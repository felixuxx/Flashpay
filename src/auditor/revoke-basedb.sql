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
    auditor_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
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
-- Name: COLUMN auditor_denom_sigs.denom_pub_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denom_pub_hash IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


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

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


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
-- Name: signkey_revocations signkey_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id SET DEFAULT nextval('public.signkey_revocations_signkey_revocations_serial_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2020-12-17 13:00:44.596215+01	grothoff	{}	{}
exchange-0002	2020-12-17 13:00:44.70488+01	grothoff	{}	{}
auditor-0001	2020-12-17 13:00:44.796959+01	grothoff	{}	{}
merchant-0001	2020-12-17 13:00:44.94082+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2020-12-17 13:00:52.731437+01	f	601c0f41-66c4-4f43-a5c1-eb5350287fa2	11	1
2	TESTKUDOS:8	EZZ1741EEBBMFSY02VHMY0HF8A842G4CWYXEYDM96RHMVKNCMMB0	2020-12-17 13:00:54.661228+01	f	e13379c6-4efc-432e-a021-78511690503a	2	11
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
56cfdb7f-4661-4916-a4be-311f6310fb48	TESTKUDOS:8	t	t	f	EZZ1741EEBBMFSY02VHMY0HF8A842G4CWYXEYDM96RHMVKNCMMB0	2	11
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_pub, denom_pub_hash, auditor_sig) FROM stdin;
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcbcd2f25fa0e9f8f38f1551e03e0db8596664726fa6bc4bf3cde3a3ef235218065828a69f0c22d22e7fc18b30929a7a401921765cd0e0bc10e856dcac1ed74b4	\\x34995a7b6191fe979d8943ecde783118e55888f4839cb6fe35a8a99eeb4c088d5f69e3df2ad5429e3d142272d187f923670a9babf4b1105042a841f534083809
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x59c3d3a5a196c61a451b2ec78981fb38bfc897cfce5cbad2dba774f63a8562560dda2781e648b7a00f002ac980da847f93591e661f929c652d1c0a76d0c4db1b	\\x026ee560e4f6e8efe46060838f649ce37186f2652f71194735356ce08e34852017e8c014b9a22631c37377414f91bf41fc2be3c6037d6381b396758746dca706
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x60e48638550c918dc90b5bad76269116e8f3a9c5c119a68b1c0f657bde6c0ac13161ba6f03f6d3827068ac5a1be9d7170046608f0ccc22412e20f7b4f16211dc	\\xc1ef572047ae3c9fd34f0fffef2fbd583ae3733c147b0cf8ccd01f4e4bd90671268fd28f5e00ce43a40a404d2d31d5e32b724aebd1c8f83085f69de63087130c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x47b88ed5ca3a0d36b00cff6fedcb92814fe3cb451b93e868aa4aa54b2eb063f369222bc62eef6d5ab9fba3150c7a128734df8a621e0c4bf578e5b748f1969bd0	\\x81dbd8e9949b4f4835048d172afcf126c8d873ca12286b312886c18424b04816ee506b54b6e0c42d246174649bf05f2584f0704350e4c9be8cb3d8e6282f9c0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x23917987085bb6988f89c444a945504e3d0270f3cb543374602707bf48c56a1aba2c7ed4ebe2bde6f367fe9907805aa48fe7be230fa84b23d160ebcc2006f6a3	\\x3a740c40262bf075f6b13a1fc71c5b03c0ec933e5bf8da768ffb70db165af1142a8231b62150445691774c54045f1764ed43647a041ddfd211b5ec0e87822f0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x481f58fb1ba6bab6a4e65a577244a15ed348314928a5d3f99c19b7d40e8fe92f219833ff05dfff2df2dc0c8b05eb1dd2e26189c04bd78623ade78a622f1ee6d4	\\xf03d2cb821628fbbe09c37dc64968c27e1092c526dc22b89738586c96fe9ca284363b3326d58693abcdfb1edcee76709b50bf3252a99e4939bde003e81c90301
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1766ebc6e47bba2db19fe0c0a13a42970d3667f137c5abb83df864da4be7dc880c02f488a729a039a2aa41e82cb5338adfdd539235b11866e89dc2a6cd557b54	\\xcb4a60340521f6252777b4f4f14842afbdee312d8060e64ffc5a048d36d69b6dbd20d91dfafdd12ce05379f76c395e4944a224af60c3673e01ccf4e890734605
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1eb664f1fdf25bc2b68c4df4f1e7c73c3cab31d1cc06eff9a3baa756aa6e27675ce51a72546d01d70b0a261230f40fdd0c1d67664651185ed8d22c1ff56f23a1	\\xf0b8032db1da63918d36d09b1027de2cac8f31a4750db906ee663693315e3f8b0411e3796c4f8c35343d4b71cb95b2523333d47378b9707cca0c715cd3c63b0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x883e95c2c31fa24edbeb82c2d518b06eb688a4c18f3550bc879ec00330a6df46e1d430d1b51140f549a953f119c171fae84c9518bf2fd4517d65613832c5c7d0	\\x26e8d7b9a64ac1b5daa28439743a90bea5d0c0501127c1202538176fde6e3647582c2e5dd8bc7bed600f674ca111d2bc7b41a4d8ccda0d07ca581eb60e9c540c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb3a59a00698df03952ffc9b8e248d3b33a8f79ab3ac0a361d88d0e8acbf812c4ed6a1d18d2a4f7d00f4960a3e178fe495342aef845dca208a817c0bbe7d50c60	\\x6c1b47d5930dbaa80ae134cd6e51f08b68e67f8548a42728b6cd43bfdbf151e9c6f6223df99309680957791ade999cf50380ee5ecf19d66b6519c2e9f3220d06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xaa6632167bf505b7739291c6386bdf1cda9f81d3a9cd1c37226bb43c8111f7b4ee786d84b22b179a319ee5b6274349fd2af73c95e330b43f3494723fb63aa4e4	\\x7ed7d3ec0b1a1ecb56d2bd696b62453a3374e6ba634d0bf22696b7987b1cf3b614851672b2a10d811736eadcbc5d13a162e3edea442764e88c78b205f07f6e00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x658ff42f84e243ce37a5743488b355566e6bf3adb935546b47f5bc8d0307b581f65df0a722454599d8ca8de36d0454a18e7b357599da30b1ef469e0e92ddc6fa	\\x2c55d24f53ad9c17cd54ed1a6875c09ed3e2896e1ae9deea3b5741481825a9465be99c14333c1b696f140e102a2b3e5195bf00f3b270275224cbb416432acf0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7a6d49a5ef14868facef306bf71cd7c2518096471cf3f735fefa1fc8eee0b91fcd320d277ee36c1237c122de0a96a8d4bd87098319a230cefaf632c7e78010b8	\\x46c641dd725cbe8714c25ce32d67518baa49bd6bf63890ac8b959351b1601b1845a9d622ff5f9526a1d75bd0eb7f0826410a427c71ef6cdba40560d7859a0e02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5ed48ba8f69920996bf934b734b194d7deaa770d9831dbab65d369cb19d9f9db1ec033af0aa4986898908df1332ebc73e0ab16c18419c241354f61a55aac4743	\\x134b6b45d8156d92e4f05a3b94b974ce9e622055dcc2052bff06bfb1ccb093867cee70d6d0a179eee8112c5d3002912c5e90a0702ec3e422b03451c2d82a0b03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x33e60e842aa6e718f612a4b97f75e4c57c6ea14f1e181c25157b6f9cab527c277706ad89cbfa1ec28f613efdd264a2b5f20c61798d732574eac2621fa89abe86	\\x27a3b5119597eeda7edeb2af53760df0107e4747509d036a5fa755baea11e495dc8ff1bbbb3ea66814fb2c40b347bd27a7f4ad4ad1740633740d4e8ae4446b08
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2e25fe3a43e698f12e7bc345a49fc11d1b4694f784b7e1d957f476f6a712d56c5b664c45533f2214fe210e6595a3f31b1c31cdbd723328c80e93b8a9b9c592bd	\\x0948ed372f3115291f3dc7d71451d2230e21e573c599c9e9882bde189e739e9b164a1bd288355a50270b86bc132bcfec1705722572060561b7379fac70b5aa0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd37e15b30eddd48348ee82c1b7f2f1153f14190618c1133b63af0524116d8034c162969ec6f5a868b957db5300cb4cf8ca95e70fddf25a771c5d9fa0833a945a	\\xba516b1d9cc1025c428075f1bad65c0e4bf72b3f7a95f8e945270794fd8348584945d208701775c428817269b0a875ea626dc19b098542c2ce3a1f9bffb75802
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbf02a3aa0365e6936030582ccc7273e8088364524bff1c2fddd92010427177191a403b4bfd6b53b9a8f30c1c14d717621fa396081cf903f475ecf125a48927f6	\\x8a4a28274ce8d9685a79104049d84164177155f1d26cb7bcac390e0543157875b130295da448cbf2fbb971eb207de8950ed119b50e1bf33d9b470bc2c6dc1404
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa4355d1aa8d73dd542ee749b83f55c2e66be102c40f554c6a186606790756c0f5780610e75f92892f137cffe2acc67288dc392691b850924af6ef3c3e5b2ce9e	\\x91de4d5c25b304745466f5d284d62c67b424073ad776bafe79302bc01c38abaee7741bfa37e948347c8c1bdfb1c1d1fecad60b2dbe5b657b87803c12eb227c00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6d77dc88d024d4bc7cd5c9d9268a837a4d7be830a87685ab2e90ad428cd8ee0d980ea88fe2f22a16f7d1558f44082cd3650bbf851b331ec84308571b673e9b41	\\x5a1baf45b72727cce253781d1c43ea1381746a5ea3a6043410021ab20c16074a6403a2071c5d6219ef041bede4c01a4385a5e4f1fae42fd7c33719593b34cf02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5cd5addb0e349617a933f82c16c97092bf32d5ff2e9090c7c454b8c3e6d6d449d22ccda44e0c4995b095f3b634d3f30da7ce40334d1ef7cae56418905d125e75	\\x7fa487c65cf55ec5db389479548cf7e26e51cf6884a89e230e086bcfbe7751364f5072163465cfbb7c0d800ba3428200bf7061a5bc0c8d4c035200dfb397320b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3930c07ba7c7bdf8606bf5de17d7ad57dad99ad88ddbe3a240157ac341841f395cc1bdc5bdaf1eb7b8da550c1585926afb4d93b934ea6132fca43a942d0f933a	\\x87528b7d08e7ce10c5d30572ab4b62cac0517debc07880d8124f9a411dc542cfbbbbad27c9abcd604405f06e2d431986cbcbc4b362379122a644340d265e440f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1527252f03cf1e36c58b875c14926fb98eeb520fa2b0ef917a663126005f6545ddfbb72f8cd04c61e517ffba983e75d490b52979a5ede907e2654d639e9b127d	\\x19bb19793aafb83b0101fe1e82febdafda899fd841920627c95a14efb67b30b260364e4d79009c269297803d9bc6b2852402a0042b5057a49c677ac20dcad601
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdf51456fc90d43dcfca6c83cc28b9d54f0309ed8cc706e8583b6c471bc3851a821adaa577c3538caae355c6af09ee132eeffb85b7f2f54be6f99867f5625c184	\\xd6f1a442e840ff9c3d9c0a6e3858cf5ebac6f803760a6b9cd6242695065ff55c51e080bc6e2775cf32bb662407d1e412e75679ff4b831fcecab401a2bc20650d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa5de955611011a4c2c0c1df838a8199093e8bdeb5b6792366a571d50a60545ae44561816b88e29b37c7debe59ea92db71acbdaffaecda9ab90cd59c910ca6120	\\x2f9749d4879afb27f1d7b8c7c9d9a98f8b5084a64d71062a5f1714575344c615ee561358ce769e8331f25da7bdf9b630482b014e71d704b156562414d0d33900
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7013cdc3e6729afe20748434814cdd79aef6df449a9852d942247362652e75241e3c829eb63085eafb7a53688f666aa296d6df4d3ecbeb0f38f49f623b54464e	\\xe079edff7ce11fedfadc562b7970c35e6483ec32269a96f6a44ca168d65ed3216a14080f47aec299be805ae2e6bda4f4b69abff36c979a729b4c8d11e3c7e805
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9ec6d9a23a536e2e9ac15a8c99e85fa9d64578ee946c2c28975d8cde1e62d54cd9dc651d5972e6978efc1c8a56ce398ab96b220ad2951e26f9bf3ae41bdda600	\\xb3dbd06f924d3790ad480de3666ece724b1c066f8df2ce8a03a228b97887484d1794a3aa99cfdff168830a8237227a5af68a760bcf2518ad197a7f391c89c80f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe1bcd187b66f9dc6553e127104f11714746482429a6401c89c740b1cb66babfb895adc418b7db3d6377a3fda4f8efdc25431881c6c7a3f674a07a3a46d5ddc76	\\xd4ac34e3e0ae1587991cd35a8e296d2924132de43020a936487ec3d0a1b83588669cc689d8394f453e6422b36f2da334f96a1e692388a721b73494ef36db900e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdb223749303636ffa3c3e473864f95fffc333a61b02d756fd773aad247a0ba8cac9fb4723c5c5486142a5b15d5e75607ff1d7cb86e2b16f501e39c8d9f344858	\\x27c709bb03ec3cb63e8f4c56ad4ad2ec7da97045cd5c1d2c5f7a6e360c628b364e72d9c68113604c7180ba5255c2502c84ddfc79f7c0113c26e97be0ef6d2c0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc82cf66e87f6898acd23c8f1d3575cb8359f8e338590dcacc10385ee81ce1e6e795c18904301a5b293a3dac187186d1155a841e1c5f8633395a7d07dc6e7330d	\\xb90f65a3ff247cd5d55ba40dd880722b877c866bc892b3079522e5d567a9c80e3ce611a4ee73f4c8f560c821724acaaf82da6fa3057470aa1f34c303b7805c05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8c95839440a41e6b950ce6e9a58e7b65fc4fa142f4d9910656adea105fdf24d95d1ea855aacac70cd9f55f125e061b192a1808dbb581234d965973d1343ff3f9	\\xa4d8faedec106ea0f51fee6aca9bc8e1848b0c1b97a28dca8daa2719ad95f165eeaf9784227557bcfddb26a3806e9b3096d646c7bb9c3d379dfc388bfd918408
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf8031e952467c5d63a33d5dca379efd889aa5f7885588b1315e118f5f12de98a2f6d5ca94bb47ffb7adb9aad553962657ddd28172469658e42b6dc8ebc090d67	\\x546f213a1e3411f9a1d7b59796b5a94d618af961cfbbda700b53fad86565b576c68fb07ba674cd11f2243badccc8fbd436fd7c7f6e591851b56c9f717418c00f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9acaf96031fdaeb0827ffd57502a349654bf597698f11bf348ce995c6ee5650db413f88fc6cd099b163b33136999b7d62c1abe144e0255caee3dd6dd857c0528	\\xcc98f4e3b1d86f739c1858eeae380c773bb249b25e10a6a70d6c4cb29ce82a6728334bfcf2e6dc1b1081878bda5bbec8408b3038edee44d6441c29fb14684107
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1b50d8dd93904b96c606626b08256c6462dbc7397a81d5fc4852415563041aa79e71ec04a16193f34b31174d054a3e9b30dc85df1c642afeef5cbca1ddcf5290	\\x2d49e8fb4baa688b5cf0d5d3c8121a42a979cbdde4fec5893a485d13827fc9161fc16d7e36a4b58549a51e944d734fc1f64b50a1ed44fb9e098dfc44a9c48f03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x26b1769c92b1819ec8c602fcf52c0150240d992661e22b18821a144c09651712a9ec4d0f32ccd4399428cf91ec308f4c24568b723a3330114e6719671fc8eb99	\\x8dde8742159b98ac712f87cc9909b293f92e72a13b1840f7bc332440917374b71c9f3a4312023063df0316c258f512b14b0f5a9f9763774b53a9273fa7e67e0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7cdf2f1019b1027ab8dd56b0688e5738bb6fe46272fe189b74032feb6b23452154d2c48f008994df7d9b606452129978110176b22773db4ecb7cb58e390ee265	\\x16e5cd16347ed4e332857bd38f56022861ba691a26e55066ee1c19ebb10a7abb16d25eb012199de03efabe36767be0b26711223fec5bf0df75992221114a6607
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf8d92e5bd33466bcacc0a6115c8fc933f634a6ece50dbabbac99382f49fa72e6f2e3f3baa2d478b82c7eb8d646b12f56671200fb857f3fc8b9cb98025abfab74	\\x0f5c93a5ca93092b59126aca24c1dc770ac1b0028ed1a50df1af7b5a3bdcd45cac885621b519a2f23d915f5a557daf2f39c7fda7d3e0cc0e0e07cb5b3be1e004
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xda850b0a30f4a75cc45b0f873d3b662d07cfc8e1aa2b61623097e3e88521e496f005f7d02ebe107e7f1f66e17fdaeb93d247046d107f5d62c9d50316fde338eb	\\xe43e0135e0006b56b83a0ce393d42ef9144f5e359a8a34ac56e47db082f60659fbfaf404fbfd33a655fe71b79cc90d484f65aab2760d768b1789aaf97d2d4707
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x13f181a7aadf933ac713952112b136a47746fdcae270b1a52292d915389fe15f29cd67482cef9fc016990668b6d2b3e769755a9d1396af2f91844659a9e9410e	\\xe8a7c35d235a1605604afac5adbe973b9bf43d8b64503f9967e70269f86127dbc95a6f6d3adbf175223afd54020ae2a93558dcb38213cff560812bdf1a52c90e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc53b4dcb42d3167336b59ac62af20c1bd038dd79da69d85c5ee7a649a46e0e04efe02523ce31e7bbc0dfe76ad1915e35e514a2e4cd6fcac9375c1ae73dad0bee	\\x2549917da4b81096919f2a27435f923baa7c5be34ac4e7d211514f2cfe09d0a2457f75e5df827238e7579da4288e4afd59795b29ee2242b79a246c51d48ce809
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcb22d65f487e66cbfa2bae0d072166166cc1c544b6bbd945cd0d19364656ba391f9cfc52fed292319ae242ea1b3c7b4fd8cd377ac36fa7c035cadb6b777511c5	\\x4ca712a0711aef3638e94046c9853c7dc85bcaf2fa307c1834191a0bf2940ca5d3ae59d2c913d79ca549e0ecba41fc247abd5a7bdd739072c20e6a6baba2ea0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb5f24da5136ef58ba0720f509ee4f71eae593ad0d11ba245eda31537715844fa194cceda68bdc9b6197ca93acc0c6e52c895a27ac92ee5dbb325e913caae3e86	\\xd27e7032e98a068e133fdae1fb99e8bdd078855f817409ca30633b39370ad2bb974eed5590331809b732a5ffdb4012cb0fc1c878a6289c887aea98a283f8bf07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7ee1ec44d39807102fd9d3aeb6c2aba83582188ba9d72e8a9c24af12b60c1ae3dbc50e679fb01d938cc3393c89729514839933384670c99a1c2a66b582991881	\\xd16ec8d604b2c1624e299b094fb6a7f18da728f8902e235d308636ca11c7d41bb17cef92232ccd76131a8df952a954028cb2d78845ba200ad2eb8b63ed421d02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x22cfa0a5c468e3ea95bc0aa1da08558e4c0e9ccee3d31eca34f4716428ea8612e0ea65bc971cfde8ffd05c50cc52386be5c5eb918ee6656699094d3396882496	\\x4be368f9bdaa523090c104b77d6d71651e7cdb1719910548c7e3b6f98f9e30e2f224f5845bba1a23448f3475e7c6224c9b3745442ee82e05375f11d179e4e108
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4e3755dafbc8659adb63f586424befab05df3b57eb3f0eb6374ba26c4a6aa6be85a3eaa56c2c19df636ec5027aa1ff0c08bbd5a3391de9a96314df35169d53c3	\\x0ea8d2630415a84c9b5659d0c3015c174738b4677d2b2b275040e9c9b47fa90fd90a0b6ef0f577ce47dd78a6aaeb78f191f332536de0530c96765361290d9c01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8a6f4c66ec57ccf7d267d02e524245133b62bd9c104026d34502c8a3073b9a798edcf23d8b5e09e408b5cd96e2c6ef9b13a7ca294e32b9a630d4bb33d62ae4ec	\\x2fb3d5a9c1673f7e39628cb385b8d9bf72fc0f27c0d95a269fa791c06547b04ab1d75755fc2d25d64ea34a3a53d1283f46f8189e0d2b1be47e02a5f6ad11ba0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x13d4edb8d1608eca0ae54e13fe059d601aefb5123a51f97394bbd0365f74894584f8359c936c8ed2a6a966531dcf29a737818366f33831293c9282c656a50830	\\x3772019a93107fe46bfd44e44094f3311834c3bbf1f20fd626de632213a12bbee65aa1857815a1ac8d94419278b1a4f58e45d68042a0e388bd8e36ed9633b306
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xaf52eeadf91ee8258a08aa57028af7e4f6584de23d3abd2d353d4a877b723453e7be2581b169a955d10215cbd90a08c4b48cdfdd24b348c2d789fc4d8b5ca46e	\\x7e1a0e8efbcf55657208cc4e2df28486c2fb2cf3b2aa60c7e08c6153d3b4c5c447a0fd2e9c2def98c2bb2d8b1c33ef721305dcef60360629f2b7848203efec0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x077619358f647cb90b492f25cc6d1fe4c1d9d7ee2b840c697e09e1507e52e93eac33f0ee871d039934a4a55f3ec37ca711840aea8d7e0dab9c7fd82ac35b6433	\\x3d4f3cd15fec1cccf60fa26bdf2520b72df397226add95fa09b4d907f3096c287595110bbf402724183f21c7da932539e8e9c1a510a01b5d988d1a56624dcc0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x484014b2040e3ce83269f323e73d8091ca39ad710d77cc5bb5062918266fb55536f49b68c5197241f1be0d74d49b37598187aa7228976e08af2d046676b538ec	\\x8ab2b74a415e1d26321ed747c388ae294a25ea47176cb6e655570fea652846b88bcaa3352c33d68c62568902cd8d38320b0afd9dd517ef892c06a09b66ea4f09
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe0119e140f2d16991c360488723a8eed5cb7617b10c9ed4a72ca6c741707e7c3ab6215d70ef9e37bd388c7d806950a887482dd3d20dbad36f8a3855b484e9545	\\x13c746a9be35d4d05843033098d883ea21ec5b1438fd6b1c931f3c856028b478617f8bc5a6d8f3dfc0b516f59adf84f4d2d93507198961960554135dcc9de401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x721be291b3db26d7daff9d89fd43d99b8e8f52311493d35d66e25149918563e1cad393b334328b250faeba9368b93d6d9a86ddbefa4379419fbecdeffacb97c5	\\x63221823f19c40f4b01b8fa805971b0aa7eca43954250551e89488ca4d6646433e59fc583052ab6e401f14536fc9eb38b489129d86c834e98ba24e2691c8bf08
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcb401df21154c7bfd9a8c2321d056a81b1a38a61159424b69afbbc78fbe2f4d8b37fb04e6e5ebf7fb6b27b78dcc5cf7f4f48e5fcb8c5262fccab0957ee7482e8	\\xfc479dfd9cdf32fffcbf15a529b6e3a1167b01ad31e37465c79cc93c26f3ce45cff9772b612c94b22502dc576bec6139f896da56a82c8f69723ee3b09b883106
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf40a95b141265bb18d21e5cb7146eb187038cda34d00d5e7cdc6462a4ad6534bd3bd09aaaf303076600e9932f9885c4593b2068529289a3d183e10d9dea58c69	\\x8e5c290be276514169626ab58ee2fcdb0b31ca98cb78692a55fbf1755f1e5ce85bd81de0cc6363b745c37721f5a827bb76f969220a63f224dbdeca72240c8006
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5af7bd0273ff0fc4e25b3653407c952a187f9f4ee7458c52ddcfb0762c4ae173b59b883047b62e4d875243709d91fd8f0e0868171e5b895f15272d8b52582394	\\x415f5f46063285cc75e60c27f3d03634c531b206e729cd8243f0f1fe7e73cf57e532caa32f12d7bca31b43552fcaa0bca8c015416ceb5eee42f57115451afa0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbf7bfc4645a8b1ac9ed1b298ee9b3fff3bd39a73d515ff25333d08862f4638819b404cac02f0ef933756df094d2c43f6b7c9d8b072183a677e322b38fb25d6dc	\\x166878ff6288a989c06aa71f5eb2ddfcf4ded4527aa1add439934f5ca9e354b4283699801163bddf02c9a94dfc77374b5bd4dead717a21a644235a858b15f001
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x62040a7efdb071dd4fd42da76b9d39cd85e3d2e3e0e0aa2ddd41ca8ec0f098dcb16ad49a1185f186d10301dd405f4123ca7a65b9ac2d3432ea722f266c632719	\\xea7a480a318ff5572397302d3da3d5d8a9950f05813b9e3ce6c23af5f2a45a5d0cfb9c33e9d1a75c7992d1222b5b6db5d7218132dc898f5791dfc9f9fac2db0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc452236fe5acd1a751ee1f9eaafd53ea31d67f0a60369ca83f8206c5456a66241d8022472f1e1e9c5222a9b00a86887c7f01a62c7eaada34603a3a99d1b980c6	\\x8997e830a6529c8ce653a018a9ddb06978720c0c7054ddb9b73d44ebab9f621f10209783cdc0c4b09f971ebf57b3c41b05bc6af996c48149a549b15b5c848900
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4dfefadd6e227d9dbc6c5d3b0f3b86514519136944f3afd409d031c4193adffcf454e0a64c90c3f277f35d068d7370dcf69104052da77d36cb364c5104b1bc0f	\\x8637a350abf171dcfe1fbf07f86e33de1a2d889d08a7f74411352edc859e23e0fd3d895926a8a642543c264cc9eaef11cda4b742501b7b2d0f32788e4328ba01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1ff2cbab58d2619bd38863c47686c2334f10270a34bcc3268c8d7e76bda77bae7ed113c98fe2ada2c0f019f36e804eb43a701f1d2041afa7cb967e582c766604	\\xea8f44ecf4a2a2e8b10ff511691908de968ef51ad7cf6c5a8567fd6b33799d19cae8a0ab646a36165d9439cf8432cb2a75f88683e5c91f24d666f84297b39906
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x74879bac592cd4f061bc7d9932dcced70a8de034d50da4a29723d360f8b14580ca8e0f8eb7c5d6f64b9b7e99ef8016665b76c8bbb1c246d0e9bdde2e0767c11d	\\x92715ad2eb405b3c2b20d84eee01b24409646aff36ff5224ae09edd953fd65a2e099759c9f95f3b51a91c1b4666c193341f4047c376f8ce28cdaa9eba49f3d0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2f190d03270f9fc79e24a8589303785e9591c90f22af2e46574493ff53343ce66289fe407e8527128ad4a1f2a5854175f8d2ad4a25f256d69c35c289c154d90c	\\x4bfb3edd4c9972a4124326749abe82575d6ae648adc7f11624b33c69e14ce8007a5795a45b052bc213ba5e063a6bbb43c61e6c7f66d5a4a39ec6ec8a1f6c9d07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbe57d00bdc1a43ef9b0dbf4312f700de64cd9563958b9e8284943a9339e3856233d8e2ecebb32e6cf0662175fdb9c73849fe8e7b3f3cbbb626d00ec717c13382	\\x7e5a8a213a3b51fc4a181b2ef2f67fec7990af57f94abcafe3290cb9749afbdef0994411ea51090b589c36424304a2545119cab8e3c1148f1a6221a2c0ffdb0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9d6edff68dd6d8e94ebd1079248e1914017499a4b7257b88f682c11635bc9337f57b5fe14c8aa3e8431150bd637f7ac433f78bbdc8c33eb3d2c9f5de0c667cbd	\\x0310adde8288e5949f7ee543ccd739b0bb3083d404a8ae1b659f92a1e2a444a69334ee9894ba950ab4b2cd30749f9d3723c58105106b5a89dbf661dfa4787c0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x730990a590c27d687d6ee069a82f964b7e454ce631388c838a78e48775983a58bcf3bcee8ede77e3065bb0e14be5b85d2854895a6af42298876c972482ae39cf	\\x2459298a7376f8be0c3b95d9b3684b6edb0c186e4b40b8fb5944c6d583ad1c21b9bea346a7e4cf0216417ea50c1e96e6305efa48cfbc4f42c572683dc323370a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x50705ee050c2e0f6db44f8d2838797aeaca55e152bdadfb91e42e2b47f4ddd51c88166f04e6b307470e3ae077cca75011ff6cc698d63e95d7f08b79ef0b5adce	\\x88f604144eefbd461309b246322a1d19c769bc4b76e38e554722c47e49401058f65bfc995ea03ff00486e543b08002bdeb1ac682feaccc7c2d4dd201a9976d02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe0512590ddd32becf4326e4c7c13b291ca9edc428125ef9af101fb5f4b2c40136d2acb453621600d0ebe75f5029ae9fd7fce46f47ae512dbee4e5eedbb902102	\\xb350efa41ca2f47c859a0c293c712edd15f8929a859d04acd1dea18ecb990c6cabe87ade66e887c896a2b3beeb839537739eacb3f66795032e20217586aaf901
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbafb81d5d93e7e7118f3fa56d705e29e623fadb7c5f7644caf5c07f6663fd39989949c912e2f3398659e6341dd15ffcc43c06ef17094d1ae6c78a7a43d63c31b	\\xfacb42134ef168e3ac60bfd3626340fde31790e3d2f36aa11aacf28837fed481e3adf86f1e4aa538f30ea2d04fad31e03984f53fff4b174b9e7f7e4837757402
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x38977d3eaa150a2cffcdd8e0693dad8e67b4f7ec329889eafd469f411195b1639308b3bc044b65cb88ceee6ddd8986f85be5cf4f86acd832686107780ca9adf2	\\x6fcc42bc54ceec02547249e13842d75581f8b19591800df3ee1ace2ceff361d81b2b60dcf139560f57fad787ae57a83f9efaf5643387ef86886add7b424dc40b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1010db5b7d0f0524bd7abab50c367b24b31dbcb89326e7c6745f0ce3804827085d61504300da967ddba7b3e4949732a9483907630e1c5e91abda7d6b25705e7e	\\x3f8ce5fd10f37c2f501d01bfb81a80c577ccc1d6300e7e8ba4489e1dbe27b31ad7dc31218e2f691d5904a5467f5d60546920bd4852015ec404af72887de0470e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x49713aa79b0ab4c32508029ac8580aecba159b42cb2cef2dab3fcea8b4b9c343dd1261bd7eaf84b99942194cd14360d6a5844cad772a996b902e71ab712257b3	\\x9004cd4f05272c3d8dbf36763d94b80d42c8b0accb8e344f9bb42eaf8921613abed86f2c008ea4c1ed440336112f4f01de205fac06eed84d76c996d37ffe9006
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xab06bc50fde41f31d2febabfefdcdadc6c7d526d85b13b29a47fb9b444dc56efb2e87b16c00679015ddabcd2d7c24d09bcfbd02da28844d11847f51cf9d1b271	\\xa39d3c7422ce8377f9cd75fdf91a35e69933d1524c7370f4f269882a62ce93b28ecd585fbdb5a2bc5950d9f796ff57349c8aae69050e133ac76b914cd26e6904
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x068dbac4a2eba9418097e41c8673fc88e0fe74ca8453ce753b2bdc451c9d9dbdfc562cb1ae200c9219919d868739b1064232025f8d1df4246fee876c5d0a64cc	\\x659c8ec9f8850ba6b87654ee322feea77be918064efd58cb086ae3ec28b22b728310dd9e064e405718f4af749ed6da90491bff034be6bafbdafd35f270cd6308
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0284ff37856bfea493f240b0ba4627d3836651ff8ca89091a31feb086af2953cbfc849946dc1cce60a75a78aa0ec5ffcc8054fc8b131b33ca786ef9d9163676e	\\xb335aeef500791a50bbd83e208f9cc40058f157cba9e99d8e699c8477b9ca371d523e0ac2155e25d38a66535ea77668881a0c9861ae9aa2981a31a733916e001
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0d9139a6ad225672dd58569aeeda377cad2aeb9b982be3cff9023de6827880036e8dfd283d0c3f0a10ba3d3800fe54458eb9870bbd5be4a12e9d84c0b7e509a2	\\xe72c4778f931ab2a818288129db4c87ec44dec27e4e1e01ab618d12659f07ac5d610850a583710adf0176e89107de3be45649bd79f9c220029b6deb8c092610c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0475d1f693e907b0e95a2d0756e11678bc6946fa7e32625686b0cffba276358b55707e52a052ac85dc3fb65f407584318d1366ae4973738b56edf3720f4444bc	\\xbc6611c18000edb15ce8c66df3700f2cc7c4a9e1b93e3edbc981f1e50351e05c9eedb0977e05b96485705ec02b3cdeb59d9f72017ec84ad7976b44012d45a802
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfd00b71b37a1d469f11adb0b109ef62f57f48dfba5341821f08036f66f8501e4db0bb7bb05c1ab9a6f2ebc21f743c70e9d3642a76144f10364ae9bd3bcf319c7	\\x96dcaa874c5494d2ac41d979d8ab4c8f2b7324e2c168eb60863b130d828a0aa762f86ee7772b6d22a292c023dac725fc76640438a39a517d28b984831ce0170b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcdde0f3a8349b8be9575a85c9ed39a9f331c91e9d707f6850ea514d0c3bc3097ca955a1a90e0a334c11fd6c37e3e4a38492802d3021354c7bb00046e14e0875c	\\xc73b209aea342158241d431066ab77fd17eecb41909ee083b220a8dd64b227bdc8eb82f41815b918ae33157fbe066c9c01ed7d2801dc7a8e12c587344c513d00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x50c9ee567a9f7d9c1d89b9f5c9094a3c1e53fbc611cb6af2f7f7f4bb2ec8b4b8161a8d21dc5fe9ee1246fe658e521c58305a08743c6bea4361bec4d659ff5b25	\\xa6103fcba122e04f82dca300aa2cddc3e1bd132daf053930d93a807007bb5ebcf8fedd527dff4ffaf11945c9add7c19db610f356102533e9df6414c321a05008
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc5f0e48b863e5e6f14c08f0f531d2e39780a0d0f332a1b6fd1efc1167325d7c903e7b609073b4112307a7cbf0063bf181b8497dcf1fa80e7ffab0e39286d425d	\\x557d5ec0964e782decbb20315f7bb507ff3f3544442b0abfcf6848f457ee70e24e4472f44186ed3964096e0541d5d85bdcdb5eba79bfad358146844a90c6e803
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa792188bdc6a71aa629844920770760df421d6d9eaa4973c1b11473754a398225c1794f265eae25e4c5195598a9bdc381b043d35030e453e7298b56cbdf90202	\\x87af04120c28a6fc31d0ae8b7a460e8c155e31d4731e15a5dcd5a1c4cfad09d8a4fda3b471dd8e37da038be1d6c1638aa35e4240e17977634e1cb145dd646e07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x54fb2716fba2fcec9ccd2d8a7a7ed5f5d2486e2dab55df9a289363eeb6a66220222ce20d0af5bf252e207e40f1f5a0c2624e7390d2a7806d648ae6daec7ddabc	\\xd4336caeaff4b56d5ec9d134929fed07bb731ccac53541cdbba500244674443be745ea5d351484653e716096286e80f9ad855ad81bf48e92c996b8ca5afb8f0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9861d511a57016ae752570944083ccd8b6dbe9e1444fea545008172eb7d5903bd1c3ab9e481a502217e215f884aa4885569bea51bfd0a8874b9a2428cebf3261	\\x6c8b067c42c9d8da2faf856625cddcc05cab56a28d4b9b5b1eeed93fce2f54d5bd39698f382e219d08cd489612c2aa1177c6529d2da5fd322d9a4d42c112120d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x66c89280b4fe4b91d9df92a5dd329f3201e6387c1c4697e4d67a3a9e40de47db29978b7361218994ee35d337c525cb703813d70dd821316803d19f911e33fed0	\\x847a1050391bff9271d4723a5dc62e6222f2f165f8b6ec9cff6c723f401366fd6d9149ee9bb1cc3766212e0695843e6d1a663e2f68ad15075da72eedc6b3d60b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6fa0ce4a33ee961bf8a2b2f28ab2db3bea3744975b32dfa89604b875ccea06ac87d0bde248f4ab822fadabea43b15018cd2959c403ace9bde66de0b37701ace1	\\xc473c274338b8b18c988ca8bee2d1704024a443bc03793e7c210494e650e7b46df02313cb04c44548f16d6bf44bd89ffa5b56eacdfafa3d5556ca5449e362e06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x44b5478409c17fc84213d536726a574c4f523b4ce07cc029e4f5ed3634c56d81d8c5a5f2c3638382d9cf5ce6fb27a986ddabe7d6ce8b2f8a8a15e2400e188ce9	\\x9ccd91b98b62dedf2ff859f171ee593d3cbf97c536d585f8190ebec7a2c824f67bbb6be9472cb23b3ea9ad2d667f8b058e0312e49752d74522765d0ff8e37a06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbffe141236afae3ba7ffb6acd8be591ca254ce843e6f6197b76b4c982255a0c671dc463bae38d53c52b21aa69cf263891885482f9071f7be36488a5a201e2e4c	\\xb7a0af02a25286567024bad16d6fa86f7e2dd0baa0f9f5cb18953ee73f0cf14abd799c0b160f5441cc66cab485a6cb17d0cfeb5f1fb27cba90dc44c9226a6b01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x592ee87cdbda4da4a700cf15d6dfd7f975492bc859e50fde7615b0dc3e3936f58121543d838f9af13f8bae86295b46724530c0d22f14c1d5e77a54a5b65efb94	\\x0984886d8ba578e1ffa1476b54bf7c9fdf2fde630a35c2ed2a949f2ce1e7175a8e64b7031c0681c1c983e2f140a3464f1ef8007df5055690435f64fc295f4f08
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xed4c0ad629eb14a3999d2ba9a6bce505bcad2a2248f3b74a04f5219337d7a59cee7e6079c09e0c5272362f02ff7f6b78a68dd2ba09d3d6e22f573fa4b2e4ea4f	\\xd93f83b2fcf414997f02cf3871b81f84b304996240d6ca60714c8039a2b019195cb9f84f7268d33de666d96a8a00bbd156f3c087ae4b00b1dce9d061ee403107
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2f807f4ec6409ef51991629896116247097ac72f3eedefc813bca40a5b983e59568e2e69965538098b21b2f3bb7f324ab372a426bd456b5f524ca721c875d72f	\\xba2f45968d17a53a40d1163b2639dd69bc9ae7c4013b7cb9f327e3326eb5564eed266847f1c53c8ad83028a682ad90fef012d27e80ca15df229c81eb7cc2c005
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa2c0fabb3388c68449c2795d22d79a08850b50f80e41bef09cc98bec51a69c79670c877cfb877674ed6b4bf18af03510017dd87f14f23ba7cd4fd48ed7b2dc46	\\xf21e25756ae172ca4cab543f938b777f704cd6eea27f44c2143d6a87f4b24e36cd46b508e70bef52278d59943da21afe27398da4a8263389d70c8833118d6503
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdb39d6bb4cea80ecce7345ca23ea65d1725a441b44ddd41bcd5769ea9a89cf53824d6d38bc3e61563fd8aca9228369048237c6356ca43d329abd85e48df08003	\\xe0fcfb16620ff6eb14b5841eca4e9bf12d57baf826b00dd7e7c9c18030d70c22a867d0aa7e53e92793a77529f30f9ca75fc15d2defd1533d517cd2d2dc6e4309
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x24a14f9ec9d1e6eb6097c0f5da7e6eb482db598a4fb2e4eca93f803c257e4c5ff5e9436a25e896aae84036e65b373cd3e60171408982a09eb2783e64aefd39c4	\\x4d232827b4ebe3446b3c0aca591956c9e19de9339b6eeac86ad4714d2d7f6736fdb3dbea59cb5f22d6cbc86813103c5c059f582d6d4f96d78c27328338bb5704
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0e090f69f3a282cb6c93eee020e761e1f84403d0184c76a29828ed5160ffaaf1b93b04b350e86dceec3cb598630272c87c62fdafdce6a8afb6ee487a22828dc4	\\x17c4ea0758126a0650c766085e224c916c1fa660d32f95eb5e980803f02f7b747b99dd2d7334b22935b98186fee22dea22df4ae3609bd49d7bfce92836ef4501
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf4786f4cdbfaf587363b3e3b6af73f79186d59626b7fc474d32fca95042af02b15a13534441a0308032087488a52d1b620c55e0c05bea3398b24cad0b4c8eb17	\\xb0b16334e47e9b62dc19c9697f85b643a142edf41db8fa80b2e288ae6d4f96342a5b4c072fcffdcb12ca44580a5f7785cc67ee2fb1c2eaa27975a0760f2bca00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa6d46472f9142b07f94aac9d50a7d93b09c0de41513851c63258dd33a4a4b949ee3d420d47a55588b23660285275ea833beaecf344a504bf9ac9e26b6a2ec013	\\x1e00cd76c62e2febcfa090f71b55705f75b8e151ba91d6d98aeca22b506b7c504d05de3b192ed5377063b0d4f5a70af03946d2a5d29d76d10ef3c99e53fcbb0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1225310195cc771bb7649ec35bb7d509542b8a510dea0bf73aa8aa0bd7ea28b25d345b309659c5a564bdc3a4a0d33879c2f506da56aa0c820cef881491443b25	\\x76ba9d89e934ac0d81204e9e918e858a2ebb0117e066aac30c72948e44f54676601dfaaacd0e5b24bbb56505248e80db15ce2aef0188354dbdb05cebf3a5f705
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfaeccd194d01a61a4da5e19ca05aff2322613a4ad700abadc06ec67da604667b9c9894b7fcda4aa7e656d43bbceac9bf6cdb6dde72705b98350513bed2ef4c36	\\x8a5bbbf4fd08cff73fbb569f0ff9bd6886303aade0e3652839baab50931fbc4da61586a2c9ae5dd9d650651200cbb0449a3a8f90954e213bc0c7e2a49c0e970e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc5d618c5d051fc36884cbe3de1759741d2a9f57fd4d8156753eba8e693f608b392d48676e748e1300c369777c4ad47349930c3ae4ae9fb37af7f6158a9efb9e5	\\x552f42596421e0b7fa7521e49d3ede993a35316cc5040a2ae02cc8384163fd7b9c4aed2f9fe0ddb2fbae5c681f2bc028167e828d093adabad12069ba99f8a50e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2d310461802eafa95918e210052a48555d47c9a0bc01ddeb35d1c216c3a6acb8793d61d58419af10aee08e7d3a92ddfdb259853a66570f7123937766abe7b2ad	\\x695b86f3f77ff8cb1aec3409ada0e5f4a9ee843c9bd0c6f82299813c44e0ac4ed6baae967267a3a9fe1ae84236d5b6ebf996692a544cdf6fc6adafe1be94c903
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1adf9008cb2bd088ace501e8874905827c28c8f51beb8afd5cdfafae166593cb9b16c1b4f1ebca5139ee61a4be71af585c0d31a0e9263d237c07b338b25fdfec	\\x2c982e7d708c6184b25323bbbfa3d7aa5d878bf22d8ab6fb702d61f5a22ea8ee7c96ed98d5b27f9be8f0c4c7be546ebb8afc00237f5e7f0aac638fff40f9ff03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9718909b21b51a2f74afc076816bf21309e576f2e26dbccdf8150112fd45aba1a8547e1591664f597acb85a6b3bbf2a146010e3065e2e9068ddbbac45eca261e	\\x0b4e1cb39e10cbb4d951770dfb449356168758cdb44ad837289474fbbf9d9208d4cb31c476598de68ad1572ded0827aac3563fc6c51aa0e5d5364c1a9e9bd60d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc05bd55b58a75988e67b593da1fd7116c39c3d6ad3c56f862739bb4ecb5f2d61e363aeac8dee80ff9e5a124d4206ad9970454a9cfe32a9815e5f3696728a3ec7	\\x564150a0481b7bae922872b1dac6c630bf1317e8263823ee7784d501b80c68b9ffbd03f7f83f4cf9b743b6c03a7e7be6ec4d924f4678718e9c95f331a2ccc906
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xba7148a00853c9f6a803ce09fb1a709e0045be0091c689cd9404b6d0b6f82106b840a78d15715b6616397b42f15eb0eddc0e0f5f60c9cad0231b6a2fe1453489	\\xa36829114a98e1daca2b6405e23ebe6c3b914d7fe4c3b46254e0c54ee84fffc1a89b8f3ccb61f5865c1eb1df0db7b05c6413e0a176dcd13a0be524144fb38101
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc835ec7701e4194f689d9ade59c005c6d219286c86097b6a08be6fde035bb19c6ad5af8e2fdfe5cc1a37697302d8fac925b2ae483fca002ca4e9331cce5125cf	\\x23320cf2c7b8c41235cc9fabec73e8844f5039952538ca6acdc59501149788742560ccc420ebe4caf86c1cab0fd9edb4d88fb0cafb2950c3f3275f1f9d5af607
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbc2cd0bfcbb47aca35244760c100ebe4e8c3ac2030fd7f6a3dca41c26ece0ead918212823541e010e4bb234ad4a6ed4e8b8c4eb211304767551de07e4e78c443	\\xcf1545e1052980810dcd7b54507488ff647f61acec71d572d787897242c98b91415e0073640c5b0023f2778357335e21ddcabdb03bd932b1037cf23127f73002
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb5c86926f68c2fb58d1690428b471c84346a89973bf57371cd4fb99c698919575f4cb0d1aa1a31abe5c13ba329c8256b0a3aefbfe78e1aeafd6a30bd2a5d7ce4	\\x024d86d77142b03303102d87166740a4cf65b5af81cc0e8a807901d468355b7adf1b02bb5ba6c5a474b298bab2e4640c035052584b13357b393a59c8de40dc03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x88c32eb2e0eef8666561e3e1aaede03159102c4b74c8eb2927c11bf855dc3f8b38614f57b7d87a085de73a74028d518e6cb7d5cb2ac25a7d463913cbb1cd0044	\\xe39c1713c7415549d686622471b397e319180a454d0a0915253f9d23ce7e5e36ab88e7a8c8252fdb2e34b43d4a247d6ec9707c6033a6c224e8568b5cf678b804
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2a26be06813bb284d9915f06daaf12da5c8c8637c48f769e944b29f9b9d316b36172bfd0a30282ec4d8d7a24ad7c731046461035ed63ef719c6c7359f4dcffe8	\\xcfe911b275517bdff304b939d5848eb784fcb1ee200635b98d478343b484fd647aafc48fb7e11278307eac9552665c879a79d9756a7c66ed7b480a2def60370f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9368a0559bfdc38a09299ac7ac22a948c3709cfd9d9f5b7123c09b2c34350fb387063d3dadfd8ac3ea61ccf8084b8c23eda2be6ec5371fa61566f649ace9a8a8	\\x1e09a01e653ec0cd5370762ef875c381541417f5b0a638c07005be8b9b4e42bfc475f28e58a40005fe6fbe652cafd3df4b641e658ec6ac3968649df126a78401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc27f9125440270212fa6461d7978c5c9ee4afcd3fb378661bd70b7c85e98b6e062ab2d5bb02b54862b5800785cd5ba84c130ad050b08dc3a4ee871df3ebe2e14	\\x12a1b06b04c65ce97035a32fd39f90e3a84d9cf86286383f4f780217386212d102becf45df1651e46ba18a68ca1cc89e5a1f0770ff860df86f2884e966f90a04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x330a0b557505a7f7e0da8fdbc1544130ac322854a2481b7bee8d49030c1cddd5b3d81fd824b398cab4f3349f6f7a2bdbf476d227c69112d7947a834e45a3ba28	\\x2fe1c1def3a1a41288b68460294cf9388132a9e8f9ffc56bafa8e750b65506467b5de3ad4aa43a171bb3bc1cc867a64c36b2c99c095daac9736ec55641086e00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeed40115df46f0a39dd4c99027e3a57110cd775644f07373e8a46d9545ecd2ec5dab8690d80b20add557371a8e70f96b406373a7e5cc9aba27ad0adc4cfc83da	\\x9eabf5549ab955de19507b2345f849f48ec77b3d970cfd56315aa90098f4b261d64811c77590f30fd0fd98e5a7c5e709fdcb07291e2bc584a365943a8869c90b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8364f7d60a8dbb01cdb20bc8e8e63eac49693ce92439eebd9496ff786dfc5d3566ed63b946648d8d1bbb1d94c89cfee81ef7a36cf09546ff5d74d19a8fa3e0a5	\\x0f1815de234dd187c6e2127231f5d0e90b1a646e47ad0196fa9a6a97ed894aa65b65bc9df79e5257be0dc68e50f50c4b27c6d9195bf20f2a23a361da4d99200c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x082820ef5b440d85baf9e52248e0aa6fdcc3d21140bc726310957aa05b6a0402e78f43154c24780bfaf08900d03b1389a245b2114305a302648549293128ea8b	\\xeff9d6daba43ecafb5f71dbe956cf849b7432b6a2e1608189eb857f2048ec9445c94381b0a3836de35ba8d418cedc948b3db8d30fe8cd86100e27fc06657440c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe778c70906746807b73998f3fbefda3605ad8204d88d0acfa0e157f515479ac84b13620238dbae8a4d5225b7ef7eedde44b35c4a73df2a3fd056ea90458e13d9	\\xd5434de04222157d2221f123577bf16d1c75adf41648df2bde7f51088d455592b38143a659bf75fec2cb93794ed603511902d1c285969f8d8385102d386bb806
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4874bc54f511ae443c0256e007b5862e19f8847b7c6ebd041518c6733cffa05efddfb37fdba9fa937c25eb5b74903be76b55be4543f249b86d3725c4de9c2040	\\xfdd1e1329c1dcbf5fa6b4068717fe4313d8c8a2878767927a47a44af2ba44e3e4cc552dbf6a5b476f8c802328b193e767a51dd75344bb0394d8949d83ee15700
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf31d83b233f85f4250ad862959ad26cf7a8b044a0a441763fe2610b1f29900e50dc019f73afab6fdb9a1a73bcc4ea122102f0f2d8e32e752838fdfd5938bb761	\\x1070bedaf3f014682bab598c7ea8a6dff815ea87aa5fd3de2ac1fa30a800770afa40b57ea159bdd1a85a3b118a40ccb2d8a5ce64fc21dc66b423ec93392dcd0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6c84480890d89385197bdd88608683c04b2c4d343bd58566da86f64e799386eb087bfc84975a35f74e2e29ccc80f2e41aed6199b9bd1e9128308e06ec2c69ff0	\\x9bec8c5744a1551e07930d5b83545eda5a089085d121adabbbbe41b2a8df41e3d48f101d41c43fea346cf8fb90b9b4420b92ca9607c4ca3bde02fe226d619e05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x70deee7ad5219848b726546edfeb323f41cc83dbc12512eb3da1a0e0ca14c1211ee1a3e46f89a287bb28d6b34375d08a2a269001db2ae2d9bed25c90b92e60ac	\\x9dc437b421f94600ba69661c835675e2bad9003d33d5405f88c295d2ce57bdd16ca90ba19a3135bb800395186cdbc788ce7ab0acec2adaeaabddbe5cf1a2160d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x08bdcf31646a9af749a435d3023df022bfebcf1f49f73280cc19900024c517d4bcd177c608dd8c89cd0b77ae89142e4ff346a0aad8a89e325fa7dfb614e2b4ba	\\x54b24ef97420e1c7771ed132c1c0ef8d8163b195dab782b12663d19990bd83406a16cbe41644cce997a660a088245d2499038113222c929f6cd67919c306630f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb0a4433d2fcf996c3dfcdb32e6ca2a7c4df1018e57246177ce77b2ab8b4ac020640e9abf1baf4e14b829dc15fda54df5c1e6ae92298efb27c6f73b94929dbd43	\\x1d0f707a36c3d56cab5e5ea0a7b632658ae64b4388cdf49c287e7be21123bf23b99a161aecee2902159352e4d2776fb5ed17c4c9e9dda6d1df6f686b549b5001
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeff0df37a70acdbcdb915fa6a7174a9e795c2c83617ba323df9e3f3f3947dfac9a191027b516c03505b3d55c8f99b22b61851b067cd390fd99ffed80e5b8126b	\\x979ae73a77253f23bfd17b99059e1a3fec342266634b76dd0b87053199b818c87c1d3b1602201cb64ee9c522985a3f037de1836093b34dba73ede52464fd6f06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4400738094998c9ffe5bc1fe1f6e241452b8449cabbee2b83d148bd653ee840a576428a15c227b0ec0b46e28c4e6c7228513e7571d5f02ff86adda42f1032a36	\\x29df1a5ecccefad024e31e62bbd51a115635f82cf1ded67c121a118189015df29213b56e3776418866345f0a93fd189a6fd4d435486dc05e29104eac642d0f07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x30fa8718a9f69766e173f739ba2a8f77a12b60690d7bde1e8b8ef05757c697ed3cd332d917baa4e0e08239479c75a9f408d94b9ec5bd9accc9fc76be3c9fd19b	\\xa70f883625527deb2c62894de7742b454c451c0d6a81ed2412dc1f3aacd8fe5052a8a63750466a2b141cffda2c5dfc6bb9991ffe505d26d6dd68976eece7680c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfd892f72e80305e4ba6d168395e8cb1affecaef2cdc7d9a8ba64229e674e8538a2bfee09ef1dd18a8ee1b7de0f1711d2f830cb486396e0eac5a7935feb73ec6a	\\xf8c396ab8243605400e562d6a786553d5b6e2b561d98105163a667f7fcfaca7d0b0e77081ee0408925b118f6e93091fe354ca9d237f19fa88d000a7453d7b50f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfa64c38711c83dc8ed1d48dd4752ee5cfbed11469e63a3eb837aa2e3a61c547ae360bf2b4bc0217d406d703af5416435c690f7b8d8cac29dc772316eaa70f1a3	\\xd6a30e2835578ce5d2a3d3468cc1c4fa074f142bbbf15c64222e1ad2477327f07f3a192b611b0af4baa9f3495b4705d4c97630d7a8aa7e3b77e77a367ebe7709
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb40bcf1e2496cc2f43afd0c7a3ada784688e2f97ee94c3c7e00d5f2805d63f685b928a13b04f7cc7e1aad01d9a459bd8c33124e5d2163391d0e9a263a27f5c95	\\x7793a3c377a32d7328bb6a014f7bc925b3a308e339897ebd2802fcadbe2df3318bd08e884ce0e0a6275ed818d3297dfe7461c5b8cfc4329f50faebaf9236ae07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc0c11ca27bb5396b6c69fc6eef528e0c28d99bfc6b85937dab5e5c4e870d41ae3ecb409c1b2f19150dc1ec6b5a8909d1b3fdf90a82d592ffcaef05e906d47cde	\\x133b77351659167ae6c5151936f63b82487be3bff6b848240a74f6be522eb2244bc49019a09d26540c0acce6d056288bb3791f0856b98f3cd3d546091d8b2103
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb32630dd389cf5fbc5453cd42ae596bb0f17cfc3041dcf015b719693e6f1b7226ccf517d470efcc2f36b0ef5a0e74ab0f30b224f9dc413e9751dd2edce37580b	\\x433d1071b1e52a581bfdc36c4de55f2219cd097f38012ec50d23b3b533146bc1a4d14355615627838a26bbf4f0142c01a74d2c56ec8265709d64efda7613750a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf77e5718f7af88eedc3924f6e39869f97f2275a63bad5c66181bedc0a3c690640cccdf8acfdefb68c0d398f8b5453a54cd5e0deee4c15b0e064a3160f55ee69f	\\x3b31d51eaf26c6c08104c9818d9e5602435c6821521b01ec5e625c4c521f6a12b62b00166edf57c0e396c7b0b9345f2da63da946941ba696f8ef49429a923401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x373ebac8291f223bd2586063311cee6f5f88156e75d4d74cfaed1d11cca2a955ad04705328e3f560328e435c61e221324726b6257a51107f93a3ac818776fcfa	\\x99adba27134ecd9b983829c33b571945a466aa1b2e6048d39e67635e8a08a887ee9132db2784f1b877aaeaa5157e1f878275119b866103db50af75531d1eb807
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6baccb3f3d599b9e6a2d76437cd0435f8907da2ed0be4dfe1b33da403250480135f0ed6ec326b6a45e3824551dba24c1dc735918eab62882cade7200d6627c08	\\xecad4c3e9146f269afee21f8df4375d6270ee77dd03deb3b0fe4acb364e986686c1858d05f032dbe246f94401ffe12865883ab03a17ad0edd8d5a484d0fee60e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x03dd2fb590b6a224edf91629a957e8676712e5cdc6e30dcda2e8317505dcba6c5193a27d718e41120a333230a3093c599c0f2f8419cb6092057aaf8c099b1691	\\xa6c765089d4b36ed6b604953fb2e0980d48c57ca597184e3ad70f77f1c1eea1d00f501d285164062244e25125acb5e70363f75f2d1ba089e954372c37e790100
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2660361a7c533f47c484fac1e642fdbed7e2897fb3d980a5060976a94a8c21d419f79d6130cf46cb0e62c1ab7011b2828acfbabd198b855cb1de9545126459ed	\\x92f6ee3d076def88f1a95382b4594ab987f8f4a27da33b1427e805e81fa9f720c5397807a5a625c86b4f065ade17ccc8af855fc8b2331946fc015c3eec24b207
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x652bac6295c3b7de523f806a7829e4fc9006dca48e8535531a5b8116382b4eb144c0bda3a614531b7486e41548dd362f6e797609a40fef33d1fb03b3cc3b06f3	\\x25db1262f9a07baef3330fcea8547ab3acb453d88683e29762c78d23496f48c81b2787d570247045764183037105d02b406de55392b9297a2604afb9cdfab60c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5a9cb89018959e7fe76601bfe8eefd286c23f6b60dcd0442d338cf55efd9355d0bd4d6e9d00fe75531f589faeec04547839bb19d45e1dfdd93d13792e7585bb8	\\x55e120a17b35c7c75df239327e9b72fe213e9f0c9469ccf1ece605d68ac8ab34e21844814d244d5ca3673fc5c2c8e2b83b2ebe8697994d49ab7faf5aab7b1304
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf6b576bad4c2cfbf4a50fc1bf838ae8e56a80c2ff2304df47e3ec1c72eff45a8419d26f6428d9bbed68bda4c2b3a8729e6d0ef9781f32433e9c18b1202b9d639	\\xb28889e0f6d2b2b5294e32f3dd667d23c613e345dfb2ca344b9badad8ba0d8036f56cef013b864092d1b63cd0d2daf903ba0132cf25c7d9ce557ab1f4b59f401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe9f36d8790ad239798572d1e3f024305b616d96890aec79d7490e6378343706c018f2e00bcd9254b087b4453c83f69a8ab0fb7006a92efd867187b500e03f38c	\\x7ae9534bca56f5d565073eef4b571a0f49697381431acef734ff2cc001b8c8a4a375539fdc4a7d1feba8c48ce99ca89cba139ad2e479fa390d306d348a9f8c0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x315d25ba629f25d9c08fb92fc2a30264e44a4480a370a9c733db64032c3e09b10d78218ecd5aa36b21cffb825e0573ffb5276a5be65b0f43528f07d31a85abd8	\\x5256f02b59713cc1277f17397a237e7e475692b73834bffbe2d9db435fa3fbfd5d79136b257bc41d039716b7b564efd9b88f27c6f14458e1b7ad836ebd503f02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa15f1d53b1ec3b2245e5ed9d3344755a55c8b24c902abb2bb7f4b89cb80a1c9b672eb9ab72a6124298ec714b0041cea951350499c67db7f415906a673b9049b3	\\xc377945eb5ec473419a21562c2c4224c1d35e4983c1a7aaf0b8fef429cbc7f9c08a96d6cd6b6913bc4b0ba3d7f3c37a455dfb5826003a647f841102f69ebb50c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc6fe22da8cb34614c8f4b4df37cf0dea13c6be5806b05a156da31bf2739f502507acfae674baec61bde79e78aa36c05832eff6fca40eb1ba47547b8bdc81b654	\\x0c5c68e765b7bfe84dea1d361d7189f360689621064c559ffd4792f37c8da0ab03ee84f5f34b2444c34ce6fd7b86507353aead2f8b11633d4ff0854483165206
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x076097b1eeca6dd74b2ac81c8222f833ef737306e388e0ff3c12a9fa67f61499348a2a02482699e30c6e0b3865c62cad772c513b13650de66707ec5243d7d114	\\xdfab8501de4dc43b2b7ebb02710088359535f38726244c093bd82f0b8b0e478d147d246ee2f17f37b2ca070c3061e6445ef0df5a03a33d46df45861d994c3603
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x25f7476959474ed54b6de280282ba597c5f3674227c6bf1aea7e22dfe4cf0b77b1a12c5e027aa92769f7bf533335c31fd64fcefe89b43b034079588e71438edf	\\x9945b98f70735f144dc0205a759d4668f824f0ee6c210c83a89b3bbd0f8b4b7e4acfa52a4f482da197bdef86b490728eced778d2b102f7ce8c2904ac778b4904
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x083c68648bc47e727c16d7af2fd48d843efed0b4f322d64f444aeaad097e5cb0086cd29b89a293541339aaf810f149d1431b69ef14c69046669d53549abe1c16	\\x2dea35a5d6c083cfce8d0a9a9568ba6f3a8ab2f0ac1444bb4d6231180a48fd60ba43bd4deef6063e2e5ad338ca23d132e0d7d0c2a9c89917eb4b5b7b1b4e1e0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x97efe00145fc45703b97cd0597624e6a3b83e97b6f1ae179a9147b642a06c7b7f75842967feb72d759c24130dc91654d3fffa5f3ecb904a8d7f89bf1bea1af52	\\x2c894a61c649e81bb96151c1e8b46b817df17a5a4c6fb038989ac43ca45d9db3848d80708b4ae865af55b7e70f7f1b11dd5bb78eddf7748a4ff9c8cada339c02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x411d63016465223f58a9d6817a1cbc8cde7c65fb11958a5bf0d4efce07ca9bfb13cc5f43f9f6f03e5a66623b4f6b91279fc61ff067032e278137540046bfc2dd	\\xed071e9b6656644822742a5d9f4767aae263dbcfde4854a6025d891d0426dc062094b4c611ad140632839123de595dafec94ce9edbaf084b83fdc3caebc1b508
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd783cc1f89e022174c77b392eecb72d3596fa8f10087f6c7da37774247e5d75aca6eb3c94417520fc60aa665d6b56a96725ee9148d738c9f9fd02e54da0d4ecd	\\x7afdb063ce9463ceb410d909747fce3f4856729ad323be7f191fabecb4feff1dcd35313840231abd959f4fdb1e51222de6eb49a2fd07b248dccc9c8e90665404
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x89f20bc1e4c2183be61fbbca988e8dd24c956984725ea900a4e1cea168f0379eeabd510d1bae66e17f7cf0897def272b2389f4f5797a2e011a63ca6edaa8b745	\\xa33f61200a5322a683aae17db2147f8e456b8918993bf202964e5073cf6da7edd4e577ed13c540159a7e8da6b2d3e9151b8c9df416c09b41fa1216b1d4f7b604
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe28bd1f01391944d3cc8987902ff798fb0a8f3ff0ecef3ed2fa763b0923c22b02afe49fdb55bdd3f1593b5826e60cfefab94a6ac4f69f4133176ba625ccc7672	\\x4437fa21cf80a2a2a438332900c3fd14c724628274206e3ba46b036c543498ead05f54c117a2dcb3509f61d80a6ddca48e11f0fcf4b1e9960a6ca3da8d77c20e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x02842e5509956f69ee0f325c66ceb060b4f40e3a2e6cf1c85556f0e1f4e46489ffe118a7db0a6cdb21cace859d725ea514435f5b1b1e5e9d252c6b46ca1363c7	\\xd3830e2842b0f6bb9b68fd4c18ab81203ff533d9b2f4dd69873bb0860627efaf6b7191b2a03bb11d6f3a4325c91ea2e73927439fd460a15efacd16cb61f8680f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x46b5bbb4db8c61717ba08ec3c21daa7ea8cfc924c01c0b8a7b7b35db2f17fd8c0955ac7f6ae7515e39098d36b48c6b0b6491cd4fae6162c13043d4d272bbcdda	\\x1c00c22f38cf2377bdfad939acbee9b911d4e2af16cd51d6c004d85925c6d4fcce8d4017c222a205bae1648a0d1e7049414a81d3978a7dd3bef023fd38189604
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x706a190099a422494666284f05713fe5f3f717d433f2c9aae5e46b617df68df82719727a7c48e7dccb690bea54bfc62c8600ed2441ecaf78a215b654fa390f6e	\\x8814d982ebaf93e4f4ce803109b0c521213921581ce0a0f632ed9367f292ab99c0715cfbc82d9ddaab3ac8de858860e1e6d1462645ac47c0c3dfba7047d4220e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6aa24dfc86e8f65628138cffdab72cd5ed27a7ac583720ea9829dcd4c8009c524b515df4f958664654a655c4c86075dc82d9ab26d5ae9d56f4479f158936143b	\\x4db687f017b5429694952407f59a8b1f10258e328043d8059b333ad5e954aa6147728194b808231c01957d5241065493c8175bd4aa17bec3de598c1fe34f7e0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x65222be67afb8487881b2ebed9c0a5450db1b12f2b265febb2b267c341a21476a8364e022c7376935bf9a2312acb34383511175794fb13b541cd1b6bcbf757a9	\\xcb7bbc892714c3b9677b3ec355ee4ea0cfa00abb630abceedd1a8cc2abb2cbfb045fb079060e6ea0978c4ee6afd0b2628b099c02e9c5575a549dc6b1485f4400
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x04855284ea1cdf2ace1ad45321370f61d51cb09d9f95e5b30b2e317a10bbc4d1fda1134aada7e5703be891d9e6ac5adc1f8a824e0947ab57a2944e2d72ae55a2	\\x9b2d5a0b02d6d8eaa4f653064a181a7f0a7772d087281540ed26be04e3eca86545dd89ad33654a5ad4d0bc89e5416da4efccbe9ac0b29f3e5a69220f5606a105
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfe7b558be9cb239b99f25255ff4b13331fd1d2b3f747803f00138d045120441a74d2b9bbbd111f03587327e959ea79a1d86d8f1c3e722f529f3cb45278108d4e	\\x57c9331c8d9bec5d98dee0e77a3fa6c56a38b1febacd50fbe3adf31b26b4dcb30eec4fdd88ec5d5b100217caa6f56dfdc9e238ebe2e97291939769fc4158f70d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x655801caa4c0439f711d2e25580f7eaadbc1f7423308b88e24150b2cb1db801d21bf6f8844dee38ef0344c003037b5f508eb11f4294165cb42bc0028040665da	\\xea497e1608bc5a0477551cacf871e9d5dfbef0feb9b8299c3b774c569bccaa4cae7c2d2b526f16de38298be6448185df0c787f6a2b0f655186242009320db203
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x47c9740b2c8fc866efbc7eee30a9950da0104d0b6b90896e1d235e538201931275475863b4ae320af321925e8c4fd16a2f9958daa445342e9738ef4097bb18c9	\\x45838ff826bfc17b14496ba394aba659a7e98f4b520e74a98cbf49cb37f6532b41e5bb51ebeab974d3cf2580ead3fa1d59d538b0c995db8c7b9b42cb2191290a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5c2b2ce72c93a785f9d4475ee95220f11be31c7107b3ef9b8483ec85fbcb6a0318e5a937c2a9f5ea60329562d02bf6ded6944e56e4af7c71d7a5e1e222516342	\\x64e91c5444113e3872bc1cede27cd0e16cb9f802c898f116bf5bbf2f5263533b5ece04fa560dc20bf505b9b80ddaa9f619dd24e386e66b40c0e96668edc1c507
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7c8f6eea690cdcd501d7c5b23a501d65f8ca8436843c8b8d0cdd5d3c700254c8f846a37597394df9b4209bc513a7939c2ca5dc1a204baf50700e307388b33902	\\x1b1279a11a3518077d9c6aba5a0368d752f76a7d1f22a6ab1f538e2016b671a60fa8b003d49fdcdf5c16a7a95af1968377577f9f466c41a1b0bb2432b3d5d00c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3e6ca976dba3577b0bc95735d192c02c3a17958e4b83543773f7379fac3094978a47cfac52e1ab65dd7393e338516b2318ddd2070a924e5c10b1b7942b2eec55	\\x082c9f1f69c9b106dc2a9c28a459da6eea164a14a38c3c6919bdd8bc3d7d64db4b7869951bf015a0de398309e70dc3969c41efee98c411bd2f47b042570c180d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x403d83f47c0651a0067ac7a0bede24b0cd054803cb16bc2e2ca8fff9ffe7c830c31420306be8fd92bdfe77af0936d40ea206d64209c778ef62aa192459a8513f	\\xd261cbc0d2b49c6d9bbc66347875def8f630130839b37609a17c98108e4b7ed7c4f2d350ecfe2ce92a396b15d0cccadcc275de6e0ad8fe8204c06ee2bc91da04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xef52019279ed69d3a663a2d02228cb7cdbc82cdcfd46a93ef9a2b2d18fe25eabb115e01d1903dad39851d433d0d64f385c9822e953cc03db1b6a192ecaaa9f2b	\\x4e08774b85049324d72610e01166f91913a96e95b767810304f3ae00e3eeeb98c9701638d91ba9abaf8b34d8128a4e79e79fc6e2baa3113beb266d95056a8d01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf4a5b2b9a56817f982f57b73a5f85eac99836bcec6f125078b4f52db74e1a425c2c8b8552ff0ee49b28e448a8518820bc139a141402083c37954772c9f54b2f4	\\x0f599626b7e54e6d59896444b5c7084270716d8b8c87f9eaa9e1e55c579bd8b8a13c9c0bd675b6ba5a66c18d3b82f3b7dc39bcc15a6838c2120946058b2e3205
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x12aec27a704454595fb8853e5056b1f105dea50473a53919871217b28c26643b5737ddc3f716b14492f20a76badc40c92bb05375042f89e8c500a4f7b49a2c85	\\xfbee78bb7e024e2d4efafd04a98d9cbe9127da6ec93c875cb99edc65d94814bedc9cfac5204d2c669fc052fc2b9fc537aaeaf7757013f18914c00fa167b5c70a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x85d9fdd1b296df51a6a62649959f7410e282a1925377317503d73dbe5da4b911ac7fa5346c8a674a2c9f93cba0829d2f8591d70e358bd6fc2d7bf00d198fcd81	\\x6c17c570eb32dcb383c949931f39d0531f195e0f6b6810e1525c37b288bed700627397236724216f414170ef26b9d3c11091f058381aac139d7727114d1e9301
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x93f3586f1746b92a941ce7eb57245f55bed5f7df15493cdf2d48de6de4132ebec6e1e059373f688b4a7ec264ef74f7eba91cf7208d8eb7161fed8418dcd2e899	\\xdce574aa5cf518ebf7ecde57f9fbe717a5e528e3fec88231f15692a9d0c2617385bb10a57df7d90af8bc8bcb56ec060d8b60b8bdd52dd14322ddf967fb8fdc0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb9a5c3ebf19b6839c1f343622bfd569ecb537b549d9be0b82d5a3f6c7074f0c3dc820f9e57a413679b9ff6678d7bad021e3535a45ba353629784cd9d8f618989	\\x3a00c6c7a498a5d99f5e770d8ea514e1afc8bc4cd4d242dd567bc8580327043ca5f52f267954adf5eb1422c9a9a451ec6ff7e2415c73b731643d2c27fbd5d809
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x27f3785f40df6fb390a5cdc5e2755bcfd368e6e979cabefb28a61cb4f8c12854286ad9686c4f11d7d670741e0f8a5bde3efd800794200647c708a8b47df86c12	\\xf10c1e7159ae28aaab2ec92fb3a71d93f638c8778eac8fc53e47b85ef177caacb7c31f736069a9ee3c9d00e14e80456be7c31c2495ec577f7bbcb00b784c7a0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9f3c5bc1f4972cffee3c6ca2405bf9b77acbc01e8a432babdb9bad9473275bfece7d5f1e1db4296d9482dac4e0b3fe21352d5dd6673c70c03b608481d324b184	\\x0173b624d5897e53a6272e7a5d478587b5a5d5b557ed2be5854ae897be99135abaa78a41d42f778df24c12d2e69823302c0ff1306b2cf216afca0b0be160400c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x226a60d5aabb1d0bbcbf8ed473ccde749e39e47cf2b62a433680400375898babcfe960dbd3917c84ed12b4745c4152f3d9dba144ba18ac36d30c2ede8273dda8	\\x5f91e79d7e2eacb6fcb89201b25521f0cb2aa73b544cc0103612ad4619b98a5f88d34b8d502eadd213fc4c654ec0feb3be294423abeeb680c9b8df9aeb260703
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7e9ce03c32a33ceb8b2581205eaef24db6654a91bb9461a8c65ed677ad4aa677eb65d43d6a4dde2f755c447f64550965e98c783ae59413e9f07e0dd7246a3a5d	\\xc83951ec8f687338c75da1127d7435822c251dafca4e91589b7e6459d042af97e839b6c433210c5f1cc4761adad86a624933e2e181c1e6f9e2e0be62667f9607
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd3d26174e5f35ca609aa43878d927028d9154fa88081765b09b197dbeb94db3f67bb4cb9ca17d5d69126a0693dcb754929ff719be8ece9a43c3f2bb76a99e773	\\x37194a43edf8fac19d253e2fa0c702141523716932fc3a83b8ed0c4c13e10a08467bec15da1efd171951ea7afc28620db86cb085db5864b4a5b7f5a32aeb750a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdca06cef824d0b58d765fcc4074c5b548d4e36324db61370a9d8f21ca7e138ce5f009819e06a8eb09b33b3941e81cea3c13d00a8461cc99eee63809457a8ab80	\\x1cec043246fd321cf05ac1b0d0565c346614cdf3413184b21929544d65ec294acaa25c8abc61addbc7837a8a14a38a2b0bd97124ee614b2d5ed4d6e6aeee7e00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5032784b53f9c70fb27f470e15241e578b705153630f28b2c91e477d05315bd2e3dd2379e46b2073144615799faf45b4984b7393823064fdb5857fc44d442de1	\\xa1641414d9c588a1da9baf29fbe784d1833f2aad5dd5c30ea8e70d58baca0795eb80ba422c69663ba8c50d71b2019536e4fc38078d3a5a268e1803bc6800d80e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9819644017eb5dd54618a43db845d5b3d62fab1f0654a40fd09ef85a7c79828e8da82b1c7db2cbfcb6010f3a0b0ebb0b691b5b984471796ee97c900fff298f68	\\x52d26c6454d5e0fdca4e9344b6039ce12632e7781e6e68f5008b480796bd91704797325783147ae82fc05e77eddfbf551a54339b3dcc1192d3ad1c3f22018b04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1d069b9e27d64597b1ec52e9ac73e8e61d1564f168f19a7db0cc8b2561e08239939c2eae3c82aef431518074878923d87d80b0e87165b4e5b5b8261c88ffde68	\\xa0e79b7d5418a029245f088cb5fb2ba81e1819b67bec263d8a38fd5bf3f8484422abeaf5f884c82d2f31941b95b27ede06109e86534dfb9c243b733e839a8109
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x86184c99a4d83b89ecba20b5036b795bac59f3b9c664b422064c36fbb82a47b1db17a317b1c37235f630ebd2dae8061c9077e0ab9cd70fdde9ee5bb4da474dbe	\\xd0ab852f04d659be2f167c56fe97fb598c5a910b3cdac45ce21e739d2c9de7ce430d99bddc11af67d9bed586928ec2ef7eb93815146510198ad29f0b23e5b90c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2f53300410800edbdd99b398a24b451ab9e4a3b36c66720260ea1d414b3685805ae684f85fd5df35a36aa35ce491a2007085c59ac7eef24a5fd454e12cf06c73	\\x6e1837452fc9a204e1e02a40a3db1d1eadc6c7023805a2529a78bfa9ad551483a165a36263b1d2e45d369d6f4a19f17c312078e9c4adb77f0a1135e0f0cb9b04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x738d35046d1d1f5097d8833fa628f3496d4d00a64de3e31d93e32e32b0f03e742dee3ba2f905c3f19f2cbe9112d10413a6297d510e2ead4b2a309340464309a7	\\xf8bdfae1874457105df5a8d9796e579376f7154d6815349d17975cce95cb0bef97c42c1b45d990a2f822dcd7695a73981cfc998f33cc69ebd96153dd824b9902
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3da70fea3d01e6600c97435797cb3aa5911111d07297a4289092961b24126c7c72d92fde52bad0775e569cd6742ec7c3196bc7c117cfc6805d01ab36cad84a0c	\\x0b332c0bf5e2f7d27b3e3a9a4303567f8ea06976c67b20320f77589fc4cd76ee7c487ecd7d9c681e4cecd4f977418d5b7168eca0ab4bac481d100e7547622202
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x44f3e0d823f52f5a05d2f0ab992e3ef89d571faeb683e1382a4a29ab8270e9ed9f22aa8690eb99eeacb52c6f28ed679a44dac306ed1e01150f7b8450df1dc7d5	\\x181705fd32b237f3d14f03ae222977cd4d486da70a8aee52e0454210caf376eed4f09987217eb0609efcbdb9bacfce328f4b79e6adafa975601fb319b9defb02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe629014ab9b1147b59c1b15331a2849c00cff863ec2a2c0512ddcb6eadbddd9744a9aa769d1fca005185d5b66c8597a0a61caea149ef744f483e54fb0b0bda47	\\x8f23d400e9841823ada3b661f664abe99af84ecaa819a051ff12e7399a796f5bc2a60f7ec00da1b11e5fa6988c7fc8b376c84a8416efcf837f75aa0a50819209
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3a528ab9ae2369c82abfb29948bff8b0918ec9f3a3e5b17bba1761d5684edcc75115634ca4cce905b6823817dbcb397acd8ddfdcf5eae566b567a76dbbed6ff4	\\xf428b4b1bf013fa89dbbaa3e869f2c3761b21764d32a58c17daa0d7e457edbcd05424234996563b93f2c9c205717d51f51cb1d1b93c2a73425ca2613bbc88800
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x151a8a3033c70213375d92d400fb90251efb45d3a70bfdae24e914226ab7fa8e041d9d69aa9adb06fd7a00e0b3057198f43387ad1a2be1ad9a4d3f63e7d68ee6	\\x5731823001a606b16faa86efe678d4b88bac966c5ad1474d2c8c7c9de3fe0d360989e4da1eb5713510d90879bc8a5863a6f37f9c0fc0786f99b88976480ef60e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1ea962288ce8594c4fb929d06ec30f4a9a0c2839c1fde4744b2819c3b73ce7a58efcab810f4a66d2e33f306f139658ccf89b6e31bb1dcad87721c0ae2b7f741b	\\xe462713b6a5d2e67dd3bf14c9dbd83b0e24146f8c3b780dd0fa8903f880b1d19343daef313574001b663a9b63bde06533f9a0c19547d95cccdec1781e2f9c302
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa218b360b78a96c76d9bfa18a0627ae01086fdab4d5c11a92efdbcd3f225d9f6073f0c6658404700a3b17aa7682eb08d8eade4b59f0b6c1ee2171b2081348db6	\\x7b3290ea5066d4139b714c43ba2acf050c025a8f04636f91e58ff27665c8a145ad3b9c004135f9e89e8908468c2dbd592c629787e57efebfc7337c3f4e9bef02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x40f3aa07fbaf69705fe5dd87cb1618ceeed70daa2a5d18fa7c677ec20dacb3360c6451840a4c6b8353588123b0e5f34f0f8a08b4807d8e2fab3127a1220ae8b8	\\xa9cb614a0e7cb15a1b89dc7144b2b9e073060ad8573cb7ef30b50410424531badd1016f7a6a74f56924af09d633f3c0809ade11e223d0dbeaaab546a0708760c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0205479279cdab859dc9f547e3ef303e74fc868ea648b2b1d950147892d7a7f0864771f22dc1d64e922dde3e76a6143c99eb0001863a5254e7b1e0bb8ffe01ce	\\x14c924e83bc0407d958bc242f78d96f944b704fa12262a72e6384bcea20d9fff4280166e06ee568eeae2aace1de8d4b8bb7684ab9cf9aaa4c94451c5b0f6c700
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3506ad1dbe982cb7fab3c9faeef93f29b53aa59d83e2626240d8ccdb327e98fc7e93043286fbb07158a66c11743d63c901f31420c36ddafb5cc61323feef2d50	\\xfd99265950f634f8c60e283db229e2758774067c6371c22ff2552aa7dfbb0ed547a52e2c8c09135652c90b910625a10a99da67babf5d78c57878b2adbd36b000
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x08dd7fa0813fbff77828d1133351926d35db5284a73611d1af3410d189f9eb9a0eaf2a34802cb93bc9b2c6558f0daef9b0bf5d98e24b904c55b75e409f71c67b	\\x9729d0361bab6c42ff1b7d9862c77b918892375733c2359bed9096195648f882e21ff8422bdab8a5f74a6eb57679c237c11f859d1501e05dfeb4454f329e8201
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb33dedb27cdb56119fd9bc8a7806715f0bafa61c4aa6aa185cab4666e74df331bdd7de8054bbb4fbff4ceaa98ea5631124da5cd3035a8aa78ff21dd694bec2e7	\\x2e63e25c414ea3426c8908bcfaca509b13cf16b786202240bb7ba4d91ac272b43e0ba69ec622ea587665aa20baea80fa9ef7d3566dfd477d598c1458878a8401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa58e2cb5112541b81be694d3d3636beec72a5d0ccc339a28ba6bbac52ccc6ca8f8d75575406bd472ef2d0d17353b70c2a789c55952bdf56c45826f362844c40a	\\x85167b15af50725a0c8fd40b5977baa0b7aafaeb79af203f265cfd01840a2600055a0b52c643dfce53569f29591ea567197e80e4722dbeea3b7325a51d4da40b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xec2f1e05c584ebb4fd4373e67c18efdae23b0ce192d272888fe960605a08b35034ea04229c6243efb2f726e3ecafcc0cebed7fff7a15e15920c5b6bc69f4b820	\\x63be0a98d49953acde6f70172bdf6a82112c16c5f18019de6e4ab112f6ec8c8f5a6c41dd6bd8d6e33dd63fabe23eab95e807aa76537f8ee04b9d9e42b7130b0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5ff00e0831b0eb486f65d1d7e4a2fefb1576d568bf0f3993802662e7d3305152d99498a1950ca8834a661b40995dac9dd57de553dc306ba059d8b454daa2de19	\\xe370b8b04c1f3643838bbf2657820c8c91fc3b74b6e20d90c5299c6802162b66de2c8c4190fe3fc617e268033935de8c9dab5f45e9a5deebf93aafbf1ec77e01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1d3811460dfc9fc6cd89726beffde7dd641969199c9c6cfb3af86247de4cb95548582a1c77c005643c227a9c573db830b3a5a66550f4ecf8648ba62ab3e2973a	\\x4138d8c793c5ad3f08c531d594d849314c1eba6830ad8ff863a0a960e64e1ce95732b9cf611375b75fefe7bd20f0af793f1107102368f4bac99deb21c9723b0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x253c38b14429c0c21083806ecaa59746c5eb957e955ad68ceb4b4ef7f77dec6f26ec913f8b6ed82704f18bdacb423924934e7011ab03b1487bbccf98931d8891	\\xde60fe51c2fa1c2a8e2edd78cac3d47ed320eacb4892a70767c9a0cac2c693cfc761d62345efa8d8ae4aa4310aab20ca2f154394ffe0b4cfe82ec696847c840a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6a582bb8a6d1949e9f5de5f7bf3ed2403c73ec96e404ec852ac589f7d1311779662a603da90078f04605b330992bb86f52fb8f00f8ffc6ee09859920e6dd0cd3	\\x1d5682acc394cbce6bb0b0d26b916dce4cede253e9d11dff4b8cb460aa2039b1012f73f60309a5cfae10ddf5efadcaca7e6abffc843cf97a7beff0764ba6360d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x597c04e77118b35522588ca1d129598b43b66d50eef4442d367ebe5edf7f059f0e1248d622f6123d62db8e75372838acebc4143625fe277a89aa04000877848b	\\xd0cd5134ffccfdad010dbf44bc5aca68a541067803d88373ce7c3a05b9cb7fb45177060def957b63fbedfaa0eb1c63e9ed426013e24951fdb18254e2f3cb6d07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6d27f35dee82070d8b1b3f8b35dcda3c565be16f5b7b48512b5cc46761bb4916f43869c2dfe7fb4c894ec873b7dc4c1fdaad756980729bded2fb63bc8a075f6c	\\xfb41ad7716165df990f514c15c10a906f737b328e7ac16ff31c0ba4e47d9e043a8dbb45729a506302a9615e42951c3a270b9624b77420aa85f033f8d97605b07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x47a1b603491acd648766aeaf507576d0007753324f50a08b00584e87dc552e55eff3d67ea9106fc2d49c9f532bc819a9e3a3e6ca832a490d07d53125d60e44be	\\xd5171ae8ff89a080890293cd91857e9d2cb34486bfbf48b2f00adabd3eeaabd471da4ee93b238b7c8f1830e3769052f5c101a317bb0142575e0bd0a0253ee001
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7e0f454deeb0b443f299ef861eda8ce02d3b3f10ecb8a3918fe2b9c016a48c7384bf192efaa7d64d2b7de2ec6579a84af9968323d11279acd3d29cc1a4422669	\\xae04d83b37b3317f1e4bf4aeeda8375ebd6960064d51c0068a439527b9a673d007bc84bb7664dfc826d98eb94a77c128f13fe88c5351763114802269c4c6c004
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa16bcbed209595ae9480d5c1a78bc251fc810030b3606c3f03f8651c4b8c5e0e9dd96efef5a03c9bc019cf2e2fe140cd28bb03aa0bd28960a3fcee1ee3af50f6	\\xedd0bba4215f9732c2a87c841ca4694e332651746ea0d7b8cf3ed488cd1b17dbaa633ae47b28b4cc6824a55232ad2882fd71b3a9dd64420345c59a2499fece03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x832f5dd41e8d9f73e94b103ed870aab574f685a5527365e841cbc487fb0024aec363807032a67c466c934945549806acd1dbd212db75e0d5287a754651987281	\\x57f4a5291e5745326ba1d1112b14cae4e7e9754fb2a43b53d2f85a8291a79ddbee92a3cf19a6150acccdaa2717fbad5e6ad5de2764cb97b4b2d68e59b132d10d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7b5323549d4bb37cc3077c90d65707a6a64f3f9aad86350315852ae0ca33300ef468e99f1b621bab136dcc8d30d2cf1c4dc2fd3940ac062f4a310c381df74a2c	\\xc28701577159d4ff94185a489104f7e8874b4cef3701c7bb103459e6e7b16f8a08321365178fa0f519d449517b99c2a61ecfe21f7d304cc9d7eaebb8b5ce7806
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x854104e65d2f9da8e7873a9e92db4a298122ba0263e0c4f20bbc1e30b2db60e3e37ecaf71219d9e12af8267991bec3567cc56fa5cc05aacd6c04b44aee299ee9	\\xb1f37be2b255c674fa9558d97a4d3499918e26af4b9fd49ed6bd03cdb505edf181c456c8d9d54457e1b62cf1706bb489b413386f622bea8b8745fa80d86d5406
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb1b401c245ed6b9ca3c2afc3ff11e6f6e833886b791fcbb06a52d7f9c88be55f9be74afff372f1e72b65f6ee0db203c75b6bcc852934fa67bdd97af0f6c03031	\\x74dd3554e22b0867458f088e54549b6313a37897bef3f1aaeada8210e94a449c8d3a5d3c6c558cdd5f3df824f3058c6809e769371b9cf627ef1171df79851901
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9b3c89d27d5915129fb0271b45ebcc686c74807440d257abcb4a601f570e14ae7846fe49f512e5aefeb068f5110ba1bd877b3809aec4c8df381fc24fa773b35d	\\xdae3fff2e6a54e05574620e86057e1a8bc579d6073a5b2e6c75aa44bab6baceec10c21c4c1ddf9c3bc1eddc194dc1025eaad20c6970e32ac984b2ded458f3608
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x21e2a3b2b04aea72f6502de2338dc481612b388b2f4e2c265f549d8cf5c68da7d6c824bc546ac3c8dd001761e0091940f48c1097c32ea6bbfc273fda110d74c4	\\xe391bf3cc2ac8cb216214c045b88780ebad249987efe64a53eb235d818411d95c1429cdd3bc53e303209968cc37569a1c37069549c246e6d3e5873f81e89260f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x09157ecc93f1396ebdcc8a0b2f8ba60d3e5e7be2a880ca1b85b4b299304feea2fb56e8b5eebdad8aaf20ef28c61df94a921b068e65899b8ec10f672fb3e569fe	\\x98821188baa0d0f587e3f496d3a62ffebfcd721a991677ff4ba80a2962f8d8ea1e920980fc87b38933b898792f2445e2b3787226a4d295c61081d0170ee4e20f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0a963d2adc54c69d9b3f6a91a6c3287bc0688d57216b1a5603c8bddcecf4e04e114141551271928ffd0f4f4b16f01bc72b5437e93a12ea37f94abdeb27cd4eba	\\xf2aff601c5e67b90cad20236af6da0ebac8c0c05e10130ba29295dad62dd5fca2b239dc67f85b932a60b4a2dad24fe968a5eb95ccc07a5940b34f11a5141890a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa28fe4c6723ed30c259417e2df26f3282fdd218ca09b25d0b6d44b7a31d0522b104491dc811e67cac0d39993230e81007c6890317d533288853b1bbc971c482b	\\xf464a45792f7ed5ba534ce1d36e2db008b3a3f8d2e4b711c345ab7bed6926d5a9454da68aed1b3593ae177772606f63337b31f4d6273694d24befc9462ca240a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe0ef17e202634474776d834cae117b2f8548c2f8e07b3a442b879ed72428e76ad42164b83d95f1e0f83e5397ad90816a08b1c78c4fe45f19e438e8b56c0e57b7	\\x8fc10dd1dd11ba431f91c20b3a96229b0adb949dafb8e682589ff601abab97365c8ad578c390c32e279dfdedec404b36ccaf1b7801378b5fd6404163757d950b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x23f94877871f345122feeaba931940be60c41d4d3b0be010f13bb295ea8b191cc3f37c110fbd3d2984a5cd2ce8ef247c273ea2d71fe57f84f1f22eb12a92287f	\\x47db839cbbf1e0698d5cb3d3cfc0a8e388801437f7c631ffaf58fc0ca697c5c5ea1dca160a186f876a56dd05d6ae39ebf7166b71151560ac1b22820871620b0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdb200e05d9b4e2ee5d92737b75107c70c4e6e3347fd7717f50598b4065e27a8560a00a28b8bdd5589c374dda885eeea269174402e7e9039bec3224a5b71b19c4	\\x00a0e791ef7d2aefa33f1e413b87791bd1cebbb09e760d4ea832fabc06d62d02319b99e322afe535095e686ac50229c0e76348e7762983b471324c6c08a0c209
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x831557c51e3d5510fac9e5a3ecde8fab74b5ee7335b63dea06f4e9b5e6ec26a902e465c51d6e05b2cb2443c105cdd8ea3f88e474861e8f2142e4e6f79751e814	\\x36c308d686f16254830bd3752e20db7e6c813928653f7d40878248459b6a9f0800239d44a5ab214045299b6f9d0fe4d742f4d578419e7c8bb905dd249b0fe609
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x77a66d948b95d70eb0e18c88298ad9a9eb38d6678f1c8ee41a259c754e7ae27fd4cb4206fd3260ee055e6c2d89e43c0ec5b878f2195062f98ab1e20100c53e88	\\x51b308304b5cfe442b7f4f42a28c3904b84f5ccbb9723ffd8bc310ea2343cc46a6625d448a07ab268ed30682d3820704209ce85d4bc76018f01863c0d285d20c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x90181985a4d43487d5e05678acfe2b8d18c7ddc108e2db4ff4f13c0cd5a0d2765837b35acc3651818123ce8d2a4a8688ccc28599009ce5646b25632af55ee199	\\xb0527887a3d9fced9dd009881c0130c0ce0f94ee61629e97d29354796a9978ce1387a9ca7c2dd45476df934f0914f8d10f25b6d66ba5678b74d456d262863b03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa4d950c1f8616610cdca5d88b4818ee647fc95290609c7d57cd2bd79033dc8605f8bdcd167052ba63e5eaa2b3575a9273b2c654d7a60f4e403ec82d626ad1cbe	\\x3d1c36ddf166aab0748cdd2eabcb46dd2dffb8b212c2f1870f613d1d82bb31e34902e879fb65043bd522b9895631e549253299e720ee07dbf38ad4854dc8d80d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0229588baa64218e1a30c116699f7009ced601c2c617af3674f8ae349a5e61112615f213f71e04d3e19b3e8c29fc73cc14d413d88dc1d02574af1042272257ed	\\xc0934301d69f4180ac896dd3eee468e5fa7e87493974dc3dc9d1d493125c7888a46618fce47514373c4456c1e087b55aabd8101d0e5a133fa012d8817d34df0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x495043952b71c32078fb9265c8917361f4d9d8a1b4a7d9c9ba84b0c664298fafd34f15113117ff25ff2dd5b5f0d565211358a7302de117ff4f20821f73918a18	\\xc002012c651687318abe88de747dcaa7ed83f53e1c05dd060adc672cdb319c6988e604e8b86f69e26cd35bf4c0da61af136257280aac22f3eb84c0e6312ebc0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3436204831c07954612317731dc967c07e2429a4779dd39cf00513297d0b40f3ff4fd3c8e2e0254a8da37f2b194066d607ac9a702c24bcaed5b92b73407f23c5	\\xe581b9f09b96306fb1522ebd22c61ca39c3964b1e61aeebb92100e1dcfcfa24c901e7d4c314c4609cb2149af9010e931122038d2bcef0f3e8444ac5faa8ac602
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x61a978eec16b2ed58ff85e19defc651aabb18c5536ae9e67e2c92ac86c806f4185ae765bd260d9c1d48cf0c6ecf8ca1ca2baff8a61fba237c3a3e7d32ad31b6b	\\xa3b10eeeed35d0964ebedf4852e462b5d0bd36f47f93b7ab46beaa165233a66243e3f0d2affa7dc7dfca48f4a1fd103c19efd72c8c2feb4d347d6b3d0b01ae0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x60c86a0b972ef007434070bc42d33dca849084c2dc2bd15216d7b12e68a9babed32f53f06c6b4ca295802ccb124f30864db0872e523743483176cf3f89c070ff	\\x48f2a89cb83eb38b502ea2cdc313a20374a6c36c3c7c14cf7b0f4bdc73720ceff18fbc652a91a89acc7be8201091e708b61164ae7006167e9d6320a844532209
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1d1038655ba06294abf914d6a2fdb51ef4ec1ea29e237ca6094d2c1d6730541db746b50fa29f4f65bf1baf81c15107491e925ea03d63ccbaa017c76aaa11d73b	\\x1a6d9d1134c4f7d0dee4644b7fe1d118992ad18889170835ca3a2487b3715b2d668e70dda33ef249fa78a6995fbd62312831953d7a0587061abf2693196da80f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x09dc42d18fb591c1e15ec4277f38ee553b96747bbfd0d61ba5011b31ee8ea55b7b5fbc77e5b511f50f8ca86ff1d16d8a9f43b12896faf6a8d40d27565ae737b5	\\x2940552442f7fd72ae0249ebd2060e5fe1332ddde47e350d0dc3ee4b015cd816a1b292f042324fcd474aa2aaa9a1afa7970bf5867df3ac45bf883e3e0be1b403
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x44a0cb59872e178a741080bc4ad2a1aacfb43c6212ff7c7b201492c7e5dae324c47d30dbae34127b0e662ab0debb136b264c0314bf77c1d0c58a1f79a23af374	\\x618a026868011d3b7a8adcd0d3b5bf0ed9d35bb79fc2aaada4280169af4aa22fa177ee892fb7ebb8398c45a102459c42ccab230ff7620b117455da497e3ae309
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xec608c7937ba57d4cd11e7cccd1440817efd881e948891599d804a4a5fba2eef7295850002c2a298be37c1a98eea32968de61610bd8247a011b9045b39d7b994	\\xd63122f2885fa69306f5e7fc575407011692a26d079782988e96ec6501c819c2691b9798ddb7a82a99c42fb137dbcc60878b85c854ba13d435dd6560eafc7b01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x72aa6b8f737b86fc68a4055b57e13b8ed07748555f1569c9d29c2094d50cabb9bb01e1207b1e0ffcfa9dae93e6da639854cee89f53f0de215538c8a0d9196fa5	\\x0984c2dd445690ec34793d9bc9e667d1af4f89ef835e81f9d8b554116a2bfc7a0fc41a0c25871736e5fbc63065c54ec3909ebe70d5335f1e9a993ac8a90ed104
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1042f0dad3c7660cae237463c5a330ff37a87f38cbb056f9740d2c8ac9db689c9841843b32f3156bef3ab6ae2f7b4fadd396dac2dc7a761f59aaf00907b3f9b5	\\x4fce953bef6dd0a9bbf4d60fd57b5c7aa39747ea5354a475bb74302def0fb0c802d85d9a7dd4c7b20edf70d339a5eb7170aa74d98b041d1585fee61298f5c700
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x284a043c3c3bd0a8718e643ee059d6db9d20d8eb1927d6ef9c5119c1d09759f43adefdc20f7d19ee141966c4482bf7abcd16fe3dac620e4299556dd05c627fa6	\\x39cfa429d283578365bea9da625d8254603af84d85441c6a6d8e0985c6eadfea1d22429440b2f8e0197961443715a057fac007ec149448505592ab5f2022b203
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3ded0db7234e12f9cb2fdbc374ba6333223d20514224bc9ca54247f7ed8faeac74bb0e5adf35c019ced1c47afb4e559639d2764b501fbeed555ad24b2a274154	\\x78313162ccf5e040b4d6232768b3654dc7cfe395e3337c20392f8cb16f7bdf521a855736a210e2b449b73309ae0d29fe16e2b77331948e5630981b12f92ef70b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4605140d9785299c07d8fb18c07b5891e56265c04f8941a94c3e8ec464deff224b11add8042fafb5d91ee06f1544a4d0d75d8c407099660f8fd014f91bdf9131	\\x29cb5910fddcb20c025610a360ddc7ce3c4caf79bc4c8d1eec7502a95a6766c20df504d28e0a4d24888f3ce101c4b597c64e0f08eba750e18a76e382acc43d06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd3dbe7b413558f08f586c7da6e6578d5f1ba6104d9e0e9191a7c5aedb54cd4a424b2ca9aa38f13233dd7b3f4dd673d03572dce4aca06fbf981c52c189654dc91	\\x2a896bbd0be1e73b134bb308fda5a98eaf8c8cc553f641b1091fdc256750213d379820011146d03e355803b960d8fa955b1548be177d1ca9b6d7a36c28000704
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x04a3194a3446d41021aa4d0a5c339b1e5adc430c7c77e75e2bbbe8204fafd077edb5d75fba06c602a7576fd4a39927f4b24bf731a40dba8db7bd00a43197a7af	\\xab0d5e2d067b1d975d9d567dddaf1ffdcfde95aa50407d33d38f53bc731047ed78d82707c77a11f55e8dbdb164c173fabaab6e612e60f0db51ae178cae551f02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x52957b1c7d69ba96921513ad3b6d9c3e43db051df0fa22888d6f90d4697232adb5a54abc57a563a1d41762d8bd32a36e4aaf00098cc61dfcf1095ea357222501	\\x229b3b34f9104553c9c82729dbe01e62ba1d3408d5d3e4a173e42c7cf86a9c063e8caeac2f9c33dbaccca92bd60c64e6f0532d0392579fb52e7a0834175efb0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x33dff6b7fb2c96a75cabf2df0cab9310acfe9612725dbfb2ad919732469267e1740cc392b6bf370410c89e1045acf25bd6ae61306144517f81a341fbd9ff1262	\\xba0072619b14124bfe206656f0eb55f0eb30912baa05fc666e68a98c5d767df63826851577d38a33f27ee7ed40755f28f82778779c2c2c87634e1d2543a0850d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcca69c191adf990274b9757a8203de262759f9922226e5c8f696dc1b1ac15ed566c3a2160b7d162a6bb3da1baa40027aa84d77841c75402346598ffc224e64f6	\\xf35e33b3434fe781b58befd27ea1d2f3caeb594666037f2e75576cb2ada80eaff9ffcc460449a51c8165ba6da78f3327618ca32c0c3b7514196c68ed18cc530e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x961bb935e7a338154aaec01b07c3ca1168cbd235bffe4b04f90ef6c780bfdee0265683971be3e8e3e97fd51161d5bccf5c70d3334e888d2cc5f39316910a02d3	\\xaaefa2c4a6e70ae0182c7d8e3d589ac44a67343ddbc3dda4d2ecf914f04dafad78d6de3d2ce3aacb5c3bc5c851ee32fbe49bff38222cb86432f5b52c846d3f07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0ab648489b2c857bea4e9b696644a3c2a09deff78e9c1461ef6b2c911feaf29a8b32a956bc9b2731a4365e44c0e2687c06279a405931cd857c67de7539ce96ee	\\xc75b5c17d67e8268cbb6093a4488ebc5c665f23bbedac129ae6d93d1acf9ed242698dbcceaf6579d21645ae88dac0a5894e516874fc4d4362e75f629c6b4df0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x427c178d395ddbac81c1218acc5e9130fc24f76a2487a121d83aec0650e4a0748e74451559da3f0e941f95291d99087de3b34c445c1039478f7c7cf3cae036c2	\\x67f12eaeaa88ef06fbb3bc65d45aa3b539a724297d60db732bf67eb00ebaa90221b042c92638a3aa3f114c0093a1457b66d16a26bc0236c8043eb1f54108ec0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa48114a42d6fc428069a9114cfee4b0cbc52af4b775524d3a2fa99f31c0eac561f905d47b968057ddb0b29c6b2f12191c424fa0bf3ed0b70c8fbe4f3ea2099ed	\\x3ec60853d86b71931f1ae8810fedc4e9d96fa34a5a3f92e61da1449d9fae8dcdaefb6c27aa5992eb6f70cfaffaec116c3f4cf8a5cdde404b01474841f16e7903
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xef4942a7764dc08fde950af298f284abdb58c6312dd9ddf8d8b579ddc883cfdbb7ee4bdb7362cb51546ad81ae6112c2a84ea5c092026638958521bd0b0b04619	\\x67f2463574e61de0be2947846c81c4716fff0e90f63aad51e436670bb5dc6619be214bd0af8f7f82455c9a057bed098379b5b67cfa52d25b2e0e86f9537c9e03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x13d339a6d7a073e28c4254befc0a5ff5236fc18c0a99ebafc28028780de12628dc8a04abf92e9af6dbd2586c109af73c4c00728e22fa07152ea194170fb8dd83	\\xd0dfec0c2738ef6bbc209338cf8143c3d53ef1e8d9124efaff852ff5acd7a2c32e7e7fb3fb1ef5004e914f83b16308bccb6206f88bd6c3bb807524d2b6f9a107
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x04be73eed7ad2a7e1d5ddf5d5da8b9c77b8f79c75b5350e5ba31ef379deb72aa43adaf946a6e4d20f579bfbdcc51bd649171e11f7b474f6626c407f1b44a4840	\\x3a517d6fa2c98b6e54c251add80b18775783a85ff797ee245623cfbcf8813adc9bb52ad1acfbc0e04eff17e83629680c93cd6d7cfc2e0d7eaf4af7b910332101
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4edfb762a69df67783ed09b5845263f5b45b0d91f0ee92c68f3d675f57b15656746a40711f10bd0daa4e9527cec39ceb934658fee6834be0a0664e50aa7047bf	\\x453fed5db2c07a841ffb5c1665c40fd03ebe404b7eea65866584bc952071dcc125ef4d37ecd0466feee4ed1da184e1832921e449037ec1ac638e54226b23750b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4334e021f537bd4c9b81af1755ee1b4f0efb7215be2dc6887e9565c4cf89623fac75e0d850b2300a20379a8c6edee29ae1a517760ba497486b31327402007832	\\x2f9c0fd8f93894e58afb8e64d52282c5806f550abd5dbc1afde272d18baaec32af343b0ec84d5242f00d52e489a162469f270019bcb1d694f7710540e12a8f05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5ce96e733f439b901bc80c1fef77f57228d829bca552c038c7d066de617795e702391f085d22908136dc5dac3a1aa35a944f8e26ff51f4b1cfcc4d6614a6fa01	\\xfbd298d60d2c70c6c229450accc095cd76a34d4049d42b1b6b5756db8bd205681b0e3191a2edab26f49fdd1736d73e7aca570a53d5c2e531789e2285f87b0f00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x6e8d40aa00dd9c7e7fdb5439b106c42b1b03d9b7315050d93bbaeac145a99e0222e4a22a66442156fec76bc7ce768f5f047d20391e046d89cb4202381162a00b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb4aafab63e306d93d27ac0d015d3899a73661e05d5e502fe68a52a4ff9ab831c3ce18a098c6b03bebfbd6174153eb9ad013e7ff751e6881698ab0f377ba800b4	\\x70d7c250d3ecb0e8e675d1a830d14ac7709fc5f55e68a4060a1dc6f4070d530c9e94aa40903b5b18704983120590ff8a48e479db6ede565cef1e9b5d200ddc0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb3111d09823a796dee09d528e93b274185e2447ea827ce88bcc4215373366eccae49696aa7446548c5c5891709887e5730b32ff80500941c7cfd1d5ef9a81374	\\x6ed0572d6c19ad002422a62aa97f9a87d173539bf8913d20629d20573c68d924a5883a7bba1a9098893ab353f84fddea961d5727c04ba66408cdf8b056c0fb05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc4778d1858b69d51cec570648d3ec99a2adf612dc38897f1d896ffe84e346ebc802ae37b2f62325b999992453577b416b5bb26f11acefb9fdd5bee1622a63943	\\x97c2d52ee84cd1577d6f98195f2f311fb67ea2c7439ac899fae11134fb61e304f77f1b23ba887d0eb00a708a9a618d31818fe9bc971126b7b3fe67511d943503
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x36f43d0b0170b005d246bf7a00031ed452130b88024185ab1381e050cf9c3ee5d9a84fe35b180991e5d0344a083a65a178d59a6a587686716d37e8c4de9d57c7	\\xb7254ede5b6f213a1ff9f698569810b475edc3436998549162b3f42040e4b7dfabb285b6fad240b1fee65afed2e2d725e25b5fac602210800deb016510684702
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5797392d9b68d7e9c4a0926b1a414a5456511f73c59a689c169e6651d9d4181880fe311f981874bd291a968bc099ea9f86d105ec797662d7a37f54f46f817f39	\\x76a15de4aaa467d4235d50bff2565bd03330a55ab6f7940e7a5974456888554f4991f42ee2006ef580d3a5e9f6ea52f2e06aa5de040ef47888f5eb2e83ba6407
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x70b488eae74a448de3faf99ce9d8b09f1311c40319afc710187ed5c7fe38d4a95ae5c5e9274715fbcee518cdd02a47f945a29d928726a13598091c63fd2fa472	\\x11d646b5e8086df11a644acb12c39b692f089f11141d94f6d5c052f8bcfc675ea6d3fd3643017aeb9c0ca324ba7e7805ae85e8d09483d697ba70106c95972309
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd973e0c19459988d05e4fb198668ab0cd611b6ecbb4007af390c4395ff14837eb5ea7e2733ab0b2cd0e34f91bb7af83e79f3d354b7e670230c216087c5e1f95e	\\x830a1d78bda6eb4aa7c797d4bc43547c8b36d7f5ba08fcc8de17e14e4516b65fab3154aac67037925d870ce97b8e6ab3634eb75a3fba6efad07de8849005770c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x007709cf389fd1560445882469e91059780f96ae95d28c97c921b853ba29fcb786f986f14812cb054054b591ae07b92ba04e6275f07fd1ad0052df308fbaa706
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0283612b6cccdd53ecb165e9d7d8a9d8cdd670c8f2f2ab13389cbc54d4c15f44660ec5b20615865dabd40b31b67d8df40fdcc1db430b9a514b1a985d46a4bab1	\\x8168579e71afc912de522cf0f78c56877ed55ed9a4d1ba64dd00a9926a8f7156046a9b1d7920c77dd33c58f399e4c422931271f72de055961a47e3def7bf5100
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4de450715fb00a2f81e76e13a192ff6493389968f3b6dd8931d6ae950df48926250cef01948bc91742487f6dadb2d787a62b9fe33ed77ce6341737caf650838d	\\x7bfdc706f42c208c38e1287721b482df47d5ae47da845b41b2923d8997e62a5ecf1499f91f4a486f28b9206a5a2a1a11a3c49203d9eb9002c56c590e0a327c01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7925a82cd33753f9d65cc5ec4d14a518445966729de799c46fbab608002a626be29cf35c1d3976a018edb7590d6d9975449053d0eafc45415cee3f6eed4a09fc	\\xde0063431d78a6023549dcbcfa125f2167ec7443bb334196d931b9d1b415cd69167db6b591eb62e9768e3b255a6d6c8d4d2238f7e6318684c9280318d6a55602
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdda3dd78942970dbfbb0266a5fdb04d59252ff122182ec372856f0c6dd9cf1038eb6a8ffca716bef08009190506c6ea61c1886db274a5d3f1e2216409d11c21d	\\x052f396affa02d1bb833f0982ed8d476daad97f0daff2840e1ce457ef2f6b7d98b58edb898bdc7333df26f76446bc2a307f1f449717fe358ca7fa7facaf7ad07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xda02889e79201ef6b476febc69b70fce77965243775ed191f004e8822cb47ae7c07bd95e1d06b2d4cf8978c23550566754b71939b85d0b5d55597db74f76074e	\\x7b4d11a5bdbcb61e176e8f659286a945e30ee5327692dd796a9a311d196cbb409448da5827da4ea39754251fe5c0e9c615e80dd1f7e8494eded1a265872af30c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9d99c76961048552f872d965d3b02bd579a70de11c28e46e3ad9bb3bcb5139cc2876fc56f694bd4fb2effb9afbcc3ac28a6adc4ed3003035a57b6e05f8aeab11	\\x0fb2239ae7f0534e6f1a389f850e69b1e60d75af5215ff29c1fe7ca8c5a1b93ddb819d84c8a7d1b46b9ccea60aa9ea2613b26ff985bb5aa86a712bf9be6dba06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0e076325aa680e3e96c8c720cedd4130437cdf4a9224aeb5bc3aeeea16f0aef2a2e9ea0ec31d76fb04c4238cf5f590b876c82807761116c7c06a3ad90e0a85fd	\\x91f87f911eb1b757a216cf34f4cfeb0ea1543b64b81cda2e2f92b373d352cfc048dab6eccb4f7073a59d61c631ce246822e17b3f627d792814121f05bd075508
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc4fad9591cd987ad99a8f0e5e627af8e668dd88afb522d327c0add4244b6546cc8679b36dbd7fea7f80dee765d8908ea07453d07fb02bd31d5ede2c4bf124812	\\xe248a5927f005dc7506721d976fb578ef92ec119a2a38ccffc54c845fdfef2c3860466126c5bddcc227651e41d0c1ef9657ef2fcebc72f734393aa798755ee00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x93b79ddbebc81e41cd773a2f75199fe59b17c281a158eef5e44a96cb25af8919a24478e5dfc69103c08fb3af7ccf07dba00a08bc41335a1c88a14a508399a2b5	\\x001bdf66ef2df8956bbcd719c1819875423a5e264360a88454a2052991a0c447bfcd9a1d868d39e01cd9ec3957bcf16f8f5a2864b9384082bf1dca07f0a3190a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeca68e13a17b16ddd2fc668e2f92beab269964649843f85a31ce51da65e1146962ac490358c1545aff67df64c3c50c4f3c6656f231158c29cc76cfbc2bd9d4d5	\\x12a4e7fd99c0ba677668914cb26f0b71afb09ea73d3a0099da090d1f451804ee79c82836ddf48d71cb941986342ac5789bb4e0d2df4491a832d4446cac36990c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x589e086a41f38989775ca1f48c29be2d769d04b9b5a26c1692b8666fcfc1ac67868ba19fc264a10faf5665f3429dcb8846628063bda05d3ed590d8e06323e532	\\xf9c000b558590d02010db7123af7e74c92965d9813daf3b75f9c83c61cb5c3c6412ca99656eef8a7e73d90c23d2c3c7802e6f44acca72ad9d8bbacdca2014107
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1929faec32f3e8d56c6111241ff8210675e33f628fcde4494f1521de07c8743ee6c46fb84de90b94fec0ec8ce996206f505d6ebd3586ec6b904fcbbe2205196b	\\xb38626f3a8d7a990ffd3080ff3e7686192d5acd6c3a87bcd9b1cf8f2abf53f1ebb7e0dc2a740871263a7edde396becfd2b4be3f7f4e05335d27874e8f1b2420a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x133ec2970017d3f009d0664de94bfd93188076c4a9cd09b2b65069a221c31fc5ae890daab29e52b7fcc154a6c57ee5285d7e2ebd057ead381995f4ad7728235a	\\x8d6f059bf3fa0895c35b4349876c46c23fc862e93916b91268001f1ec537dd2a05b6141214641313e9b837a05676cf7d3dd8e4fb7893b405b75572ae60addd0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb6f440ce79f0b6acf0d02bedf8468d633ca894c9e9b49ccac91986d5fddf838a7c0af2d6c0b34b3eb772d1cdc8e783afd6f6d840dd13f3b94cfcf5d6a5cc7e22	\\x7d964ddfb91f44fa0e1f27a8b26d3d49e459ea3bfa8b2ebc3fa1ddc2d5046be915080d2fc3cda2ff96463db2be605040aa2f09dbcf91b4cca74ef26e9273c407
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf2550af57c5a62f515407d12368d59c09fd2e6f469637d55c76d8c0203ccf1adf22fd976cc0922f74470dfaac0e7bd694d2660cef65948bf2f16285176379401	\\x7891f880f0fe2bc8e032ad8a803c5b7dc0d4f5ec2fce661b1ccd449286d1f5d84e12af258fb4431f5d24ed100489cad8660a6d9636781d8c73a27479aac7260a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6b6c6e3a5d54cd9f63bacb40d0184713e2677f035a99520eaf1db3adafe691c712f54b741de721240c09faae2a9d7b0bc1f89d991dc359cfc2839d00ee968f96	\\x6b816f8bdd29bbfb68476feddf1942cd94181c066adb89b6cb47d9169b922e3e6c20b514d2a25b4df3529b7550980492d5740cedf2d3ebcc626e76b90efd4600
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6e3c0662f611038a9bdf64adcfdf4948226a34011df96fa569959258fcc356d8924ae403d21e633127021e85c56614f4e9fad969d5c70753684cf9f4e63944d1	\\xc2cd6c4796504706d9b51ed9e942cb5c1d4fe874b406a8c6e9f560a01bfaf66a58d06fd3cf8193af21e1b4bcd29afe3f08e058057dce3ee6699dd475a9d99b05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x81d53ecb43dc3754a080fe32354c707972782d12e279afe73a6708c6fae800a155ec4435da5b3cbb3080b0c7ab46beef2e20a073343e3ddbb859eafe31348514	\\x9b11b653190c20ccb06a748063784d28d4eb25427a8de4145e47ef0a06a88d9f0f0270d0446becfd2fa6ee24164664343235d6f0bca5345c68d30e8122ac7305
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb8c4b7b3230e74e9185d09b123664eae632da445a5ca28f1c703d33bd3cf1dfcbc584b247e358e93e5769f6dc0f55711866099853cdcb7203c57aa683d9b2393	\\x82992533fff328c9fd77eaf5b1d15892f3a7311d53e60a9421c3e4327537150ee7cd498e653bbe08633e8755f80c03210345d173d996e253134aaa56db7f0a06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfb8076ee41542a4269c11c0b9cc5e55ed482f32b2a9c6781f683bd103853411c05b2d6442151f9ea86d29b5a8bff4e77e73153abf03ee771682018303d59a40c	\\x8446205db3a949d28fa080ab3e27fef49f30a11f917204ec79b87d9aa21341b75a92fa0b57a3a6bb36d6477eab187423ba8941c0ac61bf46eda3f13a36ba0d07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\xe8a278a1068833cd3846daf7c41391f1b1116768fd13371739ea9fa17cd6c3402aeba84952a6292041593fac40e4070b17cfc40555efae2d753a112a3809bc04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x618b72ea2325de368341159ef58dea69f7f0fc7dadd0c8c44a5de9d6337ece0380074d7ff4a075d8f066cd22115fb1aaac8638823dc25cf9652e9679cf1f1310	\\xb18d674dabc04e80f59787f3b5132ffaf30693702fab3f43607ccb540ddb9969c19c87c6287f0aebabe0e403b7ee91b9950db99151240560eb708afe5a4c7f02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf6f2a923c9db2bb6fcc9996f96a93696eaf1c86878e59d2f94680dcba7b61c19309fcb8a93e9055194aebb8bd2d084fb539c4ba6c7ce66bfb8afc487aec90fa8	\\x94ea97d6ff620e6c28522eca766aafd140fec668018785d3d780dfc8448686330d2de5ebb057dbf2e274d74d9ad183a3736aaf3f5bb5709bb8fe619d200a2a05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1dd9fbfe1b673b74a4c3e5377991aa166d8851e513fa893f39171bf0c8fca4fc111caf8739847375d0b17b92eb1388d2376ce56bba3c3d795084c2e481d494f9	\\x3a2acc4f5a9b2d4ddd86dbe09343cafb389b1c78609bf6c4e3484563733cf90b7591bb59d084f6d92f6a8087343e95858edd92d431dde906a078414d56748107
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x284da7017552a00bd09ed5f96d0c5b02a09d83700ba9864994635b908a8487631c3fd479d6acab6f29faa963354c3a1535a4779ab5540669fada0ca2646abccc	\\x00adb26e2ec606fca6353f5f9c54cf664311c84c44ae910d278d1c4b9a6c2c3a3717410294bc1c5e9a4f8b10b7e96929b412b1c6399794227708a8972fcde401
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x50da01812dd84668ec840d45b7d84424c656abc7c584a3d859a7d2d505ca1273fc3f674c5b20aac32be5c307e45093fb023d9a20e21064c5c68dfe3151f65db0	\\xac1a60f881e3aeec7eba52f381408b2e6f2a86c82dee588dbb5f2a9790f5bf107d11cbaccb55f2ee3a98f1e24850970e54e9f59a607742a2737a1d72939d5f08
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x213c104c95afc0b4c1801c98f669a79a4636afbd394841d50559ccba16015ece14ec449053cd944d027d6ced441d8f43973f614487da49064360f3ed089533a1	\\xb4f25a9e30ad94afcaf87dbbb87b0b6dac5c6a73eda1b7732e54739fb5f0efdeb0eb39024ef0fc93fe3f9af203f390cbdb66e6c4a3b3513b98e4661d04cf740f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7e524ae6fb8f477bcea3675267d40379c304e04d345d0d2780bb0fbdb9fa64d55406a00826febd29cc7d57e588367698493f8d93339a866274099475b6c5e034	\\x34f56043487af20f24d5a16e555dfe89a1eb37ceffcee505de1291a280f4dffa4942948e5a3695a800d26f32f7d3ba0ed6d3d42423fd18e7f7043f6b48fbf00a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa99ffb55105bf0e9da366c44c5b364a4fe9f683b1a4914bfc27b9c6125750b7d9532bfe60805fb0b5972316b176f6f6110e42ada9318cac2756335de00674300	\\x3180030909154acc8d9aa8f6a0e8129eba7f725a3a23aa9057cb262e195160830804e2c41d6bb646803001ea3220f675feec93bdc7725f2c4fdff08c4707e305
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x1443fc6af4e2d558af23b991fb6d8c13f9c6965a1e0c778f1ae588359160a50d3f52d765cc87f7a93f8421c8b704c7abaaa35760069cdd3e31f864ffed8c53a8	\\x480261c05d43ac1a46e29d98cb113bab8f1356710b7e836c8a6020d521fd71e85ec5c5556f9af01f88ad03e99a569e55c629ba73b91779ea5e0aa4a856901d0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcb08cab5a396b5b335c10d7cff080bdcabaab79185348d76dc25f2774e06ab172724df90d10f869f3635b1290a476a0e4eb2cb933cdc0d65b33235fbfd391ed9	\\x9601bdbb8a3fbf047cd23cdc8d56c3934d8364e3010bde70d5817c2bcc25e8b9d8c1341c13344879bcb864c493f2452665a848f058e7641c293c44b79700f60a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5a7e889b0827806d1cb0f9fcb24298c37ce38e4ac2149ad9e398e7738fc1b8fe691d8f9fe8bc51d6500cbf02805472368b6921c166b0c47d647dbdb4971982d5	\\xf32e51cb0d7a1d4fa6d7eea5cfdffebeb2e4504e07bae7971eadb8f70579852e725f7f3ed2d079698a3b7307022e1d8bac1dc2bafa431ea4c3dd854e80429708
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x06d74f1b48c6fa37bf1d7e67fbf176874c062f28f8152132912fe52d044b22834fc20fa4bde9bf6db127cf6537e1053745894e5e377663f410d876520dc972bf	\\x1d0cdf31011e8433ae0d765c3dba0acbefa43d1ab2740eb3714bd0d3ea595da53493280238b568a458c457ae7d407a37eec1d9f7de3e32688743c2681edc100d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x553caef6a3b84e3fb4dbce940c35457ef96c970b37e2d1722b9e84d58594f6f9f7aa5fa2111784193e0bc5c0bde201f07292c4ad4792a0ba895c2f28cdb110be	\\x6655ed3debcf387b3f5a51280e0d5bf818794897e073218f10c142207386446a8e50bb454cb818bae3ae7c43cdad3f8279de2bfd3e78ea1cd3a98d0521a99c0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2cc5a8a32654961e237449142bcb7b2e28e5ec6ea0513a8537fa5ce6f5b5de94d59cedb045eb78cdc0e846833260d500e8a38a8061bfeaadf17e7fc65b3d3edc	\\x16748e07863cbcebc4328f6961c7d105d35f0b3a5c534f3eff0005d30043bcad951526d1af0d2b91795e44d5ba22de2f157cc90ad7135e261917b82e2f395706
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x6b729b17f5a6d07ec32e098747fa7532b5b0d50883fa3c17176d9be96788502cd811a5320600c392a7b2e72869d1f048dea901f6ef77b82291613fd6d209df0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xaed68f4fcafabf81adc061b91f4013b2d064670e3a1536139945f91c1d081888d26663103a68e9fb46252609a26dc6f9cbcd72d98639363240ec46ce6bf8cfcc	\\x74733d80622c23170494a12c26153da47567089bfe9c52d06081861518e226927b195e7cf120a77e57d7e884a32e7af4b650f1f831e1326cf74fb3a05d3ae80b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0420185c98b5223ce50b04b31580fdfd83e4cd1d8b940d33c279ba2c0cd95f64335680892da77418d136757d136043575568c0059322312369a924bfb313dbcf	\\x3144e88dc52cb86aa9128dcde84b12d8725814403c61264dc7203acbffbabe5a40263390a679cae8ced8c3c7cf9065fc9d0e47d230b2fe83774429943fbbb70b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x63284d72bb0911e7fee88cf88bffc7b7314bcade4af138013bd6522bebef27383bc4785099739210181aec7e6ae33a924cf025758d3be767f0de2895713388f7	\\x2747d4f2697a391191f4b0a2787804c60fba8d8b789cda3456fd05346f147b0163742a606c374faec6b2258eaa680656f4521e15dc8b790e569500b316c64d06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x48ecca29a070bc7adaaeab8f5ac0dc9c8a82076283476fee2adc5ebedf0ebb2452059476a7f5ea77ab71a69ed5ce184d0e2a154d25dce17d9e3bac95e772359e	\\xae9f44560e82822741eca39f16c42d1a508aa17d252b6743a65fa28dc49065036a91851f55cff1d6f520fe4ccd868a36a710b5e17726ac811bb7e3ccc5df7808
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x13c784cc892fce96244d3385b595785e57a54bcd2ad2528b6b6275a84952d945bfe5e920662c4c5120bbcf8ec6c5b8417659aa9a93dc6d07b06daef8004623e3	\\x64ebad72b5d572520db6a055409064eedf8b712af19fd12a9f568c514e3aea3167b96df25bc0a4fbd3cb81a8a22a7b3c9835d65e230c600f3476a77f1a47dd04
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0f032834c78125b1f9889ebe047a2b3506b4f09e18db30e9d906f4ee4bd539460e72f6cbdcf93450bee72997dd309645a05390e832487bf70ee1f50cdf171d8a	\\x595a56969270f255f6e5db5ae921e19eeb16f1e7215afbdc8a56b97b803c6008ac2b86aa81aeef53594517c57ccb2568af9e06aa5422473db2ac52145887750b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd653d251bb60598f6b9755d93a2c691730c51f94d2cebcf37b72c41f9a84a33133a96edd2a8c9f3418a4b7f1741bb4faf3ba7438f479db1a4b98f3dfe32df466	\\x3583c8deaae7beaabe5d8c25a74acd2355532e0163a0c06c2090b57f11826a01ba78fb63d96fab5d57b1b3ab2aaca9b193a042cbaadc20792bfb5f5928033b09
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe61e3ab72831e4f4a7275b7806e2be3e75275aed375691a5a470018a6a7e86e2a256cbae509389c2fdbc3cdf7e165d1d716db9d6fdb1859e66ada532b33cb4e7	\\x8ba54d79e746623b2d80043cfddd44d21a8bad20a09c024b01cc71a7ec6d281fdd1b2041f8ebb9297ac57cb1521e3fcd1dbbc9f9aa6a15cb4d9702cef20f9c0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8438e7f3ff3a9ddd2afeced690e8d5ae5e972e4a8a7e988cac97240277a2fa7aab305514fc10d9e23fbc6e4ea812ac91e54fa79abd3cfb5b43d2924049b37f39	\\x7a810b6d495d3501312ab1592bcaf775e3b28395fc2d692fd03597e72bf6477479a9075a67fead17cc3a20cfff76788217638894b2f09eadd770266bb23e2204
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6ae44c5d9d1da3bd1101cb959044e049df6c4ac15080c4eea6c6ca620b85fed356b87e5a47fdbbe7626dbc179fef0da13a51d46155f1adced76fc3ad39702b7a	\\x950cb5cd0bddd2035f202551bf6bd59447ce15a573793f9bbc602951c7088925db6caffea5d365e802ccc2d3f0ed2bebebd7e17b4ff42977ef76ef1b44965b03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbb9289a933525c6935d7d6957b7b31762ac374f3c68bf0e1c01eb8aa9eea65f8994c368e20b4e862f8f9c3751958a806ef4cd0f46d6fd26e2b6a817267eb403e	\\x64a0284a9150dd68cd0e2b25549856028c9c61ed5f8000eaf4a54b5ace51ab77767cd19403b5efc9e2704339657f18249d02ce58e130ee335a1f68c5bcfa050b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc83a411780341aa78a17b56c9d62dd7ff111a2134a72a4f881f31cf0529616a20af97911c2704780029866c2efb3ea79f48fb15abcc9af4f94d89511c0982490	\\x1bf8d531d7800bb969409b9fb8a7fea864413ff53d930aeabba794f0da36fff702a6782731619d2a707d29706288f83d50ce5625e4c35806f5ef7e611b6e080a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x74a3b770134f83602ea2322e507c723ef139ac016f254cf8eb746feb928f25f2218b42b8090757a9831564eb9ea8e2041c1385210ae55b1ca423fe2df963486c	\\xfbdf6c2356d2f7a42a222c052c5776bd3218d2d85c534e2d83f533275926dc5e6e6ba60ef642bb7ef9030f5ba81560f4d011e34b154fadeb6a5d8b359fe6180b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe6d852cdbdfc2e5cf540020ca37f56f1a70ff86eab47b511c34ba472767c10d108d3f11b97968db7431ca1cdc581da322639e125fcb89bcfbfe2e3287f919f28	\\x773f970d97db57a2fb8d3f0cbcfd4a1a575d2a8c5218203f7229462fe5e91f588cf3f2522660288bfd897e2c504c99de9a3721d4c4a26569b0d048911677d006
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfdf9e0d6d3cddf30dd632b4a1ee59027f0eca851b048c4d356be1d2b2e3a268f751e658fc212b0262bbeba25dfb42ca075f0da9a403ca88e8bf91c4f8cd53e42	\\x4c7f5203e36716d0062463607422ff341168ef92eeac332655e4068a5dcf74dfa030e7f6384ec27749f1c1bd0ca1a274208bfd00ee805e701498dc04668ee90e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa1fdd3e5f12d4e0ddb52bda74ce1afb56c0886448939de60fe82ec48a683a1e74b59dc254d0332d76af151eb39dce3223ce7dde01f28b66f8dd66ad4478a9dda	\\x91dab6d49564453e667fcb555070412418d59b850b2467de7b91a5204fff0e38d3b65f76f9267625204e9b614fcc63b1f7bc5978b55022b416db93d139d5b702
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x177ac26e0df04c9c69f9d472ccdfd75fb4d1be83b453e99ecc54048405d337c01ed9d29d8cbc2857bc3f04ab86ac66094de82ec6130546368f853cf906637ef7	\\x57fc54fe7c33cd53dc94fe2049cf51e39837c90f2376d06e88108232b4aebb6e5ef0d791ebb126de4196b7a7ca07ea8684cc7b5d1d34099f966cc9d83c904206
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7424e467f191e09f7c78eaab914dabb747858779da66af38ea8f2953133e325ca195d6640a04a87dca74503e2e2e2d6f56bb90fded199ea57f94c4100e7ea7e0	\\xd18328df0f50afd4a036b76925183f9b4d047e3259cba4e4ca3cae0a43c0df0679f4796db002ca439fd5db8f5653e4df6cd8657d334869096b42f6b476708b03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xade9ccfbc8b70b5f40efa5430b7354f82eb91b273d4845eb03cbf855e193f77e1b479d40666e5fc13c9cf08686f6c199da4cc1e44e9452a5ab09122fc143d8a8	\\x7c150c790035ad8606bb2641325b5e4313e632a69cf416de50c4cf9a53de4f05ee03015bfb9a7a15b33638c5514912afcf353b3090cac3318a93abfb08747805
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x58e90564a5ecc3aa2a2e4dfbdbc5b2435dc9b0afbbc56a254f3615f56564391133ae55177a6e1470d227b873d4462fe60805146b60aeab29753d1fe2062b4f0f	\\xe6ad52bf7752f49f0af7bcc3dea133ff00b73e6fe3bad8c22ae40faba074a55da68e3a77db3109238ddc0225125ec1e8d362f74266b0b35952f80bbadc731408
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd7af30f43eeb5b3c426f8c1cedba2869e9691d418ed4097a89a2debc1b8d1f4f136669740cf27e6f1ae4513d97f2b52c74c07fb6f54cd13d3fb0eafae799fc9f	\\x562f84956026ecd3b1d6503c7817331d9893e2c366e517b2abc605395cf06094803378f0fb1dff10f8c42c64bf0603d6c92ef7094c64d9079567ff25756f4804
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x4d67154c05b5a0c739f75ee637b4eb5e2f3409da81b317ad5069a69a75140be9d5330b466c235eb99a0a6c52f8cd3d002f4cd3b1ee43414efed92a9b6206cb71	\\x9f04b116e5de76513beeeb355e0bea5684928c3aa3c0e8d8bc81d5182dd7509022d321c40d7e853ea68e48f8489422176cd6e77f70f58bef081c64c378e7c403
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x517344f9204573e9cabf57e8d1e3da2bbf60747c503c67538efa1d08e42dfc49eaa9c2e7ade10a4e1f2b8ff7e57220bf977eb9da025283ed62aa155df8a1dc82	\\x8a4ea73dee46639b923ba46ed0b0acdbaf0e2c20826b25aca5ac66a752d4249a9cc60a3dd779e68b42facd48daa09415f81c8fcdb9ed1b9cc21fcc979fdf3a05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x337986ced9f37d9853344be06f91a501b50d851c0acf0d3d2fd243be4fb717e1ef876cd46832d6b5bd42432044eab3affcf17eaa498e413f0369a7f94b511a07	\\xa48dba3f436219c0db83459b9c2ac11f5db71e18df2af0ceff9e523e23a9ecfb5ce502030f57ca0611fbb8b70109e58e3974b0535751c5b711c40b62f5e34204
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x660324f52d44bd04f3811984becd72a87dfbeedd68b83aeb7090444422162486db734e260433812f50f124ff58f5d1e4f9abdb8b64f829fcfa28e08708277757	\\x59fee9b5e26a6227f16d01a4f11633a3f111dc54aa77a28c4110291661b269036cc37b213baa057a2ad56df6cc36b7a020cbb492d3c16f5f1bfe6d8f60d5ec0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfe50aa68ee44a12364bd7881278f6bb875bf01f7b0c0e84acf8832f394a01dc08e8e19db2222121667697c8e3886592051b43c50409356b8187b7b839078cc5f	\\xc801e0f5905d5c4e2197c2a8606c8f7dd0b736b58963a8d82282138125f15c687a17c8171b2fe6ff652c9c8db01e579029a1f40601ead5a4f76ce33197205504
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb25760adaee81a940ac0c30c343cebab915dce98cda830f221358cce7be2778358a70a1fa583baac1f4a5ea3ec7926629e49ee355da9573e6ee1048d4ad6eee9	\\x12a04cae5f8276ce500c1b46e532440c64071982572e550ccd0f6aaa825e05ba9d2962d445ce6e5d8e3f5d1dc32833302408b182362b09f459fb0d47ea41cd0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9d498a77e845f52dc24deff45123685b389b7a7ef9daebf058d2eb99bb78a4661391690bc29fc0bd6910157486f2d2f643bc3a2f9c696b4a38ef12af05ddee8f	\\xa78ba2a0b29d6f099e7036af10617ed4759fe8c5f761af474ff18b843360d2f24980b450306ac578363f4edc2d13a215f8a146264552aed38d8a9657d8199d09
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd25521b663ca84975e117cc5f1ec73ed970b8801aa741fe8a790d6ac2b7abf28c6be6e162874dd70df4e772a3e0bc1d3261c2ab0c84ff4880b9763488d963913	\\x6370e8a30ebaa48da30e2df32f336d3b765c875356ad64aba7b563c4468c9692cb1a5751537190d9a9cce22fa339eaa8cca64f2b299f8c188bdc390149425c02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf194bdacba4b4315e846dbada744e7d21969ad4d6c34e4042e7fc8ab7d6fcf5624a7a2e1b1641393812c6c322a048b60242b57cfda951459eb4a532bf95f4d10	\\x9482d2b1fd05a558c04f5359f1b409956cdeb12d1ac5ff5fc035f307500904916e7fffdb359bd01d2af4c862320a13c3ce9e1680ebf442ce47c63e0079569601
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeb7f7d766d114621f666a49a774dd332d089aa171a500fe5b192ae92de6d5107df2105af5c2b0a55a0d7f96091f7475b9b763d8aee86b1603fc343cf192c0086	\\x5b69b71058b7c28b81c1cb3be8d82ee5adab25ed94f31ffa4c881d70c8de3009e9275dbdc481060d86d70ad9043f95aab358b2bc8176e907f82f5a4fba838d0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf93256c3d78beebea7d116d2e797ebf64436e5903d8063345384fdacf0e2df18becfee13d2c112ae402ce39a83741b9527b47278221a18ddc9f2797d7fbb6462	\\x26edf0d76abf14a505701a4517d2a655f20565d9f86b7a77481dfbc0eb98865d5a25217fd13b08e8baf1ec1724790ce143a2d730a9515609decbd7485131170b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfd566ad2603f9478f3a2fdaac2b6dc295c688efb05bd95690a6ceec768e77d299f4b018dd924aa4a457d4dda44e3eed867de39258b1c3561c5729015b0edc3b3	\\x84ad76c06ee308862c636ef0a03589b3cad641178827584f9791d7f13daa064abe79bf8399772b72b8cf75db7e3296b5c2cf2fe27717ec2576fd8fe645afb10b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc54a02bac0ba0434376b2b04d67f22b3151cf0b43a65bfc546f068fc8a4338880fd4677354d28e9bc569a88fcb9fdf8dc1d7cf3a3de181f7d156e271769b504a	\\xe16f5e6604fdb39a0180ad554e790e7bd2c5e145310f5bcd4809aec3998ce3bbde00b24d1355544a27f65bd52f97a90ba6c29c731267999f33f89b116d402d00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x01c1b3e4415112da2aaa2b210395adbf916e46bba7f0e79f0ef20e241940a5284e85581bb930ba85d682a3b998b48c593cf5843141c50a2d35d33c71ef708062	\\x9423fc47e4dd1a6bc43097edd951adfa3e2bf04b495e3a1d8e8924b447fdac46cfc9ed07b5bb82a0e25bb663ec360fb71e5406b263c7b296d29d9cb76f54800f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeeda3a042000d9ddcdf95e8c7bc655dd2eee53d83d38ead04381a95e8d805ad38c2b88654ecf50d007a034fe265410d5aa2cbf697de9752a5c1e9158412f6ab4	\\xb6a724cd236507d0d9d7c9f687f206f54f9903778e067c1cc474024b69776a760d7a7ade6b3a6421fdc4b252ce50549fad6cd221677d9bb83f7536bb37d60d0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x723f6ade8d59d0bcd03f62ef6e3b332ae843746586b32fb5e75cc3778d50def3a6842716e4d07e061a9974b702fffd4a8c859928d8ed847fab0556f919a67434	\\xc1730b0b31b21a5c0e995dc96b54274dbca97b350910afc0da6bfce21cc90ed5bea1cc281770c6d53373393f469eda226c268801eed02b21d771065ee7a92909
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xbb287d5baf034cf304616b1c20e0e2d8e2e69776a7bc8d2dd42c4ca74b08d5332720049cfa50ee98c17d3cad38a362572930d8b5d2c333d8211293ace0def91d	\\x4eb0073f4ab8de185541f942fa949ba839b703136002f970f0e9e71eeb35a47432805c6d24aaf6ff50b20e465ed8d6121e65944eedf934a17ccf56dfc4510802
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3d2582bf46c7323e82d7e4cb20b5c5d857cf3c8fafc89b80203c8f61f2229ef3b5e7ae26252018724688e8d64ff19b8781762ead864ad1a33f45a3da419183ca	\\xf49790559cf2d7dfb01f20c71af58d76f0c0ef84c421ec4b79adf36256f8a4d6a65222b6b346691816818b8b8bd88c98d61d424f46845a54189c479fdcfc2b00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5a0caee9b8e20922fb6694d43729ccb8f6668f3231f714197855c0239c8bd6c4b0a26b5e3c382616ca8be939140f23c096d1d421e38c8e5d56fa800d4c4d48b0	\\xf537aef9feb027ecdc32b1c5d868dfdb93cbfc29fac55a6e650a3723464008e388bcba47561edaf0deca1086769385b97578a1e3460ca1dc986c75170efe1d0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x492af80d706492758daa2c8d6e53eebfdc13dfb89e5973030281fd8114f3123bf312ae77ad94e19ad0a5f9807568d4182e9e90bafeca7e709ab215fd2bff2797	\\x7aff9e124797ef88e1bd5d238db092f8a4c602fb119d0f3e2a9d2a81a3ee680bb91c3a5fc60a9884b7b86faa8203aadb5fe6d047e6f94233b048246698e96904
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x24bf05f7e3a935dd52f0055becf3e78974d0022f1106bf7a032368813148d7d4a9cbd51daa7f3eacfa2bc89a8b18feaed7fdbc09b45b13dc2c07d0c5eac38343	\\xfa908c9724f7792a34e65e01178e3d9ea60313be46e366c199c617cdb781900fa7cf1d2e1e51a229f9e4c396782d98d2c710def040d6889dfb17da3c812b6705
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfe6f3b94a556c321122ab5f0c97753820fcc0edf36fc80b3e43ca2fe0a852189b31d0010a6e0afc07a22872c5dc1010b0c8be05f8bd743bba12c265e12159762	\\xe83c128b12af89b72e503ca397d06175c2f265cc984c5dd9a769d54ed4f74d75e2a85d3f56ac9e84e76dfcfb01dfaa89152f389edb5459baf1c156aa5123720e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x44bbdfac1f7b96187c667513b50422f045aab734354894ef426f14faa373c6e62a58936d9b0eac7aebb12c3bbe7bc9abe504c58e274fff40b7e950c8885658e0	\\x8be5a2346b43154f78e0df85497ba27083d2519d6f67840fd727a58beb4f3ac59d0a055125ca911a6dbafef2a9962fa00970152cf5d54a8c2b22b6ea89318702
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6ceb397a20324429409321f9abdcb4c645e1d38fc1b373431ee97a52c8134c51b6e92dd4121c19380e924958e01a77b4a2d2cba6c6140dca8b1d3b32ba78754e	\\x39527f3c3e2627bfce34d23543d7dbbbd4fac3755f4c1105182c3a6e34f3527c019e5d87533ee358ebc7dbdcc85d30c5687694753c604ed2999795f0d0406100
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc1c59874ed5cbc9b14911fe88a93ab27ea2cc3c1bca410a3ad3608b82c89125aa9b43fda8c858bafc7ebdc5aab89f9725afdda1b77ef1d266586500e42b228ad	\\x1cafe25d90819576f3c63492432fd420355743c3cf2c4377c0f826ae16f08660605f661783ccea3527cb7320a9b983d59efa2e3d5d94e02f6d0ce06c92827400
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x01833c2c3866dee63d74ff546e02b4b249bccfcad6b4c7062d781e823b82b90d897c0c6b14029ed2df9b744b1aced81860a219f3367ed56835e8b13776b0bf34	\\xb019f413b80a459f1bdad36e14bb4f50954aa8e9a150a3844eac750d3a39481b271a02ad09386689242564eacd7534418c1814463aa57d4ca6035e70c1812c0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3c432b1be09cbac66075d61367945ca147f3bbc538e4e27f768bf8ac90686a6df02d2941123dc87f199f8351307e14458f53e7ce814e9d52ec3c8fbac531d2e8	\\x45b241240e27ec443c82b5ae17d9c9373ee55331520f3c307bb620b8b442c4a10f8a0c8d473aa5bcee6a24e15503be31ae1c68844d51d71d4eba396c2968fa0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf1e6cede4cffe5b61c8285c392d521303f2a2d012d1e18369e4d9c71a00b2445916d91e8a0a45bc65711723736b070b5129440003a08d9fbf37d5f54eb30ec63	\\xe546a1f6a01e954aac5ee472339a13d255b147dfd035566ab15702be68c13ad2ab897622f7d7caa2a5a101f3587145d5c939c071b947b8d84aa1baef2b175500
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3e69957373417801c1ca09ad655899647c37c594a47b1dcda2c3bcb6a96f9a3beed8ed1ce46024b67048cfe7dad2a6df72c9e2a0c17529b865f3e1562589a0c1	\\x34ca93ed88a7182a718691bd32d2d22c132f54849ce7d3d5c30a9ed53bb0605d384b3c83c4bf4af3010f5fc0d972a2500d08d67134e79828281a765a7625ea0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x18e78ea2983c1cda93724e9187e6c9ef76c6d6f3187e317cfd0789223130a41d184c0a31f6f029b2aa6347a0d52dd94130715ac1356e627be3c1db3fe2b30224	\\x2661bdd0b6fbdfb5d306b66c4ec44eb06f658ca9a514c49f962cdd4bcfb04a70cacbae55fba4fe5332d1372fa8101831732fc902991ec88bd35d2ee522a1ac07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe0c8e5cd20f2d3b2bc2dc8b8fc21b5bb5128e7765cbebbb65efeaa0631ea928f24db9a77e1027ef16c8aa2dd687d23ddba5f7bc3b5d31d7b3259896a1285b499	\\xf0ada97442fec5ad4a38c81f23606d924bb1fd210a168e61a06a952e2fb574eefca7a5cf18c080730cf8645c6f7ddd565dae2e7270bad1b0f6801f1d33c50302
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8c5a2f261ec3fbccb11a94a562844d1bf551ba95dbdf5bf36f89815aa158cf173f6eae0cc245f3f25cf8d5e182342b3899349d19d601cabf519afbc262603729	\\x7c1f889101b796af423400192c5a2a2336cd0bd2334808ce0dc8b026e447e240da9a61b6680439faebe37afd66f78c9e99fb7a033df350a137bc9af30e093305
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb5ca8951a0a6f919400665fefe0857c7a8a97c2ed7f20d9b015b8fe9c4227915af6c65bb1796aab8e9645b5d168dbe87ef45714d5816628cfb3a414a952d7aae	\\x4299a7242c8541d6cc18e88c43aa86400c5776bdbbe10f0b4ec443cb112426fcca03d84abc8d8561c4449f6ef343a8395617b6f21a2bd0d47740b6d03902420d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6c58a4e16e018839b2bd650d59706dfb91a0cf67618ebbbda8db56f855cda4c3aed10736c815d66fbef39e04241de910e409243f463ba4a24aba89d71be50a47	\\x5756a16b5fc91eb19cd8452b12f4bdde2cdf4aa938b286bd06930a102538c67db6355f14bf4e49b08900bd97044d4e66df074ceb285e5176824d71310d91be07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5bc5d9f7836c8c3d0e81286acc579f89654a64ed6d8c502b0969588f9986f205ed7e4c776cd784399a7c22ec651b3d240a57d99bc78cb8d4344ac80740a9741b	\\xed95edffe6034847cc34c442f343b625c0e4c7cd519029f66e407371f7f172f49ce4210b96efa93faa6fb1940c1ff1b9122eea898828ff9bcdd7a2f4a4587405
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x447bca2490b41636c51e88d7ec75f599b9538122c53bbfdf770e368238f3804e5e400e64fd65beabf94914eb242dfeb80350dd9be820db515b2f98faeec3e335	\\x9cfee7c49c09cfe517d7d6f179c8b3c0a6f0232357997500755498d6518d1ff336dedcd30960be3c3f6323f112171a27efc3ac45355ae1b19052a0fa7174ab07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9b5276985bcb1fbfe08f1d0988b8e7d72b7c802f21e0aff33dd64ede52d54fae744ed9d2836b3292ff7498f6e880d1fb92cef5a5627c9e732a678cd94e4fee11	\\x777663048040aafc70bf6a86ab647cdd3c3f4de5433a17aa9c7223628ffcb9594f2d767e8f0aff20b14ba33f403614c2aa733d1a25e3faa0e74dcf911dd7da0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0585af3695efeee7aa878288e40fdd1a3ef2d7207870bbc887462237be05b85f4b937c395b2a4d0d3b0ec5fd732e640158da6cf4d1ddd45171128792211d1360	\\x70956319aa67af26b28d30260c5b98195079565ba99013cad2ae6aaf642a5ebc675881fa1cc5a8d5fbb759ae51d12958b78a0d00afaf9fd33718ce6b01a8f906
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5f958649a8942207cc9139791128e3848a176dc424b6c78585909f7483809027b4d589b712711fb7d56226a1f8cd7bb61516dd50024ce2a6ca82dc252ced2c62	\\x0226f3a55ab6b29b06a31c1ff53a8c94eee67d9f5567e1ac1a178ca2d917a0473bbcfb12d99c422cf2e4887df17f9693e4f291b77d37126cabf239d9ea58930a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfce73d51c7c44f2783a9f8b2d5b1914876345020cebb1078f203e69f41a1d0d45cfc832baa4a90af549061ad1a5959a502c1c8fb5c041a4e31b8ef0563cae14e	\\xc96eba6ec8dac879b7ad6fbe27762acc0f9f68e2b258e0471f1de2ad22a77baf795e8f91c68cc7dca26ed59029f43d6bac2688c670797ab6e7f756c44b5d3a0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe33f8302347c4e015b95196acb0f51f7766a2084a1b7ffe2748e2a4e98409ee88fe7b39c004c04cfb038740c348c167732f1041b43b5c0d58635bbf6f3cde064	\\xd49ec87d9f4fff25ba51db151be2bbdf2eda6982b03f771a487b66e17ea81d5fb24f178c5bf31c9f0ae029ccff7526d465c633ec7c4d64df208589ad8bc85704
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xae31b6de7027130cb421d66d7643e33413a9c05f2b19dae1a0958a2d83b573b3e525452828ec3b2a05da1132a222d67dc006367098755b0710c44c0eacfd436c	\\xdb5726c5d135015d73a5e91ce5259fa68488a4182e4cff7e211141ecfe3b1b5e9108d54755884b5f2f9e710d7a1f1a83994b54680f6cc2c7ed56cf32dea6970c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6c68013ebeb06729ea0afc3f02b59dfe0713ba188711fccf72da9a29dfd39234448e93df4c50df5b2dfdd0883d100499e8037beecd82a78148b90b62e40edc97	\\x90c1b44860246850caa4bc5ef4f5b74753ab72f72599de5e863977122ecc8cd1b1fe21463ff14d6958cb1ecdfddd7b1a6681fa1606138ad205607050039cae0a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xef7685401fb39c1d6c3509853317a79055e97ab4d35ee228b700856c6edce70b00dcdbd326d9a8e86c22a276466781941b00ccc3b88096c1bcab531129dd446d	\\x949d4c98c818356190a82e8318811fccdbe65543be732552787b20e4771ea41d84cc896f88fe913c3d8bbd78d6af0fd524f5c14edac4f99df8c8a7fcb5d05304
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf52d6df81b5e5877595a92bdb369386af99f1b05c90ff1c780bfecfe6a6a48e4b13d3285c692e4a9135679e95f65f85bdf32e7015fd75b85b2c0cbc28dada95d	\\xb21b373c17b7f8578890e9ceaa4f77d2930fe145de417b7504f400bc5d8c9ae3d920e2e37cedbfbc42df59abd3d87c247211dc469f343666fa62821c844fcc0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb159bf84bc10e91466e31ef08caeb0e2a889254b5d8d5f1ff51adb5c99631ccd20de85d0a6198cd018b983aa8432c3f111108067e0d179f2d238d410d92a1732	\\x400abf494f993024415150594e84c4bdb81e1617a27b1b1868af1c47619f1dd47f1323825b43b5dc4f8dfc29f12c288fb627bf95ed13ee3a5214a9a9fc085500
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe24249be0b890adba81940ccc88e09fce0bf86f3799fe1aaddcd6eb2f8051ec8e12de5575a4a984dfd390b847b47b618e4e454e0d5092d878041dfb8e50604d1	\\x3fa5b9faecc7230389c680e9b5c02183378d7d42d2b87760bc409669f46d2574c9e57ae9a473e08f258facd31f5f0848d377175bb7dd654ea3de022261f1cd05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3880baa3cfe58069027091d10db39ad9b3aca625b65f40c796cb6fac0bbaf828827b885a4558820b069b845f98e19bdf8c208d336399e5afaa1cee6a4efe6ec5	\\x113b29c16e8a3853f9cc73ca97ecfdf3f968ecb8739312f09981228b7ab5da89f6b13036b37c98f08bf46b7ccc20c62bfd3b365ca81f5e87fd5bb8e5f1f3620b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x31812c0e0c9f00ab0cb6f10ff11b018f542c777a4afa05db52893497736f74d1741e14a4b42a4bf2d7b5eafbc347dbf751911af38c62366c7d9bc02bb3b37d80	\\xd0a87ec8267af63a8898ff5c0d67e3af7ffcabf7cf7517a023a5df7276ed377fe1689448d08b13e1ebf9fc63500b03319088cd5c8240927df7c79357b6cf0105
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x57ed5241235521fdc7157fc2d2cc40d8684016c1d58663cb2828dd19469f15c819621104a0581a5ab2043221675426dc028e4558ba30b5d1809042ce5d9eb154	\\x7d500032e10c982908d3dd8c9003d863ab173e0519c634524738e67f1642a394fd70e4552a566b495f2d7d99d75f74fde62581e35f0e634cd6e0b114877bc30b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x63912628677b5fa550181a68b6bea1e9b203838eaed6bfe87135ab3963b2fd398cc9349a177233dfafacc06712e4a887ab420d2942fe97486a850f0fc9db7ac5	\\x729dbd9d2b40bc912ed21499ce8eac482d7de7a6dc2c9cae1a9b6007312e627132075f4a1c6a5f34e7e596159c7e286122356551f3249fed3bedc304f070de0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xaf5b2b234b4852fe8bc17ba04f5d38e517389a95d3bf5ca93a723b931fe22c535befcb40311be27d8efe28e4c267e83f64d46fc2d83055cdbc28532bd86661c5	\\x69ae84704b8fc00826e08f7238273bf258dcc41053830ad13371eddfeba5838cf1b64a628728b9daa8b117df147741a92f9f16e43ae7132cabc56e420a599d01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7379e959b17b49c44020d6acdbb42f34032f68a8e19d91c5427cbe215469afa9fe1d1290f897f328a85076e3330e3eb3f7dd3a10965f363ac2f73922aef4985e	\\x99613723a6d7e684a3efcd6d073387be0cf3f2857ae74a41274535a42bdd9dfbc9dbfde96a8ed438062597fb1926ce8361fca0397dfe959a1913c51ff94f3b05
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xeb7b60f66280113ebb0c5f5ce061ec00f495a9bb5bd1e19bc10ccb741cb9c803d9dc813145e1d9bd69873c6b5af02a07c4e99af80520276e9e3afd01fecfddfb	\\x7720cb310b101606230cf054344bbd3a36a98fd1a6a723f24468cc4f3b6fed21a9139fb8139abb7cbba7bcce9fe6c0135504796e1e07bb6dd77c40b63dbc9e02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7d24118b78d4551c3bb8b84739206764c37fbb648d4ceda23f1728ac65e52bd8fdfba58628ca36a923a12558923bcc1643a2546e1fa8f705f89cd43cb63ffa70	\\x10be94d4da618e9b9c151cf02cb8713fe2fd2f68181cb96e01bd4da0d7a14cf66e60fa98f63c3fdeff81a80898dc6760e77fd847e689dedaff6094b6c7f8b600
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9e465fdacb212f78dc01c185928376250fe33bd7a3fb542a50485f1f5a13b32706e01ed9608f5c4ce9e272d08db81b8aab7f1614c0277c1a3e10d08b12f8b352	\\xc1b8b601e6d72912e7862d90ebdcba42e9b0e75c4b816e7566e8cfae392bf9216e28ffc34adfc43cd9c414162d49a995b3c2a8b2bcdb73b16f6ab9aa9338220e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x16c1fa167deafff0e1933baa439ed6a26e646ff8eef747afd3f62e7d89477c2ff28c03bd6f81a079bd48533d95fb81f188513fd6b86013f7b26ba9ec793489de	\\xd2969dabdee4d5782e9e92f22827ff7373c8531da620dec086e29f9dd70afe9f4c7356c73dc7826724073cd0c9f739e2d8c3cd21bf8be5a81018418485dc610f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb18e1c8569f423d840a80cd7ef63e07875c30fa67ab59c701c1186991859c3de5162eaade533a478937fd11c2dcb96949c6fb28319e6c5b8388232851b29f2c9	\\x9e8a666e5cc9f1141989378eb865c560583be44da421948289b23d4cdf93c9c96bf6ddf9b81f9d48f735b4b814f04738040e130c607ebc844c9af2393b885c01
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7580c92c82b922c202a9dd802632e0402acaee371c31f626a1cb74208b5f29766c06cb9c2fad9654af2443260d4f700e28aeb0988ccf216f216e6ecece43742c	\\x1853a9b1245cad0c51ebd7f105ebcab11e94e0a71bfad8a3c0f566f6cecea4a82bbdb87c35237ef36a578408cc220bd32b001f7d0e663c6fc129b6f3ae724a06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x874e665800845b467dd5905f4c74cecb8470301aaeb7e4f7b79dabfcf7959af2ff9a4327b97dec44e71c7d226cea433f266bcc8dd1c685bbea4659b271ebf628	\\xf349f4226c0cd259b95056a7ee68d1627d5eefe91b4483f426c141ec016dfbe5542df37644ed2c1ebb51088dd29350805cdcfe9cd02de9460e77cf981ae2500c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa11ae99bfbbcb42e2c712e2df9a47032a829e2f564ef60466bc7d5b79dc603ea43a03409f3c00204b86b44df7ebe16304f57198b422e3212249b5b1d47a50fc9	\\x091e25c23ef726dcebae6cdc4462f351108d0c2890485eb8d851044a640e1981814818412031e5adb00e9569ef5c460a6cbf6e48375a91e88791b2885c119701
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x67f3fddc444f97b024f5e273e167257a9207de153ba40cc1a95c213b0a9d23ac1a8b876ce633c297a320fe7b0fae7b95358b2cca2e059204095a134515bab4ed	\\x8bff095c601e57d66951dce1ffa0b7b84ed599e5db052e8f4425a3f1931c675a6f0e71de05697e24693d6e363b95887d9b0e23c30a672d02b64cc324e7c77304
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x9b6473d5a792f71822c4bae9c17e5e8817ce4ab38d6455d669ca4439da2dfa89e3b4fc8dcce171468ae0667615a504500f35759aacac247492c4dd0281d22583	\\x9b49f5c1125940b801b7112ee878fb81b5ddcb43fa5cf5eba1bd036288aef52609b39cbbb2e23235c920d4c9cc76b99d7a5667859ce62ef874cc915d73051703
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe6e95152f77e35ae43fefa03f75c01d41435311a3bf7caf1551355215ddc89f1996704f89705aac6902770a8bb9f0df51b49dccb749b2801bedd4f7326640c88	\\xd83ac1c76c66af0cc118ff807957b77be84ab41c63c4dcf6cef7649a2df3d80e66ab47da5752299d39010c93f1be4f146c8854b6ec721735e8a974adb30ecc02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3e57497b861040ea57e77b3d3750750bef2861a19fff75a5e2bd3bb028731ae0bc8b0aea72a3ab963ef6a829bcb8cce2abcb4bc4e6e718e5cc150c8de6ff0209	\\x5d9ff7ef15eea01322df157261795bc9e4ca2b606a380730454afd0c4785fefaa1c39f025c7256a57091b4e9c250eb3f186bf9cca3363c20d7bcfc0f4ce14f0b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdcbd28b4e59feafa9996ea906e6ea5c9e9989848db83159aa55728bb0a0d4d1cbc3c41b80af51ae496452ad2389f890f83bed6dd9606b95dd81db63fdde2268b	\\x2a8b9662a8e1f2082786419937871764eb7c0e8d68123dd7f0583f3ee3a4518c791cc82fbeff83ebfcc434a7dc44631170241c41265867237bc32edfae20d109
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x6edbef644f5a0abe10dff01b7130d42dfc2ad28379eec083971db3abe6e61c379c61d4ab4ce2d06aa1e70d2f96b61d6d76bbb381a53294abcda72045eeec0a0b	\\xec5c30c21bf12c9b9dd5c3a792c116f139bdbd68f0a52253a3e7ca46d712a365b91632425d935f5b9324f37142c882faaba25c61a784372b3b15081a844cc708
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc5ef48861dc67ec9c5bb469f865770350dd4bc5e16217489652a3a010953ef0357c7cb911d54a98b55b22d72e459c6f3572195a59f1a13a2ff84fbdd25f565d6	\\x135b88f125dcf13b9ec1deb3fef54ec1a74551212796211a606ac669d24e625f21992a62ff5de792bc66f478c875cc7afa2f25a1ce61b54d150b1513c040c00a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x96a19a83b0e2f47cf22de1247507df16986136068a9eb94ef86fbf5d987d13aa50a1e73f0a5d9ce25272a6ae9a86f1eba73c9d8d78e74771ab6511d246eab8b5	\\xc6c20cbd1785e28e01c44d4a75422e8d4554fc28ae1d81edd1c243d87b8be49c38f0d0be6fbe71417f4aae1370970b5a5603f40699eaf203c75281627e0aed00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb4fa47a190003293cf202f106a2212f4a081064533b8e77506c39135e203ba20b7e3851ed6f06b8990d5c95ed4374e3d927d5e3066fc5115d0fca745ee733ed9	\\xa097c2c2c77a78365f533a2427f0d06ffab785f4431a38e005f1c0f89ca2ce2a75db62f3cc71bd5ffddd43f574334c9127835185eac0c9ff2575d851272e630f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xad9b410c6ee814035af42b4520236169fbbcc678a4ef50d081baf0cb1101d641896ebb7ca662485b20e5054d34f811aa31fe301be9334dde146f557500822997	\\xe11b082715c4913a1d233c373a4d19e66142af4d45caedb1b953bf284e6c057666f41d251325646c7c321b721faf8b5fdc1af7ffdb92bb410aa5e660b5362504
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x230781e0e5b9ee4e197f47a419bcb6c9de5dd311b22acf1a1cab470c4e5cda04bd4555702a60513e1aca58a00d202ea81dfa452559632d76aef618c1b69c92af	\\x66becef991a4710913d867630fa837723de0c6cc7c2ee1a06b068a4166fcc98ea2dc6bb921622ba82977de0908fc3aa5f5626eac6ca33e074a9487aa9e477a0e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x436c2f37b9463350d9bbce366411f7bc3a89ced0ea4f18c23afbf964f0331d605f16e75306bdd3187f5406a3cd9f1263004874d79dd33da484b26269e147085d	\\xef151650f909a0e1f9f84af847ffeebf53e2993cd6679395b3e84410dcec56f9e9d9b1572f565471c890d4b60bf86f0a2c238716ab46c0a6a527d9494617b90d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8ce275f19057e5ec16005836d5a509470df3f6fff7e77b808f89f6c2c7fd84d783959382391282c2e846369638da5c0a9c7b2e75915ace89ebf36bf4c82f904e	\\x51a430537d105ff10a4979c6fcde6386a93bda7160e122d0173a3fc607c83096b9ea8cf16844ef9d2357fd26fddbcdf9cf5452dfbfcec308188c26f6f7f3fe00
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x40a12096364f47d1c1cbecdb86ee3a50cae624686b9245f44e04ac62ede55a0b268df22945f485e0df6354c08d3d41ac454fa70cd1b2c730ac443bd49afa4bbd	\\xf89ce1abc7b13b0f9f2a1c52ae6c2efa15c6aef343058e5d1caa1548d4f18ac362326627067e0b1459a05e77bfd6ef1fed35fe161c00e15d8a4db569f3d3c502
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd9083142b08c06adf2aeedbfb8ba9e6f15f74e8e0fe3ab59aed32ac1d62f9fb09922991d84cad19e933c365b15633340e89979193cd4f3f1c2b6704cc5d47724	\\xa7b389396ee2c54bf422baf8f6235664fc01bd50413ffcc28089fbf2274750c7c55ee38e0f9c9b3ca76774067516a0889d3bbd479782623fa27a3da0243d0708
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfd7e1d8eef99abbcce56591380c1c72b8dd69589431397d025c8768d61c252446325cc455c95b0800fda220a2799fd10215f65d5d0648408dd152232e6849f15	\\x0f58e6620e1c27f2c0c021f2ae041958854df749c799ea7c8f5c7db6401f91b5f2c09c9cae5e23436442d3b7e764787612566912c51a1892799dbcdbae9f9c0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xc5d7f427425207c17187f0fee79b7de3c42f55bd779e1e0a0996d1d4ddb0de719b8763ae3ec90045a60e5abf7b64723ebb67e2575d5cd541d287bd229a99277f	\\xe3ad05ccbc350e2944d331fa14bfd58391179f4ace96284c6a35a3ffb8bcd5a56219fac9fbcc3647c12d5d7edc20c03e2c0d35ad14f53dd5693405f48a18e507
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x7dc81ad63e1c52173382ceca6a7b969316f58fe6cc6ffa73c9b3e99b5f05ac84a20d3eeb903466697203240910a8d8f1792788272b40faee3b87cc8509f76856	\\x794df1ec7f201a141a89f5a9ac150016cd174f7c84935a78371e3ed37200c53d3e13f72a2402a498b254859e9863fb92d40cb2a16ed67071be08496f5bb0f20a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa517a42ccf161d5fd680bf8fe338f4b02aa332e17f0aaa78e79684266fd9e657c565afcb757f6a3ac1e7a76661cbca48bb202da4be24c6f50ba36de3bd40c7d1	\\x71d2050f6260cefb8e83f38795863c909129bd28acf7ab5cec096786d760682cc5d3dfd5e0b8c1e5e2cd9d63665e93441b077a8ddb3eeb909d208cc39b43c40c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xb1ed42ed51864ff96b5c75125c62f9ca3e0734c42905484f3d3057207764aefd90bf54c9717793d41a33e292ce8e028bf14b7d2f9376ce0940dfe0ca34719d1f	\\xc4384d48b82966c6aaa0e9448d416e5008f25d1874cbb7eee1836b353ef63b8c446bc9d708051eb96b6e544dd49ec19a2a52ee4ab006b530a8f8a7e3bf076c0d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x84b179f21cc3fd2663a319b23998784910533486081a5516c6327d0f218100d50808b12e16756c06db8d4c9dd12442fb6433da149ed5c4808e7c12fd295cbadc	\\x20ec25c06f1caa6bebf0332f47c6353d303516c839224ffd64edd2194171193b9180955c3f8142a9f6e79abae3cae62cab9c4e91aec01c64fffd2ee87880230b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x0e4acce3f7308adde5af867f533726e66e77b6da55d818c4c71ab16ae979d4de23e3f43f3c38eb8cc273840122bc697530ad42290f94ae954aec8235379ee510	\\xd09bdbf05f9db5d80af8191cc0ee81ff01eb1764ab329cfb78f3ee0d11fe5a6d4f458e21e70b68a74e2f7e5c418647d2deb5a1483ef8e559053699e84100f101
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf37cf321d535e9d24bae7c65270006b0948620d98c1fe1ab320a22b92864a780563916bcb2b66a6831c96359032c5ff624d521bdaa2eb4c14e006fa14cbad0d2	\\x3a8571cd96423659d087b4fffd3a7762b2997a6c629f22086dc72d6e052af51548aac6529fee4b87820720465e9b18f9be8bb1cd4570502b68c419d1a4510808
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd9ecebb6c6981dc48686dcae7381b86bd9f51bbfac760ecb2651957eaf64c81ded661960372f4d9b1e00a6cc4730511ab3a37d8bd7872c4f8b6fc569c8c53bdf	\\x97766843caaf6afb9c94aab3b481e571fbadcb882ffd07b7cd872544f1f6a71f2f4fbf58f243b5e82ddd7f04682e9c36fa9d1d8ac1b3382495ae7201f480ba03
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe4b0dba604176bdfe7b5af705943b911440c9bc9096a18dcf7cce274141c7b023e4a82876cf8ce38de76f144c35b8442c79926bf66d43d2101a69e8c7c686cf0	\\x69e2784825e8d3e696ec885d7802477725b345e2b2fcbed7142270f6ca2d16632bd4aa85bf10bf6c6e0ba0aa9b9a4293ca76b08334f4011bd5296aa47566970b
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe2beee3fd506306b7f5dc8b4063b83e34633139aff656e412acbf68d61085ab8bfca9cabc0ab47b95a168a524d7ab43e4b12093167c237af9c1375e2644dd5e3	\\x9400e18ab10a6198ddcee6e9387e41d2199819f22cd95e971997c8e68cd4e5a4ac6490fad7b287ac332d75c87eac58deb66144fa75455761dc88ce1fd436f806
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x21fc89079ddc50325a978259152646130b012bf2aabdd88dc861bf1afc24683a76e4764086c9dceff72060179af8037b9ce2c03075b1ec93fbf0615bae414c3b	\\x279fab4a9a37f681af94026de8f67edf87987b32a2694eebe20786d2a31144baa34b58a09e2016a341b8bf191eaa94ad3c62d9d06ce99ee1c82b79279452a103
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x05a0638981524876554cf59a82f8237caaa324ecb02fdd74486c87af5c468238a9180f9910ec889e4cb0011caa41fe732b15976f852b04ea31f3851efbd6d48c	\\x2512e020c9ccbefe0b342d5017ed56933bbbecde30f8d7abcbf79afab9a18d615966d7aa44a724c3fdc048fc2e2561348e39ef53b61d4684e04652d980408a0c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xd21155e35dc3d2ebe37b33a1084e3d0482cc950edb13a742ca4b4a47317a4425ca92211f195c6f9de4dfc64651e095f8625c49dd0ebf7029700e3698c62f7393	\\x63ab3198895afb6cb70cce40c54784f5d8bc5eea526298d161c7fb255a645b52522f2183edbef228b539d8631841e4cb40ee9528cf8ae23cda48820e20dd290d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf2957256b152d738e386832e7cfaaf76988a43d763a80071e3b158600ac386ae5de65ea1c1cf186896bf254a1da0c24065bbab3ade4e9c3170ed54f2b0e38d32	\\x8d756b44718b4861fb18a3f9f81375c7ecce43fa2a02891b8bbd23a80479cd8a3f564e9ab6250f52fd1e3646e51c779b14f5d2342bcd13ed99a067230f2d260c
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x44de2be9da1cde1bfe37df4059a4377d169b5caac20f0f55ec3c2ec091caf44e28c0d32969d4c0891af30060752e94f69db3e637e16c69e11ab41e2cae8dfda3	\\x48547665e849f1fa661d64640d2f45979266550b9b5f9b2d06eb476cce804eedccd337c270d96f573d1338b94991aa308154d53c88dddfd2a4a2ebe8430c7807
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xae0ddf29cb4b8e2c48fea4ecaba52755073e4102a487180293b19b8e0db8d667642e1953f23683b65973ef5b27733f676a926c45e9657f118e12fe48e2f5c482	\\xc6d3d705b037aa5e1f64e7826139d9d86edc92078b975382fe03b6eff2f77afa8a9cb2a8b0160339cb51b39e0570cc3a137d2391a0c4542595cab33c83e79e07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3e92c79291bd5d8a2379e41bb408dcd7b1c2f5b99603e3c5acfacb183529f502c8228637634d17150b04eb2f1c93aed4de47f1e28675143a0e136c453a98f843	\\xa46bbd0e25ae11b4f44879c15548b85b57d9e11997d5b41a7324484f68c6aa3437688c6432c3d6cb114da3fec41d5803dba0df35b3252035cc2f2bee466aa307
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xe98f1d2842ee0dc8232761dc3f2bf21466d869d98d5b62b6b2c97f9753ef5cc754dcc17ea5f0d1c599e829f578815f654fbca7813e9a385092dc91adf182e307	\\x67f7fa52086e60b291f15abfab982e4d7e8eee4f8f8c0bfd96c2d603f709f3b753c474d919a4771944c4d70543eb71f0dedc9da594595bd842275ef153022e06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x931030e25de79954bd96fc113260486db1465fa6812a32be71b4588e25b21614226b370fcf7b4a4d4434ff67cf0065bc43a2bdeb2469a60b9c3171dae3617834	\\xdddf3d2aa323ff82a2a40001cb9e627e17b06e2f127f6b908ee7f34ac42062a3bb1e075ede417e732bfda464504c4a0a5b61998d95313adf287b207bf463ad06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x8b337138a51d7575a4a2a820cc78ed461089fb3a5755214463494adcec390df37092479d8f9286f74f8e79bd5284d436893f1963503266067a41bd14a16d6707	\\x188a6425164a85be638f19a0e577a914dae2118f749f21c6aa8e0c7182c0e109a704f995b3654f35050994439b8bbb575302d3a89b0aecbd0dd434919e2a050a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xafcf79c40fcd5c52e4554d7af85b85ee7d986f9c22bb0fb1ee87b4bcec937b16e193c12f93865d370384dde444cd7024d0d473ed673ef41eb6bd96d43dc39756	\\xc492180dea44cb5644fcfeaf20f5b0b04e8254df5351488e3c68de35fad9944fb13e5445fc7afc439becee77b3098864c13d6ac45ba9562688e919050daeb80e
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x56d57c3dfb918195954eefdb67eb246c6b9b170eb3be7bae79879fd9ff6341520d0a18d5cfebfbd36b1645e5ee13a5c3aafc71a697bdc52bd03e5da15afd5656	\\x0da56c5420545b1e80e7c38c33264c2c834e971bfc4bdad8d8c7fad489cdd8f7ea55ec8c4df6200a08d45700c37928d48ae8a8b96f255080c0a60f169d9a5c02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xf703a14c117622cfd00e7865aef4601aa449cd41ce373228583f528c03ee2634bba2b599f08976b88e3e9f60dddd60e4950477834324e0cb11666f022b7c4eaf	\\xe3398d7f8dcd649988fe8a3497134e83f9dcd8231fe563118a4c57fb4c2b2a5e99a4c33d80bf7599f4e7ad34fd59afb238c637cfd4043ce9b1a0c526adb44b0f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x5c9e33e61422a1bf4d6e19f2f947ac4f96f335d2a05ad917a3c59cc71eadb318395017f9ae1a41d9b27deb35dafe3e4c2815b7ee99d037ad2d28157a461c706d	\\x6c4e3d80c1c65edad1c64b6dd1fa1bfefa64a3f341f9da95527fc93a828d49713d7ff4c4052b70c413a1b85f5bf6d4b1bbd04ddaa7fcc5b03599be1346389003
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xfbd934e10f7ea935ad4866cedad19dd32ec10149bf6e36948c7af59c5a10b8091719de656a744d8a4d313de5a2e872cfbfa49a3bf759799ca642c563723d2f26	\\xedcb59fedf21612424d0a3e056c3c4266e83750bcff559fa8f60a7a2f37b463c76d94bb85dce1b7998c08197d2d4c663a033c1c60b9329e533de4395489bbf06
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xdd891d50a18d6dd73865d69329acb6d16f692a885c0d74844da3a50ee98f42b05d96a92d8e91957cff78547271b1fed67719247654331b73ab9164f0b2a022b0	\\x24d1ecd698744845f03d5c5ac10e948853e803ff83b9a795d054e6e776a90fdc1240201b99d4eda4c14ba52f9cd7f29447123f485e20cc5bc6ead0f87a26c30d
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x3a32301c3a1f2976ebbdd3856ae784750d8efcddf19e14422f0ad1c9993e93e09dc18e2341b0a6a6af93a282353846d9292ca4e47c8626c1dfe507b1f75acda2	\\x34a11c0c22443059ca269fc58ee98d40f5cc3841df6e1bdd761ab2d93a41059dfab28a81cb98c1684500e90bfdfbfb7b4299a7b3441546578c45e6175023f40a
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x48c0d4ecbac266deea701bf9bb1950c3bf6ac8d6087826b5b165a416cc8f2b04447a8e227554397298bd537c33fae99ad2bf6857f6b5b1370c8e000c6923cf87	\\xd8a359dc520ae2eca1a0f6619e01532e224084b8f0ea8ff9e85981b3c679cbfdc0c423e35aca3fcf2330d57337c8d45f2e35bd874925dd3bb3b4d120d9788c02
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x2b0e566f4133ee7a01c617474fce4733a1732a46126c955083154fd6a274f6b86c894f29d7dcba81ea6c351e1ac837ede9e8d4af7f5360b4c4997838a06e73a0	\\x0b7a62ee19d9bb3e02a5863eb360217dc259a3404ef4e27982feb8d18c4258b29ece9846b2056787294cd22c82667219fe312d291c4566f5a3fb07ad88ab600f
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xecf7810b472e31819f4968423ca6789c77a8c6d6f1ffbdc2fcd473750fe9fe5777527e4b7b6889dead58e80528852a3b8d94a759605ecdc19d26ecd9a8e6b157	\\xf1eac08a89785f4c352b53aa98677673d85ffa2a82f36ddf395f72f5712bf2db13277ad4017a17212804f78019b6393d35f1b85db6e993d56be00e0603d75100
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\xa89b266400512f69688cf97e1c32a9be80a7167f8c3b97ce667ae627d717970cc9c73f6c144b9be85b0d3b54c8caca731a677546c7b40fdefc2fb7cd5eb6ec8b	\\x37d48ca59fedc45d5af1cf3c2e95b95c781f11bc6a011fcb414e22025fa8795cfc00495b39df6e59910bf8927fe3525033ec8769a00dc0f821981506d30d8c07
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	\\x60d8d5ad1c5c5c5c5b3fc07f98ac170b7e8b50dd8f63a8ad78a4d71ee87611ba5e3b657b2376443d8d2917a86d12f6e7e8be90a106d45ef2d84c11692323d188	\\x7e132cbeced20b305404238a9875adbdc4a5f38da2f83d0e565703ea1faf1522b29fdc9f558a9fc4347a4ebf22e42c68a8f3f54a7fba4fe8094cfa30cce56a03
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
\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	1608206444000000	1615464044000000	1617883244000000	\\x1af73c93bbd77c01480d5efb4f7abb2f56b794eb038250c0ecb9e86922f4966d	\\xfe379a5d356eadd7ee8d19ad4b2ffe5213e812ff1787bee197554586289082f9633393f9447eb94c4caa740a4e6198915164cfa5c72138a96e34639766395b07
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	http://localhost:8081/
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

COPY public.auditors (auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
\\x4eca3a6522b47569f59f8efc19cd7e1e1e95582cca4e3a0b14600c6cbf4980e8	TESTKUDOS Auditor	http://localhost:8083/	t	1608206451000000
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
1	pbkdf2_sha256$216000$LZkfB8zGgGfx$N+kUtZoBzNWJz5HnGhA5d9Db4E+Lbp6ZFhC1mlLkiVw=	\N	f	Bank				f	t	2020-12-17 13:00:45.329973+01
3	pbkdf2_sha256$216000$RY7KP4BHAARJ$/btLSrrHa9Xm+mdo7tJhXyWd6dSdalMO86Qcqe/vAE8=	\N	f	Tor				f	t	2020-12-17 13:00:45.498208+01
4	pbkdf2_sha256$216000$nVeexAkaGeJw$LJVS2+B9VQDDFSEl5zB/9IYXsWc3RLRhBmXMGjp08H4=	\N	f	GNUnet				f	t	2020-12-17 13:00:45.574374+01
5	pbkdf2_sha256$216000$LRGJ8GgfSY4v$fedjN/QPKLgRgmZYr2J2oaCImVqTG4qJvmhJaxxy8QU=	\N	f	Taler				f	t	2020-12-17 13:00:45.648341+01
6	pbkdf2_sha256$216000$98vAuyR6lnhE$mTLurfkWSt6Z/JHzFMlYEQBhUz6ujRPjA4OqFAS/rXk=	\N	f	FSF				f	t	2020-12-17 13:00:45.724712+01
7	pbkdf2_sha256$216000$1Ie0GwfZ2K4C$NLKVVHOdU09eyhvifzKmt0CGEWrbQF7eHv71H3TenrQ=	\N	f	Tutorial				f	t	2020-12-17 13:00:45.803284+01
8	pbkdf2_sha256$216000$r6hMZZgGl3OL$z9S7em0Mvv75KauqdoxHl8jwj8x/T9t5hJT6r36smWI=	\N	f	Survey				f	t	2020-12-17 13:00:45.878331+01
9	pbkdf2_sha256$216000$bKadBviC0Ey7$yNxANuFD/mCODw+2o1GgadIzIOWaChKs4Io2QJDZ98I=	\N	f	42				f	t	2020-12-17 13:00:46.337233+01
10	pbkdf2_sha256$216000$wi3C9K00HGpS$AyVHPnQieAOdXPmuFuCYcMNjEfrtEXRBixlYlw/CEQw=	\N	f	43				f	t	2020-12-17 13:00:46.806751+01
2	pbkdf2_sha256$216000$kA7MYSMofTNM$9G800XFCgR8EkjQ98u+Oax3pawOLhr1TEZ4h9MltfCM=	\N	f	Exchange				f	t	2020-12-17 13:00:45.412852+01
11	pbkdf2_sha256$216000$BCFWCXHYNnmq$GCa0X7vShGlCObspgRcmQub7oJBPka8wt1CBFnngs7k=	\N	f	testuser-IE5sQAmq				f	t	2020-12-17 13:00:52.63863+01
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
1	\\x72aa6b8f737b86fc68a4055b57e13b8ed07748555f1569c9d29c2094d50cabb9bb01e1207b1e0ffcfa9dae93e6da639854cee89f53f0de215538c8a0d9196fa5	\\xcf1bfdf4bea168b92b6214504446fb818a4a55f9e75c71527d8dc7dc17a54a950a36c9e8672d5df1b8b4809609cf514c80e84eaa146ba4d48b415f2eab4d4f04
2	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x2ea8db1b6edd46d482692d73664ed6f5e6a8c22e2cb29393772dd00e7c9fb2bf6b9451c06a19b56f8833f5715d2a665649b6d88f66969b52ec0c231e95cd0e0b
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x0284ff37856bfea493f240b0ba4627d3836651ff8ca89091a31feb086af2953cbfc849946dc1cce60a75a78aa0ec5ffcc8054fc8b131b33ca786ef9d9163676e	\\x00800003ecff156fef3a9e61689ded3b679a9128406c1d1b1fa174b753e3532ffad1eb9cdc22a1471e2881a3aa3b5c9205ec063b1bfb3f85b43150e4b0afacc730f1f992d07e320eb2b3fc2d31fd500072a9d95038169fa00df19e4674657e9b0c91b89455b88aa9f7d5c7605f50f58441f05f7752d8c1b0a5ec6f67d608126849d76c99010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xaa78616f4eea6bf1e46096d2fa49edb112674d6523bb6fb0e3a474f5ef714539438495d722f54001f9d863d00bf773c45826ec6f410e36edc7e92b8d828be10b	1619691944000000	1620296744000000	1683368744000000	1777976744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x02842e5509956f69ee0f325c66ceb060b4f40e3a2e6cf1c85556f0e1f4e46489ffe118a7db0a6cdb21cace859d725ea514435f5b1b1e5e9d252c6b46ca1363c7	\\x00800003a4cb0d0490da16eaf9a4619f1ec0fb4f484a07a1e84c897c3d448e05392c1619aaf16389e3949f622d10674a8785f95c7a527f00719781993ea966a6a690ae494a6c1f244c86ceb96252905c11a82fe2d03d82c4490d3f85348bd0c701ae54f9fb17b4012f87cdd5033a2a111f7c3a3d9b2cacf946f0473f7f8c451bdd3910e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7bfd52b192d37afb06edabcc850e047adaa1c20248720ab15a457a17b5ae298528e7284c5818513688c7462ac90e1e5e06f5ca9b4b96e9cee06f950788d92c0b	1616669444000000	1617274244000000	1680346244000000	1774954244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0420185c98b5223ce50b04b31580fdfd83e4cd1d8b940d33c279ba2c0cd95f64335680892da77418d136757d136043575568c0059322312369a924bfb313dbcf	\\x00800003d7dba7111a6d03680637636a0554f320f5e86cf7f7cde4a7de9bc8d19b2025f2c9b5b5dbb2bee2dc7b221347e9f483a331434016b3611ae04eedd47f87838aa3acb1da354e00ea929ce7dfe8dcdc8b7481402d25234cce9b2fd476f899605f88d3100811497088fb89d071235869e7173d1714d233a3e9cef5dbbd4e87ad124f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x55bb7e7bc08a98250f0e683b73baa095ff6991a7f99a5ab6d76ed246bd515a02b266f4291d58aa450841dd8826caae55e91894819c68cc81f14612b215b1e70a	1624527944000000	1625132744000000	1688204744000000	1782812744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x05a0638981524876554cf59a82f8237caaa324ecb02fdd74486c87af5c468238a9180f9910ec889e4cb0011caa41fe732b15976f852b04ea31f3851efbd6d48c	\\x00800003b95c7db307c8b0e6b92e168b3c62bcc82ab8e94c39a636e39df4218c938406ddc91260e3fe6356c5752c506c78ea6def44b2e38914c89722a9f7c2e0ab02a1eb9ce284220ace0dfd07589a23c3bb792eeb766fd1a244e5eda8c9d9337db7d56c1a232dbebf8827efae2c849017e19ecfa7163cd7f8ceae3644e4d947aa1cd425010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xde706b57a50c23c4b9e6cb854b969a91b5e79bed7230c63645d89d7397d6bbfaf3c690e8fa7f424c612d308473861b5c60ca0083c5950dc19b5e7a5087a1d70d	1613042444000000	1613647244000000	1676719244000000	1771327244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x076097b1eeca6dd74b2ac81c8222f833ef737306e388e0ff3c12a9fa67f61499348a2a02482699e30c6e0b3865c62cad772c513b13650de66707ec5243d7d114	\\x00800003a8713bbbf658b217541c79e27c3a40536894b4e96838c24e8f7201b0bf5894909b1bd1c2d7315fb51c78a870bb6a9fea75e9b7f28bd227262a5f62506a69458d3318b46843eb206675ea0da4fcf5118ae7907bf850e27ad246ee03e70dadd365b8d9ba691d441b1ae9a8cd32f0cbebedabdbfeb8820a383e200ecee268251713010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa7599c097981d3db1f62006375945d36b4923606700f112731fa7d287ae3fc997ff250e150c90eaadaee20406798820f085f7b048126e30a2ed0bf0d6ab5bf04	1630572944000000	1631177744000000	1694249744000000	1788857744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x083c68648bc47e727c16d7af2fd48d843efed0b4f322d64f444aeaad097e5cb0086cd29b89a293541339aaf810f149d1431b69ef14c69046669d53549abe1c16	\\x00800003cd742a9c4d06b9747224983a6ea718d4699df58b1652eba5e2110d4784d4d60ac029271cc87b731f3606bfd5e3649f52fceabcdf8b36e9eb13ce42698ae835e1fc1c49f7f20815445e07dfc376e1486080b7ba3aec046e8f98521a50ce1e4c40bb7050333c85358e32b885d9fcea8be2387858aeb0f851be22489e22449d33ef010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe09decd5156535ffaa5ab488a7c4884727dc9b6d21bdccc11044fd8a73ef81130a70638467cdb4dcc7af4200a2c07e0a9aff45fd98b97131ec1fda31ade4d70e	1636617944000000	1637222744000000	1700294744000000	1794902744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x082820ef5b440d85baf9e52248e0aa6fdcc3d21140bc726310957aa05b6a0402e78f43154c24780bfaf08900d03b1389a245b2114305a302648549293128ea8b	\\x00800003a383f966e1e2afdacd12dc14116618104881cec24276cc313a09dfa8fc8eef35fa459cc0bca8541467d524593621958155762e95b14145c9c6ad7fb620cc1dc8d3d0ec07f1bad423f7003952c3efbf142544142aedac64ced7a33664ff8c1c29beacc76ecefac8d04b436c25f71d00d115cdd1e9bcb33f109138efaa0e6bfe47010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf831a718629458b2d2cdc9593364f17e3f6241bd7d36b75a048c352f14c983d1cf230d61b99e887073a8fb8ea6dafdcbaa7bdbf824510c766e6d7734f798f308	1619087444000000	1619692244000000	1682764244000000	1777372244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x09dc42d18fb591c1e15ec4277f38ee553b96747bbfd0d61ba5011b31ee8ea55b7b5fbc77e5b511f50f8ca86ff1d16d8a9f43b12896faf6a8d40d27565ae737b5	\\x00800003cc3b2eff66ab98a12d75e2864ccd43e84990928602cef476364d5e2eb820cccb1cef09d10e568dd593c9df385c7d5785d1aefbaba3d7cd5a5118a7d9c9298b9ec7032e79e59868e01a333a8e332f3615a3dd4ca7de4ec68f1fec2f4c399f69084fb5bf6bac10b3c0630ac01c2ee66360329b9ffc713ff8c2d3c49981bdade765010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5e741d6dd645d4c96f7891dc43e1685232b5b7442329da07a0f37a225f6ed2da85054166153d6036911fd708ffd2ae77d770b2712e5c369862ecea978db84800	1628154944000000	1628759744000000	1691831744000000	1786439744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1010db5b7d0f0524bd7abab50c367b24b31dbcb89326e7c6745f0ce3804827085d61504300da967ddba7b3e4949732a9483907630e1c5e91abda7d6b25705e7e	\\x008000039ca3e043c8da5d7e182b8d0e46ae63e60965e3df497ebd9df60612aa6682aef0c1867c15d49a4761c427040eddd62e4363ea90f76746147298d71f908e7d6effbb05a8f2414933d577c48328388d758cb272ffefe0c5901f552bad7c7926ca15c1bcf573d4b3b1e9acb1aa80c8823cbde990fb9afa8530dce015bd1e31a46c7d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdb199b0c23472880017a14babe691e9504bddde46f4b16707e684eeb9ac834067f8b394497444ad9999cbc4a0df2243d13ccf2124e966e78f1f6b33bdcb70400	1617273944000000	1617878744000000	1680950744000000	1775558744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13d4edb8d1608eca0ae54e13fe059d601aefb5123a51f97394bbd0365f74894584f8359c936c8ed2a6a966531dcf29a737818366f33831293c9282c656a50830	\\x00800003df2640fa0a3a0c72f893890f8dfa25a1ad83050f1b9fce220e31794d1b1e580e38100ebbc50f9d22b61508e94e7c3e0ff44f8058f5f0355925464318aa85348d872fc5820149edca6a747da7bf0cf9ff7ae3cb750ab02fe7f23cdb9b7345a72c610b001d159c0b1390d80cc58c6846747138ff78d45d5ae454bb2a0c85272d59010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x109fb2fda900fc504ede9d1a9b5531d2ab9116f31cb976764ca7200af398ef805415c2de6c2b8c85b062172fcdae9b80f27cac24d721715f972fd35f4fd1c40f	1616064944000000	1616669744000000	1679741744000000	1774349744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1b50d8dd93904b96c606626b08256c6462dbc7397a81d5fc4852415563041aa79e71ec04a16193f34b31174d054a3e9b30dc85df1c642afeef5cbca1ddcf5290	\\x00800003ac39cd3e302f2a2c5e560ddf66d5e24726244669dac76a7c6a4c7b66e97a6cc03553b0e19aeaa58cb998810453efd72c097193bbbf7432c3a5b1bc60b91ba5cddc106701aa8deb3871445958919371e775f51a7efadf736ecbf3f9d80aa7d59a1d62af2fe82511822bfd02e79f4483072e90305dce06be82a1c13da8677a00c3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6f770e065e9a8856c3e6a47d61c6e8203bd8dd2e09a2977fc1d00fdefc030d816396e9106389c18d7d860c324188325d1f77ab8e301c185ed6fffbe33f956e04	1612437944000000	1613042744000000	1676114744000000	1770722744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d3811460dfc9fc6cd89726beffde7dd641969199c9c6cfb3af86247de4cb95548582a1c77c005643c227a9c573db830b3a5a66550f4ecf8648ba62ab3e2973a	\\x00800003bdcc6d7e2217c8886b8f28e454f6bbc7294a60458ab848243d707d31ab2e6a8854da7b6447d4dfd167a1115332379a7530ec6f608b488a984536cac232c02183cd7d81f8b8d162246df58734478d994670fd35cae266b5f494e01ad7e8bd40231ff94db65cd889bb3dff9717d8fd4eb1f636cf5cbaa2eacbdbe7899b1859d43b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x85ce646155344b76142be20ae6b695f117fd8d0fe96b3c5e929463a6d6f2b65e6369853deb28ae9363896b1fd8afa87e60860ae5d26a1834bb60ce085412240a	1608206444000000	1608811244000000	1671883244000000	1766491244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d1038655ba06294abf914d6a2fdb51ef4ec1ea29e237ca6094d2c1d6730541db746b50fa29f4f65bf1baf81c15107491e925ea03d63ccbaa017c76aaa11d73b	\\x00800003e1b7cd75948e1e0fbbbb84015986fdc6ccfcb0d006a543433a4705289c154592fbc956a162203ca02ae43f7e329debc63eef240ba14a7b5b3c5b9a8eaab3c5980b5ae7c9cd56fcb8eb55dad5f1e97c86eb6cd64d60f4995969705f85b8d4f002a9240f31374f0c0470d3cd27ac2c9b84eaf11a6c99b7921d7d54c93d12b62ee3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x703dfabf290c49311c85933c1bbbb1ea0e1863e5205586caa4fe587ab79ad3ad5ffb7c3e137de1b8392b4593b4d24545a202428eef28e0aba39fca531870b10a	1626945944000000	1627550744000000	1690622744000000	1785230744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x21fc89079ddc50325a978259152646130b012bf2aabdd88dc861bf1afc24683a76e4764086c9dceff72060179af8037b9ce2c03075b1ec93fbf0615bae414c3b	\\x00800003be120b0cc5ea552879a7e679799a185d92cf688dadb65c95460264993cda01b8c065ae0b7752a7c0ca22ccf2ed5b64be6dff4df6a64c094e450369c78212f0ba1982db05e188dd3d4bb7ba5a4f9a88858ab3fddde89e781e54ebbc28c3c05965f48be47b240b06106a6387b6c42ff412f8df05c725934ad700b57ef8bba09ac9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcdb9e10087a805873e8e7e8493bfb7f45a8db53bb934af72a4d777ed30090f00e37164720cf43332f54a47d7a2c10f66bb83d3d9d634221604e2c548a0e5410e	1635408944000000	1636013744000000	1699085744000000	1793693744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x213c104c95afc0b4c1801c98f669a79a4636afbd394841d50559ccba16015ece14ec449053cd944d027d6ced441d8f43973f614487da49064360f3ed089533a1	\\x00800003c75e1ac97245f5439811c18c8aa7c0865e796e94847234e22a305829d00f4c844ad89ae5a251ea457eee243234687a44ce1fd2bdcacb0a8abdbf4293ea773bc167c7bacae8b7a246beb0c7f91bb19e2fe25c34f5173c01b2d956cad3e92a0cb566e8b06308d63d699146b4d23c88804ff4b8aef04f4f0ca9ee68942a4166ef8d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1311abd4f19fda472ea0a3d7fcd05eb758bf5a8c1dd42ff3b9217929ce3849218d085581501b4dbbeec831c4f33a705f9b35cfae24a5e693386580007f7fe90a	1633595444000000	1634200244000000	1697272244000000	1791880244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x253c38b14429c0c21083806ecaa59746c5eb957e955ad68ceb4b4ef7f77dec6f26ec913f8b6ed82704f18bdacb423924934e7011ab03b1487bbccf98931d8891	\\x00800003a1894567bf10d9ff0c264270176c63a716c496f26e263bfbfae7366bfa25a2e6c76eb445e58ea3f646145abc388aef489c5bf437b374272738d4edff51c8a70706074c8b676054c81b357a09bd9b6a9050808e03ae5c8ab1b7df45ca0bdaf8a428cce09c256d20b70029e8914c60ae9db41de4ce7f8eb2e0d08ceedafecd3a39010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x245a54e099752162fd5b5cc8dde13ca35b71990803184012fb3100a3656dca70360c61ae8b3b0d9beea1525fb5b45b9024511cb3b954eb90fcda0e6f9eac6205	1622714444000000	1623319244000000	1686391244000000	1780999244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2660361a7c533f47c484fac1e642fdbed7e2897fb3d980a5060976a94a8c21d419f79d6130cf46cb0e62c1ab7011b2828acfbabd198b855cb1de9545126459ed	\\x00800003d8f895001ea4300293738ab2b54a43101bda514fe624afb89b353f04c67e0acc6b25992f7aecb9726ed10909ddf5c9d713b415b11a5810383233fc93e71debaf1c6cc794bad84769bd1845fabda74d5031bb2efffcb78d82f54b09905eea7795cdeffd04a08ded7e2d3b66597c475219a870214ac55a12aea50379e78e4d339d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xce2df54c4b27a5220319fa6d313ba720e69a01dee29f3774c7e73611fbab6c363da56ac33880267812d9e30ce6c6ef72302c182cecbeefd78a5b7ee95b412509	1619691944000000	1620296744000000	1683368744000000	1777976744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f807f4ec6409ef51991629896116247097ac72f3eedefc813bca40a5b983e59568e2e69965538098b21b2f3bb7f324ab372a426bd456b5f524ca721c875d72f	\\x00800003f4890a32777cc024a2b60f5d7f58d0b90cf4eb79a7312bca890f270d1edc4b71f32e14a494eb522bcde58d5f1db0cd1bc128a963e31331683be81ef6ccf9078ee6b97d86fddbbf374ebe82b73ed4f075eb067a83d192dc31b17abb61b43afbad751df51d33adc3696c269d09179ceb043a4dee9f32e127343a0487f3f6df0e0d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x988165a36068a114bbf103b33d1d9a2bdcf48ed53ca5a20a2349952bb13148d0beda7896672311c73f31e1ebc42f0aff3ac333b55d46ea1fed9f07131c3df706	1616669444000000	1617274244000000	1680346244000000	1774954244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x36f43d0b0170b005d246bf7a00031ed452130b88024185ab1381e050cf9c3ee5d9a84fe35b180991e5d0344a083a65a178d59a6a587686716d37e8c4de9d57c7	\\x00800003bc8f80859e13c76dd8dd387a7444a98f0a0bd76f70a2f9fba46e4a6e6c2ba4ccd056da29177c548c6767051da16bc61ab3cf82a615df6c2c9732293410b9a6ce894fc9bd78058d8cca612153fa4f69975a25d5763d4370249ab0e3ca66e9d980c6f92849c5f2d68a60f2cdde78e000f0ff434d67a047a8dd4e4f8630bcf10df3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfb2eec1fec5aadde7ee4bfbe11329c34043035e80cf41a3083c32426ffc7a04419affc5033a873c9a0ca3e69ed00498d2d81ebabe0acd560bd74b4b612f19d08	1625736944000000	1626341744000000	1689413744000000	1784021744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3880baa3cfe58069027091d10db39ad9b3aca625b65f40c796cb6fac0bbaf828827b885a4558820b069b845f98e19bdf8c208d336399e5afaa1cee6a4efe6ec5	\\x00800003d75d4de1e2fd4cc6c1accdcf676412e34db3ae8738479d1eac5256bd50052d729f3988a2afcdaf3dce5e81833cfe97ac74fa07d7c81474c3bc79a5f6a95390ab863d8a08698c03d3239b5f026b5c848fcfb3a14872b12880118b6be3086d2b7ae4a9a07e4828ba9ea3e122a7db7e4b22d82c223cffbf4372e3777f74bd5e8be1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa86e02d42ce511c1c145e36d620c361034c419d04781831046112eee563c96e8351b71e987abff816b4783573149dc26e4b8df5d56f4bb46b2b02a34756bb50c	1632990944000000	1633595744000000	1696667744000000	1791275744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3930c07ba7c7bdf8606bf5de17d7ad57dad99ad88ddbe3a240157ac341841f395cc1bdc5bdaf1eb7b8da550c1585926afb4d93b934ea6132fca43a942d0f933a	\\x00800003b39c2c9f8d3dbfe6f36f16212e3dca6e1de0a3fd912b1bdcad1cff23434eb4043ce20cae2d06fd077dd98cd840e49ef641894f2c067dc22c23fdf3305955ee6f4b7814fd8b9cfa8c3adfba33439d3bc86974e0b7ad5dddc76d3451022b3c49231d70e909d0254f300072903cd5df51a37bb18293952658a6e6469658b2e49a79010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5c88c1ede9c41a12a48a31f9194942f01989ac3b490075dbef38a87792516788d4c416ef8038893bc51b331c9995e39c542e875935569ea0f72459117c44cf07	1611228944000000	1611833744000000	1674905744000000	1769513744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e6ca976dba3577b0bc95735d192c02c3a17958e4b83543773f7379fac3094978a47cfac52e1ab65dd7393e338516b2318ddd2070a924e5c10b1b7942b2eec55	\\x00800003e2c7fbe1747c841f935632a2de6163f84e1492bdfcd1715fd56ba26fa13ef596e90ec6526d9f5996e37655cb4295ddf7452fc4462da71a9ba96ef27d0c990dab7ae7d4ba39648e1d7f82b8c264d2b56babb89d10637d6501623d838b4d36cac59de780d190f1c798ec847755712c83a907693ec16ef311c112a4fde7d93f4a87010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x73d460b323b1ded2a4cdbf818e93ccdf2fc630751e0f0923941352d3be22e2f28f267b8d0ee8422eb1b48dfa1be2784b256f34021d4fcc539532fdcdce519106	1637222444000000	1637827244000000	1700899244000000	1795507244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x427c178d395ddbac81c1218acc5e9130fc24f76a2487a121d83aec0650e4a0748e74451559da3f0e941f95291d99087de3b34c445c1039478f7c7cf3cae036c2	\\x00800003d4d19f4a59dc7c7bbb083766f43214b2d333fbbf9f7834008ad719516816d9b6ec89972749ce66db651b17017133361159b0d41a9efa4ed325e93ed933222274381dd8ad332ce6394318fd9fcbe7ccb004766a800fc8673bb15dcb0887ac901fedaa2945efd286aaba28081fddd49bb201aee610d89d85d80bd0b371d1f402cd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xec1c240dd1a741860bc96e7637bd55087e9b4581b10f54b6c462acddb505a952ca617e65eda56bddea5cdea298f2ccd81cce95ce7bed0cc08c68b8f563503008	1623318944000000	1623923744000000	1686995744000000	1781603744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x436c2f37b9463350d9bbce366411f7bc3a89ced0ea4f18c23afbf964f0331d605f16e75306bdd3187f5406a3cd9f1263004874d79dd33da484b26269e147085d	\\x00800003c3df0e07d25a55193a9c7816db1c99848b3469e41283501ea70c17506eaf83f7d55c315389cd4fe304c216c511351f312c54ed2e9bcf48f1a6c136c0e1b2ecf8f8ab3e9f6e1f5bf466753b06e88bd965e0d01b7ac22b65a12edd3670f3bab7e113dbe7d06fc00771650a1a062a24164c499b387c4df85f439c15c531a67f026f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6796b2adcb27f92cbcd0bf42a3fe6d9d53bbb7e6aa54a2975b87879f8ada698039630449473a071d62f9f487578a4f9931132f7165d184567d704bcb6e742d0e	1626341444000000	1626946244000000	1690018244000000	1784626244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4334e021f537bd4c9b81af1755ee1b4f0efb7215be2dc6887e9565c4cf89623fac75e0d850b2300a20379a8c6edee29ae1a517760ba497486b31327402007832	\\x00800003bfed10c19734c6365db076feb0b38b8e3fbcd6972d9a9dbd9e7ca8ec0af1afba62e156ca4fb91ba62359e6d045b8c5e1c04cf45f3f4084d3f891aa33dbc61ba6f0db3ab01da8b83109321f35e27382cc778e67ff7a03acc096f84c41cda632e0beef15c73749ef58fa7014321b764fbf7cfd41e70b9c605fe8479479b1dcc6fb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5176a045c94eebd0f553eefc1d1481b9af374486c981c50ccdac593b67e57e79b67ef61e1b3d19d2c5189cd991dea6503273a05400fd59ee5b1a1528e6632f01	1636617944000000	1637222744000000	1700294744000000	1794902744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4400738094998c9ffe5bc1fe1f6e241452b8449cabbee2b83d148bd653ee840a576428a15c227b0ec0b46e28c4e6c7228513e7571d5f02ff86adda42f1032a36	\\x00800003c45d6e3099b5cfb4c699924be251cf7a89e9d2303e57a2a1fc6fd3c0d825aff1e13cc01d287952003b90b1affc17546e70ba911840f5ca03b6ce27d365654cc72339c8bfb0f02205da2ef9e01afd5387cfc0ecf200b4e19b1883aaa59956a7da3761612896ca493eaa9ec3c05851b3456c57dc9462df1d747497902b22d38989010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd44815ea326e6a5be284aefa6cfcc33e6d52df5ac78af63110b30c83b78cbba3ba7a5a18d4b5df00024c381b5e6fb4a126e4fa3a9344900b35c8b722fb80810c	1635408944000000	1636013744000000	1699085744000000	1793693744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44a0cb59872e178a741080bc4ad2a1aacfb43c6212ff7c7b201492c7e5dae324c47d30dbae34127b0e662ab0debb136b264c0314bf77c1d0c58a1f79a23af374	\\x00800003cb608adad1a94a9689d3dc6f4475aa77850cac36eb877bf60d992c16d2150fd96e2006cf81f9dfa761a2e66b74b3130740bef7d57ea96a9b0df71107dacd9bf62734e34542a50d698e1949563ec139b38b77d10d56cc1418e04e702d87b088938f9c17277b1232da48917c9192630e2fd3c3c078625b5c1d4ecdbd834e977ccf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6aa5c2acb14512368cd8ba2466087a479f55fe2319140c2f834fbf0a7cbf53fd363ab4686144edf371f944954190006847fc6b26e1b27cbdf405690925480809	1631781944000000	1632386744000000	1695458744000000	1790066744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47b88ed5ca3a0d36b00cff6fedcb92814fe3cb451b93e868aa4aa54b2eb063f369222bc62eef6d5ab9fba3150c7a128734df8a621e0c4bf578e5b748f1969bd0	\\x00800003ba2f16a3876a7c1a93a43df8d8884d6daf067298b714eb2fdc1b7455914f3903e5c0d3aaaf1274af32e4014373a8458b7978df6b06407864f5166e2465909c73169f5817e21dd711bb2556ac7a3c7c7bc20362eeef181fbb23fdbdfb5c35c1351c0bc7fcce0f4380fabb7122d7fd2668c54a89f8182832c0f3fb5e4cd4a215d7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe139ec8e45e09524381794278bc6903529d3485faa2892ca5599680e109dc46e4dcc813f7727c19a007788fa2ba2c2aa9c5f2452e5e4fafca8d7f4fba1b0be05	1610019944000000	1610624744000000	1673696744000000	1768304744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4874bc54f511ae443c0256e007b5862e19f8847b7c6ebd041518c6733cffa05efddfb37fdba9fa937c25eb5b74903be76b55be4543f249b86d3725c4de9c2040	\\x00800003bdf5b682d6e7bc53c671b5c52ebf21b2930882c920015d44e3ecdd81ac89751a3951b03b5f7f0ef483e0a2db3212bcadc321904736eac6aa77d3c934c12cafdfd653488ea618706e4893ae71a0e84f24add9feab906b6a14dda0b288181305193680f84659235dd94e9db02bcb28f858346cb3263779f2b59342a93c955c9f79010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb7381faa1403466a225964c1341ab8b5fc4922e99bd687f4a87eb658fe00b103cccbcc9a871fa81538a6f6268d6b871be0b8827cbac9eaadc0043d9d97cb4b0d	1620296444000000	1620901244000000	1683973244000000	1778581244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48ecca29a070bc7adaaeab8f5ac0dc9c8a82076283476fee2adc5ebedf0ebb2452059476a7f5ea77ab71a69ed5ce184d0e2a154d25dce17d9e3bac95e772359e	\\x00800003b2019ba56f8e264b3ea61bc9727aaef31310b781dcee062d4ffbe9478cc9a017576deba04fdba030b191aa421ce1823db39edb124f8d0e499353f4fdef4fcdca24bf073049d94a8e9eb168458efa5cf40b7a02680cf14ab8e28296b2eb36eabde3195214cdeac0cef25fff2b5a8532a21f51250a2308482d50804e05a9a27ced010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x05d65c507fc4839fdd9f5b13cdcc83eec0e0d2ded160f85e3c62339b8cefbe863114023d5e445b0351c498e8389088288565941fbf587e723445b8d7fd8fbf0e	1637826944000000	1638431744000000	1701503744000000	1796111744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x48c0d4ecbac266deea701bf9bb1950c3bf6ac8d6087826b5b165a416cc8f2b04447a8e227554397298bd537c33fae99ad2bf6857f6b5b1370c8e000c6923cf87	\\x00800003b85c51088941221fa7999a156adff5d3861cc997ca24e0625f9e17bdfd8cc333008de114c06031565ba8c5ee8c1708c704aaacac36df6107dbefc0958a7aa2170fbca84b33c81e7b07017684c9557f554c7c0ccdfff4e1c281ae95c192402fcc78f54dac051ec17563bb1e7e17823fc91dbee6c2ff6fa4e8346bb1171a44f831010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4babe1b902b5aba420ddef25d0630a31a673ab766b2b5c788ab53b0a6795388bafeaea189b6afc6c53a326a315a3308966b0c6bb5d7345774731a919e8cfb60d	1634199944000000	1634804744000000	1697876744000000	1792484744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x484014b2040e3ce83269f323e73d8091ca39ad710d77cc5bb5062918266fb55536f49b68c5197241f1be0d74d49b37598187aa7228976e08af2d046676b538ec	\\x00800003abc9a5900d9b180efd233fc3fcadf6c70dc1063481aabb74db0e9ad5bf0928b49422d6d1f3ba33c3fb9135757e7e29fd2478a7797c6544d13dad2ee62c04fa5b6027e146e962c0b3f7939be02bb8e6300d780a4e0ea5ae1a6a9c176205132a7f8c3797b49366e02ae3de60db54e432923b63322a25e0183d96c3542c3f5003a9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe1363442ce9dfd3cea9bb672dac8c555f5d3846901d39bb920e9bdcbebd2685a30bc5c5c145ae49aa68638cc53e3797a4fff67d69fb60e6ebfb99244d2a10c09	1617878444000000	1618483244000000	1681555244000000	1776163244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x495043952b71c32078fb9265c8917361f4d9d8a1b4a7d9c9ba84b0c664298fafd34f15113117ff25ff2dd5b5f0d565211358a7302de117ff4f20821f73918a18	\\x00800003aac98f2293bec9b3ea868353fad46a95bf132b25d59390410df8d8004619a0e051a675705091678071b9a4a3e04453198b97c96b9daf4e17da5342438a9f31a146f9f3a6e6e07c36692fd02c4ec1b00014cc98d79a64da195dcd1f42be5f5cbc6389c5a147573072cb0dc23db6ce081a397e9ca98b40ddca38f8ffadabb7cb13010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x724cfe8d13f5a9e2919afbdcdb5bf9d4346d8eb9c68307630435161c1683172e2166d93096d254bc2934dd4e57af9bd676f607cf39589626fc9dee5efe68a70c	1608810944000000	1609415744000000	1672487744000000	1767095744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4de450715fb00a2f81e76e13a192ff6493389968f3b6dd8931d6ae950df48926250cef01948bc91742487f6dadb2d787a62b9fe33ed77ce6341737caf650838d	\\x00800003b6b3b504517f7e9f8c9e49eb36e86f65789c1d14b450c71b5b466a1f9ecf6391bfd40a7c2f5b7ac1fe29316e21852d9cb9879b27f3cf24fbd5b59eb96683768a37d27abb41cfba5c3df7fd4bbc40188d83a8ac19af24737b5da15ba7f5b5ce4ee5894f2c04faf57092af3b17553b96a6ec59d996d3e220c3a32672f6f6492d59010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x844c967d1ba46b0af1a2c9c4781a3144b4793b0089dceb63dc55a57d47a1c6da8d3596e2a71dd71dec3cbc0c5fc74702eb9455e1400e3814e8ec07cac309b708	1623318944000000	1623923744000000	1686995744000000	1781603744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50705ee050c2e0f6db44f8d2838797aeaca55e152bdadfb91e42e2b47f4ddd51c88166f04e6b307470e3ae077cca75011ff6cc698d63e95d7f08b79ef0b5adce	\\x00800003b4e1eabfaf834bfbc7bb08d36afc453c11b3e96b16e4d61c973f2a6250d133f53df79086f07e20b2d0eec83f515a87b0f432b5372fb55e9abf2879b664ccaa3e6e462a48a70e0da35d0c9b6e5a668b6ceb7aa9bb511e1ac2e041550563d8b5e59701bd07c14f83926d3ad03d47b0ca62ab8ac6f0740e1286cb0d68f300605425010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2da9ca3ddc355b94b525f13e9830e1ba8776faed0260ea28e352ff81fd6299d4eaa2758bcb5689036319dfe7c52a5ebd60759f5b1dc61f6677b8fdd5a9a08a01	1615460444000000	1616065244000000	1679137244000000	1773745244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x553caef6a3b84e3fb4dbce940c35457ef96c970b37e2d1722b9e84d58594f6f9f7aa5fa2111784193e0bc5c0bde201f07292c4ad4792a0ba895c2f28cdb110be	\\x00800003c8575f5b90962e1b724b77e47f0550ab87dd14ec3170545337c0e83079145f9e9026b4469125f484fba445734bfec27c95eb455eedbf35da198eb04c40d08677036a5c3766a921274127303e040c961313398baf30eed84028f9216b5a87f7b306d6df249783f0d18df2c735c612cf724b0352aaaee62f0a3cb48b3118ba6141010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x51f746d9220a22bcc1e579baf43d16d342d1d4577cb2ea1f91b3fbb126fc700152d326e32e470796ea89878a5a5d975806c83f266907b17de49ded224a700307	1632386444000000	1632991244000000	1696063244000000	1790671244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x597c04e77118b35522588ca1d129598b43b66d50eef4442d367ebe5edf7f059f0e1248d622f6123d62db8e75372838acebc4143625fe277a89aa04000877848b	\\x00800003d421996b27b00e6dfca42409a1292f11d61589c8402097adb4acb583b62039bc347fb9d01148663b4c4a0ba3ca1dea40e88656790a7157e148f7ebf879c5237d0450444045cd2dcba1748c96254193d3c36c467986234ab8f09d32672d20a1c95ab8c4799f957afcb83833f201999a971a2a5952e51910df6223097fe52ac7f5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb7629c8c06935ade2bb89f601f32a8d9c93a96be95cd95a5bd878f618519f66d3f5b7885d356aae9165d181241ed9f6a92a4417baad6b0b8cc2b43386e0b5802	1629968444000000	1630573244000000	1693645244000000	1788253244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5a9cb89018959e7fe76601bfe8eefd286c23f6b60dcd0442d338cf55efd9355d0bd4d6e9d00fe75531f589faeec04547839bb19d45e1dfdd93d13792e7585bb8	\\x00800003d55e1d4b43b2ce11652aa9010fdfe83ea515a1527955eb7f1931f2e4155fbf4ecfa32aa1cdaef6e7dbc3f2cd8b799b0c7a4383c11da84a5cc748729e07b0c643a001a8134b7149c33879c5e78a09bac54a24f0c9ca8861999836c83bce7c981cf30a9375c7315b5a41b76329dd6f3964162f487d11ad479f40f9c7a5e3d93f81010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf9d0b4f813ae82a94111fb494d09ede7b6cde54f672702f51e182e91f11a15f0aed1c3dca8d07327c5d961de8abf6947d67f7dc13867f7068425cb464b50a807	1620900944000000	1621505744000000	1684577744000000	1779185744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5a0caee9b8e20922fb6694d43729ccb8f6668f3231f714197855c0239c8bd6c4b0a26b5e3c382616ca8be939140f23c096d1d421e38c8e5d56fa800d4c4d48b0	\\x00800003b0043b816807df0d2169d96a35138aaab640b2d2de95cb5d8c9d6d9352a2c6a219c317f54444e2e1cce51df9a611b3679954edaa9db4c7c1c34783ef08fbd5baf1140493ad6c8bf3a0e2c93f0fa2f2131812e365c00367d6fea91cbb3ea08f9b12fc2def0f45229026f24508908aa6c336b4bef788d75245ac01426a7c0b7f79010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3131ae4ce22784e90fc627b1951ebbc7a9a15c5bed10aa036c97ab1b9739eedbf224041e653b15c639ebf52b53924cfa8a57e5c11a8602b4fcc74b7e1eebbf05	1636013444000000	1636618244000000	1699690244000000	1794298244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ed48ba8f69920996bf934b734b194d7deaa770d9831dbab65d369cb19d9f9db1ec033af0aa4986898908df1332ebc73e0ab16c18419c241354f61a55aac4743	\\x00800003db97ec7c9a996bd12f4abd5b50e8f94554245daae7654aba10db421e36ba6c59c4cb636a8565c6d387dcd6a8f6715a9f00c3dabb4eba204b2930d1ae57b620aeb41abe91f73012ae0fb8e6915265481b84f0d1c64151fd87812a58cbd9ce0ffb788ec3cf2c3446b76ce718e10c7a125eca9c2b4cb8479df98b4c174ee80585a7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xddc6af962335c5ae198f8ddf3f4b89f252060125bb465cf1b4dfcf36fa2357434ea3c94ff028941bdfc0ffd61a7eec50be9c36259d2c8207d4978a95df5aac07	1610624444000000	1611229244000000	1674301244000000	1768909244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5ff00e0831b0eb486f65d1d7e4a2fefb1576d568bf0f3993802662e7d3305152d99498a1950ca8834a661b40995dac9dd57de553dc306ba059d8b454daa2de19	\\x00800003c0de024cd37acd58aba5b5696c4fe432d5ac06af76803c74c17083f7b9aea384829c916ac6752ea165fbc64afc0938ff321eb15ded327fd9d573251bc86b8437a282fee88e671cd9d5cf968830c0fb48025c5bee086ba7130874f6b1dfe38e1210da7cfdd8c183229fe6de8853d69836f5f15412cc7c9ba8148820ddf9b8aee9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5ad6a644feed4e3653bcbb33a9dfbe7cef90f535dd0aab27baf373ec12807f0ca4210055ba72fe242c4dd0e1cec8719cd2fc00c32a508d3585dadd2adf123806	1639035944000000	1639640744000000	1702712744000000	1797320744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x60c86a0b972ef007434070bc42d33dca849084c2dc2bd15216d7b12e68a9babed32f53f06c6b4ca295802ccb124f30864db0872e523743483176cf3f89c070ff	\\x00800003b18c007fdc619d722fe1f41d012890af0ee593bbc8e13a0920a3279de876064122ac8ee2896adde5c0fbc88fcc500a3117f5db7ac28a007b91766ac93f049ec175fa0bb79fc0d698f2211ed06eec4ac47e74f214503018f73621b4ea5219b3ae0e20cfd97454c4f3f188f693e948f009035f1e79565ea4e3f5a968ee3aafda51010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x40f323aa99fddccc38b7463180ab773e154470b83a9bc3bad509fadff6da5d857c254b5b800f68aa96a861a687ef6ff9046cba797ba74c66125e5445170d670e	1634199944000000	1634804744000000	1697876744000000	1792484744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x60e48638550c918dc90b5bad76269116e8f3a9c5c119a68b1c0f657bde6c0ac13161ba6f03f6d3827068ac5a1be9d7170046608f0ccc22412e20f7b4f16211dc	\\x00800003df36fc0276a8b0903dba6c66951cf21512657dd0e5821ead2ff9263779c88d348d77dcd9180a3a19af06f819b45c0ebe5fe91432427e2b0dff31eef38139ce60da064c189a2fea025f177b7920675cab1dcfaf0d97c53d623d97851fd263f94fc92684b0e13df0888b18bd24e982a921e2cbe946047cdb0c72c5f492da6f5fbb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x985e1639da35a3de17d32a85f41e190d1896541316f16ce870c3e0fca7602f031bae919e8376fe94f08093348298b7cc1a10bfcc31a6f9cd26c665b6aa47a40e	1609415444000000	1610020244000000	1673092244000000	1767700244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x60d8d5ad1c5c5c5c5b3fc07f98ac170b7e8b50dd8f63a8ad78a4d71ee87611ba5e3b657b2376443d8d2917a86d12f6e7e8be90a106d45ef2d84c11692323d188	\\x00800003f486929f49c8e2d7a6103662c7ae64a1a1df4056f01f936101f36c5759552f0a948af7cf3e6e662030f4675b48ac7c44cf1bf0b1e17040c1b644bcbec9c0913fbdece12b9cf9a4daf548b9c162d7f5d7ea18bdeabd415fb23605fe27d2bbf08d4bf0a923989bbfb741e0cbfc4cf7b241b1253a4115ccaecf356ad31479f3e9b9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x913b7cc5adcb33cb2f20cdbd6770546becf6f1c2fd29707398cae23a0c209e4585f5b5c3ee1cce0e76c901a6475df1555abb5c140d57f8aaf8370a33fbaaf200	1634804444000000	1635409244000000	1698481244000000	1793089244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x62040a7efdb071dd4fd42da76b9d39cd85e3d2e3e0e0aa2ddd41ca8ec0f098dcb16ad49a1185f186d10301dd405f4123ca7a65b9ac2d3432ea722f266c632719	\\x00800003bf1a76b55bbc9effd661c0d4d047b847c3eca347e14020a00af816ea3a51bfce85c45618097210489d5611189f11528b9bfa32722be3e801bd97934d06eb0a8b6c560bd34076313fd6088bd655238f56ed0e1169da5e444c56d4fd0cc38cd7c6ca4d3d9f6ae782e41e67b5d0805932b2a4bf55b8c03df223aefab5a2e637c4fb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x97b064b6365ca865823b3af5ca101c6289ca32a5731b7636d1d33f7b60023d9f0ed0d3bae6fcf57c8a99ea514eb821ed4f5765d83941698c7ece18b82830aa04	1634199944000000	1634804744000000	1697876744000000	1792484744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x63284d72bb0911e7fee88cf88bffc7b7314bcade4af138013bd6522bebef27383bc4785099739210181aec7e6ae33a924cf025758d3be767f0de2895713388f7	\\x00800003cb8eac62b1c3e4fcfa76e5dcbce62e4f65e6bcb025e3518c9a649b9aaef800c5a50dc5d0da54c49528b2b4b116f055ef247c3f03d82bb09a0852a24c37f126b675a066ca85a9c77e09af5b48ac614fe1436f9515dac3ff79182382b043f968b6c7716d94357637720c66e22b3856656342514e46feb2db8586fe6e265830ae93010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6702711ffc17ee2b0584df6e4f47aceb682cfba22a8c270b99d3d7f3c5ef1c01f0356488a5299c509d2667fa3b8493c7c11f14b34661b9489f10ad7de8c8e709	1629968444000000	1630573244000000	1693645244000000	1788253244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x655801caa4c0439f711d2e25580f7eaadbc1f7423308b88e24150b2cb1db801d21bf6f8844dee38ef0344c003037b5f508eb11f4294165cb42bc0028040665da	\\x00800003a2d3a6451998220e7bb772ceaf79f220bd52d053f207dfa1b6e69bcb664edab7a121c8758dd1bc34f4381d35e63767e8181b9aecad0bf4be4a2d0b1c56797e4c1d741acc64b9328353e3b98ae572667f83f70403d47d9b66cd8ae0798536bade64bc5d354d9d757a508e7e06e72e92f157502d99706279e73b26f23e13c4fc23010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3403787d586fd6e1ad6f6d4f1c9c149a56f2e03d6c9d9d8c4e3047b38ca6cd7fe3577add8a8ec279a23ca9a5fdecc9b132dae0d04f48b742388e00e8658bd00d	1620296444000000	1620901244000000	1683973244000000	1778581244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x66c89280b4fe4b91d9df92a5dd329f3201e6387c1c4697e4d67a3a9e40de47db29978b7361218994ee35d337c525cb703813d70dd821316803d19f911e33fed0	\\x00800003d94a4f9aacda43e343b71b4765612076efaa3b7c016f673c4546d23e61b8b7ba82d47b5fb8d18ed5227b3dcbcbf6e81429f198584781670f02a408e1dd00090ba99601171f4ba9701cab765a8ac7f14ec9282a70a6939c56920eb19a31a1a91e16beb398fcadb8ddb87eff1671c62777deddf5646acc305b1e59c5f7a89ee58f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x35f84faef2606b0e8da7e0498702c705d1b80ce2b9f4f79c4765c23951c6f7cbc5e9be86818d78d962c966034e4573d1f29e0bfc164cb0aac4efd81ed6c31509	1633595444000000	1634200244000000	1697272244000000	1791880244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ae44c5d9d1da3bd1101cb959044e049df6c4ac15080c4eea6c6ca620b85fed356b87e5a47fdbbe7626dbc179fef0da13a51d46155f1adced76fc3ad39702b7a	\\x00800003d5a40f346045afa5b897cdde188c2acf016582d63397a49fc7787b5ca72bbda422a04bc334354a73f7b1c0b3407bfd9cc048b1c3ca003122aaed77085369210f59ae8662e171d63c63d02314b988fe76ccf8c40a9402755e9443fdbbee159ae442b7cb0beefc3247ef8128aa919a9dfd83f96c9cba7759c5149520af5b5ddad7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6764279e185c487d50deb1c430a22f38049750e1ff21c4eb0b1a3aed9d810adc62da571b744aa4d82cfced470e0ee3e3b1072b8e01e15e94add6aa582cca480c	1609415444000000	1610020244000000	1673092244000000	1767700244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a582bb8a6d1949e9f5de5f7bf3ed2403c73ec96e404ec852ac589f7d1311779662a603da90078f04605b330992bb86f52fb8f00f8ffc6ee09859920e6dd0cd3	\\x00800003d3324eaad7806f4c3131c01a07c4c6f6dab55b2cb3b339ddf7f0c409824c1d3176e368e909530475bffcec8d1d26306caa6019e949b7d994fa8d8c607541b3e5d505b4f2637fe560b1335bdd88f7543eba2978de09fef697384a287ac33a824cebfece403c567198b7ac3ef5082d9bbc96973b3d9f90b425f73904d778b03b63010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd3dfa57e5a566106af7e3c218a8f7313ed2cf62a98282ec18520dd8fa8757805cd60f5de51defd578cb978bb85b612ab137fb5cd3682292e45c657b7e105720f	1623318944000000	1623923744000000	1686995744000000	1781603744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6baccb3f3d599b9e6a2d76437cd0435f8907da2ed0be4dfe1b33da403250480135f0ed6ec326b6a45e3824551dba24c1dc735918eab62882cade7200d6627c08	\\x00800003e038c7e0b4b29bd06bc4a6748fa39e6c66f50915ca0193a8b548b5f7fde56cf076de97e0e6f126eeabb49758627b435d93fb3c00c5d538e9cbabadc8e9a9fa942776a36319a2a5b1599ed75d44f742400696c5044e19c3df54c8aee63a52a2435620a3762eebbeafdca375b927171a4f716f77872c5dc2a619aee3a76f3386b3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2f7a07902183a614192aeb9755d34030fb7b3233971188ddbb9a11fa72b64612eaef2c5a25976fa4af7c7a085f98ce7ad947a17a4b11f2ac8406deeb70559a02	1619087444000000	1619692244000000	1682764244000000	1777372244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6b6c6e3a5d54cd9f63bacb40d0184713e2677f035a99520eaf1db3adafe691c712f54b741de721240c09faae2a9d7b0bc1f89d991dc359cfc2839d00ee968f96	\\x00800003dea58e9f87850b8082d20d4149be2376f469911e343e61d4efe02e25b4eda8b0d746a8c7c17e63c9844aefeb6ae9fede8d630e794aa6e9c96d09145d84f2ebafbe2001a7c57079a288255a54ba33e7153187e7cb4a787b384d298c9bd2b18167149ef3598de8baf8f43862f9280958af59f455625816fbf3fe34e6fd2050e9ff010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4159e1e58a17a481d3e187bdb481c1f0981978ca42b2fc1b555828eb6723293a2a8bbcf37f26b4ffa923aecb8d213c5eb8bd20b9d02055d07c84ef0c3c9be008	1626341444000000	1626946244000000	1690018244000000	1784626244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c68013ebeb06729ea0afc3f02b59dfe0713ba188711fccf72da9a29dfd39234448e93df4c50df5b2dfdd0883d100499e8037beecd82a78148b90b62e40edc97	\\x00800003cdea0ac8caaf4b7d2be0c3f281e2df1b470019c83eefdc4eaaaf07a815ae592463c7739396f595467b90a26863b258f12fe7b51b96fe9ab1f6a13095fa74c1a8d959877a278b10c67940ba2ed20c4f5416bbe8aeb8744386d6117972e0900ea545d806430ecf364cdf984fb092f108cb4f91c398aa33b71ab2077b16b75cfe91010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd8ba13e05fc6ae4cc6b30917b11a85c439f92a8a3c372fed3fb395ce5299bc21f9f8635da2e88d113660396c87cc25059dfa84630eb53c9dd1f4d44e71009001	1624527944000000	1625132744000000	1688204744000000	1782812744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c58a4e16e018839b2bd650d59706dfb91a0cf67618ebbbda8db56f855cda4c3aed10736c815d66fbef39e04241de910e409243f463ba4a24aba89d71be50a47	\\x00800003b27710b4c1026d543d274ad6b3c047622c690eea1198d006b2987b1e400dd17d6420ec9959793553225b647b762f8d1831bd1c8658364b97168a565c37a01d32accd7ac6a36e005606618d5e74a05ce97da94d3f2b961abd7081f0dade13d877f68c782abc69d34fe93d4331145cbc0a11228ad0a6209d91f4b9dbac9414eb71010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0be61b857ab0952a2b4a919f15ebd044b312798b50e01de0fbcb9ed8032d150feb77b59820c7c844b84b94e624d926ab4501936b33d5781b780213766c18910c	1632386444000000	1632991244000000	1696063244000000	1790671244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c84480890d89385197bdd88608683c04b2c4d343bd58566da86f64e799386eb087bfc84975a35f74e2e29ccc80f2e41aed6199b9bd1e9128308e06ec2c69ff0	\\x00800003bb050166d70d6f46d59e0c0c2329a967c9d0d456ed7b5cd7cc7ec222c02dda1193cd75cb26cca876a19afed4516cc1dea2d51bd4afae65efc2a05bc70347a8c2fab62c7449671ca239eb6957faeb4cb878924affbf01475b11ce2795ec79ee9746c48cc7adca89960731dda76e043b1507bf8f30f053bde20281a06237a8ac5f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3c7c26ba804dd834ce30718647990e614a70a95bcefd35a80fe1719490460ff8a493193b4b7556889b2d578e214fea1a2a653440cc2603891c31a07ceec5c205	1620900944000000	1621505744000000	1684577744000000	1779185744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e3c0662f611038a9bdf64adcfdf4948226a34011df96fa569959258fcc356d8924ae403d21e633127021e85c56614f4e9fad969d5c70753684cf9f4e63944d1	\\x00800003f1c6bef7cd14cdeeed6be3ad3b814ad2daaa680866d2d96d7174a6e600884be09542ba61332d9e0bde2c26e2cac4e08f7fc06f0ed6949a6dbea7ca63125744298b62b2b776015254a4c793e1a24206e43fa49ade008dbef2f8c49adfb71d64f3f1c9d615536e032a2ce9c2ca25870001c4d0bbc33a9680b73c3cf1e90a719fa5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1549228cddd69a58682d6692c36a799dbcd22f267d9b8089bd5ec8de435178e20a6470be9acd945d6dc2a3c7bbd8218d6cefff2d0df0c4d4a401b5445a543605	1628759444000000	1629364244000000	1692436244000000	1787044244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6fa0ce4a33ee961bf8a2b2f28ab2db3bea3744975b32dfa89604b875ccea06ac87d0bde248f4ab822fadabea43b15018cd2959c403ace9bde66de0b37701ace1	\\x00800003c688ec2acb81fcb07f23015072c98582ba39cf076f82ad9e0a24c19629cc925f2f55ebb090d756f03f712b6ba905fb69c4e57e1c5204c75cbdda1a2d5f01cd75b11f8c0b0cf081b0b5ce89db9715b8e8e86c55eb98e9deb40ccaef972fd44279c4c1d92bc118d2b4481a42780bdd3282893975b8762dd27f92f944548aad77f5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xce332164d1923190bbd822591f24c8cc01016b3b3bea8f21adea28d7a69385cbb2aed2557777a0eb10b9aa145723aa48996fddf283c57687b0404947f0596e0b	1613646944000000	1614251744000000	1677323744000000	1771931744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70b488eae74a448de3faf99ce9d8b09f1311c40319afc710187ed5c7fe38d4a95ae5c5e9274715fbcee518cdd02a47f945a29d928726a13598091c63fd2fa472	\\x00800003d793b3ef06cd1575cd7c2cfd5a3183533cf30d7f7496a1f11b0245bc7a95a0133e6c7d44a3d4845d53cc0afed5a6a9eea3a7843bd3be8c5e01268ec7b9f9414f3f0b3152fffcd7ab8ae5aee508b0d87481ea1f2ddd60dc75bd2ef04d8ec11f4aa71088724e57619604f562d51ce426784556ea8e43d09d5971f7d18e0e3c77e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7ac1f3e600436b8eba159f1724cc98b563e019c7e964a334be209ce7e88d741b58a3a5acbcbb6721e7b3ac71f8f964d0f3045d34afeca3faadb6dc61cac6880b	1636617944000000	1637222744000000	1700294744000000	1794902744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7424e467f191e09f7c78eaab914dabb747858779da66af38ea8f2953133e325ca195d6640a04a87dca74503e2e2e2d6f56bb90fded199ea57f94c4100e7ea7e0	\\x00800003c0d9c753c302039e4672ca783a5439f52eb76a90bcf77319db1647f62354c6b22e517007b323f255ebc1965a80c1a9528a7f04c11c5cece99b11a7bca31204c52a27d55875180ab888caf9dd5d4c1991b79c56b39c773d38919eb7ab46cde6f5681ececbff17a27854353559e8617fd58295d34c876f80078a411450e60e851f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe246c6aa11c685a03db101c595410ca11643ec0553f71840c764528b7791a719b67e26c70e33c025ead516f7e0975a99424fb086011190b7435889865610d50f	1638431444000000	1639036244000000	1702108244000000	1796716244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7580c92c82b922c202a9dd802632e0402acaee371c31f626a1cb74208b5f29766c06cb9c2fad9654af2443260d4f700e28aeb0988ccf216f216e6ecece43742c	\\x00800003bbf796b3dd6541aeb97d52ebc52cab963e8dc21526a21d6993025bab1fb975c9b84a2bb8226e49a5291a0fe34197fde488db2c7d06eab554688add08f1fce8388a6ffb8485bff2c4977807efd3e33da4103e350ec4dbfd13bca1aa93bb9c7a7855ccadc56ad0ae5a434bf4e7df83924640fefed9a3d3719ef5b707f21be7beff010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x05186c1ea1eac15d704417af6c62f7099b855b24f07caeb15c3d087bdc1168c464a1106eab489b7fed1f76de94f3a3f242e98d3fd27fd863b3aa4d9c46ed450e	1609415444000000	1610020244000000	1673092244000000	1767700244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d24118b78d4551c3bb8b84739206764c37fbb648d4ceda23f1728ac65e52bd8fdfba58628ca36a923a12558923bcc1643a2546e1fa8f705f89cd43cb63ffa70	\\x00800003ce61e4cb0b9596a9cbd7684945aedde45a35e3acd613dfba8ba1319200e843301c0c4fa5c165b6defd6f5a38b295c3def34425cf822913d61ff1aa699d2662e6d9b41a657fed3e7d3d19f1aea890f091db2ec267daf25313b5503111cdd03c0c5c77a30da3feff7a1c736d43be5d750a25f2e2b46c02b2efd2a1bb8f3f538697010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa4d2f9146c2c9ca349ed0f7d337274fc4feb6288bd65db76d80396d365830fbf2494ea8e7fa206c07e3cda312509a687580e06990e28b858f28fabd10074c90d	1627550444000000	1628155244000000	1691227244000000	1785835244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7dc81ad63e1c52173382ceca6a7b969316f58fe6cc6ffa73c9b3e99b5f05ac84a20d3eeb903466697203240910a8d8f1792788272b40faee3b87cc8509f76856	\\x00800003a26c7eaf91736508be1f0f99c158960a7ac764c70baf305574285e0d6cabde595aa5228471c0ec3140e008f008b51a47fea759a1ce53d4d24acb7e0b44fe7e75a52153a777544544ba368b39e6e4904b61c6e9b1c859ca2a17451ed8a35bf4eec322b3ce341d76ffdb136c0e8495d7712dbca0b5e9af9b4ba038b64ad71ba299010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x334a449c8126ffbf1ae14d9817008c1bdd8fd26d3ac2d36138ef1db222881c17927499ffae82acb15ecfcfac6a37d6a0580d30071865874952bbf974ae8b0500	1622714444000000	1623319244000000	1686391244000000	1780999244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e9ce03c32a33ceb8b2581205eaef24db6654a91bb9461a8c65ed677ad4aa677eb65d43d6a4dde2f755c447f64550965e98c783ae59413e9f07e0dd7246a3a5d	\\x00800003cada52da936aa257aad99fa68241f802c8ba99b695c8195147e45520dd00466826df694ab0525af1db40bb395478e6eab49a01a00af1ab60828968a9fb1ecc87cbb29262dd3a1a700d03ed70b0d9ab72e178a2c1e9984428c76ae8021852b33494d96e13e368094506b4e45fd25b957b6c3289e1795b0c4e070a9298808e636d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xffd3d0e4be52781bd4a3354abee92d4c6ad18a47ac0e9436367b1f40af1d1f11830241e9e07a3531e43434b96c2e67e0d0fd342e21f7b0e71ba6701392f7f509	1616669444000000	1617274244000000	1680346244000000	1774954244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8364f7d60a8dbb01cdb20bc8e8e63eac49693ce92439eebd9496ff786dfc5d3566ed63b946648d8d1bbb1d94c89cfee81ef7a36cf09546ff5d74d19a8fa3e0a5	\\x00800003c1f644bd72fa5df905c7995017da49972164e9cc0f6c5575f6c44d79489ff563e1423ddbfc6f78ce40859a0fd912d7e7b02097ab29423f864f0a8cfa5633f4049bdaf75ca7205cd383947d2dab92fa199c633df485d572b213a8bc057e9154ed6e0d131314bacf7f47a06db463a94aa9f079ef347312e3070ceb991d38f79613010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf38d8ef0b86818213f1b30182dc64d350022748851cda9612a64724a1af93798143252776d75e6f3652f95d8615a5dcf5e128763e5ab386750f3685e6f697d05	1618482944000000	1619087744000000	1682159744000000	1776767744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8438e7f3ff3a9ddd2afeced690e8d5ae5e972e4a8a7e988cac97240277a2fa7aab305514fc10d9e23fbc6e4ea812ac91e54fa79abd3cfb5b43d2924049b37f39	\\x00800003b5fb0aa14ae31be1ff298190391bc3a0e0617d59f4ebc15cc23b2bbe9f9ec039941807a13b5da13c2487c7fb5baff3875bc12bc9f815fd1545e530bbd1c5eab89c04a23c0ccddbaab0f840c7a0a49fa6e3cacd12d47e2779d92e034f93a78b089c1c9e660d2a908ec76428b0e67438bc4afbdbdf7bb16f443463306455ff984f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb687f2a9cfa632431b7051c459eb8f60eb92d32046a9d719de8331f85d725b063f2396e0bb0362c19088afa35d712436b9cc6834ac7e4df83368a7190045f108	1638431444000000	1639036244000000	1702108244000000	1796716244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x86184c99a4d83b89ecba20b5036b795bac59f3b9c664b422064c36fbb82a47b1db17a317b1c37235f630ebd2dae8061c9077e0ab9cd70fdde9ee5bb4da474dbe	\\x008000039741eba6237ce955c9baeabaf76da28a4e0915c851c1e78a60c851d0414c2227e1c99e0a904c54ab914252295ec8e5f02f04fa26f1262fc9b74705187037703c6098392a78e3e13e4b8f9469ff6cdd9753d36ee170a0fdfcbb85acdeef4b61847b1c52a12f2e7634aece0a24dff7647fc1d2485dd3bf12d0b340482bbfe1f05b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfdb87657d73f0ef39c7f61d9a299916936550cf93b2d644ce5d6d184b05bb003d618dc761ded91e93ce29813cbdf3f3321d84e990fce12d2785213669f5e0900	1619691944000000	1620296744000000	1683368744000000	1777976744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x90181985a4d43487d5e05678acfe2b8d18c7ddc108e2db4ff4f13c0cd5a0d2765837b35acc3651818123ce8d2a4a8688ccc28599009ce5646b25632af55ee199	\\x00800003c132bd7c09aad8dc5b20807567cb21e278f84945d57c463185885723e9f39bd3d149224276898200239630cd9efe7198817feea8f69cab5001754a41db66dfe63931ad3a1d5c5aa86b35e5cfba9966b9e29c2913f2f720b98e52b22e992b6ae26db0dc97a07424730c02c46192d309e92fd50042f057a98d7552a77beda43553010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb2fd80682fb9904de2e864ce8e48729dc2c6e6d048ed3da543390cf9620993ed5560749ec3ba85b1e656ad4b00197fedd5b97056e934ad6b9b1e9fdcbd013103	1632990944000000	1633595744000000	1696667744000000	1791275744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9368a0559bfdc38a09299ac7ac22a948c3709cfd9d9f5b7123c09b2c34350fb387063d3dadfd8ac3ea61ccf8084b8c23eda2be6ec5371fa61566f649ace9a8a8	\\x00800003d9212d6d74668ffd10d32ce04bb1dd95bfa7e2132287b131a472b4c0c3b9874ebad807ca6e8e58d153afb4da71579506074e4499537a7a3138e5659791f37dfd45356f6e8c0727e71ddc612cbbf15a7d864b93359f986cbd0dd476111ce398f91bb137bb68c3bfaa23f6d02ba0924afedd4c82953614710b55b53ed76a519e4b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8c44d50986b99de6e664a7fceeebc0853e8e632398ce204b4832aa87bede9feec7cfed307de926a22a4af9d67e6f58db235703dba1b2db9f71406ebd20cda102	1615460444000000	1616065244000000	1679137244000000	1773745244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x931030e25de79954bd96fc113260486db1465fa6812a32be71b4588e25b21614226b370fcf7b4a4d4434ff67cf0065bc43a2bdeb2469a60b9c3171dae3617834	\\x00800003a1c3cb51be4c5f901abaff10b09f20812375b19bba7c041c151d8a548aa15e78681ec74292c12708f7706ad190203a3c652d239b107022a3b482f30570166c90f37a4ec7d9917236a3ecf00136f6c48dbfb4aa11f3e984614bfa3d8d4685016f4f1b47b5db0b5eebf39391f24a4a5ba088b6bedb7855d07427c37ad790ac081f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbd7db4b03aa4b8ee7855033beb2ca0d78a42d2d7e92363389c663ecb5856ecf5066a0e0fa4eb42adce2abc41b4f3a2bcd19b0e3013a3bccb18144e1fb2efd50d	1617273944000000	1617878744000000	1680950744000000	1775558744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9718909b21b51a2f74afc076816bf21309e576f2e26dbccdf8150112fd45aba1a8547e1591664f597acb85a6b3bbf2a146010e3065e2e9068ddbbac45eca261e	\\x00800003a9f668a04b60f38f4ea92f450d5d67a8f3950bf9d7ee9eb179b187226aae04aa6af350b2593e33e54ffdf158aa176db6d3cf540acfdae190c53b2b51efca51257a4175efcb4a545d22f1783ea65111974e21906e096bccabfffcbe19e0ae2b0d5bef8551e9c287cda1bd8807c3d793cdc9fe4a6e09faf21fe5236824fa05b955010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdde6acee6012c716f34bbd4c0976c9335028f627b88e14bd820beae3eade94f8234cbc6149a6585d2e0bb2cb0753ae8973b1fe17a885117fa74cdccab09ef70a	1628759444000000	1629364244000000	1692436244000000	1787044244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b6473d5a792f71822c4bae9c17e5e8817ce4ab38d6455d669ca4439da2dfa89e3b4fc8dcce171468ae0667615a504500f35759aacac247492c4dd0281d22583	\\x00800003bf4c2382265e7e30fb0ca17512038a91983beec60468871b6d88f6b545028c88a08053e85ad604f3f6c5f20ac179ccb51e5798eadc90721311bf7dc60885bec6b1a2c32eff7d6aab20686e58ab8893e872db67d14263b9e752e333082f4ccbf380022aa092696d6e19a3ef8c94cf93c58312e0e8c8df072649c4a7f53df775e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe812b96b80fa8f851e881fe7900a84db5fdabe80917935b71d33509f667db7a99fddefc0e517b0d75b5ed8a143796edf39bf1f0b3db08057a441c3698ab69100	1626945944000000	1627550744000000	1690622744000000	1785230744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9b3c89d27d5915129fb0271b45ebcc686c74807440d257abcb4a601f570e14ae7846fe49f512e5aefeb068f5110ba1bd877b3809aec4c8df381fc24fa773b35d	\\x00800003d010b1f7cb30ad27b415e112a52572decd4f71415262017589f5c16f3d6de991184a4e77407169d2ea8d7b7d01488f74789089f738df5f000680b2ebac82574ac1a8644e73b82c32b39a60835df3b8ebf390b809076e3908f8570bb5473973805a827245343ec4d87642d32cc1e9f283da21e72b48fb328885fd700d788b119d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcdba48f46feddbb9d98cabb4e7b1475497a3e7ede4253948b7cb7ce01e64cecfde9079afd6de53520cdcacfebb8964d421438a0ec354fddcfa788e3c3b39900c	1622109944000000	1622714744000000	1685786744000000	1780394744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9f3c5bc1f4972cffee3c6ca2405bf9b77acbc01e8a432babdb9bad9473275bfece7d5f1e1db4296d9482dac4e0b3fe21352d5dd6673c70c03b608481d324b184	\\x00800003a32b3e136a6bd591b34c6c712d3dfd7434c1975ac81bfccfed85d1754e911b65344836e42bc704e7620fc8f016c816c5ec6ad4095f8b3a20772a1f77130bdbf77cf177e173df99c49f5abfe7cad4cf4965fabfb3fe70b23b352cd5fb5c39c109c48d2ce1825aa9f6a4d19e6163f1bf98b3c37fbd59610502bf372da3e762d24b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5bd7db202f98b0ee327c7044f63ea449757ef79817a2a69784ef49afcf0cd80bdf957695dfcf529464e720055a28c4a06c011f88ac44ad2705843db9ce39db06	1616064944000000	1616669744000000	1679741744000000	1774349744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa218b360b78a96c76d9bfa18a0627ae01086fdab4d5c11a92efdbcd3f225d9f6073f0c6658404700a3b17aa7682eb08d8eade4b59f0b6c1ee2171b2081348db6	\\x00800003c77fcc2c6429c7e23a4d213f8138c27cc42fb418409da03e96bd5ff24fe9e3968804b695b485a89a2da27c9acecf4438b7ae326cca4dd4539700482c5b170fd6bd96ff71b1d916818d5fd0ab87690e1fc3844d2a0f8bbb8ccdde1db20f8b87832e535b15ed3ecabd430c36ae68e7a318f5514538675b8fc4b030f0e27c23fd6f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9fffa8a2de804ba373355b335b1527d900cacac44e91c892658437c4503fbf298c9287efe8fd8e9d70da495746f0ff0b83c2d0d30bccc35d33b2e659c7aefb0f	1639640444000000	1640245244000000	1703317244000000	1797925244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa2c0fabb3388c68449c2795d22d79a08850b50f80e41bef09cc98bec51a69c79670c877cfb877674ed6b4bf18af03510017dd87f14f23ba7cd4fd48ed7b2dc46	\\x00800003ab899c94182f31ab9e7f9bfdf8e8d7fe54869583eda46b2a913d4f36a6211556b855f19f85157620cb7be6aaadff15c891e8ba1ad024ae27e5c3c29e4379703d12b09ae65c6affb3e5477ca7adb53999d374f8afde19004529ceed3ceb0c2693d1d3b07df864d8f41b18babbaf21b622a314ea9bab8adc10512afc6eb8f54c99010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x413b6b446c8b7baf8038c90719ed6c1025fa293edacab05f81c6a3a7eaff4b9d3c1ac1a8742ed087f5473c55d7433bce431f62ec921bd1d1664c677ce632630b	1617273944000000	1617878744000000	1680950744000000	1775558744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa6d46472f9142b07f94aac9d50a7d93b09c0de41513851c63258dd33a4a4b949ee3d420d47a55588b23660285275ea833beaecf344a504bf9ac9e26b6a2ec013	\\x00800003adc5a524008fb13237d4eb65cb737950b6ae7052234cc746c70221f66be2c10794d41bb8db3ad8ca100145d6b6dc493ebf84f264b4606c6392ca9e72dd515911b288b1a463ae28d7431f23a167a347a119f4ae62cc33c14fd35790d476238968b25af69e6d92448f6855089950612eaa0d754df1a187971b9cc6e49849167763010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdecedd228b6a8853d4a60bc5a45c62cc6065c9549fc0812c3872a470f8611b274ccba49760f4cbeefe2229c2e5c56fd021083f50358195595984db7a54bed20a	1620900944000000	1621505744000000	1684577744000000	1779185744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0a4433d2fcf996c3dfcdb32e6ca2a7c4df1018e57246177ce77b2ab8b4ac020640e9abf1baf4e14b829dc15fda54df5c1e6ae92298efb27c6f73b94929dbd43	\\x00800003d9232a1a4bcec0397656084a9f04dc29c59d23e0b9cc456a11903c5376bf619654a42bd60b6b116b5ced1f288935094db172a01816ac18465ca2191d86e84ed8058091b590b53cdbb7b921099c309829404333c21cbfc0e1438d0277aa7df54e6f7ca3aad3dfcd8150a2d926a16cd28e2be465182b3019b1709f4cf9c5f597d1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x75dd9f3e6d24ac177fa59d707bd04bdf10e73b640ebdd08b2ea1a4a42c3666e3f6a9703e356ad9c3726adf8c99faf5f00a9bf2b080f19c8dbda65e9cdaba2b07	1636013444000000	1636618244000000	1699690244000000	1794298244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1b401c245ed6b9ca3c2afc3ff11e6f6e833886b791fcbb06a52d7f9c88be55f9be74afff372f1e72b65f6ee0db203c75b6bcc852934fa67bdd97af0f6c03031	\\x00800003cc91dc36b0f6130b5deeb2d0cc5dc4c8f627dc99d788195898a85e7598d6fe3f626d85303d95deb9aa4b17f5240d2ef268a46faa17086a47a2f6f0c07c00b7aba278d59ddb1d1884bb8745d43efecee0e5422947ac36bd167613fdb08667bc6d03edecc1a048fdfc6501d377ba751b59a326ee72f66edd5d9969468255d211db010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb1cd163df2b6ceb6e45f6e366d1de92f5e11f25f9e7a04f09d9be7489b57466e9c0f1a6847191cbcdab6d266a011ce6c0a6109c64ff9dcc721818031f74e250b	1621505444000000	1622110244000000	1685182244000000	1779790244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5c86926f68c2fb58d1690428b471c84346a89973bf57371cd4fb99c698919575f4cb0d1aa1a31abe5c13ba329c8256b0a3aefbfe78e1aeafd6a30bd2a5d7ce4	\\x00800003b586d3dd262ebceba1ac26d63bc8aab137b3fed549bd86fe82d5195cd1d8290dfda058704c8eeb64d0f6bffa299baf76ef7f9dd4d5fe07289a7c6c26eb307b4e9ef0b6814c2ec8eb1641e6f6e0e1c4f60c517f36a3d4055d3c0a630de72156b4ba0731641efaeae25fc4825ccc660af184b20aa3df2104ba7c7066fc0be2c75b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdfb5a2db9d39ae9cb864a918184596d633bd2abf82e51c5714a23e5365b6ec2b0c1aff155d2a2e4c45c247a78e03471133f43cd8d6193c7ba400f4c11f0f190c	1614251444000000	1614856244000000	1677928244000000	1772536244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6f440ce79f0b6acf0d02bedf8468d633ca894c9e9b49ccac91986d5fddf838a7c0af2d6c0b34b3eb772d1cdc8e783afd6f6d840dd13f3b94cfcf5d6a5cc7e22	\\x00800003f4d5aaa43b945dc0f1c40e26b3b76c7540f158185c72a87da9d303ae75d7f0b73a66f67098dc059459757415b0a1847ad481928c21a0f6cb40f029109f7dedf8dd68b9dc2c680ce6aea73aaa6a31f20ee9790dd7653a254fb466fab172d94e28cbe516396666cb4ab4180a4238161104a514adc9eebeee12d67deed9fe0f6a15010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2fc67b77f0e272a70d070826f2a15bbf134ce858c0154aa0168f91d23387108aaba03e410a5d4809b17ba96e65a508ca979c99a1a87297b46ba32bd4859a410c	1632386444000000	1632991244000000	1696063244000000	1790671244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb8c4b7b3230e74e9185d09b123664eae632da445a5ca28f1c703d33bd3cf1dfcbc584b247e358e93e5769f6dc0f55711866099853cdcb7203c57aa683d9b2393	\\x00800003f7fb8172e8b8d2aebbc35845cb459b7f7dc41bf555d8ed4c54c3731204d63835c83e658a719a47a84ae4c6376300cb43e6cb00860cef223bde8ae33b57cbd902e29f7bb1cc945e154b20954fdff4d0bcb2d699ae1f67123fba76cd52fdeb5a764905d79b70dca193d6723fa628f9d074a7b8abcc5f17484949a4a0b87c91dbbd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1912e75defed9fafc4e86268b47633d73aa1452664c6cb40bcda772ba66be1cb76b6ee93c3cf3a90592a0d07fbdef3f95c969068d3a3ca72f4802da8c41d9c06	1636013444000000	1636618244000000	1699690244000000	1794298244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbb287d5baf034cf304616b1c20e0e2d8e2e69776a7bc8d2dd42c4ca74b08d5332720049cfa50ee98c17d3cad38a362572930d8b5d2c333d8211293ace0def91d	\\x00800003b39b0902af89f4ce81412ae220c4eb97a7eab2f4621c388d2ca92e5f51a5083300ae7713ba439de40f27e616526ce5a59a8e7e4c864b1315c2df4af4885da74a51b62b3e382dbd0ca13ef736edc25edcc43546a7a8c7058912f6b3f54c4b8011c15dad739813706e849c346a8b46d55eb1569ef274ec51d01e6d702cf326dab3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xff503ad7c9e3768306e6c68ccb3e3e3aa6947715b6930535a0059db8e658635a3f6189e58beb9db1b3d8a1060cf73bae907d180616848934cbcd25ac4cd3ce0d	1621505444000000	1622110244000000	1685182244000000	1779790244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbc2cd0bfcbb47aca35244760c100ebe4e8c3ac2030fd7f6a3dca41c26ece0ead918212823541e010e4bb234ad4a6ed4e8b8c4eb211304767551de07e4e78c443	\\x00800003b45238f9b67bae8b28a2a689f9d3472e0545436c74a71dc9a8701fc3b561e9b8216422479da00caeea3bd272e62cd8f8bff7b507acfe770298c53197645b342cff5fe28981e9731ff0db850be44d171be10ddd9a10a5ce6b15f113d181c8e03576b7dd2a1fb167df89f09d3ff20b38edffbb47f24b400cf747a682dad1827d11010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x78fc256ca69c286efdc4debb1b2b3eb83c5ec6fd29f1b4a4e5b6d6080cf6d677da1d53db5fc28dce698786be119d0bc93de8264c50df61c6d276ea18c610bc0d	1613646944000000	1614251744000000	1677323744000000	1771931744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc5f0e48b863e5e6f14c08f0f531d2e39780a0d0f332a1b6fd1efc1167325d7c903e7b609073b4112307a7cbf0063bf181b8497dcf1fa80e7ffab0e39286d425d	\\x00800003ef981dde22f9f73cad51d5d4945b726a30a9a9b49bef56b5ccca232f14ce9c7ece79b71f7c9ca6d454a0dc8ca73333da91ed8e7d3d06baacf27c6646e6380676f47f099bd387f70d1fcfdd3465ee06fb574168614906ba337a2c6cdc3fcfc7a75b6a5d637673351554b8e33e7db75e71584c3243120b112e3769146a705d3311010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9b2ea8b2b23f6d0fa4eab1d0fbf26954f12337f5b8e50b842f8f6b446e1cac16e296cb365b4d33094055daefda66e567dc94eb68c4a189416a8c6e7241d00309	1639035944000000	1639640744000000	1702712744000000	1797320744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc82cf66e87f6898acd23c8f1d3575cb8359f8e338590dcacc10385ee81ce1e6e795c18904301a5b293a3dac187186d1155a841e1c5f8633395a7d07dc6e7330d	\\x00800003a81415350b4662ffa4715656a9d3337dfe7350b191142edcc431cfa272883110d9bceefae93f95168afde17ffa1d48b5e5355bf0cf6332b99bf3d166b5bda20c282eaf0c50532f714d9293bc4ad7b75c1abbe99dbd6ae8a42b580822a91512d5bbd18ca3b716a9bfd643a6ca9a0b8d79f7544dc72f0946757eb54cc636433fdf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7ff7b0244abf3e7a3079fff9e83533ab1fdb853c2ac56cb1c01319d2a8beef31f8eb8663b48391d5fd5e99328877466dc09780dcf0e3afef9fd72c35f3960b05	1611833444000000	1612438244000000	1675510244000000	1770118244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcb08cab5a396b5b335c10d7cff080bdcabaab79185348d76dc25f2774e06ab172724df90d10f869f3635b1290a476a0e4eb2cb933cdc0d65b33235fbfd391ed9	\\x00800003f2c51c041c4e530816b656d0b317eb7189e948bc37677f32960aa0b4ef361dc60749670133674a75838f5e38465d3322bd66edd386e6a91b46f9722b59a1fae3c8077e6df1f1469414c46facd22058b75af9308c6390a95c170c150c2d613711e39f5dba8d3974fdd8c4fabbbb450fb9f351a18c10e820c75c3f216fbbe2ccdd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x08fbfdad0feb438fae0058c53611042b5949088f73d5d716f1b842bf06f75e360fa2ff46148ed66f131a07c42be57af49983a075fec96176d85f67ff8220aa06	1628154944000000	1628759744000000	1691831744000000	1786439744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcb401df21154c7bfd9a8c2321d056a81b1a38a61159424b69afbbc78fbe2f4d8b37fb04e6e5ebf7fb6b27b78dcc5cf7f4f48e5fcb8c5262fccab0957ee7482e8	\\x00800003c1194e3ac7b7fd1e9822e18c3fa5dddb3fe01d0b47380d91ca06846d4f9d7450d63a9a7987d202dd0a500b8cdb25084a55cbd6ce8c76a515af112aa1ba581a6e6b5c9baf5a11254cae4c4baa7568ce1448ec28e8e21135169a097c0b926c2d90872a7745c606f85da224c1c6baedd3bc26e4607c337423348eb85b022c65251b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xaf8524189d90a9dede857499f03dfac30a3f786d955e93329f76cfa82a374bf4e8bab4ac4c7838a79f6b15b97beb82d1f85784536add70b13792d96528e0e804	1620296444000000	1620901244000000	1683973244000000	1778581244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x00800003b64526593d58bbbc8a65f032a9ff36f24f8ebf41ed464dc5b6a1c7e5d1a0c544d9c3496e98a91124a3087df0c50d4060add591e7e8aefe02cc5b198bf921df196a8a3388942ab1750dc3c44f2e12ccc49daa41dda02b3a8352b9a75461c3c92438a840cb3acb053222a6f052314bc1f94fb1a5799f703e821c2aeeae458a6747010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4ca850117cdb9edb370bf95cbca1417d4d1fcc67e5ebe8c3441106fa684ca0368b75d053452faac753177ae55283fb707716010c4e6038b754755b75be1ec90c	1608810944000000	1609415744000000	1672487744000000	1767095744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd9ecebb6c6981dc48686dcae7381b86bd9f51bbfac760ecb2651957eaf64c81ded661960372f4d9b1e00a6cc4730511ab3a37d8bd7872c4f8b6fc569c8c53bdf	\\x00800003dd888e2caf898450127e90bc7a6081993f8a4e763547b14be0f78b74fe5b6254ba61f1d0ca2501cea5bc0aaabe516a93ea3a5f003c139bd22007d920a33ef7d930380c0955b1fd222d0906ab9d717cb8d4832131ee350eacf845faf95add107c9ae693fcc43c4bcca65389f77788959cb6063e9ea39290a475b540d0bd65c077010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xabff51a39c44e6c3fa52eda81d0c639b3c8ea1c4b50ac9c6e541271e93e8d01674191a6006f55ebe78ca4c2b97c9a6269e90ed921122f10d8f939277aee55102	1629968444000000	1630573244000000	1693645244000000	1788253244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9083142b08c06adf2aeedbfb8ba9e6f15f74e8e0fe3ab59aed32ac1d62f9fb09922991d84cad19e933c365b15633340e89979193cd4f3f1c2b6704cc5d47724	\\x00800003c76eeb23649d590283afc23fa4be7fb100f9d93b584a1e6f4046ddad977aad33d454217a14296b97915d929f2a176a612bed82fc4b3697e34c5413344b1afffd7b7da7a4e82c1e195eeca3dc7914afa72e36b05d88e51e71e00ddc8fe4a234cab4ed1f326a98c72d12a6dccf29f5646f15ef0b0fc77bde47e8a24eb8e0067e81010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd65e31bfafda1c32ca5a8cf91f631e3a8442cfccaea6aa219911a5e8ca90118801961708f552a27c289ade3e4a26366881c607fe0b3e965d978e3e80f7da580d	1634804444000000	1635409244000000	1698481244000000	1793089244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdb200e05d9b4e2ee5d92737b75107c70c4e6e3347fd7717f50598b4065e27a8560a00a28b8bdd5589c374dda885eeea269174402e7e9039bec3224a5b71b19c4	\\x00800003b021a1e4e847e89d20bf347ff10fffcb74802fcbef7a0390988dc01c07f1b10f3f3b0cb0b19371595b35b36de9fc1901ccdbc4270ff006ae17d375ff60f0b5a06a59745839d670b9334f10d164fac86cfabdcb25c4557f37efa91815d18b63e9176488f1ea36c4e10165a781f25e82d15f256fc473b49cb6999bf57fdfa228b7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x79320329a52ab35b728caed67ae5bec3c9f2f7945cf1761561408a2feada5d23952e0e2a77c7d166e93c3de5301039e51748b3b305a2bdc4d3e4b059a1f8d409	1622714444000000	1623319244000000	1686391244000000	1780999244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdca06cef824d0b58d765fcc4074c5b548d4e36324db61370a9d8f21ca7e138ce5f009819e06a8eb09b33b3941e81cea3c13d00a8461cc99eee63809457a8ab80	\\x00800003e75c1f5468150f40a0feada83ff0bcb1dd6d0f763d812321d7ab0f599f613fb3ff81ccf0fa0e003162505281f6763d71ea46fb79ed6e100d18427d87c547893ae57b19f67ba2f9870d63444bb49f9127a118f23ad04d09aaad34ec8e8bfb517c699d575bff1b3247d3e345157e253478fd8fe6642f6d45dd0b99d89a1a4b0b9f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xefaee1174d2ec77656e68a1168315001f96ba0eb182daa7625965913851d9f6deedc78f0be13fb6db0eec38e8abde8d76eb399d1ea7fb1cde1abfea31734cb04	1617878444000000	1618483244000000	1681555244000000	1776163244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0c8e5cd20f2d3b2bc2dc8b8fc21b5bb5128e7765cbebbb65efeaa0631ea928f24db9a77e1027ef16c8aa2dd687d23ddba5f7bc3b5d31d7b3259896a1285b499	\\x00800003d6800d0264bb5dc9cb2eeea48e3ae1fabd1d759832bf02c7faafaf1751afdc43055e4154466680e78c943ac5f7fb83697fe78f3b20de313da82db8046071692c9c218d971a6f4c10a86feef94791eb9c0eb1be262dc9330a82b93fc5362f72743743c42634e4c138b67dca5b054fb660b78c50aec0459972f32623f4761617a1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8e6733cea718f49062c20fc680a4bb5745b954f61b8d8fb2c28c7dd1ea8f7dd2785e11bf081c7b659be970f9dc2be820ee102635f02dc85e00cb45ce7a9c6808	1610019944000000	1610624744000000	1673696744000000	1768304744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe1bcd187b66f9dc6553e127104f11714746482429a6401c89c740b1cb66babfb895adc418b7db3d6377a3fda4f8efdc25431881c6c7a3f674a07a3a46d5ddc76	\\x00800003beb68bcfba1870cfdbf39a6bc7eb938867b3cd562819ebb07a3744f8e71a0289330ef1b62da1b1ddb232cdf6594fd4fb9cf6a426497c77dc69a594a7ed8a95dd20abf1e02a644cf3d1cb63c9d02f643630f613daef06b26b6146b3cbad728e34c8f2ac483c5b8d546abffec81feab7b9389b6bb5a52fe858bcf63103aab133b1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x84ea704839e1b58bcd1fafc1e685a603a42f6bec480b9892169a96a3ce74c482d71665f8489b1080f9a2d7bea0e8a5d8d7ab1cba93a9c89efcfb05d9d2ecd205	1611833444000000	1612438244000000	1675510244000000	1770118244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe4b0dba604176bdfe7b5af705943b911440c9bc9096a18dcf7cce274141c7b023e4a82876cf8ce38de76f144c35b8442c79926bf66d43d2101a69e8c7c686cf0	\\x00800003e2b69eec5146d119de299cf6e0808f19a3b508aade2121cf418ba2e63626df5bd8f56d81e6581b65413da9b21be1fc3ec11267264a6526b9c8b469cdd9ff6fc5ee9ce8a015d752992382dd304265bd3648012ff6cb321600e56d7a9ad432387a19c329dc48212098bc7db6d827bbcbfded50369892ee386258f6da85ba585695010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x46d70f3ebb67f7e008df17246bd0bd298559aa6ff8dbb96d609b78a8a45920894dd5c4ef9c891e0f5a3a0be0b16c055bac2bb6c0bae4d7fc2925b1ebe7b16e09	1631177444000000	1631782244000000	1694854244000000	1789462244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe6d852cdbdfc2e5cf540020ca37f56f1a70ff86eab47b511c34ba472767c10d108d3f11b97968db7431ca1cdc581da322639e125fcb89bcfbfe2e3287f919f28	\\x00800003a3714724f954bb5602f806a8725ce91ffa03c8a9955e9a6f849806628b946e0dc8375ecfc1fd1d1a35cdd444f551c10cde57d5b52f60a1b5eb7a5833b471a0a44abf71ff0b8cd9cda584c63fbcf9a3f1b80db5eb2860ade211b876695aacd97033c741871eaffc172f0cb9c6aaad7a1f0086487a9a4f53f939d292d2164714c7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x016ea5d0dc01a4f51fc1ad8e7f79729227f3d8893980a0181a38a88bff2b39a9067fd2d4b87b40413aae20150d90482199f994488d4f01480cf23a85e109980d	1638431444000000	1639036244000000	1702108244000000	1796716244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe778c70906746807b73998f3fbefda3605ad8204d88d0acfa0e157f515479ac84b13620238dbae8a4d5225b7ef7eedde44b35c4a73df2a3fd056ea90458e13d9	\\x00800003c617f94b7fa78b05b68842d90e7e4bd1462266b1d5301e66548810cfc213dd4ccddf4217fb787f6920e9076601a9f99e9fc91358df5cf2e10b3dd12393166bc61c7e8382e83c4d50d3bc2abb165ccfde2824d1f91ec93cb23a1e0345cc7978234d9822592bb37e1ae8d3d6f30a23ebe2989480d6f281b51fde420435fe21b1c9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x19e1a23b59e5cbab071dc4417dd50df6aed282d4f7b1a5e6bf62a34f33b46b028e64f20d47a977768605508365777218dde082ba06d27a4da48e7fc937ec4308	1619691944000000	1620296744000000	1683368744000000	1777976744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec608c7937ba57d4cd11e7cccd1440817efd881e948891599d804a4a5fba2eef7295850002c2a298be37c1a98eea32968de61610bd8247a011b9045b39d7b994	\\x00800003bded43ab64c7e6cdd942f81a02cac58bc506a2b5d1be7c6d7065687f1204d4355a560269df13ef0a7cd1e2ce7b2299aedda8a9f607a9e9bc53e589d1a70369461fe7f4830d14548189aaf57d8d0c9f9122d25a914cf2857270006271c05497c74c470d77f7571806c75a208729352fa7bd9ef514b4f10e3114a3ed20f9c085a7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5db9d8c5e0b3d7593b40887facc83ba393037d1d122bf6b6d945a7184b5c5bcc80c8298b12d43b20c807975aa3d130255932baa105debb808c3b01da4b7f1a0f	1635408944000000	1636013744000000	1699085744000000	1793693744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xed4c0ad629eb14a3999d2ba9a6bce505bcad2a2248f3b74a04f5219337d7a59cee7e6079c09e0c5272362f02ff7f6b78a68dd2ba09d3d6e22f573fa4b2e4ea4f	\\x00800003ca383848233166fe4809aec5d96791107b2b91f478dad0518088a63927be8e95cc6a2db9386d0dc0616e40647966cee580bb4660a179e6e64304f923c478b71989ddff548d290b39623fbd2586011ced2458f6268878b1b79fdf550d15db6d08fcdb6e10f99d5d103447a3110f0282fb950bbf887ae996881446041a0f3a81af010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe332bb9708788fa7f8c346f8929b34c634a2305ed15d3114301973ed14339623bdc38f9bc7f558fe596b0bad208962cc12f69a0de3141832aa139f405bb4d805	1616064944000000	1616669744000000	1679741744000000	1774349744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeed40115df46f0a39dd4c99027e3a57110cd775644f07373e8a46d9545ecd2ec5dab8690d80b20add557371a8e70f96b406373a7e5cc9aba27ad0adc4cfc83da	\\x00800003a0df527c2e67e20600f0d6a6d22e25a0d214f823068bffe793054e918d4fa709a8e7aadf1815056d9a9e195f94a36648d786d22f0727988d89781a867ef2df744c1fd20e5ec7a463d00861296d5cda22cbd2d2dca73523b6dad9bf6193681c0a3a43695e8ecbd5799e1a4b92d71505f7b79e0e99275fb1c87c47e9c6ceba82ed010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4e133d8dda69c6d7d7fb38b2be8de030afe36dbe4625c81ec244ee1f4c34096f1d34979efb61350b909afa966657bb63b8fad833cd0c799fcc86361da4961a00	1617878444000000	1618483244000000	1681555244000000	1776163244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeff0df37a70acdbcdb915fa6a7174a9e795c2c83617ba323df9e3f3f3947dfac9a191027b516c03505b3d55c8f99b22b61851b067cd390fd99ffed80e5b8126b	\\x00800003c7abe0d87303db13e314c0f3d6fc7979c9ffa9c95af7f75dd6473ce054285ccecadc0417f811f4d68ad180d9f599aa0c00565cd096a15f4e2005894b5309d8a3a156c74324fa521e2ea4a4ffee2540e07066ae9fe61999c1b2b2cf45229ae8bec1840a2a3986bf497e40318f328e5babf960ca0fe946d57f570c987894258a57010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc473608f4e80c92be2c6a44dfb8d999f12b420eb0a383636c396a1554416d7ef4e3ed1cd4ec8ae479477f703965d12216778cf1bc8797ffc7ee1e434dfb8c804	1626341444000000	1626946244000000	1690018244000000	1784626244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf194bdacba4b4315e846dbada744e7d21969ad4d6c34e4042e7fc8ab7d6fcf5624a7a2e1b1641393812c6c322a048b60242b57cfda951459eb4a532bf95f4d10	\\x00800003a2e62a16fadd287e8b1de6d1b4c3158279d4fcf71cbc473a2c21b933398ff50446948f5b401b28bc782ed68b045578365b61404b88ab0caafb67ee6f3f14a846382b8ec0cf932c5ca31369d5aa0dd369bf7ad93e0ce6b425cac6b60c3be6db70b2b8ef4d2f9f81e4282598c8118cdc01fa69a8c40fbe953a2012aa9998a7ca99010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x16b9d0b8e0f63639447a0230130adf5d6ac4a8599b92e98c6372be1dfb4a1c6ea2e4d73e981265c131f339edc2d1b2bbc83ff8eaa39912b0aa0881e4c4e1bb02	1625132444000000	1625737244000000	1688809244000000	1783417244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf37cf321d535e9d24bae7c65270006b0948620d98c1fe1ab320a22b92864a780563916bcb2b66a6831c96359032c5ff624d521bdaa2eb4c14e006fa14cbad0d2	\\x00800003a9457616d764fcb300ddabdc5aa2d66f302176ad9d195287db024a517fed1754cd84cadde7a36ff39b35ac010b3717b953afe2d6a0756fa1e5080492d5d6f00388235a948db31424bea426b26b9e4b04658264139507193053ced5edd87f53900d859c814e6dc4b80169efd87256d6b65cbd8105489603b9bc2539838617e89f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa5222fb9c20ec64b2a1a97084d7c657019104da361f43ec6a37327b1711b081410974b980d5041d96bbdb74437ec3b62f305e097f5b2a498d1bf5cbc7cc06701	1627550444000000	1628155244000000	1691227244000000	1785835244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x00800003ca5eae770762b7cacf5a38958d3e9b728f247aaa8ee92d63aa5f7353fe0e838b198ba91605e893bda12c1eba4ecf1a6df258bf20d11fd9ddda10348802f3c25ef0d312ce75c87b0e5dc87712837d10c4393f3d9feaccaa2c78a8e085efeacea4659c9136a47751cdff69f95a811055faab6e33b454231765625b55a394513545010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x16a95c70ba5ba4a51174b598b6d5305bf5d30b6af828f15939ccf36a3a84f4a376edba1fca3d5f357493edfc45fdee0c5254c8bd70d848da7c3b13a3ee58e90d	1608206444000000	1608811244000000	1671883244000000	1766491244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4786f4cdbfaf587363b3e3b6af73f79186d59626b7fc474d32fca95042af02b15a13534441a0308032087488a52d1b620c55e0c05bea3398b24cad0b4c8eb17	\\x00800003e37e438266a35f7ea9a420a4a70a201711440ec4edf4943637aa903a8eb978df9d41fa57b5eb4257c3865d397af1e037e85010ae6f15d2e857f32ab3da5ed7c3a8a13d0e029806314d3dac2e897d2da66050f5261c411a53b6a7aadcf5f01e588ab6e5f4e22f924433f12b3bde8b4910d2afad3f447838512e7a4101df5fe065010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb1e1e784530e7675ce8ebed1e17df1b2b03fead4f425763f462a688dce5c44ec50fec78bff83f669ada6c09b5feb8d545f16790ea5930d685744a04fb0c4150f	1619691944000000	1620296744000000	1683368744000000	1777976744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfaeccd194d01a61a4da5e19ca05aff2322613a4ad700abadc06ec67da604667b9c9894b7fcda4aa7e656d43bbceac9bf6cdb6dde72705b98350513bed2ef4c36	\\x00800003c1ee73718e62abfc88e6be84fb6b6914a810b208b667ca42b0e9dbfd6d5b0bbe40d746594c86261343754742273ce7fd754560ce1236b343b6c64d76aab5893241c55fdd58ff7579cf770289553d85b518e86cf4e0eb6cfc0e6af694e11fcc35a53770f682d9de3f6a069714bde8543509c560a63244ba29e9fdceeb8fe33b69010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb37e34565a436a13774e41ced850e7d80cb2a0ff50dfd6a5aa9f113025c08a6f12affb4c70b8bb892fbfbeb3dc98efcace07d17d28c78e0d3db87cd4d4413703	1623923444000000	1624528244000000	1687600244000000	1782208244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa64c38711c83dc8ed1d48dd4752ee5cfbed11469e63a3eb837aa2e3a61c547ae360bf2b4bc0217d406d703af5416435c690f7b8d8cac29dc772316eaa70f1a3	\\x00800003bb371a3592ba87ed52d77a662636de58599c3a66c66404448723bad03de83e0c18faae6a4ec86ed28edb7dba0028d5143ce4370260c24d4e4fb9d982ab6a8b18510d3e1877c2586a92e0397e4f5dfdcd660ddcb6d7cc85370bfbee809528f4d1b5093c93b28a2ccdab506029263f476de947a7f4728ce11305be250a25b7079d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xeb090d872f2482f4b19a8b9873b09b0faf8a7f5ae542eb53ec75e30f0892e2afe0f73fbaa652105fbec89f8dfe9e0b17b188da338a285c0bebbef18ed6f2d20c	1614251444000000	1614856244000000	1677928244000000	1772536244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb8076ee41542a4269c11c0b9cc5e55ed482f32b2a9c6781f683bd103853411c05b2d6442151f9ea86d29b5a8bff4e77e73153abf03ee771682018303d59a40c	\\x00800003cffe59269382916edf32d26ce0b3aad9dee68ada0f408232bc2e9c3d3fab8beec87f0839ef05d221d0957eeb2784bec7b742218505622e9bfaef62ccafbd0fac72d81b5f5912e8c539c945bd500c48b30e346b11f9bc39f878d4eb10faf84dc25b9278cb48f378744c50a80e1fcd5794a3c854a87169f685daa69de439b1d815010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x23e86f6896de56dbb96f68d1d45677f24e9483f32d49888b64d627e8033d31f4a7e8b40292575d2d3bc4afbc3efab5dd9d05bb17dab944dca85e9c9071aea500	1639035944000000	1639640744000000	1702712744000000	1797320744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd00b71b37a1d469f11adb0b109ef62f57f48dfba5341821f08036f66f8501e4db0bb7bb05c1ab9a6f2ebc21f743c70e9d3642a76144f10364ae9bd3bcf319c7	\\x00800003b1e607b6cf5f9d75941861661a5f7ef44493dddc7de5280b1e0bdf5e3f48b7cb1ab235db872fe3b3c6aee3da579e6c42cc4471535381b5edfeffd70af77726d4669cababc9334c8b34dc379e8bf2eea5d5d3b5a6c528cc17e545dddf39f945f1ee46b6e255f5964b96157073ebe8d36cce646ca62ad05b3a4272ec605bfc4651010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x00f1852fab37340d73c366a5581445dc84d1bea42c986a80a1bbf118511cd29463cf75dee66a20bcf084b91d17b804f407423cdf19000acfb61d0f8b46e73d03	1623318944000000	1623923744000000	1686995744000000	1781603744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe50aa68ee44a12364bd7881278f6bb875bf01f7b0c0e84acf8832f394a01dc08e8e19db2222121667697c8e3886592051b43c50409356b8187b7b839078cc5f	\\x00800003a2085d5ca842b457367dc371828e9f49a15641a3d0dd1b9e9c2a7ddaae7dca173fec9b1b1c1d5bdd19b3bd026eefa86b63602fcd3daa6d7235704d2e3203ceb0545f63d5f437f4d0bfc1144a7e4f5a30bd3d442d80d28ba492d9d9c2dd35c95b05278d0261aeadb500343670d78df29c45ef8593ee1d42e32a9252c9cffefd7b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x083e5c67080d0253c4ad2708e2e68852c7f5442e14135c2500e96d3acd70ebcfdf2bc4970f34f74b62158ab46b25ccf480b5dfd098986053a3ef2222f7e14400	1631177444000000	1631782244000000	1694854244000000	1789462244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x01c1b3e4415112da2aaa2b210395adbf916e46bba7f0e79f0ef20e241940a5284e85581bb930ba85d682a3b998b48c593cf5843141c50a2d35d33c71ef708062	\\x00800003c77452061c16f529c2c58201d87223ee4c4aa9ebfbf7470d5383599e3b655befbcde9666b3691b102f98d16608b04967551c8554eefe698cb815f1f60d86bd333ff24461a06c00f1300aaf677af81258f7cd5ebb4abb8efd1e6c7b8ef2edd778756c84b2add6534db1f7d33172d7cdf0e0661d1c2ddfb5993e464b4caa60fe7f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf75b97e3fe12b7354696e2147f2dfd4513974ba4540223ee5467d749c2ba7dcd9e14dc1bbc284d7cbc5145b0ada45629850a7516f6a6894fef25a4c28a58b20f	1634804444000000	1635409244000000	1698481244000000	1793089244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0229588baa64218e1a30c116699f7009ced601c2c617af3674f8ae349a5e61112615f213f71e04d3e19b3e8c29fc73cc14d413d88dc1d02574af1042272257ed	\\x00800003bb8a49496cf04e2de933299ac1eaceba1219c383417e2a8c2214ca0e322bb370cc351026b41ecfbb41adde9e7783c8cb097c1892dfd0b9b995f001f87afb3598eb039fd2f630b6fa2dba949b42bb6b3dddadabdbec5eefb86a2f1020b784e2814d90f1d22b372787d0c9ae84cddafef2f2953e0031fd88f87831c29400024ce3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8a932466496aaa572eca67c5745aa16507f5bdb2160c0f4b58a5006189929e96a70b8545619ca76e3113ee0a48c04b046f4361335e8686704f300403a1fa7505	1637826944000000	1638431744000000	1701503744000000	1796111744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0205479279cdab859dc9f547e3ef303e74fc868ea648b2b1d950147892d7a7f0864771f22dc1d64e922dde3e76a6143c99eb0001863a5254e7b1e0bb8ffe01ce	\\x00800003d39d2730ca7d3a8ed7b193a57e613ba641ef5192f6ce2272ecf6b0005bfacfc58b121cd7210239ec6153fcbab5a162d96a1cea26db001a8aa558f7a06fb41f3226aecf45deb3bdb95148c1364eb6fbab5372735ce4007ab6bcc66b163f358284ea4bb7514a0f8b9be0a027fae45a7d23d71a52578473c18e1c9ef957bdf048cd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa731cc228b5557531c8a44c00a35f3a6d7a2ef26908a15530a5a71d480f5e328865d0750aa98a553dc19c8cf03edd3e00884d898c8cc256582b1afd25d74f90f	1621505444000000	1622110244000000	1685182244000000	1779790244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x03dd2fb590b6a224edf91629a957e8676712e5cdc6e30dcda2e8317505dcba6c5193a27d718e41120a333230a3093c599c0f2f8419cb6092057aaf8c099b1691	\\x00800003c210f972cfb350d96603300a46820156db86a1021f0c60b79afa0dac10e306dec0344e2db4c36c11fe10d3a9f17c935f927238890a9af986d9525430c42cb0205ca57adb260e37cdf499e0999154c923f15c718b63d831dbaae31b9106a3999a386d24361dcfa8d0ff5eb9d13bfc971c1ae65d0048f757a6cd589a4d09887f2b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6521fbffff50f90bfd36e5e8e676f09bdb896f3c361730ab841f9ab3a41377505844cbace7782b3e6d15a965fb470111db8cbcbd6643929333b95458353df200	1619691944000000	1620296744000000	1683368744000000	1777976744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x04855284ea1cdf2ace1ad45321370f61d51cb09d9f95e5b30b2e317a10bbc4d1fda1134aada7e5703be891d9e6ac5adc1f8a824e0947ab57a2944e2d72ae55a2	\\x00800003dd3718b167a72358cca45598902ed4208b0aa9132cdd02ff046e26c362d5eabaef12c735359ec672775d7704b401837c56a25d943e085e06474aa343aa787bcf37344bfb1f6915115840e158f21f4224e554d05ef3946acca0796aff21c30b82fdcdcc320dcdf24076e34d4355d8bbd91c58a9e1f914a704b4d24386eb601f75010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb324a3e8dec5ee4fdb316bbf92fec2cec5bbe058aa483a7e7848d65cc0fcd1a61496df2259068c3dd129bdd6faa7bff100ce2f8be65bea63aabaeaa1e062d30f	1619087444000000	1619692244000000	1682764244000000	1777372244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0475d1f693e907b0e95a2d0756e11678bc6946fa7e32625686b0cffba276358b55707e52a052ac85dc3fb65f407584318d1366ae4973738b56edf3720f4444bc	\\x00800003c84eb0489e806a9ca6d4ef44d2c509521b5c8072048852fa475c55a2ed9c4f35e64d0aa21d6c55a7bf8343bd0261cedd12c0f1a5dc050020afc74d73312e2938c081e4ea2a5891a7d761f7867f73d4a53c831977ed0f37d59c32c022e296dce2ed760c32b625ff5750d6764afdd23b64257f2955a16160ebde0b472ddd8127bd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6b657e237d9d2f7bcbb0da21e4e304b19707543a01d845847ca7961a4123a99d910226038adfe91d3b10304c9d009853a9fa34c355362931728f2e36e8340c06	1620900944000000	1621505744000000	1684577744000000	1779185744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0585af3695efeee7aa878288e40fdd1a3ef2d7207870bbc887462237be05b85f4b937c395b2a4d0d3b0ec5fd732e640158da6cf4d1ddd45171128792211d1360	\\x00800003f7eadf1f5e034976354ada9e9db77708765d8bfcc5db8a860b85b09c7f0df7609f90647c4f039f7db982897e8163a74fa699309dcbb0ce3a32270988de2a5dcc98a4e3631c9c7a26e7eddc0e0bbed9b5126999fb84f468a32d9ecf11562f0f0753ba232cf5b1656eaaef46564786b8dad87441637676e8463245ff0bac8f69fd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7f73d52144674e1b9718ad7608430c8f02876ce6d30432bb80e0b7c18317dcd0631ae89395e270336f3b244a4226f389a4ead85c932abbef0b955c1cafe7f30a	1631781944000000	1632386744000000	1695458744000000	1790066744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x068dbac4a2eba9418097e41c8673fc88e0fe74ca8453ce753b2bdc451c9d9dbdfc562cb1ae200c9219919d868739b1064232025f8d1df4246fee876c5d0a64cc	\\x00800003aee3687e40bb1e6fb464f1cfd7340a626751e10dc29a6bdd1defbef91757575b888a6071558b0011b87f2e365b20cc4348c04f761e8bc67d199dd5c5f880e1ed8b03c69e3877b4adb9a52f1cd00848afb788ec04da1884dbb8331db9bc23f53f77be0586ff0b810d057fcbae742edc0c824b5e4b48804203cbe0b19a111541a7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7e4a400401c91d51729f0adc58218d1084e1fb9c5212269706264ac2a38c24417c252dca7113bd06fe6bc33cc1b7f2d8803edfcd7789d15731e749c8cca99e09	1619087444000000	1619692244000000	1682764244000000	1777372244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08bdcf31646a9af749a435d3023df022bfebcf1f49f73280cc19900024c517d4bcd177c608dd8c89cd0b77ae89142e4ff346a0aad8a89e325fa7dfb614e2b4ba	\\x00800003d21522b6753699b67b80be5b0df41808665799635aef45b1799b81d2931a598887e46f11d7abcfd17c28d880581930da8ef8bb2764af14a78049a7a6e4f1d150cdd9062342a8b43a173931effb6e83c3a594b4323decd4435a3b02a1655734f7d32b24a91e1c44f6a5ef29f3e5f47956553153e1e1f92db6fbe2cc343f13b427010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x073282d988c12fee039199d13684aed2fedae2372a0d76b1384ccb432d218aab149be9ff53968708f582b33ddcde82f19d42ee889e0b93aca85fbf2e8fc30f07	1629363944000000	1629968744000000	1693040744000000	1787648744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08dd7fa0813fbff77828d1133351926d35db5284a73611d1af3410d189f9eb9a0eaf2a34802cb93bc9b2c6558f0daef9b0bf5d98e24b904c55b75e409f71c67b	\\x00800003ca32f068242be04f7356f5bc34320e2017a989aeeee775e8d184fea4414ca47ebcfd4e91704bbc36580de7711531cc7931ca0196394009badaf8a91c18d75ffa737865b60fea02dd4b0cd90468d1d9e52054cacaa1ef2d0cfefd286201c3b4c1ed7ab974500640611720de21897b1c27b005589e25982385c87060385bb39d49010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd6db4084489f1be3e3aa77cb1d5ba1014aa6ec90c534191c4fd2ea0fe84e29de03236266d714a0b0cbc1414a288ded3d6c7e1a43fe4f403746cde1efaa891503	1634199944000000	1634804744000000	1697876744000000	1792484744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x09157ecc93f1396ebdcc8a0b2f8ba60d3e5e7be2a880ca1b85b4b299304feea2fb56e8b5eebdad8aaf20ef28c61df94a921b068e65899b8ec10f672fb3e569fe	\\x00800003cd572b119fe2ae34ab16fa17615684d11b9c7c776a819dc04cf15304da1b78913631e0988fa8b86a09bca5ef82a562f4255729fb62100cf1396b41803a6ac63b72f8cf8e4ab6828a11af819ac6cebc1e1f350a6bdd0c7c391baf913f53605f7d0fbb4bc4a339f45fe260ca69523d6495d822f18f4514d7d37c995d2b0859f447010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x72fcebc26de5c77f74dfd27371d226782b114e2a7557f84f7556e71a2fb27429ce47d3c351b849b4e49a9786c4dbe59f5ffd1c50a03f6325bdae6d2e522a0002	1636617944000000	1637222744000000	1700294744000000	1794902744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d9139a6ad225672dd58569aeeda377cad2aeb9b982be3cff9023de6827880036e8dfd283d0c3f0a10ba3d3800fe54458eb9870bbd5be4a12e9d84c0b7e509a2	\\x00800003ab3c45b619281d70928e3192a19dd3b8c19450001b768880f50c25c21741bafeab024603235813e11a4aa4c696254d6660acc905c4ec722e1db1994ee0b78f74c3628a7c698f366c45eef8cd37e7060bff0616595a530e5c71814160f48583d184511ad01e08371a264dd189e398930798c26d05e04ff6984552d646b7452333010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcaa3678d971f86027efaf0412d868712792402869c1033565d47defdc640732a71a148b2f12b5875f7a7d28f3f4c85822b9ac84a7b29452216983e9d54fc6c09	1620296444000000	1620901244000000	1683973244000000	1778581244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e090f69f3a282cb6c93eee020e761e1f84403d0184c76a29828ed5160ffaaf1b93b04b350e86dceec3cb598630272c87c62fdafdce6a8afb6ee487a22828dc4	\\x00800003c581fe98efcaf3b5249a98aaf0c5e0e50eea1be96517e904fe19740a6e62bcd2f4df5a8fbc15ced48909be5e23e3bd391c94c22d426e60e60e0aa6c7480b5fdce134a4646877871c14032f9233e5d37fd2436c2c2230e896156cf03509e6e0efa08d7464a3204408dd39ba15b924e45a7951ecd31eddb3e1f3c76d406786fb83010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5a10c51f71d79ad1312b82acbd9fbab38944c6ae10cb69943bf02f9a5ba05dd1ea6133605a84ef8af02960c08abe89d0727da59d8a0421b45747ce9c926a4f0d	1619087444000000	1619692244000000	1682764244000000	1777372244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1225310195cc771bb7649ec35bb7d509542b8a510dea0bf73aa8aa0bd7ea28b25d345b309659c5a564bdc3a4a0d33879c2f506da56aa0c820cef881491443b25	\\x00800003ebcbffb824c4914ae3ce355e86933f17f5e5cdf0523a48553ca64c3776b6ae9e3aec33895b8e749d5845ff1223bcfda1998bfcdd4b46ad59b5002e0570df61fa802ea2935c4c7ce629b33e6d41d704f7564ce39afa8800577226d9de7bf0d904050669e315a9ad54a47a94816fd9b6c3a60b34d97181063d14f820cbdd8618a3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x17bd5eff8628cc911dc7764bb2cd4dcb6d25fd3bc324fe550ed760775b6002f01fda82fcb0c88d5108b045d61ce8bb952c6fdedb79235d23459b8e9c67ca6a0e	1620900944000000	1621505744000000	1684577744000000	1779185744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x13f181a7aadf933ac713952112b136a47746fdcae270b1a52292d915389fe15f29cd67482cef9fc016990668b6d2b3e769755a9d1396af2f91844659a9e9410e	\\x00800003a2fb049de423f2816088e0f080fc6b193109f58de0640767373c92aa6c192df5f877ae9c75acce08d8640575884f63220865bbfa05cfac1b5e00b17716b3d1f75da07c9564f3a53f69aeba2aca173eecca563022cfe7c07de56da03b8af3bcec92d47f9aec4ef4d5c04f51f6440d38bbf42f34951844ca331bc755fbd08594e1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9ca18b35e417862930fa720a4ab00627002906a939873bc323726dd7af4ef5343f6f223bc6c42d468cc6c50c27516677f772c17bf5f7eece21f37f4e30b8f307	1612437944000000	1613042744000000	1676114744000000	1770722744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x16c1fa167deafff0e1933baa439ed6a26e646ff8eef747afd3f62e7d89477c2ff28c03bd6f81a079bd48533d95fb81f188513fd6b86013f7b26ba9ec793489de	\\x00800003a6e2c6d858b4a132840c52b5a9a92c80ad0e10950ae651a47af07e37c63ff2d40dc0e9682834d369350b0c59464a159c60683a058cc0752b6ff3248eb3490f0360fe4992a0cbbf8a5068012379f98b03f0355ce26b0bb9805a64f49de3d2ece780acf4b940dcf423cff676804eb1f53b157d7a935cac6e46402e97a34b0628af010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe68201bfe064774fd336cba87c87f3f3af758d6cce633cc8e10795cac7dd85b55db6e3258750dce494541630c0721e41feb368bf0b53aa938496980c054d1809	1637222444000000	1637827244000000	1700899244000000	1795507244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1929faec32f3e8d56c6111241ff8210675e33f628fcde4494f1521de07c8743ee6c46fb84de90b94fec0ec8ce996206f505d6ebd3586ec6b904fcbbe2205196b	\\x00800003d4ea39d7f26000f566ca1ae01f5c3c06de542ef09c3034b0a671f2e40fbca2f31b656aa1c79a6b06215e213e8273610a0e721c087059de4a3c5320bc87735df300c4271070f742da016364d5b153c53cc2a1b17c4b8bb451411562f8f5632de0cfb65814d5962d9aebc1f6f041b42c50bf044819563bf4cd3a650960926b54d5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x407e35b1bf6b99ee2f4aa6b0f7f01435616661e5fd7699b6ef2acdf0723a8094556ac8405ca7e6c32b249d12a376e06986730a866874df04e7aa4332e23e3104	1622109944000000	1622714744000000	1685786744000000	1780394744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1dd9fbfe1b673b74a4c3e5377991aa166d8851e513fa893f39171bf0c8fca4fc111caf8739847375d0b17b92eb1388d2376ce56bba3c3d795084c2e481d494f9	\\x00800003a97053d9cb9cdcac5af9884c330b678c659bcbfc36d02fd937431756b6ffdafe5a94c5e4a868fe584e78863611085bd68f7690a266058ae41b6875ae72e25bbcfeb7094104b42dc6ad0a9a555fbc37f1fd40e53a157caa5bcba72580b15a4cedf3500b4689c393611abe40dd86ac696d8a5cc5151f21043054902a7ca70a0233010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9bdb933e88b0bf8545afc8b6a43186abd7027482cac491291ad438a1a0b20460b0468d3c3641d56fb95c47ec62a3504d5e9fe0a85e10b3bb96ced866a4faa804	1631177444000000	1631782244000000	1694854244000000	1789462244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1ea962288ce8594c4fb929d06ec30f4a9a0c2839c1fde4744b2819c3b73ce7a58efcab810f4a66d2e33f306f139658ccf89b6e31bb1dcad87721c0ae2b7f741b	\\x00800003bcb8e31e1797de7bc32d3b428d9e499c2ccc5149352c81ad2fed1a042dc8fc29921e73a003ad6a12193f4cffb94d7371591d441bb274b8d85bee04a164247725f77b82d002dc68d5e5848ecd3e6ba3b07338dc2ede00a9cae11a3f1df934f251d97487c92b5eb2ffe6e59d97c0cc97f88ca51564eebf74b60021be5e18906915010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf43b75ac127424a500908822286d9847d7a0ad79c1ec7ccfee5743671b92443fa70a5250adab9eb0df921c6cb51efc427b3c589e520bbcc290ac29d3b138c00c	1637222444000000	1637827244000000	1700899244000000	1795507244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23f94877871f345122feeaba931940be60c41d4d3b0be010f13bb295ea8b191cc3f37c110fbd3d2984a5cd2ce8ef247c273ea2d71fe57f84f1f22eb12a92287f	\\x00800003d021256a31f43cd9f1329fa73d6f42f5f64f33b1efed40c495243ec7621d5a8b6b99e736e0309d5e660186b2e52c189fa08c034cee91940ee4aa5255c8dfad692a83f4270f50c52c551ab7ef7dc8a21f75c2daee28df5bc5bd009eb9b5885f934b9416da5b33ce186a36a68fa9fe48533ba597283ded029074983b2e36dc304b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x49a09e7bd7d88111b8b2330491980a706338f85700279fdd0fb321c664feb83be6b205a9d37e7fe63a900b319ed2d9fd54af17d6416a54f5509cc63faff57708	1622109944000000	1622714744000000	1685786744000000	1780394744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x23917987085bb6988f89c444a945504e3d0270f3cb543374602707bf48c56a1aba2c7ed4ebe2bde6f367fe9907805aa48fe7be230fa84b23d160ebcc2006f6a3	\\x00800003c5fb8e30f372efa6ff00cfea75f906a5fe9606e47be00b092db5cc076cb761a3769faf545d840fc011432ccd715611ad5c8a58e59f9fcc1bb355211a0d049eb119118519041ac773f7b38ff8096553886a24b4e0557de7eb05079e593d080807b00b16de97d98006b98f9de4f1c00cde6af7957fb645b0f38eb7a08d3dece413010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x85e3fbd016767644721d9e70a977a0874ec2eb74908490b0a4c7dec8540c2898e2a30a2f1e97ff8123f627341ac600c163e2275b5f980d11ac042514ca09be0f	1609415444000000	1610020244000000	1673092244000000	1767700244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x24a14f9ec9d1e6eb6097c0f5da7e6eb482db598a4fb2e4eca93f803c257e4c5ff5e9436a25e896aae84036e65b373cd3e60171408982a09eb2783e64aefd39c4	\\x00800003c57f6d00ced5869eeb37e17f1d963b547dbabe762d73240ec209f6619c074052b1352bf01096ea702e132eda0824d8f34b2a51c4703542924016bae2446ee9e3217b59af8dcc29ce1650bc89c96df6d1877a76ea0ef00cd94d6222b496f4fa4f9f2caf3fccb452e0f58dfaf0c1ef6ba5c2b19c787e3680181d67fc1c46a926d5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5d5d348006666ff508705af97c07f6f2f697575ea5654ebdbef541cc50b29021e4ed5ec14760e1b6d2da6f85c15bb68c84c80934eeea1c77bffdc5958c40090d	1618482944000000	1619087744000000	1682159744000000	1776767744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x26b1769c92b1819ec8c602fcf52c0150240d992661e22b18821a144c09651712a9ec4d0f32ccd4399428cf91ec308f4c24568b723a3330114e6719671fc8eb99	\\x00800003d23a8abcd1b2636892f680693a892c0d96e1b4efad7d8beabbb15042d6975443b59fadad95f10413f589d98af4915f6fc878b7a006108b57a5d17df9c79845eec38555dc09ae051b97e54937c41b87550dc9cc567d80f03ad5335338c53e326489022b3cf2034e6f72c097de818db7e2c7cbaad8384635b080516a98f2109d3b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x077b188e6e5088640fc40251aecff0e9de82317999e2638b89502aff5e9c5ac56430fe632ec56cf9574bba2c7f240e172cee454e65836a680909dba831276504	1612437944000000	1613042744000000	1676114744000000	1770722744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x284da7017552a00bd09ed5f96d0c5b02a09d83700ba9864994635b908a8487631c3fd479d6acab6f29faa963354c3a1535a4779ab5540669fada0ca2646abccc	\\x00800003b8c559ddef5459b2db5e46d13b839c6b85b419240cd47a65e8526fe76af7203fb74492c7d3071bc2174e379c76d6c4aac4e8e77446aefa05e1cf7dc8cda6aa1d4d2cb9259c08b1ef39fc5b990283482266271008008fa0c2748dc8454f72b4d88ec86cc28336e37ba0af4ebf54d51295e4a2f752127827450a9b95d242651703010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xebf4f5fd371521d0cf63b703e41a40add8c82474ff02e1812060fc4e938588ad596bccc705dd87ab15489408de1370dc8ee27346573347a3538bffaf28ae4c01	1639640444000000	1640245244000000	1703317244000000	1797925244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2cc5a8a32654961e237449142bcb7b2e28e5ec6ea0513a8537fa5ce6f5b5de94d59cedb045eb78cdc0e846833260d500e8a38a8061bfeaadf17e7fc65b3d3edc	\\x00800003c74ed9457e45c1b30787f2a52ad4f8b0abaf745cfb20db9b596e74aecbce28342dcca8d5cede838b9182018ab6843d7700bf12715f08f60cdf837acc3581af68480cecd3337c9b8124650e75b8f7df6a22d433d497158de2a6d2388f2834bad4c37d2e822939c726b10bb10e93efe9ac463cab691c33d069c450dc7fcbc47435010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x67fdee494c30c657d976d16db2c0b50722035302058012405a1e349cf89d6641bf662f639db3497449ab440ab9af463259babda2e35ddf43998b52da9818f108	1637222444000000	1637827244000000	1700899244000000	1795507244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2d310461802eafa95918e210052a48555d47c9a0bc01ddeb35d1c216c3a6acb8793d61d58419af10aee08e7d3a92ddfdb259853a66570f7123937766abe7b2ad	\\x00800003b4677fbff8910a222085b20b416f4fb5de995617894ce788485616b9ef5699bffb655dcba6408fddbc14cbb2652b8a0edbc463a0e29aae94a1efd983aff9c51691ed274af892b2e777d3b5b4e2615fd899272ee2024f944feafd510e5b92819dfaf61281c23d00f045cde0acc12415682e149b43e2b01360d0a62af9fa5de959010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6b13366fcda826e0418043492b8741ec6a6e69f1863a2682676e0e0119f5c5d49cf1b9bf0e23bf5aa44d840c646064eead3272d07ba06fd55e055be8b9ccff0e	1637826944000000	1638431744000000	1701503744000000	1796111744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e25fe3a43e698f12e7bc345a49fc11d1b4694f784b7e1d957f476f6a712d56c5b664c45533f2214fe210e6595a3f31b1c31cdbd723328c80e93b8a9b9c592bd	\\x00800003be97a9da8456944674f9a2b5a3adf5f1784e91d70f609a92000f0f6a85b618695a39a6ba14f73e4c9954cc05156743ecc8a76c5285737e630fa2c5867e4e8ac24d77fc5f3570c15c8eee47c70eff1f8a196d960917bdde4f50ca6e2b871278f55682c0cc17e1e7b83db05326ae5edc63f39f0be93b263773576dc272da16f687010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xffe6ce97b0a448c42d116eaeedd1519d23f23d1b1c7efeeaf769011365d76339c29fa88a7cb20cadfd2952f34c0a0095d953c5fdffda632d9930c10dafc0ae09	1611228944000000	1611833744000000	1674905744000000	1769513744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2f190d03270f9fc79e24a8589303785e9591c90f22af2e46574493ff53343ce66289fe407e8527128ad4a1f2a5854175f8d2ad4a25f256d69c35c289c154d90c	\\x00800003c380630c2415ac52134d8f05be79f20db32388c5148911f800deccf62a15f273fb6ccaa253da6e061fdcf13f6ecb092eb35af77f9f8e213e342316419b7051b8b9b7d550f40f9589b2dded691deced1b698b439a8a6e241798e328377c8ec32ef7025c516d402f2319b4ba54e8f950cc423394b3173a034ef644c222536ebbef010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa6234bd2c48ce20e6df54c860521ce402991e64c0148257d1aadcab07df2f74708f16fa2037c6071b54036842c85e99b779ab442db0374cb8ca779ad4094980e	1613042444000000	1613647244000000	1676719244000000	1771327244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x31812c0e0c9f00ab0cb6f10ff11b018f542c777a4afa05db52893497736f74d1741e14a4b42a4bf2d7b5eafbc347dbf751911af38c62366c7d9bc02bb3b37d80	\\x00800003e1b1c783aa0367ebb4e791fa320104dd643aaf500a6868f552b08b9d29bf6e9161c7855a8b470ba5ebd38f7b3120491c807533ada3b509f15e41dfb823a2f9f175cda2701e8bffff4b9f878eefdeeca1aa147581b9d9eb657b86294ebfa80af18825fa215f20c022770e7b502b13765efb026e4f37acb887491baf4c750f67d5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6b3f0fe75bf10949e9905c989e6fb5f0c1a06bf4c04a457606f7e9c294acba712474cb3734c7a65d9928f9ad44ec8ee3123d3ada81db2a8806d1369a5949f102	1634199944000000	1634804744000000	1697876744000000	1792484744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x315d25ba629f25d9c08fb92fc2a30264e44a4480a370a9c733db64032c3e09b10d78218ecd5aa36b21cffb825e0573ffb5276a5be65b0f43528f07d31a85abd8	\\x008000039b54c1212eef6c854955e3c9f5e59e26cc8c85b1ea91b1fc18a4df41a38e95f531229b400a873f625454aaed39c1003018b94ef098d8c06e0bd6c9a67c7f9fa955efa445c55f770c23dac0f6df3badcd1aed5cd6294f5b009aac93849c18b279a71034932e278e17ee308513bad722854b2558bdadeca33910fcc1b80721e2ed010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x432c2e26d2426508736d5086d89601ba9b78b1c42bbba138416801eb37ce5d87c6383eeea650e416f0c6b9062626ee019a360b46b6228f811aa4d8dc5d38fe04	1637826944000000	1638431744000000	1701503744000000	1796111744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x337986ced9f37d9853344be06f91a501b50d851c0acf0d3d2fd243be4fb717e1ef876cd46832d6b5bd42432044eab3affcf17eaa498e413f0369a7f94b511a07	\\x00800003b359ca4754a9fa19cffadd24ba39de9a3fce19517e9ac93422380761a2738a52db13c9701f600e36359d4d973f991c28ff58b40f4dd6e7252e4e21fc2347fbd9321a8260791260596917766d313becde4ff69383f21eeb87736429dccc4efdaffebc81f589270cd0596f450e6ae845a8e3e385b61a5dd29675ac569c1e0d4faf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfcd878823693a144a26d408e2c34bf857436c453deba92e030a1cecb81ba8bf4cf268aaef92e15b82fede01c3ffd2f3e07b6825f103635f6ebba242cfd3b8e05	1625736944000000	1626341744000000	1689413744000000	1784021744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3d2582bf46c7323e82d7e4cb20b5c5d857cf3c8fafc89b80203c8f61f2229ef3b5e7ae26252018724688e8d64ff19b8781762ead864ad1a33f45a3da419183ca	\\x00800003b4b30703761ba26f9ff4de8f03d17e255468dbf6df3c53224e95ea5274b127ca3a24eb3ea51e9bae40ebce9f96242188ab7c1c6a01fd0246aac569330e1dd7aa54c3a65ff39317e53fe8b2125b067f7451c68ef1caa6405d4ad0c16599e464f124c99554efb9d03cd6a4c8ee0b72000ef15dd18deee4c3987255be4eb8ffa743010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x972856e4e08b61041b751dc8024eb7db077622dbbfe89016dd3882fdd7192379290efad50fea3cea2959b86ec996bacdb79618f5db4cc0e75f13ea053d7b9e06	1622714444000000	1623319244000000	1686391244000000	1780999244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ded0db7234e12f9cb2fdbc374ba6333223d20514224bc9ca54247f7ed8faeac74bb0e5adf35c019ced1c47afb4e559639d2764b501fbeed555ad24b2a274154	\\x00800003dd8467b5df2816e1ea3970985ce0e3d57c481d30ea58528dddac2090cdee5a1e343cf62eca3998a3241a06a87682af69dc16949c18f0a012dce7d69b1190ac0053a49350a39a534f1ad578dddf2a6b587f3c4d7179ade52a103ed4fe62d6ade3a579878b788063aff4e90ac90c8e591b5c57eaccc93964924efd8fc743a2a9a9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x59b57ca5f4a065937ca31e0fe1f91356fd309356c9e8a3bdda68be8fcacbb50d6a9946d168b63143e0600195b7594dea3b22215dd8e34b7fdda2d62a258b5702	1632990944000000	1633595744000000	1696667744000000	1791275744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e69957373417801c1ca09ad655899647c37c594a47b1dcda2c3bcb6a96f9a3beed8ed1ce46024b67048cfe7dad2a6df72c9e2a0c17529b865f3e1562589a0c1	\\x00800003df98f89c9942cc5ece959254d9bc33580a672ad647881db79e356bda9faeae145570bd1ab407dd554bfb5669c1d687c6f80d1e3e6bb17b19bb763252e917dedc59584029e0815c1aaace6fd9a436f31320d18469a1b8cd05f47a1a71cb9d2d6ac461760193fb9f8290b55ce112c0246ad1638d378aec3b668dc8c347e6ca40a3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2a56efd85826c033bbfafaf6d29c5c917145a322fbb9f0c8fba571e74088231d30530deab0feb5bf7a6213d93b97a70b948fa44a35e2a1eff852b3f2d9909007	1629968444000000	1630573244000000	1693645244000000	1788253244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x403d83f47c0651a0067ac7a0bede24b0cd054803cb16bc2e2ca8fff9ffe7c830c31420306be8fd92bdfe77af0936d40ea206d64209c778ef62aa192459a8513f	\\x00800003d271e6d8091c4aebb1d84b73155be1fedbe6f51a9154c926a67d503a43ce928bcf689445ec64d1543fcbc632c30a0ea726a8893f02d5a74e4468778470d51f5c9a5456ff236edbfef961301767024f842fe4f83ad8375271d3e31d14da0867f777d86a766849df762e7bdd052830d1146fd256fe407018be035051a081d8f67d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x04c097a1b0382d57b30dfd4f89608b7b5686303a8f29619845a81b9c59f05f723881fbda26c9d64f728ae48273db43fe4ed1ef2b581e690979094a6fb301bb0c	1625736944000000	1626341744000000	1689413744000000	1784021744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x40a12096364f47d1c1cbecdb86ee3a50cae624686b9245f44e04ac62ede55a0b268df22945f485e0df6354c08d3d41ac454fa70cd1b2c730ac443bd49afa4bbd	\\x00800003a33709be0d99b9cba3316fa82ddd6e60f8f99e5c0838c7342540e144708338d93a88ace37963564f01933fba070a6d4e2f23c725a4f0519c80b9a5659a695190d109d06254a2b4b6584c6c296874eb8e5540a05490f6b605db7546fcc53d57bb23cc5e137f5f9bde0c65edbd2fc840d928fca9dccc84a55091227173beca741b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4e52ddc3080dd8ceb18e1ea2047c1502654a630c33ab251ee5280b7f9297d815088595f6c6fcbeb6033c2e24a970f189eb73fe8c09b058c8e02ddeaa5caceb05	1632386444000000	1632991244000000	1696063244000000	1790671244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x411d63016465223f58a9d6817a1cbc8cde7c65fb11958a5bf0d4efce07ca9bfb13cc5f43f9f6f03e5a66623b4f6b91279fc61ff067032e278137540046bfc2dd	\\x00800003a7435db2109154d0f089d289f3f584fe5326ce67fd99689eeb9458ec77c81ca6779d78e2f21d3a3ca4cdf1b603b9a70bae63cafa4c8a9744be156d437810576133e2c2b862e7c0832adafdc7ef27187b8b12d7851ae9b77117c44dac9e970e7f0f1f4a8c11a8a22ae0cd31c854c46e5d5d1eff6322e1e53ac507c28181809e7b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe0167f758012aa051ccb382ecdcc46952a03616237f32f6d11af4b4189063476802b91bd1e8cfe49d9ec2aeee1fbe9a61a5a05b00e59e1e3fead88cb63830a08	1613646944000000	1614251744000000	1677323744000000	1771931744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x44b5478409c17fc84213d536726a574c4f523b4ce07cc029e4f5ed3634c56d81d8c5a5f2c3638382d9cf5ce6fb27a986ddabe7d6ce8b2f8a8a15e2400e188ce9	\\x00800003bff8390b2dcaca982648649a61d851f1109e777148f877570b55ab82d26d4d5bcc2bb5e78a49954d40e51fc4193132a88c5e8edd41deb7d02b7751eed3e71bd73535508b99c6a14c5eca9a2eb233f143c15cbe99bdb78f20766ed97c056f9c0cfd00452cdd4e63c04e00c822769bc05a782816ab2b5f4ac15d19beaa7fd1abc9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3b328614b6a352fb87fa468a5842163b41c5282d567f13d114a6f4e2a3caa6f82030304f492895293249260d50cdb50a3502115b5e0f7636d4eba3ad1789c00c	1613646944000000	1614251744000000	1677323744000000	1771931744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4605140d9785299c07d8fb18c07b5891e56265c04f8941a94c3e8ec464deff224b11add8042fafb5d91ee06f1544a4d0d75d8c407099660f8fd014f91bdf9131	\\x00800003aa7121ab202a45d2b4379b6765384b358cbd9c76860d97a9343c425d288991a0ba3f82724876b8da9a4aafa150c9d3354707536e36f79c475d80c1552af505433823ddfeb8b03834bb7d8af7dde77734b1e0871e6b81e2711b9efb747545ddd5b25271be1490f4ccd83c39e226bbfd67664927210a76b18f29efbf9528163aa3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb25b6328684be40f8bd3827df2c1007be4420b0214af65a3d38eca3c11f9fff8b586b255de18d6f8a95f762d78530668bf5dc5b0548b1f8c7613eeb7cfa2f90e	1626341444000000	1626946244000000	1690018244000000	1784626244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x46b5bbb4db8c61717ba08ec3c21daa7ea8cfc924c01c0b8a7b7b35db2f17fd8c0955ac7f6ae7515e39098d36b48c6b0b6491cd4fae6162c13043d4d272bbcdda	\\x00800003d1076b71d557ccdfcafc653de10e26bce739da74ae243554ab04349cfce6fbab13b61171ce63bef7672f35ca52d9bcd56b545e720cb9c09dc74560dd71f1aef293dfd4f31422648d4399026497642d2cd46de7e3d8f789d76e8ce7483f49e066e34dfb5118b37bf82a9761f58bb2458194842634674670332ccb2f5adee23183010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x599150bb60e5f1237511614d74740122bfe0de351ab666ebe3ef701fd6d46cd0a031f66bfc1c32071bee22bdc673fd64d531a8ee1fd29c31750bcbfc95fbb30d	1616669444000000	1617274244000000	1680346244000000	1774954244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x47a1b603491acd648766aeaf507576d0007753324f50a08b00584e87dc552e55eff3d67ea9106fc2d49c9f532bc819a9e3a3e6ca832a490d07d53125d60e44be	\\x0080000398830ffd6fd3163a457ad6fd99094cc93a0a4f597c8c13064569dc0758dd0beae91a7c82ab91ce9214eb97af582a86f3ef5c2139d1faa202507625b6ded43b36ea7031e7ac9511d2e0efc09bfdc120a737c805ef231df584b6cafc9e7fa108414d98223aa35028bd7894f997b7771e1aec9fe2304287152f7ffc0577b899742d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa8248009a8e1711d26cf8d5e45356d3273013ca5c78dcf8cbd42c70574de3e141f6a5f1492f2bd5abfd1263aec887631b0e0841c88e6664c0fef0dac8a91c70c	1625132444000000	1625737244000000	1688809244000000	1783417244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47c9740b2c8fc866efbc7eee30a9950da0104d0b6b90896e1d235e538201931275475863b4ae320af321925e8c4fd16a2f9958daa445342e9738ef4097bb18c9	\\x00800003aecaab90fe53545b3811d2f48c9fc25ea5f3c3fc0378cb58e6bd2a6514e1f8973343bd78769fdc7d2f1a97962746053a6a38ba3f507a8e783da2d66a0017dcd2db057d903c5844edf6c5e13d39087d6a30db413ca28b4074dac414fb722d33f99de6835d2d9fa1f0b206a16efdd76418d6de0a26d676b07326b89e242b9b049d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x34b1682a0cc0e1968579efd68b5c8ab0bdd463ba6e909c94b3c8a43ba1cec5c757010ed877f6a43a8004c9e6e759e21f86012f6930406b341341a862904ebf0f	1621505444000000	1622110244000000	1685182244000000	1779790244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x49713aa79b0ab4c32508029ac8580aecba159b42cb2cef2dab3fcea8b4b9c343dd1261bd7eaf84b99942194cd14360d6a5844cad772a996b902e71ab712257b3	\\x00800003a84003cc9028eab80df13304d146b0483fd9f323a9d2dd11e160c0629a4af29434d929cb489b12baa03b0a231039a81075a3d6d493a9f5c8c3503d683b4a8437dfe76665e186462c5f2d98a469bcd866627d50064214794d8912498732b30f5589671b7d4267ecd3911b459b8de421ef5e4c3b46d697ce9df46c4a88878f0fff010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x60266d877c799864662feb452ec8c08913b6fcc50190ab808d056b4c2e722ab20394c4249cf0c4431bd25417a0d34bc5f915b0f0c6743eb19de0bdc97661bf04	1618482944000000	1619087744000000	1682159744000000	1776767744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x50c9ee567a9f7d9c1d89b9f5c9094a3c1e53fbc611cb6af2f7f7f4bb2ec8b4b8161a8d21dc5fe9ee1246fe658e521c58305a08743c6bea4361bec4d659ff5b25	\\x00800003c8a9c078f705199246b3175bd96e5a51da93f289a6a9fdf5b4c1a13f0bad08f62cd18ea8c2606448afcb753ddac4f520af6a2d33458737808de829cdd593a82978f636e087d3e17f28db747af00091e46f339f67213b3f2517e87e8d22cb96cbc763c60f6291074eb44fff04001e4c09701ccff09b1ba05e5e1aa24dbfefb5b9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x82891aa3e01379cb70cd76f7e62f20a95aa022b0915bf1fbd708b2fd5a011194a212d8613150e7309298d067b27bb9df5f4b98029e9adb92c839b1eb64076e0c	1636617944000000	1637222744000000	1700294744000000	1794902744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52957b1c7d69ba96921513ad3b6d9c3e43db051df0fa22888d6f90d4697232adb5a54abc57a563a1d41762d8bd32a36e4aaf00098cc61dfcf1095ea357222501	\\x00800003b9fb062883a61b1e4796e52371a6ec8ba32b0d543cce248cb73b11e3cf5064aadc91b0a1d421b40e561d351f4417dd9385ce3af68c59d1eb9e0f2388c65bff6153a9cfb637e11174b64e0416c2dc78f54bfd1de98dd7436859093fab59eda9c27f7176f4d4533f92cb5d380b6f1f6bc0a1d93ae0d885eeff8a277cc604a7ed2d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4dd485513087ac66c307af00fe609543105a79ed458a7d12462620b25aa107ddab6e5d01164135d22c988c8ed5038a5df3c3488e95686897e351a699d8f7be05	1632990944000000	1633595744000000	1696667744000000	1791275744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x56d57c3dfb918195954eefdb67eb246c6b9b170eb3be7bae79879fd9ff6341520d0a18d5cfebfbd36b1645e5ee13a5c3aafc71a697bdc52bd03e5da15afd5656	\\x00800003cfa0465b1b1ca6f0ea4666149ff36487c32346074752616feae80ea284957cfb3adcd0d6966cd02633e6baa17f85aa9620425edefac2a600613cd9260d6594a1e4c45ea194c0d95cab9b0a40b664af0eac6111fefc36b908e9e05b0ea4cf586d93b22c1361d32baa4d97583c02294d820840ae54b34891d34041b71ddf377467010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc7862d615d1cd0b6549c47b75894490d38262405e2388a693c11563a4ed9371f085d33ba86dc3a6c6635ecd4beb600e23c592e95801577e2f9651800a0148504	1619087444000000	1619692244000000	1682764244000000	1777372244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x57ed5241235521fdc7157fc2d2cc40d8684016c1d58663cb2828dd19469f15c819621104a0581a5ab2043221675426dc028e4558ba30b5d1809042ce5d9eb154	\\x00800003c4e34405214b88e5f9d8acc71f17a092fd382390838ec71a2604a134c6b733bb1857056d6478c6515c63bd98b268dc3f819abed6d96dd121dd5b7ef5214405de5c7e2735f053c2e0585d09d1bef7cc110345f19b48fff8b5f7ce0af4538e9d707fe6dc6d5957216116db61b8ba6779b4948068f6d39e3433faec1a70820e4aad010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe7f47a89ce0eabe1796dd6d9485515eec575888154d91c013d14bd61be342dd69057c5f53801fcb5c6b24b3684890a87c6308b8d15e1b5acc189ad4efed2120b	1636013444000000	1636618244000000	1699690244000000	1794298244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58e90564a5ecc3aa2a2e4dfbdbc5b2435dc9b0afbbc56a254f3615f56564391133ae55177a6e1470d227b873d4462fe60805146b60aeab29753d1fe2062b4f0f	\\x00800003d0d417848b650defbce9cbc787695dbde67a0d85b43b6995c46f48582e4acff401cdd8f030f92237cbfddc74f710e7347152d5a07eff946b52d12881c37c5719d308e09028cadf1a6a572dc382826e5b0e7ec579d99e70e374423bcfb7856abb758b54dc5f57a54ae0ba27d4bbfa602b0704b4996aac8279a34528ae97d4b3cd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xac141859cde4c87027c79bd585b66804a0eca5a45e76dbe01c2b6e06ee6e47e7fac843968949d52049914f3d383d40b8254a600abd5e16fd4dc2048b3bbd3c03	1622714444000000	1623319244000000	1686391244000000	1780999244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5bc5d9f7836c8c3d0e81286acc579f89654a64ed6d8c502b0969588f9986f205ed7e4c776cd784399a7c22ec651b3d240a57d99bc78cb8d4344ac80740a9741b	\\x00800003d64e5f795a5cf3b7b86c2bd7769dfd52d6537f8b84d82600feaefcd5449659ffe9d7e33f3913f98d09f8ba780779cd22ec216e377abf4064036e325315ec6ae93a8a26aed0a7fe16f698fef12b44161bc045c440b688c14d24350824fab657e8ac049134f412a4ea78dfa4b863cb52794216987a4c86e0c284a3a0c2c1e1171b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1816ff337c28a5eeda21dfe37f4efd3964cb7ea19e172c043456ee00aebe22c94ef2250d2e28b17f332f7a6b5ac3c25dad20cc6606b9b4a34940fa0d89cfed07	1639640444000000	1640245244000000	1703317244000000	1797925244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ce96e733f439b901bc80c1fef77f57228d829bca552c038c7d066de617795e702391f085d22908136dc5dac3a1aa35a944f8e26ff51f4b1cfcc4d6614a6fa01	\\x00800003dbdd71519c8a9f9fad550aefd774e10e1639789f197410e8a7cbc9a01c9bf92ce3edb4c4fa59b2b7c20e6b32ddb1d2a335a9e0b539b2f6c2cd4351c6aaae5782423784a2612ceeb029482f1e5a3b203610d1513690b1d902bd0de76a19287a3d11866f4f9c809671ac99b880fdbda4b74e3b483573b97c7b64c18fe7730ea82b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x81bfe105a7b5c55762fc8bcad89b14c0c5e3a5c8db46e076ce7ed3683a78c0511bd4b89cac9f962ae22aa13c5a771ead87a2d9da0d3d0a26d42262c838a86707	1638431444000000	1639036244000000	1702108244000000	1796716244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cd5addb0e349617a933f82c16c97092bf32d5ff2e9090c7c454b8c3e6d6d449d22ccda44e0c4995b095f3b634d3f30da7ce40334d1ef7cae56418905d125e75	\\x00800003ba656ba84470088c80b6fbf9e0dcd70f922ac008e3d96f86d6c9c90ce633e20e07a04e0edf76c7e196d2095964dc07da8de4aba1ffb8e2d7d8f67450af304dd60d3d712c64b35003e5777ecf2c0727521e7c85d8f54dd5fb323425d8c880c4ca608dda0eff499b4c75219f26a67c40ef543ad228447d8f2d0bb8d2f2403bac6d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4297262c51cdeadaa610c5491dd5523da0d17723c91cf3a1ef7430a57320fdecaab3e1db3c0f64bcf304716d9a5a2d0ae24792fcf69c0c0a54e43e34b9c24604	1610624444000000	1611229244000000	1674301244000000	1768909244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5f958649a8942207cc9139791128e3848a176dc424b6c78585909f7483809027b4d589b712711fb7d56226a1f8cd7bb61516dd50024ce2a6ca82dc252ced2c62	\\x00800003b8e2ff2a8cea0cbef5bd05406e08330a97c4662f9c5a7dfd20cf96f495fc838579bd68b62692412286ec8738247f7edfc0f765843651f2866daee11af32eb9be2fb539159ded3db239a96abad8bf611380ff2caeb01f2540dc4414753f698001c9a80e56b1f89ebad225e7385e502524c1ef981844af8571719e9d3f26307e7f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd0ec60200c9279e071f535bc32d0c12f045cbca10428e9501e1f690d8dc1fd5b7553df20d107be68ad36e67076afe3f99a4d723b611a6a1ff2083c0d0224c507	1634804444000000	1635409244000000	1698481244000000	1793089244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61a978eec16b2ed58ff85e19defc651aabb18c5536ae9e67e2c92ac86c806f4185ae765bd260d9c1d48cf0c6ecf8ca1ca2baff8a61fba237c3a3e7d32ad31b6b	\\x008000039a25e60940fae815e42487729fc8f3bdef749ed2557447627cad81086b1b26eacbcb0ff6e6315ebb7739def33a0c7ab64b414e625efde086a239727ad0d54d3408526a16b61b30de814272e5d5f8ddb71c678c1624fa7dca8599f6144c82ff789fd4255e37308ab220dacd8ef2e965f62c153afb765219454f7b78a9c561baa1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9f2fd7d2a5a8ce61f089b40fc2ee972a965acebf3810f08108ed8a10f76c60564a00d9885170fa9bd30d01fb7cebd3fa79384e8c68b74a14f036d374f8c66e0f	1625132444000000	1625737244000000	1688809244000000	1783417244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x63912628677b5fa550181a68b6bea1e9b203838eaed6bfe87135ab3963b2fd398cc9349a177233dfafacc06712e4a887ab420d2942fe97486a850f0fc9db7ac5	\\x00800003bd2bf30e8667726b3a463c8b61b3364894357728bdf8ac71553738c40234aaf2bd47fc4b1c0337e2fc6835d08c2100467bbdbe4cdc0b86c87299de1f3a770c9e38d405494d869cff8f871b10003a650bc493c76ec3a9cb213a7cee4c157a89e48b9b40f3ac269ceab18dfe38e9049be1afeb8814d3e8e5bf43f4618761706e05010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8c7c4b427338060779cbac59874195f5f93e57289d7a8cc4d3471945d91e9caca86119ec7d12c1e314e920832807769e4bec98caff5eab1e6ee7836ebc2d3f01	1610019944000000	1610624744000000	1673696744000000	1768304744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x00800003c56ed070df66de9b85d5ceb223acd431f9984a88aa6abd6b6da7c10b474cf005f4cd34754b5a1fe4c726161c6125577b842cb8b73e12d5fd953ec7de0370df249e82dccfc6ab19d7a2cf7d419ee5df0497e85c674844e9248dfde24db79e5138d5e12cc509d37efdaacaf61df72a2e246a663dcdfbabd806e27e3e13212a105f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x17cd85e2a4a6e81e2fb337e4242e4457db682f3d03bc47d58d98b27c2b570b562878a015e027da54a47c56db8316c8e01669d9407edd3aa5ae57682c0b857f0e	1608810944000000	1609415744000000	1672487744000000	1767095744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x738d35046d1d1f5097d8833fa628f3496d4d00a64de3e31d93e32e32b0f03e742dee3ba2f905c3f19f2cbe9112d10413a6297d510e2ead4b2a309340464309a7	\\x00800003c68f1324a8cc555149b9f807618210f2ee48c9bae2b765dca6ca7c2927b66609611fb7662cc72d9b1b4c9d927f3eabd75ed2dbe502088ae21f9740db3622da5f4bedabcb590e304745a4104236221b3f7b60296669322e008504603f9f7385f733516e88d2dd157362fcaa4e188980ede24856ddc3358b561aaef7a9c904383d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7299bdb69abc29c3653e987630a4832f16aad37970fa6f50833532ecc3bd8053b4e4bcbefbd5108fb49f7c102483af5c6174821f331dcc2201b32edeaa9f080f	1620900944000000	1621505744000000	1684577744000000	1779185744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7379e959b17b49c44020d6acdbb42f34032f68a8e19d91c5427cbe215469afa9fe1d1290f897f328a85076e3330e3eb3f7dd3a10965f363ac2f73922aef4985e	\\x00800003ea27ceb3879ff3ea1c77d1ddd2308070c9128f8ab5b8c30f887936542d5927c8fa44f4caf134748015be56fbc695abf8372aa9050eabaaa02a07f2452015348fbb6cfa9450d60c3bbc21eeeb62571cfffea06d2c4093bf95fb4a923cae015df7c82fa30a2e4735fdbdd4b8e2034ce3712da137accd7a92eb9be7428ebd8ca3ef010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbe0d7671f4e1d226a3ec9c7aab6aa4437a217fbbc0388d31222bbe96b73ba13049f3ed6ff8a8a1612427c49f2285a7ff3f8a21c240a3a7e6338a8775e8ccec08	1624527944000000	1625132744000000	1688204744000000	1782812744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x730990a590c27d687d6ee069a82f964b7e454ce631388c838a78e48775983a58bcf3bcee8ede77e3065bb0e14be5b85d2854895a6af42298876c972482ae39cf	\\x00800003af5e6c3afec9d27c65db5127a59bd3ddb1f9082ffdd844af205420b6afec00c9bf1af40ac741a8089dc93146a06eaf0066da34b3d7ab9dc4dff99ca6d3b2d78f26ed9d31d1505ba1fae8f08584c6a46c07fa3be3a8abe9691d0d8907920dbef379ecbd3df36ebc5006b6aa4bb431fe4256f0ddde8590f4d4955183e6dad8f75d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf4d252dbf9e599a19b6b9e00196bd5ddda9a0fa984fa21d21e1834b1b8bc5552c07b9967205ef7b306187e55e338416bf042fe7830d08ce277b0f95ea2c5340e	1615460444000000	1616065244000000	1679137244000000	1773745244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7925a82cd33753f9d65cc5ec4d14a518445966729de799c46fbab608002a626be29cf35c1d3976a018edb7590d6d9975449053d0eafc45415cee3f6eed4a09fc	\\x00800003bbebc842fca2f9828fdd10ce342b30217c4a21742130d211271daf254a6b2b8b09972f81c636bffc4268dc582cbd10d6fa0ef22faf52d31632aa30dd035eefbdcaf5730203f258964d4e12577da028a300f7178ec1ecec72a6ffe057e35d9649a50feb4a4a6509c6b5766d7e688775d0d92a81c2c729d226841d070e2dc1d5e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5883d8b6a136debb900b5262d6176f2f23130904636855d9ef0f2b9a024e4473a95316d0f57132343703ed95f4d303d6adba45d0c522a8231a3cba9d68e4b904	1629968444000000	1630573244000000	1693645244000000	1788253244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a6d49a5ef14868facef306bf71cd7c2518096471cf3f735fefa1fc8eee0b91fcd320d277ee36c1237c122de0a96a8d4bd87098319a230cefaf632c7e78010b8	\\x00800003b7a56ddf587cb7f25b7d34540e1f0cae77c85b4cc722e1eaaa5ebfd5070e28532a8cd0514b7599d172cfe7fb3e1dd42020eac93ad37794a794a4b281a2e7d14d7ae17d57320accf7077e9374ee51a6361c3a8def6876b18b09bf5caaec3ed477c9e0601e855c9aa6257d7b21fe296d65ca772631a650e6e9fb5cba5392f3b20d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7736610d3dee4697b4367cd739c09660325dd050e1a01b5f514befc9d5f993627bd98122700233a4d8226ae91f11f3bf79c40254c02bb491af0d5ff46fce730a	1610624444000000	1611229244000000	1674301244000000	1768909244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7ee1ec44d39807102fd9d3aeb6c2aba83582188ba9d72e8a9c24af12b60c1ae3dbc50e679fb01d938cc3393c89729514839933384670c99a1c2a66b582991881	\\x00800003afc113e3de27dcc30cfd7687e42a76e9cfe5fc88e158d75fe25f4337f805e8b4ad217f96e3563d3812d18f314be707186bcccd6e68b8d0da93048862796aaf75bed5f4d0fad0a06300658b7e370c66046f95e7bacac95a7935240ebc16e9aab84110f2def4f3f4f66fcf3eb40bbba58271cab7692aa4ccf3b9b2c991e729f19b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf79f5aac44a1fa8b0fb4e2d79ebb1f96e4055cb00a726855e833026371f28e7b9993148422ba1149cacc584f23374671e2f908949eafc99534325c603639d80f	1614251444000000	1614856244000000	1677928244000000	1772536244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81d53ecb43dc3754a080fe32354c707972782d12e279afe73a6708c6fae800a155ec4435da5b3cbb3080b0c7ab46beef2e20a073343e3ddbb859eafe31348514	\\x00800003beca5ec87ea14eff2235a20a953aae9758b6018303da3c2470106a6c128f18daa5b38559d2c6ed3ae3bbb2dba12b87b8b0a80b7fd7f9c2d304cc75c9d70f9fa773906b24c02000e86a1fb39d9db03841585241bf0c1a143b63a816fc872af8fb1f2b9f98a031c44da47a1774e87740a4085c0fd7a9401bf8f5dbab1063fbaa39010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc8c7304c5f2a453d41904cc94a1ad7197b0a42d18ba651b121fe2ea5c2be1c516b1f4b1523c49836e33a6c76a1ec95cfbbc32bbe3f4eda63867c283d67b9ab08	1634804444000000	1635409244000000	1698481244000000	1793089244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x831557c51e3d5510fac9e5a3ecde8fab74b5ee7335b63dea06f4e9b5e6ec26a902e465c51d6e05b2cb2443c105cdd8ea3f88e474861e8f2142e4e6f79751e814	\\x00800003ad44973ae9f2df79b273e01720acf279038f3572a6d5014c160104aea0407cd59004d218010c51b165272bf5f4fcfe1c1d275c375645647e04ff9847ea037c89b78d8192ca4faefaab358a4980226b9ee360244f464cf492e543a7c081396df1388265b16aa65bdc667eea11c8d8232c443d4fd6c6ce0b6be2a828be241792ed010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc6c351640a967223f276112da04e55562d3a3266bfffd9163c70e1fec096f34e7ab83e627a13da5e1fb8ceea4223fc5ca91d8f927681dfb74b2d941e1447350b	1633595444000000	1634200244000000	1697272244000000	1791880244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x84b179f21cc3fd2663a319b23998784910533486081a5516c6327d0f218100d50808b12e16756c06db8d4c9dd12442fb6433da149ed5c4808e7c12fd295cbadc	\\x00800003b6539df4af8e003dcb6a3f330399b538c34bb30f3fe089b9e979eaec8616b4b7cfbba1b5b9b615b74a517afd16342cc03e5cd78a2fb8f46b3551b37b85859d28c1d428b874f6fb7bb2ea997885ec8937d16574e847e4ffa54ab7e06f498d67dae05c011bcbf6bf274c4e6316b5a31821a17599c2e56fb32da46b6f1d69791511010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x92ca5394e9268c90aa78ff5444a585945eccd8aaf2e064cea034fab50b8051974f6dd98c67c910bba7842baafd93a8d2cb436abd3128c73f6b7dea4f5d0ab80d	1637826944000000	1638431744000000	1701503744000000	1796111744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x85d9fdd1b296df51a6a62649959f7410e282a1925377317503d73dbe5da4b911ac7fa5346c8a674a2c9f93cba0829d2f8591d70e358bd6fc2d7bf00d198fcd81	\\x00800003e3ebb9607559cbb8634df3e1c9f1a8d26048bcab007ed54c0123d1653381828ac7554cc7e6b70365ed00736763b211933e76d27c505f11021d544ef104a2f02927a70f06070d526c54517eb687b10523b21e0f827c7aef648e10db8334bdf3f5aec543b5a95e7d9188552b18a227213390cd2fc332feace13cc17247150f4613010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x592817d676cea31e90858e590478cb18d146d67e3913fda5837404d66c06f9aaadaf4d2715143e02162899784bdb1734f43056ac7bf55f7cb944367802f0dc0c	1613646944000000	1614251744000000	1677323744000000	1771931744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x854104e65d2f9da8e7873a9e92db4a298122ba0263e0c4f20bbc1e30b2db60e3e37ecaf71219d9e12af8267991bec3567cc56fa5cc05aacd6c04b44aee299ee9	\\x00800003a2acd3702910487e511e36bf70041657b6dcfd6c5ff039823fac12b1d50271051acf50d4bdc6f1c8c96b1bdbf1b3d459e55cd8dfbba956df150ca874aab1a0034233dc8d831d36ca4fb36c056b2067d2a8daed72dac4d4b96aad124d775622b38776cd5d392abee757a04ba0a819309819e2ab6eb847300b7b1e09b018886cb5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf67275202a761786584f882afc58f89c4087e976f593b408d17682ddcbdbfe35107f05374171fb43d46799c088cac2032741691396369b0d486e80e667c38a07	1608206444000000	1608811244000000	1671883244000000	1766491244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c95839440a41e6b950ce6e9a58e7b65fc4fa142f4d9910656adea105fdf24d95d1ea855aacac70cd9f55f125e061b192a1808dbb581234d965973d1343ff3f9	\\x00800003d3082cab1e0b9fa3bf2e570789cbb3e2d75e28efeace4845560737bf0a2f45a314525f286d474507d6ffae0441c9e36b07a1db5aa44bec9761caa550b4baa9f2a70cc0fc2ff894ebbe851c53115c1b127689f3a16f997ffc73d642b5610226c9840a4e896ebc60798b5f750ea27b5776036f38cb51225b0e712087472c14b99b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x913ae1a1e36bdb8056a7530ec00b288513621a2533629ed36bd3853e48320da67b502091b386b5032de39f7c1440815fa30630d31a3f39787f0ec2d3662eea0d	1612437944000000	1613042744000000	1676114744000000	1770722744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x96a19a83b0e2f47cf22de1247507df16986136068a9eb94ef86fbf5d987d13aa50a1e73f0a5d9ce25272a6ae9a86f1eba73c9d8d78e74771ab6511d246eab8b5	\\x00800003a9c33226759da1ba990eeacacb7816071c9c8408e326152a4e067eadf769b3f485292e7145181edfe06a53e0a1b38946538d24ab5f3267cbf40309a0ef03fa88e8155d279ed251768bb5e7f9d9158e12e26c11fbed8fb3cb66ecc6239ef88dadd3f69d3ff65682895f53d9ab38c67c986b46e44698571f03f2e42512c880447d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe57dba1003d47fd56d4f8ba467a1ba8c4c8a50120cd7828aec6c4fb38c8d0605685ce48f28dd88e7b26707c5ab0d36551195835bc59f0d11ff7f7d4221b5cf00	1621505444000000	1622110244000000	1685182244000000	1779790244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9861d511a57016ae752570944083ccd8b6dbe9e1444fea545008172eb7d5903bd1c3ab9e481a502217e215f884aa4885569bea51bfd0a8874b9a2428cebf3261	\\x00800003e991ff24aa216c5ec45a46007e69b5667c94c190dfa173d28b5e523836618428bb987a187ef929b1dab081dcb2ac69c3278504374270d90f8063041895d55b4aa9af623d2ebd48a8e4ba72c91f5bc5ee2c31c782a5c9bcc8a82cdb416c46e67998a2651b91e8fd7c664de141c7f1c65f7704970273b942ed9ce84c43d9e5f1b7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8a0d4cf49975a6fe9fc8fe6d1e23dca03f6296f0084e401db4e003cdcc8fb188fd9b959dec39e04b2399c94a086928c6f2b8a880681ada38c3394a896e149c06	1632386444000000	1632991244000000	1696063244000000	1790671244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9819644017eb5dd54618a43db845d5b3d62fab1f0654a40fd09ef85a7c79828e8da82b1c7db2cbfcb6010f3a0b0ebb0b691b5b984471796ee97c900fff298f68	\\x00800003d387ae823fd84e430abcdf01031b5f649e073b048a605f732bda2315d8779c2d846b04acec13a0f81b765b31b9108fd2b1dd27b4c482d0e035fde96c269d3a3e3d76355c7dc72c79c752ba81f8f31be28ace1796cc6e559e8bd018bb7e1242cf27559e650b7cf620f6bddaf7b2d4ccd03cbceb0d15f895aa89eba01df560507d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x128924f84c1d77ada76b23188aca3d416eb8cbf070e1bc1ba0b46c5eb9ea46c9ea9a330b9894672f4c18fa6ec9790149fdd3592a1165e7fffd33770a9f25870f	1619087444000000	1619692244000000	1682764244000000	1777372244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d99c76961048552f872d965d3b02bd579a70de11c28e46e3ad9bb3bcb5139cc2876fc56f694bd4fb2effb9afbcc3ac28a6adc4ed3003035a57b6e05f8aeab11	\\x00800003b9b3f513114c79d61951fe53c81f2d5dd24d005db62e7811f6e6b8eee719c5a87768d872f277bae820f1b24a6911e142c5631ac7e25617fef67ff3ae83a2126fa0ac4c3e47ad343169ad33562c3beb4416a5cff794d2e8c72482dd659f0e972e3b6465c9fb0815225f3120143f823849d8e07a9bbb5d02f782b24f03014e68c1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe976d6254d529a3e67fcdeee0dfba9888441ef21b62c9682c970373f9d448e60baee0769f62b69df7a177fe895b920d41f5fdb30976b36c94cdfa198d8810b00	1630572944000000	1631177744000000	1694249744000000	1788857744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d498a77e845f52dc24deff45123685b389b7a7ef9daebf058d2eb99bb78a4661391690bc29fc0bd6910157486f2d2f643bc3a2f9c696b4a38ef12af05ddee8f	\\x00800003d01d57e0d714fe8c2363bbce688a8bb69b3d8c3bbd36bad66808634192ad7d015a3d0f2f20f53176c66269830a6e39f37f3cbb12f00dcbc88ddf97c03b01fea4c7a48eee9845a139a841b6acb7a4600073b4b4608148dd62dbc2f70726cb52e1527648ed89c6300b50c6512493f4a8f75181c06b89afcc9ea0697dd37656c0e5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7df1abe1661ab7633cac22c8a6fb76933a3803fff4d8c455879986b545522522e0816e76e119c33fcb02e3f0fbafa32405006c4bd973508ab7327b20b9fe1300	1639640444000000	1640245244000000	1703317244000000	1797925244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa1fdd3e5f12d4e0ddb52bda74ce1afb56c0886448939de60fe82ec48a683a1e74b59dc254d0332d76af151eb39dce3223ce7dde01f28b66f8dd66ad4478a9dda	\\x00800003e0bf51dc3a9afcb6ed7ce25949c94e1477c916a2b2720cbad8fdd7af915659b17f12935ffd771473a1a5bc5c94381f14841c2b30e905aaac6581b74fd54f584444cfa1fcf5cc3aea7dcceeffb250163fc259ecc109a861ccb48e22d7d3e24aaffe986d025a2c12ecd573e35cdab45faf4a674e0638374ad7a2a6330617a87e11010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4b9a2508f5b683c3bff9aa0fcde442812175599126e38e214b89eec0a2618421013c4a6642bbbb90187d5806c1bc7032fe2791d9f0f0e1f6fffc8b3f379a4c07	1632990944000000	1633595744000000	1696667744000000	1791275744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa48114a42d6fc428069a9114cfee4b0cbc52af4b775524d3a2fa99f31c0eac561f905d47b968057ddb0b29c6b2f12191c424fa0bf3ed0b70c8fbe4f3ea2099ed	\\x008000039d385e754f95c6e354c042b1074d047a40bef677f318b95177f578368fcce9ad8ad21e47eefd3fa59f39612d018c14d9333918c5bf8a35d2d2ff8a8b2bd54921b7fa7d73f792f9efd18a133b7271b814e15dcf1e57a34f34f46484214d4702fe7028b6d9ba98ff72414198ba888ffa0fb0d055e994730a8f5725c3139cdabad3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xccf69b22ca58f5dac3864dcbefd137d0880f3393b67ba0288aeeec50d836e1599277429c50de369bd480e28c8c1822aad916b1d5eba435012cbe2df0e2604901	1624527944000000	1625132744000000	1688204744000000	1782812744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4d950c1f8616610cdca5d88b4818ee647fc95290609c7d57cd2bd79033dc8605f8bdcd167052ba63e5eaa2b3575a9273b2c654d7a60f4e403ec82d626ad1cbe	\\x00800003ba534d8eaa3c80ba852e17efa35229ea38b09aa29e32e41e239359d517a7577fd1069cf489ee2b182b3cd88730cdcd8727a7a12241e5e01296628140990bb63356bc3202423f48cb1ff9ea0e3e0b7512bbaf478c1fd533f4f5dc39b06051947f32056b6861942d8e2328bf18ae1285204a6e227d0bb33c636c0526bca241c3f9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4dc321e33e58b3e9a303492f853a40aa6bef1762e64174793aa8206f10328ee4ce3df00de8cc925370c50617d6374320c85eb8f2e5d28a6b3dfc641f131ace07	1635408944000000	1636013744000000	1699085744000000	1793693744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa4355d1aa8d73dd542ee749b83f55c2e66be102c40f554c6a186606790756c0f5780610e75f92892f137cffe2acc67288dc392691b850924af6ef3c3e5b2ce9e	\\x00800003d6de13c7b457e7a7dd8c38638b0bd93f51e0749468bdb9a8a0ace5e8632ef60e9436e999e4736ad3a619f744eceb93d9e9a0bf9fdc662fd1c7e03daef9acfd998beca6ea90a12e98a7e83f51968db1c26eb23fc9e0077f6493b420afc39ad5c899e7e1048b6994040a2ebf1fce605df2d930b497523aedd547f7ebf6edf05c6f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xccc21239cf33d22d9e55fcd42068abee83cf66a3201fee878443738f505b46349e00bee7f5e7bc4657e9d8f3ba6f72ccb54674757ec76dfa7dce4acb6946a50b	1611228944000000	1611833744000000	1674905744000000	1769513744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xade9ccfbc8b70b5f40efa5430b7354f82eb91b273d4845eb03cbf855e193f77e1b479d40666e5fc13c9cf08686f6c199da4cc1e44e9452a5ab09122fc143d8a8	\\x00800003c3ad41c0ea895ba7971beebb57d7f9ac77129f120923766666c3e1a8fb51e322ab23957b6921f9c9f56444c50af3329141228c35bd2561d44786f5fc1b4bb84f574d529b8563d78bc7a0d522ac41844293c5e5133c3ffa96f14db6a472c8cf6237d68ee166a438bd56fdf813cabd4a82db8a6415cf88b802d1e42d54ab4c796b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x180adb384cc67852354f9cbc2407c343d84ae0d6a3ce099f2258832fc894a4dce513c3a47c9ba8497b330b696b4aa44560e8f3fdbbfdcd951d522db2d31ed709	1609415444000000	1610020244000000	1673092244000000	1767700244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xae31b6de7027130cb421d66d7643e33413a9c05f2b19dae1a0958a2d83b573b3e525452828ec3b2a05da1132a222d67dc006367098755b0710c44c0eacfd436c	\\x00800003d2415491b8ef419d17dcd4b7965eeb79b0f31b8ecad6364bffba79055018448436eb8e6277c47a26362b8d26ab83bfab38031949fdc3c305b30baf4d2b29c4440d64910a06690b2638a6397237c2bd5d9b5e234ae69998eb0415a1200b26d2d1071198b8d245af84fd6d3954977070f86fa15269ab24ff04be00338bf4ef5daf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x45c8befe4bb3c9cf5a102955880f1142fe79dabfe3c98d7ede2d190f70a41a04f6ef93c3cc0d1f353137a27876a6c50b3e3466adeeafe7ed90c5c33fec91e403	1623318944000000	1623923744000000	1686995744000000	1781603744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae0ddf29cb4b8e2c48fea4ecaba52755073e4102a487180293b19b8e0db8d667642e1953f23683b65973ef5b27733f676a926c45e9657f118e12fe48e2f5c482	\\x00800003dcbf0b9a49076a309bbfb9c2014949a337f3bb576c4c86caad0e6392936fa5100340520ba9502a992c062c1fda0c34b65243a40e9b1fbc66e721eca22e258db197ef816338c09f53f953be9c7673b5608d9cd92a67d61c984a8b9fb3469f77708b810644ae4084b14d0ed7f7f710e86de4dd1fb9bbab56e85606a85aa2b4e371010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa5b8772704493a20ab062ab0f96c9a55e70bfa7341a092deac9b1f6ef4af5d8f636c30ba9c6d3364ea88b4830c6d30c255ad81de89c754eed64bdc2af70db803	1614855944000000	1615460744000000	1678532744000000	1773140744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb1ed42ed51864ff96b5c75125c62f9ca3e0734c42905484f3d3057207764aefd90bf54c9717793d41a33e292ce8e028bf14b7d2f9376ce0940dfe0ca34719d1f	\\x00800003f47db5db73dcc7c9d9c563cbcdf92319751c75ee0bba16d836ba22779783f6a42ed43bab7556db8f19aac4d07327f61560b492aa18c05da3144e661b98d7b04635f86456d533c31f1b4826f7da69e3260278c385cd6ee12a3a23afd0544d06c66ed7791e611ed2638efe18a00ae24d75ef9846b1d4c12a221327748b91a691d5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x63449fce8d7f932a134f3f015cfd2d6722e98391a16d6c39821f88b3632f6a1efbdf6c207de8d143f161736de4bb4effa8aa58492a2f0c51b7e175b78e278a0b	1629363944000000	1629968744000000	1693040744000000	1787648744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb159bf84bc10e91466e31ef08caeb0e2a889254b5d8d5f1ff51adb5c99631ccd20de85d0a6198cd018b983aa8432c3f111108067e0d179f2d238d410d92a1732	\\x00800003c7d135c3344590143e6b942aa28c116fcf4cd6d7b7857bfe7374d3e148feb1e80da30359bf23a46bed94dd09b792bd94b42e5cf653f83a9db57fab1d4881bdb63faf9f6a27ea43199649b6f1960d3fcf5e26e4d3795f68c471fc400c461878dcc80e701cbd5c7d83457d4a0aa16ce20ea1858c759a167dc7030c935b6eadc905010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1c46bb4be9a8817ddde53916c378eb30196d728a85a2991b5d44aca8d5a02fc4f226c392252a89868097762175727e1432e357f932b16e90ba423ed2eb47170b	1627550444000000	1628155244000000	1691227244000000	1785835244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb3111d09823a796dee09d528e93b274185e2447ea827ce88bcc4215373366eccae49696aa7446548c5c5891709887e5730b32ff80500941c7cfd1d5ef9a81374	\\x00800003cceb7ffc140c2cff46fcacb9546a0e86a2cd5f1486858c4d10cb548b205596ae79531a2d3ff71a215c3923c807a94fa69574c8cc6bb829a9c71c8971a05b9920d70ff85447505345b4a27df12c83bd4c674bf9ad5398dee0f7c25a098d4bdb1a87dcbaddb064e67fe6b83c3996a98ae5fbf42621ce9ffae61ef5a09d61ca1f4b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x24a9c855f1b936c111c9f1e1a46d48a13d75dfe4cb4858b8ea761d88ecce97cd0bc18e918c7ded326aa9d36bbc2f584070f729593dc1e06d405bf6c059a77e0a	1626945944000000	1627550744000000	1690622744000000	1785230744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb33dedb27cdb56119fd9bc8a7806715f0bafa61c4aa6aa185cab4666e74df331bdd7de8054bbb4fbff4ceaa98ea5631124da5cd3035a8aa78ff21dd694bec2e7	\\x00800003bd586c38ddf1e487b50a5e66602814cd5d0eb744e6ba38809a2d2f17bcc1272ab07fbe88d9519db2449ac498d2a9b7d062dfd57cfe632d43904d4f6b2c7a39e775662bdc6aa52aa2a3a0fb455ded266e63ec89ddf33e0ee644c7a35293c81032969cd9f2db6bcc5e914457628fe6523711d60a960492acbee94dc22e11308117010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x802b5c043750aaeac1c3bf0354853029e9c3eeed5891cc03e5bb323eac1347a1c06d373ad0f74d227702582b8f2b09d0ddd541e1e2e794437e65a9f90eb1d800	1626341444000000	1626946244000000	1690018244000000	1784626244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb3a59a00698df03952ffc9b8e248d3b33a8f79ab3ac0a361d88d0e8acbf812c4ed6a1d18d2a4f7d00f4960a3e178fe495342aef845dca208a817c0bbe7d50c60	\\x00800003cf15f3c26ee6796ce909a17603e15e525a54bc2e7a2ce534e041c87be389a1ca61522decfceb220dc084c1ca607d5c33a24bd9452af3442760612e4771e3323654b8591587d817680d5c2c9568684f6a08a97346694309e59d51436fe2c84b2e1dff6b0960b50798f94ac4096627388195351b254a189d515faf489e0d02b46d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfbe5a675bb5e4dfd025d52d7dfb1b2a32acaeb730d4f8c41ea9c4635b02a88065a1048e9968c2970c431855009956da50350d6ad202ed2344208a080803f2303	1610624444000000	1611229244000000	1674301244000000	1768909244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9a5c3ebf19b6839c1f343622bfd569ecb537b549d9be0b82d5a3f6c7074f0c3dc820f9e57a413679b9ff6678d7bad021e3535a45ba353629784cd9d8f618989	\\x00800003c1de98d3feffe5fd7b59008c50faf2845fd556a6b04065587583483d09c44171b71f906d8d95e4252c9dd140f3ba31334bedb9fa1f6f30b433d5ec84b80887e31e940cc7d3350b39f808bf000a4f871bfaceff624d815c4e8b7403be5e09e72bc4c0b512b7a8948ab62ecc37497199369032ee7adef533f686a353aaa5803c6d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x05774792faab66d4ab37640772832cc40ea987b3f2ffd84403ddf0cae8bfacb48b57d5eb06498c5c4ec2bef193c7090ac2dd2e5ef114e2bc8a9415d710b75606	1615460444000000	1616065244000000	1679137244000000	1773745244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xba7148a00853c9f6a803ce09fb1a709e0045be0091c689cd9404b6d0b6f82106b840a78d15715b6616397b42f15eb0eddc0e0f5f60c9cad0231b6a2fe1453489	\\x00800003c8895e4bc0912cdd4633bce27f41ce8ef0482f6d455cccd8cd734a2a1b10e1027075ed3a6325aab141ec36416d19d7f1a993d5e9d3dd457c5a6719b291c3bb6f03c2d0f06204b820ee5948ff85c1bebca4f8da89ff4642c3d4e631b54245034369974bece6030b9ca394ecb7663847df2d34af7a3984b44bc7d4fe9f2c7f5671010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbfccbafe72c85b6f98cde67b6ea49c710e42b820efb121538f20a5ed88762e14de9d703e8023231a1a051240eb2a9971faaac723cdb9fe9f524a3c3c6e0fac07	1637222444000000	1637827244000000	1700899244000000	1795507244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc0c11ca27bb5396b6c69fc6eef528e0c28d99bfc6b85937dab5e5c4e870d41ae3ecb409c1b2f19150dc1ec6b5a8909d1b3fdf90a82d592ffcaef05e906d47cde	\\x00800003c345f771bd7faccac4d8e7041b10468a4b4bc2f918ef3e416461be71bf9000614ecdf19ad07bf7a43584777a88bdb08186a4001e1729ff34093e86a8f04a10ba2905a5eb3dca5451dd1c88c8e1a962467bca214cd38630131970eb3e42f5e89086831935afdb5b053ec5d203ab9eb313c9b0f22c8a20f804a0ffcfb190e3c0c7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfce515ba6dd98a1ef08cee45b02567d1f2637bb1b10a4b0653ca464c119ef298b59f5a657721857d4e4188bf2f95a278b36879319dba44ae43fbc66b4ccbd105	1616064944000000	1616669744000000	1679741744000000	1774349744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1c59874ed5cbc9b14911fe88a93ab27ea2cc3c1bca410a3ad3608b82c89125aa9b43fda8c858bafc7ebdc5aab89f9725afdda1b77ef1d266586500e42b228ad	\\x00800003c13f1e2f48b9e117283d97546b399c42996a2a5aab1365fe6f72dffb4d732ffef0330c37b38d45da24dd9dea62ce279271ffc821e6ee3a57b03b2cdfa026aeb64daa912a89160d6fb8abc7bbc4c9f75d644edc8487e68a134f18b5d59256b3020fec4f9d279aa97ea2785796ec1ee5b64589d19d529a233ab9e52b21325c4291010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x126cb245f5c6b36b37dd74d66a446b6fefe9ab3dd7e8cc233427c1b53998b810ccd693fe4cc4b952d62c1afc19250fe83dc37ea54418db4dcec8eb3d7fe5c907	1623923444000000	1624528244000000	1687600244000000	1782208244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc835ec7701e4194f689d9ade59c005c6d219286c86097b6a08be6fde035bb19c6ad5af8e2fdfe5cc1a37697302d8fac925b2ae483fca002ca4e9331cce5125cf	\\x00800003b860f34d4811c065df4ac8b7a8d74e54beba8a7199c48e6e137cda5c12a46909520b374c5f5bf52e49ddd08c96a03b2a2b5aa45a15cfd8d7d0b90273e27575c1a74d5a1960b31c3c8d6b81f8b21e582adeaa36b3bfe7a5897236510d9fd6ed9452bd8a6004c9292b6b1071e71bb4771624227d443ccb0909df535126e6d86c0b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3ade19d674091f32d745a638efa54ae88a0513d1a858b471b0a2f0866b7ad5da6b919c638b2e38b527546caa39e28066692c8d0f6ae7f0094c47abc8800f7608	1613042444000000	1613647244000000	1676719244000000	1771327244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcbcd2f25fa0e9f8f38f1551e03e0db8596664726fa6bc4bf3cde3a3ef235218065828a69f0c22d22e7fc18b30929a7a401921765cd0e0bc10e856dcac1ed74b4	\\x00800003c770444b3245c3221b108e546d0f3aec5401a822b9ce09f422a0e175ab40e1143732564466bb79e2b82a9a6e21386b152adf01df9af7de40b788d9d6adcc1256f0fbd8ecf06501e6809a1bac72018d44b7d904f0b644bd5523691773e993ef8aa00e8533d1fa9b4f9b111205403b037e9baa9ce38a9e3d20bc0be2b668d23261010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe1ad12f1841b0651e27e377e76b4aec4fb76160c2452413101e7539179336886fe45b6d41e67aa2699ebd9e3646fa8ebb69ef03aba65d51b716613760795be0a	1608810944000000	1609415744000000	1672487744000000	1767095744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd21155e35dc3d2ebe37b33a1084e3d0482cc950edb13a742ca4b4a47317a4425ca92211f195c6f9de4dfc64651e095f8625c49dd0ebf7029700e3698c62f7393	\\x008000039f33fe61311741ab06c98d5fa9d91f4392686a75e4eb44c1357469b03fed23650ef59ed88e419752177b7fdaa4d5bb64c2dd65215375e20fab49fdba6f4abdda8b34428602882d71439ac86d7b8c7575afcb191adea6d716074a76b835a1a56f3bfeb2a72b55977092d3a8b6cea07a229f78a6e95f7768fbc4f84927a5c9f1ad010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbc7ce8835a60958160f7c9acf564323502c9d0abd25e0b0a7ff49a8f88a50e0d3e7e4a9acc3feeb6e9c057874379204067e7e0ba58532c635f14118550aac201	1613646944000000	1614251744000000	1677323744000000	1771931744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd25521b663ca84975e117cc5f1ec73ed970b8801aa741fe8a790d6ac2b7abf28c6be6e162874dd70df4e772a3e0bc1d3261c2ab0c84ff4880b9763488d963913	\\x00800003c8176184b731b4f99cb15679dc7acbeea3d2b5300c08be901bcadc8e991d38eea415a53faaa1d718b51cc2c5c9194b94379d9900f4784d2411b87ce5e2d4a50fccc5a80076ccc5d951167da6882c78cdc0dff0317cebb042c2af4c80bdfe15e96ea58ea294045865fcdf383529a4c22a094eac4aa23828c9e51b292e9b3236c1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1cf511bb463354860006e4e2f9b423deb6fe179665f09a01b9b8b1811481138f8e9ff7b7c49aa9e10b1aa135a0df7d241e1ed844076dacd75c2029834c30cd04	1609415444000000	1610020244000000	1673092244000000	1767700244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda850b0a30f4a75cc45b0f873d3b662d07cfc8e1aa2b61623097e3e88521e496f005f7d02ebe107e7f1f66e17fdaeb93d247046d107f5d62c9d50316fde338eb	\\x00800003b57eb5569c1e268c773c5f41b3f2ee56c5cf8aff98c63bc8e77d806ed4bd29f6a4ad716833c8754ee116deb1d4bf02048e7b8820f86d1c7922e9addbc9923407450d980468710d092176b0c7b2ebef10be9712d768cb96d6894af6e42374c7c98229813e3259e1cfb7521f0c7ea5d05823376140348dc4c72dc05a1d31335645010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x138338f1ffab50bc945d0b1337bc0d4a74e303b1c112a2591dbb9b31f86b09488009e18de5542465e41013bae9c42b1597b9a230bfc530e6e5ceedf351e18e0a	1612437944000000	1613042744000000	1676114744000000	1770722744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdb39d6bb4cea80ecce7345ca23ea65d1725a441b44ddd41bcd5769ea9a89cf53824d6d38bc3e61563fd8aca9228369048237c6356ca43d329abd85e48df08003	\\x00800003a5b21fccfc35a5f30662fa1fef86b15ca227432ef6d668b1e46af8e247a6dc6f73fa227f39b265f407ff9dc8facdbdb5cda355772b8b46732b2c80ba3c3d3e5b831f7678f5dfcc724c27fa55578f9fcc4ed1454ac887158499c94cc8f9b6ba44ed6eab5f8c45b90da5653aea63ae3bd3c6cbe77799c0a8f9f7284f261c102f23010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x36f03710b60c46aa37c11c61923cb781509e28fd16f5b173bb6377a08b96f40887f6514b0891a51d36c0e8bd932bafcd38bb8dad19e3807dde98f291ba99b00b	1617878444000000	1618483244000000	1681555244000000	1776163244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcbd28b4e59feafa9996ea906e6ea5c9e9989848db83159aa55728bb0a0d4d1cbc3c41b80af51ae496452ad2389f890f83bed6dd9606b95dd81db63fdde2268b	\\x00800003b7e959e7f3f038fe8f1355bfdf7707ed64d703556126383df47f7809df35d8ec1cd9071136c3ed1ed6de54a20a78a0591a8ef147c4327326dbf2355f754aacff3f107daf4c5d551d849bd99fb1bfa384653bf9aca79a55c0147a66ae50eb465c3ecde07e05105599f49c2a77980d1a4527c1b3538245de38c5defc7d4b99e0a3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcdfca7cc3ba504ccbab371c47094bae4dc5a066bf6d34fa49d7142ceecde57c050076ac9225f9f360893dea7f09d8b1c59497cb9737d9736ef826aa07fbb4a0e	1637222444000000	1637827244000000	1700899244000000	1795507244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd891d50a18d6dd73865d69329acb6d16f692a885c0d74844da3a50ee98f42b05d96a92d8e91957cff78547271b1fed67719247654331b73ab9164f0b2a022b0	\\x00800003c91adab213c256592f8f4d8ac3b8cb0f252bb46b10c9d4273c0ed597b88c64d5d1de64653a5d876bbff63c61bd75b787027151f2be8a11e4d33e64335b9bc8dc6a2b89c1d48045648f3436423b3f43e6d15f2657c0a6662935044803ba0eebd6adfb8a2f4df541430c35356f472a3180b88a7d046da1b8883545878a3df8c64f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x17c8560fcebf7a03e33db17e1da5736e3e07c7ac01812692f0423af5ac837a7edc57f38fde29af37aa7e2a76ffc0cd762117f5cfc22e52a83bc349cda7cca209	1622109944000000	1622714744000000	1685786744000000	1780394744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdf51456fc90d43dcfca6c83cc28b9d54f0309ed8cc706e8583b6c471bc3851a821adaa577c3538caae355c6af09ee132eeffb85b7f2f54be6f99867f5625c184	\\x00800003c1b185c10575993b188673e478836b07e31dc89207ffc9852c0453a69a6dcd2a31573502e075110979eb6798a7bfebb9eb38210e1ae029d138ed3be3dbb6e4b681b2077b52405cbacc61157c650a319bb34d9f4ce5e15d34440744f630e8c0238673b09a6295941b3f84d6c4635df3fd1bdeb31c1632301673032e36be2aa9e5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5d6b6742969a000bfc401d36bf2b066d0efc8be8e20bb7acf2a845e01db1036f1aa31b1480a97f4415b1ff8e220162bb36abf06c89d69c3577b1cf2859c2fe09	1611228944000000	1611833744000000	1674905744000000	1769513744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe0512590ddd32becf4326e4c7c13b291ca9edc428125ef9af101fb5f4b2c40136d2acb453621600d0ebe75f5029ae9fd7fce46f47ae512dbee4e5eedbb902102	\\x00800003af89f251c679aaf6ceca0d4a465e286d2926adb5b83cc0365cde7dac3606573c58ed819bceda34a8c5bb89f7f27140b38dde1674891c68266be9cf70046a0f92d6be4a21bd7b8c6d50de09a544e9143955e9153e184a699f2ac2de67e666073582a6b76f4286d2d16d8e93a105c60835feb5a6c23821e4dd5759d3f602262b37010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x510cb4be278258b7bead85ac298d5df5dbe18216ae174b701c35f4ff4a082d9e5bec4d6f3de8aa03efeb527a2e810154255f41e91a8ba0aabe26022bbe07530d	1616064944000000	1616669744000000	1679741744000000	1774349744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe0119e140f2d16991c360488723a8eed5cb7617b10c9ed4a72ca6c741707e7c3ab6215d70ef9e37bd388c7d806950a887482dd3d20dbad36f8a3855b484e9545	\\x00800003c8f030efab23a961608527af6d81cbb5751b6d045d209ea7488e8b60da7cd6b0963dbcccf55388d5923e632f3c66ed4e1f21efc14f58b39146d6179936c81ba027127b685d521249afab30d9aa3fa690e466871bbb8c337516d6b7467d990967bc20dbf22a041574c7d384d78c3aed52f31bad6244a3801c0a5c91851adb3a27010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x072bdf9510ffc952fae12982b4904df8795619a9b82a12151a2f3b3dd5d9c0a1e051719123231cfc63e179ca91ced41e572bd4fcdd1398cc7affb54da2c82f03	1618482944000000	1619087744000000	1682159744000000	1776767744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe6e95152f77e35ae43fefa03f75c01d41435311a3bf7caf1551355215ddc89f1996704f89705aac6902770a8bb9f0df51b49dccb749b2801bedd4f7326640c88	\\x00800003b2f1c7c338dc5b56487214427bed00528805ef7bdb044c023bc9d95eb30df4bcdf6581b15c93efc91cb8d4cb9ac04294acb07afa13bcb7072024e59d9c3290786c057fd685ade90b9d3052170ffe7c85179784c767f9d82d51beb0456b426f2eb700a0d0e8e3b5744c78d26aa268e637a3ed35354782a77c7149f8d0ea254e1d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x71c780d7b256f5e9c55943548a6b5a7111c7fff29f55d7b06b229688d61c58896231ecd6d07fd0e9cca42188b34fd08836f12ca7d187565e09d6bc046c317b01	1628759444000000	1629364244000000	1692436244000000	1787044244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe629014ab9b1147b59c1b15331a2849c00cff863ec2a2c0512ddcb6eadbddd9744a9aa769d1fca005185d5b66c8597a0a61caea149ef744f483e54fb0b0bda47	\\x00800003bec781d39ee11f5abc26426fa389457f1064b0a804e5ee1aa8c9762f99816a2647e6a44a4ff97a4af9e907ec2d80799b728286cac872e8a01fcab3ca5b4d8f5b1ecf73604c12d4b23cf1ece0bb1dadee6415b601ae8dae1c8d4bec110b2bb14a8d665d28ee975ea281e70f8307089ba5e5dec2c6b97d766232afafaf4fa64861010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x22c879dd2c83c3989638d3688c8b44c38d5d4d56665903d64e0368b73f1906804c706aa59a779177bf98603427affbe13ef6c7896f381f2f270e31ac46ded905	1639035944000000	1639640744000000	1702712744000000	1797320744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef4942a7764dc08fde950af298f284abdb58c6312dd9ddf8d8b579ddc883cfdbb7ee4bdb7362cb51546ad81ae6112c2a84ea5c092026638958521bd0b0b04619	\\x00800003b9227298f99ff7dd640e3577ac704e53ef283b4d26bcbef4cd28578dc094af776c2f37620fb5f1f86a69a2f016d40210d23055f2394f5ca21d107e1e97cb6c1ce50e0a2b1e5115ffc4a1e2731b7c5fed33d4593184024fe27f48c85b157694ab59e2c0f434c8c1fea4bde8ac8411f3d4038f7678f07bf3d663e56527523eda27010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x19a043d39ae4206b3f96d34fdce755c9d58447675cff8c38804175226d55fdfe8fb65e33963afe12e59e7db962397bc28d1c5b672b009d3471e08682cf6db400	1632990944000000	1633595744000000	1696667744000000	1791275744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2550af57c5a62f515407d12368d59c09fd2e6f469637d55c76d8c0203ccf1adf22fd976cc0922f74470dfaac0e7bd694d2660cef65948bf2f16285176379401	\\x00800003c282e10085e42360fe2199e08029a67940ae7d1a90956204b7d00762fc97c5df4cbeaa648868407b729ff16255674c9aad95c75d3df48f3041495020c74d31e20f4359e321749e9bf692aba30f1c6799718db8ae50fc7257d524867ad63f1295713756ac0df80fe882ea4f3ba1dddf8788aeeaafd9d85a612df7d7a6184b444d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x828b0c470081be844f4dcf59864fa774149fea00ca69c12933854e01f8f32702c77dd3275c2fd909e9765e540f32dc4dd6eabe58f6e8f416aec849bcea9e6408	1639035944000000	1639640744000000	1702712744000000	1797320744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2957256b152d738e386832e7cfaaf76988a43d763a80071e3b158600ac386ae5de65ea1c1cf186896bf254a1da0c24065bbab3ade4e9c3170ed54f2b0e38d32	\\x00800003de8108ad29b116c2aef24d6045a8d1c55b4d14c85eb018588280efc487597a18c777c9d4623ca04b23d4bee393e2f7845bddc7750489261f2b625770c5c81c6caa02d3933d6fe76a5dd803c076a02e9e0fc78813c4e5c40a4b851f914be38908d254b6aee6de1c48355c2b3b4c539689c25d17e1008da376f2d5a2bc9b352367010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x86bdfe47231fae6721496932e0ca2afd735fa17ad9c89923f7799f93fc696bae4516a216da2478b848d38b8ba83e220ad1a3b6b6e83ae137a047751d5847f105	1614251444000000	1614856244000000	1677928244000000	1772536244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf31d83b233f85f4250ad862959ad26cf7a8b044a0a441763fe2610b1f29900e50dc019f73afab6fdb9a1a73bcc4ea122102f0f2d8e32e752838fdfd5938bb761	\\x00800003d23045b245e0e7c8812f5c8f68f65d9eb371fd304073bc7e6e1996c61074c94b3cec31e38203431e53860ea6ef717c3d7443e2443862cce827156014913294778d6aefe1b66b2b8b9825c1bb993e1e67cb6938e9d0079f0a1e65bd135014c853213bc2c82dc141514297f50b66b55bd148db282bca3bf736630e5464763fff0f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x32c49dd8a65deede007e77ca436463825dcdc94c6f846fbcddca0d4588ea6d31133b64a50bd6264ee3f5dcf09ba48e820830a9ef5cdcdcc8b742aae330c5840d	1620296444000000	1620901244000000	1683973244000000	1778581244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf4a5b2b9a56817f982f57b73a5f85eac99836bcec6f125078b4f52db74e1a425c2c8b8552ff0ee49b28e448a8518820bc139a141402083c37954772c9f54b2f4	\\x00800003a9608bf7f5a6ce618b772c442424481836590b13aef79f766ef24b3a8a18d8670d1bb89ab65d8f73391a6e6976ee174e3e57e14a772c838ca93a42cac1e8b4424935debcb0292a13314e55f6c01cabd3a53bda325599c1bd0b0694d594698e6594c58af078c17c0f4f9f4269b05513e763efa399b762a57459ab0e98d9e01de3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x54bc3ced691456b367a414f24994a41abae21e3938fa8e98b12a34419c161b6609da83619d3592384fc2694ef1b8ddb8c2bbc6077e4724525c41db715cffe705	1635408944000000	1636013744000000	1699085744000000	1793693744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf52d6df81b5e5877595a92bdb369386af99f1b05c90ff1c780bfecfe6a6a48e4b13d3285c692e4a9135679e95f65f85bdf32e7015fd75b85b2c0cbc28dada95d	\\x00800003b244dc96643e4c59a7b0e73a05d7d42933a64c3f370d3036939f2c2183fcbb42e91d2aca9fe3ced60425be45e4dfe8211105f616c9da4a36ce6b67fda7bd800768764483d424c6d95e5d93b56d18c617d279d36b0f27f7507f8067cfe1919c1279156053540a58e3179b5153f2aef2f40aaeeae17e4b086747b92302a13fb455010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4d93074ae76a768c1236703dea29bf363dbe9594ee2987cbcbded2a997c552be65df2fe2fcef4396ec2d2add410d703ed3ed8b9ac92341f361b846121a36500c	1637826944000000	1638431744000000	1701503744000000	1796111744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6b576bad4c2cfbf4a50fc1bf838ae8e56a80c2ff2304df47e3ec1c72eff45a8419d26f6428d9bbed68bda4c2b3a8729e6d0ef9781f32433e9c18b1202b9d639	\\x00800003cb44313c42966eef894c7405fad353bdd6d69cdf3119287c7ce999fa9e4f1f9656c5e8b1df5f1b6200cf629dfa68b676ef0b131ba904ff986b6f293e510bd0c15af4aa8cedcc48c31707a356f6bc0a8cc08e30ddaba943a0867b087ccba46b67c278fa0f1f33e07927290692da582e2fa58d41a857bacdc623003164fd6afd1b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x44a4ca878d0def59fc96205720b5e186e4d22236573882e7599c9c6fba58abce744c7e968c7b3b7e7fdaa7a8cc3dd2b32489d41fe0957357fa97ea12a7f84907	1623923444000000	1624528244000000	1687600244000000	1782208244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8d92e5bd33466bcacc0a6115c8fc933f634a6ece50dbabbac99382f49fa72e6f2e3f3baa2d478b82c7eb8d646b12f56671200fb857f3fc8b9cb98025abfab74	\\x00800003c3104f03fc367823bd1bf15b2e27a8647d8ea304ae2eb58233fe21bdca44b429adc988901cf178129ab7ff55d756b025036c0290570df00c45b051a7c7aa0a33bce740970877af3c0a3bc89f36b8cbef8a24f2034a8fe57a5a0b126a5483c2bc95ec6a1e4c0d2ffe69ff25184d00810bb7c4a5267c03f56059672a7fadc1c42d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xff886ba0f56d84ff5445889bfbc6d67b191d569c797d7d795a19ee1a59ea86b9082a5d967779d33290f1cd547ba3a94c2a46e3713e66cd3e9c5315bc7190dd07	1613042444000000	1613647244000000	1676719244000000	1771327244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfbd934e10f7ea935ad4866cedad19dd32ec10149bf6e36948c7af59c5a10b8091719de656a744d8a4d313de5a2e872cfbfa49a3bf759799ca642c563723d2f26	\\x00800003b88ea010f57923b52b6a14205e982921723c58077bb0107bb370608c42558f75063e765519dd05f4c76911330843f7b69f546f20d5d995a18ad0a5d1f39240815e91c0f4f0c1a30fccca5e6579d8249502d1fe273d1e42cd45cb4b6f153fc419aaf683ff48bd1e31c8819f4942aff0d126b1e680d55cd161d7679814b3b50a95010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc24844085a8e71e57c95fb4ca658def50b3587bd0e30e382158275657d3e8694ec484c0fd7f335e0bb0b4004d239ac864d0975f2ea76bf51cb17bf81ab3fee0f	1621505444000000	1622110244000000	1685182244000000	1779790244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfdf9e0d6d3cddf30dd632b4a1ee59027f0eca851b048c4d356be1d2b2e3a268f751e658fc212b0262bbeba25dfb42ca075f0da9a403ca88e8bf91c4f8cd53e42	\\x00800003be0e0c50a46375550bde763f52e36e3d857ab7f89b555c0a77976a8f2cf75233044fc20f374311b570abd9565fd9502a4c513a87246fbfbf13086f0cad5b0f1293dd6fdf03f54c7aa70670b183f3ab3a939714a7540c290fe40455edc68039427ba62604e8f3c4b44fa335cdb78b7962c8ccc2dccfa9ff21b3ad977b111558ed010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa956c1f821280aaf5ca745bcfd21d3214c5f01e01bc9f23b41b1f9a27dde5a7d0f50ee32c2ffe473743ea733930ff9e5e4e8bce872fd75349a83d443c1c8180c	1629363944000000	1629968744000000	1693040744000000	1787648744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfd892f72e80305e4ba6d168395e8cb1affecaef2cdc7d9a8ba64229e674e8538a2bfee09ef1dd18a8ee1b7de0f1711d2f830cb486396e0eac5a7935feb73ec6a	\\x00800003a5072fe6acb7ccd0aeeee5ec5a1031a87a7b341fa9264769b470f372a5bdc8aa961a42a63fe9478c67bc130014868783c5285baefab561283b687bbb8bf72bc015542fe947443d03a4ef396a65dac131afb778e203bf3484d8c7cf7947d85c6684a80da0afc892effb39f61647240494b94ac7fb675374375e7bf4fe7f45a755010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6e845af3f880265b57740d3c7f5a4feab76415957fa87256c35c24da2d8aed5cc0f6334c4033287cde01f11c52d54ec8ebab4b492a0ad45f9b902a55cbbb0809	1613646944000000	1614251744000000	1677323744000000	1771931744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04be73eed7ad2a7e1d5ddf5d5da8b9c77b8f79c75b5350e5ba31ef379deb72aa43adaf946a6e4d20f579bfbdcc51bd649171e11f7b474f6626c407f1b44a4840	\\x00800003bd01aad3e20642198dd04228e28b557be5614a9488d0e2c6cf23994e3c4dc15588c1d1a9f55321cfcca21b83dfdf96967f7b8e48f0bb016a9f1ddca59d2d742814ef25ab8ea41cecba1ef67fbbcbda3dafd99f7a19cfe808ac191980017da647e5d19161a6b9d5d183500870a3b3ed9c6e903cdab1b499cbe5140e411a09467f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf4a2d58ae52252fb638339162f474055baa06677026c7b1ddf6b952a1dd4157bcfbff8b9049453b8833911bcc83b135001942b6f04ce6147beddbfcb42f9da05	1626945944000000	1627550744000000	1690622744000000	1785230744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x077619358f647cb90b492f25cc6d1fe4c1d9d7ee2b840c697e09e1507e52e93eac33f0ee871d039934a4a55f3ec37ca711840aea8d7e0dab9c7fd82ac35b6433	\\x00800003c0d7544684f753723f844c2406038327538345fceefc71af068a7a23a887f6f8ad1d1d1376b31c783d826b2bfeb8e5405e592df9c6d90e2edcf1b88e9431909f3d43f4e83e0d4ad0e1e7e9f6838089c5c96c3fa9ab82e98724623430019079fb04ac3944248ad5e6ec46e9bfff5f98d7b1556fb245d53902718408f00bc4d0b7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x52ae4a150270bffb875037458ae6f79e42a171afaf07d9ad3eaaaa8da4f8a9d0bdc0ab613177a5c9d3d921486e32e2f703de3f7374345f52a2983819c510e202	1617878444000000	1618483244000000	1681555244000000	1776163244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ab648489b2c857bea4e9b696644a3c2a09deff78e9c1461ef6b2c911feaf29a8b32a956bc9b2731a4365e44c0e2687c06279a405931cd857c67de7539ce96ee	\\x00800003a1fd7e5f02e7933d5cbe366b21c9228decc964b064ebae34717ee8134dca6191eb271ea00dc1d5a090938cdd3f247d7ea80a30de28cb2b376b327f70fb9db4c9db8cbe0b1c468020ed8ddc9159825285d78f61b5a05c2ab10aebacdabc4489bb077dd8097b4b73c313acaf6f4b167d95442110eea8b755e4d4e23ed81a71ff89010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x33c9df07c28977101c95e288ed7c0efd072a60f93fc04a5053e0a369b002c03b44144cddb3a383cdc9cd3cb66b33bfc5cee17c3d68277a867ee63a843ddd8701	1608206444000000	1608811244000000	1671883244000000	1766491244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a963d2adc54c69d9b3f6a91a6c3287bc0688d57216b1a5603c8bddcecf4e04e114141551271928ffd0f4f4b16f01bc72b5437e93a12ea37f94abdeb27cd4eba	\\x00800003d3e5eadee5204a849ec0815d636850f56d3f32041afea6c675b42c2016362ef47a90df4559384bca72661a5c3d22ea84c9d6e706469ca7a985241144432905a6e12d6250fb15ef2f94c47b9b91091fee5dad53e296ea1a9a3d4781bbdc296d7075fbe39bdcf85b5c269c509f0325df44abd57dbac4441ddb85f96cddf2832c53010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x531e083d159023c2b7faea2d9b79ffabdb8780918f79d4ef13a4d982a653689fc092a440d891302f19ccb163758bf10e95f5bfaa79bd744c50c166f20b0d7102	1631177444000000	1631782244000000	1694854244000000	1789462244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e4acce3f7308adde5af867f533726e66e77b6da55d818c4c71ab16ae979d4de23e3f43f3c38eb8cc273840122bc697530ad42290f94ae954aec8235379ee510	\\x00800003a04b6f4304ae692cf62cf187343a560138106d023808e994d382b091ace847a7c6b085c4fa7c749b9d535d7ee47e61cf69b255e33b9e05577da2a87eefb555196c04ab16b63b381bb175f5d3739906138b914243c384031d9a89f9152ef9272569c63a366dfa5c528684236afadf85d8fdd0aad40a4e1b03f5a1510237b66a53010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x174c80ba27d125f3f9239f6482d1284415d26007108e8e3f89bbfcacf19cb14cd4445209d11e0f211697fc69d0a20649d329843949ca72f4a2919d7b5185a50b	1626945944000000	1627550744000000	1690622744000000	1785230744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1042f0dad3c7660cae237463c5a330ff37a87f38cbb056f9740d2c8ac9db689c9841843b32f3156bef3ab6ae2f7b4fadd396dac2dc7a761f59aaf00907b3f9b5	\\x00800003aeac3728c6bf0491020110c841a538b909e979f130d1f3d18345ad23694fe3919c69a0a9f7dfef1e01c6fa9c10ef87a8f24b47eecfe3638cd26a83b827640743d683c69d98aa079c74d2ace78225b1cdd41ff04b837bdbcdd5c934e0adcc78205474b183341f368000e03768ce636597c5520f014f141daaffe3b1e95af3ab89010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9bacdf32c397055da51ccf3aacd431aa4a2dba986a1149f8c51b731ca317109f89c80517fd2e24d08e6c5887e7c7cd2caae1a93d5156f04eafad37e4192ebf0a	1622109944000000	1622714744000000	1685786744000000	1780394744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12aec27a704454595fb8853e5056b1f105dea50473a53919871217b28c26643b5737ddc3f716b14492f20a76badc40c92bb05375042f89e8c500a4f7b49a2c85	\\x00800003ca272e6edf603188ad32dcca582cd1b83a3f1965ebfa55dfa9ee05e9b6bd4f70819769d60dee8734866129c646f31312137b108e3e3ca50ef7da851dfa762cef7fa19919d759fc26757f0c342a63ab175d836d40a0c122eab9bda626990d89c039e1b8f20394fb58bba1437edf51b331220886db423cc71f2bfc83e10abc9fc9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb995c37a2c55abdd6e1d61901f52d2d9027659afebb7354922d636f474e4d1b224157f1de3ae9a60a7536855f0ace767fc719c7ceb1aae3b2774e06c9b0b9906	1613042444000000	1613647244000000	1676719244000000	1771327244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x133ec2970017d3f009d0664de94bfd93188076c4a9cd09b2b65069a221c31fc5ae890daab29e52b7fcc154a6c57ee5285d7e2ebd057ead381995f4ad7728235a	\\x00800003a990c84631528b70b05fa342c618abbe173d62630a32ee436ea3d308d6a41122d0219e1b49b34cebac19161a8415b6906b3519ef0ec5b728b74c5a3d858b98a130144c4ceefb15675f7e034ffcd86d4950f990267ed12285c67d478d4a0a1f14fc9499b76d248a19a31c3791bda787233a17eaa16d507ddf06b618515c4fde4d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x22ce2e606be70924a4fe48d2562dab0a470be851b807e149673a477feb0999a20eb78e30a37a51eed8a0562911c0bc53ed0bd7d144ca147fc59117ca2a3d8906	1628154944000000	1628759744000000	1691831744000000	1786439744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x151a8a3033c70213375d92d400fb90251efb45d3a70bfdae24e914226ab7fa8e041d9d69aa9adb06fd7a00e0b3057198f43387ad1a2be1ad9a4d3f63e7d68ee6	\\x008000039a4462a80539b22278f40f0ae5b9cbe278b39dc2028a1ac8d2e64cf3e7285d58039301ee92751d6297fbce2fc16324313b93108f446b319d5f91cd82415d02c5f6c84c6888aa3623a6ea3024b45fad65333d582a0f25303ac06205d05360c1e4289617ea113bc916303b980cbeb4767758a9d99ea4a0ed6ec11d372820c95175010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x76656c390b9e72b2803b89f5f6b2a9ce183d14c43ffb409bd2c2cc89a95ebef667a75e4dc58e884d9adc9a885bd7438abfcd5848e13df99ca969c5ddb143bc05	1634804444000000	1635409244000000	1698481244000000	1793089244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1766ebc6e47bba2db19fe0c0a13a42970d3667f137c5abb83df864da4be7dc880c02f488a729a039a2aa41e82cb5338adfdd539235b11866e89dc2a6cd557b54	\\x00800003b7a123d8997b4bad73c6f305670d05228e2630683576f95a8e4173df7a899af9efa8b65770f9e6b33f82d64052a7403773c6b27b12c696c86bc00fc1e0727aedbaefbad4a83beeadfed1b23c4a59426d28c57d3b7968e979639e5b74c5e1a7bace6a88bd7c30642aca56a39ddf9ece4ac65848fe385efbc4cef02f23e2c74f77010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfcda1e93e782c848d44f65a9a6dca945d9dd7d6e0c36fd388875ff9e26335622185595e31ac8b8285dc669cca7abd5400dfd3aba45a07ce52ab4d0f75df0b70b	1610624444000000	1611229244000000	1674301244000000	1768909244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x177ac26e0df04c9c69f9d472ccdfd75fb4d1be83b453e99ecc54048405d337c01ed9d29d8cbc2857bc3f04ab86ac66094de82ec6130546368f853cf906637ef7	\\x00800003daf132b4493d57efd0d3946fca95e564313f85af56d09bdfedbb7f1a83e73aa52aa33ae6070be93b6f4e3c382afa6b9f23ec945519a76493c8b6d8c811829766d733090c228a00bae483b1181a2e9a5b53df0f25042862d74e8d66ecb06510fcfbc9fddcc83378ec5bfceac31038fa0e8ff4e7a07ac1c865307bffd65351e967010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0e5ec0dece26cdb51044bfb956fd3f73c9eac5e087fd7ebbef7fae8407ace87efd42e26e945929b7aa838f837c4030bd0e9078092b8666f385188cd478998603	1635408944000000	1636013744000000	1699085744000000	1793693744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1d069b9e27d64597b1ec52e9ac73e8e61d1564f168f19a7db0cc8b2561e08239939c2eae3c82aef431518074878923d87d80b0e87165b4e5b5b8261c88ffde68	\\x00800003c4b478b048e15417e31861f9bf21c7b2c47a48d0ec4d149260cbbe791a14f92d5a68abc2710d177daa185f199e3899e1ce00274b346369e3fc7196f25019979c49149f2980234aab7221f10efa98e8b4b5d7a4c5a35dd9188e3f6752a32e3bc3f932e140be55f0283459ed3606a00cab01860c45a07c085bee51e12928535627010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x71649163e7b9b1e6a397cd8e498e56c7e3781468bf0b2d4f627ccd1a79358a54236bb3db6366b434191c0869100108862d210875bbb6c1ab80b83e4de91e8002	1619691944000000	1620296744000000	1683368744000000	1777976744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1eb664f1fdf25bc2b68c4df4f1e7c73c3cab31d1cc06eff9a3baa756aa6e27675ce51a72546d01d70b0a261230f40fdd0c1d67664651185ed8d22c1ff56f23a1	\\x00800003a1b3cc48fb172ff4d98892a25bfe6e98a7a96d1f624bef7b7aaa0d0526991a2ebf7f9818ef22e55af262e059c1c2fefae09de541845880fbd9335a1cfcff741101980c52a6725176295dc1b7d325bee4551149b2fdcdc8cbac981d384a072f8464581003021a0b85ba8af8978a50ea05864070b6470165aec46a614779ed9bf9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x10c05f3d20082f72bb8c576e03fd9b67f25a5c3e2212056beda32944ce24981de7fc554e68d5c98bd0b6a3685584aced25b44affbeb3a6c46b50d9054c8d7404	1609415444000000	1610020244000000	1673092244000000	1767700244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1ff2cbab58d2619bd38863c47686c2334f10270a34bcc3268c8d7e76bda77bae7ed113c98fe2ada2c0f019f36e804eb43a701f1d2041afa7cb967e582c766604	\\x00800003abc9a1a302499fc2313da9a74e747112461e0bad4a47e062a1e8e7b0e689da30ed08f93fb773a266611d8925e1009471ebb28bb4f7d047bd0161b513d5eef4e7fe449579a2c236fb8e57bea1ca605cbba4f5b6b04814298f55684496b6200034957a34fbeae241b2c90561a2d367e128034117a42c91c0e47af7412435f8f587010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4314510f50cc5c7e736e7dc897a1f11bd8ef1a84e6483dc6d0d77874d3a95a013b199436b6c4a4c9be5c2ec41e839f0242611af026c00d3c16edc1f41d2c7707	1626341444000000	1626946244000000	1690018244000000	1784626244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x21e2a3b2b04aea72f6502de2338dc481612b388b2f4e2c265f549d8cf5c68da7d6c824bc546ac3c8dd001761e0091940f48c1097c32ea6bbfc273fda110d74c4	\\x00800003bc762970991c4ba63ce2cb0cc1e39685173cb6de7536973ee51fe011cad5bb0616289a235f7cafdb69967af17e730c240cab863f25db8849e1ed643852ffca89afc93c9f529c026c28bfaa0e7f3ac8dcbde501d2992eebbf95de1fdb5dc701713a9213e7557837d5705f6527fb0949600632b6c02952168f3d7faefa5ff327cb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb5044dc526d35d3f5b40a343f56af035652dc655a00603fe8f2904d00819cb03c206d58cd3d5d94932d1322d5de3e637b7bdf12d0abe7f8140372a1a75eb0909	1628759444000000	1629364244000000	1692436244000000	1787044244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x226a60d5aabb1d0bbcbf8ed473ccde749e39e47cf2b62a433680400375898babcfe960dbd3917c84ed12b4745c4152f3d9dba144ba18ac36d30c2ede8273dda8	\\x00800003c4b62706ccb20b03c77a3654c9066b0c2696086d90ce2dccbb280724fed95f84526dbca5a4d15284f4e63dfed18e5b515510abfc912cacafdbadc07ed51d6d4342bc9acdf57a65de2efafd4d9d284f7bbbae5af54bf953bb1fe602d99962ef359d16afc43d7ccecc14ad8913d9b6531f0ae542783481c3593780a1e50deafbbf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x277182258c7da528a9c8929028dd1ff068dce48cd14b713fd1e24c53e0295ed9d4c92b83077cc9d9aaa6f7c41732a0c0e79eefac7b4e8bf2a432a0920e27c900	1616669444000000	1617274244000000	1680346244000000	1774954244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x284a043c3c3bd0a8718e643ee059d6db9d20d8eb1927d6ef9c5119c1d09759f43adefdc20f7d19ee141966c4482bf7abcd16fe3dac620e4299556dd05c627fa6	\\x00800003b75cfad7a508d638cec730c80b3f14d9291122f9c02e69f7b1395b5caa1c26747ed069d70f02036fc445c4328c23aeb40bf7fca75f0b3fdf690ee05b770861fec84ea777146d5af3a123a505a59ebe11f8503ae01cbdc84b6f6fe3e858de612776557e3d817f93ae38bc2c7838a09ce0b2f635d825b281fbc7638dcf6dc7902b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf841bc4f8ab0aee4687e06de1a9b854633df9c84e4687eef20de54a904314cf57c9e37c19034679bc42c281f6fd237272f7e9430db44af010098b1dcec634307	1624527944000000	1625132744000000	1688204744000000	1782812744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2a26be06813bb284d9915f06daaf12da5c8c8637c48f769e944b29f9b9d316b36172bfd0a30282ec4d8d7a24ad7c731046461035ed63ef719c6c7359f4dcffe8	\\x00800003dabcdf7a69ee6d28fdef9730c7a66da63faab257872748bf9a44e21f48ad32df8f0b91672f80302b0fe2735af60f6c8c61644de2b4b01cdebfb07f6bcbd3dc862346ebcee1873efedbb3a87dab4b0bdccd2ed982042899fb84aedf886c2f65456be45cb327c15a4d183812b8e0e6695369dc996c79dc229e067cc77c1c6c18cb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x51f76341891da6974e78b2b6a8a5591e02dedff784c74b5e246f58b02d920416f386737e5e2253b11af364fdba262c03522ffa02a802eec7ecb8a767040ae80b	1614855944000000	1615460744000000	1678532744000000	1773140744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2b0e566f4133ee7a01c617474fce4733a1732a46126c955083154fd6a274f6b86c894f29d7dcba81ea6c351e1ac837ede9e8d4af7f5360b4c4997838a06e73a0	\\x00800003d4c385cfe9d5cd529d7edeb3b87ec6734ffa8631d4e3b39af820aa701ff9dfd0238d44f47ef891091e594ae832a84d9d22f07833b176e9449e4d60c3276457ebabad8cda206fa719e037389fc7e9f48e71ea471e4a07f4b93b4b10c01eb7d5e0e1aa949561825a6ec59b3de9470d9b64e5e57abf964a1e2cf33fb3f2bdc2ae49010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3efc46ac270896ecbfdb4395604cd336ac8a0ed5b0b800fc08cf36d00417a13632990cc75c1cfb4fe0448ae00a9e52f909b55e294656610fae50ffc4addc6900	1638431444000000	1639036244000000	1702108244000000	1796716244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x30fa8718a9f69766e173f739ba2a8f77a12b60690d7bde1e8b8ef05757c697ed3cd332d917baa4e0e08239479c75a9f408d94b9ec5bd9accc9fc76be3c9fd19b	\\x00800003db64eebdef2c07b108940c303c5ab32a5f72fd8c5e1853df9ac6245158b535da39f96773c13d2acab7a456e6a97ce0b150e3ee87438fcc3737a6bf9041541e6f99cdc3c32bc8c504d67840f696bee415bb4aba316cabda27de7d4ef3eed3a1d08374fa4fcbd5b660cd6d2c885cfbf401efae695f7879fcf721f69c0693242947010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x795c7846a56893c03803625329df42b5c51af8c74f2b3f5ea4291e380c7cfafb37fb674c37a377704fbb64bf118382eca309c47574b5bb9987a2ca8301f8a503	1613042444000000	1613647244000000	1676719244000000	1771327244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x33e60e842aa6e718f612a4b97f75e4c57c6ea14f1e181c25157b6f9cab527c277706ad89cbfa1ec28f613efdd264a2b5f20c61798d732574eac2621fa89abe86	\\x00800003caded5f89b35ab183df75686829f98ce24e07324d3022a06149c1ef572f3c8b2d9847c0df0b01db948359ed428506ae373831668478ed8d2009afcb1aad28065d15febe9596b8f198208f15b5cbef88df77b8b155389a95f0212db2074393db20f27e0918f1f5d7f578dffa155d431409ef9d50556d176488e0a4e9a71f5bf71010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x808279bd074abb25011c3725d73e7aa5a1e26d7748352f05aa85298f67c7e65e809c86a3cbbfd4481313deb378495cbd31df2de5f62e6fb7861fade94784410f	1611228944000000	1611833744000000	1674905744000000	1769513744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x330a0b557505a7f7e0da8fdbc1544130ac322854a2481b7bee8d49030c1cddd5b3d81fd824b398cab4f3349f6f7a2bdbf476d227c69112d7947a834e45a3ba28	\\x00800003a9a651221e5480565b7cfeaf6daa1920ee83ef4a67d8a62eed2c099a36ef65ed490c8ae9e0c88e09c8222e6bcce582f275400803e97b077fc0e3793cf36844c30836824eeed37603dcbff32fd9f89d3b8e5db80cecd58f3b2e6a520989088fd5ece86441e316149a3e5690e4e1113f955da90ad4509151fee40e7af1df49510b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x431f58ba0b5a592cf545e3f56b3f4a1d502dd9bbc6ebf547a639ca3267db2b47e9b3bfe031c085744243ab25c1ac84294b29f757be49945d582635abab836b09	1617273944000000	1617878744000000	1680950744000000	1775558744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3436204831c07954612317731dc967c07e2429a4779dd39cf00513297d0b40f3ff4fd3c8e2e0254a8da37f2b194066d607ac9a702c24bcaed5b92b73407f23c5	\\x00800003c46ccf56c272035c760c3aee90e5a596dd442d7ce51e3646eb331c9b12af132ebece477e52684c50e8c64bad6fbb4e583919640213221282bdee653aedfd3cf187e1fc0d970e3c82cb8544f99ae205b7530df377b9fa7b15b80a3bcd785aaa1efb622b9d24a4e0f7230c2d18e8425e5ad0be8b6d0a5aedccd5a1a366e257005d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x05aa0c35b75801002da80792a8411df08fe18ecb3b43bbcb9645069ad6c1ab4b62598733a886bb407db74de5e654feb09ca3d95797136a8ba4cf022551469f00	1623923444000000	1624528244000000	1687600244000000	1782208244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3506ad1dbe982cb7fab3c9faeef93f29b53aa59d83e2626240d8ccdb327e98fc7e93043286fbb07158a66c11743d63c901f31420c36ddafb5cc61323feef2d50	\\x00800003bd69600e5f4b79f0383f3ed1df62871be319d7ea66a9c6c44586fc2817a524422c997978ce2456245176d20cf8d2858d0a18929f71c91c4c500f5fe14097200732f06650f036daa8ffd78d769adbc3d1bf1eaeeb44c2683c9145a69ac8e177b75b2653bb71b6fad45ad76a98a16d7a9cbeb6ef1ea5b5f8a8d96f95a1e7e98c69010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x154591acc48c12df5838c7868752252d0b576c417e2fc9cc41ba90208112e0cfc5c54d8e18a0bdf81cfd8354671bd5057ad58a9562392d9cacea0999a816ea0b	1622714444000000	1623319244000000	1686391244000000	1780999244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x373ebac8291f223bd2586063311cee6f5f88156e75d4d74cfaed1d11cca2a955ad04705328e3f560328e435c61e221324726b6257a51107f93a3ac818776fcfa	\\x00800003dbbe6dfee66c516823bfb1b558257b91229c4b5e5e8c462860642c9344938b8473bcfd8c3f7d725ec54871708df97ee3af7ba68c53bf5518bb395707a56067718ee302cdc16cad6e10ab4293bc560ec350d9f330f4d76eec3322be3f70b3c395a99dfe00ea16122accaf8cc97b6ca5ab0136398727740ca456dcaeb7d59310e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1257b513466a7173bf4b821f7e8dcc067fe4534249978e25311f8d97440ae4210608d9155fff1815ef3ae2e0c386018e513986cf1ebf282d738cde0015c5f401	1618482944000000	1619087744000000	1682159744000000	1776767744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3a32301c3a1f2976ebbdd3856ae784750d8efcddf19e14422f0ad1c9993e93e09dc18e2341b0a6a6af93a282353846d9292ca4e47c8626c1dfe507b1f75acda2	\\x00800003d72fb037adc765cf1f2ffda6c529fa967777b5df8bc78a99bba957f8932ecdfa65d08f3e881b192790f3bd3e5c652ac9949544f33064160f15db944147a7b1970d00c694f0cceb46bdd9d4ed3e9ae8efbd80c7b48eb10409a470017990e5bfd8e75b3141811fe673f94b8340648818f12ee6dc1ff49622f101a7ccadccfcdab1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x88ef4e576cbf9e5dc7e28c17484d39037c66d0c3df7d1a67c1b9ead926d74ec02ddaadec482ff05ae1a67888dd3ec6f945fc9ccbbcaf1bc2eefb5f5857184802	1628154944000000	1628759744000000	1691831744000000	1786439744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a528ab9ae2369c82abfb29948bff8b0918ec9f3a3e5b17bba1761d5684edcc75115634ca4cce905b6823817dbcb397acd8ddfdcf5eae566b567a76dbbed6ff4	\\x00800003cae2f8802dc3315b66adcf5e51877f3b7d199f8eb5bc458601b79a0e4b01159dff562fd60a929c56291de03c6cc2c05b5c7f612867bd8725346971d3e082b515721124516eea10c7450295903fa19ccd3c4f5625a1f0615a80647dd51184f0c52a4fea9b2b3e67f3396fc0c209ce30237eba62c5871e85e89aef349ad7b12367010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5750275fe697944224e3b17efe438c05af65f931b4039d806d2f5731b153044f4fa7201f7f8b880b041261701a69c5ab401ddfa23221514c056bc0a45a66160a	1631781944000000	1632386744000000	1695458744000000	1790066744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3e92c79291bd5d8a2379e41bb408dcd7b1c2f5b99603e3c5acfacb183529f502c8228637634d17150b04eb2f1c93aed4de47f1e28675143a0e136c453a98f843	\\x00800003aa80cfcb7115fc06d9dea91f49ab1fcf09539f602a8e55892e9f7731a7fb36ea3757a43984ae550a4accd1d278bb7d98afd6cd64ff31631a1be4bb394feda9080b6115091c467df6d075180898d60fde7b2ea575a4a99e775f457418c840a5ae4edf1e7166e3b6f8122509edc4ead52545246186bb6a039d168b94dda41636c9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7aaa16ced845d4203cc133566e40cbcf1f035e65e003cc2dcbad80c023479aceee2075453753f3443ed4bc5b9b7e41c9e130a18c5002eead8557d993c17e4706	1615460444000000	1616065244000000	1679137244000000	1773745244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x44de2be9da1cde1bfe37df4059a4377d169b5caac20f0f55ec3c2ec091caf44e28c0d32969d4c0891af30060752e94f69db3e637e16c69e11ab41e2cae8dfda3	\\x00800003b2a1678cfc954d81d2b5c56078cceb6f5f95a8f7f128a9a83781b3e9522cc59f0345b8e11ab47ad5a554f98f7ee95cb56efdb741cfe0aa0141ba83241fa26e8896d776f222de629436a35fbb8dc7e3e7b628e1337fa1260e7dac456393574c5ce3b49141378dd6c65ca76884eaa64d60c369f5c65670f3d805f7b9795bff88f1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb4d78a918e8b104eb52dbd2ab61054b891113628b122d829ed19c6906866ac56320f815497c8891344e7d2db7d0aa245a4b27b0961d76e195447693b03287d03	1614855944000000	1615460744000000	1678532744000000	1773140744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x492af80d706492758daa2c8d6e53eebfdc13dfb89e5973030281fd8114f3123bf312ae77ad94e19ad0a5f9807568d4182e9e90bafeca7e709ab215fd2bff2797	\\x00800003aa490f325c6c0d08d9d87f990463006a18318d8177105ed5817b0108ae39e0370d94c5f142271ff95187ed8da724a6ce49ac71de22e9c278b95f108a8e170bfebb4bcf7cfe6a861461a1db5a072e99599f35b21c96724de728a253c6e77ade485654915ecab9f04540825a4241867d3e2532df4e4644cfcecde93e37bd666669010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf69b7e6a5275ab00e341d7237f497e915fcd591cc590570c79228d2d39380ae354cd80ed897c965f447108a8883a3df3f52838791af9c45f87eb19b26e29a905	1627550444000000	1628155244000000	1691227244000000	1785835244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4dfefadd6e227d9dbc6c5d3b0f3b86514519136944f3afd409d031c4193adffcf454e0a64c90c3f277f35d068d7370dcf69104052da77d36cb364c5104b1bc0f	\\x00800003bcb6f554acef0439b3ac246584307791fa44380de5c4340708aecbad3eb1e2afc78e0a0cf7d6bec18baab51919e7ee49ca03e9e8c91f8f7d2722ba81895c4a5368fd046298b9ffa7c533c6f4cf4e8de0e4fe8c63147610cf9c9ef1c9d4cea0c7f33e82046ca820cec3baaadd3922cb05f8cbf1b4cda2abf0e6efa0ae63a247b5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd20cd63677187f6770f56a6ae520e390949a4f2a19d23b692c1018c14b20a484337a005ae80643ea411372044efe828890261fded021a3c94f7ea8057792fe01	1625132444000000	1625737244000000	1688809244000000	1783417244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x50da01812dd84668ec840d45b7d84424c656abc7c584a3d859a7d2d505ca1273fc3f674c5b20aac32be5c307e45093fb023d9a20e21064c5c68dfe3151f65db0	\\x00800003c7e6f11809dd5ee775a9d4d6d4be3b578b824e09e243f21c20af53e82265a0ff8969e6fadb181f3a1f359b8113aaa442b15fd5e8281ec620bf9518054ff57a4e24130867a7bdebd82a1840c47938ccae470cd20a3f309ffe851214143c1811eab063c008ac51dd809d41bc7421ad2cafa4c84430136aec65a14af563007bccdf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xed1515616e178a4c9d94c59d70503904ac3f2ed46709dc56b72ece7385d4897c2648db95fcd7fa219e55797339bb3431edfa8193a52883f653706bcc107f4006	1627550444000000	1628155244000000	1691227244000000	1785835244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5032784b53f9c70fb27f470e15241e578b705153630f28b2c91e477d05315bd2e3dd2379e46b2073144615799faf45b4984b7393823064fdb5857fc44d442de1	\\x00800003d15948c968261279a217aea4a8c1bb80670d8b8196e365995f963794700d41400cf941eb806764cbceb40e67d4fc3fc697f5aff8eca3eae4e91e007b6e3423f0670273f380580ed84b2c71253ee7da6df56e2d10f8ca4ad6fe33068b848f19542737b2eb48577c0b7694ce489546697ad2cc448507ce7489389c7418ebb1f461010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3fe69ff86b5dc759d8aade42e6fbb94313e79ce9c15a78d78f8e7582715d494232f16cead2516c0e9ffea167f283e61bbf08d4d8bea1928cb4f162fe171b4700	1618482944000000	1619087744000000	1682159744000000	1776767744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x589e086a41f38989775ca1f48c29be2d769d04b9b5a26c1692b8666fcfc1ac67868ba19fc264a10faf5665f3429dcb8846628063bda05d3ed590d8e06323e532	\\x0080000396ad21cd8f77c268524b2cc8aa46056b15d7bb12906fb6f156b5029d6d496890ff34a5744782bf5d9f350bf8b7d1c5674cf0529c86639d173b83bfd317af7ef67f29050a23d9af5afcfd63cf044b00c21fae644e38a85dbb2928d15e644c19d46924c9839c6b34e22ef7783d37d074ac659e7f08a21c47e278c38ebbc257bad7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xeca386451ada2b56e2b4d41811014e63932257323fad669ebd549223650baf7a9613d1a8447e47fd8fa2c6f7c0b4a8754f687e560d71ff148dd5d24e7ffbf30e	1622109944000000	1622714744000000	1685786744000000	1780394744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x592ee87cdbda4da4a700cf15d6dfd7f975492bc859e50fde7615b0dc3e3936f58121543d838f9af13f8bae86295b46724530c0d22f14c1d5e77a54a5b65efb94	\\x00800003b0f8c3ccff901b4d7b2e9ba76efd55e0d55fc5f7cba9df091be32c8a1a7f5efc939d6e7295f53e7121396255b2e943bc89f4b5a479d95ec4189a7f5f6f03b6e25b817df9b72b7b53c96c9e324b90ba7b6e5e6a1e0cb87d067007db48bedf2b2d6b955887836be2e7c18229b3e833de3fbe49b97412c6fff43b0bcde8fb145d7f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc1760d1433131f5b79abda35a330316032d41225faf964f6e2097e06f3ff57d2f13750c3b2def77a22b40d493a5412015a752adf60ab29597c74dbf0de29e004	1614855944000000	1615460744000000	1678532744000000	1773140744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5a7e889b0827806d1cb0f9fcb24298c37ce38e4ac2149ad9e398e7738fc1b8fe691d8f9fe8bc51d6500cbf02805472368b6921c166b0c47d647dbdb4971982d5	\\x00800003c177e05af1a919f293e4e911d3ad6fcd49a007853fcfb8a4516f708a75b9af38fae3def22b82d4460560ae0acc7a2aa0157cfefa95cfec8b5d8045a0983027fcf2f8046f40ca5a704aa68d30c24891f176cf31e19c29598f803cee32c86fdbc79320fbcdcb4c239219ce3a8cd6efc7194c2d2643b13f8732be11452f07aea4c1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x952c99d9a79ea5a3496a282fd3680f00a896acd3db3d11c0da9c6e530a213556a91381015916924c946e1697154d822d4a02516999afbc756a7f2f3a05a79d01	1632386444000000	1632991244000000	1696063244000000	1790671244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5c9e33e61422a1bf4d6e19f2f947ac4f96f335d2a05ad917a3c59cc71eadb318395017f9ae1a41d9b27deb35dafe3e4c2815b7ee99d037ad2d28157a461c706d	\\x00800003dc9844137ac5807cf189958ceb9e6890bedd5b7f8d8bd94434fc98534eff7f5f6dd729bf8aed82bb83f730bea558b6ce28ecaa271af7f6129febfeb9af24607ad20f665f5593f61a609f8ff9469496cf796558e269e886f445991d6820c16125c8740eab0953fa63597c4d349fd1312c4832e267e1701b8e41283fff5a468ad3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2c76b081d18c3483781bf1060091ef31c52daf79983223bbb9b847c21db25738ba0c676864fa28249fdf415b2ef0298f8228f8fc240819736691d1bc6029ce05	1620900944000000	1621505744000000	1684577744000000	1779185744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65222be67afb8487881b2ebed9c0a5450db1b12f2b265febb2b267c341a21476a8364e022c7376935bf9a2312acb34383511175794fb13b541cd1b6bcbf757a9	\\x00800003c0a8265fb9553a5545ad6f81589def802de5a965ca245fc9dcd2150331623b11ea3cde83556f7c1b3268bcd9fcb41540fbc515bc29d5575c500e5f32e7b88c6ab2853970795301d5180cf754521ce5b38e36ce6741cc78a9561b73642dfc8455bb9e5f766cc25a880fe1d69c5e8898c270378e5bdce006f6e495117a636a055f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2d4ca4326f3e7f6263f74996adbf7ea705abb73b58bf3e4937232ef3fb54aac86c253573d2366c7b032ffdb7d11bb41cdb40b71a6c7bf1deec6d464b03237b08	1618482944000000	1619087744000000	1682159744000000	1776767744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6aa24dfc86e8f65628138cffdab72cd5ed27a7ac583720ea9829dcd4c8009c524b515df4f958664654a655c4c86075dc82d9ab26d5ae9d56f4479f158936143b	\\x00800003c40774b22dc1ef42293387344f7f9c0ef6bc3db4760b95eafd0d93db9390192245357da4653ad72238a3079fb953b636d7dd1398eb51ba22544af745275488b4127b9debe47c20f9922e5f37a534142a1e28a10508b72763e62800dd8524f2dc7fd732b1c0b6cda88eda714ef0bc9ed4a4f8f3a2a963f1339ec959e5bb81d89b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9fcc2da2f538441260acb7d69a3d98eb0c6c7c46ad56f3eeedce6c4c9c70ce5f0410f8a76c5952564339f56e9f27b83722d3188520a4949239a94ba7feee5e00	1617878444000000	1618483244000000	1681555244000000	1776163244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x706a190099a422494666284f05713fe5f3f717d433f2c9aae5e46b617df68df82719727a7c48e7dccb690bea54bfc62c8600ed2441ecaf78a215b654fa390f6e	\\x00800003ba29c024635554c5aab2067b60673d5a7af89ea86642dcddb6786b3a76d4439f7f12b903fd147a1ec242b8e670a3b968fe51bf5050b88e5b0248613387a093bdc42f41c70f7e13b740df456c8888b6c5fcdc3f7b8014e0731cf776ad29236c99406e6f44b19f408ba980952c6249db0dced2858c9cbf8d2be10c54b2ca2fbc37010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x04b87be9daf84de54c3fd0060659605d5682c2322d22a37dfb62766b59cc11af7fec47e7f72658846cc152d5df78a0a73dad1288662a6134b006ede8db58a808	1617273944000000	1617878744000000	1680950744000000	1775558744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x70deee7ad5219848b726546edfeb323f41cc83dbc12512eb3da1a0e0ca14c1211ee1a3e46f89a287bb28d6b34375d08a2a269001db2ae2d9bed25c90b92e60ac	\\x00800003f11cc55aa163974620b613d9150a902e97ad07cece2249c6d8b318870c73359760b67a0d3aa77c42a559163ddf190013919c7a2df69dd15abd6d063616aedf1d38b408f7e7ebc62e84193c0e3b4fd9856a9dade97071568a8e63d94c7b184b4473fc04286504d845c2c18187e8ebde71bdf506b312d39d58288a2b37f182c34f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x73899ebb6f7e3b6265177551d31e6130009f78aceb466a2dab937fb27184a336241ac2f3f643007f60c75fa9fb46e31dec30e50111433867875c1f747871f801	1622109944000000	1622714744000000	1685786744000000	1780394744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x72aa6b8f737b86fc68a4055b57e13b8ed07748555f1569c9d29c2094d50cabb9bb01e1207b1e0ffcfa9dae93e6da639854cee89f53f0de215538c8a0d9196fa5	\\x00800003adcd07164d3a789b48f2e3c81b587205b5c1876611cbd7278cc26143be8e9a69743772a3068f1a0ba36c5c6fa92bbd5c74ac6b13305d12754feb8eb402fd6ebf7c4d7a7f13224dc5d9d0693532e360adaa693a677d1258622310223c609265d2c95967903ef7f79896f2f010ba97f99a9f22165830750df1a19225c2bf0df56f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfb197ca580d0599e396cb780b546738b51841357bdcb09bd3a6f1a03663511a2bf006295746ed9757eba987b38a12a000c67026ef40b8d30a8cc4ba51a3bc508	1608206444000000	1608811244000000	1671883244000000	1766491244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x77a66d948b95d70eb0e18c88298ad9a9eb38d6678f1c8ee41a259c754e7ae27fd4cb4206fd3260ee055e6c2d89e43c0ec5b878f2195062f98ab1e20100c53e88	\\x00800003bfa44e1080a93d416d09b5b088d6110af48e52f766f832092e97892b1aa51fe4e613ccb4bcc16498ff63eef960a3eaac8822440cd5467c4ede6d31fe121d7450c8e2a0abf35ce5add88df3127fa5a1a7a4386ab31cc5d21483978c7734839fae6ba0698aa6e51a1e66389c77c1e196e597b3e4320a517f050730dd10abfc7255010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xde2b13cd6288e2689aa48dd0aa1446087d4b0f42cd57378367345ed8aacaf8f6194de2be62d756cd5c25acef20b3504f79169b32d17c2af9f8a07c21d633cd01	1626945944000000	1627550744000000	1690622744000000	1785230744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e524ae6fb8f477bcea3675267d40379c304e04d345d0d2780bb0fbdb9fa64d55406a00826febd29cc7d57e588367698493f8d93339a866274099475b6c5e034	\\x00800003dbb7ef64deac1df9a5ff25067b2fae6941fe816197608ba574a8ef0c6aa32456bcf443a04aa844da10c5db4255979564053545100eae99e57deb840809d29ec1f25724584346147d3d2f5007bc975a6c5ec16a792f70963c48edb98bcc70fd160de2f923cafc3918eb4101d2adc9a212cdb17bd30a360581f6344d8badc0b9f7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2d85bc9e846014dac8bee32f6698216bdee8bae473e9ba0dbeda8456ab2d0c109f9cf257c73c4ee9b25197aed25375c11ee5af2e0c3cef8eed26731f7ceac20a	1635408944000000	1636013744000000	1699085744000000	1793693744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x874e665800845b467dd5905f4c74cecb8470301aaeb7e4f7b79dabfcf7959af2ff9a4327b97dec44e71c7d226cea433f266bcc8dd1c685bbea4659b271ebf628	\\x00800003b704d3bf10b2f91a19b8e12540c3abcb43abd51032e384b7d9e42b0af6e90314a7412e9ebdd625403d34f3bede382714c3dd4f5179f50bd72c11e2e50c35c472a3df7adf458f40b7cb94696584804cb42e2485f5cfdb970611cbfb80cccdf3a8261d5dbe2f1015b810e0533fefe7bc744c81c0d9e53660bbb95f3b06d8801d57010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe1b03b05c2256141860b0aa3492ae86042302b60fbb1b9171b4a62957470ef0ada65cc5ff90fcdfefcfdc8c55e315e09351c89df6a5a16975be45b2d1c3a1009	1622714444000000	1623319244000000	1686391244000000	1780999244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x883e95c2c31fa24edbeb82c2d518b06eb688a4c18f3550bc879ec00330a6df46e1d430d1b51140f549a953f119c171fae84c9518bf2fd4517d65613832c5c7d0	\\x00800003c340faf7c763c2bf2516c88e79956dc09a4bb81eb072a0a43c740a55e323176f6b4c10b8eebcc1665d52f59dfda6bea6e3ae4bbe55e17b3626cfd36239d9cf14ae3832297af8d6ed0d0e16d5c6f85c91b48fb155e2109b1b734596bb1d45ebce9c074e6c9acab6d988b103bfa24e18e161142e52113a8dcb312708a1a61322bb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5f33604cc9eca31a18da17fbd752825e0a0f8fcf23900f0bc155fd6641d7a8048a6e9fc866d6c309b2ea96121ca366e5a750ecc7feeec5a96ef2391327bb6c06	1610624444000000	1611229244000000	1674301244000000	1768909244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x89f20bc1e4c2183be61fbbca988e8dd24c956984725ea900a4e1cea168f0379eeabd510d1bae66e17f7cf0897def272b2389f4f5797a2e011a63ca6edaa8b745	\\x00800003bded7ba202762d6c59286013587aa89cf3e8653fcd7a4d208e5374e9c22101f3ba41367a868b635323ffc44dbdc18cfcfba046b8d98f8aa55732caafbdab639b93f6b376180fd1812687e4b7731416949f27f36712d4e252970947ff16fd6f0d79f29cda47dd546735289016f5347abdb36448cfd0b1fbd7d4e987315510ec5b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf5e35ab1130ea2d0a0979e44812a463f227ca519f0f2ae742da6b2f997caa2767f18ebb2600d717182073fa5b31ed70b965190270045513dd7893aaec9c41e0d	1615460444000000	1616065244000000	1679137244000000	1773745244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ce275f19057e5ec16005836d5a509470df3f6fff7e77b808f89f6c2c7fd84d783959382391282c2e846369638da5c0a9c7b2e75915ace89ebf36bf4c82f904e	\\x00800003bba663f2669e95091150e7643ff3ff2ae667b2f6fb5c03cd05453a58bd01a15642cce5c958a0edd5693c8487577d24b1333e7dce8788612a5bf200ec94bfa93eb1509331dd6b1d830e66005cd4f4c5d64460fb9f6cdcab5693031ff24fe581e306858c60618470f276dbd066bc6a9bb0d9d546cc2f46b707264228323cfa95a9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4244dadec610db098cde85aff4a500907248d4a3697d5969bcc8cd34753f8bb382fed16b7096331df8ffb593451b4149d676dc1a844829807dced3142f0c5601	1628759444000000	1629364244000000	1692436244000000	1787044244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c5a2f261ec3fbccb11a94a562844d1bf551ba95dbdf5bf36f89815aa158cf173f6eae0cc245f3f25cf8d5e182342b3899349d19d601cabf519afbc262603729	\\x00800003d8a6fb3f3019ecce2bba128a0e5739d75cac5977bed739201c30c8f9c77c1d535132d02bf3421aaedfcc9e583d64943109f82d525bc1f8847e372246f49a624cc822f47b06e913eaa95ec9b9b70c4705c5b1a8a297037c211bdaf64ead32f2ee678f063daa43e649eb49e3a0a1f69eeebc177e7aa63dbc54b5ac005e767ad3e9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc8377ba19ccc2374989cf701d03e5696a29bc7858b2436df5c96ace7ebe2c13eb3780d8eece21555bed9e768f7e44e0ec02dd0fb1ad2c1a11a35c29f78b6200a	1626945944000000	1627550744000000	1690622744000000	1785230744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9acaf96031fdaeb0827ffd57502a349654bf597698f11bf348ce995c6ee5650db413f88fc6cd099b163b33136999b7d62c1abe144e0255caee3dd6dd857c0528	\\x00800003ac6da51124276d51fb0c9089e6008b00c1a3d1517fda1f115fde7109bcf8879c015c74b2d249030228bf997351a00d3f99081a2584b064db0336eb3893319203a6d065167a3a174d9b23075aed9f6a386c33fa29f58cfc0e6b69939e51516cf78237e30b26fc85cdba70fc9d7482ab12b00c2b6d16e788138f7f9323867266ff010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6c6e73ffe3d39b8449ff15769956c9d49763eb9a8db87a6ee2fe5ba5ea513a1843cb3e57091b36ae46a23aec792e50521795fc49b802316dbfb088638dccc408	1611833444000000	1612438244000000	1675510244000000	1770118244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9b5276985bcb1fbfe08f1d0988b8e7d72b7c802f21e0aff33dd64ede52d54fae744ed9d2836b3292ff7498f6e880d1fb92cef5a5627c9e732a678cd94e4fee11	\\x00800003c9a92777248fb9279174bf60648dabf23005b2623bb155e4d1e1454c862569bef55ccbf2131f4d4012775e15ef866e10be0c237b59cab72df75477c6c4f7ec235319f45093ec112c105149e0e718fd862ceaaa4566c937e3c6d83ee6b274b9d5c8928d7075b467e64266e1dc5ccee8c905e6ce680cb0bc7607d6980d0785894f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7c7968183a32cec821d0509a4810b560b0893eeefb1de74aeb4d6fa9760b5884ec4a610b143c417f8f6cbfe827629ef3f322760f7c61b57dd6be27fc15c83606	1630572944000000	1631177744000000	1694249744000000	1788857744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d6edff68dd6d8e94ebd1079248e1914017499a4b7257b88f682c11635bc9337f57b5fe14c8aa3e8431150bd637f7ac433f78bbdc8c33eb3d2c9f5de0c667cbd	\\x00800003cb92138e8ef9770b120c361c51e4e7a71561816fe41da4ebc7a87fcdd65b7cafe38d8817310b316c2af6a57a9181f9c92d15edea0599063a7d1bd881da87476818c4ee7490dd8055ac6196e101968e904ceea377e580d76883d8c2fcb3bbda92d2ff13d272c2352ff80b76caeb4cedcaab6ec717e3dbade838713871556558fd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdc6d7735a5e9352f85f52acb65eb721b6e3dcfd4865350ad8f4c6ea970afc1a27b2ea7b5a951c052ed51025884b75feaa288ee68aa5d8b14248bb5dbf0f0b700	1614251444000000	1614856244000000	1677928244000000	1772536244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9ec6d9a23a536e2e9ac15a8c99e85fa9d64578ee946c2c28975d8cde1e62d54cd9dc651d5972e6978efc1c8a56ce398ab96b220ad2951e26f9bf3ae41bdda600	\\x00800003bf9a4400a12a04e7997bd927a0cfa72c8f9ef870cad1408a190320768dea96efad178db784ac2fd19575d24ac95cee9bb81265bfb91ac56deeea595817ff9d8ab5bc77cd28ee1cdc8ea201007a2c27f320c0eae277f2967838a2753f90baf4e3eabafa63ec07d29abe2d45b25a0e4822f830881e3399a58b8a4c3ed444896e49010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0249061e54fee4a810a9eaa48eddc685a68cdbdd0ef22ecc167367b1ea16b95411abe1956b312898465bc4377284dab7e199143a96cc0073d4444b46ef0e3c0c	1611833444000000	1612438244000000	1675510244000000	1770118244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9e465fdacb212f78dc01c185928376250fe33bd7a3fb542a50485f1f5a13b32706e01ed9608f5c4ce9e272d08db81b8aab7f1614c0277c1a3e10d08b12f8b352	\\x00800003b3340e89ff51e3cfbcecb0648a17d8de7b87fe165d96d474c8a1fbbe8be70c5561c99477b0619c6673f2857e12cd373b75524247af4d8d2ca476c3e13e966666ee3c3d034f2f6e5239facd200f7bb195743c6f2c9baf751d47ffdff8056450ccc398e6f2ba0143151fea9a4a677b365b4c8a0e839f7f6f7478d51949da59b57f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdeffc2a037ae8952f2132b9fde9a834da3f798ce48c20aef241b0a32cd8396552b36f795dc9d71f69598130d9dd07231f217006aaa86f012d7736646dd547106	1631781944000000	1632386744000000	1695458744000000	1790066744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa11ae99bfbbcb42e2c712e2df9a47032a829e2f564ef60466bc7d5b79dc603ea43a03409f3c00204b86b44df7ebe16304f57198b422e3212249b5b1d47a50fc9	\\x00800003a561c846f4eff5d680c470e051d9c9aa166acae73905a63d6e2f70fe663cc942b8cdda6b4de8feba2fbfaeda507435b231fae6a11b559934f58d8e4099c161c2b10b40b59147b1e3ab9b17f9104dff85d33f36ba17c7f1899f3414b603f0c1a6d9adc1c2eba2a0de63f04e0a589b76d5c0b221b74c1da4b002e0be2deb410357010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe728e49fc7e46a1e6639365f7c0f14309aa0203cfce1bedc7923dcd52b920e5e0f870499c0e9d9b5638f64465ea4a6f81e308e328efd4b15076bd3f563d21d0d	1624527944000000	1625132744000000	1688204744000000	1782812744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa5de955611011a4c2c0c1df838a8199093e8bdeb5b6792366a571d50a60545ae44561816b88e29b37c7debe59ea92db71acbdaffaecda9ab90cd59c910ca6120	\\x00800003b7db8a1c53f0782f2b9d6be3a3b7e218ea7471737e11fb0a397b16bdd1e2cf65b1a34cd60ac4e1db187ea9c464fdefb856f09a571bf93987574972112da181b1e2b49a7a3be5266b77fe5c2c6f4f5c45597ccf8502f0b02f85aebc4a7c15c807e0d22b009c2823798dacf438619c26a44728653c79cb09c07ebf8025e813805b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa8a417ff75733f83f2462445e253c899c9a0faded3b0ef99115a2e7a563f65eb25b7b049e0dc8dddc20508ffdbf0506c596cad1b3e4957a5cde6f5378945bb09	1611228944000000	1611833744000000	1674905744000000	1769513744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa58e2cb5112541b81be694d3d3636beec72a5d0ccc339a28ba6bbac52ccc6ca8f8d75575406bd472ef2d0d17353b70c2a789c55952bdf56c45826f362844c40a	\\x00800003b444e343bda054b6ba50a29609549c022bb41012daef67e07183fa9e8ecfa7ccb698da21bc88df215dac1b9b859f948f9373d53c8ef80bc99fe99957649d28848f8d3d94188bc62081b21937a8d79d7780710709cc8a7c227bdf5a3ad64a4b9a4ec314ed8e9fd3637344d6b642268dcba9c11a61a3ca8707b05db46ed4c980a1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2628adacf099b22e1b2ec24f3c5f96b1b19e78d0e04ae3893f2591d4540de6758771a389034318892898c2fe643e8c67404edb133e2ecf6563fa2898c3b0ad0f	1628759444000000	1629364244000000	1692436244000000	1787044244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa792188bdc6a71aa629844920770760df421d6d9eaa4973c1b11473754a398225c1794f265eae25e4c5195598a9bdc381b043d35030e453e7298b56cbdf90202	\\x00800003a4052ebbcf18f0f0e049e7cb9e7320f60137972200679a5db08672dc0f315e70745059964aaf43ab084a0ab1beb03dfc2177eb5917f37afaa7b686e7355a7b6a6467e81e728aa00cdc36fa13f4007a0bf3dab8685784ac69da9cc183a7f473a3aa027efc32352641c02baffcf3a8c45fe5c5f950b25c7bee4732853813466bcd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9d71e105beba328bc622e7fdefa136f968678a0034b8f29d2bf9c2072ce71dbc4db3fd35f5c0f1d4e9adf58a1e79c2565d304f156d423405c4ad88064b32c70b	1625736944000000	1626341744000000	1689413744000000	1784021744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa6632167bf505b7739291c6386bdf1cda9f81d3a9cd1c37226bb43c8111f7b4ee786d84b22b179a319ee5b6274349fd2af73c95e330b43f3494723fb63aa4e4	\\x00800003f87788d6691f0f296e295386e114b96c979df972e23e692ff64928f6637362c12c8833d123b51dc98a79bd1e08df533a7cfe734d7defbb524587a4e6fb3e8ab5df2bc97e86c07ce769721ea17dadbf7dbe15d2ab8f01ae2a2ac83cd88d9b852153e60b16b8af38a5c6616731e8ca577b9e6fde38d2aa9ce2eb8b858f03cce13d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb5a38f4832a1b3396441fdb40e07a8e4d99d2524cd53f3ab58ab46b2ee899f0979d92e48ee129e19528d618fc97c923aaffddfe64b6011aaf03db72f4b623f07	1610019944000000	1610624744000000	1673696744000000	1768304744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab06bc50fde41f31d2febabfefdcdadc6c7d526d85b13b29a47fb9b444dc56efb2e87b16c00679015ddabcd2d7c24d09bcfbd02da28844d11847f51cf9d1b271	\\x00800003e957df5d94942ebb320806c009f3a42d352a4fa1ddeae4ad16f5e40b1332a8ec0d29db1eaf37d6a039b7721df31e86ac130e976bdcb335bd6914c94e88d59bd8cada8876407f4fc64615c80404e9ca8cdbd734f55e7cb0b9302034a220ddddd5a17e691a9d7e20dbcbe9a2bb82acf815fd212df4f88ebf4d3e6eb49c03938d0f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x732a10c7969da3d1d02bffba4db79eb6a0444c73e6537bdc92d48e7b5068f176c209908ab3b56b1be9997f9121294d091b6588299e6473d180fe68d8bf6a8d0f	1618482944000000	1619087744000000	1682159744000000	1776767744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaed68f4fcafabf81adc061b91f4013b2d064670e3a1536139945f91c1d081888d26663103a68e9fb46252609a26dc6f9cbcd72d98639363240ec46ce6bf8cfcc	\\x00800003c95cdbf3bb767d4fe39fde78cf4a42081ea458bfbefcdca27da69223ce54bfae9b4d164d18d60685672abeadfe0de381e36b6d26c1177eeb525adfb0f553863efb563b45f67fb4bfb87c411efc242358a9142c5793930b9470c6cb3def042d5c89cde09b4936f0b0e6ef4b760f43a0aa59516e13b90bdd100501e08ce15a63b3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd683756ad756f667defd7ce2dc59efcd3aac99f72a821ffbd0a1de588a3686692ee199dd7ed3ea0333441c134ae5e152822ddf46a3ec74b9a5e139f82cd04e0d	1623318944000000	1623923744000000	1686995744000000	1781603744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaf52eeadf91ee8258a08aa57028af7e4f6584de23d3abd2d353d4a877b723453e7be2581b169a955d10215cbd90a08c4b48cdfdd24b348c2d789fc4d8b5ca46e	\\x00800003b9612fffe2d4a66fd7914ea31725aa22548736f72a6167027e21931e689d66b813c458a8a3f5bd357e1abf1623fa5559ae127065f6b48c1bf9afcbb337e7001a6a2c9eff075f958455602f360ac5c21f3da5ac9964b2defdbc892a5dc2205df92efbfe4700de6bb6590a76adf1348f4d7b54aa436b9719013f3324b3cf64eacb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc5c039ff8adb66e24ab4753c623f7ec41a180ddce0074bcffc58fcbf9c75b5a7023e561fed786c4ccd1b4009de784bf13ba4252b6d59b7f34c962ef127954c0b	1617273944000000	1617878744000000	1680950744000000	1775558744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb18e1c8569f423d840a80cd7ef63e07875c30fa67ab59c701c1186991859c3de5162eaade533a478937fd11c2dcb96949c6fb28319e6c5b8388232851b29f2c9	\\x00800003a9ce0cde99f396304c24b528b8caa2b48b4bb4f66d1c07c30f3fedee84329d6fc678408db60bf43593b9aa43675bcd6d2e6187e9f378ca5e048ae3187d41fe008a77219fe228dd14caf4b6984182c28502df109aa49a8149c47f019db007802f45f16f7a848c6ea7d53eec1cfc1a6fd2fdf10d95e2f2f1344e122a9a2394b247010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0375293f3e35cd322d16ebe95cc6b4472887c650780163c8d6170d17071f0187ef5da2d6e56313e9399104a0235e9ae2f1c6047a2564520a176b5d3ea308130c	1638431444000000	1639036244000000	1702108244000000	1796716244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb32630dd389cf5fbc5453cd42ae596bb0f17cfc3041dcf015b719693e6f1b7226ccf517d470efcc2f36b0ef5a0e74ab0f30b224f9dc413e9751dd2edce37580b	\\x00800003b7e3ca34f7f3c2d816543ffcd8c3f976d5fb16f09f63422d0ffc7c4dc5367aeceb104cfc06f55716c7cefe7736fe66d19b8413616ca218e4ec818dce31f037bc2d170bc6adcdd6d51b399cad1855a5a65a362a488471b538c93b511469b9499e579b2ed351bbcb5e2539d4afba260a323155c9861d965aa8d40e1d725d6e26b5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5289268a684c82456aea39e7673fe560eb6a962d28fda31d2752e1af59fb34dd7a32e78bbaaa8cda09dbaa104b6c810e991e34cbc064fed124260629ab89a201	1616669444000000	1617274244000000	1680346244000000	1774954244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4fa47a190003293cf202f106a2212f4a081064533b8e77506c39135e203ba20b7e3851ed6f06b8990d5c95ed4374e3d927d5e3066fc5115d0fca745ee733ed9	\\x00800003cd537adfea436a9f11dfb9c497fed8bea7db87e6af468d802bacdfcb4c558057867d85311996287826750644ca5a3c53e9c901a77a7946cf5853b8d38677b1c1812b85b086a07c0e1d2ca51a36be6f12a0b7328d3df3714e169458d0b866315afb2cc28404e97da998a26fd3fce4ea56867a21c1035ae3e37421240c7ab71979010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x42b51eadec11d9ec6ecabb8f9868c021cf22b6c2990b793e8e3420fac2dc566ecbd5825d986c357c74cf58394eaf6911fec87bc6d2f62a5530d125c37316e108	1623923444000000	1624528244000000	1687600244000000	1782208244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb4aafab63e306d93d27ac0d015d3899a73661e05d5e502fe68a52a4ff9ab831c3ce18a098c6b03bebfbd6174153eb9ad013e7ff751e6881698ab0f377ba800b4	\\x008000039f4dea02c8c091facc81fd390160d6fff400110b59b593f895abcf9d15a57308441d3d57c18a36211b65cf309eda5d3a3b9e518f9223967afd0365e9b570e55125ffa9581d6fbcafb51bea35959aed4aac6658f97aec689e7d25de6e82fa9824bf5717e6dbe41bef859c69316eb76da0d26fb83ad6005a1c62136919e8cfbc6d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5de1a494c5c6541de7fcad6dc683805dcef236f47e2f9a1f7f7aeb3ce4909e24a4bcdd756c633a7e9f8e75d158b0eb4124bea0fcfdb328fe4f8270e6d57eb801	1623923444000000	1624528244000000	1687600244000000	1782208244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb5f24da5136ef58ba0720f509ee4f71eae593ad0d11ba245eda31537715844fa194cceda68bdc9b6197ca93acc0c6e52c895a27ac92ee5dbb325e913caae3e86	\\x00800003d8b05c2728db85d1fc82c5f8c64a7a054ebe219130e2637f76c5e2413a7a1b01e07c3021e021a24fb02f892cfdc36c141ce9c223e1aab927a0ff109b7f52bf1819000b6800f1dc77a9eb7375d599e1e9cd2400890bce1a24b7dba7c81282b9996c649844c8ae50d86a775f9fce1334b9eb94680dc725676cd46274cd2a23d225010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xeac53b8a72a5ff20f994c1f8d208cc907f43c656f86982d8ff73fb02afac97ceb69eecc29a8b61e4f3f3ce6b4de8c2f9803a3b0d826fc81fe12cba9b3140a401	1613042444000000	1613647244000000	1676719244000000	1771327244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5ca8951a0a6f919400665fefe0857c7a8a97c2ed7f20d9b015b8fe9c4227915af6c65bb1796aab8e9645b5d168dbe87ef45714d5816628cfb3a414a952d7aae	\\x00800003a90541a1136ff2edea547c95ec5962f3222fa15e5ab52fc2005fb024c2730d540afb3724bb5ec78f9884804875ca139870e83b0db38c89c59eb82eebe4cb55dd579eeb425b5375ca5f4eb099fda181fb33648acd2f60b794c7c74d5acb8ee9b8821f4bf7235a14832c82ed55730fcb09f8c2e5a9f03e126f90a71332a3b7854d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x45e2ffe0f552d91a02e8cfacfa4b8dff6a11f26928a4c740801f922388f405031d7021bfd2bdf16fb322fe232197f8fd6e142a50fe04957851c0a67c9a675503	1628154944000000	1628759744000000	1691831744000000	1786439744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbb9289a933525c6935d7d6957b7b31762ac374f3c68bf0e1c01eb8aa9eea65f8994c368e20b4e862f8f9c3751958a806ef4cd0f46d6fd26e2b6a817267eb403e	\\x00800003c0d09e63299595e98de415a7d38f984de9a32fa5c4065c818791c59071e9be7ee1cd6cfade6eae5754f5676da7688c78f1850f83317e785d7c8a2c194efa383b7b9f6e00dcc1dab0173778384318da65a190d55d253654db591495eae85b660cb051878d5cf4ee06f817de240e8dd0992a6b3a277b0f8aad9487eec3673a4279010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x246f3ac4341e8161fa016cc19c94809f0b222f09a08a7d44316643cbf62ea12f1c0494d4e8cf39f8118a2220287318dd6b88211634a286b578fb6428b5890901	1622109944000000	1622714744000000	1685786744000000	1780394744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbf02a3aa0365e6936030582ccc7273e8088364524bff1c2fddd92010427177191a403b4bfd6b53b9a8f30c1c14d717621fa396081cf903f475ecf125a48927f6	\\x00800003dd1d64decf37ff82b56a9101f8a085b3cb466aa5bcb8eb13c3859ab6d9775e35d69cb7541476c29094d9535c59e759b558d21e9f72dfce3ace98fd9421134d0f3724fe69c1282e8e18ce1e8980da333def9b03e6f996ac03152716ac4238bc358264b2e3ad4b951b46d8e974f53bfdd4a263d578e647ab75dd5b03ea72cd9691010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x404780b8ea5a044598e1c6130b38b3aa84ed8d7760a41fb2c528c0824af991c1f220fc1567f829fe37e6402d016803a9f95654df8d93c9a2578488676077df0e	1610624444000000	1611229244000000	1674301244000000	1768909244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbffe141236afae3ba7ffb6acd8be591ca254ce843e6f6197b76b4c982255a0c671dc463bae38d53c52b21aa69cf263891885482f9071f7be36488a5a201e2e4c	\\x00800003b5d9812240cb6808fb46b58b76d50138f304128152e32458bd81f057335bfb98e1c093748a1cdadfe951f9d9e4df61fbe0bbd2ab0dfee3d40f1eb1cf6529211fffec201c01027d4252390f67038a2a6bb91468d0536b9f65c13a3f723dcb4a4ae13bf53a306996d68e60b719205b2be06686d45e6a2120e6edcfe484b196f7ab010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x23ac4bec650c294f0f21d94c4c017d7d5dc2cf118b5a1467c8dcd6f9d003217cef1f7675eb0a016896de356cf7ac130cd77a6716b7dc24f5c4b4d7e739699e07	1614251444000000	1614856244000000	1677928244000000	1772536244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc452236fe5acd1a751ee1f9eaafd53ea31d67f0a60369ca83f8206c5456a66241d8022472f1e1e9c5222a9b00a86887c7f01a62c7eaada34603a3a99d1b980c6	\\x00800003cf872e67ed23bdbcc9bbcbf7bc0696506a1573a32bdcd6175ba4e311eab1b10abc51e3f9f730f023c4b6d998833dbf781b93c701700d98b03fdd61ac95cde1267c4f9992d661471323e59c5ca0622f1af49d0ae52837baaf03f9f412cc5325beae014d41829eba3edd40ae73256fc4fb4f06568cef3a6154815fa24ec99e58a9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf7dfe222767b4c0c669f894c813513356c90a1bb8d490b0b4f60303c682cba4fcad1002fc1002d30c5c0d800e97d645cec0168e77bb69857362ad657367c2405	1639035944000000	1639640744000000	1702712744000000	1797320744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc4fad9591cd987ad99a8f0e5e627af8e668dd88afb522d327c0add4244b6546cc8679b36dbd7fea7f80dee765d8908ea07453d07fb02bd31d5ede2c4bf124812	\\x008000039c64ef3031c55ba2a3d29187ea9c1be0ee250a07825c4f0352d3d5229e32875c2e0fdb10cb261663e97206c689d50af75013b12e93cf4383b9209014b413e63e5019e5d1b63e379e0e2453472e0ee91d2081370aa60135bbb681272024e3af0ab316725ecee5e1228210bc4ed0fd243707ef2dfcf535a1053f41c5d9b5218f67010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xaafb861392b151a52699bc26be1d5f0b902e85a9c4323bdc0a445aef81a176bd28855d5c9527b175325e6b93068227cd2b4090af204699d576a78e7b54abd200	1633595444000000	1634200244000000	1697272244000000	1791880244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc54a02bac0ba0434376b2b04d67f22b3151cf0b43a65bfc546f068fc8a4338880fd4677354d28e9bc569a88fcb9fdf8dc1d7cf3a3de181f7d156e271769b504a	\\x00800003b3e263d89eef5343140b57e00bedd2f00e5b120cb3cf3dfacef989d124be6a03ba47811ac8d6a70263b1cb0577bc6146fd25da73f6982d72fa0343b5ffb63bc281650642d9de704b30c6989f9c255fc6fc7b10f349f609aee9e043cd6dfd9dcf30061ed394ce3566b546033bdf4c832a1887fb3bb9024874aad84bec1cdab595010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x383f86347f9dc43d399c06873fc017ec1d3a316900ac3aee4af8b5449bd13656f05e101effb02907057f144249980ab84ffa9b38a4940483efc79b68d0345c03	1629968444000000	1630573244000000	1693645244000000	1788253244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc5d618c5d051fc36884cbe3de1759741d2a9f57fd4d8156753eba8e693f608b392d48676e748e1300c369777c4ad47349930c3ae4ae9fb37af7f6158a9efb9e5	\\x00800003cbb8e64bb98b74d24523a8dc453307a3b3f0dcd9f40a4aa128d085eb9e880a1ed2de666de021818eac1ef4f12bdf0d79d525394700ecccf68c6dee8a8cc383e723912195079b179a715f15ec3db21886d912cbde2623883cee5135ce3417f4d2d9fd2ec35ccb78f91c7939db53665bd2aca5b64ff15d236e5a07f711425cda75010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4ea4ad8fcaf212caa42021f0678637c222b7b973b2f2887df33b02e9b20c9c87427a0a2633314cbd58e5f6e557f95fcda995b8eb91df793ed0562277e2487508	1631781944000000	1632386744000000	1695458744000000	1790066744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc6fe22da8cb34614c8f4b4df37cf0dea13c6be5806b05a156da31bf2739f502507acfae674baec61bde79e78aa36c05832eff6fca40eb1ba47547b8bdc81b654	\\x00800003ad8d52167b34f09c106b144fc07917a2409f021d58027b0df788e00b6803185b78fb3042e396385d58bcb443979ed48e22e7b8a25a121db76aec62e6185c4afe7636cf4a991dc0af20eedaea3fc6a2c5136a90b79d1ff09692c837254bd8a0ab86d1478cca1868ae724fd10916ba4a0986159022125c36296b4b7b2ae006c029010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0dcb3fd2f91f88460aa810e167e72c3671fcfce8d03939b6e4f40b77cb40bc16b2a44d36d104afee3b2642f8b30a01643cc413d88a77faf82fb25afad40d0908	1627550444000000	1628155244000000	1691227244000000	1785835244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc83a411780341aa78a17b56c9d62dd7ff111a2134a72a4f881f31cf0529616a20af97911c2704780029866c2efb3ea79f48fb15abcc9af4f94d89511c0982490	\\x00800003cc583f92ef8645e300c59e44bc0010a1136bd2a2851c5d88f0cf6d4ce4b7b8b780cbe0efc583399d7b8076b2c4fa85264a38c382e1060d1f8a3ee25977a00ff04480ed37eb262276d71df35d2911d2916f57403a18a6c9b2595ade904d8ced305573f9ec2726aa4b0f873ddd2f044a7df87d739ede657c767e0a62388852ab87010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd1b60e9aeec5648fb2da72d1e9c1abc979b22ef65fe5b74ff5c24fa4a9c7f30e0cc4c75d7eb8cd2eba2f85d89ccf84334b15388fcda78002d2f8db6739d6910d	1623923444000000	1624528244000000	1687600244000000	1782208244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcb22d65f487e66cbfa2bae0d072166166cc1c544b6bbd945cd0d19364656ba391f9cfc52fed292319ae242ea1b3c7b4fd8cd377ac36fa7c035cadb6b777511c5	\\x00800003be8771a9fccd8349a8ac36eb99665f1711bf7f825f5c5b616d509934c122a2e62a970d968a4a750c39c5f9c468300fd59df177283e337cc4f0c450f8dda423e758064926dce69a77dffd438996b72552dd55466eea361fec915c236ac38ac3ef6955d9b56fce203ea8326409cc956ed48ea13bb40518c14371a3bd3afb7b5b15010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9f5f03ffb0ff32bd8a5756ce11b4736d3bd6fee1f1f300152987f6dc08897156152acc1c4ead9bc702930cb130c836a60220983e68c2c7f377afdf445f773302	1611833444000000	1612438244000000	1675510244000000	1770118244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcca69c191adf990274b9757a8203de262759f9922226e5c8f696dc1b1ac15ed566c3a2160b7d162a6bb3da1baa40027aa84d77841c75402346598ffc224e64f6	\\x00800003f07bf777599d05ef42639a7c5335d30ee1602cfb4cf0d322cd56a8fde837cd5f359f8803526b19372f6dea8da6337f5c69a0bd2c8a7065bc5ccef0239c43755796bdf933b4d5f2894ab7834cfed53c4cfcd1e9d54e008bbef3ec5583d7f005a07233609d1cb9d476100253553d226d5b4d913c72d78e10560b7ff667e031582b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa8af72a8fdefdfc6b947fb880279e580e17bf327e5b69690da46f98f469393b52182ac51dcbe67782f3046dd5e91280e37202654c83a3ff2674af433cd6c3205	1637222444000000	1637827244000000	1700899244000000	1795507244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcdde0f3a8349b8be9575a85c9ed39a9f331c91e9d707f6850ea514d0c3bc3097ca955a1a90e0a334c11fd6c37e3e4a38492802d3021354c7bb00046e14e0875c	\\x00800003c2fcf508bf93d38a88ab04262d7473974b1a028b8559f4f0d9eb85fd625e92989dcbbf3874f2347877b9a05c63ed872511694783153109d65e5005ab149994c260f91f0ccdd52a69355ffec3218c83466b6c93b3764dbc803060f7f3e6a72c749bf32ddc082043354bdcb3e9f780342b43153781ff674831c512cf90e1bbd751010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc9d55726837e463769489d7e3a4a9ef8d6501a332c44d79a9373e0a08990b1f95e15bfe59cb0be371b63ed721e2021f7fc60c4e5a2e35e7389a89671047ae20d	1629363944000000	1629968744000000	1693040744000000	1787648744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd37e15b30eddd48348ee82c1b7f2f1153f14190618c1133b63af0524116d8034c162969ec6f5a868b957db5300cb4cf8ca95e70fddf25a771c5d9fa0833a945a	\\x00800003c0ae593f042152ff55234bcc189c6f4afd1c3b0c100380af6d4f72d6ecab6014d58ff150da0757be191e253c1fd700e1c5af1c3356410d3eedc61be6ee057815edd19ad39b6c6830bfba2b1b8462dddebc319a19bca77820783cc158af8e7552ac857faa17d41e6b8c33d31ea3c899fd4cdd6a47ea1ac21701789932b9fb5a5f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x221316bf85656e804f027173364f9df7b1fb3b959345659d073f846b4ba4dca1657fc9d9739a3a2477923441a0202530e696bc3cfd9a85bae2504dfca3d44c04	1610624444000000	1611229244000000	1674301244000000	1768909244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3d26174e5f35ca609aa43878d927028d9154fa88081765b09b197dbeb94db3f67bb4cb9ca17d5d69126a0693dcb754929ff719be8ece9a43c3f2bb76a99e773	\\x00800003b87e359062ec478b3d2cd4f884a01b59b460cdc2ef3cf767ce15e66a4efbfcc9acdfca81367c2f00c555cb588bceec5ee61998c15cf31a4253b8c02bb020b2ca231df9e3a98b32ea80ba446312ca1d85610c0f507db8f4877ca14aca7680b62857e35dd81b69573552ce3b775aa21742190de1a5c3369f53f7d4e90fdaa609b9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xab65df188f2b45e51a0d4c055c1855d76c441edbf92b670a69d6fee13c25340342a225ae2e826dabdcd7f348e5f6aa94a962d3beea44ed87ebeefe25ca579a0c	1617273944000000	1617878744000000	1680950744000000	1775558744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xda02889e79201ef6b476febc69b70fce77965243775ed191f004e8822cb47ae7c07bd95e1d06b2d4cf8978c23550566754b71939b85d0b5d55597db74f76074e	\\x00800003a90d8fb3adeea5360e3bd8af1304e09a5c618edbb7879b392eeb4e864a79efd0510a6d7e689615857b92bae42cc7718f36183d1e416c85d8d178310bde17685734cb9943c4233316236c49a18e19126adbbd4adee8fe48b596219b320484c4e195c5d639a945f9b10bf403190536271c095dd1d945a9c605c05dec31acc94f7f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x20386af3a28f5c366441bbe7349107128b2d60618b541b3d916d08ad69298820049cb28908d95dc165505d2c2558e3bc76b1535544aa363665826575bd9ce80d	1625736944000000	1626341744000000	1689413744000000	1784021744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdb223749303636ffa3c3e473864f95fffc333a61b02d756fd773aad247a0ba8cac9fb4723c5c5486142a5b15d5e75607ff1d7cb86e2b16f501e39c8d9f344858	\\x00800003f52949b61c41fdd5cfec7dd30b66df2d2004f1835317152a7df56879bf1026490a25ab8b1acee251f6cd89611515a01967e98629f7a86b2806b888b445f63f66e8a34a6014111d346ddf35f529a4b4de5bcc8bf31fd9209ce1876ce5c8e97f62744b89d5612b47acf51199b0477f014b451b436938de3beed99fb628c199aa67010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x01e8b9c9ace30288bcf71dc3b2ad1de4ed6c8a30a66aacee22a5cd1708edfac9a3a58002b34ef6b61db48aae9edfd3b80e83fc589a6bc60da185015aec06b80f	1611833444000000	1612438244000000	1675510244000000	1770118244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe24249be0b890adba81940ccc88e09fce0bf86f3799fe1aaddcd6eb2f8051ec8e12de5575a4a984dfd390b847b47b618e4e454e0d5092d878041dfb8e50604d1	\\x00800003cf2de7d79d6619ef4945f72484080e0c8685ede16ccf879058a0d68653d734e536cb00d0931af8d255587a587d4f952f64a2377599f6253df58467df68ee84d3189fbfcdd79e3f13734442350d78dbf56071af3e065b3dcbb545ca293a6d26396358a8e191fa0a032bf9298f99fed7bdc5493bbc59409a8437e71832ff1bb4c5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xad2b8a301a1d51fe085ec6341b2c730882bd5f1f4e31490d66502ed6da9c094611dcbecf8f8bebad3eb6f4050577a8f9e071bd2e7debbdef33f6076d010d9200	1631177444000000	1631782244000000	1694854244000000	1789462244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2beee3fd506306b7f5dc8b4063b83e34633139aff656e412acbf68d61085ab8bfca9cabc0ab47b95a168a524d7ab43e4b12093167c237af9c1375e2644dd5e3	\\x00800003c75c63a29835d4a53453cc7028658506ef0724230653f8166e853ad7c498e7257aafa06497ec72f80bb0e6ddd7fac8bc6a2a3eee9b16dc1ccc6b7bf57564612e62001930c663b72d687c4a1d96dd0477354814132a1ca9159ea96f219dd6da5400794766bbaf776fe51293edb9db1da30b8f207d7c5bd98c316cdf421fe5ef63010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xfc1a091c6f36f4dcb6c34bb64f711d0caece983a0c203f1630ed0582b478d0331f01cb36242a8a7584720557f01c6b50c0559ae28a3fecf244bc3c96caa83f07	1633595444000000	1634200244000000	1697272244000000	1791880244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe61e3ab72831e4f4a7275b7806e2be3e75275aed375691a5a470018a6a7e86e2a256cbae509389c2fdbc3cdf7e165d1d716db9d6fdb1859e66ada532b33cb4e7	\\x00800003c0630ba5a035d3aba2d72627dcaefcbeba6323720618edc8a3f6ddc1864dfad62b6a6f753b64821f01f677c7b79212d1849d20a38c23cad7b2c0e55e4c865d03f4fb63ba6b62b9d019d53671e4d651638c90b1e163195f9f9064feaadda38eaa7519382fd9b7e63c462b63a5019f014d04bdc511e195eaf8f66f782677d34fad010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4b40aad20e831cf06208b1c53da3f9e025c22e6fdc997e493002cf53ccdb81717143d661e038ff15a34a6238cd30d4b25da28a8b8c5e532eb6cc4c741944f107	1630572944000000	1631177744000000	1694249744000000	1788857744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeca68e13a17b16ddd2fc668e2f92beab269964649843f85a31ce51da65e1146962ac490358c1545aff67df64c3c50c4f3c6656f231158c29cc76cfbc2bd9d4d5	\\x00800003e8841a9ac40dcd4641b80d046fc38d101bae8dcd8ac8ed5d7a5788a1d96f91fd3b711f5e3645c1504a9a03d821f429a74da99dd8533bd2ddf318b080a0bf9246b6753a7358402e32b4e2013cc3ed69643d64a3e811c68606d6949ccb002b6e2488a117b7483dbbb45720c76099ef13b61905ef844bee14322c4ad65bda990975010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1a03f25a78a4400badeb6475661205c3b1136f98521cd0a309a82e35afe1a56ff6dbb89feca8a459437d5f2db99097e7a55fefb34f07d3e990bbd165a980180f	1608206444000000	1608811244000000	1671883244000000	1766491244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeeda3a042000d9ddcdf95e8c7bc655dd2eee53d83d38ead04381a95e8d805ad38c2b88654ecf50d007a034fe265410d5aa2cbf697de9752a5c1e9158412f6ab4	\\x00800003e985070d185bec614b1f57ba310ccc9d846ccef9d28f4d4e44e00ce453a7dd8a407f2c0928a8b039ed766318f550b38d9f03504eea78aac2419ac2429ab6e5d0ce2ac75d775464dc3dd08cd89e355bccf6eab524123f3498e467146b978992dde13f83e098e4e159540de4d6bb0c0266c299cc2b2debf6edc60e6822cb991a0f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdf9d3a254ebbe5c16181e77bdccb1ae3235a4fa6cf7473b48bc897c4979da606778f1677f54b1af7d4ed48c01ecc0b317c803f194b80f0fce4076ab138499e03	1639640444000000	1640245244000000	1703317244000000	1797925244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef52019279ed69d3a663a2d02228cb7cdbc82cdcfd46a93ef9a2b2d18fe25eabb115e01d1903dad39851d433d0d64f385c9822e953cc03db1b6a192ecaaa9f2b	\\x00800003bb8aa49d1cdb1c21871e858566958d4459df236c94acd1b1b3a7418d92593633f0e2ad6cb80066ab314b467b9d0af9b591fcd8df4bff34abbf5cefe3c4547be0e4d4a9cb96f064874f34026508750388e638a47a564460d88b123afa28d385ecd7ea54412d9eff665259728fc7a05f88556dc6d6dcec9b3121596a9f4394fb43010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x850ac6f711afe3b9a8437a0c04ddca5db9cb1225f5d4ced599e0911e37be5bce602ec426e51771b677e804564d3bd44b9cda7b5e4920b8897a282b6286e1220d	1630572944000000	1631177744000000	1694249744000000	1788857744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xef7685401fb39c1d6c3509853317a79055e97ab4d35ee228b700856c6edce70b00dcdbd326d9a8e86c22a276466781941b00ccc3b88096c1bcab531129dd446d	\\x00800003b56d14a28c14d24b4784fdf72742f7cf904cc6337c5e3f4b5927640b383a4bf49da9d5b8bc67e1caf488b4513189cc3c4119e3b9b47c970a912cba589a6be60e4bc79f9517ea6f1f8779a3b42c9674f228b058413c51b89f4f263171025b4c50f07b73a4ec129d610186debe41bc9b5f2542fdcd04b65711e01f86932c216f71010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x2389bd6056761186632a8a9da48d1609dcc9bc6d593f915980cfae28498a3d1f823f783e5b0f5f306faa18ffbe4fbf0edee0a4e40dc360ec2a9063249bb6740a	1629968444000000	1630573244000000	1693645244000000	1788253244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf1e6cede4cffe5b61c8285c392d521303f2a2d012d1e18369e4d9c71a00b2445916d91e8a0a45bc65711723736b070b5129440003a08d9fbf37d5f54eb30ec63	\\x00800003daef3a347bc25eabd227db627c3ddda8aeba5f754e7cc2fc16c54d25968124e3749f525b4b8f19b3571f888adc5777e64140617a2ab57f7501c651d375150be1322b81717bf37b2cdfc5ba9b1bb89ca04cc5034226515c14488a9d7b295f3c316fb38fa95f938c4a83508912932cf5269d1712262e690ecd2a0cdeea6ee63b95010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x76b5aba5bd4f2febba12a095717017b5a051760fd73f2b35a6bd3580f50515097231ba1ed3d8b05071f2c2c2ce06324cc9e359264eb50aa993082585fe9d120b	1626341444000000	1626946244000000	1690018244000000	1784626244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf40a95b141265bb18d21e5cb7146eb187038cda34d00d5e7cdc6462a4ad6534bd3bd09aaaf303076600e9932f9885c4593b2068529289a3d183e10d9dea58c69	\\x00800003e1a8555bc0637b67dda63fe1475a610665933a177c61e292ac2bee20db62254e752db5cd175a72ac2b5dd16917974739df28d4a597041279ea5db3fd6ee32184d450807bbc9c1aa93e15be17cf1053626f6171aa2b7889b8ee360cae11f18939698f4b6b56ff0a17e3a7c124c123cd5cfaaebba7bff66d8ee1a9f6d778174a03010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3db934509c3a96f156cb7a04a378a26a33b783dc6563a2e643a867875b92ed110d38972f4c0fd81c9559711a24b8c4a1b1a5166184acbb861eda4dcfb12ea40c	1620900944000000	1621505744000000	1684577744000000	1779185744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf6f2a923c9db2bb6fcc9996f96a93696eaf1c86878e59d2f94680dcba7b61c19309fcb8a93e9055194aebb8bd2d084fb539c4ba6c7ce66bfb8afc487aec90fa8	\\x00800003ce2bd861da09e3d3f3e8fbf4aa51155bab99613402870a6eb6ef33494c142b758cf379d480a6623656c6f9dab0aa2c76523189727b2d8c9acded7a51f90761a4c6fe285b53ef1b565becfd15af502ddd146d7d87b2ca157c4aa53d769e736948217f0579cbc6cff7803eae3ae5286237d47715f85087916ffab59c1c83950b91010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf20fd5e4ce5bfc2299cc6a3275657e4ce861845479f7dedb8525c985c8fad94f389930f73f8c49e15eebb93ff43ee259378136a14e63c0d4198e59f7f7e32202	1625132444000000	1625737244000000	1688809244000000	1783417244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf77e5718f7af88eedc3924f6e39869f97f2275a63bad5c66181bedc0a3c690640cccdf8acfdefb68c0d398f8b5453a54cd5e0deee4c15b0e064a3160f55ee69f	\\x00800003df719f7891409573ab7743aee3b7f36b01bfb1b1918f3cf1cdfb880450b409cdb6e57cada6e5359f1e1232f621dfe1e33dfbd2ab656f325f2dda6b54686f45cd38e011ecda1aba5ae8140d70ef2ca775d9ecdca71ea1d6cee01680b3881493f8101ec240117d20f8c80a20ea229d8b4c122839804f6ac5e2698e2dfc3f0992a9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1437e15378a21ac8a3e6d86783ea972e26ac2bb08d7a88123f52b251c717589f863c4f7d0cf76a828589dab6929d6831a36d84646d84f5d5801fec4d6dfae709	1617273944000000	1617878744000000	1680950744000000	1775558744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf93256c3d78beebea7d116d2e797ebf64436e5903d8063345384fdacf0e2df18becfee13d2c112ae402ce39a83741b9527b47278221a18ddc9f2797d7fbb6462	\\x00800003cef97e84e9ca36de199b057087159bc3bac5ef858a8078d04e5cbc22efcff0eb8539c1da7ff4947e063a6d186a8238f6ef0e92963e540093e5f5b0cff76d7c470cdc720b38ef070afe2a51dc44eeb9fcca63e9e6159f6ed6702a329c27edb7cfb5bfa30574af2692e32a79799f45c52865cdd4c5c362e041ec01b194c5bc7349010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x41e15c256ec3d9eb48182e8b0b878d378499a3b1b6a392eb14f3e95207b2c6566d999599a6f1e3a3b567dffeced4eeca9b35bf2cdd89d62068fad63057d13f0c	1634199944000000	1634804744000000	1697876744000000	1792484744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfd7e1d8eef99abbcce56591380c1c72b8dd69589431397d025c8768d61c252446325cc455c95b0800fda220a2799fd10215f65d5d0648408dd152232e6849f15	\\x00800003c01be921f3b1e87a07c849b5eda2911d544c987179401f8972d37e079db4cdfae8bc6a51953a294813389ebfd71e5984a30a358474c626d33e041872addee72540db099da9391c15f6cc7df4d3565f853074482529ad4b1a72800c2ef8ec7151fd7138cc85bf8d35777acea2040d487e180ac230bd4e13f5d2946c9515e74ae9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x444d0ad9c1fb6bfd6f17e523d535b2a9351b1d8cdef54610da907f16db458120b17b7e63df0b95070a5fc1afbf8ba1401e8340a801894d29a493620e0bd02b08	1636013444000000	1636618244000000	1699690244000000	1794298244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfd566ad2603f9478f3a2fdaac2b6dc295c688efb05bd95690a6ceec768e77d299f4b018dd924aa4a457d4dda44e3eed867de39258b1c3561c5729015b0edc3b3	\\x00800003b06e87d95f76315546a0f382427c8529e80cd4e26a740fa4c7e9526520cb48deaaea290218465cecbe7df776408162653a6a0edd80ec12e578c5f01bf41cee76d2901b303b0af87d4f001420d2357866ed71462259879fc56e3958fb72308659647000bdc3374e3aaa6425507aadade094c09f67c1a909ef9b472c830cba9b73010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x469e68756f2f5d28a2edab5d439e4c73d48aa5de627e194b5276d4c4e9724a69fd6a4901e1cf593c53330f61eaca868df7ed5f0fabd00ba466f6602b6d2f3402	1625736944000000	1626341744000000	1689413744000000	1784021744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01833c2c3866dee63d74ff546e02b4b249bccfcad6b4c7062d781e823b82b90d897c0c6b14029ed2df9b744b1aced81860a219f3367ed56835e8b13776b0bf34	\\x00800003b5fcb4e751800ad934087614164c2a631dbab9b71ad3888504a2bbb242a2fcfc4d15b11eb225f6a410f87a0b254d934d2cd5bd0c74cb5bfc6c5ed9426b15869bd389d89d88607d091c3f503353078f1524a63e87e7124263d925a42a89ac176afd1d7abc3b47db07bf8fa1d3e79a40e739a6a26b816b1a00c8186b956b258f3b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x313c2d64711bb978056b26cf2d880d451d1744c7120a15840c2fe1b5a9f83915c117bf622ba491f15644932654663b0c9ce0ead485bcdbe49dbd3b9afaa18703	1625132444000000	1625737244000000	1688809244000000	1783417244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0283612b6cccdd53ecb165e9d7d8a9d8cdd670c8f2f2ab13389cbc54d4c15f44660ec5b20615865dabd40b31b67d8df40fdcc1db430b9a514b1a985d46a4bab1	\\x00800003de85d1e2061bda56ff54bd91dbabcb8b07b1fc5a44766b66723ccf2d487a5a8364498d1cc1a31528ee1d27d981b05f9a8e6c0d5cde1b51ce8c22f9cfb79366aca13f0b6974ef005f7170314144d72ccf119a253272fd118625822d3143cbb0fc7573b996fa8d5117bd7a23fc1820169e3420010c327aa297e62bb80e5f58fb79010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xff6501fddb9e715b97a55131744febea24351c4704f47bcac21e7cf6760aa331a9ef59e2a7e88b21987f62004ee464759dcf4508a73d57c9ec2d3f91db457901	1621505444000000	1622110244000000	1685182244000000	1779790244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x04a3194a3446d41021aa4d0a5c339b1e5adc430c7c77e75e2bbbe8204fafd077edb5d75fba06c602a7576fd4a39927f4b24bf731a40dba8db7bd00a43197a7af	\\x00800003c2d3918b2934e513951e79c956857424dc2ce373186e75f0ec3e3b9ccfc4163c82b02e783174bffddbd1076ec701a0f848abc27fee5f39caae3310210e1c3ed5fbdedecbbebddafe4f54e389708d0d38e1f55f439ec6c4ce6f10e14546001083ba3b7f1188fc4f21a49f4a0486043414e42863dd4effedc37add1a81d369291b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8cdd587b9ee9d82a49d3f93121dd7dbd20a933ae801ce7dcf6cf1326fcdf091fbfcefd82b7b826abf84c6f1ca8de0000a3ae2915708e12fb2d0103a4c77aba08	1630572944000000	1631177744000000	1694249744000000	1788857744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06d74f1b48c6fa37bf1d7e67fbf176874c062f28f8152132912fe52d044b22834fc20fa4bde9bf6db127cf6537e1053745894e5e377663f410d876520dc972bf	\\x00800003a23a4d7f639d70ce36a6941418393e0d4387b5eeca58cf09b43a2b7424dcefe3397964fcc53d511e29909fe0ace5e360f2ff347d9f87f92df0751f4250b07b978236c274ff9ac5fc7bd1079c7864b480d6c4117b57368592085b06b2d5c4ee227c48eac052dfbfd0598688daecc771f51cde31a3bd2e79e8e24705a2409aa483010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5829d05c17883163504c868d219f1547a57c6232f60e5d04756103dc92c410f62bf867b23108eec283e969d40d5f4092321f096afd0da1a8fe350d1f50089c0d	1629363944000000	1629968744000000	1693040744000000	1787648744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0e076325aa680e3e96c8c720cedd4130437cdf4a9224aeb5bc3aeeea16f0aef2a2e9ea0ec31d76fb04c4238cf5f590b876c82807761116c7c06a3ad90e0a85fd	\\x00800003c538756e28b40689d72cec6099225c837db6755de9eb2d3b339ef3457784a3463ea53edfb181cc1ac03c9eba3f46023682ddad073112055dd69a3b17bb7aec35c0097b449bf4234b2c4d519a080174b3f79e1f67467abcad7fb1632d42f3b34710c09eb0c7117081a7da28ef8356040eda4cf07e55193f6d2aa7921f69cd6a79010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x40313e61e30f4bd22123de3e0b83045e2e18c6c32f92f05abc375548300ec3959b781abc09a25fd4e18424cac57b0fff86fbe81d39019219e58665e1a6d9d60e	1632990944000000	1633595744000000	1696667744000000	1791275744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0f032834c78125b1f9889ebe047a2b3506b4f09e18db30e9d906f4ee4bd539460e72f6cbdcf93450bee72997dd309645a05390e832487bf70ee1f50cdf171d8a	\\x00800003d9b870777bf7904dc4af6ceaaa5747581a639b6562cecb954ff9bfaef6cf27504f9bc103912b28a1b66300f9bb139561f8d4bf16aa147c9f458e5fc7ccf715052f090a6ee364fd0bcd9d5af351e0661500285ace195b7ccdb629f79a0ed5ca2939312cdbf3b4c1e502ed12c40aed6e274a7ac6ce9f2a8ec4292d41acd9e260d1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8298a7d2d2ff494f89b35064020dd64bef47e69a71adc262bea1e765207ef3a5e8f11722bf4e7c4680777cda8478152512795d091823b2917263553624fa380d	1626341444000000	1626946244000000	1690018244000000	1784626244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13c784cc892fce96244d3385b595785e57a54bcd2ad2528b6b6275a84952d945bfe5e920662c4c5120bbcf8ec6c5b8417659aa9a93dc6d07b06daef8004623e3	\\x00800003aefb0ac5bca5d4e17c42c2c2332587a82fe4e1f4e4c674185a62d02631194b146530a675a8314e78d1e5c07915d9da48f0dc717aff3052f0ea5c0388119375e09b8bcce2390b19e9b278a6385f889e427c08487fb92e8a1a630392103c55b2faf354aefca4a8b1dfd196aa6bf7b2609b9786a5d581184bf46d74adf2a6cc6b9f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf5301707c0e99e4e7534c44174683a828815aa458ae94756c2174a64a34d43f88d699f8a059f969a91e0238a361a0c32bc69b9294956a272c33b586fe276160d	1625132444000000	1625737244000000	1688809244000000	1783417244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x13d339a6d7a073e28c4254befc0a5ff5236fc18c0a99ebafc28028780de12628dc8a04abf92e9af6dbd2586c109af73c4c00728e22fa07152ea194170fb8dd83	\\x00800003dab7f7f37a7a5656351bdce19ef03532200095eb909ce1aa74585de7c80f7f571a8483be7361dcbfdee3345440dfe4944f90f3f59227effb5d14855a23fd8ebd00c6a5c03d5c71d6a5d00a98202daaf164791a6ca0d53125e7d0ad1c0d8150810a1f527ab35b365aedaa974b7aa44344752593e8ac877bd9c7a5d4e2544130d7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf5b4ac9259964ae494bc1628f2e6f552e54fe9a15c4c6bb547b099f50ccb0a711a421d7b56a7868eb29f74a9efcda7f7de471b3317a6b1658de07c12127de70e	1625736944000000	1626341744000000	1689413744000000	1784021744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1443fc6af4e2d558af23b991fb6d8c13f9c6965a1e0c778f1ae588359160a50d3f52d765cc87f7a93f8421c8b704c7abaaa35760069cdd3e31f864ffed8c53a8	\\x00800003bda981d35c1b5d331cfe9a0a041fcf4d819191c04223f96a332bb5ea0d72a8186a0a5da4664c2a3cfc76ed0c7c1043682f3823f50309f9602c7602c29c1cca7b139caf38728108f0dfe8c008288af54177db1756198a168c5a34ee7144a7127ab0c879ab68c05cca37de535c2e85fbcb54add3e280afde036dc1350b954d0ff9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x346baeeef61c54d7b1479eb385926e69eb3f0e459db9385c6646d71a59ee68908854ea9715b2231b965231a4aa1da231d46bb5602b88658c3f4dec63098bf605	1623923444000000	1624528244000000	1687600244000000	1782208244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1527252f03cf1e36c58b875c14926fb98eeb520fa2b0ef917a663126005f6545ddfbb72f8cd04c61e517ffba983e75d490b52979a5ede907e2654d639e9b127d	\\x00800003d6fe324ba013ea2731dd1cc451aea9f73605abd1a5c2b80a4d67a86cd14cda9bc4d92273cfebaee177ff3f89214e95dd0a758473245d9d0fdc4507fef9d0494cc41543b8388bf2f52a122d36a42fe70b295864fcce8e44a9f8926a73d5c18c1f80eda8193d2f145c8fa152da59ee510a0d18e3df6d79744aa92d881c1a10dec3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe7bc7a2d5c1402e9120f5d738b1f5958e5456e8372b391fc59d9e8b196733164a0b1925e31f333274a58749aaf498947a894f5bc7a0401a2d82376f96830b607	1611833444000000	1612438244000000	1675510244000000	1770118244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x18e78ea2983c1cda93724e9187e6c9ef76c6d6f3187e317cfd0789223130a41d184c0a31f6f029b2aa6347a0d52dd94130715ac1356e627be3c1db3fe2b30224	\\x00800003d8a6ecd5d04e56739535c3196cca18c09b59a59980f79e85911327a2dca5ad8afc7e3eb40dd0f3f6d41e1b42775cc4b7f00734156db27419fb94419ca432968ae2f5d9f9034ef1c0cc7ff9ecf4dadab97d006fc56edfe47e9f53ed2b5968cc07f7ce07f3ba2732101d560f9ce0513c458351fe609ede62c79c3ad5ecd200adaf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x328c744c96b9f2ca9b8ad45f2b1a83ff4f26f9b3bee3de3b0b46e3983a210be7cdf82f8e2a2e31a3addc364939bb3033af801043fa3eb3e90dc07636514cc906	1638431444000000	1639036244000000	1702108244000000	1796716244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1adf9008cb2bd088ace501e8874905827c28c8f51beb8afd5cdfafae166593cb9b16c1b4f1ebca5139ee61a4be71af585c0d31a0e9263d237c07b338b25fdfec	\\x00800003d638a247e3c9b5caf0e56e80f6b996a472cbf2a52bf700c2ed804318e9ee3d1e269712e4eaa833543022929b2f6926b467546e53a7edc5b20651dab5a637afba0cee8327988b821c26fc5ce10d652aefbb13186f14c429e92618812aaa468ea6e0ece47fd8bfe168f8c08138f7d387b0f89026ca58ea8669ff3ff0137e9df883010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc10cd60368ee69792f1bcecfe65a677c88bc2da76971a7f9af81ff15668adfaaed22a14523fd7f868b83f24600031fc85e37ff5ce0c92f1b999b4bf8db155a02	1627550444000000	1628155244000000	1691227244000000	1785835244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x22cfa0a5c468e3ea95bc0aa1da08558e4c0e9ccee3d31eca34f4716428ea8612e0ea65bc971cfde8ffd05c50cc52386be5c5eb918ee6656699094d3396882496	\\x00800003ca7c87b45ca6f536dffde6d2bb9f7d381703d80c41b034383fdbe1d103119cee6dc99508b2a2b40e415346d32c039e176841d10ba8463efc78d7fee8cab193d707331c1f60c420012e997fca24ed77313cf56ff9e3960325090547688e6ffc40b8f44e1b4db53189728416b05080d7225f644432d90e0b594d12d88c5f764f7d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa77efb0f6bdb48461dbf18fd970e5bc022fe8ac48fbf7f77e42f99e2079cb8c9f73681dd3180d8c31bb2f8c5294549d3e01db76f622d81746f8070631c4d7306	1614251444000000	1614856244000000	1677928244000000	1772536244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x230781e0e5b9ee4e197f47a419bcb6c9de5dd311b22acf1a1cab470c4e5cda04bd4555702a60513e1aca58a00d202ea81dfa452559632d76aef618c1b69c92af	\\x00800003b40da4bfbed3a0b4f4db11d14332df365b3b32b4932adecb705d2041f58e4204a02188f81c645883337c8d450a3f1df9f9a5b659a7a1a8c1cc517e5958de7f5fb5a8c9f96c318da9b2664f235431250d94b06d7af573ada2028aa0ce9a39a4289b834b86f4c4045b38a696f6673024e0c1ac5c62ab5ab2127124a21d3008340d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0947a117f7c41f537647d5b455d39a428d63650fd285d0fbf74c48397ca0ca32c2687f85c04c4236f3fcb6817fd38d60f2df470c199b6fc951cb78986a0ce600	1637826944000000	1638431744000000	1701503744000000	1796111744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24bf05f7e3a935dd52f0055becf3e78974d0022f1106bf7a032368813148d7d4a9cbd51daa7f3eacfa2bc89a8b18feaed7fdbc09b45b13dc2c07d0c5eac38343	\\x00800003c75701bc44d502dd60c0df6f312c5517444a1ae6414d28c4e5cf7bdd538f34983aaba8ef4945b16b9b17e7e1b0b8ad156f8364506030ad6dfd206fbd790d084999a5531b1ec63626c56b932012115d645486ddb2cf034340f72f9660a2c16d0a11efdbd16fbfa5ac14ceb0ef4f828558d210f368ef76f94c1688231c174dc491010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1aab0f675c3ef63dac93ea3f56d27736670091727f24fd028fcbd04b7db09da4e3a3836928cbd47afd896d564d37f1c951eec1bf48101eacf6cbd02cfebee200	1630572944000000	1631177744000000	1694249744000000	1788857744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x25f7476959474ed54b6de280282ba597c5f3674227c6bf1aea7e22dfe4cf0b77b1a12c5e027aa92769f7bf533335c31fd64fcefe89b43b034079588e71438edf	\\x00800003ac9f44bae147267ffe0df89f3072a4fa5c0e4a0a941b0d77e0c5296124630836026b3fd9d1ea1633dd4915e7522a11e9662278df413a266ef4e9da76077824694defce6adc17b9e3fb24eddfa74590ae2576537699fd1304779bc576e682b180d1f976d5648a7e6fe999605872520e259258cf4dd396cf60dffa9333c1fa3455010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x24ba19419034f631e1157d5bb4d26843cbbad3388fae2f3b61f9e3752de9cfa0196091e6011369a686bc69c328269546f5a64c0f243c355687cab158e9a53f01	1632386444000000	1632991244000000	1696063244000000	1790671244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x27f3785f40df6fb390a5cdc5e2755bcfd368e6e979cabefb28a61cb4f8c12854286ad9686c4f11d7d670741e0f8a5bde3efd800794200647c708a8b47df86c12	\\x00800003bf34eca0f6f8bab79a93608c12ae038bd4714c9bd867641e1d67a892271fbdec3b4caac45a76f24dc323c3f30b01c79265f7e6b3cb66b8840ae6b42b837347280189e2a9fec760e8619794b9e5140079b9260d3c98b82b2faa0717f1cde29b677c612d63b36529d46f5e11f0710d957d04e6d1a3d7304ebd4a26c6e5c40ca88d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x535863fec7071e1ba0b54c37a0938bac8c2a98589aedb560ccc4900211460414b6d52ca0ce4ee1140eecfcb115d437cb9eb89a94227b8647669a9e94baac1802	1615460444000000	1616065244000000	1679137244000000	1773745244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2f53300410800edbdd99b398a24b451ab9e4a3b36c66720260ea1d414b3685805ae684f85fd5df35a36aa35ce491a2007085c59ac7eef24a5fd454e12cf06c73	\\x00800003aba87ea8037da1ae3aba4b25201c3bde9ecb2e3d7a82b2ad008aa7d6f6e16aebe4eecba25705889ab0df61a6c9c91678aff161d82c088774a1d7acd9f91b74fbd6e1f4eabd065b06a03e4b65ea8348ecb2f232e73df3b4e7a90b3589b66bb1449f2d9d2697b2e736f57f5fc173cfdb193138acf377fc1648f30b7edaab4e064b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x75bc3cd553c21667afe27063945e452cb48fdd99627106796610b0e22e2b4e372d792e7c8bbaec57561f9377b88c10cd47a076fc987b6e007eb5320b85653d05	1620296444000000	1620901244000000	1683973244000000	1778581244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x00800003b818f3451729e7ab5a8da46057ddcd32c9fc6048e66a9d869b3673fabd83840e3116d5693c5e7acc7c0c94c96b88447dd71dc2168c2de54a926745196e6fa2632080ba18b04d7f2a099827c7e081d47eff2b4954461c3cdef6cc61068793b6c7a8fdd8fe257f5f3695eda9b6d67e9b2e8874cc99875cae1b1b96e0a688080def010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xce185cd18bd8491956d8119f0dded03798f3f9a07b60800b51d039c1e19da2f58ca37a32275519d784d3867363f64e1c347782571d0e254a8d408053ee103703	1608206444000000	1608811244000000	1671883244000000	1766491244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x33dff6b7fb2c96a75cabf2df0cab9310acfe9612725dbfb2ad919732469267e1740cc392b6bf370410c89e1045acf25bd6ae61306144517f81a341fbd9ff1262	\\x00800003cff749db770cd0d78d2e0a2d1004cd822d38006717543edb4ca53ad458583a2b7db4dd27060bcac8fbf5833a0f9b101a1df8a6cc1a308066ab45420ffee374e4fd3e9e05406c94041d03799cec20ed623efc2cfc0c0e2b0f35ef58a7669523dbd3696c5896ae863d98450259df536d9c070cb141e72be06d8d10a94a7e3aaab1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa76eea972fceee8fa74be9dfce8b65295aba5017ce89128607feb3b5e0806c2464ed052f763c1afefcf25d5e0724019581ec13dc3f62b10aa39761806e1f8207	1634804444000000	1635409244000000	1698481244000000	1793089244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x38977d3eaa150a2cffcdd8e0693dad8e67b4f7ec329889eafd469f411195b1639308b3bc044b65cb88ceee6ddd8986f85be5cf4f86acd832686107780ca9adf2	\\x00800003ee8df7486400ed575ab622de12afa5088a8c8882b72a6670e1a9245602377136cca3fd6d0e41e4d2c861dbe1f9d41f81c042d16a9bff51b35375da157fe9da7aa29be140653dbbb5e1ef7c47beb8255b13e7b2f519d2e72c19c48b10c95e0180316055224bf18a1b4ed786e632cb4232b6c99231b41e915716fdd2acaf393f01010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x005f11596549684be10c18d1f4699252eeedd98168a4cc2a06d5af25aea0e7c50b31ab5102aa28a0f17de6f790ac5354b1406a74a941b8042639dd7bf8ff0505	1616669444000000	1617274244000000	1680346244000000	1774954244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c432b1be09cbac66075d61367945ca147f3bbc538e4e27f768bf8ac90686a6df02d2941123dc87f199f8351307e14458f53e7ce814e9d52ec3c8fbac531d2e8	\\x00800003e82dbc269c8ad0c0634cd82b2001a9cdc9ce1dfe8225962ada5dc9155c2c9316913a0027f3e3f5cb01299aff70cdc9cc7bef7cecc64a94b7cf8496cc612dec1b27022c913fc3b77b04dba3f8ea306a9190e6f5699df684f2e8374319316c999f0eb0652a5eef88b439114ae26f73cb8a670cdbdfb4b35226fc7c25974b979223010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x21db5b731f6a9374006e5e13fad35261995e6c8ce01a34a8569605d9600ea7a3c945fa5bcd66a1a747a2fb2ce6f8225bed785836945ca2e9e6f35489782a1b02	1634199944000000	1634804744000000	1697876744000000	1792484744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3da70fea3d01e6600c97435797cb3aa5911111d07297a4289092961b24126c7c72d92fde52bad0775e569cd6742ec7c3196bc7c117cfc6805d01ab36cad84a0c	\\x00800003b51df116a128e9e1d331c48ed83619a562786f650ec501a667b78323730a1ab973ecf831d3750f7d2595fbf3cd1742d28104dd8cf10688aadf2ce737e5d53512645bc3c7ce983e706f2dce20b794a36138040b5d1698975573bcf8ea33c6cc3b9916849aa45e59c76a61d88ce1b7caad446c18281680df55fc2a3267cd0711f9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6677398949c2ee4a2bd9eefdfebb3847ae459862dda0cb9e3a45e4c4d0521dacbd20985b9473565636eeb53619064dd63e98b3d5de79a7a76cace9bb82e3f900	1624527944000000	1625132744000000	1688204744000000	1782812744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e57497b861040ea57e77b3d3750750bef2861a19fff75a5e2bd3bb028731ae0bc8b0aea72a3ab963ef6a829bcb8cce2abcb4bc4e6e718e5cc150c8de6ff0209	\\x00800003b1e69d6286731f65df12bc75b97b933bc318918ead1179fa9ae03ce6f1bc0eda08dbc9c90a5cf159a447ad4ef9560575c5753d538595002258c4749f5ca301e10960d31edb2c179c0688cdc85599adb68e61bc556f3e8e893b7c2c5e2812e605d62fc1c74e60a2b3bd09ad030260b5d359e4b3f8f96593303f136961fcd37b23010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7d981aa0262300ed08aeea9e2c828454cc22914f9e4aaf063524a00c2c60f372c7d96c9b7e6371ca4366156d675ea6a141d4a6d3ca75fe21546efc9051519200	1635408944000000	1636013744000000	1699085744000000	1793693744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x40f3aa07fbaf69705fe5dd87cb1618ceeed70daa2a5d18fa7c677ec20dacb3360c6451840a4c6b8353588123b0e5f34f0f8a08b4807d8e2fab3127a1220ae8b8	\\x00800003bbe15a99e1ae82b81ce4aea1e6ee3633c9f66bfd911af150ce6ca7fb03218becd48d8462d78cb0c62233ae379b6f1b944970555fd1f444c631355f5b3fb6bd43f01c2b4826049c224d852e10c2c410ef09f97b2ea7589363f29a8380b974b3e641e717c40634000616d15a8e7d6215362f3838229d6617faedbcbdeec84ab1b9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x738ee119d801247e71f543b7ae5aa19ebd2e000e58c6cefe132b858eb86b7f2f69dfb2e7cff344c42cedc74da2c27117706d0b77a0c958be130d093619d3f707	1608206444000000	1608811244000000	1671883244000000	1766491244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44bbdfac1f7b96187c667513b50422f045aab734354894ef426f14faa373c6e62a58936d9b0eac7aebb12c3bbe7bc9abe504c58e274fff40b7e950c8885658e0	\\x00800003a66662e69823329a0f2301a184197c70c382136b9ad80e189943b5df3118d4db55aa9f2d10d0ae87341a21c896362c90dbd1055f24c778d927bcc079163fcbac56d493d500424b3d677abce64e4bf1b1a4530884550229a110883d3a3dc4e25ba8683c501bfb1ac9a6a7b91594e508e7795c1c4bc98dbe0b4bcbbc96d211229f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6d40ad7c81965716ac7f5db109021c9c59d019cea1e20115ff85d139ec8ce4a4bb9497edf4b78eec7f5a96039e7c773f7df970631e288861c2e59e944b961500	1639035944000000	1639640744000000	1702712744000000	1797320744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x447bca2490b41636c51e88d7ec75f599b9538122c53bbfdf770e368238f3804e5e400e64fd65beabf94914eb242dfeb80350dd9be820db515b2f98faeec3e335	\\x00800003db6254ca531879c5ce674f4dc9cf631a5d46c29c603a7e615f3ff9aa9b3ef2caa9f8a4247ba649b4df06c75effb5175779d9310adaa5b6480de1a7ac1dc55183e60b6caccb1fa0103fa263d901aa806d1b5695693aa8e4d514547fd4c687ae106e972ad08abce950360164a233fcd66beb42ed028cadfa30aaa572885684615f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdc77a09121c4e4f8d5b6fcd51fda401873d0fc012b121a0af1256299d71c1b68cbb13755e7467113496f1a9a65bab107f16f55947c213e9c21a8e459eb710a06	1626945944000000	1627550744000000	1690622744000000	1785230744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x44f3e0d823f52f5a05d2f0ab992e3ef89d571faeb683e1382a4a29ab8270e9ed9f22aa8690eb99eeacb52c6f28ed679a44dac306ed1e01150f7b8450df1dc7d5	\\x00800003cefb5fcffd984a729558462dabfb0ba0b74ef79781ddd941f852f2df7f0090fad5616d6ccb606cfcf9eb2ffc99800b32c49bf3c05824fc6891ed364547dd035861fabb0a7a02d76c89b746f42420da3dfb3ccd50f39f6d258f528e5c55f39a8789f9b0ddc72e4401125c194938734919662641184d8c313a34918ba7135c3635010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5cb6946a12f5db6de4e81149fbaca17cab3dd472f2a9bb3396ad8c76f91234400620dfe46e1af414a2dc204ee6153a151515d56a5d1eee7df2f2b05bda086a06	1631781944000000	1632386744000000	1695458744000000	1790066744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x481f58fb1ba6bab6a4e65a577244a15ed348314928a5d3f99c19b7d40e8fe92f219833ff05dfff2df2dc0c8b05eb1dd2e26189c04bd78623ade78a622f1ee6d4	\\x00800003c875fdacfd1609dcf16e54402533958986c34c2b6fd7ca1dd08a23cc32b444a695a7e903676ea428a74df99dede6ee5c8d0e90be88a0ebe96c04e37d13731a327269db6d259a8199cee204e58495d0af5c18cbc0c411977036c6e25a147ed7017f5eee244903bf80065ca164ffd290ce506849c8e249e732e1bc6fb4fd21539d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x870ebcf9dbdc17e857c6d714f7b0c1de9a8bfc0b3bb717638ce2c94091f08cf456a9f2187ae9c9599ddfdc0cf98e3ee7218f02d9765afda6d15e41f6ddc40204	1610019944000000	1610624744000000	1673696744000000	1768304744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4d67154c05b5a0c739f75ee637b4eb5e2f3409da81b317ad5069a69a75140be9d5330b466c235eb99a0a6c52f8cd3d002f4cd3b1ee43414efed92a9b6206cb71	\\x00800003bdd6d7799ff02c3447482756ebfcf8e96da2d0b56c0e255bda8848bf9496c3cc009100fb316e95bfe70af19477a510b61ba23ed0d10553d21a70078935d7cf5b83886471e9b5a9fe55956588a41756077c296ab78021ca7d4095ec934b1c39af8779c6ab2142071f05d7d322b6e74c3395c75bd348ffd42917aaf5f21d614dd9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7e99ae340bb09bdb3b3540acd61145628d29763cccf3ff271be604210af2936e1bffbdc2d942e81d289452342395dc5108893f8708e66fc06d1fbab3c5bd5c0a	1629363944000000	1629968744000000	1693040744000000	1787648744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4e3755dafbc8659adb63f586424befab05df3b57eb3f0eb6374ba26c4a6aa6be85a3eaa56c2c19df636ec5027aa1ff0c08bbd5a3391de9a96314df35169d53c3	\\x00800003c0a711c3fd39f0808e12985f1a77f12e22959fd0444137b3d39f9af8aadeb78d8702ca4a2a475f2213f2ee47d540041e6b9406465c5fb17c6fd2deb084209ed5f7e764c50394f39c48c74e501d7d77fd714c1d5b599488586ae3e8c319aabcee83872dc8d844a1b9934d018e79d211a5958e70b0a1b5cfc6087bc352f2d25777010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x991f71524532d893c79bf341ee24a8d8a7c81a0b778122d6a82ff7402aaab0833bf610c916ed6a06b8adc4e83d44b14bdb7fad986c238eaad83526cda30b450e	1614855944000000	1615460744000000	1678532744000000	1773140744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4edfb762a69df67783ed09b5845263f5b45b0d91f0ee92c68f3d675f57b15656746a40711f10bd0daa4e9527cec39ceb934658fee6834be0a0664e50aa7047bf	\\x00800003dcb0b23098b7d51b240331d402039da6b9ce33112363242d03fcfc25de69d620201f6af5f467391d237fdcb429688e28ba4f9c8f3fb0045b20b9246826f527ba0b8ba900e43f41fc6a5c36f676f3619ccb2212d7b8f11deb4526e61048c67f865c85938c2d917541233f3357d73d543103a9742939f45e8109479692b5437639010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x33c15f0dd5a111b9443d354ea916b61f129cfd06aa1e9b91f0e4a816f001c64cdb32ee25247b0563abce64d5d716ae5fb016251cc1a0ac08efccf999dffb970f	1629363944000000	1629968744000000	1693040744000000	1787648744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x517344f9204573e9cabf57e8d1e3da2bbf60747c503c67538efa1d08e42dfc49eaa9c2e7ade10a4e1f2b8ff7e57220bf977eb9da025283ed62aa155df8a1dc82	\\x00800003a8201cfb45825360880d0beecfa0476cc9a2a20db94410b6d7e405c04452ffcdd1169105be9e96fd645e9f709075b7812884903f76c56a33008851070fe85428940ca027c67b93f7569ffc02992eeb20898a609c5e8ab8cc22c535c11c94bec4947dad66f9e47319bf7927e20b58567633947b8394d1f8cfa66a08e0e454b3b5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x71d6ee5087585c7ac57f7d196ca11185975d72601e8c5da50ff824e3222293c0c7519530225fefa44018e2adc0a22ff70a652682fe409f756bc2085a6d254e0e	1636617944000000	1637222744000000	1700294744000000	1794902744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54fb2716fba2fcec9ccd2d8a7a7ed5f5d2486e2dab55df9a289363eeb6a66220222ce20d0af5bf252e207e40f1f5a0c2624e7390d2a7806d648ae6daec7ddabc	\\x00800003d28bf3f21e30fcd87791f94bb032437e2a3a7a3ac5435cb49ebaa26954a2e833ee18676e9edde98dac3ee566a28fdc4d7dd9b9f376d33de8b01282be1beeab0ff8761e299b0492d687d03a3c9f24ff1bedf5055edbd1340b5560d467f2a3a118180e75af0dd6a6a1d5236dff7567bf4f7207f929a07239d6277020360ba45cb9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa6bc250b834ceedebe1e811c41a3d93b9dc2fb99d3e1352ed8b07dcc8ab83087665f40668310b5bcd82bc1e3ab28a9c67b34faf2350cf7f95f1720b54148370f	1630572944000000	1631177744000000	1694249744000000	1788857744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5797392d9b68d7e9c4a0926b1a414a5456511f73c59a689c169e6651d9d4181880fe311f981874bd291a968bc099ea9f86d105ec797662d7a37f54f46f817f39	\\x00800003b3987ed48e3067758673bd0fcbb54058ff0bf17d4be74a4c74ac10238c48240fe662f8af60be20e33108a10fe6c26ed8dd4f096871b15c850513d8e213c5b3e7e5dc511596635171620510596687741bb0c06a3ac39e7d715f7e24f48219474c6bee21a6dbc8406533cd99709e3cada4b5f536eac07130165ad16e708a3f535f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb8f7c7cd15bffad8af613c8dbac1709176aacb80925a41360e6aa919123cfbc4eb4c4b4da16069f922839c06236c5d3998e799e18b88886708efbf8c557c6f09	1627550444000000	1628155244000000	1691227244000000	1785835244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59c3d3a5a196c61a451b2ec78981fb38bfc897cfce5cbad2dba774f63a8562560dda2781e648b7a00f002ac980da847f93591e661f929c652d1c0a76d0c4db1b	\\x00800003b6d05b2e67f858a74e193a807846240275ddcf80e4da581484aa0c79d08b99c1a298d5d9ae441e26b96f4239f5f269ea5c41640587437a5fe7613c866a4380bfa5cf912e63a256048a1fe3787a358a8cc14c3af35eb53d21efb856d3acefd1b62f09ad2f5ea5acc6bd6c0f334ed5ce4cb474e0c1dc3d4189f9a72f2e496794a5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe79b57144c7583c9d32a5a35e1452b9e6c4b72aa421f5247c787abd255e395d6f5c593add48d33d2d2551f2c7c74ab6f41a56b5e9a311790482e4389d8a4db0e	1608810944000000	1609415744000000	1672487744000000	1767095744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5af7bd0273ff0fc4e25b3653407c952a187f9f4ee7458c52ddcfb0762c4ae173b59b883047b62e4d875243709d91fd8f0e0868171e5b895f15272d8b52582394	\\x00800003ca249c369fe9e7ae1e17157289ec7d76cbaaf342f063babcd8678823828041ede76983629678ed6889644baba9ec15174aa7ab5c4e9309ebab2f4f0ecabd9f597bf7e77ee2d9f4d8f96026110969bb62c2b0efe0bc1fa8f89623e10f4a119a0573952de290c328cfbe628b6e70d3434bbe8e1acfceb04d7d29f6a2e562d36cf3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa9568845e704935f88d698f445330357227d744fbf715ac8c9fd060df1fa20de0c868cd2866c9755bf1749f037ae2175a30250cc9cde861c03354f5fcf49bf01	1621505444000000	1622110244000000	1685182244000000	1779790244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5c2b2ce72c93a785f9d4475ee95220f11be31c7107b3ef9b8483ec85fbcb6a0318e5a937c2a9f5ea60329562d02bf6ded6944e56e4af7c71d7a5e1e222516342	\\x00800003ba5b9146519f4bde9770998668704d80c8f017f5a9b723968c569694ff1af773406580276742c793d79b16c5816e99f92cbb171917d5c69ac5aa7e4802f85c5ab38c9403d30510c44ba1a980d0872f2bcbb2e971cbde9c07e7d5880d2cc11bbc47c8238e4d873fb210492499ebebe2eab81c390411098757ab5d17133513b885010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x09c4ccce3663aaad820432d079b91ab2de85f2b064cd64738dd083cc94c8eefc9f52b242d9d9a60f73819729e5e1c538988b6715f04c2d597529ecde4613af08	1628154944000000	1628759744000000	1691831744000000	1786439744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x618b72ea2325de368341159ef58dea69f7f0fc7dadd0c8c44a5de9d6337ece0380074d7ff4a075d8f066cd22115fb1aaac8638823dc25cf9652e9679cf1f1310	\\x00800003ac23a08ca9eb91687a8028a8790b3f0df6bb774e3a4c3ef693d360cff83c2b6aeabb4012d8cb52a1d91b75db42b18dd33adca58c42c14dda56a96dfaef76acaf9f44ff081d45c4c8ed093a5b4c4870e2771d9524b698b8ec2207177694f23341fb02445d898b373ca1acdb71cc922f0c26356ff9490b2c9911e5344b12c17339010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x302d237a758adc227e1d73bb567e694e520bc94d68dd3d27615c0e5b34b61cd52b4b37155029c5a0cbe6a1737b8fb119999463f38c3c65920ab85de788fe110a	1623318944000000	1623923744000000	1686995744000000	1781603744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x652bac6295c3b7de523f806a7829e4fc9006dca48e8535531a5b8116382b4eb144c0bda3a614531b7486e41548dd362f6e797609a40fef33d1fb03b3cc3b06f3	\\x00800003d4eaa7fb0fd265311e577380c509c9bea3815c1024938adb9e923c2e852e7b656c949996de562830f2d2e86ce713225a9ea9768c351454293c33b8e0e8fe9b9f9e2d6a88420565cf384d5b3359181ad91f0b44b13f3ce9a85d266de25663eeaadc8ac716643ba6c9f727588180a72d561e857083eba08ecc1b39d41775ec0219010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3172a01b132b6e359bcd17c76ec7ab5708ff19aaa09d768f7a3c7fc49d18bb4f0fa74a114db7b316343ec4f856700de13683e3776b4b11f489fa92cd05f1b503	1620296444000000	1620901244000000	1683973244000000	1778581244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x658ff42f84e243ce37a5743488b355566e6bf3adb935546b47f5bc8d0307b581f65df0a722454599d8ca8de36d0454a18e7b357599da30b1ef469e0e92ddc6fa	\\x00800003ae34ddf7fe54ef414e74f578f8ac0b5e5a7c4a84007483fc6bfdc32c20711090e0bb695f16ba62f9559f1be85f610f2fe47f2d381bb0bab6d00370921c4b0f72c15ea8065cf1e06c9dd831b48b52c4e838166f6dd27f699a88753469e65ac1fd52bff191b10a6861cf4e13b9d2eff00f6c2d3b3f1d8b40585692f1336a5b6541010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xca8ffb5228c311abdc3f443ef939a37c7975f7a16b4dbceb8bca39a48f5b242ee8dd12a3bd5a86f38f5fa1a3c454bc76ce8782b63280c79ef7b40fe76e99cc08	1611228944000000	1611833744000000	1674905744000000	1769513744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x660324f52d44bd04f3811984becd72a87dfbeedd68b83aeb7090444422162486db734e260433812f50f124ff58f5d1e4f9abdb8b64f829fcfa28e08708277757	\\x00800003bf9f7413d03610d6806417ce900e03d20041d8e87fc5a38433566ac5282e9ad8a4ca1803285922846a76351eff9c35b1765ad045e47325e31a99bc80feba164cd17f4b9f90ed0fb717e06dbcd3403e31caa1a704a0c50d7edf8459246f02754ccd588eea3f78816fcddbfa53993fc414a989b09932afe7efe450813ff836152d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8cfc24042992ae5ae02635dfbe9054007d8bef4c94942e50a6d622120465106bf6a4bfc199a3fe64ae7210e41360282c157d8442051f7d13bbf1e0ff94f15104	1628154944000000	1628759744000000	1691831744000000	1786439744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x67f3fddc444f97b024f5e273e167257a9207de153ba40cc1a95c213b0a9d23ac1a8b876ce633c297a320fe7b0fae7b95358b2cca2e059204095a134515bab4ed	\\x00800003bb8a595c99ed305efb9d448c5d72130e08fd17bc05169d0aead58cf7f75ab093f87caeda5c3b44be0a46a10bde3a2a7f6e1593ecbb523971055a68ac508a1ae314650e372fc2b1088179091d0260f416a1aa7349e49d4ac2f3b4597d296d604f5dcd8b5f0a3a47827185f901dbda3d3e71e5e9a9c0d337634bfa331eee7de90d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x267b2c1d0f2f46c6f8c4263c84d9212f4731fb9241d2a97e5c3f95006d7b4aa26874cd724b75aa28bf8cb5a0241d32c7413037a868f3f6dda5b749929d5d090f	1634199944000000	1634804744000000	1697876744000000	1792484744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ceb397a20324429409321f9abdcb4c645e1d38fc1b373431ee97a52c8134c51b6e92dd4121c19380e924958e01a77b4a2d2cba6c6140dca8b1d3b32ba78754e	\\x00800003a8d7a6d5005c2974b9e2b1c784cb719bef99578ccb0e6310405caf93643a93b1e8b01a4159fc30d0a9d5ae07baeb9964dd52cc105b5ecb710707eb184b7ca523103be0a2e4f27644df000d360d786d9b299cbc0fca24ae988795597b65abb2b88438e69ad29add660fa7eb0794c4de4e1e2cf397c642c3729a685c728f04fa51010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4c43f4fac7c95c87819a52e03678179e5603ea1c1fe5f6f36138b60bd51656124042eec6e4b63853c0e7fb349d6e50aa203c713ed4c40db73c6e845b1a70340a	1609415444000000	1610020244000000	1673092244000000	1767700244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6d27f35dee82070d8b1b3f8b35dcda3c565be16f5b7b48512b5cc46761bb4916f43869c2dfe7fb4c894ec873b7dc4c1fdaad756980729bded2fb63bc8a075f6c	\\x00800003d5c18aac23f3be81911eb250a9fdedc84dec4c90a753da8abcc5cf3b0f8bf9af3f40a8d6fe5c8a67fc9075701bb00e85741cff61e2fc6dad894da7f17106f2bfef8483f4977671c8a9a6be67ff604c2a786e3e9ef48d7c9ec9cf9c41ef1444aa02cf07569c7ea229128d1bcaca97bfd392d71476ead5a70309da838a06e57aab010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf334700edec430c08d9d60a5c34483b7804fc6c10a14e6ff284d4538cdba8e1256a0a6ac6b3cffe4c8a1e34fc41711c16d7a0eaa3f995b67db27ba8e20285605	1636617944000000	1637222744000000	1700294744000000	1794902744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d77dc88d024d4bc7cd5c9d9268a837a4d7be830a87685ab2e90ad428cd8ee0d980ea88fe2f22a16f7d1558f44082cd3650bbf851b331ec84308571b673e9b41	\\x00800003d32536715b621554d31a6eeb15fdf3aec26a96b4a03d731bb9070431f6509632107f640b49b43d58116c9c0bf3a3a5878574154769d47f032d076d8625c8c58294fea62ec7767da4a0191fc8b894fd57df79b0053981f0475d0f7344e6987908429f721ab647003c0397da0a1a7ba3e728b87729ca75bf026f86de76107ca5f5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x460fa27e26e27f84a5febdee2e94776e11d5158fa7ebc64659e1b7006bed7b4135e7ae0389bba09cef816285197460ae2af70c359b7ed67969de9882f4d16b09	1611228944000000	1611833744000000	1674905744000000	1769513744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6edbef644f5a0abe10dff01b7130d42dfc2ad28379eec083971db3abe6e61c379c61d4ab4ce2d06aa1e70d2f96b61d6d76bbb381a53294abcda72045eeec0a0b	\\x00800003e688a607a6ffc90f4e350a67ff4c4ec7ef6dcf5a38ce34fe273102c57ddad9168393aec24b2b8c5f7c720f199302c531c9664da16ca7b3d62993e4a951e9875e9a0c5cdbe2560d8d52ba4df584316be10b16e23b0cf3c02327ed1d3ea829d5cec6a76d0c7e339c5ddf94ef248080861c91620fa652fca7640dc598c21636c7f1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbfad987d36c4e9b83ddd397d3fb0e8554b3ef77a373d032a5d50cdf797aa3404717aa65366581d211bc255e9f270b9f9ea1e236a6231df4eb91fc375e1ca4901	1639640444000000	1640245244000000	1703317244000000	1797925244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7013cdc3e6729afe20748434814cdd79aef6df449a9852d942247362652e75241e3c829eb63085eafb7a53688f666aa296d6df4d3ecbeb0f38f49f623b54464e	\\x00800003b2db086e4a7874f3d6d9b9732448fa2917c3f38d781297a56a5dcce2d200ad65515d40f82577dfae214cf00a75f0da720def56be1d9c9de9e6bfd044d8a622c5ff523648d5dc397c926563a4fe104a700d1029d1d0fd645fb88837f4a9a8d2507427c6a3a3bc01ede752938ba8a0e1048fa7edfa12fa4ca46508c23b81721351010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x536d6ff2d1e6ac00b16623f77b3ba3af9694aabe8fb9b1ec4c36b6b18004978a099676e7e0697cad412d69bfd012c9da924668609e437934e2b6674dac139608	1611833444000000	1612438244000000	1675510244000000	1770118244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x723f6ade8d59d0bcd03f62ef6e3b332ae843746586b32fb5e75cc3778d50def3a6842716e4d07e061a9974b702fffd4a8c859928d8ed847fab0556f919a67434	\\x00800003e4c12a2307561bb817409ac74472a62c0e95f60c9a0f6350ca31850143a9f98dd2b922ec71106f7818ab7f7826c6fe5d021353198e7f8f7fd1d64186316c0ffa1ca460a761592d6b9813646d3b975bfd34b9d12e5362e48604c4dfd5ca22b93baff518b52780a1c38567ddf7e4eba196430f7bdea7b450e28c793f04f74c9a3d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x865d3d3a7cce584f565a16abf54679f981582a6950f6d9301f004a7e3b09391d37cecaff822d87d6e0777214d7dae44bf81a20876adf92f5b5595db1b6f3ae02	1608810944000000	1609415744000000	1672487744000000	1767095744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x721be291b3db26d7daff9d89fd43d99b8e8f52311493d35d66e25149918563e1cad393b334328b250faeba9368b93d6d9a86ddbefa4379419fbecdeffacb97c5	\\x00800003c2ffede72769d1d2f2d287212750a01bc908b57dbf27bdbc235ca3e28513be682b2928e83a0ef7cad18fbfad1cffec19236aac2eea00dbfe9a6d3e4669f27a8a360a5203760fff94ddde2a1250697c709ff7701bd0ef570dbbe82d699e7ac06da522d28485c89f9f529a8058504f51fd7d4b20bad9c0b7dba5193b58f7e95329010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xbf51fa905f1df5b09d365aa6236777dc45d2542d7e0e35372360ff4168434d843036027dcd5ad8bd3cabf413b83fd7e961500c8a5aab83ecf9039d1a8b476002	1619087444000000	1619692244000000	1682764244000000	1777372244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x74879bac592cd4f061bc7d9932dcced70a8de034d50da4a29723d360f8b14580ca8e0f8eb7c5d6f64b9b7e99ef8016665b76c8bbb1c246d0e9bdde2e0767c11d	\\x00800003bc71e4c3c6ac17af2c99308fcfdc130ce48c6f5e98056a27a3f5dc2a34be579c24a5ca166719e703efd9f905869a78def6ddd58d854405e1d7d99f7a3ede43da7fc7dbfee7db67e3580095ca84115d9777779fe776f8e6b979d816d86db85d126c8250c3e6f4189eecc7b9c69f53259ba37f33c53b328b00aa2fcb865036ea65010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xde0a8cf5beba15f675b73c629a94a218d71b69b2824a55108220c7d25a3b3dcd4cdbf9707ff7bf4cd5ba6048f0e09724650ac1d93cdc3f90e93a9ff9a7da120e	1636013444000000	1636618244000000	1699690244000000	1794298244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x74a3b770134f83602ea2322e507c723ef139ac016f254cf8eb746feb928f25f2218b42b8090757a9831564eb9ea8e2041c1385210ae55b1ca423fe2df963486c	\\x00800003bdfdc2d6077aa530cdbedd6b6397186bda1a4d8fa57ac01f4ec9cf2e8cabe4c730df8757c188bb28cea7ebbad51a18e415276e5cc0765f78a2d2df6c8b2757a81c61cfc6bc625287d5b5db03840b6e903b57706a7cad62e4a11ea794c5b0d1eb67115a6f02ef179349b82bb67cef36b7adf1aab69e5d7a25354c5ae78e59b141010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8837c1669dedea02013c9462438d435e354a5be60ddc9578bb074eaadeebbbdc5bdd98ba95f7806491c7a3b2e50568a1da27bee94dd3e0c0ebb2a50c9ffdf306	1631177444000000	1631782244000000	1694854244000000	1789462244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b5323549d4bb37cc3077c90d65707a6a64f3f9aad86350315852ae0ca33300ef468e99f1b621bab136dcc8d30d2cf1c4dc2fd3940ac062f4a310c381df74a2c	\\x00800003a3e3ab93285a0436978a8636ef6f0d045c1956e288193c42f06164c51e4401db64a3c90b40a425eff5891642d40c6dd9aecbb5888c7d13fe78a8de39ee3f30cd73a618eaf2173538cd9c3945045b68133fc7dde2c87542a0326fca243ce304104d20385ee6387a372c0c93558510616c5289ba563958b5c4bcf58d3757544bef010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6373189c444522ec10ebe580917192532c1b2063b74c7395113ff25f8c78cdf6b6ef77f71bb865c72dec20315a81aae566d3e8d6a2394fc1326ffc4a9bb3b90a	1639640444000000	1640245244000000	1703317244000000	1797925244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cdf2f1019b1027ab8dd56b0688e5738bb6fe46272fe189b74032feb6b23452154d2c48f008994df7d9b606452129978110176b22773db4ecb7cb58e390ee265	\\x00800003bc57e778323a753f558b8cec8b4b1d01de14ce8747044650c510a5bca78fe5cf43d153f96cb33a6b3e7e688817543aac8f475b704fe60c4dbf270e81a953ccd12e1fff4df50c79d29fd459a7cb226f2c8533cb0577e9a5927a5024014f6db9e8fb0d8e4eff1891cf0e3db9be3440380ef6424afa67de84c721ba4d6ca2e9edbb010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe978072a67964712e66402285eb1d5f519316db0b704c92bcace51abb1df43a7aedcb355fa93f24740ebe800de90e44a632268298650e6fb3ed6aafd001e3c0f	1612437944000000	1613042744000000	1676114744000000	1770722744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7c8f6eea690cdcd501d7c5b23a501d65f8ca8436843c8b8d0cdd5d3c700254c8f846a37597394df9b4209bc513a7939c2ca5dc1a204baf50700e307388b33902	\\x00800003b3ad3834684813a52ebe0c1e4c697b45b9389dda0b065263d07e418c533b4bdf66612b72b82aaf228c6f41bc6264d4b3f3168b9afe4293da6f61440a6cd4d17c2e2c5c6b524e86a6fb13aff369126adcec1aeb4a002fb14a2fdcba9f91bcdf15195e2c00d19e2017f09c64f95f1b5d8aa7a09263929cd6d0317b8fa8e05a9869010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x69635396dea525cbf4a45d9cf343f034eeb4945fa96c23f87e184d468df25ef5e41e2d87823afb23a286557d3a00a46df34172a33b7d8344fe2db1ab89a7a10a	1631781944000000	1632386744000000	1695458744000000	1790066744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e0f454deeb0b443f299ef861eda8ce02d3b3f10ecb8a3918fe2b9c016a48c7384bf192efaa7d64d2b7de2ec6579a84af9968323d11279acd3d29cc1a4422669	\\x00800003c5a9a37620cd7e916bfcda808d9396fba1a91e6f7dd80ee2f27058f510b79cbf9f89a265fd4ad174411460f8fa4dc927b9504c6457fb9eaba1b05930d0776c08e0fd081369faa7707cfe803afca68a453a8e4668a9a95164ee7a373ec85a017569b705d0f1d0c464239fed277af63525b0e14d87d0e10f79e52985944ea6b1c7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7f2df8af92d9ef276c6b4d566435385cc22765e75bf045cc8a1c7c8552ccc373c7d284317312494a035b54d6e36a6c38a4378b45aea0f244e14b3db7d8133206	1629968444000000	1630573244000000	1693645244000000	1788253244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x832f5dd41e8d9f73e94b103ed870aab574f685a5527365e841cbc487fb0024aec363807032a67c466c934945549806acd1dbd212db75e0d5287a754651987281	\\x00800003d1c1ba6ed72c3ab1b10f58dbf58720594a04fe7709a9b52b3409f497a5edcf81568d613921717f75d55c2dc92f5671617fd4f3f279b6b0238a146a2eed057bcbd51d0b106de2ff5da2257ae1d25a2975323ea2bf50cc2c2c4ef96fb5d68f0a35f3ffca55ffb4b656b274a490fca10cd20aad5fdacc6c8647205f7a453fd9341b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x80d86148efc0a7cdbac71096318f270ee9d7f37dd3f77f15fefedbc87176ca26c71e59ffc0a3b1b51f5571efa6811cab93323855f40a45e66fb8bb2f47e20e0a	1636013444000000	1636618244000000	1699690244000000	1794298244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x88c32eb2e0eef8666561e3e1aaede03159102c4b74c8eb2927c11bf855dc3f8b38614f57b7d87a085de73a74028d518e6cb7d5cb2ac25a7d463913cbb1cd0044	\\x00800003a3d7c02a0a287c2cc09c048cfef23da6fc9ec4bb21061afb17359ef73afcdf60d673bf5c9f4a1d6642070a683803e22d418bc6a9af539f831b638e9d552f7dd47dac9918eab8284ead7bf57c1acd94c4539967ad5bf40409475e6fc355df4ffa2522b20bb148a99e34cb3f9fe56251ea70056dc6b553c78b310bd3f92cad59bf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x61cccd8240beb6edc8449a45c14fe2d03ffc98eea686a471225801e9d0966054b6aa26fc4d8bb9e76d992900137d7453884cc036102a0e6c0a99330da3108e0e	1614855944000000	1615460744000000	1678532744000000	1773140744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a6f4c66ec57ccf7d267d02e524245133b62bd9c104026d34502c8a3073b9a798edcf23d8b5e09e408b5cd96e2c6ef9b13a7ca294e32b9a630d4bb33d62ae4ec	\\x00800003e3fc111a3cce400b747898745fd1a390f9cfe4d16117309fb60c71fabfefa01051a8242897950b1ddad866a13f8f5041054665f59799a97ec23edb173c9762055d78efe3d84241b90d9e1f941e8cd4cc2161eee897819476889b876275f181852a73278fd72f00cc27cd977e3bc7a8ff7a11a8584a13b82e7cee33c6ecf65867010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6b0df2a3f0b5186f8190456110c22ce47335f92a4df601bd3a74bdd1e3777d5c1d3977d5e26d28ee00f1d81414a332b54cdcc2b3c2b3a1ae47b0c5bdfd23be01	1615460444000000	1616065244000000	1679137244000000	1773745244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8b337138a51d7575a4a2a820cc78ed461089fb3a5755214463494adcec390df37092479d8f9286f74f8e79bd5284d436893f1963503266067a41bd14a16d6707	\\x00800003bf05d8ebfd88c16cce9028bac382e49a832aff02c5bdb6a2afcdaa22a13eb5b63e3ceb4153e980f6ff426fc72d2d3b42d2cdf878ac7893414f62a90cb50eecaeb555938d2e04797ce7807a39e0819332b96464b274a3b6479c21718328de27f81a21f22fe6cee258c2b449cb8d1f85ee2bb5fa9c8171a8e9c19a47f68f263843010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0821a68ea3dbaa4a3c131b332b2d875c4763592e7fd79ec7e27bddc7cd53f8385d63f83f6255c9a3ad1c7f9f2c67257d1dfa6795e7d03a0ad8ddf2df4abcd206	1617878444000000	1618483244000000	1681555244000000	1776163244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x93f3586f1746b92a941ce7eb57245f55bed5f7df15493cdf2d48de6de4132ebec6e1e059373f688b4a7ec264ef74f7eba91cf7208d8eb7161fed8418dcd2e899	\\x00800003d0f6903492dfe519f778dd96ad38c89f4ada17d933e49b5f98ef5715c7cb74a724362a956185ca32e87105df778cdcd7d091dc69f79a8b98c714ade30f1fe6abfc22f141c3693f603e692084059ea6c71166a9802f4ed6a84bd5e8874a9c47b9a70215f7641391555c6571b09806e338ca962a97936003e3befdbf393de7515d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5a21a2e944423aa49ead4127a414b352a241d749c97bbfc6755fcf5685119a8917a22fd11359d2c58183dbabd07ef2a1624f16e0121e68803862635f18d8b50a	1614251444000000	1614856244000000	1677928244000000	1772536244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x93b79ddbebc81e41cd773a2f75199fe59b17c281a158eef5e44a96cb25af8919a24478e5dfc69103c08fb3af7ccf07dba00a08bc41335a1c88a14a508399a2b5	\\x00800003c6dcecc5a824b88f96df2403c2a6ca26a65b1d5cff453fced51b563ce2525c141fa70083f5ad9813269cc466799f4215462c69d696cafa2f62cf0de1d76701f4cc9099ba583151e3dff4202d2e6248329652b4b34932f74dd93e3f45cce60ce258d21e427577ad4571d76cc811a6b46d3641c44e6f855186f233a6223a2aa0bd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1d3a34aad83483d50e4a6e60895f223b116c395639988de5891712b6d557251d8cc8c6d4436b64455dc89aad1b1e948aeef34e4fa8c8eda4a6fcb4d92e49700f	1637826944000000	1638431744000000	1701503744000000	1796111744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x961bb935e7a338154aaec01b07c3ca1168cbd235bffe4b04f90ef6c780bfdee0265683971be3e8e3e97fd51161d5bccf5c70d3334e888d2cc5f39316910a02d3	\\x00800003baf1acc2b71f87ff1126e3521d48ee4aea4035ad28f852c7f15997181440704059106f09588a039db2c933a1d4334f74ba3edb507cead36fa4638615bd9b62b57b5650a512cfa274f8f82a2204d36a9e9f684df3b010986b1db7a2fe764b81276cd0de22680429bce7d541e47e83d3f6eb2e2fbd0aaa85fc4a346145645457dd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xd412e7cb6398bc4b80b93eb4c6cdbbfc1901429e58bb168ce6d2e4c8277de560c7e5315b2c6a41ff5f5260acf8dc72f23ebd96978a36d806c0d2d331aecec606	1639035944000000	1639640744000000	1702712744000000	1797320744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97efe00145fc45703b97cd0597624e6a3b83e97b6f1ae179a9147b642a06c7b7f75842967feb72d759c24130dc91654d3fffa5f3ecb904a8d7f89bf1bea1af52	\\x00800003f455e899ac7c04c866044ef27faddc36ed5ee4a1b4fa9cd8276b593af459e0af773b4705df6945ea9af712e26422b7017b987bc424ab1283bb92636f25db027f83f5b893b9323dc3f479f7934591abe84fc5f0d1434c92d3ce4782b9de980fc3d6243f8eb07eee87b8c44d9fdf7d7f02803359fe71c735d0cca07a25779ee743010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb33e30c092cf23e8c996edc0a0c06c55072b492cf93d516366d715abd039626e136412a78fbb3da964b779ccb7ec1f480f23efbd664304fb48d2ee02746f0f0e	1613042444000000	1613647244000000	1676719244000000	1771327244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa15f1d53b1ec3b2245e5ed9d3344755a55c8b24c902abb2bb7f4b89cb80a1c9b672eb9ab72a6124298ec714b0041cea951350499c67db7f415906a673b9049b3	\\x00800003cc8c023bf7eb42ef9329399852cd16487aa41f181891820af864a7ec038fcaf607e8025f2e0e1ba4ad121535088a5f5bfbe205f0c76ff621907a3100fd1d31414369175977695d75b41b6cd5d12e8e1116abdcf6389b2e77ae6c995181035faca3ac191ce666414e76dd7c78c59c4074a9f5fab37435d781a97e5b8001cfdc97010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8b5c68822679af985f703ef9aa77ebf40f4c11531d7d656cdd941ccad11d4f1056b425f6de11854507684d92967d861fe17e57980ee3d42b399f71179eef4500	1625132444000000	1625737244000000	1688809244000000	1783417244000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa16bcbed209595ae9480d5c1a78bc251fc810030b3606c3f03f8651c4b8c5e0e9dd96efef5a03c9bc019cf2e2fe140cd28bb03aa0bd28960a3fcee1ee3af50f6	\\x00800003adefe55a1e95fe378d1e8da09b36004209cb5d53cceec02c0afe69616de6ba89fd6a90c74ffe2e3d3e51f44c435bb8067331a7600588461f3d9b29e83b88ba46ca906b9031f9b4a2a17f12a2d2b3f135d0842970dc1772c19bb6f2d7d144410e94fdc059d5be4fa2788895790ada0ab07ed825b874e42f8957de526dbfea6807010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4e27734e7f4bb529dcba4e92fe41d2a3581a8aabf3ddc971f8f7e95ca59c76e0d223b5caa2e6d1219b8aa6bffc47d9bb356f9666289b42d93ffdd6e475bf380d	1633595444000000	1634200244000000	1697272244000000	1791880244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa28fe4c6723ed30c259417e2df26f3282fdd218ca09b25d0b6d44b7a31d0522b104491dc811e67cac0d39993230e81007c6890317d533288853b1bbc971c482b	\\x008000039c21be848b10c6e73691ee5fb174e5cb20db70e4bf7b2edf6275b9515eeb4b70a7a22f1ca178dab986d7ae1946513f0064b77e40562a31b2c4667a92e915b56446a2a41c312c789af2306c94c5fc3eb805d98eb57cb5a5216d095edb7b1779cabb66b03cec02acc8f6c5b062e423cfa63da0c13c414896bed9799af4c1d35ae1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcf7cb4e80e75a732dc4fa3a87eb3f6cd81832a386a54fcb58eedec65cd13964052909505eae63205a3271505f398620790c97c483e474b0b9622754ad6272b01	1634804444000000	1635409244000000	1698481244000000	1793089244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa517a42ccf161d5fd680bf8fe338f4b02aa332e17f0aaa78e79684266fd9e657c565afcb757f6a3ac1e7a76661cbca48bb202da4be24c6f50ba36de3bd40c7d1	\\x00800003b48bf820fd23140a3ba5ee3a865610efd9ce9d978f2fd7cfa68fe1f259d239b7000242c897349a4213cae9443346b230d41f7a254e98d9dbd5ccb94e315362a21649efcff471cc52f69765f214280c48c36d1edf42a9b8ba3fb68fadffead97dc2f916e8e0b877fa07dd0da7150e8af53b78738ab49ab6958153cd1c280204f3010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x55995290af4c30da450851ce45b55fb5d9fe3098645f976846a3c1c3f2ebaddfbcd47b63d5c4cd7a23d023f5ea764bad8ffac897e02bc23939fc2e5c289bb906	1623318944000000	1623923744000000	1686995744000000	1781603744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa89b266400512f69688cf97e1c32a9be80a7167f8c3b97ce667ae627d717970cc9c73f6c144b9be85b0d3b54c8caca731a677546c7b40fdefc2fb7cd5eb6ec8b	\\x00800003b45204ab2378411a8e4f0eea6f06e6791584513a178a1b187c86cf8b58e8718163ffb07c5fb427384836d3880a46e442c9a661298e84cd8b9eb3399bd0a4eda577a93c298e957b8d1655c92456f2cf71ec4f9a1b8931a5f3c292afc5d9702d92b48cefff1edf51632d451c589bdcacda70d04949e9c106a501a12f1708e88635010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe9fe4a09eb4764ae581db4a17a3c0e890a1dc1e0ea9dda5a8733f03f302e5093bdba5552180e631bf178d3292d841e6092f6d56a4dccd314b3952fd345953909	1632990944000000	1633595744000000	1696667744000000	1791275744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa99ffb55105bf0e9da366c44c5b364a4fe9f683b1a4914bfc27b9c6125750b7d9532bfe60805fb0b5972316b176f6f6110e42ada9318cac2756335de00674300	\\x00800003e88a406f74d73d7fb1d75e1f7fdeb27977efe096a2fed77ba387f1ad7b31a6b38717aea33182da0277ed4f4fe5488b29e4657892a1b1c6f7c054daa0666435b7f8af1bb7f7490108dc82915ca265299dadc498f2ffb71a8149cffbcb8afbbf96276b5d044faf1e8f59b81ecde786979a8ab13c91f4dec4b6663f0eea5d8a0f55010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5224fecf3a5c6a6346031a17e864185f705caf8ce3c69751c69609fb1306f31c24610cfc4add684f2aeb3f89c16c981e28d5939cd8f266055cd441b29ac59104	1608810944000000	1609415744000000	1672487744000000	1767095744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xad9b410c6ee814035af42b4520236169fbbcc678a4ef50d081baf0cb1101d641896ebb7ca662485b20e5054d34f811aa31fe301be9334dde146f557500822997	\\x00800003dd98dfbd45703465089d9c7526c5a3bc5db8606c860404861466e307a4e1361901f4cf3f94f0d79406daad828b6ed0dc771ac5f44b83dd5ff424a56e18892c45a876a43565413c09f04ca942abec16c5c9d695ee10a5bc7eab15e7be20689f6859dfb60fdc26e95b65b53bc21144bfad1151ffea8f4c3c5211abb9a01c8bfddd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcbb0464ce0092763d699b8a425a5b92d65724eeb87ddb2169fc6b946d410e52bf234bbc41945b493b3a5162708bbb8ad9a3fa7370f4dcdcecdbfacd746c1e004	1631177444000000	1631782244000000	1694854244000000	1789462244000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xafcf79c40fcd5c52e4554d7af85b85ee7d986f9c22bb0fb1ee87b4bcec937b16e193c12f93865d370384dde444cd7024d0d473ed673ef41eb6bd96d43dc39756	\\x00800003c391e971edf76a5354e2e4f79de9903f1fb7b751a29d13d58d2e8e38077ddf2eef11bbfcdfd0c1551d4feaf85a1b75fb7855db4590bac611e3cca71c499da71b00a7c04ace07ed2a5290b90d6b84f20d591219a6f3f385eb647c739bd1c127dd00bd2a4e618741a153cccc9773c44cffa332dde6d5e02a61b59b8bb0b22aa151010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x233d502863206ce4f560d4f6833e92ef8a5ede9b6f4a0f3aaa5a2a2dea81d68f47349fa0848f30248224bd5daf6b75af0b453cded5846b01ec9b0a9f879e150e	1617878444000000	1618483244000000	1681555244000000	1776163244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaf5b2b234b4852fe8bc17ba04f5d38e517389a95d3bf5ca93a723b931fe22c535befcb40311be27d8efe28e4c267e83f64d46fc2d83055cdbc28532bd86661c5	\\x00800003b7d6625a0783717ad9bae6f448cd230fd50be9a3d7d8bf7963f60fc4dd0e294791070b09ff0c6d128922831b14e4a73f47c37db7fe83d5ec37d5b97c7467d80f84e702532809de389d9c9d3e99c63a1c76d4650e3368b07ac6a5a2a6777704de48819526511c57585b17f378901052a723f69e852be01fedcb7d844cd17fc4cd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6e8061a53707340b83e8b5f90fea168ba0ef5ae1fc9a706e474fa715112a6a9b3fcfcec7e1fb29ed8a83a4e850fbf49d19dbe85510b3b105b5fe4b48b52ca60f	1622714444000000	1623319244000000	1686391244000000	1780999244000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb25760adaee81a940ac0c30c343cebab915dce98cda830f221358cce7be2778358a70a1fa583baac1f4a5ea3ec7926629e49ee355da9573e6ee1048d4ad6eee9	\\x008000039defc0321a1aeff09bbfe95d32b48e351ea07893be19eac4b9c311fb1453424a163f73f423145aa9fcf295db65f87371445314859ae31d31087a5549869c0f41a2e882aac2b792bafc9256f72ac97af796a9df8d3f118ccfafc76ba977812aa1517dd2616c5b577c7ef96f95a487328292f4eabd1c059243df2932cf9ed7bcbf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x0ef65147d72515e023e2e551a6e10179d0cf1e2e96949c97a746a5c099b2d562bd9ff60cc9dfde282c0bc66cd30ff0f781a9dfcadd1b742b61ccaaad86bb8b04	1633595444000000	1634200244000000	1697272244000000	1791880244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb40bcf1e2496cc2f43afd0c7a3ada784688e2f97ee94c3c7e00d5f2805d63f685b928a13b04f7cc7e1aad01d9a459bd8c33124e5d2163391d0e9a263a27f5c95	\\x00800003bbce37cce1cf28147e5eeb6016eba61b7eca0d993fbd50c1540610845bc6794941bfa24ff1e25aa356cfe5504239751932027746bbc7809326985ee0a64c0977d7fda9f75f7b11e5678905439d86df07b1af2bf977e51234d9ce9e3812e99e14a73dc9c4d28e97b19b4c964dd48b69353ac85a6e60cf2827c10871ad9c212431010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x8e2dd7a69263fa0651647dbde909a1a27c6537e8faaa46980458342f3c206fc460005584bbb48042102a83a123c4cc3382cf491956b66802715a91335c1be206	1614855944000000	1615460744000000	1678532744000000	1773140744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbafb81d5d93e7e7118f3fa56d705e29e623fadb7c5f7644caf5c07f6663fd39989949c912e2f3398659e6341dd15ffcc43c06ef17094d1ae6c78a7a43d63c31b	\\x00800003d7b73a41b3cfca1d8d1ecb693de4431783265f09c5777162af343b57c3d9dfa91ae24d5631897d0e0463c9f82931be3ca11407bb32ab8ff154beb16b75730d40330bf66c061071a218d500f54f7a8c3e44484aebc0c59ec86df8c955b566bed7f77e714438ed5c07521e2ee8933bfaffd2687a15cc84e6106587e65ce8c5118d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf5bc44c8a1e99c8ca35d41c42dfb04b38adec803a14f75f035270b29fdd264d1d96408e83a298f6ae0f9085d9de46840f5c9b0a0efe629d8e40f9e1a84c4cf0e	1616669444000000	1617274244000000	1680346244000000	1774954244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe57d00bdc1a43ef9b0dbf4312f700de64cd9563958b9e8284943a9339e3856233d8e2ecebb32e6cf0662175fdb9c73849fe8e7b3f3cbbb626d00ec717c13382	\\x00800003c9e6eb2b3a599379f66681b25608866f78cec162691fea22bc26ebd83ca1297f550347f3888db1ce7b8d9276cc40b88eca64743474b4499969d7ffca09620997adfbe3a9f70b42f3bb3e2c9ecd761ee299e44a6b97443759578fa8e2f8e5e456fcbebc168d70eaff25af7fe95085e2ebe4b9aaeb3f811619c68c5ca33a3795e1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5ac1945d5d75ed2d651ec304794cc7d92100c48ed97eabfe69b9e91da3a643ff5d56a837af17c3c054cac8a40477c9c9e89ac6e73b2db850e4f366804d95600b	1613646944000000	1614251744000000	1677323744000000	1771931744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbf7bfc4645a8b1ac9ed1b298ee9b3fff3bd39a73d515ff25333d08862f4638819b404cac02f0ef933756df094d2c43f6b7c9d8b072183a677e322b38fb25d6dc	\\x00800003a0cf13af20b2f484d26a650919d6232d0a9ce53f689e531c0eaf6cf56752444f8f158535da4e2b2a18ce934ce117df61e3910b9fd2700200eb5ddbc151e8c6b3521b0aa57ebc99f80713867a4155a86b0df88b809b8e64e08dd3d828410bdce3969a9a6bb64d47a8b564461ca16d760803044ab54492206f4cdc0006534b9171010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xcf2eedaa7d6049df6e6b263c2648d7cd11d29529ed3a34516477cd59fd17231742f5087d9d0a1c73a3a6e290d3d2f54ae76530c9eb473738d2eaef492253e10a	1628759444000000	1629364244000000	1692436244000000	1787044244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc05bd55b58a75988e67b593da1fd7116c39c3d6ad3c56f862739bb4ecb5f2d61e363aeac8dee80ff9e5a124d4206ad9970454a9cfe32a9815e5f3696728a3ec7	\\x00800003b541bf0b141419e8b53eb5dfad79b6153d5785a5e897357e0227419a765560bfac652a6348041cf2c163ef8406acb04a91d2ab393937d33c1da0f9a050997c33014a9a183172bf5483694379548b17aa871a833ed650ec0db3c443c233e26750862b247823903a184902ec252b6bd04fe7f83fba87eff0a260a7975dd0725bf7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdb40053355c4bebc7fb136f77518362c9f45bfa279a3e91a6494b2e60c2e0bb0bf0a51fb3cf39e4dfe78cb48d839335f16c7a6f65911b2b5f2d9f7333ff4a30a	1632386444000000	1632991244000000	1696063244000000	1790671244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc27f9125440270212fa6461d7978c5c9ee4afcd3fb378661bd70b7c85e98b6e062ab2d5bb02b54862b5800785cd5ba84c130ad050b08dc3a4ee871df3ebe2e14	\\x00800003bdcebef6e0f2435725735bf720abcaedbb126894236ac119688497acfee92b8c3bc9600ff917ce0a1a94c83d6833c6757748c6d74106b1f31352283d4e1563e4df3284ed76f81ca85b672a2882e4dc15712f5a493980e4644c0e546921dcfa8daa11f2cfd5f969ee1bfb9064cd06030a8d608b53a5b11550f3e64f95ef62c217010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xe61aece092db1bc1dffce9565580b16ce7aa0b9067dcb60c0dce4d03a7451b5f80854421fa8f9aa6deaa8ee65439f86fb6648251fd8496b998e8df89fd610c03	1616064944000000	1616669744000000	1679741744000000	1774349744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc4778d1858b69d51cec570648d3ec99a2adf612dc38897f1d896ffe84e346ebc802ae37b2f62325b999992453577b416b5bb26f11acefb9fdd5bee1622a63943	\\x00800003cb832dea4c0d7ba288d72f5d7534747f674d10600532b53781206624258bc6889f475cbee28ba8bf6f864862f254d344198194ad9d2276ca1a13feb1eb02212c6486a64655c85af2caa2fdbaac3cd7c88010aca863cfb515c5c62ccc1b618842a79b33deb750b17c7be3f3cd404a2b7b47a5387fce0c9e087f8c546948068645010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x6152964a4e6586088632df498156da0e6046d50b8661379a0045b7def7a5773424a7c5b02f6157eb70c22b1b4e0c052ca510ce9b686f2e2f6769f348ca36ad02	1636617944000000	1637222744000000	1700294744000000	1794902744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc5d7f427425207c17187f0fee79b7de3c42f55bd779e1e0a0996d1d4ddb0de719b8763ae3ec90045a60e5abf7b64723ebb67e2575d5cd541d287bd229a99277f	\\x00800003cfc97f4db2254d9ae3e3b2849fb52c50ab4a119a8d3c6f9c4dac5aee0f494067e665c394b1b0d97814cc7a4d8f06e79484530a90020778eca1fe6d7b85e01ff91d34a44abd088ba3d3f4d15a3e255941f103cae87b024391e046c64abb186452cb66baaee9695edffac1b55aa997aa343376e6181cc99249ad9f11921b7436f9010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdd9496238cad5a5ce4c305592404ae95094a5f4547f8725d2479e2c610a1a7ee37de424ad9ba29b62ccaaa3467414be05d665bab5fd45d019d71dbc6ac554e05	1610019944000000	1610624744000000	1673696744000000	1768304744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc53b4dcb42d3167336b59ac62af20c1bd038dd79da69d85c5ee7a649a46e0e04efe02523ce31e7bbc0dfe76ad1915e35e514a2e4cd6fcac9375c1ae73dad0bee	\\x00800003b8745165bbdfe348380487a5a5e4b2f9429f50f154bace1f5f327a244bc64d5517d63d5931a19ffcccc99db00d0ee85756ca489f0a75fa4f4d722b85e13a86874695f7e0ae245e06f915353aca7b06ba0119c58643065e1209d3b5f76bdf6ed4f6e06e2a276711c25b72ac97610455f4aa1f301a98431e812ce53026d1b0086f010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x19c834db3875c4292253b04a43e7fc3a3860f16354b436b7efecc4be87c8acd9d96af33d4f7516ef816edcdce457758ef2201541559985fb5c6455c3178e9b05	1612437944000000	1613042744000000	1676114744000000	1770722744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc5ef48861dc67ec9c5bb469f865770350dd4bc5e16217489652a3a010953ef0357c7cb911d54a98b55b22d72e459c6f3572195a59f1a13a2ff84fbdd25f565d6	\\x00800003af4fd012422520780747936bd57af2de7b9993dc3e50d8dea5eacf93d5997780719e1c0ceed92ed6936e38d3d1cdcfd129f6770f2d617a899db853ab196b8f9c825990902f1572d6dbc87c6907138ecfb40011e4f1070a31ed9de6212bc2d408db756fee6e3e5a6538db4beca937db284c9adc2017755b6ba10f3c5da58e6765010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xb103a271ca2d8dda57aa5aa40c63f68199d4c4d6f945a99135990fe3d2d82bca9c750b4ae115450b79557ab203afbea36ff6e56333ba632ecc3b3c511893500d	1610019944000000	1610624744000000	1673696744000000	1768304744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3dbe7b413558f08f586c7da6e6578d5f1ba6104d9e0e9191a7c5aedb54cd4a424b2ca9aa38f13233dd7b3f4dd673d03572dce4aca06fbf981c52c189654dc91	\\x00800003aee9369a3d4284ce0d73df1f0931ff94502782b9967e28f371af5dadfdcf1c359bc9b092621217082be668a35ed030ae37e198b229dde2fafce98259bcfe0b722381f0a8fd7347b34f4aa43234b25328621087c71169f2ab59983f890df5b93a75430be76bae7f849b5042f1c1a3fc6b3341ffa4dd3cf3bcf29d776cbfdd3b01010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xc483b5d475d2fd74e81060aae5f7d930dbe0b2cb2a65369ed5bfa3216fd7a62b1e8b5fa882b3eb9f5631b8bde48f38a980bccd062b648ea7ed4827a4c06d8b0e	1629363944000000	1629968744000000	1693040744000000	1787648744000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd653d251bb60598f6b9755d93a2c691730c51f94d2cebcf37b72c41f9a84a33133a96edd2a8c9f3418a4b7f1741bb4faf3ba7438f479db1a4b98f3dfe32df466	\\x00800003cfbcc6995be2b686e8020df9f6fea93ca36c67de267d0042882f30ff504febf9cc454e2caee319b80526dc6eb96e35dd910b12b669bd97d892e1911996ff9b65165b8e1da65a75f7b9fce9216a25a9592de45cea3480f3a74c52923b9d6a6c84666bb90f3cb41f54574acfeb6900038be5e4c8375837846bfdfc7812215476e7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x265a3eeeb78f20eefd21f8a4f7907d6f8d3c6cce45ea019afc532cf8f907b8d41308403961ea6fdc009955966a1fdf02eac13f6d2f35ad9c7c2a622b56588609	1628759444000000	1629364244000000	1692436244000000	1787044244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd783cc1f89e022174c77b392eecb72d3596fa8f10087f6c7da37774247e5d75aca6eb3c94417520fc60aa665d6b56a96725ee9148d738c9f9fd02e54da0d4ecd	\\x00800003bd4e95568ae8a678a6fc17442c8316b253ad951557ff0664bc73bc1055c5a97d35dc8524b15b01b7353709eebfba2380d1d2b273fc7e40e0a65f706a4e463e3e2dccef9496bbfedc5b3e31dc361950bb91a315c6b68ce49171aa12e18d40475bb3180b946c57c976c07338f26e237afe6b1210c07709833a9973ee47c6aa4c59010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x65a22bbe3e89911b4ea9f3c80105f2e7ee8b5ec4cdf2412fc45b962a994f10bcae2625554b3fdba8a82e21e79ff4f598336c0542fad5358a3ed908a9e50eaa01	1614855944000000	1615460744000000	1678532744000000	1773140744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7af30f43eeb5b3c426f8c1cedba2869e9691d418ed4097a89a2debc1b8d1f4f136669740cf27e6f1ae4513d97f2b52c74c07fb6f54cd13d3fb0eafae799fc9f	\\x00800003dd88825851b95f71c26782b137683d0ac4b404651cdef914e6f417a063654a46be4cd55fc65c65600b4358f9f773e7649e817bc179f1d18f29347000c774f78445ef31cc7ce2bde189daad2077454efba9179e45c0f71d6cbafb281e5ce2b7fb0c7d3f3fdb25c966327314250d59f0075c42745a9937dd4d9274ec1014658de5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x32c5cada8ba856a30bbbbc5fb3d6ab61bd6a19a3f8286817b273c72b1ed29739f6e2e8bdaf271c1f2af4338fc68944019872c47476ee0ec3b9c9d81b34ecc900	1624527944000000	1625132744000000	1688204744000000	1782812744000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd973e0c19459988d05e4fb198668ab0cd611b6ecbb4007af390c4395ff14837eb5ea7e2733ab0b2cd0e34f91bb7af83e79f3d354b7e670230c216087c5e1f95e	\\x00800003c7a24d14895f7d6f8578d7b37f0a494fa953b4e32edc33265e58c9ef4319741a27b3dfddb0273d8cd1b695b8a43e863b8b853d013433f6b1c977c3a148e187650b39c40d39ce65a11acafea0007659d0792cb7a5ec9d7f3d3e162f93ccf76d895bdbbd9a25097533435838282045db5fa442071891b1f40c924e2cb5a86fe16b010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf8419dcbec53e99eead036901c0ebdbf04de768e0a0bdbe6e8d6d85ddfbfc08dae74c4cc02a3f4dac2db2b5f68450050b18e935d0b06eff891a677187346f20c	1639640444000000	1640245244000000	1703317244000000	1797925244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdda3dd78942970dbfbb0266a5fdb04d59252ff122182ec372856f0c6dd9cf1038eb6a8ffca716bef08009190506c6ea61c1886db274a5d3f1e2216409d11c21d	\\x00800003cb224287301be878fe4be29f37885e4377fe0a75e47680532e6189bf811aac527b85c5e1e5d4d8e2da57d8efe6df1922d9abecfcf64fed312713a995a78b592d3d1c9d27e31a9caca8aceb399f419c3e6d8c9228283f18a8e3547b23eae48ec4c206acff643bc3fd0f68efe06fc306bf587bcea8f60cb1702b9a052ad97a6533010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf3f6c52e6cc029e72fce61a2617b086d74f63c84a85fe9f0a8036c3a32ec7302e4c8a8d3ea957e7d6944c95a978591c1f12794d86d054da0161311c6922da501	1637222444000000	1637827244000000	1700899244000000	1795507244000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe0ef17e202634474776d834cae117b2f8548c2f8e07b3a442b879ed72428e76ad42164b83d95f1e0f83e5397ad90816a08b1c78c4fe45f19e438e8b56c0e57b7	\\x00800003bb04c265e1a89245177e5d90f830c4c4f0ac2965a936ee14cf32411bd5dfc2d08207eb86cf228f9b93bcdb32d8db533acf0bcfda020ff3c4fcbf2cd82dd43bf472b8feeaa5bf280f2ebe1bcba7abb1664c1f168f3eee482c1b886d2e765af9623d087cfe1157a843f125a7b8799e5d2eb1336437c91886a78c494db1f7719caf010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x057e37e6355fa726528c9ca9cd729ddeedbc7f7cc27058b71369628425280939079ef3a597885ca2c359c38150cfd4903b0c9f15884dc4e705127fe055ef2b06	1608810944000000	1609415744000000	1672487744000000	1767095744000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe28bd1f01391944d3cc8987902ff798fb0a8f3ff0ecef3ed2fa763b0923c22b02afe49fdb55bdd3f1593b5826e60cfefab94a6ac4f69f4133176ba625ccc7672	\\x00800003ad7e6debb29866f821b19ccf5fc1706696a179b977e9b48ead12bdf7748c229f55968879e360c79503e30a81737dcceb6d758daba6a5ab2d1a9ac628bbccbd234292786ec51438da510628954cb1ca127c3701159e3c83a52244cdfff4eb7c3a0389554ec83d461f9ab630d26c810c24df710a48179064edff6a00e35dd579b7010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x05eb1a718a67a3429e9b7f95621d55af45f3e890eece0810db3fbcf0161f0526a218ae5dd2a4c5a013d52bccb3de7d58c41d470fa696a6c6f616d13582cf5e0f	1616064944000000	1616669744000000	1679741744000000	1774349744000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe33f8302347c4e015b95196acb0f51f7766a2084a1b7ffe2748e2a4e98409ee88fe7b39c004c04cfb038740c348c167732f1041b43b5c0d58635bbf6f3cde064	\\x00800003c6f275be85146318dc4798fc71bcb459803d3f0018ac05c3eef3fc45cdfec6f091d8014f095be45ed690103b2b31deb58a2d9c280ab2ffdeeb268d11487835d9f953a59fc7a2f452954ca0c85b4d74830de358f4a954c2fdf648d642d80fcb7a68eca7afe94a240042a2bf583bc1dd61a8bad44339c17be5a8d38f4ffe40a103010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xacacbaa8d0462e52dac89228f26a86b27ef4fef269d1f1b02078eb7fa967ec48d2c2c5000106d19f5a9f10cd0da542fa9cd3b2f85eed45dbe062bbc974f86a01	1610019944000000	1610624744000000	1673696744000000	1768304744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe9f36d8790ad239798572d1e3f024305b616d96890aec79d7490e6378343706c018f2e00bcd9254b087b4453c83f69a8ab0fb7006a92efd867187b500e03f38c	\\x00800003a8398d22cb3a636afa2b7ddb10f0266da9c25fb077f8ad8344908f927a6553fdbbbd8e88d93e64d84697be20c22580c810ff6820116d6a28c25342e1f7f4629ed6d64cc061ac3c7bb4729c64bb94e0a24226ad445fd2a9bc79833dde02b0d63d399cf39402c3c171d1fb387f4930c09aaca209494f8e20a014ddd5faa4392405010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1afd481f30681b7b1be98801792dd8a7762ca3dc8689289bfc3ddec0b5885671f0f5608338d4ea102f79fbf2780a3f3c581e7ffa7272fbfe411a3aa59db78a0f	1631177444000000	1631782244000000	1694854244000000	1789462244000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe98f1d2842ee0dc8232761dc3f2bf21466d869d98d5b62b6b2c97f9753ef5cc754dcc17ea5f0d1c599e829f578815f654fbca7813e9a385092dc91adf182e307	\\x00800003cbd9661dacf67da59721a8f5da4c5f6f2b6b33d6392947b994357f16446be9ac77c8485781df61d3a30d57800cd36cbc28c54f90ccd51f2732804dcb575afc652316bec6224eca139400a800441e8e058619b0a562364a09837e56d388db0dbf39d261a11d2c1404c0861d917d20ac68f0ed59d7112b1325de18390932480b33010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x5555edec40565f2fe949806ad9d759a0a6df61a8c4661d401b412ece407655ac8284e0caf0c6a8c60256293bfa99d14651de7c0cca60eebd4f21d01a3b6c7a0a	1616064944000000	1616669744000000	1679741744000000	1774349744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb7f7d766d114621f666a49a774dd332d089aa171a500fe5b192ae92de6d5107df2105af5c2b0a55a0d7f96091f7475b9b763d8aee86b1603fc343cf192c0086	\\x00800003aae8516d781f9ea0a3249d32f3f46624b9a1746237c08ab897779409dfa7081e6982eab7327baa3073cca9a754b3d52a117d785c016f91f97a9970ffbeceb5e2a6c672067c45fd860955875c5b914a15ab8a240868fcb5688ba87795e483d57fc43dbfd67fee9d26b24aa8a90d5600f0db0ca21b585b9a85445630355e87f295010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x68e62fa2cd4b73e78f2aace2da12b740a3d2fbb096db423395ea5b887fe616f34dc8664bd3e65df1cdaa278e4bcf35f447f81ca391322232688954006b6c4401	1628154944000000	1628759744000000	1691831744000000	1786439744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb7b60f66280113ebb0c5f5ce061ec00f495a9bb5bd1e19bc10ccb741cb9c803d9dc813145e1d9bd69873c6b5af02a07c4e99af80520276e9e3afd01fecfddfb	\\x00800003bd514191231e37e22a55ec3aaa127881f9947d8e2d8f18093cbef1fb6885df2d0fb860f30afa02a7bdaf5eb02eb7770b5612dc86ec33651969cd7430fe90c9daac75bc24ec71f1f63e2deaa8dd53f0144d93c7ac5f58372ce915456641fba8cf9c5aeb04bb3abec898e6e73ba61b993d703eb405629318f4a860d722b4896427010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x496e0ec06d2f9d378703ccf80230af04fa548347ff90046c19155ffc2f99fa262e0f04eda3e182d05ee25e868e468583c21ac5875c2276ef69a028e83965cc09	1631781944000000	1632386744000000	1695458744000000	1790066744000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec2f1e05c584ebb4fd4373e67c18efdae23b0ce192d272888fe960605a08b35034ea04229c6243efb2f726e3ecafcc0cebed7fff7a15e15920c5b6bc69f4b820	\\x00800003bc6dc3cf47f0315639d0b8401ab7d47f0aeb1db5020ba7e2d1df35ea9713d0eb9b248e10dce77fec1c1e18c645a3a31050789e8dcc7a3ab1f01bab6358dee247724ed1db53b356732d9e7fc3890257eed96bc94856a95cb06f9ba6ec89abdce5617e2795a54a95a61b9436076e18a84f812c65b9c28a2717d0dfa104a7b5f5c1010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x328b9b217d904bb2c569e301c9b10701f080504ef091999e21dc84046661813b7ae15520784ee882e4255aa483a8602758117e7d4045ccc4482ebfe38af7ea06	1633595444000000	1634200244000000	1697272244000000	1791880244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xecf7810b472e31819f4968423ca6789c77a8c6d6f1ffbdc2fcd473750fe9fe5777527e4b7b6889dead58e80528852a3b8d94a759605ecdc19d26ecd9a8e6b157	\\x00800003d0b8981ab3bc80a2395f9b33daca2b832cd082624a4525768e1c860f2ad77ef39149e518148551e89e36074176ed69a9cf34237e439a1232d5d2b396b72e91812f55fcc40ec75a339ca872360a2a142db8746c250e19efb75c0bf8d3ece4d8af243a2a4a9dc98bf642d915ff2428285d21fd4c15568e20c79d13d1f59b6513d5010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3c6a210dda1093f600f6c4c00f5e8d8524859fd7b1fa33b7fb527826a4176b5c69611df46a4bea2435f8ffbf44922c0ecf3f939a5dab6eb3fdde0b0da429d804	1625736944000000	1626341744000000	1689413744000000	1784021744000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf703a14c117622cfd00e7865aef4601aa449cd41ce373228583f528c03ee2634bba2b599f08976b88e3e9f60dddd60e4950477834324e0cb11666f022b7c4eaf	\\x00800003a3cf59fc499f7597bacb2edd57e97a2500005558e8d886c7fff0c860710c72a4bd30012289f08952ca227ec56df0c6949e75e400acfebff7a467c0da85b41db2d201b3142eab13680eaabb0de7622ec9a598da08dfe0421235429ce81b3941f9a6068228e020c8281c9b6873382ee76ff83bdaa8ed1bc1af9d8083f333ef3a01010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x28c0ddc9b01180e02dcc78fcbfc950b3488fb2e61bb390e7a585cc7ec17d7cc9e1ee5a7797f615bec5eec82c3a6d5b71b84274a1f50af987c4c97213cd462605	1620296444000000	1620901244000000	1683973244000000	1778581244000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf8031e952467c5d63a33d5dca379efd889aa5f7885588b1315e118f5f12de98a2f6d5ca94bb47ffb7adb9aad553962657ddd28172469658e42b6dc8ebc090d67	\\x00800003c62a2e1b209764d70a7a916c3e681de91e56e83e865316221392764df762bcdea5070ee745f514f88d715275bb867a7584069ab17c693816355ee29edfafefdee92aeab5f8c2141d962ea47faa79e7255ad0529d8454f5d56dc8187123ff40b1f883ea63952d0d732fcc13ca3bb5b745c525bb18661b8fe593af9d5c965c7f2d010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x9ee29b404be7af71215f6c1dbcc514ca1f688dfea6789a76ba606a780cce0b50a1d4721cdf178e217de17ded40166af0a47b471cbc11edb8ef3e0d78e6c2f901	1612437944000000	1613042744000000	1676114744000000	1770722744000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfce73d51c7c44f2783a9f8b2d5b1914876345020cebb1078f203e69f41a1d0d45cfc832baa4a90af549061ad1a5959a502c1c8fb5c041a4e31b8ef0563cae14e	\\x00800003e1d4e2b35a73e7d8ce1b14a844d9494e6ddaf757694ce37c8c3141c1e1492a602bfb17f091364b72c3e0f931e80cacc2194ac8133491f9b5395c7048a40314fb627b435329b9c3afc01db8cd5a9bccf9cf25141e5937daac3bba2d761b6c04d4b282386e34aca33211d0732303108f5b32071baf7df3a70e13be4fff620ab945010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa4f31698581886936e21300e95dba42e2023a25dd0e580796c5b3f2b5cf1d64be6a4f8693d8fbc3326a1885d1374e0d14dd7b73eb75390cabc2085dc00098b0c	1638431444000000	1639036244000000	1702108244000000	1796716244000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe6f3b94a556c321122ab5f0c97753820fcc0edf36fc80b3e43ca2fe0a852189b31d0010a6e0afc07a22872c5dc1010b0c8be05f8bd743bba12c265e12159762	\\x00800003cc7687e193aeaf53ca441691599be4ddf775b46c50456177657785fe74df29f7bc020787ea23e53758106c4c43c00397ad7cbf8aede81c8fe0317d65e4f06370ac72ecd1aed9f4f3977eadb95cb74d7117ef47cee7d860d65e94b101cd6b695c2858e11e1ff9515641d4d8022cdabe4abf75d7000df628b3c2ca98ccacf753cd010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x3da7811085615d9c245691a28accdca19fa7f161783920893ef844c20fb02503010d322614de0a45332eb796aa47e813796edba77630bdbd0f096075431edf0b	1636013444000000	1636618244000000	1699690244000000	1794298244000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe7b558be9cb239b99f25255ff4b13331fd1d2b3f747803f00138d045120441a74d2b9bbbd111f03587327e959ea79a1d86d8f1c3e722f529f3cb45278108d4e	\\x00800003acba32b8c99be688cbde796c6ae9ef71fe75916f0d8912989449b3900147e3e27e58bf066309a5eeba961ea38f30cae8b6894ebd0ecef66c992f896442783c8481ce8f38ff9c4180ff5ee4c633af4a1d4f9ec2930b088e36a5597c066176d39822c4df303818d780298660b4b3fe8dfc0528ddd7034320e507712f5db6aa3b77010001	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x032d314e74f2c708e1313e6d6913ef3f3bb2b1d2142c48e735c214aa9c2d9c20210ab2d2d2276a92f6b15504d92442646d79af26d670c84655ad784991de250c	1619691944000000	1620296744000000	1683368744000000	1777976744000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	1	\\xa4194c7dc0f59e8eb652d99dbf008c45022ae793ba7812ccbafe868873b41298cf50a733b2a0abca0e2d2762abeb3ea8e567636818b255e55cc5953e7823ee48	\\x977f90f751dbe1a555ee9233b32bdd8dfdaf3996a274e0b2779cf317536d248a5071c919f95a88df0a31b988baf84848aed945e3ddbd11ab015739021c8f4872	1608206464000000	1608207364000000	0	98000000	\\x622d387b2711bfd23dc10ab6532d911bc852af7b73eba3f493bb4a9f26906b70	\\xfb5b6c476b4011a89173cc141f514b7b4691f48d173a4623113a5e853ce0d7aa	\\x932aefb352b6424c0f0b87fff3b4005fd3d565f3469b137170e910ad6c495b91e5eaa7af457edc8a8be3ecb8eb414b2c5ec706af49899bbd36f758e34b0e6c0d	\\x1af73c93bbd77c01480d5efb4f7abb2f56b794eb038250c0ecb9e86922f4966d	\\x1bad851801000000201f0817f17f0000039e60c756550000f90d0010f17f00007a0d0010f17f0000600d0010f17f0000640d0010f17f0000600b0010f17f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x622d387b2711bfd23dc10ab6532d911bc852af7b73eba3f493bb4a9f26906b70	1	0	1608206464000000	1608206464000000	1608207364000000	1608207364000000	\\xfb5b6c476b4011a89173cc141f514b7b4691f48d173a4623113a5e853ce0d7aa	\\xa4194c7dc0f59e8eb652d99dbf008c45022ae793ba7812ccbafe868873b41298cf50a733b2a0abca0e2d2762abeb3ea8e567636818b255e55cc5953e7823ee48	\\x977f90f751dbe1a555ee9233b32bdd8dfdaf3996a274e0b2779cf317536d248a5071c919f95a88df0a31b988baf84848aed945e3ddbd11ab015739021c8f4872	\\xec5556f0df20d62eaf7927ea7da27e70e4f74e45a27327b264d3024f4e83f6f43ced6db1279a9e891b66d20678c8eb94cc916ad7e440f82c1521a840a06fd307	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"KHQ6003XY5YKD4PCFHQMPW3W588HGV8PV8JQBZJJX8EP95492EVGAEE03K5QX8PPQB4EC3WF5EQZ0H69A5K15N73KK8H12H3Q8B9EPG"}	f	f
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
1	contenttypes	0001_initial	2020-12-17 13:00:45.066616+01
2	auth	0001_initial	2020-12-17 13:00:45.091303+01
3	app	0001_initial	2020-12-17 13:00:45.146874+01
4	contenttypes	0002_remove_content_type_name	2020-12-17 13:00:45.169351+01
5	auth	0002_alter_permission_name_max_length	2020-12-17 13:00:45.17704+01
6	auth	0003_alter_user_email_max_length	2020-12-17 13:00:45.183872+01
7	auth	0004_alter_user_username_opts	2020-12-17 13:00:45.189441+01
8	auth	0005_alter_user_last_login_null	2020-12-17 13:00:45.195234+01
9	auth	0006_require_contenttypes_0002	2020-12-17 13:00:45.196618+01
10	auth	0007_alter_validators_add_error_messages	2020-12-17 13:00:45.202386+01
11	auth	0008_alter_user_username_max_length	2020-12-17 13:00:45.214954+01
12	auth	0009_alter_user_last_name_max_length	2020-12-17 13:00:45.220882+01
13	auth	0010_alter_group_name_max_length	2020-12-17 13:00:45.233428+01
14	auth	0011_update_proxy_permissions	2020-12-17 13:00:45.239808+01
15	auth	0012_alter_user_first_name_max_length	2020-12-17 13:00:45.248452+01
16	sessions	0001_initial	2020-12-17 13:00:45.252933+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
\\xa0d1c0c59e9fbcc735228b5cd498e86d2ccdd300b3c0394c48a5da04698dfe1c	\\x77e8066ee0b4e664c53988d9aac9da57a5cb336a606264b93461a4093824f0887ce429573562b5656f9fc10c5d8df1180e717d24b433ec9f3fb659361b9b2006	1622721044000000	1629978644000000	1632397844000000
\\x4420d3aea739f4d2754bfe7ed1a6bb07d5253541a18555ebf945bf80d80feba3	\\xe38831c48c6482899988e022d3298745af7f0c9cf427164377264b7db91428685f2131aadf635bd28e77d0924c53aa4b817c2cc18f1b77b824d10a4e51be1e01	1615463744000000	1622721344000000	1625140544000000
\\x1af73c93bbd77c01480d5efb4f7abb2f56b794eb038250c0ecb9e86922f4966d	\\xfe379a5d356eadd7ee8d19ad4b2ffe5213e812ff1787bee197554586289082f9633393f9447eb94c4caa740a4e6198915164cfa5c72138a96e34639766395b07	1608206444000000	1615464044000000	1617883244000000
\\x7b9fd1363bef6a0473c4207ea55242b8b679c9b5a75d155f6a54bec5039ac228	\\xa7cfaf62123359268f6c70eee51a7d87e425711ecde27889d5b86452543e40ec70c0b399a294d89682757dadb4954050eeccb333242306a15d654c0952910304	1637235644000000	1644493244000000	1646912444000000
\\xdd7d4878a12be246442e1f5281da3134c9abce5beeeeaec082eeed9713e31e55	\\x73947e87b28fff6fcddda13df732625c67afd98e1e4234bae27ec901e0f9cfbeace01bf677acb4a59d36b7581153db2b54d019ca438ce48457b2076a760e3200	1629978344000000	1637235944000000	1639655144000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x44ccf5a759a3062176a0f6efa394bde0ca1936e68110276f36c203c6a576376b	\\x72aa6b8f737b86fc68a4055b57e13b8ed07748555f1569c9d29c2094d50cabb9bb01e1207b1e0ffcfa9dae93e6da639854cee89f53f0de215538c8a0d9196fa5	\\xa079b3caab87d355ec808d3dc525bef0f1c551980f77f437a66982ab27c754fc504ee779dfd4a7b2971edad0015239951906a0d0ee64b5ced77d78c9ea255f5ad6e9453efff664cf7afde48262d6383ec0b0404e40e69f4bbe8194b16c729b6424ae1698c695a1f62eb298155d2c8d1fa6527ef4ca2e49036bd213ad4793f0d9
2	\\x622d387b2711bfd23dc10ab6532d911bc852af7b73eba3f493bb4a9f26906b70	\\x854104e65d2f9da8e7873a9e92db4a298122ba0263e0c4f20bbc1e30b2db60e3e37ecaf71219d9e12af8267991bec3567cc56fa5cc05aacd6c04b44aee299ee9	\\x292372429ea4e90c8519092b5bf41410dc98b0b6e5dab0c4fc2cdd423cfc21315db1f55cb5e18b5e1d6dc6a044c9c69cc4452481aa1816583826a277efae41b680176f750b0ebf51a574b3933dd52550e23cae928b53f06106538b557004d372cbb6f8e54d3855ec93a7590b11ce21b92ba5738edf015d59f35146c3dbb19b8a
3	\\x00ee687c3956b37030759c6f9061876953846d57941f64da01182332a9c2530a	\\x0ab648489b2c857bea4e9b696644a3c2a09deff78e9c1461ef6b2c911feaf29a8b32a956bc9b2731a4365e44c0e2687c06279a405931cd857c67de7539ce96ee	\\x0f8a790395c722b9b60990c282523479bf798734f34153c2d629ddced77a644773bc45a377e8a17189d1f0d64105e0b022b8a0884be5d42a616ebc6d11fb38b8364598f5eda984522ae8458d198269aa798096f3cd3c939aa873697e0b64c08fc46c4519ee84cd6f2ac90531d6451c871942741dfc32e2512fa9c9544a3568e2
4	\\x37f1b885f143950683a4d8bc3b3295d1711a3c15a241fdadbd3c9aea1953b774	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x7f99cd63d98dfbd40740ecedaf6585375aabcbe0596e428b72a33e17fcf3708d24bf4dfecb1cbae439b45877cecaef734ee676da602e4ab2107a66d7fc883fb0c988dceff9cea577eb541dc5f2fbe6f90c127117cd757aac6245c0d36f063a82c487c77488c9ad6b6d5b2220bd6bb874d780604dd5fc323b0802c7c8d06616b4
5	\\xc7c8944bc0ce9b1528f5a2320f9406ef73baca9e7dff51deb97b1aa31a907866	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x52b4d573fdf956b4f0e0e07cac77ba7c00d6573c0f87d0b9e9faac2df3fc6ff2aa3ce69dab21bc8f229650ecf2cb7733050affd2ee2689e86e54c4e487c92cc9219d1383dc1a6cc64b223725af4772abe07bb7695b9fb562adb5dc2ac24788f32c7d2d53dded55c6ca41e4dd4047c554cc53c8288adb6d08efa21293a95aa7d3
6	\\x3ab3d1b5306d5c56a3ce2deeca760ddc0e1a3fddf5fa29454240342f8f9ad553	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x38293c1702119e85f862f756131285e4b41da03ddb4a599a9d4de68d51647391468f11098ee2c79620fa99c9be67ce7cb70b8657343fe031fdd23516a0cd2a8bb09b2ffdf37ad6cab21f1f5cfc6e3a547b3c90a19dbf73757c661cfab168f3ea70b0bfee6153a86dbb0f5919e98ace1e215fedb6f92cc5561fabdcfa23cd4b8f
7	\\x38f379c81bc25217fa2a5bb3199736843af692c6c0264a39fa4c2e25e0e97ae6	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x24a468cbe83ec9427b3446b4b09318cd5da51041b0d761e8bd31b4aa97bcb2a809733bac9d67ab2b42c5d57db9107aaae9e20634f3de040a75790745d1d66a95048f83e023c4a8cdf46bf7187db8918984680025299debb620ef7f19aa08c20645f3abe3648db589bbe9fa533acee6624cffd48994cd6bb38414540b6d1679f4
8	\\xe9f78a6ca51bf8f53f74df256f1f18aec2d9edf64a182eaa26387e7c05b1fd96	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x142c4eee067c55af0123d36bf6dda5eb23d55fab785f0d7eaaabf0d9b95075db9dcc5c2a5a03ebefd71a0e44c2a3513d7238a0a40fdc623bd20542a9ec298b7b05deebea2235a31589106355a593f627cfc18faa2fdabfc9b128340556fb2afc85394b266b66845e92e90553dd8c68717578a9277af873aedb1c62ed3d729481
9	\\xeafff98c7e0a6b3bf0da860a78a8d54ba51af9804ec8f08999efefbcad742176	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x96d3d43fc899a68921fb784b7edae91d10916f4d107f21a27a1191ade67d6b2a8893400c4caf9fd58f797055cb4fd2fc0d113c1227110ba13993587fea6e7ed084b07cfa0e2c233e820f4094b9b628f76b307ae5e164a21ca98438429a550c6218213e8448ba6f8fc72226dd0b711e2725295e1ce3bb19afd4806ae4ccc89378
10	\\x8a33ed6616f51f2437e478ade72028e19aec86e4bd8d07a0e16de227680afe95	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x52c556d5da245e39505ecfef049ba1050176dfe1ea4b5421a4195211215704b7ff3b56b17c030ee5911a89944c0c260f7f338f29a83f15e278c3f4d1683b7a94d2f81e6dacca3048b4092e1750228401d285c3ccded37173bff39a31fa7d391e9bb593119d2a5c9cae2e7217f3d26123b5d56795449b4a2f8b02123a563d3ed8
11	\\x40a9cb6195507e32e4d8b0898e28fd55cf24021c128c92d48e1431f247afbad6	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\xb4a59ac6e4544f14f4326d07ceb7d6fb867d98d3ba137407287ec1f71543fe26988803b7d7cc872fa9264aedadb571c8e3c0c5050c9346cb76b32b7fc396b59ced4862841d104c72a7eed81ed447595c01c6097c72166a9f664469a9977630d99fca66540fe4de1bbc3025948c152cd72b11510d118a0d40cbc591750e30175d
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x977f90f751dbe1a555ee9233b32bdd8dfdaf3996a274e0b2779cf317536d248a5071c919f95a88df0a31b988baf84848aed945e3ddbd11ab015739021c8f4872	\\x9c6e60007df17d3692cc7c6f4b707c2a11186d16da2575fe52ea1d64948913b70539c01ccb7ea2d6bac8e60f8f2baff044c9516612d4e39cd1108a23ba16975a	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2020.352-01G3REM15RF9T	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230373336343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230373336343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a585a533158544856464754414e46454a3853563641595848515954594543504d39544531434b514b4b5348454d5644344a3535305745393337574e4e32365a313852564b3235545a3134344842505338514858564638484e43304e45453832334a374d475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d3031473352454d313552463954222c2274696d657374616d70223a7b22745f6d73223a313630383230363436343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383231303036343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22584a515747334b374d383348333548395158304e4e524a4751543947425638513245414e324352473236564e504b443036384b30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a44445052485642383038544834424b53474131594d414246443339335834443257583443385248373946384146373054594e30222c226e6f6e6365223a225136523032533136314e5a314447594a36545842314856414e585a525444393530424e5959544b325a535144484a475052575830227d	\\xa4194c7dc0f59e8eb652d99dbf008c45022ae793ba7812ccbafe868873b41298cf50a733b2a0abca0e2d2762abeb3ea8e567636818b255e55cc5953e7823ee48	1608206464000000	1608210064000000	1608207364000000	t	f	taler://fulfillment-success/thank+you	
2	1	2020.352-012BH4ZE47E4J	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230373338303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230373338303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a585a533158544856464754414e46454a3853563641595848515954594543504d39544531434b514b4b5348454d5644344a3535305745393337574e4e32365a313852564b3235545a3134344842505338514858564638484e43304e45453832334a374d475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d3031324248345a45343745344a222c2274696d657374616d70223a7b22745f6d73223a313630383230363438303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383231303038303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22584a515747334b374d383348333548395158304e4e524a4751543947425638513245414e324352473236564e504b443036384b30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a44445052485642383038544834424b53474131594d414246443339335834443257583443385248373946384146373054594e30222c226e6f6e6365223a224d3933304537525750335650464454304156344b4e51543050503244594b32475931514231534838305144314b425353345a5147227d	\\x03ce242b56ac0d54ef4ee82d8a8e4d26215317253c426c3f59cdbb1e1d0bfe73e8eef12a09527ca5578b52bcd5749f6439d4abab4e92d16ea3103a3b743c636b	1608206480000000	1608210080000000	1608207380000000	f	f	taler://fulfillment-success/thank+you	
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
1	1	1608206464000000	\\x622d387b2711bfd23dc10ab6532d911bc852af7b73eba3f493bb4a9f26906b70	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	3	\\x932aefb352b6424c0f0b87fff3b4005fd3d565f3469b137170e910ad6c495b91e5eaa7af457edc8a8be3ecb8eb414b2c5ec706af49899bbd36f758e34b0e6c0d	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xa0d1c0c59e9fbcc735228b5cd498e86d2ccdd300b3c0394c48a5da04698dfe1c	1622721044000000	1629978644000000	1632397844000000	\\x77e8066ee0b4e664c53988d9aac9da57a5cb336a606264b93461a4093824f0887ce429573562b5656f9fc10c5d8df1180e717d24b433ec9f3fb659361b9b2006
2	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x4420d3aea739f4d2754bfe7ed1a6bb07d5253541a18555ebf945bf80d80feba3	1615463744000000	1622721344000000	1625140544000000	\\xe38831c48c6482899988e022d3298745af7f0c9cf427164377264b7db91428685f2131aadf635bd28e77d0924c53aa4b817c2cc18f1b77b824d10a4e51be1e01
3	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x1af73c93bbd77c01480d5efb4f7abb2f56b794eb038250c0ecb9e86922f4966d	1608206444000000	1615464044000000	1617883244000000	\\xfe379a5d356eadd7ee8d19ad4b2ffe5213e812ff1787bee197554586289082f9633393f9447eb94c4caa740a4e6198915164cfa5c72138a96e34639766395b07
4	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\x7b9fd1363bef6a0473c4207ea55242b8b679c9b5a75d155f6a54bec5039ac228	1637235644000000	1644493244000000	1646912444000000	\\xa7cfaf62123359268f6c70eee51a7d87e425711ecde27889d5b86452543e40ec70c0b399a294d89682757dadb4954050eeccb333242306a15d654c0952910304
5	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xdd7d4878a12be246442e1f5281da3134c9abce5beeeeaec082eeed9713e31e55	1629978344000000	1637235944000000	1639655144000000	\\x73947e87b28fff6fcddda13df732625c67afd98e1e4234bae27ec901e0f9cfbeace01bf677acb4a59d36b7581153db2b54d019ca438ce48457b2076a760e3200
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xecafc80e67a207119629bf415ae250be9305ed17139551331011b75b4da03226	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x148da9ca70ea8e3a7b5edf7ec44bcb26eb41724c1ec4251b7f31c2b9fcd2e755c6d2a6325ea42617c0b6016f53b258f0d5e1d5c3282a719d832a98e3d702cb04
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xfb5b6c476b4011a89173cc141f514b7b4691f48d173a4623113a5e853ce0d7aa	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xe4fc91e9d4f8b148f6b789b68edcca13be838ec9d7dfc61082c983a32ffde76b	1
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
2	1	2020.352-012BH4ZE47E4J	\\x7cc3edb3c5d46a71d9da415eb06d30bc	\\x113f48d61a20e16703fed018d4692592fcdea7f2ac5b9f5e22c0e0853d5235a7365758dd1363dc0b3ab15e3eec2fb22e776652d52f3f43f386c710635d6e7d20	1608210080000000	1608206480000000	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630383230373338303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630383230373338303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a585a533158544856464754414e46454a3853563641595848515954594543504d39544531434b514b4b5348454d5644344a3535305745393337574e4e32365a313852564b3235545a3134344842505338514858564638484e43304e45453832334a374d475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032302e3335322d3031324248345a45343745344a222c2274696d657374616d70223a7b22745f6d73223a313630383230363438303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630383231303038303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22584a515747334b374d383348333548395158304e4e524a4751543947425638513245414e324352473236564e504b443036384b30227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225a44445052485642383038544834424b53474131594d414246443339335834443257583443385248373946384146373054594e30227d
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
1	\\x44ccf5a759a3062176a0f6efa394bde0ca1936e68110276f36c203c6a576376b	\\xfa214815c6960531a6d3103bff765a12170993a864e762b131d62a7f668d4ab35ef78b56ddfd9ab43c9f2023ae5be3b9568799cddd22c38903761bb81b0b9509	\\x6cc74509745ba2334dcfceb9c20423c1213142ecb188cc6d0e5976c94176c6fd	2	0	1608206462000000	\\xd47b7cb6539f5afcff0a364ebf1c64dcba7396b3b6c183acb60bd505d5b59d57c79ef369c3e0e0579e7e96c1b295d49cc1061e30ba63ec7feea39911f57c3f45
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
1	\\x37f1b885f143950683a4d8bc3b3295d1711a3c15a241fdadbd3c9aea1953b774	\\x932e9b1ec8a1e071960197145ff797c3643747953e1ac616c87a8ce42da44c4720f5bacc51f776b301aec21d9785ba92306cf3a357701f9880b79366d2444902	\\x5f1af9b985cd620507d3908d1197d1e5bdcf4ca1d689ff3036435bf1d1ea470d	0	10000000	1608811275000000	\\xfde763ed2f6ec9778124fa99fe2e6aa400e8c98a938345d9901daaaa31a3c3322a4d28c6bee26136bf8962e736889ef76b9dcbd374eaeda8303bd2ad02be2832
2	\\xc7c8944bc0ce9b1528f5a2320f9406ef73baca9e7dff51deb97b1aa31a907866	\\x13406b24b56eeb9e7cfb6450c8ea7328a3ba15beb9fe9297a9991512f0e125d2c114cd9557d4c2026e696c9ea1816e8d7b95c6fbab2cc5e69fb8882d50c0b40e	\\xf52adf526505e040a596e971270eace2d532f893fe353f74143ee8b8d6c7d2a1	0	10000000	1608811276000000	\\x425508525dd33ab24ebd0f8af449e737db411f9d72076893292ba0dcf24c8d183bcb3d639850e890e013cd77485414adc364930f11b9e6a1be1cf376efebe241
3	\\x3ab3d1b5306d5c56a3ce2deeca760ddc0e1a3fddf5fa29454240342f8f9ad553	\\x64762b3b37058d669b9fa1531155989450150c08fcad4246a666b764cafbfc00b7e125a29e9b3cf7c79140acabc9521be7972751c3c14075074c6f6fa3612b02	\\x2800bb12514767eb5a62eab01f23e7bf9e520c3c9f34a100e283df98aaae0adb	0	10000000	1608811276000000	\\xfb43e24c2834ca75fb2445f69bd64b8fc5aeea5f6d196152615059b1148faa898c7ed3e0d20efc274473ecb6ac21a1ce06e969a9a82612b6924246e5b1bcc56c
4	\\x38f379c81bc25217fa2a5bb3199736843af692c6c0264a39fa4c2e25e0e97ae6	\\xa40a8e34ce64b0ba2959296523cd42f26986bdf528015e1bfe91a5a2fa4d37a5d1fe76cd38f071ae73d908e14e150e3916d041480ca1b3218f558779ec071f08	\\xc8830bc9f9b29cac64fb4884893be9c15c1069c31297a85dfe25f91dfb750dee	0	10000000	1608811276000000	\\xc42ab31573abfb08206aa7049ae6f4baa28fd2f63cc8615a3e56f6b116c07e81acffcd46f6b3a86ee567c325376c87e8cd6fbcd05f4ae82be82285ca04f0a456
5	\\xe9f78a6ca51bf8f53f74df256f1f18aec2d9edf64a182eaa26387e7c05b1fd96	\\x470f51200206101c6952f3b061285ca8a9bcd1114f486320b357af964b60c18280ff4093452db1379a20bfb52aeb0c748b66464cddff7cbf54faf3fe2de7a50f	\\xe8cbc8af793fdad40174c88c2b380aa12720751c38ecab2caf1e90934e2ede37	0	10000000	1608811277000000	\\xf77d63b74c17bbcbb497d62627eb1162421a1bda9d6808acd16060f9a2268c9ca4e33bd10e058a8d989214a7a092cc732e7f169becfb045a9336f2b1ad6c5d40
6	\\xeafff98c7e0a6b3bf0da860a78a8d54ba51af9804ec8f08999efefbcad742176	\\x1b4c33d08aa4289ed3fcb940f75f8cec802e28b9a8e5077dfc22fabec066b699c121377c93e79d33c385ca6993e7bf383d21bc00585218216f1bf2087015a705	\\xdeff1732fc47919b6f14fff9325b0a6174acf3f3c68a5017b777040d90fac911	0	10000000	1608811277000000	\\x83dae4b47ce281b783de21eb96632a6e2eeff1121999827de2a7c0e53d6739c30a00cb6dc1b1f6bb7415ba0d3de1870a3d2fb0ff8bb51cc907d06884065d8129
7	\\x8a33ed6616f51f2437e478ade72028e19aec86e4bd8d07a0e16de227680afe95	\\x874b1fe05f37069cff556cc2a390b8bc4cbaa54e4ef2d300b02d9278d9a1bff7c7a25a1ded89433ec5b663dc7f821a8426aa62ccdb968dff23e569da064a3609	\\xbe2261c38f45ca5e551ba71758d4bf4a6312e4b4e7aaecca0eecb73a75a2eb81	0	10000000	1608811277000000	\\xe973d2a9aaa08ce4bf9f82cadb9941bf5f2e7d34db874e2bb8ae87b5ce4fe0f8a7dd61a514a8ef038041da6ec6b07c3293a67c3893d3cfe046756d2147091e60
8	\\x40a9cb6195507e32e4d8b0898e28fd55cf24021c128c92d48e1431f247afbad6	\\x61159bb14cc64282bedfbb9ec5a1612c61e4bdae33f01900ce21f709f3ef43b7c92542002514fc8cd15db2e1a0dd05db883f2e86d32a8e8d254b8c74c3ae380f	\\x0a48e06520796fa5a3239d5f3bd2d066db4acf6b085d65eb5a50fb0ed71ee90c	0	10000000	1608811278000000	\\x400ae12f14946baccdb8eb0950657367c53f366522dbfbe66f5bb2bfab298d47946a0389627f46fe712bb6d59a79542136f1ea42d110925039f83c93c6619c80
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	\\x00ee687c3956b37030759c6f9061876953846d57941f64da01182332a9c2530a	\\x64d5b377b251d8ae79a2308fa8b0e9301d523107918003598d66dd491f356ef534c6f9353f15da057dc9eb6e6e432406165bdf61b20154ca694b3a3a1058450c	5	0	1
2	\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	\\x00ee687c3956b37030759c6f9061876953846d57941f64da01182332a9c2530a	\\x03e79da7e0f9daad7fea4c9e55c22fa9c824edde0e600a3ce97587ae3a125f2b68003f49ae8895133307eca1b5320cd396769be398210b9b42e43253d1b5f200	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	0	\\x30b4ce16f9a8ea79aa570b42ce42e5c1dd32c4a1dc4e8af911f4ce7e4b23f084b107abfbde50fd89ebc14b0009848b0a56f52e5c7610d8157f5596ced607130c	\\xe0ef17e202634474776d834cae117b2f8548c2f8e07b3a442b879ed72428e76ad42164b83d95f1e0f83e5397ad90816a08b1c78c4fe45f19e438e8b56c0e57b7	\\x559679f3da1ec395f0952df8bfce43cf53cd584190d1f1788792e61e989929d09465110c363a184f707caacbef3da4d763dec01a3e82546c98fe772be2455565b1bb9c054a635f4f278da4e87ebe9373c8e7be8c850ec5c636fab24e2d9c5aa8ffc2a0699436620c6a4b75c079b614dbe85d31742ffba7609de29c328915c8f7	\\x4fcda594b13c84a7e27b19c5085538f405a32d08b42ac19f00c0e419a4b78420f88ba6cce334b24189a779623f56c8c4c7f10ac98009a6ba4eef7ebb2c0575e0	\\x07ed4016feef7a914be1aed731d2bdf858df4206a1f244e5f6b6e4ef8dc64f5cd2ca38149a77fcab132da456240d1a248130aad291a097a96492b92640fe4ca997338778b116cd517091e742c5208279da13c291037d97eab8d7f6df917227fdd1c29dc505b6f4557b581cb6dd343032731114872a4d8b8e00d4693433bb2ad4
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	1	\\x168b0a638fb8a26b397bf9ef62cdacf7b10040f1c160bd3a1679dc2b2cdcb62fdf28fd21a5b53e2c476c27251f149f832fb69da0d519cf782c5a8d6f7e41100b	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x8d4546ed43cc6fd18dad0ff2fe5dd7166cefc430da2a7f90a9fbcf7a2071dbf4b5ac7097ad144041001d559c7a7077f922d0a4f5cef40e59f595d18400ff92ad739c6825b8f5201e3eef698fb027e865a5544db023fc20076d256a98ff3d416e9c03cbfb3aebc80064807f22213765bba70cda0bbb3b4fdeff90d118726d3148	\\x425508525dd33ab24ebd0f8af449e737db411f9d72076893292ba0dcf24c8d183bcb3d639850e890e013cd77485414adc364930f11b9e6a1be1cf376efebe241	\\xa9730d2be01a7d1e34dea8e3d7d3b5f6404a475d89098cddf4eb204f19347b733abce734c34e0ffc177d399c242299b199fd0376f5105fb15ee6a1317dac1d4faa027b251a3f701dd9b1938c5f6d53b3440c97560a93cdba133471882142a07f6bedd29eca016c9c99e8c8a11e1d2755560b5443c158932de042f7321fb60105
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	2	\\x530572435c4fbd369f79cb2fd553b4a7d536175137bee1c2dca990b021d4bec189c1000c6cebdcf5208ca83982f09a571de5bc63d1e6edd5b079c95ac1c05409	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\xbb0e2177689458a48047f9543eaedc973b9dcb6efcb9f51dbade5d211594656fced2a2d6bb13b93e21bd56d2a03103cfbe430c335701e6e7b0a4a7b69ed431e0f57978cdd27e9963f25906a3dde55b21d6581485d540b19af5e2072cd786497b761e3b99e1f876bcb13bea32e68e44951cf980707f2d0c8f8d57d37ec87a7644	\\xc42ab31573abfb08206aa7049ae6f4baa28fd2f63cc8615a3e56f6b116c07e81acffcd46f6b3a86ee567c325376c87e8cd6fbcd05f4ae82be82285ca04f0a456	\\x9877e6670429e13447c4aa66b130978a16a86e872017c8d698f8cc36b00286f7604728424167e8d0bc4c6ad9cb02ac67ed4c3bbb1097cefecc9eaa7e22262dbcb8460addbf73f14d0372026c35689afb06da8e8502830d43604cf8138942852e820db83b66341f45079629fef910d5673eaf17e74aed8b00f5a90af3ebe04e67
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	3	\\x687a7232710b5e59e77ea7a8219317d8d03d7ab6ee53a033b24d53b4139656776030232633cb834da0264664ba0337ae380babc53dfd446cb1844a3aa4efe808	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\xa0c3f4486bd0f84f3d3539d47df14af42966c7c3cddf27514bc63085ea981857c1c410a43f34135710a877547c4af935258e3672d57a353c8f1ec98015c5658593e6bd7c0408ad2b4d4570d2e8ab32bbe4ca6f1bdc7f8b1e2f72aed3ac31682a78cad02abd8745a1b22b83fbcf07bef286f1f2203773021d304f532439b4552e	\\x400ae12f14946baccdb8eb0950657367c53f366522dbfbe66f5bb2bfab298d47946a0389627f46fe712bb6d59a79542136f1ea42d110925039f83c93c6619c80	\\x4907c3fa05c3df82e6371ca105dd8d8d9fa264f9fbb28fbd9ef43ec0eb1f8ac4003d643f47562459d05e53935de3043f401682e0bf8c66c4259e636f2fbb50ef341b308541991f76cf5f13031272fec426352de2898d705217b4c364c3bda976e83248ff7965799e1850609895ae332c5972e38906983439b037bd704cb1c1a8
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	4	\\x7729baeca8cba451b17c11b44e1173206d3fb6521dc9df6d1d6b06a5d7ad6465954c1834df17eb275ed9c1d193ed736cd17ebc48ccf756d6426a63eae60df900	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x8ac0d170f5dfa6e453963b90cb32a08c8ba3d81e665c92703cb92a9280baffa8920772180a9ecd83cd7de5f256ab2ce30c074bba45427f83b09a76d32b70bd0e25b4b7b907e3803991f7185ba8f921900e3e9f11fc59d57a84fb242d13571fbb99e9c44a8bae04467631a8344531a1ca6bc0bad60d71366098622332cda407fb	\\xf77d63b74c17bbcbb497d62627eb1162421a1bda9d6808acd16060f9a2268c9ca4e33bd10e058a8d989214a7a092cc732e7f169becfb045a9336f2b1ad6c5d40	\\x1378ea7f0fd1853399f803b8c61e1c3e2202003e246c7c26345a4e40032afb5d4cc914a3cb80def4f897a34271b2a7491af0216c5fc640c8dfb81a66c26e2667994ec81aac57c03bcd74d35f5b7364d5be5161489b4fbd8ffa3b2f363f9715c1c196ef19acd2a29b732108d752fc673f8a02d1706f4f99d0c03acfcb0abb1a37
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	5	\\x31be164d463b48d8ca6a694df123f2a291bab9d2c989c08cb9ac94f72d318a0ad899eea4ec9f05fc31af5342505d7ae86f4ffc2b655008253537246d59d1bb0e	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x66a55171e4d826a2e02d9f69504a183cd859f0a50070ada7362bb0e73cdfc638bd094f4bb68d2d54fec6a5825299345c7db3c38dc33dacd67d28c091985162a105eba4c246ce717330ad9bb16a96864394ba9f4680eb7ef9b1db783b0d4f54b889da2ffe9c83e40169d26efa8ea410f06690e84615fcb1807c759c89d3a8dfac	\\xfde763ed2f6ec9778124fa99fe2e6aa400e8c98a938345d9901daaaa31a3c3322a4d28c6bee26136bf8962e736889ef76b9dcbd374eaeda8303bd2ad02be2832	\\xa9017acbe24697c4abe35dfc59f3fe864c5bb6aa6fa06bca86834edd0db82817da020b7855f395512eb2187e737029d1c87aa9c06e563b8978ac9790f50b640ca4027565cd0c02a8780f0f0eb3af893c029af2a18295c6cb57973627eb960629522dc07fcf3a1f36a13f339989c5e8ecde95700efffe202b5875fb9afa9b46a1
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	6	\\x09cd695f13afb09882c975d0ce0a33fff6604babf2256e8e1414730ffaf4ba90cd0813b49de126531e255d78f0b375f348879fd465a2d458297f90a15fedf80f	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x91b4ca199a9c2f27c467375ced54ab46c8d5b41a5057f8307076053866fc56f76e68dd240cc30382caac8581dbfc7cd07cd82a62290fea13a253f86c2f2b0454a2820d5bbc6bcd98090e045f869a1a3401c34b018bf80e25c28ef1544de9f57f0b562a7efb579eb7239bd3b174705e76476a36073d96d9539d30165bbae23dd3	\\xfb43e24c2834ca75fb2445f69bd64b8fc5aeea5f6d196152615059b1148faa898c7ed3e0d20efc274473ecb6ac21a1ce06e969a9a82612b6924246e5b1bcc56c	\\x583f1338f6e45514cba35703f1f2dd5c56f6d0624d1bdb30cf10d15dc6332bde3a40d0b01e37cbe2efe2c5f3cf5a5e45f0bb4dc8b04e9d87604ed5ffd0e3c30a6b3a7f253b25ceb165f763a3b6bcb4b76991243683177a1a5b1b49723354a783b2cf22f341997c39d0048aa7790ff14dcb8d6b8028f7abb43f591b2b39bb66f5
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	7	\\xd8386afb2081ba7ddffa2f18417af50e713b53c2a71b6ad873e86e83f62efdcd7028485478e307caff75a7f6e2a4b97f7c28a170a4ca8ca24abee587536a8b06	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x0189f3edc72a5f50bc316864ce2e922194e1e15b294a95197ba7109c9bd151b5078ac5f247fcc6578d45d4f5f98617b5bb4f72b3891adf00147cd978efd698c8355b2f84ebf69481552b21b486e65adb78e951ad6f48ca34a89b8b8a96b054e27353fa5ffb5551d23f770e156e86a18d8a136d34c8d2674b7833de54ec02717e	\\x83dae4b47ce281b783de21eb96632a6e2eeff1121999827de2a7c0e53d6739c30a00cb6dc1b1f6bb7415ba0d3de1870a3d2fb0ff8bb51cc907d06884065d8129	\\x0d1b6456640f791b3c6bb76b5ef3129f853de23a3cc84518a3d7873f9d4978d40a64d723ded63adbce6bee53464b3d6f691d9775eedb81d88ac1438d58316cba82ea63889492aa86cf284f88b2a53ccf999fa32e8d475c921caffa22566f2503baff287939d28b4cb1db0c615bd76bb895c0d3037204e8304dde59714cdd0e62
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	8	\\x08534f3c79e1d059c268b761951a30a3139c89202f7cbebf6f025289748bd6932388ff67a851585077b8e4ceb951064af00b6b646e658047f4b165401f464a01	\\x724d32fa5d9e79193916920dd399f7e9fac22e62896a67c3d2b5fdec7e304d5db9923e891c715422b0a3597fa99d08b43c74edf4e92bf973650b52004579c735	\\x4e754f6e05096929109173779badce2306f626d1d41482a05d9bef5706fbcd0c3356d79cc85f4b734c1a5ea8d1b8d97b33ff4c02f42d5e5b04bfb99fbcb2dce26ecb419367f555edcacded24cf4783c08f81ba61b5d923b4e279d7fea1af2db782ee8204cf4c70d0f0be02358675f3f42c7f5aae824250e6d279b0f0c9621fb4	\\xe973d2a9aaa08ce4bf9f82cadb9941bf5f2e7d34db874e2bb8ae87b5ce4fe0f8a7dd61a514a8ef038041da6ec6b07c3293a67c3893d3cfe046756d2147091e60	\\x7952947314d26079888164c6433454c25c932d669c15286b25642266af221355901dba52cff0d0b634249a31ec13fbec56ddc44cd3429912edaa8a5dbc1503c25b62d56048773c7d064a81627f02347acec57055d92bc03ffe235247591412e29e13f7f5303239586c25d4bb0a3a3ebc6f87e880cd87516dffc96df9910645da
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	9	\\xa3b4bad2a3f080da2e9b0e6b73e264f323a53d4bfafab035019347c5079822130b6d941ffb36fb03d22b35c9007c5d89b1f5ba4f410eae7c7b107856f70f2e05	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x658b505545b5daed373fab9d9c45972b146c947590f941c0fa0b301d245b2d488b235fc8a3728012c7f6d739e1a0aa3852714bdbcca3d3b2c4398e6651bde046fa629c60d064a0b0dd210a0cdfa8fb6626cd114b1e9c04586a19f50a8f0f669b37708d1fbffb03809d29d46b0d3f9844a144071e197a3ef134f007ce7bcdbfcf	\\x2c7461036eb8da5c8ae5e031f7f9686c5743e2e8be4bb1d13c02f61c8b1d6c45cfcaa4845ec3dd3c43f7b0a1d63a9338efa3faad5d14594df13b3005e133c49a	\\x1dce2bde7c64847b1924c997592c4517789e331f944a686e43f0428cd6635b5ed66ddbc19ae85461eb90e2d3bfe1a96bf27f4c679cdb9e0854592e0226127e82c078f04412c9cbeb8cef95e51c3e6d888594fbb365658006076a256086de229dce81a2a37d62698df313ab3cb0d99386b2d9a922171d189afa2bd257c1933fc6
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	10	\\xac77f19d139f1836c18d689d542c6bef6015cf7198ad5bdebe1911c3985105adfd3944c2ddb4d4ed4c9d882b0221cb3dd2fb8a99b348c67f8f021f2b605b3501	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x2ab9042c2c9c085e5bc4a5538f06c21e2d86f99ea801c38b211df0aa0f3b5e3ac6b8098ee1b374de44f2292a201bfcc185d75dce1b56b6026fc57f9fe76e0462871a1a80ca18c047a623537cadf46d122bfdd34bb7a9a6f0f123487bffe92d4affa4019e9b5830a7f73e16b25c5bbb00956e202b33850fd19815b90518d55a9b	\\xf77fa315437fbb4f12963fbf6599bf7cdbdc06e23f2fa262f90db979b45ef116b2234fb887d565afa36afdb15fbe61adfbbe3590f92e6cd5db6d5816bcd00b6e	\\x177888a78335d256b9adc51c2af357ee6745689dd516492790100b48cf4270d7f1204b9606ea2905415576e2eaf0ac5ca2515f8c054b279707261d2e5a7fc318bfea731322c56f2468719a2e6a09fceb8fd1149d8cdf0bdc7658ca3c412aba34cf4a053c439488a6d666f91cfa029746e525d9ec4a76178f6bc6a2b6b5c998ae
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	11	\\x474940b5324ff8bc84290292aa9c40655c71113533e4e793515241e239ae6bfac3046435ff58eeff55a2a089b9a9103f8587d2d169669b9b9d4e0e4e3a589f05	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x08a8505bb438ec721029bb07b9a87d22612c91354af8173c8d8de0449e1624d62832c6419d401571262e006f7d4103ab12b43dce3a6878455aa8f4ea890941151f18a932a2f726dc383e448fd42703fdeece1fb35bd947dd6efc6b90645520fcfff2440e4016365342e4d54dade2e0bd0a09e087e95f091d891d4ac6473789db	\\xcb64feeb4d31805d954eeecc6472e390b8ba4b6ae20cc93ab2327489e95d83130d1e485c3b2e9ea06fd88e1a1bcca337c1fde6a650bd2c7c8a5ab6c37d867532	\\x9e8064bfc020ba6c7e60021872d54d6c5332fce8cfa719971678dd7d71a6d5b402b3bc8d6c2ac70e7375efba4c38ce34a143b13666e3cc8f54a968d3bcbbec53d0b3f6e002387b4fb9ea53e9e20e6289bd856e483b982ce33b47dea43ed3dff24a18c8e0cd4e7a51199a453de7e46b5d2cd1035523abeedb6550d341232ee35f
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	0	\\x7d2352a1c0fc96eb7af8966d9b332b4a8850f9617f294f3f3e9149a4391ac88d969cfbaa9ce1ba9110f452441a82344f46c479fe471bd311b4812697e0943e07	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x01316f9b1431448bbb29d9854afc599026474c49c25544b7f4ae53ad9f104afe349c30a1e4ac540f9e3e6690e57e41cf415ae552fe63b8b318f0eed7725ed1af300d7c260300207532abdbc93a758f779e3b0aef6ece9104338744bbaefd8ca16837eee1773eeb1e9dee5c91398bfdf4ffa1c906338319577be930eaca9e1b68	\\xba1e386eacd850e06e153c8a3593ce23fcb035c866b157aaf405163c1b167d5e6cf61b568177cf9c188fd035684e4a385c794f69a1244b52b27c2cf3bcc9bf43	\\x4d6f6fb5fdad50304c9ca55860a30b95cdd74bb800d6b6b7c76506c5484fe8f17d9de1eecfca0948c971a1d24a538d29ff09110a2f514290f4eadac375f7a2a083d72b450aff73726587f3bc812b0093a65c830b0946f5fd8306d4199e67feabca9d3b8f101920e67d7cc566cf38b11a7005b779180a5e0f4bc0f8f5634867de
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	1	\\x9ce30afdd470db174bdb6d19d5dfa6d29037aeb60d1f198ed047fa1436d1cf447981e45aaae7ce2da46dd0fdc20b5d10611d41b9f34ffd0525a82b0028ad5f07	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x8a23a48ac574447a50b5ad7022ab623a474b7675200263b2ec1d3e31b2c8c8f79a468a1504bf520f7e56cb59a584371fae11d5af531fa84cc57dad037f337d4085f293906113eb6cf880783a3b758d5cc7435da4575ee72cd17c166ea67b8e401fbc143f0090b1b83762baee4801e2aa23dc70885cac3208b44e47bfe1d5babf	\\x9b92dbc3ab5fe66e21b1f12cc0f80b434023d6ff2ac0e02ef2066030154644106c0a301cda895d0fea84308d9eaa46e708bed6fd4db693dc221958effde2f1e5	\\x2ead8a7c53f2e34d1dab91aae192a06b269c5413e42e759346a93ef727bcdf54e237838f4ab5cf1ce8f0cacb5133ef053eafc8744b7de3236a6d3fcaed0d94b7e86514a86afa659673909390bc0a709581f769539bd1e7dddd137bb7572fdd32e6815b2db8e287f5a9ea4400a1460fb1cb1b80c9d91aa4c1f2d8d215ec2c0e42
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	2	\\xe620ddc473d2a3258a6e6a4c4671e938b165c5e162ace1c741fa59afcdd01da087fa423ef111651b65149da22a0f19d3d66a6499ec96bac86706b8610b536a0e	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x2b45608e3604a8180a4878fabd45d800f11a607da66971af68ff610aee4120e355790f6df1a38b2a12ab48dc90cc3ebc9044cb89c2186772e9a85c36690368355744e3ee6cb574aadfff39aa2ecfdf9578fae2278f3cb3bc595c6b7e075c13c0568cf07189ac13bde124341a6f41a1e8cd78bbc29a4c6a604d848111ee63d7d1	\\x5c1aea884829cc2ad3d5121ee178d6d3b3b87efd0e3ce3a5f898d9d90c776127af6b40251cadae1450850b04e69db16fc62f551894b5bce0ea65f7e31a9822e4	\\x6d3e4983fd7c9ca76cda12251ed42e82bb01fbb6e892a55632b9b2e5fed31dd3588d817d2e292ea47c91d183b7b4b19ae01e3e5429118ca596068149d12ae6459b3a3cdf5f657781e87744c98b0ca22c39b62a8f3aaf684d14de006612c4851d4ab8b2ae86251a37024f93f45864dc1a850d81a23d2131deec101441b2961c6d
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	3	\\x96e5998905466cb58fd6feedb2929403010cf77f2dc9469a84e532307a48abbc06ff14a26e12e822ae6d23c4db9aff7e82ac25d53cf491f0114aed878960cf0d	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x1a8cb29e8322af5933f80c8673872b9ea843327c6c657cf9b46729988900ed53bc5b47f65b056f08061d8efbb6d23c798cb737841dd58c09f5e73db86dfdf3b6c596175ea375e64652959526b1e664be64d67c531bf3d7a84f4045bd32997f653d110053e08502cae29197c4a67c7f66d5ffb90f26e073639edb990b2a46e309	\\xf3e5a8de24cf9a15867722df41c119ead9b0efe493cb817d02871b4b90dbc37f8534772897d71183accf004301d30cda886d3831a78612a63bd463aeccac49bb	\\x37010e250c3028cb516740137958cd28b102fce9fe9785bbb391bcbed614ad88dd3eaf9b073ad688dbf8bcc904a7345272960e092fbc7329a3b6a4a9e45edc42694268d68d7506f519b51225256009eb0e725844c597e2f162e78a0aed7b192fdbed419df11a730f2cb2d851da5979087d5b04a2570fe606e06e967ac06be46c
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	4	\\x9b1f1d497eb63bcf4163653367b328d169eda3d4e83195182ca95f432dc549777b0c570c9620fdaf4847e68fa6535fe11be4c639ca0497fdfa9f50e3f5e0d70f	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x8e68cd59c84e22a7ff611033504f355273c3b675f1902d7c77f2b8f061452dd4f6e328c7cf04ced6299ad87d2e089d14ece2a8fed2248a7dcbfd1bc01789345b72e2eff93eec41b06cae6532cd8781405bd0aae63e84fee9da89e1080c88b5a1305a1096af7404a7fda4e5b2c0fa67d9d1ed356dc922bc75a193c677799f2ce5	\\x7398734c694ceea4901381733580557d77ad5f0751862bf00d14cbfbb21610b66b2e15e264e4b884cfeffacf6988d0095c4dcfed4e96c39f540d401bb79d69ca	\\x7847236095e68aeb9ffea28e4d1e00a2e92de52ac46de5d6c961546744f7636012d91f1f0f1c99fac819af7831743f28da4f4c36ca3d656452ec2792c5519362829ebaa4fbca7e6ebe8660714349975f843c269450e5b02a871b8dce48cab5fdf87943f1f373a77707b24a75bcc042acfa21f6a6fdc946b05462b2b30b1af1a3
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	5	\\x3c84a121bd4e0467ecc1a0f4907338eeb90b010ac1f009ea2984bb6f5f4bbb81bc49b5d018b00497f253cf24c4d70538477572d2d2454244ffcc89bcb2d23a0f	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x8691334a2a315b02a75f4a063f176befef0f8475f2701b4d689c89e13f593bf1e7e358c7cbd9a0c21b135cd74a37b74217d7c1accf9f29c49123d6c4373a716d2cf927b06c6649a355aa1dc5009196f1f8632e468e9b6a354e675beac48a543726ac9f903cecbbce24b7fd33900f69bbd2a07b0bb7f0789ba6c2393c75d248a9	\\x42f9abe880da78b1c3c85b1d3ece227c17bd6c6cf5af7c26c1a78965cc1e0dac2805369f3d379be7f93a7dda8799c8710891039e42555f998599803facf411d5	\\x4ca29258fb0275977066b0222a9103c2e9a4a518a18323b21d66de1cd943cdfc7d9daf34d3bdbc9c94d10f75200bf32654d00637edb3cff7dbac117fa310c1050cd8938064e5e7cd0a09289b7b7673a8bd2c014e1967fe552cf7ae5e5fafb10323a449e1017191bc358d37001ec73d48c70d464787ec3616fd45929ca9fa0efd
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	6	\\x1d5e1a01abfa95979877f6512d0949652816a1ac457b19963282fe34898b2ecade371019e558696b158564c9c5eb42edcccfec9f67a39d80b512c5aa04e35d0d	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x26455a622524bd5692785c998491cbbdc9456d2ad99ec7905088ba6bb1af3714ff9b43ae2e66d8c6790ad46a9def885a9c120274f2c9aa30476b030b11b3503d2563263c64ea221819b9dd739f631d6125e29ae87e52ec1aa9f8bbe8e5c21899100787b12b1219032ec0e596ddac95c7c9d155a12033ac9d3761b13fe719225c	\\x687b83c5538d32464257b4e083301361e875ade9e3dbe7b7480623169703b6b00c761799e2198ff18ced8cac5c5fc929c690563d41d411fa2ded6dac7dd2184c	\\xa0c4c6224e3fd3859b80fce4c5e85a001514b1a9ca3de7f630afa157714e06dbf1bbc6f3df93c757810409796ffc76cbfe7ba28a1e062210478cfe92c95e73e95046307ca6aaaa2e7c0aaf429c0cf977f672e585e5b414eb74376d59ebcd3b4ec8ac408763b98c8607639e6c31e0f0e88a571b421623e343266683a81bfdd988
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	7	\\x02cbb326a69453d1a055c6c5cd820fe6d968c01db584d2b45172f41f73db75fd58ce52b5d1d0406a933d7f551977dd58fd53608108d6bdf34da6f6d5f54f670a	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\xb40ca66f20761490a1bd75ebadac00c5d8a6012fbe9b1e949e3b7a37a92c756bb78f9f531348c5f2ebe61975a464a07a3f0330fc393ba74a1cb3b877d02cbe77b73d65bbc742b843baff52eaead60f44efb5c43aad298e190f4e5a0baaf64f11a46e6b01618632a7e40e99a9a208f2cb12f84a5fa1ef7c81f46e6f6f4aef674f	\\x64b4665b32c0555da783df5d935ea27d7f874b4cda1ee33cf66e94861d7fbf1e5d898a2577beaf1ae0acae01c6f8a700bdb1523900694862488744e832c5a8fd	\\x871be51adbc3e371db9b88b6a9774213aa6da7b048e5b4357ee4c7b22be5e262ee84cfe8d70c4fc88e8009b9ce0ebf5e444b307de59dee479990895b8eaeac6297b3d7e3335874bf7dc7f6473a1208b1d641728449a8c5194e35fe9a22f613fe6265953b23a632868062d6a136f4eefdac2601ea8d5db39a519ef8dc82567be8
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	8	\\xb584b6a8faa9871a370a505b9518256740ab59c44ea906e37b926791671357d23b939628c8aee6fbc32340c5170a9480226685610fd02f88f2ab02127ec9f008	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x30a06e623c74be6c7048ece238cd1d938b47aff2c59fe972fe18d757155741643b12154ea725c18f1932027b4a0f97a3c6286d87af88123a50f60e65b0e00a7ff309d0f29dd51a43658fa6c6171f60c7fd6665bbb3bed47514c4e5cd4371eae9438fdcebd668dd94427f8cb59ceed2287457f2a4aba43c0c83d8c3d362c38df9	\\xe2a77cd2b28c6b4a9e4ace116bb79fc79b6e903628b26eb64b7923aed85bcc61479cf948c866f85cd3d931010362b08433665aaf720d92acc313c25561bacb85	\\x6617cd2f83c9371c7e00ff0c8367f2501e9836f8832453ec4705f3e0b70d34a4ef247f0bea1ffacba18450ba666ed712a8baab8e422820062df926175434ce33049cf1bab753dd6c7d750018ba2f3ada43b781f5603d7d84de25434540ff4daebeae3b30e3097e31ef6aceb45af7e2eba6ea01486b755b517210ad049546d26e
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	9	\\x0bb425e777eaa2803871b7c3518c469323b9d988035ec263267988fd68ec7567eb1570cd6733da22aaac5928adc3dbf2ddbf12281263b6d351aae201ab045a06	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x90d5face9f1fbbe201e03be776bc12c9083344f952b2cd91f8c46f09ea23c1924006ba82813de444d3408ef3cbe7d29ab8ff30d9a01be194b3f6dd6654d25a3d20f63748251ee5bab1e71f9d68ba0f6d04e189d43e667e76f4f576bcbe850ee93d8d85a86692b13cad9beb06dbb32889da57972c5abba7223ffbe974cf1416fb	\\x13fe85f53fcbe6d906195c886654efda7d68fcd1d9595d907c2f9ee59605a648728021e015eb95c46336d49f9630d3c332b9f15e5b3fb39a8d0eff2c9f629fba	\\x4e37417fd2bb63b8f803e6c1b05e56b5572cb5e47c6228bafe8be33acc0d8958617c467240ef5b4795a396a0c940ef92e1f16cfb5c432e532135ff69349b6c08f5003598c1031e21678e6c71064483744b27ef9ac0f5640e7a89fa3eb6313378f3df4e2afe7f6879792684a95fefa0b0986be0cea675ab69f1006180ba5c01c5
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	10	\\x8047a93beb8c80a6b540373e40aab572b9023d0ce86314ddeedcc76e4534aa96c9346292c7b337efd89c26184546091861450bb6a88b3f3a315bacf6c438c600	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x0dff9f2b372028ce7f092afa9b9c0c5ea8880f4264589d437d685116aea217fd65d11d3cfb1ab0ca79fa5322a3ce2334ad1232e59f09b86df1e785e2c18b95eabd233951519f66c358520c0fc0bd8f8ecca4d0a423f59413371e87f9965f91f78d3565d9e7ba2bbb27ca5198082ba7f150c321b4f8ce66c1dfd99433854f46a0	\\x49568cbec6feabab5ca338de245d3865fc3356924443adf4cff462ced8c30133ac0cd51866a9b25ec02c3431c54479a6c8a0047610c52073b73d069dda2ce878	\\x662460201d48411e74fe343c0601e3c3efa28eca2911becc6edfcbab91db60fda22681c2efeeadd58c08a74d699e6df19b2ee3d6e478cb93b7e040b2829171800ef0f1b802a44e93f5c381e9679c4e5f3c4c23bfc5671b9a19e775b6f4f02f122d8d65cdc3dc890997e76732bb61deb566e8eda15b5d0862f4502da648ede4d6
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	11	\\xdf37ad0dca3fa01d7fef4f69111b250cf380a0c9e6581e4554706cb940f6c7812a56c2c8f8229d6a78e0a6cb37d611dea35eb6ff7663e0628cfe0af28d99e105	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x9c7fa47171ed35da50732ab5b19a1e49a422beab5053cb59fd15f7abf4b4d88bfca91ba112d71ee8f1ef19316f2c00fb85355c6812c7d92a378383dfdb6b49f8a1e949f1fb5dec3740873b2d0630c8cdcae75f453fd57c4acdb6d0111ac82d0d95513c86b73244189b7de82f41944415e9bda57386ea6b149bbd8b9f3afedd63	\\x8920d7fa542256fe53d7af6973305f60574afa603d003fe36454ae2e0b64ce9e2b776e1e7a33d70bdd3bd2804258f77361355f6dbe5bbbb8b60a755acc962701	\\x3d6e5780dc877ad5969c51937967efe7e185055a04f6c7bb945967cd9d483c65cdd5f7ea474ca8c1296f0aa7d529ff72c2f590ac5a275b46e630edd138a490e0fbbf68d98f03f95d42db89785188430ad9002c83dc718abee8ca96d1ac07c970cd7a418cefae6237e5095602e31aa02cfd1b332a578fb2a75c45c935ca6dc301
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	12	\\xe4e0350d28147af503a0abc616e1fc634802e4f09927e4789389207eddaeb0581059d2c2f73e72fb7fa980b2ec83f53262b03f3859fc53ff08c278cd4e302008	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x2650216656fd21bbc0172bc928304b7a73e250f70b78c6c81828691e5b2c9837412523f39ed93d2878462bcf19eb2733b56a66cbe07eade72e0bc37fa5b9db20459af7a2ae2096870c79f78fe4ec2c69f42c2af5073b6ca687d108bbcf8ece0dc2b9de98bf971d76c5a8daf07a461c408b80a591d6177d9c6bcc48ecc0519daa	\\xdd93aaa2ebe060ff986d2070cd758901d32a987b4d761cd2650207e83ba5a4f692938e8d1d4007a48de7d5fdf467a6835c2df5cf9fe6cf04691de4046352b7b8	\\x339dd82900f700cc61cb2b62af89c373f3875604945e9d66ba039ac0dc2e66b54f343fef342018e6b13bb52ddb0f37345949dfdaec753ddeaf8c4cd9c7a91b0790eaa3d9bfcdf1aabbf221757591439e89825791b8299ec8b41e8b8e041ee1db84032db8bfba7e9599f122f88902bcf59ca437cf442f7e91904049674fd8b4a4
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	13	\\x01ce6e400f52ad433ac15fd24d97a14d41ad40e07d97a3bb771e25a9e71f4c18291a89efb2f5d42c40522f150eef37927fc98e61a786f9bd1562e94bb626ed0a	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x878e375a0e18b558c9ba4a3c6457468bb8f9acbeeaa00de4e53ee95570a20fcdec276690070dc53849b8ef6586032e67862626c4f2bce0bee690dd8f7eba23ee49bf2f4fc528f8b9d42028a85951948a63d96d050afc95875a5377003c016f6f39671851b2344038a62ff0153503b34365f8c0c24994e7ed2efdf48193491974	\\x28c04ef4c0c0aef46351966c4a3b58d16cf8ad3fadf7174e45cf5e4ca9255b9f0f357fecc897e34c9b37c4d158f96e39a736764ddef2e353ee2c32282e68aa0c	\\x1bdb5becdcacb306d8cf364e69b30d326ae759123f622301fcbf23b77820236043e8f894ca0c622a22d9027cd122629bfd1fdd5cc5fbb0a59d76496a17cba9abb6abd1e1c201f4de87e21c57388c55b69036dc796de110a21a104b0013e22556377381c5117dd9be4841563d85561312d1587dd6b993eb2c9f7c74595c5a1561
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	14	\\xec121b6f376ab13e59d717ef281551e82df7c0a517a4f5a6a854dffd04499cf1004cfb833f952b42c0c77465db94515a91676ebaf92d020718cd37af72807d05	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x0773b3cbd4785a63832a8cbd93f14c93a92de39318647eb15c710be42f2dbcb1d149028b51c8378c3759df4233de28de5271e53a99285e12567e199ec29b1d35b999b7edbf25da7a3a270eda98ed9e2584c9d9f907b6efcfacc8fea128db7543a610915c8678e4c518e21edb5a080a457678363b7ffb23a63c60e2a0dcca7ed5	\\xff26329a4ae6f659f7002d46c0c76296c48d20be7fc2c370980ed299f46c604ee34f6a70d067e1798aad0e2f16b2f5aa3bf25f7fafeb1be45fc2a9116ab3dff8	\\x1bf4b992d9c6688057599a3dc712bc3b36162747c4de4cc2210a177653dc58c19815dcbc32b956978101bd4d66aa3083fc3f484d3d9832c18f5900ad58e31783932798f197cf67653c236b00df1e90dfdacd0fc8994c1ff4421be44c6deecaa40c66727518c152a3e3ef95f8720a49b9da9158c75d0822e414d76486ddbfe3f8
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	15	\\xfed2bcde93d548e4c1a5578ae2e22f59dfe7c2fcb84864f9064b7cde8bc5c24f7c3fcf18b6a147598ff9beed0a38670f906a053b88e02921c106aab5f1ba010f	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x7a5f96b8f334b7877e8e561d8cf4cb5cfa4f65c02c0255ae8fa64f03f6c4555f276959da27583ea528d0b652a7cf71aaa8669d550cd6845602441d9f70f1136683da539e7fe70ca0f419911443d7df3a5c0049ca28f1c81963bee940e548a01d5209df9bfec8a6f3a2ac29145fbecb63ac7c2b7f9ca66b597dbdbe437a052d00	\\x15853bec98b2814ea7ab5cb19f95f173b28b284fca3ea9fafc394ffdb5ef8b70cbe7b932ab15e65bc61f841b4c3d667149daf497ab550f5568af6054e3244390	\\x8af71b64e3603c7700eaed90ad3fe0959090abff28b005592de361844aa448d1fc84456d1331a7cd71a5fb3c206341f66206699362b7599e64564d83d85d212354933d769c457b73e67bf32f162e1d69ba541c5ea5e1438713db0cce0e57143b3bdba54d6f9ce012fe183ad0ade8ca3cccfb2f4747b2ad116d68210fbc735660
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	16	\\xe68ed51b0a7d6587c8d9108c3443a4ed1b21e07951c92353919737fc6243e523083e66d34d52f9f85a1387a97e3ee3aff96dcbfc2b1fa71e82346b691915c70e	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x82b607e7c36c0e998e3c3d95417eec21ee8059def3b5bb99174eeabde05d3fe9b2f6a37dbec270ba0fe9d114803a84ffbe69baa9542ff342a6ce86b484644d262346a3532b6ae523cb7226bc933c8eb4877218871f032327417560f1948fdf29289b37bb506f6f75ab9ce97abee75fd49c96cb57524d67da55491b2917fbdb51	\\xca16051b4f3aa8153af1b38dda6ab0a1209cb3ff7689471013e762c6cea5a318fe4de33f11d8866e75d654f00e768a5eaa8771e47835c225ce4204596cb4357d	\\x1d910939789cff4f747898fcf6bb816802fd257eedb0c5c5b31c49a85e6db00ddbdce608047e508fa8a4a3c768ccd99053023724375be227da132e1fe7ca40082a04311b33a3c0730d8cc2e15da1d5da0397ad7960ed91d02defad90e28a5bbecb3da97c570d1f0c4f0c4c41dec1281bdd95d62e7d95df829973422a692a8b17
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	17	\\x43d2f9fd18966df82d172ce5201c3bb12207776c9f618ac65efce587f4dd74ff1c5c0298ea589e9528dafd9d13e074e72ac82e7452c382e4de82d976da97260a	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x070f7b94eda33e8380b232867ba35145a447c48b201139df160b1349f7f80508e495d900a0f72c9323ecfe92c0f3790a82011ea9adb631e7a195653f5a6d41687523ce929cb6cbeb63bcf3839ef4f3f61ce6239a738a7428fa5252bc5f7a6de75878df8c56b2c8c941d1a42dc429f87d96d42b995401ad47f21f14ad8686d342	\\x863d1eccc8c465f7862ad10093cbf69c5477fd8d3a9d845d512fcdd6f61d74f792788629d6c85400dde921fc518e33e6ef183113f38f55983cb67bf28802931b	\\x9215b8054de87008cece8b00f3970b97a623249b93b5409dbd226a681f034ea746331e63ee5e6e50dc893ece4f56e67f6c1c537e78a90f1ef1bc0ab90daacbec1252750715abb75253183cf5fc5af9ffb61ac4972edf9ae66822bc97942f6789f8eefbbc6f7e47755ec26594db92c226d54e145293b3b6e521b843c49e96a608
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	18	\\xf01c3eb05fc44debee267ce8cefd8a1545060efb45ee9e255111c072ae3ad1bc053179ec6fd5a0be7dae679ffe4cd97fd1a56360169b57caa667222dbc5b050b	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x30818a3bd79a20aa39935b6bcefb64e391d7007d5001b4bd25f1f12efe7e55068a7bc529a0ed4f015771f05afb45231e3102339888afe39e2b1b7323c32c041ec166e8f5a66e62a4938f0e4e45751fae68125712b9020dfa91c1bd87bd776bc2f22bb7ea5bb8d89eb082815ba902e517471369893588ba61f6050f001ea49328	\\xedbc0939f65eaff95f819cf4e24dcd8429701c2ca8f41dbc355bbf631c2a40d77d238687dd5ed0bd4e296abc29cbfbbdda27222f431169185cf5a9d3bcfd6864	\\x352c35914055188f09ceb359cd89abe08c8a2a6f8a030816f0af72bfc29ed959e768e01107f4d47eeb13bf94d90c606aa27614df6e1767f2f364dc04bff0672b7315968c892d4be2217d6eb91a63094edf303af5fa66fbf579d1458ba86d540f7ed1544fcdecee23b3dc8a073c9f15b27fbb5908c7070f91eeb6600af2da335a
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	19	\\x1ae5582c378b46bf5669d1c8fe616336f5a24c3db1dd62eb5edf17953ff9a2f07c266ec781cbeaad7b6e851085dee6a4d99f692af9590cbeafbb970de725ef0b	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x61a0bf755d2992e2fa0619566b6c34646598570ee56789d8322bfa43442e30e8a7f3c01ef3a49ee100d7700c94ec017ee67867f266e72e32c68cb840075bb5c8e70d56798261a94f86705c0720cf5a88f9d54aaaec3970695d51b227e90d0567a8525ee60d49e4c0d41a7552677dbe6f5b3042d721f9d53e92842d2baa10af53	\\x75443a150e1507f04282aa2141a9e5df198987764c0fc0973d2f28115dc1250ba20db9f466cf49d1025939609e543aa5a4a7f11d44456d74983238d5048707fa	\\x6e1e4c61512fecc2cebc3759787410cd1ffbab477793d420d903eef6c85c55f0128c00e37396b0701fb598e9114a4594e2f33317163aabab75462184de5340b5058044e643a57d1553bb402eec96d2a273043e1a6d132ebfeeefe6f01f19a22ea475b57f986008b74e7ae64e8a5d3d0c67bd6e78c8879c716e0b80b00445ed5f
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	20	\\xaf530143a1b24168c86ecd118ae43a53fa6959604cebf94b9b5dcacb6c419d88b2b47d2ed7204f480db0e5bd5ae64798567798f8a492e38e06a38b751aedbd0d	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x732525b0f73e6c5b3b40d7671dc302ab006a5fecb1fbb18139af916ad6736f1ab68cfc0d741dfde90927fb0b2428620314d046b7857a1116a101c7de6f451fba52151fd400c271e0746179d8a1c6cbcc63b09d492ce63694c35f38bbfa40dd214781254762ef960033f28a62c057e3fd9f983a7a76c3ab52466ed45201ac11e9	\\xc01818d3613b11a62b9cbe09fd5e371dcac9088e3653e4a2c2b21b7eabf7f94264864b2860943a520a7327e92fead42aeab0a42df4605bc18e1cceda8d4ee090	\\x43643495ff1b19af230ba6bb03beefb0a9176b70a2548c7b5114aae85f91500875916cc81bb79eb62326911409ddbdce5ca13d0b7853308c464b8f74561caeb1ac2a454bf8d47770e7d3e59aba5cac5deedf988f45c4c98b396d9e6459231fa0b3204e7a795a82e9472be1626eb51e12050135860cf36d0bb1ab90ef4e49f527
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	21	\\x74a4c5da6b0162495cda589ca6fcd10b9afd616ef8c569e07f42f49843b0d43bd2402f2bf5fc6e9512a25bd5b0c325018ae301a79eb4a22b675abe04f49b1101	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x54e24eda896f44f10294dff98c7011dd2bfd35a3f6d2e794744d76b616d81895901d46f274d0691e9e467da1de67aefe47e7b47cdf8ff2eff66d5bb178d2fa7b1223781bda6032288b40ed3e010cdd389282bb740612c24d565403964a6eaadcb6d3bab6c285a0ed47bf0db23e69128c0633faba600cfbc08943d06aed1bcab0	\\xc85ccc6a554d0297444fb81f54b91ed79449ada637c657db48c76cd3ffa749a182df59fa47a3a8998f5a057ceb0753cc2d110c91187c09444a5492424e1c0087	\\x43fd657feebb132a5cf218c158af48c3f9cd6167474128cd2ea2a33f5abe0a2b9550b2627523d1be275de07b51a9352cb953d4a00a17c8edffd2e9395c1d8ea3a2df9920b8c5c9c14f3c6e76e2a003ba1457299082904d791afe4138206c248d5b427f9c939cd7b473e506b9940c56ab06ed838469a326f55e8e55e80b0d96be
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	22	\\xbb1016e281d42c6757441372fee600c18fbd82657f87bffe96e1076a59c60e4d326daa8a1c76e478d0388cbe1d99c42d2e29e5f6acf21728e49f59cdd873db00	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x24b89de21fa91a733e63a590a73d584ef13cfa051ae2ed0b35f02fa47f207925d17eb40137f7b7855eba19e93f7646a3a70b6f953a1b3e78a0c1f00858bfab269d6bca1cbac6d053317e3dd7bfc6a9549f9516a9dcfb83f5660803ba98c2dab07b860f2982ae810112610917f305e90e9db8d7a9e0dd88f1c8b0fe9001dce95e	\\xc83c510242b5937da47d594a8471c066e8e741da48628fa3868e87a6d956164cc04ff63c1d81e3794731f113000b8c16d5dd445ba6d19e98958afafb34e7f82a	\\x0b94eb779291d509d7fd722192248dc08ca770aba1245b580b6cec0c42d8db3ef658d7c4793c0d019b0eb226c845f63a0d155bc6bc9d6f6ecd4224fc5cd0772962509c4acf064ab5d83d347620c792b0038bf2b848b99b2107859e15aeb6884b126ec01ba9a6bbc6ec3a97002d6baac2f75cf17bbd44f803e5248e1d5c88a15d
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	23	\\xe218c31fdbde104f57f76be9950f6f718f3ba6a7b4e7b966a9660b090e968f941ca66752729d84349d224d7756190ba4b7f8b7f2b23687496c6543ea92de0f0c	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x74e6091314e1c38893fee76e6248400c710884f01c5dee5fc2a20d038d4a58fb7480c95b160d629bfe89f8fb06be83bd2b754fa34db57ad4a0922911a5d3723495baa308deadc13bb606b8d26e20424d20cb1fcb537ec329e4ca8cc024b3f2ae8d89b114ccfe0f2973e790c84fcca7586a19def451b11964184393d517f1eafd	\\x7bb0d87e5f6a09da69e63d3076e5850d6bd24670d47187ced2480b09c098422413f9378c3adf63d845af9481d34a9d94ed81d62b06186a3c6d47ed0c0bd60c4e	\\x661e14d6e96445b80551d805ada67b6c8e16997780472f74bf7255576ce49b499abdb5f2ffe36db924084d74d8ea812e288d9701ec1bfb852d29ad6176f401b4ef4e688832a3ef9d032171f2fb83fb9bb3950064af5fe1ab0845cee75fee7f7ef70fbb95f16ed349ee83f4e6c96521404a04d6fa34159be4c1f656f6cd798351
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	24	\\x1d0b388a430981b7d513353c26596b00afa6d81be2c96ab599cac32441f38c656b284cf62e11c3db517fe59e5987278fd0a2cb302df15a1a0fb7f96aabb9a506	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x6b0826c32b69cfb1c5a95a59d33ef05cdfe0324444d5ef3c40f17b8648127830df9ae142203a0f35420b0f75833456b3f63c431657d24b34f0cf2b656a62a4d69c0003621ff2574446bcdb4e1d946cbccd1e5bd449f07045fca48d77aba76a40de9d8048713205c0dac84f32ef9b0d2fa74db9454b7f555f789e72f35be2c2cd	\\xea1a3d1094436b43e2d0bfd35e698ad527a68cc904a2cd0d4efcf2f8c867af3bfedc2cb39303d0757d1303a245e4a75a37c66acc7917520a960faa663795b5cc	\\x650272516aae6dbb8eba7be2d7312c0eb4892486df9a391cdb911433671bd7e8b4cff42a630f96a17d1c393c5cc8df8bba84439f430cdae398e5112a172516268d01e94ef5c3b32f0fceea9e7fd3a460dca86d9941de4b413e46c76b79ea739892d41c475087524a001210fc7bf0e409ce7e31ec007162c820f1e138787ebd50
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	25	\\x25db995f23e54b31f80dc6911d35cbaba05b87233c82a30a571746cec00495c9f7dee4cef290865b9385b0d0641b89884f422cc53bb7e20a7a6d299051896602	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x1d3fa1fc5ff2e9374fe7b1001737d00802230cd20efc4b09553750aa4942b668193bd53ed592b6a3e99ccecc6b7aa60d3b6ba08c01662ef7508b79e6197ff20907f5fb7c9dba87e3b907a7c0578d86bd112180c8b530dd43632361562a03dc8b2c839facd20eb7537cfbfd5c46561c62d3c9f48cd5ab515e34fab723e7d7a26e	\\xe323b76376241cc5485bbf5bf20e9961d09b7fbf7c62e58dad4e7d62b9d609286273a4ce7dfd1993be02c2eb8c5bba7aac2467c46b082361ac1139ebb1c69e08	\\x128e2e130ec40681c421c047e3c88bd153411593d62284b59e49ebbe39e9017a384c856d622ac4c5900480b393ae3e6577c770b23ae49efa4b6367e87ea300e219b099820ea84d4285abfbbd0f029b75879b9467c5a19c14ca6067135a98c1a2bf0d7f247a80bc1b9ec497e96ebc53e9b9f77b4b47440b2a71a3038b05904df9
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	26	\\x38a9a9e7423174b811e61b80efe1718afcae052b757134620106170e88b2344ead372497bf8fc1c3a08f8a4e4e8afb89e1942803c8a292ee48a15f69f9e8950c	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x2c1514b5f5ffbad6746c414c3364d58aa9850661c618d79dcf41a11a9ea0ab4ae36cdcdd1f592d2a61e3c019cb55a354ae307d5c0280c809d0ea0cd08b8491da3e52404d6c37ca3c3d9be28b6445509b5a8d4ccb50f4d4cad198578511670456dcaa1fe419eafe24be2090ce90900a29c37718e24d3bf8e846c114e5ec763950	\\xd057c1c022bbe9dbbb5495753e5e97222529b1e7dc63a1798b03341e232917d5e65d19070ef348bd2c1c514661b8ab4b1bf374cbf260963db3232b29316c49fa	\\x85147d76810742e03e466bd89669c92e1926448d30352021957e13482ade6c53c003de3855ca115b99e10a23030813b21173d328114ed3a546f2cb1c6792f73846721152c2b6a8bc846e3cd77e4de492c60180db2db6240dde57a25c3adc309af35987e1d72742876f6d4b4f9236e324325e325d95102f824fe687c1fc926c9a
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	27	\\xe772b05c58849b05263959e01e8a8a4402b57a57160e3ea2bb3a3256f81e8518f6fde9d95d2df4a1194afffbcf346020fc441e52bb7608cd9b98b211d3d87406	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x937dfe35bb2859cb15aaa086010b900cf210ba8fe222c691017d107ce01865982bbcd26e4ce58e7fe7e9cc9bef13b5839e92e63c9b42ad99dd764a8a719d7fd9a6ba3b388566c40aabbcb45ae68a28e276df4fbeac3a8b9fc0bd933cc15008bd19b9ad1cd621acf882301c32f828348187242e6e7e4a85b90ffba03631e30d41	\\xca7409cc99b35b14784b867009db85babec8bb1c4e0a30962d74e3bf6b1e353a6393709e0e668dd5412ff74cf859547786e8dfd74759c47a6be7bb8041ba68d4	\\x96fbfc566d840f69420386417af9246bad5978f3929eeba07824e15a8f334f6151b46db0df07be4b3655380560c25a8f75af4d6b6e377602ea598954fbc34afebc7ea8b032538abf1ca6acf12c0d51a459391c7a32e930f59d33ed069789641262b293aa7e808268729f6e5601f22487df747aff4178d408503ab9d106414f80
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	28	\\x168de6dc6d05474b059e36182bc511252ad71bf7a846b8ec133fa2db1db2c50627988fc2cabb0b45df9060e7a88152cb30890384558581708cd263522ca22f09	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x47fdfa8ed1f33014d8502d819941a199c01e984265fcdcd556bd85e8df32a4191d857e541042a7aa0ceb0012de2ece4dca41b873e347476853a3e995cdc4d66bd2d48a7a0dee624fa13da1645c045bc9351e6f908088e17170124d65885caf7a6bef6f612d9bd0c26fb9af768d1c2ebb5b0a0c5579d6c20f25b28a679f518082	\\x0b6ab0df2d642db3c1eba5a427663cae96d4805e3c7490b8f8e7bee4e360767eafa2261687be36a8421796027eb1e83ae3dd36556a958c80d3aec6ddc9e28d8d	\\x280fe265b960d4376e047a96c2e5b9097954225683a47140e56b2723d1d069b49ee57f9be7084230f7f0f2b13d25146cf35679d2401963fc1ab9b93f817f9c42942a19df1cce650c41bd4ac57a72f3edeec6a422b708953271f387ad0adb3e4ee03c0e74963bccbbb1f8d80a6c4ee663ffb058aca7436350c14a041f539a6e29
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	29	\\xc71dae0309b2f0e0c5d7b506f5b419ad208987c2f1d1f77b89ded83c90c9780b98916a866cb764d286eacfdac9ce7a7a68277e201dd562262d0ff7c6d487670f	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x4109ab6b91e332a791e127cf25b99e9ead85b70e5d8a65b7502fc879b639fcfd21c3f94660623d95fff5e0ecb6f7b66cd168574a621efae5540af2fa92431a6bfeaaee6e62332c158050c4bbd79c42a2a0cfb07e8dab557243ec799a128fa55892419c1f6ec6eecdb2bda7056316a4e9497b013826072d6b2b0aab484c07dfb5	\\xdf0063ee2a4c16d3635b2f2a3ccec3b1c6dbaa15c60bdce23b402b5e767c39a35c72ef2ffd31067277a48cbb30402286224ccba3f0482b34168bf89bc2080a07	\\x1ba010d6bad5bd75902528377b614306ccf2adac7a5917a230606ecc7cc3cce48ecab420273b1bae6ac4561f4a175b28e9793b9bf89f3d421eebbb1d135c6a96c63b7b291fd0f13ecc4ff8ba62161db835e6b7ea8bc1d33e3b72e4fb19c53ef14c4548f421cac5cab1259c6438223c952295debbca71e3ea6b8f982b62c24446
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	30	\\x691c90dc56b8c8a317bf5f7cbca6eeabdc70479e355aab2dbb36b93563053d068d6a4b487d891e55d8d10faff4c8706d3fcaf8959c6910b2172e3cfe67dab908	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x41ab96678702721bd5a826f603b7609290b340281a6aebbb739e0dc41ceaef2ea9d623d7b459afebc02a3446e2860bbdf0687a25c8a549322cf93e80cd879ef6a0997d1c5dfb011d48752a2771fd205ed1848a9ecde350e2844669c41c3730a015760d9903e05158adae7d416aa3e2ac2d10a946046e04ed7259270dee00db6b	\\xd08f3246f15c0548cf5c4c553b55b0b6a633551fc2f28fcd598e46bfd1e7ebfda1957a72a57e155c3fc1693077b851f639fc6ebacd1485261f89a8288798c282	\\x54c5e5320f1fb08794f064ccb9247b51d0945c3f82313edeb341e89bce175edb3a52f4010c93cda94c0dacf58cd8cba6445aedb497594a228bb1b9fd249575c89ffc5bc5ced1f51436890701c369cdffbe5cc84f8d18665d6b10b9bc76023b8c89b1baa243df6d4a119067919f6ea95a6f89f00dd3a5e7d33784334dc12d86a3
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	31	\\xd572fb71d6623231e1fd57e20a3d5f57acff131b41cb736cbb3f949163abf5147367ea13a69a96a086211541be7a9ec3a111a00644cc53ee64a96aa837c4e508	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x55a9b3663c1a22dbc40ec041d40cb3c49f21b4515e603f208c34e5a03b9bf866a19d80acd09dec692e56e1f82dcb0acdf32f717854fc81e1b80f1d4befff5299cae9b9332d7bedf55988c7c81ba127d74800937bf80c04cdb53ccd9e9605347fc124960fcc2510d8259871120aee5e25dbb7ecc42dfbe296430d2a4421697990	\\xa852655e5e5bd1299609326cb93d4328ee70816ebe7baff5933e6c57120899465f67bfd79027dcd47580b27bca4908658a7bc01e5e7100ebd7ec70427d40a7c8	\\x39a59f934eb9c091af4066355dc86b3099b599a6bdd6cca587ad4fdd63b3ac0a2caa887b377ef93b8856dba20256464a0e544cee97a14009dac7590b23438f212ecee1f7a67aa218c9cea78b4297e92ef2a0cdd574935ae3a1d26bb254dba0109b9a0f78be0bd47ec782b1abf68988cce91d0550e0791180d39f81f02fedaedc
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	32	\\x7c252a5bb4850f256ad6c281b3212387c6d5bcf6723a99247395cbd0280cf7fb331d541b8900eb473904f5d5c9c9d483a0d29c34bf96024eb9e15aa54af0d80c	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\xb0f52d7c40a1e4bff59f5ba4ceb39816e56bb4b6af5fb8395c127f4a584c6b4959cb14c301161c7cd5c698e43454fb61a794a20b16cbf609c418ace45f65d4617b24189db87366d39d1a187979f5e837a2679aaeb1b3e8b563112a27da7a44ce410241760ee01d9075f681fd64956594ed6f427faf77b9d6ef2c70b832756b85	\\xf5f6ef4db3cbe93d5270dfeea614b6b2a7c75e22ac787c3db0b6e8223f375bd3a3ddfb317611c14ef51b5be757a57a449d8d16713f1e82bf8ec4b3a0c9206af1	\\x0f6ee6c2c7126eb4fda7d9f2fb8972d1dccaf32fe67a3e7343d11351ecf98d0aa9f9405b09b33a4a1d4868d62fce49843b4dad38fb659254d474afa02d160ecbe204c3c638f504b098407284d495b653970aaecdb704fd8c4727f80c6f5eb131492b904960fb22c7871db3c97bd02e99d43a5b5bd049c1e5761a7e97daffc59c
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	33	\\x2ee15d75db1437537fcd107c60d944d58c00506fccdf5b71eeed5578b5c7d129e7b27b52fc1579e650d6e0c8761215751c185e55deab710e3e3c6d0a7572860a	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x35ab434200cd08f50399d1f3b25f37aa1cf7e659f068444243169879e23eeebd5c899ba0316f37562797e9a8186d02a17553da227ff9fdcd39ad1d1ff30ef70f39c4e6c490e0e464e8afd6c3c6a6e383dcc82e67d6e062553eb21ab63938df32961533327ff0a6f994e7fd1cfe8170b1189e873ebc42fdcdb06901037bb7b77d	\\x0413ed69cd6bdaf397dff0af43d48352e7a8883667617158c4bebf57dfd7049615b9760b79c2a44a6ce1f277d480e0a354b411022c1a6ca1f46b3fe06f4343d1	\\x23c4dfacb36fa0c9620c61acb97aa01336c6f5740a91c6f1f89fcd36d4a4c7fa8280d5d4ae35864cc8cf9ba10437a2acafdb00455a52ae1f4198df7e38fdc260fa5f1dff41708f2454e34242e403d87e7d4547ba2050b8c1f2681e0e24c063cdd43c2e4f54825049552ebdecd1b23dc53bd79f973930e41c9f4abba4268ddaa1
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	34	\\xdde889e851cb90a98318f1f4a9303d07051de2a5e5962dc0871a5ef62f606fc7e6cd79941e62f06c2ac07f38a44a4fb258e5b58fb072efc552e94bb58180bd08	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x6c874cfce62cf905311a3e1bde8ce862b5d0529d13b1fbf94d54f2e170b8eccca863684d14d23e673c343f7de629fe2f78dc9b327f6bf0af3a1e2bf097357cccd46a61970e8efcd0452648ad85f9470b62871b2735d2898b21717e044d9c65a6582acca8d9fd5b45072894748601adeaa593d6fd2a427f1ebf58cde3a2ee6441	\\xc941970eb1d7039ca07ebccff0da7681bcb83107832603f5a6a801995dddce9ac0af749e12032d4f022de62e3709faf760d5e25267c9d38db30919d18ed0296e	\\x1fb3913b5218e9531cd190a3405da89b9463d6a7922f3f123ac4cd64e79b19aaf3c9571deb342ed624d9e1f88a8ed8475a02aa1ac3c5498591449498a87061cce964e94c2f8823501bf42ddd92d27b1b20c87a8f17aeaa5489bf367e459bbd3dbe89495f9c61c58c8dea03791847af7126dba023c4973582d5ed3f2ebb9b6574
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	35	\\x1d16ee42999c98257e8c2619f61319ede4dd45faafdfb5c9397b429046b7b47cf96efbe13589cacf5facbc31062097eb565be4cebc0868d83922a1e75f6f770f	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x016524d520bffa1c9f9b2427ebaafaa9294e81c563f117493fabf03dea3471c658922229da2ca9708b9a26d42826a301d50eafc738c128548a85ee4a96264bc2e6a86c8c65b2787c0f2d32ee466b38a9e66953877752393c25e7a78038a8dfba71b8bbf70f9a21a25da49d263e500de796bf715bd541e4143a9874a2381479f8	\\x351b60b6826260b023149a61304c4d3ae8a35f9060cdfa590bd363e78d62ed9aa95cd5187c231a30d2009dd58747170c935e627d54d50857ad4cdca64de562df	\\x79206120e2309f1d921b5e2ed0f3690e03b6bb82df3cfac02bb4b9d104637f665153aa0c4d0806885863548a94117a93c22c987030abd86921f75b8a976039b98a0464d69bae506de503880f1cabdb52997a5a0d77359e39f07d29921f28ee80af6ff4aba91e441bb00afba09ec56ba8e4f53f6a64efb4bca933c6d0aca5282d
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	36	\\x2b946d1deb1759923fefe172fc13f898f5300b162f48e91bf628fb8e0926ed6230b9d125eb3ec29eaa6ef2366e46b0a009d8d889bdf9da53924302b6f0ecf504	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\x57beb6b2df17d07ffac59ca1fe36b8e38ef1d40432a3703b97bf302d5d2b2fdf2e54a5b7b2f8c91d6f2f6a6231b9a2aa2bddc61d2f571e3c0b0d7b9ff55f9a95bd4792a28e404c238864a048aec6e1442f123341a1c7a4dbd55731b54aff77c1e4b859da0e83b106af1952e149181a1f8bb733d342b16affca49369ce1c388dc	\\xa80fc6ffcbfb63d6cabe4d1a0f2005168b53a2c4bd5d94646fed97ebb34cb386ba84206f65a8e00ff32caa0ba18c10326f95099bd1ca265e28bad28f8894d0e2	\\x611ff6d47889493c6e2969af1d3df3a2c417fb8b391cec57831b0034be28e4411ec2619804aa9eeeec8ff101ed7e831765a1c38c0ac62ed3481cf3993e36d901f30fa11aaa0eedc49702035757715627db24576be12f1de8e02ac102c98f8c6c0a169467aa980b985e69390e9bfc7d26a25afacb4e18a6950a4f4e3d6c469d1b
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	37	\\x9fc07808f9538f625015309633bd0ece3e79c8b9b2bd232718e2560f5909749578e435abe8ad55efe7a9d5c12322f2b0da6316b798e2e5b2ad775f2c681fb501	\\xcd6c0d111b3afb929b3d9d9db3e013e52cf6887fb07250c11a05d969ef4d7704a7438374e5ca1dbb8ce0781a5e2f957e43f09003624822ee9c6c8cc3f45837fd	\\xa8c0a68c9f89bd03453097a9810ecb321aa48136c47e334fb78feee5fa20cc05146fb521d4a3aa7ef36e6ba18eea35005d76024d20dcedcd463a098b8b68e9440b995e9ee29f8dc48d7e437771fef12a0cb11376e605e6a300729d149b128fd5d0e955f66a494c0134a6de78ccc4874991d2a736bee9fbf2ed1ea569178f9b2d	\\x2cd61fd421e0f95e4e46906853443fbf98e74257aa2cadd7b9a2a1100ba74d23dd973d2e3eb415d7a925b68e5212cff6eb2b213746cc4431d83432e34a9f293b	\\x9ba1ba90d12851cb11b785b328e1499ffc321e2edba07f8c14a5795b38e6f6460acbcb685120371fd52adb64a644111ef763197d024a748014ba26f207831e31561cf569b67727a32abf01d4a2d253f47b6a11018d3cee377020e50770d298b1e2b6616b588a45cbae8f187e8226535bcbc9a6c14a7fc949ab74a3354e80d2ab
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x12d46e05c44d4e9e6d357cb3e6b839742ca4950ad003a490aba8e9e44647705c7565ba3c3453f9560693a23d8fad6ae7821193afd071c519fbf017ea2f4d8d8f	\\x47965f6d87000505891f21dd8cf5ce7eda60a9d8ab9a50dac55db9382bf56b4a	\\x3ded92b25077c61a4892b982747c90d93bda6d5dbcf59caa9294df085e4a0028f08329b7dccef12284e7a8dd07891cecc0ffbc05bb682dd6b7546787b725179b
\\x490a5063dcc4d2228b5287eb83e4a9789bf44ba9a2dcec24b1e407af35ed3c9a50bb3b21fd9b63b8cb4741ccb6cef4d396eefc39e64b75aa67d5ceb275557231	\\x69b73a610d59d684e38b4ad84e9afd4c3acd4ebf6e29440b4710cdc5c7d7d203	\\x508db9d64584926bbc3928ec3e751f49da857ce7a3f9a9b3f97cc38258d810adc32e0bbab872816bb1052a949132c451fecee3d1b5ef0e0717da11ab9631c5ce
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
\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	payto://x-taler-bank/localhost/testuser-IE5sQAmq	0	0	1610625662000000	1828958463000000
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
1	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	2	8	0	payto://x-taler-bank/localhost/testuser-IE5sQAmq	exchange-account-1	1608206454000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xe7e2cd1142116f013e62309f78a3d6d1e699fae0422e88ae2fba1962e1a50e21d9b1393b7442e7d6eb2ddd42157ce39a2a243634f99580893c2848a3d83b0913	\\x0ab648489b2c857bea4e9b696644a3c2a09deff78e9c1461ef6b2c911feaf29a8b32a956bc9b2731a4365e44c0e2687c06279a405931cd857c67de7539ce96ee	\\x26e078e8fdb4e94c3db96ad566b2c522cbc97af1bedad5d40e092c59291fef008e9b1ebadc0750cac08aa0d38def06763e20f70d7b8cdbd2f05e31acfd7037f4048bb53ddbc1432d9d43320291d3d2d5d4324768be354ccb178bab3a3f8f8b380a4bac17cceac1d5cd3233f94ccb5896cf4929fb1c78126e84d22c7d03b77ba0	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x673d0a4607e7a16065d457d02723d421a1339045ba5b81f2463066359a3a29a74284c033d4386cc910dc300c6723e4c89b4e40538e35cec0ed54cc707c802d0b	1608206456000000	5	1000000
2	\\xd47b7cb6539f5afcff0a364ebf1c64dcba7396b3b6c183acb60bd505d5b59d57c79ef369c3e0e0579e7e96c1b295d49cc1061e30ba63ec7feea39911f57c3f45	\\x72aa6b8f737b86fc68a4055b57e13b8ed07748555f1569c9d29c2094d50cabb9bb01e1207b1e0ffcfa9dae93e6da639854cee89f53f0de215538c8a0d9196fa5	\\x84780fd770a1df930456eaafafd5578f9847cafee5dc7802fa175eee1b42f5c338a8ca61991503e65a6fdf5848952d503bbc1a0c3309996037bd4c704230e506f321d790c1fc2b939ebf030d4e8c788b4eee5744a62da796328058b877db9f986ce438bffd9eaf0cd705acccecdd51302ea02ba11c4a9244231c88fb4be2fa9a	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x5490971d2a538b3f6e61883bb90ef494a9b87858894b7d226eac91efd93e9953cc45090dc5916a8e2bb05c99c444f2dc99bb1ec863695eeeb3a4e5fd9ba6db03	1608206456000000	2	3000000
3	\\xc007038119927e3f6b000a50cce6d868156e6c8c550d7d647b6d62415a765dbd2dd0b2d67c48afcf834448dec4206389a0a81f1d8aff1feb05ff9e07d5316850	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x3d2924ee8ec704c8d8df72178694f130a3aeb7e5b6fd3d7c8f805741fab44f3c40aa8b814e579309c4a0fb80b875af982b90ee7015167a329b399cf5d3f1c55a1f9e363dc64a20173cfbf265a26262011870c1da8e601214b52365a5777f91f80d708b1a4baf4a49a15bdca29ebb27a46dba7d1f2e1bb6d8ae97421847c153ff	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x46a5b10a80507dc774fa03686551812be6bcca4ece115c8dcc3e9918d83c91c2664d62def8ffee66ca6a6c8bbec4b5f6485caba9c5abb3c1956549fde4d7c904	1608206456000000	0	11000000
4	\\x590d5282a5701abe066c27fadcb02e9e7463bf3900cc7f63a205be534951e9afca4ed2821e1b5201a97328cf3df3e5a947ab169d586a72e896cc299ec0505ae6	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x85e3ec4aafda95f611acc333cf5853cfb44b0b4031217dde9200aa8ea97de36fb9a681e532f8dbc8a3bf05bc866556266de906d74182701346ac7d871bdbe1e3f13be02a4219dd43cca8d38dfb3d286fc08d321c3b4db67db6f64bd17cbf3b4814f8894b6948b62e2d02a627b3baa145bf05aeaba469c87eaac5f46bc954affa	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x6162d65fdc266ea2f1fcc481241770fa18648f91a82b3f4ccae6bb36c9ed56bbd801ad6fff650e6666577abd05c045545dddfab8b398bd1c5bf19249f07ac609	1608206456000000	0	11000000
5	\\x2efe3b0db45eb1f25516574249c2ea72d786d24243030b18e179328936e0908a070e1c0deb1076093dd601c7e4758317c77cd77575eb324be14ef6d0980173c1	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x8b384d602cade6d487b9e2cd56eae40840f246dcb2e1e1ea5c9e7499e2ee54cb25440a72680699a87e07769ac7ed2204160ff9f104eac64040b781d7ddecbf1b07937e9c27a5a5824d3e103c20aaccd7084a0a5cdc98c304ba9c64ff7faecd7e11f7c692648d764f135c1d472731ad6375e90ca37b3b4cd1e4c8998ba2dd8e30	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xef92a864b14420c582776885635efaee37d592164d783808114c614abefd9510ed89e2d31b18ed70a27ef8ba5cff2974bdf9aaa057b2736db3a21d435789b400	1608206456000000	0	11000000
6	\\xc02653cbaa608dc394a933e92bc452ce33fd8acab3726b5014ffa1001ae38d218e66eb20978de87898f59fdb38ab4ab470bdb8587306854c31e60ff6cad6c99a	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x1268c80fb94ae971c48c18ff6181b63aac3678a12291fe023b4f9dcbba838a1a16baa0e56535709f625a9f61cc99beb3161688fe4446553d7ec24fc21e06a88ee9602bcd33c3a1a2186d60cf8f58d7a76cf89a312e8f9f1b7c6397b56b64955f90e76932047a248f251f495d0ee950f3eb657fbbb5ea416fcc1ebbd0bd22482c	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x2f2846e1ead46a8918c2dad35c82d3fc21e020f5d1fc0ad8ec2e3b1d53e0b78c83b1d434a127c0be5f1ba91dedc615cc0c041701a4b3a4bade42993900775909	1608206456000000	0	11000000
7	\\xd01cd4fba8dc655d3767b01b14d535bf3553c0f15f60019fb8fb8f07c99371b44965b3c5fe7a68b2c6862c13cac3af5868c0680e9e9ae2ada1b6942d9e73dcaa	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\xbd1d4ff7058277fe950ca916533c0af61a52bee0d176f0ebb353da6dc972a95afd6983ee7c6a7b703b518d5747fb9570fb22f7705da3c62293e1f6294d7441bcc5f3144539fec74db015d59ce93a39c40849e63bb1ace0d6572c348872fbcf561b173b3078f580bbaefae1276193c2800cd0de803f2887dc2b837f08e83d7e91	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x372c98e1755dd3d3b0d0bff07f5f0dda0571eb1b4eca9eb64a9000939acc5f77e5befc5bae026aab0957e58434f189e739e7b9d34b8a679c3a145339d12b2e02	1608206456000000	0	11000000
8	\\x42ac3c2f3822bbdc71d769b491d065bedc9b3c4c94541b8996a5d93b1c8d3cea62a5d8aa26852f7a84d60f636db65abee7a98099887702d8dd17a4040a80c719	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\xb754cb119b97666c26278e63ed6bb8a96e432240377dc37867c7c8608ef2228d0dfa0a318fc9c9f626c7b32f851c48f566df4e289be01c0251e8c8401172a264524fa793f236c8537144eda1ef7692b65e08114c892906280f78e6ca9b2b6213017bb3237fe316f86e840d88e1437425f9a5476082a048c24ad2f7f02ed4f588	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x1ed582f5e176447ec11bab85d8cfce1f6a47e1b31f7c0a1679d633be0c3b903953bacc86d34131ec5ba1f2ded0428e927efa4883e84904ef026efb0d9ed0f70f	1608206456000000	0	11000000
9	\\xee53094f1667cdcd0e8e63224359b161106524a3edbf27587249c7c277486cd754fa8af140909ba71d169d05fb831a13a005a0b33ea2a6904d142a77b4256f73	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\xa8d4162e29aec62c004d1427d282acbabded0010c85ab2c5c0030d926b2c9a9f6dc5c4c9cd5bc4079ef587c99acecd5366f545efe86c81a3fc8f1c0eb0d842e487408d3ffe53b1859ee87d3bcdcfe61ec56615e42fdcf184ede322d37f6a9a4672367cbce144e1f7fcc2cd0b4104e7e92e78c41f5fc4e7e984a7ef4e1f8d817c	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x4a02f8680ea28693d635514aa185683e50e6cf13dddff7ccc69acb1fa04dc51723e61b272b735c133a583ebaa71bd6ff8d8fb2c54bcddd45a2eb606cde882d02	1608206456000000	0	11000000
10	\\x18fe5c6e1cab43e3ff909f7a16f4fda86cd6decc28e65b1ee6c314ddcdda375f67a1257371c35f976f624f39a28060881ea22a57756ab58e3fdd7fbb02b00078	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x1ffe35d3a1d943e451415bf6189c8a44356d25fbb6f76be7f70a92dbe371f622cbe79ab49409fe19b399e1033d85bde9067dc334d449975a0cd34e5e950a2bcf89abbe05c414a480fc5eefdfa112933a86615296b9756490b8a380db98f1fa79f0188cb2fd651963f856ed7765785513d229139a6a93f1515d40682f60f2d209	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xcbb6d95c35693034b463c8723eb4b81947c2066ab1d2d21f5022b5918dba3fc21945e14046929391b1d5f41543850924578c7ffe789dafc99804e2188fb6e00c	1608206456000000	0	11000000
11	\\x78e4dc1913b62e2d1be20b53f54b2773db29b9e7eeec97578042794cf7bc4c42f044a04a0b951d4145d0a0a9e2b29ee21b3b5f7720db8c23460d68f98c191408	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x796e5b2dd90b9eb30b42bafd1e30443a651ae8487aa544e916f70b99f40678c45dde6d5067c1aee0d1e524d0f851e64db901b883b4b762e37c4671244dc6423f464374479bd7ca2b51fce81176f52e248cbaba7e98858d061d6cb506ced4ebad972039072c13989eb968bbf8e7090f46db29dfb537f9c76ecb6a29763e2f3394	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xdd4e1ac9a147126b7264bd80c459a5079afd0bbd02147e918fe1c41fb634252db29ba078c799b973356e0bc1d892430d3d171f319988fe1647b541a116be6804	1608206457000000	0	2000000
12	\\xb626f877ec4896e1778baef277c34a9e714381e12e191a29d059b849ffa5457b60c923be336fc22dd0f2d59a0bfd25b6d32b6eca802a300a6aca142e441b79e4	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x66bd2dc9fc5473d2569056607d4c3d4983830fe439be7142b0568ec6f3deabab1bc439c2900913e799ab74a52209de6583c1a3a7bda2e858262e55e88c918955f4ff3588c2da56579234a1594e9ee652301450eb30b501a464d059dd6dc2842a265fdbb553b387dd2d6031e3921d1f3f0aa076e036e151729e1f1fe190674991	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x3d42290e924c4a2de07a150c7a54ac2846033a64bba15cf46515f3778917ce91c2956ca057732254204f006998dd3e6613e52b8981a83a205673b07e7ee0f60d	1608206457000000	0	2000000
13	\\x1ec983c437efea74306134879fe73c587464fbbdc2ad7a480cc390010dfef4018c38b4dac364a33e9193fa3ae8a78aede8504c72df1470f6e7379e373ab0a50c	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x16d2663d95ae08d5391aa0ddee632f451a18dbecad8e117858f4f49c5906d11cf06d8c1f697adddcdf6533d99d3c3ff4ccf11ac8c7ab2e58472003e489f311418c141f636b046dba7d0c5a6bb6efdb64ea7f53d8c7dd19675805664b9f4b0ecbf098299bb2a8c45f9f1605d9ef1c9238c55ee2fe5c8f689e13f1ea23afc59b00	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x3691ec3968a817a12d3433efdcce837d5681a9470826c11c5d4407e42ff929a08f06588ad47b6380ab5d600bd547227c44d94ecb21de673031f91696774fe705	1608206457000000	0	2000000
14	\\xbcca58e0fafb41177f31165bae014dd728ed0b429bd1e9b59bff2c42f250f74de7aa23c9e89e0eb04c381e3d853f8a02be5b11d3a41fbe713d94aeb85e028019	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x4576775e26bbcade2ce3bdc48bce3aba41141e27aed57fac144141d587df8ad28819834b7891bbec57e9c0895b81d2de5a8b0e4782748d52823b0a0c7d03fca3fa03187fd940612b7f4db2b5472ff0729da0138d7c47479bffdffba26984500ee942c0fda19266c651760a2dc72bb8299c8f860b17697f29f36bac6d37061f97	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x0a47ee8402a769aeca2d9c02fcc58c503c66baf990780c500d50348703e643391dae56a5f60730f7510481525277f5fb9b3991a9a49db6e28dc9c54b441d9906	1608206457000000	0	2000000
15	\\x3e1f29ef0b7ea4ad720ddb7f82269a7e640d4d35e5553b0423acd9fdcea5750bcd126f162a1326f617e0588840d868b94e21be68dda63a313a42ad0a0df09bc9	\\x854104e65d2f9da8e7873a9e92db4a298122ba0263e0c4f20bbc1e30b2db60e3e37ecaf71219d9e12af8267991bec3567cc56fa5cc05aacd6c04b44aee299ee9	\\xbadd4ba2ced0469e1ca9d0f12f6430c5d2e4315a87b237c4c32d918cc8e8aee2ce069f717fa83c079541bd95842006ba3c9524bf9f9c39bbce9e6468ed8d313f97a2d00555d25110ebb3b3af93cf8d886a2ac9d50aeb4a86848142754fa860b4c6da5a4408b7b0e7bf728ebd2779d29c9308b81ddae5966077f6d23adf23c6	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xd350913cd29f45630f1899f8840fdbd50c25e35019c2c4d0245c59e6501ab3f8a2cd270268726ae77048d7f90ae8ea5e068a29ed13a90d65ed5d1315e086590b	1608206463000000	1	2000000
16	\\x89ca92385b335931d08750fc89da9ac5cccb31e16f12900724cdb896924af81034ecbe9ca6e7151a0897a68485d9c643f1883fa4308cc188904fded4a3275dc1	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x91627a4545d8fd5ddfd6f767d2d0818128d1206333597eeca64acff154fcf14e90f5632e92a2b005266977c963571af32ab815f9fd1d88aa8da92207d0e0c1216aa8f341721484bdb3e7569dabf8b6418d992af118ad3ff4036421fa5e138fbb4ac2847f2cb224e5aead18fa3c634faada1f4010ac246c739f483776277ac90c	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x8df60170bfb2d211a8c132bddbdef03744ac7083e0a702699ce3d6bf9b4f0259f98a1bf8a4bd4fdbc4e891a1b5bf84edefb4af09451dafa61d1de341087e9c0a	1608206463000000	0	11000000
17	\\x7b98c22054b5521f6c31e1ee788e1b1fa1de6b66a1f26bc8f2d810ff1a74da7c9534ae01c3dfc436a99d18578ba4415f964a25afceac078d5387375979de8206	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x6cbed450ca638eee18e533e12d479761317dc37f5cf7a24926f1192d1441eebca8da42bba7c1601fcfc1261b29e58ea12c4fceba86dc4dbc582532cd56f11862941b59a94da8a8942f139e03ee87189bf76f17ce712c7b6952bae923dd4f7ecbe317ba0a639a608eb777c18741feeff75fa0651bc42a910403ab79ff5c916435	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xa41ca6a3c34a1d41666fdbf009f045eed5b79f47f5a21d7f6dc6ee4497373a2afd4cbd801bf19bfe4e68e1de46601cb45b06ad29e51306c31513d7dc4e2c310e	1608206463000000	0	11000000
18	\\x54b7bbc456f9320a256786523f2e5d04ff8f43390c4fe112c98274e26110e050573ac6a54f26c4b5e873f0a529b82e0e5ec5a39d2b9452b722bf3302d186a516	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x2ea0145cdae5cd0437a9cb3e3857dc7eadf3901e11201fccb261608e2343d8ec2d921f6cc26ec27cd5e516e835c3ed82fea45d3ed1a884c5715baa2b41cc168b0b243e9efffd76836f2837267362627744330a53d368fab12f3e1072718973a710fbd50b5301fdecdef5f6887ade7d04dfab12d1009da809606de597ed370952	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x0bcee91f9f45776f36449b6baedfe67f4ddfbcfa6226139f64758bdcc68915e7fe86b7f97ca6d5af5d1c7843db99dc393a87edbea143e56009fac97adf5ee004	1608206463000000	0	11000000
19	\\x028ddcacbf1ddbfa1a06557e988b51cfd79782e1010cc59183f3e63c13c393986b5c6a69a576f70046424963a33642ab9204003f4b4aea95fee7f975617938ee	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\xc41a890ef126756fd7da700435434488e716d828e92b108b6a3e8c99f4a3887286ea283bbe8ed6a9243a354f2c8d274a0b15e64b968e0bb6b823ac176b7a8220258ef724536d70da5d21036e6e092754078705588be98ad37f21324bf0a5e4e99b6b3a35a808a0f846072049cb30928f7219ea8cd2918c127b221ece4f8dca14	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xa5514534a00ffa0e340d75e46782017c1f9bd8b4de5394ed45e1226729e7c0166dc85ddc5747406cba294e3b4755fe90a94da79a1dc93a00c96b2a944fc28b03	1608206463000000	0	11000000
20	\\xf887ee6e4e96d98852b70cf55450f42c4054a6fc44e5cd5c45c98f6db0771a9df782c9192ec3b68f74005c7e1c13b97519ada647b9f893b9d8e01ab641d774be	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x9f2dca997bfbde35b9cc65cb5e00bb205957ad27324edca7ee4c55762f47520b54cb23d3f1cecddc15af6d0a5a91c95eb2b40504292dd872275697d5a0231d9a9de60ee3001b41b4b2e615780ed15ac0ff04e334e5e32051c5ea875d6e4dcb0b618bed1f0dae8e7167db0ac738e221fcaadea9fd06774c8ea6790fe91d10171a	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xf7ff8220978379dbb41ebda45e0916c624f936709364e33d6155a059c2c54b0856e8f176ce5c5a1973edf15b3f752683f8181dfb541363a3aba3c179c6c9f607	1608206463000000	0	11000000
21	\\x9bf94510d23887448f5c7c1163bebf0a0790ca925d9cc2dd1d0426f44e0da5855a3cc2b96fb8b362aa37ae2154282aea57ac03d5630f8c9db7124bb0c65d7797	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x09f1f5374467c02f86e96bef18f2a52bf29d24b0a677a538b960bef856419d9f904d3a710f96dd5f47e0ac61cc2baa233dcadde0bcfdb993b36bb2e98322cdca81331ee401a34ce40a310c607c53b271609941a1743cc5637d99882d294ea31a6439c9d4f7e2b5fc25855690a443b85ac1d031443bfe53a513a0d30e60bda4df	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x830a5a9cee4ead9ddd39747b86e5ddc695b8c1c24818b99566a72cbd4deb665b1ea12316573d5b9e5e16eead5aecd41d7260c8470a455db9260aaf6dbc701003	1608206463000000	0	11000000
22	\\x9ba5597d44e0c82f57296f724de8547babe1d5c35f8a3ce4eff34412887b837ebfaa93962a6db6af92990b9268ef2a394444a6e2d251568af92316637dcdbd38	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x7159ace93f42a605eaef4b79700219540fe3aadd9ada4ef3df7c44612a5bd0d447fdd2e289475653e13ab847bd36e6ccc16e4b3c7dbd5630f77d92d9ff2bf09208e0d9fda3f3276fc025fcebba864d884831b4532d02fd3c9868b95fc46994e0c82e57c3a5571fb66060ea95d1d19530185a7320422e2210dcb6254575e3b2a1	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x3819b65f9068dd260cf23f08300a42bda457effd2d0a9642b09b178d0206606f9cdbe31deed15a3627d1e2d4063c62ba70bdf3e5f88a161aa91bb3aa36ae4b0c	1608206463000000	0	11000000
23	\\x7de93650fecc05fec0889077e1ab1143293d941784b4edac786c1bb8d5bc75bd47fac94a13554b30004ae87e8888627e11d0011af05312f4b2c4e1308671ebd7	\\xf3d8bfa83021381520e877b81e1bfdf8d8cea124f8177a684632e0acfb4a9257ad42c5a37d4e51d8b70701910837061287fce5fcab70fb0807a4a905d7b2d2b3	\\x665c09b6a5127cd1fe808b8b020fa7953052c8ba4e6d61aa35e30fb66b6ec7f2b1d6e6af20b2baf7bfc910abe5fdf115cb3dedf817966dc38597e2010339fa91ff734c5db55cf4d8c7ad4bb77a9914662e3aa9a0d2294985881e482699ac6a8ee65ac7b99767325760717df4b8fa5f92745f3cf6bd151242716c71cb79b4a89c	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xa7bcf942952f4d17c6095518e1645378d7129c07137025e171cd65638f8c66f3638349ee0bc240094a920254ad9dd607ee22344ad1bcde2b0f728e8d1b79f600	1608206463000000	0	11000000
24	\\xd719af0f6886f69eea76110eb85c0819387e26ba18d596cef88a56f8ffc9bc7fe454ffe7b2fc9a2c6f5328b2be5664c0d6270f37321e140c60f7fec598053b6b	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x7d3b76dcdd78762bfb7d295f570ebf68b17c6d60b1f478d9f88bb54e3afee6ca0eb61302cb57d874bac45a8a6c9d605c0ea20bceafec3a94a1de5aa2082454ac058012b97cd5ce589d78136246367a89e29a6e9ab8220716ab019d2d7743b1fcffa9be06fc61a467e509515b8f8d3fb73988686334094ff09972a054ba9927e9	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xff39f3016071e2a90232d11fb0b0bad60185661c9aba658b09b75e0b922984c7e4f269f6e4eb652359649c278ce6682987bb196da0430ae9c42e40334e88cc02	1608206463000000	0	2000000
25	\\xcb2ed4f341f87f04077d9c2682c09c4b0df45f20e0bfee1e8df039a85fcf7611bc6b5350fe9709de7b73365c7ada82582506dd999cbd271c384cd8826412434f	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x5da517a181098773a7b410f56e2de2d728af903726a3c612bb3f53989378ef49414e36a034e7b32e612ee15ed290799d25be3ac75e7d19e4e44494d0214095d227a067bafb720b7b89844894fefeaddbe5a1495b2ebf68a3bf9cc7bb71890f70466db7e9aa6907a8e40931f978ae1db085f98a17ccdd9586453c1f088b7d5198	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xa6196cf2408c69f30c2157574f4c25a58f9465347e622429be54a53b654db2e282a2e81d7919f776b47171b011c7db2422774a15e8f22860733336afd37f2e08	1608206463000000	0	2000000
26	\\x5805c87a6fe22b583352340348d0802b1637651240ce2b4181aa355447fa3043dffa7910213f5c287ee9e983cbc8fc9892597330c4911b5f8464b258a174f89f	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x3449a2dfa5c29342d1782157d01a7c83909dbf947aff42b2809113d6b219757a4d2ffe44fad33a4d1f909d75ea1b23b2d40945791731eb7480b5b056b1da25f4cee048915fa5956996a8187150f1fd1e0ecc045a70552819afb68661fb0dd18d3bf569fe6881872a3cb671cd115002a49201f98719ac9656a48ce9c3640573d7	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x94298509907aa5caf14c1394766ffce78f9af258c5822fe8706f8e70f8b7f4081ddc27a5a5eb237b24eeff60f990b6b86e623f404734f41eb37e23d2f6a30905	1608206463000000	0	2000000
27	\\xc74384804ac869aeb1751f94374c225d1f2cd45ac75abb516287ddc64fcfe6ce66c44f1962c7b581bc6b6f9769b88d302802e120704ff9c99d23904c9e92417c	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x45361a7f01a17868981c26bf2d5b09edd70b4c8a950f28646ba77078bb266205ea953653af04fd939c1819e506ea70d73c0cee73809ae862274edabf6dbd9c313beda491e2746c134ee44327c0ad3cf501e4ef2d574926b34638f64a1024bcf48718b220a451ede1d9c7f3523ede4e9d4a52d672b1c457a06264fa93b99b801c	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\x09e092f8f1d3adb8b7c1bd868ff8442691dd1fc20fe19a959ee267d72962a1b9ef33a87bd06a373e8d1ebfc31f76a4a4c38ce65d4b8cc64a90c953ba17ced20a	1608206463000000	0	2000000
28	\\xe6ef908bf2507d2cac4dd495ef4c9062e52f3ce12f40fc0bb20d9e541023eef3111fe5c4018e13fa251f20c6b2ae7fa2676fe2de1050f337336129dd89fa760d	\\x327f331b8282efcb2ba5685c9d7b66fcb6f7d696137edf36f8cbd554260d8f19884da16eb5849c5012d46875f2a35a961974782d654586bea7ddedd2e03739f8	\\x1b924e816a0bde013a3f2b6c03a3a4a1803dcb424e2597da0575118ef9fdd0535510666e5fe0b4bf81b1e8b7935550d5ee58a6459ce836687ee8e61813d95739f2adb07407f9f01f09c5254989ea4e0bd2b5b437cbe0235161c0862e23c0c9a1a97e40bacdc9a94fbc5762030769c378144ae2449859471dcea9adcd12206807	\\x77fe13902e72d747e7c016e34f022f429041408ce7baef368936234dceaca516	\\xa080ecf778615d4706c69dcdfdffa5121867fec736c4bf8397eb3c7abd06fb6c3e253f3475b8de769df5ddf14a3ea9a57119b22bbce9a8a563df219da324ab03	1608206463000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x0e6e4778369777a762efa323d5e8351ec3214a996088f43b9840f7247348ec29446376615b602bff3a56de5c55d5f8bed01481ec5ae566d92996399fde805f0c	t	1608206451000000
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
x-taler-bank	1577833200000000	1609455600000000	0	1000000	0	1000000	\\x148da9ca70ea8e3a7b5edf7ec44bcb26eb41724c1ec4251b7f31c2b9fcd2e755c6d2a6325ea42617c0b6016f53b258f0d5e1d5c3282a719d832a98e3d702cb04
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
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denom_pub_hash, auditor_pub);


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
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_pub_fkey FOREIGN KEY (auditor_pub) REFERENCES public.auditors(auditor_pub) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


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

