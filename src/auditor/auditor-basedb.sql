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
    rrc_serial bigint NOT NULL,
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
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    reserve_uuid bigint NOT NULL,
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
exchange-0001	2021-01-06 11:34:19.635568+01	grothoff	{}	{}
exchange-0002	2021-01-06 11:34:19.741429+01	grothoff	{}	{}
merchant-0001	2021-01-06 11:34:19.916648+01	grothoff	{}	{}
auditor-0001	2021-01-06 11:34:20.046414+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-06 11:34:27.555441+01	f	697a0636-ed84-4fd1-8e90-ba8d923c1cde	11	1
2	TESTKUDOS:10	901Q64HAJ36VA6JANAX2JFG0VWGZT79QH2X4AWBY9G2AQ1TWKV5G	2021-01-06 11:34:42.529686+01	f	3cef50ab-e5f6-40e6-9790-3d7a839034e1	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-06 11:34:46.15139+01	f	1534e847-4b9a-457f-b156-fde36e9e0712	12	1
4	TESTKUDOS:18	2S3PWH5PZBJHAK9ZYTBWKY82K79XQKGJNTTPE5ABJJKH873S31N0	2021-01-06 11:34:46.845867+01	f	37b797a8-10e4-44d4-a315-0ec456c9a90e	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
40846515-5087-4aa7-b67d-a6b725bab480	TESTKUDOS:10	t	t	f	901Q64HAJ36VA6JANAX2JFG0VWGZT79QH2X4AWBY9G2AQ1TWKV5G	2	11
dff63f84-c80a-4eaa-b721-8e3322ebc7a9	TESTKUDOS:18	t	t	f	2S3PWH5PZBJHAK9ZYTBWKY82K79XQKGJNTTPE5ABJJKH873S31N0	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_pub, denom_pub_hash, auditor_sig) FROM stdin;
1	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8d0c87b48adeca880fda8d3afebf3bbbbbd64f71f225dd92dba6e81eb24ba26fcace7a4dbeef99ce368ac9583358cdc3e461f1736b842e893fe956ce516372fc	\\x9aa6983afb29fc2ab2cf4344c8ad2da97bd8e70a0c624fd899cb6d3337ff514ca6d5fd0fce6962a86fa0efe5cbc709d5e7b52f6f365f5f5c80fe2fd7e816d20d
3	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8ca13da1c6c53d767dfc168d4020750c6ea0a1ec0ce8ade0ab2863ccfd830446ba4eda466d0d8cf9f956d2e6d0c88feae7070c2b141592db9b94e78a8feaacf4	\\x0e82a3e38e4a532b220bf8d005f63d2df2f252a8a7e73093b71910c493918bcb807d075e7a4bc1eb11b56159dcf758064e6e309edb485278c6b8b0da140ea601
2	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x99a9529bcbfe3d4127431f24e1785d98a7f1a01c4ce5c7f947c31b0288049608f8869dab32e0b0d652294364068bc4d876402793dcf110e76a4f552f02ed9c7a	\\xee7c64d6ff948d2e991985616c56aaffcf402aa4a128c5233692a7f890b6e0090c76b5b792f310a2d35697316de3988f3049d4654d1156455a221ad4ba1e2b04
4	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3a2383ddd207b541e4c1d6d31dc96c66378505d908fcedbfb770f2dff07cf742b6f9d486f1acc7b6f30db62383baaadc84f8df69ce3e8842db1f9e0c448c619d	\\x8300a94669af5f231415aab51e99dc2bcc9a771ff710885144623e6a076863a8d666edbc2583dc6b56c9a08315332c992a564bf88d49953d7fc77de28c2c2807
5	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfb3d67df686a3bb9f9ba41c927d95d7fc05c44d2a59f6a8c207c4209a746ef4a7e8073a595aec9d9ce61e2067f507f8e3579243d1c13b0e45bfd30dac9a7df06	\\x08b44819721c408a740a3e89f292502c48d6a9733f8bfb32c58e019c99707fe709e21f9669df6d6c4e3cc1add344f2bb3d98fa46bab841fb1e084f5fffb76505
6	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf67077d2d1d78174054aa853f1ca401bfee4b81dec7bf6a3382c55b0f158003038137726d0164f63c9eaa00f3698f5954f70716ed656a9ab4c871f3df4b1d285	\\xee25fd3344f1dedd29c0aaaff4036c9481fabce8567958631f780d883cbcf88ffb419c89a4c0cff70fed0f886249d2ff71856a64c5e57462292aa56319313c00
7	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb2070479c24166f65c52639c242d4a9c4acbfbb17810c36382975f54601abffa658022927a100737181f1a8d69e842d27f3df738374281909e7a568e77579031	\\xd8ac4b2575a44698854d1022e9dc71bdb3b235dd58c36ca94da9deb5f47730f3ea0888518312ca5735653b8074a8e0eb70574642076084f5f64b202b76b5d604
8	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6853ce7626b67999e5939e1199bf477748be68a1d9ad5f7e1b484ea6e204ea66995e8f31fa50d5ad72b9805ef6cab326a08410c4d856f9f6d3b8dfdcbae2f130	\\x85fae423d35eb21dc6234cf522cbbe20418149c821a9ace8fb2c5aac58dd21949dde2ed2d6b46d19bf74000e40e5a35bc4ed33dd700f87b27304522bcebadd00
9	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9cd335fb84fd068125c32d0f301e364873a31c421f487125e43c5eb86e5f1e0cd22e4b93701a7e706a6793a18aee5f80a1433234242a28f92080c3165893d436	\\xf0ee8b9ee61d74559a4bd5b7d700789ac07dcc04f548d96d05f0f152c32c55928c12a6c143e11f5f48c93e8c04100e7e80faa86d043abccd6a2d81f75f10360f
10	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7022b2d2a68891ff7da401cdac57fc3312885b457000dff0c9ca0d5ef58c3800e973c88b02996e1b9294214166a09b5804e48b1a76ab9c77be7d1635c2925573	\\x88fe4f31cc4287d71f4dd6345624bbaccbee3edbff1c1dff1aed742e3a9cf5f85451a3057d0b7e45bfffa49452759984d58c3c66160c99063ee209b647f97507
11	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8fc0867ed56f7a3142a02d41a9f456b692957c43d736e0144ae678fa57f40b03b9bc8710593ca54473d54991e670bcb470d13caececf28d09f94050880d17099	\\xeda3da33f7f50523fca1e6c9c3dd6a1535efbb85b43d417796f3bab194dd257795a22dd29450db706ba1f95a05fbb63451d746a68b02407ee4dfcb1582bda20a
12	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6406832d0e7ff078c0448539cdd09db5e61a9b6e31d16f624735b754b0d64896ba4ca41cb7ed09de177e8060d480801f57a3080bae8e85a10d3ca76f6cf95021	\\xd6ab3d025568bfd91b08dfb87f915219dfb39533edf63a395d386bb1f0306b6533d011bbeaf406162841882cc1b6958835221705e3ae2147cd9bfa6d4030ef09
13	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8b9d43f16cd12385c32b1adb5d102fc9638b3f15ea9c8d32cdb70c7527abc23df133771f64900d316b0ab444eddd7d4080b5924983f22da4f11b12c68cc5869c	\\xa37f50aee2d30ce3d18cc4a5fb8e4c3d8dfff35f5933f8cb1bcef185fb612b487844ddbdb96c45fcdc40bd6ed6bbeddbdc7f92a562fc6548c0d127f53e230b0a
14	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf6a4c474a39e754050680b775854ab84cd0d3b1beb3741a5dde70fa16597bbc216ba50c511516ad6001957add1c27a3960341b4458884cde8defea5bfa727ea1	\\xe172ef2cb97f9e0b40680ae7b94ca529340d39fd9b4a9b887ee70f73b5eb8745b7df865ee7139af44447acb6bfd75682de08fb275a903c1fce27ce1a8b8f700e
15	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd552236a912a832c298348a47e95d8fb1f98e8b7a49f63c58282ce933a98612468b3b0c0172a0fc25dcc0a7b3f0e46f6dc7aee61c5a4652b49e69ae9ff7ea78a	\\x61d4ddac3d56a5c3d12deda3eaa6ed0cc552480bed6671e6a1dfd74d927c0dbe28210cf662f1258591bef7b8914427af56236d4eef9158c19e98a0c69302120e
16	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9855c419d9b0d1ffa59914ff67c6bea87ba697dd727eeff32dfb60511290f01aff02b3c38ecb19e4bae300a6dd9ada0899f94a23a777183c17b97acaf8a3c839	\\xe26ec15e8d222958763dd415376ccdef5a6b20ce056797378d10ac75e5f1ad7ceb8917e2e614c66c88bc96136c26a448bcbf1f80e9d7249845bfa08f53bcf703
17	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb8a4ee90401c54c130f041c430a4fbec201c25c809754e6b5e13040802a71da90dfceca209b7c4382ff93c69bcf46bb8924f53859be5bd3aa84d7571d36ac00e	\\x3789855a44eadd6a916dbf07ced18aa53a3f3514e7e54b24e9a4cb011ee052245074dd48385ecb6dc11cde5f2546746bbcfc3d2ccb408e970a3e22129e91a704
18	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0c9f69e6bdf50f1298296a53ac521028bc0ef88120c989ec9ba4bb53001c2dc4dd9bffa35947a878de4bac277e570acf8d24206470ab872dea000ee9c68e871b	\\x889aed17d069eaa576a8bc3df388e8a580537aec25a79a0068a050bb480c917962ef61cee337ca05b318ba550a9ea0dd2850e412b7f802f5f96e2a0b6984bd0a
19	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd6805ae6f091f43dbbadc741e605a1fd2f43e9cb607e0f4b154875cbfc45e9c3927bdc1fcbda60581ae56127a4760faff7ff8015e4de1a947475899f04b0fd57	\\x76233cdf85dddf4ba7a478ca95da6d8a8a8f28ec13fe9e521476820d0ef111c0e65db380a47d6a4a277cce51f3ac69f0559bc961b1b247780e87270bbb92000e
20	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x47a564b85d6e5271131d5a9181427bcd58f404be2a60885ca1901b96aa9c67e51e04249e13ac15e940d3d3be19939242ccb44205dab8cd5920723313536bc6eb	\\xe51c2bf4ef89bd7827ebfd260e2940634491413f00e64dc1b900a5cbc336285a656032343375a7134ca8a5fed87abc53211d90c15c232cf16ce40418e136d300
21	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc0ef7e89a59010c4b4315f22aad3523bde961ef61681b4b91e791a5371c4bb62523de1a2f1ad70f59d1d3533f1c349fa309ef88a51f2e42623ac97dc7cf80480	\\xbd9258c30b39500dda800c3cbb752b9d113866d7f4b56acc288eaed3c020fc5fc626fc7b5c102083cb35e24ad65ab92f5bff0a41e1a7c1924e503913b31b4007
22	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x65f164a705fe0c274560e523aebd217530dd27d9e50249d4d5134ad3564a9fb6ad65c39e77179961c695fa80d3c5cbedf463527be085b1abce8f9026bcba41e7	\\xd91c12e4ce6965a676009f45c8e135c9a80b8c1be199cb292dc01b85f9aa2cc4faf8f05d61eb8236ccba8e5cf2ecca876d033a0a39ffe4dc1e61f999cb05060b
23	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x10778221f83476a473d9658ea0d6a4fbcd532fb6ebeb3823e5aabb0321d77fd7aab3e886436ac73e27c7edaf6ab75ed2edcebbba8fcb1b34e229afe7b93809b0	\\x645f0e5a75d2cd2b34580ca56b7224376e72c13527e946000b7f858d2b2e874bbfee53b6c234821c7d3e922781eb131a444b02b272dda3d111da44795373330a
24	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x591f0d6f127356c4987a914403d4198ab03b615e6952e620bceae1891a4ee3bc03551aba275f80cd8457c82d628395ffdb6e3e1f8b59898f67a64c141d005be1	\\xa9289eaba15efb049165fb7cb4231cd66ea167ae6b29590f0dfab3cbf320d62fd408af4d908d7f5fd54cabd234dbdf4aa6607d0f8b5903d353a78d36bf68a605
25	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xcb5bbb4308553622daedc1938904366142b5ffbdb370ea649cb45847b33d5ed74b85eb870b7fc5a2aa1ded2b8c549575a70ebb9c7519dc2c82e3934de531f34b	\\x9d82c19e7f95c805e95e27dbae14152ac29c896434f2f89347af1693b87d37c78f9c4e9b9ff7052e0bd55b0cd2f0f768cd850e383d582c71b0c967f38e0eb807
26	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc48d8252e1fc5a5593f27e674215f1261ac843a873fa6d622078d747ae75165d25b97825107647d264af9d301f76e0cbd247ca8426e197070794ca24a3192715	\\x37143c337aaf0599b7ce27cc814fcebae35ee76bd26d558d3178567ca9ba59e96853c919c5b41a0a43de5e43ed1143f49a36751eeb9b5ef00c65756a6c053209
27	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4c8a6c714e5085ee0e0d305e50cf13852d97df2edc28f387922fccd6878affd2012fd356e0830694b51db2c79b27de5c2dc14f86864e7e9e74b3fb91425f1286	\\xcde72370f53c8a116c5110fba4c4f369c7b7bf8961197e281a6f2b13c661013cf3eb02286294be33d6ebc33a978db3c007d1076e2501752be016e2d70104110c
28	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb997509cf131bb78239df645ab8c8ab3480840c9705c66441cf429c280bb45375173a9f4ba5d4700d21f8492b5421e811175e1b0ef55fafa4b5ff02ee0610a46	\\xdfabf85e6fa799121f276bcef174e28387cdc891af302364212c57d473d74661273fb46789ddf5cd16bf3870dbc0defbde16df6b407258a794acd07f153ded07
29	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x816227c6cff102e9fd61d12d16ab035f536795be73e1a867b301d93b7955ff4b4176dbc4518ff5c08971c1241622da445e90fad7757840d32aaa08a5e4f60340	\\xe15cd772300885ecb18afa62ddd03b84a456e8823bfe3544df1d6b0048d060cf565105dc155c6dd30ffa17a44f414eae4cd193d624ee2d79d19caa4f3bac320c
30	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x306458bd64c7daafa5ecce6d6f11c7108a72e935c261edb3c9a918db07f1cc3f208c85c9d16cfc1892ac922d1ed6885a364e1021f4bed407d650302ff5aef1c0	\\xad1401d0f4f61da5e79f4f5e140f55acc14fbb341d246b9a486e3e8e42a6e907001b0c6d95a05ef4bf8f657912c824c6f2d0dfcf6ea0efd18313dd90430af804
31	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc1af2997fddebfb5c39c1d3e5a42ec9b795b4bd266795775077c04399b153587271eacaa8a42d03055f1971aff90c0623f61991317c376cde8855a2b388bb88d	\\x259a1e2461d91b7568117f009465306d4b5eb15d85d9f761ecd084ba6cb4470e61bb77080b51f9f40cf2ba92ed758109619ba74abfcd9899a48fc6adcf477e07
32	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7ee38f11b6473c93f417ee01f615bb8b6a50eabc37ac7adacd45663241d6bda5fb5c8fc4da4c5d28c44f38491480249cfe7ba5470fbc93f7b5c4d9c7d0618912	\\x2348cbc9e4bdfe76685274fbaa4cf1875460f6789767f49e0a0d0b40a4cf518d4e01f422acca70d22fdcd58797001d94e9d5ad04096a87b87f2550ea810f9603
33	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd8fe9316d94c6842799dddc9ecdeaa5968e0d8a05a0b597f8df5fed96ee08bd44ef0e7ebce59978883608f829505d53c072c4ed678e1d38bbcb60e9279c5c0a9	\\xe759703dcef0c63b8265f866fce9b2b2480cd277023d81f8c3b3137a952acf422820a0de2ed2ff4477aebd3c84fca9a5b2a142549aa74166aeeb8e1c49236007
34	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x186774aaeee49a7bc921189672ee546e1c7d58a75d7ae1c9cacee8382e48dc3f98a3b10dd9bd900d684ed93ee1f5e8ef61dcc6c43ccfed57aeac940a77634b32	\\xe103aa47dd6abb3d28d3675c461a158885a3a1b5532cb22b607b7759bc6d5f5d4a544a2af6afb0620a8c8c953dcb2413ae753780a3b98258bcadfaa1d063850e
35	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2c5a57c5d8ecc16563083762c1f655d41dccdd27348931140501415d4f0cdf3cdf6af8edd5f0450847fbc94ebb2959375d5454b44bdde0a2cb3a5df9726b8240	\\x6478231efa31f3eac9196f72789188b833d722d03ee2f2e92457643ab28f9bdd97f0d4b6dce54edf468574e4aa02217d6298437ffdc8d57763dc0de92252e909
36	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x44e46455483d859cf7a3c13540126212a31b2e6560efa739b6feead078dc37b19d68bfc9861c241135868270db6709114182b470de8d63b28827192a847afec7	\\xf881ab8d6e3cdc2f6153f16d2e09c2bf93f8d11adf400034436f83f1e4ed7eb2a0d48da2b87fa424187b3a230edafa14a7765e22c1e1028b7f802febe98d8e01
37	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc5ea92d4196a8f9dd9b94a28a35507c387aad5926bc7a5cc0888792c9c06e8eb20aecb31a7b111ffec279bcb1f1fce71a0db7d952ab75a59ffb52b78b307848f	\\xb76eb499a4df9b7d2838d63e83c39b5084578ce0860b276caa32b34ff256dd90945e41d3d8d128c96d0ee2ed0c7d1b453c8168677f44c79c3cacfba3fc78d406
38	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6a60f0b1e73eb1050c22b6008e00cc9114b5a0539c277f7a47e5765d8d877e44cb91be34d31b9d930b02963f0c08faf18ab71b7f9665b47e0fcbe793096382e1	\\x16d873096f00bb3e06443277a2d0b1141339edd9ba5d9254e35ef51b7e7d9ab28e3d8936e6d7afbd78880bff1b3dbc185ed39e48a51355c6a93083248752370a
39	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc0b4fa36890701a854a2f8f09e59e9ca77867356e32eb679c40d22946cd78d963d9d5bb82d2ef88344ed8a7eca08d8b4b4abdbe6161b40fea9d45fbebf73fe6d	\\x9b10a750bdf39d319507155776825953ac9053acf6131366f75d011aaf4218542dc38d47a1338f68cf0fbed13cc40dad6236c78e0b3e012dff68b81a6a61a90d
40	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa43516d948003cb76392b96e0ec50204e4b5fd1c153d09e456e2fbbf82f5d9024451b86d07bca42c25aec8d6edd94cb3405635825a2f0cdd4d3916af3adb35b6	\\x00809760d04f4544c4486b6e54bb0762c96b9481ce3bf2e4aeafce9e2d2888a282c9b58f01eb8d539ed7f81583c8913ec06ac8cd5b1ff383458da50b1880b602
41	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xed4bcc321985b26ea7e57e8aec77ef7feb707652482c4cadf7a2dc10499993eae24ef9de6a8178a3173927ff1613e524606400292880cae3aad606e300f36a37	\\xaed30a85f37c70e646f57abe0d8da7c6edac761019890df518175ade72ca01d504a2146ebda66224251915e0b30074c7ca5ceb4a813dee616c9bce8ba1cab10a
53	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x21a89c35acee47802dac3b900435238451f18bcbc757b78092c1d8b98733afbcb4faa680461241a31feeb2ba889166e1a305b98311bf6912c18e36c0edc2fd9b	\\x24984067af5f8bda316cdf9e753c2545f12c059582a555fe2c19783631de7c6f0a91d9ba1bd59a076f9a66bab469fe28065cce63a6d5dc67141e7523f3d0a108
60	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xafd9d48fa08f5e0a4640ef241dce9f443a0d3cbf64932e569f285e52329ed197ce28932bb9f24cc54b3f3acae712e68d00d305861453dbdc8fdeed66374032df	\\x8d46db9f5a402e420a0c66ec489c7bc7b0569c481ec5c237efd5e17ad6271ee3d7405f31986fde4b0512627cf959663e2cf544f680adc45fd451d5908839ae02
66	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0871b8d79e3d8384584a4ddd82945a4835f9d754af7340ff7dfa35388a7eefd3b576751824f1863e687206dd79be8faf21ca44de74d04cbad04711e3602a183e	\\x167b77ec85d9a4e26fe5b623e86b03ab450aba00e0adf93fc1150e73ea61ea74b0b4ebaadcb275819c92a1c0b3161d2d8931ac4b93ab2a4ddfa916c20af0e605
75	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7f9f18d1e05041811a3673d92f00bcacc9c59be0d74b0b1330d096e3e254ac06f55dfcf4c9a3a7aee4e894ba0dfdf0c61501e47b5eac25f8837d559fafa12a3e	\\x618a9ac171ee795627dbba1dd2c6cfa083033756841acb788a19778655b0810c19aa67f234a63cd9f76ea45e8c64d23c56a510e8a22575423baca178c13c6406
89	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x53d09dfa25fdaefce2a9e42f4dfca6d5253a28a5d5049e3d8f4f418176770c05b9ff8056becf22d888f0446335531aeb9747174f2c12b4b533afdfbb25c050b2	\\x3073dcc4da2a49cee2f9c6edcbe3cbf1efedb8987e01569734e36a2cee9ee84480b799ea3d5ba792251221b7ac126d737a13f8e3fc3c7a85c1e4375455a8240f
93	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8fb3923eded04c28305004ec34cbf316776357b572644280ae60d7ab03fe12366e7a69145824e9b9db785dbb52e958bce1afc259b7921b94931f14754151458c	\\x427562edef041e8b675a571a5e2604f29f2f9071123a0c22a48f6a2d7e819f6aa19c31ce012309b864d2942b7cbb22b2f36c05ad82627b0e73ad2a9db65d1208
102	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x10dc784a0ffdb65d20f325906d5cb99523ba7516b95713e98388947fdcd3e810ec53e1ac5424435076fb1ebf61ab336a837b3576c4acaa01fbb8f8a4197c5119	\\x4807a2ab62ee9d7566f2e22a7c48c6616e9076038a9a6f40a86db2d23b9a5534c6c5af2efa8c47118b241f4b3ad50561e42d8de1bd47203e0b5e7d3d6e3c440e
113	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xddf4babe90440876938fe5e0b4e9efafdd722ef7578fa17ad3f8055799a43291db54af9b16c9b152e9f6f2e268cfddb6c6061964571346ad7e9ab2774135bc0e	\\xc9d359103ba94dd28d13ede0f3918b402761f9b11514596de933d00945e4639ff1970badc4f158b84da9ee7e8b5a132241b0a90c768bcb6a1543bc107b46dd06
123	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x46cd7a5a8186f15811d08ded7b48ae682a5d18e0d3708590b891f151d3edd941ca9eaacd11d555236c456a7f1d4a3dc558da85c2211601653b92f7f4e6900801	\\xa3bfb4223181efa336f43307e3c7bf917c977bedfad94be73e545f69c2d0079debd8e9492d75bbd8a7e0acab040052f1547663dec0548adb3a95c72e36ef9e00
133	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb7909c18519270b1cdc0f9e0c5eb28cdd064d2277b93778e595c5f9007eb607e0f46839568a6ed0d1d602f8fae9314b7a173507c655994bc907c37f221e713aa	\\x3b9c9594cef0e306ec63a48d9948868bf2404dd35f50089cedde44e1538959b5da895b935e5b1697af9ad998e2fa150862633d05b4ec8089ca3fffbfd29eef00
187	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xee9bc244bc6eeb8fd54e81acef95452b0758f2213b69090716088bfed5e7667b657b7262c3342620d7135bd01dc8f5ed968e074665c990423df4cbc39c6c1d28	\\x2af2ad7dfa94ae4c78930d8fac4862cedfd132efbf47a43b0b13cbb72c828068a9c9ab9d51f0c090d41e9d0d581189745d1e67cc15c441043c363b8f3253f80b
232	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3873d6f8dfbc7e5f67be3ed63f040e8ab5dee1d46be1d6787d71a1ba0789537d88b293c96d796ff10eb17b2bc08b91680049c2d81abafd1ba0d080817be6d421	\\x2f426484a2bd6aa7bc17a052cd6e795bbd49adec0d070ffb9db0e981f3a0f10f3525d8dd6c8be330afe9d78418a1c68be0c8a95280fa7478851fe96a806dcd05
276	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc22cb533772d670f24798a16e936d424a2a758cf022dda9cb913861d7845a4ce45ea7f0cb6fc339f86e291187fbce7c6661754cff2d290c10a0d057ad9bf5654	\\x8acf720e8ae00b943b1da2d7bbc52035942d007d601ed9ffc72ba59b87f045ea8d2643f531e7f6983a643b1408efe36cc372d37f60282c9e69e358ca6b35930c
301	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x05734c43b2823ee96678c73eb4c15a83536ced6c55dc43d00bb1e9af90e0cddd3297f586b30cdf9cc6007e7104f9860038e5f28762b1d5c6fe50038ab95faded	\\x255a30ec79b17bea2d6bff5c19f9294b729864d185d76fefd2cf3125105f39bb5c3257a2278fd06103e1736511c53f093206936a3d7ec7e0c9d661a706a5ad01
421	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb106e4d1012a58f6cbeb11757143ecd32f677a6919d189ad8cb65eea31c25f658f3695573f68cc39558b5e39186de53035dccea1315f440156d51ef2ba391753	\\x7af3d3a7d842af9fd66f57aaac9238dab0c5a874083f53747019fc400545c13894655851fbd33a3c7509c9624a8c08a2b44907dfdb19db7f8120aa90313fa307
42	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb0bac1092c5c8bdf0d63de1eb08d36599c587f46a6e73fcf8c8922ad3af82eadb6314f62df5dcd84ed1270d1e32fb49b28f2e38b30ad06b32fb2ea9d924a9817	\\xd6f1d772550bd78426c09e21a25ac8ec05fc24c53a5ecbce286a7833493452cdd26e7f7b951435ddaa045cab57436041f1a4714dac04cfedeb3a4761dcd09d03
51	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x37a8de29f5606dfd7097896f6efa7bbaf59a9d862250af33f644fb46b6de4d8c37b471ff4ca67dbc44e2408c597d729e3d9b96d9e5ef1809e105f83a85c76a94	\\x96b9530eb0998e716d2993f91c792ce643aeb70b3dbc0f8f3d295f31c485adfd44882bbf7e3eeab008436f52de8d1bc5cf65cbc81a76176a311b31d2c11f710b
63	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x97047c845ff01d82cff83cd776b648f6593470ca282a050e3ad1c4f1cb9a05cf3718a012bdb457ae048426c4c81936f98a1db9d88a2c22c4cbc595bb0502eccb	\\x5be7c8bcdbaffba8d1402fb4d9080e7184acfbcaa9882f010f74c9278e03f28b9744fc2d0192611d4bf8058dd6d305ccbc846ee6d0dbc1631fac00fa4c1d4c09
71	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa202cac914fe77888b5d1f3abd4e7bc3a206176d9edc23c2d0caf5fd2baf45436ca19d5d6de8ea5748468d50cc5ba5d1f06b66a472c91c9647fb069707668be9	\\x59a3f55f779b1765dd56bcfb99fbc89b8bd56afc9166b148548c2e73f85bf16666716eec133f384deb2d1db6736a959f9ec15a1fa9be0a96df160d1526c58e05
82	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6c59868923f7f4f16d9f45d7166a9c957dadb8d788aed9a7b3b5f9b33146a4b19d79a1d766ab2d41209993fdbd24d0f4ecef25098757e6abfb7c9aef5bee55b4	\\xc371f089a89de2c6caa5124c6d95e11c11dcaaffbadee9ad219b9e5c338451cbcfd49fa6b2409d9ba1ed69959ca03824cfba4b3604c00053bee6c7f1ddcf0403
92	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1591e6fce4b73bc675feab9ee4606e40286e4228f69519b1ef6e442d675126f1c4a48843bc09a8eb4d2306e6f73c70a90ec7978eadbe5a61a1dbe71abc20e838	\\x2aa1b5b545ca8c401ba1b19fd88c9a6a137d1819b35e5d36a9bd383b3ecbb921dbabf2c194e32e5801791ea05c0e84f04cb370ba62be6436fa4b01d76ff00c0d
100	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa322e132722b6a8b62bb7aa6f5958e4b2197ccc41395e47226a35813dc014254aacc2488e6d0284e2ce2563b0a76a574a147b9e669a3631895c72c2fb40980e5	\\xa31f3503dfcc3fcaeb701de649b00b989ab3468b07003b1ae774b89b32eb2d21b7d00cf59154341c5809988f2059024e872e3c2279f995ae53098560d961280f
108	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1e5f3a6cdc4eb99fb9335f20449b94c89b03e6cdaae6537e9a885dadec17f6e77b633c4e0eecdb85466475c12f445d32bbd504598d0392af41a6c4c40c8d56fe	\\x20cc3bd405ee0174139acb45e15a9c216b4b2e2a0762dcc4ee7c2da0bdfe20ba77aea0b577b0ceafc0fe8855b4d0fca653a1d31eb948d3c689e8b1cb1e62d400
118	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8e75167bfba1d9990a065f17d4750eaf5a4e45363c90c2b8683a6bf6a62fbd07c389789e6bf19b707a672b6a223f754de9878a79452f26c81289af8200af8eb2	\\x705f85833d3b7a21e83ec441cfbf2cdebe78ded7cdc899a02d9b0f6462e0773550351f54db8e65f9f34c4387ee35731db106544efaddc97daef4762518738100
124	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe9b85ffe1706732d820eea423856626d00e6fec04ba5c67c29e4f803db67f3e9c0b403b169c69b12f0ecdf32f2bea6b7a916a7caee1c6261f1f5c074949c3289	\\x999375cd0a431e199e2c5ed8a9b4877debb75f54d1b75c08d3723f84c2b3634e368d8d11a22a21c1384ef2e42c03da069393df55fa795f9e761d86b6bf62a102
135	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3a814b972d29f180dd23238441ebf806d97801e529eb8685eb5e9a5ef0e56a8b9727c8efb7a15a60518657a59ed98984299347842d1f516ab0d3cfe2c852b051	\\xc01b6578c6baf4598244b25cd4203816fcea36bb22d88b2e81148ac1086993e022838c2da57c1b215c3688485a9a5faab911e0bf1062f8f32ce56f08cb44680a
167	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaf1807296dbbd21b10477063253b11e23a0fb276871114681ddd6b9cfd68ee64036c64ab15ccb3e58e4167a22a26327ab084d05a12dc6163c7401cf63add0f1a	\\x0dddd78ad5dd26e5a6f6522cf0180a8beca118dd3dc1a7b22a43816084832c8644b85d593ac35696357989059b6a39fedddbfadfef8ebc6891599ded8833000e
193	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x622b03ac4e7549217ae012ffd5de0136ceac66099fcecd4ad8aa70a9492404c0b302baec45f0ff2d75fd83862385960dd813afc6e953727e35d5f03eb69a1520	\\xa680fec4e4285b80b610fc1773137ebc38d7d8d53b6286f5f5e49130351b5f4911c3775bf50bca62059a0a43550574a8674ac086841e8f4daa1440a350213a0a
223	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x92f2f8ea334763e4fd4f98672f17ed75170b426c904dde75ccd425b0621e334796d65163973dff5f96b290577d73bd21513e6cdf315886da85fbc74607de405a	\\xac10dfd5d90ecc6cceca62841e8804aaa0c98d35b7290120db0f6e9149b759d605504c29bd707d5d218fea531002099b642d889d6722fc677c88c1a88c324f02
251	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf7346f51ee2a785aeffe24e1960a7b84d0c3e524a99184f60716b1c0453a98987304baafd5c5d58cbfb5e134215aa12ce0b9b25cc560b0055f042c939084cdb7	\\x0cdf66a497820d6edbb20cfb608b26910e935552991a3935bbfd9af4489a15da4ce327dba72f4addcc9c71bed484bebebb6acde39633de87edfa2f232d4c4006
288	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdaa937bdb49df73424494e985a11ee9c5fdb568455c372d04395ccbf60cb74b1f0f7d9084fddb9c3fa0264bd7c29cd9c37e2242d5ab45826e1194b603e1b57e9	\\x1f3b8f4fe9648ee965d15fe956fe584cfe0c9bd3bb64658ccb8dfd52f4c5e3b159bc8ffd6c77b145272f305fb34e7e498be52d0b2f25fda801f35c9597a87705
349	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3c476e9a6de51e85be80a973681861ff02d12df2448483d8a8e1a7bc83808dddbc069491be0bdf9bbeb6709678c0351241d895edd65f63f5fe577cf38f1dd06a	\\x7d0688da09a24effae012ca86955e23c3ab2973f2bafb50d83e03f9efdf1d614ba5b2b76ce7e2eb5adda6a0a337e8a565746e46959497608de0c61393b497c0e
370	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x603dad7278fca91c75782fb70496981977897716f30ffcb7a71d26504812f95549df764258cc466fe8b8f009660f47c7b6bf2fdd4b7be4acd82155ddff4e375b	\\x0b8a32c765619d26234e9fa14a82ff80241448eca32120264ad4b000111d78a9394b6e5d591acdde0df1fb841c3f25f17fce0777c61aa3d0c8bff53371c01f0a
391	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x220ee9d6ea3b85687cf2e49a5c8bd3484646c6e4bd6cbb68ffdd7fccf4aa1708df98d5d33fecd7b023678f65567692a1ab39fd00c7ab63b73fd706d3a3ef128f	\\xff4f415523ed9ead34ae9b44c51ead4106b75904a16e10e0e00b162dba19a06ac5cb059c3b91808a26e2926157eebe8b6805c30a381c922394a178b91189fa0a
420	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8c1d5d65d8c632da3f0d55b760a1dea6704630a2f03abb347f2bb4810cb0568ca4fe51577dbf9dc3cd3e7818c20530c447756a780ab5292acfdf61ace26c4cb3	\\xf7493d2047590c3092b2e235d76e2cf811cc3203fd5d5d555ab2347cab3d5707fab5a8f8b2fdfc093c7be1cb41bfc0c2212f2f70bdb0c7b3b996f9ae4af3ff0f
44	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x69a13049b2c90c298d696eeeb7017974c7126c549dc94f60d8b1d8d6ff5d96c4d05c6c473580016078426b360156830d865d8784998c329289d56ef6bf74791e	\\x92b4fe3d61e749f4dcc4a7be1cca019a66e5c10d85468c239c3b8bc20e4d8e121fbe5a3efcfba5f6201399f9fbbe6667264122f409ff8e77c509917f55dc7807
48	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5bbfe3c50fb26e187b4f9bcb3d90f1e163871204e22a3991a2ffc66dcf22cf63e410f85221cec1ebbf7eb79f2934dcceae2f0725630dc64aa8dbbf4ce8e5eecf	\\x18c8819081efef550c03fc8821005fda2a28f5da66c7e4274fef625171be00907725c621dac361f4f012cb46b5f9da645e2d6f6db17115ca9e4035150d3c9a07
55	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe34c2b54bf3f60786aea57c9319c2ac57feee65da32e6046d4647707e7b8fdde38dd3d9ce13f33e132be691eea653084e187cdf35afa2f54258f806d130baf97	\\x47537b40b3ed182d1aa5e725c893cd376444d3712a41ec50adedf644f651e65a3cdfa7cae9e1eb6a7565f5a5cc02869d2f55fa4480d29e32e7b429a9f0878c07
72	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1a65633096759748a6e011ef4eeb147bf6051a7e8c78f21cdfe67c569a9fb3159264b37109093023cb127303a88cbbddbea3568f9d1e28eed975cff3e73bee68	\\xe7361681ad2a5cbb0d4047887256b42aad6585754e519205442c2475600d15875bca62fdb12baa6f97c0318e4769b8e82fdf933c38df100759f9793ccb299905
80	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa6e9064d15eae17bc16b7a34cf1b6b31e86cea9d3aedd2b018adbed72eadf7e1596a6a7f7cbadaa8e7aff02007d631eba79e50d5b542bac754e655662a3a36a4	\\x4854280ea609f36581e35851e8aeb050c1bc0865914a3a2ef9d39cc9996ac3f3b6b337fc3a0f3c6dbec7048b330ba8d3db8654f10d8874eaf8062038ffd4b909
85	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6500fa2cb0a04f41ca8f9b0e1c426266d9e224f31d75d1336c2fb7bb370e5f65408c0e25560872eb20ae044afb0cc30ca654a66b4e927109f451f55319f9ff58	\\x5897cf1ea7d05a062c008c54484a94ac617abda18864a5346fb264d2d69cc06adf6142c961fb68957509f9fe29d8308cc482cf3ed0db275a8666e179abe7e00b
97	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd729513319059adf49e5f87b4f26f235ed79c376c8060574d758550a3e85e0c8e1befd5e2e40ed66c6a33767198f4201975b5a1db71d21ccca429da5fb693aed	\\x21ca38be01b99b20e114b7e9acf61c4d671277c41864265a75582d51747cd271308ae36124d12d13542746c80358bcea9901ea1a3688b9f828f82a49413aa00c
106	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa8c1514ce77956750a3295cc77ff690ed54ae522ad3f5dc2389195b3d830ad9cb3dba6acb19b2e32d89191d7da7cde02238712ccebffce58f8722810445dd6bb	\\x203f95ef83d0cbec478f5a1dd49d0ba8b3c0f678305af03d5e0f9f7647177b7fd6a469ca8249b7b28a4097216c806b489a4d24f6bccb77eac31f0e204268ab02
115	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x304baa51187582457afddf750014770032f61cfec5d66079d8b1e41b7378d0b4d33132bff067ea1120a92df77870248a054ea496545b1ef485a1827be89881be	\\x84419c5a9725f7d01908f2da2ad1914bc1e38e96c4d1abcb53def328c289f5d031db6439204e4c6da2be52721fb677a4c2bfb36fb9f8ba0acc250888ef163c0b
129	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2397b1962d44d355804c92cc7ed6f0bb34c208e28020ecb293d387eade4ab0bc36814b64b0c6fea032c5e2e127743d48a51209f5b3a4c3c524898ac4c7fb5fdb	\\xc0f29996f39c7ed148def20bcb83f73fa84376046246d1715ad22bacccb595275606a2bb8d48bd1b8acb1a23f8ed560294a209079c4421af3cfb4141f4b5f608
140	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2bb9c250526ae6d845f82b8de4204537aa0bf734d20ea5ec7777bc0f2f0783913677dcb5e07dc9ff14df4e729b1abef15bf5eb313fbc5d69f023955c5ef655b2	\\x02586da062fc9ed43dfbdbc85cbc673c01d6349b4616b9d715805c027d91287520301bc857e61999d6d58d46bd631b305b5acd0ebf74abcfd2ee0efa6d297905
171	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4da441e619163ea7edba267c4053c690231dbe0e5c5977754b48279c6fdd80f45dd2e947bb3460c3f8250960ae641d62b3ef2cad38c9d1dea2f0be9c21a9ba20	\\xa800077ac7c3e60b57af669787d6d12439ade93fd5962a2f2412c3dd72bd282ad2ffb8182203831e13315e557e21a3a5bb05e9eb3ef9bf753c837c40684f1b08
198	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3a7494f244afbb2123729b3455deea4abe1d71d147a2d4d95d49674054225b5318d9e62c0e41a6a3893d94aaaf67ee9964d2101a87708e85c5329b6079201375	\\x0218f0cdcbef041b0ce01bcd2ca557bf6ae5e65dfa95e0f68aa27ccaa973ee89d3007d2bdcda070678c0ad7ae096a8694bb4e7ce9ddcaae1978954b96d04a30a
214	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8ddc612139087fa3cf71b55102bb5f2906ccc889e075575a010cb3da44b4b3f02657b851a8b8d54d55a248a58981b688f38c37f9c4a3c5aaf1d52809da956ff3	\\xd935933d759c746797e3f5f8ae058d0763ede33990721df50ed269018d43b69cf1935e91fd9c0a3ace8477f21873bf6aa2748522b706f6c6b915d3a5cf13830f
241	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x18642c08949d5b06aac8416c4ef4e6b02c9b8eb0d66f96ee0dc052eff43fb7572a040ae8711f6b95e0e27619ffe4fec85d1c639159e7b1b6d20b74c32af7477d	\\x05ff019e5f73a8d46b9fcdd2e893e483f35e3a36459fafa785df320081f719ad9278075d44d2fae483fd4567f894f0887e16962df53f37953b92bfc52359cc07
267	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x65f92954ccd9d291f1da136a4382ff6df621bbb6fa9cb3e521db9d1b4ee998d72294f74ab13e5c10ba7a1fbabc2cef04f2616c6e6e687cc7f5c2b15388387900	\\xb6e67123be5cdadd727c1ab29248411bbfa55ed1ad48828dd6c5bff0902323c8de6fbcbbd9e48e831d7bb7500c4c53d0c3db9d43d7c9172e00b690c790550102
293	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1b70d5c717dd9b7684184a84c450198b000cdb3e5ea09bcb6efac264437d1e2d575e8ef04d46d4898530c011a1179a1cbbac484fa33dfd28170bf574ccb69219	\\xd69c4d6db8dfebd8ab8a108735071033f2afffb229528e80b93afc1fb766d389171d8a303381b215c9823e0d540780e6834dbec67f98809035a99cb724565f07
328	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x831a397103e9e64db1dbf3512925bc7628c434b44e6c42347deaebe2861e1cec7c48aa532fc8c1eba328d15a8902668a2144ec3832b6946688dfb979567175e2	\\x92b786b9bb52216cd2acc3b44cfd7857e0e770510578bfd306732508e425544a17f07a5f133bbbb65d2ef746338a48ca1220456591075571fe18fb5bff443e0d
341	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8065c37f97865215b31835ff2866b8d149993ce04244c66fe617f6aef84b7fb116a1255f69189fcae8d0a49a99b05cd8af47698bd359e2ed6fdb22015b83eca3	\\x12a9b5f0e812f7b21c7a8a16916a010d2266818b3a7aef9e0c742e3dd13faae66c330c2b548819522fee8a677fa913b6c33e147d01461d8b148ac3989b2e1900
372	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0ee0122135ba7c17b7cfa19cceb750642ee770bcc006bfb56563db91f1748279f52c7b02fc7065ea344871af9b97d422e2a084d9c124140ecb7e1a36f453efbb	\\x3ace09c6563a45c7eb0d65ffb1b7156422d89009af3602bbab0b2d73e876d1bbc990ba5f2c0c367be1359a2cdb1402b6a30288e6283ec735d8cd3d17c279a20d
397	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x56a57718ec2ae7c697d4d9f2fc84e12504eafc6730c890c644008d889e8e20ebc165caba694ef8e253d15b365b3944de68129961aadff8e586ed627a1a7e9dbe	\\xf2b6cfacd26cae28d7369dcd69717f14c3057fd52bc65cfca0c544329c694ed383c95e61e03edb02ef1c77cac7b0baab92d08eac1ad0147d489c2fe184b52d05
43	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x32fa94130aa90acc9bb21cc290db33fcbe42f6722953c5e8c257a327e559975632429058b43bf882fb40ffa4e6a5e150dca72d01fd0044b04aba394039b8476c	\\x81e6d63cbf7204ac72cad2358f1479ab640fd599bb48c4afb6480aff0604b2a0ecf5396547465f3fccb9957083049f5ae8e9f1ed951af0ef4aeed03c34044307
54	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x058b6de74f4ad6d738e69b4a5aad86794f0c84f8a65e14dbf32d3518ef78da260e2183ecf71ee8f2eb30a2af98f4970adb3868e885570b1103ddfe22cc33ef83	\\xe3373bdf951758e0e7b75ddb97c5fa399584b9dfa0c10bdf4d5814fb65b5208ee74d37dbc4162cb0a58193c1b06476383ffe04b0ea6d26a3ed4c4b0b8b63b007
64	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7156158ff95edd3f86f9bf17bca9d8a766f58893689400f2532195a587929521d34100a657a1e63e39441e697941426a56c7a3577a418513a445236355d0af57	\\xa1b32f4775ae26ca795a7152da81ba4678c1e2d52e89ec1f7a5900b91b8f0bc87f46fe4f08a7d5a62e81cf5927c9138bddaadc33eb4c37620a757227b1255803
79	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf0c2aa72a2f82a05cf89be6dc54fa16e89960fc33f833f15b7640b181542564789355a5fd5a3c2aa902adfdfaf1aa8c2cfed78447896ce89016fcb49a45cd921	\\x8dee16435a8fd4d9a54dd8ffd14d81f6df80b36ea44fe26a1537992a9e340f5f7b4def1df789fd1b2bfcc8e7fc23432740dbe7f989aa65a0ce4fae0b5185a201
84	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc011e5e7c6aaabb5f6a9ecda08d81474c1cbcd1819906a68bf79dfd1ef8b2cd9ab1189cedb167ffa0433c0b65af53e55756f707aed5ed5ca74f68a926aa0fb28	\\xab58a2c6e082f7d6aa87a87222b8a20916c2a5b7b22fa10ece9df2edd0d7e477b0321faeda9a0b02bb2539f7d387265b7b66c05ce44cad481362d418401a4201
94	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x32644d2666c3b817483257d2cf1d121be6470af501f67954759655e57cc811018f37446d18921fefbc1e3db5ea3ae69f8ba767fb31ceb5bd6468c81765840eb7	\\xb89d87046c787ff48419e601842e82d4ffb8d70b10477460c89726c9d3bf53a8f8f1aa2e9258426b3c17bd56dd90c031d88e557b91d0a50fd83632d158701e0a
101	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7aa21c2efd3d0f50016a8f199ebe83feaf376585f13dba837cc959a4f2c80f66f20cbc6853e4a69ded01bcf66c3acedbfa9b2ae36521ad9c00e3d5e16b68de50	\\x110372077973681cd445a260e6b06eb8bd6c68df16de5a6a964dc42e5c2be93c04ea71f5ce0029f76ce9817c21c77435bb28512ece944e48c51a3c340850900a
111	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb9971c38cbe32dd4e55323aa41d251dc475e66efd7c945e87b11424c286ede57f55b12cc78459bc72fcddc44db7e30e865b7129961db345a3271516a866b00a7	\\xae0f4d8dcde1ba89e458741f7151fc797721d4664cfc79bc43d518f9863dbf100bb5d083438a6e9f5f6630ec4f7020ead7fd928f33d3de7bdaaa72dad5220504
119	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3df58d16baf191641157e059da56a0c1461f2d87d23605c9afbf1dc033d4fe1c697f22488c19124e3809e481538ecc63fc703dc2873ce52eb0ff7bed62bbdc8c	\\x270bf8e629828c03eb092d82fd66a46467ee6e7df3a15199a3b00420a178f5e867ccd1c84fe0982241977f9a9f2639d137e1ef19501b1a0903a3ccdc9b8f6609
126	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa67af8e598d8e3dba283cf00f686eeaa3edb6c1c711a686238cca1a04dc42ac73f6a7afde0e88b5758cadf637e0904f909dda01b78fe7af11d19d82548a6b6b6	\\xc981cb6644df5e84a06c7820c446d15f6e2e758086c51fe53448efb973dd001b2ed7ddb33f90bdd3234ca7d22dbc8ccae3044946c447b760248aef9366da8304
131	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbaf1b09def16bc6e70c9b0c8ff26e8e35b4fdb0369503fae4781a0113353c8e609a7733b62a69f6ba9455af902443484fa1dd693f2a24ca26744de8edbdfd5d4	\\x6aa173068e77b4aefb953476eb22574771a800fb2b3301dd2d1019d7b70d42e462913e9de8290c3d0752d46feebc48d392f2869cb56629151a943df01e17a20d
136	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2ae8eabc63284d6324114e69d0a21fadefea4e86a9f44176a985782b060be8456a503b485ded355477a234ec17da86277808438a11ed6bb6eb43f76352c8f743	\\xe0d2b2848b0b126d2d0c98e0592f7cffccbccd01b37747c8ad790432559cd4d095b32d07955cfc8cdd064f2416e7ccd951f8b5101db556fb0223e7ba9272a607
160	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x138e1805c5e4cc719145674cca1c1c1528f285bdb4cfa1dcee1faf9121b8db21c98f915af3da95e4c0f43c3dbf65cac945aed1d95447d13186fa85290d1efa38	\\x74c65bb234fe0537a2e5491c0d3c373058c9d8ecfa859c8859d7c7c8e377b7563c1f0acfea3cf65d78aa53ec523b2dba42852b242e8c940c26a589b7eff1320d
176	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x408d97c9408ce8e7589aadfed9f03f246f87e9327fbc1d0482b983f3622feef2c076a5ff824867108aca28088794f0e6a1b76c494526d023cd28f10ed69f87cc	\\x659ea8bfae6ec9ee56f51ab202b5784376adeb8aa4ecd055c36aaa300d5cdaa002e19140883eb2e5b3cf81b9f6a3dc478998215c106f10d4aefd7f673d6f050e
184	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4f03e762a11bfa86de60cba317badd0344991d7a4ccca6855a1cfd5ba45924ff0f470049c4eab22526ea3de9d39a709668707191c0be92e89cd41ae2f13632b8	\\xec85ac3de3f8de0f3c97abbe601cc3080f6fd17e6ab49e85a27825d316f778c92f3e660066837eba5d2a5483f45d4e8a6dd122a8e4e831ba5c8a1dc30638500e
209	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1c3175385ba9e351c5fb9aff7fa04772afb4b98890061ea0d1a6623658b3c3454e2ac095466c7839acb3afc21958fa50b5dc0200a650eeae95f5f56c8bdb2e90	\\x97acc4aac833b6e167de5c96b8e7fee8537a2e32da108db186f24d9417e671cebd645d3200977a013fa19f42b76ab063f58b28d84eaec51834776df2f220200d
212	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xba081d746d2bfb973e52325ae287a9748aa3269085e2c95eb7d5832a9cfb76fe7eff01edd955c305c4513fee298e6c69e9639e3bfe2b1bb20c63e19b9dcebc3b	\\x9a0d31fb6eb51e8d0b18747f872a9fc225ab97f856cf5c97bdb73feaf7e99201360511e1fa4ccb6c6c53ecf78afadef3db41d416e5d0c544f395a2339348ca0f
234	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4054481dbdc2db792e99b7bf6fe757f853f12f40d5d9113cbb17766513b28241067ba0df730f9af81da4e11a27beae242a6a6704a019a7ca95c50ee94d0191fb	\\x3258202ea1690360a2a3c3ac640ad1a6d0f66f2c2d5889f16e84d6f4300a973faecffe03ea6809e9e462b6493a354b7926a641d4d7f79e5590e6ef06eac8370c
238	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x59f46046a4cd538884089274bae0c0b19d4f240bf86d851dcf2943b9582db7455e86caa97b2bbb839314bcb08fccdd1342c15c087b41a1d189349113f0022018	\\x2eca23a5004effc697199f13fec9aa050f573fe394a89d74620842d76a6b3b9f22fbbf1ed7467ca5ac8da0bce4b9fa4ca6dfd2ea636c3b34ea7d84fb0243e506
270	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdd08ce4706884ece08824a44d6f0b7797539c45819c3fa111a7f66681f34f156523c23cb1871fcec5ac2f553feecbf63f22749461171fb1ded5f29041c58aa49	\\xe299944d1332e506e0b4113719c103decb0e698ab3fa9ff7c8ebc2fb9fe25ea0a5f4b9fe3d623f930f316a45df994ed250860efbf68ddba84fc05887ad935604
278	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc7626db2a732b91560c95c637456d03377d5f9647c5e5d7ac3e67ac9aea9497380e16ab84dec9bb86490549747333a0c0e3bfa0fe1b9f98ddd56003bf971c146	\\x151099ec480b60d1e4424e5f94958a9c382592d15494b140a4a7a357ea9204f75f8a2e454c425504ada69dc69872e0fccd8588a5b7c32d6a9f1257b66c84ec06
298	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x98185ee3318714462144532572648e5b6320fdfaf458395911064b154c837d2be548b0eb0f397ce8df982e4238d784e42bc7adeef28b8d9b0dd90d471c913807	\\x486f1e85bc9f76fbe8f4d7fef432ec3776d77c86eba2e07326ade2ed19c75d61fdd78cc0eba3e90a37da50782ab0c0c6f1e26d8c5b66996d66a7191fb4dc830a
307	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x247933565840855ea46d546e930d21eb9bb9d4e74c7cbc7694b847871d627147702593971101279e841da60707f8248588cca6501e642ebdafff7b69ec79c3b8	\\x14782035d394cc0025746213592989266c959487eb80a207417176bb493edeb832aa00b61cae1a79de5de081366f980fecb189706cc6c24a13efafb72c8bbc0c
336	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4a0b5555c36a1fd97fdc8ba87ea2b42177218ef8655983d37c9bb587434db6f2da471208a40b637871fae507ce4ab35add3ac9b89d9a4076b2b7b66181a20972	\\xfd5c7a2b0fdbf5b945a00f5a1a3843ad4340514cbd726bde86a5cbad8ac0f41d148770b838bb28c9a279dd7b61eda9acf79689cf68d576668317d102885fc801
363	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5840e1b0f285c2417c693b0cfe0655df3c6067a47929f444af81e5de981a270c4b19e25216292028a47939e59bf29a3f58bf25f0bf37389821a1f1a648951532	\\x0f90169207cdc88c4762ad3d2d3a0f36d63d81436cceae41e005cef329d0ee8be15ce299fa8ce644e01d12a84a28d04f2b5d9537a71a0a40cc18c0cfe8b2fd0c
389	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbe5e7b4811daee9651064c6d4c3d91b1b00acf452c3c2b450df8febce456e1cf3e6ef44ed4e21d3d2855dcb92453b1b52456771d1b24068995c42fef667bfb0b	\\x76516de352213a4f8323edb9dbf8b947eff98ad006e9af9dbebb21aa98a881c0690d251a266df85fb656f6bae6f34a5734f6e7efc12cc05f65c64ebb97ce3805
408	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc37f584ce6de8aef73e5eb6fbd50b3be8f2f7c8fa58d59ae7e7a566942e1f56b824a6812928d99d7b3caef21ee80b44dd609e011d79567d2adef20f5b371ca34	\\x77f2a109431f0304732b392921b6ab71a11059fbbc20b663de621d047274a45556535f6d8fe1842442de1fa3f3d13815cdb18407b241a63b2a44198a78f4330c
424	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x023266dbeaffc1b55a609558f891d6536ca45c0667e8f5a242dfa4120ce1e8a56b649707a2911cfec2a9ccc0b3c0ba144bb3ef806c27502386b2d0f24c4f5faa	\\x518987c8909dc4d7d83940e83658894d687bc8ee1867a164211fca2bc4b5752031dffb122fcb6da8c51c73e04eb90da9e64d015a060d9263884f097c1d8b3b0f
47	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x55d73bc5535cba2ae6600f3e10228310632df7900c4ec90b03dfb6283d5967f8eb85f07af68777d6a3130db75658a81f61670ba987322ac6b5783b96c2e117e1	\\x98beb4738eb5fc0102caa41bf50eeb226df6666ad4030ccefcd98c3fbc209d53fd4f505bf5003987ac6af4d39b0b4259c317897b7de6efabf87c03bd3b036005
52	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x62b00efa832f53db7ce3d22d1374dcb5f6621ab67a67cdde78f51a0a4e2247f97443e13a33a08ff27783147898b6356f6794a130ea29791701dbae63385eca99	\\xdcb28e71764315317cd871e1e24c8f5573d861bca94a5e3958ea80f3bb27c7b395a7d9776b0296628e6254556584b6fe5fc78c4d18ae5e6cdbbd44097eabf208
56	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb8a0aab52df4ae804cf94ac6be2b447205d1555bdffd0e6f2b876dfb4d4adf387810a1baac6080e71005e10e7a08718ce89bb6fcb7f878dc76a85a3808a48750	\\xe6eb2da0f4c58be8cbd1106b22eaeb5794050216ccee045cfaa652daf56ac21a46bc316596a6c0af20b726b8065bed56650be61ca3b5ead23683d4327c256502
62	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3229b15f113e464d8b1053e5dcd5e5cf9c85fbade108f09fc597d172b4d685880253424ab403406f6e6dbdf3108d0d49923a6d08d8b8e0fb331d6ec5cb950ef9	\\x4bd34e906d8222df3673351fc774407db86f7e59fd3bba9ca3b5da4f89d1b98475f2445bfd1a7553f690a88c116d090fbf7044654f4a59c58bce956906e74a00
70	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe696c90c8342eb6bea4912e317d1ca3052751879f8de7ef731d7b5f43eb06d55c9d5952cd661fd61e40412cef31a977b3528c4a8d8e630e43135119bec7295ff	\\xae3e71aa54eec0824249455899da79e6c03d8bb42a227b636040abec840f7226d6080f5835db1b58837206084983cc77ad794981db749058c7a7b4751811ea0f
74	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x022252e12950c914940601191088e31b9b8ebe9afe644abf9302fe4ce65214eec0d5d4982aa5c22644564b5d8729eabd1351d9ca15a080ecf7c0416324e800ec	\\x0991877b16d53212a8c482a75553cbf141d5f81100a3fba0b7a961e03cd318eee118416779872f8af63245ab7b19b158bd71ae9d1fa7c00a25088bd9de2b6408
87	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdc52d8ec98ab25943acb4d359558e27af3656bd79a4ff857e5443fe0a00a71830844421fbe915abfb74f176aaf1f9f42824ee2c16a764a5a46080b47549f2f21	\\xdbd2ffd9ec50476e3535254ae1c91a9a85549d550385d6867c473886a7b156214c097faf0f6aa2c86e88be429d16d7a346175c0ed17673944b1273aaed19b207
95	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8b111bf9333c7fc24b266bf074df084a4b6c0635da65c4a9dbf9e7f3ec32f64c30a15f7c27cc8ade0fdc2c3a8840c85a628febbf673831e3975896d4acb9816d	\\xfb6cf33ef63c76c84e170b0b2be9d343749df360408c6df12d623bc785fcb8462c537fbe97444f257c90246f2401ceec1581dd23df0cff620f20adb9d19ab705
104	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xce01d82ea02e38a9b8e74977a9ba9b3a506bdc7cce18784882d23f6d97c0738c8e44b9fef46284d1fd2b7b3e4418d8f9be223e0fa723d1115addda01ae0487a4	\\xddedbc7c1793d380e1f05d7347f4c3d146bdb9e2b12ef0bbf978e6baed9c4f96fefe85f045fb1919959e66ecc825a934c67c8d8a086541e747abce77f910c207
114	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc9f3ebffd1e43302c024cd0366116b30813503d0c73293053c1f9a6156368008dbf1d6306e98ab1827575fc38ce8274fed7bf13bd4236e5d7c79f69031b7a44a	\\x47978595bcefdb77d99a918032b5ed1d54d29da2045ba1e3fc20096d0d57ea54ed755e93dea4f00c9a093a34579066028d002fdf369defc29a5a54253377990c
128	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9e9299ca402fa8e54de67c49086745712e89d72f8eaa7e6968403dd1c7d354109210d9b21191f9d1b57c4c24d9e02bc012e9eab765a96ff4e93e811c444fab79	\\x51b6c3aa7c627ebdb0df84f2cae43824a1c3042102b4f4f8aaa44801e011b30d02d112f5c6b8fb146d8989e6832b6dc6bd248acf402982b540b14cf69d99060b
139	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1824979bfb4e4e777c8b0c831bcf1762e9f0caefdf9f8af1c171b97a99b4250dd2a7c568a539ce88ae212d7cc9e777cd8b8331715faeccaf16f1cd52528422c8	\\x7a5561f01f05cb51dd8d1833cc102c54dc4151be8d845dfa4d959966a49dbaa5d9906eaded57ead817b25108e38b1e427ec4e332f78a41d4b1f558a9c2813d06
161	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0e6f685e6d270103e09f78241f49a74c11fca230d8247e5dec1c57da4b21663a22390a9c53d390e8e91c73aef548c0f0ce8016e4ec97e38e6172b55c4689f884	\\x07f32d8eabc8504b7964ac1cb92e78f5463706cebe0ae7498730da1836457c6b5a6f8f85b45a030fe5a99dfded025827217503c74b01811299b28f717783dc05
185	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xeb50f4b5465ebfd8a139945562ac1bc474073edc6a6a25adb72bb72d1fb6bdac104e1ba99e23d35e6f34e64274e2ab6a01c2948165109af2eacec0815d40bc48	\\x94b55674fee9b906b26339fc2defb86c7c7d798dda38bc43634b691df0fa11ea1d91e3c37049701c5c793a333f2da95093a44bb2d35c7590ced267dae0e54a05
194	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0b92530642b06982c656dbe18ec365435ef8cd4081329c2bb399f224855b53e07bdb4c6d050488d85d259ed2be9a89954e2895641d9c6cfbfc52378fa666d622	\\xed4125e2d6c6270d3d654d4b508b36fd1f03ac06ace8b23bf20bab5d0f60b3c01373075291a08827bca6ff3c84327c2591a8d4bb0e942548f5f2827c9d593201
213	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x60f377261a36d4b6c30300bc9d2e7d06548fc51902a24657ee0c6547f97c808c7b9377d748d4f816498ae63b599cd3992deed134af7b32e4900eb61f2987e66a	\\x1fbf222eabb0e2a05cd50b0058f959705bde86f074fed8af4263cb55fe5736032fbae381707d54a5dcc75f5946cd9a5567bfa93c9b739110f1b7df6871342f06
218	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7ae571323fb7b631f99a25216e8641e01b6c3f328dda9228c71d8631996f8ceb912175f0cdc1c56f03ecf4783490fb64f55ce7401c12b8589cff242863129e65	\\x1a5727efd34c26b25183bc6ac3dca3144e874b5786c8546f1dc76228245e0b828dac1f879c132034b1bc5fe2c08f9464883f935048350e20d051280e0a1ce606
244	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6c0a38b890f710929a18c132352c5cb3d98165fce184c0840dde08a1ec36ea5227a43cd326d5623b39fdf2e03d2b6d8b8669c86f090afe374e026c3d8f42a250	\\x9ac850e3c8bb65bbac609882989d19854dad7fef472289076a80834d7ef7b0e19b53fe384e46abfdfd428dd1f163484b857cd99f04bd3b99402f0ed33fbd930a
256	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xae9a73b0cde09760a47dd3ec35960226c1bf6eca9f942e1bed11261e3ff89f1082f7a01875b6276ba227b11d8f5e05567f0f0546e6b1de968c01008c9d704e84	\\x42ffa9f4be76741373cd02ecea45f235f4c985fafa2c58d735c16de55e0ca05b31601ab2b968776a6ae0dad12796b4119253cce026e075b09638e4a29779c50b
281	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6aee838e013e83ceb210458ab36fec01117e14e402b8beb3501b902efb54bd2abc71d4f87ce17c58c5110f6ba311ac52539bbb7e97b5d473ce484454cb4bff88	\\x432c0a4b35e5a52712f6aac9d7985f6aa017e306e64ce17bf884321a009892d5c65e6efb0af92c15296aedbbbd3d48da2058bcbeaa0ab3d1194070b388e51301
282	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc739251757cd4fa1810cadb03356a1b5f92b29c0491643153a0b35ff2806e794cfead7e9379b5c7be62ad8d4cd54d5c6ba580a58ec3e2929caafabe3dd746df2	\\xd003c3f0f87bf332d436f69811f2d9aa1a668121e15213e2bea628493b0980b44e8dc923213cf1f298f128600c48f45960b6d9cffce906f9013a9a8f5092360a
343	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd6a07b35d43bc7abcd1fa3bd3db5b2eaedef1a5821bcb68bc41c9090bf45a39813957916d24e3337e7dfbeea4d00f90e41723e50fe712f48e3f9e4a31c5734c4	\\xd155c1278c0efac49a75d2181d87885e82ad1041e5cb4de848c67b2c71f2362ff82898688438a80089a94f80606e164745416365554895b978be2df4ea5b1c0b
352	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb88be71cde3d9c220a772c394bbdb18af413e4cc7ddfb30f6e3b0212837c4421886826841d2a83433e3429757573c2596efd5e0c6b8f2bbc337c6a2e102ab131	\\xde1cbb985dd7261bd5009aa47abcefd30d70fcce06c96f13190ba2a68fa423b5bd44e5c0e7b1ff918646c6f8957fc61b07aff58671ae5e40a7066c27ec72e701
404	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x306ac2a89337756e8fb9b384e89897e3e2e68a3f8ed38d05a27b397f0beba6ff6277ae3fccafc11f1a7ada25aa1fc4ec22198827d413f75156da3e8450a72279	\\x4b2ee09074e73753e2278e289f527125b3644751ec99ee7def09e3d606d82d89303b538a8821f88525d8ac7d90a736ead792f34dce717dfa8c767a71073a2d05
46	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc309e7c764e374deab3a02ffbfbdec6b6f42652f35f2468205cf2ef6e2e916425126adb490d37ea675b968c6e426406465add1ddbbf880f4f3619a069a1cbda9	\\x1cc18660982879799787728f6437b856283eb4f0443b2bec63716a3c901ff0e86982978d53675776021c1d7719dd121e259e1b06ec99d20c41eff83266944009
59	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7a9d277ebcb901c9a23dcb3018fefa57eb09f64efc0b7a30709f21c38e1f1cdf6bb87c3d450492444f63d427848af206a43f2d68011dbf6fbd40b81afdeac018	\\xef4deb8d5719c30bff7af341fa745c987efc0785e33e966854bb30604b9f185c274df280576fe22399a76de88b330aa22ccee2c00a212f1ba90f4385a5bdb308
68	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5bec64da0df0f734401808975feda6baed91706502ee4df062395cbfbef56db8c1952e1528a04a89b23cc04f32566ee56146814c81d8084ab3e02325574af467	\\x2530dd3252f4a1bd6ca7bfafa4c312415afae857ff7bfdee8a5f1ab58ba13e93acb488864a87fc477a4bf4d40571eccf225578c5030042d2eb6c8266f42c200a
78	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd06d74d3f75b168a3ec7d4b30d40e4b8218343e2003c20b2a840e2a410d1f7371fe54f921ee1105c5d5a467b1a244151813045d637dd5611c08df36e9b6f4852	\\xf8a8d48fb7de22a9f461062359caa59b00b6bf9faca7f9fe980114204179a3d677c7bb6604c49b72126dac5ffab94c3698c8aeda65f93513fea07bac75ff1402
81	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5bcc4090d00aea4e58cf2975a81829c5471a0293ddada877b868fa7e10bcb55bdcc46c34022d466b9d6d8322c9f7160af08c1d427b7d7c1f89a3f719df8de8c3	\\xcb5b9bf48336cb6ee0baaca91ec8a8aeaad4c301e9d615bbee79f868fe0459d957c22538cf62026712fdbd264df29483e852fd06fe7e82c8dc77b86807cefc0d
86	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x47794359e511d8f2ed98a3c81c0199851bba0d24be3e310a8c101029d1fdf36bd15a844e42f6812e87b2068f9a4d3656dd26531eb3aaaa12dcbfb7ce46e983e3	\\x69fa0b02c27c03c10f294c9d827a7f3e12f422fd01c07d2330e239f83eb8f9ce1ee3f1c8b4eff4d4769f3e60b3d18a693f59747e5653409c1b7f1cd876926a01
98	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x473067a19268c966aa39525bbbbf754f7d862cd4975128a8764cfdd52b94631b350fc9100fb6680e99ec35112253ac1d8d625d2b2f05fa8aff2f1154b0578ae6	\\xbc1cf89d3ded3af50e9d83b884b5887c7e869527229eb1b41e3d77b9bf4c72ba42c133d40b05b22a3dabf18bb0a4256f1eca1003ab1aa6ad6b3796f6c70b2b08
105	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x38f9d98dd2c85d50f59f8f45f8369ab245190d1ce7f125e627bf79a40d007d19660734d63ff4aec8916d96a9a80a5a7c1c1e48512a094453ce34f56342555686	\\x5b20a487c1d1460ca57a797364df65792bedfbff800821f33a1d49de599310d1c219ed6604e7a7340d7ed0015dd4d908c8c72386e4d1ca3be9e16fe3d773640e
109	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x68d2862ee6125e1225505af2867d8085ae011a1d6df74a16732f381296a890060d11f767746714e504cc555e78c6d5d3b68d357ec07ea0ea66fb1348ecb8dbdb	\\x1afed6ebafa85704a26da3d1afd6fd9dd0773163abfc5600e79926bf5dd41cafe2f101dff4d9b0a50053dfad76f7550c2f49b81f9bb25fc25b1277ad03c1450b
117	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x65ae0b06bd6cb9d16fe844f7cecf71a4fe30ab16699062955d29a321a8d88f9bcaaf9a0296dbd3d842eae415ecf0e252652cf2bda71b114cbaa90cb269d77caf	\\xccf92f72047bc193519407093a75adacf39441ddeca2c1ee5747bd9baf3677532b91bc41cec8632ee5c15fce8ce7bc16cac9a0921a08a0239014d224849fa50e
122	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdb32da0ac04ca66420df6450e061dc35c8cbb57df643029d874aac65ae9fcc35fde95a4bdc49eb4fd0410928c1bfe253707fae67d1dd09ef02b10eea96bf65fc	\\x514a51dab8757d15ec51d63a4518c2a283666a9560e9867592719c21b52905acf9c7cb17cc2f4745cd2721de0a70510af3f602bd302f0e6e79a24415fd065c09
132	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2677c3d60efb9e8e689eb56c60b5c172766d53f7122cb7a59516bbaed78deac978a6dd05dfef061363b2f887a53d02a40a0fd453a71e1114246d29ad9285353e	\\x3e016cab440fbbe120d0213fb555405ce620c17fcdf4c67cfe8cfb3edb40d0f74c9db58ce7e5ff5ddd268030082ca72e3459bb32e1c6c595bf0ef60c9b6f8409
138	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x74f08a9fbd323be379f001ca0a20cfbb2cda070b4b8930fb7f7b3ae3e54d2f38493e3c659f79266d94f3a15d7a5a6e03ba8aaf09435862b00418c6659a098f89	\\x2ac20242fd5670749addf1b801fea1a7700007e4e4ab49c60b97b3ca004030fdb5d3e71e82cc2cde41fd52d93ade8af780207c1303e5608af914fd143c56f907
162	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4b9b7b2a809aaa6e51e49f9cc12eb02154a8dd3ae2c8795b224f7be4a519724bb0cf7ce952cd94a67bb4d1b21f74fc1c27111e369dfd1528763bd604a7182ac8	\\xfdf07b6ea5584f6f2bc4117892fb941b69f448948fff849ab7b6f33f028fa99fe97f285a8ffb2ca1319eba14be4f8430c9cd50494d26c5adb44c414d6816b005
177	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2d92f35582c6f6dd230c69c6b9891f9170787db0c23d283fae0b35bf72b9dcac4892dee517df30b4e9112d2d9f22344298fd9e593bf5268383a2dca200a01771	\\x26ea94a30d3fc155b72f643fa0b50c61f56b5f36cfbdffdf5931728d80b90caf16b919cac1fd7d1504e91bfe85a68d9e6c1edde7ab9ae1218fe0c91c0f922007
179	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x79c8e26446d953b9c24a15463e2ac0f4d913c55c24bc42d684022f7864ee2306e5738bf2da2fd7ac0b6593c35050c908b716e7c66c3a86bcdeed28ba21c2e4d6	\\x74a774061eeee31760b24a379e9a843ac66ad84f4b8fcd35a104be7176d1e0ad16a5edee84aa60daad6996b8b518abc1410b3b26d9e3f5f3538f1fa69cbde107
210	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaa5273c479943bb713700ee04393454643d4cc3c3d3d8481126871e87c9b18bd980d71a2d053510695a16ddba5856ac001f1f1a173846a88691d1858b7d30024	\\x37575683a4aeccff5458e136453436d78455ae5b1f80ac27aa43129a22f90a959bc48417770bfcc166f58645a2dcf95a26d2510ecd7bfb00032afa1c8ee42f02
217	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe1cd3bcde37c1f08fcf1ca5fc898eefbd2995b2d27fc765acc3dba99d8944e8802eb62487081fa74b1318638788e8d9076c490dbe979ea76cb71d1610f7776a0	\\x873c59cdcb7b6d38bc8258ec109db3435fbc2baaf3e44da385ceb72ec60052f45fc02664a001e0076185ae1c0eb3a81c9cd1448c1fb3e5562351933c88fb490b
243	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8b536970bafd567c0a3d45871999dbc149c5e29a387e8f03256bd934da95a55bfcf4e3ba7a9fc645d937eb4d3e66918705483ab710cbb77d1756978ea32c5f54	\\xb8f3abea7b6727ab3d70025a0e4e98a42766ee89045e9534d7db138ec5b6dc3b7228c5f4b53e43a859449b4bdedb025edd998eff14d16e213690df179e162301
250	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x91639ed4c1fa37ae3971f951fe9124c40f9b117117edca88ab69f86aa600a99f0b93a78243716d4bff90b2a8f142105da7b32c1d94616631e11646d8da6a5992	\\xa1330e4fa05318e040ae7754eba681b6b2f2324067eaadde46740fac0f5326247c967815b0cd2ac26eac5d0da8bf342330add812ff4e0a38a379d9ffa145a300
274	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0f3f7c8d9d91f8b315fe36e0ed6e91585b3f6e43a6a4daf4845565a8a55491560445f8d844275056b5bd65af5b058f2a4534750d8908b3a7fb1f5ea641bb0e93	\\xd56e19d096b83b0a00e593d9a507b6ed623d924789b3385d3d09c2d8c754e70651f3ae0bee20ff35fd5e0a40b225598dfc78b97759e58f0da3dd034fbae3b403
280	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4c52eb97b51c48a970a0c96fcf8e258d09fef456e1be82adbc0f68d054f89d6cf7d611b3eec0672ff73f6c1f2dde5409ca0721d1750e7ada0a655bd25964453c	\\x0eed7873df100f414e2d14bad959727cdc1a88b058cd3558c75eeabc4c3b8e87015be8ef70f564fe25288343f05b8c36550ded1325c4a8352c664f2dd24d620b
314	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x03adf4f3cf807bac40af7581cb3f7c6e9286ab25328a9ee3cfcc93aad8d5b3a0c34dcfb869f006ed2d3a90dcc29c2db4f578fa13003fc933a2a3841811d44906	\\xf0a2968ca84fa5453487c7d78c6d187ed77dda2605dcd1ed05085fe0cd781c039ec9f46b66b800be857361b2d2d572a58903c18e0a512154b9998bccb93bd30d
335	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x02e6024e19a7233eaf332428876599819b32c6c9d236af90c92066fbe50198a40a7541b754567bf07e5b890322b1c43a5d1e7f9f4ed7acf364d8eb3b586ef34c	\\x0c1a739edf0fab28940423c5829f61ec03ef61997c8923a200b704aceb7964f3343033017e167d45704c0d092782fd1a3b6f13ab8b153e43376126f1983b2305
362	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x37f1870ad2c8c6dbe26588633fc6c36fdd7aa04a1b4faf807cabe08d162e5c0afe886256b57159730f5bf0ca008a37156f1a1c0648e431eb7182631588c0e237	\\x9693a3c88cf2f2864559f36b6d4a08e6cce953269eeff2de87a1a0ab656be869d157d83c27d2cfcb5727a57f0238c717363daeb9aae0f44e19bf114d26368407
401	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe219552b943456c7deb1e993cb2f69fb0a4e20464dccc97bf8d68faca04833510a92c9aa785ec92d433eac592ea2af9defa2d431359be4ffad09eced7a195ac8	\\x2ab77842cd2ee8aecaaf02f2366d430c9a04899abf1770cb9bc95b855b62b03c4902c6dcd61747703723df5eee4b8d2956ce49a3caaa0426398cbccc057a9a07
413	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0d0b472d6f0678fde730492def62655e7d26bb6fc3b35e4f973a4cba092563e72d48feece1cad8d1c6f535564f18594bb399baafaa83b4382a777493799b343f	\\x58c1ab7ca3ed6c0801dc8b79a68ceb30472592b682e3d603161cbb5470fb9a16b91b8060a822b3858ad1aa4a22638653f2f434eff554a40f145bf605488dea08
416	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfb34c2dc352433e698032995d5cf5da698fe042721ee21441268ea2fd115cc396bac8f8681607844ae94bd92f622ac88e2520175c17b2610f78b200173b79500	\\x16022398bbbd1d3ddbbcbaca13350efefafa90395920f1b0f1da456d13186a5ec308254bf43b7c2e1452bd9998aafcd2422ed6e08459942c71034dbb64a55002
49	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7b61ecadac31f0a92850d0c95d1407bb5fb77c35652f5737afe6da654a79db24f819ddc616abf89476001ec5f829e7704668004bb06905e4b85ed22d9436f014	\\xd4d470ede94388e11445580c98071b0426be50009bc366ff280690fbbd88748e94d9dc3aca0653f211dbf755677efc120ef8fb4103c16755c2a8adb742eabf0c
57	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5f272026211bea5a5ff5e9866bc46ac4aa935e99d4db4fcb95f96c1ebbc57dc30700c14cff13bfc07ea8c33a5ea55ecc6756b078c330cab47763e7d5b2d25345	\\x16500103322c26e0e2efb15521c50453c2584848401d8a6bcc421caee4da723cbcab0ec1246f9768281bd538003e3552893de2606a075658ce6a96fd428c2905
65	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x055223360e64d2882ff1a8eb0d5dcff24a30fa7ce795e42aa930f2bf1638710fe6463c707205c54420a79884ba5130edaf5606b6616436a642475d5a9da812d4	\\x6aa3bb0861861a6a0e9055c0474233845d3404f06448590270509b0dacf7b93e9f5d49f05c2426464601ad7377b59ffe61de6436cb1d1ef9623f53ffe13f4b01
76	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x659c6e96567f91b8685764e157e78ceab97965a26f74620f62a11f646d62605cf049865a46836b306fdf66302a22842e5a441a73e0895b85c5697972cd242160	\\x4955cf0a1ba5ca7befad76efb5a609e0f3b086b8517326c408b21da56a32e11035870de387feb2a01b614bfa1a870de113da66b546c182209ce9b9bb9722e805
91	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfbcdca9f0738e657aa0196270a85ffe1ef6c4d29f0bf31043ce1085eadc49528b1eb3157c048ed6996e29ec1768eaa9f174e8257d07b90ab137da7e4128f54fb	\\xdd660ded19efa6fc5579c2d6dc124d6d3563243c1cef4682a37fd6ab876865675812bc47ad46359d942c96c85b5a369565eef14b26a5fdb30eca7c39feed5d06
99	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x96f4666b9e9a72ad4bc85f7c0107f2c7271a3d3d4b74d049f2c83a47a7b8befa6cbc65ca2f7fb16e1ae92d29eb13389dc7c42f1abe3143aea91bc2da27ac6c7b	\\x1ac879fdaad84c29bb64e582073c6c185e889e30345cdc1945350f7072935e6b317f7fda9e793b34a01d4e536cab70f9b26f4cf5cb4116bdc37666c059ff7b0c
107	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2ccb636ad7e1228116f4d9c0f0354c4b2fc3b75faeee6a4e5c013c0b03131349607a1618ca7e0119cae1c4110dd50b97fa333723be379c769f2e27b2ef689751	\\xd4e01512eb35eba5d05156539416cdc4c620152f14eec434ba17e6ea864afd9b7b6adbc105557febb4504244df964902a0d17c3c930a06ff0390bae4419f0d02
116	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa865262b71cf36b7cf3d9f636e6e59ae01644efac9f8b7168249d8cd2c4480bcca047d90fae8eec281facab47f66567ba9f1cebdb6673a953d64285aa03f2909	\\xf0c5ed4794cb5d57ae988f9fb1953fba992ddcd01f839d970ef8a48d29c4b13db7c67a9e048b1d480709c862741c38cec9f37b4724366064547718ae93d09d0a
125	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x75ae5ab7038ac74a947afbba2986d33ec18fb595e1a5fa8f450576fe8538897bec9f57fa2939f246fecb3df8226ebdd3656c15add287e31e935b7d1653c46654	\\xe32c02430137fba9024c7d669419eed693edd484ffc49121481ba6929cbb2b6f54fec05bd80c6ce5623cb90c5ad718ddbeee6a78491476ddd0e50b88d5608602
134	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5e80dde5a5129a43b58b6e04f7939d7fe052d3720ed32e0a5f8267c7fa8b124cfe495103433c11abf130d75a01963d89f87f87fdf3fcc82ea95e93f1c02fb0e5	\\xc7f24c5184e1ff49b8baa6701605e2d0c65d7adda3747ad82b463d34e3b64f505054b889c283522139037dcf96b01346ed257d930b31ef67f1bd221f57a9380d
143	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbe40d8638026c71a02508be60f968f5b08b7856beeaf5760615db4f61be8c419964d83ae18a180bac4be9878994e114ee943a8e16aa6fee6575dfe733f48f832	\\xd8383eb293be8a5ef911b9923228f20bab39b17aaadeca894d1b1f669c58da79387acaeef4f11b143781d3d5d92d5e25354bf352fef32d661231d8831d99b70f
163	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8f7fd2f9d0ebc08edb03d08fc9a857ca1bd6d559b66f6fd8d62b8783b851a557a082f32e92ef23bd08014e44969c5dab1f33febdd776759531aec711d5e956ba	\\x7865aa4bd90b296810e6e6811c8173e149c1d04887344a30c0cbc831a0441f8f606897c1600195b7cef187d6da13a79eeff9a468fcb833843864165d17074f00
168	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfd72d9cd64f441a6e4e1c3e59944a6c729f77d43b65612eabc334bcdfcdd2618d209fe28f5ee702d682473abddd42414cd1f65527cf8bf5fac5cbfe326185ee4	\\xcceaf111af6083ad6a3b091a7c2b968ead9b0758e0b08f3e70f53a2bfc409b8a6a9d55093c781409579611c20c0622303f3a0f5de2a8136de5a8b72f87a5900b
196	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8f51faf4a7eb8320088d14a177ffdbe81f22c756d3f122fa5c1aa79a0645e7f3b774f34afe864f537d552bd9281cc90bceeba66b998b971e385ea8deefe646aa	\\xe3fb902f409809544109fe337b54f69d2af64cf603d56c3cf562a43e0686b9847fdac9e0ccd6381b30604a4fd99cd5173557bfa3c1428fd4c6fc54b466727606
197	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf61cf9b75c49f18bddddc1fb446320a205e7e80b1b530ed4a373abaf976788d2cc8883701062275945c0dccafe30b0a8e815f5638ca189ccd1e0cdee6d5c78a1	\\x5805860a319f61ab747801903ce1dfce6394e1059bf127e61c44611560e218d0de26506ae791dc8f106d1a8ae03d3ca89a21c6177cd3282255a77e1ee284c100
222	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4db82031d820baccc8996eada08158d64b4ebb9fae2a882e9c05ab1245b8d2117e9720af53057883eef5cc6f805eae41f53b55b3c4d54d9a91832753a90b85b7	\\xf489c548d9514a5125f16dedce3b6b2a9efed9e987f2dbdb600ba0d238608ccb571eb392f3b81f9bee0693b3ec62260852f5c4048b0537034059d84825f0bf04
231	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xff57036ee9eebaa8a094788f1cfed5b52548d9851e8de2c3bd1db3af90309121aa7c88af50f37ec401c53e097a37eadd7c0f7b8593dedcfc67546cd401be6a20	\\x7af8a30b3a5a9748ed4be6822a88f8da9a94651a793e925430b59bac0bc08f1445134dc03e0519fc5cd6d5ea8bb9a38022bac4a69378544c089598d5469a920a
255	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x33358598dd5bfa2941021fdce457b9cb883e8d2b6dfbdaad1e69afb3d19d708fb9084dddd8bd2569f5eb6a847b7deb0e924fae5ccf2ead097f0251ba0f126e5a	\\xb7493a230fb336d9bfb1120a8d57dbd890b2a485f2a7df7d1c8e2fcdeddb5434acac2aa57f1b8dd5b0fee3c7c425560b60991019ad0277dc11da454d5bc3e100
266	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x10586a4d391169d690928ad14077081642eb6356db10674be2e2fe74f91f85b2496241a4407f32bcd2d931262227045959c1d8302a6174989626d24284b4fa59	\\x078e20aeb56f117ca09c9a7a3288667f986ed3542acf4b5e9f7d2f98ae59fb8b1d2c0f48e5d06e891c1b236fff6edcfc6307fc4be3bbb4176bd2fab27d1f6104
284	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc8628623e54f1defe69be832ace219318fd6c235cf9e90c06309632ca92af877ba4aab75c524f5e90dc34fd9736089c88c5886524fab048bb55182dde415281a	\\xf8729cdf23026b64a94e794e571481316f0eb4a3da279bfe34fba2cc119c9f6e5331e83d13f2acecc960b6b501a205ea292dfb901220b3bf872ea916e4aae509
299	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3b17ebd823b98a6d66b41556002f7c98aa511d1111f6cfac642b60363f7d872512312affc1d7ac3328eca780bdd633e52d6348386ee2590666040e782705cafa	\\x7d4d399756154ea3030ecd8e57faba0d3b58832c2c976c09ddf189884e030aac29ec80ee2d94502a0a9c4575f792fc88929d9f6671ae3c007fb732c579f1190d
325	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x420f86642c40ad28fbd0c9a6874a9d154125ced7d468cf7986ea1e197a8d5c6368136888948df0d7e3f4841fd55d86e06624adceb58eda0a5eb912002bfeedb0	\\xda45a811f769f5587c4bd5f32fa737bae3d501243b4aae6b41d52fc10970c7411082772c4f4387820f0a186c11e4c917c589b49c88cd94abcda912e0659b6f01
355	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x28b9e406c5d873da8937521eb7a930d1b77dc6d756dedb9887168fdf232ac78a4e0db07bc524efd29b88bc5f4a1e67ba674cb2ef8bbb3b9a41a0fd274c20e59b	\\x68a1566cb4a03516e81effa0a6e4e0dafd05179a20f72920988184ceb72271f6ea6b4f0df404332cfc52dfaf41c480ec2842473bb101e0c7c0e3ea13b8e82b09
383	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xad543297e42f9080c59cb9dfcafd8c20b7123553e0686df492dba2b94fc5068e518c7df263de3556a8500fd7fa98446ba52868563fbce86913b7162d1758ad82	\\x17be26693a530dc47a1dcfb022f2fe901134c87662ac9e6e4713a9ea8cc7fe4e1e1f433f0ec9578601593f66569c58985931ed93e1ee2e3f75a1d9f03d305d02
410	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb12b74e2c6fb051bbb96d01350d19bff4b5ab106ec03c1ae506cd7d5bc08392e955dbef46d037cee0f943bb05157faa007ab4fab002de13574b332203c95d35d	\\xc4edd6fe61ce0c8f92e9ca716a277f11f688f3b1271bc4b237ba84279e3af0dc22775508bb9d7164da4605b4704277136047254c17b5b977a69db61ee8818909
414	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x85fc8f313d0ad08d72749c99b5f596159d8903ad1ae46a15fd8b7a8ac2c8cf1db43159e1600059d2c2ddfb98d838f081175635dcb5a1696eaf35492a321cb2e9	\\xc689b3317669ef4bd160ad60351698448dc4e013e446530475d07752bc268f27c1556c01d10dc164a97a12210c40838ab5b212cc54de0ef24f6bba929d739505
50	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe3ab467073a85948d923a73d177c174fe9a31a709150297bc194981b06380d124406795be5066a6b5c6fbfe8032a41673ec2604068f94bdebf6723e3892efb35	\\x322ec1d5334f7a431776cc8e84da2a51369ed6ea2e4f1f637610ed893540766c289aecbee32eddf321ce26f7ae329907e7fbfefb1ee99b0e0c1f7c1d9cd1d909
58	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x871b94abfdb90d96252152a05e72839ea49adb80cbf0149a11cdecbc905fbe5152feeabd740ac81c6e8030aaf0a249439929521c71fefb7b8ab3f4d0073ee140	\\x2c7489f0d9d664a52894c8339f936c3a0f61edb9ce8e194234a7d651397ca1020d92ba8ab80d653caed7948a768b405bcd146b5a485b7987e51c703134114d0f
67	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7c9fd8b5e5ad76b603c8975327677f9cc9639b705089f415f10e0d8945640fdc9560566570055b4718f2e32c7d3689413a8ec05b8951dab73e3d85db6130d769	\\x735af4ad5fbd8e3d8bfd7ce9a1b16b76f304ded2becc59d7c00d18482973e26db6974dfd4c3dc2550b347120d7503a1108fd293d3e86fd18f1bce85bd83fdf0e
77	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc43b8b07dbbb991bf4a3f6a8c152e2c7658a7c119d67da9712c4aa13c128d2b82d4280df90d7e4f0dae669a896f25757924b839aecd00930bd559cf4370067f1	\\x6a7269f3698f4810f18edb4c9f746908a7b4c0aa6a7019cc967475a93080c8d1f9363b9c44856c51523fe91d8f24527f7a515d3af5a68cfdb567820d11427900
90	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3a00f5a3e5160bff20343800bf2c4fe04cf9a221fa2eeaee0604b5add5015b5666fd09f1ec47e0b9ad70149ccd690319f32ef84916f73406c32814d8679df351	\\xf029061076a50ce15eddcf44bd9ef477972681f8214940488539349b2b20e1aaf7e8ca80b1fb6671e6ddb4f4b4db6fcf392585c8c69ef72db3091f83de36910c
103	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdde510bb7ce7b608d9ab1b575c1161174e43c09c4b498f2c82de40d0f05cc2fd3011127197f580516f3e50cb8496ff51725f2bf902253652ba6f9839e007b346	\\xbbd25b1ed4f2e78965ed80841bca054f33b9e787ca4b4749bee5aa9003de3360ba0dd36c1ae02d5914fa3ab38b36c125e481aac2171f197b043e38d288c7140c
110	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0fd533c3e373d76f1d6d13686b54a8b550ea65582f85c3244f4b9ba03ddd8cae50fe59f8c91353763142fd2c170cb2a96718cbfefba7dd1f4c07cf73b1f8d172	\\x7507f4bfb997d3e6043ac04a7a646fd9acd585b4abbcb7c7b3e7ca823e4b9e510c264094e51cda9c48693ec50e77074e9267a09739a7f521871265cb10208e04
120	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2ad41844938291dc7b25e62a0800e6c364e4968c4b0d22dac7e0ffb4aff4746726b3cd3bc4619fb7b86f61c4bc8ec48723d3b8816bcd3cd96eabb97c6e721746	\\x0e1554b601b4ebea08a4ab148e797611e8de3874905c7269f65459dd281e954763bffb237e62ca52465620a1dedd7a2854e8f3c1a3598bce8395b414b8b41a08
127	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x041fabc7ba299c45e29c036875ec5cabbad125e3d823fc779c78b5d9398d72fcba320d27fc784012dc485bb703880ab7e06384ede9684a74cd496ab6af0f68b7	\\x5103a126724f26494eb7d4dee5feb23bf6fdcad4d5d1235c2f124968df52f9266e2f0994eee570c576844ea4b8d71f9d5915110fdd01f0e644f79ce4d8a00501
137	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x217c566f4262da12eb92933de248a61196131b8e15a3a142de733fccfb7d231c5867a2fce419ff2561d296e14c806ac7f66f1f2bbc68c2fcaaf61b28cd4a128d	\\x12f02d9adbf927f4849257af7df07833f6200bc5158e4a8cd71beec49813c37ba5533059f41810db5abbba45be43ec229fa1d2fc982a5dc350542bc07fb59c03
142	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2bb2e7e0d30451d70f6175670e588e17029facfe6478c086919a8b979f6a24e1e44324fdd3651b48b8dba0c3339a68134c09f7bc9957c3af4088ad83ea60b1b5	\\x74b561706844cc7baea1cf48253e43cc563b56f5427cb2ab2e7e7af68573e407a4d5b55e7ebc164c52313efc66e98c219395e13ab7a7ba72579f2b7b2288ae01
164	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xcb6b9a50c472e8bcfb3e5ab74789d041ffcac7e40e9a491b3d4481121b99e0e8a8953ce220f85b0de7906431b768b9402d5fefa14ef105efc5d4a6dbea6af438	\\xf8cb8a710625f598111f408a1b7581ca2d82c11c9f8966497e2dfdf3029d4a6be92efb9a93b770a22e14284242a949ba49e48894b3ffb65de156ba781ede3a0e
169	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x75560d6a138e7e7ed056c4d0a4f4fb1ff733efaae88d9558fc9a5f5fde3f626b3a8539399ff189d1c7b2a82d765ab22dabe3bd3732b39d1ac97f07b2ca80fb58	\\x2f23480e42928b7a530180d6184b54bde3495fc78a7f40e23ae667922d03daeafc5603743b73d8ec05cfb029179a012a58c4159c70074405f56d303fd8fc6702
181	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8c694ce3f059c7c5741f6198523caee0559e1b19f0a3668a0740dfefd779d39354808040c80e1fcdaddc48dff3d763cfa791867105703c86a53226e0f0ccf053	\\x4c8f13c95da8f8a0600f11142c299524247b6bef138bb6ca7717f8dca7b0b8675536cb0436aa6dd393f381f01cfcb5dd40593e9fa3054ec4c88600838a1c1f02
205	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd45b34596394d58126180b1092a0f9d86c16bc4c509e027da437fd3e3c6107861d20c5729fb5246249bf7592eef52e692fe42c580842afde52a08e560e611b07	\\x68a1db9fa6c064c4df0124333c9cec6caee537424b72cf232d58f22a18dc7f4132f904486ef50790be4b34cf746df3e80bc5002edc056c5f070bc570e893b502
216	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8de18abe4a0ab1e0aea52e36e3d42522fa37ae47e307230d84347a98480f1845ec29a551da93611247ebb2eb7ad40b4b95c2204b408ad63ea5d80428655055dc	\\x8cf737a0ad95d2dbfb866fb7063fd9c1ae75cb4b39f7776cf6395ab952dd4db8b42862e269084da6eca15081755877416ce4723ec00b18ead64668096761540b
237	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x38b7086e6508b279685d9648ed6a0017892f7d07695e068a9bffbeadecb5e5bc0804003a26add10aa98816f0e48c5b6e8febd43ff7946f6f7af6ad7c716d5db5	\\xa3db3164eb6789eed3725c5c3b175728f1d05a93c619bd87d4db14f0d94572b09f53bdf3554c3189675259c86f4bc043816ca7b6e4bb199d20bfd9f05159870c
245	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1d31b3831eb0ca6708d75faea11e96d056f2c2714bc433fe5db744dcb2332b08368c4d170b815f7ce8a0245d65b3b397944a90a6d9e19bab45ebdc5d0682a5d1	\\x28ef6b9985f9c52f3c18552039b13c37c08ae7efe015e320a96ab8e070e63032225100f5a3015ce2acfe669499efff3d0c8efd500439e8c9d4076e8c15b29500
268	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdb71807b167e4668ee5d3830aa8f255f70a3ea06dd970e1bbfab9435ea1bb52e1ac53d8f381385ad1e3ddc2ca8ffccae3245089a0ce78820164f24c8732082b2	\\x38fbdaa3c89e5cb82cfed62883ea77ca91c991e9dc20408fd762a0165aa1c305108041ee30f40f0d4e654d6483d61c5d9117a26488a375b3384f94e5267cf107
283	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7e87d46b26c83615cbfb234a6bff6e50545130a9ae55438c39206aa0649beb52ad60dfe89036c6b98845d3497a57bebb24271b90e0dc7c221dae40ef30d8ebb4	\\x157de4fec16d462ca4ac4b61e01e7896905c8dd2aa8ff78c8a16c46bb921fc017ff9e34ab1045089077ae17b8b7caa718610a5ce0da4210f38d9f5b78c78ab09
300	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7e74c1aa9c7557724abc7d29c208a3db73a72964870d48f2225003690a4c0d8f0425488e18fefbc9ea031722b1ab4cb94287c06d032dd0cfe73969c72f4bc16d	\\xaeeaf5b6fea0a35eeebbe803e63da917ad0275ffeed205c518bc4a2fea60762315622b782880e26686d4c55afec5140d71e1a2345d11372289199daf94a85502
316	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4a9f1adbd881a31d4aaefbc2dfd16b29831b12cddfe524ff97efc9e1e96fb97bfe123909600921fe408f35e2ba4bafbf10aef55a4c6ce149cd06196c2a7fda7f	\\x27944d9c8cce9b1f8b173915c88613ecf6e9e5b8fe8620a4d7b9b572d7f842e3ad2adb978175d3f08be8cf06a022698e2befcfa999691916fc99858f5313b104
326	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x94eab4c09f0e161b6c87e8f8975412b51bc9bc01fa5ea77abbbfc80610ff077603fa18ed3e6d1cddf34a880c4fec5ef3529f7ad2c7dd96623f3f501ad91b16fa	\\xdcf873e9eee2fd03f63e7b4b65ed8c27446fd0e6394a88a26be918eb9494cb0b690d61879ce28f1c608fabf581bfc34e3730c975a0f94cf778245e5ebeb9ba06
337	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x86db04d7c4732720d8a0f7dec1cf506d9141675fb2b5bc6d7cc23bad7a8c1326997dd77a617c637436bc6500368d9665935384139f61ba96121b727300de47f4	\\xa28fb324f5ba53ba1e9554c92354b3f848124a00f9093a8e0b84fd0a1049c668a72679c4369162dcbbdf47d8dcd95c537e3471aa317a94c4f71a051e3212fb0b
346	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaa60151953c061c81c854b1615e134f823c39437cb4bbc7952652b3cba39f7d6264508321f0f8f6e684427c6fd5b65bd771b45ef04b3a84cadcefc15500c039f	\\xb3a3503f0b1ff90a40196b05d277193c5a8347b2f3ac5d9f82751294b00d62d2144083f1e0e18ce984e37e2d6af03d22c712686460e6350667ee3a3331e0190c
382	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8fc1ece17ce9d002c6dba633c1c1e8f136ae7392c6fd5376d1c2838be54228a27a77925713c7450e0d6435a40818536367c0c8e6d3472b2c02ab7e888aad078b	\\xcf268c4c93763bc3a3804ada2c6a51c83e00c204073bb5ddad524f80d64451a12ba75fbd766aa802ae3315ff001ef463d3c658dd7267e1316205443a91effa0e
412	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9fa3e3a911b7d1ba8f0e4c01fe7768d64af5898a2205a95f44fc9fb3f379f268a0c51aa2878faa75a34df6f0cda8ff58c7f3c26a82e041c750de42d698249a2e	\\x3e5190548618cace2c9f1a98b5aa740718170111ccf96f7718776d5e764f16264163e2d116f2bf6f52caacde421aa7d85a4ba6815fe1e13ae99f881fb2c6fa06
144	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7e501e8508142deeb0edbe1ef63f770b333596538da65d63255f890076033c7c49ef9b78b8e2b84b538d7edcfbc6c01e160b38e41ee8fdcc96dec75ba83dfbb1	\\x1c577cd08831481c5530a43c96c81cf8c955c4ece8d8c7db16b8f6c514345161b45dce7afe074d7b295cd62658b8f1dca634d43f7b315c462bfd217a6b744106
165	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x17ccdd3cb85bbc409ec090416adc224b6c4ea4454dcd2b75d4a618bc757975714abb424e113efa1f729a9b87cb3409f5aba4f3450b2e8bb58909af5dd0611e36	\\xcc0dfc0a9b9a7b93a143240908df102e2192f0c37f26a90c649ac58982de27adce1b8d0b042c1e82475b2b6cbe8b87c807db0980dd55e20146d980ab41ebbb0a
182	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe0eaaabe624851bd0fbcb4e8270c222ac5786662e688d3c804fa029511af9fd2761ae69ce004c7cea06346baf426b929512646fa53045aedf7a17921d61fb3fa	\\xf2639090fd82dd54fd858d6fdf18435192225b3960f769eb5e4435a1e6a8b7d40b5928f952be7fc7d40f9d26236d6d1eb92a1706c72f85780156e30cae120b0b
189	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2343880e5ae24557f44b1284c205e7811c31ef16045947e691777a7c6f8ed0906f7ddb472eef8ce9176ba4daa1a62d67e75c91f3ce94f81e3018969224bb04ec	\\x2724343ebc7ab352628ef274a42c7863cbe3d76914ed3aedd1b8dd6e6843566380758ccaf0887861454a46d8adc8bce07b58f775ad4e60434a85c1bc0627680c
220	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x19096039f3664fbced0fcaf396556bae15c240bb3de4661ba03ae86e6d86b798378a8eb9b8cefb9121fba954d3430355029be4aa533d83a4947911c4aee8bb13	\\x1cb66ed91cd24105cb7ce0800727c2f7a3be5b5dda11f28180bc7470a830ebd73c321277944d42d6bec0f6f3bc1f1f6445ab1a1f3d13b252fca0385f7a5e440c
224	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0ba19734eed90f2c35ec770c9ad8b9a881437b39b266b3c8f84474966aac92811f02ff1c30676b7d206d9d034759598be9db2a5a051b60826f5aa0cd29bddfb1	\\x90cd86a66dd288892e4dc1504322152f04a5eda0608e5c32af0950bac5d18fa7da24c77874a14b9b8f56bd9ee1ef7fba8eecf69b48f426af492b82e87ad2730c
253	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1ed86f17adcd757d8f4fbe84dcbb6f64a3ec9c78921a0874d683e547cdba9c6027fce601ddd7538ad62061429ed0c881afb5a464966cb87ca81d37f93adea3a2	\\xc1ae01aff2a6690c764d5ec0a5ea25f73f4d0da26eb2de05790db75f7f7e23890f34e1a5580e95a345d51b410226e8e06db9719191d6269aece549d3bc44e00e
257	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xeb52f54e4d19df4579fcbaae1e2d269ef9a424888fac30a95b84961b959f18ecfba8f456e6160739a78f04bd9884a41f66555216a9bfe45d6da54d5bfd5d3b97	\\x31782ecdb8c2351b44b8334fc7fc3d59fb610a75ba8039577bf636d13e78ce134f649df4ffe27875c668f6d50736195df95970395d31c094dc56bd091692850f
289	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfeba8e0ea9675b34a08fc4f5258d0ba9f9e87aa99cb6392280486572a6861cffe20a3b18b054a7f2be2a8db102a3b31f8bd2c0c27d3498b38dba8501a1b2432d	\\xff861d7b4feba1507f33bc2e289a4148b1640d5f7085497fe2f06ae3c87a41115ad547fb3351c8bf3a5bb0add15ee2c3491ff21258e8fbcc57e424b7ed63680b
290	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7f1d94947725a7256f7e684d222f64a33bad28260205e83927578e97e650e657f4948f5e0c97282f573937cb380b896db0ed3288e48998bd89a290c5a4337f2f	\\x172a283822f656fd160d61a0e67c7912301e8b2ff9d11a3a6add08ecfa52822b8d14b62cc2a29a1430bb391e72944cf4eac85dad823ee028d4e2516d6a85440a
312	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaf7ab636b369d7c7403a87b4490991835a0231949b38b1a392d7516dc726e2168071d5776e6bc4e6169dbe79a19b1aca749bcc1e6c46d5c2a90728d0402a7479	\\x4685399657b8f5b559f3534cbbc8dc48b4ba8db865020d37fcedfb1441683e15bb236fa520410fabf4e920c2b79972e5dfd736ae18b9d6b35538b588fe1f610b
330	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3e71344441c5beefc7e972959ed735f9d68e0af21dd0f5984ef2ad38f49920e725e132574ee718a9681b939d72d8e5e643d4869e4e7e9c4899c94a20be1ad794	\\xa9838865282c3de66de891add9a613bec7e42c49e2ff5b23e67b39e44b38add6812db00e5922e715e3084c536902753feeeb496f3b4ef8f451d006531a644409
365	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x406f2b30080ea3499bc00a17db937e4a46c0ffd0af650f4b32445223a13ab0a18de0018c63293053ff6121d10c939b299c756766ac0d2b245497a52bda1a2602	\\xeae1fdfa8204d6cf236e9c374df24009384f397ab173eb991455eb2204524e110b9a21a29516b6a98f2f2a9682e4204ee2da9b0d5ba7990f7730d607230ad306
396	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x88d096d779c4238763de35531b960b9f4298c954d9057bed1b575fb4c84c73456caace623e413803eeab7a5367b4b8d825273b8e892d72ec481819aea4257b73	\\x2471e66488a03fb2657a75f8ce4512bdf734b9afca93285158088cf291e9661855455bdf06f05dfa481f1d9a246d27ddb7accc1b9342cb562aacc7874e80820a
145	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5a8d3b53374840358b58e4ea3423e524c4f779e499cf374797aa9f656dbb0b8067025bab21808a7889ba2460b9bd049cc32a9071fc483b37c85e3efe7efb1263	\\x93be75eb7bc99feca867883c8b9b4ca24a771c91a26382a19728e4622718e31b4b2adb7d198cdfd7d79861f7c1fdcd4fa107bfcc805d60edc257ea7f51619f02
166	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9bc3016b7227aa47abdb0857d39f5b9ee620769047594b263b08ca1ee1596be5c2dfd78a7731e8c6cb623f2e0436e81b16cef2a27f038d4b5e14963d08dd818a	\\xb6f4f843d335733d9d1a9ef3f178345d48f0768d10620098d4d85c2a71e7e909397e63c1c4d0160c591cb4d6c18544c0c9c5b79515824f056b854c008ecd3f0f
180	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5e68ddfcc491e1a1bc969b855433e58dc60e96a766b38811ffe6eba12bedc371be3bbd76a27becb00f58d82f3f51eb48d06a21d3265d952e41fd3940ac8b0234	\\xb91e6e84b3efecc298a252cb7626b38b9ce98c043c1c3308d2d0c27530053d78114117f6e7502d30943c079636141970ee2e52b7e2972fe50e213c613d11d600
188	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1077e251d541ae231b4e236c0bf513f59326ffc2565b07f8f98b6413e997ccdfbfd8858f84f376229496a0cff46b2e011cb118dda6a81787a009a760a953d6fc	\\x90c8890d3a884280d20fa03e5de5421990e0ad0391faf13d9e81ef70f361b0c7a2c52381fea2467df4736dc236262502ef1b14021481f1b1646b34464a817301
211	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfbbeb95ee800a4d95c763f08ae3728e0ea3236ea36e33fb3ae438146a2ea92a35350db2d3f3b8408f17037a93a021719bdccf0540b1167dec5eca23ca91c62ed	\\xfc2912a769972f3b93eb7f849327552c3ac5ab0f21fbb1b498088a8ec4edd1d6512bbed9633dd19b571db9e3bd6515858d75c51cb7035c40d0551b4cb569ac00
219	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6e88b6e1cf77887cfb1bca4dd129580f45d6d7e000b7b6d28c881512865376f5f6e80576b19b841db1c89610f2e9384cdb728c97d6a56bf919e723a315f2fe01	\\xf660f52b51fadc5e138efb151a3f2cc98ee1928b3711026cc8e65d3e33349f729a0dbe4bc1e2d2089172a0387013407be1ca86f1beb4d2717bdea6df4cea940c
246	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc8381f1538d3c38cdfeca70362a6f55800fa79c0e2ded15deae6e20a2aa0fa77da3bbd03b2846c51f8a132c01a9eeead75061890edb23028838bad110c3d2c30	\\x81daef193a2a50ea2126b64fa859888da8758b122ef1d87fb0489504456a073ac0c3fe46c45d90bc898906521d0374c0db29cf6482c046d812594b8bd7b66b0f
247	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc2fc07a14c2b03c85d429ffd4c303ccd2638bb4d90e745a184f1799f636e232685404e1798992677e9e5daf55ec421659e616124fbc7bd67e3a35a9022fb2ae9	\\x59eb2e46cb83053de58949d68ec3f4261036e58421ecde6fb850ca55aa873e0ff59788b9536d633ab64d4a8b1a216dd6bf64bb580411e6df3eb3bb547142760a
273	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7c0ca7be28b32059e5d1963e7dfb9bb84de88d9691585072547027a303896b86aeb3c42950b88e6897fa27caff8d2b10af50237bd91fcc6be6b68995819ed66f	\\xc439faed3f86a3bdfa61037b71b2f0fb589103259ffd82d47cd89cf35afecf7f5495ec5b0eb9e52ab63ef74bc6d995478fb55a0ac3b0871350b3255097894807
279	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf45dcf05d0ab032387946bb2750ddf30b86c163a7de22dc16193a74a54d0e13d6722794416a25fb65af58b899f70164b7d6860dccf2a76c9670f0db3efb1cd50	\\x0b3d5c75763e3011f6735e672435845e18debe7e79e003830e1b25e2ed5f790895b40c4823f3a4c6a4c2de475615f31daea868a9551b42643da8969b030fda0d
306	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8a6f0429cbeaeb6d49e407089af2bf493820567d16393ca27ab84793e6f30b9aec1ae97b09887f8ba2e1e3e9f5eb3d3c0295a6f35967eaf5a9b513b86b74fa0b	\\xc80167d51fbaa472c90602ab9968cb3cd816d714665758a30a962e5d0de162778e653c005b78dfeca5621bf6fbf32db54332e5d9d4213ba9fcadf387f67fb907
317	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x32066531766eee57f4b4877d86c25f3dd3904e7923d03e8e5f45586f0ffdd2b4d31df67641a98ddfea0bd7b8133f435b962e450c2f68671a8d22f62cb9c3943f	\\x1fc66f910113339f7afa37e9b9b4969340574e1abc2a506be030ab63e411a99a095eced1cd26fa137c5c101c7b83713d8d073e7ff03913278a1ca289affdb100
318	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6434d6a390ee45b2cf67ab29fa71d54a0b1e9bf8b81c61beaf21e47ff1a58a74d67e02b84c5bdba6153d0e633cd30f84c6051cf5b84aeac05a13085e22094c1c	\\xf04e6d3952d44258ed3950622788f2ce9c93a2eacdd3291b069a39c3174bdc802b93bf1349e7b6fab07d492200223220f748e075ce5210386786009afb49f30b
347	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd6885aa032fb3ca09e22421785ce09bd82358f8edcb28e110e3e3db824fbcc1798f67787ed597a5f064b5b93b99a67cdf427a8b0ad622504232e89b813538233	\\xb66088a043bba62a0641958fbd94871e0b24741a4376b739a40dd7e58ae24158528ade80c589e0c9c727f016d49aebd7668b80a8b6a3ff71f86cc5109735fc04
351	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x431057179428df2a16bf071d3fdbdbd884628514ca4ad6b3e8a74120491be91cb43a775e4ee61a3b8415fc4d4469d7bb914ba70aa5a8dfc884e36b92682eeb3a	\\x167646d79cf539d80a056b6f94f8e3d58b038365cbf5e0c0c56e44f015673bf9464552ee1aa4f666f892eb52bf1d5e6a16ecf028ae999066787017a8380c5d06
367	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4e53e05068e380b13b08b596cdcd6d8ce4d0082e3a4363f840ccedd21380836e3e5a973b62487bd35d929300625efd2eae7943eb4360a6e273813669c5bce631	\\xa9f4cd875bd5e08733de3c5b44d3974c7a05187adebed6572172fe0a3caa8ead4a74a65c169bb2229ac3f0c68216d13f55bdaeade3bbc09dbbabcdc77f295603
386	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x250ff6b89de31c09356aa0781368267dcad76a7f5106de48af24da2adaad50580fe8e8c2c6c84750cf674b44c8575ea648e5a35ca33051f06f58e76aeb591294	\\xbf6606dd6b13cb1e658a82e4a8598342d874d442ae3d86d7eebaa48497f9828b007ff903756a162ac279ae0f9b7cae18be050068cbd17ac5b6a4ba66c4f1da0d
403	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3a0830deea3f30d594859c4dbf09f12fa23cb539c18ea9189fbc3f727961418d0534b7ead98567dd7f91f97d2eb8521ebfac330f7811d1bf2c5e6531277e30e1	\\xa03cdbffd720dab8b49dfc52c50a2baab0dafc9ceb0ca0d6e165988b669a9d513e08b22e00511c7456f5b89ec5b6d660eef7eac78619edae756a743f2dc80a0b
423	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x71c11045253d8890503b8a39a3a57ce71ea6d5ba9abdcbe79c97c7838820a39da662f0154607110117be93ce5e9ae7f6cfaf2246634ff479f855f9ee6c399b1b	\\xd2ac08e90d9819be9b306cfa59309bf06877b815af4ee17ffc1163f35544afa989633eb3c4cbac0020f71243c5c9c7c4e87bdc781ce4b2934afbfb4727af070f
146	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\xfccb4245a2109e39ed9de8e42c60262dcaa02d976f68e2002311dfd7e3fd25c36955762c2806e94803d92b0d2b914dd1258471b2bcbcb7e6675423af621f890f
172	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0b56857b8fcc55275087e73918f544de78484551fd44302d42a36f1acecb76a41780dcb55bbe047b09a832cb124ed6365af3248ec1a1fa92414c8a055f979cc1	\\x9cf13aa653357a86e6c016bccb3f5531e83c1a7a1891a8c4d51efed7f877146acf75310049dcbc08488b4d55cc2c2f1473e0253ade22d7e75492faaafbdca308
204	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaa30ea733ae263a2e71f28c8b491ce8430f9220e03aaef8d2316728df90f830e11bd5bd22cffc23e993abbf0e8b3eb705f7c6b47043be643222ded2f947aa2fa	\\xadf470b15685569f4e890c53cc237aab2a12335b7bd7ddbc2cd778ff639381150df20ea6ff9512e104974bd06c73331a237ca30da2449635cfb71d3ba0a93703
228	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x03b410367d03c4303e6b14db90bedfe10cd7c4cd2b3a0f92420a27ce64694a9567975d43970a3ab0a86becc08ce2307a5a24608cba6ea35a139f1f23c3b86f0b	\\x53590f6fd2c0d07a220f24e73fcada7c25779bc0e46d7314362c7e08dd38f1d4c201df4c4415056fc673dbd0a0d190cd9f90485198e278795ebd18bbeb04c207
254	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8e0e52930e0667b8c63761745943e66cfb6afabc79a4d4e3767c11c476329d91b9748eee3090e0ecc3b19b9830bf6a86f2f199cf883ebc1aa27121d780046641	\\x3383ae74768bdfa7ab05d6d0d76744f06037ee535f82f717acffa6d3572b5d51fd84e9e68734e7877954d24210e1ea8649783f899e4ccf57deda4f513888bd0e
286	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x76a981c39a312ebd02450a951c4fe673d2b2089a2f489a41bee62958085b0b2d85513843de8c89fae61e7e68e74139f454587c587ad3225f90eb121734925018	\\xa14d7f6b70439f79c8f306605ca8fed53a9a148665a4bc7064461eb7af1840db79e7c8011f466c24caf22a7c256161df306c8a4255d1eaba2f5bc474e1d94400
374	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc9bcc5a0d8e452158ea81728e90e26b3629106382182465f89058475cb201ca9c11f3bcf75fd680b03c34aa5940c1991cad18e35be3cc11ce95830add7514545	\\xb635fe5600e25e795588c11346032a8af11cdda054f49681a3e3d9967e71292a5d3efd5ee90ca1b8e0c7e5ccf2459ec9278e199f37e3633df4651d4ce2f59f06
381	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe7ec5603b19bcd69bc785e82a7bf00083b1811bd435bce873fb86b9509adc853b25fc4ca8fff47a460070929dfc21d13c20296e991b6cf2ed800d312fde476ef	\\x3600b352eead529a6c557fbd3f3d01b84d32b57382a8baf130816cb78a7ae68f880890a1000dfd5131c42c082a69905e540726b5616ae313122e9a55c5eb7f0e
405	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x344d4bc74c3684fd6c23ffc39b52ed3f597ba838a3ba4ad88c5298f9dab8fbff67b108881f7320698dbda2476013fa8eaa3da8e5e263137b132031042cd7d916	\\x5040ce2a2116828b6b2dd60fe91c5911de92fb103060ba31ad938bd15c0ccec98a1ab7808179cc81136f7c5947dac00cf5d79be84067b91f19703ce02e26cb00
147	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x307eaf197e8d962c6fe82c5326322d3fd832e126cbd6d55a7f1386676c441602a88b51323e4b17ecedefd05d22f6961c7df36a44839ea5a7bc1d03b18f7c3fe2	\\x74dac8e7afaa38c32711e4a4699e5b7d6b5fdf9eadd175339240c39d82dd27f97e63719b4e5eaa993c1feb8c30c4f9feac940f7f02f74f1d4d5c75af1b35b10a
175	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9fc5c6ddbf83601c6e89da6f35e0a31d461fd4cc75963c78fc7fd7a4110bd027a43ae30fe69780689d6fc2f138f067082f32f017a6a57081184d40bf605caa84	\\x55ad74a21cf0a3991d462c463d5946bf6b90a4ed22e58f0ef0eec7ad52f5f277519d592b024f0067966b791d7ca9e875d1dc26c61f357eeff41e1f456a942f07
227	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7cb3b5f84c5fb8ffa77724d8b7939b640b03a9624304769df64eabe7017fb9707240a3a2d2cd08fd3ed3e4d239c465e0d69e6d3aa6214c80df82fc130e86c4fe	\\x324c74b3b4e9c45b31ca92dee6b920658c6e2aa260f51e349cc22a0201a9b7c15807e7966f6a8fc8aaa50f7635a38c65d7d138db5f5fdf8587ae885eab6fe303
260	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0162ac4cd2c7a372e2f1f1b8b8d10d47adef74bae9755a57561f22e79a55c327674663fa52604b258634c96d06f83055b983d2ebb48d615fa960d8c1ebee4de2	\\x64473ea2c5c50ba9fbecce73673c8bf0539256c92bc33205b3be8df96e91d7499250b0d18a50e3e3efc16f67e9375d2cc91cc41397fd81cbed71fdebe5d8980f
295	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xde5a88e71d34000997549a45c071cdec9a5aeb9a57625137edb72f71efe4634aa1ea6d3b4e22722f78f20183acab169e90993305b903b9455889521983b57e64	\\xafcbf015c0c53aec2d737f7907fcd3215b4a40123ba3e1349d067e2aad0ccf873c3f2e659c8634d5c35f7227cfb1da796d0e2c05bd9a0721ca0575a4c843d400
305	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa8a4c8f4157aee4785b7c8487334113e82995074f82e54177dd4b12dba7d93f424c2025e17be2162063d39e244b55225eb28087591b831d6ff1c397ac04a31f7	\\x995a29835f6c3b87cf85b2297b0d419e6b32c24c2789982cfc856a70378f43508243c3093700e7591623928555e59a81e10fb3e5aad9c3d4e17ac08c70436f01
315	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x23bc9de6c85f43ada8e7b07e73bced7eccf2cdc11c441d127a4485233b4fc64f28dd75f9c40c0510bc3ff3d153beb27a758005d51362d718f5bff4fc7ce32fb8	\\x908505568cf1602c5ae1964302a28d5e8de1fa34603259d1c212fdb48b406b3b6419aecad809d96186b3ff5dd9dc45cf23ace79eff93f33fb96baea14d8bf306
333	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x69f4af5dba4cce19a49c7fb09dfb0e3b1bcccd5003c0049e00c5b790ca282ad315a727be5bd6c94f07b1d77f9e4cab84235b6d8a2d5509fa3a34c0f4819c933d	\\x8eee3eb739c8f0880739df47ab978c91cb8b0487cbb2703a38dae0b765bb4134499cc399f64fabed058e4c09d02a606f85531a0c7e045b4563a3b09cb3ebd104
344	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf44ff930bc6ae32bfed352d16d334d27add65e18a835950ddf4f0eaf6af436c1b4bc427a3cf473f9349cbbbba168583fa4f4edd9d7760d732dff68cc7f2690de	\\xe00b2dfed0455feb43788e69db520045d1e93fb272b016e9da0c332751dec37998137c5419d364e903dd620f781f168f2f43c24a0a2b50176a0567ab354b1500
384	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x84249f20b9e28c63948c108c05d41df8aafeaa87e2f7cba589f83b06fd15724ce8afbab2ae92a92cc7234cbc9d508c4c003c2aea0f3772d193a9bb2469998c9e	\\x8830cb296348da0b33cd3e414f53e2608d4e1e976d2e72fd11ca61ef48bedd426280c855de59a600bad971a72de503c83380a5cb69c0ae35d1fe05261b8ef50a
149	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf0fca82ed5e1f475885fbca451b7e6d2432530bd12461168ae397b81d818768ff7c392e11593427066f2f3b6ae605fe44de945eea1c6cb67382b1c013332802e	\\xe2b72b97a82ddee6def29990180c08b6b892016293d02fb236bb0998a4c89514ec4a98c78ed7b41363f3f562cf1748e238cae54007ab6e3fa7b4a516a565af0f
192	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x24918f7488cd7ab9987b732bc430f5d2d784e037953d32c37b6630467bca738da28501f05881ece47669fc2120d290037885d955fb07f6103154f3c7cc176fdd	\\x3ceb3fb63e05a656a0dddb9501a8a65ff6913c0515a587a825013045d05e724a511cae550fab5991fc550644365d991a576f308e5779e61db037fbeb25692d08
230	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7fe3b56fe17d37572c91f5931807bf7428bb1122864501cf21d1c5838875e4b03be35e89f5b2513e1d0b3b68666b7860c0b20f54bd9e28f039b33222eadb4970	\\x12d1be5648ce8e764cef0f9ba7d8079f4cee853e5aa896c9d740082adc210040dcd0a299e93de643db55bb907da568f3db09ae8f9a418e692b11be2c427a7605
258	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x74418af6549eb9d8be89953022e48f13f8d10598430012b5363da6cc99339e0a631372fb8c5ef4b127f8d3d49223763114194b704350849d2fe89281a55af198	\\xdddac28d1333dd099522188cf7babfdd60ebddbab99704239b0ac1d7ba8925b0d2a6ea373bff4f6f45fc2ff3259c3d57f1b7f812d32628a198e842fa6ca95d03
287	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9d9bd5f982fcd35116ad6a8823f92374a0761ade38266e31af593d1942d935f4bb776866833ca9fb735f0f83ddecfd407c7f4ae0869873c59ed8561254414a32	\\xc7201e792ca8a187cf2fceb1435ddf2cd0392b27c5e801d384cc6b9727aa7c98fe29255310f71cf7947a52efbab2088baa01242603e344f7c0f3bd59b32c7f0b
323	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe4e9d64b4a6f5af3fe92e041f75cdc3b4f6fc57d62eff3f5c9edee216d03f0f58cbdf3b11616e517d896e47a7124622a8ae18acf433297d3e5bfa90c03ecfa06	\\x7fdc028c846a8d55d0dbcb95cdf3bd5c5dbbdc07864f18b958c0f1bf46c9e6cb726454c720afdcb3400f3733b2552763d00093be9d564f9db08130c102d72c0f
334	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf5ce861d8c4a6e397d874f999a9600b0c760d25d5f2395a06e3042a4c871975714307936a32ccf5d03f6e08677563120971cc1d8f185195492949a5c3bdf1dab	\\x0ba7f918693bc0d1652b61b63241d6c6ced2472ad0e1311a7a5010ce12bd90a26112064be740393705e9ef2fbdecd1db0c11c9c98a3c6c5b7dbb521ef6849d08
345	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa6c785b050385a8be4ac4612c9fcb19e5de180f41e85bba8c98e66e561ad50a27e42182d936882620a485b75420602874292d097f140d6e675ac6f466ccf163a	\\xcb5fabaa6e85de47530b292c7116fef40e8f9d203a78dd027b730b3492af0bfedd0589f259f31f18d32745bb588cca7bd0d8cbdf9fac5ba7e049d401d5b4210f
371	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc09fa6dbf07ffe23d3736fbe0e390da778116257ae68b55431b0632c3e7705c029efbf68445451d1f4d246630cbdd21adc069590d6b76d717d76de130a509ee9	\\x39fa2a5e64f8c9d1e1d12d124acb55470c48456b1342b210f995f621184211e2af7d116d6153e124bf1082cf15b85df8c8aeaacd04f14612221a5a34e6080001
380	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd0b1ba7fbfad44eff41b7a02af646c1451b66ea7650a1f03d5a7fb91005e6ff8565fa01baac5d46c1c04dfbd98168106271619a106e2bd6193efaa18bf576dac	\\xb86a5e3d2e2dccd01cd23ba2e59300426569b7615c0deab0d6bdf834061795cd3a383712c4eb8b096dabef4e8a9174f083777057fbe767dc59bf14e6dc9a6300
398	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc251dd5ad8e82534cd9e6199b4fc61ec0ef19a7ca5a9ff7121342e179b44a7ef4c4b32450e7b2928c88589b6856c5b12e6570e7fe7bb8a08e11f8e067c5396bd	\\xc1e757308addb211fc087bda0a6b3a2d06fc7de583c2dabedcdf97b992e28b74ed4e7cd1f530c9a6c31c37762eb4a81a0105199a2d6871a863d025f927f0950e
417	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfdb213218934abd229f33434896fa037f17c57622a7dcadee32595fe34b3399e32adc0788d9bd7632b16f792dc6fcde3d08a3499b8d7eee6c9de93707c867d33	\\x01a30adae3f74154ecf274d2886c20f06c98e858861a3863dc806fdb0979f74a67f31eb2715e44696df2b7318252882c60111c58586c47c542c681faf0dac30e
150	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb50355ec647735c5f110f4b56a103e50ded99a607e21609e9ec6e9c0b41ea56385b3eef1976091f97d0975888ffa3538f67aee329a9a97de914243317b76c5e2	\\x06875bdf2922e1b793c670b28781ec46a535a99664d92959c393cbf8e9441ca6e06c84ea6fd3adce515eee603062e4df080ec4497013c219535557a60bea4f0e
170	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8cbf430aac195fc5860e49641ed497aa4d4095235b62fb33c3e0f37bc4fce28ebd29d6fb7385c7f4d6ae8b9354377816e68aaa8c1981ff9798ff953a29e19502	\\xa883e85f82d0e2626eb635827195db18b6a9ed446010fd62e7604ec234164547b0861d3a9e555fa3a98b6fd7ddf7b450e24826c8f85ff1a3e562f4f82be9570d
202	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9a267afc8f49e3fc9f72e2d1a087318ba2034dd2a34afff9cafb6789100e90126471ceb739eae485da8d782105bd513391f73f3392fee7fb0f499f9ee8e707f3	\\xef5cf95c7b68975953b2a5a6b1b251f94968a9e0ab41ab679b0edbc91bdc7ca67d733bf3931ea01e44766f79f7f5ca10e9331d06e99f9d9ff4355f3bf5c7b30b
233	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x09faf89a48779446d9eac44f1c9d90be711f2991f2d9ec78aec49bf63bd5820361b4a1ca857dbb00f9047f088494cb9653a41d50849491c37b01fb1222d4c94f	\\x9cf1721feb58d2c1e77aad6c727cbf43661c275fe335f092ebbd3346cf69c7803e16ecadc8157f0fbb77f46907362ba60fd59f54807f1721930a419835eb8a00
265	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3c651ed012a79239d035bd1fa75d7eae04042ec309e999fc25c3f9463aee65c6fdede3d1e1d178a2947792e19849fd2b377871d4fa006ce2c3580b3621c97eb0	\\x21d213f3a2872d43bfceee446449f6fe7373a0feaea830ba5ab9f492ca37b03aed5445d6ac6c75b7e2b8ef7ab880330f4372eadca9498a2ea4bbd10242230c01
296	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x83701e89de0fbd2223434cfd4d0a33424ccf71d5e8b25b63dd44a6f5155019414b500462bd69f332a489bc84d6c899f227a43d94bca204521d142e5ede7529e2	\\xf6a22a87a120ff03bb2f6d77ee3d3629992a8182d6ac1ac9e8d52321985959c925cf739e48c1596ae08f8a526a837e0472dadd3e8d9ba9c6deb9f464bc4aad0e
310	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbcdf73f86f58878998848930138716962401f306b10cbbc70fb617310dd54550633eff9941a31fb04e0777fa2bbbcddb5679c9cb8b5160eaa1c4a91a2ad78aa1	\\x7dd603693fa01cd678cf9ae09ff6130d862e0efcc7baf1daacdf26bf79b6713b2ccbdcd0e63ae4230b8e29facd716bf96b4eba7aa09e0aafbcf28d75dd94200a
319	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x969727fdae3f0c228423b771a5f057c7ce7afe83174a88b21c35abcbc5d0db58d4cc1ae2ff9b21e663c2fb9e2bd2352439ed0487985e0b2307d6ef1419e772e6	\\x13c609d6dd2b6c373d9cbab0c8174e6fd0cd6a71341678a20da66b9e4088df5b56bfc391c77bcdd91a590b42ad2856f612d513d3e8402facec023a3d91a33e0b
350	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4f0dba382fd52bc5b0afd5324312bbba21b6d53a37c64f51191d3a49f17aad1360c67f9d8e8bf5db7123c4015406e26b7c97a7695e41d1303d7008040bf75690	\\xf522854b2b9914e313396354a3de265930204c6bfdd59a6f50b1441baefc743af2e873ed66bc10995e57df86204f9e48538ec7e40410753f17514b624458f50f
377	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaeb0293ad6d88576aeb50441f071c6048dc9eb836634d173340b3b9cf10be0d47902c0346a226aa4b92d00c90d667933da43213d0c82beb9ca5d09822afe3a2a	\\xcff0cc233ca05f14bc3d8b2fb32b9c3e312066421a86b9413924befc5a3884b3d3dcbc09e4b852162543e2a27b4ee306fea8b330119e1b35adc5034da5a11b09
400	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3f9afad2a8e955359064e6eaecc26a50a6a5614c418c7c0f178a1b1672ef7b28aebad9ad8e82da37e5a495dcb573d23db6598dd83c3ffa6102825865311b1a54	\\x6e663f50275bbd04a07ca2a62b1797fcb010289522c805021c734fa378efd5c72baf546a4f019c6be7dcba6416d161afbc176ab67eda8f180896387de3cc5300
411	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa1b13f8018d510bcdb2bd431dd81766b588abe3b400f9fd8a38c940fa7a92e0117db4b5cefd959511568b467fd0befa737546b274651c2539d12e9f9f66d43a9	\\x1371b63adfee4cc4cc4fa1dca68736a003dcc73a6e43219733f63ac62d25bc514a796740884343556911d34ce1149ce335c19a2fb997c9e598d257645ff68e04
148	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe040a07066ec7bc27a840e4e7e3c76a6fca0ee3987b539c8bc5b395815a38ef08634352b7b50939c6e36d5e758829c7e545d3b6bf76ff02582a9d8a3a59aaecc	\\x6aa278266e9fa9af4eefee08a1013df59382e3a9cf0ad884d776953ec586bb000829c58ed9758024c9ed51c818decdf1534b024b3e014c228e607bf36ac82b08
186	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x185500c270437a923836f505431e9becb19941534e1d8b0a9877e984bf81c1f2255700d28c44c62b7b32efbbf7bb71b871e475804ae2ab3fa0c02779745250c6	\\xca340f3222c4e0377b541ae6612f505e7bf8b0732881b5bcb8b1ddea7530c143e5a07a71bdd32d826eff342b6f0dd75089084b5a34ccd642f971261a309c0202
215	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbc40fda9dffdd6ded7342ba8f0cce726aa833c4b909ec48539ea027e983ae57720d7521b6dd69c003d319edfea3d92069f90febc0b6dbfe0d4af7470b8302535	\\x8f1ccea1f7b6553b5a8704bc1ed04ea74ee655b4d904b2aef05e2c921bdae096e15f92a688782de1c0974e6b961f58c474574c41022202a9068589278b0d8706
248	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdba8cd375fcf3fb6108ea2b37911c963d11925bcb52ecea41c48df39b7b0b386938e27f8ae892437ff45daa377427c1470c8420299c07a6f19f0d467df068dc7	\\x8dd1e1ef925d0114d0318919deecaea2eb72321b7fd9d97c9f3614c45571ee6a823fa496d336d7443c9e3e9f5d03e5361e1b607835b4be1d5af3f173fd151b08
285	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xaf564bb9a8adf7002768ce9b016c5f93282774021ef4b9db4090ad40a021f35a2dcda4ed99fb84fe83b16dc0eed3bccfd1285dabe21c14201cc545fad560ee1f	\\x1c143cb13cb6871390da977920e9dc596658e1c6c790c55f134ba16149c85743e7a64f17071b1a681ebb075674d215fc844eb097c2c73ac9a9c08f5d670a4902
338	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xc83814a0f50141566a2c98ced08d443bfa5dbd32664cd7f5c3cde1a8bcd3888f6a537be279e6b9e704554996470b7bb9930eb8eaa488426bd4675103f67ba616	\\x18aa7bfd955143fc4139ffaf6841b94c8d0af06ff7375f09fb0f63829e9c3b2168972c127e8d726db03bb3e0e5204ce70a384334bdc1f0ce50c84a3cc6abb305
356	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd6887f12b01a4435dc6aba8ea7f1b1609c558b026b0a276028504ab7f8c9d947827c147eafccc305ef5d27ec99a15581948c537bebb5dc1a96a0bc5caab42376	\\xfeb8e65df9b2fc1f7e4ca3f3b5961bcd08b9ca5495a48d65047674141e703268b006d41c2088fabcae2eeccb5856f865b922a6b75d318caa97bf2d190089b804
368	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbdfec0ad97e73d226fd6333530b4d01dfb0a652147bc171ebfb450f9547146de3e48617f3a0674f3a5ae52987c99420496d185a7b32a5edbeecf402ecf26f7ba	\\x8413105ed03100dda1d34b03765aab6328059239d53739e5b82920be66f0298d13165502dd780f36390ca1c468bfe080862eaa86393ef6617b182258cf96880d
378	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x054e476357e0db206d5871a29cbf9911afe8cf61ea6ff224fcb6c3c2abee737e18432638bc489a0a7b2ada7901515e6d494edc25b8f12df0217d05ab3e56c971	\\x81d03e205b05f3e51d4a3c0e3a96a280782bac5cf01e52be9f5a02e352072321741b4dc57f7df7581566a4e70e59a12dceef3a39b0e8effe9a0b513b6a179f0d
151	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x767458269ad137ac03727880d09d5bb84054a385266c3bef4dc833dbb16672f82b65b7fc1608d4a4e7dd50f29851eebc0ecf5bd119c3afa67a37c6cbf913d325	\\x0e4710f7e918d7e782e6520b59669d656923e7e8bf0674347c4b2e98caa890247a69623d554f11c28bff45dadf226027d970c8bcdb3e3fa439635fe00939a30f
195	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x906d4fd8f06065dd77eb1c63f75ad757c68cb9d884097927ef6c1a75501b98faf25a4d115c710b1b1df3df33ab6fe139d861f98cf9a9faa9844a2a13df46dd93	\\x8d0e2c61675fa989e62a93d03f3f2fbe6ca414aee7f8a28637a4b7af6af61046c91f9023db11f068a2c15059913e0502253be1915746b82178dfd5d0b9b0080d
239	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x215553f58d16857cea419b72c4a73bd14088a80f8805835eb918cc308a0fcdba2b10d301bf1155adc710b5fd037ed4c8df105c09007ca252afca16a352168600	\\x70b618cce8a560c16e492a1f25ab4aa90175355d08fa2374621292dcf8c7ec5ad7af2170449ec2ca92ccb0f14c88bc2190c847ababfe204bea2b0a9786e92901
262	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x93f0c55c3d6b00a0248ac16f54f0b63c4aea1a9488b134e7b688d2e3e0728118b2624090daee6814a2c4541ccbd876c90d1e1cc5f147e3cf2a9eb86dab7eb418	\\xad2ea44c3d11114a46b639570deda79d74bc6d5ebdcd3ca14e2867d489cf4f20c08eb23cd37b7c76172d7d7e727f99547f2c1950e3700473f4f6df9ff1558b09
309	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7543683263b487d85e9c6069d33ea8be2e6650e90f36bf944faf9094d356c811e46650f171855d6d096a8e759b5acc961315d43756a6c6af6ab14c287ae5921c	\\xb3a59ee3e5b9cf620c73710b0a804b7a9e5b0878066ebb2bdb87e19d4956266f35d1cface7d1682cb9ef5fadcfb488cb9eeb98c2693f4d3e2dcbeb66d0ef5304
322	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x928b1e0b246835cdf7d641a9baec947fd4483792480ce41daa4f179e7b4e6fd7a0ac291920e1976773a3fa1502a197666119c763d0dc4e60ef319aa7900c28b4	\\x6078014462b5464bcc2363f5d41540922edb6f6d6f2a4ff39a1794cdfc761cceb45aca8f2132ea0d6dbf46aebf47b3fa87d6b200a305f817d6268e8e95f59d0b
364	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5fe02e12f33cd2ea4ca008ba7abdc8d6b77289654439bddda1394c89891e99f4ac003731e5b86fbc1f376742453e87713ff59b2d7b727e0728435a806379b207	\\x60a27e251e7278ed1352d7d5f477bd9024ef683d18ffe95622500d9e03cf6074622d47dec540fe30c20299efee3f99e3f1a193841e0bf559f6ebdc0783aed907
395	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x58e40cc8330e2b1465105264cd31a65b6f13f67091e619767a33970901d966c34a5e3ad1a382ccaa5e7d1d2c004c76aae9b05a645667296512e38b0e30f4b27f	\\xe9c2277c7c6c90b80a9c40f1b07252f9e542e944a05ed4e42036f20fcd71134fdd9d01dbb1ffa8e3acedf1471bd6cf068425ac990865398f6561ac50bb80390f
419	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbdc8e2ac500dcd1c2ffb58d54ce8b3aa9a585b2577f5c80c6e07da659463b1a25b678c7380345639d15ed0f077bfcefd96a35833c87a45e10df9259f03b13961	\\x8465e94e5bb8c776825ca763191872d0ecad44e5a7bd6fa8d3fbae1669c3ddb792d4314e90f35d4552cbfec4858469e08de9fadede8c7db3bb38a2ea72fb130b
153	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd4f4220ce3f9299032a5869114be36b13445e8391789af6fe6691266cd908246488d85798af74096d5587fd3934fb29d8db0adea326ddd00dbe936b0951ae5e5	\\xfe9000ad0825a206b3dfa6221de0d394f207cbd06cf60f1f7190c6e9e238baa999af651b7712ef76aa20ee21141c949755e5c1a5070f192a262ccbcb0e05150f
191	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7a4f6c979a3fba1965dd6f4a671f088e4225f4d693efc6baf9fcef900802fd433467c9cc95f71624236685037e121fd8a9f933f41f9933bcf55a6edd71039568	\\xef81f497920dece2ab58b10e70154d3826f98d7b98880ebf70eb5ac31815cf6ee396aea1cb41dfb889b3fb5a32e37ff086a3b1fa2dafc5dbe4b349e2be4bbb08
225	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5ffc5a14bed3e8da317c1c5ad9d8d7481fcbe0cca1fe5657501f1484b9b40639c91ebbdf5729c559fa4db2e675e6266f4b703fd92cc8c312776ef4b4832733fe	\\xfec385bb6f33d231007464437301df9abba6f65517cf94926cfa7b8e26e590111b874ca82939e93c959e5187bdb6a16d5f35c4134bf0f1af7b9d4c316e81a602
275	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7d140a26b1495810beed3beb48c568bac90411dd778001f9d71f9948f0d003e65083b18d716752f5fc2dc687dc3621c458f14137389153482260c790ba4d9737	\\x293cfb41d9fefb0483848370e384f3e95fe93e901c0cfe22823f03d6edabd5aa1bdce422d492f18a5ca4b936f8458cc2b250f5b4e91dc82f2d832ded33ef5603
297	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdee90fd3817d1bf7169b50491346d614aa1ab52f5951913ff474e67e2cf6b99e72cf3ba02dcd004f25b962c4fa0abf1bff87ed65a72940a03b0f7f5411fae46f	\\x0cdbc097b5a33b7b6d3b40be95425cbe3e06284b208fa7384120bcbe9c7169a817833df76cf781e68fe70dfeb0ae5b76e810132545f0e71591071bbd4a467b0a
320	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xcb380b038f64195694ee6827486f37eaccadb5880ac8b141fcd91661e5c2e567134eb273fb6421a4f041162af0fb5c7a8a4b4611683ba723cb51c1f7a48dd5af	\\x5fb26458e3cc04394b4334111ab48f8e3c6f110b57bec9e12e95de2de9d8e709007dd40ba468d2597107b72e312850d2be2c383f0bfea386660b0e6b18bb7000
331	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf2c524d66466c1876f5519e4642c0f6b9c471a532b96ae985a4652be3fcb948fea692a9619f4ec2bdc94e8e63778c79a2333bb3a8f8e884b83fb9123264da714	\\x7d3421a382f977807a880ffa3f8d88ea1c463ff6a94ce2c2f22687815cc9718f16baabda23ebaec7b2c2df8fc3df36e146a063e5545a4cef32a66e6bd496f205
354	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5a2a84a21b02d53af7d9ec3e20632d9530575029506f13a2ab7db0b3919da98252baeea8f3493fc9d996b106bb594e39842496f58250c9c1195a385a1f3ddfeb	\\xbb5fb60d1e37743ca2c368f24706150e8fbce626b3cb87d2d21858fef80a6ff6da24a4b3604271051865803e5e985b3e7554928001a3eb1f8b9a8286fe163d06
361	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x384dce528853053bbd97f2a40194af5b32b1398f4a6ccb001e47d7c4d2e6e05c5f8dabfbb6a5e8f270ad6b088b507d7d57e6d8befbfe05fab28b63a15c91be3f	\\x42872fd45f20433f626a7dbca474e46bbc8e3d8a1dbb909df2335fce098309cda0f3013b121158486b08281af9a302b023cf81ba1d60283c32600236cc18bd07
385	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x173a96e219d642f434c4eee25b006f06068f64e12204913c64c839444abd370a1a57559bb7d90c5a090a2d75bcec11bbc58126379659ca2a59fe1ecba5c84d7d	\\x71739a465b69006bc629cf977a6d75de34590fbdd34a2b10d00569edf4445b6b31c6a8a2c4d11689acc23d3c65f24a362e3362c38878f22e196c394fac256700
399	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7746155055ce35286883f87045f5026070bfe13c5da4aeecd3dadd34754c761c97e3ecb5681a16bde696aadcc05dbc335b6df60947eb318160b030e52c209a69	\\x9b2188917476fd5067ce3876553cbcb3619b53632bad31b84738d94a6464869a6f06476bdc81281297e4f5e7a609a5421a737a6b6b30250afe671f70d07ce30f
152	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x581f4b9ff7a2dd6d89e26ae1d367ff34ee60c224b5c83105a8a9cb541b5f7bb27e2f306b3f2adfcefcc9f7d9fa2d39aba80d3db2a2d1da78eabf937e907ec4c7	\\xce6691f7acd499dd227c0d3e469fc901aae1ab0510d115832d3cfb469e9fc2f14824c45ffdcb00bb94f5e66f1222394e79ded54dc19c00ceba0a69bb84e2c70b
174	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x28d88bdfdcc86b12d9e48dd9d1edbece418f6f160951bb78067a6b835aa44684b42ad4dbcb53d907a60aa85111f33c33671dfaa9cbf5c1048c096c03febbe9e7	\\x8aa6fccfbd681969f4ea9d7b915409c720ca69e3a6b144c80e55bc4b5cd109d772561f7359ff8a3cdabb00e0fa17f5bcf920893f99b143a40d426b1ca904800d
207	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x18fe18e4b5f9f0952adf468e38f05191844b1271e10ae1e190dbc7f636e86aaeba7d0cd929cb2819cec773c94a0db7cefe47c7ae6827aceb7ff9e37d1039e517	\\x034c56f6726d8643d8ec8d1cab07176c84843d734e8cf93f7ba394e38e6f56a455d5c9104c8d0b62f080f71506968683c48ad96353c059be73470d02caadf801
249	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x05e3b0e55323faa425d7e27e05bc1585f7c24777622bef050e83690a80c5335b394ba8ad29ed3f0c87c882e06df2296afd90db5530b2e00811dd00282b3b4dc6	\\x79ba62527902d6ecbd51dc3fea40b5639fb7694e556b38a05a6e1b3a90b3c814e07f6e2b75be9e1ccb6d257ab4884d7581b38a6c255ad67c5f1fba2daf7a7d0b
277	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7ffdad41511ddab51143e1a78b416ff22803214fb4916fccb9f712cd2daa0e12f438bb854b1ed4bc816f4e42fbfc65b949757748b2bd67cbc5120f05f531036d	\\xa07c3fe644245a54294bd71bc0dca506e14990f82a48767eeb893a4903f06e1f1a617cbd5cd8fbbb5a2d9381c71056f4d60cdb2f517709dee86d6363c89b3205
313	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4c39d67368c2f1ae37d5ef08c3dd9697eb7d452fbc567fdfec77a01d265f3e1c77d8390d008aa608cce1c7df7fd9b3d96335f8b268f498b53b87a43d4ff03dae	\\x26148a055cedd1e4309ddbe0d8c9a9d8d22780637001db98d678c06a9f6f337d3fae7dfc700970ba070afe69cd34f49f934ca1ff58ce2e72dfc36d63226d9d03
327	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd4de6d39a3967ae695a04984dd4415eebea61aceb092f52f38b4f2dbbdae62defb80c113b6b3e40046dd259b159977c1f07d53a6252a39f8774c597f1bb492a0	\\xc094b52eebcd125d73988048b41d8be587bd1958328c721159a6077a2dfb1e3cdc59997d30127933cc6ffff81301be888bc37855694c3637b22b349253c68407
360	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9f588334795fc8c4d31eb3b3e1f5e77d3282b200abedbf1b75375b9c1ac2b078bed2674fb16033b9a766ea09af135968d6377172d37026fecc5c56437fad567e	\\xca1631938fb244efae51cd06b3fe8887fbb7e216a961957d5fbd32e7960824550b32b86db4526b8079f9e6bc71f745871ce6ada83a8a4c8289b71e6e555a5a0a
392	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe7922d76bc5e226adf360dbe38e239442c53a0a78fc0ce28a8a323c7cdeb3827c1417ae17edd68c014364893907fc672ed62d9c28762cb371cd345303dc989e2	\\x2656a304ca41516729f8328ee9f3b7e022da795066134f00fd7523163c7ddf503e72da8ead3a69b8cffd9e025bd747ac525b182548f19a438babf0108614d901
422	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf153af67387550e181e7d873683235e9fcab7f15db6e43261cbd290d887cb1b1b373ae4401b4b1da8ddf6333cbaabd07d3498b5f56ae4c6209f2299e50d2c31e	\\xe4a0402f9e410a30a772fe2ebf8e0e5c3459596764f8c3e1ab36deb4e42a8e8ae8a0368482a9db1b71bddc5f48bc3becf09c66723ca298d99a05137b9114bb00
154	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x763b59e9741deb9342fc02f68d398b6788cbe56c2fd646ef68922412cf9386abf21bcc7edfb2dec97129fd3b8ab98df500a25c63b5c034169747737ff4881d10	\\x9912f929f03936e10c8f8bd963da9cbbcc186c6326a82ae80cd1e9533f5a561179e3cadd643df002ebe274902f4d6c9915ba462ee3dd82b75af39be26a4f5b02
199	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4c1f466ef5e29dd3dfbbd5aafc8f96ac41c8b47685c397bfcc37ec545b63d718380726c6a0fa75458f596c3a9682cb210ede5474fdf109957d41b5b9eccfd5d6	\\x1fa808ddd394e9a3893472d96df498124a71fc26eeafcf3359b4df316d7030d9be354092ad36d728f632a694455128b20774ceb627faa81a514e4a25e6730800
229	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x17c3ad9356db749540291046f29560a2baff08407798e13a240f98a9d4ba6b5c7728e5666953b72d314057fe15a6af9351e171be54cad08a78eb1582bc00bce7	\\x20cafbb26bd225cf012244c52287606b6b519a382ebcef8da88ffe72b0a73e4d4983ea373ab008481104c55c576a583f98e4078275015691943a85e850f92f03
269	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb075837a3dbb85190e65dfcbda69d411f91fdb49d8b26a1e8db89cc2db0663a0350b3786e285dca51aed63e90526b9da3e89c203d6fc86fed0071fdcaa6fdbd8	\\x2fda779254f55b1e6b8248d82beba6ee91886548de3dd0ab0fdb3dca8352ae9891bcd218e3323c6a4381e117f12f7f7264f0dc9fe375db30b63321fec22a3a0b
302	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5f170cdd59597bf9c6c8e87ec38a335e04edfb06944d19a906432cfbad4b8236a04d9fae0dfddb370971b9c23162133208b50250bf689f9da92ee1c197eaebdd	\\x5323a8aa0457f495f4c6af936c6364897168dd5460801b2e9841461a2c2abdbfcd801b8a85fd0ab716a0f62576e8ca3223f28504e27556dedf74755562623b0d
353	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1156bfc610287aaadc4937ad73d1045a6a0fa294a5bcfa36aa9e23e5036f612f9d296fe054ecf3c03192a66b0551fd9089bd62043ef5f2ad012f72ef324fb127	\\x83fec747eaad2fdeeaca520a24e1e0f54650203f76ed8f491b8bb00e28655e59113fd42aa44995fff8ece162ecb9c61996f122a65b2457dca97f406589c05e04
375	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9cf805688731d99953d1d42d38e0cbc84b4feb2ab750d8f467ed21ee2449f01d10382663d3feff4ff4b343146a1b5aa6c0330a88de0a7d678e9b331fa9a98bce	\\x34daec5012d562871cba83bb53642648d198c9ed9766b23ce0f60a910778e87c2d0ab1a2f7cfb4bc00bf5114f2cd73d896693043a84b06d628c61927f4296a04
394	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3c0fad15bdbc5fc67c76e38f7a28c280768388b672c84a74d053ed6d53bb131537af8d1cef896d9a50b7faf02f49f281b761aacc14f8246b64cc8f059bcbff36	\\xcd1b0c45193cd7e339628d3e31cf48c633b928f0af0f2af531c3c315ff466ad1deb4ff581e7ba2011d595be601e3fb4efd3af5d584416b621bbfc6b17df42104
409	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5851476cc7a83e033405ee5604948528e6eb57c11c09b5e8af6273a6510d9a0082796c1cc53d65ac5c3c0ec7f11818f9d49371662916c2ddced875199086c852	\\x3fff8671e4dc0b6fc59c565ddc403b1d95f4f1f210670c72b8419349922c37a5322d84c66c73f23d1c3a101d16eabd3c91489f522fe6179ebcf432edc26b030d
155	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x0e4ef3c70281267662de75223ee7037de05c5d467d68d256ae182cf830e8af5076f1c84032edccf6eee0f215a83b829fc06b8a7335d8f568fc01f4f13edaa503
190	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xf43b58bfe3c6b1a4eeb6e8c2f88ffe9253a10faf7e55e077287d4d5824cb96a42c0c5cdc483ca0987091ae856855ce577bf327e989ed2a33f9f07938b76b3123	\\x2130364226fe0bf9f31f5a225b760c85902dcd2f28b450bc1a04d216ddd3c7fef15978099e7ab2ef830374e1cfb00e8ce62ced4003f7512efa6c09f0520c7308
226	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7b5b43c8fefc86ec7dce8813caa7dc0f101eeb588984a51254bf954fa708dae8d19fb68a4a3d1fd1b4f5ec66298e99e4df6d07af2c9aec297a7e138c4113d310	\\x23277dda4d81bfd8fc964596751bc4adcf746ed0e4e9113dd890f4c015b7e034dc20d4daabf009736bb854df78a169bba2047aa8266404895dc467aa17b87a0c
264	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdff2a212a996d15e08475a90ac82473ad64409946b40b5f9b102f8c0f36701e877faad77d1f485269e795f512dbf175dc7283bce16554b0d36ae74234ab28a67	\\x17ac692f5be8d6503d8b35460d63ef23685dcbb2fa410e78eb820b7ad8926f198479bc34565b13be2f4bb9b6e320d6b3ea4905709610aec5bd9dd77c8f0a1202
294	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x559b9c96bc1cebfeb3833243dbb450708ed0539fc4d27188fd3cb22332b3c185402e8f264135c1407d8884aafb3f84c0357b4c29cb1bde88d0cbf6044194a3d5	\\x85d7880442689c46c6cfd4f8677a1ea07648af151c386b0f1368cc45c248ed99087d9b5164b731bca7ae92922f0e6f9d95524a506a3f39a65e86f8e32a007e0f
339	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb03dca0d83884e78559efbac7086d8eb206f6f39ffef52639ef51c3c60b63b5187f2b80562faffe43609bd4e146996981565375192fa0e7c6732302d4e4b69aa	\\x9c5de105e99ef3ade743d8a8a8835538c939b8192cadab7b7952fc4204c47420b96eae0f44d565b3773c07d0dc23c263863c38268993bfbf84db4d198b38a40d
357	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa84ff55f00f5ccdffb9a8a6ca7b71eb8ca987dc7ecbc6865c16010eebd1c820f654b1fe42ec2eb778e9b70a1165920876540fb8d48ed8f873c481f379d4eaa47	\\x7605f897a8d9462b9db421874e4a51db486c3fb7d05fe22001a53ab2348a90423db576b8accbf62b32a71feaa6a9237e6d0358e74ef9ca101d9c92652e7dc309
402	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xeda61f2cc0790a725eff386afa9b0c1e7cae584b5a06ba661225878efa5f28426237bb4546a0704b22b0f673cee044193a5c1f2898b8eeb7590e643f7a27fee7	\\x7ee9ff5fa34b9727064b9a87945853814a8d2af87744bb78ac145ed5f5b1f1bcad75e01354511bbb98f9dbf5ec9ea65166c71c82080ef005c62bd8e8bd1de00e
418	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb4ae7bf81120a4bbd762801b179c3efa339d64387de969bcc2e6bf3b4dacf83fe1ca5e32c807986493d7aa3237dbdf7c63bf17ee395cac5606e798d58384d372	\\x44c2888911cee579b9477d120ca80b4d4fa965aa47761e5ecec1f0c520208a7dc9226554e687ec1f82846bbf130748264530c6a66cc1e53f5398dff9d52ef90a
157	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x864915345ebff425ca12e9ab5d843f54571957399f833cc6ea04c3a9c04ed8ecada8271d3d3a1c18b567d8f684386c036fddd5683fe70e6e6ba28c52bb3b08cf	\\x80be1a101a9018a4015bf7cb1210db04992d1cab9dfc9e441006b09cdd8cd58c73484c21a9d946765e2e89f5feb79fc73bca7ec0421d473dd6cb91b9efcf5400
200	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2a21e341dbd3a114c31dc4300bff658dcaab1225cc1fa8895398030472b2e14b4d68b0b7f85a3ae084fd2ec4934b21fbe5ed43b634b1bd86ffdb6523c719e620	\\x443aa280ba90c4d5c376fa202d3010458ca14069175f792206c74c256d05db5d7cc99be4d297dfcaf5c626368c506b143003082d73d7083a31dc9a37117d4f00
221	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x18bb9793efd663f85072e7d7631237d4d1e3ed6049ec17a2906a8688d174789620ef310c7b776503bec30c484fd6d2cf39fbf8c8b94f5aaa8a06beeb9376884a	\\xf300d637e7e5aaa598919b907e3434b3cc0482b6a46149620dca7b9a955047c1d012ac4d299d49c5c8612e922e356ff277833bc118191271ce7936669fc98b0c
252	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9f5f8b8aace5d0b87e8951db0d403a622caf8fd08c325d89338024c2edacc8e48b4ee82d655ffc2175bfd1d7978fb861cdcea18325e63baf45a2cdb99cf5fc99	\\xa65629fe927e9e40be85ffd2183963c8b1c9a67b612d3f39bffe65a9af3ca34afc362ca99a8646c6a7c3e0c0c9a1287ee2f0c617510ed8656f4ece8eb83d5e05
271	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7e8ca63dab8779102823b89eaba30a60d8d7ca46dab6841a370dda4ad0b5aeb6d0b48b519fa6ff17a3de45f9321f939da198385831c51d17ef975ed77b81068f	\\xf5a6f712a2921eeab4c01ac5e5a0c71ad1c41ef49f5fc91df4131910d17312e4a40e8337a1dd7fba707f3ab7d5c3fc9ccd6a9992dbe2f98a5d1c6572e1b08b03
308	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa1e78c041402bdfcc4c768bcf65b931e433b75d7428f6d0315c5ed1ee80f509dfc44d80c2c6548f101af489063d86355395ecde1463f42f7fccbd0175f2e6f4a	\\x4d4b813ede1e07a607509c7b0dea51472fdbfadbe5a8f4353c0f6d860bdb9fa5f90f68741ea95df22c5a6181d9b215d9b7ca975f14e8e07daf0dc6a008fc6d06
348	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0766a9c19fa1c04c5d7286613b990f4259318867dcbb098d1a0d4c42ffee8391a2313ed0f4c323a04b18167cb2a227b78c61eacabc4df92b8953cd027b468686	\\xeb850145840c80a7f0b2663eece7008e39e31807503315d480ae311bf8cc66e477034b1ae4ba9a20209507cc2ef0dff2c8a1c36f82d1d83b35d9a04c6fb78c0c
359	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb9fa670de6483aa824190e506097b0f4011a9fa1f5d26e46842d6427a856ecc9e7f5f0b19e4fbe93fd0e1d3398d11d6cce96cb948dd60610552ff61625c7018f	\\xa7a7e947b1438dc4cee21e9604108129077d8da47298a49a582895d666705b78038b6b05aacaf49c0a7376d32e5f5fc4dfaf7f1ced609e2eed0e9669b831fe0f
376	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd5a94b5cc6938082198ca42fb6f0046841d0b0627ce9fa07c426f49d2b28a632f12a6b5a5a9ee4da5ef7e30a58ba01e686da5fa14a78cb485186145b2a8533c3	\\x00c40e6dc9d9aedaf65e67432b5f75f845c7fb5202e6bb2d60987021d552721c131fac6ddd34b3b30ba3d3893c630c65347198bb71df3ac38c532262aca0290c
406	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8d8741eaab805dca1f7ec579f9d7281f046a781b279210644613d734af163274b8a647ba6ceff7b70afe9f8723c02193f9fb84270d410af67d2ab48076421b27	\\x2c6b25150156af7dd4806bbd143cc6f725961bc375d94e7eb2951f49c09ac6afd577bd090fd1bee5f2074294e33cf2df72d6a69526aded3d27e2f758b1febc07
156	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x84768be589557671c08519e39c1dec01cfe64ae7f38167837ffe4a1c47c0e4fbf9207d09152b1004fc3df670e52d69b9f7b4ab6139de8752002b623e93245f6f	\\xc204b3bc949c1c18c617f7f6bc2dc6592f2380b1d119c31ea436e4b2a7437308c24741f8a226c0f0bfeb08fa6c29ff4c999b3ab5bf31fe82e823fdea69f49404
178	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x94c62122fb41b716c4713b82f59b89378fcb96eb2130b086301b18907cdf5d6a37f10d9161f5324edb36e52cdba8b67c5bd024c7dd02c036c4915cac53934941	\\x228aff5310506f12e76af8050eb791a096bd1466b12ffb58a41d1c9722ed2f7d1e1988ff0fdf323c32faa3e5e7015e57b0e87406ba90c132cf302fc807f08202
206	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x493202ed3ea0e12b3c92295a3d733b458b63f528205f61aafd0d456f2062bf4aadbfb6680388a15ff584c47fa47e6c5f3b8f010aaec3efe7203e54a76f40dc1a	\\x13d3b589bf88d974fc09d0a27cff36ac2922f072279ceed5eb3f2b0231ac46a509babeb8e124af0cb6425ecd9a7e4ceffa1f510583bd6b6a2a83275c7be58100
236	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2524de57b2ecf9e0f53cbf0762df54c8febd3c25b50504162b8275a045d6f1359df34591f6ac5722587d8d1dff36e7ad5336239ab4e8dcc8755f9aeae05b2c19	\\x729ed83e49b46356393b7e011e1bcadbdb28098217b043a2b21b8bde44f2d2723c5da20347345c45956f15c84ed7e6dac77f228505a64b624df9093639f3350f
261	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3ab5cd0b8fa2e53f327bf2cd451e38aaefe4564396edee4024cffb08ee2d0d4995009d912ed219615d7ec6d6ec092f176677c4851bc7e8a0c04507d45c7bab85	\\x2b6028bc7e1ea5a453c7cdaba439b4ffa516a8fdfa621d8780c5c3032e4748a6bd8058e3255f9c8bc32f1c7a80497e67ef4bd92cc75665aebd2956a495d52c04
291	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x56c53221adc3e7af1286e24557a130012680ab19d176a2a29c8b5898662b8700e876132858acd52d00823a08cc0b574d9b238dc2937dee8c5a4e3af8082bbc68	\\x9117b3163d6d0f00d73d44ee80ae6ef5142a3e4308cef0eae764515283d11c4440a45df31a6e9e8a7c6004e2616725661acc3cf1967310b195e54ce1f8b66106
321	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xdd879577392ecd153f59c3657f89286216666d4dde56cb76618bf7d2cf3af62bd3da02e04c8c192e80c9104f0e5f658d4784aa26aa1c6d72efbb842a87c4a011	\\x5c3ce7b08d20c5a8371005f71cdf484c9e33e44786092ec4772672615845111c53b2923873ef56b1948d4d152b1e8e6f6374ecaf3d71247da0824517daa4890a
329	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3e0db82f7954f39dfd366de4f7f8f9d5622bc1890b039e39d9c8195ca9b5f9a77c65ed3f4851e56668334d6971bec1f95b288df115ab399afe0fb7259a96f47b	\\x51f7991bde60c4a0ad2f6524b78ea9f4cfde85087beffed90e0a7969472cc5eb7db779f8bf0499251a8eb1ccf2661f389e4b3cc0850413a03f15304825a47708
340	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7c119cf9e402317362ab5218c747546f945c4ec2223ddda952cdc10dc6a9a1afdad7513c69d407ccb9abe1f7021ab6f092e3e332104cd0f549cfbfb6f5c16298	\\xd6a526ddc5dba8ddf2443918bdd9f68528f14c59df54f3cb83b891dfa4862a2bbd62b74b8d17e1a883ce566075c0dc74e8d439ae1e25ed5c52db51175e27c101
369	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x0204528843f51c8b15df2aea11e8f876900a2fab26f4550d544a29bf4d09af8636dec8fe8ea07c837e060ef6de344859ba0c07dd4c74cfbe951645f595686cef	\\x34e83d664f591d0f2081b56e2bf9a3021e6a709e58619f350a7c2a973628395d879af3359a83de7d8c4dee78ab01501be446d83d61c50dffbcf46a2e53b5410a
388	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x6ad73a5e3e0f55ea91d61b234b83a90ce58cb33a81494b0ebce5f0ed06c65595268e106ee5a7e6b9d324b1cb926ce4a4ffd22017b0303d09596480ecb965deb3	\\xc088416387787cb937e5dfd2aa7d13383fb16a24c86f78f444b4287041e075228baedbf1278e8a17f49c7c49121d05ee005465a18af08d57f518551fbc70ca09
158	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xe8dbcdfd80f76b5a585b386a6eee94e5ddc731f219f01c669c3d7fb5484e346b52d59ea213f8444e296ce16d0d424985cb2c9258e87ba95164720fd10cfdc9ce	\\x11d7c37b57f2baeff0a90b35036a9ce0a0565d3cc8b85d732fffc00d9612ec847773c96d4dd73b7b6891a62a32e4ae107f51a85919459e806860682a73fc5a06
201	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x929fd5cd36949537c46e40b1fd1d78ae2b7c2221e6e9fc06786f317417205d052332b78ec6bf7db301403338d882e000932e1e0b2f70636f0f3007a2c2d17e9d	\\x18fb996461e94a8f90f0587822ae3d300dca09f764083cc41a6f237f9453779fbb2227783e6fe23509853ea1210a2f71503acfca87908c1f19430066e4ade608
235	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x9c551c30807cb4e0dc0aa581e69b8c1177eb61daf9b99b4a910dbc39d850223c4d5bbd9bf1951e2cf273d60535a3140b553cc52a77bfcb910c2d992568f94027	\\xe4910cb75949e3d32fd38eded38b78f016b1bc053befa35206c3ad5ef4b8453406b076be195f00403254cb7a9b829e6e27ed868516ed3298048a8fc6b5ca0902
259	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x36e1eb3f970ffda6c90094fb5223591f2ef58c3c03da543a82b34d565134b28bdbfa06f0279602dd8d6d84fed0ff80032159a5ccbc56cba271839b1e5b879490	\\x443d915b519efdf2e37485a2c980232c4ba1d865a0b44bed32c5cc4a8c8ed9f8297d7f7a3a025eaf52ccf1ab748380deb9b02b6b2f313f3cd697d897c972bf00
292	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x38bba7b93a076f74b7f1fb1e8863a4dc87862678d6ed879e123f3977ed8f24174fd3a1333378aa6e17692043679ce5869162c97a5a6b124d7ee0350afe52be0b	\\xbc53fc128ae3f28e4e69e534dd55e1bbc8538acf81d49c70cc1db06ecb40e3f1a222a890ee62447c09f0341a691006e3b383a527946657e467e697d852bcc505
311	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5f06a811883b4edb182a9ae11bc1759634a0f96fa6cd542f84a2e693a025dcef2868ba5f647597062663f4ec7209e661722365f9c0d619009a398240288dadbf	\\xda85656b6bbdf09bb4686565104501580449174423a0df74e9552217e1ba509fdf556e0029c35f98036bde31d3f7d751ee2a1aca241ac035986fd97b6d501f05
342	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x688c9107e8b0193e6be6d7d29eba4bbdc3788ad5887e04bb24aae621f4c6586979d07601c8f1b87b044066319faeb1544e8fe077a63af8a37f856b2d182fafb7	\\x3d8e3ecc4520ff8499f57a09c2f9669bea032c2fc7f693c9085d17cbdc8e7097ffaf29683d0bacee914ad3b419c59a1a5ae8280355ef41933e63f0beb5f73904
373	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5020deb0ad1707b6dc14cc4336380ac8c1d81288c75b64a68f779501867781c845bc0188a92cf5eea6adced9c008489df799c402066dcb95e91cb32151209aab	\\xa3b75ce20bb0c459675c0cc59069c93612ff637fbf796be4bc77fb5d9a4843dcccffd86820082387122ad4f0089e3719a7428810e289a01af424471b6708600c
393	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x8b9ecba93c31593fb2c57c8db59e8e12704998949ea32b060e371b41f83a1155c860088780742512155520cf45841af7a9acb3a9e2f062f777c7f9d8280d07fd	\\xf25c2b7649a89896de3bab3376fc78f860ba5766586e6ca66fb70ebd7bb74b967ff0e3ac6117099029756a2223771d41d08be2ef46238dfd1ae767379810460b
407	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3df9770b94fc433b28d1276870e42e5bb5a7b3bf3b8259c9665858573fd31cfd1993fa26532f2e22a1ec943e0c1861c8e26aa0e25491725e2ba2abbd6b3a64aa	\\xd66bf2f2805c90d7de9803715e38fc45385fcae1ad2d7dd1e2c6abb80e9259929b4c15d2bf3ee852f88fbe5bbf419da02e0af5548384ab097fc4e526aa615a0b
159	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7df6903220fa0572987de31c75baac7ce63382a7d673c9146e85c94250fd7d0274e1d8c37f221774d5e525248d9ca5b7cc5558a1923985c87053713667cced5d	\\xef5ec9218295cce8bab0eef2713b37ee8999030ea26efc1131ee576824691e030bb072d0f6d57c34b2442904e7719cb7556bd76807a06cb0ee62fcc33764730d
173	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4c8d65d4906ac5751202b2bc10848cdfa03eef1c99503b0d54b347043f99071b5fe2a517921834f547414e9bfab101c2e751f863514819e6a815ee59439f0f36	\\xd0ef739c218c5ab0611256e6c002045ad34411c88efa1dc90fc5955b173d1eee521b7c0a762a4e063f548953598469763a1ea417d06ba8b1f0f53b78a4fc3f0f
203	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4960602766c0781ea2e194d3797727aff52fbbc356271b7a53d9d2e44fcc211a9854aae04af20b3ae16c1102fe1e76d7ba173bfa3d998e7b7a2c1511e8272991	\\xe3ad3dd772eaf5810d2221304e7e3035849706b7d5a7b7daa86af1ca789eafcf38a75f19b05133d605da9ef0595491ef4ff630a4256084aba532b2e61f2caa09
242	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb3811bcc0db353a543b3e1d2816d2bfdeb67e68fadf132e4990a9963053fb33067e2c76d639920b73c19b049d5e3fc1ef826a63de46f480f340c64ddfd479bdc	\\x55c3d09a1231a8756a5bc34e37cbf0c48a55af2e20fd601b1a4430ca74befea762981d9e292cb92333559e17a7e9503ea73c7f681f89529ca8c85b9e549aef03
272	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3986a82708abb4f49d883f4caa1f7cfc632124f50e3331362c400934d3ef603ff690f462405941ce0319bfcdfe32ef4f07e204edb3a3730bbc5f1bee0ccb449c	\\x9afdabad77dfc9b074726def7eba0115b5fee07ff172d654fb0ffa95649e1d90d386282c384b2ae17d96f8c5c69f956d267b29b029afe1296051a3ebe9fef009
303	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x11d92d4f06470b9c8532762ce7357e0f60de5a8b4026c0572eb80fc61fbfdf6ba2e6bfd223f9d6e9e037b2ef91b65cdec143f6657314645065d492572cb63b20	\\x5cc88b39efa915a1e7c458d55cce5a35219ec9480d88dae815cf25a7ff417175677700171f263383c7258a3eddc8feaaa8fe67d13538b6dd1bdbcdbd6072f408
304	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x461ac26bd46983442d209f1192941df88c6021a0dab21a154143a7359f1fe0c2f2b8ca02e6c8a927a4719f8da5c0e238e9f1ae45e5b873d470565382c145d174	\\xcb785b935260de7c354da3b331277d8e16448abd1554d1d76fd1328f8bc3956b7eb344f296a59abe979fecb102e22bedd01652d51d54027f3a40805f43ffbc06
324	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x1e571f68c1291f455ec8893162f6e8cb1f059cc6eeb8f993c5bba8ae3c876e42088b6b0ae5ce3a14cf49e2c45b42d1fd26026a9460c9e48d1a5d8209271aa689	\\xaf290c32343cc6cae8eb1b8eb221d193f5bf29a111f323174c9dfda09e337a23bfd746589ecc69674740e694dc5db7ee344ec7178de9606226c5f29af606ab05
332	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4573bbdedc626aeda846ce75e31005dc2993c583ee12ee1b22e817333080e72b2c89628a53ea0e573a199a6f092b9d5f35104ff76994e6cc8d3b4d391d5ea98b	\\x569e30fd201bc775b8e24ef14588cb8b55b4ebdec524b96ffea3fb1ddb9ecd7eef3f46e48a2a609b35c2e17aad0724a140155635e046b53de51164201481d800
358	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x84d3672479ae13be053edbd21e37ba6550283152cbb10790b59ab71b2231093e098751dc121ca1a7ea6fdd02eb25a0db92e0024ae568ddcfcd4fee5585520cd6	\\x52f02641c84b7001679fe769ff46a1f1a4d44410fa361201e718d96604707c7d62a94e70bf5be69ba1a905563294f77b193cfc4db753ea6328eb95c91169a903
379	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2a4dc51ec771e71d36d55b996f45e25bd9a48650eeeba23c22e995e5ce3f824fb55d82cb1dd82987c597ee2efb979299501179d41656c812e910e878a5fc0b5f	\\x7abd6ff56bddb4b9175ceb11d4f8b5adae96fb265b5226342e7a2e0efdd418fe801041ad1ab767c2356d48116aa8f350af501ca610591215bc7bcbbeeb2f1007
390	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd8cae03f7ab143a98955620646edcba23ce065d8d3b8283dbb732327d329c2ddcbefdf68b87753f20b9113a3a6fb7a51896f2ed3cdff7cd904c2e849d0ef8770	\\x8c207b39fc799a074606b68bf34c3d55f1857bf393dc25f6e4bce37e7dac19d65d02f7e036f77e8b5d34302ed7f81a254eb8c3232c8edd31dea0835ca7ce5505
45	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x486fb6b8910274e39bec59d6eb22337baaf7138a937044ff5b7b56fd4f15a443a658b1c0828c2c7e8171c74a6772a9de51268bb841ed1d20c13e35331da8eff8	\\xfd0494b13edc18311221bde230b0f5879867ac25e9d89199c7b342455897db56fc816cf26cfb66aa8ae308cbeec4b0882a6fc2a2515c47ddcc79e93528a0ab0d
61	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xb9b8c0974ee9a3006d6f965beb21c1385e81aafb80e0bbbf6548a99e6244eb68832fbdce4b4757a4f8fd8b778458fe9fc69ea37f41f6b42ef1eb8f2cef697bea	\\x9549ef8bcac5cc91ecbb9b7d3c6f7ec81256c8766f7e8d9f124018f58122cf9aa5a338f259dcc42e6e3551f992e97abe991ce8de69b11957617c265b23420107
69	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2cf0217982d954822d4214a0470596b8d30a81867f8ae8877e2b9f234431587f9c0069b54b9d25f25871194ccb83868bc4d6a2042f8a7776c09afb4e37c6f4f5	\\x92aaf174765018564d49c9e0c445a6f530b6b7fc26d109a14fec2a3e18a638a0e050a922229edc288fbd58757b4e66ef9a16c188229e40acd0ab5dbc145edb0f
73	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7e44fe9b9e7a66e30be699f06a9e32dc7c2e04d378668ecd6208574ae7a2ce961f82bb4ef302354343202c0d602febc84e5a55c1cb955ab52af569e92f476002	\\xf0c16e6e93bee5a78d3a9611af0d3a75d0689c9dd814c7d695145810b71970e398a60619c0c7b29b1ca972d76486b73f6cfa08292fac1c531b81fcd7393bf504
83	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfa1590e4c7641384736a68a939a29c5fd95caf816b731d5ddf2b2a4462f4a9adeddff8d885f7a134b1c169759d5f601203681acb67083df51c82452aa3f5f72a	\\xb36021b33e3207d58cf675ab616d30330fcae02e622a1675b7fc1877960e7105a1c902e977490c06df6e682fcc95842f653213854a50a04b3f543b82d355890f
88	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x18f05d3644c1a0e50b1d93af9d7352963cdf371a32d016e308356e27fa2298ee1a96c57a757a78a237e979e3f9a9b913876ce8f4f06e8c6a89e1cf34bc657e42	\\x0b18eba41fba26ef541b72be7c9de2d799610bf2c7ffa8c6ac0ce345f0ec5d6249445b8cd50db571ed467c591f4bef2e4f1617b89b86965048712e1cb353320f
96	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xd9a57ccd374315a09f732c5991d13ddcbed09c9a78c7a336dfb0483bdcbd47130a865c8757313ded2d39c2a73a0fba6fb8c7fb16be0af400a781639615727efe	\\xdd62bb817ea2797bfb206dde88dee7519688dd0915c72fdba2d8cfd5f1619d5235b608660346b660b83e574b5dc81caa84f3ea72af0a92061150913a5bfe4b0f
112	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x4b1f3e6b8bff89a8973cabcc221e2f15d2b25c8170eaa19d36bec7efb8633700ab3207a53025f8c2239f3769d164b3d37d198e6e6e114d9cc0e88a5ddb391b10	\\xfa6a45264d396197047dc729cae207d460ddd561500492ebc6255856cdfe95dfc1308bb4163c6ba6bb21de9151dfef1ae1c735d999845e150947309762e1b90b
121	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x5a51c2264a274c28d13d04dd90ed7467aaeb41a9a46aee952772b3ab329e17fecf1e7ea8d7241a205de005bcb637b38a0917ad1c28c15877f2435de66f781ebb	\\x8454868f8756b83c416124fa71dd1f516362d1d27b36628732c25510250ab63d0f1aea78e18d7cb0c16c7d8d59a49b4bdeb329b4ca38b999c5b2c5f7228b2f0f
130	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xbce82b9b41a0347f9862e921d5b2c54da43b07417230a94f2034219c5a8bafab09c207fbd310516ef80c8c9b0be96962d4de82318ccedaa1147e022f941a21b6	\\x271efa76892670c125bb3cca3038f74c520d861d1ff7adde9ccd9a5abe69dee4d822bdf0d83a780487cc134c383610fba41965fa20cd1913001d4a170cf2f908
141	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x2c10e7e8e495f184ae92d138bdc8c70379678a88ed5368e4a21f5b6e964342bbbe44c535dc32f37810085ec6880ed418dce12994f87da36cfba7fc55915056bf	\\x18b1af621ab6d220c038952a366559d0ba5793e3a919fb19ce0156dea1b560518df462d183bc62cfe2922160ad52d80febd141d0e224d5acb01a0798ca66710d
183	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x78f2fbead8ffb2ab82dfcb03c7097f300c7974aa64ae6939c8667fce33a96fd3a2dc07959931d03bad1ae0518ec7cc376cadc3e1cbf6f6ac86999bb919f0500b	\\x83f3a68409ed7a6bd8ba2c7b89d030da95f262f85df9a81b96e2dfb09ea1fbe77eea583388c10aa6cc47770f04953674000c26f9f8a0435336a93bbadcd31a0d
208	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xfe76ed8bf12ba32397acbdcb11e8eb8b9f7a91ebc7a3d4942890418cfdddd894d91923ae3fcf1c5282aeaccea13fe62f4780daf1817471e80b58e77cc62781db	\\xf511c024400e20e8d6799715b336a7940cf46ef2b9c7f2db60ef33f1ef60006224bdfbebc99f47cb16b67d0429aa578264eef4d016ae2dda21f31587a176d806
240	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x387a70cbf43067ffa1b375743c63d7627cfa2872bd955d510ec7443da44b5b0f4c646a681ec1f706ef21c160637ff32142a33ff2d1b638817673613ae153afde	\\xd1d2fb28ef3b42a85175f72e6cf2d4db9353370ecab4220bbee42ad6082b403588416adf2d465f09e148e04f1f87dbd9a163048cd58c2491fc6ffae593069f09
263	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x7d79d372a2e5b1c8f9676573dea30e6ba6a1256d2d0c45bbd8165b28b17770ffddf93a433ca483a29d026f662c2e969cd12773fcae720c3ba00f133de799842d	\\xc04a2cd2cf7177c6164b3332ce80122ff99950256c5bc375b3c7cc0fd19015bcc475e5acca85282b890d45d26b9e02b6fd2579e83bff1116fdf59a75ce7b6c0a
366	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x3ad3033845f76c4866c1cf7a7c50b1114d905171f2c755d2da8713c97c966e423eb6c54865e444a500af499581976a1a6a65e50d91bafeb16ae01889eb006a39	\\x68ade99621db6d7cf27051379e38c253447fac5592e2fb3baa7ce1ebf4ac6003d85a031860a4b62c8ad4704166e7fe0d70109d3c02cde53bef4f67b94617e10b
387	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\xa5d028e063fd5b66e7864e6c5fec59ea86dc985c241359241e76231f2e36f85133eae113dfaf5c8f7d5818cfa031e4dd0a1d0b3f037183eb036d8264e2b376db	\\x2c5d79d35ddce83b2989e8fac9a3f841483a0725488b84b1551da44f2aec390196d17c784c4b3baeb3acea5e56712085a4cfc8343cfd2dc29d23650d1447bb04
415	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	\\x462a35919d017dbedeff72df74e5883153aacb29de41fe3d1c7eb37c756cbc80c79e9b3582c3bce0cb27bd04001b4974d25836661be2f1385c3a19884522ed38	\\x4735dd1705b945efac51bc1718fc8be3bbb391c3cba5f1b20fa2e26dd2570fa881e4bfce7939abe52770908e6aa0372265d71ff61c996415cc6ccec8a9428b0c
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
\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	1609929260000000	1617186860000000	1619606060000000	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	\\x34c42d5626c2fb07e2ad177de0aa8577892b9307172970fe2f4da3b8647ea85094707aae8565e8a51d08de9d0320f9b144408f5718afff215a0de9e3f9c94e07
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	http://localhost:8081/
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
1	\\x7f31339f5239252ab5a603632572cdb90d634da2ccffeb6e0ee4da3bf545cb4b	TESTKUDOS Auditor	http://localhost:8083/	t	1609929266000000
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
1	pbkdf2_sha256$216000$3SxTJFOwpkyp$sHd8mhXbwf2VBD0vyFTO2aazCu8oIcgLV7uxk/o2zf8=	\N	f	Bank				f	t	2021-01-06 11:34:20.591138+01
3	pbkdf2_sha256$216000$FbKAWDE81PxX$WXt/S7DltTs+luE0Wfxv/DOyffU++M/ByskY/j5zCe8=	\N	f	Tor				f	t	2021-01-06 11:34:20.782697+01
4	pbkdf2_sha256$216000$zXehhn8Jmi2F$skZwBRZ//qPp5h5z8SeqyMGLYhyaErmt5/+dANnsMis=	\N	f	GNUnet				f	t	2021-01-06 11:34:20.863907+01
5	pbkdf2_sha256$216000$XwLfKKMGkrOa$4mL60RJrG0S0K5QQdwJOI0ajCC5hG6opJ/b0zVSNT/E=	\N	f	Taler				f	t	2021-01-06 11:34:20.946263+01
6	pbkdf2_sha256$216000$Af59i4Rzl8C9$esLf8fawvgVfhjQ6tIQHrWwPyUTxMke1+Dm7iGvqE0Q=	\N	f	FSF				f	t	2021-01-06 11:34:21.027848+01
7	pbkdf2_sha256$216000$QGCglRr1n26w$zJsccBiuM/+IP9GEZRZFXPfDEeDBGgiC9pKy0jU44g8=	\N	f	Tutorial				f	t	2021-01-06 11:34:21.109653+01
8	pbkdf2_sha256$216000$f02BaxQ636ib$FkZxFyAmS3ijbaReO2lROqx3EvAut/sqPvusB6wxyRk=	\N	f	Survey				f	t	2021-01-06 11:34:21.192729+01
9	pbkdf2_sha256$216000$t3VR2Pxss4YY$q+eCMqPEQXx0knLsSpO/d5Tu9rELkS2Jwp8/vbOPIe8=	\N	f	42				f	t	2021-01-06 11:34:21.640956+01
10	pbkdf2_sha256$216000$UGGgmDJpohGA$QGZPG0CJy1FhOm7rbqUN9ew1YCdwuvaJbQbJJXGpXHc=	\N	f	43				f	t	2021-01-06 11:34:22.107437+01
2	pbkdf2_sha256$216000$iIvctSSf9N2P$dHGF/FYRdZmPw/uOEUvDfMKbCFbuhS6sUbvdmTkPHLk=	\N	f	Exchange				f	t	2021-01-06 11:34:20.697264+01
11	pbkdf2_sha256$216000$GnZBvDhywImc$k2tTnwnRNE/WPsPE4QOs7YRx0Ur0hnV/lwmuA+S970s=	\N	f	testuser-zuZ1gmDT				f	t	2021-01-06 11:34:27.456877+01
12	pbkdf2_sha256$216000$8gZHT4JZIY5j$xS1OH4ax92CXiwPlupS6MeRWouaSB2E70Z2El1l9DWY=	\N	f	testuser-jTni7cbF				f	t	2021-01-06 11:34:46.055188+01
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

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x0204528843f51c8b15df2aea11e8f876900a2fab26f4550d544a29bf4d09af8636dec8fe8ea07c837e060ef6de344859ba0c07dd4c74cfbe951645f595686cef	\\x00800003d747486681401abe1c00f91df643efc168514d9effce97b350d6dca888e999f7b7b010a55f266a59d1646101f46a042f25d5263055aaf5fbc4a5b301e6949a1729cbc976333dd56d26e36cb589c49809e392a7af1c81ea402386ea2f13ae930b8ea37da9254e3c3998964560e258905c0de12a22e27097d3ac5f8ff907bf38bf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdb90523ac0ad84ff2f50d96aaaf04dbaf567b4fefcb4f971119acfeb6a47cf2d426919e4692e226e5e6af6c47ce6fc3b5177cf05f8592d273679c022541e1609	1635318260000000	1635923060000000	1698995060000000	1793603060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	1
\\x03b410367d03c4303e6b14db90bedfe10cd7c4cd2b3a0f92420a27ce64694a9567975d43970a3ab0a86becc08ce2307a5a24608cba6ea35a139f1f23c3b86f0b	\\x00800003a790dab06922e15fb45a12133471c82788d368351cbcabbad39d2c52bb0566e42e7dcbe887ca250de336b08bb1921c59d55f10d91caca7a0e4ced8a6cda850176416c31fcabcb4d5ed235eca760ff616f8912e54ccca0ea7b209c245ad0ee24068ae5bcda465b7118f90f0b8c62033d2486751e1417cf60199dc3e05633fba67010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe2a04be3f2d0d867accea226b10ec87faa9616fac52a071f05d8d3cd46a40ffbc292d9efc42fce25e301821946acc54a0874ae1ad252c6f0acc5f6837d7b6507	1627459760000000	1628064560000000	1691136560000000	1785744560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x0ee0122135ba7c17b7cfa19cceb750642ee770bcc006bfb56563db91f1748279f52c7b02fc7065ea344871af9b97d422e2a084d9c124140ecb7e1a36f453efbb	\\x00800003bb74500ecbec7bdb559b6b630d7209566905fbb782323f7d96a9b933565e529c084d40076b4bd935f991e0d3fc1f988e1230a68953b3b6a031a654051ff066528af2f14eca3e4e9aaee1af92007c62dd7f7ee5b10fb4a8c1c3c11a39043a70d3a44fd3403e7c07ece5002ea8de9efa4daedd837183b7a13cf5ef44e78e15729f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x357c3943c9107316a221d98d7c5570b57dd132b986131a901a691a55d0c0c55ac04334227b8eafb14ba3be55bfd1d2c4941169ce304e937b08dc82fce878c209	1635922760000000	1636527560000000	1699599560000000	1794207560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x10586a4d391169d690928ad14077081642eb6356db10674be2e2fe74f91f85b2496241a4407f32bcd2d931262227045959c1d8302a6174989626d24284b4fa59	\\x00800003b1752bf2cc2b486ff145c5c18bea57cad37a9c4bbd23678ff2607e11636d092c4b7f35bb2ba7cf98afe6ac8eb50b04a8cda3281de437cd49dc5e12c20d76852c3bb285abed98e350d4108a087e2680ee7de25d7a98682aa0a7e9369537356479191e3e6c878324f165e8dcd2abc7820513b0f22bfa18ef0cf65d1b55b18a0231010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2444603167bf74d15ac0f1f92ea205721275f37a41de2883bea2f92f9ab874ed9e90daabb0a1992bdbc0a5ac7f6422ca5a56df47c29bbc77d0971e81740b5c07	1629273260000000	1629878060000000	1692950060000000	1787558060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x10dc784a0ffdb65d20f325906d5cb99523ba7516b95713e98388947fdcd3e810ec53e1ac5424435076fb1ebf61ab336a837b3576c4acaa01fbb8f8a4197c5119	\\x00800003a91c4b04e0705543500980de14ac76a48f2ab8dca97b564bdb83d43f5a17f57f57c8908f31c462ab96dd1d93557c7ce533c83396a1a0dab8ce4afa57ca2f6cb956888ed7181f659d5a5af82b676621b9fe7250318f0a1bbee4daa24f231f489c0fd0ebfcc1d3afa0e5b2adbb67de575909b890bbde5ca7a757ab53e095976275010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbd8e96bc36b784ba36fd5e1a1ba1bff7ea5a744b72b8568193d1693f31f9ed9bf9f976ac0dc6f556f42794a81e4e4453dfbbd520b79084718e189e3bba8b1b02	1618996760000000	1619601560000000	1682673560000000	1777281560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x17ccdd3cb85bbc409ec090416adc224b6c4ea4454dcd2b75d4a618bc757975714abb424e113efa1f729a9b87cb3409f5aba4f3450b2e8bb58909af5dd0611e36	\\x00800003cbbddb0d8eb890991c9100164efc7d7a90479f271f52b418b1af839c66ed7178bcf0ba480bbeaec2d3e166a3a7638e6c5748407d98622a57132e333541fca55f4c50d023d94be69db145a5f525c077b6d8b1ef12237ab0fdaa8d2233bc507aecca35c54cc069845175496b91946f3ffcbd4ac822478bae6363e468ef59605373010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd71f6f78f26c4b355efc1c099c2199c54db5f243b71e7ddd0f672560b33b75c39b64cd8f969852a43dacffc211b47fbd35b13945eeff90bf2bfda076fccb5506	1611138260000000	1611743060000000	1674815060000000	1769423060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	6
\\x18642c08949d5b06aac8416c4ef4e6b02c9b8eb0d66f96ee0dc052eff43fb7572a040ae8711f6b95e0e27619ffe4fec85d1c639159e7b1b6d20b74c32af7477d	\\x00800003dd35a7dfa91b780b39f354308d7532a9b3413ec47becae419614de2054ed5bccbe7a48c48df27bdff2b59efbfb18adff2cf8d37f87e9a0303bf0af5c6586bcf6e6219cda35d41182ab76379dc7b044b05c1fa0f8f7b5aa2e435a72c221dabd6b449461c9034a7eed96ab40adb0a80c3d11cd5fab418b91b9cc974194a2a2d6fb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfd3d7a9241c096fc4c0d88a7d9fa84e6a94fe611ad3aaa4606e3c6b31891e90fb3a5f998f2623fe84f12fd1db5c87cba05f8b7d453563098dc4d45aaf018e305	1628668760000000	1629273560000000	1692345560000000	1786953560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	7
\\x1824979bfb4e4e777c8b0c831bcf1762e9f0caefdf9f8af1c171b97a99b4250dd2a7c568a539ce88ae212d7cc9e777cd8b8331715faeccaf16f1cd52528422c8	\\x00800003d15ed637adca59de6ab110538c2defdfaebcf8e1871d2c514c6925422827c8517dd4ef15ca1c7c66af793784621497f79a9724338c568c661a232717bb7ae37c9f4525a7b6187f063fbea0cb1ae5b93fef74cb809b15d6017e0229d8471056c8fbba9f825662e8742b52ee4952042d2dc83051b09be6213dd3fb0e3228a3a0ff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2be13971631fbf31d75cfb6867ea4f8e72d25c442263936d905989f05cf27120c361b441d1592ff64b78cf951b95785a0e6b88229e4b0e13f3bfaf0a9d101502	1621414760000000	1622019560000000	1685091560000000	1779699560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	8
\\x18f05d3644c1a0e50b1d93af9d7352963cdf371a32d016e308356e27fa2298ee1a96c57a757a78a237e979e3f9a9b913876ce8f4f06e8c6a89e1cf34bc657e42	\\x00800003f3a62bd746c3764ab57c8ed8711f3f9cedce85d66aac7121111eaddd19bf066b24cf3269395c4f38bc7de07ab20c0951397c725c7f69f3e6ce7d8fc880eef8bc325859f487698100cb2304b49f5b8aaf2c829fef38e1f758f268de63291bbe25af1c6c885f02d6754f0c49a78fb1b0fe6d02547ba07269e23dd6b1038707a621010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8078235b06ce4948a3eecfa6c00c6a1084cfc43af7861b2924ac41c1ab8953d8f4b5e779243344a788b3c9b9a407d5a6833a65e7ce0bb3d3ecfcf88f0c52030a	1618392260000000	1618997060000000	1682069060000000	1776677060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	9
\\x1b70d5c717dd9b7684184a84c450198b000cdb3e5ea09bcb6efac264437d1e2d575e8ef04d46d4898530c011a1179a1cbbac484fa33dfd28170bf574ccb69219	\\x00800003c3867aba2f30d727768ff62ca570b424dc16d6de047a52764fb131225478b1922174ed50016b08b69556aa3d35d7887dda9614e707bc7607ce01ec3deb70947f9bacd8904e4b7099e008012d7f1db8111499769773757440c13faeea2e7bf377e364af3024631b20013502b4a9ed8bb29ab6a0fc766dc1bdfd842930f0f70937010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfb8bfafc4460072dfd53a5513894ee881e10cc18130c87973e192130145f41526d8efe60fe225869a5fd24022c1e6e96d18d39661e25651fc94ae35dcf297408	1640154260000000	1640759060000000	1703831060000000	1798439060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	10
\\x1ed86f17adcd757d8f4fbe84dcbb6f64a3ec9c78921a0874d683e547cdba9c6027fce601ddd7538ad62061429ed0c881afb5a464966cb87ca81d37f93adea3a2	\\x00800003dcffe33cbbf0e18dd6e15d3ff80bd1b194076c339f6bda2ae17db465dc5272a33b03b8d74d857353337f0ab16733709a98de428ea52c4c9ff7e71d224c25035ebf934811965a5e3d3fc9c4acce8f9fe973fae8816952cae2d9df53674ff4f89414c21a297a59cb2df365e55e071b6a24fdd5573753bb0f3e0fd27a311ba87961010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2ee5b9232af39660352a5b43db5116fcae3d5b3de7b990173a374b9fa938dc9da0aaa9b8c13023764b970798ff41f3b803b5183010e576bc0bdb38094035a50a	1628668760000000	1629273560000000	1692345560000000	1786953560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	11
\\x21a89c35acee47802dac3b900435238451f18bcbc757b78092c1d8b98733afbcb4faa680461241a31feeb2ba889166e1a305b98311bf6912c18e36c0edc2fd9b	\\x00800003c1bacaeadd8b21e9f554a1f7ad8b056a338d95cedf2e21ab5c2c51101d7ef855157541270a806721b02cd9cc1cdb8e1e98fafcbf2752221f1893106a4dc4b0c1ba1440b5579811746da1cb78e24247b44f81b07b7bb3a90fab8e3bff43692114db735c844cd624736a192e8584ccbe96b7c1019da6fd00f32f3a87dab4178687010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4c177f2071b89bc8ae73ada0136654096f624b3e87020a5e6b0171d1b4f81b8885b88df7c031fa4f1ecdec5034763cc187d3cbf5a7919f37164c6dc77155d00e	1614765260000000	1615370060000000	1678442060000000	1773050060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x217c566f4262da12eb92933de248a61196131b8e15a3a142de733fccfb7d231c5867a2fce419ff2561d296e14c806ac7f66f1f2bbc68c2fcaaf61b28cd4a128d	\\x00800003c6e60bd4a2850ea75b172fe791aed415b4f6a52ef1797cb23345e987dac0cdee4d3fb6e4a9471e3b1f3b9a8f9000a3721015ac663a359e39b5e3b4151b8708bb261fd142109196e2b6ae113acddbce47eec2ba2b9e3f49c069b54136f729e781e042aeb01545f7ae065023c00f9f86ea4c741f3ec140f5b7de608a9407c079fb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x397dfd3519f73b3789a1f76cf171aeb2c709833c50bb11b3b067d20664d0884535b6f39f8c6947d0e288be798bf8f083629176d83e54e5f9a07d48a9671a4a08	1621414760000000	1622019560000000	1685091560000000	1779699560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	13
\\x23bc9de6c85f43ada8e7b07e73bced7eccf2cdc11c441d127a4485233b4fc64f28dd75f9c40c0510bc3ff3d153beb27a758005d51362d718f5bff4fc7ce32fb8	\\x00800003c4d5dc8185bfe3ae4638ee3850ba49b25b22a112384e23f1e221bb3b3c4ca5775f2faafd46c9ba8659b9f73eb8707ec780847d8a21ed0a36c696742703ad95e2dde7172ed937411c28b2935fe7a7f25a233156d5c0538fccb5ca4793699e5f7fa87018478751b4c2a79997c211156add8de91b100378af74d4d2390a535d9421010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x40c2f9236fc1b2f4ef085fdd73a98ab426b292519bb68fb4253415f30ae067a91cf47d1b2318b1bb64114239a44913aacdc5614d991dbfb91237ed7684af0408	1630482260000000	1631087060000000	1694159060000000	1788767060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	14
\\x2524de57b2ecf9e0f53cbf0762df54c8febd3c25b50504162b8275a045d6f1359df34591f6ac5722587d8d1dff36e7ad5336239ab4e8dcc8755f9aeae05b2c19	\\x00800003c2f66264efe24f6281858978cc0bd3b539457553a6982f49740e4c356ea118c9bb5be7058c64c73c1c617a42e00f7731e31f3bf2e7b66acf40187461495306da939b17adc8f86611fc7220340849428028ece2127112de8e6ffbc20f5be588684599d4c667616c791a051f3e37d9015e2077fab16a40423b2be48e051d57d3d3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x39bc9522407dc6237499f1f9bdae954be608ed6ad57d526ee2fe0962770a8af70dbe48e5d13b45feba15dde79becc62af69e7a941b0ed6d488e9cd49b027b10a	1627459760000000	1628064560000000	1691136560000000	1785744560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	15
\\x28d88bdfdcc86b12d9e48dd9d1edbece418f6f160951bb78067a6b835aa44684b42ad4dbcb53d907a60aa85111f33c33671dfaa9cbf5c1048c096c03febbe9e7	\\x00800003add5b8c8e66e44399700e1582dab18f5228f2ace93e729bc96cf72704f8e1832a06acbcf6a4224ec5fc6ca6249a37c83dfc46639f6272f8fe2f5316cd7ab818c3c096690c4a9856d3d6b988fb397f5f321fc1317e821061cc2006c602e89e98ef1c267b2bb92a475ddcb32245e9d1feb0e12189b362d5b2cceb9626280f5dd9f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x133a4de1e02a07c4c7c85e6fdcdd8e3f556055bba142bb65b962e447f9561c8cd0a9b0139705a1f92c6aa3f35925d4fad1077e939147b654466381f762875f06	1623228260000000	1623833060000000	1686905060000000	1781513060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	16
\\x2ae8eabc63284d6324114e69d0a21fadefea4e86a9f44176a985782b060be8456a503b485ded355477a234ec17da86277808438a11ed6bb6eb43f76352c8f743	\\x00800003c756320d3e20152b3f2077d6b3d65e566d2942ceec130178765d424a7c6f8703b84ae09df89d6c6c040d0b0f645c80ddac31f9fa30669e837e9da31edf8e83327ca84a9037a25a2ba0b2c25eb47ac3a8e418dfe4e592174c4aa5fa8fc400e2df6598d0aa274007656edd1a33865961a7c1f7590050a785a73fd269cfe676a16b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9f597468222b95470c49be562173788dd86a550d80841ce1b89dc2ca00bf3cd050fc2e0d94f2b2fe2e77ab3ae9e17f6e336c3044f37c781c302375302c284c04	1622019260000000	1622624060000000	1685696060000000	1780304060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	17
\\x2ad41844938291dc7b25e62a0800e6c364e4968c4b0d22dac7e0ffb4aff4746726b3cd3bc4619fb7b86f61c4bc8ec48723d3b8816bcd3cd96eabb97c6e721746	\\x00800003e4ae4fb1cea46e6021108eddc3cc62af366f1c5d55d86c654e4bc675167d4872fce453e4b7cd43df43f291665e0b60226a993cd0af89226d17dfc274236fe397cad29c8f0bd9208045fb3d1a1e1c876d588c9313a95ce33560ebee2b3089737a10bfbe4624548056de7cbe72a76d5a39479541c0bfb16926bcfbd8a680a9b9fd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6eed9a301642fd2db13442edebee1c987a3786e340158fc62475739d5eb2a384f484b1f2716bd38013814de8b6cdcec054363f3100d7c5d5fc687e6f62af9d01	1620205760000000	1620810560000000	1683882560000000	1778490560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	18
\\x2cf0217982d954822d4214a0470596b8d30a81867f8ae8877e2b9f234431587f9c0069b54b9d25f25871194ccb83868bc4d6a2042f8a7776c09afb4e37c6f4f5	\\x00800003d9952986da5dbdbaf037cf4c5ff2b37bb5ce03c12a1db097e3a7d9382bfa0dbad121ac33f9867bbcac3f17e7ef286ad6a91fc0d0d17efafa721e593278cdb744501251e0f29f11cb74c99a652f82f2da9890e94969876753b5ff41878732254bd8cae470988f5e13755591202a1b6ade86d9e1b77f9064029e212fc6a63eaa33010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd6578dbfb3f54a06555ec4089353adcb06427eaccc90850f22deac5555390f44042b6a204bb4d19ad70da855f48bb420df6b5a60056d2cf7d644ec135fc6b50e	1615974260000000	1616579060000000	1679651060000000	1774259060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x2c10e7e8e495f184ae92d138bdc8c70379678a88ed5368e4a21f5b6e964342bbbe44c535dc32f37810085ec6880ed418dce12994f87da36cfba7fc55915056bf	\\x00800003bc271e43b29d89bd66c38db1f23ca21307386f78debe0b62862cb422597828253ca9cded29a7c969e8e84472ca47617de7e383485a7378dbb2fe161ffa77b2af147ea61914572bafb043917c2a051739de56210dfbd47d315bc6c5d58b6476cc0fe50f621e96fac1742da85f91aed5b28976ce4f807ff9592cf309db31a31d3f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbceaa5a830a18dba380eb4438c1e2d6ca05498bda8b13ac02a231455aacf5c358d2b20e90d1960022a6cff8015481c7c886479ae1b0495be5081a56cc9bcdb0c	1622019260000000	1622624060000000	1685696060000000	1780304060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x306458bd64c7daafa5ecce6d6f11c7108a72e935c261edb3c9a918db07f1cc3f208c85c9d16cfc1892ac922d1ed6885a364e1021f4bed407d650302ff5aef1c0	\\x00800003dc887fe6eb41ec8c793e5e3dfb95a14cfcd1a537d597e4d8b9dd815ad21cb7c3486dff4813502232896c6991c1185cf11421595a2816bb79ad47aaba87456216959446c72f03647766ab9313bb43eca6fdf063c8f2f441b21cd561ef94caf86065716dbd2ec6d4abc29f40ef17645de46b3a76f3d30338458df57c17d7558b0d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfa10a22f528c6b4c7d10c8bf8075213ca0c5bece8f7736a0c2dfe608313825d016f746e393cb7801b45089c14c53195e7ebe2c414d15029b9fc2bd274b30650a	1613556260000000	1614161060000000	1677233060000000	1771841060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	21
\\x32644d2666c3b817483257d2cf1d121be6470af501f67954759655e57cc811018f37446d18921fefbc1e3db5ea3ae69f8ba767fb31ceb5bd6468c81765840eb7	\\x00800003e069fd16ea7e4fb1dfdafb4292eecc2750d3299a10ed4bd94f7dc76dc27e8ab703e8701dff68b07bdb953aad28b70ea63fbd7defd66a9effd6f7bb17d8d6eab5482550d1b66db19002a3f8e5fb1f1d8d744643be4856410cc2f0516e99884d82d8293c41156bd9f9dc311421e355f6c781599cc96cca34eb4c7dbb5a61e85b9b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc9b986f88552532448b33be610849eb3bcfebf308954602d30c2a9015e4c3d3c3209f3be77986bed9ffb5831f81da31b57f781e7e1a1d996d956d985dc48c701	1618392260000000	1618997060000000	1682069060000000	1776677060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x37a8de29f5606dfd7097896f6efa7bbaf59a9d862250af33f644fb46b6de4d8c37b471ff4ca67dbc44e2408c597d729e3d9b96d9e5ef1809e105f83a85c76a94	\\x00800003b0d860476029ca7f50831a1dd11f5cf8afbfa1f07fd36f714c266d1826c5ea869246f9161081653059de7bc3803b7976d939a4f27faf1270fe61876b8e21c2572e496c96d72a76cdc993b0683b8ba5476aadb42cf6f7676bb2eaa5285c6caea0a5d9a0e0f519a22fd3ef4fd82bcd43f11cbe076feb44bca28758084071566f19010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbaaa86d453975cf034bc04772549a66b2cf0b336ec39aab09cfb841d5dffac13f62dbe679ad24bef2ea6036b8d21729c3de723ef17357d5824e6876d39e5cb0b	1615369760000000	1615974560000000	1679046560000000	1773654560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	23
\\x3a7494f244afbb2123729b3455deea4abe1d71d147a2d4d95d49674054225b5318d9e62c0e41a6a3893d94aaaf67ee9964d2101a87708e85c5329b6079201375	\\x00800003e1079f73ce335334efb2449e295d7e2f50381ce101c32819318ea2615f9aaedb5aa0f8a9297d9672a1199e0b1f1e82e7850cb71273847b9e58f475ced42d159f16718e7706af7f1aed8015b8f3453e1fa33ee681ce5fe45bd294a276f959aae6fbce3105a584a8ed5c410340db7d7c86907bcb0cfc199ec004b3f3a44e6dc741010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9634ded46c2581ebcbc93753410937fcea91d38e08a49074301a9adb79277986a2d2124a33d0affd5b2586cd851ffed4fe3779de56d12dfaf0da25133d312f09	1625041760000000	1625646560000000	1688718560000000	1783326560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	24
\\x3a0830deea3f30d594859c4dbf09f12fa23cb539c18ea9189fbc3f727961418d0534b7ead98567dd7f91f97d2eb8521ebfac330f7811d1bf2c5e6531277e30e1	\\x00800003a2c95e496a395ed63f30d87e37fd779e4cf8eaa7e9b567f633d505dfd0a08293e01dd63abcc97b060a61ea421a5f6468a11fb25f005385b16045b3af808c7d8ce4a261b819d269efed426a316ea7b9d77e3d83f7cb6197b890b8890f9f8a2be98f2b4cd798276a06acc6e0a4d1bbafda5bbde9ac1bf6195b16f7917b9a6aafbf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc48bcc8301f23cc32b1ef16699f387d1bd272e8354450924cc8f6136a32cd2989d21e7bde46613a62396c76e087df7620b7f860278d836ca611a63e8ba632e05	1639549760000000	1640154560000000	1703226560000000	1797834560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	25
\\x3a00f5a3e5160bff20343800bf2c4fe04cf9a221fa2eeaee0604b5add5015b5666fd09f1ec47e0b9ad70149ccd690319f32ef84916f73406c32814d8679df351	\\x00800003a02922d2f49ae2cc667254669078a7dece272fd3951f904573f8dd2aacd912d60309173e90999725277a8a8f534fc6000c6d28b3e04f3d99f28bd6c3b4db5bacec169834ad79289c5709399a71b7782c8da4a12e4a9344fcf342b16347e6e709a24b9e4e0eafe257233ac6df44df8c00e5edc9d3bbbab7d8290fc571ff6e85c9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf7d4e00e9eb49d59ee9e888069d9e6f89230f08b78add31a009c5adc5355cc31daebda9c8493bf921df2204afd83545317a255bf4f62b6800b585ab74200a00d	1617787760000000	1618392560000000	1681464560000000	1776072560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	26
\\x4054481dbdc2db792e99b7bf6fe757f853f12f40d5d9113cbb17766513b28241067ba0df730f9af81da4e11a27beae242a6a6704a019a7ca95c50ee94d0191fb	\\x00800003c96f7a8d555f9b275d987b5bf58f580c992c2fcc5a732de24cc6e868eb0becb187ca48d20fbb4596c5df893164ce0f608870670f722a9850e786a6307c01a53571ecb5afbc1eaa58095e5748ad3a3499fe80418132faa5e84cfc215a16dfe9b4e89f5d959dd8f653fc55e07092defa3c2d7ac63f9aae75e7d412dc8f2ff34767010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xec126b4e85ec7e7ec0570a7f1e1eb2e24ecf9498f225ebbf46f43f8e396fdad6dc33f7c47b3cbbe3dea25b80b7748cbc816526c70b59721f0bb54019e7226e01	1628064260000000	1628669060000000	1691741060000000	1786349060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	27
\\x431057179428df2a16bf071d3fdbdbd884628514ca4ad6b3e8a74120491be91cb43a775e4ee61a3b8415fc4d4469d7bb914ba70aa5a8dfc884e36b92682eeb3a	\\x00800003cf846df7f93672cf96e634f79dddf4aac543a160d0b22ef6b60988c5caf1e1243405a73dbe3b412209d7fec1d0ee924f0d0497dda2b98d873d34e9575e40536232e91db1ad8710c72a7bfb6a5eb89186db75597e045cc24888f9a27e0b2ba48ab37498613516ee6a142f0e9b452ee5063992f56a6f53f612061dc905c31e727f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x68912f8aaa03ab797bf4a3755872f8b0ba0261e407b3580b970830a61808bd12a4435cf9bf60d9b40b2b2495e4c8ae64e5e19b0cd751229c2c14de1d8c8e7a08	1633504760000000	1634109560000000	1697181560000000	1791789560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	28
\\x44e46455483d859cf7a3c13540126212a31b2e6560efa739b6feead078dc37b19d68bfc9861c241135868270db6709114182b470de8d63b28827192a847afec7	\\x00800003be4187f2547af3a5320d66464b085dd744f7e154aa99b4dc447ac359c4d6a2bbb2c540cfc459f4c6dc86ca2c9e4deff559bbf5913f78359c776708b374ba44515a868faa0715e38cd9aa26a8a394cd346f63a19e60d360041816901acaacf13a70cb42d179dd302ec7e52ae63dc7de8250719fc13b7dadb89bd18cb582c2c0df010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xaf84c2cf2cd12d8446f6a2063e623b6a65a7e47bf1b111c6b055ff2f3e23ad9c288d4459e47b03b4c927136e97358395d2aaed78494eba33673c6c34a855f702	1614160760000000	1614765560000000	1677837560000000	1772445560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x473067a19268c966aa39525bbbbf754f7d862cd4975128a8764cfdd52b94631b350fc9100fb6680e99ec35112253ac1d8d625d2b2f05fa8aff2f1154b0578ae6	\\x00800003b00184d3cc19cbcd2108cf3de44bebede9dc71c04fc4c8f0c53859bf412e86bdaa315ea89f8c19c38e14453e1eefa3a0c30e663ddaa036d6daff8ce7ccdf254cb30f70c696c77f915822e91e7dd79246b825ac42e280f6cd483b4edefb053b8f8b76017dd53f9cf6e996851d7bad4bce0e04570bccd71d9f92ac234afd6468f1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x235bb7e5a2613e5142fc94858f9459dd37b195d0d16fd577b13b99baeffb8513a62b7a4e3f1e3213d4ee9ac607db70ab7adc04097f07cf72aa7f4e0a604f8205	1618392260000000	1618997060000000	1682069060000000	1776677060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	30
\\x4960602766c0781ea2e194d3797727aff52fbbc356271b7a53d9d2e44fcc211a9854aae04af20b3ae16c1102fe1e76d7ba173bfa3d998e7b7a2c1511e8272991	\\x00800003bd86603fb7efb9f932d137ab9c03af9a7be40da710f3f20610ee9ad6ef6cb9cec93cd87d685d80b6a2ce1bc4119c0c01ec40929136463ae6315bb45b9fb9392650873df481806642304d04f6fa81d03a2a9d8533c2f7ea637688eaad7d75ae8a098fce535d4ef6f57e71c68c00cb5c6ae22d06da18cd2da83d3152c544d1496b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8502860bf87ba3830583ed632a652824114bdd7d1b43aa9f2529674d03d04c76af39da60113a3e6bfd09b8f7c62fc3eacf7cd2b5709d7c12330b6be7e700c200	1626855260000000	1627460060000000	1690532060000000	1785140060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	31
\\x4db82031d820baccc8996eada08158d64b4ebb9fae2a882e9c05ab1245b8d2117e9720af53057883eef5cc6f805eae41f53b55b3c4d54d9a91832753a90b85b7	\\x00800003e22863c88055c7ea9e5610c010f8887ed21c97791e17a44a4ac84628a2b6c86deea698c68c517bc906610f23a5274527b94a4c88c93e0f39fada775bd640fd88c7c9f5bb73ab0af58a18bafd6033623f6549a9b7633de9ded9d9623f6433c548c765cff5dbfee8f92ca527b1fda1dac6d8b8bf75b44b006eacb08b39da11b7d9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb0d9e58502b3c5e8a9999ae18f561168b46461bec19e400922e905bf0695d5ea9ef6981cc3d337a05ee67f0c967360e50cbab1310f25bc91cee870e824647d0c	1626855260000000	1627460060000000	1690532060000000	1785140060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	32
\\x4da441e619163ea7edba267c4053c690231dbe0e5c5977754b48279c6fdd80f45dd2e947bb3460c3f8250960ae641d62b3ef2cad38c9d1dea2f0be9c21a9ba20	\\x00800003ad2e0c17a88bad5000b2c6399e4d2a431b45a588c90e2a086eb55f362bbb7fad31cff7480d26f091b0ffa32e61f66e002d77be05b21132b9eb9a7f5d0a80c9aa5dd7acb626ad9c651d7c53620cc57d6b6975d962cadfd6b59b548426b48e2decab683940535414cbcc5a443e57bb175407cdd066d57a72863bd7eaf7a95f64f5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7812513591f835cf92ac5eeffec8e3682ae105a07c3fdfd524a25cc0e53dd7274de076ee4edbbf8ae5ce876a7c896c0a2b94570748e9fbb60e7dfd20bbe4df01	1622623760000000	1623228560000000	1686300560000000	1780908560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	33
\\x5020deb0ad1707b6dc14cc4336380ac8c1d81288c75b64a68f779501867781c845bc0188a92cf5eea6adced9c008489df799c402066dcb95e91cb32151209aab	\\x00800003bbf6101b45732359e71d8f58be9ff720a0978518b471934279f2748694a29ca8f066e723b320f66fff4397e62e670693ca3216953fd4044b5933f8664bbe85ce36edc73de1c89995564af7c236ba51090892813ebdc775168a2758b4f21a3df2100b888cf7913fcc254eb75af208989ff94564a90def76ba1bc75ca0992f33dd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa2e94910ec6e4b52c14be2828ba0abef1b0233744ce82587c7f83c5f457d49e6da7dbab3f41bd7a5e709117e3e56e6b7a677d75b39e475d9be01f323c295a101	1635922760000000	1636527560000000	1699599560000000	1794207560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x53d09dfa25fdaefce2a9e42f4dfca6d5253a28a5d5049e3d8f4f418176770c05b9ff8056becf22d888f0446335531aeb9747174f2c12b4b533afdfbb25c050b2	\\x00800003adb8543f483215f23a719432b80a96f739d4a63d23c5b4c6c2548559052991881b9807ee8bd1c6dfd0669127f6afe85ba45b081738bc8d20308b51bd0d1ef7e13e43351dc914cac717c253e72af8e73ea2bbb7fe4b36eeb46fdb328b3bace7c950a229f3fd2bdf4f13f22b0079e954c71c31531947d6292d4737182082ef361f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4c5347e84c6cec8e827baffe9bdda8de2b3692239c21107b252426d43f6ef0fcff28c09a47e44ab56d22bec2b74670ab843a1d0b81635092c6cee0519bd0e805	1617787760000000	1618392560000000	1681464560000000	1776072560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	35
\\x58e40cc8330e2b1465105264cd31a65b6f13f67091e619767a33970901d966c34a5e3ad1a382ccaa5e7d1d2c004c76aae9b05a645667296512e38b0e30f4b27f	\\x00800003e6c53fdba19b67b64ce7c07a8ae53e51f026a64d1a1f9a04cbb632ae66aad1f642a411b6284ede18d0550a49ad4b87660e342bb14d5c37d5755e6008f1ae73365eabb731169c9f67343ebc75aa14b44e3aff99cb1577b2c6ee022c77f2d5aa37002481870e841c2150ca0369e77e2eb650f26ab93d5ebc983ec4a03920ebed21010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x57a7631cfde83803ce8b1da5955ad8890711f2549534f1b98dcea04741112720c48b99406dbf21d0880f3d58702e8793a7a98d45fe90d8ab58546522ae51e507	1638340760000000	1638945560000000	1702017560000000	1796625560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x5840e1b0f285c2417c693b0cfe0655df3c6067a47929f444af81e5de981a270c4b19e25216292028a47939e59bf29a3f58bf25f0bf37389821a1f1a648951532	\\x00800003cd2f34f7f8b2d0417060f5851e618db047c79b607ca045023f446cd2c27335dbeacdfa9eb01f0b69169274d7d6cab36110bd85cb9f0d69648e60c31530000a2177a995c33567d942af52db06244dbf2dc355f7ab254e63e5c2bd9f613eb5dc8b55fc6ce257ffc64f7c2a1d042ce22edf78eef053563189e5250a021c819deac1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb32c4053d64cd3d252f4153aa16d8284f7a644ca2344ad8bbb851781356707d4c28a6a9c68e1b3a8f27b22bc1ec7c5f18342ae8609baf83e71cf2a4570054b06	1634713760000000	1635318560000000	1698390560000000	1792998560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	37
\\x59f46046a4cd538884089274bae0c0b19d4f240bf86d851dcf2943b9582db7455e86caa97b2bbb839314bcb08fccdd1342c15c087b41a1d189349113f0022018	\\x00800003cdcc15b6e7c3cb9d43fb096a4262ebf81def769c2df028362ee1afffb5525d391f91ce0a2bcedb4df58c3551336f8708440ad1bf3c0f9a0327a46d00ce1ebcccfefa59ac868b7236629db9d391b012d0e99eb3a92a1783064a57ecfe772fe692557eaea01d5c4e8edbf248d19b88c05a6871bc5dc05dd18884df32c298040fd3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb72aa36ed8a2791d2fe99a96f4915e4b0c04471f4f206da330546459e7b1495964219884f6dea181b3315f7378e6babcf902ca03f4d6995b119f5b025380530f	1628064260000000	1628669060000000	1691741060000000	1786349060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	38
\\x5bcc4090d00aea4e58cf2975a81829c5471a0293ddada877b868fa7e10bcb55bdcc46c34022d466b9d6d8322c9f7160af08c1d427b7d7c1f89a3f719df8de8c3	\\x00800003bb145b7c3dfd2ea0d5159286ca8e2f90af5e44ec28a57d49bc8111948dac66e93457a51e31118a6deb798009f9d798809afe60799b8b4862ad87a94e362ac65d16790b668f158f57efdc3cc180d3841d99f31469fbb40b7fcfd26d656d0a4bfce5c7ac9155637c84e72fb511e0ee4e14b65dd4aeeb62f3035cca1158a93ca4a7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x457c9df4b1b0f092a9e0245fbfae903d43f83dd757fac60f703d1fc985ddb7f28b7ce344946a9ee9d5e703439e7c17ec9155fff23db918912eec751e6edf9a05	1617787760000000	1618392560000000	1681464560000000	1776072560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	39
\\x5bec64da0df0f734401808975feda6baed91706502ee4df062395cbfbef56db8c1952e1528a04a89b23cc04f32566ee56146814c81d8084ab3e02325574af467	\\x00800003cca64e20f2127a54b5166a95aefe59b739ccacf3ae2b6acacb4f24cef698987c8ba3bca7e527a2a4234b04cdc1388afea342309114baafcf2a15fd88b2686494ad60ff0cab14bd04e20f9de6ee6603820ba526dd2098a32c41d58606d3eb0d24dcaa66dcb549a35e4dc2206350a527ab0ad19c1acbcd260b53fc151161eb770f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4c555a85a3547d3e7cba5cf7085eab2b047df6358b41037c76552d36ee528536d038bc8d482e9e58e43dffafc73fe9f5910ea590f2f789a196a04a6cf2d0480b	1616578760000000	1617183560000000	1680255560000000	1774863560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	40
\\x5e68ddfcc491e1a1bc969b855433e58dc60e96a766b38811ffe6eba12bedc371be3bbd76a27becb00f58d82f3f51eb48d06a21d3265d952e41fd3940ac8b0234	\\x00800003c2a173784d956e67ea906864f6f0a9178670bc549903402827588db679b1db0296531b07d5ac46417a9556ac101dc2665b03b29588cecdccd78c5467a8c03d9079b0928e0ad60b66b67f9b52bbd2aae58be5cde57fbdec01cef4b25585c0b03cd1f942ee5b143cb00cb076804c2c6bc80791ac3f82725a43b397eec814e129e5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdd5d5bc9c7c6b360eeac16a46ac785e9c26a5efd64f808f0b7a4981e12d3aef9267a9a6dc36aba528222ad6c6fd08c546af3b32b685adf23767b04e0627ccd00	1623832760000000	1624437560000000	1687509560000000	1782117560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	41
\\x5e80dde5a5129a43b58b6e04f7939d7fe052d3720ed32e0a5f8267c7fa8b124cfe495103433c11abf130d75a01963d89f87f87fdf3fcc82ea95e93f1c02fb0e5	\\x00800003d9c4264308db2c2c7a2a32e046f0c497efd3c8150bcc31cb64ba5c9f2b7954005b250940805ed5250902abd5976e756f1c9403d6a5b67180594802d34673d8f83fcbe0e776670cac025510ee603c971422ba275bc32f9e8d0afa03fbc0533c271b30428859fefd5bf237dcbf9f7d97793589a9aceb468c8e240b0723179d1c47010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x222d3fdc7b8917008707db448376ecae6494a12178a5ec34575e9d7e2996e12ca343fd972a642e48d443b7d6ad2eef54f2ab2bf1c93d9842368c69348eba220f	1621414760000000	1622019560000000	1685091560000000	1779699560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x5fe02e12f33cd2ea4ca008ba7abdc8d6b77289654439bddda1394c89891e99f4ac003731e5b86fbc1f376742453e87713ff59b2d7b727e0728435a806379b207	\\x00800003b6fe21f2cad60fae9e66d759d0804adf93c0adb4dbe55564b6ff8f021f64a5640ecd124a97a4be5f55752f1423a8e8d586c26b2e7b97e6f2963bf072892ce978eabd72d24a2f3b986e60817758c287572d1116db60741610c156a826bda71358fe9d3329b6b2fdd0e225eb76b583b2ba5ba3745d07a9ad0408f3e62bf055a395010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5305272ade38447a8b71e298ec9ba833ae33813568356ab17e6359077ee0024c93abb76468cbeeaa3ea6e17de06b9ae1197268406ef20ed0250c0862b578d304	1635318260000000	1635923060000000	1698995060000000	1793603060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	43
\\x5ffc5a14bed3e8da317c1c5ad9d8d7481fcbe0cca1fe5657501f1484b9b40639c91ebbdf5729c559fa4db2e675e6266f4b703fd92cc8c312776ef4b4832733fe	\\x00800003b700dea3131791abcbe453274916b6317e52094224d10a9316a1e696d6fe567cd83970fa5129b8017756a63bec934f84d587bddce4720399733cbe120e78ebab47634b7f0999c9184c1b5660e24237e4528f059cbe523f845173440249188c899428cb50d0197c32ab9529ce5db1cd92c4916647876c2502270166429d9ce7ad010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc87b7670533f0fcd75591171dea2cf40a058c661d62fd3eb12bb1c13966c27348d2c1180d59e1e02b0d66376ab0deef13ca4670350dc5ca312ed75cb2728610f	1626250760000000	1626855560000000	1689927560000000	1784535560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	44
\\x62b00efa832f53db7ce3d22d1374dcb5f6621ab67a67cdde78f51a0a4e2247f97443e13a33a08ff27783147898b6356f6794a130ea29791701dbae63385eca99	\\x00800003c63da4a9f594a141520c54d8c6c3d82d787d82a2dc8dccfc92809ca32e1438eaeea59dc2f72ad1145a83bf177d09b244498979379e20f1fd64b8d214fd0c204c830fb6c91d770b0ceffe42e8d7f2288d51a66c8167bd60ea64318bddc0d77a176c40af2b431b1b0f02665d91af09639f801d64813e91a8094a04ca1e84d9a173010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4c31708782378b24b26979718423fc5d06af14adcb670100fb4f336bde80b2a6b694c9534a091fcf81bac0348f0487b6f6b1bc45096553c6adc5da779b277c0d	1615369760000000	1615974560000000	1679046560000000	1773654560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	45
\\x6434d6a390ee45b2cf67ab29fa71d54a0b1e9bf8b81c61beaf21e47ff1a58a74d67e02b84c5bdba6153d0e633cd30f84c6051cf5b84aeac05a13085e22094c1c	\\x00800003d598eddb218fe27fc3ebf5d8f1591f596332ec74824673ae43dcccfedb031d5011647e3ccf638a1612c3f6ec337236b8a1794d2155e440d2c831e3fde589751e879735b57648fa74487aa3ef0f68c702d5b6158a693219ee8745bf0dc2139d7082cb30aef108dafd72a0ac1e0e9af340f8d54e7d911b22ae8f8223561a94eef3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7957c07a15ef6c2f3998d3b7d0ff106e888542e91eb980cc7a32ebcd55e86b951ff932eafa377974bd7bac6f4efa1cd2d91689571d396f6126595b124d29ff06	1630482260000000	1631087060000000	1694159060000000	1788767060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	46
\\x6500fa2cb0a04f41ca8f9b0e1c426266d9e224f31d75d1336c2fb7bb370e5f65408c0e25560872eb20ae044afb0cc30ca654a66b4e927109f451f55319f9ff58	\\x00800003a884de2cb20933e9715ab2d474daa3acd360a98d0420ca8c18ae6ef0fe358df4c7b33d1bb51ad31fe54a497fdc509572e1b121feedb50f64543ca90e5e280ef9f09f2e4566c3999bbd32cf1f693bb5e7701e331cf764ec6609ec56f15490e743811d84a1566c0ace6e760fde85c9ad3440b60afcaaf3fd453d6dd0e139c12265010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa78af75c223ed7e4f627726e81fb324a57fb9ae632408067648a1226444651acc0d6b0320923616d5bb920a96651425b8ee48ccd3bf4c1d752922da59cc41b0e	1617787760000000	1618392560000000	1681464560000000	1776072560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	47
\\x659c6e96567f91b8685764e157e78ceab97965a26f74620f62a11f646d62605cf049865a46836b306fdf66302a22842e5a441a73e0895b85c5697972cd242160	\\x008000039b03aa6fc446d7a46bf7e9a59d44f8da1ade643218a60d30b91849375310be9dcc3b6df254609d59a39f17eec6c3191051a295dd79083618fc367f6d56143157052b9c56fbe4b26882875abdc062acedbc583fe23832128038b25f74ee3b460c7376ef7008ee29f34deab217b1a33c8e67e7aedb4b66a17c5491f8b52619c061010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa31785c2ab19a2c6765e30d53e51361e2e63cbe26d75a3152f983bc2816d672c45d4320172d7e96bfa4e777d3c0a07cc83e0ecdb2dbc72cc1f5d66235bd5130d	1617183260000000	1617788060000000	1680860060000000	1775468060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x688c9107e8b0193e6be6d7d29eba4bbdc3788ad5887e04bb24aae621f4c6586979d07601c8f1b87b044066319faeb1544e8fe077a63af8a37f856b2d182fafb7	\\x00800003bc752a5e3cbdb22e09d20925cf6e71c3215b060938e554d3d11d0efe7a0a4354133c493a5ad3b05734219b573ad1318977584b9ced339895428b45202f45157f92804e489087af2e600b7f8a097626d1311f47f90a00d61004a742e35ccfdf0d08d65c98f5c94937bade1911d01b5d0cae950757c084372e81e9a547fb79f20b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb7d0f54a7a5e6b437462af04b396d3b5c860babadc362ebdbd2a159cc927193cf78558238a05724a1ac733767e2129fb3b3566bd8f10c7aaf7ac83a52bf18608	1632295760000000	1632900560000000	1695972560000000	1790580560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	49
\\x69f4af5dba4cce19a49c7fb09dfb0e3b1bcccd5003c0049e00c5b790ca282ad315a727be5bd6c94f07b1d77f9e4cab84235b6d8a2d5509fa3a34c0f4819c933d	\\x00800003d05a2f16204c47da3b46e71d33a4bdfeb6d88d24e54f28b4372d0b29bc881fff12735292638529d91f72d64b22205697aa9bdf11c4fdf65a5a163b93d9fe2a2f1c1a9b47808a34abd6c4aaa77a531cc20c93e4df9cb3e2d3c7967bb4a7b7fd868825028d068d6117ac1f0da1423af61113b3e0b953d51075b21b160de3df87ef010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3f34539baf659fbb8bc239f02363d35cc5b6b340dc666b9a12c458294ed12ea1bfa7163854c7f93519707fcdf48c5f3d8aac2cf2755459d4ed436d635bc3910f	1631691260000000	1632296060000000	1695368060000000	1789976060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	50
\\x6a60f0b1e73eb1050c22b6008e00cc9114b5a0539c277f7a47e5765d8d877e44cb91be34d31b9d930b02963f0c08faf18ab71b7f9665b47e0fcbe793096382e1	\\x00800003d8fb9fb172ac6b9efece964b3ad91c9491c73bd61140b0c2e7dacde033ee78936146530fb87766830fd761dd74cd2fbf98387f8f991ef2cf01dfe2b4179fd38591ec32a1e52db06ee080b95f32b1f8cf4b7ab7e537f7092a2dc3b2683ea65265015c48bfe3b69bce86041d744a01d4895fd97e7ec015ac053f4017081725166d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x095d9301944d1e1af97c822bd8b3ba82d42023798bd49c4560930c9c7b4ba4041e8657e15990dd8e92b437df026f75abcbe681df3b4d10e118f26f7068e2010e	1614160760000000	1614765560000000	1677837560000000	1772445560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	51
\\x6e88b6e1cf77887cfb1bca4dd129580f45d6d7e000b7b6d28c881512865376f5f6e80576b19b841db1c89610f2e9384cdb728c97d6a56bf919e723a315f2fe01	\\x00800003bcb6333b9c6611d2c69a17663fa138a57fa62d215446e11bea0d204fc0d0eae26aa887a4cddd49cd665be52f71422da87a108b8be2f196c26b47119354fd90d9e45a81a31f2e43344960f75d89d0704173b4d4adf5e81fadf972d96636d76469957344048bcb57bb42fd60207e159a42510c637b03fcb1ba5ec47cd394401e31010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6b77a611df8a6b972182e1e162585ac813fcba2016fde070c8ec7f02d5ae333e7b7f54a90109fa977fc621ee9f5441f273b00058ee88c7a944fb608bcc0a6d00	1624437260000000	1625042060000000	1688114060000000	1782722060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	52
\\x74f08a9fbd323be379f001ca0a20cfbb2cda070b4b8930fb7f7b3ae3e54d2f38493e3c659f79266d94f3a15d7a5a6e03ba8aaf09435862b00418c6659a098f89	\\x00800003d527f2a26eeb1e320afe704b7c46f95274f3afcf67bb4d50f067452e5c54ec81158a992bb1fc0c363dba6c60aa6acc821b5745b960c3dc4c4cfed75b6097a41a39ed2c0c1fa9e3bc8af96189e044e7cb7433276feec1aba60521d9dcbec7adaee7beb4fb62eddac8e8bfda2642cf7feb8d7efaf6d2375a211ff363907b6c2ea9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x30fb34da00ba846f330c16c0c7465907fe01cb2dc849b3fbf645a76ec928d5a88e2cf42062f5d52147701b23e59b0f813553c139052d1689fd8da9958033070d	1622019260000000	1622624060000000	1685696060000000	1780304060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	53
\\x767458269ad137ac03727880d09d5bb84054a385266c3bef4dc833dbb16672f82b65b7fc1608d4a4e7dd50f29851eebc0ecf5bd119c3afa67a37c6cbf913d325	\\x00800003c817f5d2d444694d3c07e75ccef1da514c0544eb5529da88e14019ff30bd2c9e7a79c96ac372cac5459271a77dfbcaeec8bb4a7e2d76e6bc9b55ccec8d398bbe1c5299d494cdb37982b9ab0a666f5ef9c138fa1d33ebf978dddc24b3568cf88d08f000941790093a8d4becd6441417bc428b82908cb395b664d3c4381587d1bd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x38b1f43bb2a8bc36e58872e35c6978e4843b1f8bfe20020bb65c77ee052e0615e9073965a5447a0bb551d422b5ddfadf9a9e902f55e930083dd90486d9685f07	1610533760000000	1611138560000000	1674210560000000	1768818560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	54
\\x79c8e26446d953b9c24a15463e2ac0f4d913c55c24bc42d684022f7864ee2306e5738bf2da2fd7ac0b6593c35050c908b716e7c66c3a86bcdeed28ba21c2e4d6	\\x00800003de96173632e30f5ff656d02554f618f6cd51b5605feb87a24f29104149fc8c755b0dd545f77e601f366d35ac887b849821a96526b5ce16ec71fd5f4d8eb71b5cebefe6b6adb6a362fda09e21df2e89d4bc2475d3e05995efe416beb4f9cebb38888e94a8b8f5934c493ced348a1e1f52a4f37bcb052094f351800bb79d67362b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb3490475195fffa3d69acfe41823575ae836562c26350c9e59fcebcefd0a1dc926a273103407e5f2175eb02661c0fd3d64033b304bd0d93fed6d4190eda42804	1625041760000000	1625646560000000	1688718560000000	1783326560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x7c0ca7be28b32059e5d1963e7dfb9bb84de88d9691585072547027a303896b86aeb3c42950b88e6897fa27caff8d2b10af50237bd91fcc6be6b68995819ed66f	\\x00800003d2f1e0907f26bee3e24aab71466e4a66ee6703981a4dff5c990c988ced7efa08f6aa247407b019e43759fc0c62b9b5bb7d033848175fd9657fd938c4e5a677752fe0e36cd491510ed771128bfa9fa3e30f11a128a6006fbbb1a08706cf1c77508bcbb409eaedce57bce61c0a7e1d446f2e25cf3711459c19f7e0dbbcbfb65f01010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5e2d83836ff7e40d259bc331bf206c857578b21add0950f512bc56d6c60694244598029b89d2e2b1d7074a20743e5e9eb32278cd9259c3eaad916194c1bc430f	1636527260000000	1637132060000000	1700204060000000	1794812060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	56
\\x7d140a26b1495810beed3beb48c568bac90411dd778001f9d71f9948f0d003e65083b18d716752f5fc2dc687dc3621c458f14137389153482260c790ba4d9737	\\x00800003cc58bbfe42ec88456d2db08cc1859c405d82fd67938ab1e58c7256d2522592db07947dce21773eeb596d4dbb74fb32fe64d7f8e0b0fa6112d73ff665b8012d00f331c305836e24f40d0d47ab78084ba0f72fc23a6a0a1fb03e2365752591a353c7cf9be9f7627fd72cc862df18ec9bd3d880078335a862d0bca9afc066be76c3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x539dc4cdaf6812ac22be829c765fe1a33046324ad03e3c5b6efb75667937643a7d55a9ad5405b3071e8b743a416808de62162d98115d840b6823a0780f893108	1628668760000000	1629273560000000	1692345560000000	1786953560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	57
\\x7e74c1aa9c7557724abc7d29c208a3db73a72964870d48f2225003690a4c0d8f0425488e18fefbc9ea031722b1ab4cb94287c06d032dd0cfe73969c72f4bc16d	\\x00800003a03c2c3e0cf9d8c7cb1c6c26fc75280674309e705c08ec8e6d779c8ec3884afed9a8d3c0075a95a4e6d94163badef38390a7ab026ee88150b14a85da7a5abf16363f4beaa44579c5ee42d01de841149b9e5bb2d05c6b581f15a8412eb90dc8c3786ee62aca6d2bb37dd86beee53c8710537c6461a5a644c2821e6948cbc1b523010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x550bf297a75b92df5d0ed35f3230afd8bce253da86ad964aaa4c643f503e61ddf3ba7f4b5fe2754836c743329104f130721d81124bcc19dfb5c4c547e9b76b09	1639549760000000	1640154560000000	1703226560000000	1797834560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x7e44fe9b9e7a66e30be699f06a9e32dc7c2e04d378668ecd6208574ae7a2ce961f82bb4ef302354343202c0d602febc84e5a55c1cb955ab52af569e92f476002	\\x00800003ae3c74cc7545091d1cea7f02b26d366bc7888128470f7d45e3d8796d536560adb8a224510be5decc83b09b9eb51a40e5b27ac40bdb1371191f4917ba630180d48496673c72cf7cdd68087af65dda6c3b35c1375633177147876af04299fb8329a4a676be2fdd8e8aa7a2f981fe18bfd5a9f5142e3faa836a13ddb1d4f3ec9a2d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2c1a02167bef55cfe536973993e4854d0d2d5c07d2a36c20380f1c6eed6532dbaa02b41c1c0afd74cacd6b4a74c1029c0e09e589b410cf344c98ff08cd37c70d	1617183260000000	1617788060000000	1680860060000000	1775468060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	59
\\x7e501e8508142deeb0edbe1ef63f770b333596538da65d63255f890076033c7c49ef9b78b8e2b84b538d7edcfbc6c01e160b38e41ee8fdcc96dec75ba83dfbb1	\\x00800003de13a142bd42ba4d27894871b16faabb73b98df96d7eab749b3e9bf97a54edfe145b5ec15725c18e57d1be8b44395e0192e5c0942adcdc65aad61906938926e5df49d6e5772249a578061673cf6fdb52ebf7bbc29271aede17df43c26233a24efa7952133130fdec3c6f88ad74c6bf3a0fed30a6813f3191839767663fad8b85010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf9a3655e83217c95ce29b981296afed8529e7f424c36e2ecd4760c4bf67867db8f4106b9797b6fd73ebd2c45534100b72875740a45fac4972fdbb6dd4c31c90c	1609929260000000	1610534060000000	1673606060000000	1768214060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	60
\\x7e8ca63dab8779102823b89eaba30a60d8d7ca46dab6841a370dda4ad0b5aeb6d0b48b519fa6ff17a3de45f9321f939da198385831c51d17ef975ed77b81068f	\\x00800003e06a5b357a2d8502e7f516f16572adb38abf6e7a7c6b136f3aa5e3fe60dcb184f01c55b7794300e3abb9ada10dfa569f38731e2cc412416c4055f15275018e8a8f25bf8669156cd6a826535a707bfe15dba7a7696a684ddbda70cf4e98c9039160e98fa734c0d04856b68f8bd82a7675ff7805cff7457aaee920b1e159970e09010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x458463e1f36ec60cf16f1f486493b2212e27c0576f02e40d0a5f7c8b5bf87b9ddc18703daf82134f6ad4c090309cbaa94914564ecf220c912771e8aff719d908	1637131760000000	1637736560000000	1700808560000000	1795416560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	61
\\x83701e89de0fbd2223434cfd4d0a33424ccf71d5e8b25b63dd44a6f5155019414b500462bd69f332a489bc84d6c899f227a43d94bca204521d142e5ede7529e2	\\x00800003941633ff57fadc7cd1ae37da6a533631cb26f77f57c4e824507ee61894a77bde112ba4439f315d228e0af123d7fcdd9e005b0a6b44e210c66e7f454551200fd89abfa800be3adc54e1934bcb7526fe592d6fd2c5f7cd8f86b9c61d7481ebc6b902f050ecd5ec5b7624ae3390da7793fa185afa893d9245c39a95fd0b0774645b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc6ab0d0ecb5b9f09a5235552f0ef7c089dc4359626bbcf3a27036ce3aa79eb2b900e7c93c814bcb5f1d3dc448026be6d709b852a57eb8fa21fff121c34e6b001	1639549760000000	1640154560000000	1703226560000000	1797834560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	62
\\x84249f20b9e28c63948c108c05d41df8aafeaa87e2f7cba589f83b06fd15724ce8afbab2ae92a92cc7234cbc9d508c4c003c2aea0f3772d193a9bb2469998c9e	\\x00800003bdaaeea38213935ece5bbd00a8748d06f5623fcac6349ad1af485a309a09c35e909b8273d8b0f5d3a9138d96ef33114b2d2a9eaeb23c4e2e60fc688f79d779736755ead9cf4c27edc0daea481f842ba4e50c443e492271fd2326ae789ed3c1ae50ae141622fa5f9615a0a9029a533f25f25ac167d8aa79fa44929a653f6c94e1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0e99883ac1832fd5302b6dbad6602c1e2d347853b637578c00a987ea56efec898261638f48c9604c9a08e0b622dc27d212f17775dbdc064c981c1d73a3a54b07	1637131760000000	1637736560000000	1700808560000000	1795416560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x85fc8f313d0ad08d72749c99b5f596159d8903ad1ae46a15fd8b7a8ac2c8cf1db43159e1600059d2c2ddfb98d838f081175635dcb5a1696eaf35492a321cb2e9	\\x008000039f9c81e1713a260e072445b8af87d880e7567e837a4074bd1d1073bb925c842bbaa839fb22041db8318ac311026c8029c36b06972a65b7c11d22010b45573013354cf8c7955e008ad903632d51e036dc76d1c630677f6a654b58be31cda9ad124f98f03183c852cb411156e82b864c7bcd1bb5c348756244e78d7ad3981c3bf3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfc7bdff34fbbe5114d36e8248cb89935859027bf95b52ced5bf463b5669c2e244f7e90e3d7bca84d5f538d7734c037f360983a7cff2e172393fdbe3ae64c3f0c	1640758760000000	1641363560000000	1704435560000000	1799043560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	64
\\x88d096d779c4238763de35531b960b9f4298c954d9057bed1b575fb4c84c73456caace623e413803eeab7a5367b4b8d825273b8e892d72ec481819aea4257b73	\\x00800003bf2af8f950b3074b43d4198118df6d36d4bb0a0d4d9a202e87671a988d38a270d268f37a2ef2077725c986c99a7c3398a1b89cef64cbcb81c921cbf79f1b74a464fb1fcdbba34754d0c04f08a2ab332b2b886bcffc22524c398e7cbe51e5936ae11a9ade07fd65d42d53ad44f274bdf8fc9bf9a3095f3ae5a0d4a814c76fb10f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xabbf58940718ee49a60931b50876d9be48480915a915d2be8f467a1f592b4a453194ec9213790fb2d5a8204b3a01fa49688b6064ac80a7089b12c2576e471b09	1638945260000000	1639550060000000	1702622060000000	1797230060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	65
\\x8ddc612139087fa3cf71b55102bb5f2906ccc889e075575a010cb3da44b4b3f02657b851a8b8d54d55a248a58981b688f38c37f9c4a3c5aaf1d52809da956ff3	\\x00800003b4fef21d76d8ad11fc1a257cd5653ac6d5b6e1369fff044ac32de8679fc1b8716b3aad13ee10c2636f98289087e82dc9d7a25d7794493f55f2b4360241952f38f16d5cd384bcefe411bfcc0eceb85610bc3e2c4ed8053099f34b80c1fe3d17285be2995720fb16675ea0a38cc63316ad05411bbd1a3f6f56a52d2b0d5e2fbbf3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6fa62556a4d5b0381c315fa30325773e6a9eaf382a980e5813434cd6626fa7efa6586d023f1fb032ba051f0e19ae7b14cd738f867da6f3a361405b3ec6006b09	1627459760000000	1628064560000000	1691136560000000	1785744560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	66
\\x8d0c87b48adeca880fda8d3afebf3bbbbbd64f71f225dd92dba6e81eb24ba26fcace7a4dbeef99ce368ac9583358cdc3e461f1736b842e893fe956ce516372fc	\\x00800003f4b7c423923d879b24b8af64342ebd1fc6475a9f7d4abbf85e503ff579cc2523dbe427a0d48b350707457fbe448ac9a1aa9ab653a8f7c833578e726a9b48d85a8b40efea6175225d23d4b8a5ff71b664531f85909d1f6ed12fbfa0c17838d632cd33b8733ec5f5d69002eebcbfa040de49d96e8d130e7be4ab4289580cfa21f9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfeb268a51cf305c81f7a20116c12291a2200a1a9a16486f4450c424fa83feb9284eb08dc857b1d0fc378538333dd1c019a188204453719479ff090a063eed301	1610533760000000	1611138560000000	1674210560000000	1768818560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	67
\\x8fc0867ed56f7a3142a02d41a9f456b692957c43d736e0144ae678fa57f40b03b9bc8710593ca54473d54991e670bcb470d13caececf28d09f94050880d17099	\\x00800003e111079f3cfdc9eeb688b1861d9316ebe9bdfcf218c2d44ec36c2b8a0885d9f38945e2ef0e0615f987f294f729f155958d2f1f61d25c0894291f3ba7e51867cebf8aaf2e7685d0a1ee276b88715b5b8bfd885a1cc4c026410e7f599c6476094b7920aea443b632e4dbdef348f5d0be727f7d5935ceb9dc40213a50b5e7b32c1f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x371ae201c33735a938c2a2751d64085ec1e0d80beada13205f44c69d877da63ab48e8a27613c9b5129a547c4ead2dae28abfb12898e02ab94f864c1989f93304	1612347260000000	1612952060000000	1676024060000000	1770632060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\x93f0c55c3d6b00a0248ac16f54f0b63c4aea1a9488b134e7b688d2e3e0728118b2624090daee6814a2c4541ccbd876c90d1e1cc5f147e3cf2a9eb86dab7eb418	\\x00800003d0121e1929e25a23cd170d292ff113b43ba2156083b1959f679000f99cd957188e5bd9281a71f5bf3fa152275306db0228da1f01c0f63802e3841aab5c6f70ab6b7ff9579f81bcb037d54f3f76ff1bd747360543da625eb34733a400c822791b19a2f5acbb136d2adee76492100b0bf2d1a37c8a2057d975bd479e1cd3443223010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x74e04ba25819706ea9f71600fee67cadd2ba0bf583c194b6917323c223c4095a06d6ea36e73829151cbe7de0e711507ade430159859a2fb06c71e84a5fd7990f	1632900260000000	1633505060000000	1696577060000000	1791185060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	69
\\x96f4666b9e9a72ad4bc85f7c0107f2c7271a3d3d4b74d049f2c83a47a7b8befa6cbc65ca2f7fb16e1ae92d29eb13389dc7c42f1abe3143aea91bc2da27ac6c7b	\\x00800003d70b4766be9357a858ece08aee0df268e4e75b3e0b5edf4cb5e9e611bdbe37e983753f33d3e0d6633fa2b8862f3c09c6aabb366d48baa18ac375131bc319e7e2eb2695d9517b1ce63ae54d732db2a3ac013d8c7942dca9103a8cd792ab747974e4907f49ddee93f129ba923119cba92149b50ae133e98e80e9229a6280fc9bed010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x19ed80e89b76b11a4cadf1ff10f3e59390d20a62f90ca75fa264899f094d0455dd5bad4f1710b88a74050115dbab9b04fc9c19109520491c37d4d6a7ade0f305	1618996760000000	1619601560000000	1682673560000000	1777281560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	70
\\x97047c845ff01d82cff83cd776b648f6593470ca282a050e3ad1c4f1cb9a05cf3718a012bdb457ae048426c4c81936f98a1db9d88a2c22c4cbc595bb0502eccb	\\x00800003d2fbe7cc5cb50200daade97dcada0c3bbb9c40edb14a509111ef1c9d33df8e1daf9d0a2e4aae589488c810903428bfd57093c744cf3aebcb77f9a596e89a29416dd6c392fc6cbc3ca0b71b0133aafcc39720a372ba1c130efcdede8b5bd9a0a2a94dc3579e84903eb94c0db30219e521e31b887443623f4dac5dee0efd2ec0c9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9df481d29f8cf5da22f0d32940007a3ed591cdeb6d18688c399a8191384087b7beaf54d7cc14f020b426074e084d4fd4bb8e9428edf46e872c0435422800eb00	1615974260000000	1616579060000000	1679651060000000	1774259060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	71
\\x98185ee3318714462144532572648e5b6320fdfaf458395911064b154c837d2be548b0eb0f397ce8df982e4238d784e42bc7adeef28b8d9b0dd90d471c913807	\\x00800003f1786801c8d5281491c1431e71953cb219eb61cc594af3bcfee6f916a2ebd6d12c83f863a69c207bc1c15bb3885465fec55ed0b1c1d60dc03072e055816a1c0f8973ca6c75f71dca12903ca32c1a4402cbde48ae27777741d277ce6ac9234d649b6fdbfb61e677adebbc389fcff2b82b12b83b6580b473a3fa739d390a3a8009010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x54d2e86a362ce97ab1652fe6a822dc72901b66b93dfd608dccebb5e0778ceaa61b6fd1bf1e8ec5f93fd1ab2d2cd49338038c9a65da135ac99759702449e67908	1639549760000000	1640154560000000	1703226560000000	1797834560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	72
\\x9cf805688731d99953d1d42d38e0cbc84b4feb2ab750d8f467ed21ee2449f01d10382663d3feff4ff4b343146a1b5aa6c0330a88de0a7d678e9b331fa9a98bce	\\x00800003aa6c1f6116eb161890f920d74d1e94be216bc211c46fb7d72a9306a09543960479cb36ec710a8b0097d286d6dadaadc516f8ea4a8dede874f78c17f664cdb80bcf7645b28761d81360457ac1951bf9bd0042737e8a23d4ed23551a08fe77c41eeedc79b8e57b8379b14d96d4613451f90268216946d7be7d652006c73cfaeb1d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8000c5d4b5c84cfea73608647f5ec2fdbd78efdff8ee3aae893a60f105797dd57d1d070f7e60129a9ba2d5157a354fa0aa2ed963cefb87c4c5033fa17b0bc809	1635922760000000	1636527560000000	1699599560000000	1794207560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	73
\\x9f588334795fc8c4d31eb3b3e1f5e77d3282b200abedbf1b75375b9c1ac2b078bed2674fb16033b9a766ea09af135968d6377172d37026fecc5c56437fad567e	\\x00800003acccf3f105f0331a88a375844ad3a1478a6e1c199d46a88e5ae0238cccd939b90363fa7fd0906447c5191ad43001edbbe81653f13a58b90d9100ec9e3774a68e30518ad2eca18b35456b84b3b5ffe1930ee7eff4765a1bd58bcce8b55ee52f947504e9a3f77973f4140d43ccbee543ca9497a865ee57111739798d7853bb6877010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc25d1d7ff29ca2cb32e5bade46e9edf0924fb74940750ee463938af5159b38080edc42cbd95c319d53aa63bb75ca9e91414bd5ddcce081b88d4353df9e32b00f	1634713760000000	1635318560000000	1698390560000000	1792998560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	74
\\xa5d028e063fd5b66e7864e6c5fec59ea86dc985c241359241e76231f2e36f85133eae113dfaf5c8f7d5818cfa031e4dd0a1d0b3f037183eb036d8264e2b376db	\\x00800003a716a15b94a3d2564effe7270827312af4bfb549440c5d1c946f533e3879219f80b94b8876e41193d35eb86f4dcf53d9704e6462139967585a8aef44e061ac9de78fb50fc0d0acfcbaf9fe5c47325c5755984ccc5f3a7f5e83c2b099b61782d735cfe5d107a89990d06cb864facc5c11e85d8334a563f184f3b6e4c84031968f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe2cefcbe1903fe1c4456c905f549e347988aec863d89a9672d79b442efd295fe8f5f7859cb6cd38fb508f9471576afb8a90798d68070dc67ba0b60d23ec59400	1637736260000000	1638341060000000	1701413060000000	1796021060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	75
\\xa8a4c8f4157aee4785b7c8487334113e82995074f82e54177dd4b12dba7d93f424c2025e17be2162063d39e244b55225eb28087591b831d6ff1c397ac04a31f7	\\x00800003b389abaa5c725924fd850e2c2a1f9d7ca8cd37678984603ef355c36cd485030592dcf9f0bb4ec79e9183d788670f3cf55896c9151fb0473a369a220b2e8e8c333195776d28c66c8734b0ce8ac1337cb00d3b5c6f2add56aada8aacbd063714a1f56b053ad675cf736d0aaf9c5d60add8fedb644270e5065531995324528ff2bb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x664d1195cdc208346bb62d80d4cfc6c0bf9aeae7abd54b8b427963152b17416724f4187e349c1d2678621c1c0292d8960b9da24375b10bd47d510944ddbdd20e	1629877760000000	1630482560000000	1693554560000000	1788162560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	76
\\xaa60151953c061c81c854b1615e134f823c39437cb4bbc7952652b3cba39f7d6264508321f0f8f6e684427c6fd5b65bd771b45ef04b3a84cadcefc15500c039f	\\x00800003d0750e8eb7da3d53152b2a092b6688c3949d515664e0ace71e507d47044942b5d4391050050ddbb30807e20ddd7f0936e55bbf30855d3e87b383ed095d7830e216443905262544b45d064572f99ab4d228b5d4415fdc4eb24d9096c5608b49697c6bf8a01c43c4d9ff8bca37e915aaef11afeb05d81b37a1a1bd3ad5f4669187010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7a4a62fbe0216303ef7f80ea2ecdbe9df614f2b597650329f65ea4cf2ec9876d597c69e87ee617e031b069eecf05492e17c42ff70683e591c622578cce6fee04	1632900260000000	1633505060000000	1696577060000000	1791185060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	77
\\xaa30ea733ae263a2e71f28c8b491ce8430f9220e03aaef8d2316728df90f830e11bd5bd22cffc23e993abbf0e8b3eb705f7c6b47043be643222ded2f947aa2fa	\\x00800003cdd7f609cae988c850b1155cb8354adcf237e0a206e7e13f86cda1e2cce5accd2511f39a33e2ecca0cd87e918a1234896ae6f06745688bb360286dd07cd7a76a6e452bcab8be7c0edbefbb0f56a65d7a282dca188c44c4aa5eb53f73db7683b8c06532f77a97d95aec9a4b76800e17ee69b7d5d06d9796cffaa663159ca1d831010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9c187edf40dff3a2180160c0bdce326cf411bf17cf73d753848a66d21832a82d49c5f4471014701a513d9f9836e5b2fd6b4110f3b459e45be2700153e54e0809	1624437260000000	1625042060000000	1688114060000000	1782722060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	78
\\xad543297e42f9080c59cb9dfcafd8c20b7123553e0686df492dba2b94fc5068e518c7df263de3556a8500fd7fa98446ba52868563fbce86913b7162d1758ad82	\\x00800003b0448a9c9b575413f17480649c149ebb15706437ba319a6b4b93660073f80041b06ecd52130080c154402dbcda5252a9e93c61dee30e95da79e92d03c2c884ea4245ccbacf6218a502df4de2aa07fe3f57ae439e461fc9aeb26461558d667139d2b4192672f9b42495dc73ee3584cef756803ac38517d16a731417493e3096c3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8f5cd40007c56c08153c7598e738540c9417e5fbe032ef6bc536b04b89617c1a2dc4e0e2b3c60cb13442780e76581536c1243fba68188aed61f04dd1af7ad607	1637131760000000	1637736560000000	1700808560000000	1795416560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xaeb0293ad6d88576aeb50441f071c6048dc9eb836634d173340b3b9cf10be0d47902c0346a226aa4b92d00c90d667933da43213d0c82beb9ca5d09822afe3a2a	\\x00800003b9d4e9c202ce96da62cd1e24475b46caaece579a7c30ed60dfc6a8806be493bb73be61952874b412597b46461d71bd829466766dd1fb4d0f2f927aa9a1d1e60e6a587d6d9f6a4b15411acea6e05edcacfda487ac75661ff8fb60fec6f051469259eccb9f1ae81010e3b42d8905db3e0570b159fe2bfae31a07c6b40879401e4f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb79e614dabd5e19a2a610752bf53d5ffe1b1ac321dc3a896f6bb7dc4255f86ba90e570c639a0ee41d2ec8c2351716a69b51a9f148a9d63320fd062da42301907	1635922760000000	1636527560000000	1699599560000000	1794207560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	80
\\xaf1807296dbbd21b10477063253b11e23a0fb276871114681ddd6b9cfd68ee64036c64ab15ccb3e58e4167a22a26327ab084d05a12dc6163c7401cf63add0f1a	\\x00800003f5e8df5f951d8df73ed7ab5d60aaf0ff86d1cfb318d364f360650b83272a0c31d6391b6db06d3b2b8b9ac6d296c817652d72dfa1a4ac2ae267feee5008df067f3f4f528db1daa47e2a68f138d0f04805edae41514f34f297864fb33678a4a9417d1bf7932180f485972e13b41fe3e87d0a0baa264368e0e2e2a42c3d68f2db9d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xcedbb13897bfb7bcab487dc4950bf7d3aef422801d7984eafb9778c9a2ee4d4a71dfb6219868d9e23f084ec4a54ad94c6b4b9ccca15e62dcbd5a94dced862900	1622623760000000	1623228560000000	1686300560000000	1780908560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	81
\\xb7909c18519270b1cdc0f9e0c5eb28cdd064d2277b93778e595c5f9007eb607e0f46839568a6ed0d1d602f8fae9314b7a173507c655994bc907c37f221e713aa	\\x00800003e41ba8b4ee06766964f984fd4b012f7b6933e64ee700b7de23bcfe93de116ae17a6e096adf17aacdd090e6cf2d549f33f6ad222e56928bb6d71032c07b48a82bab07d0fe6477fe42c4f90df53a91420116bb97cd21de037919201de11729bc8748b9448cfe4693a893f70d21d2c0c54c5379bc63bedbae6db8d17cbf080b5023010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5ef19c0ef0adef1dab18ef1b73602b0935936ad18ed40ec40384ac6e5cf2cfeeb513310ddfc0474a2e5b4bea4e6608e15b1f7fb57a51f1bccaf20517b2624b00	1621414760000000	1622019560000000	1685091560000000	1779699560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	82
\\xb8a0aab52df4ae804cf94ac6be2b447205d1555bdffd0e6f2b876dfb4d4adf387810a1baac6080e71005e10e7a08718ce89bb6fcb7f878dc76a85a3808a48750	\\x00800003b679fd6df61c51eb5aadb79086b17511e8bd51793f0751bee49484eda62cd2f8cfdc3b9f21a900a76045d80087124476f0fb2d3a435ef930d540687c30a6a552df695721da35a25006422c87357e7edace08ef4e78275d05213328dbfbc7844649d8c6b0a42f7524cc156a11cd9adca27f51744615a148d4425cf11a0a00ddff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x251f3b0f3ef08df7ecb03f28f18dc83ffc99640894de21a331532bccc368bfd1ddd55df1f8d5a45da8ed7b6324b72ea6117c50ceb337d32b01603bbfc42ba603	1615974260000000	1616579060000000	1679651060000000	1774259060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xb8a4ee90401c54c130f041c430a4fbec201c25c809754e6b5e13040802a71da90dfceca209b7c4382ff93c69bcf46bb8924f53859be5bd3aa84d7571d36ac00e	\\x00800003b6ec2ff09414f1ec91d95bb430780be53b1ec95700c87cf4b5b320eecc6abd5d8ea8863b9ff2d181606f9d32b58ddec84558706b97cd18e69c7ae18ec7e8ea7887ddd028fed1209d3931e438ab6a88c278d250932fef6a96a5b5c416a3317a54f53e22abd51c91a5bbeab7434f2486b65819c64746541ef7a3ef8a31b47a2bb7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa7b20c795e4fe29601090644e47ee23187ffc602dad25bac526e6f91ccb22ebd695d9eba2ae948243b648e3392e4518222d4d42d9a71616a76cf269af4fde207	1612951760000000	1613556560000000	1676628560000000	1771236560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	84
\\xb9b8c0974ee9a3006d6f965beb21c1385e81aafb80e0bbbf6548a99e6244eb68832fbdce4b4757a4f8fd8b778458fe9fc69ea37f41f6b42ef1eb8f2cef697bea	\\x00800003ce43a09c14ee8c7a8000dc3407f4a5bee9ac1c121f3081e38cb9dcb3fecdeb3a4a7ea4e6e5952ae4b0232abafb5fbcf52c47a601d1b959fc982bbec9bba6efe72e60b4883f10e02a1f559efa73ed161fb767e3aae04864cec9ff9157e547330c641734adc988d36670c42d8b46a9209be772e051cc37b0da94f251f70080abbf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5d3b3da9eab779e77c31954814a9f7f3cdcd8935c2e1054b52a20d23807ec977bf6bf2d8cbf9f07ee256a9ade51ea33c1a8cc3edb67a0b3442008b2c5d8c250b	1615369760000000	1615974560000000	1679046560000000	1773654560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	85
\\xba081d746d2bfb973e52325ae287a9748aa3269085e2c95eb7d5832a9cfb76fe7eff01edd955c305c4513fee298e6c69e9639e3bfe2b1bb20c63e19b9dcebc3b	\\x008000039d75f0a0ae2000348a78a6fcfa2811ef4e6816e380c57094bf549463688270208162f897cec7b623382aed11d529c939bf9203a3fdba8a0d85bdd6f6e7f7ec648fc3ddd69ab1119cb8fc00f78460650facf71af1040626149e1df6c1505d9c4837243cccbe3bafd5b30f215104a6a01ba453c5224c01ce70d5a4e3af5ae7d4a3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe3ea041ab4aa0dcc21ce12a3c64cd0e80ba065cf22075ee87aa3efa874a88cef0f669884bb95f6482d2c33766001356375150b135f634df89c6eef236c60090f	1625646260000000	1626251060000000	1689323060000000	1783931060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	86
\\xbc40fda9dffdd6ded7342ba8f0cce726aa833c4b909ec48539ea027e983ae57720d7521b6dd69c003d319edfea3d92069f90febc0b6dbfe0d4af7470b8302535	\\x00800003d0520254f4f69c5e2be215720a51d506baa0e9498d437c7cf58b1d5102efbb6f041e01ab50839c01a105afe3528bc4a7097a018d79c3f74590519cfe1a70b6b57eb9af27ffa4bea847f364c792e1ce4247f97a796ea1062ae319149f0697ffff823c3dce2cec1afa24bdaadc4082cce555b3a6a545b6a3bba3bbef897fe74bfb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x978691aa002c326134751ebc56e28e5fda06d58ca3247e0a17545626c6d3c1847dae060245b809f1b7fe4d31b70d24996c5b8847902b30616c2b1bed4714d408	1625041760000000	1625646560000000	1688718560000000	1783326560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	87
\\xbce82b9b41a0347f9862e921d5b2c54da43b07417230a94f2034219c5a8bafab09c207fbd310516ef80c8c9b0be96962d4de82318ccedaa1147e022f941a21b6	\\x00800003bfd23ca9feb54582a05ea235233dcbb89d9e8a06d833112e27d87465ec497d91d65b7a261a86076269ae1db9241b283813626a23cf2cd5112fba4fc8f127ab96d877d25c58c207747358424a242fc7f9180038892fe8d2d4e4a581724e0f2a28995a72b9c1d52ac05f17ed3a5e00f87f7926b49974419330a2b4c42f48dc6ad1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x55b93c9cccfd758fbc213314e71eca00197ecf0a427afa612d6af8b1d9d47adf3112765cdd14fe138c9cfb108a925f16bc75bba23c1cf6d7246eb5ac4dde0209	1621414760000000	1622019560000000	1685091560000000	1779699560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xbdc8e2ac500dcd1c2ffb58d54ce8b3aa9a585b2577f5c80c6e07da659463b1a25b678c7380345639d15ed0f077bfcefd96a35833c87a45e10df9259f03b13961	\\x00800003e3d5b0c4a13477e4eb6e5061e4c0d3e0752e2783f341dff783917d0d186b3954b7e7623055f97da26a204396fe9886a98372fab1fd048291f1e7cd2b3e45890446cfa90ce97e15968b9b0c43dc458a8b199e4d044a60c44beb512b24cd7e28ce309125c8f31e84920dbce5a5f74b02fd45277e2f6c57e71fdf477a8ebd3e6667010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x628e5fb5155e596d1fa7d9534df23839357c35e1966dbe6278790852184b558ed7cd8f958f5ddf4c9144dacd18304be7db62a5cd72501142423d64e1625f4b0d	1641363260000000	1641968060000000	1705040060000000	1799648060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	89
\\xbe40d8638026c71a02508be60f968f5b08b7856beeaf5760615db4f61be8c419964d83ae18a180bac4be9878994e114ee943a8e16aa6fee6575dfe733f48f832	\\x00800003bb7fc91024e17a10e18f257f59dd24154e045ea3697e200e52cde990210316bba5fa35085c86dc5ddb5293f975c7ec4a56b92ef4159ed40f678831516b89eec716095adbc8b9d0ce7a8d70e6cb110dc4d2eb813705adbf8a8fa0d9556ed750ed67d0bd146d4837af1455c6f02e14fc7034aa09044d008c19468e7985ab6586a5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe23dd9a3829050f6c255b7f688814cb72f5b8e4fb257302f5de587cd54b8588985a0f7f9a1404882df3311e448b10684c9f912b58d5127b2d3e1c630af05d40f	1622019260000000	1622624060000000	1685696060000000	1780304060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	90
\\xc0b4fa36890701a854a2f8f09e59e9ca77867356e32eb679c40d22946cd78d963d9d5bb82d2ef88344ed8a7eca08d8b4b4abdbe6161b40fea9d45fbebf73fe6d	\\x00800003ad9c251a5e8f42ed573ae14f305ecc45d9580e06464ebebf4eb4eb64bf275ae5d5045a56567d649fe7acde591024b254271fec7b1536a02588ded690b5109c17353ffc57e46c9d37a076ba9cbc177aee543a2b7df6113fea1341ec865fda6876d0a70a114e32539317f3086ac092afb15babdc5904241b94a8ca96351c8f0e87010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6a766fecfbe07c03d3516c27503c0dbf72417c6f770722fa7e1dbaef704e2552b32a4fb43a926295edac63de3e866421097b6a73cc94bc8edc2c82755f263e02	1614765260000000	1615370060000000	1678442060000000	1773050060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	91
\\xc2fc07a14c2b03c85d429ffd4c303ccd2638bb4d90e745a184f1799f636e232685404e1798992677e9e5daf55ec421659e616124fbc7bd67e3a35a9022fb2ae9	\\x00800003c10f5e219f5c4f4b084cae979b368ed07a2355b25b8415faafd700f16b9971ecc9b07fa71f4b3c3a4ad391811c7f0fdce7f970370e6f025840dfb082aff441cc52a7002481d6fddaa53f806c5282b5f936af8cbfcb8d5c99a6a51711628e57c22a76e8a53d47397246ae445f1483630e61ce9f1e72c5408d6606b4832bf7eef5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7cb4751112243fedeb91a308404e4f639a0364af259fdc15cbaa6b2a3a5b44d97e774a44ee4e31df097e176dfcecd472f64819bbf53a45039a2ba32f6f89db06	1628064260000000	1628669060000000	1691741060000000	1786349060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	92
\\xc22cb533772d670f24798a16e936d424a2a758cf022dda9cb913861d7845a4ce45ea7f0cb6fc339f86e291187fbce7c6661754cff2d290c10a0d057ad9bf5654	\\x00800003ba257d748ae92c541b0828047db01010e044e5c18616c877e1451a72db70b5ab895b568cbe7e94fdc03155b72bf618d44833f28eb37395e300c48c129d53d4c63e77d4bf5c6624c3c8296acac7a4d38157b5581354fadb16d1287f185f4d1ea9f86656b9994fd2764919cd8d2a3db6e02ff16f2c75bde383f810ec34af887dc7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb434cd3ebee07959da42195026a375f58d35ed07eb8ccff11a5d35a4b50a77b74d2a38adc13d15c1b281652bd026a072a413ea4072fba95b39b3f22caaa5d907	1628064260000000	1628669060000000	1691741060000000	1786349060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	93
\\xc83814a0f50141566a2c98ced08d443bfa5dbd32664cd7f5c3cde1a8bcd3888f6a537be279e6b9e704554996470b7bb9930eb8eaa488426bd4675103f67ba616	\\x00800003da89c891a5d61db8bfe23ebb9de3e7a61021c9a2b2401963dd2bf4c5ed454d7082378d375bb6ee75a2d0d201107b683cf554e58f3d3a71cea018ab7d5662051b06cddd890568c74d99005382410b6a3b71af9eed6c8f2f40ebc234b57249b463f9600f3b3529f59b98f07809c992614d41398d8802ccbef4b6b3747600a6aef3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8d0769d6f3d04379c718ff792e97c8af8489063ab7950e67f8a4f8d80971888751c50af1d8d9272faf784f3a97233899dc1bc79e80a56e85adbd9826934d9a0f	1631691260000000	1632296060000000	1695368060000000	1789976060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	94
\\xc8381f1538d3c38cdfeca70362a6f55800fa79c0e2ded15deae6e20a2aa0fa77da3bbd03b2846c51f8a132c01a9eeead75061890edb23028838bad110c3d2c30	\\x00800003e42a581bfb995b078739a3ff1b357bf8069c7031730aa1edd82b106d0e04d8885718faeca9c41057a987192dbac784923fef272d724348a4b67235f320eca4a52e3caad411a82b5776e4a6654fc1c3e76ee6403a9536ad486526e3c9261186dc67b54b5a2916e8557d1ec12f16452c90ad9f8eb3d15ec61ba1e7072e3c76c887010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe7c559b70e52105a95afe469be98a5e3a2f0d42cb29024b7771025a718627555018712e4822f14f701568c4c1e47ebb43c6c3cb6c680cc3697649caf99cf7c03	1628668760000000	1629273560000000	1692345560000000	1786953560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	95
\\xc9bcc5a0d8e452158ea81728e90e26b3629106382182465f89058475cb201ca9c11f3bcf75fd680b03c34aa5940c1991cad18e35be3cc11ce95830add7514545	\\x00800003af50091260be2a13f98fc64a78bb7c38e4bad237d3f0a586b8b48384b22939cc6caf2416ae8fafb7e0a7a5a09fcec43d6c71172f24ad8dd03791deaef6cc49147bf16114497febb2c02e3401e788b33f0eb4faefe52ec66abddde8542a29d8d67ecf1cf5233214c94726258dbd4ab1ea57ce422905eb328ce580eded5e032c2b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1b7113a80159c284b83ee1fe1527d76e5e8ceb8908de6e482699cec483fc3447213244afaa73d50b2ee79324b0604fa717a10db1fab0108e6f006b862d79130e	1635922760000000	1636527560000000	1699599560000000	1794207560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	96
\\xcb380b038f64195694ee6827486f37eaccadb5880ac8b141fcd91661e5c2e567134eb273fb6421a4f041162af0fb5c7a8a4b4611683ba723cb51c1f7a48dd5af	\\x00800003ad20f8826bbdc14ccfaa5ca54def0fd9d065f6a376066c0dcc7a98822d598e6d0391379a1fd9b11bbddac3075108c584b7c273946dfea146043fc59696eee56b2c72fc157267abbd0327db4928ef9f06c3c3fe54fc63a2b2d048b7544c46b8cf28b4020d307f9f6ea944a757788b9ef68c9ec8cd4474af1f6e35310796fd6d3b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa1514bc0f511c31894784ecadf93d6791b3f8b185809067c3cd7fcbb07e65ed217a6b2e681992ca60cfe9d896585e1d146b7a8267bbb8f5933ff2e1306bf810e	1631086760000000	1631691560000000	1694763560000000	1789371560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	97
\\xd4f4220ce3f9299032a5869114be36b13445e8391789af6fe6691266cd908246488d85798af74096d5587fd3934fb29d8db0adea326ddd00dbe936b0951ae5e5	\\x00800003e3f798eff6a07159b5e05d43674bde4d35273be3ee1498ea9d40b42d2a640303982739c072764d6b82fdaca0e513a99e6d0cc1733fd72abc7dcb5d1a88d87149e1492377f6062e46b266cdd76f616eef60e3ddff7317cca7a711b270b0e7c6c8bd0a977ef63368826623e91451168412829a03ad364e2229acf43a66c92ef9d3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x62e21fd81162aaf05c6d50457bdc4a773af24d53445df844f6b3498437f812468333004cb165379d2a2d1a5b5982364903870bfe42984f8778184b1f3d890006	1611138260000000	1611743060000000	1674815060000000	1769423060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xd6887f12b01a4435dc6aba8ea7f1b1609c558b026b0a276028504ab7f8c9d947827c147eafccc305ef5d27ec99a15581948c537bebb5dc1a96a0bc5caab42376	\\x00800003e53468c39018aac934984ccad2beaf0fe5a7384a09b8dbd33c4e95b008906e9d2fe0209e1dc598719f5c0d516b2a3f8f801b79d507efa653827069faff93df24654e7e370c3f9d77e209f74a7a8f98434764aaf619232f81ef3a04cb7914a4df39556fd1e6fca54da327f628388cbad6dda07275bd913e93f1128b0bbd19f1f7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4ff0067cee3fbd577b279f71cdff7a971f4048856f341d22b4c4d7c1edce8806d33b7f23f625eb71021a315c60a8b63e0f6c6dbd2684d85a85e69821ad9d9208	1633504760000000	1634109560000000	1697181560000000	1791789560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	99
\\xd6a07b35d43bc7abcd1fa3bd3db5b2eaedef1a5821bcb68bc41c9090bf45a39813957916d24e3337e7dfbeea4d00f90e41723e50fe712f48e3f9e4a31c5734c4	\\x00800003cda5aebe68906c9d18caa9a6d2906224f6559aac06e5ca0f5a360ec14fdaae3b233f274970283269bcaa0d5cb1559dae33c0b0ba83d1248d5dde770f816920d4b451f5919eaf9721dd56cf0d330d19e08816262eb3b02a29910671c3bbb4b6d146d6f10d52d0fcbf5278b3fdc25136641b34d09506f364033a7470f6d233b645010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x660d9946f3ca32359933d7428b973fcc66d19e347188cb0bead127f5ff8592c2942a8fb3d8aecc9d838e3ca73f8180f846b00b67d40a8e51a11560bef3f51706	1632295760000000	1632900560000000	1695972560000000	1790580560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	100
\\xd6805ae6f091f43dbbadc741e605a1fd2f43e9cb607e0f4b154875cbfc45e9c3927bdc1fcbda60581ae56127a4760faff7ff8015e4de1a947475899f04b0fd57	\\x00800003d0693bb380b6598956789e17298f8f557a6b530474a8f44e7a8e898a580b57f740d4f0b453bf59e7f559a3d9a4014e1c767388688af5e1b25cdcb6c6d7586188427493697a5e79ce3de4caaab5593d296d076c97fd1f6efe9e8e3735a035b97430a8c6a5f286c000b69f353f0394172e92bbf88df9d22e6fc547967e4c7a7927010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x93605b933fd46690161b776b179b39b2766faeaa1664f6792aa53abcccf342ad542137f4cff9b4a8bddd93502393e0408f1748da9481450e42c967c16ce1320d	1613556260000000	1614161060000000	1677233060000000	1771841060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	101
\\xd6885aa032fb3ca09e22421785ce09bd82358f8edcb28e110e3e3db824fbcc1798f67787ed597a5f064b5b93b99a67cdf427a8b0ad622504232e89b813538233	\\x00800003cae243917196da96c6357cff0a838390892f40ca4b5c38d66ec5e2cae823b8698f9ac1676fa3c060e26eac730f790a778fbbaa8ff538129e49461602358d8eca864f3b358f9f19b41d0f33ec7fb6652e076647bc211ab4e5eca9d807ebf607c5eb7568ca0deddbc983ac4bb9c9483f492cdae8a573b38a9da32cab0a7797c63b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4f76a818a62f0adf7c642791ce417ca06759ade5c93752e9f0f663814ffa6aaab363076723cf8a2bb6298c3c82aa3530657368c852a691c8b6facde3c7e69501	1632900260000000	1633505060000000	1696577060000000	1791185060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	102
\\xdba8cd375fcf3fb6108ea2b37911c963d11925bcb52ecea41c48df39b7b0b386938e27f8ae892437ff45daa377427c1470c8420299c07a6f19f0d467df068dc7	\\x00800003db697d9f8e9bfb3b8630b71e2c1defc34b87b49349f7339bb5647b021598ebe90a6f52e1a87362bf7662c4a4df24dae4eb1190605b22982d071f32273775c95b3922a0f78ba45698d0fba7834175d44b52cf8fcaf086434a89646b21837dc08f7249c0e5f8ef07042077e4de36a39e5c710083291b880cc8d5977b557c96d669010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc103eddf45c42f29e7203efd8c75550272ab8c590154ca0cbb958fd134612070f0fe42d661618948786467bac0d0d8406bdd8e971ed48da9598dc3607b1f7609	1628668760000000	1629273560000000	1692345560000000	1786953560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	103
\\xdd08ce4706884ece08824a44d6f0b7797539c45819c3fa111a7f66681f34f156523c23cb1871fcec5ac2f553feecbf63f22749461171fb1ded5f29041c58aa49	\\x00800003df7733d814f0a5c5f1e5eac2d5f02527fe035b85b0a809caa30a63ffdcf3303ff6e3586bf988c2afac1501b8f4084e84777887c76a170fdadb79e187127f7d0800588ecde414a01608bfd13fed69c43e422822dc419fe799a325b9b708c591613d56495ee9938d438d27bd4db35e18c4c4a9eb07f50948237c1c398107dce7e9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7855ce93232441c8f035e1eace4c845d2f1357914094ee7f3d24a0873c300a6581b5b621bc38d6fcb5579f465cd88e86b8b05269cf7eab85b7d494648a933f08	1634109260000000	1634714060000000	1697786060000000	1792394060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	104
\\xddf4babe90440876938fe5e0b4e9efafdd722ef7578fa17ad3f8055799a43291db54af9b16c9b152e9f6f2e268cfddb6c6061964571346ad7e9ab2774135bc0e	\\x00800003e160098cafe1492c52436e01fb6574982f7269c41a456e58862ada2e4b2d5c9fe2c3f62bd6665df7ebba161173cc2dcbdcd5d0f758f879381ba039746054a0536abd343d7348784f13ce5b9c12af0eb12f15f7b2809dd60ef42c132ad75fb88f115e40059273926c61eae1b0d166780c2a706754a48791683dbd4d45b8b906e3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdbe433ebd56e28200110296c7bf7b18271e34a4c50aba71f05ab22139f9b9a725806573f47c93b345cb6eed0d420cb8032feb32c17d103cfc70fdbdf3b88cd06	1619601260000000	1620206060000000	1683278060000000	1777886060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	105
\\xe040a07066ec7bc27a840e4e7e3c76a6fca0ee3987b539c8bc5b395815a38ef08634352b7b50939c6e36d5e758829c7e545d3b6bf76ff02582a9d8a3a59aaecc	\\x00800003d126fa35803f8cc561c7d878ab7886438f0beebc6104e39da304b79321edc19a398c9136d37743ab25d98baeb99231996466b2e9df5e8dd699ab671e82bdf9e3c33f06cb2fd1c9ba8076dc295543deed238805ae6b6b10b9180b21b45c7a018b216b989e770136e6635ae38eaf0cf3c6d57df5d924d41fc76b200e8660151d2d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6fff6dc84a1fed2ceb9a21f2c55386dd3c9bfaa1257919a69ff04a8a5fce3aa26003830eff96ca45f528445dd65b635083a40865c525d223f4ef7225420b1a00	1610533760000000	1611138560000000	1674210560000000	1768818560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	106
\\xe34c2b54bf3f60786aea57c9319c2ac57feee65da32e6046d4647707e7b8fdde38dd3d9ce13f33e132be691eea653084e187cdf35afa2f54258f806d130baf97	\\x00800003b6c427a66cd9ec355ab819f73d5b58009afc0fa54726abdc76f4adacc62eedc39256a8cabf26fb80b853b431be9a46e5bf474bafeb872bb9eed77a3cf3b89fa4c0635d658e9d842ca1b5fd02ba96437c90c36bb4a244206fc58767ec33a1e7d99ddabfa3a59192911e9a9e0e1ec010e3c00eda2a0ceff09417e13c0b107d49ef010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x49fee85d85ebed2beb777f7390240679bdcd4c7da8ad2050158138ae1953ca76852bd9493c059b052533fba2662e53cf94ab5856850e5eef8412a2ac79714e02	1615974260000000	1616579060000000	1679651060000000	1774259060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	107
\\xe7ec5603b19bcd69bc785e82a7bf00083b1811bd435bce873fb86b9509adc853b25fc4ca8fff47a460070929dfc21d13c20296e991b6cf2ed800d312fde476ef	\\x00800003dfe5c8bd3c8cbbc96298d4db457272dc6c698dd6696901b2cfef1261fbbfbaa007e37475df944f5417568bfca9a6bcc23f9c5aa7d26e00c7f84cdab18106cdf73e439c552137a135cb2fd77d5f513f4cf85acf1473d9a40965087ec13f3562d0aa44afab442cbd840d6879a657d5d5f6b0b91b9be9f4fc93e1ed6faa8aa3e245010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc4f34a84f9574b542f6dfea80d69275b96b8a7ae5be5ddfbd2692ad9bdd9f73f362e9507ba1c3ad94bcf44847d09a5d7963c65cd9a3595e33f729a30bd7c780b	1636527260000000	1637132060000000	1700204060000000	1794812060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	108
\\xe9b85ffe1706732d820eea423856626d00e6fec04ba5c67c29e4f803db67f3e9c0b403b169c69b12f0ecdf32f2bea6b7a916a7caee1c6261f1f5c074949c3289	\\x00800003abc46c436b13227aea5d41566ddf85f2ed470fd106a56a7768b2406f9e95621dbab9e9329696468299b8cbe21638e470ed9e352809fff3083a9957b5dd4d28e6ccd6ca3ee34d3a9a74a35dc454ceafdf7be01b90259e2222e6f2c297921ffeaaefd79198b0c8e625e28f6d3b85a35c47277f0cf6e54a06061e56b88ac518696f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8f52ed4eadffafd014942c1023c3c58c614ce9f97cb16dceb147e68cb500c4e0f6a18f787f71dd7840797e0b3e853e8afa4129ca7ea4a75647b131b71f74b30a	1620810260000000	1621415060000000	1684487060000000	1779095060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	109
\\xeb50f4b5465ebfd8a139945562ac1bc474073edc6a6a25adb72bb72d1fb6bdac104e1ba99e23d35e6f34e64274e2ab6a01c2948165109af2eacec0815d40bc48	\\x00800003e9920dce4be1c51941593494b3810717aa8444458c97338a910b0b5110f0ac9b4a863f427d0c5311dac53145b673f8cf4cdf670f702b11c8c9d665b32c2a39173a469807e23c5352f104410b6227b8cbc07a4a9cca8b06ec2cc693874af6ed290fbec44c9b03b40b8177594b0f48bf6370ca97b996655dd62b20f628c0df2947010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x354354e98cc4f6f1986c9dc7092b5d450475fb41d8bea7950c4a1aad4efd1572c28f84710b32cd647728fd55ec71e574e2beb68724b0a1d5d0c90994df825607	1623228260000000	1623833060000000	1686905060000000	1781513060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	110
\\xf0fca82ed5e1f475885fbca451b7e6d2432530bd12461168ae397b81d818768ff7c392e11593427066f2f3b6ae605fe44de945eea1c6cb67382b1c013332802e	\\x00800003b3dbd691868c2c0e9a383f28fab072f635eb16ac1a2516c45f1f0bff287f3ccaf7ed96744ab57a196da53d43df761d4e115c23ad2abc2cff002e6aade06fc2712d395e746ece6a251d5e1abdab83a11d6bcc0cf3a5c49202a8e37423f9fdf220cfd17ab0f34b4cdb0e0aa1a32545c5bf385f70daa2b65c63ee6f6bd77664b85b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x885d219d74d12cfe860ccecc39670a720b7686e25748a42fc5b9951555cb582994f36564d4bae455e33742f441dcc7f07fcfff008cdda7fd7e83b671489b5102	1609929260000000	1610534060000000	1673606060000000	1768214060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	111
\\xf61cf9b75c49f18bddddc1fb446320a205e7e80b1b530ed4a373abaf976788d2cc8883701062275945c0dccafe30b0a8e815f5638ca189ccd1e0cdee6d5c78a1	\\x00800003bb8211443e814ac27a92e0d604fbd973a69d0ca4d2d61b55215c5767684340b83f5a2bcef08acc58279be78cd6bc329467a2f4d72cfd4f3aa8fb4bd7cdfaa1420db442c1fd4ddaf1abb6170742293f5dd1b31f0ab9716bc393cd17eae4da368a5c98f8b8da8ef04a4363992435888a113560fd6ba3b37cd185687b100aa39501010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x34557fb82bf3e9ca912c6b77d2706de978921deb741d8b2721870691327dd09bcc08443336b113dc2c783cbebb2b208dc62b0d3d97e54a52108f04aad158f00d	1625041760000000	1625646560000000	1688718560000000	1783326560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	112
\\xf6a4c474a39e754050680b775854ab84cd0d3b1beb3741a5dde70fa16597bbc216ba50c511516ad6001957add1c27a3960341b4458884cde8defea5bfa727ea1	\\x008000039ccffd5529e6b2306673be86b723fb5ad25dcd1468ac2bb1969932c1e205026e8c778d8c2f082dffa0d14d840d9588f99aa7c108e368afdea756bf33b289e7fc6c6950fccab2c03adcfed8113e03584467601bdd7b16ce7e72681973d2f6bf785e78bc74ccff36b69dfa913e89c84d0ccf6da889aecf54d944987c2155b694f5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x596fde78248100f08209e0f28bfcf869dd71b98d50f0e1ee794c6ba6d45b71a4aa65d8d74d1daa3136b69f0fabd4bfae2d31e870aaed068ca1bf23b161e12601	1612347260000000	1612952060000000	1676024060000000	1770632060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	113
\\xf67077d2d1d78174054aa853f1ca401bfee4b81dec7bf6a3382c55b0f158003038137726d0164f63c9eaa00f3698f5954f70716ed656a9ab4c871f3df4b1d285	\\x00800003d609e85b2c2752e76dfa1c12c957bfacdb04c350d6431027672c4b92d4bd2376d570af9a1151eb822b66f0cc3af1f687e1588425564687de1ad2165e87b795300cae5f475fcb723dd645142b6ba81b7450047f1ab14fce28f4e06ed7ccc278cec27f4c4449955b32d7f6cc40dee59079c12308725ec644bfa8ab9356354f8b91010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa72655dff05b36558f9a141168aa9009c2d686c8d157a6ac567c6f376996882d620b9243b5783ae4eefc128793045038ec86364e1ca11e885ad3278b3fad0301	1611742760000000	1612347560000000	1675419560000000	1770027560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	114
\\xf7346f51ee2a785aeffe24e1960a7b84d0c3e524a99184f60716b1c0453a98987304baafd5c5d58cbfb5e134215aa12ce0b9b25cc560b0055f042c939084cdb7	\\x00800003a8fbee526d03e1dbdf58bd2c0a2bd4d8c40de3315ccec0fcc6ef7ab1069dbe15439abb2a52ad8afca72c1a0e224f9024d6706816cb5cf0334d282c014cd796b91ab79939c0696b2f094a24d4548bb667228574c74255fe385a92d6ae9b7ea0337ce23ed2c391e9ce84eeb1dd68783ee4bd3a2fd9e461824dbb3b5c865eac1e81010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3ba448eccd4247967a9b362626a3b0d9e1bb23fbecfef4b35b74d92000f4d29b5f3823af57c64ac79d0238d6389639b84f60f093bb713145e4a317670bc9e106	1629273260000000	1629878060000000	1692950060000000	1787558060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	115
\\xfb34c2dc352433e698032995d5cf5da698fe042721ee21441268ea2fd115cc396bac8f8681607844ae94bd92f622ac88e2520175c17b2610f78b200173b79500	\\x008000039c87c4d642e60f05bc0d872a85d95a99eef893b4de19a757eff57c80e3c855933ab24f8cf0b77d41231c37333ac65edc98a326107d6803f151e34e437e5e90267569b0eef0e6fe677e313422e4df963d23380b9a50093fc6b4c0ca1c795e2074becfb404e41179fbbc7fe171beed94599865403b2085f50a806762939c151c7b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x23095ae509e7805774046bf5431e36d2fe6748150f72cda749f977175a2fbe72dfa07188f4082811c5227f427d92ff84f74d5426101e3c354ed0aad0c518710f	1640758760000000	1641363560000000	1704435560000000	1799043560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	116
\\x03adf4f3cf807bac40af7581cb3f7c6e9286ab25328a9ee3cfcc93aad8d5b3a0c34dcfb869f006ed2d3a90dcc29c2db4f578fa13003fc933a2a3841811d44906	\\x00800003e3ef0846ae51de3d8e242c155be6b4ee87a683eea68ca700c363187aafda7efda36e012fcb6dcaafa08a10d624c5bdb4e090856c072a95690bb6926ebe17d54bf83700876a8ef364b3dbd5a9718a5237ead73111f4b4ba357994dc9442cd39c154d16c292407401873661abc8098e623dfd94615a3199f938ce509d89db085bd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x03d9296e79ad988ba07f38256506d72d28bdd7d9787041cbd0225887093d0638cf0ad430be7de6a82807e92e63fab1e42df1e64fe7c7332c9ff1f9d39a8a730b	1630482260000000	1631087060000000	1694159060000000	1788767060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	117
\\x0871b8d79e3d8384584a4ddd82945a4835f9d754af7340ff7dfa35388a7eefd3b576751824f1863e687206dd79be8faf21ca44de74d04cbad04711e3602a183e	\\x00800003c3e1ee2a90f59c2bebe940d976b36a454a16fd0f7cf013271603ba7fff189d20e56b95fee5c97e170c8627a0c351af91124f351e99e9c6607107200ac36dcb5cf373b91c15a11a4354bdcfa373bfcaab302f3bc56922b95bb7b21f438fe641ec4fd81e10caa3ae3aa2c2584b283c9169b79a8de3f1681c062929f28a0ff1ea7f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe2b2cc39f28579cdc32f8012ce5c5d192659096ecd9ac10c89217c78cb5933aeb94f40a618beec70497f2b3015871f57fadb3588dd6f0b46a3147dbc2a6a1a0f	1616578760000000	1617183560000000	1680255560000000	1774863560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\x0ba19734eed90f2c35ec770c9ad8b9a881437b39b266b3c8f84474966aac92811f02ff1c30676b7d206d9d034759598be9db2a5a051b60826f5aa0cd29bddfb1	\\x00800003a3f4ad84b2673f66ee5d97d1e9413c21a2d0809800bb8fba7ea43841d8149a246bbd1c0e487cda61230a28e664a082caa4708d9f0cc55b86b27e9d3ecbb336eb8d6e937d375b5827d67b83bc1037851acede4d38217844cc7bacce8439f640103096ef07d06f7b1d4088d2879a456aee20db28db7dda5be325b38796d24c489f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xadcafc6ae9e43e91cef37aea202876f4770caf45b5bdc51db2f34f06a5bfe39228a200a3101cbbf59f23385c07598ebceabd4677f692c5dbcda3b599577b8100	1625646260000000	1626251060000000	1689323060000000	1783931060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	119
\\x0fd533c3e373d76f1d6d13686b54a8b550ea65582f85c3244f4b9ba03ddd8cae50fe59f8c91353763142fd2c170cb2a96718cbfefba7dd1f4c07cf73b1f8d172	\\x00800003bc098a575e50bff173495abfb54241c347f6625fab9733e4e5291a071ecd5bcca45abb608e7c5c4d599399824a3cfa008ac67db50466930d64b81b0f024c3bd5c4bc7f16b0d3950e343fa3b3de74e7de63f7737d8c4a4ed2e7d399705aa7fbdd809520f9c801804b4d67c5e025cf14f5e3eab8d2c6cf11056668430e13b62a6b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x15a54aa3c3bcba98a4341844873f32b517087a7568b865897af96777beb55cff8a502120e2edcb11c377a4080daace75695918118698a9a74e94727bae14800a	1619601260000000	1620206060000000	1683278060000000	1777886060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	120
\\x11d92d4f06470b9c8532762ce7357e0f60de5a8b4026c0572eb80fc61fbfdf6ba2e6bfd223f9d6e9e037b2ef91b65cdec143f6657314645065d492572cb63b20	\\x00800003c61c4da272c1287a04ac0269f227f45dd539a44e60a6807692db37c2ce4aaaf40aa2dbaff40508a37b4b646283aba162e33a7f937888d637771da3460e0b073a73d5a9c157672959d9acffdd81e4e63f4516994ac30478feb1495f62b9d3dbd8a57aa4231349a906d60c72594614c55efcb2eb25eae9c07b68d15bf48b29424b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x174a4755855480d38ebd2a8cd473d8d3878f5dd13ad7d5af3d36a1facabd5def1da9202eeca282a7f53ec669e256b0efaede7b978aa73b43dcead7e8026b270a	1640154260000000	1640759060000000	1703831060000000	1798439060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	121
\\x1591e6fce4b73bc675feab9ee4606e40286e4228f69519b1ef6e442d675126f1c4a48843bc09a8eb4d2306e6f73c70a90ec7978eadbe5a61a1dbe71abc20e838	\\x00800003c21c3d6627c92b9e8d172bc57ce6c5b752a3e7bf7f55e61563582bc8bd4d52a23c2523a4214db21205522ae64bd1e77ce5828e5170c5ad3ae80953e3dd662fb8917edea2bde72f5652bc3450845d2a4e035a1bf63e0c06e7b4791ddf850f00bc5ebba0fa8e845d00f4f2bceff04f81467734c7f7403ef41922938f75cc96806f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd03e7d9a6fbc50c7b94235c7e67f871bd5c0642ffe8975c7f813bdc6f0623732ea34422e94c049b14a6e542f8b56cee6e8c59e8e8365b2c2445420b3d2c4270c	1618392260000000	1618997060000000	1682069060000000	1776677060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	122
\\x185500c270437a923836f505431e9becb19941534e1d8b0a9877e984bf81c1f2255700d28c44c62b7b32efbbf7bb71b871e475804ae2ab3fa0c02779745250c6	\\x00800003bf286cd6b4a6a5c0ad8b121a57521a61270c115ef8c0dc15c223e5bb924f5fc30b9f443c07ae98100af5d4b291125f9fdf14e6de39f59d44e4445170cd65137fb38711598d5dac1a93a20897ee0b3f9d6a485fd42895518134799b2df7c823b7a8bcc932fbc95113992bdd7de86cd341ca6c90f015a006749d087845faedaf57010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x01b6003e58cf47152ffebc923cb8b8e86440cf5c957b2df517a0c2a50693a92718f9b5c6a5c7ebc620b2ac73f15ebea402f1ebcbf90e23d27c73ce1644f81a07	1623832760000000	1624437560000000	1687509560000000	1782117560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x19096039f3664fbced0fcaf396556bae15c240bb3de4661ba03ae86e6d86b798378a8eb9b8cefb9121fba954d3430355029be4aa533d83a4947911c4aee8bb13	\\x00800003bf91cde298022e6aa18600aea066ffe7e1efefbff14be032d83faeb0c01dd1dcdcff80aa73bfb391fe1715ca9f19e21840ac69518ee48d3956f767707a9e48ebfd2afd83b96c3f318bed83542f7d49fca4d593c8c32f6348cb124dd5bb17ea4b00a7bc29483b17c8f1b0979c75f9f269a738e9e566ac94ef8121262a145a0773010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf1ed469e52d3264a7da260dfa432d1bc81179298f3211d973d5746727ebfd3858ef0c811665b19ab678c17ead8f3bc287bd22a1ffe43514bfb96173608864b09	1626855260000000	1627460060000000	1690532060000000	1785140060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	124
\\x1a65633096759748a6e011ef4eeb147bf6051a7e8c78f21cdfe67c569a9fb3159264b37109093023cb127303a88cbbddbea3568f9d1e28eed975cff3e73bee68	\\x00800003cf0d14d97fbbaa398bdcaa46de187d8c56c9b34e8bbbe8a88f4a342bddc74ac14c12ced0579c3c86cb2fff932ac4dd8ecca5a5f230f9f1957ba64940ca74ae4d43f3500c0855155b19ec574d7501e50a3c57440858da357e06a1e1c3e33e2c59980a949bb8d71353598bac5cd16e9599b9e270e42f70d8243ceaece4234e3905010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8074a7c9ec1b22a544f83393906443828fa5a543cfe4835645852bfe82d07f6b22a606b4422de4eac18fcda94c0eb7169219a1cd09117162e5a29ff9665e2e08	1615974260000000	1616579060000000	1679651060000000	1774259060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	125
\\x1c3175385ba9e351c5fb9aff7fa04772afb4b98890061ea0d1a6623658b3c3454e2ac095466c7839acb3afc21958fa50b5dc0200a650eeae95f5f56c8bdb2e90	\\x008000039faec4525435dfac8db53255428b249527e779a4e89f1967c5c672910e5bf0599643675d413f4486e73098260ca2987e2273961ebc2aacfc848b3e60889170ac8e3f9ca6e1abd5a7a310f9722bf1876fb8b683353e6d08272d78be8bc8e6f56dcadcccf2b5739be104a66ddec49b6180ad1e5fc9bdc2b60558ea1987296de5e7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x73d9d30e93334f54eb832ac60a8c69bbb7c49b675e587322472497137336f05440bf0874322d7bd2c772a0965c89675a225b70d8b9361d2488864fa487077002	1625646260000000	1626251060000000	1689323060000000	1783931060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	126
\\x1d31b3831eb0ca6708d75faea11e96d056f2c2714bc433fe5db744dcb2332b08368c4d170b815f7ce8a0245d65b3b397944a90a6d9e19bab45ebdc5d0682a5d1	\\x00800003acea1d930ed328615f511078127132783629e171c9f2f8d73367bb229b926669ae1adb2ae7232a25bd314454371674f4d99668e95264f1aba363664d3e8fe97f46339de41b58620189f4b00abe010a651055eb04c04b694ae0a9522de0cf2d6af57d4b7e1bcf230fc84d437ae6fbbf8930cc8185624621a6b429f25bc62dae6f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6b246d704cf76075ae0bd4872911bc0996d83c2942b5bb1bb9edaeaf01957f2d91ed20cc53c81942c8932d88de65e1218f0828c92f1333945e6685c9267a530d	1628668760000000	1629273560000000	1692345560000000	1786953560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x215553f58d16857cea419b72c4a73bd14088a80f8805835eb918cc308a0fcdba2b10d301bf1155adc710b5fd037ed4c8df105c09007ca252afca16a352168600	\\x0080000398a4faf338b35bb43d79246c43ad7c870e6c2721501ef7f9a36a0d0cf1de8d234aedb4047933e7b39758cecfa8b8364569e2fadf6031340da0e059d97208a31d7b196c147a14cf84f628297be316ea07fb4a591c4c5cb1c91f7274d07c0753e5702d104e3a97e7641b3b1341534a3069fe1180155a4cac4b3cff05ed2fd03fed010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xffca945d2fb8640d71b8579224d02b42e0d0c06e38049426ef778577be27076bc816b9cc331a5f30454b9891001a1c805ce4fc8ee08751f0b86cd1b9515bd602	1626250760000000	1626855560000000	1689927560000000	1784535560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x247933565840855ea46d546e930d21eb9bb9d4e74c7cbc7694b847871d627147702593971101279e841da60707f8248588cca6501e642ebdafff7b69ec79c3b8	\\x00800003c47211d52eceaccc165a913fb7c2c07541e9c2b200fefffeee98bc28df95658bc00cba217c50e090a49ed0141903248f611b87bc447c21855ba7ad681d74a5740f61cd6d1a000e73f1319e26b8ea3ae6759ef5f6491aeaf5b441717b3a8d8f88e68ca6329b988af1ae7134fc928985671f106feb860190399d2d272f853c3e65010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x25da6ec883ff8ee149ab210e399f780e5bdde9adfb6b0d6b04968345298f6056ce790ab790dcc909cd02f54c0974036ee72ffc7c3e70303dbae402f06dd91402	1629877760000000	1630482560000000	1693554560000000	1788162560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	129
\\x24918f7488cd7ab9987b732bc430f5d2d784e037953d32c37b6630467bca738da28501f05881ece47669fc2120d290037885d955fb07f6103154f3c7cc176fdd	\\x00800003dfd3f9977c0c4f1760ac3dcdf17c9aadabae10fb9c87883851240be48615b89ec93fa6371837506cc6a314de0a0e4f677c88016c9cc10d16d7369530074f2bb790793f4e8cbffd8f61246f9ea921358d3d184758f6ce8087f2e20b1cb5f9791b173b405d368d1048ff15206122d5ec5e975b1fbe69c50c3390f7f67a8be90f2b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x90eb45e9561c4b4a3f149d1138a44d445d194a2002553c1a072b1e59e5d16076c348abe21ffa56b85088359580fa8c5bfb9f70a0322b1bb45b7c102515e9bf07	1625041760000000	1625646560000000	1688718560000000	1783326560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	130
\\x28b9e406c5d873da8937521eb7a930d1b77dc6d756dedb9887168fdf232ac78a4e0db07bc524efd29b88bc5f4a1e67ba674cb2ef8bbb3b9a41a0fd274c20e59b	\\x00800003be3af822b806f25d9124b0a48a586440cea09a16b6233f1fdf5be1a3a68399a4b9c556ffabddc533f4bbd1bd2b203e11f37f82132862a0f596f46db2aad7bbd3e9f37b6bdd140c1ad502e3e45bfa6bd5a544de724c237a65e507eff288ae4af48c989461c11d49d8d7b045d850847c2022f65d5e12c067e1b838b3054f645663010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa5cd25dc0c7beca82ff095a3c5b800b295ebd45df2c7d4f84d5685dc9546b1b4d04806508df09b6b60a0253908d135d5f8e829a369c4fa58b0cfe811f8309e0a	1633504760000000	1634109560000000	1697181560000000	1791789560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x2a4dc51ec771e71d36d55b996f45e25bd9a48650eeeba23c22e995e5ce3f824fb55d82cb1dd82987c597ee2efb979299501179d41656c812e910e878a5fc0b5f	\\x00800003ec7326db036a49ad92216e04ddb86b663748ba8b7efb4a6f2a4c565b3d704df0d7b15ab5b3f423be736cadf9499be7cab87ccd3e0e740072857fc99370aa7a67e1b2688089bac2c567c0e2d62aae973173d51b9fa751fee1666a284659440614bbac0de253f7a7c1a89e46af22cbde7d0dc5604d8f6c52845b2cc62d15e2e4ed010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3d15a749ccc9abf61653cb10e1e231b775c98acb9b4294318b572a19342158145b08634afa474693f3abcb76962dd3e24bc298f1696d0e88c9d2cb70c49c130a	1636527260000000	1637132060000000	1700204060000000	1794812060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	132
\\x2a21e341dbd3a114c31dc4300bff658dcaab1225cc1fa8895398030472b2e14b4d68b0b7f85a3ae084fd2ec4934b21fbe5ed43b634b1bd86ffdb6523c719e620	\\x00800003cf7212934984a226354bce7caa588e2e6d094453a120b0633ea2c5d804afb1b813b3be87b975b1ba7445700cb43ccb0ff3993dea11bd7b8d185fed005bf6832b16f2f6e5f441cd6c82733aa437b8d9322d8f1a7d35cbc3c7c97b326e5bf66cd64ee0c418dbca325082e40c64fd37917b2bf5c7bfc819d280a720de3aa9f96e6d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xefcf5caa62938f1a09c81ed0710639e745036bda8bcad5bb005bba5ff3235308bd0fb34d0db433487e879c784262f068d7f3cf7a0b7b0cc622fd4ddfe5def405	1624437260000000	1625042060000000	1688114060000000	1782722060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	133
\\x2bb9c250526ae6d845f82b8de4204537aa0bf734d20ea5ec7777bc0f2f0783913677dcb5e07dc9ff14df4e729b1abef15bf5eb313fbc5d69f023955c5ef655b2	\\x008000039bc110b11e71f9c6fa30a042f56ee076c704a73699cdfb16e7b1caf5497aafa6ffead24e6f0ad73ce8bd3c9cdd782e0c60b02178ac4dd8cdaf2bddfefb922094dab2b5d401271e1f72b420ba23f93939a2967273e6475401a3d1a26e2def2fdb0158188e4e2fcc1db3d475dd2d8e812b4a73922a694153d7722be1c8e1b82f89010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xed46436bc1007897060a3b2ef79afaa51b84227f464f8d2e96e0f9cef7c76d6ba0365720906f2a8908b95b6760cac9296f15ac85227906b419e9336373366007	1622019260000000	1622624060000000	1685696060000000	1780304060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	134
\\x3229b15f113e464d8b1053e5dcd5e5cf9c85fbade108f09fc597d172b4d685880253424ab403406f6e6dbdf3108d0d49923a6d08d8b8e0fb331d6ec5cb950ef9	\\x00800003d7d3d7c9bd518e3c307f5d5121262deaa75ded986b391d7317c164a5e069c57c1df8afc4140b06a82e79dcc880a00fca63d29e38721c81d7003a42559e632283adac82c58912b2d396aae68e671ddeed3726f412673a160c905bfd61f5c87c5ab4bc8b74bbe4333fb7e7b436c398d194a602d3e092f60f78f7ca702491b204af010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x511aafa5d1959439aeaa101c1c0f76d6c502ec715a027496b5d8b7234259972eebf1dd6a6dac8ff63baea91ee46fa5473a7034d953524d5518707d8f13f23007	1616578760000000	1617183560000000	1680255560000000	1774863560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	135
\\x33358598dd5bfa2941021fdce457b9cb883e8d2b6dfbdaad1e69afb3d19d708fb9084dddd8bd2569f5eb6a847b7deb0e924fae5ccf2ead097f0251ba0f126e5a	\\x00800003b5e05027aed6a4c4be50906ee247647209889021b2df276a496ef5b3dfce0a7eb4bc082edbcfc15a50f86d124a8c861f74b94a6836b3c518770578ef41fd25f5147717ddee84aa8088fee8eb2390a0d9327537a503a95187e8b6886c98f61542fa409551fe6f3dd6b61a8baf3be0e734c66f980c01944191354c5f7c6f21dc1b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x937fe9a19cfb8e63d2cf3ba7a5462b7a01d676d94a49008bfbbc2a5872ffa1fcd6ed1672879f2bc64d1bf10880fbf00aad3dc497c4128bef8653a74194ad8d08	1629273260000000	1629878060000000	1692950060000000	1787558060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	136
\\x344d4bc74c3684fd6c23ffc39b52ed3f597ba838a3ba4ad88c5298f9dab8fbff67b108881f7320698dbda2476013fa8eaa3da8e5e263137b132031042cd7d916	\\x00800003c945dda7743a5fbf2b9598d3092f88dc32e7da61b439772c8a31a62307fe73335301da0104f28221a28ccfb7d24fcecc5e19a7ce6937e1e5ca7cb5a75b4014240bb051c713ef479e97e97836b21b9673d81e23812295619b2e33361d701cd4482c1372cbcc840836eedb9e05aef7a2df55073c5eb80d48e9f6e801a93c231301010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x860278d788e2340a2ac969f7e2bf689d87b1c201da15cd0f0859fece5dca444e409e556f90d5e4613fc5879b5375843833b94e9686104b5eb1e983b51e9c2006	1640154260000000	1640759060000000	1703831060000000	1798439060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	137
\\x36e1eb3f970ffda6c90094fb5223591f2ef58c3c03da543a82b34d565134b28bdbfa06f0279602dd8d6d84fed0ff80032159a5ccbc56cba271839b1e5b879490	\\x00800003ddeb78c4290549efe156da76450d49c80e612c39a2758f7e119d24c82f040c1c8070de42fba93931ec0c1e96e161bd3aa3297ceb4ac745e3864ca7b97568f55dd059ab1b3faddaf648729a3b89169e9055573c7b106c57407b4bb7e85df2f80a0db28c2fddd4955ae114ceacc94e558684792485bab7b3eb2f33782f41d3aaf1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x306c65682d9ad5b78e95bebe5763b58c4a8eac20d56d7db92d9fa153681f8377478d1c11ea9a4d5d421c6c2bcca6f6142578aa86940b6009121f260f126d780f	1633504760000000	1634109560000000	1697181560000000	1791789560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	138
\\x37f1870ad2c8c6dbe26588633fc6c36fdd7aa04a1b4faf807cabe08d162e5c0afe886256b57159730f5bf0ca008a37156f1a1c0648e431eb7182631588c0e237	\\x00800003bc0429fe6050dec5a69e813ded8e619ee94b776df3a74fd3d7390decde8fe2b8f2272a96549c7cc0a18fb46964ae1b467af9660770b62deb55abe6897384ad78b9ac11f1c4fea2da51a170142176fc75bfb93d7bc626212f8cc4f9bffd98710c3573ff89dea1efb9f11f20bdf5a91a496a4dc101f9641ce38d6975b11c5a491d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbe0bb787f50328f55c4355600392922876eb832e3a404f76e0faa7dfe27c395f80b95d74caab50486cf5fac3d0e264e3a0f9b16a2df443481e8261df6c15590e	1634713760000000	1635318560000000	1698390560000000	1792998560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	139
\\x384dce528853053bbd97f2a40194af5b32b1398f4a6ccb001e47d7c4d2e6e05c5f8dabfbb6a5e8f270ad6b088b507d7d57e6d8befbfe05fab28b63a15c91be3f	\\x00800003d13cc5850b4186ca19f099742cce89952dde0964332e07439fe689cc83cddb7b248603e391d189007ec7b7dde43d237ede1975f29094529c397f247405da527c295341ff7b9ecc318e5cffaafdf56111a0bf29d76cd44a2881edaab2271c7c9c784723e526f5775b81cb9f984fa600da0ef26586429e89fa202bc846519f751b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6685ba65a4ead7e5f63a8ef4de56942c0437749a74700153f9b68206121b2168fced2ac69600277c09d05cb07aab7b9eaaa6d4705d31083d79acec8213da7309	1634713760000000	1635318560000000	1698390560000000	1792998560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	140
\\x38f9d98dd2c85d50f59f8f45f8369ab245190d1ce7f125e627bf79a40d007d19660734d63ff4aec8916d96a9a80a5a7c1c1e48512a094453ce34f56342555686	\\x008000039f98a4ef22bfa10978f44063221cef2b7ccad23adeed91a1c0173736d1dc19c87a787c3e059820b46ce078cc6f90534f50a90420bf10632e55645ec16815c48513577c7e07473900b86e9b1605927e310aafac440966b81b01254d2d5d3d3053010ce14b72e5126f7eab5486bd8be4d4442fea4a027eca9e110d02ecf283ae35010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfcfdef33d19dd45e8fc0794d4c446279cfadf45d9231315d0c22dcd88897597bbdc1beec6b62b1924e59e7d3da432de902ce74b5e47583123a5d4403386f4d07	1619601260000000	1620206060000000	1683278060000000	1777886060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	141
\\x3ab5cd0b8fa2e53f327bf2cd451e38aaefe4564396edee4024cffb08ee2d0d4995009d912ed219615d7ec6d6ec092f176677c4851bc7e8a0c04507d45c7bab85	\\x00800003b656e0e1561d2631c332f09361b8feb95ced5715f7efc2ddbbf3fcb91be5c04ccf1c916dea25b088c7ed5ad991840b2738e29782a994bbf014ce51359f6c6d199102670e738816ac5bf4d7835ec96132134f78d79032112045cd5526fe8b864bda7afdaef340432c07e8c92a4819596f3b2144bed540919ac35985a0686c1437010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7c14dc5c37a7394db33134117b604254907a494bb7e87527363952bddc171cfd5e6ec2749cec0458327de63cf5f3d17c1b97ce4f20685ef123ae7d2400a70601	1634109260000000	1634714060000000	1697786060000000	1792394060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	142
\\x3a814b972d29f180dd23238441ebf806d97801e529eb8685eb5e9a5ef0e56a8b9727c8efb7a15a60518657a59ed98984299347842d1f516ab0d3cfe2c852b051	\\x00800003aa3826336d794499333ea2927f03822d65cbfc8403a333afc514fe4cae3ce077cf58287536b1b022cbee6701126858b248953a9b9c97292f4f74128fa7ffd1c363bd921e907786f1f3b6fe1791096fcfb70f6c6f6486a3916421ab3381b37b7fa743365ea098af20e177309899593e5245a109d569be437ad6595ec3ec006bd1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe80849c643be855c080443ab90948d6726b7632411006a0b9719963f7d664e643dc04226dd1b376487e5ab77f108a3c4c348bb3d439e5dc8ae3eb4f1049a2309	1621414760000000	1622019560000000	1685091560000000	1779699560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x3c651ed012a79239d035bd1fa75d7eae04042ec309e999fc25c3f9463aee65c6fdede3d1e1d178a2947792e19849fd2b377871d4fa006ce2c3580b3621c97eb0	\\x00800003e669906417adcdc622c414dbd7248a4455b2c4bcb25d703c9ebcd1f2980684b57510eda9d421c0a3282d5ba210d17d49d03931c07cb9adc65f021e8e7648a70719d2a6a14d44a04e556a5f0ec0ee6aba043ccaba4f56c367bdae4890cde670abe95ee30f78f373833af414b1f2d35f4ad2e13388b04469ce8b1388ccb1f42989010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd28883feb4817ac8fdcd7582cd331f5d30f4d1321df1c0b9c4c16f499d13de050301cf6583e3a613f4a74ebca086e02ea4d5df1387269fde568ec5cebfec1a03	1629273260000000	1629878060000000	1692950060000000	1787558060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	144
\\x3df58d16baf191641157e059da56a0c1461f2d87d23605c9afbf1dc033d4fe1c697f22488c19124e3809e481538ecc63fc703dc2873ce52eb0ff7bed62bbdc8c	\\x00800003bd7014cdadc63d3e887acf44debe4eaf6f7842081c25111db6acb8ec3238bd9ec7cb53ea08e7a8e52e9554cc29a67fc8de767e2693fbba59305cae7a00baede8eff6de75dc84f842cff35d7e4ef7bd6fa71d3920e2a01efabcb85f55ddc58ffd15036274e8d11589716f2d32482b7fde9f3cdb0fe1c1efaf22a5f3a588068cc9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf85a3ee95f8a6f66535830ba4d3782028f65190268bea63bcb5396419bf772c894aedf08844c1a55e73fe1c48fe8808b65c9377047a1cc9582b025b17028150a	1620205760000000	1620810560000000	1683882560000000	1778490560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x3df9770b94fc433b28d1276870e42e5bb5a7b3bf3b8259c9665858573fd31cfd1993fa26532f2e22a1ec943e0c1861c8e26aa0e25491725e2ba2abbd6b3a64aa	\\x00800003d6b16815e4e449f4a9ef7bb42fe2597d2453f7981d516ad2dc9aa3a33fb203b11b7d74d11710d00a5883ad3793d51651434a17a9909ccbcb760770d4dc6362c24cdd172b0f2a7cc1ad645b5a82581d51c9e4c91c38b1e29ababcbef886f6aa5b22c695368909044a749e6d10203539f8ce242ab7dd7bc1ca0232e87c07fb1e13010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x863c8da8ab7cbfecf8ec3f98f4acfb8383495d62922403ab83a9c3de6a599864af7049b493fc830bc50302d9a6b6b7e50ca2b7f8d6af604e0e6999894cfd3d02	1640154260000000	1640759060000000	1703831060000000	1798439060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	146
\\x3e71344441c5beefc7e972959ed735f9d68e0af21dd0f5984ef2ad38f49920e725e132574ee718a9681b939d72d8e5e643d4869e4e7e9c4899c94a20be1ad794	\\x00800003c4bb46988e05eddb0a9558584a189146d98fc5283caa5eaac8e2898715f8f0b0c724a4d47cabf848970eb72d5921dca0f92d492000b45d4e8395c53deeb3d5f0a7e37037136fe23164ea91ad97ea9f050f441149ca881836d2ea3a340395b1c952f3ee70e172772be55efed5ee7b3ce29488f9e8237bedd53dc84abc94f0ecdd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8b64c671403a424726beb9e69825230fc36483cae8299ff61eed68de1edff9e4747d1eed0e7ac8ee449061825e3fa7a843db64493b514bb20bab385314e7ac0d	1631086760000000	1631691560000000	1694763560000000	1789371560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	147
\\x3e0db82f7954f39dfd366de4f7f8f9d5622bc1890b039e39d9c8195ca9b5f9a77c65ed3f4851e56668334d6971bec1f95b288df115ab399afe0fb7259a96f47b	\\x00800003e527d678a8f757bfc848c8b9f91da537191fc861ff4d49dbc0d4b310ac434eaf41d40fe25a6ba723033779d2190ee3028096b70a47569d96eb17a0e6a7711c8700b2ffccf5df9f235712ef95bc556cf3c7678150403eeb1f1a415d665841e725524ecef8a7f9aadd61887b292d93286c5d4276c5cd601fce64251b21ea6c4b73010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x16358a5ae913e54d0422cd92a55c5aa42f2f082d3b9009c765ce51ce9f3a9dde067d3b4c99dc5f5e2b2bdb4ac5bdfa4f9255b47f089651d28eb423571d57420e	1631691260000000	1632296060000000	1695368060000000	1789976060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	148
\\x408d97c9408ce8e7589aadfed9f03f246f87e9327fbc1d0482b983f3622feef2c076a5ff824867108aca28088794f0e6a1b76c494526d023cd28f10ed69f87cc	\\x00800003abe20f5d3cd6d7254304319cdc2b233b9154267913acf0aa91387509028820ba36e1a72b81b6dcce5cb151a3279f1fb4eb53ddef113b244f6eb3480c6da2eb6f900c5adfe447afbfa0f63698ed757add427d7223151a538c4f62c026ed4aeaa425335fc560e015c73f4ec37a6dca507fa6fe71f80b9568a8de9cd2734761d953010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd5c12b54d077b42d9b10f61ceb584237247c8b268baa3b5107cddeb5d135c839b2315812975f88a2de9e6ea957d5efd746ab9169287cb5d3940fd266db3ab207	1623228260000000	1623833060000000	1686905060000000	1781513060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	149
\\x46cd7a5a8186f15811d08ded7b48ae682a5d18e0d3708590b891f151d3edd941ca9eaacd11d555236c456a7f1d4a3dc558da85c2211601653b92f7f4e6900801	\\x00800003e5473819d7684360cb337ac0abe05eabc2dca07c97c92811746ad3f5f95bda8aecaef3acc081f298fe06ba1103733e72862fcbaf66f8f04d3432e2de339f050102a5fd1ee741db8c23451798ca318b562522995edde2b4ba6c1737a8346786601e7ac6764237f6cca869133c72f2ac82211d5959a79ec1bc5dc1c276255e6ec7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x11b47a7d4e0e39d89f918cdfc068d3c9611a54fb66a7c4c3d318908f0bc3b56013cb348647f41a9536d8f2f15be7f52df36b6b6542fce6a1285245ed5744df0a	1620205760000000	1620810560000000	1683882560000000	1778490560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x47794359e511d8f2ed98a3c81c0199851bba0d24be3e310a8c101029d1fdf36bd15a844e42f6812e87b2068f9a4d3656dd26531eb3aaaa12dcbfb7ce46e983e3	\\x00800003dbe27bc35413515f82ef95e57dff04a264ce1bdd8f75d4bbc73f4c1dbf39d801d6a8677dce23e257e86e0a21a516a3f195b33de0337bc098ffe18ab5280b96bc213c3e845a212921b1a7ab81da19a52efac19f4e58782b0c81f1b0e91cd4741e076bf4ede973bf00065818d6d5c52c1d051a4c2411766fd55b1a07b28c225c23010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd818445265453ed22797ecf58b1d81d69d3f4dc4ceb5484e1e7956e7bb96c73d3d26e6ff81d09f5fba485f407a0fa788e8423fedb629f0bbc1c6a4d541bd2205	1618392260000000	1618997060000000	1682069060000000	1776677060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	151
\\x47a564b85d6e5271131d5a9181427bcd58f404be2a60885ca1901b96aa9c67e51e04249e13ac15e940d3d3be19939242ccb44205dab8cd5920723313536bc6eb	\\x00800003ba0db640a63df93bfb77010b36430e7b4c073984580f084d98a8c6f89e0f4e9bf0d72ea25f4b5f49be44f581f90c01826dee4c6af6ac0a34d26c50233ab75b4e9ae392a081487573cf1c8b5f4e8ff847caa562e0adb1def23bb2dd950a6a49cead0e3d2b35a7cd7a1a73027e3d82fad11b8e9c9960ecc32df92030082f1eff21010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7ab141f434d6a6cc17e9a5658f43c5b7c462f7f9c0b5a2e87e1a6fa007bba3b3dfd055651cb505832c6233204cbbb2fdc3627ca5caffee0bcda7bc8d30a7ef02	1612347260000000	1612952060000000	1676024060000000	1770632060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	152
\\x4c8d65d4906ac5751202b2bc10848cdfa03eef1c99503b0d54b347043f99071b5fe2a517921834f547414e9bfab101c2e751f863514819e6a815ee59439f0f36	\\x00800003a4eee83d57c2217648a2ec66db075a3bebcd6e3dcf6abcb6cb70ae00e8fa4b0880c92ee4c66103c36b0e997e29b88c8eaa2e4e923610381a85384b7916769d66cd468d5cea67a2473774322b620a206ba026c12de6e5395b333d5cf04a9c2482232ebf7f612d72a0d860e130cb7c6e21c47180cc63c867eb6d3514adb0787c99010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf1ed4538aba650fa6c81518e40f4db8ee25bb537f45c882084d05b3c190d50ad478da5359f65ca0d085df98b43e6178f7ae974487c859ea988c2deaa9667e908	1626250760000000	1626855560000000	1689927560000000	1784535560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	153
\\x4c39d67368c2f1ae37d5ef08c3dd9697eb7d452fbc567fdfec77a01d265f3e1c77d8390d008aa608cce1c7df7fd9b3d96335f8b268f498b53b87a43d4ff03dae	\\x00800003bea03c2158a297042c9f70d2dff1cfc340205907a0ac630b3b497c3e18e8c2f03d419cf52f48c7d32bb53542179f07e51b76d899f72473acc16929ad20062750954bbb2affeff9462aec419e2dcd24f09b25a80c40b2814352ca1dea9a26c6e1d6eb4d3f979ab5bdb2bcbc756f87b5baa13dcae049a7ca01d2b80cfed3e7cf5f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x50d2c9f87f5aa5fd962d5500a68da7903d44f35dfb8e85e774958073a439d45c4936033f0271fa21ec2fac716f7f86069a836919f351d1af7e7bc5f3b32b580b	1630482260000000	1631087060000000	1694159060000000	1788767060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	154
\\x4f0dba382fd52bc5b0afd5324312bbba21b6d53a37c64f51191d3a49f17aad1360c67f9d8e8bf5db7123c4015406e26b7c97a7695e41d1303d7008040bf75690	\\x00800003ea32cc12dcc6a71614fb5160052999c5e7b8c95e252c703e23721064ea704c675d3f61f67bd34ff023ddf8785fcc8583717ac8390af161a36611df411cbda7df99146b42dea73dda182333575cd76bc6afd812c699511729932c6144a7e39fe0b79ba80d52d6ff0f7ffa4ab952062e9c8e8179d8e76ba42ccddbf8f20f232d83010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x106cb35cc7de2a0c17fadd6ab39378e06e4275bee0430fd7229901b55b035999f52955953eab654c2e6a75a5102b2cccade3a5a1c0c98f3cef9bc5c7b7c0ad0d	1632900260000000	1633505060000000	1696577060000000	1791185060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	155
\\x56c53221adc3e7af1286e24557a130012680ab19d176a2a29c8b5898662b8700e876132858acd52d00823a08cc0b574d9b238dc2937dee8c5a4e3af8082bbc68	\\x00800003b51e4b4d1ef6ad86f92d01f3b86f5b072495e202b01674455514fa7c6e089f8050b116429b2853a9b158d7cf1cb0fea65e10d24feae31e4b988775feb77457bd7cb8147b236df54ab244e2924a6fdeb6326255c58e024f9a642c69f2a65c6340865bfc8bbf34953a7781289029a051c166253853d2795762ae99a4c9e2094355010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x23abf9366f597efddaf23054166d1af00d2e1c96314ca2d347731d3791ab2174ee26f0db1e59435d745818687de9fe6dda5032c7278ece81bd6f9cdff3050e0c	1639549760000000	1640154560000000	1703226560000000	1797834560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	156
\\x56a57718ec2ae7c697d4d9f2fc84e12504eafc6730c890c644008d889e8e20ebc165caba694ef8e253d15b365b3944de68129961aadff8e586ed627a1a7e9dbe	\\x00800003d614d8692d9c10bb6eda03cc364b3813458d73ff587dc626053fc46ea1d0fa3324e49fad27d143c8bca9784bc14ee83e4a33fbac95c4d7090d801f79bc00ff94e1f19a0eaf91fe034ada5f86d28a0801d848e990703f9af4bc443ac676b02016b7ef506fff7801c03c307d805ed424721b2ccc61a8e85a421892e9cf9ddbd239010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x19872c0b55aff8c12dea963f2d3e832890c88eda8255a28f1e5a660b79a1e38d217ab2b2dd46fa9ce8864508c9bec514cf02e0763b1bf097a22007107b530f09	1638945260000000	1639550060000000	1702622060000000	1797230060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x5851476cc7a83e033405ee5604948528e6eb57c11c09b5e8af6273a6510d9a0082796c1cc53d65ac5c3c0ec7f11818f9d49371662916c2ddced875199086c852	\\x00800003bf06071ae013ddfb08d85ff18e0c640a5e3b7b67df2c334b55e0f1fea7da9a7f8a8e1dd7789674747c1d78bec6d2c3543972fcb699133b72c68fa40c63ef4e94e8ee542a9905fa5178565cfc1ae843d39e7325e658ac3a75cae4118d9666a9419048c27d86f06fbbb7f02aa80ab749c74edf9f3599c307dc189546d1028e26c7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xac8a73a1b82c5f059b75daacad773b98b543ed17f163aa6c9364aab3bb932caec6e1f5baccf7887668b2874c4a8f3df328cf0ad37b73c01182ace1be60893a02	1640758760000000	1641363560000000	1704435560000000	1799043560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	158
\\x5a51c2264a274c28d13d04dd90ed7467aaeb41a9a46aee952772b3ab329e17fecf1e7ea8d7241a205de005bcb637b38a0917ad1c28c15877f2435de66f781ebb	\\x00800003e0b41652ebc677336ec9bf16ae7746d55ea4c0b72249a1361aec9ec0adc4d8745394cc15cb1ab0b61bcb984b0df757b024bc64ea062c8eb0e63e3116719c47009ee08b3f23db2ff0c2faf48c7bd35a8131cbdf4a94cb0727d697c0beb418819ccacef61c5d8846dcb6a92cf39f1c1a7555300ff14edb493d902c505be48e0d11010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xac5f0fa353b0a92a3debd877dd6f5123ed5285481f8a873b60a95ce1a2d3ad9ae3b144b9558adfa87374e3503f1d50b86bd29f45adbb9e38a6a76fb3a8f02d0a	1620205760000000	1620810560000000	1683882560000000	1778490560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	159
\\x5a8d3b53374840358b58e4ea3423e524c4f779e499cf374797aa9f656dbb0b8067025bab21808a7889ba2460b9bd049cc32a9071fc483b37c85e3efe7efb1263	\\x00800003c51ad825b8d34c77dc487290179306300b5b54952e16786593e27d3f4bca30436bd96c4c9b8f6fab8c9a40fb77ce78509db9332cc763a80c82d70fb91e10c8d25be9fa944b0ce91ab5a13ef0caf2dbf8b6f3694dad530b3453c87f2da4fdda74fa2e0ea2947c235699606c1a581093f5a8238aaf73b5d0bde9bed295a3b6e203010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9ce905aed20827d6be76dac4013b838b9df1f750ae50f06756a996548720f473312a38f79b0ecedd7c9d3b58daa4b412d3a28377d49f0ff35d3198ce7dc22402	1609929260000000	1610534060000000	1673606060000000	1768214060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	160
\\x603dad7278fca91c75782fb70496981977897716f30ffcb7a71d26504812f95549df764258cc466fe8b8f009660f47c7b6bf2fdd4b7be4acd82155ddff4e375b	\\x00800003c3ffd8a79c140f02ca8e7c9f2af95403008657785a214b1fb801f403de0076d5ea0c5f6e3621176f3dc523ff84c35ce89db5bef8a328468956f0de33626d4641c43bcbb28263a7ba2522c262c1b3dab07f92de9af3ba26f43e82348863244fad24e7efba4c1694f02177fa0eaca7ba4bfd710e4e677aaa454f5ba745e1222f5d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5812bdf6eb462b1208d0c660a9206b77fc26da5d94cc16f4b1814f114a71445ec068bda2dbcfe8be28faa2b199734fc3f74aa67b8fd949fdd3cdc528c0917b0a	1635922760000000	1636527560000000	1699599560000000	1794207560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	161
\\x65f92954ccd9d291f1da136a4382ff6df621bbb6fa9cb3e521db9d1b4ee998d72294f74ab13e5c10ba7a1fbabc2cef04f2616c6e6e687cc7f5c2b15388387900	\\x00800003dd72cbb0c0798a6bb871aa43d975626a2f8f6489c2a0510220acc5caf99918a470cde38c95a810512cfd3e734cbcfdc18b833cd527066356bbb4b9903200fb7b79d5487c15e97dd1057b9e5105c84d16e92b512f53ff7364be273ac005deb605fd2e60c4db5fa69f196cfea52ac3a2e59af439a79ec6f1c1e232946ca651a737010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc49c9cc5b82be563d5bb41b8288f6e5ce3eca444c076b480a0c44854b062997909cbc7db2e283df2ccb0086e9448a05748fbed514135ab5708c1b7dcfe9dff03	1636527260000000	1637132060000000	1700204060000000	1794812060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x65f164a705fe0c274560e523aebd217530dd27d9e50249d4d5134ad3564a9fb6ad65c39e77179961c695fa80d3c5cbedf463527be085b1abce8f9026bcba41e7	\\x00800003bd595cd1f69bfaf2d85cfd845879dbd39447db3c632069a342ed3a00e8929111b1c628a9c870811abce0ed26a9c53b9ded0c1160d8a0dd958958daa75c89df76c0367423527b1a0f766fdf471a5a619adb639468939a921826929bfba93d1927dbefa8872aea8ea09307971c86931653512ab4f8e08f3d96365198bee0f63c69010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x440f2863bc6c6f8f1388fe242637a3ece543a3b993a11a169abe8e4cc0c7666273f397b119748678a63f2e3bf23975609dc21f555840cf861cb80f24de596b03	1612951760000000	1613556560000000	1676628560000000	1771236560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	163
\\x69a13049b2c90c298d696eeeb7017974c7126c549dc94f60d8b1d8d6ff5d96c4d05c6c473580016078426b360156830d865d8784998c329289d56ef6bf74791e	\\x00800003cac09f116ff4b0ee436b03ecbfc9703b351770a813fced10a87989b6f2a71e9b6f79c0e6f87b7b781639535e8f5e1e5a4364bdf5e8d47e702fe501a510b0cf12cab082f6ea398b574ee42fb8ee78446e698586d446780bd4cb3b81b33d1c42f1898983079baa43bdd8b8cf04246c8a9c5980d0495f414092c4401496e66eb989010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x848ef32fd4ed385f8cd96cc5fe46c8d3e5989e465d0e1d3f877f8452d8626ed88e2c0b8a8f4715b96a7e1348714e27109203aef3d2bafda131cc674d4bdf630b	1614765260000000	1615370060000000	1678442060000000	1773050060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	164
\\x6c59868923f7f4f16d9f45d7166a9c957dadb8d788aed9a7b3b5f9b33146a4b19d79a1d766ab2d41209993fdbd24d0f4ecef25098757e6abfb7c9aef5bee55b4	\\x00800003ec56c98df2a68dcd6274789385eb1f2a747ba4805de067ef002736b10ae1d6d583d04c84047d73fc9d3aae1fd010e8e0f09d7903d18452068a1a1d478a04301d3f8e1711cb833942e559fae10dac1980b2d566fa8ca56cbb7caafe584bc38968c6e0956e9f7e7852bb40245af5963de6645625cdf45133b745f5343b824f3d11010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xabc7d5611684981f9c074aa5214f858d4fc3126c668ab5107b0a2c042a4311fca87b388652c799b2e232228efe00fd52ebdd5b63be6fdeb9a1d90c3c9887ea03	1617183260000000	1617788060000000	1680860060000000	1775468060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	165
\\x71c11045253d8890503b8a39a3a57ce71ea6d5ba9abdcbe79c97c7838820a39da662f0154607110117be93ce5e9ae7f6cfaf2246634ff479f855f9ee6c399b1b	\\x00800003a2ab14b77fc00ef9b9b6385db55d7de2b37ad7b5662046d589959f0a5d6e8508b3ba760347155910ff94cc4ee831ff73bef3dce10ee5b2d0779978aca5cec92a1bc52b28cdd7e797929abdca432d1872818096b0dc64159963c043275e5e0b498caf122d7b0bcdf0c137fe3838c218b2c377aa496f36033b417c131de929e3bf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x837c1bbbd618f9012baa655cf38c6d255dd89bb338cdb453b77c7365e24ce5d96fcd1bf1c7348001114bc613c23f1d1ec696760980239bd633126bdc444e0604	1641363260000000	1641968060000000	1705040060000000	1799648060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x74418af6549eb9d8be89953022e48f13f8d10598430012b5363da6cc99339e0a631372fb8c5ef4b127f8d3d49223763114194b704350849d2fe89281a55af198	\\x00800003b9064686dd93d98191e08e3b498978671a80b60d930aa13be70315a3ae95b1ae094aa53eff01ed1e1d4953c50fd54dfe13495df7c280c7c7c2cd4b9072beaddf9e2ca1f1c855028b1f2ad1066f9479cd6797c3a3bc94908647b0f6f03d1f1d72a04d329cb83136cb2760d233e2ef57e0935596f52f16c5615d6b1ef204f14b8f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x83505c3dff72a1ec48bdeb7410f136f3c1010f9eb2d3ad63201b669621c177ea26f5d1358bfdf6d56f86df39cdc8735a07592910149c6a68976daa65b5dc460a	1629273260000000	1629878060000000	1692950060000000	1787558060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	167
\\x76a981c39a312ebd02450a951c4fe673d2b2089a2f489a41bee62958085b0b2d85513843de8c89fae61e7e68e74139f454587c587ad3225f90eb121734925018	\\x00800003b3401404b03e8df3ee4e6e025ab4d36c99453b441272ead510a6dba6ab682461c9ce31c7146d418140d948a72b936fe505f9acf16b3c40d74b193211bb84923e4461256181d5eaad7fa2d84fe9f40a4434af1f7866b88cc9f5ca0485f2b8f3ac373e2f03c45233e7798264fcc4ce767b8553f3ffb490447084ef818bb0a1ed1f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x040d6e22aaf78bbedaad1cc72ae88f40efb97394e287126e8f143921ba245ded3741272fc5dc11007d29cd0661224b5a0df43ca26c2cf481fc11b1ec67ed7f0e	1638340760000000	1638945560000000	1702017560000000	1796625560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	168
\\x7ae571323fb7b631f99a25216e8641e01b6c3f328dda9228c71d8631996f8ceb912175f0cdc1c56f03ecf4783490fb64f55ce7401c12b8589cff242863129e65	\\x00800003caae3f2761cbd7a07dd06b67171ded622cab220cd5e6b6422b1dbaf3a7e626610dda94031baa684530342f560af28c54f7dcda486d00760cbb011eb61abbb26d0bf0dcb5dc6089bf23d35964414fb63aaa6565d28812c474d56365d0304fcd40f218b19914c7582d8b9b9ed65f448f740d1c4b42607719dc294a9299070c8c65010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0b8d497bae843295b151a645235e9841cd40f70b8ce9000a1abf38ba416c110b2e3ab34433866b6e293d91fee894ec5cafb643816414ac54afcf7ba7968df600	1625041760000000	1625646560000000	1688718560000000	1783326560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	169
\\x7a9d277ebcb901c9a23dcb3018fefa57eb09f64efc0b7a30709f21c38e1f1cdf6bb87c3d450492444f63d427848af206a43f2d68011dbf6fbd40b81afdeac018	\\x00800003c8fd62581cc956a113034db366f17766595c4da8bf95d191e6ee60ee95db859574c15b349a2a85de59a1219c54a9d296e62a8e5cbe02de97467dd8eba1e46209c99e869f576c2c9cccbb49a1265bc3946898e04bef889c5c599d3a5b5e21c94371b58683382a777ec27133b08b39b40d139a0df21183827556ea545ee4436d37010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7bbf0d5102217771a06b8ed26d4d71c22f6e4e411082898e72a8244af0a650446831eaac38549ce4a5b410259522adbf8feda22a72ca68cec6c9fdc689544c03	1615369760000000	1615974560000000	1679046560000000	1773654560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	170
\\x7b61ecadac31f0a92850d0c95d1407bb5fb77c35652f5737afe6da654a79db24f819ddc616abf89476001ec5f829e7704668004bb06905e4b85ed22d9436f014	\\x00800003d624ff6e205ce9e46bf219770405e58523dbcfb79f46adec5e990e1ec28301bddce724047f702ca4a406a9cce15eceeb52a75412bfa0aa947823e174829b78415edd8a418febb2cb528aaec52b3064d489e228c588ed4b0641663410920df969ab4103ce8e2e0bf00b8a22e693e7bc3769acb6ffe75c1d523c8902c139e43541010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf2a4dc38a9effc8eced1835072444849d75763866674761729283fae430dc4c77882efa8945948bf882aed1712d5d248b8a912669fb62fee1bc5b6bf31927306	1614765260000000	1615370060000000	1678442060000000	1773050060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\x7c119cf9e402317362ab5218c747546f945c4ec2223ddda952cdc10dc6a9a1afdad7513c69d407ccb9abe1f7021ab6f092e3e332104cd0f549cfbfb6f5c16298	\\x00800003a3d4808e969ecfbb87d2368c47454490069ad7d33402d9e3093e365ec97a6956e4050bee8398a99e814247c5e1fc7edcb25f342e9bc2d0fd7558ac6dd77e9e1c78c433b6548c31f8a8bd813c16eb197bd0c521c85e5fb201ff3ffde8b440e3e88a06cc6a92a412d9554f2748f536a8652c262600204bf1c0d8ca9d678a50c367010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7934111e5ab94b9e0da8d993aab27624a8688d6c411d76eeb7a8e848a8f0caef3b387b2abb8b0bef94cb047ddfa571c8988a4b12af2fc89b096a8e9a803ab404	1632295760000000	1632900560000000	1695972560000000	1790580560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	172
\\x7d79d372a2e5b1c8f9676573dea30e6ba6a1256d2d0c45bbd8165b28b17770ffddf93a433ca483a29d026f662c2e969cd12773fcae720c3ba00f133de799842d	\\x00800003b98dbc43a3b668ffd7fcf61ade6998955b83d9fac2b305e5ec5de543254e5dbc355b2a7a5da17a27278cef661b2619f82a8b8b872ff886b17a2b86fb86bfd6327dd456a79e3729374f206a9b14cb3be80377d6e80130f27d4e57b6fe066f2f8db9c4b9900db09dd3757e7956de2560f36a39646c1f856135446fc3ca2721d22d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x926682620ee96bf257dacba3897ba5626bf20ec3e57e83bd4deb87358f8a62cc83bf98ce32db3a958e97dc99e48408d2cee4a94296c8c068df8893eeed1daa04	1633504760000000	1634109560000000	1697181560000000	1791789560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	173
\\x7f1d94947725a7256f7e684d222f64a33bad28260205e83927578e97e650e657f4948f5e0c97282f573937cb380b896db0ed3288e48998bd89a290c5a4337f2f	\\x00800003c4362db8049c6f4f5ebbc55b9f7dd1beb4f198c6e47647ee488a39c5eef888d5aea804334faa20750c30c7e5d64cf8115323d25c2adcaf035888c41aa0fee4caef7bb5d9ab240b14275e40e7717acc67cd9bf79d8c8aff47778bfd1343700501928acfde78a19b56e2d868dcb9151531fcdf9c6f6482371d74263475a652cc4f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x956d7c6920bbc6b27fd4aa2f5762498d46c1f8ea51303f1bbe8251abd750735eaab6fc0dc81a9302be16853a43c59d4340cdf9aabccf5ea9fc1e4fce6cf89d02	1637131760000000	1637736560000000	1700808560000000	1795416560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	174
\\x7ffdad41511ddab51143e1a78b416ff22803214fb4916fccb9f712cd2daa0e12f438bb854b1ed4bc816f4e42fbfc65b949757748b2bd67cbc5120f05f531036d	\\x00800003a31add3a24843331b5b410d9ae131b6d78e071db0255204598a95b0d4e74b7af40f18fdae0413e63808ce92d40b8a15b86214f6f1488b2fbc5c42ac2a526c5f6efaf8b9f89fc60ebf4380c847717a4a796d5afd090ea3a5b25bb53420cf24bc3c437c44c7b15891f50876ca0531029f220cb66159cf7f73ab6eee110ae38b5c5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x519881255733560797ad91f2ca3c89419118126b8ca41759f5ad369cb5c2148dd21969eeda1fced444d99fa515ebee62bc399821015c3ca0424807ec1fbbc50d	1634109260000000	1634714060000000	1697786060000000	1792394060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	175
\\x8065c37f97865215b31835ff2866b8d149993ce04244c66fe617f6aef84b7fb116a1255f69189fcae8d0a49a99b05cd8af47698bd359e2ed6fdb22015b83eca3	\\x00800003b9f29ef86b5d1fa5a91d1cc15d81f5fbfa78531fd70264dd2baf73e075c368d3091ee21f2bffc37138dfd3e4594c9a3122f8b3137bc955a1286b839dafc26355b0adf6b34f7517d0717bcf95fa9c8021614537b0db2f97b76f932ddfc0127bacbbbd5c33fb6d9072e6bfcb0d0445408a632e592ca112f253a3ffaeccce0e8f7b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xff040c3055ecd7da0508e8aa3e6243b5bf75bc3c9b0ed6d9f5f35cf404251f1e2337e50f3f3c751ba5131a75219d28c7ff3ee0ecf9a52c8f90d19c8cf4dc100b	1632295760000000	1632900560000000	1695972560000000	1790580560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	176
\\x864915345ebff425ca12e9ab5d843f54571957399f833cc6ea04c3a9c04ed8ecada8271d3d3a1c18b567d8f684386c036fddd5683fe70e6e6ba28c52bb3b08cf	\\x0080000394eced1e4882fcefcf0ba02c24036e920b02b690924f824bf21dbee3e0335c6b558e51477ac1b748986c77ab8291c68e069d0cf26d9d7d53b9b79230771fe04558fe5590fa3f164480e6798b29439e7bfa563809d5f5506c22878e3820b2969a62547b7aaee8fedf41ad1efaea7ad787bb9c743852c9d46f008f88a48640bbe3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc9be79d3457394da109447752ae9b9d5f7db83bcf38dc2768337143c47076e0cdee3465e8929d409f6a83de3125a463f83c772636adf4e64b9dd5f1c5c83b906	1611138260000000	1611743060000000	1674815060000000	1769423060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\x8b111bf9333c7fc24b266bf074df084a4b6c0635da65c4a9dbf9e7f3ec32f64c30a15f7c27cc8ade0fdc2c3a8840c85a628febbf673831e3975896d4acb9816d	\\x00800003b63b492d04df20891dbfee86e040f246ca4e7ac47ea64f5e88913ac9180d6c3813bb5f9b3e3f09b397d44474e84c70008e9ed7a7943452d8ae21482fe7b79dda05bf54beff4502572f9d7fd7fac82b75d5ed11de8aa41786c53938a281244a3476b10aae2da29c36eae18ca6d9a0cce5bc37498a423603b0050c9922a62e38c9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x33677888537ff48afb030a992cd2abcc0056e9ce5aaca75ce505e3f65683ebf33c0ffff754b40f68475d05bdc14531b7cbeb6b5ba0c2ac3c0d113f54cb7d9808	1618392260000000	1618997060000000	1682069060000000	1776677060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	178
\\x8b9d43f16cd12385c32b1adb5d102fc9638b3f15ea9c8d32cdb70c7527abc23df133771f64900d316b0ab444eddd7d4080b5924983f22da4f11b12c68cc5869c	\\x00800003b8fdadf8b11f0f0a9abd6f4c7160599b676904ce1e1d3af10218313c7cda149764ff27220139200ded328fbf27401e05924b18de04fb4a06ff3d388b9a3b20ba015264cbf0cd7d09813f64841e2e8225947d270916894611235c43513786fb00e1e386e3c325f823620f871ee12a875155ba81dea8d1b1a1589cea9446d00841010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x09b79c9adef974c3ac8b0b09e470027f4b45228e941fdbc823588fd1b507dd649d78997f502281721b9d97cb141e5f3749ba6f6adae454b96286c0fedbb5940e	1612347260000000	1612952060000000	1676024060000000	1770632060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	179
\\x8c1d5d65d8c632da3f0d55b760a1dea6704630a2f03abb347f2bb4810cb0568ca4fe51577dbf9dc3cd3e7818c20530c447756a780ab5292acfdf61ace26c4cb3	\\x00800003d138345d142c6d8bfcbf912cf9c8ea72581faad5c015c4385ffb7d438bb0d84ed5f041e6f51bcb95bc50f27c053888894ed927cfe66478795001a7406cfc9532ee639fe4c0527cc29725a7817edb18ad399c73eda3ed7be05a31884209f3f0c9ddc271bdc6064e49be08de7b26ba943a06305bb55680c8350b1fe3bee41f29cd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0e13bc72f5978d138074c660895994e29da7e27e889b91ef1714ef0020843d14525a75a25027e6f6033957057e9dda838e79ab8b92cdcb78a311d5d41072fe0a	1641363260000000	1641968060000000	1705040060000000	1799648060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	180
\\x8ca13da1c6c53d767dfc168d4020750c6ea0a1ec0ce8ade0ab2863ccfd830446ba4eda466d0d8cf9f956d2e6d0c88feae7070c2b141592db9b94e78a8feaacf4	\\x00800003bc484fd51ccdd76ff935e2752a1b2d94b479dd1b6af602cf869480e3fd483a9b889ef9fb1fb003aac82586c8e97433e67abbd47e597aa6a4a268611ce6e941b298e48eeb5827f51300a10ed685e1625950c2f902480f6e0c8a8b96e38b7b348cbdc4963cb9ca75565e23ebc2830258356df695924a9028e447266e6cdba4a54f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xebc97671f86d79dc09e60950955a9a038ed948a22a55ee69a9a4f4ce7cee945a66215d8135005f6665523bf1a51794ae2ecac9af00e88cd951b976307a068a07	1611742760000000	1612347560000000	1675419560000000	1770027560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	181
\\x8c694ce3f059c7c5741f6198523caee0559e1b19f0a3668a0740dfefd779d39354808040c80e1fcdaddc48dff3d763cfa791867105703c86a53226e0f0ccf053	\\x00800003d697c633bc64c76909f85edee613a28a2c80cdbac4ffb363250f36a5cc29cf4c887a4f6c8040ea9ec1360700988124afd2b6c037bf38818ff1ce62562f33b42df7b6ec3798d6ec41eb7730898ec9748e6ea97c24a7d41c0d0657e9bbee125339663f89705f89af60ab10bea1bdb711822631e60202e0f27d0e06e0ab5830f1c3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfb718f42e13c818e7df7506b1416036066503f63c0f160f5e51b4b5e5433d27ddb91d2a2f3950a23abf9ffd0e620142d217d2775fc74185545d6b4a92b62e603	1622623760000000	1623228560000000	1686300560000000	1780908560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	182
\\x8de18abe4a0ab1e0aea52e36e3d42522fa37ae47e307230d84347a98480f1845ec29a551da93611247ebb2eb7ad40b4b95c2204b408ad63ea5d80428655055dc	\\x00800003b0ff8a7e9a04d5b0a0e7db05bde28e838ab7708e46e54c020850e63d106f37ed4368185dd6b1d7b51c17c02077f65ada44a451b653ccf379f3ceed00810e6bd493e07b698d4427bbd40cb9f2a3a303d7e98342e40287a6a827a00312d03ab90df19cf6ba83d5282ac38a80c771f0a25e7439cbf30b5f4da29ce39575f8815d1b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5fe781d8dffdbcb96cf7b5d8339a489e72d5c33a29a567323eadc9fca600968a7fe567bf6e366df739e8fabd1a10fec73d6d13a1ebc5c583a7c9cf9ebbe0c000	1624437260000000	1625042060000000	1688114060000000	1782722060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	183
\\x8e75167bfba1d9990a065f17d4750eaf5a4e45363c90c2b8683a6bf6a62fbd07c389789e6bf19b707a672b6a223f754de9878a79452f26c81289af8200af8eb2	\\x00800003e96c6187703431e2eae7c3b2a4565cd56f37399f337c25768364ad0aa6a3250ab118a0e64d2d5eea3e23eaea3ec822a76185cd35e27491215e7adfdb101ea88fc46ef7c56e2abadcf55a8931fd735acee7943cb4244611f1946e9d4621107952a0960f5dec1245cbf132b6581ace58e13f75f91681766f9facea5cef388c9f0b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe12fd9d46d2ca4a0564be92ef377799327ed6b8e4f9bee8af0ef9626592630eac764676b082197a25d1d7a4d9adcfcab2285f4320f04f47893c817607c058902	1620205760000000	1620810560000000	1683882560000000	1778490560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	184
\\x8fc1ece17ce9d002c6dba633c1c1e8f136ae7392c6fd5376d1c2838be54228a27a77925713c7450e0d6435a40818536367c0c8e6d3472b2c02ab7e888aad078b	\\x00800003bbfc6cb3bad662a10d83a080ca1e8048f871b45a380fb899b88de09d3bb9428b648e86b2266607db2dad99b3cf662dc077daeca1aeb384e60ccd187b3d133a8155af506045cf2ae806c60878ece1ffda89025c3f56584e00f965678c918b91f2ed189a01724d17d47aab86d1f7812b25cd039c53e0356b729245fab6af5d906d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9e74104ab67f94ebba02b94f9225bbd435c0257e031a0311975b2012201606770749e82d6fc5d3e3a349c168ce53c3f0601243fd33dd34abd70284ef6db56e02	1636527260000000	1637132060000000	1700204060000000	1794812060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	185
\\x8f51faf4a7eb8320088d14a177ffdbe81f22c756d3f122fa5c1aa79a0645e7f3b774f34afe864f537d552bd9281cc90bceeba66b998b971e385ea8deefe646aa	\\x00800003ce6dc2343c9ac170365ca7a95e386dd4372296872832bd1bebb4cd99d3d1f254155dddaa0719d6b7a38b8fce7184e5a18c373e71723c50ca7c3b2d9c9f7b7a62648b9900d0381afd346d2db30a9701dd72bfb5a4789093076eaf906095d07ab1d0010071d2ef8833747450efd8692f01786754b29db3e9340231d9b0a248b7c1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7ea53919e95a1b7ce402ca321afa5ff7360b504947b4c1612aad7ca52bd91a2d4aaaefbd4e4e1e57fa677bec7ae753c945c1e2bc47846bbe707dedbe974b1f0d	1623832760000000	1624437560000000	1687509560000000	1782117560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	186
\\x906d4fd8f06065dd77eb1c63f75ad757c68cb9d884097927ef6c1a75501b98faf25a4d115c710b1b1df3df33ab6fe139d861f98cf9a9faa9844a2a13df46dd93	\\x00800003dd75a0b5c7690dbe8b57e3acb5da6c9470d8e35d2b86af6e8a9c043cce69768003a8223e6a293d9b3ac422a85573fe59908df0ee76c3b8a7ed8baeaae43ab4d747e34f3f6d7306a34370bc774f21e17aa82f7e1d2bda537d8a34f003cf6daaa263cfac3f2223b7a951b2f504d3b54d7e897a9ef3ba94fdc31518f4e9e9e8af33010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0ee94ca74a9abc1738958f71a2c925c91f5ae85f149cf5ad492cf9eface1e32ca27a0130b65b16d5a626dc51ba00ef7d48e1aa4402e63d4d1baf3edbbf3af102	1623832760000000	1624437560000000	1687509560000000	1782117560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	187
\\x9855c419d9b0d1ffa59914ff67c6bea87ba697dd727eeff32dfb60511290f01aff02b3c38ecb19e4bae300a6dd9ada0899f94a23a777183c17b97acaf8a3c839	\\x00800003b500d666f73725bab48c48034e8f1778eb110a07fe4ceb352f23f5f53ec2a51e59ebe9a5919cd293a6803eee6cb4e9f921ce9b6a7bb382f6a27b8c3727649c73214e4f8e81e5f10a1fe0a29494cda6a08642455db6a84f74ee193d2b5eec74f4946cc9d2981c101e1d68c2aab07019e5d71d60b2cb3e4be0e55618daf4d73d0b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe59b6823117939eefe386923fa45c65be0beefaa4c4e9a34af8ed0d517c16d97c9e3f027380d7a76c76b398b192f305c00a6f94e63bd18828faff700cb7e7900	1612347260000000	1612952060000000	1676024060000000	1770632060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	188
\\x99a9529bcbfe3d4127431f24e1785d98a7f1a01c4ce5c7f947c31b0288049608f8869dab32e0b0d652294364068bc4d876402793dcf110e76a4f552f02ed9c7a	\\x00800003a972cf81015e768e3f1255dbcb0611be64bec340fb55ee25c4df0476307a55497dec83049d0ddccf62484224a7fe7cfdc5b86b46d563571da5f8fde1cefa3fc739ddc975f06310e6150f3088454aa9c96920a2e8207d303f666869d3f83c32fa761b0a06b9a0d6cfb9792666c0a556638211d13b25c85538d0586c38ccfe0b15010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x792f51ea553fe0cf38de1ffb265cf2a5abfe51ea718285382983761ab3db06ee42051eabb4b3fec3b6325783f2e72d6df61e909bd5178ee1b86b984a6c89e206	1611742760000000	1612347560000000	1675419560000000	1770027560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	189
\\x9c551c30807cb4e0dc0aa581e69b8c1177eb61daf9b99b4a910dbc39d850223c4d5bbd9bf1951e2cf273d60535a3140b553cc52a77bfcb910c2d992568f94027	\\x00800003d0e8f93fe4cf45809372965ce48507fb1930c6b4b1adc62fcab96fd758ef44d7506b8e079fcbd8d375de9a6e624bbb9e1e5b5f84e9b156ba553ddce0ad8746d8c55d442537b29cdf4438bf690a6ae26852dc7674af20a77596b986e59d9f5e466136d04dd1bc1113d0be186880b00c8d6472880227f31b6911b065e3e94f58d7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1f8543cc4b0b5339685598f37e5ddb27295b50ef6c6fa09767b90e83c7c892f911364426309c2bf2c13f41e3c6d9ba076e87a6c58068548c1eef7ab3470b8a0f	1626855260000000	1627460060000000	1690532060000000	1785140060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	190
\\x9fc5c6ddbf83601c6e89da6f35e0a31d461fd4cc75963c78fc7fd7a4110bd027a43ae30fe69780689d6fc2f138f067082f32f017a6a57081184d40bf605caa84	\\x00800003b38fec281af79d237bdc3d9945f8632fabb93dc9334b5dd2da357175ff29481e2e8ea1d572c7c0ba4ec652f1d4eabae8d220f3644c50bf3a69002dcdb10aaa4330343bfaa0b9bb94e8d25c37d00f7665474fd78fe6308b4485035b36c096b09c244c55a3050e8d13376d23905e6535e361fc4111b4097151de90ef649139038f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0bdc27154e8445bb6ddd12993a676c440265ea03213205475648a9741cc168ec502742048e8b97e7d7356fee848cf8dcf4f67064e18b98d856b87b54eb10ab03	1624437260000000	1625042060000000	1688114060000000	1782722060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	191
\\xa1b13f8018d510bcdb2bd431dd81766b588abe3b400f9fd8a38c940fa7a92e0117db4b5cefd959511568b467fd0befa737546b274651c2539d12e9f9f66d43a9	\\x00800003a34a1f0223a79e4a6b3dd895dc231945900e8cd8789c2e53189af77a1031f53f903c2dc82096d3033eb259d73fca4ff00cbfaaa43fba29fc77c6fc4240634daa09d04835014c3c7c50b66d923a407871e6353a822766d4643c8bd9b9b371fc97166a9afd07738f68be77f0e4c61c9ca2135a44c9d7b177b867c2b90823a2dd05010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9324cd86678d83702bace07bc28fe85743978295b7550f82603807cac434aedc814b45078641fdbbe61dabc9c5aab1c36d1eb9063f7cc0c47e8bdecbb666f709	1640758760000000	1641363560000000	1704435560000000	1799043560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xa43516d948003cb76392b96e0ec50204e4b5fd1c153d09e456e2fbbf82f5d9024451b86d07bca42c25aec8d6edd94cb3405635825a2f0cdd4d3916af3adb35b6	\\x00800003d6cf55b76f1cffb269084b5e520bb07a5c6035e37205ff591270a0e95e34b59dd44adb2bf9f73f452e9e3339ea22e8cb59e437a78b5d913fc23c1571aadfd5180ea292cd91f951bb7148b440689e0ea6781e492cef5f73c561d13e05cc5c6d449fa3087c6f0f7180f5b9f5bc4483004c8ea99b45d5472f28a8b11bf316e846db010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdb16e14d9b9dc12964c3f3bfe4556b86d707bd02102e5b7e36cb960d7b5225f6312035c11de92eb5b03d2a089b7837505c3b7fed7335582596ce015cc7374205	1614160760000000	1614765560000000	1677837560000000	1772445560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	193
\\xa6e9064d15eae17bc16b7a34cf1b6b31e86cea9d3aedd2b018adbed72eadf7e1596a6a7f7cbadaa8e7aff02007d631eba79e50d5b542bac754e655662a3a36a4	\\x00800003aab65a0fb4bc058ea5b146a84a9740d21cf78cafbce3f07dc48ea0fdf24b7468dafbb6c57d39f0e251e638e29b0a041b39509598a452cc520c1991a9167ea4bd2e4407974643604b99b968307726307f92d6b932e302634631ffbf4c7aee278f15cdfb9d3bfbef8941bf373a1e6435e4dd22a55ff29a7d1b6817efabe928b119010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3dde3492f07c18584514afb62d12324ce4ee5150a6e0350934694905d1167199493c9256e057fcc77f370c220e828e8becb253ced1fb2203d17f00ced970af0a	1617183260000000	1617788060000000	1680860060000000	1775468060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	194
\\xa8c1514ce77956750a3295cc77ff690ed54ae522ad3f5dc2389195b3d830ad9cb3dba6acb19b2e32d89191d7da7cde02238712ccebffce58f8722810445dd6bb	\\x00800003de42c33a74ad8d896997d734f36a74cb9fba3802dd13e54c5eff0134700ea5c6ee88db0faff2613fdd1ebab9c05ef71cdfaf0e52bd1154e72c33d884df84a211dc6b36e462b57fff00993b4075938e111fd2808c573812e9cd0a4a597afc350b4ca66d0843607626c9f4905a25825057912f39622dc495ef0e68b233e5b62955010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x981db99afefaab23b864ba7a2bb52071dde612c54f807defc3a18d2362d0fe687edca8d344e5511d7bbe9724808caacb3154e6ad827b6d0b06765fbdb755a70f	1619601260000000	1620206060000000	1683278060000000	1777886060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	195
\\xa865262b71cf36b7cf3d9f636e6e59ae01644efac9f8b7168249d8cd2c4480bcca047d90fae8eec281facab47f66567ba9f1cebdb6673a953d64285aa03f2909	\\x00800003cca302299c05bafb57fa9baf01bd41d8a044e17b8240a52236851449d9cd1bd8aec515bd5ce98915647dffa20770a33534270e4ae9b73309064692019a11bbc7741d9014487389800f6cdfef0d6ba9ab9adf343f79e086d09ab43c89789eefaa13d017c4a42ee5975c96130cd2f1939a8f08d98fac776cbad73619546fd3b7ef010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6fdb5c583f4545ed95b70a17ae355dad5047e9647aed479af70de8d5854139990cbdca6195f4134bfeb8ab12700ef6f625ab5fc56a596f3265983595da1d5805	1620205760000000	1620810560000000	1683882560000000	1778490560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	196
\\xafd9d48fa08f5e0a4640ef241dce9f443a0d3cbf64932e569f285e52329ed197ce28932bb9f24cc54b3f3acae712e68d00d305861453dbdc8fdeed66374032df	\\x0080000396e3b8981ecaa48c9fbe06bc1edef3dc458444277c83ec5b589673e45a5bff4b13e4a426e20e7a0230d370908b55d4ce8dc993ed566843e3a50b2b32d2175b664ee6c72e19299e6c4a4fe0e3ef3f0a326c817b38e46e818987e17a5bba82673c95e8a095c1308755318cc583f307c4eafd03b84a76751af392346b68e9a9bd73010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0ca863747f54c52481708f242f8cada7abe7033c482439a4e81593497b05081d60417eee045d3b27ad00ace7321c8408ecd5d4a1a078eb35016e994171f7460f	1615974260000000	1616579060000000	1679651060000000	1774259060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	197
\\xb075837a3dbb85190e65dfcbda69d411f91fdb49d8b26a1e8db89cc2db0663a0350b3786e285dca51aed63e90526b9da3e89c203d6fc86fed0071fdcaa6fdbd8	\\x00800003cc395df54e334adca3b2612091ad28b13873d3cae03e6f905712a542c2a3a391ad727760a29a2f0d2b9dd71283c22a029efdc53a5e0d2e928fe819e9ac5320fb586a5e6d544f77f876c6e1c6f9cb7f7bdaa4ebe10a14251df04e23c23e84ce6f4f4976ee46190818ccc7af47f26c436b1c5bc9363cff897680739ae9345f18bb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2739334fed9a3f50a7f7cd6bde95585ef6ee489b41f2703246029d3f0c763d55a61774a5ab44c9e1074f82affa2dfe7109a6a064da92e9a967d5bd2fc3f61e03	1629273260000000	1629878060000000	1692950060000000	1787558060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xb03dca0d83884e78559efbac7086d8eb206f6f39ffef52639ef51c3c60b63b5187f2b80562faffe43609bd4e146996981565375192fa0e7c6732302d4e4b69aa	\\x00800003aeba212f1d659584fc18fedfb0c9a3ef8d2ddb3b3f547b46665379bcbece9ed6830cb34475850b86bd3ccc22fc49fb2ff9d57955228494aa97ff649cee7a6e5f2160a847e09fb576524f8d245f5fba9e69492a2b589aebdd955b8befb628925848f012a68013772741a7944ebb2e863dac8edea6489de16a655de9c3dbf92443010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3ce50ce6770e1f79a4c85da1c143123b937b3e45ed1fa44f0caf119cf84097c720d6ba6c6a434763ef4eb1a3932c4e8967bdeae968df69f621495388cc79c50c	1632295760000000	1632900560000000	1695972560000000	1790580560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	199
\\xb3811bcc0db353a543b3e1d2816d2bfdeb67e68fadf132e4990a9963053fb33067e2c76d639920b73c19b049d5e3fc1ef826a63de46f480f340c64ddfd479bdc	\\x00800003b0b4ad851c8a3bd0baff00d746273b6553b89c5ac08095d1f6857e0857e3592892b71cc8ea4b74f1b3c19a743a170791e3382b241ac346bb83dc786178b32594d8a2bed51b189cb8acd1cd11e300f155729e6adbb5b4151724a23399e66fcbb92673a0d6e07cbbeff0c758f70e02b33aff48c8f42c625b91c4f77020669afa73010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xda936ef5eafe8bf5a542c587b38f21d452f44e1e6f963193f24a097b264e898b93d22089bd42ae60caa0da7c359cff2e29116f17a17c4bbaa2adb3d01eeabb00	1627459760000000	1628064560000000	1691136560000000	1785744560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	200
\\xbaf1b09def16bc6e70c9b0c8ff26e8e35b4fdb0369503fae4781a0113353c8e609a7733b62a69f6ba9455af902443484fa1dd693f2a24ca26744de8edbdfd5d4	\\x00800003c08bbd3df341d5d624a89792fc3fb837b27776a032239f3c9290869e15c6e657c19b96c929383ac34e98ca3f81e56cf95723728767ecb1689342c6d58c2a4f73a5665c3a1eb99777fb98ffd0249fabc3aff9d5b0a5eb1398aea97d28c51bcbbc1ecec770cb0f1e753272a7548561ca8056b7b61f8ebbc4500ac58cab8b9f2995010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7f46531c5e9155aee95899b297affd4caa84b5c85e2400b1e93de72930b8ea7a5ba8bb404664b2ce379eb016ee48fdc24ff025dae9747ff0e51ead9a2404040e	1621414760000000	1622019560000000	1685091560000000	1779699560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	201
\\xc011e5e7c6aaabb5f6a9ecda08d81474c1cbcd1819906a68bf79dfd1ef8b2cd9ab1189cedb167ffa0433c0b65af53e55756f707aed5ed5ca74f68a926aa0fb28	\\x00800003b82d5690f0026372fc9f6f13edf9e37d1d5705bd7cba2dacbe0ddde8c4d569a956f1badb7ab326810e9cdc39f5246283a95de05789faad8663221041a03f917a2ddc97f75a715785f5b6db58c49f2ea6c6c989dac9aa129c8756d69191c4a774481f888763ffc0a3d1475a5b9c79632cc9af7d5c1642b12a7c8d4490b2f9f0a7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xebba67a61a46275941a5a0e298ac7359fe135b8f3b77507548fdeb72d411f45cb4ff02a04af4e735e1b44327b4ac7f60f09856f9269b6a25775628617163380d	1617787760000000	1618392560000000	1681464560000000	1776072560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	202
\\xc251dd5ad8e82534cd9e6199b4fc61ec0ef19a7ca5a9ff7121342e179b44a7ef4c4b32450e7b2928c88589b6856c5b12e6570e7fe7bb8a08e11f8e067c5396bd	\\x008000039b04835dbad8d6a361ab918695dc831b1f8761181da638516b515ff7db1793edade0a8b435450506dd812f2132f469d5c00e5202647b300e77bfc6cdc860670aebb3f21bccf65f5c1d88d3bff5527c25a87c5091b9a50a278d73dde5a34ee7f68e5784a4cf17ab5bdef198758b1114f3f0d72467713237e02bbd5299ef7a8c53010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0354b7bc3ec91124f98961f74d4bd18ea7a4e0dd05f39ec777bf5f9b5c24eed42ad2d44767ef009d04e4305e1577e2389414466d2f0fb0f4d71aba0a20a62206	1638945260000000	1639550060000000	1702622060000000	1797230060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	203
\\xc309e7c764e374deab3a02ffbfbdec6b6f42652f35f2468205cf2ef6e2e916425126adb490d37ea675b968c6e426406465add1ddbbf880f4f3619a069a1cbda9	\\x00800003c6ea1d95f1c41da87a89287bb9caf64d3871813b4a0c9827e8a8f06a0e3df579007b40b087e3d783e0fe141afb7549a0af255663a802b830cce9681f99889e899ccc938df3cf8dba9f42cba11ae126210f10ae14f3b3e0f35981f18715fbb7556e638b7dd620b7d04a5babeed220afaab3aae13cb80b9ac76ed39f6ca7c19ab5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x67da1d5847c2d95b90347dcceba46b8c6d686d8e1cdd0947e0534aa5b2964991eceac2b07ae5b38e6d66752823a2aa208091f5f30ae3dbf77e471271d8f45308	1614765260000000	1615370060000000	1678442060000000	1773050060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	204
\\xc48d8252e1fc5a5593f27e674215f1261ac843a873fa6d622078d747ae75165d25b97825107647d264af9d301f76e0cbd247ca8426e197070794ca24a3192715	\\x00800003bfe86a2662395d9581eb39a951e31a41ec38ce6455512873d2c0c9a0ddc72a445a64cc0c00c8b833d7d505d67fd811e86c928c244c90e180d02a8c884ac2acb098c5ea9fc3181094e974a35a5d4a93778e6c961a76754adc107b84a8935df986c325b2cbe96d5477ecd7b7777309da8ff6df929c3491dd6f96ad4a84ca79e89d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe41a8a116a53dc87082a415096a59626d0898dbe45c16cac2722a3bc950eccfc4483f5ac8c293579f12a0f4d381eb8eb89c45fc1cf4775e3402d6f57d4ae5306	1612951760000000	1613556560000000	1676628560000000	1771236560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	205
\\xc739251757cd4fa1810cadb03356a1b5f92b29c0491643153a0b35ff2806e794cfead7e9379b5c7be62ad8d4cd54d5c6ba580a58ec3e2929caafabe3dd746df2	\\x00800003a28887fc670a154a3f712466882f247570c5707bd299c41b755aafc195773ecdf8acdb65e5b0ad0ad593c8678ce7e66a593461670eb4a8c185a4b3c1206ac3918e6d19d8c9d54ff12bcaf0c9b1e97fcc50c2d4d4a32e146f5b54ff85336df1206b543c6f0f6d1070e882f6d847a9e0406c438b30b6e3365d08fb429175300651010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x774e286afe011f10d09aba41766ed015f77fc5d1144db02de083dc190fdda3ea9953924e68d94f0cd366a35d21aba134bc8b88761c87428fa6236da7c70dd407	1637131760000000	1637736560000000	1700808560000000	1795416560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	206
\\xce01d82ea02e38a9b8e74977a9ba9b3a506bdc7cce18784882d23f6d97c0738c8e44b9fef46284d1fd2b7b3e4418d8f9be223e0fa723d1115addda01ae0487a4	\\x00800003cb921b2f1a7ea5c0682d622894aa6496374832e4cdcb5f41b64ac1c6ee41c92637b9ce48176c865cceade03fafb08cbd0af297234ae6acfdecf057f8c08323618cd145ec18d0604f46af2b762424804f7e657b3703d044c4241c0600d3f6dca02f65f49056bd8537fc553971a55421af6f9a87623137f239b8a55bff1ea15fa3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x247460ddfa432f6d0efbf892f6d4115fc8451d1ef849bc3159ca627621b12646efac9ae785d3b426372b70b733b63842a7af5f59200707f3a89b74bc54558702	1618996760000000	1619601560000000	1682673560000000	1777281560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	207
\\xd0b1ba7fbfad44eff41b7a02af646c1451b66ea7650a1f03d5a7fb91005e6ff8565fa01baac5d46c1c04dfbd98168106271619a106e2bd6193efaa18bf576dac	\\x00800003dd431d3cb02d3141ec477da23e1b9ec306f78aaa50fc7d622e18b4b8e03fe7b90d7a617ce6c3955bf8de33a19ddf86a3c5da78511b1e4e51a224e32b4dea41ba1a4e32d8d020b30b77daf60150ac3211ce7bae7ea3713e831a632e3d52d70f0929180eaf4abae48774fbd00fc4a53ee8148108615498abca2f141b6ff616d059010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3cc7333f39c45b6f965cf325a4f182ea3ab92b1c4218866a0a43d6f5572bad4e790619126bf1dfb988c0af24bc5fa16248608eb1f5c47a232d2f530661202d03	1636527260000000	1637132060000000	1700204060000000	1794812060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\xd06d74d3f75b168a3ec7d4b30d40e4b8218343e2003c20b2a840e2a410d1f7371fe54f921ee1105c5d5a467b1a244151813045d637dd5611c08df36e9b6f4852	\\x00800003e6473beedb80f5d9ab85b0501c7bf56c5568c03bfb47b44f4d6b94741d4ecc30ffcbf15fe4c4fae79f7368b84da6a3831ac14ed00a10df44df0f76c88e22500949a65fc6b26cf9562de74f8a539034dfd56a9db66a6b6b20b946c35d12d5fdf6e2f672e1fa882ee8c8bc78d115fd8faa367cef816523bf662059433ba0763459010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x807dd6c6a3a2c5d0a0425340ab142da066d04345ae8ebe7f576f8c143c71ea11b272a73121dd926947059ff4614c03a5aee11375d92dab00cdf007db35fc450c	1617183260000000	1617788060000000	1680860060000000	1775468060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	209
\\xd5a94b5cc6938082198ca42fb6f0046841d0b0627ce9fa07c426f49d2b28a632f12a6b5a5a9ee4da5ef7e30a58ba01e686da5fa14a78cb485186145b2a8533c3	\\x008000039c70cc640d39801d009fb769f5a529c13d1a40318b002f7dae3eceefc2128c70f24e83aa7cc4f6024c4d8ebbb27950dc60eb5f65ed2e735538ea17cfdde52d85f237955ad77ca2c1228b8072494da1c1d73db4d20d6ca828c26918ffd891a02f7380dfe77a4d337fc873aab17fa8a3bd4676a92e14e248b867046f42cc3a1d57010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6c6281473214cd8fe132c16e41855863e8723223dcd51aa642db6cd16adf347183cdbbd9164720c8da161e97da5d8176c078c38f0a1c9d3ff21b22f5b72d3109	1635922760000000	1636527560000000	1699599560000000	1794207560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	210
\\xd729513319059adf49e5f87b4f26f235ed79c376c8060574d758550a3e85e0c8e1befd5e2e40ed66c6a33767198f4201975b5a1db71d21ccca429da5fb693aed	\\x00800003f4562206f985532ff36f6729d716371b840dc28a6951f828233c13b365661b8141c2f0b211db9dca5861b1365a0d7ded387ffdac15238354fae74fa54d7c60560066a7010dec3ad0247df56c822bb15aa6c0ce392c75588d12cef8adf3b73f42fa8dc65e48104dbab542ef19c70d0ef7a206e86acc1ef4aee6277457be372329010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6148b50b65f63d0f5d9b47926b1d3e2095a29b09d2dc6fd00ecd4f4f6b9760dedbc45198f8b9d04b15e4a83d5025a93051644d6484d1662923cfcb91dc435501	1618392260000000	1618997060000000	1682069060000000	1776677060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	211
\\xd9a57ccd374315a09f732c5991d13ddcbed09c9a78c7a336dfb0483bdcbd47130a865c8757313ded2d39c2a73a0fba6fb8c7fb16be0af400a781639615727efe	\\x00800003a298e7e28060914ee6bb022679995fa1a05b8aab932dd54f7ff253a9d0088fd94d3ca5d94a747c48b5d1bb1a87aff234f9fbdeedef1a0dc4e55e7dff42aecb9c3c7f741826b04ea04b783e5d66af42eadb9ace3da5264e19b02d530efa6db4da9ccefaea24e041dc87820320a4e8332decab64ed1e1017fd598c4b67fd840083010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5813800a7df92e2f9dbb8ac8f19225e440384b7e9a11bf2c1d33936024bf506394ebc70187f8517599d0ac051ad90aedaa4d9d0f3443e4373b0784d55446e50f	1618996760000000	1619601560000000	1682673560000000	1777281560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	212
\\xdaa937bdb49df73424494e985a11ee9c5fdb568455c372d04395ccbf60cb74b1f0f7d9084fddb9c3fa0264bd7c29cd9c37e2242d5ab45826e1194b603e1b57e9	\\x00800003cf6747771ade1c902d5326f55feff529435f721d716b13d9d96f36fb7a3ac968af4960402977af7694c93663b0f33bad1b7ffd4830d8c81b5877849ec6b226ab4cc63eca1e043a8590d9e1a96fe36799f71c32691d178847ba9eca9127fefc9a509ec025bb055d3e9469eaa510dcc5142ed0773e7148a95c8e2250d62306a725010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb58f04c71c32dab18edfc61fb737c16c7c98eed51ff2d4cc9e922ba3fdfe5a9e95cc4e43dee28a1316104197a3a2f1d6bd9771b9f20f7964f17b755f1d513905	1637131760000000	1637736560000000	1700808560000000	1795416560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	213
\\xdb71807b167e4668ee5d3830aa8f255f70a3ea06dd970e1bbfab9435ea1bb52e1ac53d8f381385ad1e3ddc2ca8ffccae3245089a0ce78820164f24c8732082b2	\\x00800003d02e941f802be5d6e1cd295825e1871f6866fc67eb976c93928da9e233bfd0b62082c4c4a89135adddc9899fc20748fa546faecabf58e88adaeea8acc632d59a290450520df7cc458998d8e454e64c37dd97b4b020877feea52cb4953224ce2f0f8e66888e59fd0a735962194d63ee82ebf49d44565fa776d6eff7986c72610d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2ebef939786a8d66111f352a10490b459bb6cd569ffed0238d9bf7da625d26dacf99b235baa44e694984f5fc3942cb44e1feeffad97e5e0ed3bd117cd332fd02	1634109260000000	1634714060000000	1697786060000000	1792394060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	214
\\xdde510bb7ce7b608d9ab1b575c1161174e43c09c4b498f2c82de40d0f05cc2fd3011127197f580516f3e50cb8496ff51725f2bf902253652ba6f9839e007b346	\\x00800003e9d9c402fac9f5b5025bea20023501ae0dd19b8e219ddc4d56f9af467e7d9e6942e6d17d14413985cd1cfdd05cd024713b8c3e6e119d87e945159273187a59624c362a83d40a71fd45811812bb9f1bf6130a418c52cef77bca9321e26c99a95a3a88b98f4ecdf5bad21036b63b78c5d8dc8427ee130c695da41f5f3b780ea7b1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x358c4f738cb7834238723061f0a93040b18ed2bd0a78fdb5e8785edec589cabf6230d10ca181651966b23a9aab87241c5454e08846a73bf8d5b5e5aad7928003	1618392260000000	1618997060000000	1682069060000000	1776677060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	215
\\xdee90fd3817d1bf7169b50491346d614aa1ab52f5951913ff474e67e2cf6b99e72cf3ba02dcd004f25b962c4fa0abf1bff87ed65a72940a03b0f7f5411fae46f	\\x00800003be9477a46dfa95dbfcce900865eb3637b917ce1f65857de329654586ebca9ac8ea3ff33dc8665a55b143d047b886588e1010553fb9087f145899524007eec2348d4ebf7c2ef66204e4c84240942a71b6a2e227ab1a70e074b4a71fe398097db9e7ae78c6e1709c6ce810f5556a707c34533f3e78049c74aa5ec476afa9046165010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfcfe3fd381d546c0df1b7980317d6dc4ecb326df2a4fbeed146a2bd173d3768faa8fe7be17776b246ca1cfa55b4cc8a3f17c926a997ac6028083e0e006bd7104	1638340760000000	1638945560000000	1702017560000000	1796625560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	216
\\xe1cd3bcde37c1f08fcf1ca5fc898eefbd2995b2d27fc765acc3dba99d8944e8802eb62487081fa74b1318638788e8d9076c490dbe979ea76cb71d1610f7776a0	\\x00800003b40d3d0815f974f15b33a800fcdb89afff86879acb111130b433ebf0e0ba2b9f69a76d0dc7d29653232e287e0e91b0b9d0bd45583010a6582229cc7434d718d3ee3fb6e6350aefd9c9a90093ce2fee0f9bc9fc041be51363e8f53f4e1b0368126662b9fcccb8e5b7d8c0241f632acc75c513325aacd639474ca2d4a42633e293010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x96ccccbd7d9dd8ce19e0356044128d67cf888079a3107dada1b5846e1a235fa95b011ff2dd1cfbc9a6bbb279a3d22cf87bffea74eef3974cf10ec51abcd2860b	1625646260000000	1626251060000000	1689323060000000	1783931060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	217
\\xe219552b943456c7deb1e993cb2f69fb0a4e20464dccc97bf8d68faca04833510a92c9aa785ec92d433eac592ea2af9defa2d431359be4ffad09eced7a195ac8	\\x00800003c862ede7ccac7d59d85f49f3ea5ff934120ca534e63d09997cac60f6f17af4528510b75b9380ea6bfa260785c36eaade2ab0b6a769df39a4bf8118d6faa993138da57398af4e0992509ff4779e3f8d63c5c0dc3caa9e77fb1c82fb57402182f27df4179ac334d94447cdb71849a1dffb2b4e28dbb99d3bf2e896884bedbf6109010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8083409360961367487c23c64201b3954c2ff859daddc6cdb7fbeb69665a4933095b175e661828af1a5bd9d6ffe65fb6a48589b9d4fc5f0d98eb74c5fd510c09	1638945260000000	1639550060000000	1702622060000000	1797230060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	218
\\xe4e9d64b4a6f5af3fe92e041f75cdc3b4f6fc57d62eff3f5c9edee216d03f0f58cbdf3b11616e517d896e47a7124622a8ae18acf433297d3e5bfa90c03ecfa06	\\x00800003d35030c409a5220a3e7421be3322466c4f069f6014800e92cc9e0b990d1d6d4de3dd74fdd017b9621c60841997c6167d14bd54797fb936cc5e94f44287129c6e7e5a5f1f34aa490cc498612d0980e3bfbbd76b5c89e8337d5aaa7fb9aaff1a2d1f13bf1a3a1c9be2cf56574ef4b5fff6ae293383196aed656e35f509fd82d84d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x413a874f1f4442b815d418219989f197f54a32dc7009bfdc471aeb9041df886a5af3e2df0c758a9284a2ca5ea509ac04ef829f5959672c980cd20e8605a89a0c	1631086760000000	1631691560000000	1694763560000000	1789371560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	219
\\xf2c524d66466c1876f5519e4642c0f6b9c471a532b96ae985a4652be3fcb948fea692a9619f4ec2bdc94e8e63778c79a2333bb3a8f8e884b83fb9123264da714	\\x00800003eff26208661edc2d82725fc6289b6e993b34368b705d61e23b63cd33ca0406bb2d87908f9b39219a828cd011669b8e73570d699d58d360d230dadd9a87b6beb3bf78f3433ed9ede3383c0d7220952679318ae43fcfa99ff4794f6008e6a514db65dc0a0135ff726a1fb5a7e5f6de83036f0cf7bd34f6c56619c5a593435be505010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x479f5f1392927a2f310b71a4f52ed58e0c722e2cad2242f84392f1ce729621f9dc144076efb9b5c31e76a927eb84ac8d12bf0298ecaf406303973624344f7a00	1631691260000000	1632296060000000	1695368060000000	1789976060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	220
\\xf45dcf05d0ab032387946bb2750ddf30b86c163a7de22dc16193a74a54d0e13d6722794416a25fb65af58b899f70164b7d6860dccf2a76c9670f0db3efb1cd50	\\x00800003a740e955fc913034ae138ece2c28c8cbc12db2f9bb4a78743102df649fe360cb447bff5b2c1d0f32d4fc934a3b5d2ca1a39bfb700b59cf7ab3b801614dfa3a40881dfa924fa391cac51a69de4b633653718d5ded479ad80025305e435c07ac646b341a5f6c23da13c8fce2e8aa6265d493e21762ff1b94542671eb8813745903010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2d183941e825dc0adf98ee80940f2a92dc159844e9042ca9ba3e96754d0010db86bbabad43ea95b1fa2349f3dc8e5ea7d94f79342735ccb2431ae7463c9a330c	1635318260000000	1635923060000000	1698995060000000	1793603060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	221
\\xfa1590e4c7641384736a68a939a29c5fd95caf816b731d5ddf2b2a4462f4a9adeddff8d885f7a134b1c169759d5f601203681acb67083df51c82452aa3f5f72a	\\x00800003cb3ae7b87f2bc9a718e902d929fce41cde69c6cc5e9636f1f57a9ea313863569906c9ee3ed10262338a5af5162b6c0a4288c8485e0c5a0dc82db069c73f967d9410457b6d968831bc4cd66792d2fac17914bd09fd32dd0910e9edf21e6d6aa8ab5f7af35e47df9b0148054c457f9b6b6dc4f1277fdf6b8f0d3df43da496dfc29010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x191c51205fb4dce623755e4c660e74104757520f95cb4f835835fa7ef7f47ea4880fc03908fb2d83a46bf2e4f1ecf5bc1c6eecba7c61243dfd96fb8d034f5009	1617787760000000	1618392560000000	1681464560000000	1776072560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	222
\\xfbcdca9f0738e657aa0196270a85ffe1ef6c4d29f0bf31043ce1085eadc49528b1eb3157c048ed6996e29ec1768eaa9f174e8257d07b90ab137da7e4128f54fb	\\x00800003aded3042d3a402d50cbf3dbc0bd438ea3655d0a3fb254b768ad2f42550e9ded89ff93a3d21e521357dacc19eef46b647e5b5bca692519aff17b8c4f61de999b84de9dcfe8480b5c363a13dfb4926428b44bd7081ff5525ae32ea123e5bc9e86d1270ce317d0ffb6b44c756ba01f3d30a37fddf8be5555e47d673595fd0aee7f3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x35ac794add9f1363a7108256187135c31efab889b1da294663f7300b0357192197602b4d7f97033805381322b0ef3bb901c4fdb0b246f424ef659bbfa385e103	1617787760000000	1618392560000000	1681464560000000	1776072560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	223
\\xfb3d67df686a3bb9f9ba41c927d95d7fc05c44d2a59f6a8c207c4209a746ef4a7e8073a595aec9d9ce61e2067f507f8e3579243d1c13b0e45bfd30dac9a7df06	\\x00800003c016a358c97538bd13e3d34ce53006b73b06dd6e2924afba204bcd8b7abcac1502d74154d3262eb1581a5090a4ab09c97139e16afc8bf666454c6e5b692f7ceb6997d5babb7ca0e22ef5eac909d398658cfaccee423fbf50a9ba28615bbd9a487637a035bdc4b681fc67538b356e3bc6797cdd469c6fdf58cf9f064d8fef249d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1696eafbd3fd9eb03b61bc22d13f47a80dfad2ecd319151b7d379f5bac2f124345836e92b4d2738387c047b40b8993c09c4695797404d658ad34697839a6c90b	1611138260000000	1611743060000000	1674815060000000	1769423060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x0162ac4cd2c7a372e2f1f1b8b8d10d47adef74bae9755a57561f22e79a55c327674663fa52604b258634c96d06f83055b983d2ebb48d615fa960d8c1ebee4de2	\\x00800003d3884d5cc96a866062ad055e943baf236bb2c2b98adb65c0ca682ab6370b3609a1f1367a694b606f5db2d8a764296a920644e6a2ef0ee511dc9ee3fe1ab319b45ce7a847c6003e58b4ce533f1b73cd77b1e85f655337848ee138dc884b061a5c631501405839b6c39bfa2e88cc0413a32709bdd31f3d22af2651ed9bd2ad29d1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9d4f7a0dd3a8d2c4e08674f76c5226f2c802d88b98f64039744d81381ceaddb7533c90c1d8f7deadb417ed13521f6992960d169a857d93ef6fe68ccfc50f960b	1628064260000000	1628669060000000	1691741060000000	1786349060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x022252e12950c914940601191088e31b9b8ebe9afe644abf9302fe4ce65214eec0d5d4982aa5c22644564b5d8729eabd1351d9ca15a080ecf7c0416324e800ec	\\x00800003e72c0d5bf9042209b5c9050a26caa30e59a99c2c148195fb93afe2095cf1387aaa3bacdb3a105b5b3f19a66ae41b122009c9646bf6df73926a2f29f8ef0a515770d2a708db2991f17630bfa56aa5a01a5f65776d567c510990dae7a6510a8b2e65de9495bc1f97f23dc3178bb194a8f7649f8ee75d0ed90907e379cf6573ae35010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x634bec8f4bc77585b0aa880fa1504f2df436f67107e21d8b6cdb528724b99b844c8619126c83cb591a1fc5d2ab10be6b838e9fcacae1f69038fc895703afd80f	1617183260000000	1617788060000000	1680860060000000	1775468060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	226
\\x02e6024e19a7233eaf332428876599819b32c6c9d236af90c92066fbe50198a40a7541b754567bf07e5b890322b1c43a5d1e7f9f4ed7acf364d8eb3b586ef34c	\\x00800003986f1a3f6d194edd023647dc3193b4a7b4ff1a92c7f3c2d7ba3d12ebb5448bc41c5f23656377d2a8e0aaf5941003dd62ba1f12e7b9db3116c01894a19e1b07590ad2357f9dc1f97a683f4532cb918cea1a7e4e6bec57554c9df1802778dc0308528005e4b97bc31b3ba262e50d640607ab8fbdabb6e8196455c639f0b12e9857010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x831cb9b1c0225a6c089ca4e95de37144b3e39ae2fe4ec8d0398f89a9074ad0a3519f7a5aabe0bd9cc2b2695cf5cfa26a2b55b25c923cbdfb8e22505933207209	1631691260000000	1632296060000000	1695368060000000	1789976060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	227
\\x023266dbeaffc1b55a609558f891d6536ca45c0667e8f5a242dfa4120ce1e8a56b649707a2911cfec2a9ccc0b3c0ba144bb3ef806c27502386b2d0f24c4f5faa	\\x00800003bb54193a28488a2eb702a1b63d060cf58d7b893d324b6bd75091d453390c067159996cad4cf99336c233efd4319f79a1c5ca5ed4f6334e07f14252e75f65f9d3111d7d8cc0a4aaae4fea15a83270de8e6b240a43bbc7736b7c5c51a664cf4f9ef806f873f5b2009ffd318fc526ede691323fdecf726b6bd52a8c969f47806b39010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3cb26a8851936eff1f5d2fc98e6e501a27f1581db6f58411b85e5a5a91521f8fc67c4cf60139edebf56a2f78453e72130c9847be1a5c96d602810d71fce42501	1641363260000000	1641968060000000	1705040060000000	1799648060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	228
\\x055223360e64d2882ff1a8eb0d5dcff24a30fa7ce795e42aa930f2bf1638710fe6463c707205c54420a79884ba5130edaf5606b6616436a642475d5a9da812d4	\\x00800003bd0e1c577fa5039dfe9035ea55cd2a22f2af71e47961294449e35cf3ce6551eed38d79c36b0277fbb5a44a06a7268cc92aaedf49cb847b74d35c35626dc2e42ee0417e74a8720e0c244bc6d72ee64ee1d9e9344522cc2c263b0918c4e09146ef0d579518955643c2cef65587a8fbd5b8e467993ab70ba32665dee61df1c02471010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe10c6193356743d627d0a923951521d46d6134b522c33694359e48cbf717edfddc5efe329c1b6394d3abcefde8cfb850dd71c361c30aae9fbaf8f639d05a2d0c	1616578760000000	1617183560000000	1680255560000000	1774863560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	229
\\x054e476357e0db206d5871a29cbf9911afe8cf61ea6ff224fcb6c3c2abee737e18432638bc489a0a7b2ada7901515e6d494edc25b8f12df0217d05ab3e56c971	\\x0080000395c17d69dcb29389d7bc65cefeac5629e07e41c2663aa8e5f5f766f13cb0761b41edbfb5cb8415107ee5d2df9a74e6b455d4217a924f7f563bcd33995a0978756e8748334a43764b744d64ac31b54f02ce4509c2b28193c1c6da9a125d6b1f059b1734a65d256819596a4397fac374b581d6054839aaf1b96722dc0409634eff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x03c0295c10291b069bbc55f00bb66e8994e9718c3669b2cf932736920cce6e32957828712f50fcda667cda8cde3a1d1f5e733f0ce05ed595254f99bdfd4dd20f	1636527260000000	1637132060000000	1700204060000000	1794812060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x0766a9c19fa1c04c5d7286613b990f4259318867dcbb098d1a0d4c42ffee8391a2313ed0f4c323a04b18167cb2a227b78c61eacabc4df92b8953cd027b468686	\\x00800003c5cb952100db297c8bc3d9a44f7f4a8be60d93762877daba370b6ab723a4740ec23363e235a8b51a32403acb284e294eecfcd4fd95dd0df678d1198345412fbfc610212c19c02547d410e2db72b16b1a0dedae2f599ce06b605cdcd1cb24f1fee5419c4636d23782bb02bd5491491ef32ceeb32419fe48596744c7f31e10a6f5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1112490e46424fff419f0e987336308df7184271285ff64bc22b96c8c2c8c87f5524c07dd3e00ed116b8a034213e14db6a4468a5c3b5a7c157d4f7524743ed03	1632900260000000	1633505060000000	1696577060000000	1791185060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	231
\\x09faf89a48779446d9eac44f1c9d90be711f2991f2d9ec78aec49bf63bd5820361b4a1ca857dbb00f9047f088494cb9653a41d50849491c37b01fb1222d4c94f	\\x00800003dd0de296de7ad30d076f21d16fd83c3e5990c274f2e545b19a2f6226da6c9fc66d2e479d2bf3808c6cfa8f1808ff7d1af58a35822c82d8bd6064cbec36aa68197e506c9f188962f1b28194532d60047afeeb4451783ca36cc12e17cbcf9bc5d8bfa1cc549deff1fbec75ce172437db408769e6b1acd1aeeeda7f28ce8728f83f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x892840f2ae236fea0060707db6b73abf39c54d2c66e292c22d072c5ff234f6674a98cba56ac8e7c6d61cb203a1cbdce5a1b2c6e419d8e3a4e56ca03183e24b0c	1627459760000000	1628064560000000	1691136560000000	1785744560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	232
\\x0b92530642b06982c656dbe18ec365435ef8cd4081329c2bb399f224855b53e07bdb4c6d050488d85d259ed2be9a89954e2895641d9c6cfbfc52378fa666d622	\\x00800003b9940152ebb73cada410a2931882e217c96327f0fad24949d3691f20eac683c50b120c8dd183b8b8bed80aa338bc3da1da58be21c8f88399298cec07a7cabfc9cf3255304bb97cb5ba9ee1094ea18b062888a82367b52ebdf1ea606d46f7a66689292eb800409919a3074f9eac4c573359c209b595dc64aa4373e9b12206d027010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9187042a52c0f2ed0a3af6fa982f345280661349e17f21ec11ee438899dc906c979ede35ce34060e666772e7abb1b12bd838e488b705544f033a2ea676f94007	1622019260000000	1622624060000000	1685696060000000	1780304060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x0b56857b8fcc55275087e73918f544de78484551fd44302d42a36f1acecb76a41780dcb55bbe047b09a832cb124ed6365af3248ec1a1fa92414c8a055f979cc1	\\x00800003d16120c4ba825917afe34f5cdbd544af01298e46ddb8436c20d48c0fa8a2c75c2e6818b3ea22ccd0554365ddfd8eb03072d11fac70636224963f7c4d5c9597404cca63e0974f407837d3c188971e2de344985578a933b9ad16816ac8e7ad09622ef2d3237a6ec7e5e3cff8c9180ecfd84071d3382e801d5addcb9a18bdae4c5f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc317b2f6452c7bfda66b3ba26c52ec80af6df690cf7ba729a97cf0930b12eb547493dd68e9ea4d6c2fcd904f6ca4bb2ab82b01f1197bc03ec69dc01b7527c10d	1623832760000000	1624437560000000	1687509560000000	1782117560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x1156bfc610287aaadc4937ad73d1045a6a0fa294a5bcfa36aa9e23e5036f612f9d296fe054ecf3c03192a66b0551fd9089bd62043ef5f2ad012f72ef324fb127	\\x00800003a93f4141f29d38c6d0dc37710cd711ae92e4d132abe2102c1b59bc3f5b2bc16e9d49d4a5f609b0dbc369d7daa864958d074d5de47036151bbae5ee51e93f599c601520c49c54de59617d50319514d81ab1a554bcf5460e0377d68ed4720bb316554342633af8b0c30bc3cd176b17287c3465d325d122039848a222a38a36aa39010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf9d9f338a8045c3ff966c6c2aedcf8c7eb395a1dbd6ab8e4c8b0e90922f46835c272161a474b2cb08cc6370aec64aa692975bd350ad554fcbe271d610a03ce02	1633504760000000	1634109560000000	1697181560000000	1791789560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	235
\\x138e1805c5e4cc719145674cca1c1c1528f285bdb4cfa1dcee1faf9121b8db21c98f915af3da95e4c0f43c3dbf65cac945aed1d95447d13186fa85290d1efa38	\\x00800003a667c82399eb1d1728f053de21b1706e2a7392d54c863331bcef47f91b01eec133efc17f224debfa6429ffdcc62aeac70dcd6de3e866ea596d950c57f5cdba31b653e4bce2aacf39b35386b515333f0d8035be57484e61637c449171689982f41357f707018b0f9bae7b9601876eb2376969b8c647ffba9feaea79422f6c26ff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfac33eea6649c97b269052f0a54a15513fd6ddab1fca6f837f87200db6631b14cf9e21fbf1dea63c32443c985bf7c088bc79b01054354e7584693ec1a15c4a05	1611138260000000	1611743060000000	1674815060000000	1769423060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	236
\\x173a96e219d642f434c4eee25b006f06068f64e12204913c64c839444abd370a1a57559bb7d90c5a090a2d75bcec11bbc58126379659ca2a59fe1ecba5c84d7d	\\x00800003d5b0bce69167945ae2be66a0842dbaf0953d92aea5fc8ef2bf8a8eff458a1f5e38325d1052c5b79948bb12fa4765721693b4cb1d54caa129ff25253dfd2f533e579a3b042c57dea79987b2aaaa4a6c6d7704da201030ff5742f74b93331e3375a3c532750dca982f9d503c25045d5297c6f83639ca5089156e9cb1081b535311010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x97d6563ff82c5629081af4aa07898f8ca22d54f62f2263e67152dece996957c8b582e8e9f11f2826158c42d02b35505dc8937fd91419cd2cdb1f03963cbeb901	1637736260000000	1638341060000000	1701413060000000	1796021060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	237
\\x18fe18e4b5f9f0952adf468e38f05191844b1271e10ae1e190dbc7f636e86aaeba7d0cd929cb2819cec773c94a0db7cefe47c7ae6827aceb7ff9e37d1039e517	\\x00800003fbf19b9fd02347d1cd19bca23c14228c271f21504dbed39a68b8a34de27dc6f79b686af51bc15dc5953c4c9a09dbc58f9e0047b51887eb472a44aa58604a282c867fd2b70bbe456ac1bedc7ad4954b419e4e21b40ff9589b2a77d6141a688d551d74a45e6abbabae2a96d276c4f25db4ea7fd8b82862e45bedc4ae738d7c6289010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7980acb3b0102dda50489a1f80b7806879d7d87a67afa5f679982b65ebff8f79e1b6d858dafb76e5a9561f643156b6848b08a16c80db2d4d2e7e5987dff87909	1626250760000000	1626855560000000	1689927560000000	1784535560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x220ee9d6ea3b85687cf2e49a5c8bd3484646c6e4bd6cbb68ffdd7fccf4aa1708df98d5d33fecd7b023678f65567692a1ab39fd00c7ab63b73fd706d3a3ef128f	\\x00800003d19f13e889617a125f1ae59d5a6d80c90d8987b8b2d749102dc331365e56231e71bed186870ee8643db363535478ef5ac85ef0609a348cdb828cf86f952e0876b4b163a283802b44d7b9b18531f481faf9bf2771995893def57cd56d0613fb9ec3e0b3029aba405d2d4307d1bd32595beb65a4f510a95b94e059c4dff6f6a0a5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf5b1392768059e372ea62f1641b1c759e7032b03e14d4eeeb07f022c61d0f86019d05d59ae978ba61a0efed04d74760724be7b37b950498e1bec634d8a3f500f	1638340760000000	1638945560000000	1702017560000000	1796625560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	239
\\x2bb2e7e0d30451d70f6175670e588e17029facfe6478c086919a8b979f6a24e1e44324fdd3651b48b8dba0c3339a68134c09f7bc9957c3af4088ad83ea60b1b5	\\x00800003ab10c54a51be5af4d1619cddff24d308aaeb3bbd5ec8a498156cf74bb86e028c0566bf3588695fa780f2a8b8be9aa9c5b0e4652fb2bebbfd5dc2802e6900b74ece52eb4ced8ae28f65af75916bcf1989c0e3b9e3dff9d64094f7978ae8e55bd54b97f01cdb35066ec0153c375d98dc8d09793a869d34ded6dd7f1d198796382d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0b4ecf85ddb0298c46a2ab8f59179b453cc09949ae5809f5871a234a72ea511e0bc5f4d792520e5c3a751f433fa0e8e75f3b247e061745d1b9574be01474060c	1622623760000000	1623228560000000	1686300560000000	1780908560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	240
\\x2c5a57c5d8ecc16563083762c1f655d41dccdd27348931140501415d4f0cdf3cdf6af8edd5f0450847fbc94ebb2959375d5454b44bdde0a2cb3a5df9726b8240	\\x00800003bb362aa473b87394e9ba44d4bb9d9e33cbc6be674214f9b2394361d6dbef42932313fa7d4a3c6a5a5feefab4fe12cbc2c1a28d8836331e6e7049ba45c005a2a0a059e704a5dd25de0d5888964b0429777df167fcd943bd4e18bcc9d16a37841daa456c6f81f4aa698dee5b10b9ba11438d450e9021b44841e8c350a1e08bd951010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x28af5c2794735340373340eacff95fc5afe717ed0e9f46a8eb8bffa06a3ac353d2f158b55892a10ea15bc8d08458e11e10685a8a7ce708fa81f12024494ab806	1613556260000000	1614161060000000	1677233060000000	1771841060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	241
\\x2d92f35582c6f6dd230c69c6b9891f9170787db0c23d283fae0b35bf72b9dcac4892dee517df30b4e9112d2d9f22344298fd9e593bf5268383a2dca200a01771	\\x00800003a7c47476c2e40f1f3eea899ec3607c399ed54c224d5e7a0b8aa34d82ca9df31725e2bb706622400ed30c835bbddb696937f0cf0c8d116a57091b3a67e88d63e509729cc8037af5bbd27413258d1901089e34610b35291bc0f7514600517c8dc59220472f8b6c7dfc6673588829172f2bdec6531a00a0d3397e44c714e86b361f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb9dc14cec2c7483ee7c5114bce911d30d78cc8a66ffcb8baaa272434d0b36040b9b0b8ca8d6730dc5f71454b89299251a437edff12e544bf6abcd07e9260f60a	1622623760000000	1623228560000000	1686300560000000	1780908560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	242
\\x307eaf197e8d962c6fe82c5326322d3fd832e126cbd6d55a7f1386676c441602a88b51323e4b17ecedefd05d22f6961c7df36a44839ea5a7bc1d03b18f7c3fe2	\\x00800003c9bb116097391b8b467383be7c3a8819841bdd8dbcfc2911187f566cc33912c32044801795dc66ebf148831be1ae9a5fe519676e91213378eb150e6c11c4bf282d4a9df265cd161322e5d43bd47dddff879e0fce9125afd010f7fee98fe654751150a6b0733afb5efa210c5c00102245d18c1992bdced5fef13556105f251ba7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc1d6bfdef979a25b28ad523052ebebe5d39069ffce64734abebcc260701803ae56b16736904ae9f13fc228ef7ca8626a1b6de4fbe2a25e1ce15b58b68f08bd0b	1609929260000000	1610534060000000	1673606060000000	1768214060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x306ac2a89337756e8fb9b384e89897e3e2e68a3f8ed38d05a27b397f0beba6ff6277ae3fccafc11f1a7ada25aa1fc4ec22198827d413f75156da3e8450a72279	\\x00800003b643810a03a4cbfa6c41b5a743a2f738fefa536fe281e8487aab4f64d09d2e48025ce940cd22001e01b80f0abfad01834e573f305ecb5c00dfd18470ec57d501732db2df78a2c15b218c1bfaf2fb955ac8ed5bd3ae7ce6ad27714f64800ccab4c7ef7c45bbde9554ecb98c081310ed0b1b4c3d8b903d45b9fbad39da668c2d97010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x10595268788f120bebecc2416eb533d282946930a6eaecb39d72bc8aba83630ada77fb93e4ff8f2c86cdd6c1cdf0bd78550950eb5c7bac3196ac9cb05e00ed0c	1639549760000000	1640154560000000	1703226560000000	1797834560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	244
\\x32fa94130aa90acc9bb21cc290db33fcbe42f6722953c5e8c257a327e559975632429058b43bf882fb40ffa4e6a5e150dca72d01fd0044b04aba394039b8476c	\\x00800003b124b4abc02e98c12ce4d30a2e6cd3f4d7706a753766d945f9607454029f96094ab9e4df12d3ee6f21ea6f592a694b0e3d8e2ded3e4c7d190a88ee6d74eddb57a7aa19ae06ccbe57cdc0f14448c6ec2926cc5167b01452e5968125648c34f36287c4ab8f23b4e4711fb9b6eed4949db6dc5c782f19f84a3775c08232cd074ff1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6e55be9d20f8e7031cf0b00c1afafec6254eadac5cb67d45fcf3d1fcf9d31ef62fc25d5561d35f49ea7d84e25e21c6e77c9ae1f8b685b4e2d2478cca7dcf2d09	1614765260000000	1615370060000000	1678442060000000	1773050060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x32066531766eee57f4b4877d86c25f3dd3904e7923d03e8e5f45586f0ffdd2b4d31df67641a98ddfea0bd7b8133f435b962e450c2f68671a8d22f62cb9c3943f	\\x00800003ad0ef8e53dcf10600b676ad110958cd24aef57da1e1c774803edf15e08404b95d268d3bbc67713c912f27f9b1db3f115066b4bc11352aad9b304b75d0e29ce726d709050b7f7f4b405765c8c5e8bc9b22412a1236b95562cf0d7ec83e2bf29a1472b6d5bb719882ee4ef15a33c94879e7b254d9f9bd1ea452b2f4b565a1c3235010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbc6af2680e4f8bc5f970ee4a64fcc9d50ba655bb7769530a2898f8168ba0f32e82fbd3132102d014b952962cccfee4483593d50c0aa835d2e6a2bcbfb6491f0f	1630482260000000	1631087060000000	1694159060000000	1788767060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	246
\\x387a70cbf43067ffa1b375743c63d7627cfa2872bd955d510ec7443da44b5b0f4c646a681ec1f706ef21c160637ff32142a33ff2d1b638817673613ae153afde	\\x00800003b7839549ceaa0726890205b338f5771d596d352c628d2af78f28c659e42afff44b459cf143b5aca9ba375397d17c9bf5583675df85233d14867a6976929f8a197bca9db9c3ba0ce152ee11350da99e62672226308172c7879a2c5b0e8877439d7d528959402f877a1f5bfb52fbd7e7fae4ccf208856b1a20eb70a7e2f410e7eb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x891a32616e7c557f63b04a8132414d0c0457e8cd5dbdedbc8594bd1a6ef8369e24822ce80da5de4ec0c3b52efe69caa3e142fa5e547e6d0cb1af880d5b400708	1628064260000000	1628669060000000	1691741060000000	1786349060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	247
\\x3986a82708abb4f49d883f4caa1f7cfc632124f50e3331362c400934d3ef603ff690f462405941ce0319bfcdfe32ef4f07e204edb3a3730bbc5f1bee0ccb449c	\\x00800003bf253963ba84c8d6a768f1451af52ab17d339149e937fca11e1a8df4038e3651c295d4d7e41a49c6344f8a009ecd3ec9501a260252e0fa7c3271dab14738ba0eddd226fe5f9baa8bae54b4a42597b92ca22ebe448a5df67e172b47a4b9af162344ca3a6dfb561fb0649d653d12352b91018fda9e832d2be58eb7156958601a6d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc7f3d1b86134493d540a5185a601b0a42042182e8ccfa19054c655167da593e1f44d762a31c0f9d9998ddd78508c228c1a7351f76cc9fbcb2150d5d2be84fc03	1634713760000000	1635318560000000	1698390560000000	1792998560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x00800003eacf70ad6b7edc278c76291ad5dbddc0d4d4c6cdbd405283388146a18b231a60931e779aa690569ae88b1c0b6c7988a25e5d1b7ec838b5a469b7ef6ae43c1715a9462a3ad4bfbc7d8573f4c4e508961f78f12bf4eaab614875d2a5e4c712dcb2e04c200eb0d90f8d8377d271f448feaadca06510be4c8f0a3b752b76b7bc87f3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4f0e6f15ae03ca9d45d7c927b4a15d5ee588497562c2d6cfa78b0e873ffecef6fe5832852a6b3329a6749e85b5ee03e651cbd46a8445b6e8bfe11e31a052bf08	1609929260000000	1610534060000000	1673606060000000	1768214060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x3f9afad2a8e955359064e6eaecc26a50a6a5614c418c7c0f178a1b1672ef7b28aebad9ad8e82da37e5a495dcb573d23db6598dd83c3ffa6102825865311b1a54	\\x00800003e8e451f4895283649efb24c26ee7b4861e66bf8871a7e9e37f73fdfd0938b49a5f18a7b5a24b2a53883398c19880764accc6e4edad518eb1f977516be703103cac1a0cea09852d73e70ab0b62a3118bfb987759d35d1ad01fb3d640f6fd167f4bf979989a2e4477d680f3c6599cf1a98dd1da3c7931015efdaa9f659fa2fc29b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x22f68e9a4ba81705274dc18706cb435b17e6b0d57564f22f5ec98af928c90c164bbc506053a4e357663de09c460d997e0cd446580586bb512037823ab8b85f02	1638945260000000	1639550060000000	1702622060000000	1797230060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	250
\\x462a35919d017dbedeff72df74e5883153aacb29de41fe3d1c7eb37c756cbc80c79e9b3582c3bce0cb27bd04001b4974d25836661be2f1385c3a19884522ed38	\\x00800003be3b9d16f67070f60abe836c9da9cc597fed644225327a420809d1c9af8335da6fc4722f1ca1cfafbb3fa441b2b9bfe5c38242a8644bc9faaeb346089ae07b87f2e557cc896ddf9c11e877a0b89128935d45bada1a92ce1ce41da7ded448f90837421afe456392605ce601ddf87d616030e66a807fbe1f3f39c47663a3f570bd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x355a009a4475cadbebbe827fca7107d6660a0a5e5611f2d3e101ce7d0904f328ece79d1c38bc041f3eeae04295e02af8008c827c9b948f42a6989e7f5a8c2b0a	1640758760000000	1641363560000000	1704435560000000	1799043560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	251
\\x461ac26bd46983442d209f1192941df88c6021a0dab21a154143a7359f1fe0c2f2b8ca02e6c8a927a4719f8da5c0e238e9f1ae45e5b873d470565382c145d174	\\x00800003f4b5f9b9f9b5d66b78194f1f6f3cff3a98b705462c373bffaa42acf82e7cf97c5e0f871e60337fed8d9bf390182a842745142f0086c119341033c06d1f8d5b7e4f125ef0ea5812cf0232a24b88398e1ba181721299aeae8c545acfc61bec0094e6c55ab2bc23cf80fcb7050c989d161283c1cf9fefe52b70f3b8fa0eddc2001f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb57d330c3199d07cb92253fe43affcd17e9c77cfc4f75c93e80d2305c7ec52bc9518146a57637041c2b735f09425f1ba0ffb2a9820d88b90f2bd10f53c6dba04	1629877760000000	1630482560000000	1693554560000000	1788162560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	252
\\x493202ed3ea0e12b3c92295a3d733b458b63f528205f61aafd0d456f2062bf4aadbfb6680388a15ff584c47fa47e6c5f3b8f010aaec3efe7203e54a76f40dc1a	\\x00800003a5ba2ef7ec7536c82f1165734f59e20dc5765e78be33a2008b7b11cd9f99ad8cc70973ab8256e335a6eecfedb496d27a1a929e822c92ab2df0d5cb2d1425f23b80626f233eb701e901b1fb91bc8a9265d0e318119ec5ea2c1ade04f79733bc6f762be83b75def33cd3641b8943ac1ab6c5c4cbcbc2d3c73b290b375891e2d9bd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x00db29eebea6701b6cb84c94132cb5a7a1f439617e89125d6328d6293f58cfb355e5dda2ec932782d94497516f4272d384100f1e901a1df777601cd8068f9f0a	1626250760000000	1626855560000000	1689927560000000	1784535560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	253
\\x4c52eb97b51c48a970a0c96fcf8e258d09fef456e1be82adbc0f68d054f89d6cf7d611b3eec0672ff73f6c1f2dde5409ca0721d1750e7ada0a655bd25964453c	\\x00800003c17a2825ddc36dfec8891f7b38f99a67e197010121f292c7bd155846991821d8bcc712eb5b87e1467039964afe09e2f221deb41563841490eec1906bdfeaf858a183f488a72a7364724af0af32c97da5d8db8ecb6337065ff32b715b4e1b417979e97a0bc1520c3047f0eeb046eb696420bd8ba29fcc8e7d294361db807b2f31010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9ec7bc7e9b77c886b51b3d64091e8342e0970f4eac45367a61c73238aa0ce6def33b77d05e7a93fe1ed788dee630bb8f37db398111bde195b967d8d45c667d0c	1637131760000000	1637736560000000	1700808560000000	1795416560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	254
\\x4c8a6c714e5085ee0e0d305e50cf13852d97df2edc28f387922fccd6878affd2012fd356e0830694b51db2c79b27de5c2dc14f86864e7e9e74b3fb91425f1286	\\x00800003a0f0844c532988a2272c0a1475d261e206c76b89134edd7ebcd8f9897173d7c39370a8d41654a2daa6df9e5f67df2e4a21a8981f1b537d38d4909878742e0b8d8e5890830ba4408d1c558094c592795353d9b2ec8e2cbde2889271523b0bba80a4cff47866b8df17d7f8d1dc40263014698ebbbabaa329479b5628a8fad4f563010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2f392c3fec9b81433ef6755ec06ca31e9491a09c6fe0c16f44ea0b1f188ec53477ce523e36905ef86ddab51587ee5fd04577d6bc97a394b3d4f28b2c6112370d	1613556260000000	1614161060000000	1677233060000000	1771841060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	255
\\x5a2a84a21b02d53af7d9ec3e20632d9530575029506f13a2ab7db0b3919da98252baeea8f3493fc9d996b106bb594e39842496f58250c9c1195a385a1f3ddfeb	\\x00800003a84b6c2d89d7ed1a63f22b384fb1c79b2f312839c95db2eba7d91eebb70c94a80954ec8356a99d7015090c569c5bd7b4d34553cfaf7cf8a8be529180c457dadcd57d7f91a47310db577f95daafb0fc617d59b21b8597fc0ee70e7bd02c5995881d3bb76d598b1572641544b20cbe25820f16d299c4ee2fd3e5adad7b284736e1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7bacf30436447ba0e648ac2413ad27dc1f103a251015df5b966c1b3fb5dd17d2eddafe8acdeccc192c641492e59819e3fdc102d5e46eac29893c2a68fb6ea405	1633504760000000	1634109560000000	1697181560000000	1791789560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	256
\\x5f06a811883b4edb182a9ae11bc1759634a0f96fa6cd542f84a2e693a025dcef2868ba5f647597062663f4ec7209e661722365f9c0d619009a398240288dadbf	\\x00800003a881e2445d3c84c1188dce71bf42e4571a55f8510205b82923ef3182e6811e0ddbf6b70b0d869b15b70a861fe911b2500893e9458f9074db1f47765c3c8e6237fa59a352db0b5aad660dbc2226bf0d1105620f8e4087e305684046b12960651fc17f236d901273082776d4a5893619c065c53ac577b1b247dc6f588798ec9f25010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x117c7dfbe12fe21c6abd8faf9c15a8c626607c61886a5c9ace65fe6956b1ccf6cc42c4abaa52b1b121b2b530ad3d3cd58be72a64dcc47d90a281134a7fd36908	1629877760000000	1630482560000000	1693554560000000	1788162560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x6406832d0e7ff078c0448539cdd09db5e61a9b6e31d16f624735b754b0d64896ba4ca41cb7ed09de177e8060d480801f57a3080bae8e85a10d3ca76f6cf95021	\\x00800003a58c4232c1c865d82e86919f99b5b03512eca309254de2bca4d8bedd70041ea5bb465036d9a081216e75a331adb267f5b49800c62a6aefcd8277c735ba0408e09f4df7a83dd59c8d1906379eabeb5f69777cf431612172b8aeaf7b74181ed9ec39df59ea18aaede0722746fd4b63581d662e85b96e87c08a90c54f83b12d425f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0498220f2286b13a6fa49d4a89faee0c3ff98474c719fc39804dbd615cebaa725ac10c002a7db9072dfbd43974faa0db79eca579ba56c2fd9b32593de13ce309	1612347260000000	1612952060000000	1676024060000000	1770632060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	258
\\x65ae0b06bd6cb9d16fe844f7cecf71a4fe30ab16699062955d29a321a8d88f9bcaaf9a0296dbd3d842eae415ecf0e252652cf2bda71b114cbaa90cb269d77caf	\\x00800003bf983854afa38d2210ad99a6d2b214b00acae3d3b07d09940020236c7cf5a8081f3848a412342b2357e553794d11f2c13ff8e2836c35e6116e6b44a2e79d1f1d0fc3ba98a8bdc0823f779fe3a2fe7e7a00483538fda8ae9b0c3bab14e2f38ab2a261eaf14adde068e5e368593a28ea405d4aecf7fc158e6b1646c90f4ad48d21010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd69073f9aff0c9c0ccbdad0f568918956f943f9b59a1e4b2b18c715aacc5eb63ed9ab45389396303dc9dbb1ed81d7437f9a1d673f084bfa8d3459edbc0d6c20b	1620810260000000	1621415060000000	1684487060000000	1779095060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	259
\\x68d2862ee6125e1225505af2867d8085ae011a1d6df74a16732f381296a890060d11f767746714e504cc555e78c6d5d3b68d357ec07ea0ea66fb1348ecb8dbdb	\\x008000039c9d8a5b22ef600335f1e4e36e6618c3911aafa3596d036f3c0ca23e92ba80368a88dab65bcb109644cd582aaa7861edb738e3728f51cbc67a4c1da3e1a87ccbe83e9ec9500eed6eee0fed76af3bd10fc9c1ecf847ce1a1701fa6aacabda519181b5e0175448903f3a6e8afa53e7182cd240c331fc72b295742162f153d36eab010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc02fa43cd750f57a9b5190f7051344a9a59d8672db6bb54a0dded54b445c4cafabbb5744427dd115ed32f06e6ad573252ad460d46de48d94cc21c8eccb0de20c	1620205760000000	1620810560000000	1683882560000000	1778490560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x6aee838e013e83ceb210458ab36fec01117e14e402b8beb3501b902efb54bd2abc71d4f87ce17c58c5110f6ba311ac52539bbb7e97b5d473ce484454cb4bff88	\\x00800003a15265124a437be352b5cea3e47319ce8f78753a9d20d4d23130c16f48cca2e122d0a737658c69c342064e1f7159d99bcf17ace935b06810de86bdd3115e9885f2b1a4abe0a70835cce512ed43ea042cd340546e39b5a2aedc5a6cfe7853104fa35b5a51c21ef16b4d2150931afdb49bd61dcbea910c0fa48463d4945d231b9f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x93a120487f2ec335ee853a31b79653f24be7951643fa4ebb9c193f1f6ae827775e5130604ad9dfd0df64ea24976edf1156224e01739d0410c4e808f7ef98a102	1634713760000000	1635318560000000	1698390560000000	1792998560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	261
\\x6c0a38b890f710929a18c132352c5cb3d98165fce184c0840dde08a1ec36ea5227a43cd326d5623b39fdf2e03d2b6d8b8669c86f090afe374e026c3d8f42a250	\\x00800003adab8a8e927cef7f67a23cdfdcad4a351659ebd303e01ed21c843d808223247610a9647914105164dd6ebab4f04674d2ddc0b3d7a9279caea7b807b145f40b9bde7366cab04d9f426899f580be83a7122c0d2a3c14190ef99a349273ab306ea49e4a603ceab53ed33bc9714449fed6612cfba0beba43ad96b8f0a1252b08872b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x664acf00131be33bac144c2d119b2af3fa321d5588795f966f93a448a102eada61639aebe40b6a3342faa577d41f234389b4070d824a02101887a031c6e2cc00	1629273260000000	1629878060000000	1692950060000000	1787558060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x7022b2d2a68891ff7da401cdac57fc3312885b457000dff0c9ca0d5ef58c3800e973c88b02996e1b9294214166a09b5804e48b1a76ab9c77be7d1635c2925573	\\x00800003b5edad23dc5da2ab6b2f9d6322b560b57e81b45d862424d13526e64b6ad7c8fc795b1fbbb76dc4e96b14050de4ff05a730f257007f4175eb4f379024d4abb419e31966966f6b3722ab84ed20e9b25b95a2d7d5b677a21ce61ee7810cdec8d4c0975669d3295460c13565d6793485473551b412f0a0b3e55614b206898fe179f1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb1e7388fb89bd0e107d01107fc3dc82cc9dcd4e5368d4e3972f6467296bafeb585353546e074790ed89111bc19f452bdc1a784b6f16ea4b67894ca6aed8bb408	1612951760000000	1613556560000000	1676628560000000	1771236560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	263
\\x7156158ff95edd3f86f9bf17bca9d8a766f58893689400f2532195a587929521d34100a657a1e63e39441e697941426a56c7a3577a418513a445236355d0af57	\\x0080000396ab02c056f283bfc1494b456cff15643acdefbbf8a2cdf52de7968242dfdb942663c4fd2d5eafd9ba8b92f469af17f7b99c9b4808bb10f0b5ded60183f2f74fb113743dd48cc37eac82c1b4e512a2154a073c4a4b2ae75a8a5cb23828ba3facc47509886b7dbfaa13836735b87d52feccba97d94954cddd40cb3b2169439e45010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4a783bbf22f8e37db7cdbfc076bad03ff6bdb78c2c9f09be0d381385cdc96f9c77f7a8901491ed37e89cb652ffe99c64ca9419d3fedf316ae1847773fb96f40c	1615974260000000	1616579060000000	1679651060000000	1774259060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	264
\\x75560d6a138e7e7ed056c4d0a4f4fb1ff733efaae88d9558fc9a5f5fde3f626b3a8539399ff189d1c7b2a82d765ab22dabe3bd3732b39d1ac97f07b2ca80fb58	\\x00800003d0b0b84d2942f09136cbb3a97a089208abfbb8862c4a4fee80a8deef5b043e75b6a838e51349691146f93ce7621942cf80bffa09b3f71408b4a7c60d2fb916e015c6c6c4094d094f20ee6bf1ed5926d6c62aeb6ddf27d60018a48b8144da4020c47111895d202b760be40094e58c6928f0869d593d01edb1831b6b65372ff9c1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x895eabee256d5bc161e5e83dff71a980eb422b394923bbf01b9902709a35214ef9c996690960517088869661b6a334fb56577d6b8211a5687449dcbae38b2200	1623228260000000	1623833060000000	1686905060000000	1781513060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x75ae5ab7038ac74a947afbba2986d33ec18fb595e1a5fa8f450576fe8538897bec9f57fa2939f246fecb3df8226ebdd3656c15add287e31e935b7d1653c46654	\\x00800003d0e86f029444afd098c21c7056c1289a8a126c4fe1e8ca3c4ddcc5c70a68101e97d2b9564b3963fa45c936a1954c2ae049d99878df0be05456d1bd7b384b32c1a94cf4d6a4cbb81c42f04416e03c4de74c84a503502f20349885e5e529f083bb5c3bb0909bc6f9cc22e56f018a8bbdbd9768b6ca6865f18cd7f761b3487ea735010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2eeaa0ca3d888ab62fda7157fb1fe367375274b057625d41e835d7ea4e07c2952dc36b4e30dcc9ec16b657b9cfd97d8494ada97d0f3c897e5973f99529f78706	1620810260000000	1621415060000000	1684487060000000	1779095060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x7746155055ce35286883f87045f5026070bfe13c5da4aeecd3dadd34754c761c97e3ecb5681a16bde696aadcc05dbc335b6df60947eb318160b030e52c209a69	\\x00800003b2854ecd14931116d24547f87f16837c74079885d8632ddff7657c50f6bd674660cf9e883d40f59e574ae2925ce14b576418ceff705b13b366cedb5b24207dde5bc2e2a4a5f404a5f37224ec5db55616c298b0441b3b9e5d4ac12b482b99fe37de616a08904f9d0b35b73d47c723924052cd29ef221ce0e6c54c6bdd14b01449010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0daeb1aa8726b2adabba3c07bee4866917efb6c5e215c8b0b9aa490448b27c3047e51e663ae39953957d3ddf11da322eb24746c62ef68d7894b5b75cc4e1a50c	1638945260000000	1639550060000000	1702622060000000	1797230060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	267
\\x78f2fbead8ffb2ab82dfcb03c7097f300c7974aa64ae6939c8667fce33a96fd3a2dc07959931d03bad1ae0518ec7cc376cadc3e1cbf6f6ac86999bb919f0500b	\\x00800003cb2991abbc00bf8a45b13a8a27310332077d4f955ac865ac5a92fe13c5d826c4bcfe9e472ad0339e84cd41f449f3e98c5cc43783a2b2d72a964dfb314cea5ce2de58292a2631009dc64c3f4617c5f589245f0d33576beac62fdb42d4e6d3e6a6da8d62cdd2addccc589797302d998e2c2d6ce3c92b16954a265bc92c57ac4745010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdf63b76dae4d15ce7f65c25b7dd9bc2843ac4e8b493728305425228cb18f98e5829d753abe4aacac78d5abf9523bff4c0f3be1811e39f1e39ad7b67187b4490d	1622623760000000	1623228560000000	1686300560000000	1780908560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	268
\\x7aa21c2efd3d0f50016a8f199ebe83feaf376585f13dba837cc959a4f2c80f66f20cbc6853e4a69ded01bcf66c3acedbfa9b2ae36521ad9c00e3d5e16b68de50	\\x00800003bb165fa37dd0b586a638827a9c58380f858b67cf399cf76f544f537215223e359ed8ebda6ffb422e035960fafec3f1c8a5b5c85d72917360c16be594df720d021ec13ed96b060d7739c99dce356e00b6c3dc409fe2f0515268b8d42bd1b96712dd45bc3e8d9089bd75850277db0219eb3f46e7c0ad8358e8113e31a293f26043010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe98ac09e3aa688035a6fea2dadd4457422967e1fd733e2f5227d219a528f7bf8cc82d3221f5af53721d649f3fffabc41ccfc84df8326f8d3aad0a93474fd5202	1618996760000000	1619601560000000	1682673560000000	1777281560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	269
\\x7df6903220fa0572987de31c75baac7ce63382a7d673c9146e85c94250fd7d0274e1d8c37f221774d5e525248d9ca5b7cc5558a1923985c87053713667cced5d	\\x00800003ef3932381e4c403a573872cea207611600ed5485c83d09544141062d2f32a1fa5eae5d72d36aad6887fe8d1e040b870064447eaf0ae91181be703601e3dfbc0fe4c3111602c247bfcc1eec730847cb6d8554c4b8d696678c1cbdb7a11d1794a2b5f8e86610d2e26b92027e76c02670b0c845b11f9b7cd615a0cabd87587f3f3b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbdd4adeca0f99c129aaf7e61468aa3a40abd2064a7051f770d22c58c55072770e2d26aa7e37e19f3aa3ba14b5da232908c4b09dc24baac9e3af7e3916a6c0b08	1609929260000000	1610534060000000	1673606060000000	1768214060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x816227c6cff102e9fd61d12d16ab035f536795be73e1a867b301d93b7955ff4b4176dbc4518ff5c08971c1241622da445e90fad7757840d32aaa08a5e4f60340	\\x00800003c47954e43e28ac415a3ed8326542a8295ef7e38453f7de1f56403c7ce33353f319f56db8a0596310b2335d08834dcc45d2108da4dd4318030728dec52baf1829b9d71700662c1a467057a20520cb3c39384caa42d22ea331cedc0dad839da2f48730ef879ae3c87342fa4a5e4ae2597ad7ee0feded8a01dc624b00c1cc680819010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x87163dd5b3f4ecb9f06fd625ad6a89350957a65e547342a5db2580150653d21145690f1f5776d5130a89d3cd67d1629bde1bd463a2d829d5d39e9e7c316d290a	1614160760000000	1614765560000000	1677837560000000	1772445560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	271
\\x831a397103e9e64db1dbf3512925bc7628c434b44e6c42347deaebe2861e1cec7c48aa532fc8c1eba328d15a8902668a2144ec3832b6946688dfb979567175e2	\\x00800003db8184ff1a5ecfb274d975fdd873f3f7d8209fa580b8dce1fe6ee900f14ce80391948a51b551bf383038198322f14b4f21d4bdbe595e6733db02cc971d1e88952ff12afac80fa18852faba77c24af9193aa96e59f76fd69d8fe1b4fd406f05d353b1afe3c3de65bc8dfae86b06b582f20487149e8ef35bb532f0ec3f1cd66b2f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa74e811f2004f4716d6054e7543ffeced02e3a469d84641b98aa8f0558c478807355555f98133012ae3f8ff978c78ca9db6776769f7476f8b9d2d6f0a0ad0e0e	1631691260000000	1632296060000000	1695368060000000	1789976060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	272
\\x84768be589557671c08519e39c1dec01cfe64ae7f38167837ffe4a1c47c0e4fbf9207d09152b1004fc3df670e52d69b9f7b4ab6139de8752002b623e93245f6f	\\x00800003ac591839e654258909d15651dc13b0712eafac6c1f38ad0a736a95343fb8ecf5326c01a6bf8e6b8c54f92e5d8f2c109af0f813cd2e620730096a4f297b4aa175320d7ae7f70b11c3eb7add52348fd7c2c932bd77b387e53d73447b47ac59a3972dda563d9fc8cd3818c20cd8a9dc1f00a0102a5af4145032c8ee5e5f33872c2b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x114346605a4b78a1cd6886410f2d976d0cb6da468e0c25f29927924b0de33689ae7d2f0169acbd99cf18164948d8de7d04b1c96614fd964da8f7b6d4f319330b	1610533760000000	1611138560000000	1674210560000000	1768818560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	273
\\x8b9ecba93c31593fb2c57c8db59e8e12704998949ea32b060e371b41f83a1155c860088780742512155520cf45841af7a9acb3a9e2f062f777c7f9d8280d07fd	\\x00800003ccd951d13de47cee98b9eff4de1398fd4abaeee134754c9affe20b7ec4d438065dd1d7ae5eff932ba15abc1b93a9eeece551a22670fdb59c1249587be156884567409d7e87e90a995da0aa33f7496096e6b7971a6acedaf673a76a74a309fe7f9487b7f1c128f031497ae1af11349d5e28f8cae439f3e3cb373b47949af3879f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x43557f10f4ac9e99724bc5b711aead8315c027b39519b6000db46d7ea59b282ea862f2c0ccd427b96896ce5004d6ca7e903dea9488002922e29b437ac3c78c0d	1638340760000000	1638945560000000	1702017560000000	1796625560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	274
\\x8e0e52930e0667b8c63761745943e66cfb6afabc79a4d4e3767c11c476329d91b9748eee3090e0ecc3b19b9830bf6a86f2f199cf883ebc1aa27121d780046641	\\x00800003d43ab55b67fcb2fb052031ce37acc9c690eacdec28785cabf2d916f3dadd13ee88e0856fddbbb97d0ad6b1b2f25ae938a97af2c14ae6792b369af25d56cb8765741918dada400c1f2fc00b2d280394d5b28a745b3fbf3c21696398a3fb47a97804251cf6f5af3f4e5b293e38d97734f381a656ca3cbc3209acbc2a5fcb8f38bf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe3a933902922c04eaf38b20b33be5ec954a3e47f66d797ba2b87214a9723b388a3d8316a0565894c1729382765a6666f2e64a0cb7ce33a1c5204e7c396f2d90a	1634109260000000	1634714060000000	1697786060000000	1792394060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	275
\\x92f2f8ea334763e4fd4f98672f17ed75170b426c904dde75ccd425b0621e334796d65163973dff5f96b290577d73bd21513e6cdf315886da85fbc74607de405a	\\x00800003c25ec54c891b893600a73a1daf5f29c6e6e70c74ce9961354c13ca95b40da843d1425daa4d844475e25261ea006d2b3da0d5eba0a2927694badba96c873e290b70080e39b9d3da4802a292eba87f31cd412bc9a5a98f758170e0b6ad7cafd03cff2103ce240ff349f974d808462277d0524c33fd47e01adb17d540bb0e4337ff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x47a7d6e7024a1e73561b6b72c6d8380aef60caca00c9dc03e744120ec3ca20dcc5eb7a85b25874257b9962aeda1fd3ff29433f83bbdb984c1d0ebc540649dd00	1626855260000000	1627460060000000	1690532060000000	1785140060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	276
\\x94c62122fb41b716c4713b82f59b89378fcb96eb2130b086301b18907cdf5d6a37f10d9161f5324edb36e52cdba8b67c5bd024c7dd02c036c4915cac53934941	\\x00800003af1fdc36bc767c9957319483b20c2903d79aadf299f85f1b72c253af4f9b01c5f809caabaacf31cf9b5e4c747c5cbde152710d89ca3656f8326bfbbfa6b6f3a5b847a28716decc1180e0f568e6261bfdc11bf07bd360790a52611a5007e46e6940635155da8e7b761576aa735ca1282aa96a25288e10601a542ea94dae57ca9f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe5669aee8985fb65265b628d3933eaed4d9df314172dcda91bbd74818e3a7525842f3d54e0a618d17b9f1f443ba5e41d665f79afefde3f0bd4324e95ca08590d	1625041760000000	1625646560000000	1688718560000000	1783326560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	277
\\x94eab4c09f0e161b6c87e8f8975412b51bc9bc01fa5ea77abbbfc80610ff077603fa18ed3e6d1cddf34a880c4fec5ef3529f7ad2c7dd96623f3f501ad91b16fa	\\x00800003ae8063311824b7ff2644a37c52435dbcff4f175f6edeb2fc070486d0848c09c1c36dd648f16173e15f757a6283b0454ac4ff8476773202e88dc7857715eeb30b8c4990fb657bd1ff20f0e4f406b0898c2d7d08ddda9fc2b3e824cde6243d65c04e76508a0d287fe23b0312c2f49dd44f051ba424d7b90b62939cf72cae78a6f7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf02a2a364339b1a7d29aa9366a811ad8442dea02bbb94de02612631c3afc583e3d391d7da9e8f4fe5066e563c07aae0819a5a400aa5f1ebfccbc19a642812409	1631086760000000	1631691560000000	1694763560000000	1789371560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	278
\\x9a267afc8f49e3fc9f72e2d1a087318ba2034dd2a34afff9cafb6789100e90126471ceb739eae485da8d782105bd513391f73f3392fee7fb0f499f9ee8e707f3	\\x00800003c35868163593b02a17074a8bb97e27ce1543365b4711782b88e37d1491effee719e6f4a313891b375d89e7cc6ac1c9e22e19b50732dccf1a30d935b593c04db7e7dafb51d8f71c7a89f20e01d757366bb227d1962cc2b6822ce0a355172619ed33704960b639de233aeaa75a2f60326b5a8ae7467c6de7f964ab8d1ae9b9dbe7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x966f2a94f088b64058e99a6653f156e564172ed4cab7f67ff4e1f8b523327c29548e61378da7ac607faa1dde8c00ee62f9df990f4427ef5ee74fc48892b40e09	1623832760000000	1624437560000000	1687509560000000	1782117560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	279
\\x9e9299ca402fa8e54de67c49086745712e89d72f8eaa7e6968403dd1c7d354109210d9b21191f9d1b57c4c24d9e02bc012e9eab765a96ff4e93e811c444fab79	\\x00800003a559ac0361f72a34f140aff968554ef94dcd84efac9f1152d421b372fbb3c0207c2b360b1951b30c078a831adc2b3cf7d41cc462be342455d0732dcc286ffcb8d0896f12a92fdfec7b81d49bf8e4252ca77fbb539b2943fef05846ce580434927536029853efe7688b700e63b1b65d3f774f436935e6130faba3c61e49b3de87010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x237eb20bf57369314b51aa1815929c7cc9d7f7183bdf81990059d42636fd374cbf4b92e54def8c1cd15ac40dd92772ddd1d9020fe02ebb18aacc33faa1b21f06	1620810260000000	1621415060000000	1684487060000000	1779095060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	280
\\xa202cac914fe77888b5d1f3abd4e7bc3a206176d9edc23c2d0caf5fd2baf45436ca19d5d6de8ea5748468d50cc5ba5d1f06b66a472c91c9647fb069707668be9	\\x00800003ce7327f439cfc0dcd97ac4f038c3be6d8bf97c0248bed7ade622e4df06deb52dfe155576e2fb145d523ff27ebfec006d15c8c38dca3547cd837256617f53334bccd833e9d10f2f0712ccc3372153a128383bb46837f522d523405c3d82965a6fdeceeca53c4bf290bf338677b21ce2e215c6aa39c586e1c9b295c98bd2b1b7ef010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5ced5af903c7e94eca71499f999b6660700d4b0b26b57cc24a624bde2f5dc3ab3f75dbccabf8b5af07fc7d4665713eeb95d33ff806e3504f5c9dc3ab333cc903	1616578760000000	1617183560000000	1680255560000000	1774863560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	281
\\xa322e132722b6a8b62bb7aa6f5958e4b2197ccc41395e47226a35813dc014254aacc2488e6d0284e2ce2563b0a76a574a147b9e669a3631895c72c2fb40980e5	\\x00800003ff942129daa0439808b16a9337a2bee835a859a10df0d1691eabb5f208bfffbb7c3d5ad6ea8bd177c95a86e7fa5642be37ef1434748470957d74599cdd1c2442f7c7b046a861fa0ab3ede7100d61a9741968498b0f01faf6e4cdf70b01acd48e680cb31ae6d45cfa5bd1557a2f1aa453acc4b891cd9536d402fbef04638d2ed5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa3772ec48d68f028ab3ee2e409b38dd44e94ccb4d69f34ece0603ad949110eb7f3345bb6a171d5af7539cdbc1c3df5ab4e5786fad03fd72402986a4d13013f04	1618996760000000	1619601560000000	1682673560000000	1777281560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	282
\\xa67af8e598d8e3dba283cf00f686eeaa3edb6c1c711a686238cca1a04dc42ac73f6a7afde0e88b5758cadf637e0904f909dda01b78fe7af11d19d82548a6b6b6	\\x008000039ef76487f9a83c36ba58a060a8382a1610496048efde059cf14a8be733c1cac61c1a4d65d9a3e72e0377b6f09a98334f327c58166bc213cb20ba3870639e4d6f3a49a6bb52ddf1bd3d36e7e870d38466d1d284960b0794bd4236aeeb7a98513ebd63a53a0bc52e52bd3d13a6bcd3f7c620422de18171cbdd865b97c9d25d968b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xaf6312974ad4ddd2c919a48d44a1091302742e4005ef5220e16381f64a03df4ef66bc2e3ee4a827fe60a1d5869f5746c24a1db2971cc03bd5951b22e76d33e00	1620810260000000	1621415060000000	1684487060000000	1779095060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	283
\\xaa5273c479943bb713700ee04393454643d4cc3c3d3d8481126871e87c9b18bd980d71a2d053510695a16ddba5856ac001f1f1a173846a88691d1858b7d30024	\\x00800003dcb0291751b9ff00f4dc9b163daab4ce6ce7bac05e50acad55322ca9882c1fbf652fb408cf1425cb6a82c24889cd50ab7a9bc5bec9216d1bbdfa5ba18d69f700faeb4feff8dfe7c569c44b25847525b159ef34b44957da3f4c91e49afa20a9fdac9402cde5e920cb46c23a5e1370c6f35700458f85447156eae4b56749fc6789010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfc4b1705717772d04252f25014ff98d398ca107a3b30a2bcde20336393769d5907aeb47c7f5b8313c26eed5fb8fa9e72754696c5e520d2ce7510a4a74053300f	1626855260000000	1627460060000000	1690532060000000	1785140060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	284
\\xae9a73b0cde09760a47dd3ec35960226c1bf6eca9f942e1bed11261e3ff89f1082f7a01875b6276ba227b11d8f5e05567f0f0546e6b1de968c01008c9d704e84	\\x00800003d0f1709e65ac948e73c6b152b197af2219c80573cd330f6ec5171197e1f1dbba8f51fcffbbcee9812e3c3011be16aebece10435744258ab53ec53cbd93cf09e6b87b32ae56747261f25e7cf636b18d214a7d2fccaf9a906c21a2de03128474d217a5ffbeaf1b857b61075e8ffa8a3c6bdd20e52ab9ec443bfc2ecef227a70221010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x991351a7318fa8839b1a6ebbdbb7ab30ea0c9d1a61643bf88a7c60ae3f8b4cefa484b6e12b67de64ed21fff43ff947484b8c060837df1c5dbd5b01964b338b07	1628064260000000	1628669060000000	1691741060000000	1786349060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	285
\\xaf7ab636b369d7c7403a87b4490991835a0231949b38b1a392d7516dc726e2168071d5776e6bc4e6169dbe79a19b1aca749bcc1e6c46d5c2a90728d0402a7479	\\x00800003d0860606998d638d9702d56ec7e860b3992ecbf235d15e5bbc4229a92b1376d1cf05a541f5a31575c0f480c4c6b98cc5e2e16a54de76c093592bb6893004d6eabe6a0f624a9cd86b1eedc1b22deaed1689fdf17c557866ff35b22112dd2b26036edef390e9e200431e3e16cfd5baf19f0b4b4a475d5598d6dc3d9a85ae75f2dd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd28dfdae523a2c99ed0bdd597e0935675e27be9eb46da38c58812e94eeef24966ab05a307846c5b3fa02feb5097bb24af83439565e20c736f57f11f05a20030b	1630482260000000	1631087060000000	1694159060000000	1788767060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	286
\\xaf564bb9a8adf7002768ce9b016c5f93282774021ef4b9db4090ad40a021f35a2dcda4ed99fb84fe83b16dc0eed3bccfd1285dabe21c14201cc545fad560ee1f	\\x00800003f008f0f921b97c71374a28bab94aa4e0742030d095526c51314e6140d7a41a3789f42849ab35ff9b389e9d75d1e15560f8a4db3e21ea07c07b690709eabeeaba66d1716166cc87a607b2ca11df335dc355bea95713cbccb48cb015e4e628f70b2c0f2c094c5da322c2627e9945a2a7bfa2ad5a8ed0ca85030084818220900957010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x45d6374236bfce9c689e635153d64a5dfcd272adfdb8181aed8c538accd05f6d593b157e51a36707d705807b805407ff0af3431ac9dc5c2cf6e40457c5438c0d	1635318260000000	1635923060000000	1698995060000000	1793603060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	287
\\xb0bac1092c5c8bdf0d63de1eb08d36599c587f46a6e73fcf8c8922ad3af82eadb6314f62df5dcd84ed1270d1e32fb49b28f2e38b30ad06b32fb2ea9d924a9817	\\x00800003df4efd39e42780192c560e98b67a763fd945fac19de5219123e71c1f4fffcc4ce74756440c67a8bfc7102ed3b28ee708baf7ef51109400da5ca5790490f71f1a40570a07e22883e5081237d6a63ca343c8162691726fbc3ca43718c6ab672563845dc424fef4e521b843981f099b16a36e26cfd356efb06b877724914a1671f5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfffeb7de0fd296dd5a52333ea7f4e8acab2277b6db631c5b27738a3aab5f10b2c716c0f4b3ca36cb82dcf22f35f04ca9c5d0bd3d6234d10d0c5a92b9361aa909	1614765260000000	1615370060000000	1678442060000000	1773050060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	288
\\xb106e4d1012a58f6cbeb11757143ecd32f677a6919d189ad8cb65eea31c25f658f3695573f68cc39558b5e39186de53035dccea1315f440156d51ef2ba391753	\\x00800003f7a4bdf2564f6ddaf7afb4ec79fa8274bcd05fcfd8dbb5c12527ad23e86af43037720c9a36b709d0431e5f080944457f4ca4d9f29e425144fabb11ffc9bd94d4e07d3d67f0f4d16d100049b3703c06c4951522bdd6e56b1c3274b6d02ba56196ad601fe05256daf1b029abcf46ce581112a2cee1a8e91deaaea8a575e554897d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd85a6f8b12642c1b9998bfcc5c53ff7dfb4ecad3295a4dc8a3c56716a5a3f89bc7f3cad469522e7d1bf27820c4db67b58040bfc81167c9c0035ddc48de3e5608	1641363260000000	1641968060000000	1705040060000000	1799648060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	289
\\xb4ae7bf81120a4bbd762801b179c3efa339d64387de969bcc2e6bf3b4dacf83fe1ca5e32c807986493d7aa3237dbdf7c63bf17ee395cac5606e798d58384d372	\\x00800003a10917f0459c34190de4dde2b429dc5db863e5bad054bccf2e00762342551a7a2f3324d0137a8ac13558500941509e2b76f8474cedda588b1d0ed3d496663ef347eec2daf30cde05fdd1703c63b85e23b4237640228e44e243c33f5137b23d17042a60faaa10ae356306dc865f6203d838b0a146c1980a33e4cdb463449d8315010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x821cf999be7796b89898484dc1b76d567e9a849f23950c58e41f63bd1122b359ce99b97742feb67874d8a6c83ab770d42911bd3ffdefee11ce523795d7c57b04	1640758760000000	1641363560000000	1704435560000000	1799043560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	290
\\xb9fa670de6483aa824190e506097b0f4011a9fa1f5d26e46842d6427a856ecc9e7f5f0b19e4fbe93fd0e1d3398d11d6cce96cb948dd60610552ff61625c7018f	\\x00800003b8f5e08e5ce709e3402f03356fa9093ee957128a79b76cce4093887898d731b2685c0962370ec2f6b6f71c63167074633577db2adf456e92d5838c5b3443fdb5e3f77212c838e05534e89dc57ab674533fd3e9d830a2f4fc27910015cc1d6d001d7486192fd211679e5c5336d443e9d29243a192e0ee5279856de34b0600c7df010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xca20f70c5d438b0caa87a7fbc20ea23d1962317f1bf249194e2527598aa7dc2c8f5b2fc2f816313782091af8ac92a885cbf028fddcc24ff2a88527027533960f	1634109260000000	1634714060000000	1697786060000000	1792394060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	291
\\xbdfec0ad97e73d226fd6333530b4d01dfb0a652147bc171ebfb450f9547146de3e48617f3a0674f3a5ae52987c99420496d185a7b32a5edbeecf402ecf26f7ba	\\x00800003d00095ff5a71422c41e5c1749947578f7c710d817ccd5b14bd55a27345898d466b0aa6fd75186ef9e63db9e63d60a7d667609fdf59b53036fcc7de6d29e6563d88ba6aa7b0e28f01238e26ef444c449287bb0d0fdffc7c2f36db0f96ee377f8f6ee0f7c2e56a27916aa509cfe68c1885641df4a9b4c586303a8e2888c652ae57010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9a34e5060b12f682d8b0330bfadd03a6da9fd9483af403e2cee1b5ee804aa209dd8920ecd07d943022b4cfd8974cdb2f0524cc34d9c068a14ecef6471537a509	1635318260000000	1635923060000000	1698995060000000	1793603060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	292
\\xbe5e7b4811daee9651064c6d4c3d91b1b00acf452c3c2b450df8febce456e1cf3e6ef44ed4e21d3d2855dcb92453b1b52456771d1b24068995c42fef667bfb0b	\\x00800003d3743836424cc0ff964fc5950a85348832cf55b8577b66600ba8951d555368a9ab81b532bfcf7c3ec93d5483a9379a9db3065e906c6f6c63f4ade66eb783ab6d02ab0fe37d5c60c8ce7d03ebe237bbbf35fd4468f37457f5802d258b22ce9e175420a8d37fb8b33e8d1c43ea0ab5ddf04cf228e4958b7a319ee5cd48b79be28d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x26d3e8c1179c7f2c8d484ed17f5fc6e3cd97b9a3e579ab73656e8fc10091480a702b23331a2ea79a18f1a71f3e798474ba087247eeae10451c345223a6f4f50d	1637736260000000	1638341060000000	1701413060000000	1796021060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	293
\\xc5ea92d4196a8f9dd9b94a28a35507c387aad5926bc7a5cc0888792c9c06e8eb20aecb31a7b111ffec279bcb1f1fce71a0db7d952ab75a59ffb52b78b307848f	\\x00800003b7c6b1f0960246805bc7dc0a8aba88d5d9c1d0127529d9d7bb986fe81137ff6ae6486e73915963d5f9a381e2eca3a19424b801144dea25a44bfd1f4a699a365a794c9314a519300ec90eb576a31d1899b4dcdee9b36237d18e279f72f4fe795d459d5bbe50d8ef91be8e748c13ab3f251c77cfc130c9dc2eefef29cd03debbd3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x38863d9dab092d4c1b06654c0c0ef8b09959e79295154a49d68fed311a87287dc76b3d2cfec6c11d6552de0f307808b4805a63df1c67da35471051326f935c0e	1614160760000000	1614765560000000	1677837560000000	1772445560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xc7626db2a732b91560c95c637456d03377d5f9647c5e5d7ac3e67ac9aea9497380e16ab84dec9bb86490549747333a0c0e3bfa0fe1b9f98ddd56003bf971c146	\\x00800003990f7a12507fce967d0071537201ea64605a4955a0f0569fc79be13a8c42c8ec44edabc670229ebea7a13187e64838292f872933308b863f0010adb862a2068add81501c646b17d596718a2c8987e0482e005b3bea500d02f7ff21001d61ca4d9f491b2ddce47e9398aa4c5cb8aa9ccaac21e522368f702f4eaa6634b41c4eeb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb6b1b26c0c39a65615a1f994531792afe0abc7ee8d391c7f57af3a43365c8e265520ade54e3acb2f72e226dc32bbc69db680c3687491b060f8ad496dbda1480e	1634713760000000	1635318560000000	1698390560000000	1792998560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xc8628623e54f1defe69be832ace219318fd6c235cf9e90c06309632ca92af877ba4aab75c524f5e90dc34fd9736089c88c5886524fab048bb55182dde415281a	\\x00800003bc71383310d15a5d3c99b5d92cde6a0620ac4e572e5db1109286675151f0e078570589a49e2209e8b26a09007600a1f291d10ca0a331d39872dc69b2887e2872c86db46af986b35311fecbb0c479320429730d7667ad002f6daee360648086dcc40322e36373b4651ecd08e29054f298f19b59bf84be42c12d3e2a0a19b57b57010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7e01a6d718e7473a281fa5b336de97759539225358ea69346b383e8896e292fe8ebd23205dc2003ac8f0f9db08e61051645d4c72c1180b2eb79c6af68ff48203	1637736260000000	1638341060000000	1701413060000000	1796021060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	296
\\xd4de6d39a3967ae695a04984dd4415eebea61aceb092f52f38b4f2dbbdae62defb80c113b6b3e40046dd259b159977c1f07d53a6252a39f8774c597f1bb492a0	\\x00800003a3638e6dfa659c7878412b1fc339d83fa2826a1a33f45ab3fb062d51aa0f2fc396d64cf086878ccc80474dec68bf1c81d0a2cfd3f19020b577077bdd2f3b9ce95bfb12e200761eaad296090f544b59f12abb20a6775ada08491edca3b06d44f0a2d9c212b6a51d0e1e973632445dd28c882b9014873b399fde598db6d2392a27010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf26b03ec05b7d88cfcf7d09e352f1ed3cb37a6c87af15185d09b034a4f41a342fdb4fb97d9b4e97e8890fc47462a44f1dde19150eac03db1578a259559c0a30d	1631691260000000	1632296060000000	1695368060000000	1789976060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	297
\\xd552236a912a832c298348a47e95d8fb1f98e8b7a49f63c58282ce933a98612468b3b0c0172a0fc25dcc0a7b3f0e46f6dc7aee61c5a4652b49e69ae9ff7ea78a	\\x00800003bb5ff0efeb611d6ad9498e976dcfa28ed106b5ddc5099571d4a4f3a513c2de10ff5fe6f04836a513a2e947eb02d40447467820c7d23f9a37791d9afab68c204596e3c0e952bd9c198373a4adab84bea2310244a554ef730cb2ee5b61d3912cd4d691544b277f981e0734a0567b0cee074528c0ed94df8cec7b50a0bd2b058dfd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5f8b9d2d44d29b1625c7114f840810965dcd721ed49fd436cd0d494cc948cbd0766ce355d98b514b972ed2d23b5b65325c48a8079e65cb4ac6cb6edc5ac03b01	1612951760000000	1613556560000000	1676628560000000	1771236560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	298
\\xd8fe9316d94c6842799dddc9ecdeaa5968e0d8a05a0b597f8df5fed96ee08bd44ef0e7ebce59978883608f829505d53c072c4ed678e1d38bbcb60e9279c5c0a9	\\x00800003c0c133ba37b375d4f4054b925a12f150b104e39ef1f50fb9995f5a678545151791191894a95765fc03727ed1dd35664ebc7403ab925f0ae25a9f506666207aa648237a35ebd7266523c0c0addce4cbf8bf7c9668b4d11a8302bd77edfb4411556ebf56f6ca2b8349dabe36fddc49bbf706162d33a4b2a112ff36f0635bbd9acd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa879e020184a92f1aabc78662314f06551f2b9f04d0d3eec7b819caebd25e14ab7eabef5a1ab9da6b5c0131a3749d99c869ccc835767af12ab55aae744f78b0b	1613556260000000	1614161060000000	1677233060000000	1771841060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	299
\\xd8cae03f7ab143a98955620646edcba23ce065d8d3b8283dbb732327d329c2ddcbefdf68b87753f20b9113a3a6fb7a51896f2ed3cdff7cd904c2e849d0ef8770	\\x00800003c24bcc8c6691e7856d3f9f46c6086bd413d4dcea06475ff68fa0f66614b5d7232ed26d082dba12ebe29aeefb7728a6e658d18b347719309032d938794076e7fdfcbf8377e680d4566ffc4d7719b815092fddc9671cd4b78aad5b2f2bab82e1790f5485e22ca6317f781d28fe3773f891a92d98373cfc9b413c9d35fd4b7e1af7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6ceb94abba67c951c491458597d3c199eb20132d5dc9021636326d29e735b2f1924c32c2e94c6f4aa4bc640edde74a15c06d5a073f8bc39ea731dcf214a90708	1638340760000000	1638945560000000	1702017560000000	1796625560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	300
\\xdb32da0ac04ca66420df6450e061dc35c8cbb57df643029d874aac65ae9fcc35fde95a4bdc49eb4fd0410928c1bfe253707fae67d1dd09ef02b10eea96bf65fc	\\x00800003a1a87d91e7fa087b4aa190376df25e625089e990696bcf87e13f754cdb8620b90aeb39db79ed3160c54fe4f9a4539efde7c29dd1a47f9f71d195e75c2dd756cdcaf2bed9d156360018b84067c92f76d36c38e55acab142d13e3b094a1dfcd89fd6d23625e0e5e7e1042be096100df5b2663f9eb6d16175ccf3f72e6d36777a55010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf2d00f63a2c298c268bf38cbbcfb8d763d6fbc543616023e6bd47b169498d9a346d7fa6a00e93deec89951694bd7a070959ceffb7178e3214b82fe19558ee90c	1620810260000000	1621415060000000	1684487060000000	1779095060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	301
\\xdc52d8ec98ab25943acb4d359558e27af3656bd79a4ff857e5443fe0a00a71830844421fbe915abfb74f176aaf1f9f42824ee2c16a764a5a46080b47549f2f21	\\x00800003d789206321692ae5c5de563e884e89cfea0526c7a9830d403496df87c18e4d020b4166150d1217eadb7fefbb1182f72c5d25307543399393f223b85ac264fbc6078318ddc9b3a9188e2a89c8121b54265d1a3f3fc4ccb101965da212ce95609960760a695cf7d36a6c71017a8658e1dfb2a7a1b2538755c83b8206f7a3fdc167010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x77564af4fa3bf2aef46bec5c97606c726cf439345bfa39e00ea2f8150d6a484d9725ba5cb96b7be7a89aaadeebd7b4dbe5196e5b1b226839aa30a09c71532409	1617787760000000	1618392560000000	1681464560000000	1776072560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	302
\\xde5a88e71d34000997549a45c071cdec9a5aeb9a57625137edb72f71efe4634aa1ea6d3b4e22722f78f20183acab169e90993305b903b9455889521983b57e64	\\x00800003aefb51bec829e117e2dbb7ed369505bd0e2dc105c203927d0edb99d3056a90bc90cda5f3acaeb651fb155a07b437f4747ca17db4f533c8dbf962cd5bd0c47b7b710ae971a670705d0bba0b81af7ffcce94dabd2a1b0f0e4822465e4d3b57c90d733a80f119e58c8b5d6446fb76228e8a9ed932de87d9f106976f4fac3f087cfd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x05b74e31073c8ebc886ed9998c46421312290cf85ae1501aa36be74478355d3125afec112f67fbaa13f8a15b76250fc7a6f445daccf8c6f3ed4d1df98ee02d0b	1639549760000000	1640154560000000	1703226560000000	1797834560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	303
\\xdff2a212a996d15e08475a90ac82473ad64409946b40b5f9b102f8c0f36701e877faad77d1f485269e795f512dbf175dc7283bce16554b0d36ae74234ab28a67	\\x00800003b578ca36eb4cb1a7ff5142a09b56019b256be59b80c6c54b78db42500f4edc8107b5fe66f7d0ba1bda00b3ffd54262705818ccfad97ae817fa2b820ab618220db5307166d909c62cf335b803911d1a40aeec094ce3d7d3320a423ec2ebbbb62ef8266c5cd4e2cccc7c0ec06a230f10f8de48b448aad889139f6b3eba762e0739010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd7cd0e2da9479e8763cfc0d85941fa100d4801fd0bedc729b555a792bedd842575ae2f26eadb4f9a2155dbfcef0f2da048d4af53678d7f9648a664609162d009	1628668760000000	1629273560000000	1692345560000000	1786953560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	304
\\xe0eaaabe624851bd0fbcb4e8270c222ac5786662e688d3c804fa029511af9fd2761ae69ce004c7cea06346baf426b929512646fa53045aedf7a17921d61fb3fa	\\x00800003c72b32bd2bc47861ece73bea04001b8955fd61f98fdf2706d69069a10cda7020371a370ebaa3085991d1f22b37fcbd14b4e7364ac31afe182e9701cc69b9797c956e20f098bd49322c0a5759dbe4a9bc79070a4bb785d5f46526d6a144b112b041cac9f05f1df1c9585fcb489b2c976db344afbf96231c6ea6ea1519a186e88d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbd33ef7a2ea4bd7beb747b20456bccf4b3f37a8e24353cc368c4c1ea91b318885df040e0469c44727f49d57c184c3a3c524792e56eb44fe90d854f6eacf8150a	1624437260000000	1625042060000000	1688114060000000	1782722060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xe696c90c8342eb6bea4912e317d1ca3052751879f8de7ef731d7b5f43eb06d55c9d5952cd661fd61e40412cef31a977b3528c4a8d8e630e43135119bec7295ff	\\x00800003d85d270eb4e05badd86a129eef604cbf73208ac21fd5bc90f0b640eea46c134a9a73abd8a868b2062c237d47ee5077ae4fdd1c1d6082580480ca721bfdd6d4f60dfa698e856225d50633c221ea9670e18c184f490101ba57818ac5b87b6713c27f3a4a173f957c82e21afa1bcb9a187400bc2269d22238544cd98397354e9d7b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0c7866ffbe0aaa2e86f542e5e2be955133c4b565399951d4fc23521a3b2da84df74261005efcba2114eca3334f97b8a14004b761ae3840b62f10845611be4d00	1616578760000000	1617183560000000	1680255560000000	1774863560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	306
\\xe7922d76bc5e226adf360dbe38e239442c53a0a78fc0ce28a8a323c7cdeb3827c1417ae17edd68c014364893907fc672ed62d9c28762cb371cd345303dc989e2	\\x00800003a300f4e0af5c4e7bef917edfbc2fcf8d840e5d592ab1ca735bd75dd5ccbe6b35f8d1b3c48661ca047586010473b1bf2f82686b3aa968a3be1f38e5fea4196e04d10347035bdc8ab5743b2ea175304fe3cab40cfa72a4ea5b4bf8e837890e02e895903694f637ee6c9ab4aaf6328f6cc4a0055af1b29599d0a9696b0582cd88a9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6bc82514e96923f86bd74f6a79d4a558ff0e1f2caa60c3e883df981f8c19211b59f7ee2c076d311cdef6db9b24f0055abfb35884922c1314c8944efd612ba509	1638340760000000	1638945560000000	1702017560000000	1796625560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xeb52f54e4d19df4579fcbaae1e2d269ef9a424888fac30a95b84961b959f18ecfba8f456e6160739a78f04bd9884a41f66555216a9bfe45d6da54d5bfd5d3b97	\\x00800003b2cc478404caefb556d1ce0d42228e108ee0156074578a6e5c782ec12c5d076df757143bb899ef91a0fed77663c5577a7b2f071f0deb15a173ffec5ce26db7ea1554d33e8924b938ac93e977cbffd88665057f86a31baba68cf2bbc9256fcaf458a780eba10a11f6d12f6ecac08b4fed76603fc772ed343f97be9c6483428455010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x94bdfd65f715f113c7fabf3a907d3694f2c8a7a9cd82886f2e18dcf96a2aa6a8d29c4627dac0b4b905ca836af056520721e9d69d5637aa8f4cfd46bec9fc1805	1628668760000000	1629273560000000	1692345560000000	1786953560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	308
\\xeda61f2cc0790a725eff386afa9b0c1e7cae584b5a06ba661225878efa5f28426237bb4546a0704b22b0f673cee044193a5c1f2898b8eeb7590e643f7a27fee7	\\x00800003d0787ad0dceeeacdc4c2eb2805062db542543fa7e3f73a9d2b438c0752f4174ebd60a5a3dd94e0b9efccf0a0cd6cd1d55c7c61b696271c19e6b21e8e43cff54f3bac34038ae5424939d4125950285a3f98b2b3aa487ee88f9b84b2f4d0658f9257e98f1e580d8f415e28bf9f1a22daa338d6ac4593e0bc2df40790a71fe5ce11010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe256dd44730e8d616e15d8e90a5847fb0acdd8648fdd14a0c306aed1faf0b60c90afa55d3f824f2c9be9c3d38d10715efda242c3d966d2d3590a463ffcd1140c	1638945260000000	1639550060000000	1702622060000000	1797230060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	309
\\xf0c2aa72a2f82a05cf89be6dc54fa16e89960fc33f833f15b7640b181542564789355a5fd5a3c2aa902adfdfaf1aa8c2cfed78447896ce89016fcb49a45cd921	\\x00800003b3ccbe133d1e38765c087f9a774da16da5821eb76f151892d44a3b646c1e52018d59a06ad9323abe2f7ad66c8c2de119d5620289133c8730087db89d3d6f1b026ecb1489aa6be76651816be1d2a8adc5b5280de68f1e7f5d1ad46d6312e4cca1bbdd1b8a9c95826edfe98a86d47637abd8e2df08e26715376fd3199b64b5219d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5e861d43eb4bcc3bc1f1cc249931b13fb188e3f72c51e02c9040fb3b7a94959a2ca244f2be6e6d5996ab3ec147ab2696296491dcb0f9041bbfd1757166a92104	1616578760000000	1617183560000000	1680255560000000	1774863560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	310
\\xf5ce861d8c4a6e397d874f999a9600b0c760d25d5f2395a06e3042a4c871975714307936a32ccf5d03f6e08677563120971cc1d8f185195492949a5c3bdf1dab	\\x00800003af6d91de712e52b64af637bb4cc624247f6613a1b7af76287d028b3b12a35a08febfc78f5a790c5eda1307d511b03eea581be6310c27d49484b8b016df214d97f1d97e1405b80cf5334b04ed5c477517c4252bb39bf6c0f4a7a250e00436af992fc1dce4467ece49a04aab2c6006160598b5bb0b108607b164e80b702f46afcb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7fb2ed701a5101a9f64f52e9635544b9809c0b9b82b0628719919bc8b6ed319fb502595769feadd73730aee0efe9478ecbb0d1df64869b6ad88941da2de67e0e	1632295760000000	1632900560000000	1695972560000000	1790580560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	311
\\xfbbeb95ee800a4d95c763f08ae3728e0ea3236ea36e33fb3ae438146a2ea92a35350db2d3f3b8408f17037a93a021719bdccf0540b1167dec5eca23ca91c62ed	\\x00800003d22925567ab1ec81791489c7b2949eac841ff2a659858123cccfb7cb8eb7223b6bb838473d4b79d1e6fc2497c43981db89f93ff96b86461494795e521ccda767131662d1ab34727e0bb671dbbab3a1245dd2da4f74869e646a974962b56d9c30c09268a11fbebddb4a8e6d105dbbce15bf49eebd966896529379018ccd79a019010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x38e9bfc12ee08e387a87ded424c3718996ef25bf3a55854272a692fe70d1df9b8b6839b04785b318e5e25c87fc985d4a5f64b204147bd5b657e9cf7bc638e509	1625646260000000	1626251060000000	1689323060000000	1783931060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	312
\\xfd72d9cd64f441a6e4e1c3e59944a6c729f77d43b65612eabc334bcdfcdd2618d209fe28f5ee702d682473abddd42414cd1f65527cf8bf5fac5cbfe326185ee4	\\x00800003ecfb88d173fc2325aeb89e205336c199978a6c558330c274160f5507320de06f023f90948816304070fc7f174577285d8798aa22486e5ca040c5172b3fe59e9eb338332eb7fbef527a69584083a8db8bf22b53e740eeafc0288435238326a282154d11df75d9b4460064d7b621eea0958dade37bad2cec692f7628ae62f6fb53010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x339269e8442dd5b538c341506cf727898f710707283e6972e6f7f92effd6e751ed40e05d12ca4499471103e8fd7e2a9fae89f1990f9a53b0180757146993840b	1622623760000000	1623228560000000	1686300560000000	1780908560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	313
\\xfdb213218934abd229f33434896fa037f17c57622a7dcadee32595fe34b3399e32adc0788d9bd7632b16f792dc6fcde3d08a3499b8d7eee6c9de93707c867d33	\\x00800003b22dbb859dd1ab9226b22013290908dca62d89e8cda24a55c25842f58a5d848176802de56459e4a452e8019fc24d5eb9bffdac92769aba4335a686d76592082902ec86c78afa824640c69145346c4df3315a7d53da1c81ed52789c398cdc5df856fca05a5420955d3e10286120f0327fb243732fb0b2c4ca31ac915d662d85e3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf7aec4ffaab1dc0011ca0adec166072d62075d8314bc7a7672bfe9a9b95fcaef82da6eb51fcaca2c93c837a3a825f47e6ac81f62eb460bb784459348d7646103	1641363260000000	1641968060000000	1705040060000000	1799648060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	314
\\xfe76ed8bf12ba32397acbdcb11e8eb8b9f7a91ebc7a3d4942890418cfdddd894d91923ae3fcf1c5282aeaccea13fe62f4780daf1817471e80b58e77cc62781db	\\x008000039336e935bb2466bf792a84b016c39b4d08387ef8419e321175c3542b123b80cf1db5d685b471f6305347ace7aa0082a511a182da161284312994d09d0f2ddb994ec71db08c7dd437d9b93bad10908971e116a913e9be680e6931c4571104962d1d22264cc9c749deea41e70d302fbab88b35663159324da7f687923db0266da3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa514d06bd324b5c28c14d08e51afa6730806d8e9a217011fe534776f5b36119e94bd368a7d93a4ae082fe58cb64b14935fd77ee9c43ddf33e8310dab85ae710e	1624437260000000	1625042060000000	1688114060000000	1782722060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	315
\\xfeba8e0ea9675b34a08fc4f5258d0ba9f9e87aa99cb6392280486572a6861cffe20a3b18b054a7f2be2a8db102a3b31f8bd2c0c27d3498b38dba8501a1b2432d	\\x00800003d477b544751e5e6a42696083c49f9601d10341fda13856bb29a5df7901033720415f7efb3eb45c1f01752fe0fc44d7761e4a4e14d4914580587b833b24998cbac2f4f54e495f61a7ba1155cf68d0ae0ba285aa49dc084e1574a058ea15bea9c55e008069a40a0976f880e9a15bd73637136d13ee6c0d15a1b078b64b62f4b397010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6056072740416818ca18a4253d0311dda9592f9bb474444cc023facc0943c8fa98fe95b4238f48f3d6cbe73aaf1993834eb5ea874b8233e95409790f575c130b	1637131760000000	1637736560000000	1700808560000000	1795416560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	316
\\x041fabc7ba299c45e29c036875ec5cabbad125e3d823fc779c78b5d9398d72fcba320d27fc784012dc485bb703880ab7e06384ede9684a74cd496ab6af0f68b7	\\x00800003ddfb362e24bc10db235e37f3872f0b33564ffb5f0942338bb65a5d7ce00f0e72be472899d3cb16fc1c1761b583e456c32d500accfba1dc8746bfe3a1a008a3b967be418eca10e1405ed20bd3af393ba1a618e06182db52e22e089f7fdd17054f8a59661d5cc8a35244ddc08fe2fcc1f88f37210e3cf520baf21e9d5f669adc69010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6d0be26aedfa1b2bfb68a326a2cca8ca1c1afb989dc11c222684c3c7caf3038f63de6c73d65e063e1ec54a1f6a44fd5255dc27cf5d15112959c7aee47cec7505	1620810260000000	1621415060000000	1684487060000000	1779095060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	317
\\x058b6de74f4ad6d738e69b4a5aad86794f0c84f8a65e14dbf32d3518ef78da260e2183ecf71ee8f2eb30a2af98f4970adb3868e885570b1103ddfe22cc33ef83	\\x00800003b45589f92b89aa3ef2345f28800156aa89751a449c07d9b07cfafa11c958a9bd85f1de56ee4eb6509741118f2beaff4aae446f80401a716c58e0859a5a929d58c9ff1b619f995f3694613704653460069bbddf200fe0b34319d0ed64ea46d7135a9c1000c2c3176686490bf10a81d56bafefe1a2597ffd9bf44d16ac7837882f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x18f66f591759aa195d41c4dab9d340c85a8f8a71b03db5bef18e200e8a32a5022bc02579704f32cac0402d4c1322069f3661cec627f7b603d5b69e558a4ad10e	1615369760000000	1615974560000000	1679046560000000	1773654560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	318
\\x05734c43b2823ee96678c73eb4c15a83536ced6c55dc43d00bb1e9af90e0cddd3297f586b30cdf9cc6007e7104f9860038e5f28762b1d5c6fe50038ab95faded	\\x00800003bb06b20a8da9d271481bba4533854c2bb3e21a50aa40060996670d348df45c8dd12689f7f5479734ab374b79c1b8779b2dd2f2a032e5183c38c50587caa8d412e91ee43ba5e51df52fa2710518903dc54913974ef6a6b3f21b11d2383d9f62ab8af76b055ab16a6800ef86d76894c8e45aee398213fc552f10178666103011c3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x87e43a59a3e94c7b17eef4686d5a7b88832aa5e7a4d582fd5446b45a8877a73f6eb054e97a78c489e991add1088071fbda36400c678f67f7687acfaa3cc24907	1640154260000000	1640759060000000	1703831060000000	1798439060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	319
\\x05e3b0e55323faa425d7e27e05bc1585f7c24777622bef050e83690a80c5335b394ba8ad29ed3f0c87c882e06df2296afd90db5530b2e00811dd00282b3b4dc6	\\x00800003d20cdc048cdc5e1d9d0a36efece1687905458de3a4141217056830ea0acf5a21c2801ce4c5b8de2cd75214cffe146ae46eaa86c2f4df1e3b5cf7962932027f5b75731897f03b4df25307103ca9360b8753797eb2c0319a7c4495d3b53325b1d721bca5e718fce17740d1cead3b5466d44e07662ff6eefff80d9d84d8c421b6e9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7eb473b5b3940ca44009caa0a8dfb1826a1cf211f3fdcfb2cda0040e47d58f3d8c03ffe1ed3f24ca3f82c00689ef276d93c640e1507098c6967eac46b0986309	1627459760000000	1628064560000000	1691136560000000	1785744560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	320
\\x0c9f69e6bdf50f1298296a53ac521028bc0ef88120c989ec9ba4bb53001c2dc4dd9bffa35947a878de4bac277e570acf8d24206470ab872dea000ee9c68e871b	\\x00800003c2241460cd409911c042e61462beedeaec8485275f911d3ed073092b36fcd72e1a35fbb63c9b9c6cca6592669854ca4233f569b168e62fcc4afb5d8b28a20a953ab2e68acc13e0810dea08ce1ef95ede8b4763d2391c264371fa2938a11391a562b24162dcd155f19456978fab984f7e87236cd7d52b21af87df9db9cee989bd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x79f614ec5d76d30d0b1498cacf36b4812d7dfb490f492165297c482c16327cb40e5aae605d6f34ce9e369db473bfe38f3ba28ea90928dd06d9a02c7851c9850f	1612951760000000	1613556560000000	1676628560000000	1771236560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\x0d0b472d6f0678fde730492def62655e7d26bb6fc3b35e4f973a4cba092563e72d48feece1cad8d1c6f535564f18594bb399baafaa83b4382a777493799b343f	\\x00800003fdbe569ca605d72804ae7b524426549632f72a884b1aab9d4fcb37be6efcd6f1d57e2eede284ec32be622be32e141f19c1ab715709a4ac1154da1b65e3f1874812b796d59d2a208518c10194cf0ee16dac152a354f3ef1c49ae5a5000e95ab69d179581d6ec280fde7ce3c4423ffd23f66f2627d4f5d5386f4b7e891308fbd9d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe80377b54700473d25886807948828790d40b35f01d0df738794a4bcbf527b64c4b883def31997c5d685c3af5f8420bc333d02524148e94c173f396bd12fa00b	1640758760000000	1641363560000000	1704435560000000	1799043560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	322
\\x0e6f685e6d270103e09f78241f49a74c11fca230d8247e5dec1c57da4b21663a22390a9c53d390e8e91c73aef548c0f0ce8016e4ec97e38e6172b55c4689f884	\\x00800003b2b73c4ebaf066179c86abbb08efba843d56582f69c9d1d4825d27291f80e01a7b06c1e3e68c6902dcb51699aa943fe3961e0453f489c7ebe1d2dc25ddf18599cc75966f84476cf3e1a5494cf80ded2ce8f3750193236909e1a7a1b88455114b86ab410468ae26b70df4c752af8d66adc0227bb9553ec39596af2d565334a797010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9bf37b15c3f38513ada7ee978e84e54f28407261cc28daf53efcf54e295847e3566e4bf315574ede030b47da9c87c6a6b858c2af42bc47bd5b3bf3aa2df7b006	1610533760000000	1611138560000000	1674210560000000	1768818560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	323
\\x0f3f7c8d9d91f8b315fe36e0ed6e91585b3f6e43a6a4daf4845565a8a55491560445f8d844275056b5bd65af5b058f2a4534750d8908b3a7fb1f5ea641bb0e93	\\x00800003b63149fd8641adf0053d3c9a2f5d160f22a7e53205be41fa6ee6440f05043874a631d28b0a2be8054a460a46c84377fa312cc67de5172501e5c125d9819e63c8f518155e846d84712b9820ad2eb774b2fbc2ff21752d14aff602d2783e8ab2b6f87e5e23725763b2b45f953860db3f3a1566c113e3d3a47635dfe9c75575c897010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8168a0dbfa406ad06938e411ef7b464e3fc58545c532d59fc24715323946c4c20a16104b20e859d77c2bdfc873f7e9cecd7f995f05769fd8362b971037570d04	1634713760000000	1635318560000000	1698390560000000	1792998560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	324
\\x1077e251d541ae231b4e236c0bf513f59326ffc2565b07f8f98b6413e997ccdfbfd8858f84f376229496a0cff46b2e011cb118dda6a81787a009a760a953d6fc	\\x00800003bf3b61ccfe86521042b48e166053bb46d0cf1b8f8dd221d94d078adaba527b4c52c58c7de46c4cdd1b439d6b8ff47e80e3a81339c52d33e1f94f79ffa414a8c019e308389dd8532fce39c3bb89f5ca21bbef1a1af874b59c67117e285c02a24f3ac7bec6515b5bfcfae413556d9606dde7a0aeec1219b68dc26e341b66bd3c31010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x89bc1779ef390b3bfd932feda19fa26842f793bffcb19bec4448d457ccdc54c4ff52168e0d52cecddb49ed914e27f15c394189c6e35ae9bcac98f109f5b1c504	1623228260000000	1623833060000000	1686905060000000	1781513060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	325
\\x10778221f83476a473d9658ea0d6a4fbcd532fb6ebeb3823e5aabb0321d77fd7aab3e886436ac73e27c7edaf6ab75ed2edcebbba8fcb1b34e229afe7b93809b0	\\x00800003a9e0972aabeded33f79075781abe6144686644dd5a765705074792c048371c60885844711ab3bfe7ae2ba43ea5f0e2ac13430c54099e9f8f6563880959c1490bdcc9dae5603113b5b6c54ecf53056ea7d3a02dab79a328da6ebca10adc29b43d0333fcab57bb0ea2b1e1e5a393a51a3e5f9afe574d462c5ae061c54eb10909b3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x64d5f883faf84f78816c25e3bb33a51f2474f4b487ce7aef66e5c548b0cf104bdef558c446ce98776a3f925984b51c72d4f632b877c851e0a35d5389d4d2c106	1612347260000000	1612952060000000	1676024060000000	1770632060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	326
\\x17c3ad9356db749540291046f29560a2baff08407798e13a240f98a9d4ba6b5c7728e5666953b72d314057fe15a6af9351e171be54cad08a78eb1582bc00bce7	\\x00800003ba792bbc0209c2c064856615442609221d50513f1e2f423acd3426e4a30411dd797f83d4693267c1f457b61ed3533bf3422b668e7cf22018d38f2998c584d305fedb3d1a7e999650b57964705b3a78df5ac64d1150242f419e122eeb889126f75b7c5e5a7fd4234e3dd9b63eacaa04699c24506feeedbaf1cef573764e7d890f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe4971ef5ec0627185c6a7d222fb30b074e41b792f12010233ca3b0a3c30ec0b45eaac0cc876fcdfe9eedd4bf72274bae06a6f93d125beed8e93acd9317566d09	1625646260000000	1626251060000000	1689323060000000	1783931060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x186774aaeee49a7bc921189672ee546e1c7d58a75d7ae1c9cacee8382e48dc3f98a3b10dd9bd900d684ed93ee1f5e8ef61dcc6c43ccfed57aeac940a77634b32	\\x00800003a3e7e77c886fd2a044b44b8169ae8b54bc12cf6168e5c575176549ee4dd411187795ba248a2fb725f831b8bdec8d1722c91cb85c34fa89148064e48fc4fbda9b270a19ecd2a56741495f109227d4f3edb9f5a6caa8dc71a6629f78c868c4501e31fe2f6df13484ca829fb0cba2eb5fb4ecd78a67792d8e53c016e258bfcb1d21010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc548916a79fcaea9441b19c3c22f193fa8062c2bef36b3b9266510a54d35d238cb2a78524873eca53e88a130288d1ffa406b69b02916028edec83392dd9ce809	1613556260000000	1614161060000000	1677233060000000	1771841060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	328
\\x18bb9793efd663f85072e7d7631237d4d1e3ed6049ec17a2906a8688d174789620ef310c7b776503bec30c484fd6d2cf39fbf8c8b94f5aaa8a06beeb9376884a	\\x00800003cbd303b4868e574f99a05f7770f6bc92cde23e908c7d566b7e86a5181ec31441b050c5a0a8bc0181e7b9807ac74b8f39eac1142d96aa560d5645aabec906734d1ae3e4291976ab561763aa524c37f0734fc609c8ab2f301d9690c7833ea63a5f2b62184a40d685050e6fcfbc1cceeef21dafa521d2f714643b4ef4c3507cc8f9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1c30ed07702ccd92f12e71b9b22225db89f014a1fe63a4a5af106780bc8b9d5a55cc992d3df3a1d8a490d0cc02dba519570b51fe3767aa50f0918d3245a6ad02	1626855260000000	1627460060000000	1690532060000000	1785140060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	329
\\x1e571f68c1291f455ec8893162f6e8cb1f059cc6eeb8f993c5bba8ae3c876e42088b6b0ae5ce3a14cf49e2c45b42d1fd26026a9460c9e48d1a5d8209271aa689	\\x00800003b95208bde9e029d5d9a35900ab5406c477dceec30c0b1d9914a657f8b63ad23b153ad47783ac6916777006e02b107c14a395b9f66712c29ca89d9ccbd969e4b8abb92a18daf1158c06d329455d2ee73351a93e391ad73d8202e24218d1a3f07c96e627cd3d209f41d8bda9a84091858cb1cebc66b6a27fd35fcf345dff5ae4a5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xab7bb24ae6802737f01d4b52952b32de970188af3817e6324968b92e997d5d405cfafc11e83ed0b2dd6408faa410c97b72ea5c1856b5acca83b2a5b230303109	1631086760000000	1631691560000000	1694763560000000	1789371560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x1e5f3a6cdc4eb99fb9335f20449b94c89b03e6cdaae6537e9a885dadec17f6e77b633c4e0eecdb85466475c12f445d32bbd504598d0392af41a6c4c40c8d56fe	\\x00800003b7e2726a2db865222cd10ccfc2350f2e87610673477e3f34f1cd7e73e14fd8ffb58ca36a9a8fd34d10bb9b0d6a49306cc58f8700d5728b2570bb10b3517f87bdf727365217ea7e76c60f6725b8508890ef6c1e5627a69e56b8a4fe7342395b290bedf0997dfd79f4f5a9349bcf27a06a8b611fefde42ee276c99181de42aaee7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0354c870a56a48c299c84c23cf233e18e89e632281b8cbf3a27fea97f2d846eb52ae62fe8bdf2585aa54f8932253bf9c2ad1d9a3a939d25dd9895a24e5e6aa07	1619601260000000	1620206060000000	1683278060000000	1777886060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	331
\\x2397b1962d44d355804c92cc7ed6f0bb34c208e28020ecb293d387eade4ab0bc36814b64b0c6fea032c5e2e127743d48a51209f5b3a4c3c524898ac4c7fb5fdb	\\x00800003bfa31233bece9d7296227785e48630119ef912ccfc5a5273d9a90a39ca73e7117507d3f15b2f8e0a826f4df8fd15a8e0ba6492bc0a20b4a0fb418ed3e023c3a4c8ddee3ffc4d9ebbfc0127ba81f9082a55d27bfd4cc43144d57fd0a7cc363a0bac9830415a4c717d5e19d8af8e2afb75ecfb0d58373aa8d75336481fafac685f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x73c2a3676b29057f0d2e67118a49d097cc405613f83d3043833733f713510919cacea12a6c6633445acedcf203ce1ac5122f61b604fa629d407e00c24702a10d	1620810260000000	1621415060000000	1684487060000000	1779095060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	332
\\x2343880e5ae24557f44b1284c205e7811c31ef16045947e691777a7c6f8ed0906f7ddb472eef8ce9176ba4daa1a62d67e75c91f3ce94f81e3018969224bb04ec	\\x00800003e29282cffa9518d182cca732c301726ab4a054e669b872443c5ec9a3d29b4a80c801d2e2264e1d204d0bc75841065b03718c15099f9140e8642e4db53de45b6835e7ce113c50c7e312d1edf0a792968bd01718e260324a227a6170c25ab942a27b72e84f30120e9dc73cfc10f93b0dd9017cbcce690a85d31965452180e8cb8f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfaa79512e721eae5a194eb961178819c4e707dd81928f3530ed7377732b26dc0b700f7df399c6a55e1d57bd18a4e6945119aac0592498d2d0d88dd8974f81b08	1623228260000000	1623833060000000	1686905060000000	1781513060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	333
\\x250ff6b89de31c09356aa0781368267dcad76a7f5106de48af24da2adaad50580fe8e8c2c6c84750cf674b44c8575ea648e5a35ca33051f06f58e76aeb591294	\\x00800003bfd8e7e40162b8a5c2095ec3ce0d79f7656c8d23ff84297467445093c8c133e4f1b7e497c64d0e112c09c8d14a1cc4d01f46f5b5a605c9393dd00a09ed28b0f778fea571d18a36fe1134d5fa78c3f8898167ec336249e425363cbff38cd93c93556f7b27716cda6203ea1ee8eaaedfa2b3bba333c01346feca2524b63f7e1931010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa9d9cc98bc977abca509c9e970ed5fb969c763229534a5e07eee45cec2482dac9b9cf23031ffcac2951ced5ac6419d0dbf716ecf83901a3390a1699480995103	1637736260000000	1638341060000000	1701413060000000	1796021060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x2677c3d60efb9e8e689eb56c60b5c172766d53f7122cb7a59516bbaed78deac978a6dd05dfef061363b2f887a53d02a40a0fd453a71e1114246d29ad9285353e	\\x00800003d6db7411dfac98c54262c71d689663b54c7895171a1c8158e00fdcdb9756d1e44f0ef38af90c090e421d663ee3f40b66c0845d443e21ad026fc6575b3483ba659de1994af3674fb4471a5ee1f930c7927e502de0ee56b95f29f141b180ccaa0ef1e032dd7e9703aa32e0e77bf5a9f4af3dc0eb6019bf5b47567241956e9e7f23010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3ebfe102439d48f76f292df9bdefd1a30c6f903ca5c1d51c7305303f7a24f632ee848a2e81d2e26eb602abfa26d3d57d7af874b317894ddf6d5b92bedaa7a20c	1621414760000000	1622019560000000	1685091560000000	1779699560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	335
\\x2ccb636ad7e1228116f4d9c0f0354c4b2fc3b75faeee6a4e5c013c0b03131349607a1618ca7e0119cae1c4110dd50b97fa333723be379c769f2e27b2ef689751	\\x00800003bfbc91fdd8d8e10f1b83366d4bc52afc5ddeeb1919757b3c09d789dcc27dbbbef114723fa2cfec91bb7e6c8d579f80ec45687bf353b6c5f0bbd8f7801702ab6c029778803002155c3d321a1ce88592e9666f6cf47d8032eccdb489350e0e85dcaf77ccc6fae4198b63d0a7b1ef900c515d20aaafcf035249299665b25fc36ee9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xfe33b74e70cb370b69381cd80382601b67333df75f8938a76d2cfc6e1f02983fe3955c5691cb0cfd46b6d9112790e7ea0e05848209949436591b043224d6020f	1618996760000000	1619601560000000	1682673560000000	1777281560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	336
\\x304baa51187582457afddf750014770032f61cfec5d66079d8b1e41b7378d0b4d33132bff067ea1120a92df77870248a054ea496545b1ef485a1827be89881be	\\x00800003b1a463217d8dd44653e44a4903dc8b844b2bc79ad7d83ed7c124fd08cd0bb4f264bb21f360b9dca4418fe12727f260fa0156347d209f643f59998f3a80de85b8f5fe9b2c876b7173408b101bb72ee4d81050cce10b419ba68a79227bda16d536a4344b7e842b1548f9717ebce6e34b90047db019ff3f9f0ccd2f865f111a54ff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xada01c6fce62edf347d96675c3961f8c6840efd21abc5e4dfcc3457ffddaaecb91c07538fce06101ff514dc8103d4dfd2521c16a2576c3763666ab9b77a9fd04	1620205760000000	1620810560000000	1683882560000000	1778490560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	337
\\x38b7086e6508b279685d9648ed6a0017892f7d07695e068a9bffbeadecb5e5bc0804003a26add10aa98816f0e48c5b6e8febd43ff7946f6f7af6ad7c716d5db5	\\x00800003cd00cbdfd929af97e9081dd4dbf14e08b2372cf41bce63e15b2f794fafa3696a36155f7b7692bc7ad51f1e88e3f928e0ffbed699b78cce5e6e62018a24e717076157106133376b961918b192bd316d7cdba02606defebf700411e6b8ae6ded7ec30455d3aa5f87978158055e7d9da391726b0bb238db746a9839f82a02e73b4d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa58274abb2abf3c76082686c90b1aae712bb9abccbae7bf74705075291b8ade3277166f9b11857440de47099c280ad5d73ad54e2d56dec42d0e57a312c2dcb05	1627459760000000	1628064560000000	1691136560000000	1785744560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	338
\\x38bba7b93a076f74b7f1fb1e8863a4dc87862678d6ed879e123f3977ed8f24174fd3a1333378aa6e17692043679ce5869162c97a5a6b124d7ee0350afe52be0b	\\x00800003e099c73a75c005e571a452dc128222d4d85b2b9fe1b55b6442e4b1ca5e689e27ea80f38625645b1954379e31b984e477703fb280a525c1747010c297065bbbe056389503f8f48b462756e1fd11ab059c1186b695b8c02ebf5d76823874833dfd12fb8e592868176d47924e21bdbfc09eebc073ad5fd0490da00a324ebf82783f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x90bb0376fa779e77acdb2ba137e50784b292ce52a33b36c2b29205510cba9cc0ce8fc6c963b01dc694525a0a1bab0ae9a4fc807c2987093bb84c0c8a2e4f7c0b	1639549760000000	1640154560000000	1703226560000000	1797834560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	339
\\x3873d6f8dfbc7e5f67be3ed63f040e8ab5dee1d46be1d6787d71a1ba0789537d88b293c96d796ff10eb17b2bc08b91680049c2d81abafd1ba0d080817be6d421	\\x00800003925d4d70ac41e651b2f921dfef5d5c78fbe68d814beeebc16e968914fdc86ccd8bfa008f8ccc6eac2185c9b4f3d0bfadcb23419a42c0e18704bed682b10459961f7eebb07df98e3b7f267f5623172ef550466cb5018614fb8abf78bd5c9f20645d27bc4857ba2078d161597769499825a047b4d0dbc57d0bca420df11e12cb5f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa6c0d165339197074ace50d935cf0a13e1ec3e04d0a099c42848b5b7fc278d060c8c546b144d6465235d7ac69f0c718b54499b7ec917ded933b3896430b27f03	1626250760000000	1626855560000000	1689927560000000	1784535560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	340
\\x3ad3033845f76c4866c1cf7a7c50b1114d905171f2c755d2da8713c97c966e423eb6c54865e444a500af499581976a1a6a65e50d91bafeb16ae01889eb006a39	\\x00800003d78dc209ed4496575e3bccb0d3ebc754d1ebac68a18d0f15b116b6a398208b221e4ad0b341e47eccddb413c63db356654661683b0c2e87486ba0837c4b5db5d896825b9a0091ef24af1e640bda98c5b63e472b9d84a48601efb66c6907512194ebc7d2d1a7d32bf6c0e15fa046c646692dac7c1b13301b38c14fc97c31925975010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x49e34bc100ca7d8e60cac021d1841dd20ed0eb54115f28e3bead9c60e175e5913c24d1cdc40654aea3f90442b307a8fbc0bf0bd8d812b64f104a3138dac94304	1635318260000000	1635923060000000	1698995060000000	1793603060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	341
\\x3a2383ddd207b541e4c1d6d31dc96c66378505d908fcedbfb770f2dff07cf742b6f9d486f1acc7b6f30db62383baaadc84f8df69ce3e8842db1f9e0c448c619d	\\x0080000397b71af0c3b2c080652de68e29a8ba1f1c91c5a8d04422787017c58f146a25ce4af79f5263a4647ed589cbc5858a6fc3610c7b27c944543d479878c8b0659dd524868070c7b09e4c9cf1b50f7b7f0a6afd40ac8bd3e161449d7383c2649736312bbaf4b1c59c7142b12242cf1c09f49dc266b7f80ad640944e55ecc0bbb033f9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5f6a28e88c885979856e4ad5a7796694905a6ca83607e445b0b170744ac6703986a7b6ac5b06ac5f262debac6d218c800da0db60060f4fa05fca0f5965c4ab0b	1611138260000000	1611743060000000	1674815060000000	1769423060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	342
\\x3b17ebd823b98a6d66b41556002f7c98aa511d1111f6cfac642b60363f7d872512312affc1d7ac3328eca780bdd633e52d6348386ee2590666040e782705cafa	\\x00800003bd04035e7f9db6ee5695af8e0f3cbfe62753ffd4bd28212ada3f8997f7ca93bce12d96e5492559c49a27000265b4737852b5eddff49cf39519655ae3eed7dc68c899ebb93e6fc4c9feeee1fdf02dd4ba9a36f71c36d43aa84869375b21a12a7188a241c764eaab91488c4fb5f502c9973a06db3ed9c4a6d5211298062bba6e61010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x641a43cf98d5f0d7e3d1c6da641ee60d74d2ab98048529de31fa8bd32493366328bd00a716363bde2227edf0b3e4450df08f1d82f3f058e12071a10c03b1e90b	1637736260000000	1638341060000000	1701413060000000	1796021060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	343
\\x3c476e9a6de51e85be80a973681861ff02d12df2448483d8a8e1a7bc83808dddbc069491be0bdf9bbeb6709678c0351241d895edd65f63f5fe577cf38f1dd06a	\\x00800003bbf1bef78f88b58575fcdf7e26a9cf164ab269ec70184748f8ff8c8618ea35ef88975468936236e07e77b6c09a098c853f9709ff3df64c1e38e21639f4e891b8cc7ed68635fd4a1e3e2af530a837a3e90bfc57ea5d2342aea91586a0712881688fa796f6d6dfb39fb4a6734679a371a8f1e2b0579c67d5dced6a755412d819ef010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa94fcfea4e54f32ca74e2a35f73485e67aa08bcc52044d850ac42d6a8ca8679d3d447364141345b3f0acd853a5d1e1f849851a2d257507c735454ac4f556c107	1632900260000000	1633505060000000	1696577060000000	1791185060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	344
\\x3c0fad15bdbc5fc67c76e38f7a28c280768388b672c84a74d053ed6d53bb131537af8d1cef896d9a50b7faf02f49f281b761aacc14f8246b64cc8f059bcbff36	\\x00800003c74a68d1c00eab5a24d55542956e07fb247200d1c2bbe3ee2b6d6b4e06e0cb1445283c0752e036b79955538552a741daf891cab6a465bfd1b410552a71f4338f63b5185ba2297e5dce7db3629e6bc306a6e396c05c84c65982dbcb70e47f31cfed48a68403185d05dcef714b178a74af7831bdf3136d20618041676ec0f284fd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xec0c1a981d4878be96f0e4495930dd1294102f2f67d069073a84f8a036c955896d8fa124f5731f6a9afb81c8a1647b5e2da66492a724cdbd51d4674dbe029f05	1638945260000000	1639550060000000	1702622060000000	1797230060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	345
\\x406f2b30080ea3499bc00a17db937e4a46c0ffd0af650f4b32445223a13ab0a18de0018c63293053ff6121d10c939b299c756766ac0d2b245497a52bda1a2602	\\x00800003c2c1997c4745af65a0a9240ed7798413857e2b968b7e1f1a4b4ab2d25a064b887c97cc03f8d46ccc0016b6be7dcb2f13505f289a90fa7a6ee1ffc49feb7118539c00dbbc56cf4e5b2fbe53a8ee5ac49a2de2ca4232a998a17728ed4065a1b5549f18c19e83bc320f585ba5f2d9cc3b75e9d4d3eb1e64c57c4c02d4ceebf0b729010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc3de7d140ef4b981532d12ef42f5da9cc476b3730ee18ec75181b4a5d16041110afccbe10cf9414f5c3d68c60d64e4626c0c99fe3958509febd1f2fbc7acfc01	1635318260000000	1635923060000000	1698995060000000	1793603060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	346
\\x420f86642c40ad28fbd0c9a6874a9d154125ced7d468cf7986ea1e197a8d5c6368136888948df0d7e3f4841fd55d86e06624adceb58eda0a5eb912002bfeedb0	\\x00800003be2fc7f673c959c4d055f563f36bf502d5ca2569a9c36f966bed14741dd4dcc74d8d1506ee5afa75c461d021478ef2f400eee3111803fc44c517faf1410954fa288b580d997dca85746f224e02ca5565a1e87dc2de2eea610e2a7204983d9910005141925d72e3c1aa4f8e2e12f9e5bdec1f7b3d22fbb109d665de5d0c80e7c1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbdc6deef24b0af635c38e6e0a8ed0b371e3a533c4591ffc8de40142172c42d0963785668c93be8b2b1c2d6255c75815a06ea34df36ba6239311338cbbe0d6c0b	1631086760000000	1631691560000000	1694763560000000	1789371560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	347
\\x4573bbdedc626aeda846ce75e31005dc2993c583ee12ee1b22e817333080e72b2c89628a53ea0e573a199a6f092b9d5f35104ff76994e6cc8d3b4d391d5ea98b	\\x00800003b7e940b532984c2936996dd62aad731f4119a01d8bb46424deda6ed6405011118befa6b7aebaf6c3b22420ab56a1e7ee00385c7f7f993c633603806de9c439dff9140d838fe627ea224a1cbc4ceaf2a7261c5f6147cd2591778ad79efb3dcbea758e3ed9802a646f7ffa4fadbfc75408fd288e065cfd165dbddd89aa9c0b48ff010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9a0a7c5fdd31e0cb66494c27321710a2abb7d667f0740c8befa9eea10080d2123ba0dcb55ea993e67d200510d44cc36df7bf18aea42c73c67c75a19347e9790c	1631691260000000	1632296060000000	1695368060000000	1789976060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	348
\\x486fb6b8910274e39bec59d6eb22337baaf7138a937044ff5b7b56fd4f15a443a658b1c0828c2c7e8171c74a6772a9de51268bb841ed1d20c13e35331da8eff8	\\x00800003e9077197cadba2ee25c42491e4bf185a93b1ec7064544c61c00cf8baa8c6cec93714f1256097e378bef7ed02526ebba2b4198a389c0e16763bd212e97697d6a37bb4c50373beef72a88394adf019a4c7e5ceb371a5d2c0ebc695fafddb31fe03f73e7ba5d53221d3490d878cacfa678567c2be9e3549388057159ce772532817010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x619b3c0cfe202e432675810b4832dfd28f6bff6a3587da4ee65cbdf4c9c465aeb3fb8564bd0ab5b54c3f42eec46ad772ef095ac2ec3a4bba1d010997e457d802	1614765260000000	1615370060000000	1678442060000000	1773050060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	349
\\x4a9f1adbd881a31d4aaefbc2dfd16b29831b12cddfe524ff97efc9e1e96fb97bfe123909600921fe408f35e2ba4bafbf10aef55a4c6ce149cd06196c2a7fda7f	\\x00800003cef278aee89a24c1e62accc0a135de31acc319abb974ac3e115207098065f29b43763537ce21b1864e486b6516ddaacd2e9a0a690e682f1c531f760ffb84a0248cafdff6849a28de81e69e93f702382ca9a3e19421af26b62ea7870b3681004832372ed001dfdb8c938ea318165a368b9f05f27214e23678250a2ec8056b6f3f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3a3301f3ccabffdd8c36db198d8c70d669c12f9dc3f6b4915b656ccde966073c1c45a64ff8cbf5765a504b0656b694921eb28274f549e157e49a8a62c5480004	1630482260000000	1631087060000000	1694159060000000	1788767060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	350
\\x4a0b5555c36a1fd97fdc8ba87ea2b42177218ef8655983d37c9bb587434db6f2da471208a40b637871fae507ce4ab35add3ac9b89d9a4076b2b7b66181a20972	\\x00800003b2a8387e93e65d9057a3cba355be4096868a40c3b7cd6908f9c0b2f83844b4d19173d49dab86c130a16e3fd1464ee634181c75c450578d40459cf96263cd1b3294ade27f9e168f42614e3b65d8926f718ee3124a4582adc483c251b5ec57b0addd5fc68f2d83d8c387cde76ed327ba70410bf1d8052f3daa18af777acb22611b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe930acc5efc58d3aff1201a88e7a938f6908ec02292e85f7062985abe5d53147330ab91edb8aa77c73002d85d7f871aff14cdba1417d9f20131eb44f4525d800	1632295760000000	1632900560000000	1695972560000000	1790580560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	351
\\x4b1f3e6b8bff89a8973cabcc221e2f15d2b25c8170eaa19d36bec7efb8633700ab3207a53025f8c2239f3769d164b3d37d198e6e6e114d9cc0e88a5ddb391b10	\\x00800003d21cbc179b63cafbc6ff2cf850309384c2a71442b3d59c913f7943178ec97a44282bcc62f6430d5f0712e91053c1a11ef47dbb5e075f2bf3b1ff20d7c3012b97bf6810604ab78c042f6c247d9068bf65e4fe2d7b413d5edc42bd96e0b705f3099ef881852a14020328f104fd3ad2c2f25b9f7fc98953e28958ed7a9934b2a657010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x45f8b9afb688269857188369ab00c890d75a0ad1e51b1bb2e1eae78422c1a47dcdcec7cfa7de5b29f761532d9b6f4d6c9a0cd6b0c11e1c62549e2bf9b854f407	1619601260000000	1620206060000000	1683278060000000	1777886060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	352
\\x4b9b7b2a809aaa6e51e49f9cc12eb02154a8dd3ae2c8795b224f7be4a519724bb0cf7ce952cd94a67bb4d1b21f74fc1c27111e369dfd1528763bd604a7182ac8	\\x00800003aee65006a49208b301f7268b197ddf936bf5ac2f78c271c639ddea1f658bd3d2b391ffabaacb7d17ac1efe2d855db0484d4870bcc63cb0ebdb85145b24ca6bd1754992ece0dcfadfd9592d61054ed240eee86ceb2109e12c607c27ba8c7ab47eabac0f44bc7212f32350f49f9261873a9f6cd73d74f4cb6014f7d609fecd3197010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2a778e839a3277bbb39824007d05dca83c0ed9c6ebd3a39bee6c17fadbec1a4df2b7acac9bb8885e32bd1dfb687f9f4d4fcd053eeb3dcd9f427f864c922bc306	1611742760000000	1612347560000000	1675419560000000	1770027560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x4c1f466ef5e29dd3dfbbd5aafc8f96ac41c8b47685c397bfcc37ec545b63d718380726c6a0fa75458f596c3a9682cb210ede5474fdf109957d41b5b9eccfd5d6	\\x00800003a73dbb74d98952067d91bfa083afa51dc86ef322cf4b165ec2a1ac7d1c26fe6a1ad1fdeccab3d206e197375841c796875bcbf44ab880b819b42e7b4a675f44d8af8f534ea757456d4842144486ba1fb8ec216b92ea799130bd47af0c3649961eaeb1cd2e72bf93cb1d35c96acaed0c174df632e1b95371684dade1ceb44b12a9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc41b0de2672229095d8f77d3246049a6cd0ecabdf4a5af715f54f116dbd3914b65280f2e380039aee0c4d778c00ec7366d5e17fe9d8fcc8a53570cfbad3a0005	1623228260000000	1623833060000000	1686905060000000	1781513060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	354
\\x4e53e05068e380b13b08b596cdcd6d8ce4d0082e3a4363f840ccedd21380836e3e5a973b62487bd35d929300625efd2eae7943eb4360a6e273813669c5bce631	\\x00800003c93b5ba8755d01ea66de1fd3eeaa14ec3e421214b499553937c31464486648037f5e8c1a4631959c3ebe26c567e4c4e62597d3ce992b5db24839696683e48a8d164cecb3a5018b69518154e979cc02c4dc92c2495876f7e6f90ee8823c05011499d27132aa9c0dffc9601c7b5bccd847382406a9dfbe418ec2e571bb3b26cd05010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x17116833f2c85b72b8ec83389428b3df04ac4ffe63584cd08508e91e309b9480225b667c365e9f4d29e452cea6e61c0b23f33ed61e649e6d631e9a41888f1504	1635318260000000	1635923060000000	1698995060000000	1793603060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	355
\\x4f03e762a11bfa86de60cba317badd0344991d7a4ccca6855a1cfd5ba45924ff0f470049c4eab22526ea3de9d39a709668707191c0be92e89cd41ae2f13632b8	\\x00800003c5be76fe52815f2db0019ddbf82eb422f20b77875b2b0d3bb94434f829a1544103405e25735bd730457d4902a4f49b25c1b023fa5d2afc9d8af561e65f78f56cde736f8e8220f201f0bcf13cd515f3db76686d88d5f3c47254e51ac13386902d1a5ce43ade16a9ac769706b37029f5f3afd35d352257794af6f4b88e24afe46f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf5f062d6fdc4a430d94e71ecd96eaf72a33b309f03690eb0ad844a86841f049eeed52491ef4f7a3f44e63ee6b735a76d2b1930f8415678d0ed9eaf9b8ec5f60a	1622019260000000	1622624060000000	1685696060000000	1780304060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	356
\\x55d73bc5535cba2ae6600f3e10228310632df7900c4ec90b03dfb6283d5967f8eb85f07af68777d6a3130db75658a81f61670ba987322ac6b5783b96c2e117e1	\\x00800003ca178de3172a33f301cf96a82b2102567a4ecb1f556f7d6ecadafa3ae79eda2981426503b419b3f322a347fa8528e22d0de8747e08d2c5cf61ebf5dca08d36bd11c1de5d7d381d927cd1705c059dc67ee94a2d00eb24a9c7174f999f744cb88cec40630396d22f9966ab5f9f747f976d20fa5cba5941fb9f405ec560a9af296f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd051ba72f57968cb276a698fb42c83c69856efb5e5d44cf958b8c4362afe73e2c279febb66ecff2bdd4b56f4a79fe7466dc8055a77e4dab5a5915d6720b8a806	1614160760000000	1614765560000000	1677837560000000	1772445560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x559b9c96bc1cebfeb3833243dbb450708ed0539fc4d27188fd3cb22332b3c185402e8f264135c1407d8884aafb3f84c0357b4c29cb1bde88d0cbf6044194a3d5	\\x00800003bfa3007154c4406ac47d2bc7702d4164077c4d081d48937564b3b5efc2d602bbdc49f5bbb08880f4cb450156e9a16d491f334d76837ba1b007b9f78a7f6298bf51a7c03626b0770a915b283a2e8ed10570aed9fd5769d4936eec08b1fc93589bece11fda6b013078b17ec660d9311efb34f692e4baa29d9ebd97f85ddf994a15010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1a5dc06bf760b508c4b8ab314618a6ce65e9e9826583f752764ce2505fdbb909cbce91d076919b568e9dc80e33d502dc3b521f297d3c80d65d3ebc1bc3caf106	1637736260000000	1638341060000000	1701413060000000	1796021060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	358
\\x581f4b9ff7a2dd6d89e26ae1d367ff34ee60c224b5c83105a8a9cb541b5f7bb27e2f306b3f2adfcefcc9f7d9fa2d39aba80d3db2a2d1da78eabf937e907ec4c7	\\x00800003e9e009f3abb1994ab0ee0e0a0373ceb7641d1b55223a0ecd14397896a59cdaaecf9e0f896fc4ed428e123470cdf204f0a86a1149a629e9b49848832f8595fdbf5dfb3f6ca02b6f659160f595fa4c5d282b2c245f899d3e9d6060b47f9e870d2cb10392560bfb62d8fc41bb6ddca4ec0341c51df36a570179ec44e39b97137c69010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x02805c208db7bbf44cdf493b05fc8a576c2dd919266a8cd62562cab0e0f649a02188dae36234a7210e9d5b43220bd332ccd5890113ad117b2786e22e724f810c	1609929260000000	1610534060000000	1673606060000000	1768214060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	359
\\x591f0d6f127356c4987a914403d4198ab03b615e6952e620bceae1891a4ee3bc03551aba275f80cd8457c82d628395ffdb6e3e1f8b59898f67a64c141d005be1	\\x00800003b496a61fa80fb86a621cf7c969c6ba6cbf9010a0eb1bbeb6244dc0c043ff83d1e9a63a73076019051f89ef78e9d48372c8f2bdf8e703a876c373b5145cbdca41de3c938bd8105fc94ad8f9f93b88bb42fcb4ae9ee466ea9d60cfd88c5d4bd2c7146db183cf6768c8d12ec01c3fc7b090e3747263df8863bce19b653eab7461c1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7aa6e264cd629e52a784f918064567b708bc9573f67f7d6b58f3f5db9c7a7dba2ad0c0634f17a501ffc22816ac020fa85a7c31143928cef3178cd3c7bf665b03	1612951760000000	1613556560000000	1676628560000000	1771236560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x5bbfe3c50fb26e187b4f9bcb3d90f1e163871204e22a3991a2ffc66dcf22cf63e410f85221cec1ebbf7eb79f2934dcceae2f0725630dc64aa8dbbf4ce8e5eecf	\\x00800003dac4705bf5f1209c6a9785393806c44f58456e08945c222094f3402eb59d5050fde3e8b279e3c41ed48f2a2c3a269f3460900848a6b3c49e8d489bf5fa4c6ad3606b5a5c8abeab7f0d183a7928040e275768e57959dc44c9eae319deb7d876e1202c2b89f6b10c407737f3bc7eb7f6cb0451478a2a48e593c510c820002e29d5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2d1a5f05a419fbdb5247f007d174409659dd9fcc3f3b3f166b809619fe0c8b6f590a83dbb366cbf1d92df53ac4582dafca7b346ea9d76bbf787fd72d8f729507	1615369760000000	1615974560000000	1679046560000000	1773654560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	361
\\x5f170cdd59597bf9c6c8e87ec38a335e04edfb06944d19a906432cfbad4b8236a04d9fae0dfddb370971b9c23162133208b50250bf689f9da92ee1c197eaebdd	\\x0080000396e0a71929ce0d8b785afc4dbaa19ad0a52f721773beb5992e66fe3b963a51344479e8c598efc2ffbf02d02ebd276c985f3c0a48a6d01dee9313be5ac1ed3cc74603e07882882c40f2926d2e07ed3242a0debf701801283d63469263044f19a3c29a2a867d6eae41806bbc8b562803faecd3f428a33df8f784fa706abc1f004d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf012881e353b60c4d1e620885996fc8bc6d1b36d002088f3d071bc3663756d9ee00e2420713ecad794c212e8218e475c6867a5b8eb4a84e563525ddfb09a3506	1638340760000000	1638945560000000	1702017560000000	1796625560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	362
\\x5f272026211bea5a5ff5e9866bc46ac4aa935e99d4db4fcb95f96c1ebbc57dc30700c14cff13bfc07ea8c33a5ea55ecc6756b078c330cab47763e7d5b2d25345	\\x00800003c5ef396075b3f8ee188045f0643043111dd6c5bbd904cfcef178961ff8d731ca28b0d7c2a8cb3b78335190a09432961146913062eb40b2ac2d93f2ddefa48a37b08c86ca7f39e8787dde767b54e0dd343a46844863af015a3c6b0d443eed4e8dd229349f687a96ec027717c3d3a109818a31a40ebe9c75fef54664f4a142f5cd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xc94ca8431790fdd583db6ce5baccdb3b18e4bf01f30cef623f1a4eb7e809fda2ea35b0003826f0a362e525514585fe954ceaebad9770850ea081d54fc8311b0f	1615369760000000	1615974560000000	1679046560000000	1773654560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	363
\\x60f377261a36d4b6c30300bc9d2e7d06548fc51902a24657ee0c6547f97c808c7b9377d748d4f816498ae63b599cd3992deed134af7b32e4900eb61f2987e66a	\\x00800003bcc0e5a3018083f6a80552f78c26ce56b1ff739a20eb8fdcf36acaafdb682b0ce0d8a5628f0ef56c974b7d68f72ea40aa5c053e55cd286e367675ca55c33eefdacb4aa6a3581914b427822f91e6f157502516b5d941b3239b7643217979eb8befbe19082f48b8b891c1ed6104b07495c2639eb708977ee7aaf7a428ebe97dbcd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xcb4916d8181e6f26ff6a9d2b3e842c9b05fa671524fdcaa2f7e8789209255fd1af230852ab0fa4972e0108e4a9f34419c937b7eb13e53bd7f3b4a0c7c1786907	1626250760000000	1626855560000000	1689927560000000	1784535560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x622b03ac4e7549217ae012ffd5de0136ceac66099fcecd4ad8aa70a9492404c0b302baec45f0ff2d75fd83862385960dd813afc6e953727e35d5f03eb69a1520	\\x00800003bb376b2f5cb81a75cb8ce6afd3fd4230bb044db531c38656ff8d3371281a474c747d8f37067cd6e78f4a79725608f89e165b476b0e9482cd0dfcafe33ecb9c32abcdd95da3aa0b369bb2c7a659b2bbc5b0c089d798914479e88f17b4459e70d97f4b65579ec2cb9c2b73cfe96e2e5d86b8469c9822d06f35cb9e412411bb050f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x627cbdbda25288f8330f9250a7eb9f5e6887c5558bf06e0c7a4dcd08f00a66db9c073dba5ee099953ab2e5163bfe591b46abe809a88833c9c9848ff54ae43e09	1622623760000000	1623228560000000	1686300560000000	1780908560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x6853ce7626b67999e5939e1199bf477748be68a1d9ad5f7e1b484ea6e204ea66995e8f31fa50d5ad72b9805ef6cab326a08410c4d856f9f6d3b8dfdcbae2f130	\\x00800003c66049cec36ccbfac9225e3553e3c9db5ba444c48a2403f60a06e687f14d2b961fde8aae69b51cb235a045c00fe8a20ea95942627148a8d06dc374e2e08c520bc5d8dbc03e50c7accf6775023618d175b596f56f247e625d371ba93ddcaaf9560443bbef5ee41f6fe390612b27a622fd10a3f9d5ed7a16dabee958cf390f0989010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3e303f129fa616fc59ad7c88f7e0c424fbb683d625505b1179592768dd321cac44c01a35b269b5fb8cb44e2428b56c60d1328be1c386b2d2662fa81989425502	1611742760000000	1612347560000000	1675419560000000	1770027560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	366
\\x6ad73a5e3e0f55ea91d61b234b83a90ce58cb33a81494b0ebce5f0ed06c65595268e106ee5a7e6b9d324b1cb926ce4a4ffd22017b0303d09596480ecb965deb3	\\x00800003a030f1db1d536b22a28a0ccb4b432f19e54597de259f311d0eb1409e9bac1141c147a13436c443c215b77e3c03016b3a12dc4736bb7c4d1167c13ebc0fc0a7696dab90efdaa1700fb66f6a766ef44d8b0b66fd161f6c23f83776d71c9fa3401f7357b2d8e34c7d514c9e4cad7a5eded9bba085007d4df60e98d0f82e3f9e5a79010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3283050d782fb6243b62fbf9e1be7133d81eb5112ed6e32a7d49ff55ccfdae966ba9ed11a76a42d3d755541f25ec22f10b6449f52edb09b25f68195cd0d0c50f	1637736260000000	1638341060000000	1701413060000000	1796021060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	367
\\x7543683263b487d85e9c6069d33ea8be2e6650e90f36bf944faf9094d356c811e46650f171855d6d096a8e759b5acc961315d43756a6c6af6ab14c287ae5921c	\\x00800003d04f4dd1b8ff3d29fad0477d69cc1aab38d1fd24f0ed7fae1ab2907b2e116510303736b6def2933613e3a85c4d1e2270dcc84646f50a604a5f8d365e49a77e0b553e443430984954c6c3747798302600103f72102acecbf6acb5c38aa43d2b7930556a64323727fd07aab2b6edf6f15137ab79fe1fe83dfb75d19b0f10673f75010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf1c6da775df6c227595e814750125ac727f69dd1988d60f4cef58a4052de28d5df97411578253dd0a28a69854df122515b12ed630f80d90a2a1febb77fd34305	1629877760000000	1630482560000000	1693554560000000	1788162560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x763b59e9741deb9342fc02f68d398b6788cbe56c2fd646ef68922412cf9386abf21bcc7edfb2dec97129fd3b8ab98df500a25c63b5c034169747737ff4881d10	\\x00800003b2fe4fba99231590363b5adf29cc5d955894701c565183369a5648afc07330e171bbb581443ca7102071bd7dd8502da655bfe96f270cb0e4d383a49e7f579bf365def7e4a95e2b2aef6443d0c920312ea504e3ceff90425cb9c45ceb45bc0b852911786a6ce83425f3a9f31f6867c403f528fdd8721c6c048dd0dc8de73d50f5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb78724f30028187d99ab59b372c33c6804ed358fc9486416ee85331b28cd9d96130c75f14cf67c45b0faf39284fd4de4cd50517d54802d447c8150ae944e0f06	1610533760000000	1611138560000000	1674210560000000	1768818560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	369
\\x7a4f6c979a3fba1965dd6f4a671f088e4225f4d693efc6baf9fcef900802fd433467c9cc95f71624236685037e121fd8a9f933f41f9933bcf55a6edd71039568	\\x00800003d755b836cd9d1c44effa3547fc8bac08328427838226f27f6d59038c397f86c0ff1cdb83c8aa173a847c1158c10ba3ff62717f621983a5eeeeb53238c5ff1987c410a05d96afa08f2683d220ec7349160fea2907c5376d8b78eb23d4f6ccb1ec35f86a4f8d371044ec10d03040a8fd668319e40a3f6845fa195b85850c5acb71010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xee03e2736a5bdcb0e9ce1cccfe1f0322f43f896afb5cb8bb8babca3fdc53444b03fa0d09fc37fc8c61568872017979ab0b4d09efb5a01273d95b650893e0930b	1623832760000000	1624437560000000	1687509560000000	1782117560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	370
\\x7b5b43c8fefc86ec7dce8813caa7dc0f101eeb588984a51254bf954fa708dae8d19fb68a4a3d1fd1b4f5ec66298e99e4df6d07af2c9aec297a7e138c4113d310	\\x00800003970fe5ca0b3c6b7d5bf10f01eba4126fe5a378bcfcc376e6aff61f4124b0f97fd85c25a7c65291277b265535cf50fe510ce19903357e859a71b3634f1208714f898c0707d57033c591d4ad585c29c63ffeb54f7c22ff4690dd66481a289b7bc2972439d053664487ba6f0d66228fdde14f7081427623d827087095bc7759b957010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x79e6360ba905e9ad6f4f0449db02b772387924e95bb2a36d0c88c573406bd68c95912d3c58a21dd1689f9eb6038a376a762e11b9239cd50f363ed9082671f509	1625646260000000	1626251060000000	1689323060000000	1783931060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	371
\\x7c9fd8b5e5ad76b603c8975327677f9cc9639b705089f415f10e0d8945640fdc9560566570055b4718f2e32c7d3689413a8ec05b8951dab73e3d85db6130d769	\\x00800003af026b1d7ba971bfb444966693dd30a374685127229e55d9b0d5d64945f6a47476830d90dfe4693d5970c936da81482a03c0694ff7d2fd6e52ae96c0f05790a6cd2b5c07a440900e25c06ffdbd54407d3e8513c2b678838421a39cf46fcb37e1d4cdb7d9ba3a930ea215885745c9ad7271da46940cdb24d219355fb282d5d98b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7f53c7e1bfdb7e8db4bf70c79da935ae442979e066406f12cce9927b93ad16b9181f7df4d4ddf706c4d44f5ee7cac9cde92f916484342f918792567a5cb3de0c	1616578760000000	1617183560000000	1680255560000000	1774863560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	372
\\x7cb3b5f84c5fb8ffa77724d8b7939b640b03a9624304769df64eabe7017fb9707240a3a2d2cd08fd3ed3e4d239c465e0d69e6d3aa6214c80df82fc130e86c4fe	\\x00800003e0e566cb74763a348ad6c94b25b6a1aee0379827084edfd6f330aceea0d5f92555f3015fddafc3244df62a9fb788b30140402bddf886636e629b84e0c2dac1082af3389e3a521c461cd1531475e51b00b1feb63c71e928e8b502eec63506bcc340ca815846db89c5ce7d1c418c6a889f452e214c825006e470e8c12ff468316d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x347fe32f97fa2299b1fcb0746029b84084c021181450de6a78f01eda400486da572a7799682c1c8fe903c17a045df3d23ab8d05068e02c92fc830639b2fcab08	1625646260000000	1626251060000000	1689323060000000	1783931060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	373
\\x7e87d46b26c83615cbfb234a6bff6e50545130a9ae55438c39206aa0649beb52ad60dfe89036c6b98845d3497a57bebb24271b90e0dc7c221dae40ef30d8ebb4	\\x00800003e9bcb8b171a97e056ef26c631d16bd466ca9804d24aefc150a83b18566ab70f29a4bb5f04e06114ec60f31e019e32307d35cc5b0d5d0b7035ad572f3c0fb4bbceee1db6e2ab3f429208c45d3b51b2c3855cc33c64e787ab9e7c2d52e6ca0f7d57991a932568998abf46e490cb944b3b17890096b51ed550b0fe6e3bf73d68fe3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf3f8fbd6b9aaa0ec75c6a913d2401073e5dd3698586a57cd94597dcbb1acc1485ea40a7af7ffa0349d15152ae801474b9b0a78e4fabeb43bb37ebfab901b570e	1636527260000000	1637132060000000	1700204060000000	1794812060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x7ee38f11b6473c93f417ee01f615bb8b6a50eabc37ac7adacd45663241d6bda5fb5c8fc4da4c5d28c44f38491480249cfe7ba5470fbc93f7b5c4d9c7d0618912	\\x00800003b28a7a019fdfe1c693b1515b24f6ddabd3ef5709104ca679d8b85e3d38bf2be57b3d29b4bada40913d7828aad3c826d0c813be1f3a895a33d6a5c649dba159630c2b08ca9b70d1109ff17a22e5f034eb12eddfc3e9696080178cb78fd623f257d436c8316eab7c31d9ecc8f29dcdb3efa7c734290fe239038a194cdbef8206b9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x6a03f40949977673e46ac60345ec6a5e3fee6fec5759b6fef0fb9dc444b0c75871a355d83cc99f8484093c4c734994e70e787b02d9f34574d99d3d7531d2bd09	1614160760000000	1614765560000000	1677837560000000	1772445560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	375
\\x7fe3b56fe17d37572c91f5931807bf7428bb1122864501cf21d1c5838875e4b03be35e89f5b2513e1d0b3b68666b7860c0b20f54bd9e28f039b33222eadb4970	\\x00800003c23e199ae9ddaf383073727cf081b5b20e6fb0605917e5dafc4c5a34aede220dcea5d0423592ba70b2d6a0142e486fbf65d5e6a5f18b16eb099cb0174e886e4b3e85932551f754ab4ee211c8b76836ff2bd276ea1b5c0c8a2d14457401c491df5ae94b424592290cb8c1a632a6e9b8848b4b194577f12f88ca793a3ba0a10619010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x4a41fc37ef742dbce107c956cc052f7dba72c9c595ace68c51da4b2da83f0e7fe96074835995b3c5a7b4f8013d384cfb477d9a251878481d093849d5bc194b0b	1626250760000000	1626855560000000	1689927560000000	1784535560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	376
\\x7f9f18d1e05041811a3673d92f00bcacc9c59be0d74b0b1330d096e3e254ac06f55dfcf4c9a3a7aee4e894ba0dfdf0c61501e47b5eac25f8837d559fafa12a3e	\\x00800003ba3a185ff14311ce7315bc5843ac2cd64775a62bab970fc1fe49724f3c30d45a1c046aae8cede5afb17a0ca4bfad70b358b49f9ea6e6a0294cc588d12d9789ce4ae11793223316f06d62af09e4672fbf2d894829ec8cb0b6ab2eb32922c57a66078590edf900bda6b5c9e8db991df093bdc8ab51a732b8aa8037918886d25657010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x33436e6f1ef79b728cb62765a041a7af7f97ef078bb2983be3c2b368e0ea9ed1a438948fc2130dc3a763b0e670743fec9b22ba3b502046439bd87f092a29fa05	1617183260000000	1617788060000000	1680860060000000	1775468060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	377
\\x84d3672479ae13be053edbd21e37ba6550283152cbb10790b59ab71b2231093e098751dc121ca1a7ea6fdd02eb25a0db92e0024ae568ddcfcd4fee5585520cd6	\\x00800003b8dd6532f4adc48d2c778de78cd6dce859b0b145db52b059b71341e012920f4569d5a7eb5b788b76fdabaa054af08d16aaaaf6ca0750245ab04a681ba4739b9c0857719f580d50d9f459060107371c4b99930f5f7382828903a1e216204e221b475faae31c891f7fbf5bfb02a6531f1c30b6678407dcdc8d6b0cc54fb46bc761010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x2474c7b2c2302b5698a1e9eb330a29beeb650e514e5da19963c14cf2f9a04b4de5b0fed1aad86882cade5600733fd96ac1cf4fb38bb3fb06fedb0ed810089b06	1634109260000000	1634714060000000	1697786060000000	1792394060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	378
\\x86db04d7c4732720d8a0f7dec1cf506d9141675fb2b5bc6d7cc23bad7a8c1326997dd77a617c637436bc6500368d9665935384139f61ba96121b727300de47f4	\\x00800003c3755b109b012261c7e3f0837e7bff7a61cbcb804cbd4ab9ff94f6d3ed163f1eff8872bd3307bffaa7e0c0df6e32d6e021a33081e8ac2c7f75b1c4c7be42223686eb5fb0857a141bf2dfb3e7756cb0f7c19297b682d10189ababea5451edaacf8ab6f59b9d5fa98694de1259779225bcf2f5b9565d86dbf8aad2ce521db93ead010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x54086069e27fb04d34dd5300658e4f1477e5f2b50ad4011f3f83837c7c659e51fad9683190249d40aa37eb4aadea8d85a4989afd8c90774604e893aa4935d107	1632295760000000	1632900560000000	1695972560000000	1790580560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x871b94abfdb90d96252152a05e72839ea49adb80cbf0149a11cdecbc905fbe5152feeabd740ac81c6e8030aaf0a249439929521c71fefb7b8ab3f4d0073ee140	\\x00800003cdb2ee1f5c49de7601f89d0d9644292527dbf615aebbf3327b8ab63d99e6f01360fa416eed113eea1ee75557ef89158144d7e993f26eb1b5cbf132ddec49abfd9cb9eefd365544f1ade021b9595e45898c681491b509a75fb637287de02df0b15b11aa5b9ab80b4f3dda5874109f3c3ce2ef433e326af0c5fcd84cbcdadd794f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xebdc62173608d72e6fd4dc1f65d87fc77a39c33d47ebbbe0e773794a602e56ad26d4b6cbeaa559734d647bb19f8a71d2210bc049f5a9d615bcbb30c6ed9f5c09	1615974260000000	1616579060000000	1679651060000000	1774259060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x8a6f0429cbeaeb6d49e407089af2bf493820567d16393ca27ab84793e6f30b9aec1ae97b09887f8ba2e1e3e9f5eb3d3c0295a6f35967eaf5a9b513b86b74fa0b	\\x00800003c91e6dddfe32e7c3f6a9916c1185635ea999710dabbe76e2d1623ee13aaffd5df66b0d84a9ad8875ef4256876291fe16af2eed541afe37bf6632e7ee5a43411439bb5e15181a8c369265288c47f291d52f8a0a27c9e5803fb74a617938aea5585ec7ee8e92f55dc163ea9bbcb8e26c73d1bd0522605ec412245ad4469d75a06f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbb9fff5564089e0d6c391f94b942c72bcd35a2d5441320c70fc1a85825f77a9acb617fa7d1b6837b929d1a96649f5c095d2341d86a1375cf7764eaf175104505	1629877760000000	1630482560000000	1693554560000000	1788162560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	381
\\x8b536970bafd567c0a3d45871999dbc149c5e29a387e8f03256bd934da95a55bfcf4e3ba7a9fc645d937eb4d3e66918705483ab710cbb77d1756978ea32c5f54	\\x00800003cbdf4c659b9049a10986df11a01d57a1ef43249a0dd95621ed3c5c0ac1778cfb2c7aa48151ee1f051c0e4b48b9777a0af1f781e35d881ce9ac1e73b707011ddc60de21006a31eeb0c53e284b650e204e625fa4a095c35210fc22ab4d98b68eea9f467a8811fd4998a858121bf4be75aee4b4c3869578cf15d9725b8a0e0ff753010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7309d52d6bde952bb7d220c1c2ed9c32806ffe3d202cc4d7b991bccabdd0c8497334a203dd17c7004c3241e929fa1a53eb4c74ff8261156e3941b4d8056ab10a	1627459760000000	1628064560000000	1691136560000000	1785744560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	382
\\x8cbf430aac195fc5860e49641ed497aa4d4095235b62fb33c3e0f37bc4fce28ebd29d6fb7385c7f4d6ae8b9354377816e68aaa8c1981ff9798ff953a29e19502	\\x00800003bb8a8b871727ec8854fc22c2b1e30bb43d05396fe5b959fa678484be2deb95a6faf9fd5b7c9abd4613a61b0f36f4df709b28e26a424e717f38f2718e36786f9263bb96bfdbed9fcf60848bc569a96cba0c6f4957a2ec9bfb8363943e519032e8e6f261ba7a859594d443991b7236af8b9b69348d38acb26f6860bdc4b29c5ee1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb0f7e528241c73f755a27eabe497d68197b12346d10bbdc5fd84e025c8187fb41d95ea6a695ec0cb5f77f8a22462b56d2fb29fda0e294fc3d93b6816ac63900d	1623228260000000	1623833060000000	1686905060000000	1781513060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	383
\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x00800003a4803fad8bc6f5a833085452077f74542b6f5ee5a1ef9786469bfa6bd5160c33c3d53aca440de7496901e1c5c5e7460b448cafb760da0b49a7858c8906307b6e267a096e17408c3685dc3a50b1552d6a898aa071f3fd6f29a5909f567fa7497c598b32795cfacd0d890ca8853d07d2e10e05746cc168e2693d102a2272b447a3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd28d224d3e604cf6bf429c7c1565aa7bae14f357dd17ed81411556a07cfae51166f36e3bc1cf48ee93f5d8ec767bbe6a4cd314e9cbcf11313553a5ff313d290f	1609929260000000	1610534060000000	1673606060000000	1768214060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	384
\\x8d8741eaab805dca1f7ec579f9d7281f046a781b279210644613d734af163274b8a647ba6ceff7b70afe9f8723c02193f9fb84270d410af67d2ab48076421b27	\\x00800003c2c4f2e73638c6edf62814e5f9a03d9688a82fdfebd2f084f8805d7fababd06e05caab062cbe4ff59a214a5e8e7338e239bb924af0663bf2732eddedaf510ace6297ff24c3ae182406505fc0586da2ceb781f24c618de2623614b142b1e091683cfd3a48c31c00bedffb67e0c509acf34c30be8580a5ef45884e21e6150f95c7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x558e413c324148f063a8bda9d86e6c512925bde4625263cc303ec6fc8bc0a7e0191e1f199f35377bd08101ef7efeaa0c3967fa56b7388ba0e6cb62b4c8590b08	1640154260000000	1640759060000000	1703831060000000	1798439060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	385
\\x8fb3923eded04c28305004ec34cbf316776357b572644280ae60d7ab03fe12366e7a69145824e9b9db785dbb52e958bce1afc259b7921b94931f14754151458c	\\x00800003e88c44645bf2f67ae7028b57e8dfc9f28b453b7285f51262d8b079bd7a74cde986ac241da1d90ef77df4b0a3f2f971406a66bb11511e287a60e320bfa339484a265dd2f31b2b7e7981f3a58d65d436c82051a3d02e1cc46d1ef2ed09cd7be9ad7e7bf0ddef979f179d51273f1f0d41a33c81ebf8398e78c46094b490ce53373d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x979a8626b02d56954fc2f5af3e104e5d7187462dbad24f3200712b9e32df92816d65c76ab9bc452af1bea0eaf82af08a2f03e9ccc1f482b62aa7b2c4f29f4408	1618996760000000	1619601560000000	1682673560000000	1777281560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\x8f7fd2f9d0ebc08edb03d08fc9a857ca1bd6d559b66f6fd8d62b8783b851a557a082f32e92ef23bd08014e44969c5dab1f33febdd776759531aec711d5e956ba	\\x00800003b441e161469b3fecff4e970bf85003b719c65b7822a4fe01d54f5820241b11117c1d98ede3ae90dfbfa276646f1426d9beea2c468c214a3c3f64ef18b47ba72967c2954be3fa59c11fbb0fa4637d856cac238843c1c3443f6c5e35c49030e6b9b35d46f5c7e1127aa419a1ede2a4c84aafaa4fb14fdda8166d7ec5721b12d985010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa03c9061f0ade2b19d2aa834e97cb5fc4d753f3ef831e253ed12f936a8cda4027980caa2fe48a744c71612cc5ec139f382f6578edaa28d7754e87463ec588900	1611742760000000	1612347560000000	1675419560000000	1770027560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	387
\\x91639ed4c1fa37ae3971f951fe9124c40f9b117117edca88ab69f86aa600a99f0b93a78243716d4bff90b2a8f142105da7b32c1d94616631e11646d8da6a5992	\\x00800003ddacfcc2eaf6ff565998e72ab43282d36e2a7cd9b7fded97b9f5d471ca3a1837c94e50f08ea009b2beb4bf3624c3023756c5a6f50fef6a7b1057536d89d294e2ad993033ab774ca08eab2ce80ed6597763e6f0e3eb1cc3deb6ff2e66aac560cdba233746cd3139bbb6f1d62dabcec4b351867e3de3c9f5992e5a787986115973010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x56e891b7f69c6153d3ca33b39c4b13d5ebad3613601e5f5cc34d6c508cc0e0aa3bf571ad3e46129b915cc865b58db4cfcf87a89bd3ab8e0cec93ddf53490050c	1628064260000000	1628669060000000	1691741060000000	1786349060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	388
\\x928b1e0b246835cdf7d641a9baec947fd4483792480ce41daa4f179e7b4e6fd7a0ac291920e1976773a3fa1502a197666119c763d0dc4e60ef319aa7900c28b4	\\x00800003f3dee5358c9d45031afe914f53f2e6b64e3e3b24b9c4754a0d7df86fca87c73af57f4475ccb8b024b0c90225c7d9138e72294d97435d8d0d70a7d44aaa66ce32bcee9a6e039078e9776e1339a699df8c6a1692df4da0861e9f1ebb65ba7db06057982f22a9c4a70f7ba028af92b50e7ff6ef0ab9353f3552dd22061c4bcbcf37010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdb39eae4d7cc863cc44a0708669e4980099794a7a9bf915598957312eaac69db309bfdf0960c1a726d940602e44bfb21201fa1a13b6077315e05725de8a4c806	1630482260000000	1631087060000000	1694159060000000	1788767060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	389
\\x929fd5cd36949537c46e40b1fd1d78ae2b7c2221e6e9fc06786f317417205d052332b78ec6bf7db301403338d882e000932e1e0b2f70636f0f3007a2c2d17e9d	\\x00800003aeea9f59fca8f78bd7dea69ceada180d769adbcc46823367fd3d11f44d263323cdebc3f008bd38b4572abfd28ae9c655148044e46e9645d9a2f3f416d172d6a0390c29c3cfa3af2efc93671aa2f164aefa06c0e42bb73d1a8c655baeec7768d4a498a215e99ba61ff1457bdff7f580e70ec6d0a5853226d7a18c286df90de279010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xdd7397e24383f9f2a3ca6ff2286bdb51f135b9ad64a30219df6463571266f55c9f8914572056e2d356bd701f7ff7110be7e5e271625defbb630dd34b2fa11502	1625041760000000	1625646560000000	1688718560000000	1783326560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	390
\\x969727fdae3f0c228423b771a5f057c7ce7afe83174a88b21c35abcbc5d0db58d4cc1ae2ff9b21e663c2fb9e2bd2352439ed0487985e0b2307d6ef1419e772e6	\\x00800003b7ae90a8479b0ff8d006936a735bbc4a7721dded204cae6a0325bddfc89220571762da34e97789eb89b748059eefcaf7c7981e3762ef72cc2e620d6da42610bc3da7d52628d7304f1780a1d8a91e96f69779396f8c32c985b28ae7c4932c3b64efe4f34ba5a202b1c081ffa22e16ca22e9cfb038647088acb6a55757d5dfe4f3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x55ad282d5b3a787bc11960ef4422769d7048a167190f1a6d2be328eed211cf1deefdf4508d5e183a939ffbe3f14d8941d70b4abe91ce840d3488f104346aee0b	1631086760000000	1631691560000000	1694763560000000	1789371560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	391
\\x9bc3016b7227aa47abdb0857d39f5b9ee620769047594b263b08ca1ee1596be5c2dfd78a7731e8c6cb623f2e0436e81b16cef2a27f038d4b5e14963d08dd818a	\\x008000039fe70913bbc39d1cfde56ec7c13795426910d2b2646fd250f23443eecfd539f08e7dfd37d8df42be8c5b8b1d6c8c6f0b9c8076c87b5a9e6b5e0ddcca13ac6b1d8dbde6d7cb9960711c6cd17e70a4f4634fa48a3c7332ef2c48adf2d772e7880dc248bdb5a67b4a8e17de8283273724bdfef1b177cb335890e5675dae9e5afc6d010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x88ada1c5b369e780322c32b894ae2ca0b5fb14aa67cb826844be3dc63d08cd6b505aefac681d069cfcba8a2647b0a411738ebcfb22e97c33155d5e3098cb0509	1611138260000000	1611743060000000	1674815060000000	1769423060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	392
\\x9cd335fb84fd068125c32d0f301e364873a31c421f487125e43c5eb86e5f1e0cd22e4b93701a7e706a6793a18aee5f80a1433234242a28f92080c3165893d436	\\x00800003a90aa6f8301a6e7208fb6772fbdf830c7c8a8d326d2975549a4fc101ea76ecdac9d4d6ea2b80599833088ea6015e4d30c18825d26638e422a1f679bffb40aee009bc5aa0e5e47c7e0927ca5e44217a4f73f904cd6a954e5b0e6160acc742570543e35487ea56bdc605219ec0079b001cc8f505b9fab9cb0deedbff6b1aafbc77010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3d0d98b1bceab8f35e2745f8af167c7f7bd21b5143a47c4d6832fce21a0faf98dca75f2905a945dcc9f2dd1c938b200361d8e6740bad64493270ee262d1c5306	1611742760000000	1612347560000000	1675419560000000	1770027560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\x9d9bd5f982fcd35116ad6a8823f92374a0761ade38266e31af593d1942d935f4bb776866833ca9fb735f0f83ddecfd407c7f4ae0869873c59ed8561254414a32	\\x00800003b34f059faa268aa62cae6aefce8101b2772f0b9b2561697d5b695cb10b7516419edb44bc0f067c74ff3a6bbd3426e9f832eab9031ef45bfd773bfeb7c550bbe8ce5215742713ba6186fd4b20cd9278dcd822673ddca5ec19e58195a6e89553ebe8b5d49b7ad84a8a51bf64d547a3bdc17e3161c6f44a2c3bb7fbf1bc6f1ff1a1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbd265c8134977ad270219334dcba9c796a5088b079658bf932b5c104e22e5584ab42988bad26b4d3c2e33147febf1ffff8cad03b6b1da3c1209347945047f400	1641363260000000	1641968060000000	1705040060000000	1799648060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	394
\\x9fa3e3a911b7d1ba8f0e4c01fe7768d64af5898a2205a95f44fc9fb3f379f268a0c51aa2878faa75a34df6f0cda8ff58c7f3c26a82e041c750de42d698249a2e	\\x00800003dc15addaf86c32c91456c345fc52fc36f9ea4f8046b04b972f88edf6383434e6902adf0c90caf7013ff3b26c9476f31a7b4abab44981cd8a60281ba6b1f8d8ff3a8f67f46518ede677a4d35feab0f31989c55d752a7afa0a85e6d4b5c7805d1c5e165f44238569f1de7eb042a7ac3a125a54f0f49190c07697516faf7ee43343010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x5b02d3e7261e5f770a39b056bebab042266713212bc757feefd9a42631e69a49128cd141bfcaf6e02c869252ca6858388a3cb7fad745edee3c3bbd8a98fbee0b	1640758760000000	1641363560000000	1704435560000000	1799043560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	395
\\x9f5f8b8aace5d0b87e8951db0d403a622caf8fd08c325d89338024c2edacc8e48b4ee82d655ffc2175bfd1d7978fb861cdcea18325e63baf45a2cdb99cf5fc99	\\x00800003bae637a40efdf442e60b7ea766c5aa3fd5af4b1f170f864b1a7072d29a897167accb33cb55f8c48b3c50697b265638fa127f7b07e00eee3e4168d95022fc514d5878eb66f3eb2fa39e0a523209b91afba8819c67a2b5c36d0e5d087c67e889dfb586861ebb3f48e38961a7fe07e379feaadcba6ac3e677cc55a95197cdec0871010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7f5297c89a3d6ddf871f2d1fd994645322bef1ddd5edc6c502dc7fc765710cb8b1f40b8dcce7d6bf6ea50ee3940708e4abb64322c10256d96d8dcf830451b30e	1629273260000000	1629878060000000	1692950060000000	1787558060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xa1e78c041402bdfcc4c768bcf65b931e433b75d7428f6d0315c5ed1ee80f509dfc44d80c2c6548f101af489063d86355395ecde1463f42f7fccbd0175f2e6f4a	\\x00800003a93e878c07d187d15567f7e47f942b20a266dd41393a40ed6297f2ad70a8cd8b5be6cea9cf3f4bc327c416807ad5c3fca276198b01a4130cb5b935837771b7a0fb4e5301408491a12a7c94c10c6a6f81fad1ac6caf03ad9a23f2ddd0b1511546a07f03c2d93c218aaec73c577fc7fced59d5d34867fabebaa6a9fbb05bd546cf010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0e6d69841e06c3da23e25580a307976cdc51e17786efa975c673597f35f7386dfc711c1797f658ec88ef9ad51a16a0ff6e2f62aef8b2616d11538b26157ba406	1629877760000000	1630482560000000	1693554560000000	1788162560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	397
\\xa6c785b050385a8be4ac4612c9fcb19e5de180f41e85bba8c98e66e561ad50a27e42182d936882620a485b75420602874292d097f140d6e675ac6f466ccf163a	\\x00800003e86c909e66b8f2b8888057aa64207597c29d7b3137c9210b451be4183b411bbbf5d1a44df3760f51102b24a485a8016e2075b9242941d9528516e8ce6a6708b6826a717c717ef5ddd11a877fd643fba3fce95b71c0162700568779d32599f16fa2e2b8f4b5bd9ce897d2bb277833bf82a3d7efa162dbf46c4238577140fbfabd010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x0a029758eb1f6d2def2e9ef460827116b6846a2aa2b277495e5469308672615b3a669c09dbe042a62b0e3cc6a8045b802132dc1c594995338d6a90c548b57b0c	1632900260000000	1633505060000000	1696577060000000	1791185060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	398
\\xa84ff55f00f5ccdffb9a8a6ca7b71eb8ca987dc7ecbc6865c16010eebd1c820f654b1fe42ec2eb778e9b70a1165920876540fb8d48ed8f873c481f379d4eaa47	\\x00800003ae55f14428af85ed093e56771a82c29fa3f8c997ad85d1b03b2e4afdfa6b176f887a481360e6705f4ce465ba48001d3a87e0803d47b57229ac2c0e080e49cd3635b1aadc656d9191d904b7aa52d68b24a8012d92a6f86388aa429b6d3dd70c701c436104a89b09a538807608a23020d6d6b7bc777ebb7895a734114cf1333dc1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa13a0a23fd4a132949b5009e5b1481bcba5c6cf62253720826810075047c7ea81d0177e3bae2ad9b276ac6e738ca798f08cfe4f5caae5c14fe760cc6e332450c	1634109260000000	1634714060000000	1697786060000000	1792394060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	399
\\xb12b74e2c6fb051bbb96d01350d19bff4b5ab106ec03c1ae506cd7d5bc08392e955dbef46d037cee0f943bb05157faa007ab4fab002de13574b332203c95d35d	\\x00800003de6dbe115b0d716e024c2983d39757f3b6d3b3d8a93901a79a40fec08ff2e5590a6824a8e64195c33e5e20d860341334ecf29db666268d77dfe92728ba6cb2bbbc0314f836d2292c8a467f061407e991f16c400f0d9e7681dec5dacd84482b0a88dbccc5b03e788d094f09467787796912b8fca0e8eeea9fcd516e16966bceb9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x994d7bfe91200e21714ab854778e90fa3bcde5caa260480c07d2628d2e5f8acce9cda5b62d5dab450a25742762302804df4b00b0917bdc57fa2f83bdba275700	1640154260000000	1640759060000000	1703831060000000	1798439060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	400
\\xb2070479c24166f65c52639c242d4a9c4acbfbb17810c36382975f54601abffa658022927a100737181f1a8d69e842d27f3df738374281909e7a568e77579031	\\x00800003cfb74f240175decf1ef6139e2a8caa96ffc0167842c25107add2f1104f57db2a55635114b4fd353b98dee3296de8d10d48f5c536909b2d0975940d59c52cfc71590f61895f0e2972c941a634b22ebdbeec11b377d1cb29f1403ab705e84701fb85595decce73e8cb78ebd4eccc319ce69b7d94483d1d3c43541648e8b59e0d09010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xaccf4d094fdf098dd4e73e5560638d21686858c618b4a4cc40eefda9d9c3fb8a351d6acdd1b207ca044059a711a7046bc4972a24afd7e81fa718c1722dca2100	1611742760000000	1612347560000000	1675419560000000	1770027560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	401
\\xb50355ec647735c5f110f4b56a103e50ded99a607e21609e9ec6e9c0b41ea56385b3eef1976091f97d0975888ffa3538f67aee329a9a97de914243317b76c5e2	\\x00800003ef89140624a1c9d5116b8089928942dea8f0e5ffae9422e5a5def827d1bfdd0eca09d633f59db2bdc83d9a0af5692ba5901ac13c3eba157e74ca8461e6215f4d5f1155d7f2456411da447fdad05a94f321a342d78db4438f8fb9f41537934ca4802e77b3c211f008afaa19701ba1e8a46b2dc230dd6477f076d77757653c61eb010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x090684af6375dda0d46df8473055c400373cbf3b11988741b551a0edd60dd44438bccc853f862697c169d1398c86bccb7d5d1b0fa371edadb905ed143b140701	1610533760000000	1611138560000000	1674210560000000	1768818560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	402
\\xb88be71cde3d9c220a772c394bbdb18af413e4cc7ddfb30f6e3b0212837c4421886826841d2a83433e3429757573c2596efd5e0c6b8f2bbc337c6a2e102ab131	\\x00800003da48d5cd83e1d6b1bc3cd57cadccb55d9f5fd8426921848450165662e2fae8e07d99b1c25659bd872f282948cec70ffe2c1e189951d7d92adc0140f6f608008f6bb01facb30d5a9f9d4b78206525c64a01f96ad5048d3d6ceaeb1ccbdd7ba0b845f1b3c1e5007f3e7110283796f28b4843fb03b7630c9b2b7399d3c356e9f5a5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd2ebb027fe0b6a9135fa63c8518fbdcc9d8eb429dff09e0bb9f4ef74883cd161aef0aae44d996469e870ecf88c941a9f53c47ca765e1fe299ef715f8625f7d09	1633504760000000	1634109560000000	1697181560000000	1791789560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	403
\\xb997509cf131bb78239df645ab8c8ab3480840c9705c66441cf429c280bb45375173a9f4ba5d4700d21f8492b5421e811175e1b0ef55fafa4b5ff02ee0610a46	\\x00800003eb8b49579808abf424aa1b19ad005f299822e419b9f2423ec04d88b97a99a5d46e5cacad5f207a8fddef8266b5551fbcf277524f5826fea48b45e2a7b75584d28b7b70241324f63d0f47eb0e812fb324aaf53c59b1e1386f557aad1c3f3cb0853081e0d4d60b7409e39507cb499a55ccbdf6869d04211afe94cc3614ad0b4473010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x8f850c1c76628f40338f788445108778fc365519f49bec35d90c4a4d7d7605f6c780c4e7b993d1578f0e6f4746eccd6d364af5c315b71c662a54d21b2c02420b	1613556260000000	1614161060000000	1677233060000000	1771841060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	404
\\xb9971c38cbe32dd4e55323aa41d251dc475e66efd7c945e87b11424c286ede57f55b12cc78459bc72fcddc44db7e30e865b7129961db345a3271516a866b00a7	\\x00800003e6eb1ec38b85eae16c11b11455849772d253665b970e64a9cbe360bd0a252acc0494078e9865fa382367d961c510b8ab72e68cd3b7a957c63b449c098a674b7616b1de926530e8ef1d8e2aefff67236eb5b28da27f44d70e5e7c01e001f975c3307daba498a6caef6c27c466d415bfc036f45ffa8411bafb6afcad892f4be755010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x09cafa2f4ae49f5dbe350630e217b6bb03cd01de1bd40b1dc8a8bf918d918335f3c09ac24836be1540baf92a331cd30ecb6b963e0091ee91f46af1ec8d34fa0c	1619601260000000	1620206060000000	1683278060000000	1777886060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	405
\\xbcdf73f86f58878998848930138716962401f306b10cbbc70fb617310dd54550633eff9941a31fb04e0777fa2bbbcddb5679c9cb8b5160eaa1c4a91a2ad78aa1	\\x00800003b4b8e4462b34d394a1e6912236970d38a07311ced9f9ef7e471a78e1a051ed8e09760746c3f39407ce21f885fa17156cb3dc551f84a5e65278b5a04b048cde6204281bbb17a0148f00cf55d6af4f2b59a6e458c530d34b77ad32531b38605fd486fb602ef66052e53457b278525d354562cc4b7dc4d65710a8d3a7f43354b5e3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x970f46861bd7f97fca6e0b245254eb86b6fbd586ed97b33c5c73e5fb2f3648135cc8a8fb866ca7c12fe5bbe0a2cb5ee7af45ab07ed13c1c87e7de34f9a216f08	1629877760000000	1630482560000000	1693554560000000	1788162560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xc0ef7e89a59010c4b4315f22aad3523bde961ef61681b4b91e791a5371c4bb62523de1a2f1ad70f59d1d3533f1c349fa309ef88a51f2e42623ac97dc7cf80480	\\x00800003c80f7d646e9810d5e4cc1203a160d57db9eea03b9d44c9941c0de852fdbd21d9b091a499a39e6fc12a23516ee3870ab0c8175a6bb925e8f203b6cb0684aedb0013722187f9f086f54417c38fbd3a6b1e61d230c33eb86edafd7d556a5ad5f972c0fe0f12693ca5195c333e488940e9258dd6aa0be4a0f34032522148b11273b1010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xd4ae54dc5b431cc8642798d5f6da4e9d9faf07fe7f718934211940e76a0fb3e677a31f9c84ef5d85998407d8954d192a7514e3d3b55fe66c014b0d2ebbe96005	1612347260000000	1612952060000000	1676024060000000	1770632060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	407
\\xc09fa6dbf07ffe23d3736fbe0e390da778116257ae68b55431b0632c3e7705c029efbf68445451d1f4d246630cbdd21adc069590d6b76d717d76de130a509ee9	\\x00800003e35304a05641a24280fc616fd1b853dbbf2a6d364b3f6b27fa4e729715820401899894cf8bb4f8b8849667cc53165b94035928d06f8407df9babe39098401d312f0d6bf71baf69905e06b93ed707b6f38201711507f1d4e25137179a902b251bf2f8ce15a81f9585d370a37a7754b9f9336b07ac908a954f55ad263215aea57f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe60eef34079f7d31a6ab7a1f44bdee0159e768b998bf80918351d1a60e74f640bae92c384550d9244873fd06963195e9a50ae5e33dbd8b2ad685306a30fc8e06	1635922760000000	1636527560000000	1699599560000000	1794207560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	408
\\xc1af2997fddebfb5c39c1d3e5a42ec9b795b4bd266795775077c04399b153587271eacaa8a42d03055f1971aff90c0623f61991317c376cde8855a2b388bb88d	\\x00800003a418a9131fbaea2175ea07d2c8fb78164c1f870d1d9f49cfa5d665639f4bc102340b4fc853d393d81b2c3acdcb03489ae770d8c5d3b701a0ebccb6409ae8f43b50519c5706bcbd03d42ba9f2b3b84b6c61c6b93a6650d597cb81ed5ef7418ab24fa837a78bd6e0ceed82e703937fd78ed0a85fe4a70915b51dc33015a3a1bae9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xb8fffa048d2ce23de0d95abb9116f525361c28d79ef8d07e32576c6b98c3b3e295305152903320b64d496ad93f7426ece1aec65aa33b261c998ec865e0a3090c	1613556260000000	1614161060000000	1677233060000000	1771841060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xc37f584ce6de8aef73e5eb6fbd50b3be8f2f7c8fa58d59ae7e7a566942e1f56b824a6812928d99d7b3caef21ee80b44dd609e011d79567d2adef20f5b371ca34	\\x00800003cc4cd50e74429099f15bc45e1fc5fd5b7361d33e68841de1dbedee7d26563732072bf2765819f8ac4614d1a3fef1f462799c131a408df334b2bf2f3f26da5adce109a4d277c7ab7908826429cf7f3423e42e63d3cbd84806e8a019cc74aeafef2952dfe925e1be3ab7da0d4dc8ef563c451d07f3090cbc9621c6a76bbfaf0fc5010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x989966acfece4620c85c8e622a42528ec3d2331b829ec73ff8f8de509ee90d4a51f0245e6c3ebfc294c50fcc6ee55ba8dc49d2b47c5f5c8d5ab4f7f8bea1840a	1640154260000000	1640759060000000	1703831060000000	1798439060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	410
\\xc43b8b07dbbb991bf4a3f6a8c152e2c7658a7c119d67da9712c4aa13c128d2b82d4280df90d7e4f0dae669a896f25757924b839aecd00930bd559cf4370067f1	\\x00800003a0127fd72a4d914d0ef83586ed35b37bd9289e66d7b645f3b9a3f46ba5adc53037db11b5a2ac5df5a3e349ea9c75d7f4ba4762753ea8dec77b59a8c3365f0e0498cbdd0abd17d4794f721ea61dca913e1c1985187f48cc4ee28f53fb1f233bb1a42835d55bbd0d598e4f75333ee9ed0e66c658673b442189f9dde53fbf3f5b03010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x819d20de6c85a122a214f23c6bc3e82ab532bc8543b3ca4e5d56db9d41633c035ea397c0678c06379e9fffd93aa20060654e5e55920665de4a00fc509f52ff06	1617183260000000	1617788060000000	1680860060000000	1775468060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	411
\\xc9f3ebffd1e43302c024cd0366116b30813503d0c73293053c1f9a6156368008dbf1d6306e98ab1827575fc38ce8274fed7bf13bd4236e5d7c79f69031b7a44a	\\x00800003b2e9d218ded74c3dccb43bf2f4f788a30093abe934493d0d6eafe9ba4ff1a62421eb51a598a81ada7fd11052bd4ab5238c4a8f24b78ffd500556f1f5c1dd5101c03cad876dac75e593c51246c490bb1c1ae744d327f6941df5ecefd03ac36a6cea78641f2b721a066b2b1c948d471e7b2f65a0d08c03f3f7078eeff09cd9a8c3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x9e807128ad95f82c6132077849326b8a586e846ff4e8b82156a447c8fa5e17c0e02c9a934dac669cf35b78a66915da70c4394101daa01ae17d832d52aa262204	1619601260000000	1620206060000000	1683278060000000	1777886060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xcb6b9a50c472e8bcfb3e5ab74789d041ffcac7e40e9a491b3d4481121b99e0e8a8953ce220f85b0de7906431b768b9402d5fefa14ef105efc5d4a6dbea6af438	\\x00800003c7bb038d898a4fe4dfd0d1b21578062a2ed084ea015befa2dc82a2d2f67384907b57bbbd1f0a92c0f51fbf6b80fa3c378f2a4ffaf5b09a74c3425d2e47f49e84528438a76340c29345f545f4104d3c3a0d513c8b1e83739e5a6711674f6fdcca0f4313340606b2795e85b7290b9a260fd79b7dea705c57cbed269c5023a3caa7010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3a38d4225559ed9b5fc2cabc3512d26706d3669f4dbcbf7c586f4c6381ea2eefa54bb021623f98c1f7f6c353aaa1877a39ec26296baddcaf71755fd8f58fad0d	1611138260000000	1611743060000000	1674815060000000	1769423060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	413
\\xcb5bbb4308553622daedc1938904366142b5ffbdb370ea649cb45847b33d5ed74b85eb870b7fc5a2aa1ded2b8c549575a70ebb9c7519dc2c82e3934de531f34b	\\x00800003f55d4439767c59601698578fa7a9d8e5320ac26c6b68d1b671d1438c5c9f2a446cd58b7aac591095b9e9908f10ab7ff6e09258e55ba6352ee60be0c35bd2e9b44774e8a37e25e56d0d2faa0ef13b25dcd2a0db832593b63294c9af64ae2efec6be5357f09566f66175300a9e8469d17ec91be0fa96e1f2b83112c87bfee190b3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7edcba6fd4f3b81bfa37f2efe5f1c52f771e1291ce96ceee643c0646357c8adc80109076b58841cc885950fd0ba3a38b27fb4d35483830174bf72c6cebfe2701	1612951760000000	1613556560000000	1676628560000000	1771236560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	414
\\xd45b34596394d58126180b1092a0f9d86c16bc4c509e027da437fd3e3c6107861d20c5729fb5246249bf7592eef52e692fe42c580842afde52a08e560e611b07	\\x00800003c76203f2e54596a19661ae726b100c54c5e04c1343f646dc78947a542cf5ec1401efc96f9dad798c7b8060ca5384d34996c36d132664a8d48a97b2a24b42c9e6a02497709db8e589985274c44f808537901ac2d17bd13d024751b5f6d8e85c408782da72648411d928f4a0fc2993cfd4270f5a033b2b2e2e3da5df0a9d353f67010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x31bacb94ad9648b330933db24522f3f78834b9695e56443bd86dc120556a32a925ddc3898271dd968e81ed390f65960d06515e7179dd838f4c073abd32a3530b	1623832760000000	1624437560000000	1687509560000000	1782117560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	415
\\xdd879577392ecd153f59c3657f89286216666d4dde56cb76618bf7d2cf3af62bd3da02e04c8c192e80c9104f0e5f658d4784aa26aa1c6d72efbb842a87c4a011	\\x00800003a42e6061cc410be783be4f3ed538930d6a5fef1c1ccc63016dc7874380cbf49c0161e538b0e53e9a4d7ce3f1d6338dcd8dc0372b37f8cebad8c374c79cfbc200ee9a6849028acf0261d8c383cb7c01a7cf6b8fc67c536d9bca774de3a0ef1e04b905386b9cc8161686dc85ac595518fd9a30531cf23586fc37809437542b278b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x1d61de57534af408eb15ab6e0fb6f63a824b3e2faf1adba7d97c23f3870395963c5dd300a2ff17cc2591d8779059e275daf7d4460b5da2c68fa7e39db1b5720f	1631086760000000	1631691560000000	1694763560000000	1789371560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	416
\\xe3ab467073a85948d923a73d177c174fe9a31a709150297bc194981b06380d124406795be5066a6b5c6fbfe8032a41673ec2604068f94bdebf6723e3892efb35	\\x00800003d1499582005066e9bfcb88563f2944de4176dc6d6ec2ff6ce2a44866f79670c6df432af12e4e500350dc49741e88c989bacefb833cd394d4a76751ab92e9e31025745a8284d1b37fa5d2204414a6b32d221f573909c896894cff8eeedfcd0fd1aaaf8a1d70a16aed78039e71aaba28830fbdf5c090a4d4f77c7e94b2c1fe4bb9010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xa57c853da6e183f6e8e72f890c68cfb88cd0a381d6100e8379972b774c097560384686788d6977bce8e251416adaa2b2a0f99009100d00aaf1af3fd042dd9d0e	1615369760000000	1615974560000000	1679046560000000	1773654560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	417
\\xe8dbcdfd80f76b5a585b386a6eee94e5ddc731f219f01c669c3d7fb5484e346b52d59ea213f8444e296ce16d0d424985cb2c9258e87ba95164720fd10cfdc9ce	\\x00800003b88e1d75e97dcc84c51a9b7c2567d24fdbbfc58efb29f0b5fdc51be8dcb3eac3361a934f215720df8387de841ee6f2fdb4aebbc9c26a03cbf1243dd96a8423c633b77f4518199b5021d93dd45fe013c41dcd98e30c45c4c3126a1edcfd9675213aa818b3f23bdd20c73c0b2918baada14293e2e67594d9e68dffad79ab391cf3010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x772b38bc95c810cc55e73a3e596c28f477a6792c3936a19739c41fc6cf70d5b197622035ffec95da4fb25b0e1f882f63c58ccb3bd7f92d316e9cd44cde0ab500	1610533760000000	1611138560000000	1674210560000000	1768818560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	418
\\xed4bcc321985b26ea7e57e8aec77ef7feb707652482c4cadf7a2dc10499993eae24ef9de6a8178a3173927ff1613e524606400292880cae3aad606e300f36a37	\\x00800003c5a4464dc78f8c4c01eb577f58fddce6f66d8afdaacc93ca720020444b3bbc3e6222e418c9f9c12531204b1d48ed1007a5a68b325789f680b2a0cd6dba330e6feff0346060f781a81d1ca4ed417dfbd2518f4ab99c62edd73d7f45cfddf5ed9b8d4c33a988149e8f6dc16f68c9e016e61cd24199c2c0c1bd254a31c1ae0ce983010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x3e814469b027952600996af61a3306eb3129f9d52be6ef9d5c464b1a734fe8e593a1f7ccc2830625d9762da22e5efacf12da42094de23c726b2415ab0cf7df0f	1614160760000000	1614765560000000	1677837560000000	1772445560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	419
\\xee9bc244bc6eeb8fd54e81acef95452b0758f2213b69090716088bfed5e7667b657b7262c3342620d7135bd01dc8f5ed968e074665c990423df4cbc39c6c1d28	\\x008000039401fac4da1cbf055f5a7a1c511fb30482d8de9dc6f1974a0d75ccea3b0d2ae7a0ba01e157f6b68126c92a2bc886348a7f5a32a0df516f31749ff871ed53943e489a7626fa360ababb8fe7c80749694a620802e749bc46a4bcff43150517a402a89540075a9d9b7b44ae37f1ae03771e390c56969330cacbf6c6a639db526863010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xea14078bde2261f17fbe93d172d56e1233287d37d9cd585c7fd636d9c86f52abbc3d8e5cf885aa380789dde6f1e72b93a916b3be7dfe4977c32aa40d0b262e06	1622019260000000	1622624060000000	1685696060000000	1780304060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	420
\\xf153af67387550e181e7d873683235e9fcab7f15db6e43261cbd290d887cb1b1b373ae4401b4b1da8ddf6333cbaabd07d3498b5f56ae4c6209f2299e50d2c31e	\\x00800003f43e55b1c413fe5fce78bfa700a98d547ac59dc3f23730366489162597ff18fefaeade07a9cddcbefa227c46663872b08ce1533b4f3470f3226200a94eb27926d53ca504b387da83e067ce4064accd8827acfb72b95bf16f90626d0e9ee65679e04010eed817e97ab05f0f07565d59029c2c2ee2628bf85728dfeceac73f70ad010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe8dd5a5d8591e010b5997dbcc50c21d19e75ab39fec6c0b57ff9e8ece8660d3ebb6b6ff188254408c89dc4417895196a2d1a4104faf55d1e9bab742f50d66004	1641363260000000	1641968060000000	1705040060000000	1799648060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	421
\\xf43b58bfe3c6b1a4eeb6e8c2f88ffe9253a10faf7e55e077287d4d5824cb96a42c0c5cdc483ca0987091ae856855ce577bf327e989ed2a33f9f07938b76b3123	\\x00800003ce451be3e3575f0a9280227fbbe1d549dd77c59cd6fe630299527da8409b8e833aa3e0420434bc229bdffb631ecb535856bf8fdaf3e9c65487e71f590b87704a1c4803203434e092fa8fcb2f6f6a3560bef0e0ee1dee6ef41bd273c80cd28f324ed1e5afd10dbb114e705a0387842fa1abfc57de5fb5b81a89d944c393bf476f010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7e5eb6fbe3544acabf4e786284d11a69f18140ba9ea6a1fb538b1e3e527a388c3895446d246967a709e9b369428b4f2b07c4d3bfb83597669d5f2cbf711d0b04	1624437260000000	1625042060000000	1688114060000000	1782722060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	422
\\xf44ff930bc6ae32bfed352d16d334d27add65e18a835950ddf4f0eaf6af436c1b4bc427a3cf473f9349cbbbba168583fa4f4edd9d7760d732dff68cc7f2690de	\\x00800003d66a40f58fb5b0e3dad454ae3e7b210407375fb11ab601432a770319e0b9ec3a8175befaf832031bc6d7833f59cdadfc19bfb49e5271906baae321cc730b70528960e08efe2a407d632af520c98c5fa106c525db429a56e99b029e4b93f1f67d20ddbbd3b63036fda2721e9dda6a7f6171edfff2f942d15e1ed52d60cdb7571b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe64c1c54769b03190a95086332a32559c8b9a258e44716324bbe0a7bef63984df21325555e74f2e54ceeed371d26d4a9c60d51ce14ca3f3dfdea11be2d31b109	1632900260000000	1633505060000000	1696577060000000	1791185060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xff57036ee9eebaa8a094788f1cfed5b52548d9851e8de2c3bd1db3af90309121aa7c88af50f37ec401c53e097a37eadd7c0f7b8593dedcfc67546cd401be6a20	\\x00800003e6e27a405a094ca2f51613417e8192711c31d5e40892da162cfeae3f4103df8b0c20cd212ecdf69b97922690eb470ccdfc3d32ba70affd62148f685e3c80a0af075877f6746d6fb26a55ac354346e73c12caad731c4a4eb51aba625f3eb5474c568b6898592f89d27202e956f6a2ebc6c01d80404b5843beca480de26e8e918b010001	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x457a78279b025f346319e952324f0ce0d36a70b3adecbc3014423606b3f3990a9c089e866eb7096ebcd5a955f82ed9be3d2248704047b8b333c4698f0dced908	1626855260000000	1627460060000000	1690532060000000	1785140060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	1	\\x374ff747c3f6d62bd538e4739a4287542bdb620df927c773bf183edad1fd1fb66908c1c1118b7dc256aa73fced5224b42a1c9718c2ee6eaa6193a37d43c578ea	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	1609929284000000	1609930184000000	3	98000000	\\x85736cc5594acef4b1ca36c35e207a5b6a3c5de0fdfdd9e6cd36f2b467d5eac9	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\x6bb29a59c027f5570315bbed1bcdf97ce493fd00af8caf4e7e66ed96fb4dc722c0e9e357f6de1211c979faef2887282cb45e9abfcb400c3c259512a32eb0d404	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	\\x433dcc340100000060deffc3a47f000007ffab73b3550000f90d00aca47f00007a0d00aca47f0000600d00aca47f0000640d00aca47f0000600b00aca47f0000
\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	2	\\x4415b09aeb04c3f343f10bd3c379461bcb63dde3f8bc23796f82b2bc21d79267c6d483b12aee82160603401f5d41856acee0faaa62dd3d186c5333288c753ecd	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	1609929292000000	1609930192000000	6	99000000	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\xe696db5e9dec1482dd89a542d579aa5c0a43ea3f18084ac05a7fc35363ee0d095a5285932457808f37488358894b99d058272420c54a4c7febc22547ec8e6902	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	\\x433dcc340100000060deff23a57f000007ffab73b3550000f90d000ca57f00007a0d000ca57f0000600d000ca57f0000640d000ca57f0000600b000ca57f0000
\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	3	\\x98ede207db2fee9ca9ba6054ff822b073a4b20cf0133ffe123bf1511aee2e238d7f312aa5ea924fb6a8e2ab7765df9bd57b1110e4397cefb95004dfd36134b43	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	1609929294000000	1609930193000000	2	99000000	\\xa2dfec1ce8cc79325e6aad1f63f47e5853781e4d99e520f1fcf85f2c89f9aedf	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\xe1ae08fc9421af1b47554a67f5eada91e48c1495667671cd9d5dbb7b78fe1aa6415c1b10dfc575d26507f6ddbd44b706ed258961932098e18400ddf1f2ddb504	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	\\x433dcc340100000060ae7fdaa47f000007ffab73b3550000399500c8a47f0000ba9400c8a47f0000a09400c8a47f0000a49400c8a47f0000600d00c8a47f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x85736cc5594acef4b1ca36c35e207a5b6a3c5de0fdfdd9e6cd36f2b467d5eac9	4	0	1609929284000000	1609929284000000	1609930184000000	1609930184000000	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\x374ff747c3f6d62bd538e4739a4287542bdb620df927c773bf183edad1fd1fb66908c1c1118b7dc256aa73fced5224b42a1c9718c2ee6eaa6193a37d43c578ea	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	\\xc78f6e43295609893779bb712c2b2a4459d8cd71c258f2b5870c9531859824594a1c6c42573cb2f888c63beed53a056e99af7172bb13eda3571cd86664de010d	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"EQ54FRWFHF25JKK1S5EQKJMHDFNY5MCJ9QBS5K3T8CJJSYCTTZ4A153HD69FJYZHK2ZVY9PHDZCSZCBWSPPFYWDSKAY0J0WWAES61D0"}	f	f
2	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	7	0	1609929292000000	1609929292000000	1609930192000000	1609930192000000	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\x4415b09aeb04c3f343f10bd3c379461bcb63dde3f8bc23796f82b2bc21d79267c6d483b12aee82160603401f5d41856acee0faaa62dd3d186c5333288c753ecd	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	\\x7c097a344df08759fc532c69cdd8fa1d9d02060f02c49e7ba5dc5cda77ae68a4ecb944ccc2d6e82f7fa85ebe75dd4bbf94fa803d8f4db43bfa5517fbb3bbbf02	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"EQ54FRWFHF25JKK1S5EQKJMHDFNY5MCJ9QBS5K3T8CJJSYCTTZ4A153HD69FJYZHK2ZVY9PHDZCSZCBWSPPFYWDSKAY0J0WWAES61D0"}	f	f
3	\\xa2dfec1ce8cc79325e6aad1f63f47e5853781e4d99e520f1fcf85f2c89f9aedf	3	0	1609929293000000	1609929294000000	1609930193000000	1609930193000000	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\x98ede207db2fee9ca9ba6054ff822b073a4b20cf0133ffe123bf1511aee2e238d7f312aa5ea924fb6a8e2ab7765df9bd57b1110e4397cefb95004dfd36134b43	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	\\x12c1e10f6aae1f513dfb63e1e04f8307bf3cd977f6bf2646ca5f5b47bc5183c98d7b04ddab6ccf6ace7055dc5e601f52ec88d1bb84f276f058b9e1ef5d02d704	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"EQ54FRWFHF25JKK1S5EQKJMHDFNY5MCJ9QBS5K3T8CJJSYCTTZ4A153HD69FJYZHK2ZVY9PHDZCSZCBWSPPFYWDSKAY0J0WWAES61D0"}	f	f
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
1	contenttypes	0001_initial	2021-01-06 11:34:20.324866+01
2	auth	0001_initial	2021-01-06 11:34:20.36478+01
3	app	0001_initial	2021-01-06 11:34:20.407037+01
4	contenttypes	0002_remove_content_type_name	2021-01-06 11:34:20.429381+01
5	auth	0002_alter_permission_name_max_length	2021-01-06 11:34:20.437772+01
6	auth	0003_alter_user_email_max_length	2021-01-06 11:34:20.443585+01
7	auth	0004_alter_user_username_opts	2021-01-06 11:34:20.449163+01
8	auth	0005_alter_user_last_login_null	2021-01-06 11:34:20.456736+01
9	auth	0006_require_contenttypes_0002	2021-01-06 11:34:20.458234+01
10	auth	0007_alter_validators_add_error_messages	2021-01-06 11:34:20.464807+01
11	auth	0008_alter_user_username_max_length	2021-01-06 11:34:20.477133+01
12	auth	0009_alter_user_last_name_max_length	2021-01-06 11:34:20.483123+01
13	auth	0010_alter_group_name_max_length	2021-01-06 11:34:20.495893+01
14	auth	0011_update_proxy_permissions	2021-01-06 11:34:20.504096+01
15	auth	0012_alter_user_first_name_max_length	2021-01-06 11:34:20.511441+01
16	sessions	0001_initial	2021-01-06 11:34:20.515924+01
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
1	\\xe29d7a15aa873d4fbda6c08daa3994da2abd449f96617947892bd1724c578bf7	\\x662c13f60d73112f3659604c041b13fa2442ffd3e9fc8eb258e1b8e431c77fa077bec0eea0591054b75ba9394ddc8057c485d5dd31871372a33511414246040f	1624443860000000	1631701460000000	1634120660000000
2	\\x696fd6421337ced16a78ce3101cb56d45ec71e145be51c92cb69a6ed5a4a488e	\\x7237a64b0fdb963153c36bc2d50f17e2794c55591e94e9fa7a00dfe3b4d522bf372f0d53cb51288836c8b19199b1ddfd820c6e3b8be952e8093e5816db4b4804	1638958460000000	1646216060000000	1648635260000000
3	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	\\x34c42d5626c2fb07e2ad177de0aa8577892b9307172970fe2f4da3b8647ea85094707aae8565e8a51d08de9d0320f9b144408f5718afff215a0de9e3f9c94e07	1609929260000000	1617186860000000	1619606060000000
4	\\x7a557f3a9810b5c50f08e3853c5acff702403895f3e8662ed04f721943d087cd	\\xbbf25e7d91b0a65d3c00bf37af719b8ca799fe22ca7e9cd9e8a922ab9ec9b07873258842852995626322e1719e91c879aa0e4ddeb38cba5367647eb7763fb402	1617186560000000	1624444160000000	1626863360000000
5	\\xbe76a2f85301eb93b45a5b4210f59f22d3eaee17218d89212a912543e185f6dc	\\x5ea8a6e0a00424b330829c78cc7e38f3468bd2148811689edfad71d588d092c35c80040fb3626345ff4ecbe7c8b2e7a3220719c631f63a1eecc852fbd7e92b0a	1631701160000000	1638958760000000	1641377960000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_pub_hash, denom_sig) FROM stdin;
1	\\x85736cc5594acef4b1ca36c35e207a5b6a3c5de0fdfdd9e6cd36f2b467d5eac9	\\x7e501e8508142deeb0edbe1ef63f770b333596538da65d63255f890076033c7c49ef9b78b8e2b84b538d7edcfbc6c01e160b38e41ee8fdcc96dec75ba83dfbb1	\\x37e2394e84770a6ffe661c8518812ed2cf97f1b65e9f26440350202dc74b5fac413f01e1ddf0265dd7e72e5a47a8a63c5b035046f1759b54d040223b11ab532af47d0245fc6b52490610f777eb49bbe1daa4c7187d140b054a9415d695295d64f4b266a1971556d2940d35c9f19576dc4cbbb334483a8d6861b0a23ac745c686
2	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	\\x581f4b9ff7a2dd6d89e26ae1d367ff34ee60c224b5c83105a8a9cb541b5f7bb27e2f306b3f2adfcefcc9f7d9fa2d39aba80d3db2a2d1da78eabf937e907ec4c7	\\xdc3af9cf118ab6d296a6b5d197b9eb2dc63dbb24ad6b2b2934e339862218dbfc1a590e21dc9bb57f7e533c2cba2433d05b31d735d1bc1664bf097044cd71ed753e84f6fdc383a61e935a4605d8d65e2a3361d4cc11d6495875fa30f6d0732e07769fc8b772c9279633a4410b55f5f14544aa742d78e445091f574551c31d9432
3	\\xa2dfec1ce8cc79325e6aad1f63f47e5853781e4d99e520f1fcf85f2c89f9aedf	\\x7df6903220fa0572987de31c75baac7ce63382a7d673c9146e85c94250fd7d0274e1d8c37f221774d5e525248d9ca5b7cc5558a1923985c87053713667cced5d	\\xbc4e36204fc7868a0194d0d710888f01678d77693fc8bf36957f6518990821b1a9aecd8b5829702fdd0af4509cfa665eda72567834ebd8d11cfc139946209f84fc1b58641adfed38b27543f523490713835e558351b4882701d4499f2caca3deea5e8e9abf98be372dddc2c7ff4ff55e440e47af20f93fd71871f2e13e8cea80
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x9669049fa967e3e4c5c59376f2b6727e75dadcb24b9ed1d897ad225a414bfe2f05fb2e542330ca38ab29e0facfd022d63b1fe0426a1b0beec9595946b2d471b7	\\x75ca47e38f8bc4594e61c95d79ca916bebe2d1924dd792cc7a43252cf99ad7c8a094716992f97bf198bfbf26d16fd99fb17ccdacff71b99abc09039c53b260b4	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.006-03CB73C6XKCMC	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303138343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303138343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a534d4739375839435a4859394845354a44564635444b4a465354584e51354a39454644335034514e4d48354d4741425a525147425953454147484b314a48524e434d5931595046543048444345525a573131364d3652425856344e4a50413650424137334452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d3033434237334336584b434d43222c2274696d657374616d70223a7b22745f6d73223a313630393932393238343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323838343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2257304b48355941513559464556503454563336324d52463354435258363333505747383754543435444236545937563646323547227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d5157375852384236384252464b53583253325354534132304e374b37344e33464e34514145434b464a365048534a32324d5a47222c226e6f6e6365223a224e59474d4d4a574339565a33434a5935374646544e5153363033564b5638545759484d4247505458594d4d485146314a43354830227d	\\x374ff747c3f6d62bd538e4739a4287542bdb620df927c773bf183edad1fd1fb66908c1c1118b7dc256aa73fced5224b42a1c9718c2ee6eaa6193a37d43c578ea	1609929284000000	1609932884000000	1609930184000000	t	f	taler://fulfillment-success/thx	
2	1	2021.006-01C23DJKNM8DP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303139323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303139323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a534d4739375839435a4859394845354a44564635444b4a465354584e51354a39454644335034514e4d48354d4741425a525147425953454147484b314a48524e434d5931595046543048444345525a573131364d3652425856344e4a50413650424137334452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d3031433233444a4b4e4d384450222c2274696d657374616d70223a7b22745f6d73223a313630393932393239323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323839323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2257304b48355941513559464556503454563336324d52463354435258363333505747383754543435444236545937563646323547227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d5157375852384236384252464b53583253325354534132304e374b37344e33464e34514145434b464a365048534a32324d5a47222c226e6f6e6365223a224b464743395459463237573736473931485642504730544e31443447343236514538425152584e32325332593033504d4a343747227d	\\x4415b09aeb04c3f343f10bd3c379461bcb63dde3f8bc23796f82b2bc21d79267c6d483b12aee82160603401f5d41856acee0faaa62dd3d186c5333288c753ecd	1609929292000000	1609932892000000	1609930192000000	t	f	taler://fulfillment-success/thx	
3	1	2021.006-00D9RJ921Q728	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313630393933303139333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313630393933303139333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224a534d4739375839435a4859394845354a44564635444b4a465354584e51354a39454644335034514e4d48354d4741425a525147425953454147484b314a48524e434d5931595046543048444345525a573131364d3652425856344e4a50413650424137334452222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3030362d30304439524a39323151373238222c2274696d657374616d70223a7b22745f6d73223a313630393932393239333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313630393933323839333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2257304b48355941513559464556503454563336324d52463354435258363333505747383754543435444236545937563646323547227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224d5157375852384236384252464b53583253325354534132304e374b37344e33464e34514145434b464a365048534a32324d5a47222c226e6f6e6365223a2250324345585153364639424d5756394a32393348475142523331453041475354425a39594859565656474d354d5745414d425630227d	\\x98ede207db2fee9ca9ba6054ff822b073a4b20cf0133ffe123bf1511aee2e238d7f312aa5ea924fb6a8e2ab7765df9bd57b1110e4397cefb95004dfd36134b43	1609929293000000	1609932893000000	1609930193000000	t	f	taler://fulfillment-success/thx	
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
1	1	1609929284000000	\\x85736cc5594acef4b1ca36c35e207a5b6a3c5de0fdfdd9e6cd36f2b467d5eac9	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	3	\\x6bb29a59c027f5570315bbed1bcdf97ce493fd00af8caf4e7e66ed96fb4dc722c0e9e357f6de1211c979faef2887282cb45e9abfcb400c3c259512a32eb0d404	1
2	2	1609929292000000	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	3	\\xe696db5e9dec1482dd89a542d579aa5c0a43ea3f18084ac05a7fc35363ee0d095a5285932457808f37488358894b99d058272420c54a4c7febc22547ec8e6902	1
3	3	1609929294000000	\\xa2dfec1ce8cc79325e6aad1f63f47e5853781e4d99e520f1fcf85f2c89f9aedf	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	3	\\xe1ae08fc9421af1b47554a67f5eada91e48c1495667671cd9d5dbb7b78fe1aa6415c1b10dfc575d26507f6ddbd44b706ed258961932098e18400ddf1f2ddb504	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xe29d7a15aa873d4fbda6c08daa3994da2abd449f96617947892bd1724c578bf7	1624443860000000	1631701460000000	1634120660000000	\\x662c13f60d73112f3659604c041b13fa2442ffd3e9fc8eb258e1b8e431c77fa077bec0eea0591054b75ba9394ddc8057c485d5dd31871372a33511414246040f
2	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x696fd6421337ced16a78ce3101cb56d45ec71e145be51c92cb69a6ed5a4a488e	1638958460000000	1646216060000000	1648635260000000	\\x7237a64b0fdb963153c36bc2d50f17e2794c55591e94e9fa7a00dfe3b4d522bf372f0d53cb51288836c8b19199b1ddfd820c6e3b8be952e8093e5816db4b4804
3	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xeb95d759221a7275734617dbca22c469dfa63f48f90d795397791e4cab44f782	1609929260000000	1617186860000000	1619606060000000	\\x34c42d5626c2fb07e2ad177de0aa8577892b9307172970fe2f4da3b8647ea85094707aae8565e8a51d08de9d0320f9b144408f5718afff215a0de9e3f9c94e07
4	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\x7a557f3a9810b5c50f08e3853c5acff702403895f3e8662ed04f721943d087cd	1617186560000000	1624444160000000	1626863360000000	\\xbbf25e7d91b0a65d3c00bf37af719b8ca799fe22ca7e9cd9e8a922ab9ec9b07873258842852995626322e1719e91c879aa0e4ddeb38cba5367647eb7763fb402
5	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xbe76a2f85301eb93b45a5b4210f59f22d3eaee17218d89212a912543e185f6dc	1631701160000000	1638958760000000	1641377960000000	\\x5ea8a6e0a00424b330829c78cc7e38f3468bd2148811689edfad71d588d092c35c80040fb3626345ff4ecbe7c8b2e7a3220719c631f63a1eecc852fbd7e92b0a
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xe02712f9572f9eedd89ad8cc2a61e3d331d30c76e4107d68856acdaf1f66788b	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609455600000000	1640991600000000	0	1000000	0	1000000	\\xef4cbb880a50e98016a07b6e8014de7597aa9024a00e99f7c587b98cbf624573d41f411106b1f3647d04a01c022a9e22de7f75c2bb6b6168de47aa5211101707
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x381d2f8f980b57b957ea1ee0210124da626406a9f95649c625a1a8ac0553b1af	1
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
1	\\x41458acbf187459125fe794f2ff608d4c652b71eaa33deafaa24c502f902bc6720e075ed14dcadaa1b4a00ed7a66068fae063eca6f072bbd2a7d8040d854df0c	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1609929292000000	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	test refund	6	0
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
1	\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	\\x85736cc5594acef4b1ca36c35e207a5b6a3c5de0fdfdd9e6cd36f2b467d5eac9	\\x733095c2bc68dd191e269bb96eb67bcd7740cbfb6f119145f895a4a2ed5e824242b4b268635a81bac3f12c6a35ea4b7b5182b9e2042e1e91b0304177384cb80d	4	0	1
2	\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	\\x291c032bc2024b9b848dc2bfb5d70f4f5d316bf617cc4b3bf39232b210a257779f48ce304cfae63757f36e36e168c94303af36f1ea72268773dab17346da090f	3	0	0
3	\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	\\x76e1a9c4394d556241fe96b34414c481c6467d0b60336725098fcd5421a6bcba3a77477e2180bb1db5973ed933d220930bf1356771cdac865acdde2b56484a04	5	98000000	2
4	\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	\\xa2dfec1ce8cc79325e6aad1f63f47e5853781e4d99e520f1fcf85f2c89f9aedf	\\xb7952b2f301ec50248b4a414e5dd1454ec170091d2708185bd3d3ffa2adf1e7727620077689141175ace15ae1801515fe1e5834153a743adfafa849e2b7b350d	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, freshcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig, rrc_serial) FROM stdin;
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	0	\\x968077087e257b5bd6c6e9f568c8c07d4057b037951c21ebaf5a0329c5c4fbfb481a91830b31282cdd1a29e765529e692a99283ab8a398ceaa1b5c8230d4ac0e	\\x307eaf197e8d962c6fe82c5326322d3fd832e126cbd6d55a7f1386676c441602a88b51323e4b17ecedefd05d22f6961c7df36a44839ea5a7bc1d03b18f7c3fe2	\\xb2aa8d530c5874dd9a40b90d0031acc7975f9ef8c81967ae1c7074162eb811038e083b9e1d7d9cb6c288377af7fae606da5f48570e7c2c6405b0a427b8f593138729da91d101ecc3e04fcfd0bab23761266e08cd61cdbf38aa8965686a4ef598e89cf6c162e3ef17c6aeff6b29d63781baf9a54126c274431d6cc85085c63ae0	\\x8b5c53f414eebbee04abe771ca39d5715978aca27933ec308909496212b17ea4a7a31ab56ac6fcb14f059e1266f20f1063460dce99a4e5c0f17be0ebb129aabb	\\xb7ea918b78ec28bf4cc87223869804fb47f2137bbb3306c91f2e794574494b9d4a4f85a8d20a69c36d8c5fa312c6e73816b460f1cdd2a9d3e6be1e09193540acb361c577a44d3f18fb69f402b723700485ab72f92959ca10ae144a4e338b42cdf8b3d2dd7b17d89d65bc534dbd10c894f3bcfc88866c72e7a7087fb134dee09e	1
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	1	\\x398835db6f2da01cf1cebf3735111c7eb3a51c2ed58db98036363474d3fe5b0ffd09a89cae77acf371440455fed2a7f5e32254bd0d44f380a242055a1b9bac0b	\\xf0fca82ed5e1f475885fbca451b7e6d2432530bd12461168ae397b81d818768ff7c392e11593427066f2f3b6ae605fe44de945eea1c6cb67382b1c013332802e	\\x8b47d01ff6cf7923f32526e708caf1204321ebf85a95043b2a7489b596cc34bbaa7c39c3811fc3460056ed292e71ff68a92ae6d9f610fa94e7289c4f01cc805077fcecafeb02c5b742cd15eaa3a7e2b1f55cfb56985fa65c1ba400eaba9a321fc8b93549e59e42290a6731fa38291cbdbee1d4674f63e711f97c2d5d9489cab2	\\xfe57a2ee86171d0200a30e32b7037ed3cca4caf5d0792372477fadaf537339b102388f430e734fa4a94ebab37768c725d50d20af0bc73d6295de8959cf3e1d17	\\x89dd355b0cc6353e3f82730b30e840d96a266de19c50d3c5a012c1d1c651b0b2174706d212b7aa353816dcd0bae8e682b2b5cb10fa942b234cdea534e351c4d6c65a915dd649a422fe4ad64b66089a820b00baeb55f16f787b1f00b3bfb166776dd34d583b3c982b60b5d43d90f783ee9de290276dd54eda1e1b4a76352d4355	2
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	2	\\xa5e196c3ed180cb003c59e4541235329aa54c10a1c875640aac1b1d0b0d9b9c25ba8f0db04b30df5e8645ba25d0af5a2e36d8898e55df94bec0beb52f55bfa01	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x72a5ce9c1c3c7a5d3c6e5ecb41b68e97342b0f4726396c0f11593b6ea793b01e9294eb212ca864ca1c79165fe09ea8ac496e644a54864451d1e3bd9ef0455c60677d999e76cad274e5ca6c13e192664038a167d169c7ae735af8eac180f91e41a3ea4b2143b06fcff2ab3d83ed46cd52d94678de1f254fc3d96ddfc53d3325b9	\\xcf39fd88ed237f87244b1c2a4fa942b9eb16bacb4db4b33d06d0427bfa5cb173db3b5d775be34118ecec85e062759e3f6546595b7184fe1abec2a64a55ab1c9b	\\x5407096e03d780e2b82591527b64626b12bea592278055040928db4e2c70b443fcb1ecce48627fe9699f7fb917d707c43fdd9df2df4753372d8e0d36f0efea850f4312fa1d7f256aa4e9d59aa185dea2bb4efacc66664520a96f78a50a843d663224484c23f9edb3396be3ff1af8ea95df3ed52bda342f9680fa45b30c79f9c7	3
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	3	\\xde92737b4c6b6b5ab787da22e12518d7edab9ce37e7ef46705c1aea0b8e7637e7b1f267f13c1d7a404afbfaceff09f34ef1b608b8b85991d9321424649098400	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x9456519c938e74b48314df83d20a27fc02dbdb1f82b0c2588920c91f2eb01405ddb6d7c96f18e3cd61a986f3a05634c9a5ae85e3f3358a2ee6fd785dd88a363226dbf25ccea6d456656a071c11f35dc28173228417702a7ec63e8296386c49ea7ebd0eaeb4fa333c7feedd517d2b2067c05b7fac4402e1359002adaaac57e202	\\x918b1e631471e1cb29bf42866e6a116986da035a79d64de6b387ea81129a2bab30f56e960bcca151e63eb139083f4ea8fa902402bee49e53fa7e4299e2c3f5ea	\\x1a887541334c57e221dd4bc2db8da435c38c5dae2ddc2c9ee8b87510e26bb5a04cbc78749a6b044468d3abeac66a7af1306bbae0a4ba7438bd40738ffd8c8dc7de42ca5e1815fc5a57560df5bc147515a153ece7c2abd6c801e52e9715059e9e9e98ef0bf7d4122d3b2435ce2dedd5c3b3f2eb61454f3e333d8ac955cf750009	4
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	4	\\x02700a8a1c4f1aec690f51487cb77ab75e6660596bf6a28433a25775d399cd04d4da353cb2884ddb8b7343f5f985a6dfbc7272d6ded29b10610761ea18ad5908	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x10467bb0d436cd62208f7f83c4cc429f09c25e21d73c56dc68effdce96ab13815c0fe8f69f6ac75273c6a797e88130fa72e62564c196554491b03a62419d97f7aec92381e5e15d543eab6a2867ece7bb401c21ed7f69bd152a6e832ebb829b76b5e2cf35b520f21e1f4ec5d390c1190aa8698c5419494207e368eaf781fc2d94	\\x7c006cb7a44cb561b312fda467c9f4256558544b1b381d79829d4ebc5e24d5dbd221a370ada6275ef32f0d572d1cf99ba6330539e9de88ef84007c1c9bfcf3a2	\\x915ffd03ad2f3754ed90ab6b9ba773ba8817a8c7d936b01e8bd0e462627d3cab2d86f4a694d1b7acd3d9f33ed1619452e545b528cca251efff72bf19e215a3bea119bab2fae28b3195b8e098cff51b0b17a823b299b0999aebaa9d0e3910d1399cd434b11e944926aa426058d72762b01c4916e942e2e31345fdae5d858d9672	5
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	5	\\x97a8cfcb9965344e1283dac1ca486580e32a9730d17203ad9ead728a314df8c79795c2f3e7239cd752589f9e135cc47c7df46a95c6ae992c12fe3bbcbf30cb02	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x520e346f31589c9fe9361313dcac3042bd91c2b047e54f432b9d354c0720e7e6c86dcb54cae54ff3a2779ab219b3e3808cd658d788f464e446e04e544b0648b58625dce32b0864f0a983aa62e18ef8708dc0b6f45b8dfaa26680aed1f00a5e54319a71a066804d02732796c0a0717cd0b1770c9a57c49f7ede76bb0e3fb2a504	\\xd10d9a484880edbb16693086504602f42d521aab8d1ae53cf99b025f05deee1223b4abd0580157783e1fba9395c23aa13ae10ab3ae1caf0cafda89e369a56d97	\\xc5dda1586f7c8693628045fadc1b3cec19e677d38ee7a21f01f3bd45d449fb3c29b3ab70ec8151d97b24f6160113ffb8e9a4f01f774f4e26f27b0a45675d6f69a4f6116f37b000f1dda4b1ccb3e3689d4689b7fc79615b6383d6aa27dd5cf896e9c1d203c1271ce395c512c918e8f400e0dfc88290306548a9a09b77bf3af093	6
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	6	\\x7608330fc1dc92cd6c8e1666d0cb550c4a4dfc2f558becc50f132230d87aeaf95e79d07b390872e5873d4d548c346eb6f5fa7ced70379eabe75f1ac0b1e82406	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x57a8d9f37d91159be6cb9d8181bc10ec522e9e23b73880d27af8fc9c7c71ef08be24d19553fa37a3e1525391c663e47afe5b0783043cf7145d29dfc73369b61063ac29c83e68c6cf710a11be5da7c2bc8b71d22a30145b035d00d6793617290c51d6cd186c291c02675735ad47508c1a2181be12fb23f54425065b3200251773	\\x7f6e20fd8c35f83077ce752b83b916081bad97d7c48ee750f29dd94cb2c7b79d0dd131a5cb04d8a4d2d53679f2701f34de1de723df86a9a40bbdc22cbffc838c	\\x7fcddba2bfb4f9b6bb5724d4d07b1457b961bdd0386d16b88f683b372a47d0273a40bbfab3ce2263ad37d5ae1fc61dd2f681631e6ba343f5fae3467ebfeb806bafa10b3a1509351e2a9f3e49e08fc88d6b6bb91429cff67c79f2358aea5629cbb17ab629b4a9ca72207e5285db6c5422dda51ec8fcf2c3c8bf27c5d2ada9df39	7
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	7	\\xb51ec9a3a482ab9560b90885b54a6ed8d5657470a0bc4e25100f45d21be1a4710ca7a48e421e127a61360890a62cb14d56742f7e0ae7ae2bc8e57845166c8609	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xb4d501c69864cfa3c41c691bdddc1686144647f18a1c0ba426cac7b0f6845458cf442e894b79c937a05dc9664ad799d545df5cdfe825be828f52b7d8998b6aec5a391f4798f683830859b41a9a75c37b1da4c05ab2861c9fa73792b25fb1e7be759cf427d0ab7ba756e1ea418f0fab48cb09a6c03cb17f5e9f2da79246fda49d	\\xcc13526b2f21cebc92cf9ab8f11cc51676213d32a99e68972d95922bf3f50619d9e8295cd01b761d45f472ecffa0a2cd1d36a4bc6c453cebaf4a9899d620dc5b	\\x8b6796fb252af20e675d7a7b0124a83e99e9cc73067caf1a3fe736f41c5259557b9ca1207297160c09282ad6bffd07f16ca72eb25b9853c1aa4f88354b3011025e944afda6b36b69b0b7a70b17997b8e4da1214e896d928332ed14e0470802180abd83c1c892b0ff18350feaf05c950113d251ee8c5d6518627532c97c9a1249	8
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	8	\\x05fec23e43d5e4e42af1a3512b02cdcead962a0dd6f0af41303912cf3f000b466c1c2d1b62ce92625a8f784195120af42806a98ece4891fbb6588d4292ea410f	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x7b0a3aa0f9f38473ebd1ec510dd1a612e6824282d5754c20bf4cc66de291a6140bc6c0874ea4b750a9ef8d5a37c44584231bd387a9b4c7bc3f3b9c9671ba0552374cb7eca85f4db952278fe3e895589c89acce155ce2580965b32b6071703203a595094392e6d9740888563c64ba7e365ec3d1e2859fb05a2d481919448a91d7	\\xc0c6bf236471a4afeb5c94081341138c2485567145bbad148ea028e48e8f6ea498a629df516feefe7c85b3c8dbc1e1f6a012ebdc8db43af81ae5588f0aa038a2	\\x1b9609d07bd8c6d37efe8ed9c6474ba4055632c6245b8859159af0407747cf740694267180b577c6b833c012b463effa7e654d3ad6cecdac8817361ec37919277af2a079d62e40329653104197e81e0f092f24ac813c6370ceac6dc8b409191677bfd37a94f87005693a27facf298c1c0adb10df90072916f4980fa149ceb33d	9
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	9	\\xe969d59a7e532b699e3bf266cb094a3808ada3b238f46492e133e80e8b17ab7e082ad3566ad66427d466e84f0ae0aafa6a4e019a72d491a97ad45a879f6a8307	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x64d2ed5758cb11829e9ce1b721effe4979c8f1c4eabe8b56a4f633bbda12b254ff7a7f8b5735b756032a7072273c2cf2c9c560cf67cff2fbefd20e7993d179e1f32d87cd9a43efb4785d8398558a28480fa1b1f80d11a3fa6b173c580e89b883f257d4ec1ab22cae7c92a291940844b0ce39a3a3a637236fde5b27afe98d8af5	\\x7403e9bf8e9db866f2d30fbef6453da0127d067b3691e8be3898b1e8d37e2cfb3b65767bcca91846a5cf24618f3089ba681896fcedeee4b2a6685386fab73972	\\x842b20e92e4a205b02d71b286e1350c971fe008f26313fdde0fbdecdd3124ecc97e439b9a285881cf79be47d7304f2db0f42990f5473c732ab5d0112345ef692422c209ffc9b7f1109de50dcb863f582107692534325ccba1cf209c1131ce725ebb9e9b34ec258fbd72bfcf1b30c7235da1b4c2083d4dbd6e602554754dca720	10
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	10	\\x87c588d1f5ce234f4d6092b9bceb46fea0705851ad9556e6e47043443523e2ac30ca6343d26d9b490190a17f13ef9fd572d320ee06b8599f93b1d663e6d80f06	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x6e25a2115e8c37fbf3e440b6d4b2b8b22760b0d8d30ae646c58205bf0b0ddaebb53cd87a8690a474cac16b2f00aaf073b4a0ef46f74e3a1d8ef48182b65c5cc2ef7b2d398b35017e7d3e508a5297ab5850ca8f8842e28d11584b119c8ef06883d7c0838184ac474e95ca97384ae3554800d869c2ac696dda041f88fc20926b1f	\\x47e58de0f9e08795fca311f5725f27f61767510a2ee65abe35dbf4e8b9b730c51536e134dfbc5e8fd089757dccae85dacc1148876ba6cbf9f2b9df87da414f75	\\x1acc62af7d8f76bb220b2a6e4e7ef93ecb0bb4b2ff09ccbffe8f17b21efc5637dc4d8f021b3e417fdeabd1c6076c102e13d1b84d4b80e21b374faa1d3098f0fe14962da6e5e3b85f54ad4c74330ccf6f471cbc9618043db5a5821ab79f43baa86267b32752e51203bbb95bde5ed112ffef2b1d7fea0f50a7ae8784e45794878a	11
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	11	\\xe0eae1e9b0b4a6dcea63db5bce935f3139bd78608d7bde392f5c2bcaf2323df6b95aeaed363b6e9a0c0ca5c158506e3030467105c8484ca994b9d41f2759fb00	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x288c84d66e67fb18ffeed827264a009034ee32c4611cee15638d23e3326cccc10c4cea0ac9769d4de32bde5eb67715b1f7dacd7847ae3239fc0c32c54684fd13d18d55aca2e8c88fb86afeef4193c12ed9894a024b35e8d12343ce793de6158441ee2ae9244b519eaa65455d0b8171b4f0a44e52127e65f20b68da443275684a	\\xb1a133c029b32519c387d56698bb35c4fc2681231581f26fedf65378d444fab60432d97559b3f1eb507bd143d3f0cd249bbcdb6996939b8257f8a3dec92fdcdd	\\x7f4277975425c15f03e06e2f9fb2a8b7477c34122348e6ff2631901572c5fd0054b4e649b0947b4ba3cadd27d02aa6ad5cbd91851a33cb6f97ffe69f30a433724ddbcb23477b89dde62fbc230071f449f8771aab3a1317e5a2c1c38ccea42f6da21498308b1ac511d67de7b3877a7ed1a1dc4066e4f15e8162587196e3328ca6	12
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	0	\\xea5d9f2dfd8fb45ae05764460be8f3ea5f295f4b6e3cd02d6e71b42fae6f46131e0c85ac75dfaf043a6c66c4345b7c3496912c32d09681f8fcc6313dcb20030b	\\x307eaf197e8d962c6fe82c5326322d3fd832e126cbd6d55a7f1386676c441602a88b51323e4b17ecedefd05d22f6961c7df36a44839ea5a7bc1d03b18f7c3fe2	\\x54e31a819593f5a743548ca8ef1f87581b1cbbbfa2052814b4258fe8dbc7d0351e0d16cb627599c7d3dfef80ba21224862abaf501333708a2735629e2fca94d8e009f2b7eac00561f57b6309fec59a353b8e762cd2cc13992959487a6da3fa0cf36c14dd53f67b2b2baa4bd10affbe99e5e9234b0c2a53cb339819d3d912700e	\\x4fe219e6e3b130021a67a04346e92fc824234df9b638f6abad5b80464545169aab4e58981fd5d13c6f245dcd349ffd3f3d79aaf63ff54310dd2e7bf86f137c7b	\\x0ceacff8a7967267e7970400d02665a62efd660212a3ed535013798485a98d4656b763aa386557baab5ac32f22e970553188ad7743f69c606ccf9fb0c2feffe85890bae47f889b7629c0927c87400dc0a548f64a79232a3fa553f4a845c23eb88e41a07781af0fb600fdf59a5194c30f6416e841b77dceca62a7786c137ec0e0	13
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	1	\\x8c211cfd732d2e33b76f08e55920afc5e01dac58c6fb05fc78c48c8692adee564302d5ec0c969a916608c1a6dedd4fa1d8712f38c4e6cfed5a66618b9cc5120e	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xcddd6501b747174d5f73f0d1461c389c1ed245d88339d5e0d4478ad5b5de88cc72fa8e7d28bbb002ee087430adef635d88f8a5a09cf0e4be8206460bf8580d76df70a739b3291a4769561b37e732d1b04855f163c47e501997af853b738673205887d18eff698122f44e4a8e05623f72365ba28fcbff403f792454041d226d23	\\x5c2f772090890dca6a695cdb471ce08a2bd4e24cac0d5e0c701218793ad156b78acc461697d3ed7617042794f4b3df18714514341392826be853694cc646948f	\\xddbaa274dc1dedf9b5cc52bb3b5d124082b6861c9ec28b88cca73b2312badd5b2b6d7b37fe97ccf589d3e92e6944e54b8b679a168bb29ef5a48c17db05a016ee76f9dbd1cd8f79224d6126cfa2802fccb43453977c3b3d9cdbb6f992b512265c392e4716cd18852938e25f4f591333a9793839b7c77c55258e8db59022c008b7	14
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	2	\\x2b3aad95da3e0f176851dc6144b30586b3a926082516e1893f98bc01512bf6e93fc37d3d83a20c26cb3e5a9700fe5f1c2e1266a66a24f87266739f7cd9a7fd01	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xc8f3c22e897efa0e3c5a3d0d288a4caf93bec4218f80b15fa737609ebeadfb9ee8c594bf18c8ef1557c520cd39d003b13017a944a6836699db63095567aa6259881eeaff82e20467b11ece43dbf648027d5e32b467ea0d34e21d150a9e5397aaad1915ffdcdb909f30b3b78a48529ba5599845f430c91835b425c67e6ab6373f	\\xe65ca1eab290ea820c2bc9a4ea3fcc5f69e0b228986f4a3ae1abefc14f9165f8fd4ac29ecaf6e6e80381db61a5c3b688a29f63f8020c2f4300c3249bfd43e81d	\\x9e364443e496afdc7420d38d5696643b19e056bf68910b34b5f18f91ff5dcc58cd64d6062d45cfbf2986d246ee4f526dae7156201cb6a24a4a988db8a83263dfee4cdb1a8ee90e20d40591d8a26b1d4e34c6de472c412f3e8eaebc5ff09346f28b5beb159598073d7f46406e2e5ca31f31b84bdf62f95861cbe652a282043e40	15
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	3	\\x44038b0c7fcdf583ad7eb078fadf0baf2a92e762aef9a2c24f85bf198f8406cdd4420cda2591774eec7263909a0701d27073a7291f0a864d615d362a65737506	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x27324aa4c25d4cb48f8889aa7bb004e6d0bb8484d5768eb759c537e55c0ad354caff40ebb716400c7ac1b6acd449b6d8bd70c0ce7d4a6f1f6d4690da6ac0153b0b69e92a6e9841082731b4ab657bd101184d1be386654ee47bf5671f54dc030ecb822a60820a58d68680b881b129d1ce95f26e51d2a5891606d5c7be650a03e9	\\xfecbd6e31e1a034ef97cb018cea873d9ab47aeaa51b2af5826b666fdee1fb4be136fada223a619189c705d2327f1a9edc2c3078847d1e4c77f6b4a6a4ae25662	\\x738e39f427187dc3516c321e4e8d3d876109e4e728db80df466e647ea6ada1bc92cea332775a434500e7f3bae74af520031676f1147a5984b999e816eb3988889901e0e8bd70eba4ac8d3de5d600a7b492330f4a426097070a67d464d70ead4064f1f42318fe98e8d088d60ef8dd10306add3702356f292d05552735cf57129b	16
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	4	\\x946142da5425d28089a817ad345460c65309d44f387860a4758092c9dc9691fa8752881163c751c458b9f4876283f523e3828a78571d7a2d7846d5846dd49c08	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x1c22e45e326aa3b4556a0bf0045cf34189287ceb8e5c6be677ba685d82705f69cefc0b5a9229d4ff76e48d33896de1b64377fd6c78880cafe6b4e772dce447dbaefdc76751c4485874d0aee09421b379a78d8cb694068fc566980661d93475f65d62caf04dca86cbdca959b037290804690733714f7276f8f175ea1eea8db5ee	\\x4d3866075b25d03d83bedfeab8395dedfdcb02dd1d18bfc9c413a35f2d1e2c0fd5e73e7499cee749395dee46f586f3d17350527ffb90c3c7e381af5c044d0c63	\\x6efb77020cfa0e44fa1a75f3c099b81621f5a24b188d2f2279b845b011492195d167033213e3ffdb71a2d5376d0ad65f0e0c718d0aeab2958679a4e171699b5b21b1c3a07c6c05f5274c5fdc1b474719831d00461c625dc21f8809bffd3b584f9894ee4cbebe8076713fb832e223b60db2dcbd81be31fa8b1b486782ac488528	17
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	5	\\xbf9eefd2886f2effcc633a8716e54dfc30709fb97e193f20626222e29f9ed1cc11c49239158dd6979c124591974ad9731a8311b025aa97a5d5edba7dcbc1de04	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xd0d244a93bad5985359ce6867d49588b921cbe662336ae27a4202def64134f7fc446c850708c538e54c8dd8cc66ae75be1128318f1e1b99b154b466ca0442cc125780346409183a50b54d9069d6a3d78e0ae9a9cdc63f11df58a0abf3f43008f2fab909f8c97169cc81d164f6bcd4d70a0c11f98262ef306b9cbc496e054d6d1	\\x7a202906a6690a5561a2ab6e05f857865dcd3c0c9d9eae42b476255fa2dc20f3d757d34e82c7a316ef31c245cedd1be7834e2fc956d500a45c2256d82e52daa1	\\xba508e193aa1383755c971b5cedad79eb5348eab70001a3f9912e677e3ba05a64176df786b2b95abb6a3fcd6c995ec3cbc2245a41ca7c5e1879f74667bc937653606cc385baa21d2d765332b4468eaa8f9db0c2681becc07f346105ed7e1641951b3a781fdf3f5b00bb03b67d38a149a576af56d3b4a0b86751e6bf6784a8480	18
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	6	\\x4b4cd1d9ffc75b98d721a8e7b3b6a805be00f72d22cb76ebadb48240ef073ff444d12e03e285e7170c13d770bb8adef9464f98c2a881d6a2baff55e6494fe40a	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x7440ae047149d5fe991c7514029b8cf25ba4314d7ab068fbb5b18c611ca93e32e321337616812803d3b35f57b2fca2210c60d713dd6b3df796d12caf696b03c400c825d552041b636b07b116ea11fd2e12d6f29be9383b2068fc3bb4051a97ff94cb69183a359b6fe337d212743ddd40594de6d49159f0f915bf317460a47de3	\\x204ea8f6480f2d364a9f9e7f7fa7af91c6440a482ffb631da2dc90254e0b181d85e0aafd41efedc63a1ada2fcf75e0b773b5f828bb65b8961ecca7863ebf8328	\\x26c6f95adbe3f7ecba861c6345b5a624cf622190e56c31676db768ae6eff5ba3e45013e2a11ed9b00ed88a951591514e72970064e06398cd045d2854d9f3ebbbe109c3c2a32123b2012eabfad211cf565b6371c48e00e75d77db93f5d80a8d7c6fc7139f7bc0a9f0106933af31f11e48d7984dfbdcf7dcff8341a943857a2be6	19
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	7	\\xdac1e1b6c536cf8a948ecca5202031cf3f19a24e79757e0bc06c93bda44932c2e60e1ad4c0b2636424e663c2fdde4ec392e47c29c699b883b9e0c70644618604	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x13a84b81c3538f4dbf317c568858542c67c95f4d5281aa34a2da711f0fae7281d49b18188056d24050d94f02fe57e4bd1d1893bab46ec97a42a782a3bcfa46d19753baf382452c9a323ebd1510b915cb7c93e062a30e6469e95334f83479ec740a51f35643063c15f653fdadbd961bf4a8b78756f35bffe4ac7f0745fb4ab3ed	\\xb780d8e360f8e971287cd74ce884860f79967496085ee7c9d0dda4ac5e27ecf221eb40b1fded12bc165be259cd628139c9ad7020a4ddf7fc1d3b627ac4e2757b	\\xd55b5ca9ab38a7a0f7ecf44a23015972d8772d05482420e074378df8f6da1cdfe1e107c48eecc2c8378e3671c67c51e10cc1aeccc88f16bbaada3ff0cfd42bc61d1e7491d1f45cf0614c3669fe6fd18e54c08cde7a66d9d293c6ed2b7f88a3e34ec886bbfb091c02696e5d6af1493ac608e0aaaf138acb29f0a4e089fda58d69	20
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	8	\\xe20cd7c345f2ed53ab0f3008f33f30ff61e79f4415f4aa723fa71e59137f9ba54b52e30769e80a5759750d8b0cf4e3d3e71f2f69104b401a4addd48cfecf7f01	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xe32ccef74ee454495b9d1556e92885ce1d25794a9b292c914cb8938b01bed84fcb2cf376df74fe9ae237c3b60168defb3325fd500cc92e65263aee62f39d621f1c73cf23160addea3a4350b8927fd5528efbbd35088da50d0856e69f7bffcbdf9b6172ae9e4d386064908e75942596d6288c08db4b230c4bf0520e7716d5cd01	\\x843a609ec324c67ba3042366d7f9030e42422aa0eed6088c5b79c172aef2e30fdc3f9b439f493badf2d79dc7f0d514d571e4d2b60c014e6e62aa9249f61c2339	\\xaf520b0e56813e8a6e1345425a58ddddd4b1a0ab1c13ac97a1d0270c77b5691b3743d8d15802018543ea454babcbea421e13542529c7bf21dd1d98779fbb937c3e5970e67283839ff6089d9e9e757c697b815dcdc1cedb8e052f49826e2d718652083fe1ae65aa10449eb91286fabbbeae3143114b8d2bf615396b414b5915b4	21
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	9	\\xf64bd94942635370b2ad559037addd51291925a493eef139b69369943cc026d467e2f0f58c55039f06a949625eb9a667dc3a8376deaee2392a775477004c2506	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x9e1a4956e08f94b9bce5e5952b519ae23bf2cdc094ff2a2bb54e125fc06249d20f3b67aad0f343feccb83ff7b4bc80962bd5010b815d3a55e91b8020a81fd963bf38c1a2d490f2e1d27c696825b36cac549dd4d9dfe7d93843db36677d0ae2f878f5e7672ec5030389d2684bca175ec046bd7c79dcd090174ca26a01fbc4c8aa	\\xb61c5bf4c2edca320d153ac6fe7837aa0d5051697b96300a68e29cfa1096b098351a533c8b25e89e6f18e62f3b30b011a4deff5b32a1f6117a72ab3ffc217e16	\\x7f349f2afdf560f64ca58b892f83afda2966d84c1dca265f8fe6f7db7a92acc9ce6dc1d4e12a849e53b2e78ae91f23d4d18d9b139c41acc13f308c31fd8b052119fbd23ec998e03e5d3cb1e230919e0f357a4496e2ad7cd9d5f9b11337060c8c88cd86889f26073e733ae7cb9a84b8007f8ec0b1633aca71056350b543f0d8b4	22
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	10	\\xfa3c34a22b953eceb1fca589305207cfeaca1e9af2d72cc698318d43f225e82045247d61c6eae47d39059c765f87be545720efee2fb7848ca4dfff0e05e3130d	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x103b0a24093cc4583c637f3f3b88350c180b1674129ad227a1e3e7593c6d90d47ebe0253000056025e203e2191abae8147beb1595acca6723763987a11361b0e36a2b53c3b4124e5f98195cef48591e9e4b560fee344bd34bac564b3760a3f4b181ed7e2e0cb29ac3ddc1ec236db24770710aec726f6971a17ce049c06aae8dc	\\x94777a6e654144e261eb9fdf4628220e27e18b0453aacb00b4386d1f914c6f5a0af929657318570bbc55611665a8c53c15f87f398ee4fab4fb4db3e3749c63da	\\x48f0956669ff344d68757753ed8f0b505e7ffb28ed661c66304b2bf6add0ce9ad75e3b9742f437319d8e02c02be5895f8b81a315300e6cd3a457da6d3f8aed1d7f8e9c9b85477bb5765cc19219bc6b1424cd8cdc944305771a3a41d75d0842f41bb72944b9d89e824ae78e1454dcbb0deeed19e453e733ff3525ab53a6646b06	23
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	11	\\x1e3ee53923c2f002bfdb48233a8949efa6e795616107783e579ded86c8f17595a02fb760ea931984cde895814c55a8bb4eacf65cbf2afcd2462f833bd9456a0a	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x4ec0fe59e754e80ba9fd869d18ed42d9f5eea5f67cca8196e37251788434255468bda2ebf5f9a39ad0bc0455d1d19fb34d112cbd9b10b2ebe1297272c6a6ec71d51a2056408ba0a665c3d1943b72d95131184b0a78aff1de53f4720690c47d4862ccfa61e99f4caf3601e7d6736c25ae4b474bb6965643b3b534095b0c23b39e	\\x7c76ccd7064b6b876e821b503227f683f8146c51eefad09501710527f271abe332d7380567c6f1854e3d5d7aaddd5c14dcc1b9ee3ffa981794e083ef111bd7ca	\\x089fba2998579c5db19bd205d2f4e8fd6294fc92ada94878db8a334890e4b2bb40246ae1313c3458bcf6bbf748904758948b60fb9ffb6f43be8eabf0b6ef40d51489dbb593c7ad6255eeddffe05c9bbf9900748677c4c41c8fdd4db8b97ff366285cd15601f05f1b4d10712a4c9d3fb2b1fdb7fad942abee1011a4ed44f23133	24
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	0	\\x2d7f9f54bc183fadea8bcd80dd303fd908353292f29e79c6359e2f8205e1bb7f73425893441c7d4a3f45b288fad54011b26fc50131f07e70bb93379537df1205	\\x7df6903220fa0572987de31c75baac7ce63382a7d673c9146e85c94250fd7d0274e1d8c37f221774d5e525248d9ca5b7cc5558a1923985c87053713667cced5d	\\x9a60f2ab2f5c3b94f4d42f78aede419ad083658be9c1853b610b713214f32acd483be574640b7208aed5046980b2678bc84060763d2b1b3a73e8816fcb3360f4712a67952e77138bc76e714a604ae1b07ab63301cc440c52f4c4b16c045f033670710cac5f6e8fb658d0fd1e4f428b4be32143364901d8649d99c039409ff2cf	\\x02c5551d466d33b0f17fff511dec78cf0120779a7ae349241d739ed79e903972af3b3caddb905b3bada982113bbc77ace8cb95616cf7524f470703335eebbb2a	\\x4fb7c1f69eb1a20c0b32fdc2042c77009e957427cb9630ad7db62b51d92346f1b9d444b80783c855c0d22cec07e11cae84045652c63316f41a78b7c0fb744b2427e89837ef0798c11cadae8bf9adc8efe92d6ad1a3f3dd1856a015a7fe4dc754483ececfe84f0b517176d2a5625d35cf719f15da5c015ed84faad40263dde562	25
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	1	\\x16d40cf1bb294623d5de619a86f2e2b6fceb63c77744b58c08f0b1b8a7b7a23d1fb640c5b35e54e5326d583df56962f20a4cccfd6d36287fad9097d735533a0d	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x70bc49d568077dfa5c7874300352b453131bf74a61a2f0ef4c10b25d7863fad2dd88a0e8aa8dbe3f96e0c2f39caed06cd520a7590f53dd6fe58fc1e005f0f8b70e178be1722bb5425b12ddbd19218f6ebb1f191036d3ff082128d461faef2f9dabcf2cc79ba3344978b1d1fc45e82cc58f6aa125c9d7adae5a2ad102c045ba18	\\xaacebd0c0a140d29954771e36581152998cd41349bf4f0b0f48ef93ac5bbed7fb66da8305c07cd602964af0918caf1de2ca9e96451fc733e99e4c2c4230d38aa	\\x9ed85cbe2f3d1bfc37c298f02560cdf2e6c2504d63c0dba398797a12729fd3385c5202c92657573b56680d2bdbb57383a9a2815b4939481bf937cf3a5feb29e5cebd5362dbffa2ec16cab6ed8fb934e735a67d43a81f61b73e18a50faeb0d7e84fcfd14caccaaccca83b81e1a33aed0400629fa49730c85f424770c31f3425ff	26
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	2	\\x8f8bb62727d073d4a560e651998f99f39f8dfe58da8968eb5d83c9ceda8ed4f2e07478a1cd66bda6038f5014455591e2465dbdcaf6217057f935961306582c0b	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x226521969e2f40bc36c38f1c17e9934f796586beb3c69a55d926935237b4416a897083e054cd235f1013894f9d8a4c8c58328230c605f7b3d222c32b74602e32a44ea9d58eb14fe9965b6b3ee1693c21cbf39eeeadcb2ffa536b242cc57ffad943f3fe74ee7e9b0df87b2eefb2738b1ab10130c46d50f0ddccbf349a45a20618	\\x40d9dbacbfd972835c8d7de32932046fc583c05e21013facccc641c3242c6e2c8885e09ccccd915880189b5f7b18c0ea7e68e50afd1e104ce9926821a1b0ed36	\\xab54f4af31b4accde58ed9f9d303a7b58b0553994a6b951ad8615b31b5d697b7b9b3ba1e263310729bd926bc77556f672b6c9731dbe345bfe888b9f41980968b11b562409a8881de22e3be05643599557c12efaed946debf8f75730403df88b09d16b2cf4cce41783258a719ab350d87c5403203d2ab69f1b2be9f766d5ec944	27
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	3	\\x0eabec97f5ff59784406eb3091deceb541c3ccf54908d999acfb2a2fd3f8f8cc8d12eaab177404793a25af36e1dfa7d34e1d8b91adc40f2f6b428e3dd1866d01	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x185df6dee595af459c1755ac8e3891c4bad9180d70a3c1851ef58a5dc690c33500ae042f3c70fe3cd0b6098dc9d6d20f88e5ac45aba129cbe56d78ea8d4f2c03ce58207d82884bf3d9c8e6e8e2086c584c323a05c663baec362f6fe4842cbba0c0fc5accbdbe8ba52697a3d195bb1f6b452a5f21a649a0db50cd3142ef08518c	\\xd41d17276b2214d2e7bfbffd229eef20c40a50f72b01ef053570a5594e0d6112e367a0d96859a3c3248471af4b94e4d743235919f728afc28f2b4f526b7cc938	\\x6a171dc54157f41e859e21a5d5f719ce39ca64666f951b41a6f30a668d4de1585fb374afe48a8b43a73037bb8423880eb9d7dc9251cd7ea81c26df3b23b9ae3554aefa2ca4f82217bf1d218245013797011e765e4d09bb4e23c70c5079a537c8eed513a954c7fbe445870c6830193b45853c7a415723bf2f2970b193fb787ee1	28
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	4	\\xb24694a162257ec4a09546faadd4a5ff67ac4699f468bc084f0db4237b47d242bb34d71dd1266a62a1cc4caafadfa68aa29e096e953caaa559a4879f843fb105	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xabe6ed1f077642b6db3ac18782ce3a1f56f8e71e422769ca2f4d097488a39c394d61d5e122a9b567cb2d20e8049a627c31bd48f5dcad60bf6a2988f50f452f4fa342584366b245fe0f9c5b65dcc8c0930c7454a8d8ccdc6815462ec6d6c6827004971219c0f73339edcacd63088b0d8944b085ec2326fa3698593cf71042e042	\\x8919158e07a8cafb4f58af2301d8dbd232523fc359f36abed88ab58e6b77735f2fb94cb64f7b738957678bd9872830d2a13910cbebd657fe6659c46cc44dc861	\\x69264cb23ce14bf70c31b6a31152a315b4a520b1fdc3163556649a13843d5407c9509724c916813d4388cb4aee76f4fbf238327be3cd960d446f4a7f66b48e52c3b584bd436a26d2ec1eb9769d951c94d323ced7ad043a102135af40b34aeadbc5d6c10851481fcc38ad3c623fcdd5b05cd400501b18fd65b5867cdd2e47be69	29
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	5	\\xacce1c3d83f3b2ad21f3a19911dae8f15343971f8008da5b7eac40b208d78747583e65e136009a2e5c93a7591e4af5e6f9936ca4375cd6e78f3bd154d2858101	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x0ac5dcd7c69dc0ab04e3de82c91249edff87c87eabcb26fb06d5e2525ac30eb7c97cc2d6f3956ff82892c1c504ac17472949085c868ffddccabd89cbac6289de699544405253d5b7856c41f748f32a91beaea9f20338a83864eb8e4e2aa0de150e7dca5e3c108ff51abb3191fc9db7000cc56488fe4475a0be348e0f299e4090	\\xe4026ca390e9f9426c59c537e3b6e56f5bd023a563292e7b1a39e50d57515ae2b4b9b3c873c5308ac72fae1e87c75bcffea105fda24e266a5cd4d7bd7d69fbc1	\\x3f1b3ed5816e328c3c768a5d543f338574c256ff4e44f1bd1e680a2cef902785a156b28df7ce56ecc5a2d2bf92b51aa052fe532441c1c1d09c3fc21ca4fb44ac66832fa94e818bbf63b5b9f64318b2c931b0654ed60d7b1cadf3e8ca6d3d04f013f93a0bea08c285c9bba21f024d579010a576dbf309acac15a6f2606adcd97b	30
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	6	\\x1c344dc29e8c498a70e7efea3cd875ddd2824c9046ab9fa1c2d57ee043b2061fbf87ee9c37b04798d3fbb44f791a3fac8ddea0f696e57991f9b9a4e7739f9905	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x0d0bf963f898f92270fa0285bdb514379f7c20e4c95f0f56369c9d64a091cc479732057fe17562e39fd822ef23c21aeea10378b28ae1866d1f6a0366c98d826117ada308e0dfd7fabc9f594d0bf2383f47584b402435dfbba945dbdb146d9ae4e2e22af0d8a37c5eb1894128d84ce38b6a547abff5780c76b00957f4927e1a60	\\x06cabec555c93b8a624c142f1fb3fcd2c45a637a620b0da0dbce338150f69bde5eb1fe2d26de2273836afd6feb8bd5c8a4066a53b5cdeb759db054ecac607d4e	\\x1ede182607c1497b0b42d54515e3fbeb3d82d2afef8c882cba51346c2cb204ba9cebbec35cf110214097000b9d3d74c0af36cb0ee3f6876fb0ee344cdc240ff2ca8a270eceb987a77ca3641fca6889a6da9291bad7dcb649e11517c6b511f1bca77ab5d9df74b3cf71e3e968fa2d831ccbc0b025c7c4ebca2568d2281a9a30ab	31
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	7	\\x6acb5b3fff83ac4f6595c98292ce477ab37d70929cf20ec96e0342d3255f5366c5ff4a8517d73ba6f2f68f6130608c547136671bcc0db8957e72c2f5d1a05502	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x41820bc4e66c07c5d8efb28bdbb4b3c419dffac62e29d2f463decceba83312a514825ce33a3115edb4b92a36386a11496429684c120b93b7f5381e2b6352879f5772ee5e4a364a7b41d6155083b7fe4e1d32f068218e927cc0f4f8508ed6c6a7ee0691870e1c70820be93cc0880ce13d48d7441e88a5952212921e401705818a	\\xa7046ca1ac3e690a008e3130a3320e8743171db36bd254d71f21b0a96dcfc6fca611922f8e6954c2ddd9f2a1f419472d08dee9ffc7b68cd28d6f6de9e6aec718	\\x7b1468722102842b9ee6632abfb3234dd81f4ee2740e7c80c82050ecc0a8da1737de09aa42f52ec0615759199d2a2131989b597b145376c55578ecb179004ebb066f1e28c9a155b9b3f984483336aa80c01f80fda7461ed5bd2f1065d93fbaf18b50df07658925f318ef5005a034cdaf1ba70e073895750e93b479ec6f26a53e	32
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	8	\\x00a594ee818a0d089e9fec4eb926b58715ca7cfb83e53b81249ae19a466fe3205d3019153579b86e969d133e256ae7ea2ae31817a3cecea159a0c430dee9110f	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x3b09ee4100fc33f2fa561af5f8a4b35dbad32c1e8169fb74277edbb34a729decec427048c8fed2dd05a9033cea0ab7fa633fc81ef058a7ef7facebbde41fc2b66614f88a32bef3ec8f7136a70d2cbd2a74f2a3fde1c49d2dae4568870fa6bc3db34439ec8f2490f68a3abe3b60f9bdee02394093569c22b4875f49a75e6dae12	\\x964408497f94a84d55ab52d4a7b238ccd09e44e41c6ee1d243d6f9237833a0e698313e72f5ea53b303a0b4fcb55555071e239843684a06b9b09b3858275ccbec	\\x2350155da7fe256a6848226267d6a8008faea9fc0b82be6fa699526db66ddc613da62c1048a34efa7932d1f06bc0411b2b2fdd913661c595f224b4b6378145b51a0832b38cf6a3a5dadaf3a237fd185626d8f659cfaaa8e1e63ad5339df01feb2828ce25c516e16f0a18b6191ccbedbea6c24a69c79977eeb0beb9cb89b886ed	33
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	9	\\xcc49da0190c21db49ee87149c89a2f8efd4b491b432510d0e659494bee0d9520d31c677e47c674223b4dcbff27267d2d32ed9c2a5e2afe983751b740ab272808	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x2493d8cb6c1c97bbc3823620070a91446ed5be461c70b55aff067aa97f3bb0522708f07230eaa30e00461be52530cd2666d6e1276dc6e6c98ecc24ab68ac4a0a9db4d24068a758d031f0b9bc18cce8fa7bff0f41aff52f59abc20c2214c68d51ad34ca949387220783e7d40f2e48c95e6008ad4afe5872074a07eacc291463cb	\\x396f0095d79c4bffe2e70d7be8a92050d1654d6b4195e48ae3c04a224f6682d70c368a0064322026dd508395adaf69f194d936490107b4708c832c7f9c553293	\\x6ac9a434a79455dec9aee18aa264dcf03f120bad0869d4c4302118ddec9b1dd59eee0b2ff92af857d77b5ac2fb6fba74c7dd1c3ba38e89d95ac45ea651c41c2461ac27d147e66017f2307dfab13d04ecf1e3a47657f89cea11fda13d11e9d15734776e5e74c5480740c081a6942f443aea767b489ac025b465c00cb25ded8392	34
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	10	\\xa73bb62ed0a781f9a3cbd4fdd630983ca9a7df0013b4557469915c99fc168e61c730a884adcfdb73260e969d1a1dacaf97d9e9dc0e01298f1dc648fb20b3eb03	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x65509755f557bbc3df93b90cc5e2f719b4449f729e09655a8625a774e925bb0b78d5a6fac494e0b58cc05fd0284effa8a7e372d3b04f95d8bb578c52e43bd979a271d2930cbc12ceb43adac6225af69e2a9a3b67c3a25623f20d87a891a47f8e8abd858869e7eedf363fac51de57f2cd56824097abb1fa5c3e6971e1c4e20c2b	\\xfcebe4b42beb5d7e331cdca26645cee493c7e520fe811b3f352915dc801e72afa8c95d8d20846194bf418cc139b1c1812b2af657564e5016c85c67fd36949d5c	\\x65fc724ed019ecd3cd850039d03f3616ab3a5b77d5b93133751177b0a8d7a6170c63feda9af03cf55c2b8f78d0533f4bb5b8785a2bc7dbbc13119e77d4d62f5008fad188e3f09abb8de927cdf738ddc825b32b20e6a5dd91e99a919ed11bfeec8899f11c9843c5e742e0ca265b14320783cd23a4a944e9ba00d4fdbf190fb538	35
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	11	\\xadf8ed55ec6c154f2a2000bf4f0ddfc70619395837362f629f13d12ddffe7415aec0ff06b52796cd72697c91bb85fbbaf57cc9617bbc274bf03323867373a908	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x7fa5eb273f6f457962d0603d18e7ca86d72c483ef895413413a3554b2179f039ace5e6450709952c80d97eae9b366a6b383178a7f608f674adfc2c8548492f7150a74f40939b18a89f2244606a3f0190eeaa0c98666f14aacc59697df282b49d7eb80731c0e5e3508508c482baa4bbccba6d050d12ae177e0a62ef0479423fb0	\\xb67edd3ae3cbd8874cbb287ec34ef555a0af7c488cbd7950dc87b97babde8ca218b8d58cd1b71bb688a651511326a7d771b44ba6f8773ba8ea8bdbb2d5ff9f01	\\x23e81336c151a9252a1f52c1aa27f8ee29cc3a1238d04f529ef055a70e50c8b00d7887ded0db40b3d0e9c907a413222c24fcede384ce25560e6e8d9e960b5468e99a15b47a10014d6e5cf3acb9e002bb2db862dcd9f5d120115586f300b71afac4819a9c239876566683ff965a42e6baea1fba8da1320982318c2eb4dd3b653a	36
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	0	\\x27949372d15319d10a821db03c70ae5d63de256c58e4a891d3a380cb5d9333ec76e5a7ece689cfe07f3a428366e41c43c384d566d1d9f8057d890c4a5f7bec04	\\xf0fca82ed5e1f475885fbca451b7e6d2432530bd12461168ae397b81d818768ff7c392e11593427066f2f3b6ae605fe44de945eea1c6cb67382b1c013332802e	\\x7d2cd3d946d937f08fd120293e67a7639c398a2c0bf82ab7cc554c089cb615dfb588b08c5775d3d27fd855e88f33e747d8318770723d47fde829fffec55a65f7dda56cd928e1911bb9b18eaddf828e45c3203afad2b6262ba71eaa20747680c10a6ed3cfa0e921931e28fa0e67c639b2a06a7b7158d19890911390f953b8f790	\\x34047708243782723f543fb9ad1040456935f37f0d64c958a6771ccf29a1486156cec6f00c6f2929cee6cdaebc3716ca050c2d5de7843a4dea4db7690d2537ec	\\x3f9d30adc7f7e0fe3df72b2c98aba850ac18da6f21f8ea7d39ae5df9d831e224a4b76a2bb628a86061d27dd22e852da7133dec70380411294940661dcddfbfe76634b5742c6f56881166c946d2dc811dd0c7fea3a4a28362bf1e2aa408247e3860d87983ae3c92fcf1aa6bfa3ae3fdea42891988fcab17218bc15f80ae106a2e	37
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	1	\\xd0a2ddbd7d49355f63e63fb56f6b5f201cebb0027a7ff47980ed1a8a84cadaaa06bf486fda4d91accbd5ccecf43ec43e5fc1b2798767b3a5da2d9b7dd3fa7507	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xca381f5669f8d158a0c87be877b04eb67375b6ce2bb7609d95283901304046d8afb3d4d444bfa7222ac5d155c2dd7dcee49e127425a9b258bf73a4fd6cf8cd3095631f3f1b2e34c186bd1eae42d17214fe3f8e2576fc6b03388a3066e980201818b51849243c236f76e1f4346f5650a6afd9b35cee212d89a100a7524fed5e8f	\\x93baf6f6c9a1f1b44781126ec2d7b5e1e542d951a58b4a2eea9579d969ac2630e201c505ec5acab74e822980b95860d538eccdcf1b7a23f19f559cbd735150ec	\\xe7354ca27ddca7d3eba56935adbc380af969f2fcb13bfcbcd59cadb34f4d1fb3a88de78314db6639552fcb743c82b0bc6f5e60caefad98e893605caf6849c844bf3eb78070fe49c07498f40f43f73c6648714506df94647410de7375281c5581466ac55b74bc3d7dfe8bc51cfdaa5a48f943ba968b0b13abe1b3368533c02045	38
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	2	\\x621348dbf8adda52e7d92962f8d65d0f0ab571d1920fbc34e39e0e90c952a38c43344d00c1ecf13bfe336e6c1d2908206cc5a71201a974e5fed2230854a0000d	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x022040211ff43a578cbc2d00fdf0afe3b4c67298a8dc4f4185c008bc6755bb07e4ecabc3934c7de9a6690118034783cb2847d607b936df34be9641feeeff06a8d7cd1c403392b63139732bb6c2cf81d0c08050a587612af1bba5d2f6967733f7cc52442bc0518fa7d29529bef0f2cffdf9e0b8ab00a47e78490a214785273469	\\x0fb0796ec888bbfb8fd7843c3c6c90aa2646508c38ecf6f58538ff7b019a3a10688d3e266494b719a106e2a8acb7481c224709e0784ae2fcfd8d23b2c459cdf0	\\x24cde69c499c8cb2748ab371402dd3a0dc0e0a1e3ea6cf46bdc9164edb73068dd16a246faf60a5cc0b2ae8774827d85130d412a06016b652939643983e0382a1320cd3af5593c2be948037450ea2b7deaa6a5098afab60c33ee162fba4d8f2813498a776cb000c0c78aa1398519e8720cba456e1aace9dc7dbad0e3ee98becf0	39
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	3	\\x2318617a6d6bb9e596c207a815773d3066deec14600ee7a197681de6a15f8ce6aff2ae114b673a1a2161fd08c550e3ca23d14925fac0dfb6fa3b04c5c2724b08	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x3aa7da6c1aad5200dbe5df8fda44c037ef955e71d3fe9ef7dcc27341f8724096cb023c0704b6aabc13318ef6cb07bc11873424749ee66ad974a8e485913b891b52255d7cc0ce53db65be4afc843adbcb9a16afb3467feef63f03688a72d494701b27e1d80dd56939b50f41a5e4edec4c55f57950742486f360b47382b6a962a5	\\x9a54b1a931f14c21be962fa66b45fe0c52ef99aab3f91a7b8492943f264fdf06fa82c0187b0dac35ee77836c32e4cd336d3c7810a41dbbca3f560bf909430e18	\\x694623d08783518bbab7915a160b8b9bbbaff0d3fccb7fe52ad89ab041e997bfb42be2247f80bb385ff0cfc7698a17f48a1fd2bfb66fc8d1cb68db71230da7e960a41671d0be9dcfb1af08f3f1cdf74f3c85e26fc7fe2fa02215f6c14032a51a8af92a012277f1652a26bb625b110b3c7a51e9404a60255c37a0e1c4ce0de1d7	40
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	4	\\x82efc5c8f3a02c062da71223b5fc331dc61d86b2a058f528bd5629b9a870cbe8e0f30d54cdce201f3afb92576fd872cc275333ee5efd69d8623367a415618b09	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x0eac8bf858d797707adafeed2729ae936c09c0b39b550c5ebf93cc58440dfeead6c403225f833108ea326880754a1358761da3fec940b6f1bf148399962a121f0db854ed1edf6a0f4b58e091df4b93278e7be332504cbf135e94f69b3c35f41d73e5b60ca8033f5e6c91e664001a11f9e6b944fece34f6af5f51b9eba4fde9b2	\\xa9d158d20a00a27469ecfe1a9fbe44b6d77769ebd113c7c16b0139c545d5b704290e4071e37cd3f692ca15a790bba4b01789d393e1e000491d6abf4eda6d1f32	\\xe6a90c746bc11cfaf7fc9204fb985e99e6eb21a2472337f865718762a59867a10f80bc9e1d60d0ebc3a6610921cd59ac07c87aa96da31c05c1a90de1a42f661ee643e861bcf1375b652f77764fca719891ce3db62bef9c11a647697c11654d9a9dde250e07476c0fe5bedfe462f8e125c1ec0946fd3a7db17fd30bd80d141212	41
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	5	\\x406fff5dddcf717b5b730b916d3ffbc93d72e7567a33fa47168c13b59244cd6f8763bd7f52725434b06ca820da3eb4b5283627e043c993bd716edb9e87423b0e	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x6cb0c0daa781a18f6daa88e34c7570a6fab91cc50105b16914482d3b33657a9ad29a5af38c7b0254e9151c70677cfd41292e121e65c26cc825bce212287d63afb1d72b1aedb65bd8925b3503e08b8757fab792b2cff4e584eb34ef6beef194eab2b33a3b625cb3c9e82370b7006a218172891eb5eb074926fc3a9c90996e3aea	\\x9065747fb1c3bdd90c0e72f90f43cc096389a35a4e82fee79c6cf78ee5f9c0f39e2c898a0f3cd4cdc284748abca4e09e0e5993f9f16f66d473a40429a7d28f03	\\x8ab71d0e00a38a1c5a7544b40db4d1f698c230b383c7b4be7b0db61cd8bc9c7dee9061e7f3ac02adf42815a7298e7386db2a12b4c8b37fd0f0a427762b9d61e2cd076bc4a07871402551cc86e0126a1fe10ac572164c2199c69ac1d162560017c57c4a5ad69d3a1f33771d8c631784ec9c691be5ed87c9eed559629305452de7	42
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	6	\\x4307fbaf58024c3cc4cec7c9f1ab21c906a7375e8b85f03ffc320614cc11b05af32079a1ae357b29dc272b9ebdc32aa3a6d91fa163887ef1e4ef2366c37d4308	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x4b18fac6e0403aa8e2c0fbd89decb69f64a4a5685dd0e536d9e21e4a2eb38eb7b68fa362aa44de43c40d5c11fcff63c3deaa40e47d556df2c08d298371a6bb4f01bb99a97e4402618cf5693b7ca1f09654b61ff40935bb5132a7a5c71564b6dfa0a608a2ee544d46a2ee11c77060e14443abafc2a461d58b37b6c726eed7ab1e	\\xb8e75ba3a4c3b039e699a9399723a4c52271881168257151a13a8a2e979ef721422ba8c96aecca3de5865c4f8d5e9130270df97a3f0836480d5efc2721b661cc	\\x095f74b356d93676e6aa6b4a401bda3fd1bf467aa49ee9cadbacc5bbd928eb973fd02b72e423257eec2de3ccc07961ce9005d3d9864460a54dd18893310ee5aff598ad86db66d5549d94d5735c894d346a00f523f90f2356a1ff90d1c73c401b3cb7717bf490a1139683dcea9510b696586397877c90afd8167b9a054f3238f8	43
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	7	\\xe475a75e08d06549b286be1231aef7be558759d17f7bf95f62704c971fc074d3bcca4aa0a98e1a380b174828cf77f9fa426ffa148e4a94669c8cd8d038c0ee00	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x387a03cd30f4e4797fe61071566f87a78baef677ce58b53519060023ec60ec423cce7da724d12f83e8d14d679d20ffcb6986fb66e991383606ae396cb3783082a8428cde8f2a9432ec456c2fb4f1f9e986936de4c2c8ecd2a04ce6e79d85be125130255953a980c7b1b15f06132de778eac77accccbbf8802c890a5211650a0a	\\xa59d26d95cb8ca2c1a19a4c7f68bee49fbdb1429e15b2ec90cf42bdb098ffca24c3a6fe8da0c69fef56c495076bba1b994b121a5c0c5ff60c89b95260a42c2b4	\\x856fa1320b9432ba49cbd3cff9f5c1a2c43d9e929af63a13a3fc399d8a8975c3cbff6721381a80436ba7547c312b9e7b49a6488f0e24f2648df97bf2465f20f2062b5ce312714ab1cb2caa77cece1b86127c238730fae41a7767662b81ccb0647b7188b4069fab640c0fc30cecace074b0818d0aa8a5ae55316e0cbf67464285	44
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	8	\\x527d090118a0a6152e09ffa9a6b07da79431f40ba4d4cfe732e182fb6543f02acf9269bd48454c0c1e94f3170c4134263166e8fa399fe41754c881a4102e2a0a	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x350de2d7f3167812e7e03770c1419e21be53012c5682f879be95d5c87090bc26edc8dd3918aa54a71bd668118a3d23ad3a55d53431aa8f58d601ad839e6599a7ac96967ce77c0f349ef23cc25c93c82b8220713fe6f82dbd4b68d3a1e684c36c6a8e809c729c3832d6c29649f389707b531db349bb51daf6ec7860e5b856adcd	\\xb1cace5f3f529bcfee82551ddc0a598fb935b5b5ada8e7c94506ca486e1f7196159e0df37c4e451fa5ecd9192eaf62610cdafbbb7f5778dcb89221ddaf8c51bc	\\x0ce81b8659dfed77ef6048b6853509bbc376247787d8bfe171d1a45c99c4b463924dfd4bdace9cb8df1b10feda440a1f1b371df8c8a8c3f7bff77948d8943e789b49693ce045a16cc6df773fc0551337d7f2c1c5c3c1eacc57b9fd211adc7c710a1e92507d93b2be48d5c8a8c70d426332153ddc34907789619d1ecc0013872a	45
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	9	\\x7c6485cc2dce8a3b29e275d6b1f14124bd36421c8dde0d3118271a9544e903c146012970578c2bb37e2920a888527a5338c7c0d6cd97742dc13e2cbe460cad03	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x2fc2a35863f709f545900294ca4645966d7f9480701c1cd4eb0fea6795a5094f11c6c11399ee3307d592ec2d2eb0276fa5504733df17be0400cf450eca4bb336e6294be2c2863726a4b2f05fa1162f69551bba4e1c628a4e4dbf15666167963cd195312a9e406dd2f543e96d14d3ca38a931bc361cc09edf4834d58a2e3e5da9	\\x775cf2ac2ddb4bbfc71b44b141ad161c68e71853ca82802566997956b7cb41b3d9c89588f0e09f19717e523b1be7382bdf88edfad69c7aacfd540001c0ce2bdc	\\xa1c2cd454437d95dd8bb16895be1d96d8d6cd71e8bbf62794c029aa77e4e833ffb09ef0e4554361eb2706b3ac18aff239a176fad5c9f400f81c4cd5817a86389bae326a13ec23a1d716d6b33ba94d09bac70ff2379f309ab73f99368fc31ec221b2cfd2a5fbad6acfdec41b884ee6d058f7c2a15c58bd4011dd8b976db983a93	46
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	10	\\xba4eb3ba77fd9d4c59a1c858b9d15f17ff8e12bb11383bd86fc6a40ffe2ca1fc008a23f3b27f6be79f6e398609c8de1dce92b41514864fe3ef990916ecc55d0b	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x4e096f4c7cd0484ba3bf07dfd134055677b5d2b2fac613ec11863a58c742f988e8cef046353f261aecd1e12344850b2d4f1ddadd7cec8a13c4ef41f6fab4a24c42199af0ee26f413a572a06d7788cfbf0e897b8d2ecccfeadbeaf970cb551f5b4602a264aab41c67bd6164823e3e1c0246e0f429474fcb46bbbc138040347629	\\x775acb6410740776c774e4e122bbcf81089ad2b4ed336306d682b1adb72a8184d59f4d670723b5fe076c199dc5524079821e246f67902521e431d238d333c591	\\x4844dee51f3c2b834306b007ece71c80dcf7a7e62026858bbf034a61accf10ad61c2fd0eed678edcb84b94f92c4bc0b4978aafc9881d14459bbc2e61349985cc5a7d666a707d71749b2242ed06dc4a8b78e390f6b42cd6edd91290db24b071ac8c65177c361fa48a41161647a92a9a4a79b878296bb8f44ced5ae0d9a56463bd	47
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	11	\\x710cd0bc39062b161b01e618f3a0849dfc58272495129d9f1be56e68c2ee69cec4de1170c7f869e332fbeb966e3123bc1bc3ccd494e9193b7b22e8bd0e471508	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x9693fe0b2d8f5429e0eb30f554e694068aa7a5c5171b2bfaec24c4048eac8c43624b49f35d5138ff8c61d53397dbcccbb1fefec5d2b12f98d3a9bf7ac62a81521dfbe17bb9afd9e89285fb767ec63ab9890a680cff060da72427b00b1c100c702d14c4fec6ee047474c31d4543f709d1d8136316001c7c0c71c91dc7035f7f73	\\xaad9e4fbffae3281c7a7c9c6a05b6a9c343478a4a33f56cf533a1fd901df16aaf1f77ef129ffcb176aed397288c63fcb4b4545fdb6f1cf702674fa02f2b29f00	\\x1c4e68bec5fabbaeac54ace74ebb3972736da10faca27cd83ca56d106228434ec617f31b7f78b8490ef1c312ecdfd980daf75d95934566d1c624fd906883bd5312b721be5ba42437b887549a5ddf5fbe7b17f22be7eb43b72779348266e157ca39a7b202198c635a962b3334951d4533d27a6b81d6513f61cab024fa9fb86797	48
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs, rtc_serial) FROM stdin;
\\x3c9715ac55ce25cc4d8c901b2f1aef3c6dee1eb1736e0455a15494ed10437815ae482985098c23d0a10644596ce6cb956029d262ab05ce5727029af1f4d923fa	\\x51c6dc27fb93fabc1b571053bb052784f891f64990873093763016e840d81a69	\\x68489a8acc43e7bc236617ecf6d1bbfa3cb182676ade23682ff68f407ebaed26423749c0ff2ea84c828c2463da54bd4f1f746100440337a8c5bd1b0f895759cd	1
\\x6d9d91a2111a2d22ae73ce8f59f41f2784af2ba71b811f08cab1295206e9e454ff239cec2fb601bcfd6c133252fae106d84a1a7028ccf2873726fcac46f87e83	\\x9a9ebec1a646d6fd8f706112acbcca64ba719ec97ff431449d14a9188238ff35	\\x17e9d8bf7b0916854547b3b7f290889b119ff2b80b4440fb0a501b3e6cf6d50500f6d426664898c50e529849b92eb9bf4a4e802b01d3bfacf1a2de159a93651b	2
\\x123f6f5474d668eb3349285fe04a960c81b5da3025d2527a5424a081475f17b777f7e05c6c10e62eab4f413006f24efbc3bdd8d7a2865080f5e0f02feb7853d4	\\xb759b4f58dfbf66848ad2782cba788c68855ae14a6a9fd7b699b61e2eb82bc35	\\x2a035ed0218ada9bf919929c2dc0cd645fbf9f8e52c23c72729834857187d387312978a90408cfb0f806796323e3ae43791f02b3b70d99bd0490eae261d7b7ad	3
\\x68a8feefd21b72657c004c35c8e5cbeb06c3ef7f88de355c5285bca7ebe7a3efaa2af557d821a9ff882bb19af4293b9255ce86bd94e65a6f14679ef1a7e19ea4	\\x48bdf75dc6c48d9bdcb27ceca04f7eaa2660418dd83eb455c77c4956de973941	\\x12ee3d4fde3d56e007c73d16492e3ba6ba035870683471f72b667cde055731aa5ac5afd30d965f3934225d5941757d2ad7f9f6a3e4fe1c59becb00eae01f90e1	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x5377ef4d05b6ac07454e5038eafeb1d7beffd5bd89430076fc2158e7fe8ddb90	\\xa5f87ee10b321787cf3d16459d6542054f3392a37d497539937c8d68e642153f	\\x4e640a1159278b76c723c0c8bb4edb48837be8cb28568c86edc25341f81e935a3f501efc2252c8afe0fc6b72b3da6b357a12a9e8483a260f71e1bf1cbd247d0a	\\x4415b09aeb04c3f343f10bd3c379461bcb63dde3f8bc23796f82b2bc21d79267c6d483b12aee82160603401f5d41856acee0faaa62dd3d186c5333288c753ecd	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x480373122a90cdb51a4aaaba293e00df21fd1d3788ba45717e4c04ab875c9ecb	payto://x-taler-bank/localhost/testuser-zuZ1gmDT	0	1000000	1612348482000000	1830681284000000	1
\\x16476e44b6fae5154d3ff697c9f90299d3dbce12aeb567154b94a7141c79186a	payto://x-taler-bank/localhost/testuser-jTni7cbF	0	1000000	1612348486000000	1830681291000000	2
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
1	2	10	0	payto://x-taler-bank/localhost/testuser-zuZ1gmDT	exchange-account-1	1609929282000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-jTni7cbF	exchange-account-1	1609929286000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid) FROM stdin;
1	\\x559c988a0a85be2d4f9d415efd140fe28e4462c1bedae323985b4f92cf4443e2dac1c5dd25028e1c49d03747d535699d4ea798177d1d1f422b63b9cba122a4ed	\\x7e501e8508142deeb0edbe1ef63f770b333596538da65d63255f890076033c7c49ef9b78b8e2b84b538d7edcfbc6c01e160b38e41ee8fdcc96dec75ba83dfbb1	\\x6e919a7a9fd12e456e8cca3522f1a5b8c2e0f3288e9d2d96881c59d0274a2ca97b4cea393ba562a99af35bfecf91efec2baaa087f6d728e25becd21e619b159cca6d04c1e6a7f320739960f548b47d1429bed7fcf5eada7a3ac7594b2aee4facd7dba3e756b09e2dd6122cac20b0b9b8a6f6c0847450552627a8547159eb5cb7	\\xe1b73869a7ed510a36ba0eee630b9790c6d33c2e1e133fcfd4187906f90e27e6e7cf6481dc0259e244128df5adfd4c0e95d407fe157887fce0da4c6760eade0b	1609929283000000	8	5000000	1
2	\\x56d5ad3364a451b56005d59c5bdc935e915d3d3508ee2b502ae5acc43ce597f14c1824af979953102be2b1f078e2fcfbb3c4b3b5c96d715fe920d8d38058ed45	\\xf0fca82ed5e1f475885fbca451b7e6d2432530bd12461168ae397b81d818768ff7c392e11593427066f2f3b6ae605fe44de945eea1c6cb67382b1c013332802e	\\x7206bcfc64654f98a95564ad5ceda5f149b19afd03d772bbd3117f274e548e3201fb0e8a782703b5210072b272d9cfd9da90f63fcaf745a196edc5077af37da7e861618dc09b3973a39fb4c5e7e68451e10d8c9bf92e99842ab5d3a475d988059ae45bf45e96d687dbf08af20a4e4896cf07df9adfec2300a2fb23e2d042ff20	\\xcf1ad8ac36e2b658f8df33f4940cc3a724c8dd524970cfcd02470f440ea2222764c6456a4bcd24e71203bc8d153142bd6a237bccf7a141595a5b2e03bb34d707	1609929284000000	1	2000000	1
3	\\xd43bd8d874aa161059aaa9b34a497543ba4e5272d0a7f4ceb7cc1fa2c8cb4b9787d4d87229c5792c09c12b6796d3fcc0ab9098d2ba3af0f76f9969662be98cf8	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x0cd68f68c1b223a302ee1e8961fa18fa75bf81081b25b7f1b130d59d557fcf4d86aa1dfa0d95b3cc6fadbd156c7e6a07471fea1c4e16ef0be2523252857b1b921bf6b9f573443d68a8063203711fd6bc2bd380704ac8411b51ad3c92b83c3594dcc8830e9125b226126510034ae6de11db670533df0f8c2aec9a586830b58c60	\\xdb94af1bc951bdcc370fe3f4dbe0e65797bb3a60c9696c7d9c12e2b2f5f30a2c3bcc65abe15adb5dc84f0e9f9d24b385f3058fe2952448f78828706982a03e0d	1609929284000000	0	11000000	1
4	\\x6e6a9c4162267a7a59cecf7095a9fd19be453f51d7439452b03352c82a46f7008bed931a185cfb5f5d6d2b5c392ae97cf390f3e5090e32c6e35b69e25a63f0c9	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xd47a70c115dda5a332e5b30b8ffd1f41c81e5aaf98a9374b2af7508050e589b534182ab707f46b97c382008f757d137bf53849700d7cacf23efde819e9933028469228823bb11b4ea35efa58c6b3c0633512de84273b9229e00173e9d52a4d907ba74a5f54d261e460263ad3d16ae597dc584d04d74dcb3ea3699034ae53c953	\\x9aa8f70b8614a67ec7a90abd416e531feb7f4465c0f0ea4de24865a61379b4e6848ff7751fdeb63979a24fb8a10b74711fea1d39135717d5e6c91967e23d1008	1609929284000000	0	11000000	1
5	\\xad99acbec4aed860a835631712e5ec5bef55c3f271474a11c0dc1659b8494b7155c337fce3e965095482e6256dc0d3bd49ca61b60d557a0d1e8ba40d7b2cfef5	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xc08911477315f53bf04fd654394e3b336cb7fb5932cf6dfef9e35bacfa33392a55749e9732f0bf4e954b4843a411505ca0d2373ec28f23b85c60e46e7786f0b979ba19ee3b346af31bda9602048165f67af87f9237d0b9a88c2b0b14c521a6d954436aae242f194879d5dd17988487b065bd838d69cac603e57585ce4daec840	\\x14e44e9fa761ecc8f5bb6d3019f0d244209b622d5729403253d1f3620e963875a23a90ad36dc8af2a5ffc0b57cd6332120e428cee5ab9999110dc0c579307105	1609929284000000	0	11000000	1
6	\\xc3e3ecf14e04f0ae705f53907c894fa63abc4ba9092b5b32fd944d2830f52288daa3f3e5256ca93a714151637def52e6735623c87c1c23652e07608961f98105	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x825c77ad0e06c8a7318d2b39681901842a760e9f6ca4f568bd3b394bac5bc329fb16491aa9731b708882495f7869469190c5f4bb9df2dc4b0ac410369b9706e032e841831b612a10933a56f917c481bac905c62aa5218c7202a59a91301aa7477409d7a8a01b490086ec4fe7adc59906a975b16c6a699f0ead9deff3ad7eab08	\\x4e0f02302325bbc0f827a7dbacd0b53e4f13bf1a7c2a48934b6f73f5edc98f9fe051b48ed96df01fbf5930ec07d145765188699cb030953a1750842f331d4d05	1609929284000000	0	11000000	1
7	\\xe36125690635c21e3e20ae8cb59dd0f50470bb1866f8b138248f62fa2e214a7ed25d644e3c745ea12aaf13c4cb6d5292f888b70b566633270a6aa97af8df918a	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x75fa018ddb7ecc084908bf138180efd42f28c9d5788faa68e371c0097a1fc316c991e80618fd3b0f8cd4edec4c601ffcbcffb40ba149822060f469c6d5111abb9e2058b9e1a5180a78d4a843029f664ad43a333ec221d07f511d43a29dd7d21449b72dcdfc558c561fdff66069597fced217736ade1629dc76f58685fa1d98db	\\x6b06f1a8b7d773975133e0b7d95f0bc01fe15c2310b06f21df0541ddaf855c4d005db06248eecab913f6185678e72cd636d960981a7330dfdc946e9eb75f2f01	1609929284000000	0	11000000	1
8	\\x480baed6b1e5ac95ad859b97777f40108a7d64ceb9e42f8f84346c0dbe77aa6c7b8b7766a0c21ddc70371ed053c3520058b06906a5726df574e21f5344d3753c	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xe6475042db838d1b0cb7004254ae190c428f0255bb74469d414a37220304d9d8a7c1c16d9cd02d3d9aec95100b9f115b6b4a66b172c7bb08fe7c8c10c883fd29bbffb778b35769524950956bfe54334aefaaf14be6f58142cfa935086bc7cafc8c398fd1f1d464ea538f829f14145dc43bfafb73bc924788b6c30b648355cfb0	\\xdc568824f31dd77e4a699d7f3e76bac86f2b19a30c3830bac96fd85292e6286455cf547617c22297d3389c5075a62bfe2cdcc38d08239a118ccc0745a35dd906	1609929284000000	0	11000000	1
9	\\xab6114d7c33627dd53a94b252743f35fbb3c2ab89c0f6632210b3318d4bc4d2a47a516febae87063a6938ced4610a33c6fcf6e3dc08a557668270027bae0d9e9	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x4b77ee82ea53b12fe0868e8f75464073b929178ae2ffe163ab8058d3aad3493992247d14d97fd084e89251d2cd6d9c8765cf2cac2fd113fc6ad1763cf685a474aaecee94e5e545611e757442037eed362f2ed0185440caf2ab00a2959d31b2a67f6dd7bd8601cc700af401fc1e43cd7c364311245ee7e090311f3d2d120cd2ba	\\xc204666800381053e86897d6d98b46f6a1b17cb84f7c0aca4a68daac34ff7d7b78fd5fd988dd465043962fb2aef3d43b2ea7c39ac4316719d41cd874e971f204	1609929284000000	0	11000000	1
10	\\xac5d572c139bb5f06225b56d823634060c88a755d17d410ed064651c62f9e69264d7fb63d7db2f2644f405b03d849cd356ac33ab144bc7053e4833de27c988ee	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xc218586e480fc614bd0b3fbf9632f10bf26542d36b5782167ec6e433de57e6424afebc2e8755ac4474f7d1b63cbd84cd4083af7dfa21a996fbe30130a8c118af4ec8e4a272c6ce3fbc1029cc318fbd8c60c6362d1bb0a68de2542a21e02c3a050796ff2e6df91d8591d12a53c117d07deede0ed64e8e780c3656b8aa9fc980ee	\\x97634189600e10ffc0e4bdadc79101e7b338240cbac77ef66470fbe1898ebb28340cb02f8f56822743dc5e0353b729cfda1f084694b35fd481dc17762f855403	1609929284000000	0	11000000	1
11	\\x5c10c5a66e91f51e9a04d9c6f99908522073307f3f5d4aa5e7540222b29a73f8164de52699dbec098f4a0d56ce85c3bfe96217f3ded8753df760c3ba749f796e	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x82846072b9748565719348438a41d916e6c52e8654cc48ab190d9d3bca2c362db1ab65df341cdf40311668c7b01818b372d3fde9984d4388676514ae3f086bb9e42a55a2fa9b179e20cbbb0876efe999cf1d6cce23264ff9f1ce19b4592521590fe62ee8da519a4884deeffdf35728974f79ff2dc74a6ea007f9976aac265e03	\\x265ad12c00554a91fcd3dd7d95427d388a4e5fb6196c4c77a7f427e9ff8740535e3bb67446983f21e5107d88a19362dc9a070f385a3320eb74b1f2ec4a71db0c	1609929284000000	0	2000000	1
12	\\x30d323cb65e8470cbd25a5795abe41294ac402a540408933e6084263724e64866fb7534d99577281d36c963fee68fa281e38980b8ad16a93b9c5f4ecce2fbd20	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x2474dbfb728b912a2339798815a8b6a8bd1925cfd8d111551efa28ec8c6a9d45c909931da2dc29ae625cec6cd307439470e773ab2747b852fa55c7d5416db357f048e36a77ad94dd4cc4f89e48be0b9d283ca1a29928868706037fe586513249f83807e01ba557274f41e7235d3ae1092f7790902d422d1867affb4e26ac95cf	\\x90e5505ca2e201a08d71d06531677fad1546dccdce4aad725aed80991d21dfd3fe4d773414e692cae91688380b2111cf93aa0e7674e4475603858e3cdaafca04	1609929284000000	0	2000000	1
13	\\xe8258c1cb3e38b9ca199e78686f0c3fc8ada0a948eb80fca025f4712fbe5d21464de1338f02aced5a83c15800ff077c1e63a3796f11e78827928752538a4be41	\\x581f4b9ff7a2dd6d89e26ae1d367ff34ee60c224b5c83105a8a9cb541b5f7bb27e2f306b3f2adfcefcc9f7d9fa2d39aba80d3db2a2d1da78eabf937e907ec4c7	\\x2ef50c9398bbdae6b245234326b1aa8ea52f5f33baa0c74dde1f3f6f3944445a4a4050ddc43ac2db981a418388324bf854c3fb710a095b9c89579d22d51168c71018df5fb11e8e911337dd711a26a600e62f052c31f9e93d3b76a22b63aeec4d987c94a21b76845111f3b08b6936e4607dbad4088e104564116e2843237d4257	\\x868cfbe473aaf814da050d7cedd6f42f5f59e885f3cd846fc4e74bf9245fcc08635e88185e92139e57df509b1bd4f9904f493b1165c9fa7f361a80ff87cbfd0c	1609929291000000	10	1000000	2
14	\\x87c0a2a105700b936494897a3ac3a7db8da5ca7c50224a80821f196ea03a00342bee6acd0374260d6785fac0ffe8281f434f3fcab4c67e625f1a556e63208b43	\\x7df6903220fa0572987de31c75baac7ce63382a7d673c9146e85c94250fd7d0274e1d8c37f221774d5e525248d9ca5b7cc5558a1923985c87053713667cced5d	\\xcbe146ffcc328ac620403a67eadf556521fe18d3fef634eb801ce4f44bc4dfdfbee85390e3e00b088163b11a1d5a76442a7d71e2926cc9ee374e277f1c3187549fba27ee1ef461b98ee0ff32b35478997a53a049bb82b6422c1e576cc9c870f11efdc594af80a9d638ff2e3abff27853719c6aef6598a85c73d2072e942e1944	\\xab1cf822bf217ff72da3fa619267f99534136726d350d90f417432062d8834d761b308506b8232a483b5b6691969d9267f787d664c3bfa8d8040fff703605b03	1609929291000000	5	1000000	2
15	\\x3d186cad020b5e0d269c486658bf9293beb734bcf2367951d4ca8a493b087449d2715fbe8ba9460be5171bc740ee38777b7266cfdcd7d7dd46107540c9b488a7	\\x307eaf197e8d962c6fe82c5326322d3fd832e126cbd6d55a7f1386676c441602a88b51323e4b17ecedefd05d22f6961c7df36a44839ea5a7bc1d03b18f7c3fe2	\\x3cfdfb39ebb407774bc30c92ad349c970881eb8fae1f164c578ac0074d4c4c1dcd2a4dbaa1190d038ef2725f22a6353fe4cb2fb50e8cc9b777b06ef49fe99ee55bbb6979367503f2ba492263c5b22da43c68611ac3e03eefd779251d88658f2513f32cc8d39b8e8b78e25ba5051e36fa9660a840ec697fc8a496a2d2fd1b3976	\\x66e2600ccac09fed34197e6fa30575426777cbce7c13f0c2757f8a2b7a10fe3a7c1c8c8bdb56d398dfc8db8046f7ce74de94c5f644414e784412d4ba660a3a03	1609929291000000	2	3000000	2
16	\\x504f8b41fa4e6078f2ae21ee01eb48a52e2ab3e93101c002cf17f1d2a3ab27131b73180150a226e44f26b03d16800b56708e00a5a9a5444a1c09518fd2727d00	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x88041d940bf4120e521a30ce826b1c0bb4f27f0e9af82dd0a3b974923a7ae622633b955950b2a2e491befd43a584fd62655e933772847c33d68f2602573d03e9a7ec689e63affd2e8e20ace2137fff8d1fed4df995c6f7b9954bd7807eb9210eeb7c893d96a5185551c4d21b932d7ff3bb17f83ccaf06bdc671f1e83c0ae7715	\\xce3fef0b18ec38aef145aaa43d060b5d61a20578dcaec2420c7f39295e7652cd84f134ee996c5b296774d61efc5fe71645ab395be400b92261f79bac38abad0a	1609929291000000	0	11000000	2
17	\\xea39e5357b1fe9b5410e50f385a94280c6da5ffdf27e21b1cc937395df095ebc01cd831f04b797d20b419e789733242e3ccaf646da72c08636a02e5fdaf9b384	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x7bea0cad26df1da7da2335acb53694fb3174205dfefd3962630fb286334ccaf0cea44492f4ee38be9a53bafd2752f07c5d9fdc1113da37f42affdf7b8ca34c2b741c61f3e219ea1ffe24a4acf927692b3b3f0c1d2a6adccfcb18a7ecc4911c2e9a3fc9dc9cf73b84bad10e9ee98729d37b113b1cf4f4780d3525eb1196527e3d	\\xa8c38dd388184666336d4719739d849069d3c50e3dec2a4c4efebc883ecace0a9f7db8062edd3987308ef8015a450e29df4aa1c4344fb53fa736215cf2821f0d	1609929291000000	0	11000000	2
18	\\x31a08b3c7cd3da49dc059847adff46e75196dba3b5982c3f314f26d1c5e679d8ed33077113a6553339352a3d6419fce8f0eb293ad49f65f3253eb34315780daf	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x6390d6742ae6dedc798a41389a3f8fc2c0c356d96f619e95685103e1820cbea6c205d4392e5e0251b1a4e0bc51f10b4136577989cb1ab6f0fe01808c55826c99d61374a22d02a3f89ba88180bec517138d642fcc21978dd2d6fecf091bf8e192a24edbcc4b44f24edcb31d2e323bafb8b7d55eafc32b68ebb8156a88feb331e3	\\xd2e87a80f92d44f4c2a03b8ec24299844e080753aefea9392c815eb664c949fcd4df31453fcb42cc00a98c5eb82bf1fd04bfb1d3e75b8bb0006e4a2f24e9c601	1609929291000000	0	11000000	2
19	\\x8a18ebd2e5b514ccc75d2ac8bf082f5787a99e010e82b92ceb92294a614b47c1e732c0469ea1dd980fae68ff20fe0af259273d5d0c20b51f6d94efa12b568e84	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x6079a4a00ca1f03f48c693073ee647070c220458713ae3bc377bf168abb6312e4a0861ddd0cb47b0a3501e735018cd40efd3358273adb58a683b54b89d70d3febe54f90cd99e860b2c374113110c1f6dff3bdccaa1256e97c6a094ad7740d4f836894e4d8a9705dfbd04ce7949624c88be81257211f10fd9f21a01c40399d647	\\xbd88f1b8eddc89524aa91469ffb300b03c9cfd29598c7da0a6f1f4ec4ad45251c91bfd40741086450b6f76716652c3c8a6817168c48c745f33f094c267d14f0b	1609929291000000	0	11000000	2
20	\\x28cc0c36c3b0a30e634c97360d2fd79d2ffb01f314d9c79f3ec285b5deb3752c93b7e73e358cd62ac9462d4042a78343e4dc1b642cbed6f836c6161ce2f14507	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x45eabbd621c13dd6d26546992ce3951dff80fd2de5347701714c0beaad9d083c1eaa48e97232f63631071d8a964b606936919ddf4e6f7cbcc12db8094d2a2767ad81e44b59ff7a5e0d87e301d93c35105f9eac0914eb07b7b96c99507606039736f1968394dd498ffe206fa511f7f31a554eeeceba539b168cf53e6ab1348f4e	\\x72350377e035282b0d448b9b912703a9a02fe3b1764305ef0dbea8a014d6c8c03154d120f8348bbacf097164d61043a9fd564300be24b41edbc17d6244f03708	1609929291000000	0	11000000	2
21	\\xe2b57c290c4956ee3251da221ab4ac1233192bf11b1470d4acd112e30e595bdfae8dd56b37c562e148ee6b3cee18fe2d0abde2ed1c8b2f4aebb61d6e84c8fea2	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x899ddb7fbe39673560d8a4d1ede9e0b55f671f3a855fdff95be5ea91d1262b1d7bd1a9169e90bdaa1aae62ff511416b2a5bbdb3489498741e187e64447bb0c5ae382fa29c672145e850040d56d4d9b174387b1d617e7a93539a7410acf4392883b08d22ebfceef259bd32aa065c491039ac45a531a3b9a02f36b7bd63c17296d	\\xba0913b840bca4d8c7d8dcf20d1ded5fc15a1adecd5d06cefa80e7ca45ee8b36afaa811408a1e6f85af63a90c7f2ee8ff227a1de8de6abeacb5ae9bf12591705	1609929291000000	0	11000000	2
22	\\x4164faf2abb339a5cb400054624becb2f59d456d5f01d3ecc1d42d1575ef496ea9d0a2aaf1877a5cc9d68c31477c411986fe8264c645fc99780bc93acf5b5911	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\x4bff46d6322f33968a1e9cb4bf794a950363808e2fda206a7c07304c2945bb72445db6d76c0cadf5373b2d3c5c5d358df61c326c3aba4e355fd5492c8b3f64a604ea0c25a9bf6e429351f3cc073ec2144492641f2cad00a6c265bad4a967983007ce3a4867ce6aeb3ac879c0f4051cea54184b633e8ee3ed6c5a67ac699855d4	\\x44ae8eb5bcdcbdb6fbdc59923eef3acdf67e3b56522f2798e06dcf3528e29324b3e80e28518340442320aefe6c21d4db568f3c02ab38f9c2875d58184c892c07	1609929291000000	0	11000000	2
23	\\xd740217beb508d008c653ce5ff8bfbcfe9ce1ed328d960bddfde8fc76399a37f72673809c24ab40bc89b63070dcd0a429f2d64e9f482d76d31eed74c226df434	\\x3bbaa3e30746ac0cc20896997d5f62def8d2f30a1af3bc6c6b95d2d53581b27de9aab9003f60617197f4e86959bd51d01b5ca14cc5e4aa21e0bf4337cd591005	\\xb9c0b6a8f15d8f1bdceec1f56ba85e43feeba0193ad9e433dcefa136bfee8867893577b5287be58be0fbdfbc62e951a6d7ccc6665e577b6e14b4b0fd2dcacfe8564f353aa87c8cd2db6f75567fd681bc32ad2d6fe88116e1576810d57c1911ff04dc5012f7f1a0dc5ca8b3bcc53e543fc7a1eab83a4f667cabf22f0fe3deaf0f	\\x7b3e037829c24d272003ac575bce26d91e0a992d22af49028c02778557ba38bb221c03cc7ba25cd387442e931b0c91b675e966887967580033b2c67bb38e5f0b	1609929291000000	0	11000000	2
24	\\x5147624d940945ac97b9e7c67bc321fad12a05e66bb594794006945492a4bf1fb9ff15400bd3b8c6cf279a350c2615e0a1942da69fc61c71d3eabed86d7343fb	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x375bc182c5b12068b70376bb51d10357a138ff7cb9d7e515356bdd1f1e214991c282cb3da606e284adf1e8d7b277d22f52ad158b6b896a59eeb873b1e816a869198a0218808ee006399d7b5589f419dbd64d6d7f933518dafbfe6b7a051f18c51dd3798d28bbffe4ff49fa3615a0ef0b880e961c54bc788bb9bf597cbc6a3c0f	\\xa731c1c99ce75fbb69c077740f6fc1c27ec1eade0e0a377880ef1c11faaa2800b5f58f3a43266372715a449623c888104be241dc4abcfd9918e518aab94ee606	1609929291000000	0	2000000	2
25	\\x38e27c9b37e12208d586efa33165ef7f176ebb6b71435f1756335a9acaea4f7413c77f545a60d0311ebb987e094137df2abbc6e5fa9b15734feacbb812aafc0b	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x391277815fdd7c73cd4ceedc99a40e4d0f837a2b497a763ef95ef185b038d0d70a701161867dcff20063b5ef6377b1f8147f8d456d085357ca9cd14a8aabd9f566f96f70a42d93d562f8bae7fbb3db7b4845c0d836c4e8b1d2fa3f04f3fa0b8a01606c58995d3f236189dccb84428560c4944abaec159b19587874f1edf1f743	\\xa0f10b627f43f9216d90531b11b4761e1fcc3af6686ca1823582027b511edcff91b1b28f2d7d8d52ed235fe182b17d274a1018f9704081c94dc07d72117ef102	1609929291000000	0	2000000	2
26	\\x8aa89dadf21d268057ee16aa3b2fc8b5d8546db284e4e3502bda2fc088c98a8a10988c40428830cae27ca180261b1978ee385fce7cfb1ed6dfdf886d645dd4f6	\\x8cd7268f899355fabc2bd26a9fa3f0219207f700164231245f3d48b16b81c99895299655b0b543a82e6c71bb5d0bc03490f28cd43d7c213b1b94805eda789113	\\x2add13c32d77270cf54fecd3d77d7519cedfae8f0b1e65e9805bc2f609324e345d430346706fcef28b8a0b37d4031ab95fe92703b6d4a51023744cbc279e4776a36c1488b7e6486b75df91bda0da687a61c0abf2a798860f275d9686d23f46cc0c0642adccc3ed99fd48e7267ef53ac2d831a552b3e4acccaf287d524f97b93d	\\x9e8a94801e18b637f7e0e4e1d89dcf869483cb275065fa45bcdec96378a5fce166f52e3cb190563ab10852a799564365db7064ec3bc7c052dce06445e673e002	1609929291000000	0	2000000	2
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
payto://x-taler-bank/localhost/Exchange	\\x42f4b89030c34c004e02219d4282b9b958a217a990acb9098991404bf1df51a64533f70b23fc90e869bd4e38493b91185d9ccc5dec331431e6c0c3eee52ac00d	t	1609929266000000
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
x-taler-bank	1609455600000000	1640991600000000	0	1000000	0	1000000	\\xef4cbb880a50e98016a07b6e8014de7597aa9024a00e99f7c587b98cbf624573d41f411106b1f3647d04a01c022a9e22de7f75c2bb6b6168de47aa5211101707	1
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
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


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

