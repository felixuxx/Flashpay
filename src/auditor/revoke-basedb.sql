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
exchange-0001	2021-01-08 20:46:54.2683+01	grothoff	{}	{}
exchange-0002	2021-01-08 20:46:54.37423+01	grothoff	{}	{}
merchant-0001	2021-01-08 20:46:54.585124+01	grothoff	{}	{}
auditor-0001	2021-01-08 20:46:54.716543+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-08 20:47:02.426456+01	f	48a9a853-ed41-4d2d-8a16-07cfb7b55831	11	1
2	TESTKUDOS:8	GDCTSQ3HXTBD2CA9KNJFBSR6SB8TN7WAZ0NTFTW0WCEFWQDTBHV0	2021-01-08 20:47:18.654392+01	f	88aa8bc7-bd00-4fe1-9710-a00a7c3a0b32	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
6d2a3704-a4cc-4d16-b58c-28c4b617d10e	TESTKUDOS:8	t	t	f	GDCTSQ3HXTBD2CA9KNJFBSR6SB8TN7WAZ0NTFTW0WCEFWQDTBHV0	2	11
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
1	1	353	\\x9ce8deab6cd44f3f6edc2d31398108f1a5a06ae6222a343b8b53c05458a08039ba9dafe1feadfb3e6ce1cdb576b2c4a57c6efab4a8170354c39d740cf7a5b701
2	1	336	\\x2df80f2a701b67addeedef15267e347a62f41a60cb5f290e549eb62a4e99d91e5185542033ec668b19f910b76b985c40b97f73b3147f08f30df9354ed1a54f04
3	1	275	\\x774a824597cea5c924bd7de93014ec6a33bf7def8d040b16c5cd285d0e9850abc23d0c98066812fe05d4ede502016879097b509dd57f34b0d804eb3c41cb6d0c
4	1	198	\\xd559f4a3c979886ec90ee6464176068fe1da1eedd616a28755d05e212033d853bb79f9f2a107df485f44d34b8c2d47eef66d091af973337ffcfff4f3f51ba905
5	1	68	\\x497dd666dd9cb27c6a4215c1520496444a20c13c094a6c6a2ba0bcd113aad062979c1959db6b8beb25cff1427e9da1aefce34c142017976f66ceca7c37fe3b0e
6	1	255	\\x4e08cdcd203835e667eb6cb2d80bb1def627171192f5bf8c03cf87e0f254c9a8f5846b49752a0f60a1a3270fbc023b3a53f160a28ee8a7a6898aaf57fd458a0d
7	1	196	\\x34083f0a35d1b71e9218a12da98263e0faecca098aac037d68f7c49641dbaf7fa5a5dee9d5be6e7b1a9570edef261f82db592e241d0b9a9a16baf44480a81d09
9	1	153	\\xa423d6e3e79d684d45db033be69aab6efa3029c0c9d7cf0cb28cc84ae406ef0cf29aa15f110c748efeb931a07fa0ac3956802a410094d4f36c2eec3b5851330a
8	1	35	\\x91ad7cc1a76204508a0704698172fe7c1de01611d49e551afa841cddeab8e9f55237473e1c24e7b3b0fd95df51d254f7e5334c5a5d7d37a2cf11518868fa3606
10	1	256	\\xf308dd48fea013f9a48bde7e806ae336bf0e36ef1119bbcdc5e60143a0f43cc1f35f86d1b3f9be05a410e5e5307b4bf9c09307fc1a9a9ceff0331e8acb94260e
11	1	144	\\x3935dc6684ff140762bd1aa695b701ef594c74eef0669772ff6897aa52bceced2b12e1849fefcc3bce1783a8e4512dfa8e5f522844ccde0babe4d07e07e37400
12	1	67	\\x716bf9e73444a6b5290d7c70af8a03490bb1ad52e7c7f53781f9b59b7803c0c1359f685eccd828de2a060b1644664b5a74a6f2bfd2388ddf1eb8132b74772f00
13	1	184	\\xc8cb15af90fee2b10552482d1a7eb66a6005c4e5d29e77c918375fbe4f46e0bbdf1adcc0eb00e66843f2901f2681e5a123f38f8e98f65f10e41c4ad4f4a3c300
15	1	2	\\x2362659c01163d34873ea210b38da126c20258f5a222d075b7c2cab2a74d3ef8bc3f005fdeb9d37c063c25984446d039c53c44fe89c97f55938d12bb4d1b5b0b
14	1	342	\\x9ffac376e2ef0c08208382a0e9164ce3dfd31161e1372826b9cc1899f5f32d4eb17530d4e5ce67f3758ac62db61cb5d07292559827edd5fca19510de40c71b01
16	1	394	\\xccb99302aa225a47d1b6f8e600eb9124fb86e4673d6b515a244e5e626c39a08d38c4a68b08c6ca9ff0f43fc274ba17b6fc488b5551ac68bf122f8b585576d501
17	1	98	\\xc5ca3410cb5be0ff32cb739eed05fabed08d009a525b7e48c2eeeac967923c51f8a76e5fa1e03f1dbc7fe101af70b7e01f18f6591bbad655ec5ffb4aede9ef0b
18	1	176	\\xab0e1f0fd5bea1ede01511c0a8d00147e0dfbedc2d64f39d86a3160fa9d54c975aa8e067a165e9ddc13e5651ecb6354ce963f1674d8dd082e2322b6bde9a430b
19	1	392	\\xf5fb32b5a6a1ecd44005c8e87eef955cddce6cc14e8ed4633c8354d1638b312410626503ac9c55d10ec6aba2993a583225d4b714365b0f3fc991e4cb6bd06701
20	1	24	\\xe369c928b32fa565aabec11892b77840e163461c77d2eb83aad3b961335efa1487221d0f8e07297ef49a7dd2181c708a1475b708b3cb10d0de9b434802ec5f08
21	1	79	\\xf8057034da551ae222b659bdd2676d3e0f2a6b859ffb6ea78ace77fd508c08168ea2ce97e0eed24f4033747e14bceb9d51246b1a0710712adbe747096f186105
22	1	179	\\x631c3eaa4cc6b5847497248566d4260612a9dc2023d995dd584adf89bd23a732cf5af5e2eb71dadf08a099345c0d6d87752d80c6542f77f1f82891ef03c7130e
23	1	286	\\x6da40a8e3eae93807290180cd53793288ef590ba7e007f110f07dfc76d6262433d24eec37bb46d2c9d4cac7a7cbe0ca9406ffefe91ef395b352a67d90b4efb05
24	1	358	\\x4c2d106ad5022606337a360c2d9ad01ac3b93f0f66f54ce35a180c413074f75b69d0afbef0b9838438400230875710ed95c9f1a59ad4df3e716313839bae390c
26	1	100	\\xd7ec23d39a69522d34cf0cea64af82e4bbe7955c68e58f13f1702183d02852972d0c8188779885e86bf9ccb81714dd52d2f7366486e565b7b0b3b2e77b549108
25	1	156	\\x5d917167e52e29643e8b6a47477ff9b94f6d77ddc3d620cd79c05d7af66839fd4462b206edeff989e3e84c944be4f2ceaf53b5dd20e7d4a54668cd38ef61e10f
27	1	170	\\x3b93019a669d4656da69b1f87a349da60d112769111c6533751d1c974457582be0ce1ad5eff580e941702ef87c6e0ccf4d770ae591f46bc9c2204d87457ab403
28	1	52	\\xa3596cf9e6d5825a1d73b3d17ab65b213778e00231fb35d92cfbca196660f5c0c755e0faa7f8f7531987fe76be9eca6671c9e2acb05c44e2e5a4acbd380a6b0b
29	1	72	\\x488cd69418b770f38db9d2dd225ac32c5882def121920cc817982a4dd44274bfaf3188f9c0ca40c344e0115c2f7a7f695a4b1fb88d7262b9c1ff9518f345ac05
30	1	203	\\xf399e460a95fe07fd59ca3314213b09d26ece1e882777a2313918e81e83f4108b421a8ac7a8ea076e13ca57f9e348603a9ee67323c83260e0f1b0483529f5709
31	1	284	\\x2f18bf71e1b3c51f954dd141ce85afa0129152a08d390a62f88700a96d0cc921e331e445afddd3224bd440cc1dacbdd9ae70bae7a27be28d98996ab9f129290e
32	1	364	\\xe95afa0db2fee39c594f07ea87ca965231554569ef3968a6800959dc92503cc04459fd982db8d2bd9f5819780c2589837723f9dd7d9ec25a137c4a002acf290f
33	1	8	\\x424ddb118d4eb0abaf1e56313967c377ccb1b0bab2d7da6d5167afe051b1271bddee68f54dcef5f8c9c1562c4230672ce1e273b12029034a8a916bcd57dac408
34	1	383	\\x210accf2373cb6441d4bfcb812d4b0be8875a842ee8c153d6d6220fdb2c4db47a36d74131a92e9d38dde1333746e6f7d2b6743650a059d19b22b91293dfa6a05
35	1	413	\\xa67588613dbe3596b3b67604442e33f5bea38fc2198bf77cde5491158475d82398b352e70d5fc762b9fa3cbce9d8643a48ddf470b76084337c5cb323f2bbda09
36	1	334	\\x1b6703cff3e14f3e003f6202f13bec377e23c10f23521dc0f31e5770b5805f4ba444f8c048e1d3600b5ce8f65e85dc0cb7ee025a73470a5436956fe5aa366e04
37	1	88	\\x4d88762713711c07426da02e12b5962a4548cf63f525883c331734728c551238ad4ebed6ca9f206ba08fac61a5793a824c611338fe194cd82ef0b581a6b40409
38	1	345	\\xb4bcbf99770bb5553eaff6dee2c9461ce87e045e172446092c2a6af69e5af7bd020ebfce5f1acf807c3085cf3d176479ce9f36aeb28484c0afe72cac9b78170b
39	1	62	\\x106d33364277b2a090fcf445b0319f85ec8b39d8707f8a7dc20bf45127c9846425c51fb25a91bee86253c0d7b5b6b93b4b333066ff927c2964f6e0e450a29004
40	1	294	\\x47d14820364ff7241ffa04fcc57e7e9cf8c845a61103c96bfb2b145ccb55f86b189a2f662369bd38f8ba7199c620993b4858f1c635e2ed6ad29a2498e4135301
41	1	43	\\x44fcde90760e70587ba97374abcc30af6f1d1b962b09c3b5fc7217a6549161ff0fbc5b18f505314c028d88435e3a760d576c41d84d1e34f5b94541939e1acc0b
42	1	40	\\x649bd2c0ee63ac83fff775344e897ab96cc51f6433da8cac9835904b9151914af9a5db4ecc7bcb1ee45d30348b651ae2fba069e821206f8af339c94e2c64aa0a
43	1	299	\\x4a0b7d120b7b53a5e20c01076c7366cd7cee1c7327456d6973922069c01d3b6f06b07d4059b680b60ffc9a6cdd13a715de21940199f4a19246a1c29da4d85b02
44	1	420	\\xb0c8f4f34047c44e8b159f4e320bcef447a44b419ffa4ab13bc74e2f5972c1648ad815b0133a558c8ed10fcae9b0533b3ce0d8fc4dded56ab05d07bf06c73d0b
45	1	221	\\x4bde2b04af7b575603835e6dbf2dba72fd80690a67fc594f5420e518793d6045ab8cfae53b830b07cbc07be337181e21ba2ac4219ab20978c11a367ee013730a
46	1	163	\\x710c1eee864f9bbd5b35bfd71b73a18a4d4549ca0eb6db34151fead3a5203aac079afff3c0dbe03484c07541db3ee82438e025d59d1bfaf007312f10fcba5d0c
47	1	354	\\xdf7f0a95849d35033580a7d31162cf1b9927d39f8629f6be684c392d79c39d735e88014fc0e43c5f4be5e1f26b88c29930c3013fb24faf4ec99a0195f195a30b
48	1	243	\\x1b4cafc5b053c1b007342362a7b75e9b570d8d2bee61342dd7173ee12ac0cf1708e59a5a0f70e7de06f286a47a107e1bfa64405d348022e320125366d7778406
49	1	45	\\xcd30fc05e2474c2b4705956f70ca964db020a7cfdf70f070b36c04f59f9de68459a48979b93637a0f4e0ea9c4a7d84c55a05bba1e13d1a107b39d25d51371202
50	1	314	\\x8a325402f7975e8246d9ee35b7ec96e8f981cfd72cdf45f7d61c074866f0afd7e5e20628480cd2298403f73477cf815df2a74ad0b73cb8ec95cb2ccea553b80d
51	1	233	\\xbe884b910ed3be637b6a72d0a8de801e5ef28687cd1161e6d38320a95364c0b7a61c589fad6a654f0f44c3978024044829bad18df65e5675c7c70412906f3807
52	1	25	\\x216d84240f71e7a7a98fb1fc09bdfc01b48f58f5858396401f2caea2e8ec308f0af4d8e978520793a699c570c0e3e1b960dde69f78c4860fb94757f4125c4d00
53	1	333	\\xfaa3429c956e9c520daefdc958d096fd96968cef3903a9427126bb79c8634f44df51c0b905cf5a3f6c2e5073a7de14d8aa319c913cc527ed35f3b3f267a24807
55	1	182	\\x0a9cf49df07900b6b509fa8eb0c1fcc205f6671987af692c1688eb2b5373a06d46d7e0c0643767d24171f1c11fc6f8b4eef2bb17456fd3fa04672cbcbe797d09
54	1	174	\\x518fcc904520e29d9b68d73b853a7d3a02e288de71f0e22e91edbed570ca1b92a89b3832e95067d8c99b9826b1a52b1d4dbf3ed413be1ca155a698d9ba0e2e0a
56	1	288	\\xad60bbed8e2a7fd6d132ab54f8ca3770451de7939de786e099de43ab0840c39eb2948bb781e03715083a27f59ca5f580335f76e4bf7aa9383e33652ca997f704
57	1	206	\\x2fb3db7c14858bb412d3d2466222795d2f3d046f6aba81a1823fc0e41e7355bd2db6fb9da96a667fee3f8d980301f93b54d4dd79fce6c80922309aad78e94708
58	1	402	\\xcd75af93ed66297225031d13d5ce8a26aeb12b1cbaa12bce521382cc2538580e39239bcfe667fb0c129976ccb399891f72a8436ac680c16b2ad54355609d540e
59	1	143	\\x43c4221897e890776d9303137f4bd5a21078a339b5e8c6a18392d1819a05ac5a091a2125849bca0777f4af702c311c3a1b0f89f298f23920a964f24315c37a05
60	1	329	\\x579c3a40c8b4ed6dd460ba289b593484eeb87fc51c0c46dfe6427a343c7b387874d758218b4580379ca95765637df4ab9983666b85938ad0da58f394d87c1a0e
61	1	171	\\xb80ef5cd39e626b06dc0332e48e38222fa25a7304a470469f98b329126da46571399c29815f46d23a9643d0247ca8440543fcf6192e14d3c4495da179d8a0e00
62	1	58	\\x574629c0e14edf6cc7f299a13318a61a3e2961053561e5fb4c752196b5669908daae1f2223b9a979fb3b71738f583c158cea6fe1aa000cefe94252c95f318403
63	1	272	\\x4b0a7fe86fb2b00a1d5462206ca82a036b4d407cb3f7239cf800964df7745b06c4b358a37a12dd131e3e50c55f328b495fac92751e982777987e6b22b7216d02
64	1	337	\\x1709987840ba3f2fb767c68c4ccbc633f0f4ef27b1bd140d15ed6340f6ef4ba9e3261d5d103b7119dfe4cfb5c1a1c88236083b175802f570fd9b8b1d2ce0a001
65	1	230	\\x71ad3287c719dcf8a7395c6fba81c0de5e16e6726a6c08cc2f332dbcd097d4d86f9d686af0292142f18b74f550aa7211537c364ec10c36ee8a90e4bb8dc7f508
66	1	64	\\x984704e8d9e2385dfa2211c685545bb07a1b3821716178e1f1a2fe8e81867d8ebbf26fe0dc6dcf86e72d9fdeb1d87992aad75e00b2fc33b4081d37e2ceb82c07
74	1	301	\\xa1dc43ee2fe19b707f794797cff46a74469c386640bea43cd75b5b56fef05b13035c65193876bc079523dce90ca9c9de838c54307995c23c6cdc56d25ce02e01
86	1	114	\\x5bc1ee2e4dfaf80b05b1cba79c2dae65041f3a5d5f3f74231b2e28bd253acdc03f15061eeb01c7f4f524d219833ac60fd5940f2ac5d0a6d091b3e5eba4a64007
95	1	207	\\x8180dba4b5cd0ad8eaeb8422192bff98137418d121afde02410c7841a64d28f8e880adb9fb64674674319935ff20766fcfddc6530dd3b545fe42194ac7f58907
103	1	217	\\xa96326db990ec56e3a109bf4c549f78c3aefb46bdb7470fc0e996176fe96cb9a78889a3a0502cf90a73b6af69fe61a035725d0906b18171e6f92abaebd95ef0c
115	1	399	\\x967b150ba4fa39d462fd0bc5cdaa489587544b64e2ffc4c0237d48911f005f5bf95e75deb7dee7f659e843871cc4ac5b34869a672269fabf3ee034df0e98b200
124	1	382	\\x1fe1902ebdc1728bd70aee1573c0cb4534a40cfc1eff61ceca09961b14b4753ae26391432ee7869f9410d2196ffc9fe11ff9008ed66cae53525bc3aca4a36203
133	1	97	\\x81208cf05fe1e77f163a5894a0964110e3f6187bb407712982aa4176c7ab9b9abccf53d73bc7acf630805e9dd097ad5a9c4cfbc7d1a3879e372cf37401adcb01
137	1	219	\\xba9383fe0f410d31a61a0753cbef1ce8c5e03ffa223f165c7ad9077118d3bc02c7a65b8285d75922c0f0fa0bab826266ccd7503790458ad06c534abd2b73fc0a
186	1	93	\\x43d17d12b9677a12f1168c34abf5507a91ce65a7090b08682434f2da3c641718b989442288f0d01455c29b84fb20ebf05a2179c44cacdc8a00d8137a39053606
222	1	49	\\x53601bb169d86e0b5e39d1371e3c52c2df751be74222b07f1be515b836af0610a667e766bbe2bfcc327eb8b007a4687699a7bc24dbe6f340b4952dc55bbf2e0c
250	1	133	\\x7e347ff7c45bfb49632765ff7812a7a6a03f6e2d26ead2e3f3616f33696f44249f7982973c796f088056e62c48f17aaba6b2aeb842c8afea9063af47455aff0e
281	1	309	\\xc1ab199f256a6a2be6836b22c7387ef30cfef82329da54b6a5490b3339d731f19a09bae9267eb240915fb387cd2c27816aa30ea453928beb6b4af0aa6ac02b0a
345	1	406	\\x2d93a40d8a084bb05fb11ba90199b3885e38127db5ba44547e3e867510daa80a328523108b11e83ddf4885c3d2f04af2491a90cb702eff13649fee0f03f99e04
390	1	352	\\xdd71d2663165c463056894f4ec8424199e2fec2006aa5abd6520f8b66c15015c6887d5b699dd70dc3cb4995c4c174ed4867df3faa2537def49dcdbcb043cf901
67	1	178	\\xb362f3ff8f7c2d379352ef76b3d33b7182f71e9cb72d47b6f20c704c08312c871c5fa656e1fd2f2e87d5ccda1d6be93a4d34fee15e1834a34aaaf3a2812bbf04
78	1	140	\\x91a823aa13b2a9e2f87d9deee2480499ea90e72573d0709d2b9b0abc2e4f6b385334ecc645d04babd003710676b1fbb05afe0181bb0d15cc6a7b34415cb64b03
91	1	375	\\xa855c5a9df1d85a1fe9a21dda43b3ba7398801532f6ccd81ddf2c04f111f259d9b9a196dc84794dc99bb8457c15c5cd392c99595915b48da92b9f8523abcbe01
98	1	276	\\x755ed5fce84ef858b9ecc2e7ed8a5a58c866bfae211946ffe15f3e549662d4415df70588246af906ebb8fae6c2f266cd208098184c012070134801e6577c5007
107	1	332	\\x44011c85680454b7f34dc0bc0f185ef8a7b3e0f76d62be724b6bc2ed5df0cf42097901059f1ab51402c10ec2b13c0ddae7e2392ad7f9c574daca68acac819e03
117	1	263	\\x2318066b3860368b98c26ba8d630db65f051fbbdc55c9eecd467102347260f9f3e033f904f126ba94f9fd54ab79164b6b1743c8ed76b2b6771e3dfe6f6a4ed01
125	1	186	\\xdf3231fe9267f2b77966dbc034819ebebaeabc3154ab2b09333a5931cb3525bd5f5d3f2a76156bb9a7b67f4331fccefbd59e4d3d845aba678a155af2326ecd06
132	1	410	\\xd2481caa379094427f023d4a98ffc602abd4a8292800e3a241d8e04bc5a71494f7da951cac5b34138473e13ca77af00895dac2dea396d4adddb8aa9d5ee4dc0e
143	1	21	\\xccb2f0965143398c54f5ec55b52f6588dab4b21cf5256eae9ce8ee72d91a49082f8d987153db67968eb6a80ab146b6def4a814cfcda3aba1a811efb2f304a309
182	1	368	\\x180b668aeb730fc8012d4f458e250f1a1028135971df26e9293ffad76ea0e3569468310b668e4c3a40fd22334fd7dedba8eccc120999a3767480aa442335f208
213	1	238	\\xd770bd0b1964f9c0faa6ba17f25c1db21a6f49ecb131dad92823aea3f791ed73f70dce313dbb32e8aadf351da491ec4f4f5449d67dd546e7095556f8f1fc4f07
243	1	192	\\x69e44c05fea4ecff41defe1357d780a8d1385abbc9d801edbcff0950c08ba9ed157dc68758498cefb3b151074686685e6d17cc913ce5d37fef6050ac62bff303
277	1	201	\\x9c0b70f2c9b775052fbb9ba35bb6fee48b5045d5dd88ecc44728ff5f1f3f8da9e84f9e977c368ef952bd97aeeec7aca23d470670848b9b8d0c75f0a322a52204
359	1	149	\\x959a04a34c80cca61fe731ca5fa58247764308419ddfd79e97748e52e1d0d27a8c233fa732708142f686e893557dd0d0a14a588b6db54b9b7e91ca378b256e0d
399	1	229	\\xd290127a2488baa5759b65bfa32936033eeee0ffa09194858db569e8fd1039dfdfaf07acf472efe64a1946d98b5b10bd747666225d50c3c0708f059fb3672f07
71	1	38	\\xf0b81844c4ce20d8f8edd0b1fb355e4336373dae35857d4a31acdcbfbc9ab65f47b57fe50249ae876d8b7ab1b1a7ac96f581545ab52650eec1b9604ae812c303
80	1	19	\\x26a6459f1091624798ca8418977e96e8074aea2193704932ed64922745b305ed28a4e64d2a01dd06c9b7cbfb9de70929c73209c83ccb66090ad4aba6caa9dd0c
90	1	183	\\x52c7e834ea9dfb49a4de231d5ac9004c339c20dafafd9e627140585db16d9c58ac438184c3231399fa6277513118d8d42924e4ec3a7987ece07ab429a4432c0c
99	1	236	\\xd7fcfc9710faf4dda8c937192c6934332cf059388e7c00245a6e41b36408f3ce8f0f68b78eeaf7ab72c59c413ef952eb9fb6eb604d121ae077c849a01d21540e
109	1	151	\\xb665d1d5fa2555d51cf54990fb9630cae9e16bba0f864da6bebb4bc379264b02fe46bd98dfedfef56084b8a9926779a843260f3590eaa4c5c944e65d071d2406
116	1	137	\\xd6757e8e9d7226bb06b534adab6bac2f6b05f29559d7ec79fa930e9d7db756318cb3cb005c25ace5ab2e1a5437374ad906c64a332f18949ac651ded9fdebb30e
135	1	160	\\xb7b91d3f746481f46ff237934324ec153762f9d4d8b0aadf342a90561ff0e6e048b2e2d0e9cfe3ba70b2e64b04a94ffba0b0f32ac0f6b553ad2fa1af2da6af03
168	1	169	\\xefe3309f3163656ea76c6ce6bf6cecac2742db883ad2f7351b86f0043df3a91993e16d4772baf847dbe343e50be66aac901410138ddd6b3851d5b449212bd20c
193	1	361	\\x34e78979622dda1f57b0e59d75c151571ebbbd0fc8c0a4399eb04d4105cb19711ef455c9e52a4f40aea79f50ac90cb88e6951efbd61afca2f95cb45ee010bc0e
223	1	388	\\xba21b12a47d34144cd7bbb3763b2a4b0f05382dc9b4d06814aca90eea0747d377f8718a498c2c84c92f43ba460d855891f9a5d1bb02f10c07822beda6dea2803
249	1	277	\\x72b7cb0fbf02041d7842a6f59a9ace467859cdf0dc9ff938e50b5d190f0a69429a053ec57ae366cae61f9663d2efd3243bf6e80bfe4315a0c1295d3cfe886e0a
282	1	213	\\xa4c4da95e8b7de99d876bf383e32711497e8a62a6ddbe47cc5cb9689139a099c251c58abbc18475804437e9db14a95a0c0f90fdedf16b7c055222e50fe3b7803
376	1	310	\\xe7455b29f8134e1771580c2587ecfa4977901275c02d1445c73229cf39b55a7b323584978f02bbcee9d2a738a2d56b32bec204cda18ac104f2052a73f1084f02
388	1	296	\\x1c6b4a65f89b2ab154f5da809b59a0779f91695ac2cae7380aba333df44bb8c390f76b1578b73233eb3e61caac8694dae5fd68efbe35ba01d58d19265fcdd10a
401	1	127	\\x7e5e2a5c384e5ed05d40b17483d8058de5354586ba1b32fb76ac9f2cf1762b0eb30db2a1c1a9c213844b8a44187761bf2e890c91f7a8029ca1f21ce6ea2f410a
72	1	338	\\x0020649af2aa43630d8fa5d76a9f526d385c97b8e2ad4584e2ceeac6563035b222d3fd104153ec4152bed34b76f753125ba43f1eae6c2eed1c8831f8045f5e04
76	1	161	\\x7625bb1732c6e9503dc496e46c08a09d2ee4f55a63da0bd4c220eee1ade666a182eda90f8f669bfbfae3a7f483399ba477fe1ed93b9ccf63afa82f8ff9b8830d
84	1	225	\\x0cead10df04671211faba0cdb7729d2ad26bc0194763d8dc2afdac80960f62bd18cbe17754eadaa32861a2c915c9b38c3c6a885db769559caaf2c54139312605
94	1	42	\\x658bbf5a6dd12ca7d5c8943cabd6a43c206a3ff19a6fb55de499cd67a2c79860994c33332f1c5b6a212048a035f0c86f89c1134f7e5012640e97615565b33c09
102	1	362	\\x64b130c4a5e2f0f95b58d31f6f13155d619e3b1829a76ee13bbf219aa563be36f275a2538b5ef30d2c6640a2b35369ea05dc0c6628960f9f9a128ac5e115080f
113	1	108	\\xea1be57221790fac6bff40e628cfcfe462a982cc345c72662a0ab3b9b093110fad5c4d55f975e26fb87d86c368aa950e17a9fbd2840ef3f7cd3528694505b200
122	1	15	\\xa482b73ac7f261205144c9a3d3e7f49eafa13c6800e666082c6fc9022213148dc71e4fb6f0dfa8529455eae991ef3de7d494ab4de7f3351fb47759692cae030a
130	1	30	\\x84614d64074897fcfd5e5c3b65e7a1d21b191bd9e826437a5ad5cb2b2992f27b5b513f84f8617449c450a63d7336332ce073e2d8eef8cb04fee60a84d004a405
140	1	124	\\x1d0735327de216dbff868ace953b9502789d8e5b5421ef7dc5e60cfae04f8278ffee9c49d0c42778a2c932cc1b6c517cadc3090079a53e01a84cbb3d748bc202
175	1	81	\\x49cc1bd0865686b8e74dd4e755cd5f463c40b7f0f5fc4efd7af5e17e3f4b61cd56155bcf2f1c8e79608b62dc3645e4c8f3927bbc175c72f52a9db76b0c5fbf0c
207	1	391	\\x9e3b5bb6106a3092bda0bc99b0deb122815a2bf6c6eea345825e6d6edf7e9bc51ef8aa0e6dd3dd840d00d3bfdbebee4a56af292254b1c73da4e1ebb214bb5306
232	1	63	\\x0b59f73c70ab91ad8f2edebc21acb97211db0c7feda5e0ca04d9a2adcb83698f0b10d966f69971056911ad6d2801af8ebf3ba4ef749b8296c72d1fe16166af0f
253	1	298	\\x1562b71fb529587816c47c59c8c7cb765549c56351cb52365368426511cb544c3b02bbd96cfbdc87e7e8b9276d37bdf9f0b5f28b713633c9012c5512249f2000
291	1	311	\\x7b3616851c4a81975d550abc0def3a0cbf1f59e7d2a3cf83b76265917c2eb6cb8b02b56de21791e215f2526beb9fd68b1886dae646cc1f8de6b477bacf458906
312	1	327	\\xa9983edb38e208fc9e508e8730428b3765bfddcac2aec89b2b51ba22e70b44ac94c154997c03a32da3c6e37b6fe17d6cea25117d5e138e6446a976448b437202
356	1	37	\\xc03b9c89a0e003299759dc9dff71143fcd24a7fc935752494306b28c743a2102dcedbfea6e761af6e919ed8cda2c6509c8d5e66a306266be15c861b4dfca0d0b
419	1	103	\\x8f5be736fe0acdd6916c985755288c93ea800a100a81a3a4a81cb7e250bc30692c1f4eb50d8b8a2d69b015c1f8946322c336f9297a5e201f9ee66cc4842e4804
73	1	312	\\x5a65e54d10176ad5b4fb2a24176aaab2e7984ddb177d1afd1910acd2e6a261adb7dd7e634f4c4956f32c6c1a2fd60b05875840939570110192b7e28849cda40f
77	1	92	\\xdbf02d10e1c8a2ff83c55dd01a4b4da7b4bd83531d9e6cec30fe824f0fb7a4e851a3cd803e576645a89556d798be233180fdbf3762ba6cc6d3bad6d6bdd76900
89	1	28	\\x7b1878e58d6fa3c905bb75b702d98de3c69ea8e932115cb72cd551245f4c16b51e9bf2c3ecb49bccde8df1590dc4c9321beb50b369e69cc9231848d8149f030f
97	1	247	\\xf0dcbe61cd01466b43bce4c0bb97108e0894ecf5c26475a7d094a0c1a8b20fc9441ef4aa22e3175ce2fab438ad877f109c875531dbc89689549be9330214650c
105	1	303	\\xfced87a3ec52dc83aa9048a92a772575d39d5a01683dca98727198a60320f2bab0061de66dd3071e0d2fbac47bf8d9a46feaad991e3dec3224ef8dba0ccf3603
114	1	367	\\x5d1bfbf940a00f5a4870892e25b49e71d4bdeca7cd13d25eccdc9736136cb0104066c11498ce7727ea946f65e01be56f3686c8cd41822e9cc45c162bec96360f
123	1	261	\\xac98eab8ee78721ab7454bc64c2944410cf97fa4ee69e764173f9050da1a238ccfde15c214744b835678cb51002c7739c2811087ed3d32f165a01265505b800e
131	1	90	\\xc9726ed938c4003081f46005cc158de60669f3320152a9e9a33b2bd3e12d730b1b14d754278c33efa077d60c843806065e50714199f7e710da5e17c59650c80f
136	1	172	\\x0d7f76ade45bd072f307c14baa863b7436e765dd33c6e15d3a51756cec7ad365bf7fc3e713bfc6fbf4e0a23364c832788b0ed595b1cba191f8ed92a7291c620f
185	1	240	\\xfd7d8da1747383b4ac27dd445e822420962561802dffdc56a2308967dce41292dc4cd40e1580f60281e1aa3610e2b6d073f353bbc3338a2b0cf483a51a804b0a
218	1	250	\\xb4cff8d0b23fbe3dcd5cdaa7e4defdcc8405b5d4b66a452e236d51c97247e64cf2f3260487488f3ebeb8d96040fcce50745504839a0ace83ee56fdb6df056a0e
254	1	318	\\x6228e7075d6edfe09e774eea8328495eb393a3bcd93b60b46ca625c97bea0441ea1cebba2444ca0dbb22785b75743ffc5aca23b6faee09165c45c562a021b706
280	1	109	\\xb841e5801ae81e045a68979d73898a8017eb2ddf295797967c9dd8b4e7a50e2a5d968c17f69ab5419d7d2d6ccb07ac0d13b6067864426d8c84afac54b327ec03
350	1	300	\\x5d696760431ca92b7681acbbb41e4289e62a6c2a93ed503a6ebad66c044d1f5e14c452127e7af758fc751312753722c6d030d21b97593d7e5767aaafd9bfef04
403	1	193	\\xc8797eb00c616ccddfb3db235dd83ce74f1099fde2a8f0c21baea6c7876aca3f7c7c596687463cb742e208a33094941ead8775447d1df71939e83b5977472106
69	1	381	\\x47bae12ecfe97a44a42a8638f09615a0408b9cbb5f70c9a5fee91090329741ee1432a0bf0cd9fa6337f4736ef0979d97f9d5d77866fe9021d7e3610d989da20b
83	1	384	\\xb2945ba764c0e9f3f2be4e8c7655859d3dca60017f870471f78af71339400f42dd600f254c448db7c9dce8cc5737ebd708b0147db405350493e60b6e2dc0d307
92	1	117	\\x7f02463c1afc4cb5390e6b35827ae2c2be5540aecbb6b52ed931f66ceebb3363f3db9ad85e20f9e5dc2a9eeb5eee72151b3d251a21e971496d4746ac95f4a403
101	1	118	\\xe5be314633e2e636b517ae41d5583d1e3c036dfdafea868b9c0a5c7da38dd923bfb6b5e9c9dd976fd78642dccc9b385f5e1b628c909ffcc97ffc180a11937b0f
108	1	325	\\x2674e71dcf6146f93512f0a1a3e9941d4e3d650830f95ffa58fac05c847bb71f8cb327b29f2864f558478b7821362beef11def8c3dd2ba8db0d5ac2afa673d05
119	1	116	\\x1436f1cc0fd40bd165579354ebc8ded30d80e75f62c1c6383abc345264af18cdb94765c6b583a3d71d629b5e277467bf40b82fa57f2f284b494b587d98d9dc04
127	1	126	\\x4d07d3beeb7cd2c9f1428ac05811586025120ea3b1b2a80d0e89bf8a40ab33179974e67c3edc2e537267112dabf147184966db6407a599e0e5e08374e024ec03
141	1	262	\\x3f7e5a3c69c069c5c1511c210bb14ec9b18f7ec57435dd12334c4baa2f51f716fb216c4b2e6addda021259f089a1e3dce2789040184334682c44110db0870104
191	1	55	\\x6f87fe82c9599003a3132cf18de3e070582bfc0e3927533c97952167437045bef247770d8a0f8d01ebeb15ba4355316f11bc04d3ef45161512e6d7e90bda510f
225	1	214	\\x2ddb3d35e088ff3afa216dec38d72028b431a1d14508d30230a7b3839e0742caa3f7e2b4a16830b24a7a65a6a2bb6a3ab2eb7cde3b6ab577b7d42f58918a4b08
242	1	307	\\xb3939512da73be64235d516314cc36d378d6f3026a4d2f68b6efa23cd3ca682337f6217f2925f027aac32d6e1c06cda5ce6e2fb78caae9e2dbef78b132969005
269	1	377	\\x639c618398348b1fc6f28d0fffe950d412e8890ae27a9b20fdff5e53e78f7bd48fc37d3747b4fe0f875586c20666dbcce58f8c0204a3b2800e7dcf6ec390b00d
310	1	57	\\xed10441d671dc2e70b2a10addc22a6e35c0ba41a87d1813b2adb1eb63d980016bf6adaa7ed7d29c36d33882441112641d7262162d758c9cfcb97cf90b65c0307
317	1	235	\\xfab2d562eb8658c75845fff0b7032d07784074a976ac48059077df9bcccf28fffc4ec60e54c3ae38606184dc0545d4130300b4e50a763acac05858147bc1ab00
372	1	150	\\xf49fdacf45478ec1e83849052e2b62e8bdc4ef1bec4d855c1b1215c653ecd526bb6881c42a006ea3d70cd0db1de95ff754a93843f12753cf6048815c89c65706
70	1	104	\\x284f3bbf1abc8da006ffbaf9052c19bbff639e05abccda1e92a27871ab77d55c6b7e225f6a164ac07b87a0c6057dbf29765e9918dbc54baa5448108963f8990b
79	1	414	\\xb86ca9f5846c2ef16fb17a963b51e554668939dd3b89193bb74199f9bc84520aef4edb86811b67c94a8608970f0351e26f95ea0a711e06fd18a6947b59bbe903
85	1	200	\\x426bcb9bec6882f558826bb6b3d54f8ad3adab31d6a4f0d81917c5c7a062daa24762df12f9b109493701258b90254047eae5c39db5da5a5b06cd87c7daa1fd0a
93	1	264	\\xcf1b02916fed72332079792efd438eeac45068124757c838c617c83555f0e6f6d57aa1be79491156a7af3f5fb8b3f1d0128f697fba884ee43028a25705373605
106	1	73	\\xe800060f9ada2ab96f51446597e1c150176c806ae51af662095695a5c9113231715e19407ba38585f6f50f34c085b3a3a7c84ad492ceb6af864cc6b0e6fd9408
110	1	224	\\xe7331686969fa28352edf1dea6c5424796090e4cdfeb20e0d3d25fab48b0dbaa37314e171f57214c41470342ebbc91ab7f590a12b35707ef4a39720437fe1103
118	1	115	\\xc1b58e405ecd2ba108caded374ed62d534d10a600fc89083ceaa09ef164126adb8eab6feb5d6fac616679c81e6d743b1eb76f61a8c7436ee8d9612f8e01b5c06
126	1	380	\\x9aa5293965aa63f0b616f14445db4af19a4f27ed2ee6f7d468817e50ba3dee189bc1c761f018c84a12b37a6a0e8d7ee68894cb564156a240f3aeaa42eb03890e
134	1	424	\\x2877989b9c81f3ce3c9e1583fdb30b5649d6c3dc0ee94dc048d48233a66409d7ef595da4ab3ab309e6be729a15d714a54c31051aafd622a2694615a07dadb007
142	1	259	\\x9ade93092539ba3ff6abfd7e8cde2d65e354066ffcfbe15f2dd95878d5a7a328d83009bfb0b35e19be53a1b5cd1d9d5c900e983f59c495f2bd8688efcbcd850e
176	1	162	\\x9f9271d4507643529a0b4feab2d37aaeaa43a99b069060af7f946dfffbb2e6420d07d71f541ca6518152d374c9e0a330524d48263936ee39e66b159024916a01
205	1	220	\\xcc8be5b2dff789ee85a12036a316a0dbbe3698a689b33ae85f5891a51928b8d81b46c49fdfcd47e7ff32d92880dab634236010a62283388942f52390731b3e0a
234	1	227	\\xe228b11b37456c09032cf18f28ff4172c8bf37789a464eb12644ad94fda00fe8f8e360515431caec4795e995170f5cc21b4db31f7df4fb2ece2d85af53753f06
265	1	166	\\xca33097100d78f25eab95c9bbe4c8ae93c7ace8cdce6d1f91d3edcacd22a843364e545ae13e9b13f9350fe21ed9b0d0492d2f6fda6996f7994c88c83590d2106
295	1	53	\\xd80e25ba7489e2197ac535fea62522dcddc1a91cfd1ecad3823949fac42c2c1c0053bc2605301cad816fbf70deb70d0c5021b4bb956b9d0f5a844a77dbcac50d
319	1	398	\\x05b35e61163877be71d0df7dc72bfe789f3537b8aa7978b5ba839da4769913618437a6a72ed470d11f989a07bc5313f5d542fea69f107f05052f778bbaa74003
351	1	20	\\x465e613df3fe8eea339c2b6d1b5244870c08b6c2e3fc89d4de6733e0d7b83dcf85d9ce2e0f9e4044ff431ff2a8cc0bb0f0debe67b70ce2f2313ed0d26a910c04
405	1	139	\\xe074d830b4757f037fa24112be116850d21ed566e17c60123d6393ab85f82ca51d88f0882f0e24d61818bc46dafdd93edb4677b32a41c153eed173d129c14900
75	1	78	\\xf1fe3620980de274384a4a3c66a11571a65fc1887d8ed145be42d47ea7d203070b5d15add7d7dec0622b84c72d54c52b823781c1b499208eb92b688147d32e09
82	1	6	\\xb103e6b199815f7288d60a794d0ee400e43ce182469babd1d258a743ec53da79dbb1a0b75a32e3c5a1efea01838e1c3a2311956f678850653416fbcb19ce6f0e
88	1	295	\\xcfba450b71d44cebc624aff14ce89aced38125ff6580953ed19b943f399b7bdf06efe50ba100b2e15a40772d9815f69ad589836b4f6eed2d05a299a0e2b5d506
100	1	273	\\x77b39e1144732c06613f8701840f1a99d319686c258e9d1273a0cdd335d4483632337744987dc3c2f43dd7b03f78bb8ad7ea0098f580924a9c2648227a553407
112	1	282	\\x7ca24e76acd4efe3e44b9ecf99fb9934b7656844b1e117597e94393cb8aa6c035f8894dc5c1cb1d3c5fc0b89ceac2d67645a613820d3c72039f92e148a38b605
121	1	17	\\xe15da436ce2141fcc769a797f0470be644df602f64d8b39308335ab2c7cfe00a012444aba4507e2d03af7c270e6aac0549807cae5b1903dc3e17e614744c9309
129	1	83	\\xcf1812a4c1ce78d47dc87776f2727697b60599ff1761a3a8bb37d6fb4c977daa5e1a1d5d9fef38b48f56fc1ebb0b32105820c739aa73653e917990f9c11d9100
138	1	27	\\x87b9f4677aa045ce62c301600b3a4790680e65a0a592925acb5e61c08f973eb46894b7e063a1ea833989b15451e7025d906d8ebade714fcad4fdf2430a79ab0e
195	1	359	\\x200ec1f6b0b8772399eb7c481cf1a46da90843c619272e4a5856080177b7a2b71c6af323aa666ef8021fec5fb4b470c7821d6981608ff8939ff8553a957dfb03
227	1	246	\\x5afbbb4657dd2418429002ce542d6e0bb9e40dacecfa2be906a044ed97cf6c3f47e30b3a4dc372a9b669f4cfe724141d547b66961d70a9704a138d5f571eb908
263	1	175	\\x47ba00df8a081fc8d3b867d43cdceac984e3351a35fc21071a326d24bffb31cb911b2a63f296390a363ac4a7a3a42a2273a4d7ab686aae9ed7374198b29cb201
290	1	129	\\x95446fac8422594eb68b0760550fcdad9cbbea532e934adae6c3e4c5c813450773c1bce484f902492ba4c04e44e3de8851831ff7a403a327c180c653fcf75407
314	1	54	\\x65776eb4edf24ef52d8ece12c01d1cabf9181796214f61f014444afed2fc5acc67355b5fe6d7cea24bf8df845af5ed4f0434bffbd7f829248754a764d204ad05
322	1	397	\\xa3b42c67ccbc779d5e9d03578ec66897887b98d5b7081f80be65f272296694f7d8407262ae961dbc5ad2abcffcc9f2cdf74ec08fe2f8d5595b7921f975dde40a
331	1	253	\\x7f0dab10555cc26d21a00b08f58a1058fa92cd3a1f2f5d8b5600a98a916c8f2010e83cac36700bf88bd8dafba88390f812c7d7146d1960254c7b07770b08fc0f
393	1	404	\\x47fe6d68381d3870df3a684a9812ccc80ba7c50889775cac84358282fc824b5fbbe1e418005da44f0c1fddee88e2826a79de6b59711cf37ec057ecb2c809cd01
407	1	191	\\xa4905fdd1a8861502290bac76182681bba29f5d292a7a7bc7495c9f648c823f4160307a05f0c73b3ea471f4f9bc58f7b50a54a4e865b4ec592f80fb653b9c10e
144	1	267	\\x85eadddd6823e85eec030fae72e02ae8ad92049484aea0bb1cc14983a0a8679cf071f1628e97e461354de226edf069342f76fc9efd2ba12e8c596a373d10be07
173	1	283	\\x0e09cfd1d784f683f96f3279e54d53d2ad28e04b7407ba34477cfbac98f71aa0cae5c9512c10ea2241e6fe355fb400a3d87911a432143b3a66c4bed8db5f8a09
215	1	269	\\x910f13935e0df54a4ee1afe52fd8f2e2a13977de41972a4ff5dc5149fc87ff49d8e75de8cf07963e6b37eb1c141a9811a605df6fd73d44086aa567f9874d0907
264	1	134	\\x87b376166d24340fd014e8cf91f8d23ef5995ec0531fe4a3c3208eceb125ec6b5a66e0308cc6554183edbd53d1f20180555de30b669ab51ce62c2e9992e6e50d
294	1	18	\\xe6509cd500e6e6129283f20ac99110bcf76917883951bacfa8d557a99554ea7c80da3b2f703463c76649ce46dfaaf90b4441069f3fe69490a456f41f2a63c908
339	1	422	\\x252373dff60d3434d00bce195040286d8cb8cf50eddb39418d5b21b22248aa2428685877ea3697165e90354c98da1a436052b07e578c7f90115ba1e79b65b40b
375	1	212	\\x743bc454de75d590bd3a78296baadd15d65611f9c7d545a0a34971fbd270a6abfb84c4a6c301783157ec094df439a44145f1eba8989e8ce264be246fd69de108
384	1	199	\\x245df8e3fd2d54a49e37af7cf9d73b4d1cd86099a500eb1844439a2ba902f4beb6d117e1927fb172569ad499e310869d4828cfde79568885ec33aed9873aa406
411	1	74	\\x003a05d033bfbd13c345b886c1356e73b0b90220f69033209043c38bb372a8e5028e597df968a9bae917a9817b5a51c7783c6f2f232ef6434a31f0efd8d6fb02
145	1	292	\\x096c473dc8664e01f500220b44098eba48ebf3687beb89f31154903dc52ab32a61c5a9d85a8d9042aadea1fb128614c8b6ffba0a684dd37dcb3bac575cd0b704
189	1	29	\\x2f322d4bc13fb99f0148a4a88c3c6cb053a23ff13237f0fcc4ac1da741ebbfc2b095d607e248f49583d524ed1e74f740b9512fbc9f1d9641c9d3066a229c2406
221	1	168	\\xe973aeffafad5e0cf1f09f4d9b15a8d46c6e4f42840640d47d7aec5b79a5c044fdae794e2c87611bcefe3c1b61df4c77c2524ad11fd7d0db42637301afbaec0c
260	1	245	\\x6efe40445b627781cf7ae6a749367e8bb4e775af153b3c85f3167e00cbb82b80d83832d0a42a0114eee0f278c987d629a859098eda22d8a0f38e6dff5261dc02
288	1	308	\\xf5df0a76b9b44af0ea1a6f03d8cceeeb03c74008e965ba80761af01e747c7350bdbe913e4156607860717dd7c6ea516d796443578a515c39a27a8bffc0064d0d
320	1	389	\\xbc19694ba098efdb02b4bc8bb0fd3cd6e147b1aed92832b77eed36766e93ce6ba13a9e4791bd34ca3299cdb273389d80285f21e3ab0baa48437fabddee8ebf08
338	1	215	\\x37dd87f2a1560e4a270d454bcfa55c23f443c82281a5a315d05f90ebfe2a8d02c7f60230deae80ffef0775fc1c8ed1125277f3587e44e5ede770a06538675208
349	1	244	\\xb1c668fef136348a53ab4910f0be3ca31e9c8f92b47edf676aa33cbf972d78e48b031bbbf1e7dce337e3866c3b2f89821ff3614ee2d2ca0fb1c307f4819dab0d
366	1	189	\\xbf66d3e710e1be541efa74d7986961feffc97ca658406750e75b7409891acf84612af0a7b9746245ada748fadda143c2d28fcd685740dc4b93f59c599430cd08
377	1	75	\\x42c633c2bcce296a157423d052a8f6ce4e65cd9abbdb1b84062a4e2dc3987d7b8b6f05749a7fee8a0fe8ea0997b9dd222af1225f1590fce858e848973050b302
386	1	147	\\xe8587e178ce081b60fb08cd9a3259da3603daf25ad348e1909368095763f5da3335b456825c2d08968c80e9ed3c6774df1005df3441746bb29222a9daa3fc100
398	1	60	\\xb4ed54fce6192cd235cd0be85168ff58c42bec576265fe02638c9ee62f7c544570094a81e09086b58f2750f7881fc9aa4910ab1964e7b0149a0ff5f1dad70901
422	1	44	\\x3f5037e637d7a9e3f7e9ed8617b5602317fc651706b54a57d04b0038c14be5e68a043efb6da5e4a0746b482fa27a8458da08297f115c9aec16da5e1681c08405
146	1	180	\\x7a35fa38e5e66ae61d47a667f3a6491148a5c35f6a309ae0d5b8894f89205559a6139b82dd06d439490a69cd2b58d8b0760df8e997cbdf65637ca905e7363506
187	1	69	\\xbc5c9c125c477500500db0d495059379f971d07eeecb2b37a4b4dea0729b8fb386e43d5bcb19a4f554d9a1e3d82c3273bcb130146ef96ddf9147ebab9f48a90c
236	1	340	\\x0726f98d15db2255055229a5d8519f2ed284a4ffedd2fcc9e496e487ee34bab99800aa6752933d3cd836e6a75110488860328e69a6fe226a7a708d529749b10b
251	1	315	\\xc581c00709702baf7c4dbfee947f7b269005553aa3af6f48d6eba1d1544f5eaaec9207c2850975c2363626c9401b767b8519695dc68847a15a0d7c3592139902
278	1	242	\\xd1ee0112d92be956a98168734ac8133a54af2a9129fbb41e9242ac216b5f596789a5deff51fc3d111c5066c1f7b266460af3b3447cd5447d673a1754e4a59c0c
325	1	131	\\xa36918a0acc7737aa3581fa21a62c01186ce84811fce34a20f9ba29edc412c60e5dc5862f853d411de2f3b35537bd674a9552318aa7b7481e8134efd0576650e
342	1	323	\\xeebd2f609c10ba7644221522ed96029785e0094a9d69aa85d0532f158e563fb2c1010e8a5f1b043218992f3cea9066d86ddb79debe2ff821a8706378b09ab605
354	1	423	\\x1085312b683d95a60e4b74ec0316b02534d19267c1ac91455530c6e8633b0d04f6b5d1c5eee5a25718add727e9fa940c7d237cae2d3385363d986f32591c0007
404	1	343	\\x3c8c05eff7ab86d336a29f5cd5e677761371cd023e192d0d415cc7de69d855e6d1c483c9abeddcb73992eb0e0f856837669e7f5152e4176e771c7475a3426b0b
416	1	344	\\xaa90e9e2a38bf8715ddd0a2f9f967c38c0e9c060905c9b92077259c18b3464e52b44ff3509c4b7b0534628ac17059a4044e605bca66c9524c29f67af9a4cc10d
147	1	46	\\xd297f1923660694aa094fc51ae3d9988725505e21f6682d7114d2c2a571de15f3cd5a3bcc5d28750a1fc4a6f8fcc08e8099b1c09f3a3553a55f58e1d06d2e70e
167	1	257	\\x915edb51ec85aa150d16e215970f4bc52d0576f1a7c2edbe7a69e977a5d08891fe3771523720b38fe4f75237da28b41dc844554e54cbb22168829f5d2379bb0e
197	1	173	\\x60228ee83a0b0a085282407b48266d23274d9e2b7ee949e32aea207b415c32829fd0f2c3131f56a8b25b56457106f54bdb45d91ab9f0bd846f2fb4a6e756c503
228	1	376	\\xaa6f5b3ae4aca31aff53ebc08b94ba5ab816440c6de2e584f49a0364f5d93bb7213448882f13960768625d88a70549a7ef27402f8586eb0293f8d2892c14bb03
252	1	1	\\xb1c80d1ff4fe19526bc80762e5d19f3e885872e822a6b8bf228ce1945dc0271cfde412992a83846f6fa59f2671fabd1aaecce07ba674ede44368240e8c72c30d
286	1	348	\\x7f02c91f3c8ffa50860f513f37291057840e69bd9c6fd1253bfcc4923ab423ebfedcff9c33de53abc191b204f1ff1418241235c6d1eb22d22562e8cbb8d12d06
357	1	304	\\x9fd610fad31ae6f1e3a13aa279f32936a747476d3a38e20552fd5b59fabfeaa49eb13ea63dcd5241fb756c36675f0a5dab91acb002e171a9c32bd1fd002c2d08
383	1	239	\\x48a3bfbb05ef608f18ff696cee517ba29341b6e783113dacc2baa4921c2305c7996017c3b02c2f4b7ed0f00591832f38dc16aadb85b455c506d91264fa21c20c
394	1	181	\\xc09946d0f1eb47190cb4b420a22b4cb4749dbb0caf4a0c55603bc847b6048d7b11c395b9b8e89d9ddaba035b38715c454a3228d3b7e5ed2d91b374853d47ac0d
417	1	372	\\x026a629aa746a2c4abd7ffb4fcf311fc80f3a0cac21112dce69e6800a67206a405901efc3469e8da502790fa260e99404a59d289bda99d0844491b49b940d70c
148	1	3	\\x231e7d027f8564a02c97a14a233ea8274e313d1b2691961bce7862743053b2d33cc3059ed04b9f5d85aeb1c38df3606dd6135f828a494f4ee9479ae3e2afc607
181	1	13	\\xe4ddd4ad4d2f8661aba8a41dc8ed837c3e9d93d0604d5f45f60d4a988b3662354ac63929e81369a2e76709dc82eb264c31ddd332f6d641a1195d91681dbd6002
211	1	281	\\x2111e290e219c257f65d5f60d178222b27d010f6f784bb13884952574edaef053a82a1119b53dd78b58aa782680aa7e0b5954d8e70d4c8e2ba6580b5ec1f8c0d
245	1	403	\\xab9ea7258c82ca6a4e40ade5e03bce9ce46e10c0323b6e92d49c4ba92ee924fc120a5fb7d4ab214cdb17fcfdc2571c4bbd8881c3ddcbdd2c8197ac90cce6cc0a
279	1	146	\\xb9dfcdba65d280b3454200bf1ceebf6e8ad4fc3ee775ab035e175e6351939c1d114545ea1fcdba126296c0af85bcfe124d0b0c393c31577e9ee74f7924127504
309	1	22	\\x40f38a4197b779acc4d451fe50110a5d769b8e260846f22c2e2b6cfc2f1bfb8b68b8424d5d2f716f298d4a1eb8b30304463c589104433f7cccf3541f66eb2e01
337	1	132	\\x7ef72ec6ff12512f8338c21abc47bc69108983435d14fc7e18876efe8bbd0ab38c119acefb8bead54a599aca15cc1a59c8c95b852fb3aac2aa28d19c1034a10b
353	1	101	\\x5a70274a7101f6241e9f3902ebb128d98eee2f9b300d7baa6b3dffa7f297958a751c4770597a6ff0c0f7dc3aaba067a8aacfe40f594c7d205638641151e2480d
368	1	135	\\x232b090c7f1e78777623cf2265100845b87487a3c12a05d4f1dcea7f5c3abd11c66531af618720bedbe4e7fd48e18326bb0fdd3b23845a1e118cd653902c1f03
397	1	82	\\x629547acaf9f4f3aee15f291b9a3a67a0a4e0f12171c1f9d7fd23f30184114a11c24a345289ededdf1ca31e89406ac211bc9dabc72156cad73a368f1fdcfc40c
414	1	11	\\x90731cd264e8e887d800ea586699d2e667fecf724903cb6f5c38044329313d9efb44cd50eeb26d743e598bcc5a48e39ac8e024c41a68a5566581978f4323740d
149	1	197	\\x230415522bd7e33a2fca0cbe52e800ef309150cdc8ddf2dd7baff39dc88d8d7ce26d786420330c118493cd01c111b9c7e3e2607a4f7f7ec5dd0f2500837a3d0f
196	1	254	\\x92831d704153f8ee4c9c307258946e89811ddfe97925c74788360cd087ec56b8f6612c5685c6ebbb64beb21537a6da5c5779b9a4e8df493a41c91b6aa4bc7702
239	1	356	\\x544724d22a6a5337e35074a5a184fb223d6f6a8adda2a93cc38da82dfcb9c7a6f39d0040936f7422009b3dbc6e3e538dce631b91cf183e5ec12435c9afe26104
267	1	291	\\xf3fd951a4e4d24766b47a10fdca418cc4ab2d7b479b9fd2358d7e195a582bd1d584f951eec6a77169d5ec036227ab6df864c6e915d6e1b3c2fe0224e031ddc05
328	1	128	\\x12f259eff01cbf63327012a26047748b617cc68b35b93c6b8047c12a155c54cd3b9fe48ed77bbc061f9de1912c0a0c7dab1842f7511a0a1dfcae302145a1c20c
424	1	71	\\xf13454c4209d3ff38bacec095548c0a177b7c11e3980af87e5778a509c0b037654d38f432577bb16f71b0ad08ae329423c338504a27584c10265236171edaf0a
150	1	86	\\x38ae81ac660e8663f92538db00c0c68ce2826dd572157bc2c94cfe8c8088acf2977db4064d308dd5f4c0164cdbc074141eb6d8531b586c1cdde950ad9ad46c03
170	1	421	\\x5a65c7afd3538c5fc4848c7a28eeee66ca296a729858d6177cbc1bf7b987fbeb752872dd1941384afa024d75aa28c25b95afe5e711167773aeb74a9658cc1203
204	1	208	\\xf605d9f40a83232e2216fe3b925929288372b3cafb9152e1d6db0858da786b0fe077fb0f0c049372b1498704c0833ff54eb7291c62bd60012f2f1d69524a6f08
240	1	188	\\x4db3784d502e365a04b8aa98f31a4a283c91b4a8262e03f3d2e18cd9405198ef66b38511dd9e2a1b3680a50c13f1eaae564759eee76023bfef1dac04c945f40c
266	1	194	\\x64942e65f0103b11df583f1f1224f61d18c03691f29478662b91696a9dace9c2a0cd40745de34679594ef211128a7ded23baaa227ccbeab1703a485a3fc71204
300	1	66	\\x4d787511e67756873e3649cd9918520acd3886911631c31204e8fa44882e7e3361528ea0a4f2c306da812f26461ec623b163991c6379d5b3c354b6d5f0a9b900
355	1	76	\\x3dd3151bb154eb9d444dd790b89c64428a1d5a319b95c3d075b1cd6422f5e9f9a2a50b39d685333074f512900ec3a7a57b40dd65550de0ac26bc57f062e9b203
418	1	31	\\xb5ea63ff390df14d7715189f316a1487ca0fd3ce0751982299f29855f1f2c3a4d0626cb53173dc997774d1ce18c7011f607a1b2f115036458876f78de73b6800
151	1	357	\\x953097742b5eebe7acc44e7aa6f31075cf07f20da558732c3e599a563d321e41ed43e89f0109b5b429bd0406817de72b11279c621fb544f62b8c0ebea848340f
171	1	80	\\xcf1027897c6f7d374ef9142c34ad195585c8628ee3b52420399842cdf070f90cc76293e1c278798e27e2294a3007fd3ca07ca61d800847c24f5fd118a404af0a
202	1	418	\\xdcbf65191f805baa815979964db435863b9d2c76c774c4ad8dc4b3071cc99ea1a74f0036d7d78f5e7452a04aaf6d996025550bfccc814093a3ffa11096b80403
226	1	47	\\xfcec59fe3307ca851bafb4566c8bf5eeda53cc33dc5ed3e546d46dbedbe87d9c3c4832cc53e8b28269efaeb7666e43858b6eb1f26d7f349e3b7de370df7e2801
258	1	48	\\xba22ca2d8752689cffc017979625d61af6792b212d344709b4831971e62ca2e93c5dfda46fb61d2c2752b1b76364c9ff60d975ca97250aacdc2c8d3dceb5f806
293	1	387	\\x21e65d2c403559765cbe1a4dd3760b17978ffbb6f4611b34ba09d51bbdb50af7370ea1cba8e02863e0ee85360f6c27a94db1edbced1213a492f215a8b4238505
308	1	270	\\x9fdf864e208f03d8567d55e3ca5660d4392c5326f83333ea790887d07caebd6b4986b567cbf28e39d104185ff45f620cf93afea29634348115f181fe8f371a0b
327	1	121	\\xa0677094360a852dbed0131c37ce7cd8475edfc0d43e20186db8715bb9ce59d99ad5adbb00ec3fd403e8184d1ca257b8f2388ccdd3deb0aa88b04dd3823e700a
363	1	142	\\x056b08a3050d39bee1f1f445ecce60e87c4d807be02593d2442dd4ffb303963ef52879e59da6efca9f8699f32c919f392c5dece0aa17999ea0119e032dbf7600
152	1	112	\\x6948560a77e440a7fed7bd87e56d177d860fc2fa2eea68fd5a8b9172007f8c91331c899dc7e9cf4ab3e7200981e1070578d3d4942781231c003f34051b38bb04
190	1	349	\\xb7ae6989f571bab33463ce8063063d0887b5ca0fdf34631ea61005afc7397847f2e97c715175f12511f78b089dce347b131138acc18051e5c723163109e6400b
235	1	26	\\xc33b3e49dd43cde0f7938af3e62fd4b2eda9aad72069331878516c4cf2930cc4f4f2879c811927736ad26b33e87ddabe5d4a83c0000a680e158cc7acde102802
271	1	297	\\x025d554d3c73138cf646344a97ef2520bbf0a9b4a940cf3d451ed3734de0d7ba391601ed4757dffce4a3384a07f85e4c16e308b70af7b1ad184ec608fdac5503
302	1	280	\\xfb190e73aab47c3234c2f11897be470f24288766ac4ad10c71679da57c1a32c06255e7b9d66570f208efdce58579392d041c5e16247b6498a08f9fbd9a36570b
335	1	96	\\x2c6ae26775e52fa0420c6f04428d140d9bdd9ef9c96cc2a1340dd6757b6161310420178a7cf5a5fd806f8f780be45fc280aeae877e3742a40f6552d06faf8f0f
344	1	363	\\x01d0c5b6134822718493a62a2e4ad81d265d08ef759ffa5228c78410cf03b3270dfae2eb858f3a1d805e4a6a7bb5cd562777ec7f6fc3cbc65c186ae851cf0601
364	1	185	\\xb39470791f6fd913b15e6b3d626184228960bbd7410d95ff6f4ba487d0090e99d27748257ff01c11f8f529dd67079e13060dd747bf0676feccc19a88e8a3ee0c
396	1	95	\\x489288732a7677b4ca950e640cc38bfb78d5288bf8119358f3d5594148c29795861e94fdf148ac8d7fbf464ccf0cf1c7cbd9d2d4102210dcaf2c25a1e1364f07
420	1	396	\\x749d7a05e63d49d23d68781ba38ce49f17a6896302017589144018974861f392238deed5d9d91d6ce951cd398a3735ae518cc8c204ae1753ac4537b666aa280a
153	1	290	\\x7bf7dbc93af528b2ca6d7d27f4a8a0e3f6691ce41c4f490b1761911cd23667de8bc644a7080525f012c011f2fd26ad95ebc48365b946067becbace84418fcf04
177	1	122	\\xba7197d0ddd3a87a8fc3d338637f34afc1a91b34fed9a0af2ccd6069ef8d15eaf9a0ea0317191adc6a8b1a5ce367b3e0a2ad8518e1a8f51514bfeda009e4d10f
208	1	110	\\xd72bd7f4c7211b9be28d031d223d4ee025181866b07ee0ea58de27561cef4693a7a4dd92680ae39a7a3307c0215010c3acf59c24a01dbfac1ac191cc269f9c09
238	1	321	\\x1a0e2fa63b3e5262bbf5cd99c81906c4049bff3d6d16864b83030e62df5b5502c1aa0e8c4c831ef7f9ef6c124f01039be6a1d7fd1de02078bb91c29214669601
246	1	316	\\xfa9aad9e0308a14f9c729c3862c43bdbd4368ab1523f4c233ff79efe85ec1e4177d9ab27234e847eb7b77aedff4c1c38bf8d1a6256ca87c514d6df374bcb2e05
284	1	417	\\x333b5db7f6d089c97aabe668e7cef5cfba0624da4aa9aca21750e38ef28a2d2bfba6337e61aaaf7e5999ee219ae176931a7d13a84e764518031b548c69a42208
306	1	416	\\x3faa48d89c5519f48b3d2162b307db16abf0b544b9212000d02f0ecdba16433c83bbd03e617d546c03dfba813a054b279ddf6b693f4b5d83a97af03346add20a
313	1	234	\\x60d71919d9347885102e6bb3d4610c71448230b7fbc00fa027fc202f45a7655003a729086cee1416721a8168cecbff6e8bdc377ca8369822c9bef74e65191008
346	1	111	\\x9977e9b0c53d540b5d70bd21974d81453c9757cb5eaad8aec14fed0cc0eb159062e133944b864ff4eb41b73f4b5496a0d480ce95f4ecafb25690b3d9ccedd706
155	1	65	\\xb2cc3e0e41947520b715c0a7c1b1e9bef709698040f6a54eb81b02568f459767a9c57d0b336a846ad26d1f175b12787884b774b7fee1c7cc0cff40acf1532e09
178	1	346	\\x4d0fe8cba31559f2ac0cbbf4c3f11a5f9ce7ad37f15b52d6fcf4170ed05a56b845004b5fd0bc095f6bfcdb7899dbcb6e138d4f65a07bcaa2728ef5f7f3b60b08
214	1	165	\\x27a26fcae31a8dc5467131fff331c235b30a406b682430ff96039366a9db9c5d91b9fa90823d4718d3fbc459585edc08d6b4edbf67a23d88fc4634b8499a7004
255	1	87	\\xfb4aa0811f2a14a3120f75a9d866543864a3bf0a4d6ec731eee7e050603c2df977810073583e971ecccc12a484a3552b930deecfd125e323af9daeeb4b4db500
299	1	130	\\x47fed6877dccdae363c6ac78ca3d7f774aaae54c408f9e7951e43bb41018b6472b322be34be5d9004dba50a90acb0101e88ca08adde86a2ddc7d2f5869a6bf02
333	1	379	\\x62db9f65c0d41bdf7f634403c5608f3ba0283a1f63b82cbccc3c65f9d784bf94ca8a53a30900008e874467be2647b28c35b3fff8cb045f17c08804bd7d422f0a
358	1	123	\\x0377044cdfe4c4afa4733f5ac001bf99a9d28ae4ad15a8a0d9f0368676a1a6be9329daf5a08351df3b69abac1d775afee2fd25d18e10a2069a656e7b5710b60f
371	1	222	\\xbf4afe97c62559d508ddcf0b4c464701fdf06c3e71940a6a4d443dc5c67e6aa818a37b6ecda2aca9d678ae26a9407881df31f5d56383e9ee083e93f1ecca3d0e
154	1	190	\\x607f445058149ac375f649b4e483b23c98150c40ecbf3e11678f620fc603cbbd05331b43b3435c50b18ba545e0bde022f288e9203734c30aacd2e49f93af8308
169	1	89	\\xd8c42171a6a0465aecadcfe64cc7dd2629145049e4dffa74c422e1ea279f73557b0b7698e66eb81fbc59a75f47fbfee7941241cb52d32035d6ffbb3e0fe7ce0c
206	1	285	\\x40b8c629f2fbc29b4f7abf8f9ae57ca097365f15f243a0d289d7ad338390194a16b17ecd1665a666e544314473cbd48af6de6d4081eb0c294b124881961e300b
233	1	400	\\x86eb46a1131d07d4c6dde35ec879000ff0545ec227e5f40ac9a4eaa0795203204e9252a4147d271b3d27e1182ac99f3b0d1a6e6096a11af33ed15969d1083207
259	1	167	\\x7dc26127fed49cf5380fe4ee6701605efff4038ab30fac0f65e3ac8343b2f89757439d621a2e0024f12d14fc4fed7699b6798b084ab7516c8e998c8253d0640b
296	1	106	\\x6f4d52b2a3ab25798a884b934d425f2bf9d7f2590f7164791cabc5c414d5c4085ef40b24c2fe1806195a54cbbe1c43479944d12a68024c2ebf98fa670a18660a
318	1	289	\\xa817d8ce2797d58017a4e19877e0efb2f1666bff97b10535641153d389a3194e12b15f373e946169b44eb9a36d83c9e2807e66061d5987a8b45b504ccb5e420d
336	1	274	\\xa91f57b64edbdc42190d3184a3be32d65735758cf6dc6375c4f7f90ec5af2c7c57afe9cab576577ce1ece05398c9ea9e56e2fe8208b91cb4720a1b494623c606
362	1	119	\\xceaf3d6be13289527c16609b9163ce6e9b5c3ddcfecc00939772054da39383149315b934ccfc39ec12b07991c0f41f99c8cb467f14c8bafd63db47fb9d8ad20e
387	1	265	\\xaefa8e28bd0e2ceec6c1d966ff31584d232c70f995227f41309206b2318d40c8b9f893e11ad792cc834d2682a479be944dd1d20378b8ad74bdaed732b1510406
408	1	177	\\x4b2ea06e71ff0b3dba67898226bf0bc7e2b01315a50afa1b4fa92b54c1bb5dcf2abede229bdc9b66b139b6aedd47d14c327b3849368b6da693642e860dcaf805
156	1	385	\\x34b99095ee26ada366f78a2b8ef8d1767eaba1a573454f4e63b338e7b674e9e8e40811f296655a7fe804c5c2b5e85a00014bc3529dd4067ae546de460a51dc0a
179	1	266	\\x830281386d0621117f48e3dd7f156ca89364fa343467dbf9cd8f2222edcb0715754305a15615a3989942756003acbab045e9d7bedeeaf684bff378cd2d826d0e
216	1	370	\\x4eef65210c33c46634d2320c28e168f7804029fccba42b8834014cbd482b0097192acf48720432fe856a691fd7c9e687544e2a84cde31950dbf2e74946ac6307
248	1	279	\\xf59d1f453073872075eed3f38ed2c540d917b513166e8245559ea2420568bda215b157b84b4968f957e70869f67d5b2257df8ace71e16a0c11087050696a2406
283	1	70	\\xebb74059d1b54884022d3261938c63b53e19c3ed71767024534e6e2c9df0b64eb2bb3d9e4284a45f930d1fd81bb9cfcb40221c6de80172770cafa59a92c01c06
323	1	320	\\x50f076d02cc2e4a6775520dccf3da131c30d795471744052981978782dd4fc3cf878e775a6f926354f68253c08ca08fbc380826ec08548482bf3cb7533ff8808
352	1	195	\\x4e5a1641ea5cbeecb0f973c0bd61313d31edf82d3fee433d962630d6afbf768172b3e98f51f2107f5ddcb67f05468c12d68455f9fc3d5fc01944629de54cb007
391	1	313	\\x85c441852b6171b6876606d0c7d81de8aeb4a078713f04003a2cffb12e6cce13c3f1712c1e80182007be7ca616fdaa317fd97d8d903411052532296961b80d05
415	1	155	\\xa3cda728f5b165f3ce68989e18a1f4d679fc9efcb5166807ffdf4af72182ebec5d32a2de4c7a8e7d1ef32813f11f100feaf32ab3756d12d789c9e3f52fe4340e
157	1	408	\\xded4a9aca33a5be04ae3e8e483a6419c0537edcc7485c0b5ac763782c85b687541e218ea9c5cf19f0b5fd50cec7c4452cded37148b104ca3b8bc4afb78aa1606
198	1	77	\\x076fe3d5c2548659b7b499f0241e1c72c806de3e2b2cca5c7606f0098497120b709302074b2c83bcc964f85b9c855de12e82a636b42d4107e90b67e54736e407
230	1	248	\\xdaccc607877bbc056fa34c239152f2dfb6a7e37932f2139b08c57575f9a93f041f2010aae5d71e8c9e52eed2487735722d362ac52121525a9e8aa82e5f007f08
272	1	16	\\xac24928b482a69ad3eaafc26445307bb99bbd8e464a44ca0b092cdc604b46adefbeef1501e9369feee381cc8ddd2e416401377f5ac2ffca958d2f21efa442702
301	1	205	\\x2075c819083f16c63e527a3c2e7691591b5d5082d4617bf331c1b0bc0bdf83552343c937ff1b28105939ae1b9a01dfded3cf776f78ee5ff8fb4bbfb4f4b02c0f
341	1	12	\\x64885485b7f6865f5c437e9ea64a465f6031c96c969038101c5fe75ec9f1b5c214a8a13b976af6f9fc67a3301e0a9cbf831d9a471f23535596d566a72974fa06
374	1	91	\\xcd8403ba74dd6be1e5e92807a1a7893009f4b7fa9a69144295417377b7620563faa06c69560eada5bbf3a4ab9cdd4b9c4bf20079d0977356c5d1c007690da001
402	1	369	\\x4af8cdafd726e1a3a2c17c064ffe4441352a3716bb6703f42df5f1b4018d532331ff8f4fbc5da961e9b1fde2a00e7e3e42c5692f31b6be5031d1c862115f1a09
158	1	251	\\xf9cba7cd1fb82d1bb0f9fcf2edee8c80f960e01e7fb761c818f8c52e3af27019e68c7cd6c2d081926aff6f0a38dd1ed4d0ae5a6dbb5791df6d0dd7b34c582b0c
188	1	409	\\xb56d1c41da6b6790a952bd6fee5c36a55101ecc9d28259dd07843319d2ebb2dad2e100a2a246347b81d170fbc85b91b3eeba1b8e0389b735b61894bab1f8240b
217	1	41	\\x024b87eb03643e12005251ca4e266322d2088f88798d8ab376cabaa20acc905ee837a82a4dd047db37fcc57566738a9737e79610683bc34c229620be333b4808
268	1	202	\\xf6533f2ae42396ada1c80415a2fa466b489f9ca47af985ad3fe5477a25c45c84d74b9bccdce27d7ab6084f83bbea4a828f32e9f79bfb2c8c3e66fe319e6b400f
289	1	125	\\x6bca86a18d8bd4a72cfd61897447d5d295f47130b5e6faabe7b08118527ad60ae58f3053f40fb60aa7d00aaa4ed0a319bc2e0bf3f51b62cf1aab5dd5a9e90c07
343	1	241	\\x7a7d1f3edf5f52af50d5ac27fb5a4bc4c66734df1cf9d41c581600ecd418c06ccacafa6c8bb50a42c13f8bed5ace12a35521472d210ba5212e42c2e84f938308
365	1	306	\\xcc7b3fb061d7bd283b76846269f27766f54d177b9e6748b41810e349275f543bb6d0ab19ec430b2b8eeda825223dbd4728f8247d68aa3a50880f735e7d56c408
159	1	10	\\x9f75e4d7dd90ce1dddeaf7bc561f5539815fa233933a82b65c338adad8cade2b6ccb2f15cfd00f59c797cfa9662d0f9b20f92736dc07a769a97cfab04f704605
200	1	322	\\xd41e5a1e9e17c4a5ddebdbabf8ce73536e623571d909708d0aa49a0f99917e3472f3b6833fa67836fffa14a421f4449b86a58f24543ae79a17232e9db390250c
224	1	260	\\x867c67c32042384a5de277fae863101216779ea159502ba80589b70629a9cdf4b737dc4566f2ac77cd3c1194bca8537247904e1e04d5bbfcfc0aaee76d907b0d
273	1	204	\\xfe4734c1f94ba88695c1d834b2a08f6dc857f12aaae11497ed4e95b439f1153c3fd0cd81eae953e671fccb277cb92a189300a620646a50fb188f7c0899875b06
303	1	415	\\xb5d7136fab6f9b3792bd6bf8fa934676a800d21e38463d79f053536ec47e4836dff59edeefa5c9c26f0c312400418f3b95121ab9b14b44afeeffa409ff4a9407
321	1	237	\\xb09067af960c7d4dcf15bf2a80ac7a28c7db5852c561c7a89e4c21a4f46d61f7b1c2c0829fc46f206c54834ce5b248f290db22cec911505daafaf1303ed0dc09
373	1	138	\\x55548bb29bb0d55f463213ebbc879bf50e739cb3aa2db258aec03d89336c263ea2083973c9342df5e2c618884a76c941647d2c689ef8896c58196065001fa908
395	1	107	\\xbe93e9fe38dacc4b3390fb6c8ee89e6a2f73b91d0026ea32df028175d1197a6f826f7a1a5eb9a3ea4f6d714a81f38bf7cfe2f8872688e2d93c4a83dc00aed80b
423	1	319	\\xae122401e3067550aed538a3f5d4efe0b1a59a4d204cd681be2cce85ba7564b3422b228341eee85b99a88d9c37abd2785514a2faee94bde2c17cd281bb308b04
160	1	249	\\x14a080705454e787fcd44edf20d466b4ebf0950e18464688419df5415988306aed7deb43932164b992757ceeef81d7877fe7c4c39b4b0d79db718920ea01840f
183	1	9	\\x82d1d8bbbd7ca0b160676bb6826f1e5c3405424ca3e5b1d3132eee438a58e0e2af95a2a1ca8fcbcbde1924c620d8841424a7d270c2518e1e4dd907e45580bf0e
212	1	102	\\x10ae35f454855ffd2449c8b94915da1d1d1ab3e3d36d9bf3f61eef3d7e6fe8ddf42d9c7e730e6168ca5599b503639d649d8e00d579f35fdd255ee1a842a03302
244	1	105	\\x33128d2e153abf8629e1ee0d893f6a480616cee55bf6dc7a26d7ef4ab7b5977414e90cbc9b7abeaec37565a5f0928f091c3ddd6ef1a9cf1a2653003cb808bc03
275	1	335	\\x92ea3311554fec38805abde5733ff65294e661b979be64ae9269dd4c1bd86929d9319d0f12bf3891ef8b353396445464d518bf98ec1315cac6cd3ceb99ea8b03
307	1	268	\\x637fc8157ec55600587fd79bd49acfd33e0f80d6c048d3c2c9b844ad5188909d32fb5a69afd1c984b7168ef63e5bc579560d54e0d7b7202c8b50186ab8498a09
324	1	366	\\x935ec0a7b36685ca0e93073677160e731e7d674d87065540befff6b05b2575dd3144d788d26acf19aa2e2ecff96667c9e59ba063b542c9cb1b4cb20b92966c0b
380	1	407	\\x6da7616d799a1fcae43a331ddb45bf5715938fd297e4be444569e3ab6d4896ec9d2a4709011f8a1ede9f430001c82164bfcc64ee6cedfb3e778102ea32db5502
161	1	395	\\x00b478d955db07bfc63a7879b06ad89b5e6e3122247981bb1e2598a040bbdc7d559dd68484782269b75a6b7fd1e212fdc1a6541848b675843f2832a9dc07960c
194	1	216	\\x965cd2bb15d5ca12046d04ff6f1737bdfe81fc99b908557a6e3de1a581d7d83743655224e2f0b73132f6e82559499f649a8c831aa89535e43a93fd9bdcc4a10f
229	1	324	\\xe73892f6cdc5bb8cc1e9a25c53b4dbf9818166858f121c26b89294ea9a66b44748d9624b8af291c8adce9adbfb3689cb29680ff932e23fbd79b49ca0a3a75a0f
247	1	347	\\x134748a736bcaddae42c2147c0c9793924da04d9385d4340f1b37b3ae9e6e5242526a7ed9666e4900626306eaac2e1e85fb13a52cae7823abf0ae1e44b69160f
274	1	152	\\xc0686d0aa01b41792a5e6952e75449dd60640c067b6a001706f63ba82193c4f3804bc5a0ea30e89d5d42a0286068fb8081dd097a5c151118de1c4bd6d14efe0c
315	1	218	\\x21fd6f4b6ea108e9330d5433964da28040c13ede01471c3807137226e13e77a370d1f71f976ff713e64645448936f471e3bfae9258811bbdb7d6a1f72dabff0b
334	1	278	\\x78a09f4545f4498996a1f1b60fe44ea25ea8c6ff07e86039daebc10acf734933015cb81164d7eb31022a22bd19092c86ae34d9533a898d40e2ed94b148bcae00
413	1	350	\\xb34a9c7aeff44f46cda971f812add66d1baa7d1376c1c29f30c27f3883450327ab92087f946c2cf66ac990d42135a9e2a1e355997165637ead9a500e002da805
162	1	386	\\x0a64709d8fd07d92ee050a901462c178241a80c3d95ec80a7fc2df6be9052b219bc1c3fe420a20083f1b4aecd9e2908c33a8dd4b4963c8a38843c2d189a97002
201	1	59	\\xc49366d5033cfcb8cece78213c1c607afe2cc6835f415994e7ee338cb31c20f51a9600f8bb8e6a4fe188b3f37556d431f83ccd00353b19ce2c6b7bf33e98750b
231	1	228	\\x434068c99814a56049bc6de6f0f07712865bb9e7d5363183501b92ca7a7b3c782a82da05b2d436752ff0e310accb27666ad842522351073ef5af423f67a55502
270	1	302	\\x3bf63bd7c957e0b6c11b84f72960c6cb559b1849477e88696ff3e40f700c8f0447f3695557c2a15715d469b2db0a94d9992cb2ba0b4a09bfd955eac40d355d03
298	1	33	\\x165e1b3075082719b83c117d67efb45ba1717d230f77e59a9ef65d6f8adfb6229bcd037c31dcc83a1088d60bf3cef5be6ecd6fe7e02a446c09862f0124279604
305	1	141	\\x3214734d3421529d7ddb3777153a61e67515eeca5bffda6ad2fe7d568f036be5a595514f3104b549b94ce148e505a84b6b7c302715362357611058d6ff035e0b
326	1	120	\\xc1f2a7cc95a2806e249c8c6d0b6171646d60416f6a3fd47f6765c039d334c90a035ecce6296071ae2a6d17da54b8776d2fbdaf6c09a139e3aa8924499ac95b0d
360	1	328	\\xeb67c5e4fb4d6661d92ef18222c472bd023910760b11fd55382570925b2af2a2ad6184c81fb4e9de3119bcbb8e7010491049651d05ea645d08b912c99665b307
370	1	341	\\x30832f2bc576b58be6dc51fe71ff368a9a6e8e01f97fd23e97df3aa370c212f22b24cf4d36b95c52756dbf0454e1b6e9a2c2c4824021f03c075eb1f580ca300c
381	1	187	\\xf18bcb6ce7e3427c3e5fef2962efad989f4a5db165cb6c23fd0415116dca15da7b2072f6db064ba998b010d7ac965546cd958bfccded3caf06e8decb011fcf02
409	1	7	\\x1dcd5ba7ac41c039493c3ad34771ce7cd3c6c59dce103179bd43fd3df021be0c7b881621ac638909933b712b23bd86e27b63c7622922371b45c2016aa80fea0e
421	1	401	\\xecdb206f21fb60db5c4d12a307c4bc9e13c3125eb635dea16a36b838b3a2187249cb903e5302e5fee8d39d510ef5724d386aa3b66c1c796598768b72c84ac20a
163	1	99	\\x44b190354e6d38b4d6b0242b1095d5a3e405f9d1fd3dc76770a719aa94538e3cf929137da2473c54c7f67b0e1d294bfadb3c97cd5019b6be968a18e6d0042f0a
172	1	355	\\x5d97712c27b59452ea240f2fd1a16ed8c331dc2f23be62d3869945de3b13ae4f78462d8a3cd634efd792915f785443f7ba1939abe6aac7c7f27384972caf4a0a
199	1	305	\\x648a479055fab51418e02859876c1933e57203506527c8fc2fedf26c452e3023c364c7af85f749f7e90aa5b1820b356f1ec711c31ddd4b1eefdaa630499b3601
219	1	293	\\x224244e4fdf74b0b18e899c8be518e05fe4ab1d9afd3bf9a45ac0b401cedeaed8b1e9f8a6c3f75cb1389a7ae894d6c2dfcdffb2b60d28109454a3d91ed062501
257	1	32	\\x2d8c3327e3d4bd54e80d8da57d6bc122be00ea87359525d7dbcd6c3667c3aa0ad36246b441a5ba376947c0e069c098cb459e537e474faada563e9b75daf37a0d
297	1	148	\\x4bce4a8ce6e860dfa95f489f0f6797a5492a06179b1df4d5ba6ec761afbcbc9767609155127e91391cbe4f326fa677deb3feb8726d5ce404b589947c90155b07
316	1	287	\\x12696d07a7741649bb2e06ed79c40e31c8eebcd82138f8a15ead6e5cdbf878b97e9c6a25dcbbd27d2be6c0ecc43ec718b4637f00623ae77ae684546f5e0ee605
330	1	378	\\x12b9a4241f0ce1415bede600447b10e195c474210d218011e720f60f7d8d4f15e40a514efe168ccb3144d8567e38f00943a3a5aee8614a301a16084e21dce206
361	1	94	\\xe90c437f4137a29e8b04200ad59f9a57732a30ea4a7e7070d0efac03e38f93e792d2a6e4f30482c3d0a992305323b923c85839d08a701c383e5602f5940b750c
378	1	374	\\x0d571aa28b12a025ad2f11322c6d4403fa21c11e55868752be8ca7e7846bf315fa9ff6caf9c778a625e84a89d4da3f38d9ab842e7a269740696a249d930ea70b
392	1	14	\\x8e6df53f3684e608ec58871c4f4837e620c9afa057e49059fcb7ee9354de16812daed8e062329c7bff2ece8991b2dd8b7a1ba8b7ea624d188468343a3f5eff06
412	1	390	\\xade41facbdd242bf269f1c5c5fe554bdd6335708e08f83efb57125fc799f9c1085855059a7639658d4f3273cecbdd48a2565b95a3910a8229a7b0b45e154b103
164	1	365	\\xc01d0b7e0bc623b1ebc808cf4add0e85f16d44ead9bc22f7065891e27f78fd4ff4ffd74618eb62f0cc6b4e72f9c0bcf3db42cbe53a83bfec9cf264c6fa12c50f
174	1	211	\\x48b1fc052f5f0de6b76710325778a0f4547233938fa09953a3cd7bfca4191f4c2831ad9356bc141cd0a661ed6beab617f8aff41b0ee0f7af253036e02500f800
203	1	85	\\x61e0ac5e6401969d5f9d0e46f6adcc4587fc9fe1624b0f38345e51b14594331800531eee4d119418af21c54d7302a624d0fffe66a991f3e516297ed3d399580d
237	1	210	\\x1763bbad6728725f3fdde653dec229ab6e8c67227cd76738dd2565beaf9f79547923ccea413d87f401257f26ea5491b7162cfe5caabeb48040904723c8e3fc07
276	1	51	\\xf28979d20a99f783b2da78623895efcf3df6f52eda7b74c36447a012e1be00c0004c2e78fdc1d5cfcfd5acc86f280dabd8a5c5be8d11abba7a9bec7f9f0ca00c
304	1	164	\\x5c4c8e5ec62d64304baa2630be5d80765f4dc55b4f755349be417044cfac4eda1f81341c74a5f52e1763166605c2a92ee329710f1e130d0c8a381e88f8acb100
311	1	61	\\x3b44b24edbfc63b5aa7fae7619a257b00cfac5a38f6483e02fc0d6b60483c4c319013a5b414ca13a63ae6e9dd27f4b0c1f4c7fd98428b90b2ef6f8097276e60d
367	1	113	\\x1d344c148982d931adff7f197927dfd63765b55b74065ae2403366157ec2593df6433da51e406fc303cbdfc7693c2108323b42f831c222df149ee0bf96e48d0c
385	1	326	\\x1ff0cda212493ad7a032325cde7e6ce4ca83b8157051f9b8797ded22566a9ae417ce16959fddb7229ff57c4d9016105e972b304ed4b75af3d0c925fa7b60d105
400	1	405	\\x24e3736adec3ba93774926ac7ac77d187f8c5d9af1bd35e3de49dce22a1bc0db0ad9a0954216b3f1461cd7913089890c16e86e53d07ad9eb24915025c30f540f
165	1	226	\\xad7da9e60dcfa84ec500bf43c713c34160d0a9cdc08d5e54eae4bfaba4f18f231cbde3f7d67c9fe8fa29df93a676b359aa3ccc8451934a41f4aae1723fd8f606
180	1	393	\\x3b8aa5619b9f416d6bc0af14cb68a6b134ac7a0195a3bc0a2d1fa5f95051c13f38dcbadd3866e634ce24af571e13df07f6ccadf3661625e98f25f84a530d5a02
209	1	412	\\x04405162a9e2f4ac81f8881bb12dbca0dbd9f163fc227967230a5f09c1819155d7af160b3de5d059b2ac9728215e1862e4a406de37bcd98c364fcf872a530f03
256	1	351	\\x470c2189dd84ee4c75d2180c94882c7c58b9655478d714db7a2874872110ac49ec4594ec9841c28faff8914e5724eede04661c591f8276274d86a5bc894d600c
287	1	158	\\x1863b7c656e571e618536a40c124bcc9288254c8cdf88fbc9656b70dba2bb3a8f7b4a0f6b20abea64413b5b657aa28785c33b71d4181f588c24f88b0c763f502
332	1	84	\\x320ec079322401112d1726e7a394d361d5f3d4748be1ba681fe1d121c23fa4f7c6ccceb60c8010a09c8e6bde15c5baaf1fb8acc16ec8532784e8c43063217c02
347	1	411	\\x0020fd20b5c93c41e1d22b0903d837bc823a502f75d59f46abf09d3d70821fd094982bc265a9b93a28b23ead18947bf4b7c4819f888af08e7f2a6a41926dc20f
369	1	331	\\xa0784dc668cd1c34a6b9995781c7a70af8f2a373e6798f621d6bd77adf7c44791643f9485051e749490e72a50110c379652f2b594c4b52842dc8617a04727f01
389	1	252	\\x24c77af2b9f29880730bc2d93c3c2f8995912dbc121c2fca49e3d4ef7f44ba75fc54f11560cdb0b56f83bdffe30a8c4179429a736e6d7929a053f0d3341c5e0d
410	1	223	\\x4db1dccca1dbb1fca781a57c2abc8de428395882c6c41e56a22e092996ca4e32c6afa023bdad2d0909f305b4cf13fb038fdbff379c0271acd1fac193a7e34006
166	1	39	\\xc98c7b9cf1beb65d0201e07e4b9a5040f96ad8201187ce35e2761d7363742ec06eaca323da79e65959da38d7e259ddd0abe67cd0e1d347dc04388974054ef606
192	1	317	\\x667368c6f4cb5c1fe7f9d1258aa10f08d0cb3ce434b81a3787b550c1c0b87aac4ccb262b9cfcea10c51a243f3803acfb79588388febdb8fd52b24382269c0b07
220	1	145	\\x7f1e79f539b693422a2ccbb5d2ba4aabc6cc52a22575b97fced9f5095776f969a7f08ad27c589d7c1cd8bcf1baacef6809c1775af15ca3ea785ea28a7d35b807
262	1	419	\\x15cf231cc7c85d8237fe961732d7d0b0f0a211ae1a51caad606433ee5667347a75a47ed15b112640a79bb3257b4b0ba9b6e72782870a09e2fde8a6928ba80b0f
292	1	159	\\x7f5a3814ad83064c7dcd86dc6aa0907fb705eee587f213224004daf0f567f431cce911e3223f4f987bd6ae06049b49a44ebe3949895462e0afc523347f3bb808
348	1	4	\\x2817348399a2af3b0bb31f178263ccd3eda73343be58d161804eecf782a60af59dabdd3ecd4655efc450eef2448861af0ba5b7ee7c4d4a9b1ff12ed1a865c902
382	1	56	\\x73eac916c5f2a4d929a5b2c4672cfa147f16d60d94fbb6d1f11ceb8fd62e1b622079668838f99adf04a06e12484f9ecfb0272425e6c7906c37903570929ec408
406	1	339	\\xc11ba04aa1be1a8f17b1f1074ca5ea88512e49198e0886cce2a0857fd87e1631f413762a518e4c8561d5e2ff29952588e9685ce24fe08d13fbd4086faa480c04
68	1	34	\\x0a8d0d395663fa4d4278b17c2e7247806544e18d81f34fbe9bc50b24efb15613bfa5608a11efe53a4647f08992d344990eb435144dd8a3bf8de99ce0200a8c0e
81	1	232	\\x9f234db1c935dc7d60462412ab6fb1f9efc8fc744b2c89c9dd20642d27c25669b855cd36e6acd6611c1b4f5a20f3c75475a2099354f218d2bcb5e41e84391208
87	1	136	\\xba77e15e1a808698693c4bda408947025a7f7552e91abee4e99dfdfd8230c9d9e40ff1f41def60083bc55e49bf6f0d91b94037e9fb4e2796b5f7a80dd51d150d
96	1	373	\\x04311bba5344ea6a9caa3dae150f62bd675159e2d842f8cff5dd4cb07b7b00a29054d2a0a07170e848bafc84d7a3e8816fe76705ee62b891bd78320b1fc5490f
104	1	23	\\xadea69e01cd732d771ad1b0f0a909139a12acefb9bea3aed39c712a2b087da01156b247520b93d9a94681d85bc971d6b8198e2e1671913715605de1a1a09580b
111	1	5	\\x277653b1f67ee500c319c43d08efce9984d37e14c2579141399710b64268c22145b65bc18c9520d08da7ab0dfab8dd0a980e58530316f308a3fa9d44dbf1b105
120	1	209	\\xd531eb964cd23749bc8705c8bf2c1c3fe85e1e8d0b7b1e650639d988ee5d3a86d62ed6ee7c4a157e7a4523cb953e82a9e356c5c67386b064a269b126b084710e
128	1	50	\\x80c9f3166d43b3a8f8acb90bd045e819ca3dfcd50030d8eb5d165cca7d00cf85aa9a758c2b4249820dd9af097632b2c1867cd6385052819d3db410c1c4de8f07
139	1	330	\\xd418e2ebd38f8bcf66304757bdd85eee23cdf9f40b44fa96b747ba4e6b694636ea7370b50dd0cbc6e854d29a6205e069eebff47f3f79849e829e02a5a0b2970c
184	1	231	\\x50b12fca47807478b3f23c50c28624eaf1339112fcf26d604997115411d451e09bb401284803a7a1ab47e14750d4d8f687e39c15ef7e38426ecfa396c78cdd05
210	1	371	\\xeb3129f7a9a2ebc1ecfd008298a6d9fcb6b8f802497d1c23f85fb8a5e18d1b049ff57c8c126322592a0d0d742eecb40796217577c97a9191628b4e3e594bc60e
241	1	360	\\x896497b4b96eea93622f63028bdb68a8a5003062c8b1505d618416ac4bbda4d422ccd5df5b3cc0cd46807f844ba4d72819daa9c36d640c263e9da70d1998860f
261	1	271	\\x6a00e022de828c48385ab04a01266f200b01bcfda45aab2d41ddd6de9a9535699fdde1e553f623f3771d462d152b159687716745e37522250b9b28165e48500a
285	1	154	\\xc8145074ccaa602c1da2f556933b4803f3c76bae53ba28e4ef44bb39525a1ab29106ae67461022ff46d35dde2b1b95651be024ba8f4404675d6dabf286a88104
329	1	36	\\x7205850d8b35d45dee4df3505c64d70ba88a6d18264ef0dbb9a7c3d4324de02b5d7e822c8bb423b773ce7e9cf38837b6e6b1e4eea8ad7c58c26888632720a509
340	1	258	\\xf43604a0d09f8680be76bd293e6336b13f0e41463df641a6fb7cc82b761a67f9f3fbad596c4d26c3196b36f720a287d2c532d8ba4fb0cd733aa6efeeee5ba409
379	1	157	\\x9017c97a4622e62281156132e3c9774125195a7d9254edefa9ed3896bd5dfaac66c84dc8995351bf9cfc9e7958b6bf4681acb8269f0b51e95edacf919c00640b
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
\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	1610135214000000	1617392814000000	1619812014000000	\\x2c6ae93ede9de0cfe5ed0112221bb3967cfcc2b00ca9af6fc88a2147ba4962fd	\\x62fb3d47dc948eec4a2473ac50d3a15bba86573431e9191113798aa18342d9d8fdf8860e569f997786eaa6b4cacb79e3f18def5bf67fa4528634105abce05108
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	http://localhost:8081/
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
1	\\xfef6afcabc08199eb1274913968300c02687850b8f4c41906a0b019ab1deb980	TESTKUDOS Auditor	http://localhost:8083/	t	1610135221000000
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
1	pbkdf2_sha256$216000$Oxb7BDiidBDr$IUi9VNSpOhhZKRnJHQpMe0GTe/EANyg3QbG1d7rXpDw=	\N	f	Bank				f	t	2021-01-08 20:46:55.270252+01
3	pbkdf2_sha256$216000$aRi3wVuVrJPd$uwTlYRqVN3RrWHiZLch70uADtFjOwfGVZmwNrVCEQ2o=	\N	f	Tor				f	t	2021-01-08 20:46:55.444506+01
4	pbkdf2_sha256$216000$ieobSmrYkYE8$l5BrGjx6NeBKFnlASZcrYIWiAO4XK4Gm0NQ70onZ9To=	\N	f	GNUnet				f	t	2021-01-08 20:46:55.526537+01
5	pbkdf2_sha256$216000$b1OBvAXHQMJd$/wjUHwuBe5teYXX62fk1iAepYfVGwhQhjxi7t+0DkUc=	\N	f	Taler				f	t	2021-01-08 20:46:55.607915+01
6	pbkdf2_sha256$216000$BftnC6WneCLe$4WNdNpx5oTsIwC5BoqNeJNlodNj65rw6BorpY9Gskkc=	\N	f	FSF				f	t	2021-01-08 20:46:55.688841+01
7	pbkdf2_sha256$216000$CjdiYG0M74GF$4ZqoeFxXSBlBUtNhlIpwyq+GdlWRIKBKzM85fktZcQc=	\N	f	Tutorial				f	t	2021-01-08 20:46:55.772302+01
8	pbkdf2_sha256$216000$1U17hHmthMBy$ZIcA9fFYpW5K5chhKd/XX3jYM8JtQ0homDzi9uQCBFo=	\N	f	Survey				f	t	2021-01-08 20:46:55.852843+01
9	pbkdf2_sha256$216000$flgu2Ho4Gg44$C5sr+gIgEUmKtUtYVf9VAuO+e9By4To2fChUa2wWuw0=	\N	f	42				f	t	2021-01-08 20:46:56.298845+01
10	pbkdf2_sha256$216000$AFNokGwjBm7q$xjtzoVbe26MoAqAv8asdbtqgLershUV20PSfeSeggfw=	\N	f	43				f	t	2021-01-08 20:46:56.753401+01
2	pbkdf2_sha256$216000$C70Re6Qyo67C$ZErCRg83VXos4gDporpf0hHMQqtBd87MW09B2iseTwA=	\N	f	Exchange				f	t	2021-01-08 20:46:55.363687+01
11	pbkdf2_sha256$216000$WW3hsMWw0Mf8$D5LAo955l7GyCWIDJAjcaLplYhRoy+yca1zRTgT1hDo=	\N	f	testuser-iaqRzgkP				f	t	2021-01-08 20:47:02.323696+01
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
1	\\xb74eaaa7ec35206e468a100ce7ef68f1e8a8c548107f301f6512604c208eed45cc9002a6a25dc7750170605e7f27c3b84a8d05abe8f9d503216e8c881f6b700c	3
2	\\x8f90eaa02ebfda5e7515715dced622cc0fe975f270386242cbc3fe805aca77ea89e1f0816e7b7d75bb3731a966357fea08c981ae3e506ab0268f4a0c004fb70b	251
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x003084766df52e0dee31f232ebe201a17af94da8ba3ad2de182590288d34e7349831fa5af08ca37cbe1df5fab60c2126937df3b17d49f19c400568eeaaf6637c	\\x00800003db1554f2ab1f7e3df22e8c0b95fd5b86953cacce80c1a5e8787d34d9f4b79f414c7e063496471f6b5242d8001474e337b4d3a908af679b12f42d3f306d766565b3894e62573184854bdf697a3e2ecc9130a2e858f59994abc3d2cb4447bf9b5d8682eb0591695f32cfcea9c0bebcbe5d226e4c9295916c6eba98e77a383f3167010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x16be47bf374eee11b99b98d754bdd7af0c3b420dc3d8f672bf643b50c5eed9ca7b934d6e619592d78bcd641e515593049355b49d8a1a7ae4e4cb8ec5d8008d0c	1633710714000000	1634315514000000	1697387514000000	1791995514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	1
\\x0448b3e67d5b655d49d7d7078b255329e7bd3611aa35d22ddf1bbe035f6eb96e4d8879b9df8f6240ed2fff573fd45a5dbb8221eb20284ebce8ed38f14936d31e	\\x00800003b75c05ca10366e3b7571772fa3045204bdaf57e6961839b3e42f059e85eb8d8f6fc6a6ef6a516f6bbea8d7be818334fa8a85e6f0696e7c8f3a7e3cb6de86072eed220606efbe4f7321f5120a132c1e818a89b25a4f62bc90439df2c3d2b2251e21610b85188bd31c6352744056331c7e57c95a7131b83f08918d9d3aa389ff7b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe0e3870d146f66a63baf9ecd85bb5d17e55ab342a220ca0b34583802e717e1bc36fc8bb438e03e9bc5d18783639a2c0cf77aa83a33ff5d0ed3e8148f3f951907	1613157714000000	1613762514000000	1676834514000000	1771442514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x09a810240e1311118bf461cd436fb882de5f158f36bed78c7effa33da9392c396430785660914c98ab1a1a5b1146b604c1b508b20382c9d469ce5afc4edcfe72	\\x00800003c2b8567c085c4f7134135ff62faa2ee35d384da741f1ef7785f35a3d9788bd4f94485daa224c68554cc99dc006e2c2dd6325301b3d271f8db20b44eeb4c2cae6594a7b37eb93da71ae57b5e3a8575169d9d13ac2854a282ba29fc19a1551075edfbcaf92c2d579a4d439a4dcc2c5e823b0603b01665326fe99a19cae23f81f0b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc23257ded4a733f0286295d321ffe020c1f6f3c96f7b09fdb2ae076bfe1f0cf809a841db74791f770ca36a8294c9666a172c518c0d2ac44646f7ac453b27be0c	1610135214000000	1610740014000000	1673812014000000	1768420014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x09a04f7ee01cc8aeb1a212c60a39e2fff8fcd396249352087fa4fdc19d167e555ec47c88fb0a722e512198d4baa833cd7ed3f7a93011f1ac396d5701d3aea0a2	\\x00800003b1e5f1597459b1f250d1e4b8c90d9d0612bda7b80dadba33bc1b1d9131a24eb233ff615db3c853bcb4da4f633a7d3bec2c14d9670e8e3062bd004179899b49bcd5f762b2c99b1728b53b9bcaa061734d8fda256d8541c2ae6a2c9a01a500f16e76866b73182d70a4e2bfe5e5484f25e879527c4288633d1356c717db75098b17010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe03e2b2e982685860ca59aef96e2d1541231f2d607f78d3afad4dcf0dbf95a3c8d3e82a0edb04c2ce5b772389360f64653bb8c02d2110afc810671743ca2ec08	1632501714000000	1633106514000000	1696178514000000	1790786514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	4
\\x0cb47b1740add8facd2919c6118bdd947626cece6e081c51627aac7c8559f9ca454789dece2b47d8a28d9074bc6d0f894e1ed01c006cd4df9ae9a769a274d902	\\x00800003b0d291b30c3edbce083006aa2efe9c1a33a39cf97e38a5a8d4b568ea6412fcdaef78ee30484f65dadc6f368e6c002a33d31bf01f029372cd1f23ffaff7ede98ac505313b5c381a097a84bc0205e7fffbc112a0ffedd78a43439680d70dd5482cd75b1f5925a11ee12e21e654fa9deb03fd86230289d54eb4ae4b17c203be40d1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x27fea17d025fb387513d71ee7959a19e67dfcfcbe8296eb7a433b628740db097b76a75e46512aa85d8712a746797d28710f23e98390e6d89191ffe2b37c6e301	1619807214000000	1620412014000000	1683484014000000	1778092014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x0cd45e194d47830008b334eb5be029f751cf6dd3c0e4d76f92ba50f0f9c1ad0f5f44c34f67f0b31858995734f3efc7627603a147b0f0f7c0e4bce5b31931d698	\\x00800003c952637d282dd05fd18743a131377ebb610daa3e58da4a7613836f5f9dcfe27f63de25bd341010b8bf3768993c45e80cd41b204dde725f4806da2f2e118a47cd11da20d79e6d99aaecaa89ec6d1830230ce104fe78973b8422c7af5023f3ff998568bd23178ed0d5c686e3d828ba9f3e53fd5d53eca589f98276506aca635eb1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x98133d6a307401935d9b4507307178831f790ef9011d4dde90bdfafb0234641f11244530b180eb8ad32022e3f5f7fa797add2df7fb2cd0331343b1e98c918504	1617993714000000	1618598514000000	1681670514000000	1776278514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	6
\\x0eb84175090aeb23c89209cf1d9d77b4385e6baf67d1fece8228fd312965d61f56170c78bad40687dc97cecc387fcfcac8702dc75609114f2186f436706ffb3c	\\x00800003cefdec9bad2393d3bc79dff9cb09c1c65502acfd988ff37fb01f611a4bdc387f69b017fc1f1b14b3c1b112d4da02b4fba25ff8383a4086b4c25febd93e2a18899735a8d045a4b36996e53c77875450c0ce5c517af8a8fedb7c5f947c94b38553fb91c3282f1dde26d2dcf14908c7282454cef1bbb931ce07393565f3ffbf34c7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfdca071da52c0dbcb677c9939e9409c3d262a05bd4232a61750e700364d0634a97703d9bab2a8570f668e791515bd8e141497155ab44f5c63089adfd51c92603	1640360214000000	1640965014000000	1704037014000000	1798645014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	7
\\x11c025154f476f8b4b25991c351cb989dee477fe2b66c20d0effe2dc921277c06e6a9b593e94783fed37b1919cc0a9e726acb290ceca03ad22551519e27a55a0	\\x00800003ba5a9fe6ef009f43a54b5d7d05cd2194074aaab48a258388c866b61f97cc364549294306a59376af9edb89f3656a42ccde6818c644d62fb7ceb69cfae83702504d15e57df2206e9287a24338dcdfdfadd21385d5d3dc6e1fd5e177d2879e6fc73833c5d857af6a8a7e23d84fd5a1211bd72da3a1cee8a5d535341bc9983f9119010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdf6608956d05432914e21f68ad66be4b2dff6720ada165b2846d05f3470d5ca2117ab1b5d9940cca8d32674cc9c21b21358272204beae1a9a3e871d00ab25509	1614366714000000	1614971514000000	1678043514000000	1772651514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	8
\\x163cdf300ce547c527e1afe3618030bd7f7abd65bac2518ae45952a79e11fd7041441936ddd139caaf9c34a3dea3ee5a573ab1a64ac5a78a8931e41fd4a6ad33	\\x00800003ab042e67e7dcb8ae73ace7bf4f10a75f4ce2f6c5ce45282dde363941970e810673f7cb48884bcc0d22d979068d66b4886a5a60cb403b032053683c8a8ae7e819f7b1af464a6c937e895003b58ce9536881dbe7aecd600e969832d9df5b8e7531f152a7187958e8651455e96feec8da404f3ca46d46c9a19a7f0a93776d8bf1b3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3e4a7c50fa41abc3dde31fbe3c582cf8623cd041a321f38a86d1d52ee65499492acc996de4553170c8286b22d05fabe64ff368cc06959540e7c42daa42e7cf02	1623434214000000	1624039014000000	1687111014000000	1781719014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	9
\\x16c838d41b2f8fccd7462028253f404d6b0d72bd3fa56658b2ceda9297cdab07aced332b5774c06ec396508d2731d857abc30d42c0cdc5e58c2a10898a7be18b	\\x00800003d7d2ee577b82006b085f21192507f610ded52516a546216379de3d6e7d768152a61e26433fcd95217b08fac2a92534d530a271cc35b3dd31ee4edca35c7c4b4f0172e81d6641a488849241decedd4bf531f0ec33e1a5dfb7b8e8d24a5e888d30c9bd18cfc81ae1fd790bdf56d155e8ffa4c290b31bc58fe9ba51d529600cc9a3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x83fdcf7089508a108b7d476e0182b272261f9e0da1e776c3ee04859a319c44ffb70bb7389aa984dd2e93bd7d860040624cb46e6ee378290df2c6506ea3b02507	1612553214000000	1613158014000000	1676230014000000	1770838014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	10
\\x1c586b3e215c039bcc43e1f36698d1f0104eb4df972f781bb9ce1deb577cbbd06cfc2cc256b2cdc5dc245246b7f1be36f3921faa24f81d9ba6fa3f017165bc88	\\x008000039c5096fb9c65165bcc872c7b869ddba376ea4901fa70c78306443221d95f39dceee84b6637c88531ea6a40e26ca5e10071d133fa892997d635a6bb90e9b9041f85008e67678d79a44715672c9a8e59b0ce1653ddd953d5e91d2054564210b136274cde8e4c7c167f7226d6c2cf4dcf735e2c386d2bcc1005ead11276856c217d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcc51cf661215d84eb958f087541746811f9235577055b24619a2f6a9fc8b888f740ee8842bdfb3b2d6482c90de6c4934c9a5b659ca4cc79284a1a6361df1820f	1640964714000000	1641569514000000	1704641514000000	1799249514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	11
\\x1d5895b86635aaab8a1f1c2949783421f78afd3e70ab778af31ab5344ba8faf3b471b626e0b8cfc3ffdb1619920c7e3f5e925d3cc3ab3465e90ebff1e7ca80f3	\\x00800003baf75a7d690a4ff22db89320ff2467343a5183d78c591b5809cbe5292e45208c42e68abf18ce2a3143db300d8b1ba97c8d3f40bc0079f6dde6e02344ec1d0d8cc1654ecf1af39b06cfbb4c3555afdad691e6e46420bc38ff40c054dc22a95be75077010f2ff95c02b8cda5d0800b7769904e5e9279265580744a1b746a7dd31d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2b500d950e74bd07839a0912266004a16098b7beb1ae75aab2cd0a90d9d9c55ed50e9dd535cd5c74f96ef6ffb4c7908cb25214f502a6aaf36332190e80d20b01	1631897214000000	1632502014000000	1695574014000000	1790182014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x1fc462664feec6363c978b46fae84946e132f397cd2a9a8309c890e9b1374ea7bca68643dd930667eb9fd7965133aa84af636754776fb0825f32f7e9c1abeffa	\\x00800003a4e8f5f3c3d6e0ee8fbcecf523911462a88d4e1cd126fc8d1c05837294b6b877f9e1959f52d641fab6c0dee26e6c1bb668e6128d9979e906082dfa1de8289fbd9e87495144dccd0f952d50dfd7a9a5f27e61cbb4aa6c9825402797b747a7dd47f92668dc9bdccfe238e41669bc4aae2bcec9baa8eee3381f5f22815674d3df39010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x40057ccab5bdd86b2a1fff56fe2db9d86e854e0b2cf50800f1cacdcbc2bcdc84bd5cb416ce8ab056e83b6e44f8a1de24b710e2f7f71fc178c60213416cb81c0d	1624643214000000	1625248014000000	1688320014000000	1782928014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	13
\\x2528a950fe8433d0b0966b550257c8809ca944970c29da73bcc52977e5f81d9438032b6ed8c15c4a153ae5a7f86661c62ed0e4bacabd750e3554bed7a55c943d	\\x00800003bb55456e4c6243f0fe77b104b5ca37fb5c047841a1aa77fc77127dbd3ea201fd7871800002df57a289374288ac9b1accf6f9c0de08cf6b0bafa9164e584c919e67b2e61e5dbbd8f6f5c12fd1f278dac7a4f3d5a010b9a9433ede8ea8c6c81ae2caead3ce38c29da10f79ea29f2c5218bb182fc7918a1ae00d2a8987a7217584f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb041662cecdce17387b955714b245cf3733b57c287430d133ff88d130417fd0fbdf422999cb22e4e816c3e7e828f38407ebf997c399fa1a45dec3ae5326a5801	1638546714000000	1639151514000000	1702223514000000	1796831514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	14
\\x25fc1bbb937d9a653ac30e6d8c1bced43a4b57cbaf06ab684bc25bd4458f41c6e892d4e9897002b4d571298f5402a903c963b4a8506d79d4bfd171663e9a4115	\\x00800003a7e25354b7b3406366ace49a6885caaf8e930e79f22a453bf21c207976b0bd591adf781e5f2143e8e5eab55ae8943c3e3a6282396f88b42380591eeed720004abafca73d69d18936e26d99141ce4b87c4ad6d7a94ecf9da479db71a1a4a015e25e14dce7ff5f56488ae2e671a1b26082c4767c2acdd4130fc06f873095e562c1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x456290547cc94ab49effeb92162a8451f43a61bc7f4a05ba6c2d2a7f12e300f94ddd85d736fe29d411afbcc55ddf4879dc9f5b24415597b5671c4af68563f506	1620411714000000	1621016514000000	1684088514000000	1778696514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	15
\\x28540e47a389b15f1afd5634bea5cd29a1bf520814f8ac8caa5a0bab4824c1879c7f5cd5e80b73c5074bd31643ca30c7fd5ba987145cd980ae11e39d53a458a6	\\x00800003bb4abf5b71a1a304c8d69919e53356e8e43d63056930b0a08f3b28ff27a818d9de619d03252f8f64820483fe4413f62e0d1c93e15a9c8f93d9e787faa96dc5623fa2d5a82fbda30b994396494e8c802821ba0c00b4e7d60b6171cc98cd9b01b3365ff2988404f4e762b22bd56f5e32fc0151567b2d34d98d31306916b09b4a0b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x955815c3cf1892a420dcde5cc87cf3ed4be4451bcade1a93270a2d9c9e5c8ee82f12a821bb1fe857814a091b099639d327e9a27060fd1cde17a40cb3624f4802	1632501714000000	1633106514000000	1696178514000000	1790786514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	16
\\x2b28db9348f735da879be3dd261c16b82f036803acaf0d6d2fc6c7ed53ed4801079156918cd6b5cb7371de990c4f42c3f8d0ba4c576a3b28f0f8ea40dab5fe77	\\x00800003cea469dc59f782da3d66ce11f494ca1d59cfff6f16940be16fd1cb00524818d2640788d60b503a616c7facc7a9d16353f3184d8ed568d89cf629a2e8b1f80fc5d0ab4457098f05f35122fa81f8d998f8fee65b3a4b1d02c849b1898ecfbbc996336a6d82fcfdde4bddf998f03c08fdcec91077f6a9ddd1ded98b28444217a141010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2bca75c9c6790fbd629127ede97a1b1bf5496792ba50d2918b2e775297994080cca04483e3a57e6cfe1a4cad2a16aa152dc4717ba00aafea32f7a21defeba400	1620411714000000	1621016514000000	1684088514000000	1778696514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x2bc0f27e6dee61faea4805dbbef47b2e09e8c6996396f698a77a62ee0600493f7ceae72c42305fa5514aed06d4fc6a52a4455d492d8242805b1c8986b8905075	\\x00800003d55b6652cef98d3fe3d4a7d939545e9a8516487369d940376e765dc955bc7e6cf3ac26bce1a1a1f2e0022d99760630e992bc96fcf87d085063436893fdd258ecdbfae1047d721225e65ae1184636f9fc46b49d3c2c68920134923065a10ae76c2f460b26f0db9924485181412f8c348b6c5dd9b2bad5f67aa7491aef4edad393010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0994216f8e5c418c7496645c702f87b8a80c3d33f85ad7dc4aee4c174d2ccedbb262a2ec36c8c186a109d5b79fb0bd6d63aa2008636d62b58f33941df88e9800	1637337714000000	1637942514000000	1701014514000000	1795622514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	18
\\x2c002ccaa58545665d273e43f5f10df5084f333e9fee0b1f190655e244bf3cabf03839ebdcc172d4418cb63972b0bcbacc7259389e68d3bcb61a90f3b1b999e0	\\x00800003cb697d5a1193ec4a13924feca34c3d07482db8c2dd4302ff1dad8b828e903dd44f5cbce8f036947cd366c18b3b08d81cadb5b43d9bc447d0520a134ef3b39287d0c033bf2a4e6d830724274144c2c49a81b145091dc9ef707f52c6a30afc65b377d0c37edeb3d8a927d5866dee31ef4c14b6262f2eddd8b9b14d4b5dc6bddcf5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6695ab3be5cb90e3bc10fbfc705dcaa61ace79f46d7df18b39069d86544dfbeb723d4063bf44e6a0ed7d07312f319442d93c2f67fd74bef7e8c3834498a8cf08	1617389214000000	1617994014000000	1681066014000000	1775674014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	19
\\x2d943ae819dbe8c916efedbf6356e9787f988b50db9ae63e15c11aede64d8850348ab52405ae1420f9e65864ed7be098c806602c5785c225adf2efd13c1c1d9c	\\x00800003c17086c31a69095f484b0fd2b15feb7fa4f64ce28dccfcc5bdcebecdf1463cd5d59cf8f34375706d1b613205deaf1de229df7adbbbf41d9a01805b55490ba2eea42e7de0761eefd91df88de179a6347fb438d892da5e0b8b040bcf4e085af562a65722a52e52d0ae5b70bcc7567ebee33730b4abb85f3a6f81bd0b0838437763010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8b4fde9e78c7e3a73852decd1f21c453a604a0c3bd1bfe343398950ba993eebb489cdac979dda17a2956c431abf1431a9c500fe193cebbd8c58f1d0813faf60f	1633106214000000	1633711014000000	1696783014000000	1791391014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	20
\\x2d7c34978f2d36b6b7539a978258a99c6dd37fe80bd7ea57f1d93eccc6934a791e54ee0e808d49eb0c80f81a0669cbb7722a6c37ea131e288aaf978548a2190e	\\x00800003ba9d56ece79f46270bba43f983eeb43badfa8ccdabf7bae7909a7241fecf7f0f9d0522483bd53038bcb68fd1de71872de1d4c589f5fb8ca4716a08150396f39cc9ee2ef71c101ae7beeef6a8ff75a3d4fc9c5a12e610e05b032392929f20fdb5e6c1255622214d980bb497574515cbcb4bfe24053ce4d1b70493cf149f37b0ed010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4a1d5547bf4be72e9d6c6d3b1f47f57999b385eae41e75748c2c2bb14fd6c12b026e65069ac77db1bb11748086548ad9714eda9fbbf67d84f621e42af592f708	1622225214000000	1622830014000000	1685902014000000	1780510014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	21
\\x2f14cca1883ea4ae2e9e8ab4d2b50fc2da572cddd1625baccaa323d9cb01d69ae39d6a88113ec5685768b9e206bc603bf1487a3cba1aff3e1ee99fbaeb855081	\\x00800003c796dd1616a60de8c512eb66d76d5d7aecd1b1c18febd992eedd80a00eb8d450730a599adba2064a731b21b0cb10e4e6ee2ae9a7661038df4d31bf2df04a4da73be851f7c7abe56dc73c654c285de049e17cda087c77c51e851afe0449fd5d217cae7424d333e72a954ae608774fdee3417282b7e95a34be82f5e52b46b3728f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x67dae38753aa3e7656add405b030deaae624d0c3a7f54d014cb253b515da009497499eceb79b37374e9fac209ed3f955ceb0a6c9b0ec3d452a62bdfff3ed090a	1628270214000000	1628875014000000	1691947014000000	1786555014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x30ec5a30f0fdf159c361e5901502f5a0dd94011bb3013afb2c4e55c9229a11a8c343b77e32bb7d1575792a53ab516ff2f25cffbf2b3d069c93b990b52620351a	\\x00800003c417cf87aaa467d96d8a71a16bf29736de3a77d84829d9fb53eb43414abbfc5701286d45eaae9bec6a8174c47a6af842de10390e195e1d77b1c0f1e63c79eeccb1cfecd3a4402752a4e656098d155d31223027dc11eda658aa2df2155775a50f169fef8c082c08fb66ad5d58a539017e659ced36858d9c2dc390fc996b264145010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xbb6668964b370518aa3447c43a686e15437197a24d506886327ee3c163c6df19e6b61f8f09d7aebda7e752150c13b386c54a1d9fe2976d4a1adf55bec8eca804	1619202714000000	1619807514000000	1682879514000000	1777487514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	23
\\x3144418f01ce122ed6c5c7e863327009ba78654e214b755c3ecb649278022a8c803bdd8ffb3e41f0598a67c479441cb58022adda1f64664d1442ba99f0aa542b	\\x00800003d70fd2699e98dfe1f1a4c62e5d4a5b37f9fc3b26161ad3c169343e929600a4877aebe511cba02a7aecf4f369934e05037ed53b34a1b289053d11eadefd57be173bc2d8cfde6092a1c3000594515463f1208b18f974a32266063670a29edcb036a4d0863c881d4f72b3c0d74b4b711569a018cc2cea506daef9c554b10a626315010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4df1882e81cb8712b80e4b6a146e75e74f8687254536ed65906594ccd9f974d287b5bfc7eba608addee149fd9f75e23c0b39f9e3f16647c30b43559f66477508	1612553214000000	1613158014000000	1676230014000000	1770838014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	24
\\x3140e6779fb87372c42f6999638dd3c8f991105071b0ca94fa41d88712518aab0ac7d2ad4e98d62a6c7f96f4eba42a5cf21ebc0f94c23b7f1473941b1fc72236	\\x00800003e60bf99c652fd19e4b117fe1e9decefc4cf5a64e8799ea6bbf3a642b5a1938df26e172b6ce4f263ace8e36cb3a3bd01d0e6d607fc35e8a832033e8dbcf8a83ea403cd0d7faab569d77d1ac69cc10c8db9162461a791372b01772c7e81177b9cc9fb3f5ebf91b87e9851202c0d4da1e1ef85f06692641c0214fe0c28aabae6e9b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x45d46691bda46267e596480deac5dce806199ae628703fb78a21785612f7aa0a5bf944e38b883d55a7f86a02a87c1466299b0d2c57826d4b112102d78e584a0a	1615575714000000	1616180514000000	1679252514000000	1773860514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	25
\\x37c03c4dfaf41f97af3e131c392378ea80791dd011161237bc04c5951cc8a916cba9b45801687d53c34563d3f368802d3dff85efc48452a14fed6f53842a7cea	\\x00800003b9066b04a777653a1f2afc15750426960e0a2f569f0ff98ea7a382799f6ea91a6227efe2ded805e925d2160411328a31bbb47030dbde045935f14a5c2edd8aac102592cb5c399b3075909dfedd6b31864ded666bb756702edecbc72cb19e747ec589e15c2b1575b58f9affa04f49a7d98ef2be4f1f962979c127ee23c3f854c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1018aea55dfb9cd380ebeb62eeab568ac6f505df6c73213e1da6e8e188ad0291449e0ff20fdebc13143bf520986ddf53bcf465aa0914bee76dbbd5558a40530f	1627061214000000	1627666014000000	1690738014000000	1785346014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	26
\\x3b0cb009c3059d000c79c4388cfe31e2aa70ec7e59e33d2294f378f8da320ab9bc860fc90d0634f8cd3141e756118591abcb56ba3a5b1eda8c6a0b9a523e68b5	\\x00800003d329591668dfc4378e17c4b5ecbdcf2e7b22cd1c4115b1031f291d08edc9f03ade6835bb88f6148dd92fd99a34ea6a3990c511ddaa99b010dac10967d5aca542aaa2d02f581b905728bf0b3f8e52b61f86d5f0f98f5540017f1e39c731a9affec162861ba1e95b26dbf69f10f6113494fc2909b80b01e5262d9bd2bf1dcdc5b9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcb8be951db0ba263caa2dbf97b64e69864417970b81080a4375fd98e534995c2dbe5bbffbf45331132fed0fab5b8b6f9a02f3f4fb37dd37965c771ea6b7fe90a	1622225214000000	1622830014000000	1685902014000000	1780510014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	27
\\x3c58e06353170de0de8787ac52303996ba000958cefd06082fb02e5cfd49d6dddaa5f2f1c294b1844f554dd25f76f31dc69161960e69f6f97ebb0b70c34f6b4c	\\x00800003d0234087e91fb78753e0bfeaf05774a483018ea000e3e7ff5c658b82a461eb0dd4ca9a9238f46092b513d80befa9e4ce874439d57fe31c125b4df1bdf3ac73040fd24f19e09545eb0dae3688b802f9c088c6677acbf435b27482220e1ad208a8a7fc3d7addfaaf801c21fb354d741bec732db22a19bc1a47c7a3c60317d9a25d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8346fd84bdfc08ac362d640bffcca5b3199a77ae4c6ed1572b168ea29c7dd4675db2aea8ba18522ece676011d3a76cac56842d3fc20594a41f3df1d5f7e38409	1617993714000000	1618598514000000	1681670514000000	1776278514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	28
\\x3d301fe41a9448ae9c1a9e270a3be499871128ffe306de662db019481c00029dcc608ec6e04542c6c405c435556e01f4c655d6075763f60432a4b95b57f2f5dc	\\x00800003be1209177eab12d40aed0a9d861b8a866934b1d8517452f8e5e6e6abe0cf139a63a63a2d35b844e9571d21eebcfa40d339d546821b727cd5c0caacffce7c1e64aedb1af1ab617dd7402f8b1d8ea76f7a388a4698e9360a9ae09c244bd7d535e0d6735505e541c2894b8c446f70a1f8743d3035f8d5f6aa210f7e0e850912fcff010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe9be6390524b0f5ae139ae05a87a780f35d7665fd36df4319a94d98ef3a2308e641c4d3e68535c6522e135ffd57b7fc1e06a3e1216514e9c6f8f4fa105545d02	1626456714000000	1627061514000000	1690133514000000	1784741514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x3ec48394254e43d9d7ddf16f84a79827de739356850b09929dc62e92f6c2f2dae7c5d79e252bc7bdbe5095db3a72ac95c22aff3063fa321b33f3743e997dce3a	\\x00800003c81ac7a4b406cbf6a35237260b1f8a8e498111d8e845d5193ab1f3f38c1ae0c35bdb1817337570d043f85564bca4c9c4d3c5e465fdda16bd1ed3d8f47eb3f8d64fd355725ca11c225bf1a3eb7dc0cdb9027377cbb08f53d607a3167fc89f2d6e55a4929fecbc7a790608e0c020fe755442d18549db402d0ed4a5156cf2f68da1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4d0382ceb787836526955a082092fb3a2e7e650c075d0c2768f6cea040e1aa78fa747faafe5eb9f35b3a13c4c74b9ec6abf7096f3315920b9c90fc75da396b0c	1621620714000000	1622225514000000	1685297514000000	1779905514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	30
\\x400c226da11f77041bae6e18f8cc701f422657d1ac2af1e405ddacb36701fd9f0151c1c73e65879870b1040417ec2121bf256841b6d688e4bbbf0974dda02f53	\\x00800003b53692bdd9c71ef0afadc2bc2192c4b9548f8704727edf481a84aabde3e6e1c934b86ae32d4ea0b773e8ef6f43c8814249e791ed13e65fc482c202eca0a79854d8a0331bff085b00344291307667a5e67112ce81e690d91f2bbf0f94b06282f81fade257e7e16dc00a58719b4f1481d7053e332707c5442edd8372137d4f6557010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf90465a0d7b0fc7d4d39022fe2ef7475145478206c8dc97af3fb2be7928a36ef207f464191d9c646f87778364fa049077ff3de1eac26144d2135162d15f85502	1641569214000000	1642174014000000	1705246014000000	1799854014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	31
\\x419cd5f69ed5d005878f331f2d6f4a3f2f0c380527bdbf3e6cdd65517a7a4545c92b247c6810c862baede6a83ccbd28def2b056c32f2a9c830822a9b01e52998	\\x00800003c87733c98473992b96e869fe26d4721e15d53c156396a0585b4c692a56164aab57472e5cad2a7cde1f7f9c2022490101c0f1c1690757038a9da55302ffdba1bd7a9afabc02ca17580c54003438b4520b73e5337b37b34ad64c456f6c730427552e1bcd4d17c5ec59fd2eb6ecacebf573200e15bdfad8eaded061cab1a13d7fe9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0e54a95abb84b090559a121a4b2f828b1dd200dd1b95c6d7fa44f267aebcba60c207b304277d12972a788222e1add1b28aa76bb7f5c7dcf432ca460c1859500f	1632501714000000	1633106514000000	1696178514000000	1790786514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	32
\\x420c52220687fe63a98de5537f798e6107ed5d289a5cb8b57f70c0da9ef30b6031c80a5676b4f5ac8f9aef0523b627b790f98414060edba66dca1aa0f61d789e	\\x00800003ec778e257331ce564fc453c5a13c3745660b9885f49cadc6bac82884ff9f407e912a0a7ba08e810a08cbce53c7b79c5ff6f669c7b830af971c6c687c5ccc1ebff13f2802634b1188fa2cfd1807ffea74e186ca281c0fd7666aeb368cc4a74b7c714121606f3d602c84ab62e6f668a5eda71e69624c129c6a8d97db7355c2aa69010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1f469f04f33bbd5f1206cde760a5224db67caf5ba524e27131be43df5fc4304568cc68827e73265dc95dca5d26398bf693591887dd80ea001eea767940289e0a	1640360214000000	1640965014000000	1704037014000000	1798645014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	33
\\x46e073fe07385476d5ed1841e7e1c3928f8556653436fa9861f05f00d2fc05de013813472b455d42bd8b2ec383198e3056c3d9c8ec63ee93555532659a1cf2bf	\\x00800003c38043b850f23144f79a98fdc0759626ed78d43123825ada4c90e3ec83f8ec5daeaad05bef81764f57fd847b7bdf048d19bba21d579cfc58fccfaf96814635913bc19353d306c19c29df7b62879b73d9f61c1b3705ecf6a492f8f19eac29f48b5eae14b71cb5a8d70e039964283c46f5e00bf9b8a6d51395ba387dfad1f0778b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdb5e38c5d110dcaeecff18dc095238913e3ca554205b41aa63a21239199638209756d334fff030acb35b0b8b3f443748c779fed7ab073f0e6ed0a6c73a9df50c	1616784714000000	1617389514000000	1680461514000000	1775069514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	34
\\x47004f007dfe8f35e859e438fd8bca3bea3040e24c56764612c698d1bdf1850e35512d7c27a29386dfb1ce014b676740d17d030623ede41512e11a41b8ee346c	\\x00800003cb5bb715f4364b335fbc31a0cf7176586b0168c6e132ddfa6119fd358b02481e8ffe75df47b0481746c3af29d7905b7dafc33257cd62a91a3b4a0ec5a32a36277c13857fa03ef141eccf48932e95fc7647351b9e9c7f7c496c524775ad1ad6c342ba4dd1ffda50cb07a853bb853eda9ad05ab6aa2a76b00595fd3121b377a627010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x44d0f195747f76047028095cc38571aa827ad6a9e7968ad02256216549240d1de3aacfcbf470121406611aedfba4809ec5097dd982bf1dd9b9bf65aa267a1c03	1611948714000000	1612553514000000	1675625514000000	1770233514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	35
\\x47546e0c149b5a1f68418400d103c005c663159544e92382dac88b40bfefa546172a51b3f8807aa1f494a97d73a1fce94efe702c9ad6329967faae54bb3a9572	\\x00800003cd2d1b78cb8567c2322bd8c46296d384e7cff1c653aa4810346cee032b9e3f1af2ab16d9c0e55dfb90078d6aa6798ae2a2a07b28932fd32d1b4d3e7b4f1bef3a73bb498c22aabc426f79bdefa761aca670d5fe69932acdf75e00eb079455ca407b068fddafaf6127191782e8a00c87bbcebfc061a8a81bb3bd00bb96f82d7cd1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe8ea40b1bc4e1d724a7c6107a7b20d18f8add9c74f5cd298e4f5d525c01a1f100e34e0e0b5017748c9469ce7e722c0019dad24bb28703eead06662f403b0da0f	1630083714000000	1630688514000000	1693760514000000	1788368514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	36
\\x4948f269a4b5a5e2dfd7c43092f6eb4d4ae8a34dc9f40143223cc033c485ecc9a0ceb78114b0588ccd28e417b64c61ff5acfa6f7800511e8f1a1224e686206a6	\\x00800003fd54909db1989944c126dac7b215301824441dbabbbe503656f4d94f09dd351c7de83f2454e1700e45a471720516f33ef4a71aa72cd64276c63d4174c1b3752366d81ddd8f4d37039a85bdd35099d7f58c77002fe2d01b08afdd3203341c090104472c9401af3eaa21a8f11818438def87daab81a0441d6da9fe18757041c03d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdb41cf2f6ee2b72046433ed749f4b6248a550c8af20da95be373df37cec3b7304ec7985cfc2e3293d80ce648feccc50ed7c186e1e96857e438f3681a170c3401	1633710714000000	1634315514000000	1697387514000000	1791995514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	37
\\x493c79f2171695537669c0f21f8ac4143d937436b782d98e156a85497f84d61c52c874fdd2320556fc98c29c9bfd00d21620d9b13c0c7a6cf3e332b1cabae35b	\\x00800003bfcb8ddaf88412b822cfef2a795b81ba23cb728e7103a91f11dc99de727532221404d8f38cfbbe3efc44ed93e884af7c07d36f04a42cbc0d6ecfef62c66270882a23220e6c0791453fd890e891f1cfc81f727007506738e938d4d675a978b299599ea77a2753333adc7e0dc154646d32ecd03ad0b7346ceb008da7aad21072cd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd829db25d65db9cadfed21648e890a631e2e30f2fa9561c830bf85c005532d025c3910ae4e78049731a2f744f8f5d33e62d9a106f2ce2a1caaafdbf7e9c4b506	1616784714000000	1617389514000000	1680461514000000	1775069514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x49f4c8c59539921698817e28e2d6e17346d19a191fa28778e76f34d152abe296909d0136e0b4bd718e5f326fb74b30a9d8a67c284a59c945c9e408bbd215167b	\\x00800003ac82de7b9a8a9c4b90b21227ba0793f3c41bb48bc69a0189a34dfe2ff3a2bb1b59d78dfc8e731dcab25661f32f0338bb26019000a6e546ab2b7329ceeefeb5abbb5ceb43865aa3bf736b0b665ae6de9c488c5d84bcfbf7b670f144759eeebc87e421780f44747942093437654f5b0f679733ddf239452d10e19c2371d9e7fb6f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe49605871842b5785cb71ddabfca75a48ea9c9d5f04c6c1329588331b359ac53f38f85f4c685ed58ebd6dded8e493cf31f9dbfdd9a0636ef322ad8772a087404	1611948714000000	1612553514000000	1675625514000000	1770233514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	39
\\x4b9cf914f0a1b10430441cd86a193d538407d60d4b4cbece744747c32a464e934d9224aba96e69f53edfb20b3ea6af255f6fe3e19b3621778545c45c0811b3cf	\\x00800003d7a02437b5c6d355033bfcf84ab79cd6093e25276e754da01f21d22850f75a847dfb2dbad70e8a577b2e9444d4d81de1acef47a556181461a59d3d18ea2f56ff66c080ebd9b4226e16ce60b386947a7c922a514b0da33a576c0d7570f9d08d4b7a3eaaa9d3636e2f1bbaab8112dfc209159018d938bea5a4b941e0eb30ddd06b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1f5a2f0ceee8221c9ec16b2c04ed5d67f6fd113cb87de92b6586de84540e489a913ea0cddfa6a03f7db20366c5ced8480eff492edd22e76c6f40877afc47eb02	1614971214000000	1615576014000000	1678648014000000	1773256014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	40
\\x4d1023613f66851f2f1bfbbf4256fac85c1bc6df4cd8e6365305160dffae6b558c9091d95fa0dfb0d8b5dc45d0d94e4f2c996a75ce29630a62898c88d946126f	\\x00800003debfda880ef9a7d44371285c397dae7c604f87c93ce07b6f4a7b4fa6c7b87c966ab737177f10c9aa16afc404d2afb49621c728cf3dd9f7706e7740f7b1347be18840640ed378989246ad268a4dfa8f5ebaf684443f583dfbddcaab227a3159933f9d9cb8d1d2d0e2f9a23c9fa80754298096afd24ae1ba07ced185312e18acc9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x08fbbe70377f336694f4c2f896523e6cd7643adcd022d337afec9892defd43795cc3151b91425fde8008bd526f41022173302e59c51b08257d7c8915f922530b	1625852214000000	1626457014000000	1689529014000000	1784137014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	41
\\x50d018bb8346354dbf17169369dcaa8697b5d37bfc3513c0197615648bbac4d8d20a721e918f823bbd6949e679041946726b461825db3dfe746e5406f6dc782b	\\x00800003a0064519cd1b9e95b1359453edef4ba3780e14659dff40761c85a1f0830629e626c60ff3983fd76dfe6f948f43b862da0991a8d7a5c2c23266d26be68fd23233396e71df50c77029327fd5a4fa14d724aa6654977d0d7c5292d203a244ecf5b7b880fb8d4aeeb1d42e1b3ebc1f389610d15d9d5cf730a6bdbc0d846764918519010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7224a1d92428bbd64375418b6500a34136e983f0d4b24c0e332d764d5729687757592cfef75d3a2de36ec47d7a985e181968c70eb724e413f7c6162a9aa07f0c	1618598214000000	1619203014000000	1682275014000000	1776883014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	42
\\x53f80ff1f54228a8d7a480a446b8916871b737540bcb2496e6d13904ff98f120d8e9840baa23e030c92de85d7db86e651b7f99905f2b987cbe01f2c653c3cf5c	\\x00800003de0dc2e1cab9501d45f70ae9615767813baf50a2b173e6d9c18164ddd54dc22c881190c1e2b948f40f438bb2c4a9598c4648521a32d11bee053667d17fdd6120101389aebf62dcc3535f682171bb059739dcd8fad42dd4eb21d9a240de4e91421ee036d0c838ce36234a01336443dcc3abc95cd2f9a2fd2342acdb8b4ac81241010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0d300773bdffecd215d57749ffbfe96aa092b6e85de9509cbea56a7466fa849790bca3a01233d9c723ab331721eb92280c8ebf80b3bfaf70574f3de4adbcb600	1614971214000000	1615576014000000	1678648014000000	1773256014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	43
\\x54384302d073fb5f4b2f448d737fa44231faf840a9cb6d5febb6c9587ea8dcc9937c43a3bd7e21cd5cd3395e82ccb20bbe8d3f2bebcf56611480834318709dcc	\\x00800003afa1eab98937204292270d60367efa6035e615cc1a88bfa45325242c17fe74f291d38acc67458c0217fbffe4a25a1601141731e13af0f60670181a592edfa386fcc5d66ae67f85350ed6ca73d24270d352d2a3260d8319fb3bf0884142f53fbcf643f5aa4736e7fc111561eb57996c6231171318b2ede2c396e9760893d80b11010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x449df70f08e02ffaff3bcc8e93f83e2bed6ab44043b932f46bae0307435c2283a74d685c0c6da52d68e74d19008623e470f0836c2fb3487b08bc8257fe26f80e	1641569214000000	1642174014000000	1705246014000000	1799854014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	44
\\x54d0782d04b5b8009e487e5770697763748a07db310faf30d0d2be70379f4c9271029fc4ad109804e16eb0a5657b6bd42a2dda3f39fb344ee1bf044c088780eb	\\x00800003f272cb9c845dac0a37c84835f2115939d28e40ddcabbefd49d8a50e9ab2538975f10309fc818fada6d9dfbf1e14e2a418b36b801f2ef1322065317a2b942e97a33ae60e2a4888a5b93925ee53790916a3a8fe38b796e45e61de44c14abf30de1a392b269004b71b8faf82f52a367dbde997c03cda5ced3695532e3f39fc5c415010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1edadafb80ef74f04c679511271529a13826e4978fb5872519f94d0c6fa8221e6593091cd3ba00e553ee9fbad74084a3297f9772e4ba9fe0ea8bcc16e4125c0e	1614971214000000	1615576014000000	1678648014000000	1773256014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x55e808c77b8302bdd7c3248e77c5f84c09ff9aea7e2c72702218affc6bdef7cb2d45e25c732e015f2bf632910fe44788165570e2a7b7de1201f033d24ca45038	\\x00800003c9b1ced31641fedd59d035ab50aef205717362c383f75717a97832498c8a47559658844c0e91f8d46568ff55266634ea052c0fa78b6ffdbd1f8f9e9b4fb4f70b68ef799e9dded9f03546d875898bd838073c9b6a70ed51508cd6056c94aed2db7dd217a6c3395c147d36daef2f46ed3e67dad0a5edddbf0d1f6da0d8ad693f59010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe19b26a67407574a9d3cf01699cffa3ba1114b157ad267508d72dfd7d94af6adde8b9c0af2d5b52c0ab0b2bf37ea242e0ad4808aef0b0d05bcfafc2911c7e108	1610739714000000	1611344514000000	1674416514000000	1769024514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	46
\\x5938ec3d3acc9280d9176bd88390b66b4774d91d64e17527629698af07cccafa1240f4fd6ce24446ff54edab7808e866f5abf8c5b4f0167cbd32603c1ca4ab86	\\x00800003ba56ad5f03476804141cc8e1e86cf99535fceeb1987f0e005aab74bd16f4395407e3704bafdad129910a694f030ac3566c3463cef3c3dc02f400b4b947956930ed5ff3a583b83718b40f154406c7c35fc1ad17be68aad9ee33861396cd2cc3aa42e7dae471881cd353ba91484712e1bce3b1579080b04dad5df6681ca5c30b39010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x007e3d56b3d9357db04d20ee66cc87d5c7fbabc45a171e01e13fbfa981a9c17ab0956d6e824f7667e47043a28dabc935019df5a59a6fd5470b1fb217bd22d100	1627665714000000	1628270514000000	1691342514000000	1785950514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	47
\\x5c58f70b3524abc2cef230a786dc606e790be1ae38c2c0ffb76349b0aa606048fab5c2fa8ed9bc70e9aec92b1143ba1cb21ae8705dc0050e246830f5b288ded4	\\x00800003cafd8535e3291b1f09b0c1820a6e7562c4173c67b48efcc051a0c909ba62315aae00cd0ff3f8494089af390cf9ea05e7a428dd5775430ce2dd026d0039712210c8c5eda8c352ad1ba7bb35161faff47230eaeef34651a81a48a8231a4806b44d629551cd409c3b6b5da3ef02093aaf722075d38131fc4a90ce9575f0d850fa11010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x03e04d79c2c3208a3e9a1110cab5837eaa77a8aa9fcd22773d3ec31a23eee1a777117d49a42653fca8128e0613a751d883b9f59321a58a467994f409f6cde60f	1633106214000000	1633711014000000	1696783014000000	1791391014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x5c54afcfbe94a6ff49e16c55d9c2db384db7f4c6cb4e555b6e75fa64224bc4418b5c02d51919f18b1cb1bb5697cf01f6045360e89dae140df8c2b3f11d322e4d	\\x00800003a7b6d586d7a619a4ac152554f97960246b7a50ccff77c0a22b17974b8f05f4f206fdea636c93e0014643aeeb5cf0fa5ee212fbab311bf69c1cc65bd658e8a43d4131f30d7827c4b2906a3255986856c5513ac86e25d5492b872c7e5e77c342eeb8d6c029af70e193389690d76266478a0da2f8f82740cec220900eab6c9cb921010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8b2e87d08fb324e8eaba24d7139adfd807a2da822eb4c962404a9551e5ef77524e7baa8762521a1d70e49be5e96496c9910e934c988807de3ee955624034ec0e	1625247714000000	1625852514000000	1688924514000000	1783532514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	49
\\x5e4029dd66123925d7b1af90f2713e5485e732b5be17fc61ad9d7ce2e47e342e0ed0669c719b97f7bc808b8579faabe56da5cb901b5be03bb9677bc523f658c8	\\x00800003b51274f95ffec369ea4b126c7f4e312bd0f608f04fb837bf16bbb4e83e85183f80f37c7077167fc49d29dc4046a389133b9186d5c51ba733bf656a167c2a3c274b6463422f0626f40c43bf61f1e2ee3044d1a376e7e3293d33790d67f659604bd36ee08e5c3c9fcb7bd50f59df95ea1a86fdb1a2cb0eeb6f049d6a5d5c7189b7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x78371f6c1c6074d35585f9cdaefbb5a2ba15b8b35eac0587007adb4398b0f82b4332f2224e1aef807d36bdd3c6126717c0bdbd8dfd0585063e5feed358496703	1621016214000000	1621621014000000	1684693014000000	1779301014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	50
\\x5f10807dc0baa264608fb8e675e273523b4d20afab280d1b5297837abc4af087e35e08ae845252d1247cdb0cded93472cf8525ec0cbc59d75350de05784bef01	\\x00800003c4d30fda69cdd79c0bdbcb229c13191001d95db96d82f501d325da531e5f78a981ac0e91472a8e697ad1958b756a54b231a23316de44e21d8a3b97605bb93861195d39dd137482131aee4f91ed84f24778d5ed151e2c6ca753bf340d84da504413644654c00c9068b8176e938e59841385bf2de0aea6a1fbb907c92f3b1e39cb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb6aae1986976055eedf282929feedcf049066f3009262265fde0e5c158b3d48635d519fb0c55ea95351802b3fbdabc974e4e8d568d5b10140ed43034270a8503	1633710714000000	1634315514000000	1697387514000000	1791995514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	51
\\x63147ecbb0f6a837a067442cce2360c19354b977f5771f46d66acdccff8200f62b1fcdc93ce66d5ae39b596430fc4bc7cc79a4a5962d98f891391bc7e9744142	\\x00800003df22aad4dd76aec5e503f49a54598ac39b69fbfd4f9572b79ef186acdc80e98c9883e013213067ee7ce1e35de428c726a2b7cbdd9a4ac3d7e707a03614c97e5d3388c645a620fd91e3aeb65989c0e0d5f228696c517dc4cd992ec0f8cc901da10e44a9f05b1217fd92635833674db2c9469d24d712d8c6b76d4e587e08fb468b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7ed1e06e44011e08e057b4e90afa67433ff6351ed56d7dade9d7fc9219dd7c38456a9f613b61506e2636d9280168b8708e3ca5cda02ef0bd2699cbb49a4eb70f	1613762214000000	1614367014000000	1677439014000000	1772047014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	52
\\x647817e189ddaabe55c2bdbace38078683f4a27aca8eb088280b7bbfc3f9c608db10156e92d9d44e94a961d4d965bd8512441b35757a543e23de8fb9dc3e93e4	\\x00800003fb08d6e0fe2c25a5ac637c7dccb62663f05855077d07e60473ccfd358177bcb484c4587e155bf122f618cc5f78556a7a8b9eb56d3f5016d7dd9eebae7cd76fecb6fa79e6d0a1f6cacfe9ed1f9c7e8a4eac72ceaac9b16e3c85622ebc0231810239c3a138ed848b2740f5a000cde4f592a1954a5cbfcc39265a04400df373d97b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd483721e8bf6cee4c95ab02757eb9223143e39cdd888dd4f64b48d97158eb019cffb29c8c298a5824488e1c61a0d7304c30217a5f95cfd1e02aaf4e69685d002	1640360214000000	1640965014000000	1704037014000000	1798645014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	53
\\x6a407bab5b34142ca37d01d68936013b680c732f37728e6d9305e10ccf2dd650662766effa5a7832aca9682a501bf379b27735edfabf541fa4ef8ac6213c86b2	\\x00800003c4936c9c3dddfea3f3ebca2da2bfe2c18205b00913d5d781f02ae67d623cc03a0b4f943500bf08e0b5746990b31c5bda737c9b51f330f3f62afa3cb68eff0660b968815bd4ce5b27d13f4979fc789c45fc3d85eabe8c23628c43060b6ef62909478cb1b1ac1b06c0d9aaf88cd3e3a47171268dfe1e22cc03d6abb1dc67d28419010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x59d4c68ef7b92cf4d66b5f3aa948fd43082f20abd69db35baecf9156246fe634a1455fd912da8611918f75dc94ef2dd50610ce55d9158a334e61ee34d68fef01	1628874714000000	1629479514000000	1692551514000000	1787159514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	54
\\x6a14a524c1884706ebe1b3412be8dfcf67f5432e6536bfd31834a27ae8abe7ae3e1e60843227733ff938dde0b60fe34c5ec017e08b9400fc74eacdcbceee4421	\\x00800003af2b19e70d0784447fbee74527f81c222a7112d4be4b50d5c69c52c1f6a7e96a27a817b097ce2375ae30506f4b7a41c75bd6c7e6adf4ad3878a7850df9b8d0ec65451d30f34949d9573f9ea21f16c1396241bf60cd2ef5c3c7fafa06eafa57016ec460aacc29d880dd55283c9f9f82be1a144e12f77f6e4a3846c7898dddc2dd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xae6c3b578751e9c4f191e0662756824dbfc09bac520d5e8fd86786874aeb47274f27bec6179a646dc5d0c45862061526c4729d4529957fb6348535683f8fbe01	1622829714000000	1623434514000000	1686506514000000	1781114514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x6b68444a523c90f80d855d0e0996610f104460fdad77a3cb0466c41893018f6feda8ba5dafc94050bc9c8d99fb3b995e79ae1bf89edaefa3eb0ff49f7ec103a4	\\x00800003a9d411fd1bebc6c74e22f4bf5ab5ddf1d61eda543da2a01392e72a4572a03ddfb55955e30417976bca2cffadc90113a676af3d1e9a2ac49ea065d0be1a1e9887802d93a404e84b892c6863993fc716eb46608ac9bb0c166caf4978aa33cfe1d06203a0831d901d76b9f16402e4066651e900cc1bca0c8158ee643636514924f7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd01fe0b4a92eed1074143856f73fb9b10bea17c5e540330977c2e65cc53327621745707ca1ca0f21623734dbd4cea31f2960e639b9c2de4b62e75646f1c04a03	1636733214000000	1637338014000000	1700410014000000	1795018014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	56
\\x6ed0aded603f73363fa38135fb2b0463b976db3bc0f34709eb09ba83ebd429742812e20aa1c225fc02adc4f81ebedf49c512cdc2ce8ddc3a44c943e2ca392735	\\x00800003c26da242db0ddf69aa9ea6588d0585e7a38bbd95d493e88bd50011de837bca8d3307bfad2dc94d40fd42a044f49919875a79d819fbfb46769e77d235be362ff28d7be70835b6edfd564842cec877a8b9862ce2e114aa6d6c11470a07707444fcb2016015cf1ce19adc3e33fd0b47cfa18d0dc83789e3cf5892fb7d52acc4d3d5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0f8cff4ac51bbf0be5c26245d5dad6967135af2b17d2d42f2f9955aebf88499029c9fb92ac017d54a614952a01e6ab98d5d16050e79bd1fd32d9c65384ba7307	1628270214000000	1628875014000000	1691947014000000	1786555014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	57
\\x70a8d4a6ecaf23caa25ae4da1836fb051f9a658ac9fa31ab8637caafeaf4fa7b4fd4a09e5c538511dd0c2cc73bf9674e1a62cc8c2bf875a006007b6981d735e2	\\x00800003c40db95ae191721af83087531d706a4e7190024ffb66bd21042ee1b15135a458058eb796278cd81f0b1fc257aef5488a409d4dde531ee7382f5c4338be73384f870e5c57193313e4cfe208ea3c1d6f814b461cc9c93aaeb4a6ece25d0b92641c34c9d75dab0d86c02565993e598158e67b6bf2e5847e26b0f38dc20617c34d1d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5ca622a10262162eb04042a270e79485ace9909ad8ed7f01f1413f1145bf9cc3fc8052191a81a35b536efccf07be02ad205f6cf355e58b1f1dcff13dd39f6f08	1616180214000000	1616785014000000	1679857014000000	1774465014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	58
\\x73d0896fc2d3261a39227e09806381a6ba9c976e117e0174dace7084dbc8a4a9a146b1bf0982a41715713c8bcbbe2ba9cca5a5a8349da3f7734f9f4e5e1f4c57	\\x00800003d63e472c05f967fa7f732d1c7465dc0b29229f67076c2a63e94e94cd2e0f658733f7708984d007afc29d065e995b58c63745a78117b80b2f9bab94efcc329e8146e79ec7afe8b1d545930cd9e99f3638a780b367fa98ac6b1bc6be50c57a2698903bb14810a8375324aa4bcea7bc9edb2384ccb30b411422a3277772692354ad010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x42bb87c5864da6b4bf986e5447feb843399934d4a8da72856e7157b50839e11ae4c1df94f5ca94566e11f3f0ce8f2ab411e4e1601c4e9d17e38f3f724c472d04	1623434214000000	1624039014000000	1687111014000000	1781719014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	59
\\x73d4e8c886acd5bcf4e9587d016bd12b2ef9f6b98b9ba7ee09da05970653c48f879b99b169f8eb1e81b743b074343d09e8c206bd36b62f40c27f524e7c05b21a	\\x00800003dc2a42fd21fea02924cb198264d642cb6ffe18846ceda61c63df32d4360523d14f48a9796b68cf29a680fdbab7796271a630f2a65578fbf361db2014ac7a3851b23db723466b2e77e009ed01f557df22d3edb56d8151903985481edb739e74ed6518abf09471777447f9da6e07b9de738dbfdff50eac04b489d16fbc04f53d3d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb23fe5b60e16dcdc48ccde006231fc3e35bede50e5735aec26e3f24417f5927d4d580a86345a9e470e5b8d095c7c8732c8f2ac439d31c68098dacbb0c0930505	1639151214000000	1639756014000000	1702828014000000	1797436014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	60
\\x762c131226062b30d8a8e91d7edf1fa7eefb4dc391415657f2e0c47a07eebe05338629b4f06124cb0e19e6d16d076dad7522e8e4f5ba239425ba204a57e236e8	\\x00800003ee3a588b22f455ad45f281be04979ed3c43590efe4fb77e5d76afd523bec83ebe4b872bcf80947bf97ccc56b4bc9b5882aafa654ffca356210674f2b2c42e1bf4d1753bd30ab95f90d8f685358e8d592e2286f5e799bb9fcb9364bb166cf334640f37562b588a85a087220f2a341e66bd61e870de534835cb8c0a8862f3850b9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd15d7f624df1e322b5bdc6b7d4b3b2c91853ae762ef08eb40217913e781f5eac7a722b5939287daffdb18fa7104d8912f014d727ee90ce3a56c74df61fc44f0c	1628270214000000	1628875014000000	1691947014000000	1786555014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	61
\\x76e02187fe4f31ce90895c8bf12e23300cd9e5799a0fc344454841359887b421b8c98604002200611b000238d4bcb3a4e2b428b986db7b6ebd38da28a1ff7aef	\\x00800003d5f7f5586b7c2d4b2f0894cb914ccf1d55d34d1b8d2d36bebcc72c84f3c1447d58a1d36a83af7bc116a5995f929d64caa72277977a1faf68efe09fa63e6859de13c2f6aac1fdd304b82d8a5ae71dfd687cc51e4e45cd4e3f551bc85310cbbac0ccdac14590740f92f2a8c5ba2cdc4697751eab54bfd82a925490ca0dabf089a5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x42aa77a24f866343d2fb4f3c26039c9371617567168e36ca50ac92c6938dca7ca178e5e1df5b65d8867cc0897fd84c0ec523982400180306ddb30dc0d4d81909	1614366714000000	1614971514000000	1678043514000000	1772651514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	62
\\x7d24297c2a194f5dcba8154d9d8dec1e45bf09e6f1c943035eeb12b3ccbc2476af9c336a7f1d9e68092b69344637893b7db3bd79154c991ff88bb28f31698dbe	\\x00800003c5b9fc6fbb19256862cba5690e3e0572ee2ad859c1e4b5576433d56b088f2d245d166f9fbeb6f74e8de535789e515991660a3091ad23e2dead1c0c347f28b1299c0b95d01312048281062f4c2f238ed7e519c683b01663704a956c53de405dfe7abce496a3f939e18b292213b6f4c550359e5930e3613844e4ddf97965d1c693010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb4e6ccf31769b8bb76f7bb8228a521026cb49d27a8629eb2158530984f56232b97b4ff59bb7c43cc75e90d7cbe0d4d4639af5f36b5668ee60b6c7584cd60b900	1628874714000000	1629479514000000	1692551514000000	1787159514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x7ef40be591d32b68b2cb4332b036b94495fed4474b0080cc8556e4ada37513acd9d4f9b6df1022739f9cf07500f20eeab8c61758e96974cd09089548565e65ee	\\x00800003d76c910738df1c564606f521c2216d51cd4411b2cdb7b3ef7d25cc1681a400c7fbe78534012c1a8e8ab883afbd06196ee3186becf0895e92691cd087b7fdf82f43f76afc861c1e07b9b7a6c181e1278f865e3b3fe71490eadae05ceada677a931e372cd4bebbee07453027e9610bc41a51745a092d0a8411fee22ebfa18ad627010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd79479dcb46041758bf1d7c454b7577b22c1cbdda784e15942fdf9b7862a6e684cb1e7ec34dffa92de3a6198d6023d1656adf8cbea7db09e1504251f5ff38100	1616784714000000	1617389514000000	1680461514000000	1775069514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	64
\\x8180d2767657f6f2a0cb01a4da3784d2b3640964b9af1910395b87d9d07d4f4bea39e9d720a8f5a7cc34ede7b484453d3f3d2e4054a6180247a3f4ced097703c	\\x00800003baf7d705eca38494bb40c25dbfa7cf1b887265d6902fa04971b948d8267c950f4cc916f1b8d7e116f1b31299733e6e492f08918c51eddc802f4586c84d1a48c074381b28f674869ccb979203e786fdd76754d2750d3aceb8778e65d5335f9e1ae784c93ded1968d540b67740a24d988111a875631e46d465b32e641401a52d29010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6199b258b63c3077d519a4856e67b271d0b3682e232d558f4431317619d7e52134fa05b81275ced0ed6cc310369fe31ecf3aedd3c39089c9360c265eeadb3b0e	1611344214000000	1611949014000000	1675021014000000	1769629014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	65
\\x8358445db7a1eb4ab01521ef4bccf7343acc755228284a85961df029257729587090dc152fa1b27fa46ac7c9e41c3b9adbfc1536bfbb8298465d4942f5517b81	\\x00800003a7feae05bb8f6fecf8fbd651e4d7483999526ed0254d1ad3d641e493d34edc65e22a7569498974dd17b7f03a2550959f268aadf2e174e46d7249aab2a26d1a74517df607b5e3226a5b15baf1bdf45f71c6690af2a5c908cb344d0643320e8bb2e438d2b3047dd20cc3dcd60d3e2d766d0a175af30143883be925019aba3c08a3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x205cbec48409926c3e42a6130b241ae0a8ed368a29b7596d571b89c8add23abeb336fa5d8f586c2c1f5f19893af9895fdbea6b411eafe6eb334623cacd75b60a	1640360214000000	1640965014000000	1704037014000000	1798645014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	66
\\x84d877ebc82b5bee2cd03eb4136ebdccb543f2387a5f6631db5b66ce69d3e49b65eb0eb5a3fce9f84119468aba8b69745491e7721bc7a06de349ff45e6c704aa	\\x00800003cbd49cb50858f81af89e30c97c7249bb0c2215f9142a6c1b56d2ddcf788761e18505afc5804017911b031a75933a88a7b3bd631bafcc81e8c7e00bf6cdaffa949539b66c4242a7906be04a760c76a6fde3b1ce6f7a7a12b9d2f226c3d52426b95a9b98f3d804704ddb4c329a54d72c6eda0a166b712c6ec5ae8e8c99686c1d93010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1f6f66fb74a1d4f75937552ecdaba75928c482d77462345b70fa1f7e7b6f30c1b0eb0f9a7d702bd486a11f727da0cec032c3d5d4311f9777ac3da375aaf31e02	1612553214000000	1613158014000000	1676230014000000	1770838014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	67
\\x857c19dc60527e1de7e2102800e61d7387629bb41f487dcc7a1bc02c5f97ec9e9c41f7e884c8b57bd85e380776fb2fcee592da4cc34f021a45cf377462c5fc1f	\\x00800003b742f0b22b15a2ca2e649b34c5d57ff0dc71037e02e99a5a96aa51ccd7dd50a7584999ea5be0d80bdd82d182917ea6efd9f303058c7b132efdef155ea77e403f8fc22ba1a834c6fd1ec35be5574a91fd660c74d240be8649547386decd54c1827931090a3f87a10f9c37e731c89c3049447d2cf3a033926f29136f1b99469bef010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4a6a532644ff86bcf39e7d3d9ce8967e13053d1ee50441fd654869d26c7d27f9ea228b63a9dc13c1c1163faa2c8b7cad18bf10767d06cb01ab585f50ac7eda05	1611948714000000	1612553514000000	1675625514000000	1770233514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	68
\\x85f46c7a48c428174db1366c109b740f64219865e845d4aeff9f9b3bef43bf7bd91d063780a44da623374a98cd3992a8db0a7ae263b2230afa6b93c19c075b57	\\x00800003be7c63105f87292cb7713afa618b2cd5a9dfed6f2abd5cdbdf03460bba75ad78c618a230fbce2bde8dfca86b77d2322c02d6df87b122047eb774228501066600644fc950d9476a30a4e9e4804ee77493667bf8d6bba6f45fb6a2da825d430768cabcf37613559af58e887868c80bbfcb93d7b5de78203d0b414d696c8150e40b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x532d87137fbc71d46a40fd554ec902b7ea305d4eedb998894293aa19ce9e6c06d1ea03a3c22744f94d21d2adf680290b8087e928f9e0b3ce8bf2f4e18ef3f904	1624643214000000	1625248014000000	1688320014000000	1782928014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	69
\\x86183a427da63f5c2f6a034351e016433f036e0996cc65a2cb631aeab6b5d78d1f83a09a1beea6b4e4b9284a93c27feb6f03e80e1c718743bb2ec890e299b4a5	\\x00800003c5da193ee16012444e0e0e015cc8de1201148da9e00d7c589d8951b3486fc97efece693839257db270dd27ed590b186dfdbe8a37aa41f8c7faf07de2f1edd7085377bf918c6f00b8dd996c3ef24ddbc5157367d98b4f92165e683e8f017fde8bfde2c93f71374b8a62987fd8ebee529cab45d9ad53ea2d78a4dee7f28ed3ec97010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc36ddb904e499153e9bfa20c2e604b0d29c144f61e2e9d854bb99620f83fa186a9908a626d32deec9b9cb630ff7aa1099ffe904dbb3c68a0350fc415457a5206	1636128714000000	1636733514000000	1699805514000000	1794413514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	70
\\x87083668310fbb107e5668f606aa3ca9c3e75f1d4b511350ba2fccbe0ff55063c3bc5e294d45ef0efebabad24152fd66bbffe44cef0cf491323586e92ffa120b	\\x008000039ed39b650655cb7c3f7fede0cbf3f9a472758abde8b6ea48e686ea4cfc540547f932a19f01f11a1b8866d6f20cdc6d49c7def11302f05b18b14e9443a1da5c6cf3c165860ca74669cd02df00bbf75552a6451303bf00434816a90384be82de151d286291706efe158c183778519cc664294f6b70e4f964fdc8ea6e79ab9adf91010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb241048d7e01d8abf42ddd22fa58943c0b86de7a6f7e6c30d261b9b59277ae9664f8f2e1b17c310e07a7fa53c0c8b9dc40d6577c2802b564d45fc2234f8e6405	1641569214000000	1642174014000000	1705246014000000	1799854014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	71
\\x89d4ae7e6c68d23b6816a37ec8df4ab409ea5b09d4f4d81cb2b3b23dd061f7ba7eb60b6658cd0e49c178aac9030d8539cdc4224e4eee9d3dd363088f15b9c9ce	\\x008000039c1d059852ca1d42e676b898a4365e89070f8e28e8625379b669b834791a52e6f3efaa551cda2f5505cefbd1aa655e7964e01a1eb575325595719449896fa2ca815bda206b6d3412dfa587eacf2bb606606b4e61672c76ca9ab0c22ac8d0dff16377a9cf1f7fdf29c54e248f072362937bd0e81f55d49779ca541defeace8225010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6fec8092afb74ce1f676e4335703f2243a2ecc1a36172f1296e13d0a4bc4f2a90da989fabb0c64a8f6851ff2d9b89aba3873ce8a05f7de91af82027a5a503200	1613157714000000	1613762514000000	1676834514000000	1771442514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	72
\\x8ccc854e3bddce999dcc73b94278ccca29e95af31cb27745366517b70c21b20dd71969ac1369936da779a78bb966792244c237363ca96b703c399e9485cb9daa	\\x00800003d72944e1f5457057059bc619c3adb723f196afe55fb7170f51c977c84bf4f4d55901e3e9107bacd9d9f4c0368176fa0872a9786eb15aeda1dbd93814d6586a346b772d51449674f4e8c01660e25da42fb1886b9ca4da9a76c1fec824b8fba64eb082245409c61f09206721b62be0a8f29198e46ae168e3e207d99cb40df5075b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x17df4575cf2b154d0d8787b5c17518cd1db8ecb6ded6c79cb4e45aaf96d3f10b058a0ce2112b284beee4755f5884ae479fc475a5f6dc0b9d54f71c9d553d2d0c	1619202714000000	1619807514000000	1682879514000000	1777487514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	73
\\x92acd07331f7b4c82b86d103c55bbe0b1b7fe87b6771304199529de7b9b61aee11942a6da69de9dacfa759e2e1d66c0c6720723d143716a94b8a16bcc4185760	\\x00800003e12c1d1d53788acf212bce12e17f29f4f2b7ff924178acfc6384638d20410b86a62acc969bb224a47f73ec70b76988ad347922e64d55b32e63ef54b8f425da1671b57143e172f44d054b4e341436147b868c3a59b478727d15ef86838eb783aff3625c50332c544c4b338eeaa1027938f6b5f5621079c0911e30213c61e31823010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5930d1318741a71a7f5fe466d6f501b1e68d13a5eca3af412397023432ed918c8de03e933bb573a35810920217225ef1c3db64f287e48e9fe57e3726db4d0b04	1640964714000000	1641569514000000	1704641514000000	1799249514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	74
\\x962c2a689c0329dbb38aba169b548eef60d84bdaa80085f2dffb48e62745d5ed39bae340c35dc5b5742292b333958507c6b468408c3831bbd372102db8d94d23	\\x00800003d15532eb3956b2ec2e61abd8b6d24b9057de2809ac91009d51f820150fc28a9f4a3017d131a3fa2a2396bcf975d5813f3786afc3725d075e65d5dfaf80304da60b3cff423b72e6c3dd30ae0525aed9110438be59feef90d25d3cd3daf06567331b2aa41c51fd083eb5c88d6a6293fe6d0feb4238ec30b23e9d451812e8779987010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0f87115b30a147c146787c0ccbde9b7083c8dfc44a81fdc8687169e9616baff62eddbfb566c1ca903725a4f4006b1305c52585165d5c8aa00573344aeb3b0d0a	1636733214000000	1637338014000000	1700410014000000	1795018014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	75
\\x9748cdfd25e6643b3bb589807c44c8c9eae5a46365e03be5720b42d78bb855f1ec754e50be7910804605cee398ef2ad9ce66efce7ab76901aa56bbf2cb0996b6	\\x00800003e8fe8f3daa9021348e20ebd88cab10bd845ca53f45435edb36aaf467e80f95d7eb738c29eed3ce248ce0da0481000940a0797619439d481a30511470407cc8735a951647704ff23ad44c3e7167c0ca3964f9e7a5085c3fe4a5c02af584847b9fd8b47bde0678405005a39ce3c2414342418940bcfd130fa1bcbc5b616f9f2b1d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x62bfc68126774cac90cbe27b4bb007623f61cffe6693bf7d1bcdd77960207fed89efe7af14db85bd363fa3fe5ba75521075ca197b9412f4174eea092e1ea120d	1633106214000000	1633711014000000	1696783014000000	1791391014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	76
\\xa30cd5803e7c79e612d24652c2d01ded72009d3e87602047bef7e64ad78e5e0a50021a41c7adbf3ca834800af52404acd4c59eea06a6a77f6220d036625c9e7a	\\x00800003e9013b416ec5981e63a6ce52be7993feedff9187c04c552ecb9c09a7b2800f4787bf1405777a676a30ab50cb977cc985ed558f6197cfffd88a0a02ae288746a3ea10c28abc9f59fbc97c281f3790f5d5b751c7cd342d9379bdd49be3bee43489fbddb2fe871528890a4eeb257d5bcd065862d8c634d9b86cb641724a687c3e07010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf370b3d41c3a9f195232e21208f14115f3eab3076bf6914278437756c385158e1d547e3cece62d3d9ff5f5e8e0d142412ba61ff94d89d3c4473f268365e59e04	1626456714000000	1627061514000000	1690133514000000	1784741514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	77
\\xa4487a82cefd42a99da563ed62f8da6651d9abe893fe0dcbc54b83157713faa82da23883c7c0afc5a9be378ee9a86e4ff86e6367d6ca9a11e65cca5428ab42b6	\\x00800003aa80e5e934c037c2b8faeb1a8d46925ef8e6186a061ec30ed624a3beceefe9faf4c32c852634eb5062b8c6ba2ff81b4f1837a266fea1c74750faa18ac2845ac0e86d6d868bfeb6ac45a6024f6125b3bd0f9847c07baf6eccb32e61a5613397546b0ee92db4db4bb35284c06f8b20ac2d9580cc4eba0bf60607ece41f766551f5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x16faea6bedc7b8b17d1316269f2abb834e1bc661d1bd611ef6c7079b88c10ecd7df10c96f96184e42a41d4997c10287f3efe98aa87b0d3be4e43515298169009	1617389214000000	1617994014000000	1681066014000000	1775674014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	78
\\xa71058dfb45b8d294a43043217be2238c64278f6727665b995e9fb2f1dfff53a503719f523ec302310fae6f973614d05c17f20d153700f2b6192f7f1e47b40d3	\\x00800003e208961dca74d0263c5b71748f64609e8a339c56907af34ec071b71552cc9b071950eaaf68ea1aa7fd01342fed82164b3b36a05ac20c9cc48dfcccb2e35d2f564f9ae69fb4ed5164eec6c8b5c8fc3f9e7cf215bacce426d92f0279b8b6fdb10540454baa72bb4cc624f6916aa47e6f9080f7089440c6628497a5d95a78326555010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4a9c7c4a6af9896f50b224d1ee7c0e3f72402d068e1212d20329db424733f98b3a8ca0f8d5d8fdbb8850505d7ee1db6bac8fdfff27794bfd19333b8d6f8de804	1613762214000000	1614367014000000	1677439014000000	1772047014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	79
\\xab1cd9747ab050f5eaaa05449d6fff6b18afcdbf66e544f2a4beade5d3522f1fe7232fa671d4d093ef3f53171eccd093c8e24713c384e8aad65416be5ef83dcf	\\x00800003d2eb24992a6b36592b3817874fa45082959a745b42b98cdfec72d59df2f3bf921728db66b09ade85cfd6edabc451d7f286112dcc2c397a79e83617353b2e8c3f8bd871ce2d12279efbdd03c658989d62db5a44e74ecfb50dc33a094ac9026dce3c2a2b263589058bc387d90fa055d2a447568ccdde8ce583043a95f7f3c68d85010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xac45bd57e303a3e4467c530a4f85f2f2a7fa6bdc9c67882054585d12b7ca04d776cda77268e9c6dabc24609f4d24fa411e03afefcf0c51f4b2f2aba6f8bdfb0c	1626456714000000	1627061514000000	1690133514000000	1784741514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	80
\\xac2856060fda4b05f8807607be87716bc0f8637e3af5429f725e57de31365aebf49c2d8d3527d7f2cc0c4ef01006840032fa526bfa9e74278d2208676f791d5b	\\x00800003a33db28abbcb195b8ffc114fe44732b72092d8477bef7ebf5fccff2900306d47121b4d9643c469391ab91a67d89cbafdfb00ce4167be4bc4b637c45f302a3f98d6cc53ab97e29509a072a50facb0f6dd5361c5d6324bc22f1090495195590632f01e82072262cce57fd8470e6cb3c2901c95f884afe5fd7ab64aedca4fcbacdf010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6867153703859cb442bd3ed0a9520f3ef1ac64e3fc087a6a9126b1d4fdfe50376921777bfabaf92c13aa98dcbfe24e928ff6074825782e0d9024f3d64c34980f	1622829714000000	1623434514000000	1686506514000000	1781114514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	81
\\xad489772e8b9256c1c659c591fadeeaec291de72c8cd7507c863cd2231bcdc6738697b440093b8296d8d85ef288fa96cfed56daeadf6339958a6b6ea2ab3d3a1	\\x00800003aba1283ded1a20e51c824fb638942c8fc9a7427f2e61f86b25607a9a381bea5ee191f6fc0b0d9e436f22fddb95f4870aefd0522d6b12721c92c4d66ee72ba633b129d4d40a9b650b12497c7f30e2c1807e5572a117149222a143b9c794c0f94895cd6ec94ce0092d47d3e3d1c86a1e463648102406a2d959ac001828b89ccd95010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa67fa1ae0f4808b225b7549666a4ae6b6fdb4660bb9883e2a9ff91392e7df499265efdef0d21676e933f7d038788101a051e3397b1fe1b582340ef08b21a9e01	1639151214000000	1639756014000000	1702828014000000	1797436014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xaf18e6384e781901a213363e41b5f14269d6c2efaef68cb93ee1e50ca978ef63846aff8ce334e852769fc7ca43bcf8cd056c9d8a6c28103aed0392afbf3386e8	\\x00800003cf5cc0c81eafcfaa6385df307e2da1daac58b70e30e0c4bdc195175edc25e77d75a3e4a78fcd93d251a2413f5795386c0091de6e9cbedb33625522bcc17b1bd2ee5c37c1133b4b03fc3406068d9b000b3a6d5e8ad67239fa0679fed89f9eb17763031d7a2b1c77214c91c98953304ca07c481fc8e4996f39b7da3c72a1785df7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4531f8ee3ffbb1edd1e50371ff926a32718871e0f352724e14ccd9675a0a5e55ffa733ad23c7947518a99ff522c990e0edd04d58218503613c7bdc7b7a89860d	1621620714000000	1622225514000000	1685297514000000	1779905514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xafb05dba0a8470c3d3fc541d38fa336e447ca86a4d0c210e0fa0cde82bac3551fec5a3ab6e774a492f14d9420decf7eb7113979c93c0efd1f497f1486e114c3b	\\x00800003b688b581ae439f6ff8a146bd8cebcdd28d22c363ec86dd3d7971d9fc4c107307703ec5da193c83a14ea9b746f91abeca5df7114b80388c263edfd02f22aa476b1a835ced856198a7f61e0a469d9c29c57c5bc1fd97384b291490056b1e8b27d03eedba43b8f615a6e914e02de864edfd3ae3ee6fe1f4fe49bbaaad4027f0d927010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x588ba5d348ddd67ee7a06e145bb0504b28a90352b837a0472d48e7810b429f9e491d220d895cae63f987973c22a6b8ab5d0f9d92452e48be9e7fe72adc4b2100	1630688214000000	1631293014000000	1694365014000000	1788973014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	84
\\xb15cea21dfe16dc30d1664e608441d89801d702c6cfdf37b48c007fa56ed4513efa5f6709389c0535fe8fc1f481719d372dc7ee8bf57aa200ab3f42437bc1995	\\x00800003b04856bf3531984bc98b929017aa1e123d181c4eb4cdc57b62710314739b51126e374d0afacd0700587ccd76a80ab22a4edd2a1783c3e14dab7be9ca84673d172b5aa813d7a21117143646f673e3b9b8aa02cf465b1ff014fbb3bf332126b17fe78c6a3d452d3d8c1105d970e39d0eac0ad6c75cbfb84bc61cf4f8c349815be5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc8592c578ec836a01247b4a6098b214a7e1fc5cd562813425baa2efce8382600c9cc262fdae1ae8b197b0b9af5e4167b3ed66e7c88f205f448730cc26ec52f0c	1625247714000000	1625852514000000	1688924514000000	1783532514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	85
\\xb248be1b803948f854b8b729de7be03ae73a1fc7fbe240cbbf8cd63dd7e93da567bf29067f611d682cd144c69454f9a63580002f96ffb0ac76ae42335ac1a808	\\x00800003d954398aa8f834dbf9baad2477a25658bcea53eaa8bce40df48aeffff5dd7b21b3e232d77869d650a16f1543d37c83d35aaa96d3d8e39fd9726c600877920bc22d990a0c4ffc7258a281213cd52803f181d89b3abc81d9e70b1e8e1d6f3683dc7345b881c9c169bf54eef10f9397230a01cb4a52bc2df2dd42b56df15596da75010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcc6d4d47c770e8bc25101282df01069be6ce5e15867fdd31f78bb16f7c776da183d34e8507888461b1f5445e016a698bec77f68976afe75ec9f5f36bfe127308	1610739714000000	1611344514000000	1674416514000000	1769024514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xb4440398f2641a64e607c1db346715a63227a4916595f98e7d55167dd978f58da8cb16b203355d704aa6673ef6c5252fe7bdfd549b76484935d34fea9a98792e	\\x00800003d5bc762423c57253358eb8be2bdfa7384a99d1d54ed05c5f3dd58735d94eb9a754dec760d944dfdf825b431f39f1a48964dafc09a67bfcabc37cf0fe33c104ce2ff3a4add8a1312688ccc69a190c827f34fa72b21f5c742ed08b2e5648558628d0cf0bd84862e86caaa69bc95ace017b16342661b3d84bac82bad1f3317102cd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7ca27b9ffd00caaf0a6d85a251f6cfa9c5b187ae913bd1427c8e7e96fae22f1e552cb5dda615df597f35285828c81e3353462a083aa379c84375b98a1a064307	1628270214000000	1628875014000000	1691947014000000	1786555014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	87
\\xb4f8f619961e2f0ac0da0fc74abd44ec9be6ea2391f73c3e1ee56548ebc61fa15352085538858db7023ee9e4c28d542a73d3a50af8894666185b98cdb63c5559	\\x00800003afb416b0516349a7061f9c82319b680e4815040b77db8303e5ca8a554f7a692c3f086514c7976a8cb2eef4ebc6773d3b22e62a0d832bab8f42e23fa7eef18b1d6e889b210ea8db05f43bf3dce6a4cc2c92ea81c6adebf92ad782083cccdc832c3f993e6b50c50af425985d2af48a7732c4926e8f88bf0da146f3473e43ae307b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6509705cc34ec2948363efe04996ec9872060ce406c1ea7fb3855a40bbca7afc29bbfeb6aea0222837a2ecf73d99e64aba04f0637452b91e3a733bd79f7e1a03	1614366714000000	1614971514000000	1678043514000000	1772651514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xb79848f1eb4eccca4f5dfe014a6c7c77336bff62bc5e4c0aff88046c83f2ee29d8469d83553feb25f972a256e38131fffea63dc3132288c84e4aae3a1112f006	\\x00800003c18c35d98b1b0cf26cdec9babed4bdad0329e02007722680bb5e3e6c1367c5914b1f362b52de2c71ff800536bfcfff28e3a5972746e0f47274430dc81dc9d23a9c514d733c7c9c1d4fe0e1ea01a472d65a72fb0a03fa1c160bb918fd4eb09c72f4e9f223bde1ef7bce8dcec5d12d5885f74ff7d0a64d9647d24c6abf6933f7d3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2520976b5d83eb8f04d87fc57089c8d08c7293bff641a567c38a61c198fdcd678a1746952a84e1bb7c1c98b4a682a705676d6942e9a19c96b90213de4fb9180c	1624038714000000	1624643514000000	1687715514000000	1782323514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	89
\\xbb58d4cff2fa04af9fa1fc1b4316f859b4f07b05a4f95752d85ebf4acc066867fde21fc76b0b47d16eb34d7b5e01f1427dab314a9a9ccd678ccb82a6939afe33	\\x008000039740ec155ab8578a9301dba47dee9fb76bddb009923ee0396f8d503c2dd9b00e5758a0cf439c6befa027e84051cc0a4b2021804ac905fce606774f210847666cb030ccdbb133abdc392ce107f2e4c1fb02ee17e847cb6d57ce13308b2afbfd4414146ef89edf1de37f1dde7de388ea282a63d21bd2fdc86993e1ac33c0b2bfa7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc4dba3b25dbb8f348e8ad4f9b171ed4612ffcc0e9ce7485ec41bda58239e66a6e41575e77146857be4c5f7e5635afcccbbcb16a5289936884d10ba2f7cb38103	1621620714000000	1622225514000000	1685297514000000	1779905514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xbbe8432ab7ae827eddd71eb61cd6932abe55e15cd3c420793cd88b12027644e44cf39d9f520dc23e7c2349adeca7e4ac8411f7c22a095c58cc589ca424bb80f8	\\x00800003c5bf21fab837dbb3d8645ce026ef7749e64c20433793770d2acd031115a1d34cfff3a736a1ebe16766cb2f4425d1d1ca2c279e7da7f7e812016d6dc19db532a0091fd10ad5611e9b8c64e26cf21655e60fa19a1280eec1478efa2ca61e347cb566d27c5c7b7974222e3b8ed70e18c4495d216027ce0baaa1c9069bf60f9c7219010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcc65e6282f659f1ac44a2101a9d1577713da00b23dcbd13ddcec83a6d715cfdeb099bb25c37e3fafc4036ff49a899298f203c77f72ab318576b8ae5709e31301	1636128714000000	1636733514000000	1699805514000000	1794413514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	91
\\xc124059559a81c17216ae747689e89deb6321066836fe3b1bdeafc58f5dcb0ea7c0cc35309f4a6a71371d4d7d13e7c3cbf2969247f20af593b4c5ddae803d0f6	\\x00800003bf7a81b74d874c6e241c53c3f507a8764717baff9ce9596c3809c99cecd396ce7ee79b0289cba4c37771cb2f9197ea356ab7751fdc2a7e3e17c0f3401984c7261cdc3c46e9e3e956eeefefb09198df190601bb184a0d52e6f739b9f26f29b281d7b5a86205451fe0bfb012d0296739896961eedcc43f5f15fa3069955e2f4219010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2ef70bd576fc09b368ef58c0dfb4a4dd2618386b173768598cc2682f697c00790f65cf9d1a8b8905f336e1616ed3fececd13a4e5db319a6a223d7a8e8878820a	1617993714000000	1618598514000000	1681670514000000	1776278514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xc254a91bb60a5b58b08ca7ca482b1ee36ddde280c058f48b3173dfc4bb5e688db6e8b8e6efac9100dd0d6419ff1bb3270f71825cbc245decff6d6fd948895bb8	\\x0080000393354fea56bb1a90bef7aefc8bb02538445fc09d2587423b919b9647b627b6c70067437880d5219044a3fbc7ad00649861fd7dfd524f23cb95fa6068cefbd32463f93fff8ad8532448e8eb42e22b982aad2288347ab9295c4b6a15c05a5c7455d03844195a0c6edcb5717fc836173a0d058a13e8383ebfe85b1193bddf2f7515010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2f51431750907b519ece421289f4602e9419319b4466f27c8b83add53557647efe68f39f1709725a3df601ab19a20f9480d3ba070d2a9018eaa43adb69f9f30a	1622829714000000	1623434514000000	1686506514000000	1781114514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xc54059324b54cd30af54e11474e01378b3135ea4ada3435942a9f54cf19d19b6e41b36468e9c440182079a6bc27c3d7996cabfdba058d693e5c07b2ffd81dbfc	\\x00800003b2bae650bb90bbeed901aae77cc0b6ee89c5fd5c6687af5163e16de4ad832fe70cae3f8c3d05481604d7941566db626317b535d77e56103a5150b7818e808d3d33f8873434c26ac1f0ce25b3c18b3aed59202017e910ed316cd7a5a6c7896d4e92dbfe2b968600ea0a79270c9ce34bcb2a6c772609745d2b194ff9d5e18d8653010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2e514df989b0b75e1960347d7f8e91f2aeab31826d1d510ad498f1a5e79306da76db1461e2f43d00824d6947357cd6457009a4a64e112471b5c6893aecc67b05	1634315214000000	1634920014000000	1697992014000000	1792600014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	94
\\xc6f8665bcb9e898accf33b9dada5ad06a828baba242cd66794545e1c2dd9987efeb977c2dee8c56ea85a59aad498831a1fbfc0fb49d2d27be20d4c0de2a62727	\\x00800003cb86103f373698028a8bfc2ba9b896f5d6f8a2bca7c8312cf8aab58d6ead703d1d70d13e834a55636cab178387ed635733519cc0fac20875a8c2013b377fdf5c10eff415bdaabcdce37c1bb8cc1f6e637b74882ab647696b388f3ba6ead2b7e672776670cff026e1651d015c7b5665b349e87587c5cbd212a1d8291964291f4b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x07c80d6187b3a1a91b0f4c4dc1fae014de7b062a16062cd506d107c899128b609057a328031fb0f969d1454205a2ef713a4749dde0e36cf96dc08ad2e226490e	1639151214000000	1639756014000000	1702828014000000	1797436014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xc800a3bb89356b3182fb1c184a2dafc7bd2634a48fd6d5d0c0f9f7fe90d102c7e4d15469cd375110d89aa96b0cec7ddf5b1f3dda0ea0ea9646f7d676a8e04579	\\x00800003d976286b08f7fe045e694647050c3cce43a1e121f84615ddf26c28784d5e72d3090f38439793977262a3e26566b75286a3ddfefc1ff71b47142dcd2e1e5f606eaa1e6e47b577e2b669f7cd076409ca97d883f7195d4d7c60145cdd53809bd4ed19b0e5cff816a7ad16321bf61db999622baebfd04b19c7f6aae9021eccefd0ff010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x301319671d48cc3c1e993e2626d8c7ae23f3220af735234723b0b3c6379f0b582fad40a875a89ff45d84f089a5572b13a9762c6b37dc61e22bd536c2a0437709	1630688214000000	1631293014000000	1694365014000000	1788973014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	96
\\xcca4f96d9d2aae37c76af763ade75cd4ee9a30f974bd9c2c2e255748cd8072e861d677d241a44a954ae633cd56b02553ed73323662efcc6a7050489e65432f0c	\\x00800003e0a5f032e7688e7735776ff96157b43f0acbe1d41cceda8b31b285f6fa9ae765ed765785f9623461a8e943008e9fbd3489b0a4383457909a7fb84d9b82db3c20b65955290ac0c6f202beb32ca45612fc9772985b5848c8ce548617f185c420ee4509e584a574a3d509bb7087556c73b7edcc815c0ca00ba6d8cbb48520486d33010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe9370f385caeed96d62a45aec37af48f060d7515ef35719a83bb7d9bb2a9b074c9ce3c09f9c3f476d1326ee112864a889e9da3f259c8d01cd1559578fe018203	1621620714000000	1622225514000000	1685297514000000	1779905514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	97
\\xcc7c354b4f6c0e4061e66bf1e3cfaacae18d71c75e8b3f4da0428131a0600d1a5616c04f9d3f1e5a060975d14e7a2ac0f254d8fd482b5863964e9d71e04685c9	\\x00800003e363073271f296bf50644c1d8e552c7d93f0a5c9b2e037eee58e71c3bd0b6d011f06d2d103db69d36a042ad3ff8546c42ee710305e8fe584c0d3bc1695dde955d01761870947681301a181e483921d2c42e78422e305dc740e193d1c12fc26ac01f534c1710d5a2872913fe141b9c453c09b519cc8c596e5e4d86f07f8ed0d1f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9029b97823b52d8aff706f9673bd4572f502b24bbea3382865703bb25d978ab4b7d7da55799344964c6b5c87ccb028d1730ee258836a5fa5c711b980147a7c0b	1612553214000000	1613158014000000	1676230014000000	1770838014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xd02cb2dfe30a39bb58c7c51f36b60257842b6099cb88fb5eb9e159d42a751642b9361a9cd21c3d862069f477e802fabf96a522283b9e3e38ad771a3286ea5a6c	\\x00800003e2a48c541fb35f6e0fc121a87b4dc203a79dc39ac3f2d2b4cc07d9c583d4b2039807cb517308ffef96875f453233c304d94ac7b98ba99be69c9cac1cb24a063e0b82c7349c77701a93706dd83d4cc366876b9cb0b07f2eac68a2eba1aa177106f99b4281340a81fa528e28b7c1449c1d45818e48b0248428dd6cb3387c265fed010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x56f93565da8947450f00899d9727f4e13ebb71cb791e85e99790a48be86bf6ae98c1d7b9a768e4fee4719a614507e8dc3cdf7a9fc46c91a9168d9ce62bf02d09	1611344214000000	1611949014000000	1675021014000000	1769629014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	99
\\xd3d05cf38fb23eb9a4d54fa1c73016fa5c1a7c1fae8a043a7f61c970fea433d78a1f31346ecb5080133f3e10d0cdebd1d009e0fcb6647746231bb0931b96c447	\\x00800003c3ef1a6d320cc90f9dafd612ef2c8da983ac06aeb2d268e75a293c45ce9de9cbe6b8512312bffe1bf7e97086240c4b71d72b197f6a726532eae9520186d3987684a0fb9c8d2157032f051756c08d0e6f847364f94f8e218aeec5a5c294606a03a4c8a9d1a2d1392cfb2a15cda9478f95c125366904ea8197249e1d3170e6395b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1641458837b38fd9dd9096eb4ac44e155fbdb46ec12c71a7f17f2f362f71c8dbb298f12a9831257a24439d44ba3e8300c120fb13b908c53d4a9689462c614c06	1613157714000000	1613762514000000	1676834514000000	1771442514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	100
\\xd3203ef36a6841af201ceea933abf2d507e01c517e989462d3f146494f46ecdeed7f296d2f9a9fac4c03b942fc2c9615f8ca0ba0795f98d97b211adee66368fe	\\x00800003bfc144d74d224d966e4649c87f3365fb00202f94d182c095b9c9ba61d33e836cdf75f9762a6c3efc73d958e5c3d763d24f738fae11cb969c5d2bfbb6e19f8629be08264864de00fe17a3344912d274a78a60ee6372062272050b520f34f766ac3693472a14252fb73467c75c1355b956e75f9d24730840682750f6768a82e563010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x556c0c6445de4a9b82bafd335e68f4e312d02ad5bf36dfcc8ebabf7dd9753bf0a6194c71aba1354257e2fe2b548b6b0180289eb5ba2a17705e0b74e2254d7d06	1633106214000000	1633711014000000	1696783014000000	1791391014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	101
\\xd48865528b7b8289a10339baf757795f24a14c65fc3669084525e41edc054faefc6164a16572105c70ca51c86e257bd8052f5f0c2427b8056619c6087fcaa79c	\\x00800003c6c6bd9485dc1ba9672699ba58cc53f6798170453f3dfe673016883428d2f6cbc82b6ade315be0a7286ae94cba8aaaa2b75428ab82781c0629c3561f09ff055b48334f71e4da5335f4b0ea4fcc934df44048ea1b4ea6c8d2e0f71c3646f81eee767660eec09dbc26da413816cfd51faddc93c68b5fe200614aa418d4adc77231010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8f0f63eee4a7ccb2a449da069513dea060b08f050e23dd79270675a700df0f6930ca413fca2e98d3a922d74b486ee7a0375c47a32001e33d983c523b33924e0e	1625852214000000	1626457014000000	1689529014000000	1784137014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	102
\\xd8b8b14e1eb01b1d7d5dca822d6502a56cad2f55d6a9e945e283e320e34bc259176e01d6894ba2443abd75f27f1634dda13903ea758d56a92e9e4678d2b6c37b	\\x00800003c53c2aa4279f20d9ddcacbd0c73ab255a531e3a3ed1c4b7be18f2f55e168aaf25f4b1173437e5c527a60472c304a09cdff95cb9adc1044d547f6d0374a99236aac4b14932cbbe6cb8404def70921de2b000df054cb7f35db0251fbe949a8eddf7e7bb3ed54faf47fdc9ed12d618346ddfd3648ffea59e39afd2b93b86073a025010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7d7c0de1db15811baca1f8e281ba7bd38a6a9334942c1bccdca14085f712bd92794d94cc4ac717dfef4d284f9603316e5c2f086d34c7a32d2bdf666f62475007	1641569214000000	1642174014000000	1705246014000000	1799854014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	103
\\xddc09eeefb3d51e9682b695fa99fa91c7e05187aca83fd1f7c82d8de36a0ba3e3cd1210f155f530b7283aba0a86ee45eda91e5061e4aaeba3eda0473a3976150	\\x00800003f3e060abb569f2f99bc7c8358260b54aa59397a9a2037d05fa5e765e885858596682a5517afdeb49cd9be197291876b0fa17605d453378305071c6998368b80e99bd479a06a5c34bc11f93b35e8450a56db62c4cbe70bd50456be5ae859ab8c726132c72fce57ab055a8cbf1d03bbd511dd4cd410a03050eadc34807d8c80313010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x48908d7b5b9d954ab70b8d09f12857bb0a9b5217f5e5a5c4e2a7b7cd48c872040170d57160e3c92ab517d8d9d3c2f3a2119830bcc9de219d47f88edab0b24f08	1616784714000000	1617389514000000	1680461514000000	1775069514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	104
\\xdfe450c9097dd131e785ee25da1ea4775fd32caed8ec7f5fedd36be78ea6994ab056e78b95b2c929e5fd12dd3478f417f0bc86711b0d7c54a2d29fed91790c23	\\x00800003dd1a5c335d0a5922799795691836becfd7cd39563418f76315203e12d2dda4c53f1a806eed2f624c9f0933bc46909bed324e1f66b83e8a9d933944fbccfd3656479dd8ce8f2aea95f82325a8605e5396476250ebb5bcb91d4148b6a2f2776082571a1d5e20cf7a50d771e1015a08289653f8db3d30438c68888472ff8c69d917010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x330916875f151d95739459502e352cf279f93664173f2606aeefd02cea85e16446fdb2891907446cccd54076057952a9ebbb9ebb0a8141926271afc1f575b203	1630083714000000	1630688514000000	1693760514000000	1788368514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	105
\\xe0a452212a11c0181f6b3798dbb46d3143ade567cf57ab50f8366fe3d1777aee80260b5a32dec0ef992198fe02879adccc026882776f67e834f12aedb2480efe	\\x00800003b5c903b84b8c67b5136e68aa551518866b4c3652e3bca21efa07c260ae5ea656cf2aeddbe3bfab89924d5d05ce1b07ea8c822d6beda5e3d56d7b8d8776080ab63d0ce5f652fe9760c51e06686d4c6dc248f0cdacf2b13aa748097ea4e45c9c26970f3986c2fa8fc306c0a8d291cc5a4b322f54ccd7137cc1696e142015e24a7d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x954b18b4c6f7ac170c5cdc5736d4723a13965a634cf95c8250e6a28261087e1cc3f4270dd4f1633d730a948acec229e3b8e67e215858fe1117793067e9b94a0c	1639755714000000	1640360514000000	1703432514000000	1798040514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	106
\\xe68cbcb9dfdd0b63dd3c44d24b10ed6e4ffec4f63ea5f41d60eefceb0e71c25a9ba74988d7a8ba497bdb7ba0691157c8a9516555f14c4a533de2eb97d761d742	\\x00800003cd6b68d14e51cd3c52caad6ab9cff988e574b9b7f7d2d55808e0749ac8fa00ead4bbb3c3b71e9a91fc8c976f6ffc9b648bb1a6032a7223f0fcb6c013004785f51a314308250a4ca1cbe5af324dfaf3ca0da7b2b69257d96a46fe9c0c80fd88170e5a8a2b122955cb6900c3da27a05361f3e4a30fa6e23141e2f6faa428b4a255010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3005a1e735b005695b131bae19a593995e26a8da14f3ad225e48cd2556ced6c391be66f6067ab94c53b4d4204c3bf27ffa84611f203a27358581bf5f48f09d04	1639151214000000	1639756014000000	1702828014000000	1797436014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	107
\\xe60046ef9096b01ba60b1971641a2cc6d051b52d6615c290b3571ac9c2c1e7cfb8da1262973242fa7c46dda5d70c0e4cc1e29903547448b92da16a5ddf80b07c	\\x00800003b919e6a5dd91bdcd61853f516140ae396c88a6a1d38eeb28a0cf6f17eb3c01300ff461cf433f100bc06e5f5c209b9047a541fa3397c044498f2c902f634a76d474a4db002cd77f931664ae5e968ff66228279b05ebfb45996c6b54abc3b05c690782ae73969b4bce6c61e0ca48c427b79d1229da79aef072be2a854b493d1609010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3568f49d56f6f593d77ff1cf19e035dfa209aa60463dfa7d2afdceda8b7202d952307158cf4f5e06e6208198f382b614d7d5a8203b40cd188408af8eb9518a00	1619807214000000	1620412014000000	1683484014000000	1778092014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xe84008046a4cd0adb6a75e8157ec0a912b0af1cd54cd5fe6e4e48e3cb9d48730eacbd1f3adc8e6d54f83fd06019793911330baac3eb0cedce68a66f9bd452a1b	\\x00800003c754910998ad8aa5cd861e432bd6153d7e11a108f891d033b91df7b223a4518189b31871b931bf5286a2da751e34c1db9ea84682a55b6c7d9d85dff765bf5fc4e6f47d34ab1d1d09113f78ae1764889af8738d31edcf1f6da26021ce56cb200abcad2a5cf25110a2a16db551bbc2a2e57c6f59b661ade36276bf2eefdd9715e5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa46363c4aca39bb3e4c163152556427839a361aec0a11c23a1313f4f6d8118b48df2ce5fa1e3ce1a14896e1bde94f0d79214302d19e2e100079fcca2d4193e0f	1636128714000000	1636733514000000	1699805514000000	1794413514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	109
\\xe8e89d573eb07a782fde38fca83cf489d87a66fbbde593bc94678e86dba6a4ba29b16a31ec25de674466268a741686042bfedd3459b03e794afe92893fc111af	\\x00800003bd82fe4ff5067a71aa87ad587daabb1c7fc796aa037e94f24d36a2e3eba44c7edee429a9b4af27c37b7697e5bd8e9ab0d077ce3e915c5ae2c876a2626a6f5ade54c2650703078ca1b9e3712194a29b0064fc474b8b2e23832c4478328a58748f8b722237c8c3aa7c8485288d48ed35a4fa4979972158a0772a2e34f3f5edf035010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa86e02280b8d3ba1e2f95fad5ab78eb880801fa4ffb725a72e22e9101c7c55b42a62495c0c947552a139d4a3b2f58d13da62f4fa4a6b898a950cea48b7fe8a02	1626456714000000	1627061514000000	1690133514000000	1784741514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	110
\\xebbcb1941c3c3abbe96683975c6db4047d09fc6aa52493b30d5690e06f773cbab5ba7c03551cc5aa8b3727be22adfbe63ac29e477deaf601fa11327ce6bd359e	\\x00800003bb2f5862196548b7430d56e8f3d544ab68d400a1fb1c400ecdfce474db93d8b424299ff7affa4d073b2192879e224ac45a53c6ae4b40732f000c4818097caa11bb35950d70b73870627880e4a751301c91c91998929837512a4a556b3c98d21612047db1405f30142c15c50e036f69c768656f41666938fc74bd3e723c41e317010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x06864d6b4fa38b71a547de9c4f3113046b81c6055692003eb210c7979bf97a54a8145da6bc3cef394248efb1f087663aba65f3258cdb10c0a63e93a65f05d30a	1632501714000000	1633106514000000	1696178514000000	1790786514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	111
\\xf0900b2b797a7031cb33aacab6b4e0112b5777d06669db424f483be093dee73a9fae5e2ef7ec0129a13c8aede3f2d9070d913c5eee9aff953a5dc1907863c751	\\x00800003a05575397310278025a259a63fc1df1a05caed48b1365bd2908e9e11db39844a20cc9c14ad8fa027032bc5fa5d3d585d16f2ff66c1f75cec7c48951a76b9210e3aa64cb1a607f316300c8320a2fed23316fbfe548cbfd0c44495756aa51122e9da64b5a5455fafbea0c8777db3edc0ae3d031fb5df890d45f56100e2b2f91083010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3e4fdba70a688a3d5c13580ffad369096237a5a362bf93a556d73f9581e746ae059a0fc15a81d2775048db8e077f93ad26761cea00b0307ac18e7cafecbf7b09	1610739714000000	1611344514000000	1674416514000000	1769024514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	112
\\xf33c6997abc41d1e2e8e37f937d373e90bdffdb11e95b7046dbce576664b05d788a40ce2d0167dd736f859dd6827b32178bd693d211b39f0afdfd13c9114e194	\\x008000039fd5cae5645f7174138c502cf81969ff1f8d6eab474cd50f1f83b3b3e4c423c2874b7af7e7a550cd18c2494f231a7d7eabe85bcfa43588f2ac9659f508015cbaa3f0c4adaa04e79c609d431cde0e8a9b6d796ed3a8c21711ef0b5fad5ca88d0056c0cdfe975536cb8e907dcf722ab4e3e7c2dd6edb224b87fd223972316d7535010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0f12cc17cb3869895c4b43d274b0c6ad6c8a520bc6feac7a565026dbf0ab6759371d1d012d9fa18c4ce0fa14f9311c514456e0b0eec66f548c6df6a211fb3a0f	1634919714000000	1635524514000000	1698596514000000	1793204514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\xf8641449d595b1a6a6d3ab347b013084388b8e751bc6946fb1271b536e752f6a341e569f7f9e087d074f2902c020375cc8bd97092d0d6384d52df12e510e75dd	\\x00800003b806b15ff494d973c0a8d81189d3661c0f678d0fcb2aa4b989dba3ae5e4519fe4301bf6abbcdcb45b437dc183a833b0ec8f2d1d7c7b4877a6025b5d2a844753bf954c769ddb980a6947f1a9f91157797990a8584018f3a6114b318ecb85546cc8013ce76499a67b74e0f3f1935901ee37fbeca75eca579383b51acdaf24ec6c1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x365eb1e6570c921df4cb36c7077e222c0ecae097abdfafc4f2a7e9ee6bb5b24fce4d0283ec705977986e58fa753d31d2ddf4b2759f1694774598e06252ace60c	1617993714000000	1618598514000000	1681670514000000	1776278514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	114
\\xf990f41c2260b510032311628c0fea2e2d991643e337b1bd072efb0764ad236a9423d1ddf4157beeea14e451c8d1aed285a47ce724e99a67004447adcf94cd8a	\\x00800003b574fa72c250861028571f73e18ef3616f497f2cdeb3025388aea17eaedb0cfda027e79c0c396a7c19677e65349d9854dc96667607b7f917a43fb71cfaf3b570196ffb5a1a3fdf4d35d91799abce895fb5b8f14ef861048c208c14e4185b43991812b0bf84276f6fdc92420ff6cd7053a7480b95d191ae5b966e28577bdca4d3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x58cbb550cdfdce713ea1d4bd6ffd605138bf94d2c63c221711e5fafa6b518ca71df13b479e25f6f3893de9a75c36fe4822254d5de52fbf240a5234582422ff0e	1620411714000000	1621016514000000	1684088514000000	1778696514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	115
\\xfadcf12219f07b649d598fb78556aca07933b957b74d9f720a3df012fc27df375786b6e39d03b15656d8505ca80ad62158d63c46012f8f035cc4633f58bca51e	\\x00800003bf984f499d3003fd65d4e0bf37ab1c2a51fbb0f5c1158c75f7b51626a29176bc51c72bc4dc87903900d9e208cc61dc16b86010c9e226c7c61f7ca0e6a207c042bd400b4f6c5a7d91ca39a5fc054389022e2ed7ea2a3aaaa7fa1be9a320781ce1d820c7cc97935919e938a17535a6d0a26c56ac3777782123b126c46b43827c7d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc05d23b43922fc162599365b564af52cebd3688552ea356adfcf2864f2f24d76002c9846fd292edf03cb5eb0eec5a359726a6344776ae9abc5c8581a8d91fd04	1620411714000000	1621016514000000	1684088514000000	1778696514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\xfb3c9b98468be73acf423c32f974fa4451bac6b715821dbca63145d619c15b4b3a211a637c7310bd8090e943920dd217bf53ae6961d6af3eeeadc76bb0d22208	\\x00800003b9bd332a811bc4a958cef343e82c9cba0730bc6e18cfe5a5c7944ec800f12b80296d0d267d24a5bb03584fb6767669b505f521426fae00d117971403ba7892115c183e5969c6783829955e2f17437227eb3e50b6134cfa78c06fcdb676de82b48554e46b5e99aed0c9574d5b5164464b1acbf4dd077eec7b8f8b34895faac611010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0da940a7cb316f955c41d620d794815e139463936cf14bc86930851e9bb03b03b31c6ad82b56bfc2cc9d93caadd9b50dfa7cab54cb5ba94c0399df41bb3bad0b	1618598214000000	1619203014000000	1682275014000000	1776883014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	117
\\xfff43db8f67b876256148ba5c1668538add3adb34c8f01bce8679606b54885af6e87ee29785b45a13a005e1378946fb32590d92f6e88c9de4934b85f0f15e3cd	\\x00800003ad78f9cc119942b0ff1a57e3398faf8e5f6091e0c5db82b449006a63976d43f8e8849fe91d71c9665d5a8762b3e13c3822a540ff83668b07db00bff1ac475d265676e5ac6dd7e1ed08bc4d80227cbeaf62dd1dcb1c1656470846ca92831ccbd0deffceb371e5d0566fb6bb6340d413b4e9a858be413861ad888608ea6d527bc5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb287316f282d8b9cfe95de7be3c0a44511e6ed4c1572cc99202e9f33aa3d183b3149a06ce73e37db2102cd8331493940b7ac6f86e7549b22307fcb70619f1a06	1619202714000000	1619807514000000	1682879514000000	1777487514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\x08611833dfcd5e41500216d86761c15d0e75e183ca9d464813129ca6d27515f41f3fb05c81e4b20691a6fa0868439ee6bc48df900c9e06ad4e1d33d45ff1eb02	\\x00800003eb04eb63dfb1dfca48bc7ab9e26a7188dbb6bdb8e04d0d07e4066effa14aeb69965cc4f15bab8dc2ebeab9be54937019bbfe248681b4ecbace187f6986cd43a40b261c80ad87637442d034bf55753b78a4309c173ea7f42f6f23725c8c0ec629f1a8a53eb140eca30a5da9eb0f7f5c03875ba07e3ada88f53f5066320d320b95010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6bb26240e7ada91c435080925eddc0d8dc4bf8695cddd9449e4e58b57b1248d4a3b3a4e68f345882f27fd441ccc19fd577268f2e5c23bcf210fe7b6b5ac63307	1634315214000000	1634920014000000	1697992014000000	1792600014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	119
\\x0b79659cc4562312c7f61f917e72098f028dbcb237c1055a5eff5cdba9db3de6547dff98b466696e3b3359343454d564a4a891a1fb11484051c4d28774279651	\\x00800003c4d6e48e09359d58b532fc776210c44f05371ce04324bf0956ae5c86b6e6ab02f5319ae7bc94235f9f2bb8f227370962a8d10f52712341a52db5ceb304280446e68bd30cc72376d41058bda7bca5acd18d7ec21c74ef9813017072b0ab34a03b3d44e60c0ee6be4f439a56809ae6f6dfaf977ff18693e9ac9f4ac48de84697d1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x35a7d0b9e61692ea46545d0f120df6432ab63a473ff1c80d87fede7e70a04e3a267956cef7f599bf37bd56572fc17c3bacc4b5997f1dc3f2d49d97416552430d	1630688214000000	1631293014000000	1694365014000000	1788973014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	120
\\x0e8946a73446a319492b5a66959fbb60b4b3f710a580739d1bb9daf2d063111dea4dc7d0afddf1875ef07bbe8d6161886c9aad3c90656e9bb8059044598f142d	\\x00800003e451a2ab71ee7d3fd2a39e8238775354581a4c322a6dd1aa7bd1286cfdcf72c420bd82f681aba50f0dfeca9cef966678dc70f14a931fd6f047c3b05b2d9a3da58c34b8d0fcbdd923e69ad49af8ee5f15b7758a8bbf3febcc2a97441d879b396fdde14c0ec799316f888f9a48fc3c9af8dd2723d611f78317dc06f6898bdd9d29010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd2390ba9f09777f7a7341fb392ff891a6fde4976f7bd58d8b2b0611bbb6dbca11fdb12984bbbe2ac398210809a807ca043891f049c90ddcade9f8be80af1be07	1630083714000000	1630688514000000	1693760514000000	1788368514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	121
\\x0ed1894b7d4539ff7cd87d5d3d8180336f0d0bd7e7b69957a4099203b4bde82dc0e2bb8c2ac75d9818fa1e9a3d12017ca14a8ac75a6a53ab5fd8385690204f11	\\x00800003e42589abfb2270326bfbdf4aa62d911aaafdeea7ae34dcbee9fb022abcd230f37349dd2dc0e10a55998cea21bc6968451ca3f81afdd59d155aefa3b9dafd2a3ab3230e73f2a9cd63881a43a11e12013dbe173d83456a094823f26c1cedc14db5d82b4f374d900fde0d90d878b1eb3e375feab42bf6446d546850f2686a087a1f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x75150478f6a6c1375c002f74f82e1c3771bd09fffdcffe134c48abdb1d1458ebfcfd48bfd2bc43b8c7fa7556319a06a73483606c1e39ffe3594ff5bf9618290d	1624038714000000	1624643514000000	1687715514000000	1782323514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	122
\\x10adda784614e767968e8319187be42e15dc1cec7ac36ffd6f8c010d0754aea5a1650de606dff61935f22d61d97ee6a04c65e7fa29ea868d93453cd7231c4e12	\\x00800003c3052b1db55833deeebffc9170d5f72fa36fb834a00680179c5725bd6c86b2f9b4a0f8354df48e3ffb22e5dfb82be9f797de08803e77267752cf2a5651c3af25d68f90db98fa716ed061af43ac105ffcb2aed57e5f8f35022fe08b983b9d540a7509951fa8348ad3174ff5bb9ddc3ae80b769f95e8d2d4ec24aea79006ffb947010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6badd1157f950286bae3e68b1a8e74c494b5a3cd55db420b54ef5ebe4f627e6c02d1faac93ae4b9d91bd318165a54b442829a503fe255afe8ef2da32b506ca06	1634315214000000	1634920014000000	1697992014000000	1792600014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x16315cfdf7635398a5ece40e74b104b542574d8bb4fc6724760b9bcf971a2680ca9d34f3f13462854e8454b231c9fd03791eab24c5e7d6bcc9460c7ff91ef6ea	\\x00800003c56d455d258317fbeff92daa93102848b78534d421bc84c5fb42b9c58ae19d0428f371afdeadc23b7fe5b29576164ac483f497f5c1d80953298e590752d1904a5249893de71e8cd9abb9cac3e5fad3a704a8087762f7b11860ac4702cedf0d2fece132ab90a77d0c7bf4bd76f6ce4fa76514af707f1f284b4b10f0f84f6dc2cb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa353169f71f0a3ec66a1d3cbcdf26d20418a7558e57c983b5aae4a80e4383a527fe201a89cde78d3f12898aef081f706675e88cceb12327d9d02bfc8e592ce05	1622225214000000	1622830014000000	1685902014000000	1780510014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	124
\\x16312734739f01a38b3c206ed173e43fc12aacdbb94cf49c75babbccdeb57a7444083fc14ee1f99e7a17d297915b8363efec38ae45de54dbc3452bf60bc95b9c	\\x00800003ccb356f9ebd6b6b3a46813c6e9f46bf4f529446806e2d89be83e6c8099d90e648a81ff09781d0d6a3168690787dfec2b17a152d85bae3a5935551eb29f8a06941fa6c6e1b344d4e418878654a820af2dc9168de0e0a33763d7c9ec25be4dc2f8d991553ab658a5b40c8e8069f12a5ef7f764a68a8a3a29bac2de15a3c81a08c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x41ede5d2595853662017e78da813078c00e8766a5b56298c599da391b1be08d207a88ded94fff369510808941209d6b117720faf88062a92a04d27bd29e46402	1637337714000000	1637942514000000	1701014514000000	1795622514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	125
\\x17ed672555bad39f056c2d0af52246399d583fc8c3e2102ac7c1afaa8630b9ffd4ec35578e343b531461e35e4149c6a3a3d34ba4eb67675bd038bbf665d053f1	\\x00800003b97ff6835d85e25bf4b4d72ed5b236475323672a9e4fd8637da7cdc59b795714fe7895b0f9dcf1eed894d3244c2be62078336af565d667d63a8e9ad03dfb14a3ad95d60be7d63d1d7c0f6dadf2d498659a65fface220fb5d9ba3fc65dcb775fc1df6b90bd9624e4c686b19041a033b9b3de7489a2e8c61c241784ebac60923a5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe28bed77a58ba3f17edd5d205527ee1af3db6f0fc631ade08016c83b1cecbc356545cd5b1dbaa526eec3f39230d88e3e41635058375808af991e13e44608bc05	1621016214000000	1621621014000000	1684693014000000	1779301014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	126
\\x1809976a3c3ed0a6d969b19b32880f0934434ceb28714be67aa5527d4fddc0326d14f7fc30d2af1c7141954222ca819137d482b908071282947bf6929bdb7d10	\\x00800003ba8df5cd0080ed64b0bc8789efbce1dae24887f1f43c27fab611e91a600a061dd23992de00d21734a5dfadc2ec60d338c379c5290430a8dcf69cf696f7bbc5a8d903b14eea465c987c673d6428ff9c67ab1703c13fa2453edd5ed7a4a0934de0ebd27e9cb00d5202ae13f23978afc6913851f935c34e219712206598c6dbfbb7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x48d629390a24186cd8461ed1193e180ae31c450b5132916555b9f26b89b56faa2a3024cbd21c72830844bcceff02018155ec73d08ad5249b6be28ecea13d2f06	1639755714000000	1640360514000000	1703432514000000	1798040514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	127
\\x20b912b4c24254aaadc5cc8c22559865192c4a5564175ead9dff133cb25ff65b839948d5a2439be4e6b30cc26ced9ab59fb3cdd0296b9e8643a27632e5d2a077	\\x00800003c5666853e559af2c277f827b7b11942caa97a3aa024301ce5afc4ef7bfe36ab524c2a7286f2823ae3bf595ed4118cd2925dc93a834b09276545070f44137e64be99d220bdfa0e68a1d8c556fa7242ac06b3ae153371c251bff4faf63bc465effda357a146c95a0ee857e21c705603af4cfd448149d603b75df754761b452cbc9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6deaf605b6dd09b8e2309ff272d171e10a277701adf9c38cbaaa71b53aac5f4934a40740d0f65d9e72af0c9ed5740d9a73abeb2a068efe2836b05b7b04184109	1629479214000000	1630084014000000	1693156014000000	1787764014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	128
\\x23fdf7c29f89e94c7337b458a0fb193baf914f2c4ad2a2564277de6e1c49100ebdb8687629b9f69ffe549f6f0028d5f757b4728fb1aeb63d7318b01682580ad6	\\x00800003baec2367ae503ed0dbf5a0e711d29bd1dc282fcb16e4b94f12b1c74dcdd9390011dc724e1d4f2595ec8e9e8be7a616ac7bcefc63ac768a471a5280e4899ccd4006d8a7a95dbafa823bbe456a060a9fd14fb24b5d302568f84f8002f99634474db625d891dadcb75e5e8848c042a7a6bad92cacafa3e321309168f4dcc20f0cb5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5b5ad6f6d3ae50a6f62cfc4f10c346d94289c6d1561fa1d0935726b82f5daffe6482b76983a4d1c40fac8b1ed9d4a11d8ec467ce017116b92ff86652f897d70d	1637337714000000	1637942514000000	1701014514000000	1795622514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	129
\\x2789ae34b42972b4db5d4c69fd93fabf409081b068d5c44e0164fca3fea624091435c606d85a832d5dc61abd15acd0751f128c176694abda142a9746ffbe100f	\\x00800003bdb7dce4abb8b6d974a2898aeed7265699970b439b8f7db7f8f2ea6d84cb6737c18c0bb69b60b843da1496db5782d3d21050850820b0ff7bf66f9ccd301f6835c4ccbeb6077287806089bb831cbed0799ab55f4dd6e64ff4e9cb281d1e4c58d52dbaa0575afd68dac27f4ed1596a9b3b5fbae5e1be165fae8eb952af0f9e1263010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x71d9f8a00722376dda725043b7189051f2ced8e99c96ba1f4c3e8091cecdb27af68611bae03f9c77c861ce4c05281a0d59bbc1db62bfd5ee8492f7c00664510f	1635524214000000	1636129014000000	1699201014000000	1793809014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x2b8ddf923675210766fdc18b5b5985027996b6f7bd57e8778309395845cdc5d9b3ee0cd42f4551cdfa006835facca8a1e8fa37dbb9824c9f08005b27960967fb	\\x00800003c167801de427a7cc54c45cabceb6855b8e35801a21b74a3aa4ad8c2511c84c083e583b93c7746e6bdfd79357ffd9127d397ff3c4a4ca76f7bade7b61031cb5fe684588c402bbbd1dfdf7effed3ef3dce9a408f4b71c9a738f8a96c837e9aea5a684a57d166082c750145785a24d592367cc946046a90d93c350b0c1aeb7feb6b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x99bad55a97540a8664eb5bef4c5ada9db1f33308fb49dfd6e15eebf815389251a86c43aac6b9c9e0d6a4e1f338731b533fe13abb318c84bdce9a9d5921c82608	1629479214000000	1630084014000000	1693156014000000	1787764014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	131
\\x2f317583cf76e4fe655f02c9a22c8e7f9c627076c17961b4d5341255e01a24cf61df26126711d57b469b4a58aea4a1bfb888e9573def9f13678b59d5c2eddc5b	\\x00800003e49869e5925a6fdca7410a35b0260183fd3ca42548b4dd432f77e7f2bfdd521c913cf9caad81a948a0965c04ff2dab1ba2f53c79ff06483f7e039bdda9c5de4f511d29e76270b4398c767b9edf92661ddd3b9633132522d3667db0c9c845304f498b12023676423fb7082adcda925192eeed3945823c0d7dfa6d811e77d28405010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x841a39afb5f7a568b1f4af100d8defb2707050f6603c58c6508cd17e13fed7298c1e2429c638a00163c256ff47f73508e6263e6524b4299a12d42f174fea0e0c	1631897214000000	1632502014000000	1695574014000000	1790182014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	132
\\x30d93c3a80b35abe0226515e0726bbb88513ffc1122613b78e068354a2b654c3ad1a10d4d3dad5f9b75d3d75159420a9a58429aaaa9d3fe48b2c6c2d24836eb6	\\x00800003d02a2dc0ea35c039c0aa5737bc1f49ec1ea6cb13ae6323d774791fb0673f96ebbbc8c4cc66f9c9bf37409533839b5ff37e148c3fa5ffe04d661ff69e8a59aa9e03a2c94c4f7d45a093fa5a584645c520f749811bbd05855c6f30886aa756e5d5117e9d6d5ee89f7e43d924fcfa84912918b9a61c79ecd6faf368ab4d49fc007b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9ecbc6585f2cfdb3b2baecee10ade57f05baaad3fb2dbb9c8e9857b4c67795b9025219a94ba15d903799a23260710af30d84c895c47f25a625fbbd7ba92a5e01	1631292714000000	1631897514000000	1694969514000000	1789577514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	133
\\x31d5f6f075899b14bf62972e51b806f1325eeda29a6f728a4dc0a392a8a52c384c030a56f94e394e2435de86acade018a029ed58b169799625faa5f11163dd9c	\\x00800003b6e4e2ad4443b13fbd8763ae17b1ae01d8140a8671f611f14274390e81f9e79b1d0503fd5d7eaa48230bb604f91448c832d9776124360ff153801fd37d5ecfad642870e01825853a45a38fc75f070b207beb02324fefa8868a664a4c5c7d21c70e7bc6cdad7b659b846f1ca8dd7dce00f92697f890672fa4fc5f89507d231dd9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x050a10a5db4a74c4dbb94d1d8da3f7fc46fe284edabee47ae2d6d5af06814ecf5f2f4c627d96979c743c7646873ba366e8dccdf523d372d844a1ca27f828a808	1628270214000000	1628875014000000	1691947014000000	1786555014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	134
\\x31155fca66c0c9958a41ea7ea78c67fbc1a447ff6fc115ab124e4a216fc4086b1c1e271ad00e7fedbb91d7ee67f7b4b07e73fe65d0bfd7b7fc434f820b145735	\\x00800003b2e8aa66e1cf4c6ae91c4c3478ff0bca40dc9ccf658627eef17f311dd88f2d69dd2ad7b6e6f762e478239bd889c102987a950443c5f3ee30d2ef3e41a8464e1d4fdbd6e6d0a81cb4b4508dc611cfa1f11786a444516d636e59041d5be7a11a25183800591e0b419c5daf82e8b83cadfa8f458592a59629d083a8d81ef36c611d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x07f67f92b9d2a49648cfe365c197a17640c68e792fba8b032c7dd4a7bef7d7231fab5f65cc4de55f994999d53d340e22b7bbbd82063466daa0e4c94d808cdd0a	1634919714000000	1635524514000000	1698596514000000	1793204514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	135
\\x332d65f2819b199c313e71c2e5abda7a1882d5b8a060db3432418ba692a4308458b4b8e3a546debfb74f5ff46e8f98573ef1e3a0856d26fc0ea921cc2ac7252c	\\x00800003ed23a7969991413edc2ba1315ebf3745666a3814445229ade49c40f1a9594e83a62ce043ca3bc35d9ef3e5275b55b413705ac9926fd626434bc394bd8404c498e8bfb3406cd80a19bcedd6a6ce6affa1e873d56d4b6d560f9bb137adba14f2d8f79e472a4ca56a66e6da51a14369bccefbbbe0441ede44db940610a5707acfdb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb225e85b92eccaf7d5e67c3bdff2048c6366e9daf3ff4649b07dc9d6b28ee50837b84f35c33263fc743570e37c026528d194a4b8f32b49ce16b2b15bce452203	1617993714000000	1618598514000000	1681670514000000	1776278514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	136
\\x3525b58fa248d5ee88bf5517e48e6dd3697a9994606f4c9a13e74b216369f099b4446b6d89938187dbe50a0573c43cdc1558540104fa73439ac65b43e03ef808	\\x008000039e6f0d5556a7237e9d363e291fc3841cbb42304aa089d81a31aac9d4e2523580e8477bb1a9dff5270ff88c07549ac2dff2c763828ff04eee99f6404e364269750c63a9d89012bb3f39cf78370be8f67a8a02d0c8b597df3f70479bc13308defe3733ff3e18bed9144a295f260bea9c542268d1989415acf3267000fb80c89bf5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xea6dc322372b240c9da2fbd0a2835c5ecbf74ca7969367d23b13cc0cbb2978163d9d6a4d7be99448e68dbc87a6e6a408a3976456279272915f70bfe4a45e0401	1620411714000000	1621016514000000	1684088514000000	1778696514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	137
\\x36cd2a75e79ee79927bf37ee8ec04aa1400d97c6ebb279ad9a10a3d532ea1797f76afc21a33405ef3e0a55b67548ce608c2f4f65438c105837f242e491520cad	\\x00800003c9b10cb721748d1b55cebbf19ab600e38f45fc4a5b07742dec70c87345d84423d1cf2175a5de1edea78c6918b9177a91bb1b358c01a955274dc9f32cad566cdc5a8efa301013c13e43f129e1e937fd9ec0f18f5080750c16253001054bd8ee788f869b2358384910cbdff77a4dee4c8f713f4f9977274a4ca3d276f1f0b52b8d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1826c1e5d2b08b4f2306ac59f6d201ce92157a29b33b8a52390585da73a514f85826eedec13c3262f28996aabc8c30545cc43f97ec4947f8f9f2de0834a90502	1636128714000000	1636733514000000	1699805514000000	1794413514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	138
\\x36ed40de9bf7d6ae254bbe3302a2ae46d0edc2056c8c4a788a7785d98ccdb13867d7d2de3c9d0ee0d81c9fa25f6b5689526b8f31f84952ed18d0b36a88dc3d4e	\\x00800003e8a1d8e23222f77db2326f0ae396557d52b7741930812603ffd0023334a1a7c2691ef54b2bcb94b644e77e54bb269068161ed3ce8600cba1fd129a79a257ba37dd14732bd8874726069213fdf2f0a09f7dbef63687c80331e6ec817ff6a52be5729063adde0f6e053159459ca89bc6875b35855ad5dc266e7db37777597fbe65010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x63376d48f7d66319bcb2b1eea5215d52a98b29da43d57af267f6f6c6f61e793948b3ae98862a52c55d8ec0e51517811f16d3d86dca22218a5d64acef11fdd90e	1639755714000000	1640360514000000	1703432514000000	1798040514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	139
\\x3765bdce60f6000eb99a0afea51027b07f0987ae1e5d6b90baa6e403278b1bd8502e8bd3b6a1e33f24cf57f4da1bc2045bdda8cee7594b1936180ae3027ba9e3	\\x0080000399e4e260ff0a2eebe909ef77e03d28956ef9537735c58ca45aedb1cf81e4f21aef8808fe7988c9d5247271a82624306cfefc8c53550d83b08dc26889c0290734431ee4df1438a1e84da2f96ae63417a076cf0235a4aab66bc4d7f0ce99e8ce45bb825b362de95874ad25e403e141ded185415d372a70653d1ef0d5f97ef55af7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdc83a14c1c61e2834e369197f27d02bcbc3e2a951c3bb35de3578473037c6f0df2841f042a1ba72f2a7a4552399c5b4c2753fc789103507f2bb8f54c62d90f07	1617389214000000	1617994014000000	1681066014000000	1775674014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	140
\\x3751f4897902685ed891b16c77cb91185d4a8a96fd1c28bfdd7daba41b8f2d163aae1afe2c1784f24cbdda96c6bde1b54d7eb4ac900b111301a8778a7c6ce753	\\x00800003cc75ddaff7736e63d9c9ce2ea5c6b901aa85e5b64b5d53d364d6bd0ef8b9564d4d301c8db928c3be4229cd579db66837c67ac7af1191ab68cc0f4959a6de669902e0aad20baa92885bf9b690432c75df8e16217c597a6e3c873759794aa6441a1490a2351dbd1ee8aa2aa97ee9b9ccfb664fc4f721252b5abb643cca4a71d379010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xec0a6e5d8df816b715d726b949d629d23ee0809df83e6db2ef78ef9dbd566685a9849977df79936641be9b0ae46e316bb6f3fa08a9785fcac319a6ea6be60f08	1627665714000000	1628270514000000	1691342514000000	1785950514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	141
\\x3ba165c1dcf2ef4d60a3d2271d81265ccd698e40c5f40c5ad871c9484598ab967e326e8638576233cfda2ce0bd8db66adee03008617de1fe95f25c3a90112bed	\\x00800003c488d68ec4cbe11476d52b51e4a572daa4e8fd0f1b7e19966b31e0bf0f9614ef98a9871fe0936058aff5486fd81623b4d96202f42e37d0939ba6946b95b1b7f09a6723e8d6f3247706e24f9be6ae9e6279c8656f09a082650798fab7b7bc66ce475e88d2cef092358824b0979e3015e89de1c2819ef5e582434bf8bc5b21e329010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x78efb4c66d818e3ead961444cc053e5be2fca0ba3dfa83bcc6e9080f712c949b12e67f9e07f7db7c12063247ebc3781d2aa5f3190bc2758929585e7c41a04303	1634919714000000	1635524514000000	1698596514000000	1793204514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	142
\\x43a9cf664141a74b764abbba73dd1687700aa58d215fa3f06c642adb5790c57a35bb2effbae96708df0e47e6d31a42db22b539deb8a15d5e33dca0baa03c310c	\\x00800003d557792789379d9737144171f12fc26bf6f40de6ece912234fd58be58d241d0eb96be2f330b32391bc0c3a57dc127b5502eba62bab26a1b486923108ed27630c22c23a0fec7e28dd4d086c41ea679323a3472c09650c91dd896528d889874660b1b4c58f655c1b608161ea9b3cface6f0894e9160de4e5b85d16c914f5b0ca73010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4b0395e7737c6178594704dfa14f39cf8140c5d3b13eacc7946c4bddb9b8f3ce3b5255fea0a3ca438a13eb158965badbbba07d59bade1448c2175e99620cfd0c	1615575714000000	1616180514000000	1679252514000000	1773860514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	143
\\x442d9973717fd5013b0200f0699d89e072266e482007288ef2674f6f19438800514237940a436c2128867d21342b4d7baf122a985e2439eb098fa88c8d15cc26	\\x00800003c89e9815144aa4c810e083952313137f47fabd9e386e9c7b7b1d55d46c63d8a3a3aaea550532bc865ec74d9b17c55bba44334850193ad93a94a1f00cb7f61f17d0730f2898854c72f87dac1ae52d3b10ae7bdfe09426069d55eeeb6dfcec9fedd1b1f319d817b647904192e50f650e3797564feb657978be3d93a0e62ab1cdd3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4fee6b6929d89786122fa7aecde3391854813c44969b76ee883ea059e0d265db5ff1a9fccfb222eadda0391b502105e945e83d1e736f7eb465311cc4f3a78c06	1612553214000000	1613158014000000	1676230014000000	1770838014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	144
\\x4681c6aa111ea215eb0ffde38bd7799206c8106e809a2c364d9ff89e662121ebf6604ed45877bd55d466b7e437414eb10788164cbe095a216723ca38b272b1ed	\\x00800003b3264cde04c766dd061e93e3c7b4ebc76932707bf4eacf7f7a2d0c71c3139a8082563184bd5d1ab87bcd64abdd6726a0bb322bdbcd614f031cef48b0df5bc665f8bbe17a7f695358632f30bded2cb603b76adcc7efbc351e023a082b9dab79e472b5844ec6b3dd9214a2303d66aa887bb4e3d03518263636f4850d4c7d551615010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xed9dbd87e4ac9b95a0d35706d2aa4b405d30a0e05c8dc01b59dff6654a1aff79f06894199f72a2302d4694039ad6831fceb7fcc5d3e86bfa4d7869ecc27df907	1625247714000000	1625852514000000	1688924514000000	1783532514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x4741c8e077a992034d2eeacf6e5e92d5887f92b823d11648171f41836cc2c0651be2bb004e4186bd54ff379810556215cd2b16d120be249ca19abf237771f30e	\\x00800003dbe759de7132d9a77f2235f466bb064cd5f4eb7c5bd400a77f3a97cfbaebc2ef91b937664c8bb1a504224a9acda648c48eda14fcc87d74c4f38c234add29c4782cbb82b97e8bf9995ef86ab4ff81dcb4853c71f3f17d507dd8abe7d9c1298a0ec46b0933fbc090ed6698222f4137e40c362c5f0d4300530dff9692d2a4ef98cd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5cc65aee1aa615fe0617adbdf86f28c3ffd34b896e50e2aa6f230da345e0b33c98f7fa5783579508612d9a4f916d0ad3222d480fd2cf33470a805a53287c3f0e	1635524214000000	1636129014000000	1699201014000000	1793809014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x4831d412ce39928ce8a82572a0507f31e73b3d2139fc9eb0171f98b6aa2f083fbf308fc88a877de13c501af0cbf793cb6d2b45ce83c0462ca74be0ddc73d9ca1	\\x00800003a83810f4fe096bbb58ba1772e1a44b0dd1fa55cad9ce2ee66a2e924615b334ac46944cb05abadc511b7c6c7306b9c79e1567593276f8800cdb789df64ecba559dbd25a376f147df063a5015238fc3ac5ca09063ae7f6ab417ff3a6a3a10581db585adb77064271db5c07f296b24687e044abeac9990a6f140df6d65bb77fc3f1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x75c93b4403318ca3f8f3f29a9a2d63b7ba691a6a3fd9e2153338cc2714fc13a955f6907f38f827d42deaf03b8861ccc53846faece1d787a78aa05c6b5c78af04	1637942214000000	1638547014000000	1701619014000000	1796227014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	147
\\x4ab95dbdc30f6802614b2f31d6282534577fb97f6f04367d157897b2a1cc3214f646ede4c4b65b8dd92ef01763eb17383e260ab77737fb479b69981d0d898b70	\\x00800003d8a819b81a11c08c8c3162de814f387bbd31ba6cc5af3efef6be58e8855d122c0536ab49bbea3650a9d4ce17fad6bf69577fa9de2f8b5a3c1f5202751ca20eab98a401de56ce8be9c0fdcbb0bb17087c454d2015af0892bc6e60e67f566caca3d9287ba1c9fe4e3d92fce9bb064d0ad1ef090b4dc878894b089c23c59129e28b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc28debc7d8b47a286dd622fb2ccd5a8c6795ecf638ab8fe57b909d44214c4fa3515720479fd4748fbe6c640c03711b1bce4ca540de1406ead969882c7b78e707	1636128714000000	1636733514000000	1699805514000000	1794413514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	148
\\x53398d47b88bde2c51c82e7bf64ce5e747052cd9ff12163de1ff3f2fcccf0bce0f8f8c8911bfdf20020403bbd0b9d0b6f5d496d0b611de471f6f375051fe1cd5	\\x00800003a85c60108264f057fddb061d45b1d3a10b4172af8d5d9128eb5d570f85e5bef56135f1f748c9da234df9b4c741557ccf040d63049455f22bc81dd1963c91407f51392de3ef30c2494fbcbbd012a980fb7edefd5e3da3ccb47b94665b2852b8322ceb1a50d1805b8947ce887468263e584b818bbff8d156c491767a145720c2f7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x443c9748ee7fa2f4fae73c1870b3eacbb076ac5b3f0e3b2f298afe8d3d4e8bfbacac648e944792af45460e43c02707ba5c6b20c73e0ce8698bccca29aa19630a	1634315214000000	1634920014000000	1697992014000000	1792600014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	149
\\x5569bc0d8e171dffbb94740fa7853da6133a398fca948e9f6fe2d6ac9fb93e10cbc5bd4cd3f609b4e6b4b3f385a587078b9b0bbb3a0adad8b0d27df47303ea00	\\x00800003b301f45e5c121336c55e8f776ed2044811c552ee60b60ffa14cad84de4784a750b34cfb2f336de78d8b23eab8dab709332c7ab8b5726dc39c6baa19778de7f0a29560912c416ab917579b5bb0bbd070647dbd3795ff27eb01d54a211956277badaf64be4fee8b27e2aec08e4066539658004ae6b0e14d637cc0977cac5119107010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc1302671df7f59004d7f55b9ce1d91469f618e1fa493e5e644a30676d8e5db7c766c5ef4329937a2d0723ea1769b45d5b28ea8e10d1f2501b22c7d28180eb500	1636128714000000	1636733514000000	1699805514000000	1794413514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x58b5a1cdd0ef9ce637e6961f2f9f25b3baa54d25d345eb39bd3a0fe50a5d7f940a1724c5d427dc2c5d9be6a6672673db55f81bea67552dd9826358c193a92c7b	\\x00800003ad0e1a3206869be4f7875bbcc76a878a391979cee07543a45dddc68f21b6101cfc4eba7b5a66c441b7b3ab49639d85c6c6ad24bdaf25e38baa0d8f893f0256978b4a89434c03db4aeea13911e610f2b1ad80f98541691aeb77f369f748592dcf8e6f993d544d2bb3c7240946b3738e79783fa6fb3664d802584841ead7dd4b3d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3b6b8928a7cd03e638227a47389472dec5545d08ec7437ac52280fe31ab5b4f2a7720df5dc039e6705b7326e266d8e9af8b21915b2aceef6fe78c0189cfcc601	1619807214000000	1620412014000000	1683484014000000	1778092014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	151
\\x5bc5973cae3ed96447077489a8d36e14f06014a55f38d8d93a1a5d1b467a4ef4aa0874a96cb47469c74f47a0d2e959aeecd568acc569c90adc57de49815a8287	\\x00800003c7d412b6fcf54dc9147af926ddefe89aa87ab33405510353df3363ba60adbe391126cb26a707f5d5291b8c27da37506f4b044117077d41660e6071bbb8b10321a49e05b88e2a450ac1e9010dd2ff1fa26faa145c2ae486ab02acdbfa277be891620e3d50403a9026d42361f2204bac0d7cd92b1ac43b7099c5e88783a31288c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x58b6c4ac6e01068a781715baec83e132cecfedb9ce8a50f03ea7b9b7b5dc2009433abb47d6a69fb60a5f720c89e27287666991014fc7d5347afe51a8c089ee05	1638546714000000	1639151514000000	1702223514000000	1796831514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x5fe5c84b78d520004309c32d8be9ee27eaaf73cb900f623f0f3dc17e57136398446215fa3eccfd7e87d1771a5d9f23e0eba4bcf3addb13c575e08ecb3e70a401	\\x00800003bcb1d5d3910353f02b2fb1cf0b016f3e8825061e9afb6e63556be58cf51652de5b6c902b383cea55119d645bb7f0d5625d459b8c71d44d630d7ce244ebbd7561f93a88bca8d9821e348fc61b45d6cdd449dbed4042a5baa9ff9091fcfb529cb85d45bccc10d95ae9b4293db2e992d2b64f3fefe012b5814cdb97d30825350c05010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5b1cf2c892c744518d9bac0798ac20e4d4593333550d07c4840453594034b370f7f47ae9d9c41873b7c952ab820e89fedeb40b409a262a8076ad494481579a0a	1612553214000000	1613158014000000	1676230014000000	1770838014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	153
\\x6949b60802988bc98300d281502deb1183f6095c7d7dfd018250341090110abab5760c2c8f6fc922a0ba3b93238ac4464cee35a0a233c0ab605473d0affcb855	\\x00800003cba8c6f91bdff4b5b8386adfc470c27a7feedff32838cef82eddf2b0c018d13f23c9bd3c642d46082dccd1180bb2916d5b9a7b84bd643d3aad1340b13b52aa42019a10d4c151c556ec76ae504ee132f5b7023428fe2c144273afdf1299f95b588736793064e4d68c05f6453c0a225509ed68ae5d16e09fcab9b34f9e4ade5bcb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x80572dbc702122b16573a307a3eaeeb2ef08d7006a3dcba1b4cde8a17e25b495662cdd014414c6017f0146ac26fe92dc8e3733317b3799ba6b6816a8a582d80b	1640360214000000	1640965014000000	1704037014000000	1798645014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	154
\\x718951089f5626412730f953938b8de7a10d4f51dc3cd5df4d7b3795d9c78ad1a3fa800230838e4da800a872cc50157eb99f308079b974b1c1ec5f89fe2bd3ba	\\x00800003a6530e598fa3dbf482335a4f97c13b3ded39f09a8e2b56d96f8580db378c6f2c3fdaef261984f4130c2387d0cc9455f5e6f0cdf36b5e079121cb6dcfa65b5a6666331662cb68914cfbea21a2491c78c4672251df66662ef0bb74da24fb3eb67f5d094efcb48cade63193274edcce883169d658d95c4ba53dfbfa61cb1f93020d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5a1a6ef388bb628b0e8e251234903905601709637d51745d17f064175947cd3aafac03e541936b4d36a2aed8beb6253462e6e80e578454d5eb0d46e29928c50b	1640964714000000	1641569514000000	1704641514000000	1799249514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	155
\\x7251e65a3eaad29ef6e0d0747176db32febc75503d50057c08e741462d1443342b9260f19301defa0228ce97cd78bcaefbc0ae22699f4febe267e506313f0c39	\\x00800003bd8d8e69bc78f4cca56fe0c586c973653e529941220d7442aaaad508eafdcb54439542fc016e05c4f37901a37a6c75b9640ed03b2b08a3aad9539cffb472de5e75e86e090df87d9011ec1bd4881e0868dde2d867691f5cd547e46e8239f249bf26b51e4c46ad057089e5629908b7ece72f9d4d11ca7e843805ec2552f2246541010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcf280ea1ec07fe619ec5c27897860d24c612a7f45ac458773bae7284eb8aec003f9c188f6eba9ccad16a7f477f07d0f1b6653dfead124c4f61ed17ef32818104	1613157714000000	1613762514000000	1676834514000000	1771442514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	156
\\x735188de629726fec9dd37121ce8bd4c2745f401c4bcc65b4d4b7af078171519e9615628e3193d3aac1dd3f4ba8f06c82623117330b51c5b48a504d1cc8aff72	\\x00800003c8d813cf699634a1ee65faa3ce742e1cc7a805e8e786d245b5cd167072638d5ae97b67617590a2dbf47c6610e84ca243e5fd8ac5dd702e9eade459f5ff8a355149f7a1982ebe6571f2c6d405d58afd3b2ab2983a8a0f59743e0580342c8e49da8d28d9ce1b418aea482ba8307c3e9bc7a73587a1adad8f5cfc96cb31c8b71997010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x887b48f281e292756c3abb42a19853634c9291f515dfb610c7a1fee63b68b65c21eae8e3f7a4cf75cdbb66767002cb1d7815dbc15322404ad6a4e468af27a400	1636733214000000	1637338014000000	1700410014000000	1795018014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	157
\\x7445deee54b1ddf7bbe239e875f8a02123a247e8b636119f643f90c1b5241fe2381faff78854c2f059cc04f58bb4708d0ea37a6afd437e065f6dcafca1a0428d	\\x00800003d345299fd6e5997b028eed9d181aec2b8cb81a9d32447e557e33d98dfab85462c7af87025970e96470de774b9c4505024a12b6fbe3880468bcd2f52c4cb2a9f46e5687192ea47bb69b3549e4417a78b4c05f568ccdbc6b254c3cec3a31f8fb9984abd338ffed9fb6b428b57552cd5172d538fd089e4a3e9784fde446bf78aca1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3e19dacf2aa7ad2fd0b4e0fab6600c019dbcff6e8a5fbc326c1076f83218886bf9d8238fc308e73b622d38d3b76c54010ba17ff2a2dc79016819ade44c7f2803	1635524214000000	1636129014000000	1699201014000000	1793809014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	158
\\x75dd015a4cc1bd0ae069f8f5fe8389574a91072cff16245f4c15a748cf5295efb9ce4890d61c52e2c9096908786216347e7a9c08546475462d8d00a90a2956d8	\\x00800003bddabd335680376689c12cce6f308b8cf9f5795419e45e9e3cf5544109d1dfdbb8a2c8eb98f4393ecb716c990792cc4a338a3aa6f77dfa2dcd2d1aa93966f1b3e8473a8696b38292a48556858b03e68a11f98b6487fc58431beff773af7ddda3b09b3aa49e93f0c066cd7936fdfb832e7116abe3ee017608266528fea66dfd95010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9191d6630f8d5c8007827a0f421a3444b8ed1d565f6b71857c9424cbf4962917693334f57ebb9d5799a7daf72eca2a865ea7012805d05f3e684e8c7397641a0a	1639151214000000	1639756014000000	1702828014000000	1797436014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	159
\\x7579bb5842177c49ee698b28c6bd8b7ea399b66d2a7dae2645f3bd4137656645eef2fbb46ef90beaa1c436ee44eb41910af625024f9535e1d8284091f2993319	\\x00800003c1087fea5e00c0360dd23b52f5549585174014e38d819eebb2c9fc65a70a8fcfc111dbca988501e1830c1dff19d58882c8d7d72a22d150d558883f3019f8ca96d0c0b508a296479cd34ee6c8c67ce0140bac509e6692f3ee856202538186584b401ebbb0f633ff2a286f54aff353a989f3b0dd7bbd56d10c305df02f0379d5ab010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6879343c4c11b49797d23c70bae473b284ed91f6944c680703dd199f4bf77119786a54ca6de057666b80cf00212f993dd5673f711b6eb1ba190948467e10fe01	1621016214000000	1621621014000000	1684693014000000	1779301014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x7789d62c0a4a6855b869ead599f1c6f21cbb77afc51dbc6480f34d547affc85d6a18910a94e77b023325aecefc49bf383b50065bb1f460f7e4d27e68d4095401	\\x00800003d42d968093d8d4f7bd1d15ea8712508af5f9458e8731e1d7b9357d373dd9a226fb2785eaf75509979447954d81676c667277cc3478078fc7e54b09c94cc459efc52cd1f0418bdc3da4680c3052c2f31f1f051b090108f7adef0ae160867fb5ee39798ea5e60b77016b44e224141b89e776b49a94112f768206d74b4b50324b95010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xed4305ce4203e8ace20f0cedb9a8b28fc24daf53ee53e20b1ca9c3c1acb86b8b877435bf7a521e09fa626cdbdea14c049579856ffdb5e7b078711076876d180f	1617389214000000	1617994014000000	1681066014000000	1775674014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	161
\\x7795387fcebd5d18154a45a8a45d2da669db3c2282d99335e2e3001125a7d172bc54be5e35c19d71ad41177f6fa548ab952c4beaf07f620c9ff4bbba16a803a2	\\x00800003c5db4534c6feb53d0376e8fa0d7cd4b59e4258b3ee602e6543acc7ba3fb97e50892379e4aef239a314a1497e40ed6ff74ce49b31eb1dbf93f958253f7caf2e9466d9dfbf1c5c724185bba098779f8d3dc3f9888a6aa62389f68ce07e869341b5df7d1065165248fa055802845e8c6ae434de4590817cf62d6b10bd8928ae90b9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd65428318a8fca6945e5e7bb551c21a98ff7d22e75fdd7e15f43999f7e390c309fc3539d14a213f01620b52fb08e385785c7748a5fdd10456aa213c2096eb601	1622829714000000	1623434514000000	1686506514000000	1781114514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x77f5f2e25b7bffb93fe221a9b678b34bc5dc42c7cd4b49acd26e40b17ac9d5f0b9b5aa603763506f7aae7d7ee20aeceaed01eb6c2ac9d5e39262fb3566eb35b8	\\x00800003bc42f28969ad419be33a8f7678c878947be848593296276cb79543fcd23766b9d7991375293f28c51e16c5a34a6ac983b2648125e5777155be8d687d777d8209b3ea071e8f9cb3945125fa59b723d142e460e086a091f8a244604ba1693b8f8fcdb8dee5f35ceda4de8e73322e64f3b2965df13726473d80e83d2276b70ac969010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x16731c9f460843e5bdbdfad8514256717254d46ee4228c635d05e63fbaa372f23c3acfa487752e788bd0ee94318cd3439da0483f27a54ea2b4f4a5374fe85409	1614971214000000	1615576014000000	1678648014000000	1773256014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	163
\\x7d49e743eaac18abbc04189871ed160d6c07c8e3e1b3eeddc1ad892612b4d1426efe015e4571c6025b4820ded8c2c531167d7caacf0ceed20968750d65605738	\\x00800003bd522c5c581045f9cac5667583764395960d347d30c39f8a635fed7e4dc4947bcc5b44386de4309e30bfc906df99f716cb2bb0fd8eb8a6ef393f22846540d5cb3b2b4786bf846e05cae485759977912fcf59714fd1d41bb0c5ced014be87e52facbb1d5f9f1b6c3e452e629a9bc4ff3a1f2ad73c6eb6a414078a509b799fefdb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5dc4fb235d65e0bf1f398e4827250c9285e7550bb4548c2cb45400972f183facad65e0f954c5c175271749e6f264198a6e3319e490eac5678b8bcd6d5d080504	1640360214000000	1640965014000000	1704037014000000	1798645014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	164
\\x7df1a34c40cced8d600a5932b2b5b010384d712a4035059f5dafd9f17240f47d53b4fa61ba797de271682e3aad125586fd1a201d3170e8d065bf4aa72230bdae	\\x00800003d1f25f791015b0f44e23bf1b498dcb41d25436de22000ebfe19f4ed3d3ceb117086fd139a9fdf19e770d2549fe6eec72d1c1b389c4eda868182b70f999e6fec1c33fc888cf06faa53df60478b7dbefbdb897923d6d32e13acd72c1992934905299bf29d1ff0c3710b7d5cf2d7d735312fd0e4954f05518e7f7432c462a5c7973010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xecf5f3d2e3e0d4b7433d049dca24a8d6de9ef7398a4368cb357f30ae3c4d080573d275301ebc6d3cf24061159d97002d46366b8aa27cc9465b90cd74a4f6780a	1625852214000000	1626457014000000	1689529014000000	1784137014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	165
\\x7e499dc2e2fe3c5ab68fa0dec3bce24fe63ff83ed084e897966b4786dc74148342a58c1e20c9a65033096f7560b167c915ceb05ac75ded786e115a736dbbd21a	\\x00800003c56d46734b9d3a312410b283117baafb8ea1a41e9b8eb712d04fb49a801f8040d9ffcb779b2f1de5556006fa5e3d2441c8deaabdaad919f7d70625fd1aa72fa48b245d8cd24029f60238c66a483c3b32346a6525c1d8c86dbed0250df021b0869416d2fb0100c64cee3e2fbb821f09029f9a6b0d8a2cf5e9ccafde80d7aeac5f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x04e1c0777f323969207673cb60c00b9b50ed438f0f794660ed44ec12f78a511843e319306941b361a3e1a91083b74af1dbeffcb5a517be3ac5ca0365837e4f08	1635524214000000	1636129014000000	1699201014000000	1793809014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x7eed9b12d7fc3351512973d4be2f779eb4ba2952b7c1331bd9e58ee0e130ebf0ef7746df13474529d3626352c12b253bd44174790559a7ddfb42350858c85b3c	\\x00800003bf24b707bc8fe1d39b92eb04c47052f7dab3d778bca83e6e8748fc57ae9b580a7a53c4628c71e8f56bd3ac1ab9ea71da2db41aebc1c9b604b48abc96ba78d472e0796782df82cb57203c8175f91ef267156bc40f492b5c40395d4270476d8931f84febf0c387bec1c694aa74df679ade450b81e2fe6a86648dd6917a9a239219010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa2e30ee8aefa51d2ae81d81efbbc4df225f372c7d33478bce79944e4743060aff43a5103ced36a52fa436efd87310ee6e9aa6dbe8546e9895d1cdc92f4bb5b05	1634315214000000	1634920014000000	1697992014000000	1792600014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	167
\\x80d12b622fd8a840a68a101146681b1965377ca0c2de4c028a9acac2a45ddfd8ff92e845fd6be3fea851bc73f45848d73274153639e3a4510dde6bfb4eb4a04c	\\x00800003d3e4d05d6336f75bff2f25ade217e6af31897efac5196e587fb859b852241fc5017c3b4df52566aaa592d5a43d366b0116630352304e4d789f1f27e7fe2f632b00583676eb24922b621d876d490ee14b494332bbda475cd2f5b39c1b18bcf3d4de0a81bc785763ff79d689268182c668019ae4820cb7ec0637081fac8f58535b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3c2bcabbeb8d49d4713ad84542fe6dd9e4071c43f829f755a1cc57aabe3cde64a4e85ee6c21a8c523a23ae8563167677859ff6c8625c5cebd797702c4c44740a	1627061214000000	1627666014000000	1690738014000000	1785346014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	168
\\x828591991a88e7ff871a2add39d28c2c193227802feafecc7864f213f6db0002949abc668833886752629e4335aa0a5406c7c12255f46d49a47eabc2ee2c3ed3	\\x00800003ba4dcbf8647954f193f1e459cc7b04222f8c59b11435b089899e2e99646da9ff878d9eaac1f8629893fd0ea5d220fae97b7086615f13ae577bf5cfc2b7a4c4c6e9f8e210e0f8d5635cb4d5e9c02594954d8b270c8291d3be9a97aa098ab853b612b099f4d4482eabe8d3d7adca066aab1f0dab606fb01e829f14723af5fe2ecd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xbd07d6551785dd788fdaec53a9ef646f8ca081c0aae7c4fdf7609e459c0dbe16f4e1bea40d026e9bfd367349cc5f28b23bf479450731b393996ad325d4e21902	1622225214000000	1622830014000000	1685902014000000	1780510014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	169
\\x86b192b521c17bd3d2004f7527901c7a488853d8bc89edf47a7cb3cfb4e06259acdb2f2a6c6bf1e58cdacb88354851c72f6c0f2cceefcb74cadd2b9d9e67704c	\\x00800003b4db8dbffb11b9235fa9a3c50a20382d0199a73ea4abc2ec558254f3d55c6a1215867e57fc95c026871e9f82a6dad4bfdbcfd15e1e7bc13ac20b64b3f4272d7ea29a4795de09da865b86cef1f7be81ab3438671f97431be137ac6433ac3b9d3e5016c95da9156b216eb19c6ac5aaa445f3bc07889cc8d5c7380c9fc1caf18cd7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf9adc47bc87823770ea9c4db3c5b8c9ef7e64615ebabe40622048342490e399c7cb01205cb85109dae1dc950931e3ee927f5c173ce5c5ec07f4a4fbbc0228001	1613762214000000	1614367014000000	1677439014000000	1772047014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	170
\\x8fbdce3421265a906a5b1c9f81ac505a97297687cbe85a99a58dbea0d5c630600d1a2b865778802788053801de818d1518b6dbb92aae7fcbfa988f6ee9e1d79a	\\x00800003ae73299a00cd45856dc48975f30c0e2adb42f683b507aeb9f5686a37581581ad17439d33a0a0171a1b94cf21d57058df7ba94d60a9033c7481fe3af9c0acc9ee1b79244d7da9925b3d9d549197c3fcefc4f7ae5e767e687b445c5695b46099ac88cceecaf415acbab438b5ab827036ac4dfdc019243470dd928018cfc6525e51010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x01aa261ec3b6cf591982bc97892b0e2699d4d4f762ec5b2175c8be2cae8c72aa23c2e81e4ceb9219019861d3f16c0fdc9622e76b4ea2b791c34eeb6e795cfd0e	1616180214000000	1616785014000000	1679857014000000	1774465014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	171
\\x94d93ab8f3f6001863acd8d04ddf078621fe098d7dd33c5087cbd645d9f9bc4544b107fc8fa07eefce6cc854efecbd2aea70eb5dbfcaf958d7fb14e52d3fed8c	\\x00800003cffe182100020d059aec598251bc3088fffbb29a70602b3e0408608b23aa5f790a8f4075cd6aeb699dc95d9934e9d513d6120af6681b808baa07dcbcef6c2cc19561389c43a02effc6103a64fc943d768998d23b8210acbfd3bdf79dba51159913fb954f53b54fe095b70fdc5e44e790c9690ecc27b25ad9b6bb70b8433ede13010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x367d4d3430c3ffb53b65eefb140426baf586b7979ffb896203ea882aa8778513e7f56c0dce2ddb4da040a3a6a1385bc9ce5f4c20f29348b335dd7fd35453de0d	1622225214000000	1622830014000000	1685902014000000	1780510014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x9531227ab03dead75f27a88d3548ccd81eb0db212b37bf140709ae8ebef63dcb51bdcc2e184747148d2333905ed97c646151b3fe04e11b9f3f812df157ab69fb	\\x00800003b6d661970bd5aefcec097b18acccaee021a67d8a03440ec095310d7fd6b144ab0aaee1e395bec73258213462afe31fdf90f50803519bc57802b8982c6c5c528a7dbc18985eb0afbcab8ff499d79eec789b86b70b71e099918d809e71b5906e85670a736a444316539004c93d40d3f5cc82f16f93d6b930df03ce561f634d8169010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x08b66e1b79cfd51d5aed0d6911911d7d674e7a2073d06b7d7149f89a05205290ef06c62705dda65cf5cba09e5c3139a01abceaef92e5f1c23cfa6c4dabf99a00	1624643214000000	1625248014000000	1688320014000000	1782928014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	173
\\x96f9f22bddbef0f410fb4afb9ebcca900ef7755d251cc6877a091f44a0855619d6573183f4c048aa80479daff98da0cbeca060efd35675a9401644d73fa5e127	\\x00800003ae7847668ef7dc099f224263cb37f438c34b048c60116f7c9872292b1638231f9709205f11beb92659354290dc19e288ade8bc00b9634442e8c9d0a56a961af307cf5a1c6e3701eed4a5f088bebfb55cd491ff82c6b48c6a464187965e2fc6aa4406e94d78c55b78f0357bb373a4f36dcea151f36ee7365f9201f1f64bf265df010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdb78ffc731bcd2dab0e6f24c0969354130f25abef367ff424b14b100207e87d930a49fdd87c30b4c888e8a547ada44c9d84d0138ea21785f9bc85ad3914de00c	1615575714000000	1616180514000000	1679252514000000	1773860514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	174
\\x971918c76061d0bb2c4c5faf9576711382d29d2d35e9d841f165d0ae8fa003c176e1c9a1b0bb373e215264c1a5fc453b70e83bce1e84317b265a2fceb7b3e188	\\x00800003b6c266fa85f3f74f07adb883b00a565014466b46fe4120cbe874e046afc0032e200b6466aa4f2e3ef1503076302848494381a8e49a6e90b1ddd2c2a88963aea32f808e34809d2dcb4e9e932b75d7810ae076d96c03fee18518bc6cbae5b70bca9cfe8ec9333ae2a33ff8ea1f3b53a6af817ec75acc5ab5cd2e57c908d4842277010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3ad16275c265718d67fcebc2433871b9edc5a246bdfa136cd7afe8df09b508ea9b83202761f5d09912961f4eedde7b4d2c95676f2fa012b4368627561ca7eb0d	1631897214000000	1632502014000000	1695574014000000	1790182014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	175
\\x9ce141a1715af1ff255d08bef7675f2df99f43f87687a57286cff40dbc1a5b6751457a4fd9a4bcea827ac5de9ef01df58a71f4e1d7ee22202b3174c9afbcf298	\\x00800003b3268fa91883392a5435725189655a1f9ece2b86e65b168de61c0da4d5a36295df96ad1eae80241381c2de5bd63afd60f700663b7973379fbd5aad484763aa9b54fd6ea8772f3791b397b7576dc367edfbf6fc7cb6e767c4918201770288fe68e978e442e28e3c995f8fef8e69939518827a69bb8faf38b6be418308ee465841010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x53ae0b9efe12441a23a9022776cb7323384f3001cf17251bd0997a197de3800fd2caa952eee4c3cdba47f8dfc5324253008a76cdf4a77205973edc285d70070d	1612553214000000	1613158014000000	1676230014000000	1770838014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	176
\\x9c05aaad0f2db17f263923e240225bf676933495b3ee686c4b2656c661dffd61a91499e84100ffddeaadc605e08ca07a747c22d6b8353e0ffb8a8b741a81e13e	\\x008000039fa6bafd6cf880c67a16e3830df034acf75795ee3d1b99a7098b05920d204454666dea9a4e855dfd875137dbcafaf0607f3e8f404030670900ade8caf99bd06575e6e0cb492ee2ceb9aeeaa0265440d2946d1101ab414d3e4c7b864176b17d32ef279b71affc1b1a473566f3dba555dd335101c835bb8043c3d83ccd81bdfa71010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xad738d4dcaafc5c1dee18218dea6c8bb0e52fc57ec55f6086e3f34e47f1be3f303f125c248e6a03304f864b58416d54672ce6d18421de54bb9e3a08644113e09	1640964714000000	1641569514000000	1704641514000000	1799249514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\x9d0d5ef54dd35578401767ad22161589ee32d1c66d450d67bb8e3edd71f98c3798daac20b8a2f49e37cee34edee20c07ba360f01d390e54641990fe6d878e82b	\\x00800003bce3397527984628f955834e0fa1c88da0c458e10dd8c1e741dac55a33c6dd7e71edd859ac7c8ead3039765ea30a01e2bd2598b135de52a145f6e4123141d255d8c3946410a9dc6d2bd860da2578af94232c1469940e1213fc37d7aec8fd335da58b866da0d6d6fd9a4cb657df1ff6a01281fcd8f73d218e78d162d171a113d9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x00c673ee5581c582afbbab00b73cddfd758a7baaf0e2b66b06adf3e024d5754cf1cfee727a19dfd9e31571d733e8d01ebf5ca48228d3093e78f57308227a2d0f	1616180214000000	1616785014000000	1679857014000000	1774465014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xa07da5256f961377db5fd10d1d43e08eb74312f5ad8f5846af8bf75334088227bf0e184783db9e722596b81120313df6f04f882fa48e0324571dfeedf727210f	\\x00800003dba54855e6cfae7359d17090a7e95d0dee274e769ccfbf0959002f5c81bc6a318172cff813456258ba2f8109d760cacd3cd7f0ae981696de330b40e56312e2cf8b603b26245e5d8cd3f0b036770e50bcae652d610bd917b85c2dc034d18280684e07196d9da50802afd4c73aecb60e8bc2a13676913258275a2a243a6df8b02b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd4565dcfc19d30cf066944a3fcee62d5d3e19ae7a77e3ce5c09f034fdcc94f55c692cc7ea0721f9701a12c29660a3d6df0cf467813d6cf48ec31250bc470ec00	1613157714000000	1613762514000000	1676834514000000	1771442514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	179
\\xa1a9d7a9405e138eef7b214522872b90d15548621786041838f7fda6177fea7972656c39a690dffb17a5af79b940a8a92ace3fcf30331abaa914d46b4fb5bedd	\\x00800003d3809803a63513a937c6f40f2b96ad512a10b78c341acbd4ba60846e89e60a0f9f71ed2880dded214d53b4e55f0ced82e19b9f051542c7817903c324cc9c4134aa1c48b09f3e4560e3c46cdbe8f4027539c2dc3135cd2ef4d1312ad42a6ff05119afa2343b0ef9f3f97fe94985803f6d9f80db1ee4169d3509a926f65d90b03f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x32157a7b980ec31ceff5d9a7f70ccd6edf4fac79396d52d3fd9ee97c74be4798e4256d185cc062aa943c231628494a24dd49f61444ac641b742719c0082c9d0f	1610135214000000	1610740014000000	1673812014000000	1768420014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	180
\\xa23124d6fd044eb07beb94ae71dac4a95587176f5c08d69aaef0545daedfbda43ff04d02c9a7ec2dc1c96be938101a494da160bea1f4a3d8e0b2b896b69fe555	\\x00800003c812b90ce264f41b41c7a5816a989343ce7e7539f1ecd20cb91ffd362f21344bef782c2fa4811fe056c1e09bec7184dad25b4eb6a4ab72222a4089556b0324e153f2672a2786900f970638bd09bc290defdbb95bcc2f47487f6e062a24ef710e55658c760c3b134cbb0656f0e4e0424f9ac186f22b14e4a7061432b0eae30dd7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa731d77083a38c900b6480902d86d5e5d9f37fd9154775fbb5f6e7cd576f993358bb1bea6ae782d1262e067f399643af97f1e1166955f3096971e3e4759ec302	1638546714000000	1639151514000000	1702223514000000	1796831514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	181
\\xa2f9796b1a4c284c7ab2ad23b49e05baab9d4e7026806bde62a47d6fbd53df04c94be27ee0d703497eca57e8c80929f73dc412b139008e56e3c7c1ae82fc4787	\\x00800003c14288412ede3a10e0f3958ec3216afeab510556db0643e8d604c7366d3ddd25a55613508769fe2bdab95acecf9cb2610653b480b7babc39e87cbbbd4f8511e5428270ef087ca4944909e2910e7ecd7f56ae4d0d37fe0918c114830ab4501acc5df7419cdeb3b06550afb3f251c3d7a78e55f4064387b969beb904737cc66f31010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3e6fb8c687b97041ac1127530aec09a7c679c354fa031be567e5b82f6a81c92aa8d939f5dacc1d8ef9d8b5b7d9078feeba5d9839a6e3aa34700f1ba73030a107	1615575714000000	1616180514000000	1679252514000000	1773860514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xa2299bf95dabf23ff6749c8292bdd0e8e7748402dc741230092ca0ead9e1a9d55f222cd95259846482a3a3567fc36c789ca848566089a257cdfc711c7d719543	\\x00800003cf1171052874adcd9b471fdb75b5f608c24cb7fe65c0b102e3f5ef39bc57d8a5fa7e215ad8b1a376b391957bd30ffb5a82729a00b05584bc39ee703ce5015c1801dcc63893a53db41d2b42b7a0d58e89ef7b74509b4c8175d1431a3b5693563141c7937a6cecfd5c90e1e90afb46901c84e556fd8dbd24cee23c05a649360b8b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc667741c54af2c23632681861f772f31720d0f57a636e3448119596976272f7e1e6b78a148f75a524881803e6c8d6cfa54a0ecf82a4d4d1ce3043848ec90da07	1618598214000000	1619203014000000	1682275014000000	1776883014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	183
\\xa7adc74e69bcb27251b733cadc625db53570203b9193c88e3846a055d744b7967c27329158d9a9f3a3236712e600e658fb224ad08bf006f645404e535d9dbc1c	\\x00800003d36039edc033f6594e9a0833a1fde8c342ceca043350af75fd0b1736fc8c4f2d3d68b466aef7653f3fe81ee12b81f7ec579c05f328980023eb0bdeae57c5855761b893999f1b811376fcfa62d4f6254ff6bdf0f951d36cc4baca69aac67f2ce046dfba1d7b7f8d3337abef3a3570fc1445205b8529b1451b47f8eae9a15c2f5b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x276303ccdb250e5582edcf80b04ee913d9da94d26c8876a651434a62389f8f81e7db366d41ec30d8cbaccf4b4a706789a68efd976955484ad3a0e39b01760c03	1611948714000000	1612553514000000	1675625514000000	1770233514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	184
\\xa82d24b009c3ceeea8906a3019fb16698088e1d5abd6344ef3c4897bbd19a7478b0982d9866e47e2ba5f4a7122fdf622f3f504d8dc708ba123a36cd0deeade75	\\x00800003cfdcaa6d62fd492dcc7a1bf07a85dd726022ece46953f93d0fdd0ad210a34707999d430096fcbbb40fb3e4e77da3944cdea15cd1fd0c7e952a5bf70be490adf08beecadd4627aab3403fb1d9c04e8b8ddf3d891f900b15684fb87b1bc9347e7fec2874763075e6f0f9493f8d0a43ca34c8081f9b9a3eca139188f24489eb23e9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x46beefa3dd40aa766890168bd518403bb54fb1ae8e63463194f3e326c29240b03658a84592a2d8b1b12bea381975a1a44e8725cb175e0413cefc2c185bcbac01	1634919714000000	1635524514000000	1698596514000000	1793204514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	185
\\xaa35ed7c90005fd421e6fb666a409a19b86b304aeab983134cde2401c69162ce69342764c1a959712b02dc7e0235c1919f2ea7e11aced9875924385496e6b034	\\x00800003baf9cc5a9b4e6eacb0a9882b040f4c951f4aba042021f78af2b2ae45096c208a45da84b82c94a67cc4df2f2a623b7de70379d54ada7998c85348924f23eef392fd096fd873daa03f2a3ab2319f3e3742f2b7598b29ef1c8831e435a7056594096966ec0838cd06a805918a541cccd8b1539d4d30b27f50db74fbd05c87d7fc09010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc576ef0bf8e01ff27fee4b41cd8bfec3940df90469b020f94030a54e39ac9ef04ae3ccf9b0dcd1faff6da16c6e375204db9d796e2a1c24a9a873d75b85f77705	1621016214000000	1621621014000000	1684693014000000	1779301014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	186
\\xab0d94db98b2a9f52552ce52242a4fa439c36ac91b9e136693577fce7967b3d02ce6beded913ba6964974cdde61a6a00e6d26e86399d8faac1584a2b80d0fe80	\\x00800003be98d02e1e332f987f7dfbc523c154762e4b0f016fbdd2b667a3da268e735831b6cfb88e9ca0f28c3837b016b9128d692ccfa58814d815fda4c64a2cdc7aea0f06422beb8a7bda43af34fa8d5126af54f21079681900e8857b5a3d2f3627e9455bc8cae4cb06ab51f36374b2855ee1af998ef53291ae44fd17e57d564b84f731010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x14c2f579c505fd070dd880820a146abbbb0cd8192c2baec70080fd4751c753960358f3efaf056bfd891a09aa6170dffbbb22d97d4f777bce95b39f02891fdf04	1637337714000000	1637942514000000	1701014514000000	1795622514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	187
\\xb3f5087c17ce1fe73dc92bc597f8a440453a385537ca9b0014be3934f5aa4576ab2bbf5d1d152e1145e4e81b55c46454253867eca198c7001c51cc4fd1b6563b	\\x00800003d3f262bce652cfa4fe3e26a9ead12b1df3fa175324f974cfc328947749ac4de649f81774ae3599e177dae8cb95d1cbb40c4a7e48cb88427903bce49486fceb19381e131311134360dfea71361dfec7e8fa8939d3c55ddef0f64b582e1945312566559b2d1c435a5e731e889498de39b60c18bde83d793e438a69685473d01213010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfa4cad4ac23d51ae648c747255670a11cfd70a7344ff0bf454269216cc3a141fa52431bfc49931c7d35fe8e1a5c2e019035527ea3485c75e9593fa90eaf98b0a	1627665714000000	1628270514000000	1691342514000000	1785950514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	188
\\xb419e728d854a7009c03f61881253e364a37bba5bf8bd61edbc88eaede598a1444be80e493b82b9d7b07f02f1a225bbd2032abf659a4dba6c5114c337b8e6244	\\x00800003e16b810ddc6ad05baceb2930608e419af90791223a7f6ea61832ff1b0d8ad9e2277c6c868f17b5fb7070d09be2a208a2bcea4580234ebc127d643874ce040c03914fef93d7ae496b10dc38f71cde371dc4d0239a57df16d5848865ef274aa8224c7b0a38f4fc95feecffa81f1f09607241a659b7a48109e88a8b11e0bbe4bf7d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd22548b508ea207e66f7ca26ba30c962e6bcda870645af21057f1d5c4abd827d686bc595a8bdd720c858188aa2a977348263cd3331cbc65db4a710c59ad78a0b	1634919714000000	1635524514000000	1698596514000000	1793204514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	189
\\xb53194e7e7e9e9fc4cc210fa9b1044ee7333f1cbfa86bed49e03d0b909c6fc0ddee0322371c1e4a70ce984a4ce597413678724de2d1c43be5bef8220ee82edd4	\\x00800003afb102c1e928c441de6ea5670572b49cbfbd90ace61e628291ad30e087316dcf27c840a9621b8d5c0cae3f5d724d4a8c2f9cdc3d3d142c43f2347b5c31da7bc2309663068f1b9fc53c67b9468c3777df7106e055208c77152bd67738575d2aa542f14c12101a453d7e041234a2a66e63cb2dfd526a5110dbb3849ef0a0d942eb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4e4af30c9589c7ba43c812649694920cc728c17ce6ae62d0f87986650dc1209f2408a9dcbb7f31055a12a1680d3b76559371cdc26fe7ef6037401ba87728a40a	1611344214000000	1611949014000000	1675021014000000	1769629014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	190
\\xb629d6d0b84497c607b3acaae02461ba5981da536f1ba2943f00489183e34bd95b233560522b10eca0f9580056a2e4a2e5c8903654e6b023725bb5c95ef26df5	\\x00800003bf8ec202d01e0fbc985197835d460d2d65efffc4ba4139576b5059a93631a00169176058fa3996be4e675a5e327b443e5ef9f63492ed1fa6d92a28981fd6548a3dd19043ec45423e34a56e44ba8c7357072e1ea73cbc7f46aec6c7f58eba179bc587db4213ab137d40dafbb531f72b745bc4dfd09e28372b82de9bf9845a70f3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x84851dbb1c21025530483d925ec2e8d6a4f7ed70db183e68efb26092f0e201030b9d21c276db3acabcf8fed41bf8cca072252f3a6e3185208aff0b81d1ed060b	1640360214000000	1640965014000000	1704037014000000	1798645014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	191
\\xb809f9b397be3690d05c2442199832fe2aadda62ebe3b8f9e118ec8aad1d70a09adf1146c6605a09fddf9babc3ffc29ff5c13f5f507a434835b411f36e394b4e	\\x00800003df339053a1ebedf882b548a6707bb845f2a629b17017c0494db740f2dd7dc5db71bd5c7959e5878331204ea8bd537143bda3524c823e0a1df06dac2a2c2baa749a8247e9d8121a496b6a67e5d96e2aba0538e5b031fbf72e9699da605f239a15c153ff1e1a5db8ba5b183263500388a8da2b498b9c13ddeb827d53f2e23ac8f3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa97c0be72e069c2a5538a9b3142a3e21640312d92f3cda85200ef0e24ade3c8f946c784720be62f9e94bcf6a39ec2cfeb2d689cc1791fbbef1647917d2749204	1630688214000000	1631293014000000	1694365014000000	1788973014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	192
\\xbaf553ec8d967bf7d9c4eca0a0d616449b3642a8fa81424373ee52bc18b3c45b93c2c84e8657e3313124ec3ceda6383c4759a2dbb280e66c786cecf995517a83	\\x00800003bdd5188ac69f2dd1e70c0e2d4fb6b75eb4d70c526b31f26775d78c3833616c034a4d90c9b98b740d9a1fa6f4cdefbe7a5a6aeb54ac1a40acb0c1446cf416e1de7dec8f3db6c61dd1b4cd4ac08a6009621231def1fd20d98d80348e171a0edb4606acb3ea0c5b2d64692125ee7873074411726134858de1b3984f647844545fa7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1d22d74b8aa123a4ab4444f22f9ac9719b36be66b0e8ef82a6acac746c1da347a5a1ae7027c024a1dde4b2c1d15da3c1853e6e74a453cfcd19b776ce2f23150e	1639755714000000	1640360514000000	1703432514000000	1798040514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	193
\\xbe99f0b2ca1513d8746b340c431cfc23b49b48a810161d4b7c19cb373965f3b3318a840b2023e82ee97075565839207adb2728cbf1e802bdd739b167fecc78e9	\\x00800003e5633221630e13e56dfbd783ef19491c4cc9a9819631cdb08d16c5c67c56ed92d0b5564120bc5df181d22e88000d9aeb2f0befe7176002f106148bd3f9d0055e142fb367d4819c6b74680dfdabb7e728b7049319c371c65a7a41f562adec9718300edcac1663b648f99dc2db100904a5e3278128fba943c22d2deaf4490a6871010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x51dbe621a3b0b35d970ffba59f3e6248d3375fca18ae8d972611725fc8b1dc3383dea38611db481c1b0cafd15ed28485ee3a3d6b80235105a25949ab50fde30f	1633710714000000	1634315514000000	1697387514000000	1791995514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	194
\\xc05ddc8e62eb7b0394e420739dc54added2a69be7da01a9079cb5cfd894d43c28bf0ba42d0ed97e484e8a7c3e317389ffc6be19353ee83d94616438cec632bce	\\x00800003b649f275a4beb5f6039fc64fd1725a834316d1afb57611832143d7622e9ab123b294ca18804ff4cc476d6391b1fff238d06619c6b68f5271b687a2a87f1c2f8d72b5f12688a3761cf97d56448db9bdc0c7c45b320c39b8df938de35853e96fb39cedc1b8ecc2dff7c2c5fd8060f1d517ee42e9b985c7e8a87c9369143860300f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4ea92496c5b5994b3a1d21b9283b3e5c417343ac832a82dc3c9dd56579b41b5fb9fca3850ab94b3031f8fe637abd137a770a4b3cc7871613998a60894b93c60b	1633106214000000	1633711014000000	1696783014000000	1791391014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	195
\\xc11195427b79d64a148a55d77d2fc74875406f961294beabe2371b6327700dd7b409ed0d797e9843c26fd87a3f2d75e8150d2b2b0944ef64447c85f37bde3fa8	\\x00800003c9b07ae6164b02560f9b0fbb621fb1f1a25b1d2e1137818206f7e4acf1e9e296bd30c827414fb95ea17bb08dc664f317aff420542ee24a1394ead9da0be9f9ed3fb012c67829c241e4159b87ed3e6c3df6d213b0bfb6ff725c8adc09ec91f989184076c82083074bce23a7b3e7a2eb0c27534482a971572b3a92a9576b4631e1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x542cb72e1053e1ca6ec8d0579417b8d9f274199432f95b42d164d62c50193e5f3af4b9555c67d7397b7dccbf45f1e82707e8a86f3c25334e3278dec3c0c7aa02	1611344214000000	1611949014000000	1675021014000000	1769629014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	196
\\xc1459052c58ebcecb3abd5ebd06ebd7996ee18e68838628a4b8b020577f4f08e0a1f3be43de140f9addd4fb13ae995685901dde4426e182fc64abb408b3d0c2e	\\x00800003b3d5718de02dc297c8d31a1dfc2364df8ce4c454d8d4586ae1b193e76b07c699b390d3ddbb6a576e6eca6f0a5482e76c7ae4e763f9e1ad3c1957e7a5fc5408e0f3a0907692c5e41c4def15c487043828f5ab947d802d25c3895489baacd363e8d2db3960ce917247213d58ba6dcdd5206a87ff4d53400b0fec3740d9f8877d45010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x09a3ce7cc7b546120aff24f5049de31d9e4bf7ba2c277d495f259b3c66c7e30c4a42a004fba97a50770a21068cc4f0ef8dd378ef3b4395b1cfbe2529bf4eb807	1610135214000000	1610740014000000	1673812014000000	1768420014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	197
\\xc5e903ac4975f3ae41b990a46ebc2fd8cdd51bd69ee61437ee3eeb02ed0e8e34cf79d19b0791b5db6e8aa053e5243611fba3a88b0bc367082713fc450695a4d0	\\x00800003bec1b604c41a217203c94a06d94a0530de848b08be10d9dbc5001fca6f33d2434bb51a16ad8aa0043ed9c3f17844ca68e31a0bdc22c1049d5b3da2bab85104f69f7e70e02e1ad02ff2e86117dcc955f3e441c185891f2addc610f486fb34daded446d608fe10a824050762e4ae2d16061bcb0c15f5d34afbe1da3492f45d0955010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa74f0466c897dce367c32bdcd71120048ed4e661c985c03263e69b5f4be34499e291908bb4126e05a88fa3914b73e5e590e9c9cfee6fb36108441de536e10d0a	1610135214000000	1610740014000000	1673812014000000	1768420014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	198
\\xc9f580017d78b9edd4172d3df230161d19a1e0546fdb48a5715b91da4050cae21b971ad33485ef45f08d2c20e129b57d55832deaa92a8773e93d0c62569a0ba7	\\x00800003c6dced177bcac9160370029f09242325f6698648e2ad30387fc780790252a3466888a0ace2167d8b551eb02405642c1d49cc9cc7bcfbabaf545d07dccba432a1a8a6a0e7ce8c88aaf5da05758c2035a64d9a374af36edd57d775874b8e5af879a5d70756b3603c0db1b6f40697628b2f31bf72776e4a94c5a59f22b5aeec91b3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x58fa297bebfa91bcb40c98eb386ad3ed17e3bc4675560f59d6fed0ae001f518356d7e2598f9b07ecbbdef43ab542435936a9a33784a16b4f0a2474710fac0b0e	1637942214000000	1638547014000000	1701619014000000	1796227014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	199
\\xcadd8ef066bfb7ceb12ba69324128b582afd9e684a061d77e4e2f0c3fa948dc513a6b64632e89410b4054db81ba0dd21a08642dcec84fee88b56a24914a809ff	\\x00800003c223e805078aed2d62ccbb220dce79d5a95949c385d027d0ce8f9ae02a3df71a6a85f200cb8b51b10e082b90eccfb9de216b693c8e1e5d8711a0fb8b6e2f3e1b317d5606b863061506b0e526cafb77d61456221e39320dfc77d0ac15296144c3e1e95513a460ec59f55a8ea73a76839e9cd33857973840b526957ec95d435161010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xec3055d67c0889e321238e5e253ddef541fc6a51281d03c8183a5425da9c5bd44df106f398799a9e43d58252d895a70428e8f4c180316fb7ef4e6278f16aa700	1617993714000000	1618598514000000	1681670514000000	1776278514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	200
\\xca51401a4f28188bbfa24de6539037e9d4e5b7b4910b06d23b0c2f9bb9a7aa52e421715de3053a8b73e10795613d9b7f350a3722b61fbff8c8a22a8f6948312f	\\x00800003cb972a9be059f67e99c966359f2ec85437856047e3d2fe9c2967fad9d94541a051457a278fcc431a9c02466a3bdc667d18b704c7bce9febd00fd75ea718fbf7c8c4bf6cb73696d3d15cbb385d83dd64558e620b00b023c5f0a3c329b18df161c88fc282b8964d90babf5baa96333fb191621666afb6d539f29c7f299350df285010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4eef1d8c4667b99c0d7de85657f87ae3f79027d2e9ef258dcf5419bccbc29920aa3ed8b774c3b0d3e92c49630d3e531cb5d8f1ddbd08cb33528f89f3479e4001	1636733214000000	1637338014000000	1700410014000000	1795018014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xcd11b7c3503a7e333629102ed2abe8b34831b567fcbbcb2a70cb0d1b663848806daca30e85e977a2df1745c7959994e91bb3877246ac36fc199363deaad7ea75	\\x0080000396e4728c8ad932ce423d5933c206cbdca1b26f0db858c146bdddce83a511e7a8b0d1a4c01a9fb4e3e4277a0f7e9cbbf39377ed435d47c71e016206cacef96392b2af08d44a2173603ffd9a3732abdc123765fef9f4838be310fd9d34ed25b5dbc46afadb6a4856a8f5eddb9f64c4dc97df9121cd58af4be100401a64f8045341010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd52fd34574e8b43c238f2f72a1a3d888f6515f3e079d18f119e4b99bf61fc26c7b4aead0410ee68573cb7ea91559e0d638e558dcad56cbdb9e5fe56a47c03901	1630688214000000	1631293014000000	1694365014000000	1788973014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	202
\\xcf9939ab57fa87e6e35186493267162c5ba3f52ad95eb5270e81c2492c83156e743090803d804cefa47a6ae1c430cd8b34471027ca2c52629bd814bcf301bd21	\\x00800003c437e03da1092029a6729cad33fea2fdab91ef6cd5c4c02b26daab873f2186931193e383efef0102116505625a8d72eaf77b32d3a134eedf2a9b64af20b92bb99accca78f47c195f1dee3502e99f1801e6588866b72c6af09a94147a1208d5588faa95d67eb51428969800d0335f2dfb7d69a133f0ec8689dc99feb5bb1f53eb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd88a56f3ea6a4fec42dff9bb9d41a86bb7ad3b0f7ea5cc22aa9212412e943b359f70adb128b2fdf323132144daf1172ffdb0917ef44b54d9201dd97986870d0a	1613762214000000	1614367014000000	1677439014000000	1772047014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	203
\\xd60d1c09566282126ba2f45495d4b3201bd5668707def76bdeea4ea5eb8d4f3363d1ceba2d0bc65125487c74684063b10cf774482fd02b4e5271c62ff3d9ac4f	\\x00800003ed72e46fc53f9319fb6b6218ec9eda916f089107af09ab017415eebdd5a1023c99be863b0373ab951408c8902104cf775fa634fe0021c234baa7bc1430c39edfdcdd8251e3f68f7eb4e4e554b4dcc5e5f90266eaad4a750eda5f8f8edb36f21e5f3d919395dc6d95ada8d48552ebc3cfc05a748f375874eebef1c325bdf55fab010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xbfe75b666e614c6b84baf9ae26ec187efe42afbf8d94ce91c5ae5c435eac4c2297d880a9672b3a8090da8ca57c5d7e1d6926d6776d4d7d320a39a205566dcb0e	1633106214000000	1633711014000000	1696783014000000	1791391014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	204
\\xda41cc526851e786badecc0de8de917f8c503a8c1fc208c1c95d789223ea0e90fb0802d0b55e4927609049ef1f0bd499e9c26ef6ef5ac6ecb0e6481babe98e2f	\\x00800003e4fb9fa058c25bb09fe82931c7bafa88ebf940d0d8d19a4f0037994ca5d2497cc42c9553943159818c610d7f0d5e48f06c73c9f228bde312f6e7be4d8cfffc67a2f22957c744347dc7d99d41bc1972cddf81b21568b4ea322ee63a9ce24cf3715b62f03a0348bb9f9e636c11c7dfb91c94320f415f77c5d41281fd00f5f43d7b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6d409099b1e4a82606a542dac11d4a36b220d59584e5e94e605ca70555131d082ac2130dd8d57794e1aad74a602eb1e991b48d1eac61b263118b866c1bf44405	1637942214000000	1638547014000000	1701619014000000	1796227014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	205
\\xdc81f0e1746216a3f09bc305dac0c9154390378c4cdd8463b930ed902037ff4c1b0454e588cc6926c467f802abe4b50dd94c37d1887485198deb5e841ac1710a	\\x00800003f29281977c18bd2d0a821a02a8695fad158e40b398238070d968ddf672ad9179d599a633245c2a465faa7cec6ba9c8ac7560d90a3ba75930222a7611abfb9884fe6f46340f134564fd39073496593e4e7ca73d2a1fe75cea8af61014bbc7df68ad288f7c3b2ee235147539063b776c4691ca84eb5589320b4b8920385bd2d1d9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x75ee0b9fe01d0e147319ea531fa3937c5c8fd54b4b951f0f54f185c189f3038ee17870a556bf890d218e2315b62b09089ae33d31a49cf50fa96b05108e05c005	1616180214000000	1616785014000000	1679857014000000	1774465014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	206
\\xe209f9a6e76c23c3c15bdafd24227241a316ac0bbafb6aea892d03bf2fdecfaa4c7dc2962699cd5420e19688cecd122e74ec030238f80dd32312f2d8e345e31b	\\x00800003a903fe050bf7f713eaaf3a9e05e2900591b32f60abf3ce2831ed28fb4c65485696d004744df01420ff0d74d4bf5ab2b5f6cc6ff9511ad57f93f0799cc62cc2bc1bf25a18f4ff25d10423d292f0d48a060566019301da58fe4c219fc9c9f77997eb205234a0d390e8c9fd56ba6b3a71708fcc3714f3e61bd75ecddd9b66e0fb45010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd83919ebd5c885d7fa09e3857c12e0295f311779a91c24bc1c2b9ab8ad646642040496edc0510fcb6a9caacb913ac4a0fe3d6ce4934c7753394507b6c022200f	1618598214000000	1619203014000000	1682275014000000	1776883014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	207
\\xe2ed6aede986f741301fba3c033b041718b8d3022ecd12b9e2c976c27a78a9ee61a5959fd3cdedfc91bc07f3a09faaeae05a2fb389ca9b3e05fcc81ae7e483dd	\\x00800003bc5c74ee570e1e26de23de8f9c921f66a94ebe5efb9ecfca80b362fa2651bf6649abacf38a4a25f4c6be8198b05ecaff924d6d07fcb3501fdb6d5ccb0ad5bb3c9f9edaf66e63090494413e4ac1f33eaa6c8112fd31ebb1fbf06f51ea597e8d79af54902dabe323a45b9e379126c68977cb50547917054d90f2de1df14a0f0911010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcec7157db4652cb637aaf4eb8907cc13a627497957c620033f53956ac11621de721fa533251e14aa1263caf360a0b3995dabf429987741bb458f70fbcdd76a05	1626456714000000	1627061514000000	1690133514000000	1784741514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\xe8c5262e4823796ff0a11a5aef192092a0b186f3d018cd9a281069e2d286c618a678a0bff8a9364a27727d0e57c989b2dbcceb2b087e55bfc725f4584d826a45	\\x00800003c28aa26e9cc197096f922363109110f514e36ab3b1b72374614dba44edf28f4d7337f63f0e84566fb5ac09d951544a6b25e836bdedae8515d2680ddaae4713d3e5214e910c178b025b82c70a9131a5db20889cb746886fc5e276af4294f6ca7509fe1b3f6bf10274598440ff5fdec08b151add13f729c0b37f317ffcb0cd2dbb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7c7a2b9c2c048d99af0be2eca19a3cf3f92bec0d667e83ad4100f068937abade8d9fa7f8e9f7fc16c0f5309a0bc9a3eed4da44e49c6d739b38366940eb84d30d	1621016214000000	1621621014000000	1684693014000000	1779301014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	209
\\xe99dca230a54881bb95f6a28dd610ff062e00cc736511eeffb4a6ff46c85024e40aedfe606cc299a39dcf8dd8a2c247a305a9e6d12aea95b5c4e523e79d54717	\\x00800003b541aae9cddeb1042aadc127aa757e32ffbf5f1ca2b2a006af3603ef87903ab5de39a95c5de24e677255f293feb40c0b571c0f02e0ebf4530291978c26ff367a9865d579fc5ce3770c063ae02ec77334ca55cb6e46575c2f0b3f68fc75ae74398731c2a3877ecd80dd5a951bde9d44e0d9634cc47582e4105d14d4003a1814ef010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3b119a1e92e4f35cb1821ffdb339018d0f0dcdd550a5b61aa578f691fe1c1a8d4bc66b89d63634da52b0d75d5db60ec4a64339eb0f7da2673d0deb7e1c3d4b02	1627665714000000	1628270514000000	1691342514000000	1785950514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	210
\\xe95160febf94ff7031cdf3791ad2504d1930410e619250a75e6bcaa6871549989a4465ebdb81eb7b422595bdb4234132f6280c720b538493dae593d21f53692c	\\x00800003decaf3ed91cc9b1bf96006a29206cbcaa189e8fe3c30d9deb3657fe23b31673f6ea9ff1300420795d7aba67884d9eeb4d81072fc6a3c8a2cb17f6dd8c56438b40b90fa27f219819175d86368b38bfb2fcd1e88c507f86c11ca1a0c309d78864d9149268eaa975b6a162a2f16b5d337579fcbada95ae43f26271c94bef571fae7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0608b005460f0405cbb6581dcd96d57af5f6c409cb5f3562ba398bf9ec3411d185f8f1c648c563524110431d3ab0c37bcd924785f1f38b4a350eff7c9bf15209	1623434214000000	1624039014000000	1687111014000000	1781719014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	211
\\xeb856550dbebb07aa53aa4bfcc2e2020eda94ba60d165a3a7aa879ca9e65de9e1f7d9bbc38a4d6d4ebb810306171be1a01ec0ce7ca01fbc0cbe2d2df2147e84e	\\x00800003bc904ae8f7628b79533e53f4d6f0e73d50e103f2ce7f5129a59ed5049e57f6b3cf86258684b751be7c608255bbbeef2450f69270a3af8311435cf3b444240f229cc756d3b3838d6a90d83d1c2f1cbec768a765246cda539cdfa5c513ec4bcc2688bc06c4bb268446518db44c46cd70cad5b18ae6efd790a7202efd6b8f40c727010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9777d084ceb7e60557de3c6fbff675b0337bd61312a319e79cce82d385e00e02c3722e93a9b2a4ad9dd9fc26c3f6efdf90d356aabe52da95c0bb08e92b351404	1636128714000000	1636733514000000	1699805514000000	1794413514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	212
\\xeba9a66fb14818caf877e479587b546ca9acee1db381643af130a02a78fbf1b65375ddb7d46aaae352ba3d9fb7e5206bc1c090c684033ec0c944b443eb36576b	\\x00800003b62cb31d0871b3ad65bce0b268877f4ff8f520ae61907e3fdd9978c475cc24ac72bf6185158a2722a41db4545f5d01e7584b1ae6083266b15df561e3ca568a101435e74d1389c6b2f87917ad78798286d6e7c35b468d09607132337c6c5762a17866a39a588be205c269e5a7239aa53e7f9263cd1bffff89fcfdebd5aa0fcae9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x62c4688098b994c10c19103cee2224a3e9fbc2c179859eb33aafe90858356784ad56b6bc1d066e6f054083262e5fdec55ec109b0819cd216ed04d7f6c71e670f	1637942214000000	1638547014000000	1701619014000000	1796227014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	213
\\xed4191919b9c4a9467fa006cf224109a2b2b9d4b2369995ce5b36486c3559bc53c043eacfd50ddcf188f6955539c90f6857c1f6ef84c0b3c6bcb4930e1080294	\\x00800003db035d26d8b3b41817cd05b37c740fab31580ed79cfaf98cce0316a1c680624d7c4990de55e1551ecc716c9a7f5a94addf960155a2e49173fed8058394d28ac475428bc12160c30eb625c5bb03589e8d9c744d2c89fb4c57fd264181aeebab529b1896e0e1ffb3ce2815278a44b581afe8e402463d2c3cbafe640b1b0e706863010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x40e5913f88033695338ac17ec8c1b8a3a1a985bc0c991a0ff49964ce7dccfdeb685ac5147e769bc2fd34d1214acdea8dad43907c2233d30944acba0f2c628f05	1625247714000000	1625852514000000	1688924514000000	1783532514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	214
\\xf29929b31d11c146de2195604a4aec5803fa1a197db56a0c981fdbb3d7cb8ae06a86d9c616331ce25f553f7f45dd894dd620a18ac2364cfbd1cb9261bb4c90f5	\\x00800003d43c40ab77fdc403438a964091617b486e8a947a54af8fa879e4883cd6128d015e6002fb0d1d4f6623e42895a4b61d34bdaf5d42b2e2e9f46072cff76405efce23257b2e4e8f41457c04a0852e54abd38bc04ceac1e617a0502a73b30c301d5cb90d2910a84a252d7f2170e1cf0a5c05abbf9ac0403c3bf5e981ceaa3d30ef7b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdd611c2e1484df2d8f6ce34ddcf1341799c4ac16140c3e64066331db9d0dfa2361911d3ee7bb67bf41e6d1c2a0ae456c5d762c9b6acca1ba8240864f0adb310b	1631897214000000	1632502014000000	1695574014000000	1790182014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	215
\\xf375f04a377a3b99b95c53ed613894551d96e33e5c8c483683de2955ed65b242425e54b3970b2702afb1120cedd6c5c0fffb7a1415854e11996774626a4b3c37	\\x00800003c68917be4e405b27dc3c0ad249ac3b4f161b362f70a9ec73345796ddde553f8aaca451b681f44793cd8c8b6784d345e540d73f37e949292e661e5ccb207282871f2bf5f0a561b30001e0cf40ed5e8e84cb605f11ed943613eda7aabb1946715069ff5c99d9096e26f739936f60b64c4054fa4749e991ec51fa04c94139f741bd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x86c8adc6e2066ecb502970cf768b34011dbe842d464628454feeac32ee2618e0cddae5d8be83af9ecc2c3ab67194e8d7f7969cbcacae86a2d24e981a0f4fe00d	1623434214000000	1624039014000000	1687111014000000	1781719014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	216
\\xf4cdfc4d4301ecf4e5d05077fe265a1ebf45d8f47cbb92e52b0c6dc7a997c9c4ff7649f712f363d128e970633deac498687557592f491c080203001764412ee0	\\x00800003c86227ecb044c88b570106b5e72ecb73151103feecd3f93d5fa8b54f6d3c63d190f50b994e7b79c441cd796a5e001fbe45aeb7d677fbb0b058455408948d29e927968c7cc8c69051153b194fce0d7e67ff2fe3cda81c41b235390b55d80107d988ebe03ad5668873df32e1b0bd9329d0d39e67991e94a504832d899965214421010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb2f1d22daac5c81bd6f5a00d8db977de4451be3d79e6c9b9d8076c9e08dcd9e3af932eca0a7bdcee855489633ef8d8c5a667bf0e43b23d713f11c8fa5671c706	1619202714000000	1619807514000000	1682879514000000	1777487514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	217
\\xfcf5a545a85a6b369057b440ffc1a6409d1b6187dc029d3c3e6b4f824b550a2a365a59db99639e84e250f9ac18ec270557fd968c0703277e9a01509735e2f92a	\\x00800003ed0470f62c52497ee7823ddbf2f73c47572ca51a183b5cbf7478fff18c63db8326a660f325d26af96b25a989e63731d3b4f29c6796e83f26c630a623282daea4f97394be849c79e8998444a4996140153cf79ade3303b289481c4a5828b8cd60157d15c3d48fa94f72c74ed855fb1420358d8aa3b898251478b35afa217059a5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x92f2221fec9ff9a68d108bee3edb81f49ab902896678a5b01024571b73587656090f613fafdb0c6d96d52279b70d4f78516ec110df80a292e90290ff974d1f08	1628874714000000	1629479514000000	1692551514000000	1787159514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	218
\\xfc41a33f1d381c7cb09d21045431209ed196b7e36dd9ec0e07c6d195004e372221d7e68ecca544f9b49228adc00a136a7f6e45feef71e61f8fa5ccb00760a449	\\x00800003c9d011e91e6ac7025c8d4c1da1fe68d83bfd18eb484ad5d1e1ffd8c4dd04c27cc6a64a3e310ded10c816e9ef429671e52a9cf41c35d0e2183d02c5c6235ccd272b2c3d319ad8725c3d17d21606659d3a1646bf6eae6709668c2e85af10aac0fbfc42838c6e566079badbe18e74a8dd5eb7a05ea4b2e032ee034b3cf1b3aa4ea7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0d49c9562bfe1908a04aa290e6bf23dde40f8ebf3226a59114ce8510ace6cf78dd7e59d05e0624b445866abf986b0401319a102dfb51d7c502c4002aaacbb10a	1622225214000000	1622830014000000	1685902014000000	1780510014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	219
\\xfdc5e6e75209f8980a4982a2bcd6d6d1f8902b737e6a46d3c4177038977227ff14c6d614e370a1a94e462a6055c4bf5ce2ca37b39f44502bcf1082add4177b90	\\x00800003ef15b061c8c5551cc14e99031535a73f51532d6e464fbdcd6c3a068b4fdccd834c8081cf89949c5cfa2cbc8e660268b7cc9d8e559a7435cd8385ef0feb7e3a0f428eddfb93ce9eb322aeeab37a2b0074097a633d9693dbeb497461e786c5de0f5952550248f23be4114abb6bc6d2baea4606ffbd0f3790f6944d22c4d0d9d651010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa3794b163389654e0ad5a41201caabd2d7c5eff3cbea2ba9d3f29ec9f08818a8791e56035b4078fc08a6ec1d7988305d5721283509bedd2223d55eb5e4d21201	1624643214000000	1625248014000000	1688320014000000	1782928014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	220
\\x06928d6cbd4be71dbec8cea56616afb1056668b17c566315bfb57789306295d1117204a070ef48cb993e8ea6e783001e50df24dcc366ecae5e5118ab1c273f06	\\x00800003a40d2fb2fc05af2bc5b75fd8fb42579fbfe8c2dc110c7ad4611410a4227158df1c35370b63ed17e353244c64f3de0a3acdbbae34c0c1ada8370bfebb43110d3b563432dee6e7c44f1989d7a0ffc682a15db4e07fd5d2d1610bb81c616a5cc4ba736a7212a94f527b6cfa6ea5d7ab0a251a8129222520f004d45323bd66b90f5b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x47000d8559ebbb3a4f3137473d373bd5fca46556f667cdecdf3d37214361c45e3f1c50716a2044174f646d839f8e73711e91d7e9955d95e62bdcbee210723902	1614366714000000	1614971514000000	1678043514000000	1772651514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	221
\\x084a14e87c702bf6d2103b66902c559c9edd4f659b2179ca3cea91ebbd71c3c5877976d09a784a2cdb069174dcca285f46ab5d4af74baccdb54b8918978b417a	\\x00800003da1a734c2b08f7c4d2d12e0880fd6d8ba06799ff577e146759efdb5229a61537d8e3fc633b3c83c5b43ea87ece0fa6150a9f130dc429ee7ca082d7b9284c29020538944e8414b78a1edace809dba6fc820b456a683768794fb58091888bed63f11dae25542d6a49d8ec20819d591ee97081aef2ee1a0962a62116e9c7e632d01010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x20e1c87aead06904430cb47192740804ab9637f26d96cf28eb9fbc6acb2ca1b96e1967892741affbc22c72b0bde46a2b43c089bb702df72dd41eccea70fea50d	1635524214000000	1636129014000000	1699201014000000	1793809014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	222
\\x0acefb72de9c8f282667c7ea67e53ac775fd29fbc037ddc205b01ece8ed94b34a89405713353eb547956b187fcbddddeb807b4c3ada74688ff9eb8dc2893edb6	\\x00800003c49dd7d06e6b917ccb2b3afb9f7d8ae0442a38abcc583bf763a036cbab8130841942ff5c00f2f93504c25a16e5036b6c5366432d221fa6842f382af741e2b819e9e6f87b50525dfd3c681ae455ca82aa3feea58ae515d78f2de760ad2be0be272af70383215d46b24401bfd7176ce7af35be5fecdfd24a0342cc4ebcc42455e9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xedf8e9d80f47df552ee7ef46400b5b639c07cb1e38bd374c6fbda5e5be430691214268d3ea112dbda3b047621975fd8f570ca24e85366596620d4e9f6748a502	1640964714000000	1641569514000000	1704641514000000	1799249514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	223
\\x0aaeeacbaae5f09b7fbdf9bd991f2d70a8b6417841fb78cad4fed59591d928a405780fbf87a402e813af79808dea891f1a433af26ce7749a2bcf8ae438476a64	\\x00800003c283b8bbf01d8a50eb32bc7be40ec938d4dd38318b644b59a122d8fcb7eabdd5ea9c2ef13a11ad15b620be71b87109a5bf08b474d8cba24f76ed95cc6e8eea0251bb38ea7a75125b4114213a66c0dfed4d1f8a64b7b03b22cabb98ce024e3940115fe235c9d74f769ef22ad5c8f4c4369279d7051518deaf820d8aae3693f319010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8fb153f800ed48a0fa939d1755947b22bac651c6bf3ffd67acdcfffc9741b74cd112408a03708a2cffa0ac36d344d8c07f1d143dc3b86a3885a5ad1eaa26b70f	1620411714000000	1621016514000000	1684088514000000	1778696514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x0b8aef110d9fd0128fd0a3d018132ab661f8d2b628d5bf69436dde74ce429ffa7738f9d7cba4b54ebe2606baba63558a6ca0d954edc6a9b25ebc18c7beeb9c1c	\\x00800003cca9d0b9d71457376a6afca6446fca5ba8a508cb1e624232f1a115458930189262aaeb7e7a909b054198072e43b34f0cbbf853fd1cd5e3e1f328e71b8f85782aa650741aaf5b3748b1a4ecd07850114d97a113ca05c2d39b854f3f8587c9c0ee247453cb365dc1503ebb0f6677b3c8600ac3a8c52e668dde06fed3f36bc04bf5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x22dacc6e204dd72427863712e21f4b3ab09e6662e0940eae0158134c1b2e6ba064cddcb86927fb06f2af7047cb3d8d85963f201a60c938d93d963145d406a10a	1617993714000000	1618598514000000	1681670514000000	1776278514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x0d56c222e97439f265098e7902a767dbc1f82f0361efcddf16c895c027ecfb21e01faa80f89cb5fd54ace9fe4b0886d65fe68bfbb12a7943bb6d7f00e1e3e064	\\x00800003a91184b80d380c96a55a2d0e046cc10e640d1146b49afbdd03abbae2be59f6149ff2ceeba027c0789ef4ada70bc928d6aa48c26d1439008daa55e5a745810a9f9e14ebd643a1da57f7bdcedcc47a232a9e1ba05da4aaf21879c71aead69d82982bc8a3f71d0e444abfcbfbcad0e0b9f9d7bb0e7b2debf92c28f78d9bbaa395e5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6944ef838364b5ae884c5fe9fa0f661168e72e2bb37c22a09c30b09c4db5fb02c2c15548e1ce0a9240028eb849604499a0b311fb5db4b7d498d4b8a3fa98f809	1610739714000000	1611344514000000	1674416514000000	1769024514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	226
\\x0eee89e64e7b6a75cb8074b63eb02407fe5a3e31e70c30d0afb405611cd7cea4aec24a46dc441c57f2d4409640f0036d37032515e0a7b7723889040088cc5416	\\x00800003ae0d80aa30f92ba3edca8a1a12cd02795b2fe381ff3bcc737329642c344624800c820a553ee2aa80a3834b9beca700df174e19a9eb1dd3b40fbd36824342efb872e400b0e7ea4220cf0aa20d16c9833429ea1186af216f29f86a5bc4a69e18cb4143bff5eecd504ea8a13be1bf383998df5e8e12ede748727a3c518c31a5a5ef010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x04dad3c78a4c18115dda537f38f04bb31da70d00dd2884b74f2813876ccb5dfd662188c1368abd1421af156777d247cb3071d727d359064d819c4676ab79c00e	1627665714000000	1628270514000000	1691342514000000	1785950514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	227
\\x15ca73e39a0e0c0959ad96b62df59355d9d886bd8f28b7858e7207d10e6cda02cfa4b29cfde89bc2f2bb98b15c41e86b963630e49d5fd984f598151c08cf2445	\\x00800003cbb728783aba514b2467fe4930af0bbeb6e2f41c91a808b39f60835c3a2ef11d542bdfe6f80d5ca280e822a06d6aee56170432fae5209cf02c58c5582d881fc7a3fd93e31e1e203cd7934d2b66961cb3c29f77758ab460384ac2016b3eefd4342aa31f7e3ec3eb3ee0ef69c268edb9d722940e7b9ea5c5f355fae1d599cc13f7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x184e335e1a9901da4b3af5c193bc85b609189efebd68486195b38b45ddd15ee7b7c76a2595952fcf12dd3f46883610f282353f175ac4418414b9d5219a228b00	1625247714000000	1625852514000000	1688924514000000	1783532514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x15d6b7b8ba874e5021a821c65764a0643be25dc2835aa3e068afaf6a295e4c43991f4fe167bd552c495673d7a84f4eaa4df5ac09e7460bf23b03d6fdf6665af0	\\x00800003ab06c241fdd4e0fd0be89c37f6bd108ab5c0318cb24ee2b412688e652c668a11bb5ed5fbf7b9a0c1a505122d69603caec27987129af6794511809d15b2c6c79457225cd881e3ffb7363df4e6401e91742623e65bc3efd13bd39076b2683c3dd9043748a7a5d739754fbe1f474abf08a399e96b3860cf10dbb85629c72c04fe29010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2ef691a0579457cf5fdb319d51af09ae86a805a8abada7bc0487b884c89f19539edc2a17aebc72c9f90443dd11e92bab9c1d20837d170b8e685efbe282751306	1639151214000000	1639756014000000	1702828014000000	1797436014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	229
\\x170270a1f82b8d40a36b2e39be0f08b092e0e5b2577973ed11c06943c5932157191a848cd506b1da9d9a5d797ffdf69ca1868a8d8d5c678f240b9e5a3aee143a	\\x00800003a308cf2ae394a559cc249aafaed293ffc8c972cabf54ed24ff8e891119f8bc89cd6432ec46d793b05c1457d290c2fff0ef5fad70f9f43efc29f4d3bf9ec8285e5fcd9376482bc29460007ff6f8476c24ee9917a295edf93c95f2f42e64b47bf37999c7d4dfdaff4c2170f2429e0c04fa8084462916a8e169029e7799222355db010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd9ca0626ec3b4e8ee62db5b3e541f023ca0dcb81059a2c6ee93633bb4b71ef6e2c9d73fb9387287f2751b7516b9e0b5b6a051c88eb5d36e12dd7fb3f3537250d	1616784714000000	1617389514000000	1680461514000000	1775069514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x20be9ad898d52d4e08e952d757a4180399dd42e90cd339f0e6ca6be33f0d03e5395395a6f5c76b5be0984a31d219145e6a24d94413ee8b38e7e3d2efb88bbfe9	\\x00800003b0c9cfb2102cf53a51a416196dcc7829b4cd4110eaa3519466fd4b5e69f4532d6569bca741fba9682355687784030c5feecf523811c974f5be95adaea40a65cea36d60cabc34122c5e41e28287daef32b0565895f4d8d2c046da61f23c13f56ae782f7be1c83c54c8ec08c5c717ae21b53caf1f45ac401d2c265fed3b25f5477010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0b1f414618f72d4d1e889ac943539bac1ea494fc54b1ba760c3eb4dfc96ea62bdc9a37ad9fda12a5adcd20857b5bdbf74e8fa6bca647f64c5818ff57f5f1310d	1622829714000000	1623434514000000	1686506514000000	1781114514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	231
\\x22bea209715a34221a2f1f0109a56f25cdd00c6bbc93acd886c25bcf947c36b3e407c97574f6608dcb79399df43af539dfd10a693c3663245dbb8b18f9c3be0d	\\x00800003d7a391a35edef86e3343552158c5954c11242444af40e70df2a452632336697de46d140be14e6e050a96896f4898724eca992cfc51ff0273f3f372e1aa95c252a965ef11153eed7fd984db27eb568b88a3d13c81979d5e24aa780cb8eee2f1abb820da81b897e6f4d06da15f3c00524b06988c7c815c28a621c91bacd5a70b35010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7aa15b931996be1bf6dfab250b6965f35eb0ca31c596128843d893ab41a7366f277ed1a4701e45d2d6a003d2f63bebd905ef331a9a6ce73bc7352de16e83010d	1617389214000000	1617994014000000	1681066014000000	1775674014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	232
\\x25ee8aa674e65cda6f145da1eb9b0eb81811b2598c50514d0ff7a7b0289260a4befa32880f5f69daaca5e1f75f1717b51de4a243b1438cb500ad59f49b8b4810	\\x00800003c25a5fa921b440dfb83ea1920607d69e117b62d4d5ca2a14599e93b58dc1388e067c62206586428f78ef60e9e7d098dadda12ff684f786e96f6279c9d45c411ff1e02d8fd6581cda0e49a9e10c53e01e57b3c007e3ea7da8ce99ca01f044e06380ba6ce9f869351025b976d03d4ec14d80383cfa2d689e1b8f1ae250c204a5fb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4b44172b8193a0c8453697f4ac35a38d376bac0ba747f9748e3416ff30181fe8feeda03b5f0cd0d7785fd1b6250970cfb0713603b6d1dba01b90387166685c08	1614971214000000	1615576014000000	1678648014000000	1773256014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x27c6bfab06ffd4e02effed13123b055bb6cfc6f1fcbb052599956e1b8ffeb83d32e6b6b8019accb0fca64158990c04a8f3554b674d62b460f1a9ec666ab6c191	\\x00800003b9fed88e2413e1c9ede9af62bf06d999861009963403ae83f0f0383b042f9658fdbe835b4ff9f09cedf3ab009f237fc07200c303bd46d50b587f60e091147b7cca8ecf4a868c85c6e3247e85e755a62f6be322f538e0b120b501e95f834cbe3c6e6ac54dfbf96cc2518def60936f2d8c085fea4900a1dcbcda0767640fecd59f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0a8cfaddfb92fc363982255c7c9729a1db7782baf23c6f049245f3d4dd852736bca3fe5c9e75336f09292b9ede92db482c26694fbe5d892815eb9ead47de750d	1628874714000000	1629479514000000	1692551514000000	1787159514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x292aae2bdc9dd957b283ea0815df3d70be5d376510e05f277b85ecadd32837fa73842d7c99466d0aaa0eb05b9891b9212050d509c63f97df3829ceb280c21870	\\x00800003cf121cfda98fd7c2b9cdb4b43db6abc23ae648f443722bff851a4daddf1142724d7e0b04e7e65128a69c92beee4efc67e203605b70bf5c346077d00c1eaefc2afc7095f932fc3582543d6d8ab270b997d530b69a8bfbbd69b57d37e01d727bdd4a9591da33b53189171deffb5753a1e0a2cd17b6ce2f92f4913201b69b61e6a5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x303e834476c17852bdd84371c6dc344992a640420d7214a7b4b708c5ddde6a53bf4ac5596228597471a26aa9a0e37ae17c832f6ebd4a877db11e9029c74fcf07	1629479214000000	1630084014000000	1693156014000000	1787764014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x2bba5dd1f8b7139c97894a88434052d37e8afe730654866568c9a301a46c2d7171de6fc1cd975ca65896643ad5b325f598d3a58fb173c8d0df31d4e5fa86d2e7	\\x00800003ca84429417f91f7984179fbd41645da69ec87df48ebecb39da458c8ba6ad34ba5efc40be8ab58187f8d080d0a416d50847bbd1c932f1b0acfbfc8ae381d98fafb45f0cc13434312bf74ce4f94e06a60e67a56b82df061385be9b690f68c9f11c5eeec0bf2b99fb89253111300e5cb986e5cf32a8cb7ac3feddc35af43bc64e0d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x53d153ca2a6549402f29200c798d688fb1f8a6fd92610e56383cd91bfac51c0dd8cd1880b91939ad3d646e91647e8ff6769d9a9ead27bc4a0bfc6664b7f12308	1619202714000000	1619807514000000	1682879514000000	1777487514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	236
\\x2b263e9764f396d5c7a6e4be60c73ee8c2853576420abe8bbf128973732413df477b6978094cd86d25553699f0fe008154d0857c919361a96c7d4e2f7ee64d6d	\\x00800003d4151f2c82c932c6801d6b9505823b34ef890ecec034a3034f55d9cd65ac362a4298594fdce8384d4b1329d2519c9606ce65c92a8c84305257ae730fbf9cd4a2e9664108c9c190a95c3bae990039912488e4f13b7f79807ee1613bb50491e66131d67df6f116e631e70e019756482e22bf6aec8b711c68ad4b05d7a37072876f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb82236350f9ccbcbabd35d4e232619a3716c87bdae83d7812ac81e68fe20b44d9f7e3009551ab7c92b65c0ab1e416500a34e3522e88c2364417854665ef80f0a	1629479214000000	1630084014000000	1693156014000000	1787764014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	237
\\x2dba96cb061593e3bd12329f0e11fe712b113904cf0013d05a550e6f55efecad2015b38fc7f12542273f9363aaf239e3d6cb0cfe2bb9f43c92942a17e82d759a	\\x00800003d6dde1c00db3e306ec166d30a921de8fe7349205fb4dfd269431b4edab14e920518ace0a470e3f14c227b960c3c75343dd5ef6944fe97bb747217cd1beda71df33173bab32e86da0a64a33949e717f8bb2a94fc2412dd0a9f02f2adf0ad5840ed63b24ca4e84e6182d560d37d45d03b94196eeb443ded28f9de5302d223f8c3b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdb8783084c1509400974216df9500d36abf9f7ae293ecb2d8b274cdcf7f12ac38397a2d687522eb2e514d14aea9683176b4bc84466cc13c48558b17ff4c3a30e	1625247714000000	1625852514000000	1688924514000000	1783532514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	238
\\x2e1e7bbdff6231ef8f6d4586e71e9dd1912b1e72d010ffd584c3fe056b717c3eb98f32742a80464662c72ff177db7b036b7c722a8ffe305739783fc171a1e82a	\\x00800003dd0e20ecf2534388df53f19bb868203e9394117679594829c2c1e01004ba897382a04e5a56c4b60787dec870212b78caa5bf7a07c0f85021438dc809aea40d319c5f9b147cf59907150b3379affc0629d55c75e7f6a6408811cc201635774c271851bc6713e2244eb5f574904f4a10a32fd7aa36d0427de4f8c3e82b3425848d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7eb8b485552bde935822ad5da20972c3bdc3df7a7f0167277244e2d10dd70bc9ae93370929af2fbc666f8d4b879a1ad682c39e1e3f8d748124b51c68ebb33b0f	1637337714000000	1637942514000000	1701014514000000	1795622514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	239
\\x3062bb14620afe427b73169ba418ba6799ef0aaae543c5c1d9b4fa36af5e1e0dd2c47ab5ab2ee17212df67e21cb4d78c3759be9f874feb569f1d26094f9d144c	\\x00800003c9c5acbc6d7871b0846535a33e19b54babb7896ac57ee49dff0bd4f9caf3b421bf2514104f995fded33f4a784a361cd76bedddb58dec35164f13335ac19ac3a59246dfbf0c6ec8e26f3f147b040e9e9ce82565380536c1725a64a8a2d0205036dc11b79cecb89ebe0e9d10634628ae09543eca538b6f963ab6be6ce53aa5c08b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x98ab602582635bdd311d080d27136cf34c75da917319c68d8c2567e8b5950b7ed13348b366b4b853fe0a8438923a208a7ad54da88c8f0c3b70a5075525eb450e	1622225214000000	1622830014000000	1685902014000000	1780510014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	240
\\x30ba86c3146230bb2da0ef385c984f183c13754852692c9feab5346f5013d6b7727f8a9221279b09bcbc0876a79a912c112c538589aec8df2425d4284d545b9b	\\x00800003a5be8e25d6815a5b8f1d7f8de8457d78d2ed05580eef1872870b1677f4b625b4844c66712188197c3af282d5d799da0b4636aaed631ff1baeae086fa5e89f33f4606b0017839287a7f84cf39f85d2fde75dcbf2aa3972b094154a6e23620aac71f88135da5bd8fc7a2443d9009572ddd5f20623a8e324a8097b8bc7eae7b6869010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x47a25c878fead329c691b14b4f137b8e6b94ef67bec74f2682a767eee558aa42729160a51fc889084ebd7386999ca91115c3da6a5055cd72c13ceb2961daec0c	1631897214000000	1632502014000000	1695574014000000	1790182014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	241
\\x31be6b792993e4e352ae47e9394135fcce3e1f904e1cfcfd74cca624ca5d5e23b57183d9a2b75cbf31a8896fd70774368585a5dbcccd650a69ae52fac34827c2	\\x00800003dd8acefbca7641a0304a621e7da8e6a7f1f165ed669c936fa84f5c7d7d3496ec05f5aa6f305f79efbfc8ef8c9bb5ec81d6d65619a4a69a4edd34ae34ce0f9e934fb60f66efcea70b6947f291a248450b014afb877795035bc5d5264d7cb680f94626600e28c287b29b3ba7244685adacc24f5e46bc190cc5847cf8e15b612669010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x834d8dd1cbd56d137082b9001ec8f98f8db4d976b38e173cfbde06a88b31b7c665772a03f45f84c404920ec92a3ab431737c371256a3978ca7dd3bb0825ad109	1639151214000000	1639756014000000	1702828014000000	1797436014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	242
\\x38a68573c8b24b2f395995c402315b2f06dbbd9cf03718885439baeeede8a4eaf35aa22d33193ffefc4cdef02384b2657afcb2310df6a46205778fa4aa6ae986	\\x00800003c94314a7096c5db32c55536478928975de201c118e7fadf2890aaf402cc2ebafcc945e539db88444e310033d86a98de7f136daebb7ec2fa33aa2d7cb9902ef1528b9580b059d8487618abf00de9ccf408ad8c2d8a4ea0c93d1d5e5382c5b91fced410817b7c001cfa0d6d2bae2cec0aa7d3065d9094e3cfaf209b2808d0b85f1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x344a43987183fef7be38c511baf2ff00ab77d5b2c322952b347d7f65a1db43da11aa3982d4843e95c87921cceb015d1688c444a6f0b8cfde55e61eae1c76120e	1615575714000000	1616180514000000	1679252514000000	1773860514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	243
\\x3b1295de72d3fe0358db98ed97bda7a3caf919c0ced9aa02b7dcbad2cf090aaa47ca141cff418a34350703bb398c15e8f746dfab3d675a60344e69d1cf79ca29	\\x00800003e1bb338a8184b1d7585f6f3e1277187938979ac71be2b033f7f1013a44d4a7aaafe064d6ba280baaf9b15638660ad4251b78d6706b6d2422171d5cca1cd028eddbafb1cd52e8ce6417ab0b9ae34886935a3246d7bf354c117022ef691e62d15a8ac2bc892b1753db1ae7769d222ddf3329bca37d82bf630f6733c74165690f45010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x712d0a1da4ca7f8642ff212b9e6ebd5b5965d144acdf1eb88f8dc6afd7e44f26a8f84171a2a349583d65b32748ac15bdcc42ddbbe14a88a54b9ad78fe8634c07	1633106214000000	1633711014000000	1696783014000000	1791391014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	244
\\x3b5ad40053effd8e294bd1450dfcd50c3d18d84b5678a963b9ae39e5edc3403a7e80cabd36ea369ccb4120112c30dd26288b79bc4f851ad4da631a8f24c2b96d	\\x00800003e3f4b82dd3653d650587fd4eb65c0e31dd46c01d82ade04ccf1441c02baa192a33ae1d1a70a31e5462aa1d043a8af265921f55af3bfbb77633539d3292e25b0f9f3d9a2895cf9347955163b9f89c2eb352a768e4153be10424faa41f956c652415781ab4a314a2d8568797ab89e8cd42d9f3c18be821d628cda4f6e8725973c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x971712b5c1cad2f985b20b6f8aea1add8d736786cff6af1e966bcdb52ca108c5d24874930e8db29ae1e93b97890c558e72b20c61ba62f10e602f62686e386700	1630688214000000	1631293014000000	1694365014000000	1788973014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	245
\\x3c4edb1cdd9d38a2d85953b0a5517bee9a3be2d6a9314d6cef3fa01eb6f84f46af2671a72337186683327c1f15331c2351dd22583e227ea46c1f177780e361fe	\\x00800003ada54ce9a651b6fdec4636fe4c38417049ed26b57bacc1dca6f8ae55ff3bbaf072be942790a4aad27fac6c9adb262dd9ada1cb5604f834d3c343f78932681083b5542a951cc4636baf40e366099bd02d87c283e2f9760cbf8ae68e1741243cdda3e19d2fcc6dccbdc6fb17ec49133b0b783380860a9a0f25893c2112b2a9fbed010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd1256462cff264d1c63269f8e6272491c48125b459eb5f0f2fa7965716a02d67bec9889788e96fc8bcf56bda03c0e21c36d5c2b593ff79aafa12cd3e4d01a903	1625247714000000	1625852514000000	1688924514000000	1783532514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x3e8aa0e8783846d2e557aa347cd5b2e7e2ac973f7411b82453478b0ec19e7c1dd690bf7778747fb75c9b376c781cbab93d7b9c7c6134abc5a315a59cdef2ea30	\\x00800003b2bfe0bef620cc4c09ee07a25a171ad1217b49e924ec42b20205c063d3769099bc24f88c8ac9a7d441518f0f6424a7147d9dd2585e7fbb35badfaacfc4fd703be0e05f77a5d466291a13bb4bfdf9e4fb5aae2829387df5a5bd9645b4f55b346700e9dfe817c472348ef0ec044f41f873ede2522057e49b59755b75398a551421010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xbee5801a640f3a2507bd53d8a8e3e6023faa92d555768c2df0ea939fbc111d4573b0a3f63297078025479221b1eddf2193547a94066b0efbe167e6f1f520ce01	1619202714000000	1619807514000000	1682879514000000	1777487514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	247
\\x3fa249c19e119984a45784550d80402e05709da7c566efa13f44824ee59c6a63fa1e56b4330b06681e242860ab7d295202681758d1accded88cd86cd97572651	\\x00800003c9489b7a438cade0cb68dcfd645e5a54a659a0b274b089811ecafe032e046a1c8e98d15c1176f96d47ee735a2ca0150e1cf7e4ac896923ae6251ebfdf8f04e6758b6bdeb8f1ca493e27587abdbe90fa246dbdbeb58f161010c37e53d2040cb779780a6b466376fbb5c9fda1e7983a56e12eb2098573456ef341ee81547403a87010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe6e899d3f022e72cafc770e260f10a01c044cdc8ddfcd02fa8d7282623f2dad77cd1e0444a244959fd740ec49afb56d7521c1b1d9dbc6a1a3351518fa9c0d50e	1627061214000000	1627666014000000	1690738014000000	1785346014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	248
\\x42c66ea9762e12c25f94d4f7241c831333717292963be81c95c77b19bfebc1374d24aea2cac263f68f44906ebae248461e7b9108d041f70b12f516646978d835	\\x00800003da7e162900203489d736d61fc266ab23357ab342c5eef98c7a5962b4dd3560f3763b386f0fb83b6c8d64570cb1d23d163b9d3864db9afdb269b1738223d86654e763d46746f14be941b50ac9c5aac333f321ceccd949cf05fbfe0e98e507a4a7d83f731acb3f3fcf08d31af8be8ecec2814d0ccc7991063470b33ea622a65695010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2fa8217a311f3e2ee4e875cd98a54935185411a878eb1115489a60eca148e1d0067210752aa48699d6bd099cdf534fe26c8fb76b81e0f292a27f39cb558da803	1610739714000000	1611344514000000	1674416514000000	1769024514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x4336714058f630593564bb21f3ea25784e12fcefdb9a8ac2da53f4be6e14417bb3ec4b7bd2ac5137fb014d17997b6ced69dccd6391413ad3710a7a7985fcce05	\\x0080000395cf27010ab2862ddc447aa345160918cd0620d634f9120e420ed800e900ad4c721191dd14ba0a6e8d0de77fd127221097ca634b9f480e59a494ab016259d96cfcfbb114f781ed4048b7be64572c01106e74b00f38a72501b1dca1ae862a76b29ea7a18a6d42cb6a23283fbe83b4ad3712dfbef4c62ef41e7496fa31ad869bcf010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x308efea05b3a67d7cd363c1ca82a3c431cb14d0989047035e8012102514878b03c93fec4d5f32336faa50416050a95ef1d39d45ea08dc4ab546a24c52652ec0c	1625852214000000	1626457014000000	1689529014000000	1784137014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	250
\\x4972660d0c2ce82b11c4cc9602b62b8b0e313880cf10557ab59ca1ac8854a4f71b8e5dc9248a85332b10f2a49e5b7881f55efba330a344cbfaf53f1f37309d30	\\x00800003d56de779e33c875007d7d062718edc14696197ed4b631d7e2fe413f0ed4e58b9e36384d572777afe72ad7224bfd107aec972ff57c20b284b5c5bc908be321e022abdc5d54ebdcf1638a8117f3c0d114b00f945559c1bbb0c6308a76d7fc7f1df4eb57256817cb23c5d7f64d9b69ff0c818242f30268e8008fb0c325319bbd0a7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xaa994b919a3c7eed3492ad5eb6559572b9edee8a5fad179602c076ac52469060660ea179b962f77d0693ea0ddb04411b1f593d9d6066238ebc30a2013a479202	1610739714000000	1611344514000000	1674416514000000	1769024514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	251
\\x4aaacfdfb615705afac9286982fe25fd57ee72ed24968e31a622f2b7a3ccafc54dd8ea62a29d2e2cc10d9e207c686e3bb475924a40bb8293df2d4fba25e4f40a	\\x00800003f0f2d8883a1e62513d367114fb3abf7c39d1b750b379eba555fee98b1bfea210a4b8886a5e9eda172f4b1e553b4310fc639dc466bc9e765a57349ed9c7ccde9c99685a42c84a809325aba8499c237cf279a47a5b5944b43777ffe7192029e187c08078400d9b380c7d1b7fe12d1dbc899925ca14eef7abc22590894099193975010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8d29df39c7854b3a7cdf0903788f19c574ae024970c8b33848f07c70a52347d54b7c39e178b778cbf152f32fcc7d100b3311684b2073238032acefc3be21630d	1637942214000000	1638547014000000	1701619014000000	1796227014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	252
\\x4b2af2f64aa093587cc4f472028100eb934795d6d70724de4072a5539f6b9eb68d9d2858c3fc9efd38a5e405a2260badca8c217ba067989a7e5a2fbdc5f0c6c4	\\x00800003ba8c11704fa92f5757f15c620056ccc4c2fb49a90d1079c5dc2785cca330b162625866bba848e28683d03dc4a9fb6b8070700935fcce0b21c9598bc9d27abf6e8f80328ef8f2ed5f343809366a03bdc805507363fad260f652846ac65b7176fc38c856c6dde71419d942091d7a0913e241f0cfc0461401c7ab38bdf52f0d0f6b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd5f24e91a0487c5d271197e9b78f3c7145edbed4c184d10961cdb4ae3c2100b8acbb4320370a88a0622bdc745654065335c57f1a6348e1fe1cbc2a9f3be0340f	1631292714000000	1631897514000000	1694969514000000	1789577514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	253
\\x4baab5305a67a8e8549058711dea34ffea97ce0bc13f7febda867d4554f4cd63ca6510a0cfbd7e68c9962f812b4dc81015af498d4a2ee20873819d2147973f06	\\x00800003d281128e6ae91991efedd6a3333ba5db6e41ec9374b67cf37b8f58ecfe9372b6ae1e5b28f9037bf7945cafab4ed35ba0084b37ac8bbdca351fa6e8591885c57c489c183c37e36fd13bc4118374d17d7eba569a563a2340f95543c16e6302385c843ab207ca7c8fba74d81ae4f1766a47cdf3b263e244971193ff5e3501539de9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcb96cb261ae3b5d0a9716dafc2d68bcbb313f8de33c2bba854b5474cfcfafc8d9401a23c9e44e55188f18cb96bf25f40923103bcd863937631e01c91a38f380d	1624038714000000	1624643514000000	1687715514000000	1782323514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	254
\\x4c9a43827d6163cc6a311e92fdd9c131f0e056b4b2e3c261afe7431dd9c1dd8fe397cc55c968950cc518daadecfb2cdfedb317eba01f181677a93b517e3f9fcf	\\x00800003c188d73adbb5ec3c61485e71a1670d452f8aef5e002a885555c2ec20639b0c633bbd6abd7d0a5dd230fe53a6bacbd7cd2d3de7c62d9c59b77912eadc40978944c0ba99602206daac725f5379ccf8e6b6b74ed999cf876b460e4e3d5ca7dea380019c99b7a25dbbed35981fb53ab08ef81cefd156de2244b0808e48a5045e0b13010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5901414fc593dc433285be57758e8615fd8884429f2bfe1285163af908605d87133087f93cd720ed454a90e1dd654adb3fb2d71dc326f596462280abe0c5bb0d	1611948714000000	1612553514000000	1675625514000000	1770233514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	255
\\x4dcab89d04322506e62cc71d7dbdf73444af7370e6f820e4d3ce7552568d21ab4d42c6bdfac4dc53ff75ff58e75fd3c0923ea8a1ac21156946dac05107c32fe2	\\x00800003a5236678f1d8ab1ae8abb28cc1da3eeb982cf550e4ff5fe66302aec02a82b1d4e67ef96db1417166f130f506e6fa048d0cbaee54e0eea5cb039dd87dd2ac75cf80c0d725dd1cc86c6e46de7d8864d7867b975c05da96a7a10e4e23284ad96984c0df39325ccd234e85d692cea4577e500c8ee319711f47f75e41aceb36c43cd9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xed1edab55355ab8ffbfa017fd414d7af72bc39602db810d52bff9212e9647903eca470e664b4425d13e6c8daf2742189c1c2632385888afafc49cea4b3043407	1611948714000000	1612553514000000	1675625514000000	1770233514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	256
\\x52069f43c2c646dab5319e7888640cc33a6803df6c414404eafcdb2839d8b49f507e8f269bf80c23ac8146706243d39ef2dad93f3aefdbeacad474771c23f17e	\\x00800003c4b18dd2f0686a2bce3f2b892d4146d5997317e427ae4ecba15e5e0da68e0669636320016e5ed7876ee67c546218328af4ba13d5d27cb11d31853bd16ffa9b9b8e5fbe655a25ce0bf3fea0162166f373c5b414c71a4100d7e9bc9aac1b38501648a929a0d789f2526d68aa37d76796f1b8679e6cabd5d9a662d543c95bc98c37010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc75a7d14be6cfe613933b600518138edd65f8bc6929b3e3b599787805fe1fbc8d15c518b2b3dcd4bccc1f9db9c93842a5b881700cc5491523a2a50fbb5f6f00f	1624643214000000	1625248014000000	1688320014000000	1782928014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	257
\\x555aa83e73b8bf0f6e731f650a0c00b0d9536fcf0e76eaa57155fbc87cea638c16adc5cbf8413978f3b9ccf4aa81ad8a5d31a2d1ea98ec64cfe36bbf59cf849e	\\x00800003be7f13f74486f350481269234b268153e81ee221ba124052481373ccef6cf0050d61fa202737a076c8ca039947ba1910cd9f22e6998b767a8b5859d9950324e3339c044065840749422265c83480254b532cd79aae28db29df2d83f531183aca415e8dd6e8feca5ade8f3cd600d9782ae121e286244032b7d689eee107c69b57010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcdf2beefa8aaeef23e174ad0689ad3613efb0c55c285a5f7d28f34f25c6c3d160d4d5ade6b7f8b1d10da65b1d72711ff0e3edd7e3752d281eb6303e93a3b6405	1631897214000000	1632502014000000	1695574014000000	1790182014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x55ae4b07aba4cba2c827a3e8dc36a5e24608f5f0472b69ff32605887c2d372bcc154f8a50a55c2eb7cae2ec1a760f708f10314fc1abf2e6d86236c01e1d21c53	\\x00800003d264120af700d2121274b6771956c7bd64442c4f73a05e09b10ed5918197ce3594c72bc6191ed23dfd78a9933a365de5088b7391d6dba1d275329843ffbab9c84e54663273449805fd3073d9e50c17305364c6d1634bc1863a1ef1f5160c03698fe06e1c0e1359f3f593f424f684830973548d4e00ae8b84dc932acbd93e63fd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf8fbf9985bc554ab332888644a9cc32c9257b2d4073d6bfc459bf0487326a33138406b9174ac7249d4c7a6c18dc3482a98803efc5eb7f93334d6e0219f891107	1622225214000000	1622830014000000	1685902014000000	1780510014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x563e73bcbd36a537f6538e65f0c2917e0427229d43804501ac71b99fcec10c4d95bda1179c79cec86dc42a51ed11967fa708cbf837c3c66e88a345d229f97fce	\\x00800003b29608258d90ed1398130b38151e516bb96ff6f5570e79a042842d042189ccdb29640488cbf94f7d4c5a4d99dac9d4a62e7768f93e6cc33439173d05b4e4c53e168e5d4dedae394156858fdb22876bf961ba608ca49ae00cc06b820ea3052638a3728884851e5aa9dbfe52e0406b2831b60375a4a54a4dcfe1fe05f12babc381010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x269f922f527ced565a63059a37ba5a91c02c531d383b6f0eb06c7d9b9ff555fc2ecbf172a8b9cd8b7cdb3e111b6188459f4279db3b2c17e3f17048586c571208	1626456714000000	1627061514000000	1690133514000000	1784741514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x598a0b9e53304e048ac638aa8b0f786e7db5ee102299cb08f1c2ce42c9e5092a5c9d6686f337be8a5d38f88ad91c968d2d3e5130b4476bf6d515866caf889d2f	\\x00800003bdc545e976072d00a4ba09a74884c81a048ad85cacd334b07dbc76e735ca65e44f8cf344f85a08d4e6fafc6e47476abf3662e3f68b052392ffc5ab9c0f3c2639eb0be6a880b1e1d6062a607190bb3ba90f7b0ec64073fafa0ba36306c86dd0d3c73e9aceb7af0b3d10907e6a88131148e55d2529cb3b7b51a69546d9671db1c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6b03852c4955ba090207cd05a9b4b0cfb27aaffaf58c8ad6a35d78c59c3a7810dd88b9c2e0a8f375adf338353ca98c090024581b62d5e31af82f7d9e47e7fc00	1621016214000000	1621621014000000	1684693014000000	1779301014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	261
\\x59f2267b74e6c50f0074f690f1595ab90cc1002b336bf2efe590208a19d37b8ab134ac0ffe421761dbeaf964947bf649cee5662973356283a8905763b0e5d0c3	\\x00800003d2b2d245fb6b38118dc90380f9112fafcdf5d7d7de9bf82eddbb83a0bfde264dbe6d1f6935c9eb78b59900c8f38b97df51621f35d6cb4fa89c84dc3cec04da6f1e017df3c9215c8305d5acc6ac0245153f59e15c263816e0f50bae9df54cbb4d4dc0c9363ad607742b88d82f237b39021c41a8baac159f28e02069ebaa43148b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcc9217ad023419d7bd3b7ea3f58659f6fba71eb006e10d7f7d2fa471b02028fd80785033ee608dc3918033e91bdcebd3d21364f80480b397e9ce1b688c5bc700	1621620714000000	1622225514000000	1685297514000000	1779905514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x5b2ebc86a5927c699bbde785a7e6bd61109957328850f4778819ce4378bbe03490c8147fa4b0bd9c649248a597527b08e9c5c05c1be28c020a09dd407eba3adc	\\x00800003b4751ac01cc074a1cfdb7e8c0bf3d99908d7fc73857abfad2be1c9ad9d98a0e5cfc9e10d9009c82aaf5a8024f76956104187dd8a00ae8a10de8a3045e5f23e1ed03a703514108c8af4f2603b031ebb664109673163dac0309e47e75be5436dab17ddc75111b3a2bd1ccc18136cf48577dc9fe9f7c2f7e9ceed51286a39d02c87010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x42e84c35ac141af8549dff2ee6a2d8e1fa98c6af81f7b82af0d3646ca13ee9b574d541d32f329caab620c911b4966a8188b2375695775328fea7469042755b0d	1620411714000000	1621016514000000	1684088514000000	1778696514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	263
\\x5c36193a2b0f742ebd45505e9bd3b54469267fcd13fff53a9a10ee3592498a49df22c0bdff3c94fbd5db171fe65680706b94326b1ddb3f1f84580d4eb886aef5	\\x00800003c646668f694e85c959e84977e17619593f3864e069509fb6a8283810c948c51efa9d35e66f6db66c310da1dc651c16876e4aaee77ca83ac0f94002674dcc0d2ae1858e4b5c8349eb434b1bd817f2a288c5832912e19f8a92de34eac181111303dc8f81581f472d2cd15b93bd462c2aaa4b601a1b945f91a83730f72717b5a261010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x57da27d633e1d974e8a2acf15b95cf3207fb398d7c1f35bc0bb73f570d4c6b035b3b991a5b15b2e0e33483e4d909cc4eb5314b42466df480a678d5e19c1dea01	1618598214000000	1619203014000000	1682275014000000	1776883014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x5d3673aee4b8681e08c9dce575fccbc1d2e6615dfbb83a1c5844ac88bcbd4f99f7a008d8e514ac969c0e9754a9e6dce92cbaf33dfe851e19b8de3efd20fbc19c	\\x00800003db9219c34809065c5c6617ec9cf368de64e653677143011cc15dcfd684267ed84f4b46d86ca981a62445c616f20a12f84f8a583f9893ab5de5b0261f95c275486478d01fd3ecaadfa5e0b1e6028dfb62fe66a6020dffc55eebf4b8ca6ca8697b063e70056299499fe3f2eeee4b6d4cee557a183d95d2843e8939cf47f7cad3e7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xbef702bb3826c9f8692d7b0de41b41f7f37cfd94cc20e76a07b32dc2c4c2e8d5ef4c29952e99830f51945e02dd14769e3a15bb3e888e99737646d5f99cf3da01	1637942214000000	1638547014000000	1701619014000000	1796227014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	265
\\x5d8efb02b5ddb857a8688bbfb11f1e0696694191e84dbb2c5bdd38c033a46cf3ef9265dec3c3baf236153e6693da3f0e43251010f6cdf62eb654b7ffdd84c7f0	\\x008000039f81abd6e736d672933a1132e8ec3f03b244c5437b47a8215dca549be2ddfcf110fffa800e964cc798f2b20c60acc40e55a3b767797aa310df69cbe148fb283d715972cb52600cbeb5c70baba80bad12bfc0fd00bcc881b37d2083fcc53c3da7066fc4eb169393bdd60a2b64d99be3830d5006522c7fe591b359dc8a2f32432b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x999858e28067c93e5ecbab925f575ae760bfb35a2ca5b79fdbb45d405366a1bcc12b120d63a8e6d1b4cc61b012ec195bd57db0ced0c85562e7a02baac6843706	1624038714000000	1624643514000000	1687715514000000	1782323514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	266
\\x5e66639a862d1814f0f345af0f2f80d3a4de6c264fc8f30250216a243226c1f8e88a182c69814a3ed7642db22c5c8259105e9e7644fdaae308c3b1c608680cfe	\\x00800003cc340886a6061649b868871e09a25fd6c507d67ee8615995007a9fd0d6e95b48674cc35295c457c470d81dece1b7b83c0c630c9275e628560facfc3bf1b1b6a6d5cc6692bba7f7f7b8c10a1e77f7a60ad6faae9070e155b800ae0095f36ae80e7a9c30a34931190b73999dd4e098101da6949b4340b029edbb15514269630bc9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdf9603b32daa16e03c07d299af2dce976d8025d7dd838877751ae27294077b196f012615096fea8f965e1ebad18bc25b627105f5b67ecd5ac2b3fc93883bf00f	1610135214000000	1610740014000000	1673812014000000	1768420014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	267
\\x6522f35d6b9e5b017f9c7fa78e4b94fd6f4a5444d27f53b062e90166f4e4388efd58f3a6e29faa0d2b2ec80958091e1af44d0be9aedf211722198211be8fafbd	\\x00800003c2b4ba3c1d6b4ad9dd5a3ef8f0b646eeccc4c546bc52df8c815c62ff09ed5bdad41fb022d37d998961fc62f448764b464acbe1f3de9de5427a300d4f53ca97520a36c35875623e2b1d62495eb9807ca4c07ed31ec1ede4a8597f81611115db85e1e7ee61703b8955abae9f4488f77308da507300bc2c9b3a5c1a7525e02b9a33010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x37a8d3d0ba859b904abd3cae006a670cce8c19170787016a6ba6a428d7015efb3bbbbe2b89aa6805477c7446afe01730de0ce68ea33a089890495ef59cd8170d	1627665714000000	1628270514000000	1691342514000000	1785950514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	268
\\x6aea4d549c9325fed0720a30684e16a7c966bca1de864016051d448e67ad63c5df1ed7e105484e7a4a50e97a7fb8ad0a7995c57beb5160d3d357cac3a9fd372d	\\x00800003ecba70acec88bea5bbb6609b99a307eafc97f4b4e41f3a8ac8aa165b57e9ab29655db0381984d40f6d7a7ad47b59c054280fc535aa2b87264e1099a87d184319a6a49aca470c987ffabe8056c70ecff500c907a4cc42499ed03a8080702f37a0bddb2f77172b0588942cee8ffe20901efcfe9cab456303f1e91c6ac636c73d05010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x792f18d0dc402c2a949f9abc6681f1b0e752d77e1bc7d37a98be17e9467feb46d62323d68ab7494c82c0ab14255a3879bc1fed1a151ae40d271a04cdd93ccb07	1625852214000000	1626457014000000	1689529014000000	1784137014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	269
\\x6cde42d5067e7eaaf2db8a96f5138fb1e3cbc14d61a968915758647d13458ef819c51bd13158047788199e7295de6de2874714b4879eb298a25b3f107f1487e7	\\x00800003f1cdaff9397a8af66d24822c7bbb151462b1af933ed720e7f06354f43c42fc7c1fd463936fbbab69deba8d8c302fcc9f184ff8c9b228c4337b7455925c7d18b6c863a9a2e90fb0f1b626e17625584907cba5de0babc1160a116fd4d3be0ebde4806cc67be031529081e009f8f2d7d8e767ba216bce1c004fcb6b8d9afb25aef7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x53b8ec5e9145f445ed6a3f810bd35ca7bd5df02555e0ed7655cb9959fcc64e8e2eff4c0eb1ce0b0355a04b379ced13e9bb07744790990a7825f8fa4dd4ecd600	1628270214000000	1628875014000000	1691947014000000	1786555014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x6e3669ea672f9bca984f2f60e7d343a1bb1bdd7285dc8c2394f08370eb2dff394aac179ec4b1c89be7c4fcc5c82742ee738952230ec36e57a3dec38ecc775c3b	\\x00800003c9b799f1a683bc6d4f0f5d0b1198b34af60c2577e1f58e52d6ce1bfe1ede9e720db0cc7834f5277441872fde15ce77e725263234ee360f2959ea95dd212e45cff28c403e338c94b1563658ab29d123b1f0e5349878065fcae21b2cc03456bc71e907b3a811bc35278b90583aed28d0ac24b19dcfc271e4a43dc10c9de14d0dd3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x835b12babb05b0abb9d120964a502c0ddb065d77b4f735d6e8daa04bb3d68808619880b98ade0fef62fd175fade63fb85e87ac712c7b5b28c0c05763a137cf00	1635524214000000	1636129014000000	1699201014000000	1793809014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	271
\\x712a8a6274e3af8ce52d9284dd61bf300e8f57280f0deea36700239ee1f86da2a17264a492d985d9565073710f0cfbcf20e0957e4ed9ba97808d81b58ae80ad1	\\x00800003d5f859a87dc3428810212ecefde1dc56eea1fb0eecc8843eca00f665f00ba78e2018315869a868b46bbe21498e93086348908c9d112eb538f59e21d635de84abd09a9fb99cb0a2ad881ab5aac8b67785e99f0751c1e0b875af7b0888cd712bad0b3ac224b0243d2e1f9da6be937bfc748bda7f79d5e101dd82779092c3a78749010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x278fed0cb60ed4ff5312a38521e2872a78a34b5f5bbe988cc7443b2514ccfe81ed7cd4c7feab7a6e0a562b9d91be33f281561cde82bf81f784e4955f4dd57105	1616180214000000	1616785014000000	1679857014000000	1774465014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	272
\\x750e6c20e21635b9b5ca105c1264ba2a17b3b1d9c4f361a3281dbd47f0e4ffeaac17be67254d1d3fdb144d1eb0e4938c0d72ba7a579ac721fd5a6b89be7f0124	\\x00800003b6be436d380451a11ea3f01875496ac4c19d8f8791f72d3a6f871be72bdfa0c2cca7a991afecb6e3366c7bae8ce5b57faefe233e6c01f1c46fd2707cb98dd10bcf36e2e41959eb0f2d88f95bd6d5793dbe21f58518f038004608b6b6bd957aa1207bf84fa94efc510f0a31d5844ff3aaeefd7577785fb7c47919cabf4f8068f3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1fee885c7af1634aa35b04d1867f12696014a27fbd3da119e891db17eaa62045eb7e07a7d6205481ad57ccfe2669ce5409a11a548101013c124dae942ddb5a08	1618598214000000	1619203014000000	1682275014000000	1776883014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	273
\\x75e2937f4d0f7a06265d83fc20c43e3855b5a4870372e7826d7d238d6beb3f70e02bfae524b67ac7014aaf9b3810f0bb4643cbaa509a83b173f9accde4105220	\\x00800003e296559dd481d9e2fd1e1822bc730a4fdc86a30e7be823f12b544eb7df979581d1c524143a406577d0c0120f21abe93d4c67eba603f92779d01741e0d77bb348c8f43acc21570e75c2439354f6be2a8465b7d0e7361d48aa41818aeec4e299d35a18512a79198b802877c1389ac092064aa8262ef6752ca36f15a87124c1fb47010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc6adfc4c7fc789dd0b28cda8b2a548fe6ecdbf67330ff4b2739f6ed8a2f8e1f9d68f11d4450cf65ede59a67e34096dbfcf2987582da657008a8073d526831809	1631292714000000	1631897514000000	1694969514000000	1789577514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	274
\\x754623f9c9503c23327a807ca02776a4679ea54cf6843579928d9a30212fba7e9e9cf9cb49b4fb3d0676670925dd685d53e85b9a2360002852f793418e2e54e4	\\x00800003e4483dc327f2906da9f113645e1e43dd1f92142f66a966900185fae71e5c9f952369e46c0a96714c4ed91253c1e4c3dc8496b08fcded286fd1f777a6fa709dc6ff33fbc1945d48117a99a8616117d08e38867ed3f36bcf1a229183a7023462ff3fa94b343af982e1d247133baea980fb56e01652ddec0df52cc7d12da31a04d7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8413344aca350590103d0d7e69ddfae36da681eff0795ff8319eb9d19d0ec6a1f8b0dcf3e1b694d60d94619f8423ce045f5cd87e211443d4e123d5066b0d9d04	1611948714000000	1612553514000000	1675625514000000	1770233514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	275
\\x7e3e8601819bd94956357ff99f9667a97e88d4d946c222c05e34bcacd1367690674c9afb0b72a2b6c4cf691dbd0afe6005747dc4c66e568e3c9dca7c46b72d28	\\x00800003c5b4a936fb5c7e4abe5c99ebc5b600e5ac5d107c7e951c57a6d12dbfb0bfe57739e36e5aca7878dc82cc50079f5843543c252c769365ce04a34e8220a7a25abf2266db83d83cbfa8f601974c648d31942360c1bcefedfd49d29134f11c57d93c0c5ebcaa3921f2d6ce10840ed5073802ecfb4710f17b661f2bec22fc4dc48a31010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2d6ceb6d1488cf65a55b1463f3c30850939ece9baa82bdacb9c28d262d56be12c64a3f103f4dc79f72cbc6ca5277932a1a712d01aa3b9638913c9c0565d93a0b	1619202714000000	1619807514000000	1682879514000000	1777487514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	276
\\x7f4e7b947daaf845ac609fb90cc2f4cdaae867554ba7a33139b0873282d32877843d4e2997d90deb92545ef0fbefc7889b4f95f5e43c62ab28bc1e3668391b25	\\x00800003ad810f1e6e84e29f0973d0dc11bbb45964de3efcebbaff99db30634050d45622d190f023857a4ddcbcac543b5967b64fb2e14bb5c834ab8bdbff5da1b2dea120f2e708d7675538effe764aafa992cd41d2a1620eda3c219e95c3b9f603fea15a883f29e612d1fcea12c43800aa35dcb0d25c2e1ca4fa7c54efb9273ebfe98b93010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8c536ffd6e1bf91b8cafce0e9df908ce8f21e5f169df98f7737008eaeaadcc5e76978e2315b3dc5d8126aaf791eaa10c5ce66ecf4acffec6b019f4570e98a503	1631897214000000	1632502014000000	1695574014000000	1790182014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	277
\\x853e1de2101cacd4cdb025d959ef7da9cd7941641b2dea75a6e885e645050966f1dd541e72d4eb70847e386b2fd5aaa9f683c095ac7c85600918a70e68c44081	\\x00800003b5fbe916ad839e5d1218063b396d901c0b3ea1db838c33a1c3ebd51fdda90d7dd8db1ba367d9f7f7bd1a9a739afaae722ae51be0f340dac0f3773637288ae2c2d2cf7b3490831685d60cf0c874451c9121c8d656a973fa402678eb930dd76a5de8992bc644d46cf8edaff37401b0a19c30ec57d0979e287ee9671aefd6eb6cf1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd1ba38a0bdffdd44918ecfab0514a0b5bbc5db45797eb01775463787c2cf8ef2da77728c11ddb50310d68c0556b685df2aebb215424d4281c0e9134b44021007	1631292714000000	1631897514000000	1694969514000000	1789577514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	278
\\x8676a2c1bae9a1d3fb2be6209a2888c0de9da07c4b2f193f3e8058480c439b4ea8598a1f91835b7069c9d6eee1ff6478700947b1a0434f64e5d5f8942dc4701e	\\x00800003e19feb58be6c8140f2c6f7ccfe0b2f57c894dd113aa96a9b5bf2e03d08165c813a347ef02119b6927bad7cd4a1cd08c0ed4758156daa15db067424bac44fc8982b1808f40007885142f6922e2c1549b280a5e65f1898187ae899417b2c61fb1f30df51e4062b3f00df84bb884cda84b9e2294fcfbc7eb5c6e95bf561be537b83010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5af3ee50c0f14c8080cf92ae913498dedf9d0a16e1d720d5959530361ecf53a6f1da3a84e3c96bbccc959f3eb2a06f4feede722c288143b855df0b1b4fccee06	1630083714000000	1630688514000000	1693760514000000	1788368514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	279
\\x8b968875273d4ca816131c694a6381ea3ab16d1b2fd76e99f8ed9ff5e472f74c0d5dc0ec1f32ed9a704d7973c6a179fc8dadb334394b0693a95c31e9fcb995ab	\\x00800003bce9941a7171207b3c783a65465c86bdfe8009c486e4a469ee7f2dc253a0c345e0b8d3e54ccb9c929e7da2faede94c19184e786fabffd24c06cfa285b74dab389cabe567249b05a486de4ab8edc5238b4ccd0552ea337f84beba4bb79f2e8dde24b92daaf6e8c956b0bc91904837778c7bc0f10046b6dec84d65b84e403b5c85010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc83d08045e50e1cc2e44e95c4884253be2b844ff0135350ff005dcef66465926d2170bd7ce2fef9f7153a4a8a65728c45839761382120f774e3a9719747c1109	1639755714000000	1640360514000000	1703432514000000	1798040514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	280
\\x8b0a7eca3422baaae94516b39ea5b2ccedf950ce17d7ff04c72a07034a135796b4895776390b7b3606c3ed195cb3ff6cbdc9b2e292e5952eeca09cdf5e7fbcea	\\x00800003baf4648b5d41b4a2c5de460b0a67f3237069c9b7e96e2bd7756c69c99ab6a80a11eccea3d61cfad2103d4d52fa0e6f0e14d61562f6ccb504e41a08bdd0aeea4919aa58a0789ec116a7a261344381be617625d84b64fd176b8dfcadd1df853747d344f78c2a0ce095c4b8f91a4ba1ada2d12b721e252c9bb8ea0d24b2d1455399010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcae5d59a72bee59b0b7feb0932386c05289b4d6adc690083b83079f6dcc264fcd357279828a842442a3bda027237d0b9ee3e5c547eb4a9480a59fbab476d710e	1626456714000000	1627061514000000	1690133514000000	1784741514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	281
\\x8e7e692b43559ad835183b42cfd1d7d7e03dbec4926c083b1ee0ebe291fc3a64383bd56e171566e7b19e455b52b7c17628990b78616b5c522d116af13b1fa996	\\x00800003f698283ecaafe39829ec361c4298b17e3031a0177e94f5232aca50614f2fdb6cabf29d1a7697b2e119930bd1f9a0115a2467d2ec98268c47ac7c07387391ccc876da2c0903bbe5d047aeca8ac5ae0c8087f563c0c0cc7cc21909c50ff2e5c7fa770a98d6fdecdb6f9df7c9b51e31ecb063f681a5ba22ea028ace25f27183fb2f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xaf06e552d6df9af687c0fad3cfe289bc66cab8b8c473260e2557c0ab1cdee324b16252ad460e0f1aa8fe6f7ea42dd64decf0b42b3b70499a96731e77834b5100	1619807214000000	1620412014000000	1683484014000000	1778092014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	282
\\x9dce8956f1e87c4e0d9f3faff54343a9d49ea274660c371760caa264bdf604f186d88a593ebbcff0d2873b02f53092f045152e63eeb0c1e85aa6dd83a17a3b10	\\x00800003b3a7549c73f0bbe92e1f36fc3c0bac80f0aab055ef2a50fdfea9a3d1921f3bb53ce2525d7aaa064e94bc8e63e508b4ed6b2c3229835d9875bf9cd312c285cd0054c35c39478d1ebf74a13432624862691fdd69edfc7511df7ad3d169a8639fb32f88e84113b88d287102c9be2c12b53f9ce16c685dd836bf85a49bed587ee029010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe84eac8bbf50e92843db66a7cbc514d70d197d402f7daa3c6a8af27e2a5ba9fd73e86edb126c56f2f4fe041011bc7e7d6493071ae813e775c34aa27258c65601	1624643214000000	1625248014000000	1688320014000000	1782928014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	283
\\xa22e5a2ebd2ed90318a446c59084cda2c8ff844e7214670a005261962a0ef58f568a3694fb16047c10b587c46e0b2113350f29dc5197f2a804d5b47c27a53d1d	\\x00800003d6e57186c8b60a6aad778aba63ef55be6352fe6dad3c702c955a75a87529bedacd4eb7a7806adbdca5960a854a37cba095e1416fb88487e3b20d4bb7817ec695beb9443442aa829ee39ad8434ba78d43fb4804e482bfd56b40f72449aeb80349344cc38d8e39fb56631dae3738676b2d365b216060060181fba8fbc8f5be58d9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb4a91750daf741befa7160b8804fb0552f6e2854bc10239b59b803508239083d1ebf2f7e5c239c711814794bcf0e09375f03aba7e1c669546de181c5e6c2fa05	1613762214000000	1614367014000000	1677439014000000	1772047014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	284
\\xa46a5ab65944ab97f9cb15cacd4d51005506df47513fa24135edd59b490331a851eef4fd212f98057cf239fc4efa55080ad1157875b9e993020b26cf584c4262	\\x00800003d6340757a853daf1edf92c1fd795e8e296729959c6aa5cc33c9ccdd110410ee4781a2c9b18dcd40b489f67120c7c8aa0429ead0f9a892a2788ce8992d0fd1c3231b6b1c6f742a57fcac99a10edd9608b2c0214f728a52dc40b587ccdcd1e59c6430a1512131261b10e81edba2dc504e3420b342fadbde8dc31a180aea81be86d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc70a7ff50b9e4cf1957d2950517e90bdf81d91065dfc40d37528cd78f4de5c76ac91027c257e86c9d8b78cb0dd2e54977e27ae5145f28479a816756be4cb400c	1624643214000000	1625248014000000	1688320014000000	1782928014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	285
\\xa682566c466ec2b4d87ceef9578bc05557fe3ea940647715ab4c3f3254021d8ca6c699bbab453e5c6b756cb88fb8e602805ee5fe7fa5c2dcd5882a0a5ee705d3	\\x00800003c130885d2180496e7deeff0875a62e2b98f6cf829451dce7890bca45f748ff283f65701daf5785b74333c7ca62a14c6d55b01851ecff792b25d327d4f6277ee723bc8e588ee6eca5a52e1d2a4795b4f3084020c8fd4c75fd68aff539c9fa7cbd845c80e8f37a09b8196e55ade57dd53e959a577b36e23ccabecbd07ad0db8c11010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9c6744b44481f0fe229817433a97dd306856e5e768dd9880e463a3f02f9c9b9f144cba1e6b6df5470b8767e914ea244cc625b6daa4fb5a963fa87ba2d17a300c	1613157714000000	1613762514000000	1676834514000000	1771442514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xa6feccd9a8b434a3f58982ba3ff46655354720587a7c00f14511b84627053c2d6ba830f962e3a0292d18836c0b7bf63f0554f5ecba84c02ba3567a677ffdbad6	\\x008000039c4acce59a700b2111308b6aeb5337ce960cc8950725d5618eb3eb024ac1fe9cec6d72a9133c60caa1f5022ef9cc73a87b43caa26589eec9c13bbb6fbc9c18496be876b49cacc50aba6e00ce51f60f360406dbb44c0780db421660bbabb4185941b4c3b7937db6b857dc8d4bd2ba5f36b9738dd47167a6684af3072f17045c3f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xef358fee8217bbb15c67554a7ad1e0ea7e344c4192780fe195e830224b15eaefb4d64ff0a975ef8ee9a692401a682a44858b066bb95e3555f88cb9cc4c8d5c03	1628874714000000	1629479514000000	1692551514000000	1787159514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	287
\\xa8fa5d0bd728d96b98f06c08771a10655c18b3624e1241fe34dc866fb1505b5dd022b166f768bdfb990c05fe4ce1f183fe12379929b489a063a48fa98c086f28	\\x00800003cdebb7656147d4944c6794b03eb85aafb57092f73b831110127e65cf8bc41a07907c5dac788fbcb739bf32ddb47aeabb8b647c7f6938583ebb1c7a2d32d20a4fb83627175ef01c83074b6e7b9fec0ee7c836cf0f0413a01b76d444888c9947768e6d95c52f3ae26d4371590720562c9238a1731d41cb18112e943b28053c4d61010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x54e0d30544676ee0a3c8bfd9e9aa41ab7685894bb929aa15dfd18da9273a1481aec2cb65cba3c02b3cf7204f28e34bf88971e3ee2bbf15b4be18a1ed776c9b0d	1615575714000000	1616180514000000	1679252514000000	1773860514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	288
\\xa906dec32875ff134c7026771a233561bfaa911537e5fcc0da669ae2f566d8dee77f4b96bf56e4ab5c5852887f06b5bdde0aed2873508b30521d1844fa60d600	\\x00800003e42c08175f0e44c9f82ecf3f054874f8a4918e1a18ef74bfef16d4eb10ca8f0b6625fc71c19cc941fe5106c947badd52435c5e5061b9dc076ab656e58618b2980837cff62d75022405c8425c768ec8431bb6be17dbdd28705ac96dd395f598793f040be8f43cf48120c5ee236f152f41a5ea5908c886cc479d9380353e5e2ac5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb63e1831208d0ed6e768e95566c51414c6d6df2b6d04aa19972b1d4d0c3616e6df3fd1157cf7f5929be1b9b9bc666f1dd3bee63890979b7e0a9d0a5e3dba880b	1628874714000000	1629479514000000	1692551514000000	1787159514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	289
\\xaa3a8d279e6a81e43217deefab3b1e246d06f9c8e02426b9871d1d97d8c713c9bc1f30a985462811dc43298746566c19f434920862987facdf96e5a5fcb96be2	\\x00800003e1bed6c3326e54fb388699139a973d9a866fc7e3d8bb0a1b60dc6ed45b4e89322ba4d83454448ecdb06d45c88e7850400a9315ecf7adda0f5718e6744352a3ea695f9f6d415c606cc89fc83bb4293a186a85acccb67f3108e24017809e02ce9c06ea757bcb2803c7dbc6eefdf6e1c3f3e19c00aaf60ba16ed5b9e9fa4ce361cd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0908b5c329e05aad48a1daa89602725e65a87252f07fbe8f05049094887e1db5e3a860bcfac07871349d60dc2bcfdc05e95cfcbc252af0be1601aed56d2fef0a	1610739714000000	1611344514000000	1674416514000000	1769024514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	290
\\xaa0e1b25f481e8d892e187e40bd44f21fd2a7abd40dd944790d276c88dcfac139f9969c88550054a9a003fdc4fd67ee75f9772632105c3174d1de035dda6adee	\\x00800003b347f26e53716bc2a3dee2c85cd4eb3abd022b2444627ce925a8324b75149b522d67d68ba8833cb79895117244f06a507c810cde1283be566a82ecc2827f7461f1598262cc8812cdfb62cf3f26f93ddcc04dd89e0af82f20be00fd8d06c826ebadff7cbb2b504b3d9a25cc996793bdc74411ab8e1c4d0a9e7dc455b67fe9dd03010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5c45d14135a2382cf169d9d8d50e54789574f8ce5d8566de5939df4e1805fddb6cf4f6a2c1b589692bb96740c00026f7d31586ada9322cb734c38eb5f34ffa0a	1633710714000000	1634315514000000	1697387514000000	1791995514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	291
\\xabb28fdd759b583a2e4ce22f2d89bdd855863b58203b884059ab809ae32f7cfa9c24b736f9a264c0f40fb782961175e2ce58eba1b309b431f5457f759d82f544	\\x00800003c9017340d06a1cf7b93911e093061446d4aaf712a5e3bd230d73a887c9c01c6444be1f02c3887a2f10e642c029429bd0f53a70fdb4bd1c8f76d27853bb89da8f3da7952bf7f260efe6c168b2856db65eb5357e6245dd75000f28bb72a0fb3dcab32b78f9636d0439a87463418997ac5a9f020cfb5de2a09e5a097cdf83b233bd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdf79e79c10334546b2047f784b33c01e3509292f6409c9ab072a1fd8cc7b94850670c2553265bc85a7d8a76026ddae40ab6d372c188fcb978cf1b9eeacb57d03	1610135214000000	1610740014000000	1673812014000000	1768420014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	292
\\xab72733671d3b1c6098456fb84761f0028636790ea19e232514132978829a42983182be2d62b246c41ad80c0c333dfb5faf42fed19fc5d908f007cd25adcc4f0	\\x00800003b55e97a700c1ebb0710c545cfa62e4cd2e54ec4f8d69a0de25f1beff57349af0ff1cc99f8b3c6d43369a39bea2dc3eb35d2ecfeef786ef2e98927059fc3ff4373f0540e94cfb1db2c58b197b104c194a08d7d80c58d2d3e6082cebec8659e22865af9b2b9069a089c8b016ad46b8bf1185169743a9a78aebde31d7dd130fda9f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8fcd06c7f879c16cb4fbd81215df4d93fbaddda596dc8f12d8abfeda2a713baa84b47b161e1d0c5f5fd263a430e05c382f575304977bf9787398992604b79b03	1627665714000000	1628270514000000	1691342514000000	1785950514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xafb2094ec128ea5518b19dd435b447f7c942406ea18534a5098b18facc4cf231f61abf33f8746fc1bb311f44892c1c8b55a1b34cdd27ba71e8d5828fc0c73174	\\x00800003af1e2d88f2693ba0ceef3b8e04df1c13770c305cbde0dc846079a691788091744ee378214a8ca0ec589f134880c75e6c8d20b3f612c49854406c15cc64b384d3b0c6defc851ec39f6c348065b56bbf8a84992b8aac96c94add453748b7e847b923d92ee11dcb960e8815e28c385cd7527d1ef6d1c3e196eff97db1cb2e392617010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x87da675181a959767593264f178bdeec12eac4876843a55f318c86c08a7717313ad55196cfe7a2ce6a9c41ebfff00ebf57450b3953accdef4efd2d2b622d5f0d	1614366714000000	1614971514000000	1678043514000000	1772651514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xb1eec31d7dfd837cc35b65380e389fde9a6605e6f4534b17ace4287a331d550efca3f01878b7831b4841a33127d0e459106d5a044fd65bda0121258a01e99a2b	\\x00800003cd8788c82b856efacca4ae2d7d0e6f5f0f88756da789fd2068e0b655ec9ae3e6630ec35bc9502afb2ae2ca8c600817bf632e69c5380a166b54817ce9669e4fc873b9c83b0930295f08b4d7ad786a18e262774be0a747d14f7b4344090c10c92776ec8678f310f810fe4a446c86f688c9892b554eba16bd7b5b1c9a73e8a8e849010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf1bc2956f5facd2d2e86720ac48481d4d55efeb3c9302e662b9a03c2424e4639bf90ed6aa2aa56c64c27166bc1a84f44173be262009ce6edd6dd938b95015803	1618598214000000	1619203014000000	1682275014000000	1776883014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	295
\\xb23e49387e93df506b5f807c343eb62ce2dc92b49ae050104a4a520143a128dde739c4a918bfb2fff947ec4561539ee78ea588eee69104c66dbb90280208900b	\\x00800003cd64aa18a12bb25c82ba1b6b251cbef6084d693f4962bb27b4778f1963b3f8fe2f1b47ac20c24d8fadb21b826c5b6bf19d462652686b6746dc0f33b4437a7ec563a8d4633af7e00dbf6596dde0135f5ec56eab73311ffdec0ddfb6ed186e83cb5f63ce5d3cb034eaf58355997536a39a02e55f310eba4f92aeb38535be36bced010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4a93d3c8ec0f6d15d1f98cb15ced4aee31fda496b085c5261db00783853af1b37688a6e16159d303d0b0ced5a3c3c443d0e4b204783595fce77fc6a21554790d	1637942214000000	1638547014000000	1701619014000000	1796227014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xb6224fbb1733dfd8192d4cded657549186b152d7259fb92183c733b9effa5302ef91ec071163efd3f9ce039b0d1c87be6022530f4f7187c9418429a5268b85d4	\\x00800003c0acd787087e7eb7377ca90fccf9fc28fc88e8d20e992c7ce314e97fab55e5e50d381c0c7b46b4e315d91c522ae802625c9fd49fce1f45c158b150114c6637a50d8b8e8f149d4a51b043de68bcf80409c945e5e3df25a872db0f6b9496d7864298970d41bc9e4571b9df7ff6508eefe9faa09911e80cfcf569747567701ad6dd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd419e8a6a4573cc8ea6a9534292ed0f9c0c09ec34267dd7e6dcac377bb8edc603c56f410ca30e0239a06fcced9561bb23103a947cba4a8195bb2abce3610b705	1631292714000000	1631897514000000	1694969514000000	1789577514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	297
\\xb60203bdeb8eb737e9c7def758d68f138094a323452d50fbfd093f1b3d442baceb379ca578c33a2775df2be7286d945609e68d9ac41c8284da8cf00191ab450f	\\x00800003c4eb0d7aafd1fa8bd04ad8c56deea7e41104614ea7a2b0a59473e2b919b5935d8025652a7b8fc08379d3b8bb9564dff911c5c4d09421e1b16abe58bdfc660740bfec1f2af0f32323c40f7a6ee5df702fc1e654dd82577c488c7194eac6fbe8f5b1547968d811f8a13919adf841e8571b1926aa9619b1a5f567662a3f03f6e80d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd3cc0c6c20a43793cb4408cf65e81f905c6025ac401140f43b4a841ec277069857a6fc34bfcc0eeeaeb1c01a7b40782f5da167dde07e8f7c8e023e977d90900c	1634315214000000	1634920014000000	1697992014000000	1792600014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	298
\\xb76eaaac89864c03c4739f5e4b4a4ccd98d970e1fb97929243b8da70ba86c22f65373f6e86ee3595b4fb98d0e2cba35d5abf6130af45d231b0bcc2a94879268e	\\x00800003a9f6bd41206a852745d5344b99ab5d21f0f12a5718b6971e47197534f56b567d6b4ec42cad0c300826c44fe4da15f2d8c38f6cc639f108742e0117db2ca345b0c339bdc0ebc2bad48298ab3d85e80a8d60a886efd5c70d96e0707e5bf527aa5075126e56a25b1cf44a1e097e8519cf368934d9e9eb4e0cc3098db985e07347e3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1bd150056d975deae7f2c84bc64192144c9d11b8960a8ea685249fc684e57ab98908bc71c4d4d4fc7edcf749ad117b67d938bebf96e2346b8868efcb3c728f0b	1614971214000000	1615576014000000	1678648014000000	1773256014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	299
\\xb8fa949af0eb67d72f566073b6b12f2ef33f871ededfdd7ae5b2f8344c6ef5b50bf66e4ebfc52d0aa02f87a10bb32769eb331ca81753dfde543d5733c5138de7	\\x00800003aa56eee8acc8e0e18183d751606901003860da847849d37c8db6f44cc8269ea3c873f0fe3ce0249691b9e61d195c316f2c1cc4102b8b8223ec98f229a91a1d15e394f29785a090afb8f68825cd06a8fb9780b35e6384698e26962442adf1b32a0ff130aba9e03e4f881f5e41c1cb01086171f77aa6e6bde5a0c208df193d7451010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7218314b5b5d2d5d1ca040c1af1179d99f0461a3dbc585ef9065b8d31d4bdea50b4070843acf2fe1b2e28368b953e4b51733d064f57e5d22c54b6917eadb8807	1633106214000000	1633711014000000	1696783014000000	1791391014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	300
\\xbc56d1bd92a64a8ab0402810e8967a43f629ea89ad3ea152f34911215d2a0ef78b0a3d3fd02e847a5f526821e529ed8c4f143da2d1a37b2e8b2768617f48c588	\\x00800003dcfae9c0127347f6c5275392848cc5e41fc262690a23560069b37847e496ccc2f7a8154dcff659599edb0271aaeec0f0fff10341fa4d2f5a4868d69c91069e86dc7c3f3375c13ed770de737e4277a8d2a83b81bc94db17459f63f13caff3d5a344f4322f926b82a7803012f8d051377c101bac8251df953bd75e2685eee7627f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7d5b98180d804de1c0f028455c37f8863e54e2f389deccbded89667f5cc9126583c6fbc8dcc83f77c269eef71bca5059e38744dc7e303e6fa5e35f230bcc4301	1617389214000000	1617994014000000	1681066014000000	1775674014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xbc668031656ff43d72d33d6e7c98fa7bcdb37801ded72fb0eff27272245bcbd8380fb4aaff43156dac74b4744e09e731df8f7febc155c244f8f5ef441f4e2569	\\x00800003c12df04fada375b8aee507f9f8b391b1be626d3b77f818083d2ff7dbbb7466221e739b21a2cb5d325d13283a5f629b1d398106756177e1f2fce3ab069fdb15f2f4fd367b410eb82a021c37b9c9520e3b50e786b96c1b66f5b9ca1f90a9f633bfcebde72a6c7416f17a4823f49b6c51b257abe005bee7cfb0e734a0715dd180b3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf1368d80908c7b4ff9df137a84d9af5288f40b52bc170c7fbe8890b502b27b1723a7634b5a222107203ae6154e25385002b1037b5fc222fabbb6d97fa84a1d02	1634315214000000	1634920014000000	1697992014000000	1792600014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	302
\\xc04eb6916484f5dfd7a8677bc82f29140692512789461cf1b3dd0d5d6947cd96e5bb2bbbefb2b1c1a75ab6203a75799713279bdf6867f460c2dc583faf1aa3c3	\\x00800003d6fd4b921da0dd16b040922b72050b9110b052fb4627a5b3bff2cfbd752153655cb2989373e6483db01578d4b36fbc84ab4ccffcc8157afdf82db1afb450115dff05e0356a2155d06ca9613f8cb1699bc24c45888c429ea12c4fa8e27707a2e4991cf3047b56b00f9c14adfcc3f49197335b21a75ed945ad5c0c9fd00f09ef7d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x00f9b201c72273762d6f36e1b986b3861e07c9e7e016e5d10d17af06ca3637079454894ee34fe2b2bd77cbae083b69e0777ccc56a6b006bb8b2adad766162302	1619807214000000	1620412014000000	1683484014000000	1778092014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	303
\\xc60ee1a67f74a04346c60c9fff9715dca3cf40f5c652f82631deb0d007601f2f05ffed78f90e258ba31484ac3a7e0875a9273768e7415f7b36568b87bb3851a6	\\x00800003c81117a23adb99d6ea2b0f52e5414adf545a61672e9345b549e89c72504ff0826054cb46ff4c75bbf846877b3e4b564628cdf2b64510fdc1d785aefb454b0e0266932fa24dd1ecd071592370a3e69b318c9641c84156bfff4fb984479a25cfdae9a27c2b2ee1b180341ab7bd4289c87de00558480e6498ab4707e04a9b0bd9cd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x567523ad508cbc6ee449c5d6389a8540e8412d3942cfb9b97439701572baff142fe8a226f853cd021c029188c246956ee7e2ed3920e85b66832d707e7c471a0a	1633710714000000	1634315514000000	1697387514000000	1791995514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xc726a6e43057fbba3210790f9c1169df89af7b57eb2fcce8477e63400e3170bb629aa56271dbbf2ccd7ebaa76226557977d924d5f982d2cea20f1d6e497f1410	\\x00800003b4818ddd85d296305d52f678d358b53c4a48e942e11bf9bd5de93d3b25f4c715dc1ff66aaaf40fef234754278761928caf5b7715845ccf8e1ad284e440e4779e869b3324a05adb854ab67592e08210517573ec0e58b89b7ee2182e74658148f6c6b3132489ffb04372c988fc8285bd9d6acab6777c066558333c67537271fd45010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x25a92218a14b6e6a73942d166d3be72a007bbc95ba9af9a0b2543d1ebc819ce2f578ba56660b881a115cfe98eda166d120e75a8a122ff8459e1a4a939c4f1a06	1625247714000000	1625852514000000	1688924514000000	1783532514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xd0d21947aed881edeaf480693d552960bab764a9852707e04ad660d8853110bbe1633c9df29a83ce6d47c45a11ef111bccb763f7664877a103abc4872c3ec99a	\\x00800003c18acf62025ee133a8ddb280b5635adca088b2422f703427e33669eef171a1a1870969fd903dcf10ecdf29511f31ba09f3078b817300f8b2970dd6f54f2835437bb45f1dd95dd5f01752d11c64bb145df59935571ac7fbee546edfa413c068510f08455f950e558a27bcd89eedb1a6531a158814cf134f320fc8644247fe7473010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdf5fe9f579d624e68e0f74eb742810ce253120760f72e4cfb8bb2bcde00a53c5396f48f742d430105779bb60e015e9f4a05d123102501f5374c70afcc58b3f07	1634919714000000	1635524514000000	1698596514000000	1793204514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	306
\\xd15a11bd6e4cb4159e2e22cde9991837aacbc21f085e4993dd82fff9a07c44e7555517e7e442ac0efd9039ff97aec2815e4ccbfbd101d3a9229b08f180c0490b	\\x00800003eb521e0c11c2ac00fb83c9a8a059577aec5459549f87cb33abbae1cb77a0fe77d62ac93577b5619c01c93cec7e736e41767bb068a395b8db38ce19f6b3730d5a36e16c5467140143a9806b9f2b3a0bc480c56cd401a1ddc1a9d86ca54c1f257cde0175b3cf01fb9e6c0eab0c2d77eb8e24e7cfbdaa06ba1904a6a1bee5ff1355010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x95e16f2bcd7c9b4c1ea07dc96efafd381351746ccd5a22b607b8f1c159ada5f9a72aa35132377e43164199b3d73c11b8f8123a51cbc88212ef4e7f8d090e3200	1631292714000000	1631897514000000	1694969514000000	1789577514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xda1e2fead6faf7a2af78e9302a287cd257c7fc9c50e7ad79ccc55fc391df7d5bd3a0a8f6349de1f9d960cc25567b4e38a53c65ff16580f89bd73ef852e6526b3	\\x00800003c4d32bda0d079a5f969bcbb165d97a1cb40faa9ce02e26f5c1e95097f2d879d13fa704cf6c8e76ed519f360c622b8b1e300cabb83f62f6f9fc6dffcfaaf93f268b3dc7b555d6b6ad63bbd05939dd25e3b13509e5e3f7276620a29e24b68822c17c81ae5a04f300ef1c1e572893624cc6816a6b50490480d1ac02c34042fc8d0d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3f727dab7f0f1121f9af4eb99d051cd16cbf93930a4bb388408c1474cb5aca4343e511fa68c627cd8b8217c4da4e716747727e0e2a2178df5e077f3fb68f730b	1637337714000000	1637942514000000	1701014514000000	1795622514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	308
\\xdc26f307f2c1603602ab9150054145b18cc9026a21cb0324a546da86178c962bb7703627418e3f2e94df64f9852f753d7b1c169d77b1e8feab6cbf37cc20bfb7	\\x00800003d93240f7bc5768e580fa4bf8dea1943067eff3c5151a5eb19f1018816f598d469059d2857c6fcff4accb74a12b7ab823e545447e52b158a4a36c032d66665e7e509408d607946b10e1f63024ec66b7eb5d0247ca22cc620656d94626ec98a825f7a9762900f92712323629c782f1c7efca9af678a1ae9156b10d46c9ff68f561010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb692dc92dc9d1ce8226124d3459b9ed65466e1f165ebbd90597566fa6e6f43c6163c1bc3c5a5501353b1d13b642848efea5c500b81457edc31c86f8d22238300	1636128714000000	1636733514000000	1699805514000000	1794413514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	309
\\xdffe168ccb69abae27e29d6601402a04837952815361e513f599d3df4255a9f78325a248662d20330bf071b89af57db9ee9da36fc7b2e908ca10c79e370049ca	\\x00800003d88b96c355091831820d38930ff61ca142dd668517baaa5c230a2fb326174d23411bd1b4a3b8c3d052ec77be21851357669fa6206d83aabe9a1ade480ab95b072bb48dc74ecbf3c91d1362e28eb6512227b0cbbedb1710c145ff412e5a3526ebe36da3cca453cc094177792cdc77ed217d33010481fea980272ae9f01e22f637010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa790367309c041d45793ffbb31ad418a014a165b6063074f39cbe12165a48661bf6afc7ef586954b3439d2fbe0b37c537b2263504a8ecaf3dcc796aacaae030f	1636733214000000	1637338014000000	1700410014000000	1795018014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	310
\\xe59e48a7a4c85996aed2e63be413c6d71764a742062a8886500babb056c378ff083b26a23ea7ebae846508c25325e68b7ec8f40248ff85c35b4158092a0a9335	\\x00800003ba3fa39882ed1e814e0c787ace3efcdd00de50b3585f8ca29f0c9c9de8a288e954bf17ee250f4d61fcd9f335f5745f4011f4294c53deeed15899e85a234b0f18852048ddc86be28ba6ecd08a83f1fdf3ff99be0c13daba1fa79c82c47e8b0a3e0e9e8324e878c19571390efc0a3e1cad9caae93d91bea4e4954c44a8d6e6b1b3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf4478f2a3e9e6f044b8d54ba248a381ea181eaef5c50d43e44fc3c563fb9af6e1678dfff99ecd6277c4e73487128e93afe88220c229bfc238d85e9920547bd05	1640360214000000	1640965014000000	1704037014000000	1798645014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	311
\\xec1a484143bff82b1d50cd53c2afd3fd151797735890ea9c2ff826c53b8359c57d59c1ee945108516a9e098ba0dcc4ac613763dc5b897355fb14acd982f7b21b	\\x00800003d1b972f70ea1d0394f841b2602e91adccce67432c1fbc80d43003d096e7983e49f810b5524952440dc11943482e4e9c62c79af963fabf6fed7aec0152b31033cbd48e11e961fa10d1a3ad3e5d12911185dede7cf2350667d1ea93cd1a373a876c31e496aee1d57c31526c0cf71e626097ec2a1a9767f13c875bea02db352d0b7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2c819ee78ffec970e29e79cc95401da8e2bc2805f71a1894e2dd02bfa329f5627a96ea670accf2b852ee8733387c861f699e7aed2a23ca89f5d64e33130be402	1616784714000000	1617389514000000	1680461514000000	1775069514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	312
\\xecda2c4eb886a00c6e41586b071a849883d7633933d15f1932118ae3f98b96427c74cf95e6c87af9a7263b493f1a121f0bc89bc88f0cfe7c1a8ed97f80a36ea8	\\x00800003d8186c207a7d3de00fa001eb29b0a68954979ef2902ba313dd72165eecc56a50cfc5be6d6848ed8661f22cb365dc4a24f23fe4b4d3d7b284fe4262640fffb7effee4f3251d2e663dade693de9cf57ff8c37d1f3d51c27b41b4dfb9fe8712b7b7e8bb9c727792836f7b077fc2ca58e07fa5fa1fe870aef78f1b0d2f933485d847010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdc7a21dd80824291f04e14c8fab09fd5f71fedcded90fdc8927c6fff6cd546c9dcb18e594ec2228e4c4a6ae1ebd60f69d3063c53cc61547d15dff9c5c2459a09	1638546714000000	1639151514000000	1702223514000000	1796831514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	313
\\xeff2e732fa9c2e43b95d82ed007460a4ccad8edca7e4d5b52ff27647dbcc8a59678f63bba2f9b007fdbfa23b4995d8dd7b9fa7d2650568c53d95499e6f954aa7	\\x00800003d8169c5e110fe1af8bc64ace2ffd396d962b931d6ed6ed6ad2cd57fab6e75ec203ec844846e83a49629d7909898f157b014d187cb299e4ddd96f0ef74e8af748a7fbf234cdd528081e4b9691a30d6664d8ec80ae1b2354580ae04dd0fa9d9c44ca4d3dd1892759695da7c254681fe053188c0283cfb70842ae711bc9a7bf4503010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x90cf4342e1662ad7f258d2f8a4fb0c6995c4c745104cc957084664b7ceeddc3371777f1989f5eefd7163f501d32196161e014b8e3d4b35a854cdac69d26d8202	1615575714000000	1616180514000000	1679252514000000	1773860514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	314
\\xf0dafe30f5593752ba7dcfc6026d547194fe5a562f767deb6e72aec5af28b16d5199affc11124d1bb61d62b96ed449e9a9c05e1559154342ebc828b950ed5676	\\x00800003d3911c2201416659cdfd6ad89e0d5c4494783f33cc0524d15ee8c05c19cc47e6454cb393eae0dd4c1e50580e4491bee875f10699e23136c5fba909899ed541fd0f818cd36ef96d784606fc10687b716ac65c1ebf477e52f8da780dc6612f0a412df4f1e4fbab9ebc1289f235c32d3c24c55ac9c00e2229508bae4d38e9d84c95010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3f7eb3c02f511e3d84d98bb76a506618b3e06ecf8671bd8c45cd74f8abc49641dcfbb3cc096d756e0c944e9aaf3cd1da186f4409f4373aee6edefcd13e5e5e04	1633710714000000	1634315514000000	1697387514000000	1791995514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	315
\\xf5ae241ecf7c6ff93347a8b18fd2f8a9f966b0d8ee278e3aa0ffbaf4252cfab4458ade9cedf606e52e989605911ab410fdb8ba21491993d65cc2c9776633d784	\\x00800003b8cd0345cb871b5b5fb1bd8b2ab01574c063445ce4019c2d258ed33ce35274a416190a3d40c0db83b66d6f0dbbd9ad7765073c8a850275ed10b23993d00908f14bb0046f20816f520e5ac768348ced01aeea343f490c8a4f431200cbc42aa779e9737023a670f5b7f1b0dcc41878237113507b1247787ca1a09e21b4c105417b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8773814ff8d80915d01f33cd492ca8007d201d527f91d504f556900ced97368ba2ee904944ee8e5d36c1064846ffc9904b9874d07343bde45a26339473df9300	1635524214000000	1636129014000000	1699201014000000	1793809014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	316
\\xf62639959f6eedcdaa1a6caaf650bd4588d4de3b64506a7f990562ad011043d2f81536a58c0aee828fe4d63bc0e36d86113f778afd10a0e4284fa8c5c55d19e5	\\x00800003bd1da58263bd877243463ff090be199236682f2ebe89899b9ae0d225e2d8a6d788dcb42151955ba28c5b7baec27895cdc70e4e0f92fbb55f2c9212a4e111d7c39e56352ef48223b1015dabc3a2e1454e4aa449db40221bf5f8b1fdf15b7df7f8f9dc5a98dd2b114ea84e4e21e6ef158a1d5ce7a516a4c219b7080c2ce34b6c15010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2d6beef7ae603951e0b773377b56f2dd9ceb5e332082085e2bc2c01cadd797b6a6615c11d4b8b7e11231d0a94c93d558a6702a0b90361c46e105b0849ef9fb0c	1623434214000000	1624039014000000	1687111014000000	1781719014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xf8aa33956851e33b2e3bcf1f85dbf0121adef545697c44dad9603fa9dcbc6abbf1ad5160c35fa91bb62293cf4996e2a7450e29ec0479471b93225763ca61bf9d	\\x00800003ec3b8db01fc97831382690654ccedf535ebe491e2caf083bfbcb0559f87bb299565f7e0b4b6d46bcca7505fe12868222937a046799ac92d9722a3985c086b3374d5e2672c65a8dc374165034069dd210f6cc404658155145657593420b731521627450beadd5bd33f6cf5a451a251ced20816ee42d66540149604123d6e7ec51010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb855b3c96d5b25e4cf8fa3a54c342166e23b9b2d3f6047cb180f328c32aae3fceb6e87526132c8377fdcd69b3b5b2bfca9d6e0ae2013b18cd71cde0a9d7f8b00	1629479214000000	1630084014000000	1693156014000000	1787764014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	318
\\xfc8a2ac1b3eb0200e2d550e4a6840b0375fd1aba5cef9d91d35efce25edd2536e8cccc5448aad7803c21935cface721db690e63bfe9037842afc9a09a5b8d563	\\x00800003bb4cc30312224b238b8137cec9f4a96b5b5ded878902ca49c185165a2c4823cc1689f8974a7571f93df3ccf731b40ae9da58a1580e3782a9ca90529d4235aa391b31c3b6842ebc3e95940e35298506ebf8b19c4fe678dae16ba33737087b6c049edf8228fc5085642acf568620e04ba9f513701aa9361e2d6ef0afa73b3b4253010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x501f62ebef91d232aec4ecaa45b313a3f0df8a6323fbe88138b9073f060e86ce02139a13b951e0e1526c81ec0b8cdb1de7010b2f3ad0a90cb9c49d68d6593801	1641569214000000	1642174014000000	1705246014000000	1799854014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\x015b64c0d3e9598364141dfa88f24caa575a5e8376ee0c16e8d9479bd1a52806d89acce8d782e9f45afe08dfce714d86cfc3e7fba10624e366a5179fe378e68c	\\x00800003cc7da062331c5d395a86b4125047d22abeaf8d3b2810a4bdd458824b8c3f20927b66ea0aeb4ac9cd4368d8d6a34b6931cb5a6f495fbe4f38d1f7fae3238ad60e770594500c8d0a15707ec4e66ddcd2d488bb207dda8c3b5edc515af228e7ef1f1702dffbe708480bc816eb4c7b9a50ce011df243620293892f6ac155bd3a08d3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4ff41601cc810e95876544752748bb3b2a1341a13cc72c68e5d32feddd83f5723dc03d9792cb8e7b55baacdafa8b52617184d777d95c4ebad177a11d4434fd0d	1629479214000000	1630084014000000	1693156014000000	1787764014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	320
\\x0953771b52db8cf88562822f581860930cfbb3533b8ee0b4a0df8649e140f8424d1532b3d8514883c470c8fa520e3cc44cb22ed656e7eec7ba55d0b89d5b0738	\\x00800003c22df7613fc8515490a53d6b7a28c22b59f638603d53de803b92abb2eb2c6e3a7068a9866d1893cae0bdb67fbeb06329f92bc53ba15432165ae1295aa9b78f31ad57c214ebe799eaacc90707ddc5d39483325dfe5a07852691f65af8ee76213a0303b7ac1444523fe8069bb0807318589f7ef535a95dec95055f13618518bee1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1fbe4cfb5ee31df6fad65e4c71f0ca0aff6ad66b4c89099f3cd302511fecba022a059c8e7a296075175f28d8859521a0947aeea2240d994d82943d5d13dae60f	1628270214000000	1628875014000000	1691947014000000	1786555014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	321
\\x0b2fe7ad5b5bb078b84c7b9364e472c2bde45950b2e9f7a67ea55e561a86d0659b6b468d25a06712ddd3f5ff82de90d110b27f629d31929603a168885d0176b7	\\x00800003a26d3e38e4ea195ad5b2496543733de95dc3693188966aa94c26cb0f1c533b6813b38eff1a5c08f8e47c79468c718b66eb1ffc243e562264d6110df2ba23e230f46d595da95065fd22338c1633f966ab57e1c4519ef94ba813b3cd74bd6e30ed98357e56d8bea9c4e23b992c8f711eeb2571a38c548a5969113941cf2fe12e63010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xecd0d20c4b35b1eb6b79b49ef1d739f750e13590fccba25f112a7787a57af49e3ee9daf813a731c05ffef2dd02481607ae17e3d0d076506c9ef4cdfa28a7c700	1624038714000000	1624643514000000	1687715514000000	1782323514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	322
\\x141b35a3ba50c5d84d8aa4f2ce7621dac6a8b18d59a3cb3da92df91bc1d5a08cb43866bb13c1d5571241b00c957f24d66ba29b3ae4c1b0e0d28c3e0bc370c6f8	\\x00800003bb98845ffd07da12903be4a24afea61470ce9428399ebc2123af3aa5f28a8994c49b7976e60407b03478b6f43806c02c73d3f08472e52657cc1f30393ccdad45028d551c86610c40dab48da61f23904eb5ec959ae570235c9f294f1fc94f5c0e44797867a701ef069ece3278ad32b5c2df32ce8650a2927138a1a9eec0832563010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd8efc901ad637113c9587b95da4050ba7c8a39850a7c59a8e8598a8d5125c689f92bb0c6ae11f3325202a4958d97a78bf45f1b75c45a72db9040162d7e299e06	1632501714000000	1633106514000000	1696178514000000	1790786514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	323
\\x165b1fb2275f248a4163beee109c663eaedc6b22104398edadd4f7c5a1d0e18f071e6000f1925a817ea888fdfc94fb09eb946493f83f46b5af4c88316158379c	\\x00800003c14690528a6c5a95d0dd144a737ab3cd7b19fc33bab8f1b2703b9d116d9b2fb89f3dc9111ec2f935568d2ae55dc4424c27fccb27af8c384aae9d058f24e68607f5fb62bdcf71ab2be58ef31b5c0b52f06708ee00bee7921478c0835fbb06c1f16174a90f238aa9a774430097847b110606c529fc9ac1baaf46ff1dd25d7d8f85010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0c835e25bb27046c333559fb6a7001b84b2d175b734daf01ff5e8f9c726951499c1b973d16b3ef64eae54990d78aec9479f52a71a821968e835365e5832fcc05	1625852214000000	1626457014000000	1689529014000000	1784137014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	324
\\x1b6f809effd2a3b15738540dbc166f1514938d43a525308892cda61da24795734a20f1309b75760ce2e7eb93dbb2cc0e8ae638c4f4a5f61e74a49bbd59733383	\\x00800003e148336e79ca3605bc9fe348f33574f40c074fe8453f86d51e47debca6b80cc3728457d06ffe872446dcaa369a1e96e0841c0956059d5cbec1323e11d447a8b7ef51a2974ff805460e7722e82d02aa250e9ea8963752fc4d9058bfdfdc31379295d1966ded4b56a94116e71d334dda37f027dbabf63a9b48a2f8cc51290e29e7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0754d12a3a30aa7b239cc652ee109b9a7b68c73164e3d7d26a68f4aec22487f2151d3ed0df4cca2cf1c8398686178401a6cbf8b45dc3a4b85cdef6483b03b20d	1619807214000000	1620412014000000	1683484014000000	1778092014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	325
\\x1cc787328b92faf96af3fdb4e67f7f4a9dc9a195e70a3344b2d08b4ee5def72fca2d3ebe4101985cbac3d3b087fe681af971cfe222f125722cc3841f6e9790ac	\\x00800003d940c55b043b76f9c80352ac2735dc1cc5f1152fefea64d5d32a6e6b67f690994f4e227c81d789b25cbb649bb82e1d8219923510c455b37c78ae3a9aad54bc512cfe39ba5b5e572e715e7486f8d037350101baa8040ccda4ded1bd5ab103fc647026a35a7c74ec0a4d5701b1e80a6feaca08b1b607d3f04c036a16a507e619ff010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x51bb1b43719a3ef4528f402a36da318620b22160ae61017a15165cf2c3181e3c094f467df4e52e7ddc312dbdfa3cef3bf31d52d8d80e97074d0027ae5bf34200	1637337714000000	1637942514000000	1701014514000000	1795622514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	326
\\x1cabcd453fd9fc224d1a894f35175294fdc2065339c754fb641c6bc24c386d7461c1d197b6862b4a3eb9b325e6f42e3beba21e366183e5e1d3466ea666e0427d	\\x00800003bc1eeffa6b56b62f89331545272063f9f2ca246106218d6e18ab563223d1123b75149b1110d731c1ce848c6b7a335454700f545892618b235a54967fb632bff74ce2264b6cc3bf94a038fd9328b5026c4a4aa6eab9a548c59184bdd42405d8d74bf13db3363c090695e7164cd06570d8e1599fc5f1fe9d4030a7be6e096b7a29010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe2b5879ebd91d6c0e1a6e35e2287870a1022e78afb4abdccfb628d4aead777a69213498ebaa4f4825955bbab9c8a98c0acfde07e84f412858652d77d8879270f	1628874714000000	1629479514000000	1692551514000000	1787159514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x1ec72a57e7c3db8b7edae622bbf6531885635d91a24d3e2cf95d2e2af152963bc54b50798bb8c0eeaffeb360bd0d0141cdafb512ff931c3a3c8fd79c89ca6a77	\\x00800003dcd1b3245759267808831ab6d26511ea11b70f89ef66dcb719d0beb041601fd88d5a79cc854773710c26a330e2733c3e680a394ce21f10dd08de621e946c5aa805c97f3003e6eb30c60cd372024060983e4067f1d40a28436d4e867f21b7e778f600675772a6d52ebed182d0d8e0a906a7a2e1b2446dfc7819e83e50b7ce8daf010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x31aa0df8f215783688d38f466c0a1a42262084ecd530643c735b7004673bb7336d098abcaf7e2c27f062cdb4715319537656f45bc1045678e9113e98e542b600	1634315214000000	1634920014000000	1697992014000000	1792600014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	328
\\x226f42608c32d5fe8f6bf910898e97bb2689e84516914a6ea923a567a54559af631f76bfb33e8699c3abd3943381889f760ce36f8c6902d0302edf798c996e1c	\\x00800003d8ad2024ede558c232b5e9db32c39d02621e8fd0516615cbcc30d2a5d09f320b72d925fe4ba22326a2eb3503dd99cfcc345565b5df17ce7706d333db16231079e42e6daaf0af4740fecd99f986d8225fdf2dd0ce277134ee6d3701895c857b2df8197501028ed581efc37c86c92bf3fe6bc6542ba189cba6319ea6412a8c7559010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5378922ba60260ddb28b649bd72927ec22af489cbe85d2510818fdf80824d5d5c92a2675f260e6d6fd77b55be57fbe1029970b9b15d548742f3a27b48373a900	1616180214000000	1616785014000000	1679857014000000	1774465014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x240f6da6a439040aa6c42da66eb824713e937e8e6a4df373e1050f803626198b2d469fd97aaebcd76fade9694a243eacacb1ce319dd6e196a3721c301aa21dff	\\x00800003caf0eac802220ee9ec009aa2e423468245339d03a79cfe943a5ecc92bd437f99a42e4f083980f750665f2229cd078182fdfa33a24ec705eff1cd363ea4428d17e3bb9071da26d4c7fd1aa1018999fb80b136dfa49ec7a84bed397055adce0c285cb217616c7d59b7bdfd2281b19f1e5f97163426cb4884cd6c7145b023df8711010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x6ea90efed32bd4e43992c5ae0ea0245167ac188a48d4499ac6e500c94054c681faf3f4ec4354217d4ff7dadb39c6f466aaea88b9c77c25e8ea365dc3d9128a0f	1621620714000000	1622225514000000	1685297514000000	1779905514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	330
\\x263b439040e8a4ea60ead81a480944a292664dd2a40b199cd36a4d31c14a3844217f76d24f9a915d1913fc58b780cd2b3ab001a19714876a6996873218234a15	\\x00800003cfd685750576c62c4e9720c4c23286db6e4e5bec89b6516f4770d5e1fed33e6488d07c01e7741076ddf134baf1bd406e76a5dce9da06f4eea83ac7afe95dd3218b9058a16dc457864e2ebe23af5e1274ee237589d7a14d032662701578926028bd988f0ecbd4df1dcbd4e97ff676d1a5a7e422d073beac4e7f26eb0b0422d073010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfe9971fb484c13af0db8f98fe0264814c5e2e2069ccf8dc42f2213fc731fdf868b71a557093a4fafc53820a0f2c9560d71022a24feb89c2c11187bd7261e0c06	1634919714000000	1635524514000000	1698596514000000	1793204514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	331
\\x2affc4dadfb9895d300da94a10237dccf1eb9ac9cf89ee9e57b8ea7cdc6f4878630150ae0f93cb63c49aae4de62c4d77f22eabe81db0d2c2ed9e1b015d23052f	\\x00800003be321ac7ffaa5537ea03c1db96e4b19b4c44a64241f23644d1992fa5958f92faee24bdc32bcfc01998c23f10b5d20d2e3cd3854be5f754f4e65e1e2fcb4de076a0d3b546d94cad1749da8000969808c79c66a6cf025903ef900976cc3230de2b70924c6f3018005534881ef9354b9756c40162f70215a132f510f1adfeaf6887010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb8ada85dee5d01646524a411ceaaa102500363c946d5877638710ab4d1c74187916e4a532bb44ee80b2c03d675d709c31b2eb2bb0c5dadb611800d7d7a6c590b	1619807214000000	1620412014000000	1683484014000000	1778092014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x2af3cc7f773725fb1635bc5f7d89381180cc8e48a70d5df4aaacf764ebb2cd1f9a8cc50525effe4377ed02307ac6703345b76364f05ba960cd1c518412e520e6	\\x00800003e65ae68455dd3b187727a853325372c24a89ff63484f2bbd96446bd122937571fda019e3c0ccf675f73e5adfe3c68a3c51a25a01074834183f1c648f9035ceed2278ee38115fa1075d96752a01fc75ffaa129ec0a8b8536a4cfd5a4e3791fd9b61644b898e7f6130953e926e8c10c3aca85884029205f25d07531d0633474d5b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd68895fca08a3b5d717772ddd68cb2bf11176e770c3ca2f97b3b1bd8a5616825975d99cebd61557c2e9d6c7654a403483c3c99aac9ff478555a9bba07d30330c	1615575714000000	1616180514000000	1679252514000000	1773860514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	333
\\x3177797c3381daf7e54ed243a4ebd16bc282dc1d513b896e5e0a0a7432dcf049eed5e55c588c8f1f2d0194e7c64f533384f9992678306e565c0d091e38a907df	\\x00800003c4ff8bb7e7be3388b2884eea4ca388e13228b7bd3bc7420266e6c0382bbd6b319eedaffcd1337855981dc73992e7e67189864f717f57ce97115fa2e806d83f2917e32ff8b8b31bde1897a8ba1e2aa7baaff53c9c4dc65c1adc0e71a22ba39a25e9b48026dff45da05dfbb3d10fb1a65e4b2fb2843275f800c0db677c47c38a55010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa0e6e9c89b9c7a7e0d34561037d709b466268541dae95b846ceadc2e9f65a7f715987ff4ae480a92287ce889bf4acef169d946555d0bd47178d8e299fae0bd05	1613762214000000	1614367014000000	1677439014000000	1772047014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x33db289f88ef7716deeb8a1ce401b47ee2c42371db75ff418f473687a046c8e78c1ac9dde61e41fac7ceee59392c7a2dbff41622c6baba2a6456162c92ecff51	\\x00800003becc9917f1d71abcaf8d74ed94f283418b1562e7a8c15de1c5e9786d09bc84383d7b0c6609bf3af1bd1dc79937181ef1fea38d06569d581885617e8bcff8b820f1a1a8df5362ccc199d9911f74a3d55d198c63b9fe1b2c9c1e0528a22b9ed8fd0914e2391b4a39a29f6f73772f905cafb84652225cba6c5f5a90dc4d5bc2c4b5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x62283886515b8121dae5c95a63723ab8f62f2205b6b77333ebbada47520ca68ee1fe744912f121d36f251d702e1610155f6bd4acc40a55e3ac530bc79cee7400	1635524214000000	1636129014000000	1699201014000000	1793809014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	335
\\x3b8b72cdb7b49b5481a3b77607427af0f419f7ac0537b2ff1cdbcd85ba73e39ec6f8463a5d65e291a85a99a30c574fca979eef4d5a7d59b7778a3746cac5234c	\\x00800003dd97980adb9ad3e084fb295621c15c5d2c0a178b99b04d3234c6796c045b93ed3efdd2444ffd529f9ea6a56ddffeb53fa3f323632c44de4beabbd2bdce28722ff13ed50c43688f7f7cfbfa6d6813cce76a69d02a411c0ea551cecc3066cfed3a13440e23ac2a98810e558e33fb87cd9a67073df522c2018ce0930267083351c7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x43092afa5ff882bdc81361861113b3a0f5ee9e390201833cd245676465ef97b48ca57f316aad35f50be83bd4919624c7613b2af6a5d1cf5d3cfccc9affa61001	1610135214000000	1610740014000000	1673812014000000	1768420014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	336
\\x3cd7cec9e1a182e7bb3400826c70ad0a6799479bd217055f06bc9514a9f71287909860cf11bb0a2827c43da9da5247ad2e959d62144656bb0587d2310482955f	\\x00800003aceadcbfcad519035e618e41604b558dd83d8d2f70259c7f1f372a476e7e50f0693fb6ecb80eccf505cf5c2ab200f58930d062a502a0c2c4bc41ce8dc43fb139e87004d6411e9a7247c058593b82b2d96b9dc39eef2ece75dad2f772ec2a999deca6698155f8e5b751f19c0a3fdce5cde3320f7397d78fc7a0d548fc8668017b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3e215bcecc5f84bcddc8ba5b3832b955e595ddfc10eb917d8a62ad43cdd21b796340453bc6e7e015246b0de5ae23d1a2aa80c80c6fc23cbf076c6158261bdd0c	1616180214000000	1616785014000000	1679857014000000	1774465014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x3de78abeb15aff78128c55278a9e476e10cfdb0cb4158f09a942f3ef1514974c9d1a047fd662c9e4fb8f6761b29d08e5951fcae076c0684d1db473baae0c52e8	\\x00800003caac79a92b29cf3290aeeea5a44c7a204bcea1cbc2eada7107dfefa9bc44c01835a496b915cdfd11e1a5fc2f5ec4c3d4fb526548ace8763650514a3fccd3456f8d1d1283fc4b30914e8463cb1bf444accc1a17647fc7f5d8613fb061a35bfb613e6917cb6f4b771cb48d10c463ca838e9575f1bbde073387e91d41995d8618a9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2aa03bd7cc48eeca1a5453c6a16361be80d8295f940032c345266f2a3e274499a7daa16cd5df4a38736995a1170d115ec02600855bd50fdb439200dcd24bef0f	1616784714000000	1617389514000000	1680461514000000	1775069514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	338
\\x41d7f9ed88e53f3ac80af3104780b71e887dd79753116b7591be75cb9797b371b293bddf66bc6460f331ad47c11e0eb89eb91e53dde7a8f89847f28e8be23ef4	\\x00800003ba355598c7b6198791a9a372bcb0b48f1328cd0c3f6ba7d7697abd454dfcc3557dba36f9ef265173794ce29968f092052391ad44b784df4997877b4d363e6c3ed87bde6ef3dcdccb39583c0228934c31cc2e77a64c815e0ec3f608e212801d9a1e75d11512ea4846caf577dafcfacfd013af22c8ef25e5d43c41860a9b574535010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd58fcceb627950d264962a65de0b68c85966ea105359ac47990606e98928642beb382b4344b8c6ce028466d69c982102c4612185b2d8399daa17e8a3555ae90e	1639755714000000	1640360514000000	1703432514000000	1798040514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	339
\\x429761bf446b7b9a23ddce68edb3e2c312dccec32286651209c21b1ed93a6edac1b89f70c224cdc091f1fcbd4e6b9a74d9438f0a7c7d9efa843618bb141a340b	\\x00800003e835fba72957ca3aa084b9ac80249b9d9005d84d61d1ebdc1d1460f63096c2266369b86e8d6fe378276bf4d5713ffc2c3bff507e0a920f926215a2891b96dff6fdc85003131a942918bf6b7b7c8809e63a465f29cd583356f59ec46be442cb941d05c3fce72894aeb7479efa80b972b5049016e402b026ad80ab2dffa254f6ed010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xdbe8187f514ab66ca0fecca776b17e5d023c7a7acfcff5e62a672774500e2f80b89d380269df36bdb6d9131f7422a47fa00738b5056c47c3e6b27e4fcdc0ff04	1627061214000000	1627666014000000	1690738014000000	1785346014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	340
\\x42a39dc3d6fb13264c860f3cb2805f174790d25fcad99e7ced00095fae36c09a75351fb0b11fe12edb1964092f6850eea42d6ce0b1e96df8eb030cccee41ba42	\\x00800003bfa18f19204d1918703bc8797571f426b76174beb651f0132079d14d3326e22bb14b5380e445bd8278bde4b8b8944a943861186f56774df1b503739e371354a4664e0864a2a12b208957e978ab4e662715c9384469290b40e6b17ecccd00ec97fead27056a8dce25ba595ead035f7f8d7ae4a63b71957d8ad4b7df3d58412931010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x55ff5b348230ec7217dc0105561f5b4da01cff1b85d6962d2bcdb28897b9dcfb644c54aa3e3465a02d4e283df40af70ae65b15df90b2bf6a4ac03ae373ddc007	1634919714000000	1635524514000000	1698596514000000	1793204514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	341
\\x435fabc75d31af689b87e4fd5f9fe72246cc02ef3ce49563b928d595a31e2d310818cd8d8556c009653593c4bcdd166dedad0e732f238f2cf3be782274a3abad	\\x00800003c85a59ed855bd4d7c92361ef70021599e6f156763bb7faae31304a11a7cdd80ca8eb105e8ca553d415f42e988363abdf15645d2543104226bfcc4c9cda8bf290e3361a946e8eb6775efc55ee1543fa8add5e06f38ed30005bade8a2e7fed78c3bd94c49f58c93c50d0038961e186f8368616fa95a2752b46b642f88bd87de29d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x637626e4346a8d1d3670ba272c744fb464fb385657476c3dc98a31a3690c484d91ba9a65562739a06b5bda2547f046230c7eab644472ccb6358daeaee0dd6503	1613157714000000	1613762514000000	1676834514000000	1771442514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x485f759d6ec220d41473a42d1f1cc8e0c0b883d34b56d83305d6ecba0600949c9b366835f7765e97edefb25681d637d6a5d9befa5d3dc058767143dbb25bd1ee	\\x00800003aacc6008d479aa10a9a71db232cd12052a0125134611103d0e9314cb53b1bb47188b997b97b6dd2b2e1dbf2a59c8b0c0c8e926187c3f4abcea39f2680b3ed01dbbcebff5f2d1dc2203ee6a630ba72351a40f20ed15977f3cfca3f408a26f7fc9e91478f3a70fe813e938c2b28f83026b32629678c031c13c15776fbe49e91ae7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9c1fa59ff1b7fed6bcd87550006b413301ede1ab6cd4bbefbced12ba91812046eee77cf32790c406a89e4f4ba0a2053ec5287cb8e5d55396a265bb68dca0630e	1639755714000000	1640360514000000	1703432514000000	1798040514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	343
\\x49531f1215553730e1d397c306cfb7ed1ad3263c57fd388a59742668a0ab5df68ce0ef705521f6807b238f940227bf9349481ac2fd9cbbd3a191f9d452cfca8f	\\x00800003b6c38c21ef5d380a8973fb16bf5598d16101fee66032085879c3d46a2c136df5ed10ceac5ca41fbe49f9ed1bf18fed3a9f7cf6f2924705e2a6ebc1e5ea788b8c09073d39b0d38248ab9df98505238c93db959312628dde834b1cc4b507158e66700b379d56c9661db788e76a46b879df5d21be66864d6d60a7399243ed528d0d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc93f00bc0c188a5ad2857afe80ee98023d3df177757a5c0e1c6c3283bb1fa095ad170a3d4c2be72330476b941d24f976ec7dd6fd43187b3a58dd58a90014db0c	1640964714000000	1641569514000000	1704641514000000	1799249514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x49e3613912daa326e96b818e9798c7fbc884645c47d3b583f1bdcfd194cbd91ca6e2d8a4f652f6a825089a2cfa99832a898b682c2775dc503b88212527f8a18f	\\x00800003a4100f0bc762db3d97025bdcfc671bc49695138d95fc8ec9c1d3d8d38c3b4c5877361a460a635599d2c3af44069f1ceec6e09e770625f27a40756af38efa4fc61149b4494237f2c164a736e92f54c99d86fe36641ef8d99dad0f6fbcaea964db33c45560f6d45ada1b8b3d3682cc60fa6d44e49cddef6657e3dcec9cb65c2141010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5cdd7e8c4b3ce1b3a0ecd0f5c7a2c583f177a0e415f60d95851a3e11a2ea3aa48684b80d2a7bc86fb7095019545f84e3bcb3420c16735ce24f33ef842e404508	1614366714000000	1614971514000000	1678043514000000	1772651514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	345
\\x49ef65f4c78f100c6a90504466b8e0aa9ff7a6d5f049178d489a4aac1928c126fa7448f0a902b0eab6ab7f18291204d9d239beec5d391ac5bed59665716c4fe3	\\x00800003b3c4cb1f79397b4ab236bd547b2864ccab2ee92a26547fd592e4de8043d91b3583646bd3ae1361b040a281f14801f4e6cb80887d26c3bc1d8da986e73ba2b6f8ae791e6452ca996c9433fbad249b3345e41aa2c378027e609bd77f6394aa21dd6cd74589278a08573941a35a91a006665332dbd5d5f50a1a36127fb256216d85010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb22f8057b5857fc65c1682593239d353cb0c71272fee91393fca942e2377cb06fbc8f3a601cf66741e19544ffaec3d496258ac14547c0e4c97bc6eaa9c54d40c	1624038714000000	1624643514000000	1687715514000000	1782323514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	346
\\x5377e116a78ef32eb0a5820926acd5156e011abe0c0d908e1605c8d7a02e8cca9eb338ddda91bbf1c38b8a4c06eaeebd3cf362e82c2088c2a21acbc4bf7d1dfb	\\x00800003f1993567a1621a672fbfc2ad5290f86b230ac246f94d9ef44c4689d247f653c2828e42a669fdb9b6f38910eb338e34df780a65b67f19f9fbe47815e5987954bd42dc94a6ab0624db0a3e2d3f351700308d4f6a90cf82c6dda4851e28358afe2077f5b8a6ecea3a3bd7666d12aa15c85f430a29b3375dae0888aef63612a0a321010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2829ff4f831a40bfd499d5020459248cb8e6d8c2df7194153a100948ae9eec1d39bb2b77bf9f21d6b47b5eb840cd07dcb906c72eaa1516e16f3877e80c56a30d	1631897214000000	1632502014000000	1695574014000000	1790182014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	347
\\x584b59ebe7e8efd26a98222bfd4aca9076f8cef46d074f145f4ad55c9369d446f6c23ac06bf596eb27dd67c02e2a22a14972f897bc9395289d05992c68966fb1	\\x00800003a6594b96fdc25b2b15470bf43d49f77490ed71b74aeacbb5bc7e7635e6df0b7d8d8df2b274d5b068ad609a25eb58ee19fbd95c2886f995e08df501d95c87c15d26a08897a37c1bba0dea70fe6b9abe09fa16ac5c490231a07bfefb017c82e7f18503d6d3ee7afbf17065c3eea5dc0fd8215ad3a3dcba60269128c112ebb031bb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x061ce4ca10f8ecd461a69b2a24b77dc17c86a758d8bf7a39afaf893fcc98626e43022ff29647b27f675a6d98e89bc4d2e55519c78f6746c37598cdd79e528f0a	1638546714000000	1639151514000000	1702223514000000	1796831514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x584bd2d1a111233c52517f82991f16cee95c123184606db704fda597353305fc1597241755d9e676f4ac8c6fa40f2a28643578bbd176c91af17d76816f5d2801	\\x00800003a0509a704d0f6d07b88ebdd702d7b056785cb1e9cf94fc25c5e169ec3eae7b65ea5ffb3494fb5811022f7693b2675bc3ea33e6781bc1357b6e4035a663d79b3863dfed5c53f81578ffdd62fa16a5264f968d7cf0fd72f36ec8403d16fb725685be0f05820334fd583e5ae91ed6c9d3f941747f94fb9bea5c12bf754e7c2d76bb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc4ec7fc9b268bf232a66a48b9bb236c3bb30d248c42a33df44d6f82bad19e3b5895a6e2e565ec312b1e723026650189c255ff49699958154bad77171e264200c	1624038714000000	1624643514000000	1687715514000000	1782323514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x590f0f05c3b82b4d7416238e4948a377a215b6c340e7bd10c5d8d803e10e52954bbd66b2af5131629f4fe888639c804e6002ad055d4900a42fc42305152939ff	\\x00800003d3f8b23cc652af573698f792800a2e66e3521855f9a7ca627a5947c6bea75d08f169e9a7fadbcdf742d8b2b12e1627fdef3df246d8b7ed6d07c4391f8aaf08fcb0190a6ad76d04a5b48df641dea4d2d5deb6366b56400233fb6d4d5250e9549e32157dd1ebe50ca1cb69db1379d009b15b68ee7fe1e3ac2b77cc586c3186ba5b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x1f26d3aeef5096a6e1a491ccc618417c319b1c4ce5ebaa8da4dfa6d5392bdcd339075ebe72962b5944b5a9d70ff73d2936823ed90a9c2e011e65e1d44785f20e	1640964714000000	1641569514000000	1704641514000000	1799249514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	350
\\x5d8f1031967f725a1d9bd750aecd9f27adeaf615f247357d8d6f5593493212314225ce30fd7aa2ae2c85e346f964f45e367168dff5bbed20fc59057907a802b6	\\x00800003c7d8de0203c86fe025d8caa307547abb4cf38a87cdb71ee79715a04e70bb31db39c14419ee951b1bc4be0d5739a226ff226e20ffcd1ec2bb3e556d63ec3136e4b8574d9c55990145846b6eb12d995eb571f50fda459e99afc96441dec77107698ca048f129af38c8528f443b770c1e61ee6ca29ae7c38da7eda3c64379ef0bcb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x327c3019322ead549a147e3ffaac83aea443b1b3f5e80ca9713806c4cc1e839bfdf706922d4ccd1038d21c72885e1898960d1f8d41e50e9394593bef5a012f0d	1629479214000000	1630084014000000	1693156014000000	1787764014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	351
\\x5e9bce861c2805f1e1fa64a12ec4e6d40f487a261f216d6813c77c76823a3e0867215a65e15ad0adaa393f6228a4c32aa417313ae074e39db06f1a401f71a945	\\x00800003d02d5aa94b6898c8534888e6ee223c0573d81f24291b20cc6d75dd44013618382c1d5fd5d5d1db9682c3c01113cfd38caee6506f657188df907274f08d9e1cf5ef6a2382bb110aff31d3e1b3215ac6b4be8c721835f7b295c666c0f231c7a10e0c374426674df6f64b21c3f00003481d7f1de5d68132a426f7809441a691e69f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd2f98bfdd8cc476118e361b552d0e6135954e9bfd90812d7ebf9dd13a4834efd52cc741f62fac2ac643a15207762264e3a9bfb26e21479576c702567941b6905	1638546714000000	1639151514000000	1702223514000000	1796831514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	352
\\x60f777468a207e3c2128473794f0549b221cb399865ffd227be66e38ccd1082bf181082ca37f7f31b4ca0381eb2e4117ce415f99e53064103a3c92494ce9a4ce	\\x00800003cf45e987b4d1914a8b93d897856aa319c5959c3e09ed8300de6d329ddfa8235eb975782665b6de3a17547a522e240b8d401850860e73eaf163c760c843a10531fe7c97094eb05a502588b4ef9f61dd322e67bd49c467ef26cf6145a1b7d4ce7849d6468c0f1bc5598cded70fd818bcaac6777772cd8e6e863a9301561f05ae75010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x88e7bf023ae023d36ee5c60861e6cf480eaec340e5852e7130c1cdd831dfdbb6985029990d4b2526da10568f1bafa3905f4225655784ca51cf4e3ac66b87f106	1610135214000000	1610740014000000	1673812014000000	1768420014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x6d478ed278c845ff09da5e01d22aa534e0adee308c9decc9bb3e1a044f89a7a69d24a7c18e4f3971859c79abad5ee9580e5893926ee39f707fa7a56bf505f7ec	\\x00800003a23b1020b2206d1e4cfc9977d0d0e141bda5b197a5caf33fd8870e0f92123490b730869172abe90f3406b6502ec38d40c4e78d14bc8419681294aceaef9ca7523857658f1eb7cd8d6a1c7fcbcd4d7196272c1dff5aaac6411d96091b05e6e7cd02d0773af71de60431ac93f573feb338c96aa1b2cd713f7f726c757b361662b9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3b4def124ad7128f64e1812b86fea7d7930145d4ff32229781ebd2dd1025778423faab53962ee6de9537cdbb3ef585206d5b771f4dd86920d9a1a46d4e855003	1614971214000000	1615576014000000	1678648014000000	1773256014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x6def6731391986fac5d2525f3673022b26e89d1709c9874bf7157aac070c3fe2fec735163d2d8433910b22a4110df11e1c01f3cab918d1b630bb963d469a13f2	\\x00800003a7dc54e3244d7f066c44e6eae559ccad8f1884ef3c75d292f2ac4f2f68e8b8f8112a8a05419e28967385bac743c19fd12b3d7c37ddd4df8d10027ddea108a164ddde18d4cd5b0bc1a2ec1dcaa7a26384426c35004a7fbb696467e3ecf320f65b7fab2b2ac2e9a62030164ff0600eadb756fc9a63dd387a91f34e2ab102b2a017010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3f1e18888ac16199425e1cb18263231aa1a03c1779272fb88c2d004101779c039c65b9da568883a559224172808ecf89d3c0daac0370d31e0a64ba014a01b404	1623434214000000	1624039014000000	1687111014000000	1781719014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	355
\\x6e4b398e9f09149c55da1b936f4dc8714b7fa5ae333f313ce487c52f70a2308d990c5b8ce288bab4f6c6c918e1a6a4d0b01727a1ac6808ac3f0cd73aca3e9d81	\\x00800003bf2fb8e157c3f3f5539541c12b5078a585c56440f6876d8272032fa85eb8a962fc30d87ed47df15d7c568b72b6d3d0f8848e56d5a5b59f29acfcb56d546c21a5db3eee16ca4a78985200862b58b8843632c2d17a7fee032cbc8ec2b13c4b9a75a406138e85a67f08359c37964a8690980274fc8c3b78349359212062db953175010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa1211f096df7cc23f04c10aeb2dba8277b9eb7f6324a0531e96a9f6477c269ec724007f57769b756d61101305c427c1a179fe930557d19b2dd1b1bf601cd7300	1626456714000000	1627061514000000	1690133514000000	1784741514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x6f9f5df43a58878f8f8963ed80b46ca8e62e45d603d61ea9e55bbf4acf51dbf1d770c56c8c9ec010c6c956d0e8f226ded67b0d25987738da5dcfd59efa9e9212	\\x00800003de5b8c78052183b092ce0626f297cfcaa58da91d003e5b96d762dd1af2d56f68d893064ca6a172b93fdd89c2cdcf8145397dc865b4f7282d8fc83bbe978dbccf73143e72dcc472847c540d91d96f7912daa11b12110022e3635f9cf77071005b0ad014c9e4be8bf424f0cf171169242f0fead1133cdcaf62ec3e1cebe03d43fb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfac4a937d93d99229c286b2652ea8d1b9ec44648853ddf75ee96dfed8f5f07986da4cd88678c5e8e268e57e586c7c4223053a2806b3fc42cfe6e5f5ceef02409	1611344214000000	1611949014000000	1675021014000000	1769629014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x754b2d9fdd59a158b101861f367213533c4ba0f894fb776ea4b0e948ab1e09cac6e18225033bf424be66dccf07ac410206803bbe21de94ccf8bcc535661719b6	\\x00800003a176a68acc24dd2b6f31956ed7896c60e22b1e3d24085e2ffb7d037a527c68191df7404842b2a62ab81e94fc89cc915bc975bff9f7a7436ca6e8f7cd27d44ba88caff21c383b1aa7a628e1748adfd0082289644a08be8c895e6dc56bfc09d55e8f21e92330332540e803e35d4a0cab8ef92afc42e017697343beb599e9b33b19010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd39cd730edb2d2e92e7e53d71efd24370b6f6748e2ee6120dddb44894a2b10ed6586b4168167969c728920bb0b71b1f0389329a31a6ea1c506267a779f08ee08	1613762214000000	1614367014000000	1677439014000000	1772047014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x75bf3c04b6bb4c229afb65e377bd0f076eb2ff34dd92bd2657bf677f8ab639625fb61e5716b9c96309a900eddf25dde3db8895cf7608cb9feccded04a6453727	\\x00800003c5b78f3cbd36c194daeed7d47118fa9fb0c2c9c45e68ae994e07eb9a09afc5b584c1715bfc156bf6288fa6048a7b937c967af8322bcfc7cc9ee4d70f41ad6b89f8f7399f2f98a195e52a77f60c6f4abcb67dac3383d98f23cbc30fff11c0512b83e245ace3c39b33346f07ace23719fe0ba82dbd163aae012bd59c99b7d2fc53010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe975ad2ba91ce15b9a70ce513b76b560f4afa96e8bf08d04adee53c369fd4192c609e3c646e5c1bdfd2e5dc438b96fd932746896e876973deb5d788888abda0d	1622829714000000	1623434514000000	1686506514000000	1781114514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	359
\\x7ae3a049744ed3fe7f5f447926c4b38320a4a40cf89e9fb4b195e943641152168ef14612e3c6870d8a50ce5d9cbc1d5e0658451d7c446653addb05ddeef029bc	\\x00800003c0e2e7b20313252e26c08ca04c365b340ba74935bbb5c736290015dd0bee15eb380822bb29e1e06f5e847b645af9132aeaddcf1a86a25c396e8e5133146d179e68bb4bbd309d2f8878bd916b53c75d5e4beb9c1c6c3e22a7ce07942ea265c2d30e917729b80319d6b59c284b9a745bcad92c4896bf29d7acf3e48797ef5dcb33010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe3aac9538cb25529ff4763292a5d47ddcfaa0e9a13dda880a7a60a65b36ae192890d4b7b28d60e529e336b71c2ae2e28e5a4f2e8e149733a4392a8b64a5d5401	1630083714000000	1630688514000000	1693760514000000	1788368514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x7b17b7a24e1ea9d834f0c7520090361a7b1c15bdbbc0391648c814bfad4a0df91522fabcf619aecb1c35cdd198c07af809e5c305fe47441d36abd93dd470c3a5	\\x00800003afc3ba2405bc94b349d32f03dc6ee4bb3a703d204cc4ccd812305a8fe603bee358334b6ad862cb272a223d3d6166dd0fbbabc5cf44867770bf5d1a74bdebfb3cb7a91ce4635f62e453713e00077735c977682297302f3769bd4734cf7983504e59b12aef1465a3514a3dd7b0973ec97d126a62834e370eaa51107fa580bcb7fb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0f48c42faba3742ac5fb7d04323777e2418aea0d9969e98bae5235d63e963f76f63ab1e1340b26e0b41935e4ebae5e6393623e8e75e5e543869aa2d266539a07	1622829714000000	1623434514000000	1686506514000000	1781114514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	361
\\x7d9f4526d7bc9e4b04cd87b9e5411fb2713130f365db3b06a9f75d386a3f599d38f380d557cbd1b48c18245fab1f733850ccc5afbcfe812ca7cdcbcf8d606abd	\\x00800003c11385ce73adb4d152f33a517a7222cb1e71621d90ce920f766f6ecd04b420f5904e546d3f76a53a6254469523a88a46d6cfa8a7c5b8006ac6189fe8f381143c213037a914f372b11b70e4bc9cb8757f7f6fe22851bd41b30fc9720ed98c5d1109ae16c8fee97df65878a1079fda7b9afc4ab0859da7f74732cea468baa1ca97010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3d35434b5c46c1af9513ae2c71dc6ae4ff7619346cc2c92261647887a3a773ba374daff38667452a54223d0044144b7780d7a6063b2c09404850b86f93e0370f	1619202714000000	1619807514000000	1682879514000000	1777487514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	362
\\x804fcf4280d732f88d4f735b19d26b8abad1fec93f27d125bb02630b0a5cbe64ccb29e64f0bd8a11c07b1e18b97d5d25f3ec7120e46ab7cdf0f11076bb8c749a	\\x00800003c9f4da78d27d54c20afd41438e95377eaa1a7406ef49655eb5bf1ba6a591501265ff4838bbe068cc4b916be8b1f3f6bb96f093e89836f2bfc7b54ce0598138e96bde7bff7751156f5d59cd6a11cd1396013c964c09da203e0a95e03fb2006a7cb279fac229005bd07f9bdcc7759d3ad13174f157221cc0c59b95ea6fe24c5a7b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4c2877adb327a751f24400c5eeb5c309b67a06f2146927b009215fc34afdd8ead4333612d1ef297e8505b34a4042e3d02a9aa32ddc18b64a6695b8803bfe1b05	1632501714000000	1633106514000000	1696178514000000	1790786514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x8367abccf01741653d701030004dd66406f4453321a715f0bd92e9895c7259a8ac327199c8176e7d6152102afe45d076552922e0a29179eec5e9c808e39848ee	\\x00800003a14b3e99d0f34543b0cf3eff0542d4eda11b68de7ab356c1ed01f4af9915c319f3552208f8d1b4a2288cea189726b34355babfc9c9b6bca56765f412ea8e931326a99f806d186d5f1d358fd6b520f86de09f7b1ca3fae73508686e1ade612572e7ee8caad303eb47a6e390977d9536c8cf404be243db830dea001701fbfea70b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x69d8c7c56d9edbc7a1ced21d2b7a06f00ae28c26fa71bf55a37bff384276da7cbdb8c770b1931d79054524874b998e832af9f93d29b8c6571362f9140976f003	1614366714000000	1614971514000000	1678043514000000	1772651514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	364
\\x8607d0f52664bd98b3ee353a6e62f9cc065bd05ce2bfda96db70993234d7e9249b4c76a9d9301f9c1e7911e53225fd3f9b33be616fa556f4d2eb8edcbfdcd6a1	\\x00800003deef74e1cdf3a72d8d0e1a3431c2de9a72dd667ab37840989077efcc7b762e4fc9d58765ae7565cf737a8693087770173fc6d996982a0df888185c5db7248d0949fccab8c3f0c74e9c38438b3ad7933de054e77b8795705a2267e5acba6fc51feb78cdcaba5abfb9da3df1362625f1fee062566716a56ac05b0410e554fda6ff010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc517f006887bd296ef74cbacfb7931224fef5e6868200a36c719061ccec1211103a33ab4c120d58407ed210fe7d82033429f7b2ec0e489062d44f5396a6baf0a	1611344214000000	1611949014000000	1675021014000000	1769629014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x88fbdf22824d84ccab244a4fe2c8709feefd43d1ab34c85bd21ab4ed56a2b04caede56d208c14e9853c2cad9c851b6ca052286b26b586aaa47afb3169f9df9ad	\\x008000039fe8ec0c82d04b8b10cf789e52b038f14da57cd35ed5e2c10b2b9fda2d8879e962bad097d90e3703becd83f8471dd034ad3d4e04209d06a02a41999bdf681b0b36307d184672a5bf8085cd55df489bbaef8179aa0d02a2e1a92303cc4510406e76bc8ae1b0938271ebe51b0d2af545c405d8385b48ebf418e8bacdfc5de5580f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb305417d17f3389636a4d8684b82347e9fcad130d91ef3e2115b6c27b288d77a9c151d5c24dbbe3b07cd4b07a6ca70bf17598292cf90d47da2595ef14d8bdf02	1630083714000000	1630688514000000	1693760514000000	1788368514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	366
\\x88e71cefcd6f918ea76e4a867fbbe9bf0fe0801bf3ffb409f5752306ea15c0afd97f7f6ddd24402fa2476680356058536295ab634115391ef1c1f5681ad4672e	\\x00800003c4b0483c32a80fda8b855ec7831f3871c82acb2d2eaa60fccf4abbffd90a5c5addd66af946f193e949a6d54ec2811412118392ad9531b81c260c88e25d394155f75bb7a903b6b8b6d876d1d87beba98d3f10b9ef1ee99b291982de33418cf8750572026b15b0940c85c9ca29121f28c703a08f5f8fe0ff5580e9131666dbf96f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x833204ce25db865b7247277d5e87bd0cbe44fcde706e7914ac0bf328a45f4f0ccff12ff5dbeb0c8e7139ae2067259e0744541d9323fda7deee606c2948703d0c	1620411714000000	1621016514000000	1684088514000000	1778696514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	367
\\x88bb8e9e72e6428d3130e9247218158ba94771229278115f1df4cf90f515b600b6e28f627d3b534159c1d414f2b43b8887aea631e2ccf5a358a862aca8cc8c96	\\x00800003e8865007fcce2fd3d14fbcbb2c31240a8e7bcc2811d6f951d2e188fa1e177070a83a8ddeb6442f328b65067419f3ce9dcc38445040efecf3bba2044544fd2c8ecf121906358a6f06e9b22697913ea52414486cc7d4009c4e4fe7e59c99272bf22b4e00fe6ae81221491af3be5a064f66194e6aa4a3c950d93f1fec614f410aa7010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x32fd4ddf0c7cebd7f4609e182554ba544e29a9e327d7aa6e8e8f2eb522ee820e4a3e091cf8c7e45ef1d856f60e5c185c31585966b1fff3f009a6c7a7cf41f206	1622829714000000	1623434514000000	1686506514000000	1781114514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	368
\\x891fbc47b861866460aed342e52b462a2b70a815c421dee966882cb08362ad9603377cc0e08f65de73f67ac48ee89f324b96c509619467708e7c3f38959735a2	\\x00800003edb4f39163ea0ef200a7f6d77238ababf82002e3a769e6e9229bd06148d524e04f6eea7a3e1f7a70c5a8fd61d59d112f653efe532eac91f96bc37ec401671e806acc7ee07044e43ebcd1b5b8f1b932b9398c4ed36edf7d0f7884355fb961f776eae344ed14f2ac51eaea991ba63dbd635591a31ff67ba778f8b684d7b118ac2f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd04a6627e45445fcfede085291f070874bf171030c9852fb0ee05b9e96a55c7343080d9e1ba03abefd87f13465a5ff4fbea9b89c4556e47233c3a74ab852c409	1639755714000000	1640360514000000	1703432514000000	1798040514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	369
\\x8a3ff0c44ad77dfbd0d2a051575a3af0e2a5714f8b8a7d9ab4e01c544764cdaa012f7caac0fcf8d42cacc178fbb791ef646e3c853d9643e2945bbd9aaac2e8e8	\\x00800003ce882fb3d8174f3645b3054da5909464a9c7e1fd66156efd843f0d8e92a3c8256a44d9b3c0948d5832915a90768eca4e0fdca4abfa0e34d6ac9fe964c215908eb6463e6c4ef67f9b0fc41b086d08b70d0fb1caf4b1d255fc393e110344a87c7284ebad0fc026c05c705f2c4c8184adcf1d60c765f83a36e0e3be861b0678fe45010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa004dad07796a3d198b7a6a9690d974d0068ff73fc61c9402fffb5fe2966766ef6d9381d3174cd5c75a9661845c7e357954ee033aebc1cde47318e51a1702801	1625852214000000	1626457014000000	1689529014000000	1784137014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	370
\\x8d6fef5e4aa24dacc9f5c7d75a91c0e2886bacbc8fd715232a70661dfc05ff78e5249b8801328b28597a910d5a7db2445234f0ed9850586c280c8b21e3650050	\\x00800003bf982a37b1eca67767b16ed5b8e93823ad4d0fbfdd8424a884dceafb2f2cab6410ea0838e7384ab5c837e96d22abbc0e8a1fdfd33e8d100ca475baeed67b7ef208f5ad0aa88a5aaeb6d4d69e2f2ff9f1499dafd27bd44b501ff2edb63f995009c422c084a743282b567b81dd86c1eae46ee9daf8ccb57ba624c61d47300c3c4b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfddeefba375c69c3230e6e376cf770dad25280560fe71dc0fecb1b5fe9ca1738d22d98d55112aa294efe4ca138e2065877808c9371f19f7db8943cd3615e930d	1625852214000000	1626457014000000	1689529014000000	1784137014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	371
\\x92535d7ed3dc0208a93cd65c474634f454e94f3932f4954ca6d7e8473884c73ae0e006869f04480009a3c9ae1a985b48d3bacd3731a792a51d0e9ffa2e75d2e2	\\x00800003be4661e44e5da9c0267238ad91f9aa1f4058c71fd5ae7dd283a33d4b7c53730759913748f89bfd6502f7125302190a1cdee88d2057267dbe23095b4b154ee6e96d92f875fa1d4d523e9d20653405298dd338a2f4092941ba7fab3bebf8a5c2cfa1f1564e37c48b3c4473a7fe4a826cf89179a0c8c78852ed87a77ce155ba3abf010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x181627218b67d3942d645c057286f8364738865c92c87f661cc48fe2c1f6605c0be935e335b0d570ff73e6b21c6aa14f7fddefb0d7246ef12b7f823a32eaae02	1641569214000000	1642174014000000	1705246014000000	1799854014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	372
\\x92f39d139c4ac350e4cf68788634c117fa91ce343c57e786ff53aca123e717f0001978d089e39d955ac03ec374162dbea464be779bb99c8233505bf11a0b2385	\\x00800003e66c5ea8628e2f86ff749cbf754e8a7a2e00e303c5620c905d93440446808061f383aee00d028bce132b018c95cee18ad51b7c34c00598593a1a525abd5e6353527c48f261f4442c45c359907161cfe118edbbae6d65ca6cccee650210f41153e684120e7b48d3ab65606c00159ca17df3ee6bf36e82bb759421f80dd623ad67010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9a9e3dbce69771380cec3e45eb9bf073cf0786f1353b4f7121fb30e1f3892ef273b4a01405f7d3eaf29e9aaa654d5332719ebf33bd216e8225978e9824561903	1618598214000000	1619203014000000	1682275014000000	1776883014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	373
\\x93e3fe71e602e38d9849bcea8aff24d580950e2054218fb4384c12ae11ec78b9982a15a78b2f680ee87685a74072ab0e613fbb79c33cb2d9d12bf5af0bcb7228	\\x00800003e3410e337fe411093f81c34b581f33ae3cb5fd79624dfe1c53cbe10a96cb070a1859735dbb3d85ee15f097ba00642ae5cef31a9f93f480e5f7ae1a8f9d684c9f24d6bad6b0cac10ad431ffefda5d935986ee81bffe6688ea122af91e42bb61e6ab867ab01cc75cb9f08bcb955cc97e8146d9af64a13ba0203a2e70b0f52f17ad010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x94d7705446e338f2d0a5c240a10776ba51bac5f082095be82e14d511865bf3ce70e0fb540316e4020999b68a8e4a6259aba64bb0e0a2631b4b3b88a8a1177405	1636733214000000	1637338014000000	1700410014000000	1795018014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x931b3dcb990834cbace437ad80468d568ee13f3b738715e39c5725cfa8b4dc5cb52b62ade348d74f8c73287c089b6c9ca8ef1667ff635f4628b0ea669ba68c84	\\x00800003b938a31654e8eb4a4fb0202b0245b136ea6f9cbb50a04e6b6446ebe7ed92904a939ea688c3f0fcafc567ef7af850c9df6ec8dba607ea68cfbd9cbdd665d961b8ca003566ccb38bd7d8e0aa34057857599e5387f30f1f1ed047ded8765b09012d22034c2f680f21089d7d539aefab4134e8f89136b1776d0cb60df3eb81cc2b99010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xc700936601228cefb72ebdcd78bd1ae42fdc0f64e69d8dfc6cb323559c4aeec37ac39465f5bc47825ab546b6514687f9f1ee9aab0cca5cf818df069f08854304	1617993714000000	1618598514000000	1681670514000000	1776278514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	375
\\x9417e9649b14679443776fb2a183281b79e4f34e1a0311bd3307e9fb5a2066f050cdc5e5030dea675b0f18ecac013025cf10ef186226f688194fbad04cb14251	\\x00800003c62e0fd1c0b335a3e84ab93cc9e269a5dd0380eb1cbd07a12c61986a309ea04d8ecaa919bebb844d3644b05b13390ae3ab0deecb15cf58fc174ad8b65341a1bdde6d9c2920227f4daadc0c420019a6b598a990b91971944cd1f40a13393c85fd778675de5bbf308a87a9dd3f0953301945e16a9e94ce16964bb89f17dd1ff8c9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x57771028418f9633d266f74ed2e6e66f256602d7c90afef11d3b6a583cbd737ec656bfd210f87fe4650857820bfb7034485aa784692430b87d571321deda0c02	1627061214000000	1627666014000000	1690738014000000	1785346014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	376
\\x98f7536faadb09e7653721872464697ecf88a68e1e116c9eac781b5b952dd5d7ace9068388967974782d8713b7bfb9b2bd3f02a8d75296d232dab947bfa3a71d	\\x00800003bdbbb78afaa5d552465ff2a9a8e6509ff2d19a5441ca7413505f2d4a016d34842e58aa94e490eaab69e000426ab3bb43e8723b2b2784880f4af6d08755833aed19d5695e3e9f63b6111e96d46f6671b00d64ca6751771ece0a789314e2bc8cdf5182c2bf6e26e1424dbee0b5679a3a21cb7d53c5a6e76a7913cf62c59cfdd789010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0c48d8bab8e62c03eb502630f2ff92467c1f1b8dba3a627e265eaef1f3b1b973d9582957755b731fec56e5711296c4785ef0b8e551e1b4c1d4f20d7b4c161f03	1637942214000000	1638547014000000	1701619014000000	1796227014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	377
\\x98df37cc1d1ea284051d9a79cf78139fb5b05ad67732c19433fe8a619d6b5608196e8abed2203efd0ad6c076e82a14a6470cb658352abd95039c30d1da36b469	\\x00800003d612e573ca54c75199ac9148dd71d4a8e20483218faaa62e84ceb050028aca0c3772f568c2b76e2fdf9f6081316186f32328035cc59c45e23ca3705cbe384457c7b2062b0cbd0347e0f76a82060a507e2e6de4e55af38116453e1c4b90292cfe2b1aa0aa0ef234705722c8a2385e942907bda5724eb7d9e023d15a4e1b628cb5010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xaba3399750481a58c81e07a47641c0524f713cc1dc8e35a65c2e166c3cac6aba99e85909bf4bda635d7cc602c410b9c35d209949b0cf95da362e3bcc5916a905	1630688214000000	1631293014000000	1694365014000000	1788973014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	378
\\x99234c88bd956d498b4004f3f799df06b2805ea3430028cf936b3fa1dd92ce3842c4ea0de520545a86dc0f5dc473e347b426e4c08440413c79bd127be020d494	\\x00800003d2aeb48f6d0840a7f9211300ecfc70b0df3177bc85f18a6c528976b5db6d215920c0e7890922c3ef2710feb20b58cbb17e929a7ae022681400efd3a50406358993e03789b7ff066a6b112a7273e899d1af4b86e04f97225effd8d9b5cf125167e489ccf83a89a99a89687f2ea6751d723d7e3f72aa3a47916f6a71ad833737bb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x23cf4f2a8e32375ed8e08052fca93ecb6303130899fb3c26ce1b833494ec52bb4e6b8d049b06ed1d7a3cbbd2a5b4d293236799be83add3a74c0446aed7a53a0a	1630688214000000	1631293014000000	1694365014000000	1788973014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x9bc76dd101299187be0ed9898a04fe31b70a0df48552c761436ee2a4569301fbe7b195a19618db2fd1cc5ecd2e45b4fd52b740324a1565bb82c0c484cae4a98b	\\x00800003b935f0c11bcee1c9307957c9bacb98bd1f83b0aa143057eb0da035792c72ff7a71511b28715641ad547bbe74fca4be8281e936d35b4ad9eaeeb80345ae962c58320a6c16920d46d725b5904b76f7b7824f4896bf58d3fb6367786c576f91934066bc581e57fa0a6b6d09a457694f4efe5df859ada25ec71ae63165bca601a027010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x7eb4b38f5634170489f3c5c5b8763fed17a7a73c80596f5d0836a2c63caaad30e4e4a5499ddb1ea27c21630c4f72d338530dba5738fc62def06810ff29a5c804	1621016214000000	1621621014000000	1684693014000000	1779301014000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x9b0bd17d3fc55c06bcadf4b8ac8ac4c152ae372cfedd81a14fd6c979b67e96ebc89cae4899fee7d6534b4bf041e08de1880a74452bc80b9949d45942258fad74	\\x00800003cf7c25e2a201f5a909707bc0ffd87f38fb5419fa19031f7a9346e88155dda9b82ad8ccb042091d6c33f68b92abbc25eb1590b7b1635e867ace5b7e0c7c4d300b826ecca32b068ab027d32ec0d2f2d48cb02a800e7dc86be65ad98f65964fa036dae9126cccfca96a54f307b330624ed38cf7b41ac0f0172586d2860b41741881010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0fde9f6698a0c9f9371db78546fc83b7bb53ceed41e87817008a97f72510b1ac133d08c3cec0c0647cdad3ec32f2c8b7c3b1ddca28640df2fca1d3b5fdb38508	1616784714000000	1617389514000000	1680461514000000	1775069514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	381
\\x9dab1dcce7bd092a9117510df81864dd723d0174fcff6ff2296b0fd4f37bd4f08c46891480aa0b88bbff66ab713b086c07b5eade97637b8b04031f3b4fd11e7c	\\x00800003d33bc43d08e4997379e2c5d55f849253b8bcd606c0fd78aa0dea08b8b442b23bd2dbb5938b94981c3fd13af1ad6f5da7c3cf75a8837aa1c002e8b42fe7e731d5273507b3fe3d14cec11637a8bb7e3ea51f4bc9014ceb3a6c28b1f35e131f373ff27b45052db6cc17deadd88f6d1477f21d7af01cd52f64055278307a9a3bf26b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x84d84413c77bdea30740a46800cb2e3dd83d73a156cb000c721a0d38db7b7a2ce86558cf660752aa4aa8065e992c9c953bce187d739d876b42e32a110556110c	1621016214000000	1621621014000000	1684693014000000	1779301014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	382
\\xa1c3a4132d2d84ee3237b77654e0e3386bf58c2133f620b026912dfcf1ae7de4cb53ceb7b992d1cb786463ee8544eccc90a4d4851f94a46a45e0f6ecf9c09f0f	\\x00800003d6ff966d376e57b8ffe50fa1594d2d2cf56ebfc53c57a9bfb573c38cac69969ec958efb2a5611430abc1ef9af2ece1428e58418d642491854e21c7560ce02d0475925d12615f402a807f93c4eeea823de5a89e2f23620054fb5d3087fa93c4b6a77d3761cf4ab45e240a58366dcae304402f3eb19b0f8f09509e95a1ac3cdb91010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa714457ff470a19c3f6c058e774b429f49baa30a213e1b99fdb7cc780545a4585d5538f7269f01728e9242b0c2d25ca52938f22c6cd828bcae8d068855e8a309	1613762214000000	1614367014000000	1677439014000000	1772047014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	383
\\xa3ff7e561d41dfc01c55c6b248c2fab5c538ac0175fe2c1021f2a01ec46e2678f226a7688709e4285e505aef4cd44b75e5ffc671517694e7e95f4721df34330f	\\x00800003e610bba6946c532361182c6eb6d54f91e2a036296e9cf93cdac4114f00165373b56580de2c387db4613702ec7953d0b58802816b7ab081779ab924c47b4224e0bf2d36715ea21195cec2c08621c695384b9de308a025034aad81eeae94312de22387fbe12937c9596f678672629109bc20da43e28b99897fe65795c71cfb810f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x82f83eb5bd33ee1f85a7c1bbb440074c97a879171d6c390268f7259c8503940cb571ae271f19ca4d0333a2ab30d20f7e33f53c76f26df35f063a2a063c15d70d	1617389214000000	1617994014000000	1681066014000000	1775674014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\xa9a334a371363c0c4c28670d0303375719c754a36158bbeb2d6625023a4d9a0070ef3a94956f6d8587b49a59aa939966c9367aaedcc299b23aedee1abcdc6176	\\x00800003db2462eabec1c4b5114996d329e0366a838c9a858ef957961d92170fa5ae9a6ec01374a7a9036648271bed7c823363e6c75be627cd5c4cee505419e790550e682a1eddf2124ce4a01cca71adbd9b56a3997820736459c87490c06b79fed4f21403983f874aa01ffb2b61c849e017c1857cf75e131ef5a8f39c00d6178c25b685010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd820271ccc2342104ff958ffe2ff62eff4fd22ae36714fd6d47eb23390f3f348810e73c6ad4e58f16fa5ccdd6519ae76cc6cdcf4ddab0d845ce5795cdd8cdb0d	1611344214000000	1611949014000000	1675021014000000	1769629014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	385
\\xabdf8fedcde322f3af8081e5d0ba969af8aeff62e20e2e30e1ffe5f7ea3877a5ebb6f127fc46569643f1a3946c54eaa73cc6b3c283f1b588cda690d1cf8aec51	\\x00800003bbd292b43ed213f1cace6f546668a25295199dc47410ae61ee5a199da7896735b5b27b826d63d510fdea5cdab310e82a49502cf4705d159839ad4b59ae435df1704fcab9aa0663d4117695786453c49817e7bfd2d6576593f14980533834066de3d4f2c7fb229dceac27ac824798705e10f88e017735423d5ec97d22a0a08745010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x75b75e09755cf19847d8c49d8657a31e15cc3a9fb64a041109906a6c2db0ca6c33c6a195fbd2c41dd8d6b659cfcb3bc4f66c86cd5ec40fa05a89fa9ab4d7940a	1611344214000000	1611949014000000	1675021014000000	1769629014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	386
\\xadbb4880de57be2ba8b233f5ad81fd78ea87d9a3833bc360268030d5b1782141a2f736ffd5dde6ef9c874ced6a8843ed99fcb60f9d1b831d7b9fd49e4e146af8	\\x00800003c896a46ab915d5ff0d55bf2a246c8bdb4a9b920af39227226a648c161c13e649cbf87827a3846b25a6dffecb5f9becd4cab7d2ea404d3d9687b7af55c39e9394b61b99630986e0f8f53e592ffe6d76b4605b90c425aacd7de605e4186d62404d9db9825d0888f9e90da4699fce22e298055786250b9c3ebdded1b5d49551a587010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xda9f4a91edea54906ada69f2b34884a53badecf6f44ae3f0f17cc3a74881d1f8afccafa6b3337ae205f54c8bfc561fbce51b5185deb7ba79fe965e28e75c3402	1637337714000000	1637942514000000	1701014514000000	1795622514000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	387
\\xb28f716417e8afa09d89d9d6afa6f8cad9660c81819f7fb1161a2df2f7c689f12901f17e370666d6d95b750eadc62332ad10a4fab9b3a62959db49972aed69dd	\\x00800003e4971bac855cc2e074e71392866f5eab9fe703b287ad1a33d2baae101be5309e99434340b9e3166687b4583529aed9f09bb0e17b9f8f97cef061de4a22d7efded013b89dcd54dffa7ed68b16574cc00a1188012cb171c8ea1a75c36800a1fcfbd049c6d0af0dc6da0b568c13580651efdc479ed1d9080efa4d632a651deaf407010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x54ce9b35adb0f45dc39b49d76156508fabc125c8e99505e81121ce571d98e942e12e7cba78af0e479f72c3437e88a4318e530bd6e9b15a7cf5f2672562131d06	1627061214000000	1627666014000000	1690738014000000	1785346014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	388
\\xb22b2110ff09e82dad451f9533cc3c7a7033c1ae5dfbcf0807d5010180e8145fd89d339317ae22311e0263428bf1d2e33a3e8df7c27fb0140dbd5142b58ec9b4	\\x00800003cd7ddf527c840c52f2b627c8d749b891f4654a9fa7af2a3d78ea09ff99b38331ec1560bb8be18221ccbc13ba9334a65cd7da1532b74a4927854f6fc519f124e9f96cac364d685ba6e5229e381ae48b3d6425d64e5a7ef26eec77749c585dcabbdf6abfc916f8c9950f70da1db6f5fdba95ce36f59296ad9dc7e4ea04ae74ba1b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9a7b57498597aba99c453468d6e07dc350d7726fc427e3c13cd54587ff261e72576242ffb4f3fe60ab2475d815c1e2bfbe5858de654ff695573eba19f6ad9405	1628874714000000	1629479514000000	1692551514000000	1787159514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	389
\\xb2175a42eb04acb9fbc673006ccfea4d22760988e0123c1bc7a7c5d1bbc8a2175ba5d6e6b6c7cbf0ea50329acb9170458056267d1ad217da88a05bba00b1cd2a	\\x00800003c4f32f6ea8649ba27ff474d0a532f150c9432d7d15fa3ad1ff706eb13dc7b354b2b01f9623de6141bf097bd72eec5f137ec36d56ddce8e959c8567b16bc183af0ae4b1a26cc4a18cf912acd74634012eb4d384d3636ee2020cdfd71a7edd45a4082ff5c6cce8da5aaed66a2d5d02d9bc506fd72ab8ee9f99e6ecc393c6591cab010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe4151ceacacbf6a4793839201e214e2d22adea8b3ddf335ebaa2db2e4a313c6403de4d48d9b0d25a3768b27e73a3db895c2c9202d7ef7ce69d294e16b6764b0d	1640964714000000	1641569514000000	1704641514000000	1799249514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	390
\\xb55759af07f349c73c3a210d686ea9c80a8d80ca55f6e6215ec7d52646134984c1390e979383b59d41d368b39aea2a5bf6f851d453c30a63f59d63e8ad1c253f	\\x00800003ddaff124ed333837c1f5bae83a93bf8096f5e5b7aacf96ff305ca8c0e77d1a15a293644140731b5d4b6edbb554f301612b2113fe87d6b51658fa77cb1df0fc687828627bc0b363f7846b9274736b81ade39af6fe19af4348907440a21bb606bca32ccf85cfa6e897169107d04e098c6e28e357d67bb582437d687eaec68918af010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa6502872d8f55f793defcd19b6e43a89bd347d3fc619e36b411f97c3759d17f826bfe9a01f8cec0c39dec5c53b6c247ba93c3f7d06dad1887dbb0f5ae16e8306	1627061214000000	1627666014000000	1690738014000000	1785346014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	391
\\xb6a7c21d1ffd62b2f0946d06231cfc312eb549da06d173b4dce8e280671f8b77c6f2268f6c9348db7ca500e57c8038117bd465224ad1c1b628fb09d84e27dc04	\\x00800003d628e3f38602c54f18cebba9c9d71453fb1b50245434bf5edb46c004c4f9ab25828c2a0993c0453e6bbcb96acfdb5cb574b2f2819cd30f5df643be6af32601e4cbd0b82ee44f80d0bc309ea72895934b9695824e0f12732989904c509c88b39ec8c31bebcfcf2abde36b51316a7e0ce08f86de82a4b9761d203b40d112c6eabb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9efa0a0e2ed7381706c30bd2997a953cda014d2fa865f80d4150aa0f6ce37d5c2f7c7a4c4156000c2a6466efde5afb514b5f110f3373afa24afd50c693c4d105	1612553214000000	1613158014000000	1676230014000000	1770838014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	392
\\xb947008be683abe240684004b659ed7e646ae00233f98c8063218fffdc4f5f29d74cd311ec7c5d76575866ffbe47b112aec071df5453ffa22e8a1b4639cf5bf6	\\x00800003c108b79cbb3fd183aa5354c120d616a5d94eb3ac38dfccbdbfd69fea0bc6bb0197d9d43f8f8b69aa4291a004273c758e1b1829685703237bc8e65b9d4185a1470f07f6e2af6cfe951333a164f87524a942294a292d2b06dad7ba5e63f2560300129f1b42a53431ed3b95853c7be12daeed0fc2c8a6521631e2c8fb85fe230d2f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xaaecda2cd2a939cd0e51cb5151242f8ba9d88225ffb5b1c7cedd6a332751568d462ce6e12c476028145d95cedfae25bab7d349020f58700acbae88aed4a00e0d	1623434214000000	1624039014000000	1687111014000000	1781719014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	393
\\xb95f573224d3954354c7813d8ab1cb8a5c67df3bf87628039251005fe428684f808bcc6aef3e81c815d5483a5b0e29f7191382e31f9c0da7bab00a2f46b2f48f	\\x00800003d72d91367fa5d206f0038819f7c3a2a030017e271f3ee8d798d364240a07c3b99d28933eb9307c27ba5904a50da2cc59cf266fb52a4281612e7b890efaa253910a9c1ac4fb2e8258c0d252f3684043bc678bfcd4fa25d1b569f610f9f38fec530397be62551033f17611fef37d1854afefd6f074dcd7213d6d44265246ce3779010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x79e75eb2f568c02bc936e26c9bb32c3c15506e01e5532fe019a3197b9a8a5a835de8e262c611cf1031bda19abb7fc90db3a94457f16a8b06c105f810fd0a6900	1613157714000000	1613762514000000	1676834514000000	1771442514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	394
\\xbb0b712bd7ed2ca2fae4ca56ec1174d11e004316e337dadcee39bb9e6fc12775e632d06e20fbd25fe1d08554e07944280b001d1b140bf81e7f59d7d0ee9f9ee8	\\x00800003cc30290d7b016fed8a006e52426c865d1d698f4cfb6450ecab9dded8c4f38bb5598141293f1c3c0516a28c157708cd999c53c77a22b8bf9aad03177488d1ef26bedfd550ac1a99f0ad779439ca2631566412ad273e856b700fd8875f3f5976ead6eeb5ff8cc23878c397ebd11eb471a82896bd651938190a65f0613dd07913ff010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xabecee4ec49324d2b41cd2f149fbb600117b27da9715834858c27f4c1c89dbf09d448c6fe35bfb4b187554c9ead2abe9576eaa9b86ecb3d01c373539275df903	1610739714000000	1611344514000000	1674416514000000	1769024514000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	395
\\xbd2ffd06a8927b4e40e201e37e1224cd4a7037e8981e6c3e227c1fc82e03ec85c72e207532782c72b732215646d092a936db1ce77dd72864785b670a6a6f2f41	\\x00800003e85d52db757f20c40baddf605ebae6fedbdabf9253455e2cf6ebe3c6c89d37e3c420d48cee722bdfa2981a75990e63143b8171e8a375483820f795a763da80807c2d15aaf6599516ca347ee05d38264b6adb24098b169760de565fb5e8d2de27aed2c859ef83ac8d026b239502e497aa9dff5179cc272a9fefc4c9fb188d0a53010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x4496d991bd49646db637d77327dd37226e3803459c129d8349024d7a8e3583d3e9545c6891e82a0e7518dfdfc7003c0d49337af56db528c19fcdd4773661ab0f	1641569214000000	1642174014000000	1705246014000000	1799854014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xc2d79fd3e837207eed3881a061596b69545643d92fe794a41edbedad0cdf39cb309d112a9f93ebba8377b24969e3a14bb7c52a9fa2da8cb93ac011d19a2abb9c	\\x00800003c1d3c67dcbf22b339599df97d1413909fef2fef95b7ee4c59da7329d08c7f4e44f17ed5046ec5082e73fb065cdc1e9fcb625cc1c51d50f6b351699803f03cce2cf316c596716242c9de6016500d004ee6a752c6924d31656e1b12ba22aa644396f05503036cd74a2b2cdac66bd50232e331ac7e86af9852f4bb62f7462490a8b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3b5b511125d4119e229ed65b19c2eafd5ddbe18bfcf1b043a6b81b507f10c707474c8d3c91ef36773822f3bc1d5e5f378eaba24688921d1e1c74e4b866b9200a	1630083714000000	1630688514000000	1693760514000000	1788368514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xc55bb0e0dc48e013aed909e99279b5b4049be8cccd9f4b24f1b0cfb92fc81a9477d8180a9d30fd0739b474f72a8e18a9ec3142f7c8ae9a67a9fbe8b8f60141ce	\\x00800003bb8b6f31ee80aebd81c8602896e135fd833a42efb7278fe27f1a4823ace56a3f8befc48cb9e47465f4c58651db62eb3c1be32490c018a734d43a21aff0cd6cfebfc4029c310a0651923525ccc470cf392c9e57f829691e40c570c813fc60ca71c0a0ff248952aea859c63f1512844c95bd83361eaf42df56a3dc2ebe09d8348b010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe862d12a41b4db6dc2906fd7be3d84cb8d2b43e8b0c3c5d974eb751cf8e7b0a910cafcf3348a4b9fb00334624db65dc9b04a470d7468ba9bcbb30ec1d87f1b0d	1629479214000000	1630084014000000	1693156014000000	1787764014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	398
\\xc6b3cff1b904a47c49aa63e2aab4cb9294677ec88f02c255ab5051b8ed04c8410cbcd40ecff3fe1fd34a1695dcbc5f17433bb80f160c9942313c36274513f8cd	\\x0080000393b0971da5d6554b3d3ffd19aa567886f6d599135691142c5d2eb03f8b610ba60a7fa3514f9948cd991adb6ff2b98a4830b55be2b0f40252e4acdcaedcd143f95bf9c7153c370323bbaaabc5cede7d1c561da98dbc9158ee57ee69d36bb4a893775308dee8cec69b5fa5e1815a2287dee2e4cf300c98a340b6ff00e75bcdcd8f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9a754dcb8ec548d330a11e9b12d377d3f71faa3f74006702f07b05dd0546bae3c9a741df79ee940983f624ccdf6f33f77a1612b870009a2a037e8d243221a60e	1619807214000000	1620412014000000	1683484014000000	1778092014000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	399
\\xc853c74432aa7eaf7b0eb621d9b9e3f107230f9aa7ab78991408c4fdac07d0cc6b7024c0f2b1e826004ec569a1bdf9c0235092231aeb5437d4acf7932dab5866	\\x00800003cd77bd8a525d306a6c60df468d68a936944fd34ff34f69ff2c09bcfdb742c31236ac87c705f9cd6365c51d9a64607ad70b58780054f80ec91187e45ca586ebf627f880a6ed345c6cbbbf35137ee1bc62cbeeedc6b021c53e7f4230db8667236c17d80d058bac06053c7657fd3b1064d4dc7b284b5f3bb03920a480a553474f79010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xb0a73901ccc6622b1db070ffe592a2487207000dc252d39a572c75810978437fd1f1dede3720ff2fbb61d280eed9c9d8e63bdb19a5cebfcb91ed26f09c4f7a08	1627665714000000	1628270514000000	1691342514000000	1785950514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	400
\\xcde3a5b50db2044c964f0a18a8858d9e8a7374d3fc0c9376200a8f74b4bd125c9d62f49896bd9848fbbd38fcb5e9f358f42d617429d8705de557d9d1b916050c	\\x00800003c71456de42d568dd26041de21b2fa825f282fa591df302869dec57435b44286666973d64bd94a9e83bb4ba023f4395792733a422e2d38404498059bcb10e57f42a2d51fdfaee06cee5ff932253660bde645129c3a44d37bb061a90b45e713186a5791b6a86863e423215c42949133f88fdd099a2f530578d8956a0072f5cd00f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x77aa1a04fe29b86f5a29aca6a82509d91bd17461b49a171cd37f7c887c9342a256d4a04a9b101fac170be1aee8cb4aa039a87adc07debba42c3700605d71e10e	1641569214000000	1642174014000000	1705246014000000	1799854014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	401
\\xcd67f7a10c08f783523c0ad93b2d2174177d3d1c23b106ed095dd0ec2321699f0f576d033b9d267341273a1d847c78ccf178aea8695c71f23145075cb53dd85a	\\x00800003d9f74a7862e49e79e9fc9652797a8b8a6be36b1926a2f37e4ffded7223d097cb35f5ebd1773df36073947548206bd5f6e9e4eecad7e490502d451799804fb7a4eb933d1da0845dc19f960bf5e7cf34821aa48a98bd6afb21fd3c7f2e46bc3f441523324829e7b763efc607f4c942e927ff3d3e82af2ac8470cda1154a4f37fcd010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x55fcb1ce4604d1fa19dc01416ba64f7fda044c7f693e38b61d2250bcafc71f05325b5b8741ed69a464b7e1b583029c396005f196def6ff6ca974812416fe2706	1616180214000000	1616785014000000	1679857014000000	1774465014000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	402
\\xcf2bc974fb955ef73234faad907f185fdba75a8f31434b31c7564787a684b27da552b830f7222d0b5efbc345d0227d360d9cb8ba3b81a86606df68035f50a4b1	\\x00800003cbc01425a2f8fea02d0093ff76aa5c4638a5f84eb5331a022575c77a3df0f1218e0aac5c206ce101239802028c2993c9e7ff7d2fbf43bfaa56bf3b48f4ae565effe3d3576e4d2c944845c55dcc26da433b4e031b8138b6eaf0bcbc9b15d400743cb5bf135f3fd6a881a247bda57d036b8447a364e215a4e41458d27f3a6e8a41010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x80bf5ac095fc6b0ba3485faf291b2cf1ca5ada34b62410b896a0edc2ec7ed69f1433df27165e56ba70e6fef03e3d2030512012cecf14983c5db7b3210a798c0b	1630083714000000	1630688514000000	1693760514000000	1788368514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	403
\\xcf4bae98e1d6792c3a87ee666762c38888ec5c01e0e9598d6501ad1a7b45f80ef7de0ba8a0cc44d143c324339bc9ba689338d7df8d84c63f41a3aa599b12390c	\\x00800003b6a649159765d17282c93aaad0e984549a6ba3e046cedf8d1e4fb081f5222562b8a1ab66dc83933edf80696e81e1c43e2fda4881897b5a1ea4e72ec807770cd5db18dc4b1de4d0db86b9efdee68d338dacd2d383fe63808c70e6029f8dba1ee46006e5e8f789562288c033fa2b15b082f239bc765007ab38a0bcd603263d7019010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x0b78be5d514eb11ef768fc70231a4edbfb7bbe67a1cc8f42f43c61404239bd5dc66e6be9d40b3ff56c9c03bb0249c271098381f445ebdd531e3dc9062a97d507	1638546714000000	1639151514000000	1702223514000000	1796831514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	404
\\xd07f21fa1c262bf045115536719373118ffca9f79cab82e225ab1f245ea62bc868f88c9a8043a5371423409b8e692a52fb9b0fd7a0b176066398fcf54d04a8ef	\\x00800003c06e2c83b0cdbdeb9470a125df2694c0e9c581b668aec4b02bc752e6b148d14eac0cb37532ec62f0c8adca52dce45b1e97a2dd54cda980c220bceaacb75b3270c7be5d2ca890824016d20dce1f7652e79fd8ee0c47f1fcb63bf7c107c4a60504895c826ac851f6a76f868d40acc1ba9e043456dfa2fbf9a64b56241e81fc22cb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x435a487d21df6c11ec757561430f8199529c99d3442912b5f7fcf947fec766c556537b66efe48d6fffcf16f5ebd89d0f00b61440d4e6c9cb5463dcf98a43770c	1639151214000000	1639756014000000	1702828014000000	1797436014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	405
\\xd36b6f9bc8462b7b84e3761e4b6e1eeb5fc725eeda8f60bcf931435b00074c04c07dbe47c884358e3b9f8957c9ad559224cb71e51ad735f0774b96722619d810	\\x00800003a7e5eb8a33cd7bb06b8f99f12e6df6e6ed3735eb5a60fadefe6e4f66acd49765492200f72755ba464e3027ca37f7444a912d28e9ddf2edad8729ea59dc621af4172ed18e64a4fa02a003d99bda12f4ed13ddb7adb539e0a9b232387d9696385468911e2a5a532558d952001150e1ba105f91c75991aee2cca27e96c1e34c691f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfe4288440fbf67fc6b7388dee67272ba91101da35437be7cb3b48671492be23e95812d43b4e00b9969d0308eb2e3a6b8a56ca83de74c4ab6703f02d472dbfe06	1632501714000000	1633106514000000	1696178514000000	1790786514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	406
\\xd55bcea3c0991f4b6d5d52f6d394a2b548488716f1b472b50352c5799dd42944347e911e32213758562d95728452f2efb57219196386ab92e61e334897a75271	\\x00800003cfd40a8fe67b4775bd13979d351e474b9b3f68ecb0b337d69d0e1fc5c6b819c524460872788562935ff86bd73d7317f0de5e1ce4bbfa5ed9b33c9437541c46c830def2d20a1c7738d26dd89fff3fe87e28295fb004e9a85559a055bee3eb52183dea927e5e5aefc523cc3687f8257a8d94ce2e2f300c47fc82dc74c0c1e2afc9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xd32b1e1bb8631353ba28b2a8629f54e03d87b38d2cd71290e5438d3029e0bab5261f0989f566e7c8466c7a0942c024944ba9d4578c4bd28383d902cbdd5f120d	1636733214000000	1637338014000000	1700410014000000	1795018014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	407
\\xd6ff002af47555d7a3b9e337d5099da9046c29d2dafcb660ee81fec44c979590c6498d77fe377d11ea992eb4f6ddca3ce125a7d9f88dad01f0ad1e7bda6248af	\\x00800003ef10acaf535c02939414c40b403ee4094521fe45c1c617ebac5400f5acf4580e0371a3344ccb1bb476f6522915885d1dd6afc154e607601c457fecc596befbb3663f98dc7751c6cb28cebd50322ecbc2636d6962892342951de0ce2accee54f25a0afcff7d1d6857bce11ccd1a007a5c90f1be03f3cf52a3c7473ccf26fbbb8f010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x8bfd84066909168106ee79a79bbe960f7a523b3434886cad62ddb3304d96a9e27b053f997faf9b0705b8b787b98422d840e44174eef6fb461bcf30e142520b0f	1611948714000000	1612553514000000	1675625514000000	1770233514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	408
\\xd64f6b98d442081beea0507f563cb0d852b61593c08b3dc229ec67fb5a95a4f916d4ad16817602e220c0e1e47a13f4e43b5f855c25ab541f7f0bcf483b7e7808	\\x00800003a8382ee11c44e7988f0cf108e517605c8ec83e8b5c77b28074d8d1715ea3aed0d5dfc7405a73541a0fab74cc95dc6cd823dfedd523fdc0948d156605c5ef363ab5484d87a6eb4a7d47a019289bf69dc6fc3be94448a6fb76681f9ce12c8f14ee1a9e9bda70dceb6227af082fd4bf6fce7e31275f7616f5114f8689f8a8b0463d010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5d50eb1db6cacdadfd684c730f0d095e9a25ef622c22d5f12b085c3c03c40d500dd12ff04790827e475fd3546264ba5b58bf5acfbc574ff6b1c8847c7c162303	1623434214000000	1624039014000000	1687111014000000	1781719014000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xd9db5467f0045446163b7d109e61609d4fb075a6d09e5c051978e36caaf8e1683e9bfae40460c1071d4f709f76467026db182256e96ff14761c166c0f64c538b	\\x00800003ac860633ef73e4ecd7f5e601e1ea23bd40d808a12d24424b32ace5e0f0d17615b6a33d47d21ad00b84b68f5e55204cb70c9fd758dcb4c854b576892402e0e82f2326079a470f24fb921f9fcdeb1cd5415d726df1a763a175c8e201217bcf2e1fef04f501e3e97fbc4e247986c5f291274cb69adc1af7e6f7e5063cc4b67942b3010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x9eb9d434ffceee7538b6360e01f53a9ca35b4c5e28f950d506861fad712290c7a67f9fcb34859da4898b038d9699f867c78b513ba1ac017e1085ad2eb5310e00	1621620714000000	1622225514000000	1685297514000000	1779905514000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	410
\\xd93b657cba0bdfd85a9f92adbce3c4edd6b07f752a5f994a957e342b77e07030b3feae5b7b2405cd2cbe46da1c2a81449373bd1dbc29a551a54d395011d62e25	\\x00800003de24c57165fd1d9453249d9c305398e95b11ec6f159b6a062c33b9179bbd0863d42c50a3fdb1e4a2e55909a99316e66ea76560a085fc1acfcc985491b373bb680c5647cf5d13d2b0ab70c430b2ecc98318d61f1c6ad599ad2b1871546af1cb89d02755c8920576b31dfff07225e245ca12a2f6e9f03cdac8bcf57e4ee6696ffb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa48996015bee6a2e540f94d071961c69c15c45d74292908debc6638b10891d1a802a10f1d5eae6477b3615091750a66abea3f60d727cb3da4f1ca53de0a83c00	1632501714000000	1633106514000000	1696178514000000	1790786514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	411
\\xdbef57ee79a8877fdad5134e819dfc95d435502d0eb9e56e7b48fbf234c98c6007a50808d2a3e546411a58152fb5754519e76ac1191192683b195e6ba0b1f66b	\\x00800003f7949e0af0487ba5864c35fce5c4d88d377da56417c2ecb73d0a8dde7c814a28da5c359f573cfb37a631f9fc35fe5173c4abb93364880f90f5570e0a6d948366be182431254b20cefbf684d3172f31f96622f36db78e85f83e609233f89b80b3a8e95aedac3382a57fb7e394d45dd71103037d0b009afb074356f758854f1ba1010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xcf0ea0f15b8aac5089bafd69acd4b1286b0e6795fd8b68faba38b43b950598059a6f58e5b5dcb3ae1609af2acf4bb26dfd90f8f2f44aeb820ecca7e01081dd0c	1624643214000000	1625248014000000	1688320014000000	1782928014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	412
\\xdc974e2249a976be4a425dfebf180187aec2344aa03155742c2de354414b8ec40f19f9e9e7d4e3ae0ec014d4cf9ecc0bd2890298fadfd8cdfbe7fd58340d21ea	\\x00800003bf7e1ad8790d4889f9e16fad81a842ab098444f5887cc4584b48b73639be22efa3b9686300aff7143ab1442a57d2ab602c5a428f07bbc8e7755254d0461a569144ad2bb4693a09cbd9ac2514be8405043e5652e6786a1229237b452a5c1aca7f267bb28bb3c1a4d3c0c012439731b777ace94fe0c58bd4c1d0be546dd0e49141010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x5236fe96bc2c8df1e0222a86a52afa2a0cbb8680e20c7a6b9a62d7941944be7cc3bafff34cf14dd0c0a18881b1595a3d2cc81dffb392910074bb769aa8e19a0e	1614366714000000	1614971514000000	1678043514000000	1772651514000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	413
\\xdf2ff288eafad2508ef2ee0d54224696cdfe1fe3a6477acb340cc9416459727e64f7924d633fa52a9aae9859ee81ef17d0cce5e535d341fc361c44dec0839d0e	\\x00800003d789d702edbf46b675d5c2d05d664211de00205e302e8a2146def65246667a644b072d247768d097a73814b0e5ec5a38d94a8817001ff66b9e423974bbfff28821da64cec3e605553f0d79d487838de578d8222e62ef1cc831ae2c67789bf020421b7d521709e48cab1a0626a86f5439bdeea2a465aa32fa284cfcc4295ea9d9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xeedcbf77a1331beee6ddef02bb87d133d6f8881c33eecdbceb323a5bae053e09f5bba1f03af7973f1edeb2442e2cd8fbcd4d230a36240da23484b5580479770e	1617389214000000	1617994014000000	1681066014000000	1775674014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	414
\\xe11b3efd97ea5b5fcf06bfccebe776a6ea5a2cb24a8121eacf29523fdb87dd6a068a3f9c34272788d525ca3efd4cbc747c042211ba35eea795cd4b56b203e3a8	\\x0080000394383ed150f355b46be7992c8d28eba42ae471702e391ae24a095501c65a829e01e662b333ee289883f2399d99613d4fcccf0850233392721fbe58a379a2773973dfdb2ad13a3f886223f513c39cf0dfdad1dc6091553885fcbce163c6a43b7419e78b0e5cfb9b5185a6a2a09e05dedbb2f4ab0cc5ca494972eaa5f786e902bb010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x37d294b7cb4f885b314122b8ba7fdc6660416d9c6894ab5cc996bb3a4b97630438ca636cd8154f726143fc60882105912105a43648c4c50f16d32befaec99e04	1636733214000000	1637338014000000	1700410014000000	1795018014000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	415
\\xe6b35c63f447fb21e199d85537b1b6e9f8c9cada56ec51de671e3bc64873553f63699521f46652bce6712724c36efb52ae9488f1cc38175efe3e4c4bfb3bb767	\\x00800003b975f6c22ca7bcc2ea4eb61977650592331247c8ac2c13286a6273ea7b21cfe8a9d0fe24396b04c673ad47ab3a98d5c1819e31144c73384b714d82b60f5c59e0c1e3c20de073e82271bc66cac79124e805e056685b2477bc13cf42790cdc57d97bff499958eb1ffa9f3672e55c40c38f6a08383b55d7088864a1dc60f9b62309010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x62b4980f640d324a9d896b83e72cb8ec47eb2c65d1aa6600c7e1c17cad4f9fd8b7bc3d521a76367fa5767117dc5a2b9777b31fbf6c4a1a250dcf277ddea4970c	1628270214000000	1628875014000000	1691947014000000	1786555014000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	416
\\xe92f233ebdfe42e893ec164c6bae377401aad6ddf6eff43bcaa76dbb72eb61e83febb8a8468fefe70ccdc886bb6531775eafeac6d555f6cf3e87147ef25af96e	\\x00800003e1012f5d9e0f9c810280de6b78697e90b524651ba9fe9c13365249985cfadadd23e04f6ce881e702af2d00f2fb4a3ce14e19ddfeaaabe7b7fdf72417a748e3814e594da429f8090d03b747ad405a27c57cd60fcab016bcfdd519018828d1161b09381dbc0161c669b205378747530330145b6cfb8bcff67f3a7451f4a33cd4a9010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xfc5cd9e7df21d1e234e703a682bbf4d6cb01ee753e2d9da0da291740358007d612650423c4270dd1df623c4efe390988f439c2bd1ee1500a24d861ce100ded0a	1638546714000000	1639151514000000	1702223514000000	1796831514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xec1fd7fb0adca14fb1e926a78b19599ee99e265801bfa8b2657453be3ca67b448f89b3dd774dc68ff9877b4d407a14b5f70f24c3106d5f7ff408dd6b25f46467	\\x00800003ab33ad94e3943c42c23acbc4d8b2c6dc912b0350910f8e4ea92508d108a31dd41238ee18e4ab745744b06adbbe9ec1016ab1dfbc7962d00c4a7e4127cefca16480b10b36cf037a1cbd5b043ca931b749407be29c6b8c55914210463f8bb762f75a888303123c767f134e874635a9e78d5b73bc3f3bb9d7f261bdb17345cc2e33010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x964a48b024e51c05071fe0d6992fca3d1a2bac5c7f2263a3e4a188e69f40809ab54b7fd408cd9db658cecece01eab881ded6fe83ce4e10e3d78463b50ab6b00d	1627061214000000	1627666014000000	1690738014000000	1785346014000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	418
\\xf48b70746867b0f0a1bb98d5df339cfe7f06ca95752ea8fb2de86f9ab1852e49267e5e9e8cb9d576ec91957fd57e9315d1f218a5179f62cb818100daabbe669d	\\x00800003c74e77b93af11f719a0db337d1ec3d2829bb901c2bbd0a93eedc42f90d3f4d8efb008a61f9a4abea9b8435dfb813c6aef2bf6bbf84cdb8554a276e0854a1e310accefba8837391c06f444762cda5a40e89835b7233d97c426bbd58fc5235ad83e5950e83df9c81dcf2ba909ba0e9878d5ee2736dc89bc9e283f13c59a6415d89010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x00590f1f3933fb7297409809748d0dfe6c01267e94bc501281d2884881e9a69e0940fb058cd25a6e6622c7c5568742ac11938c2215dee8cf76f2da1c60b9a403	1631292714000000	1631897514000000	1694969514000000	1789577514000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	419
\\xf56fe3edf4a94eeaa43dc38c3b5a11293c02f36fa93d2784534f3fc484fb633b19fde7197988c6e72c223cc7c5f0316e52a8852d4875c26c115028ccebb1cbae	\\x00800003e992876c2f4b1154625171adb09fe4524b193d04bc983ff448122d0b1eadcd76dd6a99bccb3a94ec5c8edaa21323929dd85b17cc7bcf103b4a8cf181eff793c904e08ca300f2bd6c98d7de7aa80ff3292f3c8add2774ba4761ca6f91cbe1bcc5865f839d88626e26084816120a4f714fbcdceea9d1706f8b187337b10bca6d17010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa8850e3361def75396527c5e8d42f5842d972084d4d7c5040ffcf9e6b706aa12540e95da37bd1ee95cdd6e59c41e70f92b0498468d88369d693c8a1c00dbd002	1614971214000000	1615576014000000	1678648014000000	1773256014000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xf803fa2995574403ec0918e327f41480b1f32590b368ca9785ee5d5154814f53f3a91522b9fa4f9f066f40da08eabe84d7297ac395a7531036c87cfb841cdc27	\\x00800003b3878ee8ac4421e05e586088173b95916600c08c867f91d23c69352ce957e99ebbc457f9b349cecf9a72cad9833a0e0f8470047acaec0a8d76ad5abeb2289c88d79d0e1a4c698936c63b033e97e030b930e9f2ea44692cb51667526d872873dac9de1c9401f333835d1aa3a3ebe538fff658d23a173dac77d91dadb33c6c4e61010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3515a321ef2750d214a97bcf6756d6388761ef7e862537552360186dfbb5543fcc9932ed2f50f63a23e08085df359609fdba623a69b531bd4ade75e23817cf09	1624038714000000	1624643514000000	1687715514000000	1782323514000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	421
\\xf9ffea47f6e5921c447d2c1247e3d9fde47dc2661bd73caade3324e230f0314d8e46fe49a66e5e8f69684d6a06b966428d37fc56403fd0a75a689a8c106b5db2	\\x00800003d270fef09793ba68ec2274141bd9dbb30edcbba99832059bee016a6ad75c0bc6b9e62d442890a89d85201bb5904a80bc4e095b32e33e13aceb6e9fc1e1a6a35e59e6f52cff1986183738f59a5f323da2cc0faaa1528d913cf52700e6f979f71e98a9c586482f9e363bb584e148400c1d003e3633938cd1ea8768a19f506b3a85010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x161c06a7f6c48e6ddd6e993c52cfee14ab919331eb3e37c7be1c8a24fdb5bfcd71670d537d05a5a32ef24edf80b2f0cf4164c370fac1f274653c93000f111701	1631292714000000	1631897514000000	1694969514000000	1789577514000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xfabb49159c444036ac38dcfac5a1882ab6437826538116f38c5053f544443dc658476c6c689b1889a1e1743a70b6f766d7e4c7e4c58924791ab085cad36fa09e	\\x00800003a672cf87de22a1c9c2960e3f9de58bfdac06c410e528f78517cae79c87d1cc441f0e88ac5dab46bb0cb3d9aa508ef08a637b4f44e15257fabfadc8b4bc943c4e77cb1ed0357f6268de7052fb0a91eb6f41bba783760ff01e6ef2e420d612cebfe9fe89f1e43a9f2e91e38678a23b6f02def0ab8f484942fbfa7b1d926123c409010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf2666b866128220b3581a79270e0a82535f6226392bee9eb3e492a61420e6eddbd2ee63c23518ef4757ed2c5dd5a94211fee47763001148491bff95497192802	1633710714000000	1634315514000000	1697387514000000	1791995514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	423
\\xfe3be54c6018650ac8a34215b4d1f1a1586a742cb0f8595c47768970dd1c6034bbab0285b86c2c5427facb9f03df269ba7df232cfd416f9db56c07591a76cadd	\\x00800003ba7182d91e9aee73e918d38f42a410af4659c1284456da5de42ffb29a5b3f88792c933ecacfed3f1b639f0b91e1eddceb1f04382f748eeb40e5d757db76c51539f005c46f7577ed72082491b4e77ceb5512a687dbfc110b288a7ac7fb33c3e0cd27bdb16fdfc29f7ac4e06986888651f91683aea474a59f23f29d714d7e6e6ef010001	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xe3fcff8770d1ea39ceed08f6d8f23120a4faf9efbcfc48aaa718fcc9e7e3f57789cbbaef8eff442d35c6e4352880ba6885e38faae38d2ca0ac95f69c440e6b02	1621620714000000	1622225514000000	1685297514000000	1779905514000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	1	\\xad9d9dce0560c472a24b5c02c1c8542cfcbef9f2d7e39fc353bd629a4bc39322bb646d5d3157c7bbab531aee4c8d90cb0e0735641a8005706807d7e04e3a694a	\\xde9fb361e9435025d2ab577da681e1d093ef8f2cf3329b76f069e9a5ae1d21b7b4655b561766be95db0d8371a287d52badbfcf5d20c196e686cdb965199884fe	1610135249000000	1610136148000000	0	98000000	\\x6fb09f6086e907806d42a20df2ca05525d978072d4c8e765394a8aef3e1742a7	\\x108c6ac9c982adf1703b51c46005cd09def1655dade05baa77b3488def710e80	\\xadf0b6c73aa42d1866b9b9a1db7cdc9a62446d8ea0e617eb1fe2f3a8a65464ccc59c335ad33b93c35b52aae04df169cade014daab599dba3a0a23ff8c91f9601	\\x2c6ae93ede9de0cfe5ed0112221bb3967cfcc2b00ca9af6fc88a2147ba4962fd	\\x293e2ea001000000609eff6d227f0000073f17ac14560000998f0044227f00001a8f0044227f0000008f0044227f0000048f0044227f0000600d0044227f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id) FROM stdin;
1	1	0	1610135248000000	1610135249000000	1610136148000000	1610136148000000	\\x108c6ac9c982adf1703b51c46005cd09def1655dade05baa77b3488def710e80	\\xad9d9dce0560c472a24b5c02c1c8542cfcbef9f2d7e39fc353bd629a4bc39322bb646d5d3157c7bbab531aee4c8d90cb0e0735641a8005706807d7e04e3a694a	\\xde9fb361e9435025d2ab577da681e1d093ef8f2cf3329b76f069e9a5ae1d21b7b4655b561766be95db0d8371a287d52badbfcf5d20c196e686cdb965199884fe	\\x52712ede97972be2b55e45064d68c40b19083a55c76856fbc648d052c9643cab0064a4cd872aedf7f62823b944f72a9110ca93a80de5abd926e91764868b5903	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"76Y2Q9YB63SABA8HQWYV0T79T56R8XRJH08J9X5DFE52YJCNS9XSKEE3VPTYMPQSVHEY7887KKMS7J3WY31P9TAPAYNBGSYSPP8C45G"}	f	f	2
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
1	contenttypes	0001_initial	2021-01-08 20:46:54.999628+01
2	auth	0001_initial	2021-01-08 20:46:55.040266+01
3	app	0001_initial	2021-01-08 20:46:55.084577+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 20:46:55.106539+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 20:46:55.114925+01
6	auth	0003_alter_user_email_max_length	2021-01-08 20:46:55.12095+01
7	auth	0004_alter_user_username_opts	2021-01-08 20:46:55.127748+01
8	auth	0005_alter_user_last_login_null	2021-01-08 20:46:55.135289+01
9	auth	0006_require_contenttypes_0002	2021-01-08 20:46:55.1368+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 20:46:55.142232+01
11	auth	0008_alter_user_username_max_length	2021-01-08 20:46:55.154928+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 20:46:55.162293+01
13	auth	0010_alter_group_name_max_length	2021-01-08 20:46:55.174743+01
14	auth	0011_update_proxy_permissions	2021-01-08 20:46:55.184938+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 20:46:55.190863+01
16	sessions	0001_initial	2021-01-08 20:46:55.195743+01
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
1	\\xa4bf3ea0929e03f85f3880ac2b2db42a8a8330606357798d174a0b2a8af59485	\\xc9b4fb6b9a403e22cee90f293c835e0be4e9af4672b70a26e3d4992ea8436ed86565115812796e7311206fb7f451cc02e0f5df4ba10a919b6a2421a432703c0c	1624649814000000	1631907414000000	1634326614000000
2	\\x2c6ae93ede9de0cfe5ed0112221bb3967cfcc2b00ca9af6fc88a2147ba4962fd	\\x62fb3d47dc948eec4a2473ac50d3a15bba86573431e9191113798aa18342d9d8fdf8860e569f997786eaa6b4cacb79e3f18def5bf67fa4528634105abce05108	1610135214000000	1617392814000000	1619812014000000
3	\\xad4ad908cd973b09a0ae57783f7024988a5440015fe11248106ee21ef0e9d557	\\xd89337889df41850de0c6c9acb0595419f14b56b86f29610f0e68be3811b07aefe2ff75455845b7970f562a5e8a5379fd5238ab72c6525e800d55a1a5666b201	1617392514000000	1624650114000000	1627069314000000
4	\\xce3da35d5a8aeb23738cb016269761e990b5e344b758e9930a1753c1cd0579da	\\x450598618c0ef4725b2ddd9b6d83dee8a101363f652408fcda98ac9374ce25f82a38aeb8abaafa35e098e8801006ef1474730fddd62f5afea9e8cc90f6876509	1631907114000000	1639164714000000	1641583914000000
5	\\x3ad98243fea2e0006151a7fd6910912f0651baed7bd7880014e6fc047db82f44	\\xbfcab217d7955fc0e321e4e751e8f6f7b20e6856b3fd32413a437730d432d06d2e7856265969b28ba3bf87bc75671fad43faee1ae43662e270063504f9abc704	1639164414000000	1646422014000000	1648841214000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x1bd44956b02e0bc2e6be7522bc511ffbe034e5388fc334ad299dc43b1d46ea45	\\x27c46c335da12a09bdb1fe50d4fe74d5e6e49a81d9655c8289e2e5b37920b91c40846447db3a995b740c6ce6fcbfd84a75c04131d821616d8b27b52265c7135fd95697aa34208ef061d0aa50151106f97c7aaa0794111f0b495fe52c8a94a52fb0bd4302989e52e32ef62f655fd2ad328f051bbb9a73c89ea2776976b81e543f	3
2	\\x6fb09f6086e907806d42a20df2ca05525d978072d4c8e765394a8aef3e1742a7	\\x1850cf00c20f710080ca4bcb679debbc1dc877353dc103946aaa62340a5c6f98862e9f1be4db96da323eebfe5d0bce2819b70b9152829e05460d199bab89e070725d35b17080df239970d5eb78cce9991586314172576e4945a48829d7144860910ad3c3bd47c6d8a6776901d29ec96081fa8c45654b67652e08370668778b6e	180
3	\\xc35facfe39ce835596f66275b671fa6420b453e6cc4c850d4b00e14557214e67	\\x7513c97170ab41d874a69445f8b0edafe09c04914e979909f965518a812cc81246f10d87ae6a9d85bc7be6481423be870102c90d673e3d0a52f5ec3f392f234cbe64409cd2b8c5d2285594fa86e28cc864417ba477c4b3c795fcfbcc43ce23efdcce4f46f973912011e47339ff6f83df81b7a7c9a1fa481ffeaac95631724eeb	353
4	\\x8a74e464feeb37158e3df975f3849cc65021e2774f29c2df94d4faa89e392585	\\xd3e41cbc0133a8927c9e09ee3d7fec7f93439a078d923a85dc0f308ab3bc1c14578628d8a1eb98c98ed28a38d52aa186cc3716282e3f93364f1804cd3679d46df1a3f0c24f979c6b64c7315b2755cfe9a00f4bd1b83113c80359744657a2dd23a23413a412a3d0561e66239d65fa651ace04aaf7e4e6c11067a7803ac973298a	251
5	\\x4997f86b83c75e0583eaa7f43b195f541febb253d772bcd10cc5a8f239291eef	\\xb0b02401f587ac956a0ce5537b49b2b1d6095ae840053855c9dee3638a9bee6f60b71f145d5e0f1f4fed7c90e131a0d39f234fe1f169e46b7f450da833f56b25adc37fd820160060a1d3e8410a29f898707eacc5ee973b02e93bc2e6cec212396e08e634e6f4c3ed34bff36fc89c097fcf074807b3f6f3e4667a414de1764866	251
6	\\x5009a8c7f7cee835f3ff2835e2c389e3bc7bc89ea195eef9657c70d6f6e03bde	\\x8e54c5788aaa400c61112ef01ab2b844fa7f513e46eb7710f2d36764e30c641b044ef7596a14108735f02823faa98070f5b5d7f9f966e6b1f4c6560c345fd90f45cd3965e00356cdffb545a737c6bf3cb9c12ed8fed6bd225c25d80b186d46fa8073f6bfa4dcc5bf25db2043a41f4dc7e77773b6444d1d7e2b638c44829f3c09	251
7	\\x4ecce85faf1ad5dc9acd3201a9b49e85fa96def6a9b4b9cf66a28548e0cba366	\\x8cb88b4e889190d1045eeefdcb166ac863b01e4ed61b2b2cd3d97a37c03d11a55a3237f9ad68af7fb367a6a0e3c8cd13f848f584aebda74810711e82dc55ec1a7a0df07f06f56f65d0f8820c8ecec60b52711d397d8f71b20e00228c146ebbf9033fcf19479e9380cbcb02778dcf7d983aa8f8ea8003790530760879f96bdc41	251
8	\\x7bd386cbff52eed844804db0bcd26b95cb5521c3563b3c3928f2252623c0a497	\\x6c171bb8afdda99856b845be8a112742edefda08393ad80242de4d6fb1cc2c5a9b001ae2a94746ebe8ffdb861e6d345d030c5f8b013dfee23d550aec24a346f82a31a0d43feeb195a8684ec555d20324244ea48a60a818a0d1a060c2c1da867c3b94611029949dc4ca7d0ca7b80983e8ab970f440ac16a5be783165682c2b9a2	251
9	\\xf75afe2d1d3fed68ccbdf19514de3cdef0a57ee6d48b733fdcb75e0fb0655cff	\\x7e0f7bedc2c8aa4c4787a3b70d5e1e5f390bad8b617eddf878ee4c49f2e2d452f6f31c80095c0423dd34451bd291dfbec58f6d67c80dc78b91dde6e6a70de1463426c94ef00ab0ffb10f4163cde2d27de0eb1be0cac1cad0d886ea5e0e68c2b03fc92ff0a208320a1c3430dc908b0195ecb86f0c596ec4fb9ec64735a42b8a6f	251
10	\\x96f787433358ed031cc4ed7c301e446675c66b4aa77b3a7f6b08a0fe6eb0bbe6	\\x16c61add8be65410ecb590f706f4e56689002ddcc33696f20c497535c2a81575e32e163062f77ec00ebd331222ad0935c4981d75e1aa6bbde28cc70e78b3ef06e7573c0daf4c6190cafabdbc382161b36a942212a8f6aa857d1b683be00fe27264b50dc082778c288d7b08401c7eaa09b32c9c7be89826ba8eead30195d6499d	251
11	\\xd52df8072276ce904ea389a8879362f6d5a1e27e9780c4e4d14245bc735b21e9	\\x731ce96d81b7d3aa4262a62abdf3059de7fa1879e82d7530a4708f91daca5bda8c27b765e02fd7f30dd5c5cc41ccb971a6b19796991cb293774c53218beb20747d413d70b778b4f77adf065c3f54d66745047a45d416170a2120377a14d6daea0eb6a3238857f37816adc13c09650d95b7caed61f43e5d03fb558b6fdd17f1f7	251
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xde9fb361e9435025d2ab577da681e1d093ef8f2cf3329b76f069e9a5ae1d21b7b4655b561766be95db0d8371a287d52badbfcf5d20c196e686cdb965199884fe	\\x39bc2ba7cb30f2a5a911bf3db068e9d14d847712881124f4ad7b8a2f4995ca7b99b9c3ddb5ea5af9dc5de3a1079ce993c87cf0c364e95657aab867d9b590c216	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-02M3EECZTPDSR	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133363134383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133363134383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22565446563652463938443832424d4e424158595444304631543239595a335343594353395058514744374d544242475834365656385341564152425044464d4e5643365236574432475a414a5142445a5358454a31474350575433435645423533364338395a47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30324d334545435a5450445352222c2274696d657374616d70223a7b22745f6d73223a313631303133353234383030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383834383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223838435239524b3551323533433550473345414e474257373453304e3246423747594e33533936304e4330384a57343646375947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22323236364e4a45394741505a32573156413732363031454431374646325341584e51473551414b51504434385656564831543030222c226e6f6e6365223a2231535a3832453730563545523941594d4b50475142534758585138594542443432504e4148463754525741345a4b525047593047227d	\\xad9d9dce0560c472a24b5c02c1c8542cfcbef9f2d7e39fc353bd629a4bc39322bb646d5d3157c7bbab531aee4c8d90cb0e0735641a8005706807d7e04e3a694a	1610135248000000	1610138848000000	1610136148000000	t	f	taler://fulfillment-success/thank+you	
2	1	2021.008-03C59R1HDCNF0	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133363136333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133363136333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22565446563652463938443832424d4e424158595444304631543239595a335343594353395058514744374d544242475834365656385341564152425044464d4e5643365236574432475a414a5142445a5358454a31474350575433435645423533364338395a47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303343353952314844434e4630222c2274696d657374616d70223a7b22745f6d73223a313631303133353236333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383836333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223838435239524b3551323533433550473345414e474257373453304e3246423747594e33533936304e4330384a57343646375947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22323236364e4a45394741505a32573156413732363031454431374646325341584e51473551414b51504434385656564831543030222c226e6f6e6365223a223336425341574b5841334b39323132334847423852545636465352365458454e313947385043593346365736463636384a475347227d	\\xed5bc645a2a419ff82b2398478ee73fdda7672f1e18ed1924687cff6fdfb71c732f6fe914011c679aca477b21db22648825f77dd97d3f10b72b757e82d7f9d49	1610135263000000	1610138863000000	1610136163000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1610135249000000	\\x6fb09f6086e907806d42a20df2ca05525d978072d4c8e765394a8aef3e1742a7	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	2	\\xadf0b6c73aa42d1866b9b9a1db7cdc9a62446d8ea0e617eb1fe2f3a8a65464ccc59c335ad33b93c35b52aae04df169cade014daab599dba3a0a23ff8c91f9601	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xa4bf3ea0929e03f85f3880ac2b2db42a8a8330606357798d174a0b2a8af59485	1624649814000000	1631907414000000	1634326614000000	\\xc9b4fb6b9a403e22cee90f293c835e0be4e9af4672b70a26e3d4992ea8436ed86565115812796e7311206fb7f451cc02e0f5df4ba10a919b6a2421a432703c0c
2	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x2c6ae93ede9de0cfe5ed0112221bb3967cfcc2b00ca9af6fc88a2147ba4962fd	1610135214000000	1617392814000000	1619812014000000	\\x62fb3d47dc948eec4a2473ac50d3a15bba86573431e9191113798aa18342d9d8fdf8860e569f997786eaa6b4cacb79e3f18def5bf67fa4528634105abce05108
3	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xad4ad908cd973b09a0ae57783f7024988a5440015fe11248106ee21ef0e9d557	1617392514000000	1624650114000000	1627069314000000	\\xd89337889df41850de0c6c9acb0595419f14b56b86f29610f0e68be3811b07aefe2ff75455845b7970f562a5e8a5379fd5238ab72c6525e800d55a1a5666b201
4	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xce3da35d5a8aeb23738cb016269761e990b5e344b758e9930a1753c1cd0579da	1631907114000000	1639164714000000	1641583914000000	\\x450598618c0ef4725b2ddd9b6d83dee8a101363f652408fcda98ac9374ce25f82a38aeb8abaafa35e098e8801006ef1474730fddd62f5afea9e8cc90f6876509
5	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\x3ad98243fea2e0006151a7fd6910912f0651baed7bd7880014e6fc047db82f44	1639164414000000	1646422014000000	1648841214000000	\\xbfcab217d7955fc0e321e4e751e8f6f7b20e6856b3fd32413a437730d432d06d2e7856265969b28ba3bf87bc75671fad43faee1ae43662e270063504f9abc704
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x421984e265b88a3616d01b95582f872641513d6787aa3ca4c0ab0089708679fd	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xe30c73eaf0ef82b2a21526820d123f53f89abf4a6acd43bed27c3e2bc27e59f9a07a6603eefa414e08174eff4ff516b16a28be50ecf7f99651b3a35ffe0c8e0f
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x108c6ac9c982adf1703b51c46005cd09def1655dade05baa77b3488def710e80	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x287c933b8a738b316fcf3b208da2b5c3c065d2ec394987eb70e7924aa48a9d98	1
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
2	1	2021.008-03C59R1HDCNF0	\\x2ac468477a25aa8d5b3640ca52d7096d	\\xaad16fe4a8e8323ece22b1ca45dd1ac196428fa7a949dbad9b427489bcce0970fe4357332e9a52562cbad03c1b9752bc51e2fed034d85443aafd6ebd4fcd52b5	1610138863000000	1610135263000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303133363136333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303133363136333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22565446563652463938443832424d4e424158595444304631543239595a335343594353395058514744374d544242475834365656385341564152425044464d4e5643365236574432475a414a5142445a5358454a31474350575433435645423533364338395a47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303343353952314844434e4630222c2274696d657374616d70223a7b22745f6d73223a313631303133353236333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303133383836333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223838435239524b3551323533433550473345414e474257373453304e3246423747594e33533936304e4330384a57343646375947227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22323236364e4a45394741505a32573156413732363031454431374646325341584e51473551414b51504434385656564831543030227d
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

COPY public.prewire (prewire_uuid, type, finished, buf, failed) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, reserve_out_serial_id) FROM stdin;
1	\\x68656d0cef27dd16843418552ed46b1a676a523b3279af5d655519344e94275a59eebd328743366e905139810b21ab9d0d4a5703a9561ce919cc00d78202f304	\\x5d3013a51d23df757bfd817b160494dfefb54f22015d61fc36d59d671193a670	2	0	1610135246000000	1	2
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, rrc_serial) FROM stdin;
1	\\x0ef13aec33dfbfbcf9cb9277798e6926786a7ba2a579796c2748a54b0b7b64b6d7fb6f3463be7825270b15a66d5f4d4f985c816d342576c0fd342a101186180c	\\xd780e5589cc3d5588db9338a84419a111417390be9af5aecb0e24819b34cd5a6	0	10000000	1610740059000000	4	2
2	\\xbe913581dc220f2e86fbb80603ffb16b50278a45a5ff476ac0b4edb62e3daf506c457235efc8c1688bf2ac66e75dd0782e4ec3bf6bb033f9be90be157fab930a	\\xb02c6b07b86826fe0d3a9719d7b2f3e0f6a47a1d3e1905492478bfac22226756	0	10000000	1610740059000000	5	5
3	\\xd8421c894338995420bc853e52dca83a4211f4d04a896f79b382310ed679085ad531b0016ad7a6791b810262886bed992e3bbcf5d6da348b3db13dd174681807	\\xd54eb2e5938f9946ce521ad6c62b2551c5b213db7f0375c15aab353535f11eae	0	10000000	1610740059000000	6	6
4	\\xbd9e2f2f73a9eac1d5fba1d12f0f5e2595c8de4f1f534f991ead67364e9d77a7b178b88d9a2bc0cd78e5603ded5555ef4fac093736605f45ed42b564acb76303	\\x010992584ec77623d12da93977b699444655aa040125f85669e1b852783460c8	0	10000000	1610740059000000	7	3
5	\\xc0741b5425777af9623d246d3eb4044d611070fd979ab8180612c1aa1f46b34bc5bb747df88170cc829361edf64e0ce35b109538d26789eee163f6ceea84d607	\\x6e64a696292ee71986112d2a5887541772afbd9e72e31eaf589807400f5bb656	0	10000000	1610740059000000	8	9
6	\\x2fd9ac68e5c8d2a85daec19592b64dd8c2eb5a7628a2eff3acc5a7af27c53e71c7088f4838bc3ac9c14436b1c4dedff66054108aa79361387cb45ca8e067ad0e	\\xe1db1b80bd15c38f5553a089f10092a9c9c1473bf8279248933e5a9c1db5641b	0	10000000	1610740059000000	9	4
7	\\x86f4f56d25290b78b2033972391bd6c21259599003e415a6de1d8731c1f908dc8c5c72990c84182c40b006bf4c6f77080e57f2a823c0d00c331ae1778d8fb20f	\\xf279e68505321dd192ef4b7661f4cc14b7fef5e2eb6ffedea75b3b28927e19fd	0	10000000	1610740059000000	10	7
8	\\x995d39d0c27f00220d964f13179c6d23dcd318181712c5579bf600bd5529e30cc4bd0cd239541bb38644a18212a804dea72813bcb64bb515cc017b142c9ed60d	\\x84042add45be620ba6e541f95ce2ef9d446e3608f30a362b5236c0129c904fcd	0	10000000	1610740059000000	11	8
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index, old_known_coin_id) FROM stdin;
1	\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	\\x69ee8f781b592c182b4a4baf8a70a1ce9415200eee2f42bf0041cdb6b7f82c5672814e28585a2693c7b498dbf438e3b86c7878247d096620c0ec4e5a71468f0e	5	0	2	3
2	\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	\\x52a365c963e2b14909c92f411955b472bde424ba04b4ca29dfd028f7d11eaad8cf6229da59d19283d98a790651cceb39276dfb5e68a46812c71527c6bd122c00	0	79000000	0	3
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	0	\\xbcbff94f2919013f6d9ac18f8290440d37d451b085d0e15199cb9898bd615614cc028ba140efe9cd776e7ff2083abe58fb93a48076e87d9072f5fb93e4847a09	\\x1c62f05b891963549c6fadf0f4f5af0cecd0b224f86e9c9ddb20b2292b361e5f069533360cf68c6d9598a113174e1369e02f85b57ff5e9cb355ad3ea363a2175b7cc6b5219c355610fe83946cc70db429fc86cc39655ed502d9b01b2ca80ad46a95ba58637d0a4b48866053eda8be1ac67d704e7f5f844633928ce186edaae15	\\x04e719dc12350142d0ed2fb1871bc77f824ab88b22ddc236a0c7ff692dd9c0704e9c4b2688c93ae49b4490fe16471a018e0fffc572a42b461335c96fe084cf89	\\x7bf2294baa492fa776c7b0190f5033ff4cfac4ab5a7a78bec2b7cbb359c67918f9beeb661d21e0327599a4da28aa76142b414392fdb1fe1fe4b7f883de9bff9e774ce9e50fc4b98398e30f791ab8a9ada48ca81fe801f96bacc193030a2992fe7ac7cd6f37988aee36a6216ef8d876c89099f38ed794abb5f876dc26bf12ddc9	1	226
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	1	\\xc87a96fd71c49d729168cd033f923e94732c6323c71a434da15e9675b35b8e9483e333581fd4266170d196e4fed4e6941d9aa613c4e5057b56128fb15c96b409	\\x67c779066bfedc58db926043cf0d669716d4c0dbe6d80e0f13bf86054de62ba50f6bba4324362a75e4c8112ab31ccacb46edf6b75a1791b0ee68e4d79ecf99023c43b1c92159f704a06edbb1c0bae21d4c5b29bee480133e736d49ff85b9548620ee86bdcdf16fe57dadaae81577f44bca1a0c090abac766a5fb68528dba94bd	\\x024df9e513ec4f8a5a797ab37b2bea38d49db7d22caca876f2ec49dc643852e5778d79ada2b5b196372d55055f2844c35d1aa507ea27eff210237438bed8cd81	\\x02b9e688041a6eed49dcb0a2ce69656c62a443f09ec86328b30490adc4648a3323946d7aa22b52542f25526faac556074d40277ac0b33f7cdde836e1068ccef25a55126ae642b2deebc1b504ad67bffe7d9e7fbfd050893840feb630ce19bf1a8d4037e691d3c68063f595410956af71ea264f162437a81d0f7a5c4302da88b6	2	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	2	\\x0025ed3c8af1f9df9fad10506ba76101d80a3114de3cbc22100925785c9deea48774415e075ff25eeaad048578c560ca9dfb431bc869da5f7ffbcb09b341f403	\\x6d158265d0caea64e3c2dd6a9f9058de118f28bdc7ac3dc69c995684da1c9cad24ea7d2180186e8be0e3d15a718eb8a21fdde97e90494ba24afacaa5b224f247988494c721590a8ad2b04b039e7f2008c5c81aaf3409058d329f60e0d423d9190918ee2d6d60d4250f6efc9f65150d860c6b20b2dc5d53ba1d4a5efc8bbb5ee0	\\xef88262dbd1b49bace67e4f3ce10e87407a164c2506b6fa8c81c5d55143799235eb4066c8747c4f7b3a3931e56c3db65f4acc1d71e9d912a87bf15d51ee1fd17	\\xb57235263931f8157e778633b615f583a150aeaeb7d58148732d96e4d1f47d6ac18210d0115b53886b7aa532c2cd49d0dfbd94b8a6b319662d9b54003dc660bd04139226f9223fc2f5aa233bebbf19c7ce9dcd6df21f809e571a2d63ea94f5dde1e09edfd6a8e7540cf6c9cce463520ed3bc7ca325da548c3739de32ad09a20c	3	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	3	\\xb38b8f360807a52cab0f3285dab4626de86aacfcbc77c513eb4e8016c1756e25c8446764ca7b3c6eabbf0b208968633592b06fc287cc8f30974b98c4acb5ee02	\\x9cfa67f6388d8713fa4345a6b2bd0d6ae6c3480ec198165787471d33e43c106198a695ca8309f92e614dc1b10ca985debe6983b37875f53bd0572f38aec4ce1af46f7ba7b0c7ef4952022eb360707579e0f419648e2fe0dca77b853dc632792d99daa5ab920be05b2710460a149c55d2c5b1a8f264d981f2f276a0a675167994	\\xb665ec0955cae1f8cc51101606a556dc220878424852568fc468f9d1a16dec80d4185bd9661f8e699c73ef5899b4f96a8c689627c57e5b5ee8a87641b2c32974	\\xc4a28cea3eb57f942308613416369320e2d2bcf502a7aa12ed6b3323bea21aa2dc8db00016be74b9b35b66405bff8b3b6905e9af85d167fb3a00e08254ca99fdbdcd5a70a648373145674ad194586388ec8cf6a79616a2c50fd34512c2c62484bb1d071cc2fa55c86eb23f235953b88e44afdda6cde9f3eb2eab767a123da8c7	4	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	4	\\xa80919c7542d04be12d1f17e7ecb129a1d27c84fa680de6412f1609b919922aec06c297dba7018853af839dd10d9060962e32416bda2d13b60f4bfad8a2a4906	\\x8820a03c1408c4448ac5f0f7b35f58cc4ef1fa39b7038e6e26e16d3d3a83d0e752fae1149fa908a54839004d5acb171ea2cc32b0d36ddfa6d1266e0f5312cb04f2bf0cc16a5648212cddbe1a1f8c549f81292a538f35bfb8f207b1c65eaf06f89ed7bc7387248cea227ee7571141481c335e2c5b2c0188f31bdf9be62335144f	\\x788e1997c94ce90f86504ba0ffd0e85aaa33db618b938e5442020c259f234414d3f47a8760e78f4ad3d13b39ef38fa271d4811e83cf4d759f87ec76ecc6b8e54	\\x0da84d6d082feb90a00f120e3d8619d7543cdcb10cd23775cf9b4ed2820973184cf0e8215f7fe1dfc6ae502e0ca947d9ae24399224f1d0f46a8bb9814ed5ed2a71e9e837dbe2592e74218b84d3731b23685cfe885435efdd2a0bb6a00403af03d59929bec3715c66a7f3d72fa45b8187e0bfa4fda8fd9f09af41b8a9b407d806	5	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	5	\\x82970afe6e8e72197c484f6062336548bac40b407dc11a8aae4566004dac26f946451a8b3483229222d8b23fa25e1a5613bcc882c159088c8832001c206e8d04	\\x43dd7308e2ab9232757af7d36f8f01135a932b23b940554abde57f3a63382e1f43d84fbf11b914d11487e654aafeaf1368532b104f224ee38848f59280637dfa43c3b0e62131a6de2f88783a70b96b85e923fc2039441182e48718e8a76dccf76b470c4b7946b21c7ffaa06d9f29c9ef6982090716e520606edae305841989f7	\\xd9d2536bd3425add8429e855338b5f579880de18b29fa73c08b23ebb304d48b8d97fd90c1b810f7bc540c4a18b5aabf50dd386439be3f7a3b80b0e9815207b48	\\x367a8ed46fc00b4087f7e32e5e5a356a1fa8b677a6568d44d541c57a0e6ee28cf0b92d91d7f9b06bfb2c7c36410dc3f303fa52404cf365589021772e09bc446dd9d4031ad33321207c5766548c5d746f28d81870a8e55adffa7e6d9bb4e4d55cecff73f0f8267bf318ba190981607478737ab6894d2314d5c9086cf78c259a26	6	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	6	\\xcb819bc01283f3a5bfa01baeef53ad41e52830be14523c5bf87fa7cfb91457ff1eedb960999aac37aae3ce686c8119e27f9d94104c0ba4a277d05c52a802e60e	\\x317a4ef605e35e00d11a08d96489d8505d10e6ba653d33d1b26891c8a4ea40897848e1819abba2324ad0551df9aeccb871cac2b7438a9485e7415cfd547ae0739f623dc57243171769035034c187e9a7ee41d46155f3e92872a08f54d6972b455eec7cfe64c2b22563c33d25b8883fee986986288291ac00c0ff4385940e9f0f	\\xbc51612024df4c4fd39e46f33b312c0f89a8d2c1c30cd24c72e7f1ebdbcf2dc6bff4ba79ca70365903143f855623b5831f41b208f94a6c861d658c77222e4c38	\\x53812a7964ef941dd85a71f0b249ee3f2fd5b42a532100cf723f7cb6bb4386411d2c34e06948e8c60b9cb553f7b9877483d280c86d919b4ef7da8b40c4944af1240765747fe7550e606b825797c4cce0f683f911f5dc97e1892758a10854175800c302b0db21f0cfae716c590b81b4a016f3135dbf6ebc4de0af3b0ca9afdab1	7	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	7	\\x945e83b0a8ccd08b48f5fc3655497b8bb0cb30166cce1f00860afa8da5f134c18e9b40f64d6942a3c04072c08794f9cca614511e2811f86b036ab8f1524da10f	\\x9dcd9b83d2e703d2ce5d97e7bcd2c9dbc79fab9bc0df59b870a2e759a9882280db46919f9acd3bf1bc4a3018a8d75b2836458a16f65661436d625e7df65e7095e520e603afbefd2c77be93a568b30d5e68b4aa36117336de7a4f931e9357415e3b528452d2b6b9a9a0561b8b676fabb9bf1e9058bf0594305bdb7209e561e884	\\x2334b6ef6088d89f3a25d73564547b6309f224920ff117ea32c8ccd3c4c7819c336fa445164ae47a36059502347f0352b91a94ee4e32474d9a2e046f3932a1d9	\\x849ee4866799a52654c9e2bce9052fb846977ad2499b2a89facf233d596857038861e2440563bc38d057e64c734a7418553a922d67dc52d3838d0c0db0c6f9fbb9ab041ca93d9610c29eed4d0136b41c22dae1ff54463c4abb69534a214917f2bff95e6ff3d18d4471bfddfe4f9c01012d131ceac4807871221971334507aefd	8	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	8	\\x1c8cdbcef17ea22b329ee07560201ab81da4d94722120ea176c44e8610432fc58f817fe17afc8309cc7115c20c6de7d45157b0a0fde157a17c305cd584175f0a	\\x79c8cb1b3b7f2914161792d9a59615b48bd82b3ba9bbbff159ae2c2e8c5a7049469654597842d42d5a719ec085409df14ea69e04212e00094c29be84ff985057144bc67e2ce9800604f783883640f41b2ec0a295379d3f97eb3d69a2818a3227b9f77dc628b5daaac1c72ce8edc78aff223169195e1805ffaa0c1eb5498302b9	\\xa0caba2a78997978687e5061ed0c4b522de1a2eca300f60ad4f310434288086ed4a447f2b0ee491f407ec7674d4739de8226ad93f461e1fc09750d15c4d3ea2d	\\x954a22ea448946901b7f69c507e0723b5ca39f98907b24a6c80d92dc094aff0785ee4a1ca7d34f191ca8dee28fa5a33adf9ec5e642fcd52be2de53e286363a618a623d2e164d6e7a4725addd75717f0f7455b15ca6d2996843ed6ab381cb9e6920b075bf9027e14e31cf2a6561fcc44d7c0e7904628f54dc39d97848140d9d42	9	251
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	9	\\xfa081eb606295c79e56df7cfd2224bce959a1d7ddfd60691509d384e9021912d07352fa6e4fa24a8866ab4a7ee2cfb5f33742308be89c641d26330ac59e08d0c	\\x67270c490dce2fcbd9cc6f1a503950b79049cb8cf977f3df79e042ff910a8a7470ed331dbce4f91eacd28e6e924eb0ae117b4b0b8dcc837b8f34839acb8faeb66c2bba01ad028425d30bfa2eeef21cf0b21e1a33e790065cfeb29ba4ee7e8871e853f22c56ef0e7e091f91852b9fd1c3449dd7af7c02e4ab11f3d9fd9edbaf7e	\\x95cb7d24fb283eccb32b8a05fed8413bf286ad218d42243d42d7b3c67e9745d671607988dbabef868a1e07dafa2594b1ededf9044365935f87b3c03f47ec440f	\\x01d5597fc84c108d2f902ffe79bdbe5ebb876b0a33bb19c2fdd6392ea61bca7569e65eba68c3e6bab786b7a64dec4c6b2f4fb68bd28bb17bde1035c95f3f8c75bfbe293c20074d61eb09fd1db917e5cc30c64b5c1b6ef999969a51fbfd72e62356049428ea316db8552b834d007667830e7c0348d964e3d72765f6627606ee54	10	112
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	10	\\x00b7672067b80afe404b135666d262a5906194391b8cd8e63dabf732ee34a09f7b1743fd2fdb7f9f828469706c3676f7f346350fa348c8dc4c5146e02bde5002	\\x0f8c3bde6e5e19fcdbcd40ca0a7028d797c9cd0430dcd2fa74dbd5932f8af566728cb9aa7a19c640d5e647d45313687a4e2706aecaf466de57f7b48ced58907b5688c7027e18b5f8fd9054de729c08e6329bf3d4648257a6f342857899d26d81bf2fdfa41ee65a77ee76488cb8b6f590d027ec9da1320bedbee13933206f51d5	\\x8ed444e29e1b00fc01cef3f890e39417cfb57029eb213d047b0990b082f2bc5a9ff6350aa83ff07cf0a813dabe2eeaadf8d6996572b9b2a942f4c7db60b9440c	\\x0af95b81e93e55e8113b815ccca6b6d3437744f5e923b093e37942414fe637074630fe38323bf6275304f616c45547bf30ed68c6f60e0d85b6da8f9d227fcfcd2ecd8b4f1c05fcc815944f8a94a49e5a15bea9f318043114b1fc34ee9e0a6c3ebcc9eee55099f8a55b48c77e7c4cda8033fbb2afeca7e9a5c2e4e75dc4b2341e	11	112
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	11	\\x556cf584f3832941ce833cb140071cdd5f1fcf949e9fe11c139b12354779fa6256eac8eca87e4fe2f56a3f155a364c211151d8ade336a6c07ea8dbfc4d85960c	\\x2a4d2c5fce55e1f9d6f9d163a49d2594b73762f0c7865863b97d3753c9cb6561537140d2267c55bee322d1e211af7f3f3e3354e9510594aad74ee2409e6257f9d420d160c8194e383741002a8a17d6ed18858ab328f3730eb885fd169a82eaa908f31df85d857b562a76b6ba4a9723a21541464a30fd6964b93c5c0ac8480bc9	\\xd1b56c9ef316c16e92214c2329eaad8f20f96d6b50a0a0921d79d80687d47f902be284c9921ffb61596220997d34510b2776044717413ec6f5da0248a000fbe7	\\xa028104ec9e109002a36d1a0ec010332c81269990e355d53454f020f1fe4188c7129394cfa0bb1e4785526d1b2327e611d3c280692a3cbb7b0507d13c780e75edb640a8ea72a14590ef8acbee38be3076fad98b979f1a18f5c4d6b84f4f51c5ab0dd7c07d6c3fe684ae6f3b9386bd6a6727ca5e16b1369c0d5f923510d82e7a0	12	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	0	\\x4e737c56ac7c7b9a35489023d56a908b011cbaef4c674e8ae8a99acb40f0ae95e71bfd3738759e6e0fb11d2a8cbe36e4db11095cf67a7cf80db492c894b60702	\\x8099fe2b744ca07fadbc68c55a7b7c7a1f201abb00d6ce9a47d68bf7508738baa8ce15b6c8165f953f69633e84783399a306d056fd1fba14539e1513b82d6d0ab264062ac5768b7b9c05977087614495221e7deac2f56702f50a68a5e6db4c98e26cc3748317ffb19f89154741ae42c5e2cd1e2054ab746c5856fb0652862941	\\x99d1255d2119075d901d725314aeadaf9273c57c26c8896b0a5c3757c32ad375f1e102e84a03773e9eb1b1932e2bd1f3e16c96dc35db6e1c2d31e8364626fb7b	\\x6755842b957c607189e6f6dd645be09436b6ed622a8b27bbfc5eeeafddb52cd27a459ec12f1105d205357f5ce656a2325a7820d37764aa83d1a1aec86da7063fe0e4ae74ec46288493eaf396c1f444cf04d93edd9adc0f455bcc03ca531b8a6dd1400c7ad81c05832feb7dcf546392bb7880bde36eabb97d71fae92140fb710b	13	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	1	\\x06141fd83808eea5c11beba53d805b7f2658705ec4d0b22a841c05728580eba5054d5fb8db878d3a9918d6414aee9abdeee9d43186d38ac9310b370de9c06304	\\x95247a5d2c4964ce10a9e652d5108ab5ccab3ec21d0ea98133dde47349dd65b005eb6380cf76cafb88dc22ab02ca4401c12c8e30a67152811e38aa4efa9c68a826264cd48b5d0bea4d5dda7df8cddc543e18366db1ae87dae668c99ff747a9afb6fd4317b2f2bab0001c99c46e48a51114ea11d9f8f0880518d23f46ffad157f	\\x285454b2bc475bd4c0fea24b868dd80abfa85dde02df21f4f5b38838f7c53f464cab5b6c0885a7fa03a91d1a17d528b646661f038f35cab74b352e90fe4821ca	\\x1a7167362a5080f4df2345fc5fd9d01397a3f41db387f360e157f0fe950cb8c48e2b0ccf8c8ef1ede7ea25f999239ba2751a0f335a4bc2f0dc60ff08d91e059b438f1ac335c113ed078f2873795faca5aef616e55db7304708eb4d53cdc8cbe4cc1526b8af83e3d7806f279b429bde17afcfc3bdbddee765a6b8e1fc5f31ec22	14	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	2	\\x99e610df9c13081d9a081935a021bf0c770bf1eb66e10b865c25e1adaed90521f62bb2e830e0dbd288e5e7c240cf96ecd464e3de888230a09bafc1110ed66c00	\\x52bba35cfbf8fbf382778c6c95e138d7c9e84d649198001278c805246ed141d90157a69fa1ad1a47c848805bd44aea364f06838f4b059dbf6b0192e47afec9a31824d32d1936260e8d3d55812a3fedd2b4c1ae40de46dd3dcd5298d45cbf1759e788a4256bebe68339795416ad8e02c286bc6aba6c49873cef31e1853e9710f2	\\xd4fa1dc37b844f4eda8fdca485ed1bab97b381e2c164b9efc1d15c600e2191089d9e5dae45edecc889da5b576063f862e2eea69fcc3e44768ad6f9b6001a21d7	\\x7ee936ff6e1d7c983722a7e182f4c8a06ce0c8f436fa79574bedde0163f473271a6486160ea3c44642e9ed690cfe63b965f0304968b715d742263e4e05c3c209f1e24a385c47af4ef71195727a037e68643f610f3003e0f2cb547f00c30a613717034b67dc805c4cf9f21840bdb5bac4ef3e88d4da42cb20709ba960411d7c96	15	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	3	\\xf5c791e4ddc66b68f3bb8499aae92936103d02b67f97e2347ffc65c4ff5da3ae44fae40f92a6e90991f298c186aa105a5ff17e5a1f51fff1d3a51b8267d95c05	\\x2c82f4e6a5d44e68821253da36573c28ab53fcb5baf91cb176ec3b862ea0b824dbe20f9dc03cc947a708defb7982a832cca24dee23f7c0e468ebcac8565b74352b04d5063326f655a1508795f308ec1c1947b7b1debe5b01e391b041139ce89af1a71765ab61d5ed1b58dae0701b8a10d6311352f24c0a585b7d05e03b844cc5	\\x003c3448a6924209ec9dc9d6a20614ef6fe6569f3797ad6dd0c4ec6556561deb3e3deabbbcba7cf42236ecde685e60664a2dacb7082e8769925430a7a0b72ab3	\\x23a427c065e2426d0b983df3c7bf92f82cf7f66080afe49c47433c9393a42fba0c6374956e1c091c4423e7f3474842f1716aac73465fed860f0ca997020f2f7fa92857eacdda9ddf41485681336b8d0ebe442a1b7a950429e495f69f044b4df647f254742588bd9c5b0311c2440de2e007bb3baeb1b06595ac912d8e33195425	16	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	4	\\x30063faf8625cebc52513d4406f00f89f52bf44e8d75487b4b6be165199483ab69c3373331e17ca6d3bd77fb2ab79b1dd5e3ed22ae81509ce2f8504e21b6ee0d	\\x803aab64bf32936acbb563ca1da818a0571fd3c0a5b7dc84f944759c80915ee6fff098d2b23495b67383977c7329354bc195271d3de287727e634de9e7f66348842929f6a66c2bac9e96655b33e81c555fbff508fd58f26e1490feaf5185760a3b90845a8340cb97a4679e6499a66b2eaef0affa13ffe4af30d5dd2f1e6b299c	\\x7754497e6a956949cd6ec37cc47cfbacac87053200d330451ba4a9a250b8f44da7b7592b8b702024fe233fcc5438cd3a5b879cd7981a24537d87e96fea24d990	\\x51956d8874719844bc1f740ff116f3808b65d2ffe8e90155a231ae11e411e4d890c09ca2bc23b2b7202c7379f029515c0d2df9b8d87394fa990b6a398bbeb44d8c1906dc786d431e4e46a31f343fb77bce35950297294b0636ed2927a7df7b7ba692c8833bbda38afe526ed7b8ac37127880ce4d3e483b50b5919023c3b4cfa8	17	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	5	\\x0401580c047b2ac812e0898e3d5b2efeb6e0848b9a2ddafa273da355bdd92dbdc0a7a4fc4e4ca8f82659d483390b777d682354400f565e50e7c5a005d5abb407	\\x586a6cde067bb0217682c65e117306878368ba6ee1cd7906a0a50c0cd44118bd146ba051631b353a7d2939578fa7e9f172123251b286848d462708d9c992e22fa45892052f0d9036b7dfa6e9f45bd546ec1d20c9f575bb59807bcf247be795aa6fc21d9316865bdc52a63a3de84c921e1b6ba799c603b9f808421434e736370d	\\x9a502209decf8c1a2c2df322216694e79ca3e120be0f49319eb2ca8d05c77e274fa72a926c3a1c2f1b1bfc0f8d90be43add39f761f5191f492f4568d24d77b70	\\x2eefcae05822f3e5bccf97040d1992294fe520f3ea4b81f2fbed96fd0d3060c989034f394d56e0ccdefe1d1878e742c759eb86d479ee2f417389c649c11c270be2d5011ae0c60b31f895a7101d03abb45b46247ae47a6b71c5b364567bf4768fd71a9408f7614db9632a0d3c8c24bf17701b371c035d839d8f9ad4bd0b9981b4	18	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	6	\\xff39a4491df545d5963798994aae537048bf873318c8d505abb79097b1a07a88e9f616fab1a34a58f4889cde625a6ac35f4ffedae62da6ee2293f2341933c202	\\x43f62aceaa82e02740361048fcfbdd0196c28743c01183f0aa6bc3b7f1f3f46e8ccd4ead2e3b6183057f963178597bedf400a3df1cd53fafafe244087bcdf6f1b6f1ad352e3f4c5563cbb5892254eab300ae2bcf2a313877189991cd7aef6bdba528e40b95b9979226ee2b38788907b4d4b9ddf7f7252c0345d73fa75a6cb2b1	\\x253c14b47cdaeaa812fe0939a6efc3688037056106ec9575cb29d9cd2a4b9b02d8a4dc24527d5d289c3824c29016eb7afbdb7c0a76fbc5a5b315bacdebd4c1c9	\\x1c469f96be0ef41574f1359ef7db4b841872d22def560adac289799fa80dd4d8fe35fe3a327209e33800f105de446b2765d7c25611b9548e914f4220ed3418b5f2a17c995baea5781675dae1f93fe29ed650820a5776cc11602c043848ca86174578f4e16da861735fb4bcea3c865da77e6d73539fae719f08e56bc1d00df8eb	19	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	7	\\x83e1a44b6d3cc94d91fa93a729f84d0507547c1c4cd09b90721bba03dbdd80c1b22526a63c22cba3c557c8e93a9ca612aa65585a20bb85183507ba812948d30a	\\x24fec6107e058447de32089f90c2204101ae69c5aa6f25c405cef7b7c89094c60ece23879d417ce8df50823626a163c8c6457db58b5e4d57682f670f65a0a7746024d60d5e566114eeac2b1655343e80f64cc8a5f1ce6f9b6f9303b01aff298c2048fcaf926de96c40b26883c24cd9ad3378287ecd129c7be33bc5c77e0c102a	\\xe75e303707931a5866857ad9f1b26d6ac3e65a7ceb57a8e0f00843ccca66f7ddd7bd9130f350ba718659c88b0c363f72bf9e6c0900ec7e4dafc30ff7b074fccf	\\x6dfec4176ad189e011c09bc63ab43e8cfa2d12bf9290ff8aed24b477e7c15b16e0a78463fb52a00865e825138b262ab2d1f1225446693c0fc3f5a6545756f9ca73ea7f8a89546a035e7c86ea07fa0f973dc391bb6a0070a12b3a0643b417e0c479b73a28b39c354c92b6bb0b31bc130403d979244a81b989cce3f2f144e87caf	20	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	8	\\x590a92433b52a5f73e12bec3db01a8d62b33306cb590b8db1f8d97712dafb179269b17695e2b09e1592bb55ad87c79dda9b818881667b98ae1527b2182549d02	\\x4ba4ac9019df4a5b6ed448decac959abf7a08a71dfc969f14c047f4da4d44365f05e8128b9ebca34b490829d7962d47af9341443e5a0d26cbb327e209076341a93e60b9aef8062da58bc527e3ca76d1116f99a7cdc60f0052f826838101b6403430b39824ec5cc2a755bea45b0a10208d352fe2765fd0292e7643e5352501b5e	\\x025c07dacf5a098ac99a507956dac9e79bb5d1d8621228a295085fee4fd51e4ce0ea03d89901bd06a5bbae1c74624d5c2e82b8fbd32445ddd2e2f47b0a0118f8	\\x33703f602de21a92403fe055d58a9761cc9551dd8ec82626afbcf72e3efd09c9ffd350e0fba5dc18bbeb353150805fe9a2b54cf9e3af0d5269dec209a3f7cfd8974eceaac57e7e7e2cdadc54d23b1819a19834663be40219bfeb4487dcc3c17afc4224d41b3131222d28039c0a6262b1d7c7e6c4e30109dfd8efe5827c3fcaa0	21	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	9	\\x708e06ff2bd7f272f6eb211a119332f21a4d285743f0ac3286aef5186a64b366d778b13b1305b6c6963fd94fd67034d898bb140a3e0ebf5289c32d63ddacda08	\\x55a6c2aba7789678f539e1d23f8b7c56de11259741e964317b0f690cd9c91bc4d1b821bfabb24a73e140bbb1ed3052ba8269cfe601f9ec5ddc60704ff2f32af52a989997d54ef7aacab771894a377228555c972b54dbaf9240f642bbdeed9a4cb841868280b153f1a4242f801f64b9e5cf6f79534767a80eda9e14d8715b454d	\\x79e306ae506e709095a76949c6884f8c27d26f2c6ea4f65aea98073277345a8fc04647a884b923797481d2cf7eb4468d30dd53e1e38a0aab8259face7c95ce99	\\x212d381390add51e0dd33874c3c058ac36f09f72fa7bd8b986834a84f52f5e035e5abb4d1df20fb18f1077945528e0ea63799c4b2c082f6fc1651930cd081746145d760d7903e49191ea0ce84ccb18dfaafcc3a00bd8ca492168a629714f22c5b74194c924f29b3782d42ad28c9de228f23cd4f4b25b21b6236a4ffbe3232d13	22	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	10	\\x0832fb6cd621ecbfe005246d77a7770c70b0286914e6f31feee3de78c4074e5d97b6f8e6fb9f19b1c3f69822e91157926906b35bb73af28ab40b39cd1c38320b	\\x014e4635cefd1ca1a0aebb36fb5d7a541d96bfc57891a12de8cc1f2b56dcffc222962b966ab8225cd2a8d85c34d948c5a0725957a4d6deddff11e111c90abdf6d2525406a6b4d709d2551b2fc9f034e0d0624014c9ce1f91d89e9425d3087367e4b7e0703b4c0e727bc05748571548d4b28c0250a9d854e2fbcf6ce668da236d	\\xc8b88f06029c9e70bfe87edd1ea79a5bf2a3523cc5610aa3fbe5a5843c78bc793fc64fa0db6246e878ca7f6ae688fd8d5b817bd3a4e512a6d8c1753de4ea735c	\\x2e7faa7e12c1d964f4ad8626a496a3d29b0fc2e1d6a37544900de8e11dc8b7b64adb95246602dbaf8ad55b2ff61b47d554fd859ebc42c82e9e79700c2281048b1aa6c2f37dddfec149a7e427e0b2a9d3cd5502b06d516664c8a78deaf9891e2eb9ff737ba9f59667cd311e6003f3dd2d84b1986e01e673f45e2c5b7a02080780	23	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	11	\\x3afd47edbfa658b09facdb5ebe96056a1e76b58991ffc17d5f50df1d4bb5b0f6d0849b3ab7b5f8cdc82386bcdb8b3ce836c871912773b3c81d5d2aefba348b00	\\x76716481f941f688b2eb09f80375fe47beed8a7a43ab9df29133132e0c83b6d6c66ae5504ffec0eee278a6c0e9d2f3d547ad7f793e117e7412140fe722c669058d15813b43ca1d68bb7460ef339e9066b2af49bf5c3781d2f5cd64e392548bdae6431a7a06cc42175a395b2386bd176f6a1f26ca1af07b77b4c17e53331702b9	\\xdf71baf2ff3fa1637ca9b7b7c4b5a610ea7d0a0672391db4ae45276488b15e7085615d3ab0ed8c7ac05db48f4aaffc5db9e6e03f53a233bafe401c3ddc34501a	\\x09329a769748e6aac7a444c2e5dbe30a6520c9f99a7bc02fab4460da38a1e4fa0d974d5c5a490c5f1181ac8be5655c983b39f4ccdc425d65ee370c2d41202daea5a7eb5c7a44f98c2ffc36c8145c7ebe59d41825ed2fcdd836e96c3aff4da73988c521b843cf2f57a9ec63d61bf05e3ad77862adc60744c93ad19bffe246cd2f	24	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	12	\\x7cc22e7dbf62120067cc76127ef3800a35695f737e965cca2ba2bab2d43c79550e1259365a7ca56f4fd9bbc1cea8dadfdc78c92ec6980260ad3bdde4f78a6c05	\\x4f667f79f1c13ef49ec6a0adb3354406ea62aa09c5907cae4943eaa99957c40ec3e1c885aa6e0ce2eefd9ab536a4eaacb744fef2b4c780bd7328783716f11b07c8b941c7147cd1c623262e7e752866a7584dffbb70ef12ec2360e5b78d03a1ce73d5a995a72e1e9cb3c1a9cfe45e8e2fe546f4f8fcfdb088fc8166f8dbb684d8	\\xb03a8b3dc838149fd2e28fb64980f4e8a7dba30f8d743f724b4f4b8323dd50a6910808b516a8b3a53218d001e2191624ad8e3550f1881c2fa9f5f343e8fa4e58	\\x4586e6541608407e38a258e11b2b2a7ae03e7dae2a7de3a47612c44b91725b87a50a37b506ab30c8c26c937b39853ff710fdbae570c7daabdabe32022ad5861ba7ff7f22bad3d02fd8995fa828afcd151a36880d18803fc95e94d4a2098ebaa9396436888c4de35e87dff2c0e346efd19038067c4334af39d9a0f045c0e60341	25	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	13	\\x25c023e47df22ac328dcf1875c37e51a9f34576900c26dd8d604daaffa2c3fe734725e8037f24f7be25d565423447d6bac4bb226826215dcdef1fa2eac3fc700	\\x28085927e08075203f159e7974aef0a6c21437427e10d83ec4bf93db27d4023240077d86ece79f2328bd4a35bfa28bfe17f3a2913b9d5d04382c18d1b9a8e729cff3fb88fd12955e6b5fc4216f38c9ac300baa5aa432b07bec906261b5020258a4c7fa81adfdfa48282f265f60b830d9a792c6575104cadfa32707ce83490c2c	\\x2268970fb9270c0b46ac539e00d23242641a35163a0528a6e6cdb879d9108360def27254f0f1e9e69ab8fafcfb60f9f7ba283c948194239ffcad5a9446aa2cff	\\x3953fd5853030fe119d2c1c9431c537810879ee2093584645c4b97b6750f782de3b1c8eff4a7633507813d047db5737f5e410fe4713d06d09d0e1a7a1fba0f31f1961a9cc98222feb7342c7e9c7e7bb358b86c1d8a3833e839e9e6a01d7332e2105df01c703ae4c414b19230bf92d5c01665e1f556177f9c3b51b7bcb75122d6	26	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	14	\\x747f0c7327e9ca376b6bc17f04953406b07c0b5ff08814f49b63ef586a4de3a142019b258b1058d8d84ec23b210a31073a7c25fd627046c1320fa75cd42cce07	\\x71f79d8847008ef54094c67496b50e0dbf0c87d089335fbb7636505441cb3c7cc217fd6470b728e397ac5a5923af2fb805881e299f746e1e852b2fd599c724750685f07e365aa530feb91910a2678bedfb0c199e8475487d87a56a26fafe1c458efa9cd9d9cd07f24d9279be524bb37ae24ff744f402ec31b6277107bba1e784	\\x3f01febf0992686dbedc4ebd64a0cbc180251f8926f033625b0df6ca404b23b30b7369049a4d12acb369949a23c7b317fecaffd5a7b8e808de960be834154551	\\x0cb074af0fa92f961a9036ce0984338c3eca3298ff71ee3fd78629afa422f71dd0b3e7254a98bf7ce7f4b8f68c8887976a5e7983a04f27b5a97b7bc04b0daeba3866781db2fed84bd9f44b5b1599fec031b3789ae8b67318969d238ab499972b437822905796a98137043cc575fa8bd035a893ef23b10ac284a221ca9400a9ea	27	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	15	\\xf86518681301f1ae2b60677d7f0db359a65f4e10a11a4c982289c1b8a0878a7e07011a4219976989fce6a718eec1f2cd321a1b4c9a17002390d6ecdf5ef9250e	\\x2a1e2447bebecfce864e35e251e5394f006f2fc87ac259315b5d6ddeab68d7c280b0217dabbf79bf8e7a3fbed9d303ab20257a4ecb55ce6b65048b0cf1ed6beb1ae612d5e808ba867216c447a24684e51e328b824869d70abf69226c71c9314700274e440cef9e6d76f71ed3a6d7e6f8cc48aac72d84a81cada1815a263f96da	\\xd525a19b4c1fbd8523fc30da5b3db41a452a2d04b34cbf119ef93667796e613d894fca0d39fe665bd211e0f066289a5a7e686ffab9005175b1ff81dbf67058bb	\\x338fddc0fb00f4121b5b88bcb7fbf8ca0e22d365b9c14aa00c0cf43b1b8a04c24c37c52b3bfb0628e147dbb3a5b5cc62d1e93f3410afdb52fdb852658f48c18e5307728f9e52f5eb7a426a4df5f8125fca8aee25a1885aad868f9bf10dedf6531f21a4d9a62325379349f8cfc0ef81dcdf8a6a0d7220ba52f8e18d3d994bf4a2	28	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	16	\\x34a53728c074ec9ff36b5456bd3d2c0eb4e8f929d9cb7ad00c0fd1a9181295d61e76ff8361820a4fddf63a63cdd5011abdc40591b5ed6431258b63af0c715f01	\\x6f0f52af46f4c83eed1094c06e156c696b24a9c46dc8782debcf238024e0e085f1e8cddc1814905782b02d6a1c4c30c99c18a5a63f8cd74e7bb0d389a9659c22218902e2737e427cce63019ba7b0bfc06d6262a31a5a52bb284ae14075a66d8b05e16a108645dc3c866488aeb74029d8716216db837240bb028e39d3128146db	\\x0f6be61a31d6ee739d6e609b43033140a87b3b5f4e637868d6fb3a2babfe08028ed287c96005e060f449b86daa71dc2d7cb29e5cf9061fb74b5fdc4311d95a77	\\x0f072fcb55efef28f469d2a8d02243ff8546ed63056053f438bcf2bf8c700191e947377549a868d7c10a29da5d2287aeab8aa4b55e9015d0005b9c239750a6d6e4631adece622e7a8f1762824646a8ce766615bb6f9446e5e0584017e15c26230f35e29b6cdf95165c46efbe51fe54e0b3176b175dfed47203edcfaecaed0b24	29	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	17	\\x7038af877cb72f5495f62ec5c0443e2bc721aded5cb0aa1535a8704d560f5e7b5a924f93b2f3290077033e110ef24097adeca085d513940e1b868554a5bbbb02	\\x843b53137e40ef52e15e75c4f56ad4b5aa00cc7d014481fccd4f49177e1a49d0cc8231214bbd259d2bd73cff03a04651417af9a76be4cd4ca29394fead07b74cabdeace95b894cda52a7ae344354194a09ce87061df2956e9d425eadc8a599912e755923d364b6410dd53d36799713ea6c3bd46251a8272346e9008421f84e5c	\\xd89f297089e63846cae162e0163491afb83b51bed3f1251760f069f795651d23517fd566b98738fd3f7d1d82e21a096b295a06e4ebf9230c9629f6b289e3c7ba	\\x4c6a3f1705ff8a6fc6a7b0d395ca8f1542645f321e8aa699089fdec6c696f6a995681595f1d503c8e0f31b11fd7b371c01b29dadff141d7385be8e4057d5929fbcb72de2341d7a2406c42aa715468de5adce097c07348705bdcbf0635a3cce0b9d72b4ceb5b706d264ef278a8903777f852d739698c15b72cd75e8e9d023fca8	30	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	18	\\x2180882caf3f345c6466e1d7829fcca7b3cde6e2ffc4aea6d1e41388aed42257c1c32950193339b05451f1079099bcec237c1dab31dffaa912f07119468b0703	\\x723d16d4748aa2cdf63690dab65a35f07a4987d5227e83693d7de67f57dc255b22e445c36fa8edb36fe86fe01e3dd757fefdd5544b0cb57013c55d1831b297de0c4e5706d327e801ac40dace3fab2c49083ff8525e42a6532b4160136b7ec409f2ee39b68d9e1fecae83290fe1c2a4b28b8930a1bcc8bcb257d3c8470f120132	\\xb11c2d46a2dea38c19c672dbc5acd01ad7d1da9abecd4838a2195c7db896ced42fddcbda935038e4a620abeb7c8ed97ed74accb3335022a11c1b68937da185fa	\\x0c62f364dead42b3af4ea6bb5e51ee8640ad6d770348a05c0fa70dbb5d2e3f8b1027ed3d5e5b213155a592d43605499dfb2b074fad4b88cba23fc470fc116421af19a8cec0e77381c6e756a89441219f8c66fe8c3e50940a6fc4bf6594258628fe52f10312c47f8406a89f7c3cca6496adbb0256565be9518152332ebc52163a	31	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	19	\\x3050bae728057f953f42136c44bb13c2ed72ea008cf970439228e15c58517c54964059909c3c63b50fcd3bb2938567b9bf00e07c19b1ef3de053886e34463f0c	\\x7077b9b3f29554044832bbd39631ec30fb3d4e7799a932bc3073b16a2799eb5c1075fa3357e70b80468faa77e09c44e775d11ae8208b470c2df053a9e014fc3eb0d789a47ad174511b9fe1baf20f6a2a448c4d32743c7ae67f70e7f31f4f3f2c4f280c31a25e37122774a056da8c255ccb65ffc3bf41a7c754f14f422522abef	\\xe4c241aabe16b1d72efa1dcf88712b28caa35750b5e7363fb1c39e283fc1ec0a1e136480df2a1ba37857671dc56d4bab785364056c5725bb91d917d9dd26b401	\\x4d0c8211bf95c0dc6fa2cb7d6bbea25e663f6988a3865b321262224d745197bc76e963f85b4cfbe062eed4205b6e106f2945db5bb9489e732077f67dfbf0d0ed6af9d02bb22475552d7d56f5ac383335c2f4a7e1bbb3f32d4c3960e108fdcc8a61ae76ebc73a6d0318e1e64cdb8a339f9337fd3beedbbd3744f90dda87b54bca	32	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	20	\\xef399cb3d473468769c2c413ce207c36a7b76a5d9cfa5f2b5c04467067205275d2591ded313d1a79b7cd82356d7a8480b355217cdc6f11ad1082f2f041f55d09	\\x4d7f9b7c13c7e3e4f2b4ad9e9871089e1db4319a90590c58412b733db912db7313dd7c09c476f06c7c1c37f82ea1675805bcfc52dbbebe958109cb26828ebb0506c208e57d7d127e8cea080924b913d45150e221f91d7fa301ec3fbf5eba24aa045b4261a92b93e99d695d81387df6ab924eb81d9d71cbc355394d4e5bb03737	\\x62aeec57a510eb1fc3c7b9c762f525db338d73dcdd39a1f25283177576a94a55079828af6c21ae04915399efc1bbc816e2600b62e7076874998757a174351918	\\x8ad27fb62559bca96b0d23fb999322ec91cc36c481871c2d03b2e992b68005f5dd94bd922b003e22208f22b22a1f41683586188648d1571a27e8ea7b91cd29be83dc531078095c9c6db2cea3cc3d78b517174b0d6a158dd07abbb919d3ba24d6a7f145489b1fbf77f81bb0afed100557d95fffd5ddbeb9388775438caa0bd76e	33	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	21	\\x9252db259971527c720791ad931d9a1ac205c0c8263aebb665c1dbad5635bd1c238f0ad9b752b13dfc23d323a0e7523160be9dd9afd4ca9115288b051e4cc604	\\x557cf79b84d263133ccf6e7c0bee61adf58a20d9466386c33f1fd74513e22ab45f8338054d08e6ce5a4238ac61b940abad95343fb86151d87010c5eecc665ee8d2f43909b286e4e9f78b374b608c04184a7a004b797ef6c370ab63737ac145890bc784da7546e80030c16d03f7fcd2818c5c8294d1e3ea24fc711a809cf5b7ad	\\x85fe20127ae856d34c641ce630356089755089ed9254253896628f4b234fde531c57edeb28a8c8323310b783ae6adfb8a99bc4ffa954a9c98e73c1e25f811bb1	\\x74e07ef5233185e853724345d2965070f7a78a603133280c2866f533fecce445f3372cff6bfc3e02daf7284ecffe93ff678cce5e829525cb1a68561378169c6e1930ffb5f5027b91b49bad97def48183093da79ea830a1c68a10090e665f7181e45b90531c9ec493b5fa439939b1b2a4e5abe214af73139cecf1cbe4b3cb84aa	34	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	22	\\x88df48785feee8f82a772906f9b3902aa0855f788388e067b119108208d009e0694fc07bb3893292e8bd518f0da7748266afde862c116715675d27d227491806	\\x595ee6aaca299f55a0c692c9efbec883f37b3838cd3e869b2ae7a12c65a49e2e47a2c966044071eff7aa128e30c9c069e0c0b315a40e1976ddd6f2bd948b3f00bdd095ec46467f41743d9ca2a054bea3d51ff844f313f16b12be1d81354554e388d1018b2ab3095dc1470a3a14316aed8259acff4ba4fa1bb19e3c7aa68a55be	\\xbeb33dea010cc69c57827ec98572c9a1d3f2996edf96c414803d4af315b45e18ed76dc0e267b5e16cbb2316f28bbc9668bbfe0a550b9cac8e8ce1c7af9f45f27	\\x1bfa7424d6f73bb147a6690c5553274cd44e97235fe9949afda006c89abbb4c71c1f65842b8bbfde004176a8195723e478ec198be1b591b9ee003001966e8b17861402e9e5582e54c3a43b3f9384bccf26c46c8e2ed75e27ac6cae24fadd3d561f79a54d6fe88074ee6a47acbb70911639b7dd8dded2361a38fd05c6987f5bca	35	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	23	\\x4a15412580507bf37d1245bb7e4839995c15ca1433534e30844491e69412fadbf79791e2a3849f05c1f828c052d418858e3f0cbe57b4188b37d36ea6304a4008	\\x74229bdbf45cc3a5f2af1245fa61cd1ac6385a9b3c30c2fced10cb555c19a3290547a715c5d728f591ba4dda4da45997c7e112ad7c53c4f88ac50569ecec0f1abfd521be30c0b3e1b2e18e794492b7945e62567ddcef9280d1fb6386c84437a3dd3f536eca3f4ae88f5ebfa1c90e2e8720471235fb9470db07355b60f73db609	\\xa6a7829fc7d2db957a2441c713660da16befa2aeb38d4d9cd96c22009d0fb1f888ce41e608fb80ee58bcc4cb138cb446a49494eac8b9a0354a6d49cb00600e1a	\\x9034fe90058925c3df409d2f746bf4e778a74c099dfeb588281b864b049a526fc5c6f90f13908648967858c7a9702f645ec78a5183998f8b3410a546226aa8eedd45cf5d2db4c799ba81d7803f03ee1662aea88db92ab9f98fb135efc28b11500d568eadac305bcd7a03d26d5584e5368ce5898c72872fff33357e4fce6e4192	36	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	24	\\x129edf1a22ee11785aaa66c8c6b45393e9f96f9cf6d9bde64e361c4a04e2b6b1759e4536d4a049bc7e177226c8cbf471cbe49887f2caa25e9f63883ecc20f005	\\x37d1bbc43b741866af43b4821bad39ed81bb3e85dacb6ed6aa6f87dbc8ddc8bac6af405c9a53dfde56aa9384f5193ab838d30d48b75b3c523e76250c7e9dd3e3f3282a3259d8a1afcc15d61f7cc8c81338bc0f91944416726edfc970f64c4d5107dea519b13e94730e6d6977916204fb3e16ced3424db18e39cc4204625adbe2	\\x1a8f9daa8cc5c50610aba34067c901ec071b76822e9bf9025ef12acf7909222a794afef29e103bf0e6d4c00cc969ab3f49d2a58e67bd6864bc4534ebe04914cf	\\x0cec98f423d380e44c1dfc646d8364b99b55f34c2aa896e27c028453368d6f2061af37a68d88fdd8cab98e99ee1d672331ca0067d42c657a0ed97832b3ab593439cfb466ad6d338d96ecfb09dc46306a7d39861b397e41c43605fb4e5b23cac4f0e080fc46e19f166955acc6d182e33b2447d68f1f8f5e4fd72f1e1d63867b9c	37	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	25	\\x9d81d450fbb0f27b9cf0b8e9d30e9ae214938b460a3302736ad1ec4b18759966ad5f8d12da71a14de9b783c6642805557da8a991d1d7b7fc829df156badc5b00	\\x971672deee1428634547531a74c8ed2371ef27bf1bd0eee2a418bdf81feeaffd6c11807afe6cd3b0b3f854ad864b89c067cfb8432ddfeaada4fb14ff95435ab92f71f28ee98b33945a88e1463bfa5de12e7c76cbac0d5f3e11d4cbbd2147e33b26bac2796dda5eded03393c99e26128537374924adc8fb8a3a9172a16c742164	\\x62c3a392e7c19d951df1faedddeb11c1e1abfefeda8fd0bbb018631308a623e2e2d2cca410106d300c45680a71cc71aad2e0fca451df4348e1a757085e93b3e7	\\x02f0b473c07e8bbb1e5aa59f7749c6ec083f5b49c2bc040d64555a5513368659c1ede036d01557bbd6631f498b04ac5467321933b03a56e114831206fe320474a24022520dc6bfdaada381650414f4f0c61213bec5b810e6489edc8a382f670a10982f8a3bbbc3bad621e40a177183a307b90a0fbcb29a355b63675b6a4b68c9	38	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	26	\\x2b7ee90cacd4e6c6dcd0b1b88dc6124fde6c708971ccc3672a57646d17fc12c788d74b3dea3d2b321eb2c01361c88d3a0a0649c74038b976cdb2179b8ba85508	\\x830d7da3da919eb28dd91a842c88fe9d6afb71559a910e39e4d6b37a162b6b660779e6bc702580cca47d8ad640c87d52e5e64e5ebae33984a8e7ffd1a824400ae51f9eec9995ac5f41dab52ba46212140bfa474c2750a687065a8805930469760f77aa6fe7919e45dc859345abdfddcbf58fcfbabb6ccd0a00ca9f7d41395174	\\x57108315bfc50bdfb457a4edf245bc293ec0ebacf2c56414112d322ef77a5c8162c167b269fdbfe7b62a7e1746f454a8bd56ad361f3fde0cceabbbdfaef4cb58	\\x6f079441e80ee874d0205b170430648ad15635bd38c8f619b624ccbe1a752ff4b6ac0966c90600f9a67b3c278849c2353dcd199623a39474ec62af99ad04de11469b219d63fc5b4459defe812b53a75d8a9906bc8651adae9a0ec861edb0ad96feea48593b08358998cb60388ff3adf02382d04ad408e18a7e238b5964daf25a	39	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	27	\\xdf17e89248f40243e04262c9346d2448f4053d57a80a4af02143078ef87ca2ee393a55e39697f8ca9048ad0b2a37360ac9e2f05af1f882901aed0cd7f6640b0c	\\x8138e28d3e032dc626fa9d4784d35445e29615c65804e59e77a805a4cf66164182034506f668b6c0f60a07d823d81a64c7c996f11b6286a8eea3de2d57fbcca0be7965e411b950cb1c89ffecce7e9744fa2dbc39ab65ba19348863faae23bbc5d0468609583e92ab1bd82695f45e5de34850ab1de8216ca956a504af5c233536	\\x346874106f127992cf641180b2d21f7d90240ae25fc656824132aa7eb1e7441aac51e89122c67a46e25f2c12b598c06aa8c4d446cb21735f9eebc4c7e585cab1	\\x183119003922d5d767a9319ba93e3c30e6776eb06e3c450606b4568b94a25b1a56d84ee7e0d2834dcc3a81a313d3ee73a5837c387992884adb620386d719aecf41913b27c42cea2ab2226660c0b71003762c161bb58ec3fa4fbd2be5c58c57e9d00b97cab35c63715397d9196c119b2639b35ef4102dd2f18ed765e3c3d50288	40	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	28	\\x1947e26ee3a9bb2c7e57010f04b35cfc3d1248beb282114d2fa074e072aada69630828b48b606501cdc6681c608bc1f82f6186370922f69e0545ad54580c9903	\\x5bc964b25020eee49be5003b2523bc222d2a9ec6a0dfa2c00fc6463d5b4bea3b77697aa0b21a1c09f87064b730237e5bf92ac83862c916d2d06efd7bccf9f2324be6097602c75703d99aa66fd54f6bde00e5caacf58a4cf84da1ff0db7337601593dbb8e0a1ad4b414f3e0acf452597575a758379e004ab5bed508f5f5269172	\\x7c6b437b6e807167931793b8545e771369b2c81fefb09544784d7ff41d717eb51a9a8aa6cba952f472c27d08fdd2706f5263295ba7b6a6f36c5a1b8448706e75	\\x0aa04574cbf57a5cb2eb8707354e90117d187072e3b0b195143688a7239e11b108705f2fdfc1a1b4c2acecdcb12e1de9c8526f4fb83b6eb4fc6116949eff74ca407cbce3405671bf543cd85bc09b863bc5958cac8c128a6836afc4795719bc66da80c0746eded75d7c08945cf2a78feaa1fccc755b4f3b57fc519f8b191d1ebb	41	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	29	\\x35edf971eefee7bc8ac95c1659287e24236f867c563cb4174581d89e8993b918e43bd027117f76df3fa74b29b6a3408df8449ffeb66d9b267d86480709ff5a07	\\x71bfd872825c31ee8f24c6930920a346819c535377333cfb8d1494e94fd1dd93d8cec379cbf27019c929b1c6e857e8e1df29fd063313cf028b3b606cd2bad21a572ecc99130e2d50fd9168a412384d0a5a069ae2f58a81bd9c8278442232a25d8783246f67712fff52dc56370b41c57c347e3c4d2c993e7e0e08c4e760e66906	\\x23b86c9bf810d0d4b047043eff52409eb281ace017c6c42eac05b455495a8ca3d3025abc4a7dc83dba65e4884506e3a2b966eac477922fb10c08daccfa4cb689	\\x65523b94208b87218c5e3677272164f144bebd243298b0b7726cfbc7a72d5c726c51ed060afc13d037b6cced4218a30ec01967c589ba819bbd5bd25a6ddb1e3e067a4818cbf90798e72610e8946e6f150daae1dc02f57e33d6a46c12afb185b8bf9da3bae1dff76d5d1483c343d3a71818531dd744678ec665b8a2ac2b9ab888	42	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	30	\\x65cf9109b6f9bbc35051a3aa79cf3171eb4141b8959234fc27fded13fdee924725116793826cae2c8227c8d286b8075bfb2ddf3dfbc71c51f03122f6d87afd0f	\\x9ba58f28cd98a8650ec3ccf4e3c06a9c93ee2c3690f7aa069225f97bc959417a5ff92d066f43464b1ef17d8a494822463a4b67e1f32ff005c0d973ce5aaded7bf6d6198e99eae5beabc061668ac0053f8968ccb57de0daeeb56a79809d3b92a303a85359191653424c37f0b4373c8f751ac10af99e00ef71a3a3f0371d88d899	\\x11d95df64f51ed7c097476e08d970e1fc194560983cba22d26f76e610907bdf62aa562cd053ffca4c2e75df1bf96776482bbd56b9732758e126fffee2e059eb0	\\x0254a8b3698d9c42007dd95593cc8ae73a6efc63931bd53cb4168f02824712ff9b59b1e5a7e20b9e0d160db54bdee1876331aa944f9b67add5c92e546fa888b770d95327042170d09bdf15aa8991941a7aa8b992ad5a1889f24624719bc099f588de5880908e8f75054762e5dae5f9807fd51e7594585e17fdf6ba8bbf4a6910	43	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	31	\\x46666f3d59f9038f5452a2303c0df0d43620454ba2c2437fbc92084db99f4b8af0b7f7f1f27fc76ed48ea012271f494a2097948ff248d67b2cbb3cce0d4db20f	\\x5fe542419b2fe0110a1fc439d975e4988f9ce52bd485264067fde73eb75edeeb73286bca2f746e6e7d0a20e83d4e408d72520087a593685a1e32180542b46755ca2a7d92b7511cae69142798b12a33587cbf6fdc9e6ceb89a05ec6e95173d6235a2e6b6a83912ff8e37c0aab22656dc2b00f4fefe271c2f1cfd7f07724edbb8b	\\x0a70e29944c2887cf6c9444d1dd2cde820403a76b4e2e972574998dd225f08ec0a06ab3fb83aafd27f0dcae4d4bfafad174d7a3a357778a4fe22667f1cfcd51f	\\x8915f723b058859c27d8897a4684f0009cc360c72fac44f5c19da8c69d16641848dc7784ec12946dbb5b4c169d5e2c0ea5240f8faeb5c1dae37fdf2141bb06645de32d194e9e411d60e0aab55b978dc89f6b1d568421aec22033e7541b6374ef3ae01bc15d7c295e922f34f141530829b33697e2b75e4345b89857a8c579ffcc	44	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	32	\\xd8b0de98d1f286a3634932c44300e3235829f357670e8a91be6cac3482624eed0342fa2301cdebfe0e22127266a3599bc0e4015999e511aecc595ed3daa01f01	\\x4ad8e3b09aeb781dba9760945265e126fc21e9c04c6ff301f0f51cdc0c5c383b505020281890bfc001eb511c39220c7ac4145452123f208493432f68362c8da7a738fca536d2a3f62cfc776eae545ad0f216bde2c97de94bc39b18f6332da0f13d9c47ad965669285184f6c35f0ce32746bf6c43cb012afa56008411672ffc47	\\xe75dc883d930d880c7ee781e933de2f5bdb302bc419dccc2ffb10f1f65cb4ad4acf5d8fa755197eb51e2a3d26340fbfafd6a3f0733d8e11f4a5e76743c925098	\\x18ab635d68b758c1c71c8bbd98f76f1924db0a8d9b6481de2181a6a8794f41a6da1a08c942162b97060177e9b49be09055860bf74ac73ca9616aab2ff1abf66af948ce7c94cde0cbad678d79f506006f31c86ddc562c7ce61ece7dfea8b441b18c7f468f50fb9686e8a60ce4b4c9699623141440806bf9fc469b150a4a7237c6	45	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	33	\\x6f84739d941a95640cb9042e08851e06b751a0dc89aa62ba2fceeac099e74ed6c8fd6405a1616985d0d74abb6edad517668b3e0e70b2662db8cdf92c5b82910f	\\x4882f637dd3e441df4f8549bd80acc12c7079fb50510d41fc5dcf5e9f972ac3925183ad23ae3d46c52a76ce8f07314b1fb10db7667559c54c1856ec6f53ef72a983e3ce247acfc16325671267dc35f1917d37b031a4b9b3d871a2e8b7bc8e1b812e8753799419838e3a9d6d03f971891614ebf2df1f64c2d041e2c301425a1ec	\\x7e1eb184e90200af3a1660e24dab19f417d2aad861f361163aec6aa94472c41cb42b6778b8ce99b2ac7755e36a70d20d45e8373ecf24d33b86ed2106b80f8031	\\x5299395b14e27cc60ef699c9b405dd935346a805b1dbb9f7042471605d3efdc91af37c156954b84de0c8315fcae4e94bbc51a324df3cc643237848b4eb9edbb1d5142ac67d9592c9f1ef393219a9cdfe74829ffeab114de54e311af79dfcf9685a430d358d87f77d50a6127389bc511ab9b5256ac60c935f5b18660726a51477	46	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	34	\\xfd328b8eff7ca8d80689da6611ff37840cd2a7857df55b810a8c9dd53583b36739d98bc11de2a5890dbaa83b2a66bbfb016b883858243e9f3041ecf96d52480b	\\x89442c6b5dbc415f7a81d6fe1073a37a27734e05dbb692a30a2cd1d1493dcc43326213497a6136c8b71b8e5cd0c5afa0c5b3063f5ffd6d7e34cb96fa2cbea5de80dbfee86ccb515190d6859810bd48e8a107ae68c8b8736a1168377897209bf532b616bea09328f30a3c42d9598bc7fc6f09126eee9afd9877268ac4d29b4b9a	\\xa46b0edc68805177a0b51fb90814dee9565343eb6edd3f52de989bd93533e7b810aa869ddd406d6f447f101839f8a0136fb862244d55b2d4a36f938b9c38befc	\\x9cc3195783cd8d21c28da03dc0c00911d6741f92dad67b3d2f16e3cd025c47fc4278fc16e48574f7df692c27455661693321c1efa1e71065abff129857d967069580aca926743f74c7a7d5806ec29b1c7aade813cd3f0a3676b8289b2cd1703773afd45e972adc0ae4b2b01812ff7b09373c528d4fc78a0be8a8c3fe09147711	47	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	35	\\x8a5f6c23c91590ee6dd28402beac584c27f33192a05689001e3a9ca9cda48c0d3bf3bc3ab8d8e1f932519154452598e9c84fef3a4090ea9de63a53d8e0876e02	\\x40e66a15bfec39bf5dafabc5c33e2484dc24f8e5ca9c696ad7189f60b683560478c519106f73badda369b4405253a9ce5dc2ad0c05d9f15453a0fc292e1bbb96ee9e4298fca00155d0a66cd44181834197f95b4c78e85242978dd0cbe68c839e41ea116556bb8c941cee7987b7278b1e19200ec062b266f943477e6b45cfcc1c	\\x7bda63079ab38f3d91cce62f318089871980a0d435a7b0b4c70b1c7f1441437d4e291067f36e5dbabf6e9729bb1114de74b9a359418fe01765f48997d95c3e0b	\\x6eab056728c7b25a196d2225a5945b6ba388fe4ec8e3e08ebec8017f12c6ede5f1e1a72ac51c102b2926cf21f16f2d950f7fa6a249d5158d69ae936fced3aeb4aa2c7e7d99e4b013249c14ab92f756f6eabadb5f0895b4e1ca0962dea0283275fd8ea038be6c166feadf030281ccb2001bb015675ba65c638be3ac66dac843ca	48	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	36	\\xe03ce2f08c516a3f8cafd007d75266046ee15471dc2429446fc1e9e31dd8e4398c1326a1f95f66054e09551d46d271e57197435f88e7f1411484463332b91d02	\\x849174c321b401ced382d5f81fcefd2eeab32df8340517e04206714af98a7d495885aaed80ad5a57d811eabea4f33f4d7ccd9d9d58af317f24dfb9604a1f358ee365d7f615b354f064834d8b510901084a1e0e5ac4a770efe446e4bf503b4bf7f1e88962498f90fb50f4006f13fb13f6d6b9012d49fc1ac07d8add1bcd00b71e	\\xfc8467e7837bc229d8dd2094242ded448594e8f6bf2f2faa7d410fd6b6fe63ccb94dfc271db3dae3a33cd2c5eb436cf7570f006d3ad9d1edcd6a8c78f7a61557	\\x38f43a042c15dc9cef7bf5e878e36b3810cbaf55025a265f9933a0ad95f75989b81a53f2f30d51e83f8f6bfd1c409c06a416a7f0a51d8a4d6fbf4eb3c0a0dbac53edf846619c2e54b8a72e85b19a88fadc30c83f703f622487e8a4ea75d2a7582b20f251d35e91f424ea0d0e21b756516db3b5fbb553b92c081900fe7977be84	49	112
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	37	\\x38625d5140306da0988978a668b60aff79c4a77665d3e8678c9ded18a09902f0ea003c8e8f5ffe3332b34c9b73b32851955ccd9a51266a99b37fb70794ac3c0e	\\x81468a990d59c68c83a2e8d35bc1cf84e6938902d319dbf8c001ec832eb2e3d4532c35c62abd49c10e3cbdaad3fd2b8c6b90d5c53e4a34df8ec17b5e0236bcf0a4493eb71cc5b07e0d88d979a98f1b16df75c073a89637310c3a28c4e8970aec64cd5c40ccea9ac0603eb01156c713b2d92ae8925b045fba65a2ff2c52ffed02	\\x52e6148e9c29339fbc0bd21b1d487cc6f3a8d37d521f7f6143ecde97f911bf993487f192eda1b8b7d597c1ea8f597e8de53ae07e2229e79de8e8ba30605c9dc6	\\x0649925bfc98daedde9149c09ada2d789d19826f1611053b5e12636fbcd85ccf2d5ae264abe4d874f993f8dd827efb0e3d1c22ebce9958ae390a23cacb95c639bea3587ea5243bb534b71b6b8b0c659e9a7daf002255fa846907c54600d52a844a3ac5057803feb7701249eeeb1d2d2f78cb6e6cdf48d9d5a80e109ce2731496	50	112
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\xcfb1279204fa7fdb6fd0195047d2ddeeffca695ae77881a7708a8d59824df528df4f8d61c2093416b221e118f43dfe2808a579d0d2bef14daf875b79fb885405	\\x47dd2a4b119ac08b57c2fb8ceb85d9b30ec2434ac5c589850aef9a2d9cbd6d46	\\x7f1c05ee5fb555c851860123b2f59e8ee66da7f7f9aa8dfaa08a890bffaac6fc9aa471e8824224462cdcdbad14107bc02e5e8ba987d34005ae1052537f5a2728	1
\\x899bb9d21aee086a8a1d007bf4f31ee8e1d0dfeb439fe0a8164e945cb8e3ae59f2f34c6ec20b55a24252b57e3236e484329cd5042591aacb96e037fed445f04e	\\xe5474f6634ddd112b4200157a6af200a9c0362725d2cacfd95d4b1cb5e2f1b35	\\xc44c0404356d234d09837bf02a6943b117ae6a0dddfb0944d8cb9a695bb8af9c8b1de7c9b6fa03e4b3ea53cc95bd44d473a1476a2721eaa84fce8cb425f925b2	2
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, known_coin_id) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x8359acdc71ee96d131499d64f5e706cad1aa9f8af82ba7eb80e31cfe5dba5c76	payto://x-taler-bank/localhost/testuser-iaqRzgkP	0	0	1612554446000000	1830887248000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-iaqRzgkP	exchange-account-1	1610135238000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x638b5f1a2a81382d460e0f2cf6e561b2c603c46a980cae98bda170511c7a84114e63dceb988dcb2efd01b001bfef6bd4147bfd1c015dc8e87efbce1f12e2d423	\\x4aaac9224f910d3f20ede1b4e6d479a96dbab3c44f7e73becf987df71190c2cec144f3c55e8242fad76927624eda447ca4bac2122956b8e89cfb743e9e2072713e44a02c823dad4872470f9b6b26463659e81727719214db9aa71275fe747479986c849963c9e4a7fb997d7b6fef5cdbe89f7579a7d7c06bba6b0b2b72c33fe8	\\x6dd3d14e9eade4c5b827a4f6c4a33b22da370cc036828747b64b881ce2a971e9b2090448eb3000e332bf1bd22af8db57360f21da386e3fef64791d93fb649402	1610135240000000	5	1000000	1	353
2	\\x859ab52efef15df048c36da1053d0f551ac915dab59db3743d37484bfd553728635844b51898e64cede2bc5c28b510005629020635ead0aa720191f9771e16a7	\\x670a8681d2ce41d8893ac8edd4cdaf15a9ae3228639786fec001d1c06a46e5c062ac65f0d3790c8e33e2b6ed2d2b64f9ad6f8320f7451953e8030b1f7d8c07d8f654f857f2e593a82439b63be38a10f05e3f8df23e4124514c8c8215cae18e1f3e1eae7cd90279c9e4e6387c86c7226d34186194030ca1985504f6aa35a2fd24	\\xc46a6593d8beb3f568ed9998cbf2b0c737d51fead4006398051d239033500380b4a886cdc6f292f29be69bc09413190df15696da70970975af68ae067edd3805	1610135240000000	2	3000000	1	3
3	\\x666f2408f868d13bfec0806b275738ec2b83a761cd258072b9a570f817cdc7322c255b7a9c4a35e1b63bb75a6582e3d998c80d496f0c84745202241e38f936ab	\\x0755864df116db338c2b3b76f628bf7bd041197c6bd19c1031f77366edbb8d4ad34174ae71f1a86fe437e8571e6914acc7e3b88e395f2359b5e0a390e1b734c97b7752afea3c86db3bc385ceec6fcef4ad927d0289ede7334aae43983dcd43967283140bb8eba78a40320582f55efd1b9352a1708830d98d160926209c7bb8f5	\\x07daad80a49d70496620cc4a0931b7eb176774ac7996f85a5298c8e5c28ff427a3d55963917771dec40ffd52a6148ae332a02504f111fd3de63dbbfc96c37f00	1610135240000000	0	11000000	1	197
4	\\xd696863504a2d8bda255418a42737f28be28d351cd998ca3c2e224d69d700b5c2ec79ebeab5d3d8e154677fb4b3562afdac17360abb88f0b5e1fea709a6fd943	\\x8de5809527de9d8e0305501d3883c18f55311f44263b46e891cb9d65aa4417b3b59678f1065f27475315f60f491e347fa0af0e32c84d7e01e40cd6566029eafd68ea152467610e7b0ade3e17c1a2b019ca78d7f974eef372468e23a1577260323f4b15417a83cef1e0d962954dc84cdae039f059d70b616f6f6da73dd4eff093	\\x9a4f14e9f11ffb25f3803e7d4883d91b2b7180920d1976a498e4550fb44e48ba30be83afde53e45d1f417d3b1543e5783a840ef3f35f5b44fb9c4b22032b8b0a	1610135240000000	0	11000000	1	197
5	\\x319d629b4aa38286934b178a0c2b4e733a30c9811e2706c276688fdd87931a3517bc3e051716a92f233d062e44593ad52a66de4f12fb3606d023ab38f2c194a8	\\x02be4689da36c311062156e8b0ee19b66096342d1676f9d7873deafd6527efa7cf0201b7715937e14ca75fc9af8ce4da38042f735e1cc66567f943dd7fda2fb0ee4d86cf6af6d36ad50ca6e305d5648fddd928f10e7c81f973281e1fef0d0cbee8c8d22734190c4a48b35861c7cd1ddf35a8b16b837a93a84013f1b8a8013a9b	\\x1a6b19ac67f920ef21f6128d72440961666f2103bd49cb98cf5c12a5e33d26312302b61e1aa8bfa2a629e7141c51f0d77e50ce74c73f93c85d0589d782f9a20a	1610135240000000	0	11000000	1	197
6	\\x5d5f5853d10b35625da53d639baea60ff37f621cbdec717cc3fedf782b4cc76940c1ebf23cde7b851daf42264c020b71336a7685297ad5c80425b2f9becf1214	\\x7ecf8a190b93b27cb4bc832c76684b0f549fe9f261cd2bd5c2627cb5fe8d1a97aacbe6414f50d01db368988f7bf277b7e58077f3255736f4d43968ea6b88c4e6cfe3dd930647685049b248846a8caaeb8003281c5c958a4f4aebb2f5ef01498d8d83a8ed9aa57a1d9f0acf09a85578b0f47965a1ae9f25c96d922ca0251d34a8	\\xd4d6d797de2580a7877ff68d0ed553a2d7324fd40b710eca18866b80aa6bb993cd983d525740af0ffbab706429ce6fa7823b09b72814c894198522d7ef2f730e	1610135241000000	0	11000000	1	197
7	\\xb3e9f5ca09d1144bcd00b26d4e2a88bccff9bab43887bbbe539e3bd46c15b65e887249afd2967dd76257a64c23812a5c1e0f600a6e736603a50aca20849c4c5d	\\x5abcc50cc59ef0ee6bf4847e4c09f68f8a6f444003407af9c8ac594b8db6d15fe91eddd1e66d86fa5d753ecd1892cce02eb95b46096b3e2a53cb1efd7cac62f5319fc7bc2398f4b7f8388ba73352bf575f8b3e35de33058972307b9a52409bf7f49b966d84e50ce2cade659b29faf548f37ecac17e353028484de184a46c77c7	\\xdce55cd322691bc631c63a87a0104c636740b01910b5098295087bb5c10703ab2324d1fca8c3f943da93c8f05d2f7aed2d40d0c554cdf70b76dff42151ed030d	1610135241000000	0	11000000	1	197
8	\\x0538489292b05b43e33d4da0587905e1fe04ed88229a4651213ea096850fd079df8352fa1a5917a1490067c5cfeb0412767ed35a0e8e77de657893ac3df5631f	\\x1bbeb452388b2a5dac627ba93ad8ee2afef3d6a2f7fdc5de9c58cd58b346cbb778ae2b50d7a8a21687199acf954493f397cf4e3ff5c90bd810372829715d9c890e7e0d0222dece71a266f6e498c26251fdcf38af821e433aaa4e3b1f92d135b06e9d3bfba8cc24292a85665e77d576b77dbbfd8c8e722c43f3ae9c6257379020	\\xff01afded5a0822f0d073a0dc830ffc58a5d6107493724d9ec207505df7b9c77243c3f2ac7e0fea646ac0082d7059a1bb43dee1be35a4895036e750188a2f601	1610135241000000	0	11000000	1	197
9	\\x7f9c7a824b0f6ddfcb192ce3870f09e1020332647ea1c9db1740d8a9b9705968f4adb884576a41550068f7b5a2db8a7eac195d81be61b0df5401483bf9a13df9	\\xa41d62a9ee158b8e13e4ce24424497813ddf21a51c5056dc4a3ba749c9da1ca9e7c59c799cdc2b66104e3315ecb04c50cd282f8f7bbfaddce829663ffc39f36b5e43b3be16c27c3ee4fffeafb39166f192ea1f5f0064fb137f76d53ea96b7f319f9bcb8a7b48d58319aaf273e4248e3b029835c990d11db27790735f5a26f4a1	\\xae4a23fa558d6983bf009147319e3e2130ad1ec630cb94785cca4d50cd12b73eff796494d1b049e587a5a7bb5debbd9958d2cdd9079d92988c5796d290742004	1610135241000000	0	11000000	1	197
10	\\x5c507b14d739269f0a92e4c77c856ea082b7a35d21fd5dac6ca62b412dc3d4c9bc85a6366dab015054d78e0fa92fcafad1408ee02ea7b7f0cdb795815b8083e0	\\x64a26f362a3a0d483cc603e89bc5a5d62d66ca2c587b1fc0f0d35ce9c4a677b05d6269ca04be35627dad5d7f084ce441c9f6697089301e0f68ff01bb85ceb72d2c03431ccb82340c0ce8cb5093399c6b0d516231beccfb5b675e7a9842d93abce7c28d9f0896a4b22f97bb5e1231c69d59795eee233fc813c5283ec5ab7413b5	\\x1c7943a0e234eb4613d734b79f5fd546b658b5ce946dccab5ed5c4f5a1737484ff7b5e757422307a9acd86aafa79196ea556647c923c2019177a6781a75cb701	1610135241000000	0	11000000	1	197
11	\\xa763635cd287652661f9c599a34cd5db4080a7342b3a7a93b2c976850a4a3ed95ebbe65d6fb710ef5482464a2c0cf040f59a963a167b471a98b936d57b1e5d50	\\x6b52342c50e50a2b679069005f7a033208a6dcde018af8334980e8089808ee1d99e8766212cb9ae8274d1364c92e7c6558e80a9866152be6027c90343b8813ae41fc787fd0d39ed6a354dea72e01d5e25d88abcd161646d47b422d845c6f4b1eeac8a1821dbf37002ecdaa9656428273273e4c67b6f66a96b9d6429ab0f90659	\\xb3bfdb347ace091df4eaaa6fcd4fb9319c4c5d650530b6dff1f4d4e49e6144e752b257ae5015e0628ac947b1c7404cda4505ff09d50e0d30bbcf1b6b10dd9008	1610135241000000	0	2000000	1	267
12	\\xea2ab06cb6cf2614e0ba263fd7a9d2c9c5894c74a1f1991a32964b9695486f89b01a76c0387e2c5988e70d5ec3caa39aeac660f2cdba2184eafc7f76864870a0	\\x21be0d40258ed56078305d735de347ac749e3553141177b266eb98254c280536fcc993d42fe19d4a09d8ad45eadda7de79f6b7f9eb5a0f26cd4a73a7aad007d7b9e44d656776f4b71903da0ff853a8a2030efea39207117d5acd96543686546d173f15d5b694d8916ae7596a2c83ba35ba781bf2a80b39f8b454c34d59d92959	\\xa9637bc73c9cdc05444345afea7582db423bf751798a45aa5074f02bc33db7271c2a61f3ab242c007df75f0a637584a0dcbe8413a17c175a6e285a321d72ff01	1610135241000000	0	2000000	1	267
13	\\x1605342fbf7cdbc56296704f154f1c40e2d8d40d3cc97ed5e57ca61fd1ec79bd24d4c147a18fc1990ad85e59e6b6b70ab206afd336547ca0a5492135f29d9619	\\x7fc10a3c4f899bc1e45603a13fd665f08ac92024b8544c8a2b3e65a2ad3a9ead1dd50bfaab54ab9750213314e0d8f90b4eb0745ffef9d33ad4d05ebf1026aebc89559a18c0e6d1fa9d4f03330dbc8f1133906dfdafc739f328ea6d61d342e3ffe619f2dd58ac290c257ec222c5931f6b83d14b2d37707081a00684b1c0bebda8	\\x6f4fe10117ddec39803327945c56db7c9d4ce1c192b0108209aaa31f0b816764495de3a595d80e6e987f5e48f800b0aec8bed2b0733cf368d2b26b04f3e59903	1610135241000000	0	2000000	1	267
14	\\x33be0cb7cc27b0ffe9178a806de3e53fb48c04bc2481b6e4657454de94e9c51225bcb4df6e5d90614253e564fa5673e55f709010f6d59c7fdfea392746872432	\\xa3e38e683809137eb30580a2cc446625630947b734d625e0154d69cfc33a35e1250b6966a754bc619079ae68f6125901b6015c69b31f05346540fe7e007ee5e0ceb23e72bfa29e9b13718c36d48187ce8d6347590b3ddc413e118342bbb9c49016e246b2f3f2251ab1dae57bbdae017fa4d9c9ee693cfd107255d6b01ae57b47	\\xe7efae6b84c9ad77da11690baca5d3bbfecb69bc5ebe3b85d62a419cc08faff82a7363e58fbc10b86125568b4ccc0083ce770c0219730700b077cae8ae91f00e	1610135241000000	0	2000000	1	267
15	\\xd9b0452abd3645a93b502de816f02d6933ac100dc7060f92421a195b3ff53fcf9c56c4b536c3e5142109c5ac63e60cc4086c8e2db2853ba601849a456f988fa3	\\x3900f09be3982156bee208a8071312d6ebdc9807e0eb2dfa3a699fdac31e8d531eedfa6904c13f11f1d14cb0f3de15c9f7a5583178d4f409206cc1fa3bf8df705437735228dffc231197ca2c7c07db59c478e728b1d003675527bafb0b9e0989ef3d80b0673edeaf1250319d53be03cc2cd4ff6dbe5e74b33aec2ac3bc3db6b0	\\x862153a9b27d10acd81769fbc5ce6c7023ecb20a1deccb23808a980ae40cf7d69c42a35f013039f272f51cc3bc026f4a44cf95efa7d4ce2d32581968d2c23f0e	1610135247000000	1	2000000	1	180
16	\\x63e6d4cccc642f3df95489bb494980b5e7e09b16910df7b3dab3ceb433bd64297539785e3ed6fcb52f1878b5fd567e01403ebf4073aa972aa10c4eb38737f088	\\x3aa9e56a024f9b283c9f2318aa83afea793b77a205ab0fdc8ffe07bed177b5ac2c2a03cd567c170907332bab828c9d17ce5b2952b202f6154976008f3dd118837463a44816b618c6ee821cd338adb5af981c180a3c2e4fbea0206a4eaf093664706ceffb8b1a6583d2c10b87520f28fbf5a183635af607585c890a408f8cfa84	\\xf3372846282b1398c963ff0df7db87dff6cd6831991c3e1f23a0e1743c8bd5435c43a9689620d31e6658eab88243723c80be622ce67737c3a1affc1bb4f8df03	1610135247000000	0	11000000	1	197
17	\\x51d1a75653c0123265657473aa9695db113d79c04ea985dbf11bf8323a52c008d2ee5ed20cdf18f4a2771bf349396161501fa4bfa38b6b24ec69a4fd731ab645	\\x773a0ed53422489f762f9627f78f3c62645c170619a96b711823928a9bbcd579d59e8b6de1b40e3dec84c9d6b513fef7709916a1a3ff62abc7ff26c355deba78fe0eb5091d8813bfed16ec86bc0753de8b5d182738b6770419341a6696511ce88e3859259ab261ffde8a9a95d44f330abd1a68e4cfa6a79f4bb40d290e3e2a92	\\x30c459951924a4847d5b448bc3e6792b71c1a96011922ccdf1f60588641af765277d0d93a18e49ff386d610984395294797661b00f866edb2970b6efc81d970d	1610135247000000	0	11000000	1	197
18	\\x8615a5892327a36a4eee4669be9616c66dd748f5a8ccac790f511a754a876b6c6924564b4295480098678f2b67eaf33e46362ea0ed1dded8bc137ab94f314c66	\\x08d6f483da7930f36f2b347e1f6c44a3cbd33f96d66d0d207b1776afb1e1bbe6aa9df5a5ae8361adc64bbc9704092acf6278baa46ae7beedabc56dba334495042a6c1f08f3bf59a7c87166a1e0af927f847c32da1bb92b695fafff4ba3ed4be45b5b48fe40ee2bb4078977e5772076fefbdfbcdab8cfe779557f5b5b268626ad	\\xa7d5911da71369299eb6fb782bafdb314102e562d78aa91b691aae8f9419f0836ac3dccca2b2004f1daa0f75f9ee8a8b270920f562ed8b477c572fd48a49550a	1610135247000000	0	11000000	1	197
19	\\xb4a8f2b79a337941955e0116e03b1733d61880735e96b55b562ce4f79588a360226f183548efe86845e6da1da3c1c8576f9496a9d3ca69affd61f1f15e9b716d	\\xa4046b44f6da8db17ba2330fef9cb6cfdeb6cbade594bff696e6811ebcc4d96cd5c9b5e9d531959ede5a8af85304595da8eab2252581ddd9d56e57ea177a6e1e411c2fb0a21621e1b6a6e0c336512699bc45c946dfaf11aab3124fc40df06763a8ca59666340abba9ea28046393412440c06ab189d402f199458321925148f69	\\x3811148957dd9d8e954d866ece775d99dfa5b5ba18996c793b62db753f5d34a7a0e199639d3cfe3547f23cf4bedd2aabbcb15cf68f0dd373e3c5c03816ebee00	1610135247000000	0	11000000	1	197
20	\\x28199b0e033f58224f5e242edafc63e1989db91b1238a87ba38e98ccf6fa1337a3b0d260a44173d20ad38b78cc225dcf813ba3fd0fdccd23dd002690a9c8d82e	\\x035b3ce1050be0063b3cc4df1c54a7cf5c475981b67cd9ddb5d75b4fe0837dba4fcaa09811d42600f9afe803e9e546fdb299ea67d0e8fada0967cb05e9284ff53c18a8e4eff39b8f20d059ce9e79a9fc54f434a4267cba86ccea5e06144b1566c9aa3f4814afd7282e4636d9e6c7fa918f742e5dcea07518277ba7d30d449fef	\\xcfde23a8bf6c31da8ca4ed85b066760e208da9f2bc221582b4563b525f7a917a8bf107b6f926420d30e8f2e7730de3b6cccd74df84701d6945aa3ef16f175304	1610135247000000	0	11000000	1	197
21	\\xe6a87cbb11e445153d316b6b0f02e8366f6ccd40f636953352ba72b85cedd89877ee4fcddf0301715d2a06405fdfe083e7ff4acc5d9b5d181a92a4f2e83f3158	\\x492528f92ad11a42e95b496b878674957b97255c6205934cd48bfaafd6b60202e37f9ba769ab743ae289e38f961a88d61a688705b922e8783260c96aa256ad030f19c91ced8ba45362fc499a633fe2cb4536678c65469cf5b0d17c9c5da177fc8cdc46b6e3b33796ded4ef8acca72c48aba0ad392e1912b2109e353f4380622e	\\xd7145398325eb11dd4462f3190e158128ea9343b4ff49ee86fd316f1aab65f061d77b1cc8d6483c7b867d9214ae292bbbb8cabe94536271f1eb014954d072e01	1610135247000000	0	11000000	1	197
22	\\x2b72f962062e5f433845cbdfa00ab8e5153c39ad202b7c47f31357f3d08bdf2e05f1a235c315effe94d58b66170fb5d39ab088ff5e3bc2072ec741d659667c9c	\\x17779dc146bea3d76cd908cd80aeb29dd6224d87fa3c0ad428a8a0aa2e4a40036cc63f56aa0e10ab9079a4a97788a751094ff182307f04d8ce4c031e884b2b3484c022b94efd703be36cab3bc38bc8fbde5cde9f79ff31e9e751907df3fe3d78c8843484b4f0fdcbfa3958ab86831f9b578115614d272065f6c7cf7f47611bde	\\x3c605d639e32fd94f203db4dba79f6f5e5c51db4db67561175ba5ff29e43f0d859c684c5c82b34466a7343f827b7c4ed017f97d9980c194d42a07b0158150b0a	1610135247000000	0	11000000	1	197
23	\\x5fe6cc8556d5b23ab8df93b2f92d83539c3a4207c509494f714664771f81d7ebbeade7c9fabed05daa6956b68e7dbd822433b22de5100ea2b06da86632cdb0ff	\\x6da7a2dba3bc77ee305e7f7de574e3ec1a08ecbc78432d97ac546695eb8ba89a7d78be9e062096b35da96bed6d976a72572b0db7ef072a64adadf9dcf99db8e49d7b9a895a4c70c0fe7913d944bf36646a3858e04581e01b9438c2141613c8edc9f66fd237426fa01684c9624b5589dfde1db547e0abf46d888a6be60a54a5a9	\\x85bc7100dcfb6cd934a339fb9833e3d9b25b14afd836d3830974cf98133d59ae5eb6098acbe29632c72a14a3afd863c233e41967f420b949fd466f22a22a660c	1610135247000000	0	11000000	1	197
24	\\xe9df5285c3c77b6aab9d71351d60f24d8dee35ec609440224c1972501a3373e083bdb228f62d9a11d1bcb63d9426538874604ea1b6f752beb0ef5129e7207d38	\\xa46d55469bb5df642667abe82d6e35ad4834cd23b1f0d1b6c8d4115a6cd9d879057dd9719ae5b544f17c90219ac4431f2989385437c56621aa96bde511a2c795fedda969df9ee194447ba5aa031b31db08383da18734195e47c152a35f1b1b7767c3ca4c8ab035e6d942fc14ca1812dd5b5ab5539805475eb67e3c99290d588c	\\xa581ba2536cc20635a6457ffcdc2ade87f65d0c7cb86e9ee9c8e557579e36e525a97c68483d38628e028b4fba7769cc93dc6eba9e4c8d96caa2f5f9c79611a04	1610135248000000	0	2000000	1	267
25	\\xf4bb086a2c3e7deb17919afbaa125e5b8d595020d0a0494f256d902e1abd7f4eaf1d390f3ab75ce99c4658dc593b7922f08d4d4c2c3ead1c5c0019bd913b0934	\\x75f2291bbc4442d15f8ecfca5a7c7ab056ab5b3cd1611383fc0bad04c77c7548d0bdc3f118a50ba95927d2dc8ea5d677a1cb4edcc3e41f2b0a39cf756f080c6a2dd582a8ecc0dfb041be8dc8261c156799e12f46f08c4fda404d65e9e3e270130d8a608ebdeab94081b454a5ba23719e785eebe736f014acdecd3a0de1f81653	\\x4109db4ffbc39f4d43528467f2c8f258de973dd9dba657dfa83ba2266f66a7afb7aa0b1ecbc725b46abc99d7aa1f194f1a8d7aa420b5fb20c47fa8d257f30101	1610135248000000	0	2000000	1	267
26	\\x4a287f3c1ede15cbc8ab6f5edf47eddd60c819c38d7a31649e0ca3a1dd724b59165b787969eeb431cc78fd3b327712051e253bda2506b35a4c3a5634071d2d52	\\x9b1d6e05e0cfe7042353326358333fcca178de84ec4573aba8d28f299f56d0d7a0212e50b09165e60e9d19762aed55ec0992b2d7aa4a4952238e06cbd2c04aff7785c6e12002f87e391c46bcfb69f2ffcabeb7ad857f51636922a4670ebee9a07b64060cbde929ae56ddb865540e069436ac007703be72e1563588aaccccc304	\\x002ff5f3026713856a8e1ff54bfa532a0986677f1bbfa2d322289bed5c8b80844a08c5d2a280f4c36d8f26c5d514ce4119c16608a65bb9963262ee4e1b318000	1610135248000000	0	2000000	1	267
27	\\x1d1e01c4588a18ffc39723da216532d9e0518c3210b08a6b774e635f61304fa9614e55c0a798c4ce701f83ad275950244aa54620714abc73e535b0bfddd8dea7	\\x34bda30daf882746d5f8dce19bced7cc3170928720b14a30425ab8dd1c7b9b5910c765cf5113da0629f35957ba258acfce75743fef2d2e149bd5bb6e5cde771cc5b8eeb1e306659e5fedd870487280dc3f29cbd672c8ce13f233f169f6092ddca3595a36c9e5353b2bde97eee745455fa89fae2a97f316b266cd11aa342fe22e	\\xa68e61013138d7fb0e7151a2b9655fe97a7863d69e2138dfa2d064224f7a4ded21f7b8ae56c1201b2bfc2a86eb36ff12c812aa532911796c3f8aa8ca4fab9904	1610135248000000	0	2000000	1	267
28	\\xce024c34d3c05cbd003f29bba31864a0004796a567ad8f56e409d6b74b19bd976c1067255620c0ffaf0be7c89e08c29c91e5dae28e86153c985e5aa9ef170976	\\x2fadc2c2f9f50d1e490df7d0191f164e3be9c3b76bdd90db138cee75a91ff54a88e7f5838c85c463b196651ade46ed94e1a87ad9828fb7a89da0cf1a96eaaccfa90f8355565dfc86d92b959fa9cf423b70ee6f94fd7f723a646e55f36085702f7ca23e0c368bec0120799949d9fee44bb634fe57bf05f5fb7a436efca6ee7704	\\x89757ada32ab683f77448098f6d03a32450f8d26e39c4dc6559ce979f5f031600d73f46bbbc687a0a978484a2d4a3197e52ccd1b7d8242be5817a1d5d799ab08	1610135248000000	0	2000000	1	267
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
payto://x-taler-bank/localhost/Exchange	\\xbea71879f65f93f80011f40375ac2ac0465d34c67e46245744142a531eb81681250b31d40895e09e4ed970ab37cbb5156d7483e7ecf4eefc1426db6c4107f101	t	1610135221000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xe30c73eaf0ef82b2a21526820d123f53f89abf4a6acd43bed27c3e2bc27e59f9a07a6603eefa414e08174eff4ff516b16a28be50ecf7f99651b3a35ffe0c8e0f	1
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
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


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
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 11, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 1, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


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

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 2, true);


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
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 1, true);


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

