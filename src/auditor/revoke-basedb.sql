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
    auditor_pub bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_pub IS 'Public key of the auditor.';


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
    exchange_pub bytea NOT NULL,
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
exchange-0001	2021-01-08 16:07:55.795707+01	grothoff	{}	{}
exchange-0002	2021-01-08 16:07:55.908265+01	grothoff	{}	{}
merchant-0001	2021-01-08 16:07:56.097178+01	grothoff	{}	{}
auditor-0001	2021-01-08 16:07:56.227418+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-08 16:08:03.976352+01	f	c1cb22e6-93bf-4574-847d-70794c45cc0b	11	1
2	TESTKUDOS:8	24WG6BGEM5FPFS16M84NGN46ZDF2V7Y03BGZJQ64749W060VFYN0	2021-01-08 16:08:20.460654+01	f	200c84eb-601e-4d3f-a143-1a15073ffad1	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
4e152ed5-6b9e-4f34-b8c4-eab3996e7ddb	TESTKUDOS:8	t	t	f	24WG6BGEM5FPFS16M84NGN46ZDF2V7Y03BGZJQ64749W060VFYN0	2	11
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_pub, denominations_serial, auditor_sig) FROM stdin;
1	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	181	\\xd387550b4096e4956c4f9b5e2fe8960e7d17e9e182719d9ab9e5bc57dba42ae9246d161eca4d525187f5ed1a126e16a68e7a1951bf098acd3fa3efa2a00b960e
2	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	394	\\x252e40481c2cc5db3ba54a2a1dab0c99b839ccfb6729616ef204a916ac93365bfae16b4912d5dddd7cd2fc171aabb376f207ef73fbcb6a87ae9fb9f2e1b3c208
3	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	305	\\x22330e318870baadc70f37bd7b0f1274518eaea7355ddf5298e8944ce6299d13c2716ccd5a55d37e3fa0f8e54bdb6a7c061a27a95ed135ea99709dd3c98d2506
4	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	232	\\x8616a062b823539cce92cd99b826c3b748c552cd40dc49e18fc7df072232ded26d0f3a19c5ebe8807e7d68b74b1f200c924eaa5e9bf929b5dba8dfe508ff7406
5	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	125	\\xe4159d9fd9dc1ab1a617a04daf832d9ada94c02f47c49cd29adbb32e397d73c6ebb7a76ba07d9f96448ba6e3180aa07f0c9bb7e1adc240bc296860e35af7f80b
6	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	243	\\xbaa9258422d87810e34bc64b007b76ec98a125f7edaf3808ff1037dcba7cae40e256d1e73dbf88023ba506c03b4d7fcd55b7eb8670d921a1f3040bfc8ae92c0a
7	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	224	\\xed702a72d0c734233bbffb173822fb03574af4a9d33462d6e19a93d790a7ab8c8c14819cb5a90590bc89bee69d8a4d259d43a971585822ca6a0d45e3c5eeb601
8	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	188	\\x9707874411ea161bc44152ff11721a9e94cde8be9b22fa92d986efdab043efb4d064a8d5d2fa0e58d8c72a6f71f24dcb0c9df44264c0390a42597683a7e08102
9	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	335	\\xd32cb00578d1c06ecee9f0abdfe3ba3e4bcf847a07163ec3343c69c60a167904399b32b1f9eb39b4d469ec863cb528c1e3f1720be916b85f689e384a8c7bdd07
10	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	227	\\x4c81f4d552fc8d7e9dff546edaf38cffa050df8b10f0d9ba268d324aa25a5d122df6e9291d144b3cf8c218417fae9a3c8692fce040f10bf1b3928c2ccb606602
11	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	127	\\xa886e9ee159de9e444fae1cc08212faf0a8772d85a3f8716978e800d5bf202323a43f2fac7d735daa3bdcfeffae8879fa664d5a7b908ba6c4437ca6592391907
12	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	306	\\x96e27008d0379ac5001ed928c506b63c132a739f173f7a81d8fbb1052551d9d5a46c78637272ef93acfe2f7a7daeb6ccbaf95034ff7b08a2050984fe8522bf09
13	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	264	\\x99c73f6eb3ace6d9fb273e9baee49dff5f7ffd98a3bd185eac03be614aa3308ad63ec41b7234765d65337f654e525323a7790090fa7a6615e7d6724be369600e
15	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	29	\\x2f58af121a5dbcb88a566184a2b4b3d82f6ea04dd050cec7dc7c19ebd79f53e8bfaf2fefff4f406d6b79d54d993e18c152faa0bf5433c4fb908a67b895e95e0e
14	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	312	\\x23b9ea5f7498803ab1ab997439b08677e6f03ea4b48a3add687e67cc9933e553faedcd6230ab8104da5543f5bf18c391e40489a8b366ddadf2d2727c7c9b470d
16	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	151	\\xb21c88b6099eec7bed2b8e76e4a1239705455183eebe8564ce7a4799aa5faeb6b59749907ff74749f44d5dfa8ae4ed4558408cb88485a053fa5826965a905a04
17	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	70	\\xc0173010b47a8a73ed4317452caf23c4fd3bf3177653f576bea3e1c2b0389121ef4709a0b524c593b091e3af89826cf83bc4b6f7d184300d32ae3ebfe70aae07
18	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	199	\\x7bd5ecab811acafd7838f31ab40b6c8b0157ecf560beb21dca0a61be6574193a40c4f80d4b539a8eea25774b2fca950522058c0dc3843394db1ced525f3b4b07
19	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	84	\\x25f463d5cba1b5a9514726ba71fad5f9b229fe882823a9671bd9e0c70117930f382086ab658d59502f8537625d2818d9317fe53df4bdf3b72080a3389df28e0a
20	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	187	\\x3ef77b224af17b2715d3d30566e7ec8d4d7b4b2153904c49d69c68e53a049590c7ba5111d5390e6450dc2758d4b8089e7e73637b11254ac624bec0081b3b1a0e
21	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	1	\\x5327ad8bc0d5ec805ba7928d8003e792dfa3b7f6297b6c6f0101bd6c6693a041ae7eb30c6de0277f3535b759ba2073a3c90c9f25153c3f6fd14569e7a48a9102
22	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	223	\\x0a3c092797b5533c3f104b0d4ee7c695e9fc04d488f0dbb07863f596e15eba82319ff82a92b11814d6403cb96cf88cc03d1b0b43c77989ab92fd806c7723400f
23	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	69	\\xdd9b114479b4c9c9328bdff9667ec780dd99c1b9e06f429740823b2fc2fe0bb6f5ad5c7fa9d2e442b192c87ff09381b6a6e774b3da83dfe1cf53c90657f37303
24	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	324	\\x640c9e320cc8d45ea034b0782afea3862b4dfa6bd346ebb4676bc79036247932a0da788665af4e7eddc14fc59bc2a98307aff42b0e64b112dbfb2a1b63cc4705
25	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	285	\\xa7ebbf99c8328a1d8f0ea1a331c5d2a63d7123973a4db3d2f8ce6cb76f87e8512f953e77a0a50aeb5ea415eec0ee804aa35bb347b8aadd7271d21bfe88535c07
26	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	256	\\x5421ac361b3558efb4a2f24375e04f8c2e79d4052dd7be61560b8542bcb693bd45e09db33166f91e453f7f212203692f31fd7c43b2577e0e38ef38bc0383ce0a
27	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	408	\\xa48787ad4f3667d437167db360a81b7df9e2319cc9b259dcf9ecac00b8b6f99ebb8904511ff50cdac90146dd2cfd2daba795cb7228034b6b8b651b67c58cc10f
28	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	406	\\xdcf655018eea53fb0c61ca5840ea8b7551da1a302803609d495c77854e792eb084b838c3521f12aa40a15863abc3c1b0105d311a4ed927e78f9c0f4b77d30705
29	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	321	\\xdb6f270ee2e7dcde446df42f6043c0cbc310d09ee17f84edbea9b3b199dd75f12977000ee053d2b324fb91a7b79dc61aa94405b316abf54b24014a46b769a602
30	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	390	\\x535485a76dbbf123cccb6e77db22951fd4a44980f8528cf8ec286b59c6656082dc378e4326bcd242947495b06c0b23e3e3bf18f48205fb75be1fcadd2999a40d
31	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	63	\\x37a6e7e59c2db13f06e2febea4891aa87efbdca19737986d84d2a7c28f775b6dd0aa03dc722b4fe6b4d93fc1783af74c37001b44d63a9a4679205b59cd153001
32	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	203	\\x53cb6ac5d89a05325ff4cdc0d4630e675bb1cbb85c50fcc97c8c00f78d301dfd6db3267d8aa095cd3c7941a998939e91b700a0d82775f2d745f4071cf8e4ab04
33	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	33	\\x14457631fb201b182f956812321b0a4988bf26f51f164db979521d5a9951754337c8cdf52bdbe20a76d6f229a4eb4b324f52d3c64bb464a88ffbe5895a20e70a
34	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	296	\\x0aed0b83e3546edd1fcfa2da3205ab63198ed9664c85b331f20185a43ae0a588f98718ceef233187f4904fc2714e0b2b78a737689c91dc3d730259bc90b94007
35	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	115	\\xeae28a54c5cb5491a7f413e51d16d4aaefcf46b4ad28487c36d9a60882130fb1a3e068ee7057e57b45e473141b077b5754b7f8d6bb64c36013a905518c837204
36	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	250	\\xcea7ad53edf39a9407adb3d9c38c715b0a36946a916f28cde30f2ce3a2cf02eda44081256bdbb0815b1c4e67420e1db75389c06afce410b813f2cebdd8456a03
37	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	393	\\xdc32c826eea3bd8a6f1d02c8a2a58e6bec4dab4a394056c323fa571d7d850bfbc260d2eb7a03f374f7334f1ed03fbe7cfe9f4b078096f3151d67c35cd6e0a00d
38	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	175	\\x795ef570da3c2e252617023d887b9c91a27733456b44b9db73f60a7cf593fd1a56dc4d8fad0178d13c40a89c19461f9305d502cb5893e6b4b710829d8f653204
39	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	357	\\x1a8519677f4c61d47f0b1ffcdf841f213365a6e259f8b9a5a7c7a1ee341023b7d7a95310ed32fba48c444e1ec24f04d63c56ea569c7385938e35f152781fe20f
40	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	328	\\x3e6af3d4fd19502b8f6951f23369396963c480be2eb71227023faa707b09e7830fcb41c19b481630142bd26715267b578212fef536c1f89b676943cdf6319e09
41	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	16	\\xa41f1f3c1d2c11d10daeb23827a8c31341a3005649d8b6cec875ca3712e4fc1217d8dfe261826d7b3befe9484bdeedeb6105a195de0018cac3e5c3ab99827108
42	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	295	\\xb3f48391103de580bffc442537559ca6344a7da2a878f266b3968638df72d8e7abd6db96c8e96a23a2265b74abc644fdca1ab907aa5a68f71213f2705703e50f
43	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	354	\\xea5a2904ec59ecca911d90c460dfb94c4899b5eeb30cb6ee601a3361670c020e05bca9bb9f4a40287d1d864b2042edee7c79662fb9e281b9c46e0611f80c3804
44	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	152	\\xd8c78b17d40a77747bcdeffbc4e6143e9f0af697d189f00baa69d1a5ddc9819277ebd0aed356ead35d97eb0a2079633c4a3b7408bfba004cfe1fdca8d5965b04
45	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	123	\\x1da55692f9c44d85ddf2c1718d4b637553cab69d50804253db6837760685d149d90acdbcefc13b63b88a6d542607d66ac59a84c7a5e859af6320b531199cca08
46	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	196	\\x36065570ffd44c632eeac33c0d779f5f6d8de14324e9fc432fd13857e25e3ccc3ee8b214f7f26dbbde0215db0fa90170ed6702680d1ed93cd44a946ef62d5209
47	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	219	\\x4be94cc5e52bf2a8e7d314507318ea0bcd1db0aa40800f493a7926e4c5c13f6087fb9ddbe1621f8e7d3dbe7e81a0c72b4c28ccde5b8e0cb3c42697eb38984f0f
48	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	10	\\x4ea49458e6de6e51ef617eb45f8a2c994a3567ee184ffe41bf25340362f2c1e822e199df2d79e71da30fd42a178d048d856cab2a22557d848501ed4627bb6e04
49	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	157	\\x50d30178f22198a135e7097343ec2e41c6f0fac14f7602798963c951a1e3c3f31944d620e62f728c2cab36c53e388b97dfa7c435c811d92922a9e423a724ef04
50	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	149	\\x4ec81c8b307f7546273efb7fb2560663a036c5a6e56d7d72d34c4fc6ee6dc3dd5fcdfecf0e7260159dd603e67ad52fcd67e799902767cf2cb8c0f6220c129f03
51	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	155	\\x9464b352d5a9ec3b0dfc5e5bea13a75857e3cf45c325287e4e5d14c89f0561992f8bd8d225df39f7bda106ab6e469f7a8a618a25cfa54265d8b7d853d44c9109
52	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	270	\\xb4f11fb9a63f19f72cba78a6d0a5ad17f317cc9087499aa0e2c9e40a8aad083e5c86c4aa2fe5bf820cdad82e33d20e048d0291129a19487495e809124f5fcc0c
53	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	257	\\x811ba515e907f8f1bb1d0ba74b603fc374240bfa770f4b332406b20f889910aa985a7cefb18b7a0a418d236ee743e0d89b3e53402e85a0fc2caca3c1e278600b
60	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	214	\\xd68fac89da6b894c7a1eca1ef04daf50a8ac29f6356acb3ce4d42b94ef082c43291a62739a9cbe0eec4709bb63bfe96c43d8e99fda42fee775f77a8986d6c702
69	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	284	\\xb9df3619c6638dc9289aacea2dd87b250597feeef9f239b9bc1c89a30b740e4fbb2b1285445f864467d58dba6a7f7e34b433c46f30edbaca2815caeed4a0cc07
70	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	303	\\x3071dabdbc8dfc3bb9db0077fcc8d209b13b9f9aad76d8eba034ba3b536dc5ff69310a52e4050aa641685a8a93c22859ece160e5b3d3463f5b99cf02be41190c
75	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	92	\\xd173dcd574be06b061e62641cc17555aae01b9ea8b6d3d5742e9caba33c62fcae2baaadf3b1991025117d86a6d6c692b64c058b31462c37082c46a166c213004
79	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	103	\\x24891511db1d7a28f9eb20667b855d078f6c53b6cb713b6e0bc312d37b7a0e6a426b8e6c89a803743c117adc97995718e94ccce707aacb601061dd24fb12200d
84	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	30	\\xdc57e77dc6c1ff0a985ce03f832e0fd19c0c50e1a4e6631e0319c42e622267676c1c1d18fe5baf4bb7731c75ede80c79843fb703ad2f1955ee1a0a2a4180670c
90	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	241	\\x996620f42c45e1ef23c80915ae901d43d418952b9672a3d5a8312cb1ecbaada36cb065b54294fd09a1b17e78785993762d8a3ee4bc9c974564bb30d3e8553103
99	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	325	\\x13813c6d078ed53ceb479769e0cff4bcbe9b6a7b1d8728c794558870774c0f7bd96025fefa23db977f7e98e2888d3c2fa37a5c9bf860a94de09b1f4c0ecea204
101	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	130	\\x6a00df2c6dfaf1d6d902eade28ef9a6b5db4af8c5937c74c738bda22f8e7e58c8677fc265b63cfda4caafdc032e84e4140ddab5d0eaa8c25cf07890f589d310c
109	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	202	\\xed418a6fc5e9cdd645cbc9272f0e5ea5225c0d996710e85a123ccfc7e36d5517bc3c8ebfeba3c69a293eaaa903b5ff0e3b953cb5a8bc2aa6df4e89b616f75f0f
116	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	173	\\xf139c51b8f2a375da4c03ba7f54c99918cce5b3d2b40e546a7999cfe5db7b639342a4dc634f38248cd50e8cd2e7ec7bb0877af36be05ab83ff954624f0a7bd05
120	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	7	\\x4893ff47f21fd0d3392d5e97a752f3776dbde7c53cfbb5a6d4635dccc1445e01e67917713bacd061f261f5b1f438edfbe04cb82fb2e1d782b73916b415ae1a0b
126	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	120	\\x866eb7079a43efd58627217782db9c67442f3815bb40a35c88a09ebc8cc8bd792d11c44df740cc444aa5d29a86675a19f46a4aec7498ef59528b4e351e7a3b05
137	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	314	\\x4ffcd3d8aeb11fdc4d914854045f659d6017fe3122a7db893b312d3dcb7bb7be1c9f2dc1b2ae5d1da1cb5f71e12f2aaadbff8f8a0c5654cbfeae742a80bd6903
141	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	323	\\x3f9866e45ae27cbf6b7ad5e3e4d40d82b33a2dcc20ee04ff30c2a1f7afeee0fe552a853013bdc6d7e0bbf3ee9cc01a4f06f17f1e687d2bf2d21645578043940f
170	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	121	\\x08dc938a00d54cad574933ed935462a29002f0e6387370f46d483a709754595ef050ef516fe75e5b18a8a15b88e123086731e37ee254a00e92fbf6e65e2e690e
197	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	271	\\x219b72e77cf8f2fbde2d18e03c217d00ad17b3d7a5805bec4e050e68fe6680707365033de694d561ca3ab1d5ce27ace9db02e7e60542a0e807d41053a0502d0e
237	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	422	\\x1b4fe2cfab157d24e585f48115e8496bf40f8cf5723325eaa8aaaf3436850c6b92a06fc59534d497bbaf38009d6237c871fb7896d868320a743018c92b41560f
253	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	352	\\xa0c1a7c370debee3bdf24db2ce10465c31b329f9f15f1c8a7c23aa129e32979db2843513bb870ff74ab0445de3d112bab8093d1ef47238792d66e0136bd5c20a
286	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	365	\\xaefb4be8ecc7f5797be06ede0619895f6c3b4a65dfbefc15f55d520c71bf068cf9db7c4b37ac3282fb1af1bff7175f5ccd4b26112de3655b530035a44919da0c
358	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	251	\\x84091a586df62f707ad711e5d5623d672dcfbc67e906e55b3bfad932cc5d9c07f746a5ebbd575a177067d98d42d953687ba9a869d4d36a2b54f01faa5ebe9107
55	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	363	\\x0f2804f3519efac119ebb216847d4606842e54aea0c1f7ff75e1d35af3853a63cdabf651037f31112b456a4f8e79986e12aa38578fa0121ef33160fd0f76180a
63	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	399	\\xe6c35946e2b1de325219a5d3cbb15828547bb5c98cc7c94f6de8bd2c4e573450156be6f946d121dd5c3dec323d6fe66547db937c93414995970682c3ae884b0d
73	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	166	\\x4734c0c59606749c8f1fd98a2381f86073517b2513a22904ff7e033d0f9ffd8cabedc2c56241f0ca97822ff7b32ee64b422c9bc3adfc1bd7ac392a967ca77605
81	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	317	\\xe64197c79620460d3c6a78d69f592dc4f56e7b2013382bcea2db801c21ceceb4ceeff4a7a8e31cfb646727600c3670f5a6502698670fd8461a34da64b256d903
85	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	353	\\x66a61ea398f656e2ecddf1d16c51a874eacabcdfce42ce27cd145569b3702fa2581d9e899217d0baf922a90cd5253ce90056f9d3e25092b4b26930c504cce70f
94	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	11	\\x4d3e669f03552b7b10f9f9c0f57dbe5b88fe2d5b8caec9165b1663ec4dba36b7b8e74d6346138e32910ccc5f61fc21098b68439ccc92d9f4f94ece5c877be409
96	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	367	\\x9449a473fe8747a12cc5bf1cc266bf0f9a41199ccb4fa9a5cf0c932d6d98937343d2e2f0fc4921aec579ce25e3cd8f6672f9ca37b673b6702498f01cefaffb0f
106	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	52	\\x0978c81314d907e1d07ffcbc987ed8103cf2feb40b0ca38ad91b09c77e4dddc6cdb91bb597ef3000b0761582c13c1724bb57ec037f21e9273ead67a5a1d8ad00
111	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	322	\\x2ae1735f7ca0c82049ccc6daededf114df6b5de492e33c1e1328c38e826d89253b2aebbd99b7d830abebcf6d1b212b5f75e712b678bb3088ea2a13987492bc07
117	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	107	\\x0379d7b1fa1dcf1ef6a6aaf41aa602ca741f74f63e2d82a7f8e8c83f620757f88e7b8c407babae7a1348ee4c4a73bc339e22a2b793ade31ab001f8c82d85ad0b
124	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	64	\\x2ca1137f1591564d390a7562aad79fe3ec521150f94c4554cb02ecb6ddf923e3b4b9328059b3b8ddf3fed82650877baaebec6e825e3306685bbeb38619e96c01
130	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	309	\\x6eb24d15247beef0839b022664962ecaeeb9a5643e2b746c063998c6f8d116100c7aae737249bbb57bb672509573ce56e7e4d15013aa6fd256eec9bde5daba09
134	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	338	\\x9d0854341d1abfc9866b7555cbe77048c7bb7e723b12eb9759ad7c1bf220774aeb5ee221cf7e71f3004b38c79036cbbce574549e5a15e46f0f05fcfcbe012208
161	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	156	\\xebea49a63c5bc96a1378477893cbdf45ec97c8cb703d73ffbf7e0f03a762c7ff60718f29a1dd4e6d351c0ff14d38f7845aaa568bfb9e8a5efa852ff0b8bfc20d
173	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	96	\\x32ddaf7d483ff081c96df75639198f748710b144354fd06f71a0fc3cc2c0b60a4fdb7863a3cb299a07969c4f9dab0db37429bdfda20aa2f7e9285af0b0052600
196	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	205	\\xca0b673908cf76f8f956c2667f6df7f07e295d8c9f0a9cf0fda702a7f6a366bce41d3138a69d4a768c160c3842f74a11e731e707c7801ef177f6c24cf640590f
199	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	172	\\x5190eba97b0c3bb6a3b7dab85ed7df7097ae909290c3ecfcdfe58cd41631d8ee0faeea0736887e252cf31f7478a3605390e4da06b8dda44f238594a4b2e92002
220	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	235	\\x73520accda4505b58899a7f00d100c3b9fb0fa86e28bf8718fd4a758d6524d3b5c4c4a8af6277e1d44059a1e7edeffe3b11d5e7263c0ad61f6d0a44c46546205
224	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	131	\\x00db526d5ab14a4030ee848a3f573b6eae9a7a377a5c85db713e1c89e4dcfe0420d04785b9b01391a0ada1dea04f985388d64a60edda6aebc1ffac399ccf4b06
255	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	350	\\xe55ea10bfc2d98392ea6291e5020d78db6598aa502601cfd07ced04e14a28bcb891ff9accf07043b8b88cd76780dc1edab2e3e0856044bad9d9635ea24f8920c
257	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	419	\\x90395b0e1e73504dc8a210848dbba7cde0683964b581280fb7f590060c61fe4ef053178f7d7f29c932a21809c9211530eff75935567dd105f571cdb98f1cd803
317	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	373	\\xe96280a87d6c195b0acadf5404c6f6fba0d7b6267a6976e20a78807ebdb0d0f341790975c29bd710f2fad98a9ec3366cbf6372abd9d5d745663e56b0ba506c04
324	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	342	\\x796c9befd59bdfec11f86bcd675ef121b02f585cb42959fea5bb4724121fbec3728a3c4c4a3c748c747bb8212bd02001848cf7b76f1a72912ed1e96c96b2e401
348	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	374	\\xdfb1d06123ea39c1c9c1f7ff1affbc6243b3a1ccc8980def8d7a5433898b1b155003e1af89e5e14340ffd28026bd91845f521666e93b2f31688df480a678a608
352	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	386	\\xbe99f377bbb45df646f026b69c930f2f02ae3a78122d7fa615d58e11c4b270ad93caea336bb22f7645c73abcc7b341a74e2b1b3d8264b590b3c6b6a973d10c0d
374	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	380	\\x63220a39a27ef95acc2588da2521fcda756d70aeb3ecb0d1e8f6109094df02083aa9bd3e8fecd8dadd9ac78c934e996133fc6210b7b7364362ff65b5476ddb08
375	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	297	\\x91a6b71ed0578f94298be262b68d8f0235b6f8ca43bee2692cfdd65028f7214951429bf10f70e86f31d1a89bc1bd8035ae4dc9ecc4f525a89870fefcb3987503
386	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	35	\\x8c337f8180278fc420c526c43b36749f1f6a4769f972dc39e22937f45f3ae44368f21d5d6da519440c753113383e7192185b840d4ab22f64fdb7843169eaa506
392	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	413	\\xd79bfd61142ca9646eab1045dd9b32e7048fc255b6e90d12fe786b66fcb57a9091dbf9062758ad577a151b5883e35a6df11350757054fbc6d357021683fef208
56	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	234	\\xa0d5a717f892f4138722ce376d0901364e0d58cb0387ca8408bf88c933e81a08e484e18ea287a3117e361e1f82395ea0c49c996073b9309b5e91ead368dda305
59	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	26	\\x516fb6b6db92bde6c26f4e5611323510b6e9d86ab733112c0c4e9727fe86d26d0ee3219f9fcb1f044baf085e9611af63d5dafa96f182984967e89669cc2e2c06
66	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	247	\\xfb21bedd31fbf4769457a806cf5ef9dd9ded5d314ac00d62678b79feb64d43a27dc5668a45f494fc164adee657b64e9b06551c49d87186219e46d1fee850b804
74	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	168	\\xeb197d6255ea73dc88e7483e5d981118bac6fa18551eeb1da601b5e8c8db4bca9ccbc4656ed79814af67e20642fefad1b4c0b66efc0ca6f1e9ae37e53247db00
80	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	398	\\x437238c02ef7d4b5915714350365ff1a23a3c43f8a299467d0ce8bf1791361bf7a2d08daba26b727c019235f97ff949eccc2c7b79b1f2179596d6d4fd188ef04
87	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	359	\\xa958547d889c8ba5eb2d158561585b9ef8dc97c1a1bfc7d41b9d10fba9900bf2c201e0e87b940f30e5cb26f9696d325b5640bdceb0b47888a01158edd2f0a401
89	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	286	\\x244861956d2e48798d6074785086fe14a4e3faa5d003e3c3864ba450f91eaf82f91a29f0615f3b3f1201b416162857351a7db605a4c5bd01c1aeb283aba7270f
97	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	366	\\xe6a2024b2cff5cbb31941c444074d8a4cb874c05bcc292e7ba131a46f73139433be51db2b997f55986a7a3385427896dc9dc38c3977afb60f09d96ed721a930f
102	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	165	\\x9ed1a6193a5d4dc01e90a617296b3af53678a8547f5e44ae5929d44aa251168bd08cdd6b3e00fd687178e6a1c8fbe21bb408f9b49a3d5bc21971aea93e63340c
110	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	396	\\x4c1c2e6f9aaac6e3f8363ed9e390c302d34a595022c4a9dffc2a169f40b58b71264e2783e467514441465e452f6cf2d80d1513f1ddee4c0372bd31d8f197ea08
115	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	6	\\x9763b74bd3d760e2bd85fc2657bbe0b98aa1c0974e291482483c7bc112929e21f3694d9b02b2eb9b249e9881f130bcbfdf59a041cf7ef4041e04d3484fe57704
122	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	190	\\x982a28b9e5ddc91177730a06028200d7e230224e4e0660d357748d51dbd281bb25c1bfb48a5f51f00a8e7b9921db8956b8d1d06857a0252ce1aebd6f53e52400
127	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	18	\\x65a6eb47f2858c72d414beebba761fdec8a7f6ba455d89519c7ad17b009de57e14bae6ebc12c71c847a34a6cda71ebae0c81770f455f8811d16d54c0028b9007
136	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	24	\\x86ec866bc26e5b5b2759017b91b43bb519429a17bbcf00626fce4ee3432c7455ef7576dfcf98014c1531f257820ec8388daab026fce378f1c728f8d880a84b0e
139	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	124	\\x2ada41f29937370444020d5760c2606d1ddbf880ebb8f787abcf93695344df399da8a3dd4e33938cfa529a5243a7a0fe65c27e8af5c4784b9ec2720276f68108
144	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	411	\\x327d935cfdeaeb6c1220cf9dd6886395ddbcb79c13afc88c158686c8c6d7d33c48580c641e2a7e96dcb1311e60606f4215fbc6d6d00ea02527cea3bf7041160b
162	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	253	\\x379f248cb9a8aa056e6d9478b2de575ee7960c416922806dd08f0fa8605e97ac0673b0491b7661f8b4e63d6d88d74dd05eacedd255603b82d38151fc52c56100
175	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	57	\\x78da597ee9385f6e2141c768e5d616dcaef07011e549603c668fa91736462a3748017431be60635e362d17cc5ee9085ffb201e44ae40efd9b54a1df7058e2e07
201	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	138	\\x35df0c1d8f4a5a16c66c265136fa56e61db435f24e8820c46032b2fd92796b8316e61405d471d9f4a9203b4395975e1bca693adef2792343f824a76538616504
202	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	104	\\x6cf7a499a13f92caae274309a89065793fc65973f66c6724574c251153205d1d449d20ba1d285a47d175d70b32c23b6fa21258e1c3454c5f0edf465012df6209
225	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	290	\\x33e081fe4c2b10f03d7381ece83a779e5234e6d60c338ed4b529aa27a4c1ff0f24d538cb64def5962dd9787c0b76d90d400027842f7bb8522d4e5496961af707
229	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	221	\\x0f001a35b8ac2da7064511dc6edcb324ce5db36a3610dfb30479e363399dfc57db5003f16218969a357c14d6d57c07ac4c72b6a0cb6f2be229b2f3f484f7b000
258	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	142	\\xb1281ba1aec8741a2707a675cc78f4f78a4ccac4e2db6c1fc1edd680b75d09932680dc397945369ba0646c952f5d583a0850ea03ec376361f67502922d361905
273	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	102	\\x58384454964c8cfec971cd67f7ef5028c7124091b1b73961a094e993b75aac1643635679815164452aa6d0772a97d0603ecf36eb43624bbf81e6182b801cce08
287	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	49	\\xf639271cb882f511c26e336103c5a3cd68e6a7af644e7f92438cec097bf6c41f00c860b95a740d349c6b2109a18030dd0967c0ea16e4195890f73001f008890d
302	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	162	\\x609f8cea014ac037f3673f2e2627df73e606c910a0cc68f282728a677fb56f0d562bef3af061d1a4af1aed3e021ff25fd216ac2169162e1d1c670471145a0b03
318	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	9	\\x157104bf5e365a6e718f1d521647efa0cd45010d77e368d1205b41f765c689a327f677fe2499c63ba1744fe35d8709d3b04de4c60718b24de3ab7bb61e8f000f
332	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	319	\\x15ee0ec2e6cc5f62f1d7776a69c246501c8ca58a13b458a08ee06e6cf44b86892693e6a6dd4843dbf40b1a0a42dd8adb98803af2055aeaf52846269252230405
399	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	89	\\xd1700420cf9fb5f95be852e1012c2e6e25831f09d10a4aa32fc39a5a45ca98ba8f1f586f1f84d6e6281cfb496453fb4f637311b9c6966398b09ced3f19ab7909
422	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	159	\\xe86691b68de0a847266ec6863247e2b3ae308aca9b65d23f7782a02a6760623b77e1b9389bfbbf80fa6424166d65384bc7fea77847d753b2055334aef7c90b0f
57	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	23	\\x0482639b0ec22a658b628133b0d4d7bf4eb7e56ce5e429ce6aac93ca1d7aba7ca41d2f85637c0798bee26eb4ea82f97aed72289dbfa404a748184f88c73dcd07
61	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	341	\\x0c18ed3caf47e3ae3212df82c699887e1aa452237adb28360ee7e1a1146b8f3c49c072edf37056189c7465febc2cfe267058a61236f9d5995349a3135d783b0a
68	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	73	\\x7f73ef64913fda61af4f39c411c7bd7cdc83d7911f52030dc78abf8888e54e25a40acded63e714c7069f5f7fb5e77d735e5cec71104e021b8f503d04b282120a
71	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	192	\\x416bdb11eac86d81e7331ab52dd60f3289347e29dcdd02ace11bb17dfa235271e564b6defaffe74b347307f18e37f14bcb813829e51b1f4b71e7c6ddf49af90e
76	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	105	\\x81e67f0b905ccf1b6453e670daa667b99f0f216b18116c7c02109c22d436275a8112629e5e0da3958a33ad9efdb71d52124194db81563e43efe647bcc0e0b400
82	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	252	\\xea3cd0a871f3ac8e566f7589c7bdbf23bfd98e464ced699da2f5108ab221c6d0c5c67c86bee786841eb6cfa71bcacd612202fb020734c88af41a60be75b4f005
86	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	50	\\xf6b4b70b605d33ec049da99b09c75cd2b24fc71a17799a42ed1278e3f6a727b789d88e3ee019ce4c405799f09f5d8aa8898f883eadd550760e73e03f18577805
92	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	240	\\x3675f233714b70d865f7552cbcc0a605827dfce8df08b6d8e6bb8d8356d56a944d79ef5507c62f073e0694e90f7a1f8c84df4bb20de6bba3127fe9b02391f308
100	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	402	\\xdbc27e695b3d4f39703c82d21279d7427fc16d981eeb6adafecbcad60e6e51c9701a804e4d9636b3edaba568006693d8b7bb3e861710b47296d7e75364590d0d
103	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	86	\\xe314cb8ce294b8cc028dcc6e135283100959d068d4bb9f7de23d68c0995af8f751af698b9449568bf7fe96968aa72316995c79d98bbf6639e98ea603067efb03
108	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	282	\\xb496b0b1914ad0b84ae4d55a30b22191cc3851aa7557e37baeb16f3ac883f571c37e79e27773b880a4788ffa9e8eaacf4109fa75b88817a2825e32e029b9540a
114	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	93	\\xb9fe5e94eda192dd3ea484f12cbc71a84d89583c87dffd7fad95fece4ace1a563deb1f9fa128677919d1ea62cbadfdf8c7864fadd97fb29ac7a2a8b70e365e05
123	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	128	\\xca2db4991ea2b214286f0869952c286b8f660d5ad0dc73575c2d88fc7c055f076eb7bed85427c0cab55af57093625acd1e096c470aa22ec372abe9d6dadf550c
132	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	114	\\xfabf4b2c90e0dd504ff1f6dd03a6d2b854193c4bb99c3a23679ba4fafd96d44b8e09c36bec9be8cd3c3a45244ca1bdf198877168239dc2c34e3951d0e73da002
138	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	88	\\x9db0a2cefcbf918464de98b7834f7058627f252e637fbd2e2bd4fb9bb5d363c0b0035f0a7598bf011e70ddc2a2ac8a8d7140c6417c28cce1a241161a796b4404
140	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	410	\\x0c17aeb8f7a39e447275ff0e32e943a1fab7404488e4cd9c2e4cefd46a94b3a7c3814c417aa751a8c694e7a6808eea8c5d3e512a9b96e14388b2df6eb382c10e
143	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	108	\\x43da16654c6fb6913f2aeb47e733eefa242e0dcded0f163bd935a897e93d2a56859abe54cfaff00e51eb653495b993e039a369464592c2df06e88e0f0d3b6509
163	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	15	\\x42de35f796e5ddbf0c9e63fb6c0c10d193dc6a031dd7bb38df922d38d3ef47dad4ff7d0a2cccc99daa531f949784d1eb242bd5d22d800e581ff1a62ee4d5ff0f
171	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	180	\\x161e9d4cb74664fcbc8f42701e83d1c75326aee053fff34f187ebfe985e78ad940e2efcf196774320ed2f60ae31116466e308d3686769e79383766773eccbe06
177	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	21	\\x5259966f5ca175fcba7110a18fecb87153cfa9cf4a929629fa3d363cb7e8e846ad4ec5dfe32ec1a5b265918fbaaae891d5794a92fd3cc11b5bf0e2c2b43c2b04
191	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	420	\\x4a3a5346ad11e56af633ffe44a50d65c595461032cc309270fa8507fb7693cb4ec5bd5229b848d9e15e70a4656e6df5c0a97b74845dead27b4169b711019e008
209	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	388	\\x7ba474b720e15d24e42a22f95c128420b0dcd05c9705414ec0ac5269ce18e4d8aaee774d9246c74200ff4c9667233d3a37d7d5f49a81ec283ad0123b9fd65802
221	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	178	\\x17a05af572651004cdfb95d05cd3e9ff96944d866e445df2c2f73e481cf6d4960f1febdc1bef2e3e940ac6f1b9925575f835ec277f25fe9a58bf380f72c80b0b
233	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	228	\\x9f4ba7aa4b24c00f58ffd0456bd0971e1835af19f75a05322e20515cf97366ad4032b7edadafd3b806db93653e0e8cd7ca5b81c939f3bf26489efeec3166c009
249	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	207	\\x5883e6567386b703d2ba57900a61b5af0b21a8faf73caef1260272fdd43fdec209a6dcc8a648eeedcaed6a4cdc3d56083c1469a54e02c1429056fb7ba6b89d0d
260	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	161	\\x5257cc3160478be91e69c826085366710289aeecbd997d854d6cab4d97aed9e9da2fb3cb847ba8692ce47ddd8ab0f05f7ae523d2ea4c9b29dc3d86da32fd1001
282	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	65	\\x7de9898add8ac298a773d8dfe58592e690ba36432ed0fef4c33b3df856c62c1be374bb1df07e8c6ab8f118d127f0f353e6fbee5d5668c6bbd6ee857be9aabe0c
330	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	370	\\x9b77dedba748a14856cfb46921cf782bc1adf9c03324bd5e5d7a9a6648c60a235e9d59a403dd975f1a03d17e9628f3f2360a7f987a52777783476d7786eb2103
343	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	154	\\x071cee81cfe88c168156795d26b006151a063ab598829a8248e699ef5bf95279bfe1dea1dd2e44070a51da137984f7bef31ffb4dc1745d7916a2d873be09a805
345	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	278	\\x11457e112ead51e2ac67325b48c1b81429e2055b77c5bede0fd5302c087d2cefefbdfea673831be83cbf22bab32e1def037f761e983a708129b5aa275c2f4e01
369	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	244	\\xc873cb7036608c4d1709342649bca06b4da22a0578fd3182365f9a7bf8bf2e909cc414c95da0bd95613725c476787b10677f2f918e719182df5de33c7f2d2d01
58	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	51	\\xab9cd779becc1da03376feece24efd9412bd52c1f985ef20e2ca9b7c70d2599c2b8815663565d4140d648345336e2614878cf647ef62ac8344879b321a8d5f08
62	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	136	\\xa463fa851212def2336735af9c4adce3d9adaa6ff1464c3da000201e45d0895af866b6676b764709ae594712b9fc4e1651d4b30a9a219e3bdcba8890f75ca20e
65	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	139	\\xb795f97f632eaa12dc936b0d992577b7162823c870775c1e35e406989508faba0b1c918d6cc1fc3c5908d93b33646a2581327b851789cd5687c1d2e4b7d31d01
77	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	233	\\xc6a2e2227b55e5b5d1f25ce144ee75062f78b2d790e17d462f9f68f83260f4007a0c188556d6f28e9372d49f87c16825e855b9d625287429337ff6c9b5bab900
83	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	274	\\x2c2e2b53853efa81b9e4c0c76f1e152a2e042a0d1ffcba8cb6f7538be5fd5265e043ecfe1025951e6d6fd0dc09d58c434064b20072c891e06967dc44ef0d2d04
91	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	377	\\xf1d986e25d23466b5293255e8da68351a5f38027b2f11d1c02e45b089015379cb27150126cecfedd17227a1a6a92367cf323e1c4df33d9169b9e0cd6a44f0706
98	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	111	\\x00ac9c3b3f03633d5ef1b3dcf64d1fb9e1b1bc7e8ed7058841e76be33157bd189e4cf4f594c426da6401727b1299792941ef7e0e066018a9a8f7cadb0f9a1e0c
104	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	87	\\x9a66a111280c34358a3dce7bf41af28d8a9a42cbe0065a13e56e8d8187e43d19b11a6f01d9dd3d46a98638ac2f88d2b72a94fa9a68b8d170e3a33729ba58b90b
107	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	347	\\xcb4c58f49e8f196dd833776af5f7fa3e1b5f9c942d2399c681d7307cf0c201c0b93c3a89b449a94a52aea2a12eea82636882c313ad16587d0db9ec11da85830e
113	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	412	\\x2862183d8017edd0d03c02a7777ddfe0166fb4fbd81db4e85023caafbd8efc8c66fb9680cb1f45b4fbb1c1e6a5dd9bcf38b1eba78528394e481ed119ad3cd005
119	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	186	\\x266af2da273e8e76fe780ffdc5847d723c2fb48eab0f3b5ad17d2aba627b59d2cbfdc4a1827d70f0d68369f0c82aeda2a26de589fdbb4b0092b653c6f6da2302
128	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	268	\\x07865fb1269c9c3523dad8093e3c8992b6d1fc6b40dc70c8dd0ed435ebdc59359697ecad2938b7ac952c387c55b60695f87a25ce802af36c4962f9a6085c850e
135	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	216	\\xfb2a2c2a2986923a98777169877d904078d266b5132acde3167ea28b5eddaf62a0643b6d689631b51bc817c04c96b6117c667dada6230f3b271849391528dd00
164	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	116	\\xaa977724561f7d6f2791c0e0d82108e4a62b6413a3a3e1e0baacf04a22b89e7569a9d3032af3639a1ba200d1d95245ff06bb4377d439a8841c33220ce9080907
178	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	174	\\x8100862d7b7d9fa907479d7d0856676ed1e172285ad80c1170eb4937efe554c5adddce4c920828ade183732c0ac943d0c06797bc1abd49e405302725de926a04
195	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	276	\\x5f4be4af0d3cbd7dddaafb6e4dec488c1c2bade9ae5791dcf1cf13a53551e2bd1a90b9cc32bb698f83aac327348fbc8a11339e02c881efbaff184208f0db910a
208	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	345	\\x37ae69e180c1d572b0ee48b69e96da803348d2142d720909850cf882cfe4e217a486239797f959d5f247f05e875a16c9b8fc222100ae4f48222f89ed0658ed0d
227	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	302	\\x15fb576253575a5ce01f4777c8ab603bdf586e6ad14cb033afadcac29183a3f95a6054ee1a4b59104f569d0740bd2c8227fba9115f920d4318c7fa50e0391100
239	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	158	\\x2b723e16b772e1afa89694c72eb4d21ed7b4245c15abe2b1b869f3b7c2fbc64a0148cbf271f3dd245ef0ddd640ca5a2a330613e692d3b3ef2512b3ef4a7f2508
259	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	344	\\x4d216c55c314ccd6fd3b780929757334cf6944dbb785e29b3dffe6daa3564a4216ec4d2a4c5a32767eba8b411e8812a65f91f19f4eaf25947ae4bd14fb167d0b
263	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	293	\\x99cd7fe621a0a11e8da4f1fcb64873af676e4a4097d0519cf297cc71f297c2fd858381a11d069f45786a3348eb0c20c10d46096f68babdd45bcacaffe259a40c
285	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	395	\\x10007a78de58e621a63969f10bef36b90cf5641a0cae3a01ab6a0fe98806eb358d338af217d8164d5166e9c3599087c4c0a97f68e7fd12d8d4314daa3ee38a0f
296	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	47	\\xae82dfe2579571900a77bd34981e17a1c3f28804a4bc093fcbde70ee20471167ff077d4648c608e79531cf84fc77eadf698e6f95c5af8df0735fe5dbcd0a280c
320	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	101	\\x689c05e66ce6c2fd9cf60646d2055f6730c20bb5d74181bb92a57f9cf1249150037be6542cbc9d467d9b297010dbdab54e2c0e17c17085314052e582cb5aea01
338	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	225	\\x4f36edba026ba47dc95f731ae93696a4f492a168c58cb295829b643216cd73ab9d19e120d9fd031fc43785f836542dd1841c184d6a036608cc5f01419fe3ac04
341	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	248	\\xd6ff9e8b627528d1cf7526317062b021cf6965c5a51843010292039b6f558e9fa2c8872738575dd542c36b86ee51aa8ad8cb52673854e64221340a0cd7969f0f
356	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	5	\\x23ade95a2c6997a10f9fda35672d36948d7fa050ba34f8c85cdd06ab3dcb8d8388c2a0a650e990fa512462a15fe66f96a36015b973259554b869f23f4f16a701
357	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	191	\\x4e7652eeb149446326dce7eb94a44ea5b6ef74aa0da73fafd4ed52c716376d3ee57f3b6bf6efc7e8e1c18f60c1acf92bf36e92c5c4196593e2118bddb9861d08
370	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	407	\\xa8919e21d9fffcebfeddc2d70387ffe15786b133d85d927f55ee08ad1d2c342a6af9c64c67d169a104920f63bacff3a400e3f56488327e745917bb98a9bea70e
379	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	85	\\x24bd6ad020dc6b229d6bbcd623a753dee86837f1d36617f23d53627bfdd8aa512f1032cc07ecfe5175fded70483514dda1f2711719e4d1dc784b3747973d6302
387	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	82	\\xe0c8f7c6e02ed211e727290abbc4fe6a783283dc6293597127bcee925a50027465ce522508c607aa7e3e1ddbbdfdccfd8d8465937385cd1c41a84ccdbdb95e0d
423	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	230	\\xf741b94c9685b623552a45ef0bae12429876b2d3166633f8c916719b070a359b0c68cd2201637fdf950353442c571c8d0a4c7edf458bc358cecc54f3c0841d09
131	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	91	\\xdc6132fc259d0037799e4e1a00b796da7b541e0c24f8388d6e6e166b5d905733a7d7cf8355ad9d2c7d0e1bb798d703beb6a1f8308b566db53852277bab3c5609
142	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	362	\\x13521e78d8138e792ad9426d3c41b11ff25abfd443ca232c54ecbd2c6be1fcc3b4a397829c7cb2ee1d4832f3b247a867a924cd012f8a75f4c6413d9a6ee44c03
165	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	255	\\xaf5ecd8434b0b658c3c942958f281c36871115af464e9650a04d5b5bda7e4546e55c796fe27cb1f7c9aec13b42e34e913d840be69d14937bd081f8d8b0cb8907
180	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	42	\\x935409b2326fabf93a53bb217d9686048a7ede90f717764a4d8ed9bdee717867f3129f9f1d5edd996084ca88c401bc45463920e4e4632890ce372e48fcb8b303
205	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	160	\\xa4b02f559af4c5d5b01d4f30345f1af31590dc7e71d159302852550880782563f4d42a21050c26b08d2281f74dee14157258e0be078a5afb49ece87c32e00b06
212	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	326	\\x41c88eb5d8e75cf952af3a5ccaed6a7f1d359660cbd0dee934fe8da73b078e37c8a81f52f2c68c8ccb05c23dd575335c29df78a3f0196e597d76f965c50c6505
238	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	145	\\xc0320d786fb4b781e260ef47d2b64cd689fa762b64eeb21afb663745f06c059d3f7e612c15657ac92a1aa021eb73dac51298938c987c37356df9b03af32e8108
240	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	401	\\x0d973786d0182ed522b566e16dbea5c7c836e8a8e008599b58da36b859ac51366ce5cd15287df1ba5c818590c205c2712a708ce8d0b5e355a8866d921932fa09
261	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	245	\\x235513784770c382cfa08277213e63f1b44c5494184e4b630ee7d3a7f5f513b27ab3188b0b3767347cf6b449d6b33c16fe0be09c0e176e9f322e0511cb9b2801
299	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	283	\\x38fa2dfe94187183dde165da9546c28b1de55ce523e9dfff21d0fd9a08350933ff88fb688d9860a264942e16fd42917ef2d8a36d8e72ab537074219f8d370f02
331	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	229	\\x2ac19d87424d70e60988f455544a2775ac6755f538f67911c0c19d3a94bf6b7f6d2406d1029f55250739f208ba9a50f20d8f931c629eb8f730f133b52830600b
346	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	126	\\xfd9fba625b57c985aeae6020b352b000bda8f35cbd3ed2f1cee6dbfedd238256a6685a9ac355a70968aad721cf75712ecca346381b9999bfa6665b0732cf870e
377	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	231	\\xfef6bbd44bfd71886376d6e4ecb38ede42c43c302d31935774a7576a7c3fd0d274c921ad08414d7ab5697a3f156d1520a7fca100b99e99a73ca40b1dbc0cb102
406	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	337	\\x26944e1f3aaeb874ecbe1fee870486868f7b47ca6c17b5020cdf2c60213878004f5b5d7c8af067321a68d3db153b2d9eea37f5c5325fcdbc53a6a483be101a09
417	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	20	\\xcbd72b8f9c4af069f47323dc436659fc9ca367df3c258ede6e480465107740a341ed2a7b5c373ea0544cd27dd23e1158cbdfc155faa1411c42cc3ff61ffda208
145	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	60	\\x1b5a45e409b5cfe1e6dc95f5c1b31f52f226eac92f199e5f75c724c04784c8f268555835b5292006db2ee75d95c5c1ad5abcbf198c278d87584143d85ae5e104
166	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	163	\\x8b943c34ba64f6ced8484a3ba258870906e5c028adcde317efe3565e9234b0bdcacbe05d5088d31366071905c978d0aa93afe9a0b00d5b5b7d74b9b588b8f60c
182	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	31	\\x6659898b9ad445df859755d367dc20f99d3179ff78d122196583c9cef4cb5d7b8e0aecd90d99f5698ecf6cc3161b73c977c85f2c1673428a443185b9969d5505
192	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	220	\\x2521239e5d404a571e9375c015f0fb29f0b312cd29cbdbd9352a70bc308eee5c9ba2af77a7531e3448579980442bd0ba1887ab0c76367430ea7fa21736e5c308
226	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	332	\\xd69518d14680149e3996a212039e8e6fbc7381dc9bb7f2084ad8fbb736edfdb416c81963c833853041f778c89e9e41039838eb453dff56b0fa9471812799b40e
234	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	75	\\x742a2ce3cb4ad0ecf050bb3497af1b4d0f6b1013d0fb3537f6433e556f627b0576bb9a56e62cb43d0e6cfc37da23704866b217220d9ee7bf500b856b35e0960b
266	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	19	\\x6a3eded130d82d3a2d627d768c3fb80e52a22bed7b1d70484e9bc25c70b41f0c4f2812224b054eec4a74c50c3514601c179db45d3028c501801cc983be68a904
272	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	249	\\xad356f6afebcba3cd616cd2b28895881eb160afd24e833ec804b1184f5c8d45dfbbe904781642be140318de094351f680107b944fb18335e856045d12fef2502
279	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	200	\\x909c019f22eea1452cec5bfda9b304badb502370081cfa5d03c4e0a2212ec32792995de6857f41d546806757d7176c9848f2a158da64587a024922d7a1130603
288	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	134	\\xd710ce9ef2d4e9905c8930470a1e16e2848c629f7a65e6c6cae6b3eff79969282dc52f61095d0b24fa038a271c890c28bf25ac4362cbf1b00a23ad0d0ecf9609
291	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	212	\\x17cda9da6cea9d67f40bba5df1f9830d9b7dac1fbab957a9bc3516808632b4ad0316bc667adcc7f82bafea7b565d03ef6301b437356d313c4faa32c6ffecc80c
307	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	32	\\xfb62e5022fee27740eb190f62db4d2ba0cfcc2b7e13d89201b97aa16753cfdefd8e43989186c5bb3142d800b864d17102b6e3bb9ca8d37693e434bbc93f8d90c
314	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	391	\\x254275bb1c02623995c0f1f5e7ac761310ef5539371d3dc77a0d7fc11a0ac6a4739c7cca9ff5701995e7ac194a84b4f652b9d8a0e050a0a95ccdce660c8d9409
325	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	167	\\xdc5e106c12af39ec9aaded15afbbdcc49e53a652a56dff07414ea1697dc12c3c0744f015ca072dbc4a828c276fc5b3bd2aaec4065afc5b21d596ceee110c5a0f
329	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	349	\\xbcd00a68f72c857881a44020c9b4190daeda7defde2bcd7ebccc33cd7e3652e2e7926dde5cd232005bed11d03f6672080e644b00bef0c2f1668258977104f305
372	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	2	\\x37661c3d855944d64d4672783f7807501b4f42acbcffea890563ece978a0498d000063cd776076c4d7dfe5ff20e331be90bdfa99df9d9c23ef1b5b9fdbceb203
373	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	336	\\x4f35f654e6a6fd1a7ef3dc468f0bb06605740b031562bb1680b1adc561aa3741aaa6d28c8e2fe453fd2d7ecb6f4053bb9f97210335b4eb45c0d5a78fcab67606
388	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	299	\\xc82a61f573ed208223c414cdaafce9f0244bcb7781b35badd28eec1b9820f06413022f1eef597f3918887cdc89587151b7d9dc2f6d353814173c457ca2531e0a
390	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	260	\\xc16a005517039747465f090a12e86d5a54718e91b65e883eba738fe231a44bdbad7b6051396c19acb5ac02c640c29bae4fc4e5084dee251da0bb2c544f70e104
400	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	273	\\x5a8f5c5af0e1cdc6942299ae7a349df333b925ce1d650a42b6912b147a037f645c1a6ae20f8babcb6f5b5f41e1300cc7d36ef6d06256e14f245f9339bd12510b
408	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	288	\\x942f8391a0caa8ad84f9c19222601ece87c6c88e43362ab68e62dc2ee8b3688570222feafcd3ac9eacc4f209c4536ea3162641cb8b53b4020a2f7ec23bd5bb0f
146	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	54	\\xd4a9b210a8316e00018e7bb41485a10f3fdca89d952e5cf7dc668d5f4a80ed994a48fa3d6162b94e1a4baaa6f0777ff442b1356eba1a0f44a29f38bbcc275505
167	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	169	\\x5b896ff4bd90eac6786b1d1e20fc050a700861c6507eada5ae957420f5543961196570b0f0cd27a558dc32b06cb969dc9a50e4989955f2dbbe408c26726b6902
183	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	403	\\xda4bde987be2240fc2012ba8d85016ed6427c2c78717a14476fe2e034b7dca233a9709c239afffb48dc5ab0c576f3319c33c77eee7db7fefc633eb9d4dcd2800
206	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	144	\\x1fb85c9c31e92976d11a82551e7ab7fc791b5169f77fae6ba46c4b18e328e2d8492e8beb97b3bc1c536f23d9d25cebfa7f14f85ab616e6242fabf5e3d4672107
222	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	55	\\x6be1e5bd2e6871c8316aebaa9bf13c255f3831b00af49378b592c518bdd2e6cdc967f49959b3945658b8cee63931cb9a8d7522b4488626c9e2c924251abe7a01
231	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	382	\\xd337fdf14f78c2c23127a6ccdb969a0eb278ad13b8dbc782d678092bf239fb4860800259ca9a88af3cb363351feb169f01632ca08e24df21f0ba6dde7fa69808
245	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	46	\\xf9f253128a45aa3957649b8d50e4430a00e266c5c0f73990ca3807a4af7fe67e46881d61563b8a9a1f73842231cf691288e20980d7bd744ccacab8fe9c0bcc02
250	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	376	\\xd7f384abd42eee45296c105e3cda6f9557248bb494857501a278c9e6c361724abf219628b394823692bc66fed89b0a8e481f5ce0be4d5c7c3893babd5e88110a
276	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	417	\\x72f509e085ee37be6d911f715502068d4eeaabc2769c9e6ecb736ddfa269dfeea72c5f0841a9dd62c39b2f53cd87b5c78b2a925f3ac7cb9a3d701006538fd304
295	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	37	\\x8a3aaa1c7c8972da52f2775049c1afc0894d4d10802ef452d86eb71eb80cb89411187c927fe7de48e352830dc9b9444011925c58e6fc7270cfb97fd0eecd140f
312	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	71	\\x907944a1034ec2849b1acd0799fefe184511403e48539bf34f091bda3a9aaff65eba9e13d918fad90c5599dbc924c5af8bde436b87b2f3a819187e95b81cee07
319	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	383	\\x146c0090ed0d2f9c5346079204a17ef3de63ad97231d2b301d8db1e229147db163e9150e0235336b1a3ac502a55ee7e60dd52d77dfd9e47d3a7488b6ff603f02
328	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	339	\\x5fa45121e7130addabeba1ba5f49997ec9662c4e9cd1184bb65f6e89622af4cb3cc3afa56fc43ff413f9663c8316fb618f459842d6ac920470b03eb31d63d60e
347	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	109	\\xd48ecc66474c8d08834354575c0d0eaa81d9f9c16912c101525346b764d3166af0e0784835db1f44e5b65484755b4a45c0413407d53352b61c5f08f798a70f06
350	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	405	\\xb6d3c7fda5ae5423fd544871013ffabe48bc58458cdd37981434286ef41555b987421f6a34f4fe02d0ebb967f7743930b0b9c376f65e75f91f94be50e840e401
360	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	110	\\x151cf3b65399c8df8c8a51a45b136bd24ed1ee86de39cdeb7b260a07b0dfc7f9f4365386341b10720a6888462c5165021672ef098e30c6a3f668f92a47aa0502
382	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	381	\\x5ff119504aaa88f6528a629ad72332ed98d8a418130ee8e9d2ecba8a9309bb6597e32d3cc1b6d1cafed43fd40ea9a093de2f400a874bfb0c751f5651c39f1709
398	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	153	\\xfa2ec003ccb48b335e850ab3905ef75aaa72a785022ac015d1f0b4fee29ae6c15100d77362971f3498a4a3350b6b846b9138c7cda80fe2bef6c93dfbfa99d303
409	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	331	\\xdc13bf7c16a07648db74db34402d3e75c83333ff480c0725f1f4edc83cede9bdbeeff8990aa1fbd6f552a6bece8c3381c6552d912e71ad3619b0b1f557076500
413	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	204	\\x5f9c793f7d1b2143a1a0baef19c0f7dc617400be1752196691170bef102f1fac5c9a22a47147517faad7bc834d0e72eca6789a0282fc40d33f840c6dbae0f003
147	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	269	\\xdc57858b19c3ac866e992b099a332ddc9dd718712d6ef1b923dddb320fe5d02b783ea2e253f5dfcf7c650712dbf067405995862299402cfa37ccd3409f01d806
168	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	226	\\xe4db2212e4455e03d3669122b902a4afb53bc7ec35c0bff150a4549025cef375f591b1d0c3af95eca95c193b38a409345b759857b1539e5d95c3ae409ce15b08
176	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	316	\\x7c61654882fb09bacd7ced554f74d5783d8a20098a924b7fc5339cff2f6b28d21a7bb6057b04663fd69d42fe6589013cb8f97422a5f8a60fc75d1342cd932901
198	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	404	\\xe147a827886b07757ef26810a23d117a7e12dd22c9fe3b1c4133ad54ef23a340e4f3a0de93617a2b172672e160044c552fcf7b2b8326fb0e68ad7aafa4e0040f
215	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	177	\\xa06f3e199469ead8a3d246cdd753397c288eabebc3002b8209bb85ae5ebf0ec7e72da1c0b12ac4945a64733e11fd4492bc66d6ffbaa6f4613354ac41f5ab5101
232	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	17	\\xd9e3f261802d9853a05438e144b58b6ef4beaa6c84a0d49f36fb8a094f1f25b18a7e324720c78602080e3722c882a098b8436420766656164c44970a34357e0b
244	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	330	\\x1385520c0ef248d567c56abbbc37748e9599cd42084651e81d1fdf876b51401434df3e147c1b8f114396789f2ec642f2fbb1b17bc15ab7da8ec6d9dee317f308
246	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	418	\\x304d8407a36f1835c434c91cf1cb714c1945301f2e25ef2ab9a17faa69e20b7a411dd7033cc2a8bd25186879c228659b82fc2593d9a9db9232e910026f9e9e01
256	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	119	\\x0f6a4f27bcbfb0322f386178b3722d85c912f6c6511f2ea45fdeddf752fcc3aabda8ae508797994af938ace6b127f1ab1b21839bf7a02ba13dd3ed645fe72b00
270	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	421	\\x1bc30972f19664787448dbb8f0aee6c3a94e043bca889bdea7177e07520c6dd359b9ef802a93c0b79ddc0dd8cee163eb49daa1d2c24443ff2114dca018b14106
271	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	213	\\xdc526c66365da048e64551a141c4936729f943fba11e44598f9ad982d59f5ea71b08576a56638a3f362c9155f1bccb994ec9ccf20a1f7fa97485236d2c29a303
284	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	98	\\xa8592b0cc0acd1b1fcb9f0b23d447d0f6a9e65883bb7105a15133960c4432c3de1316e43cb96c3431f39fa7a9b870c1ee91dff21c64c3cb2bcf2f35ab10b9500
308	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	277	\\x7306c572244606f1794f9a5f4241c75fae74d7929d27139b0eb0836ee4b70cf6bbc0f4de7abab1f68c04e256d9ce4c898abbbb8995f60300f0f2b8237c94fb00
321	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	77	\\xbbaddd30ebf3e647191c2801d5273b6850deebbac3cd4d7f12167f6c2700d41157866d3e5250c576ac41ddd41318c015bba64edc4ef83fd125f74570c357780e
323	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	56	\\x5a840de18e2a80ef7d361681e38304ccba681d027b0e10b50279a823d54db78324c17745f9261935771f57a8ad863ef1e64c9fc14025faadb56ce04daafcfd0c
339	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	185	\\x85a5593338d8ffb6bb4d4840865e6fcc4676d6ce80b6fa58a57fd9f2c8da10d986cfeb1b4109f07e94a6adf69bff275f5e623520e51f8d1f4840b0806bc15e08
354	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	238	\\x9477c7ca52e32906de5cf7e141a4bf2b279592bf31481b21eda8e59acbb4c0628540b4925c0fd6eda02a29328a05bee6d2335be61fa0a86a2b4caf2db7a8ef0e
364	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	45	\\xf220d93e7138dae04cf3a46d93cb97c24e44e9f1e3af95511d4b315d540ed2f1779a0b71939ae62bd353690771017aa055b3db03d3cc058e71defe0da6898108
376	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	183	\\xdd61ddf831ce3494ae00049ea70d385fca23cb589dd83d76bdc8f9ef7b58e6aab7e5395e0f732de2af6f4c5ef65113a8d4cb3cb7915123099ad13ed800ecbe0b
385	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	97	\\xd36ff7397519c0ccec7fedaac44442a1bc059f44733a60b1f6df5233faff667ddc63229a46a429b2de3563a2e72ab26de3af296f9f5442eeccc6b52d18c89f06
389	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	59	\\x62fd769ae8f63a2d0c211fc3b7eb8524df23c5ca533f14e082127b95a85c45a582964fa31f991ec592b995c5983b3daec863a4d1358d592a20dfb666851c850a
401	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	22	\\x84d483ff34ab8968e96b53f47bf9932d3382254eab89791503afb144a3bd0787cfc9c2eb26b3bd3f2eec8ef661e0ef0ff0f0ea2410f802fc35548e72b6d29900
411	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	112	\\x8cd73ba46254fa0e32ea2a518d89c56b3c2026c62e843b5b6cfcb310946fb9c6ee980cae8832dfb61a1d632ab544b48ff36c8698289f1e663f0ff350c4815f09
419	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	327	\\xc852e3cda7955a7e8b36c216392c2931fe2c13632924a7a5920fcff6ec7bf4cb36d5e992d92af5111f08aa576978532da13e51c690d0850d09497f18e7f81304
148	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	242	\\xdd2ed951e187dd17cd8892f2250569b105b54e62c3687f9e1dc86612f971d85765adf5f8aebb5b5b88d6e3c5839254a1e2098b4c9ee92a2b6899fc7906aa240b
169	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	343	\\x21204b644a651790631bf03c440e32f496a6bcf72b01afad3e18ea97b5b43e9ca3f13dba66e691c92c49884e209e6856955b5eed543d2df311eadc584e531200
184	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	361	\\xc89350ace1d1e02794dc9f64dac3d6ba5a93da7ecc33002a501590a8c8c0b6e8ab24c3adaa4bfb276bd32f3dbc9db1cc2ef62755ad8d7a0e19345a61c5da6709
194	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	414	\\x78e6cdec15b201e9e203677724471d380c26c181182dd304211bac072dfa3c6fd88d6a5ff07cb88bb2a155d22d20505b61e02680385ca96d82302bee34e2f60c
217	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	3	\\xdb9d475e3f97e087aa57db55a042e6abaf44c1ca08b16880c6f068638fcb52b5a850f3fac0ca4173445710c0484391d37a715d1b1c93f60c2c6ee258881f720d
228	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	184	\\x70f1f6ff43ccbc72d9eb9b455d0e9157ac61366f7d1073e86b59e9db5efe900119d27137a92f494d6f9226e3aa47b157fde758504e7758509d4e69402218d102
267	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	334	\\x641d04ec2204a11a137a6ea066099eb42d10ceb99df9477e60afdd3808801e33b45b398ed1754719d6f13ffa4f4549e4121b2e13225671058955558d37c0dd05
277	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	195	\\x3a24ccb8a435fd9873fdf7af096ba6f091e18ce8f81dee039ddf53947028f410d267a5fc2d9cccea2b2338cd3001900c827165affcc5fe9f65cf266125c9fb07
293	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	25	\\xf065ce7937a728c3285bec7242f3af39327c85dc40d4c5a91e11c42a1c5f7b627bbbadde5433b322d2d22ff3302348d03a6fc38f0aa2184520efc197c2a0fa05
305	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	239	\\x0075e0ac0abf118ce593a845a9fde836c2bf23cb06b26c4dbbb3582b39531ef2fa9d9a8dcf23ff532f8281a2d68aaaf1e1631d3ad17bc728fd7dd308917f070a
311	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	379	\\x7050868c1bd4c92f6bbd557a94fc3c47bc6f4b8c16f8956ca883374c477d697b5dd0e4ab8d598532d30e9a1e1e46a9bc828dc7d5037a13029c521b2c997b490b
337	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	58	\\x08140f4d81540a1aca5aee49352dc853ff2593cac99656c984fb25533cf448bbcbb0810932e858060ed409daf791cb627771b44279c56dc17f54b68c724b560b
344	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	315	\\x1db5220f6739e5647953b916d425cac69c24247aa0c8e6e0fa931730bc0890675ce72e49c85ea43c6cbfa27c953c411a08b04b3dea3a5c06df398c455a4d0607
366	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	106	\\xf517db8aecb197082c83abfbe7001237723215eda0f3953ae7253da87903a3cc01e0b97b62358e2348ba74cefc3d7c5e799680b22bde8a702a5917bc1bafc104
391	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	355	\\xed55f1f89b1e3a27d73d3c0020981dac67c485801178c1bb02dbb30cc6e0f2b8c47e6e3217c0089ab95848570d186690bec1cfe1cc510f9136d506664b860900
407	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	298	\\x8368408e998494ca6c10375038991f2ad7d8e2426758f55618c60dd2542a31aafd083fc49014a651af5cbcce3b432fff3571c5db926c9c65a393f4d1ceeeb30b
149	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	358	\\x92e2fe7720e8b0c8fad2e0c50863559edb690181bef16b57bae6d9203f2e2485b00525f785e69d9f621cc833068785fbc989d5fb24c54a486bcd0f010234dd0c
189	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	372	\\x7bf8e1768367cb199fd67ef24ecd44a69805fcee33b283346fb55bcdefb2095ef3f3223a172acbde4a6be8dbbac0a36b20f7b861a9f05c20f12a2ddff9b73d04
243	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	201	\\x60036827049450639e795c5cd997da7e202204c88490966f9586dbc2aaba438b095125d6ae87ae79b168033b2425a7a47bb1d30c9eef46b27f28a9e26d299101
252	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	117	\\xb9bee345aadb91744c1bdeb5ad81fbca8a1832ed820949ff935cee9c248337fbfb6d66409d1a3534aa99faecc7ca084f1993a966ad13275d076c30cfa4c00902
265	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	68	\\x81ef5b62f13d63a80ea1a4374af21976dc3ad23d8652ff9f6fc606caf4f6a059f3b5115bb006736628d908373410340116a0e90b201d3a7b10ee716c4c14680c
283	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	41	\\xaadefd5dbdbd223e7d640d722027e45acfaef18c19b882b8cfac28608101e47b0797a9bd19dfb9dfbfe2e8a1638e5838c0f2097b7fa9405443a704e67e81ee09
313	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	259	\\x54017bde8ff8880c061cfb9c649008faf334f5a370d2f259e5d2ee36571ab85fc288a56f985ae4e71d6eb0038cdbf05742e8026d4580f5fab6141c4eeb585d06
336	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	237	\\x09dcf8d46a73775cec566a4ca95b24a9f1f0b778b00372a84e322d8eb6cea31f3aae01f806280d7b9d3a678f4cea8384a6e439248da2b5fe652a25112a3fca0b
367	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	385	\\xd2443a9c0c03b47da28ec1adc6b1900433175c7681ecbf9b7c0cfa4970b774dc3573131973e48543edf914e728193da0f673ee263b6cf8f6206cf9053963000a
394	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	263	\\xb3bad26794dcb4f14e0b4ef361f1bb28e1d65cbb24b991fb545a08989e22ea0c61f77a3307fe5bdf5817c734bb68d06c1cdfc37a271a7ba6694a142536a09207
410	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	133	\\x08713c0b3d19c2ead68aab71d903336ddfbee7e8fedd18952615cd652be15dd66e028ee8d9e513eef7ae55104887a51d2affa5dc6bc4b89b9f76237123c4710d
150	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	62	\\x37b8482cba833fc6c29842518b447883e37c1545609056012496c9eb7f76dd91afefaf42b06728ff7ebbec0969d86dfacf1c4f12bb7a4f4b76ea710635e85c0f
204	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	360	\\xc26623ef890d63351b9960590bfd14e01f59ee91d52f6b06de828bbca401f814cf70c0dbd43d9b31cbc60479ec74828c0f1a3fcba24735d7c88e0347e5bd4c02
230	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	176	\\x1941de681639933ea2fcae9170d9ebf5b40b90e0a4f2b21cac41837cf9759113ad18e08f8e3233bb3e1258782ec41fd4a6ec60e26eb35a695485b251364baa07
247	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	28	\\x9b39724ce067bf84f0863cebdd82539c60c2df559c8e5bb8f2069f7260ccfb3c66b4b75d2879a7d7577ecf8fc61613067b7d344acc6e6bf2f938dfe29810d407
269	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	280	\\x58881ce181287344babb3cc0b69c448469d6ea782586a3da95b321694e6bfc5b8e9a62fd38c3d5c17f8fe3ff8f9dbc5f6db3b4cb4ac6fcd0707292d42a6aed00
297	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	39	\\x7d3c82c9e8ded1f062e6160e893258c82b6351da61cad298bbdff75d32f1f63d87b2d36356409c27bb7490013919c40447a7292f8e22863165b3775a1454690f
327	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	409	\\xd414af1b23771217b4040a5169c3d98700ca97623cd5bdec0927a7078839e167882d247dc85ba17a77b81000b95537c1c8d9741aa91da0aafe50b996a5df8b0e
363	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	135	\\x8acc21ebf62d69b883b5181925573845373907ecee7c36c5d5508d35fc6a5ffcc0249faf31064ad5a64a9028062adcd7a7eb300041238fb02bf2fe420db0c40e
384	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	246	\\x9b2ac5783bab788e536603ba1f35fa93f674ba78b1948d6d6cf22a5067b5174f788f18d919a9025ae3269539956111a810c9c0e9e3ac20ed720cba7aabe80a0c
395	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	61	\\xd9e02f5d1cc65f72a58f249b4ee45712e292d1b768f2616561e970ae6ea985ddcc8b93ac2d1422a79b30c7a510ec058ab6a8b24c7e563c67ae218a5963a9d709
418	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	90	\\xa3be7d645da0f16499024c19cf14cfc6f5a57bd1c8af20f5310ba34a9546da35908b9109d514527cdd7809c946ad1aea5f0201d7cdf26411a9d9fa8986240300
151	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	371	\\x2929d656c747f739f0b999eea21103b236fcb0d4bd04c0dec8d98e5a0e923ae4623560fdf20bd70a6c8796889ca2a923b164b7f1e3f0c6f53540debcea56070f
179	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	94	\\x88274a942b372cb34415dfc66d36477152e7dd2f269441aa5f01cf5ee006ca8b068378ff417ff7b745bbacf7ccef2e7a900d816492bbb06f7c0fce7b9f2f6c0f
210	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	13	\\x388b5fa8dbad1311aede749199de27dfe80ae31d7b6522ead031817cf92ccb6c92430693050a8132cdd90c6daece98336509e799c4465de178e6b88b55c8e900
242	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	307	\\x95da5fd65e89e16303779a11112425f47f9796e16493b493e1eb523a79f16d73266b696c8400992e4bd798c7a5a275559eeadd3c8c2854347b1776467574540f
254	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	210	\\x84757314805ff0877df11ccc4bca42fa6f6640ac6a978b06ef7af935936b455afa21e2a8792f46bc47fddcfe4927e7882064f79981a3aca7418e91c6f343070e
274	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	38	\\x4a383ec236226bfa36b8c3eabf0c259c545cdf57037552928e1fa6d5e3ab827e3d57e78d929f361386a869049a8d23845fcae72ebe9166be237c42ea9f709903
303	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	72	\\xb7ea7ce7acfbef24766c38ed765b9a3f853da342cd1e334cf55f29baff731ae163855e97626617aa5e5558117c89fd3008887ae0df60ecb8a1b1f2c3125ac800
359	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	171	\\x89db94ca7773c93aafdfeb80b409e9e6fd5fdeafe07126b528d5104c92711b2832663b4a850bfc6db0e89bc4af368451b47de769893d79efc7fa2ef11ee3340c
378	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	164	\\x278b1fe89b3368932a3ea7689f69e627dd7a695c5b9c5295b2b70cf8dccfaae6c794078867994ba5d8c8b6eaab27a9238eab14bea530d36c883699fb11354f0c
403	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	80	\\x7351268f7557425f4a3f9aa7906a456e5f9611b0ae51a1216e5f2752e077b0249c4a6766efa1efea3a4ba8ccd26dcdc8f38fe0abb71f12e5c0830ce61f317302
152	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	132	\\x91c6a3273979ad734ab36ea3b15321b92b2f78e494eb6467f17ca4441d04d7955c1d7e30610d2fbc236b2d11ba96d70ccc5bc2a5b318a8f3854cc5503c997f0e
187	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	74	\\xa98605f72226412614a460081488f671edd49ed4ae08a473299b80e224735e4c66601250b52b97b96b919a6bc3a1558277b1c493764ddaa0b0c68eba5882e60e
219	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	267	\\x033d1530643d01b73472660731c00f745bb16717e3baff0a2ea0d4417a49ba4d51aa37ff494abad0a70f0771e82d17cff976f267e3126a4ca0a239ecc0f49d04
248	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	211	\\xf8881e68ad45f544f4e0320b81c17e248c14d1217ba1e3fce64cab93e439174696531365fd778839e05c85a37ab8c3e7f5098c4775d34fb839ac68bffff6e108
300	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	416	\\x8d05b44f53c615e3d0b3bc2cae0207a2592329f389b3e49040383a17ae505a05d8828c9c172218438db9fe28e429af76810ed4167821d5df3af9e7a44e9b7309
315	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	329	\\x3ba61454ee0549ecb9d91dab0f980db1b1dfcd0791a3988682608c13e6330140469b7182a427ac548c56b0938fbf496f0dde88fe8644f86f2e814657d6a3e80c
355	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	193	\\xc80e073924ca36cbaf958a9d94312a5114936f476676d0d7478fc991cc2c7fe622130b5400b9ae79543612386b1bdf245e232f4d1335cb021986f8f41e64d907
368	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	206	\\x49c76a2a77f0709a1ff876701d4f69afe9f1ec9d3eebe7e357b835f4fcebaf35b98fd673441868ea531dc12bd069e96218a07f751e480bd74a8c5aff9bba8f04
380	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	4	\\xe8633da897fdbae025dce71026f6aaf5beac37e378f4ee44f421f13dba53f3ce32cb9f103dc4677118094721007c7b4745c60e7025ee8798f595489277bfe704
397	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	397	\\xd31e5f9ee16a8ffefa19508fadd83310795d62e435db22e8fa73ce0d9762fb6f0321b9df11fec843ae8cfaab1382f8f39f2619f6304692d1acd87a6b9ae81e08
416	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	348	\\x09b1cb895d55fd4dec396977b5ab9ebf834b9186ccd6e08b957f9d7796a617205123ffdfbf697ac8704bbccc3e995473bd920811b0837cf815f9d3066aa5b00f
153	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	258	\\x3ef08789c2df7bdf09be3dcfb6592e5fe8cf2d89a98b21ef72437c1ec4d26518445562098c61f06391e1a8afa6df1582c05ac7b1da24a3260787db747729db04
185	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	208	\\x45ce3dcf888858e89d2e4949f242cccc8246fc48438c9072f1dda5df6d6ad65ecfdb109810b913eccca6522be9c68b0ef7d199bf8817a0843a130eb5a8a65d01
214	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	340	\\x2e7e92b9cc5983d84ebc62bb35a716eb1c4d77a1ef4be74c7ba190214cb1c9ee4c36e862dc63cf94b938077d08fd678a58c18d92fc739f32eb7e5811bc2d8204
275	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	318	\\xc1dc107de0959466b789ffb8d5042b07beb00994be88d4da658e6f989ef88b30907a08c36eb9ef3eb01171af4a76f1db4a3fa6dc9f88bfa1bdda0908b304910e
309	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	122	\\x343ed789a30cae9e26ddef74ada3c39ec068aba3c199e201b6bbae83b276baae8b9ce96fab365686fa5dfdea672e1332e8869b527bdafd60b1521dc0daf21901
405	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	375	\\x02f97b63cc9a1d2a2d504cd92f97a83f5a9f4a2adc42ba65d2e225a2ade5cc591a562da1b93b026ccacba3182b0005beca9a62c3b7598e681500a5a6b632a60a
154	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	392	\\x15aa5ed7c1acbab3d54d582da7993eb8fb0277a0cdfb72e492a1b42cb3544b259f996758102658b535956d4324b3a9cecbec98f7f8d997e9999348ee88581a0d
193	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	222	\\x0b77b1ec2cd37dfdcbe56ce46055f9617baa1516b1de3202260465f658d561a0ae575b1d8fa6314554aba19414b02aae94fa76700b772e7e3ca854e921af2c02
235	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	36	\\xab5cd3f7f5a4bff15021b302fef243849abf8a09cc0e9750ea5dfb8cfd8dd55922485144a4c3ec8ea76620ab37d318d6f226f56587dfe4beb343433bb8e51703
262	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	194	\\x8d9cac0e6f933bfaa0df1f3524f51be9071a92113cb89d46bd63f6e8d0dee62c7f0173854670fed58cc5f263e770e1b111ae08ed9dc0fccf7582d2698bfbd203
290	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	40	\\x128a37a2727f8f6fd04b40aff154f577d12973e195c89b27bcedf8a5e62f48595c81e6c81a192e8d37dc1a00f1c9553f73d40d33c371641b9b1e81cc406cb60e
349	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	218	\\x4c872e77a83a50e7723b2c7fdb0360340820e8007a252e567c03f3bbca90fb54620f9489fd7e94244a067f2377d90de6af349fe7178e549fbcd8f3c4f4ec9c05
396	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	198	\\x7c76984e71673125fa8089b75769f05355c01d5f64cfb6f6a07512453408ed7f665ac1c0fcf0f279ebd81be9680eb7b2267d85aa32c31fba08f3efcbd7806b01
155	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	424	\\x286514c3e6913455f7e2829f701fcb4fdd46f1984a872a2b1494eb06f6a5e2fb9fcad8dba5358a33b6389ae08f671c1b53e2562097b4c4d56ddb992a99e6200d
200	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	14	\\x73add41a0634e41c3955c7f71790ed7a4e21a8f1f402b54db2310e5d36f8fd88aece11b9517382fa7b415221618d847872e340391cabca50a81349f8fe0b8306
223	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	27	\\x870f214cc188bcf10bec820c651f0c97a92088753ac992446fe9b22f251197190e7281e21b482aecf5a206b1d5271372697791f5d12734e8e82a7ff4b611840e
280	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	310	\\x96e11919855c22460d24dcb6950e28b2a6360a3889416285925526bb10f2552356f13b558be54f1c62772adb1ec225c743b94d66db66ed80bc745963dceada07
310	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	147	\\xb0d9255c4b7add078d9082cf18fe22a2645af486a9520d59ad04c04bbf2c34df83012f8903b8ebeaaac5ddf99351141bd087f595853b518cdaf16e4366f6fa0f
342	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	236	\\xe0cb7e5f22703d4e34337c5f4dde08228fa6d9fc2f546f4bcd28dd66c0544ef65ac7de6d253292a69e612538f2dba098dc77ec0a1f2512ebb5720c957e554909
424	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	170	\\x96c6e01ae16ae75a1471c203e01e8a43814e02cd6c7e16db9818b0135378ab71ec466db4ace3c7ba5565ac0b3fb76b9c8f19dd03794d20f314c860c31681610e
156	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	356	\\xf101b78212234c3b5655c0db182d3bbd2c5702cca42e52349cde113afb1660ef10c3044317b7912837c2adf68c9c5db178392707746c360751d5ae562c23a105
188	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	76	\\x9be26cc302fa49f75d9d8b4038122d8b6909c4d881bdaf8006f2d1a2e90adcdab22fba6f6373aa7fb8addceb23d6ba0a7de341abe772d9dcb1410fc3edb2b907
218	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	79	\\x9ae0fbbcc1b28c519d6c6eee89ceeb15e16f6eef7e90e49779bc6ab808dff8b98b1133d9cd13fe1e8b2ae7d7838b3ea81a683af99895a995caea07396fcdd80c
251	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	148	\\x0192382bece7bd40340228268f9bb4f9f55c387c5ef8664bda2cd290f579dec86b94bcb84b18ad817cf4f1539a2867ab938d5bd65956f53f8fc80641d391470f
298	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	389	\\x51ac8bc8004f77a745bb615ed1e0cdb81bb41083dc1222ee530df47d878a9385475a015e251b36efd142e8f6eb76d4e98cbde9b92c7486919ffe93baa0c1f103
322	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	118	\\x385baa81b795a49d5308e8b9408c19ef06d249c84870e4b9370e5d5bb4b7935ae202a1902b92449a10f78348dd84d63df55c683575a1d4feda8cb272ca665c09
340	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	137	\\x283a5461048e62bae794b8a51ef9da17a30c8060f1dda53c03d311ab4b9fa81dcdc619d81d4691002491cca75368f8ad2d2131eee81cf81754eaa40ef5437409
393	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	351	\\xa8726653806b5b0a769640150895cf31293d0027eff04a873b6adfe31415b618799052f201bdc68f5c313dd6c3e2cb7176eff74f39f947f58607641c54621d0d
414	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	292	\\x46c158de57f1100386c08a7f536eeb84fea48d4b10117806c0f7a8500216c84ce1d4b34af428aceab8acabb86250159da99ca96a5d2ac871d1a1afbc0863c60b
157	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	83	\\x098e8c5eaefa1223dc45edd80b72630e34fdf3aafa259ddb3b201221da09cc974fa49bf5fa25fec72c423bcdd4db7b09bed4ca42d4807d7948362130004b6d05
203	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	300	\\x8650912a949423e13666385e571c4269b7c8cb87068890de9d43f6280684da10ad625c786a1b1b16a66b6ba16266855848df4b6ec79634b6686af113f607bb0c
236	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	34	\\x3e8f231e7e87aead5d0334a6b79fb58c2244801c5191206c4c14f169502480bcd8c32bdca6badd95daa05e2df2435db87b4111e4d5d0c2c9675f7097e7b9bc03
281	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	313	\\xc81c6f6c1644ed8b98a72b3d91d8350afefb56d2bcbd45d6ce64cda34b3412486fffcc6097a8cd47d1a0655aa8b61389e8f769b09b052314f672bcb9288fc509
294	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	287	\\x9ba46c1409b26dc1b279bb2985a130d5e6e09f5584937b8767d4b8beaa01bc5204c02f9f52b72154110d9d64c726fe0f93676482d994841aa89b0d969bb26501
306	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	291	\\x3c88a622f4b968469e90a62364f1cde80dc3008561d6aad25b3cb38899fbe3682df2bbfa5f641d1a5b49fa76fcb1890c05c1ce96f86080d41c079cd2fffefe04
334	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	43	\\x8cb1999e6dab57836afcf8fa6fc3e36469e645537519a257a38a74090ab4961fdc35e0f8a4ad96887dadc44aa32ac223fd6b6b69b3b1ed9cbaf495e19e33530b
361	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	311	\\x49d318987686a2ff3b9283182afc25f71a72babc1c5dd81960be1962871295a176c18c5357af89deb2ab95788301a43ee1a1eccaa5524f454890beb8a9f6fa0e
404	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	333	\\x02cca38090d031e899a36567cc771351a7d1ef643970122d4ae2219a2e5ef948b2711fe4fa9dd8e32f909bd3582a352375674cced3cc07bf9cd6895b432d4106
421	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	304	\\x2bab785daf009a1f87d40769651e9adcac0d7a35cb5afaa7104c136ab8861c5580b5490ed983024639ea3676639cf351d8114c3c026dc5558aa2dad1d497fa03
159	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	143	\\x5a854ef600a9066e8ec634cf279d48c37e264fd1f2fa161910ec4a33c70344d7c64c0ee0ef252c354fbe250cff2aa8cd0f5eaf0692fd4ada2894d26f1a660f05
186	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	346	\\x5047f6b3aa0916eb805e4a28bcd0e23cab902572800679737b12b911514f40dfc6be80c3fabe55ce7fd46725aad1f00c810c1c49a92165ebe1b026ad3e24480f
216	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	100	\\x1abb1a974989bb151cdd1569fb01f66cf2f665b0257a7ae1bfc452f72b60e9557c56342504f6146fc0b143885dd1c03ca7a0b7634b855e0c218685b182dacf0b
292	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	53	\\xa1f65c80587317efafdc7e94eabda7098a9f0264edd6472cdc357d1adbc1a11ba16196254380c7126db723504d6e4a31d9ae84a071794402cdddedb421fae00f
304	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	279	\\x275ab40140c2b15f807a50cd1bb72c380a93847a8bc86ac83d79619b9bd6c0f02805bf7d6113bda452c5f68425bdf09afe632ea304b4790e2b74745bb7917b09
333	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	275	\\x50763bbd1664febc527c182e940ccaf603b1b6ddd77ceff98a0508ec05a4e184a3f3f0a017628a77e173a7c6fca08dcd577afc09dbe32afd8b103f3e8d4c9f03
365	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	48	\\xbf92159fcc8efaeb3ffdf7ffa86be373da1b4ac1823cc62855c249e76d318597a66e1adb27446f787a2b5e3dd69b026cedc4e62c6d29e6d05df85763df065100
381	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	150	\\xe96fef4df1b8d5a4cd96c045e3b094e1d36f816c30fed4a91295dd6e1df7e37619fb85a9ada69a473db48f07aa04c5d913e1a4ef9ce83d25324418b075c91706
412	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	8	\\x827a1508674154c664b3305b2ca7308be0b34c61d8281d3dd2b839a274e01dca5751221fa7e5a01afc6dafe5cbad0690e80e193d13df2415cf85cc9f795c3a07
158	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	179	\\xeca66e2b9f5da34f8ae81c2a6c3869146601e142935d3e222a6d33762dc74300a86353a4eac8e8ff63f06ea004c1efffea26122fa4896202249882920416e00e
174	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	266	\\x8fa85c541fc5c691a6682ad0dcdc372c34cbefccd89d8c91f144b7414e190e4ccc6f637afe20839f7ca2ba2cb9b342df8e7967ecf1c5113f40c626bf3d269c0d
207	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	99	\\x548cfe10f496248ba48b350be94df186b9546c66a3c287796284a38271e3d074ceb68e8656305d28b97272d8da76259e5c09da1de4b3e1801ad7eda0e20f8300
241	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	423	\\xea79b369f1042a3708cf59151c7368e2053094ef4813da27219aeebb986743858301634645c3ff9bf89b1ec0000b00560f7cdffe0cd81476eb00e4385528b20b
316	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	364	\\x91e72787b6868a523fbbff6bc5cdea896544553b7f3f3a935c1dfe576d2963038aeecdb328d4aa9328c9fca07030afbf7142835df74ab44f6f0a28a9717e8703
362	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	384	\\x7acf967d3e409e091436a1dd8afb8b605d26af15bd58038305052c0bac5035a765569212f700c308b98b46c50f7906dc86136692a3c3ba8c5ebf5d194e64c906
415	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	308	\\xef4b7098676661c634691ae33a6ebfd794cc687234a401f483e2235270475ed388da6c8381e3de36c13961d1532dac5683bb71b866f95d6deb9eaaca5f748209
160	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	368	\\x2f528e69627991e08768ff5b9bc6aabde59a2f9ac2c7b01d0c19d47ddadd6ea7aed623ea1be6dea15ab4d2173f68aa26187a45474f74d247f364b44a7bded904
181	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	415	\\x8b58787e9084578c310e180c1773d6cee4ea9c2a756b89dba9d34b6dccdf34bf5c2d782f18bcacc37389bbd7f1353000954c4551931015cf29d8dbd147ed7202
211	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	265	\\xd0db0636dc1c88302b75846434f0e95b566f20cb1e285f0597cf5d6132b639c830140709d8298806e9c061e23fd9e461487713cd9fddb01599b04541b49d2201
264	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	67	\\xe0105f5fc0a3db17df5eea31deabfd075543f7a4919a23461baa78283c68f995ad0752aebe50795442e39a7d0e9edd49ea0a4fa7d10a6b3a350533a22a726b07
289	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	400	\\x1395a125a4eb0a40f321bc47c591fe1edb824e9066a2c0011a2b92253b29a76d950c666f4b0a6b8fa2515f5998986a1db7bab15f187cce634dc06aae1b61da0e
301	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	215	\\x8886111bfe8b2d8efde6079804cfe6a400e57e75a5f5847ac6381fbbe60159963f0f8a9ee013b3f81859bf8e7a7c33e25696b0a1a1d31cd23166077696f0f20f
326	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	81	\\x62e2af9bef1c0719616f2033f588dc37560740eec1c70d60ed46787d93589fefa3f7973302a3b074e7a853ad58a943149733d65318f5778b9fccb6882c2e0b05
351	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	197	\\xc67443ebb3dbc4c343ebf3b29f53c17a0d42556d971eb0b6564fda3c65a45a6b8f79a8a90d2f8015e624699c1141ef277bed938c19d8b62653c42c57ac10d805
371	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	387	\\xcebd9c3c0dd21d58f1b519a53dfa95e5767c9069b938874032a4f604c08444eb850d522c0ac4d9b686d7acdd796e6741d4167ec90ac3384d11a38815939b1102
383	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	209	\\x8f81ea4c394654ff5a776de36832ee4ec8df9ac0865180a29cf724b88faf294cac29353938823be1c7607e326dff984f47dc0c7e1b4c08f89bb396415372380c
402	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	113	\\x52e72e2f21fc3b84e241246f012b18ce86d12845aecd3540630b538c0197241d44f34c9573b86a932a2a9cf563ae090af14ff2a5a3fb9e21abac149d6654a802
420	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	140	\\x401e86d431654e8d0c90221e9690226a2b72f7f7ff0af2dd3b126613196613f72de0f067663338181d48befefb5270a1a0091d6ffc74df8b958f16eb88298b05
54	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	272	\\x42ebfad5088d450f704da6a0c13ee2e4126baf5e2b464b112cb778802375051e0f1cd48145c6e4fe32b89e8de092f0e69663b01f9a68469013e380c1c6323108
64	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	146	\\xfb635539a47e10acb6032bf1df2d5dc99afef3835a68066aa4b5991ca9b0ff3ec6736473e90b7fddf3d4c20ec2da058e9016554dad38fc3c87c8e63b24cb660f
67	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	301	\\x2aac4ee3666f317dd50dc4d2037410153dc13257fe506f29869e612ad8cd87d3ac31aa9a6595ca7b871f6c826e1a3186778e2f3e05ef337c828bc147ab7feb04
72	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	281	\\x96b7ba731098e601ff73f9a0f475c4c539d4ce6f854eb99e4a1fae267dfab3fb8e5a96813457eddb3920135c0a0ddfb4be73d32e62ada8832e04ab2d9d3b8402
78	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	189	\\x675dcf0d84c9124363852f1d07e6355d05f393a09a3caaca8d9c2aa83568d7659fb0e6b3258c0692c31ff86a29b6a9d1a9b9af7498309c6af18f17ad7e675300
88	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	261	\\xab2f482d139bd82b77d08e85bee3d2b008c7c8c9f8b7d75610deedf0dbabfcff5d0f0b70167c0aa30ffeaeb9fa425e1edb2363f3b8bb3c9bc8bc54449b56f002
93	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	44	\\x369d3ea1f91118ab098654930a543f46a2d039ee07d56543a1b57e5e17e9a5402a61e36754787daa2b131f3a531323064ab9a11ede7aaccec726b37c0922660e
95	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	66	\\xe71aa2649da1e656fd7a68f7e02eeb1eb3c93a5c5df382163d0ee423ccd3360045660fd01eb9f402c5c897ebd74dfeb643df4d1417306d4b17400851ad403f00
105	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	78	\\x807699f46601f77ae28cfd091348879474484bbc296465d24c58d12478f28f1331f9ec2f4536c0bd97e439491fd5683ebb7ec5415c0949513a437f518005c80c
112	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	129	\\x1a66702d47f6f3cb5e9fa0fb0d0a0b1dc0b0f5905590a899bccf488d796d4f52cef18c67ad9074f94f1a32af6400f12d9b5e6abbbfdab41848ceadb5975c1800
118	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	95	\\x401cf374d9c4fe439fbea21c45044269b7c7575a94be0b799c7a6d035bc2f3c79cff89f9da69705a1d2f6fed1851988ae0ead79e09beed4197880bafadc91200
121	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	141	\\xe9005b8132a33f76e032ff42aa156006066122e587c87c374e19beb7532cdfc3639cbece155a8e71699509de4a49a752ec99945c143ee7096bbe854fb068b707
125	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	12	\\x3b77e3da4829654ba7f310642125140dec4e860e52743d15bb2da87fc98e9e802804d273b5ff966a1c1889d10cb6b0cefa7f60ef939f47a69b5c70e55a6a680c
129	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	294	\\xbb3d695f14a42a138d84c6ba459c3d856847186191944884665e9026c7bc48e2e0a9d6605d60ce4c025198de850f2426755e91db89554d5de06327a522bbc101
133	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	217	\\x4848c3420e47869895e3f241dda86e585180c8381c53e42aaf40466c211526ab0755d0399134bab9082818e845db80ffcd9eaae6b0768aed761394f159323403
172	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	289	\\x80c09fbd27a3d8134700986f98a3e66c69f7e9866675ff717cfa114dab250f8702b1beee45fc0f2a6d9e976f4646313740681e245068fd2455c875a6a647fc03
190	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	182	\\x8720aeaefae0b8ab87046c18d42a5c5fcc97a04c65cd327017ea8c5563bf8fc263856fa610909628ea2d56d9c0d8836a2613c9460925085e76c6b19a270e8006
213	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	254	\\x1f60c30f6b1936ce12866734316ecd8ff842abbfdd9d4f3285720f0d6ef0522c2313cd9190ed7e408ebd452c6e9e3ae118aa5db7f04f0be41d307b6013858c0f
268	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	378	\\x3439c2e9706abb18b4c1ac0e4fd0578f1a8fc604027311dde55566754ca0e5af629f298f76ca4d150f4779bec32f2ddae3bd82d7e4a0b85f167795eb0b01570e
278	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	320	\\x1de85ae76add56c7e9f86ee78e624b13afaa45d57bcadf96a47b768d691368e4a39e032b1c889e807b70fd4cb9658545fef947f1cd2a113da2b5aebc75fe140e
335	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	369	\\x56c4a106fd677c7ea0f55c592a76477d2b339c72329ffd14c2ba7866c694419301b24c9de85ad84c4ff852caa8254583d4b520a1506bcb4a510339e65a447a0f
353	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	262	\\x85a25e7e687dafbe589bc79d995ce6ab09faac102d7bc7e58f540a95cf43a547a0966dcdf7f62ab4422bdeef30e2fe7bd229f766d0a5f2b653a3796646250100
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
\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	1610118476000000	1617376076000000	1619795276000000	\\xbdaf0694b848767d45fe6210069e23f3442c4e28803d710e1eafe97dc0d4398a	\\x7daca5ec6c45b662c2fb5ebe38aa81a11414de2bff0013afacad693f968bd77105e5d140f7b632d2b9f937ee1f212cce45b5b5d64783ccb27f13bdee7ef74e0a
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	http://localhost:8081/
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
1	\\xefa518f4f23b98e29f255e853e7d8edf5711d1f6d98fb42d6ea4ee95957841f6	TESTKUDOS Auditor	http://localhost:8083/	t	1610118482000000
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
1	pbkdf2_sha256$216000$D3z65P5ZpRKr$S9ScCdTVKg99fIYyHfBKQxf0jR6QakV3WCsEtgV3Qe8=	\N	f	Bank				f	t	2021-01-08 16:07:56.78482+01
3	pbkdf2_sha256$216000$pjQbN9SdDdgl$nhYKoTGX8bvuJuae3wf4z/Dyea7ytv4kMmqPopnHXzI=	\N	f	Tor				f	t	2021-01-08 16:07:56.954019+01
4	pbkdf2_sha256$216000$PZriHlGc6yX9$iLkiPpQZppYTZUIs/IzY6/qHgpYqxnz1uOZv/X2/AAw=	\N	f	GNUnet				f	t	2021-01-08 16:07:57.032283+01
5	pbkdf2_sha256$216000$wahBcYy5LFK0$TlDmWrBO0YKdmtxPPxeVsLPI5P1Vst9obRMuBYuwycU=	\N	f	Taler				f	t	2021-01-08 16:07:57.113778+01
6	pbkdf2_sha256$216000$RPz9fG22qCPX$AHYYrjayH85BDjbRMl0R8teCdRduPIyRsMrYV4/sGg0=	\N	f	FSF				f	t	2021-01-08 16:07:57.194263+01
7	pbkdf2_sha256$216000$3H26ahmRMWWC$vPqkYqpEvEMpVPflMEcwGVnD4UEHBWRaAjSK6urm7Q0=	\N	f	Tutorial				f	t	2021-01-08 16:07:57.272998+01
8	pbkdf2_sha256$216000$lQotIyPqlFvb$/lEWs69sqKuM9E7o4lnektpBHEz4OrJ1gA2ACCFVML0=	\N	f	Survey				f	t	2021-01-08 16:07:57.352753+01
9	pbkdf2_sha256$216000$d1HFLxbk4u9J$OAYDbj1aQ2c2Kas4a/v0yaWv4VBjkZ9boRQON7kRYEs=	\N	f	42				f	t	2021-01-08 16:07:57.790623+01
10	pbkdf2_sha256$216000$LtT9lVG79B0t$RP0luFeO/8IMvI+HcLUTIWKeZDlx18UC722MMqiouDg=	\N	f	43				f	t	2021-01-08 16:07:58.251896+01
2	pbkdf2_sha256$216000$oqroycA26ven$fmdel74VDTnkDr/JCMGZckcJ1h7WIQfbIN6zwNBNOmI=	\N	f	Exchange				f	t	2021-01-08 16:07:56.872982+01
11	pbkdf2_sha256$216000$9esVhS5FmS2o$SZH6tSdZ4viY2+cxg3Z+kr4d7V7B2m4u40SrmvTtATM=	\N	f	testuser-RtGmnMed				f	t	2021-01-08 16:08:03.874122+01
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
1	\\x198ca9f673a34931dbe6d03e8622433fe0f929452d6c7be237482bdcea914dddb6a4a381e53e0533aba4460e37b3e06a619f5e4673ba1c3ab89ea3ca81d3c706	91
2	\\x62c9b3efd7e63277e93afe434b63b249c5bbe7b23430e3ec07ef967ecda83529070b4a22438ca5a939138cd432472856f26a5319386ac422178c087980415c03	258
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x034417d8be47b0af6cd5deda4cea14fba184cb33cc15ff88452902db08a204ae288bfa828e550ce27e2020b032a1d0c5db75ccbcef7b70e5aee688ffac15cf4d	\\x00800003dbeeb8461d61c243d66aafe7ae4687e78f841e59876410b3a1b4ab1a631ac98c6c465d1ec0489a83f681e8152837c99f510bcf69c76ba22c4428ec252016fb59900163b38ebaed05ac89ef0345d51ad135a0f0a6a82e3fc93d0f30771300413c0f2c7ba407d65a66c4e7cb850db431bae1057fe7674d5f94d47ab2fd844f9f1d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd1c7568ada6bccc7340887975c46951169f7eb5116cda3cc9c961cdeefa4c9b95a75bdd063c7f56613e43176e9aecd8327a23aa049debfaa212bac9e85be5d0d	1613745476000000	1614350276000000	1677422276000000	1772030276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	1
\\x05581b54ce13c447235e37c621ddcef623faffd1b61335a5445572d04ce1d4ceb630b6a6479e3db115f92a983fa03f735de7efd605ae10b17e3ef7638c16f613	\\x00800003bbde3d16ba895878daddb54bf70533f1f13cd516eac3225bfe919b87ddd99dff6fda9a24fd323127bb12ba3f0325510363886f94ff7eee6b5e6751365acbbf9d9b0f924d0939a1d713aed2c4280f074e0ae26e1630a592ec05ac8b19e436f1f157ac2d67f5f8b166e29fe5bb0d2cea06bfcd9e9024e1ff039ec9f223fc674d55010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xef4f13c56bbdd02ae044a06277a40fdda6fa565f2489017ceab90c1b381c578b5c7a63543b2953b44b893a65760d4bbd7bbfe7b61e320b101a3767b9c27df104	1637320976000000	1637925776000000	1700997776000000	1795605776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x0610f988012a467d8dc98196ba7d72bdbcf3f84423bbd3c9aec6622fe2bdc5db8fe511ab7ce06b3e2bc9c61e176d58aaa89dec08be0a037acfa98ef9f21b1e5c	\\x00800003f3eb5bd936ce43d0e37672333c8f8ceec65a40215e8d013ff4d2b0a59492e2dd88d3c50cb541f4ca6d6d51be2212c2bfeaf2564020b56b60e139fe6e9e1fe63ea28ef8eb1f63734cdaff79a62b660c81d93a7e2362b699736c993b970cf5943db141bc09ba6f707145cccb2826695e94c90555a97044e5a238fe3ae35a2eb7eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x32498c6753765c0a44311e201a8cdb7127dbbe11902392b6158a9181f829b57e56572fabc5cd1f4a13c2e7aa7824cd9d2a60bcf7be889f094aa555b0c414da00	1624626476000000	1625231276000000	1688303276000000	1782911276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x08b05855516df964b54fcbe7470d2561fd331e642a3eb24e1187f63594b27b6eb78e4deb6362373cf528f8eb69337b2195e951f1c30a1bc9c04f627f6a494215	\\x00800003c83c81100732eede06b7838a4c95523baa7708e8bfa34bed44540fe60b7b7a1caab14394cebed26af60cb17b009a04bcf64308b1471eb4ade7a9ff8d43e03dc0ab54269062842adfa8ba450686c1892055d2ba4c32ec8fa9fc20507a30f901f707829ae27a29db31280142d5ee388dc3d8c5eed46091a4cc3b7ab568c5ba5089010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb8e3bc60bf24039fd4f0bbb35957bd0de8bbab798275dd666f3b80f30907d03f9b754c15082a4cc5d83321b15403332bdcffef09ae2835d2b93bd5da12fe750c	1637925476000000	1638530276000000	1701602276000000	1796210276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x0b104b6e8385865b0728ac3b352ce69704830e80ef9e88a9ec5a400785f4cfa7b80628a4ae60081c19633ed60189858c11861335a95a7f86b5eb75d48a71f435	\\x00800003f2686c63f8f30c2bdf83b64f78480c1763be4173d3aaad010c18a4e96c2b2a2cb3b690540a7901ae00e5c0031c4ce13bafa29a43b1340c0a642aac815919ad86a0b63be412fe65511023a99c886312cbb48876dfd6a747e45778e4be157387d16e9178ed52e1ebcc3b135bef210ca894e5c583d25424f3e120c4474f86b256d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8e2860c05a692788961e1fa4dba3e8c82067e63320e537a4c0f29be3d5db629fc9bb88ebdee7c735af715a218eae576e777b475179aaa37ee73b17fd6061c30c	1635507476000000	1636112276000000	1699184276000000	1793792276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x0b1cc6ff64b9d6030dbb3a2cfe28866e42e24773c057856e14ce3d5c7e120d31a39534b56d4e28efa1f9c3c7b6adcc79af4df8a22bcc72037a987263230ee4af	\\x00800003a9eedb32077bfd275b8eba15206c66b314de28def402cd6c1a2a177621e3373711c231b4d20dadd2bb836d9fb479012fd9389aba52cbb3b08ac63888cbe75e57bbc4d8e54ee3e527ffdc99f7ba36ca17f3ab440b3414de67d89ddf1e69c588d2220dd73a0b52af4a855d3ba2a9a09a581f7f0b02f7d7c308924469253889084d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5cf25eee9696dc8a0c0c8dd4bd1f64270cef5133a04c277e4b420c6283b31a0caf759e7f9b46658ca77b930997749fe6df46958febbfe047525d0ae240b57201	1620394976000000	1620999776000000	1684071776000000	1778679776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	6
\\x10708e25ab59d31370a3aa3a714ea049a44fea8b788cf5ff74569832a22233d6bac2161bc027868f449a30895a1822c9c92cff7b70eaea5381f4a1f94f4da32c	\\x00800003de8f0493fdc307fccb676f0153db0428300eecf242bb1655413b7b9b67042751b65c98426ca187f6f4afb62d91d9f5572ec9b3dbf0efe457294b3b5ed0ced00db4ed148b4171766e3c75937ef93f5f02e218f742ac7c6b1a121a2b71b99304f15388c9e09ff54662371b9585a28da1b040deaf6af0b1c3b43e1aeeede5b799d5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2559da2da94b86275f7cb57a5ceb25b83696fd724f56927fcef280694412c53a0268b30d4bdef361e1936de3d31d09e8a07bec848a4cf4244d57d86f91ebc00e	1620999476000000	1621604276000000	1684676276000000	1779284276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	7
\\x11acf6f90ce0bdd2014e662b361feb312727d01f7cd1d5aea61b883cde01d369c4beb10561920c5eb4630ca951baca0f42a95ae570a84f1ee3113570498b1f0f	\\x00800003cc1f500d2ad4c3751fa6fa2a676b6d47470b4fadf3b63ccf58fc0b7d353bc5c67eae3541a5e0d3d0237dbba3933f98e54a8e9d647a96f19ad1fd1a574c7e16b7d95f2f86d82e0b86680e7a000d2ff2d32dd5190ce28a5d64b385bbb4d553d868265d621b7181fed0246f9381bbcaf086b2c17f53085be777762d293d702e6479010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc4da5625518c6619990593ff04eed2f96d8f7f1c6ebc1ef6ad86750e67efc66eb1a49c377a58ed76166db66ec6d2616b29ca91fc5cc071f09019f62b56f0350a	1640343476000000	1640948276000000	1704020276000000	1798628276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x129cac982f011332d82a180a886e57a4fd34b34578beee7c7705b7dd1cbd640e9394958d013c02f5cde9c2822e5ab40f500ace194f3305d8a8bf838296fb29fc	\\x00800003b334261b2d8d2bfcbc4356a8d4a50bc1aa43d7ea95e55a0021e613dac773e7965c37a263af14e4f10cc79a7a4a0faf9bea250f7c13f2cd0776ff516b6543f822069dfe5f44932962df6d79baf35020fa845dde61704538f3cf13881fde9703455f3be900bfcc8f381f4b2c62e66b7f4c15ec0cff99306b1a852ad00c7737b0f5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa718662e998a351028324d5e8cb874519c6e958eacc7bd74440bd356413f0700417a481e339f65473a6cddb53b8e29bc13968ab1bd4075d0a59c00fefc945a03	1631880476000000	1632485276000000	1695557276000000	1790165276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	9
\\x13404080d451f6b84aa53bc772931a1fc6de6867d2277716054a620f9b5017623aef3a9d66efd42f7bc8c69e41b9c0f0320a9fcce3b1a104077eb9a16a8572fa	\\x00800003ba0716432456ab5a94bf0c1b973f1cd50b4c03f88dc71f591669c3e1191af9529dd692f93f107140c56a6d54f5140694cea0dcce72ec0ea3397169ec236ff49186e35590ffe11d629c83b1bef859de6ebf8e1b03ba8927f717259eccb284f110820371da8324e230cd1a5ab76536ae0f1d7acce6129fb83e2112fa2076ed814b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x31b96ef6a91ad57c0a593bd089f7d01e7edda8d9a569a5497a7fcb0ddcef62a385b400f75dbbea0be00ddf82ca6d2bcb4b10dc2123f7b914f5a1931c635c980a	1615558976000000	1616163776000000	1679235776000000	1773843776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x19bccba2ed87d5039df6da17d67e2473704eb8671d1b1c3637e051058c7bc9b3cd276bc39ae7dda6430a0a8668f5cd85f379246aee466558930b904ccd5927fb	\\x00800003a731c9c43c0bb270b640e37674e52d0b60e1aac54d718191fc35eaa116a63b7cc350e9f42f378b5a677680bf1902d890cdf84145f5eb2076aee9ad94cb5ed39d7ba740112224174a60ed5e2048b3fcce286e447de6fe778a7959b5d0d49db825b56a19360ed549eb9bc1b8b85a7a2264ad5bf3313d28e46231d70b01e4bd0a9d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa284cad89b0f7ec481f8e7547436acad3712ac9a57b4af3a2bf4c31f9a0bec142010db90fe83e161a75963737cfcca5df5db816254ed2e121b6e9bdb9b379000	1618581476000000	1619186276000000	1682258276000000	1776866276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	11
\\x1c8c6a2fa72509487230025ea49ee2cca668d85348081c0b55f3295c43eac2dbadd77ec692e9a2ee3b0e67e0e64d0b93515fd9ef3e562ca35487554fb021a46c	\\x00800003d37af270f337ab1a67c3b4da10b5b48abb2c683083a4d055a8a9a4ac34411086ff810fb21917ebafcda0c9c2d303a5bb596e2c898dae9bd9d4bb6e7bfdbcee571a2926b190c72c4ca4b15a03ad4fa62ba5ae463743e5f82adb4d9ff219fc986a689198e6ab359aa293b5f65ade670b654fcc02acfd3b171dd04e63f3ef4daf03010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x244e3a747b59e25c303cd83f4dc1dd92d259a63de81155632c1c1e72e536567360bb724f594a6e88c1d4d9083b960f03d923b367944131dd1528e4bbe170c204	1621603976000000	1622208776000000	1685280776000000	1779888776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x1c64920feff1bad6b42e0964895d24d33afbf3ac9703941fec34886c277ac074b80938b2773a528f65310420a0ed6abb314add4aac6b3f8f9b3c2e906793e54c	\\x00800003cde0672f7d6caee48cfc7f351c3861a0c980fb774ea45c73fd8acec4dfa39f8c4c7df8d261d7987caa48c6b04e8042bb9caf9ae62610930611a7e0ec3492a485737f25038e102d78380d387ad710cc9e50ad6448f876a47f1f6b072cf5c5b1fe64860094dd8dcac26276f13851e6a2b1ca81329513ed3480be2c926e3ab851c3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x08424c3e37093a26c9d1bd8108ae45f2a5ce3a8bf87057956a3c6b9a2fa54983ca990b2dc7129d77fd47baf54e9e4f62d49c307658d2aee6258f51152603b304	1624626476000000	1625231276000000	1688303276000000	1782911276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x1e4ce3ef242110bda42c91c34b285fea5df73fbdbed61f73cde66772bf500efb4cefd71c2979f5e215f33d0973ea0140802f22d5ef1324134cc29baff1245105	\\x00800003a9c62602053716dae6f6ae038c8cabef7f2cd7994f5e0e90b2d66fd6c03d9834c2f715decaeca16b258e509edb1f4ada4c03676a1e578e43f32ed2a181e76ec625229c6c55ec9212f574cff7c0e196925fb596d600eef32ff03ebcc7fd59279d8378e7cf15cff4332f9948c46cec91e7f8ebc27f49f52a1200630b7e828f14db010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5c4a2f8985c087c56b9cfa9cd0284b7a4c96f7bff8a27853a4b0178d98c46bce3d343cac3bd2a247c9ce3b3e029c510beca34dcc350a86b6a5d78993268dcf0c	1625835476000000	1626440276000000	1689512276000000	1784120276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	14
\\x212cf6e9eaa120f4a92dbb5daafd86fb5ef84e64b1c8f037df0f2e38f4798e0d6bdc1d5349124e3a826258ea05973dddc2391cba30d0fd2ac1d768791bf99bf6	\\x00800003f73f977d16e9b5adf75282fe7631f18bc28814d2b963e2e9c455574644e6d1f7dd8cf0a551f0ad9a2fc29474b0bead9038696f28009de4c45a904264a731455e7e0652f302b1d41067c542155ea6ebae4381aeeff219aff6ae02e4c373800b7d3d996bcf2d26fa6c2ad4df5d4b64949aa2c7869820b8652e884631c4a1872f31010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2f4a19830546b873fc1cdbd02c30149d4eeca9c0adf019f0106da5b6a08cfe53688efce2a3acf30f4be87d6487335fc1caf74621a3c6b4d12840d703d76c2504	1610722976000000	1611327776000000	1674399776000000	1769007776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x2324b285130cf80e669b3a2c8b589f2d561199eb73ed8ce76a6c925ac13aceac1f59fb324b120d133b604a4a2faff7a7bcef8a26fd413807c29b4ca59eb4f14b	\\x00800003ce8ba52bebc65772a7eb6004aff06a898bd3c34cf859c6e4a34ac3ebf0fc17593b3df1e462752b947a46899580e69a702ee70bdd8d62eb8040227e7cac018f7af3c99959a6465ed7e59885b2f48fa71eb567ac21280b43f0bd9255f0430e74bb10e42c76615382a6feaa3a2b30c01fb5339df56b406a32a9971414a5b7351535010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x74b3b6d4bce62871d9037e4d07160ed3d54da3504241479e5c87e492e9833b9944b2928806e03ddd4cf25c75d9357e3176a659779b17394b320a6b7c57eb0401	1614954476000000	1615559276000000	1678631276000000	1773239276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x244c10d433ae41df4abe420381d9d674bab9bea48634adfdd585a4327ac1782a072fe982eed43ac9ab9c9d27d5f7c3bb26e1fa1e8d2e644ac4fdf2873eeff45a	\\x00800003cbddd9949f0433d3fb449f167f0996e10463d066f269a90e918cdb9f0690a5ff7a397861e71960a32a9e4288bacc604412caa29d2d8066ec8743d4a77062ced591a936acaee79004b5a2e7447e379eedacae8d2a7950e3e8be0769780abaf17bf86d08edda03b71f63abebad450ccdd3765aeb32f0650a834682e3eda33795cb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x824e1fdc54dc9fd777cb37c141dd519b6b40c4c7e1189811842e33f29b4db31d80f37d2a589622e00988ebe1b6d2aed52933ce50e158800179a7d4860bc66b0d	1630066976000000	1630671776000000	1693743776000000	1788351776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x24801025e1c114afc9359006169fcdfe364b5d74add4ab6545b5d4574c7e206ef26799a5c63947531fea2b458c4c463185754a66f6ca36493e8f75f4b3b3385c	\\x00800003d4833af1d62303f84b5b7d35091ee6c7377be4f7c21aaef76bacce3d0677ab40c6413c3b2fa5a083bcb369507306a9a6f6e996be899921cc1bc49236a510523a91f4cbe0ffaab2e868b846b8764f970cb0476f02439ae1fce460f4f3551c5dc330f0c85de51c3b874cf827629a091944b7d06f0ac0a9b5c110a9dc002975900f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4e98eda309f9cdc95ca22ae88f266f3d8706b18dea09deb26cd2859bf04b5385efd8cfb41870fc8a8da02b97c89c1349d482784eaa278f773b8d0c42cf978d05	1621603976000000	1622208776000000	1685280776000000	1779888776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	18
\\x26085dde71b7131304d310b8fddc4c0cc80554dc180a2f833a78d19bd6cce8070d3f56ca54cf87cb7487c2b0a656b15b5fb3da157724b92e9a7df141b4434e1a	\\x00800003d160ca9387447ff9f65486096571f37da695e6b517a63b9f3d32b313acb25b024b73d7e0d13350724af82407077bbadf79199b9f0bbcdadb90e63b323d6088d1b6058aa839510d2cd0a466140478c84058a47e3d35f653b7734d523cc21800f14486014053147f64820395ef3bf4eb189410ac9f90d2c52b2c4ffa5d0023df17010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xca971b525df104c006d47cfb675bf618e6ef134d8c3c3320e434380f286a13fb09e1d80c751ffd535cb89a12b8ce49fc375ca7d36f7770e5825f253dfcce410f	1627044476000000	1627649276000000	1690721276000000	1785329276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x266c4217cdcc01b134ec7b0f669c0c5cf3575196b3b59d9def7d95c5120dcee97e0099bf928d666771233033f08973e07265da491b35830813c9c6e0d654f7c8	\\x00800003d49ae1f6ea4c920bbc22bfabfe3b73999c9794069b37e6645d4299314e60d6761ce1c86632427e94f26e32cd3ffc4a2e4738dda9db02ee5c40886ad2c781936693d6e9f863f877b372cd3181652664dae9f8c9828d5a3b85217e5fe939f9453722c9e51e2c9b824cb17c5d7ad828989f6ea3df1c3709ea9ed7778c284ac04671010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb8b0cbd8d6671541272b2b12b4dc2e9114845f145ea522da90f48f362ca29c21a2fa51490d5b495086d8ba4fb55dc94129e0ccc9beaf83ca0640b49e0702a205	1640947976000000	1641552776000000	1704624776000000	1799232776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	20
\\x30a027f0ee446fdb2e538ddb5bf8544ca26ec213975c766db0587a654f517cc93989610cf8b25faa69ca65c6f309f70db8649fc1e2e37174de3a5795cbf40872	\\x00800003e4c08e0901861c4acaa41e5cfb1e1f9d28e73a4fbd03d134042a53c5088541ed95637f7ce89bafb731a4fc9b43abf04b0149947e217cf259ce191c535421fb154f55451929f790e4a51de7dd609d403476f2028a16f9877874af5cb48038f6bbcce1060222ec8520c978099f32000c9320bb24a308562f832169236181a5e1a5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5ff8ee851fa59156066b35847df672dd420fbf7cb1bc4319335fff4dbf7f608cb1e09b0324ee34a7524fa17c39054a4d9d9191448200ebb767eb0d2aa3649108	1624021976000000	1624626776000000	1687698776000000	1782306776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	21
\\x34d8e9fda96c9b914800f4e2069bb8deae7120edb4baeed0c61f0c46f60c0dde5c50f90d2c1ed7eb48e086e7e71187d76c8d4af004302bb602ae8a947cf0e7dc	\\x00800003c684bf6f1845969aa9d69cdd54c047b870642700ca059ff061ae693e42520a1e539739d25cf79931bfdbd352d748339ee6b9d84b816723ecffcdbd213eec7bbfa25da3162d85e372dcd1e709e75a4fc17a7e309da24f4ea6b8003691e00c22b241968ac3bfbee4bf68e916bbd762e8ba0cab3c5694490e662e800eae6481baa1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9e4e8570cb724bcc4fb5180fc9c4945d13feee23963d8396cbd7778e8556e7c460063c47a56d2ba5dc0b7079c70d7cd20f6f24f52a13d8ac540060ee25fbb40e	1639738976000000	1640343776000000	1703415776000000	1798023776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	22
\\x354ca5dfc536b8fd56689cf75fa07226a2730ed9bd0a7e0dc3191e833e3f7d210f7ddf612ca0106965fb9bec7b9710d5295bcd534793c874b05bee513ec13d62	\\x00800003a61e5b21928f77e3da345bea5be93f9208666393d7db1cdeb097ff643e269e23b798be644aff84f4ecf5b6d4449bb55b6f261c53f8cc31c3c70d1011a75c2f1fe099deada5d504749cb2454075c54d70e75500f744eb68936f69a739c8359ea6d376d287d74660dcb21a43f8a48ff409398394569be9e14a7436d9a2e0112e21010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa60d5126b44c73854c17222d4089ee68eb1f15c4d85354545bab24d0001a0095baca452de62497cc12db6e8427277c54274727b05a6f6a8937b41fe8bbd2c809	1616163476000000	1616768276000000	1679840276000000	1774448276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	23
\\x383447c2c46d8c46a690c695f053e31a767ee4b2ad832567ab7ccb91613ceaabfb155e936ce83cafa340875a7b3309cc55e0a20746bd94a367d3a3f415af37ee	\\x00800003b3f696bac579489a82811842492ba4e493ed824a71aead153fdf60359eb66981824c8b06715abd3af9eea76d0422592fed223bd5cfa8c43e2639c087974fc604ddea7e77485f09a7c21c61a0feddb7e52a85d2d561ebddfa3900ec50971ad67d858c5c9f49f72422868d4d16edfe3b585df43d04ce80e70da279053fc9aed4c5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x64d6fbdf3389f06e3c2908a72f06104315b91d075a73637b8a054dbe59e90f1693a387f398e0f7926c9d44ae80542dff942a37397af6a74b09305d61a35f5703	1621603976000000	1622208776000000	1685280776000000	1779888776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	24
\\x3bb4155144c57b60bb487e3c5fff240ca1a04db0cff872d3424a166f62ceada4e4a6cc771236b88702df715417545fc51e57a253203c6fc8f8393bab467f1e41	\\x00800003b6ea30cae5b42b85259f6d761ca467c4e2a31eac2f69c5a2e5d617100e58420279957332dcf11ef1b00bf644d4661a48a501c46f56303259eed0d0b203592d1af74da6c9dfd764236e6668731a33e9112f0710de60050e4d19fec89239752000d13a3c5aa511ee4965d4a0de5cf80b8e470a9bded30741e8a089b715504963cd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcd351db27c6b537f6deea80336c7dddccde4381f2708ba9f5f6a7d3a4ed484a87fab4babb41d15cf8fa3075535cde61947ecd8f48565659e0b5c087ce82dfb09	1630066976000000	1630671776000000	1693743776000000	1788351776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	25
\\x3b14684ead4e398ae7140e246ced01f61b545a96824d637a81c603835ee03c21f3fba781eec3261f340008d356e79af98bd2e370ceef614439f372c973205666	\\x00800003cfbd1451bbe5b8a2fe5847d3c975cb2a0df6229be22668a0f19d6b8b9000193e0a5dee786507aa968ad5bbdca120e73308a6dd8d0934b6c19d08fd8bcdcd79340332901e9d5c5597557ff887a4b1dab4f36eb9efebfc77fdc7b9a9ee34c19e477e93d9c4ddaaae837ca4e2b453d4418b6d171e3064f0dd096b081fa0f604b529010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x50e96bd8b955ce1d4d6b4e215e8cf56649453f4d5fd0d07d735c808d234666bfd3a559ded2d3642785f01d3531dee45f5d0d9c5cd94c2d571b6fef76024db60f	1616767976000000	1617372776000000	1680444776000000	1775052776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	26
\\x43207ee9d0b4ed2237e7acd53c3fb5687c47df583b6f87a63c87410f7f3c4ecef4e724fcbdd6d4ec20556b7a58b6e704bc763f424679dcd95017f21d9e9ebb5f	\\x00800003bfc9d86eba75b21e5b0eea3180a9fc215bdc70751eaf400f4c835665a791f84894636de4f90d84b5b087aec3870ec2a0c2a25f87e30ae97bb6754858c66a777f164fe173aef7f57c8af96f88d18b5a1edbf66cf556eef17286addd9d96fd56a8de8a4887cb38fcf41ee4af6d56c45146f9d41663986c9c9147ebd8514a3c836b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2e20f0d5c0099a4d31a125b57be68af57f1b8cf4cf375ae6f02e1faa4670d6e3e2f8ea5bfbc05346ad88f8f63e9942fc297c925db04a7d5ab18f836816829700	1632484976000000	1633089776000000	1696161776000000	1790769776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	27
\\x44e40e8a33fad3b70719c427febad191ae4f4f045e694e03a32f14b84a6a624886ee54ea20f7a246b21e75fdaf83a7e2748c69a8166696db509fdc357507400a	\\x00800003b4420a8c6110483b0aec5ea183c626def108e2afb2797eaca9bf991571f6be7f6eed84dde39c0ad6e5fbabedcb4e17c60cd1c206f9abf7d1e9a8319bc3beefc4854a71f15c8f6fa31662afb46ed46c752a5d2112ae8606a49edd00363008a3a42d05cb45743d07f1661a382f48bde43fccecf2ffa2677a55663aeb4a8a00074d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6520146007442cdc8252619117070d88498eb77c0a9808401424fb2474c56fd8c740d95fdb8ea8300fe23c9966ffc523408d675b61cefc60619cbdcfb70d1306	1625230976000000	1625835776000000	1688907776000000	1783515776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	28
\\x46c89dfade175376aed91398f29efdffcc194862bd14e98620af3d9cf0d5ee1131e5a6ff80d92778bfc2fe6a828067419bbf74af9924d1782fa5b2bbd251ac19	\\x00800003a7b07f7b2f2f01c67766c29cb13cab7f8a7bba52d103adb42dc323b10d4d1ffbd83d26d74e786f2546578ae50ffe40b146f72cf22944a418cd9248c1be7e20bb07eca44727db38aaee87ff2d48dea2d4fdb0939f16990715365fcc7b890ede195b20b76b94241bab3f6a79125cd7217d424f4d893998cf1fb9d7170f9f907989010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xab75db8c1933e8b4ed0d7532c706a5860f838d96f898c4889f55e876ec6dc4546a6ba102a63b1d8da60dfd64aee598d4fd3903bf02fe6489b9adebf355118604	1613140976000000	1613745776000000	1676817776000000	1771425776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	29
\\x47e887fa96326fe59e5eb512f810352653712caf105558b55feed0de2d6eb66f823bc1a589c70288fa38ae8672ca96b3b340efbf0e34312072ddf829bd4db6c1	\\x00800003dbf45acd3340b17b380986779d4839e3f2b0f31381edb8668ae4b294713c64a046bfbeb8ff3f5ba95976be5aa8b0192a9c82b21718943389acec8a2f8a424ba9cdba4a056c44bafb4f03edfe5ad94f577ef5200715b7e09e34810bc39e73993a57ef116493b853ce34fb7d72f4b32b0070e069015a287d5abeb9bf4af822f3ad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x77646bfbb331bba68146936a4975e9e2aae78a3f25decb9f124d65d51711ff8ab567fc664c66cf08189fd9d6de2be6691adac222a631399f565ee4649e7ea00c	1618581476000000	1619186276000000	1682258276000000	1776866276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	30
\\x493414d22fbde845b009ca26e758ceff65b6e6b628c8f21ce90670813edf9ca90cdc8b483ba15e62cb78ef9da4a030e9df47e5bebbf2d52a3a79ed2a07f7f583	\\x00800003cb59b6f8f3591b3d32fa34116ffd3291e9191dcdedeca36bf9a520c73d55198de35997b59bc7e62d254dfa31ceafce9c2489dc6c9edf680876f821798c3a8c3227760209253fcbe2e8a15daf852e19e83e47597f285c4abaaed6dfc8d82595c6adf6757e2c0e421ef0267f4a36cec283c3fbea533d4d0dd9c8ec0ec941a0822f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x08efaf6bcaa7054b84696bd1cb2d9d581d921084bbf7c849baca5a6c0dd85231f7e18885c16abede06ec40a79cc7a38448ca67f5162d29a570d06515c76aca00	1626439976000000	1627044776000000	1690116776000000	1784724776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	31
\\x49e020ba6e0375859ba0f576c5c6362fb8fd5a7cda5a876e2dd4a3480390ce2288f9840186bbb0e53883d2af4a2971251ed0c739468ae8aa1d58fc070ade4c9c	\\x008000039a641c409d344ed633d7d95260a9ab9722447d35d477488eacad47f544e5502a869b763f01777e5f7bc148c7c91dcb32f682d65519833fab643e2dade521799864d084e12552a69b113eef430e091d919c7ac675e93f504a09c1ee64139f76e84b67607b8b6c92d97dddb077f08b1a2493b6a06055d92c40a389e1d4c7fde337010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x10d044481fe003efb9f0d8b94fcd721ef699029baea4eb001d00f383fba7195df6cb4576392a74243fe872cdd998869fe922ca98d20fbc57c88565f85de9290f	1631275976000000	1631880776000000	1694952776000000	1789560776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	32
\\x4a34347f2cdab0324de63ee837f4e81204631bff6951e075cffb9ffc3d5663dad0ae003c3fe5a44d42dd345913afbd52d7f0462eba9af1a4fd2bc4c657968c75	\\x00800003bb9d8ec485aa0f8880e45e117a6a1dbe75cc77c90de927f1b3439d18edf19b3f1626c938c7aeb9ae7e763981a851846ee47de42151a2f932a0be1989e0411ba7a5305446d198d81ef0d81fb0fee94dfa8938d2fe6da3ae91e682eaab5c3e08be9a5c15089b7e7c41d2ac436735afec1c2a96239f193883edd59c891f24721e3d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe3a7fe50d7617582d5b5a9041ab2844378a312d7dbfc5374a866652b6a175fdc5ac08b791c34285bcd3fa2f7124500e04111bad97f5097730f0603a7d307040e	1614349976000000	1614954776000000	1678026776000000	1772634776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	33
\\x4eb8e03139e7f4c96dae4c5947b1dfec09ec1394ec14cd4bd732c16f2f66128770ecef1dd20cf9a1903bcc28a179aa2491b0e306195d46c1fee38701a7dfc8aa	\\x00800003ccf55f7acc95d167b27be3d6330d7195aa6ddcf4416e6fdc014787bb0ee0a9d767e1e67ffc2504539e62c83c2b65e4c15c09a08ea94151c751dae53fb737af8390d0bbcb619bfb9b9534ca2d2c9a43c093cbb76ade7d480a23c6a8b984a7fbb04bd0eb2b46e71e3007cf491f1355980fe2cfbc533df4e889d876239e2b215adf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4695b7e7ea0ed82fea77063a1f38dba72cb74742590e03db6bf50def804603dac7b3135e8a38ca49cb8ab43b1311ef968bf41b52943c558f419b3b7a7a2a6e01	1624626476000000	1625231276000000	1688303276000000	1782911276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	34
\\x57480c2ba2a8b9b67b1c01bbdcdb64a954356f5371d739c97d253c2934ba5d10a7d934dd02d2ee20d02ede4d172ae9a4038edcc80a8a1cfcedcafcac70a604d5	\\x00800003c55b39d58d04480bd76ec48353bd2ecdbee42f78c1b81dce138a16b98c654a495f1d7e7b4181486c530fed641ee2c138620bf10783ea5c812d0daebefb69f70be3058de59f2c6b2094114a3e8116977b29d90504d43f0878850bef9184966d23b23e26504616968a0d364ae7fc85f9500ab3f5175e4ac23f57fc5cb88f260195010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5e96d2894bcd332c7a83afe82c75bd5c767c02427656c95e2cac8573bed0bbadc30b1c50e1eb387d978bae03245b53c6de677502fd035668ca59f1b16fc46603	1638529976000000	1639134776000000	1702206776000000	1796814776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	35
\\x59e4b98826765064df6694050343490dbc5429d43863b7257d91b617d654e823b3b7dc0f52b9cb0dc4982547b7f3b1e3348b6aacf80e3424e92977e9e4b5bf59	\\x00800003b95e88d413c2796587b9767b95a6374db80761fce87c3ae0e37f0ba61c920f2340dfaf688b0b311f24c82ec6b162fabdf21f094471ecddcec35d12ec03b8ea414d03dfe0a251b56c579da4a4c2f5a323f923723490e42201bd9a3fb03cfbdaf598485cfd7e9c95b32d5a8de16bb7383e85be725ba52b585db3410878256fab49010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd8430830e527210aeca922d9d9f550b3c6413754720d17ee6b4e7ea6967647fa60ee107ac17e3706829e8a07a7abcb77c55d6f9c6f4af4389950dc8764423105	1632484976000000	1633089776000000	1696161776000000	1790769776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	36
\\x5b98b4520fd48193c55dfc565bd6ee3ec903826048e662b8dde8f0dd3b1da22a5d03833e46aaa5d08a3eb72a5204198e8d2e005a855988a71ae14e95da8275cb	\\x00800003d13b7d7c68a5d940280b4ca61b3a3a1db0a2295844aa0473b0d41ed6631e7823ac4d5be666dff692ecd4ae20cb1abf70d8fe50be8c271f39b2f21feaebb69e7bd65aac106e146e584207bda2596e15820ef7d69ac062f6920d52979e9dffc7ce79254975a4228e776bd9ae3ec839ed5b838c4938d2c6ab5d79a9ea90910a7029010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5c2efd67824283ae16eaf792441670e9fc6310930725c1a6625aa32f756e74d4ea89bdebcbea99d4d84b7261bdc9f9bfefc6fa84163058fc41a3df763e7de10c	1630066976000000	1630671776000000	1693743776000000	1788351776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	37
\\x5bc41bcd9fb966b123a55d8638de85e73cab252562976ea61ede8c566f13ad3fdc94e4296f7618ce8d4dc3e85b451c1657235c434c95943cf07288debde23637	\\x00800003dea00e31ed65678fb5fed8f6d9865ad942e9d09f224a2ca78bc82bab1424173f7184edd3603467890bab3905df3ac134e26caf38a5cccce46e9ed42ce4e9f645baa9b69b7117997c45e0607c085b9e4da486700d3ec3042d99de200dfa1f7f11b61c7d8fdf97209cf638f5c860f78654a1c98f755efb553acf3974e91ae08ad7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9f5e96ec277ed6384b23b0319d612bfb28c4976a0ad222bc3799028ce44675c5f75ac0de787958e76fa92ef0b704b19ebab6fcbe3b49c8b040a519839162f906	1627648976000000	1628253776000000	1691325776000000	1785933776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x625cf67a54ab93e4d721e2ee66688b07a7e8adce921feda051c573ce3b5fb9af7e302bba96a51da58726e83e67a696c6de3dd9df188a85de12233bbfeed94071	\\x00800003cbb159b71a2f9043e0b49f549b612fcc9be673fd4dfdf5a5ca586c03712e188c30c652d381166d221ab714de20ffcb090bef2ebe2cbccccbce9add7ae1c4dbde8024da5f70187752a3c0c8d0b722cddfe2a194c4bf3c29e0b9d41d31d6a2dbde5efd483022b6155b122479881ce6a05410cfc1dd37234d673a211e4d8489e26f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x462cdc3ed45b7fa52b180ea626ea42b98bda1367e17b9b2f27730337c895de6f2ef8f8e596db146e813a31e84607e546ec92b8da7150f3071d856e5c23801d0d	1630671476000000	1631276276000000	1694348276000000	1788956276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	39
\\x62148808bbc60cf01a0278a2c70b1f3a8aa366a253c563249c07153dd95ad6c2452bee63730b8dd94bc0168de87444253bc9b165e273c7aa02ca781c2a4be9f6	\\x00800003b33afbfdf7738807645c71892850bfca86e18dd3642d7a0baf26b173d28ee996069da8a6040fa2f4fa9fed08fd9d7d9975cd31ae918a38bc9b4a86e7a1fca2f69e6609cf557053e6818c7cfa31994764946b06fd79f24b3f2bcb896c72969e51d40959348ae151bdb1baa7c9b66a47920a414fc2d84e8ac149c521fa39439d15010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x012db5a0340ca95a99c69a3749a2a032b8fe904fa28e45a99593f42813c90d802de0c04414b3997aa4b219ec0b48b94f46b726880b695da2acbdf1444f90a30f	1629462476000000	1630067276000000	1693139276000000	1787747276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x63a0ef5dbdae0336a02cce03416ce1a5d884bcc384c6cd2096038735ab29becb5323f03b9bb3697f600d0e8045ed6db3ba2340cff318422a5b7a54f5ffdd0f60	\\x00800003b3f3b22e7f9a9aa7f727d5431001c64b04436fc2fdf1cafcbcc7ac045259bab37e585f9be1505a611ffe409476b9eb7155093ac65913820582c7ac52a3244d95e045e0f88eb4f7619ddf25035c571f94c680a7bce3197e5fcdd04a96d5cdedf7068d4e90e2134181e30cc0f67145f0abd5431678bf9f7a727718bd97be68cfb9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x61bc9bb81061ef03f588d23e301c24c3eb8f98fd3fc6968011668120de574f2b98f69a5da02b0ae696c04e87015e61057efdc77c0ac69fba08e635374e7db30d	1628857976000000	1629462776000000	1692534776000000	1787142776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x65246c701782b3929a2252399cddba6100bb7ad3075d9cf8d4dd79443b808c330382902da80868498a95937c12d51c88862c10cdd7bbd9a1869c86f1414ad6f3	\\x00800003c999c0729a1a7eda2c91f0c9829f3e37de1055045c5db5f653528ca1bd13d10a2716854722eae97938d68fb22f883f2d0fa0127d441f1849fe510f7b91429fa6be2ec702c5ba00c2b5c0334a5077ba490800f8023f3f4f1cadc6ecbcbfa8f66db9bbb14140a136b0a7d9fa488ff59439e96201c9e00e8d06718604bed0bb5461010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2695c2aeebba02a1624f1d5d86b8bffcf7ed4fea2d09687939a7ba6616cc53143411f4b9a24ed8bba5dde2eafe8357eb3e6cbd0450e16ab64ebce965205a3c07	1622812976000000	1623417776000000	1686489776000000	1781097776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x69dc6fe940af73bd63451c085baff2b249e054711252ac0514a9e365bb85d2a8c8d7e6a537fc5b328b377c7b685dd6fa21464a982e2bc60276e480825490cfff	\\x00800003e22fb3b10ccf0d38b15192176df5be84f687a94ce61ddc7d2de65661e7457468e6b2dd20d39190f1fe2a779ae4c1a9fca3c4ebc5b30d83f051745f01c7e005807fc0197be270456f2ae1974fd68f00b71e33392b5d39d003350cfceeb91111314726009b4224c40a7a7fcb6d4724e8b5cbff0512be4439acf9e1834e4f5b27ed010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x99242485e15b75ed4b46c64fd8c82ce457813b57b872a1ce0ff917d95280d3c2aec482b7514279a5327c63705883ba0f688429ff2aafdcee346b730bfe4ebe09	1633693976000000	1634298776000000	1697370776000000	1791978776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	43
\\x6a4c56a7283db0e11afddb8cc4c1abbcc71b482ad1bb631d9e9ce80f146caabc31d7c4852a8a904fea81cbbbfae9c1a389132c80e3ed4105efdfeeba72ee31ad	\\x00800003cbace419c079b895366659cc637ffc4ec3d5aa778da818c38a82824b4f8bbe97fdde8a5bab8ea358ccaf306a5a694e483477e3d98180e4359a42b66820a0f3afd7a625caf54c149a8c7f01430d75515e5207bab644af216b2273698eaf005bd68cd125f40c5e967799805a77b9c0eece8d86dfb7dd97477701758245bf5bc8c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x14f0694cb595f15ed064a055f0fd1c93417be27d3eb45ef3b87979d000c21e9f88059add26e39207fa8b9eeed5ae1c30fd08ed8ab6c7be2f6231cd6755c30500	1619185976000000	1619790776000000	1682862776000000	1777470776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	44
\\x6cc40c0f79ada88c1243c6427fcd3fdfb61db1c06a594a4e44adef321dc35e644f42147c94c22dfc6fa39ee75a37b55d7dfb14f5cb6573cd2b057aba1d6a7431	\\x00800003cbddc2a806ccf589566f3153d91613fbe3ae650f01c77a389bf972101fb312bb9224c0df3c9a276f7d135663ff768fd0d57d189e4e87eec57a64bed49a164a6bba4b38a24eca62be0e01424d24561538e9b25143dd45992b41d80f1431440ee4b136faaef34c4f4fe0a11f848d4ee4e4ba4d2a267d6d8b399e29b298a80ae223010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe1fcd5415058ce7865d104cefde5d132c7e0f2a80c5f2b024725c7c14d451957ebf81ce958d374c46476f754ba5ee5cb6da838a50db40ea3acc765aa265de102	1636111976000000	1636716776000000	1699788776000000	1794396776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	45
\\x74c4ebad78bb48c225143e1e51a45bfe8ae23bee9460bb4aa7a22a544b22aa411148314f15ee58b50d02f1b367b16194220e3cea8e1f74afc785f4be6547a885	\\x00800003f14de25bdae991ff658302a36b8c31a33bbd0186c2fcdf025913782fd67610be97fec9b549cc48e34b5695414cfa52c56e670d6d74cadce0d43c095dac9865bf585b85f082eaa504d821b781056739dd81c5cfa0dfaccdb8a35df9767f6faae1d96e2f06151f34e717bd47a99b7d080f666d64cb812f3dbd4481828332353c39010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x98b7d1a92331030e20a9f96914993047f2d953b45e4334ab1302c4e9e854a8567ad40d6693b69d4c4717b49e59e358213ffc933f9f064b3caf089f409aafb004	1625230976000000	1625835776000000	1688907776000000	1783515776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	46
\\x756804f28a63ee81215f8f6c2c0ec2fbba3f9f26ed2b1ea2443cd6a461c52ba45d1dcc0c2e18974a67ac3aa3c848883401ae0c3824e06e8381dbd2df4a297b6a	\\x00800003be32df4ec3f343919f958b23757d63751a9fc9e0dda6cedb79b5d674dbf4f4ee9184dd91a6a8acdac54f7c342e57be5b45f071056cfa9bc54c192d69b1b50436177d544b84e6a2db0d89629411d8c73028bbe20fd10cf9d439eb151c3bd0b365e7fdb451eedb5a5cd1e228b3a11c839b28d96618e6c7372068654b97ed8240c5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2ebb4af1c8027adf10db9c675fe7278bfad0c7bda54913c990fa817ce7dc9c8114506a09259d57b78ae75fa9d99bdbc4d43514d9de4cf7babb659926645ad606	1630066976000000	1630671776000000	1693743776000000	1788351776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	47
\\x76f0a399c0772e612388a737550a02519d854758a459ac0bd180d6c24915d89f5ceed8a5456bbd3212ea856cb5d6e91491c4463649c5c88792e2dc61c974d995	\\x00800003c7b607f0c7aebb9e6795fe8c67c1934c07663bd09fd550578f88f06a484de99d7b4cd2eac6997284f4bd8761ca1bdb26e46eaf83efa5ecd7c0c82cf43cdfed09ca95feeaa3ac1ffca0d8b39efa6f9ccc585a20834f92d1cdcca9a4530a161e6bad6bd41593a1c6f260f1425d501dad87f90c63aaefc36fe3d8f7326fc9b465eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd6a389a9f7307071f28eeca2e169e7ab4c01b125ce3b90758bd7001abc8d639e6a893f0b9ed3545072718236e5b45210be3992e2c9c503c2ba77d21d9ded8c00	1636716476000000	1637321276000000	1700393276000000	1795001276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x760020b57b8fc41400a24017e3310221a2d9770e91db12f2023c8e930699e14006609b64d618c10389ad1f1751848c3c9d6be54aecdf8b139b7de683814b8930	\\x008000039cd4768bccb18bcabe759d6907db855211e12c8c8be7c9eaf1fe7a6e8b80a9913206c7fc7628b52f10fba4ee07ec5742838e64845c5d06c11f1f875d042e18e00bdcd1571ebe265b46fa03902d55edcf803738228d144ceabc66ea3a37c397483935655d3bc4fb22915d8c0100acc6c134177817f36ce3388ec5627d8734a4e1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd41a29e19f0372616fdfb95f4988fe3eb353fd0234e6d822937d0cfacb6e4cd964325b6b799fb85185ba051887b4a581f1ee4bb39d67764a13b7c3507fc7d008	1629462476000000	1630067276000000	1693139276000000	1787747276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	49
\\x7de89fba497c338c11e2a9cf171bae4893f2a294de5a247cbbbb8d8c14647315b91a933392174870485d32b576a8566dbca2b3702f59423faec4af4e2dee0df4	\\x00800003fb259bf207c21ceb85d164282a5e101065bc59c187c4657dcb9999bef6f6ed313bcded214d8cca81569058e320a862a584a3825b6bd882147ad6d6a17b8a48e7c26fca07e56530d1a9d4703df91567e5a3ade8d4e443239bce4ab834a2980a3d6abfed3ffa2bd4c8ac3fb0ec42a5a4c8de180782135c13f11e00ee7093bb0035010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x597a43932008da1fccc8b43bffa68ecc81d63d755d1911d1a49cd2ac25b68f2c084b14fee48ba38a06a691539eebf7ab67ffd4558641ce069ba251547d185f02	1618581476000000	1619186276000000	1682258276000000	1776866276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	50
\\x80f835cb0a447ed135e5f322859fa28ef0580841326f3f5dc254f90fd12bf230f9739a729ed754c7469012edb939bf394f7d20456d52aa17f0fcbba9cad936cc	\\x00800003c065737872da2ac581fc5d610a49b92fa69d3f9e6f02160fe2dc53049a9b4c0917b6b8da185ea278d83db517643875a57227fe12f1b361172da6f0ee43315aefecf0a4e28805a5485b18830b69d25dad4068f1f8de9846b0782f95cdd730cc20773ddf0ea1dd8829a1a619deacc55bb4e6bd9695f64d744d064f51ffe8c16c63010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdd364162570bd8c2b5f8b12afb9fcf529544e103e5c143fe2ba826d76f46b289b89afc5694ab0cbdfcce7e728afd7916e69b9b00fb2c26254437c9be80f2f601	1616163476000000	1616768276000000	1679840276000000	1774448276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x8054136342b1b17fb1c39762985b0992ae6a1c5fade2daeda029deb63863b7a1844a1c511b7af74e61642f31ecba4e28b1b839f618abd00b9df5b4045c66dbc2	\\x00800003e7b09827deefa13d43e8b0d6bab2490c59df3c9079d830f8430d9ad1eddc39c710df1344e05797d04ef43e055c0ceb1f08569b3038bfab6359edabae2185cd7d42d695cb6c276c7f03a46b60a6cfaf797995c57f530a4dfc8b37e5920be7a8df9a60be43a6bbbd49c291262684be83b2f9fedd4682b4f764db5f58b6e0a8aaad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x756832467a8a51f5ae96c1735458fcfab617d66e529c321af18813195b4f3a0066bb667402c4c434e427f518b05e67fea0d7ce93d6b30b00b0d5337be1eca309	1619790476000000	1620395276000000	1683467276000000	1778075276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	52
\\x84e46cc66790cce24e5e4c97b0eb70e7dc69e3bfca7af7582e10785ce3d2076547085e726c4f36a50e7d23f4c9619b1a9717ca7c04985e6d1769b5802593a588	\\x00800003bef22439f20218681c2e9df288b29d286914643d2c093473d694b9e62076c2cab5b0c3175b871697529aa951cf522baa45df61cbd45c0b0ef6c2794b705be1298fb51d035c13549e823a2782a4ba6c36c47d2f011bbacbca3fac469a43060ff168059fb5c73b9ffc4f1f2c91477696bb52fcc2cd091a11081842aaab38f22de3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdec7a9a7fd315ab456f23b465826d46f946ecbbbb5c5c20fab186f5c399b12bfad155112833b107d6f7d9d9494cf706f0c7aa9f4605b660235780e171d215d0b	1630066976000000	1630671776000000	1693743776000000	1788351776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	53
\\x85a04d7ebbe6a8ff5566b1a295bd11ff2b472594bfc69abe7a00952e8acb5ffe16b72df96851dfdd79ea3becbe02b392a4009b25056b96cdeba1c54ba4266e92	\\x00800003dfca21867129c7a622c895f87f37530cfca69054ece25a7a2f5c38215f9683306b1364f4e0a9e89c61b786de2699cfe4d50851b5add2a004f95db724077cb2fb1c69404c1b2ad663609af14b91d95338e27827c6d92ef765a7b2cfcf5437aa0d62c031fe78e4a4bb0c4d9bd2b0dec5e8dac70ccb7a763c48ae674ec1209d6e85010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbec1b990ff4e3a1ce757efde28e98dae158e5e4452c532e25983616f3941767c5ef6fd6e4a2a0205ab2401049bbebbdf86a2a73da6f7350b2b53558892f7760a	1610118476000000	1610723276000000	1673795276000000	1768403276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	54
\\x86b0c26eca255be4a4d62dd223a5ea02fa54e5bbec871dbcfc67523b1b06e2375faf9e95324575103caab2e1c7619df30d3b8afbf41c209fa4ae80b22a7f3e58	\\x0080000391bc3c9da44af4515acc5c02df5b6618b178d8bef3e25c0229a5c71fc5cb8a6445ef186c9e13c830935dbb08010edf6a1ff0e97e4c8804f32750bd78a24372476d2d187b5fc6b531242ddbc0bfebfc39523330ff39f998c228710aba067349f08a59c156c867765f4f35318204d446b0b2a2c4baffd2105403d06c5ecfe951b1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0b5667c7e4363cba2be5274159848e1e87ce0c46dd6bfc2d2c2ceda93cba062c1dd269cf9c069955afa3fa4efddad1722b8af388698fe4dd0a433145af645d02	1624021976000000	1624626776000000	1687698776000000	1782306776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	55
\\x8600543e9f7ba9cc81cc2a95a0ea3330b40314b545be46820301eb993616828644f6cc5bbc411b34144a81e639d456fa52d9b31881515ceb7ab1f3569303479d	\\x00800003bd9d77e93ecb5f8012db3b09d68b20ae43ed29e7348933b5653273d3b641f8016ad9238d06ab896eb0d92385488a99b1a73a56c68a0d83782bbe46c83d8b8ad854186bc54b2ae3d58c56b8708b52d6ef6a7ead4b1795a0b1ae638c83f09c0303192bf0710e2b10a480e666c3743b33f52c9e5c1a62758fbc26b676378fa084bd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7af2e2c4880300c0109b25e990a30322b324c812b010bc0507e2e9711417fc10296ee91a078f38a43952c63fae6be4aaf19550699ac0bdbb43d4e5a79afcf90e	1633089476000000	1633694276000000	1696766276000000	1791374276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	56
\\x87d467386cbafc0117aa76a0b5daee4177decdff7bb3e4fc3e8d454e89f46c8a17cd54d8de764a44a3a929e432679ecf30d47bd5cb9f36ff83a49116eddeec20	\\x00800003a808f975050c643ed4a95b4cc05b6516a9f264816708293e8d491e2fa9be97c96c4087a5997c67c4fa965d9781994e1acab17925a8094743d1723c37191f5de93fcee7e7bb34eb6e2613330eb5fa7bfed1e4320985818ecec0dbc1c9b5f26419de3fafe6bf9ed86129b625fb22c7c9f80e568d06e37de26c5b1fe658f29abf89010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x29ce35350b256dc113a23485ff214b87fbceb8d175fe655a538bb4135565ff19c2cdd1a972866edd468ef2fc1f34f22c72df00099b553e1df7b026fcef2aa807	1622812976000000	1623417776000000	1686489776000000	1781097776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	57
\\x8bdc186803a16065c72422f411a21561d02d253bf2c2fbaf06bf2bb0f007b09d6ef0c821658659f40d3b308c7350c02c6aaa4a0d329625cd5c293adcaf9d2789	\\x00800003df0e61dfd64bba4d3f2252e3aa5752f06c057a8c3a8c030a2673681d889d1bb76379fede4073dd408f0e290c98273c888b307fe5d49be35a6adb2df40d84aebbf57716dd14302ef71a58ae0caa1df512209af351a26484df18f1bdb2d7810fc2be57de6443ef5639566fd2798e0e6880dfffb99cc9a455e2615be38e43c7835f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5a9e16546e4583f25f4ce3e81c77b67e956ffde921024b41d05049e4e6e71bcf87a43377604b0565ef6badde0708757a5ee9c030b49828f2802b692608823b07	1633693976000000	1634298776000000	1697370776000000	1791978776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	58
\\x8c08e2b15d156d7c20038479713a047a6f7072cfcc1295bcdf95b1ddb0737d542894c182adc876f17b316ababaf987d0dd6c049909e5d8b4236faebf48b8bbae	\\x00800003e81f87e5ec2508c442c49372b74693f811055fcba98c9d9a1b4485271806fdc01ccc3c69e1f9eeb4b29c77336d1186d89049dddf91a628e944bdfc7a132b0e5ae7492ffd4891b77332c20de06540584494f88473038279c17c145e710d748ad8fff2d62c547804aa9e2e12d9f9f03122054fdbb17b4147ff5f9d19778cefe669010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x715cf50f07f0110a14e53f5d364cd866f7a70469e9b518fb0d788efea7dab81e22dee7902891bc41733f2cf42d2f005058014a5437a81769a633dd9981a45004	1638529976000000	1639134776000000	1702206776000000	1796814776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	59
\\x8da42db0f4fc64c9258d1056cbfc9ccf3f161907d4360b5dba620cce7787b52124e9e84fa1a228506c2e7c339b73d87ffbd15350ecca409d1e13ac697371ca84	\\x00800003b84b2425e4029e681b5d75d34528fce86148a85945de3c9335183c2b9b1e3b204b54212dd74844fed791f5cd6e8ebd23502925189f71f7e294657e63223eabb7a30478fe8ce166916d34f6bde49b024963402d82aa2f8cdec0bab21e4548b11eb4cb445b781c8ce5d0103879dbaa89e5ca432ec505c7132de61d25e5cba17541010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb91447127e60865c453b7e3a6a8d76c6c153432d65bf26f2b498f5ced8c70ac0f0a99f3f2f5efc7deffa6dc0c0f2226ff10961c33babb47a2cff990fda99e902	1610118476000000	1610723276000000	1673795276000000	1768403276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	60
\\x94f07df944c3a24c2b2dce9684b1bb54d9c4b6a83c877c271a9e1114b4e18dddd561807b5ff6e984608af1a991dda8c8c75221b72e33c2ae8d21ebe09631a9ae	\\x00800003c726697eaacca3d7f949e413095e124a89f6ff80d2ef82623d07d904f272840d5bf37760783f4c12b441ca8f5805dbfe8e6b5731091b4e84cba43e24f9a3286958a6292d02bf029e3227e06c34f1a3304de5f6ba4f8ef153328ddded4f58e9a2225df2e2097ab133543e531e02cd72e2f90fe88fa89a7f16d5ac9b16e65cc3f3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa3f3ff77222004706301e3f7162c4fc8b38f97be491a092f75d514fde81a09e2b0b09db44dc7c26aba28275d121aaf1f9ae489e923e8874af2448ec54db3900b	1639134476000000	1639739276000000	1702811276000000	1797419276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	61
\\x9494d82eae9a155920be67325a6321cb235e728c83586fa1d2b3001af9b6cd8b12afa52837e8178f55f74f6db8f8f985a0d6b0bfb461c2b5045ba2d8533fa07a	\\x00800003d86e21dbbd5048057c3f66b1564f53aa5e8d7a32b3cdf87186fd21764e0a8907e4201111aa79abf992cb0a63f2b02a994c99b7e408cb21c22b9ec1e0ad5e2c6ae9b30f2c3da238c7e4ddeee5b66ed2f0199be01e45997731b3d6ae1cd60ccd46e80fd10d96d73b6facf559d62a99f6b16a60315978ccd3a8bb3dc2096ddddc11010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2261dec773424e0b5c7e75c42152aaf9000b6ce393e6b9b9e88f827f3e82a803a383647468f04b78a815eecfbf724671778b47380a70221ddd1128c223798e01	1610118476000000	1610723276000000	1673795276000000	1768403276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	62
\\x9730ce0649886e146f11d66df032e311f8c45dc847f010ae14197951dbe8298f2453f7f6ca1e66620172f8120200713539cba379c8659bfc6e294f73b51eb7d5	\\x00800003f02f6a3daaaca5e92e47103ac4a9ef3b87146a70e50b89aaca020b5967c6b2aba0faf3afd0c97753dc00b581ed84e278acd1cf6f4c3fb463e255507698bcd367799f97af9498a8c631acd0771f52677c51b47a465091417cb92a21540958d28ec40a02033236280f05cbe20d7120586704ab8a612107ece99a2f2a2226963fa7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb027e0d4f4adc5a83cafa1fd2aa4b065d3c3dc6550d8a930e5b6a06e201ded755ec696a7e39e581b1aa37d8e354c9f8cbc28f7bb55f2b081c0903f388d485a09	1614349976000000	1614954776000000	1678026776000000	1772634776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x9c249a8ef8180effd662dfa619e0c60462683dee440e642152d1187a1df493156f0a6096f69b7fb07960d619a5e9e657ff0dcf9f42230dba15252b21f684f9f7	\\x00800003ebc16c1264e8eaee069a0ca92182956896380cf1065f67e15d0c211f6a4922112e273339a623533ede20bdabe281649d237ad08baf2c0cc96059f65ac2a4e2201674320fb3e110313c3087474b4d85bc7afdf2479840268e1bb10f92ff8825131b2d949dd37090d27f656754aa9437adb4ccb9ecd53a4d603a8b0bdd6553efb7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe1d7c520ca0e6fe0ee8f518f12a5c3861f83f420626762754a8161d870ecbbd7f7a22cc1772db2e496ef556ac0128efbda2490f542a9b85eff8fc8e2a87a6408	1620999476000000	1621604276000000	1684676276000000	1779284276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	64
\\xa3a02f25659063519cb2b5dd3140088a36a11fecac2ae4a82a39ea7c6d4f8b5a200f0c786269f4ca2b5a58f2d4de8cbabc053dd59e1296371418eac5b7f2741d	\\x00800003ce4d49304db0848185324393046e21b18b7c2583682adacf0375212ddc2e208605b98c03a79bcf8c7f4f30d84ae948d9cd6f1ec610eca6328a942d88957953e586510c456b0ac8b917be7ff0ec32c2d9166fa16f53faa6d4c04fade61bef05f9fff6bcdd31697607ff3d236bc5d8fb631d7f011c6d3b072e0d0ca66c786e9bc1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4e0d4a4463d249ad32131c39d5e48a4d411d9a11bd1ff1bfccdf4e2c4ee6c9973b56eb428ede63f0407a390e384130b479442ad6ecf39575aca9632b8966430e	1628857976000000	1629462776000000	1692534776000000	1787142776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	65
\\xa3000d63c574b43e7f4255ebe096b2051bdc90b62809ba0f265a2dcdf616b5f6154baf7ad6f9fe7ee267a9c08e682da6b09adec86720f81a2d6371c0381e992f	\\x00800003a988efe6cc8c13fa3134394ee02bfd6192a6928b26bf9ea25f69858d7aecdc42bddc86b4c6c0ad905d1dbffba3393b6095f9d937c6974f47e246dda48b56a7630ac9bf65075fb41854750cb61ae52d9eea6e55c5c0973d6edb2a896038290ba2bd2aabc8ba00ebd92e21c9d52fa92710b0e88cb4a78b12e65918185eabf932f7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2bc75d7ef946b32c7bb92625c204d6e4bed553c4b9d361b9d8a050d27359af6f362a28af61da3a086bc2333b87e435a055e5619ac984cf6d7c62fdfb374baa0d	1619185976000000	1619790776000000	1682862776000000	1777470776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	66
\\xaef034f7ecdc98919cd321ff4efd6e4c4f7d08d40a5f2bbd52ddc9abc63d77bfe96b60054eac1c3fe134f22e8b45de0e0e3ac66b7cb3ec65e8be2344834815cd	\\x00800003c9523388c9dc652e5269fbd1c3a5ad8cc415c2fb42b84919c0c5c1abe26f1a8bb4f411de527782ab7d03efd21df64dc0736991e9d0d086b05a92fffea257ea2b168ceac7d93a7c1514a8b1defd082cb3df06738debf20414b8fcae9f7a41a8a433ecf1228d01cd058a2670997ecedb30df5a8f9024f39f8a499994817e1946fd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa20c19f267e240835cbf11134d4abe39acd16f718ee78697bb12403f77c90a72aeb784ae94a83427d4183759db9bf879ab03f3592780f7773d025afc8cbd480e	1627044476000000	1627649276000000	1690721276000000	1785329276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	67
\\xafe89abf84527869f395d3c46ecff961305b723810cf2785486e5c90019da95b4eba78b84ec0e1c0a867f70b5d405ea3bdb832783e4c3354c53c554dc9caa90d	\\x00800003c6e1a1f137ace2428c378cb133aea9671944d6dcc0f022e51f75e8c713e50d1a64c36fad9fce026c408e1c1bc53f333328fa0d3a583d4d81e45216fda93415d36920c8460c540b5b1e7c0475c84cb34613cd3453eafecf6950e6fcb769ca1619ed86896ee0c365ed91f2bda938edf0a3e648fd5cb1fcf2cae40f4f8afe0c4795010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7c5fefebca73851e4feab9c42e876f769cae5c1dd303c6369924c16d4825beac8ac6d20ef98fb7c6a3c33c636374154a6a042e63a0a2d97e777a650885b0e003	1627044476000000	1627649276000000	1690721276000000	1785329276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	68
\\xaf34c00ef320efa5fb8112046efd2368bb99bc739baf42bc9fdea1d7d6dc7c354d1d72b61dc6fec25171eb6cca71ab6f78b7cf06bbe2fa70c6acb0c2234026b9	\\x00800003d86549f63e4e32cac77d5f66984df25383b06f77cc06f80604b423ab4f86626ef09db224fcb6960bf353381e42b4b3ab792f4e359b4741cce149eeb874e559987702ba48fc576bb5b7d3480c36369a4448992acd139a30327c6c19c065ef498a7044be611be4949c5430e51c41c8e80a9dd21cbe319dcf93a1868fa686d30d6b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb03052af85a84b35d3878c33df0c96ee36f409e2fd57badfc05cf703d2cb7bf6d3afbf7ed3d3d6332dec405f7a6fbb3dc6c20fd8adffb446489c20d86c796201	1613745476000000	1614350276000000	1677422276000000	1772030276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	69
\\xb33055a45694bf2f763a32ad31286e4438bac163ddff8fbc366564b263afb32610883d779458b7462e98b9536a137c2f36f8c59635e910a74d249d99206bc313	\\x00800003b0a7e8fb2cc090db444f015fdbd7d6b4ba7f055ecba056fee9c4fac70a21820ff2e7661418062da70e19dfbf6b53de25f5debfaf814174859632fe9d9cc84eaff91275fa50f558af69ef5272a6c837ffd2540c9e221e5f655a8c3a90b49672152e3c51cef0bf74d0e074a9e1ceadaded2f503d77c1aee21b66f64bb162839303010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdea9280858ff1db2cc99cfbb28016a3577c2acc923db677dfe13727ee32d88b0ece0bad541e8aee1fa271920fbb9fc6909b1be5dc77af36a42b7778abe132607	1613140976000000	1613745776000000	1676817776000000	1771425776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	70
\\xb6d42ac94be4f28d0121e50bb0558cc7f0e3096d9fa04e8e3f103dadd1ebfded8a392d371dfc5fe7a69648a205ffae975957f82b923d620fbcfcc410842aac29	\\x00800003ca03f909fba83e6163c2f8e4f92f62a52528dd0cc2bd63e6ca0cd90becb265f20915e9a9fca7b711a60f76dfaa9b3466065375b558822764bffe361ec833ff6bb5b1471299583197b755e055d806bbd5c948c7a51c63642f97daa182c4b9ca66c191cc33e901605ebcc33beb766d4bea4612870bdcc0b20f235d197836b85e97010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xee6104bdd2900f2a499b9be082e587b9f14a3372fdbf321070d0560a082c1369c329fbbeb4d61fb4b1b4ce476e362c634ee5042927000255fca35886e9530403	1631275976000000	1631880776000000	1694952776000000	1789560776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	71
\\xb8b0b76257ff7f3d7eba9b65c9be1e0114a635dfe8e0c8137866580da9fcaaf1f60658e5a45a6f1262081215636148faeb674fdab11e739c7b3d21ecfdb775a8	\\x008000039d77dc1729021009a039fab67fe19bda8164093173f8a7b60f5dde70399ed8e7508eb4bc9b43c5d55bdfdeb855313ce08e34865ea32314ea5416410dac5f85cdadd10b61083d9f67d45efe675fc29e28f78cc69cddb98aeb0c26ca73adad4cd7beb2a52233238808e0903f451472644f5a08320a5640a48e7a91c7b8078ba943010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xeb29d3d0dfcba20fbaf227a0906ec1dda2fc935f237c9f93baff6f1c99a683bb3c533da5360778f9bdd52913c466d2377b1c66c5a6252cb220c78d4991845409	1630671476000000	1631276276000000	1694348276000000	1788956276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	72
\\xb8fc61ba020a81e4ff250b005b7f6d668d0bcf62bcc411dae5a2ce93cd98a09b6637dd76d1f9eeaa649480b78cf66fafc9755202907edd5130e241ed36967805	\\x00800003d3137999a1547bd60f8ae4c159d03b2300a911c649b84b8d312c3fbc63038d54bf351debbe69dc285f1d4de4d414766b8cc94d418e7ac3d3d17f5451c71c8e5bb1d59b0a5cde0afa255294d53aa3c588584ee16857b096b8e680f384acd03d2f17dadb12b241fbd47065cf27a178ab2dc63b289c8b1349d11ccefba0eb13b23d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7e17fc7a910a236552e5359bd7d88d6539933a99a01539e015ddb054e5d80f7a8663c6fe2f9f5e6ea3a10c097363c94d2cb86eac592d578f7057a8bdede8670a	1616767976000000	1617372776000000	1680444776000000	1775052776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	73
\\xbafc8abd2e9fba144c5bf260fe60b906e4dcfc7c945ebeedc7433c1e29f09a556900f37cd20deb9239f7014d803dbf962ff4d5560dcfc514b56de998ebacdcc5	\\x00800003b72792b65690e586cf51dcc52d22dcbea76700df7c34f99f5a5b61a063550652ae4c3a2f1c200c16ff59c7caa2adf811f5bc82abf9124aa366367e74d9b70262285a70fcbaa7db75b73be05a5659671bdb480c11a331a4030c8fe845fb580c8017a4cd7d2442f2dc76710be3fec43b3b668c2bfab1385664e16e5c534e41f1b9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xee727c63e284249ae9f34ea98167e77085e346981eb14f801da396c362607372cb59cc2613b7df49dd9d700761ca6b14274e2ed5bd0ef7cb3d80dd1f04d44e09	1628253476000000	1628858276000000	1691930276000000	1786538276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	74
\\xbbb024abeaeb8101a4a0c256b002cbccc457c4ce097e391c3f4f7ab2df1efb96522e854c30e75841419b499519151f09246e46bb2c56dcc38e10296cc910d79c	\\x00800003a304e40a01e563a984b7fda7611ba4e7f171f7c3293547e12d2d1d385ba5b7678bb1770ebcb63e1403d954155e4b2806810bd6fa4c854a3fe1ae34029e4e4d4662a4a04ea4b862bf2fa8849d4ae37f760306080248999e397e7d581a80fd3d3b6a034948a48f86320794da0adaf4fdc5d18589d1350529144d4a41672ffabae5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfb630e20fab1df7ef6d4d042d554d08763ffef8455487e8618640033eea658101037047cf3f985809b0417c48f671804ba53d883ca0f9983597382438c62360a	1632484976000000	1633089776000000	1696161776000000	1790769776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xbbe096ced8da4778ad3f01bb452e8b107b7409311020b0b0295e894c6ed1e86d267860c86636947cf3a26367a75a5187bb6dcd7feb8dccd88ca12c5e232fe4de	\\x00800003cd7bb9e35b5fedb2c88f8263ef4eadf68a4202356fd516dccb0f3627ae276510b16c581297dcb571caf6c47a97afdab8282cb3e22c2ed9c87401b54b187f44f776c24229f080594e8dc8827507348d4650d12400231c0f84624167a845797d2ad52cd432a02eb5d662b61b922c3f4a05bf9623f7076ee86a76c766b3f0485143010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5b412fdf3e1fa34c68e48fd94505e0dc79baa795d1c7926b140711c51bc663436dca643b1ffc077a64cf14ab97d6c8c4966d8a34e19793540b8c97111dfd2c06	1629462476000000	1630067276000000	1693139276000000	1787747276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	76
\\xbf70ad594d3a889230bfd283349d566356fe36c2e493d03d52b3b1024b5380eb3ffccb0cdb8ce62ffd0e66df3451e7bd19ecff1996d70e03725281d4f6ff135a	\\x00800003d47981edbe90608f0e2bcd37274956adb0aea6d7f253bbd7d48874b636796dff8bc334c3abd30f0d7e342859bf79819c640b9938639c23d3767f64ad959231439c4828a339b8c56bd7d9ab40c897daa0a2fbe54415438bd4dce3f6031daa03c2e40f27e49b846eb90567dcaeb96333f7e6a54a3d067527af3727f10cc45da185010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9a9aaf93019e875f101c86b509cf70515cb70d1677ef595372dda7641ff479549ef38b23a80119174ba8fae7ef2706b6fb5b4d7c6647286f70aa7ec868737d03	1632484976000000	1633089776000000	1696161776000000	1790769776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	77
\\xc2385e49f8c7f2ac1139484877faee5aea67cc96fa700aa035c17786388778fd7552d3845922fa13ad517ca2c949a2404a8409b4d232087ca613d5d6f345b0cd	\\x00800003de8400b89afd38e7e1d4e40ace304268e7f73e6ebcb95a517fa46c8ac73b9199dcf06e428eadb9c44191a42dbe1796a44970a4bfd80925453e6e2c07ccd763b46da1da6c62c5c11f15ea806e295dcd9b86892f21fcb063b1258cf1211ac60722ec3eabf37b312fec267320f5737104e6f6473c3cfe1b0b4a6d9e57648c052c7b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd759d531ffc605c94d090e723d692af0e7051cf79f1da0e7b381840df77d4c996411253f2bb4eec4a50b2e518e0001658ee848e39ada39679637939ad846d507	1619185976000000	1619790776000000	1682862776000000	1777470776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	78
\\xc724ac2e74deaa1857962ecf70c3cc139169e4e49e4cfeac89e04e9af04fda717220c63e4da9fe8bf71804966c1b365270d8248b60ab4d030fe97a061ec2b8a6	\\x0080000399e9b4c17b74999480f28bf7f9fc98e04250564b505835d49b4c7e2bf025ed910e033a073620a942187a8e9dfe19498d4bd39bd2bb0c1c093e2c878672ee97ad681dd06f2040e65b4475c674b0964c51c836f5a1873d7b0519cdf75021f0d9e702f7ee06063cb9787228805bf6f778676c7cb8ecfb611112dfbee611fe83831f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5229bb79f10521aaace3310ead0e63684c2230b7bf037cfbc963251743458aa76f8d43289ff6a73d42b9dd137b9e1cd230967d86074ab3e2af761b07703e2d09	1636716476000000	1637321276000000	1700393276000000	1795001276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	79
\\xc7c4f35ec51d22b4d9b348147275dc3d2cd1684ee3acbf54c6015d8e6823b6dfae07c9173936af917984429b558b9ee1b1796315cd80fe3b27fb0a61d24fe67b	\\x00800003cddd21719e02d660f3dba343cf4ea58bbb82425f22be4b26718d0da4d97894490e40e3d8405e4cb06d21ab9b483d8dc8508aabe4524bbe6b4394eb92374d1607785dfb3ba37bcbd04be4edffe7836db42ce4e5fc8aa2475410d99fe2bba82713c2f861bea2bba590bd630fb9496d6b86f09409767a0f2c95fa5c9b256c87f33d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x930515611faad041d12883c8d303cba36c80f0ff32eae6e036af7a45555ba5c552676e266551c1fb5a43153dd8330d3e188e19db0697138eedc2852f837a7c05	1639738976000000	1640343776000000	1703415776000000	1798023776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	80
\\xc8fc885bd3e08295362588637a281832728c6a4dd2b7ec0484527cebb53bd119948de51aff8bcab9610ae49a28b49a129cadcfb05c88fb701a80604611e31bc8	\\x00800003c00054e0a5dd1782d49ab6ee5e2fe2eada03fe3d7d52c3c292ab68b6921d1409becf313ef5375a4130f497a0591a138f06df6238f393d4d1736284c1290e6a95d91ee9370ee976a070c4119bb75aba80222d7564fd5b81c33d9446b3a0ac1f65f2bc3c958bb130401c2f6257a2c0e763e9f21b2214805fa04c8d2653b77ba425010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb8fc2a1864ddef99cc4a7b568bb34b363e91f3411ec0c825d64e9d385b594f658b5c8ac11055f784ce60dd38b65fb5bf9c4610f70ead69340dc18316d3600b05	1633089476000000	1633694276000000	1696766276000000	1791374276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	81
\\xc9a89ca413e78e50c714a9ef22f946cfd91cdf7f46b5a15084e557541aa84f1f4cf80ab73386607f47f99936930cca6df2128a2f5939f9013b7ec49164c725db	\\x00800003d9f621f8d55d22c6b4a7c71a16f2601631e2ce146b7f3db2aed04c9ccf363415eba203ef5ba260fe4bef5898de93a0c99f505a8a3589a338e5b23984e87704ffbc097367fc3db772e14cfee03eb6a607e71fcb8cb09761ecc9d0cdf43334abe072b38948ec87e9ee82fca6c264f7d6d5a4765378f53ad0dd55b7d108debc9025010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xca6c33382146c402cd5a9266ef07c44af7c2e9929c5dc98337207d0c9dd14315c83ae22e546aa8e64fd0256febf10b9b4c14341138045bcdeb0b5d25a3309803	1638529976000000	1639134776000000	1702206776000000	1796814776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	82
\\xcb24fe53ca6d9d963b1c262aa2f7efc03e84377cfea2b4e2fbc7c82028678bc71a3a3a6fcf7cddc479424fe1552dd5e4582a57ff12e6f9b9edc50c34607e7a67	\\x00800003cc6287d861a8554d41045c88d0e0c43023161c129a010bdabc65a2ad38dcc919a3522667883270bc88129ec7089d593a397ce89f1a94777080fae78d0f5a66b77c9cf03161a7bffac3a0a1c0a320ecdf8bc5f8a35c2cb5aeaaeddb4fd56d1a6d057688be71913aafb67ac72bd3169fcc0dcbabf158393580908f713082cac763010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6b644e042753ac49b7553bd11ecc79118d2c7792afd31a5be6bc9b5f576c5ac6c2b8db2a57fe2c49623c79208c0da0ebdd8eb2f62511dca44d7138dc22c40f00	1610722976000000	1611327776000000	1674399776000000	1769007776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	83
\\xcc9c81267b224cbc54d4127fa5ed639760d24f14abaaeffc7d7c3ec24ae632c42ca4493b2ab9dede92012e571467b01ad8ced43452bc396f8745d2192275b31a	\\x00800003ac13e462eb9a4f5ecfe86d32510f63a5dd583e1d83ebc6a3ad716e6217733727205a37fff6899b315a547164a623ce6cab338115d0d735e8de4c17997c94508cdce9004e0db0bfac74ab0ea34f04c71d95ab4aafc5445cb573191db5bcfa8acb14a89c9e9e0ff98f4d615a360de8570e3e46ab5793c19a8cce92094047c11389010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8db9cd7c5f1b2ff3fe058ef4be25c824dc684e01ce09ce2c8b3d179b75fb442157d474090ab90cdc9cf2feccc1d497da91d07c330ef02329222f0fb81a6f6603	1613140976000000	1613745776000000	1676817776000000	1771425776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	84
\\xd1706386f9b0fe3572d331a0eb38a5d36fc498bbb66dcb3c53d2231979e4d0c9f993768a47aa3d2786d8073249b279a750976511067a3e0a205ee63665ca4724	\\x00800003c4f9d5f8ed2857ae64a118cd7ddcc47df8126a7ed695cf7638de8585e11a31f4e8dfa57839ea7f08016c4112578343a36e9ba8ead6ecd78ea655bf9b69f00e2595b3489e2632e6a1447c34e6576a4afb25ca47ce28ff27c3eec637e2ff42b9b5d2f64cbc6b24c9c558e943b0dbeaa88e1bf88a0c4856418e5b0d9c55dfb80e53010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7a00d8fddad3bc2fc85f838559e4c36d31bcfab68d44b817d8b743a0656839718742ae8725269ce3bf1e44046275262b413725ccb3b7fe4dada30c2c9bde2f0d	1637925476000000	1638530276000000	1701602276000000	1796210276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	85
\\xd12436f8baef86cadd1edfdcbd9bfadb510cad73883650d20b4f8e0effd66b9b5e27c7252e60ffd6fbe4a794208f5d033bca733c04dfd76501bdc31c2db20b74	\\x00800003e96ca4b4f881275876a21b38d900bf7950fc5e2c14c5cd7f110494ecad492dee1ec7990fa15a1cddb31074da817b0eb3fa56d2accfd065e4f8ffafea92c59173916327d6e99ea794558cc87e63348a8d743b1d7118daa9ca0e3bc151c891dff3773d5a7782784bbb758b077591407bf312ff45303ee3d437d1d7f3d931b2e657010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3ab256ef9e844961fef9ebf76b9bc4bdc959d69286f30b233eed206fb2079e57e9d74be1a2188576aebf0314b3bb86ae7ef26d3eb55406ee8828a440513a810a	1619790476000000	1620395276000000	1683467276000000	1778075276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xd240ce0e38e24d25be1dc3f237ca5074f4464b4e943abf4e58213018e10e814856dcf51b9c6449fe1083b4368ef58798a004ead3484e5ff4a3b09f8377312ea0	\\x00800003acc36f717fa02ff7d3c9e74ed25c646270507f2817379a9ad43c45e42fc60d3b8b913311532bbe3f55ae883dab1c632c6eb1cf98023135d04481081aef36ffaea5ac053566db7a1a8cdd24583f54d31dfe4b7f083e63bee3c5d67d4298f3521143683fa1a05c4a16fb0f6718d8a9885de5ec195478723005f004cb9ffbe2e151010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x07a95ad96946c26c45d8eb7b47e3c755475a7fb5462561560dfc624c91ca560668e01fbe216113eb0da5cf629c2266409f7a7bb6b2f8b7af4997769f70a0e406	1619790476000000	1620395276000000	1683467276000000	1778075276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	87
\\xd29496a874645a3e62c73b3b7ade2eddd4e33c82897b9d6a88dfb2b0a606e7e25b51b152fa53134b3a0585cf91119660ebae349d0678b7075e2ffb0ab7deaf86	\\x00800003cafd3ffbf3c66f14b3689d192db53b722161e0ffd20f35ee4bae1a100d9e3ccd226771e0d7a963a88b2706a65bcc5e7cdedc9e62207f484ed4e0bec2dabfa6456f9ad3a7d26e4d0e624b5c78d0dcdd76399b9a69d808d86345001f033be322777a677ac5dba3efcb7c1cac21cda93f0ab810b6c75166cf86c16c3aae912a6ac7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x368123d53bd6fa4523b95ac0b1bbbc15adb68be4cd92775db2fabcb5eb9a4cdf725cb7b53e40daff00bd317925d349b1db2f268de68e78251dfe254d7c330b02	1622208476000000	1622813276000000	1685885276000000	1780493276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xd370944b55f25dd7031aa8e2cdc3fddcfa45904ab5003fa62aee9433cf0ff1e0babd460c06096f82275fe7cd390d5589fbd8c28d85bdbc9223aac509f10fc02c	\\x00800003c73b5649803950e66c46523e480bf7324c7bf9627cf08f1681227f949c1aca55fbe09a1ec7cf11331f4a1abb06c05249357d8091aeee1a531b500a55af7171f533772ca32d3cf56bde990226003ff9b6319d98d926efbb17a4c453407b14611adc7ed21a6919abf758deb2f3aa231fa792fea3d3311b7c8c6918c4329266c7c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0c4a0ddc3014f171ae6c98ac5a6af5b13a509a1f953584d6c5f8b404c8ac733796a69e32648d2ce0e464b1953fb28af07808c0b72ce92590dcae597e866d990d	1639738976000000	1640343776000000	1703415776000000	1798023776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	89
\\xd890b1ec4c846c466c461e9164d0bfe133704ef891e5105734c89cdbd6d5016b137abb40e379c07f9e76c6b476b94a8d32a5b24444454d2e6db3f95319ee224c	\\x00800003f2f44f578c4f39de9c9a9c670aa6b8c74e76188a3dd030fe89d3ad4bde4f5063aa781f9dc13b289a6a4f65d9d383b6ed20d94e5a75218d17030d89505b79562505a547bbe9a62c0afd6ed0c48a4cfc5f48bae59410e4d00a0f14ad11e284f679fbb66e87ef530d0697ec3f45250f8a6fac0fc6fb28891ed221d282139e6e6df5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7800856ee31f856920fb91505951de62824d3995f4ac34c68646d6451365a709455da8b7c1c1b7464f878ba76f768f63aee9f16fc92765ee2b6db28e86fd1201	1640947976000000	1641552776000000	1704624776000000	1799232776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	90
\\xdbf4a8b91ebb2a902b03981520994a504e90fcae5ec08d9c3a2041d2d4db2acf87ca919ca41349d84a28ee8ee985b63f10dbbf2f2a88bcc3b3da90f62f8cbde2	\\x00800003b86061e015951ef7e864041041b6753cc97a3ea318bd790ff33e2164472724f8fea53125e7954fd98886b3ffec6b933d6bb713b588b6747e224fc5081bc177c789e9f94e69bbc64c9f0bc340e16a5b01c6e7abf0e47e053a9d289f5351f8272760b6393a4b4d56f8a6df7377f3244f7158c2621170a799b4e5b1a3eba94d2b17010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfa0b0ecac5b7ce189be076249fb08b8c42eeddd6e190d9695f752112d9bcff9d67cfc679d436b16ec5241257de4eee9a05de9f346c9c41799f8c27a626978c07	1610118476000000	1610723276000000	1673795276000000	1768403276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xdcc85cc9b2a50238353cd052e5dab35cd5ff46ada7c9b24d0ea8086669fe579c76a34c230bc50a7d18928c4b5f1ec07623c9c511433e7fd18c73dde656fadb1f	\\x00800003bdcc5258bf59f9f792667c03d07f1238e83dca78d6422ec64c43bf5252afaa83d56062854f7971dda35541572f14a15db40520a5458736cd6dc0f89f1ec68a93811647af9a6c99501fef0e696dcadc88ec2be09d1804d371d8edd9427bfce3559c551e485213075906bd2aa567ec464f2f4b868e592a49614524c8c2e756a95f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0887d9fa2b54e5ba634912f35eae4c15759b23dae21648abd52529c4404a1c4a31cdaad142e1edb41eff1bfd23370d16d9d27de675777bc505ee5780fe3e8608	1617372476000000	1617977276000000	1681049276000000	1775657276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xdd280f495917907e4a0f673006a0134f0c0e81786880107e253e56f45f7f49e72abd69881aef0312d7ca08a94764456d84b7ca386ddae1fc59b85426b52d81e2	\\x00800003c32da823f339b36ece6ae526f56a2740402fc44d04a09d852e8521dd06834932b7d7d2a4183f3d7e1148e3a3d947ce292f015a7d28ed94940af468ceb88100bb9f992cf61f45564e142b47dd2fa38bd871b377f8218a5ef7b9675b3380e86826938eb6e803db27d57628f00d5ebd6704e7bb7a811faf75637a631137df35aee7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe86ad0f666f80cb81000ccd104b998bde74c41a03cf341a72385287d252a618348ef6eb0c07a04786570ea40fa90d4f0d7b12e16269d85517e89fc29b56bee05	1620394976000000	1620999776000000	1684071776000000	1778679776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xdfb8773f604d1252d863672a62902241358f3e25b959d8a6986ccc87d7510fb8723f4c06cec62b09926cb46e44f87226cdb20ebcc1f34fe1624758b95566151a	\\x00800003ddf42373ef41e5ecfc06a9f68fcb048e614ec4733d182c9f24bd9dc2c736e77ff34d62edbd96942d516782f8d5210506b65e69c1b26185377b2166f1a80a8a74d6b856495a35c942d0d9099654db86a32b77d014f7911a6974f96d68a5d54fbad82ac55e0fc0322fe4fd8791347c012bebe203eb95c780ce3d6bc3d8d7821363010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1992bd84534f6a9d1c6044616a98f42c83bae11662c41411186841030d721ea55072771cfaa5d58ffda3918f36947ca9606e40791f32ab5040543dca1755c200	1623417476000000	1624022276000000	1687094276000000	1781702276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	94
\\xe0a00c33c8397f536ca9f870058e085da37cf9927df1dea4d43dc86c4c0d260a2b4287ce49483e89f46b83e015d5970ae19081115ffbdc0c010929aa0642f9fa	\\x0080000399b1b94b5dab4fd0c03b5b8879f704f90eeea6c77b581245114651feee35167c704471979bc6c4803716dce2e2c4841afe1dde62b68fe0ebd03e337a8a62abe8089d8abbef2853911185794cd89dea90f4f2d1d6973d1a539a4dfa97daf5967c0579108694f42863c691265496d433c4ea30f352b8d0551bb74b19dc2358f539010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x536e9c3a7271056cca4b36cbb3fa1d64ab4936d111510be0fea7d1326fce06271308c64d875e326bd8c4a6dc9db845b5de3200cc8c2d3a8ba6885c98b084ed0e	1620999476000000	1621604276000000	1684676276000000	1779284276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xe194cc95b1c491359e1a5ef2a0d8fdc9ebe34f45c779aabc9d36ffb9bf2f76087f73f1aa4a3f221ad989f1939cf514ccc4ccad336750c5ceecaf4d8072f07743	\\x00800003dd832c2d34e32ba53314c5f2cc9848e4799f7d18342d1c3dc601e41601f1bcb137a1dfbeb879f13ca33a677e5d2df3b4358c42bfec433c63cfe5e7b083d957a1b57712e1763a573d47d4d849c8b276248fc23caef91ac211bebe8061794e569ff5317437d381b2b8a14ecc69672488fb69b884d6076d94f55021b2091af981eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb193db717be73d1ce25562dfde3a1b1d68ab9265846d11758c4292f7d105e21fd3d45b11e09aabe9dfcebaff7197c33cd886e05d6251795b8c372de117fcaa04	1622208476000000	1622813276000000	1685885276000000	1780493276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	96
\\xe16442b5f2f0a9b9da6494a9c4d8e0dde3a89a9a69aed18e11f710aab51322aeb4f56a56613a9ef7b9365f72d2d420e96899a50942e6532858bda4d97174860f	\\x00800003b738c1cfcc4dff877e58aeb5f602d1bbb4c98a844cb75c6fbfacc210e783cdb8f67fee048bc3eb481df765dfd7e1599e5f01134588169462535e9ea284421667d3d840652c832fc8959b9218a389d26d054115a2ed0b6efd57cbd518699b149f478c8c7598c1ffc084452da3039de80eb551cf070d030beec9825586bbbcace9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2209c666a97268386cc0da659194ce4cb406585b49942b386ce99dca3a17c1f5597639c8d386e2a5db0e98172d41b70f4a90ad6e64d9a48785bcb331c35e5905	1638529976000000	1639134776000000	1702206776000000	1796814776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	97
\\xe238ef348452d6634fd82f68f10e998fc6f1af2ae760d6201e79bc30150d82e17dc5d54608a29d0b98800861eb6cb774c3b344ed50afb1d322d248c6175966d0	\\x00800003ca584aa956b3f9aaaa91be8531e0d285d903fdf0164b01bd7c00d223ab2729c3834e836ca3a5f063ade2b3fb236aabdf544afe9946ac9545a22dd45538ceee1df34599adccca4c91aa2d95c99e9bd2cebb8050747fca0ce902d7b8481dea1937a0ac64d6110ac524a127832ef0aab8cba9597e13d776fa82b7c382159dd58967010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3f46132b41052b9158784c0535e2ab3c7fddb7eda98ac8a579954a7435a3ee81269ba6d6a3ca4373db6bfb442ba0e09cc523f2f8abc19547ecca47b3d61e360d	1628857976000000	1629462776000000	1692534776000000	1787142776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	98
\\xe734dd06741ee67390d78242c45592f0d2bd152218450f5395b2d51ec0d90ef89b8c0276c08e092917e8620259952ccf073503ca33b271729eee28c27da42099	\\x00800003cfcbe3a7b5aac2be48718ca0ad3181d942cbfd08fe230f45426d91b0215a36dd90910e2b73ccc28731ff096a2efbf6987412ffee1209a3a7bbf73675382bc6fbb62095b331163e8d7df735154e388cce6da8dbdeea2dfe321dac31ed9b64cb711239cda496a9a9672e34ac49d4183136e94d785060ea65a75544c7f39c38b5ef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2d409af8aff7901cb8cdfd794c54f0c243b7b3bab3d6fa4972ec352497d571013ecaa3bdedc6631d1078087eb956cc734ca4809cd16f56b6b2e8d5061d537509	1634298476000000	1634903276000000	1697975276000000	1792583276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	99
\\xe91c28df0123edad8a49b92384aec78f9629de17742647e76b1ba86908b0d6dacb41c395cab6c6e10a43350eb8f9ddb547803ba6f83bbc22f8f166fa9fbf37ab	\\x00800003f87276dfac88f71cff5ba548703026c54c1650d3089ccf006ce1ad242c7b0a08c8e3b92183b3d0e2bae72579883d9f28302f1674f08b30137cfe94b26555462f7e3d616109432f07c1884b68a5738b3a9449a4e285f36ec48596e422bb06b45b9500fdac16ccab25fb58e5396e37484f5823b9d1571929247cd460fd5d480835010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x816399151b5d9e51d48303b7bd30dc54860e6c0ee9768c9f6a94af9584e18cd5de4f0f5bf7571326f65d21907b30e6d549b05303ec658b65248027200e973b06	1634298476000000	1634903276000000	1697975276000000	1792583276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	100
\\xecac219b4bd0d632f6fa0e6370435548b7d1cdd33c0b5ea7c6a89fb4aaedb77e961676b8bbbe730e52c5b653c0faf94f9e934c2e99af68df4f9222539342bbf6	\\x00800003c4c0aa90b6c5a800eaa463efcd308a3275acf9e5c7e21d2ba4ff6a4c561113d7443a4a31cf3e2f5f1acb3d44cabea42d8a7b134e7bf9c4137f0d3e74b72bba01fb5ee94a98fafd03e9447a2fb05f6457b7f473bcbf11d89c02d18bf16805f4df43bb9428c4a55d465dc4adb23078baa189cae72dccaf520088743dbfd43db4eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfb30c1a52bcc833123addb361bb9d307d0a9f200284d2b1bddcd3dac98f5c1030248d15981dc35dd28f20846c3a91540941a7430ffcb2bb3781521b483a20108	1631880476000000	1632485276000000	1695557276000000	1790165276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	101
\\xef18d99929b1ed20f13db0fba21d2a395f22b9fe93e2dfbdf14d2fbf813ef3242acb7d3ac5ec8facc8553dd1b4ffb04d411a7a906f6fbbd39b104d39c9c7f6a0	\\x00800003d5f03eb5141c3ecfaa0aec99d5f713708c3f32d5b1ecb109cab2c2a716b8174041bcbe5b162a9aa92248f528ee1cd73d7986eac5dd1d34ba3d0d108ba435be6af5f8d3f7a498305fe0e646306dacdf4dcd095429f9b3cfc9fa835ce15b1a4d35dba0b7e4bd808c058b11830f455168ca6bd0b55f283a88d733cdd1cde5e43eef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xba914558e69d39722cb1aed34b961a071d1d63c832359099fc41a553d7e271fd01815949b4a8c9a03bb41162af11b6f512328bd4adf0c6dde6edc2a50289a300	1627648976000000	1628253776000000	1691325776000000	1785933776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	102
\\xefd00bd2d834b5f3e965fcd13a8b270f07bcf472d5895b47e5d3f041c5303f180fdbe9db430c945eb213aac6f9e2a18325a41b6799f11ec3f76f5693a03dcc42	\\x00800003b831d70b8aba3f01b12ba1f10175759d6b4fcbca7e3d23e87d6a2053ef4323419bf61cca0f5dd0b0cdcdb9e0e43a406e30844f95cdad2e279805b7007a0430e73bfac3104e8ce500aaf6ee122ca35c25bdbbecf2edb5f3e31cb2325cd78fae2062a9e21d2cf7625b445be00ce02356cf310e74c10e9d2e1250ce3000441d3b91010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x86d84e6acb5e8ef4a3bb93814bcdc8c33018c28967852e346dfa2099ed2b710b4a016ce1dce23af60b25b0e7b65e23758f021cba16806fefa4fa3eff43d3430c	1617976976000000	1618581776000000	1681653776000000	1776261776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	103
\\xf1fc1cf4c1ce7ba5a0954da375b4880be4bf3ea0274972c44a7c3c7af143dbd2da914e3c20363a486486950cb202016f8e8ee89cf3bb696cc0e4fa139fd5170c	\\x00800003e3f3096a7d81f966ab26e1a3823e90e43f6535ba7c13212f3ed04332538026cb10e2d426eba91f89e5276409e66c11f3432959052cf5b9c9061ffcab7915f6dc8d90960768fa536f1f27ffdf769acf4f87544f080a637287875698871b42b9cd9b073b2f5149b934d00737143307d4aa21dae4e96c9a586bceddaf78204c46fd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x34d78eb73098fca2141130574778fe79c33657c2d12daac5f9c27c6d123cfac34884abfa460b18824287606259a8afe0dcbf9672f7782615a7dde0b271c70f03	1624021976000000	1624626776000000	1687698776000000	1782306776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	104
\\xf160190ebcda196b6eabac07954012384c4aa420b60952e064d763e4defd01f3bb688159bcf2c28a279f9e50a060e7019e427a44a1d1b6e5146d82c99eac4ed3	\\x00800003cc3d4f19155e2ca3d285914d793ce0658daf4099ba6ee4ca17c58773c2288550475b78e95d5a2ec16d0b13985eb1071628d196628073212536597e7e0527eca1556ebd4f43edba03ca7816b91423a9a461068004cb919b059cf4210cf64a68137bcc559613bd7a9fdee60ff435a735b354c9c38b2f8055adf47198c0cdd8e65f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb77a359707e0c8e8b2d814721c40045e65656cd8677a3fcf9adb614720855cd77eeb7d89fcacaa4a39e592d92c80e16b79b090865a9e90e166d3960cf77bac0b	1617976976000000	1618581776000000	1681653776000000	1776261776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	105
\\xf364f2b319954a5c91da495f0394d373579f65835594789a781e5efad179d98fdd5e79a68753180c4db42f0b8463af2fa8b0db69be1a48a491099f600be9aeca	\\x00800003ef6db1265ec5c6d070eed4a27d5123f219d107e4065477e3a79aba0d6dbba6edd0a072afcb6123c4529305632a9b4ea3d5a131cc0cf14e619bde8c8edbadd37f477bbcf9f717ac0e7ab48e9e4fd13dd1c76a1a5767594b31d6bc7f7279f374ffbe9c0fa42789e6200985a364a1521b454f75435919ceb0b496ca6079af6958b5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x04d62a25479728289c2e28a9d7bbda4b0610ef6c5e77fafec617dc128fc5c41c8f8ecfd948ed55c3f7f1571b0a35839d2f2280e0907f37b6f6660109fea78507	1636716476000000	1637321276000000	1700393276000000	1795001276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	106
\\xf66465530451fb0a0b3c3687ce0185bcb97723961f76d054dcf3e025b21347707a521e3153567fbe0338c518a7549fe3059ad4755edcefb38220a57b6a9408bd	\\x00800003bc056cc683c473f0bce951189486e1629d4d5327ebf53f144c3967991996d19b94103ceb33c1636fdca0c85cc1ead16210064430655b7960f37c1f00e6ef56b1022f5d8926187116532b302e9e556640dbf2516a4832763ca9e4e027340ac6fd0aa9158d0efee70372a72214ba3067b2c70f6357942a1f58c5f3e6007e1c0487010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1b198d4c1353e0b59a8914947d8baf5daaf55f7ebf1b27a171e81208ed751cb58cc95c09b00f593fdb7566d00943284f58a9fb751ba0e9156ba5609c5dbb2b06	1620394976000000	1620999776000000	1684071776000000	1778679776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	107
\\xfa940861d6edb69ce12529b902af325304671758db77d4d07c1ea0d1cac514529c328c9040d10871fd888ea625156dda6f646256cabcf2f12bb83e542ca644ef	\\x00800003bfa6e99416afb677c9e942152b4e3ea0ec9bc88c9886430fcc8350a91333bfedc2dee35d959ad02f525aa6647e300f3ec08175c1376a15034f28777a1ec01afe4d909e0b0a2fb850099df6c9abe298f0d7fb6f2ff3de2bae4eb9f00492deb8eb543b84200d705276e6a2018f93db9412966f6a7ee624aa416e4713034ad5d19f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x15a9ab93293f75a126298c76eecb12fbef7f001020cf93369b0bda334623ae180de65a62d7e0675dc0322da044ab149c52531fe3e636f5a6a65b11cd66a48500	1622812976000000	1623417776000000	1686489776000000	1781097776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xfb688a8b8026a67a5deab035c69e07af977df1b95159e4f1afea2de266f318577e917eaaa3cfb56bab2a2f77dca936e5ac39a6fd1c78a3148b3c134700fb35ab	\\x00800003c339d51fd34573c8e8481038ea26374ba3f0898dc011066f7acf33db8fd6b69dae71491f2e9c1aff704ae62a02c1634d5a1bdedfcf25ea490031ed5eb3b5aef1d86079b010a517d4b923503b4af5ffe8a932e76431e710a5013b348f3e53360f41af2343ae8d48a2af3eaaf99937f4eec7e4df36b905ee9ce8e4843e5e507cc3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6943dcdc9ffa67d8806c728a0f4edb69279d923c92c81dd4e1f753a84f8a39f39ecc68649bd5709ede3e8e8556dd2da3ce5ad39674f61ff0eb7791bcbf418400	1634902976000000	1635507776000000	1698579776000000	1793187776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	109
\\xfca033629d74981cde2e86a3aed6f3e8e13adb06bfd89b629faf5ff020e2b3b46e3aca18f3dce0534a69e35f635def7a893e3bb62381661f44565f11033030f9	\\x00800003cf693896ad126aafc12551d168fa1782663eb57d0950bfbab5b1086c475f02e5427a6cce30a6b615d02439dbc7ee617e5a1fef2b2382aed520ef2ab109a16621b55c9343b4c0fe62b84b99d82d4cb922ef391cdb4c54298c461822f75891d41325b67580f569aedf619eeb7c3513afd6bc40b55a6c5f0ce9661b800564351a95010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9f482a41e83a38c38ff6aa65e78dca11f6a2c6c24ede2eec2c8a4bc72cd66a27423acdc8b88a7aedaa6f9704c16a1cc09c5e46c6a2ee5da25c38951415927807	1636111976000000	1636716776000000	1699788776000000	1794396776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	110
\\xfc5c801d5c6748e463101c27eaa11872a450b56d6b00ae42073580eb83b455435ef792bb6e7a3368ab4a31da3ecbcb63ba0324601697b47237091e23760a9b78	\\x00800003e08208e9299e05ef6906d0b3b529d766875f7c764c95fcc45488f7f4683fb061bb23139311081e15a151e6393bf207cb6e7134c8acd3df2fc30a79310a6ecf3eee3dc730a1d9f3593ff386e41b7891fba8bbb184377d360474a4e5fc40fdc6b3c6cc9e702b4e4c8e6f6a007a07ce2af303254810a99d7d71d07c1629f90f69d5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd71e409e3e6dd67d6bee455c504bab319f0db0320d2a0258d87ae2735c15a59c6a1b430d029b2266ed73776875988fbc333d8d8828ed964a584b19b0dbac5b00	1619185976000000	1619790776000000	1682862776000000	1777470776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	111
\\xfe4c0a49507ed98d501e05149b268f5e98b278af63c03b925e7b53b89407cc7ec593de892745be839b2c8b7631d1ea1767ac48761df662d5b91dae64b7f78be6	\\x00800003c3eb6378135aff99074909dfb02ce96a9f1aa130dd06bc27c9d542cabf5190cd91c282973019c6d7a6e50a322d09bd89f64f2b37968427cb79fa2fb3f55132c79db3995fbf0650b202c2a9dd0646dc53036dc70d8eb4831174ce43dfbfb00fe1086c75b7152e81a3467fb17992c3ce38d0f0a0ad27f30bbcc132224cd497373d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf2350de8a2d138b861a3b77300ac48ea450a0710e4edbebfdf12564729ace980fb9521db17969c1871888ebdada25ee6f4b4975fc26b63dbd7bdbf5d6c41db00	1640343476000000	1640948276000000	1704020276000000	1798628276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	112
\\xfe54a82bb2694036145a96a86e3921158017ff03a63edb92bce366742764ae68ab363b57e8a973a81be69f847415c211f5c857ecb7b9d7e90d5d92f1d4e58e95	\\x00800003c698b9a6420e1cae480a42e0f9ac86283fb5e4395252af07d1f1964f6f15e02532a74d692200de89034ec9fced659600a20b173619ad67ff7489f4b63240c6edc2262929f3a5985faeff4c03f24f23ae8f7684b55774459cf3ca70c3a3073ee012e9ba3d193f1f60b49aa63ab27e66735e6fb5a52d35fd431e3192afbd2f1905010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x07a5c1bf04086a54dc84cb84b16d70e960804496c211fff2cbe162a1f88385c3d1a58309be3378ec3d48fe848561b9f206db1a59e0505c4f15072ab666144d01	1639738976000000	1640343776000000	1703415776000000	1798023776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\x0295c03528955ca5ba61a9d48563387118395c7d38614bd8dcb441462ff19d4e0fb53c7f5ae17576aa416aced16f1018c961c9da00e1f17dfcbd99447bc1f41e	\\x00800003ce07f2c72020d32d6200432f2cabafeeefe770614075ab082c5ad56ea274ac4ba9e9fbfe5b6878e7704a10c1a050496ea61f36feab915d0dd6d054c60475a5c4fda0c927ecbff6d0875d49137d03bd92222398604f71b0de3dde8b1b6a27da180c28f3123f8b60726c9e8fac6208084a37f9d2c8e23ce24d46ac017d9ee29f4f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1721654d4c6860e74b08f24c8fc0d5c8adfc078b48d50ec132a043faa45b31b92be8aa740ef188e5725f72f2b0651261e1d72b2d1590c45cd2d2739198ed2702	1621603976000000	1622208776000000	1685280776000000	1779888776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	114
\\x03ad8b7fbe6e409c9828402a97d3cecba5b37d87692f1f09f87e46f70fc88025e3c8331ef6f2c6e57536d7798641bd61117b1d86ab88037999b1d56e1b8bf021	\\x00800003ac42fe40faf82974398e413606599115e7075af035133dff2dca1413bbe307ebc73c9f3b899c69837e42a8f91bb80cbeb90b027b41d4492ab8de041131a25d160e3d763c74c7cebc63e13b51d47188863f022830b79e5d5f6e5e3a8d14acd8d0dcf0225dd53e4f7b2dbfade8582a9b7b46e9fe04bfd2ce401f71b0260ad56da5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0a748586a659b8f7b91e81e2a4d9c35d6832c5c3cfc4ab33d11b9e081e9b8148550a364a24639b2c14c9d6e6ffc7dd0598979fdc880c166cc6b1e07601011704	1614349976000000	1614954776000000	1678026776000000	1772634776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	115
\\x0441e3d56f3ac97f14e99610fefd6a69fc4099c57fc5ddaedb560f7ecdf02ffc9095ebc2f636f9e69509dcd8a02ff6ac6d562ef891b59d0b0aa0ca4b1f6d6aae	\\x00800003d18e0ee9a23b85acbcea1b32e1986b8ecf24e37c699440df512c4dac39ad53793a855ba1c674eb01390572ce813f5564928ef6bb03993c0b8be979b0bd93dcdbcd598376ec5c63b74999f0d9f65f032a5256246049eec18427e2bfb9353e278e5188172a05bfc72201dbaf6e05f4de87e6cc1168c548574e7ccd09e73ff8affd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9813509762a4c449ecb4fa580bb303d7dc4d819f7e0e22e2e930859e079422b9096f1189d9e4aa5913ab594412582af6ee4aae285b00c9ec9e4d398e59ddc901	1611931976000000	1612536776000000	1675608776000000	1770216776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\x04dde1fe1c4316c1ac5b50afac155aa14f4241e5b894967cc42a0380ab0f320311d44ce610d18a40310f45369923b66ca0df3fd51ab1e753294d45d820f7e9af	\\x00800003a9582987cb7e4f72a941034789af06714e10be05a386dd9742387cc5b5fbe804c6ded91fa721c77b056bc3c01d0511ae5ec4fc96bb0bef0532da91824a309571a1dc374ee672b9ae7adb4b2a2e9892c8a71e16f4ad9a80ce5ae65310833f6f0c6ae4fc658176f9bd0dc1af5122febdd40b2191458fa6d2bd3e67636f5c68dfef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbad804c4679053ee963bbc05f18a548b14d8d39b28c0909f5fc66e00846a4afae6d6ef77015d97d626f01ab7d67f154854d2d14d5f2fed57cd04ac97252f7202	1625230976000000	1625835776000000	1688907776000000	1783515776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	117
\\x05e9bfba605dac45c405a21687716fd1ee99db462edb8d50676315c0be5f82e5779b408ec93dd4512304a6f632b761b469c8b22af5abf2a71ff136eb38a2adf8	\\x00800003c6a93d079faa92298457b3bdf782505edb52a7282cbd4279397d328d35abd624cfcb6f4627e98b4719ae6d6a82ac80adabaf1062d69b2de2213cef54f2e7b0d56aef7b43553363eb5e1d3dca59fecee6cc27364c6bcdeac3b22aabbf9cfc57445425bdb87f48ec5c8295eccfb3783cfa0c4872743c1551ce1c5d70724891d777010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf9281ebf4bf81ad48e3308442bc899d1d9ca23b3486deb6f5a0aabbecbbd08c44a0a8b17850b8ea6e81e8e50181cb875c42171009e9993faa1197b81e88d7002	1632484976000000	1633089776000000	1696161776000000	1790769776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	118
\\x05790e3721693008d91544e57bfe86d92814565b1e3bf50277805bc4f1a14a438d5fbb1632ff8a5338c24bc2c5cdc08261ac458d7a88ff8db922a257ab60787f	\\x00800003a11b89d3794034bb0b07354c44ad7220da762a3e9e846de94c8f8ac4d9ebf0c6da1477fcdcf659d22c6c113ea65658eb4bba5e3451ccade89fd95ddd1909a4231661842c04bf5a44769ee811bf8032f98608e051ffef86eae62447a6f2ec82db7d4f5da4e9e531f63d6a7679425e06ab7716234e5b50dc8d0f3deb9e77ff5ead010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfe8fddcc361fb16afccff78b22341a32cc0013be370a3706f60780f8b34abe8ef88b13e539a393e4bd48aff61277765503eee821585bf1fd18a94be35fc7ba07	1626439976000000	1627044776000000	1690116776000000	1784724776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	119
\\x06e59a4d3b8f5b91824884a3af9ac3d919008cac70d391cf72baeea01af4721464b991bf7bb28c380b25c0012cdfa32bf185cf7ff563a3af92d191cc30344429	\\x00800003b741d97ac0286fbe0387525a69acd185530584406084f36ae66afe5df1bcc77d14f6325a7d20c04dcc4f06fe00bfe6aa38d7ee26dbac6f59626d8a2ad18f80381e85bb37e45ce4d20159b895a1edbab27721909f8eaf8b95a00e03d0b61d2db63764c498c2c1dff6d9b9a4ce08d6bc8b6b30a56dafd6521ccbadeadc7c5b9d9f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x292a65fe2bea9e1ec037c082e1b0f04d4f4ecebbb1104d5d57e0234924c3386757b84e6586e662ca2ff34ee2bac41aa1c8f3c0a3a15cb1bf92cf4c509c4d1102	1621603976000000	1622208776000000	1685280776000000	1779888776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	120
\\x07ede3ac351e4e10aed818b6e86ac3c3f2a22b8b30f9a09261e6942aeed984cec2c3292d28f1731e0bcd3764d8cefbdfaac2831be14a41e20a4388fc48abb827	\\x00800003a15f002289b2a1c4245a71c07211eb9ee801821e5126c6329660f29ba2d08bc6765405c4a930808c3ab688eb9ab4f286cf5bbc067402b2e3ddd55c4eb6a8abfd100352644cc216e95b91b8fe606779dd4be88b6121ebbf0eeb015a44d0b8f65d50713cd66e2b78d97d40f713946200ee27a0ebfb7695ddec8e45c0652ff988a5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9b640748043577078a5ab1290160e2e53d69b9846d969ca7d9105e16c31d40f394bb577f0dda3240371d2c15cefdfa3653256296b7db8ce96f8e4742b3eb4c02	1622812976000000	1623417776000000	1686489776000000	1781097776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	121
\\x0aa584114f309f5cb748b0507970b2f3e35de72a65386d7ed341a8c08dabe411960d2782485c79e23639a1331e47ce1c50061dcf20e8a289d66f504b521b26e6	\\x00800003c88151c9e80cf6574c206101b657be98fa58e684a583cf37e7dee69eed52b5a604f798380a2ea0c264f849b0c2462a7daa6c446c23d2d4f51dfe4ad5047497be9dd3115e2cb168edf27c83b906b791ccd600a0fabb814735ffb275151c9b570cc5c6e3561e6f41285f5fc9f442f619713025f55a20dfccde09285c9a6dbb22ef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x09dbb9c418371179af6ab95056d1905a2b9c016b294aeaf45b8d51acd68e2406d695caf47cb0915447d6b266fc0751511b859fcf48d7eea218162eccef73190b	1631275976000000	1631880776000000	1694952776000000	1789560776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	122
\\x0dedfe89f6e191942a365f3317749505df46a0e12633b6db02ec50aa2a1db6028eb99ecb3fbae4de2048f8540d7cf7110d6e881f7a73f65bbe91bfe03416f2b0	\\x008000039f1538aea8031252db6bd08187c5f98ffded638609562240019c4159dd09c3e8d3eabc6acd810979e103a49ea97f532cb525d309f8418028714096e0fd467dda720a6e3869599377135e71ac7ed835abdef3a1bf3224c393b512318b09bc05e1c538211a9b436dc6d2b402134c15541a0a42ebb47d9f7cf97e4c6b793d040969010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x568d888c46189b76cb67db9724d35e221b3786cd9b1b7a91009e0792e19026cbbc52a3d83f7af793242d1d6a6e9c847965dc568d330074dd8d4d65af6a643707	1614954476000000	1615559276000000	1678631276000000	1773239276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	123
\\x0fa9084d479f214f4ca777d40b7ad8f3c77acf725cf88a2377eb7b460e17fed6e02e876e93ca2a427166d1a2619c5314e41aa613ce94cc489fac51de1c2d6990	\\x00800003c83168b635a12973e7eaf0067826cc216f17f1b3b3261be6865bbc94f77afbb2b69e11d6b41d5bd25f9a6bc45bab9e478bcc6468bb40e3fda57583429aad74e7aeed79c53eeaad103128f9261f2053cdc6dad08136ec46258100aabff31b015f669a00bd772b681c70beb498ed7e557421628dea30ae3aa7d54861e72bd5deb5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6c30022271cc43495bc9e9a4875adf593777ac73a2c8831fbfd3679de08086b30054ffa1f8cc29ae88114e8c62751b01b3ed543d8a1c574acf74ce1a6f34ef06	1622208476000000	1622813276000000	1685885276000000	1780493276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	124
\\x1309ca38bab4083a243b3aba795fbf52dc2d8fc16af6eabff072ef2d15c419560563d2bcc11b221223612d87922d8aff5d64a7e5f44b6f5a1f56276097dac1aa	\\x00800003adbc823ea6404a8dd515696e2a34eb5b3ea5f8e11afdbbb8349503cca768dfdf2bfc04b5bb6692ea8e8a2bd01095dbabec52daf5f412627c6e17e3a4ab414713ea3ead7330efe6ebb4116da1ab925b43f04f518d9c0e562ff5d61123c113b7ddeab1bf0e336b0900dc6116fd1f67407b49bf13ecefa81764366d930ba19a0623010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x56c221fb604fed8b0411591b576908ef7b37475e4e5c115db8f4e12fb23777b6d148c6276093fd09a40b1d387358c6e21b2cf3d3afce923f4785cca48fe30309	1611931976000000	1612536776000000	1675608776000000	1770216776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	125
\\x1335a5867e7c8edc9961e8dd20ce264d0c97ab0e49cadaf3fb52fcfebb4cfe881675ea67ab89849a14e345719c675519a035a4d448d5fb2852b5b615847ef648	\\x00800003bf3f7dda6e8885e8e3d64a259de9836c1a2959d9d76490e88bdd5526a1f28e2dbd2412e8ac8a2ee348915895e0e7be7fdcf7093b0038af25052e50f70cbc1ea8df1f4c90c1fc9fbbbde1682d19ecac3eae7ffed272b805a03027bff0882ff232f7b4486e9d3b789a46a98b1bb7c3a5eca4e64a08cccdaf1afe0a6cc9f3766075010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf1c6f3211b46a3fe31627d3fee1cc70cb6a47cf95eee79833f3112239165d5bdc8c95699baff0b63ca9233c473ccb27738f4a9e56193e07e29eb5818a7357402	1634902976000000	1635507776000000	1698579776000000	1793187776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	126
\\x16bd599947a6988308d72e85cd65782932906172690526ac055b4880709096ef32a1248170c1b586981014c37fce809aaa7e796309efd693617962ffdd0a94ed	\\x00800003cf15b3ac9c7463b4018649ad9363bbb48fbfe420b03fe04ebdbcc9cb581d837cc5f767a3f8c1dff772bc61a8897c1d429e54949a5e86ca18ac289dd7c19aa3d4b2be83851ef7ebc398a5427f68f395c21ce2b53cea09f8fecd9590aa3cde19200a4b79aa8ff2990f4fbcb1f6405d3a7f84235575f9913ae6ea1f4176b59b4dfd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x19d58b0db77bf7c1245d9dc411a2cf6741589b2b1b2b689be8c3a51e8213ee84b827e80acd4847f7ac66f04f3f1066aebbf951e1a9d16d7841e8ecb5f8c97004	1612536476000000	1613141276000000	1676213276000000	1770821276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	127
\\x189df8d0a5717a391cb5c89ddcde56a0da7057d7fe5ea5ab2f28ed583462c20d1790c481bfbf427debbb4821524f11d807c03cda70dc66b1aeae7c855e46df54	\\x00800003d18203a866f8143daaa3d3a741f0ca1ca1347b72d05eb91ec0ddcbcd1fda32802387c7d9ef8c0dab12bc6921fea8dbe93c9d8017b24b42b30a401f0f724c7a5fcf86483be418194691e5ec758783a2677a43751ee9e5986bdac10e7f4da0191c63682452f2e3d4d4935d0a35cbedac181d5609601c5d690ac64fd1d490d8d64b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x740d81df55850fdd31b19f683c64d7ec0aabcfa5eccbb6ab7bf1c53060421461d652dd6728c9a6b61987cc13dcc552218778c6b2b42152f6e8af632db9c6e905	1620999476000000	1621604276000000	1684676276000000	1779284276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	128
\\x187595d8e01f89a666533f28be71b03737d2fa7d0ed387e669f5d03929c142d0d661b698a3afdabf80f56eb6567e375f5c5dfc3eec16980fa52c9d263f7b8e8a	\\x00800003a153e2fdff7a766d5748faf9b15e58dd4131c538bb458e6e346cb6749b465940fca2e18a29b2b8af8866a7beafec09658a26f35d6c5a85c29fd601cc342be9fa6108bc090721743e1e8b23786f52c4bf4e918c15e086ab90847b1f737f0c4cbde746e536ea72efe77516d2522f0161f1197956435b2338908c331170adaee86d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7d691c0afae281d7b506ddfcd3f5d6073fab3b3caec54b1d9c32745d24b27a817e45c585bacfb8f001052e5ae1ae6898c1f68543a3f56a95a5a40d626121c206	1620394976000000	1620999776000000	1684071776000000	1778679776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	129
\\x1921055b3289598c893a7187bbf75175bd68e504e8c5e929b3fa6600a2e96c0ed823309cae6325a9d2c2313d9a9b8717056a2e9440beb3b89b3746c24854ad11	\\x00800003c910fa713f8f053d8d69fdcf1073a18c4491d8bca6b3c60821a1176272f837cb1b6bd951b2830c58e46cb61a81c48196a0897055ae73c5b8e8a6063b645ce7ba7747ccd47361b0d03074611ab875a647751c1e733e22da8eaba4736a83275eec6a192a8d4be9c3c97b035c479c12cc1f72f7683abeb0e83222543ca3e2b75391010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb2f6378a9f253d99f190b61a939462d3837746f7aa216e43ceacc5cd08cf7154da8da2a8f28e48896e1ce9773c20fc6b90b5f7131cec7007619ef4cf47ca0704	1619790476000000	1620395276000000	1683467276000000	1778075276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x1bb527bb575825bea3a6a05a8af6ec4e66ad4cf7bf3e9f0f46395825535e5c6aa5284e461618d3cab71f4e3e9d901ef1a60d46e5fece3172636ecc108b9511ef	\\x00800003ad739d1c01ce967989ca6d7636c4a61db026393ce22bd796cd81290406dd27b105024bb6ccfd2ee9be061c536ca76969db288bfccb115e9be35a9b41773c01bdb19bf945b3b449070d853bfc9fd268cf31f4afba1a7daec2446ef04c6ef8f2e33f0c8a0de6011e0dfb9a9d4911609cf9d040596a695130b5ec5771de5bc67beb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3743d86350706c0ab769fa0cca6b3252e59ad6714086485cbf70f05e9960a867bc16a6c73f38a7b8edef0d798f8370865d7f123d12ac4cf9684c86b5cfb6210c	1637925476000000	1638530276000000	1701602276000000	1796210276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x1b317be3f7bdb76cac2fddac825e2c2b4def70e2bf028936859bdb1e90863655a970f98e19bc24ea41d88a8dfb89da6143ddc33dc294fd917bae2902014624a8	\\x00800003bf7aa0e1a42059e33e8736c52c24bda9a44daee46a3ab1798fa22d622e717229b7eec2be7536c184e75a38bc52dab07a30078e171991f33281a5ec44c31e2a1b9a050dc574a7861799505c7f5809e35653e183c31957022c7c99f420ddd096d2c86e19b8baea21e8164ba984495135e3818a5a29cd482bc7c920c6c8ee5afc39010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4c7c4672d0b8d5f36c165423be09d8f4cce0ea210bd4925eb9b1e66d16e59b0f423d7a2277d9b4bb6a3d07cc06f762be5c81ad6d14889544e0092626eb06e502	1610722976000000	1611327776000000	1674399776000000	1769007776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	132
\\x1d7d4c5ac491827c2f74cdd45eb79d2c7aab90e6e2b240e2e9890907c660fc26d24228b14918319fe5926c004136764f7de3eeeb2f9ff9a0ed96b062aa2ddef0	\\x00800003cbafae56ef1d47dc53ca5c47a7fbced51457c741ff3ebed52265f766a5971e920ca6e7e411a8c780284db9c6b9a819c6446b909d4c7946618efab4c786043536ff2a13d2a0d752609a05a10c296435ba2e5cf5130d9036f1cbce51838730f3eca7c0c631c950d4c3553bab64e8806949def9c0a00e7bf55c8684a6018a71aea3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7c7659d6674977079d7e4f91f0717279a179c881d0b021a43f52a197dcf76d5ff3015b22084fc8b207a3b6b081eda2873a6580dfdf5389c3b1fa8af9d620d307	1639738976000000	1640343776000000	1703415776000000	1798023776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	133
\\x2129dfc9717e9d1b7d91cce0a97b954a28bc73c40fe1ca2e87cb973140326d80c7640a09a8eece74a1b622f3fcddc07c1637fc8eacf7eea9eea3d87a05903dfe	\\x00800003c691fbc8d5d57eee2eea6d6b2ee9c1a1a5c98bbc8efac96260bc4e040a7a7186e33b0a3bb64b03533a751927c8e67fa0e7df55a788f91aba47d5129d9d8253fa6726b70f994745ed0931458e2408657bce249876ee289f5df8b720662d87ff07b7aabede51c5b4b78db98ab06d959f6f3df538c992e511e8e3b830f56987c585010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbe9d24b28e9baf799a3e36f4f5ce9eb625ebe5bf1c3062dee291d939b3a2b9b089fccf73663c0c0e3808458ea09f30363142891f7000c710aee151751c8afd04	1629462476000000	1630067276000000	1693139276000000	1787747276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	134
\\x23f1791979bfba98c6f0da280b9c73282f2b59c56b5bbcbca903ad3c02070dcddd9a80f5a54f9b2a544913d81e01642dbe6bea87a0c49e1aed5031aa205d4285	\\x00800003d568d0e808042ecb5cdcab09cfa5062adcc8ef59a416a9de357575aba5b1c2f50f764e84185ee9ae90c779d1af4f4241019d5807b48b4985b6a16529625e93c580119515c2bf979e4ec82c09ea307df829cd1d0264998c8462f0916059f08e732555426c02ffaf42dd9c44d210ab92340f1e9a4ceb93917ec378d33113508df5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x10be4615a8acdb040d3308e3bc25229fc1c8167a3c6d359eade95135825fb3745d4c1cee243c362d47718b1e53f480ce24d30490eebf087794e369f58cc1740f	1636111976000000	1636716776000000	1699788776000000	1794396776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	135
\\x2ad9a28bde8531ea4ce9bd1e8b5512873bf606b93ef1c7a8183ad6da782eded809151f6cd48524391321dfcc7e9935239ceeea3789603b6d900b3d873bf48024	\\x00800003c915a39d3273d7837a8f60d7cfa0d28ff0ce78fdf475734b4c3d045d98bb28d918c85ee995d6eead9a1d6c9fb611f34e21dd45668548ac0c9bc67dc1e2d16c96ea4aa183084b15f5719e387063c89887fc79336cd17a55759542149994ce8a647c5d7c7948aa581925135d3a4588531d6257b5d9955045d73460d984acfa6113010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe6ed823926371751e9cf7969ea72f584f492918176473ce8cc877acfd165b08d5786441cffb4d1eafa9e87abd2b404e83b26e542cdd118a44cfbeb032f1af40c	1616767976000000	1617372776000000	1680444776000000	1775052776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	136
\\x2a1541258575db064d6a3fce3db37b37a5153bb6a542d3aacbdb7b255cc44959f98c312cb7f8124aa686014053c86c2a40ecd360729e91b96e2ffc6f662e6bf2	\\x00800003b5c5ef47052121bcc7f382a9fb28aba3f8a85f1a77445d261fee829f98e9c8dd1c56204af21664b38b06cb7baec779d7bd43ed71aabcb87014fb402971867e0cba245f2d91f6dd288d601fe76e8759e47a2cc66282e1d2ae48d9ddbda342b1f35581148848f8195696515684c3d4a8dfe35b5e09e79a37c7b33326b546e9136d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5a13034e5c05c88598d2a0c48dbb3fa8e8e1bdbf127ea56c55a269d9633a02545b21a4226c656df17ee8ebe7f8f3fac0c78917450217274121667d4050efe300	1634298476000000	1634903276000000	1697975276000000	1792583276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	137
\\x2f0d9a350700c1f44603b60c93186d0fd99f11f529f12756fbc5d6dc779d639c1171a83bce3b9838254eb0801ad97c69d8157fcc53895b88f144ac04fe7d478e	\\x00800003cab5f9de427f4d4d1191102966821eb1158f5769d9cd6946e84ea20fada04a887e4903f2e62b6615174b4aa95b200c3fdece779335a6ec8a4c18b2a651934aa0a0d0e00fd499383ceeed9e1c6aae4ff18e1b3c4214f59899897485b47456665125102b409b09580e944c7692c21357a401218727ba9cac776cd0ef22fc113ff9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x285b16d1865c08c05b5e851689bb20a25ba5a7cbd0a16d542c21d0025abfedec779be9007b9a1779394dfabfa0091c6d61370b0314810f3daac745e97abd0c0d	1624021976000000	1624626776000000	1687698776000000	1782306776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	138
\\x33c98e5b42c21b396e0a2a3073d8dd19ac7d6ca74b541a76f26422ba2c623726293e78065385bb6a246ea9b6bffe744e5df4144107e0597e82f96518b8fa4957	\\x00800003b7994829e23af531c577c218d4650c48cb2c2443f765e0494b36069eb5cadc4654903c1cd2db879a488d0bb4e0372547118ba8cb61c5560914c7b42b39a1edea07a85d64e06d5b7c7647ca36d6a15b7c88f567fb38bb372ef03a8b01f0012dcc5aad6f1bab5e5296367dc7e2be09df2435593bcf80e821a123980624ba3556fd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9475e75e514ae8c529ce172397d897e8a41ae2a5ecf92517abb34b48ea7d961bbbd3963b7bae17f7a193b91aba477b450e3401dad99b1b270bf6f027c17bb500	1617372476000000	1617977276000000	1681049276000000	1775657276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	139
\\x344d178a7f54e15d71ee9dee9ca80a4e3b89eb508fffb273374544fbf21ea6f93294d99700077b48ee811ae7f6bcbcf99f85658eea67cc55764b091b8e3596a1	\\x00800003cec8a715e1d55c66061da0e2bc5ad9e5821ca29ddf5c90c84a709933e554edd2c43ab94d6584c657fff93b7997e9fc6f1f967ab29483f420b859f56009ba24dfc6df59c6d107d6f1c522a3b11ba7e41a107d4cb633edfd9f74a1d55f609790c4e4833848684edb85587d5114e70a7886993a7c1a9ae0f36bdc28ace84ef91ba9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd1536570fbc86334872f6827d3676d4ae5e6bcf0f63b14e7a0f8f58738c04e54ce6c0e774fe1af4eb53bb89c869a24bd6cd8159fcadbc4b9e47835561d6fa309	1641552476000000	1642157276000000	1705229276000000	1799837276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x36f563661ba3b4fcade59ced2f159223fb0a416202041f7b47005220d141486ee9a55dda81ff419627601cf789b5aabb0e477e24f40ddf3f7f93d28cbf11584a	\\x00800003e7473ca92bfc33413cdcae6f894b8ade9cf66d5fb2c5e697a532438d078efcfc459183e868decfb825c487165d60d5fe6411c8b1bd0ac4f127a9e8934c51758323848d13c4bbc3ec5172a39304a1988961ef255c2b0e4c57430a06fd8c5d5a8a2f15aca5c959f9b0a9a3a9a47af99662112e064ad47776e5ea2b01580dab001b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x581174a6ec1181647303d2275b4143d3d077c9bdfddda9eeea09c19f38536e87db6cd8a5ffad37516642932793506beb61654553229b50424f2884da800dec0a	1620999476000000	1621604276000000	1684676276000000	1779284276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	141
\\x384d66d27aad525ad6aff9f7ce968e94ff97f200538753f25111c2941e10b3c220ccd6e37917a518271481ab8d3fcefd0c9a79c152206bab016727b938005dd7	\\x00800003b87e0e302eb25ec6541ab5df0e4a45a88a6bdbab9662df8df5e71f6b2a2729c250a960b3e04298cb427c8db848acb62c50c389d84dee17cb4136b30d622817504e8fa78eabe8f38082935c136416e3c6e31037eea54fccf9fccdfdd924abdf69d1c94445b7d56841e0236098085cc5dc10864ce11b115a415740908c1533ca8d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x486da2ed47c83769b55ba7f4d7f6a2bb4e04d68e176b095cd965ee6362ef3cc4115347e375b640167eda202b1d7f1c71cf8db7b8c24b52f3532a8ce7d8246f0b	1626439976000000	1627044776000000	1690116776000000	1784724776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	142
\\x3c29d10b4d6314bc40402e7df5fb079f644d1b6a75962770c7bdf0b6e882cd25f3af891f6128f516deec4356221bbebd509501db6ecff6cdaf75761efb7d7fe6	\\x00800003a1394a0f6e55c087bd81cfd0109a338954234b01d7aa0eeb48e0e7feef9933c8030881b3b7d7fc678b9e23718a0abb5cb66c53fb02a29c6e38b7ac975af25c266b40fa70f1abdddae1020c44edc27595ef85f44f30596fa462fe77a3290814c22b030e0cd2b67dd8dc06baa118432d8ea567c0ed849182f1dc14cdfddfc958e1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0ea9b6b47388acb824d6c7636c87a83dfe2853711b08cd87c15d36e0031315d8bc5b1c9b98fa6fbadd0cc192f1a361a524e47dbf1c006f18fdcc0f44033aad06	1611327476000000	1611932276000000	1675004276000000	1769612276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x4115ccd9fee37a8f15d527572830c9aa027034ea1489d4a89e6d24ba7121f582eca804fba45f702a7e94be99807accb3c7214b9af2148d3dab61262b9e57d289	\\x00800003e04decbe196cc69adb63e026b1c961d5926264a416e68b97d53c744e35156e9f96986e98934b50dbd5adc1513df08536c2da4862366824979d6b4e26eba7124bcc2e469087e6e294a844e29479bb1021667d8fbfc35eaa466bb9553d03e22a97d88d6875a987efde50e364d40f0faad5efe72b5e11aab4dd33de05e0adab9dc7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4871815f5f683b625dcf91d2b269fe03714a0a37713cd94ca2534013a30b97340fb8814ca6fe9e02fa4bcb2df5f7a862622170f25c6b473b1f7428569c446b0c	1624626476000000	1625231276000000	1688303276000000	1782911276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	144
\\x411dde620d13affcf6f2afa7c1aef2e7f0311dd2159d6dd1d5dc0c315cd6e89e64fa83503370bf87b466a9843d41d495d5bc8fb70391d95acf6613ee882621cc	\\x00800003b40b7e941a6670e61b2d1a83ddc84787ba03e8ba7bfefe257362aa46a6af561073be43aa92acb7d00b95d8c58d7afa8b4d25b65ef460236567be6794bfa99976c3cd51df8116126ac2bb021d26346ccbb3e84b706092d34bbbfc1ff0fb32512ef5170ca6de49653560c226e54a86eec5f2cbe9373ec0d44144c971e4b0f3bb31010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0e395b03a3416139d86b8aef694df5ee024154d8fa00ecdab460695f8e356d7e37f2a4ee7bfbb1496946e05d2ea86078dbb2925d9aefab98db6e5b886330c40e	1632484976000000	1633089776000000	1696161776000000	1790769776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x42d57bad3289b0e2a75ceea4a6ad6cf6c20b51fef8b220903da85257a6854db3b5c16fabf4e58a4517e0673bc4d792c7ea49c064db88fabf520104299101c4e4	\\x00800003e2353852a5d779bc4f5a629aa7d2accc4f2e1caae5d848ce93c14a1dce532608a8ac94b7a80e89d087479a93de75cbf111f7788b097ad2015385dd2175a943ca359d38a86d06c1d6234011815c7b75770e0ec2b862cf19df1b499260069958be0c2241a62e9c4e7664acfc7468531b4f57a5b3fd30a69c45a78105b82fd6241b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc9297abc7688ffc59bd71c116e96a763e32d5caaf4025b4773ae572e9324abf969ea16fa53511ed5e435d9baca62d740260ac8342368590de5c3c88985def607	1616163476000000	1616768276000000	1679840276000000	1774448276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x451506ff3053b460ff72d5c01ac12bebf547cb68b36a49cbd1bebe3b39af2cc4862f3c89550d9b003ba4a7ca5624ac5f3542ea2bca620c2907676a62497c7dec	\\x00800003f8e62425636c4688bd3ed0a52192dc273b9f86bbf1c03ca45c660ce15f136f9ea4eb12316326668f2cd785cc317da0196f761dc8bd92d7ab2942f0480a7b3fff3a7fa95c16c03c9892a974c888678ebd1cda04eb2d829ab3c0a8de20a8953662967b321addabfd7c5fb943d374e5e13d25d3dc5e90e795fadcba83dd36948cf9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa3bcafe02c749879d52aaafc87c0dd647621268cd3dac11ad480543bb1e662eb1d0e15b466ad34553a52a7b89fee11014af2fc3df8a591e78535c4836a6ad60e	1631275976000000	1631880776000000	1694952776000000	1789560776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x47dd65478b187c3a49a076b8da91fcac1712c6b446ee7d3385ea67acdd8b51d314f08f5fde471524297f870a635756557ad4be7b64c90484cc64ce2a5ca6f69a	\\x00800003a23bbf84c70b7d65dc054b6bf665d3de8b9332c5b22519de4917259260af927ce020dbfaba0672dadf217ad5d52892dcd8836248c8f2f7f3322347804b912a0efbbd82813c04501f651b36d3b0ac37ed7b97f0dd44f7485ff27e93d6d48e8f564af56b5b8ddd5be87e93030eab5ae0ce9a4baa7b4be6243823e80a04c1a3b723010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf84d89b5b829c40a7b70319580c3144b6cb7ff19e9ef3bc0abfb6fced162c0fc359a6cd6affd6047df6430036213f4303edd84f3f8cd7fed3ddae4bc375d6003	1625835476000000	1626440276000000	1689512276000000	1784120276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	148
\\x4d914032a27f1cc58c7fc4167f9ba142f8db4e0c450c5dfffab56acb505fec1d0fbf8658af08212d32bb15f1adbaffadc27d425e47a37ed483a6a3e0b3ca2366	\\x008000039b515c740ca9cfe2cff19ce4e4fa454d2351fa883fab41927b1413cf4d513b3806309eb410ab04690388a99055c83c9637a139b94ff3d90bf44d2d19998b11bd43c152716e5e727df6e95a07ca83e6a92e82ac5839b538f24104a71cd55176654311e746baa5cf435ec18db329569539f14be3c057e71d7e4cac65c20d743b3f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe11ba28cba36cbcc01428037a9b2707179bba8aae311df62a46be9ca0aaaa23f0e513fb7f918841a0ea5b547d4e72997336a82a0eff67a99020d083d2ef75807	1615558976000000	1616163776000000	1679235776000000	1773843776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x4dddf70a893518e37b88004096bad00eef7cd182b8cb1253bfd32055240cfa7f8004f5d9fbf8c8c07325ad4f9abf987fb8d645ff551bff32a05592fdba805abc	\\x00800003d1d8333027789dc16eb17729b7fa4383f0cbf67d5fab2d56737343e82d356dcee42c6ed387f449a75382a338c21aa156d4c1b18e3ea16d067eea6262ca3220403b423b1c2aa208bb5c7957d673462e613a9c73b32f3646f008a77fa970811a2f0cac2f07dd8582041cf9f63dbc0353aef385a1639c707a854de9a05ddb0204cb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe081f0a76d490cfcde30f2586fac5e1738b1fb28bc57376d6698d9e66e02c522e98560cb2e403fc726f8efb096e343952ea8f9f4697a391e01ec28e75fc03e03	1637925476000000	1638530276000000	1701602276000000	1796210276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	150
\\x5441d763136e04121fb666b9126880149f73f68bffee6a0fda58a8e7b086681c921460fee643a1f07ffe67c49355d2b1665b85f481a51cadc0228b451f4b0207	\\x00800003b8daf87a8100fcb682d1d857a90079380ccd686008e448606b6ecefd5d85d49f201cce197cbf12a83114425f6956f0ae8c912968c529a456e9e038b5268a06101d3f20f5b18d03635041ba9c28141d357d0651de5ca7b6925f9a1d0932415de9cd7c468c7b27e745a235bea35b8419a5e6913a306781332672b9b647a18b61e9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x82c30a3060a30cf6414229761b747cfe69f6bd08b0e319a6acab25ff9abb3ecdbb66bb76393d2fdc1f492989d275a5666079a5d92e7f558f884f93d814a37d04	1612536476000000	1613141276000000	1676213276000000	1770821276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	151
\\x5909636af34a44721e7466966e3a9a199bd74ee623fa7b8fa10d1ba77f3da5f62844b8542f882bce264326dfabdceacdb6b86aceb9c8a8914ca290ecaab93308	\\x00800003c1df4590495678de9c2cb9143217965012a59304c808ca4c6caa8afcac2a135d7081755a76b6ea61f75c6e838d09abef169c5afda17c0db26af06c5b547cee23bf6bf66dd187c1941fc9bb66ce5ea0c2a59d5a0fa61e6e4bf44e7f6fa073dbc92a5e55e78bb7b87292670fd5983ecac374a15cbff780e0eb74fc6c4f6495f771010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5c8ee71c70c4cf8f8491e6105a4ed23920eddd0addd8a4a3e93d99d5d9f06c293e392b11ead50fe7005ac8bd72ef7de80d53455098a2668b4124f47e7ef0a804	1614954476000000	1615559276000000	1678631276000000	1773239276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x5a1198fa38435124e407a543873c47e519d4f9d2ae19c866fdc1197b0439c6098f976728b126e68532c7c754cab2a1db1483df86059f527a4b728b84e56c0e78	\\x00800003d0b9c67d37528d60a92e9c9a3a5250721aac20793b0aa60b5059a42c84b12253c5f6d93a0b5b7f5b30ff74fe293e69ef0b9cde854ae36552c6967afc89fa14b8424dacd3db8acd2bfbab036c353cac0888e06d491b760b4d3e7c5d377d03c1b66f9db6ad4a30b8b46249e8b3c4df54b20777aa85c8cae18f6aa5a338087f4a83010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc9a7e1cd39cd5e2c9d36b81fd44dc08fc70943e106eef0173001eb64fbc71d65f2ef841568ab351bf0e5b1eebc3f020e00184e5adbd7cd80647014f68023c905	1639134476000000	1639739276000000	1702811276000000	1797419276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	153
\\x5bd98a42182a8087c037c3a096564d0b1fbe46da12e3b586d8785886e017e29eae6ecde8035350995d1f804003e9dd979862e9f09dc85f66e3978961b57276d8	\\x00800003a1752aed7cc7c905451cf7d69d29a9a2e34be8ad4992eac3c0e39b1693bc47354f74545bc3598c0a39e2365841931336443b34829c80c8d8946a5ed595ba80bce1f5a397f18e503b25d3e56c9d975e5e7b01c2de9bf31a878394b365e426394d7de4fd01d9e6daacbcd835e55d815c8eb4f998e340fb0b57865dd16aacc588d9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4873b6e6c23245dbd891430b8499f7595b22a99c7223c98539e05e0af3177fba4cc02dde24a9a91b64abfc782df050790dad24232a6fdb779ef7d27cb45b7007	1634298476000000	1634903276000000	1697975276000000	1792583276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	154
\\x5ca539de380b169b7947125861651a3deca44fdbc60ee140b4556e72153ce9483c827745d22b1dfa51ac6f3d0d8ac4da35b409ffeed20c87ad46fcaa76ade876	\\x00800003ab581d7e61574f5cb9c4f6e3fd3275cc8239cdbeb70c0034a6fc8cd4b754152b0a4a8e6ed9f76b39bc3d932ecd1a16aeeaf50fb7acd46e3053d547ff5a88f11d695f34f0b8fd8d6c4584b2549085467e32b76a26de67ba2be805cb18a3945de788dc8fbe2945624e29edd54ecc0e02b152d3b665a40a237c6df3655334895e09010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8077bc6898d156c4122654133251ad31620c2a9dc51c45e77e492442a63d4e0acf6dc41abac9be0b427aa196cb0b6b8575a75f0947ecfd0ffddc2fefb3ae4e05	1615558976000000	1616163776000000	1679235776000000	1773843776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	155
\\x609d14191cca49bab25021940ce4c2dd837311d79040cceca9dd7d05c090b975474625c096642d86c4d31014fbf2ca9aaf8f2406249873918391c342476851e7	\\x00800003c49d21a0f090196867eadafff53d9eb8218c4fbb040ea111b4589df81fa6228c5c1bbf4e5da70df5334bc9a8d62c0039590ac08ff3d07376aca5dce1798d78d186e0d6825e257c770b6be28c82652d7adb57274e8be3b50b7fc229582e9d0bf4119302be7d666ec27603b1b613291a9e52916be8699fdbb1719e5ae14bb8df2f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0834bef7b0163acbc05ed808bae1d119bb2879c1975ca4fa4752b2c6d64a11eb6748d4002d45c2d6db3355670135c9ac44d7e656982b5927f2b7206a3970e509	1611327476000000	1611932276000000	1675004276000000	1769612276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	156
\\x61e97879364df4516d54dc95da9608890402d9d40c6fe14ca50425ff67912177ad3192ea635eecba0e637015237dec337af5dac3acbf00358d28cd575b4862d0	\\x00800003d5d0d98b3dc9ee448c181bf34bfe64fdfd71edc96e163b1ed161d08cb7ad4c82760d8f49ce21c86b8a9629a72f859f5122c7f10f0a89a6f9bd941411d051d7b09ddda3ae2a1108152509a367da5c9bea6771f6c5b990a08d8f54ca9ea63c44e8104d48db22804ea724eed60d696e36c4ad50856ef3086d2455dab65cbc0d7fbf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xce9a00f53a31709026955cf3b093fcfc3bc0bcf372950ff18f41bbd7925f72073ccc270f86db1a97ff14f82ebbd7145ed824e9a37879a77fe26655495b13bc09	1615558976000000	1616163776000000	1679235776000000	1773843776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	157
\\x636536179a7e842fc62c17e502625ff58bb20fbf098713062316251bb822106aa942aed398ad33551977e3c389557310a03b12c7ed09f893901adbc617933ff6	\\x00800003cf701aa6852890a2872b11ea2eb1aada045e51ade3f461f47e79a51dc492bcd858b1c54e37d8a9c56738bca98111a6448cd98099cd2433a91ba43ab85b9b1722db4e55b3bcb66ddaf649c28045605faf0e2ccbea2de8ad080892cf122c7d5af226b07778d0375558e3d129fe9f67e205b9c237309cbc5f403f510e84aed8f26b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xeb95818603378adc68c98c338cda7c88153b566f18fd85ceac4f724d3f9eb62c394af06319b80d23bc026c677c98c2d31bd788312d607fec16e66b466fcdbe0f	1640947976000000	1641552776000000	1704624776000000	1799232776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x6441de6f2901c2424dfd329c024f245e51115f63691575c5ba1535e9313c9e70189c6b1f3ab46937971726f53f72020ad45b8d319e6de6fcc8a6c19868515498	\\x00800003c6e5dde1a64380f723acb671033c94a07dfaa6812c6a9dd03f6b33d90bd35c11f1cf86112737dc73e244dba4ed0c0ec96e2f1a5441f5b76472678eedd5d2130ac312bd1adc0552f3d63c20f82b3154bb2d7a5d6c2de6129ddbd4405affc25ab7fcb721d1c447e31af1b19f0a26686643fd25a9e23c12cec4805a8a198e573e63010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x21981d7a3e93fef3d4c14f68a4bdaa924f87584368ed73c9f905d51db8bc24c6d823ab53900f4b1099b557171481d35ff2647e0e0ac380cc4c1abc7d6c81280a	1641552476000000	1642157276000000	1705229276000000	1799837276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	159
\\x65d5cc253af8edf2d8f96f85c7d9287fcf97162b9cc1aad05811793c11ca2fe39ed6c1db9401ee5f2ab941c7a02a09932be4f4b1ff1c184d106ffba7509b3066	\\x00800003d3b3fe04f004d132869e39b4493aa4dcfdeb724b1d3ae21598704bdea06cb7997441d34aa368b7c78bacb2611b5452c79411c59492e1b9bc23b2163e8d638d2096ae2382211225546b25c16b9610d1c74be034b0616b497adf46f71935ba941a609eb2de5968f8e58b9ae80b7f39fc3f65893e8161b432f54b19d834420d38c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd3d7c4cf7566398b734569666c43eb2f2de003a8f4a1fc4c6bb4fbc429fbf38fa89742db99c054f0f1b149a77476f5ea15a5f75aa197214add024c2e3f6fce0f	1624626476000000	1625231276000000	1688303276000000	1782911276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x652d7f2d0b54801c213554756c448c1204a4a2a809f2f19eeed1fa6bbcdcd8634bf1d77af2d131d4808502e9268e8c63e90006ff28d2075b1ad7588b40dc923d	\\x00800003c88355cca3de0a1e44f84c342f614cf1c9ae2c881392d8ff132c4f01fe722109e01d53ea0ce373c6c80fb8dc8ff6a8d1b59e6a486df771af8cfc2e35572e56df74857063d8740b284bfe1c724726a3a85bedd18df78a831d65279a42684eedea9a3eac20004e513f45898f6a233a42771437e11518109bab19582bffc27171e1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3f93eed5c7501c21746ab39529660321f24928602951a80d9da5e65dcaa27272f105fbcc33fed7c2a11cf0b68caf4c61944cde47b550eca5654b1412815e220e	1626439976000000	1627044776000000	1690116776000000	1784724776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	161
\\x6799900429e5765798f88b1fac2c692542aad67a958b7d9aa2b4c7f729f28502102cbabbcbe904695a76a1d02fa7a4e3184cd09361025c5ce32ff8e65fa9e142	\\x00800003eebc821c1737ca6a9d3519b03d1ef3d0c466a06e8f3516767df634f16966792779d39822792a37f4692e09f452fa35c2601e6a248494ba9cd7fcafd25a4d12426ff600ed1a1eb6084ab31ee5698c06159e209ed34d9a1962abeffcd54cb83d0784fa1b5b382a71ebc63119ba306e1b8ab1a9a239b46a690f2b95ca88322f8d71010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4d1ef006ba3d67d5dcb9626e14183a9b0ae2f8bf1c0444907f97fb468536cce7a4e791f3e273b93d87d7cfcf87b2e93b295d78013c4bb634cc4e8ac187047a0e	1630671476000000	1631276276000000	1694348276000000	1788956276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x699d9110f46d28d10e70b93d3af24c5335148562e62d2b246e5975e70327e7d87c2be36b615985bbe1ff7247b384a64aae7388c77d84b691299ead050e74feba	\\x00800003d6301f6c61ba9e3c949d27e9d158583f4c172ec0420e1fd03c21542b9e1d13d011317c89e99edcfcc0b7a4d5c8eabda33d8ea777812e7b626e035bcf15232dbaebf8469064e4274f84b2c8eaebc0e21661c003344f09c37be941787fa148dada9428864cf6a5a8394002330d30bce49c63f7bbcc2e66b670d1ae86e96a3bde93010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf5d7f19f17091625e8959f1a930ecce243119f19bde6e24b53e8b8f60d973bc3bfca34e45dab4fdeceddc8d0d1d0c2a73bb58ff60537cb3c93d907748d12500d	1611327476000000	1611932276000000	1675004276000000	1769612276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	163
\\x6aa57ac23786effe00117188c24009089343bb722d6d5d8a0d2e91d5d28ec424e4deeec20a0e145d1e9904c1b86119193a079afd485b3516e386c471b1c84e70	\\x00800003d19bf8e2f3d84ba44914401a20eb91fca1a5bd849f85457b8681020820a39be02445f4ec8f2b6ffa6738405b2085ed630feeb463633a26fe80b1c91c10b0d2cb5e779e009cd304c9c6e6689866befb72080da0ff6048349fa7f03495511df057e8dc240e992e33a29f4db978df569edce944b50d0857f374fe944c455baceb99010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf512a3b2b534eaa4a8883e3afd8d690d545fafc448e52d63fae4c2e1ccdc422b641cf74aa279b28af7e03521d03bfd8d0afc66b5873b59dbad0522346966400a	1637320976000000	1637925776000000	1700997776000000	1795605776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	164
\\x6bf572beb1171cd80ac4361f847bbf1ecb58aa6eb620ebb67b6055f4d2be157cc478273d8440bf66771a505e7ede6b832a241cca4eb18a72a362244dea212219	\\x00800003a7389cd3e4dc458db03f2b0729c7ecac9c92b54b6ce72794fa8d4ca9a069ee22cb91b9214efa58e1d78cbde5d7aac3deade063782983554abcb776753161f2609dec49f3bd7041358ca8cbde6f30ac2e558744f9634d728057a7501cff231948e2c295008d9d3252f79a994e80c69f3fe0fc75b0671f3c6964118bac129ebbb5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7ab2f4b1625834841a51e8082ab646f8a58965d9edf7b32c0003d7d5e80778f2f66569ab28b4df5fe7216fa8eed0c9d479b91bb646a9c281554fd14077b81f08	1619790476000000	1620395276000000	1683467276000000	1778075276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	165
\\x6c3d36204fc6d3733ce7bc2b31de68b30e1793f8639780785d5146ed1298921a9edc5ef758c5f661803ffd3557d4f75105cc9686551e5a8cd7cb40db6cafe1a2	\\x00800003e0103a54a862fdc16064fdb8c287ca4a5315c697c81c11e701a2ae5673a59d6a6a629f95c47a1fb374933c11c240b46117ba0c16f3c1687a8d5a38b067879e5bd80c4d2ff28f1c1b16efa99d5da21c173f0d9c347b5e427bb670eed8629de9c967c0563174fcf1f165a76d1e6380a29c58084a6147c4464bb33b686769d6d6f5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb5450a06fe4c31a095bee8b373d2f347f23757d0a244e0e573e0c2016272de613fee77b18ff31ff594d99e557b4abd55ee690d2c4a3eddd564dc49cf52837b05	1616767976000000	1617372776000000	1680444776000000	1775052776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x6c7da8b09b38731fac75553f0010b71871ed73e3693cbff205875684561b88b87b687631e88c2e49aeb3c840c0eb421c209d9855463b84fcd692bad4e0530fa8	\\x00800003afbef4c3a4e0de9797c65abb063fa905cb2f3f89589329d584ae676f511f0a2e7a15dcbaa622a3b158dd18e43efab685824bce47595d5429106690d6bb1245e809a6a662c37275f9ddff3142fc5809cd420074a2eaed92df7fff680bc2cc58f5d0cb509fed7ad277c19c3d3960dbc758c3fe6b1e35ab8bc2dfe5d201be780d3d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x77697035ab7c1af90671f653e4d88a33a3681de661d68a810aa48c4c56fe895bed0eff997a9ed198552fca32b735ff754ff9c01c527c9e8f88879fccb9bf1c03	1633089476000000	1633694276000000	1696766276000000	1791374276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	167
\\x6e35cfb47acd9623ae6edd883dec709fd729d8b082abf247f9a50435f8b41184a6c8e220fc7e109e6ba44a7fd708492455f2195f342dca0e0d22c067d075a978	\\x00800003cd7e65cd2d9c0c46942407793e709a0c13ab5b638d0c2c67b877f75f40b0257eb1e2f8009672cf65302e8b72b418c5aa7a3cdf02fb95c25c1e2919ff13d8885111cfccc903f1a76f5a47d6c47b9074a44b183391ee1411d53c72577a49d200c512e7368e1d2fea8af59f9b41e59d6aa2e40e96ccecdfd7e579b30862cf099937010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfd2e9b572d33ba94db99899fb94b90b3914c4c6a569e4bba74f4ab8b421512540cfff76f6236eb93ec814ceb76fc69283a4fdbeb7476122fc0fd1d8754249c00	1617372476000000	1617977276000000	1681049276000000	1775657276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	168
\\x702dcd3d4800604fc889d8c0c7569e60d140fae8ac8f95da8fcf247cc4dda3b86e28d4b2644d36f271fe789aeb298a24f67c72764e26755896b013ceaccb8a79	\\x00800003c1b2949091da5ddd47af970d9750a7654863e88c79f067708cd59a68db7664d51add29a335bd58566577895616f98cc9135644a3716889756fe621821f0d2e994a270144c1c8101f9ca580e617aebba57a4c3acedd94e574601b40b95b56284b32752df657d52da2ab7c423fd1c23e49699c9f2ba5da9a608f84de6025063301010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe3486bfaaa3b198dbe42d9107caceb1a5174fd43905d9eea782b9761ef794ce5b8e1920ea2a1b9c6d7dd42bd59247b4d71ff5dc305629b5d05d9f985eb5af904	1611931976000000	1612536776000000	1675608776000000	1770216776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	169
\\x71c12a7f5fca5ff772de4bdb058053dec8f1f8c823b3e090497cb582ac50a14343a5eb343ccfe982e4c7eaf27a6ea873f1ee78141e447f21d5a986e69eb40994	\\x00800003b466c62d895809b438132e6580e173a86a3ce336ba4e8633a7842b54c0f5e528e5f42176475b2e1dcccd3d4ae764712865a047155f2b29fa892db6b2bab71ea4138b1e13fcf3f71a5d9626d2ea66c73b7d7e09c557e68393d276daaeb3490cbaa3de02c8fb3567b1af31a753d27b36ec4a2e92743add23002d107439da55e45f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x77d9d31ac37db1ab865da9e2f52d3def83ded42687875492e949cdcc49184027d2c0b9f353d15f695beb98e5e2e3aee47ce3d1f9955b5eafcfb635696ee2800f	1641552476000000	1642157276000000	1705229276000000	1799837276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	170
\\x72495cb57bcf3dbd67f8b6d82ff5132bbcc48e939c988101095941c98806ec13aab1d919d68882d982de0f2fe0a35b50a88b6f22a3e98981c90289ad1bb3ac3d	\\x00800003b7829ddbbc297a482d9df3ed9adda562367558acd164e137e6e8005911a8b9e32f1b927ba3a8d6b07498986f643a541c6e858be66dcea8937862aade2e2bb98763a98adf23679136300ded38e1f05a0148ce6bc55cc14398898d7f56a1acc333376df88905ba4eec5228ffa93e8bfae5e74d5c9615cd0da8d3acfc2fd6f00feb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe122b541d72e370db4d045b5da37e14d78e2195e6fc73d917925ef94cbc78cfa2d4a8fbb01b63522a1bb99a17095b66a1a4e07b15016f437b7556604ed21fa0b	1636111976000000	1636716776000000	1699788776000000	1794396776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	171
\\x741df09fcf7df741256292d99dc55dd494439e1f1d759b6a228ca82b990ea1960897a9de5556cdf7801da667893dd3666fb98fe9f307be589c2050810f302084	\\x00800003cf68f3c96475d63a8d1ed1523d816686e02808dd5f19eeda906e35ab715384248f3320b54bcab120ef240021c87deb54996d1b8022e33814f01ab6545d66a4672108f403df74a8a5660471b52af50128dbb2da2c5f1b19ba1b70284710bad8006a5769c3f5e4a8b9286c35af2782382ebd213b565424fbadac1cb4b506e2c70b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcee23138e60d256d980f64f84974f0f6806bb444899750e36ce7a649e4c9dc56f7504b079ed073561eda324c043e1cba2cb2d512f84c73ddcd3771df3911ff03	1624626476000000	1625231276000000	1688303276000000	1782911276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	172
\\x7899dd7471202e9ebe3479c3a69260f65206f2820fdab9efff6df3de9e9792e5e908d01c77df9124ef3fc14bbab9cdb300a9894a63ac7ae6f78c4e03ec129c8f	\\x00800003d73ca103ada057555450b60ec00e5bd71e7508762a1f4ca94b3559bb55e0cb947e56e4cc5d0b4be0b01ee105353ddc03fbf56051ae0dd271a3e62fbf6cd2557f9b469ec1c385d76fc0ab4480af52295c6a098f084e68f60b1cbff9bde4f26216c66b8e2097ed0651b7408af238214e8aaaeb9e7043f99bbbf6c8e574f6c87ef3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xee0762f347c062ff761374f098df93f91325e8e9dcb531834d992094714c4831768ad243d74a63b315a9e953d217f3d4970bb05a20dd3bb883dc1ab1ac3c3d0d	1620394976000000	1620999776000000	1684071776000000	1778679776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	173
\\x7a89a096deaf3e7bdf3071706b644388ae6be6b591ef808b56f57dc8c9f75d7cc54915ce9b0eace8df15a608f21f177014cd1ece81162528385387f63ddb8cf6	\\x00800003c57877edab65938846ebaab8c15e3f06a0d9307c066a0649db2720c8d385b7b485f6110e8b15e8e230f5d69e27548ee8b212b5de24c7999d59b9078855343273b8be5a083664338a9ee6fa4a61e7b1a75959124436088be41462e86bfb199d87feb06b5a7808749bce9c561b3af11b42f5c8915b9e9f3654a5d126cb6e7ec4ff010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xae8cf14f244b40975ccc5c388cced20cfc4f6e2e1294182cd172b90122bf191144cd3462dea5e08d1247d00d32c06502bcb871db20adb5c9b6157eb89b9acd08	1622208476000000	1622813276000000	1685885276000000	1780493276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	174
\\x7b09f65b76e39c22dd0ad902cc1969dd29009c23509e08829cdc2c3654c1569325b6614a2c41bde1cacf6a7ddc64c6ddebb8733bbff862d57f2a393e4ffbc292	\\x00800003e54208eff97ff4842cbd35a72e9dd782305aac5ae42e586f890444cd4dad99dd6f4731220388e90801c8490ddffaba10f101c9049ee7a6479608284625b10224a145705a26960ce2b7677ce61a03347d24003b7e8a2bd658fb4984a52706041db5a527d31111d8cb82e204c8b384a18f28b7c4831121edb7fb49ae079af203bf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x02ef10421f5d01e609c96bcdef319934ba0b0bcdf58dad9c6bb2857ca562af718f8ec147f51bc49e080e39665025cd4a89ce19dd293c5bb4bbb5f040889aee0f	1614349976000000	1614954776000000	1678026776000000	1772634776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	175
\\x7d0d7b03e1d7235d3e004ff13af898a28d9c530eb059ede4a73aa4e062549af9f6785a7ede623059d32825d9a414bc6b06e3ee46354c421bd518e53bbf4f819b	\\x00800003b5adf0327d2a0e226567c5668935cd79f5730d11ac44cadb3959932041bbed1195290fde1602f903e832ec2684a985bf20003f1da1e0583b7a18e4444c1de25c9d5539e1c137b8ae646fa961229a14832ba6a5aa11c7eab2e3a2b851d15d5ad35d640a103228e017b1b9aa1c289f980d9159c52afa582b6a7b39fb6232e9bafb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcf2cc80911f283abe0fd7b29e333ae94e161fd3a6c15d5c2986c62cf77f6fe20e2960d0a956c0e35aa093fcaba41c98d515e9da8c1d19fc60ba1eceb190a8e05	1624626476000000	1625231276000000	1688303276000000	1782911276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	176
\\x8121171b65e3fc4f66aebe6e8348e0bce125c8dccf1dea609159d8f115b161cfa4adbfc216eb96b605075b1e82400afb4920a2d904d82b6f1c5e45e233a02497	\\x00800003b77b377eae9207f34c4392f1b21246f2ee7b2aff489d053c2a7407074f12bbb0d0b2f9933af728a9d2a362c18274bb0d017641c09d03b20ec73ab306a92aad533ad6899508b9ef2c663254f34a62a0c89fe3d80ce173ca221eaa80571ce6f9bca58ff5b471c52ee95145022852195eda206edb0ed83d8f835eb1332b00b7c541010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcad81445c1027937601dc2d5aaa09f23967fb192079063a4fd4007e7873ee28d853f4d3ed8b09a5fd285dff27d68adbd8e67cf67fc84679f0eb809c2a6c64c03	1623417476000000	1624022276000000	1687094276000000	1781702276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	177
\\x8181b7b5e8cf5f6953cac271d20874f8c1b0aa8a5043cc5b70201cd6684e0bd37e99c054f5e8de854a9591851523e5e61e52ee11d698364ad8b8a0b70f0a4a0b	\\x00800003bc69eaad4fcf705ccb99b1f6ca331e7d4d165db1fe5ef2d8cfeb8487d03d61814c70c9911434c0ac101675e68f8ea7de0168d244da7da6683b111cc73f6fbd52874a6dcc3263ff9301adafc7d362a37058861a2fd71426c766b41baf952b8b8682d896de21974762c5b390947b7e3902c2637d0c90457832302c995bcb3348b9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x75085d91e4d08af262d027f0b573d7085f5ac27a361d6b468cfda185cabc97fa78dcc7c18b8a78c5a85b0c733d82f51f5b4bba54ef3b1a5922a698c951c94900	1636716476000000	1637321276000000	1700393276000000	1795001276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	178
\\x82255bc96733bcbaf61e12403f7281321c040620c0fa0b07c51878fc23442e9682fa891fbfca6cfe42a7680a718807021b3affb48632c9c3212de2775475e3a3	\\x00800003c6314990a827316a9d369af1a3d252dfaadff113c44cdc6c97c239d046d159c63ad8374b7dbad8d52ae297e4a570aff9f3fc1883f4707d12c7558c2dd5790dc9272e475196a06de55339aa4975a4c68010f69ff2e3eaf9b2481684360bb63fc7dfb7e40e06c088e203eb39d8e6a1953ac5080e4f648a9d457bab1b14876b759d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1b27706b2f8d52e471e1eac29f066a2c60188de535e6eedeeb7232b2ab7b61a8e46bf651497105fa4d8400c3d9f45567ddc867ec0a029ac244462569f1c37c09	1611327476000000	1611932276000000	1675004276000000	1769612276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	179
\\x849194fbe1274b022dc87074f98c7f19bcd173fdf1ff70bc7afbceb34da9055539636d4ce11c9b9e31549867f7b6e91779dcb20a5bc203beda1e8f31bfdc5f05	\\x00800003b4be1e9a69f98976a839fe8ece1edd717c61be0c8dca7724c94bccd951e21d8135d28211cc3b82269c93286df751210a74ffa86334623916df00bc9cdf1e78d97f4ebe28338d07e243bad027ad87e429561f821192cd487fc71bef0c0822bfe35f6f2c5523acc4f55f3ec5d1ea9eb0b231d69536b9423464c65f50451a2423eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdde2f15af11cb0522741e7af260c0ac2dc94d3b1eff120ab7fdc7ded2961cd7ec88163ce924ba5207257a657426b9f47d18a85eb27ece21eea4cfcaf3058000e	1623417476000000	1624022276000000	1687094276000000	1781702276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	180
\\x8c25565e44032e760a99110086f5b6cf41a61f1edd80103b074141b3e0b89f8df9dfda5d0ee8b434fd95b480dc24b8c7b0cce2b70ae58218f7a541d96e85dbc8	\\x00800003e670ba379c6cf0722fcb2293e4aba985db03aec4e7cd3947d14749443199fae5157534d6a2de01bb338d4e9a89c4a354156bae8e23e97b031cec5ad8dc1d23499a74fefbcc342daa53df1abfe19076bd5a150d24d5ff3605eb0e641ffd3d82211756229cba42d1cd386ddb9278512b7617fb93c091bbcce08c98c2215c7961af010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc27994b18b6ac033d0addba665d342b614e14b8c2434e18bbd1aed94d7558243accc2365af19b88c2862a6bbcd37552b2acaaf21e9cd4d5107947032d6701405	1610722976000000	1611327776000000	1674399776000000	1769007776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	181
\\x92d1625a9c749b702e881bfe19252de125e29e6721b4a8c0f06e6c1b9eb6ba482c500a59b5658ef0cedbc77b2c668bf221b016e3ca0185926f3889bc3f59b529	\\x00800003cc51888e5f577896e9b8dc64a2d2c55c2439ae57cb6e16f6a69cad6a0d25fd930dfed7937b1275fe7c2196ab44490dfe3f41144a3aac1e0711ba427132418d2b9516ed297315424aa1da7a1a4913d2c49040e856960a766267e343c7016e152a58d69387901780f0e4b3b06ee7b05457ade2c897544956fbc2df9719921ca3cd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb331908b6241ac8d3befadfc40c747a3c5e3969bdf51e4657b4233a4aef4078e7291b1c84d8a9863cc9154e72b23e2291d9f031a68d26e0fb5c8087a18d83901	1625835476000000	1626440276000000	1689512276000000	1784120276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	182
\\x95797fbe2450ecef8ec9b7b9c7ad9a0141b7ed4403134d0298c7aaca0bb5849ec0a21e7295657504c5df387fe94e22a89f40939b9fa669c6e1f6693534b17f21	\\x00800003bbddf27b59bf53b9c2c538fa952cbcdbda1f8dbbed3b1b588f08a1f9ef026ad86f6a8505c90d86eb5c1fce733a741d40dbe8656a2453d8a3bfc0bdb4de0e02b41b17ca74e139c0594f0388d099f4bebe9ca31f955720d6d45968040fb8d324733d4e75078c6d4ca4956d9d4e750e4c1ac033656595a29c4a563a2186d9f0fcdf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6e71ec4a6e4dbf8c82e56135faf1f406940b66730905e7e33f867abbfe2ff326be37f841c13f94366b30bf35edc46b3735308bea3f0e36923f5fceba4352d60f	1637925476000000	1638530276000000	1701602276000000	1796210276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	183
\\x9869aa34bca97b387d4738ea7bbb645b494a3b289cbff1807ee2e026593f6a591eda04213166e15b13e1a7692e2dda7de33c682e47f3055f6d7e111af54e4b69	\\x00800003a5a0dfee574e74a5aa163e469f12b9e4894efc99f46c3b99c38658ae8c143b6d2a42eb2c67bfcc49ce1fca7357330b3ffc422c38980dd0c77febccba4941eda77d5b9292b7768576b7893dafc6f7cf82e8475fa71817a8c284236d5b08005a94540aa9011d604474cb0c9e04f9cd748e141e029a2da535081d254f8591e06423010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xca566be93a6439fffdf1891d1014998503d6cf74473e2debd33f18f486d68b1f45252b0476b52326341066925346f58c2d8b8ad4699a0043ca1bbc14c6eb2600	1633693976000000	1634298776000000	1697370776000000	1791978776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	184
\\x99c9c067cde538c803267ed19fbba03e4a6fc4dbe4e20b9ebb31d287fb37b7aae06913edb0323dda91528500547f9f3ad029d09c2dcd3d8a4568face7d3aa513	\\x00800003c685722fe1062c76ef7166dd1ff89801028d438bf797e23bd61e664b5627e951ba6f097826eacbf44b6dc6958a4a7899876d013f18f9ea680c823afdb7d4caac27b95459cad7dd39866a436aef96143670a1beac4c5bfbd9756e67fce107728653cda154a2f817cd3fbe36a3c26a592ca86ed09b0c37a64a2b7aeadaa2c04be5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4ff3fda2f7ba93817c45f9c7975c05691315759be7978dab94f1ba7871f54cdd0f588656e747d91d2fd5f4f19012018fa508de51fc0888b281fa1036e9551f07	1634298476000000	1634903276000000	1697975276000000	1792583276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	185
\\x99b9b6fafd24d32393ec972ea370f337e4d71c4f0ab7367ccef03a9feb6e5036298e40488cc22359ef5e39730354b9f285943a33b87795138b8c6b53e6478f66	\\x00800003e4353e254938bc5c86b75d42a329662acbff2c1d5efab008e1c708629b0505863d01a106d1af7738470465626cbb4b139e5602e87498bf7fbf654ec47b846b32dbaed82880070526fd28c39b25935ea4e535237b5866f205b3cf76c292baadd76bd490801f02e9e6f6e3a9401c78c06a24a11f4d9d5021b39a78b971fffd2a37010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd6c90e075ea70f6866d4095aad6c4b1d5313abdd8c58708fb38956eae5a592e1221d1a15e57adea0e75fa92db237ffc38d196334dcf45269bba79b2c9113b209	1620999476000000	1621604276000000	1684676276000000	1779284276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	186
\\x9d2974525b4a2b166c77902d744ee246fc5a57af8d6bf941c47571b0da8c44a95e161d51bc90f5d4aad072ab685ab61fcb447e7f0f4d4e34429a476a1af86539	\\x00800003d61b8becdec293c0cf14bb6f48a5de364f46053dc2cb505e94dbfcbd57e58fb2d137478a2ce5d88ad44a64273f6fc17acc8683a755cf2044728c9ca9e368c234f1d3a63db9fbf456e8f2079528204690f5653f37d21bd860528b82c02a8d6633678241e40286665ec418f5d1b31ba005c82682ba57e01c0ef3a24745068dbc11010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5159d579f5e20f54bfe0b1d0eeec547f8f8c201f1cc748c3e882ebbd848a1096877edd643248d57f94b95e7fd652ed28fa1e3596a58729ec0017b467d9ae2c0e	1613140976000000	1613745776000000	1676817776000000	1771425776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	187
\\x9f81a426ddb683b90beedcafe6ecb21e468c0cb263dd725b984c1b8b8908e3e070f1afaf393fe367488f4cf236891e8682352505199f993ca3167504665b84c6	\\x00800003b711a88aed60c49ccecdc70a09301a1fb01108415fc4c7d1d7db9fa640efbfd8ad77a4404b2f92bfd451cbb084889823898a48a88e7387602b2c1e1444ceb0d1fd60d58c6622236a8237a4b5bc7f3549f68ad581e8bda60d17c578134dbd729ed9e43c3b80b719d4d98523e165d32395918fef2b06ff616af2ceafdd22f459f1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x811624c332d0296c7ff2ee8f3b3a53de9e50ca392bf72d97095e9580dd38db25e20f85aa94eaaee6cc81d58357e9549c312af22afd685e04a300e034afe80f00	1612536476000000	1613141276000000	1676213276000000	1770821276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	188
\\x9ffd48184a0072a460c6d047c6906ae315fe0f6ee3598a6d1c9479957fd126b177e88777f2196d9cdf185e25cdf16109913adf62e6e26a569c75dbe66628b5e5	\\x00800003aa4d04563865346484028c8da5fef93b854a3df0cef072eaacd47d6007022447a95b687f4ceea6a37c45ca787c8d70cfb0989f5fca968c04a13a90aa424d12d755de4d86f1da05e4bce6bf5badf3345c006ffb8db54f5e18bb7e4c407fd22371df9077d8931029a4e90999e7d5fb447867ef03be87c6d05845238f2b739b10e1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc980b71e68dbe4df55c76c6be9ce3e001d79145daa397e9082a995e84c4d1cc111327321c5621b3073613ee5e96b629ec851356458efcadc47fca01571e12e04	1617976976000000	1618581776000000	1681653776000000	1776261776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	189
\\xa0a55a8a62d9a8b760631d246fddc5cf999f13e217bb3fda2543faa9e54763ce13db3a66001c616e3b80bf9b6139cdc24f7c2f5e14875c123d0e3717b7aa29a5	\\x00800003bcc853aa3a98a98bc32d674061feaeece617ce0e6b91635cebef5e7605853bc8e2dedf55e85df0e30cef8859bd9679cb5cabcf1c19c03c48d06173746bcf30b72416bc1304c753466aaa70c27b88088fc42cbdfc7a4f966e8ed0e308377c5ceb6cbf75016cc81778ef51adf28697b1c01ee89c0419abab1b41ebb17e92ea9421010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0b167078084ec064552dfdcece9ce368a71ab7591a7a3dbbf8c2567c8821aefa52a95256110e90dfe573e9e75c0153846b0c276fd0b9291f60916e4866452608	1620999476000000	1621604276000000	1684676276000000	1779284276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	190
\\xa115f02bf108c5a066ad6ea58733b01f1dcf56d6fc9cb5e58f691d5a1663bb6baca292f41478e32c0477aa68487fdbf1593da320a7601fb0a6835a3f9e7be382	\\x00800003be8db42f0a6739e7a6850370d0cc051f9ee50857d5c776bcb7568c4b4eab03afaa87194a6b83e3fac6856d5c179cbc6fe2db1a7d40dcd38f64a012b2b39acb048c074eee9a8d631988c0516f8af0fc54c58e1895d04be77ef44cb35d628314794a28d486248fc72f9c4c2172799132c5157ae0dbf3d9b557ea35676ef3503181010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xac2d8ed9c6330cb2ea9b8f52f0753ffdffce21b36f099ef8cd71b95f041d0fe6b3d6293b4341a1ddc40d2737e5c87955f09127f19d430e0bb18e06edb13d2408	1635507476000000	1636112276000000	1699184276000000	1793792276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	191
\\xa3ed8777e30d56dd3e44fcec5c48fa8b2f8b431abbecad7d3000013c2eb4bba41b7866d5d376f32c4dc8cd3dfb33d0e12d169c8a47ad774498263ba839e05d8f	\\x00800003b0ceeea7a5ebfb28ab0aeb5b4960ce351b5386c7cdcb2d6936ff18422d2f61e14500d7fa610738ac9a90c5842222c768bcdd2605ff2e7ab24b243b80a7955961585563def00cf8e8bee1468ea7761837fdd2d5b9d80b83c717e094df49a7e3bb3e20c7dd8b109373ad9e6750236f811016ba629706899bf2797286b2f7e6fd3d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc5c5d7d9d81dc5b294dc35e8ed53fd5ab4b74d334c0881969a6ab0cb3cd484659a4abcf8f67e2393356ee529d8ff0cc488d8a7a13c8ad2ae4c2f92c3de6ec101	1617372476000000	1617977276000000	1681049276000000	1775657276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xa43d078146786475384e99c96440d83126f21f63e194a441a695df1db4d5cf547be9091b5b113939f8d10f07bfe7e0d53ec6210eb2b3e7af26faa2647f670aed	\\x00800003bff5cc8f9d2e1f8b2fb9c4262400fa264b3a519de38c65d5d9161c6e24268d3f52b379027781a9e202deda72c9ed501baae1a923b789777eabf45560a11d56acaece84ffde7e404fb54d37653b4ac531f81feda8ad82c78a48ee31a44f2d2bd2e2b546552b5a38db1cf92b1733e2979292aeeac2c6a5e3334c5324d09bc9b2ab010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf7d9e7e263fe3068ade66339d3708208ba2614eb70f42166a01d13c607a2c01253467f0d8b28aeb3a69f710ea5c0a34b50258fbe10620df2208db3f1083c9802	1635507476000000	1636112276000000	1699184276000000	1793792276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	193
\\xa4752297b7de12a8c0ae43eaa160c0e65baf19e56072458f1e694685212387bf2580728722cadd26cb5c1f230321b61c90ffc518087a55ee486117fd985b112c	\\x00800003bd1c6721e264037eece5873d311908a77fde120c6a2d63374449338ef77e0048ad8c08438569bb0ec046f560fae620c887432335530f6e1478ce9be310c7ad2357b54ec80170149352be8804e8c65d5891f4f075722c0bc9872f38d133b6d6e77a85f1dfdf22f22a1c0d4a9993ad9560d688f7512bb667626d196e44ae08f003010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdfdfc3db308eaa9b631b214d3366a79f41d6411a45eae6685f3ada9b3601724c983a4cf7149e023a6a4e80ab42df3eb2a7d8c9dfb0b20e7c97902a9a8e540c0c	1627044476000000	1627649276000000	1690721276000000	1785329276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	194
\\xa8c5f2437cf51484b899488f9de5fea19ee447cade3932798cb0cb81ae5764be34af7b05e7415ee641d0cb38aca73c155122fd5a9ad29c9e214c9b514ca74f45	\\x00800003c21b3d69e91e89fbb55fcfd96d534e1cac8fc80dd7ddd4a5143bdfd244d773be846629b500b818dd11091841a04a57fa826dc62257a7e38bdec7966ebb93130c1defabbfcc294c661a1317e6311a80e96e567b3d23c87040e7467a6ce876f9d420a8fa18c3becdf9bb610400118b51eea8b0d806f6ae08b3fdab7cf892ebdfff010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa8628c19f8e05b9f3be17ac4e6abad1db69df0596af60aa1ce0148839fcb81551cd25c44a15712257e51f0f011d9d159605cdf9b9a53709f7452b96eba478f0f	1628253476000000	1628858276000000	1691930276000000	1786538276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	195
\\xaa95d694e2ddcab79f197042d5030148308f61e0760e15b3572e65844d752ed3930848dc34142719f9f924f49e77a05f887d5c7221fca95d5e943ff40f3c1162	\\x00800003b64dd79dee505ab2e6e2c60bd7f0f4d13c99aa74edca39d40e321cf1b5833aeb09856b77977a4cbec82973ffd5f6c17e0750996d476182a986cb1f51fa6cdff0f371aacb4ed74192743d9def8ba48b199cfceb42d57d89a6ee8fca5bb79417416dbbcb9217db16c0a918d4079acfb23c67e9a7087885339d4b77d6549d352075010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8544d1c6504d51855aaba3e4e2bd17799bdc3ee0275a16f23acab0cf209c3c9623fafb722b2e0dcd39bf2bffb92769aa9b21b189ab06427e0090205d5e4f6c03	1615558976000000	1616163776000000	1679235776000000	1773843776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	196
\\xb3d5a6c8152db98824f42c8b0411aff7436842eda263cbd628fe2edd3838c05ad7afa13781ea8217611a4b5781d4c21acab242994a60fcf0911b07f7771c581d	\\x00800003cb7fd3d906fd4f94d5e4610ca83ffe959f579e048250afa9976ee6c4606db2589f180be7ce248c14c091e9575828289146200a816a88524b1073fa96641c78637e35c74d2e3b4ba0a26f910cb4e6a9657320a68aff5615cf3d592587d028516d51e113ad6c2e841b75fad1623d0e22d8582a5b6daa41d7e8a83f33b5f38476f5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf08ab22540500f84f007383e0e966bbf09031aa86a177ae0354cefaedabcf01ea9babd74c0626ea6ea6ad91b890be76bcc10aca84f30e24164336206d07aa10b	1635507476000000	1636112276000000	1699184276000000	1793792276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	197
\\xb409380f230b17261d76135558c83fae402c2325cce50ee0911c53494e1a22702cf92ff3d6554e15331962081ccc83f484dc18c7f9a9e595cff64fe60f6a55c0	\\x00800003c662b2e4a1973c0e6fa4e70ffe3e8dbd9a1f619b38f8dcd911511acd5638d1954b8e3701bb54e89af03dfdc5d5aac3f0af26fdc3b740ae628eda82ec3749af8bfe56e5761e8526c6a1069ea110ff463482d742504d6f9555ae2b7943a3195a929a1577ff65f3aaec0315036ce643d2d931c9b4b238cc7bea643014d777b96dbb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xba24b1858e8e953f9e1d862a2e684c8482af683fe3f25c0551a864c94c17236ccce71553e4598bf130ab8e0f57c264d26188a6738566f45585199f05dcbc2e0e	1639134476000000	1639739276000000	1702811276000000	1797419276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	198
\\xb6453d951add204cdb574768bd39167b5873f7986df0df472d862ca84e1dc66cd0769954fd019f0e7bf8478838f858a6c6cfa8d740e8fc405ca459602c157591	\\x00800003e37175b26b4265200a166b6eafd99a6082ab21d3898b42eb2630fff42d79a8e44b571f75baa5dbec9198d352d59faae01d7f43d7bbeedf68b00d3c2dec30dfd1f8fb4eab3b6409f9c269c87e7c9b5af944503dd2639aa7b3795b66d1e3a2b3ab3e3a21f1fb30fc241543c49e85655b17f4d361c8ae9e0afb2c0d651ab7ac2199010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xad41f7ed1c8532f468aee9035095a87fc8b4f1d994ba2c1483025fa1c62f6dfcc8cab562b84b2e3e86a4ada2f5b6aedb80b4b68f4d2166355d88e7cef14ef60d	1613140976000000	1613745776000000	1676817776000000	1771425776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	199
\\xb8b50d9daf8bab27c3f0ceda1a723165fefaada2363c2f5940ba31f5ffbef526bd0059985289c3b1e473b39b1a159e6aaf4407c781c58050103bbc51b2e55cff	\\x00800003c02b331d53d6437fc757c212925b45efeed6ba169d2c55515bc1ef1f860cae0fae0e885a440f45d9e80d594e5cd7ede8a45a9dbf69cfe2dbd3885a724c95580ba16d09752b35e399c0f88fb85de26cb2f3dfc2f3af1fe4c649d56afb77cb44f00a69d6f4895e34808aebc8373715f7bcf32c50843036f9f9cdcc01f52412f16d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfcac48884a6cf97e9c927c4d1a7f7d8c274434d051229261305771752ffd05499b6efb4047a4338bd67c6ac9e86e4f0042e01c4f66cd02b0072f98cd6eada80c	1628857976000000	1629462776000000	1692534776000000	1787142776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	200
\\xbbb535ea711e14269fa9f153c6b797900cfe3259156a14dbe44e949f7ddb84c5fb2fb866e8df8e56e72c31e2e0b73cb4d1c70502aa24929eaed5025dae15502b	\\x00800003a7408ea27f4752d4ceec673f35bc0551ab1ff58d4edbf0b5306dd661d66ba5b5ac4ec3da452b3dba5a892d8d9bc05bd25d64952809ed6dc65c8f9a3a1fdb50973bbd4f0d07bef22a644387cc7f9b774e45a5f31d19ddeb0c07e84c7b26e92e84925b0eba05ee278d5720521d652884b0f367dcd2fa89692be197e85645efa653010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x11b57142087f926ed0e54786aab38ccf2889dd3d35f147a2436ebc375c3bb8c1f8baca0b742df29ffcd724fcddfe34da7ba878df28db865fe756cd53da6fe103	1632484976000000	1633089776000000	1696161776000000	1790769776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	201
\\xbbd1494d520c6cfdb1da409886f0b0b9033107b2d1c489efb54f9e82c08b59bd7357cd0a5e50c250b2a7e6c67c378b7607feb5903f6c774be15f53e245d82527	\\x00800003db9ec6dad82107f1827a173d1c96b6fa5e7492b2a79f23d37a8cf664a240383aa527d03299cdf756996de66e257aba647868f08cc512faea1ad306bbf221d5083420ca5dc3242a5d42226442c8fb5ef5a9b287679c0be9bacca8a68a3e3e361f5a91c9a2bba4dca1bb898654406f7cca0d56599b93e91cf2476078fa3d0bffcb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe103632b620a71b6791aec1af7af39fb07e8aacef23e6772f483f63f51c7b30e70e411865449a99ec36f90ca4d830ff647f0e12f997d523d63bd9b25a762ea06	1619790476000000	1620395276000000	1683467276000000	1778075276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	202
\\xbc695a4830bbd23ec4cee601fe2d1d13017f834d6b23598db4e2d1acad4b06aee7d19405272d1733eddf2f1c4924507485e00528abdbefade4ab27fb6baa1725	\\x00800003bcc902524d8095d836f71684087a05e14b9eeb9270c8523923cf76681299a2b64a2c05b8464e4826b7fff96e2ef6d3764c404fcfba1d0545fe2d34d103f2d0ff33cf9b993b9bf529e96cd105812df78f835dd25a776c3634f360cd78cc55b102f53588cbbc591aa36bbcd06c236d0812d2ac280de39c3b49149476c35fb924a9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xabfbc53e935f6484418061881a5f6ea23c64a425e7a75379cf3a4d53707f6a05942d5ecae16c8e742a11a73e1a5574dcdec28018265cab0578b653f4b404620c	1614349976000000	1614954776000000	1678026776000000	1772634776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	203
\\xc1e13e4a06db6a9e14e7fcf3b8855009b93eb53bca6c465c67cd3a7cd52e897d1f3da8eea47f308a5ae2c21155799d52cda406b2b58dca686cb7287bd7c85296	\\x00800003a4d1a89668b8c8ea934fbeca048debeb95551c27c5c63ab4af2a46feffe142d18e0b81c767a30055fd8749a6897610af573eb9df13fabd0ff8e9106ce9984c732314ca09589d5a8c0fe7407cc8c290dde4814a3d51f06874f5915d87ce067e49e37fc0bd9a10e6d2d15a6f3133ffb55975260f2d0cb92f40f213d75df764d359010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x977eb8d7fc1580273124c6185c42c726dd5a0b3140f9764f49abbce26cc4f1b1426de725c378aa603ac1426761a5c32232b6ae11d78b3c4643887e274d9c710c	1640343476000000	1640948276000000	1704020276000000	1798628276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	204
\\xc32162fecd5e5451ab9d0e91f470126481a41ababcbbb975ce959f434f952f3b49f1fa421e424e149da04be9c7260936484c2c85ffc547284e905022c4c6528d	\\x00800003abcf765e72dced70254174c77baea41ec6e6742590a85153dc78b77dc4b8989f75df294e82650b8629d7ebf3c9996014bfbcf777008a874404cc2fcc003fea2e210c58cd7e27fd0cf3c8e8ee932fa8dbc4054e923b86969df4289c8f0bc482588fc15266b918eb226ab79a7c31207dcef0fbd478de57c6a2e6f33595884d15d3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4ef14703269f738be9f97a6a23498d8701bf3deb891867a671353451e74f3ab35c9e5b95049926872837ae86885a3cd113d220816b131b78fc7df99a30035206	1629462476000000	1630067276000000	1693139276000000	1787747276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	205
\\xc9b95d656b9e3235489ca5f35648956750aa53bf19973b42965787264f511fd6507299eb6428588c8ed3dbfe767ef81907e4dbd8a08953f9a1154cafac2cffeb	\\x00800003dc245a701431890d670a7311c2c091305966145483991b2e27639a89a6da02f3ae012163921f2722a4186790a44ce62286b02ea8a251cfa2abeb73345481521527c7bd5d2b48d068094479aaacdcc5a6d259ba58b92c9ab5469abbc5f7b14e66cf94da02c51ffe24a9d9142337caa3b35ee04dca5786f835f6b7989f4d0f1339010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x980748a4ddb3eda441fec2e949ecb213fe2f75d4d494bb6e084381a075e9fb6f8c1ba4aca657b7a880b11e81ddf9c9c148917ad815be626ba2698cd6a4beb501	1637320976000000	1637925776000000	1700997776000000	1795605776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	206
\\xcdb1f014ffa5530860f1212ec34e60a2385dd1b1f9303dcded7d95cda977c82bbbd14cd4be3df0a351741e0abfd8efdaf5a076ef5b659d98ad3f960ed5aa5033	\\x00800003b3b1924b0c9cbd0fe752ae102c318b3094565ab866b47d71eeb956158e4ec64599c2213a594d5b409ea14931fe5b4b9441368e2815212a786a6c7c21d08edf49998f1850f450aad47ec8b49180ef6ffe777dab1a6d945c05924ac47b67326c3569de9b87c3e4daf79173d3fbc8ed6ef6252e45e2d09f3634d09b9b3314de3a41010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf9cf52bb74e7d187ac5d2efaec6cf408f8e0ab20d3c5eaee1036ceed20fc5e200cbca1b13292df3f4018529de02e0026816cf0550dfd02f8469a7882099e6104	1625230976000000	1625835776000000	1688907776000000	1783515776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	207
\\xd11d2002724dadb16e09b4e38ba35aaaba327d45595f6d4703f03a97714ae8bf9442f1ee16a2d96989bec396c0e9c45f5b6da1689f7d8e68ba21091d9b676cc5	\\x00800003a4fb5f4c3e038d50eda9d03d92360bf33e5990e0d0ba396d9ee5ffaeadf80b78082753c7a02f59b3db90fd3eb026ea76f5af8deb63c148764f217966c568c196f9546b162d40c7417580dd3e910571ee7cf97eeb48f1e1cfdd8f0caf4a4b9031ae828742b3c4fd307c0315918e6db94cb8dc004b88d329b41c1dddff0c352da9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x02143d057a19ba855c72b2850c25881cc11f36801bcc602fb9fa493a652de643c303f2162450fa61b6c4fa8599e1d0f981ffcc8100afc8761ea8ec337b54bb09	1623417476000000	1624022276000000	1687094276000000	1781702276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	208
\\xd111e78979935da84c7bbab38278b9b065041245ddcf0781851dc0691667850dc42eb46b42953b93a94c7154c9e4db951c8b3b92b540f9eafe0520c7be647628	\\x00800003b89b5e662a76b04159f55994ddfc2b4373c70659eef2d421beb8fa4d36bc2f5c01dd5ef0b04087c6a6d39b81218deceaf5a63dd3858f0cdea40fb2afe34d41e677a7c6d2961e3bd1379d69b1ff81cba158c807f73d88cf1edb205a4090b392d516617dee04d4938b14ada0f49165e02ff675b3d2b510c1d25d689a0d7ebccb61010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0f2ab8e491d285130553245e8af841ef82923ee07d31455865af96b5136cf2b1f2f522ee3920ad7e41c6f312b06fc2895872cd9fcdcd9bc08dc382d1b207ea06	1637925476000000	1638530276000000	1701602276000000	1796210276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	209
\\xd26d7179a6708d2425f36f98db0f286be320fb4dc586cd30e72c2481f7a6d1b2b06514290ef0989c2c7dd9179ed2755f11a52da5672aa015126a1a579b4b7cb2	\\x00800003e7f0103cdbbfe60419fc6ca3a5548edaf20af158cb38fa166483f13765b5141acc59615142439b92f5749ea6c15a4c22edb5d704eb7cd049502c4ab3530afc91bd27ada3bcdc2ba9e3f67c41c9c821986546a0e5d7661ce0309f1a44dbde2e1ac68832573b07ad6df5955514af87a3e23c4a2634a9395625c91280cada60ffb5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xed70570feac420bfbbf3f3e2942f61ad5169791aad9ecffb792810f7f7ccc21aecd2a9d6e172fdfbec573c794e9b7d116f15c48912d06203ba7540df69d05e0c	1625835476000000	1626440276000000	1689512276000000	1784120276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	210
\\xd5f964a93547247edf1ba6197a16a588d78368cd05f732ede0b9c33f920091e67bea05876ecbaa3525c8dd84d34786870cadc670363ad600e7663fb17426c99f	\\x00800003e17b59a8ab05ad3cdc62830c15446f47aa28c21d2b19d40625ee874259a7ca6b95a27929580e009044fe0242cc42de2ae6b3fb6b1f265aa663d9cbfbf34a92ed1f80c3862f6f160336d47064a8278e46b7de0043ad3bb0d652f4eea2d32b838b7030ef412d3dd97b59a1342ecfdeb932a0e60f91addde5d98b4068bb02313e77010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe053bbb50a01f1fe6e3cf159d094f3b8e1fa2dc88f7c824f4d4f4dae903a7f9ea70ee3e59bd99a82f529553a84d445a5c0ad0eb8d0e2f6c6aa53fc5fc8715703	1625230976000000	1625835776000000	1688907776000000	1783515776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	211
\\xd5cd05fb902f934c8b91688e58907448734ca7b74ddc7d056ea447c0973df408a2aaa1049a6fdb25b4071ab33a7f39e25472fd26ba57764df5df4f83c97bacf7	\\x00800003cea8de55fb8317db59c2fbced17c72dc01fd3274ffc46227340ef63e6e4bdd6a8ece393bdbf7209708a1c874ca003d658e53fb16845b2312f288cb9b0339228a9f00db92b8624101413743b221ab6f60fbe4dab999a5141c843ab93c5a1e5ab1687a76c11ff08d2a99e85d7b80d20dc8d1cc397aee695381ca88d3f28c44f5f5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdd42a9ea0fc333da028e46baa086d81e31a00cb5157b5488cfacd00d78c45ffaa62ac338548e3612385d6ea6a48eaae23965db7ad43a7e13b969021106794102	1630066976000000	1630671776000000	1693743776000000	1788351776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	212
\\xdd611c1dcbe444ce11037663d56a1930d6d751912a4122b744cb3b3bee77e2e7b1a4fc7c3f8bfc3ee1c49dddbaf6418469e0636d4c379ff9186ab66b32f77714	\\x008000039f1a81024f30c210d0a1f0a5aaf21c6862dd32eb537e8f80707a31aaa0b6fdf0b3274a6c57b97bc3631df7744bd340ff6569825b196cce4b20e0f670c9b6ce639b27fb090fc72d31f7f9eb3a75436cd257921d945a6e2e7d232a8df54732646f189840fc361b80dfca5453f685d3e83fee9a22759fc779d73c68638f44ce8519010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd357db3d2ef9a4d1d6d89399bf3d4217a001b78c905c8c0af28685c702d113943d4cacbf8a7d5ecdbe011ce495032e53a8712652d773bf7e34f365cc6e5d1308	1627648976000000	1628253776000000	1691325776000000	1785933776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	213
\\xdd454e8bd779d91ec8a2e5df76ee0c720e4cb8158651180a168fc6e9fe1be9981112ba709235b3530c1b401e9db09a8222aba085d9ef0f88f0c75bdf80e26781	\\x00800003c9aaec6ab964e7aed0b9e7293daabdab958a855239b7c93dcc5d67d4c04299347c2801c6822f62e8e702c95be343da797f557269f02ccb5d1a5a48a472e547406abb77998368b535876e65073aebd823a387bff145a8318346c8f553bc7c8591635ccd6b1e46a107050e3fd13e0a29b81beeef1b0754af23b1412b57d3d84313010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6d621eaa965261607820f1a0f6cf742144bfb13f7166bacfe0adeb3994c016211e5ff1e52cc13b704d469393d5bb4a4159e8e44f71c2317847a66cb0ca6bb20a	1616163476000000	1616768276000000	1679840276000000	1774448276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	214
\\xe2a9c189c060cd4092b21f1e6bd05d290b533729bcb2b4074369ae517eae83f0bfafa4be40b5c7cc2095400f19cb85d9b5923d5d0cc650f23b24c4fd96614e85	\\x00800003bf5bf6c34ac147a65cf4bf5c15a58fc9e0c700bd294028c6cc837893266da9a0c0f01a03e3087bf2201390f56bd49987b0946372bf02a005f55824c5b072ae19c5834d7d5d915836a10a8b386d682dfaaa1c60b1e90fb4de4fbc338bf94f83da5502f421cc00fbb454126282dfc1cbf6c4ec93c34da3494f3eca007d2ecb22a5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x730c71dcd2aded981c0df4b27b2acbb0beb4169375d664695057189f260fa5f610f2f69eed0142bdd479b14e188bd154b5bee60db912fe5ba9dd4b9a7b484e0f	1630671476000000	1631276276000000	1694348276000000	1788956276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	215
\\xe58d3420bca455c855180aba200a6caf77cb99343652e9a24002a56353d600265b1eb920a1dfaa0fe510d005a48b8c26fa199de99c37ef1c71684e5a34774724	\\x00800003b774406cee95d04cf1906faeb2ad1c69e9605efb4c0c75142652a7608e5ffb42c19cdb87145787714ebb612bf9a19a99f785720d5678134e9859ad8d8ac83baed7536175276589fd02d9593dfae4a67ec31e0fb571774cca5dfa5e8cc9b4212a53f2b14ca6b22018a8ca70eb02b137389b74cf653788a20457b10f6895729c73010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xadf539d0c41febac52afa25fadda429450d15bed006c2b3be5fb42b9cc20375f07465c6ccd222fa7ffd351a9bf028b8eb6f31e045e2f1d3a5f72d4f8cec7e20a	1622208476000000	1622813276000000	1685885276000000	1780493276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	216
\\xec7175ff2ebd8897f92e6401cf9b6a2e92113c279b2def0e59d3768b42277bb73a7149470214e00a1ec62e3af4122b7f8972a27ed7fef15ffd26aa8df5c93984	\\x00800003d4d08afca5a0bb6f7eeb2dbf7c2c2c29efc2633fb9176208734a8d6bcfe4c232c515fa884532d6fbfa818b580a767d64cab83b0e3b12d65cc04454bcc965fbd2664455fdd3d4014579713cb0ef65f10d3d1db194eb802b5a0f98caf18ccd5bbcba5539e53fc2ff26bd7a343bf750d4c4afd1f78dc44c53b3560c9b8b9cbdbfb1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9cfc8522a358c5b9ca897390a6542ebec0cd314da6a29f472411606094beadd48b7c47332cb91bea90eaf966d1f3d3906605e26cd92f5a6a34c6936358204704	1622208476000000	1622813276000000	1685885276000000	1780493276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	217
\\xed150e09f42e64c988f8ceada9169e39e0819258c94e1e79b325ede3daaaa8f980bf4868df96d3966deab0d5378861d89cd4d7b3e7525724b049a82c89dac114	\\x00800003e48214c6338ac13e472ef1077faaa5d5020c8f6e9655f99542093824308f3cb6f7d13e518d2faf3030ab746b46ab3fbe0f65356aa4fb8b61e84676fbf54c4e51649894a74a59ae9a4b0a36be0c2bd67be24f5ef9b4239039b06931dd3fe2f0d6284a5b573e9bcb001fcf7e5865b02a5923bb19245d7de46b770aae437ae583e7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x601227cd6a9b86fc8be5dc1280bcf6c84f7606f8793d5b026347900efa0964109d9bf197754f01e066d83f6db5a664d7026407be76bf51443f066402d7c91200	1634902976000000	1635507776000000	1698579776000000	1793187776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	218
\\xeff55e9f3ba59dc851c61aec09d951b2f7ff7efd3b9ab97203bad806fc298fee6254f8fc6653842240743b15ce451228dc50d4a323c4b281523ac34451bb27a9	\\x00800003d4e7c0e4638a857fcfbbd22a1a2a3927efda048c0c774000716039b80f9f67dd514daf46d93edc7db413f35ab5884318fe25c722b626009a828c557eca22f4079221c3b8baaf85fcf4330808956fbb543a121f6d3503259f3598e238b35eff307b160ca3f0983777d85807508d46d5f6dbc2a6d185d13f5784931399426b7775010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2e68e198586c28179390d7d4a2a7a5b56905a1d5d2ff3ddd1325d6c5973a80805aa8c413efa0386980dcfd86d1d0ef28820da48b07284342ad3900fe00babb05	1615558976000000	1616163776000000	1679235776000000	1773843776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	219
\\xfb0d10db6a899b565fe996e5c09a242ae68f7c0ae615d96ca4246ad53ace3133a11a57c241358ad02c118938d61621debed4bc806e4acd3179f77ba5e73d4963	\\x00800003c556ff9121ec4bbf7a310c627ba6a1fd4ca77823431ed010c69565abc8a7108c83d05f5a37eb702265f348cc02a00dcdf156bcc346db3f92857a4dcc2b792326a348a584733bd491294bb06ef86c58cdd9e2be7fcfa111f4457713ce52666ab16d67049242082571cdb2254af2de0a06341b9dbab512e88138936c0186614bc9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa2ce3ecd8cdada511f109dacb58df2f57a0b6f3d4eb2b47982fa43b865ac01bd93761dbef66c27f10c07f95e6ceb904792de986b7c1502cecb525ed7f97e4f0f	1625835476000000	1626440276000000	1689512276000000	1784120276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	220
\\xfb457edda7895370e6710fc3bd4e0c4f1a604ec42321fbfea318701fd21b207f1ba7dc237aa5cfe1d760aeea4b8a621cb5700d953fd9a0907d81458e7ba9d693	\\x00800003d3de0376484ab03064df57ce4ae7df4a9e79459844f16e122dfb833b65d91ea43fb124149d95bd11bea8a515035c28a4af2a057015f27eeeb49f5b60a50d04d152807ace404703b9c9f7d8715727818a373228f385f6f89ff4e1f5d33e402090b86db2522d4ce79fcca699fa1e0917b035b4f18f07a606f707d218a2496c007b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4dbac737f7840eef344aab623b3e3a1e6e0b118a89637793bb33ffc056b68a0024923a07b58ee184882f9ce58a3459a7c47933252b3647a08ec42e6ef2f3ed06	1628857976000000	1629462776000000	1692534776000000	1787142776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	221
\\xfde9aee04920c30191e4b4e7b54c691d9102626c02f7911481d0a92aec33491cdb71a975571a5b9d0b7ed2938eba0445918ba86b56292f2a675264554f572bdc	\\x00800003b4df7af1421e40bef1437e561baa8f832d8b657f3497d3f9358d2c86951adab0f8778588666568e2963e443166272436e91d85628a528cec273c2f62473c28a53a7b2ace62395e6c375f0b0c3722a107d4a42fddba782c943fd490364ad7666b058b12683ffeba247f236711413c29a7d97751da975046f85c34983ea6d98d41010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd12db4010b154f33d2507457ea19606685112daacb138a1513c412b7a6a8955d63e21bcb6c415d638f70eb3d848cb231126f516815479a1499eb7f0301df9904	1624626476000000	1625231276000000	1688303276000000	1782911276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	222
\\xfd09f200aa85d5b23492d67cffb56b10111e524122004acaa436d53c11841751d2b92a86f9a70519f3e23a40c16f21cffe813f76f7c241f8d926decb6c7d800d	\\x00800003c12e9109237735265cd25c8c75a0556a9bb79c0f8dcfc68ab8f30174f324063c39913e3fed38a286b1fc2708fa5abb8ea6af8ad245899c80be7058b10349fd6b4cb9d27dd41e9d84085d10e3614dc06b29844d6320043ad1e872ae7fd7fe26b27ba0a22de8ca2710aebafffce776997a572254618317d6b5b00e4b6a1deff5e5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5ea91f92390c52eb0fadb4c551c02f691f0ffa1ef7ad93525368f3e8ef987972969b4d4d0a2b6f2a102ebaed8eddb41296822a6de9f693bce2deb70890475608	1613745476000000	1614350276000000	1677422276000000	1772030276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	223
\\xfef507bf200440b735027f4799d7c0f8c92268d6bcdceaa4ca8d914b6c9cbe801e2c01eb43657879fa0c7819b6cb3f3434119e39b770b05c7ebf37507e64aad2	\\x00800003b33b3333a1a2e6b28008640a118e5d9c5582c256027750b9d81318a873d7198b8214173b11c7efaedb1f91337cbd4729abdf09071fb539781e4f66dae4ccd7fcad14ccd0240737c85c26580adf18ef626d525c7da7ba6f8384bd12ac314b674460f876f4737433b2fd6f59bc420a1af0501f664715e6939eb7c20d8bff371e83010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc908786e333d184bff0b547987bd2695c92a5fea6a246607d00b73204b92556661defe43b079e8ef2ff6e0aef730d3b6939d085b787c682ede76cf75cf1b0607	1612536476000000	1613141276000000	1676213276000000	1770821276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\xfe2178a590c0e207200c235103622ddbe9566062451d119b0c0f8187c34615df88860d058e137555f0f540af7b3d2d5c261f7cdfd175dce8f08f2d107a76a9c5	\\x00800003be3f3fa2198d281cc90bae892be3ae3e56b023f78215435cb7e456a4efa1a5f6cab5bd42d86ae29eb2dbb750a5f7e65ecff3ec2c440b22d66174a9fa75cefb1716f22b02285faa4b041e3baff3f0fae69d2d4d1489122c8ab72dd697c95d0473fbd98a553ae584a416a8b81ac94e180ba638a4cda2f9a60abc94c2b5f267b379010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x91229df0c23a5935e05e4ff2ea70d9aa33f50b50e902e4b3bfc6b08c74be3b01cf907e1409b92da07d7ab480097ac3d55e36862f363c69b521f68daac2598305	1634298476000000	1634903276000000	1697975276000000	1792583276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x05a6e2cd62b002404462092516da2d967f5aaf01afb8ba014634638f1e22d069e8112611466a37da9d1ad1bd5d926daf9aa53c2287551de02dc4efdd4794fd19	\\x00800003af3f286ba8dd04cbeac3c0ff4fac8e698ea6ab43f7b0285e37929371ac73366be6c68b4a5cc22b35e48ed8744fbb7ec4625cfe297fc5bd306f04ff42e10500c07863789e4ad00d59b1586ead300cbea60e979404bcaca89f8ea393d7718f2a2b1b7c34d7c6652850de7e8d8d90d593c788fab5227dc459efdcb8c3dabcc9cc5b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x849cfc195ff75e24bfee14328a75744c8a993dd739d3afb01cccf3567cabba4acf048fb2e708c6379ed6bd5ea0d3e62c29d71169ecba1af78d291b5ca2ab550a	1611931976000000	1612536776000000	1675608776000000	1770216776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	226
\\x06deb34f892c90a09964a0ea874c9fce4a5e73301d79e788f63cad4eb0e33490a92660ae13e643c8b3b9d815988202c5c1fbda38725495250295f521707dffa5	\\x00800003bb2695f1f88e0d8046ca4294fa653fa1067aec08653aa03c88b9773fe19c5afc27cc2635e164cd1012144d16dc3b456c453252b41472a62b819477002fd22698dd323278aea3679a683ab93e3e7a99c89ba8be54aac47f69d56da2ded3790f303f26e7b5277c196374339189c78662a21718a6654f7dac2ca33661682ad73d23010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xef3563085a8052db5d58387d42c534b90e155408d25773aed12aaf47d4fdd9426f91678359fd6a7b4fb19173c5ae99fc28b38436c3f1138fe0101ed065d6080c	1612536476000000	1613141276000000	1676213276000000	1770821276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	227
\\x0866c850b88c8092e311bd659e33865b70da66c023623b7a3eac912d1b4c8d47e623b1815c928158062129ad95bafb43fa2b61414548ecb75a7524de1cf712fa	\\x00800003e43ffe82da22d4d03fbc9a4abed5a80827feeef13b22c12b6b46222d94d0ef0ae6d972a3e4c1fe9225418ab1bdf63c1d222909c4f6c4d5e5e23de7738f4a7ca07d436f263c9a289c16567dffe4edd3d0e1200afb8ed91cf5d60ad774cd462173ad6e363f9883cfed127c56c36daa1cc9486148e40a5a39b9bd2ba53d7e4414cb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4f8f79d3116a45f8ea3bae9c4df04e89349fd1cab711d235500db1f54e86b5dfd4b5bde00f4052a24758ce0c076d9311dc186936e50851194f36f90ef0dc2a00	1640947976000000	1641552776000000	1704624776000000	1799232776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	228
\\x0c4ec3bc0d9aae1e13cb5d8fea1f317bb3e1d5047c6d41b421cb31766724c46af41b18ef2dd496e80e74b7cea826d2b88646cffef7fdcf01194118e7c565f792	\\x0080000397b5eed2601d0fa287ccf650c32d6c1e1329fa4fbdd23d452ed2c635f7be60b54ec01e97cc5a489dd032cca2fb53a43e4475c6a258370cc7be05e4d1f2c18dc28f25369d3981d0d06dcfe75ef491246ee6be23483e88c563fb28e10f45f174102c7b8e7ad336fdb35ba17793d2ec2180ddc4dc0abb70919462a6f57c7e7ba3db010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xffb2f83b15e84044d45cb99f4cbdf2ec4f649697f36c1484df78218f9093f863f76d428ab3f9d4cb6ef3181e9f9048c795a277a754f914703ee087b545c51a03	1633089476000000	1633694276000000	1696766276000000	1791374276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\x0f16583cbb7f87d5be79136dc07e372c158e39e243fed920e3739a3dad4f2740f2a8b37698db2c3049d7c9f9ee5eb003be7765ab6e1b2e251c942391199f71ed	\\x00800003a04a320d06f88062b5d295b29d0e1c0513a919ba168667265c1783b1689cbd7e64f26945be8c568f5afb9334d68e4c4fd49c7caf380da05682f2fc3f62493170c84d31aa8cfb55228289b9970a0975d786927516dc5b0c816fa5167ebe6dded7b47c1da836c61f6cf46d5424a3668f8d02d6d4df442058bbd331598d8ca04de9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x68b9334c77a0de2223d38847c5fdefe0d08f1cb01187999b4e5dfa6603f58746e709e869303aeed4c6539f73c9260d5e0466a0a6e9659d2ad07ed90d57725007	1641552476000000	1642157276000000	1705229276000000	1799837276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x16a2cf5907625df34155a5be6a10edfedbc8a9833402492025e56ae6678aa4934f7701f7aeafdfdb19d0fb4158870f1c242f10deeb36f3bec8fc9ae6da295393	\\x0080000399e5faaa059aa2fce8f0de798323528f7c1e0faad7b62989043fe3ffc81e44e7bfe6cf6a5b208c34326f9af834744bee7626b5ad7ac20640795e37c3b4ca005558542e94a6f29fa81ecd12c1b3d332d8695ab6f9427595890c8404fd32bb9c764178fc164e2da30cd18a24e5aedf5c92b7144a33e846d543800ffa557ca0dc49010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc5198d3017a9c9bac22e2cfa977fffa1cb8c01b44a423bc8f235fd08f65d69c85ab470b068ad8aedb29585430c76590fc05ffa7942b499cbfd496d3951bbe50b	1637925476000000	1638530276000000	1701602276000000	1796210276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	231
\\x174e6f345c87b732fda44a1cfeed71f1664ac1060aed272fda2dc6941bb9f0c5c59ddbcff3e59eac7176f47ab33abc9fb47b0525e01c703292c12865818a01df	\\x00800003d650935e0403b26890e611d9abf01ea5c211ccdb2ce9b1a4c94124a756c54486b837557895866eeea45870384743c614645d6e8f9f1661f2c5cf7e4e8d8aacff5245cbda6ae2f3f1e3679d5639bad2c41f8d4022d48c692077d2c26fc27532e5bdb3d66a21a8ed0cbf6395973530e38bc3ccc158f4949935c1b80b52956423d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb4036688af19778135dbce9b8c8fef463f63c8ae20855e826f9cbb5af03bbaaed0f0e022b1bbb4883e0c31228489434595457c6debc8e5d47d2aba35a49df500	1611327476000000	1611932276000000	1675004276000000	1769612276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	232
\\x19deaf07cd4831b31760c89460d01988b7a918103f2bbc2006ebfbf83686e16aca18d4ba93cf481c2625fe669c0edfad47a7ee6ee4b7b2f44d63a4323018e11c	\\x00800003d2d8dbacb39ac65424207d133f99dee16357d75e5d51c2f8d0be56b9767920d371879001577c91539d007f65cf248cd9728aa2a2165f4dc0060fd3879ff0dfa6ba51e8deab005f66786a4d2815d862ae19d7322e2d838d0edecd1f3be1460d5d6c1dea17e7b4a4ce0daea3e600b0d3a63b5b073b2d818e8d0e8fcea8745d9329010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7b3431203445d9e5b186ae06e49ef9f6b1599510ee4e5b7c6bd0518475a1bebe24d430c05a827354b87554485954fd2d0e7e4a80d86f68be8c2d78e9a61b010d	1617372476000000	1617977276000000	1681049276000000	1775657276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	233
\\x1c7ef78c5beb90f370587b85461f2f04459bc42b45cc50a6e4dd079c9de037977ea1fdd07f16aaeb23deea731be062ae763355947e517466a40a0c164edcc4dd	\\x00800003badea88acb62ddaf637e22b37d952692f199fae53807acebad4ca271490ac9725287437fe9e057377f0b4c0624a049bf2d7d61e9c8c0b288b5c9152748cc4703afa06bcbd480b738847a4475a6a7512851258662dc7a50f300b54fd47b456614e84de52addc707c8b1b92897249fd6cde9e836d2c6a889673698735d29361d2b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc5cb46bb25777e27213419724f134b414a616084092f5ae5823acdf1e2deec7a792f4a3df67565b19918533917aee5e5f8d8eaa05295825f2f00cfb0a32eec0c	1616163476000000	1616768276000000	1679840276000000	1774448276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	234
\\x1e66c42627c6acf6fff5eb19bb56f7d4415893ffe6488144f274f5dc07afe6fb8ed02023132042f4c50da306a1147934aac2ace1f26768e7b8a4862449c8461f	\\x00800003cabbfaf797888db83755bd51164d5d21dbb7cf05a8a64104e847a17d91409ee63326ac2ff39405c76928f1a5b5cf526b3f326328649f036fa65a027bfdaaa82bd2804cb63eb31acb42f0c38b46f9afa8d473fdaf1f22ea5fca49fd31db90f6c57c738ba849db65e377d65737bb84232a4a386f0802443b2272d719c2070f52ad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb58628e1917564cc937cb331dca83665882a7166a28f43f84aacfda5de209cff5d6ec408390b53139e23c1e1e62069c1136d5f3554b9897f739e0c2c055f8107	1636716476000000	1637321276000000	1700393276000000	1795001276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x206ecf2b1a8c13eaeab7f503e335becff336fc8d47d755cd48ab4967d2cd0e7dc892b6617aebc0625e688e86fc34b236a8add073318ca218567f8a33540e52c2	\\x00800003cda15779e898b2aac77d00eb82f0649b6a12b4753ef6f560f1a83125ab2fc326131cbb9b316ddd6b90f90c122cbd0dce0d1afa5b5ac9d16c581e392ccaaa554bc29f4bdb0bfdc32e3d9bca8bf802520dab11f660914637de24a10f398b0244f400e3268c0c1d8ece507850aa24c515175e66f2a5f280740d13a76efc08ac8179010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1344a9a1b63125eb68f012e222a7aac5de01430e139cdcb90e5bb57a97ac0e7612b779a5007e87d12969d24be3cf0caa29cbf192dad5ba5836a771f58b0d3709	1634298476000000	1634903276000000	1697975276000000	1792583276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	236
\\x21ea725c25aa0ae432b093ea0aedd8d9d060007e8e28e87bcde09a976146fd422678d039399116a4d3089423f893e16c23790f0b9da9ea9a628b488464e2d797	\\x00800003ab29a5765ee416d0ca8ee13058c35b55052809b24cb05d6c2266bffacdb7b4517cfe2cd145834413e9ede01a4e17f07f1de573852876f1b9b81cf9b0903675cc202e18bae38f012b5055a9d22d78eea4a78b2be67e96fdb0502fdcac4238fd3faa9a7989bbb601d2812d781eec466bf71e4171b8db86e046e84e6c1f89a409f3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8ae26f1b6f09b845f1858af3270eba868d8169fca3e2cc44c5eb4af823a3f0aebe302c1832099463feb6d9bb2e5c16aba1763dc2c9fee72164f1d0c31ce93d0a	1633693976000000	1634298776000000	1697370776000000	1791978776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	237
\\x2156b7c8ef0f39966db5bd39169f0cecc2de34835045dad36e0116782a33ca615aeda581777c3d5044d2e2ec17b2e41dec883ae8bea814b5f463dbb69f459e49	\\x00800003c79e196638eac23e4d49872d2943b055f97d9f550c946a8eeee1b827e6ea1f0449a32b2cb359052b9018a7c175a23990a05908b158ef0afa8e207ae05291193d4fbd3523ef7e04af441bd2011d70d053a17559dce3e66307808a9dcebddabfe3b30d31b1e86011eeca2970c9665e70ef5f123e85f8a08bf61387847fcc62babb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8038b09b0f16ffaa93bb421ed01d0ea66ce517da4af13869dd12d11f84d20701a4e6945a3b6b54478da3df91d797c058fdfae9c2ad8e2ed1209adb5029e4470b	1635507476000000	1636112276000000	1699184276000000	1793792276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	238
\\x21e61b5d26b667aab9d522c9c30e7024f0f7b9dfc7524db937582b244fad3835c74cc37dc97e8b3d9b6ca2b134979896ed6f1545efbade2d5ed0368ff38b1379	\\x00800003f2358f0dad25637fa236c9fa865dcfbb4e205e69a4d7fd6d368512207c221f2e9806855da159fa9f62aa055482c8db77c0d04909019dc4d2f69b4e1c0a36f993c26dbe23a4b879711bf7ef8166836faed0e6a8d50ece0edc9292a6fca8458e00d0f8192605e341606745fa25cea18fc1716d4da36a75dd87513a8f0537af46d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1b0957c6151cff78aaf448014b9d531e523d622b62001674ae3595da3f94242cf2b903163dbe5e686aa28991cda21c2a6540fdf643eb0e85f350f568274df50b	1630671476000000	1631276276000000	1694348276000000	1788956276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	239
\\x23baacec5a2413675619e77bc3bac2a74b3faf829121d7d82cc076e8ae3c5818969d61e59160e33adfcc5ad672881488b08ce93539a0bd2993ab24768a0bcade	\\x00800003ca473a15cd05e4f664f26c1d2b045d966b04cef0f4e80698d8cabf1fc34e9de6737b738c6938ab5373d4c9ced641426d5c745c5f11ac70a49c195a5fff982357890459e955f536c3d75dceeba70c6a308395f666528ce8a7ebc09c138225516fb7254f2c2c010aa3e648d95005a551991843c2f40f4309f85a980b055227e001010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd4e65b8e05c843e4ab4fec1b063404d6843fa60293c1a57deb332f093d15a2175d6fea320b5f77fc4929d65fca19c0d949ce25518ef01893e82cca5e959d7d00	1618581476000000	1619186276000000	1682258276000000	1776866276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	240
\\x2b664d7dc97403708bb98ed88f4f3414d9a9f068543d4849dad0f65c08ac7a7a9310f2fe09c4e89d3b81035151ed40d9f3ef2530008ac3607dfc23122a5de5db	\\x00800003c7de4cd875391a112ddda330c6b806ef295b124370758e23471fd7587eab2952269012a31bd50a5c17bdeca0790abdeba36bbd06d2719eee0351b1a440e39bec8a5053a64e12ccbae53f99f6bd8907dda7e755ddc6e0f9d84313ca6e53885e5c492639dd66b0907c4b9ac530b563582a627f51111d27c2251fd8a97302ae6f9b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x76fe9441832eb861b4ca84659a25da07b8226cd65e7a4c60f85c1bb860376df8bda394b0b8b3c8d17c52ba98c692f93f43bcfc237954c9cd2ea344db2b2def09	1618581476000000	1619186276000000	1682258276000000	1776866276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	241
\\x2cb2c65cec4ff976942ecf21f9c8077afc0228c67c52116dada25b8d7c10e840d09e701c3ff41cb719349e1f8518e339e275f3f8dad3587e2e7ca91bc770a13c	\\x00800003de22948acca91f99190a999a2f97dcbc037ba1665cd78cc8b4d6de76a5d88eb23fc2c17fbad2234e0e63d39b18c5f27af17e90b26e756977aeadadc5e967db6df293b65325abdbf74a82dd9b74eff50057bba96c8866f310f83c1c8aeaddf98a8a19bba0f48e13d12d83a8a63f51742e223f41832f65df05ea7e6a8cb3856b81010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x10cc01e0ea020d67d05ce8286b8e581de120ca0a7a65a2c3733d9ac32bc0db42a964f39a8fb0d70188205ac75dec0dace50d0a4f6dd9e9e5896fe659510d1808	1610118476000000	1610723276000000	1673795276000000	1768403276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	242
\\x2d2e279d90aa7499c60e4020f48e15661d503691ffd88f7433c1037400113e92dd2607f07747a27d193132191e76a05321c671c9e867f7a8946da6cd011e8ec5	\\x00800003c7929cec7745596871990b7b455142ed77d1018e383cf872bd00aee0fe4cced1b2706e423296821a87bbcd30542b2335d5d71f4ad7a594d4d48487f0146f628b0e128ee8de5ed393e1e6125a15e2c05de08ba1fd3f38e30a18c8938dfdb3fa4ae6dfaf1d352cd09345ae34465b31ac629a2e75b94571b581992c084fa75acb8b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x747d64698d8e6308aff607aab6e0e5b983525eaef430cf1cfbc01e31ce6967a06ed77d419a8f5f52e092f0e56b7c1d4264f414cc06fc25d8434873052d2df203	1611931976000000	1612536776000000	1675608776000000	1770216776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	243
\\x2e1242206229fb05b276ddb60ecc7ebb74010b2f2c5fe74f6c23bcb67ed3912e0d65e43e04a86c19062f5cde5d7fa60c9d889d670d1479d02e8fbaa42abdb0fd	\\x00800003b69c4d36b326381e0e85baabb6ece4cfc6e31c287bc014380de169740dcf0c21a45ca96ec7b999ea80ee8db60190abda4865044950a3e9ae2fc5bae74cb2eaabb721e032ca60122e13216bfce69afea4da94500c11b047fabe22cfe61742c3a39d68436c1e2fa728a5ce9dec38631f48eda457ac228766a1e8538fd4c3ccb751010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd923593a940bc613d71004ee3181164410b60432a53a336f24622679cf4cd9644447f4193acd6057711fa0ed6b77d25545b2306c3b06c04738b6873cc2ef8d0c	1637320976000000	1637925776000000	1700997776000000	1795605776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	244
\\x30321c240a52ae14426c474327db4dacdef46564a331e5a7c9abfdf482000543bb22b0d4df23825dd6091efd59237374f49993b5de19264fb44a0d4b3a257caf	\\x00800003a2b5cc4e2c6c61dcacf2717ec0ad27b2b22b28289383b9ca2f059711c7f75a3103c178e936edcdcb61107cd6806bef35e4b1e327c78bd48ddd43bd1899b8e0c4047caf3817b937241916517487a88948a54af00ba4b764b86f3d76a0ed1677a7ce3375beee0e3a2adc3d60de278156172a2acd4cf1ac84e4575b983249d10ab7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5b021791846903d49a0fd6757d567e3448ee5a70c1db615eabbe73f039e29174b31bc50403132c3c3b4ba745fe4cacda5fdbcd02c6ca2a5ca537f0a08fdbc105	1626439976000000	1627044776000000	1690116776000000	1784724776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x3176419ce145701e5131f67b6be136091cd42339693dfa36ff476534a3a717aa578ebd9ef7047494bcea062ee70321e35d7fa4a316f993dbe35e8d0cba81ed4b	\\x00800003bcd2ec0214068dd385de431897ccf9d1674b9cc47d543affe6f75944b6ab67091460afaa9b9f9db901a65f0b67d97dfa932937b4976f770c632eb379009ab65d93478f0c68e5fabe1a9a06b0ae7a76831ec33854b68527ca8cedb8678c32f6dbe65b9beacb1cbfd3ac9a07f07ea7c9e97479b7edb58314accfb69f9b5d339f13010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3e2d03f016d14d9663ca2296eab509f1512159dc916974e09fe5bf06831edc75abec50df7efa5e1de29422dd2a876a6e393e7efc800b50a4d514341548813403	1638529976000000	1639134776000000	1702206776000000	1796814776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	246
\\x39864bf77df44b3c999b07151dda4ad3b2357b624a59342425c3a14693b1120b06f6d4e671f7efbe6c3d7b14c289e5620393c1e2f03e233e8b49d4308548dee5	\\x00800003bcf8ece25ada6d33c5a6cfe76c92b7b5ad18d34669e971836eab077b7e7485f0c9484f33972972a773f4fcb1529dd05579e61362e3c8b1ef73a746faadde062dc87f3f8f947d5a3223839aaea2e24af59691309e0414e1eba38c91a80b56d652e286cc6c0965fec18fbe48c7503ccee66577bf7ce0989e31647ac04c151221eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa4012a8960fc446c19a05ee24e58538a9a69d8e10d2a91639222799f1852c9b2e10cdebd8a6c1c79ff8cdd8a10f35879869508bb555c89bb1248821f5c988600	1616767976000000	1617372776000000	1680444776000000	1775052776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	247
\\x3ffe8fe93f18217b1e0e238eb138673df22462d0cf5ab05ad7afe3f6d20d6ba82a5aa959dd4bb9d7bf3e344e81a19ce1c3274ddafb3d62b94d8e0a15504e8c22	\\x00800003db1d36b20d7a9ac506c50d18ba932e80605bf05426736bf27937ede36caa331422f1cfdba09931be56177fe38a83bdf9dcc370c20c1e87d2ec4337ef774f916f947c9f31bf64447b72f663175dee66fef5a3e79a4e560767be21610dcf651e4440bbebaaaa4016bcdc9193381fdcc0d25cad94b937afb94a39df66162df3583b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8576d91c96617c22dfd4acdd3aeff8e4f35044725c20f13490b6b7e41e49b0a1da2f96426ef12a37ba9f7ae4f2abcb3dbabb26a94e1029329e018bbac9d9a80e	1634902976000000	1635507776000000	1698579776000000	1793187776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	248
\\x4002d902e1116aab33f77d10ddf380c1d7d3d82d7e816bedee3c5d78e74de2c8125f561a5210ed208b6cdab2e2d17feaa3bcbd2170a2e89ce31862802395ce43	\\x00800003c8926427238390d46134e2c8f8bf410aa8d0daf722ae58c316cc156b56e15fefccf34d1859ad6801f5565ad728ce99ded426b6dc660645d96932c733834e0dc00a3b8ff27042aa81c1c25a69f1992851670395816c32ea40c5cc57bc511455e451e2a138a3d7ab3a09ce8e924ee3aa7f052a8e7427f94fcdb592a75f8643e8a1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfd42e48ecfcdb15d0405d5121449ebd039b92c211e9d81696b7cd60284b2c1b6eaffd7ad108e7250705b5c922dd466f445e6ce21e21a5c7b077bbb9dfacb100f	1627648976000000	1628253776000000	1691325776000000	1785933776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	249
\\x405e63ead8c66fc45a8baf06f2d10fc6e81c88a37eb36e15ce20aaa83a491278d7097c641d9a43549fb15573070ef51e359072d9bea6465df5812010fb669b0e	\\x00800003db0ec1c183df04bf3381e8272464c9a6257e5a832221dc3d645ee1f0b54881a40afa55016c849331df5447802c20c8681fcb20c0cb854a2397315bd58b9e2181753ad22476e8d15ddd6f10c870976647a302227c0deff8be046be1f566ca3cc9c69f30ef687fbb9963d78adb3d8ed16ab6fd6b7814151d8d0831395f979fd55f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x87c0b7c8fac8215e052bbedae0ec8c049586908c0edad77ce44f62c0d8b0e1c207678b2ccecfb619c0626c523e54d6b4dc4c2c16db1598f41cd4e1e0ef14af01	1614349976000000	1614954776000000	1678026776000000	1772634776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	250
\\x40c6640eaae9ea2cdd8d4be452b5474b9d05f83570b04be8e3214666b51bdeb2857435dbd1a3aed7d227c8e5b72bb39eab59c961ade4070e319b18d1e4927779	\\x00800003d1bd892fed52fc9e52dfc2db0475388ab49e485a72dd5a0f774609c02ee090c86a1dea2ef390cd7d80f401908ee65afd073910ba06b73c4e40ba3fad6a9af557ee6ef73effa464fff1af712ac36d504aabc969ac49bb7148a627dba732177a1f28ed289491ae36fad6bc91645341cbc5389c67d68fe6ca59d61679c8daf50f61010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2db808252fb69894a70f954dd488ba3bf9b5a03e9e3cc6989fb26214cb3ba6451c3d1c2cc07945ace7fd33a15f387ae3d980a3d3438261ce321312e3e9d1ba01	1636111976000000	1636716776000000	1699788776000000	1794396776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	251
\\x41ae15325768c765d7de868a2ab4e6b20bbe812ac301ccbf17c6c3973940e18a9b1ef5139d27e7518e020e9c240f1c7fb69dec14d511d16f5cd7c8bb60b26551	\\x00800003dec134943283d5a858bfd652b5dd72c2eb2f249c95b32c785ac223258386999306640bc7e0be8a4403d4e52874dbcddf8a954964cc46ef1531d51b36dd38e072ff3772cd6a8bc604c91e5342d4a66d7e71e15af92315cadae103d855a2acd810e4c068ac16d4e47ce9a445885734878d331b4f1e58a0f378b34eb93c3044f453010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x09f962e41945ed2152bfdf19c670e4a45913362f9424fdf8f54cd385fc1eaa5f80004ccaa576df3bd75cb56effb1233a68d54402f1ffede48d0859e25d326300	1617976976000000	1618581776000000	1681653776000000	1776261776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	252
\\x419e8be6283c995686d14b6f2102295e4db4c7769d9efb9eac99ab7292fe0611428bb988762a311efe3625d983f6fa408c45687596b15073fb695e68ed03fd2d	\\x00800003d57df3732ca226cfd495b97ac3e586d2deb7c2a1d96cd7c44f44974dfb4acfdf6724d646769fb9db3c831a1f4995b6d53e7f671f25100cfb8f4942b960aa8b36bcfc4c7bf6977616930a1065364fb588624e6593b757fd529a4811f421b80a78961b984a03d30f589a828936fbe3b8ff6400a7a5892de33d63a810fcee31d611010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x78fcb6331902b5fa90319d0420fa625f818bfd5eee51452d64124b361e4be95de622bf17c538d057dac07a7cdf41d40fcb8e890ec6d7590b73a949200aef5e02	1611931976000000	1612536776000000	1675608776000000	1770216776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	253
\\x445618f87fb184293eb0682976cf922bb2f1a2fe13f8f0e61718a0248f3e66e8ebf914a0743dfe24947df4240588cafc34e8a51c099cd69402dd5db309834e9f	\\x00800003d90920e62d64028a1675a264800af4ab210b78634962daaabae9cab7a13100d5cc32269fe73a507f9b06e85ad2bdde1d951d26e582cf291d327d6ab68c170eff67c795f0e0b88d5c32bf26d9d389ffb84fcee34e7668cd01b82eb696746c9f0447680164d9640583d38cf0150fd9aad6b90f18291b5076f47e69f254ed7a8e39010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe17353d4c3db2d76c675c3e5be2010697db3129dbdb807978b87f9088cacf6889baed8e189c066e6d826c56aff1ec47a631f4936aefa5f4f601f65422b454c0c	1636716476000000	1637321276000000	1700393276000000	1795001276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x44529d98b74b94f551e3e0cbf2e4e7916a6b3bac1239635b413fad74d659aa0f74620da89ff60c12fbe6930310b58c1e167ca273acdcdc8b692bd0def27fc79c	\\x00800003adc98f76fdfefb922f5070eba86c9db5ad2ed6a51b1e282f6026718432fb5af30f4a4e038c35bbee529b76b83e9c7901d275183f88f8084b208aa9acde7c6f3aaa3cc8ba952b166bf83bd2de5d05c2ca6b8999458998c8ea6450ecdf58a258058d396df25143f68de3ed4a2b94294f112bd3a0407d7a6dd9f21e7730e95bdb63010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6322e1e3f1cdc9b6678167cf4e34bc6ba10e7c76432c92d64ab34f19f6aeda5ff0e82d62c547f5a569820e1efddb49d408191d3c65ecdac99852f04e5dd93e00	1611327476000000	1611932276000000	1675004276000000	1769612276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	255
\\x459e0b544d96f93c463678f449472f4080b89b4206ad8aba7ee97cf5290a29120b4a561e1f57a5c2efc41f048133b86518ce52cc6668077a4256bebd248c5184	\\x00800003d13fae88e0fd5894fe0641cc33ab378ab579f37bd51fbf1ee18f3180023cb15ddc137fb086ccd27f1a4fe08da976940cf6f3451a825d87eb6a4b5f8eb9bb3ec07c589e73d3429a6aba2417816842191b8e14d77811772cd0dd350f4c096129014088c18d752c60832a00a90da190654bb58be43dfd26345c6303c8bce0e503f1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xaa75cfbaef77030e49abd8a312f30861ab1ecf7392966864e2b6bb5ce122e53713e051ebc412596c135a50e0d0abe031b09d775e696d953ee58b52a6f1c98a0f	1613745476000000	1614350276000000	1677422276000000	1772030276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	256
\\x47c62d17ea83440b5a7f73d6750bc20e1b63536db4b7b4f4c4997c1cef008eee039c5e49e0aa4035721bb80103f13d3b89e3e851546a16eba58df6edc8036a03	\\x00800003ae4526da7fbe11d5a76441500afebedbf88a9f5f886a79c773a6e4a53189150138e2e43a77712a0b23b8314b77100c606590efb6269e24759b59d0cd763c411a9c8ee9ef7d9208e8c6cee61d14e75feb5948c1422eba10c1d8fb4e25b1e26a421ffdfd8e51ab0581474bb2d276e3ec988e9fcd3afd7d324cd4981d719445350d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0fd774ae8423c6fe88f0c3cc18fb98a80ea1baee7f8c962aad11ee37fde07c5e439e256cfacc25b96ee98263d2f1a0ba1687e99e9fa70710fad274c96a7ab200	1615558976000000	1616163776000000	1679235776000000	1773843776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	257
\\x4a6e4e9d7d3e49f9918a6ec968e72b06b25ba0014fc411cd5ecaaaf9a32b6a76a740ec1c71ae120d25bdfad942d05bc24934a0501c909aa659ae15e39c7b9fab	\\x00800003cece65bc61e3d6156876b553e1d449de51fee9adcc7ae2ba13ef6edc33e4ab51a3fe3736aa92fd16ddf6f850966c9647104c94bc7280a68e7f0585def18ef34a63b639633049ba927a104db10c77ae28e1944c2fb1d523ca020bd1ea6ca6b6719e6756f271b2e445ff9115fec7f1906426ebe5bf3cebbcba934ca21845083405010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x62bb7593f049b8fd49f45a0c90c86e963b82fcf5753813dec904a7a1f53d95897862ed7b89176a411d430e7156d49e0d435feb97bdb54e359ec01770251ea600	1610722976000000	1611327776000000	1674399776000000	1769007776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x4f369a7d002d95697fc9b926d2b826e1d19cc255f6ab058f360388c8b5972da5a221c1bf992956275c8731529ec7d7d65613b24dd3aaac7b709c46ff8a9bf705	\\x00800003e8f1eef8aa32fc25ab9689b7b4c553c3521e21b33fa00a6543cf60c98de7f35d87a7310f6b68fd561549767e2c53fed0d2d2646716734030adb6799dde3dbf58c37fcd2b9336ca5f04a72d41eb3d804333736dd5869f358df85b79a304b183ffdcf7c4bb34d715a37af97ec73a2d3c47b8fabba5f78f96d31de997b191435f91010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbe6a502aa2a4dfaa87973f1b69ee4fed1c9cd0b9b34d118cb8e1a80d070d34d73b96e08e88e92b2d184c168a821ae0a36986914ca03f75739ca56e2639f0250f	1631880476000000	1632485276000000	1695557276000000	1790165276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	259
\\x52ba3170f9c5bd03a40160cf148817e837d96d37cc6669c6740f7e71e8ba322fc738455d59bb96d12c8ef5aa720575244b2c3f9eaba801e87f2612a075e3451b	\\x00800003c7cccf75d495e52b74e1248a236555388acfa0df4546093a2629af8822350444a3194cfefa55fbe5a1fa5914e2163b60c33b746ae14ab456fcca6390e6b99699f5b7310d1b3ee89f0b5e4edb067a0953830d87a3a9df12be55117198807dccd9e09a1cd8e58dec3afa889206887f5d931b271e136ab7ebb29c6c20f15faeca09010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa4ce93b5c80d75060f2328a5d0bc6374188ce2ff231336dbcdd799e0e9ec97a660476dd8a0d5c0b27789a22d27a34deb9ed1f0c8641ddc572c0999dddee25b05	1638529976000000	1639134776000000	1702206776000000	1796814776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	260
\\x53fae88f4e381e7036d921ba9477f8ce83bf78f70d805d2d0bdc433197b1530c2a05e9e451c78ba75b68bc799ba7fdac61c57f98f96f791408e5ec01878344f1	\\x00800003b0d045d319fe9766447a8eb716621d4822f4647fc04ee44a59f41f66be1e157b479cac8c42afb594286ffc693b6fe190f7d999c358b5b49ab02f383358affac90d2248c0cc491d64fc3a49ddc7378778ec7349ca3f0ebe5d2733740cb1c606d05e7882b2c264ff1eac0b99cd16949b07f52df67210bd911cc23a9cf055e2d939010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7e7fe7f9426f59f4cdd35f89ab7ec92f4c2c542419c3c1a1e1cbe2fb9e6d8d212c41823d6fc7b3ef3ac12ea774976f377f09204433ab5f4531ad21b917c93004	1617976976000000	1618581776000000	1681653776000000	1776261776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	261
\\x56263bdcda3579046c5f6976d3fd748d94617e68ab9eda2515ebf4eac34203906e4bcbbe34101e82dc7456d5238e3015f6ce2c2705c5244951efb36fea190202	\\x00800003c2df35ec4581fb44315cda1fa0b0df886963aa1531adfe66c53b38e5a589b9926ad46a7f98a143137593ff8386ae95eb6c8c59b8641066a369b4ad77f459bde598e8735b3ffbee19cac259e74cf88d4133b3caa054714dcab2f95cd8baf44f47d1759bf72112a3d3e18dba61f5fbedbbd5071d2139780f7bd41a7a963bd2aa47010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9cf8873dec7ff21bb401f1b4899854e0d1f2bc7c03095c731401660a837fa47c63626f32923f181402dcdb81d7a9ddd88f490265fdda1800aa70207b78032804	1635507476000000	1636112276000000	1699184276000000	1793792276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x589a7c122a8b4abc34131ee0b21ca9766802ef7085109f04d103224fa0b082532a059db29362573c66439f4d9fa92dec50248e7b365297684015d64a705e6c61	\\x00800003cbc41a6bedddd98802f12c2777e69b633329305d7f99dfe85bee7c7064820b7ef9327f818220139781570f1e0b7a91e3d3758c689333b0050047ea8cc929fc5538d771afa278ee3aa9c36633a26b74808273c2d4ac08dead439b41dfea595c6e43b2a5e4e9f0931701a15b4dc3a03a15d243c3499bb8075adcdd8d8596cd654d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4baa3063ddb85708bdcf28ec9352d999737eb5b8f986e684f9ccff0806494ca49cb25740bb9381106207e2cef5fb40c55ebf1741af12c42d0d2a79f5b69dc302	1639134476000000	1639739276000000	1702811276000000	1797419276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	263
\\x58ce4b060f8ef74a715683b51a433f0f632c5e908f20f58f348aaa83916d5cc48cf7acf8b77e0afa15d05182a7a2333b4f091ea9321afa03d956382eb3244d51	\\x00800003e05d6a8f487a1ba5766436f4b4959cb3a3b8c6291c3109ea317d9344c59862b4f95ccd8b5107da7a0a2813c46428a27ef421dc3baba67703abe9a662ef658b67a9db79e4885fdb9190c43f591be54bdda4900ac3059daeba11573eb857c9238471029b21e7261e02a9e1389d626a6de1446b101a5b16398282ad31b87ac38ffd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4a6d10163142fa5d8dd6aa92476f9cde78019d00248ec06032aad1ba25f306fc2897c8da04a7cab771458ed5cbcd9670d8b8a1899868020559e0e5c1cf5c6904	1613140976000000	1613745776000000	1676817776000000	1771425776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	264
\\x5daed3e1d80c47941774f821ec9d3a7c57ee9efb205f13d886ae28e30ff113e60c21e0a0391cb265989e8697a091737789f35129e002ee79b328510578172588	\\x00800003d61a9c6d3bde8a494c59b97b143866b0db963c332360306f18941dbcf16849f0919f677b09928a1875a087b6c5862ba3c6041dfedd6fa3312ccc311f19b6c854babf6aee4702124b251412df81686f7469f4010a003b67523270a831b3f537269f0cf7c8d937f34ba210fd4ce9528437e73d0ee0205e6eede962cb03d2ced609010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7acd26d778b00842beffe2e49150210a29350b514dfc8a0667b614d6b45978fc291a6d00b05a66180be26a31d084e4b3347e12251cd0505c14c0076693bc3f0c	1630671476000000	1631276276000000	1694348276000000	1788956276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x667eaaa9500cc265419f512ba9b50bfa292c97a2ed54ef032319b4fde59f33326853fcecf162ef5061c2f316df1b41d9d6e5b46f1a8626aadd610925c4c77bbc	\\x00800003bffe04f0b2e927c347dcb128c6efea0144e90379f52aef8afa34e00cb15bd6ab0a7c87da1a2c91dcae86c5f2dfd6edfd1c03bd142afcf92c41ab940944fd0fe7b8e2ff48dfe259ca157d4036b5c6927ee12c35fa68aa6b942ef04461b2074d6a3ec1f7cf7948d44b5186fab8999ea7d9c5a40f71ba1db43f7b14319bd295a385010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xde1530b5dbd75230f0d4d54e7cb8870fd4a70457911c16a6dedd539991c0368e1d0cf5ca7e0e107cc0d6f2671ede834df5ec20fc5e9ecbafe4d6c9ef3dcbc60c	1626439976000000	1627044776000000	1690116776000000	1784724776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x67b2965dda772759422b8340baf2b09471843d760e3339e62e00f5af8dfcf17fb5a50f27402a684babc5b8603a0da0524de7b8ff02448b1920033d3e13240417	\\x00800003ce377050bc80ccb4662cb61e6f4c4f6a3c6601191323ee54ce39d1917b0da5df08a318cc72ee30adaccb225dcdd743cd86e5cbd440abbb371330f3ae5253ab84d40cd86b511503ae3806201e2a2dee4806dadb14f879546e3331d27c2d7e6935f7a8bd05348dc0fcc376c2a983a099c02cb509592da7cf92e31392f26e6d478d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf7ef94ed1ddfc659b43417cbf6c948486a55463dfd0dd6096278d8f11c86566d85944771e43322d85b9c6d07f0af4199e6c5be3684063ec5c5b85bc537631c09	1634902976000000	1635507776000000	1698579776000000	1793187776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	267
\\x686efd703dd045d18b63b6f0f9feafde58b59b508b3a023c44abecd8b6bc8d448816b0daf5203c47d2f3004e689d2abea46f07ff73799fd9d5ecf3077c021350	\\x00800003b8afd1e0b1ce41c167e018e5151356e57bd0492c5e02d0b67d8037bcffa5e97061ca1ef9599bb24838770ad96bc96bb9094b73159b0c2c0d25a6bed5d43bf4670d38535f3bca82a6595749234a3e6a1024c2c1093a4d236ba2b76d7371e4c2389527bd6fd1e9262467a13a15c264f5c96a8fcb4eb1d2732d19939e1f51fdc6f1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xea1f525c582092dc070fe223fc8abe8f61788be09a69fa37d5a2b1687b769329d14021ab66e20472d44bf23a633fe7af062186ce5594bce3296ed255dcc9a304	1620999476000000	1621604276000000	1684676276000000	1779284276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x683e9d6c92cdd748037de9b4c40018eb854fa20befc6d44924a4ee5e866becd89062f53c4ee1695b6c857958b79182d42059bf952ee8424a7df9c5448257ae76	\\x00800003aa87791beeab4cd49de171c878e70e2cf077a6ce380edd4a826b844420997696b7deb6e6eedbd7a88d4ccf3c10231bbeffea77a86bdf276eff3bd17ae573baf9f636d9e2ac81ee6ff93cdf92a5d8cbbca0d4e0e2ff2a17127f0667c99a84b7c774336f0486dfd586816970833869d9586c4c28f021d915ba24915cac70680703010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x25c3cda30b3ceccd20dbe68d23981c8cef10836d39071c67459ae9232fef6baa231dde894403f48835605864e7da6fb7f28f5fe7ddb9404bc4cab156739b1a07	1610118476000000	1610723276000000	1673795276000000	1768403276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	269
\\x6a7ec76c06b4c3cdf262dc43dbc0500dade472985a99b4931ec62c4039f0bae69381338f7f09179c41ece351bf8100c754320f8411aabdf8fdc403a4f7f51c2d	\\x00800003d3335a7ace8701067be2fef6d3311745b01b10d8f1d8ba23a13b4c3b862d80deccb63795bc4ce262bd7889c9a82d28edcc69767f4bbd17be27a84d543c10341556449a66da39cdce10977194afff3d54e6d741b5565c35ae5248550b9181d862320fd832038ef31e496031bfc02c3f15f8436431b00feee4941d00090148c0d5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6ed0feefd3651f1fc983e8fdd0e77c372d178b310a142c4ce8eb3829078cd1e698171e940896bb10e30a930e3c3787df2d34d96d72aa14df62c155506f0cac04	1615558976000000	1616163776000000	1679235776000000	1773843776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	270
\\x6bda401cb3fd2b8d5006875ee061722fc128289785936a3429bc691fcb510b38218214da50b63fc6c239a989c1b55d2a25dabf65505d35f9ddc30f6de939af76	\\x008000039d838d55d2d307ccc61eae8dadb368b6a3e3ce416f81418b5865693a1ba18c0dd4abd31d995463c592b4208e800f70ae416fa4913d7c37ae69231ea6a911290e0e4b40ed887e8778135c67fbc188df218d5ef30c8956b61eeeed7380d076d8674db9376d275cbdf5465a60619fe7afc3d8c74a9adc27443c8ddf2e0af70c7f75010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xacefd44711c78df580f489b2edea9e01e85a28ef4a268f3987d379cf41fab8f55580e7f287c2800c9507b3d9111b3e895dbc71fecd5f54e1f16e40bd80523307	1623417476000000	1624022276000000	1687094276000000	1781702276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	271
\\x6e1ad9a5f7ec7124c9e361c1054e5e7d7ad2972118d5d7da07f38f9cd5a33da4085faf5d9ea5ee42b7c0da095faae3b45139db5e7443e80be7ff9c6c65f1b651	\\x00800003b199a2a427d2a015c4c043face151f6b3b7d7b278c30bd76e7a8228fafc824ec0ce0da1376748042d507d632f8b863b0ca37f71e17dc0a1ea3a91f282c8a191b4fe5ba6ae0ca43a07f9be97092087b9f3b8797ad0d84b365c7519365a4fa54417231126adb9a0c85e36caab902dafe592204ed2acdd89582c2850a8074cd5de7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd0bb583aad4d544c92706f87f263995a1e547837b59a349481e238a83f704ff31b6f1cbe4a58bd49e2e70cc7b6647d271373ee00aba547dd585eaed61533cb02	1616163476000000	1616768276000000	1679840276000000	1774448276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	272
\\x70deebe506428c587871df34487d68dbc860f3b2dda522518027d101baeb18d52231b39e6489cc4cbf7095528c66fc23759e98b401bd94d1fd2393d0867db10a	\\x00800003b0b7da49060f6646362840a7aa6142b83964a38c744b30e556b96d4a66e136e44c324932959e6705710f061b22f638a311c4c84774b8814f30c8f3ce87978aa9ab6490e803a3914c3ee599bdde4040415659bf640024e79a087db6948e4fd2544b2949a8a906a5d9a6f7a0fc6628295e605234e009b239ff36188de030df0a65010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x46efb8e90adb0a662d1a4a6185a3dfc6fbf8a33828fd446d349eb53a4ea1e651ee838b642343414191c3d3906b42ef7cd8409242701c6931143501cd0174a606	1639738976000000	1640343776000000	1703415776000000	1798023776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	273
\\x713a722831f1e51286572f9a1088a880c9d8ebde8d68b340c4e38ce91d502bdf965ed3fbbf84f53cb669dc2112e54bf360c992662c5491c712d045ce4b921f83	\\x00800003bb69ba11c179185edbdfc4bf407081dd6d8dc763040ff0d5626509efa946b5c3886392dd76f02e1a36ae69d8f11e47845ce633257175bc729dd74345f7847ce0f6b525da00eb3e423e63bc2c5ed0c01471f2b5d12f8c33f7666a9978c976fde8d08d87a8c0e681e3e756f7fc95156da0b1cdfa689678de6deaa35deb6f8cf02b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xedc771360cee74bb0d897da2d1bc106d6d125828b961d34f7fda01d8b96741b4008b74fc82d98357aba08a4ad4adcc228ecf6f8456fdd462faaf78977b0dec02	1617976976000000	1618581776000000	1681653776000000	1776261776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	274
\\x76a65f915abe6d8a28785bf229a1fa2c2d1dbef45349654e9eab5fa63871ce000e133bf72f052a0c0e1ba8a0c812f3c6a5d288db4622e7e8e170459308788d2f	\\x00800003b10b8fd2384d8bf0d2c304674d9d0f99d0893948a7fcc357eaf7f4e8c18826db33ed96731a82148b30fe0220a2b5982997ba49d1c8a25ce08939915c4f20e7ea1294613db5bef78112a6fc454d6fcb3c30c961239818ff2710f13d10b541846cb0fc65025c7cfe1b9c47515c224982328e234b3e2f6bee12ec2db0679eb9a45b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5e6cb7a623f72d03a5c342a87a06845a0dffb702ce838ccade695ef73f33f11e7a17f0019be3fff55910ed426ed1857f8a3d8fd643ff9c2df3c009bbf67c340e	1633693976000000	1634298776000000	1697370776000000	1791978776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	275
\\x7b5ee12ca64c5ebe55f779bd4fb49ba456127c3472f19e39d11b1e420caa3416111cf38aad7799339a876d4f630f127f820db6d58a36cde3800f7522fa434f12	\\x0080000391d10593bc01a62c3003aa3d3895987577dbb49aa2f006d26f22cfbc73143d901b6b4863fd399f7e8dac3ac155bd7fb23ac0117a519b283c85180ad95613f4fc729608957e154030e71621fc07d6e6de4831aecf248824a182894eed45037b8a8c6500345fec60d6319fa29377fa584b2abdf3a78e2b71d1488616b39ef6b6db010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd01433f1c92dc41980d9800681f1e0c767f2ba60a31c7bf126891214085f81443910c4c227000e63be52b67e1d2ef0b5682935a01df66e7febf72fa851ad980d	1628253476000000	1628858276000000	1691930276000000	1786538276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	276
\\x7e8ec25d26001db24f772ac6e6ac944688385ff859edfe575448878c3e9a7c83469b583c2724e097cb94ecfb34e67699ec33c430c15c1c5764916ca4a7dac82d	\\x00800003f070d1a4b47c89876a89f8cc3d7d2f3fe424c854cc6487e3b57bc6cf28a4df3eec4528b99378f25ca15a9cd11c4f04a7219f2e598f0676302854eabbbb47f53f7dab03931cd0074df232b9c672026383e28c7c1a351304602d6f0b0790aa035185b66135c25ea0c3db8d67c380b54d0722694a06b301506cfcecb1f04ec538a5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf645aac9ce2415953580fe760b03dbc22f09712bbd418dcafc818ad5d98e575116b0c4d708246f708f0e56e0e4e3c81085fab2bea71e68d5a9fb5f983e1ac20f	1631275976000000	1631880776000000	1694952776000000	1789560776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	277
\\x81faff6ff219491a3d56e98ab5d2454cf8793389fbc2bfbd72496dac2e5fd9f1af88c3a0839b8f554b435a55cc07236fd367b2ae634f09f15cf19d2b1b8d5144	\\x00800003cb0bb9ee9becc1221f82a5da7579ab4e9d0c3028ce6392eaf9b41da8c2565ca1c0c111ec115c723d6eed10afad938fc75bfb6eb5d2fee11ead39e2ca823e659b45dcb91230984be8560a47bb9ecc96aedafd8c8c3862dfecdb9ccdbb343f5c22aa0d3fb74e65822a5f5c5b8a8b407a0f9ff6e7e0977cf4c28e32a0e15caa7c53010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x78c4e0397ad6709eb5e4eb9a3fe6060f356a0986603cb6d7377861dd33e289cae85e609664d97c05cac8658a9c48836972be05dfa407fdaf12733ad6ec52ed0a	1634902976000000	1635507776000000	1698579776000000	1793187776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	278
\\x84def9a8bdd2eeadd002bc112aa3cdd200e2283c5916836a1f597f3e5a0614bfabfd90cc3510ee43ba887202364e06e86b7aa12b0d3094eb94cefb9c33f8df66	\\x00800003bc551049a0fd5f1f233361ba8701f3be6048169447ef71e51efe77d39ee4f3a8969bf45ad9b2e783107f6a9590c5079129b574eb77d2a4958e7a29a4621e7e624d83b196996d29d5a5dc03864fdbb6041b62911216c732c793ba37a84f97e35f76f7ac0f1777171e5bd0d6083039ca7763bf679aa3efbc7f835684321a72b4d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x065eb19c2f98a0db1d4effd1cb5d9d9b06b835af2c12bf217c8755fb77f2c10db3ab891da2f330d50847974d338acc4a0b856b454cbd6ac2cb6b3bcc7ffbf40e	1631275976000000	1631880776000000	1694952776000000	1789560776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	279
\\x8ef68584dbefa77a97bddb0ab522f46ed6c282604081ee3e41eb38a6e747ef606e96779a40f2f1f3beddb42ceb3d94329d23cddd74b89c9a051be28072767b97	\\x00800003f3559d3eaaf68f615b65ff7af8b2d3c7dd44df8492ef767e8b57921963f82d91b43fcd125bfdf55556d883770d559d9658dc4d9c63b24de40000ceb34baf053fe9092a4cd64114485fd74e9348901aca004cdb8e65ab414905e35b7b82710da7006c064a9f645312af7a28e7cef145d806ae10028c64965b0632f4ef05d2caed010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x50894cf3b5e9f9bc30f60f816905284faec564488a15aa1a3005c275c94014e5c893526f8cf433bb184b027d42ba29a0207f4e28604225e563341816a559eb00	1627044476000000	1627649276000000	1690721276000000	1785329276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	280
\\x904ae42d0ef3d59bd702ee3a03ed58f28a706fe29643cc879f636e34ec9bc9ad38caa6cc8a87ebf16e57c2a34128c1ed2e8e4756f4ae99b4b132149b319885f1	\\x00800003b935106a17c2117b47ae4f7612fae35ba5210675ed3dea51748a2066c47a58ee2b103926b15111be30152088576e9d339e34b97ecb930ce25ca36cb7c4f47e01d5d11919345b67b639c2c609e47be88469b99acda84e0fb617266239ab32989fcc0cd20a074de6ecf8a1bc892cd8cc9c22daf6585f5e4525fe3410a0f41b4f21010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0641d2a84b6a152350c0d47ba850de37f8f64bd13be587b586f5c6a27b844045a71774bed303c0e2b8ec18b0c30f0cbe418e2a4644d56d5fa014d53e512e140c	1617372476000000	1617977276000000	1681049276000000	1775657276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	281
\\x94323e84ee19fc36892516733e3fa8c0ed62184c49ab570c1afef179bf8e5081bda81a32f361038f707d4b2fc163545037e1c2171d7778183a1ca9c6910a6654	\\x00800003b08a275755d948ce61a729a8f832f78d62684e7a484b7a3a4d3f7be8a82ca01fd8a2fbf2fca5fe4b946d42771096f8ef5646a3df727ed199ff9b9e24241dabdd685c875f7ed1900b0a6d5db6f780a24beeba8c5d171d33f39fe14bbe2413acefc794b66340b12246e9a925dfa71f78c8ab6501336aebc124be9b4a80efa2549b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa713433cd45c8520dbcb6df3c38fc48d60289ba089dc07f52d349a2b56bf712684f584d3ca874e9294184ce86df07c5b155d2e40326ddc185c63aa5d0ca1ce06	1620394976000000	1620999776000000	1684071776000000	1778679776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	282
\\x97265524bf69e8194d3c785d93a1af243e834173bb06cc772b562f6743ad9c806123aba828ff9a93f84a479870f36cf291e35cf940e63ad4f089b6a3b182dc13	\\x00800003b236ef7514aa0f1da4e34ee9c60a1e185562dcdd056a2ce2a04e01e0c1c3bb71489bf599616f5b207a6381179618c726e8bc6aa5ce25e554521e64fbe4794d8019b9bf078fb05e02e09360305a749dd557f353d42e270c69d2c8faeb77d95a51d5bb9ca5684197cf627a1e0c5de630c087d6680357e28cd5c29c366f94c37217010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6fe275c2a10e8b03b083e9c41fb71259eabc7259ad82aefc1d36355318d55cc95b2d31a5ab269350e10b1b22c93d071e64bfa799c6e053a7425f6e1db1694e08	1630066976000000	1630671776000000	1693743776000000	1788351776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	283
\\x9b7a65784b8bde18eccabd3b40fec74949a049394266026940d3be69059ed89b999ceb0067c2d09aa2c171633cab388f5f96dc7784f4dfc12ad825e723ef966e	\\x00800003c206361144d4388f017a264f86d988d8efad9fd19fc2f3c142f0f76e0cababae495b8ea383f12f3a3a9b5a3096e434af01767e1211fe531c742c90b85510c5e0d6b07421c66ddaea944a2f75ba3a38affc2ed2116c5be4c974bc799d7f712859de56dd18148b67de21d0ef0cd1b4227ae7ef462dad05d6b8c512c9bc5d03e3a9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x20e7f40bc831f1ea2fa87693479e26d7f9455259101e02feea426569e89af80e3ace9121382e14f6aaf644da888de8bfd574a5eb5e634c533d819b08a81ceb0f	1616767976000000	1617372776000000	1680444776000000	1775052776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	284
\\x9c9a16e2dc4772abaa0bc42b82c5306ad8607f9947838c94a6a885629310f8b118a517a0004a18b43e3966764c5ee731c3b0af0479d45a5659b510ae698c0982	\\x00800003e12ce6d877f91c53c0e4e309864897021878d2591d53bf9c1d6a27cb090acab2bef0cb76155aae2dad5344a8bc0d30b57e2ebf7857ccbc70f089fb0593ac1591d7ba9ace9a7b87e9f4402aa596d943d4075e4ff52a20c1cc580ea1f1cae64e744212b54e95c1f5bc0821d5a6d436a9c4c5271018ce65b246abce893f0aa232a3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbeee0005424adbb47de271bbca5604245ec7f6fb3911b1d46033f6827975ae2302f2ca616722dead9c9f058b4cf8772c1537f9ee111198561bdf7456c43cbb01	1613745476000000	1614350276000000	1677422276000000	1772030276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	285
\\x9fca8e14e72e93f6d208b45329f59270230f7544e5ce6794e42bf0dc5c19107cfc14d47a9a54a540aad6d6eb4ed13a798be502b2c33efbea7ad6d4e1a7be7117	\\x00800003c6b3ca5c18ff1eb45012003cedf24110ed704e529865031e551296a683b7e2e5811f6c9a70e9424199bff0d59e0ddebc9e471016f0b7f76f0ae36a6c5f1a0f5c815469b504b4147c9df05549dcddad066fbb3e8714ba9b52cde04f57a96c4d9dd336f15a572cba4331adb53ac6053aafefd34a11a81e673caf2f5a8e1d39468f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0dad85b9f3b936883a7079fda1da8054e0336a46a8b0faab4fd6996cab92b5c16290a63be61cf3494cfcf508f740a340c4debe3af8f49f9cfd0826fda1105003	1618581476000000	1619186276000000	1682258276000000	1776866276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xa05af301a0dc6f5ea655837e9bc675d150db3973f96d44ba12221eb47e0059d65aac194aa466c9d71c72505f175773e35aebb09d5bc60ebb2c362bf482f52a95	\\x00800003ba188ed02f0eac6c6113ba765dc0da04ed34a96acb81cb01fa81e8100a2692d556dc4c5e1b05e261b48ff962e4f519922b96a3d4bf1758c81536484804550c50321db85e02dbff13fbe0129ca801938b43732eba71579f3af772b667eb0a3f9e59839b5e26547c794ae10a924dc4ca4604abe744e2c16b0433118880b9c5e567010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6be98445c8a36427cd542812fda3503e1a267bbf986dad859f111d719f3d3d74902894baf59dd9a5edb3a803af18efcb97528762c946fc43480ef7a63e5de402	1630066976000000	1630671776000000	1693743776000000	1788351776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	287
\\xa3de4bb3b716f9534eb0932942ea34532c30c2e16878591cdcdc377095611fc50c85e9881dff99df380b6fbe839300c7d7db4092fc272bf6e54a30951d9eeb0d	\\x00800003a5117fd9b99819c6db759f19128d3e2f85527618eb37be6712f15773259d7e50a98922d5c7ea10e5879ef85342c1a87357a24b1303521ab3142aaafec02effa3877d2bf6b36c07a0977340ae1c49fb3191f81cd28f46b3e4bd433c973738abaf51c47afff7d3b6cd609a3a531bf3f2ff273b4f031750febcef7624d08c6f839f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xee450848c00f3994237274fe670270e5416b527178712e5d718380c50dc2e89ff068beb6e536265c9629caf35fd5a896f5101873c2fae95ca7915d763d25350c	1640343476000000	1640948276000000	1704020276000000	1798628276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	288
\\xa466de3c346dbc2713350c2777ce9b5bfe8330ae595f9771a6f62f36765a612a9c2c2ecab71ec6e6ee4cb1fa75be2fb56400a709b89409f66b1839700047cb8f	\\x00800003fa1e1116dc8c63edc236be3e3ec7317cf3b0a6eaa6fa914740d840e5f0c2c15ad3585c3911b0e240b8351a0b40ce715240f0f3b097a4e202201324e8d6a2769e66b7c72646dffe4a2963ef973fd4916283d94a47add0f31fd08567c71266cd6783e81a9de8280df25e69b0f58096aadf3154f720cc19223377e5060985593867010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe22fac101c0d6b8df1b8e48b5ca02df44490e8fd9fb4ba51c7545b6eb2b50114a4876cc9f609c42767bcc9754d1c9ce7404349ad55c834a34bc526fe6c2e8904	1622208476000000	1622813276000000	1685885276000000	1780493276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	289
\\xa5ba968293af9c22999433862e0ca3d0c21c053dbd94ac466fd60a517fed7f3fde59fa6abb0b30e730aa4e669fbf7b519e38c9fa38bac8ceb34a4b8f43c7414d	\\x00800003cd587bb0679ba2b032a435cdb38821338b944276f2595a3c4ec9c415069cbd7a8d08f88d051f01eb4112926a491bdc730f1d4ec712166c628aeae747d9a5a7538626c170c6bdf47a781ef547dd19b641e7c113a4aa88dbefe8ac5e8fc48b4c9950c00ddb4ee790dd617a8981d87316ebd09d3f70213eebec315c8fb2723c21e9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb86e9fd56a6662fe4e87db73a1f8a2571c2c9c94c67ed93df05bad6b6817264ab4738ed16c1c33a008d4cd7e7d7f34affd5b8cbea6312c8f4d723878f48e5d05	1637925476000000	1638530276000000	1701602276000000	1796210276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	290
\\xaa5ad3e7ca995ecb125638b49ad410df52db5ea1eaeda08ff4aa1aff5e5a4c875c4cdb2e513ae1a7ea2889b7426b8a81aab81420fadbc9f8f1e677cc02fd1c01	\\x00800003d280313507ab22f1c8e0d13551a89f7367a74da89941b4bd9295f61896865eda5f7fbab7dceb1131a672a7ffcca5d6e833e3a5d50226a18c4b29746ded74ca31d2a671831c4ec224f8e13195777b0c4def2763d35506f9e2804987794954537bf7d0a5ac706853bb454c1343fc69ab16979dedd60c8918da96c1bde52eb0ff59010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x49a6fc2fa85d9ce86e531dc1f56394deac366feeac7cb20e6d430a79af02ecab382cf69db11b9bddd52eac2cd3bd9b7cc5c74813e575c64c21408a766bab1502	1631275976000000	1631880776000000	1694952776000000	1789560776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	291
\\xabe6c844c95b47e043e24fd5e219e1a5f681e32e0fa65990ada5c8fe340880f40586789978c1ca0c25b699b06806bde8178998e9fe2bc720851ea73f98798131	\\x00800003b983c3ed9c065e2e59291577b883aaff6cf6c91e470dcce293f7749949bf34d72f64bf33a24d8312e0ca654765be01d3b4fe2ab3f914e91e3d78fe2ad8a5c148679ec4234dfb50900499c78a55eda705ae2d34e1951509fd5e7c832418dd90dac4e67d6484d45b11b0fdbd16278fc487ecf838d3dc8a7edcb544e2a70b25efef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x02a633fb4538206b875bec9f6eef3799d7b1feeb5932271bb32743dc76f0e2bf4d3f92c1cf93238e2d10f49d8ab3083905cafc5709a916057e75041e65d15903	1640343476000000	1640948276000000	1704020276000000	1798628276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	292
\\xabce1bc31aa48ed44ece7fd7c9b873be5e37915bc5b3828b9ade74985b38be911672c8b2d810bb36599d3df04078eb4d7ea1492970266b33abed0d8f255354df	\\x00800003d498a565b365accf6010237c0d4079b612b1a1120f018e47f7e5cae4c5102e67721e713b96d2d429e2db4c2c410f0d570d7f2b590bcb063869a73b92b4866b7d8720c0a0bdd013598a0f9a4fc75865a5b1d7c2e359c87a5cfe3f2f05ea2fe25effbcdf2dfdac5439f9ca9870fab114be186daafa4a8bbff4be5d64ed633f8de7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x616f5d749a777c5ef8a0a7bbf1a5246c46b669657783f8ac9351b3526af01505c6e871eadef673b4bb9f750d8d4670418954f0a4ab06e435b1d5f64f73dace08	1627044476000000	1627649276000000	1690721276000000	1785329276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xaffa764019e966b1fc9753991fe47a66a804c7449f05b1b09f81e4cc8da57a1cfc38b674bdf121ae710d89f886eca7e5b01903b1f7e406376b6fd9eb0ab03b31	\\x00800003d78a00734c382016c8e783d5976ec44a2f98a451f5cec14f45890b8e27e7e04090e02caa1b67d93af5087ebc3c0e629c570f83802da681ae95046f7baed160bc28b185dbc59ee4274d9570259dec1ec1094bf9480460341b060e8ec1dcef6233b00cc0acd710050553f66d27904068642e478eb2e0729f3daa20b54bdada1205010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x08c2c3904f4e882da7556228ad40bb9bead0cbe0d38d37a3be110524be8ce042ada476c51e3e4919b7c10be75dcc7f52a7eda3fec079db9bdb691eb9bed32f08	1621603976000000	1622208776000000	1685280776000000	1779888776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xb7ee28a70536a5029122fadf36c4794eb5404478165e76f119629590917a5cbe41b7794235a57b580b3765770e58ded2a0bc31c5d9cd910950ccba5e76263434	\\x00800003d80906a5e73c73973b6b826db05c2b8a2c78c19e42d73cf5871c810050993b7f2399cfca8e349c54309eb3997c5ff76dcdbf380af0630b38f8847d73bc9f633ed3dd340caa696bfcf38ca7a0a31ec8f165e47cdb4aee4ed9131bcb69bf0a2b67b27bcd588e44fb9e15a3f28ef31069f6a359588e1c44f3061d86bc57a52486c1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x53c0834313bcd41e0088704ecd39cf3774b02846ee522dd7105f3f6e5f74cc18ccc8b594bc5bac92eff14738d8f7ebb3b9309ec17ff6a2a2a8e86c9f1c76c301	1614954476000000	1615559276000000	1678631276000000	1773239276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	295
\\xb88ea2dd889ca0edc82e3d6a30f38cf3c49663256f85f50beba236577b38e6b2a3e29d722ae7c61bf196ee419f07e2c6df7e942bb30ee9c47507952e02d454f2	\\x00800003b01fd12aa48a116891d1ff97c0d88f1ab559f314366a9fdfd48a46e887333819ece308fbca114667e46d76df7cbc888e93444713f75a88b87f8bfe2e2137bce50248c85e8d2ae9811d7a34f8b5e2914ddf2e0854b6d09142d87174666152d8d5c88689fe27b6152ea03e8063288f872eda39e55771f2a09374586e2ba1c0f765010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x81b574593734f249eac44b91d1db298f511557634d32a501d231a359c7851c868a5420853fb8b4aaa70364a2881407b01e69362bd3a2a5df145276edd02ade0c	1614349976000000	1614954776000000	1678026776000000	1772634776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	296
\\xb9aa4c93b7169ae4532e57cd0cb452ffff33b8a5d22e0745670240df4b348514de100d732748bc8e001d9a0b46c7be5476e20cff97539e4c3fc031112df09b1d	\\x00800003dfe12360886e0983171b50c248ced7ed817deb9eab69b881f6fa5e22def3059a33f038d3a060e2a5277151163a021a4d81634ad477c7027fde86e668c091497986605e4401cb2f6172525321bc6af1ee5aaebb7f5a536b22ef3a0301bdd10b98c8decf3b4acd666b37c5bc8160f3410506355f23ee506a792509fd8992988655010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc86182fd90c8afecb7be79e7b7fd3899962a5e4eddbb80b268e72486c9e4573840a7b42970b92eac06701228ab5fd7990c168507a0b40d7b60a6f4f3a6cafc01	1637320976000000	1637925776000000	1700997776000000	1795605776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	297
\\xbaee77095497008fa9b16c88393fb10700970898a2e3977d6013e9aca5624e1b840279ebeaa9852cf024cf45a8b33b30bb5f40129b4b4d197b12b17d922838de	\\x00800003d3cfb11be83bde38f8678213d21d2728219bc77830a0a70827dd1d5e9241592d00aba020074c522b97c59e49f699d6185cbd49f0d565f734924b45c790a4c092e41f7c34273da9082f26fd7fe8d45aee479249f786dcb4b468de3b641826ba6e86d0c5f35809dfe977106d4db6efb9a7914a5719a57b4b03dc670f468c62e803010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x77ce6db1cf8f2e61d57ddbe5f123f3cd71128a2e313d63a7847114de9b255dfb7b8d8c0af9e3c43a4f8eefd7a46c89d3a400848f26cd699acde2872e63c3b608	1640343476000000	1640948276000000	1704020276000000	1798628276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	298
\\xba3235c486e07a59a11ccf59fe5d5c458d282507f7d428c8b9c979b10d11349f2c1709ca652393c96c59d497f88eff1abb88d70d24569781f44447d2f36a4804	\\x00800003c563d7bd156c231ab863d5f84eba64438900d54c49e767ec9a74f70467e4ed2c5c79ebe547e8f2ca3ca1e92a170aba5b49edeb0bf013444f4465b83000634e5ff9bd7e07309a870beed17ca822f6497453bd226292ee3a27a889765fcf01272ea2ff1cde39e7235e4e58f7d06a3ddddef4ce0a88d459152d0b22ce2e90319509010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf2b43a0ca297d3f0644b8004aab4c4abc17b906992b0697dd5f39ebc68889873a96fc63a54d28b8edc08787b72ad3234fde283711f0e33f965a1f655e443cb07	1638529976000000	1639134776000000	1702206776000000	1796814776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	299
\\xbea6a7dbcb7873a329087598d34d936b26ca98e642a0d2b5ba7254b5a57094aabcd596ae6d2e1dfb3078c2797f708330a4be75eadd9818be89d5e2eb6a33c1a0	\\x00800003d036fc19eb0545da2ed62186fa3a0600cf67ad83d1a239715feb44e6442e2c6cfc71261e0874c7063993448884bb0603654da4c664a3a4081764be24e39e6dc5ee9695a891f0cc7e663a667ffdda40a0f380a8b8e9caa7f0afea94be691b4f89ea90713ed71315c6f72e116dcdb63d1cfb77d4d67d820e8d8b910991d007fb3b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x65d0b514c45bbb023a5fd346982415193ed314e9f5cdbe93a2738794f73ea5c44029a124af7a8cf99a3b0176c90716cf32df520e99a6fc747bf57c381f73d90b	1624021976000000	1624626776000000	1687698776000000	1782306776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	300
\\xbf1ef8518df4ca88ec3a964217d933630bf53d499feafdc6bac8fd3cb717779294822cf20353c97247d204eb0d1f14c1c679aec11f4dd51dbf6804677ad72019	\\x00800003ce188a3a4ae16e9145326b41cfdb2f9aa8fe73a81738488cae0486938bf2d15a05e00ba0ba78056db6adf0c593fb2304af4404493e1d4f9004aaae4d648760de5ee03c42090dd82bd4688730ceef018f9227ec689590a63dd19d4ee9992b669619f22ff0a6547b18ee028e62bd49990558c15c1936181d8591f37c3e3a7c330d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd0f0f1f588112e23c37fcec989ac62fff0a53460f34be119361fc60f1ad0da3f325548ce5f1e338debd5a8754d8c634124d5e5c99a7cf9bad17fd915868e6206	1616767976000000	1617372776000000	1680444776000000	1775052776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xc77ae5f71cc899b67b52f4b40fc1f0a0e75af68ed30f0629fb294dd625cd73e0bcacb352fba599ea88024b1cf6ff83419f7467b191302ad857f1deb3074b9533	\\x00800003d24aab00c257e7ced206ee1b69dc73eb477eb70005b92da53a7e19642fa289b310685efded0a8d0de0b4d2c484eb6b84cc9a397d7be848c54b784f8619020e154adccb0220a42e36829cde57f2c631d1a46109a910151883440848e81088699ad1b31d088e4ae2596c137b7341a2428b0c2f33743aea7bd8556b2d1a5c9b6bcb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc72460bfb0e13f0aae4bdbc970226ff451afc944f3f3ec807e27d866d61047e8320b1fc77c8af0f259e54c9d3c8bd4dbfd91e8177ede56e32d9a37fba5e39d07	1629462476000000	1630067276000000	1693139276000000	1787747276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	302
\\xcc96bf708ba24cfee1abcadb869cb041ae66aebb69c9b87f206470dba93925b3cbd74d56f74fb33e2b89a3cc19f22301377b94645732a9b6ce6d38d7e2772b5b	\\x00800003aa135b5c597593f21d229afdb00b09b29fd0bbd29f75cdd7b1b99ff2a4f9180d7119062123b262e668bd0a8c4b7109b03b06b1c10fa00e1ed6f3ecbc819f8f7ec19e42ceb35b49e978c678da28afcd343d4ba9c49510a8ccdc4c2d3ed514fbeccb84a7cb225ce26824cb41d67777dc92bcc7cf9f1a195779447f6e32e23830dd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x73bca7cd1b28c4a758afac9f2b99c65ac53ee08805b351dbf145ab6f9db6f3657709756474056cc48acf0f9c33a307d3d307cc1e291d5a1f1b37e8f175b8930f	1617372476000000	1617977276000000	1681049276000000	1775657276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	303
\\xd37a905c3c5978cda093677334559cf1b43a98f7fe74b0b14dd2e0dc8f5ea01170ce583efe63d9db350cf557d48e26e2393e4d46e657d93ed96b7d7cf0fb0f87	\\x00800003add86c9f774f9ac917ab81a7820d0c73ba544567e99ac754840a8cdadf07a72b555a25f2e2ee3c281c3cb6ac6727c2aa6981c7411fcb5671afb017dd2534969ce138f8aae72482052dfb97c43141c6f116a61b341d158a024902a7c1814f5ccff794104150ebbc73eca12b1bbca5a8a164febc458d3228020411c260c4c204a7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xaf954b816d301587f977710dd74d6f9c5c8aaa2e28f583d4783a48b2693cc9affefbeed5efd7f56447c2d9a9bb9bd4f8eedbde0c309a8d3b40f93a4f34860f0f	1641552476000000	1642157276000000	1705229276000000	1799837276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	304
\\xd64e1522d604db7297b61d80b63d2eaf10360aaf85545b5ca144f94e93fec5e520aae3ddc62960ae8e7cd4a681ef6c65f187a0d8acc95ada1b761d0815c6e92e	\\x00800003d28a80635d6bac298dc400a4569998500ac53fd69bd17522ce093a3dd26e7875b0b80002279ab33b5a0c2b7f1d3736032c898b328016b78344525cd8e219a41f0464f14f070128d9655b49df0e763d3208d0175f0a5d0d830a4787637f543cda4f95f6266954297875968b69ce859d032610745631bb5bb998e6460f5a78af17010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x140cac574c5d622a6a1c4d5ab0cbd49bfc46120c3fd15af3eef4a65bf28bf2575885bafde2a8855eb0c3cf8d394537117774f624316b5c00b0dc094cb6a8aa00	1611327476000000	1611932276000000	1675004276000000	1769612276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xd9b6ad425c42385da624c556541882b3a4edec8f54830aee5e85d2704e99b888d7ebfe3cf3ed189cb8e474f6824fab0f01566216ec05f079ecbb4c6b79afea02	\\x00800003bba9bd20cf927906171e7826e6dd698597ae2f9b213f6978b2cbf6021ef4177086db6fdb2cbdf6d8512d2180eff94f71a6e56af73dee747502b773a25195e49e6ddf1f34a65d851abfc8560707c1fae90eb5e0877c3055d2b170a3589e94b42d600a21e7c648bc7b7b09cd8126a5952a256514835f3015eb0d5cbb9695e5a883010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x378a333a8dc0c974d5909e92be70edd692ca2832ee12ebf3db59b37ec887973c0d86dbb3042835b1e59b63df4a10cfeb7df9ae188f447781accff8fa6935eb0c	1612536476000000	1613141276000000	1676213276000000	1770821276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	306
\\xdffad2e718b0d32ea6d26de1d4eb778b47e41e40b827b45d96ad5db1341a024790e30fbfd813277f0dadaee3cb7ca18b0a6d5c42f89ca1a334978269095b0c04	\\x00800003be6c6a2f46c058b3f1a5c3da20c82b708a27d72fc100d27b562e6554e44429d175e3694941baa36e0e0150c0e175f32d4221a58a699b4af4fc16140c71f474348ad971d86e86f2248b517e87bbcc37a617fac470266ae8a8c188dde9dace79c64132b360f735ca80a939e4073e8dbabcfbc00b005e5ea6165689ec455c0300f3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfac75354c606e852687f420c4f55222fae1319837b4082b34ce25eeaed03787a3ebd00154462a1083b3d000f89b83c9152daa04f226fcc556a1e6d736f983e0e	1640947976000000	1641552776000000	1704624776000000	1799232776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xe056fdfbb8242900a2d0cea3d2bdab86918daf80e9e4a4f8657d4d04d8ee920bc05bcaa3430da172c599b67e276b1fa47520aa352de5837669ccf344cad422fb	\\x00800003b6f5e0c572c19178b4a70d02b913c5f304ac20e952ca362283abd296703db1e11574f6c483143043564131dbedee3071871e538a48ff7ac7e0a7f7ce9fa5ee34883f3cbeb0fbde544607f93942418f9b79ab3c2a6cddb983d8a99c28c8c25b729f12bc16961cc97dee2ea72453107e31ae9c17f60241fc6d64eba57015b541bd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7863ddcfbc0e342bf7901a31b38f698494fa17598d31efca0ec83ef3dda3ff337a4f5ed6046f10fc6d0c8552496bd6df96bba1287ce0f2ee8a4de19aeb31db0b	1641552476000000	1642157276000000	1705229276000000	1799837276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	308
\\xeb0acdc74973f4aafb84cc812b1edc29b262ac5122d253d93eb2ad40262ef53ad036e97a336c00d3698b4465c7d75d53d0ef7bccac0353bbe0c576171cf0562b	\\x00800003afcf36d78d0b50d3cf5eab58742c40afbd14b0a4ea080990de94d8426ebb634acfd5806142858128a7714c241a808949fcdd0901b9a6f3e5d9ade41b073873701e2610e11f2eb92252452eb26bb269625dcaa377c18a20433d2822f80354c94ef7d66b0845a213cc7b9146f5091967f30c2e1f957b65d10ecb745ae02e2d0c97010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xaf8f6bc630e2f381d77429bfd8b0c7dc1fd4e7a671965d071343a1794a88fa3607fb4aaafa353b0a09bb26ff627083272a6056b382f280dbd350043ec38a3205	1621603976000000	1622208776000000	1685280776000000	1779888776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	309
\\xecaeab65b0fe1786dd0bd864a5f4ad4f13652aa706160a70a92150af9d8d6b836c87134b7902ea12db48ac0e3ddeac19c89a1442b17fa66247a2bc6324f36860	\\x00800003adeb50cf38b2dbf40be13e7a1a766a5c88dd13f72c418682dbf6b63cccf9f6a4530136ed3ee265d4c07b3a2723e35431c6306f2d1c82e4e7e5da05e9766c04d28174c2a19817a58ce9ca5c1af11924a48887813241f1f186dfe4e304853237657e9216be370987c69bb5aefe9c2eda5beab367d3db021ede64b48e81b8417ea7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x04b19321a14e60532009567f414cef4d6b5a8757530629ffcf30ea0c287e2c196802ce5ffcad0b8177ae7f09126668109fae1ecf150ff2f1dd389a2c218c8a0e	1628857976000000	1629462776000000	1692534776000000	1787142776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	310
\\xf09ecb2723343a5e63e74f016e3cef0ee0fcce1fbe488fab53aacaf3194f3f2368c2cebd680e762950c1d43ab24343b46a96ab64e2bb00348a626167ffae38c6	\\x00800003bf76017db3c9e2f78ae344de8661f84846b20bd840c4272605339be8b70f9278656b39e3cc6fb52e5d6dd68c3d8fee3a00967d52ac8e35b7b8b38ac816828e47e7e480208322a0c5c6be2047e11a38596ce491a2307b3c8ce177c04c70dc779c1a18bb9e9223afc79608bb42daace7013a7991fa8db88b85b8abf05e6b246e9f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xce52f5e5b72cd8c29bb6decb536e90ac9eb073115f6e2c3f47a847329ad59dd2486aa7b805d0e604700289831c1e996c05f866147b540561fae6379e6633bb07	1636111976000000	1636716776000000	1699788776000000	1794396776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	311
\\xf1f6f2ee16b18bfc8bbd9ca4a6716e9bd8180457e4359bb548c28515c2fd1fd3feda51541182b0c4fb6aec12cc5f421e169f22d67fd1cb656e53dd7ccc475eca	\\x00800003dedfabadc80236b8c60ad38ba2a50798cc7cb15ad9302c79343028f1bc2e50ffa2716edab7ce0b20bb75de49649cbb182166d154a765ccc62bf32ce95811d50fdde1f4f2d15b8f0f70e71f6fbefbe0549b9eb6d41a277ffe330390c1b439d4dddd565c7c221fd14b10a0b0b110fa4187995613fc1c45c3f883f7a86ee43b9f75010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x049866ca8990a5f1160c97cc8654c8ec20ddeebf41e84ebee5e4692545036322892b87aef4d8ecbc7e498316c1bdf3848c4bbd73474fc9e3d6aef9dfd671030b	1613140976000000	1613745776000000	1676817776000000	1771425776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	312
\\xf2aa7070d3556dc96fa11409f3bed0cbdd54b1eb6962f3fdadb6afedeead24357ebfacff8bf4137b01b02fdd7114073fd86e4fe4f6d47a94a817f6287bf965b8	\\x00800003b8a27841a5d5fe2590955bbf7db6e558b03ce337c6e2a33c20c480dac786993788603652d0c90e351c3c25b31ba6b433ef46c24dab35ad2dc4f25aa177b5aa4e08c88493f4e2e86be96c30f9be95583255c74acf321f78102d1fea98cc14ec08e4581c08808a6c6cd13e58f3c0e74d997b0c3831496f33941c99073c0f48bf3d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x044f687ed483d6dbd400b1b60126ca8f6e48390073941ea3b9cfcc6165cec8621a257dac45ded2d93e188167f40f4afb38bc3857914f4b83bb14abc7fc39c60f	1628253476000000	1628858276000000	1691930276000000	1786538276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	313
\\xf61ee8fb25156ea6d5e703cda1afb814ffaf5714a08fcb39f52157d0ab25437fd20c935af82a54d67fb2b3a5f9b7533ac086d8a43897530e3ca64a9e18f66522	\\x00800003c5ab6108667a0be4fe2daa812be503ef38b52b92bf90729ebe64260d5a56dc52723efc1695a0fb2bf9490582ffa9094b961088d80487e2403a496361105ff7bca5c70051bf06cf6b8fa0dcbab86a2ac6a5ffea945954108bacde2b44b018e11db4e25e76205841265d620379f32ad0681ce2386e9adef33929cd856722e433b5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x73e46ed809189e867abe47bb05452861ec3fe83e63dec98530172f237ef1d7d928d50c11990b3c9a54149aa2080cc818e23ec6dad6df4ce5636b14ef167d4d00	1621603976000000	1622208776000000	1685280776000000	1779888776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	314
\\xfc66b07348d24106d412879a431e321c196e9c483e9d89a212b1298af25208e03ae922c9993986249792e513b600d9be818ff2d4498009d89e0d2e35feb9de9f	\\x00800003ec9e10e7fd1ca55a3b445845c79562c87d0de3010510d711c1e68361e3b349b1e7648fb8f1ebe1154f20c6ce83885929f053edd99db03eec8e9a10b8de126a8b1937edb7c87e2bc873c1d641762d6ae0d93d2142f0505764b96012df159f8e7fcae6427013ca68d8d8b6e13aae23a221a0e5969dc33991d23e93c1b7fe5113bf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbfbcb856652230581720978adde6760dedc1a1106af1f30486a12523259c1f39eca9547ed64a9634ef75e6e8b96493e6a920c50d9fe3b1c7a4c4fda83a7fe401	1634902976000000	1635507776000000	1698579776000000	1793187776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	315
\\xfd16d0897764fbff87006867e773315ed03e1b0aa0b3183d369cd21aa9df0f411233b0a563a78c6dc99bc04dd6f1f735c754981d02d622011ff95a8b076c6643	\\x00800003aecec4bd8a7c52e07850f8a2fab9cad4b66a57ef23dac7b630a1ae89bdcdf97132f84f0de8ce268a2e16138638f3d42a2b60e7051b53d649f73fa7142d0419e49e3c09b197e30095c2dd9744e5b03796efc4c7578021890757a4c8770640cc6615ae0f0448ddd33654cb5644079679dbe8c8a04f24eb94d168a11732fd94386f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcc8dff7e1c71422aef175251aca2b4fb1afd97cd359fbb1d8b32aadf55808327948f5981b0c0cfa5ecdf3483dfb158d951e2cc3258a6e82a1d8de910fcf78108	1612536476000000	1613141276000000	1676213276000000	1770821276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	316
\\xfe26ca34269cb0f4a7ead95e3c6e8139919ff5b3676d240ab46058ed5f1c24ffb303bc9ad025f7ea1a1d3fe6f8ca4ec6ccb7ffa8fd91ab0d38159e0c2fd99a35	\\x00800003a03a70b6f86312d475b1505f4e8afd0cde985430a71e6928382323094a1ac6d9154a1cf4b96aeaf81b8ccc11c0b5afcd7f2e063a48f6836ddaddece18f3c70a833e65257d0099836f2e89199d9aaae0fc8fe773f036ce330d8e32825ade8f7a6415c329215b28898271318e7d9cfae18ffbfbb73dbd7ef58f369ca7e0277d5f3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd21daecbf6650abebb5c9122c7c5ad2562df2660623bba804b4bb977f7ec5f3735fbe2c98084d9aa8276b857dda4a1e5616684783b8360e9263832cd4315d606	1617372476000000	1617977276000000	1681049276000000	1775657276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	317
\\x020b8ce0cbf34ffb2c92d3fb518f3582d8aa2c3fcfe9452779e9ba0bd83ce92190d3667013a5e4411385a11faad8d3b3d4133d388083ba031953c4ccdd8bab67	\\x00800003f31011154f145ec6695bc4490dd5896894d3b55fdc687b83b0b128b659ce09fe5dea44051cb50dd0a7388fc16d76ac2b56857ea596b35ca25db696cfeb79e8f92005fc364f116d84405b4e2b7ce66431795abb16b947aaf0a4f115e3bce769db7196466b7fee28c208ef3dea28166000ba4cb480f826a80ccb2b1fe8938ea5dd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x02325a5e0279a1bb43a9ac2b4912d4ba9fcc30e075c3bd1bf9fab4c8004f64ba67d135c10548f2824437709637f829982f0405b307ef8f54d38c7402dcb8cd06	1628253476000000	1628858276000000	1691930276000000	1786538276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	318
\\x033713cdfdcf97cbe01ae8d875987ebbb6f642a8262d88e3069cde44a75a3824602f2aa7d84c25dae96e2c58bf2cfdd11739f89664368eb9aa9a6b8ed7185b4a	\\x00800003af4294335358e4748211e21c7ba5c769dc3d1358cfaaac38a7dd3bbedde8d2e901b97f9bc59ceb9f3e0700c812f9cf0449cca67d39fdcebc36879e2953ff9a96e8ef15d5eb67cced7e829ac05d76f3ad80471d804a4d1e16e544c3b9586277cd92f23c3f4b6be687666d3588dbb8d81063d8b5d5a7bc89e1849e36b863c0038f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x956a2008e6e6ab7e2e2bcf9c432e94219acaf7c20dc0fce973eb2b27c1b99430e5dccfb91eb4a3641825a439a1924808077ffb7a39928d4c64e3197612cda202	1633693976000000	1634298776000000	1697370776000000	1791978776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\x04dbec413972621dbd9d02d151d40b6a4c6a5c8bbba6ae7f96b76ff3d009addf46f2f5ba6363fdbbd3df77f71c8cb4234d60251e4fb0aa8f5268d50d13cdb7f2	\\x00800003abaea27441164f140b57c51bdd32cc8193e8ed824ba51da30f493f8d6b191be3fc7d85bd28628018de1d7fa115739daba31189e425ff33a554bc2ba3f686f79349ed81d3f6b8e065de579195372e036270f85322f58621b5916c1e3ea13dea8805673cd91f232cc4daae2edf821212a43022c2352d88ddc67245c7053e7fba51010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2db71d03ce44be8f83d169bfe580a2e2abbee58dee05819a753b92c28ce423fdcf97dbdc1b94fd3b7609c6b562f47a1f946e2ddc2928ea8556e7aae21f39e607	1628857976000000	1629462776000000	1692534776000000	1787142776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	320
\\x08e7f378b7a255206ddea1148469e1724ba0aa53c062794e6d5c990468fa7ba4fee09d0213b344d52b886cb4b16ccbf76225b414dbc99dedcf81a5736010d6f7	\\x00800003d3a240fef612bf44b7676b59371e82187f6284c83b6fb13a786037b765ccbe14ca11fcf4b38fa3a1f73c988b62755412d5cfab237576059a6730d644939c405d2f4f12aae7da8d212d6e92814636d50c3a8618580e806cfbba0800f7589ea49190e301c8f8728cbf728c8b1195ce2fbef0eac25f034db6559da45709da0d0f05010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdbefd500bc74fc7312a08904b001c8dbc72b2228cd6caa294dff2352d751ebc4fd3b69c35ec0c56be2785b3d1515c58a5c0ddababd9d6de072c11af502845905	1613745476000000	1614350276000000	1677422276000000	1772030276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	321
\\x08df00ca3786bc24619100c3b4a5495aaaf62f94c2e06f9d4164a7bffd435e320eb51fcf8c33f8cc0f4fdbd8148f4a86f313ddf760d7fe094ad95576f66cd2ee	\\x008000039473d15a4a19360494f995c6487033e7fec51251b1965334d825867dccc65a8ba098dd8731b915776854f69d1359e71a6762519da92d8fdf8d471c11618124858f7e753e8ffb85c6c6a964d77f119a7b02f61e308ae7bb7f09278b603d999644d16f5ac1ff2c1bc44caa2a2f8f3eba35251f97602167ee0a66c1f74c655336b1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9eb3eadf55ea801437c5a5c45238afa344b3cdc308481aed01e15f533acd0ebd4aea4bd5d21c45f3247223706e1c2ca51301d8bce0c50cbc4cdfec30d515ed09	1620394976000000	1620999776000000	1684071776000000	1778679776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	322
\\x09471b41652baa1024075d3e52fc72db7179953e41efe8b5538566848ac2f0deaeee9e6060714239e25a981da3533d260a47c4a3cd68cb3808a1fbf911a5b8bd	\\x00800003d0fe5dc6e78626d983e1ba107058cca3ba5b8cf0286d8054b5a193889db81cb2415b40a0eff26fb9316dbff92cbab759df559eec5423f98abd929979286468f448afa75056b7c215e49524d7775eb2e56d5c98620bc378451bb99574d2e50aca5c416a331d1893c08ff0818f08a2a3d2c9389afa9be2af285da0448b364f66f3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7024b6e5f6238a00ea555d173c273c9f2e08879b2bdd4d85f996f7c564066774de5207cf9402ebc194f127345f216b2d39ed9d69cbcef61d1d81f280a2e26f06	1622812976000000	1623417776000000	1686489776000000	1781097776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	323
\\x0ccb31f7588082cb6f803a01b72ecf0fdeb6943cc48311c22bd84f108105a6706c05665d2cbdaa1cbb076ea944760778068807c84d768ac1a1b733a634e36309	\\x00800003a21c068d29056376bae167781c24a34fe28ed90a8cbd3d607b24c66cc7c13561b94e749d75e4a96c2bdfc0f457b8d6b7de4cd576f2e1211d6ff223e7c757b2621ba45c19934439b553247053dd5564bf50e1348b840d5a5ff353da75ac63953bad341b946f23ac6eff9a9a3de2769e6bb4a1b4618f39f4d3a3b811aa00c8db6f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x7fda7c3413a4aeb6cea7339eeb06bda92f06a9aad84d2bcd51644c8b8c5e7e78d8f0fac0264044fb05d3e281540dc0884fbe36e281078c8baa5e411a575a560e	1613140976000000	1613745776000000	1676817776000000	1771425776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	324
\\x0d4fd276db2ac0a2ff5450b3af37e411f37141be2752f9fa046338bbc73e3d8ec8e6570b0aa4e9bf49edb734adaf686ca4546cd3a5bff7e53556b61342d3dbf5	\\x00800003e63aedc516f7d7949ef6d961d5c6157960fe9d01ab1554114fd013b9a2992d49a55270d9e29a318fe007433e1700dcecf63c412eedf9a707f5a8cb1355065ca097ba3f87a31c96ce2f0c7d0715544de64147b6837949a0573fd290939495d562427f3afcd584a56939e4a83c9435b4c501bb4215aafd7c9c51c79a28c064512b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x173d0381a23a23bd0e835e76d5e60ffb071de843476efc836c2c3d133bc4e5087e9dba9d284e4a40621eafe7e48b1921947cb60e2f7fdcd4d0785af5caefa30d	1619185976000000	1619790776000000	1682862776000000	1777470776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	325
\\x0f0b3269e437514bcc7f294394aa2a602907c357747e67b7118438de36a4088fda9f7ce8fca5f4ce138bcc1a338cbd6cd5d1e29f72d953f53e4f1a0038d5fe0f	\\x008000039cb19c650dabebf467377894f464f2d4d510b762ebed0eaff398daaa511f534bf5d14837f752b1da2483899c34bd645c23189be85f0ab655b5abaa7cdf696634849ea9b8b4a801e017a89a0fe2baba708b7899e6ab8f3d71da5428c4513ec8f175e998cd714300fa2b50d49fc9aaab760b0fe0d88ddaeb3661f8cfbe3eb4eebb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x69dcfb3faec5c11d52f3ed1f49b7f8995e2ae34f4802d794ded6f76cd77a4672d4db43bf8bfcd9fc6ae175ea1c582aea449850c7be88de1257d7d389a0dc2c0d	1623417476000000	1624022276000000	1687094276000000	1781702276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	326
\\x101b91f1094ad8e6bfa1f60cb492e716a0b3824730a9bc0892791af19ea0d39be6a5729cd18db295205717284147f44a7d51e2ba89cd3ad5e4e9a2399eab57b4	\\x00800003ad894db24692fd960436b224c19d3fab03f36d65e2c082a68c72acbb097ae6968b70f55806d9947dcd78b4ef79f9959588971a28021d5cc7b3e6c76eb34d67a1ecae16201859a1dd6d70aeff7db60bda9d04bb55a18fcefe4dd1d7530d1cfef1dabf4cafa784ad4735c00a0da8c1a20099d892535dc7c765e2a51590909f358d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x378231c438f59cc222e2c8b185869d645533498f2be80a5028b7429c44f094af1cebd0cb4206dad7681b91cbe0469ec59b57f2fba954342898e115d12a75c00f	1641552476000000	1642157276000000	1705229276000000	1799837276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	327
\\x104777f05583115ca5257eab97fea52b0625b47ed4e65a88cfd2fd66ae1009e30a9794ad91f43b065cc28e4b4648afefc1916ec084a1deaee5ce24ba0fd32b02	\\x00800003ccc41d7d229bf1b06a58d931027e81b9a9be6b2c3f5fc26c782edbe787ed75cba7135be9fdae97e9a70a59a5496de4667b5d3041bb87630b4139766e2ce4ecfe775411443bcf92151f318dd34bd4dab9adde3c2585ae8cb9d9739507036b7bdcf878710f5ab7412998b2157cbe77063104c91b50554c619f383153cb4a0698ff010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x90706f50d52b3758ff5bf3dfc9a2401c08dc47779380d21cbec464c0a8dcfe87dc6dc6e8be444afd50e953072548109ba1fde0403f3fe4d3ad5ae66cc3f4c002	1614954476000000	1615559276000000	1678631276000000	1773239276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	328
\\x11f373d3e2e03f8cc122d24a9530aba26b6aee0c232a2ff8d3fbb2cfcbda2b9c7d5385f73aecf1b73efd27a27b6cb2c0573204f0c0544176cf26bf23e8198a93	\\x00800003ec309c642d0958a3daeb461f022c3802e4b0a6b04c0a10c8d961b309f217d504917578614eea0cc7c1ed47b702e66f4fd55fe7373f9dbd581ea5b0b5e8113eb67c158a97abe98ba0149e197d8f5a6719e1e34d5192637dc67bdd888ebfd8652f9798ec6b6ed315ca94e0eb6b4422a8fe4e0594dc9a2755cf0a2ff5055f3d3909010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5434c8dbfb7eab73c77ed957e0942bf1e1b628687d23bec4a4f3a67e4950aeb40d39b8b4912f4dbbc319d3b9599ddd1988a097ae37eb54fd13ed2955add44003	1631880476000000	1632485276000000	1695557276000000	1790165276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	329
\\x125f43cba6a2ae75d8af091b7b2791e9186b7b16445461d551c081cb7b6189d5efd4d944998ccce04a351e1db830637d53767e15075c5d20c8b3dc3a40c9ea83	\\x00800003c1a6a2227bde57802d1885e0d11f4aa56b1ae58c1e1a250d9e060bcd0f787378908333349e9205d3b0354afb2a687228c071417a931870ee3610d6c2f75210fbb52c6e925a0664b1d18c4201f114700cadb3e0d474ac633c7129b7bc1feafc2e5c019d050bb0d29910ce96483247561bd85a8e096fdd9faa1f38ab0052e8dfad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb117019dbf8441a66740ae9a2de4f571325c58d888bb24210c307e04e8ef3f23c62d8639219134c7c8760fec87b1ee2eed1aee111c4aa3fc6aee4577a928ac0d	1640947976000000	1641552776000000	1704624776000000	1799232776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	330
\\x14af8671f98ae36e0cb310ca98285e56fce43d24f0612bec8eb1955668510fa31120f806da9b5f8b1b3f76d3e14485d7a5f9c9ae86022dfc5a4b6f79bd08df1c	\\x00800003c667a57d3aef20ca439caa3829ae96699c86a412a4204fc3e77e1fefd177c0ee7b6e98bb303949456ec02080e2aadb0d5739e0b0d481a7b3c47584e4904841a170b6cb204f07f719c9ad5d9633052704b5374d1aba6bab9414407af172ae35510b16d658987a05dbd2bdbe2adb9c78c3b348110594042c51d7554da59be40943010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xed52b0cd3cbc46c35f5509d0731b5ca25553b4056785cb76d59464c444ca8a0bfa4a85ed5a59cbe544ea1d48be6bada88a9fc7ce43ad2e43305b85fa3c9fcf0f	1640343476000000	1640948276000000	1704020276000000	1798628276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	331
\\x16f36a6facbb3cfc8f4bdb55790a8011e6338a19305ef4c24ca8c48bc579d2f12c993a2b211f4e8cdacd53b60b85405e2afd0f127e5d925f80f03c3515cef344	\\x00800003e13e07045bae4e11b63af38064b6192670fd6943627332062d6680d9a7483acad8eb786b402b4957619aff08b825c34890158dce239b4cf7ac03281f16f470d47953ea16d397d107cf69665412b6565a19861f67e6ce40bf13e8ae5db561e7eabe6590ece52bef92327276ce310a8c35477429ebfc340113573687050de12e5b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x69b48c9534a6a05429d5418d7c3a2cef38fa46193585cf7c7fe7e70b8f766233f66da270f903666ef49d240c7c8e947ef9b28b4c01b6e53e74ae03882a351101	1634298476000000	1634903276000000	1697975276000000	1792583276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x2373a429a4c4d9dd4a424fad24e72ddef13233d004d02b96f678060b63a01b4b5a94908dfd5b7730570379f71d37669c7b9416afe4e188300e1ce9d38e952097	\\x00800003f2eded553b53d09f5117b62da972bfa38228e79d31c10d4f98c124736a5d3757899910806eec71cd91e7e490345f80451c2842f59bbd9b99f52f261825cfb497eceb107d93f75c3b24f8117ea086e26c2a483c8be38e9abed7348b991fbbb8f9368de612ce8722691901bcb0127f3132b7f2f788fd69409392f017a14099db4d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x61ceb316eb571c65e299cf56f05625466b6e3723d380526c42f3b8813fa3bd5266d3b7434acacbc18c63002a8d2ac0c6922a110d20bc075a514f57d87e950006	1639738976000000	1640343776000000	1703415776000000	1798023776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	333
\\x24fbfcdbaf6121b79f72d5327c4d80a0d3f3392820c5394740d885b1f9ef706b005ea20cfcc34f30e3626bb75a27400fa76843b3725acf04a6924d916058170b	\\x00800003bd06f2fbee8d0f8105b213ef163460b0bf90c9873edd9e7917ff5191899dbba0e3dc1709e40eab565e887c625966bcb140805fe6d6b73bb1d1bb0d746421a611e6eeb76022dfa117980bcadd2a98aaddebc0370b4b8f7beac8b253226cb9e03df15035e76cd043626bc299878c66e7f2d67662d4a74ee6723dc2b564ce3645b1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfca83ab8a821eb510ce81c2ca025458edd1ff5f4a9c6f6feb1147c67c3d9ceca28d9749a6915db91e431f75c952605f4dc597dfe9e6062b4acbab937a46a0a0d	1627044476000000	1627649276000000	1690721276000000	1785329276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	334
\\x252362b5e5c3979cbb572fb6e7fd786d0cd93f93ef328408b7363ef9688008a7e93ce7fc8ef147399052eb33826318c6eaa3bbda13c210d6afe287443e80e53f	\\x00800003c927b9a09a8284d450b2487647e512b3f23c499423c64cb63a04c6f6ea5fb28722a543f03582b60bee0f28d5b299682101565b94384acb62470cc9a6b911a8cdc45a4bb867b2369e6a2900cb7589566e9c3cd53eccbeeebb934f87132e9944b8aef736a8d5581b100f016386866dd0a82481eae9962cc8d4d25f82f89bbee69f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8042f534babf9ebffeab275003e00d472f861bc85900966637df149ffb610f67e6c21cb179895cab5e73218cecca1ee63de4a90eac1b97010c650e9195da5403	1612536476000000	1613141276000000	1676213276000000	1770821276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	335
\\x28d30772e7819fea4e8fb81f8095a63029e59f4190314ce6e1c5500083750341ea7488eb8931f4480f8a131b9d542bc1294d79391ea16f3d4d49c8c94a434346	\\x00800003bdf06da65ff7b0e5c84d2d494f9bc46b25aa8958df264df8f475f262ad657a24149e9671f00fbfb1d56f7e3da1cf86f125b28e9c9c797227dcab334681460ec77efb33572731fbd077c08db672a860e8bebd498b1246efd1586bf646e93bbe7883bdae8ab8f425168dc598efdd6489c2d0c4016b8a795822503fb93c67d5b2ad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3153201966158b5598af34c6e57d3f8f6eab5549c861970af402cbad44c509aa27c688adbed53cb4cb82901298fd4b546ad2823f931bfcc39dd01e67d7671606	1637320976000000	1637925776000000	1700997776000000	1795605776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	336
\\x2f73ac73966255406b25c51f578bbfd1f331a54df6e5be764cb108fa557b2d2ad6587a8daad24ea5f33073de392eebbe575ccd46bd0c9ce6e686eaa34f040a05	\\x00800003d7154449ef22c93278adac21531deaf5f449d2adf321236232e16559b635eff7a9b7d006ae1badb072af2a80562e23ac234cdcb8ff851fd2ff8943001956eefd120001f2210f06924bfe04959cc5bb94bc7212005fe061e05e9a4db1ca28ba5230d1d138b75a672a482738c3bb24a213d5cfcc7f56a3064baca31fc363801b17010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x92b3db80048504e806658e65c47caff12337049e613908dd833269c2c0fa248ce46ada9d88291569132d01f7be433e3620eaa92bb45757e2926da8952f463109	1640343476000000	1640948276000000	1704020276000000	1798628276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	337
\\x31731931a811bf6214b983d721076b75eff69059d1c9386daeeae4aa8a8996d97a74a0daa0242106a4cb8c7f10f959a89a95730d638de4bf4bd8ff5e02c9006d	\\x00800003936913fe016fbb9ba682548f76cd070841906f99ab62edd2ff2cb0018dacc06514b5f436e03b31f520c2e9fd53b557c6837536a8727628940277f97dd3c2dd8c177db58656619f7cc0eb3f0a0aaec66c415b380fbd9afcb50a2371810f3711c799138d252a55a5f023f53c7b451d52dcb155b892858043746d1e63ee13d40dd3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8b31bd68ef508034c0a32ca361f0fa38aa4255d2787f247a1dbd77184200245a314929d76ef5337105010bbb5e9f45c06ed3eb8f50b6476703fcb7d737f88005	1622208476000000	1622813276000000	1685885276000000	1780493276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	338
\\x339fa57a274daaff7a6ea63898bef3e53ca387d6b31b5d223b065fe692a1c46547a978e92a99a4ec0f1fdb7bbe3da234e926950d9fc8166eb4b32eb6ec1722df	\\x00800003a8df806266f49ff9b163cc0556203cb3e0cd25fdfef4f258c72a4540a444d9ec116d6c5d4d7ed622f2e150db2fbdfb48d9cfba7c9800204e2f53486631cd75451ad19ae1379dea191f9bccc6e6ce6a4ca912a68ea684d8146fe2e179ae30afbdf628fb7efe8c03b90af9ea87eeb1910fd04e1448b8e37adeadf135d5e4bd1a5b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x94a37cdc34db6ae10743e74de976604fa9ff5c4af67ce986aabe38f998e4f53eceb5833b0c77cdd67cb923a98f6473ccedf8a76973137f1e79d2fdedd67d770b	1633089476000000	1633694276000000	1696766276000000	1791374276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	339
\\x35dbf60dc682fdec1e72f7c4db6a0138af59b52c61bf307486ce2fe6afeef88e08a9a65b82ca31c3195ad07bbe83a74e9dff5261414e544bbee38717bf14fdaf	\\x00800003bde5ee6358a59461bcf374dfc0f250a45cfc3550f0a6e71187cde5a71a70d312c4137da5b7aceed26626a86e957af86cd6f8a6d6667d48cdac08b520ed3bca9ccc690b243b086e91c19ef3419fd9b370b215309cddb4e0c17ac5241eaaa0951fb34951390d858433e347f59e7fef71340ff6ff18d54bf2097069e8af9c823011010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x506ebc70f2b8ec6ca48902251929e10619b5d2e5f3e200f46b27835ea451e17ac3ba4e71ead949bf7102c4d48911be3af493855eba04558fef24ef90f07cf307	1627648976000000	1628253776000000	1691325776000000	1785933776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	340
\\x377faca04525a64b4fddf0fbcbfec607878b3358323ee7127aca06eb19c46c6e7c20323878452a4383fe4c1f067400ecb31b3b25f60089dbc827d3ed9a9efcb7	\\x00800003edd6f590cf1d86e71f7ea7349f7b4e0c73faef9a1c0b33ff928950cd61e3535986776564c03e61661963df3521e8a230cc5c6899f0378fe888f57c65618b34838f36d1d38b77b9e70591f87a53426453239fcdcb70cc5c20e3a66f4df6b12f48e002126fd7619e3a431f25b06efee3edb12bcde3b40b18144b18a87a3d14c85d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1131f371d3d6621164b15243fb1747f767731dcc67aa3d55d82a927a588af6e8d9c99661e8b83b36c0d24dceed95694b05c8005e92adda8d31c53b36796c4f09	1616767976000000	1617372776000000	1680444776000000	1775052776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	341
\\x3afb5ffee4c91892f96c254e5cf10e79fa888109d6fcb4ce2c1721e9d26670c295286a79c8d1c7d9f1eaa370f5de73813885abbe443f3a19296eb2f65bbb4e8a	\\x00800003d75595bb27cd117ca638219433b38375631d0deae1d26e2abbc862c35c1a76a09f2fa8c11692dcf7e0656359758bc3a574fdb687c0dccec318261726588ea293186bb1c73527eb9c46614951fa55de49ceb6ba352ef946324c9cc70df394740c59a1827820f021969705c405e98eebe0556655e7368e848ac3476e9b6e12c4c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x45399c4dc0fe3011c554c5b9b85ad9faa69614f7a366ae4bcb9dbc03d3df2877221f4047c6ebf498d41a127dccc62d79aa0f69edb886aeda5ae8cc68245dad07	1633089476000000	1633694276000000	1696766276000000	1791374276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	342
\\x3e677f60c6b8db04791a26ce1a357cf0066cb696dc2fcc2ee68d712cb2e1435b5d9fdcd1754d06912b493859e88cff1ba58ed57ddf6b3118908f68a16850c686	\\x00800003e73a08427fdfa99117758fe53182cdf3fb3977ce55b29dab6aafe2c44aceadd9b761ec08a7cef6fea90a011ab5398bb45773a5abd3887a8ccecf796847f593e0d57a832353c60cc611d6be769220714c76c89f81229b3611c5044ac2b05f4677f36678dbf3488450e1965371cee4690495779d523d08c9c72cda9b0d7cd1b9c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9dd37c5dc698a504f8a5612b0e991c3026e47cc289c8a2df390ec9fd85942dd4e2f903fd3166808f23c7b9c5978049b23dba794233fe27387f8f035aafdad106	1611931976000000	1612536776000000	1675608776000000	1770216776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	343
\\x43c77f393f3c1c7fd7414abaddb1ec4ff0f3bb02b96ef55eacc8192174237cf0d1308ab3717600985987caecbbefb3a57a7ee9425bc961095b686e59deefea16	\\x008000039dad8035667527e1cfe1feb4284c4b2c0c00ea530c4830ee5cb5f88232a74b88d9107a9e7bc17245409b2122efefb4ce0393bfc997fbdfcc0e37443df4f4a7560c3d873e2b0ad388b251800274d85f46ea8a58e9ba580bcfb044cd170bba4aaf9b49d335c2b32432fcf35e95877f0e65f046ab354f7cf045c11956a3447740f5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4cba81cca52f210fa1c31bb2dfece2dc26c9bf0778c5b4b0d29945e55dab70697caa9c69ce880664ecc673b89840f83a1d7bb32010d6a8b807d603871633870a	1626439976000000	1627044776000000	1690116776000000	1784724776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	344
\\x446f851964d3eeb24e426d3f26f637bdcaa2be0f870b0e668cd1f32687c290b5c590ae49bc3637eb81e42adb1f3208ad4589c735ced69eb6b415c5641b8aa4a2	\\x00800003cb024006f2dcc0552e7ec9c642e996764e9151d6087c5a50b36fa77cf734c177ea5234c146121f327406f94ee219950de917fd2bdb0cbece1e7eef808f1426bf7e1f71e56bc343abd056bb6027e8160850e6d3bbf5b953c2b1154224352da33bc1615d3e0f7b3ae6c978fdcad9c7d816ca55e9d6c5d755f27c37febccff2edd7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb96f75982196ef67866e906500652cd0bfe887d8c1f5591ba47e92cbeb684dab0cad9a76f0a98c793a1c111205b08a135424fdf20b1939fe798324216c79f50b	1628253476000000	1628858276000000	1691930276000000	1786538276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	345
\\x48fbee5574fa7c6a252a144f18283a6e95525da42dcff55db77307ee768cb01138842894ca9ab4254ba5b37f7df33e09ff45e578c1f743082d002a97463d7fea	\\x00800003cb97598ae8a141db5ade1ab08ce885fe202c935cf254f0de9a950ba0bf2cb8e078e987e5cce9989d5af6025bac6f3c7accd5588eb1404912f03601bc20d548cf4dcaa1572829a2521412386ff4f0df820a2216aef8cd2d0c9b724f295061712cfb46a3a307d0553d5091abe3bb0a2c6a4431c35a469ddd0d58892deb3f512b4b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf7c646aaad5976a905efab15dc7eaee858d3267b3dc7bad5906b514c594d3ab9954e40d0fc7ade3b085eb925b9803c63fa975476196520d846599f7c98b7420c	1627648976000000	1628253776000000	1691325776000000	1785933776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	346
\\x4b5fd4c222bf23140c57aedef3ddae262fa3997c05d6a84353d460c3766f1b07e8863d3cc34e6581acf96aa228475632f89ba39e860ffebd81751e60e9c29e86	\\x00800003d756f598cbd9e99de0ef29e34d203375602ec0515e9aef5757063b33c7d300dc92b51abd2e3d0fb2c5b0f3c365a5b2cc50a01bf6ce02b7f3ddecb73d5af8d50b2628fbcc40eda3ed7a0a26772b780a2e4876243f6702c71712188f5ffe8ce5c9f1b4fcd33ae1a60647cccab5d1f76d167efe37aea4801827d9185c0d39cd574b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x23a9831aa45ae41cdf8648519903701f28563c2d4192bd7aaef851d70c6b9c81ee30825df5de35a7f30434e00452bb734d43e591fcb0f8f7ec3416d199436d07	1619790476000000	1620395276000000	1683467276000000	1778075276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	347
\\x4c47260bbcfda87e85547bc29f3d74fe16278f6fc5d1757a3800962094b772fe7ca177a0ec94060630bb068e3e22256cee638fdc354cb087d7a6f10f83ed26ec	\\x00800003c3955ab21248bd27408385bcbce206fe874813e2aee6f2510b0e2d6d187a842287ddc1ddbbbaf241a6a90c299d53d4fba36da9b3a25db95c5719833c7e83e509999f16841711ea46c738bf21c71e70f6b775ae03439a2d7bf94c1552ca22f2e8fb3394a90b2c8a16edef3ecce5b5c873c8690d2d56c7dc94e667b7df583e7f23010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x80d9b1c73cc938c2cf75878e41ba9c07ca5e7f577e7ec96c4f7f5222729c795f5b7e2699553acae474b2ef1eda4a789140431700f7c36a9c90a114712391810e	1641552476000000	1642157276000000	1705229276000000	1799837276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x4f53795f4e096d70c5d7b81337629a4d54780b553846ee3c51cea5b0495ceb20d4eab9164348dc28d7ec343b88ba852d61d21617e1017d50dfeb16bafa88e8f0	\\x00800003c7a4917a6ba51850eac43779fd381c21a4dce0f3b093b6328a1537545068fa041d79762f7f7e3deca581fcdd885266a526ee199ec9394bbf840850e6bf720be69e0388841991a28bcac67a820f2763c9c0eed480aa6b4def703b448e3cb7ae576468de31603cf9bb5da35ab90360907d86cddae6db76596cf9f5d00a211b29eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd90b33255acaf8ed1e4e94ad6983ca14e9a7fd6c430e62b6c81f1310b792e0b7e8cd229b2f112807393adf01417de3e0e76728cd266ec63f28033cd27b920704	1633693976000000	1634298776000000	1697370776000000	1791978776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	349
\\x52073b79e98a1915710e3ed1626de7d3765f48a8873106d807c026035bed03d5be75278860f4bc34b3e0b3bbc3e38bd318a72aaa69226e8fa9d7b017501f479f	\\x00800003c136f6b78c644c88b32d534b1cf2e8947567296cdd115163890fc8c6f5e264f983e5d7e6682eb1ff0a311f79ad0052c957608eed8c8219a0e22ed862dea255c49701b6ffc8022295dfe868bda323e8f245c4e287e53525bb4836fc4d3ff471812bf93f60037dfdc5cfcc3b59c90462a279e62e91c05cdb1237a8f2d364cf5da3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9e5f5c134bd0bcd81161effa2d2daf8d70b0bd7cb875631408a460fc33f0a7a66456924ff0b2bb600885755d4b17eb26d3267464f5c891730c19910b91547803	1625835476000000	1626440276000000	1689512276000000	1784120276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	350
\\x53e79d85d98b17dd4ea5827020d155a4f3353baaa74a14112f72803885413157899e36f2361de6acef58d1d73b29162eb822bb84d384425c670304ccb10ef43a	\\x00800003db2d7c655258926976e8bcfe59cba764441781aa4132743bdfacaa05aec8dbae73649b21e90657d7249343a7ef9562e6840006fba074f7be76b224e9ce670d63725e4c4a50fbf989d8347933fddef677a8891c5368aba3cefdfe4cb9ab97096b9850101cba997a8ca19aa1ea3914461f1c34bea46c7c3de9614702260bf87c61010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8b6b4075754c11ea00386ba8d5bd74a912f1c8701139d83595daab1f1861eb0dd48fb6a63634935f7f369f790a6a01fb75cdbdbd1a2d10cbcd68ab88db9e5f08	1639134476000000	1639739276000000	1702811276000000	1797419276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	351
\\x538303f45ea7316185698d0e8e640a502e49a32e68bd9cb2228e7a261aebeb830c20a0a1815b10ae3825fb1ac61ea7bc7a515246bbd8af23f62b4844464441fc	\\x00800003c2d32780fcfa7d398f18a76a255eaed4f190be702d7f62bc19217a29b07985432237b7b0fd3f0b9c867eef27de2f4f0ea671fd6948b8d76c9cc6164281b465accccf9776c138bb13516105b6253fea93308d09e7df182646aa6cb1b7e9bd0954728084b240db6cb445716eaaf7d914e6b8595f2fd50fe335bd37ebacf2b2052b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x993591ff6a604f3e3e75a7ef853bf4128c2bc9c7ded5227fd1f83e27f2c8d7a0f9f7f4d0a6aea6b4b211753b45569c06fef26339d819542b20f8756a960e6d0e	1625835476000000	1626440276000000	1689512276000000	1784120276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	352
\\x535bacfca41741792d6ccf01dccafd881609a486b13491019d5a4ac44d7d5179347fc24f67ba601854b151514adfb104431943e54066b76658aa24af626e2b0b	\\x00800003ca55ff2d8534f7327bc1d2e86bbad0aac539e24fffd39e92a8de0e00436b80ff54926b0d69658064c197effc51751b31c31fd271f3cedfd5831573b9def3853d314fa380a39fcd1afb5ce5cbef8ca2376de7c80305e0928f678ebb44d5f6a8dbf14119a915b412908dc64aa92937bfed4e28688e2b2103391f56e63f9b22fdff010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbb0c5a0515d56fb96a0c1014fcf9db4760d4045a01907fa859a781ecc93279a18c31600ceaf03fbe347ad97cc3b9d40be129b43a5e10c7a7a68a2f70c3c6f908	1617976976000000	1618581776000000	1681653776000000	1776261776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x5437615254de6da6aa666983cba71a69f73856f0a9f5196b52dc86ec719663329a30a54f55bce231789d2b74fc0e2079d5ccaca8c77e3ae25b3ff4fd612846c0	\\x00800003e8e32ace50b82d4d01b5021709458e15b2d9ff2b8a6e28c644eebae555be97483359be8165deef300f5ae5894c786a012384a1d34ba9d20de2a190a059da6293536e4c5df9e2c39dd9fa9cab08dd95f66a1a347e803195f17834938a6bc267f6a46a0a987d1d0d08b4751004b36634f279af7362368dfeb292ad6b2543c17d7b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc651fa29d45dff44761299ac7ee71260f2261534f10203f69089bbe3303716bd458a23369a57571eb8d601e2c808b2db4a24a0d90c0184a6a62875f610f3bc02	1614954476000000	1615559276000000	1678631276000000	1773239276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	354
\\x54e770324550ee1648dde24403ecc7f5120126fa1b571935fc0dced2e062eb9e80c5d331acd180b1842aa330da6d35697e9ec95c0968f7a75ba5be85fcfc915b	\\x00800003d0dbee9f6575bd481fdf08ee50bc07cce3eda5c340c7de5a4455ae6869a5a9bde786cc2a892f97bcc9a348d45adc84ebda10f6f939dc8e235a5c5b468bf8c362be2927ff8fcca5c383750565ec47e8d1cb6b97c7626feb0585179a37d14c31253c76c3c507f1435a43d77d6a47d8489028860a71cc90395270a62463ab342a4f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xcdd63f0e891b28e0ce8f014acf99b85fc8fcef4561b720e27e43a26fe0d7b7c8eab87d236613a3a4b12d1609b21029ddbb3311ad865be3c272765052de0ce004	1639134476000000	1639739276000000	1702811276000000	1797419276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	355
\\x586fea30a24595ec2e78215066b102ef756f8bcdbd37d86e9242840cbc7c003b9be3a5d3c6932441e23eff1df94b9d5868b1ada9844880265e25b403d7b36df7	\\x00800003b4e043663084ca6a8a2ef3c5e7e04eff76277918948110074756727ffed6116d4b93cf01ededab687f29063d5305689f87ca6e08c3ef2c501d454b4fc359f763025dd3c9fd1745148e8ea804e0057b7606de08c69c893fcb037ab05e0950f07832abbb9ee63c7d907ca493d8a1e9c825e5cce36b93f91b67bbe559c5a21f3e63010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x6005b0e4f91536ea16d77f9aeaf09db6b9d8d84cb3e8861fdab89f71a9252ae1f7912d778b27228c72518a309aefb4ef94c2ab464425f904183a7908edf48207	1610722976000000	1611327776000000	1674399776000000	1769007776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	356
\\x5adf9bc4df02f34d42345cf4e767da7ad6012f3d55012bdfd87019a948d8339037a5dd7ca8b9da8802f3524e6caa9014baa5355172800647233665df774701fc	\\x00800003b20c52872f8dc42ba362c1c055d5b9552a71fda0e078a2bc75fb29291af37b505ea2d9e908d9f1dcb489197a1dbaf599ffbbbd85bbc33f0728b64f66856e2eed8b0b2a757f8d7d0161f89248ebeaf11fa8c79a0fbc03aaebaa762f78b352f9180670d1a4b0c4f5535e66675c0077bac5074ab71fe1fb0853272f9281862bcfe3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x068a1802523285ebdba8381900453bbcc093caaffb046bf850580fc9aa96bceb48fbc0a90f292aa63cfb14866084ec6906fbf9a99667a059cbdb60e23448d907	1614954476000000	1615559276000000	1678631276000000	1773239276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	357
\\x5da3770eb4ce83c6c6b61277c18d45bccb84dbdfe74670d45e0b0991853a3692c885903dfe169b4176ff78d98c35df10244488035228a9109fdd419102103495	\\x00800003b05161fb554ebfe6b267cf77baf11b3eba87aeb7cc284afb87053a2b59af1e6272b7b3fdfb7ea3fd85cde07178929e7ea0271cb5763544d27ee2079e10a812a44bb99a77be988e2ccdc8cf72dbcec115633bd6a4d9519086a66ccc996ec9c17fd2a365567a07874c2961f2b64027829a1330368566ab0b5650dd8e0a50c931c1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe04b91a876259517affb2e6c57836cc8c76e0b19859baf4fee46f3ecde0dc14bcf347f13d84e839f55d409c7d0962d716c62987d075f3fc18a4f17b0e888d10c	1610118476000000	1610723276000000	1673795276000000	1768403276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	358
\\x5ea73365eb55e6099bd5e21cb657efb70efc6881f73f160f69f25e733ec0f9bed4785b7da8928fc0bb8aa8060ec131ad5e55adc3939d9196acba1589d812bfce	\\x00800003b111c068dcc69e10788a6f62f692bb4b13bccde6f4479c3d5aef1070251419ba84864c75f7e64b7e5b0501ea7f989e7f3a80a0e435801c52aff225b5dd3195636856bc4c967f198aee42c884dc60eccfdaccc0183de63c44504078212132094c389fddc65464188eaed4a72622d558fa22001f5220a6716149726bc001c6814d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe94b232489488616bc9be3eb3979a227f900eb8eabf7532180dabddf5e555cc574aaed0f92dcb6ff05787c4ba8647ba42079dcd6813c2e34402cdf2f3d89e103	1618581476000000	1619186276000000	1682258276000000	1776866276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	359
\\x5fd3ea665578d5bca9c73f0e029e1d30d71033d6f7487961fe0849f15fce14dde27edcf2158edae7de2d305d4bcb4c1fa73a511201c927e1e1fbbb627373e97f	\\x00800003bba90a5d50bc9912e7350046a6ab2f04999664622c7e0a66b0fe2e39180e9344a97fb2bca5ce1a9f46a902f375d81fc1f552259f2d3471d3e8ffbfb745c87628b0a8b9333c1323afb0e3f852e2e7b33cc6d8f499142e0aef42bc399a5868700bd19a81fe49b24eec657f3a2f629d2312da18e6ecf8b8de041254e4abea64b10d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x848eb8ea8a2dda7a714f0d9a92dfd1beae949b8917042ea70829d2bdba879a2b13cde2ab24b6bf3255a16a75a69676645ffa12946020f83c5bf4915ec949f800	1623417476000000	1624022276000000	1687094276000000	1781702276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	360
\\x63cbeabed449a72638d8318e0142f51259213ee250317764bdc0ea4b0f113b86897603ce8b261e73474b56c637a8390cce8d82b057d28265090c50b513e9c0e6	\\x00800003d7627a229c02b4175a8a797b292fc411984df069e453f554fa428cbf302f91b127a7461d5dbb869acdd54bb4e9830345468f887b276496eb30019d8226ac29f98af4e1b66da86ca2eb6fd70db03fc328099932af22a002fc2d960c464b03c7649ff7ff0c3a011342218cd47e7638f9ac1f5ac45667be27f0bfa634e71d851005010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x68758ba527698b9d1f055309ec1687b5d536105a2b1ab8261434162916de9aee2c0576c0a86cce1c88f053e8106a3b6b1713a60ffb828febb559f47fb12a9d07	1624021976000000	1624626776000000	1687698776000000	1782306776000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	361
\\x65cf089283d59e95bc0bc97787d96e62a34f17730371248c3cb93923c3f2a0c3c01e011ecf0ef904302de34fe85049e9d0a6e0e09ee8571da60b45c684d2efa9	\\x00800003bf5539a42475d1ec2b1c25da7bb393f026ad100b6b62c92c373373e7ea5cefeaf84f8cf9c759f00e9a0eeb5195877bb3cbd262bdbd49a18d951af48e38cf5238f9f76ce69352c4d3fd66cfe89f5059ec240630d896e870032b34e0041a8b7f99420464b410df8c8eabc3e897b2ea13ca209133b1299df7032792a4a9e23550c5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb830e4eb147211f6013769e8a09c809c31916e6bb3beddc3c34ab0e7d28109743a8ba11861c4da1b327db3e7a01f073f1154f2bb3e62aea383db0d2593f6530c	1622812976000000	1623417776000000	1686489776000000	1781097776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	362
\\x6ab7ccb5d78e4db65f80c12a83b939e80f174d30177c7cf5fc2797f7e22b45dc8e9911878941dca8e73aa1411cb0508c59de9bf0a5c33b3be15c7f60ef5efd67	\\x00800003c6afda5be086673f8baffd785fb177628d71bf541a0d25ca24d579806724671b61653a042dc7f0da9c2e2bf13e5947a5feb03052b055b9a66a44179d88c62cb9c697f5f052e9baf43488ca85a40dbdf0acd8383e77ed871431938c6bd1ecbfb06ce46db2c7cba68361b8628c4f03a6802714cee0c772f50cdd58e876c6caee9b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x4598f910f8c3101843bcb118b6962c5eee9d713ba65fb5c591c2fd21b21345d504b80cacd89b3e1d7408f3ddb7e96e3bb4cecd786d4c29ee4688a96133582f0c	1616163476000000	1616768276000000	1679840276000000	1774448276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	363
\\x6bc7d6e24392c347ea5d352c1338642ca3142640f2873eb08e72cdc39880710adf5dc961df28e279db2af15b4cf2b7fa4e34f64824c0ed6631925bf824ddc5af	\\x00800003aa3b5cf0349f04846dc0f998040d661793d732d23142d45d47acac4df4386830a9b09ed9cf0874545b4054d2c805480378f865f450b0bfbdb2dbe3fa13d8bfe79569eaed6ea21a8e014c574880023227f71e9020932c3304ca4cd860c774c6e5bad8679cdea574ef375d072c1da7addde6639d5518d59f1e415fe2b9aa85c017010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xceaad47632073664eeb9723cc86ce4f2c5c028492fc0233d57fec3f5ad631d1737df56dc43e7925a7b84fb684cde2e50493d2de154cf4d47ce9110a72ba23e08	1631880476000000	1632485276000000	1695557276000000	1790165276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	364
\\x6e43c0ec745589db32ee63f0e012159281bae10c5aa4aa65fe8a29d418f0edb8f7ef54aba0bd7bfb76b09f18ccff0a9ce7deb8ac04d7877ac27dba2c0d9abd87	\\x00800003c689606bd87c8460ca14b4adc3ed6436b1493c22533224ff2e89a0705e9d5f2730faf6438132aade9a9af5664f6a67263a39b769962e12654e19a0625164072a9654a068b83396e7c42a71fec8d0599d019ebd2701b52b6e9bdd598fc411cb8d315a3cf398fb64a63476b807fa22c13348172f30e7dd3e7b0345a483a70231ed010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9ee7532ae2f97c44238dad6c4c7b51f8126ab7af4c471c22489ef7d7ebf3e4e8dc6bfbeb2f548d7940d46e828677a8f778cf18457f1cfd3f8d6ece518a0c000c	1629462476000000	1630067276000000	1693139276000000	1787747276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x74bf789b537b34c786db413aee0c481c897abd4b31f96b600da84d805c16aa69b39a86f864811d17f96f34f5788651470716e696387bebf2490a2901f37cf007	\\x00800003d181da3a92cb123048b395fc2e8fd99fb306a7ac5b294725428ba66a86fd1d482f4dd545421283e43ca4df8d7cd081cfc50fd8133e680fb59a446f923a99768ab71c6d5e05f70c5ff3ffec1a666fa70b8da507bfa34f06aca6b34a782b43a81ae669314dd47aa0fcfdbbdf9578a92515a2aa405120973dd8f186966b70912a97010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x218ffb3f9653b7f51c4cdba8381c1a92902b297338ca153f47ad0d279c174fe2a17e50d78a75e783f0901ce8a148a175ab97c13ba111eaf1fdae02c7925f0d0a	1619185976000000	1619790776000000	1682862776000000	1777470776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	366
\\x77475efde0c6c36eee0198c7726e4633e6f836191c408190ad6441d8416b54a1097b48bc5b152f9f57adc92e9f15f6a1a375cb79b28115812b2fc244971f916d	\\x00800003d8f92a88daf3a390df23a47cdb0ccb6d780011cfb234b97b27c835d7a944ac61ec7f7d4aab823c6b54cff8c45bd083b8be11c02139152f67e22c595eb4f05e7a7522b3c4b686846c88ce9c0c9cfc2650e13ae6d477809a26ad931e2dbb035d791195942c6ce8eba985be652e9335ca54c58688eefbba25d1b2c13d781145a80b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x35a426a7131619ba892aa79e6ab0db963b2414648f39316cf5a62eb50e33474f8bbbe620be88aeea56d19b913e678f5157596c20f999bbcf1cfd48d816c6d00b	1619185976000000	1619790776000000	1682862776000000	1777470776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	367
\\x7767f3e7da2dc5bcb74cdf91c7bb83d968da1768beac4bb8aec503530659ee472d8b98393ccdb1529579ff88fac991c9846152d3b417d8f0f7a5be83aa6773ac	\\x00800003be82f0d24b7e9fa35acffd928e1efa4ac94628d3a5da18c4a19f5820928ee78926cb7a7419165d6436cac3d5624c43c03846bc563869e89680ac353dd2fa021547352c300a92153bd2a54f35184d675d9b01110efdb22da41d8ed1060567066e9d86766f30a5232b5770c2f6549abd37a524669cf6bd41322ce5f437144e3165010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x9b26edc0fae97022ccce310efd2f66fd77cba5972bae2ef2704868a3665fec3d63dee33c6a89e865639d911e49c1da42275a25188d20f7d1cd9e39de08f46402	1611327476000000	1611932276000000	1675004276000000	1769612276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	368
\\x782323c71ecdaee4ac0f0c7720809fa0f873e581b5b309ed2f1761ee8537eef677c0ae8b13049aa1eb7ab737cc502422a8b9b1aaf0c812b1c9939a2ba3b67a0e	\\x00800003d5e77b245167296c92c4a2eda6faa706288815f93c28d43fb63e651003c07a017aca8ce2affa5a2a08dea8a3765070e6da379dd957c79d1ed266b64567a00f5aa4ae2141b9545be890f429a199ec1bebdf8fed6c1199cc51cf7e901a74d9e70a58c5e06b31839c8bedda7d2001c037a720aea7ccc2384b56fa3539263aa23f71010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xee044b2252d59d668e432ca22f84daffe8108d84f6aa9274574c7deb2f20336c4af4bb73ef7466700d9af53098a9a81a022ab895d33f3901e9ef325dbf8d2b0f	1633693976000000	1634298776000000	1697370776000000	1791978776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	369
\\x79a72286e6a8f0dbf41da26155a76e205e1e41ef4f3906779d1ae758ae11726a48df0e8d4c0f29c6c5921438aa5d6d1b1d8ce9ac41132e48e6a9813baf70eadf	\\x00800003c03a105952b3499b4948b1706ac75a368ab86d74a4e6f5151c6139e049259d1259e34ef16923bdcec313bf458caee6d184814bedf5a57cc650ee4c324438c3906832999784b2593b0942e9650fda762fb4f2a9aee099bc20e6fc20dfdf16d773e15463e570ec0ab83f0ea28b8d17f4c9ce5e36f4a88aba15475644861b85acd9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc4376c03a0ac78adf345e1dea01027a469c4fa802da42973df1e2d6f6e0eb9aa34f6efaed66360c911971eb8f12ed055946d13781a829498453e8c9a73752806	1633089476000000	1633694276000000	1696766276000000	1791374276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	370
\\x7ab3ad234ccae76619d9d93990a7b3cc7d0eec5c418f2038692f89ceec35dbdab2d317b3f8be0dbfae0b393d6551046dff055ee9807b11b998ed14772ed36b0e	\\x00800003c6922cd281c78bc8edb0f5a2efe56d1a12306793641bb7e41f058e1e58513fc162b581b2ef9016c29f36da4ff61cf768a6f0637b1aa7483c18a750fbce572964caf7610f0a2faae3d6f1110e60ba3ac08d90da84e97c8082f17ca35274bf44509a28e207362774f96582dc80acfa5b3ca560bed6249a4f09a87e5cb552fcc421010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x0474deacba4c32d9a84ff2b4f450b9fe743884f8a5df4d3e8bead3ad02a9317bdb597564fda3f3664da4ba9bd9d9c024e61855a06930a580c0c38ab4e38a9507	1610118476000000	1610723276000000	1673795276000000	1768403276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	371
\\x83c3c4ce25c6e47c1813605885c17e3c386bfaf20b308bcf45e6a0152791788b82e844cc95d3423639ee40a5c0b42a38f488dc2509ed29231233eedd09ec9546	\\x00800003d218a6f4c18aa55d0ecbb11798f7c8c5d4817996e17874eb1c2e8b5a5e2be48c4d932b202bdac6de07a0c9dd9aafe159b783daf367aa6db316d2acad115666d90c40bf8e7eced2d9c46a686ece069b0921730d09a47bfb0473fec06348936289984f50f0f8bdbc4f550356a31d8159cb20b4e90b09848136ca0885314d6697d7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1b82fbe2a213049855b0a09d1122b9c4f08bfa0f703e327c05cf0fa670ee4fb8934a35e514f59b08372d94cd33ba503c5f9df3370985ae981837eae5870b620b	1625230976000000	1625835776000000	1688907776000000	1783515776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	372
\\x882fb39388b5897109a1ba5e33987e01712b664bfaf9aa3b24199d0a1b86338476bea8c49f6c6a08095ed1ac7ece80f41b3f8a9d753c562fa5723be4b9cc6ee0	\\x00800003a730fd3ae981a93c8cbd7334f6f9d54dfef8ca2b8c87eb20147e6e8c6e000992e2eb4a1165b8ab51e389d036329e0e9b2174459bfd2c3237dcf3f1367f8535d9300bb59b9c140ef5b17926b8b3b2e616627fb4fddaeeed7ca1c5ad03088380208d5994b2482be688c5e347f676bd8aedfe06259d695afb5a98d18d81f84bbc15010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5237b49258ec243c51e3ec913b5101c34751bba3ba7aa6f2e1bca5a70e454ded72d5b27338c82854cde00767fb02fc44b9818ce157bdcb2d08186c860128af0e	1631880476000000	1632485276000000	1695557276000000	1790165276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	373
\\x885ba2e4a7c2ecdf1e9fb1a04143e29ec52683ee08396a47e78f5eaaaa47907a862dbd064cb0c2d3f045f0b52b2fe2feb31a8ec5ac1be479db2b3e68bb38678a	\\x00800003e72f1babf2af39f5d13b37005643a2886b61c8d33f7546aeee68be08a7a833f82dacde34032f40ca17d305c3435bba1bf51ba7cee5214233a3c38dcf68afb07584b800be1ad228a9ad133ca062c8cff3762113b86c9cb023bc29ae90eb1fdee715c165ae3d9ac88c4d3aa465feb71492fff81e56dc8992c35b6d54d78a9a1df3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc36648698cca0f8275d40027cba61842f7dc09b90b81e5414022d4bc3f7110f55333ac1094d3cf861b9cd7b974b59b8816d2dc8c89d5064f7e26f5897af42001	1634902976000000	1635507776000000	1698579776000000	1793187776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x8c2b2db8f67050ca6e156d5c3944e413710bd22fd9de6e729fb3ce8fb693724c5f7956edeacea075028d0a4f8b909f980b7f954024158450583b5b474b155edc	\\x00800003a5715386b997dbae73d5ebc765ffe8652fdcc4bf4e131f40d756f2b7f32031366b922b4bee3fe00fe7f9366f200e860b6d0b4210b7e9c2c6c095ceffb6b1eb75c3b1c0f01887c8a13be9a638d44c2be8abca58d352d54f1f982139a014c449fa2d7f95b75b9f2276cbadea83ec1eaf7dba384fe81fa93ba5b0d966d7602e93bd010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x51771d9d075603d3b0bbd7feb6bed7b25939448090d76fea0622c90309e90a8233f283bd79be1b656347f532113ae857901e8ac9febc2b907990c8b2c1b87d09	1639738976000000	1640343776000000	1703415776000000	1798023776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	375
\\x8e8ff4bb48247c5e1bd7485e43345b2ac95d7a2b83f99b30299775d353ebcd5b79be7c3bd560ed727a0e1a28d87ad44739a36ad07b1d2de0222f170db877496c	\\x00800003bdf6639cb266dd10af6d41d9b732c3467fdd3fa4ebae52197a75169228a5433ea8c0eb96c8d441d006a4ac9c6bbd37312855bb751e85405672834e05c85a28a4f9785d515a85fd6badb6e9d0d1acbc70ae0f391bdd97a4ff2439e52afad26eab62219599b3891e2f2bbf37f404f16c3d90ff463950c34ca59506e0dcc9046713010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x8fe8dd2443aaf3993607fc857a6d36e6e2c42b6ff89676617263da2701d779de60dbdb396325c48905dc82d18659221e135795cad5761c132342a7a469c6990e	1625230976000000	1625835776000000	1688907776000000	1783515776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	376
\\x91c3c57c5ea86683de7415750a932e48335d07a1af5ae463ccbdddabf91c687cae4a60d9398da61ac9fc42dfbcce05f8b1173e3c05ffba3f652391fa215d72ea	\\x00800003b50bebea3e69b06db917cfe31a03a011fda8011fc08f28ab89319199848b1251f266f41b1addf1c851e6d9a075cad5d21191dd29501d02ce3cdd5b22fba0c1c6ad29d039a50d8c83f8fa4bb9efa76011d3fa1cd20d5b37a21c273465a33d0b1624f55866fa9613eb02af68e396a452f55b1a21ef827b035e9d4d1a973c71c235010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1711c794e3027c5bb3e1516b67ce517a80f83186795716f585351bbf9ab469ce9d2a3a0f960d2849e2310d36cb94c15303b3f70db34913e0b8ed049e5d1c430f	1618581476000000	1619186276000000	1682258276000000	1776866276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	377
\\x913b3e19e9fd46797238cc356c3e44d162bafc05db8444ffa4fa08761ac8cab593b48a36c6f2000d659c4b9cc9516adc7c5ae09b10b68a3c19f2840dd300f90a	\\x00800003ccfbc47dfe64cdb2384d7a704fd58f2c40cea1ab81cbdad4fa893e8e3adc73f7e052d5bb7e6436047f536c96f7bd60f9743f28ce3b35142dacf3a3fe16dc8c4f94480fbfed63a24915f6621a2daf231ebe09e283744d43bf49bf790f43de033847752e4d0ca686fcf2aa6dad0ecd31b5e307120a1198307194289edc70e4c905010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5e60a59ddd56cb1f784a0162c08b477865fc627f8cd976f746eaf4c4a1783aa15c29369e2ba07e3134140ec0df3516d0a05fe3f865aeff9383666420c7cd8407	1627044476000000	1627649276000000	1690721276000000	1785329276000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	378
\\x955f84afea9431fcd77bd3fdcd4e2aad698b1bfab4733476425f68e095f756cf14f647b8498ec637fbb799dc5a9ee67debcc81046bb3cdbc39bae905fb6df192	\\x008000039c0ce0241628b6b80a8d018a900b4dd5dcaa3ea484bbf40002453404052128910359a3a5105bba0fe64ceae518e6f5da13c915603cd284bfb72ef5381cda9337fda3660ef300a52a963239ca563d21b3a36f96c127f69ead9eefc4c33803267c978d66e551bdb540a63451da6002660df6b620a5c5f2ea0cee82f6240daa76e9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x01bbafb572cc7fcb05bc957ac6e2730aeebb240dbe260e5290f45721cce8a734c22916369a0cd129fb4433a344b3939d71c6351221a21949704cc50585484d0f	1631275976000000	1631880776000000	1694952776000000	1789560776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x98634ad47e994bc39f0b33737607500f8809927ccd6e8f55ab8533d9c4e9be9423a0c0e89a3ae3c0735d6347758b81918ead699d70f44dd984ddfc2a6afefb8e	\\x00800003c9d905bb8e792e7d3267d2550af29d96bf0187544441c89b18636214f1619b145e88630f51c5c1fdc353ddf085f2236ff6d00ef4f7392cc98502c317babf2a2927d156779f5494f68d0175cbd4e233635a342065abda9e26a4b8fc19511e36fbf054273c77f35c767af7cd84a65f248bfd166fa3659e33efd6f129b3c61c1fa3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xefe972fed491a4f679be43098bb3fd7499eae302b9c9d15513f592458bb4745b255076caca01c089ba5d536a6ac87a3c96d5f6f83182c65f4294efaec8fd9f07	1637320976000000	1637925776000000	1700997776000000	1795605776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x98033099d489d937a51f677e2e75ffd3fb6cf89fca728c645058c3e7556c4cbae2d41e2617319c0263cff67f54f962f53f743cd41a7ba4c2a0c90b1c23e11c90	\\x00800003d9b5f98b9dc45ad06b6f6202e3386b152aeae10c25c58477579ccbf2c17583f82ab5ddee59e4b5a212592de13b1b4f7bf6aab27d147477dae419eb42ef7a8a6621f366587a2340085a395fffb04efd7ab9db70eab47d540be28b4c3a4ab616ae9677795d3e9930a5823bff355a331f00c72eb1fe85b861b682edfc67f6f00ff5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfe7cf7aaf6c402f5e733051b5a412c73281e31f4892853b18608a52081501b337a1bf26b9ae57dd129d4c7c8257899a19b2d63005a3b823a66ec8548b052c70d	1638529976000000	1639134776000000	1702206776000000	1796814776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	381
\\x9afb831b9cf2020b328337281ee937d773484979fb03c662cc463885528cb499f7c3ca61bddb078860af58e8298d565fe6181285a70503f016490e1059b40890	\\x00800003c4c071b6a65111d1afda4d85972ec376ef49aa09f4af067f6b6c9ad1d62e315d908bc7d319c7ec1c279de344dbd9b27b241bec593a59ce2fb32f621563beaf7a412c4fa1f840f634cfaf52425c12582464955804405b9394f2772477c7e16d9116bd8c3b27a13b2308dffe9cf604a9c1c59eb5b0346e8972e09db60aaa5e5671010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xaa34847ad41b5792f29ba4e83172e81c6a5a458f8ef7ce9f2d75b5d9319a6510b7cd1812dffef0eb5281f44fe2c918a90781c5547f2a2b626ad5d5945de01407	1632484976000000	1633089776000000	1696161776000000	1790769776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\x9a9bc7627ed1a789f15393fd12278ba247f953644cde0b3d6a44642f196a9d3001341af6e33370eebc79b11d505ce802f85d6afd9e321bf66a33b734646a8833	\\x0080000392345b68e5c0f06ad95b679622a286d98c69cf30a8f00fd9510439ee69b675b8f0b8af3bad7a13c1bd0c6db91ad4912e59e1a3f98b15bf2206a8bf0b8d53bd40d080748b3b0fd5cc82abd6f23b8590f7110e033e25769b89ab85ff8a9e18ca03d7c1ab0026e10b3260237999cbc228bcd053758879499a6c4115b5bff1f57983010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1f69cc89868f5d23e7d5725db17c8f6ddda632c5fc34a938360b7b873c2b44a58f9e8ab9eba733329b1baf846f241ae9998ef4169e89cb3806f7420bca910e08	1631880476000000	1632485276000000	1695557276000000	1790165276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	383
\\x9bf36beee041f81917bf46b7d6a39989aed89651d25aaf6458d0a09be5d971138bd853fb980adc60ea7568478f02f2e3557d79e28c77a9d11397e1fccbbf5e9d	\\x00800003ef5ba80eba6d14a02573a75136cab5b605a421e74ae52edf6441ddc37eeea6a1fb462a3bbe547158a9c526fb8d3f387c041e0ad9ff26af7fc266847d6ef9596221b116464f78afd31519d64200442aae7a05357d7c578418efcc3a9e559cb2dbd6f1388a939230c978f24155db034d22494f4a6c371d0e35da18dba242d9324d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xfaa57653393a8bfcc7ceb0f6672855ef4de34f0dc1a3560d9114bc7f178c8f85393b645b6f96f02c71e0df6004768f8d91281f7a7764240f203011b08f7d8b05	1636111976000000	1636716776000000	1699788776000000	1794396776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\x9f8368b5cb9aa008bf9217703e05671d3446bf2676ce537a0a280a4b88b543f1334ba6c8078ccb2246825e4e320e7e701c837b2e3ffdae6d1d87acd85a7199a9	\\x00800003bb54b3677798c02d979696155463be06ece31510224b0066fd094a0c57e39d5fdc01e19c9891c86fda6f0c2368e42ff2e5973e3fbce19f432ee62f718581802899877502b2c33d006fe35e2a23cb8102d69fa6783f6ac984d0a432ee8cf315c595f91fc7068e97ce6643f7dfa2ed1bd3dfff1e385d9810f7a7bdf2bb39c7f683010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x97d5494dc246f2785a6e7e2993d712a332805969802ae3cb284c2ea7f9575b91c885e44f3f55748d0902c00e350bc92bdcc1dc5696e14e4678a3b913710b2e06	1636111976000000	1636716776000000	1699788776000000	1794396776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	385
\\x9f93d95494c3a2502edcea623476a4140eda481b7505ca041bd1136dd1ea91e9aa91deb81cdb04ebb573db8cfc0af63193293526a42fe90d07f1c922ed315e24	\\x00800003bd9c3b7dcedd0cebc5631d3486ab96d5c48aaf693bf75e41d0d9f61585407659f192753817561382bbd8a92d4424ae8db842f97635dc8e3f1cf0fbbba53207d88bb4ada50752b306f7bdd54b9afd20355a76477e06b2c204088c16ff232631bcf51c0630cf586b641e026931b68924f44060801a37243ec499f75eebc486c0c9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb67ba0ff486b76a718c0dd5737936a0f6c20f79051ee53aefec43c7cec5236252af94dcec237d93bd69efb4eb83ab4a99b7dce4f710c2a3917bc374cf5f2040a	1635507476000000	1636112276000000	1699184276000000	1793792276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\xa3df2cc41778fbdbad9823473f11c8a8e6d5e911a5c2a4aff7c34d461ec277ddee947c564c975377690e7a5228eaad6955ae18a7c254a5e9f07abbe25bc0c035	\\x00800003f0369b71b146e0bfe155b1f05e3993640856276785b9bebce78b7643bd9d7fdc94f2f1323bd71b4046ad090194a7a73771d7281dc49dab21fad04cc3c0f7414bbb9a5b04841569e82602193cc27f5d5a8b3afacb53ec48daf9c272a836b92f634a8b4d588bd8cb0258da3b92e025a9bfc7787399b711da9139c33f911f092dad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5ef9428ec3b281286e0ba336e64e8c573a17a47ee87a65e6f3f925660e33cf6b06d5620d0195f00a65b966320ed64d15fea1524e6ad653d20d15f66b8da5d90e	1636716476000000	1637321276000000	1700393276000000	1795001276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	387
\\xa69791902c4415550455031b92f5d0ffdec21e56f174fa362b4f4943c6f7438ea781d7d0d4ebb64273b770efbb07f7a38ba750e2ee4c91a63246981404135c11	\\x00800003dffd488625031d155feedbf92be1a5596d2eb2d08acc79575eadcdb868a5a544d43d6df0b08c79841a673bbe5de95666b460515a434153ac5841b18bad44af58df12486fe429c02dd52826b56038e0a1f784df4af71f2c71f25396c0b18c7fe764f800c09bd8e625aa6b1a65bf7e5f61ebb789dd91b582c17d84bcdf064606bf010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa7dc94908ebfdeb96e9ef6228e53ae33e6f883cbc47fe21927138f58ebd5ba7947bb69f268e15d57a27591e431b4b892bc6b5e58ce896f2ffd083a836c945605	1628253476000000	1628858276000000	1691930276000000	1786538276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xa7ab8ca77efb54375a76b0d9febb759c8a028e3361803e3932c02462a069acb680357f8fd78c9c76d458d58f74483ce8e509634f3d7122b06fec73f73ffe874c	\\x00800003c70b699491c591366cb7aa75883e8201bde9934491a7236c9e9dc8bf50b9efd2400d77d2e0e490b22e62ef733b3514d199f69d6f34942ee00ee9aa44edfa77096752dda0779da59b7de7b87b6ac8a8aeba4fbe40ffe35f3e640df51745a696541bde563de0e4317dbc5cd010976d67bf2dabbbba24784263337ae6f2b4c5c965010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2f705f8560da703c4c19fd1db0f310fc66b7abd4a631712dc6ef732c71226834072f0b41553ff84b66fea178dbc99f19fca7818cf1614ce2a4674973e25c1a02	1630671476000000	1631276276000000	1694348276000000	1788956276000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	389
\\xace74fec7d02a986a17eead47d812e89db61ee0ff332b2bdcb27f9038bcd0fb50212d201032206d213d314a2ccf13fd7b76bc39203170ad31889a14c61e988e5	\\x00800003c1e5a7eadfe718de28c16956b6ba0b67ea4f0a39f517971a783739ba6b4dd8937528f1dd26a2bbde59e6c99d9099d002410dbc687f0fac26ee1877efcdb64059fe780c8120cea8b07b7536fa80f2a09c2db4af2aeefb241596c5ee3e8db3b4e063d895b32668b9b12bb9c6a01564298a05af3419caa9d3f555b2008f754dae21010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf477b89a295e9d43f4da09bdf2d7457eb8c394f3a4be64c8164d73fe10a92885500044b3c89c777e105d105bbbe55dc758e5b7c843b8df8bc895445ed740f60d	1614349976000000	1614954776000000	1678026776000000	1772634776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	390
\\xb20b4a37f3f8f21d13dcd1e02d6ede506dc3827b5be3d575935bf700e6aa38380c9af7a875527b46db776bd2caa58e5bbf35a3e3177cf786f8e685f92e0e5b78	\\x00800003b7458581f1ab2c5a2a14c09bdf645465896ddb6bcd15d0c4db87d6fdbb6d5c983b86858e9ee96d43fbac5ee060f57cd1f8d97635bd5c1a13716cfb151f944791b01bef917ba735bbc233570aa399e7d6855dd90f3e749a2224c37ef4f1872185554ad752e866b4c55c65752c456d9b47a39b5ffa17a864bb5ab23d143c259e09010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdc59892e67bc2a655d32ba7a129ee5a81b4096979b15a4050a1d6e7a16c3a7dbd7d65c3cea3230a766a1de13a063de478b7253b7423583da36846a0a2940c008	1631880476000000	1632485276000000	1695557276000000	1790165276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	391
\\xb79378815331823361435dada01ee70864564a906d227c132e208893b52cf67440009f543a0c709794448809d7a0390f8dcffac8e7a2f7d8d742e6d6a97d4890	\\x00800003d46dd0b1a254c9ff3bcd30043f8cc53349b6004b0a234e3af0684839cb215629deb23d3903f2c7582b5007df82dd12fe216a9409cec27136b9787e29073d4fe41d3c0b50e810a3e4725108348a2379dff6b8582dc0d36691ac118637b3057616e60722ee7887cc1bbcc23e8dee1610abb46023cd156a6de01753b7fabfc980eb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x23cda56e616578d7f95758bcb0aacb35c41d5351385b2bb8ab4bfb8140095e84ad2fa658301b35794974c882b2dd4cac56985e714609c9699ac46b44a0fda403	1610722976000000	1611327776000000	1674399776000000	1769007776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	392
\\xb74b645c85766e869828afdfb6c7986cf68bdf1eabdedaaa45db4f5d00779fba1aeb47a34766cba579272daa17f42b3e4dca7501d02d3a320dec63667a1b2c79	\\x00800003ad2abbead803aa18dda9302077394e178672bfadb9ce75532155b4023780903c9d27c03e4deb49eb4d7fcbc42ee8433615532bd8a0a8c15401114b65e15a810ef4da2c1b2b05938a9999d16980591995b022428357b44b54c64f4d5d3bbd7de466e45bdefab07c6599b65c8efad00361be3249cf5fe47af0a64e0fb10a1664b3010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdc945d9da354b886c537b76cb6ea32261fd95579d771eed2a7dad6fc4a2db5ecfaebc40df13a2e6d356bbbbfdb601c64d638458b46736a38e2968d1aee20100e	1614954476000000	1615559276000000	1678631276000000	1773239276000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xb7b72ff6afeca47a92ad0ba628a2f78186afacc5e335f0c1dab031996413e2a6330d2a82cd7a5671831a202cdc2c91896b443a34f134f5225d57782ff8184fb9	\\x008000039b3f1e5216d95bf01f6d5a3f0e777b49ef0571a1767e583c62d03dc8e5b927da32f719010ac62adf79f5341c24f33aa8f5a2d2b3363a5546d803bf84e0672e7d79640d88cf1a1e74816424f8c653aecec8220b0c55c5ba6c84e195bbb64921d5fa5d4443965eaad283ce3ffe97c0d08031772a725566ba8040bf0a304ecbea1d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x71d7e941a52ba5fc57d0c18de46ca7a6fc1ec2f2794600039bbfdd2de98f0e6f18ccd09eca482cf7db28982aa33370125dce47bb2ceefa7890c8503df97d4808	1611931976000000	1612536776000000	1675608776000000	1770216776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xbba3dcc7c67f65febbe274af3837b3e0f9382118c21f903c3aa9cd18d4b395b2c3182917dbd30807fb1a9f6c8ada20ffb75dc5c6021a0e7d21a8816d694a8ba1	\\x00800003b4ee26ad346e461b0dffc692a212b32ef7687d1881301dd7ed0f0917ebd19a4994cca01059495d048349a630973234b178eedab9ec646f4560bc16d5cf270048d7ea9f96be25d4731bc3f289d8d677025abcbad404e66dfc1abc07557437df11cecc90c497c006ad32fc9a47219de4b712e8db4ecd0ff7e450a44cdc8088c2c5010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x295cbbba3649c3b7682bdafe825a63ca311a92fe7264c147d1ed149af2e1c2c0ee05d7c6a3ab96f8da760d63b4cff89eafaee9568eff6fb56f2734c64f671a0f	1628857976000000	1629462776000000	1692534776000000	1787142776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	395
\\xbec7ec52398b4628936e6dde4322aec8597a3007fd00b3b574f9126710f6ed1b0b990682d6a8cde0c9674e661a2e74dafb681fbf9a8e4f7f7de1de0af4b2be2f	\\x00800003bb2e815047845fdbdd8d8173c440d42e8b24df55fbc60a274ac6e7993d9e00281c2cb468ffd35518560c07797558b98438e5ca8e25423321011b4170c4981d2ca156535e1c869bbc8faa9b500db1d7449c0c72713f3e3bb0d7c0b7af5a93ea3defceb61e123c7f6419200f5512a4a50a015b7e9d6e6cd3b4d617ecc5232a2399010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2abab15b881c37e7e5755482157da33565fdb7003f31f7242951c45084c94e6a8a2f9b8f6ef3ecb39e52452ef0f4ce8340b1f67b07c6d7e459b2fe230563fd0f	1619790476000000	1620395276000000	1683467276000000	1778075276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xbf93f50cbdea12eb77a59368772caab5c94d6bb8b6d0a8a86895a7d17fed1232abaf78e8ada7d2f9808ffe7626cf1a7cbc811de6c0fef3143cd0de59cba0de21	\\x00800003ef149ce8ff91cd92928f794cd67e9128e619e42e91ec40b08d536f6e348db75e6c992fe75f171ed3e76ff2bbd1ab1e0df08c2b82099b6a4b44b9095ac5331ba5210940c4925876c29d43d124d737d910479fda431f58c16d907d4d131dd0c81796711b79e6d737b9d9416f49f6a72bf2520d683c5b828df4cb9e8f5e7f3f1b79010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x178c2e007c48a991b9d136029eb22a746a14b268a74c55fe4da0fa185c1557c5bd32d6e51d14b17f570ba776b2ba315d53b53e0b46b0e6236c338260e19e690f	1639134476000000	1639739276000000	1702811276000000	1797419276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	397
\\xc05fdd533b67629fd8f0df2055b1d9d6535d0faefb0974169767ce8ca9165c1523b1f1f5905e7b5ecc87fd0bcf15bce36376fb81b07fc81809e0c526ed3a6bc4	\\x00800003c6dd679a0239fcea4881248029c662b7cd5ab2d07273f3deffd55eaa25e2d41be4af578601ed14bc8df6431d5f6db20a4867f16e4f637a7c3448556b7f7c338532619f4e5d01b960586d40e311cb1f5eae644b503c8615a8347f21a6091baef7d5d1888068ec288760f0247ca5ca7ef981a3e7a0f9ce1b9fd042c04ac360db5f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd6e35dfff84bc32526ce6ca49562cfce7853dd68f4f5b7916ec63c5a459cf37b4310bb827bf1e71cf6ed8201584513d15b8bb625b9bd017e5b6b6c19bcfc6f08	1617976976000000	1618581776000000	1681653776000000	1776261776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	398
\\xc46bc512e6a5a5f4ee06fbd251ed9059a2befcdd4ee7fcf639ae4f65de277038b4fd4c3f27c37ba92fd4d2353cf846f67446762556d1b8f630e530bc00a505cf	\\x00800003ee416f651204dc0e42083326bb12aedbe52cf30f2a55e223a976319c321472005ebdc7c592efbbbb617010efa5afd47d915972dff57f182c8c582c73eb1bd422a4fa9d1ffd6228d43e2f74605abd34115b2e71a16faf004376d3b25423569f6f6def29959b5f8786c298ff9d1f749fed0ec279b78dc1e8a0362bbb7e29e1be57010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe3d8294f38f30f7e971a53a1c024474db1c95a623ac14cdaa686590b6b2159a3fb965ba18795f79be902ace07304e27e9de5e4e1bdb0edb643fd4dfe5023b50c	1616163476000000	1616768276000000	1679840276000000	1774448276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	399
\\xcb6b563a5c9c94e7d847e3346f25e32c90370c8eb3d1fed376748a1b04c0c9d5c8e8ca1ba2e16a44ee9e0e805846ab818ad2dab99fc82bc835a9b399041a042e	\\x00800003c1de2da0a33d223583cbcdba9a2973c79a92aa9c851a7e7185341d0b12da81c444233fafdb053f4bc1bc9f735b7a6ce9b5f6e6a1c6fc22ece13838c1f763c75d0a0c4048024c259f19c19ab1cab63ba0a219f991fdfdecc8f6ee05a494b2fb98ce33b7c678eb76a4604b0692465526b58b3aac84a3b815a4f3d442587607eacb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc5ef3b1d79cc5a94a655425d3c7f70e267f164809aa313e27c5985b8e6b5dcd2d5c2caed17a85697a09e50ad177a530a91effd4e2b9b63e762e128be58ea930d	1629462476000000	1630067276000000	1693139276000000	1787747276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xcde30b2d991649591c20879f8c607fc0c3177051fe9367f740aa3aa860b358faf0a08ed13fe9aed4b466f24c00129b901df5f0eac75eb06e07f188faddde5a1b	\\x00800003bccee2835ce86878d073f8598e5ac4fbdd152a95636343b9bce21cbced953a4b49052ab463794fff6f7d41a711efc3abf799aa089185f845150e4e5dcc46f3e4a9d3328704acbff905deaab8008fe795a118f4108b55ae345d3af14dc73a369e604e1a35ec520005f5f4e81bf84b347113af7b021cfbbe11c3a349a12af0a2d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc33f8ff190298575504b2389250b872cf5922a3e6404794a0494ea2fb72d57a8fa42a88adf1ef94d2c2768add13e8cb7abd3199a4176fad69086b34c436d010c	1640947976000000	1641552776000000	1704624776000000	1799232776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	401
\\xcd47eb94d8a24edc6c95dee269d4ab823c1033f7a06e2ae9bc1805e8f4f5834f9f91feabd1b288fe317ddafc16b04b2ad5c37787be6d3d860f857f2ac8580379	\\x00800003baea25d42128c4c31b6d533a48a6a31b9e44083859d56ab1e09a3063206b7fc1329ef36fd0ec8e6416ca805694527f0abe587260c25e301ac60e6532224365cd146e7e3e8d5fa2d50a59d97e7d2e0819fd1eb617a7e534e85992c72f65e36243c6fc1ebe6938c7051f8b26d21f110869ad2c2ede76e1fc49ebf3de74a22698af010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5c4f3a1115941cbec4e26e8cab50920687be3cddf4a320188fa6fb8aae3aee67e9dfee672ae52841d1821b05ec6650b70d037c3fd9952b9db54fa33a6bbd4706	1619185976000000	1619790776000000	1682862776000000	1777470776000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	402
\\xcd0b5d02d37b110f0e7423d62d33a00153378ffaf1546bf82e66068a0796200ea661774ea5291e11f94719ae783951f4bf02032ac22203a08fcccc52fecd941a	\\x00800003cf1c0d746989151e7ed8d1d7978cc9420c5ca1b3eb3b24546d29127308dc09d0aaae83551c8e54f5bb538250b9ff80c698cf9a42e26a96ba21d496c65372c295e1149e35d1f16d77574ed4e3dd36e947769c3df7aa6ca7c70a8b086c0e4449c959d5e7c40515a68f28ea083fd268520457a0ded00c609b5ffac908e4ad8aa0ef010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x714915b6588e9cd6e7bea2adf78bab21b02a1dfe79c8878b855b652bba44526fee35d01938c3e694e381ee8c9fab3ee528c12f2cd9151971b712d32c0555bf0b	1623417476000000	1624022276000000	1687094276000000	1781702276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xcf53f0bf2c8d8fdffc5cf68650de9c3b987dca2f62d64b418301be1d9a31349ba4096d7f50ed30b26a65211e361e8ea14adb2cdb3ff1c23e09853ab1df65017f	\\x00800003c2aa5cdf580d87dba90ecca8aa4767cae556ca5bf14527dcfc9a5d7404ebd131b6e97e41ae3e3523ef0d64aaedeb052a9d37a0d3cd5a39d50f810c695f82cfb2b703d4183e6cc920c7b22ea187cefbdeda6e8a86ceeb30133bb3a769b58d86b79ee5eef5df939cca059199024f53260e1d01c95efda7ce9e64d9b801e94cfd67010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xeb14ab9783d419c98852659629e40eed0aca3a9416d3984a47c18151277e2504a761704c4560c34d02e1e2b0d898a8e64761b8e0358f4e613d4c44a81f601a01	1624021976000000	1624626776000000	1687698776000000	1782306776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	404
\\xd2878e665cb1c790f6191b0915dfa4455120587d5c72a6d2506325385529dd1f4020a6e44af5437196430558526fa5d43b029cfa1ac1579d0a92277162482bed	\\x00800003aa5539a3a8c32b6eb52e1ffcfb302c84bee82d43627b207ed921f30d6a290735f9f471d11b172e30658b6f7e714d5393acb6bade2e2d5d648ee1bfa9ea3ff1d479c1384c5cb5e3882f30d2964e87979de2781bf2ef6a981fc6c264e0269769d3fffbbf28cbb691ddedfbe12a7f037e1be6227c88bccc87f54b57a6a724a9830f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5f6817bd88c7b03cd6628510dfb44f1b4f0186c804397e6201186c5ab7c909419c9f14f97fbfbc6331852581b30d8eb611c8a808fde195939ec9447860ff160e	1635507476000000	1636112276000000	1699184276000000	1793792276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	405
\\xd4a7c7141205274cec6b507a3f51491d103d9c3a8ff0cb60525c217414b6a78aa57eb75f6b90331c06c0267582defb90b326a3956289de5c46f0df08dc362dd9	\\x00800003988ef7a136c49c107c09fee4ee85b60785bdfb0bd12be2682a514d6ecf52e1c39a4ebdda7c28c7d9f410940f2de7a52d420d76be70620a5cbd66c4dd28170617589c7fb5ce6ec3d23ff32b503a41651601d9781b7711d9ea405f6489b4eba4a2cac4c38a31daca0e39624b1f58c962fe9dcd7913f4ac3dc0cb72a85da7a60f8d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xff35bf97f93418f72ebd905d4a28a9df47bc120f4169a5a55a8f7a7cead2e84a817b87f2307f01d5ee80704c931052909f9ae4726a2f4d3509392fb4121fbf0f	1613745476000000	1614350276000000	1677422276000000	1772030276000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	406
\\xd62f079a698092e36fbb1d4176f3b66b94cd53d0e92d9b3ba7110e2ae8aff3d8bc039927782134ece3b8cd36b7e2b1930ff32c5be038fac1e28ac2b8c35f38b4	\\x00800003c27be2c84c2e4055930342b9214606ce0d5bad07eb512e790327e482db52a43f9cb94d825799aac0a180da94c9c7d3b9438527578e6ae8ecf943fc847ecbec82a1689651796ac0dc8fd31c9631691762363e3ce273d06a198ea85e28f17a4461153a4f3b81219b724a5385da243bbe879bd0388793ea0519a99686d2851821a9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd9d72eb59109479e1da385aced23748009775e12515f00bf21bdf52319101182a3330b214ffa939835e4081af3e7ef10949e5345bb23f794e0584a114dd30905	1637320976000000	1637925776000000	1700997776000000	1795605776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	407
\\xd75fb4c6cae14b7613c845153a9bd499c7c9fa10f3b68f169d67c125a77befd3aec8da25d6f25ed8365925e385a3ed4c231799b985c32f8f8c1c29efe49f36fb	\\x008000039bea500c78ffae9f8b1b023dac26931adc36201255be168152cb94e134df87e816a5f8696864fee4ed5faadfaa658563d41e81c89b34d019d3e1e8bd106a373a677e73b459442d78836d23b9e2d29e25faacd5b6f2ddb43c8ec5bb8e617f3ff12aeb0b59054a755a0ca348ebe7a732d5299878871b1851ff7ce2a28151ee2663010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x88960ce5a4dcf16b4b3ebfbc63531bd482325288c9d0512e489d3352b92d971a5c6841a3134c71468a9f4886a0bd3c2516ca4cd3029b421d5a3632fcc5c7580f	1613745476000000	1614350276000000	1677422276000000	1772030276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	408
\\xdaff8ac2b41999765ab45cf24fb2ec4ab44b818a8d26ad49d3609607b766d8b840c9d90a65bd6e401f77c5477f6a636dfa059f56878b63400d0e96361d6cd977	\\x00800003c3a2e5813dbd3f521e4c21d597a8896ccd514877cf6b6a3282dd6b7e8bcacb309d9e101488e0945fe1fb83d7316c09d1160c34291be794765bbf7f2bb2836e9730d0338a1ca84146f3799d80276c5ae9b216d85ed4d44335767dedbdd2bdc18aa743403bf18cb5a4423ec2db0d1e5f4db13c118c5ed54c1e5ffc3ef50eb0ed73010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5b8afe32649378e4d287f6d822babb346ce1c2adf21140ba4700908640e03e776b4ea7cecd32d9f6306ec4aa7dc06b55a7ad87bf6e082a1a56c7550ff00e3004	1633089476000000	1633694276000000	1696766276000000	1791374276000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	409
\\xdb5713146826ed7083f73988cd9580d17ca30826f670999c94d06c235a07f523110d182d73d28d8091ef823e29589ab5dc7b4f136a59314ad554758848f84d67	\\x00800003997e1bc3d0bd81d1ecce73f14c02de6d5570982cdf59046e2b078b6f9c14255c66374f3bd662d9db4b4603040b7f0b606c7221ad4b08b2fb4c4a61c7cd2da1c22745fc3ee22397aba6ac034354ef522f5b2cbb3c56ecb0df625ba1e20702ae4670f2ad7991429781523ef863bef0faf0ded0d0509338506f0cae92b5f71a5815010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x1305c169636f5164bed80b243b33cd816c586660bd1d2ba1a21eaa568c68b960131f91c23d26c4ae3adc7969d130b081caa7184d0ee1c52f6dcadce956b2390a	1622812976000000	1623417776000000	1686489776000000	1781097776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	410
\\xdb2fd12616a69081dbfe6680db49c5cc342b31cb7ce32cf88f07c9dcff845cce6f24a641db3a15a297c0b83ba8372897676a50222aaecc6a3a2bc0e06d52f2e4	\\x00800003ffcf6461950dbb3dd6eacf9f693f821af83dac112d361d44d4ae76065327ebdb900e423b6ba58d552d4f1c8b3b6eb0e3224c89ed55af8787bfa8b4c6cc787067ed7f562d935a09de20351743aed1432a266e75a6f9d4b78b0ac713db91d0cb30ec43fc398d8ee27c461257dfe3fb472c0a6abaf762b71f0f40175c8c11f405d1010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x897f849453e0e1eed57317453ad2ce51c89138d6c9c163b843919a68feeacccd365ccc1139f6da1d3423f860eb65c9321391a675136d4b81d5adc1b837eb3002	1622812976000000	1623417776000000	1686489776000000	1781097776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	411
\\xdc3f03f3930dac48bd5538742e8993d9ee4873e586d30516425630467e7bca0119a05d78f6361c6587bed2011a2aec4245d0380767d0533bd7981c8c8df5cc69	\\x00800003e8fbef0a245f9465c32d2b6aa06c0a106e326af3ed2d0f973eafb9c6a69f266e2844bf2272c4e28cdeb5c6e7cac291646478e43ea08a3d18115928e27a7f4189c8ee0f94c06522625cbf6dc6011a3152b64e43a13dafb59c0c8d0cae9bf177e0d66783cac4123e166a1f48457fe2c2db3658e60dfab5f8f8dbe65d16c4da307b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x3535d2096b174138a10305b9f94a1b93673c624207248132ba33cb0944c991f58ff5781092cf1c1843ab1bd1a32ddc8696b0a7fae470cf48802b3a6efa83c50e	1620394976000000	1620999776000000	1684071776000000	1778679776000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xe32ff75211806ea94c97d4b526a7c4f152fee4de3c7a5992741d190ec7430293620e55b99384c8894d3b39997769e2eed2ee923fba0ae1f005f47214eca581d1	\\x00800003b75b86c9bea3cf2923859a7f8c7dbea0ebb00ac30b36cf6a3a5f1155294cdbdcd47d017595552bd481f6f28a607714b4036d7afa732f18b62673b700567080814a14994c908a673c35a213f9c54eeb5ed7115bff5212cac7082e49381aba4765efaded51321cad29f53ed9b34fb300068ab375ab0efaecf634b37d3879146a2f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd15bd0726472f8ec3ef58d90de77e11a3f08f32db9fb94f3d1bd3e87237b3052e7d571432d9be6242b0412ebcdaef4a84932f386d57c6d42a65fb09b56485b08	1639134476000000	1639739276000000	1702811276000000	1797419276000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	413
\\xe41b5bcdb012e40455aa987d67b74388871df0763057eb2a933f3cdb53b7ae6d50de934418aaa66c7292ef5f11f09b4b2a3739a15be93f18baf7a58a7f569a82	\\x00800003c7f18e4c49ec0b2d14aa5a12fe6f7b0412210c299dd55fe8a161e572d448ceccb2b2a22b22f42005da910a9de68317afb27405c958ea875bc399e0c8f84eb9da02411b1fe36dafa7148bbb65d4ba1f2c5107182c2e11e604537c7a0696e8aa43e8fd4e7c4c0a20597dd9533ff6a0d1cfbecb3e834db6eee2603a87ba4a311e4b010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x402a49668d04d9b7b2c29fae96e07d015783a54515d1e66bff45f46577b88a6bdd484622ba94d5ca4752fee7e18993826e91e284596cb017731f52c38d538107	1625835476000000	1626440276000000	1689512276000000	1784120276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	414
\\xe533a4b34fa6fff9fb68018d51b9d443442e3d5839a0691e1e424508b90bc83392a3bfbdc18606731a4abbc2578900b444e304e58ba9f3f602b0f9778aca0226	\\x00800003c3a9a1f9d3f9d02854644ba32e0511a539f9ece30e4b89e121c24ebb17ca445fbcc9c78d87612c6e17b4bd48734def65926de5887e6c92cd94f2b4564f792e1630552108a1e95bfdde138908c188e22583ec88e1bad1b2475eaeffa452965ba89eafbd9b93ba5343e1e0f5b3fb31b32515202a2e818c04d54113b4490fca6f4f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xb5be1b367552eac25fc762782fb03c8fd15ea7f1ccc9bc83d5e693ff71d86982140c5522a35b04a762b87afef0712fbc166e4e34f3059a852d071e8682ef730c	1624021976000000	1624626776000000	1687698776000000	1782306776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xe7eb642669853743767f42efb98debadeded48860f20bee85589634c647c3038f1d8122479925f83eb1f483b3a46eb1005985110ea3b01127a2d75cd4e6433ce	\\x00800003e42e74042031c0406b6b89ccb7e71b24178bb02d90b2781e72068b2c50d7389ae5c3a5b3ceb75d1245d8832fad10a3a5923571b9fee916aff5a1df23d93d40417db15dfe84851bf0b635fbd3df3353dbc638115f31efd464cab37180d1c2499b3cac277b6e4aa1209d2ca91198d0641fbeabb681147ad8071fbf2e529b53c3a9010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x5c81e224de66c81b236e893d3f3b078458c13efdba354bdc95a33e0fd4c7de8c39133836566285bee9ea092c451e9405b03127091c4739a5b5723fca2998020e	1630671476000000	1631276276000000	1694348276000000	1788956276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	416
\\xed87a77099da70d9f56f77ab39805edf8ab81107dee6a291db5909b514d4ed27be6a0c1e31f36846c351880dd66b1cfcb6230ac11da7d97f2dda456da35ab528	\\x00800003b735d3de1d75bd933e3698696e2ac1a2d87e143bc1504feaf412fe973fd73b20dc9c60f008cc9e9ae9475155c76ef28b4a8e57f46881666ec9fb3e8886709488554a5156b7426e8bbef40d094c12d894c6ad96b56ddb9b4c57f7858810afd642828bac0ddd0a7a21e9b7b7e7a9ec1cabf7e4155274fbf268939dd002f980a23f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdaa7f813da930ab3df28339006e4ca701d7ca00dcd2d9dd039ca0f4b09ecde221c55975195a131323628ffa1c9d50e8854c46d48b1cfb5341301915bdfe21f0a	1628253476000000	1628858276000000	1691930276000000	1786538276000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xeedf11fcbbb0056972c2f845b7627fcd68cdfa138c2389b22fed43129a80f1d0eae84c37036a72cd808a8b2432ce0bbda66368ab4d1a3a20305e3016e6388d00	\\x00800003d3db8623754f81bd9440898afdc4c2587e1adce0af5f5ca206434a00ae679da5023eb8854c4e0f93de6548b9ab2c6bbe346857ee0d404d7b0173a528d22f0308426466238418ec0656379f5cbefc90e0c402ff5ebf3aac0b5fcc27d009379029e32ba874301da532d63de8b4e4eb8748ef3f83511853444e55cf05e1e65084c7010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xd3b037015e4a15048b2fbd7e78ff5a7e5103d11074800a530c3de986f06be3002619da9cda764fb9c2024b50306037da1db2c2d84cfd6ae7999c49c5b06d9e08	1625230976000000	1625835776000000	1688907776000000	1783515776000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	418
\\xef23fb988fb9b021fe110dea3e4ea425e5dd96b8637363efb977a2c7022a362f0ae0384192c7ea30c68a651a421fe80d436561f9586838268bf36ac44e99e07f	\\x00800003a98185d6182f7e1d9c488998f90c2182db9c2583f2c15ffbf94f0fed5e71543214d8c64f2c8090cb2a03973c2acda65a2886b5ee8f4d1c935b87b9e490f93944d055b5c047fb342e969899d3023f658967adec05b1ece7aa731ceed7a39f04a09dd728fd728ed9f565def713581ede7b51ea6a2e4268072fbe4dec29322ead3f010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xac342985a32042056b4843a1b5b628322499e5d083fe0f96569517c7408d2d5a6359d95ea7326620ebf41cf9433b745eb886d671526bb4cb377bf63c26aa2609	1626439976000000	1627044776000000	1690116776000000	1784724776000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	419
\\xef8fc27307fd9bd5380202ab1fdb3d8ce6efb2e4973fc6a225a4bceb681a634f1c34cd1ae811179602db547711ca56eb11a51fec0a29e4960ad0132297ac290f	\\x00800003c8307dc2a2069234fb77247252ecace93b775e6a451914c97d271e95b11decdb4c9f3955c2ca8ea9967b9b96f04eb03a5425f58e6ed8d6e6460add53ef8ed0f9e1fed821e23a6cca1fbd90bd9f76256d6d9db25be360ba4a1c10261e00d400a2a9fac48a8071dfa1774df319482f9c79fa48664c090b65b479b761c2deda33cb010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xaeaa98d60e01ae970dd4da447a6bc1bc25cc1f67f09472f468742b9fc473291a61f0ad7b53f434ca218cb1fc12da9b26e32288f8757d151f9a4f192a1b935e05	1627648976000000	1628253776000000	1691325776000000	1785933776000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	420
\\xf2c72e64ce5e2203e78a5dadd3e9bae39194ac0a13425535f3cc6b11b265c262ee570bb48c208cfdca51668d6d52b20f0e2afd6da8ced80e6e31478249d4dc34	\\x00800003b6a8165dea340298c51b0e39af29f3a709c478f00bf29b18d4a9b3bfcbc139506957c60f82f0ed9364144add81698677789bc064e4e58f1ff13bc88c65d04e768317cdace23a88e6608b6bb0e2e6dea8587e8dd1717b377fedb41c9b5fb2d7e66c7cbb6b8fa4f3001800886904b22cca3d3056ee95c2fd81512faaeb8bf2944d010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xc848b450ae364c9025b9f517ab45f48eb4fe2791f68fb26aba1162bf6c5b57335994b90df0d0df5a494b902e42f4f05e49178e093275ceb28bcdbeac4e167603	1627648976000000	1628253776000000	1691325776000000	1785933776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	421
\\xf4ef8d98ed8d20bef9a04aafbc1a14f1b0871d3fe6ede58b628bf8cf22c9f8bef2e5ac392885534d16ccf86771330f31fa5cb04b6ac99b716903ba2810139d89	\\x00800003dcb90f0e4bf68164894cae723156fb704d75e7cdf981d12b56098b2312bc14a460a6b1dd5f93859b3d1d81abcc6f96e5a184118cba7883eac2d63b00b9220289bcad91053b4277a8e964547e4314cbe5fa4103ae3bbf07b4845d975dafa7fb1d73e172ac1b8f772181d6f91221edd7781a8a2feefd060dc1c6518602f63485ad010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x22c517a206a910f88fc97db8439d0f65374b5e050341c07f88927a27f9bbd5a992946b63e9c776433255766399aa09d913cc4f395e1bbb8a17ab2d8dc2813700	1636716476000000	1637321276000000	1700393276000000	1795001276000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xf7775bc3cb29ec43086826339b187e4609be826d934a05a3fe464f6315053431032964fdf0715d857cb79ebc2088cc6d0e147fc2933ae4d2e6c4bcce62201c4c	\\x00800003c008697377d03ca0bf53b17423da101d4f2e082b93a431fd6727cc156acf100bcd6407b28eaf958a5b27f98f5d6a023391d47f2ae7612914e27b4f270cfb010dbe33f6ef60c32558e4e06c9ffa69c653f793be3c95f6d5811fe83c21138de52e36d5059c2ae6d3162908e00ab59cdf96d3e84d00c60d0920346a41b680748843010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xba874a993ae85a2faac73b1e65fa82265a0d757fc9c7f27cf4d1f97c9314d9e99a0c213773e878274cd3cad848c9a6e486fcaeb1d75014e87484f9950b916505	1640947976000000	1641552776000000	1704624776000000	1799232776000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xfd7791aa44512a00feacdfeeb5961f57203f6428144c404f54b64834569c5780385eef914cc743c99517cecf19a53ae416b5ce01a9257513decbf393e1b3d768	\\x00800003c475367956abe46bfe4ba2ab59eafeec691537c800c49ae7d273ce712f90eb256b40112202600aedee0d9f782bd6adfc83eea58ffd178a1c390475a2eb46dfec5c23098c7aaff9d8d3b964e6786a274daf9df815eabfc0115e23c48b8cee316c58e6f7056342a3253eb7299f52ba130333ed33eecd251339b03bc5b5f3203f83010001	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x2ca0df835d31942daae6b2f91a22b6a2e877757bea9117eb9e659617c495513eeec6f333c3ff6a35807b12d9fb03f9c1059a24efdee6f1116a32ebb08d277403	1610722976000000	1611327776000000	1674399776000000	1769007776000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	1	\\x681d3ae198ed5675d0be51a37d6db3f1bb4be07d3c6a657e740864098e148e6d134374e9881c65cf47f9f7b5df2cf81dba22a9828a582891aa07ce0fae3614ad	\\xa9ea74c7b3854d68be30d469418b8baca7f7cbbd014f9f9cfe8130b86e5c346ff56eb632bac64b957c9cc4ef06214c21e8cd4b187fa926deeaa9d44c0d82bce0	1610118510000000	1610119410000000	0	98000000	\\x979e276d05f9cec99bc40cc545c430be1499c0a2c866bca00952be71ca379119	\\xa5758837f202e2564cd390d0f8d30a28ff745ff7077eb9de02664aa7b76f40bc	\\xd73677bb19095107412f41d26834755b61b713b1d0c5dd7c9b10b8e7d0cc17d123fc164694ce279d424c5239ccf2cf34fc70af71fc3db3f48378781fcee64806	\\xbdaf0694b848767d45fe6210069e23f3442c4e28803d710e1eafe97dc0d4398a	\\x294e2bad0100000060deffa3f57f0000073f11f2bd550000f90d0098f57f00007a0d0098f57f0000600d0098f57f0000640d0098f57f0000600b0098f57f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x979e276d05f9cec99bc40cc545c430be1499c0a2c866bca00952be71ca379119	1	0	1610118510000000	1610118510000000	1610119410000000	1610119410000000	\\xa5758837f202e2564cd390d0f8d30a28ff745ff7077eb9de02664aa7b76f40bc	\\x681d3ae198ed5675d0be51a37d6db3f1bb4be07d3c6a657e740864098e148e6d134374e9881c65cf47f9f7b5df2cf81dba22a9828a582891aa07ce0fae3614ad	\\xa9ea74c7b3854d68be30d469418b8baca7f7cbbd014f9f9cfe8130b86e5c346ff56eb632bac64b957c9cc4ef06214c21e8cd4b187fa926deeaa9d44c0d82bce0	\\x1b779b3ec15bc2d7b643506d46456e32f395fab3c850d3de2d1961a0e2cf1a0527a8640c42cf76898d08ff8ed056cc7df2e070330858b74ed165d6d77cb0e90c	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"309VSWZ0WTN9XVTGWGF9VFJSJ86KTWG05Q8YRJEB06PS3J3K1A73GG43CR17NT689J9B0ZTYVY2S0AD69KCZJ7NCW1M15P7DHM24RHG"}	f	f
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
1	contenttypes	0001_initial	2021-01-08 16:07:56.515461+01
2	auth	0001_initial	2021-01-08 16:07:56.55562+01
3	app	0001_initial	2021-01-08 16:07:56.599073+01
4	contenttypes	0002_remove_content_type_name	2021-01-08 16:07:56.623009+01
5	auth	0002_alter_permission_name_max_length	2021-01-08 16:07:56.630925+01
6	auth	0003_alter_user_email_max_length	2021-01-08 16:07:56.636584+01
7	auth	0004_alter_user_username_opts	2021-01-08 16:07:56.643518+01
8	auth	0005_alter_user_last_login_null	2021-01-08 16:07:56.650595+01
9	auth	0006_require_contenttypes_0002	2021-01-08 16:07:56.652156+01
10	auth	0007_alter_validators_add_error_messages	2021-01-08 16:07:56.657758+01
11	auth	0008_alter_user_username_max_length	2021-01-08 16:07:56.669344+01
12	auth	0009_alter_user_last_name_max_length	2021-01-08 16:07:56.676928+01
13	auth	0010_alter_group_name_max_length	2021-01-08 16:07:56.690061+01
14	auth	0011_update_proxy_permissions	2021-01-08 16:07:56.698572+01
15	auth	0012_alter_user_first_name_max_length	2021-01-08 16:07:56.705346+01
16	sessions	0001_initial	2021-01-08 16:07:56.710334+01
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
1	\\xa117aeab4a0f868fdcca623ac0a2e8f2aead5b39b55c4a645c2581bfa96f7410	\\xa1a4bbfb1b4ef7b9bcd92684f392bd8a54ca327f028195e66abeb1f59b0b2192b9de36cf43001222a4ed5ece190b332626b8764ad12709dd7bc04fefe184ac0e	1639147676000000	1646405276000000	1648824476000000
2	\\xe5ce4c29b1748bb53dec6d754fb02e42166124dfec8dd5769f3f749695cae8e0	\\xaffd7c56a9a780ad9aa705e5ee18e4df1f30812afa8f63d106548e3e643ff484f95d180b56fea1bc9bfc762a8a2f5079931cf24a0ddcfdee01870e5c2879ee00	1631890376000000	1639147976000000	1641567176000000
3	\\x28e80608cdc31df1dce636b7436358167997151612e12fbca9c9f1c2689d5bb7	\\x74d6bbf31f09cd8c8a573dd471b1b876c7d9b8c1a38430484bc2d3344c273121c4deb266ad9af94b3b54f4a2033f49d7c345e415359e0bbc6051874de5319800	1624633076000000	1631890676000000	1634309876000000
4	\\xbdaf0694b848767d45fe6210069e23f3442c4e28803d710e1eafe97dc0d4398a	\\x7daca5ec6c45b662c2fb5ebe38aa81a11414de2bff0013afacad693f968bd77105e5d140f7b632d2b9f937ee1f212cce45b5b5d64783ccb27f13bdee7ef74e0a	1610118476000000	1617376076000000	1619795276000000
5	\\xdf34128b75703d08a9c5735d9772c41923bdfcc6d7d3191c21af505785a21709	\\xb309afdca79cf4721c460ed696965b5152ac023d3fecb01f56acf66bdfad22419524fe4ca95cced286d110daf019f3b6da281a4ddaee5be4da4e842882813904	1617375776000000	1624633376000000	1627052576000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x4c609dc8ee1390ec0edb34cffdfefcb2fed2c8fbee9d9fe214c048889b7c3ec2	\\x873461762ccae611421c47f6c7563a5c9a7c3fbfcb654186e8636e1602402b5d01c4fd2f7985aff500e1ce760ac9f442160f790cb379b1efa27c18a8e1126e2eef19a7bb9a6cdeb0c37d5e26af4ce9fbe4d9dcc9c1d38860e880e70c5650ea25bc3110213ee0231f755e6920c05af7930fcf4db2b8571e957863ec924d87e785	91
2	\\x979e276d05f9cec99bc40cc545c430be1499c0a2c866bca00952be71ca379119	\\xa04250af1167b18cb5e197904e410d2fcefe696a8fc49ee761617f952a4054950fa49d03aa76b0568a32cb42cdcfc37ccd2d354d815f747eaa5f37a79e3f262b1b5c6793e74461c1aaa0f0d7146ed5eb3aff1a65a00c71994d78cb5493cc5b454a722447e9c5abdddb5afaf71f4961ca9d928c911a1d39f48514efe4ea56291e	60
3	\\x8667752a64416334c6a6aedbec8e086df349b6dd459497201b5823f898da52ce	\\xb8779693506b95f1a28dd1075fd4176817413a9f39aa1826c20ffdd7a631d11b9d4f1ccc7c3f8c9fea0e51081b7945631765b185fbdffc203075764e0c70b938c05176443614cc1abf6ec2890cfe20e3c509a78c3249e3912b57ac42b3d8e1d59adf68989fa58546804f3e06bbc5ea9b17e6c351a11fbee6a17d6a1f9fc80a64	54
4	\\x1085b4983ed4973a644bf164a90fb6500c272affb6ac08cc9429958f420c1b30	\\x172ae32ee8a3abf190e680b7bd02713e362909fcc07d1d04ca3c0e34e5b23e030f818b382c52aa18c258ead86269a394cdbef8fafdd71a7ddfa41bcd12680606933778f03ef494b668717a099a3424dff838bc7a3d12614fc83fdbedd52680fe53ed25fd2083cbc056543501047dbada8e91fe58b56166e93e67b1006ad8e0	258
5	\\x6796f20f47abb19bb5be58722b08df8339aef5280ff79218a50c614aa5d61f6a	\\x94c960965eabbd08b7278a84fb01e3d350d7cd4c1bf1d710140e3254b4630cd7c22bb82c2b8bad4f3d89fedc88bf0132f22db7635c0468c326e0fa57e07ab3c4ebf0f10dea30856bfcc43a64cdf83459021e94f9b71c8eac03f7bb1879cde53d31d2f7ff9fe3f71d19a69e9832e579e1da7cf9fb7b16c8ab32f2cd852cdf6225	258
7	\\xcd478cfdbc44346aa2e9485b0fa78343997c3ac3c9454101d591d0756f7cd25a	\\x78bbe64f38f75ea06191d308777a330b2b778701d2f095901a51729e520141b489f340d508ead8e527644580d9500a959eaa3905172d65e4ab5b692362f20f850bf939cb6d4bcf691555103e66a90a4dee75527433036afe44997f38834a130dea6043806c96ef10d61042901b5561e359f482399454ae6688fe5e8250a44cb8	258
8	\\x30b93129a58fb9721c09b25f74c1a8271c6faf6e964cf049c17d7708f0743852	\\x33ed33f71c9fa9f464606857c037203ab864646a606b7dd2cc4a9483b70856619ea76d500d6a6fddcd22233fb6955911cf6f8eefa3a0f4c9f74153ee8a216644c4c826e8468092be10c33e6e098ac00652f54d9df3b64f6511f21a7af87e16423f128467d227f9755d75ef8ae92daf15a388fd9c45c0689ea4d3220a4604c247	258
9	\\x79b88354d2929c09bbc7f4c990d62c23dc37904d733bf1d096738f7ec1460c1b	\\xb307c6049ec2c1b6afa8bf237d45bee2fc15e711c143d247c70bb4ddb8c0c23fa1b49610aec9f1fca5a0f9aef0ef37a9197658615cec1945ca2156f9804934eba23eba8cfd176981b4aee86f558747d774461d309cc5a3140a754597bf9f79e1847705fe67be150e9715b621d511c59cbdd06c13e6920b5621604e8f6f08b2cf	258
10	\\x323fa32ec5f44f7180cf0997281d5e53d4f71decb836eb5ed46e588923e23e84	\\x2cf1d360b00bc4e5acc22c1e3fc11704454e7771a9e209dffc23c76af0a46b992b31d514e7e2cdca1d4fed94872480a0acb60b6848c91e3146be9c2b0743a762a9b614df8d4beb39caa06bf396ae9dc4692f1069457b9932deeb8124c6566150761afe1add19743f065a50879c69f7c77612304eb515db889539d02d27b38b93	258
11	\\x6fbc8bf60440c405122065e8fb26a4fa74597a6a59dd23736bd6b6df41a0a40d	\\xc7c10f971b5c406ab4a409da3a43c44b7baeca3579330d58794b75a41c0428371e65ec0e9e1f8fda4311dcacaf32ab7f3678fb3a6b41c280539ca4a8484040a4864f1db5e6a0eb6624b1ddc06fd3b65e58c39ca922bf8f36487b01f5b9e6dd1771eab0bb6a52a736ec9b99d0b63ef859e23cdd66706863c5abe3c8c18261ed7b	258
12	\\xe8e53a4f72fbf95d1551ea435bef1cf6dbbf779f3f33ec23c824551d6818c2fb	\\x32a7de2fa79b662c6e10713de632145e7bc9e98bbbe74081e077045c6ed38e68acc5c238d96b88585a6190f929b97cee574a65384e89fde7022a25b176e41e5ca0a5d5a9be9e635ad171c07ca118647a75268e77806b6eb5369887bd7a5f47eebfc5f9d09fd4aa2f811da0c4c9b44a53575d04ff422e9a413e9159239dd8e51a	258
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xa9ea74c7b3854d68be30d469418b8baca7f7cbbd014f9f9cfe8130b86e5c346ff56eb632bac64b957c9cc4ef06214c21e8cd4b187fa926deeaa9d44c0d82bce0	\\x1813bcf3e0e6aa9eef50e41e9dbe59920d3d72002dd1ec49cb01ad91c8730a8e38408366027ae8c84c92b07f5edf859029a64cd9f91eace06812d8ed8d044c46	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.008-024BNYJS8HEZT	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393431303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393431303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224e374e373948584b474e36504846484754484d4d333257424e4a4b5a464a5858303537535a3737594734524247564a573648515a41564e5036415843434a574e464a4543395652363435363233543644394343375a41393656564e414b4e324331503142535230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d303234424e594a533848455a54222c2274696d657374616d70223a7b22745f6d73223a313631303131383531303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323131303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254583530575135503452484d4254384e4b474d4e465053364758574b42375654524e3941515a42375336544d59385957585a3930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d4e545247445a4a30424835434b364b4a333846484d524135335a5138515a5130585a424b514732435335414644564638325930222c226e6f6e6365223a22543552383244393848383444514653574638444a5745355853455448584151384d524851364832334e4234425235365454444e47227d	\\x681d3ae198ed5675d0be51a37d6db3f1bb4be07d3c6a657e740864098e148e6d134374e9881c65cf47f9f7b5df2cf81dba22a9828a582891aa07ce0fae3614ad	1610118510000000	1610122110000000	1610119410000000	t	f	taler://fulfillment-success/thank+you	
2	1	2021.008-03W5CN27FMNTM	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393432363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393432363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224e374e373948584b474e36504846484754484d4d333257424e4a4b5a464a5858303537535a3737594734524247564a573648515a41564e5036415843434a574e464a4543395652363435363233543644394343375a41393656564e414b4e324331503142535230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30335735434e3237464d4e544d222c2274696d657374616d70223a7b22745f6d73223a313631303131383532363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323132363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254583530575135503452484d4254384e4b474d4e465053364758574b42375654524e3941515a42375336544d59385957585a3930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d4e545247445a4a30424835434b364b4a333846484d524135335a5138515a5130585a424b514732435335414644564638325930222c226e6f6e6365223a2235584d5243595232344631355257504843594437445350343451563151333037475947584e423238314e4233573636344e423330227d	\\xf25680974a4d4bf4eadcf9d963f205d7af3b06ab455bb2bb9af37d368734d1f2b566ee4b41c9c15cf1ccbaf59879c77275ae2701c6392bb52b907ee0e940e7e2	1610118526000000	1610122126000000	1610119426000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1610118510000000	\\x979e276d05f9cec99bc40cc545c430be1499c0a2c866bca00952be71ca379119	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\xd73677bb19095107412f41d26834755b61b713b1d0c5dd7c9b10b8e7d0cc17d123fc164694ce279d424c5239ccf2cf34fc70af71fc3db3f48378781fcee64806	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xa117aeab4a0f868fdcca623ac0a2e8f2aead5b39b55c4a645c2581bfa96f7410	1639147676000000	1646405276000000	1648824476000000	\\xa1a4bbfb1b4ef7b9bcd92684f392bd8a54ca327f028195e66abeb1f59b0b2192b9de36cf43001222a4ed5ece190b332626b8764ad12709dd7bc04fefe184ac0e
2	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xe5ce4c29b1748bb53dec6d754fb02e42166124dfec8dd5769f3f749695cae8e0	1631890376000000	1639147976000000	1641567176000000	\\xaffd7c56a9a780ad9aa705e5ee18e4df1f30812afa8f63d106548e3e643ff484f95d180b56fea1bc9bfc762a8a2f5079931cf24a0ddcfdee01870e5c2879ee00
3	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\x28e80608cdc31df1dce636b7436358167997151612e12fbca9c9f1c2689d5bb7	1624633076000000	1631890676000000	1634309876000000	\\x74d6bbf31f09cd8c8a573dd471b1b876c7d9b8c1a38430484bc2d3344c273121c4deb266ad9af94b3b54f4a2033f49d7c345e415359e0bbc6051874de5319800
4	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xbdaf0694b848767d45fe6210069e23f3442c4e28803d710e1eafe97dc0d4398a	1610118476000000	1617376076000000	1619795276000000	\\x7daca5ec6c45b662c2fb5ebe38aa81a11414de2bff0013afacad693f968bd77105e5d140f7b632d2b9f937ee1f212cce45b5b5d64783ccb27f13bdee7ef74e0a
5	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xdf34128b75703d08a9c5735d9772c41923bdfcc6d7d3191c21af505785a21709	1617375776000000	1624633376000000	1627052576000000	\\xb309afdca79cf4721c460ed696965b5152ac023d3fecb01f56acf66bdfad22419524fe4ca95cced286d110daf019f3b6da281a4ddaee5be4da4e842882813904
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xd74a0e5cb6262345e9159c2957db268779359f7ac552abfd67c9b54f23dcefd2	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x946dad00430709090ed308cffc8be5dcfdd3aec521d763141e992a98b2ffa98c5c5d0644ad9ff56f0f0cc5a6725a18f983a6ad0a71f46a12a7f4f54f2587ff05
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xa5758837f202e2564cd390d0f8d30a28ff745ff7077eb9de02664aa7b76f40bc	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x35d2f1ce1aa4e3f0f3729a63af699f5c1d3b4995fc6eb36e6ff3ba7997bc2403	1
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
2	1	2021.008-03W5CN27FMNTM	\\xc4844b355faae9dfb8426a806704d11f	\\xcca1a4c705c1bbedef7b535cb34c445b545f50a9c40d6ebca82b71b4cbad12e2ac5b011c7f074501eb90f93a1cf0ee3cdccd29627ce675294bfbbade80076003	1610122126000000	1610118526000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303131393432363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303131393432363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224e374e373948584b474e36504846484754484d4d333257424e4a4b5a464a5858303537535a3737594734524247564a573648515a41564e5036415843434a574e464a4543395652363435363233543644394343375a41393656564e414b4e324331503142535230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030382d30335735434e3237464d4e544d222c2274696d657374616d70223a7b22745f6d73223a313631303131383532363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303132323132363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2254583530575135503452484d4254384e4b474d4e465053364758574b42375654524e3941515a42375336544d59385957585a3930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d4e545247445a4a30424835434b364b4a333846484d524135335a5138515a5130585a424b514732435335414644564638325930227d
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

COPY public.recoup (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x4c609dc8ee1390ec0edb34cffdfefcb2fed2c8fbee9d9fe214c048889b7c3ec2	\\x72d1a4939b704db1db535651dc58de35328ecbd0307e79103f9880cc0f15c0857d85ee00d88f4b7c1fcfccc148cca2f16dc6d5e20f22fcbe2dbd901a7449fa06	\\x11c0522823e6ada4659d86b17e1de053dbdea52ca0a9d50d5b7503b3bef7048f	2	0	1610118508000000	\\xc5cfc39292c33971d304766ce0100a88297bd3a47479b9d5f030e3ceb21071be6389af70c18901f11ee337bdcc9f270a40256f76d313328054eb8e5535a608e1
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x1085b4983ed4973a644bf164a90fb6500c272affb6ac08cc9429958f420c1b30	\\xad4d64f671c6cb8fa4c28de4ee3e21c22645660340ac094cdf16e6022768aceca3cca7c10f886079c7837e25111bb52a1a369c3cc21067038682827513a1630f	\\x16cd57b76ce04e44d2c8a6a3dec1b2d15636216a53864086f80c7721d680222d	0	10000000	1610723321000000	\\xcde6e83911b2f11eb116c4fd76ed6e36a4690a136fed181073963901f36c5c2cc0c11ea3363ec9f40a0fb82e973168fe2b533988c219eb920377dda79209caf8
2	\\x6796f20f47abb19bb5be58722b08df8339aef5280ff79218a50c614aa5d61f6a	\\x9653374fc63b7151bc4628008360ecf939bf596f8b328d8672ebd4335983ef5665ed8756615dff3206f12a809bcd4b4f5e905c97c684c32118b1f21cd7525e08	\\x7cb277408e0b21c8d8259b31b910e64989f4a2fdc437c86f1f8ac7c4ffb12a17	0	10000000	1610723321000000	\\x29c41b09a841046fd3ff07bf8878b9bc40500d79f28fe4175f6fbaf003e3526c4733b1feeb9871e64848292a5011cc6ea5f37b4a112ef0662fc1222e5ec89e6f
4	\\xcd478cfdbc44346aa2e9485b0fa78343997c3ac3c9454101d591d0756f7cd25a	\\x9102ba0cfa6de720514f73074b95ac5a3226a2a1845d741ef6dca35f4c6cb90514779ba84cee9f91d2dcb033f33fbced677d3f253d9550af1b36238ac0a6fe05	\\x59c9b39f7fbbad9f92c9729e0c771c4104c82a23ffad80d37c9673a1203b0658	0	10000000	1610723321000000	\\x584da828ab3631ade7446fc6a835424c8aa88aca54c995986046e920d73557d1e495a45f4f33ad81c84a4574034a35b90c7c07d700987c1fd65376d85100a039
5	\\x30b93129a58fb9721c09b25f74c1a8271c6faf6e964cf049c17d7708f0743852	\\xd4b9f8f0384a35f3b7c2547c5114112821ea474e93dc2b01e33481022cfb64fbca66e16d314d96635d21828ed907e11c2486cfb3e3928380a4e2b6d05201440d	\\x4c68ebcf9a2fd78a074522ca6a600fa6f10679104707eddd6b0b9a3b059ee828	0	10000000	1610723321000000	\\xd77ab07dc2819945cd384fdeff6ffd71f17a2d38be220859a4a27fca88e35bdfecadd73d2aab8736e03efcddb35ecedac9a775439931f76b8fe9bbf33680e88c
6	\\x79b88354d2929c09bbc7f4c990d62c23dc37904d733bf1d096738f7ec1460c1b	\\x1acae5289645464e45e582e243038d779f03164947f5c2cd307d1b6f78bbdd10590d5a9ada8ea09462688b8a7d62772cbd284b7c8df3c112bb10379303986206	\\x3725a02986a340b6478cb930e90a779302d6193554d4605110ac98776e68b1bc	0	10000000	1610723321000000	\\x0cb6b57c809bb5a8337e463b680c027aebc4f6e7c84cca98255a6bf3e04b19ea7bb188d9b7f7e587bd6f1423d620f2e54f785c3f764d1200d7393d81fb2677cb
7	\\x323fa32ec5f44f7180cf0997281d5e53d4f71decb836eb5ed46e588923e23e84	\\xb49699c78f1afbbabd65440787e80da1029f006dbbf97aba423970ee27b9b0297fecdac84466b804dda16f5f7ea6265eaadef6991ba440b1524c3232496f6302	\\xa484f5aaa08034b84c16f6bca32e186467629e6f2249862e9979b0a53a4984d1	0	10000000	1610723321000000	\\x341a7cd6576bb002c351dbaa73bf02625fa247220c407e72f66a82ea93cc4341ade503f252ae841206740aeb87229ceba68c571c73718bfb3bcc29625e96911f
8	\\x6fbc8bf60440c405122065e8fb26a4fa74597a6a59dd23736bd6b6df41a0a40d	\\xe38f73f9b76bd1e061ba2dffe25e060081c32ae2a873f89ae5ce3730a24c9c2858951720e6d2bd24a0a7a0c8cd3cad4718492cfc44637ba2e75cc56bd762ec08	\\x395eacad5e6781ccd3b1c9a9852ee55e060e77fe6cbe43cb1b51636074708d1d	0	10000000	1610723321000000	\\x569a963a952c29e64769d32f0a120654bd4886d143eef680ce21a04ed57d5081e468367a58aba60fe9209e6aac22e03e7b152fc35a79ae9b358fc46b87fb993f
9	\\xe8e53a4f72fbf95d1551ea435bef1cf6dbbf779f3f33ec23c824551d6818c2fb	\\x4ec52697c7945a2a6dc68bb2179c6c13d203c613af8925eb51a41fffea39500ae0caa5d2f38ca62a51ac7963bf63bb20d8e07f894d795d08a13a7e0a5b06030f	\\x7dcaec373358f5453007f057331e3c2a625eb040b1e792655e7c20441f173276	0	10000000	1610723321000000	\\x61dc6c2f5ba91a8ef52cd34fee0f7f465e6e20638a8f5b0bfedb854f3a859f466963263200fd373fe373f70e9cb7c9d57513e8a1fba7a99df6e3620e7dc56a2f
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	\\x8667752a64416334c6a6aedbec8e086df349b6dd459497201b5823f898da52ce	\\xca692f05713fc9b73b7f6c1e5f346affd80d5f078b678a17655c27ae4305e7bb2031f20bd96a9a7013310d12978e492f236851c16ff78b51c4ee50bf856df90b	5	0	0
2	\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	\\x8667752a64416334c6a6aedbec8e086df349b6dd459497201b5823f898da52ce	\\x720bbb838f860565fc9327afacbba97fbadf77f52f9a0caa7a49ca6ce5bc30d85b01dd994e2f6199757769e0a4dc606f01d4455f8a26ac913056ecb458a80e0d	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial) FROM stdin;
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	0	\\x4e882367c7121ea1ce0a0ae6414f9f37b74475719a4d86c9c984c28e43a0a0a72f41d3d0a7d7bb906062d4aeecdfdc8b233ba40d666e81b6e0a008c9c115c008	\\x7132143cbd67058bd0b92e279be3aeb285ba0156f4a3b1e12e6c237ec62a8dd146bf66fec5e69effc46a378a5ae0a1c062728240be023d4839f2b963c89ca41e0931a22edbb170e9e2f776971afe4dfe7b5f544b3609e277aeef11e2a29989a85e01b93666b23b7094b1f5f8574e5884470f26652125b74fabe9731dbb830f19	\\xf1b69d15d126ee338c660c1aa3cfa1ac47e76550860a22692f6f05c031ef949b35ca46bafbe6f98205ae6ddb4f4bcd648898c21cd6902c1029ca5dcec6bb8dd2	\\xbd1bedc4e63529e9d64342aea1ac2d37d92e59fe4c8a6de2366f58244069256be2cc00929fa12a79a118dce90ea922bca0b0c0deef5cd0ab9913049187bcf1f2765114a8a2da46cacb2611ca43bdd85f0a5df98c054e076737cb1a6645d468980f467133a5700e7bc3c97901c1370030b080696d746cb8676fbc1f9166519c8b	1	392
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	1	\\x7c3c33d350c0fab21804490225d53d965985d4f73d43b172b258c32f02879152830deb1bcb1cf603192740bf4434e17a1851d1c957e74a83c9ed528ee4aa3102	\\x0c59c689a0b8340ca074ea96d017109ace17595a7b4202e567dd5a3e6d3db6695ee2b26c8452e37e1fc5688d795683a83edb589688c75820a2806b3b0e98d27742f574df35b9d104edc4171215efe6db11df5c5be9436eabe71e2cb339163168041dd359db6f5d77c926619c4e058ff87c6108becf45f4a088065c50d081c765	\\x0cb6b57c809bb5a8337e463b680c027aebc4f6e7c84cca98255a6bf3e04b19ea7bb188d9b7f7e587bd6f1423d620f2e54f785c3f764d1200d7393d81fb2677cb	\\x3ae3b2e0acb162b4540d09d8f4b8d634566191e55c10a39cb20f5cf8386044e071198a609ca52cbfb3b060529bb380d46c32ecca54b1e2ea58ebb1ea4b0dc0cc252cacc1421033a2177dd0062b61f683464b01c1d51ece56ff88bacce3f32d53160b933482c696c83cfde2d39dcde3036042fa99808008a2fcd29b4eaf35591f	2	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	2	\\x63c0d3666cf0ed352227de71dffdd422cd48d4d828a092a82d0aa05f43f98d596ee95ab94fc1fe2d282a79e15aa742f33a88785af1328e8ec2a97827d2389001	\\x5d67918c9009125740832b617f6e968b8ecfab0604aab3b1af9895f80c07aa72da5dec98adc7ad40edb60987d0a1df89c6ad78f17074606dbcfc2d81d50fe4449e55c37fa7e0b6361715362529a90afe428992e98ed25e925b17348958f538a05c30ce1237a603f0a12b71ad72a15c25bab64b4e6defbfb1988cb6f48537c234	\\x61dc6c2f5ba91a8ef52cd34fee0f7f465e6e20638a8f5b0bfedb854f3a859f466963263200fd373fe373f70e9cb7c9d57513e8a1fba7a99df6e3620e7dc56a2f	\\x3ccbe7a4ac8a0bef2c2015ee3e2ae1dc0fa7fc8a156cfdf5ceae2512ccaf71c45ddb61f664901af66e8fb0ebc2c97af727ab4f568990415df9ac5351d5a9eefc7d23762067e54e89bb34f37ab31ea17b6595f224a845d7e70f5c56451cef9ba69dff0f97b896f278088ea5395e0f05cb9475b8fab93e8f50fdb43a008df8ef29	3	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	3	\\x9300f418342cda3dc4a9f0d6f213bd14e52c293ff6f3c9049bbe15433b1db9372256fbc7fcfebb5af6ad4a6cbd5f3d1ec09767d47c60aa41a66b9770f2b42d0b	\\xbc85614e811700c6e71f8db16af233b62da50d9be7976512e84ecdffd8880d2633efd0fec8c087a8428525ef095af13154e4c9bbd19e06c51d0c2b6d409330d70b045508acb5645353f99bf836e0012578823552afdac1becc8bffeedf128ff2ee0da741cb78deac4b5c367292fa41a3cf43f7c02ef85150728e0314af19b39f	\\xd77ab07dc2819945cd384fdeff6ffd71f17a2d38be220859a4a27fca88e35bdfecadd73d2aab8736e03efcddb35ecedac9a775439931f76b8fe9bbf33680e88c	\\x374d6a922326da9a1e5350d3defe2c3ab817c3cdd6fec25a41b5f587fb27ae44de506401f044f91963317d87fe196db542cd8333ee5d799a4e4d66e13639beafe5e90d7f21367d5a653b7901c98f443de4680defc1a7a1072cb6595e7e22855153b8f31df15be20167044f23beaa6ad93a268afbdf7bb024f978b2cbbba163bb	4	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	4	\\xd926474cfd35f2a5c8c54ffd68c3422bb6ffa8663692ffed9f3a0ac36f93d3728abe377d8da3ee9b208737c3b67211ec29a9027e2218aef4ff988a34a050d20b	\\x8b44c3046af5c4cd9e34f732d96e251850e1dd97db68a4cd1456a18810a7166fa5dce4b39daa0c369dbff8e67ab83e621b656a39b928c1469ed79ac4a33ea68e63f9d4a2c25919640870928230454c8c7990d86d328b2f41989b4cb777337ac0d2341579c0df31bac7af7777dd0d75203855a83464674a44236e0de070abc9f9	\\xcde6e83911b2f11eb116c4fd76ed6e36a4690a136fed181073963901f36c5c2cc0c11ea3363ec9f40a0fb82e973168fe2b533988c219eb920377dda79209caf8	\\x53ecaee81537dad14e4d8d8fa52077c555b9e5e557f1ae7f895da8a61396728f2522cb25beaf1baef56164409bcfe5126ced7e606c70529925b3e840f2c3caabdc7051ceaecbf69015d043bc6aafaad7940cf90b4d03c28b1fd925abb834e2c1333b325791207a1c8a0e098fa21fd16d622b1d78fa7648f74edad9099ae78113	5	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	5	\\xfcbfde8314c0fc0a6a05fc13387d3d5b2c34bcd822fe8b9fa51db7f47ec300453ad48ec3d83ce8b210c33a6af4df0c622f07f5b52859fe850ac22aa142407304	\\x8811b55fb28aeb925c8c69153dc18f0dfb5b76e32a6df123834a570707664da9995921e58b6f2487a8d98223f8b91f5fcfe7b1ce3977d78ad6bc6a02e495061872e272a9843417c5c7036e2e558bb0c2ed9c0c71635b011b3269a4a4969703dfb67fa30e013076526c1fbbe2d6a914628f11f1865c7fc8479166fe1135776f12	\\x569a963a952c29e64769d32f0a120654bd4886d143eef680ce21a04ed57d5081e468367a58aba60fe9209e6aac22e03e7b152fc35a79ae9b358fc46b87fb993f	\\x6ddc6a63a82a91c89ec3decd7a305a35a0fa1ba19ececedfb5d56ce5b63e36c9fb9f23da429c919783976ee113a8208d0853fcb825e9b3bad94d6ac43356b88faf6abc856e3081bd85e19d13a2502b62870485cfae011d9159829fac629a1cee40249757b87dded5db8e5fee825289596b2d9d5273cbce2247889a2774e74167	6	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	6	\\x49c0d78fe3d449eb546776477304fabb22f8247aeb2d1f89bd0786f4e26c97b23f750ad2839145663f8008650013966731c86541521787fc9072e5ad1c439f0b	\\xc717ac3dd1a97dad07287d58440ddb75585f70e69f7b0f92fa702851148d64ee6a4232b7b2f02630420b4f2a39bc41f390e5cfd46a1b5b936aaa4c2143339b0254b30f4a78cab284916ccd3e98c05a459c0489ded59b2ac9a716b5e40d0c9805432991c736ea5da81e4f42ca1e0e4280841d01d13a87014a83987b48dc309c56	\\x341a7cd6576bb002c351dbaa73bf02625fa247220c407e72f66a82ea93cc4341ade503f252ae841206740aeb87229ceba68c571c73718bfb3bcc29625e96911f	\\x315ee3e1b3e2f86913531271385e6c9543ee5c3f10a96d5c5849d4f476b88cd0738ecafd60cef6174d78b5c660caf4c3906cbb4ee31ffd876425bb3bcc6b1916beeaf18dc269565a7c380275859a1f28b89135419c0a6f65103892ad92ce60a02dac7a62a2e92484a5a237ab9de40de450f79702bc9f521e0b85c7ced47fc2ed	7	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	7	\\xfce5cca67c1a6e03ef4fe33a75ed6699fbe306ec2c74fbd3287ab72fce7751e805f7b5e39d2e6fd0856fce5cd0ae33d5c8e92f7c2775403721692e1c63034508	\\x924acccddea2c54d1f270825df1baefb950476e06a168d8d1476e6426b58e9200a64f38f91300fac4d80bf11ffaa04e9f976c1f6f7810e80e824fe48ae7e4b90d2825d894385f79d6f28b376d2497732838f22f764951ffe5576d64528b6471afddc9ca3ff68e959b312db1a8ea7817278e3f50c2e683040bc006eed4b1a4c3b	\\x29c41b09a841046fd3ff07bf8878b9bc40500d79f28fe4175f6fbaf003e3526c4733b1feeb9871e64848292a5011cc6ea5f37b4a112ef0662fc1222e5ec89e6f	\\x34b5a08e9d108db170e18bc657205243e76c1c9b246810bef4f8c9674f63e98b15a8bee9c968304779ac5433acbbe9dab96fbe2a71ad8d16db540646d6406eb9f68f1a69a73d1577454575b33895818aa82e6a4e575df615ec8d48c8fc08cd342bb26c7246384e37a52ad53196fe24f302a3a6bd284252561430bff7677b29ef	8	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	8	\\x07f94c37231179ecb65793f3a2f3d2c861136f6f00dd7a68630ad4ef1cec536a80fb5c09dd356341f5fede84c3cb4e3f381bad543b7d432464c062a6323d9b0f	\\x7f4e2891d19692aa3a6e6a602309bf397cacb8e16e37d269df1603e7722f29987d7e13482d6e1110ed858901e49ca355e1aa3fce2ed99ea307d614486d55573554d273534a8105dfc4aed26720afc45a36cfbcb7f74dc2918cfa7cd2f78e087c0bc133834e3fa49d30ed90fbe0744788e07ce9472f53fd3c3ed9a14122aa89ce	\\x584da828ab3631ade7446fc6a835424c8aa88aca54c995986046e920d73557d1e495a45f4f33ad81c84a4574034a35b90c7c07d700987c1fd65376d85100a039	\\x5133ef2416a3b53ae630a755ff869cb19adb54250a91274ee9e47570c424a7a09f610e9abe9a13597da9783c71f81b19560841c812c65fa766031993a90543e671b89fe70a9d286d05f9ef7d73e2a3421273ea0c3f4cae298e7d52ccd3ad7b0d48a77f92444300a272bea8cf03cad60cb5af2f60d70bb16fc59e875399146baf	9	258
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	9	\\x63ece5e72d83d0c21c5307f95ab022c15deb693dae343414436f913c2dbcb8bd0051727a223512d3cdd8328c01f54a37712c8cb395a52ec3f720171fd45bbb00	\\x92d5c945d061128ca8f8bb3c802e83937065fcad3a195e75071ae82cca9844315cfb0d3aefb80a1d2716475006c21990a95eb07c906b8a5dabe79e491253711725723463870ff0444fd52bdfba5b1219adf3510c1973a9ff4573fb36e0a4765f6248a61bc33f66f7033744b30643f18da4cf9ffd0fb0010509b219f8afaf9ebc	\\x2fc0047a9560808b435601ff3d824ab382c1ecd7071b095d2e02f7027827497bf8d6f827c131956523294080cc1f68c2ad7a03a091824be5a1a7c83efe991aa6	\\x3a7c1195dc7ad03c74495c7ee3959b5214d83c0b69086886c7c548b81a0a8fb3b26d08dd128a3c95a6ef458156aaf2b688bcdd8a2c4251b043dc659a966a8e5672111f5bdc57fa4f8e9c6277288608fd41a32df79fb83abfa219ee1703bd7ecb8e418fdb191eb2a6ba35c86e14242117728cb4c2a48760fdd97ae10a3fc5a3d7	10	356
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	10	\\x76b420ebc772fb0c0403d85a18421771f331abbbae6e7d2360306772f9a2a98bde128a05b8937d13d12e631f57fe8a3871200f6445a9fb2a04051dfe1bee5004	\\x62a4b231cc9882be738c01c051409470880a82649f882ff5f23b1d3ffc7cde5cfd6df26f8a0118a5d9685a13bfae62dbc4cbe083af27f121c637a252dfeeec2118d594c9182147be871c56514a8e67c0735a1c467f259556a234544813a2171813ef7f714e4c728be7f3fadc9ed2de9ee2c84402484345838988d279bbabbef9	\\x74762a0517bd03427188ff7c02eb0651f0e896e80d955b7ab1460eed17a7460f9912e10189672b44a5c565d3efdfea2dea7123221fae5ad7651ce7dd1bf03ec8	\\xae06cd3c36443de87ec68f4fc15594036edf4cf7586cba743362e370c1e3b232fb333351dce121e479b6729eb866a4fd680493a2f4f9df8d24035f1a937a7c46583c581a7658705f7a4972ef19f0db63d437273c0f96bd8ceb55b69da995bf154503ca9200141196b00bca67faf2d592dc257b469a4389a3070e9c827d7a98f4	11	356
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	11	\\x2cb9f3f42cc09d600def082be9e86d48d4f6241e6d100d984b017b56187a8726362b237e17d5304b71a382575f63c36791961d11a80ee9185a23626de7556b03	\\x4394ca7818e72a1539863bbb09271a3933808b5682d04a6d21cf17ebd6937142df07ba0ad7912330122af773cd20743f5fe2ca142fcae98405b9b419e8b753fa75e2dc825c5b656215941d64922b86aa7b203339544bbbf0b1a6a911e45f9e900a9ff92c991332d9a37010e084d1449b7cb9bde73483e3dea7458352604b9091	\\x8003509992a5d59bc6872ee9a33909da10a4a30427a8f368af45b6cc0e52b2773505e0c58f20aa04ecd99e165b791079d60b593158a3f7a6673433286709f77e	\\x7d965ff1e4a8e918bb7325c9d7849c23ed42cf1bbbd3dc4321774c552b6618e03e782f55b217782e9b7dd7da8b6da282bd8e887b8532ab681cfe984827ce35851147bf73eef73f5c2b78a9751d5865c0141157963376f9d6a08e4bb73ef744fc2d9f3f7fd59c97da444a9b2c0970f5a26210edddc0541a8abff998076657c5f3	12	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	0	\\xf3c3208a32003f2ddddda366a9d6a7eedc31b2055118eb127afef90f81096a8d7f76ef76229627911f4ddf15e95c0420a956ce0311689b2e1468cb1059f84907	\\xaaba751e026c5779517eb145874895bb0cb076e5ca469374f38003e9494c94609cb3155ded7692512181ce2dcfe271402d6564f504f483a6d5b7efe9bbd476dabcfb643bbb1275a9b08f3c8a9c200e47c742846e4989b9f61d10339e5a29936f8483fe2196f26ae8b60bd17a9181649fee8bfdc2a4cf20158b32e63efd7848b2	\\x05bc8eed7fd036ae1b5953e63a3cb0055d56772d5f8b3411624768c53a9ef558bf60d8acce3918ea7dff547cd2b3574cc8a6f6ec51d404e0cb0c241b012214a7	\\x5f153fe06a23ed964c17f00a4756a35d2294a5a73e0a975ddd21a638e81efb7568a6319b17a6ca4926e9d8bb69c242dccb92f45c4a21f0276aa1eaf35b60fe33d0d5a8bd1085f7741c01167fcaefb6b963d9ee18f3a80f870f97641201fd6bd43ad355ea4c3633fb0075d7b2f26123f4981583af299efb84831f247b9730c092	13	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	1	\\x6601c5f489176d73ba46558e80440a06ae2d663dd6feba01e44821c6842e87f01a7cbdd3cec88f4d527f0d5c010e115d8d679ac416c8a3bfd3085813ff27d607	\\x6a437346637895ecf50e92c00777969355a5643d5a992f050cccbdc7ab26085a07259970e26b407e3fc9fba0abb90d0f66c6b563bbca2bc7df5a0b0f8d6c4b93d7d63674118257492bd3389ba90d51efe0f7cd7d9eb5be40d01bb8bc28487e81526e1383fae647a883f3f2236dbac5275cfeac8d1d91ab9b2f499e5386cb231b	\\x67a183cd9ab8bd601b63aab8b052ae2d8a921668169960394c584bc66e8144f81aa28cc102480b3a70f2cc0536d27c80e57b10704df3320f4de027e830e20651	\\x6f6af09b8e6beccc8dbe3d3fd181642b99581f41852cd5e45fdd16e75098bb9b0d336c73196fd41867161f37de27993748b2961eded5a079d6e454c4bd5a9d1cbc6b4aaf6edc0df352e8f9b080e76d543c62eafb30f1075513f8ef8fcbf0a4fc016fbece18db53eb60a5113c243d208f80d652ef266e616296ee4e253a11f1ee	14	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	2	\\x7e24776a24329da74020931d30622075e4773c84f78272f8a0c2751271b5cd01108d94adc93bc92fa979c54d3d32061d4ddddc7da3473808a6967376eb127300	\\x3e88e75ec81f401465de718873fae6d9056d17ca9b5934370814fedd393be41b6823f3b1cadc6110a893b836c8230cbf51ecb92c186ac7b35474144de207ceb355824199e5868eaf0bb9aa202a1c167eed799315d56cf2c3109142df6ac9678ad96597c340d080c8b5a92bb2b9f0f0328cf1dd22ef21dd753e1ca28f8bdb493c	\\x09f04c4fa3e413b7530c5bbf6763a17ba5a60410cb7c1e5dc64bd350327b559bf7acccadef2a69e75862e04672330cf176ed16cd0cd382a343a5b75440ecfeb1	\\x72221b73b5376a4120be85eee6de880ec023d5729b175212af18ed0deb4a16324ad42867c5a2af504c97a2cbb8f5c5672f5a76b582849ce35e9241b0180c2b459e47944ca631c38703bf2655d47d07f21789156851b69cc7b218d174099ae06d45e037bbbf1903a03e5972a129cd70b30704d8e955d452f1d910542359f04ca0	15	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	3	\\xf29daf7e17f95d912de49cd8242155beb01d3ee8c4247562d1e39f5da69f4fd4178a186ff447c07ef267a6e7941d2eb690e3097a0f1bd0935e879bb69f9f8a09	\\xa6208d65d19d9d459fcfd64b969cb76d083886a0f7651dcd1fa4c9895471b158033b54f44ee38b749ceb8ba002ff302938c371875081ed57de15001cbd01462a89b45244bb33e8e30e69358d3ad1817adf6832567f4592ba911f88cb832d9b8278b52fb2c8112d94dc42aeae42f01c94dd2c9b8611b02d55210ae24ee8630955	\\xeacf2ad4608128d9b6a463a905141d574c9621646e1345d78a1ebdb0912e56847b8067e009875d6c56b614b4978ebe2c8aa12f1aa6bc6f6faacfecc624ae41cd	\\x73f190e81f8b9d6cb59f74cc7fb9bdba686980092260c06670bd96295a047c0251dfa9b524c8dad85bd662915ae4378fe87e0dd3e5264a8fc63c587cd0c9f562b4060d4f1ff35d0441b541d313440c6084d236188faa3bb0560b6ac8b15308fff8636216a2963f63d9ccbca87dc20d26aa3b854805626aef56c03442bdbf782e	16	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	4	\\xa92fdde534f01fe7e00e26d8f8858c566c0a7b75f5474258d6f84734187bad922a4b0a92be5a4cab369c4424bfdc13ffeb3d6c6c7cb3cd8b96faca202d409e01	\\x6f72719d46f9dbfcc29768e731addc3099639fd5eb7e236ab736b24d07c274421dabe269ae7183da522592113460eaceb87c73f85af889b53530f17ab009206575d7fe8df18f04944ca7f9bdaf9a11fe55fdbd0c12fbe654088bdb2ab2ef7ecfb5dc5822a7004111c15a62af2d17517262b4e87a90ec91390450a1c263947c9e	\\x4ae7b0f542ad9818ce08091060449d7affd78ed3a4f05aaf7e0a1c9030e616ba34dff16253c9f8300f782d33a6a514044a830ee1d7ae3bbc688529e658c4a517	\\x2b11c8bfa1975f040ff12b5b6c707b0eeae94958f34a2c4fe852b556f3cf32fd8e25b42212461e710acc9fd221659cd1f695a3e58db20e1c01592cc81398456a471ee2e304e6d641de65cb8ce97790616873b1bd48f3566f8a2f3beec50bc80dc559652b19458347a262cef58c53d44bf1af06caba3dc8ef9639ea2d9279a61c	17	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	5	\\x9c13dc9e8c89e016bfd68dd500ee1a9d8bc9c6a133e27a0dca7dbdecb974f7c1a2526dc217c37bcba607f6c05288869f3196d0d66e6a9c89eeaa8a95c155e704	\\x77b47d2533c7ad758db4fdda523b81bcc7be5689cb44bb2eeea254bdc1f4e84e4fcc7df67153ea2edfc7628af3304be2d91c3552fbbd26a2cbf0edeb89b40d70ee216feae7a61665ace0a5f543b9773a0f3fffa7b2a8a17d81087c20d6cd6a4dc7b2c94453199004995b0fb1f1a5f6dbdadccc02f4a2fdcc52282ec493925a48	\\x2ede40c3520a6552b7b8e3f8f543944e497785a645bb7aad3667dd32e0ca626e67573ad81fa2c6d84af2d090be714fb20851a8d50063b204cca5036dc2bec515	\\x812afb6e455d91797cf8e81e804f64ee8ba1f044208b70b89f82ce72336ec0bd7f67ce1bb860f32d6cd85fb0abd1b9c3cc28e8c37c74f647f9a40cb2850b14fd558e1b8a606fb5d667bd963e3e1374569f64136a0ae6d9aeb52c323354b1ac8125189009175d828ccdbcc8b2cad9bb44bc8ba3db04dfe1f9a34c12fe0d39f722	18	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	6	\\x7480c96b8413bb23781e2bd6c328e68a5c33e9b9a91956e8048c6131adbcfdb509a3cf48d6235620daaa260a91502291c4896389b8d6dc2e0a70903031d9d00b	\\x50056718cb07c6e8e31cf3a77be8d859e2347b8eaf6d1aad1027e2720412bed9d54b50a9fb9ff5cd0841b4bafe8392bf834c00a0063afe37d4870b975ea92260bb7a184dbf08534516c49d8f22508ea71424493d43448bcb89095acda34759436777ddfb81b29983ff7d9d7e520ce337db35fad18101c149df0c8cee4be1b452	\\x68e3a6669f7e7d9c48a0f8e50f76209f0dade4cf473b4521b3267acc056987e0b5da2fd24d2f8834df9dafbc8e9c2de952aadda7807ae4f944af7c31bb36ec1d	\\xb05f7c76b506b54beba56b950326055c43d93cfd7c4ba9bca127409c03bb05084706eb9a4e583b3455a6d67d3620f640af1d7c5152bb7315c71efd8877805f059157c2d88d53cb588bc426c24b2a24380223cbc117f340b609e50456dd90a4c7a288ae517284a2069a7b7fa6c4e77067a64c2ae96ef585d81b4611408f8bb1e5	19	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	7	\\x5d9c20f6436b79b5e00fee21d85b60c400a566f516ac14c04b2fc98f19aa64f6f92e41b49e2b1df5c975738adaf90fe5d0ec3b58875f758bfa86ad4cfb733f02	\\xa01cd9351abd20fa548b33f11cbd92d9ebade45cb9eb02efc91e7b8c56efc941be2965024c8a45b6a8836d28e22d6520a127b64ff090d69801220b0ffde77ebc61a06e3a386e7b0b548907315a25245b402c9688c09930f4f0b6ac329aac6a66416b2165fbc2251840c37686d06b9851c5d0c344a4a02ca6fe5df538ed872511	\\x66485821c2a495d23a38f96f2f25b182e33a2ebdf974b307abfc893ec5fa5a34078d4cba53a2d8bd366df93a17f00c534b356381be399da16a415445d000fd2e	\\x741906911eaa4eb802e35d6f307765a55e312a4071edc095612d100ff6d4adfd76233bdb8d8ad474e18e4961f59402913631cdb3d1cddf68b2561bdab49dffbd37ffa49e2b781ef0b80963b6bcd0e92e5fb11fc16684f8fc6a165119f9ee0c16a673d350eee33741583ceb09fd8914ac0e1b7b29c79488eda9eaf7a1d1dbb88a	20	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	8	\\xbb40f080d55ba8345704091ed14e8142f42424bc3c13d8b6dbb898d60838e4417cce58d6df0aae06729d6c1c57b6e126c6335667eca2e09da1ea6306285ef904	\\x8261d7c73bcaaa26554944a61f2eafad8a66bbd1bd5b2a06ff127500faa0d6a929e3f06f79845f45bbe613359a42b74f5e2a6fbeeb2d7205a30e5f8ba0111a8a301dc714ccd55b48b1e5323ab135c2c04a60705a76ae1963b4a2beb5e939d0c935117fc523721d016872309047c7496fb5ad21a7086cfa65adc7be5f2d9dff49	\\x82f022e039e60482e8533914a6e801d679420504bb91b4a79551cb80ace81187fa5d7bf7e0c6fa74f0af418a4a1108e002a23447d520087ed0e60bbbb574f4ad	\\x20ccaebd73fd3aeff6b56390ed34bd461f71f6f18151e0fa62b70146fae2c8b338b732020852833fb3b9422d00bad834dfa6cb99fbd41b1a593590442110979cc786fd3795124d03d99fdd89087aede342681c5a95bc695f2d119d85e3f6e2e4f75c60d1430645df79005617828e794b5a3ba6efc7724e3905a35aab80a7c0b7	21	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	9	\\x68663ac3d1f9dffebaa40f622810c03b41e32050e3c52f9e3a0e2395063ba561706d2f74ad2b381f4b6e502d01245e5dac012db0df9889fbf6e7e3231c5dc00f	\\x5abc83796d7b974083a34e991c5799e1391ab7b5d9afa7fbd2ee95078ba5b1d3cbc032fbcb1dbe32678b56238f70820f165f8fcd604e61029ed89d1b5c4ec7366452c267f3ad365e14de2d0a3aa7d393ae452fb22a37c60059bb4c68520baa8ce9fe7a815539343c9b1045442d7362ebbd4153417d46b4758caac021491a6e96	\\xe5804a2bc97336c3e43cf6e64f82c42db90166967735d98bd8f1aed6afd034fdda6506cce55f64b269a37536a4ff42a9afb199ef3c3eff549da3b6c3e3c7dcec	\\x82d1c7ac91e663b43da98173fd08d0452b2cc6b6a456c4627ec70885fd0291d0188abddaf4a686023e56c1c2e6803d733ec3f8cf5a1462283975ae7eab4b14f01ba0cf4a569d96a26012ffc6460710010c0d244af42bb40c20511f4dad2ce05a19521bc45868c23e11ed283032e533178c75360dbf259bd1efbca529b1ba47c1	22	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	10	\\x99aed228ffc4c94ea2ff401ad1b32e0861ed56b0445a85e4d818f5ad6a15b056f90611d9efae14b7d0142ae74928324f361e23c68ea0a75c020a4d1218ad3d08	\\x155efd3269593e2d199918d62f5dc99219e3579fcc6f31035256215c9ef5cc91495c2f96678f3db1125af3fb9c1e4727b4507d2ead0fed9c59691624fedec8b4d3f8481b56103923289d4068bdf88787d8fd7726c7677c58ba8c646d84e672983a0986246f5853b7505bc96c71f8bb6abeca88976f4a82ec0ff7025a655ff6d1	\\x001acb1305d1cba50fd40c423d7958713989ba41e5f3a2e2b7eb0f74387079895c19c21c5839506da68794dadb4a1b601af342a5732528bd90d39620ce66a9bb	\\x1de7ba050d93f7c571c7c2ddf2ed45b6c61c7fa1e21c4dadd6471e0012d16347914592d60b21f55800de7999191ce3d03f9e05592a7bd781b2402ad81210fbfd2799b131a63eb47958052a8823868c980b0fcecfeb68851b249ee967604154ec62e6194324345b2d8f9ac47d80831d07ff999a8189ec1526454e4921458f2574	23	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	11	\\xcc6027038cb82b149e5f0cd1f53b51ba1fa25fb39fc5ba6d8f66c1fb2b71542833b3c5ddc809600440f1c7325cfffd20604f93e72fddd05b3c1ab7e9b1846e04	\\xa1d6506ff11f6a433908e371419bffde0a665efd3d9a776fa703b4d82342b05614be29b43c72a13a458294f9fbd18430c9de4631c64461387d51cd15cc92a433fc46c26c4caca6d132b824695b1523042a4a91e45051c88a92b7fc799b302fbeff9c85a6e054f534361b06b183cf32e599754b12fe4b7f9c2ac12a8a0836cb10	\\xda5fb100617083b9a3049323d9cf47d26d2cee35b1061cdbf885f43d4300c520fa0fa5fb0e7ecb429ab2ca04d09ca30e71eae9804bcd40f704fdb70f40ef7a13	\\x8bf8fb5d0cb2149a07859bbd18b6b73c55143ac2153a23ec420d8f582bee8a7c1e929c73fe823749bd8093a7d9b374d003d67b5635fd7bffb22f9d1fee4934804f2d213a2f2c45ca341669896b0791c0007125a427b5a2b049bcbb44f9add73106887121e94f054187f82b349c146f45174b1b7241a42fcbeef42c89754d2992	24	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	12	\\x1cc82d15cdf330a1b56d48ef6d0e9f339b3f35ba7930dd2864b279df140e70c19464e4518048cc6801d6aaadfeec85250192a7d2cb57df622a3adfe124430904	\\x483af405df2c111004f1e8393793cdb1b2a3bc653af5f59fad284669eda09a154f0994da0e75afbad599e6c89b034b62a691bee8443e4a206592446727419469a327423c22e6a4f6c6e7566c0f96846d6da9c6af323c411dfc0694143497413b35ccfa809c6475d3669ae97db8b73d43c32b010ba39eb36959253c23eb5ac0f4	\\x079b69da5ee674b82451720984fe17d7f20dba8ce35aaea712b3449ef7ce3357d783d11e2b3585ffdcb4fc71eaaa7e5bb086807a9d4e3e23a595ac18ccbbd26c	\\x7f0b25837363abde1361b687413011fb0e7adfa7054f4ce189f2538b2e180d346873df7e0f71b7492a78c0c428538b4bb5840e5abd1fcf935a41fb19b82f1718baf475e36017a5fc125a3e01ef5e876f2ee50f6c7b4ecca4ee9eace93e397ba939844874a5fdfd3c637c3630881ec404728958d78b0be942ae660d0550a3b278	25	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	13	\\xb67e82437dc9d29f4cf6e2d8829d831fa6d3658804a211677cabbc2a9fcf5942ee22ef9e48d8eb0b05d15637a49fdf0e9ee30c68da9651e14424893715f76003	\\x2d9c672b25728c94eab16fa4414ad08d980348e68d2fb67d661d37ad2a9035b956a7439df53df9c19ef716ad7ef91b5bba40af3b409228e079efdd3ac24a3ef644c3afd0eb161064cea793c309f6946a8a7ddfab5fe3687ab1149dfc22b389e31bb05c4ccef8679a73efdeda87b304262030e0fdac2e373df64b6cc5ccbb2c05	\\xcf2d3ac846f83319e6fbbb7ef58013e327d34f5fb56f027f296d36e30ee4c6f54ea51082c3da862183e0e26c6e57657c7519187ae09475e8f0b82aef4860247c	\\x0f2d62a2be1f8ab85129d574c32b97cdd5a033baf42238d1473cdb3a3acf90ab9122ddc923fe65789ceaefab2425c1a5ac941dba1e440b787db7c4e9eb0207091ccb69088d241f4d6c3778ff837abce7e96a29bfa5702e1d6bb6154abcff781389252dc162a77dc244d7c368668a05f318acf16105b5d7c709e6e016e43129d8	26	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	14	\\xbe643ac69a5becea44389b0eaadb21d4b1254db141e6462c3b9ed5e29239c3a587a41b974f0d09fd4915c38bfd550be20b2405b2f1a66e8aa0a53fbfcdada501	\\x4cc7902fdc90f8ed5015ca6684b083478cf0c22618998d886d0bc029bb96619ea337c56dade9e4b9d85bbab1959380fee6845d3666a28e23c23e1f303941477990def2852a1867d44519a78d3599b0d69aaea16bc085a67f770364a6ac478aa1c0d406b3a68a16cd8ebf2c89f6cb62ea04acd73efe72c393442ecd19c9707f7a	\\x3b50f24f20a097a7701ba5c739888ba8ba0f0fd1f662657c126540e47652f7a6d2c1b475633498b9fea14e80f94de9a5a58eca832a8add283b2807b76988ae4e	\\xae7493d0044f6636cfc3f31dbb54d8db0ba542709a0cec6035bff9a93b223aa4ee31f2313e75b94ed3316314f8bec8882e25c2aa9144b9e8267ee920e8ace5110593cb9ce537106fb970cbe038d9c3d720e689ba24bf6ab48ada21774c200412f9e693357bd124a8444162bd70336ccbf57d8c9d89dba5a702c5bc1631f3f419	27	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	15	\\xb7ced5d7c717e459d9bb7f90f77637774377e9d8427852d8c2c8d71189782637f6b5cf22f1cbe412efcd5e0501bc0d9c1222c34e010b98c001098aea0e22d90d	\\x8138431644ea595479da3c4eed38f453786ff16e867f6e9b085b89f737cbdd252b9596ea9ba2e78cc2e3533eddf4847c26e048f94e6b257c3aa2a956bb7eae69f7fb8f52dc9b1b5a354db5eb4eb430df6a6f125ce67ba77d0e3443cadf9eb2313c9649e2171ced8977e9026796e6ae1270f0e37f3d53261ee9e3d8fed8ec88bd	\\xddffd94d63015a2af197319e0a59dee30d035f47c7c812246b316d8f57b47b31a3b112331efe26d811b5404c83af52c54cca3bdaa7dd2095bffd2dcc49da7b27	\\x095c9df99c12b23236473e037d4dcb9d9744878e27c4be20eb42e39a865bf444c0661d23403c6f79b5df80eff589063df05d8aa0966638d4a170d8a60c334264f528b6aaddb3869bad25cfa17b0cee65684902c80bc1843f84c91ff187e993cdab798ef416d5fa7796d170b0ef77b548e8ae2c5f762af4d9f517f7a14fec6d4f	28	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	16	\\xcece1f4852237f3d5cbaa9eece591963d6eeeda4ab463298eb410b237f8720efc51d70737b25ae9e3118778d29a2482f4a597dcb8e3ec7c7bc3ba74780a6f80b	\\x0144f2235bcda9209e78f2b6d9f5594471d7ef306afbe4fd1d75eea3d22e5d35178726d2a15dfee3ccf828ad32da7e1a3f1bba7242ada26dd0163b3ce74bf4f950e6f4263da797ed459994b002e11b03e8e15cd00a06c41447c52a6f21e0e6fde2721fb6bd8cb7c992f5c6534ddaba1173e05ab7de23f6cef4342de18430aebc	\\xb0363cc5e518a20db1dd82626b2a7f4198fe4534a1830e325e2e037bfc59c4ccf939e0c0e26ef54052a5ccb6740f60139a4b3a2b58daed8dc25a4465674d53ee	\\x180fc577b5f9444cc1d9ddc14c0f73a8ae83d4c54e49e2710416a97ff4874c6e71eef898d84e8a210d77ba33c53d54132ad781247da219a405227bcd767f1ac269d1c21020023b436926f6eea6a19d14916f5a2d59fdc1e7e337a71bcaa9702bfd4706f5c8b9d4651393778bed493df228763d6e3faddb1bd786145e48fc8820	29	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	17	\\xa72cbeb6cfaffdd035a48b1ec5437abe20547fa063d23480c61cf9f6010c838ed615609731bd7c7f5114d45896669c484c3a7cd694daf47e7d7a5fa782fe0400	\\x3f033a00a3a33869920b84aa63001bd21ebfb0cb27d728e1484a6b0e910b267ca42fd618e15071ed46104ed52b807a86eeb054fcd710273ea7eee11543945e68142448fcbbf50a12f4633a9394c90a4bebcbdc8278e2552e1f825fec9986056c3bb9989b7b264c97eaf217d9907ea78bfb9d0859ec21c2aa847d5e7172a03eeb	\\x5a0b7f81a9f6e50a7e99504b5eedb15b87f8f621639b437fec7956f0b5f585f1c8197c4059db5b241f445aefd275f221830fee159015520af6d4852bac76ae06	\\x4fa77f90b2e8adb99614e3c10ad1d19bf02c91be6333c0ca9e570b470bb76500d0e71380f8d6a6a42b4be176b0cc720d59b22924d42973ee1b27900edbe1e0bf3b6752d25ff057e8bb01f9d93356570798cb612e12206cd5074a5ee0981e169f0e0233b622427698210206936959d2071c8c20ace683ae2a1d6c898ecb4b3b30	30	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	18	\\xa696e6606f50264e4c6a167fca1d66a5cd5928e17967c42004efe5fd00f23e734c99161c1c7732e6040c09b932bc4f8c64ef331040447462003479b151a6c009	\\x8530db0e15bfd37bfcb71568a92a1d61333867267891e265d2220379faa03e66a436780029734ed1ee04e0a257440b6a6916a6888fdb8feb2239922fb5d4b96d5eab7104c5928cb0130c896f87668d1e7c5be9b275e4ebc0b03b20726e2c6fb17376bf3f93301d46370905a7124b6d1c4eb1e03af8cc0b2d882a847a315d04dd	\\xfc4ad397de7ed96a4fdbf14295ccbfacf8101a50fdc67ceecc6264f7015ab220bbe00c9fd1baabfccc3d79701a8cae1b4c785efceeed5f34cb7d21a692be0206	\\xaa0bd071a65a8829364a3541b65eb0447729a0637e3a3e2175291567d8b429bcd49f8da429657aedf3665d437fe7c4d32f728b9b8cf11d8ea3038657633fc69d8e61e44f3168a319c223bcf848e61236e3659b5e97d4e18d7c70c3a76e9f01603f37abe3dcbb420524afe022a9aab3d1a5761a53ce383590c854529c2c5e2230	31	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	19	\\xa2763692b774a6dda81f07c6b5453c681265dc9f85f476888316ee06fa3b751890337014a0fb1b3936233a1e539e421db8cc18a6424efce561cf3fa7cd8f8b0f	\\x41beb48a34a862e3c720b0b169b4aa127cf153548b9ff0892a0fef6b0c83e255cc2dccd79fdc8b9b2c2c84bd96eff2efc190a77e66aec32026266d805bb979d68889f2f12d4b13e71b1228dfe2bc1f33e60dbdb833461572f637bae3c0e1b0115cdc80ad045c645db5f2bf3e6d3075c2fa98cce62bd665bb0344e3365ad05892	\\xe17acfcde60e91195b117e048905b638b9c911cfc24ecefd9139507c540293d8ccca421ce1d39ddf487931663c42b41ac68d199bfbea82acdaab187311e4921a	\\x5d838c0d9614f615d0ccf88a725e61c136d809fd135e20a16e3a81bc0f8755c330daa3498ad88d7994c9a17080002fd56502782bf3c39b5c11e5f06487b52db9ee0226873972501b0f12cddc5c0fb171b21a93848bb369ad0cbf7582105d6edb4921eb763a4609f05007be2ebf988fa8663aca9829e2ee95bfa6cd8d7bb59a2c	32	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	20	\\x207f063a243c8b78f6d1216255bb9ea463389e330049164167ccd057f75b4d6e69b1f59befd50b9fe099b266a01ce233cb560614bcc907eb68cd0317c57ab702	\\x763c1ed666e118add0b1685988ab93b6b84ef987ff5a616d4dd295fdaaf9a687dde4e8ac2d2668db4f7929ea907d03749e26037ecd06877042e60d73fc25ffccdb2efeae0982d75028762c2c759a97834c66d93eb982ad21ae1dccafe0badadcb5415eb50587165065581f917464f0568850f8f76a8c3ba8d71cb743465f4059	\\xbe023a3f09bce963a761b0d321372bc52dc0038eb5fdbf668c4f145079c28f495d04c3c854a5357b9b4b0619b745b38172dbecbaf845dbaca449abc039ef1ab1	\\x4f19539dbb4077877188032af8b51030c3c67a4d366de4cf82a52f3000c1b2c79a6726de3e2bb28fcfd166608d959cd0053821c262dc4e1d0eba4c2778bdc85a6358a8242cefb5c82889664cab666cb605e4caf6feaf28d71bd6c1c4d7203a5a3e8b7b1c6c7c31e80be07a8180c7f2ad885a43fcad7593df09a8dfadd6fd5cf4	33	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	21	\\xa0c6b2c53aba5e1ae108ce40498d9fa276aa4361ae50815f5abb817415f6693cc813acc6e3532efae76057c3ee2d2e6721617d53fdd86d1f87676ed73d878804	\\x36c7f9589849fd2aee525863726eb162076afb6c26d11fbea38455cd854c890e7186e50161bdf535244d986f03ec4b98859fa02b8880ef537abaabbdda50486ecd9ee0440b99f58a3b9425796ddb3de9df2ae731a6db2380bf260004a68508a3f6434fd2a30169154cb0ff58dbbdb490a00eec7b6bdc39cc5a407ec6f2f42638	\\xbc56ea43b0f841482810ec4783600a02ec316ae1eab215ad8f71cc4746348e4aa856e873b87db94cdc439ccf1d18d2a323b9c3ccb3478ddfdfb378e0116e25ea	\\x5b9722c0def5898d9d8f0f688fb1975c45d26bcb589c84b2f867604818d379b884ac830d76c4bc8af8d5c9b856797009e62b5abb43374e8145dc395c195a8813034d222670eedeca51ed46e2fd2fe89b9e519316ecbba8a9338f6cc5d746d40dc40f1930d45ef60dc9c9c1fc85f555001b95794c27ec16b97c8493656297204e	34	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	22	\\xed7434e8f97429ec44171ba9f79c271dbfff0c49db92dee07787bd1fc998f7dc2beb9cad2d01b36ccb00826a9e76e7a05c22dc4b82f4f9014cf0f843ce4ab604	\\x3d99d1548e6a0be45671aa53af28d5e7cbd2b6bde2a149d41688264af069a70a6d54366e445c5c533e25584b48549a73d393c39978091357bd0e926703f27f1d1d3fc313bcde2d3034dd18636382ae3d23dc44a1d9b9ab71ea012a1e5822d71ac45c3cacffb07b439e1d0f1bb46f20dad88e405949f619601c0118a0c1a04579	\\x252d0f6846d77f9461d506e741acbe3f4168ef91a13aff8fa256d6f0cb0ce7ff3cdf6d34fa6b7c0818689c949f4407a93914003267d40da0378b9a51bc9ed0a6	\\x46f13cb77b15f3a45d92f23b7684f36a1b889e9e972036276f5f3d804af4a85a6f844fe4c273390dfb63ad15e6a23c47af32eae3197f006cc40508b8406b43fce3acada39804a55d17997b7ce7bb45b9461d8e4f425350626acad10637e16f0ae43867de39c395a9baf01aaf9a730d52e7fa7f19a2538bdedb28da9f619a6769	35	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	23	\\x05d8462a322e02461c1684e33887a3eb3ddc91bf3031ef0ff6913f2df8a3106ca071f9d1e2fcdd315e5476d3b8de07efe9b49ad1793daffe21127e2cd5590e0a	\\x9016dc05b8bd97caa148a78d9a1512e8ebbe662c476c5942a99098e1a2ffaccc9f88e868abe167d6998d9931eac69a7fc0412305d03339127f3566d51503acb2d68ead991906116c7f5f959b120b62648034467541f2317eab317bb9627eb45dd08162d5773e6fc5fe6b469016dd793565049d3d685994a1efccfe0ea2f1ff71	\\x2e11a63829808ad4927c304775178a3d4992bd5ee7b5c446b8b4b252659294da0ba87b41b008c931b47580072357348528bb7c632d663c9ab2d73a7712709f1f	\\x212f40958735dacab1019ca5a77708dcbc8f4112d9dd0f33374765668009faf9bd404970f497578bd25ae2491cd6dc726fcfee17920d8b17e8c40007ba131a27a5d2c6f368eb526d24dfe28399926ae83aa076206af63ab2599b5bcd768234c13571a68fdc93725e154f146bf95c10f48a127bd90527656ba85d7da08c47707a	36	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	24	\\x1102f42586eba01876f85c2a50a046f643f4c06c2345c6653569fdf8a196be2208313e570ee2bea180c8b7ee950cd8221735201109bde8ad460a7dc9a3bb9003	\\x36e6f57dc6bc30486d24104130b588249c49aacb7bc2cd856df05b1cbd9fde85746802a8e2a7c23bc68fbd1a69e191091dfc27d4027ef41a941941f1745cb71857957f1b5b8f68f07bbf6f051d68546ad48ebe96c7440779664ddc10937dd13b4f668a41dfcd04ad5691c3eecbad95064d7da18fee983f32fb50ccc0abd7db0a	\\x006a8ea990150c8520dec31b6077a2d525649fd6619a3583a558e67e847b2b11992f4155d7fc9c1f9133c942f49a3c6cfb006fcf3b3822bc5406a818eb1c3514	\\x1f1c7a8e85292649ab72143f9e67f6fc3646afaf28bd31036b111673e075ae986aa7a1ebcc901666e0507aaeba7ea45ec405485f082c0292639db9badb425e7713c280593071a298c20c2181e9f05f754b5d29242a9ccfed5db2bc5df83022577c685dc25f623f3683be641a4d789e9c2d28222da9d65f8ee9c8e43d1dd43c91	37	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	25	\\x7e603b1098a5467e4c7bc73bf08f443665594f56eced66f7d7c1d3d2d281143a9d61a291b922066881ebf40960a3b78b57ce5ff1cb5b19a3e965da763e0ebf04	\\xa2a47474fbd492c67e29ff542e318cb721b056a2b2b51fd9a016de67200d86f24938f2bd1741a9d8ba46598795b24cda396e23e2083df9cdf3990b190a447a1bba560f50f1dc6af828021ee2d845da6a432e0ca27bcdb3f172e3fb9e3b2532472d25cb56d90dae8edbfa402ca6ee40e36e48f7a8fe6c0bf100f8c111794890bb	\\xdd4685b24202a22b84ad2b42384c7a76047977c917559d710ed3da17bd5a1e002151a646fd67de03dd5e321a7c15f24cfc4ccb4307a9e1340e7a501d98ce7eb0	\\x363c71c504a82c877861f9e161f8e90965aaa8541244e319fad775b7ccc5280c74e62610120b1f8e81a9803f6adea56551eec4c184add8d788d5f4c1cb03902362ff9be31a7c77449bd4ce7d32a4f545437726c4d316763ec3369c0d1122efdbf98fdfc0af8348b6d9b3bfbd468701f9ce3a536c0221682b46a4879e13692dcc	38	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	26	\\x0ba1855105b5574cb647c491e1c95f6e627023fbf7526e36d06f4117c25a15c9f412776a74371c9d6c7fe02951f554d5d5ad1442240858493835a3f040d30008	\\x6f70971e672767de28a7b62b764a3d8d606711454f5ac002c9052f90006b6dfe60111231e970a2a868a6975200dbfc3a972d1f4eafa260a56885f67e814357bb82bb9d00f0ce22e1ad8787ac10fa6a08d46d4fe13abf991b66f12744b79566655738ff18a0253dae3e74d1457fd7893c0ff2c87885815ec1eb32dea798c5ded3	\\x34da3f1964c5a373750a67b586236c572c68bc8331f5bb13adb96094cab2f2e852c31a8cb350f11ee2a7f954373259ff02f0bfb64512b36d02f7e8f85eb0a2bf	\\xa886e59f0e938b2346be805961af3750a83a0532366e310d36d63e263cb0143a3ea635ca0dd1d9f23ff429f7c13e98052e043669d5dfd46173137878aa59fe7464d39f0a427be69731a0cb2aa8929d14d68f8d2e74c7facd2278f256cc2a8c73680dc4d38ea4b833861bdcf9c25a2239870ae24b0289aa9af66813f3fd1d7736	39	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	27	\\x567193d9e6d34bbb7f2b870528a1a25ea64fea792bf09e7aa7c47e3739121ae62de924601af46de7280b4e91fb999096889f99be5155ca99452fd023a31e8f0f	\\x531d2a4aa6e9fdb45320a2db4805df0a8f3b76179bced203758642aa060e01a73423c211818f878c963b6178923ecd62b4f498c0ce4b991ad041ccbe863787d4bbb8f651a677e35c61ed3f2456e9737e62bdb8d5a794dc2e9780259308ae5f771593ea68afb4c70d2f438b97b88996f13bb0d713e81a17fb4bbf88f09df1bc42	\\x643ae4bb88a94f75713d02938cb64dd9af59ad94d43006b0c04d548236fe54959d29e446c50f776b754ce59cb82111b5d3f4b1d4036386b037407b9b7fd96dc1	\\x62ddf8f91901c1161e30f415d6aa6ed7874977c7d54a3d3818e67c2d29d3cbc1572b122562f62152e0ca1c77b86d1fce7bbb246f0ae3ebd88e4d812877cecc79f735dba1c73c4b1ee6ef7d8c26d6ee31440e627c9e37bdeb97e80958281ad9432d653fc8065841a1aab380bcaa70e9d3bda51e9618f0dd13e9215132b0e2a4ed	40	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	28	\\x6fe5700ee467be99c58ddc9e8589c671d3c91e562e12b895fad9cf29ec2e90044a964d14275eece426a822e353eabf7f0cebd2d2f5e4897bd045c82f71bb7504	\\x37666b0b6f22522e5c7bf7688f50ff64e6838e89198646d58a869cdcd7968579089f2b19faa8d2e5943af6ada4cf7de45cd43f93560e6e9cdf5ec34b8e18e58d952406222c185b4d9a84cd11cc3ee090eb999d45d7daa3007a72308e2c1528f8a351d0a9b3a5e6da9135057c76525424a648f7e3bc8eb21987897aababbd9dfe	\\xd0e8cf28721255d8261838c549c6c774ffacf602e4bb226dfbbde89c29668a9c35a628c36bc386a34c88a9ccab7b31a7b83b090c722dcd809ba97a8eef5c7acd	\\xb205e3e66380b474599277b20a8a5f9bd0214a716163c6cdf4257649f8cf1bead74da8bd424646c6dd445b1fb30c32b7e54d53e4da5630c156a6d78be2527217734694bf7ad6b79ffeb95c31223276a249b4fbce9b652e59100990e6f52c88d1fdcbfdd155a9be27fe0cc0472ae73a08030de8136fa5297457bab36f165e342d	41	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	29	\\x6380283ecd6a75a9070326805e80e41b309c7db164fc6c74416acc00f92afa8f7136e97015b92db84ecd65e000ee7126f4db8bd895fb7673318dae356f94ac00	\\x83cfe1eb56f692e7428df6d765a80b6a1d318981848f837a13b9d73efa3f6ec2288f04143bbe97c9a13cd403b1e34fe10b4b64dee2fa9fa9091d5eb91966451f9ea6131085bc24f2b535aa47ac78067a97dd9a6c82d75b88f7a1a16b7a699f1399381c0358c270f1ded689c0742e3c1aacc4b1c73f379e10647d927d999d6aa2	\\xad7b6944fcb393c4d238d739b73b1a5508803de466160374baba5c99cb3f7b0b8740184b7bf1d26ee3590fc7494873233383bc523e8c77263921528f76f1124d	\\x2838deba31115cba2af5706e4d884d69d3a6b954f276fcf4504a3b8092632ec64ff96977c7f8b15c35aa1c34390059f5e810c5e08be201f91819a4bf675e44219e6f4b52d4db52de15c08b5628c887e0df76df57151b9107a373553bb7f19edbb011ae8a2d40b1e1f05120792b58f3d3e519e8fcd5cda379b6192b8fa602515f	42	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	30	\\x4f3b12da021980cc23fa04d1094a722d1b68a738bf632b63822fc2926a0cb935c983eb117674b44c23623fa6ac0a7f043f3f7dcef7897eae8af727f137810d02	\\x48aeef503177c30fe1a13885b71a60c1232c1f04382444876cad73453a2ec11147439f3f4799ad7e0da1fb7a648adbbafad75bc62bf5ec62cdd9143ed348a7c4dca7483876e58206ab9b1a483a8a428eb8928f57a10ad652a448fdd7b58cd5dc883d039ee534463048782b25c672602593241f602ef3c5f577e49360c64eed9c	\\x21b118eaaac5672260d62de3b85622c795e180af207d3724eec8f8e08aac0952b8bc53d13ad228dd2536da098128a5b44557b7a65fa9193169414f1b0cdcc374	\\x1a9e811375d46fe07ff3bb26ee68c7c7db0e922a49b302dcd220d8bd57a6a55f434407fe3162ca6f61bef1aca0850520a43383a8a33d56874511931616d843db6096975d45a56af1467cab1d0480740e500a7cf6912d12593fd633e4ee547872bdaa4ef48e3859dc9163ff9285e6b604b86877f635018b267e9763c0bf942b78	43	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	31	\\xac1b4a9c586eae50e0aa202801f33702142add7e2a38e459733586f03d0901e9d40dc6b4ee289b63f4474f1f459510a0c4a12f17d6487e371988a16a54f9c709	\\xa59710bf14a40aad1e326ab59524308deeec6070d5ca26ac07d1ce97857d8141cc618a6e44edece294cd50b30fb05ff41aa7f032a400239673a498846b072fd5f5f3127bd270b032c3fbfbd14ad46b4287e6c9f60d2cb4a5b02329d4eb8e5a8355c9f8aa7982f2d400d087f5962dc611a788f63647aa4a7697bfe24147d82422	\\x410c576e3c63c383b74cc867758afae6e0c8d7c210b898eb3262078d1757e9642b8b5e2078f0112fc6d1691ae264442b65d9ea18a21ff4ba044572c8fcaafed7	\\x26f81443392405d40b92e847474f18209c8cff7182e47376e17528d50c3a99c722b1c9c9b58a641a8648be0c21adc285c21197fa9df0cebb0d08c2c94ff2e0712dca627faa60edf7e17c0c07e5a86b4aacb7014631fbba5d80e00d75c317d89f728db166f25742384a2ed22a2ea7e2b3565d9e4845ad93e3f64f012fef910066	44	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	32	\\x7b778a28b7717e92a593b24c6405bf574f90054d871c76936af199b426c15272053b6749efbf8261ae4968b2f0e5ca36f9486fe2bccafc2b4c9a8d075f049000	\\x7cc03f86c39585a97a59431f175e65a30b2e9f0dd48b55da95b58c8812cee6e4b88e255a5c313b3addb3be8167f59d3b8150d64a31e3ef018abbfc6da88f6d9693c04cb8b423d6b442f759f229dc3f42517f5119ef6f3f0b72a423cd0d9ff1670822cb34d9cf5aaadff2f1c8cd921326efbec6218e575be0a0452a8a43adfd2c	\\x641b7cb51369e6ce0b35de8c8b629870450d5148ffe700db3cb032c81c3353811d3299089b3d89f1f06b3d8c0dd3e98306598a819a6d2e96ee7458b197e7bbe1	\\x73778a472ced2ab934055033efd2b3bd922dc68bc33766f352dc4ae955edb0036f20e3faf0eca7179c0ae889a463fd182952c29b13d8ec28fb644a9e437d451eb69fe8b7c6d52948989df559b5861567c8348bdaec0fc990b89700ca63abbe7364e033f7abf08d363cedab40dc59b67920fc368cb7578297f40f407b41086c54	45	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	33	\\x6e4b331815ec3382778d3acd247deec0a6dd88130e9b4f090c88ea52c28e96ae87822ad8b35943e5c6deea0e881d0426573a99026afcfd73c4e03db11b157101	\\x72003325f5c5ccf7406c26aad873213646697316a8b6f2a2e1a4d70202f0435fe64d956d790f8bf4011a5e7f17b26f10093bf3154e28299c37963a7418fefefc09368edad359bbab80062ea10f00a34e9607a305ebd57caf53a281a11dbd80f54feb3fc34ce4e518870c634cb3a78268ef2e2545f3467ddf7a30f9eb7db60653	\\x80578427524e58601400c88a99ac75c4f895eb6b0781b950bf6232fa8c40314189dc30d6e09e9ecdbd43bb64b842f84107af0edf502b858ec1e1cf6db969c917	\\x2dc5ee1dd54b457f831fec5aa81002325e41c5e83a7f42a5e8e4108e47b528744dbe31913f39fcf51021eb86232f514bef828b68135c650cfb28327a444be941112536fd9ccb43dc7fec75d4da157c524f66a6b3ac5bdd02069e04c3b0dc15d245296229b88dbf0ab2716f3ff70caf426ac69fe7dd6e239494f4a51ae724d051	46	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	34	\\xb43f2dc7225d2f48be888ed2598c86c4fd703a980d22ca16b4820b438cd512944973ec71976e07307eb2715809e5cb6f7623b1e562ecd5e51b07a8efc7e6b908	\\xb25fe2c9ce17856403f7d210688a6e460bc980ecb09fc5beee383b1ed729bc85c138c95b631a89c5866e7f27f4102ad11384e31936885fae2ee939fcb393601b319f08e1da5fe9c65cb604fdfce73dd493fe43b532cd6226b01c26f68038ffa4c8aff714ad1394d730539a6b17ea04cf87f1037c2734506b14653880b260b758	\\x3fb19ad713c7693d85c9ecc65da712842c591737b9b258ff1ecefe3804a18ad1b03c4970a48d8d069e39cb3ed3d58c0ad0a3faa36277c6ff46221a82d3b07047	\\x0f893caf44884b870c2e815505c321cb97a96da6a726f624977cec6f65f953ec1f3d64ae104031bf38a77157b4699802399f1e19e9f17eeef424b0b567c3e9e621c58151205c3a6cc31baac2504e5f20324213a65306291fc1c0b880a5c899d5571048f431f8e1784abcd66b7108aef1d737fd35b49890d157a7169a22b4c2c8	47	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	35	\\xc2e7cd211ab7c75556912805c6de798eb4ad985be67986f3cb435995771ca7fda9b425bb97caf5d886bf6b8502cf5953b181749344aff449c9bbdd40b2ccdd0d	\\x6bb05503d33e778641869b40b88c9de7570514a4b3cc35ab188b3bf3c32aff1d49c6f0fb2521c60313e9ec9ae8831e98ffbf02b694e8f97b285302e2bd90286eef34fec8165ec9f672f62027bd0649aeee00eb1f19bc01fb3f7851c1c816d22cbd5bd652bd10772b5fe764fc850b615d29ca89efb6e1a3b1598b6894cc8396e7	\\x3b67749244e6853df27c9c97faaf09fad84b6f09f468ca3a66f63e3d9942faec3ec10339712580e50a90a22a4cba0c4dcaeec861fc155d09c1ed234d81df4672	\\xa68b83a4ee9fc726def9ab615e2853e1bb13d36dbb680ccf2dee1a2f8686a59edbf665333c03976ff20a090dcd7ff16e986dca1ad2c819bdbb2e93cb6041585448887094d6aa47b5246e5546869f8abd36898b324fe0cf88e6ec0c3153a2b0a3bac0a17807452976b70fa70d5e96ca5dc2178415b29292c865518bfc07a62e4f	48	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	36	\\xd3486d979c18c9d9ed2835699bf36fd402b8bb272fa2960698ab037c32490dd11e364c5e0cbc8805a276b2e337fa14a5ddb813a2c52978f7eac60d52f7166e0a	\\x0aa872dc066f4fa6206db7d81d6c5f040ac05135cb28aa6eed74b79966e9f940610f125aa0fcbd0e97b1f715e41beea18cc88d2ae5504b3a18a3e15eea3f21db67fd8cb84d8231d4b723adb55f6709b071b934a293e9b773e79d4f6941d9336ae5df9de2c5416472d9588072a938691b53c5672fb7b635fbe4a28b9f128bd22d	\\x4e6b5eed028dc453ce8de92d6921ec81496993eafca434634f858fe0af1916a56ba9a3c5bf86664bb64b195d8e74dd150c0013d7cc45cee6f854169b1886eb6f	\\xa4b2c660d97564caaf64742e3bc151b568d3261b0e027420b9ce16158c1b56668b3a3907e5c0edd625ece9e422b366b6b0dcb691936b8297e153e98aa362022336992abb4e4db9a8c7f08d4ce2c1990fb89ab9c001b112b4936abee1aee11bcebe5af9404d9a8fe019b1367822c4c46cfe208d3d91057be12bb9aa348af40387	49	356
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	37	\\x9d0519d5c77103687b3a7219ac1b49575ed5993e10a02f100d4e747eb3aa2a77a1ba16ec81712d388f38aa081da539563bda34a08cfe9ae6f135bf5fa945540e	\\x647dcb26ef5fa5852ebdb3d6480f6a5128ea584caa90fa8c85d9fcda9b36108c1a431e0fe39850389441e3a975b87de3845077ca9b5a8c7d51652b281c79fadac3e5fa327e5ab3801fbed55b1c1ea107dafd3c395d576ac23ee317b3ea3b114f7c23191a86679080fdf183dbdcdab3d273aaa791686f0a831a81b0f9e7dc3aad	\\x70c2e7f9218daa83a2c032f1dd3e78cdc1c409861ba6d0c92dfc27cf3a2fbe7bdf41189b6794d86aa5749f04edfb130dbda82d12c6f6754786cf66cf49a07788	\\x2cc2c4acddf171f5c7c5a455347db69ff3fb2b96a5ab63301b1df48d2aa639c2a68f660cf14be833ac9a1aec44fdd61ffe42809095e4f6b31aaee1450bfc968f8bfe8a02dd00d0198a23e6a0cad225ccdfa3dacd6692843ad41a29504111e6eef7efeeff0c1ae02ab172409d43a571524db8d1d7a1605f5bca0ebf1e2873133d	50	356
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\xaa0f70fc57c4b242e2bca10926491e4df89a06662f83dc23e241511a9946af76bfbd18092e2eaff8c5bcc84233b445a7417d9023a433b06063b99dc398d5672b	\\x368cf5a58719b127f1fe5db72d2708d9fd597624ba08d3003feb8c826f847503	\\xfeda8a5e8c84f9b9b25bf6aa0f4e8b6b06b0cf33cfcd3094dd87b138581f0864e65087ee2be1958e8b57fce33f65439940463095c8a1515a1bc581052516d3e0	1
\\x7144559103a1751b079bf0505426a248fb0ecd809c0e1d6b595a17e791b246319946688f494b422318f9ebcbd56418b1276687eb210cf789bd14c9d52f8a62f4	\\x47b4b58bc273ed2dac9494503b899eaa57da3e77ad33ed22d9c30ac409c9bd21	\\x33166bcff73c24d30a905046dff0ce9a3889849f6e392c6a1e120380cfffb087dc1148cabe95411786d9c196ee6550311b4425201bb9786568a8d9e8a342ca6f	2
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x1139032e0ea15f67e426a209585486fb5e2d9fc01ae1f95cc43913c0181b7faa	payto://x-taler-bank/localhost/testuser-RtGmnMed	0	0	1612537708000000	1830870509000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-RtGmnMed	exchange-account-1	1610118500000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\xb006d1f89fdb2cdc3c6933de27abfc94608013241e4540a9ac8cc563bed72995ec4d8c1f92d300425305ddc461e556326916e301a638a669a2aa4951659aabda	\\xb50a69fcca3697539468f107889fd8f232234b803226fbfe54fa6c2fafcd6ac95111f63ae5a2d4b050a5c350d7e7659ede1ea045eb2419176838f1cd4301093a97c4faec9c53cabb3b7815aaa17e8f0d2e676bb50f7bad38b39a81fb6641ef9ad39dabec5904d9ad9e4ffa26ca136131181954fcd772c873c703085bdf5d6a63	\\xa1e6eee5a9b8f798fafd1d91ab9c0ba0dde82cd66fb8caa2229694aebc77d21c3968dfce49a8bbe1b61d374be58f63f9c895e36757a4160762d6ce1404dff303	1610118502000000	5	1000000	1	54
2	\\xc5cfc39292c33971d304766ce0100a88297bd3a47479b9d5f030e3ceb21071be6389af70c18901f11ee337bdcc9f270a40256f76d313328054eb8e5535a608e1	\\x8ba6ea76e0eed5dd6e2e183edcc2a96f8e8ea7d16e965c7613fcbc66a95c0ac0249b89ad725c32f343eaf3722ccb23687e2e6b6229546c61a719b45c43b98013dae7147cd1330ebc8ffd5b739845e7e10ccbd0496cbefa8f61fea2f7693bf66a45c7957b44fb334fabcf68d7425abcf553d70364805c643b63f87fbcdd201bb3	\\x95abbe08f55ba0ca944a36789044f9099f93c413b29f375a70d97fe85e4d56cc66edc3ae05d957ed4cb2143b60b3d2cc0389fcdb044dbe107b32db5d3e471203	1610118502000000	2	3000000	1	91
3	\\x482b7d539504954945b13b8fbaeed794ce3713565660e93ef6e6f34aac4d17f27a4bc2c559230c9d3ec448a22434b94bcbd591ce8226cfd172afd6a59912d3fe	\\xc18bbbbe1b557ffd734b135322b5fd2ae4267e09b96ab7e9f938ce3a94e8bd27e6877f331fd8caa983226e8c212fe783d5934bba2fc778bcdc21ba6e4d5727294b74226116bba1670e9e59d893d3f3e1f55aeacfc4eaa6250f0512fcedc2a78d20a8ce4ff80c1eb836249875d0cf55e0c21e38a756cb9dc4d4fe9f15f2631f1e	\\x2ee4a632c729d9615b26d07d24b4f40a46a5fc9c4c934a81493f162b8389eb3c03fd66494fba3abdef375679b41a2905a340a607ea9355c207b8a374ca1c0300	1610118502000000	0	11000000	1	371
4	\\x244ac323a23021c429cbdd5ce238ccd5d334dbab3f6ff90c955aa8c25566f9c7bbd636d9015530aa92da85aa65deb5e40eba6c5b7225947475816081f1b67b59	\\xc4535d2d5a39778619f6c21fb5dac8d85ac7c9dbe9dd98cc6d1c751d4012b37c59b2b7757a7d61dfcdac8dec8a846b667ba05e5273d3bfe3302f8ffff6b146112aff889ea5d1153891cb143560e9a90906f5f4a806c06d96bec5e670022ac484961e41cd187f0a0041d3ef746de22075b2bf976282ee60058ffc9b614cff1de4	\\x7326a754549043e56fce49dac9c416186adc91a400d20dd0b6a1f1fcdfac9e9d1799004b1d9c3522ab84600ea581df497ecb6c92f577490795fdc4c0a842ca08	1610118502000000	0	11000000	1	371
5	\\xd25c773e9a36f7ecc50592ba2433aba6784d8ceabf6574d278ee037363220885c21ba3b6ef40752d16fcd47aa005339f46ab8b0aff32a2b9bbe6a81b0a3ee3c6	\\x14b4dd359d361ca4b8221641486d5e287045a8c24643d4e6636f044391d3ab30a8fad23b4ea7a3d5f286ce195dd0c2569b1d7abb8434e5b8ab803ca860ff680ae98acedd989edf8f8d00fef49e3610076d0b6c65555aea6b89ebd37588a882d9c4404fe3927524c565a77daa59f087d5ef6721da9b1cb0e4e61c80cd4c7266c6	\\xdecec527f79786befdef8962e35fcf80e0231158ff01004aa6a5b820553e85d969ef9910ada91c921b63c2c4b0226ac99477555e6cbf39a8a8b52948af478b01	1610118502000000	0	11000000	1	371
6	\\x4421d57f10c5bf1215a7328a82f970fa7cdde142adfa8d835e5a099ee70116eb717d607d09b77bbeedd2d3b65def2194a82f3127dee580959d8ba241a3696c5d	\\x29f19e3857d379168110b2f760b6d9c96e13ec794c07f44a553890c8bc9046cb399100a97f4c1e4dcff3cd7a0de6aa81717eaee7d28fc33091eb7471b9ec36f5c1db3ef43915fe8c868e37b0c9c24a7c22be65ae2b4636374ecfb3290f63b8c8445ec29c42a8603eb222fbdb70e47fc0a8dccb1cb2b80bd9b9c81885e48cb334	\\x5ab7362f9733e276d0d4cfdff1428a5b29eae2e31819bcb5f46c7422bec06d4504343170b39d42df4bf5d1b0d654c8e161997c6fa732d2d6d33a342783295a0e	1610118502000000	0	11000000	1	371
7	\\x0771fa141ea36c3a2752ed170efcfe0bf7934899a6535e9721783ee2c9a60cef7a3c8655dcba804556efc348719c356d8b42d0f547a405c3dce6db955f90bcda	\\xa6fecf207b955e681d08d68daf3f718fa78c7d99533b75747e38f182c7e36ba1e7437ddbc805c5d3346943f6442b613d35dbe93888f6c35a2c2f238845a634eb394993b8b61ed9125b5403f0c7458908c12c2b2a53899ecea8d19b4a70852b020be01bc4e73db85b1eb852bb2f0ee0ff0df7a8d41e8fcfa31533996afe19921e	\\x284d021164cfca9ed2a00fcbbdef2973a69e3e53193c416f83b28999c9d217f74a3dee5a715120d68ef5c79b3d8ec6229dd0c6e4615e06f9ccfb91843486fe01	1610118502000000	0	11000000	1	371
8	\\x5ec9da4f0b7ca53252cdbd3f1eecfc6e400eb8d2df730076563cbc8e0725dd5676776f496cca76107183f69f17ae67a9395b5096b213798bf9de9d4ae7992117	\\x24dde36ae13134c68d728e9d0a98426b414ec8858564fe250ce577a07e15c29e33dbefd45b0bfad4c95c02674d60fd9cbd0714e9f0f3e6477becef7403be8bc7ded333dc3aa79495b0ba33b285b00d0727ce0aa928fb2ef759ac2549e0426d06eb2011ddcb0e7eaaf5ca5e204938705408c0be3f1b49e036f00f508169cf2e46	\\x519c938c2a9fcc4a9051ab8689f0bf8b2b648a84a5e319de169d0dba216499a26bfe4898ed4dea953563e2b91e25741139899bf7002236d5175bf6a85e40de05	1610118502000000	0	11000000	1	371
9	\\x8bca7990b032c9311331ac7f30e5cff25b792c9b0507f3b26dc36b4bebebcaaafcc533d967dcf6f244590d067bc30885f5eea9a6b5024e91d8826cf58a9a47bd	\\xb81cab4272728aaf3a967011108bc790328e186ca760b04713c70a075c609b257fb83ea59cab09226b6eccaa49fe784c7e3d9f98c73cb1b02743b7b7fc79dbbc8001bb2be7badfe3f5672aed2d1fd96662a2a69494153262ad1e6e1b47ba91b67d2529c252c5e10094ab305a855d2ff99cf4f7ca44e5a3aaa2261f8f6d549c72	\\xce100703806c0edf971ec37fff98aa2bd5167f99245dc1bc187bdcc03513f1c49d9c0f7a8916415080ac7c439538aa048e476b883f242f06387b30986dc0250d	1610118502000000	0	11000000	1	371
10	\\x2b1ac4e1ca3db85485c6121e92b6deb57f36153b00db709ed8bf710578f243be3b0bd823d5caf8c9e9e0ad0dfb6af753b4ce840be75074049cdc3e6f95ee6a75	\\x4e5b0d9fcd6bc0555a0c8f423979503536c5fab5f3fe90f57a668a199399a1ce024a97e02c7e04481ea9fe8f21b8a0dffb8cd58127221fd4624a87006752bfa7023b525f35964399d298ec392f024479efa3095ef47228cc987113623c1ae5378da797a405aed1fd41836fb12f17f21f5ea850e2187951f49d8c99b62bbeb58f	\\xcba17a62242a0fc1195392847fa89888667dc28c8208e364f117148ef4b1f14cd1429eb79f0314447b40c03fcc1b724a763778e9742e2b6f6f6a7d7b037e0801	1610118503000000	0	11000000	1	371
11	\\x6c9444d0523278f73fba9a46c310f5c9b3b2e48de7152d72ace421b202f33f42a6f492b839beb463c479fc5640c2556755915ea723147bd179c6ccfd3a4392fe	\\x1f6e514dc7d978ceff9777643af2fe7ed4b3b04c8f703207a446e381574138cd7b507b9fe62efa4af4c07b63d31b55dbdc8910dbd78cdfcc8afebd64a46f5cf0d782672accad59c2ff7c1c779ddffc6cb1c0aa657936fd099961b8338a74e66cc39e18349dccd694e6720acd634dafb06e103c8971075e9adf8853c5e1b55013	\\x486046c80268f5a005c6dc026e7c46f8b30e209d743de3e6f090f1c5356ccbfa3f8428ca916c3467e8f4392eed721c477695e8fea921b9298d33b0ac3b302f00	1610118503000000	0	2000000	1	269
12	\\x0c2aedde70b2431b8291856d3b32e25d2dcaf41295259c7b1c4732261a1bad6b560c414301d1d989a6fd83bcf285c2ca9d37d8b962b3b48c4f5ab1849bd4441c	\\x2231a153202b1981bfd693b4eb651c2dd135fcb8eb3d91ff8bb21fc408e9d5fd85d93b1ba5b3807578181abacbdc3176226b8f4ef7423deba7e7420d3258320f0ac7805711f2d7130a2c2171ac978c79735ae07166093e3a7d7c9ca6cb07ce82fd949b8286f4c5b3dfa96c15f875108f82309a01632a7b3545c275379789601e	\\x80c457e90e6531be39371a0c228c448f2fd4370ccb000a5561491648b65dfd4c4e9c36f26106eb6dff4ca49dda1954b87d61c3243d28cfc7199e3f175a6b1107	1610118503000000	0	2000000	1	269
13	\\xa5752200dcff90ef1dbd26c265bff3e57029af076dfa979ddb7a5139cc9faa31c075be0c4dbbddeaba399a63ac48179b3eda0fce594c88b8d33c3b7a0ada8734	\\x3aec815f1e3376c6a00ea5c41af64c218c43f9eef7cda4a09fef1e753ec7503eb0fd590c23dd45696596ef40c008431093e95b808c32b21f83ae91963cc9bdd7bb179e7d19120a3e6979212d57069c858fb9053e9f27c3396b4f8627e49ca7111e5bdd90a2c7accece313f77ceafcc2f1486485432bcc8b9b9973dba399255cd	\\x8694cd485ce8124e10dbe1e1b3f902a60da09835df74ed29ee5e7f67810e243d4a986b7014ae35042f0c323fbaaadd928c85864193fdfd2896aa35e8a126f60c	1610118503000000	0	2000000	1	269
14	\\xf3ac7a2f1577d70389ea0c0a3c4a102deb78bdfc6fdf2a586793960acc81f380f385c3cea018a24eb961129a80840edaa53af8e9ef25f3386735ee30e5cf10b7	\\x2b7e4a43520735263dfa75bab1902cc614364b88dbdfdeed71937264daf484b9abe820b403612f3d62f5c5c5caf20b115335896a3556ddedffe7d6ab8df969000d2d2c9203c217a2dce8ce874ff489f38b9393972671a35087f542e9a1a6f9b7ac1b9a331bc7c49029ff5a318cf68d18819bcabc08d346809f8a3c55eb408366	\\x04d59ef50023932017d00e88156f52f550a6e8d6fa7a56f020dd65e119a2ef22c8788dc3719a5662e654c83f77e1631e14424ea1fe8cef2415f836d6c6c27000	1610118503000000	0	2000000	1	269
15	\\x698932a8ae9840ac9d54f77b0fe28ee82980ff3c29297fcd3031cc8b590e50a585514b6f7f0163e24d88b7e7d719ab2ea0aa556c4a0c0600366c0a2d64dc160c	\\x6f7fae4d147df1dd46dba9090d64deb2d1e0748f0df462e0fb459b86ee75915deb807de2a2fdd733f4dfbd607bdee09923f8549ab04b962e1fa85d849f6aee16b4b994a14170530aaa6b2914a6768aec0b1e75531776cf50ebf8f364eec3d9a0ef7a0cd678baba67e6f21bfac5ebe6780cf030127f409a9329c13f724ca5a94d	\\x002b28aacc14ef03e21cf34fa3ea4ebf0bbfb9a0e4ef546d04801dcb249dacddb19651d05759a25e37d72b75e9173bbfec5f6ce0dd45659b7205c91eced71c02	1610118509000000	1	2000000	1	60
16	\\x4e78e3bbec6fbee2ec2bb1f4ffde7c05a3870c921d5fcf33a5e336177f04b4f80595ef33f06e4a5484eead92bb0c3241f75cd9bddeded3d288a522309b77c3be	\\x35f610ad69e177390fee1153bc3dadc2866ff6fb805abf1cb888ca23db7aa53ed3b8e46f0870d2ffa4827ec2c365ea732c165632b49e50463f0408461471f628f1356c31977df2b1db284c8844f3c448730a0704958a91ce81182c5176951178fea36eae8ecf7051c3c5ce44b7c38dd93749cf7c4b6eb18c9ccb0114aaef9da6	\\xc27cdcf8a252b5b6cf213a491cfd58bce48c01d2eac7f9a137c52bf211718f4ab7892ddae18ec98891ef1a2258bf4d3f02419f40d939a2b14fd81cee8f07c30a	1610118509000000	0	11000000	1	371
17	\\x1fe1e6360af8e9a259c57a33dbbbb4aa5816b4a50f841fdbbb047d616493e136c1015f0fed77b6d455dd7dba947d0d4b149c48e1781cec93c0c552096bd64563	\\x01478da3be80cb01668ef98909d65e30c0f00e00ae8d35cef89e6ad209fac866decee8eab389278e092d3f43580972f0f242e24a87bf5a2d7b09db163f9b633250b1c29c6292ba3e521cc215afc3cda7aa08537a4ff965c9ec8538163f1a9c7647b5d7118f54f1e495a2cfd114b4df35c315b6e693f898e8fc4ac623dd133fed	\\x6f5f9ed3414e18a6c58f3011452ce643e2db5168da702c50732069cfd0ca21172e97197398b9dc3cb8aa863133fcda018c3973e0617624babd49bbbfad903008	1610118509000000	0	11000000	1	371
18	\\xb2426a3eee63635d006e64ae596252a60e2d441b6dff4d6fea69878c38e0243993e998ea021d4b38e1c553f6ec3ced93fe67f5adf73ca4aa6d067b38b2069f2f	\\x395abe025d8644010a01b066aeff9f08b7d38aa2d41b90923338310d084777f9782216f9febf9d467182d77a9c6e6a07c6b059c411b139eea6e80cfaeb6d7fef5df2a99cbdecdf46ca565087b8880a5c8921db72faaee8be3bc349ad9fa7b6235dbcd021256a260a489fea9497c416265ee6f704e11d19390d1086f9c0abb69b	\\x7736c2ad5f52cbe7a548b2af241298d89708e0d62e0f566dd9bdf0e7b178fb655e7fd9b47ef944cc4b4433ad2276270a62b305550de0a084639f890fabbe480b	1610118509000000	0	11000000	1	371
19	\\xd5a77bdcfc42d63c4240d7722ea074f5d9ce57e5daed219892832d8d5b4703a4ee7048cb275def3b5f905b1fc0d46e6f8dbacf1cda66816fc5ffee857d943243	\\x17088e95d3305fe5740765006212535896aaee05913622357d1250247dd4a0db17a756fb583c03f8ca2333b644703783c9fd36e45660dad47ae64ac47dff4f04c4c5ff4f399b782da81cb70753561547e44e6be18690e792999f058cb5f185ac6d1438e16e814033efe328a08c0b07118ddca3f17586e675587f3427c1ee42bd	\\xc78659431816fe39d4f43f7862c586ec3a30e6170e38e973cac3d51ae428b0ff49aab10fce161b69494e2d0d7004137b338acd69c15810c011d6f05e86426706	1610118509000000	0	11000000	1	371
20	\\xe217f974336d11b0680e62c6d20a6867c9d6b6d61154d81d8e7745a6ff4e07852416e0b548a8150edfed526962620ff9b77a3f8468c2e2472ae32db7e6ef49cf	\\x50d78dac9075cba0c0a1656840d4a90faa4a83d8d338882e3fc32ea566b5dcba6cadfd6c348122054cc546b95ac48b4143913c8430c44798e5c366d1bcbbca62ff227e166259c8f1ec7f1568bd917ce37cba00cdfb91c2f8535728855b55e0297a8305d4679608c06224b9850caf79b37dac4ece15842a905b6f9f5b3b978c03	\\xc5429479b640a894b7381cf56091e98e85444a17f3e05a33e6957c198da2c9d2ad732104e08be031ed703287140e0bd61dd2438894b182c2b4179280f4571900	1610118509000000	0	11000000	1	371
21	\\xea78e711bee7b55ad333d9d190586a797c06d617ee329c2ca5049cddac93a7913e21d9205574df74d53aa77d728746dc384776d71d008f4e68591f485b0da232	\\x40fbf30a9db9cdcc3097f5a212442083b02b0c0e27cde69aac11408341d7d1b059c78dbf05336f1822b0cfc1e179460a11c86dd5906e5c214d61bac1ede0cb25c75376b1015b881c2d5c36fd2f18a290af3434e05648592f10665731281cd2dc01cfba4473c704e02b7c31ff8fe574df0d6c4fd8aa38b89728922fba6155e55c	\\x1673f0ff7d22a528b2fa9244a9cc9b981de33f016e35d3d87bb7efa632160f59d08d8e5a6e98e014ee2d9ee98e7fce2aa75a286dcc4ed06f67ae4db294574b0d	1610118509000000	0	11000000	1	371
22	\\xbcde106a535d5d96deac6cb66a55ffe9b626a32cc064def1466baa43e7f9a183f94b5a61e837c8643b456dcd889e8b651817462f6603aac050a6306635079c4b	\\x3d54133f063fb5fa23694d18bc839bf964dd380ce9da92b072ebed8f0ff757f5d0073e007004c771ce87d754f5393c4ce5cf5d5fd9e9a03cf06d0efb035c710786046937246138b8659bf0b8e8bdce76a4f1f4066491c00cf9b17b1d4edeb8ec7aaabdfef4e298c7807faa23f1788c8b22972d945c8640d383572f271f0d0c29	\\x5eec2eaa566b9e0d686c842a8762d0021ccf874a0977b4d845da16c56a74e8ea568cf39fa75b22f5a691440e87711cc0216053ad2f743e161bd7494f01bc990a	1610118509000000	0	11000000	1	371
23	\\xbc17b25692b2986f3bb5b39aaf64500bf70a09dfd32dccdadad521867f68ab3341a0d4c2c4009ffd707c14ae76649f9912d4f979ce590d1d287f01b4b516e5b8	\\x3f387059526a40a9c4969c07d6aca286cb631dfffc2dfafdeb6d6eeed32e43e5c4d454bc79a644c200d866ed754709b1205a103acb930bbd51f350a5612b779ce4b5f9ad5f90e31d60285f0ba1d91c586141bc63a3fd161e948f5189f6ee3bdb99bea909bef32d5698ed7c8b6c431776573bc9d04c28be740e137fd990602e9c	\\xefca5e717b492674f9a5a3b63c683765f649c515563f33c9b82d9a994332ceb987ead971841daf8aa2b178f2514405070aa91010de3daca8de7ba31dd9c5280c	1610118509000000	0	11000000	1	371
24	\\xb3a136f4ee5ff50d2bfd8c28a9c604eb81b1277f0da4594b9d8f6839c3a4756effc2179001dbe7ecaff7c42382a602a95463215d8849ef28c523413a849b3405	\\x9c2eee65ec1369a6fb4ce03bc6f63797de1e270146feb2a737456b86096ff5dbe4edbf76bc83682b6bcb3a832a0349a478e55cc11ae594e4791bcf9f3b0087425c0edaad509a8a3f010e488e6b7e5060b3524fb927c8a681564adc3f177cbc3e4afb2095e4667f647e330416799ef33e72a7961b8e99defd701a0e5efb2adc6c	\\xb168bcadbb05f6ca1ecb057086de3a7f78246f47cb75ccca5e08f2fd870264cae43dd5e082bf9251bec713c6ebf41a394af2f57ac550caec92104a0408aa5d0d	1610118509000000	0	2000000	1	269
25	\\xe146ff2ec3e835f1dff2ca1f8ea1f1ca32093a663fe5950651dfe4aab1b60eb3ec3e9547c462959d599a3ad179acae1a3fa39fb136194aea04ba1d75a75d2243	\\x0cd9f50ff124396f504e8058631e176d9c7554e54b59da91fc3141acdbc832666c9bab64c78ffbfe4ea48e83f0faf43c34d7ac5614f425303595367e838205ba7288deff5f420e79a79ade07a3c5b740991acfca9ec85fae15ffb5563ed07c9805631f859315cae2f8cddc7d9c50a0cf41a3f38f40b51c7d8b30e86cd0a165b3	\\xb47aefd1523851224218d182e1f5086567a77212377e01c9120894910e6264dfa836a191b335e708cf15eef51bae1d0d030e7577ab1191e8f47977df82c38700	1610118509000000	0	2000000	1	269
26	\\xd2a310da2cd6a71f863ad62ac1da402b1d97fdfa8247095c3b5904e6e1d740300c4fb50fe816fef195e2d3a08465bd80d253777b36e6cf96d4cbdb7223ac147d	\\x3bcbdda9660c9f58867b18bbe2128a4b1c3e554f01ef03c0bfd89ad85aa0ad3bdc56c262ff8d281394cb3678d27944f0cc77ed5b8d87116ffa9e52be86263e9284d5a0fa177cfc0e5817e80c7e9b5fa07d4837d7884ab30ff2083607c84d8f78226f866f42928c212533c454c441678b28be4abf8365e38bf118648d5768664f	\\xc00be7aca9d872dcd4536575d32252be644589e4ce6ced5bf136fcd86613243c8c0ecc7ad22fd6ccc5408b7a251040919e680a52121d417d5e86a65d0b2b4408	1610118509000000	0	2000000	1	269
28	\\x0b34465bbe9d067cdf366edc0f21147cfc3d5ba2adcb90c69a88cebde3db482d05b6ce3b87b1f61176fd56a492ab8557528c8d35732c698cfcc845a9d853bd2f	\\x0847d28d127fbb15386eaeb82311b147ecd8434701d895795317a2e14fe69c04f0017ca356b27e93f027339dbae6a1555b3d708b89700892a152210b6a0a4e3f90d1b94f925ead7ae98e5cdb11d8e5b595db1c4256c34627fb67f9873e4b70fe3d60f46502c0470d1e3c649a32bb07a1324e9951b05ea6501dd037617d3cd751	\\x65da94ac86f01fb43b5205b037871ee074c3230b53d59a71e266f464bc4b9934f0baa6938a7301208bbc520461da6c0ad8ecc94dcdd1b6f5e147e1ee96541f0e	1610118509000000	0	2000000	1	269
27	\\x963ceae9a05bbe61219103d1e3f0977f48fc3b9f1a0688d90673eafe07d227dcc5494e748a77d9790e368a0baeb2c014bdc493e73742018c0cc90e432e256f52	\\x7f190651e416fb5d2ed08cb5ebcea8eec8fda8d78c98caacc6bf348b2a1e2eb0941280536d5067e3a5c6cee567e6683d047488911e63f7c298c92485ea9347571f2805a333267883415e90ef3b35d2d4011527ae0de6c85f7017146349bd43c7e96b21c13f3fb3ba2a3ba9a9f627597d6f3d6e1fbce04b9e684f4bff4dc2fa62	\\x8d593bdf3c7492c28844a0f11b56520c443f20ccb5b70e6f8b7119505b8282329478e254ecb3f4c8eac9e0025bcd568f229274c4db50b1d9c1e82309e1939508	1610118509000000	0	2000000	1	269
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\x351976987c14cf7f3c659d0298b0def4810ec0f675c620f97c38336621e5e68990f0e8837d13608f260b51a857bebbb00d2e0bd50eca5854b9bccec018f4e60e	t	1610118482000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x946dad00430709090ed308cffc8be5dcfdd3aec521d763141e992a98b2ffa98c5c5d0644ad9ff56f0f0cc5a6725a18f983a6ad0a71f46a12a7f4f54f2587ff05	1
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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 12, true);


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

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 9, true);


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
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_pub);


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
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (exchange_pub);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_pub_fkey FOREIGN KEY (auditor_pub) REFERENCES public.auditors(auditor_pub) ON DELETE CASCADE;


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
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


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
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


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
-- Name: signkey_revocations signkey_revocations_exchange_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_exchange_pub_fkey FOREIGN KEY (exchange_pub) REFERENCES public.exchange_sign_keys(exchange_pub) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

