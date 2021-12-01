--
-- PostgreSQL database dump
--

-- Dumped from database version 13.4
-- Dumped by pg_dump version 13.4

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
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';


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
    id bigint NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    master_pub bytea NOT NULL,
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
    id bigint NOT NULL,
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
    id bigint NOT NULL,
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
    id bigint NOT NULL,
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
    denominations_serial bigint NOT NULL,
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
    denominations_serial bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_type integer DEFAULT 1 NOT NULL,
    age_restrictions integer DEFAULT 0 NOT NULL,
    denom_pub bytea NOT NULL,
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
-- Name: COLUMN denominations.denom_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denom_type IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';


--
-- Name: COLUMN denominations.age_restrictions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.age_restrictions IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';


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
    master_pub bytea NOT NULL,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_extensions bytea NOT NULL,
    h_wire bytea NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
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
    CONSTRAINT deposit_confirmations_h_contract_terms_check1 CHECK ((length(h_contract_terms) = 64)),
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
    shard bigint NOT NULL,
    known_coin_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire_salt bytea NOT NULL,
    wire_target_serial_id bigint NOT NULL,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16))
);


--
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding. Should be set based on h_payto and merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


--
-- Name: COLUMN deposits.wire_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_salt IS 'Salt used when hashing the payto://-URI to get the h_wire';


--
-- Name: COLUMN deposits.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_target_serial_id IS 'Identifies the target bank account and KYC status';


--
-- Name: COLUMN deposits.tiny; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.tiny IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


--
-- Name: COLUMN deposits.extension_blocked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_blocked IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';


--
-- Name: COLUMN deposits.extension_details_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_details_serial_id IS 'References extensions table, NULL if extensions are not used';


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
    id bigint NOT NULL,
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
-- Name: extension_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extension_details (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.extension_details_extension_details_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.extension_details_extension_details_serial_id_seq OWNED BY public.extension_details.extension_details_serial_id;


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    age_hash bytea,
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_age_hash_check CHECK ((length(age_hash) = 32)),
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


--
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: COLUMN known_coins.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.coin_pub IS 'EdDSA public key of the coin';


--
-- Name: COLUMN known_coins.age_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.age_hash IS 'Optional hash for age restrictions as per DD 24 (active if denom_type has the respective bit set)';


--
-- Name: COLUMN known_coins.denom_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.denom_sig IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';


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
    CONSTRAINT merchant_accounts_salt_check CHECK ((length(salt) = 16))
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
    claim_token bytea NOT NULL,
    CONSTRAINT merchant_contract_terms_claim_token_check CHECK ((length(claim_token) = 16)),
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
-- Name: COLUMN merchant_contract_terms.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.claim_token IS 'Token optionally used to access the status of the order. All zeros (not NULL) if not used';


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
    auth_hash bytea,
    auth_salt bytea,
    CONSTRAINT merchant_instances_auth_hash_check CHECK ((length(auth_hash) = 64)),
    CONSTRAINT merchant_instances_auth_salt_check CHECK ((length(auth_salt) = 32)),
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
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


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
-- Name: merchant_kyc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_kyc (
    kyc_serial_id bigint NOT NULL,
    kyc_timestamp bigint NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    exchange_sig bytea,
    exchange_pub bytea,
    exchange_kyc_serial bigint DEFAULT 0 NOT NULL,
    account_serial bigint NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT merchant_kyc_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT merchant_kyc_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_kyc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_kyc IS 'Status of the KYC process of a merchant account at an exchange';


--
-- Name: COLUMN merchant_kyc.kyc_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_timestamp IS 'Last time we checked our KYC status at the exchange. Useful to re-check if the status is very stale. Also the timestamp used for the exchange signature (if present).';


--
-- Name: COLUMN merchant_kyc.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN merchant_kyc.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_sig IS 'signature of the exchange affirming the KYC passed (or NULL if exchange does not require KYC or not kyc_ok)';


--
-- Name: COLUMN merchant_kyc.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_pub IS 'public key used with exchange_sig (or NULL if exchange_sig is NULL)';


--
-- Name: COLUMN merchant_kyc.exchange_kyc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_kyc_serial IS 'Number to use in the KYC-endpoints of the exchange to check the KYC status or begin the KYC process. 0 if we do not know it yet.';


--
-- Name: COLUMN merchant_kyc.account_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.account_serial IS 'Which bank account of the merchant is the KYC status for';


--
-- Name: COLUMN merchant_kyc.exchange_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_url IS 'Which exchange base URL is this KYC status valid for';


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_kyc_kyc_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_kyc_kyc_serial_id_seq OWNED BY public.merchant_kyc.kyc_serial_id;


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
    payto_uri character varying,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: COLUMN merchant_tip_reserve_keys.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserve_keys.payto_uri IS 'payto:// URI used to fund the reserve, may be NULL once reserve is funded';


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
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
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

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


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
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
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
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed';


--
-- Name: COLUMN recoup.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.known_coin_id IS 'Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';


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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.known_coin_id IS 'Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';


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
    old_known_coin_id bigint NOT NULL,
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
    rrc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
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
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the melt operation.';


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
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


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
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
);


--
-- Name: TABLE refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';


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
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
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
    reserve_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    wire_target_serial_id bigint NOT NULL,
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
-- Name: COLUMN reserves_close.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_close.wire_target_serial_id IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


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
    reserve_uuid bigint NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_serial_id bigint NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


--
-- Name: TABLE reserves_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


--
-- Name: COLUMN reserves_in.wire_source_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.wire_source_serial_id IS 'Identifies the debited bank account and KYC status';


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
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_uuid bigint NOT NULL,
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
-- Name: COLUMN reserves_out.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.denominations_serial IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


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
-- Name: revolving_work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.revolving_work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row integer NOT NULL,
    end_row integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE revolving_work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.revolving_work_shards IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';


--
-- Name: COLUMN revolving_work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN revolving_work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN revolving_work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN revolving_work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN revolving_work_shards.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.active IS 'set to TRUE when a worker is active on the shard';


--
-- Name: COLUMN revolving_work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.revolving_work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.revolving_work_shards_shard_serial_id_seq OWNED BY public.revolving_work_shards.shard_serial_id;


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
    wire_in_off bigint NOT NULL,
    wire_out_off bigint NOT NULL
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
    wire_fee_serial bigint NOT NULL,
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
    wire_target_serial_id bigint NOT NULL,
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
-- Name: COLUMN wire_out.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.wire_target_serial_id IS 'Identifies the credited bank account and KYC status';


--
-- Name: COLUMN wire_out.exchange_account_section; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.exchange_account_section IS 'identifies the configuration section with the debit account of this payment';


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
-- Name: wire_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_targets (
    wire_target_serial_id bigint NOT NULL,
    h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_h_payto_check CHECK ((length(h_payto) = 64))
);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_targets IS 'All recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.h_payto IS 'Unsalted hash of payto_uri';


--
-- Name: COLUMN wire_targets.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.payto_uri IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';


--
-- Name: COLUMN wire_targets.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN wire_targets.external_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.external_id IS 'Name of the user that was used for OAuth 2.0-based legitimization';


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wire_targets_wire_target_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wire_targets_wire_target_serial_id_seq OWNED BY public.wire_targets.wire_target_serial_id;


--
-- Name: work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.work_shards_shard_serial_id_seq OWNED BY public.work_shards.shard_serial_id;


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
-- Name: extension_details extension_details_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details ALTER COLUMN extension_details_serial_id SET DEFAULT nextval('public.extension_details_extension_details_serial_id_seq'::regclass);


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
-- Name: merchant_kyc kyc_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc ALTER COLUMN kyc_serial_id SET DEFAULT nextval('public.merchant_kyc_kyc_serial_id_seq'::regclass);


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
-- Name: revolving_work_shards shard_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards ALTER COLUMN shard_serial_id SET DEFAULT nextval('public.revolving_work_shards_shard_serial_id_seq'::regclass);


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
-- Name: wire_targets wire_target_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets ALTER COLUMN wire_target_serial_id SET DEFAULT nextval('public.wire_targets_wire_target_serial_id_seq'::regclass);


--
-- Name: work_shards shard_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards ALTER COLUMN shard_serial_id SET DEFAULT nextval('public.work_shards_shard_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2021-12-01 12:08:26.821188+01	dold	{}	{}
merchant-0001	2021-12-01 12:08:27.343817+01	dold	{}	{}
merchant-0002	2021-12-01 12:08:27.641319+01	dold	{}	{}
merchant-0003	2021-12-01 12:08:27.652283+01	dold	{}	{}
auditor-0001	2021-12-01 12:08:27.68794+01	dold	{}	{}
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
t	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
f	11	+TESTKUDOS:0	11
f	12	+TESTKUDOS:90	12
t	1	-TESTKUDOS:200	1
f	13	+TESTKUDOS:82	13
t	2	+TESTKUDOS:28	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2021-12-01 12:08:37.853361+01	f	fa27c9fd-6b8a-4a73-a420-a9c20c435f87	12	1
2	TESTKUDOS:10	89JVAQPM740BFC7Q5NP3BGAK1J9ASAG4CCPET13JTSSP7JX9A8K0	2021-12-01 12:08:41.746972+01	f	32ad7113-0fe5-4322-9976-29146fe0caeb	2	12
3	TESTKUDOS:100	Joining bonus	2021-12-01 12:08:50.064111+01	f	5b41a1eb-e222-4563-985b-534f758db2df	13	1
4	TESTKUDOS:18	00TNSQS28VF2P5ACGRFV5TGYWBH5S7554T15VC9X0WZHVT0K2NH0	2021-12-01 12:08:50.762479+01	f	102e985e-f7de-4a68-8d06-dbee971e04a2	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
7c639153-d45e-46b5-9212-411a0a5f871a	TESTKUDOS:10	t	t	f	89JVAQPM740BFC7Q5NP3BGAK1J9ASAG4CCPET13JTSSP7JX9A8K0	2	12
e3a4ee21-ea44-47ee-a1f4-34dc4be04713	TESTKUDOS:18	t	t	f	00TNSQS28VF2P5ACGRFV5TGYWBH5S7554T15VC9X0WZHVT0K2NH0	2	13
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
1	1	46	\\xc074de874a97e6da510f44a63fe43eef7bd3bb9284a1d29fbf346b052cb427f0d481e20a3a7a3447165db06fb5ddfae0df484593bdd18bc0192aaf5dcca9e006
2	1	147	\\x9955203a82842400bc2b2431db96920bede1a4e42f96fe0aa0077fbcf5284e9709f6395a65fcac94f65d38dfcb02f968c27b674fd164e873979d437fc7eaf70e
3	1	395	\\x88bb1ebc61ec29f15e6dea9ffa8a2cb4d626ec39ba5b838e449253907a0c5bd5e6acf460fa0fd0390b67ec87693740399bb372ec37218ae6833f954f82a59805
4	1	197	\\x4bb239d99e9fa6e4cca9f1ab4bad03de98df4348f902046f617c7460cfad06e380f36d470524f622f2af81a36a219ce2a32865371d94758d2efba279a63bcf0f
5	1	261	\\x501aaa0141c97a475743d5816c612ce8f659379ef88f628b9ad4e598e8a766fe4df1ccef00f4ca1fc537b29ebb14607f2e689e87e8eb54a735345317b8936909
6	1	381	\\xd60ec734452b90329c7e94e7029f4565f9203f7bb5a552c7e42bc8d850191a24bfaeb04c4e5c236a07fa8336f58bde8ea82621aee8ad66b77e718b5b41482107
7	1	146	\\x7489dd2f83bf9da47242ba192a1657cd712e645832e295759baa6d1979d0bb31a4a1c910791b2ef56b2397d1bfe652dbe7c96da6cdc61eba7ee37a33899cd10a
8	1	231	\\x33b481db54d2d5aa78f476af43f73e0ccf52f55f333a9657cc1f042bd48888fb4675c64a430c3e1b54bf360c854d5c174573f4480bac61b0bb832be8baa2d408
9	1	144	\\x32e07c7148371d65d6d1525c86fecb5bb0f55d2f096af56e3dd5b094e1e76e30d8ff9436fe0ffbab946de1e99b01f9fe80361b506cf096e73ed3f107c97be50b
10	1	169	\\xbb0fcbd24fc7ab97d60b463031d566719691011d3d7ce509c51567a9b02568245688b89d84c91496c2c968ae5dd6fc7e96f0feef3eeef8c34a3e6cae0f8c270b
11	1	380	\\x435301bcfaf676b8adffb60f0a66024f364ecf14e94d4401841972e1813c78394f7b73270bdff378d9f8a1bb807f946870de58123461098418ec864c4f5bde0e
12	1	80	\\x93556403518c6e7926d644bacca6b437b5ba7c5477d1f6540ee1648efc28e6159a768a0b63ae1161b50956362a1170e6da9dafa5ec5317d087db39bab2283b05
13	1	362	\\x8adcc6dadc800a47937e520e73bcfc427f4692cc8684058649c26b68422b2b71b9424f4e6b735704fe2a850af1724e2361123a7bdb0b6d2ca1e5aeccfafbd50e
14	1	34	\\x9d7d50110d3167ceb621b653f9176e1be868bf97d8cd1de59d23623bc32dcaed664a3ba42b62e3017442a942f9fd282e1471fab3de1c6dc4810e6bf16d38f706
15	1	39	\\xc20374f718f2b2dd838b5efba84a9b316d43d5aecdfbf95e94064e865feaad8bf1895d303601c2d42d56c75b5b53bfa72c5dfff80b377009d01393eeaca16b01
16	1	355	\\x6a399968fd73c99471b14a50758af77fefb31e84770ccfa522f82d9ad4c81304ae4e504e531236d416392d547fed648d273f7ae94d2b4584b54e1ba53a727601
17	1	348	\\xbb919777498f3150f30c93f38dad4fdb85b99542344385a594eee2f32581c2eb95d6c2b3e85894bb7195978c1090d1fb099ae4d7e0fa414ab4f40b5eb70d4b00
18	1	242	\\x51566f0ae4aaacfa92ae4c9a6048fa1e6e1fbaff187f86ed43334c0a869e9776a4efe4014c4aaf5787f366b1d21ed695e5fbb9ef01c3a4edbc630578edf88801
19	1	213	\\x860a9ebbfc3b289055c7d8124ca46fb012537b4fa5a4078813be6026adbf350d10e68b64a81d7bf783679bfdcbf8ec60015a847f2957602eabae3859468b9704
20	1	243	\\x438ff81f5f803edf9e5ce34f3ce0fe3a0ed3f1fe0512fab7f0861f2dc57688a59125784e363e50a7a6d796604b7baf4d3ce7190a182051ded35c24917aca2808
21	1	264	\\x80b132395f5696342c33da67d7975b66fb8bb6e8fa4ce3bf2b69eec790e1bbe7aa8b6eef1c6b57e7f830efcabfe650f325bfc1c344fcf41b4aca247698c5900e
22	1	153	\\x65c5471413fd8fbdc53e24a40eb378fedfbb61ce32f7a641862258dcabdfa0546846fc001823d794e07132086853d70c5507c2c5adbc2b7dced59f977355b709
23	1	382	\\xcd15a147cef28c86f9a2e25174b32442e0ab6dccde2d34f58efa9c5ff6068bc23758b2aba2db12f62d1a3dbb1b648b07e11c1952d0c8a8b3177ecbd7364eca0f
24	1	389	\\x9a5cba279ff4107f52e63ca7c0329b6437ced5d09510963b0bc4287e3eae4c5fff69fb1708bd3b33c859ec026d9d6f6ea36387a7683d5aef79eeb107e7b8450e
25	1	68	\\xd775307eaad78ea6f87fb87871ea9baf60371eefa8950c07431aea543e9a6f0b3af29cc679eac07e23307f5d35ef145de568262c7dcb6e502a826fe4f1873c05
26	1	5	\\xc37086f7f3838fb295f7a40e12b4bd01aa5e2cb698f5e28f5b9bb638e242016c0bff85f4110027ad1d3022dcf018d2d2d586c651650a68709601d852ab17b00b
27	1	20	\\xb3a95fc4b7678912c5c82b9975760ff014bf55573b2e9e3dba6437a49979b895ef72b3de59a9990b2ae8ea3749e2748ae6ff624b8543160ff21df0151acd6b08
28	1	358	\\x78007eaa101bf164db2e9710644fc5de7938472a4a1993abfc024f779c9cbbc925ba851aa6e6feddec46bb001ee551288475214faf34e84ee828ace4a4e61e01
29	1	22	\\xa1086ee861e329a96d932e921857b06fbf307f6383478b031604286d95ee31a10e1fc553a3ff282df10a9c53b1fe8e7734380d31d35de141744b055db633b20b
30	1	207	\\x7bca098456b88dfa64bf9924b023f77f02150734d03bfda86de6e2ca7cf1b1b179bc5cb62e4e41540639e021f652ea085a4a159b936d95b6a1a518d1a2b48d00
31	1	184	\\x14828242f3dbfcf48e8001d848233ad485d3dd7f814f4184bc4d1708129cc8f9ca86f0b1baa58bbe7ecc25b5cbe87c64b6fb06110ff17838de41edf047866107
32	1	100	\\x409537254fd40a75d6edc5ecc5d1c215bdc26aac8e21f39897f9186d0e672aa4a06238a7638002bd966a5a6828a810bff6f9ccae8c85da19e4e5a192b0fa4607
33	1	164	\\xec0ef3b7074c8a9e81b9404b0b89d5da931151dc189da556e5909671c52ea935c80eb21d1450bb664c5b6baf1c51079a09c2f93798b972afe98e7ae53e969a0a
34	1	276	\\x2b63e017194e1e45ff8775a9432870772775f6f5d8785e2a1bac85511ac9c150db7a37557e8557b387c16d38b4b26bf61b85be636b1b44ee2d7be18fa1ea4b0a
35	1	354	\\xc4649f87c3c3b7626b22b7a34f8302ab33de6cbb5cd3a84c74468b362108fc8ea5d32399119c07f14974b63705e7efac872d21269a458ebf1360d0d0b3de780f
36	1	275	\\x0e033f9648e7e9d4c504700562f22be2f935404a0b67fcbaf8b26368db56a0dfd21f49710b29dc823f9fafc99a7f7b1b246aee82c8756de1aab448f97f09200b
37	1	244	\\xdbc36806352a67be8fba48b29c030ac00b4cd132058fe382c79aa4ffcb1c3dc1c81cdcaea4ccb87b6764293c32f4e1d95f683942ac572d468c67a85fd3d27002
38	1	407	\\x0711fd01af0e805fcd0a056b104ba123a146964c43add97fe19e957bfc816d82a834553520051794289f7a7cb9cf4f413fd4c755365f2f14d7b4cdb967eb7801
39	1	222	\\x3e7d71cc70df93733d94a761dd517d3f208ff41c41294822c44be9a32dd3e19571b21afc5e3adccca7b037903d186b1113501904a519f0c00efb6e4179a4ba0f
40	1	135	\\x3cab64bb04ee0ee399a269c7fcb41a26d5b6f6431a58bdb3f208ae8bf19fb6bd6e3f1dd1b16bfe8fbff883194e88b41718d51bb614ccbc32dcada8e2cdb52705
41	1	131	\\xdbcc2671fe8a317e5a5a6550bafb20fedd89905ab6490f5a1bba9ffd214d23cf1665ea2df8f89062a26f63191e2c3d9bec3693fd2fe8bf71952ffcc2f8f2e20d
42	1	66	\\x09a4f2b5ba715f34ec5d0f96c3d6070f572a134ad0b4a4044ab5a2cb428b71f075cbc10faafbe34c66d0d56d81f9ce402a81dc3f6ba50a6afb8deef271d1b10a
43	1	293	\\x137ecfbb3e00c323331ac84051190f4579e58f893320f8828777e5c4a8308c57ea2ae72c27364a5e280af347b69c4d27aef5c9717fced7f0d82854c894e3cb08
44	1	43	\\xf4f65a8342f4e70dac1241763b96b0d179f67e5c7fcf1bee7e1bba8b64003a5f858efde5f7df218785fb5443a510dd825b85af24d914236da33f53388f6c0c09
45	1	299	\\x912413b2730bb5c01188504a4e099a0aa1c3a9d69977903ffbfdf365fa3b801aa6a87b021d0e062133811f4fc759b0f351f77c05fb2b15ee28e3d24c460ee60d
46	1	138	\\x6a31e05f2bedf72a4559825926572af8c083ee68c966a4b30c5a676280876ba0d4864d44c4d2d0dff1723208f81ec3dbba8c53398237f32916bd258d43084500
47	1	422	\\xbb11c24b5d67d26b569bdea7cb771d88ceaec174b0ea6860e6f566ce301c16af1f22aecf49467ec64a214a480b1a4706565d56533bcb253e4eb5bb885d00bd07
48	1	235	\\x89c3898414eae1bc811de44bca8854ef86de76b6567c665867553c1657b9e75bb96126794082de9ec144e8dec5ac71768859b6bf87e59fc64e9cc157e3f02c0c
49	1	418	\\xfec6039162180104f1760b62c6c5790500c7a7ced161845e65a47d19b17a5fbaab2204b7dcdd2c967b2a794164fec6f1cbd1c3a0746789fe748e1efc7853aa09
50	1	234	\\x224f3fa2667f19143f3c25972a03bd092ab90796b9e6601e24bd1478f41fdd2ad3296d3b526ef1f16e8dbec40e63a713dc7398e00d35afcf282da1fb64a17e0a
51	1	250	\\xe3cff870858e28b6ada565436de54049edcde29cc59123104c99da2620c38aae24ce4f6d5789fad9a153dd46884277550c3feac784c664fbbfc7fb8bebcb0207
52	1	110	\\x50932b6ada5c4a3f46d9e3456abaeda08f5c519d85cba7a566c7c36d299001384b53e3d3d755c7e797398b5d5f35699661ec43c2e8205022d222149b90471306
53	1	70	\\x3b4568d77bedc4083581596d1e12e2aa80c4c7807463372bb0abb5776ee52d99a11ae9db0f0672110ae03e944031e74c0d0e44297f8b2bc94a641f29ec7f8102
54	1	159	\\x62f8e0c9c07a2b89d1b27e040e36c38e73f9ecb585b26d4ec421fb050eab51727b3c3a179e85f63c3a359b56b94cb538c4bd12b961b3fe8d6c4dcd6c9db51803
55	1	7	\\xcd9e33bac91d40b7494a335088fa786d03f184832fd08b6c743a7816fcbe303db1ea7ee1945069329246034d2876c8a15ce9da1b4286421e8a8361688adebf04
56	1	23	\\x7831be33ff270eb5651a033527a0af62f324e6341ba90d0ec2a7204c81b842724e454218d237d673e85103ce9100027860abdda657ed6d2663f8b803515f6606
57	1	44	\\x450be824454fbade387aa5c81bc6a943ab34266dfc10b05c6ce22e890497112bd61c2d168ff0658ce16ce6cf619e16d5d26a58c0d563c3bb667616603c79b306
58	1	340	\\x4d12a9146c9fea7796959d51fe34c021aec871310cfa052a06c491c78080e07e1aec868d6b053895869a2a88839d11cacc694b98911240c4cf6cc3f9b0dc2202
59	1	88	\\xff4275072e4c565256ee8acdc04aaee4bd6cd27988d477ff120182e6151defd3f1396b20e833f800fc02d99e02682bb659abbe20f390d69f793d93bd183da30b
60	1	69	\\x47b4b8410a9f849f4afe98461fecedea234fc09de7236c440880a70b22306b91195d02a18088c928c75eb679d0e080763234fda7a540771bf9566ec465773f0b
61	1	247	\\xaefdb4c4d9f50f3d87f41e1a2880eb0a830bd77b6a70e95f673e1f52136db84e080f3d32d4062e7abcfe4d129d0d6127c457abeb9937c014ddeeb5e4427fdb03
62	1	77	\\x11f59bec8cc389e3bf0645fc6a1c874fa96ddb851d8c1ce9337b0b531b2d4105b2281a3f0231a59cb96b89dc3098bc4ea13cc04eed3bfa393697e2b3e6dd2b0a
63	1	49	\\x5a020208cf6082b3df2190ee44787369208db5d9841ed163de4ed55a3aa0903c795e8882d4c596a04465ca89668e148e8185ded9d375e12cc2e69c8de8f68a0a
64	1	55	\\x6697643982a0fd39e6608b23f48ab14111d2bc3a9d07ff7c22c778d3068012d5bc71f50956c6875c70093d53d9427c5071c62c82ecce937ec05cfb98a7f46d05
65	1	408	\\x0a9cdfe97346d35cf209cf423ddf3df6eed4482e806e59c2d8a738c93babe2c9c9420a3ee69ed53b4bbf1995388589bf3604a04e93aca244a7faea196bdeaf04
66	1	170	\\xc770569c03e1b757305bc78d4b1403c467d833bd2d4711267ae78bb95626d6370fb1692868312157f89b1be4e391db8af558260ca8ac13916ba032c26fdb7e09
67	1	424	\\xf03fbe51a4fe60c7d0c785af40dbb48360c12ec242864272fd532e960dfe7a63950c07f96aecd258a2c21fb9906f2252a4c5fe46dc7917f69e58b440b67c4c0e
68	1	325	\\x852d04aaaced4e0de31c2b5eca3b52d022ca65a83ea52bcd69c7ce630f8db5e1339c17c1aa64e0b5373d784d920607ca2618f707fdda72a49a515f528b910d02
69	1	174	\\xfb5c71ba90583742aa88141ab13cfbd22e79d7b6e4ff22fbfcef202a896cea8e06a9c007f45916a096b58ce9b282a7b970573e184b874192d5179ecdc325820d
70	1	166	\\x10d7c106629bf0a8da213f1a82d125b67fe2fb2d756c4e7b7a239b7661841dd9fad64298da53d0ae3a18dbeb329dc0f0fab910a7631717ad30e79fdc7128c60e
71	1	133	\\x8cef0a119ba393d7f3a94aeb8ec93f504d14a65434c64a102da9d1396621889a2dc9d321adddd6ee1c50c11a62e0adfb6adc2aed144c6d3f6aefc6bc8d449a09
72	1	338	\\x79d312069ae475d90d0ae983e1f92d76a396e22b9d97b3d8c34b02fec192d479af1b03c3d715f792763ddc271aa44f36c0d7edd061579c683621171e01db080c
73	1	85	\\x85addc0eac2b339c14e2ffda66d06ff8629813768015184eaeec5ac0f28517dce56b35a6d17694e268d616d181cbfcb0f3a8de06c1bab72a84a3246ebc030108
74	1	248	\\x42a8d321e6e413b21fb324d7a26211abd9bc28c2bfda6ae3cf464d6fae5b883311de7948346f48f6133ef4dc6902c1ba90cbe06a5c5b920c769eb4343384d700
75	1	314	\\x65fb7c5429d0db1a8116439c7cd28f0fde95b8ff9394b8943f796e25287acb1aa9bca0d74ed4b4eb9471ffdaa37fffa4c0171f0d82fabb3500cbc75ac9c11a05
76	1	94	\\x8e283e3f672224218deab60800da9540b308e2a1c571fb281f2ec6ce121326e6404c3c333650e087e4a0f940b5c2793a0c073e1926bc77345ea5ba012d30cf02
77	1	109	\\xfa87e468f2fc28f2934eeb8b27fea2679dc629cdd2f86fc3c86c7b6756818e4a3e9e1509add81ddfac79fdd4c50c53cbae310d4f2e16d1b44bb79c7d1de7380a
78	1	266	\\xbaa1d34f44471ff2e892b57b3659309af26850aa7620a6b688eab3a3492b09abc53b11009dbd9dc138a52406fdd11676526494f53dc86c5028a6c4a62b95de06
79	1	363	\\xbb82bba281f487c1a3ff44154b5f3c0c05e845ba957216b228515cbeee4ae4da9348ab3d41f7d9c31fc41abf0dc5101954ee1e595632563d2bf17074e6334f01
80	1	281	\\x08e76c3fad8dc312d27a31c45cf39bf409545fcc92216f8d46b8b94eca36081ba6daabd379bd34dcbb285e5cf61beb57137a591abf2b97973d626618bc016b08
81	1	258	\\x1bb4b4cb2b1e1ae5f040b20bf6a4abe8aa393b8462d80acde244aa181c1998262c3a89e6af00180b972cb056c6a7e21562b98e503f67e33afda1c3a1c230f705
82	1	142	\\xc8290db4e253786144ff690d92a02888e95cc8d8f7f2a4e0a382d558b0647d823b4119e356f677ceaad8a3022a88b137fed35a35f04d19c8ed7f6ef578cb4e0c
83	1	208	\\x0cd9cc4130de6dbf44d85c6daeb363144daffd9afcab863d15a017c618ea382bd4533f50cce2df29ff7ec51fd32ffa6933ecaf5ed83ba29e8cd3726bb26c8303
84	1	60	\\xde386e9aaa5d786f01a72f640ec8ab415f35693807b86210a8f4e1f9deeb88dad4bf174613ffb758a0da6460e11aa60c464d272adbb001c4850998e835e2fd00
85	1	126	\\xeb293e42a8781cd5ee0ab59ec352f7333d5819824da56a3e18f55d76e989d5db155e44940f0e69e9a3ad89b39fbd1331a8a24af955ce6dfb686d26c1422dae03
86	1	297	\\xe7a8220f27ccb32003cb8f1e571872094f768d96223fc8f9782dbb18934586be17e6961af6469aaf27e63609ed00319c7e3d9f0176562bfd06ea07f881d89507
87	1	127	\\x5d13d200b6b7b970fa7b89a607f6118b1a1b87f80f48469c9c0378a35c160e35d75d4d48f0459c8b2bf167d513a7746af5aafc86b4fee94492e460cc13050304
88	1	241	\\x3b61fdb9952496911f4b4c108d8c0377783b28c589247b76ffa3d5f9ad3ce6d9f99abd593389a2fc93f7c1c94859c87063a80ca12f5b98c2daaefd989637840c
89	1	390	\\x5baf9104b46daeee303b5ae7d28dabcef60873675482c7d7d41b006b59aab0cbd46abb69bf2714c3b3660adc52f665c42bccb16e458f752e45eb26bb6f90f208
90	1	130	\\x556570857287c29ceb0d7b141b51b47c512d69728a11cea0330119f9a9a68d03f7372cbac1e4ac11d72dd2a52c9f7cbbf38e80e29b54a538b96ab92452951101
91	1	284	\\x3a8658e15ba52967e946d97109961903a8ecb5f509fc7ac22eeafa5a9e1f1e8c251fb8d0cb8835a74fb3b93f958ad9394a9cdc62c4b379f3f4711ac51cc01c06
92	1	178	\\x595d48a50e87965314e13328f4a72e47e931c88239f20394bf6b1df5f1a7236adc8a994ddb88fcdf694c3b2601025df8ea77180cec70c3fd56f0426a3d7c5207
93	1	111	\\x3b7e5b82ebac0400792b0b76e8858cdb44b09ca24141b527e6b47e445f5c03dbd54d1e2d4627a3cbe1c9f063e41f5978656cb104f310b6da9250eefae5fe6103
94	1	185	\\xc2f60e39389a152566da4267ae4294d907b0c4607c8787b2ca42055c73c59a0ddbb6110018fc76c821bbd452d1583acc6a79dcaa8950c5d2f55365b70053da03
95	1	119	\\x7a38630bac15ed9408a6aefd2c5691c2b0d23b4a904bb52e399f7faf91a7155b79d2ba82de907d0e76721644f1c7c2c30d392019f3639d4b5dd95feca5b48a04
96	1	307	\\xd07cc4c57f90253c13b875d3235cc93a9033e2a094785bc3fc40c057b6c99ea57d2b86531a5d3e0147b3e3e23d457fd1cdb932f68c10b620a1ba8b24e246d602
97	1	345	\\x8582aa6726de25dba631c5a57f46e56a99bd0b3bcda7e7872374f09f6657d7c8abb1107fa3afedfdede5de35e63acf656d0dbab13189ea8342fc00506d37fa0f
98	1	342	\\x8a5305a6778c386d376bfaacef0d8c2c7fec135e53a6232e1e32f319aa9404f81d45682467f69b02a5beb73ffeb7ce5f59ea10f1f20aff23b0a9ebe8d92b2809
99	1	226	\\x383eb2ac2fc6ebb44e6d74da119f28024cce22abe5278fe6e14867d4661c80b18e0e6dd5b66f1c592ceaeaee6aec60dbcab42eae2e2e9a2ebdacfa6d9d1ca402
100	1	403	\\xb81cf6b79b628a2589c93f2a20c3ca7a56af058ae9e78fee851a10b2c40c2c6dc4a81611e92ec857d7d394dde784b21080165bc80ec4a72540ff1b1fd9751207
101	1	417	\\x8c33e52ddbe9f6005736a106aec46b3ba081c59a01ef90c7ba4a728d4d3d311f001f81be992eb2be48259ff83189b2a52064d33119b291626399142e0614ee03
102	1	154	\\xf02f8121af48e2cf2978596ac13626ec6a3c7b4489d45362b499dc03ae189eda9ff3ee5b79922b6e99210c5e3f6d83e202bd66480bfb9d7cf22796a84dec670b
103	1	58	\\xffda8423da3f20164be52f6a8b607c4768702c0ca37978da64c412711571057dbfeabce2a2b221b24bccd29d77e184d193541e91486a15e3c92c7a7c606ffb00
104	1	188	\\xf954b4851c17a6180502a895e0fbf1856aa7d036c4b8c1b9bea7ede54e5514a6f8c4d0faa7783f2373491e811f64c8020ae2788634482dbd96c76f16f8044c0d
105	1	399	\\x8ec72b45a4981ce79c999f975fb7d45f858b1b455bc09563ec3b6d68f21bb6c58b004c6b63ef4a3daf52221bdd25ac3dea7c3acfa9c0f2c0aaccd5da4a6a3e07
106	1	183	\\x62691b6ad2b306b6a4a76d692436f960dae16b3eaa081eeebb5e4a85fb5f5769f416572489fedd05e14ddbaad5ebbdd1eeb63ca7ce558292501d8a4eb1360a0b
107	1	216	\\xff5e24f460339eb6f9c36d505acb79b78a2dc38523f87030e28409e9588745c47461c290889ec41c277bfae1743bd0c10ac9487663bb52c1c73492f78eba4000
108	1	406	\\xf40f4d0dced1931805ed39a948b5f1b30f2828df034b846981bdf4e0787b00855b889c2140c61bf7ee275fc1b1c7c63a7941695a149f85b5f7aa08a753f23508
109	1	199	\\xb2013eda749021420c600886306f3e4850989599cedde2f5a5d23f2a8ade3f580186d02111d98c51528e8fb5e15282ec41788ff66ad68b83e81eff03fd97ac05
110	1	52	\\x01320a094d4d6bde8d7be813a2ac14d1f414802e8bb8b9145bf5abde24682b58f49b79018e0183f8573777c6417acfb48c79fece495840726816260fd27bea0a
111	1	349	\\x3ea29677be4387ca4829b74cc8a996333b0f106dcdf5ef04a83737e8765c8d1dcf6b65d85ca88260493ca51c989ff7eb77d17ced9a9f5455ab28890aa4e46e0a
112	1	272	\\xccdc8fc65cb5aed9776720425340649dd0b33283505d28f7ca17346f4a8691a38f272ff34940c6c4c96ebe5c41ae54d8eac382beb5153b085983895c9ea6160e
113	1	278	\\xb736d3d60e84317a62c58400795594ef7aa36ad6724cf3613ee7870c4bf760cb66e60e0efa8cd0297809d97a156f57060d6336af9643cf2f5e331d818e75b504
114	1	356	\\x39b226b626c42dab0b70ccc31e2be3ce9377a06c10c8860799b295d8f6e99e1abf3932dce147a0d49a0cbbc7f1de54c3a406fc7c68dfa3c90217b6c45433d303
115	1	310	\\x3b7eb8041746f9c715a3a9c3669ee4e48561cd52865da33a316da6533c0cdc304553fd2f9012c6e72c45d8144230658d17336e7148195ce258d9ec342b8cc605
116	1	140	\\x17133cf226b5fb6686b12b17453211fe8b15801f7f529ba4bd292a2ca7ed334296874764231d6df66a7d088d0ec6fdb93ff78b0c573b2b3277797ae073dfbd00
117	1	182	\\xaaebd22ef74047355203192b757e4d9ba164d3d878b0e046e259bbf2af32b176cacd30cbf2c4e718968f193cd2e5820c3b8d6bc375524aec8661b9d0ac41fc00
118	1	186	\\x6510ba3fc965f1bff228f6b8002370f37dd184fe5798895951cac210a760aac11fdaa824163ed17c41e401613f5b73d4b52cc81d6a6c6858a76dbf772cfedc03
119	1	14	\\x218e5c4f7f4f5ab6d7d017c2d2648e735de85ac7690ada5dbcd37dac6baa84193f850bf9a660c67c59929047a2a835e593f7838e1df6a1c3499d7c4dc8a76b01
120	1	209	\\x7934862c301537a35b3caad6e88a41706964db6293e384002790ffd249d1142223bccd50f77999247aa75546cab6d45dd9c896a8761d3705f33660f26b5aa605
121	1	329	\\x7037064360551c6ef88eacb0c324ce456abd4cbbb90959af5bf45458f7a626f94d1aa396fb191b1cf914beef577ebb488e9e407479ae5c59ff3714445b72bf00
122	1	229	\\xb8392a4feba7c07ae81f0d8c5df8fd55452aeda51fb706c94ab86ed0830a876f64f4a72401a6972160da14cae0d608065d48382ca6ac156d20f049d2138ea407
123	1	81	\\xb138c7c6f2a3bc1e152d974f9555d73e43e1ba43d8e8add800266bd10a1072a48c20c86652d56c2eef772ea1799213b33af376e4040d2cee21283dd3de27e00a
124	1	384	\\x15275ea74605a60624d53f5b5c2a399f4275d9c198ca8250591b40de568c14de1afdf08f9d1afa9ea77f26d5b0f60013327ffaa33f2e96432625250a2439120e
125	1	92	\\x50d08c47ef4cd25220bb9cd6277643766bec72a539168a3a478ed0f9e54f5db0d42af7e2748e3bd4110841c37cb7a381d429cfea050a8fcf319a22f84185fa0b
126	1	176	\\x77a9fdf79472d75dc7cbf55716879d91bb1bfaa24f2261b218abe15cdc087fef5c378ce5cbf8f81fd46d30ebc85bdd73e061171f45f0bca1058d6d766bdc1a02
127	1	343	\\x86493a76ecfd7caa62aadd58761d32170e03b9ad8090331f812d0e33f86eef29ec4f7df78b2c5ea7350a610ba330c7723ebbdb6f55fbbde8cd0eab382dd7ac03
128	1	401	\\x7fb41ed603c731264fc7b2a85f17bace62b5186bf59221ca159a9e36c816ddce5669c012b06cd6eb717d12478cf567f7786b938206221b460f0c1f97d77de60f
129	1	254	\\x4fe58470a96ca1e58a40eb935585b203d847e0d76346dbb1bd74ed319b40a357144b65c7a43947afc3b7c7c8450c45cfb7bc304b3cf85cc3e173f52a69a28300
130	1	187	\\x2b0f38dfad897fa2df7cf8dca9f27eae6d3e2fa3140ebf58eddd44dae4a8dd6f0bb5435aa4efe6b07b50ae2533459e852d351b6845e06a0d0d5f46f776155d0d
131	1	288	\\x27eb997648fe0ddca8547e22a2d96fec04088cecade58312d2b1dbd54a5fef52ddc62b614a82769613e216cb1ee7e8366dd4fa377ad29b793687cdc33cef8107
132	1	333	\\xbe0b24124bc4dab023562816dffd002ce42d0db8d573ec12f30ed446f1ecf080ddd4c1ba76ae7760a081584b8a9e1d75820d3f05afb0493a11cada67a7e8a307
133	1	367	\\xd752c8e68bc01fc1e960a0a4f262729cee427ee36b581deaf20cb4eceefcf896f7a1e211369f07c4e6bd9499669ef1c158492734161b52fd870083a60ec52a09
134	1	370	\\x14a81688ac8710aa49187dfe334893b4fbafb1932220b07ab94606de47b415cfb2a7ed4f3a380eed31ce904eac42a37bc12d86b3abe5b88475a90ba54a304d0a
135	1	217	\\xd5880bd0a916f21b4302455b3daae05ce8e987411def6c46fd13afeb3aa5b8ca7e0d63c3939d639d474813cd3ea927cb6b866c37a36476efbb2ed865ed29c209
136	1	121	\\x6baeb0eb2140b7651d3087b34f218597609d48fc8c36ea0c77f3ae4b46cb4871990edfe8ab71a8c5615ce9d65f0f58b3ebb238f04d4c781c35344932603f4809
137	1	347	\\x5544c7da14efe11b7f2ba2fd81d1fb7b9b612a25deef396a724262587c1b6ffee6b98b5cdd54b78c9661e714e567f5852832928a427ae71f580af004a2112505
138	1	129	\\xaba065f2cf19b7d9da79ada2083c722b59bb9827214cb0d65ac4da0a6441ee037c8afb2e3aa8c8e466fcf81cd7d21a2de77b8ec8d4480c3b128d589d4c21920c
139	1	283	\\xdb05e88cbcd9cf845d24a07399df560a3794c2a670dc474adbd34e4af2573afff5a8bfae6149967deb25fee6af8cb5be7dfe263b719218784fcf57f969601a09
140	1	339	\\x53b4f5e274f8ca46ee5020328dda5fbf33e511b422a1d3e727ac0f60e28c51b296a2991e6cc99ff7be262fcb69d6ce20148dd7ad1fc9450dcd62b4cc8f8bc70a
141	1	201	\\x9a6a5dc41c59528f3121152be6c7afab324a6ca154389c033cbaad87d8ac92907f058d112854245a0302eff4c9e90036992c01fab2a6d9b95234e0f749d51204
142	1	265	\\x96d9b845bc74c20dcfb2f3a73a5fd039246696dceaf579322923b9ee4ff92cdc15ffd00946061b180bbb08a53d076e8bffcc2f568da248f5c9dd659a8d7b8b0f
143	1	271	\\x2236462f3af0a8452e8634b1a9aed7a56c023cb5487f40e7d040b8dd921fb44266c422f783052e86a096646125bbc6e007844e4aec5538afcf5eb1bfe6d06f0e
144	1	141	\\x8d3392e887f3b53f2db9f6b38849fc57cf0574fab7a1e652f55b824a907977cbbf23038eb421471778b923b3977b16227c7c891eafa454ec47347e858e914d03
145	1	124	\\x31b20b02f0527b1460555a638911a23ef1bc11cb38e14aeb3a963bf845f8dc2c80ca7ec82a134ebebef9290b880e5a01868429420e4d02c934187e38a630590b
146	1	190	\\xad2ce7fa514121469fa3ba26f34bf5e3e89f49c4f2af3b0a85ccdf571a0dd4c5a73e8af90a2a3916ee064105b0a527da374bcb9d287161cc9085919cb6466b06
147	1	76	\\x14714b71734f8cf6bde7c9a069b92ad692bd73364d82ea2a159d833c834dbdedaa192eaf57a62185c207afa6a4eca85e1f49b6cb345148517ecd011d1891ea06
148	1	1	\\x9cfffe417740092fa8145a63f64307ef7acc8a2b32630af2ba2820e9ac13b60c7c5fd96e71ccbf9ee393398f296f5ec6abd732a1b21a1614cbd4610b06784808
149	1	232	\\xbd49f54c2027357bb72a1a13da39ee9052190a51fa4da4ac0909aee453a7427b8722b2fd90cdc59b0cd2020660079609d9204d031f87e4a99911ef12d0e2800a
150	1	305	\\xcaec985bff0b48663782a30da1c7d71dcf975d6d74d9cb5df3a840c05e4361fb4c5a9a320d8eb6284e09e87ff1b9ae8f641bcbd744d0ffdb7bfc5c59b3e1ec03
151	1	378	\\xc92879607a7b8d053ba29eb36b75671388af378731e969b53e6bb3c8d2ff1edadcc91bddb1b005e19ea3a7a3e54f8a40862a888942aaa1ad15572ae16518f70b
152	1	50	\\xf689f474fa0fdf493cb00ce3e977541d97e4766669344d9bebcb6380b838330679476d1242a1f020f536a485e59c86b0edecef6360fc888748562796dcea0108
153	1	365	\\x8cfc0ea7c8a76f05e51e824bf38f1a857719a2d141f3783703937153ba4b745513c49a59c2705a05275bf1f2b4d4d282a938833bb1db57dd5a579266359f8e06
154	1	360	\\x143b2a89b52f4b8f77ba7b76ff7f9a759b702cca9fd8691d80f1be73cf3377e902f36acc6988a039a8d9fa738b5a847e306116aeb9e7b932fddf6e7b2ff3f108
155	1	120	\\xc0061c6312560b766e73bf78c0b32b232cf0924ad335ede0539853521d751e0e97328ce61578401412f614aee8df26e6ca6ce81f4426d01254876d9d7f22c004
156	1	273	\\xbde43cc3a3b5b18e89d704cdd477f2daf03cf79c7d0e41300466e8b45ab915ed0636f3ff86e23607aa3d09e7eb1f2588041ea964017dbad7c186281cb9eea904
157	1	328	\\x00415a426cad2f007092c035fc53ae548a1103f31e72566cc82a358c448c55ab233fb9e72e49736e735d8cb8f23ff7bed73d3dd0da83d5f91f9c8c4d4acba508
158	1	372	\\xc4448f841a59cc12d502bc056f71ef1985ef352d9f725ba321960f88b0352405acd4adbf56403ade769a175f4d1b058a88eebd6ee223b56d42b500e4f29d8707
159	1	315	\\xc109dae837c5b05c3feb28a6eddb6c598b4cd7bca1450d7990a5eaeb86f717ff20da51f2da834386d827c6a9c1c090e3777ab494e8b5bbbe0b4d43b57946cc00
160	1	93	\\x07650bb4ebb682b3365f2692ba808469e6782cb898533bf1b014ef398efecae800b654639c728332b7c5f186f27ab49448721ecdeca5228588e08143d051dd0d
161	1	313	\\xea890bd690316cb330baa628d8d81bde445fb729af3bedac9321a7d84af9220c0835933a446fa56f4741e3b2f585ae508e8a5eef8aee1dd3097dfbe6fea4aa07
162	1	78	\\x504f783c00958491e4eabc782b86e3dad315bdfa9a83dee6f018d4e459b3b082466eb5e0b0a26ab432d6c9041af7439363a0ce21eb5620eee07853521d21a202
163	1	113	\\x65934bfac324db912a418555cb79746f9c696d241e1bf68622cca4a54ccaeb0483fce1d912c28242831547e841369fae276a2ca19ba5e1f2b8c151873143cc0a
164	1	385	\\xa31ea49e85c73f067fff6f24fca2021fbe66ea4bbc2d9e7bd0ea18a28118b38be902c0209038b74ecae6f1d3161760359761d1d01ddcd79ab30033a7aa278404
165	1	151	\\xef69e8935fa05ea07a3f0cf669f4e01fc2dd18c24816a77ceb38278af26c781af0cadfa7b124f3cd2b9aa4d77c790d9ceb03acbb3c5979f6872ed60c7889a200
166	1	204	\\xeff5949d513ee9768948bc08d48a40e4ede1902dca59d9c1ab5a4934cffbeb535776d87b3d5074475bf5a9d2cdf828e52efab3e9c02cf320383e2705e57e7b0d
167	1	353	\\x74094b85333836b05976403e5de8270b48de484fe65bc4ce6a3d38e98b56e1fd957f267032ffbd5eb197cab48a14099241292f741d1353531e1634bf2731ff01
168	1	61	\\xcf4f5244c0773b4a278e68a605cfcffca3c65d6c85bd684609a1a65567cea1aacbab433435b509d99375485aa3a4e9c204c6ca1a4bea86c73b88895043e05b03
169	1	3	\\xd6b6b18feb16c766ea4ea3b6cf9e88ee91a15cba530e7c0eef0f512116345cf07aed84c7a7e247e34111868950e4252f895187b5e8f9c96706fb6b625d7b1705
170	1	291	\\x7eaf5d0a72bd48942a8a0386728ba1c1b68cebcec3fa6ac74ab28741dc3b1ec69fbf510fa0cfa08fd557ddcbfda96b357e3ea0560520c9fdf42e33b1267db504
171	1	63	\\x5302913696991128e3c406729150e0aec00f4a5194d142b12be07a3086f6cae19a3f55d9c7766dcb7455042f822d39227a7a9fcb27a8caaa33f079bbd818b003
172	1	270	\\x2ffb73dfede01d9dcad5fa92950ec121a126b3bc9c230f16044b1e40c4d79a86d497e6fa0bae9d8b0c151b064525f9c4417b9a8fd9927fd9ef80d822e4e35f05
173	1	412	\\xb9f22f5d9eaf6998619825ff1cf55395c10bf41775eff0b4fa15fcd9867c0c1482928f24abc1d993e306118476fb99c0100ff0cd9ea77a9eb07fe6d2d3012f04
174	1	324	\\x7346752d2f150e326c379a23e189beaf3b6182f6b089e805c0ab3e42c97f789885872cf280f762ba945548cbe07f8edb5d4272869dfddf58f8d7269766243b0c
175	1	369	\\x9d8b3052e57c2973c6eb0b305d17220b19d2acd0a2096f2aafd74efc62fc27c0cbd280fa27e867fb016c985259c283b973b3de8bd51b85a09115d3ea22237a04
176	1	260	\\xeea5bc92874a056768a872791acdeea8885bd30158670eaa6640bb453e4ecdebf9ba57c0e22e8d12a005ff4d21a8df2498b49fdf0e3c5ab31867631e7e168d0d
177	1	377	\\x1de8786ad16c4fc7713fc5196a684fc253f25711933e1529baa5f367c30deeafb4b64df4d319856f89f5c9073e762862fb75580d34e84f23b9ce6124a41c7f07
178	1	311	\\x354ba1c0dcaa237bf250170fcd986b9aa22f8c5ac9fff6d6db3a03972fa389f359242af81eb25d571cd21a3cd282cb7854e14bfe3706c68b99de9107a8e7330d
179	1	306	\\x08bd7dbd019c1d78441707022a3a43b0fd4e480df06660b80d16f5ce8a2af4b7ddb3488dfe0b6eb601b4d2ae848123d524a265a27971d0e382a62adb1b817902
180	1	396	\\x47f046fb0bd748c54d9d5dd39175c7d43e3af06ef8f7033db29a261630620e28f8da3094c3062a62f795d4b70219e7a5b2780573db33938d9188a052d2642c0a
181	1	279	\\x8e8a1ee1484a0b9f44ae40c6024c8bf8b5b50579fbe21f90ed4d4bd5929b95dd1c3527f468da24f328d23f45506340b98b8fb35a22356dc1de9d25d6f3c4ab05
182	1	41	\\xc65a9c738e407780496f99bf5952fad6df266dd0940769ac2280094158872b716d9a452b6b13003c0117888b6b64cb1f49a55308f98c70f78de0252b2567010d
183	1	255	\\x6e16124b028b5014816c1cc939543e212f09065741f36c5b83b362df265442ebfea1358ecddfe686db6c145ad928ed92e4756a2cd1ab3b5776e9a98e954e730f
184	1	86	\\x23a2bbf34cd508d442c78aec116d93d101efa6dcaa7e1fb1129122ccd59853757d1bb9139c862982af67dd8427e44d94ef97b0f04f89382a2777bfc32efb6a0d
185	1	400	\\xfbe415a6ff34b4012a802e38276a68c8fe158755c3f4175692174e3f0efa88938817801ee0f274f0d0d2368fe808336670571bec91d11d79bcfdf4f603317205
186	1	214	\\x8ca66caa1c556fcf6ff2d5641d679bf375723faffa87555bca333615efd5564ce1376394a6679b43ea335151ce540e7605e8260cfbff00386fc93226b32c6a0a
187	1	375	\\x2b007c4b776d950303ed5cb439e2d29efd20ab911492ed9660a4d8d4fd873a4035a09368af86834c863fa8d62529993ccf920bd686c6bed0eedf5251dad1170d
188	1	26	\\x1192d045a74bfc63c769c39542720e6656445a57143b36bd7f57c2912fd86e89719bf73f8fe3f2b56f2f02f46831bf3484707729f7c9c9c261ce869a49432e04
189	1	318	\\xd497c2b9c2876ef3a91338a7b050ead167be21adab4c0636e465cdc63ddb9b1110b365365d7e2de99ddfab56d4f339902db6c8d1bb70b908b0abed0f58f73009
190	1	35	\\x10022807b6f1b511fd76083031b696e09912766e6b386cf329e5dcbfba9698893ac5f60f83484e7c8dccd334f0df56c83798671a497bb2ef5a5428dd96e5f605
191	1	12	\\x443228d4a1c14c9941df9c359343130d2460295130fe2ca84c23be34253f8180ca54384ef697ad47eaba71ee97a3791e4aeed31eb418f5df920a54d96cf4e40f
192	1	327	\\x3ce62939da6288b1311122ca2f989e41a29523df46e680a1dfa49e413bbc8ae39a836a595ff79425db02bea0c23abfdc9ee7a399e58d0f8989f93866c3d3e402
193	1	206	\\x01cb173564e9460630cad4204a7649dad40193d98d83aa5db32f000db3009a32f77f32911771ec0a7b624b9039ac166db1a87c56c980c0aa184fa933fc003f0f
194	1	136	\\x86366958bd10b2841ee24ed10df4a3447510c21c7fe4ae51a517558825d75f7ea4f85d7684f06017749ff08f7711d583972285644075fc31aa676d772d38f603
195	1	48	\\x36e69e3d48589e205752049122c2870d70007a7ead6fff607696d7b21f7aee1385124a8b502a2c70b3073ae123a2f5e4f51dbacd781989c73c87ddb94750d107
196	1	286	\\xd5749a3c5b3cb2b9b9a5cb0eb0e94015c67f45fdd52691c40e2a7266bec9ecb8aabb4c5bac895e21f286590711e87fc183e935489a77b8e9bdc9976224d4c00b
197	1	37	\\x0ff863f2a70cec80e6569b73084a97b34508cc25afe60a264b176c4317c8396b8313909b085db03b565a1551f54f1071e5389cd39aaa8a1c8936958cea65a307
198	1	350	\\x0f87f05ecb8ecd5e34464d0711acf23004d7200598c8ddb316c796d939b8ea0f3621bd8df67a31a015b5fc5aa5ff9eb9de9c877cfc6235118b1ee366082ddd0c
199	1	90	\\x5aa3fb981cc0477bbf93afa7e23854a92fb4402ccde5cc041cb22754cef818b1bc903b5bfef4d98bc0c8718514f5c652917124348b739573510151053416e501
200	1	103	\\xa24f65b5336fe977bc3c1e9baa8247ce63e89e2a798b6a1a7c0b0dafed3a4d4ebe82a50f914b563a4ce76d9c7139a4a3a34266a8ff511778e49607632d1eb008
201	1	152	\\xa869844f218d7e4dc027c05deb071db5aa16462cf9ece7c9a4a9bcf7d32b30b4dcff2a64142cec6460961fe862876ef263e7a2ad59d8d45da97db64d8efb1c01
202	1	95	\\x0a960d1244a5b8fb6e7db08d0a34d7a19cfbf2b6b135ac6262378e33206e802dd4cf3e37ddd6cc31d1b16ff51d5edc0b09a76f18d9393e15b64c4773f0afc50c
203	1	282	\\x8ae867d302aec28c21411b818c57074b40cdfedb8a6556dffc20859298b811156dffdf03802190d287c82b0f943552446cc2981dfb9ea3b04e7f692243ee9105
204	1	249	\\x20fa2c32f98e7e92107bc85cc0698d68edc4ffcc6670b9d51929d7cef8a55591b94b00379d7a486c2912399bd44a25e35b55d5acddabd91312c28f73a01f5b08
205	1	319	\\x6b30e5adfc83fc65d4b988c1b5bafac98a78cdf8731c864920b8dff2d9bbccf670b1ef3df1fefa3be9a22ab5c058207ea27657568c3874cdcbb208d470c0de00
206	1	398	\\xbcbb8337b930587efe2a24db1858ecf00edba5dd89aa7bc75cc23b5fc717b0680b2781c684128cfff619be7b026397c0b30db87333fa021003f9ff162fe6ba00
207	1	98	\\x8cd8908a624e554dc42ea5f0ce499d10af641b83f1e6b00dc6762ffc1d39d967ee906a9b060333d46e6f0a1e49fc01077d81eff16a85a827d7f213d6a372c40a
208	1	280	\\x66f19f06d47a3f4a52a16432fb9a1b7ebaed5d8ec59f8dff123447b9518bf4c010e4977e0bdea26225a69de8ec1100924bb2bf7e9fec708c18f21804f59d3204
209	1	71	\\x77723552669cef8df4085da0922f2ce2d9748d915929907b3db09f88c6263658eddaa6a8744afdfa54d91d231f8afb6134becfd8fd9976832c1792a48859e30d
210	1	56	\\xffa369594479078bd93292e8f5e2e6af968c7f96410f61391f7de0aa9a66e7992720dbf3ae0bce7586fadb80536abced1f5957ea63c0d61a13a37660ae8a8103
211	1	173	\\x8a8c2dc13f8c680f30ce2d2e4de4600aef1ff015be36b823bc7c6e6c4af7a9da22b5ce02aa5aebee17622c9bf806847b247ccdadda6f0c9429a87c05ea008f02
212	1	290	\\xc4fd12f912940b4a86d304edb962e5a974ca0293a4e6f52da9039edd867a7c0863857136b5f89c48c38f08da290d0943b15212949776a5cc18c754a182d00a09
213	1	15	\\x96b1cc421f973edb79fce0337151c0e95ecf04ec47351a72f3553167de845491629a1f8f92a01f8e34dc8903796b88d1482057d4e6f1f4879120ac84658c950c
214	1	386	\\x27710a4c92d4665e8506606c622b3ae90232261eede5ce927d4f75724867326ec93be6b03040a664837910919feb7cefc5eaaa66e51380b7c223da17c9a2ac00
215	1	259	\\xe41578f333b2a58c305198221ad0782777b9521076e1dc00f7fafe71a5cd738c3553e2bbd1b6457884aeba543ec0f471e832c675fa758195cfc6bde35d37950f
216	1	163	\\xc6dd73c32a70d232fa61f6cd6b13d08b5cf5211fd3a1308fe5ca111ce843da9b803f89454adcdbc0b82e948659540b60791f2b7cb8bdd0e434c4e19413b23c0b
217	1	409	\\x4f59e87406a5e86d4a8598adb7023def0418f4773f14634fca09e4c8f837bbd2271e94e14fdc92adfdbdb34f334db4d2951618d60cfc250ae55e633b53ae5903
218	1	114	\\x607d39db12b28d54606bd792992cdff5e1f3a75192a29145865542921bbba5f156d35d402dbdb3debe716d8280c10e6d548041441036658405a91fbb600fe305
219	1	219	\\x1c4af85f13e0b4e705a1ead3530b4ceb8515c9b39df17e15c87fb99a289faa9a5e7a980e92480c2669b93ac660881c2fb956ca613d6871d6234491096a6e8501
220	1	267	\\xb0acf534651199bff4393942480ff8b2acba4637a2da876be87e9d025b20b02948dc123701f453974db160454dc1c2f31895bb0779cb92b0d5d1e59556517108
221	1	246	\\xfe36c536e00325358e310e5c55e680fcab8d818c428ff4831e24507b03a747fe9e4c6b167c437bf61a577d5479b395c6b03457829a2af07f908d0900dfa7f90d
222	1	218	\\x191cde049e1c1e08b2c29ceef1638d4823341e63afcf8b98be5e9746b6b9411bc87e15f3a3d3576fa0f9fc3d475d19ec34e007867f861a8815ce712398c23a01
223	1	31	\\x0684897238298dd0efe1754ff6281716fd073690310d900887c2b9668ba2db3e7635dd46db802d514aa27717bb877b811cdd66a66049401b2cc4e80bfb698b0e
224	1	75	\\x83851cdbaec68b71f8ef848655ae3d41fd8a66e6ca41add6fc71b99788df393191e1116ac0338d783a981978527d095620a21ae12e2e8b9ae80ba6560f6c8b0d
225	1	359	\\x97225e40474b73a616813fc3a14c2fef198ba3f84fd908f0df80722572814af1241f4be5cb72a730d4eba42a30824c8447547bbf4b06a92f0ae27321bbb3a30c
226	1	421	\\x6ec1038610c149455d67b08cc4f462db0afc0648c30d50d8272e668372bfca08e58a9b2a9bfee939ee1fa9cbf62232352991ef0fb8b0eac8b4b1e57118ce6802
227	1	59	\\xcf902136780354a56cc006879135948331e33a18926f6aaf4e319652b3791a6140491cb4c5af1c493e343e4f046d3da9fe257c55ba063b76b4ed9d3159f2c709
228	1	149	\\x8beaffedada7e45847ec13732f0947ed39c305b1e9f06437d5e41e9e111d5c66cc7790fbf920f2d38fabcafe60cff10b9504d104ec51faa9c282e1bb230d170d
229	1	28	\\xe19525a95be0b311f2d4d3f55eb2447a9792e1848d1b774b7deb61b2df49642523248d215d10c0ca7e7c3a751f440139d4191b1f92c4147ed8b1e015d7179100
230	1	202	\\x8eedee617cb62e601a958918375e36ac98d76f19a0b3369512964f520695bc9a27d2189a54751cd2094c18cee064bd7ee4ed168bc54b0e4b3f99371712d37c0e
231	1	383	\\x615ddb8b49508de43b42194516dfd6028c799d33b6904e16c8356811a906d4e98aca150822f9ddce8b7c2c01135d70e8fea6729c6c9bbf8e732f9c62a9ff0105
232	1	32	\\x6c73e9688248ecda3a6bc5863389be689339e65df52d80f359a8b726e689288f75bc1b871acbd8235daffe93558e3398f90c883250a773396a61097d2ef73e05
233	1	330	\\x2549258093dac74d6c29ee3ed9868a50022469566963bc9ef7b17db8036fc77c07ca675bba42bc7839a211f5571e878c9858b2bfc3db19e8e6069802c6524c0f
234	1	79	\\x1ae51f484f9ee0346799b5be6385bc6ae765cb6df534ca4e0df581ff55e561e8757c0e6265f9664a6c99bb8629acd751d1a6bea9260c4c6b202898c9a1365a08
235	1	205	\\xdd5471665cb123d253512e233ec0285df6d8d054245db2262256833343088b940c278d59086f4ecca35c11cf21d3cbea0492c8fd5c7a74be7eff962c0b17100d
236	1	341	\\x621a5de545efc51905d25aa9653ff0643c759924f6dd572b7ca6eb4f0b6c7747eed0445dd34e4ed884dbfc809bdabb6ff35706c224b538e5cb31ace7c4ea5b04
237	1	320	\\x86ddff69562ced3bbc0c4c01a8a26ec6361662d1fcba4b05b6e750b3a3276b4d88e632241d30e6dc115969723e06671086ac0cff9673757e21b198b425b2630c
238	1	237	\\xc53843b9dcb4a52bdcff456f79ae086cb5d0c8e252a8a82cd7db980a51af9116c71078f76d5a8386c6129e0010660a0c9da42e79cee576050e45f0db24bead06
239	1	99	\\x1a86417b373f38a4772403e53338a064c527aa2494dbde84ce58cfcd3768970d2d115c8d397f39d89cda6b75bab1f54dda221158c544629558b5e18ed04f1f0b
240	1	357	\\x060975aa054956fffdbee8857365bef37027c3f31383c60f0de86cc5a68614ec2cbdf8c5d7c5a5cf9ce272588b04db3883d1cd33a752afe468bfce551e9abf0b
241	1	420	\\xfa348de0437f5a061d285182268a13419e998e3b9318f971f8b5305a047edfd6aafdd3075a62dd84eab199e393dc050164f68f5b048ad04fc941bd4d0f308b0f
242	1	309	\\x049aa11bfbb8c2e676382c14c4c275b421d031c80d9c6a6f481f3ae2ab1f2b9f63785756fe51d694d57a813b8ddd0f8cb122874779789e033e4d6c8d61f0520b
243	1	8	\\x34e6c3b4f96d3fc2d4151891edc8f9b3716a095a899a12ca044aa461f9dd79765317b15207442509c900f358921dd76e3ba84966874672f6c91ea841f827030b
244	1	177	\\x435fb1985a8ad21c20a11df25e778507d71e03f23ec6e6e2dd4b5a763a9c9c18f44e48d8ff4d216c450d4c1f9ba0a2ea05f0c53493f453a96b4282422f34d505
245	1	301	\\x37ad99f3c54140e3b2c1d822d7243129478f712cd62ca74b26a43eb76fd87b1b7d6691c7361259d5cbe81398cbcf2c7f9c55c1d713bf96a42da901d054d5db0d
246	1	74	\\x8a2e12f43159071ea951f015786ca0d2a9e5576758442e3a11d374d403cff81ed8533f341ff5fb7d2c0e0df8f93b840b97d914373e9ad50790877ac7d9b9c008
247	1	379	\\x0b29d74c0510d328146e8b5a64805a4afb10bd197b745636898d2c49dd4bac36465222aa92136007b21ad4cd276dc00b3fae02717d951f7bc67d196f2b3c1901
248	1	30	\\x8bf9c6d1f60b6d43cd251416df0da7aefe4e3195bdbaaf0590fffc3bde570374d169016cc9272a45ee8475eee47670ba32bd28e31415bc200c3f58a407d3300a
249	1	29	\\xda7e747c48334022f316ce36176cf92ff68ee60e14bfe0a6bc43455f1be856eab7f08b63553390adc88301641b82f39b0a0668436578cb9fa54147500e305401
250	1	156	\\x79d78b5d63b02be1f1ef9b935313c5befcc5b4c37f693d6c370a5dd5c5518917044ee1c0f360ad7eb6b1efec1de6c9b4cc6451b7f7a84fc8c44ff9ab6a94c008
251	1	227	\\xc70aa9451a0ea44a4291a43dc543d67b8fd993d30f73ca1ccc5eda6cd444bf3c1358fae586dd1b97f2a5df85fdce84490f3127274dce8bd630ab074c27573800
252	1	415	\\x738f0d313f74bd20e2ea6af0c1fba5842286fe20f31583c01d680b4d71cff68e055d89e82888880c626d765683975c4fe5be8731cc3e42ee701df5c7221cc701
253	1	150	\\xa8ca6e31bd36e6b7282bf44eaa9b967912503866fb2df331e0d33d2815fbdf7f124d368ddea1d1ed96feb030ae2b8ddc24707576e313a594cf36ff55061cd507
254	1	316	\\x73215004788a5366da42d8dec4874790d72619b8f016881c84e920b08c089172d9f361c4a815a5e96a028f4322c09071bef09e09d6b213220238794d2c993a07
255	1	200	\\x3a04987129d7516986823b04758fe7b81fb0d38ad49f03569af2abc7d3142505baf9ca0653728c893272fd05deda793b1185a07c579817b3d8d1d84b0468f10f
256	1	371	\\xf9b93e84b02e65c0f832c6f3e2184bf46ebeffeea5ada72a7b430dc40761d3c3b5d688e39dc87fa31685b2a315378656702f048be0ed28b44dfab266c030900d
257	1	172	\\xbaa3751c12662124c4793390afc97d7be8e1352b89a45af4bf364c8d2bfdd3e3e74e62563b9b7f03295b50a880f805e727d1751ba75b6ef16504bae071493504
258	1	274	\\xcd9eac598ceb9cdc5e78408ef6b75c23c85a11c444efca30026ae7568715650750094f616f59f9833f54acb37a0d678beb584e9411c42cb70c9dbce27646b106
259	1	165	\\xa141198d3550f8ade882da5662cb57e10fab99d248d2797abae38b1f902bc937a2e74ebc6b18e043a1a94af4eebe0392d04350501c981891f6c77554a4378309
260	1	225	\\x4379dc18e8616ba3979b4ec16dc193a29ece3a3273272567f7c8a72bd61c79c4632aadcb96a2ac22648d369dab45606597f44c03d76d73042de034cb89654b0d
261	1	413	\\xdfad9550783f86768b321eb704003936391f5c0a3852a24ee4e352b77bfbf281a85a4584fe4ed8ca499127baa849f6f6fa80bab23090884850e51ae33bfd6003
262	1	13	\\x578d279dd0e1c17f28d4763f507a87f7b0e4fafbb71b59ccac7f9018e866ee5ec75d81b602a8f0008f8367cce4a7b1b738bf9376c11dcf667bcd5f679743b908
263	1	251	\\xc4ec47345d3ab8ddbaf19ec83586a5e894cc71d86ba5ac4024c3d8ca2fb183128b4b6655e40d54a9bf84cdf17ce203b43c7ad49be856bc6025d1ca0c5d21eb07
264	1	233	\\x0ade7fed2615a90762bf74aff07e37efa456da3a0c004d0b0e621971a0cae5094c68254e8e7121b52cc6f2d0d86151a641f36647abc09a95028a3141c0460f0b
265	1	263	\\xb2d1d42d2fa777503e128c97279afd288ddce7c98bcf3b72998f44bb3c0a041c39c4e90c151f6f073d90b7e9d4f57d4c45746052f00e4d12ee4cfcb1d2542e0f
266	1	132	\\x0345e5a6bda437f4de78b849a56ef530672134f42fa6cf9d675f7113a4b2b967309f51fb03f8ad5387134a7bb5588ee032e535dc767b17a86a33a0d1f12a5d0a
267	1	411	\\x373e4b12038800058d6c4700b19bfdcbcaf289e4845e6aa168156e91a52555a4e4ca023dc23257f1160ed988a938f57b026fd8f1d05be7658c2296b83a581506
268	1	33	\\xefef82dfcd5db9aa08a4c4675ffeff3b15eb596405f9d5c959e2e24e30316d23dbc4b3bfd7fd70cd6d4c591361ba3e867186b308a94b365492bc176d5b113808
269	1	38	\\xe72f2f8189d1ca25cf30a3e945e6e93c7714489249c756c334c85804a9164d2e4bca2a8321ec761e431dc4fb48a4bef68ecf833e4112021940558c92f28a8b09
270	1	9	\\x217062cb448c5d190f08e74bac9e8dd3554be12a6547c52966c6cd5bdfce47604fb8466533aff8d25f75cd7805ba142d5a9bfd87027ed561d684bc7efc943805
271	1	334	\\xbc50238c6ceeabcd2d42c7199bf5c48d9eceb6e4d94c0e97cc81a4c8952f2cede76844eee7f6f4fcbb6be6e63e88154735ac102bc5e7c82e7f3fb1058117850f
272	1	397	\\x52c69139765f39c7d7433e3a2ce1d8498c8e0c30a55a7045ec50c16131e67b2171924352f859dec76acfe51da03f5cc481cef3bcc0b97de1f170db53a6f02b0b
273	1	337	\\x17fad236e34421912b28651558781fedae6aa84a444f982d3dad4317143dd405212e46027fdb32fa76efeef87884be3dfd930b54c111669a92685919f53d6808
274	1	157	\\xa7334238f7464880b968aa39ecfe6510138a51bf04729cee6ba176ace86beb00f1230c5df7b868555696ff29ad97d6e830592c1a9b9ddc7920c5526992b33305
275	1	112	\\x9c0eefdb305bca447790ed1bcfe39f70d689128d38b49d36f8a9e7705e98345a24ff4745b236447d20a66397b12677ab7e08bdb629e557362e140c0534dc3c00
276	1	228	\\xdf59867ae90bd5a5110c321c00cef03c135e2e97c74351b9203fb8d9ad79f3680b46dea2a429ef3db4bcbed1cb54b3996a94a7ef0413bb635c08c821df7dcb02
277	1	376	\\xf31811b3a95bcc49f92f6678d8bc6d4447c7d304b3f93210681f91240dc9af16a6c278ec78236e12a79bc903b3f437680ceae77c750390595503bd9002c6d30c
278	1	332	\\x9ccf957482194232bf9bc36d988ac1ee70dbd9e9c559ab4b783b2a10366addebf61993174a0e92c3bcc32ec1af3a5ffc2f3f95e5beac68930ae26673132c2b08
279	1	17	\\x7ebee3da4f6f69fd1e1fcca2922a078c89cc07d45e2268c118a11210c52e3fd02ebe5f6ad7f0968d8b776fd49d200a9aaf23db154eccbe74f4bb7ee35e5e5e0c
280	1	203	\\xa8e321f00459d0b033aa11b68cc87f8dbd6f6bcec46e8e7cd0b88e4fc960721bbcc99adeccccc63bdfc4486066dc6672a567cedec62a01bd1870ee20a5059e01
281	1	89	\\x517045dcaaf0e0b1d93dfb9d407d8224af2bbf33868d6a801a2abd4f4c65cf0646406383322f32e11f60c1b236d291f747621ad27ee24916eae85bbc54025609
282	1	269	\\xd1a4ae86205be103d4edd4dbcadb445e7fa1d2f1e8e518ac337e9e857ed5367ea54f85054b160b77c54340434abb575fd0c76e5c925e0950f53600e730e6b508
283	1	361	\\x3600a10e49a51796548b7b159d95fc9b3ccc1aeaf9401f223ff3792cd0c0813e278c6daa14cbec0c0374a6554c08b44b5a88040c05c066d2744b44dc8180fa00
284	1	87	\\xbaf8396084435e259ecd58f77dc48fcc20303b25afcee1519bd2706ec10a27dfa18679312ff430f387c0a1adc5efa4f9365a58b1af9ca506df8d25d12b574c0d
285	1	387	\\x3bd319adf8f1cf77a785d073783a6a2356d8bafac8c329901e53f99485e92eb4de2622a31904dc1a6a63b13f96476ee2392fd547fa5c050e01db60bc71725303
286	1	25	\\xd3e9fd99c738a5ad949cb54e3200e4b4da5a8aea4886f4301fc9d095e2a402cff18a012ec5ad6c94dcf3aaa76a69d9c2c27dfb64858a9745ec8e7747521edf02
287	1	4	\\x733be87dd89b9e4191cca7d211e1bdb0bac335b3012d85eafcfb259da7714934f82a446963d0e47e4fd9b618c3d4779c1fce156ccef20f9691b41f0c88662800
288	1	84	\\x2ef3a87dd7aaf70646f7d3d29a76638c93ee44ee9e8efbf3cf3e5056b36bc105a2fafbfc73f4f5edafc3b6e651dc090e1c45b48a111e40fc5a044cc3e36fbd08
289	1	404	\\xa7d25985b3ce59d2f5ca4333b724eab4d837f9ed11d2ff4a46aee9e835e1f5f7d157e403440f88b4d441ac5538b097bdfe7488367cfae6ee12e9a86e3681250f
290	1	57	\\x7dd8036ce8f4ab6ce68cfa1e7243aab5e56c5c3484de11b52d0aa31afb6a4adcb53d79fab324f70afe176a82f70471ba6e4c45ca04ae65d0ddb4781f26a6da05
291	1	322	\\xc5925a902f7c64f81107b3bd3951f9148defad75eed5b4caa12f578798a7c15f6e33299f1d387652c8e3e26478169fbc8fe2ffc3f6ea0ee82b9a7349aa048f05
292	1	374	\\x84e2014c687ab11daa84a8282572ad504bef78d52565cfabdc3e4eb3d950e51dac22d42871c725d5a813509a10732b25b869729e88adc59f8ef11c2d17df2c02
293	1	18	\\xf83a6654e844e441ec4ca8166d5ece4377f8cae37b002b8f82cd7e9f0b30966df628229a784e1e976f4de5d4b353ccf19ae8f6967bd99ddbf9992140d1b9190f
294	1	105	\\xb34d961be21668d823b572b211d38ab4d363e11f14d13e5e2d254115d10d3844d13e4bb161d38fc11a5d6d1dddfc0d91d747fc76cc1bcf60e838d4d6a63c2c05
295	1	317	\\x51bb00e7b1e5ede29e89c7fcd498f7958002e254d88628f84b689a94dc9fe30629f7005499877a247db4ee384352cfdeadb959e20b73250cafed9c9c984a3402
296	1	393	\\xb895658a2c52c72afbf616f433ea328ead8f09ed586754918640ece30877e995df17ff68515a7ca44efe5df641c8708e64964662c3609434dfbc8caac6674f0c
297	1	253	\\x0892c3d3113070b1dd7240df49738bd8154b4d9e12f154e186e3430b93eb83b2641d1bbee87ec98f55015ee71c565fa562d008f925d4e9268f67406f94b18d08
298	1	388	\\xe3b21162cef98f1d91ed415e91a920ee0a7e1347cfdeaa1df594b93ee857791e61a1dbe4cb0b385fecbe37996c1c175ea606fa2e207f7c57586473dff6cff605
299	1	161	\\x05db586d73bbcd2518451ea82c0a045e973d7f626d0b2c6540f80fda8006a54a56baa6d5ff136527cdde0b25dcec5a07d259e64a43348b2ec7f0fec6c3e96409
300	1	162	\\x67de9255d89da7de9d06efdc56a9aed861e2cd339790160857855980e03ce022d5fa2fe639fc22cb9eca02af4dfa3441f55bc80490296299464b9c3ac66f7109
301	1	67	\\x9ee8df7ca82564c02eca64da70e57b3f40de42c4a79b16419f36de88521faf7f9fabf0b8932985f736c47d0d8d0795cb628b32079bbdb982be5a47e440553205
302	1	215	\\x2b1ffadf486413207348b6ad363e6536a2c00abf45b512f8bf4bd318b8c7d715fc0687dec93aeca99a4d3a19ea43f01e70904c1b8caf4d4080794fedd975fe00
303	1	115	\\x5c0b1c38c1c41f7b51f7ea607310897425b0a5e704413695fe3ee9b06f170918f8034e05609c1ace25244f718731b3329baa99e698e6213c4811fa7a6c6acc09
304	1	148	\\x04f2b60ed5c21c07eb8c3a7886618d1e508886507ba022bac991cb792a8f02c228a9e4f42dd5a97d9994b815a7adf7243765bd81784f12860c820d9dd0baf50b
305	1	366	\\xae4120ff8470b19714a00d7b5184ffc95fa346443fffefbdf4043316100f27757f5fc3bb61b7e068041eb14a5a30df5ee1cdac8333dcef5dd8ef423dafe86e03
306	1	303	\\xfcc7027ed22318dc80a47d14a433153692d1ffbf567cea6e96f737dfda0095c15a9b928d59f4532a02c58e335c9d0a1859e6e5a2095e0ce7a37c2e7a2aafe808
307	1	285	\\xd90cb290dea23952abf26e1ef2b0394f20a9f12568ffeb077bac6bcbb08bcc363e75ded464cd6a5ff14b63d8496f795d3adf959af2fe26f69e3299cd6c992e08
308	1	298	\\xbd945c90490816d5255d243c9f9b16108be5bc7550a17e378ef814a1018d27c14917d4135c5a2c0c2c5fd224e4c24610659bc80b6d61f4c79548ddd772932308
309	1	42	\\xa6eee96f03ddc8f8db1b370126b68056a08b6b42c43b62cdd16207128dca1d59e9f34b5335216de4565e7c85656e0f73740c24ff1db0a2f6be62ce22832f3f01
310	1	352	\\x980012ebfafee2225fcbb9a748a3bbfd013328225deb29ab69abca83195f6e291d7848b53e7c3a064b789c915eedb9dfd223f7c713b977bed84c70cc1fac160d
311	1	336	\\x7b1e3c7221880e9f31c65117c2014279d7c46aa2a80d055eb5fde8f96bd9914e263044755c17b23a1b5a8b3d5c5438f42b7d6b62ca0ac3b47c65bd32dfdcb802
312	1	145	\\x18585ce6251f2bbc1e71a64573d61cc9ef0b0af3e3c7d211a61170d4b979bae701e1f5713c578f402cc1a66a84ae3b30bc0713e4148e6144c4e7827ba8472b04
313	1	73	\\x96cbf5ed12d010dcb06ed9700961cb871311557c3e54b8722fa06bca56452edbc03129d3b604254f52b5c07eb8d89fb8dd2dd608250d91fc1616e16048b7fc08
314	1	64	\\xab233c31e8bb5fa38a5bca092e5c2fdbe02566fe9d777bb39d1cddff33fd6402fc8887ff071f5c8f53fc182d3085df6a0e8b6410d511566238fa0dc239a32a03
315	1	192	\\xbf2e8b5e626ba9fd364bee10b375b8ba1d1d7f9061ffd1c17f6fc3187abb8c20446bb9fa3c677dc0ad23f80457c6849b92b9e358456707343628838367a1ad00
316	1	416	\\x8de4a8595eb78b71d293db6d435e9be747d0fe11927d898c39a9320e3f2f48fcabc59b3fac250d43768dd9d20641ad66c2f31f177a82109229e582432f7f480c
317	1	40	\\x1890f8461a2af155fd757506096405f5bc00c222b548db2ebbdf31823fede6e493a3e8813dd93cd758cff384aa18a0736e6c20a6b2154c5e2c53038bc6aece09
318	1	134	\\x6ab574e2a865b9da5eb7767427e3f5baa8dbc0945216a16d21e071e1c9da9828637ec5778d9bc33bfed333e7a7142b9706146433f38c2c5ced9534197c83800a
319	1	189	\\x19cfbab4f6fbb279d89ebb71a5a15bcdc2b616d99dd2018d66cc05461f5b2539f0034433eca6f5eb9a9f2a1dac5fab054e642e902c3d085e821bffc27947ba02
320	1	419	\\xb7391a4f4f7bef81058e2551e90574c8bb92ccf203527e88951c4d0985c8207982206b5a6a302f40645d5c6df46c9157cc0f3841415c7ae557a4ec9704ad9d01
321	1	117	\\x9b9f08f8f0c3dea7c746166eaa542e29edf612e5ee2809152ba59413c297119e2e8b6e5245101bf29d69235462c991271433c166457a581baa2c2d2cbca39e0f
322	1	191	\\x5f8756e68133d457a99aba6c4b72e80d525834a375d22e082347e2cf2289370e4dd3a677a9ad713cb1d6ca0f2c9540ab7e35dc4b622276bcdade17380f4dd404
323	1	11	\\xef2466d552c1c2d5ce5d6a9de4cacfe32c3489f5fdb7d0d619e4d9643bd54cea3261767c5ea9022b80a5b6514eea775109b5da962f2dfba35617cc1adb063c0b
324	1	181	\\x208d9fd9a031c8a1c8e65128f4be394b5ab8b4e4ab18e2b0a7e15d9716b35805a74579cd70ba7b30df2d0baf16bfb149834658e3f23b7831696b8552b2785000
325	1	238	\\x1c9441a57a0a1aee1fa387a097300a8a8908aa5822f463b3f8ea033dff4b7fefe4ae92cf39bbe44bddd96fb57d01330144db4ba373e9162c3da5ab31b8562c04
326	1	230	\\xeed11a34ac313a47e94aaf2e7d5933f2a1c511d797a948f9c5b292f28a3db57a58b2c5a476f9aa7ea10c2e9a6a6fa4c9c69fc5c6ce1fb8597309557e573f2901
327	1	220	\\x85ad685335f2ac95b702aaa3f23817fe602a248dc31a675a996a8002eff4b788a83a4ea87d20692368e380a492242b91de2db5f6ff015181835629bdbea08e0e
328	1	351	\\x4db51d786c390ae2fa4b771f84d0cbeca7b21f394c1db53cabe65792ebe657b6f007b2ed9a67934a0b54d80404446a8e77b80e71d0c62854009c6123843cfa0e
329	1	211	\\xe0f164a8ccac13fc116c6661a72a5ac50d80495cc9fafde3728c0d1a55e9ee93e671d9d2003a9b036ddac28f6d8ee90058ea2de957953818828bc82dcfbfb400
330	1	410	\\x9fae7383508efc7357892597023ae5c6d49d413db28c5cfdf9f22f3f43eb50b74e2b5854f7c86f1873f8febcf7b7296952612d21e5182931dd4ab770556b6608
331	1	236	\\x0b04bba0ff62b1aa216fbbf798f23c744f86165c75b751b87ed48f688a1cf8259b434fcba40d4869bc090cff65a13173a0018557aa2fb595cf9ad6c483274204
332	1	364	\\x755c93b4dea032be838e3c7d88fa2c2a6fb0b367e08b899122c7050f9980c2911b195aefe586a1adef8500769b540e711a3f93ef03df54311e2578f9f39d170d
333	1	331	\\xe3ee8154494ffad6162105c39eb2ccc271609d29b860a25eed11fcca09f14643daf62226711daf446248e918e9243aa6be4a454ab652403d899ebb5b7de4fd04
334	1	54	\\xf56e002298502cad46322119dabd8b6ae6ba01dda6450aa106512f76095d027471d2cde26abff21d5591c6da79b66aefd0115c37738b9d8a3725024ea8518c0c
335	1	223	\\x65bee5aeb583f2227bc6bd73ddf5435d38ffc3f441e8ba342ae79248803f5759b2e81fb0cecf4b3b1bb641bd6e9ce223cb3a89d318a9bf6ec51b65d4ceed3707
336	1	296	\\x5abc5e0c7fcc6a03cb46d013204236842f8351d306f78f4ed59ad817aeadc06c2af05f70fbc357583bfdb0b68eb474e09fadbdd3651c18a1b061d4748297eb0b
337	1	45	\\x4c0a8bbc25ad91c57cce265a8180998d60bb5d93e09813d03ada93e39c5b85690f758a87bde747483c211a6897e0bf9818c35c1bef21e6387036f01f6e32900a
338	1	123	\\xd22eaa15669508b3eb37a0bf1597c1a7fed39bb3be8c7c48e6ca5788361cdbf5084609f6dd64bc67344508d880da3622362e6e4de11e3c81e87dbe64f8b7fe0f
339	1	27	\\x5cfef5fb0cbcfa1412500bcc0d58e872058734ea0a7005dad3e4812399066e54b71c949e02279bfd907f4f496672b19d7ea6c278a81c927bb3c74467e6cad80a
340	1	107	\\xfe7b81d8148a2e7b4cd6fd2d3d5493a0edf4573caf86ee077579b94c878cd70a951b223825b892ffc5c93778e232f64965236c7d6db1567dc87bbc71e3856000
341	1	323	\\x12fa01c1c6d1a6a1ad13f9aa830f33499b24c997b32d3264c5028d223a4056b18c477133fb49c00a3d931c55f7ae4d00095d8a8f6609a703b7a79c78cddb080f
342	1	402	\\xa7d18aa9554820608cf3f73b5760bafda34b52c6ec84980f626415a6e1bd7ee34501d378a9377743b1a71878ef69cdcd39077154f4183e26c4adcb4d01867d08
343	1	239	\\x55a9e6b0c13c0eb8b5bd2e73a940c986525710ce69055e9dd435e134e3dd9fa1f7277a1497339be45889023b1bbea1aaa48aa8fa2e78c4578106809d9400d607
344	1	96	\\x1fb7ba1573b41668660ed96262c6470af65a275264073dac1c0626989f0b6313a48e66254f898d40679aa3c7c3ff05d1154dde0394387d2e54e64ada878f2906
345	1	2	\\x23f22822e1ea07a4f603039b59622c092dbedabeabf1c658239943b501fda5b1fb43acdcb522a6663ab0787fa9a02332447b17a98e9e5c8f8ab6577868182307
346	1	24	\\xb3a8bfcf3baa514892441af8609d77f105bdef55d2e2c5428bd7e17609c56c4ef1e336195a10ecae982c0cc0e0250b117e198d92663792473bb0c50ce66cc00d
347	1	257	\\x4239818442ccb487e2a0ac66d8dfdeb999a9c6b8b26935ddeeb8f4f5bd2bd1b61758ae89e018187ab6139256798ecb3f879eeefde07d7f0de4c04deb75c7ba07
348	1	321	\\xdabce0317a3ac679e6f44516c6123f2072b599af60d3398c2d2cd0cb4ed77c652b06edc24b1859ce72ecb7146b892742fc9fff592145717d3cbfeb107e52830a
349	1	300	\\x533f3ff1da3d0d14482f3faa17bb583b168bc79f28056a350a614c1923a796d4a7e9a9e502a6823313a88009d1026ded1c043946ce4b490beb89c15c66a00702
350	1	277	\\xa94307597dc9018f083fe97f1753c99565b833dcbd6d4c3d8e777421dca5c8bc77d6d100a62712a41851e173113cc7b716d39df5facd90fc4d5d0c7df90ec104
351	1	10	\\x9d161a67015541222c4071f6188f4093053265524d271e1172013b0bbb8dab6cf5c92c134de036a74cf83a4cce6f75dd4400cc8fa182245913beeb5cc37fed0a
352	1	302	\\x1881023e1537d90e157569efd0af558e761ce1648880f49a3d922def30a178ac534f6f247a215aa19a316fa0d8a222d024b019bec0d06d38506fcb88b0393c08
353	1	104	\\xb834f7345ae4c392333fc47ca5f5d6ae31ce3e56d47f8b6083a15b0850ee449d839ea85b64ac9ed91a1d46041218797a7842816aa2067c9e618afae82323d206
354	1	405	\\x3e390f072a093d41c18fe1c7efb622b7e84a28e6638affcac3e33ac76d6f31ca569a98b86c82609180ba821b579a51d411cbfd87561dba1d0744b8e06356bd09
355	1	118	\\x634335dd5ceeca77cb729fea1676965bf2d52d5839529c44a434f50680ee66995b220f39165b8e545df2434d8089093940b6ed4c5ab48011623af8f6d970230a
356	1	196	\\x9e4a54692e6ede51917afb517bcf60fe74f78fc060ceb6ead202437209cb1e892dd1af4fda466658b4acfabdc9a55c8cbacdef7b36a66735f0e0d4cf501ce50f
357	1	62	\\x69b9dc231975414f17b6fd7cecf41b3e3acca0760b084be02c32facc92e72af17ddf3e2ca437ed6b79d5b4b77a4a5c09391cff0ffe36e80d797dafb126e2410c
358	1	262	\\x59cc3d25dff113fa2e08a7f3e36361062e84769f530e02be69628f60d2d7e49046aeb987bfa95d76181fda82b7d36452aad05bc59e1251455d61661299201f04
359	1	326	\\x107d78aaf90caf7fad54a74cc7c6a573d493f54b0f17a7db777d62793f9317001c7ce3ab1a6d6f91bda4c6226aa4be54d2599c4e7393c90c3d8c49fa9f961d0f
360	1	53	\\x0f19f71c4251f947b03b728a473528f081e590691cf02502b89dc5d3fd65d489eab646568cc3c3bbfa1a0b009963f8f960825f10c6f498195ae7690e6054a90b
361	1	65	\\xf76d8147877a09e6977de5d1652cb994b032677657318a632f38b2de88a2ba6046fe59cadb5c763030a270aaa8c9f9cead55a6d2204830fcc3608395f7e0cd0c
362	1	122	\\x2f2b1d2066d817c4abaaf7576dd532012f3dfa20dcc2b040c8907cbd674eafe66fda07ec8771f6beb964c3f3adaa945187c36db6f95498d2d695fccc7e948304
363	1	143	\\x3ac694097ca07976e0b6ccfe532cd71aa92557e5b594d520c14f840ad52cbd794f440bc24ef1ca71781e67a1d0967486a308af9abb1db202f37b6059e9dbec09
364	1	195	\\xe6ebfe0057979a23bc329ccce6f07658945d59e96e18306648c6b9e3b8d1559aed437f06034438be3ac1cd93b016c017b196bd8dcce968d9ba3b5eefa5c8dd04
365	1	252	\\x2df7ed340ff92c413ea21c9ec86457c8801ea4dfb21731c5bc5a5a648854b9bdee03744a108d39196b8b468124b3cb9acd1f02e0e7fd0c2edb666fc2baeadd0d
366	1	423	\\xedfc5538c66a385bfcab5af03392448af9657c38821721880f637aeaa64d5eedf2f1e65d55417b5173d7b9828fe4b2b56c662d1fdbe9372dcedcec16b80d3006
367	1	171	\\x924902b9500b56b6a0c527da60083e2ec74f59bde574c6f2c6ae58689798e5ac7ecd055c6b45961ec2581534bd0e6ec72174d55896bd06688621c78d56537d0e
368	1	194	\\x3b964f7661369a4ea4c5569437921fccb9aaae4e6b6a7c829826bc6114e0077144104df850d0314724c83eccd8cf1b15ba608acb3dbcbc05e16a1732667b190f
369	1	106	\\x35021c88336c56d0fc37cd715e924bffe32f0e0a5062a34813b7b619d2bad112cd42d61a722c1619c5e52b5f9e4472041c726bd623390f6338aeac7b2a145303
370	1	240	\\xfef01ad42f73ac076bfa865e0fc7235a9ed196c7344d750c2c9ea2143e515cc104aa26edb3af92715ed4526a29229b92681f00356f6d7cd8597bd26137aa8306
371	1	295	\\xfb6a1e489acb6691323f7a77b7f14127e3ef6c6dc834125b1c2058e69d7249f323f5a1ea0fa450c1572c95cafe89c154ade9ddb72dfaa01752bccdc54b97f009
372	1	294	\\x9684ca7fd5f949ae7363b61280c1b0a6968fb7ea536f7165da5c995b029bcfce9b0f5af1ed248bd6f3e85907e2551ec3a00939876d662d3d2b494fd97f8f7400
373	1	287	\\x722521423a8e59bf7d61322b589c4f5db9f74cf3c56f5119110e0f414a7fcaebd716747a8356103d43c25992d317a57d4fdde798cfcaae57e801b4cd93404c0a
374	1	47	\\x8e6f71098368addb6a59e54f9b6ab2ec79970db85ff3705dfc4bfbc327ea446ebadebbdada54faf4e53c3a45c018fa87abc7319b2848eb8805f550d86c99e605
375	1	175	\\x7c96b91f8c34cb3648316f76df3fd090a8c9813747e07667bfda2e5e9fa9364083994e7e157a6cbaa5ac6ad1023fb41f3da52532a583897b11aa0e8a4c85550d
376	1	212	\\xfad1a550328005ac76cfa9a57edc01f3b1ec080958d52614de1b2fd15ae6f5b67c7dc419f72901446ab80488589560078dffe37bfd5d6c916d3a86f6399fff01
377	1	289	\\xdd7f4ca7a5c9042b0c8f1f767d68b087fa60cee188e4d9ad08d138a5cd670676f9171a4e20429f75c410347904ba6404c879c6b0c3b05c7bf45b8f0a21c9a101
378	1	292	\\xa6cd5d2d2d9718b9bbc9c1c8a45eb88140c1ec4a3fa6a746a60a204224360197a79442fec5a231c1e761c79256affc46a6a10e1b2a368b54749693df47542107
379	1	312	\\xd383994bbdf96ed9f1774aaa4d64daa628428d795ba3fbd9d88633a1d9ef39cbd04e97a9d11a4dcda4041a08a82ded2c02244591e837d8d1bd8d67e82b13110b
380	1	179	\\x84cfd3fe1b426d0d460fdfb0d8014bf2b0902e4c61d9cd9c138a70d0ff542f44019ee490a500ec490c6bbb82bf484bf75827e1a625fe9be7451634441295d502
381	1	344	\\x8c217d2fc69ab8c19af09414fd1e2b26ffce4a71d0004801c8626bfd1c7f42ca8061b4ac367de48cf6d292105b88bcb31b4e0603290c363e04090568a3f81d06
382	1	101	\\x3087ff643cbfc973a6891f5ee6bcb907b3d96de97347d2424f63d5358b9dada8b413293673be025e871a641623e9fafb995d66be4dff47c76d33a0f302ec2805
383	1	308	\\xc966507e93321ccdf771239d9ed207d83ceab3b3e7e1ef9118502ba1e2f766b07ad7cbf86d519be434bbfa66cd576b8235d3f8ba7344af10f28bee5a69ef4706
384	1	16	\\x981408e0c00b71b219d3c51017598afae6cde6d115ea437e7408af59abadfb5275274108ecab6a37e0849590539089cefa7d2ddf5f4e40013713a9352df9f20c
385	1	414	\\xd1f23f520ddcc7879be216e6dcf5f3dd2b104ac1e765f99f9f2c0dd634a2f4c7b264ab288cbe3b0a663eb31105b54d6fc54e709f6f6c873aae3d3688512edd0c
386	1	108	\\x6325bd3cf677c9f5fe367dc5ccf8894ae4f0f6369c7a1fa324056f494a82d449a34ff35f2fc5efc36e636fe4fc7f2f0d71035f8a7b03c6d4fe5c3e0f112dd809
387	1	137	\\x53de69a80cf0c888a0c55f877f4d0438ac3a2b36628987bd87b51ed6b7a5b408572af9499fb4e68c9c2aad3d36d9d8028676fb17d2c7b07953eb0ac77c54fe0a
388	1	392	\\x34bc5d1ff16da69dee1bccaf5641c2e650d83696b77331f8f6bb7bd91e1807e7f63d20e529122f17a12c5d0e47de99d6db26df1a46c6dc6360bef26ee9254008
389	1	21	\\x128533919b72e89875982f86c61f259d7094962f08cd1d5b4b31c489ad6d3d5cf9730ef2628b9e286d3d3813a72b8c8335757a2760d7eb7d37ef710d6067100a
390	1	82	\\xcb3c96972ed7a2fe88b332f7cd865167cd0a6069da127ef8cac35d82fec71a095ec0e8f06c35defe77cb6d6892f22bb0d8f6c2653f8ab982893eb3deeed27a0c
391	1	167	\\xe244561322acd518cc992000a2c05f0c1d57d740e30b144062072b6a4be81f9a1d7ec1e3ba1969e32a6319bab5747908a433b739021f418682a95fd4448a900a
392	1	373	\\x7ac41422b7a8c5b001c6939ac8a60dbe8ce32459a82b9689de3c8b90a5797f75029860ecdd0c313b54b8adf85bac73784469a7fe923ab2412657c5452e111402
393	1	168	\\xa661acb6a797a6f20f119be78bbd30d3ef8ac64173b51adb693696d499c5d69990b8ab0b145e650cbfe56ea4836408929ef30fe17b1fd1f50681a770ca24070f
394	1	210	\\x3567c2b2ff8f3efb224d4279802215d301e5e4a913ef7cbb4a1a6afdd43efef48bcb6f74e3797f34f6ca8407b4c197be017dd8903b49e1ed631199dd66615b08
395	1	102	\\x2ba68a140a3b8b4998461183bd4b468d7b8c7c6896ba47bd4392134f5ad62a84404e49264f577fc439c7e465d0f1136d35e209a3940be8b4d755f09bfa8d7803
396	1	97	\\xdce0a094ca22d48f14281445b3980c7335e793d6a89abecaf2ea89528db85bafc7e2283c764413acaae049ac88661de93fcb5c93d4b61a4cddc6cc2ff299170c
397	1	245	\\x13cd6af0df761690faffc8a21c9094fb620bc5daffab47d8be75fa020f11eb9dfb17721d240e5edf08cfe91d9e327ceb548bc2da76a7c5ce10a6e2aa5ea63109
398	1	91	\\xd5e8a31d63f0feca8945104212e5c67fa5db174c978b161bb35d134fcd1a402fbdc8608c31654a52e649410524e8527dd07e7b98942b25d7e7161931d8aeee09
399	1	36	\\x51f5aa6ab78edd9c12b4c97a2f053a2eb8be2f69b1d4de74c49128d98b63ba51969d6d19ef0182fbf47af942538f4298638cc5dd91ecfb6b752c1db79bab650d
400	1	394	\\x1d5dd9d83faa72c559f59028cf3af5def024ed4cc4c46f16725b58e431e0b62882200d1a96fe66a9281778e704941c8704c518fde63d6020fe3f671c2479990b
401	1	391	\\xdd66655f02adc6bc627f7cb5cef6ee2fd0f08fc30909714c696bdc72c47553b5e1f2f07184c87bc62094f4ea134c0de2fcc84c334a0c3c12ad958ce2220ed604
402	1	139	\\x884bc1d4264d572a2b368d3f0bedecc2c179cb31732c4cd57855d9e2c87e4393ea26c20949d96560992f402fac046b687a8f36cc4a900fef2107f80c1864a002
403	1	180	\\x1d2f646c8222fbabb71f216758f9fa3f36aa8852bf99ed232aabd3d30012cbc162b9b7163c2cb3431437a8ebe40548c0bd89ad92d13ae75be330d81b4e2fb80a
404	1	19	\\x7c0e6380ca6d1731f88de25e54f239de7724f37ff242e206c485642ac9b4f6c894ba5147b6f8784d4aa51b1f929cb0b91101ff4b43fb480175ed2c918b193502
405	1	51	\\xae999003a917a0dd422affe49d069a9419f562b8ee27768949e0d9be264c6b0cab164a6ad0c2bb239d66814bf2daa31907eba5a3e767ea161c5dd4008ad99504
406	1	160	\\x548258ec2baeb50e12fa6b26c810da1825e2147c15aecfecc5ea960344f919d4b646fcfd3013e78b157c4776c0013f985256d9018aba870be6c67b14b66c9609
407	1	346	\\x27c3844b6c9f20b10aea5e868de11b2327b6befd4b47a738b88fedfc610564ff3d6c1f9cb0bf91c475aafd98a21d83ddb1b5c6edc3f2f24722fa0885626ef70f
408	1	83	\\xd3bbbec9b86ffc3e25b210c47de30871d1182c7d97407c9e2fe3340336dc4312f9623ac5079ea162076067c3126c0b17385e0f02d259fb64eacd035c8de8f306
409	1	221	\\xf2369ade84a0f0f25f3d24f651d23af25ca05a4ec608d99bd5092e2dadb7f22a195ae85cf5dc2cfdeeb26cc880079b9cc2e6740175a1f86c95a06dbc5a65690d
410	1	6	\\x65d8668c9be7444cc4e4fd64613b130df37e878fd334762b396262ad224300ab004a011cc91210b757e55d55705d7a80020e6513e03a7a9c5e039a518578d80b
411	1	193	\\x254b4238ff290712c89382c1379ff2f12243df5073950ac8eaf54c44a7ad05917dd769d5ce5d2f3bc9893657b22094721bb4174a254f9592581d6a707abc4c07
412	1	198	\\x81070ab4eae5d7c103262c85323fd3ba1135d144d4b901cf278c83c6072685081869ae198ca906642f1d822d19b546cfb4ec27a93d1c5684d47ac96be88d9402
413	1	125	\\x31b591b487f71f9b7cf8efc2becec1ddc1c05de2eb0f96061ebfc3823ce2bf1f85d584b7cb0d064a8d3e94a42147408670d224f7b4632a31cd5563fc56ca4600
414	1	304	\\xe79f386725756f92821083d54be464fbd2cd3eba456b7b36fa0a0a28e63e4bac9fab0dd7f79d8a41af7c2459884a76f120d55c6c6c9ebfabd8f29c76d730eb0c
415	1	128	\\xfc4531684d7050c38c4d074f06aa06cc94bf9b2b6026cf373fe7e07da911e562204d00312b647821a1d951f5b5b4fda36f19e92f56fb04382ad6a36108d6d702
416	1	72	\\x438808da9af8a20fd365123712a39adeb46668cbfceeb422c6359cedae241fbc915710a8b8febfc454d97d8a49660486c2857092e6c3b443e403e819ee89e608
417	1	224	\\xae56843ac3a631d122fcdeeb5d345cf9e9a75b5833dc8efb39702922721f01ef44e218eec7f0b26f7ddbced1ad17e12adf46d3cea39d5fe15c2fa1a5dc442808
418	1	335	\\xac92970e073ddedce5a006c658cdcc69887a7cffe332ad29273c593a1b57d82a78a1929a3289dd11e5ece60868223dc9b2d1b471c1ec2f31539290cecbc9040d
419	1	158	\\x771d2061561fe89beeebc4f9b0d9fae4538e83dd18a4dde0592e45699cd8bc78b6bd6fa6a50fb2d4ae633b536a9d99eb613a0bc46736b5db968e758647e27d05
420	1	268	\\xa9d7266e4b1130e5dff3b0d5b6bc522a578d6aa0832ddb5750fc3647e7e4c610e6187505cf1580cbd6e064d9f91cd0d410caac0f1038dd0b5b01c5c228886a08
421	1	368	\\xaf0ce8d5447930e8cfa8064bc2d9f6a6277eab0f5f7171509323fd827ebaf15e119215b0336be809829a9a34aebe8922b1e322de816e2012543e78f4875dee0a
422	1	155	\\x2f2bc03e7437b75ba49f998e8377d19fb09b96b46ef5a3938d5bf7d878ad66cf1c1ac18e58fe64c47feb2506a08669aaf607de47797798739ef4bd47408c7408
423	1	256	\\xd25f64e96cab7fac9156ee931370f9877b39add82a43a9fc47de16abb0a573fd9b76f365c3e4fbde95f98cc340ecac48e943b1eeb93c7471de2b3f0fb4571e0f
424	1	116	\\x0c90ebc4cdb40485e09158610b651c25af9ea4958b8d57a8d4d6c9dfcbc71db7d83d1ab42200a21c24325a116549b12b0facfe819ec5d04da05bc38b9a7abe0b
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
\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	1638356907000000	1645614507000000	1648033707000000	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	\\xa96df026c9d79a0556d6ed540e8cd4465ff397bef464c3d644f401b3f3c27f4ae4c04a21463d16f75d1275404447c02778884e4370086400c3eca5e4f6d19107
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	http://localhost:8081/
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
1	\\xfa3cbcde17b7eb2464ce6748d3c2a01d554a293a7df671aa6aeec13661e895f0	TESTKUDOS Auditor	http://localhost:8083/	t	1638356914000000
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
1	pbkdf2_sha256$260000$letq19bXadlaHoWSFEuxmy$aXnWIfiCVeHVJf09R8T+FShPtObYSF1Y9gverSkElgQ=	\N	f	Bank				f	t	2021-12-01 12:08:28.4642+01
3	pbkdf2_sha256$260000$mIyB9Rg63QGEGzwm63hrJU$0gMEV5FWd+ho5LVhjBjAT1iFddhQGZIIi4QDGnG9eWk=	\N	f	blog				f	t	2021-12-01 12:08:28.715205+01
4	pbkdf2_sha256$260000$dhgKBUvLIMyqs1ZM6i3Y4U$jxhUoN/crNVaMcOu3N0e0ZvQkiZHeTs39GK7nHfjGgM=	\N	f	Tor				f	t	2021-12-01 12:08:28.833414+01
5	pbkdf2_sha256$260000$esmZPL2jgshidCKiU7hIjo$lDWvIym4IVTUWIW5fnZ3J64elTDo3ZUJo2+0SDdoh7A=	\N	f	GNUnet				f	t	2021-12-01 12:08:28.954942+01
6	pbkdf2_sha256$260000$GU0WblgCUlMmoTTvDQfN3i$Vzb8kXPO+Sb/nLB4n69P7XziHw8iXojyi8UyQnNwW5U=	\N	f	Taler				f	t	2021-12-01 12:08:29.069344+01
7	pbkdf2_sha256$260000$d9QovDC5Pv1rDLCng6JlUw$P75kw0ptunQ2uvcDtuUthrDudyq5YNx2w6fe2lMetYI=	\N	f	FSF				f	t	2021-12-01 12:08:29.186117+01
8	pbkdf2_sha256$260000$TRA2E375xeJJFNp8OX4Q1s$k693S9aD4/KBrX1zjPANqLph0deaZDXjsr78HNsfRsQ=	\N	f	Tutorial				f	t	2021-12-01 12:08:29.300074+01
9	pbkdf2_sha256$260000$4sr1dZ69tJTvCLxVwEhVl4$UEThXQvbobxzE+kwJzKtmzwkIGw+Vk21cQ9iZx9HNcE=	\N	f	Survey				f	t	2021-12-01 12:08:29.415324+01
10	pbkdf2_sha256$260000$g49r7ACpirnYpmc0YsfCTn$3iVVFhIZRQwVk/ORGgotGIu2eeJ4g3cSDpzne2+YgrE=	\N	f	42				f	t	2021-12-01 12:08:29.844984+01
11	pbkdf2_sha256$260000$TDta3lixvnQMagolTOJz7i$8sfprB5ujs0jTCJtjkpGQjJnr13WQ/PtqG9ykmw/k14=	\N	f	43				f	t	2021-12-01 12:08:30.269862+01
2	pbkdf2_sha256$260000$mHdqYFFgOubxxnaoXP6xzM$TgxmAhbGh85neHKSqyF5kt302ItEtFkwTFxmWvykzH0=	\N	f	Exchange				f	t	2021-12-01 12:08:28.587107+01
12	pbkdf2_sha256$260000$qjC5bAJyGnsYNCM9EUGSIi$4bfRzD+DAyCM1bf6fzKxwAy6ASMsu2/SuJi08ybkqWM=	\N	f	testuser-7tgipbkp				f	t	2021-12-01 12:08:37.738719+01
13	pbkdf2_sha256$260000$feG2TTUagptXYjbgMcQ0Uo$j6Cv1dzDkMa0RBGvcgRsbthZ8EtLnlyg5NB5dycoALs=	\N	f	testuser-db6y8s2c				f	t	2021-12-01 12:08:49.946975+01
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

COPY public.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_restrictions, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x029c7a06bcdd58acc2786a8db57b359eabefe6efa729e49fad583b160e6b40b4b1eebbc71eb11424fdb1fe5caf5dbbb29c29bd9c2a8fb5d7bb61cc3ef161f37b	1	0	\\x000000010000000000800003c44f782d431d1f8f2ff3ac13cb6ccdfef2354fe756682ccfdd2715d5f5e15d0b83c8517f16988d0598ee8f144b3692cee91bed2ef7bc690ef13f63e97bd721fe222a053d2434dfc459d971f289b9bfce456d3d60704219bc1b3d1a14c0e91ac0bf72872d2ae1c4ec6e0131c3958d847c5e5324c496ff8747d444bc57741d7f39010001	\\xed8307c77d6b9c176abeac7aeb5cd5641a1526d65aff59ce01a8cfd54dbbef7c1ae81fbea3c7f570476885b6e484705fb5982453a8f59e9284f62538d7717a0e	1658909907000000	1659514707000000	1722586707000000	1817194707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x0200ccb719045dac20c040dbabf40b6be55382692118b14b0493d0ebb849f3040b73a60b722fe2cc7f8da423d3bcc6d9b69722e0eea6679d3007973822a4705e	1	0	\\x000000010000000000800003de45665b1ac54873f32afd45a8c352088df710f8d1b3a571a50f8f00e70d7535d57a9e35592fdf9d0cabfb097449ab33f3882d743894c1c70c691c7a5f546929fadd79d96c66b48171942a84d9e066e37c91390fb894c76bb84f4eb43d538d583f15e0ebb1c21dc1bc3e6ffee08e539a1cfbfa790b6c340089f8a4c6d9576ffd010001	\\x89bdc199a1c309fdf7465b732a19c6db5950e474ca603575fddb3e23a4551369e763b227350aa4fce44e911f24a5e1fa437fb3284f1df052e9e2f88502e45c03	1643797407000000	1644402207000000	1707474207000000	1802082207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
3	\\x07784278bd17ede8568100143d622362c356038aee9cbbe0f79996d70407b43874ab788a56da04c8e37fa630182d1b61f552995de97c23a8c0d0ace0cc8e8b8e	1	0	\\x000000010000000000800003b3cb194ba9669ef19b30bc437548c8cbf5e6a7f2bf66e6230d051c9e6e3f87030e6a336a0252ee068879e685df58b06486edca567ca3cb8fe9339cf78eb2c330ad03f1a6285e47c42ca5c267fec1c0c1410bef95d545166c7389239beabf92894736b1a766ac97fafaf3f470db9cb3b3dea1bba6ad77dd76e94470698c01ad8f010001	\\x31c372a71bbf2b56dc3a6d8aa621e6f81a58b9c498d5b26fc80717aa1ff75fde57dc004dcdea301663404bca256e68786307e15e013a77b79e9d538ca0a4a70a	1657096407000000	1657701207000000	1720773207000000	1815381207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0a5c5a18d4499dc81d5aaee852bee118b405c5670a6c3b5f8497e59bc5c945bb1b05bdf16116ebf79272f0d29a492ac32c25840ebaecd1d3033c12573d62be7e	1	0	\\x000000010000000000800003c5527c21afebeabae11e5629ed15bb62f9e0ff457891fcbb195bcd4edf206c4b8e1811425fd6ad50a7a6f55875337399991e2de18568f1f7c7354498643384dac6d619d17a8c94e9c7d1f85c9e739268ad3e7ea7bee96813df8e102847e04fec7d986c2d2f7631dad0cb708bfbee1bcd82e9661f83cf08273286ec370423c6c3010001	\\x028f25536e5241dd4f42ff588a833a2a1ae8e6ba5969eef0a03bf88c1f702d66c2957a50997db576bab3b95a5937ec6392e5a4f61ada07522cda35970c367804	1648633407000000	1649238207000000	1712310207000000	1806918207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0e10adba8cc4a6b6489b6908363f2696a4fc8d48167f25a0c409046bd93aa47cf7d0681165dbcabee127245eca177a413e51a9c8ea4075779396eb21fecb3596	1	0	\\x000000010000000000800003afcb3b7f4fb0daa23dbea00e265a006c73dd91262b722dfd48831ad28bd9f193158ec17518d3cfcf4c659339cfef8874294819a34cc925c309dc124c601c63453872cec70369cef65fbad24f3d96aa0166c244a4fe8b0e18e0bff5af74139adc0946845dfa6d4db4e57748fa3176f00248cc9865938b346b813a53fca372173b010001	\\x833616613581c8ecaa24706c12b35a00d4fefb560501446a778e533bdbcdfebbd70eb0cc1932a185949b763202fe1a108c0e78d4322c4328b5d6d83d496a3508	1667977407000000	1668582207000000	1731654207000000	1826262207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x10f0ade480faa4c987ebf6517206027e3a311b807b4d3d3070b67d70817417c2d1178ea5c82a07883a0e9722033d8acf780662e753b53a8167fbb5ec8edbdb39	1	0	\\x000000010000000000800003bf4c01faa86becf60793237fe303127eb392485c08ec70ff2197c4544b6386123755e8dc1078cc611d0a5c9112aa22ea770e1c36000425f677bf9b69161a6f919c24a0f345019ba8d906f7d73e9f9924798eb375973ddc29ebb9b29abeba7064bd4c0deb1705d1b8240cbba1fd4194cfa94c23e9424990b7339a79ca1ae940b7010001	\\x2d5755cb60a33c37c59200f4aafe84e5785207b8c2eb7349511d6e2eb2a87f6b053c96902ef094503d9a662892742c2b4a6077b80a73d101d72135473e327d0c	1638961407000000	1639566207000000	1702638207000000	1797246207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x1328c3ef43f0eee88ec7aa178f50c963801d312680652916464fdea809ba7b82408cd67f1f3d43b3256393eea2080721dbfa2483baf3ac9f127de0262b3acdfd	1	0	\\x000000010000000000800003ad8a782dd66375138ed179da36b76159787f8bd1055cd61866fc4dba010da4f28d86392329dd3f9b0c4af9c79243e098dc93d17222b0c905720df3232ec0b0506248438720514b85929657ad4612038d0d0fec0d9faeec01d3668762e5e1a0d83aeacad835b10d5958e6807da57027560109a5ba92989bf2bf384da2e500e80b010001	\\x187700207dee671ddbe110274305cfb77d59903ab7c69bb94a6151bec4cf330ed1c01f84b746407bda35092f143c636631641ab3aeac3abca7121d08c3e16d00	1666163907000000	1666768707000000	1729840707000000	1824448707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x1570e7c259089423fa51781a88835b0310d72ac346de645de6cfb7ac49c4965cd6148f613a7dcd02ef8ecabf0aa25e8a0c170848b646abd5ac217368d1facf1f	1	0	\\x000000010000000000800003d3b92f35df645721f2b2b7c4dda5bcdf32074ed0027a06a71a04113caee9e41ce2f2cfb195b623263d43d6b7a06f7196441d59f9f36a11656a5cab5d16d228abb71a4e78300d3af81bb524607cd1606fad7eed9f892545c3ab4cdad521a7ea75c31f2a2925f4ea08f1837c18b1b588515fa6162e7103bb7ca5910a1d9338288b010001	\\xde4f2ec41b8926fb60fe5f1d23d8cc20d89a0638172ce7af1689e8c7ee36dd427b14bb03d6475989518971d94c15801a56e83ced74715cd92e517a0c36c7cf07	1651655907000000	1652260707000000	1715332707000000	1809940707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x1a84d06a28b27976400964450bf661c29459b09df3e2bdeca1740c8e3f328e66cf51e1452767bf6b1666bd93390a5ba00c35fcd2730ab1d7aa0dec20dcf21c80	1	0	\\x000000010000000000800003ba4b64370aa2becfc56021444f919705dbfbafba2c2ec7f756249072582d149f3903890ecc3ab4cc7ef12d926faf30faefa544b0f71a48e9c1f25fa252079f96fd15620814957d761ec1c23b8cb39610e4a8b66aee6e8dbc5aca5a4cbe9c9d6ced10e551aa02b690590daf73d60943a7f367af7729255c72e4ba6ccb0ef88107010001	\\xb31e6e2f58dff0a1f4c8be94b7f2c40146ed79d5bdb1e6900e6eea83547017f17786584760c0a0bc330eccc5d78d8f120203f2339533520eae7598179d523c07	1649842407000000	1650447207000000	1713519207000000	1808127207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x1cb0cda243429d5aa15bd42db21f079fd6e34089131828a243d11c2128c446c22639d1a9a96da71751c073818ac279c267508a6e87f1406e8b20fa5c1aab1342	1	0	\\x000000010000000000800003b9e8b2f0fbef44aa39ba01b1f36ce55415bcca6481efa4606fa5cdb7682ba8179d3bc81505b217bc1e4829110f43e706021dd40ebbb5afa991c15c19f52cb6b6f5ab117392ebc3aeca99695b2135b083520347d6d6e5e3fbd68e2550473e3d323027214b43df7f680534c3a9e9a6621b97912df3ed1cfab5ace88d85e2b80ac9010001	\\xcf656fbbfd6a083483d8494b1498dbf92a28f5d8c44e9881cb435eb9b820e45f494dafc99b96f8a77ceb9fe9d7e2f56f0a8acf7f78a4b6b7adaf4c35483bda0a	1643797407000000	1644402207000000	1707474207000000	1802082207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1db85ea12280687e27fcafbb13152104bef3ac8c209094e1eb277f7529049f0c7eab7457cac0c0d2d059a6f5a2d3848d1528a5b5dda5b921f51c16bc7e3ad597	1	0	\\x000000010000000000800003b978a37809aae1c16c37fa5ac8bc242edb827dafbd403a530ea3dfc7c9b2312b91e70ffc083d81fc865e1fceeb4087dfd47e68ba5b1d928d2ff6de124afca461b573d665f320a4f22d641ea393ae194f93d175c2e5c3f683d00a53831e26dd4e306ec674e270bc4fc47ad4440dc4ec62ef87a60526a318c933666bff8120850b010001	\\x4294d49a38ed84b67cbc9030e1b6914e9870609aff5d3698753a297622a3100cfa01f024d7dfd27a5e483d4fac4b8791587324ac22b1105a7d91f5ceb634840a	1645610907000000	1646215707000000	1709287707000000	1803895707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x1f9cc3ee27f1d77c2f1662f9ede073090282dd3f7774333a82388f92310bf8fad73e1c8eaa14c738795480a2e05acddd9ea1a930d63785e487681215344b6700	1	0	\\x000000010000000000800003baf685cc634c67cf3a93dd580476be6fb116cfd2c58018d9a2fb6ac6975af23230c55aff714d53cf91648b43dc3c6616d19ea0ea8b105541b44bcb218b760cf9210fd249dc42fc247e21f6c22b584e9034636e9866a4a2d81bf4c254d8ae23adcbae80e990cee609897dc0d1f9c1d5c0886c45dea0326cd01f037859d9fec889010001	\\x2ddb6ee066d758959837fc2e277ecfab7657666a92526eb0a373e46cabd2f9f4b553a992432aca705e0cf2cf7f7018d0618f6d416f72b50ccf59abd54039ba04	1655887407000000	1656492207000000	1719564207000000	1814172207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x20dc47eb80b47c6b37d9df7078c90907cc3ae6089fe9cfe3dab8d5a969f137ed7f7d58e9c03aa293759aca7f5bfaa3229e4ae1871698deee5a0a67859a4fb721	1	0	\\x000000010000000000800003a80b9e1bb5699056cf9f6fc020011b18ee3ece1412a4675173dc453bdd45c1a73d20e5a27bb9c76be741a3027531277e24605c84797901d0399ffb11e1eb1119469935aac4529773d86f9aa6c5a5ad0b70d384caefe8703fd802a38e7feb1f9e3fc2842075eb685c8b5fad7a85eb56b9d01952bde4eb4b25151b103a46faeedd010001	\\xf943d12f1bd9b4d7efc12e2c454ad493097b4a75300e01e805186779790ec2fbcfc95e416cee2ecd69ec9f1c4566e7c75c7e9c94ac491497ecadaa0709693704	1650446907000000	1651051707000000	1714123707000000	1808731707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
14	\\x2274f7316b666ce563edd9b1d9c3da2aea20fae1a69a7335cfa693f4090eb3a2d19971e2581061e4d6d8ed5eec3e9df763e3a3085fb6bc251de8077fe754e68b	1	0	\\x000000010000000000800003ca2faa67e1a43bf12de98b33292a57c5ced81d75d771e776b61ccf6ffba56a0fb9ad9bf8b730d1415033dcd455db2d0ef1710cb81ab8149e21c52d56f414300190d5fc4a41f03fdefb247bd4c6e72cfc087276134365225f8a2e8f60f5241069da3f90c28078f71425bf7909e8eaa95861e97358b7690da320763a9dcadfd821010001	\\xcf1f7db8dd0d5fe53e6e05dfecce2c5437ed0c3add3c74b35c96e155fb0dc7fc739373edb9368efa6c056799a3554a9e53e88991c66eedbc6867a517d5e5ef09	1661327907000000	1661932707000000	1725004707000000	1819612707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x22bce690adbbd4b4a5fe9919e4482a593317341dc37821340147d13b9f10c72a3b43e3edc042388cffc03dbfbc2a015f2880464d76a5777befa0546c7bc854b5	1	0	\\x000000010000000000800003e87f94ad9c14978ba72d4b72a01f0a16012883b3cdfc57a3f87d4b9e7a43aecc3c0ff360de96df0efab9625dba6b4e5d4410bdf182609a5c37c753f9c08a218c985f614ed5acf71d9c8b43bbcb6c31b859a2a04e62ac41b842af11dfad92aede45dc439d6d486d2d79e30f4f36100848770df13f2767b20f36f4db20205821f5010001	\\x6febbd0d4476509582c766a38dfc5c7baee9024d9bb8d07926cc1e9d00a1c3679107518a9aac41cf0dd0883d4d4e14709fc3a831daba7dd7cc5526034399ee05	1654073907000000	1654678707000000	1717750707000000	1812358707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x267883b9f6d24047d10440c442290b71f20ade5d3abed0c9073e1fce98e1222457dace466887385ca5fdb3a1d37c176284ba0790486f1a91c72fe91fff1fd737	1	0	\\x000000010000000000800003a91218506ae211a73992b455f81bc5cdddf868598dae344a796219cafed5815285b70b82ce23af24ba3922a682573af7bb4ba178fc6d3e2a620ad0980e53e037eaacfdebe3e85a573b213bdf0c7df0dc444f3f06bcdf6c0a33c1459f36a15f60a9506763a743d6473b631d6fb3684ad346261aa5abbd1730e426d2a5b071eff3010001	\\xf651a0ee0a15e9eedfcd5743dbe1731ef7490b6cbd82d754a3d2e5ccc73d1e8806921cfae15a388ae87da10b9daa5be65272fc047e5316402fefa075c1646b0d	1641379407000000	1641984207000000	1705056207000000	1799664207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x28d4a3a532603c9293de7b7c7831633032e592286540aa8db82d6fccbbaab92bb9c843ee56584f22f19477d61150aa30a4271386fdf9ae5fd4c428bf5e6949ac	1	0	\\x000000010000000000800003b5d182cb437989bbb137925064aa83be4ed89179bc0c08a17ee1198132bd8e91a51c28c07745364e23ee2a8b42521debd9b2397b09e3c7cee4411dea88ff73f1282e7d4b761512d20bb9e14cdae3ce0624f5268e9734ea344a332fba28ae65d22ace6eb5deed37dafe46d35953ddede92d18f1e38ad22c190decccf2bb972e7f010001	\\x08b503ddb2d544ce8da3b4eb0905d1e74c422966a12ebfcde6b525bd927811d33407b50d4ae316097ba397c037bc6a474ea36e0fccdddc9f533809a6ffe55a0a	1649237907000000	1649842707000000	1712914707000000	1807522707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2920007439af0e3f0df5988a72b44a8ba160a9618887981c9f54a681496c89f732910984ffcde03aa32f456c4e67c3c024e2b2b61706ce843247cf885364ab7a	1	0	\\x000000010000000000800003c047ac777cc432102cf3eb4c75e76a6d14ac255807c7bb913401e4edc951bba358fb0d6158ac5766d1bf550e0763c35e790a2cb5b119f53d94ece2076fab4cf6a5b25f55337bfc7960ac3d4fe716d9ad3b30a86432043b39f049e7211a77f48e0deacdccf2208b8c1377a053177753b97ede1cd02aac71573bb9674f29a6305b010001	\\xd134ea18878912318c93209a0ed195e5349c0f493ac9cda981377870c6eecf996871fd6229595d66f6aea40dd4660b325bab9a38d3f5d9d5b39a935b39aa510d	1648028907000000	1648633707000000	1711705707000000	1806313707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x29506ef959d47bc600708cca837c1e8b255b7af881cf7ad3d98325939ba6bb29d2a31236dfa063f7e97ef387bc2c822216735418803d5b7d0ad85f08fe41da0c	1	0	\\x000000010000000000800003ca2c9934d35c87ee536951a9b7e67aa8e31bb953ef2ff1ebe33de8641a6e144b3bc1329c1cb8a0dfde85f575f07f0536c5b9f4c5e4c96590fc3ff76e3ab9b204784ce828f7a3d31e53eb7815b9c819d376aaba0917373fec056b21088ec1a84c1e7b821092ab4fe7a7a003d286effd9b82a9be7e6add989f76ccf81f1aa678fb010001	\\xe37651b918cceb7b58c84aaafeba867451f1ad89b22a098d530170bf0ab2fdb87e6e6a5a3da8f95d1e35a237f0e18b64101a29f62266579f67ea1d463c8aa70b	1639565907000000	1640170707000000	1703242707000000	1797850707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2d702502804870c04cfdb599b33ad9fbfa607f4ac5e74b13214415bba6a857e1bc6f9baa1c47dee1331f444675bef062bcd865d4395e67a6ab44df235edb5b76	1	0	\\x0000000100000000008000039f2796ec4a822e9be3689526972d2fd608a792aa533917555d2232bea056b5aa23119817915fb2031de5bf73794551bcec5c1a60f4874440e6e149fdf0d1eb0b3dfd1024598faae6eb2428c1f828ea460754613ede2ac60ec36ce5756477e565bfb1a116058987772d6999eaa1e3e2e4d4d45f111d6d335149c127733e463673010001	\\x35e3df148786cacdec7cceb400f4ac0c87dad065b52e239f6c93ba2356c01795d70c8173660336b2e109a6e6846cfd7110b8189438f13871ff37cbf8a4ef0f00	1667977407000000	1668582207000000	1731654207000000	1826262207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x2eb4d2c63176b458850cc47286bddc63d2f6a899112df92beecb5cbb35ca7925d2d155777dd51c2a33d85d3b9c21e66b19e1fa9bd91dfb08c4975383983895ac	1	0	\\x000000010000000000800003e04c8b61f88d41107f81cac79e50b4682dbcbd84da8f09fc4ae718912e62ff9af104bbbb6bef281e81fb6a974faf8e4c82bd17ad20f9bca02545e0e45b10840447361bdb3a7743b7f8512e8902899dbe5d737f537325d51fdd96a858d785816b1bd86d0b0935460caf7a33800ae447877393d7edc60a8e922ab6533d0c10d177010001	\\xd67773d4ead4a937ae7880e2dd0bb27a98b435b41b0343e017f2d372bb0d454dafcb198631757753378ec218e91ab35dcfe069ae46b33604ee2c16f56000d506	1640774907000000	1641379707000000	1704451707000000	1799059707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x31f8bd40f559ee4ff722a7d9f548135993223db9bf1594ececb9e2dc1174eb70472f6a5f1f6616f0ef265a3e44c2a9dc77ef22c8f8f6fa099b4332c46692c4ff	1	0	\\x000000010000000000800003e84fdb034945a3d421a7cce922dc22f563a2ec7539b9335b7428984a01bcf7d083b863f3b9da9440859873a42cb70d68babcf4d83a7844e23da73c854d7414970710efb58f7cdbd1bc08196df9a7972d1a9369f5b16345f63fb5018bf501fe205f241bccdbf28e8b7b62be875fd9f9b135b7b10e7461a4bdfdca3ae018c535db010001	\\x44747292f7a16c85d182290f267d28a48dba1623e99f4dc8c5cb627e878e67e6952b70799439cb368c45069462a296f2a0ff3b6746d2448bfb5704f96cd2e60f	1667977407000000	1668582207000000	1731654207000000	1826262207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x34482eb9de9088a0ba2beec0911755cbf0ce43b7663fd15355197d49bfaac4126a7de1fb41cee390f44b464441518355a20624e39bc5a3a3fca18fcb73c7bf83	1	0	\\x000000010000000000800003b2f6fdddcf853b7ed6b92bce9817c637827757003822ce61db1210f2021fd5176a2fd88f9f22a06653fe7dc61e6dd3ea868be3e45144134a56d0a75229b0547859d98e5d52073db8fdbda3530a0bb000b52594824673494263d4b141209d455faabe02a41cfb88604d429ea884cba761eb904fb1e35d6be25ed4dcd03ece48ed010001	\\xb2585ad3b478e3796444f44c9335e88e8d3cf66618280c849ccf1841a11ff7f26d72c18c5610459d659fa3da4dde1ee77ee7184b15c55ca9cccbdc7b43df1801	1666163907000000	1666768707000000	1729840707000000	1824448707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x3590346b4c2dcbdb43535e39f92b61a5535a59a786bc0c64d4c8cd874a77e200de5f9e1276a69e5d2a52a983c6263e4f88dc10a375aabd0c73901338e06b2aff	1	0	\\x000000010000000000800003b3cad9157576c3c6b835c4ce2421150c489ac1b63b220e7c675c2da7fe17bcb038df428fc9f0bc86e3ebf1443b14bfa50856b7f10ff1f485fe5342c4fc6fa51140861f3a4131156f0d799094ec3983dbd21ee1737687fbc960103e3709eb7e70f39054cd323c9de8a0150c835180c128fe51764b52b3043c2ad7bc4e0f2ef039010001	\\x34478ed0fef6e60fd64241243a048669be7dffb4d555b9afcf05ac4379b5b48c6e0255c37f03b32f94bee853062b47f8544768e07ae01c5fb2105adab2556a06	1643797407000000	1644402207000000	1707474207000000	1802082207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
25	\\x37a01e2b494e11396eb2b9c3d103e9f13bf9255c9d78f673ed430737770e2e857190abc9f8993a8d62553e2fe6b9c4f66d0eb59e9fa3fd93f1f21400b801a90f	1	0	\\x000000010000000000800003b47daa07a7c053dd6b5178a39b46544bf289c9e226f1f62e7718ab6647d98d3597165144ea9a8af64ac57d04cbc818ad67c497193bbc5b88e11d64dd5fbeab115a4de65a98372201f014a71be5397885a76ab3475b6f64e9e206365b5119fa5dddeb1d01e3fd40d5ba7afec206831ab6b26b97960874b093af26e9011505b717010001	\\x08ae6483857f11add615035e48b3e7d7d8cbc3af60bfbb9580152a1a8a98ade8e06e720973b6344f71282d6e3f6b84442efcb2925226c6834cd2f2ae36e75807	1648633407000000	1649238207000000	1712310207000000	1806918207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x39a43c3ba43138b0eb46005721d6a301fe6abac764cbe2c518c470056e66c72f67ba6c10ba30c413a15c1573c4f8f596af68a05afd25390338bf771355f8f713	1	0	\\x000000010000000000800003ed178667d0b8e45c3aaad1b8b0b1b4d80b83ae78b18ca589fe0d57c57c7edd34feeb8668c8e315852a512714a17eedf247774c0098ebd458af6b62242c252dae109691f5d1f3d1147259743dab0597a081b283b0e724bf1368541eee760fbf9c8d81e07e560c5206380e9e7298779992f1cc1b945819aa44af43f66f03882dbb010001	\\xb630be56e269bd5cd1fa564fb27873d6f7d0bcb04b3610aed69862c5a52e6ae7f8e0ac7b491a2b579021e76577aa9f251c6222252755efa95250ea93c86acc0b	1655887407000000	1656492207000000	1719564207000000	1814172207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x3974d3a3e1fa85f79469313da20cb4e9e6b7c3c77cb462c4b07b1f196df80133fe71403dbd222bee832a27283da418144a36fc9c286d3619c780bd06e597e44a	1	0	\\x000000010000000000800003e80b07843edfdce76e7b0a6c1995c1b99e2955151f41e9dae1a2fd61cfc624545d5864779b4862aaebad8c42435f229e5c46257ffcdda381b60c19c90396de00fdc76a109c7880ece73e1d9d7161dd47ed7b33e2be46a481b35a2996a8d13b8d5539a3f1aa3e13a3b37eeac97c01e56cc6c30785767aa411581ff2dda43b0581010001	\\xc2fd01512536eb325e7b42665f38c5623d3915a241a6a87bf96b7fb159e8a65afe0b21a3b3d48ce6a0ec695b85c278381dffab8cace0a3a286d114b8b472ed0d	1644401907000000	1645006707000000	1708078707000000	1802686707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x3ce896519d7a46698b8095ccd51c43a29e0cafd17e56bc667ed9ebb74d0f8659fef5dc82b9ea0a78a57f0c5e1a7252172ac3f9ee3af734d781811d8f20a9bcce	1	0	\\x000000010000000000800003c730b00ca5e63f5d68dce9a4de37fd3b2d27f95c021f44330c6ce8af7783612274be46ea7efa6a59d22d1c8826dfedec357f32c73f360ea56fd3773dbc39262c0a57551929457426c66543f8b0d71994072e1f95d9ae82202dfb769ec90e52ba702c880f427b79a92ac773a60aa9a58999ff696f12aa3939a90bf429e4e0901b010001	\\x61d628af1c1f2252854ca7ca37cbd855700ee5f1cf2b10a577d684ac682b8205000ce68c4a11a4420dfeee9a44485135dbe0917d3475a2e6e57cbf11f22ef30f	1652864907000000	1653469707000000	1716541707000000	1811149707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x3e1ca6a3b421ae8dd9873131180f57def90c7bbb2f629825de2618ca6508afab97d76eb04a989cf411e5ca1001025d5e526fa4ee5db4134c42d9f263bded398c	1	0	\\x000000010000000000800003c841869535d3b9cce6aa48ac165f9ba44e16d23ee57c6747e67d614a497b032d63922b6b510c7da8e398242a6ef2dc62c56b04481045f59f94940048785579e76e0cc461f459b3b6878080e3c9b610f7f555681224a8038cff01eb332430b2d95ad19ef01bae8eb55a97054bf990bd60161393b59eed7fa3bb191f3ab2ce9055010001	\\x5d4f8b8a147940b53beee4205926aa513f507fe0dcda2007978ef2a799e7c2daf07e2f5c95b6ce27e9d552b655dcc51a5098499e84fe5a590a82dba6648fe108	1651051407000000	1651656207000000	1714728207000000	1809336207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
30	\\x41e88c910bd773d1be374c55c953b2529b0eecd1cd43d5a9b7421e684f73acba60a6ce8b75622e40f397ad1d2e15fadda8a60b4a34a58a84abf1e86c8b50ec97	1	0	\\x000000010000000000800003e7f6cd72617f9593484bc87d53a9cbed306997325c1e4a54ee1a3af099f7334e943bcc5842e597fe9040ccf3437aab1bab3afbb79ca9c9dd066db7e4ad44ffa5b9e97c8d3ea789172e0585469e1424753695c97fee14a0d408141bce54f4bef961d6e2465f52336e55119c7582ae6da8050f34a9a2e4f4e74502985c9682a321010001	\\x29478434ec71c1e615bdc95e2321bc2383ad79cf1827e7aa96c158dc764ce6e4269e811f7bf066d89a1f7af182055bd6c32925e1b3efd874d7760ab59a3ced04	1651655907000000	1652260707000000	1715332707000000	1809940707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x48000068bd33a418f8950f07d8a623688a6c942e87b5c772a259cf528be8072ba69d0203ba55ae199ad37aa4b0fd3f2a63a243e8b7168a5a934f477c843373ce	1	0	\\x000000010000000000800003c9da5496622af38251582cfbee963c5bdfbff8d5eb3ec75d804a48bf000f8cb9ca5470357d6e3f20dcfe429361e4b992e2dccdca6aea561289f2df317ab212db1fa1338d8823b551bdf21418bf9f7b3fc3a2de28448c87c423da86f132c95ac15bbf88dbe47f2cef504d97e94d2c1acc6e777345903dffb672fba65c8bd0261b010001	\\x09181ab859a3ac4352b35cdcc2d96502ea0dcb397830c24a1d3c00b228602142d81a0ae41a07f4b65be9cf7036fdd353950adc25b3e9cc35d6d61da8c4f8ef0b	1653469407000000	1654074207000000	1717146207000000	1811754207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x4b1c57e6683eb20e322a75242fccc3055bd200e25c572f99ed24d9de0101389f06610dc2afdedf041213b7a98aef61a642d4bf817b8a0bb52b6d6b7057a6d8c4	1	0	\\x000000010000000000800003c6eebc95720ba253b9b8528837949d3ff7608da2746bb0901d50cc86acc5ede4d4c2a4589ccb72d65013e5053401f3f441ddf27b508f3a7ad1d3d40248ed193de8f0470d0c2240bae799010fe39f64c46656436ae3208f5ec78f1f63be4855cf427466e1cd98e485d611eb4a8ca7ce10867d8e24f421f3d028f8f51140482a0d010001	\\x1108521e129118e8b32fdb52d4a3a7ceeca4ec92afab1d00f822c030b38548a8c712544c03f21b56abb5796dce3250870a3a4a7c7bbc98d0ca822a90b95eea0e	1652864907000000	1653469707000000	1716541707000000	1811149707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x4c30862c37d3cd15f08656d6cdbec3e22d968bfdd8edee1d907cdeeebecc19302db78690c092fbb998a254ffd558217ec90b572f0451dbaf9ed6fe4e0f5452d0	1	0	\\x000000010000000000800003d6166c8071459318b67c8d7c889629f7f920a1f4a7b9d10ba0830de9887f0c831ba4822766f79c9255b523c92b5e720103d76ab7d43ac13f9d5f035935f5f1d7955fb0bc490109e88cb614ce045a0d5d9be94459d3fd610f2950af05e982230eb036ccf3ea9e9cbb49c511a49570f9621a6aae470ec2360ae961fdba3f88b269010001	\\x18615e0e4dbae57131a947aedb2b0f678d808f4db92aff18447f9e91f2b2dc7b050c5c863dc529ef9a7b67a80d8775e44747a3e2fcbe4535e5e1803087464d0b	1649842407000000	1650447207000000	1713519207000000	1808127207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x4e7c98904a47a8eed1b93905d110c38a55f6e96dd43936716a9d45fad810c5a6cfa77ceb9c5016ff2d4006f03f3b5721b7e82da3600c94b8a11f9ab57f767719	1	0	\\x000000010000000000800003bbf649a2e43236d1f489ec1de0a467c7b7aa37689023f29cf6c39feffced77c37849240e582ba3ef0743b83ae01ad3057e443264c497ee32d4672973db0419e0022a364680c4d978f6172c38f86c9f2e6749aec8cf3e1d564fc8086153e2472edc31ef164cb61dbbeee4299cbc207a17604c239ffb49ac427ed9f73db6abedab010001	\\xc9046d4adb53ef5ac8e90313f2718ce1edcca65e1417930da9be05c5a3450fadcc6154c57017cb6f471570b4dc3861bb058dccd8ffca04a64a508f7c7a3b5b0d	1669186407000000	1669791207000000	1732863207000000	1827471207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5198952f0eb58f7ee44cbf8d2661c7b360eec6360b35280b48a884f502afef90b952958502ac64d9d28c49bc93722712ebc6f3197b97e744be61dc4fee3dda92	1	0	\\x000000010000000000800003c6961da18ea0e839d675bed810241612884568b7e49f343110dab0d7b201908bfb7751a000907e6adbc519019abbed6487abc1b7ed96239d2a4929f40d5f467b396f09231458e18d9f3742d1608315928d3e548f34a2e8aa1374d62cbf1e6a850ae0d1db7184c0547170d5d5eed0394a89fa2d2da83f212ed5b215665bc932ff010001	\\x7605270fe13299a31f6aa881af8860ca558f2ee393d932050abb81e9784d03183c77a7d063cb8e6a25fafd0a1682904f09078dcbdfc2bf8203d3f0f8b03d5f0c	1655887407000000	1656492207000000	1719564207000000	1814172207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x513c47a9f58587e0e7a070e9c2c5d39cfa2e0cb0e569341c237a7fb967be89aa80f476f275eb849d11dec5de43bff74e94e68f097c70fbbb4c7441128b6487f4	1	0	\\x000000010000000000800003bfae1ebc13339737fbc047f2b8a7bcfa1ce14ed587ec0b15d99cad5d730e1b7b8652d5d50a1f8d9098f1372de0dd58c20961ab50a186d1bc8ef133a1ea8ea15482fb6187b018abbf62147b1ed61bc9d2f2d3003125e59eba7d3a57d1866ccd9397a0caefa2299775dfd8cc31de600aa88fdb8b4b212f9bf0c5e34d325f187f77010001	\\x8a44c1a588d7d7647c1bfa07be77291be3be607256600b44d8710a4eeaeef1b7163705b4598c5550ea411bbf0a11b331e182b450937c9975ccdd96475ec25406	1640170407000000	1640775207000000	1703847207000000	1798455207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x529c21b4509c93676bf3a16500fcb8503a70a9be1cce9ca0655f22ec21c9175be29c797da64d4aabf79ae7d5051672d69c3ad8352400c1b75f0e7adb3d05c7fc	1	0	\\x0000000100000000008000039c6cc81207e410a107986fc0c44a32f13b5c296d87f17f824d6cb62712e694cac93d86bf2f18e23ba60aaba6faff413a0b44f6b37be571e11d279966f654274ca98a1a3b329d2794961f9cad7781a0c752892e09dfd469c2eb85e5252793ff16093acee52ef9b9fcdfd4479d4f2fa4c00a3f6e15713242341aaf6ad4dcaac067010001	\\xa68e52b2e7b5e7a9c3d23816fdc4f00e3de7bf41e57ca51c3c621e2c835dbc3f11c7d6d6fa699e25e304bde2131c9c3a0a959cedaa19c2ed872b1eff43dd030b	1655282907000000	1655887707000000	1718959707000000	1813567707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
38	\\x58f8e5de818b09ebdb9af715addb97dad0d528438c0d19136cde2591096456775cc76fb6a1fd8ddd0ad38e24865faf3f3ddc6ff99106d8ff3c2482d217eabb05	1	0	\\x000000010000000000800003d9ba0c5b68cbe17554d8f5f55ed1696ba527a2eb3b82dd2db883050b0330b17b30bbca816618166a442fa483ba4c5707d071165ce28e508e0b7d322f1c3424773fcd13aec42181894dbf2dd56877f07374895866173da420085970f650830ceb1f142f50fee20fe5f56e25b8ee4027b21d7dac91434e3465fa7c5e968caedfb3010001	\\x8081506f731aba9c7deeaae5ca028a021314c1b4344f5fafd0eaec0bb429c2e24682233e4cd121e0fb6818e57a03b0f15540c435a6b41237b0795b1526c2dc0f	1649842407000000	1650447207000000	1713519207000000	1808127207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x59f0988c218e10395ebba3b1757d47c22858a620aa237f1fb0b9b32bccd8630b9c5e18080a0fde7d823c1bd180c3c412e273d533af2ca7403420f314c0a907e2	1	0	\\x000000010000000000800003ad97a1098ca06e3800173d316ec01aac72bbb3fac1c6d81032fad7af9bfe459f88c83c182e9bded69a77fec74ee69c6ec59115e2785bc3d17811d5d89b8b0c0d16a9f4453c6c54df5c8430371eae997929899fa29aeb6016219832c0d2fe6ce587ab3b95cb015ee8ed7b95392210107e79c4c23c7177ad42f2f944b454cf2af1010001	\\x40a8e1e8567d823f9c5cf3176759456ab745e779c5baf2d23baf83c0b9882d951491156dc7a9a712ef4a64cbfdcd533c7e9c72f2c19fbe4dc5dc71d572bde809	1669186407000000	1669791207000000	1732863207000000	1827471207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x5ad8bd75a53c0946f6d0fc693c501b747c44dd8f0352e9a3f7cc111660bb11d4a28323724dc644e0426eb41e148cc3e8ae32ccba00b261aee24ea7f417da858a	1	0	\\x000000010000000000800003abd024d9c74dd282ea50c116647e50e0759ccf0fecfbdf928f82d37c6a6f14f2ac40ab2ad3257395b59a346c5b4b3a380ad3b35a52c2edf0c871dbb5ca1e96505e05f211fb7a2f4b15e43f99a077405dd9aa938a5ba7946f3a0283e31c17647bd0b6108129e9d6f7fb86f051fc7ea66c9ee63c20ef824828d0243397b4f3400d010001	\\xb2845f7f4483575510663394a590ec27aac74b1c61814eb9d9873ccfe25a09ceb2772903da6cfa834fe9bec83f98f1c7f2a6f46362fb67f1fb40338c8b6a8407	1646215407000000	1646820207000000	1709892207000000	1804500207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x5ec892975b6818431f1136a04fb398161ba3e7dc68a62bb609edb53dbcf7ed237c78a6a12aa06e2003331f0654acddb9faf9210a32d28a83ea3b0242665d8f6c	1	0	\\x000000010000000000800003bff538b6039f641ee26cd984237388a70468aae4aa89b373da7bd6bd78dca4ac73b0ff590b71cadfd7e9172d249f25e6ed3c42848d33209b25ad427edcc560558e25c9c22a90e86c55983f9c2749bb542f4b6c90c64aede40a64ba12dd1beb503902dabe2525f6a8c2330d549d90ae2cce4b2b4c1a6802e9a3982da83cf2d8e5010001	\\xfb08bae3b94d566b2cc48f529a7d334b9d1c4bf0caea3f08c754b68c13b7ea88155171fb7de4d0bc487aa8603066f340ae437e20937e6c12277784ad3eff5f0b	1656491907000000	1657096707000000	1720168707000000	1814776707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x5e9c4602884a80ddb6da2752e479b5b445008225ef8a1fda5a41bac1063ee4bcedbd76d88de648096f399b31f8aedfc893a2ae705438d8a70bd8657ea7472298	1	0	\\x000000010000000000800003bc65083451c00ae15586c36b24b7122b60f1574a9d94d7c10ba5de8dfe36a8eccd66172b3101c0f0fdd91f7794f067de46907df0516d12bb25c908dabf8a7b132e2878d40392de2bd073ad273fd9968dabd7bbe166e975cb71ff91d8b83e4be1005f6ff2ed4a02e5a4220c84c5c228875d5f4fcb838d21dd9eb7f7fe964e87b9010001	\\x920dd848a42bd62897e8ad31b0558fc02cb6293ce719c2e7294f78321c6b6cf9a1c9d7624d2f02ecd17e6015b059c0df1457fb1c238f89c706d6cb34c9975a0a	1646819907000000	1647424707000000	1710496707000000	1805104707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x62009a52e5f56163bd4a2d8d4743bb14f078b68d6883ba3498b568a34ab2dfe2c708aa1a8e7c0ceb45d992286b6e2fa3eafc786952a3a49872d405e7af22f12b	1	0	\\x000000010000000000800003b1f0a78c36f8145849444f64f30b6d0cbcc30cca6b9571c8bc114718d7fba2eec31fdf7e64905a81f5ffecc5737ccf9d53a70f53b7df6da033c3c8d2374740ad18f0d8d1ab655161df56a52fc8850e8af04bbca862fbcf3a9a9c304f09f50485207facfae44cdf379e405e3e2bd99f5c368727eb736716f02bbe8d7f2cb4fdab010001	\\x938e11bf19730ba0c32bf2142224660fd9df93423e4996d0983c7b63a676f8099314bf3b4eb458aa91d11b37406c73401a37bfb6e8747c011ec47c5eb8425e0c	1666768407000000	1667373207000000	1730445207000000	1825053207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x62148e2ece40c42428d8e9a03e8c2573979609dfba8d6c5632021bf848a17b1d1a20b4b5811e9642b5ba1eba585e63491e3dee45caeb36fe2b8f7723dfc2902f	1	0	\\x000000010000000000800003c982e71ebe111db4de1912595bfb9aa76146b9aed2045f1b5b0ed87fec92192dce493cdc4e0613908b347d180bf6312430fdda38ff603d3a16d6e1ffa0267e7ca7ac43806e3e317a4710f1a363f653fa961c566d4dea804adba45c327ac8bf0f1b240c9c02e806f0e8a20eda6f3ef75cb0caecdb3cfc968a531eb423cfc72fd9010001	\\xdaf2d3f185f23f3ebbe4024b9acb175273d4003bb32d9520f12b8d3e6294087804026529a72b9e3429c4f0bd3b38f23a176de51b9bb97c59cd5f9f435fd0a606	1665559407000000	1666164207000000	1729236207000000	1823844207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x66b4170427de16272fdc61cfda2abd6b02318fcbb19111cf72fc73fdc6b27f16289c9ca701bc237c6c38c5da4aa4cfed9c0598b1acfea5ca26c8e644a48ae0e3	1	0	\\x000000010000000000800003c2df7d3f92037690881fdb466f7c784aec577b98dce9c57489ab00323727b6590a186f41830bb38377503c42275fb4df8e2f358ef9a8607eef4b22f1d30ad20c54a424a190a5273d30631b0054ab97be4d1f0d257f533d25732d50c85b0b26a9a72db1b94eb55758203b8b02812b6dce042d893b3990862940917151cef0c2f1010001	\\xf3f0fb1d02b032f33d3099af4b22a9eaf4b6361fdd13fd956f285a20bd45357c4478afae8ec9badf216f923686f98ecca2a6939b07a60a704fd45b51c9d45607	1644401907000000	1645006707000000	1708078707000000	1802686707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x69d437490c9eefa8e84074bcd4c28af62a3c88e5661f05bf105c0831e358fcbec0ba1a5286140b774b62e110c977ea1b79bdff772ae15c006b2ab69add7ea641	1	0	\\x000000010000000000800003e00e1f567a7d515539574b5dd3c24a2b500ec4aaddd9e9cdcfd9b47529d5c0bcf7096b0b5e69af0759e13c9ab9048652016c05bee54d6f317fca35d67988d7370bb92ef3d43d032386bbb8354e9f8fa870cef00abe4015f215fb75d4bcf6e0d924ccdd6ba92f0839467e3e45ade7b94e7e8da71c77a9a35423a20775737d4fed010001	\\x4ec130e57dfca647dac65e076f3f2b6923c474c44c2efdb78baf5cdc4b059841bd3c765bb56d84aae55509a3e27c1228555647697a123b5df5693c471d98440c	1669790907000000	1670395707000000	1733467707000000	1828075707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x6a00bd5c69a7efce4aae1ad541a84e57acefd65832be417dca496e2e008c89d7ca439e56a94767dac14fc4464d13f988df4e03722ee7166643b5990c8128e1d5	1	0	\\x000000010000000000800003b20ddf8a9f42eb0e54bd6bde57c793fd98ccb65501049294ceab0f73788a98f8c27ccf1d5973319a8b7171cd237e28d553bc426c9ec648b6f523f8778fa71a1480009412ca3c9df4ede46e75741da42870cf018a482db1106e53f90b210143970e48400d4338cad9b00175c5254074f90d5988fe00f7089a6a1a93ef1a79ab19010001	\\x78bbc0a1823b57d4a5832da57ec4c075c54e6768b8c93e213f2664cd42c6e1937b0dbf2aad67191c7a723d4914faf9d8703c031cd5795b7e3ec0671e1297f20b	1641983907000000	1642588707000000	1705660707000000	1800268707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x6a34262938beaaa738f26be5702dabee52788a6f86512ef3268b6db0277023a2cf8ca5b4d1816538f07a629d4aed6a5bef9b2ce5931b4c09f49b817cd59d5b01	1	0	\\x000000010000000000800003c7ac508dedbc74038a2537cccc381ea249fabd967edf597569be049bc95095fdcc368ae6c2e43819f9517755ec3fe8a7186a5c0a50e049cdb2058ea7274f6ee2ef5f8c71d550341a1d499905f682f4daaf2c23267199f654d4ca47961c3db049a0a40fb1dc9ef6217d99d3451d50ebef8b8c5da4555786b64f86bdba43c19e0d010001	\\x36e94bd301ce5250b8f8daaef52c5428126174cfac290a545104a7edf81b732a26ef7e5baeefdd4b6482ab313e326071c3dbba2ede41d51e29a4bf91f770fc04	1655282907000000	1655887707000000	1718959707000000	1813567707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x6bd4cb0acb6db03952b2709ea63364f7d714b5115f071665d735b87502ccf558bf2ac3cb5850499c922ca182206c20fdc3668de99d1ed7fbbad313750bf19267	1	0	\\x000000010000000000800003f13b26b0d6601524d63cb1a2bedd5fae00318b7a7502e7ce8ba32010f3c1c1f4afe9228d2495a975ee2c63dd4b662d641f4f4682559855c12b27e494360a23bc2aebbc7be5968b2e876037d3ff27e945e0177d4485bf1a38af93a966ba4919c7b276815ed987bd51d80f6299a5c08529012e5706a99cab001586e3a6a0cd9731010001	\\x5cb86c174d7c0b38f434cfc10bdfb1854a11d2ab7c6299829571940620e6913eb7149099d937d46701f3fb4a6c51a7dd2e046c1492522ce2a8ad5c995f775807	1665559407000000	1666164207000000	1729236207000000	1823844207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x71d095c4a52f9f1e148117cc20682892d8f962b9326cc2c2dd0f653925a2f213fe6b8805889911e6b12a2e039923c9d7215dddb2b114ec8b5951aae3b9242163	1	0	\\x000000010000000000800003b48f252f67e783a22acda50133d2076188fcbed66c86e419cad75d3e37d9bee2cc9199183300a301ca0a266119f1beccbbc47342ff635bf1dd3ce7ba81f8eae49dfb745de2b6e7677d13a5b21099ddaaad7dfa6aae9faaae8088483fbc3e4fcd8a077389fa23baa61813ab142915b4afa24acb20b85a30581780f2e465648469010001	\\x81231e2fc3a329a1a68ac604c99b82eae2da9fc03e2e9097bd5f4944cd8c02205df53a7a0aafb8d4ffb15802672f13091cb3d502c465f9f8ab7c96bbf3099407	1658909907000000	1659514707000000	1722586707000000	1817194707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
51	\\x71346595b726a62b10d89dc3436eed88f64eca47da9549ed7ccaa8af982be78d0562c8d0141cacb5304cf87d387324bb880fce967ef94049d9376cc5e8167f36	1	0	\\x000000010000000000800003d8584ba0bc3aab295f7cd29c8b839a9d4f3256c314ad64871e5936deaaf35ffa3923cfdca62b406c75b2a20d18bc32e490ce6e705fb5ce9faae043cdba62ef29efb8f763e89c3f6ef9b680391118574616dbf860074a094a2e56c64f5d3f11e106e6a047362c0d86fca88e6f163b5c3f019f9697e1687c561f7bf67d1adf1fdb010001	\\xf46f81cd33d76d9638715c20d0e4fc6f6355a1fe0db17d2671327afe8dee888f0a96001c1e60ee6fd58d397c0fbbb49dc7bfe0135bf3b5e6000326818490b108	1639565907000000	1640170707000000	1703242707000000	1797850707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x748c65c29d1b1258b94dd44ffba9e9cddf854fdc1a362fd67caa691736c74c21d39c39d3088c76ba379899ddf99ca8c8bc84fb0673c1afe208270abd6cb2bf91	1	0	\\x000000010000000000800003f2f108eb97caf46df17f047a6b8a74e984cabf2c039d828f7268d3c906d746fd911ecc9e763a2147335a2b63591869219fb7bbbbe5f5fb991b02b8396fa0ffe9053cc0398927299e1661bdc26c703f598ccad6f31c641343dc7fb6277db09cbe05cf049fdcca9426e4880498d32cb3d7634741d2ed3208cb6a4efc543ed47fe5010001	\\x3950aa73fdc49541701840c677fffa211a157d3a33fd6e3603c6d052942002c08a598ba710407a108bc16fdbdfd40f679ec97f8fb50eff4311d7a0d3564a0f0c	1661932407000000	1662537207000000	1725609207000000	1820217207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x74b00dca32e02bc9fe0961d9efd26bb78b0ddd9a4a23033a01c2cfb1d2009bac18858f7d8efe8701e95d6844d10198fd3648de93ca5f560dc53d5519d76b15ff	1	0	\\x000000010000000000800003cf0daa048886a3c5fd427c54a036a612cf90e95ee87562ced14c385afa56265a20f936bee723504b092aa8b5bd7a3125f35f0c6ac5184f5fda18322c3817b150cac75b03fd92a5e6993ae15002aec550cbd2b7ee13e63f008f02f1239ef76891c5e9eab1584df4635b78d6faf2638e25d4ab3263e2f184bf07d855ebdf4ce051010001	\\x2aafca874a6ff3a51dc452524a756cb8b235ef89baf3e53dccf423f6f2dd1cf009615d7093a720cbf029d4ec3c2e71a8b774c2a82bf8aa030bf18dbf4d9bd907	1643192907000000	1643797707000000	1706869707000000	1801477707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
54	\\x7670c1387d121cdca0c983994f52650aeab558c77b52ca34f74b2ab27b90afbae87f791e8340444900698ee9599205a920609a4123bd0739978a716aa01de511	1	0	\\x0000000100000000008000039305843d1e07dc5eb68d69aab96f0462e1cb87295df6dde1ca13261dff7ab8c2588f3b5626e9b8c6aa1600f77a2c79e89372fdfd1b9e7f2e2aa7ce9dc5add92cde3f179eca52eacd7e6d42e4264cb600c15f6a3e52c81d719de86a2aa70b5069f863d1babf0f6ce9e84cdd95999579b4822149d9752839abd626240afd271b4b010001	\\x5922d28b8ae9d03aa1d62b5df04639fcb89515196e0743b5794fdbc261aabdd9c0a2ac6b78b5b5ed09cf30945d38356771742845381b1958355e76f8d94f0501	1645006407000000	1645611207000000	1708683207000000	1803291207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x76e8c4f0441f13c785f0ea7429b481d926fae0d06bb644fea78a1a92d0dd97beb438e66c8205e32dd30f8a1347241ea2153e51b6cb1cfa9ac6939b6e17764f43	1	0	\\x000000010000000000800003b36a05d1080015a4e0104eb18ee1e572936d46695218781d28709be85801241f3aad0cebd16bfd51a20917d1e017ba2e34a2033eb160950be5c5120f501cd1a535173eeae937b9c6c80c2fd761dc7745a9a5b96c9c2287e585f8d569bfc58ea9cfaab6d071af3e340e18eb4622ef514ff7f2a0769c384174ca19ceb28a62a61d010001	\\x78496816410a61ada88cac6a1c16591abe6881d93d27b00655db7ac9412e186b8e7a8a93c4e9c9e0a60cbea73f2d1463df7d7443210bea59f5b226b33cef1b08	1665559407000000	1666164207000000	1729236207000000	1823844207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x78b41c2347a620e97040bdfe45a0f6b3ebf222b9e485dc880468679d7f172c8490e54389fd96c69605d16c7fd18b4140f7cb5f5450611bacbbd2f1187aceb8e7	1	0	\\x000000010000000000800003ba22bfac159267d3f7bad306d3f4bdb447c06ed310c30068102680a105bf290fcff03985267c5b7794bbaee52ef39a09cc404f02f6cc9eec15f7babe3aa98981ea3bea1c3a3c4704a2d905bfab4d052301f0dc72a53fd8699f90da6ad63b6a93a44f3b8e4d6ea5708daff9da6a4e0760fcba81bf60060ce1285ec05d0d48bba3010001	\\x67d8108f75f7262082db3da3e5893f2fdd0ec3488f78ec0dadc10d9be9c3234dcccceb8ffff621955de29824b3b5e4fa8e150cb34bd97de40cedc2d33ba30d09	1654073907000000	1654678707000000	1717750707000000	1812358707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x7920681d220de67765ce401b6aaca24edcee13af9b7f7304c219ab2ce93e82437b7194ffdb15a2473f65e5b52c3cbeace9d29391d945a0e2506ecc971ff5563d	1	0	\\x000000010000000000800003b03dbb57b966cdf478cfd278c2c5a3b921dd7fc0baa7112b19a1968272fe72092f049036110b637fe7a0bee93a5f13851356dc08d1b238bdad468b624eb1b2164110c5daa3a5e9c09757a50d5d85923c821c9bbca1c7c70098e61bc624cf8e6084ee2a36bbe7ab45eff3e8cf1655be631155bce5b795d0eb7f9e32c33b10d3ed010001	\\xa4067152385013a8c1bb4638c320d741f8958f9771446595d922421ed3516575bd41de5f681b258946914ba15351f7f2899ba2be6e2a92dbf3a33bfcd929e70b	1648028907000000	1648633707000000	1711705707000000	1806313707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x79bc0514fa18a75e0b63afd189cc1c1c9aa8574f9dee22b6984941e00a62b1e1ade73bc387483f16093a3ba5ae7e2a6e1c5e5aa1a4385a5754bb35d76200033a	1	0	\\x000000010000000000800003c95a852ee230873f4edf5b2093adf580ecbde1d1331a8e7bf46541ba4141f4b878d6575e8b3854b3270602d541de920e6538813f32060dabdcf3f28ad48a50d62976e8b6affae4c2b1c69fbdd258c7a6941e2bb6ee8cc87a2dc9ee5e334424ace9042b3750a6b41e61ed3e4d5e4c0bc6396906b8a01199ef173fbe4c33e7c13d010001	\\xe126e1ba45a252ffdd533bb76a91e87fb16cace102285d550a9d620f85792457c1c62cba391fb0f9299aa4a085a7baadedd68dfc1411f4f41de8cb254a4a9708	1662536907000000	1663141707000000	1726213707000000	1820821707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x7a6435aaa6e144de146351add9a8afdccb3abdf17935a08940e252dbe4b0cfdeb4a4a61bfa20abebe38ad00b560818127a78eeda28e08d1d7588cd32a1a66643	1	0	\\x000000010000000000800003f6299a8d54a0b6864a4830057a44ea32cbdf3b1e54d4dcf17e425c14de41d6fd3a4ec25e4897a1024e6869437067993f85857dd5a666d105b2ef866cec1bee67e7de0324597a7853b28fb0470cb5dd3978b13fb7215d37684f88f878dd0c89d9c5e8e8a00f49e47eef560e4ba1a647fd172b26fe7abd1cc0d6ad144bd45861cd010001	\\xbb18fd96a3d94946986a83a19d705fa85dbc10eceeb3f0a7dbfd39782c740cc980d5aef1ec974e9952dcaf35215d1cc619f42da99398c516143eeacea4d42708	1652864907000000	1653469707000000	1716541707000000	1811149707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
60	\\x7ca840231d9b8b3a79430e6cf4c18852a551f7af0b715db106aefb1024bbf1a2f52b0a2c55472574f30a6aac2fce4052d0d7782ebaa7cea43563c6dab54a24b2	1	0	\\x000000010000000000800003c06ee06b2c2cc562ef7589241b49952e4fe75862686627cf28da38812184b2381e60dc69c3c73669b69c031f9e6ebdcbc2b21319fd806cf1d0d03ce732eff5c20df4e2ca0123c64565ccb0e4389b14e64f63023fd482dc5eeadc77c0012a152d17c81c5626cc521b0085126ab82243e0ef7c5062fb108d55cc7f7594fec8e7a1010001	\\x7ad6f052dcc9c6f9ade92361b35a68acf7c63c689b19f80fab574886034b55a883ac80bb38f055c942afae6b968cdd5dfeb7c849f320911e9c8b99316b6df20f	1663745907000000	1664350707000000	1727422707000000	1822030707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x835cf62da2ae3d296ae00ceedb1998c73d09a0f95cb38e4f88fe8fed4f69a293d9f7f719a72033bcf7ca8ee09efe0b83902e49d0a6ba68869552def183c05897	1	0	\\x000000010000000000800003cdcc6085823a2554cee19179db82958d8baba018cc9595b356d22d1cbd4733b1ec51ed0e4c15fa952ce5e9adaf7d7b2ad2b990418264e4d03180fdf6aaa71f1c0e8c42e19fd544d3d0799f4b69eb07844586095266ff7c9b17f049892536db4a28523a5832afbcbb77a065b413f1a5953f946237b2d58caeb819cb5c790ea597010001	\\x66f4f3fa72a2597b1972380e40db0c969cc2acc8bc071980a1ed8f8eb1aa875bfe9b50c88f6ea037535acd5ab383ace162bd9a34290f4b04a8e358350e2e980a	1657700907000000	1658305707000000	1721377707000000	1815985707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x833c224b510c3751dc32c1ea8afc41daa86ec09f65b6d7b7b409a1ece04e8795aefc67b6aa890a47e3599585912f86a80fec3876855de180e4734d5b2d561b78	1	0	\\x000000010000000000800003b157d3c02f098231ca75ddc0f0e0033d2d442b9e0ebcaecf3c2c88f8cc04d957f1591f153830787b8dfbbb4c1b3c05c1f7b87d210f67a198a32edaa0b34aa8d0fa2aea0d6a624c1f72f8bb8be77c12a9e8f1e88f722683eba8b4a1a7e16feae398ebda3f10adb949806705a4b2ed7dcde70fdbed222482e83c02364677a0f07d010001	\\xd63f39e77df1144f0d5ddf9f47185eb3e07b89d9d1b98faccaecc2763bb8d44cbfeee813505134fe29c5b60fbe68692d1935ada8ec524562c1d1e3479dfc0701	1643192907000000	1643797707000000	1706869707000000	1801477707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
63	\\x849864f251cccf947fc3eb1519fc90af18d85890fa357d718858bea4998a9bb6cac7d28d01a137fc7ba94e76034480b12675b8e637dc4725863a1294fb4dcd42	1	0	\\x000000010000000000800003d341e0e096a97de98cb19ee57d985aa55f7ff3ef55336efd70e14501056cb852d27d20095406944d4cf94ba4c4c2215ab3fee0fe2c39363bf0b5bf98143aa5154d74dcc0118a5f19efdee018353228bea35bc39aabd73e87d7cda19758d91a6fa129c120a208ce8e71e90e56516c279edfb3418bd6580b06bcd928f6aae514d3010001	\\x0a0f12dec446fe32821302caa28b293245f6ae68f7a5c020390a810972d09d571a74544428c08ec8eb6d216cff483ef961b121716e690a763eb930ad7593d701	1657096407000000	1657701207000000	1720773207000000	1815381207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x86e4d14d122f18742644ec85a111f5e480ffc9d2e583419821f52a89816b2f8fc889a2f9067d0d004befe4508ec600867b18d82349a368f297c179aa4cd0d85d	1	0	\\x000000010000000000800003d0788c4b45f06e032f858f90e7cb6a65996a93cccd009d5e9eafb90b9d70f3669f735285aed1c2c33b954510fd7fa818ddffbed265bbb3bfba52fc5f98a93f5b8a782555a970034a5bf8bfd170a250c0576a17cdd6c97e7e5867ce3ada8e37929ba8abc14d7cf6e166b6d538efc3fe40daa28bd6e0a58a158aefb51aea57964d010001	\\x04da9211332f37774a4c0df3f89aba72fd05c03a63a7ff92e8bfec8a4ee0aa919be3ea170a59b018964d067c79b6adef31e5a3b222314146020a77d4b4c87205	1646215407000000	1646820207000000	1709892207000000	1804500207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x866493637036d2c51d8d1132d70d24f9fc44805af9ab5fff2ea559a2fffbf5516d0a13701adacd6399addb4bd8c2e52543920c7700651f8d5f85e9641a98b690	1	0	\\x000000010000000000800003bd61183bed377a2339d3dff3908167e550a1594a26ca4080188f60b507a0729e7fa6b5583f84d7f1301fe49d069310293dc625557c168b1bbbd0dea655eef038ed7b57c5786c9cc245a7f270aed05ae41ce34e46a9bd4eb0c458078df65f8f763e1fa656418f04c25344ae49cc9a14994e2399821788a2c1fb017d72508059ab010001	\\x4ecdb07a684e2a0e87981ddfd5122f5e8da898f485ce90c08ab44f051bafab27235894873b90b9447fd21c7d7b49d92aa567dd0b175d0c2136d011b031540b0d	1642588407000000	1643193207000000	1706265207000000	1800873207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x8768627e8ac99c2c0973af737d9f56234c2d66eeda5c919846df02738a89314673580d18befb3c3b719de5203c0c41bb767da3b0b3516c0575fcaa49059b0335	1	0	\\x000000010000000000800003aa1281b825eaadd71cfd6f0a5eb96caad4b25e6d19af482295c5d15c89e8aee22253221c70e88b23261e816b3d7cad3136210d308ffef4a092d92a2e112c6e6c93e872faf50968680ae980f09bb2a76d276059e01ea25fef1625ee08de1b80496c46f0e586525f53d1386c69c3e0ca3d43dd303c5c6d8d9da7e92be3a661c23f010001	\\x92b8c0cf081d4e2ce8dd3274a550a24c16e96d24140bcdc40b9fdbe90a76d4820d2ed195ea5eb8f21a7c29c56d5496f64a75d923aa90ebec42aed0750f32f703	1666768407000000	1667373207000000	1730445207000000	1825053207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
67	\\x890cfc94ec3ea98af1e67d6458d9909fc7f4b836ed351ebb293144c4f62fdfd3f5999cb207d85ab6b70447ef01ff7b671c34f8e47ad0f3e26e4ba825a229b47b	1	0	\\x000000010000000000800003a167614df21a6f121062f62431ca89259745d4147b2c6cde459922f08d48fccbd5253996052f9d2a1428488fb052e29ce2e6180f42215c8866005b3eb9fcf7cf5f0b0ff3c70ccc3ad8963ed34d8c27a7b553681e9bf7bd22845f945211f7a69dfb2e12d9c7e1ffbb8b437b54e721e0f65e29d9abf4f07b052f7db660eba78c83010001	\\x259efdffd90f57b2b3635a23d3633f591e90e007ebcd0331f0f7aee510a86ac58037f74fa0c30a76baf2abe299a2309ddd549116c74b9537595a3d9a90e14508	1647424407000000	1648029207000000	1711101207000000	1805709207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x8e3cbc14b02186cb82a5b63c4a00311c978b754217881a16c984cf9c12f47d5dc5463b95396335d0a580c03fb213bb9591208ee4528bb1043760ef9e605f9b8c	1	0	\\x000000010000000000800003d7e5e31554382453e69c6ed9c21abb79ffe22d0b1795bbc17edee32c1b3aaf8cbbd275eb58272ab2a788684c0b79c17883e4f66e3f7cedd7c639f722d926ff8b3c9c7918c77110fd0c72644b761dae7e2e334f72e63a375c67e2d3a0617211577d1fadff6c5f4258f8e270cd91376f2587fa71ccd7b58af7118e16bfab13e925010001	\\x600fda08915faa837e4c060beabfe3547d308f516c9a98851de729681a56f1e441efff225081114f054f564fe2bd1d8abccdfc2a02f036a33c88550fe1cbf20f	1667977407000000	1668582207000000	1731654207000000	1826262207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x8fbc94403b7006a569d29300383e5d8340c045acfd5911b7ac6616908e745855ce2afa1bfda16f1a7985dc5fabd35de079e65cc55a8c421225dfeb942c49a8f1	1	0	\\x000000010000000000800003cc71636781572d3625fdce1a68ed2718be73fed2b52df72d627dbe1a2f719a79c6ada5c448535dafcdf2bcddabdb0be8694b9bce76cb4ec832d3b38c106ba90ac2e7757137bf1303bbc9196643782c719644cca9c7baf9882f733e9fdf121fc61b42217948385b409af9c80b6a5e589818b5b8da3ca55e9404a98ab6b283a451010001	\\x982803ba2b63c408c4a536051131ba5671e53224d2da5f62dc7c9d6f035232213bcd193c47450317ef2a2815646e0c088cd6f76aef4aca158b72b4807fea6a08	1665559407000000	1666164207000000	1729236207000000	1823844207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\x9224aec00d941ed75687b970313b4f33861d293796ccd682b10555c940b33f72a04ac6fa7e2f943b39398d4698cbe1a029a9dca446e1ef6ceea5f76717b680a1	1	0	\\x000000010000000000800003d4564d8a9125ce998a5b13e829e857aa9bde5c889fe03bdd5986398080dea64d2a091cbea155da64f860e3b804d00e8494a4efe031befd6cc9ae3f512e96da2a2885e3e35572e2aab7937502a37a04d8f831fdeaa14c1f7d8ce94f99a7ffb1575d1a26c5499a2571c3a289f8613c2a55e0777c6697051e0946d6c6b6c0aef6b5010001	\\x115a8974747a77e03def0d6c65c763e21208a21ed50fe4ba4241181720225590bdd7447bba9374070c912befc8fb800c978e594d34772d08dd274c3a3ff73501	1666163907000000	1666768707000000	1729840707000000	1824448707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
71	\\x9488b7b495ccce71d2ad451cee889c78aba188aec463b8d96ea6d6310311ec91ba1c5caf8a38248029fb160f0117df3666c0c8516478774c747f6c880f1e219f	1	0	\\x000000010000000000800003d61b37ed55d51036bb277684117589fb885aa8b4c508313c4f7bab6308e1f9194fbea7217ca8fc30440c8091505e38f07684d45356804f563c491b2ed4ab977c7e6e60fdd216b24c469fad49485a47e4a822b16c0d40f16b6109ab927f1765399a21a9f38deeef69aba43935ed51b73ad99f11a1dd42ee28e92efea76ff0bd21010001	\\xd3fd40cdf3954d0ae3171cea5081245740c5f44f0f700df1e178b747e8f6743089201fbbf32697a44ceeb1f8494acc235e991844f0729924755aecf75cff4403	1654073907000000	1654678707000000	1717750707000000	1812358707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\x95b0ee54853845c3c6e92c66da4ad6cf1ef797d719a3de8f719d5e4e03cb53b3ec7c8d9aa5ad2c1c05dac022c02a52aef3770f8012b9dd9338f3d1db2d566f85	1	0	\\x000000010000000000800003d1500c5ba1a47e40b752fb3d5b91befcd7eb8c7a38a1967227d563b9c9b2b8fed7952c969615c8b4e42a78c5ac89eab0458ebb3552652cea25dd3e8c8ab663d88a7b82f0c7f22344ee0766791393c9907a70476fd372b4517304dcd1cc885a07e73ff4852014a92c892d5b9a66dd217ea136a943c85b1a28834921fcbbd4e0ad010001	\\x74ae5d015794c947d83ea95837c0c8e13c3f9560d7c240a00c01dfd6356c05e9bfc200c2e8e3af061cd7997adc8af198b63c3465dfa0f534d884a7655aa3c902	1638961407000000	1639566207000000	1702638207000000	1797246207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\x9584e8f117423c2f97cbaa68c13918969187913ea666c63a2ca0cb207d5524bc608e9adc436bb6862c63c6f01d929645d9227c8b88b8954bbb002152993206a7	1	0	\\x000000010000000000800003eb5197761d7ba0812e9a7286d6fe1d2bb7db0a10cc144a842c135a71f56fe245274502954f6a43a97bb35968f32f394bac31c39e1740c52bd3f6bf05a523805a0c7176c65b1164bebd641544b6e201513317015a21b552b379ad507f6dc53f807a615bdeaf643d85664dd09430a1c419dbbd946c9c762bb2098c8dcf2a322ad5010001	\\xd0cdd9491ec861028d8942f67daba4a1a75558eb76b26d9f252fe24327fabc065cba1b9bb634ba50e1cd4d5f485db3296922914ea26e96cbaa581043a1ac500a	1646215407000000	1646820207000000	1709892207000000	1804500207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
74	\\x98ac7a696cafa00500ee00f22d10243081460b283a69823e328e49ede0c7daa01f0c19cccdd6ba86f3c2e934147b1f373755038442872b4d0714563b95b0a524	1	0	\\x000000010000000000800003c582e0e2c82269fa3857134b9fd24d1e4f44eb0e302c3b1eaadb630c67911eb5abf9eaacee3eb1f019577262ec7e2fbecf63fe1183c97f6d46981d3f136eec82697604bea9bbebc741e063bbe8bee008d13ff7be461edbef93de7ce8616f8ce4ffb8088799c336871087e928daff5d57d3013e9f731d225979160fab87c4d385010001	\\x3984c31c0eb74bae221236e47ee5971e3423ddaa9b1d22ee516101c61c04012bf2fa0b54923054bb5903a5b2f7ce973c17cbd2463b9ecddafad7051974de2b09	1651655907000000	1652260707000000	1715332707000000	1809940707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\x9a80c2c0873e2e12baf1945948876e75b0d826b17d08ae06d9cec3cee0706c6d9b36c36f812a22433da4f1370131028b8212d25fe169bf75f5101c07a60b9a3b	1	0	\\x000000010000000000800003c69a1ae2cc601c9a94c0c839f5b32ba8b0bc77c3b3b908b6f27c219169a1803c0e23a36de6824afc5cff75dbfc35a8f201f1f7c6af21315e84e377782a59adec6968bdbed220c6437cdf76f67e74bb87dfdcd5e8d0e1cd5c4cec1860a6db3ef5d38f02b108a9e27f7b66992b5a96b7d3ba9390090a2aacf3fe656cd9403f22af010001	\\xbc1ef06ff56e5ef471f411be6d8c93ae43dbe0a7a5f0b06cec4f1e59d66c45f93dde60595d40be13d7e6d1804fb0a63a49fd1f7cf5e5f40c4f0f73f715526808	1653469407000000	1654074207000000	1717146207000000	1811754207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
76	\\x9cc8afb2f9b5a78017fa89f10c069457893a3a301b94d1e5281ba0d08b95a3e67b76ea2f3aaa23be8945ece91ce0ae5008202487a5ba164d6b009de4ee40bc1c	1	0	\\x000000010000000000800003d56eb35bd6be96bf148cde4412a4fd6647dbcc8f441c5c689274021a1ceaebf178ad01aa8302b2f63e5f646519acab406666ac35f62a805cd7bbe98be2a39f232cf7efe895f7d3e57b1f3b9b7f57a48029f01fa5d2b3fa2c83cb812a96a3719fc6fc241a1e3aed0109c475ec75bf6f5be53d432422a881230ca03b814dee3c61010001	\\xd49c7374a39c3ea128e5239b50f621e1b5fe00c58b3b41945377e92e11e770d949b738d1b9a5b7ef60aa038c338dc9f4161553ce6b8fc385c521ec6fac62eb0e	1658909907000000	1659514707000000	1722586707000000	1817194707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
77	\\x9e44b8f23d90e58669418789abb37676c0d9642e0c3e0685e3d0b5ec7619246cee4f380cd5e225a68b995802dab3f7125100d0260ccefbed932d1bd112f74f15	1	0	\\x000000010000000000800003d8944e06d5bc6e9cb6a7f947f0b2ff7820856582dec62e01709a41184179859bde8a66b54a8395dd068c465e8b7cef5a3bf3cf64822f046611046af84f26f0e8897aab8d7d49008d542dd0c5194a4b13698db49dfc585ff9d1909154d95da893289f754fedad0bb35789a9931daebcff4933daafc233e44bf06ab43f57a1d2c5010001	\\x7fbfd6c80c33105f591a73bd64c3da344755ed6321986e737d7d24c8a60fc189888e17d5774c4b20c04bd0905739763431677f51e3fa57d776858e5473c26401	1665559407000000	1666164207000000	1729236207000000	1823844207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
78	\\x9eb4daaa65acf1d91321b99236ac53dba73bfaa4673ec518f9c29b0d3048f96c5e39eaa1861edcc63c7a205eb2d90f979e5bc9ca1216ea32d8888af8b2f94f33	1	0	\\x000000010000000000800003c52624d7eb4f5f7eca6334d7052e0a2c602f157ffbd4ae809d993e6d7ce7e7c45025cebf2bc21cfce1447edc97e6258b94b90e093743d54fb4afd831d084462baa58c811f35474f35ae86701fa550ad67f59ec6e543055833ccfcdfc024b393d46f87d18a2b059275b47c651e145df86748fe04d294d475484ec5a0ce8bccf3f010001	\\x2f47a1d45ad88a22d84cb416dc89fd1a93239e5a57afd061b74b831851fa497b89cbc6037c90e66e04c1a09e60e785f8619c995997eada1bd1e8fd28d2608a06	1657700907000000	1658305707000000	1721377707000000	1815985707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\x9fe80dddafcbb04562031f8f0536414c8ab4ea000a76d0b62f34b93f3c4441985b51273f9661c968df1016480ecc1f33a5aa2df9837b86bb9c20980176e135d1	1	0	\\x000000010000000000800003b48d5e8e025aca7a55181daabc7e87d18cb47348c176d27189d5fc2bc2bff823b44300db7dda01a9634498abff771bb8da6233c16c3eefb9895dcafdbdba663638ef13de2f1e8dc2232cdb203f57a7e4287faefecdeffcd3f8ce5a920daa31e36e059ca874c060c7576e134f366d9093cfee41058ee80d1d52832470c520026b010001	\\x7b32bb1031c099adb52cf042fb9de49ce4bebfa00c13f010d96f4c6200101e8174fdcc62ae717ac5e082c2afa60171d985f5065ff10ffaa411135b9a04bcee0e	1652260407000000	1652865207000000	1715937207000000	1810545207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\x9f8c9e5d1d0a7900875ce5820461be6168d6b6d949c9a23a762ef6045e2961db53383ee4bfcf58351695d63fa3c67f1501a0f151d085bc2770b6a048eb7cd40a	1	0	\\x000000010000000000800003d1026c1341ba31ea966ee83305fc829a5e6e265f8099e3742a40f11fecc83cf167150b06966df6e23693a9ace1ee1c0cd2dfc0c6023b89fb92babf11580f8f21a4ca1ecef547f10ef75c3296ae4f288dbdef005a24801668e2ff3e661cb8437c27d9e2379f0ae91c59618da03f07180c3794bee3a0858654143fb767d7d30a45010001	\\x493060634f96cfe583ab668f8da57ce759a9070760a779f0939f144fa15859bcf68e40affc7b5a2fd4a130ab3a248bf2816d320d23f5bd4b6324d2868836a80d	1669186407000000	1669791207000000	1732863207000000	1827471207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xa058d5d0fd8dcb19dcf309cc1180313a36dcee21337bf4d0e1d6d3b352da228017c35e454da1b7bdd085da48b4b38dededdc08125189182de9f8380edb2a0308	1	0	\\x000000010000000000800003afd625285a320a7e93aebe1702b3292983de1cbabbe43194558d0da3552d2c257f7a9af13eb42ea3f08bd2c6aaa4e06bca39f8f6680cd0da31da9c3cd116089ab580b676fb3a44bbaa3180e68ad5515b75d490f17f55f1738f332c0820fbdad59e086ebad815444d9c1788333d2c4306d67a7ac8542dee3c5c603ade09e53c5d010001	\\xaa8ef0ed431c6a026979c26e6bc00e8723ac36fb52ba1ba548e8b70983e7904ba5737987ff5b0fe990326e81f287fab4e47c3d03d42db14ed2567108e968920c	1660723407000000	1661328207000000	1724400207000000	1819008207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
82	\\xa000a4c20b8414d9c6563108ac9d9c4cc3fb32945414ca3588bc955ca48d5fe6d518aa67db79d5d3d9e888a0288d5c9ccf125e7a5fe4a0d9936944532c2e21f0	1	0	\\x000000010000000000800003be29c7381a66b3318557302471b648b90d7191f555f1ebab2a113fe560a5d5bbbd5cd49d069e23007940a9e00f2878cc3722b9ac4cdc18124185f867725dd41d89e683b42e7edac8eae641377a151b9c1cf6965191b9518e647294cfd16488b55599efa1d71c7b0a34e15d144e6c015c36eadcf95f54fc93eedd051cadb00d83010001	\\xa05b997c66c5085c48f3888753780189a7b00781799bb0aed8a23415731f32d664a754a8a8b5078193076f0db00ecae866d1581502b00dfae2e2ef258044030f	1640774907000000	1641379707000000	1704451707000000	1799059707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
83	\\xa274ea8848e7251f61a2b806ffa98c47ca37e3d2aed8eb739dcd693a55cb70a62c0acacd18aaea347bc14506864aa1a2fc4c2de34faa8a439d44e26e1dd54fd6	1	0	\\x000000010000000000800003abea1c7b0aac9dcfbe75ab32dc4f573c29a5365b303e7bed9418ef2934bffa9f77109e93ff4a981a7f1b385a8aa2591cfbbd27bcf83b008f634877bb4228370988a1a4c524c196cd56cae924ca54d3e61223fc9ae48e29adfe9afa693ddc951fee210489fd3f696f0ade5ea5a07e153a79d9b3c783c2591c2d1a9cf6becd0e37010001	\\xe5224ce4b9c3e390d616ada87de6b78a400cb3df813e39260144aaf0fdb19325a7c26c7d32e0e15523c206f86051b1b380b338e504b559ada9b8666d49439206	1639565907000000	1640170707000000	1703242707000000	1797850707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xa424d4e23dcde17d78d8aba886252f4219d173b88975f7957cef32c8e4a0a53dd7973cc32e2e95d03774f400478599ae8c031abd09ca0e986d6f6d23f6b09153	1	0	\\x0000000100000000008000039d2dcd7ec0b91398ac731bf4f3b9028e9c0614547b2d46f72555a0bf4df1a64ca91a2962af56cca0e544707da344aae148e49d09879a7a229d5c1d6b7dde31415ea3d23b21baf840f00b8642a25469b40059fe0e316a1ac929394ef38bc3863b88df577733956316bf70dae7e02e79d7061f45161465514cdab44339ceacbf07010001	\\x6768ce53bea2b1a29a080a94b3054c2fabe6801e0be43f8575c10ee64ba53075ffaf54c2e22dda7936e798458dc63da1e2b147880c5cb6dfab0ac5f4564c9505	1648633407000000	1649238207000000	1712310207000000	1806918207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
85	\\xa9043c4c0fa2dd81981004ece85b94dc08576cd1e1a440252c03cd635541fd467dc149069012cce1a80e2843fbe9e4aa357e8782a57a2bb9d1fb1074741d32cf	1	0	\\x000000010000000000800003abbe2b200cdf5f6ee10d89dfd6a7a88f67445ee51268c72b09b4f01d291ed911f3161a987cd65b82ab9dd59c4a75b9b30dad8f52295b904834f9599e619d48d8e4fdf7bf8470145470e695194d52a970ad4174c1c6eefc6d767aaba39ce4e78315be005499baa7dac787a4cc7e185cc36880e11db3158fc50e2fd7164d86bec9010001	\\x5dd45ccab4f518c2802ac254ab49d0c8c2fd61110bd27c4bbea842731737e518a98748e0a9dceda8f3cf689438eb9d1a6387149acf423e1f8070d6a43739850a	1664350407000000	1664955207000000	1728027207000000	1822635207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xa91c95477bd7536ec61fdfa3651b7ecb75b2a3d54d8d28fa12539e3ae0cc14ed928cf574144df720d1f55dd7bdbba3c6c53576a88c9f169c9e2d47ac6c1fea5d	1	0	\\x000000010000000000800003b4598b5618bbc006db89871855fef23aa912a4c3afc0c080b5fed805967f7dc029fa82959b2dbe6ed580eefd712fc2ca3e91bee85ef0493f2424cec0fc555e162b9d0a17b7bcddff172fbaede84cbe8f70c46383d7b63e26eafcb544b7d7fbcaae26a3cb6a581134bf31c8f04669cfd5a1040c2697e6827d118762cfebf9462d010001	\\x37b3ce7bc5fc39de6e14f24ab5980dcb72b0533f36383ea18cd89bd11131b3db7b047407d2313414473fd7037188ce6b84ba96bee577f2bcf7cc702c155b440a	1656491907000000	1657096707000000	1720168707000000	1814776707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
87	\\xab248b8dc5f72b96d9624aebb0d10172ffb66bc261cf9e3f522ffc9531fa681d02ac073ab0c467c844306f1157799e6b827343560cee153ac01a6f0d95d4f9ca	1	0	\\x000000010000000000800003acc788a808153aa80972470dc1e3ff35af67005338cbf97e0cfe005dee4af3e4d2a23c660d01fb4b310f442a8a9cf18b2a9a21ea9e758825182ed3d882f07e7d62cae0a6ed6efe002520aed6ffeb5e1b978544ab3154e79d67dbfb8d6721f65be89c7f778e375079a70cecd84eed83c0af20cf98518d0243c9ae24b233f66be5010001	\\xd9cd3f0647bc286a1791f701eb28c55c2110b24aad226e950b9e8be793f03ff5e7050b8d188e57b05c8cbddfc892d35f3742b26e9806bd45dd66945f6a35ce0b	1648633407000000	1649238207000000	1712310207000000	1806918207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xaeacbdf6353969c1e66369e4d30e256c628346a7c4b2694c42dee7e92061dded8d6588b361ca5e259a43fb893020f7f0c43fbbacc68aa0e115c3ea10cfaacedd	1	0	\\x000000010000000000800003c5b17e7533658a5819861d77623d6118b1d46943458268d9db458d5976f4133fec053b7f018d98d7cece2dd9460754887d2a8a6c26d87a71d28054ebb27c705d96034dec9293471c00270b78c44cab35d4653299b659bda5cf0882d058f8eae1c087bd6f7a795053e9fa669b55a429aa77380abcaa852015b416930e35b447d1010001	\\xba1fd0c1c26195f7080774ec03778e8955551803f56c8259d1f24bdc26bf99b9e5491312d716890b88096bff6001e35a22b7c59775d5498edf07249fc1718a07	1665559407000000	1666164207000000	1729236207000000	1823844207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xafd0cb9c7c127a9c67fb3602ac9f6301517668cece49d9e085869894597ac0253241d0bee3d0bf4ca94e6fd78cd927ff840fccb8606be253cf3ea5a0d6738c24	1	0	\\x000000010000000000800003a6fbf8d8679456408e7a34983798a3e841077a429aa0e058f4c70c175ff35d2bab6a60d5d0cccaa8c28d3459102f570ff6a8726ce1c084c242d8f2e7e4acbeedf97b8774f4bd71ef0fa2c7ee06dbc14fd3ab7da37b349f1ce32060eb9f6eb3ba1cd300e28b3c2025f811a856f62d6380e632baec55cdf4ec4b21d72c5bde0289010001	\\xb8191933adb74c5a657dce08d76ce1fa03724b4f6577f5d3f8a94b242d446099778f11367adf0354bf6c4083d6146c6da1eb37fc492f8ca7cd6a19de24aaaf00	1648633407000000	1649238207000000	1712310207000000	1806918207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
90	\\xb2c86011b894dc18e26e7aaf34d180da225e41ff878377ff870cb4c39bccc5d75de50cd4b4c2bbfa65ce6c267cec1303ccff4a188289c050e4fcd4302bba2c00	1	0	\\x000000010000000000800003ed6503de5f01a13163987f073cd9efce9177177259c4a8261beda3383bd08860b135f6b06822a25ba6b4b5d4f9af540a869dff1c20e3bc170b400fdde1dcd9a8c0289fef7c691b75e3451f945078a39431f6a410d5477fc520f464bbfd8ae44e5417f295011f2af56307ac52a39ca20a06fae1d8649861f740e1f71164b5cd0f010001	\\x184fbcabaae6aa90f1d130d395f3fbafa27ccc192f18ea6d5f0d3689f884942fadfbd3926f2967e153416c28b9e00d651dfcb980126fb53ffdb44820e67b6100	1655282907000000	1655887707000000	1718959707000000	1813567707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xb4401877e6e614157dd0833cd2f0610c0a76c0317254ce3ed898f65de8f795f67cc8ac1aa2f703e0e554a5a97515e6babafe9c7d75d21458309c373dd6e0d0d8	1	0	\\x000000010000000000800003d28a6a41e0fdce29574de023e2377a56aafaed1ca30f98aa58c050f76c474258707c33695faed58cb61e58ff39439d82ab249e7d46a641f65faad131c3bd346edc75056d4be4d39cee02429dd2dbefad22289af499bdedf147c2cdf464191dd348bb5901b42553ce76c76b7e802b82ef4b41ff1f58882ca25bb406732188315d010001	\\xcb016e1faeb6e753eb99e829fe83bdbbfa481d638c5986527bae40ea10815ae512f7782cb31f96ae8985982e4ea72bf6f729299632154ea49258adde93f2a30d	1640170407000000	1640775207000000	1703847207000000	1798455207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xb570cec8a19c329398e45c4ae17b059a0d1f04c2bda778038c0f88fdba6e8b458502c99c7f8e0ba98fb71eafecc6359590e5af937a310d6bf41240200bc67733	1	0	\\x000000010000000000800003bc63ccd8a158dc34ca09b612d5a40e27e3ef38a0bd004b84bf8a1a8ec36ad1e9ffdd1d745c465645fa73d74c23e1b29fd2b8f140ad7fe292feb17998ff8fc667d81e37f57dfea93d0d78c0cf192fc56006609c7f94b6b1e7dd8153230230d571fcd7eebb67946688c74395900e275c21a8bc799ba468582a33d84fa5d1c9b3d9010001	\\x24be91707ae1390f27b5a7fc9d525c88bf38cf3b49856a894e9ca4548043e4819abc8db525102db0819512377810b0dfb2bd4ba36985e0a46992d46685b7d609	1660723407000000	1661328207000000	1724400207000000	1819008207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xb800400c04ccd788653279a7a47a3b598d55ef1131dd1750deb720a688a28e341543b04ea59a09f45d89ec48671430a833075d01c47a744e848212fe7e594cbe	1	0	\\x000000010000000000800003ab744ffe0ed15329ed8af4ae42b893fc19093f58347cff63f7b279f538433b2d683c324ee56a4b9d7cbe7f1afdd6a90aea5bbc1d0cf490b9a7d1ff1b3365b8eb41767fb2f7519c7fb41d3efba075d281a5a600c0fe3f9229e6d83aa64c9d1625aae2aeb312ab81206cc4159c525752fb98a365e3ccdd7d947249f464d44865a3010001	\\x599e93ee71851ccbabd6e2d989aa6b38576716be190ed82ac89982e2b14279d1ddaf5adc5cb7930ec0c78aa8e9392cf211e740f7aec4edf29befede41ed39906	1658305407000000	1658910207000000	1721982207000000	1816590207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xb878f75296a69a512dc938bce3cdd582feb2003d18421581a928b897851827dcc5c6d8d5e75f5e9c298c6c816473bbffc941bc053f668e2c99c9c0373d9fe976	1	0	\\x000000010000000000800003e5bdb41f03655a8bae8174a7371efbe963e791358d8091e91bef9be717045662f73ed6b7c11b47901fbea2db638600c77da6984ce689cc90d4f0c2dcc5ac6609d17a6fedca1ac63b0b624a33b6c1d8d8a032afbea988d76339cf96cdd954d49c739070f7ed111137e28fecfc818e27115dfe4d1086264bf08e7dc820f9a4f3bd010001	\\x5a745ee97c8cb444563849700b4149a165c70697cd6ffed639e575a1f29f5b851e278cb1fac23afad8d7fe7358eecaf89e54027a0f8fb5a67a5e8f771f545c09	1664350407000000	1664955207000000	1728027207000000	1822635207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xbbb46b920f873997991d06b93ffb6801403081ac542ea221ff5845ea893bb95a08f39598d6aec6db639c9d6d57f60138dd35cc92e44bee2d36b8dcc1bea92878	1	0	\\x000000010000000000800003b7242f9f9e0d696d8b011f10ff320a65d778ebd9885800c0a7475dd5e0131ee41d4b5ecae13ef197f4ab9c3bbf8b2c2d4176fdaae4565172edf2373f305899e52cdcb8dfb8acf46fbec01a6d08ca72e3b26740635da0ba44ecd43048bc465c29b241042051902b5aaf73ec399a5076a275bfa43468a3fcf460851386d388e30d010001	\\xfa1d9803ebe311233a1ccbebd85fcfaf7e85de605bf39062e8872acbdd7f07a700b310c17ceb9b349c640a966adbc336d23920a23812325b7314a790dd3f3100	1654678407000000	1655283207000000	1718355207000000	1812963207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xbcbcb595ae09cf4b7b3ff04a7bf45da8604c9c26ceb0a98aaf4a48d6737fcd065b6d0c268cf4d153de3bac7015c7df4de1961af32ef5a2290284225ebc8722d8	1	0	\\x000000010000000000800003c1a20ffc8037b3e0fb692adb3da9fd7010fac3faefd374e60ae26dc2d412ea4f303b323c2779f143fbfda1b72ee3a9210b2ac24750782cf7bae22008cfb03b329d6dbcf38ab77b64ded43ccc1d29fb2b35de5e7c98b225c86ad4248c49c9f646d5e2ec585a27239ebc388afabc5a12eb76279a4035737bc935d2a27fe0932fbd010001	\\x04eaa4eceb7148c28c7cad9dead8d5491f6f56dba566e3e28a0a7ca70439d994f761062c42c81c61e0140b9784fac976fe7139e98cca424e2e9edee76ae52201	1644401907000000	1645006707000000	1708078707000000	1802686707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xc2f8b743e2cefa52c18caa0ca4df13fb9de89c7f583081aca581a588b50fe36d6af3f3823b05dc01138a7244526eab47f57e260c747ce47580d464ebb1cc05e6	1	0	\\x000000010000000000800003c912fb8fc6fa4b04dcd0c3ca4804acfe14334bce57da571a8ef43781e7f59f85770332efaa00659a154dc9dc115ac7d43c1486b43c0d9944de9c0f88f7c05b6e3cde1074659f3af657f5952a0392565f41c123285de8bfbc4d098a2db2c39bf1041e024aa9479fa33a395575e274855f99bdef4b017f22ba7dfdc9902df38aa5010001	\\x7307ce031e6f27cb70c4db204e00fbc1429164cf45fe0e46bb3bfb362158f0a666c903a2bd784fe3571ac5485dac9a4200b41ed94a26fa16b16254ed2c42180b	1640170407000000	1640775207000000	1703847207000000	1798455207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
98	\\xc43cf7cc55cacf73bfa6f6217433d9675133501d6020765318603aa2fa224f6f9d2974d554d80888fe47235eae346def8e74f70d27d1b8ed926155aea0055833	1	0	\\x000000010000000000800003c0f3a11e2afbb20796eaaa3aa49f8249a3987650b2dba8055ca5d996ec5c5c73444ab4db895d2a8912236f716cfa36befb4b3c441afa1c9754d44d8971109fcd38aa2ff267628afb47fcc595f6e683a19013a8e95c6b5a7a2af29d665045f5aa19a53886c4a5b1531532356c35016abd4d26fcd9e687f24e5a58baa386881009010001	\\x9d02b95a2a92eabbcd10c677c08e12cc9dfd1457167a95aef5e6ec473ff8ec4d14b89e042909febe29fd870506ac0357373db977cf220ea4288c34d2eaa6040b	1654678407000000	1655283207000000	1718355207000000	1812963207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
99	\\xc4b873d4a42efedeee6285730702a7f4fb31c726c0d5d3236f56726792f8ed8c79a2bcb4813ac8ccb756991c8659348d185cb8a2243394e5456b5ef850d2eb49	1	0	\\x000000010000000000800003a7e5065b18211144298026cba9ac18b0258cce85551b3251b3006734fd25944b9d212bc9ec68540e76ad9833097d0bf3cf11a5b7e9d6709fdc4245f8252f119bd5d8bfff1240d187a92ce8bffe85d74ad3a197067c61b0f296d7a1c20c01eb956f0ead9df5df05f030d02d74b342788eb42a95295d475a92d15f40c0f594e51d010001	\\x0e0371cdcdd168db937acd59dba9ea01d1b361b61277f011ab231eeab4390051b7c07957738106b9c60c86be0b7f1595f0387822b7a7961591772da074ed0e07	1652260407000000	1652865207000000	1715937207000000	1810545207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
100	\\xc65cf8c8a380404a862256275c551194bf83880d18f1853a8da3bf4fafaf3f9bd96a8461f68ace3eb3a5d8ebfced939a04178cd7bd5a9671b0be9336404e9f93	1	0	\\x000000010000000000800003fc2a8bc577e2ecd5cf23f2e178cf2f9063b110af7267e3f3ee6f30670a0978c1604b769c25f00cd01aa7aa3e09a70e11cbd76fa128ebf9fe38b2e1d3ba4656ca99b20314f2d9f5d6963d6094d73a42e4c4d6f111b3f794875bf8da53dcc962b2ef6d85ad90dc58500580c91cf11a6e13081977ebe9cb4e0a43c7be269c51d9f3010001	\\xfee5727b12ce933c0762ed13690458f51da36dade8bd4a34725aaeba06d0d486ae55262f7b3a63884202286031953d3e6601cea1ca48bf7ebc50294e2be5b103	1667977407000000	1668582207000000	1731654207000000	1826262207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
101	\\xc7fc18da6374d15818bb118ace502bdb38e7fb6a0a2e1dfd236ac7dead9446b348bf72f2c89ef0f450cc7751ace4e7529c6bee0b427ef345a9f27f64a7bee7dd	1	0	\\x000000010000000000800003fcc446e83f4e5873968347b8ac876c4b6091abe98e2e137a64c669ba4cccf7445a1e08f7f920795d3071e1d41447ea171e58e40b36975ed562be8bb594c5bce68f9e1cd5ca70fb47d31521355ebb0d6e7dfe0a933a4145cb5040f4bcee06ed3cfc9cb1dadcbb4635683c3baed66d5bef4007d0e4e9467dc1b7bb17ebacc7b139010001	\\x549e8d8183b416d54cb0c30abb9f774430166ecbb7ebc763750e6166945222ae0cad7ed63bb3bd9b64c06fcb188483f954a118c1f93808c9f097b4e16c7a9e0c	1641379407000000	1641984207000000	1705056207000000	1799664207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xca18119b3cd9b2a5e5dac49c958a4c5b75934e36d07be37483fe8a488aae1cc0486d7a7db9ccebd9c67b77993fc7c2f1519dc3ec32001c79dbb9153cc8698742	1	0	\\x000000010000000000800003a0a7b8015f2190904187f5369350954b283485fbdda82cf9558a6703099cb4d3e612d9b34e05bd34ba792d2c05f8cb94a04a7401445c86461feb4c49915e6ee2be6c849efd195917d7e9745453a726ea7d6efbabaf14f504adeede782e470148527848cc067b83558172a83054bfdd6100fbb09cf5d236e59d9e09c85a1255eb010001	\\x87b8ab6f973783d9472d9fc3aa8b0c1b51b79e22c28c797473d3a706048872470bfc9075681b1d9f8b4009d174d62111ade14288cb9221b95069a9e7be4ee503	1640170407000000	1640775207000000	1703847207000000	1798455207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xcae82e83d002aee720ae611be90c65f4609493fc11446a8b07d416e281616f54997e8f915a8fd4a099ddd5898a5e37b325efa657d5359b8b40ed2a19f6bbfc67	1	0	\\x000000010000000000800003a4ae9aaa65a1b9b2b0739451e40ddada1e642bb2145f2e315c493347027ad60f4e023835641be7c0b635821ebfc28c2f72a5623d17367352f725f0feb202c927587336d95453ab0adf9170b652131353d53af521c7eec252558c77233870843c94e046ac4d977e0ec60bcd38abf03faac396150bad5e0d1d5d0640a62714c357010001	\\x2d975150651fd69861352deaf7536bc57d37db8d18e1c47ea2fe5458e2790ddcbac6b99f90a20cfdf1db92b19840ad8c80fc5e5e35756de08bca7e474c1a940e	1655282907000000	1655887707000000	1718959707000000	1813567707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xcaa0bba1eed96cea618332b401a7ed2c3f5ab3b43c2837837877de7e4d0b1e9c7fed63005a46e37e093c3bb07f667117fe4fee923517de53ad029061fbeb4e26	1	0	\\x000000010000000000800003f3f490c0df747428993eacad00af066f233fb9ae501a374c40deaa6e19cd019413822ffcf06254dda1191652ea403aa694ad1544aee863edf6406063a8f6e2b951d46d2dff09d5d957a4adc79e78e721f95301ffe310b08b042f73730adabbf46d0e3562aad6398043315de4bd4d4b772d7ee2b45227f8b3c7cbb95f3a11c1ad010001	\\xf8b92251b571162e743164d8fccb57dc53ec6f3fca6bf8af2ecd906f6b22084dbf6166d8e8d040a6ba280f16ddf598c3bbc48e1825317e88c6323c377d14ba0f	1643192907000000	1643797707000000	1706869707000000	1801477707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xca604ad4aa1a48f5a4cb020ae1c41989ddfe6cb61649cc42843b8530c80c3bd8a4510e89b2242d3c1ba960e2e17ba1a73324646ae80ce46ab9d544e03f9e7bab	1	0	\\x000000010000000000800003b8eec2b600bd80bf7c2c22deb08b47cc938002b951085f2df287f9f4531a51a3055ea03d8aaa192414ffb88e3f37e9af86139f929b5bff38dd10632439d7b4ef7fab869f9f2d57068767b304b03e165003560fd4da31f18a4b50bd893701b05a521bf499670b802bb7a553739e9d83586d9b0cf01fb48b8eb44be5f1a749f00f010001	\\x0c9f327b98bd9449ab10225cb129e4dacbc0af9d57fa66c1a35a3a918b522b01a90d97d594c1bd8ec8efd62d0242a2dcc87580bce970f9d60fc8ff4035b41e09	1648028907000000	1648633707000000	1711705707000000	1806313707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xcbccf6edc8499d511fd54ad2104c1f085b702bea91a861923e6f11eb222ca51362aeb507a78f846822d337e2656e57cb5cbd3e9c04c8e1d668ee2219708bf6a3	1	0	\\x000000010000000000800003c3ad9e8e2ce76161a1cc2ca2fb55392a812c6bca178a020bf78366afc49f5f952db6615f66dfc164df1a326befd1271838a98dfc60f5898eac5da9492875f7b1192aa1b9608ed6249484538863e4979fc0f3a00da0862c2e2934f3351967cb330a22ba35a79014bf3d58e117d356dc22ed49c10b07a42206aa218576ad616bbd010001	\\x511a2c9c4addb76045aa830d48333b56d72c45184d0da672c53dcf0262ffe8652cf0bc90a4fcdb194491b69b3194f029c6bb94f87a7a2cadc15feecc2a80380a	1641983907000000	1642588707000000	1705660707000000	1800268707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\xd0003b0d9669af132ca63c56ae001ffc39bef4b4e0e5a792ecb52c5755bab1fc1efc0c00e55f77ceb287264936424b0d31407eed820cd5c9a1ba58e66094c680	1	0	\\x000000010000000000800003dd560046096fb8b1f8178b599cf633f94e0ac0b62e361f5dee502543697269a1558ef2e3b3972615462363492382671ae8edcccc7f114f74172d07bdd677e8b93865fdb6a8dbcc5f08422bfb4bdce80d2e73b055c80c749d64e0cdd92d473054c25455000d82d1c1fe40cce550c296dd7ff190f3c95f639987afea300c83a2db010001	\\x81c57fefb9634c1f53a7a9a2005581e2d09edf2d0732f0fc5ca5c596fcdff4455f2b04bcf077aa7f44a47052750de9a985e6ab559d4640cdaf6ac30e4e2a5104	1644401907000000	1645006707000000	1708078707000000	1802686707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
108	\\xd1e8e85e50939a454f1b60dd887335fd5d7e6ba1e3be660ab23a3067ffb0c34a4286608f44cd47c7095f32f83ca72e1d6c4eb8ecd98bc53cc95df17c01244902	1	0	\\x000000010000000000800003d82fd1dc03455d0cca6bc1879163f8deca051ed4cf0ef00a2c7f6179a58d11f9f323f1ceede3fd26b2dca04bcdbb77ac19fc3c6bfd4b61150dfd8c0e26ba2604134efbbde600e3af9ef1d69e5cf70d549e286225d2862df357cfa2cb34def0c6cb77154fe1b6632ecdcc2cc89829096856a8049a648a7fed61227672e2e4dd9f010001	\\x50e7e20a94a008ca49ba58c78e6381658503f34ca09da6d9706ec45be031fda15dedcf827e17cb598ace30e6123df0ffdb1d50465eafafa6bb859639ae72e108	1640774907000000	1641379707000000	1704451707000000	1799059707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xd46c1eb2b15beb565ef19cd754a70874eea025e2747f310f62668a8dc077860c7e93558fd736beb700b85a8aebb40e5d39904f48e90f1b3ef77874f0de19ae69	1	0	\\x000000010000000000800003be277c85c858eeff4d4f06abad250441dd1b25291dddc6b4e1a900943717c7555ceab4e1328791d16b50d467b41aee5cb53c202452b225684447676e2c6dcd8aa7dc31542e4881fad4bc808b2f1ecf776e7513e9d1c95373460492d8c4ab90a72b1d1258f9a82c9b67366b26b7ad19e1dae335cfdd69fd0906b21624374d2e11010001	\\x438b27a767ca8480f3bcfd5b11d4a3df23634ecd36fc05d918bc6918b250a077ba6588c57ed66f6dd6f890cc830b1b4e91ddcdc055a762094a1f1394d6086109	1664350407000000	1664955207000000	1728027207000000	1822635207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\xd7984fa508f3392c86b8f9e4b8c5d66a5800d75efc71e5b24c1b71513fc8b1b8685344c0f1e6e3e590daceba66f9fde02d0fc1cffaafbeeefbb323a62c04e976	1	0	\\x000000010000000000800003be66549d10accddeaec4f0e020b3340a68391b888e7df3045750b2ec3f4da0826b69de1c45445013445711342ab7ab39a29a4bac4b51330bf8f6826005c045ecb74249eb173f0638acfc621594e4287dd88773fb6a7591492f7aa06b37f4ee6eccaf79bee154bc745941bcec80d76131110ae5f60a682691592b21f37fb90053010001	\\x6db9a2030e6b66615e3b64f3600a6e3503eda9e5c6f901e8348560dae5bdea66ef0ee305b168cd3447eda103d6937048c159152ec63aee96c2ac5208dd5d6604	1666163907000000	1666768707000000	1729840707000000	1824448707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xd9a01c1063bafc8e6234b14302eaa3efd2f98f0c3a9a5d2f89161a5f7689117f4e7bcd37ceb0070763e333ee6b0b17f9b3dce5a904c0e662c8575a259a532303	1	0	\\x000000010000000000800003c2c8b245290b37328dd1397710fe444f007e0eb445dfc1425c3864cc896cb1cce1fd5fecef35e99374aeb4dbf406a4464a2e8e0db3f2970de1bca3940be5f5beb7aaeaaec5f864215bac78a419232d5471dedce2bea401ba0e684c6bff2d8fc9bf8ee06b3b3f52f003b6f9eabc4e0282451cdb421880feaee3279f3223bd94ad010001	\\x889b1182cb8f35ed1f8c96b972e66c20924f73295b28f00d0d96e56083c8fd64837abdc520c99f42613e48698b590d7eed457d6310ac4dca2d40c3d5ec90960d	1663141407000000	1663746207000000	1726818207000000	1821426207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\xe1a4cd966e8e48ae37270e841bbd6663d171f099b59db4ecade266105a911cd194b6d597238e026f553b5cdbe372cb963f75aa4633874b09ef52b2d6875bc20c	1	0	\\x000000010000000000800003c9223a11871ea01cb6cf573404a7d5b2bf34c5ded09a6dea67a2819a31f4981a8383b97de72ccd7064ff1c714f9bac7a0ff010cf76a144c0345b057f1e276444d11af827e6873c74fea2e5e463c79a382af29548bc59bba5c4d8a1ddb868d5def058d5849eff40560eac09a147ad50027464042e11d606d4b304bbd1f2ab1647010001	\\xe745b9ecf66812eea8bd21a9eaa913890ee73ad31e1c7c2f264f68b21a3b765e8a31fee330512ae1a1f0b70d977c9a42dc560e84c5453b53b952679d63e4c006	1649237907000000	1649842707000000	1712914707000000	1807522707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xe44c044ee97d376c8bfa55a296d8e9c72b6301459ee8782e57573c09916900e448877a4d9d4bb019485aabff67804259fe79e68a287fa8f086028f9a4a24e997	1	0	\\x000000010000000000800003a938fe9eaea59ccd0fdb326a28a4620198ff7dd0874cc6978fcc8f512bcb875440344370f26fe9fd2a0f4aa1a1853c0ba8cd55033bbde5e06108f410663f765d3ec4e0848c6e3a2357b1167d3085fffdc3c109368ea5fd42517b12d7a5294a1b683dec9dbc2afaabc9244b913d3523d61e69968039a0ec042b8df2f6ce47fc47010001	\\xdfc05858379ec496600ecc44b76fb0386f25f0ef11988807bf8be98a5e38704531ac06e9474debb07d22fa6c5e18e59601939088a901a4fd894c6ee5bcf51f08	1657700907000000	1658305707000000	1721377707000000	1815985707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\xe61856c28ed94e93bcd8bff0f4b82de95a8a0af85b09a24c728988d8441d8491c43f8a45103af3f3c95796cdb2ebe719a16f15053e52e9e8be896146d8eb7a06	1	0	\\x000000010000000000800003b55e71fd1b61012ca6fe26f9846be1232d261ff827a23e98aa14c4a26abedc80318290dbf5cc326a15aadd4e4124e95d848521d375b61edf7649087abd4091a6ad988af2a88aae98973aced2900680927a5229abf3609b9d5532d66247603db8dbabc0c3b5c72b4bd0a63f718a598ca1a169dd1c1ab78c6a2f50d38d3c7274a3010001	\\xa6ce3b8a80c26ecfafe1734dc18218d392de526d25779661a15643dfeafb7d324446677baf2b102deee25b022554f37774ec800f8be60b2cd2e61ef58f20ef09	1653469407000000	1654074207000000	1717146207000000	1811754207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\xe6a023e5713985af543d4bfa3bdf54121607837db7d1138ef1c4da3036d6a3df75a6b95d5b9c48a893ecfda922b70f3c59304abed0bdbc792b1fcb8b758da83b	1	0	\\x000000010000000000800003f655b424d8d5b785d925fe12420393983a23798964aa66a19dc9f80cd345a6c2caa9fc7a07f1b668a1012e6ee23fb7aa377ab9c595a2eedaf4152d0bb188c247342aa3df2199bc7cc1f158a1fb439e7c3a6a159afc170306001f7c222cfb806d0c0f8c454ced41def65296cffea83fafa37d90687c2ace4d767a0faed07492bb010001	\\xea9c994259d69c9de69a858f0cb94fd9d48c19237a88677ec7ea33bc623286e0fb660c753246eb2c70d6077818a7a3a0ca9bad4ad1352b4d3beaf19df4807a0c	1647424407000000	1648029207000000	1711101207000000	1805709207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\xeadc70edf58b1f4b7b08cd98d7975dd9f879d05ed63444f311a2ab8d0bcaa3e6a3846e2d807c36e87d077d95d0d2f59e228f0f6b927d39532a1ed4ddd33f0c76	1	0	\\x000000010000000000800003b4ebcc0af11a01a273a3756c4a9cb50fb4bfb4d36227db829c09c859a8312d3114e454e52b154da61ef6cc6799cea434e11eb5332aa12943fcbe109ba6e2d2269651b30e45ce533a5dd94492eef2a5e259210e8a1d86b773ad811a05ceffbd7b6791ec55d5d341572232733c4511cb44ebbec44db505a43780829e1d224720df010001	\\x42e07a2bc9f2618f1372ee6016ea9d5c5fb946fe00f5d27e5b172fd5c77ca07d871903425e3061c23dc6a6456ea913cb7c92a1207e4c8bc97e166bef2676510d	1638356907000000	1638961707000000	1702033707000000	1796641707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
117	\\xf0705811549d6325009c9745ee9fe372cfd5dc54308f06adedfd07f3a98514d49eb0a4d84bbb91982a000693f067c7d466daf9d019a23f5a327f4cce908df809	1	0	\\x000000010000000000800003c340b534e52e4d660d31b7947e325419ad7eab50b415f76b1b977cf6cf8d84732bf25c5644813392432bedd2b507964f1f5174d3ae2fe87409e43f3bfe7bdbe1d14445831c34d1de490810793cf668ce6b621c2178164fc0ce7c3c08433b0d27ea31f5c88841af7c025d2d998308b96230044db1603c1c2bc28051beeb0da8d7010001	\\x709690c1b5e359fa48e4931971bc7dfe2136e8a40c2415b004af6c059d515efb4609b8df7f0b8e2ec987ac91ccbedfbd97d3e5cf34d7ce118f69744eda82ec0e	1645610907000000	1646215707000000	1709287707000000	1803895707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\xf168c275773f86999fff5a5d23892af1bf50e673a53637c8358aa1629f928a4575751381e70a4b22d0661abb2864ad05629ff0e1656c2226121cb265e0204249	1	0	\\x000000010000000000800003bdae2e591559fdf47fcea130f71dba6b421e16658e865e3975ec0f560f2a4f686a1fbe96b01e896f6648504fef4ad51ad9a43b6e3f798ffd61a4976a8b1faf7224eeca269c52139a357ecf950cae3acf4a071d0bfe4abe794c4a9fdf476326d7911cd909377d60a38698fd9f8c327299162976bd47a9dd7b7411dad345c21e41010001	\\x72565d2de1ae91fcfcc504d094093d3fa1948718a6243106dae261d00a41446610306a12768601f1cf2ed916e3d1b673191cae05b8f3bf2308d818bf7e3a3106	1643192907000000	1643797707000000	1706869707000000	1801477707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
119	\\xf548d688fea8bca2df101ebc9d305b07ae4ece3d68c80a3e5902211c18a8cac74efb4b09ecafe2575025648db64dbab872434659a4c0e0db6028ca83c0c461b7	1	0	\\x000000010000000000800003e23e349d85a97c9d572c7b9450661df9e42d9fe81a4dbb71b268a7a41f6be40e71d82854fca9a7575ea7d3b004f73eac77676df4e8b075a1edfca134a29655d1b66daebe6b8654f53af262d34cdc63b3359db17a9d22361211d31e6b100ee57ad6a70b107f22b87461e7a37414b299c76ca309519c5f4688b1ee46e4c1b3f80d010001	\\xb4e3e3e4daedd99fac5735461a3ad7bb4732b140cff0a8d7808cb581132d4910e9990ae80ee3521c7df0c1a3bf162ea8f14947968956d08563d25aa22b255f0b	1663141407000000	1663746207000000	1726818207000000	1821426207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\xf9e480430f2ce6703d905b4b4234ab40c7b71f25b16554e1ddf5b3a157acc448c0f9b6b2b0cc603a320ab09b887310fb2495f4ca1ba86ac439844ee51336929f	1	0	\\x000000010000000000800003df4cc746d486c5bef3887624e6bec2c0499f39e7b64bf7c0c5e69dc66e3820742ea062a01a2bce1bd1ab81f55e025e5a21d126ef8f9f7fd2d452b7441e1e5c385693a3db59762b554e908ff465bc1be275fefc2ce9d9d5c4d198414bda9072151733a27cfad464396a37ecc21b3da5b7df0bfe6836e9a569ab3b763d9427843f010001	\\xbd3390c8eea521757bb121c4520682631ed23e9d01ba1689c3e414baf2c9b6025d3cb469d5061482bd58c717f254d9cf9d0a88f626f18f0df81d1301a08b2b0c	1658305407000000	1658910207000000	1721982207000000	1816590207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\xffbc3f0ac66e680c561a40ad6637f76e8f7ab756ddf47fd194dbf9832789bfe3cf4324037cb3ce09fb716fa842d7cc5fb4db3df0929c34d41884db53807487db	1	0	\\x000000010000000000800003c16fcaaab8ff799095c5e81f002bae76e41184615e6735d2f92f9c6fabe94afa56377505d62a76c152a1f01d90a1fd6ff9f6b99a62b62bd9622189bfe30196bd82ac5f9c0bc450452d539be15b63615a07c3fc0b96231e3308db3ecfe2fb2249363cb2b8aeded5eb2b6e2f317ff04806f2ca8e37230c19c1a398705d2e591763010001	\\xc3a7daa14613cfdbcd04c78c5a43ef2825f0b12711dbff59f3e99df551e1d4ff9ee64e6f1fd972e3942bd285170efc4351616b88f567e5a530e8d306d3f27c0e	1660118907000000	1660723707000000	1723795707000000	1818403707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x02d9512fec81b7bb0d108f151fd98ff9ddb3ff3276dc6263088957f64efcf653c5122faeeb20931bc543f911e9655d03020e529246bdae4029b35d4629b6a3e9	1	0	\\x000000010000000000800003bc071db7681be3c16871b42896aa2b90ae61baed7dc32d6752c426b4eabe8d46a90b3af508d8837ffe2fbfccc7de87a7458f3e92d6b3876809be579e8d02d5ca2b1c8137b413fb0190134f959dabbd3d674cf9222f2c638c7648a9bd0053e46e00e682276825911cec0aadcf285142fc8d858907663ccfbeca69d563656b778d010001	\\x2b17aafe244676ff26f183885a7c584cad824fde01f42a8e08097f0e3064e0d1cf9defe29f7c9980c7ff854b870a4f0dbd09384fbd41b85a1927b328f6c5a606	1642588407000000	1643193207000000	1706265207000000	1800873207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
123	\\x03d978d97fc860af7727d4f1e1bbbdd885834fe7fe5323e9d8b557afe03aeec767beb8af28ea2548c68e3afa2a1980eb91ac2f4a27cec4bbf05212d50073e96d	1	0	\\x000000010000000000800003b29f1ad37fda3e260384954ee3b63fdb55d2a433b6e5e1b53bed449cba9927f377aa6677e70142e8caeec6313084b53b6ec163897c0363f25304249ddc54b17ca598c616c4a2ec9c0467c67d9871afbc2e6d9dc3cbfa949dc517d71de42a20cb6366fcb1766e6294c0c504bfe548b29820df218384b2141ebe0300f88f60796f010001	\\x45c9945afe16ab384152a992bc61a3c1d8f6ebe5ce4c08b6b4e59687f99c5aaf8fcd9db64c6c4e189b2086ee32e16a5ecdff1ac13159ea34cdf5f838a4bd7408	1644401907000000	1645006707000000	1708078707000000	1802686707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x0405dc2d0708cf80b12d9262ab3afee47159ba8e30cd6929a45bb990f8f5bbe73c2179e0e2c7b759a1af8dba2d8eb3be43918ecc4cfdedfb3f65d0e010409504	1	0	\\x000000010000000000800003a67c14de480e6e1fbfedc1d6a289973708d0cc642d28e4e41adcf0ded4ae87e5395d1bc254fcc97cb34269f79cdbbf24a7a0bb68e80b7acd914ea6604ccdbe68f479c21260f4bb0df9c52f99cfc7db436597462096e1d60a0262189a3b54035948b0829c7ea5db7d4a35e888f5d36c21487efe39b8840eea75097eadd4c76c25010001	\\x3c371fc02bd67c079c610995267b5da580d4f693ed86ed09ac0b1a6668ab0deeb3d97023a20fb976c86b9e1cda1dcc6862c495e838f9c6036c796d4f671f1202	1658909907000000	1659514707000000	1722586707000000	1817194707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x0619665d441a506b108928b1a054612dc1f792b9bd221b9b02a3eceb7f23511e219ea50903dcb7138c604056d4b44ca6dd2243004d3c32079ac9209dc5aec028	1	0	\\x000000010000000000800003c1924a68b3c754e6f55c34b561d6f8056b2a53e020d73082556b01592ddaea4cad06e331bee22c3de913816c2a5bc767f90be775c2b88489ec1e23473b4bbbca70053724a488f052db2fa55dc04c8b456c902670160196f79b3a7bd84bc838e4a54c5efef967300d1f7d8697b0bbd91be0b8d3701da4134621436ef01249fd6b010001	\\x2adf2785b9a7b349d5cf2da4e50dd63d875d218c2980c16fdb14d93c3136028bdd7da80ffa0f92440dc158b38219f14283e703d874e1668dd3904ce619bc9c0c	1638961407000000	1639566207000000	1702638207000000	1797246207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x0d415ef4c3b0b26416acedc2a5117f2eec5071e3f1104bf5e50ac3fe0be7a83195db0f46084c98342d4c3f8f54bfb88de57352d79a8600eca83e3a7be35af4e2	1	0	\\x000000010000000000800003bfbf399584f107234751071c9099e18ad182ac3f16a222278f7051a0440d502ebc96aab84d9b2d4d2ff37c8e78cc2ae793845c8020fe0d6633b1076da5dfbf6ad749a1a9b20d595faef6923172a84cbc0ca1e01bf7f64ffc0f6b2004933268d19da6c8eadfb3039c3f1ab986a9b303b5755d4b0e5ddd6cad4aca5ad9823d639f010001	\\xee8fcbb00634adf241cc3a2868cd6eca8869ebeadee57e6af24316cba59a71d869972a269f0680de405f0d0278c7bebd72d14fd08bad788c9421128098a3890d	1663745907000000	1664350707000000	1727422707000000	1822030707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x0e45d91b9094f60271dc77677883f27132202b8fd18716bc4f77246622017418bc1503dab1de33a7fa2d66b43b5acd7c23b8e6d4b2fd4cf718c676147b65c6c4	1	0	\\x000000010000000000800003e06a438965c025edfdc637215fbd2916df94bd248f7289a63ddc89e1085e33876754ad111abd200eee57ea95554f5544fa1911de1f4af60c11f8de91234b15d3ec146322b1d0c307d6eade9feaa4104848ea22350035c1fb456d90c393663b7bb0151546ae85e83230c945688bcaea60e08b04510cf85d42a76b57ffb143e221010001	\\xe4c0b7c4a4c1079a2043b7a8cc9fbb0e48f532f0990b0f0e690c3bf4a80ea70375cfc8dd032cd2f77a6ae81f78ee141d03deeb90602da62486f6ac70ee5ba003	1663745907000000	1664350707000000	1727422707000000	1822030707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x0f39427354adbe8d2fdddb4af42db250b666ed321b3c69bca9e0eb26a3adf1cf6bbe45cc0789d2583137d5cf88b7f46b197b0f89702fd21399edc1508d7f7873	1	0	\\x000000010000000000800003e0489fef040f6356762bea9bc9f245ae3e82c3e6447fee37c921df4789ae89ef12a549727a2ac46b7f6c86f11be89544be03fb546b2cde2d773e6e8af89b8d6658f9cf40dec51d59b0988e94e818a56609782719f041bd67e97acc629d09d699cd54a88718c00d40ab89aec4f94b8e8bd5f1a5f2e5bb56d54ac1a2514b6f969f010001	\\x53bb398ce379c8dc1612862a037e5f66dc60bd8c9a3a489e8d79ef8d68b7d58f73691bd45fa70b28b7d728bb7189cf79d6ebec342854b09a5a183a918ff37c04	1638961407000000	1639566207000000	1702638207000000	1797246207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x14415f738567d4759dcbb9765624cd744516e3a82115d44113db9698712a0dd3ebd6a02fc688ef698158cd487451712324a0c6965b310fa05b16d186c11b0eea	1	0	\\x000000010000000000800003ea15f6416dff513922f6d18faceaa66f2f529804419b4f945026330a72616292e7fd2f9aefff885e2e21fcf0b9061d05118ebe1c73513a219713fdd824662b0cc219e30700af3f9c3f1302a892e79362d0a3f9f5a88a72ba205df0d254a0b162d4ee20ca9d10bcdf8f1429c396c8e0eb1bb918983fb38249c45e21eea36022cf010001	\\x820f39c04638c220b20a1207a46cd9aa478b3922f35009280ce4616973de8eaea0229426cd88a209cdcfc4ce1557efccd076b126fe2a0a63a6e3a982a5435a07	1659514407000000	1660119207000000	1723191207000000	1817799207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x1a61bfe7bdb02a0293fe86e6432d005367c4d8c6dcff837faf8c883e7535a22bbd501ff00f94e2bd1d785b1972b6faff67ddd8f2f52fc5c9389299b1d1aca30a	1	0	\\x000000010000000000800003af03ec407d75aaa5c96e2ad933a36a8e8464172df8cd5c6830bd22659df24de94b0c62e9c65e593b63d4cdd069c13c416e8f744061d751aa0fc5961aaeb6ab11c1312c4f1f2ff1a73fe8e873e118a00dbf753278c2a7f153af4de0deda4620fc906a42a640bafa26b69f4d80fbd415040f8dd6c41adc9b901a5399cd7ac2f981010001	\\x1264f8a1789ecee34d4adc565e383f24f16a9f702f43546a5b5e42f95a8faf71cbb3d9ed5d51b8c90392654c5ff6c9ce8bcd1c05fa9b5d75da7496f761d9890a	1663141407000000	1663746207000000	1726818207000000	1821426207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x1c19bc3ec30196c755b0b783166deddeb076650a39bea9b7012b2bf333eac993cd7b27ca0d3b33d9dd64bff35c660324127983a65e0ff770bf66a923dbbc774a	1	0	\\x000000010000000000800003a99874984f6d2a4d961de107e21f2e87880c581aaca76fb954bd861babfa34abb098de91532d5bb4e66682ea5312902ffd0362cce2e65ebda71b7de902126119b14590bc9b480980df1c385fd0ad014fff40cb0f7d037e84d242a175204618345d54d020d376e87824b6ea8d3296b5990fd1d3b890528d59ea22b2c093462b99010001	\\xa68914f0f708d3466be4fa8de26c7544d3b98a8ea05b4940a1cfdfce22496568bab86a17260d3c0a934919abe129726bf1826d10527adb798d31113e465f3900	1666768407000000	1667373207000000	1730445207000000	1825053207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x1ecd193bbd6f272a328e9fb633870b1190469c0a526308ee34e08765d66f2a6814695073db37bd71556e4433e7673dd2d92c1f4fc798c78a52bbc6d52ffb3eae	1	0	\\x000000010000000000800003bfb61ce1504086cb8602f09ed30726f50cc818ff62919a5f8238cbc342e8669578f18fbd52e707fa0116135766640f298bad209db5a4003734be68bfe932274a60d0cee76b03fdac131d12941fac3f2907bdb2d3118f96a905da4b30d5691b6d740218e9d5703854a721abce31fcba447efa87b025e220872b1a0f7d83cd1929010001	\\x5e06e975e049e649a92a963e35b8947d784e36ff633704813618c3fc1e2ec0db60cf775db3664b596830f99fccf82d38866f7d71e56cd04e0d13a35fa2a22906	1649842407000000	1650447207000000	1713519207000000	1808127207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
133	\\x1e85a80703801ede10b3db8159ab6fbe589b6aa85d88340bda44a8ed78cd1d44088bdbff51f33079e32b3f2bfd6e08df4b70a5c43b6538bd2946832487744b2b	1	0	\\x000000010000000000800003ed3581a9b050552800d1b1eb1e1a22308b890dcde2956d46b3349e6c1b0228a504fbcae811a6c93bf1d51c5998264848a09bf90375373a1940de1c9c184cc816e19a698d82c480037afb1e6aef0734d24240943eb4946668ba4adb29fcd784233e17c1d36b1cdcd14b02c4bed74f42c506abdce1aa61b6e43aee76512a8718bf010001	\\x0f0d2a273340c7a0aeb572b81eb0970e08436bc860f68cb985735e586314d6a6304931150191f96349bf546a21f95762101502745aedaf4019e55d086de3c803	1664954907000000	1665559707000000	1728631707000000	1823239707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x200d360ce14c043039c867d013d3c7a635f8e3fdd1154823156147a00949dd8067efaeab8c640a233e04bdc3e34ee67da16bd86d849faae6d72bfd2128822aa6	1	0	\\x000000010000000000800003aa3558995ed48a7aa6eb2783e30c142f32922e5bccf8d922eb413e94f0fd324333c424a880e5ba8a51fd28e57ef3dc8025594df71167f4b095906d142b54c6ac39007e44935789af6c68c29f101e8b12b9a708b5bb7ceb6ac2f34ac53ba3598c4bf3c1d880bdfec3d4dd2b251861a3c473e8e5a6e59b758fb2261b230b17d513010001	\\xeb4bfa0aa732d504aa10d23a11cbd515f13b6546fc31cd14b263c68cc8043ba8b263e7fc595468fbd1d64f739c14cb951b74f054a88e7a4217656aed6c05ed02	1646215407000000	1646820207000000	1709892207000000	1804500207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x219da360804fd1bb2c3dd5b1f60e89489cec06b0058aa8011a97eca8da01dfc77219286d39ceb330501442b5c7551936835d1ef164d17c9993731f1f8c46db17	1	0	\\x000000010000000000800003c14eb6cb966212ac9cc3ac1d085b36a521190de27f67b54c565ee37d919c299baa87df24947f0ca2ad43eb986a47e5da3fd9639e73079bc234c4ae6dfd325d7b74fbd9dec74f200c70eaea91d486de572c010e152d587e0831b3741c90769ae280bb9d888e78bb3c83dea88939585c4f598c6ca657b78e0c47ebe6dd55b25083010001	\\xb82da326d3d50d8d7157d94016968744cfd6b20e5224e8f6ec28773aebbc8fdc0875ad0ecabd879cbf16fa8aa2adef7a1e9ba276c602c111c1a9ed4f64d1ac02	1667372907000000	1667977707000000	1731049707000000	1825657707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x22654a329b94c15c36e145a22f2c79482331f047e1a9dcc7da5219d1dde505d53f2676c0079be85599eb68ca4edb888b740f85e5636a21f7a2daab37d3f712b3	1	0	\\x000000010000000000800003d92272ce2a68f4cf499f7603223ffdb4d9ce31f8f826200320863e50c3b95d48a49d0fdeb4409f6525efa8498db736524db370e1891c27f4fc5721d955ed74a315946795bcd975b30a77faf31eea187d22d90e23022785ee6187da12ea7cb67ea77f2cf2067edf224ad47642a81556a79775d006bd32d721276c301c31a6f287010001	\\x662b047298fa4e886cde31508c1487aab11e7fb58bcfefaf9f75c227a0daf453dfd5feacee613094aa96027af11d6b9086cf574451550d251fb7345d33a3a601	1655282907000000	1655887707000000	1718959707000000	1813567707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x223de7651ffbc593024c412cd41687230b076e65261303270b0fb415b37636d59f5277511d1373b30d16c9e3db6ed9fd5e47c65ac947b804eec902aa90eef005	1	0	\\x0000000100000000008000039dffc9045d3c0af1b10c3385a8b55b031c4634211e2803b1a11ab51eb0145bb56a543565cb334c4706be9903852f5ddc144cf5f95bd1e41d96986ad4cdae70e4df623a7b859f6ea926659bec8345f99d530aa4b88b80ad32c15e0ab0a64342bbfff336a812dffdfe16302207aca8c670406bb0f9c24bc49c182e3ded56d477bd010001	\\xbdcce7ad7e16439a46d0eea6e456bba0cd8a8509a30746be7932e7ee257645056d695966c0d885119e86487c2038d1fa683cdbce6467581972b659f5b1717a02	1640774907000000	1641379707000000	1704451707000000	1799059707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x2281463600a2be40da4c1f20225dc54a3246941ce26a94394f28eba8c65b77c4843d06db4675ebe087b4edef81664c86394105d2a3c0b4aa040e2812513e2d0a	1	0	\\x000000010000000000800003c9a5fd76f4352caa8ac5d0698ac2fb14f2e87d19c9ec3af6e2cea251180ba1dc4b8f743d20e843615a2656e0aa2b292aff6cc71adbe08608a231bfc577fe00a5d03e69b869a709a82f1129fb53487384a1121e752c7394edee4dc5899092a023e5ef14dd42bbc5c3ecbeac71587dfc62a38a93215c06dda22542902ce2b1dd5f010001	\\x897f5d7ce3f62b01f114ab78898a268eae4fe5aa915d3fe12dd81f77586cf02e14fe9d59cdcc4686240422675f1a625df67dc773bd8385a0e231113a7d5ca80b	1666768407000000	1667373207000000	1730445207000000	1825053207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x26796ec6c42987fcefffcadf2d82c2e5617c39063d9bf03760e39f38de8613501dc24ba2871aa2943153c930079615f645634f96ed2e58c58a4f9cb915c89d3c	1	0	\\x000000010000000000800003d7b7eb8418618c6862c749c0a5e1697359cdc29da6868403809bd41f281781ee9f5c6f1894c932088789ab79199856d2c5e0535bcc84a0240fb678be5a543d921ddca37e541a2c631973d60e5289ca3e241c8137afdd7061f7d3a4b4348a54a3f01616b2c709cfeba3e7463c017aec680d6e55ff21b47c5896f8c20aa387f2e3010001	\\x8fff2f5a26698681445280a03a64292a2b197317b66072d52f1c24dbe1c681158386d7cd6fa7957156b549efbf9720c9162ebedf31162328bf9c6545d1652304	1639565907000000	1640170707000000	1703242707000000	1797850707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x28a5cf15b0dbd07ed999731ce6c45e2caeabaac57d0e98f489c289a089b0792cda4aa95d74d0d48e0a51c625671efe2e589f79a0d503e506af870afb652b6988	1	0	\\x000000010000000000800003ac7d9e9144feaa347da5084c48f0aea712c994de7057a53217f573ce5160edbc16a225c0f1d4c847f9b7964dadceace4c7eda733dc17dffc944a1f48ba8bb99594c1bf26f30130703e81a1f6417d8a01e4f4d4e9be4363e4ca17bd4694d28bacabf57517e2d143573c15449c40d5ccc566f1fab09cccb7304d0acc2620da76a3010001	\\x8c91ab04561f245fc8ac10dfe174c84aec07fde72a67e4758a7df9ba1f88ab94fde053732524dbc847ccc71b5bae07d8d0edf26c9eeabcdfb722a96f7458fe0e	1661327907000000	1661932707000000	1725004707000000	1819612707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x2ad1fcad9164b8187c2c80e4718503e2da367d1baca43886cf7270ff431afee2ef942cc7cdb9ccbe751be02b97b3c339026fdef00e73a1d4c7a4f26f07fe84c8	1	0	\\x000000010000000000800003b89e2514cd90eb04292fecb4c62b662aa6ce2d593ebfb0c7a5eab771cc1ebb7a5f57f3079fd0f4a28d3cc86eda4487f3d806aa7c1f8d757f9fc0d3ceb2ced76f19f7ba2cf9f3278dc59f6fe864df43f466a0705be5b3ce68c8608d2b296c100510e8dd3b8a595d05b579a059744605b8119e2cb2201418e12cb513d065e31b5b010001	\\xb484c74aca2f717caa5ebb8eb8e049ecc8f262b16bbda5e2bcdc631e5706beaf2e1d3a6381771384319a36348718d492090413573927aaf381769c79806b4707	1659514407000000	1660119207000000	1723191207000000	1817799207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x2df55749f82c6c3babe4ea950439be13436d788da36beac3a790679d4c344dd5d660e4f439fd0b637e71a16f344eb24c96ad51080af330deca310b6a5909d99e	1	0	\\x000000010000000000800003c17dd3f71096b68e6ad72181b2a13dec350b53f8f888d5d32af1da4d2a8504a0fd579c7837ff9be585e1cd547d969fc2142c8ec89272b517dc2594e2c6e54bed0da1b917b4c6464afcfe490f898de177bcf0eb18c866f6b1361ca51b4ca2a2723bd865f5950287c97451f8ea4c3b9e56a852493fe1b5119bf31ddf1ca18c6403010001	\\xb69a0cefad9c044f9c3079125ee26aebf8f3b88f0d9b5f537644040a74562bdc125bc4dd910b86ce62d6cfb2f323f2b62281ccd8309779451b74083644b4c102	1663745907000000	1664350707000000	1727422707000000	1822030707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x35c50ebaa84a5f5efaf79d1087449c8ecfe64029d3ef59cc612db7f623958062824293f9c5e4123f925b69bfbb825012a0fc8b1a5677a1bcee97673782928950	1	0	\\x000000010000000000800003f0d8caba37052691c1618a7e1a9f0b81d139925d8c2c96abcff30c02be154af9fa2e83777fd06d2ab346a5a2a2c4b274cde546c564ee5a8cf564858f4f6d9cf87386bf14eda190a25f00867e308a82d48b6ef89144fb2966419d9a6995957280d5ffe37bacc3048e0580b5c5ac2528f681fa40dfc8f84c2be2ff3a0846479a99010001	\\x7fd7827aa9ad91b91d81e1a5076f3a6334dd21c57512c16fba7b5881716f7f5b26f85c924afec43ba0f4cc3ee8e3edecf60466736485949c3fdd30f0541cb505	1642588407000000	1643193207000000	1706265207000000	1800873207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x3b71724482c2d496cbb897313d28020a959936bad8d70ca727881f197eaa0b03983d602cec09a8a8a1fe9dfd3a3dceaa09770c24cfff42c6575193457c31bc7b	1	0	\\x000000010000000000800003e9da4a2e0b1ff2d0e379a94dc39fa56510a3f0709a1924f6a7983d7001e2772ee39b1d60345fce7f71a34166c31131c152be117f5b14b00c4cccae2634c1accfe9bedc38fce71e85b8d1d5506afc3b86046ceed22403cace09cdfa154aa9dd98daae3ae3aa3b4fdb45c8c835f1b21eb742380747828b5ba76d25447c35fc8a2f010001	\\x0e4652b40a057be76cb123f4cb428375d11c39d8e9540c37cd532edccf65c06c84c664945d59b9d2067f10f81de66502aee3a2d34c26e59bfdf6e94fc349b701	1669186407000000	1669791207000000	1732863207000000	1827471207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x3b19d2d1428347fd05e35c58ae3c3d4e0a7b2392ce38ef5c74ff8ae21947acbcc0ebbc7b1a72644fad6aa01b1fb89899b73d4beeeb8fd84ef419317d018ee23e	1	0	\\x000000010000000000800003a41fcaafa604b58a264d3cf2ed565d2ca56414bb29b624605ef8238d62a6a86373b51c6d9903f273ceb429a8409d47f43e34fad5975774ce7d2f837a38fb61090ab8e2052e0e75cec29131052cc5b5732b91f69e7a68ba216ca2ed4ec65b8a4c9c81914e66d43abec1ee58e6036fd3055c02b05d78274c7d422ee295e24f0c4f010001	\\x43957db5692d0497109c672cc1e2bca1a4f946f12a4a284ef13680cc3230619bbc07ddc48c83bfc08467cb31024329c5162876f7a15f77eb2cc8f19314935c00	1646819907000000	1647424707000000	1710496707000000	1805104707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x3b0538514309afe7bcccb988cecfe1c20de1d80819fca633f4efd3e576f9a82f5c462263e2714c515857513710cc3ce10f0e15e475f8336039e2de19a7c92dd8	1	0	\\x000000010000000000800003db5710dc3151a4e70ea67e49193e56fb9ac723f99827f6be4f9079c96a5f8d68831cda5e1043b9abc92f97ec0fc7da904212d8c13e678cb3d4e580f6253ec5a47ad4988572eb1230b0bb2cd59e01d4cd43a9d75ef10b79cd1d152dbfaa22b5d6ba17d9cdc33a8f65d819cc38fc727d52998136b80bff6d9d9a06bc8594f7bcbd010001	\\x9f3715af2f3f60018e05b6e1bb3e9c5e9bb9b6e3d0a1f325e82cbd5f302ba1a3a93fead90f1bb4631885cde69dc802ebbdf2a844bb8e52ae29da73e3c72e9106	1669790907000000	1670395707000000	1733467707000000	1828075707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x3c153d98df912ecc17335f02b6575ee9f142657b0fefadc6728c4cc44757d44922cdd2667241d0cf0f1ef569bccaff90426312a76840e56b3f3186d60d49ef5a	1	0	\\x000000010000000000800003ad77e0d4e733607704a6fb4385a5dd5a5cd9b40ae98f461ee476d1388b6c22bb204b77ca7aa91bcc94e8869d064072ca9b9d844ff4064fd147077a8a3e8eeb172ccb6c9a6f2ad4c9e035481acaa93eb62d7eab5499a5540aded04719de55ed9e1908517295394d5d9e8815ce3837fc2323b4545409548f118ea5c039abea6c3d010001	\\xddb35904559a095c7763d310ca49294c4586deadb00c63903e1c6b59ccdd35cf70212675f59a8e64442d41b06d1c32dab7de989cedf9f7bb3cfb33c484b1d00b	1669790907000000	1670395707000000	1733467707000000	1828075707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x44fd941afa07c18df42f7989043111430ccc9ffa3826295b27269c4fe481f6f6cd5471956504fde2b2053f3a8b7b05ac2dcfb64191a4d7f89ebd42cbcba36800	1	0	\\x000000010000000000800003ebb0eff4cec291c93b6db5c710166525302d7a8b8392ab2c7c308888963c472085efec3fcca13f823a4c41c215cc76c3da7deaa79454b4568bdee58f052dfd004d10cf9915a90e282dd13396411d4ae6dd9cb0a4f4d037184c303419d266758a36854d8181fd3a5bf3ffa951162c3ff1da82c85066502ba80fc44818831bf4e7010001	\\xb9ef40cc8db5c8388d64a5f5d878ef4511037aed9d06c055de27f230de8d8bc3cf9d4f9f691c7aa42d1f09e28de97625fa70a32e99138000352c8cd238fdb50b	1647424407000000	1648029207000000	1711101207000000	1805709207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x44812904b811f3a5e58148c07ca5b6d752e68b913ea803e42c5cc774e5ed1ecb88e19f1a3b7c8c37034f0bef7d5220034325836f6291803c8bb2d5f7355f8042	1	0	\\x000000010000000000800003c0f0b14e8f71607c8920d01553014f2d5e3660a1e94a4e550dd6c29b7840161c11d25857cb3ec355432698552864ef6cbf6e36bbde8923d0da057f478a62aecaf244ff795c23105dbb7b3790af9d32821644820f6f2464380ed358ada2fa58d17dc4b5c71178678fac9c04d5d9661349d7ed955b1050d1779fdfd6a62e6bccab010001	\\x1f4860762174caca2427325554de1ad6fe76a52928396a05280543db3c2460b31947bd35a50dd849a0389e16bbb166e6d6892da8af45a9ac2647b28fd15e6c0e	1652864907000000	1653469707000000	1716541707000000	1811149707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
150	\\x4ac14919e01b54f014aff517ec18f98c8d19f1ffa7a7305c8a7dc65fe0dfe13162fb6af7cc0c59a5eb53f737686e32adc5741fbef64825e02822f1577d57d41e	1	0	\\x000000010000000000800003a657b550da3a10fbae5dd729f5e4fc974dc5548cfafaa16982a26e5a2b6b6bba350e59e3096beb47e0bc69b1ff9174a5cebec9bfe38348ce4f3ed65bf70278514cbd244c65a92bd34fff2d6eb81969a7e23729421f657c2abeeb831bed23f99897e950e3477c92711d2fc03f38b6007b0fe44afcbae6fdea8871c9479fee815f010001	\\xae3b46d99dc3a629eac69651323839c4bd8e687271e0cf3440c8f47735c757116ff582a7ca42bc644f0ee6b7db0ed7620bbca07d81ac5b959bcc9205f4257605	1651051407000000	1651656207000000	1714728207000000	1809336207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x4c1d539c7d10b99534846377a2f8185ca1ba74a924e522dc7e14c422abf6bfa7ca5ef28958cbcb9fb4029b46a6fd5f40372a7ba6ae756485b2a99d6911052a99	1	0	\\x000000010000000000800003ba1b32321db443b4632afdeb725c22e9ad686cd361f1c1b664981a4412ae0db787488867b8acb921c72eed12d2b2a84fa10fb3f6b460cbe672fcd3038abd8d4400b3acd4b11b8d08e563253693be68cde2e06c8c1df70d8c964afc4d324e805fed719db5eb99e478539fe084ed0deaa1ab7953de1d0e629b7a9bd387a2f33dbf010001	\\x7b32f7328b261ebdaa66040e07fe2f2979f63ee662a9686a2e958c3c0c912bbd23ea3c7c1da97121e51382f7c43c80e63c4fa4cc9f9029fffe34350ba3f54304	1657700907000000	1658305707000000	1721377707000000	1815985707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x537975678597678314da43fc3dfbe27cdfbc2642e8361a150d35a0c3d5b80883e3520a8295c51c6a9f997ca58957164e38e43a1c7d6ba850ab5609b0856e00d7	1	0	\\x000000010000000000800003d216eacd09b957220d6af41d1c4be5285cad3dc3c64c632bff9704027d430a95726b3655fadc0e9a83ccc2bf32e0006712938ba0c37c76344b8dce1534347a76f38adff15e8e9a7be143cd5ac4abe1209faa19f0e29ae3990647373742a04621ef4b425e0cd300eec3339f3019fa31b82cacba95ac93bb62f0ae3f9d4dc1f89d010001	\\xb9f940460a3ce2936a03c322f4a5045592fbf3de97988f72d581e1c4865d0037854fcd9c89f0f84047dc8f8383d6d797014a6463bf1f0f88ef43e1874c9be20f	1654678407000000	1655283207000000	1718355207000000	1812963207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x56858ce35bfdbf6f7be5a299ee079dc75f4e50d684b0c979d2d3912b1bcb92d8f7039196f30d64741769d0e3e8a04c698218412d0093c18b2e60b376e35c598b	1	0	\\x000000010000000000800003e3879ebe3387a2a66c480b2efb26c3185fa488cc6880aa3748b1ac071309ab897de16ba14ac7ef3b1a34ebc7431bb2b45cc8b30a14ba744175e6a090d9bf0176cc2ad8ed504504dbe4c7001a123e4ad0697be436827ff8ed9ec52f6c1799907247ae5be23fc4bc41b5c745b81ddd754fd4adbb7a3ff38bcb5321b6beb159e993010001	\\xa01f5d84c67573ebc1570a0b551e0657b61cd45e928bc02e4352c875ead571d04d5ca0638e4efecc3ec7211721f86b92bec94f36e920dd48f62b427a2afe090a	1668581907000000	1669186707000000	1732258707000000	1826866707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x5755ef2eeb0340832e5a47adbeafe519c3ab59420207a710249a2c800ac8f2d5fa64221237c960b43001b614d7e0152225970a29f729602473e99a8840f1a40d	1	0	\\x000000010000000000800003bcf1fef5ed05fd1ad804066ac45e276b32d859ff28fced9b24cac6aa82917dbf1948108740fcc5106f63b59a27ddbc6ff92c7b8e1bd96f754c216c1a3255fc46c378eb2004ae76f7955bf800eafef2c9c5d483a03d80fc1eef21105e08911b363771bb303b7d83960b17f6490ba3cf48c44ffbfa9aff430015ed3647affaba6f010001	\\xe3c6665c78f7e5abbb9dc1050d85a9bb684989ff4df855766924c536ec6802cb76c95d69bf201ad8e2d4998a484a7134f9701071edb43f5c186e8bbfaf00be0f	1662536907000000	1663141707000000	1726213707000000	1820821707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x588931b9d0d2c7eeb96e9e597d0da5642a9b300e2d32cce8d6cdaf6f835f6f4460772e67c214fb85ae658d79d4ded7dc5a3a6f8b94772b926f6db6db903b7160	1	0	\\x000000010000000000800003cb16fad8b255abf924afac96190e9320f1a8af3c9f72bdbc77f6cccbe593b90b5324ac70551ce0d98d20d81e3a6e5f3b3141476bfb213dd305eb43e394f5ffe95d3085fa69e94aac63c113ca01181e1138a001574f9eadf4dedc0afe15613ab5c493a6a99ee92ff09df681b0939445d506e48e34747adb58f75789e27a5d7247010001	\\x7fdeade2c24e8ec82ce37d519339decc2679c35e312679fc64066b3d1c1eaeaca6695c4dd60f141127838f978824c5f58cf2e64715d17e88b038a93e5116440f	1638356907000000	1638961707000000	1702033707000000	1796641707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x623d228eebb27aaf940fcce68ef85081ccd0697c8e3ab3f0e367957ad9a00fb80b39e27894e3acf496772e278cfc6f114b2163f2ec843062c69d9b20d1d4d285	1	0	\\x000000010000000000800003c690f8b9629b8ea065e9aeacca17233cdf7a327b6960ae7141c196af68db87df87589373a93b971a7e0b304c6d0409e9f06b94ae88628b1ff198d96a448c6ab1d8652eb19388e11043619ee3621a77fc6ab5f0426ca50dd49e19f45d6b35cf0cc9dba41c52d7abbb5464c8e18da68c8017f7ee4c04f5a40dc24acc1afeddf2d1010001	\\xe9540fe34e30aa38232fdd504a02057ee9535b590fd937cf3d98c57d6dd059d133bd23e17ea62c34cc88eda675d0e005e15f4012a99b33a64334fb706116af07	1651051407000000	1651656207000000	1714728207000000	1809336207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x6309a1bd9a269a819a9531343d1be703e84b9ad2ab9c7840f1bb77616ddb502026b88ce44722ae1782463a3e1246c3a91d4074ed32fda54ff4cc2a850bd777b8	1	0	\\x000000010000000000800003cc92c4f4f8bf70cdc9e6f237a48af057f6d4b597a07e340a1c4beb2ca6a42672b492e15fc3724b1a6d65337253a6db7d2c690384aebd6542b8d0d3505e97815f11afc0c3c42096013cafee596058e05649270aba53f7697eac0e9cb8367bc65f569bd56159ef64dd30606ed5b432bbd13ef5e1cb5ad1f7a0d53c104acdb3205b010001	\\x6a935a9ec43660023349dd4985cc39a4dfdf4114531ae3f2ef1d88aca316b8600dec8a54379ff468789b7b4e20cb70f412a90aac96bbbc6d59e06a97863cce0c	1649237907000000	1649842707000000	1712914707000000	1807522707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
158	\\x63c58c60a12fa1c505e176ef6e5caf55f66ac2bb1323682ce57b5a050c9605b9f6b38a8e1efcfff5c35e2d3651cd930d2aaa016c51592a47e6c7fcc296e4e102	1	0	\\x000000010000000000800003c5408cdb91dafba446646d1e9c535c62449d92aace1bb0f16b1ed2ee17a97d68716d172e075fab13f912d95108bff287e704a6490deb79b766536c9c45dab40219dca7853bc1597610ef5508e221d383a07af025dae469e94923da72f104ef524629d472bef46d3604453d7b7a156265464868830d303d45373d007fdf650bb1010001	\\xacbd18d2f99aa485a97e811cf7f210cc749132398b6c88ad7f49d994d703a3a4bf346c902a26672a53145be43382a2dc8d530f4a6235a4b4d27528921c2f2e04	1638356907000000	1638961707000000	1702033707000000	1796641707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x63a56d745ae4f2a8741729d7d88e7ba71ebfd096827b4a855fbb7632e5d0da8be78b19bb297bba225fe08692aa4470dc1d66e7cfd01f72c4e982bf93b452d454	1	0	\\x000000010000000000800003a73c31de8a0cafb15ccf2531af5be4af67ff64dfc0022aaf1b39522e6429dbad4383b1029c1231bdc07d8b69f7bdaa01dc4a8ceed531aa18ad64d1abcd236d0a31aebe9b9eacc0ec50861f7d55097be84f22318b20a6abd5340757f8ecb4d8e9fce9dd625cd4fe682cbf741af8b88af2a568b1045bb7438684e03b82e44f7bd1010001	\\x4737aa50d13d5a15e6a7a2451c344443336b45a6c845a871f1f050942e1b1f312a845e4173d1070fdfc0cb3a1ed5decab1ab496bb929b46486bdf30cf81a7c04	1666163907000000	1666768707000000	1729840707000000	1824448707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x6b49467955395d31cff84faf97a31157067b9ced45855d9a31c6741b025e65b60b126457bc18c08ac0681ccf0269e9265ced4131c7ce8807fd182c451ba8673a	1	0	\\x000000010000000000800003bb10ede28124101ec08c09d1a20092608b8142bbec7b046362918e76ff97182ec9275cec0c9819b7e7edca59465396b3a2a71c08a4d44aff84720ad5b5789b532b9e74e8be86e7d1a731f23cf602a073c5ca30672e53dfa5971f4f85c1db1dd65b0164cc60dba4734fd66452a4a1e39cc40035699d94c9ddf79c6f57ee2c064d010001	\\x168db54f481d831aaa096d7d04e47d2fb2270d91fcc557845e5b61323a04741e3a2c686d2a0a40b1a676973f9bf9a772eb1fc0cd5cf2fa895a76060584b25300	1639565907000000	1640170707000000	1703242707000000	1797850707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x70118c39152088cad055ff26947fa187daf522b244d776b990c70395aa38633f192dd86c18071d0746fadabed4783f15ee854f60f37b89de579c85a4f1be650e	1	0	\\x000000010000000000800003c17e8f321c627b2d35c5c138f486865aeea075741e0d5d8c218bb4dce7c84716c2de15c79e8d4d5e9152db41a94fabefcff0e1aca52f4bee859cc07d8b49445c639cfaf25dbb97b61fba6f70a3c28de7b1c498d13a9b5f34b76f361845809917538a188ea7965d2e55a0e1b460d3d125310bb0f45bc8e9102c048a84ad80d4f1010001	\\x932c75d56d5772d41bd0e93efbe1b8588f94854c15b4154d7cc4c5708c413ba145d2aaa1531654bab56f088e03baac710d66607c5bf24fcc3f483c9eb184b708	1647424407000000	1648029207000000	1711101207000000	1805709207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x70955d8e35de31943b19b675fa22ea8c0f262584795ffcd7e08856dbe7f4960c7944dd48337c5190cbb1f1681387ed76a3a28cf8e1ebf701b49b8956e17ccb2b	1	0	\\x000000010000000000800003cb15df4d27c9501339d05f63acbd9449fbf87139942ad26dcfa93415a82b41e72a138be180558b75915d20bb628604f7c3d04ba259d2a1eb2b724f17bff09570de9392455e8e63138a22edc611b57dace00a039f5305e4367787af31faabdc7cb3bf603690555bfa6c338c543753c4d750b29065fbd0ccce709030f3d842605d010001	\\x1b4ae8ba9c26c206cba1d42eda2a645903ca140b3429fc819b5c22b22d4c6dbe5792372c2e65b80ea83e3da9ff2ead1f999cca872ba33968f99d32989be3ca03	1647424407000000	1648029207000000	1711101207000000	1805709207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x722571c9cbd8dc3502514ace085450fa2da2b7129962f64989eb39a42e92845996afdfb9d32c76f2a1c635bae2fdd4c6089338a543b807da8de921fbb9c93877	1	0	\\x000000010000000000800003d715e14d5041b3da077b26b6aa3db33a6897dd44ad5c13d6d1894f0b26fc1553aca40ddc3c268cbb390ee6a2d6c38d95e13c9412b2694f47fbee2a71c7cc15e558836a4e93d899af7625566c428a0eb074bcfea07ebb19120df3f185534cca55e7fb56467f0acb853b2bb8265bb89020cb160145fcc5f57e15373adfd579f6f1010001	\\x08be0c1caea01eb881df9c91e58e33fd409310d0a73b00e4af01635cd674c68abd122cb21d4f33de06d089b4d4713edb33b6a99ae1f7aeb567605a39159ed409	1654073907000000	1654678707000000	1717750707000000	1812358707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x7339addc26f212ddce9a3d4df9468e6364965c445b53438f9aa42dcaf3f7b48928b012aeaec7d4d81ebf48730d06cd0465faa6b01919b5606fdb03650cb02ff8	1	0	\\x000000010000000000800003c5f92023eddcf9c4504f8e1ebd13b0f268415ca4a483b1e3978699fc9fa2ccb833692a2e6216cf53a922316342eca35526480691318cb66c96f19d087974a370351994753dfbfd322cf10511c18805893de7dc8b16b838fe4bfa242240ca4d31235375d21581f42a4537dd260327b947b76c00ba9782ad786f51e09a4ecd5827010001	\\xefb0c00a1ae75f2f12b80ad008b07dd1c6bb870541f7af2883efaaa6a8b92a5baa90fdcbd723cb2b48b28c087cbedab8e1ed95982cc833daba3c5f14b4a10e00	1667372907000000	1667977707000000	1731049707000000	1825657707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x75492fcb5acfbc10ca2f997b9ed8f196515cc27aec4270dc97f372bd6acc53e8575863be0874f9f9901b90e4dd99a05c250c112bd2b779ff1fb8293bac2f7a9f	1	0	\\x000000010000000000800003d8ee166a4b8769de3fe1277729f24ef75208951ea1164e9dee5af94f67c053dc0007b505232388f19c838ebe068a8e66f8b3812833b97fc8eb71c79b2d0bc76e2e5722c38c2c8053bc3d728e3052f425e543e1e3737e42fc0d5174d251fc4087db3fa32cbf8ef3b83b96449bdb5d4cabde32f283174cd5c947eb8610689166e1010001	\\x7c45a1d1b30c7442c8432f14a09f0cd95c2a5cc0b4e2f847f0e5852a2362e4b4748a96ebfaba9c7c25dd1525a1fdbd65944300f8eb18a288abc1024553078d06	1650446907000000	1651051707000000	1714123707000000	1808731707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x770d9aa768bb1da2421e8b1bf2aa3591f3a7aa312b97db7dad4e4daefd71ed7a5c4d9a882617596743de02a79890e5f4d7889d627f07ee667655665562af0a49	1	0	\\x000000010000000000800003c3e4e3d0e820a8ccd44fac95ba8bb4745ed947e6049ea78f9620362ddfede77b4843f4bff12a4c74d7af518cdf82296db585ddfb342e69208d0a7ee8a0d2a8ad7c69aafa444a3f610c7129f23dae75bab5ed4573dad71569ba248aeac4e27806626daa324fbb206c42b890718116997e7050ea82040201318287d328d089e443010001	\\x8d49f906bc900cda51e417dc75b111f173a06718d02fea68367b9e2395afdc808cabd0293010a7a697b2aa113fa3d8afc9764e1aba8c051887475f09d2220a0a	1664954907000000	1665559707000000	1728631707000000	1823239707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
167	\\x7701de84114b0ddb781293d93bee7d7d329f6ed2cc8efb0e02458a811604b7f9b039185765613fdfb7d4bdf759c1afd6ae41b12cba1f3d9e3550c6b2696ecc23	1	0	\\x000000010000000000800003b78e3c17eb31d21158f28f2912174b8ee50a708fb4ed9741aa33ae8ebe2a787858cffa1db937f7a255c18a3f1db8f6410dfb5b137ecae00bfb33ead3ef691a17eaf1b67ed60780ce3be567ca7d475071a94087fdf8fb527cd12b021587af7057692c3fff76281bb459c50d2787dfa726b4da02e4af8a37a89b96d2b30975ad27010001	\\x0db5d90c3c39645c39fdcb8e65b7fef91e7f9b29fc3aa5e10512b2657bc602cd1aa7233acb35d5bb46d46444b389e76899513438701d66c1d5913fc77e6c9a0c	1640774907000000	1641379707000000	1704451707000000	1799059707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x777136e6dfc8636ef4c597226540b50e19a61fbe86dce64d516c09588e9ec291b75939eef02cfc13810bfceb3818b5b829f289bda18008f8924132b310ca3d20	1	0	\\x000000010000000000800003ca7ac963b29fa6766d5a3a3163b51cda4c87d216ea2d5eee6108d5519a470246e8ac9a2ed3384f7894cb18cf001dd282b1addf6bcd6b910bf3a031a4dad3bb813b8b11f3e9504b0c89e63d47441e7ffe4b7d6047db23234834cd2a794205afd901a82e19c487c72c68cce6f49417a34e7cda46bec3b595c516b4e01a795bbf9d010001	\\xb569a74fb512309f5a034f5e4f40299bc484d0575397560ebfbe2085ce66752a8404d2740e245efdbde2d194b4ab2a71e625a43010a569054160e5c0b6626807	1640170407000000	1640775207000000	1703847207000000	1798455207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x780dd53e4c43ef8e74f4e6e62009e3588538f72774e8a45bf484315af12816275769659ca62341d1ddb687fc71c8e77973947a1d5f1774aa1ca6840e0f754ff8	1	0	\\x000000010000000000800003bcd405b746343e4515ead0d7265ba5f5b68fffe618555ed668a175da33190b0a4fd5106a946ebf33ac19c8892e0f8bd2502f1989c77b4d995241cf6604cef45ec10970961cebd5bed9d822becb4b0fc68593c424e23f67c89103ddcc347609f409a34b82417f581b62dcfac9f1709f6d979a24c6fda9b070b165f3c7732b4209010001	\\x0477edba16b630180a3b57c292319d6da3ce0407cd41a409d81c2012eddc4e3a19471d998bf6bd55cea935b330da3eccebd27631d257f7e281f8065c21b9b20b	1669186407000000	1669791207000000	1732863207000000	1827471207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x785d64eef1faa396b2525097432e98ec6f38f838fc7ce7f4e8152bf3b43ef0c41cb12cd797427c0fef8b1e9513fd86b8a8535fa26e262c2801823c286d9c5c02	1	0	\\x000000010000000000800003cbea7f6269a2b64434ed74d9d9604b58a637a1c403dbbfef1f0d015c6472f5bf4f102bc189557a02ffa99995687e0e8b5a04efced17abd4d00fe2f9f7527f10da079df4361cf0387ac4c09753796ab4ead27397f65a438816d912abf308fb8399d0faf4356cf468973a2e60bb593e4414fb80c1986583f96b2e090e0d82c0851010001	\\xdd4aa74e7a35f888df5ef46e53440c78d61fb31b3265be7db635e386bb52628928adb7baff4069b1cee2fd4e7aacd5e70acf3e3b8fb40494448bf2426a069f04	1664954907000000	1665559707000000	1728631707000000	1823239707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\x7949be9e088e1caec150c831cdee65cea98e316c23f8407063a86496c1c8579064798c98a23ab86e3cb83d05da5f8f07d89e88d3ce747c12b066ea0fff2a10b2	1	0	\\x000000010000000000800003b4a54ef9019dd8027b51620a786b256a7fc3b57b17ac026ab1eaf75c347cf42c6b7dd1ba17d1043ac9d1000ba866f8ece8068d2d456e930ad6dd0ea7267635e23b98513111614f64fee22c897473020c5e09d62bcbec22cb72719ab640782dd517ad45d0adebabb04f896548f972c97e477fe9aef328ecd74d6ecb7070e005f7010001	\\xab21068c3f8b2a322575a0d044b61bf8526723dfded50663cd3423305a25107400d50bd31d61b6da6b4a277f293d8523b5bb7e084fbbc9e61957c3d6f1afa401	1642588407000000	1643193207000000	1706265207000000	1800873207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x7bd913fcfb61f685347f44859392a30772971149abf1ddf0b14fd84c0fe59485acac0b83199fa89b938d4239d649f37015277d1d04db222f582b28341c27d5da	1	0	\\x000000010000000000800003c68b4483cc0cbb9f299af1a381aa994ded584db0ea24f97c963767384dccdfd03a2756f58cf40341f5c4d7c22e8f567e7e4b4ee5bfd719f47ba6db6efa354689297cdf3dee010135af157cb7cc9547051a79a6cd6fba6096196d0724e0ba9540b2859906253d45c866ca31e178478a8bddec3fbb4fa54de1b8e775e24b8f3fc9010001	\\x94e3cbcc79a6e7d05a26854f97d05651edc5a87b2047889c0907cf65d9dbe01539976ba86760c26f2e0396e8d01c4f97793c148547272a31455299866f306a05	1650446907000000	1651051707000000	1714123707000000	1808731707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x7f4d7e6ad484ef0ebac7b8a34b58a020d143bfcc2114f1c67c1631f86cc48e7bbe81872e0b0d5536a1ac5605eea5256d4b9c42b186f2a96308060a1a8c576144	1	0	\\x000000010000000000800003d5eb011c8c2b3f883a57cfcf9a15807b4dcd96d89293833a985fb51d3689c790663e0c1391dbd4462ab3a09e8359aa5e2a1311dd3edfdc8fe5492d7e5ff710e2cbf96dc6c6e500ecd42b7d0c778f6fc0bec354e6d39c5de7ac0d9a8ebecf1d04a9b5759150ff33cea36b4694d2dd7fef65a862f71fd348a290e13b82b2f47293010001	\\xbb1a96e6aeef7883fe4a7edcc73e5cf90a1d6ff9cae296c130c5d4438c5b1f8d644422f6f3831cdb44341aa4cfefa7f0e2ab72db4a306494711583d8fc1d0d06	1654073907000000	1654678707000000	1717750707000000	1812358707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x7f75dba5d780d2e4fed7f56693b8344b5ad885b9a7d8ed4b27af6c9e666926e5bba876f928d55e10d03e306caf6bc148bf4a23c3682b3aeae3357886efa74a81	1	0	\\x000000010000000000800003c98b1eacb09209c4aa1256cdcb6ee416ed0423c35ec1673bdc98016d5ffce1cecfaed920e679624001fce32c6a574d0ad158c3ce15b3192ce41029c83564527f1c1fe05775b516d60819b0ffd7943a092eb0db1fe80666398c271c4135cc98d1ceb4e58da44b340cefcea3d4a7754e198c4aa4c458d6b0109648841ba0d8d5e1010001	\\xcc01eba84a6dbdce0dbc457f28d2b7cd0657cdc48f82c09da625b1856fd5f38329ac394ef30341a6aeffb5484130d7f8718380b6aec316adc063fab9e407c50f	1664954907000000	1665559707000000	1728631707000000	1823239707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
175	\\x7fc9bf5940074bdf7a52544868f909fa71bc0956414d5737f556a03c933453c6a7721d3aa0f29a3d8cd95e39670522fa3179d1c282f67bb920a94ec3d98c8b2e	1	0	\\x000000010000000000800003b08c3b4b175fd51a991c927722187d5fad0d362ab1653d5ab1de7cdc67abada9f033707f60fd21ee9faa093101aed75678044246ac4a935dcbaa66f9733269af53983b3de4bdf4c04f97d3f556fe7ebb0c6218696fb2644c16f559344899f0ac6b4a2115daffa29822c481b6003657472b0c08ba3dda2913a7fd0cb8c5e1f19f010001	\\x855986ee3b06375677259f9f6c6974c9b335b2ec94f929de2a2a771f0c02b019652670754c98169fb047fc7866ea956c77f502dc8a46c1baed3e7b966c79210e	1641983907000000	1642588707000000	1705660707000000	1800268707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x83ad663dd2d4d8eac1936b456a96daff27bce3d30174b392a9afc1bf41dc79c9175aa5f330bb9719e64247f87ae938b00c5aca649555c06be3efa5115b790bce	1	0	\\x000000010000000000800003bda8d919008545b3bfa90f09693178ffaec7ad1976cb8aeb3446b231b8926caf5b2ef4341cb70bd257694c4c8938cbb9785f0ffa3eee071172339c1058ecf4bab21f74315c6392764176c7799a472b875ab3048dc4f9afe1bcd3ec3cfd52e6529e0e199076ceffe31b4bfb0e45972569951fdc35e6108a170939cd0bcaaaa7d7010001	\\xd54c226b036287a5872f470a29f54ecc99d1a222ef7cb27e081f45824567676304502d5102f92f366881ce1159c5f3c4849611c7e230f35a5b61cba994be3206	1660723407000000	1661328207000000	1724400207000000	1819008207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
177	\\x86e1795db0e3af41bc2c37e6fc03e7acc52a65d39fd7d4860654832133898dfd0de50bfc576b4adf815e36b4c0093042c7948a31610befed91583cd6d19e37c4	1	0	\\x000000010000000000800003c8fba1c15353d4686cc54649d31e04d429d20b69161c5c13e1cdd057a12170e181af31b4879f6ae9e3dd5eb4ceee1b7c1334f54a1bc8accb07d1c8d09938e0fd069722078f2cdab8d51b93378b491f10a800b07a6500b5403b7c23f975b469f038106cf3a4e2420b60e1384a0f46649ceb45f87585cc4ef65bb320250ee03ca7010001	\\xbd2d6d5d5a4d245061d693a08028079c194084e5c21fd2e58fa638cc94dea962c8b233779ab7220a52d3ae106d9522d78cfd1bfb23ad489bbf7f8b13a3b06f07	1651655907000000	1652260707000000	1715332707000000	1809940707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x8649c33cfc3d0a47f086ffd0cf7cb5afffe0e77a82c0c12cf24b0b5ba6f181aa38628501cb9b54823d8d7adef2c5bb21abc467a462cd113c04f58cc19178fe90	1	0	\\x000000010000000000800003bc1c78d1be04f6c39438d229529890263631c8e786998a41473443854d633dc4a2b84829351019902ee5799195c6aa2da71a214339a7f27d2a65b409e25a1530c71bf34825f3bc7363cd166c023a5872929407ea83bd4713f38931caa22fe4aee3c953aaa9245f2b5170f4706a4ad8cc323693af22303338cfd53bac6aab07e5010001	\\xdb5dc152d102bf1071a301d7ecdba68ce7142a7a2c6e5367fea735b24f8010fcdfa8b28d691efcfb81e031ee2b8414ac0f15e88c1de3b4e00898a70710164e09	1663141407000000	1663746207000000	1726818207000000	1821426207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x87bd9a29d5f416973725824f7ef209856bb17ff658c71efcc1edcd08455b2f6900139e13a8acf506944a405df42e719d707b2ffaf9199aa888055b6cc144c519	1	0	\\x000000010000000000800003c053a49a2429a5abf1e462856e2632e7a1124c49a82dc0074e60edca25ed18d5c7497fb12c54deaf2b0fc6e28474f066e3c4b8b927293025091f200a0d5039f988cd2216693d75a24a941e5cb464b22d7042a47c5e3c3a09addc8ee363e53f905be497465fb5097fd10e2b3552166d984bc8018518cda17c748cd537caaa8319010001	\\x44b76c2c0e6a2187c2b845948e87532c3a627c9f8fb8e45770b9b634e7aec38d7277962b8c5f9c19d00c37dcae11072f16e719c5b83ac5e7054deb7bb605c200	1641379407000000	1641984207000000	1705056207000000	1799664207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x884da637a3db48c4113230ef65b075d2d6e567dc1e2ab342686807e96efa122bff68f2b3547632197a121cfc0e98af407ffd9eaccf0ed82dc227245d489ea273	1	0	\\x000000010000000000800003c29b0d39de7314f9ed366f188e0857fc8d8d97212904bafc65447685189ca760dc9a7861ab114f45ec76d5d4cfc1c750797007d6e2428d6c2c57c5f98e003718bbc1990a6108b68f3b52d3b93227775eae616dd91751f51a8c1d5ffa3643032e81e0f18fb56678abf9dd99b365f1702067d192cc0ed7cfdd54646a1c776fe8d9010001	\\xde9ca5267a51949b95d19e369a125eb6353b5996e90d3353502eac8f4501f303312d7bb0788e703dbb80ad1caee9b866b6d8b355586d9d549110fd6b4dcd1f0e	1639565907000000	1640170707000000	1703242707000000	1797850707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\x8cb1fc2e1b3c6dda066a4d7be334a40508d2bd37b913e6fc134d2491abeb85a9f5f0e5a9012e9627af79b3a04d878aee14a35be29df80a781460ac625b6b2543	1	0	\\x000000010000000000800003e06dede90d259f9ca753fc963a67042fd3ac7009047af80d883884ba1a8223e12c36dd4e4ddae06575f9830a2bf7ba3ca56544fd26c7d8725fc3e2e597204ea416631d3175a0f6256a3a759487a7c5087461c495326ae1898f8b423e4feb7995ff08aeda248a875f6a3b2e084f5d5624178241ff9066ead72095774148fa4e7b010001	\\x84a82e70f26d13770990c138d9ede53c3f3314396fa23b11afba1b849a04e4db40e67f679f0243c4fdee56e2659ba3fe11700b02d642e29567571a9e0b435608	1645610907000000	1646215707000000	1709287707000000	1803895707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
182	\\x8ec92840dd0b7da113b1bf4afe8651ec90df09705c8d617b1eaa066829fcfba106ab7b4af2c187efdb9f51d64f1e886be135c1dcbb4bdef0bacd15d1b33f16b4	1	0	\\x000000010000000000800003e45134432b9f065f415f1c51154899a28e85916362662d688b14ac7e2264ca4a639a49f61d77a888b3cda81dd5c17666365cf9f6cdb55baf5262eb787ae2964ffa39e820529a96e517de0b9f40969c17f6caba5885e9befce9fe90004e7cfcc6f2fc464f93914ba2fc285868591dc828cca0bd33afb36d04b15fd7c32c524c85010001	\\x5aca22c46bcbaab38bf633cbabda05f8bf719f8474749edeb50472f9236b39067c2eec9a92340d1e129c513054de85413436cbd79512d7b008248c1180a0be0f	1661327907000000	1661932707000000	1725004707000000	1819612707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\x9451c52d45b48509e39bd81374c5557744d5f403c5e13a6bba191a0076e266f5396dcc8b59c6b9e040e6be598946741b84d5d4e98b9c819d1962543b9c45ed34	1	0	\\x000000010000000000800003ba221906e64a2ccab89b004de7e1e3cdb29493ceeeb9f54694552b14ac2b5fbaf82383d01aeb0261128bd8c23ae978f386b69a6ea2a1d76ef3679b9757352e30529b0eaa99fd1890adf8109605032dd5002923c4502926148e2c4a7971eb5709913aa1488dcbc184d60989c3252c72b030c672edeee1fcad084967780b3f054f010001	\\x78e834aa62f8f14283106b7d6c0178f7b0fd197e389874a77a08b6dff620849bdc5ed1e97b5fc13d01e944d68199d88f0aae2662cf54b9763769fdf099f3f805	1661932407000000	1662537207000000	1725609207000000	1820217207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\x9569ba34f046cad06ec35f74e0a960cda3c0943dcba873672bba2dea4986efb0b277d8f4487ec68d6e3faae11a93b6fa09af5762b8cdb0bf63b4c8956c946e3d	1	0	\\x000000010000000000800003a6a75f534bc5e36d034d84eac3820b76d8b2f1de3f8810456b270594a48b4032bbc5bbce0d36e9650c39e1ffb9d1a006560afd082d464b6039336da73d0a193b40ef239daf8f411974cb905bee3aa1dfad6a4c4c6bf2311ec1a398412357493c304bac455c5612a04b6dd1fcaf594918c0b901eb1dae97c53b0c6d23914db3f9010001	\\xba6f7fdf9cf45e75240c33de2dd18c45f2e144e1c402037bcecd30c98182506b1ce1b8b9c045b919747a1b903266d4ab66cb215c84044f6d2307b7d9145d7d01	1667977407000000	1668582207000000	1731654207000000	1826262207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\x9961f49a0ab4f26dc567d883930f9ee1d1e46d71e423aca7920674ec2be3e16d348a9fa0bc69ed700bf710483dc6faf58595bdc73dbfb60a261d88a2c0462119	1	0	\\x000000010000000000800003c792c93d77262aa3e2e3bc8facf6b8a1e67b2ad5f0ae32f40855b6f8aeb0b29ce21679cd675d062ed6c2467e39abb240758ba93a5c3f973de7b13b05822c91e3e089fe49a5732077803df607d6931ed307498de3d390c9dfb17b9bb2eda57a478e9912f16a34abdf4bb184e19a7d6f93cca491c3a4c4645de3b4918ad66d57bb010001	\\x47825a1fdd1081af41f356e2aa0e301df8c9824464214363f8bcaca565b0cc14f4241e23a6de02bd87e87adcb2e7b16601e2214abe87c2202cab80f06d0f4601	1663141407000000	1663746207000000	1726818207000000	1821426207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\x9b8db333229285b761c269bd75cf4b94caf8a134bd72ba33d8afb4d13704d8e1168339bbd3b199c04917d2b38c652d0d32403269c0fc3cd1760bd29a6b0edb75	1	0	\\x000000010000000000800003c4bce8e6acf6c0e941cb4a7f82e62b240e62d9f9487f7da14b3b5775fed139fdba54338702b15fb2c97727a04947cc2a4e17d1eec82c53cf3f794fbcc4756eed8fdecbe0ff1f811e0e1abaf6f58770761d8f38f0a0dc32fdc80fae61f6fbb6f6f6315e15585c04b3807373b04bcd8ecb7dc51bc43760f216815ab416313cd4b7010001	\\xd1deea13941ba31da3c224c673dd98d048be61fd223fc827388dab1cea1026665ff86cdad5154cb38f55c349cfcdae6ffbff7f04bf1ca732ff0df8c3a4e4d00f	1661327907000000	1661932707000000	1725004707000000	1819612707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xa0096bb1371ae97b911965dcb4b1b03080b96e95fd85a187ba8c796aa9a0ef7ebdd89f3d54b374fef4827daa229d26cce958ac625db60302a1437d5df8ed260b	1	0	\\x000000010000000000800003b8785d8aabc06554ce231ee933037b64138911ef6727365799d5f5051b4556f0ba62f62daf3940c7e7857cb921a2b483343c969980fc9ba16af6c7a438d2627461c20e29c3da5c4f44d0e80f7126681ceefec184a1f0477671b8b43bbb7d7ef1a76d2b6de3a39194ce954c03c2b9ba3be2642e9a90e7fcebad27f1555cdee84d010001	\\x9994d80ec769e62e11c8b3af0ffa3edeb6a9fd8c84bec47a5d591068d380283520d7b2125b5f0c4512245b77d2e443437bff06326f371a471293beb8d4edbd07	1660118907000000	1660723707000000	1723795707000000	1818403707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xa25540f0a493a3054260c56ead265f0b492df98323e24bea67b01f59e72215f90f0fbe81230df0ccc8dab02ff553f11583cba835036caaebcf19bbf96438021b	1	0	\\x000000010000000000800003af85469b40f9b98e338bacd750aba83657a8b09fdd19bd6214cd26d5da89253535862041c6f4c256c225a21420d1ba438bacc43756358f6d763c088d527334cc0ccc0fc7b88278bc19a518f54b97b260ada2b30e5351acdcc762c851c6730f7a0488af2c7d975eb8a67ba960635ec6d15f58a26279ddf3bc41a688a0050bd693010001	\\x221eee7c967fe7c18c47dddbc785add42220d25c605d05d88a5393508b241eadc2ad31ea5a9b38f6e104b83ba828273f4f9a29d10fe6efb31b595c0b8457f60e	1662536907000000	1663141707000000	1726213707000000	1820821707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xa91929be7a78f0b313a34983c7c0f5ab271830f850467e5c8926c89bc53ff41976c2acc0d6f8f11ab08d35f04675033e027736d7655399e0945fae35226283a4	1	0	\\x000000010000000000800003d8e51528ce6d4dd17178ef49cea6148e9d9fa26a979db8eec6d1c4607c44ccb99051d9d3e5f1c2e50021393bc1942ba114c864c1063fc6c069aed16fa0eed5b052d576839d8cddde00982a61e60894700ce9c5cc4ea965190b9368722d3f69f4d47025538e139e6d4d9be40946acb48b11a45eec16faef10b0d8c49e2c17b7df010001	\\xe8ca6795361dc9055d85b538558a2db1b05e6a137cce3325cd0af4aa4a997f46136bd90799ea3610ae29b4ea789287562f96524064390df27cafe964576b0907	1646215407000000	1646820207000000	1709892207000000	1804500207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xac9935d79fe1115e173b3ee01063b07be455f89597330783ddfc91f7479fe5358eefebe24c91efe61a15137b5bc3a6e465c5d4d2ae967eb3c9b3b49e1fd4695e	1	0	\\x000000010000000000800003b3a23d70c4420a70b87024eca9cb0b119a4c54628361a85240366d7542cff4907ca05edc32243805f3439b794a5f62f41bae82973fa113d732d8be7623489334e0a2c56693f036a7bc0f96baac08f90f5a51d5db9d623b848cb7a11c2e53b0083037d2f9ecf9b990ad223ab3ad28fef8ae90a57e18675ca8ba7654b865309199010001	\\x129f6e0e8bb2640fbe051892eda82748fbdc2bd1b9d855b4f5efe95727b226f85bcc1cca1fdd8a4cc64fac8c2c627f8780cc3a29109f3bdfb70de2aca6e2e906	1658909907000000	1659514707000000	1722586707000000	1817194707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xad01ac8e902b74e7c83a43ce5f87130b7a18e265eb89ce612c6f60ede4ec07f699fef60f1f02674ca1bf4c2c6c159ef4cf42f3fc1c3f1a72128ca3d477448ebd	1	0	\\x000000010000000000800003c588303a95ab215e828b00464ca52dd273ec85d2cd62935dacd03ee706738fadf376ade3179f1619dc2a5000046bccb7e044518c53a22c3175fd43354e25f311b86ef4c47c4098cb155221f64b06dec6b94cd03ed7d60fba73803a023f8b98f0051c25cd97cdaec4e17cb93194b0821439c1f99f8151e8c7ac0711edaff91b8d010001	\\xf45f1be18dc62d9fc176d48278698cbf62002ddc0da1899e52ba403ff00c57bc914d1a29d869f348af003c71350bb18560e559305c5c42364e15d26a7fa8350b	1645610907000000	1646215707000000	1709287707000000	1803895707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xb1eda56df8407fb48bcfc817ad0ce523d8c8455e13580b232a616655da731e12cb2287317667f4e86ca50001e0c3b14b68fc668d5769864734c33f8d364925bf	1	0	\\x000000010000000000800003bad25ddda31cdae0352b19ae4d9c9de1e5a964df089b025e0b9a057badf739838d8f023296b8df06b7e6eb11a29f04d1e1b5628fbb51aa9e166e60f1c67281fdca1055a71496b6d7ce10852ce4361eb61c3c7884d12420d800228cca779b742d15d3fa7c21a579c08dd75f5c48b0b97ef89cc28968a2bec5adabc3c953749b59010001	\\x0d47d89ba8966cd4f370d4f5b7dbd008940ac3b1833374eb8bc1f7f6bf3cf71022826d2ab751f8e354d90653fb457dafb37b176b3b1cdd427a5808b379e99306	1646215407000000	1646820207000000	1709892207000000	1804500207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xb6254cc2ef251314d79e3bce3bd65c301f1ecf94924463b1c9f96111b4837fa865851ef3cd3ef083d702d70361298b44cb42a47c109622577a1b231302671b56	1	0	\\x000000010000000000800003cbd8fbd36c8bbb948d49de237e969a10a26d905ebb22a3c7dac5a9538e64bc29b37d1c75477bbb4ea542bdaa9002cd45e66e17b012b40e9ff1ea9ee110afdb028156ebef11c758d0d058800a3772907f035e11caccd3d8b7efc157539df08b374876ff2dda19a694b47001bde5c3faacbdfce750f2f030f336eb2ae16e9d310d010001	\\x3d93d5c1074fbc14da93fc9b10250b9fb2285721a9e07c6a92bc24fee2e1a2f05c199db56f34f1860d8f89488ba1577b144424f95b3a478b39b924aa11cec602	1638961407000000	1639566207000000	1702638207000000	1797246207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xbe310f287faaf9a81f93db3f942a3fcd420bd70d2023fbd329eb77d761ada67ce377b1667cc560865649b0f39b9158f2e4ffab357a9f2f7132dfb929c1111169	1	0	\\x000000010000000000800003f74ab7f2be6f064d68bfef2353d08277513b1366999ad831c22937f13bf64b137aa064a2f49e6e9049db321fa85650e2f80f984f5a8dc2c5a2cecea884ddbf45b2ab01abff4e98463ebc3a269e0bf223dfa1686b32aa7cff429059a281d947b9f44ffc00c891a64acbbd7ea8c0502011238437239989aa3ca410391565af860f010001	\\x13ee44560d3c37eab9c9f9d76a676e639225bc5169146a76d49df6e02764aa022988656ad1dceece9a82e7a3232450e869007f6408f40b142911078281fc9d03	1642588407000000	1643193207000000	1706265207000000	1800873207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xc12d932fdd294f70682fab6bc941018548cd3b9a029fba0c022e3690f971cd5ac7495524e54881be329bede1d74f74278bb5924800b46137323d318fcbc84259	1	0	\\x000000010000000000800003b663038a3bf27e5fc53d28b256547b10c814b28c5b4041be45f725b0ac33267c9afbad1da56be39a4601927b58b081b40486d91937a46421bd597c80cf0d4e6efc024e1f97e2afe176f8c780105d18fc55d594fcf9c349f0340fa24290a8638bfb2f8bc272aafa2aac234c382e9f46611b1fff02a18f295298360bb05ac669d7010001	\\x959fede8585950c509a22f8d0ed2dd2f9122267452003879c395d9510b647508d563224986ff6affa96f779e7e77a20d2e44064bb1819eff32141ca8e30fe605	1642588407000000	1643193207000000	1706265207000000	1800873207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc31916090e230e355a693105b6289ef60b7bb0cc3f455c912e8bf94f035db38bdc9209acacbe0226c79b910a11a367e7065efb232907c1adaebd33b97b04b48e	1	0	\\x000000010000000000800003cbb04543ea74b38d7d45289160109cd3ac5af21ceff406c0234c42b3e936d62fc79f13e7fb33b22cbc289acbfb479085ff1063290fb001c51a3414603bd78e20b925275aa33c26c591d5369d3f41010b79eaf74bb3eea2d0decb6032ef774e00f88634c1b9e6912cd63575f871040a3218809f6c4182532af352bb57fc33a08d010001	\\x32f7b27d2f3bacbd2d07dc66001866c1e334f18ee58648d66abbfe55d665622a7b803a8d0c5993c5dca9fa642648e6191fa0d91b0c06ffb3abb5b41ba3449d03	1643192907000000	1643797707000000	1706869707000000	1801477707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xc56db23178c248b92aaf72a057228861ec2c91510fa83b1be1e1afebe3d4625f1e7080e9c49e2c5af6ed22f40e8aa43539f7caefecc4bc4de4f406434e043763	1	0	\\x0000000100000000008000039e3483c36811f629ba2196d23fe7be0d4fdcf3f5609c80b08c18840cae3269c0e98f51ec913eac4d7d11d07fff4c87a875476d33725495330a1385f502fed976b276d6ad016acc14f3dbe8f51da4aad13a117de29e0388999347da6d3f32c755df7c2e75ced27e7a93084d5757f8c71d86767d2e862309bfb586c748eaebc55d010001	\\x35028c8485d6878f6557f9fdeadbc4ee72542ccc4b9e2ebe6c6bd08b2db0f8026f8f8075fde46e3dfcd0d3e8f68d524353424f0e207fac118a4205cc6bcdae04	1669790907000000	1670395707000000	1733467707000000	1828075707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
198	\\xc911eb63ddf4593e2bf22ec8fcdb7c14b110a94bbda5b665120154a658a277af41823dec12932027679ff673d4c044810a99b4c4750041b58505106f7a5c791a	1	0	\\x000000010000000000800003bdc7488e0bc43ba83017618ec98c1cb30c861c4aefe825973ec6262751617bbfbdd953d667b024415cd16265a0adbed7499226e5acc703880d4af291580262ad2bb70b941d330b904889de31100fe283fc2ae65fee94a1aa6217e48d038545cfd59c88e4e6014b0b1bb3e059a1e27d62efc1d474304c01effa1a707f5d178ed7010001	\\x2cea549813d2778703d0e018068a3c3029803b3406d9677386f7f111607920efd16db21337a210e9cfd74fe3c5480ecca28cad8339078e61fc8fbc11b8186d0c	1638961407000000	1639566207000000	1702638207000000	1797246207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xcab189344176559c67fe9b69832cefde8c50c24f06505e0bb555d9e03c69cee9a7f512934444cbe117e2769118922d7867c8e1944f5b57dad45f00b0b7592ce5	1	0	\\x000000010000000000800003e4fdb48b143c74665c7f682be74116e360fbf9e7b54b9b248deaeede0c2f60ad1e9daac2b1557d3e2d67fac63149eb01d5f21d81b5f7475f7a32968c404781e5dc2665f72adfbedebc2471677c5b2352e851f18f617d341267d8f14000ad65de47fc34356dfc0b4bcb98df87da25da972f056281a493d41a6c18ce904bc64bf1010001	\\xc2c8c367b01c3d19d460562efb08f192433e6046559ec6b221a1c23d8e7ee5adcefbc27277042cb9a85629fc47ebf8601d3b16f9634420aa7364e827d7b10b0d	1661932407000000	1662537207000000	1725609207000000	1820217207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xcae1f7f7a294307c77c78e13b28a1d1099edd87274c2402f8afc9494d19f02c5fb6902dd0ccc2be61e64bfee81cffd99f984eda0a288623d111f7436d4f2c2e7	1	0	\\x000000010000000000800003a19b66d3675adc0029fc68de5d2ed14e0f536f82f9444faef10af20c164157a2b371b32839c91328abd7e94a2b61de0d0daa7d6ec034ce103ed7bb246788f81f3bc45f6bb987d99cfa77d394b932e650a2f635f87e7cd5c98bdc9e3af554ff10db0830e27643d287fdff7ab01ba1cb33abc6e4b69e70a89e1a652d021286ccfb010001	\\x2699b998e0c51c2e6a5612b0c93e47d9aac9eab8e6339e31a00bee67ac2f3fecaf3b9118cd4ca152c06074a0fc6e5e063f20400bd734564139a147708e29870f	1651051407000000	1651656207000000	1714728207000000	1809336207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xd109847edf2c15c28716ffcc43683e14ca70e6af7d807506e528d8dbff992db7193f6199578acfefe7b0d4ce676ec92e73616280705d0fab16a364c91b3e8e78	1	0	\\x000000010000000000800003a5240d18b96d39802421cabb9340091b848b9df1eba37b7d34d32baf89a5595738193665d07e7ba7f4cfe9ee4b9635b8b4b62305ed8e763bc24bab6d15116d21aa3c183105bae5ca1e65f11a8667e1b4ddbed603e988eb5ce0eaf51ef69857818bd8df6134c7cb6e4fadc65e162b151f679bded110d8e915ac161a8b8b7c7e91010001	\\x659918487bdb43be6000b7641716030f6006a13f7ebff6e91d2d26975602c5f1ee42501f2fa7e8e3040799430a0dc441daf129eae7ea47bc33afc09ed6bd160b	1659514407000000	1660119207000000	1723191207000000	1817799207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xd169281b8ffb6b8992677044f70a8ef5cef056ca1a050d91bc3e298e106623cd2a75acc49f252b0436de1a25f21e1005c9e2894df5a6209c9bb6dcfc20800931	1	0	\\x000000010000000000800003c4ee7feb23063cbd5e66d04f41bad02709f28528e0d9ad6606ee8229269add7184db4fbb000fdaa2b1e90424bdd75948e5048a7c0dc6e180381b2f371d137a9a59ffc497956c49cb4fabdb9bb2b12990570cc1ef6bab6d33bf61882aa52d7abf7be72bfd6f1aac8e00d43702f2f6b35b5e5b9b5a4926e85489201e1c4fe51e41010001	\\xb7f8ad3396cfcafd3015c92fd85f26f229c6ef75a38ee5087eecae29207cda8be81622e8d9e8bf4f200a9c1fd6e2856237abdfa17460f6452a3146eaac80d104	1652864907000000	1653469707000000	1716541707000000	1811149707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xd5ad4dab8f19fc53d72e7c9c74a5486ecff31cef8db021c27221e94fd8f2c9973f6c3fc9c4af94918a8ea70470377eff295bc08bb66acfaba5de12674386250f	1	0	\\x000000010000000000800003c89645a167333b134819e4ffdc80d30defe143a9b0178d165a36edd0ea03d6eb4a8dc1761b1acee1908c3d90c232c1d7921f0f912e1bf00133662911d2dde6de8daa9a36872bf05cb46aa5313c4d71426ec102d09d80a9dc1e81905217dd39c4a0d478a543e3ae29f27da9b50a7f90c24cefc26dd043daa12b95264ea89813e7010001	\\x0d6297c12b6d68c515cf180966d900fb45bd06a160e84e6acfb731c8b3b623ce02789c73be32004900184637b19333a3cf1d99730acf0c1d77a740a346fad603	1649237907000000	1649842707000000	1712914707000000	1807522707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
204	\\xd9112270dd7b467cf5ca8da31a72887c94573720edd6a4b40bcd3f43e3357c869bff87e0a4fb0b8da02100ca5f246bfb3eb2b33ce4ca3bfd610dd7f6ceddfecf	1	0	\\x0000000100000000008000039dda3c5983f7302093a61b51a1f528f4aead6c7b9d9d748bf0ea729a10d49292640e29c0bf80f7bd7b9d2aeeda6948040a5faa6ee60bc87de2fda9b74c06fb0ad4e581a9b28e7ee2b8be811182b4e6c8905332f40accd2da7586b86546638f6cef174b154eae46577b7fb19fa4e3213257673904d0318a4be814dc2dae8e0581010001	\\xe6e13b60364a87f16a597f7c192ef2aa984a4772dad28435a996f0f91f8b5d80cb3cb89cd1940d554ba9f7c34595f7499d89218dd57eda34765cba1af6a62b07	1657700907000000	1658305707000000	1721377707000000	1815985707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xdb31ee2110df3886c129d528195e115c05012cc8c29d684f8fa2f824e260a4accdfc308932b6b72a780331b2edc871f9cd521f334cebcb41892db7b30ca38c1a	1	0	\\x000000010000000000800003b3b768256321e3d9de9fd4dcfcbf591e857aab71f02e6a0cacedfc859c0b1e288c9458b868aa5b3c0ce2e5f1b67c7471df57602a00b41b4d312b187a5ac4a0c2d2b2e35b9dc3a2c420858daa5c649b0bec219fddd3742aa65e5eed9f2da4b1f68116ab22a929acd1b63af3e1135ac02f78773555ca9ec4c0aa6291583e41a005010001	\\x509e08d9ae41241e9e7c8ec354f521dc28c4d9cd05f2ee95db0951809a7a476969782acf2395eaffec9d5525c48bb2ad181747a19cc967ba35cc26fc1a3b2206	1652260407000000	1652865207000000	1715937207000000	1810545207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xddc11b18c5d1eaab5b62df0d494bf3b28fc82f81828c8f3ea7fcedecf71958e9b69a7fdf80cf12cb3bd862d0e381914969cdfb95221c4bf1301888eb54607521	1	0	\\x000000010000000000800003c8d3e097e0b87243acfba162a38a90887555feeddc355bfdd641a2a4bb51d1b8c1581794fbd63bc28b92c3f0ef678089cc44f7fa5d843f6ed4ed91fc297e9dcda5c47103f1bbbda0ab23516feeb5e6d22caa240a149f2b305b3b29b523f7805001efb0e2184e43a5990dd6263db6e81cf70ae4b9ff46ad2ed88e36caa6cd3029010001	\\x515ae5e6c6245a8d33c58380539ae73e68d289aff7644a086131a0bad64ce959a1740e2d15410673776910bc8558c75c41e1fd0ddfef99f5e90068d4b9e6ce0b	1655282907000000	1655887707000000	1718959707000000	1813567707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xe1a1dd9014c648585430977632b5e346dd69df35bc96c11622839f4b42f7e493dd5eb3bcc5fc2cf95c53e85b3710a7c0df239eb92e2e23a7cd26f65564a045f1	1	0	\\x000000010000000000800003d8f013b31b3a2465cc3ff29cded45608df4aa24ab94c05ebf4ee1cb38d6e8bbb810eca8b37fb449228fcc2b6447afb2cf456be1a87edc3e96eac0438b6d9baffc40dba97b819d705d13f12fb847e0ae5ef94a3506806d80c65cd7cc1fa453d88c085e90dc60fa34a37732044615c31117d36d20216c918e437b2b6f1adb8d7db010001	\\x8183cb294bdf1b201c87c11d5ad9b7f0088276a8a56e07fc8961035e5acfd15c934f4c26374633bbe399a568078fad51e7c0d837479aad23ac38ea009bdf4a0c	1667977407000000	1668582207000000	1731654207000000	1826262207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xe255f4982d9b4785dbc70e1e4f2b060f334b2c90c36380525ac2700b50f0e1e329d44122ea75d335808cec8ff81877786aeb75195ac672205de5184ae6104338	1	0	\\x0000000100000000008000039f9d77732f5606fcfc048eb5dceba09faddbe1a67790b7c3b44be159bdbd92220249900bfa9bb43be1672276085a4f36f9e4ccef5c9508fc469a4a2327b343039d81d3236830488cb399d3ddd55f2a8d63c613e3fbab52425381e547b52e393a04deb431f812200b59b1251d3c63de2f16b0f3204d7cdd03c54c248ff1dbcaab010001	\\x44d566d08ae79f2372e0066010ba2024315617883ff75b7e283fcef0cde2ac92d40f7aadc1cee7a109dc8d5565a4e9f6230024083569c382305338be42b48303	1663745907000000	1664350707000000	1727422707000000	1822030707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xe3cd6788b9be307dea9267b4e306c461f9a429126a32ab2bce1e3d9f95ef4e3e548bd6f64b2738e1094bbf19003718de33ec89d9fb404ecc2b0685b11f77a691	1	0	\\x000000010000000000800003a9c042b5f132333425b478312fe94c1514be56cc46f5015d10a1106bd7d49764ccadb2456f9d747c74c7ecd1dfe428c3c6fda6e366f73cec06af290db0a9f05b0b96138dcfc06b57e156e76f79abb472fdf088e09158c716372339e4d95de691e06eccf89facc7b7787d5cb46b8cd25d4c7c0f3a0301b18c06fc55337492e67d010001	\\x4ca4e008af40ddc8af642dae461a7feb1b27f7228d76349fc5c961b4224c59745c399a996d4d5816afb8a757192014c6678ee588874cdf26106b6076d8beb60c	1661327907000000	1661932707000000	1725004707000000	1819612707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xe499159b9663afe4a8772e284c16f79fc2e4a7bdbfad78a1c2b0d8440b5c0147cf77ae266124f70deebffbba3541220c3120b1f352674f25acfc332a19ddc568	1	0	\\x000000010000000000800003aca77ed3a57001f1b5acb5995fadb6ebd98545ae4cce25ea6b1f9c355e2252885113d945b8e2dbc55fd4dd46261edbad1ff2449c2f5aab5c73c0b09bd2a7939860433c754e34a9a281ff5f0145baf73a7c2156a91b71e32c6c9e570864904d4aad1432e9e1bf3235826d0d530f7a5b317ec70cd9ded09847102c7c0e838e6261010001	\\xdfd31c90da1e5f8ce16992e3ba14d4d7c45ebf1f92536ad2219728df39fbb8338cab8a52b7a9cb5424f6d87b611cead70a3463aa4ad617949cff03a25e91870f	1640170407000000	1640775207000000	1703847207000000	1798455207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xe60d96444f6b955443e17dc9894affc74eec98c934c3b68db954ee11324ae62c9dab772b80d2b6ffd9aaa9f7229c96806b4284f6c1ee6f9ad6e18e5fece5c2c3	1	0	\\x000000010000000000800003d9848fba9984d9ff2070053d778ef7af94629bab191fcc93f15991745361214bf6ea15e0458de68e12dca25e07f6e316c2f70e8ea2f0a759ac908d6796c77799e8a00d4f662f61b54b5a53f1d5514fa3aed968c07e7ab0379868d8c4c2cbbffbaceaee6bf65a15ab2a4b2cc9f348a5a125a23c4b6591bc91c7061c262582a49b010001	\\x770a44a4d0b72d76937e071473b8631d895f70dc1f6b706e3d37b06ef4a09ebdb3d67bbb906bac047d3c58faae4d81ea27a4fd52701b95c02cc6b73c14807a0c	1645006407000000	1645611207000000	1708683207000000	1803291207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
212	\\xe6a1ff563df017dae2134e68521bd21fbb05c44c02005be4865fa8cee31c7f1ae0f368408e0ac773891abaa42fdcdd8b322a598010ca0ab9bac81a3986fea2cc	1	0	\\x000000010000000000800003bddd5da982c364d1ce8f9f4f21a7e4a442d48cbbf69d827a9365a3d406683f950e33d25fdfba2d1e914aebb6dd6f5d58bee1219b6c9f081f2be208c9f3ca0474e68a67334c4385601c491d886ee49bad25e8f5b467ba48c2ece302b385c5c0d6dad697ea4e7eb6fe1c954d1294c3ed1e07083b31b70f8f65592c9604b12d8713010001	\\x5e8cf583bdf481b03c4431bc5c9e92214fe1b71e00253239959f21b71e955bf161112568fb3e7b47e6648225d3034fc0fea7dcf58df35419e00c71a9e0ad9504	1641983907000000	1642588707000000	1705660707000000	1800268707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xe6e1b1e4eb7618428c93882f567ee7637b05673755943a2a354d2557b505ff33ad2fe5e5d98e5dd7ae6a5e010582b3b7c7abe4ecf2af71d7afbb89eddf27203a	1	0	\\x000000010000000000800003f9277c06dcafe96c96bc30c0dc654be168df7f85ca4d241ed2f0e1035a542d821aa82d1bca651e2a0f05900cf7d3827f7c39293c936604b41171c83ed42d587194d3d3a4e3eb63d245e72142b230ed4d28f98866b6136a3afabd1c59ab70686afc3bb16b5e01ad515afb3a6438a062723547ae403f48e011574c87b205f2c2a1010001	\\x70846cec056321de8a3de71d37d4c879319022d4822695214e3d39fe5bce787802cc135bf751e42f35aab5ea40e26f47739b566893c193c3d5d084f19a5db801	1668581907000000	1669186707000000	1732258707000000	1826866707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xf50985ce7378d191f347f05fe1422f98217b8e0684a0bd91999c9ec10ff482955f38f2f177c618a239d500c35dbc0bdf37646b9844c80954d87bea1398f6054c	1	0	\\x000000010000000000800003b834cd76e4d0474354e33cdea07d5609b36265a712cb4b63a83b3218b236dd2e0606355e3df305c354331326c7afca5f6c42714437ba766d2df1400b59b7e7a1206202054226f21b4d3f2def732bb93d373f87432a30f509e3c45ee9a74438692fb2659ead577e77c53749eeda583af33f4a3f5666495c2aefe313a616d61c7f010001	\\xdbe51c3bd7db39bd721c881ed561edab5f9c35e5ef8909ba03516840d487ea7b8c0e6a11f75bbfcf4b1eb7a7c9ef823e7eaeedb710bbe5335719ab40c9aa5206	1655887407000000	1656492207000000	1719564207000000	1814172207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
215	\\xf7d997f3642fc4468a9665580bb46940f2547f616c2f1f77e2549cf59b4a449fcef1c25c916dfa1b87a64950db674ecb1369336858c9aa0e3fd9bdf08829d157	1	0	\\x000000010000000000800003de010eb45f6f07b101e2448a5318227ba186090f28a81764d3ce3f89e77dfe35967b8d0c38d9136c117deecdf9e332839db5c9268e5eafc487a1bfecc8ba08ac285a1ed617436a47ff29f31a16bede8f657ca47134117c126bc1be6aa52a6c5fd50df1d952714bd40d7ea77be65cdb292a1c3a111cebd80535de6dd046b85f2f010001	\\xb062dcd1afe4d98ef98a639484f64b195be1a202775a98925f27299901fcd16a648cdbf9e4ece63c49ce496720f8a816308d02352543df733407a45d183d4d02	1647424407000000	1648029207000000	1711101207000000	1805709207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xf729ec6bb2cc6814ce53d630750ff2ae97cc4ea5311d18cacc2a6b4125307cbf324c8a65da1947849a1f957f628a1b7f7146cf0813221164d331f33d0a3743c2	1	0	\\x000000010000000000800003c42c52ee18b4f7d4a85414881cd2fb415f717a7c6a3f1ca4d43230a4736a7c938056071ebd0580eea4845d950746216258db269f65b411e1be733bef029091b32d3e8d0ce6c10c90ff3c574d4764c86c25ff5c180740510e2b6d70f5e11337cba4af08210cf3ff5736acbecbeeb8fe91fbcc1476dc67e81aba5ad750d1da8dcb010001	\\xa91c59fc5c8a55f8a631c68db2ed7f825ec38bd2120cd0eec4d42a00185fa1128fa699c518e89afc85d6c3781abb16c8205a2875c28f74bf499a14ff14466200	1661932407000000	1662537207000000	1725609207000000	1820217207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\xfa919294afb1b77bba9ccd73ae5ffecae90a5081b7185c5a46b2f91cf6b16c5a7491967324d2b114a330a7874a8b177db8a5b024b741eb88509bc9a18cd0ec6b	1	0	\\x000000010000000000800003d56c08d05e42e816cb6be8c2ff52a2886bc6f0a7880868661fa26f66fd8f4066c1c366a442e3c16109462c2cc79483cfc2fd1e5c8f110c432b78630823666c62759f75f5d36253b1b757ef7d9b06c8bcac18fc30c9b85bf648decbdf25a74d292cd6ed94ab0493ef8f5178455646e0793bd58bdb469c0f6e10cf4d21968b6671010001	\\xff6000f8687eeb87ea901e764a0db976d929ebe3668c364f360563eeacf95fe9e2a437ba60e8549cd4c461df1e6ed4c8837e785dc1046a193aca6c919e929508	1660118907000000	1660723707000000	1723795707000000	1818403707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\x00125a1454a77aa34a81240e0a9449cbb1488ac32256d969653156286329dd3f4172af83de57595c68a39aafbf6d2dde3db82ba0b128151d3fcc6c822486c532	1	0	\\x000000010000000000800003b9dfa3aefe5127324b8edfd739dba7bda9353d244dc026ce31bc681ba0f3c56e98978bd663e66b6551d053bf3a23546255319a3b3b04893342a9cb5ea79a7c20ad9271600ea142c9764fbb736b85bfd99675faef9b350f1f79c9ddfee5ce85b9bff725a60042de5ebf5e821f9264255387fd59284741855baadcfee16dd22599010001	\\x91c7bd03a85a33063d41963d61fbd203d5754692755aba57c6f1e8adaa0ca6c580218791cf40194721b64404a15ce173b4d54c2b3d6bf1c2631f91bb0928030a	1653469407000000	1654074207000000	1717146207000000	1811754207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x02a6012d562301b8e61092590caa7cd999d3c6b81fac47dc77d4673d341717cf2921e341beb8ced80b62e14e5e2163f4cd421df22348e4b2ea4768433e3b8541	1	0	\\x000000010000000000800003adef82c1f953a5369d0c5563bde18faa756cc94c506db8ccbf699f4c0514d65843dd0326cb891d967b676c9a56770f099e87ea05eb880fe9e53be65ba30f6b30eee5cd470f11d7c43957c57c97ddeda096bd56a4169ccd460fd4e9ce7d346a0772aa17cc1bf2326b755e7ac0a4b651bc3a97f30bd5b1e459359084cb4269d4b1010001	\\x14caecad0b421802af513280bc5c53fbb5f8ae7f046ac89e682ecda738e7bae5ee45b4b2b4bc246f7a0c9ac2d648d843adab6ac0b91fd5f54b0d99bcd52dfa02	1653469407000000	1654074207000000	1717146207000000	1811754207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x02fa3c3e9de56e8e79448fadeca0d1725588152fcbf7cbaa3cd79bd947755a0b0ba7bff74a32796fdf98a5bcb7fa996aeab0734010fb7841c7b0e7b99601f37c	1	0	\\x000000010000000000800003c1b83dd2ec46b39ca8504c5aa48d12cd42bbc2c5277110e8748b340ab73ceab08cb247286f090149569ab7e74fa28a78876f0ecc7c54eddb3a75d99d853e0302c96391fa41fa6c5d46d19b115a9966fed822fa8b5b55d585b371c986528a59daf1171100dcecd44bbc124c647097bc9f8fef481041473787d66ba0f001eb599d010001	\\x0f544eb0762cb4d384194d3ff76d5420218ff162f6ef31b8bc370a59fbc7e448b490bfd4aaec09782292b51b5553f6c38035c4b7440167f58766507f344a150e	1645610907000000	1646215707000000	1709287707000000	1803895707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x02ee0b3c0929792003d1ff2424b732a48ba9f640e4f2b39fb23a693d6005cd2cecd9bf17a3422d6c0e9ab71fa88813d91598486fde2dcea64809e2b434b63658	1	0	\\x000000010000000000800003d0a697a69d074a155ba320295eef305a31c9ccd20d933d6b3bf9827500ba0fc4c3b0e49c56d6ecb9371a3f201b0929c87f97857d02c427935621204bc4c58c7ac39695f2f4af89e2c35a11444655fae82a57f02f826584bd54e0d579bdc58e8b40a9f4390e3052a0f845ed274c706eaaf87bae3c71e64d514d9120edf63de0ad010001	\\xfca0e752de39232fa51033943a48c988cfaf1518839600500d90627f9e53c1ccd99a16d7f7d9899b809ecae467883d9f6f686a5360dee626c34960cf1a01ad0d	1638961407000000	1639566207000000	1702638207000000	1797246207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x045aba5d8a13da62aa104c60f9303c30cc15dc8845e489e9a951585ac74e2031231a86d0038063a47f5fdeed7d2236f709dd39077e09a84581ab99e8ebc83d0b	1	0	\\x000000010000000000800003d217265cc9c0dbdc83eac8f1d67c06a289b22df92b8248396adc75f244581ce5a803ed9fba9c0149fdd259dbcccc9b8d8799ad16457c3e69ff7858f3cc7256b2ded2d9e4acc31c5c07178d8c75cdd4663d19bdc89b81dd5bb25df236b61bcec95fb7af3fe8a9da8ab21b613ece1e02c67a76f5c88c7a04c199a9330039fd37a1010001	\\xf103d45b19f9c1a3811e0ff776c2f773750676aa2bd5f29bda7a075e9b3d9886007c3e9ff4ec8ea80da2832de660aa86a8c500ce2e71aa0a89921e811ea47801	1667372907000000	1667977707000000	1731049707000000	1825657707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x07e22bdba146c10f658794f8c024f8633c4e55b6991376be39b36821688eb944da2dfd50a466a79d44f6de15ebf2bb229dfba84c52ea7abd7f2af0330dd0a0bb	1	0	\\x000000010000000000800003d17bba50fbdaadfc7291645cf7ab3ba6e1e6d942c94d1e04888ea59654c8e551df75e40cc037ccf7147237dd95ee0b7b293f338dd7d0d1e6b53c0a3299b5bb442bf2b0b5708b6de763ce9724d3a0320b637db222ecd937ca9a585a40a225d873f6d0170cc666eab435dcb37fc1edb1fc799628abe32149edb8af94c7e9a47c7b010001	\\xb5db937f476e6095d41615677d240255baa08cf99609cc2e2bcc24fed69e00e125fe8c50089e5f832432c2f37c392fc1a3bfacf3c639741ccd920441b0d2050d	1645006407000000	1645611207000000	1708683207000000	1803291207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x08fee60f3ef005eeaa63ca6f5905a87ba06286369200192a35bf7fce0ada972595bf4abbc78af36d4d1c56d74adc256f5fe9aaa4941ffde7ff18c687656f7e3d	1	0	\\x000000010000000000800003bd7c04f71b705c7e45052ac47a11c357bc44c14b4d579cf4045f9f6b697f1c17ece56e092875d3a7ffce468607ca147913063df988e8ac4df63448a065c02c5571a2ad353a8aa722fa81b4a1c927a76e3702dc3a52be4d0fb678f5eff7e1b51e3012a6a0dba54bc861dfe15ebae535c07636b6cd2bba5fabcaa61948bd250387010001	\\x33634f0041961cd5ddeb0d4a4d3a1686b4536b0659aa91edf690003addd53e6059a2c8099514420383283d49fc97cf76e34cd09749d2271c6d86fd32bfa9010b	1638356907000000	1638961707000000	1702033707000000	1796641707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\x0d7262c06fccbd30d6438e53f75b0a053ba4100e2503593c76d3173bb6d493d4d95eb50e8e9324345f4360c02ccff00b18011824c8af7cee94cac196ee98c6b6	1	0	\\x000000010000000000800003c2e8756b3df008c3c7850821bc42bbbab7633aecb55c7ac43f0d9a4249211b0bf9cb35f6020cc219890200a1e141a81e91b0e61c56363b94bb7b0648b6c6d114102df631db3a0ea50600d16df012776b6d1af70166ce2df9456cd9f0262fb349f71c88d78ab0918b426e79217363336c94271bb7239ac537254526204ac81387010001	\\xee246452d53acbe4eca8a68ae7ebae8efc0624f0cb2cf2df16a0f6a53077100d4a602e4874aafcde13defd2f0ca98b1a4c6d506f21059615e76f233951ed140c	1650446907000000	1651051707000000	1714123707000000	1808731707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x1386f2b5ffa41410cc46b0e725cab3e4b8c884bae6fd732794b9ee41809a0843df35a5cda11792bb819286bd23b81a092fe6c113b5a1ec27e975d08e865d846a	1	0	\\x000000010000000000800003dbe6c736e999be5d0af1dc3484fff5493dfd6201ecd042176bf1ad4ba38dfc2115eff74958dbb6ad4ca07910cd1dad733121ed21d757c1746a315e2b9a890dd4067c6e4d420f388f7591493fbb1e494594ad50957ce46dd4902c44a446ba37810a76731b94692d117a80ae9bacfe2d8e15f933f82342d28a9e0c2f9060e37d0f010001	\\xc1880d387cabb19d1d4a793a4906a8db6b981d2b07381c1b377e6f7335006698fac24bc1b86de30ed76c8631394028dd7d273e43d6dfe70c3d0a5e697f493b09	1662536907000000	1663141707000000	1726213707000000	1820821707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x18465ccbf0ac49c668ab384f4f4dee141d317d38c9bf8019bd01b85afc88d20355785fb30897f41214664368bcfb6555f75cb3ced2a5b13a21756ec0308575fc	1	0	\\x000000010000000000800003d770c2487079ba2ae8eb9e99bc8ce71c3b975b570fe09fd327b67c4f9eba6ba812ac81e3a95eed14e9e3226d55cff4cb38ca3c184bf42f46c3a0b00bfd6429450d73d0ce585cf6f9de17618ac35048e872005ed8a186ad1a197b0526a78e297beda4563156f2b1b67577d37d90a689dfc64d33b81665bd1649e7df60082e4ec7010001	\\x1e6d611ed44bbeb53540e6f219b670ff6b323e9877a8f617c5dbfd91d59261d20c843ce012a97e990548bc91612aba0dfad0e60375d518a9b0c02c0313844104	1651051407000000	1651656207000000	1714728207000000	1809336207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x19ea59f9aeb1f765e7a61582f3759bd4f18ec1c2003257a8351e36bf8b6655f2b057e87858d8a96cece03a7d3c4ccedf5ca7559bffce7090c151269e668a717b	1	0	\\x000000010000000000800003b8230dea99f666f382d71d274276038de81ebfb5e35fe6cb1ec65840fd762b6298f7408dec21c0c14dc3d4f118496feee3f183a72e2342eca4d1ac51e35f24381aab332d14621038f6f3309d12577b21107b6137c7f371dd45e43f4b50c8a78ffd4c9479d329ca81d5f5f5f2df439a7ff87b4b31b173d6980f7864dd7592ff3b010001	\\x8ef8cb8e306fec81c25512c80ab24c20a563fe130f2fbc8b1c64291691b66de6b960e9b0a368d5d538076d40b190f98535bbc1b38a95e5e9590af986c8827b01	1649237907000000	1649842707000000	1712914707000000	1807522707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x1a8ef1e8d8b254a98a03f43a0b829942a5eabc897cb6b08b02e8af70d47cdfc1205131e6bb3ef85a235d66be7bda56daf06cb5d7d355b7274e31ca9604a33c61	1	0	\\x000000010000000000800003d8a7d7af503c75517cb738f4e51942070f7b97b6e1eb575b6a0ea3c5a6adbe37dc1e0373a09bfc49ee15d36e3d8c4751eb3ea428f60656b4fcbeb28cd800cb66444ac45dae5014481c8db2dbb4f097ff96e20c4764dcdd8f461c6ba846c506ce4029a7e4f71fa891b4ccae4a2444d3a40131ec536548f1a5131377ec0760f1fd010001	\\x7168669f8143ad7fda8a8a61f583efa986af7f20137729ee0f5809890420d570c80a54cda30e9ac08ba39587a6f16a034c84d7ede70210cc6249ae44217b7102	1660723407000000	1661328207000000	1724400207000000	1819008207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
230	\\x1a6612b1b553fc142172379ee64db345b50cc413d37f5db2d80a5b573c9c687a1644d806c9512c5cde734b7286edf65dc9b52d291842e8831ebbcd35964adf6b	1	0	\\x000000010000000000800003d9ea53e79fccb2e652ad511e778a30307868bcc42f9467581fd828c8821c95dfcf6d4834b0ff1ba181e9324c73122587c7e7d89c5cca6028ab30275b789ee2dc69ccc0ae4c3e40e38b65fe9eaba865ffdc17a1b2fab1646b9e33a67517cbddcacbefc1a202909fa5792042d90e8c0ee5dd5c6be422d31c2168ceb474ece48eff010001	\\x3b3b10918c1af8adbd2ea015a03f6728118dd5b140edc73e25c84e361832ce80cc2c16f76b128265feb5a2f5fb282152b9d28a4160cdc7244f470b16beab8708	1645610907000000	1646215707000000	1709287707000000	1803895707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x1d6ed76d27239a844deb4cce5302c8bcf9dd9161ba88d73d5ba2a5cc848ea367c51b38679b64fe7139ce39ccc9efb2eb1e776fb222afaf20baae731a309094b0	1	0	\\x000000010000000000800003d7c32f8984b0d5966b6bdc95863b02ac40dcb4f43925c0aed1063a7b9715d530d5b5d55838d5102bdcf4551b1b92fe01ffaa118866f7a6fbf0b38f5309ac887b830da3acaf11ab3a0b0dbe9e508acd6883b55646a9eb9d77be6364bf3e25ee33e6496d12cefb4847ff3ec4f684a84084cc8fb6af5d493ae7d95e393c315cf583010001	\\x6421fee55a46288b89cb39cf4bf2ebebe59cc37361363aa3e37438af4b83dfea91b0648fd32173246efd69b06b1e17c0fcbfb0206f9b1ed6cb3ac65d838d820d	1669790907000000	1670395707000000	1733467707000000	1828075707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x1d123f3ef8e61a069f4b85115a5ae378d386f767b575204e76d7b28482497d31c0860e128571af711cbb82b1d23669d0a8d9b6d7421f85efab33ad2ce33b2920	1	0	\\x000000010000000000800003c90c299fbb4b374e3c6221b88b2470a684ea2cfb9cd57fdb1d4a9be5635627daa22fee57e923f2e7a5a24052367eeab4854af326f70b42f9ff18384b06316ee9dd67506de6ae1171a26adb0b5f332042b08979538e27f82aeae401a0fbf7e3948169df89b8a2bc25bf0423e5e0c2588a466569740c632cefc063d7be90a64cb5010001	\\x82de49b819da356515146d22eef202ce71bbb3baef71ea9184445985459321de0d9017b71f3a29b2a868aa1686060414078fc6bade15e6e34c7a285672faab06	1658909907000000	1659514707000000	1722586707000000	1817194707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x2266d9aaae00a3d8dd33b76f9f288c027f9c6b9ca51000f3e0b01e27a8d25708b6a201b29dcda02bd2f059ce72d741c2b7698be36cbd74e61252b119611b2763	1	0	\\x0000000100000000008000039fd006cbb0c907220480d4bf4a6313d0dbc5b7545d178efe66cc332e9cb1ca145f3a04abf6d1ea0486a9fca8e60e3400065db985c7ac0e159eb360f24c308faa6a9636b6a3daaa14f76e65b9045d567018dd88b1096b14cfe46eec86e747ce5f2330771071330f9f0166d4ca69e1ec38bfbba4d09774129a7930d7d9c2977c59010001	\\xfbb5839f59198052614df9eaa97f0eebe1390cd9442d7cfb3ea87b139e4962866df008b127b5108ae7e85850c6b753a855624b23c661af81056c3655048d2d08	1650446907000000	1651051707000000	1714123707000000	1808731707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x229228f81b99ac313290fa5d924ed7a51f822afd024585b1c5aa0a17a719fade0d092d99f1825dd835943f840a2a71279916d1cfda1e4bece80edf8b7614120a	1	0	\\x000000010000000000800003ce16edf3faab14dc280e2b8d36b4f8e569d4097a0322479bd860a179df771c69858a90da07c22b46ffa5141f90358fc6af77621fb9856a6a48e7328135552570487fdfedccde48a85ab20e9a58c208a78481a3ce2d0fe5ae4331b03d0c591391746517f2c3675a0350accb50b7d542483a96451e1397058fd5df35c606e63671010001	\\xf12c67a1dd176059ef4a5e540a370ec124c835b0fcc303599dfde1c45df4520f88c5302c3adfe5a625a3ff9782e6eeefa96b1ac57a9c91132c3bf0e267711b05	1666163907000000	1666768707000000	1729840707000000	1824448707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
235	\\x23ae1b32e5412ac8d69350a683c3ca5e8b079f00f3256c6a3ba9d3dc97c8df78814d8d2fedb8a978c00560fcc8bb9bcf3101fa56032db6766ae1f163a18ad45c	1	0	\\x0000000100000000008000039900be5acb85ee1002cb1088c63d004cf91fef13da06a5800210b94b4304156e0f16121cf08914e3e4911168351868dcaea43c6b5d34244712e8764981a5f91715882b5b6462edbab15b473922f3e3fb6afc8e5a0b495a7554c6e3f9ae5b9fa40f35948aa7455263420e10ee5247ff87d3b3992ffaac8393c6d5fff2e38e5713010001	\\xa4522c71aa0eafdb53c13dbd176c42fb96e8d8e814675235367b7558bd73506fd221df7e8a0ce531a60a9dd201d55dc5e175454f91d903fae05a9a835e13bb06	1666768407000000	1667373207000000	1730445207000000	1825053207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x2412ff56a20e86bf1099ff9efb9f9caa77f27c111d0ab250e33a460cb409f19c4cfb3a4fcbd9103d0a23c3f2f991535b2437177a46132c7d317b8d47b9e55fac	1	0	\\x000000010000000000800003d6af246230417a2a2f56e77b4c02aa1b2cc9b3a3c7787b5ddb27a172453a4e7745e18c1f8c89ac451b8b199e13e1110905cfce09b9bfc28ca43cf57a19c9fd1dc1c72220642b6bc6167a29fb205bf292fdf6fc200e640d6d423f85bab6c192cdb8282eadb1ba45e0ad51bce2f656dcad8220143c85571bbfa5b8940650f88fb1010001	\\x535e435646e7e13d8956096d8e4943c1de1d6b447f6a9c95c2a177c75f334295471b1a1577c58a4cc4826e8c50a6119a7eb575ed66e107b08d68340509d81b0b	1645006407000000	1645611207000000	1708683207000000	1803291207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x2582ac7a4c2d856dde3c631327e096b620bbeb5cee5f9a3b7d430e82ece98e8b072ccd97b117ca027c5274790ee4218490c60216d8b91f8b7122d38ffcae35e5	1	0	\\x000000010000000000800003c9822bc0cb70db7eae7120c6924d834294e5c3bbbf7ddf5b8f3aa55745a2eb6c0914497f7f5b5f8a656598f382cea07663d24a0d5446c6f438a33445efad0c649290c27f615c5db6956ea3dfe437d984e0d40eb2b2913e38b4dff92312ec18c602a861aa85ed241dc3e4ef0277e1da7b32991670688f8012856c18dc36f32b0d010001	\\x6ea07d3f7ed949369f53a18265e42c0049652cfe9fd743dc3ae0a5a828ac9846db5eadbe8d0b7ceb028d833d8e65c4c37ce0d0f55ae7205c6c1c4acd9e58fc00	1652260407000000	1652865207000000	1715937207000000	1810545207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x255aa7df8dec63d0a0117466aeb1412ca2d7c620f191b73ab6df8d3ddc47caf3cfbd3e051bd675bb696a8581e49b210be7a178787c579af6e50a6b70c43b1d41	1	0	\\x000000010000000000800003ab5b2b1cf300672cff7e7605d47f56bed0db0f2361198f3fbd870e421ca8f470d50c3c2b9aa8bdc9e9d5e8597d6bd49c7eacafc888040b3c33d00ae1a4762198634cc16acb1ea67de5cb0a08dac048f9bd6b6adfcf9798dd0b1b4d3245fe78bff629f04f0e1deb66b330ea43acc629608286ab6b4e595f5b9aa5fe11efe3fc95010001	\\x333c05b1e8d0ca2c2afaa7ab6f5e39adc2692ef3d84de1d57d744b2961090e87860f44830e73d6c3310d3afd3ce8c16661ba8143fea2d681ee126bb389dad70e	1645610907000000	1646215707000000	1709287707000000	1803895707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
239	\\x2656a93873b6e4b86fe608c42446c164322d310cfd41ef418a533857d0e12131325adb38f7c61310333a463681804bfa41a9b02b12e6b53bc5aa2e8cb3bce1d8	1	0	\\x000000010000000000800003b180082bfb7a70a3ef3f107e0b98e8bee491373802c777b02b2d5e3e94ba9f51f1776f0475a578e7990ea30f412c4e11c1997d8c407f7afe02b36479abb6d13cb6795fc41f900dbaf89e27e605c0c814bba64bc7f7a3d7f052e81424aa57b14666b3b9d9afc3f3dd477597aa7477168331602987bbc8d6bca0a4261bb7d4fea5010001	\\xdebd1db33b8349f376bfa93315f66de5bbb94cc26f271b3bcb0e62e7236b37ac4dc544a3d4b3e2008f709dc974371ef9d238d658f1097db9f4f6e2b100635408	1644401907000000	1645006707000000	1708078707000000	1802686707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
240	\\x2aae53aaded67407c0e02335240200a8b8fe7e4909c4a7f701da0b82297ae79e2e63d4472d927894a48257619ad0345f07df0e86fd392fcbb0f480bef4732e14	1	0	\\x000000010000000000800003d1146af35d4a81ad37d523af2cbdcc4d8aa2e385e75e95ea1a2d3f00ccd12088f72600747edbc19cebe731f5dc870cf8268ce1467db07cefa858e3aca79317bc07da3e7c160682b934cff79bd61a1db0a9c8b1660d0b2673e316bf2d5fbb8d25b543a3e1cc00b3dce6262a120a26e47387bc5fac34b94b2d2c12bc83c6045217010001	\\x8d506ef177c1e4b4cda748c4f40463bf7a105af73613bec170f5985521dfc6b7612e198bcb91f45b956d5255eef6fd6e2841078553431726ac6cc68e743e1309	1641983907000000	1642588707000000	1705660707000000	1800268707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
241	\\x30b65884f51848995ab1e3110047ca26bbd37a75fae5f1f87f0e1f495e06aa76e1fe58aa2dbc8c79c9fe617a423a994d9878d6c7833c086827446ba05e941d55	1	0	\\x000000010000000000800003a241864322528b508c8d4f6fe9f10e41aba1fd1f71a28f47ac1259fd2f0ca7be375990a3498d38f2705429cb4355d3e8f1a1f1ae8060801d826331357c9498ef21c771ea65b097831eb21d66bb37f2750aabfa2c15aa3b5619722b8783731a406ef2ad881edfc256d4b8e743a3bfa33282051f9c5da47ef9f8ed892b820e8b69010001	\\x89d9c7d334cac2819b61feb5aaf84f31a1c66a330a95649f92427a16b4326221b8a475c7a6871ab68666e25d4c5cfc4725125f6fc91bafa0eeab0391d91a1b01	1663745907000000	1664350707000000	1727422707000000	1822030707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x329a4ad879f7d857b4adf5101cb6fcd65adbe1cf97ff01e37c5f9a72133b331e2abb538677bc2c12d06c2486b1a0ce1eff383ebdfd905e499b2ce2f85fb51082	1	0	\\x000000010000000000800003c63fadfc2c21fbcf9653a1325131ada17fb73c8ae5568dccdfc7bb70a9cd34fc25826ede47f7d07c605f82a536545517782b1e5d308ceac2e8dfe51088c8e266ff0369db5ea7d58646276c9952839977fc8d67f3ce6108a7ede146ee8c86640ccc85dcd36ea85a710881b8cda6d32c515f25ad9f2bfda7742cc5fb5606d8604d010001	\\x893ffb046d6cfbb23573644870f913441b19f855735e09ba25c99e17f7b5ed70f4afe6cb49b5fd5cae364f59349924eb9fa75a9d647b68fca95201ccf8779800	1668581907000000	1669186707000000	1732258707000000	1826866707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
243	\\x363a5be9ce32222dea1bbcbbd6a179c07e3b2abbfe7bb76c17e1c59d15f9b429d64a68ccceb3c8d1bd40f8730244cf514c2ff3c7bb98baa1200af1b5ba9d81af	1	0	\\x000000010000000000800003bd90f105d82bdf2ce6389261a5656f104b1e094e00e0a349ee0e85c20e0a73d197f3ed998ac8ba9cb05e244b402341c0b52776086eba53928a3b4ec5ab17fde240bb67bc999841aee2003ac8cf243b9f29ed66b70063c8c92f54bc9c3a523c15c79522f106c9f400d17e4b24b792bf3325ff74c2ef1ee4ff767d2dddb91143ad010001	\\xa5587de4f1223d476acabbdfb180025df06e4fc6ce8ff4ce926d48cb3464116eabccca7d5c550f06370b58a28613278e4d41061a87cda198b9f55b0d806fff01	1668581907000000	1669186707000000	1732258707000000	1826866707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x36627cb3c2c3757cc98146d0ce481899826f4e3c51fa04f89aeab4348fd502fc1fd72fb528a88d6edfa7956565fae2e896f1e54ff952296d61561dfe1bb653ab	1	0	\\x000000010000000000800003cb13b59d36d5e592e9c6ca7105975fc4c722a82fcb6f56062b4a646ab5a43c602e48b0eaddcee86c1193b91abeab06e22268fcea0d447adf75d179402e88f6552bb5be03e25306d4a49ef73afb93a829e1767ba7e844c812ef726b174bdf441e745e8230bd17132952bc80432ca5594c6d1f06c6b963855ced3d9fefbdf82fa9010001	\\x3cc4a4b1f794ddd168e37f6b454c61e8a36cb366d89ce964bdb3b696c777b962c02fbc0c8ea775b48241d88a709fc4be9648270aa10e8f6ef23aefa3d2d11404	1667372907000000	1667977707000000	1731049707000000	1825657707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
245	\\x3c96ec46ea981ee4eef41e8db45be58ae342112ac6b872c5060a0cd4630c472e0fce197a37eac5c15b2defb531459aeacea85c669dce134d6d523a3be0556191	1	0	\\x000000010000000000800003df2b9ab4ab3ae39e8208d9a0f9ff51cdfc807d414579a854afaae3f457be1e93d113728b66f85122e40180cce12481146a5c3a33e8e7c7e6181f4477cc7f15eadf86086b1c52042d66c808275682951e0012af100666f0b8969d8856b5daecba8de4475732edcf52ea56ea4ddb3f0a3835bb8b9122dd4fbee2753a60b2e78079010001	\\x810f486924d5448d5853d8d0c165fb94c901dededd59e509552f500692b73dc9bf0c058b967f447e68b26ccb7db6be409b39562bfac66983d9d0f21c16261d02	1640170407000000	1640775207000000	1703847207000000	1798455207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
246	\\x3dca7d62252d788302b98d56f411a5e5c91cdc1af1c9348d7f42dcf7a0d9f801c2340d3aa690374295ab89dc32199102ae3e811bd9bd7ef37efc31589b53586d	1	0	\\x000000010000000000800003c09c44092da350e833074a0dff5f22c8e1048462f19c7a10b05b88d0a1c7b755d2aadc46db7f3a5dfe9bd4048db53b5f140e323a17319b0b0269dd2dbba9c89d35ee8ecfc9df85273e196d528375e02c7c1721fd3bfd268622bf585d2e021da6eb418fc34b74ac83826792253235c3adce0e56136f730521eb8442bb4b0b8c37010001	\\xe6fd0a52f090799c6c5429cb259fc3bed380330205f1d02be91caea0182bbf946cc23e8789009870a5226e715a4c72a408803b435ca8011c82250f67c8b7a604	1653469407000000	1654074207000000	1717146207000000	1811754207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x3fbed50f580cd1c267967d9e7bc82ce152485e5df3fc5a5a30195df5dc681eafc82a1ddc9f875946a9150cb930395bcd562d2db6f81299bd49f60547661b2bc8	1	0	\\x000000010000000000800003a30b76ffe620bfeb5a86a41fe7dba17d771e2340c7fbbfbc8f6e5dd74206e87342148e7ba00e44b9a9d07d8d001169cca1fe678119f0783589ff2c0a018dcabdfdb281ccc3a8780a2229e462b8d3b23587150e9b9efb955683574e925e2b1811e183d6ed8275c3cc93cef4769ba39c7b8b35449447cf8750959ff52e18e42d4f010001	\\x966fac4c7f11784e4cc2ab4f10d119b9d808e85c3e098f7711bafe49f7c66febc033e32e055e148b401e8c7cb3f0be4ce366dde1b5cf6d0d9332dcce61e39c0a	1665559407000000	1666164207000000	1729236207000000	1823844207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x43aa34c61acfb5705c773c73c6605026370dc6829583f84819e911a39e50a22796fe16570a54ae6b8a39cd77e56c9dc649ac924f0a0e4590189b567d41b39f7a	1	0	\\x000000010000000000800003e12eace89a501d611388caf123b600d69551387f553d80d05c5037438f6d16b953b4c553c94ecc7d1c8df238f525e327e7394212d93b34ed28ddf4c52cee963cdc5d9461e958bbfc73baa4caec7dc81016978943f0d0ec56322a4810b1ddadd016014c19448b2497765c5f78ae052b9aa173caa1e7df24652573798a4714fb5d010001	\\x58171e93a7988cd691b95bd6839238954faabec11920990e767e74e8a5558e29e6d77ff04f369dcc5ad2d193832e8c5b4609da5a42a6a9461b58f966813d780e	1664350407000000	1664955207000000	1728027207000000	1822635207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x446a7b9ce596e4d5742142d8a6aebb313e791742b494c6e713f5f7d9a10cb076a29b24097a2e0fadf01a739057459e14745eae6196dddb87849d0728ae336877	1	0	\\x000000010000000000800003cdf719f6a6b23473415ed388ae302bdc570de16ad5387ba40b6c66c032ebd22392a18c8cfa88d2084979b2906681b966a6d604bfd6fcd5f9aed04489a3f44d3654272ba79180d4e30c586d19b4b16c296be5964fda5eae8891c6d9ca29bb4d336da18656d3866511cd392282ec5691d4c8c4db24b7fdc78b941ee05d3ebdc5d5010001	\\xc74d0f7bda350ddf9cc088669c5fd6d4ec247c09b13bac028e7fbd119b6ca6e72660451ee8694b8c18805897ca7371c4e0f56036d40deb7b04077575bbde8708	1654678407000000	1655283207000000	1718355207000000	1812963207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
250	\\x479e7fbbff21e25a76188b11e621e3aa4806dad22e229563e13413683f50d13935498de3ef40c8b092e2aebbb624185a53bf5947c9cabd7291d516e0e488fc07	1	0	\\x000000010000000000800003df5ea28d322aec5c5361b4a285d9bfb5bbc381b3cd3e7185430febb44a479e5d46fc5475020f50b1922bb6f84b0214fc4230a1062473cc63851b556aea9252498edc36c89c3a3e143ac3bbc6ac00bf07315557e0b14f8a957654f011d4bfd09c9bcf7ec6a6bb4d8b40059fd1c0df8f37558a5773ceb07f0fc993d335ea56731f010001	\\x4ac8ce9fa9163663306746ed1d5854e5ed3cb8a65554210e2d18c5cf8264d308206750fc0c39fe251799503b2f734c5f23745ece108e5273451b8e9dccf1f60f	1666163907000000	1666768707000000	1729840707000000	1824448707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x476a85e871b21620046fdde1277b96f9833bdd09d1878c68399804050cd21b3f71b0eaf546eba871d44e0dcf8cb55950e97b5e42ededa0b32bc958afb56de9a9	1	0	\\x000000010000000000800003ae831be3b9ec78a6341f88e753f4f490a6280c43f5df0adcd833ce58283d87f8287cdf41c9710f731543289d32423849e2ce24b19fe760738b1f0599bc9e8b53ca2b0e1b1d796116b3e133d55b3d012b0e955f8416c73f92ef2a44de278a758ec9dfd293857ce6b4fd07e4f9ae39c48c4c9fade634f6afb66036df107d81f3e1010001	\\x351eedee57b3971147e07d4883d7306a27cb177447bf90fbcba4b009b7004bef5c29cd20294f1d5ae55cb8c912e94798bb50f525ea046edacf9a06178b589c06	1650446907000000	1651051707000000	1714123707000000	1808731707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x4b228fae8ee419be3dfec03dbc097fb1ee3736561be25ee6c9bc205a5c369e7e69327380e80911ed2d455783d59ed2d007418cc9246641bbc268fd834e70ad7c	1	0	\\x000000010000000000800003b4eccd3b762d2e7156ef7ed5749de58a34af2f8993647ee45d511c2db05b9d4e4d7c5de2663021e7a6bfb262cf933afa8f35589f7e6d37d33ffe9cf5ad9d3c1e3022e66c2c5895e25619156e4c9fa2b1401ecaf383b33749835949287361097dbf24c451b01545339fbfb752a50460737f029b43a2b69c3e2b140bf3eed79a8b010001	\\xa77d043e3efc8424dd03f826647b75bb695da14a969e8b30aee7aa511669efb6b15c23bb55036b1f9cb3981edab2b3338676e52d5e7e921f9b7dde2ac7636000	1642588407000000	1643193207000000	1706265207000000	1800873207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x4f8ab01cd09e29c2d3f5ccb26662a313c8c1484ff59e5fff326538d4e3c770a1a6558026989a0e1db541a26796a6e001d0b393606326eea7afd2bb568f11e3c8	1	0	\\x000000010000000000800003b1bee88b5e4d32c42ad39556dc3d2a4b29e8588106f4de3e6647547f58531c4601a200774f0bb9c8b4c47c890e63b07885e6a3583d6cfddb8ed395d0a2f98cabe4bb73863e6f558938051c51a8578c66984054349fb56ec719388e5f7060a216468a82d54933a658bfc56acf8f3064ff69c545dda3d5565318a8e021ebd0da47010001	\\x82793f243978c49f73d53ff313b174a6a6019f4e3a81a3f1324bc90123616dd97d7a5148680e5a285b58d05ee51100e43606d43c2a4ca84a44da4574af77ea0d	1647424407000000	1648029207000000	1711101207000000	1805709207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x53869db8700743cc814d09f2d797f9aea682ac2b26ac5c07ae81501406910f0e29d3cd510138836aed14084cc103ba7619ba7bd9373465bcd939448978af257f	1	0	\\x000000010000000000800003a7a8c62dc4651df44136d84d6d36f6cd34ae01d78cdd901b4be8a341e8908dd0ff7f1fd86736df5e993591d5a3b50850ecd3655073e6457aa0396ce0f768b2e86d9847a4aac8f3ca774ab1eaa74ca2bdc358538cc5da9b1fe832bafde5972b91b736714cbd17c49bbae0b21415657a608876ec6da12e06045a59d901a01a6da3010001	\\x146425cedf8c65485604b10b9b1bc2eb65bdd85418cb8937182493b61376ce66f720ddbebc304f39179aec36a20a8af3ea965b1a7201b320c259e656290ed609	1660118907000000	1660723707000000	1723795707000000	1818403707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x53fe17148aab70d6517dc2736712746a28e6dd82bd01f192accc1d031754960c178eb2b95f20a25ebdc16c219212887230b58b039fa78738d9aae168a14e0fe8	1	0	\\x000000010000000000800003bcdb7a31f46039c38131a838f8acc6c22a2a3ac44c5e631359c7422236aa421a3812a8e1ae65747045a5d894b05a398f9d6fcf01c58a1a2504af22d5e642f354bc4433a68226488cafef1a294e5ef5306bc6e6f86c146313dc9c97e34a8a114ad897ff44784c5805d6d0418ab8d85e0d23d46c9a5815ba6254a3f16098ad8f11010001	\\x123208b53439847658aec94ea5a547736cf1f209161e85af94d772faee51ca308a364ef8931f2ba58ea11d5a2119e3ff49e564a3fe8332f2922e7e2bd8ff8508	1656491907000000	1657096707000000	1720168707000000	1814776707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x5532432b0619791689d57dc04e77b25f3a2ec3a3b4b23a84dd9ad6ec5e4abe45d98fb8d8a056ca20e3b6105acdcd6976780b5212f7d72e646f36a43b8c2ab10a	1	0	\\x000000010000000000800003d6d3fccacc61e11fd884aaa896f6da2133c2fff34ed0f65b373daed0c7528c70c39914fcf10d9eced6915b7e10424d5b2aa04f277013b23627ecc8a4c8964958dd833977a8ada477f4be1f3b78728a1ec1b3cbcaaf765c56cc5bb92c1e9c25a35c594b5781d52350c48888ce7a290d4e27cf0f14b032b36a365032b6fbecb169010001	\\x7ea659a15b1aa859027b0e7c746419e8723f65282cd505da00e1855fe7cb346b0b7c0f97f3f1a26d5df3b4a869697b18f5ec4b6f56e096d328bae16e39e45703	1638356907000000	1638961707000000	1702033707000000	1796641707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x553e0ff88a02120b92e37b4867974e13a830773fb596e48f0bc86aa914897db0027873b7cb14df0db2abd623593263c6276adfea1810bcd389fabaf10ff3b34f	1	0	\\x000000010000000000800003db7fcdf9e22f93a98da0d16ff8c0c98c713be3c99e426f36bdf0169f7ae217894445cfeda1773bd252ca60d36faf359bd0b5150190c77cb83c7e2f5d0b308228dd13c2f615c426be1dde28c71a4b4a5442264c2793a3342e7bc0357de2ce7b2e021ca1fb43a621045c5edc49e64cf138b93e6bf558e9fcc7efe727aae8882c97010001	\\x9d3b3c51ae3c9db76bac5f8bee132fbf1af65dad18202a981577df9c22ca96c114d34a9c6b1fd7b74e60a3b85eaf29e4e63d9553d4b2b0e11909bf7a3d512007	1643797407000000	1644402207000000	1707474207000000	1802082207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
258	\\x565e1b3473fbc5f69bfd45eaf2754940013de5f65a48b2417c8a879e8580226ddcaa3c80f841dbe16800cd9402b5ad2be9f7db8a0c94f4ac966e104807647810	1	0	\\x000000010000000000800003d6f3a97837687cf39e4e4c3333c4f0a2f15bc8ef38170ad7a3bf0a6da3747eeddf7894815ed06ae0f1c23a1eaaa7a0ff37a47a8be6d4bda84bbd80078f2bd2a727a0d5bdfba36f92ee6e45ba158353d4ffd01441be10514741ac958bf9779115fde77742a883a576e3b4bf355c184ede207b07199ce37fd6bbd43a8bb1ba9e85010001	\\xf7d30960dc5b575f9a2e900082a433b15e6c69c30779ee452cad4fc022d57f54aca6bf444242de06fdbe18c2d642bb99ea285e1d59d35c1158cc64b8695cf80c	1663745907000000	1664350707000000	1727422707000000	1822030707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x58629f8622a7efbe75afc1c77cefbee983cd24920d436c9b8abd809ac426fd1415b30cab0138b20f990dfdded60196511cc2f7793826d7ca693df7ea862a9cc1	1	0	\\x000000010000000000800003ba361cf3eb28df0d06e889b9dd1eaeb11d7473aedc7988e45965244ab025f5658ff22708ce819212818d8ccc8d44605425552237b393a22ed675b39d9a8479bde3aea56c3729bcc2577c4663a322f9c0638ed9d304ffea664d7fc66c2d5131d360f50cac63184991f759f8e4dbed7087c5788a2d5f80159016ac42031368520b010001	\\x3638869fc98ac761ed4304ba5b76a96e70910f69ac571edf2183be6aef414640b83ce085516c9eaee53d69e4de43296fbecbf1b65b3aa04ff37253a4bc8b8802	1654073907000000	1654678707000000	1717750707000000	1812358707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x5aea9c80be13587078bbc8767bf78479a4c778c8710d2babaebda9dcef3aa1e6ee9ddefd69ded1407640c23c3d979a441d83c86c68c07406464b0f55d3cc2c40	1	0	\\x000000010000000000800003af1bdfac39b742e1d5ecac8b26c8419836825496cc025797dc9e28f0c24df3cd7bbd023f0118044b1d1ec39465b449717e5487b315033b7f2096643c028c9beb703dc11e422f64775130e296e1cbab423664000441acc5356e967c6f4832cd02a42403601a21ceaded1da7eb49d64bacbcf6409e0f7a87b0f479a6358b14d9a1010001	\\x0c1d177a108f2c983307937ff561be048263caaa42ec46d0d4c738b9ea8c4519780bfbc84155ff7070881cc02a66aa38b3c80f36dbc28e1c23b1cca2b489a30d	1657096407000000	1657701207000000	1720773207000000	1815381207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x5b86f7e532533caf0aedb91655ec1f74669a13bfc4675009d53d678af9e554f58cefebe360b77875f76b7177ae4e38f5a562b797b97637898c80bc062d7b6fa1	1	0	\\x000000010000000000800003eb4e52d3352eabf3495322f92b034e1a192d453713fd8a45b5c2d8a144329a5a4ecbb049e0f88cc58eb03a38e23fc56c25045473109411564d0617179e8acb657aac7f57a0ff5a620a53933ba18d54b6416a6eafef0c2d3d73b2d4ab0ec1c05e041717c7dcf051b9846dcc1e69614234fa40e10a100e0eee449849d253da7599010001	\\x41e057867605efd660472ccc4b8bc7f5098f31c39d3e61dc0aa06df0e63d960dab85f3a9b078f306f55e19f47e57bb7c8f94e09f5a36c2d88cdc93408198530d	1669790907000000	1670395707000000	1733467707000000	1828075707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x5d8aea955c160f9c852eff39e1e7a659aafae2fde300dee6e77b6fad6987316246f411f4c8524b0a02f9722855abfc60d823ed10a34bcba6dedabf0c51f98e2a	1	0	\\x000000010000000000800003a0aac1c5dd73fa56f23a5076aa553c70591ab2b38ab347b29031e40ae3f3d72b527401ab63c36d9e143e40bbe18cd1b4bc910a37ef539d5b3faaa392e805fa2ee1625f32a3918589b10a431b26f2251e4a1d07b9ac8acf509362b2cf2006182c7d89b01ab677f2ec3c5a560ed58599f665037d6cf037413fd6cd5d9bfd78a2e3010001	\\xc9b9b6b1b9a09692d0cb0adc9dee6cfb9efd0db8db25c11a5c3df67e3faaef579fe215e5056f972c91df3886ae3d3cbd2ac96897d4e38964ded623cf1128ed09	1643192907000000	1643797707000000	1706869707000000	1801477707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x5f5a4bbcb5219cbacecdba06c62e4e89b579484fbf659935f4d46d4bf26a4cff3b1ebcaf57baaaf9c3c2f3a7111d7b6ae7569d76ff5ded2c658bcd08d46adcad	1	0	\\x000000010000000000800003c04f4aef82a581ced14476f714bbdd48e2a9bd18b4601ea3c5ee3bf1c53fe59a3f3c5169599e3c062c6317aee441b4868f33318eec4a1ad124ddbec2a90d405340a4241e19e51c2004ef2a2083b1ebf28125d1f0ea663a9a0b85a6a4d5ecb27e1878cb9fc9fb05a7ad8e5e2936e119069b5375fe5ff6c7a76ce358fd4d7c6f59010001	\\xd4ea8285ca28e45d9f008abc22428d80052f54b2bd80cbe02e65b839a2c7df6e099a8125a05d1fc4f3fc951237b405138ab55e472de09d2dec4290ce3ac4590d	1649842407000000	1650447207000000	1713519207000000	1808127207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x62de7888218737e4189b683860299ca6ed6e375804174514ed9c41a657260d73611e69dbeb34a3eb46bc079605d859e61385297133ccc2f109e3e0b64bdfab46	1	0	\\x000000010000000000800003d6fcbac531501818c86c8150e3bd5a125fff695307fec8a0afa4304251ef986288c08b0fbae029d0da6e80c9eef779f201e7fdafb37a726723c331b4d07b06fcf091df631e6ea9b055bcb63d748bca448b20953cd5bced1ba1c8e64fbe748c91031d497a65af26bab00becbb9b5fd2a21d6506106176d420aaf534423b4bbeff010001	\\xcffa583ebf7b337ba1958b80a267020c1a2900b7f3b54389da452bdfbe1c7eeb7051ed57e4c4b39b89acb51f3d68a76d00d76b3aa753663f4d212867d75bfc08	1668581907000000	1669186707000000	1732258707000000	1826866707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x63fa503eec90c941070e704d06b70dd9cdbae14fbeb56415ca93c99cc132517235e98120e8932f4e3ee879c5f18ca119dbafe2d258ecbd5ab96d66433edbd3ae	1	0	\\x000000010000000000800003f938f484d39cb47a9102508073e247ebd4723afc3938faf76150571d5e0fed933138213bb2be06fdbc7e352f79e954b56aaa5b0d0c2e09f293a65fd820d3e1b6324d99c3fcef6fa27dee4684e43b63e90f50ff8967f728fb02d0e0ba1c7b4915d4f39d042c0fa5116d78a11d2c6a7ba8db4e0d3a363cd53bc708551afcb482ab010001	\\x5b8e60fd450375a23e9d2a068255ffacdf9f8c5b0fd1e5f07779de34653204a816b76426ee6f3d79c0b9cec93cc6932f659c11a7bc9bed9a648e80daf8d8750e	1659514407000000	1660119207000000	1723191207000000	1817799207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\x64c6225174aa193d51db51b7736f7c732ba73d7185ee281606208926214918f330400aa2c4764979f7c8e8b28ebee834a2fcfded15a76c85cbc742dde1d4309d	1	0	\\x000000010000000000800003ab6d5bac548749e434004a578a4062c9b1ff891209dcce1841a33c1840caae9e8ac9a0d3632e90585378f80c5292c7f506b54ae90f572a3e25448e8602379ce8adcc97a9f234cc03a67032b75ddf7299a99ca4004b28f1776ff4ef4fd8a5e347c71b786f7c605b5e957b1770e8b1a4506e71b109317a3a9335a023e2a5feda8b010001	\\xd0dc6650e7825f229ae66b1be824e8f334b1ee8a51f4aea06674d22e2198a78ca62772e5093a86103031d398406ea4236eea241cd337eec259444c5c89dc5e08	1664350407000000	1664955207000000	1728027207000000	1822635207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x68aaa88de2a93ea8e44d4610910e1913d6d97c7c0244877f6a74c7da940ee87f1e354caaeed0d7c0788a9e6773412810dd069fde46f56e8984286adad9bf7bf5	1	0	\\x000000010000000000800003bc77bbaf57365a7088738f6c4fdc406dac62ffe55e6851f5446eda8e6255b5b0793b61675557800c544bbf48b92571d533b35f9e66fa969f4ccdccae0a451d578a93444e6e4940a0775d0db3542979726703155c340b1a577dd302640c9c2358a16e85e9655ef83e6505b34135a1fdec85924ed851bf1407102268d774e32bd3010001	\\x954260cc74ca392e4220195cb7b37ecd97d39f85fb9f72cd4af340cdb0b39a286d946016be3f29286104dc9272c13bbf32f920a6ed6233d0689364742ff07207	1653469407000000	1654074207000000	1717146207000000	1811754207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\x6b9e060cd1c14bcc38d622bdc5643bc16eed6daf751f3aa185ee42b4ae856e265ec7c303123aba5925b78575f9ddd18ba95445fd79c711576ed69898f828dfd5	1	0	\\x000000010000000000800003da5caad5151037c30281171ee06d1c8243b8e6e4ff9b6f75924426c4616c164eb56fce77b5b294d76a5a642810d0089df544a54cc9e4355d0b3c1af4a370512a24e8299aa1dd47fecf6568ac9d7e023c83a033c0a87d541ae966fdce8733f361f0622b631af8aebec25e18003fd23c2ce18e96c1695e802e874661c2b603a877010001	\\x6e57874c315cbdddc2cfaeb1d79b554407e0bbb829a503784dc24746c196db4c043b048619678d79bd89f1748f83882a2a5c98f66e66db630db6ca182b3b380b	1638356907000000	1638961707000000	1702033707000000	1796641707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x6de26f257a500deb565c84d3a29d1d999f11ba8ad1981c1e1298504a5d2b6041a20caa43105d7b3683b9e6b9e7923b3236165c37b43a4e36da007880cea7e3bb	1	0	\\x000000010000000000800003a1635f7dfb468909d128305ecaecd734de2120d09cd6cb97889e2f290428b23562a9e8576f7c965b1f84da1f1889682075e71914703bbd47eed5668b46e7165fc1533646516901e982838f12a6d3c5e5a0a94de42511481a6378769d294047806a480e53d25cf229ba52e0422d30f660a289c951134bb6afa27f27e8acaf79ff010001	\\x8f759f32fb307855d152f109b6cedc584b03d31b85725bee55773213c1b27c142aa9e2fcdbb8595b581a46dd86d4bf41a84de3948b766c16789f136a4c8dd10f	1648633407000000	1649238207000000	1712310207000000	1806918207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x6e16b37a03790ba720950b180670abab5f483cd6cddb3297270cfe7a19277d830889c81bf4d52e48295834c7fa50df52f5b154efb897b734b419d242cb54eccb	1	0	\\x000000010000000000800003eb5f374324930a2651ef467e06d19141328bc628d4ef6e86a589958b1ddfd9bfe06f07680928da32e0b545ed4dd6a1973065fcb14787673e478ea593926afd95036d77a90c99a27910756fe8eeb812e969deea429fc4d91ba2a429c721c19dc2352684115a9e76d71b15d3f75a863b0716de4a34f497d948424b75ea41703ee3010001	\\xf5200d57faf8722f5fff3f99cb9e387d0cc2c704e162234590d6ec391ee3b8643fd820a996c63a6920118055360a11d2198eed2fb2342dc17061edc6100da80b	1657096407000000	1657701207000000	1720773207000000	1815381207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x75329549658318827e474098b2fd83668e057e32adb5d8aee5020a0d663607da61acb7734f10eb85d62cf573d229281b7a5e8772ffad2ab5b55b71c380b4693c	1	0	\\x000000010000000000800003cbd477af6ecb4646e81fc53df6b55b9d3ab2d408ffe52ad3f3ec9692153136ad22c9e59ac2b4758377857d8f0cfe467706171a59078682d98550fb6b9078391f09b4b9a34c6f66dc13707af4e1f9fdaed9ef262538fae293bdd31557b7f1c0a7aaf48e25781836fd98da0f3b8acd9dfcec52bde457e1f676c046ede9d88df37f010001	\\xb2dabc2488ba5941b0baf1301016bdef385f2b70123c4e089ec9463f46d1f8500ba8c052dde527e5098249814e0ef2817b55afdb1128a26e4064bdfcdebfdc0b	1659514407000000	1660119207000000	1723191207000000	1817799207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x751ae75e268d34cd63ea39d9ef20cf518b38997bc31bfa55e087707ac477c615e1c294f8483505c8cf16ff364f30904259b42c95d0aa816e01b5669088d70f81	1	0	\\x0000000100000000008000039d41cb2d27543079cd2ee4a33ebccaad28983033f7ee3765c98199b33b48367f9d0def3c14d832053e95d42dfaa8cc8608f860b3d3519eb14a30bc4da23cf24449e78277060f85a373709ab008920ab619cfb66642dd9ceee088f0ff474eaa915aea88061610084b502cebd18a6cb4493f61cc04ed3b215747fc2e54a15474a7010001	\\x5135b6654197dad510a8b050a2bd8495af3eed5f7fd686fd1c6a0527f28915033febc0412932f02834e5b46990b5d012828f431d203daa6b16dfcc3b72a90f09	1661932407000000	1662537207000000	1725609207000000	1820217207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x76d258f652d868972fef5de4b530560c5c70ccbba8e3e7caec50f9372d8b259ab0234c66141dcf2e06ddcc2dad2997465896ce9f3f382c7ca29fafd3ffd1b416	1	0	\\x000000010000000000800003af468a55c177b26dc58e442d4c4a961c3c38c28d111484f86289c3b43d2ad1d6692fabf07b1a421335d243cdbb8fe58f2147117e9dbd0ac814c18396ea84224727074d7eadb5f7e780b0ac89cf96308631beed4acba9ac3d56ee99292069556b053aaad9d8415bbd9af2e4e1ef7971625cecde2aa2b52365184d417aa63d87bd010001	\\x4a576ee1f477fc50974daf02a009f3da1969f7ac289f6de75d2999d73a7c0dc779096f0c213cb4ff1bde7bcb5ee644b534b924b510af20d63ab7a42841336b0c	1658305407000000	1658910207000000	1721982207000000	1816590207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x781626270d02461a773574a5afa829f18c62fd6811208ef731d317284eaf46722b0ee8f1bc10b2576a8bf24a25cabbc5d6c99b7170aee33ce086aec1f52fd014	1	0	\\x000000010000000000800003bd3ef0d94e8b8171137850d0de146d03d82c85fc969f29e4a388b65350c157ac8fb6f266f694f05b3f80dba0d5a5bead80109402e3b0699976d9e80add0ecd977447c417b5ddc7c818a4d796d38d1bcb76b4dfb526ad13b6b28b4a02c330472cadf1cb717c9fc80d4649792ad46495502c28ae5190b0ea9d9624c8fc8b67cb1d010001	\\x0fb81ed9ae8e1a3bc972768eef43d159e16fabbbf3510306e963342aeac8b9efa51a7d858b81a81ae3d74656a89dcad8b4310955256b75fa4585110167e2a80c	1650446907000000	1651051707000000	1714123707000000	1808731707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
275	\\x7b4e5ce066310dc2e649e34144eaa3baabdc68223c6bc489776204f34b0c67d2c4e638408693f837f4dcfc81f1ef3fe7180c969a601b57932e18fbd0865b1f40	1	0	\\x000000010000000000800003c5703c892d477e2d6d8989f35705534cf71ab738dc6e158320b877a0945e6a671cde262520d2916aa0095861378e6c35fc64ac6d6c15f970543adb79581f877b21f4fac8a0d9adc324d37d31fe8308a685d98e4eefd95b5d55282be9197075652b2a6134795470a4652e009209a07fbc8563d6ab79a965909e0731bc58bf222d010001	\\x884072a4884a40664e120fa4c40fcfa91d8111539c16e310df380ecc2a933609e557583cd033caed5796089fb81629a81db33b9aa78dafbb3135e9359b222609	1667372907000000	1667977707000000	1731049707000000	1825657707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x7b56574fd157a252f7b3bcbf755d84ba675788335a475cba07f95d367a9fcbb00c596846e13544768f759bea696e25740b0a75fe3e1a13b7a249d731a4baa4f5	1	0	\\x000000010000000000800003c84c740a27f0ebd9f7318a665a1dc88b19a54e655f6263cc37b1961e2bdb3d07a0a6a8b084fce2288e74e94da08dd92368a04ded7d7af670c9e62fad940de3f7efd0e9650d374d7257ade8bb53c21a38162d13380c5b37817386319f53cbe5d5c1b51e218a90d736a3e7e0e7ff8053fa3059fd9807d92eff2d1d3ede1a44471d010001	\\x042970544bc20e42e2009c6cb0f24fb9928f00f94982458e73dbf342c86c5ce98d7a2f231cf3e3864d37da28af40cc6af5c37f2c2381be51cafeb1905e86dc09	1667372907000000	1667977707000000	1731049707000000	1825657707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\x7f52f35a97ddba3d5a641bc53f0ff6ddf8b0cd10dd43e4f12d8bf20df229e4cf01d392fd7b0f51dc7f054f9798d589e0a5d342d3981af42d914f3fcf7438fbcf	1	0	\\x000000010000000000800003d29a02098e055250021ae38351cacc9d0cd3646193967390340ff096d5c8346229ce82ae95788527b952d347d16e69d08a1db2b7fa4c0f454e303c28e35e104e1a643a7c319d9732e2d9e9ba7bda488c4fb4e7be49d6b5bac72b1b0ab14956858a5396e7d269014cfc85da79b0054d87289d2cc16001a0ff38d7499cc9ecd65b010001	\\x4624f5ad5bd06e59ace7ec2b9f0e57f14deac267b4a7caa5f488ddce0083f2285e9353554ac191eb934560ad4afb99671c674b86154e6a875adb048a6d704c0e	1643797407000000	1644402207000000	1707474207000000	1802082207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x802636136b909fdd05bdde9e17d591c7efe93a327f90d8c8670019103473c9ae225e17ac715ecfabea48a3c51f55deb1d7db05cc6475c6c7f0f20cf0225de9c8	1	0	\\x000000010000000000800003d202dde1c8eec1a3b31e2569297620947cd8e6b8bfa144ef9ba2924c7989877d5a02e54bd6db2ab45d1ac2dabeeb6db6dc61e27839ceea1596d799e70ad7f9b445ba51bf605b2e324cae88ce8cc4b935547c640eb9bcddcacd2d3230e414510ce52fad845c112bad6db51c643966ff7c91e71871a70bc705d412d4f92dc04ec7010001	\\xee9bc3bf7dcd6e2ebd5d7155264b4e1f658e4f81668fcff017de27f5b650e2acbd4df1d261bd5c226f8fb690419d1aa252891fa7829b56735356ec65c2f61703	1661327907000000	1661932707000000	1725004707000000	1819612707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x846686ae6dc00a82c3e46e1947da63f32cc78d6bfdaa7c24c7691414a38a6dd036b26e96816979d2ea472052ab54d3fc7e577d880a5c40d81e4e647dc0b242b8	1	0	\\x000000010000000000800003c27732175dba75748a7911b3570582d414518b93bd17b6b862d92fdd7ead41a5754f477d02b24cf22d66c579fd30e06b776a79ce3272e93ca376fc0c2e474b7bc99eb68ae05330da42e0b14aa891e6bb8ef269c06dc029abc05ada76d4a9b193c3a602e596c5b707f605deea69eadc4e1477019e1860c791f6492c7e8fedc909010001	\\xa565f43436f33481fd040c4533a513172ea581b1adcb23c590c6cc8ea6a257042845b4a081938506399262fd450cb6cba1fc3efc5eb1829c0e2237d5e332a50b	1656491907000000	1657096707000000	1720168707000000	1814776707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\x852e63d61a1da7042f9349987a725e67092a29b14a89cdf06e3db865f925d020ac70ea6bf4dce6a411b10face7cf544af22fd60f4480b97ef48f9588fd511952	1	0	\\x000000010000000000800003c7b26fd4e6d767c7afd6b9da077c3ed99b97bf77fe6adb625b0b41e069e721aa0b6f74b7dd8b7b22e010183ed84a6ab34a0dd31534f305615789652f3fde62ece2a33c5e5bf40cb1e7f4dc8a4886b0552eeba5dc910d71bbf653c2f2c9de72bc2500d2ff78ea5c5445ccfdc436b1d48cd58e80653ad2484b1b4372581279edc9010001	\\x2db7ee95c9c0aea8683decb46917bb24b0ed275f9773be612ce45d267e1c74f721b70cc6da01726bbadfd597d4f4fe1883b63ac11c7ad7b932fdd1cfe34c5802	1654678407000000	1655283207000000	1718355207000000	1812963207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x858efb3cf46740dac0a1f4a268b35bafe95ad61ca5fde745b7a006aedc190d853ff3479ecc8b683ffc30004a46a46ebf27b0b729cea22d9e6b152e2ec5f2c283	1	0	\\x000000010000000000800003c59aa71f0ebb840f2afee250bde633a658d1043b9ec5aa5ba32085da48eb52033e41af9f00352c1c367c0c8b23eb89c7d06457f960513a65864fb59c494b2ba7f98646b7b4ff6d6d9297d28d47e0abdab5b20cbbc2cfbd99f7b4216469699697438df8f9773f57895cdf4990816c8a86a3cea2e7fb3e195ad7141add56780323010001	\\xbbbc4ac24eee9ab4079e3d0a00d21e06e3ad9850e495a9b23087c5eae55db9c9be4fa21ae8990d2f83b633f2bd21d9979b75b4fad63611f78a2d260fefb8e70f	1664350407000000	1664955207000000	1728027207000000	1822635207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x860ea0031ebb0629c85f9df60f60a7b2cb276a24b6c6e792afdfcd5e329eb9e66d8162ce351c869ffc795087650c0bea9d98ebf237b58f3a35e7739c96dd4ba4	1	0	\\x000000010000000000800003ccbd4e55b81e8ef79fc229420090aa2a4fa2a7133250bb56674cc80f842aca5994baf42297dbe848af3572799aac2db795cb087a28f69d26066b53cac06e4028beb7f7e958fe84c313525645be2b6e157799e201d7dc04df8af95b77767ff23c33735610bc5c6ca89ec891e1d675ed8d10f28236f896d878bbd172cb9b9cffbd010001	\\x099c77100b2b892b72c4c9e08275dc6afa4e8dc8dd64e7b5433b60a5fd66e58dc8d5ab108d88abbdcb63da13f6c77372b9abac148cc5d51145236498c048a508	1654678407000000	1655283207000000	1718355207000000	1812963207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x87ca7d03beed00a1496c0a04c9e2b02a234cc8d2fa23f7d5650cbd630e2d0526a72d45a2e2c60c5486ae2a94365dd15f4489301f0eb4e8c6071c67b8ac417aa1	1	0	\\x000000010000000000800003beac4553f39358ad875c33351e67fc2eff5e5e64e31f77258af111b4bb3e0362f4c00b8dd7f663c9b5af1bd193a20b3db340805239653d2fe5a3c61bd1e6b8939e26e14560717eeb4ff651d6911555016c03c5386217878884af92f8ff1ee83bac5c3f0a495e13c1faaefddd393058b68bd7ee1eb142494c0e8d4c670f63c871010001	\\x706e8ddc5bdca867f125a125e1c4158d92f91c59c94f8048dd7d7cedac8a8deba9b546ba12023960b90ade3b21f6930fe984ca303209978afe5e94c5168f1d06	1659514407000000	1660119207000000	1723191207000000	1817799207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\x8916454d1c3cedae4fc6dea96c002c9cfb12328fe718d91e772f3c4483bfa2c1b4dcf47ae72a8e70a825f186ddffb76f7b15bba737268ff6a500453908fd8ab9	1	0	\\x000000010000000000800003dffbf1b98343567ccf17fe1d960d26ef802e0a9076a137a2e5c80995b5d1936730a0c163bf0b410ff168c4e1dd9220b56e5b5fd22bffccab89d20c10df63be283f7c582ce5bccce6620c05a17f5e714a3a487440ccef2e33e4c561c7055ffaeb2230952f0b0c7774a66d0c2dc81c67269c40b1accf0d950d4be70fc36c4d239d010001	\\x21090e46d34102136e7fbff12918a3449b2e927c39d88068715216198fbeb06f1780540105f80db390f6367b96700d9f892b1f96170880ca6a1af459305b420b	1663141407000000	1663746207000000	1726818207000000	1821426207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x8b2692d68303279e1617e883ad4c02e64690be5ef76d511ccf18894fdc6fe250ae64f722b319ecfc867fb8e5943fea75857542ec66c82b8e6218ed5a716c5b99	1	0	\\x00000001000000000080000398412ff57d5a6652f17501a848dbb55fd7f19d50b078b7ac7180462a1e23e91fe4b30be8aeaa05fa526239fc7273de282f98b32603034f514180736a64ad31e5cc78db9f5e940da235f608d1f37327c0614502c9891b450a614517b078a80f80e5d7cf7ecab6eab7f814db16fa40291f68aa652cbff17cf2a9cf4a61d2e1edcf010001	\\x6c714305107588b335685d860fc471bfd8017492c28a15ea87d569929a4285161fb3de27a045620371492796e4b85232ecf732004c799fea2eb781ca5e7b7307	1646819907000000	1647424707000000	1710496707000000	1805104707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x8c160e85c1eb38d824177079910b6c33e50d95999209a28eae5f1a8baaaa750738a5f207c8a5b53d9880321504859faf62ec509fa208ac1a24bba7c3a2912a52	1	0	\\x000000010000000000800003d68c84dde91d1e9871ba839f7ef5ae0b93843bb6d4b92d32194d7386f9fbc1fffd257b9a2381f18f301c35c0573d6873ed7cf144077372ddd98c57766b7c56fb6fae7a2409a6aadc84fe4593f3ce869740826e2e26ae97b2d259d8510478f5d301571d3547133107faeee671f8754422c68ee310e30dbd1046a2e2ca820dc9ff010001	\\x636b39a1ce9b61a3a6270841cf534cc4164aed76a13de85b429921f84d1a494318504b08ca6fd120c4ad89e0608a03ac6b3e6702a0c50a4fe7169b79d79b3d02	1655282907000000	1655887707000000	1718959707000000	1813567707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
287	\\x8d320397fded1709e5e01a8f7ac01dbe181140a0f43dc3fc01dd7188626e62eb62444d2c71fb25a577b720bb1952f1bd0444d6b4af38e4c54018a162f1dec658	1	0	\\x000000010000000000800003d4d8cc4622469e48fc90fe8f7c204868fa7b3750216f124d276309efdb6dbe7f64dbd6a63dc4d962a4a4f45e18e55dfeb8247197c503fb278e70da6fd64bcf51c9ae4b9a3e879418bb14a97578cb4e2e47ef47f0e119f45f74e64b61247bb6e1c04285bb9b0d291f39c91ec997c5ccab21c888c6a6244aabe290950bf29162f1010001	\\xca24336248736c185169648d9f444198539d161cf22b4ba856233b92bf67b9caca386ff61a7c339af91e4f5ae4eff6523e5b07672d3e606180bd6591ba4d480a	1641983907000000	1642588707000000	1705660707000000	1800268707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\x908e3d2331b3bb18b35501b6665425e3e45426d59109c385bdac76ef715fa3fbaa3af0c4ebcedd2a04b0e907a9ebf9158eda2e911e34e1530ce5d5e0688f1b24	1	0	\\x000000010000000000800003b5ea0755fa2457a349a7eb1898708c7a603a64b0ae1c25e81dca75ab5a579898ddbc10520cfa78188a7c9bef4421ec796cd4ab664e390c8fde6e77a9f35353749c11e7ed4fbba1b789fe55cade02d5df8ba6b901df748f5bda0d08dde9a3246785bf394995fab407e7c2df787f179c7bc35ce65681a6751f5b412686c7d77c49010001	\\xd2baba2014a9c8e3e72e3b9b88cbb763b825d8c465d3f82cd1a3ecc7e885c0cd95517dfd3151bfde73d121fda0092d7acc01894d4a24b958a65fe59077577f05	1660118907000000	1660723707000000	1723795707000000	1818403707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\x952219e9134c5f5a8f87fe0f1ea754ab28280a39011f1d9b2a04008906bccd3270260d7bb923e656dc3b00d33a606e24da72f24ceac12ee6b7ed1f31d4fb4023	1	0	\\x000000010000000000800003c3e73870605e95b7e135a20089babfb54bda77b93c4a1cc42f5527326d51badcbb8849304c700b377e42ac394db60f3e49b97db786599dc7d2a42b022695ed7ccaa9cb89005aa3d000f4e5dbda4385dc535bf0835040d16bba8b954deec94860fa66038fa82ae32356482d3fd1f0aceb290d9b05f72df07336d86775c71d887d010001	\\xe42ac66ab7c8ddf45a726d9b5bc6f131aafa2e3ec46f68af6f5fb9a4945c322a929ad3f2a8212f93e0ece561e76086eb7058c5c4bdded57dac049b4919fb1006	1641379407000000	1641984207000000	1705056207000000	1799664207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\x979eb71d6bd24e30cf65ee5736317865cc81c9fb2a19155951ccba2a6f7bff3f3440c8dfc5df7451f9c7e38e5e2449680abebe7ceceafee0bdabffe903def43e	1	0	\\x000000010000000000800003ec6d703c4a7487dc153d2252a23e367eb8c4354e8cf7841fecc5c36a2eac6648ad13f1635d5df84ec7032a7d06ccb012aa83c4f7ffcbc4f8dcd457d269cd6d77aa8cad2446be1d724fe61f4719bf63973d660b25e3e4bb6bfa6581e71c15acbc51475663b8a0ea3bf8a82d4382dfa5ada405a81ad0d697ddccf01ad4d11f241f010001	\\x6ef4aae8e7df5f4bddf226e0cfd4275134a3a4d6c4f983497f87063d08d0966650294efee3889049308599f1b62c79957ba71e2ecc1d3d8ff1ec5a34e938da06	1654073907000000	1654678707000000	1717750707000000	1812358707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\x9a929d4069ffe77be2334a11a2636be5eb5a294c1dd2593d5f954167a2d4af77c731fc58f9f10a2f6e71a6f879737ba3759b0f4acf3ad21ea0a9c5c7cec9fb40	1	0	\\x000000010000000000800003fca58e23b5e5272aba5c5a7e2f1dfcaf81aad9193c79fe50ee2cd48a06738af5f5c0a7768a2d775602419ff27652cb9f6196e518da9e85793519c4a40fc8ec45ea93905ce7fe7300aa8264661f60f96ed9187e8961bc9f850d93af5e0b00ecd3dc26571ee4fd9dd6737ab329876eea8c3676adaaa062f9ecb2c4541a9b7b210b010001	\\x456a7e65b54baedaa895b7838297eb2ac3e88cf25b22e23bd71409358aff71ed7786ea2e403b1127228da036e4bbe4078c45ef23de1b48d8641c74e6b66d3603	1657096407000000	1657701207000000	1720773207000000	1815381207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
292	\\x9b764ae50d05b10007961d5f0df545bcb5f326ef245aa7b7cb015b88a07c76185c7b5a669979e4df3ebeb1c46f76ba19a1ecee7f498f5e97774062a4f658b3cb	1	0	\\x000000010000000000800003a021627ec974533f8fb88e8f40d59c024f81c95ea80a5cf9e38816d00b789206db41b5fa86be62f7ae8356b648a03b21100ab9c30aea932e816cc74a2a4fd44db3596e2a658e50aff0b35194339d61ec2f71aad1fcea205c8e2019b75b4cb0d358d17136afc21c7b3aff637ca149c52d42df51055a9e100fb20ea52c0039b835010001	\\xeb08b7b5480f7f5462c2b0ae557ca41933d6281bb2a63e6eae12ce7115974e51d7e251355a69b16674d6394524ce59076184180072c4ccf5459526deed8dcd0a	1641379407000000	1641984207000000	1705056207000000	1799664207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\x9b2205e2db384d02f28550d3506c3a96194e8a56318e23792522966591519051a3982ba958ed340cd5abf5c148f3870a9b4b960b0605e3df1192e473f8baf412	1	0	\\x000000010000000000800003c4288e0554713ad30711d87ef45f45222fb98db467bb369672f8ef42dca060d98c38b5c9942afd0ccde98a51eec8311e40b97aa96c004795faa913b414630f133a216608644c1ec5f944ef1be98b40b5cd18f7bd79dd3e757eebc569bd78cd6981f8570361d8b17d14175c17bbfdba4edd2f928122ef21addd34fac930ff6245010001	\\x1a46fbd5083745684c211af1e581bca65b5d30e54b626188edaea6e660c8b9f9d60926720313e95f0e98f161efc364e52f5822fba3eae4da1b33cee760a2e904	1666768407000000	1667373207000000	1730445207000000	1825053207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\x9d22954fc3104061aa1caabb09a2a73679e448c9f16fe96604421338fb6b8be64caf6bdec3f2a341a2b81d16c62d0d16a313dedf31f99918600801348dd34292	1	0	\\x000000010000000000800003b95ad0ca87c15f1efd9799ae5474fb89a98fc083075934344aea35817a8be44d5d2db70b9aa11163e27d8c78089b3e4e51324fe4cb8ee71f89a4cabcd5913d3d941a1f6f5f34da8c997b6bf1a0c2bb7e5547834d6422e52e34fcbf7456f8daba42319b3564fb9b9dbaa3549fd2b7c22a7610e5cfffc9d156c079ebae925764e9010001	\\x5f4fedf65afd3e4de4dae56bb864106af40a28abb9f34a7024a946ec317324a6c23a0996c0df4f576272f8398ee705965e59ca43e4bfab52ec8d1c40c2ce350e	1641983907000000	1642588707000000	1705660707000000	1800268707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\xa022b210850abba1d3b76113806381bb54855338c5f62107877042075d92623c777a9215fefaab764962be17af32c29bc4f3e2010d38bfda2620d942dcc96686	1	0	\\x000000010000000000800003c68eff8c38dc6d7dc6a7752daf5bf5c9bb0e014c49168c17dce61d0465104d7d0160a39cf1fef9dbf8d19bfecb5cf1569b373c7493318fb717912a1f6a35bea03ba8406599374a91c426b7d09e7cb9a0b0466c1bcd2e6304770f1f113c9918f1c3b97f5c6d8d360770570d75b6a70b4c2b024233219b52cc3235aeefbf50868f010001	\\x767f2162dbf003d8caf72898d06a8277e7786815b7e0b2c8a01a086e76bbdac6d05a52106312027db74338711f21ee5cc974377da9f5e99735d5a6695052f500	1641983907000000	1642588707000000	1705660707000000	1800268707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xa16e43842fbb2e1c63e4d5ee28c03b6a43c17d89787121a41773650c5ef0ab328682c5ac5051842a3af87605dc3db4298a4f91b1d414774e50a378aa99e4c7b8	1	0	\\x000000010000000000800003a51b5f98e2004fa23e4a33e1261e8204f202dfa0294edaa9ee7199408fc4ef54bbfc83d2a0b4e80fc33fc5174380959677d0c5ca0dca54a1e656fe316859a779f89178fcd781ac04ca51d965a58d84679eb5302547762e0f4cec0382c578888e0fbfc3689fca50599f55e33bde3d4997517522a1e134959a3af7f1363e814607010001	\\x61899ded2e8a18cb0816d5b02b6dbd43652119a207885c1d4656fea528fc44fef71050a322795daa1699317526a9dfadf86e22b208789d3d75b80e06acc73000	1645006407000000	1645611207000000	1708683207000000	1803291207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xa2c6170a13d4bdd2b33b261a2589afcff909ca35ef1d286fc174046bbd4ef50efcf0aaf7e11fdaffc76520ac3429e863567443251a3df5358ce47780059251ac	1	0	\\x000000010000000000800003b3c0da469b0bc96f64b1f0ecdf37677ccbd94f11b7f3a182a802445d0bfcb1ad6ec7a27a2d7752b45a40c73c190514ec5ce95748adfd219ea1cffbc795c60384accb1f5623b0bb0d3fd11ce628fa5640d169669fef4eb04f46c6132706eac21717804f34e5e2cb61085365ce48c96b1ae3f51036c7ad0fb527533f352c1f8ac5010001	\\x93c79c5a545ad37c5d80f69d311a4eb1ad5ad409ab2597ea19ccf8d829a359992e7c93a0d41854ba678ac65b541c01d2c96a23232ec43d29dc1e5636bfcb6f0a	1663745907000000	1664350707000000	1727422707000000	1822030707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xa3be61b60a777b81d434f388f84f281d1fbacd8fe044fc36cff7ed4a4c601289fa0186a00d2ce05a08dc52efcf22453db8c8519feeb4e8d7b49be51e4626a27c	1	0	\\x000000010000000000800003d3f2af00f1f8cbd3eccfc078f31d865fc7b234fae6ca1b9f6936ed66b4935986a459ecf9f0ef5454338f22acbfa5f86033c131ed73a1794096af1cda0548575b07d1ed7992a7fb04a95e35dce9d367464431ac6b10234caa933405feaa41fb94e4722d574f73cf0d0ab0f9a5d0307f86c47c01871420344e920d68ec7e687049010001	\\xf57aba962f5f5f02444b4d6704e8a3d4db794aab5b149f1bea61fab49c347377001e9ad559a959ab89af0fb82dd5be2633878b10415e1611c2eba7b38ff87007	1646819907000000	1647424707000000	1710496707000000	1805104707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xa5e2841f476f3e97ca8b45e959d0e7312d88da504d0cdf47e731d216bb1302dd370e0231bb96175e57d2a8af2f3d58ce944e269fb7119273b7599c02c8d4b24f	1	0	\\x000000010000000000800003b3a4f02da25eaa9ea7736cb014096eb223e9c259a73e716c712d09b2b82409683563c0d50f3aa733dd8be583402a449a9b9783cbc4a7355c2dcfc5d5c6ae3ce00c95c0c7a4238e949897013526f2f1d410643d1b96b76a3ba98e8e98641c3ce9de6dc1e9c7dea94ce73031299fe33f1f6d5109ac12bcd4134cde9c75e03ceb67010001	\\xa7a3eb7446d8320cd64291b668f1b12f7c76b3adf794895043dee0f81809309f46aad09c429e0ecb91c503793e8a928d5e577eee60d0d8c25912e73d2ecf220d	1666768407000000	1667373207000000	1730445207000000	1825053207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xa7be193ebfe07faaa3aa7fd3806f82386101413e1a38ef6dc520bf5b0c631831a291148b7e6f9589bece7ab54a2aa6c3c1eda3b376798239ae4c643a8fa06629	1	0	\\x0000000100000000008000039ffee1c5c8614103c6d43bd51698080ec86dc8bb5d53dd550684965304c2e6313d69b31db5e74f072720f1deb01ef6dd6ccb4c6b34d393e392b810be622ea9b7c7aa3ff009cecc41e61b11c3e752764f0f4a1ac751125ee12f7bd80c1fbc3a3b5319a04024cc488f643217e74d14b402b54aea17b04001a831f58e8edc942cc3010001	\\x4d91eeddc8c48a96049fc14ed9c04a7b51d243be942d9bef0578e3fc647df58f0b79e076a7d65a98f4865dda046482f301f21db7a4c1ae4275f7defdfdd13f08	1643797407000000	1644402207000000	1707474207000000	1802082207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xa82663324569f4e695737646b49f096ddbce80b11639b5cdfa90a7beca2798c89e98f8876c4d01c7d47da5106ec14bc74282ceffeb06fdf63ec1e7006d145c1a	1	0	\\x000000010000000000800003c0f07e97a797ceec713dfd1d38d40f123dbf82bc7c2de7197e395c7b194b2ac1ea1e751f57a65806eb87cc1493dd4d51f57e5e2202f317d148f3fdc690187d084f88f7151d6bb6ed273049dbf056734cef0acc6902a41b924dad0e58b56d7251c8306434c4c07448b4713794948d5d974bc749de15cb9da865ee17dd3db296d1010001	\\x252e195f8f06054ac438ae20cd05f9e0ffdbead96081375767e0d6baf329dbe68e9059cee752783fbd87730ed452f438fc2d99aff4b490b15f9806158e341905	1651655907000000	1652260707000000	1715332707000000	1809940707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
302	\\xabaaa3d90610973f03d08f044aa377791642eac7cd8252d3f27c49147b156b581a732134528acbb3c2938eb8ecfbe438e5644172e62ea7837aca07b67c7377f2	1	0	\\x000000010000000000800003d795c2b021c6d6e33a1fae3e015a3c29c24a59e2212c5479648cc1fa467e50d2f49b3554844c1c5c0121baa785b52293a61217d136ebf7efa59ca915d871f32ad05fd4ee6f9d36dc908ca49d166dee23a97201c5a5f0658c51be9d5515abc9b695d642511f3e914493dcd8bd4e4daa0b7fc37d3d6bf957a072e853b9f369c717010001	\\x64a1a1c64cdf103a9fb6c7fcfb24ea75e348096d9fdc3a6e64606bf0ee8cf74eb476c06be8bb8a19c42b8033ca4a685f40c6c2c964010140dc3b14ceed1df705	1643797407000000	1644402207000000	1707474207000000	1802082207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xab86b5314f48d4093d0d0e18d4919df1227ae2cefd60f1ad3b8e8e8b96494c36ff253911425bece27f696880921c848426b265aebbc155761bd1b1c7c9001876	1	0	\\x000000010000000000800003ce1f6a1d65cc5eda56798c8da166ad382dc85dac9864ea0b599839f16c4ab64d0f6ca3e4f8291f7e5af27617e8326edfdd3e00d6bf5abc230738783f7f460efdcdfe54cbb4fbd4aa0e340e9719113c08cc0d6c6b2614e4d5d2be5ec6f53ddda9b3423bf4e2da8eca8c7c2418f8bfcc825a58e445f7bd85134c1874a5913a2ed9010001	\\xbf7c510d57a9d62eadbcdb8d2b050e2543c68f7f6cd5cf391aa6f66942273ba7813dce0211978283874c58aae05907e6a27d40216be01a05a59a7b3801581b02	1646819907000000	1647424707000000	1710496707000000	1805104707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xaed66316c2884faeb668a738d6548656c48a9c27a4389737d5baa892a92238cbea0b2ba7ef58ab28786d3531021fb50ab33fbb90ecca96de3793c267c113bfed	1	0	\\x000000010000000000800003bd73445aaecdf7c30f8c70637bccdf9619a1b8e5869ba7a6b175d61cc0e9877f60a226dafc52062188e2a50de85345a3d68d7d70387013b773d2c52f19970a773447dc8a416e16a261ee86359f0ea9a292437393ed25885a6e9714ab9f837d6c8265b8edeae8841f0c4c4e61027c11837a3d8ab1733288db9d669aed26dfce8d010001	\\xfdad83f9335b7f27dea3ec67ff8aaa07afd706f1db2a78e44b092c1d7b0cbe251da1d0ab8c8fc50507132bb7639b1c65c3e29bef1a8ab501b7051a9cfaea1d0d	1638961407000000	1639566207000000	1702638207000000	1797246207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xb01afd642f205936fda19d5f85c025c7d653a74120868e7569604bbb18015a37e584e894bcdb3d26a15718c3384e18fa0d5d0cf4c06c6f888e68bb44b5aa78af	1	0	\\x000000010000000000800003b96f1b5b2002398ecf8d1d37b3aa1c50a5850ff4d04d8456dc63a6d3dcaddf8c8819533517e2c5846a43c7a4610b86f31cf6398b3f20e4f955e1972604e347164c55cbeaf96f42e874015630d38b471c879429bf698ad86a8e6d85a119aff230650be0507f6b209933a49764b99c80e5a8b49ecc78494d293e4de93a40872721010001	\\xd31fc610c723fbc1350e3f458321ccb1ad7db313181294cadcdd666a49fbc0d5b74599249dcdff6061494250fa03c930220455112506ada20f752f2bafde140a	1658909907000000	1659514707000000	1722586707000000	1817194707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xb6225e46442f6f48d0fb16abbc60401811ea8078a7128e8dadfe3f0a2adabc51e409f5b0402194d94ceb4e553b780894db3c6495b2283c8d2b9402aa80d8d40e	1	0	\\x000000010000000000800003c9237c6379e9f3cbb5b19753a91543d68c447bdbf58ea2557f7635a72e03f974acbc9a114b18dd2d2006621b645450c1e1f1e77922ea5735499b9facaad18b5ab863ab8f8ef01dca28098bf5b6abe101317cb7d364b370358d76ea28862d479ee8773ea5adc020b0cdb4e1f77d2689927ad1e41653b2b5a3d8ee31c0876cea71010001	\\x69d44bec859250dbe5c0aa7ad6e6187ed011730d93efbf6de87bc17f81696d0742b7b2d45b892db7e8fc081e470c21ff8444783f0be865361c9ccebad5edcc0b	1656491907000000	1657096707000000	1720168707000000	1814776707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xb7ae799376ddc239663724559c80638d3a44d80698404182ce249db9ddb829a198fc573cda53c87e9bd4397c4e6a6a30fde176786ee2865614c7820b8f4f5484	1	0	\\x000000010000000000800003f9ba475c33c3729300014da1e0bacef37b899086fe6240185bbbf69080014aae42aace3b58ac892110b6071c2b786899b42da2e3e9d0f992e82c6c28d408f16f8281de88ba2bd2fe2f1354dec4ecfaa8323bcbb02f436cbaa8e23705cccc893396e15e439e484afb9ca7185c928424322faaafe8309935647617b14ff4ff94dd010001	\\x26586cd234c77230dad1c67398c11a9256a71b22ff37066d8d38f61f69641969708e1cfc93248e0a02cee4d46f61b88b4b6d4a77bc0dab380f1529c5ee57650f	1663141407000000	1663746207000000	1726818207000000	1821426207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xbfdea5a013ae3dc1227dc7112867f8ecf02a03455b8969ca327aa91e9f3aefb582e56ba11a1894bd04140d44fc2b7a2ba4bb1608c10cca768010f60859c2bb85	1	0	\\x000000010000000000800003f1fe4bf2dd1d9174656736d503525eb776b9f021bdc330224da3b4867a1b89bda9688a71fe57b6529c3694d272b450814f366992d0ef4c78798fefe7e2e9e6d360c05a410e1636ee6a5fe65a22004e713a6be7c8cac62e23cee9829107f0db2dd81687e04c8c6552abff23d93c1c5e48340f5a0649c9d2af628b830ce4dd0385010001	\\x0666dbd75077420191188271e03cfe703b0c18a71b2b4e858355b4c726ec4a85736950747565830ffc832f6c6eb5ecd340fe92e560594512973f1fc5fe854a04	1641379407000000	1641984207000000	1705056207000000	1799664207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xc27a73aebd183ddd4ae35ad86c031a7c9bd47d89f604d0296b5f585a26782d0a8e5a6f70893e63ddce7ad8d44cf29093817bd7358f1898a8335f96f47b7200b4	1	0	\\x000000010000000000800003f1d8ef2298b3edec5213bc9911358b68027fa42d0ae8a44d42dde711583847d49e8f133452f73659129c6ddb25d24a595ab2c350e5eeb5255c56c69a238ba23c00cfd9b0759d60e860e38e20001d7b101924659d820b49f9c9683e7eb852a0706c6f67a06f0de00f4eece73ee615fd5d4ac0ae7c97df0c841d06b5ffbd43e6b5010001	\\x40ba8fefb1789bda9f8d26423fdd6ebd7474e2379d82fe656a3335bea4981c7685f569521f8b4e450921da52c822fc766217723bb73573f4d323916ddb06760f	1651655907000000	1652260707000000	1715332707000000	1809940707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xd46a3b2e7b267a74ba93349f7cfe7d2938aae718c7f315d6d603c4ee8dc22e1d352520e7d903b10e40f6ebb93e970201f03c64ca5e1b164257d3d986c1da3205	1	0	\\x000000010000000000800003d8f3afb61545dc5f5de2de8da572c847e0f37c38b4762f732c38645e586f9f7838c475d83c896e5838e179a6458f6da1ae82f920eab12c37377ea96bdcbd3d18a676892112ac037452b9815aabe469fa5d70f5622cd79ad351f853a82910ebcd572d0aea09a6454ed2867d64f9fb44f0f6a11c5a19b2b7e0e47d7dfc949f1947010001	\\x04251f891e2d3530893a90f0f677cad4e21c974ca48439141e547e820b9c145d64e894a0d29a3f4671c028700cbb8931d869f040cc33f1bf853967c7275e510d	1661327907000000	1661932707000000	1725004707000000	1819612707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
311	\\xd6c21a1c7657bd62bf3f7752ca42ed93b478b5ef27edef6fd08470b8fea5f5a94967b91e21d2e5ba4b60d29b1737a46d52050eee2438faa72893a0c8882d372c	1	0	\\x000000010000000000800003be952a850a980c643c5a9dbc07cdf91be8d307d20ecd1c0f3706c959ec79389ee68f13dff57371f008ef7ca77e55a434a7b42aa6171fd7f24272474ebf42eb562905c9f1130c9d1e25b6b018cac312cc336eeedb2bb7d5631cf1ff13da94981439727ff9777ff943b0445c05c8ca7b59d9395d73fcbad23586612b43c24e9a5f010001	\\xff33be25297ece301acef463b52959b8d4c0a496e7d001f087b919e62c0bc9696c9ac29ecdef66cdc1d20b3d8ad99d854915be4ea75ed213566b833e0003bf0d	1656491907000000	1657096707000000	1720168707000000	1814776707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xd836872887abcab14e4212a8092034daba1206f4e07d7a42b8f5e18e61ef8582b8488de4910da7775561d688c6859bbc17dbe3c7529967d90979f35c703f699b	1	0	\\x000000010000000000800003bd8266b1a940d4cf4b1125a705193f78ab9821c9fa59b0ad5f9264eb1f6ec5681c665a7681487c295475cf83b801ce249ee59271e0d8d3776938e5465008213b5f1f38300864b938de4a145411c92ae47a84029ebb0b3f84b1f454ad64439cd42d77aeabe37ed3adc7dd6f3234ac68ee74ae8da8916bbe8f4e6e0d8d5de36229010001	\\x33fd251c9e0bcfd39d7ebae6a65ef5dca0613befb805c8c3a021f71c4a910e4f33fe01b6096443939dad1c7a2cccdb3ed87bcd48b365eb40a622392ce8b8f400	1641379407000000	1641984207000000	1705056207000000	1799664207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xd98a8e32c2cb21e9527dbb2406a40d554e20bf42800639168a06fc1cd42fe2481b3e1c0a73eb94b0e98cf263eec4c2a4884b79bc899cda5aa4d2dc1f4a4200ef	1	0	\\x000000010000000000800003e4a7bb0d0ae9772ada6a60eb5466e9b8c28890294c4cfc7c85436e708532b892fa7b0dbdd7b37ad82eb82476cc2d08e1923f0ae0913e44af619c07f71f8f9a374c66fad69e77db93bbe2cef2285bac32bd4fd6a8dfaf546d7a700907480775a1bdd241ace99dcf2037eda6dd86f55741d53e3663beba0f31d38d0ac83900d98b010001	\\xd353196fde4c55be1e13cc33c1e9b989c3618d320d10064b1124dd4d0e4af3d780e7e7b8c993956bc3e7f55a8a661fab102853965bb3c5bd9433e0772e269e0e	1657700907000000	1658305707000000	1721377707000000	1815985707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\xda92d80d1d6767ac7e2fa797c5bc22fcb16a1fdb453e5aeaa4b30afa82c5a9a98a90362cf41f4d2cc90a708c5549e6d69e54b438184de158ef6a100530b9ddf5	1	0	\\x000000010000000000800003add680889d9c291a9fdaf0504020d7cbb445fd627dfd3380a33349c2e84a20f1828167964cba0a4ee14be6f3adae9ca2446a0f3eda06c719dfcb5a42a04758bc49cef6569f88cb5610620d5d2df980c5fcb6757a2d199aae761098ede7c7a1ac84bc04b5f5f4b8b96a40d647cbdd0f00b4aa7f3fb868125e998fe4a2af049d4d010001	\\xd23c1b65eaa5cec4401eddbcdea6f9e302bfaa09b1ac2955475da1bc3584af1612652fb316f2e5379a166f119c7495695eb1149e802b8c56c7e73acbc3ae920e	1664350407000000	1664955207000000	1728027207000000	1822635207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xdbd2062752e7f86e94d708ac5c59b7fa1fadf386e41273bcd91a6d753f7f25dcfb97fdbf1c58418f655acd3e668ffabc32b521fcfa02b5013c9d95f68e044f0c	1	0	\\x0000000100000000008000039a78c4c3feb0bac36287a0ecb7b7976d71bfdd4a1d8e9329606749b97f509318b88fa8f321dce4395adbae0ad207130bf02fe2b4d47485a00f62d3543abe118eaa265e946aa0d6e1c1d3d468afff46ba6ed0b083a5dacd70506958d1910b3834fb5a23bbf1c505730f374246420d513361ce43ed93399664e8e1630a4bc19341010001	\\xa19fb9ae0640a54d8740c8b51700ae1b1df46a01b6635df54f8fd68a1bdf4ed99430b073f7136c1754934b67534fac2550f9ffa1f03598f595296afbb6a1050c	1658305407000000	1658910207000000	1721982207000000	1816590207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xe5ba282a317c7462906cc4d632e54a8c4e03295e0594ed23e3568fd8af9377b446ddb11a1ed73eefcac47844d793289a86b1817cb7087716375c00a79f6e9dfa	1	0	\\x000000010000000000800003a3da3cb31f0b433355c5bbd6b75b485fef822f28ce99bb10fc77a645e372eb87c5eca30b3b823073772a4c995e7febc0f86f2b12b303e0b476a3e9a90806758db9fa9b4ab4d9cfc729dbedb89b3496457f0e884890b9ac3ece0d5e3dca882edd6d158b4a8c95f5b6089441ed880272512516836b917d0dfb5f4544f790d09481010001	\\xf1bddb042da83d6dc4d478d182a0e18d623b8e72adb13518238eff9261f8eaa28e7cabd85a118a6d9cc22c264157e2108db9903626f0d4dc680155756231ae03	1651051407000000	1651656207000000	1714728207000000	1809336207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xe68e495779046abe8bbe024614f01f90a304be5a2bc2281ba3c66148571a69c8ff6a3de56603cfd7243fbc0ed00fe7f018740c0c1ac95750f600b49e77f443e3	1	0	\\x000000010000000000800003b752fbffc7bd758efa5f214c41de9b705a44cf33c2c26cf0bbddb4c2b6f9cd722d85d38333dc4a51c962428e04f7a9cd11ceb1d91d1f483a4eae59a2a35b182678b8730184bae739d8257b5b8ccf00eacfaeda5135d2f4073039d4a440123fef07665d2dcbfc5a02708bc4826032795871c25e16a841d3af6c629c612c1e6601010001	\\xe250c8dc357672fb68f8dd63157dbe92f17fd447b049e5599593e06f00f407968df45fa75325f8c959be59728cbd6ad87efe60cc2bca8dbf638617be26d20900	1648028907000000	1648633707000000	1711705707000000	1806313707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\xe67ea8cbeb4ffd01c033233b9f874ff07fb774a1c314f23b9d0459988fc05ed374528d00f0db57fadb4e1bbf56cbf8597397e85eddecda3e5d93015130cec2c1	1	0	\\x000000010000000000800003c95d7a0112d3192f7c39bf87cde32aa7cec6486404036a7b23de3abfbe0dbc6c8cabae4d6d186053ca829f103685be3765fbe26c2e9acab27d41edb522691f68c7dfc3b665a58e1dcdfcca26068d9670e63703cf72016a0c18adf84350fda9f1e5c03eaa1053822ce2b31508930b093741045b347fc5d7b9227947acdbc050fd010001	\\xec04a11f0b5aa505558416b2deeb08e50888fc2f867d01da0f62788677b12c72fa7d5d9f24a8664aef33b582cc215b53f95cca9b1164bdd6d143c434d3d01f0c	1655887407000000	1656492207000000	1719564207000000	1814172207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xe81a30b85ae51e920567f998cc19e41e08c9b1e278159461bb19e19613f8fd844b1c5f9d745c73853e341bdef63fc0ecdd2fde8a9aa753e83092febf3a5140e5	1	0	\\x000000010000000000800003b56aaae28f33a6644c067c862d9df384036c433aa7ae45b2f033df26ecd5fbd935bb8c8c3cdd8bd1b287962958b89760334f8171c12a450ceb41c263d854425812a0296fd5393dc82f29b4851b1b8f655650713ac354f6eb00de369439439d357a60a631e3857717b665d5882b78fca02ff5804b75e7edd3fccaa90497147a09010001	\\xbcd362f7d7a17c30cfbd9ab8f368807a184d3df230dadea1fb74cd707d2754c439d630eaf7bc94b71dbd9a5245c0475b35266dc1a087791a9e9cfbc122294605	1654678407000000	1655283207000000	1718355207000000	1812963207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xe9ae5f15404d249c1ad6a5d35755a7a0cfb1d362ff5398b801e9c4fbe1263c73862712c6c2577affccddcc90185ecf9c350865301667a2e3a6200529f7097af1	1	0	\\x000000010000000000800003e14278085a33b4ef86f3310d94cde6f91d08cf50867e86009c2032f7b901fe463904e247152973623b3855cf2bb4886dbba4a6ece5041d1e378f64b0f2207ca46f37e19039918c9efddfe85c6773fc3ef15f5f7c82c2c9f6ab622cc3dfb722b19c37238ce9118fe927a584026900b755f280ec60b4492726cd65e7208c14660f010001	\\x29844509c3f55a38a164ab0679c25a6e3ff6f5433f97974e65525ee5a792848095673b47b9c37262b4a660c0481db05f9eb1bfe4e37b4a054d795d18a4df610e	1652260407000000	1652865207000000	1715937207000000	1810545207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xe9ea06d70ad5ccaf8ff149b1e2816106b37ddf7dc7df4ccc0fa9cf780f5b4ae251fac2c0ed9ced83b77a70f62b95924fafa6cb2ff2723b796729ae9de0a9f5e0	1	0	\\x000000010000000000800003b8a88ef092f51d034d7506e1acfd097e03ca196475bfa20e1e89565bbe5d5c12cefa639436b93640ebccb191ae8cec76c01a1454c393fc40d452c202822b00d3831c643e3aa68b7d20d1bdbadc115be25bbc74b9560af2514fd7ad4a51ff38e176a2d1e4f1c81bce9541f4d45a3dca5800b7e1620667e73909bc1af0d894136d010001	\\xd1d3815dc9f17f95c08a877709d8cdefef24cbb54fdd7f1244751e2e8353f8723cf138f085cbc0686d5c166d2fc65e35cf0fc3e33da65b70b476d7c3cca8d405	1643797407000000	1644402207000000	1707474207000000	1802082207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xec6a29b0ef850d2e4c0a764f06a4f580b2822308f02f401e14b0f89c05e17e363d84f5e99b2ea136c8acddc9f27344728957d9ee5c260dc0d8979fcf4e3776a6	1	0	\\x000000010000000000800003c10867de74e267cf7d7b797a63511f4c93bd498b3bb2a6113bc824294f55969ff1064255ed74bcf5c92ab85ac9cc773541066d502d3958b9d736f1656edc8824de89cc2f6494a7dd87bd38a14cba006f4e261b17eda653afc25c209be4962b75e5557bb0bb918689a6b1d8b29010f7e1064c0fba68a643efda9c16ce367a1a31010001	\\x365b50876c374f92363fd2400b10a7decb9bc1ec7a974fcd9886ea75fbaa4c826de2f46f9bf0b3cc738aa4dfea1012a2b983c445d133ec2e14afd1f1d3ab330c	1648028907000000	1648633707000000	1711705707000000	1806313707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\xf002d164f28e9bd4ebcbd34c4288149fa7b5507ea2f13bb7d198afd1c666b8d9ed262ff0280103f07361002db4433fa4166e3b0bc91be5fa38903d4941b0d80b	1	0	\\x000000010000000000800003a9393898a097cb98b669e875713800b33d85cd504fb76d374bfb3a2acfde2de8f44be763572a738831eeb6fe85a5540ec6146d5b94bf371822fd51649b933a66bcff158b494fed67490bd33295af8025830488742b5b4ac62016bd784d62eaef9fb6bf875d0de70bae530896df9bb0d00d8414d725f32091faca7d64bb311c73010001	\\xaa4b4799f481146b6fc399c4cb5d43775245bce19c195f839dae10f0ee51580526859c66b49ce43e4d058645ef720e3c3f07e3067b92a6d7805c634918880d0d	1644401907000000	1645006707000000	1708078707000000	1802686707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\xf52222ae43288189567ae797b0de7fc4dc84bdc03b6d22d01e2d1ca4a3c512960141d5d7fff97b4bb1b598a0c5f92a93caa3399b8f6eead2a11ba18ace7c1e1b	1	0	\\x000000010000000000800003b857f47e4e6a898acc5aaf2377f8312d8f33eb775f363fe8377175b180d0d8e44eec9c21c3f6843e28d6760cf90670f1ddc5af9850067924d5fac5416da50cd6e36eb23962e24a9f072ff3ca200fe7fa4fd66ece1cedb21b8c4f3f098ba7da8a78a9a74136c35b13aaa299982353651a0ce8f8ff2d27c01186a3476b6b2a170d010001	\\x5b9575413d1a3257734e9d378808a3a515029cf8702643648cd4feef56aad93f27f175793a552ec55fa0acae9e2028a5683ae7133927912440f01153cc41560d	1657096407000000	1657701207000000	1720773207000000	1815381207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\xf78a87da59938fd0cfa083fc9c72f5b2e72fe9351614c470fbad019a5b8cee8847f932b50011f8eb6205ac8ef2a66df046ca101d284bedc3666298a2fcc8fa60	1	0	\\x000000010000000000800003cd30a55d53f168623a75b86da1e566035817aa59f5caf89dd3b853e00d6b3d112fa865b072db9724aeaa389c13fb25c5359abdb80c1ec1f4a1edb27c6c6fcb0fcb5a48f3b78b224a96bf786cfa82d2cac1dab6ccf8e54dfec271fc07f686af225e2e5ba0495531f279925313512d1a2969e19eb6ec0c98264aea95fd00b9e199010001	\\xa5d4277482db7c1b60915e14bc850c85fb498dd9a3f1e431528c7c5076afeed52e872d2b59e1906a19e3caa5f30b56fd4b4bd97969e8be2c982a86fb6605bc02	1664954907000000	1665559707000000	1728631707000000	1823239707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x042b647cfcbcfaf49db835ef425ff71afbdfce69e40c087b80e230c13e17cbf87faf954d6829ffd2fcbb8154122491e4fee8bca4fd6a2b92f91850b98ecab691	1	0	\\x000000010000000000800003b384a1f28fda558724365a03cfe6fcc048c2e80e795b5309818b528ad0092a40e4cfbff34f79b564b11fe323ce3c3ee400d9924bb2fc4babc77db953c36a3910b197e4b6935516a5566488ba71ad8cb3fa0cfde08276feff87b19b3c133ebaab600d2550a818754874341f6f53e89bba18434503718e8d49bd9641dff496a999010001	\\xe812ad28bcb7e0ff2c4c13d1694fe84f9c6034407e79518e671166471eb478ed19c3ae4f959d228a372f16a9759c4415c98f8518b8cf8d69a0c044d21049b30e	1643192907000000	1643797707000000	1706869707000000	1801477707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x07af67ce08a4791a14fb875027e49a97760eec542e8730a5d050edfa6d6e13a9399b42e31a3e230938620fff41c2a295a7661fa9498ff8b9a48e16117b72c5f8	1	0	\\x000000010000000000800003c8ab8f65afac43df2d488e420935ad0ebd56959de6f83a73379397e25c159fd3d2eec9727fe50dd1c8065eae74ef3a11ae331bada3afc996b2b965e6e2840c232f4a55cd1025e81a238c9b267899852e12d7cd3df2817eb460753c679eccc5d0448d87a930303ef5fbf657288b2e8af81be25c2578815196084df0c2f871a1a3010001	\\x0faa78e9a3c8870222b6c9e055806aab4b7e1f54001b070e07f0fe0c634b80c29dad9bbc1bc8fc150c3c618db926890479425feb74bdacc01448b3178b6b1d0f	1655887407000000	1656492207000000	1719564207000000	1814172207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\x0abfc5db0a177a2172f0f8e733b216d7a386fb73036ac2ae164960e891c95efdf66f96959f458f826e3e286ede33b48cca4139d060cf7d75b1e07a348863830e	1	0	\\x000000010000000000800003cba50080bdd973411436cee48e02552d69ed48700096e13d197adeb0af292e3257d1228e2fe58a0fca5fba3acc0db7aa09f02a93e62c8108806853f5af5956936789d8a1a08f79553eccf90e617f731a3bc3aa49ed34bf9fc8ee79696d9838fd18743e1c96b4fc57b32df3d4501597e0297230f76565263765a3d7f480232311010001	\\x8f2eda414c06ce3b429b0b49854ff8c4d4b0b211066d06045d4bc32567ce5d92a03a0408adf148e77964911e2a721d3257a9f6b190e0a75567d6504422ae360f	1658305407000000	1658910207000000	1721982207000000	1816590207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\x0ed30b0ba082b9a32a43c2ff1892b3f3b13c8f6a3ad13353c86541635956f14e0dba290c21e7be7511cc37d4ef19643a5c93c41ca5d22c3b7e2c216197bf18d2	1	0	\\x0000000100000000008000039c311f5ac5dfb9ba0eeb84d5e732d5e34aac75b8bb2ad50c921ef825434f5679096595529020d400f9d58b9b55e94e3f357b8bc3d53d344f4268b6bafb1cfb8cb866c71262f8ee253e4c98d64da929d4d86eec23fa2db98c9f931b3d583daab415965a55c34c7c74905915a186a33b0e50a42dcecec7302862e415344375288f010001	\\x42b1119ba4f716627542cf8db80361364b559fa3b79d23207c26a1e5d75dd563b2bc486c90409453841abf18e290e04ff04d32d5ee52174933b64894f297dd04	1660723407000000	1661328207000000	1724400207000000	1819008207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x1bc34b1f8140adaaa6909ada12a65205fe401fbd3be39fba59e5e7c1465de2aa7702cb2dcaa8f7ec9a0d2e31d757dc520484d88345c480061a32d04d4bb82c78	1	0	\\x000000010000000000800003a9fdc3fe1b313ac8556cbfd9f31145ef59fe07c9d80d0a66842fdd9370479c51287d8805665a7672a593be255be8bc81d1015a8837ca608b95d84d1958c40e73c96f2406fa5f7543777af4d95f379cd7fcee80496a235b97935d8d1fc357c8b5d05d6b28eeb36ccbec2f3e03a4980ce46b148771e8eac91cc6255f23330f9fc7010001	\\x39a2496bf087053677d9aa81f8042c8170585e1127eb5ebf2cf200f4ad5e950525dde4542e636a5030f6d39caaf9f58920e3924bf5bd704abf4dc601842dab05	1652260407000000	1652865207000000	1715937207000000	1810545207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x1b4f0ec9000481a4fecbe0c5025da85add4b6944b24af88a2512c7daf58777095aa534cf27f9c9d7a9357e5c58d04e421ce81cc32dd57319a6e94c85c117d7f8	1	0	\\x000000010000000000800003e00a929d376e13d1ec72ff13a6ff0a8bf86c6b28f6ecca5c027fb30fa60bd832a3276c6c37ec9f97a4c52106115cccc64033116f870501e6892fbe61035b1ad75785008eff6e0b4b08cd4035c4330dbbec8875b8db5c66870532de85f4f02de72fce272e2b25bd6a40d9b453963fabdf08eba30a86dd99eb6e06a20637c52ce5010001	\\x4131a87c619f56c7058c1b30f6eb3b3b63ffe9c513a055618a0b385be4bd85a73a37c45614e516163e3071bfaed9699bc35b476070035d9c7faa5e975f0f7f05	1645006407000000	1645611207000000	1708683207000000	1803291207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x1e4b19b59fa6ebfdca50eb3fccf6661d21a6b5705f1d31e1974d2b2088f4cf29b4c7342b4ba32a77464d184ed9d4eba91fa1db3b626dc268b9d387c7bd83fe19	1	0	\\x000000010000000000800003e9cd9e632172b226a067ec7878da6b74b04094096753c07c7353ce4b5abe146ccf479ab25859c4adbb7651a34fc6488a544441e4f3c0a0d4ecc37a4c23d338fd2073e580f189acd20d6ebd923c210180bfe33db881455d82752d7bf82b4a2c4c88dec192989814f1ca35d17935cf731db6f6e3d7922f38639d4fbb74ed9c0aff010001	\\x53faa76c6ff4a11d085dfd149958b42a05b3b4dd692655aa82a2ffece2a1719c6d4abfca5c5d59b278263ef1cb1bbc5d6e4a5bc0064e48c30d75c5750f4e320c	1649237907000000	1649842707000000	1712914707000000	1807522707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x1fff9886f3017abe4490794578a073047d9e3d6cf055c759665811630bb3a4b9384e114d9af7faf1789323aab8ee6603380c15e1761a6c4090dcfd4a5b97bd1b	1	0	\\x000000010000000000800003c905b2b869664d9fe200d1aea2fde594ac72195c35d321085e1d66429bb46f441f33143755088f4e3dc64b4ba523acb745e0860bb1b24de7410949ab995bd41a70bc19ef990840232cef56f1c845bd6e5bcf3dc3e94344ab82b62aadac39c15bb59f0eeaf29007676282bbb7b83944dc18321d733705cefcf25cd705146dbc73010001	\\x381f690846c2d64cc0b34743ae6ac7bbbb0f8dcf6ca37c122efc051ce433b1dbcb86caa00153da6846b500f5a1908d43f01c1e95ac1d74170ed47a93dd4b1f06	1660118907000000	1660723707000000	1723795707000000	1818403707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
334	\\x216b6963c228adff11f60fb12d4b887f216b4df0f3da636fe9a19f9cea2de43f04ff541c643088845730b170cbe90dab826aa81030c6a9f18e128dfc8ffdac24	1	0	\\x000000010000000000800003ad47dceef6b31597f1d157f99af0190e6ea3fca47a4a11502b042c716fac747aee676bf8e34d5cb8536b24c7882730ec35c754b5200b060797e946a72d44c69da90e255c917dc2fe4dece9478e83ebaa5ce18e690c784965b8a3ff9bdd3566f0b57789090d47f1dcaa7bbb946d36db34a9c097eab8ee383f202174a1242a5f79010001	\\xb1e5e169fd756f6044e952384df5ce04bca78ceeea04d50ccd86f5dcbbc0e4ece85ec0bb220fbb68596809f75ff49146fc76ce4a4573cb681a157230277db103	1649842407000000	1650447207000000	1713519207000000	1808127207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
335	\\x23e7ee83be30246d69475ec4c3f7265a191f56df40f258c4f47aede8743d24fb48767345664c8a9c67e33b91c900c65786f29c344bc64487d3db25216842489d	1	0	\\x000000010000000000800003c91dce74d8259833bf450015d3cb340aa62bf120db3cfabc87e7377c4baab75306d4d499920219c9f2fb3588a1aa2c0617ee97f5ef0e5778cf05531f91b790e0bed62390749780a78ec010f06e2d58ee2e47caa5cd7debe85db18838bc080dbafb74f264df67e8a72fb86ef0f023076d2bc7174e76fe8dc6a98403091aa13a25010001	\\x1f7587d6f52c06fa3f1eade293abfd5641dca95eead8528127ed15f9a5d381a8c51e55c0fba124424dac37ca0d61fe6b39697dc7b903115772db92bd1d74410f	1638356907000000	1638961707000000	1702033707000000	1796641707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x243f22c4303c91d9010b247bc143ec89c1b3833013ae19d3d379a743231e2b266380560880e546263455ef0876181ff753a4557681e17daebda712dc0cebb75e	1	0	\\x000000010000000000800003afaf7fba97b3b6c1ed6bb36056074878018dcb29d7bee135f0d8451728c75f7effec0863bed6eaa9007a4d78ac7feb4897ef46d8ed4044180ecda5efc2c404d87e70e4febc24caa7d17970cb6358b244f64011abb46c3bfda85160cf427c14ea5b580bcef1b33de0d17355ccb4911aed0e594d00c68e36775aa5192d8f031b4d010001	\\x40826e23747db6304d73c329690c7181fbd9014ba58aa7e7b0eb4d4bb38d346d2c922c5af0e89dfef39c8df5cf5a3a38d77c53b088a955915ad44e200bbf2a0f	1646819907000000	1647424707000000	1710496707000000	1805104707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x241fcccc138a494f260b9809b1c97aea74fa7b00d0513647cc6022524bbad38c6e23cb3837ba6649595454b63635d4dc963ad061cd6337c4acf4766558b82f8c	1	0	\\x000000010000000000800003cc0f82b988572c955c7ad0afdd27335ff9a57dcba99eb3713d8b372ea1ec66ca09beba649f6b19578a366820fde544f2167d59d2bcd8ad8dd75e26776650ac5906dcc3d2c6a05ff05bfee0bb306d71e0c9a2027acbd5da47d76702ff0d18c46f4baef5143f15b4da11a71c6b42436196e6374e1a260d3c939671c9c1e179ddc1010001	\\x4fcd2e346cee8c25bac83f2e3df362724dacf9cd98f0b5a07ac2d15d47f193b3739d4917399988249fed625fa60f0bdfd7bbcf27735334a9d6b2e6a66a93b004	1649237907000000	1649842707000000	1712914707000000	1807522707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
338	\\x25ef1520ec9509f11dfe95d634a8d81371247f183fc63c5ff6e4bf8bb11588a4d62c3f1a093f97e581596046a2f99f108f8b83ae40cec1db9ff0073e6a77833f	1	0	\\x000000010000000000800003b2468ef50f7f355e32a278d6882baa9c73a1b1cf4829141caab5009e7b254b8c8581c9bb918a2d964a641a4092500b8a8d1b9671957bfa486bc9efbf107e265e938784e8303813c3b18495f2526e2e761707e2ee21c399b7dfa046c1a3ab172d05eacdbcd41b1e685603a701572c3f91995796e0534467a4c2228e751de5a937010001	\\xaa9339ec9c4b91341c9c0a7432062835312be99a996da4d3ca4786558cd27958d0abda7034ae3bd10414c006777bdeb2145ff9cdbb76733dc9aceebfad76700a	1664954907000000	1665559707000000	1728631707000000	1823239707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x25b7a921589822958aa19e0574518e95b21cbb28c9f73b4bb019dccd2a2286f78a7c6a1e2563ad3a306f310d300e773f9e4825149be366fb48252fabe2b18205	1	0	\\x000000010000000000800003a71bcffe16652d8ad9f9ae2722d3f75d8fad80f3b79963101ab39c8840e1dfd3980bcf5779c21d9b925464c3a432cdb8e326671d8a75445233415ad4ec0484f5c9b3c5a3ab50b721dc21a01a7e147f3d866c096b8bd7e0f165266e27a69cdd6df7198b621e541ba3a782ed7bd1c3902e985c380f55831421aed072369572a225010001	\\x09d65e376949716c6b8b383844e279954dc1c5552361e81c2fe64b05b70e0c6170f4130fef1550b2ebf82289c571002baddc009a7daffe21788a9fae0e973f0a	1659514407000000	1660119207000000	1723191207000000	1817799207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x271fe90d17b43067d3e3209d753b1aeeea2e177f2f370286948d24f03e594d83e9a8e969945614bdb4044feea546eb8ebbe7c9104bb7852da0c229e47907c0d1	1	0	\\x000000010000000000800003dfba9b8c837eecdf0c301577f1f06fd13f90959f5944a1b1c3fa45cb76cb6a03f09b36d4dd2af8fafd30b78a78c4b25c76395ffce7f34359fdfbc6c6a252178f50603d22222006153d378513feb1370d319ac17be56ff45a77965360b6a089dd5347a7ad9133f7e0041c462b0d4bcb280dd7762fb16fee29da968a67e13d4ee7010001	\\x94f547d98388477198f2ef2f03dda484e1362ec54263b65340565ce9e6fe8e757bb49772dfbfc317a83ad86d2200219f81327eae7ef53f3256014309bfee3006	1665559407000000	1666164207000000	1729236207000000	1823844207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x31d743f4278457a95ce33e665926bbd8a71778a928e7a2efb3ebf01ccaf26f638a8d342c7c9856388b5a545ae47d3d622f2f2d207f5385922c05de5773adcacd	1	0	\\x000000010000000000800003fc30ca857288bf5297ba34f97f8d6e8c35062765bfcaa331d168a3db4cd30ef31915d9eb99cae40a41f0da58704dd5ef6b2fb1713c352a926fc6bf43ba2a06739577eb98d44c2ae47793529d71bbf1d30d4ade19ef00fbaf508f8ae079b3540cd9055f848ffdc9b34fdfdd6ec5704f252c62e257211157a1a370f271b75ae4a9010001	\\x879de908693891ebff84ec2b43b6cb2df749588035987c11d16439fe2f156b5e3d84ead6e0c55997a47bc27f0fd00da0a88f4c0bea7e3c5433a09b9bcec0ff0d	1652260407000000	1652865207000000	1715937207000000	1810545207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x3247892e072261b3e5660453c0511f34ca3a3c67ebf7880f2fe0506e72b8658e38404e93635237ce938524dd735af51d4a34228b934ddfaf15aeead780894f1d	1	0	\\x000000010000000000800003bdafad9b2796108c0d254c3f61405eed7e89f9587eff9f5764387488c29a307c7be333bdc47ae403fc2f541055655724ce1a92bf13b3fa8ac262fb6a04639181419e1707ecbe589299d8a638859a1a1842ee08a777169fa83e9100eafb68ae5f871d0830d78b0c6614b7eb1faac8bb84ebe9e8460b41911009cb6d83b3174241010001	\\xce9ba8b47a38d1c8bd0dd25ae3ec3dec27deafc3e40e2c982007d9f779e09822b4e14b77c52c5e5524d26428e42302d2d91767b2028b3834c8d22561ab081f07	1662536907000000	1663141707000000	1726213707000000	1820821707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x342b17b631a6c6be5cb0471fb4faba3beb251f1d548c60fe049c05975ceb0a80bb64379021477039161c95b9a4f7b84d07e0f24a6d5e19cd5384e097e976c38a	1	0	\\x000000010000000000800003c7504feefc3697b323fa0a7fc5b5a136dc42bc30f56daf0847b42b55f12bc3df1fb50fd5c4b23e24a391d534fc944e007ac117a44adeffe83b1d94554757c593fa44404f27c13f3a08d7e4af4bc7fa7198cdfeea6cb3eb67db9c80fc9f9c74b2e9faffba11c0f4dc39777fdb72bc24e39c428d00494e72411365a96b1ecb06ad010001	\\x82715e741b910e914b40d387b9d58d2b05a857b45ece9910b41eef6666d03e929b7b8ec0f6fbca5ffa41d85908c711e28a992f52962702ac903067f422c7eb08	1660723407000000	1661328207000000	1724400207000000	1819008207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x376f76bff4809bee946bff4cd44465f220e1341b7d64e586a74d0debbe298e4d6cb0dd7b9958e95dd18448439e8adedaf8b0d789e7407f3888f35cf256b242bb	1	0	\\x000000010000000000800003cf0996e92119f018e556b0cc1595a64c8db2cbed40720863088606086a92e7f90ace4cc459dfced3cc91dcff5d1ea18af658e35513582f0caf3104fabe622d46eb6c75ea511358017611288f86be3f2e1430c8933886822f52ff31a138ffac2715ecf7abefb0a15bfbcfd35112c383047a98057466701452aa05286b4335098f010001	\\xcad8e39d9ebda0807c85fe8b25703e0f1b9703e2c6d7fc9751b5504d9223394af9139f5ebb7a00499a22f86594520cc2ea63b0b2d6e58a25f7a5177a64985402	1641379407000000	1641984207000000	1705056207000000	1799664207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x3eb7f0bd0371d5da80504e81b23319fa09dafc15805177308da295049079e4e82128b37293b36a6d63bdd634c21d7c108be21d939cc1c9af7603099342657ec3	1	0	\\x000000010000000000800003bc1b68c6cf627bf73e439e403e61244997ca485c48d975a7be7eb9ace314711c77d3b4f2bab6a175b6f458668a1bd6b39a39674edd6de252827b1e5fc8d03f3b46400f8f117bce2b36555c2a3d5c43173c925dc55a621f648f6ba4b8999995ac911756b0543a87b07fee6b01b84d2b1e194263b652b3259401051979c248320d010001	\\xe2ce5fe29ceb905fe19e665e6f51f74b37c1e7e07986042caa9c284f996c642d8877bc5f622a787c24c4df25f275ed69f2760a9fa0cd56e16cc1b9b8de9a3600	1662536907000000	1663141707000000	1726213707000000	1820821707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x3ee34ca83d558ab69d7cb095cb88ef33e9fdcb0bb5e34070b4a05d6af57906acdc3ecd6b5e486d7a23c455fa223d2535ef6a36d0ba6e94c792bf83a4970b275e	1	0	\\x000000010000000000800003a457e58a5be2d20fb78af304ce0d4585a7c85795b0e0d239296f0f07d2971cdb48fb143743c96a54bf59b7619f60c83d29596b9c3c91f364b5c6aeef1c68d87e05997016a1ddb06f2165bbb83414fed5e7d8c05f9bea645a700d26170b3f5e869c47ee85b9ac2b43fa38f4bd3dad38e88608724f2a113ad71fd61629f15c9ed5010001	\\x06e6bf260ec96d594bd6fa2aa8c79781ffeee878ff1da7791bda4661907afc9261ec5063cb97bf65eef757769cd0d8a1c86c49abc2c7a775e3d42235539b1300	1639565907000000	1640170707000000	1703242707000000	1797850707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
347	\\x40d308495ca8c9d817484e4f9a829bbd5f968bdd114a592a636cefc6598dde4dd665950f16aeea5477e4fdac4844e976b4840a2c9f3eb9bc512d9e8eda6b23ae	1	0	\\x000000010000000000800003b92bb46fd8891f363eb16a9711cd384f50c71dece422b34774251c929fade75f98c87cb20ecc41cdf11e994224a19e852c26a4227495d66f2d40f1930517c26cd1e04654baa7286936b60c357ff26927c013b0d5e2b54b43db1dcae021e3181bae98329ce6c995e20d928acf2460a9bd45b2fc0cdbd4564e8e446daf6ae443a5010001	\\xbc536307d58d8c238ff88e3e9e32f3726a528c0c11bb6146af7aea8cef4a73c747b0674af68725a3e70b430329312c1b01f802b27643ab3b8d6cc91106066808	1659514407000000	1660119207000000	1723191207000000	1817799207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x40af2ae8c1346efe91fac4e9ae48e226e51d88d145e1b8fb71b98289d8f640ea001cdfaf55b83b38aa9ea8d62e934cfc2222b55b9c32767a337046ee987a68e5	1	0	\\x000000010000000000800003b7f5776ca6eb8f667595b2f74f8ec1e6155ec99394f2507b4ab8188dfb5dedc19884f24fb7d9cbcc2ad8027e76e4d91a8e41086f23f7fd18fab0f15dc30588bf2d01e8d3c5bc02025311e98858a37a672543c51f342764cb74ce9be47dd3bbd1d3958572a95c89ef1140220fb914d018d1388f5d3c1ca4fdb8e00b2397021125010001	\\x417c2e70586cfcd1cbb78189abe0a87161dad353d6fe23df1fa310a97003bc9d60dfd482eca4c05fc81208b886a4aa37802c7dc4b6465e1a95e9862989e9de02	1668581907000000	1669186707000000	1732258707000000	1826866707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
349	\\x42135986613a618eba058ebafd6ed1458136d7c4f0f42f591ef801513c98fa5b6ff0eef10db5c332486ae7f482313156a46303ba893909d92e08c365ab2e665b	1	0	\\x000000010000000000800003abf1859955479097189c911dc7543f39ade7f033f6952d0f9a373b451af34310563120f36a1c3937a38a745c023ca9ff1eccf426143f9ae68ee31f6997e7463c31fa5d80b406532a84a319e0376391ba93f7713d95dc0dbec4c479788ea3056bf2623d18e4d8e670258ae477df632b6beb6c5ae4a20c3f70b12760b92561a8a9010001	\\xbb3f53cdf31a62eb0e0fd6230fe328576f274b7967daa7d8cf26593d7a0517c35e7d7f2f103e77c55f6c47f8c8ce2f80c5dc8da3b8d29520552fe3bd8819e804	1661932407000000	1662537207000000	1725609207000000	1820217207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x4227ea57795dafb2bc7a8ccca72adc7eddb5433bae60362a3b2f90035c2d6be791e46878b347b1399b7239436ca25259f236ca8211ed1195d34607ad438e76a7	1	0	\\x000000010000000000800003a75466dbb77656fac778461424982bc7852e62a7314ac57fe2ce603d111b762d098acb38fc70d8eb7a884ba4ec4649382df045284dce20279050805c4024c9b18dabc7a4926efedcad8be472f2a97874f4ac3a26f561c39a15079f0dfee4d8585699e4e104fa8c3fcba2deac3b8f00da0fa4c19fdf90dd53b2f8c10918a34e75010001	\\xaeb04bc458915b474f38ab1eb6c3ec9e94d5ea955a0b02f197236c6f03e12c1177883a9fbf06298008244a3078c732969e067d4c0d0a023b19f902a1c89d6000	1655282907000000	1655887707000000	1718959707000000	1813567707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x44eb53adcd4844ef2746294765343106ec22fc8f7e0a9e70d9c00d5900548cf5a8cb1bc997c36c615965cd1f28f08f2954c839749462394fbca9d32d2e3db56c	1	0	\\x000000010000000000800003bd87536c3612dc3ce38d5506591fe865cc222439ecb88996e16866133cceb524da659891f97a9e97cb5698bc7824c93c9bfde3fa05d1e2a98040c1876e00d0efd8ed131f701f75e3fa187dc8c520f12c1289fce3bdcec37a399e45a091da84893da29bc20259dd2d0b1e7a7e587955913f860a2d336c620eb070471476c6fa45010001	\\xca3db5dbad4b2f3af2f4a43b90b5fe4612efb1db5ee75eb39f5a649855480430d92c4e5cc7991acc1f181b2a552a2cda4a18fdead3f5f37e6609bcc4fd1bb20a	1645610907000000	1646215707000000	1709287707000000	1803895707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x49a31a3ccaaa25ce12fdf8dea809e58bae7fae65007a45d22e7ad9eee3076bf3ea385080867f53240c02b9d0dfb17396160c970042450baa12883ce7863a08db	1	0	\\x000000010000000000800003ec72a24de9c21b6368ccdf5233dab11b7a3a881baa29ad8df498b7697b99fd3ff47a33715e9fffcb310f9bf8d486e1130a54ca5ec148e6f577bc552bca3fa62082d485062d4ada39416958d90822518b54c8657372bb331df71d4a334f6d5603da67c1c71d6d5938859639db2b74cf90fc187311a7b18b434e8133ffb4bfb3df010001	\\xf544cf71d58926bd0fb9c7647ebf2d687be993938028bab9a78fb2ee73b9c2558347475887786dc4413eecab315ae3ecfc081ad6fc8519c42a47eb3cc072980a	1646819907000000	1647424707000000	1710496707000000	1805104707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x4a536ab5ea131478b12aab71df54f2b8514178a9b7089be704dc836ef1423538db6f6fbb0b77db4edd81061f236d3915605c2ed83af7c820feda46f19c8a8b46	1	0	\\x000000010000000000800003b5204e591a063de78d6a0acf90689295e7365e96e4d4f52cdbaad032b004bffd7e7791e3b9fd5e10122960736eedd48aa8ced1c90000478b0f494a1cb4257cbadb13266e10a4ba450cdd600add61befbb6d2fdb57cc8aab50e4231e1c6b76b693e0f5e624c0e99531c42edcb789f76e5c3cfd173731c857567a9f993d077f8f7010001	\\xefb5f12dae78608955517bd59a63e75fe30cbcfe93df06e8e853127401943b2cffaed5edd9dd3ecf6cbcb52b252e9cc0e508717c34a133d0b00a147ea1586301	1657700907000000	1658305707000000	1721377707000000	1815985707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x4a3b662db6b2bfab6d0eed343a23ff45ee5d1c3a0838b0af881be201e5e3a7913aa1f0a775b5a9aa6422b207b0f672746a3aeec61310ca2f0b24ebc2b37619a5	1	0	\\x000000010000000000800003acd96988721d004166a78e6b323f843eea3fa2fb0431ffbaa73782776dd4fcb7206339413722e0b34d313a3e5090fe088b3e3b0b1a9db4e46b465459794226cb09c20735342a9aa99cd597005253cd9911223c9e4bee7aea385d83be048cfea666bb00501c65294817d40632a17efb16f9e7fe4c73f3f809f9614b3bb72148b9010001	\\xc9666aa40db731916dbaed05775d8ff566a3b6ecff85f657690b92c27e461a12b6824a23129ca55fd1e3f79f8b8654d5d33bc581a1f12579587ba1797faaa407	1667372907000000	1667977707000000	1731049707000000	1825657707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x4e03d88a06399c8999ef5c18dc318fa2fec0d82130f883e244a97d50b7c413eeb0752bb3de496f2f0fa40f2afe52f996e54564d81d5cdfdef2d3f37d3214b91f	1	0	\\x000000010000000000800003c319f56955a9fd9ac3160f2d4cf905ea8dcb05ce037989f1f2ab9fb60717604646db1579168ce18c366ce99a98c347822c7829c4c2873197d7eb167a15c338e7e1532696a268a065133caf006b5104937b1f3eae703dc93f28a6218d83f43a93727a56b20874d5b19b7b123db8ae01c71010ef3548e279e7fe2c529c291c51d1010001	\\x09e20bae8f8c8440e1004f2e3ed15f9e2f4495086e908ec39cc062cf69b8a8db5f14eae500595636d22ce2537f2e69c927ef007c4c1c30df103a36cee5601c0d	1669186407000000	1669791207000000	1732863207000000	1827471207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x50975260f940828b3f235f30fe913c74407ea65fe62fd466f4ac1dac5a374f672e9146d8345603c5a8fe42ddb7ed416f191a4692ef2a4d9e42359cf2dd3b411a	1	0	\\x000000010000000000800003d0a0447d328ee8c1b3a275aaf82d6fb3349805907a30109bfc1a6d159343b9ef2579b8187e9c5b399f27f002f7224350e77fda64faab0b5b2ad930f05cf4c85653b44c1f95f3b3c6671eb0395abf210a5817f90660e94360c48cee9994e53cbd97296d7cd5bb94ea07b25932c0665e574d13d9e53d99d0542b7dc37bb1d52cf9010001	\\x70d6d5c8e387a236368678530db54b46bd27615cd458c0b6a006c76e216a9311579fb70472dd6889524b6179570deade84803c6caf4e47a1dc82b7e18add9c0e	1661327907000000	1661932707000000	1725004707000000	1819612707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x519b18f32230deb250235823914a31fc803396254af99ddb2c3f352e46303535632ee4d2ccf13fea394bcade70ea5096bb08437faa635efc76eca26bfffbaa4f	1	0	\\x000000010000000000800003c622b37c9fdf57233f19fe9d9ef165f08161807a8b3e643021469d798fcd716bcbb4dc042b96e58706040d5a272a3f40d429bb772f3f77933244f690c84ffe79eff80b41ebf2a9afadf24005919b1c10cf99807774e5d19fe41d53f18ef9a35e00a72319f67d93d72b9f713de1680907263aa583172f108da57691fccc4b9ffb010001	\\x889ee81515d876e4eb68f5780abdb9b1e9e26d810d3ee43c11f3a69d385233a78797dbe272626a9d2e6d95f6f5796d7a31c27b95101f6f41f46040600dd12c0c	1652260407000000	1652865207000000	1715937207000000	1810545207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x522fd2cfac3c5f27613d9861d3973f2afda56a629ace1513261d27fb79dcdf52a21f6347d1555e5a77b17645aa0d8aee3c8e3ee08091c278fa41e964f79cb359	1	0	\\x000000010000000000800003d12aca62606de4ce58653bad7db67e54004090be5ce8c372c1a46417e668655d2f32118193bffcffc090a0b50a2b79369147a49412f79ff0b3cba215cd9f634a93e61a2baafb00a6728683fbbcf1121cba0b6de47ec7cf39c86a0c7ed949a5c46fd6442946d2843fdbdfc3c69c7d7fa6a4c7da060ec8229c4cb5afb8b887438f010001	\\x9bbe19234be37d99fe1e2d3b5c02346c3bc77aa4ad49287225f09aa2173e32de6e2853ba2b0ab08a628d5b74350022a82c9eaf900c2b69042fb6150811fa5504	1667977407000000	1668582207000000	1731654207000000	1826262207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x535b71f67a6bd7155d124795693f79a887f13169cebfa9db0539935d5f1c4e5d773328007e2f86f5a660e7b3e150ba50ba423696c25808de39c73b8943e1fd27	1	0	\\x000000010000000000800003e43b88a93609747883c6d22b7a86aab575198ab1886a749cc3a3c7e92df5db523f75ff6d9ad09e5c5be5300af420deab9db24cbf83ba4dd0b27d58c4a0100872a432504f5ec9ddc072132834ebb568adc237e29c9c4df897347b96668e6b37b12535bc0d7313f8b2ac03e0bf719ff76413532d59021be670106c371fec7ae10d010001	\\xac1fe8ba2f9e81e629154cdd0e397d4a9e10e406dc55e1d4bcff06e500d677f83636df374a8f12abfb3e0757419f9d7f63b93ac82e68398a52b3c7e54fd3ac00	1652864907000000	1653469707000000	1716541707000000	1811149707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x560b99f079d078f81b60b047c7f27f42048a8389ae967f0ae51c48d6d43d1d8acc7624bb8c3b477beedcfeeb1807a00a8651c2280eb04f1efdd42787fbce505b	1	0	\\x000000010000000000800003dba8709f1f798175797ddeea3081b95e9b9efc68fa4a92b3d47c842da3359060f3cb1302d1523b228cc089d5172a538aec7d833a5042f69787ff29652c05a0400dca5b77cf07bd4accd4bdfba224077d27598731e10fa9d9deefad2650db2920b82ff5ad1e9fc29fd92045dec91162b47160bd32c3868c2fee25b21261918f1d010001	\\xa8ff30cf84362fcd9345d79fe08a60cf2f4c3ee0310602df229028fab0b585e68c983ec04c6dc73ede9827d5d6bad18a176bf9521e834006d7d283ddeea17001	1658305407000000	1658910207000000	1721982207000000	1816590207000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x5d0fdecd6fe79d6e64d19e97275983dc97f88258423f90559681cdc1273e958ac7ba0f7a1aeb22db233b25d67b2c06ccbc909ccc71f53334c9bd517481518902	1	0	\\x0000000100000000008000039f4270cc8fe195b07de8e73101e88a4528462afd2e37ccc4ccbb5e2c541cd4e7cf14ebae709cce9c7b5d75ad43fd93b836dabeeeb2eb8f6485389f7268e9319542945e229ebb8da905759c2b28edab8ec67b042750d9df5ed87f86037da096a18115fd29348890c261b6548ed74301eccd85edf354ea31337fbd9e5216373d1f010001	\\xdd01020ad3654dbc6b3b48cd81d9473396676febf020b955a6878c7776351e08d2d1ec9f537db80c953ec2145cf81c5fe1772c7494fd1adec2aee7aebba5ec00	1648633407000000	1649238207000000	1712310207000000	1806918207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x5eb34af1bbd39f4fdbfd4b8e3cf70f7cb625759d97bdb80e8f8736bc5093f63807cfbedadaf4a9c1f77122e3959d32b7418e6386638fda126d768d8dc1f97d81	1	0	\\x000000010000000000800003b6e2619d3e2491c926db9e61b2fa9111e5c5b574de7ea3009bc32d87178491fcb7e1d456df57ae4d1857fd02120ca13f6e4867b34bf9ddb8d2ddf6cf74bd594161a92412fd09809968380211c3d246cde97ef1f4e506e7b9bb5fcc50b1ad9f228a596c11ef51c23804bf1a97ac2ead3103c4a84e58c552f3788346de62a324d3010001	\\x6d39c69908e89e23e2abab1eb1d513bc7ff51627deedc816e1dc7127f990a99d7df00d2bc2769f46f9a533d9b26eb12a9ab8bd4c54e0977646abd92b8bab3606	1669186407000000	1669791207000000	1732863207000000	1827471207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
363	\\x63f78cbb81ef3024443a852e2995441359bea505c1b742d44bc84e12c42bc3498d27370e8de467bde6ddfef8b6fd7e0e82027ee68428ba7214d991ee1a09abb4	1	0	\\x000000010000000000800003b15d4f5000b97f820186546ab62236b4842eb3b1fa5b9239743beb6a45e2f7b997642bfac8e629ab9d2a42aaaf33b2fcd1efb1288fb40afb6528cf377c351c2051125339d210b72dcf3c58855762f66ebc0d25513a82a294eab8c7ba04296b8cb27b1ee19462b080c628f8596d99729efd21418abcbfe1c8342c002c9d163a15010001	\\x855ad3b93312fdfaeb9cb7810863ca065d5f24589ec29c4031849f650bd30e94549b750b3a5ad5875b5dd0c3c5cf15f18df9007c88b35510c41e4b5b22acc90b	1664350407000000	1664955207000000	1728027207000000	1822635207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x65efcc57d9de067e466ed49201fedf574951967300cfd5854013b31b34749f46b1e3771b10ab1541500c060292a739ef367aebd23a3032455cf6522aaab2dd60	1	0	\\x000000010000000000800003c8d56c7b3376379114edfd303aa03e7a5dc694b91c761f7b3171b232377ce600e80eed8f1e22aa7b6ceaa5693ac1fbdbd4f1d1f17f18be08fd013ba0869db60e1087d31f72dd2df2e9156fc5db842f70c2376f7d2eb748882c206080ea6e6f1faa606074755526d3bce7750485edf99d7c0551ecd49eb7410f8680ab9aff080b010001	\\xfc015605877a987727b4eb69f071a84653a7f63d9e929f1c007cfc1f2789a92a379e207b5d537bbb80fb09019ead8e3ca3d5fa11fa204e21a00dd232731c7b05	1645006407000000	1645611207000000	1708683207000000	1803291207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x66c7cc9481a5b81957cb80bc18ed5edd1914a24d5d4c75e433dfebea26e3a4806cc4d2a1997b929e2cbbcc2219b7bcc370cad01d6f76e6c5f6257a5a777d2731	1	0	\\x000000010000000000800003e6ff68a75222c9484ea024d3f160d9dd2d6b2f38d321c4ec48787e161331b3885ee368de9cdaccedb442d8e6e80e12b7314573ba2e1dd816a3e3b5db2c61ab0d2c027ba90766292beed2c7faa5a0f19d3d238d1bded9081607ec15e4e7f12c0b4309c848dbb108da317a4699abd1a59a18377699061da57cce0156bc74273d63010001	\\xe9f990f1a85fafbc46110c4ee35f79f5ba42bb294e150004cb8c7071dfd3c31ffe39fda158d6f052e98e52a5da09d1ab41ee1d24897ba86b0d4d9cb79b63c200	1658305407000000	1658910207000000	1721982207000000	1816590207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x6f2feb7bb007c5dac58927decd58680ce6946daf1d34d727939672b36b8ae34456e28899971f111db74cf7b6d60405d84aa8e07bbd783c108d31430a6e41bdcf	1	0	\\x000000010000000000800003eebaa0e46fc36cbf56b7428d62481620306aee225407daf1716d07ca69a14fabaaba8a44b5fb89d95470162bdd57b733e743f592a8e863e0b9b7d7d35642ca413b470123087852fa23f12c78bdbb7c069bf57ee210cf381f522e186df589d0d8692dfa0e9e6323fa51e69bcac98adbc4c86b5256967033671453f01680565765010001	\\xf16322dc3f1536a9cbac4f83c735b27bc28e01bce31720fd428baf05454a0e738007ad1de5729e8ad1c784ef551613586fbbd32cfcae390ca2dbabafaddedf04	1646819907000000	1647424707000000	1710496707000000	1805104707000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x72ffd191ad2c26163a97fb32652bad4b4efad03a4da2c53506b75ba64fd6feccbf42eb213ef0421cf1a35dc62f57666b72832115fe23fbc871e91c1b937aec1f	1	0	\\x000000010000000000800003d549df5bfe9ab880199a11cc926d003a6073b8b251e6bdf44bd4067b70c3e54c528fd817648ca013032f75f637c4f9c6f04eabbfa8fb576dd10a47756d090c3d8cb305ade0054a8b9c97e13a6e8289c33100ea1d8235cda871646e7984fd1fa8e90680fccb25860d9c0c5e9a85685a1801a5dc8eb69990f1686c2f01d79b4d83010001	\\xdfa306fcbcf57bf9da9514334989ffd1c2e01b5f96c21020de76899a63f50dc8cfefd926e1c2659e738f84d636d63af073b599fc78075f8a4feafe45f69e8b06	1660118907000000	1660723707000000	1723795707000000	1818403707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x77237d295d8bf9ff02082898d15cc8f409de908e247dae2d51c9b7a0271ee21769cae1e2be0c497b2844254aa408658066df3d27b431a1597bc4a7afd60f0d6e	1	0	\\x000000010000000000800003cb46e1ee4292e84470cb5ff6bd8a48017b51b6bb4995aa2ff896f4cdbb5eb096f00132e7ca2ec9f62f2639a1ef55fda926de007c32754fbcc3cc43146e7a23d01dcde7baa82a2f5fcf4381615f20cbd36509623758c0f997410e8b165582521423a1e29d3f0eb94bab052e2091a84efa12cb302b81a6151955e9248aa80ccc9b010001	\\x676ac50717cc0655893373ada8bac946caed9d22387d8575a6d1a9d43879bab8844e35a1c60fa7131ba1b2725a914b67436e7a5fd344712d270d9298e4fa9c0c	1638356907000000	1638961707000000	1702033707000000	1796641707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x79a3527ccd49ed19548636934fae0f1da806ca7bfeda2c18e02ca14870e2a477b765ca1948b4e1c4265771b645ec93985efc6b287ffc510f46ba7d91b0d3a931	1	0	\\x000000010000000000800003db2c57f08163688cd408025e8ecf984c3d29aafece1b8b36e26c28270cdaff95ce05cceb5d0b0125385e0ada8e91a27ddc52b356612d4c9d75cd9b353bc7faf5ad99d9b878e1dd16ea88647120c0a16375a17df37d5790e1319e08a2b0923134876eb87e5111c75ddbd4a47ceea243f76ea6e1b3c60c8eefdcc602d7f294a205010001	\\x2d776c44781224eec988ab35d9ca4e462bd3597729320649e8d1fa042b07ea28576e747c220446a7bd014c777c70909f236a08aa666374aeb3b814ad589fed07	1657096407000000	1657701207000000	1720773207000000	1815381207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x7a5302518ab4906eab11ecf7864015cfc7622001a8dff66f87b03a3df1eb8f5e680a5f0d00f0761e4cae574b13b75d92cbaade7582ef9ba43fa7db254d3fb1a8	1	0	\\x000000010000000000800003df9d094a0d86e424e3b40840e9d54db7f44631eb8b2824a1043fde40434e94ebfac2cbf37353667d329868a721db47eaf069a1713b6942dad242d1d10abecbb6dce87a3b45dbc7308e058849fe08eb590306a459fea69eb8be92ab87f247ddf915bd12ce2c5354cc8ee876ebd7539d656acd8607affacb871fd2bf0baefabc5d010001	\\x91d1d1f6960f8f78496641f490d8fff86a779c151c14f013d7e50ceba3e19a96886fe73a83275e457bca34c05fefb50dd2978ec05da69c014809e34f5dfc1b0d	1660118907000000	1660723707000000	1723795707000000	1818403707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x7b27f0925e0fcfa589c92248a95caccb1f7c779cd27f41e0d90f9d0ce82aa09fbcafdbdf5b188e2d9ea918d24b8b0149fecff80d03c7c4abbbd02fa4bf5a28b5	1	0	\\x000000010000000000800003d4acea9bd67a584a95f8e755355c8fbd75fdc8889d6ade8bd01436a3b32d7187be5726eaca29c71301f18b6e0ba74219907e41fabc5a2f98035c41e4da527ab5db538cf9618288b6f2e70af78b7b205eb9519eae12030c94814048ae0b9269e266439bd1dd7f8932fdb0c8e1831b5d0496247c1d787d8d7b2f97aa92d6a01641010001	\\x5bb3aba12fb69160bb83b868bea73c317fd96af6bbf34d39576ff09b0a8fde2d4d5f5633e9374eecc3a3eaa6fcc178565204d48e289a2e1e9786802d6f472406	1651051407000000	1651656207000000	1714728207000000	1809336207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x86ff1481296384128d4f4810ed0c7413fa6cf02a90f21a0f9a21809aadea89890b2487c166b49caa74bd9d57ca4224ae8ebf409380a69b20166ad331c792e17e	1	0	\\x000000010000000000800003d071dca4efaa4eef8967ea1452293fe90769ada3ed73d30f1ad10c91f6bb90c75453241c401723b2810696c3934bc93f29ec856ce75ce4a800b44e6d8871360d26a90246f449e254374246d30e008e921b578e0ff79aa6e34d4d82dd5675dccb3f7b3ffe13c78ab656f45f845c2b47b5f7e8cefe25bcace6174b9c343b515ad1010001	\\x9119c7595e3670721e1c5ca24b6330fdcfa180a04e045f9e98d56b34aadc9c8e4546c4b582d469451682441de6cdcea3cd8137fb522787acb695958ea03ee80d	1658305407000000	1658910207000000	1721982207000000	1816590207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x87eb9b3d9a314ea975107e0d3d0fa7435bdbf1cedff99aafa8a1d1aaf8f106e3832ca05644456564a840128a84a8c00e52572c72dead6e8745600390f609ede1	1	0	\\x000000010000000000800003c8a076dd9f0d866ed368b65bdec0f78c8b468b9e4584c632f596266a9ff70695ec727d9474a2163d45f43582dff7ecb02b6cc2062d3c516ab4f96f99528c51897cd802f7019ee802646dd18edd9a85bc6ffc78d7b43df9b264e770875fcbc1b58775c684d62038df28dcd32904f186fc52024b0fb5e08a1b403e196faea34257010001	\\xd9fe35308d7256538eb62acaafe931e6754e6b9043a37c9528e8953d8b98ff23e442055230ac3032661d1bd6915e9748feb1f35283ec2a08d8425e15ab3a4107	1640774907000000	1641379707000000	1704451707000000	1799059707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x8acbfa4c3d3d35b591689431706a2d54ca7431751292d4210a8d31ffe0fc3c93ac78809f715b0d4d5d90425f844d57548958baf6853c8d145aea276f579cffa0	1	0	\\x000000010000000000800003da81693f32ced4ce97c18c644b508cd29e0958f09f545886c18d777e72507d1a57de13b38984be4500cf622d7c3496c5cf953f11fb53e984c8d71d87f74df9b5d62bd69c363cb15399ab153d91e3bf81c03b708f923231c9a6722b24b8d25b8093dd3dfa269c16e3a90791018a600aba8ee61b2455a121fa3dc693ede473e4d7010001	\\xf1a82df65d6ae836e990fe56f19ace1a04572d735981c4b978077ed72cc24c58fa37c95c06d609881afe0dc1f25cb2e91a5216aed4f24617509eba38d3a49900	1648028907000000	1648633707000000	1711705707000000	1806313707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x8bd3dc16f35017666b22977f26991656625bdaab29d57511b0379e23a539ceff590de64ec06401d05e75f55a4b450c484a479266a3646b896c18bd897d6a365f	1	0	\\x000000010000000000800003aeba3c1478f37319610c94f8183daa4cf230c1e2de70312e99a6116990862c834a26322594007d320f1e688b59684a7456b18b012015c6517abe65c01b1b30dc3d606b1ab62f1740fc5f25b4b323c8db17e60e25f5e3ef35ddd7a30c8ff6e815c2fc4caffc2558e6dddb7cd8244263b7ef1cad1ecfb152f99fbeafd5c129d3f1010001	\\x1a50387c04dd65d41737117279969c506a3e3ab91d243411e20348c5cf11b5da584dec6d187899d63f00825c8ff5d4acbad11eab7bbb29abc6f0d43c14e81109	1655887407000000	1656492207000000	1719564207000000	1814172207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x8fe3aa7bd51f07c1ddcbad6a5db43b44a64652cbe4af9cc984897235371018457e34f1c9200d79f0d59b1f16f5dba728549503de2b3af4a7bb0064cf84164282	1	0	\\x000000010000000000800003ad13f7ad2199fbef172b4c56266bebd9f32bf8fcb5a43eb2cbf1e62709726d6ef7ac5dce6960461eb2f4c3d9cb71289a28df4994276e4960055ab21947db81edaa22c0f8a68fb78ba6e841a50152e44ff5fe6d3f5b979a0e99ae57e9020f2483f7b90f2f4de547155cc7e1f517e220c3e0e6b5fe947f1e94d578443f0a50df6b010001	\\x0b44a171b9cfb9933dfd504b2ff426fdd36ee88b30274f383eb18aec682088ef26dd6fd9582344f6738f308f726d75597d13aa948795821b7e91e5141955d208	1649237907000000	1649842707000000	1712914707000000	1807522707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x9617dfc32fbfbc9bdf40975b7852974ebe4dec067c0b5999cd385cd9c6c54cf410bcb69516f37fc6b705d541b88305997a5b8c97d7f08e50f53bb7eab695b8d4	1	0	\\x000000010000000000800003ad6f289ee36e6fd287dde16f1047710d445044d3e4214b3b0ca43c0ae73a6313b6b54ebed875916470439ba65e879db2ced833fb72c91a95560ca8b3032cdf350b31e44631a192a6db09125fd3243708ce291383365d1ffbb3816df58e3bfc00d6a91542ce7f8ebbfc49c1a102644cf1919456d755cc67a84d8e40a39a5f6f29010001	\\x39fe8a5bc8cecdddf0e9da73b618d165915a33c29fd2908114b686c67e49d44ef39564886133a27130b4ff2bee180e91cbef59735e358a10f997027bbfdccb0f	1656491907000000	1657096707000000	1720168707000000	1814776707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x99ff5f5ee3a999acccf33a08c305951b4d52b04333125be26775e16bef65509c42e5adf09d4d66398e3de6d184a28defe890054719a0f5af07ded3a3f1fd1a53	1	0	\\x000000010000000000800003a8ebff8f4d39c31e5b1094a2fd8d7c78af9f98a6438298e2bde89927be55c6995baf8cf65766bc34ca3555ba4c18803373871016614cb2dda57859d327cd3f618c19e9aca0f329f07fc7764bd93995364a8ce9ef7661915c1863b7451b10c2cf304d98c41c662afd79ba758aa792c2795335be747d2d58ee90249dd4f596cf0b010001	\\x244030c4523d52bdadf69dfc22f1fdb44e98cd32d71780a67d1905cebac74419b4c9420f22704835dc7df78d908be4da6f06a905fd96a2db6fd052e78605d208	1658909907000000	1659514707000000	1722586707000000	1817194707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x990f504e84b4750c746af47a926c13c7897971b59ba16c8e4fa4a404d138038c7efb52763e56fe4ddf8445c9604674cf2b354a10db5816c01ec0d1a08a77464d	1	0	\\x000000010000000000800003e5d42c50a33a51df1387a2efe1ffbf3987e7f2d76fedbfd5f0096002bfaf6328ecfa7ff45723bf96bc6c6e770247d0d071ffe05e2c799a4048fb2a5b55814b4a01df40aa7c3ac42f2491349bbd52d802fd49c95414c65a808356968a4ac561f5f532a499fa77a2e2d34bf4af6b381e297b1eeace3b9026e9f5e16ea5341c03ab010001	\\xfa378a8f88d9a87ff17da52d0698e170ae7fc9adfe8eca65f117ff9f2c8f6da41daa8482ccbfd502f681b049e8ad57db638fb0287b58e0c9346025fc5370ce05	1651655907000000	1652260707000000	1715332707000000	1809940707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
380	\\xa2fbf6e343bfb89bde8e1f743c1cd542cc0ce4d0dc605e6cedc3b256711a8f3fde994a780440bdf513485897139eef7c694ce374d8ee91c3172be806e28a3a4e	1	0	\\x000000010000000000800003bcb1db30678cc17baaf20d22ff003d54a2148302f6a9f07c26692d5551b2928b61d62c20f7b9a7eebc8728a7f46da0a69cf073f6ba4a6064f8500ca14fe6549d264c50cbffc4d262f171f0ba5635913bf3dbe52a0cb18577999f25dafd816718ce5b2ce417e086dc935836e0fef212c204e3dcaa77c0a4d9d8aab45112efdc67010001	\\x0f950425b502d1d7c7633686c268ff299d2a9364e19a0720ca168755a9622c1dd02bdf60fca3f75a4378644de1730a6e164a6471557d0b588edbaf10ca303800	1669186407000000	1669791207000000	1732863207000000	1827471207000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa437c99908dfbe0074ef878005f31466f31ada86566b817d9da73b1d8b4a60510bdc72e4cbaa2e645b85ee122da34ce05dc6384e76c37d4fab7fcbd4665b830b	1	0	\\x000000010000000000800003d000282d6fd43ec97c1111b29d892b27b3e48dd14d506527d007d69b587ba2065c5e2c58b4a0b635d41c305e51d0f1bf8fca4275c1c22d3a8c953298676f720ebca6fa5768b093232613d0b8f4d15786690a996f9e8e142640953b92ffdc455b644a22fe24cb597163d28962e2f7265bad213c1ff59f8f051aaa23ea400e4e7f010001	\\x7afb6b33db15a35285ac29a8c97627d296c91447a4823cff5192607910d368d6e73701232208e812bb03cb5001eb1c7f9c67ffed9f9d46232ba00d7942335203	1669790907000000	1670395707000000	1733467707000000	1828075707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa78fe5edbdb832739a21a2d32d1569c0f21cb4fc2b389cd4482e7d6cb80115fae88b1bbf5a72ca59ff39aa586c134a82cc3db785147e4cb58bda5225452172da	1	0	\\x000000010000000000800003ef0fec1f3d5294687b7f424f2a1c8c515c2cdce3566431e4a309d8fdb89227c8a8d0c7c8b471b93904e71143a5a8e2e43da0f9abd01af144ddb5af04b29228e9d2aabc44a995716ab6e27e2bc649b36f52d40624a82f713862f5fcba89eb6d25586a9fbf1bfe4caa793a8b943842744d8148e01300dbe22c0010580e16dfd49b010001	\\x391ef1ce4a76808c0efb29ae0bdea20f938b7c67459aad1c112cc31f91b377e572ccfbf68ae60168a45a0493bfab47f4f24b1f601351b9657c725dee7b5c1a0f	1668581907000000	1669186707000000	1732258707000000	1826866707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xa94f458b7ae38750af48dde34daa49cd9b61d5699c8ad9aeec9f6698e47205bafdad6a8e956fc20fcacc37a79eca8f4378d2d2a8b569948d1c9d3e003e184022	1	0	\\x0000000100000000008000039bf5703084050d5b104f15cbe040b08f7779390746544ba02a0bd5e54e88aa970c4190819892c1d457b2f90062939a57f76cbc819bc8d2924882e7f8073816c493ca3542d335da201f7721b9b3c2cf0e5c07f10fc190f63a27da2178d65ca113c230847cee75135696fe14d25f277f4e62a1b56860b9ba27b2572586f8de0511010001	\\xa4840e8db9671e4777162730b59b3a4f5cc4ed8a0fee767b5e35344302d9066ea892d09d6a82b19cf03409c7e5b4af142fdd633443f2561f3cc3193ef795ae03	1652864907000000	1653469707000000	1716541707000000	1811149707000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xa99f1cfdfc0a5cbe36be01ed9395975f540d4a87131f1f9c00ac76293256125478398a490e1110ddb0ebbc9d5ffa03b05928cc4199d655546b27b9eacc0f8ad7	1	0	\\x000000010000000000800003c3a13a0a42f66d7891ba74ebaa8470f84728214309be52d2a15cf32f7e8343ab72d47eae83e4aba052e12bf33b734541bf772a01147f9fb95dacf12c4a480179ff1d48778eb3b6da91d0b3084055ba7e7afceb54138acec19c73a9e5712c2aad2c21a2881402ba3451b067b3303fe7328a21dbc7e73a7613115ca2e6d3cc2671010001	\\x7646e5269de58bdaa7c8a1c9e7039449770505d4ea4a2330bffc23fb5ffe5f061028830f37949ff15b1038bde0a3324a829770c84e98c20179687a0ab6bbe508	1660723407000000	1661328207000000	1724400207000000	1819008207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\xafa7e1117a99af973af20fe6d33766eb8b779ffa1d20ada900ae98e8511bbb07810f59026740d3a19aa305497e5f40bea09770a6d111156297d7266e514522ad	1	0	\\x00000001000000000080000398d7168d30c2a87b711bbc900a8ca81686a0481564d169ed4820d533dfaa4553e36f4dba4922551062f23319e1c1612215c9f6dd8cbe04c7053207a44e79024b114fa9fe5ea3e5a254d9e8cd1fe9ace965f9306c068265745e690da2bba5bb0be280a5d44fb2eb274604d687872ad1c7cee70a387c7c2f93854e76110a07c073010001	\\xefbe1cc96469ffd5b12f49ac5da9e12471dacd72516deb6dc8053da3711a1be6b5687d88466b5fa44fd51e148f6050d34e8ea04292b7ab86472029a8eae15d0d	1657700907000000	1658305707000000	1721377707000000	1815985707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xb14b20cec071b2afa387faa2c48d17b59b799c46857297608767a89210cd70f66a3a2f549d56224050f86b747759d3717f34df47a50e57ab28f54c5587adbf51	1	0	\\x000000010000000000800003ba13da38fe00fbaa81523a07a025b8d77898d54cfe15a688b68806ac5e5e4dca74630fab69140570fc26a1c6765eaf0e5cbb4dd699cebcdaffe1e3899d59844025d01e89d3cf597e7c2cf48291cc406cf18c4df78955bdaedbf601ac0cc3276a1fc1f42e346cb0b844094fd29646c94e4ebd480861c5d535a197f4fa2dd067c7010001	\\x6ca06964d86635557421f7ba0b04f4a0805560b01eb4e5c8bbb6920aa7c1487feb9824230f983fcd15f976c7b7e90191ae3afbeade95a4be0b797142ea88570f	1654073907000000	1654678707000000	1717750707000000	1812358707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xb2b327c878f779ff09f1f47fe9c24aff40fe8938fa2ef2418cafd4ec8adaa0fe2e814cb9654b7c86bc5a626652eccf9dd983726a2ccdf42d161ebf651a9464c7	1	0	\\x000000010000000000800003d6badbcfd2f45a3160641a3c76b839971318cc08b15f8a1160f74a375ee6d47be4535c1b48f90e8e48dc957c93d116c85ab4af5e6c650515d98a100bb1e1ce128039c9a313d0735412150fcd4dd055ccce2ca304ca77606f70d102b7c364166546a265d885e29a77e43927bcc499190022b2beafd49413a4f1dce6f3b66df3c1010001	\\x3045a38516160f7dc5d35bc2fb1581447ef7d95a45db47fc89059e8a50ebce7efa813145bd8390543b79815b3289ec43f5cadd688ddf27c5cff05d0b7e165d00	1648633407000000	1649238207000000	1712310207000000	1806918207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
388	\\xb5a753a28125213d0d051f652e20ec6720ca19e3e02d4fc21556760a3215d3c61cee22b4f6ec07bcde41c45bab3f74fecb8fe7b761cb7e7e5bb3c35015333a80	1	0	\\x000000010000000000800003ac5c22aa66a0e30d662d86fcb41ff3f810fab78cf079d9f817fd2422289d0de4682173b46ce5058b3f73ee5e46791b71e34a11d6b4305311e1c52c4b03644a6160b47e9ccbebf6a336e50d52eb456f77c720190589c3ddb996b3c022dc50060e12e4d9507a035c9bd512b25cc87fd7066f7ff9950de34426f3190db3e605a96d010001	\\xb5183dc7fccf7e019b86a1e85dd09fafab0475f115dba85d07a75fe876861a65f3d6a5fbbb3537681264772b7abdfea00845872cf265433db5d09f5a60f5370c	1647424407000000	1648029207000000	1711101207000000	1805709207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
389	\\xb7ff80b0a2ddbbce801e67ef0e0e5001eb0e784f45a7e15aed999b075f31dac93ec2afabb75752d777977e59c18251b745d3fb8f6320e19cd7609434b0b3d354	1	0	\\x000000010000000000800003e00f8e8cfd287175310df669e1216ea6980192cd73a38cad0c397946659033cb415d8cf64068c2ecdb67ddf3edd84345a67248515d298bc25e3095964babd54a5c035d0dcefc1b6652f4922e1d2bcfcf38a91ce936af4b24f656b681d60e5bbae0b816a9ee681e2de73af8c835bca0310ec4674b9ca135e0d986cf0b0e93cc11010001	\\x2818080fdacb3c80856c4327fa1c1924546ca0f969ed93c99c020f286df997ed5fec4e5be7570686b6bdae90982fb131460b9e905208388ca8d6b979f6603d0f	1668581907000000	1669186707000000	1732258707000000	1826866707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xbb2b81d485dd5d6a74c4afe00dac5dc6a0895a32e916e386b60cd5509f69c234f89db124a5a2af3826d22b50010497ab43922bbe709732cf229ab3e19be40d87	1	0	\\x000000010000000000800003f05db0b491304da6867c398700f54618ca28dc13b4153878abdb2cbe7bbd4ef2f1b57a8730877bb5b752c54859b0e264079c303bf056a34539b828b3f65827d4c56f30ce9bad98e0f3994580398f438fd152ada0ea4a306a9650a3cf7a51de503d53c37b710e2520f395f9d2e93123f2ad661f7d247a99d9ce54292565d8fdd7010001	\\xaeb100eba69c9b8bdf2f72b7b32bc9affc201832af94c5de8f89eb04749ef1371c8ce4602104da9b8c465bcaa56cfa38dedb20624defb70dd97e326f111bb30d	1663141407000000	1663746207000000	1726818207000000	1821426207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xbb4fd1867b0e99289df037213a839c92ce52e262f59b33aea5608e91be199b5a749b65df5442cf1b71d0878c75b7737d8d8316192dcb175ad2e5e62b68557d87	1	0	\\x000000010000000000800003d704f7c16d9bd9fb963ba18447e05a95ab1926424511746905c0401d5af29ff829bec522c801da8c901279beb78805d59568cf1e885d7840ca1e62c92e271be4afa95740ab72c533339859a4ad81a4f91050a609d2371a3f0aac71d6b889f1a95a4fde4d62a007ef65fbcbff56c9d829b72ad7f81714a5a421234a3da16c8775010001	\\x60e159e72654f2d18c9e84b37ca16925af19dd0a47462d0570448793a8aef8a95a49dc1531d20823d7f20a611d08c7f9c09d1e78e6b79974567c13e09388c80c	1639565907000000	1640170707000000	1703242707000000	1797850707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xbdbb93f47041ff7a8b490a2b1fb55282235bda5773f200fd7d4a56e8a54a2e1c34d15fc2a140136cab7253c359f0792786077f86b7d38a8478c9d3d9d6653922	1	0	\\x000000010000000000800003f07c198b5a24daf91ff6c5a3b5939eae9f6f379d3ddd6fdc48d9c1d2298ff4ad7f09dfa66ddadb9bf67088a15ab7c1f2a3b6136685f44e2ae8a14dcd6ab77ec70f1f8abf2de2815210ab2be6a7410411997f0fe8bc8f32c0f062b4c2474a20898c4c845635da8835da9f7cbf88a44e7ba41dd72035a86a2cdb8d66040d0c64c5010001	\\xcb1f79c8c001321e74f8990487e6fa697dd7a7c058e2c9bf01997442bfa223acddf6337f7e580a587253113990952237af16ba3c0d244438e2abb7a878eb2104	1640774907000000	1641379707000000	1704451707000000	1799059707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xbfc33d0c4d8ff750ada338ae1b0ca0ab95af7f13f80360683d38683e15ff32822eb377da9f722b385b974bad49a84f224b115b6020cdbabb522dd61e69fde0c1	1	0	\\x000000010000000000800003ee86ddf546f47e3a6ebc0a80cc98fe5ebfa8885ee73f9fddf104eda9ecf329600a4c7c3dc45123840c74ed52b87e42e2803a9607274c8eab82896334c8ba3a1118eab4a8955f8fc279e78b0f9d2d2ece638b127ce3c1179c5e06e52b7046ddcf1374c73d8078b83f59709c819683d5064c84a09621417fb12aefcaebd5645237010001	\\x22747b859750d745851ee20f90398cb8b923ce750f9d643293117c0ed26e0a0ee71140fd42b43ac62717419db64f969bc2c9ffd872fabddfeacba404e1563108	1648028907000000	1648633707000000	1711705707000000	1806313707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xc2c3af5a697fcab0ca39d06eda9ee668dab198a3b60a35ef770e7dfee37be1e354b6f72ae85f5dc0fe384fd7ef072cabdc97b253f9ba9f81ba075a48b54fd53f	1	0	\\x000000010000000000800003c4745ec7b139207783eb5b61e9b9bf75ddc66f678a4b07c606be631dcbdc30b963e2fe921fd3465d7e4b822d7e26b4e9199c431a93ea2d9c8cf00eaf82aa90a703213965f2e5fcf09ce93a5517b20ecd16786cb48972340aabe13216469b72a107a73edcd51f3414285764b4f9ae491e2870884e7fee9d026540d2b635dcbd99010001	\\x3f31490e541681f2c43aef291711571584a477f19e2577bfeda66f6ec16d06f784e2091442d23d9ff1dc20f120e76180b34212a3db31d45f1892f02f74957f0f	1640170407000000	1640775207000000	1703847207000000	1798455207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xc99b04800ab16979f15fda289b6f2ee2f3b6f349fb594b9fa4536879329566ab7657b66699f2e93a7bb035302e7f35f6b64bc736c0189f50618084ecb0daf931	1	0	\\x0000000100000000008000039d4fa580a2d9eef33e18915f38029641b39aafe73b5b5912ea1445b95f7259737c3d562237e239493f1b71aa72174c8bfdf3acc56a48b656d7f44c968d9ac2503dc47b75d5ad9b036eb76659a5013e84f0d7acf5c4c0bc18079e32197d6eed85cb4cbae584e5e9f2d2600c3cbddfb2bce0f9ba04c77b851d99383a9cfa78ac47010001	\\x19edf26f814b5dac84628e4fb8fbca6e8940c66ad9f37a9f356c2bb422ddf0b5c42e7af8397c6b8a1c016af976a8bb8a205531a8b45ff48937dc7c32caa13e07	1669790907000000	1670395707000000	1733467707000000	1828075707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xccc3ccda35d855917f602d86381de6106bb75ca74c2244529f96bb1481b460e9b2994defc206976e3b39fa170b62f617b935dea74e2c2934fe8baace5e9b8f0c	1	0	\\x000000010000000000800003b455bbc39fff26f5c5e12f7b2705a9a54805e96fae7091b543af91a5593d71621d2edf7b49805879a5b626aac9984f073310ff8197b0ea2b667921003ed1fe88bcc7d3eb6a691234ba10bec69b79d60eb70db68cc148e04b226b6adfad445f83930002041df89691de61a855304de48516a2ecfe0b91bbc4412d1a004bfb3d71010001	\\xeced69a6e3c947c9194dfd3e52b09114aa1bc9107dc289a8485ca9ac114a562bc1bf97f74a2d4b1b5d82aafde9b85c87e4f3ae2f62b7a351635fbedd4c48ff07	1656491907000000	1657096707000000	1720168707000000	1814776707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xcd5f6694b1cd0242bd2dc0fb7b0713a8d6a93556d359a3972b939587fbf48940f2852bf2a6d06271870e932cfbcca52c358eb5f7b060005a7818a9a383649c49	1	0	\\x000000010000000000800003c2df16a5dc66227e302bc661d5f590315a258b2953c4689f9e22b0f768970c97d27e9f23b8062692f4fc7974a2afa068a8c0dbd2617bf85d2b66da19ce34ce6f45ae3ae636975c5b1562178f5b152e2948228bc0704488bafb7b764b6d423fab0511abb34b152fc9321b1420acc89be2c92d8eccee9b1f14a7b18b8a9028f63f010001	\\x2bb5f85eb2082967f14e221ced11667bf6d00ffe9e1102aa8004a55d5b8a41ebf88d099b4f4e887fc99369822b1b77986ef8f6301d18562f2bfafd98a5c5980c	1649842407000000	1650447207000000	1713519207000000	1808127207000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xcdd7decca0ef3d431b5f0c83e13fc817d2c0a882f4fb024421de8469fda9aed200ab4f325f94138a6114fc1e214d292aaf964ff9aca06ec0bce5aa18d41912b1	1	0	\\x000000010000000000800003d7078aab8d0db8bfaf151c09115804474197305354e590bd966a7f5ba3a50db3ca8de39aaaa7e2567937d0b274c2b14ec06d9b1c4c865222ec72852dcd6d2bfa03af04efadbc54802615560dc1134d30b6ac944e3259371283cd7c188bdf9f881e112fff91bd1a03132ea2ff8adad8f7e9a0c049ec6a138be7640b6965be7143010001	\\xd0eb8ad8e0303c9d8701e1212ae907f62cd47eb204f2c955c9efb76ea4c033b3e287c90252c335895ef523f865990e8af90c5682379ea6a4d3fdb2e019710505	1654678407000000	1655283207000000	1718355207000000	1812963207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
399	\\xcd135953b5cb1a1390353408c380af80e6a4e05e81b925171e4656eedc05b39db9f390a05737abe94f981afae014e5cd6c1ec785f9bf2a1aea74f91bb7fe3686	1	0	\\x000000010000000000800003ac92b4cad03d16cd82136f781a30c6972eda438d9f38461ef72a5f344652be5de8614b12c9ed6da2fb0b516d948c5edc491cf1724a757ec88c1263a446075e821de566828bd1334a7efadb5f3464bfe12e3879d0cc91ff970e299638ac4e513d39cb807cc773285d883a232bb53af8453452f9fb994cb92ce4f983a5dfc402b1010001	\\x4fb5dcd28a8c08f1afd4e2f155815617811074655fe5ee7e7ff337466890778dc4c5bc5bde9af706a802f07f4d58bfc14165045dc51d2c9eb31005576e5cf005	1661932407000000	1662537207000000	1725609207000000	1820217207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xcd7f39133980fe514ceca61cfef32644414ffe1d7dcf4171713398c28f4f00baad48b4191c375e0cd9754597a94e4a3bcc8c84105e8a4ebde986013685ff74c3	1	0	\\x000000010000000000800003ba133edc518e885027b0d44935a79afed0c510556be79164094409be1ddf10598fba240853204ac130bf85ff881fdae33a53029487775ff252fa4c6c0779311c79b42300c48b926054b0998c20f064bf44718a0b0c6fdf48d7aa5a0a73dac3ec22f757d1dcb595ebc78419139cd45a8065450874a3247ab94725c44650f332ef010001	\\x8f143554b8384105eee95953a3ae7db58e79fb79523ec6c2ac2ac6e76390f3f242b979111c2d6d7037760071f1183327c6af7d88e90a5c5410ef6adba684f409	1655887407000000	1656492207000000	1719564207000000	1814172207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
401	\\xd06b5e3b47e340bd2d1df0e9e351d195e64a1dd7b9e68136a066eb36441418e848f0f1ecd3e6734637f5b6b2d31fead7ff0d4ddc23649399147068eda445af0f	1	0	\\x000000010000000000800003b946c02bb3dfa48742663b8fdc2893c25a24f175eff824da4638af345ec86f657dda453d2073eb86bbc8db3538afc3dc367c667a5125fb77c6a9ad696f32e159058cd31dc52baf072b951ee8c8f3cc02f3ec8172a0eccb94d6d334f7c6c265e9664ac56408e3459b7ffd14c44560c3378bba7d84d510f96658ca717b5f789e5b010001	\\xb436a88fcde97a00a8729b6bf0a5adfe1085ee2dafcaaff77983513b92e36a42303348db3a171c4c760c3dc8fb2992af94981e746c4e90ff45c8f3d932659702	1660723407000000	1661328207000000	1724400207000000	1819008207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xd3e32493ee2535dc47b00a8b84fc94b86a6e7e978b51798e2d427d3b94205e12e908ec04e399b875d7ef62ecd3ee1d9e92466966440cd95d85b20ad78b51e32d	1	0	\\x000000010000000000800003cf3b4c19e1c394fc50f96ca420403ec4f20ac3d94bc2a5760410480522b49c525a80814894836f7ede904de7ca1541aae814c4c6a4659b9215bf2d4ed598195f2d7868b0c45d9b4f2cbae55d64d6100ceb41325f29fd475b42bc37ac9bc8de03453d238710aaa49c89131b94eb38e3e30fa3a825e9bfd065538d59c8364dec31010001	\\xf77741b28a9b62fa78617ba05882627ac61eb264ccc821d83a49f852b360f628f748a991db2694ef6623b5181f017fc8b93121d706dbe42dc19dfee1877eb80c	1644401907000000	1645006707000000	1708078707000000	1802686707000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xd66bdc10d92f4709e7541fdf97cc3826105ec0a4f19907404d9b6208cb1d33ad52c4f96f67b04401e86de20548db21a36c3283b7bda2b7241391b1d5fa7b097c	1	0	\\x000000010000000000800003eed8cd91771ab3c6f75e06a6c78d5591c6d63517950c7bb09adbe2e104323710c6241018f43bd132b38cc18d0edc562b269d7ea765c43372bdbf1efcaa3c9266fdeb09f4c06110c9f03865fb32523038fff6d66767c2a2848fbd12d8f2694601aa26bb3916d9da9533c96b9b7d05a9cd239c4914cb14620089ab29ad840d8191010001	\\xb9fa42d686599bb182053477da14e3faf7ddd9d0159108e7690ef3fd8db9eb600372f75aefb65897020f522cbc8881c2d5312fd9f3c7c06659d78e637aee0708	1662536907000000	1663141707000000	1726213707000000	1820821707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xd7970f0f2d92b9097a4b490a797ab837e261055ea9fedfac2fde5ebc9b460503008888c2d9b6b3cc9dfffa432338a1f8a0c6a98e9216e76491b2afee1827586e	1	0	\\x000000010000000000800003e28cdce3179d417a1cbe63180e353da12bec8b5bc1f212cee3302483f92e1eb6135ff3e45735a1a7d0a8e94f79f79cc16cc36395cc3852df17be91a67e827c73fe02d651f313ebf0389e0b49a9094528d41290519779c7da4a0b28217ff5dce16dd108ac93b064f578fdb6f10a55a4f3011dd7445ac7b17c3cea731d95aeeced010001	\\x3461f4bde099b1a651dca8064f5dfb26c0245c4e1e221cd5fd0682c120f7069852c17c3430f1f12b5cb43c98736ef65c4aeb0776d9bbc001834e35128b388400	1648028907000000	1648633707000000	1711705707000000	1806313707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xd827cff00124a10f189b98975ed7fbb1eef20ff8d697832e9a49793d84627461a00275b4428e7688d706b1950e6ad7511b33c1ce98cc0b409174db1f4fd67f20	1	0	\\x000000010000000000800003f4b86788b2516dcbb7508f94129d06fd07212ebddc41e749284c689570ce672c5a47d640a3c19dee0d3a0692f3961cb7ef6efad191a32758c9fcff72c64f267cc79fcba1889a5757db16fdbad1b5e78c8ae69f2c34137a3ccf57966f923e5000d148c2dc0088461e878e3e56522e50a125e277f6b77a4afb0d3d7d17c820af39010001	\\x11d37241ea80057d93dd20b1f9efe22df440072ce26872988bb6c1adab73dc036544aa92508fc1919c8c5c35001b3ecf59ab36162054a9e0d54455b4e6c4d70e	1643192907000000	1643797707000000	1706869707000000	1801477707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xdca7b4b9208f73f76797d452767d8c0f50532495000406d42a4bac366eebf5265c3be843a4e2169a8fd9f2d3b616ff3ab45ea221f39526d910ad5cb58c863691	1	0	\\x000000010000000000800003c0761b44fe967a4b7ad46c979f4c3374787f0f693d846efa38b8acbc1a1b9ff1a2ef4ade1520df07a904f048e3d4da7f7b070effa1041f61e96c46b5a50965bb0a9b6a8486478eda125b1a13b8c5c015aac105352d00c15a52c5a308cbe39b90f87e501b16b32bf894a3220802ec7950845c944b87cc4d81dce22e2378ad148f010001	\\xb9afc278ec16057d943c4fa046a3d0aecadf9809f1c91b70e1b5d0f478a1b5887e8717cd894684f1eab116ecec149ed57804020fe59c61a5c90864c7330e2b00	1661932407000000	1662537207000000	1725609207000000	1820217207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
407	\\xddc328ea9a7291fdb7e10d37c4f79c73523e91d0630cdb6b30d54219e1788f2b951d7f93194a548e8f1ee646583bb158d83910aa95e6ad79af6351a02c41d36d	1	0	\\x000000010000000000800003b037fc934fd95a17436f4e495291c1cf80fe8bd04cff43370876396b822137c9e428dd56fce60ceb0286c3544025f7273fb936f7e1f0d835dd77f4c187b8af4da1923db0de428397d3fdd1fb0388d18055c484c1241b5d82a3f9185741fffb93dbce23b8d5671d296279f75ab40a86bc6567ed629b1d0bd401fdf6c8cd9a28f9010001	\\x06d608cbc53e91a3e3c9f76e10c95da8e48ce57b9292bb37219d7b99b745d8cae74a2e0ddf77ecdf7c87c8419d499f4b669d8e7f3b270781dc62fb386f03d30e	1667372907000000	1667977707000000	1731049707000000	1825657707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xdee7a5c873775fd4080265c6b378c040a45474a1ed5d4e7382815956e0c4bec4d5d168b81d1c8fb75037876c9c0b265ccbd08b7379e716b126ba465a23bcc985	1	0	\\x000000010000000000800003b72bfead6af31055e4faf30c1b7672f3133a17d8b1bb75c9b4e6e5782af4f3c0564a0e17a0a3f0cd69d19eb0ab8bc67c86f02fc23aab8b479b643c6f4e4b670427f1b27ae014db04660372ceac361617606afe0fe7437eb459101d591fc250a9918d1a169f4653062ae99f16f615921a0e9a686216e0d913bfcbf8a5a69cd333010001	\\x23c9ab07c55b026112644efc984bafae8b4427684f6122dd7d08efc153c4c3895e11bd15a60436ff97653d58bbbf44db034aaa2f10de3fa4c9cbfc909aa7f00b	1664954907000000	1665559707000000	1728631707000000	1823239707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xe5f3915e7b0ff30245ecab05a5bd785009f379e599c57006b10f4aa50e5bd46cf3f61898befceb08810f9ea1c7410c76ff4fc4176de25db54083f139430476dc	1	0	\\x000000010000000000800003ca21fbb287b1757ab46ed3e4ec908ff9f7a33e9fdb038b0e36019d8a42dfd332a12473257f3cb568dcf8b64d902d514d56264b8567db8b9dc48bd1ae8406c561ac5ffe3375f0876b9e2435a7aa8f25e288035a2254176e28d96383b2bd7742a14dd70be4d42eb24a264ad640559776c5511d2c0f0c2ea41b685029b286f451cb010001	\\xe84198507e10c03b8ef22e12c23bf63590ff3eab4f10ace2f5a92b2e5ac30e073d02e31a01a1637762aa12128e702febaac5f464f1e929bc225c4801a9577e0f	1653469407000000	1654074207000000	1717146207000000	1811754207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xe6776adb5e7d94f74f2b1d1c7cff6a7864340484a28b226a8e4e31a9078a001ec2daa7197937165b8865a8f4681bf7cce12e6f9f459ce8d2eeca3fc1097270ad	1	0	\\x000000010000000000800003c6bf1e60df8d6c06b3c901d21db54fcdffd1b2a06d118eead0cfd7520f908a6971cf926db45d2adc37e8cac4cda2aee8031e3b3da325e2a21b8d3398b1c3c4d3928b0dfdfde97dea1e2d796967ad04106796426b6c50d3c39a8ab5e077ec6a6a2605f6521267342520872b5f761095b9f22150c29ec791714f7fc29f2e901b83010001	\\x5aa893ed230b99d32e6d69373525cce448266db79600abc2fe0361d78c3e89515ccd4fa5358a2c11f40b45ac6f21ceba72d1dfa0baad71a9c5c18e5f4ebeba05	1645006407000000	1645611207000000	1708683207000000	1803291207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xea33a43acaac9d46dc9ed659328724fca21f73eda75fd8d7682fa15418251648c8d71d534f0a50e6cf1e3aec8ee3f78321ce261f45ec60ea90014c5bdf96f973	1	0	\\x000000010000000000800003c874b9e3fb697a73d0595b23229b77945ec0b703a2eb06f56336fc6bb27884778c640856cf37b60aa1212466823902802c36bd8ab51bde7f7d4635b695339b5e3fd7355cd15db24cb6e6ba0fcbc43c146161ad47fa11c84002ef0ce212144d82838da2f9c7fa36c9c3fcd44acdc31dbdc745cdd1795c611f7ba0bd861f77c769010001	\\xedf7cab4da3f3f1934071bb846db999cbafe4ca7bd6130ce5b44a3888d3c1a4a4ae0eea0b30f7240f5fc61ca7479c4a200043c477206c8ce2d1b565fc498aa0c	1649842407000000	1650447207000000	1713519207000000	1808127207000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xed23289b0e1f39f92121d8670dcb26a809a55d0bec14dc732de2a9bec755cbfec3ddde6e8951a5893e6328073586f59f96c2532dd77ea311c58c375f5a3d2e97	1	0	\\x000000010000000000800003b084aa1c3679a36d6b5eeac6fe88f2cd5b3345c52b4b6bd2b623df0af40186963719e1aaaf1dbcd46ce648514592a2f4d24c5c24f977985bf4c59225a2b719baac8bbd5dd4db736d425ae2f85e5aa6fc0fb2c056ba5f6019ff0b945630f1dc6791e5c536cb7e6bc252012eb36da7df455f477c2d149962e5011955029bc90fdd010001	\\x78d304075ff6632bb025987bccfb2c6aa8fdd0ecad485ef6862ec815157a2cf6d36a5fb2c9ecb456cf7cfc650432fb6b76d69e05b815da870bf44e58e7c72502	1657096407000000	1657701207000000	1720773207000000	1815381207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xefdffbbca519758402a56e4e186b38e77ca4fceafc7935f029465184af1330229ac7e824bbde95f0ebf53757a4703af50911bd12d094970300701463d2974787	1	0	\\x000000010000000000800003d68416bc011ee9cc9724c2ec7252b5e2d192fce7428081dfec8410348d3d5780e0fd7c82e494724313f3198df76e3688583bf20ea016cd22241491c43a6c4b1e8c8ea857c2cc2776a7a4a46fcc1ddd65d8f1a41b9e2be958e4d9633e2a36bd4aae64edb98d0b9553756fda5e58257296ba5bdc0d71ea7c345eddc849822cce1b010001	\\xa327839831890e63356283bebb3b66647296011f956e0af3e4781d3b0303ff617dd9f392eab6f6ae1b2551fae8057419906e4986af6036131a1da9dd7b417d0f	1650446907000000	1651051707000000	1714123707000000	1808731707000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xf1c365d5348d6655b3328d2d2a31f05413fd807ef61c513a0680a301ca90162fbe225bd0e561f1954cb3c273960ad2d888296c0ace3622680de9403def30fe18	1	0	\\x000000010000000000800003b707efc21bd92d7d38189e5530374ebefe15b899d7aeb4e41ecc393996cbaf55dccd9e25f6b7c96fc23795974e5277504dbc264215d48e54d161c259c033af18c83c0a33cbd011d33a8bee2314662f36f2905e028c056034b5abf3d199a597eeb49919e515fd9607a831cf43dc1f3ddd8b1add89051ac9a74b77d79d3eadba2b010001	\\xcfc5f4e6b593cb306f53218bfc3c6ee4d328fbc9f451da0c3bad8e2e8dc9f35939bb5ce1185c12208054f1bb1500afb083b07b77e17445f805d1b688e76f8f04	1640774907000000	1641379707000000	1704451707000000	1799059707000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xf207b867ce9f54d9f19e8170ed444242406f2d8693678d924bc11c1b4a1b19235d8deab348e4c1740fae79af6e5d04127d7ed2419c5d3d3b267e3e9dafe36582	1	0	\\x000000010000000000800003b7d19309b9a5393cb6cf29ea3ca1a42ef8179d8a8907523fd7ec3379d5b533471eb652c76891780d7ab02499416d4fe4189261a11ec0bb1b75135904302a64245298ee871e617c0e83838fd668abaccf70a627b625a2c54c9b4c2c5394ef4e62a7a33d32a0a08feef25b9ba5d58ac14172dedfbc2607d6f06ec06eab4dd1c625010001	\\x85368c8d8cb02d22d1a4fa26e6f979c5f33e95e5b2e8678cc5d7ff21741a1cd56081c95f647fbcaacc0302c8d4f9908c3cfcab018806ff7d33c61a452eba4b07	1651051407000000	1651656207000000	1714728207000000	1809336207000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
416	\\xf5af984ef4b63bbad0524053c7d4427da00fe2de44c9c73a20a10d3211c540bbb74346823819cd0ca3d464d237a3922c44c0fb92071cdb6acc4d357f4ac49243	1	0	\\x000000010000000000800003aa5103953f746c41c89cd82ecbf44ddef0b0fa59d119153daa3acecbfd0b0e04fdee3274e01978a0173490a57981ca5da1af3260db397d41f5b84783567ecfaeeb2bdc05e02b29fa122b66d96adbf7e82fab5b5a459b40894b24447663bee17e239a5c6f31f6635203526c799b2b842467615efb67dfb0a6dbd3c60a5295ca85010001	\\x1766a88f90b81b7e00983cc8955114be30d70eb49e79546b722e5e9218914f1ddce748b5da58ec01233b1e3ee61b8d0e6258fea24ccd234147ac3429edf65300	1646215407000000	1646820207000000	1709892207000000	1804500207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf6f782d75ea7a470e3a7ffc79b78536abce6143954f364debb884140deb6f6bdc68ce6d8a41e21482da3ad79254d7528165040b5010009239006d172d2ed5d56	1	0	\\x000000010000000000800003b59048ffe432c0ed722638d3db58e83bf85ad46f2cd82d1ebcecd335bebc0385770f26420b32e6c851220829df7712b15f92c988ccb8f0834dc5625d0e503de6c397a181085cf2186fe74032d655f17c38316b46be3a05275fb4b40b0674dde5c44cca7e9473efe1bcd293c1b56c27234a275fb69b2f7f7ebadf5e60204f133d010001	\\x6b8177de8e63ea8aee346cee8a6acc45157fcba42619e6b74ca51c5b053a56221b80562c6a0920da1a2cb431bc8158cd88385cb60ccf52bcb5a65ede907f8f0b	1662536907000000	1663141707000000	1726213707000000	1820821707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
418	\\xf70f2890bb8dbe239357afa64b38f79d20c647096ac714e350e6517f2a2a09ee97c7a316027a362f6e5ce118b9e7b67f36ebf5b5ab9a3fac2c625cbd28e53692	1	0	\\x000000010000000000800003a9877e18d9a3950dd58619475efe0b2de838842f612503e8f5dd6e5a23279c6515611b8dacd2dd61e262079bcffb883c6e36054b36cfa0e8794c6102267e501c357211859112edd3f80837354efc2de10b74585b62c59cd035c5f6a096e90b68ba814e475d0c2d79ee8015cc9c23b3148e6d8914e4b100134f02c7923f28dc03010001	\\xc32439a01911b822d3d3c2d08993520bfb5a4c4774e1be252aa012252a5a5717749bd455cb03add23863d0da4dff98010acc462810225572e490fffafb177e07	1666163907000000	1666768707000000	1729840707000000	1824448707000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
419	\\xf90f2a38dffd6fab044e7b827b1da1792c772c665bda398a31ed823af5fc00779770c09ed7be2abc5556aded53c6fb032928abd268fe917724e729f33075d4b6	1	0	\\x000000010000000000800003c3f44c0b78ec94fce547bb062fcba2d13aa5e5ab6c298399a43f47d1da8166d26370711f6e53d1911616c873c724ff4cc3b83ffb62275c07335c8d79203f4d07baceb0af4b1e95691d69b5a2344c268e0f295680013d575c8087a5eac71a4390777c76a13bac16deb3e4563e34c63fb13b8a8ee6ad093cba39c9c51846944aad010001	\\x77521419902bf79cbbc6a79c06937e362c581c4baa3536a55c5ee547b661a99349de7af801c4c1aa92876a513a14727b6e5c50d00d19cbe441a38b867b686909	1646215407000000	1646820207000000	1709892207000000	1804500207000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xfa134c4c491cccf953a7768fe942db20234765ab44df157781e6f60e05076c0af9d89c3c5cf16bcff18751f04d1247fcd4d1afd3a9f5d62bbd4671b382a3259e	1	0	\\x000000010000000000800003b48e504dc0e47b3bba11298708741d8b41d2a94da6b0fa8e5f3057ec0f05f164eeaef8293625d2b95975c7c094d86ca329a5710b5db576af6eedb333f26fb80fdbb163c8c99e846efb0cd88e55a33d276e442a27111364adb0bfb7a5eb9557e4ff3166b68e4ff19f71fe85a04c51aff2dc5fb2d744b36a6fca79e7f980d38771010001	\\x2508735219f6e6f13976a5683a940a004a1861e2eb03e66141e3c25413ab5eb9732cc76aba197212e40cd2d34ebd6a4efd648e7a5787aae7e295a76fd02cd905	1651655907000000	1652260707000000	1715332707000000	1809940707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xfa4b3180c4565700be2cfeaa68eb5eeff1ec05fe70a3ccdc1708a984cc6bd74dde8ed63858e8f185c1c7f177f8c5d5f84a5b8f8b74c09f84ae475ec706582060	1	0	\\x000000010000000000800003a41ee50ff4ac56eb446ccce9e0f2188baa7e3234576a8a0b6854582e925fc52360f56af6a6115040dc27dbe10633302fc1c63601fe22a755f3bdad4bd08281eff0e096d39098ef50f7724858c69050342ea9dfbf73b97c8f944e01c29bbcaf9d2a493ea158d643c9247a7a9125f028bc5117fc8d3e27bf7a8a47e9923ea84e4d010001	\\xece054072f0b7857bcdc8ea0ae507d9b5dec7bef3676cc548630525b8d5d423469dbffce0b38513c9846f763b8d381acd8a69002198740374f6d755f4e1ece02	1652864907000000	1653469707000000	1716541707000000	1811149707000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
422	\\xfb8361b479b6a5883e276dd8446c325dc780cd3b458f1611f5e984c997cb86766f29962d31a15ef7e304f3d499cfc946dd736f89ef8d37ab3daedff5e486276f	1	0	\\x000000010000000000800003ef04cfab9bd14575bf540a3fb7ebbdefe7373af8354312175e2fe589852cd612520d99c7efe0216ced953f2b7cad6dbcae98c400306d66183c285b57dd02170c89bf0798f87d6e4d47990ff6c75ab8151d0f313aa7eb5d5931b2a335ca02f47e64296f96b91ceb8cd6224dc33079b20feb1dffbe0d951b11b0970d9f6ffc259b010001	\\xcd3065fb59fce9f8af2013c623c721472e1a2e30eb5d82d2fd564769c8ce54dcfdf45713a811eeb70dd7edbcc61b60f145e365254cb90bef8abcd07abb52bf01	1666768407000000	1667373207000000	1730445207000000	1825053207000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfccbee203a96da3fd875f2ebe46a1c4389590556a4e69ccac39f63835fd371459d3374bf2663cf863d6b507d5da43caf0cf3a69f0db6b8ee2f673e9b84480828	1	0	\\x000000010000000000800003adac992cf9e68952f02993be8f9c0cfc3fba22b582033503a5a8a8c4bc80f2b36af840882ab3ebfb650925e4d53fbd8d7a4651e0c2a2616c7313f376ecd26e91c94771b6cc9c937c2e05cf095946a286ab0ab17cf8885f7ee84abd73d46552ed8fcf5cfc71d68421e06a50e649e6bd6d355cceec28c29099ee34ea9509ee5779010001	\\x33b499ec6459710ae761188db64d17879cf62410f52dc38b63bd619c341a82a2571c7c8df278fde9d48d015e1e4f03427c903e336e448b1e15feddb04bc9ac03	1642588407000000	1643193207000000	1706265207000000	1800873207000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfe276e4add494fa4c9a490cd1b8d1fc88641547dc52ff9c9c66d17cef07b836645c262f48df3f8d33e146dc9475f13719c23abfba527f103f1ffe5ff5450e333	1	0	\\x000000010000000000800003acaf8a1d540e4d0710dced5347b93e5c50e5e4b2d78fb2317f86a9cdf63b64f489c14670db3ac4661a15606c50d76e4599415bbbaa51770e91a07956a857ec71fee2dc3cefcb02b2695cf8d91a3e4dd508fa1324a4b12b562d8617f418932fb9f450760397ee9d9d4222757bc93cbf20a2836f234a625f16a9c823f428673e5b010001	\\xa747db57c0d4eec99391faa364e23bce7d005635ae51905e54dab14f5ddf185eacfacb706aa42b4ff482d0bd93f326a60d98b498447682e96372aa27cab24304	1664954907000000	1665559707000000	1728631707000000	1823239707000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	1	\\x8ff396e353930af5c419a356bac9e48feda8764c688f65fd13107b10b270f2dd16aa44a6876cfb02542834ffd6d98da9066c23ad69c1645f8388d441cffc4674	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa42c95cbe4589410d07454e975c526f62721b8d9b7e6184c027a8b9dfd522578cda79ae6d90b306b07ec4d2c50c4604b50bfcdfba507bfe2f0da9d45d84a788c	1638356927000000	1638357825000000	1638357825000000	3	98000000	\\x864b23a89d412fde2af83cf9bb078a655b52aa34299a13c7ef391ade35e1c89f	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\x2dff75327b84f774b7819d4654c9c64c96e5c6f4784c7fdcc14495156e06c7d0409e5594a7b3484b3087e23becf6be92508d6d59ebadbddd35173b947c8be70f	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	\\x00000000000000002f20da7bfc7f00004f20da7bfc7f00001020da7bfc7f00004f20da7bfc7f00000000000000000000000000000000000000cf64f701113b71
\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	2	\\xa915f2d530da9b250dee47e6375c4a95dd9f722600da4fe78b1a7c796271f9f213c2e1a8707084bb732b3e32f0e59ac16b40e5600d861af32370812c10fbb03e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa42c95cbe4589410d07454e975c526f62721b8d9b7e6184c027a8b9dfd522578cda79ae6d90b306b07ec4d2c50c4604b50bfcdfba507bfe2f0da9d45d84a788c	1638356935000000	1638357833000000	1638357833000000	6	99000000	\\x1e0c2ac6166a810df10d007612059e812beb4865acd20d14b8fb337dc4eaef00	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\xaa022ffb061f9e3c3b6f4272422b450c5872238b036b91c2b1615dc28da996babe3c263913f59a7a15ce4b102309781f4dad5a3bba86364a6742f0e1a2b7210f	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	\\x00000000000000002f20da7bfc7f00004f20da7bfc7f00001020da7bfc7f00004f20da7bfc7f00000000000000000000000000000000000000cf64f701113b71
\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	3	\\x9b46047240a728295adef55198dec4167e56abaeb0d6bd2652bf269028d617062691ade7c485292e82ed684208916cd2d657dfc6ac1ac4a5bd997d4daa9a1530	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xa42c95cbe4589410d07454e975c526f62721b8d9b7e6184c027a8b9dfd522578cda79ae6d90b306b07ec4d2c50c4604b50bfcdfba507bfe2f0da9d45d84a788c	1638356943000000	1638357840000000	1638357840000000	2	99000000	\\x4cd9aa99d5383b0d249f0c82424ea26490fa945aa7bf35a6552402c9fc635c73	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\x2adb5f3069c939c45c0c9560543f63259540c9d8e694cf7424a0c2dd1fa86cc399c196bbc86fb76ee5dc4fede7ab899cc861a6ada9fc46a600ba3cf76f542900	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	\\x00000000000000002f20da7bfc7f00004f20da7bfc7f00001020da7bfc7f00004f20da7bfc7f00000000000000000000000000000000000000cf64f701113b71
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_serial_id, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	676795002	1	4	0	1638356925000000	1638356927000000	1638357825000000	1638357825000000	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\x8ff396e353930af5c419a356bac9e48feda8764c688f65fd13107b10b270f2dd16aa44a6876cfb02542834ffd6d98da9066c23ad69c1645f8388d441cffc4674	\\x782d66d05eeb8156ace439bcea6943c212fe06aeb1a528f71b62f299a4f9afe427c225675f19087c43a82a7dcb3b3feaafbe5111bef858eb5bd7fb654b1bf70a	\\x0849796f95f39370b7eaa8c0d2fe2327	2	f	f	f	\N
2	676795002	2	7	0	1638356933000000	1638356935000000	1638357833000000	1638357833000000	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\xa915f2d530da9b250dee47e6375c4a95dd9f722600da4fe78b1a7c796271f9f213c2e1a8707084bb732b3e32f0e59ac16b40e5600d861af32370812c10fbb03e	\\xcf9283a6e88cdf5480f5b22a6c22720371f1fe575f6ff1f1477501064dc699b3b34ee0d55ffbca4f09ab51df39424897619fb4b9659de0fa0cedf5834658fb0a	\\x0849796f95f39370b7eaa8c0d2fe2327	2	f	f	f	\N
3	676795002	3	3	0	1638356940000000	1638356943000000	1638357840000000	1638357840000000	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	\\x9b46047240a728295adef55198dec4167e56abaeb0d6bd2652bf269028d617062691ade7c485292e82ed684208916cd2d657dfc6ac1ac4a5bd997d4daa9a1530	\\x393358c58a375567de85e2f496bd60553ad297c93ad96a53dca91cc8c0a7982db47dc6e41cd2de364799387e304a2a4ff3b5f6e81d2a387d55b45b90ec0c350c	\\x0849796f95f39370b7eaa8c0d2fe2327	2	f	f	f	\N
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
1	contenttypes	0001_initial	2021-12-01 12:08:28.114454+01
2	auth	0001_initial	2021-12-01 12:08:28.219049+01
3	app	0001_initial	2021-12-01 12:08:28.289405+01
4	app	0002_auto_20211103_1517	2021-12-01 12:08:28.291863+01
5	app	0003_auto_20211103_1518	2021-12-01 12:08:28.294599+01
6	app	0004_auto_20211103_1519	2021-12-01 12:08:28.29681+01
7	app	0005_auto_20211103_1519	2021-12-01 12:08:28.29883+01
8	app	0006_auto_20211103_1520	2021-12-01 12:08:28.301082+01
9	app	0007_auto_20211103_1520	2021-12-01 12:08:28.304051+01
10	contenttypes	0002_remove_content_type_name	2021-12-01 12:08:28.315131+01
11	auth	0002_alter_permission_name_max_length	2021-12-01 12:08:28.322694+01
12	auth	0003_alter_user_email_max_length	2021-12-01 12:08:28.32838+01
13	auth	0004_alter_user_username_opts	2021-12-01 12:08:28.333899+01
14	auth	0005_alter_user_last_login_null	2021-12-01 12:08:28.33956+01
15	auth	0006_require_contenttypes_0002	2021-12-01 12:08:28.34173+01
16	auth	0007_alter_validators_add_error_messages	2021-12-01 12:08:28.347167+01
17	auth	0008_alter_user_username_max_length	2021-12-01 12:08:28.35759+01
18	auth	0009_alter_user_last_name_max_length	2021-12-01 12:08:28.363555+01
19	auth	0010_alter_group_name_max_length	2021-12-01 12:08:28.370757+01
20	auth	0011_update_proxy_permissions	2021-12-01 12:08:28.378008+01
21	auth	0012_alter_user_first_name_max_length	2021-12-01 12:08:28.383754+01
22	sessions	0001_initial	2021-12-01 12:08:28.402962+01
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
1	\\x8256a7d9b2d88222b0a712440b18497a44fe0415ad273f0af8f8cbda1ddbd9c1	\\x13bcca62575c0fb2e41ca366031ae84da7fee7cbc266eeb24efc64e9d47a6a35376c4af44f5e4916ca27ff356fa3b8918a9e6ba10c54c8a66fc85cf8bb272000	1652871507000000	1660129107000000	1662548307000000
2	\\x6a7c9f52129ebc445f3ebea3eb3ca9fce6c1b89c7d755b05ae29db3909b2ee11	\\x9f5394c955b7aa653d1e8438447136f2dd6e819f182c6b8a7191c62baf4e2d0859796a55c4d8e91d4a574b02e652ff7ffd43eb8f5e053752cafc621d5b259506	1645614207000000	1652871807000000	1655291007000000
3	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	\\xa96df026c9d79a0556d6ed540e8cd4465ff397bef464c3d644f401b3f3c27f4ae4c04a21463d16f75d1275404447c02778884e4370086400c3eca5e4f6d19107	1638356907000000	1645614507000000	1648033707000000
4	\\x7cca75492be957360b96eb8bc06b45fbb395845edd482dab5e72aa84c64615a4	\\x667ac2faf237c1ec5c18013184af23aa59593f6395b949c32b8b4ae17c984c795f59afe87e4b80b9b5605f45d19deb171b0ce1630868ec808937ba277edfb000	1660128807000000	1667386407000000	1669805607000000
5	\\xff2a8f708a9c59bea4f2b4b9458682804452ed63005234c01a3cf995299e8e86	\\x65cbaa87d6229e799b3e49a5058899745bc3a224dc0a496f6c3fa5d3b6e8bb62ca7348315f29d6d14f9b77236cb26dc6017f6a8654e7e8a500c7087115857206	1667386107000000	1674643707000000	1677062907000000
\.


--
-- Data for Name: extension_details; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extension_details (extension_details_serial_id, extension_options) FROM stdin;
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, age_hash, denominations_serial, denom_sig) FROM stdin;
1	\\x864b23a89d412fde2af83cf9bb078a655b52aa34299a13c7ef391ade35e1c89f	\N	224	\\x0000000100000000b412ac0632df5a1940cc43e3e56f6c2ba2de98ab9404b0b10f87ac51b74aeeb625624138b07cb86fc0d2e6d4b827aba0909e2d096e9e46d18d57508fb4741a8f2e66b6524c80c21751e77376b6975aa9a90b8d8cfcfb0f72aca70aa77bd43fb633cc415c80555dd1a4a9fbbedd8affa6ae12dad7c0bb326719b67467315073a8
2	\\x1e0c2ac6166a810df10d007612059e812beb4865acd20d14b8fb337dc4eaef00	\N	155	\\x0000000100000000aa0ea95a18c4f52cceb7fdc0dc2233d0a0ac6cf3d92b1356037c865c49207ef8405769926999095a25a1d211803f20995dc3a1c18c29341f6cf91de63942068278007dd00b5d46101402810bb7ff23efce865301f3d1f01866c2d62c3e2b25c634a4df60ccdf2b7fe947d5c8959704eb58e5f2cefce0b1418b13af600f6767d2
3	\\x4cd9aa99d5383b0d249f0c82424ea26490fa945aa7bf35a6552402c9fc635c73	\N	158	\\x0000000100000000af79a3fc715f12fadf87207e01714aeec8e97471d49a5f98189551ba9b677c208829175e0c687e69d4a1a6e10b498f588dccf7c771b463e26d7164a48da01b4f3e76ba8b36ffbd84fff43dd5c81e59d5883def770c55eb4c7a3bf9021766f6e67358be70f7839aada93784e537baded5d1309b0de54db38e8b428a9584bae1a9
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xa42c95cbe4589410d07454e975c526f62721b8d9b7e6184c027a8b9dfd522578cda79ae6d90b306b07ec4d2c50c4604b50bfcdfba507bfe2f0da9d45d84a788c	\\x0849796f95f39370b7eaa8c0d2fe2327	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2021.335-00P4MHRW2TJJ6	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383335373832353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383335373832353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224d475039424a5a3442324131314d334d414b4d514248393659524b4a33453653505a4b31474b303246413553565a414a344e5743563957545756434750433342305a50345442324752484734504d355a535158544131585a574252444e37413556313537483330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d303050344d48525732544a4a36222c2274696d657374616d70223a7b22745f6d73223a313633383335363932353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383336303532353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252384a42413930383946335952525351445057423932435a35563156304a3142505657384a314230503856435648373143595930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223656474e474b4e383656335a445954394d383747465739564b4d4a5a52314d584e504d5044373435454250474a56333346364530222c226e6f6e6365223a223739424638314b5a5a32365144304757415a4b4a344b543852335051484632364b42594b4b463748303257504147355345325147227d	\\x8ff396e353930af5c419a356bac9e48feda8764c688f65fd13107b10b270f2dd16aa44a6876cfb02542834ffd6d98da9066c23ad69c1645f8388d441cffc4674	1638356925000000	1638360525000000	1638357825000000	t	f	taler://fulfillment-success/thx		\\x29095e9e1c56b99221b0435a57b0ff07
2	1	2021.335-G18ZR5P051Z0P	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383335373833333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383335373833333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224d475039424a5a3442324131314d334d414b4d514248393659524b4a33453653505a4b31474b303246413553565a414a344e5743563957545756434750433342305a50345442324752484734504d355a535158544131585a574252444e37413556313537483330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d4731385a5235503035315a3050222c2274696d657374616d70223a7b22745f6d73223a313633383335363933333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383336303533333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252384a42413930383946335952525351445057423932435a35563156304a3142505657384a314230503856435648373143595930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223656474e474b4e383656335a445954394d383747465739564b4d4a5a52314d584e504d5044373435454250474a56333346364530222c226e6f6e6365223a2246564d4a3336543541395136484b5a474a385752544a39484b41345947393437483554545a45504d5a30375a413932354b4d5647227d	\\xa915f2d530da9b250dee47e6375c4a95dd9f722600da4fe78b1a7c796271f9f213c2e1a8707084bb732b3e32f0e59ac16b40e5600d861af32370812c10fbb03e	1638356933000000	1638360533000000	1638357833000000	t	f	taler://fulfillment-success/thx		\\xe6700b8912c9d69c229b10c290a774a4
3	1	2021.335-03A8KA76X5258	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383335373834303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383335373834303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224d475039424a5a3442324131314d334d414b4d514248393659524b4a33453653505a4b31474b303246413553565a414a344e5743563957545756434750433342305a50345442324752484734504d355a535158544131585a574252444e37413556313537483330222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d303341384b4137365835323538222c2274696d657374616d70223a7b22745f6d73223a313633383335363934303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383336303534303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2252384a42413930383946335952525351445057423932435a35563156304a3142505657384a314230503856435648373143595930227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223656474e474b4e383656335a445954394d383747465739564b4d4a5a52314d584e504d5044373435454250474a56333346364530222c226e6f6e6365223a2230413544384e3554305358324b4257344b3346444a59485752534d47385647354a57475353423453364154354139305948313930227d	\\x9b46047240a728295adef55198dec4167e56abaeb0d6bd2652bf269028d617062691ade7c485292e82ed684208916cd2d657dfc6ac1ac4a5bd997d4daa9a1530	1638356940000000	1638360540000000	1638357840000000	t	f	taler://fulfillment-success/thx		\\xd75efc2f0d8ae3092342d1545462dabd
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
1	1	1638356927000000	\\x864b23a89d412fde2af83cf9bb078a655b52aa34299a13c7ef391ade35e1c89f	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	3	\\x2dff75327b84f774b7819d4654c9c64c96e5c6f4784c7fdcc14495156e06c7d0409e5594a7b3484b3087e23becf6be92508d6d59ebadbddd35173b947c8be70f	1
2	2	1638356935000000	\\x1e0c2ac6166a810df10d007612059e812beb4865acd20d14b8fb337dc4eaef00	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	3	\\xaa022ffb061f9e3c3b6f4272422b450c5872238b036b91c2b1615dc28da996babe3c263913f59a7a15ce4b102309781f4dad5a3bba86364a6742f0e1a2b7210f	1
3	3	1638356943000000	\\x4cd9aa99d5383b0d249f0c82424ea26490fa945aa7bf35a6552402c9fc635c73	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	3	\\x2adb5f3069c939c45c0c9560543f63259540c9d8e694cf7424a0c2dd1fa86cc399c196bbc86fb76ee5dc4fede7ab899cc861a6ada9fc46a600ba3cf76f542900	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\x8256a7d9b2d88222b0a712440b18497a44fe0415ad273f0af8f8cbda1ddbd9c1	1652871507000000	1660129107000000	1662548307000000	\\x13bcca62575c0fb2e41ca366031ae84da7fee7cbc266eeb24efc64e9d47a6a35376c4af44f5e4916ca27ff356fa3b8918a9e6ba10c54c8a66fc85cf8bb272000
2	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\x6a7c9f52129ebc445f3ebea3eb3ca9fce6c1b89c7d755b05ae29db3909b2ee11	1645614207000000	1652871807000000	1655291007000000	\\x9f5394c955b7aa653d1e8438447136f2dd6e819f182c6b8a7191c62baf4e2d0859796a55c4d8e91d4a574b02e652ff7ffd43eb8f5e053752cafc621d5b259506
3	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\x70e9063063f4dc2e3532a458ab590fa6c322362e45c3d19736b28f770d79af0c	1638356907000000	1645614507000000	1648033707000000	\\xa96df026c9d79a0556d6ed540e8cd4465ff397bef464c3d644f401b3f3c27f4ae4c04a21463d16f75d1275404447c02778884e4370086400c3eca5e4f6d19107
4	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\x7cca75492be957360b96eb8bc06b45fbb395845edd482dab5e72aa84c64615a4	1660128807000000	1667386407000000	1669805607000000	\\x667ac2faf237c1ec5c18013184af23aa59593f6395b949c32b8b4ae17c984c795f59afe87e4b80b9b5605f45d19deb171b0ce1630868ec808937ba277edfb000
5	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\xff2a8f708a9c59bea4f2b4b9458682804452ed63005234c01a3cf995299e8e86	1667386107000000	1674643707000000	1677062907000000	\\x65cbaa87d6229e799b3e49a5058899745bc3a224dc0a496f6c3fa5d3b6e8bb62ca7348315f29d6d14f9b77236cb26dc6017f6a8654e7e8a500c7087115857206
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xc224b524084bc7ec63376db8b4899f2ec3b0482bb6f8890560b236cdc4e167bc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x0d82feaa94d63ddd13346840135e4a74893bb825ac9838a99a3861024eef918e5af74401e3cddc7c8202d6f84be76f5256454d4af258d1bd9978d3a9499f1501
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
1	\\x36e1584ea836c7f6fb49a20f07f13b9d25fc069dada9669c8572ed096c63799c	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000
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
\\xb723a3a86b8a93bc6c3d1495b7160064b1b3a09e3b618cc17e9f3dc24904b976	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1638356927000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x4fa01ccab8d3a0cfbc8d27cb988dac3a272072feba6fed11c6168231fe420f5f9a487cc49ee2fda2251eb460f42c0602a729327c235e4e70e61f6ba384a0fb0d	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1638356936000000	\\x1e0c2ac6166a810df10d007612059e812beb4865acd20d14b8fb337dc4eaef00	test refund	6	0
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

COPY public.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url, payto_uri) FROM stdin;
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

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, execution_time, exchange_sig, credit_amount_val, credit_amount_frac) FROM stdin;
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

COPY public.prewire (prewire_uuid, type, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_known_coin_id, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x9a7473637436a219f834f9d5c6fea8805576f4cc9f4d2c0ba7ce4655b3c134d0491d1e4ce0ed732c3ba4e0b708165c08dd561f9c84ca44dc75e4fdd7645b2402	1	\\x6580ccaa66f5bbc327426e4a6e13c8b9f59bd9ee94b49a33ee4eb0b7a0b3f1238b01bb9fb924b83ad80f15afda29cd31b94cba06fe17f902bbe0713f62cf5001	4	0	2
2	\\x471ff0e881d4b16132adbbfdd817ccd9e0348a328bd2b94ce43bc9d0439f6c23211d1dfce1553e751cd3375261dfca9ec45abb1c46b09103abae1785db2d501c	2	\\x4c45e1529f3dc739b3fed7e06911fa0b1b0308a31c50d9923b1a87050cca7d2dd88ba280ad48279562a95102e60fd484dcd8cf2d98912925c0d4bc9954138f01	3	0	0
3	\\x1f19283b63be41e38ad6a021b9a5382fe5fd2d8c10dd3fb584e4f30bc5e91af57a7d6c79d8167b48d09cffbc6467afec06e3bf42d709eb2c061aec51001501b1	2	\\xea573d029b9ecd56715daa8b3fcb59f535fc2df9b346969b4456fe1dad9511528a1dc4989c0ef171ad9904cd89df5a2edbdbec405ccfeb9456f54538c6453105	5	98000000	2
4	\\xa2d1f43ac067bd1e9d31adfb6fd9b599dbeded3525b15701da7559fdaf0aa9d2db4adac05d9c208605b08797eca0f1281552f0c2835dcf03442758cb720a57d6	3	\\xf512f631514aadfea3ad4fcd0835a57a598dba30f78812a6eef53a783f501cf593a2c96ec2ffcc71985ab43c1bb5959aa6cd8ed149babfa7d145b7a7a302a909	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig) FROM stdin;
1	1	0	\\xf2880e36ccfdccee81c4e9d2c8662b92879979796884fefd978583a2473d64ae89a9a80e9552c87a3cb8def91df4ea4b62244620d406880864511a093e3ea00c	335	\\x22d45c9e7e88b0a9a7e4b1cbfe0e965a33c4afa675eef8b3c2a09ba7aa10b61354b69f5e2719a5dec68c199000ca2d4125bb730a5eca70c2b55cf38c1aa5664b0009dacda85b8c12563f421b27750d8e421df3f64eb0ed3857448b921422f080f9824e45327263ba5add1e1437043f7692e245f1387431dbabfe15e12d38e698	\\x119e28ddbe6ba1b3eca8b7e45b69368f6f3b99c7ee0279e9da6ae12ccd35f099daebb90df0ccf848779676952e872ca17339008882c334f6026169e517753ad1	\\x0000000100000001072e12ac1dfd9a6442ba6f74388490db3951bee0294cb905016f42b41e6dc0667d6629195c7adcf3d66b00f2f911f65c3f90874897c8696b1df9aa58f116a9897580aa533784038fdaa2ba9cc8bc30c130b98b4316050fac85532e82aef56d3369a0d464adeb2a3c09243283eefef0fa9463a216162831ad4f77138b41f5fd70
2	1	1	\\x6a84f7273824f30d522b74e8651658ea2f5dd550137df73cfad688ca0e190569085a9a1b1658f52ec6c3252e56cc45e4d11e4b08d1bb31adfcfc692466201007	256	\\x81ea9a4b889c3410d6796eaed4cdcbcc0f842432a0a5b57b2f17ed90b9678aaaedefdda08f60b88b59c20aeabc8341863c19a4b9f0cf9edda9d4115410b746350b04fb9d3a77920d2e64c55a07bd873ded9dc63b5e88bcacebbcad11e730f1b140c242367d59ef6a46f82a8703b2efb2159775547dc8655f1e6c9e8ab912bd05	\\x5dcc9e9d43e96f63bd755e1b94afe5d2244c4a629c3a0756e74939c2177119bc194930ce86b62c8f4979e01794a62d6b1e2a26dea107ebde0ee9d3690e7dd84d	\\x0000000100000001a5c9ffc713f14f44587696e327897d8c223f4b74d04ebcb735da5be562d36998030310365555aaf149d8c441c0976d250eb6fe85204799ee1f4d374eeffe1251daaad1bcc8f7e1649668c26f63309530fe7386cd115e3399f8d26b910d3972edcc88ba23ca9ca46cc891f6240d2205feb790b8dc52df43bf7f81474dbd799cf4
3	1	2	\\x39ec7d6472e4e8613b9a06a8dbbeec6db736b8444e82180d654b02e000c4c20fde1665fca526424290220a14838feec76fcc81c4dd7cf9c7538131ac4e96bd0f	368	\\x7c7a7f8af35e8361ece8de5b5646b623b405b4aa2344f4736f56af8fb4682c22b26067984c7f0a49a16d85741348fc64c995bd2ff7dbdccbfb6061e0b9ba60e2aa513aa05114de3221d9e9085f06e7c82948f2b7710c5816c980fa8d056e2cff1b85440161ff4e97e5d64d7fc49a969ed8d0c5d609ce46de1e0ed2511fba1cc1	\\xbcfac3266f012deca044930c0dba8a5a59930328add12db33f9703c509fae32f65ad0ed927bc09e2e5a6c863c852799df42a5d55639d85a2ae65654e78c9e1df	\\x0000000100000001051f998561da7ac6f09910568282a816058c51e848c5d2577a4e7aed5a7140ad1a09a798cb6848463b21ebea04369f38d2fa4083d9db78be68892d2e3f86179ed82e8e1e7284506687bfce2b53ca9937acd3fd02feded0e9bc9e3758abff8ba1522235e43f42f0df5d77f2438341c50b2bd3d782aab6cf4c48690e5c8a665ca6
4	1	3	\\x16c5b6be20259eaa35e152b45ac96999963565d34eb91c3d733a35fe821cbe1f53daeb42d9b7e704130db54b9f347af72cb96a563c6eb27f5580fec1ae32a405	368	\\x92da4d62df0f75264c92d1b0331d13b22d90548b80e7905ed1b2b9210c3331f0271acde5ed328e1ce4e94053a2e1a136fe4d7c7514264a78977e6e92cbc37f889c0fd1f11fa699e327cc02e2e5f921ea5b8f0ff3058837b06b5afba6f7c440e2aacd9c56350ec42be6494aeb3513b7f0eb9f1ed26de12c6b26272da9a7fff257	\\x808b02c34052abdc8bdc0e5b3580ce85accf78e19710222530f7cb74b716352d653e4a49ce71542738d99e06ed934796bdb63153d63b52bb22e5da790cedf1dc	\\x0000000100000001a1bf96507f97ee166194ab9a7abd1fc2faf31089b5d709843e944f81e58a1ac195e60000fb1ef9a8faca28871f6979fdd4ef62bae8eb7dcf29131f5abd9c4656bad401d0d106e0b75fb0e733212adf542c5c1da30e03a5f7c26a769bf2db8e3a57feb13431a3781a1a75a7707b7e8476871cc01a9c5e1b53fa50284af2b07ccd
5	1	4	\\x5ba35ee7cd244f217ffdbcb1d9366ae81a11ba36ccb7b55a6e68c7023174c8ed4282fe9df36e3def0480fc96eb2670df0e2824e074db2c75fd55d76696926c09	368	\\x4a652976276314eb30bdd898704d957598a3b09e711c40c07e0c1f2a4deda1de16b6c781940289904fdac0365350b684e2fa22d87bdf005cfbd7e732d919d91821367a96b203ae43380eb24d4f7ac04154eccb76c219bfed8edfd433f0962375eea3fc09614afc6d540a748c1c15985ec9126f6ec6d579d5b110481a7b1fb397	\\x1693f1bd009b716c9d4d6936e65f19cbdf79993f8171ba886af6b422d9f7af948a979fd10e8af6d3b715a6897bdf30148d07333da2481e520282c18b7ae5eece	\\x00000001000000015255d1e7193298ddb1957e7a4a835854756516691ab13f9bba1af6cb90643945fd9124f9ec70fd561b2a08c5941e923160b158acd13a8114b9f495ffd4dba0e1197cd31422958c0ef18f674b9f52a3c3d938061903cc7f9408af39fbfa0f0e4326a6d34d555901bae99b06c3ad3d6a82d7cdb3b9c07a8b1e6fc33fce9316ee32
6	1	5	\\xa889c7fbbc5875092af25a0da92cc990e8545ef09a39a36fe65c8f8184c848021bf5f83b0197c6fe306a61ff8743a2cb51e62f9129eac1248890bab654eb4c06	368	\\x0ce4b3045b5e07efa58f62d9f723d553c0387323bb02d1a249855b4802f82b4781593eaa7ece06db3e8309ea16f09fec14e471a52716463cb723097bb22b60b6be2c531333b15e2e240354b95147aa0e9dcdf37a68388b1e0ff106622066316abb18c2cf1bdb8f56b82bc1e325e3f62bac792f987005cbe9aabd29ccb45218ce	\\xd3ad734214a32762e10085646e0e198b5d7cfb981880d6677310d52fbba0948d779cd164df16e88a5a78b42f4fe7f22a5aa8748b6c066af3acf34b8089c135f7	\\x000000010000000162ddb284d57211a5ae9a92e6b3b9519bb9690985f1c42fbcb447ada3d519eeeae3245de54acdae0c25dc9695f4f128f7c3d55f217d7aeb79e16458f850738e4920ad3eaa58bb644dc0e222f3a9fc001db203a7542ab730e3b23e760e6c696838a23c7d8fa56fb1e9aaface379a91ad6976375921d0bf39b9f6d07b89044904c8
7	1	6	\\xc8cacac1621f9fdcf3b357905600c03d512be10b819292d18474594aa048d62ea6c65aac9b6119163b538633f6f62f57597267c94e574570c2b3823834e0f909	368	\\x2ca2c7e9132242a7e8996480a64f064c17dc1a6e1263793c73908187573a0f29ec633fffea16bb2d18cc58a808923aff6bc1366e368169adc68d22940aa0f0b775c682326cce3a41cfc40af52e5951ea82fead60eb70ef3f1b6c93ee83a55729b1dec3574c9e907e13b43986194319f676a2dff31e9f88539094e0ae13f40c46	\\x4d636d0cde1eafdbd9b42cfe7bafba82deb359848882bc87f755a8f8837b58ff8703e414ce8cd1cc4d45952937b289fba68bb153bec14961f6af48d8813a2540	\\x000000010000000148dd0ae4df05554ce54f1505230eddd822e7e1b12db719c4f8a510cf22a848fe222d917cdde1f045c85850f44f27a103ef2dadc8b9235bee2596e09c8e32de90bc45e77a89ad3947a39bf83d4eecacf08067d60bd9a0d41d42e9b12a7881d446452eb033ea101d94bdb6efd558047f4ca1d8e2f327c0d1e57c9a1333295256d1
8	1	7	\\x472fc2006c549046d2793e35afd5fea71a829a2574efb6878794e2507d20cad2d83c721f267a3532b03c2f8bd4ca5259be30d4c49e5f665e9efad4db3bc9fb00	368	\\x3a8b2e76358c1ddf19d59240c564724b84b5514d7169ad2c2083809f28fb7a4274a42b270f4fd18fa7ace54cd9b49716857f942a7eaa462ab64e9176fd88a7da567146d8a87c00f9c048559e4971b3a7522349981bef774a07efed7ba866b6620789757f5988732b4b88338fa367b755528c2aa1776ac5c213a4d952a515c3d0	\\x2a1f021e5261a149d96ff8a40f13a005ee5167389c7c9ccfbe105eec31363f29faf6684ad7b48457887dea4da39f35fefd40a11261eb3df842c5a13b6bc2c18e	\\x000000010000000174f8635e95b0c9be1037af54b57752bc6bd2db4ab7d235d4ede6d58b0d522adc03f39253fe80a8871c529021bf7cb8f5a88efb1f4b8d94b705665b208551ab28f5740bc6da17b62e16a325ecad52507110f1176fd35f299aea2a9cb27d91ffa5653029f05f9378cd25e2e7c68fa3fe38cbcdaa0fac68c75cdaace852b5a0a950
9	1	8	\\x67dca13b1d951a83c86ff22f0686d2bd7c5747342538757ca9942a64c1af3fbe1c6173705cdfb45bfd22de3a1dcd60425694eb2aa81364d3fc88d2d9ae9a9507	368	\\x5c56a05add63d00acaa706596284e383f7485e5ff70662043859a8b92d9c9b720c6773b3f8ed81072d963bacbd253ded39ed9cc9afe09d0409f853c007083d27f42935021a1615374f2ace7f1dfd1c7f4dad67b8813a23bebff8d0ddab0c5cbb69599d7d687172f8bd87240a1bff4d56a29b30e002f9e1e5121f19c752cedfdc	\\xe46086a38dd0ff9c9264a10cfb141bb6547a985dfea30098895888c0080f8ce8094bb3054eec8fb1a3df4544a057838c759459cd861b3a4aa1b0bf46742078c7	\\x00000001000000017815d242a4ad1b7e37589e704b1be350df2b6b12da1623aa86a4f7f17fb190695eb5864803e033e6bdac8267ebaf235f5c47009b4179b02b2261aaff27945249c30baff37bd6d0605c93daead8ac23d22815c0c3eaf9dd5c371e92816b4fb069266302db6c048cf019b309b782eb0bbbf8d2fa5680c1f658bafbdfa82abbffd6
10	1	9	\\x6a95de9e3a6a1ead84930136a18576ca7308d750d05aa5410cba3c24834d9b9715548d3ba1dcedbb35a590cdf90a50cc82845675d8e38ddc75ebe5e5e9a2e009	368	\\x9b1e2cf20b351b97688e33563e0b3a37176d06d5da232c8755356bdedf932c8d069f713bb8c71b926368782022a3902c082ee1ee459c8a3c75829bc23d1edbdec75d935806c0c6ed04fe1dd04ecc0927848036c62f5bc47cec6c2f74fea0b5e8e193ea679f7a1a792b19941066e7f2d8c410566700ba1742cbe1a39b5e248e07	\\xf1555cf64696c0719182e722d86acbeee29acaf2b468d4519bc5ef64b4d8ebf120625131844f544a9ddd7be7909b0c3991123abd738cf0f79411eeeee773ab37	\\x0000000100000001af0cb80880ed43e61dec435a917bf5b5193515c173c71b3d39b257cc6a43319f78dfd41903356f2b4134849f81358f2b65e341c0c1810c18a64a5d59c212b41bc9fc4ec108f0b0a9d80153edf5239d0eca2a58cc9fe2c4c34b07e892009a947263d53fc7aebce3f85af42a842103404f19b937850760bbfd4c8570fa375d163f
11	1	10	\\xc171f023d6da60d7ee43ff0f55093b8744d0c354bc3092d378e78ad3dec520b60781e2d5d9cb657a536dbc371226d4189b9ee50609ef4a37b51aa02911c8470a	116	\\x02e0bfc900b766f21dfd270a16fc61e2baa4c42eba54070e23d862b069b306857352e56a8427d73993bfef9b0b876a942750ed9d614e8ba2a2a9c1ea756e11bda7f2f6d13922f6a4bc3a44fe0b1707146d252a10846f1c7f00110460c717bc15e81117e4279e5a91e53103f64483bcec882ae4f4bf0d9ebefaee3ae9270746c5	\\xeec2a4de607073ad153c325a189961eb8eb62ffc88ae42861b35403408f679e3c048a954657dda3e095286f3f4c2ea6e42df2e5e1263f77a583f7c6474085129	\\x000000010000000181452f2fbea8d882d5581a1e6823b964db62719dfb8287eaa8e8fa4d8587fa495d2e22407cdb30f75c2bd52ea4f320a82d97ef9f0c7925a0242d1ca19834c3985f383a6754b4586a7e33fce12975b38add99bc1d58905929ed93aefcd2d27797e129550a0645b640958497728be3e0d30d59c03fba4da9809549c32bcae56011
12	1	11	\\x13450564c3b6a6db3913704b2cd7487f9bc7e196bf9693ca4630f64e953eb6477c9a9b13e7d37f530deb7d7ef2454f37b7ab6a513d730c2a5441321f6209c801	116	\\xb03892d1026507aacfdfb65eabb098c0275a15a41d0d46ce47eadab0f5a50d201263872fd560eb5d74d31ddb6d49dce7cd481a7cc93236d3b52059200c36cc38833958ef4895131494fdd8b8f34f03033b07c35b94b27481b9cb5b7a1cd144fed837543b10394122ea94a5f76b04b98ac8be78fc6ed19559d1e313d5ea6020d7	\\x3aff9c2c07ef0e67a4b312c598cd5734ae729a0f1d510a3d4f2d076bf18734ccb6c0982b5027d53c78dd1df8d0e6645c79bac4d7a03443bfb944c5b0a9c0d2d7	\\x00000001000000016d1fafcc1da5ef8a3f8a406be2d56dc9a1f7819c94cb17181e5daa3bda503168e624bb7ae19e8d07bf080f03557022b724256f03b50e377718a6ffa2bdba20832f1633b074a437bea53734dd2e5a8f84000a01e65b039c612669977425f2fddc743c781334cfd34c18d160a639755bedb772c9462e039b13df8f219d7a7e9944
13	2	0	\\x1e24b8b2832d32e3d1974bddc12428e9f673c47a0cd874524d481c747f970f8a808b7499db70dbdf51d234876e03d3aeefd39db47ce7ccf3cb60c3ceb2012202	335	\\x5a684737443fcec485783bd173e5c547f77a204a687cfc10bd30f7a912921fefc4180b0a77d6cbfb835025344b147e3abb33f5da76c050982916ff30dc7f74755514f4ca494e28c43a412a598433d0cee87b27780a89fe78972e885d285c613cd5b02f543df03269310024089715b8f3018e51dca84fc24d3c9c8832eac47dc1	\\x447722b5eff26598f8785d4124d53a06c5ea79881b6b15e61bcebd6057c0d6439af3a70c568d9b60e9f1d05f93faa129fff473e07a94271ce962c10ca91af50f	\\x0000000100000001c4eda265b07774d492d43842de13f60c7c3f4d6368127193e80e912de3d7cb2880d68246920d1f6dbabefdd415e9628f1f73e2be67d1f5558e46a071208cb819cec7e1cda7703a5e033b4a887a86517fe95ae869b3163f36c51b04e8b56822728981830c98a2b023f8c36a4c7b88d47880b9ae98578e347cc1805eeb0acd83c0
14	2	1	\\x72e6079e52cb0a069ac54fd9e3f122473407783a0fa0c09d6f8b38e96e804b867c1c0d839b63b17790e357f6f6f53817731bc7149a1d0d21ab9f48817498180d	368	\\x10cb6be18f3028be2c78335419329fded3f5e8f881e3568528500dcd0d5af6335d17288fb5c749e86041bfc349277f3769dd2de751baa8fa554ae977f665e5a032b97d3f4d9bacbed512c594f82b56b0036da0784e77f4b30590e029b4230c54cd3790e5ff9da16c8663a7a23f2866bca87f6e7bf9b82f68f3e81a484312dd8a	\\xf2c4a8911fb7513dfe3948522146d17db7fcac64f7139657a34b93a7cee931840804ee2dcac5695674b12db8f8b202ef1a73cecc23e5d6b8259cf5750f1214c2	\\x0000000100000001145c0add159e714da4665ec1b955460692582f6a96ab07f1afd4ec4f5695da5cefdb1643adbc236aab79b513e8ca280caa05a3970ca37377755da4bede493a6f556734193d8dede76397897aa9db5ccadd90e21a96ee5b7cdbc0035d992db3b4d9b1c45982ebda5f7afbdf593834a1680864d55e9f1354741ddd4a6aab307d2c
15	2	2	\\xa4a0f606f834a3cfcf86c4c9ada2ed756d99ecd9052c728f167706ef5a426d6004824632cc57197f46f285bd7d5cb8599969b1a2089453d2d80e9c6824c9a50e	368	\\x08c9fc60f6702d9e613be742c4e6cd842d14015e1a9c170542b7dfc5cc3ffef2770c08425ad6119191d9d7e84401e13a117d56f85f22ea15ea0dd966cce88e8a5083046a97f41c2c94d89cc56af348d1bb19410a1f5777b7277538870e34dc74cadcbdf0af034c4b5d6aa1bf01dfe22e3c6cfbc05dbc3a29aad348c0a8b03d68	\\x3816d9a5f0f942d392ce2457c8738d5d418863c7ee7b7e141458530cb2c482e260f107eb945ae6d0be19067b6a5ccff7bd855cffcec8becc0a97236d2baca602	\\x00000001000000017b110cae2180efd15749cf32aa8b1e4ba771e5f5c7caa288e128a8d7a4ae1a738b7ee11b4e69933db71a1ca7bc3db142e56ef0190fa1d32819f76a223acb35a33d7ff420b005115bafaa0c99230c7fee36829844d54caef6ba7077981a1f9b8eae44564ecfe13f5de625e401f4598e6e822176f8759fe3f0ef45be6a98e05f9a
16	2	3	\\x22d141334b2f1fda2082adfcd3d3ac9c7df4d08b9792fe8a645cdd001264bc1ada3ddb722d08a2489ea0c687d296d33ed6bd6a480aa221e3858acac94cf23602	368	\\x99d3f3b0a0388fb0eb251cb6dd6120ae975b671cf66ca8cc6bed8f0414aaf617abbb81be4d4f5541ad2df61e7a6e5a3a8d31c106a7ffdccfbff5a3e69667498d2280b665c2b45581bbb804d35e9c3aa92d2ffad2de1827e4edeb55c601133ce6ab6ddeb33780f40197f2e1b138062ab837dd9aa0a5280744422aa3a9244c05af	\\x8fe8ab0c2ec82032c1153a6b87cbaa726e983cbcb0395fd5a6e351a5db9b399617a1b91131585388dc6f8337f57677071946f3846c8ee37226620091e2e78b0b	\\x00000001000000015274737f5cd05c853476b616a6fb06f5f522e0206c2dcdfda1f749602efd3f1451c72a11b095e4aa9c4da2747a9097f654404f86753d8ac2b19e074389932283a93da0a85f5a0fa3b66bfa87e91b3039c658392b74ebaf84196cb08f7d2f39a67835d5fdf75ef4a545cad6036784e810b0f5e13d3aa1d65764457d2213ee302d
17	2	4	\\xaaf2015d137c0954e9a84e1b392b9cb16697e1a20650dfec2b4f6af001db29f41a43d7bff9755e45b3408adcc7ffc233d6d5e6525353622167fd39ffb388b80e	368	\\x6072b76bfc5be103687e1b9904aca7b9dbc69836953be86f79956f549bd538f0502bc12c0d68c1c26402233151fe53f9e890677c0dc58af8e54c3a10e24af25d64e02f6785cfedda71f5270b5c5adbecd12a3a6b2abb14888cb3845d4304b07361f59f20fa7d33557359fd5eecd904a31d19487bc638d71e6c1d55f8bc48812e	\\x07cef859cb4ea8fa9ca7a560d17786b479ff17f20494c726a8dbee55422312963f85ec70980948c3de09804fea4a659f0e9a62f4e66eef6f5d473d1013a2a43e	\\x00000001000000012fe678b29961e5eb64d12fb25bd8c4177b3a7ffbd8a9059ecf8f133850e5bddd2841a92b8aa65519d8622fd078747f2c9a16fbd2ef7a8bf3f2ae3b2a2a7af4981948fac8b3cda0e242db41b807deaa33accc482380c3c35d610243d1c6fceace01738d54193df6142b208de81db9f912b79f8b09d5a3e8d2d602f7a26850d425
18	2	5	\\x331366087f20b7ca86478be6a0a24ecb8092b06cd429e6b521119b09e1401ab95e90352182099cc56abaed51d3c0bacc377af5a5bec968115fab61872c1abb06	368	\\x3103ab13372bca29a2fd6680b7d49e9245e9310a3515c008e2cd6a4efcec0a2447fa112e56f264fc6458313d8812d80f85a1bf8441e2740628dc590011df6ef6f5ffffdf12d665e32b39b9d6fe2e21b2f98ff23ec3ee89c6b19e4f78ef8632a37bcdea490db060055fbdf4355822ce6667bf34d6f4b4ed9a3e2c3e272301433f	\\xad3533251720d002e890a0efe35d5b615043a80e83b104a492bd9be45401680f62b4c9bc6bf9cc276f857fb67a8b33c462d226b568b24696d7b8e9bd9d860d4d	\\x0000000100000001c719ae714cd99f1fed7899807f8deccba06c5632a8f74d10185942ffba9e14bbbbec89b3484d75bfade2b1d04dc0030db4ec84e29c85a32fcdfba042675bfbb6f7e54dc4e78e57b5464c7219df56806caad2b24b1b367e4bbeaab12f6c27953ab2b98064d93cbffe11b5f456bfecc68cdf5d24eeb42869233310bcfcc9f0620e
19	2	6	\\x8e4937eaa627b53d80385cc34344e490722a2274033305c0659fb4b10d6717d74e1db3ef25a90fd9421bf09034a3b2c14e95d4633742495f1b6d90cede31020e	368	\\x7c43447716eebf7bf627a4020f30114e52f18aa40d42f6acd5e3266bdcbe9152c10b2e1d79da8bd281c1b0ea2eecfaf22b4440ec740790fb09b9ce38381dc11be6fa0adb97c31edf376055f7cd0ee08ad1963d08f520549c2502cd51a390205b68da1af6e33c2ec05b3dc16e36b8f5256d30b91b42facdc78cdbac64f3dfce87	\\x91a12d728807b48bfd9fa71fe8e7a643f5c42d340e659322796dff76e96e17e1acd6e408131214cf879ca38cefaa7f951c52dfd7655c1387b876f42412d4f1f5	\\x0000000100000001512114400f55a5160627a4f996a6185b9490e10eb4862dd2877c9cce720c0473452f2425f992ce1df08ca05d0c958cc76bb3d7aab93d99de49f933c76a5b2cc4ae43e031dfc71ae18c4afe9481f701c58b9d870f92e35896d345c2014b4500e407ae9cabf811e66499196f95a1b1414c4799f024c230b5304530345c3d708ebc
20	2	7	\\x3f1ec798fc9124b722e41cbd663dd15524bb946f09ffd58bf4ea9dbe2970d94725b665d63b788e40693e09986591151094d3ef419c32d23f08f53d2e2de21704	368	\\x72b2112c7927dc31333d48a20fbd349383d6e890e1ea442823e8823868a11023b69d530ad5c67dcb9b5e30ffa9d4d9943ac9fed38edb289cb8d3e0140b140764cb15e355a1c83904066e295f2ef0d4daa32d74e46520a98e59ff63d2cbc73653e2c0fc0cf9cfe0a4a272d712833be7bc6e72e475d726317cc330b9b5cdd79d7b	\\x1ee3f357606fb436483355a09a0b89bb8b22b2b543ff28dca5e5df074c21c4db8ab6d5527eded843c1ada0a8b2a9e5347b9bfb927dbb799ded1050039e3c320f	\\x000000010000000108bbaa39c06c984f4d0b093f6f89b1801142a00756f88c5d779b73af12842389f88890b48d232a93f88d8a7bdb05bbd378c9ea802cd62542d0c588b17f6a70580474a7eb01354f3a68a1e5099f0857f4cf189c26d90bc8e363e699eab1a0c1bf655c86bcecefafafe6c7f6593f79a77a9a31ba172219b64b072d74ebe3e0311c
21	2	8	\\x41443776765d3d47cc9e68aa4543f54fe77de681ffd435527ae8e8c868e7e1bd756eeb0391479afece8f2e2c86209a5a084135bb2cb98d475236fb4ae00da503	368	\\x73c2cea698199c0f3af83cb1dc80d7b6f1ca14b040df10a71ba5afba26e0cc68455ba249d184f7e59714188869edc01d48ec386c340f51be41b74d8e7d1c3751f2f5e6cf457a7c7aede5f77fd2f9ecef7f3d900c4e5953f8aa83aad26c7a12e00405b3e1bdaa5aa185292c070ea3b20e953af3c4bb33e9078f724a6c8187056b	\\xbcd3fa1d22e830ad7f8b0bf4c1e9aed37b7f30166a508b48234dde147ec53b2404c487c5802bf98def93e44d34493d0c271536c02690b2c44ba2d4c9d8fd5599	\\x0000000100000001a070f2055f79fbb9f2dec9b181750357e4cb653ce2cb5d5e2c4ece819564607e551e064c3a8ba9947c688ebab77e54740fdbdb6d258dcfe40fc181bfe8285ca544673d84dbb4e1961fa88e7f46e2848acca8ce376cf56aa71f31b2074ce608f53a2d3960c7b265cc057b8032e2b5579c33477c91a7b8e2ea96d9e422240fa6fd
22	2	9	\\x8e7742465943390a9b8890928cdbd4d46928d5182d236c0eb557528df31c8fbdefabff0ee77d3d79bcaf518cdbac5189b11bace7d7ad3724971272a6b88f5708	116	\\x38dc7b948a8a72666bae63ea5fefc4fe11aac9d090c34b5b216b0011103b58a273fdb683a00398955486c8ba93143bb491ef176b21e2151cca2c00b22ec4272e46d63341a35c7da478b3a038e7d5a8a181ebf1251ac633e10a94de96a2e48fa6b8b4037eef640032dbf5a2cb889f9c50a97074ee109e1144250a9ff1b5ba0fde	\\xcdcdb71b1756e4d353a545983733b76fdf71b18adfbeae2e610b8bf7a869faecca9625c86ce06073beccaeaf602f5209fc70dc64f1d427fab27703f0b43be947	\\x000000010000000148a78e6a08037a53573203960724a642f339d849503d9780f69255ff4bde62c34a9e9417f9288f21bbcb5c934f869e5f7325585fc1431e1fe6bbd0da8afd0fa1746635964ddeec5caa8531ffb9711669eaacf79c6ffc0268c9bf6fe295cb7ff182569f438fa1a5a41527fe313b33e4bbb476a7f34cdeec435ce64bd3f9d466d7
23	2	10	\\x5ce15fb349895a1ed1039ec45f100bd31aac314460cffcafe987270a14fa923b59ecc1e0254ea80817bc0eebba04191c22773150175915a76054915a826a8102	116	\\xae644c109ead8f0dfdaa9f074467cbb3fc350b4db5b88c32212ddccb84ffd023043a8feb37240f5a4df39c3803dcc94c573b8e03bf31b0addcf232e48461ce5fc7e9a47117fe61da58bc74413e0645fae00c751fc9e8f8911561baa999ecb90e92190793e86aaa00044cfe6cf645457e2c1be6aa03b7d4fd3d1499fa5c65b10c	\\x9911794d0f400c6733514d23ea84677740f3f8677ae0edb7aec08562fc8c06b3503066a348465484f9b082c26895e7a90786a4e41930a469da400163590a2431	\\x00000001000000012ef4c544a4cfa86f3aa9abc145ae8ecaee409b53db4cf6fe8d13559acc0fc6907d31d19ecf3dd62fda037b2941edd47fea08397028e9714dffb5f219f0cea4b7257d1c21385856ca41891e7ba97a6407a50e4816338eb80e93b6bb98f5424531ce4cd0f907e069d6c305f4fd0fb3d44123a4482054e258a5e172f747090c303d
24	2	11	\\x0c2c23d286690a25ec3812c3512f3798f7d5eb8ef163290a2134159cfc340b1cf8b13eda7c4fd2f7177c5105f8dce99ff27872a98713706bcb25f6daa819990d	116	\\x2f44e015a8f285c87c84770e9325d53cd1a1c9fce13d1773e5d4f62cfc0185626008a580d72dc136ec0736c1f817749bfddc86d8d2c8d623b5f844918338dae1044867da3e1aa21880298f787be706a2cc4f983f2f09a63be2e2775770a9660a415a65d04df1593e6f1696e0000478834123527e39df0cad589ab3f000b7239f	\\x5c593b82a1b32ff7cbff1255be2f9d57afe176cd24c657a515d538c8ef145b42dac34b9048c67dd84d8694bdca5b554b65d7c50a6857789c47a71019c01cf29d	\\x00000001000000013176bea3ae84456d7eb267792e044160a226894c628f8e55f3841e7b85c153f61c2cead0075f8e21ac458432eb00de247429c61b7b7e16427c24c26be2c1678e998729ea2fae2c3393a3005a8976292d6c8d7564b5be34526aa7059177d561e7f612405bcc870d10cd5ae3c01c1796612fe63431329c6b89cc56f61921cdc19b
25	3	0	\\x73cda8e8d3f40b3168489655605f2544f2b696a78b5f1c70870eec9c0e4d6bdec5213b0df209fb6527f12cda0ed236f21dd28f3d7383b556fbf81d55d4512705	158	\\xa0cc856fb42b56d5cd63137cdb74da2d20d6d4d23a0c5fcf3011cf835d8fd9e16836fefb411c2c4216c6732aba55c6562902d9417a081a88a9f8a115060f1edf6ac4730c4508b496f938bee03b94214fa0278917b04d8a0bfbbda49770037a73d76b9cc3a8837552a70dc9526d0a87bfe84e5ac5ac2240d3ce16ef4790e4ad6a	\\x88c40ea454dcb235cd8020f1702249cdb4971b39d0417bd19258a0b0ab7e60da1764e01ac5f9295a1d9f3f835e0f6169679679f01d0fb98ab4fdd831da2ebd49	\\x000000010000000153345c46802e5117259acc126b20d73be4164378d52913177ddf2bb47a98b3dc72515a5b6f7f86e946635c1015cc4d7c83abbb905bf23087cf7f8d98ac917a772df348b43a91faa6b4a8886d3335ae8880b81f0bc3a23f52b5b9a068d22fd4f1db1003236fecc16af74075355419a8e43d64320e3ceeb9117b290f453172a132
26	3	1	\\xcdb3417b4663613bf81c8decc65419face9fb04a82b16f1febbc61abf6f50b1b68f62a140cf3fff7f9fc93fa99219c9e2b168f0d9f25996a573fe7b79e162601	368	\\x8eac62b94b33fb4542ca03103129b3c9b6ac1c3ad901fee2447300addd2239157f04bb06738c6a88e35ff0c2996d030503a844e050b3a724a59091a89f8b081e3d71ec988c0e52946e4ba00fa039e2aca7571d444761023bcea951bb1795521cd84773aaced5dcde9822c8a6aee20ae0ee53eaf39c65075e036f29dbc29dee3e	\\x688959a0e11e02e47cc91de511a885e4b4bbedbe14b8e456d52673802db6686150dd82e997a92e611dbd3b81396504ea799c4ced174dce862019875443c0bc6d	\\x0000000100000001348583964ede31c2348aaba0e888706a8ee4cf4eb0f5bc8c1915ee49395a01e0c1acc70062524f3fb8e982dac3374ed936bb5af2acd59c1f33aad9beecba355923fcf146d14c078ef0a2e58ac10cc7b8bd1b9d62c04ccc4e962b554aacce54058af5767a4cf52594bde80d916a9ed7cbfac745db70be220601551a9431cfd69b
27	3	2	\\xc1bedbc4ac24e402fd0b27f729cb4ac228f207f1d4b3489889ac1d7fb59fddf0c4cf40ba6795523ae07eb121c8c62fa81b2db9770fa79a9cb14250623e34e508	368	\\x56d0c0bda416cb4c1800fd1cd7d87e2be70f33b4389e8b3eb0ae9bb015ab6b759868c126cdb4d3b910eb00c8c05651dbbbcd87a896c94d17dfb6fb71ad05e0175153c145f3d3617051955e71e3b987aeaa3dcb921257f25cb3cb4706741ad366df8871b579eb5f2468941b9a51ab471acb717081d3e0f8b908d33dfdd55970a2	\\x31ba652f114aafda4b26abb723bd24c11a498935e51b5b026a6563e004c4627a00637ed14386ee51d53267896f3fb70a977b1050311bc4c8464d246c64ca3c14	\\x00000001000000018f22688533eb19c0110df5f3188a4f13ab7e1f02e5465ff1f3ac3ff1bc5b0b0637f44c88643b9b16a8eb2a9d18f8b8ac697a22c0db87494c36fd49bfe58f78d0566e7386df4fd9ccbfeed034474e2acfeeb41a96a3520475efd57d09f4cf55f106df3abb7c2e03bc2359f104681d42482e687d03a1a2bfe790add16176c16f51
28	3	3	\\x2064c5acccf2ad408c11c03d7e9a2c6b544575d20f8ae87e83adbd57ef05d99784aa66a3fb27157d93046d08c64c3f9796955a4c8f84e40faef0c75b38a5d806	368	\\x472b8b4884de004c5aff5e6fd5e97ca5f94661069544f274b559582c40dd810d7d11d6266e80b14fc0ca485b0f699844074d45a4a08608097a5b44da33b2318031c5e698f64848e8f98a76544c26d2a618f9343a03053f554661932c9eda89eacde66ba7f80c0e3e9a8f57525ced7e51a56fbadb6d06ca2567cc8d3292c599eb	\\x9e30207cd3972b7f4043db2437557c496e3db549a07dde94f7ff06d6874e7fd88f93a2d927cce6f358925e6a33dae3532800fd437c63fd63451b7db5ff8c3a4c	\\x00000001000000017a6858b98b47f929a749a693423c117076a88ba1155b12e6ec834572b6ed15adcf172cbf88ffb847c2e913b481a06d797a4ab6b5c4a5442f8c60374b5516b3429f0de1892d9c3bf13751ea10746a91384fd71701a7f2dfd60e1ff91a8683c0ef52420c3dff9a99e1dcd7fcc2a7001a8d10cafe3a62d3952483b209ef32bfe698
29	3	4	\\xc8d6dcc2aa1be1708e341525aece77e9bf06945cc2c967d64bbbd0a3641d78f706e7f2eab34beab1df31629787e459c4089e14bb2b84d8bac2f6960c0ddc5307	368	\\x9070661732864b8492c9c0f822207aa0ad3b0d88c7dc6765512d2fea23c08b67b9b432e04a2583056d25fe81c83bcece1a77c0b4045c166ba48e9259b3f56e358d9191b90a4738e2fc2fc01f6c821b39fce44e09c2b1031f9db7199db49b5f64cc630f5d34d270a509cdbeee551e893c23ff65c2a28c7ff714d0f583f60fdefc	\\x3f39164ca6c10f66c948936999de33afc7be60eaa18d71ce4f0ea573ce75dbbef5fb355ebb2ef757bda8b663ab7af625d505bfd02b91f093e5e7f782a3b3ea06	\\x00000001000000018a6e922a0db444a8bbbc0e8e2f0126b63834273a00ea67a44851773bfb01f4cc0f1508bab78d4e04d3e13c38542e4e4c168375343e85ccfe29fa9aa17a03fc05f8db5d82f03e9eebe8b88d9cf75075f7004b997abb32a5f3b999192544e5ddbd6e10f50fe7b8153b612ef9a8f4093751387969f803577814656e895414a58549
30	3	5	\\x91aea62c2619238334c3c3e6fb3f57437269cc21ee84b520e93221b22a8398b583f93566059ca7af098603230dec84be28aa20960b7a8f42c3cf42c8968a9801	368	\\x173eb10970d7ec4cdbb3881c95dd78fd9efb873646701eff0afcbcf507a584976641de9cd1a2675d1cf0b758bbb0498485bdba7ec482806aa88c92892121b4873aa660224c35533e62722af842d009f39db5605f3d452ed70db057266caf60b1b700194eb31ff5b71499b2980c0bcf175339e6305f947ea390de535b475f9e2b	\\x6695aff03ea32ae662d4f89282fe5cfdea2294c112bb22465520f6a0dca785ba384dc37c44b5e91b60e280897eea60818f3b7f50134ccedbfbd6ffde21b10234	\\x00000001000000011a10216359360fce86a5e22155fde0d223c157b240be2123e3e6e354989c4a7c33ff028e3d324ec2ad82cd720c28bde0ab1f489fd977d8e7312c05baf23482f5bc2b3511f3919ad48503e59720162f3834489c6b65fcab6655ad99c5782406d6b69ebc59aba8da53fbc18a5f568c7779521f9082e9f97ce20520621653ca44dd
31	3	6	\\x4889f17bb59ea63aba001ac219887e45f0d70813037d23c7bb1f621b447a021356a0a5274b8153f9a691203abbff421df376055a6c59c93355836826417e2c0b	368	\\x481b30a0fb216e2a031e0c308fa74b28c11e73e6768db8faddbd4c3cd99c535703407860ebafeb720157a109a9baaa50dbcd9beacdc891eb8cc74c3ff21d326de52d82341ca4e0cd72f99a16c1a12b3ce9df048c328a2002aace3a9e695e08ecfc9df910b35b66dd6c8204c77ab6ea72197f3e686f4a6675fcac69999fb31969	\\xf063eeb4027764635c6b1c9b0a45603b9b8f73ad75c770b7989bdeb5412a91c2bba926ab7c1db8b437cab94f4442a2910bf3d4e4de3ddd62e24eaf9667ac056d	\\x00000001000000012c69e4d49d1fa331bb8c1cb9f69cad2d905699968d0df6361edff2ad80e9e64fd8edcc2581f2fa844a3985e41bf3f811ffc79abdb04a307fad039fba076685e76b2b72fb43a6da14c55783956876cf5af5a9afa3dbbbaac48cab835c3d9ed1ad3ac54fcbd5aec04696c0979e5191cdd273abefd6b8b7570f7ec31a60a5f2c156
32	3	7	\\x87c66c3c5d243b06bd481fbe376e7ea289f2e06d04b2a33796f2fd6c90cd6a6fa76b9515819e922279ec092497bbe8ac1dcd818403fce79b71a75820a49af30e	368	\\x4de3240031d802a03af0aa27304bf3b1e2461e64d8563009841c029dff459836696c21ac046acf3856b5c4857cc957711541d95c92ea1cbe6bd1dd4e6a37452d68d1ccaf33f70dd68d9f0f1de766cdf8423a4f5965fbc98c992c64b5e2ece77f2d644facbbf4f0f00c66ce082ac58acd723304733bafb42ebbc967f7da456ee3	\\x0502368db7994f04bb9dd256a94091be7965d86406e682364d38746525642ba4c62a66bc7f0376ea7365c3cef018675d7804ed848f7e2dea4e556b505c4605aa	\\x000000010000000105a185181e68a198c81d6acae03d28fd37476cc74fec349e8a7faddc210b9a6b670204dd2613f8c838e5335a68cc4716086fa459f3e998b5a47fe044f10454ebc356f012d5edb832c8897dc6910f98d753e66ce6c06372c0b45ed1167565bc17f8e5976c9e1bd55249b510672182af5ee5072f419b5998a0e923dab1a177f89c
33	3	8	\\x52837899b278a47c5002bde7bc5a25835cd6f00c688774843ebe562806eeeb117abf6bb22218075b39fe1a7c2822890ffcfdd325af4e404b837dabe868c9010d	368	\\x59a31158c66ec3c048a58f5b912f69aec7634225ca70be04f9074128d2c28cd8d7cd60eb1544e5948abfee03e0ec4d1ad13a29185f0f44bb276249129ca64d4bc4b6f944a6a08c4c26dfc425a2cd4a17f2fac1c4cc1275677813fd96b53501f0de836cb5fe64ccea2802a66b3bd418cf81e1753f2bffe5f5da206b18fc4afa32	\\x75a38c08a0d37722a2ed5cc6cbc37ead03fa13608386be053f6d0b49cfe6aa3d5ac1d1d52d2b8bd4e36a2af9c760b62dcf05be1f74542d2e30bc97dbdf29408d	\\x00000001000000017ed1944eb8b503852729da97f8ed8cf510d06ebd76b9393d5c8ec641c21536fa9e95cfcb5479eda5135ff3409aaa0f125a8b978add31d934b699dcc957f8bde954b4cdd22314bd54bbec8fd106ed08472555ec49099cd0a97ac1fafe790f8f9810f4d78a451fb0cfb6428d19b3439d49cb61d47d953fb2cf4f29609375effb07
34	3	9	\\xbad9663081a83947392112907cba16391795904951c898209f5878789c994b57ee1be4be7cf2a88729f8f48b061d302e67b1e9901e330d54dab93513b37a500e	116	\\x0b6fc9ab470a820975f818c4ca95f485afa6342a33b4be4fa9a6f42ca1cdf7cc6939b296e66b95ef9ad61f3c2ebcf4adbc532aec47fc5ea1a5aede984ca946607abb481d074e3e3defaa7526b3b2b0dd57327b1f52c94c5494bb07579f355541b44795054a656b17f5f01e3411fc3de07b9b8de18891aad91aca7f92c5b88c28	\\xbea9a3f6f81fea6d664801598d8d02f1e4ac23391fd4a8b179a8e7ac078e4eb3dd0f1f7f739fecc64492a1b9e8111d39cb203bf7fde41e8323c95f67cdbd436e	\\x00000001000000016df7ff1d4868a827550dd6da36cb1f898473a8b367f31a2cc2fc12a27da52b012907e8bb0178240fbecfc7b9cff636278bce871dfea6520175afebcab0037838e1d9eba4b6390738c278dcf273e62f850d0910ee56c7ccc642b4c2c35104adeae66f376bcb8518257ea73746649f21a702181721f95883529b0e08285cbf7bfe
35	3	10	\\x46725747e590257f3a9ab75523595af7d8406135a126f3182986e66848e4667137f88033adbba406e80fe459d2062509e4a86ced93e72566ee2dd3a4b5ef1409	116	\\x1485e75249e5eaed5b92dbfe676b2891a5486f6721ef4153e02df46e94650033a66e2e556ae2d701bca013b81a93becb0c028317d9529f6f69d317ca8d59e99f73a9971ee258bbfb4cf86d204723ab9fe313e9eb868cb7ba4b62da2b502f39a0259a7a18b70d61f084bb70b23a73c96552ba3d91fad9fa1234d7eed640f4e6b0	\\xd1ea7f176080b41683cd1e850ea43c977d2c667cedbea462c48d811d555c201f6e9f4c5ac475224bf3411789a176d6a064a09c71cd7ff47b557472643bff8463	\\x000000010000000127456570c96586ca2f731d9c6cb6fbfb4bfc50a913f7fbf2f1c9b28630ebfda20ddadc73a165f3fff89bd6a4a9d8629eba91527fcb160fbce5a115514ca5fa2021689bfc116752624e1bab0b6dedf189f8be3b56a85cadd33beae9bc5376e8815c3e6f622b440112918718d83660a28619558ac5b17129ebced61e5dd5ae86e3
36	3	11	\\xd45f3711c80967b80220753cf2c0c824b36653c02885fa71a584b60dd95cc858260793e6fb02aa87c765e0bf46f216cbc25f448cb6e4adb845aa200adcc10a02	116	\\xa7c8c7280349a41e812e99505f7deb379214bceae532572a2fe3265556557a209638f88f7fa0dd71f1fa02bdfd962fefecef4c8ad6015597dd5a6f05a22a50d072ae9d7128d5cd40854c18291cbd8c4da8b6903e0ac450100d357e3195292287148e3ce9d28d3b8c2a7269d63c3cc3be9fb8f424da947d5c716d02de20e34038	\\x2b66e1c254edfd71f821a00ca6d7d367c4aae3d0969dcbb0c7ccb9af5a2b13df53c1e83011369f4a3717b64613851975f8a0c1f3c4b07b5287bbe9f378b6d613	\\x00000001000000015152cf44ada7d3474772d205d4dc0de35090feadabe2658c6e7549255d8c5543e2566027424fc45454a0e9df9767735116263832694ba34203a9a462437147e4804d82449ce76fbd041d574bbfd2598ca31212b43edf1e9f757443e9d35d5090125d4c940ab31ca0df8cea4fe0b03feb9901da414b03057cef56c54698663614
37	4	0	\\x4ad307933fc055001d3183c3225b54e2c3220a2161547248b3a82876d8fa67166d625ae8da82302431c3411e3f8681e6b72efd16fe810a0e29c933e4573cc50e	256	\\xb9ce2120c1c282e85dcc286b74c7bf9658c371752147e861700786e3b16cc7b527db9a3fa7ce265363d1e3d10eab0757f8b71daebbfb62050911375f0089ec30d4e38bcad19e98738ed00df88d264ed7cd2e72a8ad41f2bf999790f5b6b048a1e3f3e9befc2f8670fd154445dd8410c43b52ab0566e78fadc1f1059ce3f3baf3	\\x18b7c7491cdcede798cf5ea10f0b7d9c1de89bb5e4f49526787cd3351e4c9a358dcb76836530887cfdcf77c28b76f536132e567a2a41833b18ff5aec4e56ce7b	\\x0000000100000001229992831aa309a3c22fa278db27008d62792b59da694e36cfec61998f15cb472d55dae21b0716c3fff089315e4bbfd186e68744b4c8bb71acd1551c9d69ef578f42c7e326fe6d85dbebacacc6d3d28192f4f46279c7afec4ef870c7aece968b88980d058616d6aaf65bb8da36c58cc0d7086fe1398a439188a197e0e4d584b9
38	4	1	\\x54c5f2743fd6620092a0f05149009ffe426fbd94e71de3357d04a4a73e5e8b5d097531ebe17f79d0f5ff73471b45f0761715724784703b86e311e60d4c16d70f	368	\\x8057b750ef210ae4719c6da535e8ce31439a613a117518031dffc47529af491c7a8ffe645b7c5bbb35112f2ada0643dfaef8a68a211e2952f7e454d783643c6c96ecc88cbf8e8411810060f1c4218c6739a80ea32bf8754ee1b1a66f7b4d43959d78d2221bfae4ff7552ffb12a1499aee5aa412344b093ecbc30f63801a38c9e	\\xbb080fae4333cc1330bf84a29407f3b46b9e34600b0224c0fc4450f301ceb86ecd3e54477dd7b323baa1ba2747fc81c89dbb070f42083b1cb6d2eeda931469eb	\\x000000010000000143d6586a0488740784580dd173167ce73520303ea5a073dbbbb39ab15fc0401256b3e3117bfe5d002a687d8dfdb500258fec6caeaaee8f91585e008e5acdf5c050afefab8c05025dabe981a85ab6a67e78f14acb89ccdffec5c948d9bec1b399e8f480619c1f8a085a75d1289a10f2b6054c5cb8aaecd651791e54e4ec888c59
39	4	2	\\xfd40c6fd442a4292de28f32a9a75042c6797a2566befccf973fbf21c3c0f62585caa04b96449a9a6d863b29fb755d7a2cf6704bc44b4bd60f048e8742edc5705	368	\\x5663f04abcdca391d988c165beacbe7ea4db5e8013bce23b23bdad5870bdf209a80de70f169559d43b4df53572efc99c09a775a99842fd9acb0ad711bc850ca26d4b091662f171390e7e18124e8f85131de9005ff92335820c9ef60f625e45bc16a551ce1d9b4981b6f366bbdfa92ba1f6fce1bee69169d0990ddfaae6e8d6c6	\\x9786b16f65e87de608a6176f8393b9b341d66cac58331d03f2286de4bd707d220876118cfb2d2354962fb1f19e4a103dfb44f76563f1155bab3b2a83a61a89b8	\\x000000010000000130b44c8a72db21e962667ea4f98646c09ef7d9e01d8a40a70dfd971147ba21a35ebba41923fbdd44eb27e732937636b5270a3d9b096d4655d2229d23d8afdc807e52f00a2639d7b3ae6e5a7d65e0fcc160e760f9a245d324785cd2fec69fd77dcab1342cb334f46ee8d0f712be3b7a2f8f590d00d297a7b263e31c4160d7b921
40	4	3	\\x415dc60fe2bc63910d390dc02760bf7f0450e2fe1a7526e52df09afc3ec67e9307208651e0f3e71f98ff144f8383be5539c63a5dc0f63ff959d6ae692709750b	368	\\xa5c88fa9b13d9821bce30de5893423b73d184c277d02446acf85a732b4a12210759dda08a2dc2af539b991e3994865b2bc918a6b1d8022004c762f55d83b632f3752aafd4519cfcf16a7c32e614ea453957fbd92d7883484924d8de1af689d541ad9f2c825d34de003b57bca26b45e503ae9d07d66fbfce26f41f15da23b69d7	\\x207839c760683ca09dd7c9f95f05940b88c04df84d47d191da18635edb849a424e2d65e33934ce908047dea79b896505221f8989d587cae4f4f7113c94bd706c	\\x00000001000000012dac93a92a518ab172c1b9f00a8c1951bd65badaff07ddd13fb902e378a9a876e09fcc8f75e2cd800abfa0bc463a787f638d379cd52dd77209b3b93be6c253a64babd525b44fc663db2756f249c99cb4aace39c9972a8c9da90b303c3e449d4084835fc720f2f7d9b4b746115115f913010113b5a6d975bbf009f1c81380b4c1
41	4	4	\\x7c445a9e30fd488b98ea7a10ed64e464e5c4f66bcf4cac8636f0c65dbd140a89d759bea2fe54c6c6ddd19454f84f9ed6bb5951adf10c4fcf96bc2752ac1e1206	368	\\x712cccda4a9d974bdd3842ad154d999fc75ac963b5554b367da0f9da3cb6bf96f8b525e9eeb953c602a6202b3a5e61a541820703aa42fa7d6319fb79159be50a1161d470c23211cb0037a00bbda728597bbe6a44a94be901e21abe1faa341307406f138d4c1c2ddecbc8de2b770f5c4c1b40466726dc9947fbad0d54d3642d0b	\\x57a455af80669f5dc7dd12087e983424bb64e55d9bd2ad41f53845539e9d8e59c8fa34fea69091d55b3aef4ae0b3921e1f4b576d4373f4a3a25c0d72a3dd33f3	\\x0000000100000001ac5b1602977f1ab84cb34d19c1ecab89af9531920de56fefc0b650fe636e669913634842c1f4d4ff573d980ed28787fb11d5c2ff62c1391c02f5661726feb7f8321300406669c5c5defa2272e413ca5f71287ebed5b625c8dd5f94d4bcd4a0e3a8ae95789c807f4121707cb2a79ca625f07a7071cf3725ae7d3834fd2fb6ecbd
42	4	5	\\x73341c0d1541e833c933a368d13218704e259363f28487041ab467d293d3c251d70c88deb9b811f20ebe6068d9c760d40239ff9ed58620e6a48831c7ea51020b	368	\\x632670130851a27688eda0f3513c42cf548a6ee6b790c7238da4cecbe613930875393479dde805df19569b33f3b5311620941dd01fc96ae173bab2a4c458555849633c6ea73133ecdc8f655a2ffb584ba974d516bbea92579397b8fbc06b3a6d528e852ec117600ab796f6fd53c623ec52a2a786382263a74650372f116d9ee9	\\x70e6254cc347501d1e5d249b2d17bdc3aabede74895226a251d3502219c8e18cedb24a54a9b601ff5de3fa9112efc35214e1864d968b98937756ca0d1ae317d5	\\x00000001000000011eca3d5159ba9297c7a10070679fb2fbfd9e7bdfe2e3e8319564167a0c5dcd57e9b8f387499097f87c808dc3d7766337b162ed42f4b2d5fc739421f2ace3d1d4d4ce0e2e76f5c973417c9e1dd92f56147862978667315eed7109724dcdc1939c197060cb31c33cc4b6dd21b553aa03f44e5c05d8025bc00315c937a352a1700e
43	4	6	\\x4a647e759bdffa43149fbab112e70dee5f7f42270e64c217faa2bc0c10429b3e5d34c967d1f60e71a0e7971f6fdc910adcfcb6cf68564adb0824c8ca8030af03	368	\\xc8e5b06c9a3d60c936efa3d1f1757326fe5fac0ad04cbf1a9e8d499ecec9e6eb073bcd5e0b2c7a46dd477fb68d1a2d523fb898a7986e3411d4c5f72d18bb8e2e04a39ec0d5810134279badbd07646e417846714fc4306dc85b951f2b45d2787c8ab9f82de5bbadeff5a886509cf6d80d31ceef883c40c69b097539e5fffd927d	\\x0df319b51cc19742b218f869540aebb662e47c88ce17606892c3f1365292292a7e7876632fefe964f1fedeb5a88ecfd2383069952521e2742083884960185b91	\\x000000010000000124d6885cb724790600003ca90424b3233ef6966c811c618ece3f452f40163312ea8f47895e59e4a5a8595304910625c5f61cbb702ac1a9544ebe706d472b4b65eca90010024052237fe22f187d1508ca3a23e78ca01902d0281d5d7a7d6c38b8c1ffd687d23d91bf3026e84c79e8c641c9a24abd7a2d9a0498c5a90fa9c7cc00
44	4	7	\\x5b5dc2887e1df7c2ce2d9c12b18016cee0d6ee1e4d10b4c8f411e15c3d1ce5ec1ce8bfd060284fbc1015d0c591806ebbdf7e1cf40e4d9b8d9f2387e7cbac5e07	368	\\xa82d3a5310a55d77e59a74bbd625bedaf6d1594a3b4ce40b1136d0375f4e49639533b1639ec016cd6967386acc6b0ce57c65fc7aaa45adb2547ee6217178f1993ea4298553f4f0fdc32546411faa1c666fec660c72235e045c213d189323b18e00f27a44cbe8b5dcc476b4707fce58a937d1d0e49dd58c451603dbf2b6bc082f	\\xd160fad51615e4240680efdb092e8f727737b918883a18cb543147a56521260fd933fa85312fa32e570158e930674e1e56ad30e1a8d37a5a57208fd58d851fd5	\\x00000001000000013f0cceb3df7a7e5ce48fce92f0e087a2437cd2688df819b96580fea9e43b1904c85338694ef1bb0c03ad8b3a93476989c8da10e71948c7abe9b54f7e42eab82859cbefcb5a4558d95a9ceff382eff159e7200ffb4d2d21d73e7ef464c532797c3490cc551deae3a6ca626a606d1669defe25323cc251a090b3ea4ddbee5f2e70
45	4	8	\\x54a5dcfc6fc9427df4c29e29bb5db53351f57de5d44386470a7e88a6d25c1512b99ecbde1fce80d639d6aae417f91ae19d21b0e5f9b46c0af2ccdf0a12c37f0c	368	\\x27de0f254c2fdcc94723f3bfedfa21be1e9fda6a0b2b1c256f6b1e2dcd5c17fb27c33d913f377a837adc9c7446084a48fafc496dcca06c9d6f6df60df3ecf5e9d03bfce6884517257699a071dc6af59bb24bf1f91c4d65d9b18a3c1b9078d49491915abb72814de328083458a232bd0fbca5112c5adbfd6cc9248404913aba6d	\\x92c0b7d9cfed74ea115b1748c301a7226ca2f22f95783d58b49ebd4422b0161381a67bfdf4e188f7ce167b58fff419b76a93bf447e8df056fa6956af7b8bc330	\\x00000001000000018ba36c89ed7643772b945817dbcc903197eb787588708a0e482bb4a070aea093ae6ce85eaf3e9e7a0907aef2670492e29025d9fc5dd75496a4f1076807aa81ab771809a1f749b566b2a790c571d1970567f551e08e7717ef9cea78880d580b13878177f6ac163a4b66e7487fc0511bf329a3b7d7e2cfc4ce2d1c86266b353f10
46	4	9	\\xfcf71eab6d90d9970c3a5191439a7468ef52088442abf1c7e7424d048fe191de8ce7c744df2bca1796e5a08e85e60c536f7ee266f2fb8b42cb3fc92033c63b02	116	\\x22c2bd48c64e5984ccc8de64aa2dfaaacb9ff8ffc821b3a31cc3f2eccebd9f0b61dc5061ff65cadfdc5bcc7464806cfc6dde46818d2577284c2230756458d212eae4b9512cecaeeed5adeba09e63d74d87adcc42471d9a213bbc1b4ffe9f0db3a018b629986e7ca1cd79ceabd6fe00a81976900d5bc3324d2865d1b35e74087e	\\x564f6710643d6f310616ae3458b2374750e679ba625c4a89c18bcfdb629ce7059415b41e7c34b91040fc5f97e845e9975f6ecb0963622b323eef8a537a1df843	\\x00000001000000013a6bdc98da59bb8e804a5f2d85afb9ca887ddc4502671c6ca3d00fa41779daf7f361f088af0ef55c8ec5daa11d461a02c815413cd8585d034deca820492fc64352886c4afbac77fe05d850b44df4da78cf4cedc060e57a4d06d3a5f7bca1b39ba8775c7eae140cc2dc0d6dcd35c63464c48ebfc5ddd817fd9c4b9f79a5c3d660
47	4	10	\\xa3191d6aefc19052c80ff793da212dd50e5ba36196e5790639e56e94787bac78c740e0039c94ca256f2e7ef2553be06e58ce00e2871d54adb0690728ddcbc70d	116	\\xade610a4153524d17680849e9be079ec254927ada0f32f126c33deef246b0fe7d580aaa84730c195c59481dcbce94ef23065a044c38275710a8d54b275ce8b829ed0cf92909d3710ed71dd93acafe7d905ee992c1b3104ef4f9f56a186fb2320e71b23ca9daddee89dd7bae79b1d5b7f66e909677bf4ea589b9cb18f8fe79c4e	\\xf963e76f485176f2ad40e580340c62a644ed7254c4beca681901d07f78b24d86c877214a781b0acf68be867d09988f88b486bd94954b8c47d69a759dda6a72b6	\\x00000001000000011677f6f0ed66fdb0143d3337fd7231e7d4c06e6c084aa7f56dcce39c17a1d9ad2a94e8c5f2498ef81720b1313e44127e25cf15c272c366f8fd8b05f661066032614bb7c42afe425662226f11fdff6b13678341e85f8b47ab2678c0d896f3c0dc7655bb0e56da7f19290f835a458559a8cff6d8d5923103dd796db9a9af8e3b98
48	4	11	\\xadf8459054deae049c12be1d85aed596418b6742bcdcb161744bcd52be5b2f41fbe098ab3384e5ab0902a12589f9a2fea5bfad621c3b71182633ca366d135308	116	\\x19d390e61cb1c44e141f293a502b902b54b8faab793c93d700b46b360917979ffa9db71452a5ac5b5077ccb8c72165f901355a431ee9d0c48d5b82c875e183a8e0778d4e9443110a8be0a6faf7d869647e2ddd4fbc3478de0d890db98350adcb01c7f1b78ebcf54d92e9405804bf8612c1037213686d319c4c7d57c93bd02ce7	\\x1c7e0165ebc2d8998b857ef69e103ef9090d640a9d80bf0012a7acda9280c24d6fdfd0ba6b761c12bab652073b21578788a93dedc9ca968345a510cb11055d49	\\x00000001000000010e0c5761213737846f3cb7e325294db727e0c55aa1748e4d468f203f5c68856a10824c172070c61eb1d0fbc2b1f9ca4bbce0dc91e2053c2a411fbcecbd7e02ddeda8b880da581cea4e06f3107cb28a2389c67e0422afffdf0c943773984c967976f0624840ff501d134346853ef47f9dab35b05bd0b9a883006d49727817e54a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xa469a8bf92b19151212f4910b0276bb45e4b0c53d19105c7b7fc6e3609278d5b	\\xef2b081d2af6c0191bd00320594842f9f00328612cb02bccc814967263be67a0e1903934ea514eb87a62a7d794ee6c83efdfb372841b3ceefc87f4a68362b8f3
2	2	\\xa2c6e3d1b1f77ec1a7b65b2d0c64e683ac314162616d5cb3c3ed0d90617cde2e	\\x6c309237aadd40da73d53bb2cef016e71dd9f958db29db3eb5152a55e3c13dc4a703f52a7b17bfe12e8eb29c8fed9bf0b9a8c3e5e0a95a6de08613ae827e0e68
3	3	\\x5e4284a97f5a2bce08e3cc642608eaf631b4159b817a689f5f701bc145c3ca63	\\xe1d5ac953c93d658102deb1e6d9899a1b84b6d5e3f85d0b53df330dfcc9279f522256282a50193f44119eb7ca8db107de84a97e6ea60617ed5e97c934680fd86
4	4	\\xb40e94ca1b823496b3124e6efbd3756395ee75c6254286a12e430f82f694bd0f	\\xb740d841faacc3bde747769d1c018b1e3c0c1da81f7c4d0d8033fde5e402346fe7f6b1344eca87b5239712025ccdc8fa0d9f8865feecc630f5b775e8c3f7d9dc
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	2	\\xd3d7e30b2407d1065669bff040e485fde1588b0f1e77a9b7024ed39222c4c0c00a7239f461114d91ff8a6e1a819a93e15c38de518e8a74b295a0e85ebfdd680a	1	6	0
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
1	\\x4265b55ed43900b7b0f72d6c35c1530c92acaa04632ced0472d67363cba95226	0	1000000	1640776121000000	1859108925000000
2	\\x00355cdf2246de2b154c861fb2ea1ee2e25c9ca526825db13d073f1de8131562	0	1000000	1640776130000000	1859108932000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, reserve_uuid, execution_date, wtid, wire_target_serial_id, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, reserve_uuid, wire_reference, credit_val, credit_frac, wire_source_serial_id, exchange_account_section, execution_date) FROM stdin;
1	1	2	10	0	1	exchange-account-1	1638356921000000
2	2	4	18	0	3	exchange-account-1	1638356930000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x69df10b3fbae5dde7f5ba6cdf2db1288323ed99df825c54e2b00ab905eb8c71560a1478b06d466eeb09c977b5f563fff59b2159dcda8f2fad974f72c122e9533	224	\\x000000010000000141bd7c40f0b3b6990b2b8eca7133971e139b60789826d8f4d5c1f6070477d1b9202e3acedbb9afdc72b0368a64293b539b1668cf42fa45bdaff7495388d4bae79e519e594f0d20b67e9bac3f209caefab8f2baeae8af3c3f0fdd4f401fb6c6388ea5a0dfbaa821dd05faf1f9a0e93935cb4299a2d027ed42eb80f2615ce90b92	1	\\x254c5200300321296b49d32c556d2f459cdbd5276e7a65b8f63633ca4c16f8d5d82a02ef7e3b16cdd449a7677f6afe6c1a47c57fb97d07e053c2e0dfc5b08703	1638356924000000	8	5000000
2	\\xd45febfdaa13c775b9923d0c8afdf6173526aebff86b654b2578140914c81971f316497437638f96bb7a5e8aebd0c4b2f7ab07a4ebb01e5b975186897fb11ee5	256	\\x000000010000000122f6abb75300c79ca54084de5a72dd4d2aee6e24c1cdeb6cc7e5bcb9455dbf9d4cb35319bdd4493fc706e445d8111f3c5de8cc2d17c0c62b5e7348f17b36870b52fd2492e352e5a2287019f3309095da2682e6b0feee9227a6afba0d58ba85c2833dfe2d58db7aeaf7f7f305d0dca30932ec02fae7837370cc6e6226b8b06842	1	\\xa92902d2e611cba5897553a4c3f6ad0bffc67f4886ae4bd12e1513ee25c2f7cdd5bbaa814f8d4ce4f10ce10c0e3db2f697a4d3ba3f54c55af1ab0000f62f6900	1638356924000000	1	2000000
3	\\xbca25d1901d4288db08a6a90330669b34895ffc5b5ec258def040d49ba5a674f56564e593a6c7161c1ea6d052fa3a538f02cefa56be20b43034b269f7b029a0e	368	\\x0000000100000001bad811a8e6984128b0fa76cbac00d3956c654ce8e7065cd797e529570b848a7a68ad51d27f65d853a300c22e4c7c4a790afe57216d2e542a7a17ad6693c9603e989dad891cba4765c24d5f45d100b419baeeed03c1db67438b2afe203506b18c090b61cb7eac0a1ebd5e82af32e08145f58852fa63ca9995963d8006cb83a8bf	1	\\x72c1ed535fd33e91f8bbe9b70eec93f8a58cb0f64604346842bb57331f7700286d59e0577ed66fae37ada79df35d631750a193b396e4996e091587c1a28aca0e	1638356924000000	0	11000000
4	\\x1d3c1382ef4be136aeea371531ef3609933a59628a96b5aab5898551d7e90e150bf430dbef6547f34b6fe9c43cc8613f36765f08ada3eda2e42a2e32e796ed5e	368	\\x000000010000000162b76b36b691741450089999b7b1d26f4a1f824282e86628537ac60e99ac5a929660399f67758b10bbb17e35fec22bb68b482a4193795409d4406348fbf621e457f1d830a51b00373db9ebe72b7450cf1340e2ab87cb82c745972cf48083f84bbb0f8b980b613b5aa7b1824dd9d5b2b1ff970574f6201a891059c29ad37330ee	1	\\x6772024dee19ed9af82cafc9b27c76508891c599e76e73e04c1235c9731346d31838d6db8cef1d3dca49ffe7b142d4e7f6e65ec13d516a76e79965038eb79d09	1638356924000000	0	11000000
5	\\x695af2745ec91d7dce905b48bb9b3a39a85309b2663b122c1f51f3b9c7a3f4a1ac44037aa417de8dad2cccfdc2d56dfb84d365ab4e298a77c2a3db6ee2adf7d7	368	\\x0000000100000001be4e6d48d8b07b290e9a6c268c4047ff333b3cb17b93777a96f2c56d862b79fc5552e6156b6ab519a5ff8fd575b34d142b26599cc50a48893b12b5fcd2e9e20e764b2318705c0d224bc93896609e9f28755ff5f6ec7e6156eaf8a240dda9a945b904626b115137ce4b8719f61f87031eba863e5063162747c96e4113b15429e1	1	\\xb18b9f3c3933ce569713e5a81748aff4c7abc549b61f010e9ff11dae3e1413961072914d8bfc3972dacbd8d95ce0d69b2207acca7a5816abcc861171067abf06	1638356925000000	0	11000000
6	\\x9836b9cda16d9825b583ab42c1b5e57292d4b7af7221e6a6536c23b9cdcb5f3fa6e33896c1e2ece49c94c46d3192d6e0ff3d73f5969be49ad736f06106fd2fed	368	\\x00000001000000018afee3ec560103cc124a0dd95cb5916a7a5d93eb465f4b037dae01484a1a17d271fa0887c3eb53f536e2cf8fb41a7493184c0b76fc879788a3785a75ab2d80a23b93de65cffabfb4c3cd1506c927e807feaef147c73c473e27385030dca02daedeccdbb55f74718d944e3933b2bcb482f1f3afb6f4348ac6c2d4f4655c18a25f	1	\\x20f843c20b3262a86d0cc509acf19f2aa2e3f7937b6e82dded8bf7fe847b46a3a9ff2bc03a30a548afe16a342a0e68506adfa7b93bdacfded6226637423f150f	1638356925000000	0	11000000
7	\\x2e90fd1ce7c0e3207eb966614c3936a76fe14e316ab8763acef90d9ba07f3a9ec3bd8bc0b1b2de3bf5aae6df4d524fee53ae6ac526378f354671b353ca4b52c1	368	\\x0000000100000001a247a5ee312d83347d8376960bb7da929047e5f21f4655a8b2bc78adeb7f13c39b3feb5a7471201fc4d65f69e7433f1a84bf0e15e68a0f83d8a2523e05bebd1083726b57529caff847c4d8529ad01ad23772c195b20321f0363ebe50a1850225fc3756713c50ec4d3ced127ffe5205d139688605afe54f675d3e40f7c247a8c1	1	\\xe33b771581d61cac9d3164f4ddca8d51839795fd1fc43b60bab8be1e1a71b95fcc913979216b720f139b884a9ff98be236c8533bf3665c32f0a92ccc7320a505	1638356925000000	0	11000000
8	\\x1827265513aa2f495b86bede0d5096d192b19f2e4a3da4dc78e563acb9f7967af6ca898122fc50acad89c81f1a204b72bf0d24519108a7af3416688215189a7b	368	\\x00000001000000010d08ea73b961d6224aff86bb9cc9626603bd28726e501eaabb61830c38d5a89060770535bbaf0eaead6c57d0d51b3f394e508a68de2c87e6782dff23b60e509284c308593eefc485eb9eb7dc8785490b9f4330d03a8817edc620ca53d6b8e5ea26f15ef4652b7bd1aea6e3c9d193347f45f6bedf3ee17670da0d8c1bbed892f9	1	\\x5caff38c0a0e6edd87be5c36d8805fb49b4c553db045846d56d76457ffae7c8920099eb5c8ed917d0eac191ec0b69b44369e138f007c9d923c7e765150632d06	1638356925000000	0	11000000
9	\\x2e5d03bf792e4da8484d4e777d7fd991d085258658f4db4d090ccd7723d78ddc7fe56c051b3fb01b8494917d8af1c48476c913ea57acedf06903c81c1b777eaf	368	\\x0000000100000001af0e02649bcb0211e4ebba008c934ef967254027e6e8f7e4bed956b8c255785e341623164d2353161643e5b1d1db39ebdb848fafd5d02f5d52106d0512fc17b5014eef2bf836795a52660a227e0e0be439234058be34db1e7495a49370426140efae8eb95dfe00164d8c1469bcfe1c883ed3244024a43d38df94fef45ae5c306	1	\\x37ece730f90ce3ba43d56f72b21d9d9bed62a4c0603b91fcb590fd90dd60c493d48a8a5cfbbd7895c4eba731fdc5e1c93f3b44ee5f06c858d7c9eee89da02e08	1638356925000000	0	11000000
10	\\xf653bccd0da11484bbf0d69e6156f6750939ac9c1d89f74f802eba3d3dd15e70454afbd35c256309cd9f7673328badbe8e6b530bf5c18b3153a18166d5d0a920	368	\\x00000001000000012ce7291e13b9a8639b5eca99d88877b162fbece208a2f0455668a0b05c1c011645c513039a93fa1551a597a92495125fcefc1de1a8ee3ca459806cfb35170d3ab07cbf518ca103f5dcb679cdc5ebbbcf35043dd5c082a955590b7c3c5e939fe9b5f8896e3bede2f98a30cbcde5f30c95d9cc66888fb59f01aee287c433c8f7dc	1	\\xcf690774a85640d314c6bd3d323cbba84a2d15cb2ea144eb2301bc73815546a2bf63521bb347bee40777d1b03896cafaa6369057f1fa26d72a3828d529b0e902	1638356925000000	0	11000000
11	\\xfb055395da086d702b40e674e38e959ec6bce7476fc62c766662e6761b9132c67d94072dbf4404ec024ac99159b4c93bfc6291c1369849ebb966f9de570c16b8	116	\\x00000001000000016f1bdedde7d94692b2e7c13c14545489f178d263f9212ec5a5b90562dcb3111dbb8098137de41d5f561efcb5c6c22b7f9fb00eb1f24bcca7239d1082c91a22e1c76fb46e5d978e30d2221b895cef0a11332d6aec85a5bfab31ad1fae6b9ee31a6ce548c1e19cdc732e9081db0c6e967430ee462f40cd8e5b4ff3b5875dfe1cb5	1	\\x130f0b68807f8d686ab4be776ed8ea81380bc384b25e96b2d9e62faf0a8615261364634c7c201c0229cc8f07c153a416036bdcbe523902c327d15118aa330d0e	1638356925000000	0	2000000
12	\\x7239cff5a5d475359aa8965d8cfd24dbbf4b1c8cbd717082d39c21d377abacfb2debca43224d683ad5da9ab1fb3a027812b74138455d8ce54a554f2684ca43c8	116	\\x000000010000000173ce053f4ae96dcecf0a63f0eb4451a836e1044d583b5e582e0a1cf63ba2dd3381c77a8d5d12a086595876586e211042e32f6e63a520b03df59cf93f38f80e3a1afbed2d53dc08c5ba8939211af384489c64cf2d4c5c8a648227653048fc297be1c9c005c72c33d666594a26f1f75cd7e81c2135e3a13fe1bccf8e6a7512bdc9	1	\\xda606ff1500f20ef95f32bf0395d8b2799c5e13f5baf43d6f6ad89ab8a28215883164d6f9f2b3dc1ab8c099074291b006b681a67705b88160cee18f6d0e0e60c	1638356925000000	0	2000000
13	\\x219a5bb73a115ef8502f20d6017ea7d6cee5d07344612f4f5b7007e3bd17e7e53d19e1b49efcad245dc2693cb5fd92aa5e1bd844a560e62f340eba57a2457219	155	\\x0000000100000001290e9b8671699f02df36e458cd29633193bc52a5b00f8b2263b1975ae03828c347a5761280d200bdf52f5bb58e9c5f82c1c39e6e43f52cee5673e5be0f7fabee6ffec0d13e5962487573809fbcdd8c5f521b7b9bdc30ab39cf2627b128a1a1b1adfbe596cf7a9d63dc5040cd97bb84f5176df3438ebf37aa27c8649050d9fc88	2	\\xbc7ecc7e1faa3270f6974991b8425b11ab09038617736ca6d153f5abc37745fc5e24c5bef0308bfe43c6ee95aa9e640b074d0124a3311ad009f299a5e30ff701	1638356932000000	10	1000000
14	\\x63886e618dee31bc7d16b587f05509fa392370ef21936644e33b003f01bfd8289e4944216a304acdd45fbc042ba6a261dbcf7e3c8cb9f50b9e9e3cc1d18bfe8b	158	\\x000000010000000107e643225430e51656297b8e37727574e3080852576dd4e35c7c599470261a7b5e83d22b9b4b2508a6dfa69d9e975cf52839caf6e053e33bf050a9ee88273ffcf7d339ca4b3ed247456c52e9462c06c61f919bc97b4727a7be99b2ad36f617383c75d9b4794d2d44632db26788ee9267ab0b5d65513525b133ece29bcf804671	2	\\x791c46fa51d9c4c9c0f0b59102ba77c09cf2fc766e4b32c3cd0767368e9547d27a0c7efd294f5c775f7422e816bf1155a878c7b8c6a56269a0ad48070ff94e01	1638356932000000	5	1000000
15	\\x986dec0e0deae1716acb9102d689886db5cb578391c447ad4acc126d98b3392576b477dd5079d2da81497bef6cda2e878922be10eb011ac771d101112383917c	335	\\x00000001000000013a5b5a1568ea43575837257ad546ac74e31d0e1b7ef9faab4919a36f06feac8d837c64c14449e882d8911090aa31bbf50eacada615595622e7c63dceac8001c539a7f42d0666be8dfdcfad39fda7b362cdab15b7fa18ef79aff7e56a6075eccbe2901aaff23a5a5ec9e21968854a95ad5ced84358770723c7aa6f2c718782e69	2	\\xee1f3a17f8fd9ac66e58efc4ce688b70306e5acfa7c7b4937d1b8693cd11feba2019d1ab82c7c900f3e9c49a1a22bd0da3f0103cea26decf18f181b65e365f0a	1638356932000000	2	3000000
16	\\x0d2e8967a73606b2fd7ff685a5b99c23b2eea6c91377f558565af8699c80acb635be64fcdcc783920669d932339492c0a6249520118b2c5927bdd4d388e7a391	368	\\x00000001000000017f1287445bce80685ed4aa5bdf8ecc7591a1322c31438557666d81e3ae714ec59159525c574671f11f4648da66b60bc1457c48ecda546f5b1b71f203add5afdcc22dfd94ad42fac38494a812c6232ef9a62ca22c4c81e91faf408860c6df1869a5efc3ec289550c5623cf31570f92ea5ecf0dd958f7f3d9ab477ff479f35b1e0	2	\\x566c21fb9948f8f58cb5f0598f1777a8d215ad376083c8d347d2bafa78b8283694072785e6045eb38bc378fd9b29e6720a5581a50f8f4a634e5e2eb76b15fd08	1638356932000000	0	11000000
17	\\x107759c8b45649dd746a7fe138ffad96b747839cc4f5ea05722308ed29e04ae84f4d0e51b7e2cb14db50405b0dd8e04036e691b32ed3e0f68ad2d00d5e5c62ff	368	\\x000000010000000102acb2c0148a5bf07fa8bccb90020369c5527e586be4daff458d641db4e9930a5fd5dc7cd9ee6ebf92c79d119e3a6ece48a95443d2edd83c3517305c5edd1d930623c6986412ac8be0352bceac279dcd4266f0928cabece3c2c0b71d0b60c5fe7334dd08749cad2e5653ddf3150e08ed2d7b0dfbc27ee6f0867bd5d68ec6ae93	2	\\x5df83d2faf76305436f2333069fa58591461c1f7db3df37e93b178af4e14f36162560b18311369b5a2ee028aae6d06aa6a9a9bb00e0149df08854a31c8fbfe00	1638356932000000	0	11000000
18	\\x2d83f40f65782dd39926f3bbd1bd41c0cb8b12d52891d0dec23f0e27d040c8f01ec41d1a0ee06175067729b6f51c5af8b8176853c2ad764049cd7cb617409261	368	\\x0000000100000001afb81b4ddff1ca98136ca2d9f26876d8ee52479cf93b5d1bbe3cad6e48796265f356ac3796248205eea75940f8e2cc2e2acd7457c62f69d7427379abf7bb0d6d05efa85fe85dcdde0fdce44acbf7e91162e37459688de1380a40d8110dccccbf167dc5b1104dca8d346c62656295fb8c2c9e7edf0e4c9c5949feb3e66e82b2d0	2	\\xb31b5dd6ad9eba54798a09c5f489fac61fd66619ff3bbfb18a6299664de13c40994aff016b062886026314d9c6aee3e51b5baf7125893513e90f3b97d39b5a0f	1638356932000000	0	11000000
19	\\x5f3f70f3bc10fa0d39e3a258f469b23625dbc149b1fed3af5090a79ff019ae738a4c1d38165639233b691c5ffdc8c6c3d0ed84951afa284ea223488db0eee4a7	368	\\x0000000100000001027fa9b1e80384500a7cd7d7f5e411b6ac525484192ea1c7ffc5967688d6f855b88e474af767a40e9ea6e7707130afbcb8a049a96934bd27f5308152154b5db09330b84dd4dc792a67fe5a6c8d32f18537870870e4290857f543810a9738d4b434fb33470c751faff39a9f6840ead346e3b8bc47d1c5c2552acb341218203f22	2	\\xfa205e85ee345ab75697fd77516b6c57b52ac21561a9efc1b2e971b9e163449cb21defd4b12c217794452a2c5f7d8378f40e3ff660fd536246d3e4caec914509	1638356932000000	0	11000000
20	\\xee4d1453919b60c92c099958241c723b307afedd489dffff5df8f552d55e3a453120a1bb8d29866eb58cfe8423518b6fc5fe9ec014cb129e2068616f21d76977	368	\\x00000001000000010536dbc54fb685c2418758646016e8fded0d9ea120cdeee0e10b8c86f274c703412d863cf57a3408cf148cd6aa6b1bfade7e4f54757064e965a7dd5c8f262b880d91d3629046d15ef8bb4c1c75d2e3b48e82a7d1f221659bf262e58c41be54cf877b069a473a27e12798af714240df39aa044ad2dc6c41b053f86e183c42227d	2	\\x695b908bfc3d33ab51a55ea747fef4e4a013226372229d77b37ac69d68cb234d9a809c642a270fe5db5ad44bc8efced322a8dbbc45df49c093130b5542d8ca06	1638356932000000	0	11000000
21	\\xb98181f7621d3cab43d42832d8812bd41fe209dd0a5d6da958a2a912beec1415dd65602f10940d0649c3a82dca6597923375f35122281fbd3c74ec3e6c19da7d	368	\\x00000001000000013a39925af579fb22ace80950827fc72bd1e3b3003da2e848ea6d0fe6532daada78ec320d57ab90d207b4e12834582f6a869c636276f2581f9924c95abde58980cca8a8c5668be8a6020ca8aa5f7e155574209de499d8b6d179458db3a5c5b410f4f24728507e798883d2e7c5ff740e3dc095951cc18e5e46bcc62eb5bff771fc	2	\\x13d916a5bca336b55b4fd0e13f6cc408b0242dba23f6974c814678c4bec7d5d61070599720d1405dca6abb9899f7faf9e2d02fb2e14c47f215a55d2f039f1407	1638356932000000	0	11000000
22	\\xc68ed999367719d3eda40c4d544e7e23451982e093f40bdeca2f6cafac47a3dc2688c5a29833ae8971fc31aa988d2216c6e35ebc97acde086adceba63c5b7512	368	\\x00000001000000011ee10deea8a22bcd428d7e1688d35d70caffa2c84918f335541eba8d2b7a3be33aa8517ada86ba9c2e35cf0ed6b06a091e2b9f07afb9c40844b21f25a2d90e9de9c9cb29ca82f7eb8e843a4a8352b7939332a8a9ddf232ab34c4da013f7e392e7ee8d78989b146c7c74b81470ca1166ec0dd2aac32548fb7130024514de41cbb	2	\\xb722918f5050b9d82fa21aee8406bb0f209ad55f1d1eb3023f7e59eec5d6027a099fd58345c501c1b823ae6eb71b8f9c7ff50882c9d313c42239093b8d8d4a03	1638356932000000	0	11000000
23	\\x34cef93565c9e898b3397322b2650812b27d5224fb04332c88cc62f1ef8f13540d314986c3916ae722f301c2eb13391c06ab8356439fc2976bb003c441555292	368	\\x0000000100000001914c931b2cfc059bffd4c5d1f966b2c9baf3d812c30234c030e98e582715de7f297e7ad3d6b266d6d7b68a8b9c55459ce4eb59b8b10c6b3fc139177d23722e0a3abd4d37cd17d726996b20e651166f786a41775aa496fdba41a9c054984196996034b4a7a50318c16644240f2cff642d60f7d589208c619e15bb6b2cde6bd2af	2	\\x219678ca84967a3dd67e297a354c02f32aebf99b785336f8319ee4e52fa8e65259cc38c1c4afb1f1bdcf0546a67afd0b1d9b7f5d5ea62a6316ed1844bc91c909	1638356932000000	0	11000000
24	\\x3a7908cb58efaf39ecd45e74fc73b0aa5b32a16462859876b46d111e92a04aaeba38baf5924ceb3601cc147801ef805b031460c0dac510215c409adf9fef065f	116	\\x00000001000000011dd701e9efb125c39da2ccb5186f416f37f32cf82cd70dd8a021fc1ca92f1e936884455df8d7033800759fb2d3ee680995bb8069dafc4f882dbab6fddf8caca4962e83a4e5b4184f03c7985e9e9eb7f9c1e0bcbf3011ec2e4d32b15123e76c2cdff1e20a3e1b72ee97c6d9cf7b8cd72504241713c0b2fbe9dbbdf6654619ce1d	2	\\x5dca4c16463ed30071096d5238540b4ffaf13aa9004eea6339d0b9a3b57461863130ef8d220172cc519e9c9f58776b39a089a35b6cbda36cfd089c3a8b9a8906	1638356932000000	0	2000000
25	\\x37f65fbcf93b376cd5a68644f9e4ad632d1acd73c0bdb0008f95ca28756291a9d83e571c798a69534976c1b5c3d7afd8c57716d5acc433595cad63e9d48d4f45	116	\\x00000001000000014b35f5faaf4581ca37f401031ac151e6f7b6b8957125703f161fcda10c02c524b539fcdeb476e207058223c29244c09cadac5a73cd0bf82ce8d5320ed4ef9221b9cb5a3c220b46675693d9f332f4ce8bd09693be3db8b2cd20afec0d6b34fc6615202cede3099742c1bf0f1a00fb35ba2831a0cb2602429f03f9f5f5ecd74cd7	2	\\xbc73f16cac7dd63e68cc055c61c85ced9a09b3fe3d2ba6657fcbd037d3b54ae13dce20edede80897d6696e8926db8bf8b58a374d093a78ad2496c40265ab410a	1638356932000000	0	2000000
26	\\xed5536533cae2500503b66ec52f5b018d5d2e46a261ec6f16ecb64b463171f64396814518b0f1751210689e2cc37793feac66d9b4bbdcebf5bd6e9b6425a1ac4	116	\\x00000001000000018d70325dcf083247d3854fa81b57a1b8bd96bc1e1edaefc5965d01f74c82d2f97117083e557f68eeb01d7f65318dd6cca5bd11e0073229bfb0b8abc99cf4f70944ba6236f3c7a614f6ace9ed9089ea18227bf36b62df21da0b864157aa659048232f6e6906bffb5fbc3a21a5b632d936fae7f1b14e0bc4fa5da65756ab67a540	2	\\xf06b49047026e1f97fcea97eb2c19555e0323991621a79b8932a666251083405c0e57d1159bfd17c8c48543b9c8a9dbac15b6e1e3d75102e5523861697f76b03	1638356932000000	0	2000000
\.


--
-- Data for Name: revolving_work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.revolving_work_shards (shard_serial_id, last_attempt, start_row, end_row, active, job_name) FROM stdin;
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
payto://x-taler-bank/localhost/Exchange	\\x0943be92e9d54af5ea96c415b17d5884a429de4c8891bbf908e857023d67a3820b8a5cad2886ddf62710ff84e8b695b45644d51d80403120ac2f3f36b836950b	t	1638356914000000
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

COPY public.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x0d82feaa94d63ddd13346840135e4a74893bb825ac9838a99a3861024eef918e5af74401e3cddc7c8202d6f84be76f5256454d4af258d1bd9978d3a9499f1501
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target_serial_id, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_targets (wire_target_serial_id, h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\xbd616f2bb42e5615ef0271a80598b6522cfe417d62b39989331491ad0d17af19044a61ed4a28a3b6eecbdfbcb1be10809f24d4978fda96710c4471e499a665ea	payto://x-taler-bank/localhost/testuser-7tgipbkp	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660cb3a8ffd7e9e69c646815045edc179e5e7ea1ecd9584550d202ae951ebd572e98	payto://x-taler-bank/localhost/43	f	\N
3	\\x95fb0cf57b815365bf0ac184db2737810b48d77984df203211df809b8dcbf1ba740d183c7c147cb0f258cfaa2eab507f8f817829704d22a1875ef93a43ad0fe4	payto://x-taler-bank/localhost/testuser-db6y8s2c	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1638356907957128	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 13, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.django_migrations_id_seq', 22, true);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.extension_details_extension_details_serial_id_seq', 1, false);


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
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_kyc_kyc_serial_id_seq', 1, true);


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
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.revolving_work_shards_shard_serial_id_seq', 1, false);


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
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 3, true);


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_shards_shard_serial_id_seq', 1, true);


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
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denominations_serial);


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
-- Name: deposits deposits_known_coin_id_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_known_coin_id_merchant_pub_h_contract_terms_key UNIQUE (known_coin_id, merchant_pub, h_contract_terms);


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
-- Name: extension_details extension_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details
    ADD CONSTRAINT extension_details_pkey PRIMARY KEY (extension_details_serial_id);


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
-- Name: merchant_accounts merchant_accounts_h_wire_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_h_wire_key UNIQUE (h_wire);


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
-- Name: merchant_kyc merchant_kyc_kyc_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_kyc_serial_id_key UNIQUE (kyc_serial_id);


--
-- Name: merchant_kyc merchant_kyc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_pkey PRIMARY KEY (account_serial, exchange_url);


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
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_account_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_account_serial_key UNIQUE (wtid, exchange_url, account_serial);


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
-- Name: recoup_refresh recoup_refresh_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_rrc_serial_key UNIQUE (rrc_serial);


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
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


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
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_uuid, wire_reference);


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
-- Name: revolving_work_shards revolving_work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: revolving_work_shards revolving_work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


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
-- Name: wire_targets wire_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (h_payto);


--
-- Name: wire_targets wire_targets_wire_target_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets
    ADD CONSTRAINT wire_targets_wire_target_serial_id_key UNIQUE (wire_target_serial_id);


--
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


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

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (known_coin_id, merchant_pub, h_contract_terms);


--
-- Name: INDEX deposits_coin_pub_merchant_contract_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_coin_pub_merchant_contract_index IS 'for deposits_get_ready';


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (shard, done, extension_blocked, tiny, wire_deadline);


--
-- Name: deposits_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching_index ON public.deposits USING btree (merchant_pub, wire_target_serial_id, done, extension_blocked, refund_deadline);


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

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denominations_serial);


--
-- Name: known_coins_by_hashed_coin_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_hashed_coin_pub ON public.known_coins USING hash (coin_pub);


--
-- Name: known_coins_by_hashed_rc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_hashed_rc ON public.refresh_commitments USING hash (rc);


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
-- Name: recoup_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_h_blind_ev ON public.recoup USING btree (reserve_out_serial_id);


--
-- Name: recoup_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_for_by_reserve ON public.recoup USING btree (known_coin_id, reserve_out_serial_id);


--
-- Name: recoup_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_h_blind_ev ON public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_for_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_for_by_reserve ON public.recoup_refresh USING btree (known_coin_id, rrc_serial);


--
-- Name: refresh_commitments_old_coin_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_old_coin_id_index ON public.refresh_commitments USING btree (old_known_coin_id);


--
-- Name: refresh_revealed_coins_denominations_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_denominations_index ON public.refresh_revealed_coins USING btree (denominations_serial);


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (melt_serial_id, transfer_pub);


--
-- Name: INDEX refresh_transfer_keys_coin_tpub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.refresh_transfer_keys_coin_tpub IS 'for get_link (unsure if this helps or hurts for performance as there should be very few transfer public keys per rc, but at least in theory this helps the ORDER BY clause)';


--
-- Name: reserves_close_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_uuid ON public.reserves_close USING btree (reserve_uuid);


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

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denominations_serial, h_blind_ev);


--
-- Name: reserves_out_reserve_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_reserve_uuid_index ON public.reserves_out USING btree (reserve_uuid);


--
-- Name: INDEX reserves_out_reserve_uuid_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_out_reserve_uuid_index IS 'for get_reserves_out';


--
-- Name: revolving_work_shards_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX revolving_work_shards_index ON public.revolving_work_shards USING btree (job_name, active, last_attempt);


--
-- Name: wire_fee_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_gc_index ON public.wire_fee USING btree (end_date);


--
-- Name: work_shards_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_index ON public.work_shards USING btree (job_name, completed, last_attempt);


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
-- Name: deposits deposits_extension_details_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_extension_details_serial_id_fkey FOREIGN KEY (extension_details_serial_id) REFERENCES public.extension_details(extension_details_serial_id);


--
-- Name: deposits deposits_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id) ON DELETE CASCADE;


--
-- Name: deposits deposits_wire_target_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_wire_target_serial_id_fkey FOREIGN KEY (wire_target_serial_id) REFERENCES public.wire_targets(wire_target_serial_id);


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
-- Name: merchant_kyc merchant_kyc_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


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
    ADD CONSTRAINT recoup_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id);


--
-- Name: recoup_refresh recoup_refresh_known_coin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_refresh_known_coin_id_fkey FOREIGN KEY (known_coin_id) REFERENCES public.known_coins(known_coin_id);


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
-- Name: refresh_revealed_coins refresh_revealed_coins_melt_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_melt_serial_id_fkey FOREIGN KEY (melt_serial_id) REFERENCES public.refresh_commitments(melt_serial_id) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_melt_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_melt_serial_id_fkey FOREIGN KEY (melt_serial_id) REFERENCES public.refresh_commitments(melt_serial_id) ON DELETE CASCADE;


--
-- Name: refunds refunds_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_wire_target_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_wire_target_serial_id_fkey FOREIGN KEY (wire_target_serial_id) REFERENCES public.wire_targets(wire_target_serial_id);


--
-- Name: reserves_in reserves_in_reserve_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_uuid_fkey FOREIGN KEY (reserve_uuid) REFERENCES public.reserves(reserve_uuid) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_wire_source_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_wire_source_serial_id_fkey FOREIGN KEY (wire_source_serial_id) REFERENCES public.wire_targets(wire_target_serial_id);


--
-- Name: reserves_out reserves_out_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial);


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
-- Name: wire_out wire_out_wire_target_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wire_target_serial_id_fkey FOREIGN KEY (wire_target_serial_id) REFERENCES public.wire_targets(wire_target_serial_id);


--
-- PostgreSQL database dump complete
--

