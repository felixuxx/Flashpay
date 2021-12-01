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
exchange-0001	2021-12-01 14:55:39.517187+01	dold	{}	{}
merchant-0001	2021-12-01 14:55:40.300946+01	dold	{}	{}
merchant-0002	2021-12-01 14:55:40.787261+01	dold	{}	{}
merchant-0003	2021-12-01 14:55:40.809705+01	dold	{}	{}
auditor-0001	2021-12-01 14:55:40.859325+01	dold	{}	{}
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
t	1	-TESTKUDOS:100	1
f	12	+TESTKUDOS:92	12
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2021-12-01 14:55:51.004131+01	f	baf59f77-f9a5-4bd4-aa67-3f91cff15fb8	12	1
2	TESTKUDOS:8	JKWQ51N493CNDSCS0KVXZVTNFE6XDS3WFQ095XMVR4VRS1ZCFZJ0	2021-12-01 14:55:55.047101+01	f	f7fd8a6a-ec64-4d40-ac5a-2444c33211b2	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3d015ae3-e8cf-4029-b564-379d3d2fa616	TESTKUDOS:8	t	t	f	JKWQ51N493CNDSCS0KVXZVTNFE6XDS3WFQ095XMVR4VRS1ZCFZJ0	2	12
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
1	1	45	\\xf066a31fc812d18c7614205f5ddcfdb3ece1018d9432f5e818290c163a2051e735e53bdf757eab36c4122334583acb2a37690d35b7fe85144a4859eab3dbda0d
2	1	269	\\x530aa936d055e56c6830cd6eb9f1fe48f5628693baf4e50337d7cc6ac760b9f657a9f478490a7587f6dff604efaf62c3480ce2aae88368a105b37e79f33fa801
3	1	329	\\x4ce84fa7805310a60839f31bc2f347026f43415c85400ab95289b9dab53f9cd728c24f3a23c8b9ac8aa8bd2bb6414f96d7372c36e46c6f581445c9ec0e697407
4	1	334	\\x3c82622e870205ff004ce0572bd065568e93e131e0c50ac9bc8e5edb4a5a51b7c58c587ab059876e76f6ad358254aeeab64e0ebb90df60352d9e0d42b2285a07
5	1	376	\\x73eb54bd69c0f711c0569d650c6a51e5270fde1b4eeb48575ec85de59a7ed9bffbd31a61e0b54361b6f3566995763ed8ba01df0dec0f4cd46fb45e23b7e02906
6	1	60	\\xe6d8fa46eecebb00771292bad3aca1263c70e19b61715a60f8f795f9830d8988bae04b09c9fde9b64bc3aa77410d73a37aa607c2bb056f98258c5b789573a70b
7	1	122	\\xe5a627ba3d18279760019e06bc6ae7dae37eda5fa119dd748fb29e9e00ec6c36ce234e6cec79c15c841b4e759c03f0895528e738b2bfc0dc29bc35b1ad63ff0a
8	1	318	\\x327ec0a036cd3af79c76ec72914c439c4cb3d1cad467cde15b4c0e588725b90c46c670cb39bc6978b5c6b8d835533101bbe37900c341d091319db1593d41fb00
9	1	309	\\xfb97a4469cf8d6587c58d4221bf3457d36d1f10662940d6dce23ea6e22b6c5c986df8f9736e82a5a79ee9dbbdc631642dc1d2cc2121e1e0051b4d1ff39d19f07
10	1	96	\\x5d7669aa9dfd18c7bc11972343391d540e20fed09ba346856e3c2a9a34072a06fd41c34c9a863b4a2d238851bbd7b23f24bf6f12a7663e5cd3a519708b669100
11	1	281	\\x7376e463abc76c75c065c70f5804610aeaf7aa18168f7b9973806ee833e3bf605a8d20527f1d009a2b019c79aa431fe35045e924903c241cc2d9e3716142cf0b
12	1	37	\\xe925f348bd493a9bf94affe27226eb99a768f6b35ad4349c65d875a4c8cb26b71ee04d2df86a66ba46d072056fba8d9547c3a77689f722f0902927a6fb7d8809
13	1	164	\\xa00177126fca70c345c13b2daefea194e1670cec95a726de125daada01a73390011d4b4164cee5a8a243f47955ea961229c792a36ef4a477cd875cf714645b03
14	1	109	\\xd862eb80353a50e2d19c6e5b402b515567466afaf3645273c197c6c7a00b2fe10d79a14939e5206652bd7867779602aa7a6cf75d3880d2039f9562573f124d09
15	1	383	\\x8833eacfbdf16cda92e25b533356cbaca942d708164ed4ff0faa4bacc66e45f9e31b075a0bcac265dfaaf6f0b489e88de085018961b62518bcbcee1920e0990e
16	1	114	\\x6dde51e6ed450a677b2b50a8e06c6f8363f8cc76dd1adcb6f5c05470e31eb1f3400e7268115a896e74d750b42ad105c96b64566a89fb75ebed16d129063aca03
17	1	338	\\x891fc5f799f459db848c7db7efd85273914534225bc35086a38c5fcd9a3e73b817c4eda33acda2651b1a4b89dea0acc66ac2d59dfdee884b9e0e0f89723ba20e
18	1	35	\\xcc78793012aa737b4e5bb370a6be8be27147b4c7681aaf1bef8cde491abe235a538ce17ec7fb8d9fac43711811abe1dab8954e31fba27f13a04ece157325a609
19	1	44	\\x12642b17ed7b86c96679ebe8dae3afe4acff7be670808e222e7854218b984ece43d859305cea4814f58ae57b49eeef80c8ac9221d17063128af6cec0006e4402
20	1	181	\\xca4eb28d8871034b23d6e8cf1a0c69e5445cefeee688e2cf39af944ecacae369a4c4b58b77d18c21053ff76c28ffa49d41c6a289861bee4cc10882c6181f740a
21	1	391	\\x83881c68a3335bea3e0c26a6561b253a42815f33d3ca458429fe48d295cc0e9ffdd891d0ecaca37c8fe7ef5b0bbceedaaee7621c86765abcb49abc38eb753a05
22	1	282	\\x2843dee1c4630540d80a651c9e040a0b2cb89e568bcbf491b9a4b5a772d8a6b1b6dc885579ab186a5301ae316ac3751fd195cf6e26d98aac811258892e1aa302
23	1	343	\\xab579eaa72346e954f54ff93217210ccf50b6ec4dcd4989d3705767bb58b8a743ae16c06d3cbd99a28812c4632a538468c53aa1fad94c9dd153fe7ddb797230f
24	1	214	\\xeef7c4cb9952eb0c634c56f86fcc802607d6b019d231aebbb97ed2656d263453cd09a5f52938b3e2c6b0054b86a65312c1070a4858f9609a602b270378c4e009
25	1	235	\\xf46bfb3e2a1bf36ca5338a51e5f1e82b23fb52a31915b205a39a83964d1160cd37078aefd9d6de6e7c37a603d7b9ffdbccb9571f2fc28ea7f9330c4d390dad00
26	1	371	\\x2c306c759df50d92be76bd79d885b32ceadd5513eb8da5504afe7b5f59f7fedb766b98ce7e20f5f32c39b35768ddf37cde9943e4dfacd28a93713196492ee10b
27	1	397	\\x1b4b5ada16c28dd83d1904245b815e4908eb5d91ebeb36dbe159f99dc7645bce01301e8c62ace3ccad1160fff9849721832406d966d247f0e873c57d9a5ce60b
28	1	265	\\x54a487a3f03e1fdd708bb59f16eb4a9e09c8fe4bb1913efbcaa7668dcd5c5a99d9a7d4b4f0d91543c840615b34fb8bc4d1cd4f82b5b8330d7c9b2a3662039101
29	1	150	\\x2e77f5e90f40f8bc6e746edc943a85a8da4e1080918f4e0a982f9f37aff226ec8c90b1fed7c8d104e30b15e6b1336fded49d740864c2a6f723e955ec8dd2d404
30	1	132	\\x175c59d3f78333c83d8f04218957d9aa9418bd7f170be0a69d167f123ae4a9dde958c5d6217c1f347982185a2814c06febe450f15ae78c0d408e143db65b0200
31	1	243	\\x7f3853e4db5a7cfeff8bfc560e1be35b228292f85edd24524c5dfd993eaa53e5bb8d0a657b21daaaeffb2ef9bc925ca35d3043cee8103f764d44acc925d1b007
32	1	420	\\x3e3d555d364df4b018340f45442b042c03716be64ede327ecc2613416b0f8410c919d18c80db1df558df7daa456384e8b9fa8f2dbe6b8bf0803fba8acc421d0f
33	1	332	\\xcb8fd60421267d2f69bfc01f45fd3ebb9af81fbb58620bf1b9e827444dd404e401ffdaecae3f342f8eaf4fa500b1812cdc65676b8f462420558c2911ceedaf03
34	1	307	\\x35676bec9d7bfb2538325eca201d1111894699a7ff463cf57bffb93f7ccb1b9598bcbe43fb8818edb1ab23b986ed605eff4204d2b2ba70f2103bb3ca6bc0480a
35	1	59	\\x7eb99d9717703c723575503214eb06dc2bcc7c6c0ba9571e5b2fea7befd3e8f522bc3f980935efae06b62949de481e046080d673b46668de0450e1e1cd1e190d
36	1	219	\\x18bc4c67627119f490607f792190a40fc36c942c9b39ac8b75b80f12419c0e8c25a154b252e1ebbdbb32cea68082bcd283e65739928e2c98481975687edf5a09
37	1	97	\\x403590dd70e42c358786250c8cf527e07631e22f3e0cbeb1bde9f6926c48abcc493f1398f9008652bed443f0c0b59f49289a4a78d44c37a534d267642ba04609
38	1	313	\\x43453d33ddab50014f2cb1cbe43338bf14b3708d7f9ee00000a7c7836a5122f1ccd39810b560a23444e0cea2f3462feda3c43dc87ed45d0a9dfcbc9d8495c108
39	1	153	\\x3fea177201b9e4ecc88c3b826b9177c3cbe927a99e6245e66be02a35fd939bf414e6a2f4e3272ed6f46faaf1ea37ae676551e2e32174c2d20f367291de7c4f01
40	1	239	\\x99ccae69a2f7d37002c7cb6c5c8130dbdedf7047adb1bfc6d870e15ac9cec6b26f7242277f1474125cbaa23885333343a7060daae97002c39b49a66877e2e904
41	1	87	\\x67af508936ea877ff72a94f89a87555552c2484a1c5441f2fe6087294fcecf3ed7fc30d1a205d6f168047afc50cddf78d4d949c20771ee943b6c15155327040b
42	1	88	\\x608b943bc7aa5d47febc59f09c97c7dd47438264df9a85cc4f836d29a9481657f87f33af8bd6665f1fa43ce96b63d2116d95b9db90f3bd3bfddf10aac1d3ec04
43	1	196	\\x3b325f213b85b7a81b65f2f8ccb0d37e32d3772e26c80c75f9e01774d7029a6f619dcd8eeadb192a7ccfc17dab9d606f973253c1d58eda807cfc39c6fd353006
44	1	149	\\xa4c5622b4a50982a17fd83673c9c1bca788fcc4a2ea6b937379a0ef43515f3c84c52397132478acb50a9855a5d2cb454ee029864a5934468a125ebdabff7a609
45	1	105	\\xfd545011650eca22e015087a6c1f926455b8b557dd5a1b3a613d6eb67871306c1ae67434258f1758ec878b19e6757c5818fd3171d17ddcbdf038db94293aa700
46	1	29	\\xcdd1bc200800f7fb9ef763f9ac7066c0ebc8f73e7cdf3e7fe235c6e4ad8e299eb2ad95c82f0b1b8081caedd912cabcd90893c79149eb49d89057f242f7699d0c
47	1	48	\\xca35480525a6a09dcb53fca97dfce9629c4fffda043af95f0790a9e1eb849c7bed00fc95448ac7209482793c5bd0ba911ffb81f28be0296b0e7325f1cfe1930f
48	1	302	\\xc14fdc0e21efcb01855364e5bcb9d9a5200d99f09542abd6d1a299180de91f36748593929a6bbb0578cd0ebc273907e3059a19ae2806f12b1e1ab10cca27ec0a
49	1	274	\\x4326e43c8a78aa6923d59b756664cad18757aaac5b66226b2ac8d4a26ad457672260565695474f1dc3bebbc10a8dfb6e99235f3400193b6cf9a359b759a23b0e
50	1	366	\\x517105569264794498727fcca9d4cc11532c0dcc5553f53e8acd42b3aed5ac1e80d8d56a4c8be4df97f4f3c2f99767eb7fc52dc0209873d7c540282534ce9a00
51	1	285	\\x3e91e9bd02cd66d67a9f29a3702bdb9699ab5cba4ed1bf30cbed030f2afac63cdde03aa5e9f80f4ecc19eb533624ae87f01b5877fbc8f556a7814617c49fb80a
52	1	404	\\xb47eb6310f3f9be129aa3d34df83d01eeef889eb12a9eb70e3cd44d64a26c92e7c102245cf661bf279145094c3ef1f58fe9f3b38dbd591c27b7f4a34c9bfc40a
53	1	179	\\xb3f176f2a9801995b30e13f27971f3276df09c3342e8c351e7c8cce730c7e0046adda6736a70944b832f96e79d9f708c799781f8fab1076989fb75d24c1b9006
54	1	220	\\xd510ea952c95ca3d21355fc6e78f0cfde9e58843283a2df920dd3ad855e4babfc23819b1ca29a7b60426787b53ec50619542f8318268fe4a8f058fdbc6c44509
55	1	244	\\xea9779aeb86dbdfd05dc31feb9ee9aaea308ed920222a21b50e04aba5e847b007fb958b32767a51f2fa47ddd233afc1b917258f7de16f2568a41c73c3a013d05
56	1	423	\\x3ea01ec72989c545fab3fac1273071e74ab569ccff6575e88603daadd8d545ecc9899af8c7d913584c7d5f4706be4b0d04deaacc1aef75b23a6821b59bd6a602
57	1	1	\\x0db501c41e7cdab21cb0088c8eb4577e194eb940d8631416ee128f50853ff153a2c79609449956c68b896ec2523e578348104b561a29e52b686196dc6526c806
58	1	102	\\x6ab1990473bd222b103793e2efa55e850045b5763a1df4bbf25f0ee8d04366fdd219433a7ac10a878bfd9ab3fc713262425cce2c3698720d9c7feccf7037710c
59	1	28	\\x2c3311cbea6cc092cfd25920722ac3d27b1ba5d640e1fe3744acc6a70fedbda125157d46e1cf024b55ff856489dd278367fa9ba287b1c7605352abbbc2004f0c
60	1	280	\\xc2451402f9f6b2c37acc498d34328c9e0aff105b29248fc76ed2bbef394e2b0838463b7880321ad7c2e69aeaef1b815c26a397664a190fb79cb20b9690598009
61	1	192	\\xabc7ff4acbf9cbfd730a567aa9405e25a2ca87e27c27f046dfb134b8cc5760eb39daf2fbde408b088d72ef05f1cc77bd0a2da0f26638cc6bee054fe7fcb11b05
62	1	89	\\x4babc00a63e09489f387ad09cb92c7b8d581689ce4bda24781a6e4a23bc2880fab70d92c3aaa8c9b74a655fc8b895772e035c69e1d6910ec0bba1075ddf4610b
63	1	77	\\x72498cd449a2181a1649da651f65db2fd5165634b5ec2535242654973c229bbc68d831fa3e15589a671c40aa8799800243aa4b681fe6fc84e4da318af2a97900
64	1	299	\\xdf08b80d9aaccfdbcc72ce4fc63b61ed8983119a4fa986de5355542100638d28d52ee0e67ebaddd6b2a684dc0bb8b95dd1434c597990267317844ddd60866c0a
65	1	336	\\x790ddf5275db415c207234b6d9a1aaf02d60881853dc74f4c4e401e0ea633d1e31274b4b69880e7d588bac481e22d980a25f60b479aeff17a8680f4983ea7709
66	1	306	\\xeac95a28751ddb9eed1d2afcee9b14100fe0455052a6f126770d158d11409728c2cd76c9457860dc9154957223413d037410a0f7d1d6a902e0fd0653405e3303
67	1	387	\\x8b5d81cc753286bc49da234f697f9d71ec3a77720cd674af17c1253c58d082818d7781a21ac4090d0aa6a5a5d176a3658afdb5f3f5c18640c85faa219f5a0609
68	1	76	\\xaaf8b7dda662fb18a8f8adf95e11860a3ee6daa59724f9925e2830a49647a7e27c0f24bdd87a075a158167480b73ee1d3f38a29da3708fbc77bd60646f363b05
69	1	312	\\x8616492b3cedbcb1ae45a7df030f26e1b4a67c27d8b1fe6d02336e79ea6a4e90cfba06b7bc291a3b3633e0416882b88695db0b159cc6b3e7b79f4e5ceaeb700c
70	1	193	\\x520dd618661b16928fb77292a1fdf4a29419cb52701b46b456383e6e5a1ef02764a18a716e0ecd96b7f7920ed8f788e30b3b32777cf04ba201c52b92b78b030d
71	1	290	\\xf13c00fc58ae5580dcc9c79672fc10797485411d0b14106c1c3b80f056a1baf4c223e6a75a9d83af4b0bd722ef950f4a53352fd38a3b1fb2c7f74fc2286d110f
72	1	9	\\x6a51a94cf396fa16e9d1a9df9c46732044032fe53b6531c75a611b35c94851a5402b6c20c93a8ae5d2fe775893e5c937bd74cb87abc5a398cf379c5e867ec601
73	1	4	\\x996e87697bbe95aea1d8ea28fd42af4f4831dc8a39fa5a0dd7a606ad29930d21a12be294df631e6723570f402ab7cda6c7a79f39c6b3b1eb6edb449566dffb05
74	1	394	\\xd9172718dcf4a95fa62ba8a2b5d06922367df38bd3ad8f1de23c703040a594ba524fb2cc8a76d835f0e478630061909a870a968d9fa5f353df5104b28187d10a
75	1	184	\\xb018eca93e18fcf891cbdfbf2a6429b2c8ec5c673d1b9745feec9801c6fa7428fb69e22b5d2b252955c2dd1ddb79ca42f677be53c7ce87d07319aa8d101b3209
76	1	325	\\x2719d634128a97c2e10985848242150e3b3f5a8fccfd08198baa0789e97d588afdf475bd0955eaf9328b67c5a08693a8e5de32e905426c3cb2401c743ff8a604
77	1	6	\\x2e4ab6606795e0572b7de96d23852106e77c95497f6c904579709d216432ceeb20a9cb4d6c4f90b420675789579bdd77034891aaf43e78d60bc98f57bf49300c
78	1	100	\\xfe393a417fd2d39a9bfcafc9a1f623f7607e5628496211fe1b3bcecc7911601bf67d639dcccd10ec893f5e0ea889ccbeb84eceffa15bd645b2bee1abe5dd580b
79	1	273	\\xe1b27ad2cc88796db3a728fcec74cf27e5254192aa7a1a124e5f60cd281ac1a83379d4e1b75be41b3d877b8506e1bc622ed1e77a88bd4e7e298e74aeb24b4301
80	1	148	\\x7d45ef90a0a91f78653173f60f9d739a1184a1a4bab22899ef36424e59098a016b8f0bee11beb49a92fb87885b4951fe43eec819a145d1e760f20eadc0dace05
81	1	66	\\x39bfd6c711ffef73da70e37e43981c0cd31ab4fed4331d205a2b5332311c689d397b8d695ebde451941136c1980edd03717e97af35886bc9830426418791000a
82	1	195	\\x493ec3d7552ead71678455784cb0be433b70dac7ef13811c0f63461dc1b00e17140dd0c93cc3dee5d106d651fa7b7d8fb6b32bb2462dcfba28656960c18e9c0d
83	1	365	\\x4cf4f357b124ea37fae9f00819d7c5ea1d3bc2dcc34605925331db737de0dd43b1f9be12f5c6b3e62e2f94df4e48d4164b3da22ef5e325013a12ef3e5af04906
84	1	46	\\x075ae32527616ce8ded51d7a0e941a40050b29fd7c6bf78f8f45cb3b9eedaae44394080dfdebf1f216953dfda27222c2965676db0d1dad57252dbb80b1d3f00b
85	1	95	\\x2485a2c906216c0172caab0146120ab0a972f8f6c1e2e6769e3863da9afaf2b5bfbf2b5ebcc40d26491e9adb96d9df6c694850f887fb47b13348467bfbaead0f
86	1	293	\\x03b64cbfba2038bd6a46a0afa7e0d2533bc933d1a9cce9e832c3d07a957d02400aac26104434be708d6747d0e010e4dea02a7d71177761cc995996cec8a0870c
87	1	399	\\x40903f40696f0eecf86f2126638c5601e2ae8dca6204857404c7bc9a049d84ed91be78341a725cb46929071b79ceef6fc7cd15f407afeec09201426d4766c605
88	1	144	\\xd09be4e83b6b44e4bc8ee7b4f42320e50947e9c632f5ddde51d692a16f80273020c5b2da9d709ae8c27997e9e0730c06e42c74f7dc293978f895cb6797273d02
89	1	422	\\xe0ab50485b841e2a9428ecabf1f0102bb743f0c0bc2db237aabea8790578fe3fc4afd260cb381a3c129f403d7ac95d6056c2357cb001266e11ad592d790f720c
90	1	252	\\xbbf0d2aabbafb4957ce077aac132e2c397ef1ab11d68bc2e7f040e9601930d70db001b922af0c2a517d81812b5a902fc006ce4b113947051c2f1c81fd9c18d0d
91	1	10	\\x8ad066ae073fd9d8d5c907761585f1717be2363ec63b3a8bc9308c9c3d3de0da5c0e7f0faa3d6b67138142cac3109520cc000723bdcd096c914425befba0a60c
92	1	233	\\xaae4ff8673938b7674037dd5adbca3c0ebd97828ef46fb220b206704813ecb8a6d5420f0b03b457c9a221b8a8402f27dd1208bc1854c3dd3e7e1075aad8e6c0e
93	1	416	\\xe5c0a094bf68c14561f8e8c943d64baa8d5de733921d32d1db11b31cd3f66143daf10b578d3cbed0e6f5122cafca2b3ed493c0adfca1c8ae28b5f1d8fa73eb09
94	1	221	\\x350d367520bfa454d4c16123143042671aaab1c9f068b96fd61a85dad2531c8a59788e324e719db33feeb7d127ad770f2caa7e7a4bd4a37a38dfa7c9c2ccbe02
95	1	328	\\x1050b650ea8a9d081af69846f8de3ffc417679c88de4d89deb63751be2159ce51e479f248a7d648316e1092dfaa7dba6a86383da2d65626cb7646d20b1483d0e
96	1	226	\\x69a0132f5ddc3ed3caf538d2c36e291a48801e1885a34b274591766842a506af8f5758bac0aa2b68a1c04acef4be11cef271ba821fe14017cbb984f2e848a401
97	1	183	\\xc7beff8cb5b10217b031991c906282bdfe8819c52ebafde863e884d2ddd7d47f7b6bd3d736dd8772083e0faf0c42ecb2726475f0ab0587eb8b209a5cec0d6608
98	1	266	\\xf7a243e9adc1f585c94b4c1ee28dada561d15490691805a5d082ddd9358718bf607662925d832bb1dc679ff31622636d911ccc8cf5fda21a13223ffd4b8ca909
99	1	351	\\xca5f13496c412327e516ed193515e904ef723f5e2a4737cb53a238358b502d33c208cf029d398b949e61985603c95af993097f9c28c9635c51ebec73ac75380f
100	1	372	\\xc97a89db4a28b312be82795352ae27cf9f02d52bc6131d500702e49877b477634056deebdf10107f6027559c2037efb6e47dc9d1c56cd24bd3596adef6deb502
101	1	65	\\xf88fbd438982873feb097246d6eb9daad1a4f38a46a39c744c44551560d27b17e40a9392eb20286349c1f373c0865ffe1a5b68bad1d7949dd9003a136157d80c
102	1	79	\\xcedbf7be48c8f581e813a9ef24e1a7fb6ad1cf20aa481ed7d2e6a6c127edd51929a6ef03d71e3ee6fd64691079ea2aae1ccf58ef9fa214d9fafc01f3fa9b530f
103	1	14	\\xf43fc80b131b1cdfe7fcd42a9d5fa4699e1bc7fba1b7bc86d3c5b21da92e6d644fdc5b678245300f9aa815fecb04cf34f80ee9bc77bee0d08b6c91656ea4df0e
104	1	254	\\xeeca2db53cf74ac5af3345c3aa0e0c31e6acee862a0d034e9fba681177ee53a8f01416cb8a47152f0a4c09f696882da8674db39c23e0392943d0c04dc2bbfc0e
105	1	216	\\x77e14ab3688491c1bd4f1f09b07bca72b36c8716212f8fcfc86383d4fd652c89f2e09e9d55e07fd7cefdab390d945aa1e036553c855bce13f6653fb2c9ed040b
106	1	127	\\x0ddb2d365cabc9b04297abed9a53d32ae5df95ff79d48fb16d28d4ea2907738416a9d2cf4e555e0e8a26b2a790b55be51f94aba53d908035ffb3193a934f3a0d
107	1	38	\\x148e17d81fd268d6751ff297bc273ac70d446ceabb8b086f8fa011ae88d2dd82ed18eacb3121911d1bbc817a2035393276d8f02b302c1a008dfbe5f1d4bea702
108	1	154	\\x6c7e4ed839190b8d7b44732468ca3958b77842ebfbac5857816609654d3eda0090983cdb7ba22cf6d9810b0b84a0b96f0b283b9cb393df796852d939b7cb4306
109	1	176	\\x65b1940f05e41e34d6b6dc96639effc7b3d80ff2568a366265c4aa388b0a2450b5b95d912e692beb4128334c6dcb563dc4a5086e41e883a3f93946b3e7bcaf01
110	1	51	\\x2b17fd72e010be8889605082e6fef0d86442e0d9a7fc751fa1b623083e72b5eba978bbce9e44ed20a9ffad65a7ecd8c37b9cf0e6cca6c3168a5dde8745fe8705
111	1	256	\\x0ea56d16b86c9f72ec6c26d61246f5adef858b50639b4b99d52d2af12f2b02782447666b11ac6edd2dbebac81ec6c77cbf8e06c623d4d4a7e32a871ecc65fd0e
112	1	91	\\x80ef1f05e07cbf16dd8787529869ec0d55ef59458694b797234298eb16676f5fde78715ff8107371c3e07a314fff71c3643289fde883caa82fa78813caea6107
113	1	337	\\x8ac287fdd5e1014374617781a8b1c01f3dac0d9711433221217fe8bc1ec7e788a2c058b6dbd26b516e9af56df0826e62c30d47da3f0de45c68cb4d02ef753c09
114	1	99	\\xc3a4d4262d64234fdc9ceda2330422abd9789861444ed907de06740c2672f5828f103707802aa3c6e2320405831ac56acf134761b1e3176ebf7dc02ee4fe8a0c
115	1	180	\\x46d2449355ad7725abcdd0232b6acfb6da23a8fdee8007d467148e8edad769277d4c94953eae37508f8bc88aa538acd956de6a2aba17d29f217cd1468c615e0e
116	1	23	\\x413cc4547dc6289cd7928018672d6d9422a45087b90b8cf1ecdfc1c02b39cdc956bb7583224aefb67bc9bf8795e652e3b396f94613856c5c023e7ba659cb1309
117	1	47	\\xd0efc4a87ec64bd4b4ffe7c29a6eb2fed49097b11681234923120919661bdd96f7bc3efed1092acb3b9bbb784b9cc0101c2a17ec5d85faa4105d6a4facdd9f09
118	1	231	\\x33caa132187aa4610866002d67a0b7091694e42092c7e92af306e8ff97af17c01d95dbda8526ebbacda51cdaa1829890239f008d6363733b84b9bbc297697f0d
119	1	136	\\x0e79fa17a996c234d8a603a2b8b0fbfca80d6c99e147a16397db77a48947fc0851f73c7303a546bad28c02b74e4d94da53a34865e8fff2ed4b0b93a422373504
120	1	22	\\xd54b9e577cd509985d0ba1de069e878aa62bd5edcc9f08e8528e91b66250da20febd3f01f06ef57af6d621a62063b09fb6a918600a3883ec57580f1d204a7f03
121	1	238	\\x269148d4b16999f28097ee6d385320fd12eea8a778a010678567107d8cd766750bb8f206fb94a242be2d5c16cc62267dee990205afe6bb1acd58512e862fc402
122	1	146	\\x78e600f343bb9edaca806d13757c907dca2a542afe764e48874b550c4991e71e03a667243a00dcdc9a29abe47395efb2cd9b84214d92ae0f5604b1b0ba997e04
123	1	409	\\xbf0d0e60cb05e3ffe0da7212803f31b64e3227e856ae09c1be13a1e576bb92a673f55bb97d089dc075605f00d7808ccd523a89e806a52d27b76fc95ddaf0da01
124	1	210	\\xf5635f98e610ea78c2077719b6718ec31ebef1d610c57b86aae93e5566ad81ecad4f21933b8a639db0b126fbbe941a5d6aff717b595f804337d5eef732f9bd0b
125	1	140	\\xa72e746bb0ec45444b4bb23ecc034007c9023a3ec25f88e523d71a691af860c90514cf9b357a773ed4604aceac79f79eb1742be5513eadc0decec12721e3b20a
126	1	403	\\xc77fad22775682e9b2f5a3f566a57b8ea048a027018f9afbca12dc5c8e15e49956cc0cb30e4d046dce5a5eeb47af7eb21200cda3d4ac237d9070b3e03371420a
127	1	169	\\xf4e3f5f145a67720e9d6e275c27e4562a6361893af263c30e19ca614c6dd77c5eac299658489b8a141ec87ec53cfe4aeaef7bf5686d6e09208b3e7a7a015680e
128	1	327	\\x9b318efdd839af15533ccf09f527426ef36508f989440c57af127bd90fcb4c4c6ea6c7c33fb37a04fd61f6acdb9fd59d2589989845fe8093c5d69874ec1e020d
129	1	245	\\xdeb797e8d033dc7331d6f1f113c9dbd77ee20387c89e9dd64715719d9af224ccab790c9a2810997d61cf7adfb34a0c9f441404d938ba4b74a284cc3fdb62ba04
130	1	75	\\x79a398a0adddb56067c2e5a2dfabed3dcd6a32ac68de195e4858ba2c5b8a9d3f0d8df3871be75a6a4efc51934bbbac48a62595bd84b487ed0e4cce9fae91df00
131	1	384	\\x36478e32108dba90ff861e5ce0715847fbd90af6f7d0fb103bd43e4aa02051a71842aabcaf3448b65f9bb8df608daf17fa3531b4dd5903d9318bcb619f6d1906
132	1	323	\\xe8bf7b109f00c1597a9ab0366f291d2f1d4c8b0548d1218fb6d5ba19f1a2a7f7f173dd932d451b80400ac573d207bb044d1a6a3171d587f0e80c02a004760009
133	1	225	\\x5b95285b10f8194a48c0cb67c3226763ac9a3e4e6c9d60231abe13e8343b08dd00856ee9549b1e2eae51d3943dd8bad6dbfddd11b4c13a47a70bd21c6738170c
134	1	103	\\xe3483e0e420ea325e0e3e261589cca8a5f3702bc8a1f9e5b0e32cfbc11a0f181c33c35c80841b11dd5bea35d536056c7b07490e628d0c4f3f764c67b3f9add0b
135	1	30	\\x59a0b2a20096bdfad5f538987ae1be424804dff965dfb615886ee7eb3c216014e71fc6d49a11aa6622aef4d5078d02dc9fd339bcd1cd98c1c2146b27331d0807
136	1	340	\\x4c61a662e34bf25c47f77b4033ed03149cf146f2bcba8340de58d33486e62eeb8dba5a738f0434be340a74d73444f7a865a43f515d64d4b38730d3620e8a4105
137	1	173	\\x953de3719446cd1778201af61a75d562b7f197627e5d514fa379880ed59462581de6d3e70012f3632aa60a0d46e220fca4a9f57016a19e9e601cb753bc142907
138	1	200	\\x19765517b1fbd66d1ca2192eb03bf86e110b257493253ad0fc49cda7148f20cc24cd9b4a0d6dab0c51557a3d185cb76c81f202f54fe3fdc6f617db841069160f
139	1	206	\\x78c4c14f114d8b4681d45670a460a13406fe62b39097e4b6cbd5d31d1ff8f598a50c5b522a02358f9137fae7a59f0a64d886176cffba1e90f4b7a48b972a8d0e
140	1	16	\\x20d7083dcc521066aaf6e58c3f472da272a2e5dcfebea94639ca8a23c98b5dedf7d7d8efba261c6f5c1907fc6c9cd7c5d5d69b78381e020f5e3ff8fb3e49c909
141	1	157	\\xcd7d9cf98eb51113bda1a4091633b86bc939b9a3d145be429900f4da6af48f91cc6cc8dc30a816b95b5b9e80db7700d57a716a46e0dd3fe5ff1db678fce07404
142	1	373	\\x2b064e0482fce42c07862f2dd161a8ac15b23083850fed5b8e46129c8a81a1502bdff17e7f619895ab8f2c5e7651491c3a2215a667d015cbd9c6e7c50e51370b
143	1	408	\\x51cadfaa60c6204b0dad9ec4d9c017c0b4e11389e74dfaf841565fd7cc3a28f4c30aa02364975612681f94262840d00bb7648b7c1844738b4ad208e328494b0d
144	1	119	\\xfee5e55dccbe3bfef6e65016d76db069daee57ea117acf09e757fe4c549b3b3b40c5eb0e7d97e66c69f8b85fd7bf89b9c755ef6ed5d0d09829f0b855041cda04
145	1	189	\\xabe0d22a3a2d5dbc3360f4c8958a10208e450d3ed43c8288d113656923300167f3f64f49955d5e0ef74afd5b53b822d29c20aadcb3215e9ce09b344f918dc70d
146	1	314	\\x9fdfd72043b53469dd56031f4f720a6a30fc33b67cfe23c4a2fe0859d93f0aa2239385d6654e817f51ca46693f3fa4c0590672f77edbda4f61d209c7e12f4606
147	1	320	\\x726e7866b3fb527636b88a262e2a1c774c824bbf73c20b4ee02d3992cc7bf344af1e6813ff9acf660af1174ce41595fdd85a318f938e7223d84b8d99c9a01a0b
148	1	94	\\x5e3592690304d34a416c16243e0d9b53d540e4eab3508f84a5c89a2ea07d41a33803d23d041e5261f84fd8407a5a328cc77abb2d29c8e8412021b925b480290d
149	1	115	\\xbe4c0d1d4a022e303f70a64902fe29efaf9ce9e67f0aa8f9a2d3cde1c4aafc5dd16af7c5cd19132e7deacf096b2a4da88849a8a3f67ba492a3a7fef04e469e08
150	1	128	\\x797bf52b121e6db498f4551d616f24030dae06cbac0e807f38d8b056b0e6ae881c2e98f7e12adc45f8062bcd61289564f8beede7cc12640b9c6b1701af759905
151	1	388	\\xf752ac1c3ee8f80d062db27d0d895db2937f987c2a07123739261249e35f5dd84237ca3c7eaf30a15ec5d66a26c7170c5326f8be6dc155df1c2fbdd703a0b605
152	1	259	\\x66fd9d26228e83da82fe12cc328efa5de5205f7ed46a922503a75ef07584ad750d17e877657766fa6880898e9a26d5e08eb0eedf2f75dc08b63cd35fea995a07
153	1	142	\\xc9e2f7e7e0a296b8effe7bfb7eb167c58767d86838914d2a6df6c80fc27548b86e500be4d52574cc98b07afb2b3ed6eeb42bb51208a903cf5e68a29ff022350d
154	1	236	\\x41a821539c425a7e33c6aff86bca357fe65e7c213f3e28888abf8f38aae81bc9030dfa7bd90fa30d45241f7587b1e8f68cfeea9de4d9119f06ac941be230fa0e
155	1	116	\\x67bb4c7451045f6d0e1cdbedf4b632458b5311e2dd3f6f70cdd78f6f9f9a04dc8a856d43509b0ec2087ef3b5c3ef8f38bcbd0de7d4ae0d83fc78ee2e744fad01
156	1	417	\\xe35708d2f2046c2392d1c0105db5b0dac076f58221754d9a41e2c7de8e8190d2de79f123ffaf413ad0523f51b6a1d5a6947450cd733b3d5d55500122c87d600e
157	1	232	\\x70634f4a473e187f22cb92167b217399dc6c948bd7e2b6ec5f72ef63b3c4b70fb8c7362a56765cf7dd80258fb13186b0c22060e36faffc17e3604893bb2e0108
158	1	13	\\x03789180d1987fa0eb7df7cdc7b84415e81664f88debb855b8dcefe7a45f691c150c6e4927bbaa320dc96849b62d2d40a3f81414f44acf0803c790df41fca202
159	1	55	\\xed0e7e227f1d6f3dfdaf4f20c84a7aca58cbfb6f9dbd53487623db84bdebc69fa82dcb2250fca08fd2e8573d788ec4404971c02f8a01e1d5d96c1f450c654c03
160	1	160	\\x8e49ab643e8de04dc7279747d99fc974ecd6c041878e6a989830bd55845acb47c8cfca794a12f6d16849e2e1ba5e94acbb6380226c70da422f92a3f3c671dd05
161	1	137	\\x4b26e8b76e71fabb5bfd2c8fb505d3d93d1dd2cc2f00b974330bc6cb7a8ba41254aabc1f84d1710c048c34e2ba85013bd5adf4bea5149eda16fb644f69ec3a08
162	1	396	\\xc26e180985ba4d56c8f816e239b29d7c9a5769d538e6dd208805e8cad233e30ad58b22195f4febf516264d4b7c005c215b9143b3bb49ca439cfd1780141d2506
163	1	315	\\x61a801ea1f011dc5e417804cd0b6f2c83275495c164ad6f39d8d9aba11c16dad48505d6b8be6235c971d5b54512b0798e8ef982437d033617798d2ccb8dc0103
164	1	68	\\x0da6a05ed8c7cd6cec38982d516c2948149bbab714facb6135c361e94803bae6dacdbe190a19b1e7d881ad630140add3972e4caaa3a915be6c1cc3cd5302c10d
165	1	3	\\x3493543bc5cb14fc5d22d8ecd94213a535dbcff5f4c78b427d110332f3943079c695295e2b54be4e4bad3f8ce304f854cd92c8cd19c3bf87b0b950357f547b06
166	1	411	\\x3b08dfc84af97c7d4c44d5489e77941f490f2c09a84c9413a3f9a9edf88b1ef06fcaf0f9aa33f073c16f0890c5050ba6c4a87b926055b3e5392037aeacee8a01
167	1	175	\\x75742be71077ddb572bc33a63824497bf04b00ca011069d2494c79478951b3b4088cde0eb60de13fd1f1abb51411700a0887b330cb09d5141c1ee1e7c7d17908
168	1	246	\\x60d397e47ad861d64472b2781ba363371a6469c045c25e2bf2e6dc197006b5946635936f7ae16786f9c6e131e8ca46b92ddd6440fef035ae75c79c7af4bc2d02
169	1	43	\\xd16241e7c4157cac6e672c8dd30380ed4b71da7d57dbceaab4484dc051cee73289e4fc361b6476b76a359f51e851e0fd020516e4c7fb7f4edb59b481fb9f5200
170	1	279	\\x035572e8d9eccd1b1d47f3f0e05ae1793cbd189229b297c66aac919a68f31c2d59529172ac86997ed0394f10934dea42e0ec8f85a4edbbb9b1157970031dbb0c
171	1	141	\\xa22950aaccedd7febc2a7fa93201ae0cd2cfad9df2e7d389fc445fb8a745191df9ad3fe40612574495fd319d237ab71674d9b564997cb777b3fefbd022666204
172	1	208	\\xe4ee9c2931ea26266c4ca9df232cb9b1799f034e231875d5f8c02e030997c8825964897639679ebee832f111971a905aad82d0609d8b482638a9f6a395a54306
173	1	118	\\x286d8314dd09482e77332afec7cde5d8a53f4096b0ce34519b1e8ce2b6f576d2e0144880df55eb1dde8d193ff9e1e1cc9d813ad5d3ae6fe5eb073447de7c0606
174	1	419	\\x9eeb2f317246552ccbe68eb5acdf453564e7e7d05f4e18f81d40bfb4d7949c2c90674987d5b59ac6e8e703feb48b4d066339b387bf2a238647e060de208fe808
175	1	27	\\xfa3574d3c3188bd8200a440e96d9851514362578f89545d10c22a6e1b2c6c80468817ed52a8fed4b849a7144448a0394094e68efec61f6553cc8e806b13c7d04
176	1	229	\\xa1a765e7df252e93edc6b91919f697d254d780d334d952b3218dacf734c06fa6a721edf9eabd95dd4746446a9030d5adef422c7d9b056d3369f238e81733e001
177	1	203	\\x80ce3e19385d5fcac590e4ce300db6996d976ea5c9509a89cbf94ced0a372de6d92d1f7a813fa03a906a91183b15c71f9eb8181f56daf7113361c6d1b9cf1e06
178	1	126	\\xe20e0e7df43476ebe9bbf65d72f4878fdaa71b809869ae775fa67f620eec29a5b88d16477e052c325373b3750a500afe212e3a542411c2a72a98621e7a003a00
179	1	158	\\x7b3b19bc8f4b93858e8b19e969da4510ce6f00d3661b1af5e644b3a7b723fcb04ed15ab357b401a994c12bb204a73318feadaa934b242e4ec85c709d965b1905
180	1	230	\\x46c014456c90393a021674b1905ccb1675660689d25e571240eee8f7715a429a68fcc27a55aca54ab57898a1c12ab2fb0f28be588fbe8fb27f7ef06025e21600
181	1	251	\\x7be23f1e43c36d0746dfd7eba0dc430ebee593ec7b6ecf6e1adeace0becf8ca468e58dafbca1826396b615e3b452fb02c7da4e1adf298723706e569224ebbf09
182	1	344	\\xd95e59e13560dd1b51862875b13520ac0963b16ca12b603bcd1b6cf1e72425cc3e1918cbc0892de5fbf0b48bb4f7fc9825d8203600d61baf3b5e53bffb22d704
183	1	12	\\x4f91fac75181825eff9c22fa722c286194fd02c297eb516ea8dcc74fa5fd9484008a47a067a4ec66a45f09c7146048f147348127618fe06f57fef6ffec3d8e0e
184	1	185	\\xd07b3851f7a3b8fc9bdaa1d12cbbddc9c009f5a62d5e4837bfa9a32eaf48f9475ccb49a3bb94ef7101b6652f6c6a8ba45d6a1eb2fd437e4e839bde0796a4e600
185	1	8	\\xa8930aebbca7d87a12c52a46d70731d9405eaf2d52bd4916949fb846e69b1403784b7574938477bcd3e73823a4b71ffe495a91367a25e7ce7948687e8fa8e606
186	1	201	\\x601b9c7679b6cbe0fd8d1ee40db0fc5f4821bc703ddfedeff659eaf09a02c7f2ea2b75c775311d51023b9459cb891e349b8110b11050af37e622e7ac7d25440c
187	1	162	\\x834d7b96bccfad18d93057abefc21218e42496aac853ac17d3ff4055f4fea15e02f8ed4c1a982083af46af387ecdd6b773f6718fabcf882d2554ce1fcb6e3c07
188	1	289	\\x465864b48f0379826f7f6e7ec072a341310d446471dab1856808ef27f3a12fc2b3c8f3352320e00ba3ed0c46b5c84e28e8a929beb45485ec906a2f21fd034401
189	1	194	\\x6e2c52be3d576d954299ab7d47276f69f91830788c994c0d2dca550fe9b44cee09bbe5bc678a9d4e2585d13adf51386f5562a2245e943780819aa2b31988370f
190	1	424	\\xfcf76ef5333e6053d1a6042a25bc30bd90a01099d24f97e6e6fc8748dc5c57b965d91823cc5b0010f37486da189215bc1852d0c97c3824bfc5c5920c68419109
191	1	335	\\x74b53036f87bae1e04ab4342281dc8136e7d23559c3ea531e93cd70512f563894f1794fbe76fb72742480cc99e30d2c9e72981a20009b936f56a148737c9de00
192	1	291	\\xda0ffc53e079a529b22cbb554ecba65e555f28c9531d2bb6d7f6c8bc83e7108ecc651a9f5c2c29168ee7f8a9019dfca7109bdd41bbf36865b3636c2509dcf504
193	1	228	\\x044aeb7a7041ceeb787c62dc829915e8ae4e65f4bbf503bf5f709c07d44da7d5734f6ea90a84b728c9bc71e0432087c1270d55cff9f731dddb4ea6fcd49e4f0c
194	1	133	\\x7f8f550e51b3ce47b08f3e2b1057f01c06902bcd726459928ac9ad5b27fd0202177b26883d80c4070bf02bd06e7362ff3b20b974646181548b9b85c2de81fd0d
195	1	123	\\xdb7cabe76f11af7b0ab360b7e378d11d804fee443d946ac9d9a514b292e65099100a9f0dd1e8544575e0e28edd6f06312bc1017ed83e9e10384c0954a666700f
196	1	347	\\x3aac91c176dc389aa6312e505030e1f9d88c87abf50716258da9ec9ef74d924adceca7c7470ed20fd255716669ec75865e1265d7286bfd8ccafea698a540580b
197	1	11	\\xf0cc3acbba70349fc357b14608d59f2e95fbdd15b04ab5f66565cf13df6c32f9338469d7aab41cd960e85b88a54bb5c8f21caf1a4a86b0537a457646475c3003
198	1	295	\\xd25131f8cbfd3be8e065d230a7b10eac19ece0a1158328efefc7b853f694ccd2d6545318fb67c9e307fe4af80e2405776888572c78999bf185298ee99cb4b90e
199	1	360	\\xf558f66bc18f3843459c06b6594b96b57536589aabfd4b7f0ab925dabff8ec16ed2c75f17a8c4237f84d1707c787cba2ea6065d3071314ad63f00828944ddb0d
200	1	414	\\x1f4fdbad76137f581104619cadb6212ed82c2d4d13446a97e0b0bcd9334c62ad3ae661bd7019e6fc29bd93e762c3dc19952c454d8692af6c8b245cf7e2921907
201	1	186	\\x84aaeff3c6c5cd040eefed16b61a21837c858d438068ec7cf0c5177aae8b073be5aba24e994c3756c06e50e3337d835be61504b6ff09768e314e2ce77d127708
202	1	159	\\xf8dab4822e1fda0b1c3e7044a08e2efe4d07a07dee68b487dbbcdecebe321da8c772f994d58d14d99406c7443160a1b4f04e0e6ec2eea9ff348f3d241013ed03
203	1	298	\\xbf916eca555b749ee854d54f53c50ab59570a2e1d9a3efb3b17d8f60d5817c8a3c9f4d167824271a6234ddfe93ef55ab26f269b5afe2cc4aca91b705a8956306
204	1	19	\\x903b9aac25ddbea29da3cfac42f513a0a37c37e0c33dc541996904455e43184c1b03e3d9b5e5a03ba203b68e19a24886532f2c3d65ab6ae49e32e8357f2cb70f
205	1	271	\\x6b675249fd32f9a4a0ae57c41979aedd3339e9c29451240ff09f9f5f6d2ae2bfcb7d8e72c7f39f41a3627c5159b4d91a62335525400f99d5368159c8e958ea0d
206	1	34	\\x4e51e1c759481e2187112ea834720a1597a90ad167ed2a2681a8a28be2cb9fa43b07d47e461512a0e64bbbaa2e1d182c320b48b7c99a482e7e5d938674cf920c
207	1	401	\\x52174b01a6c63d246702be0a3c7561022645543c6848e571c474f4171428dc41d4893465b952a4119b86165be928101e62b5f7218596bb583c1a687cf716700c
208	1	57	\\xcd0f2777310bf4891a6e38b125d054fc41d8dc00f79a7c2cf901eb3002b51fe0612f2e8517f7b6d55290d046d0c2447c210735e1efe11bbe67c48138c3821808
209	1	209	\\x1b9926ce0e6e52aeb6122f98da010d00abb214eab36f381cba3b7d7371c0db7675606bbf6042c844dc80509ba5ce9a2ef08dd02b8db73521e5f13039730a8c0a
210	1	188	\\x2a82749afb386b28e10f6e54692d9892cf865a4580360e6a3851438e423f00db4df6994bca61bd530c09fd4e7fd5c8647f61528a80e6580c155854f83f91fa0f
211	1	80	\\x8d89eb9df3edb7e29afd6b9acb6df8ea77f27e7890a5ee2e6ac50d199b06323b4f42daff121e5710a867bf93e02e5304c5efe3660f40923ad0674e100af17901
212	1	86	\\x2c992ae5be9fe5a961540bd2dde2101784397a85b52eb079887a4932ea3e47fc3f63435497ceba183e3666567f5691e529a2df48c0a748a561096bde07e93409
213	1	258	\\xb902ffe3b196c58d58889964647a46aa7b9a18708f984d0df16bf0b039abe0bc16b52e5aa14eb46004a1ef665ff5ec2574c6a29a70d3c99d6047f5c00d187801
214	1	275	\\xa09fbf0ac2da59890ca958fcd955c3ff4d5fddde17a2661164bbab8548cb9f6be3f44c44847c8daf30d372b65cef4e0f7e3c9d8d52cb016ecb0f9467a3b0bd02
215	1	255	\\xcd3efea22f41fa37723a6d146929083cb12bf0503c9c5c397734c9289e97bb70c62140c3fecaf4239d931e1235d2009b3ff97cdb4e0048020f3738dca5ce5707
216	1	63	\\x1d42885a150a86d1c1e3684dd85b6fd1e47b7a023fa7d9faa370a4c7ef126f3aefd3ed2b8d6269dff0e2f25e7e3b022ab17e5777e99e8a06b6ca6ba50ab1760b
217	1	163	\\x69f537f9d9f7c52486d169ffda3771ce00b40cb5a7ee35524d5c02ad79b43ae6e7890a2e3eb2a32747f130e0d88646ce034474b84d818df895971789e7330905
218	1	178	\\x104d81ea943498baa9ce2a4d7f5b1445a04c1361abe4fab0782e3bb32644130788e2ca2d8088e20dfd6db396eea3d751a875ddb345ded177feaeff0e2a72b704
219	1	375	\\x2162961202112757cbdc6aefb4eb6ceb84512f485954611a2f0faf6bb30a8c00d28d837fc8afc33303af81f3154e5bff6fb94dc6fec76f48432c75732d052a09
220	1	53	\\xb59d8524cccdbadac872d6bb727ad3a6f0b16a1ebba73ec2f33b249920e6353338bdc1f5e8fc069be378efef43df1a4d8b5a7a5d461ae4f8607f11ef0e4b1a01
221	1	104	\\xcff7af1c9c4c2b5a1f4aa7ec4cb3c54675aa3771af1a5318f23766ad7014da1ca3b58f815f302086a724c6077e5668221fcfcee657d0838faf4d19e583fa6d04
222	1	108	\\xa356b786566d995cd8548fe571f38ab9a72c66d08a5addee89f41e37c3c9fdab0e236f67ae39ce3695d7ca5d6b707cd11bb17151992b8959efa239ff44c0fb06
223	1	5	\\xee78f1134a687f03113eeaa6d8cdae9c37e7e696656f1ee5d226b33a68e80a1598215ae88a21ade01d2791595d22b53a74c7602da0a58f6b7057ffe7cc61d90e
224	1	370	\\x239e21b9225de0e0fd801c1f67facca30afa473e8f7ccdc6b29aeca233a06ca5fde262f2bfe8fe35c680ef1ba178236e3b2661b2a8255d8181ddbece30c22007
225	1	284	\\xae7d1fd55f4a88a36a897ff5e9746b9e65f530995a703fe48738ec3070db728138320cabacce12d93ec5ba82ec056124b5d45e712e3baeb015c997f568e3ec00
226	1	82	\\x65fca4f1eb132ff5a71fe8090a78e90b08077f667b343861f830e62eb328310d397f27cad7e50999d45542e21b07d01e35bc7cfa068e1891a5d11a49c2758906
227	1	211	\\xf7573708dbc71c6834783824e987198b4c4be9f0e9330375938810c7e340c6996ee9741aafc60d7f0373c6af5e03b0272bb61b3107ca1f22312e033aa848270b
228	1	386	\\xced2683d47dbba9996ea631c75c27c541d0820a7200187c120940446d464e96737cbce172b8ed38e58f9af7ad3b7241dd5ab08d5849b71bab4e72d49ebb6e509
229	1	31	\\x0a3cfa40eacf30b940402b642bac3ed1af4d9895a21270f9af1705224434218ba7d3683f362465f9b34c0a3ebcc86bd7c56c6f9128a3b5145ae304bab7ccb701
230	1	390	\\x96175efb63fc347cce6f0b84f6b8ceb44a1157ad4003ee5eb1e310a47f32b09631852031d7706b643627b22bdfff5de0422827cd00d6e917ae65dd4086059708
231	1	398	\\x46299728d52eb8c58f03d3667e28551486fd676039858e297f015cf339082b81052b6e41d77fe4dcac569fd89973e8ac53820c32feea6d54d6d2f99794f51105
232	1	333	\\xa050fc24f9618cc2d1757611598d1a01ee3e968df07759c4c9f3a11c7d4aee9de1039b369832389b9fd67a7f4d0dc6d33581fa3f58b22957ebefe24b0c9da209
233	1	272	\\x318157ba7594e19353899da2c69fd051bd6989184e66bee95c58262a92452bb98feddb5d9bf3e3f2e3b50a2aab62d8de019757730d64db8e4a9804bc8178220d
234	1	171	\\xcd9c4fcfdb41ce17159dd1db86efecea79693aa4381188d8da4c2c8b83457bdfdc384b5da991ab9258f09b73971b6529efd4003988815406f97ee7b7d624f50a
235	1	395	\\xc560ea1c250c8602469c41612698d257bd3b0f1e7de8bb61c04576285d46a52ff143c1c1a16972192cf366b135ac9135cbb9fde6bd8314574302932799515105
236	1	54	\\xa4f61cb100ca1d10e577f0b40175bce4cc484a94dd3c80aa18b9cb4213dc4a3af35273c7386f213a4137257b26b69e590db9c05a202ce0b316c419bd06f2fe06
237	1	21	\\x89ef372286a58cb3fb9e6b8daef283ebe397f10196ce01c6b164e25ae027bec3dd89003d5d06e33aaa93dc5f4c341b8f23b24117b792a789d3052463904e9303
238	1	2	\\x154749924b90b3684fd1494f78d1bcd2fdac242750dc662da07ed80e15612ba28258009545adc0abad7e660aa7afe20e16b281689bc175cd719a6fda1ffeba08
239	1	106	\\x5645a428e30fac23797e8b382a4a5a31ef4beafa350847c24bb65e58ee3a5666415e96bfb5f4b2e13a90cbea9427bc0e2ce790246c85e9637ce18daf4fb61506
240	1	71	\\xc35eba635455706af074e66093e9366a2c3ee68f32729551e1a97a0c6aa252e4d33bdf9317015f7374f10f0988ddefa683a263308cd0780c83f4c93e903c2f0a
241	1	354	\\x0dd28d3352e8d26ac247c657396eb730d2b3ffbb33afb8cc98e358dca3b631a6e4ff2c57ff936750e18dab9ba0f9be384fb69c575aa596c3bea4e93190dbab09
242	1	147	\\xd2f86c2946641811d6cf26dc9eda3a987cd676bf37b856a70941712be429df8b24351f8fac04a4d7a5b6713b4d0c03921d264b39f2022f2cfbe2d4f6def19e05
243	1	174	\\xe74805086a6eeca9b5080627b91e0edbbcfd6000f954f60f2373ca60c62d63d5e8257624c37f384b5c597621df305c46ca5320b4989e78346e9eab370852820c
244	1	267	\\x0e22b803d48805a37f12e1d4d22b079197caded8d14f31c1d9b299d65e6bbc60aa710b1064233cd1ecf060ca7326b94c9c7d9a352c374293bd1acd6b6dbaae07
245	1	111	\\x179592daf01a5b20828be86304e7f4d08aa5b243cc03b9189fd2374af88af98e5a12d9526e1f8458df6f138c3d10a188d7b2e55d994031b2e482675daf7d7d09
246	1	393	\\x9dd6d29862e540eafa370093389223dc500585475dd6c614b1946380eb1c86d58b1dfa2f16d8e050a20f912c27736258ae368848dde400de1d4066ab20939702
247	1	234	\\xc3ea18c1271010777a3617d0a3f3b707a4b02886e0947261ac131cc3d94cd074f5ed9e8f7af22f46acbab7d2db686bcf044d5219e41176f30bfa35a1e0666d09
248	1	294	\\xbc501ff2b5c75958dd3459aef2d872ae3a6107c9f19a83d69426f4614a23a417a5fdc19eea618ce89f1f3a079176a509dc79adfbda37c3493a76b4858389710d
249	1	198	\\xe146b2bb345a370894709c625744d319b94b2bd4415f87922999bc933d53060d5e7afbf19acea4df4e3310af20f3f52ac972c0d9926c5b41ae1c70b7f8e3be0f
250	1	270	\\x4c24775d8b8624ef6faca7daff66c7bf536e2a21d00c473d759d22cb619cee8a5e05262260d1ff682cd43dae09fc1ca12b57a501ee651ef19e0f0931eabb5f0c
251	1	357	\\x30007346d87cc586e50ad0f9649e40cc4e7986062e28f7675a9a79825ab20df5e5ff75465b99c51eaaf4fbecf1d4edd7ef274b8c69a207e3a629014552496b07
252	1	217	\\xc9bf579a9a55990259e4bcea8f9dc6adf9547370afce68ec0adaa5ad822423ea3e35cc45cd2a6c0bea2501d7e0e5abe56f9cfdbf7809b1db466bfdfe64d74109
253	1	402	\\x717a0d9de718e22f733f47ccddf24276cb5f51babae44f3dd2e7e79807055b62b96e1719c4181f48d9da1f07230de5c6477f238ccf54bf2f50ee49a2d9f3920d
254	1	218	\\xe474c67ab625830250efedd1391f9a5f363f49424d43bddd260e32dd83ccdcc751c7de7b607f0bccebae97ea0d2369977855f91d79711db91b8d891734b96309
255	1	125	\\x1b00aaf7ef4c934e00d5709c19376e2a327217d68d87b6bccf57029495d96f8910419e13dba03f3526061611834fe9732586afc8388c8ce8934588ce6f05d10f
256	1	222	\\xb77af7f3ef43c3fb6768d5911f11f1552c565f5c402183a0636640ab4ce94a616f90eab8bbf03face17fc7b17d364e4e78b05da9ab7a1ac0acfc08d0c6d9470a
257	1	212	\\x377f50bed5ef61f3b60b07faf84531b177a5657c5d65901468892edd7e0f3cf6664bc14fde8e3a2d4c9e20459cdd1b1cd74d221bded0c8338241a80882e86507
258	1	26	\\x9f9fe999112d54a4cb65e1c98dc3f551365545d6760b2bc182b07a59070f891340be99b03d99b714b70fd5c7cad23d744b4be6d19945b3dfb68e797060327e07
259	1	377	\\x01611f2043d2f2f914c99fdbc03e15b9ce109bb9967a18dd775f575ea01de83b1ef3a5f4037aac7c100bf05786840c39aee028ef611f20fcd211eb719190dd0c
260	1	278	\\x4de7f8f05b764f176dd86e261d81d0ad1137650bce84823e3f01fdf59dc9c4a40798c62f2148833efbef18df7693ad4c126b8af79482a923d3ff14e0f3a8e504
261	1	322	\\x56c37f414199034b79fdae6dce894d5c4c8d7a56a554dfc980d3c53a756d8e9075e9a2df42c393f857245b338a21d300d055ba70e1bbb8b08455994112f67709
262	1	84	\\x4ea1d0c5fd957702cabebb4fc229474095090aa15b3c3d49091fcb42dc47c73e577211f6364d084a81f691be7d82e509c5376fe2d54a4491007549287b18c508
263	1	41	\\x0be3072cc7327115bfa0cba6b0f7ac46928e5a8ee143acad96accc5ab6aaa14a11c1e9f98c34c3cc71af5da489ee570075178a9358f1edcdc23fd297a165270b
264	1	15	\\x3e5356fdbe95f0148de66dc1b5e5407d27b96625efb551da12fb4b54e8a1bdeb0660bf75e50eb059e2c756279ed822b534b243215c70507409fd78904dcc600e
265	1	326	\\x7c8f0adf44346899005a06c771b64adcc365dfeedb4dcc392733e9f9b8c4e28224906fd1cd908ac6ef7a9f9693a5992b20bc88b16349916c2756c10896ee0404
266	1	358	\\xc1cd4aa4cad500d601034da03c55ea9367884676db41f5acb892aa53e2543530b92425cd73fb6142215a32f591e98209a675bfa69a4961c37eb49970d0c4d60a
267	1	39	\\x59200ff01ff2fff77af746b0bbaacb8b78181b3d9b9eedc84391b1389a8ef2023bce06ceff149bc615a88de36b672e3ccc8c042173ffd3433de08ad7dcbaf109
268	1	355	\\x0098f6e7f2c3e4cb32bda74b37e1af7a10112a7e6143925a7f58a0add28c9188cfa5f5de00b10dd6675cff2e1963d41c1e9760a2dafc8b9206c9870aed8b900a
269	1	139	\\xb98788e3bd5a233debd065ebf9de0302325c69b99502fda44df0d97eb159947850905f2210182c6f60e120391af2e15934bef14ac7bf9d09d46347c8b56d7509
270	1	362	\\xdf1b49a0fdbde4fe65f8f116ed3a5241390d488ec34f3da115a3f9c0ebc26b2bd4e70941b3ba0eae437ccdeca18d8bd497b4772079d37a2a62ae46f4018fae05
271	1	7	\\x175a7086636e2272d76f9ee386971bd6e81b68921a37987d145fc24fcea03e262da0bfcee8a2899511055e90b5ef43db1b5105f2d2664ad91dffc1078540750c
272	1	156	\\xd8dbb57a9352798bef3fa5ce93de7becac9cdf3a3e5d776a26ae24ea6c9bda00105637b2e785302ef37f39f8c4c46006d33e71d675e94fca3767850cbf312405
273	1	58	\\xe9d12ece13c449ccf10c0d2771c461c99c50f9febce1510951826f7b438c2811e555aa6b066c22315e0be61a48f5d3fa782964dd73065fafd2c1a64a95e7be03
274	1	385	\\x7d1f58419cd1429449f9fa11f845338f5a3cc277e695a5004319766039225e938eecbd748d7928911f16b816a3603dd2ef1175568953e9d7f479808af160cb02
275	1	85	\\x5fed9a91f6b6540517a5316a82df424476485561bbe9767c6c4369907d8431fc97ffe69d6a9a884f9ae85b00854f21925cf5c431c857ceff1dc363e157e5e104
276	1	107	\\xdf3c764cdc8e363d89053a87f8b241bc4cb67dc62a7e941bb79dc08fd871774c93abfecff42d810bdd26a203842b47bd8f0002b19a65b3a7ea6252196dcb5d0a
277	1	204	\\xf549a8e7cfe1f6188ae4887663eb7bf6eebf12134ec1387552014aef337501f044e175e9e7ef4f2d055ca52066f4e8f8850ba046c987b6eabf3adc279cfec207
278	1	130	\\x0e127afe123e0466c3f0a216f0f004fdafc18245e662c3a9ee01deb4d11bed953932f542cef245a9c9a44310e7c54c7e43aae547c836deb3d4b2d4a781e1ba03
279	1	227	\\xa43e8e7ef776c219221843f8ff9613dc5fb667d2afe79e0fc1eefedd654f97fe98a54f9c5ebc73a07ad9b1d31ea3f105cae381b799b6d8111ac4534ade5edb0e
280	1	155	\\x7c1a8741dc9cdb3a161bebfcada7de2f68506c0f49f3a7eb04e26d63a4ab7fb3c697bf112774d25564630dcdf03dd81649f66aa411608f23cc859c03b1d44c0c
281	1	331	\\xbc268930da44bfd8062764e5d5891e410cde499bdcd8872ad0489e7a7fa61f5e22168ce659e1dc927f45798c49aae91901506fed3f47a9febe2daae430972a07
282	1	78	\\xe128fb74f95e52dae7d8c47ec7620bc426eb2e5da73b56618815cddce31a907e5e8b3ecb9dba1cb1896be20a5ec91fc4dceaa337ebddf0e845273a9b3e1a3400
283	1	25	\\x25b9865a766db7143066ece2f4a771106d3f9b945456600a4eded38dc2d79bf7e4bae3ca29695bb10566c14ce5868d818eb49f3679929aba35f6a74821674b09
284	1	52	\\xb30768d0d6bb2076fe5263ad5a99f0f4540aed204414ca8f9d3fb9bf866b30e9a830c22f4d1d0c9460f7297656ec36ade98436b7dbd46cbfe4cdf97335c87708
285	1	263	\\x5183ecc45a3fadef0a19037c7800ee3f8f2a7fb5738b73e58a37325ac97a2cad1605fd878917929a733ce7efaafd33117bc50815510d1824dbf08b31cd20af01
286	1	253	\\x7410acae4327e805e4e97208f7b019e5e9ecb4284b1b3da86bddf5b8528824d0f688d547371390557ef3a3afe5922970143d90b9887f0d56767bd5c97c6b0102
287	1	197	\\xc5191f20212d3d99b3aecbb79a5be561d42f5f907b897087016f95c3f639dfd191214203cef2033a10c82ca91fbf163a6104e03c1687214147b0680976f12503
288	1	350	\\x3ee8877ec9cc39f8e3d2e653a21ae2c60b515f2518f63fed0d99ff83d9c53eb789caaf0c7fe99f1306bc43de146a206f7cc09a4875d3f7445973045ef58f4507
289	1	288	\\xa0864a1de9186c6be5cbb6ebd7c245db7f4afe4c8207e8b2282d4bfa7f2667e582d7924fa1e89e7ac5b2cfb3b8b25c86e856210f04727afc7554e95b8e728100
290	1	177	\\x10fae9a469386e1165e29386fb0bd20da9338c44b20105867f05962240d0563c375055d77fa01e8bcd59bee5e687ae0ef454c46ce1eb254425281c5ac7b37601
291	1	207	\\x158bc15a54c99e9515ddbb4bc09f964f8c5c76a83bc58cc8829c92c85d2ccd7dd3a40cf943371a68fcdfd0d46ffdd699efe5869865f72572d86287861b8e960a
292	1	69	\\x2551634b0fc10ddd585f468da7ac63ab38638fb5690678a68714f9a16fe21533d3f7fe4d62923f476534d2d829c0ed7872129140d07a32d1bede4bb120b1940b
293	1	81	\\xce513ee6b762c6bbd139247ba2dc11d79264b19a5a491b157c9a0884ced41e7e02eee6863d93805e5b3b76782219936518b913c5b739756004d20e7952272008
294	1	170	\\x4a289e736549de21743251bd3c86e52d87881c74cd993ab2f9c9422695c00042dd1f67ec5ccd4ac8ccc42621b9701884948b8e4ee57572e1a525885a7e035e0a
295	1	213	\\x7ea4d7d606a13ec7ad765af3e0bf4c62b2c1899f02d0dc31e675b1f1583e073c33336da2b8206eb140db9d0ea257247df9004987a62388ca5edce24b93769603
296	1	276	\\xcf2a59f1c0c19a99ac94d6cbe34093e3ebf0ef9fd2142bc9d992fc20a04ec53188c2c72564df487fae8d509b044e66fa16a5266489ceaa633bd7c0883ae2ad02
297	1	381	\\xc1c7505efdce9042f302331ed2c4b25daa3b1141c7629551a404716cdec46b434ffc91f13bb2ed53dcb4c0013963cfe61a2eff84c1a308d7014ee7f66be36d04
298	1	308	\\xe0865eb8fb8ae6f14ddf0469bf4977a20eb0f74bfab91f3fac6ae361b609221f53bfb034273a181640d903a65b6b5eb09f48d35c7e46e08836a9f2ddbdef8d0e
299	1	98	\\x59ecd1692cb73c993c7d57836a372130db5a4ac8a1c71ddb2804dfa7e9161ae4f21c14a1a399ae8d18b4818564e98f6373573529bd3ed96d07fd934707bcf500
300	1	415	\\xbdd6f15b183fc35efc9ada6152a9fcdb8ed35922c5d5c5414f2adf7edc4e0fd07b4816d032031349f3a9fbe775bc94be693424c6580475d842b387c051e57c0d
301	1	42	\\x9b20ed31d28c98ee07fe4245a9636d3d1d951a0c9de10c3a703612ff204cad194cc52ba3cdafeb3c5c4b2e93e650ba36e21c6ff4dd34da78f75cabffcb6d740d
302	1	40	\\xb6eb410ab45211ef8feb76ef005e40f3d85ff1f9c36c5c74bedd09815cf4e7a9f2107fa6528f8bbf33f6e3b9c2669d71164d8f5bc700199c935844f673ec400a
303	1	61	\\xdd0ada426938b4cd9c3f475a5d585ccdd8eb90508755a625fd01b3a2a526661252d336c68787c908b51b64950246c2ff9d78f34bdcd4748bbabf94673501d70c
304	1	129	\\x1fcdbfd1513c00b3aeeb8b4a249fdb1e61cee8a4810fb22540e5be9c605ff4cc6e95301f9d3e19a37eb0b6e449b58f83a433e3aef59ac57d07c11dc5581c3b0b
305	1	117	\\x8982437ed6928e4a90de0e90cdb931de6ff4314dac5efc0061f2a09d75dfd8cea9c3fd78a846d0230fa500201aa52a1513a1ded89123aa185d543e27ee3c2506
306	1	190	\\x9e36451431fa4bafd0229b395263fd48552c555e9810d76b87c3e2ad161f71ceb8f390f10458bbffef4aa5ff3731c5cc41c4b741afbd656cffb8be328db6cc0d
307	1	374	\\xe89c927ebaf8c5ec5ee1494545c1a6935298d051ef30038533b891aa75650d336e54e1c29bbde1bbb89610b9263161e3a6854ac5d5d9e2a89485bfcdfb91a307
308	1	152	\\x34871a9179de116c4d8d4bf3bdbfcdd29c091c6ddbe5e37c53778188d5f8a94e8d0405db01606db3e11592575b6bb539e63174295ff7f8ad64217edb63a6fe02
309	1	304	\\xe721c659ad95d1fd5d7a37f64ac1ac85858999fd971b74ebe42dfcf0cc3e6aa97a10c5ace08efc478efdca0bb8c04fd494dd951584d248aa0cd2931ee97dfd04
310	1	250	\\xd3f9dff34ac042b069492ad38cb42b599cb868ab06e4385589cf64f4e56b7d6f95e609caa66f2c9935e32304d8b48f5405d5a59890f3baad7cffd5351bb8550b
311	1	349	\\xbead1b568f8ba1cabbfcede17f198cf70daf937f19759de7f4954f3277f9b50ec58643fceb6767b82a4136c75a288bf33ed3b418822d055d0dbcb4a3a61ae200
312	1	286	\\x3847697ab6d863b3bc50a3e6b1f0fd9091e2cf73a292d57af0e261e03697fd26129cbe088ce8c2741b83382b11ab0c5ca14ccdeb3a1dc37d85a6e128b3149205
313	1	283	\\xcc292822dbdc34a9dd426e7d8bb5f25d7298906e38681727d8508f06240c8a7e6bc2dfe00bd80a838a810bdedaca80ab5fd4d3c1e44ce8c9220758f8fafbd40e
314	1	56	\\xff101710b2475896bc0b500043455aa6535b0b11e1999d77e65cb0d77ed56e0a3cd41c90e9690a5e50eab1667619e1cea4f245d804da2ab624835f9a9726d704
315	1	73	\\x3ef643c6edc6d2757afb1bf20bb9c1e27722b9c2333d3561e2c7aee8fcad9d0acbac5a22490c4d845458b6604e99c6b60410dadb9fdc11414662e63c29b4400d
316	1	166	\\x30c8a97e7b3f529c4885eba9e6b74fae941828856606f6b6e2f67ade3c44d20f8eef5d8b2b837ad6d4bd2859375fdfd29b33ccefa9ad2e85577c29d64b8ce507
317	1	248	\\x1b640bc73799251f84438420285739391963d5d6df684a5ca08b1b87a35a25621778a4b4479935149d0871bb700808de61156f212ae0b48f9ddfc3292d56ff0b
318	1	382	\\xc01ab50e167be35d8b83c27125258c0a14a70ec63c48bc018c6736878e53292a6e2053e429314bab08dcae392dd8128861a9147b8ec3a4669ca3bfcafd547e0a
319	1	24	\\x880bf2deaadc5a3785d2dd7e936f4c66c97388968495ea33256cf59ad0d4874f4601b6f848ad06e501145d29559fac061bf6536f17d897442730cf308bdfee0f
320	1	50	\\x263b663faa7b7a0ce04651e75fe84f2475d3942df87a4cd03daf011616ce4fbc9178643817899351d70a6648844a88d4caaf4b1f030adfaf37c7c68b41e03d06
321	1	356	\\xc35a70f031d46d3f27cff1e50089b7522a01dab8c44cc3afaea88587808eab53ba741acd651c36d23f4ac6c777fcd276d82f0cff14809549c294f0fa2e034d0e
322	1	17	\\x5cc5d78a21372a8a14420ed14881fedd8ddf7e48065cdcc464d9f4807f3fc8fbc444fa7c9a619dc67cb8e4ab3d7bb89cbaa904027f2c6df0c1a456bbc528860a
323	1	330	\\xca1869b2d1a64959653dfaffc7833e2316f3028e199c97cefa1a226f30bdfdf288c3c0ef029bda5ce98959e0161d368c968b8cebbd620ce909e61c0cb6a39c06
324	1	310	\\x059a88b70cf7ce61abe661b5b13fb3b1b4979ae220120dac06e3da4c53bd541d4508586a245b13ccbfba95404c411a586743f2acb5110da30a7bc0295d84a90b
325	1	311	\\x9f8ded531c4b6f4bbd0eaf4435242337dd4049227bd623ae3971416d48754af96745f0cec908cdc856a4b1f7fa38a81b13bfef323caa37b16f298bf474550a07
326	1	224	\\x0e2c4094d30d45c9319ea726d655771c2c271fd889bfd5e4950fc0aa33dcacdf8e02eb2336df95e185915170040065b14f431bc611d16e33bb1972afc908340d
327	1	380	\\xc5aa914f28bbf212dabaf1b3e3087f460b3eea20bd9abb64b5293ff3e4dcad5cdca51667640583875fed604fd4b19cf56ec0697e2d725ddb454ef202ed8a9d08
328	1	172	\\xaffba580a8e92c4140d8f371e6935aba8eab032f1d17347c5e7df8e630a3108bd3cb8ed757c176de232acb5453e9db17727f048680b5782b1ccb3d21e4347a0e
329	1	262	\\x2c948384f8a9fe011821f364ab977e87f79af4eb5e174f2c29aa6e09ba1db93403cedcdd6759fc9fba6e86ba93bcbdd9f0cc6ed0868bd1c66f3e9a2b6477770d
330	1	339	\\xce9f848de9e94f9a5503bfce20f6199940052436591c36e7d7a5a06782c8c2be49062d51326d9bc695b3cc896cfb914d74068459f376d549074831d0e6657f04
331	1	300	\\xf8f8de3a43c9bdf6905d6f277e6bd26f904c55eaaa25b92e19ded3ba78f7a7b5f338614faa81ce97abfb7523a18e30a2925d833016dcd752a7739c9ae90f6a08
332	1	249	\\x5f957e801791235a44db780b419cb6c6df9964a92ef421821a13eda1ff16f0fbf0758903740478008d7fb66be9dce8ad1d3b0e5d10f3f26ca5dca914248f3d0d
333	1	277	\\x64121bca38abd1b1901a73c2ffc936f4030389a05c3ccc44e6fb1f456ec73a8da1e3c1410d7ebf0c91ded7f518a93310a8398f8888a81b694616a9673e8f9c00
334	1	247	\\x99e19b3e11f3bc94940029c0a4aad57ad1cf7bf9a5b2c08331c7f587b1f217024874edaec9c4993ec74c958bf8c42c07e4e52e3c8afd4fbd3364f0b26afbb30d
335	1	378	\\x6353a92ce0762a574e43125960f3c219ac8476ebe32efb648be7e40399e61abf0d498efe990dade32367ba0d6c8829575f2a95faf362c85821116069795c7508
336	1	319	\\x5b2b42f051f1e03cae432c4c0295edfa93d405782821f1776fe05859131983ebe06a9e4f0a271aff4b480cd3f70d10b5be8a948c5b2dc7ea1e3eabf1f9e50e07
337	1	341	\\x89d11fce831514b88fc1b5cff01ce39fc251555f8696879fe88f0fa7daa12cd74a6c7c9775e1f4e4d5a433366fc7dfeadd02c6fab0f5bc2b0a2e5cb496ca7602
338	1	367	\\x17e36ec7bca9580f5f5522208edbcd6a0c73dce8c8977e68b364387f3e8e399b0225baec81a3a669799daee70f88579c919531fc16b1da19113b49d546f37d06
339	1	205	\\x646b23a81755c149a427cb1a6daafff270f9ba1f3c3c74e5b78bd12ad66f7d3566d1304f8f7edf210a3f95ee474f82987eda82f355414a5d42ca5317bc1b5207
340	1	161	\\xa3961043cb743b77fb9078101f3abccd381c14e024152b3034f86b5569750652e420f8f483b5a7bbb2072540c757113675668933df04230f1f14432ef4cf120c
341	1	305	\\x508a4b66c8ad846fad63e6ded8a562280fc59069b2b4a180773076a6c24d934406bad6dd4aa85cf8d1da067f22a2e85e97ea74eb879a13d3dbb03d6d1a05f204
342	1	83	\\xf61d84a17d82a67132e89c209f4883270415946593de9470be6c24957967f276911f8f2a0fef2cbd3e3f158b33936ae61fa2393d048c65a6288822493fbc0600
343	1	151	\\x3e2878867d386577f7abea1b02160e27ae684382b514dbb9bb1ac69581111db84dc79ae50c6d92b0b3ca8d73ac2df166ced4b5c136e10caffb2dec46a53c360e
344	1	64	\\x75dda22a1d0e14ee32f9047ecc40ec55aed0edfd7b1b9ad0716b584ad5c4419632ceb64e4e3bfa4cb5a0cba2c7c3fc82cb0461b29973782c338c7065181c750a
345	1	342	\\xdcd290ebe9e1e7d728f2aae4be7a7195586e5cb7010854665381de0b725054baffef677a5b345f0aa1b13b8fadba79ed573dd4e25b40b48cfa1709056b798603
346	1	90	\\x5e60954aad35f7a3af2041c4aab3c8c5374c91575199493717d3a848105ff1e6e7eb17ab71ada9fa714bbc1eb7cbf6ef5237dd9a506c5d8532768cd4ae79cc00
347	1	345	\\x58179aec5eab3645714319a4f6bc4279dffe3a54050c22ebc3bf662729ac045fae9cd437ff1e2dccad9c446aac1432eea2f1a412527fa80d5a73296661aa7a03
348	1	413	\\x5c4ddddb665d334fed1fce412b2dd96b70ba625b6bb971fdd51e022fe9904d3ec86357283676318902e2b9473e007696fea7cc9e79a950bc3eaa587e3a472300
349	1	138	\\xdd033b3559501a26cca48ec2c90b42366a51284adc0184b1b8c7a2b16fad45de2e53afba2936556d257cb93a53a740f49351ba85e65fa16e1fba2ee1abe9bd07
350	1	405	\\x7eaf92bfcb72dcc5d943b9ddde647ccffb717196e71ef5937cfd551d3e6e07ce5a7920409d4e1397565cec25499055834a0eb9cbcf0f0cf7fb35b860cc028f06
351	1	112	\\xa7e414c580e9dc77049235f5e68968eae37f60ee3437fc06e339d828152065ae9b889aef9a90053b9e8dcf55664ea3cb1862e12ee4621d62a58eb9906bd8a00a
352	1	70	\\x7ef0554283eda237f4f5e16130d52d73cb56208760e0ecf114f65af8f7181546626f32dd2f590898574d15d39b559613916854725b8ef96a4fa9ed04fe5e6405
353	1	363	\\x1f35bcfdc68ed1e4b0eecb167be1da986c40bc2d0727b7b23b4084a952ec7db98f7e2738c2f0f8b0389a9d7ffdf6a16d94e0bbaf06edfdc35dc3a379f8180704
354	1	101	\\x5a4c4dc200a00dfe6a8ed7072fd3a7b9026740616887066ec861ce34c1fa67aa97c70716ff269d5150be9bbd54d8e7e9443d4063b8272aa91eb4536a00c8fe0d
355	1	240	\\x727fc2294090d9419b2b2898f4ed7a380dccd6052346c4641e867e32965339f55b412ad3261bf7545fdb9cb7d72df8655b9679e433675accd474fe79acf6700a
356	1	287	\\x79f048d8df6aaa415d03c24d7ce289eb30c3878d7485ab59a7fe9e6f62725868d2c0555672bbecc28d5fefe7a8a324c3434a8e8520c1e4243fb6c23cbf1f3a01
357	1	292	\\x211a8e3b9e25fe2b0a196c409c478899675ba8f86b8240a8521231ac4481bc7a232a7d63ac5336e9f0a84f7514b5b2cc173b4780848635dfa9932208fc747c06
358	1	74	\\x20c747c67d405d9c4ae6dc5ce1f55bbd184e83aac5de0f1a302903d16cd95a8f3ce5d2cf43502a2d0b02d347230b09a3ed9481b1759f0a406572974af7c2110b
359	1	379	\\x02d18b6e94853f07a9c2bbc35c7ee74f2f7ffd04616cd805f57b4ad035131771979e3e0a1bc6a6849741c01943745d7bec297335215fd27c1a2b323271a53e0d
360	1	135	\\xe3f835c28736509aa6e5c6d074e9f69ff09203e15902631cdafc0c8f349658a2a0439d41b6cc26ea5c41f7c19189d1d2b7bfe753f081638eaf61e96247208907
361	1	268	\\x5c961347cc785b7e9fa4f27992c8acf6f3f67ace583408fad2451a5cf98e8c9c6664c72b583b83d276f279a3fa548d79244f12d1a9d7f31df4623183fca6bb0e
362	1	392	\\x6d0f6f7a889cc178942d09b4e4071877695e5b05c9fee9776ca6b374d7c52bc76579e753b6efc4307cf3003f404ad04db1bc4fc4d6c6a099851215f1b8dee301
363	1	346	\\xa834f646d8f5b492af2c1c279256d116e8b3bd0087970e41e662d8e8d28e26c88405c14820110703a3bfe49e20831c41ca9dd24bfcd0fc9bcac1bf6695302c0e
364	1	389	\\x47c188f16fef15ff6f7c1d359607e42d64717b366e22aaf2ec26da610c7acc83e0138345b79b903c0296316cfa6e20e0923ec99c71cb589a91cb44d0ffe65903
365	1	18	\\x6e360adfe5b9eb33d6ac2a9357e4e74e8e0d69847e2343a7bbeade6469d6e22ffaac57f28286d5f2f25510f4680cd38ef9a983bd79a7a975ddaa2119cdd2f309
366	1	353	\\x10da70ced6262199cd40fb558ea676346af7e76d660e987c443ade0b49553fa7c38b0b820c80896199c9ee67c4a6ec2a5264c3d9b69b42378548e5319dbf5a0a
367	1	131	\\x7328935fea7e8d70e39cf5cbbc2b2353ce2d77e727e451ee2763d16dab8d9c48277e52856c57a0010eb683525edbe625bb1ae6e7a9e3e0969991b8af1ec9c803
368	1	120	\\x12330ac296e44638838b0acb00604964652206bf59197ec3a26f15d5785b380ca74399037abe403cac1b513b1696062018ac0c4dc331b75b71ed26470d06030b
369	1	400	\\x8a9075b5310d24c7b5551239cdadb31bba0580e5f8f886d054b8678194a316a6f6aea311eef85096f81f5a6630868274739ae0f3dfa71ab79a4998f4d7acd004
370	1	260	\\xf0b8331aa7ad6830504535aacbb833f98f9773f41b6035651f656e055019b2c92f294554372f02f95057c9f9d9b7d6f4a43a618033a8164c715d61901f95da02
371	1	143	\\x33337792dfcec5256d2ab25ade466eab57a317d01078cd380d6276ba3716cb6e539f56fd415534c211be8ec048732820bb8bb17083362b262e64da8231bc1a0b
372	1	348	\\x66528e0d33be3677117797b1467bf0559d3ca3d5a12a59bcd8e494f1889d21190c0aca7d3b216166dbcaaba093ab43f3ee74acce5ca8d0f6d4a4d924300e080d
373	1	36	\\x4895bdba53b7374da5c7455b30f96c0b7db0b0cc2c8f79cb1323a44d6e8030c83071a686d0234a1ef40e842381b53af7da5ac04609109c7c3826c0439386d603
374	1	168	\\x770c01859709684850f4c45bfa92031c7b9e0a4b7a4bb7b79d2b9f3af063d8db18611544568f46d6daba6e92cdc75854e38ee8c7f02c6c8a74d34acfc190d80e
375	1	418	\\x1d39f884ff60df3ee1119d1e12a289c3876f5b1e52ae0d67ef160c1707b4cd5631275347a1e672b4898634bcea682e9910da5ccd12ba7d93bc9b4377234f1408
376	1	187	\\x6c25839743d983963df550352914bb8669ffe5ce99306883dfc3c7ce68f450bd5884f91611cc65f4cb1250ca5667499cb2e23b13e9dea862a61d17db6cd5350a
377	1	368	\\xce6f84623ae2a382f9d71368f3fa32e10ae0abd7719073c9584ac48054d5940f205577291be2103699b496940a23f7630a2ebd094907e9378affdf5b0eb05407
378	1	324	\\x23d05bb3a7c6ed718ce505f0605289869c98366b19fd48756ad14440be05bb50b89577021d3fead9c4ffd2fa8289f7e89310d0b6a287f946a7ab41a86f4d2302
379	1	303	\\xcbbaf123b127c4cb934cd8455191811f102ed7347c29148fe8d9445916ed9b1a1f2c5045ae14942bf4385dd2b982eb0cea460a9370145261bdce0599500ffb0c
380	1	361	\\xb31a636fdafe7c8feb8f5c1797c67053f71f7c7e708644c99da5a3c45bd3d1871d9c1ba419a0110ad39ea49ebe65eef7d32fd83cc19a047cbfb735f6a618580c
381	1	237	\\x8661dde7307026072e004a33a9b5aa19a25423068df2ab1233b45bc69caca30f49b6d7654bc33f7eb8245423e5aff42db5d7428b4c46b145dfa7c154e9fb9e0b
382	1	317	\\xfa0cedb44fed4afe1c6206137fad72a6aaf64edeaefa2f7696a1033bec4550a8522652a1e214619506195d6442aa861c3bc4962191c881fa078e48e1cff30800
383	1	352	\\x3a731c88079e34eb3a64c111a107fb52229e7c482207c51536b2b2c4cc033d2d20f975e61f6ac5f5b8fa1876204bd58230ae0fbd3ac3e6c0ccff5f608837a109
384	1	257	\\x1e46f9496e1910cb0217b608ca117e6b92186d5feb1dbdada4ed3745ff49f21bca3b5933bede1fa0aa0f2ee024b93643bfdf084ebab1e1c4501438a9acfaf003
385	1	410	\\x59f9196376ec1ef946cee44defc1cafedc00a8168a3853eeff0b8b4642720c727cbe693dc09046dabdd6495fc20c58cee56794b4b608d45030581a1525929503
386	1	316	\\x464e469c936414f16e812de9421c5192ae6b141f53768ab696eb54223910398f3d23676b32594ae6066e368c5f32bb94182c0ab30e2edf7b8c2108a341e2a407
387	1	20	\\xc25d71f3657a27a086b78359d6e3aee2ccc844b7d72ccaf25da97e75b1d7611c376ec1a814a299741b79cde54a3543582d8f16190e79febe894d826568b1d805
388	1	223	\\x5d983ecb0cb9490d326acb64dc7471a260581af8cf4e076e6d06e79dd4a034374a79fb7fad84ee82df83c43e2e2e7708375311e902676aa731c3e4f69ac2030c
389	1	72	\\xc4e18b0d9ea83ba03e8aa5dde295734433c9297d26a1604349c7c168dbc11e5c14757f992cec83a461fe095cb61efa979db590c4c8e5b9e71a8962823e2e0408
390	1	167	\\x0fbfb024ccfb06ade3195ea7020eae9accfd276804800f170bd36df8f0bed137e82bad874d8ae0818116942fab9f1bd8be6168d0c1a3898b1722de9e80614f00
391	1	121	\\x888cb0afdccc296646a05667b4af8dc78693f87113e01e1b20ae72a8bf0029c46776feb01211ca25fc9529aa67d2c0a19524b65be09f67575dd96843fad83501
392	1	199	\\x78f5e5cf9bcfd96e058a809265a7a8397d3c8597f0200983b203b36f15a35cde0548ffbcaf4274641c065476c324ca05956c015b172590eab181d8db003db609
393	1	421	\\xbdc3243d5b06f176f505e5cda157fe941c796eac774f5c97c0314c8ed6fa4b957bc47f257e409a38416ff500eec8f5419e7187f6c7a6ee39e117f987eadddf06
394	1	67	\\xd62e3cca27f6610858132cc90cb25bf6398cdb687619edfc59ce1caf801d2ff95d2b50458c181cb46a27708ec40b5ad4647e7fa4ba4144fa1d491335aa3ca70d
395	1	407	\\x58cae00a41ae051b444b83ad44807574b2321eee373c304e6f3c2c9947c0a115335134a726ef04cb2b224ad4597739d171594ba0c6171947a54cf5301a1c120c
396	1	33	\\x4fa097aac72e66e7152499dc757417c6734b56fa7a052af9b3225d8ce46b1c6e84c981f1c08ae1c6b0fb0efe999b066804e14b2b0932dba6d0df4f206d97db0a
397	1	261	\\xc57a2e8502b2564d60d5d3c5f2d2902b3cc3654a061f2b2ad7982bc1362c7e23ab5f6ac95d955d9ffd3eef232064549711b0b20819a945d96554fb4417470f07
398	1	296	\\xdf7ff7775af92992afcfe9692d6c877c6ebb92b12aa158d1a27e0f9b05e6a9f6e6269b80ba4c6dc38d3956f713066889255ab18685ecf69210142435348af80e
399	1	301	\\x8d2cbf8bff48d77d0d471f0256519ca710335efc484fcd8d48a025232f09372ae0b26c106d7fd0a47efe27ed9f1f5673fa12bfe38cc85c2d38271f03318d6300
400	1	321	\\x4d51d446f473e14275e477acc55a6265b17c1a4b12bb3f288175217642a2b92ddbca7d9ecb4cfa871e27eb374c9997f1485e47f1ec55a531c013955eb9c9ff0a
401	1	49	\\x024a2ebfa5642d3043d267ffadc5b4cde09c9104e4f6364c8697a7b458278ffa609fb303aa1b6e6771f66184f0ff82d0a6a3ae96635ffd630711036dc8f90509
402	1	369	\\xb7a368dfae0d3db033e950d254cf2a0114a0f26b8d5118db25523c624a4fe4f8f12b92452a8f7a1725533715c298444e90703ab68fdeaea8892aebf2536d4b04
403	1	191	\\x77385192804ec26396e7d4a36a514fd753fb36dc8998a639efcdc8cbb429e8be8288fad5f9b9c564dc50adb17e4b8587dc25b21bf2bae98b219696047a6b4a0d
404	1	215	\\x8f7606348545fc3a9d31d34a0f75c563f9ade07f8835b48fe6fb7348fac7e63d825289da24cb1eabd68616f07f07fc04ad96e4754dc820053b037ad22c73770f
405	1	113	\\xdf710fe04e529b0e6ab58290a7e7b7827d25b219dabefd46bb370dd0ed5507124412d2b29c24f329339b17945e131b27fdafdb734d28b594b40d6c8465c5d60c
406	1	412	\\xbad930c676f2ca2a1a0872083fffd0054eef8034fb21491337f7f2a20e6f3c05dd433993135c70b4bdd5be4c3ad63e6a2fb6e05eead19fd52d76475882218b0a
407	1	241	\\x4b4a7952823f2b543ec9d87e46046f8416614a99b095e39a97127458b93a77708e160e3ca8208da68392bfdb69babed3cc35ccf1a03d54312c338fd389c91d08
408	1	32	\\xbe1b79e5c541c8ec12bd5ed8286a56cec84d433974144854f992d73dba52be0a95947e860830a02984f32a35e014a2e2cbb5d4aa154d1d4e074ad7920adc3b0a
409	1	264	\\x6df83cb7d384fd745c35035668d59382e4fb3b1469d5d1eb2443b2a3c45ace71c5532532d72618570a34b83c923d5ef22099508fe79b6ce7c7ba19f23f2bb107
410	1	242	\\x3ef9e17d6535e2979a89c7f0ca88c928149085e0cc226bb1732c756443b6070dee0507efd7effc5828e8c6dac4c499f87cc85a66a0c8f4849e85bfc65f08bd0f
411	1	145	\\xff5ea3eb749aea27e582edc66a033de8b3f149283b824366186d413f38c7febeb43d8ce0d98598497767e48adc2a90418c501a188a92110ae5e09c0c655fda0e
412	1	124	\\x36fc2e28137b930d192d92421c285966a0d9ec991cab970987a6404dabca97998500b7674cb4f2f27fd1b3846e3ad35b45821de05c702fc78840032275f6d00b
413	1	364	\\x78f99cfd84867ea0ff43efef48433c4bdd1337ef935ed4f6194d3da31908aadb584e392276ed405810813e6b17e28c4ae51c3335f9951e20adcf876aee577e0a
414	1	182	\\xafcee604b345790296b3c5b12dd42bce328981295aa7705574f934faeee5a21565e7cb162e946c2af241b800e00e653130051904bee914230cf96a38d5f8700d
415	1	62	\\xaa3a7ffcd7af86d8d5d5e01aa44fbd906101e337c2ddd8159af3a6a2e63c7a3826f2e2f5dee14f6c8bf42c648098cec5e26b0c9e34c10ea1a8090ea3420d1807
416	1	406	\\x13596ed5360cfd68c8cf04ab6a210b1cf46e4bd8097eef5f078ddf7a6ec7930d3ed7994cbf41dc90f1b99f7f78e2d711c9e0f20831a722713271f00513873503
417	1	165	\\x239f0ba1997db8e5300f882593196d78f49cf10f4df733cdbb91dc499156989f238be1ae955129002b4b01fb45a30bdbe8ca5cb18a0bc1ad0e188f3f090bea0e
418	1	110	\\x2001554e9f5b9026bff99ef3316eca9cb9af519f2755fb5fbce4f508d9b42377e2c2c5636a409f0fff73e988e020e2d0fc28fac581f331bc0a96a2445d0dd206
419	1	202	\\xa9df4fc3f6c687ac80cfcf592470b47d9427a20617b89aa068a12a36ff95ff3670aa42a97a0a495f2a6ed9fd8037556a40c39e65533816edcd82b41a53fc3d0d
420	1	134	\\x6b638cd1d3a937f5bca1cbcafc4a9fb446fb48929368a8abd61a6a309deb6d4287e98e76fa04debe6adde4bb483f0bc0e16a5d3110e0b0a98a48a29a26c75706
421	1	359	\\xdc1d2e84fd686c7ab362abdd78ab96386133d8927474133df1bc94e09e90d619cc8be61a48bcd1385b9b1e386ef590970cec4a2423a9d8e3504fc92161fa840b
422	1	92	\\xb74fc1fe3ebbee2677f3e79f734840ee0b6e5601948f1845bb081e3cea2ff1fe3b255370bc4ff49ff9e0a7d6e172cde416b189cd797f10554a156fc7eb792b0e
423	1	93	\\x615ed7fc0254297454b8ca96e839d1a8bc0c825e3a39826283ba86cb874c6cc9afc965efa499d05e6a2dc4a02778616207c612a959acfcb608d40537df56fa0f
424	1	297	\\xd3176bf5300ed1f51d5b94bd8dae296fcd8571f0de8a8058a0ff06e20350679c77a0fc9b8cbd7fcccb3d5608fbe01b6b9ea3858a29897ee90a85e7e02f83ea08
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
\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	1638366941000000	1645624541000000	1648043741000000	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	\\xa0d298ebc68805af02cb0f994d48b4c7cf88c9356a9ce46ccd55bee9053fc558462f46d171acb343b405e45d7429ab1a3fcfeef76f4269cfda2a88b656059a0e
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	http://localhost:8081/
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
1	\\x576f2a47a31d4e2ce025ad523688fd4b3b519501ed2679fdb11a7ff6771c20e0	TESTKUDOS Auditor	http://localhost:8083/	t	1638366947000000
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
1	pbkdf2_sha256$260000$p8IvxGXlI3Db1VVTyG7Vyq$2KEQt1stbDu1X3D79yecHZjnbUOEeHfZ+vwBtcUulqY=	\N	f	Bank				f	t	2021-12-01 14:55:41.623585+01
3	pbkdf2_sha256$260000$yF1NiR4UTNIGjkfvG1UDuw$towB/2xL507PX5ghmSpfrXutJL0n5/8E22/8OUXPBmU=	\N	f	blog				f	t	2021-12-01 14:55:41.857362+01
4	pbkdf2_sha256$260000$5R90jy6hupR5cSPfMrKqNL$EWpTMoaNUGDvI0WegMUAZZTY/dowVh2BcBO4pNxypF4=	\N	f	Tor				f	t	2021-12-01 14:55:41.978251+01
5	pbkdf2_sha256$260000$MtJImAJeww98TPE2xhIzpY$m/CMXm56Ce2Y5M/TEzhV6Cl4WIt9+eV0dYWC1po0hWQ=	\N	f	GNUnet				f	t	2021-12-01 14:55:42.097013+01
6	pbkdf2_sha256$260000$qjxl7r3wmzhRqSrh3ACxXZ$wc0OeNX4KMNZyIs8O/H+tvvZw9M+22KrfGrFjKx6Om0=	\N	f	Taler				f	t	2021-12-01 14:55:42.215284+01
7	pbkdf2_sha256$260000$qZG0Px533rLBAARDMM2FxE$/SIsjDFZoDoRol1SjIBXwLlIlme1/buF8rcWergFlWg=	\N	f	FSF				f	t	2021-12-01 14:55:42.333893+01
8	pbkdf2_sha256$260000$L7tS5iidAArRrdm27XbRuI$Ydd/Fsa3PcPyXupJ13qZFRLaLAjDlt4xF2nM5YYvXm4=	\N	f	Tutorial				f	t	2021-12-01 14:55:42.451999+01
9	pbkdf2_sha256$260000$PMTplYqYRP5wkOB4ydaSeM$3+9PRHbh0PdNUUEUbX7Eq96c926u8ydW7aH2xkpSouI=	\N	f	Survey				f	t	2021-12-01 14:55:42.570292+01
10	pbkdf2_sha256$260000$qXqwLgJfIib4ZcV3kDnUxp$eocv9iVMjEDqv4CquggoNyNsrzhury2Hl7YcxQzePYE=	\N	f	42				f	t	2021-12-01 14:55:42.996536+01
11	pbkdf2_sha256$260000$g1Yz4ZYzXZRbR0nQJJWpBi$585+1ZlMuEWE2zGo3g7H1SunHmLLGf8jcgkjM4VpA3M=	\N	f	43				f	t	2021-12-01 14:55:43.409847+01
2	pbkdf2_sha256$260000$rFDsOrNuVuyUpskCM1QazZ$Li+E83r3dEP1ndBw0HVCyDj1soHaGR90MBcyFPizIG0=	\N	f	Exchange				f	t	2021-12-01 14:55:41.739521+01
12	pbkdf2_sha256$260000$AUcLX5ofTYdzstRx8D4O6t$K2pRyhaleeD4FBiyFLVFzn5CM4AWTB2y0kLo6pDWNXA=	\N	f	testuser-kusufpjk				f	t	2021-12-01 14:55:50.894182+01
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
1	92	\\x5c3f2f70de52a95881e5c4ebed1b6c20bd74473c25a1a595d89e0e1924e40184d688b2e0c2d1e96fee291fdbf03600864c44749709105748a2658776bd2d5305
2	364	\\xd64c7af36d9a35591c0d3dc714867abee7a5756f168819c1d188edceb215edaa13c48ef5cdb8e80f87dd1fa0ac9546026d8b5083b0e1c95e7a9f3fcb4a3cde02
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_restrictions, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x008cbcc9c5a4925fed43da4392462d7cec0069a2a94ff61d6c8063356407cd8afc1bd9bc7b2c649f4e81863a9d1e01a12c41c09217dee36ccc8bb6bd32db8923	1	0	\\x000000010000000000800003960cb41dc694644dc0ee6fe64e4ea917bfaa131d6325694d366ad52448d82d10e6c80dea631768534720411770f19eb2a22dfbd77c83c4760db5f6cbf4f18f4d94f9c05a4d083618a720b43d56efd6b7b63b5d7134378e79c30f8ed76b4355ba0321dea88efabccd424f980a183447251fe8c04c9a261f73733ac958864932db010001	\\xdca5b1be97fb9a555a2a8aa318297b9b84cbbb2f4a25ad73b0be52e1e4ff29de2ed344b34f8e9244a571a7bc0181f31d5e4bc81a509adab092310420314d6005	1665569441000000	1666174241000000	1729246241000000	1823854241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x0028b6af29af75fd4d44e981b0ab522189ddeca047cbd282bab7d4b748962fd54541065a3d0d62eef10f761f7f16a6a34bf3c6c662e28a88090aad3969c106a3	1	0	\\x000000010000000000800003e141f513ecd08b032cfdc2983e099276e5e8ec829df5acef61b2cbc600fe39dc9ae6e679cc54459ddbd9b1b38b7c537240e4705f07c5cb14c6a95ff440c97b7e9cec6eab81432286b2b2a040462e4186e48f486260b48977336e8914d638026bba30da28868db34b0579c125765b4155bed260faaa39d5e9ed74969ccdaea679010001	\\x6395b4825e2ee70263fe7167cca5513d5c75476d97cd0b31a820f0918c43c83dc627cd24409586f6c16b6d5b56d41f599c6560a97df00d193f63ed11d32e9301	1652270441000000	1652875241000000	1715947241000000	1810555241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
3	\\x060815dff10c515d55b8845d38eb0eed8de522615a905c15970ec9784e2cd370b02bce72bb3b66b1c692cb5975ac64d02497b3800adfdb4791a68962dfb430fc	1	0	\\x000000010000000000800003c04e2b8e8461d1b432748990830d4318940af7844431267fef9f249852efafb8b2562071f0eabf83d2e18fde4a63bb32c6942129e256ca9ffdc98978a4c7e9b08af4c5a515297d615155381a0dd247ddeeaea6c1092d1776b4377c7d98df55f52fd1a775c0940f80b0d09172b535ae4aa6a30473e682b711e10aecb8878cb98f010001	\\x5a02a7fea4ac1455afe92227344a565706db1f26b3d2bd107b79caa8b6562db1bd4c1a48a7fdfde2c448439e2eba6bd53f656e06fa9994eb4acb7bfa5f569308	1657710941000000	1658315741000000	1721387741000000	1815995741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x0ca4aa776849c4f6c506b34dd5490dcc39fcebca41b1b19aff2ccc8e1e11a1af1c3f0f80f6e88ab50fc1bffbc8b603b2d55e406ded3f730645f6bad140fc0478	1	0	\\x000000010000000000800003b053a1e714ade9a7eb088ec79c18aa06587e5f985babf2d2148e79aad969d46abcc7e5aa9810920d6c98db68482f8ef3d805f75c99b6b7888f7ffb9ad63d99ddfa381b380457e425704b28e83334a5c991ea2b47bbff939ec26ed8feaed3f1b55581895bbdfdc7794cdde1c78987e8530ddfab15d164829f1c1e071c54f11c15010001	\\xcc9c13bda710ba7702d4964ac7b5de6503f3a69f16cc37e330a72f54e51867b88ca0a98e65272cf52a8838716317e2455644b291d90d4b3d8b5032f89452cc04	1664360441000000	1664965241000000	1728037241000000	1822645241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0cf8a5da00817a93fda79e90dff92d5d652a423f08d5f19ebdeb7b455558348854fb0e912f1bc48d11efbd077a509dfd6b79d2e46b748b8b1ddebc520d83c9de	1	0	\\x000000010000000000800003d9acfd05f3d3bc3ea25ad57b5d80eed8334fd440b85e1b99f57f7dd574e208e9cea66ce0162a71d622c23396cfbbd22cdd1abafc98ce8ee1587a8f7134ffbc10218b7f984375b97d67a041fd1f4f007c8a7eec34c570f7c7310cac0566308bf50263676c31eb84c3a2dbde92b17b051a920f81c6bf546a7aaadc8f39176d7c5f010001	\\x6a80924ca82bc097ddee4c0c5821d02223b76e344120b9fa511b778b4001e0efc424170af4d331950835bec214bd05498011b603d00c0b32609a04f5a5f2a900	1653479441000000	1654084241000000	1717156241000000	1811764241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x0e68813a589837f2338ed9b0c8b25131c9e64d3ac86e2c88401699ee2a5811995d138cb5d80a36399f3da600f801cb7f2a1e5a3c46da382e3452d3e7e8556d6a	1	0	\\x000000010000000000800003b5b04be30743ac2b853a592fb4eaf45da64f05b2638b1e856f2a47eba564c1e29a8005527b0606e273e42efa9f30c96fb1d49f4974241bac59ea5599bc55f4fa43a5a98bfdd5e6f6c926253e978bdf072dbf11fbe6a69af9f3d9a36f5ddd94e139177bd0bb824969450d8d139268c4b3eb8ab02df60f79af27c28e61d99db6e3010001	\\x15aa10007b350f5f53d1c1be96eb9bac7c285733995cc0e79914153096df33a671df6898f29def2958655fe6ebaf0d8a79c855ee3bfba7fb3cb7b4c35ae02e0f	1664360441000000	1664965241000000	1728037241000000	1822645241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
7	\\x158c52802f9a182dfcfa305ff9424857856608a4a3b7949439ddc8c3cae4e931cec831f8cb897d877210f7c01c2a712f55511472a5d612b2e9552867f186216e	1	0	\\x000000010000000000800003c1885b4f7a5fa6ae8dc3d8038956ea09a2ea999ccab206a35e34be8ce06daa2b490c8df103b6c50ed384d3ae8872cbf2467c991e41339ea0e2c33f8d72f037f012580b90930d4ba25d432ed36d3e8457f3021dd0d1a498ade519f32f8fe14515b51b1e2ddb7bcd6232da16656aa92cd32f5232dff47b7395ed47f7a30a1d879f010001	\\x48284e90142a31d159b8a1c98c80c6ba6a91573ffd883de3f6c26a1ab1473fef155073cbe7f407b1f3d541b9c6d238afb2d2ca162e9bab1d3e7ef5db26234709	1649852441000000	1650457241000000	1713529241000000	1808137241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x1864804f8da104c6fd3172d66370aaed23127702cef92f3241af429c344f99c26b1622176f1ae63cf2d1a64394fc7d3431383da2aeb67fa4274ecbfd36108889	1	0	\\x000000010000000000800003ca878d485022bd843d8c447fa0201cba02138307a20cde1a3b408528777ca3e15a2f1fa2dd7697112d60721da6514e76d6f9396b09aec27f2fd519b2211d5071fd8144d31518a81532ad7215e194c7737c4ac5ac16dc99a69224a5c6f548eaffc371ea2b2203b3c61be2d463326747b6f31fa77d73eba72082624d8c610d80b3010001	\\x2a1442dc377e0dadb37345d5e4e93d4dc1d1e50b82ea68c615eda9d5fa49b6e273d630d8414b7e811f47e51f7d598aabef434f2b70c08d34456671471baaa808	1655897441000000	1656502241000000	1719574241000000	1814182241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x22f4b06fac57f442f204e897a5b27b5328491d25608907651c753ea9aa44b0baa65314fb46ebd457a5350c114011280970ef76af28c461ea581477a341988933	1	0	\\x000000010000000000800003cd814385afdbc2095f30897c6faa76b5aeb2d1e7e174ebd1b874c9c01617f9e3b0a4a98b29b0f30035b9117df783e34de3223b02840efb962f998a1a227bdbdafa7c7cd5baa9da84e29aef0556ce39df6a79ab8e4222f829af6503571177d6a41b68f61f7663f31ba0eb621a1c12b0edc4b47d14f2088b35f818e6450fc58de3010001	\\xd2999153faca4168b9e7a13909f49b33b9abe5a46012b3095ac16a49f0441d92f0fbd92cebb8da123b3493fa62ae769b618ab76442639b686ac5bf7f6b9fd201	1664964941000000	1665569741000000	1728641741000000	1823249741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
10	\\x25a818f7e3fd43a29870bb2afd4e4f38e73c9f742d76e80654f77386f9af9349994f92e3323ecadb3740010e2c77e9e57925af2af6dc9f856770c2cb14966ece	1	0	\\x000000010000000000800003bbf003282dc6c0e9f8712bcf34b24dfb44339ae8c48a734799f2d1881ac17646e744af9831b8c77e9ed1348a31663f82d86328ab4f0a7de611f4a2e7ae0448177ad40c06984d09e21b483be7f005f4622ddfa2bcd06cc7eb50b261230c5cf31b89b59e406f834360ab2bab8e1c23f88699013ee561c99931a0ebf44bc0e451c3010001	\\x6d18633c34e23a77ad822bbed1d88a3935723742e84ab75619abdfe43a5ea07e89988f19cb59f54f3a62f147c3e2d02dd69020ce7fb4f61ad99dc5123ddaf20e	1663151441000000	1663756241000000	1726828241000000	1821436241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x2b244f36fb40aa1d05caa06a14468b3748d102711b850e6de7d27558409448d5318b70bb87ded1eb2361ca4513e10e33fdc0054d5de1bd1e3afd3c528916a80e	1	0	\\x000000010000000000800003b8cd2f498b452fecc223a26a75dd42a9ae924e373283b67c811812de4d5ee2269be49e3ba220aa5c24a8bfb10717762333956dd82755609f8ff06246417fd42bbb37aa83dbb39c513e88e438123af729f23035c9ec7af637897e9e9a76f571ecc4024496b868a2f1ac100afd0c64edac4fa449a16bbcef89ab502527ae642dfb010001	\\x147ac8f69f06c610b7c7f7b5e4e7cd4d920637c6d83fa1f290a4c95b93b19fe96e9ea77dbbeabd0a568ffb39ccc4a468b6eee6808256d7acb4600bb3b4f15703	1655292941000000	1655897741000000	1718969741000000	1813577741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x2b58974c5cfe40d5b3fe67da01ab7bd5a35672c7385eb37d58a1e50afb03eca8a0d581aa801c9a42f29d8f78b55f0a13a0b8330dd5e8f2dda4cd5b42fcd98d70	1	0	\\x000000010000000000800003c493d4fb070eb8b38b7a492cae15f9aeff0da5170c3c4488a859b7d03cd235c8447a610b04210c92aa3dd7da6efdf510b1bbb7873ef6554f42dfef31b5aa7ae117e964f54af99b32aec19f229d5641098d801d32baf10602d728691ea571f5482d8bc3d7db90a15e52bdc97436fbcd641ba5b24f33cf417a04e948ba7783123b010001	\\xd637b6460f29c42e4b7932d60f9e010d913991e1820093602e4fa510c2b4389cd20cff41ab620ec7db1792083a6b0ab536a7d5ef1130332cba774af26a9ee30c	1656501941000000	1657106741000000	1720178741000000	1814786741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x2cc0a7ebbf1283573f1276dc51060232509746871f430e4ad8d15a77cdd5e1ea049006076da5e20d767f062fb66d3f53d958c9f741fda39354a6e29fa851734e	1	0	\\x000000010000000000800003d7f4253c3aa856dbf85a72ae4e2151f106bcaebd02276e949a12d3d3ee0aec3f3790c8c3b1600cadd76d0e311b89e297d4aaad6d41610e73a1cfa27c7cc1ac53f83503ec09ad62d2ea0b13878167b2489ffdce755e2f2c6e13cb1e16b755b90cc2d3a95e491b4e9cc9c604b09319ebac0573999ce1c99c3b5a081e0f17bcf8b9010001	\\xfc078657d1b265359d7af983682c30e96ff50eb4a8f3ca3739ef904d1d1af43f56b8fcf3248a2848faf264318bcfa3a2b1abbfbd59c29585e88d5a4e795d9e04	1658315441000000	1658920241000000	1721992241000000	1816600241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x2d707885494de727120df12599e68d211ad1573e92a40bb1b34d35e931681301b1faaf33612a652ec14891b9d7a4d25c6be3f69ce9f43441c7a4f619da46f43c	1	0	\\x000000010000000000800003ac6896c2e714e60795e19e88586f3858af62140e6e27ff90ea14cd17add2fb614a6f4d13fd49cc2554b13a3308a14dc6ad80aa54d1a47c62e47a4c79748940e5eab3a76841a5eeacbbc6d106348d139607b34afc1567dff2ac6a7f8cd472f52a8193b7098056bae5a52a0995883a6d4f1a8f1c079f1f824cf6af652b052924f9010001	\\xa04ccd78a0bb8918a65cf4fbb4fc9cdb7b24b6790365a7f2a885a4afee47463ec3579ab2ae0efdea4570eac10af008ecfab60d8106aed6d2979609d6b313c50c	1662546941000000	1663151741000000	1726223741000000	1820831741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
15	\\x3348c1b38092acd120ba4246bb378f969a1322a1542363daaddeabf5c9c72009e73a359d5b0d362facac9d4eb4f803fa7fea66c0559e5e6b8c88ec5bcb625c6b	1	0	\\x000000010000000000800003aa094b7eeef18ab5d77b90a1f530065f0a04ea452c88967756946d1582f432a3220e8236e24ad941073a044171d44ae809eaf4b3ce1f8201017132357cfcdbc09e2422af64dcfc702d2e87e44c22553a861984d59a590b833dcf7f104fb7703fd39b05b1718ca50ed2c2a5b150f793d79b9b7608a16860a3fdb860122a246cd1010001	\\x6940ff7e5cd8dc0b9f7313191511bb26833b406ea2e9fbfb1925490d10218e76b00bc4df6e2ea7b87317d457ae3387e9d3b5f7c98f7709ee8806b8901e630a06	1650456941000000	1651061741000000	1714133741000000	1808741741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x355052a2634e183b1cac1cad421b3596e509dcfe5c6b6c3a4ec51231d96e3a35a35c94b35a78497404cf4c0bd678c6bc705f40b785cb5e41b6bb98fe25daa3c2	1	0	\\x000000010000000000800003e3d8491a92800d7de96389482fc1b91a13ef70b1e85c415c09d522c6b33aa9f78e0359e41394c6c84b0f9f7ebb43c6a22806c79968ee1891ee730e52481e04a48f1320f547224281dfafc118e1354d985a15fcdfd1242b40f942dfa5949a4279c189a2f598d30a68daa0e03fafafff37139cb9906bb618fe582b55f5c1732a3d010001	\\x4bdb5e5e8b714b440b3b67225b8dc8facf60dad8e818936d6acdc68a0ae462a4b346bf7af5f47b2610834ada16e1a9ee391b12d8f84c387cd8ec7dcb6922c70d	1659524441000000	1660129241000000	1723201241000000	1817809241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x3a3867177bfc3b2ccbb5923183e5fbebe0bde8643542e1415f604303ebe928bdfde33ef3cdd0f4c821bec2982b775bf3b9e0e83be4562e092790c5698b149a26	1	0	\\x000000010000000000800003eccbba620fb1a4dc321a421ba19bf97b036dc0f7fc894a9797b758238dadbe550781f230f8e008f1995b22ba37744837eb7274c8f077479ff29db6dd8c0f01d3e92935fbf1c42c0cfac17a11fd45cfa539a854cb66f8a8870a13c790a4f6082ca90192ab5f73b75f901a0f4ba0c7e5c581dcdf63f54ec3befb580b0b0fbf7285010001	\\xc96af5302a0b98e43c8469ff824103febad36ffbe43366e66e9362abb7c57a9dc481d065fc32cc273624d35832e967ad8fd58c668a0ccd3c71dd62c9d4fc2900	1645620941000000	1646225741000000	1709297741000000	1803905741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x3be0e0587e5a2315f379be20bfb71e7c2902f8658b3638f50daf6ead8a79b4613a25f58297633ecf68973d6a4ef59774dadf4def277c349f7b3bb5163c257a03	1	0	\\x000000010000000000800003cbe0e6188f63267863b583ac144f7d5fff150c922c201c9d69f79920a22531b2d7540ca918363cb43d088ede89f5fcda74e080bb59c0d0310c105f78350cd42e5a9cd0c5f6858c759dec6a208f09d41c6329f2b72d99e9a2c3e9ea6754ce5be5be082b395a9a4fdaa3894edbb6f31b8d24b16d599907376c14847ecdb4767973010001	\\x31671c8a0100ecc30fbb99d8ec402b1d60460926b006f61c018e98e081a3ba2a50ade5c4ca154f27a50c84ec739bd6c5cac1674697b8b3a6dc5619bf39325f06	1642598441000000	1643203241000000	1706275241000000	1800883241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x3eb87cf47936920f014a294d6c82648cfa444db72360a558a8c5d91fa79aed81cf747f8a5551176526379944ed0badd69f3aafaf4c0f8b2f127bd33502f9b618	1	0	\\x000000010000000000800003a12aa908fa29f53f08612d3b83ab904a678eace544b298100dcd73c1dd498f42513b36a802affd61ec23ebe625b911b7d381ab14f410c9750c4199ae8859963a9d852f8b325e8f44da1a510648d1efd1380250921d752bfc35852a91f4a66e8048cce2492024343260275d6fd17be54dca85a816592b0f92d54e7f641a016339010001	\\x0e9c2fa29c824ec4f703d82ca2c9175eb93480763845dd73b2fdc305b66b9013fed09f247c5f63df57fd0cb27035d032b4a31a0c1975a13391d893d37af3a708	1654688441000000	1655293241000000	1718365241000000	1812973241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x3e88a864e4b434cc826dc9bcc4cb7738a3b71011d9e68f4ef2a3c27c45319e159d5ca106f3bd6c69944987e825e3abbe63ad35c38cf096183ad3822a4f47cbf8	1	0	\\x000000010000000000800003a3fbf86a6a91fca287172f9a909c288856fadfddfd1612f28835eac4962e8ca6ab6eb72f59edded3dadc683a3df04645384a79e8fad3189126ff3b0687e22fa2b157e2c9287199437fc884c8593d13d51bcabf44397ea8d7811550b900cb4b0255a3e668b60a9a25f4c7f66ef65ff8060ab7cf2552726898f70cdc7112b610fd010001	\\xd58d6b5fdd6a785f24271aaced7b39a6d987d810cce878d2c6d0ab9136b2774f09f693f0c05c625acce138a4f690034e9d825b004b4401a24307dfefecf0dc00	1640784941000000	1641389741000000	1704461741000000	1799069741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x453cfbd45720cff7741a38f395ce6507dd4da39adc6339d63c0e038ed682739d648461a535108f6ed205822cb48a3316d5fd2731744abb42dec72251433879b6	1	0	\\x000000010000000000800003b7e57fb7cef55d6ea450ff084f5471fe104035fb54fb53fa2c22837204b13cd1b7707f6ffcecbfb369f6d77de6a424fbbc87b429cfa7546ed82bd8a22c507756707ae71c7b5956ca66134ec602731ca6b595194946ad13ec0a36ea77e488d401d9d32fb303065d200700017f165aa88842b5a589aa547699f4dd55939459f6df010001	\\x2e883ea27e2a5a110d16bd5a374e2cf45b58652c6620f2f95e62d7fa6e65849a524ccdd4160afe6698f33d517e9666f8aff880593b6b5abcabb51f8ddf4ecd04	1652270441000000	1652875241000000	1715947241000000	1810555241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x492c2e712aad7397ee91bf027969a9aefcab74f4f1d3d7e23feef1740c207eda78f3efe86e4dac623168ad78261bf0b482d87b1dd93eb188c35a04c6d6e97268	1	0	\\x000000010000000000800003e0b660ca4c39afba0e78c567b598d922ec7e1a71bdb5bbbec58d0c91c7fd8e4a50daf46073c45f4219ce85dc1b57a992b91d56b86b3c0ec036013fac5471b991fe4b450713d8eef6ea92e545bcfaef027e6f2254aa4954a18d2fe8404380aa06f45082e218232e64cebe81df4919993e5b31c129b27a2dbc93651d2458387df5010001	\\x6c945b12bc15f8f11ddfa256b256d34bec9b9fb6abd473f0f5cecf75a351ef7ab74f1007f8a07dd1ffe020d91afc2fe1d3d809a5e8c8f76794e91cdc91d4c106	1661337941000000	1661942741000000	1725014741000000	1819622741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x4ae0cd81466eb66bd9048d2d828fd27be9cfe576467b347894a74ac210edf9484dbd0cb03fc904133f3b71fb77393f3fb889d62c822fa3d80c13e519fc4644cb	1	0	\\x000000010000000000800003eda4b921eabe106d7edf2413dac25c1113602a6fd9695a37072adb90c3313da18b06f186c780793cb6266ebb91a88a212c5c86f461e4831c318549e3b6b297a50f633611825d0e99ed7aeac41f465dcc21c8434535e1e1b555ac06dbece223259a6acadcd9221a77fa1153f3d2fa9e1fc1bb2be1a6a3df32d1146dd51ed7c495010001	\\x0dc4ddd1371a5c97b735b3b772b5e2fea09a46f44d72b70f563c104d2cc239fffea462ea2cfb4ef439eba681546c757b9fac242c870abcce1811417f818f2b0c	1661337941000000	1661942741000000	1725014741000000	1819622741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x4d285a82f4b607bb9b4d2dcf0e8e2c65a922755f4638db2075677744726b389903848e97682f655ce18bb5d84809d3aa6ce5a142e2f4047014ae6f9230c6261d	1	0	\\x000000010000000000800003ca6dd5cbc15814c184db7d5c5ad251428cb27c4d672438698be8230c7a71fba1309053a5086547e0588ce9b9b74b5eafd1dc7a30706dd5a57f60fcf61a28d34d79d48414eb00bd4d9de3fc6369245569456031b4e9deb74770ec604b8658cf3b1d9136fa9d4292a3b3accf3428d367ff08076612b6fc7f8f6595d2bff5f51d9f010001	\\x5fc953f71cd1d04517327edefc1acba4d31501fee77548a06e62ebf561258a2fcc3796b7fa94af354272d26ade8ef719dbd09071c363715c00ea365f281d5703	1646225441000000	1646830241000000	1709902241000000	1804510241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x55fcbf861a8ecffcc132cf0de5f1985f158538e317bc2f1b611557c6ba2c605ec69ea2af3cb9519b1b5164c2e6fc8a29a92cc0e4270ec27034478d8b526b6527	1	0	\\x000000010000000000800003e19e32d927ad863c6c4b5c3edf4958a13cdc4f2370ab35a1182be7936a195a2f52b18bd599dd8d95a50c68915fab6ef0cff3f1a786e24f96c1f88fc29698b3d51f834b3340f153fb90c009237630087023d493ab4abbee516533326b70857d20bca240b69d10ff9dcc0cae69e5fc433f052637ed21d51066193085d77b274a0d010001	\\x38a5ac330f838506b0481163b0a86c584527122767d41bdde672c0048a553f9e48d3cf20026b328a0bbfbef3e345919649383d60db2123ead36bc9b384ba5c0e	1648643441000000	1649248241000000	1712320241000000	1806928241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x59c484a4dd917abc013f52a72ebfbdc0e1dc5b3ab19f7b0236c2ae7f136c679f3bf641ccd3725704aa502c2ddff40c254d62945d6e678971014017cb719bd073	1	0	\\x00000001000000000080000396e9eb80564d7eb6e6f8339df16d98b36647d02d7ca4f202edb1b4a212a46f51d534c40396ee06610601476085594be9dadcaef436d916022d8a37ccbfc08c079b43313e056829d01b162f94e4c73d0f4347511ede188d6f6fe1da847833ad69dae2665ae47b777429de4a86f7e412af30a5bc586aeaa14da5758458a2405599010001	\\x13c6187404265caca59a9d232c1f3d415bbb4d48390b6ed35fbaf9fd1f8358cc01b3ccb82ac780f85a8cdf60cc1776139df1a5fe866f30f5a6a802e4ed3a7704	1650456941000000	1651061741000000	1714133741000000	1808741741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
27	\\x5bf8a23a6eb3692483f6f62c050b0c3c0a527f95842336cfb8a564f88cad293d154d3f1c955fa8409d40d97cdb58ba0402dfc334fe50a6f9c7a2673223098e4d	1	0	\\x000000010000000000800003c24d2e06d34700ee5ee004547b42a26ca98de696b728d74e94a8aa2da0f5b7820b18d3d37503941599b9db99972886a37c6509c12126c4316a4e11c6d3ad4bb74d4ae0a2d5b1901f611d92649311b30fc90fcddbd9c997b2e0dfcd328297d8454496e6bf71f72a10f31d3f1d3769890f6dbaac336b5adba3971632364f5a338f010001	\\x58b2f43132a0836e3288664347e1380f151b90d63739cc92f598939aa86d0fc9d5481e351aef27481337b7c45ee34f4cc7f3c47f71c30527af750ce274257f0d	1657106441000000	1657711241000000	1720783241000000	1815391241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x5ce8c60eec96946da0f599b2035ac2e6de4022a64a4c646dead1298e3d5e7e88b751ce6e8c5dd958cef37284a414e6666b163d3f995969fb14a3bf0ab81dbd95	1	0	\\x000000010000000000800003b134e593a0d1815e3a290a03887ca7202e3eb15fe401725784a24feabe09d03daf8e3a26af561737acd6554c5cd13a16c9bdf0dc9ff5ae8c46204c57a1e1cd74a038eb9b43c5b54d271375f5ad719478be3b96349ad57868e3ae913e339fcd854df19ee051297e56b2ebf49469ddc0aa34fafce5ed64d37fbf021521e5e4f101010001	\\xbd937ca74bdb60ef91a0c7d0fcf9296d2a698548e9f41c5c28f7a096064167f8348ccd94dc91d767d41676507fd6b63afcf46ff4a6e9616bdf5a833f4e189808	1665569441000000	1666174241000000	1729246241000000	1823854241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x6938027d964285ffbb11d7e508d548b4f7639bc0cc09f11d54dcd11927fb8076ac64b12e831603163f2e807aeca1fca639b075aacf4b13e63c0d2fd1e75c2c48	1	0	\\x000000010000000000800003c93c0f6b391c602b63f6f27f9e3776c701ed6ca2779824ae47bd27cbe2722b4e715ed8d021d3389a429a40f3786ffc39b99ab1331632d8b7c34848bf0a3dc39d99760f91656b465e6aafb7734ab9275f1d3f5cb5b906e384bf78f0bfbb76c3078f445c1416692429c906f67a33c12073992c76235de49ecc93754dc9767df151010001	\\xdd87df2a164ba6dc8babdd59bcb181b793b105cae95f052eaff3d46c196879d278a017cd3737fdf0a6ee1bda7dfd144ca11d3eb9b13980d8b5b557392da94b03	1666778441000000	1667383241000000	1730455241000000	1825063241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x6c7c3c2be597fbc9d1a89502bd898b59f6cb57f38b20056cb348fe9e74bf6209f63404b08d46904371b2b0ae0c70807c59b71263c1bd2dbcdf14bf4149bf6525	1	0	\\x000000010000000000800003b967d59e5c86a78451782cff026b59e8c5d43c8f424460b6fb9c10f1942a0ea13c101c3b402dd119f3d615b7ee078ff640fe0eb279926f116db1f62978bf63cc4fa43a4129578dea467851e6cb1f4458e356296b05e9864200f786f94cdef47d9f906cb50b14caa26c3a59ee794e1b9127dd7a5bc1f0c8b9d56e7aec46158a47010001	\\x5640b16cdd600f69ea53de9cd25cd550a75c01afaa9fde0b05398a8d00140ac5baa6d4164168c3b6b9cd5274783fd9053a07e901ee6847e5b15c8f8f699b1c0d	1660128941000000	1660733741000000	1723805741000000	1818413741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x6c08ab47d6da166031e8543c8da4e2d1d0eadf4f185723097037b948b2f020dd5cbb6a51a0b34d72b6b6652e922ca51f8227942cbf6cf50310ed045df0750f97	1	0	\\x000000010000000000800003ca2c43c5206e166ec390da34ff7dde0010e128ea714cf5d1ec358dbb13c7703847c9b7470bd07b41f4a117486917c78ba52ece4d6d6e7c61400d4950e22e22b815c968cef6e27729fc11b26d3e5c062ec119b4e4c3ef182eb33e15f2ffbde5e81a6953275b5ab01661cf23a14ba5f460c0e7f453a8be767124637455f429476f010001	\\x4e23c53039c4632a93da168d6164d7fb75547b7d60378a16d6b3f6165bb799df20c2a1203153c26a5191d5c1bc3e5d1c20e8a5859c63a13c5acd5527f26c250d	1652874941000000	1653479741000000	1716551741000000	1811159741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x6e448fdf0cc77359cf07cb7beb7519cd351cc611cdbfb508e638945d1874747f6885a228c590b9734c6076b9d8341df23aedd1af30c7e8f5db34d476939eae2d	1	0	\\x000000010000000000800003e753f17b95b29e75e22ac7226273cf17b0c1a08510724d95e166dde43ce998b7d3132bafdf6f15c80c4655dc6a7ee8c1bbd18a39eca9c52110db2ee82a2af323fbd0a7b14397e8dfa94151c4a760e5b48f71730c299bb3245a0fc26e9edf309f36873e5e82c770d772b393232c769fc0f465f1bed9d348893c9c4e9b0e8b7293010001	\\x8310e74a27b589f463b655ae3dca708abce551507f206b21ba695486598f73e17ed87fbece01f4a3fa4e7ca040051a93d5a863362a8a17b0c4f72ce2434bd70f	1639575941000000	1640180741000000	1703252741000000	1797860741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x74ec4db899f9a3ad49fb07efff1856f8ac2fc0735cdd4f95430646afa30a6603bc25e138ec2d9b7ba6e0f79daac95f861f9a564aefd1eeeadc28202db1c20b7d	1	0	\\x000000010000000000800003cb8983afe1a838badcd0fe84d886f57c20e32d1e40a0a6a684a960b64542b310ff38546c23c31a89c3ea790fdba8d063cbfb4a86d97651281695f9eee9560581af59b14cfa21eaec6c74c9b0f6149100bb1cae638afbecb824a45589f046a3ba056677c103fde11cecd0ab4b51fbdd3db1f485470b026451e4e8bec0c8705b1f010001	\\x863dd1cd86c3e7328b13b193199e7dea729b1e9fc359d8db29313f374dd35b01afdc631bd5527b1b856af0265bb760bab3526f711ac2cbf3081327ecc412a901	1640180441000000	1640785241000000	1703857241000000	1798465241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
34	\\x743cec993f470178225a4f1a34fca846c3de1ef848b77b8c18eba54686fcb1821a24548017c121dd3d8d8db3fb876584cd23b719148ddf395e27acb4dd091a78	1	0	\\x000000010000000000800003c80c06f75c29e20e0541039772f49a9646ba0b9721348350491a573494a0cb90ed386200f00ba589db8afe3ac97c6ff75c875091918a7f3d0fc3eb18957f58d3bf1962f0923ec045050847937598136e5a291afecf8b28c912eee98f917a736f96cd318a3883ce3de5fca42636995880538bd1173f375b3666084ec081846319010001	\\xc4da47eed5c7e42513c600f243d560da41cd3053fea8d6975404a85885d11000a3ed5592f6de9186404ab93b91f346507c1e35ee9c61fb8ce75c0c403f1ad30d	1654688441000000	1655293241000000	1718365241000000	1812973241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
35	\\x762cf36460d5a5c8e3318051f46e8c51c584d77860bdb1becb40a8b457b76e6878b29fd64056f130301ded15c6d27cad4bcc4e494d7c9fada701d4e15773552f	1	0	\\x000000010000000000800003b3c07c9dbb246d629d5175dbcbd57dd1f1c5369fe173b1c9a1b3a9a0df785176b8d4b46f519206fc9533ef509590d5c0593c778206978adef671a64dc8706b31e4145fc8af474b603aac78546b261fe7f97175cf4e7a874011fc8494fe166fbd8a2d685c00dbd62b00f395f10f6638858062323781f06a45abc8bb7205c7cea5010001	\\x4ae6b77e56a2f1dcd222a8d971751e01e39cc50eb344ed21dea51f5b9d343d9055d816df807def884234a6cdc97f1d4e504419c569d3fa82a8f6273959150002	1668591941000000	1669196741000000	1732268741000000	1826876741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x77e0d0939c7a488af03ef8127203b312eee755e90383e4bd45356153f1d8200f24a37e3b0315fe9f2f1dde2a89d668050fa791e8cd7b11ca4b850e9f60c87059	1	0	\\x000000010000000000800003c061573f2e6e5d5197a18d3aed75e82e47dd6c7df39fd6cc4d823e5ec70480069c316b1c40841840136cca95f5f196cb3bc79ee9bda5bb505238a78629811afc4df022f6935ee941ce00ade826727bdeebda831de90ba6df9d511ce82a7f418604001b0c1cbea7f47f06576b4d15cfcafa7ce5ccd61347ffc53f620d60e37fd7010001	\\xc47aa90dce4677f67c5d8c8fcece183e325efd947e4ad85562e961a998686911605de5610bc0073f938563c50149b11f5526a573f48feb25fe3d64270d1c5101	1641993941000000	1642598741000000	1705670741000000	1800278741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x7adccff69113f344e2eb53b32bdece9b53818ee7d123e2a7f37c15b2fdbebbf5a8ec1d4b146480589763b33f850d786b6c5a17a8ba47d06f9259081cf8aa61f6	1	0	\\x000000010000000000800003fc4f41a679f34621374d045d982b7534169005aedf5068b1d034c0eb343c1af1f83b606afe10d863e8daa7ded10b146bff3f7dd0f24096b2fea7725f504b894890df715b069d334f7ab249f968334914fa56ed3718e6866431d4490fe23b30c23f8e8d1494133f20959fa73c2a00c59f1046816d0e143ece0bd4748e83b97d7b010001	\\xae7dc72b050620e76357c927c829d41db70a653dbc49180032b5bdd8a07b09d8698c43f968927f9076db5211d723abbc783a9ec670e29c0ce120f57a35b30702	1669196441000000	1669801241000000	1732873241000000	1827481241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x7d206f16f106085347a449c63e6bc71842090a6384b3eae506cedf91db7bb6971ce881157b7fdfc0460d66ed832b1ae9ddf2aa4bd4fb057a60eddf5b4af1838b	1	0	\\x000000010000000000800003d61c1fe72d11e1889044d71c87f0abdeb937ed16e02ca19ddf1e8a0de20a9f3beb9f989a985f511942bae6a921469d4d79e2030f8b3b509e306a032c08e940ac3036a4dbfef1298895f16329306528f5f810712e83574b1a3d54fe14fc42cc75fa245316d2ca1b07ffa3902ba5b4ab78fd2b2a459363671fc219fc39084e5613010001	\\xdce82a42ed0f6a5981c1ba2a9ec3894abeb8c92fa216050f4750724edb412db4616815ab6cdec554196e2e3c18d8905d3ffa30e5d456b7f5a85473ae737bc805	1661942441000000	1662547241000000	1725619241000000	1820227241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x7dec919415e7f6730fd2b2ebe61f38dd1d026176486feea65320f0d9efb8d2457e86668456875fb18a1d643fb86b40ee840dbcdd006be40d824ca44fa2a00236	1	0	\\x000000010000000000800003c6a5398d67b49a30c32f4473dacb94af3255171c7d15af2516ff367f0c15a2bb996f126d8f8b2f7ac96929821ecf3f98de71eb79c2245364238ef57b895fcd992655ac5b4aeab502646bde7caa9c36e1c908c59096cfd2b647b74cbbe9d0cf0fb34e5c00264a4ca0c6688e8baeeec64a11a5396c5e77df3d9ad64782d08695d5010001	\\x50b0a67135d6c4f73ceb501b5f4225ac7886f57727556f92de7c5dc18cb0083785d03c255b6bc443357950829031148fbc8cdb6980a886848776f17f8ebfe800	1649852441000000	1650457241000000	1713529241000000	1808137241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x7e84c4be615df09e1219535ed04a1f4b0a4a43a6d6948ed884b867553b010e7a984f27019ac617fd4d0973fcfa20aee28f83453ab12fbf4458303d78833f11cb	1	0	\\x000000010000000000800003e3d855987aa741ec0f137764328eddcd5f881aace4113f276eb3539c37b387b02efc18dee54b8928a14b30e9b2e38b08cb6faf55b52e23490d39e44a5db626f60934e637f15206be7d0a525719351e98b360759a3837f398414c3fcac0a62cfb2be7645fe7cb62a69a735e8903678dd82eaa311e0f340ad30a30c3e4e5d63a0d010001	\\xa6e4ffb2866f5a3ad71f456f03d00db1e0272602e70daeb56a3c531c5cd387867796b1c17811c993adb6dff8d49118ea46e5a275b9c681d9d80a14255ab78b08	1647434441000000	1648039241000000	1711111241000000	1805719241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x82a8810e909a1a2d3d402ed8bf4bdbdf8d4b506ec293d078b3d8080bb27ba641cb1299615d93450e94b1c83e6b44429b88042d73959d641f2238161421a6b08c	1	0	\\x000000010000000000800003c8bfab8dcfe955857be5c70df88a17b33b4b9c99b89ddee91d3ccae78a345ccc6487db6d8403d68a149eba698e4c916b486aad5b703a41cdb4dac2f4db3ecfcd51a7412f40a46d1a10c24038cee373e19008d0c34961dc9e059c60c3ade22f2d036fa8b9121fae64d16c6f43f693f501b26221c999b687c4352837923e6cabeb010001	\\x61cfd17fb69474457af84cfbb2e3f5a0b947bbe21ce3f7bc7243fe1357fb89dda67bc29d438191d424d542494332696e1e242b58ee9e45d9d92b6339363a1a03	1650456941000000	1651061741000000	1714133741000000	1808741741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
42	\\x84c8175599e70870f7bc0c8660f88b6ec6e5018889a57602b2e54f28af5499ebaf7848fecc94952d93b852a03f04c5324144c5b3f0f0588f6a5a44582ab31cbf	1	0	\\x000000010000000000800003d18b1a2de9c6071ba6a9ecbd97096209f1d108d437935d59949f49109f344a80cdc1028a4ab2e8e18cf1e620bdf0a796be146147e42530db00ee6b5c490c44938861406cbcf6f7a1097d850cca72c0b2c6be2666d5b1be2b80d3c0dd795353b0f0381be6bc3b9752aa4f3dad19e2b651bbaeb99eca690a4acdb9597ba8820af9010001	\\xc936e0e8de0df0b939eb7e05e4dbd6cb9747f21b38783ebb20df3ea1ff765b72552a5324f9e096662f1c58e302355858fdc85df2c0e08c5b68e1139233c9d800	1647434441000000	1648039241000000	1711111241000000	1805719241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x8648bcd680f742a967333c682e83630ca25f69bad1ea513c5e08130006eb74b1b7ecc551b6d033757f09aa56c390821a7bebdfa273702cef28ecd5d2acc57784	1	0	\\x000000010000000000800003b181b90ecdcc4c4bb8613a3784616e916b38665dbe38de69220a5ac1850e7c031bc518b2ffa89adaab797b57c53bb6f840dcbe89d7bf6f1fd399e3666e007f012927202006d9bdccafdacf72d5d39f6b2fd5128249da3503b79d3ef568a643ab005ad3a44b11f65d19ad091c78ab6d8917abed104f9f0d2a22f5f85f3516f05b010001	\\x31f39216476e7f6fde6cc7bef58324366dcd36915b2fac8143ae33f2195b8a5e3c399f011afcf1d556494ae69b61f2c0a8f26174d52c714b8bb97fbcb1363506	1657106441000000	1657711241000000	1720783241000000	1815391241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x89f4827e986f50832b7ad1470859d12c5a08944d4988a7a08d1a34aa6532e3955ddf84a50cda8be4ed0e09fe9278ff9377c058710c0f5869c3bc039ff70b876c	1	0	\\x000000010000000000800003da2473e71e6dd094174b3f33d956082f02eca9943effe92c706e3812831e73ea431d94b8c9df571d3926fb7692e2237d37b8da0b08f1f589cb991c3449c1dee40fe9de9b84a22a67805fd91e9b8f4d0e5af267709bef5aced2fc0fba0f1591a4f68ccf728f865bfbd9d27fd4cd4e6c686becfee568dc588fa1a7ed1ac8290f49010001	\\x8bdab262bd0e22f27d3285e016b77f7dc2da270a60fd2b333bc7af7401b9d225501bec82112a7a84d373b6fec9746dbe455f047d8fb9c351f12dbe57b6b21b09	1668591941000000	1669196741000000	1732268741000000	1826876741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x8a98a94ee1a6d0681c20b365fc5c26da75c22747c60fc8acbb7a64729503a1596f81ac6715ac5f49e5849fed68da3edd983a05d48b74e47fcf5d351bd9255cc4	1	0	\\x000000010000000000800003b8cc76c9774633763b6df10e364531b1863eccac02a9e59472fe8b13e493b93723f0d6244684daaf9628191abf9236e7fcf2f65cc79d6275fced1e9fde606d516e01abca4145838f55cb4be0b655929e91db1742991a1236509a8b64805b56a3e0d165e045194a46b3c536de0c2a96c18548adb3237766d7868470ea81d1fb4f010001	\\xbf296b5fd9dda3f431ed33de55d38056bee2517983e93bef05ad783c63f1dfb0a932b40964ae5c3242511d14608b693f1f3bf1999f30ea9549b6b68de5b8100b	1669800941000000	1670405741000000	1733477741000000	1828085741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x92047d45c8ce22628feb77925d6133a55f7e8488c89634692b8ea0068cfc2a368c3fc2ca0e9ea364e227efda13aff7f910ee98fe7ff6dcdb7be49108708a17b8	1	0	\\x000000010000000000800003e30b3987cd8ac3efafdc36349d2bdd5208c685fa904384a9b76449550e87a158cf78ff6d2977945d39cac0bb233fed351571724f75a65cdec9a014d9dbdcfb6b972011fc0b3cd036bf05385da9537e54efe3910275dbb60a1720e5314f1aa323e6fc63a3321c186adcace9b3cccdceb078cdd49259c0b8dff4b8ba0efa9c63e1010001	\\xb767abb1560b481a35a1fbc8aa529e7f6351aa9a9abcb1c3ff74d19bccd38200de47669f72a8465cab7039e696896e8eece2b8951a63940cb95f830fb30c9f09	1663755941000000	1664360741000000	1727432741000000	1822040741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x925cb1685dcaf286f33fb8196f46470d89e4544a5eff4c0578c78bab9608a45cc322c894932023c234343cf520fc19f25dbfde539d9c789931bc3128a091f020	1	0	\\x0000000100000000008000039a44fbd9161dc8dd422f0b44d4cb9dcc41475c8de46428106b69405b92b2fc044d84b3fef4991d6a182148ed3211839ab6cd61a9e63971b5915dfbcddadaf1868f2e5db12420a13dc8634aabffe0451674c0600a0187abb7c32180993214ebfccd48cdcb48f8b5b4c34bf966a196e140b30be13168706bb88afc95dc6802a069010001	\\xc4a3e0a4c678feec3f6adbb962582016da07f0b52354a609adc7b207c528290ba5f57f0d5b3a3a5c5ef84f339db67ef47c754944e9a8877312e6d18aba1b0102	1661337941000000	1661942741000000	1725014741000000	1819622741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x96302c24a60c2de740c6c1d6beb7919636024e7c32322fae9eee711de281bae0c61dcc0b0a66c1ea68c416084be0027395291a87e60a017f1640a4e0ee065f25	1	0	\\x000000010000000000800003c73a33bf7b9857f588386691d1fe34c1678986f803f41060bcae1be6857eb163dad4170d8476566859f8c2ff08bb57486d6cc116450458c6e9f50af91e9afe5081e6421d5faa8b5ada5b4ae533d188aa05cb29e719d006e48bea79b6a616cd95cfdc7c5ec859e6b087864cf1e4aadbed4eefffd054718e4aee775f4311879fa7010001	\\xb933fc22cd9d453c0de25e447ff63838f465a5ddc8791cf688a6dbdcc32bfd397a0c9bba3da9e14b5cc0e9920591349940b7a21e5bf46e8d0e43ed0527d08b00	1666778441000000	1667383241000000	1730455241000000	1825063241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x969ca7d14d0a765155605dfb43dfdd95aa9cdae7996f02ca29a0f62017bcddca28509394763d46df5b97b887d0a6aeeb10f27eb5590d2d14a8ea38e324638aa5	1	0	\\x000000010000000000800003abd1aec87afb80631494b521d5d7c5e618a66442fa1f871cc16e6cc4f4c4cad06817d7b43bd86524078d832f5de38fe4f426b498b569676923de8d0cb23b68d9653861a2715de240a720a50fb2920f0e30b2b03023a9a1dfbec0fc8f2959f16f7fef91db11ba12b97b67e11d7ba25d28a5af3d2852c8605cd7c8c88ab0f933c1010001	\\x8f73a227b383c89240e4b7f3b029200c0387296df021c3bf946944ded2b2079b28c54ff3a5b6e479e0d3a8ec9944c865909c427e3878fa44e175d513fd7c3609	1639575941000000	1640180741000000	1703252741000000	1797860741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x971809a45288a05c224e3cfbdc16823ecc8ffd2aba0e64be4073da79398e59d625ba59e11a68e41534d296cf748af41ea7091c4c0cac58832dd0b59a37552281	1	0	\\x000000010000000000800003a5416f74e43fd08c76a69face3e6db7bf01dd2d2523fca7090759494c895bbf41d27f5744b29a3c44a9aa5fab87b4e640e0f2847812a7460ade05d8a5c031de25caa9e1918a869743177e66f90b83f98524d8534c5a3b9b9794d7f43d065e5fc34ade22cb9367ecfebaac060e64af3dfafc09ecdc2dfeba5cb767bdcbc734c3b010001	\\xf8d33a7e171f77bded0c65ca15f0669e4d6e9dd247a5e01148ce0f57d0854792ab887ee4007e335cb4bd165a3d4bf4a32dff15e2817c4b2a7a2e345d6001fb06	1646225441000000	1646830241000000	1709902241000000	1804510241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x9778a0be73687e60842f76fa663282d11c9d021b5b46690f4bc49c38b1c991ccbaeffd99965b2197dc22ff3c20318c541ae0659896cb6cecb8078158889912ad	1	0	\\x000000010000000000800003a722981dc88fca9abe3d37b8c5bf7f0e97a434148824be9383ba95e0d74de402ff066fd7eddbe86e57c727e32ecda7ae59e461893ea4ce3b3c589c52329e148ecfb9b537712ccbe40e5a924d08846803dc69b217e889ac409de1d4b9dbece42faae66cbc3ae543ff79f636de150e00438b086ff497e4dddccb2f0127e654f071010001	\\xb17fad8adeceb98123e56eaf384a5ceecd1ea73e7315f98b0dbc80972b1186322aad64a2a076f624762233c26860376efafd4034cf1dc4d3ce7786027b7a1c06	1661942441000000	1662547241000000	1725619241000000	1820227241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x9f941ce81d4681f1b7d4fcc43074ff84dcd6410138de5be5eb1ccf5e04cf91de01df88ae561048bb36293b08adcfb7bd6fb2eb09b80fa9cf45fc51b32791947a	1	0	\\x000000010000000000800003cfa23da329342448bef8efc9424d71a5c7af9dae9ab1152f9709580195866748bbdf0fcc1a516014556bca0e7e997bb65898526b5fc7cfeabdb0bdc97f7ae412407fd5b48bf7bd272ab8d339cc57bcb807b2a92d2885e841b0bb7f2ec4ebb095e3096253ab8c8cf08fbf5b150bac5a6a6d0f3a4ac8ebb515e6774f4c979e6d75010001	\\xa1cc08e7311a14539c718052b3060ca56c5426de6ac7d08dd01d0130062eb395ca28b3076457eb1fdd2521d3121d768eb1d9b66b93cf5b70ad0326d2ae562b08	1648643441000000	1649248241000000	1712320241000000	1806928241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\xa234f1ae7efd9d0c155bcb8fbe8ada74927e1093857d010276e91ce05c44d58e6a5a85583cd4a506caec3ae57f98631446ff11dcd863a844fd2c48b7e95ac79f	1	0	\\x000000010000000000800003ec898c88c72df1d1f7b307fe0a00d6d351581fecd68b71253ece4c1180a09385feef4ba31691b352a7034df0d881e9955f842e062edc60777f572eb4173ba8ae49a514b9281f16d80d84bbfc2415139233ec14864aaf601e16ebdb82b3706e43d4fb602bf531fe2f2d7c9b9f5aa508f3cbc388242ceb9cdf6f491c72b019e32b010001	\\x612e730c693834487324fd9f8ab5fd4b2cd186d034cec23dedeb7c5938ed675ba2874a41fe698a8fbe6f897c798e8004bb8e580638ac778ee8762a4d3e31ff05	1653479441000000	1654084241000000	1717156241000000	1811764241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\xa7e8ab3770cf49f3e3d4611eab4803d8cfeeecc3ea38f649605cff7e1b59fd896282240cc2d7d6173d09c9e6b09934c5cd0f5d29f19691781f9eace489498018	1	0	\\x000000010000000000800003dbc180103bcbab830057f9c63e2740c7079e92de21856781524b5b2b5bd118e2e4449058b47d724228d68d4cda473761668703f9ec711fa94c2e73fcfe594ce6360a080ed27f059206c1d657e4385315bb946f08fdc354f536f58ca6fb0807d0e3e9568c04b28d3069fc25d70ddbc8cf063630e1708fa6dd1976819c30236e0d010001	\\x03794386aad01b7ea15f5b3c9ac4c7a2bcdab697e1d6a364994e3346e4cfbfd5ebb71763d4c6a723b3cb440cb476b25ba9b9abc99164177793596c806b021a05	1652270441000000	1652875241000000	1715947241000000	1810555241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\xa9941504b144a6180a4458fa9b8f2f64f9f1ec2932f1a3e642fbf7b32cab7c3a79e3035b73d59ca935534bc7ebf4af5a90969aa0716d626245598f4a28341bae	1	0	\\x000000010000000000800003f566b40f6dae7e5e35c28d352bd4d8f54b4f30511c9c4a965321c27c7ef869c76626786de4fd19838cd065878766410e4db0c9b73d842d8f0dec2a66994cba6465c69b38cffb3438afddfadd1d0421e0072fffdbe1b69510a28f3963082aae5ee3996e924688816574f5134a595e96f509101c4e9c2a2e012bb873fb3a970d73010001	\\x6d043b029a8c3eb7e1c01e5a0784ac9f9bf794fa59ba27456bc657fb4e08e5503abf6c81a11d4c1f104f240c7b5fbc31fe84f2a52f57d5e79c435f7f41a96e0a	1658315441000000	1658920241000000	1721992241000000	1816600241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\xac0ca3a8118d4dd37625ab327ebb705faa6bc437116599d59705d4229c53074a3a9cfcfc0fd7bd056bb5fe98b917ca4b503cf9346911f29a5e87c63b597e6e2d	1	0	\\x000000010000000000800003c0312c16c61976db3cf7b3ef5d08b0c2d6a16c7fa3a0a445fa3447d46d2f4db0eff99a4e6e5b0fc081a3da3a593585b26c3280d59b89c2df08e9738a876eda5758d32785d10a61ecedadb39d52d414bc0e2f3adcaec57b1d6a495af799f7ff049739ae943a1af4cc8b1ea3d02944f345a0e6654cba4ed62e688e06677960ef61010001	\\xf08a6955c37a4feed1f865920b9dcc9019201efa7d23bcdd58fd0e109ff624ea38e0dc591a97a69723eef5a1494c30156d30cc4282c34ba42c661d41ded20905	1646225441000000	1646830241000000	1709902241000000	1804510241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\xae1052ac88a4f29460df2f7eed5430a02fac27e4dcff51a9e644bb6578ed6ded040b8067c06b244c884bb4cf3d9f8cccb510c88818b69b01863a03c89fefb2ad	1	0	\\x000000010000000000800003c18eef244744d33f6a03598cb4ab8befde8171c9c99f5614090e0045cd2bba79bddec7da32b5fb2b78aeb6b209359a43590916489aaaf62f0c2ced8258d15229669cbc033946a7bfedaa57fb8e65688dac5156513b94a9a61c72bbcc6e275f721eac035a2ca2633f9031149b164ea1157a7326c95f94ca54b6e0dcaa5d6816c9010001	\\xe565ba412a0190ff6fa584a7e30ace5438c4ff7d4f42f005a670e2d8166489f99de30627dbb47d6b8a08d9fb048f9c6dda9d57d99172493572b12b0a4edcc80d	1654688441000000	1655293241000000	1718365241000000	1812973241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
58	\\xae788b576d29800b4e5e649cb1268eedd93fb42b42b68ad6098734ff5ff334eb735959fed87a45e9cf586549e21e4b2e776fd76c9a64e47a9b29d81d51da3d9f	1	0	\\x000000010000000000800003f11796ec4610703084141cec9e7cf9466e93aff2b91d534a04136ff296d1b7bfbce1b00d7114326d0e65385d8870e32d41b60a9633904d55ec23178b9917d4753156b0870f7f6133a67a9223cf10d4059a766aa66f2b81968acfbcb1e4859fb44b213fb723095b781b95688b92d3da8aba2efc8b7c71b4d1352ed8c8a2cd0169010001	\\xf7fb2e6f562cb2bc89695238d3b4709ba2f028b4e68b722983d4302df8c1b10a562a7352d977c81e97e4bb7b7c9b6c05c257351d3736cde02ca1e9150e415c05	1649247941000000	1649852741000000	1712924741000000	1807532741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xb15ccbd9ec772093d8717c1190ef314c1f2551bba9939bf4c78f5da6881ffcb1783e80341b2c9690fea18510a1a98909773ff965eb212ac2f34513d411292c24	1	0	\\x000000010000000000800003b7a13e9f7b16e826a02e6c615fd933ce182738412084f39efc56018fb1a684eaa7f908079b467d2185709f8f0945a884b54160c1c1931c9313cf95fa6d898db1c5d11d0f3203b031ef016741ef1a40ff025dcdea45875dadd20782cc6cad7cf05122f50d93718cc6be64d9a56935efa80916e89c028c05c0c4c1130fc4369c8d010001	\\xa4c94350d3baad307f3a8fa53bc193e00463274abe31fb3f9c3aa94fe791cf42713f64dea039ade82c962cacb471425fa33abac1863ead3c10c0ff5120da4006	1667382941000000	1667987741000000	1731059741000000	1825667741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\xb29cc975856835a2e24a9a2404f65bba118eb17c1be07adb6df5357c22c5980725dadc4da0c4428b1cccbc8f6a21dfec59654e4445eb897ae35e159d45315f22	1	0	\\x000000010000000000800003d9a99991a7830c63e24324ed6bae521fe941be767bbe1fce01233cc93d8bd550eec5e3dffc2b7f99945c8dd2ee33b6d85e30a1e7da640d7fd699946bb48109897b6ab4112aee5aaf265ed156a808974deabc4c100296c70445f010d0d6a0159fb79cdca5a631836d708b12ae409734216b2054d28395a7c01b7a9f14de34d8b1010001	\\x275d440d9b5c947670a4e4c8965cd2f78d3b67a0aa5f7eb5ec5311b16ba364ee12a22f5d0445e5abc2f30ef55bcb9d9f712a3474f5312274096ccfa85cc2b205	1669800941000000	1670405741000000	1733477741000000	1828085741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\xb2a43a8110ae9584e124e655370867793be1758bd776b5b9b38f23b857c24c5c0ccac641c592490aab1cd42c01eed30faa0753963a5cec5bbafd655ec9ba261e	1	0	\\x000000010000000000800003cdb07061f4dc5aff066cb644d6452c52f9bfa7990b2bb973bbf1e86603b4addb6e6e91cf522a4cbb32b13ed3e460570642ba8ab65e875c69da80d064c94271dbf6cf0ab850e0c35f1358aff848dc547b61473b08f35c25c69cba797a9638f19416d01b18706a31c682317781f50fde08411d43326613e15654612839f3208347010001	\\xe2bffc314f37949938ad7004cd27b6b10574301c89b9c744e445e3e70d32b01781f0e6808084daa4c60f9ff1d19c2be5bda9145dba79473d3b6476c878b36e0e	1647434441000000	1648039241000000	1711111241000000	1805719241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
62	\\xb3942fe3daafdd7eabc4b1f9f0a4d1d3ca83a69e27cb809a54dcbcb24c3f01fb92eaa70da6353bb3c868aa3f2027b587ec268ed9c0a7c7e81a24e3de9908f4f7	1	0	\\x000000010000000000800003aa8d4755f56093a1a49a21d3a9d46542fa7de3ba273a731fe13d9f946e905f5ee5c367c04cb21d92013b144c860bccf5812552231916a625dd18d5990d6e7a9efbc3b19863f6a39efc5fe0e4fcc0380d63d5c2216054e36b29d430918b8a2eb4bb06931cba1ff0983520c14567740a226b411cc5112e71156b529d83d60118dd010001	\\x63793b5153cf6f5848cf206457e10ab9840b67e7aa42018cb7018edd4dcb025ffb9da1058fbe3fb4431cbd00f1c00f71ec5af2968c850e49e616ccb8f34a680f	1638971441000000	1639576241000000	1702648241000000	1797256241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\xb8c82d783e3f21a3ea60b5226872b69102654171429885a519bb65a4950883f9fff81db616e5606caacbcfce39ac38c657960adac9fa01d72b7ae0b1f9e09ca3	1	0	\\x000000010000000000800003c3997c356bed6f8781ae6620f8cafce11d5e23e92e76e532ad4f5e46ef17a78e132452403569ac5d71571d2469d512f86bc594f3b9840670920b9836c6782f2d577a2ce6778eebf61433ed99b9fcec72c9d10a99daa4d8fdd85c9bec989930a92d47d7ad4720d89fc41d1ea9112fbd494a6001eb9a8de9d62217dfb274da2811010001	\\xb8b69bc2109190719e87f59b37a7326b314ecc44a1cb2122bd6ce7b6edd0cf9c7c0135c226b2d5a0d8327171d1e779888be7194a09405b608887dcf14f680909	1654083941000000	1654688741000000	1717760741000000	1812368741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\xb83cd9d7b8cfd7b78de8fdf82b2b1c82e1b7e46999f59b07e497123867988069243af04f36e9cb031ce6f706924ae8a486db759303053249b7d5503e03089007	1	0	\\x000000010000000000800003daf83fcb37974eead58568ede1f992b78ec857ba05dc8eb75019669600d68677ef76b771ad567e9fd224695487ac7bf045288062a897033eda69697255741dad35484e68a667b69ab409b74d347ff35f298f6166d91fc2eff8aaf11a0dc2e770ef2988bfec19014f3f740f32c87dfede3b25f699cfa7549f0b64f59302ec07e9010001	\\xfe856f40cf563dfee122827fff3d71adebed6c8c82bf46cc72731ece0b673c98d3a709c40543e98880aa3593d26d45ce25c90e23cfab4b8ccfd22e3c1d348500	1644411941000000	1645016741000000	1708088741000000	1802696741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\xb9c0b4cbf345aa83e9eb295a200080beec96d047b238d5c478a65fe7eca92a4ef69c3ebbec2f05bbc6c5b2456a23b0307e6561b65ef05ce1f22c262821ebb34b	1	0	\\x000000010000000000800003d0e66d80fea717f4e1da1bbb862a378eb7fd1b934e9f194035f82ea21b09ea9977691f9b0f6bd8769abbf401144019bef6af2da3ea873b70a182a63c6230a549d7226f6663f6fdec919cea9c3ee9457e8bb57939eadcb6571c9ee028f458902402697a4194b8c1f5c5715212c493466e02f776fa15cba1391792d50c470eda63010001	\\x11ad56f01f019349edab7462a111d9ebbd7b7b6d1ba0e6f471009506226966178d1c15b3a353514ae199a1b7d5b5e3f6d9bb1efc241d34163f6088e3c3400f0f	1662546941000000	1663151741000000	1726223741000000	1820831741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xb94418207c5af9a742dbc451a07e66cc9d0202a01bb78e61974bd7812385a6022794d87f41f5ecb946853dd16801431b9a711e679b88a97b968fc1f66a854b5a	1	0	\\x000000010000000000800003c14be6d00da2bfaba48fd12bbeaffdf321009d9ad309720b3dcde4218769dc7a4e375e9f218fac9cd7f8e864f14fc240c6d7bea1c9f58295bf26bca95c8955227fd3e4789bc9c010c10a289f61f8bc89c2e3ec66550ee006ac18248970165a4c51ccd641b427d2cd8a8a6367b1f14b0fc8b7a0622006c8724881596db552f241010001	\\x64dcfadd5df49500bada833ea42c5eee4158ed7cc6712ef64f0416cd0afb562bac250078eb621933dbf02d20abb199450fd7e6b6e20f5812749358d15336540c	1663755941000000	1664360741000000	1727432741000000	1822040741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xba1c6a80427d53a0bd80f0db9fa40349f7f1efd7ad1cb50eb7af8a57525f542647dacb822007f89304d166c5f4d733df032432c78a5963a7a6e00363a97ee746	1	0	\\x000000010000000000800003a80cff348915f8cd2a57b44e640636143d62ea571c41077efdb6bd2c296838424f11d3255afedb60321e79a0f71ceb8854039f9fcf3e952f8ada796664bf08439d49ab263348d3053c456acbe88884718331e14eeb59db82101401cab4024b59fd80c5a260f4f85816068c86de74353e20e646bdb5ef5a7db271bd8c7b39b483010001	\\x5cf0c3c498a52958a6ec438401d1b19a2a0dae5d2a218d9a5a160b1dcff8fdbe7c0ab3c0624ecab6d719616435464cf894368be1f6765aee3291c45451a63201	1640180441000000	1640785241000000	1703857241000000	1798465241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\xbcc87d6df3dc5a814c9f71094a0469f05f33911e1b67fea3ad24034bcb1770e0886a02305bfc29d853c11c7db46cc885b07067445fec06fa31a30b2451a8b774	1	0	\\x000000010000000000800003cf69afd89f1401e54eea9b7663c30e0f685f74f39cff1d4648833eb5b409bafdd94c18fca1aa8e86c4a8818352e09b37070cd3f691ab1b153815c02952578f7e9fe1051faa2cfc4321d472d4c5b5ac0c8f84198d834625417d997c2e2b8dc458e88f20f06187c5b7372ca9232ff2e0d9795483d307faf6bddc7d925726537cb9010001	\\xbd0fe3656ff362801d7c37ffe5d57e41ec8a50ae6584726a41c058ba688b351fadb19b7e3510e5699dc64803df74195acbe35e4df14da9a116f1b95100d5b606	1657710941000000	1658315741000000	1721387741000000	1815995741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xc0e4ddf0453337c6ce13ccdc8c64d1a711bf02ff0125dcf301d456849f4cc36a4a651d7d579cfb2c5318dae219c94bbb0d7d186db5664c9c3dba668501dae03d	1	0	\\x000000010000000000800003bd9714b307e25318dc1da6c15057c274722d878bd28d7d7c5326d8648f91d3c1c8a7cd5a33591137f7f215b57c44acefd058d8420d4568bec5b363fd5786741d28ab655f32dbcc4bfaf6617059adb67578f827da76ae3de4fc7314f238ff4ebf053945fe15ca7be050fad89d093a82eb180e9fbca10f87899a9ba1384bd85663010001	\\x0abfee46ec7a650d137472d5f48c18fd95e625d49f29e079b827592097830dcc67652572517fefc708fc99b2582e71c969992512eacced81624fa50dbebc5d0e	1648038941000000	1648643741000000	1711715741000000	1806323741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xc380c9065694ae2b47013913fb30c6ff5a31752b59cd9b9a8679f937aeea7008ceb8eabb6a4859aeae80cfc69f0e0d288797ea261471347ceaf73bc6b7ab0e2f	1	0	\\x000000010000000000800003d521c2ecde98f8d27c213a3d64e720f0e9c54f9232e32c0cfc96ce5843839c3e68f8889a053d7570ec3fddc98b1d0b3666c39521671b06a7d915f46a7cce96566eb1683ce8b77132aef53a8fcca4c11f9b661ae3f1ee86b6a8350e190d6a139f7ba9887ea48ee5ef4d4ed9c8ca95383c7aa1f3a90a8a5300d78d29a50f2fb895010001	\\xe0e12ac22a673ba040d99858aa9140a27d6d1aed89b9c0e2220d45a4bf385041b507f36bccb93fee836cc8328d1831b2dc12db20aa7d9bc5a84df560bab94d0c	1643807441000000	1644412241000000	1707484241000000	1802092241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xc4e4697a3c6ea6c22ac553b2387f4868d049f2222f9e0a88f9b07fce58c436ec134e137091fa1db5b09ae381f82936ed20121dea87335c90892f3c162b8840c2	1	0	\\x000000010000000000800003e6215bc302fd576bc33cbf2f8bdfdca548530e18a854969290c13060e21fa1ba50e7e000e0afab0c5a78eaa6b5173e82e281ced481be98f526e43c4f90fbf0d526404c5faf6548869497997980d1e48c733358c4660a44ee9f8dba3b274ff90f82fa215ac33bd483b681fb409b3e3ba8e07a1287bc4863ad4ea3ca0cf170aefb010001	\\xcc484a6fb4f0d53b4b0c871c8a1b86301eeb224d79664d4f6abd9b1c8353174c5c2726c396bffd8323900daf98504d522820da026e27407113a1b74da868a004	1652270441000000	1652875241000000	1715947241000000	1810555241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xc7a84b73b1e5b2fcbc119f91b8401754422ae8f54283bd849858019a278857e4fe38ca0d5ab793266193bb659af74faee50fe23665d041551cc7132c2f65cc75	1	0	\\x000000010000000000800003954fba3d3c0e6afe49da4e499398d3a7ccb6c901b0deac3fdb8a7a29968bffd24c2f5b305d2816e58a3c4fbe765945613805861df94c149bcc619ca779461bfac8c792bee277ea9f23b0f989de7d00a5a1aa2d9d500ed08d98bed0f088628cac1c3f2bc4759b51d3c528deef6d2285403636615b54f4861b55f8185b1b5656fd010001	\\xca68cb275b3505d7396e9bc7f09a8dfd7e9ff0fc9067f03193d1195f7daada024bbe9f5ccd9d054dd6757dd0cb79e052a88d158f3fb804a0fab60cb3e029b702	1640784941000000	1641389741000000	1704461741000000	1799069741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xc730d11371e461ea1afba582ab3eb7cd27a0b101e83b2e6b30216b982fa48d7d1e55bf41cbff54b1825136c10925e9e16ad35711fe74de27caf1c691e5fe2ae2	1	0	\\x000000010000000000800003bb6e661900a10a92c9b22578af981de13dfffa58660c650b771e4ac6ce06802b5cc45550c9f6fc2fbc6af3cc0a94bcec7bb796d5176613214d9b5f1864e379c09a115586e55628310a6bb41f8e19d0805bcecd9765b3fcd3c229776fc5a5936a116a0d6e1755e9dedde537297bdbe8080ccb096198028f34ba7e5a8e7935dd41010001	\\x1bdbd158d50e21ce6c6e1f0ea0b22b2d2b6c86c9cb27077e12c0e0e521cc3922294ca71c8fdea719409280b61dceada9808e671ecb67363c798fd021bb8df800	1646225441000000	1646830241000000	1709902241000000	1804510241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xca4487b3984da978213073872d55bad6f2879bad4745b85abf519616ddaceff838b7c025d3bdd8b21f05fc2ebfc1bd4653e0b7832dc24ad59ac139723092927b	1	0	\\x000000010000000000800003da89188ef110b1ee2d0b76a521e17f60e91d62094c9d1d7ea0c7678943f1885d057b284023f81e214561420898b8809ed69ad79448c96f1570923e2532810691cb678a6a14096ede7d317ea91d244c6db19e449fcd58e4ba5ce6a0e99bacdf1fa158ecfdc7d4698b2b1847dee0c5ba19620998fe74f55832ed6c9b89ecffe37d010001	\\xe0231390004381d18f433242010b27d96709563f1f1871bfafb70ff89df8446502301385bab4eab1323ae60627500c33e18579bc749196be330209dc32d4710d	1643202941000000	1643807741000000	1706879741000000	1801487741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xcd246dceb090b8c22a547c6ec5a7eac9fd72679a311b8d7023cd7f5f87460b09c2e6941359fd1059c704a281f01d99ce0dc6fa958223bda71debdaab588383cf	1	0	\\x000000010000000000800003e72da8b937602451fcc6e80160dcf764fed47937063d873d7d072ef0486de67a19a6f16691e4f988de5fa7deb8e14927aa846e5f518a4b81ca8ae0f02167997caf9863b5048cac185a15e29202b8800b8d9ece343fd701cecea88f9b609396abdb972954039da19e96a416c202ffeb65382135149546cd1f21cba75b4e8beced010001	\\xa2fde9728a35ab1ff7a2be65d6f47e59fbdeefdf901e2d212f206efcf403d34ee63818466fe7ab8eca1a06b0c0750fbb113fd058cc95771dbdd45cc26d05d304	1660128941000000	1660733741000000	1723805741000000	1818413741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xcec0faa2fa0c7ba85e442e5b4bd42b7f64c30ecf96efa3af0edc464d718d86be69958f47861cc639f28440252ecd67cb2c7adc6e7b273aef7b09a4ba2b454cfc	1	0	\\x000000010000000000800003c4e4959caeac760a3036929628a728345e9db5e7104e8fcb35417c86f0f127d13568b5378351bfb2909354d1d4a716c7ee86ba38ea20f96089a0bafaa33f64c550e9a55c37e5f5bee43a9d6db5a38702f2ff05e11f24b313f4abd7bcbc0b33aaaa6af21c115b03fad2dcfe72a949746dfc2559a59772f3dd4ac3f394cde82219010001	\\xaf50194318877a76a37b95655e3b8d08ae2931f3f6ec27f14e46691698c3544da5a430fad8ce8c476c33597a3a8e752d3353d1a0c45242d33b3f411daf8b0c0d	1664964941000000	1665569741000000	1728641741000000	1823249741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xcff0efb91aa741deee49ffd5fd990ff38a16e26f176df684b4861f218e497702f5b9fdca357aaf8f70af93b69c144fd6b24f8d2278cff1d35565ce1c4eec7091	1	0	\\x000000010000000000800003f2184d6795e8cbc406ce321f99bf4596b40c6fb9abc32d7fd16788e9b6714474631f04b7b0dabeaa975bd758118d0210d46626eeca706333e1b7d8b0786ad26dd0ca59201ddbd4b60c13f2900d1fd98bc7dd3c6f2bab609ed792b85e7e5e12402e13913d576a58de913a5cba7899c86f6d2eaebdd9751af40a752f6189fecd57010001	\\x70a79e20e7117999f13340a20c7b327d41214b96064fb5df2cb7da98534b2b9c16ca6b95849027ea1f94fc73035f71e0df41e59093ae32ff63a74b5a4fcc300e	1665569441000000	1666174241000000	1729246241000000	1823854241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
78	\\xd01084de3210284f6aaa2925067a79776e91e47dd22f420b2a8fa9e6387fe6c34d0533aa8e28620fa67f8624ba7330af964440a66b9850ab66923cb34580f611	1	0	\\x000000010000000000800003bbf909b58f4c4f2d6addd8a89aff9bacc3b169007653023cb06ac4320e979d34a26e07fa7daabce601d370d35cd50943530cd3f8a13158ce40c572e1916bfc064890b80e599704396ec1e6946038032445121e2f0d572446a5742ea45cd8945c4ffb3a3dfb1a8103030191cbe457d10a43cb0acb0f25c31ff890225d9bf49829010001	\\x7788bdfb29ac30fa6fb3c61f4f6b5bc76341df375f9163bbcf7019cb6c781dd584dfcc62ce5ce067a86c3c67aa71bfd01f8104a1f1619ab242d1c871dfbed404	1648643441000000	1649248241000000	1712320241000000	1806928241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xd1e829693d38de055198491bd474e14533c442e77fc5d3f9fe80699110f98fc874d991a0e7261c2619d369d96f156716ee2304911af9db9fc9ec9d8fdd045c02	1	0	\\x000000010000000000800003ba5a106cf67700875abeaec9be2a20a9bc74178ff6715a30f89d073b01729de1667ad2b0d36fcf844e4de231867bf9eb582db13e0e06a50636967d5e68d9eea0571f1d0fa301d90339adfd1b7318922465c01db351c2e86ce50ce51b2222ad692fce6fb15575d64ad5406ed95d84079fbf7b9594808e00c6bc1d5c0304b0854b010001	\\x9ba8f589e253d94c832c6e9f6e108e9fdd950ab7bc0ce21c2b6621b97ec4e48cf3a1b37afdc8b4bfa435d2e4c9438cee894e99304432879067dffc324106180c	1662546941000000	1663151741000000	1726223741000000	1820831741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
80	\\xd26ca175812822a5f55ce9ea27aff45e0b86d8efe74ff688651d8dafc96e8fc7445dbc64c1a1af2671d83a84efac1bd5df32c5af17357637eebe7f82ff985923	1	0	\\x000000010000000000800003f0b2c1be391209d37b7cf075db500082bd8cb747eebe79ca7c79913034ba90074a412148dc8e57e77e18083928d55b601343925c77b4c1d0686fb78cae9b89cd6154e6f64a20a9ac1a6cc0d154819721ace8ac4765b3d708f283be2b1b344db0e4bffef2bf1607c411788aeb45a9e070e69845c5b0e5e4a25f397090b9dab1c3010001	\\x031b204b55ba72b1f21f4258ef5141845f2cec036bd0142abdc13d7f87970d5f5993aa03952210aa78fd265789537098f7dc72a0bb24d68f2e9583160c103403	1654083941000000	1654688741000000	1717760741000000	1812368741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xd4f40b76aa7c355e7c823084a18ce8054b048e54ff0d2d3650810a6445f16b4130a4139ba7ef753dcc00d787831666e314ea2a3debed52edcb460bc12750cffe	1	0	\\x000000010000000000800003b680d6e966992bf62ce97c3f88e31771bbea6acd77a8121123ca25197f5c04141d066127dc648fb15be3968c2f5e798916ebe2177061aed72bd601320c04bcccf4ff60af69626ea95f61aafd20bcc11bc95bcd6996e3cd153a1e2d1a9e6612f59dd20632a9de670f07b551d128a4c6f6ff14e221bd13e0074cd822f5e928ed05010001	\\xbfa8731a1577c22564051e57bf756402d3ee44759b54d3fe098a0c0e22be18260bcc0b531af35b7f1afe18c5f26438a49cce230a01820a31b9e2c8cc28d4ec07	1648038941000000	1648643741000000	1711715741000000	1806323741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xd9c86355a1bc2657aab2f0db2d55a1142f6dc5cd54dbf067b4f4dab849b1cc6ae0ff63a19df3fcfe68bec62212b2c561930bdc81d649f5122d09bf39706f4ee4	1	0	\\x000000010000000000800003a01539ae822944c6b94276ff3306392ae4d21439d02d0adda53e10f3354666d16193a703ca630754b70afebe6300be7917fbaec8aef8e31a4ee8a1324bf22380a44617cf302d85065a8f48e6eafea877be6b5f9bb334d4bea3b1714904040c5ee33570de4a126239ac76fbb76b6c11d558844fb7a5cc7648e213e202a2f726ab010001	\\xa67ef5aedee70770e5c5c2e6c9d9951c0aebfc26aa76ae5ee084d63c9b8410e491a0f7b13b1d03a4b68ed613835a59850fac988cecc4003438d1353af30cdd06	1652874941000000	1653479741000000	1716551741000000	1811159741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xdd441f527b37c9957db1229da8abc0de7114209d16473e8509aab28378c35a77a82f4aa991e82ad3181d971ac9002d001f518d00f31188d728cc8becc7b715f2	1	0	\\x000000010000000000800003b904483a6a9586905eb8201eed60691213268ed148f19dabe7217a5782faf397e6517c7d320ad9419f5b37d36c2f1093d627f31c14842c1d62fb941e2c487068c67769a434e79742050574529025ea554e9bbdabbb1e3963e0408a74a4f79706635b7dfa6c9ec0428ccb9e715caf116a168247680760b82b053e41beb28f67b7010001	\\xbfa329a5ee4a218e57b10415286deab71ddafd52f9a79d79a3917b2903b242331b0306d64c0043f2bf96d2a8482d4ef2b41d62dcd2aee07eba0049fd1806ce04	1644411941000000	1645016741000000	1708088741000000	1802696741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
84	\\xde50e3f4d2330f94498f6ab7111ceb5537af9fbb978476e08913c880e7d8b8fa597fa2147653a6384c6e3a17a012fb058d9744cfa0a55bc799c8cc9a90ece4ac	1	0	\\x000000010000000000800003c7e563a598788ba2f143612a8d7a68d744e7f5ba8918f29ff712b220df8a4a9cd8a34d4900624198ba885b469c1db278ad3359474571a66a2db62e33046c5ad5e8e3a231ec9c20cc4c7a44069848c75431aa48dda0208092c84505e42cbc03b9a353ddb4bf7c26b741a37401c8a600ae3fb6aee2321b189de02a5e61d21cfc8b010001	\\xd9682dacd3f1656bfa469cfd25a116b28ee4b35aa42e6ab55696c5a580db0b2023a513942ff65c900101762d9168c56dcac50b40de23b5a708175fb17ae4b608	1650456941000000	1651061741000000	1714133741000000	1808741741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xe1e87e57d5935597391be0763c5938700eb660a684704ef26111ea51f34a98420403b3a06deec4314771726ce46c49976dfadae92f507213cd11fef1b10ad0af	1	0	\\x000000010000000000800003af4de3665fb8485269df71c49473cc1953a26fe58ace90cf2fae309e55610ad7c700ac5b49e9bbbca1cebdd9acd38ecd8c0fa5beadbdffaa2cb48bc63de6ac02b56dbe91bc0085c1108098f75c46ef60f2e2eaed6f0f3e53de5d1ad930da861936bf5f21d430ea11f6e09d1ed5a86a4c48a324364bef1240a59d99234b3eba07010001	\\x1bf3ef71502587759cd7996c5544797597a7713e23ace29d8393630d1503ad3464aff239716e1f8cf4df23ad2743b96866b71d40ae16048fa7bd1109e6866305	1649247941000000	1649852741000000	1712924741000000	1807532741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xe354e4d32d40693e33be965ead242aba1c35215f98f44cf30a4db8b1f4ed31aa8916f4a250e8e1a2615707554ffd053108ed7c1e9c8117ca86a628fd6ceaf079	1	0	\\x000000010000000000800003e9411b31e89babe5bf9574aeccaace6c5f627491268a7099773dfda32081efdfd6e41a5158a3f79f8f1b8bdb1eae54ad587227b119a2eab86de1dd739af760e757a63cce49acf0f6fe4f96c625ad4f3b1e2ba90482bc28ab1beb027762666f98670e01733232bedf0cab4d22a23364013b897d3f4c7296d5e151f02c54f78e65010001	\\xe47b7001c907f2086c25c1f10d668a5fdfc57177665dea4f09887d9e5b2c349783bb7ce6b7b452b5895db850ae7953e324fec316964791b3d5dbd5524e95e708	1654083941000000	1654688741000000	1717760741000000	1812368741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xe42c66f3f7d610b3aeb7066e95212cba6fd66bcb3c9056d36d8cdf5707776d92722980101298e139217a2c1ea63150325a86c52409f112bce75b8e87c85e7c76	1	0	\\x000000010000000000800003c4b06056d71228a0c3e1e3dc850ed0c53f6c58e4fd48e366bae8288601934ddfb51dd6ff0e0119e500b7b483b6526b099611698e24c619c033ffdd40fa28d08e77b03fa6c5f8f344221cfe1a1f9612e95c9a16346f982394e0f783d05438c8e88a5ee997298e27e60bc64f7e9058577e1d25480963efe2e154a37a919056a7d7010001	\\x0991f7390fa79215ff4390c84e3358246bb4de9fc452f0c3349e605081d5e0265f690f608fb9dad83cb6cde0418cd708dc6639d8969f97ca42d511447e66e907	1666778441000000	1667383241000000	1730455241000000	1825063241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xe7fcc17d0aa6fd85925280e7fb3a9a9b3a6a5e20a6e5ff7ac53d20df1c33c99403669daee8ab8f7249439b64cd516449a64860e2a153f1cc53a03768746e1671	1	0	\\x000000010000000000800003b414dbe1225834750f4c11fe0d278dacb3aabbe448a5226cc5ff1ad2252615467823b6f645b1e5a8d8b8e01680bfdf3b1b2ce4799b4ec9ff5676d0913fbb3b7098e914c4c437b31aee0fe15b4894dc63436f9aead5ba8588779ee9253f3e2e7d43a4148a3c105d14e938db45639fa70eabb1a6067bd1dfa3ddd26d68da5f656f010001	\\x9f00b773ae31e90003f60fd9428e764b7d457f6ddd6efe74b22ee6917ebfdf7bcfa2ac13cf3913560e90f58bfbdbe6ad284bf22574d6b0fdd109d2d5878d9001	1666778441000000	1667383241000000	1730455241000000	1825063241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xe924a22a0fe1165deac19bf8913001d3832422309c9e2faa707e4a5ebdcf13e21407988166474cc9840a6daa072f18123ed96554d34e1217a54f782f02cbf0b1	1	0	\\x000000010000000000800003be3baa5ef5123269365531253bf3d753b2e40a3e348fd2dae52125e06c75fe6e83e0389e5b47bf6f14d6a27c4a0c69054c691b23449506ca927e6fd7b8300a5dde3b1b8486a6230f73639be252f15d094816c5feb1bb3419e2c40d72d51afdad7a0b41b60095ea1072cf5e6028bab7864e13a6938f2b56a8efb620d1025cfb61010001	\\x5f9eaf2dea7898fa57b325117b7e158847932391db48344e81b4b8d1e740539e041f49a61b062c5241e0bd90cad1cf1b4e4cc4352ad4c55a579d7b8ff726fd05	1665569441000000	1666174241000000	1729246241000000	1823854241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xed302eb138dc210d128ccc0cd10f7a511c2edc17b7c84e2bc0e6f421730be21394dd958b16e5096a80811192826628c139e61a3de3a094f5ca3c6ab5dcbe3bcf	1	0	\\x000000010000000000800003a4d681d5021b06bf2590ee5f7f629e7ca10dbfa4c87ff89036f1b709c9711a336e553317e09cdfd53ca3fb1b808ec6d73b62cebf10158d766a8c14fac240123b1593cf8edec16a2649f6204de504ef3919aca28e8364f1896bae08c5dbd9ad4bcf29385c78e0fd3696143deacef0f24db69f1160278b7c3c1c798a798bb0ef4d010001	\\xec8dad43233b87298745c9f5fce5a0759b3e9e51a43249b319fcef24b5b04f88146eca0de47460ff32b21fa222a4665f2b1347cd9c4c1d44caf66a2dc6bed20a	1643807441000000	1644412241000000	1707484241000000	1802092241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
91	\\xf0a008a5992ed6dfcb741acad1463c7ba16d29258840e75b96857250ee95f9a493b48ebe2cb59f17ed8393577708ebeaeb599c0f32e72e15ae45ff2cb6b02522	1	0	\\x000000010000000000800003cde2e68abdf46ae611d5a3dca5f09278570b90c3e3ecbe57691d96345b33a55f34b74c41c275574f4939fa6a80c4b2e1cdf9c1ca49ab273dec6cb2d445eadb83a347554adebd087802b599ad3a8aaeaf8cf78679748c1bcfbc656c75b7a3ce889744af16eeea57b914469ca6ef253fce7a1c4fb83ed9babe209efc878224b5b5010001	\\x11b106946ecb3e454af87bbab4891ef524fef097685a4a2ba0f4f3102377af10ee0218a8d15f9640d9cd294bedbc87a8939a4d6e53b04438783b3efd607cc20c	1661942441000000	1662547241000000	1725619241000000	1820227241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xf00cdafd2dc9295c36998ca6b5b2bc23c1219508c8cf5b26f4c2fed44db51d178e8cf88518172df9c60d8ca868c5b401649059fcffe7811d0104962b6411622f	1	0	\\x000000010000000000800003c146c0f2f7753bcaaafa9f17c053bedfda603f0d67eaf31926f65b708c108402b63d6bd15d864530c9da7f110eb9cb13d63ce18d90683b19a46104794c70e553d834ad8d43f0e9dbdfc512e57bdb447fb16a3ab965a489290b066993e7b74563cc3a31aa88cd9731686b2976f182fc873a1292e63dfbece0f1a58475c87a7a5f010001	\\x33cc2911d55fd45555e78fc6aaeac367b52ceaf9ca4031125300ecce9febc775d982dca1bc606001b7a0b8dcf309ba53f694d431ca998ea8231017cc656e1e0a	1638366941000000	1638971741000000	1702043741000000	1796651741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xf17491fbf5530f616a4d1c81d65e74762f26593164ad78bf4aebb998e914d34ad78566a9091fd4332395189ed250846cf30e0cd06fbc482f1cb9c2f09fee999c	1	0	\\x000000010000000000800003d5406f3ce52783e48b46b45c1a99c90e2c58ddcef17136034c1565652d36141ca1b55f18ac7540fffba638afabac9adfaab814e7cc5e295e431f321a645bc41b969739d1830f4c7c1a4564aaf1ff6d3a9ab72a8aed0ae4fdd010dc58da9fcd45f9561583122bb1a1553ddec1e040bba59aaa4516a5b96621ef27240b7a12caa7010001	\\x3ae80f20c5f4377897a111b0ff7219133300f510687e940b64ac3646bf5e94a00c2f2244848a0e2ee9f658c299f8f49a0fc56922b44dd947c28c0c29b9834801	1638366941000000	1638971741000000	1702043741000000	1796651741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xf2043f2f0927766e0855efaa75f114f284961bff6488c1a1f8aa76a4e9af8116cfc728aa33801dac995a77fa012fb4fb5ba2e587257d902e29e2d6b76584ea79	1	0	\\x000000010000000000800003e6e64d6bfb29cb82fa1d6eb480095b3120e82912dd803cc419b1aeb2ec425acba8074a9dc8531b0e6857622bec3552cf08e34f4488ee28af6fb8c9cf50864138644c748ea11d1c31cf32c6774c2abdd500290a2e2d33979f241028325ee58e3a73949bdc735a008a283d1b1927b01c85fa6763a0893c67a78c41277ad79928ab010001	\\x9cea4fc1caa924cfde634c7009614dd1485b813a7777995d8e6011cc7ef368c8895ceec7f51a2f6c582e3fe609f01bd24d8f2059468acd15b1cb61222957dd07	1658919941000000	1659524741000000	1722596741000000	1817204741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xf2b80d94320bdc2687e4091bf9d8faf9ebf39371ee7371b9ec0e9ee02efb818aab80b5d914dfe0a9be98f76580c7bc4c5730a2d086a4c27cc0c8ead9574187a4	1	0	\\x000000010000000000800003b01b87068c6021b0a7c140077270cb3b06666c6f7f78b61f210c328cf09fc4c9571ed40495ed43455ad9795e0aacdfa382273fb033d7f4ebe5405000dc66a96c6f4555e0cc43530d13bb4b707520ec3cc405bbc0f7607405e593395f3ae3767a9a5e131f69d86cbe9e5e7cf646008276ab1ba6252cba33885ebd5aae4218f67b010001	\\x48606dfcd00f8982cad2dde215f7d18f3b294de4107bf4a75f256935876d9a3a21cab25891aa0e068d3b8b03b4fdc746d105795f8c40d5fa4a9a0c1ce22d850b	1663755941000000	1664360741000000	1727432741000000	1822040741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xf400ddabc1f6c8902fed4ff16d0084585745ce230d7e754439d6e85313ca433be9b102d170dcde0f44dfd57c4aa5c0e360c95e94f7d11d1d14aa0903ebfb852e	1	0	\\x000000010000000000800003c432efc80ecbc72864980a1e96277c5b4625584b1074ea0b45a1efbe7a08080085995ce3c1608e258f6d79628463d94e8e31ad67add09bd71e222a990d93ca7ec56d623cefe540b5869389a3e5f0e329701dabe91c449d438f19843b09e1a5f2e288c8e4c86994e816690d0f6acc6fd125e1853cd0f0af5bde10eb88587428e5010001	\\xe102ace0c467188d782849b5af9d81ca68301140e3a308a1a7bea1c38a3588df6e310b00cb50b30994f1c66b2849f1a2abbeef7a7692d1948eeec99a11438e04	1669196441000000	1669801241000000	1732873241000000	1827481241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xf61438bd52fa65ca9a61b58d6d9b95b91ae0fb6dac27cb485eed940204e892458ba050798daa3892fe9df2f7b5cc0af602eebeef915834db218dfb705bedbf14	1	0	\\x000000010000000000800003cb5b5c5b4f6d773b66763bf6961e54a5bb4908777ded45f1de811a3c66d4ccfdc7da8fe833010546487fec0296d1914629cf7bb347baa8d0479b8ddad7aaadeac3b0927510871f6b20b3de1925fcfba5686981d2300c34bde92297ab6389d6925b06dc035245da382f80809f26e2ae14f349575243f0477af525bdbfd0b63129010001	\\xd34048991e7d6066b2941bd1f38cfd4b7fddc2efd408c6a376faa6ae1b6fb960cba6ca4996c82d7823c84d2930110425db834ff3b1f1ae9079397b4a7b76600a	1667382941000000	1667987741000000	1731059741000000	1825667741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xf658378e82a5c5262147eb8c7c31a96de5c876bbc4cb84ad9ce604ff10df45a2d226893f4c85518d7a3e95c9c4d5a1a581a3e923364cede1dec2f965c0480629	1	0	\\x000000010000000000800003c5c345c60ea0b65f5d7299a20d862f58360cecfabfa37810ba00775ba7406cefddcfeae46afcb788028a4595301b006e12e0c43d02a3965cbfeaf61348464a0d802983c8de5bedd9ff01da2cc591fbaf3689c947004711879986d9af207671c4263d760cda57fc88438b5177c1615cbbd50fdf15396e17f0b0ac142667423e23010001	\\x3fcfec13b4ebc625d283f09ffef2824f9537aebfb549a4ad7148a2a2723bf2d61866086c9cfec337de867e6bb226241878ffc70c0940d1a9432ac361a31a730d	1647434441000000	1648039241000000	1711111241000000	1805719241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xf7202879f05453ad669aceb9aef81e83efb8747789c3c0c151811cab6d452e1a9f8633fa72c1b2b3a62c5dca092cdaa19089aa5be098a2a25523e21bc898cec1	1	0	\\x000000010000000000800003ed1cf191d211a8253dc9430301c0d16b955e2a7b359d14ff107caf8209ccf56e090ee8466d4e892355c485ef3b64a8d9a36d8e4595cd9391b1cda1177a67cc56a92dd8c80343780f8cb38cb3f254df51efdadd970f03690be8955e596972340147c28572fd347eabb8a5da4e84fbe9764ef49d57969d1c667dabce7a58a609dd010001	\\xa3934e6b97877297767cdeca8bee789530a48e27290de02b7b64560db47920cbc29c6634d5fb44ca5e95edd0b803f04e5dfc1c7c6a13aeb5571025f66f73c10f	1661337941000000	1661942741000000	1725014741000000	1819622741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
100	\\xf9b41b0eb6538d512ef00b57f1cd58e31f54b5072ce421ef38e62b424d4d2c0e9858efea08c44a37178f3ab9683578b124000e9ad6d8e0288db4855e5078a647	1	0	\\x000000010000000000800003bef81332a8c5e42c574ad512e2fc6bc65e8a87ae719f15f421e8c973a99eaedf4646cf41aa29c9d1bca828eb755ca3c332b83bb0cdc7df7df7df52cb7ae6e1173b164f64dc5d3860468d717ab1ba723e770746add73aea1d643f32b107f8ad154795175426d5c016e72865f77608bdb4b40b628c7a41033aa2e8c8f5c0c060fb010001	\\x1278d3ea86d064c75352e01d1a8155b64ff5cd8474b80e8038bd144eda1de765c0d11da2841a34e9db0422d7b12ad246c5176867471d316f4c290924af96d60e	1664360441000000	1664965241000000	1728037241000000	1822645241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xff788e23802ad112df916c9888733859e1899544e937fbcf5f41092106cf9b8ccbc15c65ec0a2488411722c28a4e3c6de63b1ebc61d6239badb3bc51406424b2	1	0	\\x000000010000000000800003d25d3a13722979e0d57e2eb9ea69c89da8eb2b7f312cea31bd4e73fe295b0c22a0997d357f6e59a9978c7c8a112231efe9e14d48d133938bba4d1d4bc04fad18c8bf9315b5d777ed9916bf123bd5b3bdb1d2304cc8b1783f0196524a9104bf01025864f341c6e0b26bab55e0a6468ca746239a274c04f95a28ed81aa06a25b23010001	\\x53a605ca780d408a4cb39c4634bb7e3dfaea7a6639beb0b7e5d7928418911ee3b76ce75da51f8142f019e6b205f54e86b1aed8b8d781a13bec97862b4262df05	1643202941000000	1643807741000000	1706879741000000	1801487741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\x01113e85acdc41a111d0f11f8d294570d19c76e869f0610268f787d47eeaea2a70398664c7890be84530ae22eed2eb3d294f4db3bd77aaea4a3289492c9962e2	1	0	\\x000000010000000000800003d2f74e570704185e82bd97ec1baa8605d182ddc4f3eb0165d19ced09a444ba0c6d2ac3ff4f8d3eb93767d5ade9fba174af4f3dbf8af49d0b26edaeb49326908fb2cc95c313a5ef976dbc22214158c3fe4ddaa94ef73e6ec9ba8224455cb4b14359e723e9d11f15f5de62f02a55e694fede355b52a7a6b37e829900f0a5d7106f010001	\\xeb070ddbe4de9bdf5520e8c8547522a1f8ab43e02a21d884514b7635dafefcbfb9f597a195d2d5aa84e7a4ecf055c961ed72a621684e2bcd4bfa7f2e2ae9f302	1665569441000000	1666174241000000	1729246241000000	1823854241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
103	\\x08bda49481a6b09e1ba1f6daf8b61d15972f44bfd39d5e0f1705548c2c3694b93d526136fa9de8a6365999bfc836aac606a43cba19939ddc04e21758dd870741	1	0	\\x000000010000000000800003dac3b0eacc22982cf570719ddc6f78b74e48c6e43067d376a7ef69c7db9ce1fb4ccc1e60da4f8385c89d8f9beb0cbe99cb25bc0bb35606296fc2f4cf484864959b0e93439505b100c14914643c90fdf21a4bf9c7ca9b2b28ddc28f80f60cf023e4d45d0266078b313d4f72c3fad6cb6e6840c4fe4633870878fab3802fbd4909010001	\\xe260e196b00a0bee15474ca7d5d214767a1041857e4827445945408d1f92b20f15bb87c25a532790fca1780c512b5149b16fe0ed4622bd55215e25bdd5c9960f	1660128941000000	1660733741000000	1723805741000000	1818413741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\x08f13f225288300113233a19ba708767bd13c835ca3dc9e1d6d94a3d2fde9c4f5d812a8425eeae6f734f71a721e4c131f2e53efb9ce95aae872c108643b2fd6b	1	0	\\x000000010000000000800003d338f6a8af5721926bf58242eb3db7479cae5645a781ae0f7e521e6469aad68e6ad12521173d27c62e724211de10e86c531c3983f4a1a878c3d0f166d961e527f6c6b95b3505690b9a461c38e2f81b86921236fe2faf58fcc1589e78d2aef4eb03acb745dc52fd8204846926944ba76161abc4538bb932b8c4bfa58a12a73c51010001	\\x7d1965a4fe2f69d7efa30b632b8147abcbb38a9c0028c02b7f7bb0e1fcfcf677e5a6d14086d34ce0c3f70445bf1d6088cbc0efe52c44b0e86db98d2baef03d05	1653479441000000	1654084241000000	1717156241000000	1811764241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\x09d540ec32b4208f561dc2a48cf11298a1e993b8461fa7a8bf576199b28c577a376c981d43c0eb758edacc6a4ee89f55621661bfa51bc09ace43e3fe7978a508	1	0	\\x000000010000000000800003ab0185d96c106c9d2cf427fb5453531410c928183e7201625ba9df937c4a9f840f2aca5798897a71ef82baaaad604d4be3f03524eae4dbcd8333e586c5c5df438b2303ba84eb6fc802fe0b439bf1658af55a19ed63008076f39d6766c6c9ecc294514876d2c98462f8074003d31493b68749449a957aa160baefabf139b64dd1010001	\\x7f90b917197ec7d544f20f552a2cc805211ec71f6ce4c651107a9fa9ce0b055293d7009b22ea32726e90ea2211bd62dbc8c2ab04ca9a3802fffe58153d853f0e	1666778441000000	1667383241000000	1730455241000000	1825063241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x09d9ed96d67ff752011e466c728e30622a3788f26e9ad3c67c8a520a6f4d346aa53e721a587ec1921ce4510522e509039b6394245c17a9393f0c9df2ade7d54d	1	0	\\x0000000100000000008000039733b7b7d6ed571c24202cd4bff6dd3c12fc9adfa540753b45635126d689a5f7cf01de098afa94985ffe17b0a8514b3bfeca39abcdeb9ffaa45dcdafebf10b01bbcfe9d195619712ef0900ce9cb9efbc9909c2f849173e33f2a237e5dc80df0f5913db392bf09f2dd074c867492c210e17a8e14bdefb0ac7bc9da441b4a64af9010001	\\xaf0af270d7c26eee89d79876d45db3f86962847d0cf95f1c6d87db1853b66059a1a16a78028949fdb6e24335b37a8e49f2c961d3ba7f9dddf72b94b9a3375604	1652270441000000	1652875241000000	1715947241000000	1810555241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x09a90e6510cccbf0b14038b48aa04426fa723f250e605c24339831d60f151ffc83e3ba06efa127058fb41ee6db2235ea7974fc692267047190e63770e4872c27	1	0	\\x000000010000000000800003b81a088828ec0c565f0ef9e4ea36537f17e7a8fdb05677a6ab6977947866056cab3625fb7d8c37dbc90727ab16be86f328d6f5464d94e4e2c5f0ecbe3f8ee9c5b7efe9cbf55286a138568ef8dd10f09679fdb2b77d28684e7ebbc0bf54b46249b6b96756b3d6e53d417174a23196e0ccc584f68f025ec3111ac783bf7aa86017010001	\\x2449f456c2a490094043fda692b94a7d8ed0cc07381877f0b598eeda2afda2119fcaca81449cba5d293dc5da0e725a48734a6091b9c1794394d1e676982c1b01	1649247941000000	1649852741000000	1712924741000000	1807532741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x0949f79e2d57813c45989206f919562f5f4d86ef00f79eda1a9077df8d428dfa28df295f3a3d238cb4263efae6bb67bdf92364b7c4d055b27a003ed6d19ed1ce	1	0	\\x000000010000000000800003ce0394fa8a3ce66f93ac6c98cc20fc165406a0409dad38e6787485a18f67d5f1791c48b04f592457e035508b80ce6f60408dd47877ffdee8c1fc7527fc870fc8ddf739337e11e096cb7ce650bfe6cd02474613be02486c397f55e1c34563352139a56ffc55fc9692725a2b518833ecd084e65e61e085886a94a170c3dee1668f010001	\\xc4cddd731473d968691ca43888d87ca0f3a1c5e3aab734ee66b4cfdd18aeb7b25f4f50d9a65ba12781d9be0de8dff41d1db4905fdf89c4fbc7dffd5d5c2ca60d	1653479441000000	1654084241000000	1717156241000000	1811764241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\x0fa59ad7cb57a12e7f29bc3db3314ab85464e845a5f10278e7114ebbda499b5325b62c9341bc6b0ba0655362ef29f19b16b839211f450a09b3f92254ee1bae30	1	0	\\x000000010000000000800003b2fcf2afeb91028b56c7693a9e59c1787d9a00700b067ad70e5e670c647678977b2e0e2bc2ded25d6b27eea255374e54e452a639eaaffa630d40d5ac26aa6c779fcbd8dceef0d83b26a31c282750bf3e74906b9dcd273a1208501f45c118796ac5ddeac8e4929ac96559d1ed417780b6585e791cbaa4b3a06b4611d26c818261010001	\\xe2c649163f0de50ee0ffb0872901bf5a74b30e98416a8ac024067e65344a0a8a7cc8e626a165dc21d044bb981333cb31776fa261ccbd2d1c9ac89ef70afb3d02	1669196441000000	1669801241000000	1732873241000000	1827481241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x14195a9da72feb7ae92995a82b136aaca5314ec7974007f3a000a031c94a72b309952ce3140c32ca3a04f04d92f25922f044cd0e948194afc6872027a3587a54	1	0	\\x000000010000000000800003b076d01d2ad99cc038410d6ab19f57bede5552ee2889a445d0025c198242b14e1789a94da5ce82c8abc86915c50c069ec6f5b2a04de660fd69ab947d55e52efcb1a5c6f00fb98247ff92c168fd342fd30a56b1594d4868e947c43690ceb3cae177c8300e5b3a8175e17adab5067f5a0065b4dfaf090c175ac943597a33db607f010001	\\x8ed0eace7b9843b65901fdfbeea4dd62b738e0215e5eed97347c4f82affcb67c5e0ce92e6f0a2e9433d0bf0aa04ff181afa30dd972b615dfaf0a0b4fb9b1c105	1638366941000000	1638971741000000	1702043741000000	1796651741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x17599a64fceae9cee6b38ae957858d30a37760723eadfed136b1b75f62f51d8d5376970829ddc81119d7e5eda18859729d1bc04a3bebd0a6b61b1dd1607ec792	1	0	\\x000000010000000000800003d36b4e006ed09eae2198db81592934f8c27891ad695fdbaf050be1134d0f338945eab684eaefe77d0717870d9b1759a64569aacf9f7f471843b7a42966e5cad087d4b069a25126f09ba64acc81b48dfab15dfa7b2ce7a6faaea56e1f7c4e45a7b2bca0013d1d7ddb9bfe6e4ce3fc0ccb5373cc166257b4467c93252c23a1f601010001	\\x0e76e814e86d2a9061492d3ac9470710fd4d53fdb08f5b85c69c2e4d9f30ee5e00edac4e88d08c4a9631ab6847f0ac4b68a49a8d18fa83dbab9bdf79be65040d	1651665941000000	1652270741000000	1715342741000000	1809950741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x18a1196715859d9f8837cb791933d21abfc26509eb41a6515cabf8fae16ec7642b849db9c9dcc1fd83b218d6f4eed807ce6868fec7be2f752c6cc2f24f27d384	1	0	\\x000000010000000000800003a01a06896b121953e4bc2f3a56cf4e796c396fa2a2390f9a664a3a504ee0584dc402ea18b210e12ffe6f9fb218f2963173db87a5b06e1e8a711514a246710ae8050e28603dc1875f4f45dc3a8ad282fd9cca1a45008b17235799ea2b2dcebb2b5d458d0ec2879a63df65e8f0889037eeff04044edca2b2ae5d7fac35132e92ff010001	\\x9f9917db091452a87762bed6b633236944c5c8a1b37fcc67c01a2bf370d94d6ccfcd28cfd282f8d5344f77823de41195d93e6643f7105aa0cd496663fd915704	1643807441000000	1644412241000000	1707484241000000	1802092241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x1b3d1300f31af1eccf5d65e6673ad80c8c69235784756c0de283975327207931d1218a364aae656eedd603ea80323dfc69934ac67606e19e2674f09584505893	1	0	\\x000000010000000000800003a566e744a3992147dee487df3ae127b3b2fe2dec1adc7ec6872be38f2fc510c3e7abc2b807e3fa7968b979e787bdc8eda4fee625a2b4a9b632ec4a3a3dc7854fab6738f1d3ec8d98215ab85a2770f83d58d49eee43acf0b3d1c67aa7efcb209dcf01a94049945dd2ef1af90ec2f5adcea08e5cfd314805353c78f60f4bbc4cc7010001	\\xe9d8dc081b5d713c68175e50599de3e1162e58b03370f04a12beae651c978e9827f1da4ec63b2256d14a18e859b7a59b3af2f5771d45cb3e85801fca72cb9a0f	1639575941000000	1640180741000000	1703252741000000	1797860741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\x1b81f84e5a1884dcf7a6a3134cd5a1caf77c71c4b024138c72ed9d5a29293694d844dcb3fa87234f07bfac43ca79c2f82cabf05beb105e2afb79b7ee15939971	1	0	\\x000000010000000000800003de8a64cccc0738e188bb9166aafebb966e2e2c03bf5d50fde77532912035e59f399c0e371ec50d3e361618f079f13e9973b434901ec7d5faeaa2170b7e3be54a2d2c143b2fd1340c2b3959e7b78aa23f96cccae6fa31253e92d1ded424a43b39dedce3099e9053997cc8b5781a5b1d1f13ee90d1331c6f64b7a0f08cea90bf03010001	\\xb83cd2cde0a52a0f2a3a1bd4eb017c3da845cfec638461edee1d0d549123bc910d3f37fcc28613d2f0551ad1907a13e5bb453b890e0215deb317cf127b239703	1669196441000000	1669801241000000	1732873241000000	1827481241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x21ddc9309c59fac74874dbd88de01e7354e47c7ae362bbc766fbb1c5653fd2c487c80b4a159b049f4cb3c4fd846f776c1fc06dbebc925bc6f0d01676a33ff74e	1	0	\\x000000010000000000800003c608179d6c8c4b4bf9d05694b4ecc752b04c5976813c41bb94fb54b1a9b6cb13881dc45fb07c702fed395af909b4182cd34861afffae4725bb9586b11e5b4cf037777b4d434fd09f9cf489afae54fe79a73ef68459a254128faacd32d57b363f76b591b95de8fc76866af866e74db13081b14fe50c7e9bf9907b82349f3f8123010001	\\x3b668e8ad2bb3bf0807304a1fbf513d0e312058bed6dac0f908d0e1688e1708432996b85fb85581445f55f25c19d0ec3cb561538233bb405f2b1e6eeb6c5cf0a	1658919941000000	1659524741000000	1722596741000000	1817204741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\x224575bc60d9ad60ba9ad7257d307210d5cbef98c46a576f0bc7f7afa4c2c7ffdb8d28166e1a2e7ddd267f2b50bfb9eb54e630e13f0fe083bca75453d05853df	1	0	\\x000000010000000000800003c90d034f340ed3f0f20c051cf12afdc51344eace86cd23a29d6353dee6b78d6888da279a52c9ff372da144c6ae8b5442070233602f8db44cb2ea2a1e0fedfd5e322e0493011c0c7c5dbc5d7c0bfc4cc9e93fd3552adc117f1cc5293a26d458acd425fa2af19402c620aac813b2556cab028c8c84cb12e7e25330a59bcd2ce1e7010001	\\x9ad36b1c1de59de3e2c5d1c224d07d7e3c2be057a98f03d9dbb0a8d4d070023d4813690f85a47ce09ef63069a9714841a04ebed02edf9223a35b380e6486cb09	1658315441000000	1658920241000000	1721992241000000	1816600241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
117	\\x2815770f9a8898eb9cc2c1bd80e1c8ea09232f48304a392113179d0f8a039c42c43b208f81a89c564e246ca35c5065c7ecba411587d0a67e64fab75877f61116	1	0	\\x000000010000000000800003cb140f2e35fa4c8d880c746421a342ba47ce50b543ea0ee2acc5110e40ced4a6fe685f0d6938b5a46f8178e2b3acd16b99bd3fc0b91d86b07c027f76690f885d0e029ec658c1503d8b4877c6d21b6ae5d26b511d2079f8178dead403741ffa148d7efc73fe32bb1a239804e1817bcf574fa63341adecf36c579ca7f9f85170a9010001	\\x0359cf9ae726d4abafacfd095e7632079685220fbe6979d453c6476da52c5b512c87fae116819790647ff47bada37a3e81e5fdd0c25c413cc035a81dddc54a03	1646829941000000	1647434741000000	1710506741000000	1805114741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x28053d930ab97281fb69edd5dbe5329b3061a1c8dabf0993ce8f35df1036d37b358b1aaaed69a8537ecc31bef4cee3f0ef398d5f8bfd407018c918ef38bd7e38	1	0	\\x000000010000000000800003a948ce9d2270ff90f7d34f47797b8f8323ea5ea44b150f63cb7bc8dd997c1dc6db2109e8dab1b83a3dcf97f84903dd596e08464613c37f6cae7cc9ea245e2ed995a929f1923821a4b837f6ba0f7695d0c03a91bc1ac761575bb1721a8f903cc45be54f040b52c8b82d9c5bd2699e5a11f4a2a82326e352706847dd7f631ac219010001	\\xe7d353f893b790b59bfec03f749f934f0903e2cc7ea862e9477215f8c4040cc70072323ef736924e4b766b685a51ff51c8323b9156dacfb8307c2a0bf0e56008	1657106441000000	1657711241000000	1720783241000000	1815391241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x2c2dd80162fc2b91b06de3dbaede27672580af76bd09f56996470742a474db72ae1d02a32cfe2c2c3152557ef52ec7acf56b035cb154c41c133f9093bdb0efc9	1	0	\\x000000010000000000800003a357ffc2e60e712c4f3940652dac5477f35600044d4f3d5d367ba4ce8b9d02957bc37c730ac52905eb3ac163da69a92f6f1bb79e410e72462cdc6d97e4bff9f5fb85448946f44338ef1e0e5daf5344033ec875d5976564233439a8b4aa238f367a40e21bba295c8fb05d16c531a748d8fd09d1c05b617a875afe927c1e8a43c9010001	\\xd0a4ec14f43e302a9b598a4e1759ebb0b27c0d5c6c61de5560c87b94b942acf5b09fa6f287dec990d3d4bdbdd4ae141b92ce409c1064873588c1a3f58e815f0a	1659524441000000	1660129241000000	1723201241000000	1817809241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x2d95c72b73b95a6b6638e9aef95e9e4a02c49577f02383f9b3a2555bd8bf406f0a90989dc2bac74531d1b970b258a94148bdfa7602c8cc574a2b8469b09cbc53	1	0	\\x000000010000000000800003d7913782729a9ed5d844b8da3c63479b29a610e9d4fda04e28b1888de2051f70644df7f39f0bc860493a4e77f1ddbc3bb638b16400829778c97d1586ce02097113a55be62995686cc14dd3d14bc2916735edf6d8bb080034812fcdff965360735e30ca86fb7426f523871dbda2dcf1d9f1806624ca9a4d7764a408ae2cd314e1010001	\\xc7f66164b481137adb6cb763fdd043720c481724df9bea4ed45734ba2bad1f9acf64247fb8ca6476f248ffc2b3e54130581957fc48b92232f332e11121985a00	1642598441000000	1643203241000000	1706275241000000	1800883241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x2d31354abfd9afbac806997f1f3d06736ffe80a9687a54f26fef1cdce73ea4b4e0c8394f385edc648357d2dd1faf0dd6b060d43cb00be2edb6c3f2a980ca50dc	1	0	\\x000000010000000000800003c7a3a2a63fb98bd1d8db5062c29a8e3e599003e78abec8e8c414f58a80eb5d9c1bd900d3c8510243ef38ab7615bf0d56b780ee1f780dbf397b462faed734f592421c0e619895122002a1bd9eddd9a18bf4cac53bf0c11a7f21abb292ea7a35c74d7fbf1cbbbd9e38b5acfab68fbe5a073e10ca618b3fe4b5a1451043a9b93a73010001	\\x8a96f29c6efe0bd5ad7b02606f9cd942fea0a704f93c0623482da27f529f491c6afeba99e8f60613558c4850ff349b11b312eb66bda4bab65ff8234cb799db0f	1640784941000000	1641389741000000	1704461741000000	1799069741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x2ec954fd1a18b41829c33c920f5c7ad405ca2d5805eddcc83fe403f515d0685fb47b5f846048639c9cd32616f94d8d76259ff7afbac995b5e8ad6d63b8eda757	1	0	\\x000000010000000000800003ce6c39db251c0b99827665d78d7cca2e8d281d090ed8881f2764108d5c847e480a23599285c37ac82dfb9ed32154ecf5acb7d7abfbb40ca3e6c98037c3974e47707c4c7e42165abfa1af91a85ce211216425bdd9025186d47d509390953ec12ac01a2f9d326dd9987f67cabe3aa6be0ea03357b9bdb50225dd2368349509e9f5010001	\\x78d907cd85bdfd1fd6c70fdf56b0ac6850e3587ce08c7629d6af60f63dbb2c11477e55db79028c36a686ebc613e7f39919e638803923b779faa3450367d6d30f	1669800941000000	1670405741000000	1733477741000000	1828085741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
123	\\x2f799eb9d9ea466491892d03ff5aa80e8b5f3da2f67e89fa2e3f8cbab20e85cff4a5bbfda0184fc46e30eb6fe47b9643725c07d898d208938b406f86f3273730	1	0	\\x000000010000000000800003b80534908afa43c040ebc3a5669bb48efaa5eca5292d0e589f10588728aa3b0a7d72bf78c5790a21b9e8c4f4e7485c2dd4ddbb2293d77a804312b59dcab8ddbb5f1b96d9df8f6a8e646079233bd795fdcfd764ebd339cae62f0e2850f879e391713ef91d7a2a20a9550774e1a4f5ba48ba9b45c106c1b4b1e8c26c3933f5c9d3010001	\\xd2824b4bb0c85925c13f168650cdd930c2bb5055aa981a78e292d104a717c5e83e2616fe540437f0aa52827bf982e2d010a9e0182a2956d65f0a493bb842ec02	1655292941000000	1655897741000000	1718969741000000	1813577741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x30a94c791411ec5614fd2d10051fe20e1dcac7c8a4eec9aa1b885753b30c1215035ec2b98954b32e6826c28820f72149cde966daecae082c3fc464fac0640287	1	0	\\x000000010000000000800003bdea2f91aae1becc08ab7a98c626dcaab532bddda6f3955d341cec7c4442ffc41412ccfd19ef174c8ef1f7261ccb69d9f387fe92daa5dbdea362cc674c5e640d5c3578c75940ecf3f1231c85950d2cd274dbc65b3e4d76a2774d91b9ebbc416ca66889da78cfc51528656971df3fb36fc857b0d4066f799774eb26c22851c9e5010001	\\xc2100ff5124cf366f12cd02aa375d63cdcc2e3b065b3eb484ff12448282fca3dd16f4554b612aa8965b84d5b2dd8309cd12a8e017e77d033fada8356dd413a0d	1638971441000000	1639576241000000	1702648241000000	1797256241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x30b5c7633139a82622127dc17b345c71f3387bdd7b9a379cdaa0d63018059693a87cdda12111eef250a126c49988d96ab9bf9846e6cc541c67984ebd36932b6b	1	0	\\x000000010000000000800003d7f833d11af1963f2e135034fa1eee75a987be9097f3c8dc0ad58d317f82526af9b48aab87480d5d783d57edcae2c185b77f6d4e8572fbf2ddf34d14e3b43e4233fc4bb57dbfc18b235d231aa3a1b0d5e7cdcc6fe18596dd6dd395e54fd323558d0009d0d7ddc3d443b72b37707e4b4301c6a94bb9096ea3d728fe25bdf0d1d1010001	\\x2fe71d20908cccfeed7ce8e4603e09c0398e2c28b42e8316b47ecb9de2514d824d878bf4a3e53c765c8732677fb7c9b683bd3b6f1b87c15d4b55cb18f0c4a903	1651061441000000	1651666241000000	1714738241000000	1809346241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x33b5e709a3c2790254089ee44a1a29b9d638215aeda0c8e584624871d6174ad02e7d62b319122bb1b82a5e61949a8656fe588e76679736fecb826a385c65caa6	1	0	\\x000000010000000000800003df8da6792897fe6bb1a5424389171ea996f4c437ddda94cbe373fae32ddabdb31f4c7ec8c218bcfe5c2f8df99797211da2d523377fc8f3880356b0bd5802268e34eba6935361ace11cbdb62f6a27aa6decd4db4140b2435d97712ac3b08d018c7d9a19236b2040c0d7be89bbf19e21e17198fb15d0519db9ca58737861e9b865010001	\\x21938ec8111009021de9e420d30f93a1747af5cb03e630d6212c9ad735797ef756ade5e70629584b9071c9c7075ea6a46e62e88357ebc5a17e2d35561c024f07	1656501941000000	1657106741000000	1720178741000000	1814786741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
127	\\x35950cdd932aedfe29f77ff5b91a97d5dd1538abb6f6bfbd5b07dee7f12e47eb3d2aca6e1246254ac1010f3f351e016a5c427498c3f3bb45d2e6de139728d5c2	1	0	\\x000000010000000000800003a05686677889375670c88d03aa932ce877ca85424c731614dcf4dcb4fd9a3a8d6d6b037ea3e528b0f463f3fe0e5f49c9f9ac18884c9f84eeba585ac8f1257095ac8ae9b3c8a318f6d12e58039a587ee42c572474f807e29cb4b2938e54f73d644ec88d1ea7437dd24a23dee543bbf1c3b24be93977bea0460b660ff73ff951f9010001	\\x09d616f4ffd890e811b0ee1f58c6aa7d8ff8c29eabbbb8f6ae6fc70936f056b6c9696415ebb08ca342df8de1d0da18302e431a040ca1528ad3b9bbe328713607	1661942441000000	1662547241000000	1725619241000000	1820227241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x36b1a1d2d2e5965d7b18b1185baec63cf2fcf65988d5b419c3bbcdc05dcbb20c32359329539fbcce95b42228a0f5c7ef9fd79ab040aacb4c7b14816f0b9e3282	1	0	\\x000000010000000000800003c887ffaa642b8a94560313fee1e7d55841bb20f5d9f931f011e4dea3eaffcc170cbce57c4afc99f527de5704bc6a67dbcd7f52f172119e634d758ddc1b44f6a00da3afd28fec68b3dd0574e726536bcd45e9bde28ed8f32c4453dab48b7388e8bde6e33b16f955948a4725cb44caee7e9d7855230c22ebe5c9bb061c9ae78717010001	\\x9e353631e996fdd7fd3e0a30bda433634351af7cb54576a157089145892b1498649dc61f5d9582fa15f8e57ef1d55727d29f983b1f40ae705faf02398a036f09	1658919941000000	1659524741000000	1722596741000000	1817204741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x370d3dd1919d331d9852cad3a07913e19aaf2f63b5286297733a13173b6ff117c82295a30b2a97ea614a023ce39d872916eaa95aa6fa680f81b828a44af6cf72	1	0	\\x000000010000000000800003c68f70f52573ed482189bf0283200bd94fcad3a8053f5bd2f0635b82f82836344d60af774e2165bdca3dd930310c533f93f4b47ad8a943cce306f1cd78af8446c01a70b0ef1b037b86364487394cb588c22deb1d4cdbd89eb09810fa4fcbe6e04ae5fe7ed8626e2d44689199de2eb78ac518ffe27c74d3c7d46c57216d27c767010001	\\xdb1dd7d362d590ef092a721cf18ba40a777fdead47e4f2010d1234f6fb6d3df206f6350f44951d62fcd653a5165f16c2263869d30f17d4d4b4287e5831a27e00	1647434441000000	1648039241000000	1711111241000000	1805719241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x3ad1453666f485a86b632b819beae0f06fc98d099106a490c90042d5b14a2fbc4ff30173d046165b082080770130c51c313fc57b7606682bd5e48e7873edf6dd	1	0	\\x000000010000000000800003ba55d88e8e5fa877235399e837e731f6c4b654565c2e0d909b583233b4f98e1f9efbc37cc2889a18fa1438cf61011985c3c3b39759b4f14984e18a7dbc54d9dd110b133dd1814a55cd3aea881e9e90e0e7ccc479bf760aad46fa4eb1f5a96ff305cc2155e910285891eae913251f25b1980be17ee3ad5f68ffd40558e27c4eab010001	\\x1083788e63602d39298c792fa04894dfffb2e18c36ae2ca2b614a7dfe1dda650e3c21e2440cb594c15dcd0f2ab6c176f0319a8ece166cb40f8d8b8b638cb2b0a	1649247941000000	1649852741000000	1712924741000000	1807532741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x3b515753d8186beccf418dd192148102cf931845ab50f8700025888ace64fa6a0bb5fe91ed7a4045f19f91973bb8ad356281cca08054edc4ee35bd58b22c2dfd	1	0	\\x000000010000000000800003cbf8d5882735f53636360136f00ef3276619c6502275a90e76706a438f0eb733c07f9121af3719e101f98e6e0a1af52e45c22fcfe9159819041cea1e24a180584e248c2c0b36bfb6c5b683d63752b3741efbe71c30558f515536510deb375f49439648ac19a14afd36e7e69246afe9682499edfb876df395f03a4b7d714af56b010001	\\xda7cb3e4fef885e783923980e058edabfad5708a18a3ea37b984801bdb0cd09a0f045ccc89835b6082ae60790358f63e9b4b3c280d2f125c645dac7b94859b0a	1642598441000000	1643203241000000	1706275241000000	1800883241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x3f0ded1ad7619a60d5e0145d6f11eaf696e6e3fec9aa35bed54d3d8ffd292dcd723d241a4cb39bace82965012227dd2389e6100933aafadaf3d16054461707eb	1	0	\\x000000010000000000800003c32db69146cfb87a18f290253d9201b4a92bbb3bb45944a074f5995c32c909be4f84570e3522b150a5e724c88da0cdbfbf716ca09e6a23307d43fc22cbbb21af2984cd3d15554f14d68c20adf8098b88aa3481e3d32ecc1c0efd52c72413c0c1723656d4f844ab1700ccf934900731666f9a0eb30bd4c38245c3158f471eba59010001	\\x0935739cdfb8c6d269fbda59e77c0730202696793c828830fdbac354f5f2567a486183eaa9f746fef121e9de80f0e5c767efe7cc431f944fee63e98675655509	1667987441000000	1668592241000000	1731664241000000	1826272241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x49619f594ada81c72c83eda8d1cf7ddf2d5255d2e863e2d34f946b51630780322a35df138f924fdf5f150a65aed0e899f4bdd436419e95ca883ba7fb2a87dd8d	1	0	\\x000000010000000000800003cad97786bd629af02809c94602f50bed531d96465ca623a7fcb51b511536c5d555e0d18aad8b377efacd8461e47599d3890a02f9d660257992a40a1c66811b225a624f9ee37a3dc28a5de9f36d44855124dc2681af5906cfd2eadefb18071e6e52449ca4bd8057319238a8bda3d153db154719b3bd36bea34fc76f5f438105b5010001	\\xa8eca51a75475b0055a842614a15385140d69f58423c378f77c7ae8a16a42cd22f5f700050df8a14f8817d96aba1c6809471064df9c4c69b7d7b688d3104af01	1655292941000000	1655897741000000	1718969741000000	1813577741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x58fd5188f08293723f219f76899168a1af58daa2d0a276718da326c53cd4ac181e2033a1e46811d1307baffc829dd1813a88f939667a4c0dab83601abf20feba	1	0	\\x000000010000000000800003c49d9a1a767ac59055164c98973c60327391f3c834e2e95ed296783e616f46e21480e871caf4720eb691bc6ed9b41d95f3f04e675652758ef24cc0bd0aca9cbc389701249654b5de56c43c0680f9d0ea5f98138890a4ff67d5d40159e89d7aa462bfc64f876fdc17077d352ea87b0688831f080e1b3b54580cbf656f6f61fe37010001	\\xf74668b957450b854f53c1ecf6f75c1a266bd2a437005eee38e8791554430ebbc3bba97ca6db7c8c638af46e6412ae2cf28bb9931f1fb6bc992131f990bae703	1638366941000000	1638971741000000	1702043741000000	1796651741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
135	\\x593d45191811123aed5f53f43b677faed3e3582c20d01f4d8df557454754752ff6ae82734c1c284d5b49632f52d416e29e3bd20486575370027ef00a0232e973	1	0	\\x0000000100000000008000039d3eeeac1d8c3d8b22872791a0c33990d2577c9119a40746d8306d108043c427803f0cce438ed45d53d79a3e361d398a85b3a7d979bb93e08405a5c436b2946e07d64b536c968ec3d368073e4d86d29342d49c93a30381ffcafd2776049f8892aa44c590bb8b2bfd47f791ef16414994e5e345ec579548db79f7d01f78be064d010001	\\xd2d8615ff3640abb605c22f6adaeb654cb377a051e074ae737ba60c7f6950b405b13809307f0196dfca75eeefcfae413c18ff150be9eabd2f8f205e8143e6602	1643202941000000	1643807741000000	1706879741000000	1801487741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x599dbd11dd874a654620dbfc4cc8127eae7714362ae05a8e2352d986805c7308e369685a24e59630833ef6be1d48bea4b1d76e608a1e35440cf70b0357e1f76c	1	0	\\x000000010000000000800003eb1ed568791f7da3ea7b6a49c6119b5d6c9af6fbafbe9b87338c19d964d957fd731e22c50bc849fafb1c330a0f6d1150a7da698c03433c3fc3ec0dbbd99b1ab6e39dfc3f488c0bb4266f9d4b7dcae7e7b6792da7458e343dbb1378a36ed2cdcd62c323d242d0db4ec39b6ccad078e0829c12ff696458e08ab572b02df96a6075010001	\\x6ffa5b06c722d9272f6a4d03ceefafda0754ab3cbb12fe4f4788ef9b3c2bcc6455795da2782c53d3346f7ccf845d880608424e43477043d42ae82bf6bbac2806	1661337941000000	1661942741000000	1725014741000000	1819622741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x5d51d9ce454ae3ea07f50ffcaa92f1ab8ed18605a4b547ed1b792d5a6dcb92477eb7dc21b84a6ba76a8299fe89b25a9f5f58a21074a8f154760ab31ae936aa9d	1	0	\\x000000010000000000800003dce2784fb6e41a85d7197f3e0949a20f03d3b6b01aa5ff41383210c2396c5fb1b552c7740991ea02d2639f43e6022e73657e362c25f1f13ddca3d95adcb89e79114652cdd86f8444d4a8da930df86bbf492f2529c3dc597b3d6d1e969c97cd0b79b9cdcd3c2501bb27671b45aa6b565763a8a57a4e07020b91cada8537f5e397010001	\\x9cb2f223ff3e1e6ba220976b41e126556437f44d7c7f5a6a7105486b14c5d106208b810a3563319b13d117e9afdd2a50a7ae6de40eebfb63171996ea0973e005	1657710941000000	1658315741000000	1721387741000000	1815995741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
138	\\x6209b42bde4487a219013a4e1e6651a4d05252e7fba81218d0fe222c05ad1bcf52f8080e534e83df5be1065b498c3562b5e503fa57c6b789f0dfc7e24bc5cf05	1	0	\\x000000010000000000800003dbf6a5bbc318754b949acf4c5bf00d953654f8c499b2d69245471eef2e94f075129f3e1fceb258da882f45b75b168343747493a8362d0de810bface3302c19da2bb4145a17c8836ff58f86c1fc86ec4b805f99a9fc04f4c5604a9a8df7eb08a96b292fc768f5d31b099208e28fd5f1fcdec2c1b976b6617e9163a7151c98cc8b010001	\\x24506265ca71f23bb7146a28f1086789f3348ef8e1920e6e27ab2c45164260bd9a46f7ffc1fb8591f450810172f4d0197c899b4dc6640515c41afda21b573906	1643807441000000	1644412241000000	1707484241000000	1802092241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x63855806bf2e743384eeb67de2468b5d3e71598b44f7b591c86c549d909e00f0ccbf0547d4a41dbab43c2e9a9cdc4cde555c0a75945be6a5c410a46e6438e160	1	0	\\x000000010000000000800003c3d382b4a070e3c338a8565de7196a5c3dc58908106290c0fd2e73980676e5cd32e244527ffa520a5022e38836f8e0ba8b299ba1737fb4260aa49153058af15820c41c6eb67f0686624a0b315bac8874a785c5614dd15201e93c02f1c495e58853d0aa52abbf676fcd4f3ba61c81ec4753c21dea9df43b94b9d2ec5055659865010001	\\x768631294ee72632afdd45c7808ea6785bd445cade523364724034c03afebfa738c908234e62ed7f93d6f8df550dff91ee5f04d9b8e711595090196cbed50c02	1649852441000000	1650457241000000	1713529241000000	1808137241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x66c1830477b7d21c2d2710fdab7cf94982a981c4be4ecb2b41ba1818004272f170fc1e1d3f7dbbffd6437fe7d88988726a70948f98b7134869e558c1036a701f	1	0	\\x000000010000000000800003bfe5165cd0eca1c8e4439c54a428187d0ef8e689fb1011e1a64432d777b9ed8452f45147e0397fc2067414dcf0b9a89d0530f54e72190c8f81cc2f19f71099d6870a4be5a09a946c98ddeefbac6da421f4dae46fb98261f1fcdca5ddc1fe1cf469860406581ab2b0e85847242b1ee8f06ceb6bab247f98a0a6ff1a2bb49b0271010001	\\x0a02d908ad210e446827e3e68af14e23186374804b875d3d42d88449e31586e6445d80e44293b29b2e3a750e0df753245de5413e1e819c31fc330a97b9385c01	1660733441000000	1661338241000000	1724410241000000	1819018241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x68ad641e8e235be3c357a89bd71c7950af697436393a376341cf7552b2a9569ab2c9be145139cd4269fed053ff348fcc1dd4e46237fbe506d4f56a74862b0f3c	1	0	\\x000000010000000000800003c314c4fc6a6a4b326c930a4d0234ed64289e8c6dc41cefccfad95ded507e456021c486401a48c5e336cb838408ff64e8b8360c2c2fd150b8946ff61745fdc95a235d67ae102def2eb426cc152f5120bca8ba01e97a1233b2b8318bdf935fcceb35b87847d9788e503dcfad375d9a8904cefb6ac79f51dde08274cb741b33aa13010001	\\x71375cf583c82a66b91ad8ab9f537be0d4e834cac37656488176af9d62e320a574dc364e82dd6b2e029580aa450d7c3e884a4f327dd82e5bb983ab74d2bcef06	1657106441000000	1657711241000000	1720783241000000	1815391241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
142	\\x6891fb81c10769070cd23a0e5a2c1d3ee8c1d0471fcee7ae191382fafd47014cb9c5b39fda80781e382b8fe6d6a1947947be6ae00755a5fffebe5555998e72db	1	0	\\x000000010000000000800003c576fad783a192d6843126c40249ee686fc65660ead9eff5ed8df4d0d114fc095bbed19edd14a8e5ddf3fd5bad9807b669c2d29707a1802a61b8f52ca1c37b438afc1548dfea20ad7dfd3aac2f76608a3ae8b5313a9b0075bc894247a424263680c20dec6729a251904f6a17dc5537ca7befa53f832b4affedc02e404bceec19010001	\\x30eed729ca247498ea6ae865203ed59c11cf3d19ee17123e6040b10fdf9ed8340fa0b11aa6cfc77fb5737c1efff773a1bea2258a55b710a1173238c4ff889d0f	1658315441000000	1658920241000000	1721992241000000	1816600241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x6b19c00bf5aacf95b2a6fac41d8f510e0f74bac2e075606d2e109871423c6ee06a816ca26edce9ca0160348b61ec71c0a9df3b34aea56a47571a191692030af8	1	0	\\x000000010000000000800003e0a8d879c9ef2ae0da6938debd7c192ad7b7a58bb8aafe79c84a5bf33f5a42e93f2e57a6399854cd9871ee869c203d3e304f70ace4ee16033e1bb5e8108c8f00b00e32f899a46062f93af0f66825eeac7cddc5041ae41538c55bf0bc407c37cde98be7d5d332e1339cbe3ddb915c8a268f79c5eb00d28519a2956fd857ab81f1010001	\\x42f080701d35d7ed44718b76ebcc57a05f1e26446ede8b6257db8fe4a8ea156a28c66227d0aa46eb9067f42e2b69f5ef999ded3cebb839e13becaa8c5ccf8104	1641993941000000	1642598741000000	1705670741000000	1800278741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x6f3d8b4e6d85d785549b770e30b4c7f98ec4e1a141902c306ead89b6773a62ffc1f9b04b1b70b6f898ab98be624d0dc6359f610c875941ac7f56d65c2e9b682b	1	0	\\x000000010000000000800003ebc940d9f81414933c01159fa19fe388903638e499cba06ef923f39a7e95e80d5405e3930c968809da70ce137804dafca7137e162586a0e50a42e33b8aa72d177e1693895ad68b747a503dadc9949541e5bd60c2af78f31263c54aa222dfd6c36bc16a691ff1fac834b72ae624501492192065dbd059cbd601db8d421f0e0903010001	\\x1900ebaef0fb540ed78f9e932c757c388d30ff1a2a497c914b29957b4ef996853416b15917a9bd76e5a4566c2b18bee095118b718fa1fc4b3416f706930e3d0e	1663755941000000	1664360741000000	1727432741000000	1822040741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x7159ce3981f6342cc35fd31d57409be19426e230363c0704a70df15113af424459ea26893a21d5b72ebe477728bdcbc61defd67cc664c3b455f2c7f33f5c822a	1	0	\\x000000010000000000800003b9a8e788e85e3f5ee0a05d03122f322a22c571fc55f13f2ad4dec97bf3e94bf0de13cd681f7d31d830cb0c4faddc6d22dd2e870056a80a0a687b05d834f4f3b9caed0a885bd6f2418d3ec97b271865c9f5c190d02e840d9aaf520172911f6f61599a7c3485f9386c423e10e4b09fa3a9b3ec7327c21d8c6031dbb93efc171ead010001	\\x2600ae9eee2a1b0219f24b89ab4e9c0c98c4c96e097fcb11e38e1de8fcd25e54c301edf53a54e4197cd0b73e8684de2898db83e07d47288603a7642012671605	1638971441000000	1639576241000000	1702648241000000	1797256241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x73a137178f211cf0f01b016173bea4316824a606b27db77d408b3e1577cf30f38e978eafd0834a6f208588942d52bd364aa0dd231b1ec2e147429a062573edfe	1	0	\\x000000010000000000800003bae51bb90a2419dbbe5d39f5c91c7c0101d11a40080c34b125c61191e248e29a41297472b9ddf9b27b9c00b7494e57d66a68e14fd012ece76b3942c77ddc446029e1bcd39655457d5105e81d12c7304e910eaf7f248a216aa2110a21a880fc6c8582f85652a59ac2c55a2bd6ad292e6d276541d28c8a9ab74ef38d616a25598d010001	\\x48bf50752318fb88b2bfbbf99e61fb7ef2b38b421f328c5fa66624a06e1c835fe3a2f3040a03b55a3e52b38402c008f4a5e563dde2a30c9ecd8ce4c3fa20510c	1660733441000000	1661338241000000	1724410241000000	1819018241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x7791ce344be22d0b65994a385fd2fc6d33446abaa305b70423d85e35232eb1353f3046b6d9fb8168fc296e2a3e938a9e296459e95d66f8535735def5d3b4dc1f	1	0	\\x000000010000000000800003d983bee847e35c9d056fea984dfc572c93f4d5de21c800cfc069438668e0fd2922be45683dff86e0c528bb299a0e1cbd839d8c847ce094ae3696a1093357a9c53854810ac8761a83d95b950735777a0723accc80a8efd5f93ea67ba5068689f8a1bc5868e7e7171d075ddf4a9707544716bca5e2b8f08aec6ca80b6137453bd3010001	\\x6e7ef5bea3ef86902928e55992b0ff522d54c6fd7507e659792b4cba599d26848c18a50c4523c06922ab6dc78e23bfd973aff679bdbe8a6e3abb925f2309400c	1651665941000000	1652270741000000	1715342741000000	1809950741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
148	\\x77bd70b9a21caa0078a835fe6aed7de661de15e5f8078022e544828321ba5f5f74ffccf37bb1535ad4163b4141b81ef4059b65c201ac0560e3a03c29e29f3b65	1	0	\\x000000010000000000800003c5eb0dee593b850e357fb8d9cbb90ebe0f0ed92824866d4576b640d2389bb7acf67a7bbb9c821f62308465e76a518e71adc8805e0d6fd4b3fd6e408f0299e2ab853381b34c8fe243d1645797342eb909a17a026ea26f06037b73d91f854a962dc1ec621efb69f76fc6d74744fbef5f3bee49887fa6ab5522ab2f39fd67216221010001	\\x0b3f86575c924fc087befb22e11a57be72d239b2ab969b6c53730592b0643563d2d6f6b15ac04de7c0fb8ce814f58e3918ea6a0337bfff4f07f228371a477e0e	1664360441000000	1664965241000000	1728037241000000	1822645241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x784d0ad5b14a1283d879a120d6ebeb7562f486aa243cf9cacbad3e66530914b4de95a367126e18fe4dbb29335a7b23e5c5190aab9e6672dd437113eecc2e0b67	1	0	\\x000000010000000000800003a98efa89c18267858c6635dd9afe198c57b7d77e530a7d4ac0d458d401405ba2e11b428c65e15f812c5a3085f1c6f0685e8012419dad68ec2a6b6a445db5a8396069b4d3516a18a9de5793d4c8cba0726df676cadb08a6ca464460ccc0d47d7eeda3fca4e08b30b6808d55944fb0232f61c866b0e8abc88556532da1b6c09b33010001	\\xf8af19e2e3518703fa5cce75e4d8451826783d3e5d5343914d749c4e71223c6f8942988f04e673d88d8663dfe37e914cac73ab6ed09716327f9aa822c130990a	1666778441000000	1667383241000000	1730455241000000	1825063241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
150	\\x7ba558fe4c0be652c59e665d68fa338b679679f812d11d73b375807ca64865ce77f23aa7bf0d456d16145c3d5acb272068af14fdd85a2c85098d98f205560b07	1	0	\\x000000010000000000800003dd3625fdb63691fab6c1efa71606e4bc2a825ed6a981cc7d565406c077dd45c786972c7c9eea752aaf3f4972465bec1a6d4b8948bc875bcb2147c17957c4b0f075c00986bdf6d2f25dab7de5d496f314ae8ca38909741c2b207965ccc0a9ed373209361ba73249f38ade71944774e7f1fdd0a9c6d1ea1ec8457ac11b8b9b7d4d010001	\\x7e76c5b4b44e65301e19df59578f7039e7cfd299e3b87885122afc2780cb105c4a5512be2e82b0421fc2e053a0980d2f3cd2a0e7787ea6213cb8d4e7b6d6f903	1667987441000000	1668592241000000	1731664241000000	1826272241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x7e19ffb6307048182359fa0a3b73193812f4d3ee3f3e480319fa1c8f6787fbd19467582749836224299b65eae6bc71c3d250809ea0a88f8cd1c06a40260e80ef	1	0	\\x000000010000000000800003afd129f64afc4a501ec98f160ff939d4ded8b16310c22be53200a82b901fdcb4f436bcc78488bb676c6d004e5eea991c4d7076e2993776a73ce0d0c2f3dab2a1cedf9e7dd45ce433860a77f4c8f628d28e4d82190b6e81c5be3b11a71331edc9eb6ec703dd6a2f0e29ac73a3c3ec22d260fc2259ed49604f6e75247fafcad1b5010001	\\x610368c91216340fdd799acb264a2671217f02fa027523e87c249334184d41b44ec3a986830efcfc8e04d515c0788051db44163ee6bcc7092965a987781f3f0a	1644411941000000	1645016741000000	1708088741000000	1802696741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x7fad8f92227c26ae312e24420e4db272fef8d11fe931c9f02b739b4a41e12aca09769c878a54af03dae3d9fef8970f4075c217f7bf1bd02026483aec943f2d6d	1	0	\\x000000010000000000800003cc8ee18a5fe5ea31a6fd736a1a34a47f151df65b8d07646eb038c8774a5dd1662981b8ed2a7a6d81f8562d6dda71a3c7c3b7983be7da6818582b6b0b472c50149900fbc9dee04c99155154580e72011f04709d3c3dad4687fc6e41cb06187ab14c9025e86691f29e18f732b51db6143b12aa36895c042d12362926b6f99498a5010001	\\x7b063974c35d1f0a7d8bbede65f5411051e361956c8467995af7cd3cac0184a1cd53920815c3e0eae12607111a76b5c0ed60b90fa709bf0942c3ce63c855740b	1646829941000000	1647434741000000	1710506741000000	1805114741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x8091f37a61bc827faf7677c22c58082cc128a831e48025dd7766974a32430ebbefae0e4509b9bf436a93fc404d7eeaafd85dcb33b0b4f7781bc2420f230d15bb	1	0	\\x000000010000000000800003c7ce86eaba04119bcf880fce478664e2ec383274435e5ebc13c81246bcfda5dcd2a094757f1f64db69a973e9ef294e8a975c2ea00770228fd0d280932e32f83070d2a08455dff0f22e3c886560685d4ebcef2f097d058cbc45341557b65817edd15030bcfc520b1d6b887a5cf619b38d56d34abe38d5ac59d6def5a693df7aeb010001	\\x81b239d3a4a6dcebc00b5c32a986ea07879a0ed0ab11f3a3ebc720d3089a042b7c0b49949c714fcf1a06fb960df8f6e40632eb95f8d6677fbfe8eea3e75da20d	1667382941000000	1667987741000000	1731059741000000	1825667741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x821d1fb124c698136d91da3cc26fb07b7c865bed40a33b05f6cea82b73e909ab091c041a5032a470d16b8301b6d96db0617294437b06c1b17221aa1995689dbf	1	0	\\x000000010000000000800003d820b03e898c16d647431389fab065b49f923e6c41d8f52e51dbd6500c560dd58a7675af5fc512aeb6a58535756319b51cf9f33df06b79238a1f8c432b0e4457c1cdd43b481d953bdbe5326b180945d168f4cdda6ec2203d88e4957eeb06eae011874ca8294b5a5853ce4fac1a064719e91764345c3068233a6cd808db17c9c7010001	\\x484db55d35e86d5b70303803eca0a2342741d9d2a1392a0c64151dd584d97991e69e3e80a9b47c4e88fef116d64dc1077ba7fbcfe0baa50e3df32c0c4daf4807	1661942441000000	1662547241000000	1725619241000000	1820227241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
155	\\x83a11380242b159557f378d56bed6423ee3c731baa6d0c6255628ef57820ef15554675aa3956659c3450969cd631838acdddf265a12cef9e1a37eca193d23979	1	0	\\x000000010000000000800003c69a2021cbe2e9c1908a9b5c226c0cc88f4fedfb7c0b125075b3e8d6419ca491fca9a35222e3017e4495ade8e24a93cb51f8ab33c353bcf5ffbe3eac1d88ad52833473f85effba005bc68cdd5b88eeef645cad1547409648689fc4137e31ae17c8355bbfe5e81662cd4a146f59c8e37072863a5523314f8f8de1d3f6e5e9ae33010001	\\x68a25275c8e1e1181749eae9a4c837243f4884cd83466d2ab78a19a598632796c3a724ccb6218a2adba3563aafb3975f1d643b87126ce0362d67ab98c2b91f0a	1649247941000000	1649852741000000	1712924741000000	1807532741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
156	\\x86f9a1dd386c3b3188cb70c46cd22ea198c0e35afe1a54481807bc04bab2821eba6a504ad065c8087162db679c14a3998cf74f122292afbc6e0cdfd544cde36a	1	0	\\x000000010000000000800003eb89a2f2b8233693b412b667b78a36f6bbfcef6a28b3b03a18b1f96d93affef64da84e22483f5884bef8deb074b5155fdfaeb345825d58d3c6c0db215b04b0467a06f59f349d287ebb66f604f9a4aa8cb8ed847e25c6dd839faf4f3cf4106b74978e13fca904e1101192725d834e363c1a343019710f9d4a2a91bcde0932c5db010001	\\xe840123a4b2fce59dab8f9da61499ac5a1e9b46bdcca7fc04c319e3f62976216f9f2a4c9f69d7414687159fb47be930cc10288b02c61b3b7fdfba7401d0bd00e	1649852441000000	1650457241000000	1713529241000000	1808137241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x88a943969fc8d3acd7519c3c0c657e72a8db913a7508e8c5d51a568d09f30d661e359bbd1a2486f21af06c60eef27142a7b031ec0cfbd146fd144b6b6c3e2a90	1	0	\\x000000010000000000800003a02548d57c0d4fd25641f24c3576e24adea540744f2d7bf58d1a04721a26d70f57be1351f31d268b8d2f8728f2668f787a3e553f4e688e454f85b0985e2facafe2d934280df06feca72276e328d1389fc266a64a24e460067de7727e4564ec623959823f9fafa506005ac4427db53e52a51d26c5ffb0c98c24688bc66ef6ed17010001	\\x88037cbf29f5075b6e43c1ac86d880c93df99ee9e9c0c9d3161bd9b87f7071d29408603612194572464deca10ca483b3b29e61dfe05c48a9db886712ca56f604	1659524441000000	1660129241000000	1723201241000000	1817809241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x897984ddf6353decda4af85e6641dbb3b80dcb2276e5000150260a6210c4dabb0bbde7b2e30ae772d3fc840bbdbbcc2c5a26be3d566f952e6b17a24a5656fb81	1	0	\\x000000010000000000800003cf634a369bb54b06d64dd391e187840afb1322be5cb73a21dd8a2af98c915027d4c29f71d5e33fd95a88bda960557812343d37365a621999831b691f7d1d86fadbc797c746f398e5c2f314d0bff8ff6aeb22868c2567e934e9c737e0cfb585c999451ba2d43d1f53c31d1884baa333084c004c92ed288c42c25d0dec0156d43d010001	\\xf238349ff4d53474ce2da1237e7ba52cf4f4117e8578a02892d1d2d88422662d4b60852c257f82528542f19786b7c6f8793a0021b695baef741a73026c798c0f	1656501941000000	1657106741000000	1720178741000000	1814786741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x8ae1649ef2e1c6aed2360556f25d5ed6c75bfcce20346edb2d014e15bb317979b505d00cdfce9f37fef311c8c943a2272791e77f03f26fecc2d562f55feac6a8	1	0	\\x000000010000000000800003d24ed96938cbb0d832d4a6ad82ce183b3dffe3fff1ab171a3a234d067196f5b0e20b3630760095b89af1bc240b2b5b2c7d8b55c7d248e19e65a4ed94141a2ed8c0736cb28a236de1002cbbb75b1c0881f7400d2bba7d4f4d7c188a5a23e14f78802607eff93a14eb90fc2e1d6f4d28009e1b85928b5cc250acca1a66e46d99b9010001	\\x9cf1b8861ddc7dc4d719baeed2ea450e4155796f6f637a3e4df88690868d635b4b96c6d14430336f611cf9687986ac380e3f63f53ed58e2344cc4a53bcf0c608	1654688441000000	1655293241000000	1718365241000000	1812973241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x8cf1b83a61253efa9ec60e7d3bb3ca2abcb881ecf8af1e8c3e3c6ce2d165079e10339790a298133301c807876fd05d307ec84ae19a14cd0195ef5f795c69fe3d	1	0	\\x000000010000000000800003dcaac64afbe06e15e8b8ea81803747d6f584233c50166814e61f783a819a319e598fc06a41237e5775a8104472e3ca82c74b65dade81f6d743da4585ad84d98b2e5b9ee47d3461b45c8008645f0da197e082a2f13283e6b87a31ea1dba2098d77b25727c719cfb604fd771498a62ae4254a8bed467172eae10e722547f4fd8db010001	\\x6a2d8d0c53d4b6a46d6abd2c7d6f1315ea04f28db5777dff410110985372c09e97aaf891457bcacb3eb5cf5f578eed883356aac784e569d8f4d16113b3d69905	1658315441000000	1658920241000000	1721992241000000	1816600241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x8c493fbc4fab2803a8fa699087e495418926ed8aed5d9bda9ab4154521b1321a70a975cc3d89d0421249535bc222f6f702b3ce77dc9966fbeb7b069d0703af13	1	0	\\x000000010000000000800003a5aeca5ca85af62b3db444077d6579249db9a7cc887f6537612b7e662276a51e2120fb5536a1849a4077cf0cd9088d0dca3c044bb715df76f2c39078d85ee55d2c9c01f805b0567771b0229d5594b0c5cc10128376345dbfcd73a024fc5e2fef664af6681b20593c77765f3df4a106e5adc060beda1ac2a1edd2a9e828392a6b010001	\\xfc9cfb5e344cccb19cd851f8b2398cd5d05033d9ab8ea8a3e0c5ee752534deec9e3853572f2459bcf53fc1f80a27ed1c82fb481f3c0c53ea6ed563711c0f040e	1644411941000000	1645016741000000	1708088741000000	1802696741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x8ea1b233073595837de69d526abe170e11b11abde4e881f4e1cf82698d0ec2eefe3e03ae130de1de5b4e866b159e59ddeba30c5ab5303d1beb70a40e8dda492b	1	0	\\x000000010000000000800003a13ea68bb44770062090462d5c0157ff6ddb98fcd5ec14c9957dd8f84c3a1d70c2d10d4316bfb5daf6547a3a740e714373fa52b2565118704662d1b3aaa68f4ffeaae0b1db36d58844cccbc6609e59e7ba573d9532a89227b24508d588586045a4b21ac9b968bccfe80dc90e37ff578f7c7f396eea45ffb9cfbc3db2ac8c9c5d010001	\\xdd53603eba287bf4b09bd6606474974faad2777f8a76d47ece2535fc6cc960e6905c7844bc72f62664a88961737d885a0284b7fa6198157e432d12870642a707	1655897441000000	1656502241000000	1719574241000000	1814182241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x9719aae38cd9493a3868e4bb7d3b3f579297ce5c206703e0571ee695ddbdd073826d851983aa899ca39dc68929ffea677e8ac5af19ac91d6b9e25ced2992cef2	1	0	\\x000000010000000000800003df609d15a6835e8b967a59aa268f7a8e1ca314d7d58d834838e0f0be3099c53b4374624840b75ac8de329d7516e2783af68fb77026153787023cd714dc57ebd1a4d9f48ab6d3fbce31c7a56a4ba40a70cf899297783ec99403be9dff790f00392a650e93827e32374b8244dc648c27ec211d25f08c883615e283275d7f1c60b1010001	\\x95e96860c5de90fa02b58c58879db507e87c93737d3264add8129da0cf1c54a3d000c08fbcbdcc7274bedec474a50f32658c982fc204da12bf13636fae8d6204	1653479441000000	1654084241000000	1717156241000000	1811764241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x998dabe0a3dc4e620d5a7923cc59a5e88e9f8becee5436c7a8ecd105e44ab97e4c75813096f6fd77be38df48a34be87f2b1f167599a7a1201b448416066f9e77	1	0	\\x000000010000000000800003eb4a3f69b6b05af8abceadd9bd25c78e3c7bed6821e9f021c3b352c574678261e633a4f0d939af419e407caa2ef59c1b6fd171b7543e8c209a5eb82d57a6a6e78d253113006ca6f15241b3992b222ff67c21c7e0d9b6d1c0dca4643f6ed31deacf89d7e23b1bc2d100fc040b318e20a90a7859f17a6c87389ba0fa0a16e3cf61010001	\\xad86908c7a2740646bcb437ae6c598a7afba62add9a529a678d35d640f5f72c5ffafda2d610e86b8e70847702e04699da7dae92ee01aed7c12ef9e67c5cad70d	1669196441000000	1669801241000000	1732873241000000	1827481241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x9f41f27e915716767c7877bfdbe8edf1e29edccbdc7174375c011b0629b852b1e43edab3c966270ae447c692f453218f9956b897faca90c6e077f691438c2c1a	1	0	\\x000000010000000000800003b82ab7ca33fd32b7601eaed0ba6e8d9973de495257320e2d54541ad77ce0e84c4c6ca6c99fc81fdc48827612bbd4ae48a66e4a722e3dfe65b0008fcf9bbdeff074fbd6a2b2cdcc18c300e8a8c50e88f99842f4bd4235741e3d8a192c49baac8afe49be205fd9c902ca50fd5a462c642ef8265d8dec0b643bf0c5bc40412dcacf010001	\\x6e09f97e32a0fabf214e7893b3498f430804d1c889c533bfc047843ade91645cc43861a13eba4566a64b6b881d8d0fc457f037196090c82b2349b770dd995602	1638366941000000	1638971741000000	1702043741000000	1796651741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\xa1359742da938611c1fb6f81bd19b0a07bd7b070ebbe5dd465df1c960027bf5719c3eb65332ec7e06a890370f3056a3b0b2fa8789a6af82cf49ca20214b1cb3b	1	0	\\x000000010000000000800003c62c80c18d65bfb39f5b90cfa25fa0f41f531475becd1c994d92d542468a8ee4404acae1bb9cb1bfe3d4339d26f88f786ca0d465d06661dac2cdc81c4c0c488a3592b8fb9a62e08ff791cfbaa91438c092d0f14628886a56891cf5ce2ff7a4f4cb43b6a438e5822246b588300223ae1f5b97b7fd388468c078393ab9598c21eb010001	\\xae7e15a0116333e70add9d98e633909e8d1fbfc35df28f33ca398de98cac5f60552e719ee29f741414b795163af2770db1cf1a8d18b2be778b2f3d987354c602	1646225441000000	1646830241000000	1709902241000000	1804510241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\xa241d642704a27105e8220bdb4ea66127b0065f489f85815b75cd5f5257492092f5451f28eabefc16eae761737b85addc9b9069074d4cba457a892c1335c0f8f	1	0	\\x000000010000000000800003ca1dac06c9310538489c1d7a92f63fa7f089f7882964a47156548bde120616bd935d63a54c01b0c44b70985ed819ee2ba735250da96c6aaddfe76aa1f34ace26d5d10df5b1726f9eb06dd56e0d9a984f9942300a1225476a4801f9f7b50f73b7b6ba9c86d202c0b111a0415d280e47361cd4bd15a16b4e58df0c7585e8c930c7010001	\\xc20bee99434a3ff9b9e249a6969c21ce09ad52f26f366c0cfc4fdb98760717433fcae23f23c6949fe5d2e16de058b9bc48574a529e48c79d34e562cf1993910c	1640784941000000	1641389741000000	1704461741000000	1799069741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\xa321c2406139244f036a179d1af41983fc34eeb919cf7562b2ce7a86d27593aade336c14876caf4a143fe1185cd8359728665af2af1f07a752077f0cbb94ed57	1	0	\\x000000010000000000800003c579bd17b20edacc7ff7e65327c92dedd095cb5a7418e750f2aece797d22d20e2c0ce95b0670ac9605a6d9a4ce3d9fecd73ab2a0a6e7e3b96048857ea4b1195e7fbeccd7011b865e584ae534be2f71b274ea383e57f128ddbd37045dc75e6b44e44789f941b87b358954656615bb04fc1d85d99b4739a630310261ab6e29dabb010001	\\x083a87b2b1ff2a11b32cc056b51befe697453f09f00dd7eec6bfc9a166f567f5e34625f5bcc59329fe5e8bd6782099cda37e9df58103705a33310045c826230d	1641993941000000	1642598741000000	1705670741000000	1800278741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\xa4659d4301e709affdf1503efd2d4bdc31a7e4992ba323b6902496f419acb03cbba31b33bb4c1b11784c999894145cc277551ac8a6e98cabb854c30544ff60ed	1	0	\\x000000010000000000800003c4d074ba077bf2e34cf4e6657eb9300022b55ca53b22eca529dbcd416ce088e451ca4c5f743043ef99f4160e11fe1fedef250e3d4762e3200809d6ab73df423cc6de39d07b37a1c82f3160706596d482defc0533eab8333d597a1372e707ff4bf60216839ab0bfa65d41a247460db6b24db5cee489855f8e55b5a9e5da5b6d1d010001	\\xb9e1d238a773cee654ebffdce9cf21bf676925f3b3bc3d00fca56766820244016c854692c721efc1c51c1609d7eb38f4e584b4bf18d732a6d6bbf0e4b6b9810f	1660733441000000	1661338241000000	1724410241000000	1819018241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\xa4c9aa9fe2a3ee09ecc5eac4890c2a6cf54a31908aaf2e4c0d3c72802ef5bb9b02921d0bf25faa64f6c7f1573bce7492de2b9233b3b70426cfc53282e7d7bde9	1	0	\\x000000010000000000800003bc2c7e86c86884d1c6f1c939d9cc6159dd7db7f956ab759d21b4888a5cd7967da56bf09a8c38a4def1579028f96a15e29f70e96c038162971d7384506e240ab10e0889e1f62f07934a93e08fe3792d150d77b24d2385554d1e9845ac62b3d9fe4b756d66fb99637da1a9732be13c8486401a593e1a266d06e0534f4bbed0cff7010001	\\x87b6cf6a182a6d01b3ae68bcb55e20063aad203e459cfd12494c482aafad027349c4ae587c887689f2f3dbb03b7ec4e6b983bba1fd8661cc3f8642f53c4ca30a	1648038941000000	1648643741000000	1711715741000000	1806323741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
171	\\xa59540a8f2706845b9ba3fb3dbefcdd780829accdce8958917301ba39f4e85fc21c9a31d844e33319fe35c52d697958d1a832618d72576f106076b07f9025454	1	0	\\x000000010000000000800003dc83bb477d0c2ff0385aa4b4675f3e9c44b6e1d646b9ebebf575a210f48426c5a94f15b4373c0cb66f39c00d30c50f839977a5da82b08454bc917f45a1ac9cd8fbdf1ec245fee9ef9ae675ebfaf028370cbf5a0a0b004087163805cd5f4c9902d562eb4c50e027e659eeb2240117a1c0f603628769d6a21d904e890b501038a9010001	\\x5a0c23ed52498fec55246ce96bbfb524824cbe51d7ced73d31c41316ce6f0de80278b8cec78257da74d63997a24e0cd2c2d4147fcbd4e1409d77b5c420a8090e	1652270441000000	1652875241000000	1715947241000000	1810555241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\xa7c940fadb5f93a43452f548633ffc3bb68af3d6bbbdcdf2f47510c8695bb702b22f454cfd51c65ca71ec5da493aa730f77629e03a9247b05d7d2fa2078df222	1	0	\\x000000010000000000800003b0ec37fb3963a8770aced84839e1a2be34d70245cde0998df9e7d65732a112785b4aa86846b730981fe05d5c63fa943587814349f2bc6169775881dd5dfdefbf4218af29e5de332ac9c62555e35c431cf9eafc10fef2b99b729e94f4f3c5bf97c901c5f4cf7dd81f80435c9080b93754725f407f95eec9c4139a2a8235225bed010001	\\x742492c6ae8b66b3bdb32276b58ca14bc1e65eab9c0deb27d77c80fbefeb96b9a94bebac852e500deaa01ae4d91b3fa7a017c0bf446d2ccc9c3a50b24575fa02	1645620941000000	1646225741000000	1709297741000000	1803905741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xa805f846a0780315b85d4ab3f417b3f7f4f7f5af42c016cbfef0f75f5585dd24f6781bee7cb26c3390a441fec85c6ccbe32d61dbc598d6438639bd7ad83f6a93	1	0	\\x000000010000000000800003a5fa5f3eeccb0f487c2a9958cd221a0420fed2fa4fd159af3ed08d646fd4ba84da3a93e3483395683531ef326b700e26ebef05835e33421200cebadd70c6a04c74440a93933795b042efc4abc889d7fd887c696f362acf8e0ee9e77720b7f7809714971d600599b9c54450cb09157abd47bd49ffbd2269d9a33668ffaea70221010001	\\xb80468e57775ccd4647e1dc4984aa313306927190591aa642e2c0c95d65e888b794f826e7bbac8354b6a75f519e77c25ff213f330ebf4364b885d6a948e93107	1659524441000000	1660129241000000	1723201241000000	1817809241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
174	\\xaa39f5e3da0c5965945ba77576d2a28db91ced68349ad3ecc12dae24c2b120bdf4628793a34958749b13d055c970ec93a1fcc9135fa5ab0c6ee4821981437286	1	0	\\x000000010000000000800003d9784e8fa795abf1a7e17490614612a1c65e54c55eb58c1e3abed72a2d05f262f688616b1e8e4d0a2da8198787f3619084fd1962a515719b0b9bfdd947eb7415e315c40a52a7de13630a6befa5dc3a780f24b2f96b5716464f3fd39b88904c9ac4422e621721256ed1ccaeb797bcc0e98ef8ac9396fd6bd421ce3c0a2131223f010001	\\x22766233025a6c8122b882ec8eadd5431f27115f73bfb012c0e0c639efdbfd5a04aec74284cfb55043e23229ea4178c161ed996034d236cda7e2fb5363e24301	1651665941000000	1652270741000000	1715342741000000	1809950741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\xabd5ea71b7fdbc11886e1262c19347cd769d6d1c34404a7e1319334cd3e8b2a77d7a1afdaf807252bb1281646ba096e89537ef0a2732eba2a14b4ae955e83523	1	0	\\x000000010000000000800003d14b457821f587c81a058638bfd648f28b3600dbb44669612650d709e48ae6636e51247ece784b8fd1b49d7b016e28d0316796113a2dae950635c0a306f696e61bc96ad77e25217ba3ef19fdc7038b716978ea5d56f27a298c7a0753e0d3766c04ab39025c697157983b6cef35a44769cba1277068459383044024cf15275e1b010001	\\x6f15a4a65637db92b283ccb09cea30318388d11099b5bf1916b3668d019ed9eabdba43c9607d958f719f4257be70d522e5adba0bd701f5c3dadd81344a016e0c	1657710941000000	1658315741000000	1721387741000000	1815995741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xad49f2276e63b0d39089768fa370445ee1c0cae55a75098fc1f38cfb2e6d754aa4cf2d587995086cf00318a65087a8b292f3e50a46a81bd6437752078e702006	1	0	\\x000000010000000000800003a808267ebd5c66b26ef94a47140252548f28e1926f4717abde12a55aff6542ffffd5341fe6e50a90ad991097e3ed66300d5735990ea8e33365bd656606fa6869059f390b108caf1f0400a0b93be298a5fa8ce40cd9863336445172c9dcb634083df10a6c716d9811513e31616d86cd5a60ad6229b0d3b43e177386edd9c255a7010001	\\xfda8e319a2bea707894ee8f2fc46d99bc7138d3f9344e4cae49861991cfbc52ec5a42cac594bb6f5d700a5c2a58f851e0c2adea6d3a451ef10731beac0df4d04	1661942441000000	1662547241000000	1725619241000000	1820227241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
177	\\xad6d586fa84c847668f0c86fa6a1f92af7989cfd1708efdb69eae4c06a6f0b61ab6d556a2827871daaaddc96e9243b7abd2b2e13862735743115b283d6a854a4	1	0	\\x000000010000000000800003bafaad2d71728687f1d7aee49250ad4a2fdca2b7de2f32a1cadaaa65ab8c9b45a3f9179067f10ef803e54976df39f6efe5190fd9ef6df22905834bc686f76745f3eb0d4886d1395f54f50db736da9647ba7dbf9e60b28d05e0ade78882e36fec2bccc9f4f4b329fd9b4a16020d10246439fdbb0f04b6290e5a51eb0af3fad08b010001	\\xe80468664417364af1232fbeb2bd10e5096b52c4b04a635a61d4198d3d821c56bd36d7d1955fa81fcff948b96b8a209145228fab61cae6991b0a7bd5d430db06	1648038941000000	1648643741000000	1711715741000000	1806323741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
178	\\xadb9ff3b62462833d51f30459ea16e5f6ef3d2647ba1790248acbb0c0fc8dc458f863b579df7c7e1a8e8167e11ee28deb93ed9f8154c7f0cb78e2834595ec038	1	0	\\x000000010000000000800003e685af947c8cadc6719d66e6e9c01142823b7ebdbe974ab4fbedc3063fe1a202cea2f6e1648216854e44633e6b454f82214d85edac4e5cb33383d0138ad50684335f646f812167de8130d4e190b705fbf9dd376a6db57916f65716e14c4591a516c249d838d3edd72e2764e30de0488d4b5ed7d19297c2fbbbe9e96a1018e2bf010001	\\x094d4ede388391e4304515d99edd302fbed5c3c391aa1476a1fb64c3a657117f385dd4419f1d6f841ce61c72a44fccdf4b6ad0cbd0c85b2636f60fdf3a9f6a0f	1653479441000000	1654084241000000	1717156241000000	1811764241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xb1e568dea56525947db0fc3021cd98de1e3af66715c1105dec8141676ba8dba7413e9e7321a663b53ec621497a9fb438253557c1b6578f4bd07f2d4b8d150d38	1	0	\\x000000010000000000800003c3131d2f5df8c964bc7a20b6fb1f331ba0fd22e868cad4a0f58241fed57f6b69d3503c403cb7eba376276823707bbc262e7cc90b10cc15163fd07c8fa7035dea81e7399be10bcf2ed53a554e47652ea05f3b497c9685552515285501e8f86fb7880ab7ac9571393b1d3d0e9e55eba6090a3c89ee02d9dc05951fbff6da8f3a21010001	\\xca039905ff1ccfccd0f7cf65b1e39d8be677b25e5064b89b4a92ce89283d50ddcfd5b4aaf136a8485ac6d137fbf1603f5c3372f3b40770e1cb828987dbba440c	1666173941000000	1666778741000000	1729850741000000	1824458741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\xb7d173e3754331fb7bb011b3efcdd33f0cd82a5e85b849033f3dca27607bf4d79e080bb36d29066592b0927a25b3cdcf7864714fc38de6a6402ac59c48f7ee27	1	0	\\x000000010000000000800003c31a779d0fc8a596b4d81f38957b3bcdde08d5426dd1fea61695f9cf4961ae5780e1df4598828e38f42ef5545028bb855342d8a44c592d42e35f1de1583e1c7d003fb2c8503c89d5aa59acd9710244895848a0479031f83ae2ab6ce690a251873d979ac390628795cc1e132491d898ef2ada5f10463f726017e8375a02f1885b010001	\\x3bfb79b1f28ab7cc728cb78ea83693ea36d9ae2a03e6b718b2ebd2e32edd91779c420f203b49dfe30356f7e9c61b631fefd15a31f1497418f12ee4f9f539060a	1661337941000000	1661942741000000	1725014741000000	1819622741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xb9ad89ba989416d95f0471653f284d1681f297cd02cfc53040dfb7ae4e8bb9748a107dec7eb4fd1d45891ffa64c2ebe06d9666e4110f8c70deb81b2773181dff	1	0	\\x000000010000000000800003b027a5aa66bad69c78d933c94160a81db7496e8cf9a73d8adf7932b0d1b6b4f67961c897b9ed82b2107c213cface1959eae5a8ea33c1a9bd6af2823c6d542b6636b5cd2c7612143ba176ebbea8735a03b8cabb3566d234469111f8dc79d537a2298f8b1d7e486bfff2e72cb7df08c52ef27fa585c7945f144743ee1d428a9363010001	\\xa0c2603ed405d017e2ce303dfe3835eb3db58549aa65e107055f878a4a650ac599a88b76e9aeb03df245d6ae694954198105057002da979f1fea367bca28e90f	1668591941000000	1669196741000000	1732268741000000	1826876741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xbcd534cffd89aebb7e761a2ca9cb3e4f1fd3b3cb3ab3d8d7e665ee1b0f5be08b2479c8c14012e5c6b9e6c795ddad1d9a6de7d8ddd45cd2f1f2f9fc194b8edb62	1	0	\\x000000010000000000800003abef5e01b74c6b74569367f6b569569df63fd87f5f5978f82c6c14607128e673a3dc51b0ffc3dd1eefcaa79ca019fb0f5054507d96fd0555f880d2441f43997c16c8532b6d25357fefd2af101fb2a0e597ac6a845d37ccb2847067cff6ace428371af004289e71cc2983820ac53f4cef94d1c316bcc61f8ce1c6ad788042e213010001	\\xc957ad7321805e6fdb2a07d1928c1eed6669a979b7819450103fee8ff93d8f4722ceb3f5d1cd806aad8353236e5f4ee2926126c4a190e7407b3d3a6dca71d504	1638971441000000	1639576241000000	1702648241000000	1797256241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xbce968716ebd68255df00e1843cbd079de16b60c4b4f3e8feee6076e64cadca11b468b3e3570fef91825c7cacf31f6bef5841b67936d793c7a4e776f431b6e1f	1	0	\\x000000010000000000800003be838ac9eacd446a0b7cb3928e0f595020d726c6ace5273f6cba997e7e74b26f11298cf99ddf90aedf49c7b2faef03f63890ab2c6aa91bcde7a070b5c04a41d74df2830cc7ac6d2d8c4d44e3be70c161a225e7309339f9ec1b57cf6e72a01c0c24c885f0c465aaa4930112dd9c3925fd084ab65952b045d615102b1c2e557557010001	\\xab55183d3eb399f6ded2afdaa4541f31b0505a0552125dac08aeb5981410cdb6970a9af250e5e8842385a39fbed89f427c8af99929be2fccda3e9391ccfe4902	1662546941000000	1663151741000000	1726223741000000	1820831741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xbe9db2fd3667cbba7af9d0fc6f19ef38258aa2e59e92ffb1ba97f15f8a224484d3d9a73462f72e8df4653abfb21f1e1e400656fd10b413662022c9c28313f97a	1	0	\\x000000010000000000800003d5da846f8639158318a07c6e2ba9f172f80f9a4647826d5850841fe0fa2f4b34382c2a0966e1031a686b1c9e9c6a4096c91195a620b0b5f5122523096f11382ff65a86011b9062918ccf1cf65676dfe6e3f15aa0ad2567971f99fdd0eef955ba41262bc16d612e3f85ee0c55074e983404d4e59368f21b6e912623f42b8a22af010001	\\x1e09915425d9a4182bb77a4e3480e00ad04b5e64f17c39b6bbf067c36dcd99fcc9abb230c08d4baaec23bd32c9d1541e4594fb0d3268f6eba284934ddda74c04	1664360441000000	1664965241000000	1728037241000000	1822645241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\xc169f9af937e227c23b68adf478b2d30d08f30e64d856af8650304667a268eb78dc576179fc0bf622c6db4ac535cc108616143e866f35bbbdec5fe49e4feb18c	1	0	\\x000000010000000000800003bbc12154c30a3dd41e40a07779c94721f1d323deb9b2b6d8b375d939cea920b14d1e7760736dda82fbd958d320360e9e46e133edd78e3fbb30069b9370817cb8d5680b446772ca3f84860f3dc19ac569acf3588c3f2cb8683e96aee05c54af39e0250a3c9b890c4af4a55553b1e632bdfc239ba267965ebb612e9874ae9a54a3010001	\\x5f76b883ebc1e5afe9a66d03f2c0955f9d99a4477a98d5c3724501a5a56cff8cdf74b3ed62aab74523f00a6208372864fb972ac018d5c7c6bf3e1423640c1700	1656501941000000	1657106741000000	1720178741000000	1814786741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xc5f16e7da021c123178bf3a9d07a50fc50dd2f387f07347452e9326fafe51355570634beb78cac16186ee6e2d2310dcb08c045e1b549f9e3cd1d4da80364bf6a	1	0	\\x000000010000000000800003e38102ff9ccf9e509646ac15d665178e814d81a6b8ff0891c15653c21357ac78b1f51e8bdf25798dc96ec050360695ba0c099f58ae0e4b56b02a81cdc373d3366d805314274d79c5b1f4f268df404e84422075057158068984a0ec5573faa141d3b2df009db836ca58e1a90f0e50615294e984fa7b299eea66f4b47aff513fef010001	\\x197824253a9f0e8ac82e12b59c931ba4a3f5794e937acc5d68515bb3cf0785afc92315c62e2087ff137f8a65d160f8f9a98f34afdb804fd74d431017826e960b	1654688441000000	1655293241000000	1718365241000000	1812973241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xc6a1f1e89e5a40e971d21c425d4e38d5dfb9ba10d9a17d3dfa0ba1f862db9ea1e431ab7a45ede08313d0c9ca96bb7c180e575a37888c79d8f18419d5b2ed2fa0	1	0	\\x000000010000000000800003b93058c48094352fd2f8e0407ff723cd3a65696afc96726c981e694b4d496fb1d8d78ab0ac393bfeabcc26d6d6e2b1b63a76e1c5a95c991694ea7fd4a9cc9b3f72754223350fa1d518e3c41ae0900774920602667750efedd02ef4171c0a811dcf1e9865017caaa3f5bd4459eb3f55a63fea2c24c80194ca474dbbf6edad329f010001	\\x7b977fa0a96e9c2f63d9241c1ea0b9d29156f922020fa7d917e663571ca924824784bc93cdcf24a900ea59e2d74aa6a7d0bd0c2c3ef42ffd0483245cf5ff3201	1641993941000000	1642598741000000	1705670741000000	1800278741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\xc915d9daac15cd610b442c89e14ad9598b6d375077d25d029a2c330ba332b71a4519cbb8e14a786606114ce57a09c3bff30dac358024c64419a0bdb8222a8b2d	1	0	\\x000000010000000000800003bde5b45286cc380640ce37caee258c5af07a2a29262b483c86bf306d010074e9dcf0ae9e23a2ef0ee8bc5f33d3b0c9403566335b5db2e7b460213ca7f3169b0806af809f0cd557e9ace86ebf5449f9f8f21eb092be6bd7bfc6cb73c915d74650f903789e287dfc8c21824185d014bf68eb0e00c4d9baf117fcc45f492048ce15010001	\\xf57617d5111240f2ce298f7ff3678943994c8da18faea21adf4621c57a17d98424518ad48196f07a847ddab0e36d0578029d59539d50f463ca9f9552f4584a0c	1654083941000000	1654688741000000	1717760741000000	1812368741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
189	\\xcaf573d1841a79fd8b8d805475b537b6c5f9408dd3b228ad077add2745348913d0f2c4a16e21da1c0f25fa4b4b78a32e940908d6c6b7c9e062b746aeef32318a	1	0	\\x000000010000000000800003b141ae0c9a5f94d4dc76ff74d8315f47eb231e225754d3829a455f092e05de96213c94f7f731b5cfbb95a79daaefe489d2f2b4d9b7c1a6f2095a1c82c21cc2a813321dcc3cd3fbf93cd5f7664627fe4e6ab7fc8066d41dadc16b7d94253998a0a00ec5f0c81e2e035256f264397bb6c5be1e37612fe72bc5acbc876e8f8f627b010001	\\x201260fbd10816a15533182b61e5a2647a98dd19ca7d4de718b012be945724343713af03e97e2c7da5cfd6dee52aff4ef40dedeabdf1832f111d00cc86f18a05	1658919941000000	1659524741000000	1722596741000000	1817204741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xccfd6545fe4f00c677892891096b8274f652ad30f86e77c8641da8628cc00c98f59ca2be63963436e221ee8814ec1d684b103f67a2156db2d311cfb8ba789f2f	1	0	\\x000000010000000000800003fc9ad5a124c6b69477d5e8ac85d06f28fe065cc465e79edeee7b1daa28b7b60685051d05e63bc7acd25f7c3de981e99dcde476539d5d1a74ebb34a0c02b00b388a3f3765c2b89bd7480e178ffe9ea086a5fe77d5ec034efc50baf17a78521d3fef508bd1e2353e359a4ceba63bcc57fc82cec652b5a3368e2edf93d4c59d4521010001	\\x14a42d6377acae4689c26d6e5ae2a3c7e3ff8a134bb3aaa34ae3602ed435f6006b1af733f9ecf72fab11b42e87a278fecc96b6e28e3424fff4c609ff18795c04	1646829941000000	1647434741000000	1710506741000000	1805114741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xcef98cbb22efcc9b5b63b2ec640d1a85c77de7a0f9e536583fa2c77d9b7721f7c48ef429513165f849be4046e9b98513f40e44495ede0a0e4a312018db8b5de4	1	0	\\x000000010000000000800003d74b7870160a01e5a4b79e009c75d7c67e96bd7446a0a467db49d50cb527ba4695274d3e9fcd21cdc5ad90749a46fa0f4d1bf9de71b9e2a060c05576dc34acf4902f4794eecebaaac8376431e41b54726420146e00bcd54eeff87f345f9c57af7bedad7719f8e5434a9cf99cacaf641f7a0b3217493c4e3b897e6b49d3a4b437010001	\\xe8adccd0456d421b99570d3badbacf8ad7161f053d3a64d4f3de45244c74403e0399fe2e297fcb5386ca3e1f6c606c2d7f2eef9d42dc7bb7380c3ad5af440707	1639575941000000	1640180741000000	1703252741000000	1797860741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xd03dd39b122e8e188fe3a4b6bef684b2cfed653112d882434ff2fb4a60157df165b89522785f24234ecc888dcb9b3f156792757efd7b646e8940de4ba21e1858	1	0	\\x000000010000000000800003bb482f25d36fb6bc0b46397aa9ea3d55161d5ab8d2bafeb9a10193b6858cb1ab606344d9119f05352bb233962bf3f08d6f6f1ab7802d25e96b69e75c87eb8a8d34b0929d3bcff81c855e79c77e029483f26ac02600d09892ae1279b6234b6f02f58e2028a339ac5e7484a77b051519652f1e4712f95c31d7043a7ccea2ae25db010001	\\x34bc60f55886cba95c2fc986a2a8ddbe9cc5c808c41c109d73004040c0bf90cde16e5b05c4726213da092e84a7bebf0820c16a93dc329f4a3a02fba2e6c4260c	1665569441000000	1666174241000000	1729246241000000	1823854241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xd3919f6c4910a1b01bb46abb6fec5ebb30130ba9109f888e29b65a5eb7458b710923ee70adddfc9eb3faf20a732ee7d5314188f73cb15be0ebaf4023d28f9b5b	1	0	\\x000000010000000000800003a3fd30aaf5ed05622a819e580c18af3c3979f488dcf2ee3e1b8795a6d76794ca322b0e278a0aa003176c79052227dcd5ceb3c717279a810aedcc3359c76b6a4428306c9347ecf720df7b04a41fa90849d70ecb42713cc4906b4f1358d9dfbd3a2f929a52a479e6484f12b433e828ea9897246a69e90cc56f945b801f2dcea6a7010001	\\xc68eb1d524689c8f59fb8856af112a6b5cf53a6415cbe3b95c8cdd5169c08a3f19e666cf9b282ca47b66e80636ac7cb3d2c4c77855e122a7524651c28998f00a	1664964941000000	1665569741000000	1728641741000000	1823249741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\xd38dac135615339960dc90e10fadbbc8393245ce9d89a6397b04ff3b50b1f0cba3d6fa3aebc2d82626dd2d06ddcbfcce75166c2c2ee62ec193cf6b012004deb7	1	0	\\x000000010000000000800003dae9cb624205a3b9add88617d7b95f5301e01c062392c9e74f6a73f6adbe099489e0401572df4cb26c2739c245f50750a31940c801c6ec8f8ee5d9b6836beab7b1ab32ddaf72bf940f050a70504c071911130daf3f28f5a2fae9857a5add9135807a80ec40008cad3481a9bc7f90d62afbed1d1c6cbdb0b0fa041f93b4dc5651010001	\\xed6f16b9cbbcfa558073d4bd582187ecf1775ab41190e41a818c2b768107080f56b30988753739c5377ddbc9c2bf771c53dde8214e58d30e085e7956745e3608	1655897441000000	1656502241000000	1719574241000000	1814182241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xd33179d5662a79168e554c9f37afcbe3dbf8f03a1604701ccea6a960e1a13e83f7f29a9fce44b0b3671835bbc1e89d1ec97652d79c170a5eb18279a34c3ccf0d	1	0	\\x000000010000000000800003c9e602214e29910334eab8c501b089618d74943fa7d5e82511d0e629c10596dcab756e93295760183909bf179eaf4738f85049862b3b3a6c87c38ae6bd9539f3af534f031f4625d8f01e52d12f84d30ced1b75c7098ffd1c36c9a1277be23a99846060bce79291dac215434c30a7621876a3b448b17e72fbec70fdddf1740e61010001	\\x18b4153b79267bd12ac4bb05797d3d872cb3e957c95963a917f4d05f05a40d70e3f38a99ac4c678c21d6de8b6c7fd2be2b482564eb2fb7bcd5a5b04d26cd2e02	1663755941000000	1664360741000000	1727432741000000	1822040741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
196	\\xd48db9364473dbcab4b468919eb5ed110f46737bec5c7bdd545af42ef88c9d97a24247d4a36bef5383b1e0d080bb53b05436294ef6ac4aec26fa730a6edcdf9d	1	0	\\x000000010000000000800003c8d15d7afd45dc80a6635b978063b9edce87a86f8fc14dc2d5d28987927422f53440c13f91579cf8e1b9922509f8ebb09532eea7829ddbd49072739808eef1e1c4946a14a7aa87bdfd64386bf6e48416bc8746bcbb4b13e53918df96350525934d2c47ef1a73c88545780b7ff388e3321118cb44cc28272988ec17097a22ee9f010001	\\x685850d48aeea8941ced975b43b4919755208628b467afb76a1dcc7d884092850e57573f9786322ad43a03cc41f724770d5c91c813153493507123f17970cb06	1666778441000000	1667383241000000	1730455241000000	1825063241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xd6f50c572300fdf6becef7f259899c17e4aa47fa435902a01ee15869abb21e31d22406d754d83932ba436dfa7df41e0f83140293b5c51f3674b7d2d6fd8c5b47	1	0	\\x000000010000000000800003d1c3ab0aa91302e2f4cd47a2ce5710147018f8ab4a012a554a036f2006a0c6c88d00a9b91bfb9ef04a6adb700df4a761bc5713504f7c9d614146fcbf446e0d6b6c719e67e4686e0ec97c5d16a3996458455dd1ed2de4ddeab375422bf15db5d6fd834d8315dce0ff1e32584de09eb6e687897d8135ba17ae60f449917797b561010001	\\xc38f700e3a2a7169ff136ee1ef96d07693c53ef34ef555e33d1acb3570427f2030fbf49ff2089dd4ba5f0cadd83939af6929b9a8373c684b48ac6ed89fd0b104	1648643441000000	1649248241000000	1712320241000000	1806928241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xd7b956d59b11a54c3809d18cce64de14a8adfc7c6ab52c66bc8f186e61ffc19079a378991917a3b4d9b0ce5184e8a947b7d97a4d96febf74f419ba662ff37b26	1	0	\\x000000010000000000800003befcc04da7e8d5f9dd6b9f97c7d90c7b0fff56cb9bbd9c39e105a59bb287fb9036be978e9dfab5c2b1e67790ea6c475e6e0236f8e5ae5a147cc0b6cd2feb732197111c8b1f48ca54e3219e9ef51656b477e69ef6510a3003c44df0fa48600bd724ecb5cbf798800115f5b5472e9d9a7ee21d7286cfd01bb88cf4794c9141b031010001	\\xec45588d290b87bad276ebd65786dc53fd27e7330bac31a3dd0ac77f14ca2c87a38a00dcd9311383be3d8d6fd6873d39042a404cfdfe1ad95a1ab07398482c0f	1651061441000000	1651666241000000	1714738241000000	1809346241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xd8651dfe18c7e22d450f56ac302c5717565350a360a1bcf671737924143148e67e7c231c0e0a68cdf2d59dace92defff14af9bd0109688c4d4f8e7a9e974afb0	1	0	\\x000000010000000000800003bc1b7af188742efb845ebd18e29a53c52d793e31126e470ef72c7a723e363a5ace37f1e8b443a8fc8eec50530a5a7923f26fecfabafef02420a92a45c60e3086c5008d4434d3a97f7a9a2ba2b7cc39f36df4c26ae183c656bf17154f49acd7abc7b4669e1125edcad45216a67fdc9a4eda4e295c1919827eddf871185b05ff1f010001	\\x34131ec703f9d4796e2874f22d09e1b6cab59692edeaa37c99640d048da3f0115d927f108917e1e2428a6026f34a8eb643fd2f48204f3edbee0325246162560c	1640784941000000	1641389741000000	1704461741000000	1799069741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xdad5f2d3551ab0bd3ec098e6afa65b3291e8a8696a61b452cab3d79bbdf4252bc58b59a5e59cd26f225c65a9bed5f163f13ec44b61fb86c703ac319e1a387454	1	0	\\x000000010000000000800003d48c2ae3e84e3ebd82ffb54c6b1b8dc25864b7901e67fd514a6fa2d5c34f2d9f136cd988083ddb2c5002a74dcd42b38f94d1442eb16acefdec760c19c5a90c33198a6fac2837672ddc38974cc03a02d90ee8a566e921fb8445732dab47a34e30207d1202658f41a711ae2b90b38d49b0c84dae8a6471de71f4d9db2fb875fe91010001	\\x888cc0706e34fbdb103fe7ed884ad770fe3d67e9419cc7550d7a0f1db14ff51390990a9886c1d3d5a05f72259c2c985ac0c328247dc039aa0e1bd884f1b60d0e	1659524441000000	1660129241000000	1723201241000000	1817809241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
201	\\xdea901d15d39f9d4246a9c9c91a5d8b7d34ef665716486db5523a35030f04a929f426d70d926a10b34c34bb40c4c7e545a352a92b037e0efd05f30637ce3f048	1	0	\\x000000010000000000800003adcf3fcc2518681f4d4d48707b8cb6ba43944b58da005bc0f72227a0fe0b47f8e0b04a68ca52e09134afd64117e3ee7086f274b17f6376fc8452c01343ce783a144c72b3be6324c102c4e4d62fd833b2bc94b82178bf0d75cd4fd361dd01703ac7b4e82870d937666796b9a24bdcf179cf9f4cf5c6a1a87de0a25d77afa9f257010001	\\x96bf4cb26e94c899705245db8b2f7d65035b5d815ab669fbcb6eba4d50371070b5275077cd93aa68809f39c8494c6f2038f3e8a53bf9ac26e5275d57cb56c300	1655897441000000	1656502241000000	1719574241000000	1814182241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xdfc9a711ca9bbbe196f2976d9fbbab36e5f93e9698d4f26f9ac28fd8140045ff939297a600c19b36472fef42f78e636f49ae5a459a661f5559cc90143a4c0126	1	0	\\x000000010000000000800003af552cf43a6b7244869dc46717f9687e1a201260332cbcd780c84b25942e5074ea16c7f48c92ade98abe29a00349b44e2bfc6ec2a096e0c90ecf2e3852951a3dcfd297ce1f98b17ae5bdc5a6184ab8d736c45f4c6c74baff10171c69e20c5b8df39ee84514d27e886c3972d25079481925ad2019443077c7be0cb536ba82baef010001	\\x3b68e760821481b1bc32fc499ac33be4b0d359f23e844716d91267cb2660ee6623965a593f1c2d314237e3ed22749efd53e51c6bc3f33f24b8607c19dddfd90b	1638366941000000	1638971741000000	1702043741000000	1796651741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
203	\\xe4c9654e7865d4ab3de52f53375b6d76f840abdf66d59ff8f13f953a9f1ad5e8c3520ea71717da9e3fe4e64eab4fb4e4f6acce9e22ca5dc8ef18f4bca53af61d	1	0	\\x000000010000000000800003d3186a539b842d1d310730ab5610d213b18587d6f3d9ed17d75a7648bc00261b89b3eb9adcd42429d9e5733c905263cff870574df8a32c25609b862d946a368b4c3293be79a35996ff7722cef9650bb0e902f0c2424d563700a531bbdbcc36a27c6881731c3268c279e9f74a8fa10f2c2df995e5588e63e188b6c7f587e6bbb9010001	\\xf0020b2711b2d662a1b29c1caa4850ce466474a9754edb420c1e616ab904f3573633d90bc36086e06c70ec5f060d99bf5df178628d516f6a36352abdb0ba6003	1656501941000000	1657106741000000	1720178741000000	1814786741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xe569522e5685f89e62772d0f1c54a2ed6ce165f876df9d21d66ff465aec5f099b5dd9ee9a8cf059b581be05e90e38fa4a1ef01e0789ec95f69e780edcb880be6	1	0	\\x000000010000000000800003b427efdaf07b60cfd73aa833fa37f7ce1280d0ccbe34c64098ef26a881447473d4fd5ca99a27b84c5726e089272906260be523e3aaa57fd798f1088c3dd9edc922a49df32b045b9e60264a9fe610d69e14025b2dd1dd20e018130dc0a3d1c65956bf0f3a283c73ff322f6072828209b6453525a20072618f5cc7b5c5e0b21dcf010001	\\x600654ee87b01a7cbe23c2b71830f63b96ca3f11f26ffef6465115c333751246c394510c62b3cf8f915dc9fed4df02bea76997463e25698a8b1e0b84cbcbcc0f	1649247941000000	1649852741000000	1712924741000000	1807532741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xe65156f78402b33163b33591de227e8213cf8173eb71299b5d050e6a09a649d136bca2a3df13312dd2c62a7a435b3b0728feb7f29b86ebdfa2fb2ca6d99abb5f	1	0	\\x000000010000000000800003df2a03181423a6ec9740faea20633d6e2ab252635bea35e6de6eb683c7f25e6e6dd1139ac828e4a4abb78a4388785d766b0d8d0f97c679b8cb9ae42c1bfad6cd6c8647280fe4390778f0457f3e305163013bf90a6e012c83526e6c6d6ca11d2e3cd7e3d03b946112839a5abbadeca6bbf0e516fab24badd8f7423ad2b78ac0f9010001	\\x2970de1ee2efde742b10ce49562044a98c8d01ece381342c2acff98f8c1c455f502dedf566dfe7749a67407a50a44cdaf55f8128f2ce8bbc732eaafe4fee9c0c	1644411941000000	1645016741000000	1708088741000000	1802696741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xe68572118e1520476bd6ab3fae731ed304d80b2c6176a5ec0234009a3d4f5d1f3aea80fd2103f0f132be95f417e38335f9bca67d3664b12d6e04e3683e631cce	1	0	\\x000000010000000000800003ade0af820194a77ddb4b081b3149818d64f5905af52ffdc6c7348a7856c1c41071419881adb4bdae940e3ac84ff231b983fb980368ea7bea517b7e5d8bba5f016a393c33df0af790a2e13a7db4d5f6b432d79db6a2adda0f72681465625f57cec658bde88e8a28a7c8de22932c07ecbf411d09b8ff28e0d1192ce8045dae9e1f010001	\\x890e420a72db274d47e23bc3fc52409eea7b5543c98ffb925f0a63f0eda4dcf1c53c3fac4c2c672cc984d8129138dc43627fef9a71a410678def7f08df921f05	1659524441000000	1660129241000000	1723201241000000	1817809241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xe9b50adabf7703a0f8572cf452f4a59249cc7d3e6699c07c1f81bed902de1092198f4606e06d7a12325c22724ca8cf850519c675019f0a9fd9afa0fa1e031a37	1	0	\\x000000010000000000800003bd140040bb4b575d0ebb47ad28a565c1216dd10cb7267b747df67297b6cb7297871c8295d4909a6f4728273f952d66d84d99a34770dd9f78a886d072e1c8fc6bbbdece0cfc888fcf06bbeca678fd390e3be193ed02c18aa4ad44f9babfef83cc3f7aedde6c052d72487a4fdd569c8f243c6c760de4d99edc8f1d395112fcf36f010001	\\xe87ee15c2c4bc277b779282729301eb29467a7f45321d8cf1a6a4fdd92154e7f6cc93b363163014b806004258e882eb74f43887ae9222de31f094820ba81d202	1648038941000000	1648643741000000	1711715741000000	1806323741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xed4d1689489ad038bb88739e049556d1deea78da3ba01bb3f3b3f6dcfb289aaf1abe398a98ba46efba939e1cdf7a2fef34acd4d7b030ea355345516115ad7e8c	1	0	\\x000000010000000000800003c04feb3a691e9c76cd57c451238c9c3793d416465d91ca6b42fe704d6783ac57fbee46e3eb9eaa807bb8b8b46a56d8e48d157b10e6bea46908baf0b31acfaf27d7ce8d7060135802d6656f50434eaa27ca8cecc8fdd3c04b4ddf0ac5ebf4e9fe7d47e53955d2fa84ead2cc58a53d5849b47d13700c38c055397da51236e89ab9010001	\\xa83bae6bf15976fad79f2411b6c16e7e319cb1ea6b08e99f6e9cca16dffc57909637d4da0f765d4e8d9d6a9b29ff8bc0aab72803aee9c8d661db9be8cbeba90c	1657106441000000	1657711241000000	1720783241000000	1815391241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xf631fa08762010c85f6b36d06ef9658294c2730ff5f6021343f7e617138702d035ff758e5a67f462e1be4cc0204ab5ddf07302c5d18ea8feb0533bda62a60328	1	0	\\x000000010000000000800003ba07d2e39a2d0d1f1ec9bb7843762577ceb73b119fab0b49e8ab800ded73d1e0b06cb9dfbfdedcdbd00a1a2ba8258968f595a9a74811ea2a31d8c98885fa285d01e7e257c6ff495f20034b7b26f203d80de9e4b15a968716f3aaa980c97f4af11c88e0986f9fd05bfeab92238fe39a58ea3f947d5075e5e8a43fbaa96c7c4667010001	\\x790bcd48d8385bb165a8ca684e26851f07b7311b7fe4ce89c31bdb0365199186ebb285246c1ac982fce061a477dbd6b3e5a059ce6984995c364269d602158507	1654083941000000	1654688741000000	1717760741000000	1812368741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\xf73d7632861f1161b5077f96fa24b02a77f4e0f4f327e703ea8f0a2e3e131095b646e999593dc05af6b917d94b796ccfb40eecb06bd791117797f3e304ce2fb6	1	0	\\x000000010000000000800003e1e829fe16cac32d432b27f3eb2f4e4ce5af68b7d423e77b8861942c1804c19d6693126797949ed28ffabbc7beb19785ed1d80a7264667013b3a3312f81ae962595a8657663bdd41ee1dcf9a9c358b72133bbfdb0a1afa8218efee78ec8ba828d160e70373e63409fa2d0ce13f2b8ef2f3a5eb4b321e550ec2b842008a0d464d010001	\\x2c2a04fdc2e3dd1edebfb6e015846b5edb473e1c4b4e77e51a7cbd4d80d21160b1b0ea67cc3a85385c3d5210f464c90d116e51f38ecaa09e8d2ff93c6078df00	1660733441000000	1661338241000000	1724410241000000	1819018241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xfa69f47bb80f791c8bf70881534729455cda9d3cb427a5007294e7890a4c00cfebdc83db5c6f6f105f07c658960d9e3f245cf220e2250303f0a567977192d0eb	1	0	\\x000000010000000000800003a89fd05ea18a96712afa66ffd65080650ffa76b90f12efcae8546d105476907d346da52523aa19d2e6018df361b20030622c17b14f61f86c2f6aa66fb92a0622b3588b616f5a725694d0cf4e330e2f0123922ff47f756cc511f1478da9d8fc0d2c24f10c15e6f552f347aaba07aaf3e13f61a890219dd55007c24be9fad1953d010001	\\x1396c5a098f0374eb2afe76476092d604edd8bc8396727961101f3c1eb6981b74963b54d71a0bbbd806624e6cc922dae629c7011e83ae7515980178306a8dc04	1652874941000000	1653479741000000	1716551741000000	1811159741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
212	\\xfc697dcfd2555af070892f89d6ffc2d614d344b8c6d7d066b414d7bd94860cfc4e86287d323ffd6e20d85a4a1cda95c0d61b9dddc66ea48f3913ec0043c3141c	1	0	\\x000000010000000000800003bcb38a8f24a8c418ffb9c33372ece4b461e4e158974e50092fc66ebef5b33e3b7fbe927a3f0f059bbadf6f2838ecb776e5bd4a794ae3a2f8dd1a468555204a6ee857c4593fcdb88ffb864c32bb94f3814a106c6b8255776f65482c92450df261bd78b15623a46cb646df293628651129a29ac59cff33ae2fbac239b0683a4d65010001	\\xaa682cf853d11ace55cba1d58a2585b91dc548edda814549dd15e416b4e202463cbbf3b73ab606d5ab739069f626aec352b6904ae1ab4e728ae9e3f838e91d0b	1650456941000000	1651061741000000	1714133741000000	1808741741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xfe91f22143f2c1849eac7b27dea11700f185e6bf8345517830d7d956dab181bbe550cc5827238ba46bbd931a053ce0237c9c6bdb295965c0d6ab57652e5c1c12	1	0	\\x000000010000000000800003d34b193b0c515608f41688b89922bd9c247025f23134fae09e4f4a8b7881584a6bdae53e736389c99923d8e3d09e202362670dd3a0e7e20071bd17899d1db2c2bf03f050ad29a3c992f01ce06573a226c6bc0c2415ebd607f4b4e52cc709bffa1257659346b5298974c539c62344957e490fb4b1e828402d6edf55f444b91e2d010001	\\x93aea323099fa4a6ac0c26372950977e2fe58d785ccf80aa6a4866fc74ca86ad19cea6693d922d61b732e7268a5163362a94624c721c74f2754ce406e719e30e	1648038941000000	1648643741000000	1711715741000000	1806323741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
214	\\xfe01e45ab30326b2206c0be1dcdc4a30024b8c002bd3bd298fc70be69574a5031072d17e667d93c1e71228c48f902d5803b441fa87db5a1ca5ad14a5ff5e0ce6	1	0	\\x000000010000000000800003c5373eb6544319317c137c24b0c6e001d5c9ada1828c69e6761dc93655b0715f0548c50e3665a274b8e7b49f7216df8f4dae3ae9dfa29c2aced963133987c737812ee06f37b4c634c961b02be5612a0641981f1cc2ae85a887babdbdac72fb9959e7b2865b440cee15205237032bb58d7fbd37a72a8fbc89bd389cc95b55a4bb010001	\\xfa62e7fadbc19cdef48fde529672d578f733b4a24884b71caacb3ea1e038b493bf49a843bfcd7145bb234894f9f2c411dccea04b92e47be77f8d94cf46598f06	1668591941000000	1669196741000000	1732268741000000	1826876741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x0012868383ba21b8026c0fa01d980f369e0a2eee295629005ab2a5f7e11bb2400e37e09496abc1825177e27827c739cd2b704f6a6bf6c6a4d4b41085435c4ae2	1	0	\\x000000010000000000800003c6f4ec1b160be9114db6379b8147ecc923b75772136018ce93e78e0addf877d45fcb6f87528188fe8996852dcae339a3afe0070bf145be40497e8977f919ed267249c8119683aba808e0b5ea34e60efb910e6583b43485c38394bb8ba3ab483d7ebebdf183110468f3c02c9733bc9d78c4921b6609d4b15f93dfab682c26bb99010001	\\xf3e588826874a0241c7437d1fc4e9dcb230b66a1e28a746fc0664cbde5615cfc805d4239d95c3be669b38e101bb67025ea9f988a2201a2e8972868beaf6fd00b	1639575941000000	1640180741000000	1703252741000000	1797860741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x01da62389b39faba35b7683539f082bb5814e347ad038f6b21121d493e1c57d1a642eb6686bb4e8dab0d94fa6093de79f3a89cc4364d0227aa3e0269d2fc0f30	1	0	\\x000000010000000000800003c4479744f4c633b63d067ee9911258465b2ca78dafd6f11bbb89c160d17cbe09a3946b7117587fdf1f1be5bcfd9ce224e7247c2ad4b1379ed8a15987fae8a7d01ece636f9b92b392bac9030925d105c8615a672ce9086e0100b85a618b622e626752b3bf8c64a1b3ad444685bd72430a8daf60ef51dd3a2c483a967e109da223010001	\\x41dda9476b04f6053d3d10e89976cefd9e6d4758a574af22b3cd11495bfa83e3d2a578583a6aa7f3c70938a8815bcf3cb4b3863e1dd821c0221c2fd6bf46ac05	1661942441000000	1662547241000000	1725619241000000	1820227241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x02c6b0ff00d9e857e7d6b0adcdf8dba737818613583a35a48f0719b5963b5b1fa3b22d2a517ef533446295ad40c8e476ad283e7c1d6aee0175b8c41a0c852e1e	1	0	\\x000000010000000000800003bfe0d766a573e39c22b77605956bde6f9fb00bb734beb02d65e8ca9f2f805db63307839f5b6f26a90ed49b00f2319a0c1302260ceb0cd1c7c3d1ca0932e5f8d85b9cc514c094927a6f06a522767dc3e133d46e30ca32aefae41f637650e0686fd1f8ed9cebaa45a50798787ae1c9274f8f14a15e0a6b6d8f2a0883e5faf32e07010001	\\x56e810452087894c69ce7bad51ebc899bf380da6d4d455c90edd6eba33369b67e07952367dd01bad46c5f30362113216f82a2ff5a0dee153615a7e2dc52cc001	1651061441000000	1651666241000000	1714738241000000	1809346241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
218	\\x032a00d5b8a76d813d926f3a634c8b18f09d9937e6e29240d5c74c91dfdfb80c75ec9fa6db69f38e600628fb8e36a264bbae9e2e1521bb84078592e2f488c21e	1	0	\\x000000010000000000800003ae2966d5d650842fdf28e479aa550ff169bde075addc78203908ce4b9b308d0337186d77def5f2f7308d2340070fca35bcd3a24c9322cc7c779fc8f1885a3666e6a24fbeb16219f643a134645d5305603733b95c0a73a086edaaece843a142dfd2c167b6d305529b0b70b1e77f8516611771ee27e92ab56e7bdd6ec7fb581fc7010001	\\xfe061457c18f7674a2565aa9dcb9e88a5a3aa4973842b65e05290e05df1ef046897c4e15fc040462d4c8d75142150df5328de5e3b5fd81d7a57830cdf6945f06	1651061441000000	1651666241000000	1714738241000000	1809346241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x04d63639e36f9cd27b974af72240dd21a010e0284b668b67165df67b96a03d241be5ce2b30338fab2831406b6c66b8f97a96d655623452b6148ffa708827b106	1	0	\\x000000010000000000800003d8c322433b26622e114ed3f642fb2a2d44d9828f1d60c7604feb836f9818ef5473bf721b20abcdc27e1858453389853f11cbf871107080cca88575cf727e2b8e4a38635777a2f882b829b92e02235786d8d6177dc52e8f8603c667f1aac31c15d554110a4bec179074fe4507cb0fd7fe337cbba1dedf8a12e3ae43e0cfadd22b010001	\\x160a41fd779e5bc03e0c08d366eff721c9a98c77b5a7f4a8ea48b63096aaa17a605099c9077b9db0ae653a4a0881c045d136d6f3fb616acbf92b2b7948af4f08	1667382941000000	1667987741000000	1731059741000000	1825667741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x055a862e91b95d1f0611ab0ea0a8edf8289a5431e3b6e9542035df4e96f79eee3e6895608d35fb100b906d2272b257bb6e9a95f6ccd010c8f2dfd3a9bccec2ed	1	0	\\x000000010000000000800003cc23ee0e4b43b0d4ee31b3a2e568421e0a9dae824a78dff25259c66a7816ecdde1a09a03734ed69751c0409bc5239443288b5c4595fe729d1cc45abc16e1d6a386ce07ee8072cf52a196eba6016d9ba8f633241ea97b6815add8dc507713debf08e472e0d7e9aa9f902d7be93f7f9119e0c9055fae7fda10debf3e09641de8c9010001	\\x5ff222eeb1e88acc2dea98c53258e81a9340165eed1735dce6b6311fa94812378ce05631a59b809d9bdeb5a6735b09b90fb9628025945a8707d1bc40b7009d0e	1666173941000000	1666778741000000	1729850741000000	1824458741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
221	\\x09aad548e5db208c7338b362e3dfbfeb0d95165cc38f79c5fd574fea61d2314a9f8e69d73fb96220ea8af9898d7cb46dbdc02863fd735e41a817b2e73e087b77	1	0	\\x000000010000000000800003a210780c72fc911433b8ec234dae74a08f19680e68abd6d89e7809f0b6f4828096ad5e63c8f13546ca37c4a2f59e54fd56c51c0a7fa23f887d9cad4b16d7f1e990a91064e510373ca88c0f80a5c40da9b0449cec14d5098adbe27d38020c9be0182e559c8c9b45fa65d3790eecdf4e9c5867837b7a646d030456fa6f5dff5edb010001	\\xdfad6bca7f63de24637547befe31e16c9fc6d581d4f40029ee1d1e079628de3552a1a31c8eea40c403ecbd78914631e83cc3e8872d6f7b2f2b62f03f2a99ec0f	1663151441000000	1663756241000000	1726828241000000	1821436241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\x096af474f8aed5fb87a211485644305ba5493fb9faa852f31a1c5dcd123738bcf03336428ae57bff370c3de06cd359804b65c759b4a9c5fa4f1f134f9b0e7657	1	0	\\x000000010000000000800003cc5b784ef543cb0aab39317d63b9d15a9d6f55976ca1ded58aa8bbb334061e9ba301247af457ffc28334dc1c1bb854ab29984ad1bd11962372c9505c5a5502c1f388f6cd7f8be6a606a02e742ed21df72dde71d5056afec2efee134bdc4d5904581948f828b61765faf424b93f2446b80cfa004de33b097515e57c58bc7a9c1d010001	\\x934b664cde441d2c791f7d211059ac982cd1e48c32d9d8fb5661e89205d984703b774506a0960b881fd630b47afceccd600740f39ef1bf5ec2c4a10bf1f9260c	1651061441000000	1651666241000000	1714738241000000	1809346241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x0e0a87e363807270fea16a347f369937d7aef5c9060a8fdb5d84d419970e435975997f4f5fbe69f738315cbacca190911935af0bf69698f5f5449eacfd15b06a	1	0	\\x000000010000000000800003beb5dc33bb091eaac7991dc08378215aa5b089c8d389e704d110cb5f3027584a3cad434306e01f7dc83873f5f34f9fdf739bf7b158a132fc17453bd0f0cfbc6643e3a9ed650f6d9f70244f70066dbe77b2dc7a57f851b735d5df9c076e3c872beedb3254b156f551156321333f76496516f8f1e55f7fcd823c4dc298e3fe78a9010001	\\x611a4bfe5a34438107c385c203b7d192d3d106ed3d0da0efbf092acd0fcc937afe1481ec22bdd660190eed5b4fab830b72dd2333a29ca05c3d064c2c0ab1770f	1640784941000000	1641389741000000	1704461741000000	1799069741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x0f1a797c1b5cef3bf69c2ef83b06764469d266be086f93862bfae3d7ebf5a9258fb6bede4e7620ae7e577f37647ae64e16dd1cb48be657b3fa7b8f98e1468307	1	0	\\x000000010000000000800003be8bae02f5177196da7463ff97de323b2305f0498915e176ff5521fd6c8d55a4fc6e10778ab79c636c959a6114fd0a13676f430ab31926eda04b5a2e50b06d75cfa472c644d7a4413e7e3cc963da49e6bcc4f0bf7e0910695a2f45cbb8b43cd0d55d5d9f209e27338779181c3ecb46869900de4bde9920f88ebd3605e698d177010001	\\x43a7bbd725d73da16de93551c671706a15c606566c841b503f92bab22e6ea9921155aa19c8887d6f75fd62db068769940f9155e8a678df6420c6a51b75167f07	1645620941000000	1646225741000000	1709297741000000	1803905741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x10b6bff404f1d4bae66a74c1a9018a96a385d0b55fce61f65c0fa59a12cef43e3d9bc5a5906ab19fc336c48a5d311d31a940ccc3dc45a9292e6ff93634651a0a	1	0	\\x000000010000000000800003c83eba52687ed0a5606c3206c4d0cf102eff1136a0b89fca53e0b9660064ff3ff5e37bf63e6ee4120600d34d60485bb7003cf42618533f94717ed4a35debe2a7bb6b75b875549adda15c1da5293422ec8affc088668f3e6c682902f7b90fad0798bc411450dc2b1af159c3bb7a7e6a4b791d7d6dda356c344782ab3a25be3f79010001	\\xafb7b92754f93926c58fe57e565b73ddd3bcbaec85ad2fe52323c04fafbd98829d7cd18b0b9dd496078d97298ad3ab5fa3d8861d61475777a95725d038e5110c	1660128941000000	1660733741000000	1723805741000000	1818413741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
226	\\x141e0220f7584a17b9d147e77edd1e7c63258d522e3bf81f6e4e1101bbea444ac610dac35ae7bcc6a713133743525485b2fb8cd46da5a742af7399df58afe1ed	1	0	\\x000000010000000000800003b82e0807ccf33ed808d72c1b444e01f840bbad1760589450298ca8c51cc149beff940cf3150185d13a968b906df4ba5cb8faff5a2ece2904c56010913936c80d8f7df4abf1f6102c47e4e616e3755802f5f0eadd6c40114583354509dd9d8096e79e5d2bb21dbea0a342d9af449d1d75e303f84fe7faf520b4c1c8314ccfd375010001	\\x3c6633a64f8cd899ca736b2eefde4faa345aa1c05377b1fb22d6def798243bca7ec47b8421da3ca9d5acb3415afa43ab132eb455f19237d581db50db87bd7d07	1663151441000000	1663756241000000	1726828241000000	1821436241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x14f2e501b6214f8a7e898219feadffc647ec5d6a831a8b1c06786384aa8b71349d9760fa8c4b0e0ab5aac9221b5bdfd33f2cf86883a7cada3a93411b9b65ba77	1	0	\\x000000010000000000800003afa87970be306f6b1fc1e8c2054df2385cc744256730207813f04688b40725910d01b5ff01529309a1565ce7e965839df7da1ef67d6739f8248e230a51468632c7504eb1a361bb771eca74d26a7e179d79d2c7e79c2e3c14ad916c5f76633697d1fe09d3fc22715850d505bde0824e5d821d10f7fd778c40d594044537b35325010001	\\x787c4da342bc329839ca89525de8e1dee380cbcd346d32b640c42a20eba007bc9918027cc06da2702f5db24a4c77ebe3e099c09da64efb084db00eb90402cc08	1649247941000000	1649852741000000	1712924741000000	1807532741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
228	\\x153e9553353f824e8d0e9c64839146ad81fe1e6cf5d21d7101e857a24433713059ea717f1088e11505915dee279b6568d79ddb33420b1f0fd64c4a141c7ff36f	1	0	\\x000000010000000000800003b49f44008e67065088a98e322b25f383fa06a2be870ff51245d330da8f2ff1f30edbd46c2beccf4ebe554b4a6f2869532ff837a4d7328ec1d4f89d6180e712224391db03521ae86fc63e5275c3b6ef46a381b0546fba7fa3dce777763bf9241367a7337121d097bed5ebfc0b8491b00864c99f74c9670ae828300a76f357d5b3010001	\\xf7b783fdb352ceb4fe5bc263d6efbe7401b75a0319824a5215672d17cda9a633b0cd894b2cf041d177dfd0f0467dcc48ccb2f6067aae91e5048abf97fb07210e	1655292941000000	1655897741000000	1718969741000000	1813577741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
229	\\x16b6883369e94ca2564eaa5fa40e2450a3fff02b7579aef287fe701cd98dd4a27b05188f82e60ad0ec7b803f985c3fbb6c2fe5ab478f2148c8efa23ba2d2487a	1	0	\\x000000010000000000800003da5a08ff555741b18f0fe3f2b42693a8caa3628601d9f5b0763f8e60c9a7373bd9c8a94b05683abc1aecd64df690e6bcb59935f2ec4489a6190a7fb4a860f647542f730c2a32efae0ec796b9b44bb25dc47909ef1c6cbafd014ae6bdecf5d75e671a50faf7e1567c21d74c720004f1a55d1d3665a1207eeb659237e6292e90bf010001	\\xdfc90fc75f170eb1b50bc4003acb0609c9226a5af3cc9f33cf045c46dfc1355bf3e7847cd527a71ba8682f4f70c71da5a7c70975ebda25d9b6fe4637530a060d	1657106441000000	1657711241000000	1720783241000000	1815391241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x18ee89d3ed6f775ce8d5abe4a4dd76ec6d53915102e528b05e67b3cf270ba9ab6405ec7dba1efec1e7808d098c2f42d2a02c9eb3bd7069b328bf640af88d780e	1	0	\\x000000010000000000800003d052ebb20352ab45ddd743c0279b972d346a3e851faf2fe66028e91c8f8160054ead38fd0c436a37a8ce54aaae387de85982faf25386aa6077bdaf01efba17fff4a1adc7747d9738bc9cee34b563917685c6907b529abf65ca225551d4dc658ae0e5221f11e8044b48a503f2fd1e54de6818590c48e48fcd40eb9c5ae6f704df010001	\\x5c0a6521a61ccf0bf8dcec8e1f9d83674236243e43972943c6bd3bd0d5a59f9649405cce9491fb3bcca737275c69e395ab1885e8be35b6e9cf657ec5b7db5208	1656501941000000	1657106741000000	1720178741000000	1814786741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x18ba4fdc41d7ad8f2640f956f61c2ee95074868c08a185acd24dababa5db98bf2223fcc229217407dd939134ae0f1afef0250c3a3fae98777187c02463bb97c6	1	0	\\x000000010000000000800003c918870fd0692fed400974a0ab47ded6cfd96368b1a1addcff22487c246e9492526228698d05bae6bc65a8b254fa29cbbc297b396ee83953e1f35f58b387e5229c23eb51427d6a0b444098b668c0ea1f8dd61833d3f2acb9ad5da377dc7c1f634c2c08cf71ffb53c27cc531cb14a5610fbda5b7cd4970a840e951192720ea42b010001	\\xed4747663e16a89fa8fd1d742c5fc95ffac5000d9a53e6365de0f93807ca2f9d6bf41e902fadaa4a2afa71051c7eb4e808419f645f0c37751d8ce1d435d2a507	1661337941000000	1661942741000000	1725014741000000	1819622741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x194a02dae549dfe0ad94fbeaa03f49c9a6be2bac00b8e644ac744d575ec3db9d6ff9a563872b8bf65ecfb1bac43c4c2d37e0d342fa8ef6b647aaf50c4af219cb	1	0	\\x0000000100000000008000039e53ee9033d36ef10247dd7abf6f54cda7792324b954ea342210a348b0a789c8226418df94de2b0f7da82916dcf4c159314efe6b9c2c52a62cd0b88911e613d71a2861fc37b659651d16e861421257070a47b06bed1f1aa7fd3efd560536925960cef0073fbab48d9299c073ee46245fb7fa6ead84273532ac222c3a6606f25d010001	\\xb70474788791a6c1cf5d78b5d2e5a7a8096f8afc141ebca02d211af8f0bff75b4c8f64a82a00efe1bd429999673900708b60420e23f79b251181fc031148340c	1658315441000000	1658920241000000	1721992241000000	1816600241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x1aee938716fa3f3129d6047f7a57f86d4f3efae960c455fc6390daf513871be8b1ac52b157da4b6b5d560699aba0eec58de96f88219b6c70620faab93b673894	1	0	\\x00000001000000000080000399e691616aca1eaf81c33f28174dd1ef836787e81c9fc8d4bc504dc6b0e8440b53a55c0a7e9ab760afbc1f64b3a8801b5e0e7fb88699f5a889b0c3186df8d567ad18026ef3295ddee85c83e9a301aa092547cda681d43c9be7543f01b80a7b662e01f189b6fbbc08318e04c7d6c7408069d6cf7d00ed07b19f6dbaa59ad8bb93010001	\\x50041cb1613f86567f2e47596a01e8189ea252185ceb3b61427e311a322bae5699976512e0e01322678bd39f98f1a1605b804a4fcb00cead7f5876054b7af206	1663151441000000	1663756241000000	1726828241000000	1821436241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x1d82f811e7321820cdbbd953043b767fba3922a0e65abb3dfe543044759bee70df9ada9ae062aa9fe077da92a5f00a3aad6d77064aca6144ba7691c186ac1527	1	0	\\x000000010000000000800003c19194be9fc9013e5df310fcf51c42f82a7bba7705441092c9cafb2d9231a49a8d645dbf8e1100b55800c70d54c2158519eada38514d4ccf38072b971b0a0ef3596d71e005b8e9c6f7fcc66d92318b85a455203a8dd0d9a4f7c662da681733f5c1e3c0d4fc61c78d1cc884125de4ccd95b96a1a4e1f8e1c13e5708105e76bd73010001	\\x6b3b5b125792a21b03bc6aa5419ef6d768da9b959ac8683711a97bf92a6d6406e398fd8cea983c94b3bd7049fbefee5672187bee8ebb3dd1dfedfd3e6379f001	1651665941000000	1652270741000000	1715342741000000	1809950741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x1ecedbd48b689b451a6cbf5ed6858f3ca7289aa838d4ce4df7457bb73bdf3752e551f87af89baa009340720b0eef892c4864f0f0a7231ce749a6605cc5cc0184	1	0	\\x000000010000000000800003ac4eeb280db3ffdcb9502b792ba53b4932a8c3953504e66a89dff89732567e652574a6d73866f3a8182b17cd62fb9166cb7fd8663ba3ef53bf4f0e03232a5793b909fccf51d9ddbcf83d38ba14954238234e814d6e68f6836a3227dd3c0cf083b4515f26bd7c4765040d0c1379db49bbf3abde5ffefe2a5ce4789dae29cad3c9010001	\\xe8b00c2af3f64b5a018be31325c1f2ffd70e50829ffd2f918c7ebaee4b08ae2a888bbd45adf36f877b9740f9aa0a9287c5b96aedec957222c0eb709ffcd1cd0c	1667987441000000	1668592241000000	1731664241000000	1826272241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x1f8254a4de23d2bf2d125a5230412a1d9e743ff5a60ff0906386762b132c8c87b1fabea17090b764f291b2a8d20596beb93e2b3b2dd2abc3002de4a0929e4a66	1	0	\\x000000010000000000800003d926cd2e488c819a03c109278228ea4c7dfa0c43b818d2942ed03483d0cc87b947f8805b9c3991004c014093d477a50a88bf1bd49bbb34a4a2c83839da82ebde5b8aaf924b8750619e90927cf779d8a9fffc7781d7ab5b404aa794e3b773a0919338faad624a50cc3bba4be5f62b43235bba3349ca2d7c202689473d7b8746c3010001	\\x5b896f0d45ca472397488cf4167300c925a23011eee37b18d013a88f3af4023820a12e79660a63f6239bca2f9eab7516007627353eed55efd1297845ae1bec0f	1658315441000000	1658920241000000	1721992241000000	1816600241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x23b237101912d9f47382102df1d60c5f523dbab70d2f889055ded288372483ccefd9007938b4c10197d1e6f87409c79dea7b307e714853d12b01a5a2c3b61a3e	1	0	\\x000000010000000000800003b65cc08ca2bdd6c34bf3c7984f855b106c44c087b022005dc44ee0f3c1a13f1bba5d9f10d6c94d623c3714b8ca503e164f1c73a3755925256a95e11f2cafba9c0303633f7abcb71219a3f7b22bb362dc254145f6e8066f549d088e8acf30f42cbae0866ca68a44b5c9c26378a02120f4308e748a1c85c76116cc6ff90f1fd467010001	\\x270a7ac707cd4b1a192842bd14e38f8cf2a3e83f95f0bde88b0177eefd960f2196058557d91db828b09382c577760d9723972b7f0f1965fd0c5a4a5eb1479d0f	1641389441000000	1641994241000000	1705066241000000	1799674241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x23fec01729f22464890abf22a15288bd950e103a3adffaefacd2339af0dade5b374068abf7c1cc76c87bc70a75fa2b9012d70e9fd11815dbd0fb4631673bcc07	1	0	\\x000000010000000000800003c9f53636751502b4152952c5aaf212ea42ac634f426ac0bae692211d805091ad68489c2bac2307442758ab437f855156a14f69eed333e965028cda8fdb92d07c110c03e74a9caf2676e1795d9984ac18403c20f88c382ebbccec5e64a17dc6b52962dab079f274a68df9aad4c9d25c1a88cf71720d29126f26e59e4870d2f659010001	\\xdd3fc3fd047d12941c90f9659e42ed91e9f668e7cdb12b1359c12018e385dc352ce58711a11566e005c109e74b684bd78212cfce7ae92b5bbdfad9d2d03cfd0c	1660733441000000	1661338241000000	1724410241000000	1819018241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x28be479f034d07c6d72992319dcd5de8967dbb99c8e33344214eaf07214084e01335fd68eb796b55034ddace8944b7f0b65ac3693341394922579a34abf1b160	1	0	\\x000000010000000000800003d4e1c6c331a11bb3b699df64465b3d74e0bdbe8d296d1b6c91380b4e329fafe25dbca7956a5fc7180a29dfb76580d1806001679ec71db2f43dc05f251c375b4216077ba14d0cd6a72f4e25fec75b685187a5572fa4e8cba972fc7bec1a56d2a286bc6a64db8d56c391714bc06407d2cbd0e22dc105487f2607d98c3ce27c0385010001	\\xf46efe6857909e5a5e3b22fc3b43e6c73cd3dc25b7a201481d1f506f43e377a45c7830bd4a21cc510ca0f2c55e462ff9ffdd661419ab19cda2bcd7f5eafc970d	1667382941000000	1667987741000000	1731059741000000	1825667741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x2ec623dc4bfa18789ea4e7b413f6fae12362ece2d77bfde444845099e411ab7600fd468cb480051c4b9abafe24d07a79d1a2e520aaa74b9e4baeb19091938f6e	1	0	\\x000000010000000000800003ce0971f1b0ef392a372dfd2838c7878f33e071d2be708e6399426fb3eae5a41a3348218482599f597988a1e01289cff26a10c5144fc893224cef68099518663f4df0877f3eb105711edb8923d91549e27c55fad96788840d3e4e08280c9f5fccd6f96fe2e83fde62efa2c992ef1655501729d76c8609feede29ed5b1eb827637010001	\\x9e874660cb170ec78829812de4bc4cb0e83a40f20fdbebc3ef961dd71c4d611ae45f915b22c1c13386f65a1d33041da416aaa9a8d22fe19274098cc041f2770a	1643202941000000	1643807741000000	1706879741000000	1801487741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x2fd6f35c4ee50ae6185fa319597b7e5ce1c2d7911f7f39e23370a96a5eebf87614458b49ee4f2776183b5dacce0a5d186b66c366819a23707b182961f7f10fab	1	0	\\x000000010000000000800003da72e75b93d251e272f884524d5a9decb2014d50818ac766816385adb5e8216d2e17dfe7b2ce86801eb3418b15cff09a6d5d5f94ce1a2ff78c044c98c95d7e5c284b58d00c4607339c079dbf521b638be689f0a68d45bd453370494be812278442a02625561237052445f7e58744f1597600a2ca6b037d0e51fccfc21eb1a2d5010001	\\x6b2c4a1b2fc90851e4791b9cdd5b251ba99c9885a0f364bd40d66f76ce50e28c40e79b73aefb5a5e80469a914130f0286ab6437bf59c84aa0bbc07d5fde48c0a	1639575941000000	1640180741000000	1703252741000000	1797860741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x3056018a8d356e73793a173c80e675424a6a500d2952a36220a9c59e18787ac7d80b18dbea42bcbf0e3678bd7acd15c2996739c4871e9514592d66725b14254f	1	0	\\x000000010000000000800003b1ae921f7207e9240298074723f663b808e192c62b5b2698f30bb92a00b2b204cae1f277e1bc975563cb516bd6525ee667b70fa506deb3b2c81eda3e49390913ae67ddfbabe03b5aabb3aece57cba3bb5d5ea1ac10f4343de4152b3b66f24fc81d41b73e77c7d544ee3e9eac09ff795dcd1a6967d2b6fb354e7be79a1b596385010001	\\xa1a0e91754f917add34c969f5d02f5861d71e53168262e83c653fd3727db13effee8db40c11ee797db474f2b6f4e1d05aa8013b6146f53281e05d2797f9f290c	1638971441000000	1639576241000000	1702648241000000	1797256241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x3116af9789c9e2d6f5ae43226e42353ea0a3b8ad8503edae02bf72f90a78e6ddad177bff70e47aa950ef815d8ef27f8f741cc3bcbf544a04e4ad60f8ec97327c	1	0	\\x000000010000000000800003a50bfdd8e704b270a044f26a01625d6745430fd5d88d1ed63f5dcdd602a2a61bbfd47c880870d84e8e1a3020ba9563935b769ecfd6db55434b52295c2734da5f105029d71e8fcc84e4bc400154ef4691bb4a703bb91f6142fd703fbd8751e68189ae4079b1b32e8d7d5188c8349e0c0921f86df6c924af93704ca6fb825f664f010001	\\x7f93d3340a1a3eb7a895204fa3d01386618898559b5a016fea4a27e15ea89a0a05a08554d1aa4bd919d803c8ee96f8c3507125a4cee2f8f46d24aff24d18d206	1667987441000000	1668592241000000	1731664241000000	1826272241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
244	\\x31c2f7d67587f3fb3ad16c1912c98209ec433e1a2ff0b2e2a75f2ca07df48d1989c96a74ef7471583b7b53f8de0764c1a9d210bc4f84a3dd138fc9fc19553582	1	0	\\x0000000100000000008000039ee69ae32fabdae9bb7882fdae92fc922c6e902334ef252aefdb8b46c613a1f1a718e5c0645f4c3bbc3868ff28683374e2e4225efa670f3eaabd417f632457a943962632efddb57b1b97b524b4e3840d3eb2c20fa37f93e6e9397e3830e4388e4557912b973b76fc4fdeba24cdea0ec339eaacbd163561810317b4ceb800e9f1010001	\\xf485281669b94500395e68f3c73f285d54ec14aaa3c0799b932821be4bedfe8ad63196e56043fd06e4ebe965d9623b7764162ae7234a00c1244356df8e5f6609	1666173941000000	1666778741000000	1729850741000000	1824458741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x330ecd85f833cbac973f7eb2da9d5ff76e80e92939e261f0f3f5b1ad30f73916c2561180de83152c3a740cfa20c9d7e98797f6bbcd2e738ca27269686ebb52f5	1	0	\\x000000010000000000800003b17d995caa879c03a83fb4fadc770a539f868bea61f83054fd215b3e0486a6940a91f6f9ac2d04aa3b3505b0497d88673746edc8f7abe970e613b4e6fd2e2d1bb788aa292e026122e4f5bd8c630255e7db5de8c38cfaed1aeea559a6762a3adc60808b0a17b0bf3916b5207c671521e0fd1ba6acf789b7e493fda4ab5c043de3010001	\\x65d2d163dc38a8fc0f1caf91784a10fa279b6ba593a9b7582e01ad9077f07ad21cf5d7daa7e1c50a2af756c330a8c704bf0c3aafab88153dd2aab013f963e508	1660128941000000	1660733741000000	1723805741000000	1818413741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x3706bb582858889f2ef043b34c8949741a0b36cb992def276e087afd1a83bed11f091f1121502ac34ace7ffbf3b835a9c9e75f61664b516753fdccd46b0ab94e	1	0	\\x000000010000000000800003ae8805fdb3b881c4bf474fee9f4d113061d1579d578ec60dc1a0da9a040fbccc14e64b0c3238cdea99590202d3bb8b15b3d8982028a1c3df72e39f643fc0b21d4e35d49684773d1d618700bfed884ec348c4febfcef7fdb0c2767d0e9729a0d7275288f55631110792838f15309fae1441a7f4abe9e6b0c4db08199ba933d41d010001	\\x118f4ffd053b3ee49b76022dd10f3e84ec7ac7fdf1c63778873b465d36d8e3e645cfd0575cb3751f29cbeb1dbc178226e698d76bca651f93260fe0a502c8270e	1657710941000000	1658315741000000	1721387741000000	1815995741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x37ea78a80288c7158da10e69dbec417a2a345e14c606bd143f0bde59b9e9d0ed1891eb43a4b0d2696801ae3cea2d2fae2b5f466b9f9f4df2ceaa2f93cae6aa2d	1	0	\\x000000010000000000800003a40c6ae4d74ed80643f128231f52d2ad5e0de46b1525bf04a44f4ae8ae529300eb9491b691eb5e04dc8c7e307a9f3b182022b905825c93adc46ece4815bbdd0a28430998b1202f5822c5c28ae3d832aaf0054f9c010c2cd2704b29399369165156c05da6d50f696f6f9c2f16f7f75e1c0f44d5759cad45f0dead01b407e9c765010001	\\x13031405db731dd0a6aca035c8a82e43403a94a2e206abf40c8ec80f96cdb05717bc3e178301155474d9dfbb2158f403326aa0e97c4d7c697963703a2c09e901	1645016441000000	1645621241000000	1708693241000000	1803301241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x393ec72b6b4c5e08afc2e83ecb49ed8f1870e29a16ae4015bc64a7b183e5d94a22bf9c15d6636fb2ca13e1d0d5cad9c8784e6545548cb131342d2ca928ec6dd8	1	0	\\x000000010000000000800003b921af87901f6b7b1d77d215e10aa3a9a360690c62bb167089ece3ac92ebc4f474650daf8764b58ff6d6d4a69f6ae6d4db85713dcb963850058b7b46c524922ee4f6b1aa919d4395ec0e5f4e168644ebcfd3468635cb9399cd53418db57abf53969a2665d696c039f820ff3611df97a5cc52a05e110c3f1d3b7c00f09e3daf9d010001	\\x987dc278fa9c358e7d6ba71129402a9a755ce7314a9ca428ede0215187f18c77faa7fd8554a32d65c57a5bc43740dd1a04e9d9fd5be087b5802d6bbca82a3802	1646225441000000	1646830241000000	1709902241000000	1804510241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x3d62c421202297967c83758cebbe39f1ca9285802a3ce40a8b800e4f0c29ab58f2ebbf5075d1e654e3d3144fb75a81a22687a8235c3ef852c73c90069eafce06	1	0	\\x000000010000000000800003bc7c4650ca57dca6fda975e8f3a8728b8b4f4a76e850af837cb1576c184ecd146422641f5d0d5c16e5ab10aa270aa1506a217e19b8da588cecf19aeeb9b0c30721d60fdcea30920e3d197529ff57ccbd2a29f8fd22c157fb8587f5e10bf7307606d8836cfbb4f3176419a5194605bbe9634f4c25b8b79be3234cc39f90217ed9010001	\\x9d68b8379510e4adbaaf4ef1acc62b243370c0d2b392bb7dc88aaaa65dda441eb68ec0ec804ded8a82489b30ed684e04e08389cba02c039ee5a34dbc6c802604	1645016441000000	1645621241000000	1708693241000000	1803301241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x3f6a1de02b352cd02ec2f0b0346c97b7541e73b83b37c157e65f67739ca9c8024fbf28ce3b9899d805c1a7bb9709098573377786e15709c880dbae220326e95f	1	0	\\x000000010000000000800003f16ef42f253cfdb48e98c4e6fef94c83efcb8e16cec31c8e422a13267ffc2791f8b8065a4223e1a3c4067f7b85f3f53fa8d78566732ccf392f2b07ddfd3b508a4af2bd72c1d2fcfbf705ae14eadd878192662dac623ec2dbbf113bcc2f2cdc22b43d81594cabbfd110a3107b805813ef1ed05dc30634981150d0e5dbef7d1f89010001	\\x9c2bd1bf5c633901cb63d27747159c573a4a3ee4fa985f547a6001258acbefba4b7f31253973dceb3d1ac230e682f2666af7e601145250a177c2a39e7fc7c50c	1646829941000000	1647434741000000	1710506741000000	1805114741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x45aa9b631aed6cfd940487931a40459f1db39eb9ddc157b187dbcaf83cb77c2d315c3748dd8c9fd687be073615650006f9f616874393b0d08b5c23824a95a085	1	0	\\x000000010000000000800003cab06bece2e9ce7a0f3e0b5c2ab90981e85c131fe862aef51ab11c9b5dbe03912513f298bdf53ec5fc238afe9ec3ac22e47de17c356c0034a1123faaae500a87fd45fe53dfbb1b379fcba740b40cae448270218e262aa0578eb526a25211a3656a9f0875255aa619b3e4d84ea41356dff634e904b978d9fc6165c878ae2bb61d010001	\\x0a485395bd65ad9ad98824ff394782b2e9525135c4b84a7e3edaffd846e9ef90fae39f050b00587d7a379cf2da569dc7b4b60818eeed127998370126a84c9f0c	1656501941000000	1657106741000000	1720178741000000	1814786741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x4f024fc06fdaeacdd0afcac4ffaaba2159a1aee41c7a906e10b28962568fd39a117d267afbf05c40283fafd8971a094dd4685244ae91bf5dfa9a358896d5d065	1	0	\\x000000010000000000800003c37635b8596c8445e4c902f65b060cd039c534af8691ab7b25ae7f43592753683b442038fa0bf5535607dfc38c417ec89d90cc0477d3572eb1af53f0bb6388d05dfb7db662836eb0c88f7ef000d23ab08958c62116171a49134a5f79863f8999067ed3a23344496d31cb6c6c4265bb43ebcc1c8a790c1fd926eeebc340beae49010001	\\xca1cf32412a61833c13a9b8b5f221a6a57a97c89f35f9744010290f54304a9e18accd1ec6bfb6d68c0bf631bfe0a98481a476e6941a491581c0544054a216a0b	1663151441000000	1663756241000000	1726828241000000	1821436241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x527eff165441713f27b9a3dee90da355af0827142dfb723ce108025afdfbee5e50877751f29b41cb13afa8cf9ec21672c5908df4c2363bd5b59d9b3441c2fc04	1	0	\\x000000010000000000800003bfc85119d80f1386f9f2bc9c38640aec8f1827305a420646683d976110118de96d4e117cfde5109c3dc8d577a477c47d9715cec3fdec49f88ad5ad5c3f55a666cb0fd76259d14cfbb0ff8b4dafe6a0e79e40f74de710241166f2824f69cb83a2ccb3786e55f9330d0f1a6a54965712e27bbeca41f1d5c6e0ff58b78c5a3fe2a1010001	\\xbde4d1bb7735e3653de37357cf7e1419ac239cf4c8ff4424a41a37057aec7591d8053d4baaecb19290ef2bb22984bca26ded276739d6ccb6f218dc0a7f15d70b	1648643441000000	1649248241000000	1712320241000000	1806928241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
254	\\x546284c9d72dbfd761ed73c4cf1dbf033474d6b816e414896a24cd70982b74c298df3e62d3fb4bc2b7a8aa183ab04de1f88dab94765d28896faf36cc824e2790	1	0	\\x000000010000000000800003c472ae9e501da3004a64fa0831da1f9651e05b1f2f45796b8a3571e391f8d1d2e4f0d93c6f64dd2a54d8fc0b19f33d452114d1ea48764b72d09da89b914e7740b08e4f2ba2939bd991ad8cf0574238778b0e0692c6e8a80a5bccab43748c5e1e4dc9895710cb150576c826e012abc32e000dd3a53a0befff521d10f4f6abcc51010001	\\x00ac25f62108750b3f49743b94761763a2b4ca737c98825497beddcf3ddf12e619210469e76dfe805156c7e44321490d77f6b75c29d9bd95db346f20aaf90001	1662546941000000	1663151741000000	1726223741000000	1820831741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x54421631fb48f1508b385148ce40bfc04d47f99b4480de38c08ffdb60cedf6b88dd36697dc15963ad57c565efe37438e799dc096376d9a8a585d800860af0597	1	0	\\x000000010000000000800003cd7f0c42bb0afe16afd5ca37b0be3e27e94b40d1b32d0e5025fa9f861bb324cdfdc22aadb046dc185c9dd8b8ff06f8195acc5a606d41cf5b0211cc78386dbeda40b21f77f6c0cea98ce9e8948016ef8555823450e9d240c361c6211dce4d86ef60e2f4f6aca8c1e1428a48facb1b02e9106110877434529e1ad62bf6b38053af010001	\\x8d3ae2a0337c26efed5c49ee5d0c6ea6c7f6a4fedcfc641c8018236edac0cf2f008984ce7b777a733d6ddc56413eba106bf09ffdbcdc3e0d215629341494f70a	1654083941000000	1654688741000000	1717760741000000	1812368741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x55bead5bfedbe2407bf6a100a39ffeb8d8f847949b2e3e9593ffa5e01b7172f26e8dfdd1508da2f8da3909b3dd3e540f5989e4be84c37464b56fd0485b5b32c0	1	0	\\x000000010000000000800003d86e2783a55b3c9558666da488e787fa3d0f6e9ef03626f7b7fb9e47af4d397622ac7be5e4802e2304010849f75fd391b7a9a02e77d86e2149907ad4a62b1e4a97a95bba268ffe87f0d2c798be2c14d4b6be6c83f2e371d4a6054b7645999385303ed17485101e0cad349fa75fab366eeaccbfc82fdd6629756128659b8f8fe7010001	\\xfd4801b21baa96d5c4f6294226068853fa45d4f2b3d1c79ff8b40e87d0577c89fc6fd9219280515bd695871086afc175f060ade393976ec51db91badf6543b0e	1661942441000000	1662547241000000	1725619241000000	1820227241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x573e99e4b1c0ebe8f343d0ed69ba772c23ed0b5854945303205d0204e07858b37c4760e85cee65e480f4501c4b2657fb132b73ed63d64e797e4d788367b13e35	1	0	\\x000000010000000000800003be76a9abad3b74af8e719ee1948ccd4c339b212cc3e93535a24d094b453d709fb5daee3599a3adf9d64143aaca6b4efdaade4e3ca388b218996dc03db78243583ccd6d78c2a0e00789145edb6fd6eaa1995800de0985de42e471bcc31e6eb43fcbd08b63b808ad904d08d2df5f926d2b5b88b88816a178ff1fd825f5b42f207d010001	\\xb1edb14cac3bbb04120645f600b78d9eab18b8deae8b5c21f67d5db4a7c2cf88afd846713886e2a229c539d06679e222ee169165973e1bcf248b936685976f06	1641389441000000	1641994241000000	1705066241000000	1799674241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x5aca4e2259740a3d7cea924a83b463d68cc074038c27080b7483161350207bd7a58b1c00c0c91b0cdef4c22d36ca02f601372a5c2fbdd0fa715a2c8930a582e1	1	0	\\x0000000100000000008000039cf5a4d5892e928644a64789e816faf211438b4884299861c305b2635b39a2eec34573862c0033eab962a16141ea419ad662e60292b6261af37d6bfd4439402593794309ce4081806bfd1aaa283e1fa0303e9b2c67adad53e1eff9c98c798c8a64123158f20f5695226aee98f3c64fd94a3ba450fc29f8370970aa1a366bcfad010001	\\xfde763aa0a4082a871751af9012f0e5fb688c9af25a508dfcbdf375c1e371a06546b3e07ae8039efb9d1399e45c333044122006fa8df87dd06f4a2f90f70c606	1654083941000000	1654688741000000	1717760741000000	1812368741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
259	\\x5c8a5e7651b81aa702c642c61de0e35bde538f02682233752390c58a66e42251e586e3e83b236ff1c2ce65dd87b3a8946987d85299ddadcacc36f6964fefa1a2	1	0	\\x000000010000000000800003d976ad44473c354d3fe937f9ef3f54351a2ec4cc927782be3f1fa47d258e427d13bf91f533b695fe99fb5c6340d1885592f37129600d162bfc5b005b311561dbd013352133dab8ddba14ab4e78406edfd024e12ac80ee084face0434c292cab40f65cddbe155bc7d9f6f5fde2fcb0a187071371bae20d1492e34f4711811b375010001	\\x291fc5833ad269572b868e2184a5c3ea6dab686f2b5668a9fe76dc6a8cf089b06e0d8ceea865b9138f9fda8f209586a79cdd884b735832e84e82dbfce2fe0a0b	1658919941000000	1659524741000000	1722596741000000	1817204741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x5c36da9276742089e99b57d033d9cf0493737e389a4c1a3a4339f70eec66943b34082f3b5c73a2eb01d4bf2132e0fb1bf552314759579a2968163f06e246dd83	1	0	\\x000000010000000000800003f607e63309f0db53d8ae1521031b29e4cd7e3117fd2dd8f1e89e0f477bf4672d87d9e3a4fd4977af93441144b0f92202e95f77c8ea8b208309fe7b82abd6d73c1a21b2c398c3421cc51609f4b609a41b86a160f2583fd1d940d69b4266160defdf29ca44dc892b13ff2dc7e67a014c0f8507db566a99805cbdd1c3d2a211ea53010001	\\xaaae8da162173ac74cf4f5717183c38d25ca2ace2db0c3c0fda31274c5b429cca8c1f64e4443666be0abb9490f3e5b210d2648a7d7143ef3f82a45da800bbf01	1641993941000000	1642598741000000	1705670741000000	1800278741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x5f12c848f0aa15f7d056c8a3f6e9f2b4c0f5c2c4979a9e6c2b882e562280de846084bb750b1e7a15c78f6e95572043db153c1941f85061f44205c4b01aed6507	1	0	\\x000000010000000000800003d9b2158e4ae5945a44f1390340066c3483d1ca3f9d081c90ff0561e119cfbd8a1874274ac4815997ede8763a75c960a494156a5ee079fbdd09896661fd1daa0e3bfec38dcd6c9ad9e44e5e6b9ed24b9db924a7a432f86ab1e6d4ca197efd7705aa19f5fa63ff73e9a797ec0810b77a96b76a58723c75980f42f9c49d8046792f010001	\\xe99c75c32a1e860aceac6f61d82447f1ddde8d8db24bbbc49df263b6868700eb57b2eb2c7daba7d8dd4f86b680e6cf9b100637fdebd3b9dd7a9679536b504902	1640180441000000	1640785241000000	1703857241000000	1798465241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
262	\\x69befc01dd9ff6b272334f32b8e8d7dd89e5805f2176ba54fa00e009edc771e1c7aca41101adb6d0b4b613e73c447ff435873000c401065bb76bf8a5e81f5da0	1	0	\\x000000010000000000800003d6263c245a386fae92c305c7ac0b6094349e2ffb2303f1b96a072fec04ca94654fc1c3c5ff742e7ca1591f8a20510682a98e0bf2c2df5df1b2a34bc40b62d76d2ce069161ba5e9eb4dee785a9d1e6e69e4797274cbc8ff9a4fad4214715b76b3bf8d225e8d6289823887da2b2588101174f529badc7cfe95eedb70e0f12e767d010001	\\x48b471503731afe7722db099bbd18af7d10243ccc1eac71dcde8f95564f6b34eb1588ea6f56b64e527d816604e934c4964d09bcf6fc83a5dcc0d6fcf3173d108	1645016441000000	1645621241000000	1708693241000000	1803301241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x6b42f02638c6ed4177ff0e6edcace85e045dd8d1f1f58416cdb8bb4365467eca19102eb28f75764e5e8998756af6a5c5a1ab544499d1d2315508d47e5f263c68	1	0	\\x000000010000000000800003b8e74b9dc9ac59e7f3a69840241c557d970e32a0075e6b8975fff34bdd97e1a855015ed6a344460927d28c6be9051b37e7b8423c0cfdda83a21200884c314aab80cc074815653fcbe35f9917621aa2c78e88996cae5999dd5ed02032c908c2e1a4b428d80d3449043f7cedde8db2b9861af0e48d19ed455c3e6deed450a08ff5010001	\\x2e14190309239a78fab5f72966f8b4b2024b565eccaed08cfd6cdcf3b8d4487537a8ff342139ad231cf509ad6aaa06739ad196bbc84d3793fe22c2a1c9c3d100	1648643441000000	1649248241000000	1712320241000000	1806928241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x70ea2bee5a72d3ef84539c95180eb9b1d3e83331f6f1b49cc30014c9c12346c78a5fd2980c34feb7feeeb916e7db9b5b26c4593597caec569be091d412a366ff	1	0	\\x000000010000000000800003c1f6b713624b2363799452561f378d467dc2ea7ae84a14612d0583e3a73fd3d4466b3c75eba7ca9ca260fe81770316d136fb5128224e9a8571411854fb8250d498a757b4e60956b3db679629e5a1334af2b6d92283aa230545a6c25a67f8b418a3cef0f50aaf4db2077f6127f8a60e858112723a3f85f658d6a8cb3524572319010001	\\x665bf8c31505f2a500781fc3cd28c68ba8aa516f3878afed805ac3674deb326f0da6bba94076e5a9686306b4e2852d7a1dbb3b566fff04ec8aacd9427dbbd705	1638971441000000	1639576241000000	1702648241000000	1797256241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x768e0edacf8bb35874f82534fef5c1b58f1d7887d2b8333375c4c067323cf2eaee15c9961df0ee2548d93d20c15d809b34c09fdf008e2b09689871e759b78e5a	1	0	\\x000000010000000000800003bc609c459f6751ea0c8133b4b241f4818ab2c0e52da0a0d1e5e3a9df44b1e20dbeaeae0e99f8887f24049c3c3c79ccfb648b08d4c492192f4044335fe4a07af3dfcb96e92be49005a0afed79b322e39d37da7f6d63dee75c98dd2efae164e8c83bbc137366c5bc1082665c55223591633a474a06b12dd34db480da0b32d4923b010001	\\x99e6c2a4761d4a3da4eaeababcbba54790ba1732207140280c3c4666d80e7c0f60dc8d761c67cd5c0acaee72982e48d79b5d3b0a45c35c39b62ca66cee92ec08	1667987441000000	1668592241000000	1731664241000000	1826272241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x76ba618900d4b5be89ffd16d0288f16528c953827ef404fe0d150689db5d02bcd4af547122c7130b3c3fe5a8451117794b4041a2c2ea1d4effb1e153ef1f673f	1	0	\\x000000010000000000800003abb9215ec36ba898bb251a31975c93f38181d245af09d18d1bf9f95174fed94ce386b0b918367afee9f40c36956b0f97ff357b9a7230d31bad48a3ac7244e7c9d9c7a572389916c9db135d5a2024e0ebeeda1911eeca40cd03d064b6adcf0881148029d889cac56dad1e0601dbccd36482eef150400a9af4fa48da8271bc3e29010001	\\xefb69606d213ca1d570697725e358ceddae16883fec183f20be5631ff2a3427e12f77fe1e578d9dcb0c0bc7e4fc47287b70ca3f50855287e41a755c7f29bf409	1662546941000000	1663151741000000	1726223741000000	1820831741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x765a1b1e95a36854bc68ec18b145905c07ca2f1ffcc2e40b3d1471cbfd8035690930421e59c5c05934531b60c96be0ae60f742d413886585d59810b61a197e6e	1	0	\\x000000010000000000800003bf709def5584b08c17f4ad0a0d8e7a6c35eeda42b9475f69813b614099a753d02c902fcfcee4d21618f40a8f26b6b3002972e1328332945d0948c0c268ee35ce869afe6224417eed6edfd931aa7d1a8eb609affed4d454448a5adf942eb92d9518ea4ef3a8fe79b346a281fdc61e1eb3faeb994663ec5ee4f8bc5a279e95e495010001	\\x85297e870a77ceeda08d003ac95c8dfc5899e93dadafa9ec1a31490186167e2dce4ab0d2cf1d08e0393f87d890cc640ba47c590dd11f7fe97da42df3c2014908	1651665941000000	1652270741000000	1715342741000000	1809950741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\x777a0b0d8e178a0514c4d7149d18a224f04ec3e6a07fb15c8ec6792d3e81bed445f916419f8626940f8606125f2800885db2b4dca3ee67fcad20ddeefc3b2844	1	0	\\x000000010000000000800003e4b11bbb4d917098902c9e1c712820b40055f5fa249dd9c91d59e31c664bd69351f06eb31d62580bd07be56a21a3a7dfe50cccf67b145eb0100f46d27a60a3903a5ff155359129899f6556304dfef73ce0d746d69d73b2735ee82008dbf4fed09ad8a8f8837a53e9d2ba367f3089735af1e65df8aed0fd447e2a4746571efeed010001	\\xd9d64cd0147df9344c4abf33fbfe8a80b266465d37116fda513f957a644416ed3e0e1a88935546b781cbf65675d944e09cb342a74329c497e715d9b04e49a70f	1642598441000000	1643203241000000	1706275241000000	1800883241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
269	\\x7856053fe685e2e1a48f0a58a9b3e1ea6e11b7e7eaca89f88133b749bc581a48b81d47ddf83edb664a58539951d77c775453bde400e4b66ba4dc5c821f5ff3a7	1	0	\\x000000010000000000800003cd75159dd9be2cf085e5d53df0ccf386c5e681932435b944be41b190efc82964fac88c83318bed07b34f92eaa8efd64f90a27835129f41d0feebc2c73aa1d022fe935e268a6d43bb69e4069ea87059f250019c603c222d7e6fe492859d9076219030be1c8018119de29312d345abc74d63c70c2f2c207ec24923157186c35745010001	\\xdec4fb837cc62e67c78b2511c1724eca0bfaa1a56bfaa9fb41c32504b389ec4b983c292a95c8ec08902c783750420721a46a99b267e09ff8582a4c6d98da590f	1669800941000000	1670405741000000	1733477741000000	1828085741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x790ef412acba9f993d3f2e10e12c145662a9b6ef17f1cd220a4581f2c1256ec6fa76791e24ede2fb177db3db988a7d6a29cbe945689b29640730db676aec2781	1	0	\\x000000010000000000800003dc043a356eec15ba04d51e7bba4375315a5a80c46f36c13cd3fb8acb7a92b9ec87daa08f036212a12c2446eb45cde5028b4974ab2ab037cfedb5ebd48940699a09ec2d7ce9dc0def8b8e4c54ec0759e6cef446db61e5cc3b493a1906b3cd7e3514ffc249ef14358ddf1a2d148adc9761bddc847ed92b9e213b8a32f6dd46e8e3010001	\\xe6f84926cb4aee39cc57c2fdfba55086b9b32ef184398fc5c93c01562db0fc27c5256f62bebf69da79f40d99baeb61fa183b3ecfb4f8c8810ed75880f1f78f01	1651061441000000	1651666241000000	1714738241000000	1809346241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x7a26140760ea29e3e268612c8cc88a34968254a2b1cdb5d62fca600b5926a83bff888048ff8fd1ee81f6d29724e85600aa5b85ac8473ec28fb40427688f58184	1	0	\\x000000010000000000800003b21a83c50ec54fbf235275e8a8034a7aa1c679d80434fdcc20ce2c2e95636cbcf35da15cbe49234b977dec224ba7febe3f70289c5064fce34675cc1a6836209755cc7926d6d8bb7ef1cfc90725e6f01efce9dadd0361ab5d18d19872ba8989471339f2261aa1bde60a8c3cc6d32723eaf91136250e3f3d124e5412e4a9b1ac13010001	\\xafb8017dfb390a8c2e41eb6c693cfb15d2a21e3a91b365ef8dfc196ca3125b69184f640b2aaf65ca8c17c2eaab4bdfa7b647493bb3f4073244099b139b37e20c	1654688441000000	1655293241000000	1718365241000000	1812973241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x7d860d9f71d24ec014263fb61afb942f1a08b9d3f1a7169349c542a83dc3bf16e075467214a8cc40b4732e2bae3370613ff55eab94ab58bf00ba078ff112951a	1	0	\\x000000010000000000800003df11f951e0fc520cac820da92eb4932741e41bfd38407c7454c0734a6dc8ff147d32227667c3d1e57ef6967a074d01c98c74906d95017142407e176dd26fe4976b2710a81be3fd3de281be84e8d7eff89687411cc5fd7fbfe4a26aa3162eecd3450663415edbc4d6355bec3e855601e82ed63c835e4ab7828d06517fc48c9181010001	\\xf555896299fa8adc857cdb9165a9482aaa6483a476dc6404dcf001b0f301cea6e72c6ec8b08839dd84948af5afefb25a5f5535f20ea64bd802bda28da22b6f02	1652270441000000	1652875241000000	1715947241000000	1810555241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x7e46786c4d2bb3c56ba930a96aaad45030946def06306af3d5a2c07f8bc65436710321623094f9a5bbbec04bbd756f0e65a52d20e5fa69c46519e6c19002cb8b	1	0	\\x000000010000000000800003dcacb7a068682ff934ddff0db1dc5d523ad518b7adea3c0109f950922930ff99b0ded35b960b1a1eb8eb817a2ece507d99daf3a47cc28b79fa0484ffed25d45c0432d9dae135dac3125550db37164cc9e73e2a59f2a7edbcbf95e3619eb8cf777789572db4809f8b1b3f204477df58b7d790b099ef2d74c59fea37d18a2e3ec7010001	\\xa97fc49fb2e7a654387749d26cfb0ae5aeb6f82b33d0e30972ed98c468c9e7268b597bb320fec08591ddc1d4d44360481ed8a4d7d008c51b49fd90245f2bb606	1664360441000000	1664965241000000	1728037241000000	1822645241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
274	\\x7e8673fc6bb89acd39c269a81c847cb14f4e92740d4d95e114334e063ac6d32061a0584b102eb2927f117745babe4c7b7a09128bc4eec98b92f2f119a090e632	1	0	\\x000000010000000000800003afe96afad81cbcaa5e644416c4ae81ca4c2a0ee022c23d5f3e2afde8e4d16c412e5655cec188e9b7af4b7c46811cdca5052bffca8ed2b7cf038ab4342e8b5c3ac8c32d7013d7561c23d764f3a23dbed3b1b52f3e15daf4f6a79c7bfd9214d4ee055391c6c221cbe4cb97ebbc6f367c0ccf32cd5f7072e7b7866398670d2a731d010001	\\xdd52517111ff125270c400e567d9fdc3bb562f0eb8ab21f095ef4054432853122266c5213785e7cb0d7fe6f4c79b081581683abc6724d8d4fa9fbf100919bc0e	1666173941000000	1666778741000000	1729850741000000	1824458741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
275	\\x7fa681a85d421e9be128cd3f7bf8c39c2ec861a1b76831c1a184d6947e9716e255b1c4a0f630d98cf086fee42f842645488927e381023e51d6de634e1a3d420e	1	0	\\x000000010000000000800003adbc1311748f8ca464b77a54ec69b42288d249447f6bba7bef1c9cc2662b74c7aa5d380ae0ddba7ff806c92d9242356d048adf7317722b8058948afb2e320ba6d30beffd2c03ad62a4e42349241cf36e921b6890cd0276ddd0311a4d473b9a4e3bd9adc53e1091af4283a889d21746b1969ca67a5494cb3e58e1503c7ff40ae3010001	\\x9ecd77a9c185a0b881a8781f996fb78674cbc5dfc59d3e16c492c79902b0e88c2ddada2f9e3df206203610ba6f44198ecad2fb8b04601f5394db4bb266958e09	1654083941000000	1654688741000000	1717760741000000	1812368741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
276	\\x82b64ccf1dd3f1e8acfb9bbff8cc2b8350bf444bbbf36b3b25bf4d0373248162b6f2bf83ea059ba5375d582a35ccfa1c1a998e40c3dbd00b9e602f36eb588c74	1	0	\\x000000010000000000800003b0fe0173094f30893089408041bdf74a5db965c7381d79a015734f8c0d599c2a92ef68a00e47f0144fbfdf420b81a459f266622044e23f138dc3b10dbef063070096936ef514b8406cece16f528204c8d9630e269299ced53673df965c9483e6504458bf4588b39ac7bb2c51a91977d39627dcdf9c33c04de34c6962c7c900ed010001	\\xcf1e45d4c58a5da4c1863604c7928d6aa43fa30328f07454c17c35d5242b22362711efc35312045036b2c9b3e7797d8cfc4cc6ac0957dbe12ad9af24a0eafd08	1648038941000000	1648643741000000	1711715741000000	1806323741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x837ef6126239be757fc54f568bd3e1d00d528af87734e22b9430d1a670839f1d314eb0ce7ce4b1e066b6b29381b54403cfd2f555e6e9b0956e06716a845fa7bb	1	0	\\x000000010000000000800003e25c5bc2734f63cf91e5764e2c2266b35cf359863bb6380761da8e04294a9fa353930929dcbc54fc95621fea2e8b071b4004d8a7bba2f2941f169a5f465593a85eb5bdcd717f440511737e825a9c1c421647b9a54a38d63addb672b4e7a323056b5f6665201177f2391eec25cf83d1ec59b08e1d5c79ff0a7bcfe49cf27525f1010001	\\xffc2ed32fb49a4c7cfcb1ed97a2b3ff37f76f8de10c2d0be10341d2655aad0c348fa08eb30dc61625b7142f9f6f2e388364d4653e87f3822f874405cdc077e09	1645016441000000	1645621241000000	1708693241000000	1803301241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x835a42adb6fdf6d8075bd70828e237c29b5c402bd950a968fd15e0fcc6e32dad7a3099de4e3e8de14a769b20124d51e1e7a133a56c1dd5b1c92ea282dca4ac1d	1	0	\\x0000000100000000008000039d38bf22cdefe7849cf7d8d23856f98bff20e0b556bbeb76b4a249d379874fd15327efb4b8017f1b907772c78a469193be01d4243816705c27cbb61d56b30c03de108d43a185ef13d97c378106d5731eea3bcf25ffdae55eb900d24830aa6552cd65cae3eae9c50a4d9eefc581faea3732474af189469dc1f4e341710410d919010001	\\x9b3900244d01e772512f6517757c8e60865c57cd7d150523e3736b23ab2f3d2a3545c59db87b459656fd383b668648e1282a3d81b2e7e93bcdd816e345afa50b	1650456941000000	1651061741000000	1714133741000000	1808741741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x83ba11e0c2f1dde89d126c45013438c939a717daafdebbf4c905c4421d4a44d2b0be784ea48963c015c78d198ee9be1cf70b6a08fe8b30a86779fd48e17efd21	1	0	\\x000000010000000000800003c8d6a1c3b9e4cf28402036ce4f8b791a9f50545696839eb373fac313ed635cae53f73e7f8f5a53c8dc376f499a3838d0ef64b01f33f32062c042399da69c584749e9b7acbd4d1333b85711cb0ea7e701e1933cd85fcb181d36e2302744b0b99f251fa311d09dafa8cb92b8a19286f251785d85f68c5c2a83d8580e6d28eb01bf010001	\\x7e45a096174e2310236b7a8bb05e67fa7122ddc1cd090f489a22444b36b9722581063277bec467521747052e8a5eadddb8c05cecd5b69de17fc19501a698ec0c	1657106441000000	1657711241000000	1720783241000000	1815391241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\x838a55ed2383a9410f62c8cac408e5021097cc70a8aebc295fb578880f997cd75687e3d3968a53b88c7b4d626d1f83597a9bd8348c3ad00767dcb84468ecc269	1	0	\\x0000000100000000008000039ed6215ba5981c5aac5aefb1ab8560562dab882c370608ba4e5f129cdfc590e1a879d5823c99f9bb1c776d2157c4cd297a90f1d14f4e462e71dccf54bcb7045c6b4e741703377d20621cab66fa5116fb767502810d4af518156b1510b0e417d8770fa98a6f537c09384f558a50fb50fbc4d76ff70cd2434397fa80a1aa389891010001	\\x93483c379510c3ad39bcf7c9dc15234f21ae156e7f686d38c39de2b332242f0f37c6194b71679b27729521cc16275b8e7bf92c2379bf184abcf03aef45a3500e	1665569441000000	1666174241000000	1729246241000000	1823854241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x84bead4e229badb24ae285896869923811ac1c919159b8f4bb40fe0e52306cf8ab8404b6e994d0c395e8f41230ba77f7556c551ba246b29992b8b941b1399cd9	1	0	\\x000000010000000000800003d8bc9b785149181172024779b73a1f0af7bf18602b03893efa3b188ebce343b74429be9f3e2c0c8c1296ccd7898a0d64fd57e4f50d641a485e0f9dcc5417a6e240efe4390ffc9af3f49e4a68bae78ee1bbc3b546af6d46fea0f94bce75946b97ea0e2cf664268d7397e9f853ce5a839e1f962f6e35cfe779bf37581457f505d1010001	\\xc5ee98bd77f6af8c904c95c6bb6400a630a7244598ce4770f576bee693641ddb5538f4d23ce01a4f03b09df419abb65b330bd8ba7311310082e7c2dc3f07220c	1669196441000000	1669801241000000	1732873241000000	1827481241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x8752b206d7459abadebc79926a3ce2a7a5dad20b69d811e724fe75e495cc0ef59506b21a2887c2cf807a46fad8ec94eb63fe39ee48fc510019ac3090f9ef5fe6	1	0	\\x000000010000000000800003a084afa039d4034f2fc24d41a447170e4834ed482cf39dfdcf1016728c93cbf088562c2b011a1763ffe1d21c47c3f5c5d211cc95d130fd948f08f9c7e7e3b0d5c1fcaeee71fcb76f19c93c0dd32b26119d06843d0d89591384649092ee768b8e5e83ded5e95b72e2dcc7b52c011d3fd3f6c66c3cc8fae6eebf3d1e1515fe9fa7010001	\\x19bf0f73b30406ca46353736388dc4cc80560fd4992d980ae895d5522cfa05ee62d8e2474cd2efdc4fffe8df6c5579dd5125ff5697d1f9d83d9a3baf113fbd0c	1668591941000000	1669196741000000	1732268741000000	1826876741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\x87b64bd91e63364e27e5681d7a9beaa2bd06d37f1239352a4c927c9809b506128e917e49f00146a8bc9e6982c0bb0208302b291675c6b31be5136af68839a3fa	1	0	\\x000000010000000000800003c2fbadf35e08ba77f2eb50f254b64c639e907329f4a9ec3a1412c57e6ebcb13eae111666a0b8f043ed592701874e86084c80440569fbca94ab3c51a68a9361a61ffe9ef9654163b3cfe5c0a36b1ef74892d78a521c30175ef5de528400983b41997342cff8a1b513f77827ce950189f2e4fa7e77918457b215adb19d3f59bf17010001	\\x37e1d0fc9dca2f5f5e22341b7edb87ec3569059e69d37ec2936a957ad48bec64a3554223818b5e3c041fe3066375bb3041f528197684ab28901739c1e1328e0b	1646225441000000	1646830241000000	1709902241000000	1804510241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\x8d622d69934bedfa0215821a33d214a77e0432e0329e259909b30cbd19f5795b1c0e89ff8efab87e9a254eacdb4057ecf7df3a8a148ab1fc28237608f47772d2	1	0	\\x000000010000000000800003eecc597f92ace5e4e4aca10aefa33d5d56e167848ef7d0a4fdd298da45076ed71ad3980f3c0defb7528e9942911609529500adefcdbe3f8e688faa4b782e99ef577249579c00956dcbbffeb52a42f3451e829839679954498d3c7671139154a00ffae5142a2e93e916a55173d2691c7f68397c7313c9844d70a6167fb84de39d010001	\\x61c118ac2885f20b98cd561aa7845143ddae0edc3621e9fb190cb3fe1a2cd4994b514bc8c8ecbaebad88bde54ac8909a6ebe8e0698e07a6e194802b4e267b40b	1652874941000000	1653479741000000	1716551741000000	1811159741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x9346d51acb2bf83593cf564419a5086f549f51685cbea59092a2e6086449ec6a41c80efb9786181febd1770aa787899c51953c7759740174dcf53fd306389ff7	1	0	\\x000000010000000000800003d866e1e3a44e50fb0cc99d8b5e7c3f3583d4f59743a584a337ecf0098e21dac7f729f7cb1d79bc428474adf6c22228a5edda9f26bd2090de6a8342af073c7ecfd37bd4ac242d29f297242b6a674954c19ad670cead4bb113fc118242bd6aa68fc48618fccf61325630e349962ab4781d64d88841da31dfe2a691aea2b536b377010001	\\x6cafb7c5daa9aab2cd2350ba626a2450329f2e141fc8e5ae0677bab76d3ed89d7262af3792386a4f113219a2e383862f13b7e00006bf84a1566caeb602921e02	1666173941000000	1666778741000000	1729850741000000	1824458741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x941a8acb4f45bec2bc7b812ed0a27b16ab1138835cebdb0a7faab46cbe2ca8d166636f3d9c2a8dc52566d8d631b77fc749b40a940dec902a9fa1d0783e757fa9	1	0	\\x000000010000000000800003be911554afdfe60e9b1c7555b5233f1648739e2e0b2b7c5fa25fbc7584e95f2ccfff617c04cad7db5f290ca4c9d2aea1530f006b392962501af5e188debf0204ed471d7947529a61d906d51ec6969f9b60706d69c8b86aa90c6b8050f813665b1686623ed533c1a0a8de83ec7acbff5867b2aa140f0adc4b30ca3b91a4ea1a93010001	\\xe4439998f8f0043e3d11e4b408f02e8c0e0803f2bc5f04c5932a5ed5487473f4f5ca7539f4e8bf88395235b092adef28d63d5aaf4920c2dce4fdd1c4d76b770f	1646829941000000	1647434741000000	1710506741000000	1805114741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x95def4a747ec641d23a79e3f62debdfc1b073eb002c2c3480ae2010cecc181b4641182ee17aac5c1809a2d3364652a4577d7ec2c326cb60096d79eeec3c6238b	1	0	\\x000000010000000000800003be3288605c8ad6a2304e62f38ee39a5e9d4f237252692bef70afb7571835284f38d4096e38b8b5acc4584243663160e5729a4bb2aa3f6d14684b2b6e9d041c10e615d3026346f0b8aab2c929543af7d6daa341693fb5f3284862635ab665133ad976e59ea07a535421ee339cf2e1fbd08ef25942a36ca5004b74f4311cd3c4c3010001	\\xa773c54be0f174507e29227c65a23b0a7d8af9321398e20abb6671a854b79e19c19fc2bfb11bbbd56b907f25727af2a669bc3e1f1568bffe9776260e29861b03	1643202941000000	1643807741000000	1706879741000000	1801487741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\x9a9281e34d3d1d79d877016a89bf06b48e3da601306d95aa95596287c8fce3a279cdbf07afd3c73bbe2002fffbd67e78ceeaf32d0f972b864870bfa8f794904e	1	0	\\x0000000100000000008000039f736d3f62dc6d775b5c76f2e5c52f8087d1d3879aead36a0eefbf55e0b5501250240ef9de4fe869f56283ed720de379d380544bb0f472b33bdfa4d6c6cc79d70463e5e365d0b2a2185686c3819bc4993eda38b84af2684088e3d6cee64f587148c3fd812c4147f97da1d3bcc1baa1c030f74df7394b3b484a4e98cca281d7fd010001	\\x3efb80c527e91ee3dbf7104c8b598bc45cffff8c383a73ed9cc7755ea5d4084eb2bf48ab43739599e235f78fdce0fbdd3042f6951c92c3b503091b54979ead0a	1648038941000000	1648643741000000	1711715741000000	1806323741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\x9a565b16aa06bf4738b74cb2a85fe3951bd2ed08b137c3f429af5b234d34def097de6f13c246197df6f0b436b6371c15c058271764c5703b088a57c33191f8c5	1	0	\\x000000010000000000800003cd0a505d1277282834abe98d22c0cb4fcc7cbbda991b0956987618fd03720eb2424d24bee66311740bbb6ebc1d0d488db2341e240e7d7fc689383fd26bb234e93eb9e235ef4d1d50e78ecca4178354b2e1f7484b9964d325b8eb01120bbc58068479ba1c9aa2edce701c0a2d1e3508cebe53c9055ed7f83db6185aac55ac0401010001	\\x77c967d716fa0008c07869db84b357f9ac988d2400549228cf3e5c94498ed49ce1363d076d597d03d335ebcd4406f971f3744cddcc4fcab21910300c37ccb70b	1655897441000000	1656502241000000	1719574241000000	1814182241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
290	\\x9bfae3034837df6b5234eac4dfeae9be1178e54aa8f7675d8edb54bff46093d8ef2f4f25e81d4e787775b57fff89dddf338bb1b7b47d916e118218eb669b7599	1	0	\\x000000010000000000800003c345f1d816756491f76f60a326df92874307440296d67b317f421c1fd60c4e630f88c59503c243919e8c75dcfe7652ca645215b1e54e405921ab02bfba22ba7de2ec79574790a460e649783ff82bca1487394cb6bf3ffba9987d7d102d7f10fcb7894152e3fb3e3f5364d26b812736b06e4e1946a923ddf4c92a8c34d3f8e9f9010001	\\xb56e3d405cafaf5ebf2f257f1aa2966694cbf8b7ebbee7b10d4f4d6d545224685b4115aa5ef9d52623506dbeb4b8d6e92ab5a13e1e33af446950b4264124ae08	1664964941000000	1665569741000000	1728641741000000	1823249741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\x9d0a5b59b4dea721b6ecd018a433e71d1952feae934794b9f4ecc7d79feabde75d5d745b38a26eb87ca37a1baabef266fdf1a35043b7c238db8e298959da7ac5	1	0	\\x000000010000000000800003d1350d8c68e4c403293fb8ab62952e4ce13aa9b6489a476acabc356d8d7f2c57000add9761a210a47dde400ef67a4ae3db1fe02ac6dc7ffc4b93d35007795eee6489836ef1c069cfcfd473db333496e20553fab7f7394f0491376ef10f325317b0c145d2124f4b04d7545a145db131c0125c32036536d1d751a0b1591510963d010001	\\xd5722fd8b3d484c2da1519f839791ea4cc961529a4b83376892cc965175d2388c8e7008e510a2c7b28a0e99656ac29797a8bea13602a63cb27f228b7694c7f0e	1655897441000000	1656502241000000	1719574241000000	1814182241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xa6a62410dbac03059861886b1a0fbe65e5b355abf3fd919dc8880ec99b8965f0a0ba2873806f400792932ce962618850b8abfa8574f1010b84c10aff3d52b5c9	1	0	\\x000000010000000000800003b2b587e1e4d927db7a1a843f47395d0264afeca1390214de77642899734f4fc489937d5a8f703b254c597bbeb01ba0c669e8ec4ca80767f8b12bd8149f7fcc79cf44306b7ef65c02a65896bafdd437dbb0a415af8ba3256ae14bbe322508cb3842b72fc886a077d78dd7370d477045222f27691fa55988d61abba531b09463bf010001	\\x8bd580b5e9277b193335b04b692bcbe9a7fdd9d37f0e95ae8269a65cdd5f7e4eef664a8617352d2b630c042501a5855f737b147eca612cd96b35ca7af5c5ee03	1643202941000000	1643807741000000	1706879741000000	1801487741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xa6366cf8a3e4278e65742dced71f3aa50f2ffa48d64fc90a124d44eb93f5d6d99ede0f887678a051910846dcb53f65ba9debbd5c963a73aac74bdd6153269731	1	0	\\x000000010000000000800003bc00140fa575f7542d2a44eef63c5e81c6fca3cf610f65641ba0ee8b1141d9bbf5e7766c6a8dcc49a6b5d26fa6d59be36477069aa62ac766ccb323b243064d4c0352370d2ecf1f987f2aa042c1965ac442f8b4495db119d5759acd9c9860bf11c96f997a26e89169e7eab91c1726983ea0babf6791cf8c0c4b229f0620cc1efd010001	\\x7373377cf43828085a27ba7c8758c83de0e81e30bebd97729605a8bb1c934e72f6db4794dd675cfcbbb3b648151988e8ba8b3b16857bc87e7e0cbad922021403	1663755941000000	1664360741000000	1727432741000000	1822040741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xa63ecf2346b6b667e4fb190955f8c3ffb6d55635ad9acec378629c8b0f184a7747034584532509d3550998f896b461e11c08d7046849c82c2c44614417547a9e	1	0	\\x000000010000000000800003f7cdbc8fb32b3f97fc3af620bcea3f9bd0171a8a368e7a67ec2d2f88f3e15b9a63e0b652c368c4d7410372956bfbd3a2c6079e1e63ddd915f246378d8ec023b8ba4168fd20f498b7597356af618342bd07d37d6cfee6018615d4bbfd20d3e0317a94709709ee64e666a0f289b24823867a4f7e4eb92541bc3b948ddbc6ec56d9010001	\\xedbb75e5026a6e1ef7851fa89da2e5bdeb9ddd0426c8ab211c7b654bc8c79c2d3aadb67d680976eb6289c941378f7bf7e11e6328340236518f209b01ab74140e	1651665941000000	1652270741000000	1715342741000000	1809950741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xa7fe7c47748ee2721150584c6e298b9a1ed403e84c4aca623ae4d8b5700d93e01d6b01fb3c4504c868fe4f8cc4190446882088f5d4cb1c333638ec8dfb3c2428	1	0	\\x000000010000000000800003d7e57a58ad738d40075bd8d4334aaaabbd22a96d63b722075a928a3b482055a1e581d9d7649e0facabe823c09a21fefe7ec13e9568c523e3f229d58e90ba6d75f7b37ead3f8e3331085d84abda36de04d9800a3f4a29b9a06c3a6b0c49d7689756e1f4c88f34e83fbed2beec4fcf62158c11c391f7e29d2c6088c8b9ddda7f79010001	\\x46907377d6105faa5c92e67f5fbb2fa29c68d99cf7c6541ba5a6f244c359730beed57edb26d0a34ac2dc37b34787683b869bdd72b03460d006ca2f6b14ada10e	1655292941000000	1655897741000000	1718969741000000	1813577741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xa7a292e8accc75ef9c96998d0c7008ae0122940002b070173c9cd2d38625e3c00f95ef1f7c92be57a0da2f03bbdfc7722d73b9b44da3f80648c4aa031df4cc40	1	0	\\x000000010000000000800003c8d6a798cfc2f449fc5c24d85e1c392681caa7ebfcf9fa8fbe1300cf0d3f790ff232105a8e1f864bbe12b59151dc3fbf2ce02647d5c6836d7951d4e86007f10487bb5198a4c4920dd2d3e12834d0b8939120c836a6abdec66f93ba87b3e0f90bdf38befdc185376912d88c8632ce528fbb06d8d1bd864117c41656dba2a6e647010001	\\xc6fe2a2b4a93e61c81164805244b44514e94904274dbdbc42a5fcb6bc5ea0394c890e0dbc10af823228544be4699d60881cf03b190f12312c35479c3dc010601	1640180441000000	1640785241000000	1703857241000000	1798465241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xb2aec1afd2b72135a3414dfde13ae3e6c155955695fd72f30428962784e6dfe7f926b76549aa8cef6f7ff5229e60a489bf993747451b1408745f5b8d60ac40c9	1	0	\\x000000010000000000800003d02e559ed7424f6441e1099818c48819fdd15fe4307e1b224356d31c0902e3b230413cdf6e6964e98b357fb387eab6e81d1c70033ac889ae14634cc25d838d6792041c15ad2897260a5823b994c1190b965ce38598275a6d28184ad7a4697ae8df8a6afa6ac7fcaaa15a12c768f202347e7e4cd78ffae60a7b1e838ea0e72d05010001	\\x0b1f807687944711a4f365016123790c747eb8eae2f1d8c66622800b225d92b2b4a9fc9bef626a2cd0f0dcf9170293d2fd37952c8c2333750b30c95ba692d308	1638366941000000	1638971741000000	1702043741000000	1796651741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xb24a8ae79df9b3a2dba1cdb505d73ffc02faab81c9c49bf3879fae28f853117e563cebefc0502c4809e5875ad98158f7d621ade4f1f601de530032da90031998	1	0	\\x000000010000000000800003e12404645beb2f016f45ee76eba3fd12b499970014910b6562fc0310246a9b0ca58c4a7cfb98a624ea503dfa9b9ea8debd7d55e5dcbf48002cb8b124d98f3db72a7149d5fe8b60bd16b5878f697f74b1a640a2be4db5a867b941c48fb876ca2ffbd296b077b6070d564ea55c3b457bffe36836d298dc3f2d512bf8c7575fc501010001	\\xd1307548fae751d5e36f49a11cc8302cb94205e298d981ce209ef91a69f1d47ea99480592ab1b0eee62bdaaf6fc7e2821739f46f6f6d1d4de404590ce05cba07	1654688441000000	1655293241000000	1718365241000000	1812973241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xb42afa934909714dafd228c88ae998698df009b95bebe6238eb13465024d6ffa08532bbfecf669a93b8c3e9791e4f1d7737842be81aa1589cf5bcced9828fec8	1	0	\\x000000010000000000800003b1d77730b95a22f812770a40bfd0d9e56ec9870e6b1dd4efa1ff5b6081bbe3aeac3cbcaef69077554dc1a34904097d34f3b438fd552995152e0799d5f53cf0c6e001e60769837f3195769d6b8821baa2d2b21791e834489edb733e9a2d8804dec96601cdad2f8bf8534959940432bc5a35cbd6a085b9d1567335c74baeedfc4b010001	\\x2c3e7cf29601379f03d8de718ff703b2378fb83c98fefff860862597c3ba4897e4d426f85c6f3328a337864727d93fa39713f5a923c72fc00e340fafd6a64304	1665569441000000	1666174241000000	1729246241000000	1823854241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xc016f0bf3b87bacdb42b9c9a60178eed8355b3540bb889d4f4fa2308bf7a3cd2964766cbb335f59750276417bf39f585844b07cabe47ad596bce4770a06e61c1	1	0	\\x000000010000000000800003c587bd64f9c5dd5bd15908ed37ed8ac41c8cc078defda9c02a7abb3e12900ba46fb4364abf98dd63eea5420b05db299f723328fcd2831472b0328456d19a5dd733aeed6ceb9193d6a0d1f9be2a4e7aa741ada565584a21999e80d07d48e0a0844262bba571dfb0c801c6f76929838d9ef98575a7cc04a99e0677adeed47167b3010001	\\xdf936f5543fa34fd6b896a2856e04874b7a45e986f94b3a1b0fdd416fb7f83e9c217c7bab56013bfb22e94f6c677ce62b96dd740e092d1325f646b18fec17d07	1645016441000000	1645621241000000	1708693241000000	1803301241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xc066974c9acb37cb0ea8b72d258db8dec474362bba09303f695e69f25331af51facc5f39b10f13b50a5bc6537efd2566a9249325e8fff5a46377caf84a61127f	1	0	\\x000000010000000000800003ca8167f77a4e8d6bd5b860811262f1ac32a90a87b79114c0d02c3989fe548558fe4c57032817a8669607f12df868275c39e073bf30eb1821059fa72fc2ca8b04be9c4fcc225febd69d2f1d9bf769a7a99c988efbac9b8511c0b787c6f6a965d7dc2271b36bfa1a3cdd861337e6aa565da9526f24304e847547986c78206eef8f010001	\\x818bae0095669733c18b78b955139e7907339f1c17507c0f93655567d02c4b12b30ad154eeb796f4ea5fe96ca9af8babf397e915b189a73aa6e904921e36150f	1640180441000000	1640785241000000	1703857241000000	1798465241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xc0e6d8f1b62e55fc70573ce1374f145512dcd34f8054a033f7b13f064b9c3e098de9c93d78c4460a4cbd58a7f77805d43494ea66a4a4a58cb71dd739f011d73f	1	0	\\x000000010000000000800003ae7b17e13940d8c018a587179d770f61aa696f8663cdb8bf0e3f50f287b2c1707c5b41fe1fab041d0ab64a1d5139bff7c0f12ea98d5c39146ef9324bcae13e3433ea277d78722ad1c32ec7d6797877e247ee9a1a9c829f899092a3c5847135b4467f2de458aae2aa6179c89c6b49d15281268ad24d131ed411f92a35381027bf010001	\\xa6d4ec4b4e8ff7745d1c372abd7426b37709a530b528a8cb9ff541becb181fea61777c796bc6fc9ad21f5525e2557fa72683a28aa23c9d3a4b46039fe5945205	1666778441000000	1667383241000000	1730455241000000	1825063241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xc2860a37418391da98d4faabab435c12a8c5eb5a10b2ffce5fbaa76de119c2e1e23706691a667788667a3d4482f225e7c8e9c5c6ccd091cab2549c7d31dfc380	1	0	\\x000000010000000000800003c3b9b64b87639eecb3a9c39fd0ce339439d27db447340117811c92231dfcf416710bf40dc9d028d352332657002a7a06f4e89447b1a7faa469deeec810da86e1cee9d67c87c9f76fc70537cf8c5e373b30e52b7208daf9abf16b30e0c89ff07fcc5743ec14d6c658663600187c3fbc7530c780688ad6da134c74bb2343b1b0d3010001	\\x3d5a37fbe8cec744506ab2baf33a1b0e71e2f3daeae4ea583e7b28492cb59b85e5a11d2d67430e317e338f5151c7dead098a948d56674c2d8e7371b09a00130c	1641389441000000	1641994241000000	1705066241000000	1799674241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xc272c67edf57ff9310225a536d0f3f4ecc1f9b8d1025c02804867964a1f735f64c06c926f95d14c8085ba32fcdee2bd4ee00900c3d0ecc44ecefc12e52bff94e	1	0	\\x000000010000000000800003c68a9946652749242888661324923c20a3ec873f37e3cd22d960e3af334698c959c42d80c7db1bfeb457460bc22b2de4450b57425c16e5cf79915802846c234ea5c3584fbee1066a3fb23ca5a09d54b9c5022e3f4f65d388feef28f39cbd0b3d653a5c8b25892cad76fc9dc679b8fbde3df93aa9d461bb0e389a9b914b0879e5010001	\\x8128219289247997df0d51718e01ae2d482eee84f8e9e57bbbc6f3824d95ee1bd2331c291243d66b4734cb30871ebdcb14a9619c122d1b920449cc423ce75e0e	1646829941000000	1647434741000000	1710506741000000	1805114741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xc35ea747120fa2aef5cf0ca39c333ab8fa7e908896c1d247967c084bed4f1ee84bcd88b94773e2ffe78253d767a3e638cf07ed91029821ceb4e1a5325c86d06b	1	0	\\x000000010000000000800003d098995b3f2785ab58cc64e2a24a566eb8e0cfd2619ac76bcf5d46985cca00f0574b1e604043bb7f92f8b59f0fad0f42696a95b9a41dffd171bf24b8b00cae3eca934eda68533c7a0a26d8e11cb97641b6ad8886b6dd9fca030aaf1056e9ed94977a9b6f019efd923247b78140fd96af7190fbab9c09834c5bf12d677ed5b3af010001	\\xf17fbe26569942c34ba2c6285aa6b249d3cba7d0459f730e63532de28a3f48aefb1f8cccd9483597b526615528cf21980da83a6712f318b96e78c0ad2a66740e	1644411941000000	1645016741000000	1708088741000000	1802696741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xcca218e3db5737b1067d6d1b02f5dd047156671733dd341376ab3df7326106e10041a79604d169d1f2b7f1158baddadc1036b9daadfc833245d22f38151e0fe6	1	0	\\x000000010000000000800003a9612c7419fc4cc6992472f0479bc6eb4f93f8bf4db40c4efbb2292808ffdb0ca961ef93f7728c8c1c0aa9d4e17648a4016275dc4e20dbe34ad8c501babda82e62c82cc57f98074659cc31607a7f6dcb32ca2579992da9307480d2c30bb78f9aa27e00d695c208375fbdbf7ab70e262d4152284b42a64bd482bf3f379a02662d010001	\\x20d9cf443f88bd8929aed66e3e1cb406576a636491590e1d339941e92eee898e3aa0ef4666880f0bb7b91fc8f31cedfa62dcb92424b2c80f71f69ec5c509870f	1664964941000000	1665569741000000	1728641741000000	1823249741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\xccf69f3a234713d6ef74b2930b9de7dac2e7b783c1700941bad663d45fb66a38eb72e18c5970a0abc2ac743af2c67c810b878f8de9f83e8e38631f7dd889c30a	1	0	\\x000000010000000000800003c1b86fdb0c2a7d533d457009690f1a59228641263c6856aedd1a968da7e004f8b3c4ea739c27352cd692a7f05f63f35773b7fe8d8ed63b5a18fe911d380337e2da87d59361ab9caf05faef409c4fddcae4dca4481847d92354a4491c472a4fea1fd4ca49363e9e6954ab807f524ec6bcab3647a36c636b599fada869aa079373010001	\\xe4c5eb9d2cdd9d4dff812f13627bf942de93af7c381b3985ea16a3f7bd374e8ccfaf377f39fed87e517c33480059d0bd5be5af6f0f0cd9e61ad8cf33e6fa5b0f	1667382941000000	1667987741000000	1731059741000000	1825667741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
308	\\xd38e43caed9790533d5e65096accb4fced5ef4228570255dace8a9b543f360452561032e631e2186918916a6ff839cd294eb6a0b93761375b7685512d615a587	1	0	\\x000000010000000000800003b4e4dc9c76d03928a6f771c618ec2b9e12814cae1e7459166cbdf329a4d5ab2977ecb36ef1a2359bf30362264e05e43988359f70d9ef77d15dd1461ec4f3c6f2f3a5e9587a639ab7223ce028a6f8a77d1c8cd884da422eb5a53519b742d505200be2e677c48a106ba9995642d7ec5140999c559aa19536812c79df92adb3c14d010001	\\xbf7c09c26415e14e8212e66c2dd4505e491627c4faabc7a58d60da47f34f534b15391c7a66f01bce85fd4b581a6d7b694c454da539dc6e83c78b5be73d72920a	1647434441000000	1648039241000000	1711111241000000	1805719241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xd6be3cd6307340bef356d329ec8243b546698635adef70b9a97598d410422d7040c926013755696305006aa9b6f67e43f34a8db4999a7cbd6fe8ba45d48ac95e	1	0	\\x000000010000000000800003c5100fcc3724877c2a89b95b30fd42e8e725af92cd5d55a4289995f7807a93ea0784672ed8dc5dee82dfa9c382b7da80bc74749604cd18d882093ca980355e7e00f648e30ebcbfff938a8753be1ed332adecc26ab6fd2c9c6c251e30530aea18bfcda4cc0cc71744c12c4fd423bc3d4affb17ae6b8270ba1c4117bfcba4a2371010001	\\x78050c196e84b1fd79f5d7def0d173125e599cde2073d8fbc9c90950a21314cbe8c9051ea20d07947f57b0a69541f9a658b015ba7f4ce095f742c8047f65400f	1669196441000000	1669801241000000	1732873241000000	1827481241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xd63a9c8290276a7b63651e6ff7be83dbab9b6e238daa3772591c62896fd027f0ba75322957ba6c009281a03455794481470db2ec51818d14b004564847c70f03	1	0	\\x000000010000000000800003d00b485b466e9315e63a87b82d2a1d19a389bdfa14286d98fcad7825c8f729dfbe5d1d836b3553981675145cf0483641340a5c6a5dc89a3ebc03f5f4db00f5cfe523419f0a8544cb44aabdbf6084771bcb6bcad3c10b02127fde361574e85020b07f1a218594a4d9ba58509a01beba809929a37f09eaee14c98f1df90795d787010001	\\x9b432346ae824b1666322cc5b2d691d3894b84c99f4b183bd0d134b1368cc19ece2e90a6aab30d15ad645dd8729d9b4aa2633111620d1366e9970bfa3797680f	1645620941000000	1646225741000000	1709297741000000	1803905741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xda360e77983c34d17dbe51d100d2aad72d611bc64b4b9ed29a0f8587bb7514aad9229cbb93b10d045458a4aa3cec9feabff5f25c3e97dc3ee2d2d76baee57761	1	0	\\x000000010000000000800003c559538863a0f9af2b889fc2b4af037ff21923e85348f8442333ca39269692c5abdd9f5fc0cf935fd5287c72e56605040fba6bff71765165fd44fb6cf28a984ffae3dddcb96f8c8394aaa037e96cceb930f55a73eda8f3f6ec6c010b5e1db92b4d51f4873c0d76296998d9a0197d4d7dc1efec98e94dcc89198ec45986165419010001	\\xcb1b1beded353421080e9efd8a243b8c69b0b86c79d25d879ad39248aa388a70c41b871dddedf2e375e212a9d233cc796e08ec3be37461c8304ee35eee925c09	1645620941000000	1646225741000000	1709297741000000	1803905741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
312	\\xdee2e183114c218a925a406d80128ea622b488605c8f08fd459cb6c2c3bbcc07ee721cf28ec041020482d97c37374fef782abcb0f2d0f55426e9396c3ba5d920	1	0	\\x000000010000000000800003afec977a63a95fffd44fc7b5642b6a2faaf29481d8808f1b15931b47d139bc4cac28592b0f58e44788221afddd445122b750395928ba86967c9cefaa6c26c5131c3e0f11aec10fe372129fe2b6e2b34bcc6ba77330dfd6f8f5345a7e0ad9c2f43bfe2f51f6895267846632b673162dd1af87c74001de0a666df3e068a7840a41010001	\\xa5e4a010c8af6ea08ad23d6b9b8e22c1f86ab1907805f037f5f77965cf50cef71540af241c89b8ea06c4934f1a508468b64c3e513c171714fa16aff8711d7003	1664964941000000	1665569741000000	1728641741000000	1823249741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xdfbe1d6efe1591e3add2765de2ce519dfa16341293eaab3c5c7cbd5b242761c186dabdfc6032efae2cfbc35d21ee78a79e60da2d1d7807e54a414c6a513967de	1	0	\\x000000010000000000800003e1b7543f1e750b314767153942c7ae09d0a90f327f51cc0d7d5f900f3fa2128f2ac4cd3f433244052a37d9fc39d1d587e1edefcc7aa8c22fc1e10f3c1276bd98c3a5a04258cc12c751d8d0e49804d9753c004e2e94254eed9f3b3b1f469e23f629cf2c0cc36fff3d1f4f1a020dec25e4ec7ab27720892244e06334167f0d4dbf010001	\\x438b104b8b68b6bff168162b4cbd9a74d69344db2e37e0af58f5276570d4fd652d992e4858200e49abbf4f46617bc2c20e82ae98771ef6a8f7b310f89993f000	1667382941000000	1667987741000000	1731059741000000	1825667741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xdf9a5729d5ef85b3c73d9bce01dbf6eebf1ff77bbb8eea0ff04cf1885638507043ea2bfaa32c55475a630592e4eb0065f7737c5ce370e0689dbbd1748076a06a	1	0	\\x000000010000000000800003cda4c4f9a6fec2fb9017d09cbbe85cc75dd35a7e02ebfbab0445a38ec0272ed083a8e34a9f3151cffae77e8f6856b6bd1cb12fbde739273bedde50b2f08dde4177718b26436ab29ae1bec712a97808299565be21d2e9054e9f787edb4bae73007646841c23079d6363e41115d752d85a77e7990ecb6f7027e1e5ed0849d3deef010001	\\x68986aa888e63ced2d3b4ad31895187dd6907f7fddc8b8cd80be279cd23ba800b60404118ba0ca10bf23e944b1db8d39bff6c60f3b0edf5126de0a5f746c7f0a	1658919941000000	1659524741000000	1722596741000000	1817204741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xe492c4d62beed3a2ddc69e1aa9ed658238e3b0c4f861ef9d5265ab9173b836f9030d081a3602f157d1d1549ab7843121c873f4c5d622643e8fcccff8aa134c42	1	0	\\x000000010000000000800003bd4cc4823b9429c3e4601ef9d55ceb981d4e06b806a00633200d58386871c30afd6ffdb3087ea3385c52fdea50c44462d8aeb083517836e3ac8cf92445bb7ab730c8f8e25c5293de489364594caf96bf25bf2e3ffd0f85880056f403b7737e65074c8e992c322f7d515e9365092bfafda539a2aab943b1468036725bcc8bd81f010001	\\x07008f5630cc9c53f85e88252e6f7f86a520d93d8eace1ad75dc5cf2ac4d9e9aeb578dda6b610affc7d7fe5fabe1e894cfa4f70dc64ddb52f0281de1c8bd490e	1657710941000000	1658315741000000	1721387741000000	1815995741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xe6320db940d50924d60599cd9b23455265674a24f39b697e3dd221a218f5441d1edfaaf48b9f2de528e216a295f6f395647b0cafef12708be34fd89e71f538a2	1	0	\\x000000010000000000800003a3f2bcdc8e09bca1bc86879fc87bcc662d61b53688e87d674a12847cd2f4fe43be42b6958ff0ed1d9dbe7982ccccc577b6a6e19f58d817748b5457f727bf7360e087b42f0cad0be0585bb9619c3fc850e3c512cd950bba77b5796bfefe727398720482b6d9031f3fa48c918bfd4bad53af1b73cfb124893376987ff5a7ba2e17010001	\\xf42e5c0a956568ad43d3860962f24b96957ea6050705c9ce98ba4eaff5f046ee9a0f6df9cf8c0b1d8e68b3f22880252a907cef4d4afce03147e9198c81713408	1640784941000000	1641389741000000	1704461741000000	1799069741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xe9e29f0f0adda23db03df7103420ffe4a105de0b0b0a2f7b7db31a3ec7747932860305a24543854aec7aead6666b61dc18add1b74aeaed9a02d57400df42ae51	1	0	\\x000000010000000000800003aac15f248834789fe58b5fee661994e9e054d620da523e332307bbc407fbdeb64c789de2875afb55e9f8585f8f6bdb6eb23dcad2edfd2c8f8a55fa29dd81168fb246e98acb0150ff064b1d7aafdb0f60046d28ce1ed78cfcfce59c27facc52a262350616a81a03ea46b5b28633bd74b7e4660df0612e13721a70f8c75588e7ff010001	\\x617d937a675ff100dd4f6d769b1d229bca566add7b89c4347159057484018615635900707d058954d254a303f23d4b7ed005e48516ccb44504599db72428880b	1641389441000000	1641994241000000	1705066241000000	1799674241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xeef6924cfa7bd3fd5177fe34652f34adadf4fda7d8022f95ffe89eb41cc27ced90102160c9e4b2272ba838b41d619b4a3e7c0f9b483be8165a8fbf9bc0c505ab	1	0	\\x000000010000000000800003a99754004fe513d353b8bdb5ecb138e387e7332ea9876a6e46e1266700ef6732d55b696ee9642589c6e4d8fd633c17f54181624b624002379aca13520c9bceb9066b29b244da92c8589dfca7a7d0bac4e83d6abbd51f816d8f769848fa54f53a3228936663c8657c199daf860d9391caeb1969be9afdc390346b25bad46ae50d010001	\\xd234432b22a1ada5ef5ebfd26ed4966b5b893eb20fe728f6943ece2e89157999ba65e3a059917bb5b32b5e95db22eaf779a8258193a152163e98d222800a2f02	1669800941000000	1670405741000000	1733477741000000	1828085741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xf04e7b61cd215ac8fb757c7c8b710a619d47ddf4d8288cd7ce67adb779ab5f53494a60b03db9ebbd8ec00f6fde4e7a431fc35223a57220e2eb105760ad445ffd	1	0	\\x000000010000000000800003d48ccfc4311b28248541db1ca1905779a1134baeaf4ba105a31a9aee89b4156a89e9aa8ead53435c2bbd9ff3a798a992d4a0f6e47a512f607ef3bb91eb0a317f11485481ffc395885466d5248f76e0c60f695f6aa352662402dd4fb86059e67277cf70d1c4706f04f76625cacc6590f238c56218554eec04b5f67929d1879b8f010001	\\xfe43a90371eebb87691519cb49c8295f29b0ad14bbf5933d9b0396ede8e56900fb215cdafd37f1c72fd8b289da9380670b0b67d4afb1e6b43caaac5f16ff4505	1645016441000000	1645621241000000	1708693241000000	1803301241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\xf15e0da399a86b17693133db4c69e0bcc51ba6b6b581e99844cc241d8a429e6c0626446a93d3cd71eecf0274362e3caf395476ee93337872d684755bd74baa85	1	0	\\x000000010000000000800003c9d86387ada7b83559436c18a5703b72d6f9bcc1e3bdc49cf42802469680bf76630275dddf42e3dc0be9fe87025d89f56172568844a93e59686fe4a3b5666a2c21455048dc470b2922b1f3be28bfde53e7a0e894719e899eec5a8cea69b71ccaadacb02ee360b8a5eb623398d67df635f147d08258b3cad7424f75238c1756e9010001	\\xe36db0227b000a88248d576dbd0b36bd02a33fafb72e2c74be5b457c4054886c2d3e28cb428bb36a408d643169c4c8ed7fec3787f0acb1d4509db970a450250f	1658919941000000	1659524741000000	1722596741000000	1817204741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xfbfa87cdbe15c178610010921665b02ea8bdec12e29971ab16a91ff8670bf25c5d31f4a42b9dba8a3710c5df4f3b670644834a2d0643aef694171ab2807fa321	1	0	\\x000000010000000000800003d3d3a45bf099c8df77bf19f2f35e46e5b51be1837dde15336b84cbca274648d1a398137997c1327008d07d61fc5d8e10df0e87d1233a838db65520296b6d4693caa9bb358631d2c4f4d931dda1d65241fbdf40470999691e6033fd7e0b0df28726939e4b65203b4bc4f11ae12f55b43ec34a3bd7c95d13d884edf83d3a772fb7010001	\\x1f505d46c91d84e6443368ddfd317d852312c45cba8ea9069b3adab63674fe09920d399be69a48e3d49c300539fca39326875fd034fc1d27346393d28408570c	1640180441000000	1640785241000000	1703857241000000	1798465241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
322	\\xfc1edb4d423704ab3cf7567286dc3c6701bb56ad8f1114a2214daa95799eea882322f75c9162819ad3bad58861775d5c449fe2ce83bc06fa7c6d95a103c3287a	1	0	\\x000000010000000000800003bb73c3f823beb9ad2dd3e76ea445b8e9fdaa1bf183b22d3126efe232fc12c929ea04fde4ee1ca7451481f86c153a319005c1e39966f848f602b971eee791c4982983e68c1529d35cdf68d981d33dd8e1a0f178ff9a9a93c53e3a4943a0b9bbc15f63046b4472adfa75b1e03d99fb7d4bc29265475ad0647fd5e76071619ee4c5010001	\\x2273892d6c36d56e5dc674006b2ac0973a57cd506e038d6bc0992ba046fe77fb9eded80f87b40bc2ca729feab23dfae0adaa949b5d1a002f00111e1d87a4c107	1650456941000000	1651061741000000	1714133741000000	1808741741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xfd02344fcb57eb686b352807944bd1add71f90f068e9ec20f83d48b24ffd554c54b2b10dcdc8a2610520b01173b1dbabc2e40ec1d73c7e9b509a555221da147e	1	0	\\x000000010000000000800003f7852d380ca9424cd0e1ff0b031c9d75d94715aaf7e764c444c6c55c6a921950a92ad54b14d6d48cdc097833ad26dee802d79c8180e4400b5dffe545ddc38e0943b35fce248e5513a6e818812c13dc5028054d404442222603c4ce88807ae73b95ceb0194ea3558c6db3d42fac585d46f76ecddf21880dc27bb423814cd2b5a1010001	\\xcdb4ed0c618559099bd723fe47434e83a3fc275d8610ca6db2df0818c1a8ad5e314658b9f35d524bafd698b929b5615dbbd2b807f8ebc3c487c0e5086945aa00	1660128941000000	1660733741000000	1723805741000000	1818413741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\xfe26c9d41ef170a342634a5eff2e06b22e5ad1d65872a3d80f320d8f96b44cc93678cfcebde089dd9a95aaade7225e9e4e5b301477630ee57db3894da8e178e2	1	0	\\x00000001000000000080000398bcfa0559fdeb0d79ce3b673c2a9ee555de4e2e47cc898dfc6a30f30b6d9b18cff7fb04d0a08ff2c9df6a330f7c38cfa6ac6ce8c21bb31f4906b6131619d9c497ce8940f2d7bd4f117128c2d948dae1f34d7c234d131eedae8255d02f803c375fe4c9cb57095acf4ec12469825b07276ceb8215f9e67364fa0405388a0e461f010001	\\xd6638c0bb00ca8eaf18a6fdc52ef83b1d7b61ad4372b3f051133eb3ba16ce4db38c5b277e54f72cc33f5b34d05bcefaa3881c49eda80019a6081670bedc93104	1641389441000000	1641994241000000	1705066241000000	1799674241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x02634c757c044c2eddc51a8255bcaca207ca8e365ebbf10dde04b316287ed180326144eb269f68441338603830d2c7e9dd184e86146e3ff2e87bc9148e33d959	1	0	\\x000000010000000000800003b8780182b69a4aa1190081b29d5790fd4b4e931dd9e9cb957dd0c3902e34a816f33967204559a515fd7fb593c101c61b4b92072e9cdeb579f74643529dfe06580ed3300aff4a8ebad1dea9c5defc0facac2c79996d61e58701f1c30290b6a515fc32ba84b50fb50c674e349c33ed9414c796b0acec40a2fa95cdd4c3c80a07cd010001	\\x6386b09ae670791f9d70ba5dca5c58f1bb8c5950d60d528a343e20072803c0e27c143ca2ad5d8d4d27baca142a8725c6de9fe71edac9d54cbfb1286bc93c0002	1664360441000000	1664965241000000	1728037241000000	1822645241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
326	\\x03afe59f6cfdeaee4d8c0799cd1045c25c815610320adcf1d019970008767cf69a3fee94b0251e740d171edd48940a2dc8d955e5a22cb979f3902673a914c130	1	0	\\x000000010000000000800003e361dbb70f78276759326e96ca86972161278f3c797917d4cd8897a1e9a6aef35ac6cfed437cdc86be860ac4f79b92039f455a9bf76b1e246683c510c0eb2c9c52e79bacf630f045946b1753409c1ea80e9854c8c5fb35bbaf371bee1ce7877e6a944c6ebba57104be01eb1251ead07f61bead97beaa0bef845b1d8d895502b3010001	\\x1ece643e343ec58edbc8c85005552f2f8282b669d25bf6a04100ada566b53559ee39e7b737ea554b9211f8d194f5c4f9806ae502b3315f3f8ea11655bc8efc03	1649852441000000	1650457241000000	1713529241000000	1808137241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\x068b0768734daccf24b334b1118ca2e369409d3611c76dcb3838301ec1d8bd6fc751593bccabade6cf0e244697589eb307edf2a2fb688a9abe5ee7555cf5414c	1	0	\\x000000010000000000800003aaaa2b5f1683ebafa80dcc457f5c31c42c542bf0a48200268e578c157157aef98e9d2bfcbceda056724278d7495a323a585c61844b5bcb4d4dca3e833591d659bdb207a948d09ff8ff1d1199713bbf1f19a7661fe49d4e4e582974265103204d0e3a284d274a13f73569df8d85340ce5993de228c0e2530e1d74b8fb0d4ee543010001	\\x352dbcb784f3fe82ac2b18ba22636bcde41623664c174683c9bd2b6b51a67866492f06551eaa13a2bca01d708639e5bda97ae1f4355892fc6e4177e898c8fe03	1660733441000000	1661338241000000	1724410241000000	1819018241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
328	\\x14df010ca82b05c60e642827d1ef4e7ce005986a56529c991fd14ae4844cd5a02491acd867c42a57affa31d0d64a3f0dbaa3fa700a14f7602912b5951d479548	1	0	\\x000000010000000000800003ac9817f7ed027364baa3c8469dc5d3a6679bb3a061dbaae3593a169b67a1a65657eb04374fb84a38cb467377142e17b562daef7d43044eb38a6788045539bbc993cf2a9c3f0b82e47cf5d3e93c777250cfff3b1e79586312c03de3243cf21b6f64cc62c97835aa6e389131b8651d243ea7cc8602e0e26e8bb7a86a47b74d5079010001	\\xc27b486a95abf2afb6f8d330b089e1371c6f9d9fa8c0e5a3d5cc13b061dcc572393da94140b0062c0bd39f0b629a13fc36274837788554aee9dce10048c1b50e	1663151441000000	1663756241000000	1726828241000000	1821436241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x144f12a1937c726d5d0c9998713ce5797f9f614bccf7fa41be7580b11fab63a19b9053d75d3f9fd1826cc6336e4c1dae5d193b596785f1289f39525f5bdab17e	1	0	\\x000000010000000000800003c391143a895b446ab77cf73ac505f36ab5828db6865380b00fd0aa1680cf18a4e35603474123c153a11beacb40c8110fb171aa79e3a928442c037d185e6f79548651aacbd9e2c208d8dd4c915918b065e7e80e8427071d254af26cf958fb6fb798e84edeede52b6f8bed49b9afe9088a82909fc59347f6914e9c14f4c76637f7010001	\\x4752b16d9733f903a73a7a640c8fa3b8fd7b274d9d024bcffad530ae9a3f3df3984426e45274ff9cb7d3471dbf78b7d74c83b21836e3902cbe488f9e1a570d07	1669800941000000	1670405741000000	1733477741000000	1828085741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x149335c1462f4f3406b4e57627826e82dc880739c219cfeab58535bc43065c779142693cd708a722f5b5cd6044f395b85cc039a13c7a6b54da73f8bd313eae5d	1	0	\\x000000010000000000800003b6053e25e600ea998f97059e43b8fc123c51c4b3b640c501368f578aea1a276117fbbd3dacea4a8e5bff332fc1c929e4855dd825f161c06d43d8fbdf6c074c8d7dcfcb81d1a9037ada7fb7f57f064ba12c703eaa8c42662a365b25b9b27dfb5bdc74b49496ce1e1b24e101bb5eba039465da616b28475a3e971a6fd0be1f31d1010001	\\xdd30afaf830c019e0869f756a2106501dda729ab596dd99fcdcded5f4a13b39e1041df49e30bb22aeaab401fa96d8cd8538bbf3f84e4bccd08c60da45a5fd90b	1645620941000000	1646225741000000	1709297741000000	1803905741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
331	\\x16237e40a68e11e1e7460ed19a1136c691901bf6c005da4ab919e4aff9750751e9dc6beca9e668cc0e0b9ddcccba7eb0a75ca88518983d0461b72f93c0d6fdeb	1	0	\\x000000010000000000800003bb9dc6d3a559ca964654619273926f172b44c6a8733d27201a3a66d0307d163d62faa0cbdc173010c30b6bc3cc448c74ad8b055c4aeb467798bb689a7a12e38a219cc89a02ece9ccfac8c751e6be919696f4ed3a65d82329f505681c5e7a7f53d34dfe17823f89a0c44162dced03bda33f6f2632a47b5182756a761fe26ec52f010001	\\x1f26c28ac45eb4ae66e8d7212a9c4f2e75cdc134db52b20180d9842e3ccb143b6eae416ba20fe9dce0e2b3c39b037ec38dbd916b68b97374f8925b1526b28403	1648643441000000	1649248241000000	1712320241000000	1806928241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x1b7fc2600295958ada64f9fdb26615b58fdac6bc9cc803568735194216016449db12ced5cc8f3618f6ab230754a1dcdf522a11445c6be7aa50fc1be72f0c57a7	1	0	\\x000000010000000000800003d659a56c0678a586507869c57e74873c010f34e3bcc5e5d749dd011cbe7526fe087c347de7a66a55f83b6428b59f035af753daa5ede4f30e95559e490703a1361418f259a5b3ed0944fc54139418ed362a5f47a8c9937e11aa930286b988b27e9b0a533eaa083e4439dcbf4ef59c5d1da6550e3d71d205370acdf43625928fef010001	\\x2c7e3dfd5a09fa1cbc6b377d7a7e384e1625fc13bf8b5f796a883233ef15b4ba0ca85c1d8b1c41ae4aea46b4f9c54c7caa4bf1a3daf37cf8042baac0977e1000	1667382941000000	1667987741000000	1731059741000000	1825667741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x23736a67482554b097816a0248cf2080d64b9bdf5406d0dde6fade7d92074f12122865e4d4d06e19f1dad14ff8b7e5b31d2a8028deaf1ed98d23789c9bf28d01	1	0	\\x000000010000000000800003e608f1d8182b3475731b16043c84b74c9f94650b1a0404d95e1b9cd3720a6d64a6f2f9b6bb1a7dca1d6068d78c94be81fe4cc33694e39fc824f01cb4c4880112eb4667f11ef67e7689ba9d32d04d404d574a54f45c28fceb72ee9c0196fbad1e1c09fe32ecbc831855ebb530014a00efed81785ab6579c80e353bf9a483effdd010001	\\x8c285192a562e074836c604d0afb92493b07c085e4abbb2ce457692a9434319178c171e5ddb1d0d908dcdf37f0a422590b7be26351c9c0d708dcebf3a484b806	1652874941000000	1653479741000000	1716551741000000	1811159741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x237b26aae41f966242ce4d0c5f698e0473a0aee000ebf9a245c86c09f84eebc1db0d889e690b39b015409236ab193d90db079bca1ea1d06a1fa8390db9bde175	1	0	\\x000000010000000000800003c2490ea9f44b739f127e9306ec2551aa1b9ad2bb6fa64c2febff378784dfbc42ef7983fa1be71a546e2948d8104cc873363cd80fa7ff79377ab5a4acdf7d22272228b6be11dc3752143f458f84b1c7ee7e93f7d19cbb8c1db2557122e0b7b03db82292d2fc4aa51ece2c74e6bc061a3951811bc5e3f145c735e19dd8d0bbafef010001	\\x76121d85624b15ab38a901958a6418ef97235229bf003fc38f77a1ebe3fd7e09be697c7607070c19e7baf2b617c3d286041012846ffbd0cdff35ef82d21fbc01	1669800941000000	1670405741000000	1733477741000000	1828085741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x24a7c763963fd5f8e7ddb970b1c01aef84e8ba9d803993d94ea65bc94ab87908ab110b45d21232fa53a7d8531ce66145519f59f935bf50569be4a5c198911ba5	1	0	\\x000000010000000000800003d990fdb7abb6f47663e985d46b6930f73c73ca3c91e585b4037b8ac5f44e62cac507192f619dcfe55872e6ef6897d82155c4d036919711601e7f958eb107262bbd9d44d854fbfeda10dfd41600bcc1faf85e38eb832f7d74c13c7bc56e9948adb00a86ec0691b736266e3cd33202b5dff65b4a59247c1be257c7fc5a0464fa3d010001	\\xe06fb51e2b851106f0f1a183ab3d186272d7d6ef5d6c9f3c79d07cac86386c8a538d32ff93107d29b5062d449a53d1b728a140fde9847cd2a9ca3fd1a258a407	1655897441000000	1656502241000000	1719574241000000	1814182241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
336	\\x263bbfcc82bb63fa4d31a65093c9d3640bafd3bb14faa817ec6889d8cf3015c0bbf58d186477cf0732a69ae3dfceccb39c39e2234be9a9024cc71d6e91a268da	1	0	\\x000000010000000000800003975a4bc7b4857c5d520dfee321b7406ad5152b5258e80e246be6d3eb1b8f68b8fb61c498dde0bd43649622f42c635f2b663d112f7393236f89eae86636293fa284bc305c0470eb0ee987fae45d3d896a90aaad83a98e417876645da0f263fae753ca0b98caaaee84b0aa0e2b42b5cce4289be4b76fe14dba7fa063bc257bfbbb010001	\\x324b569f27e4b838de72ac6498bd1425aee669b0fd95871fc61d05a38627cd31264554903ec694a15ca0f5ebb4e0c4b1843456a117981215734b6beacc3ffe05	1664964941000000	1665569741000000	1728641741000000	1823249741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x26df9a35201275c2227fe0bb04130dd18bd803a2b434529e363848c45e84242ef9e5ab8d67540f32489e7ab1c21ae497a5d5b376eed7d7e94d3a18b027100603	1	0	\\x000000010000000000800003c682f22531f784d721ae137f0c2054483f3e80df090679d69e719aa8f0e971e02d60312783be6a7463e4e75376e07b85f05649b804e548490000e5d118b000a4a7f5c80ba6ccef3eb654e57aafeab50d02104fa3e2d2b91313f3ab82bf56b76bad846e55cf5e7251ba9f39edb835dd2aa886dd64a7a15a63354c955ed9da4d95010001	\\x7d96e58f39c57f19dadc841f4e0500ec32bbabfa4f9c1cbb1ec291044bda33792d89d1ec3052fd5f56f2d0a550b234bf7aa32b3e3e132fe20403a3d17221ec0d	1661337941000000	1661942741000000	1725014741000000	1819622741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x2b3f6055b623a0683e2046123f21edf405ee620fed1cdc4393acf0313d1ffa63f0c58006db79bb3827bbdf9634b3d471ec039203db19cd793bdae8fb042ead96	1	0	\\x000000010000000000800003ceb94dbf767cb117477f9123eb426ab4e56680dda0fd846910d384449e1ec9225a5d8970694bc96c25133d9bed7a4808ede582b091c594f2c9624e3dfa73461e36a361f12962832bc3362f7173d74034f01c9d63a04c7743084a24eb0d6cb75038d2dc31cb5588aee37e481fc5f34e2cbc33c63b74f8ae3ec83743c8cb413965010001	\\x6cd351b6a7abcd6cc6404142d52b587516113dc72757f44a580c0cef4d0793a5a5a44d9bf0fdaf03d27298424eafbe377fda385d1dd1d3a37427eca49bbfa30e	1668591941000000	1669196741000000	1732268741000000	1826876741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x2cd3ee202c930e9ba3de18504fe5855b510d1795236a5614e25686adde4c9ee87ca6a1decc1347677333bb89f59f2072969011f98da9c5d9466b50ea2db3918d	1	0	\\x000000010000000000800003a058e2f23c094afc4221992c9086f5d8897a6a562a3e3c7987e220a34a4cdfa0a1d5cf2abd36a289505006cb7992d2ab448c439aff9c8accdd17fc0e4d6f7f35ec96a366762ffe150b208ac5154603741c70040840303b46d956ba1a11bf6a4c338c8486ae33197f7a39ea1fac2ad202b4f1056901defb795020953955f829d7010001	\\xcc04d33d631f82eb368fcb228a2d125ba602536a884c67220542a9e1401abf53d2cd5b14c297dc7b371b97769ab1821f8d3127a1f5b09f54e05645601d87680a	1645016441000000	1645621241000000	1708693241000000	1803301241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x2d3723912c51df2c415d62dacc7cb7dc77277ab508143b3ce9b786cf58cadd96b4c66941d7fc510840c3b389753c855f6d0c5a5f0bbc672545b5d6a41a50d3fd	1	0	\\x000000010000000000800003d4df5eaded25b9644332dc111c7eeee9b6b7b434cdd873f6da0891f1ef494e7326d87996ccda166b063054f54c7ae6d748cbb41fe10dc99c754f6c41f6d3ef77ec37b14796de48970b35e809648620d6f159407d91280031ac23a70133c0ffd339b7ea56a31a1243a9c89986ef11f5b7e50d33b6ef2424a3c4e6bc6368fdfd99010001	\\xf311d012be5edb50637338b6f8c728f2e1bd11695e0e913f8e88eb7cd97662202b20f7a8ec27844d09f4bade1ab097618e786378902f7ffb351d5cde2b1b610b	1660128941000000	1660733741000000	1723805741000000	1818413741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x2d07ede800f34d2213101662a8cb6cd883aa2b0f861dc9b657e270ce25aa741f846fbe4c5e6b9b2c39daa34eccb02b9eb1892359fd373872c7baaf2a12a2bfc2	1	0	\\x000000010000000000800003c8afa0ea6c16d9a993b8b9e29e603f1e6bcb6a8decf1cf77cb176bd89a22edbe23963c3b91c5401481903bc945dfd7e10224bfb514c7c75822cb4479f4c32df2d82c34863aefa4527b0301665da7c670fef4934f60f6c50c5f67748c963df807ed9e130ade5e532ede946a6b2737bc79b7e30dcf8a94d35e800b700085a7b439010001	\\xd09fe4ce067a5d51aa1985fd1e2b497b7a1a0d05327fc0c7b79eae0b4043fc8d9335bcd3769f82e2641138ecd72ee3e4a5a04a59497fc75ba1efb736cc365401	1644411941000000	1645016741000000	1708088741000000	1802696741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x2f4725d0668d379c51c6e4c14593cc9cd4dbd25f8a41fed6db751f85801e3a8a7a237bc0ebd080a51196e9d680219273e42a460910dd1c4730e3aaf64c83b236	1	0	\\x000000010000000000800003cf9e6a23c025acd6d5380de4c570a14c2821e19c01025dde2010e02662ad33582fea4c6d9a62d2ca90129c71278a6b207b21c03b674b6917154240e0cfae77758b18cf000b16bcfafd1fccc59fd5a2dd4d667fd8ccd49dd0c472c45c76b987b27e82b4e067457c39a35f2d53d4b889f2e953baab0a08c7ddaa8d8c4ac46bdcc5010001	\\xbe000a0f913c7e1cd236ccdea5be9beede41b4bce1b6639ce2843b96ac87aad84e037080f8386de0b66cbe4794efe290701753aa6c9848684c72153d5fa42502	1643807441000000	1644412241000000	1707484241000000	1802092241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
343	\\x334381efa17153250d54f7c8d06d475fde9a71ab5732f50a2efc8972f44c1dfa4feed39a348a89bb818f5b1b8328efc7b0fb0a8d56f75d5c56b2f71df2ce2fd1	1	0	\\x000000010000000000800003b5c6b6655a331ab098c4eb3433e4ae91a7028686f6b384c0e06dab1e7665b53e66d59b9fa114ce980ce34c2f35ce5aefc2aaf2c716f81325940f9b6b62ba575a0f6a95d85682feeed3f7a74fffe01e54ed10709715f99202d3850cfb43518a9a62f13404d9d593279fab6b61614ce4acc26f81f55d69a3de0219613c9f0ff9d5010001	\\xc8e5659d0b9dab41c6d5e0eec91cef7b0f71f41118841fcc0b403fabe1bbab1289b70d4a223a3684938530b613c8e3ee32a66b0bb931904e02c30de5efe8ad0a	1668591941000000	1669196741000000	1732268741000000	1826876741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
344	\\x3d0f266a66ace4b168d1ee744357d76ca159a874d6fca499e7ed62e3c4ea78193e3a442b0c8e75d170715056f9004191976df27b6e7eb1ed956be4ae360c8306	1	0	\\x000000010000000000800003ba366e9cff79d720cca649b8d2458c460334c5fc9b739a38e1e14d4a1a69e15bdf2303b6549b71eb892e8a65b628ccf748b0bde8bd8eddb8974ce440e96a10d31663090382bffb0883a8c421c2a869e8ba06ae36c1aab260e1840287d06e6a5511fcd5484fb1b664fa0f82891678b61a9d120ee39044f2c88b5c7b473ba3564f010001	\\xe728eefd6c1de759d8743281fbe210be40d03edb04396cf7e2124c67d416d7b12677c3d013898a8a414698a70a25b4d4f994cb384ad7fa289c49b4d4ad7c2a02	1656501941000000	1657106741000000	1720178741000000	1814786741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x3f33d863e97c14609476a14039556337e1af5a8291d460c3fcaffb849d019f2c53d90204becc45b53312f99dfed0257cf838e7c9f2965f4a2893e295ba7996e7	1	0	\\x000000010000000000800003ac8b78a2a0b8ce2c19f61008101cdf8bbc01f29896a98791c9442b3370ab61538caf785e98cd7ebe9bbd0e6565378b02fe467a06bda9d89054d61205341e11ba8ead80766581c4855f0742ef4076a481f8f69cf588872e9ff19b55b10d9427f7020ccdf6f20a44c77949565e2f8e119799eb6f5cf0093eb497621ee69ad06467010001	\\xba5f22972237e24731fb02f307634d05df6b08fb8524249b77839748d27987b3b3cb2f987421db680053166f6b27d1dbf8264e5c456ee52025c8b13dc5d7740e	1643807441000000	1644412241000000	1707484241000000	1802092241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x4447be49a7d49021562b724fcf34c03af2d89880b0a1bc4b291fb8f0565b6e748ba30bb6dd19d7c8dad997321e10be608fe652068c3ecc2b70bad16ef5b67b0a	1	0	\\x000000010000000000800003da1abb75dc80c42a51ea08dd1bc0f327c606c0f2e5a22ef0d7c8fd4d0e24773bd8e051a019068f495a707d38e34ff3ea81dfdb8dc534edb5d4dab2c653a365de95bfff9221d003a4117542e74d2f854d3c79f42e0356356c90960e73456f7a2537a3a36e2621d8476132d6e031c5f154124c0a990ee48593ed6ebe55125e35d1010001	\\x26befcbf41fdd7f1f4a0d8eededd84dae183b1961be48b26175070cd1762e612d7b273092e1ad543926c19b06eeade17b85486f4937e06e0fb6b7ff3fb26790f	1642598441000000	1643203241000000	1706275241000000	1800883241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x4663f53621886c3bef32574dcb1d91a35b185016721eebba5cded5597df575737e2467e829497ccbd230eed4e306203dd9a95aec6434e5e7ae7d6c4baa638d25	1	0	\\x000000010000000000800003ba770225f576ab101a3cb88e41aa24b2b1d374c9a324723ee22c6b1c033cf4fabae3d100a358f3e49e2b1fa158f63e41baf9cb77bc256528991269569f8a076c74c4f41a938988a437c744ce6e511908104afeb4414a8bbc649a1c4f59337f586d1a11bc9eac083cb2537e42d47999714114751c56692840c39ff4e1afdb8c4b010001	\\x9c2a3ba534a085477500ffef082ae131d9d3428c1a4613ce0d8ca0846a27a0023d8f689a08f0a17461cf1cd2d74f762cacc17d49c7d8250b4e9475c94469220b	1655292941000000	1655897741000000	1718969741000000	1813577741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x46db010c132649f6aea03a469a475d79c8021681dcb4eb408b7a895d3b2315bcb5cf3f4a73e44c5b0883a9c49ad80d1ae1ebf57188490fdd1d7f8360238e6041	1	0	\\x000000010000000000800003e4e01425d49955453f0d9f2da1a66c97a14ff1863dbdaec5fe7d1bca01c27b45169d6143aeeb61415f323147989e93ce902e9a4c8d89f8bc7c5420babf3909e27dc5c968bbd5ad584bb359da2820d21c858306897bc605dd4af9d4298bf769508c580eda5f97857c61ea7c95bc708b56e9abe0de7d71da918e33bddf425d794f010001	\\x7ad582d7e133a3b89cd7d6a16b47e9ce9e3c3f2e75ceebed98d92d4d73d2fc2b90fd8e62e15ab25df519d83236beb0908c5a1429f5dea7395ee96e1d8afbce02	1641993941000000	1642598741000000	1705670741000000	1800278741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x496f877812c39fc5f8a8d0a06ce28c22058d016374f91c5a467e37e5498788cc0019c463f67fa8c683fd504e2d70efb8870e29c4eb7d9b24395dd341c059ea50	1	0	\\x000000010000000000800003c029778db7a148af85e3bb0a1f33210b643a83d6c613affdf10b5daccf82b162229e053c5abd80a392bfdaaeb6c0a6e56d940afb2c0da9c9028e96fd88ac3998ee6aaad6bcbea71345bf853c35a274291d80acc083b6f46e1340b852e595521d7d3e06c87d71fbc19471945bae26f8dc52a237bb8a003f9f22a45582c34b81fd010001	\\x4a65c3cbe10a3615107e22bb316f1968206800997aae60afc7d13544ef500aeeb331991ae5e488f0a79dde871acf4b5cb98e031f739d3f2a00cabd9657ffc107	1646829941000000	1647434741000000	1710506741000000	1805114741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x4b775e01c7b89acfee18c3542709d0448a51a890e03e5137a42ea0de638e7baa98c27a5e13869484c93c14bf1a6f94392c1048b3898bf4c7ebafa672ed10e62e	1	0	\\x000000010000000000800003b5e1cf8272d95e136c5a0da7197f3de91137d571b86346b1ddba7a9bbf414781fbf165290bb68859970fb88d171dffa3318558dc3489ff54f792eff52e9a0c03b9e6a858a83278d7b52810bdf014b0f130ff0653ef40a10b7f74999c738ab39889888e5763e9eaf46e980b9c6840a13e363437adda8bc56e11b0383b2e1bcb49010001	\\x121eb56750300635f9ec4ab2e8506aad0f979d7ddb1c2d76f2b798828d3a6a037bd51d8cf0740ff9be56531720734c49793203e7c93be1c2cf23eb58ed7d2900	1648643441000000	1649248241000000	1712320241000000	1806928241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x4dc77644a58b16aad3fba48a2f1f46ee91bbc51e4944405b526484d6c79e7a690753a0897006b91289c2993e641eb34881f7dafd03a2b188614a86e76a234a3b	1	0	\\x000000010000000000800003b39cb8569c381ed7a964fdd079a901ca4623fbe07bf2fcc1f8ab7fd1d40b9a99106d08e0fdd5d78d3b7688ec0595b7c1c17554d2cd3f3a2a64eaa1c051f2a6b9c63742bc33e3f3b220f9d14d421beef2ca2eef3b92151ed77dbcfbaa499d0db4dd5a3042d81719b3507d3a518f1afc22b7bcc7e9d3a12875e185c1f4f4fb757b010001	\\x1bb30e7045f26a60e829ca96507bc002f224fcaf2518a6c07d15692d0186af2f972204b0accc15e9665ca718566b5f0601d079fb400508cb062ac63721efa20f	1662546941000000	1663151741000000	1726223741000000	1820831741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x5513e2c6835db6c9e899e0f3daa43ecbd6891fc882f046f3fd92a4cc7d9103a8ce2ce12c65e819a542f07d7dcf9ace5433b7e7ada4262f568c5630fa187d4709	1	0	\\x000000010000000000800003aafce84f941df0820b1ba9b53805d8c12cb2c729d85c577572c77edb14321048ae9866fc2a92a1125630b18a2db84677a7fabbbb5128102501820540f24cb1bba7ff9dae7eb0b576dc565bfdbac42382461dcf7b1600faa9d1f438e6591118884c12016e50a92496367b8f665fc0f4bd8ffae7e1431ea4fe2fb45dd71f3ff095010001	\\x53b97e47e0cc097e1fb63c31ca47f57b3cb5434a70edf294575a4cac212b77fab22eb2333259795f64a9be59ca517edf1e5678a1b6cab07af81dd9e58de9cf0e	1641389441000000	1641994241000000	1705066241000000	1799674241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x56b7e67dd93f1f7f6ff48ec3fbca8472aeb03079fa213ce372090fb479546a7652df722d4face1cd7ea7d55efe98989332b29eef85bdf205ea1fd9360b08db18	1	0	\\x000000010000000000800003b7339da7943cdc31cb86a865cad5d0825422a23aafebda07554413cdd62f9c77f078a5c49ad4cf418879f48fd9662ba64ffca2f78d8dafc9a77c11161a6117c6bfe5ce89eeb7bb8e6d24a84b3552b27140cd9f73b2b7218bde8b060568e965a603d7344057db1a7654173e999936cf6ae9e54e73d0ae94be3975918668f7131b010001	\\x9ff2520681e32a5041ba7a9c4ce996f2be817427c3530f05d043909a51f103cab55b8e03673d644791461063916401cbaade7c2522f5c5d6f506323d6481a10b	1642598441000000	1643203241000000	1706275241000000	1800883241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x5ab304ef0246b393457f8de5cf35a17c0b457b5f91b6dee651ff10f98348139512d9c44e24717fedc409b161107ba6c527e749919e593e0a2834f3464adbeda2	1	0	\\x000000010000000000800003da227299dcd1bfa321f27cc80f302e94865e971aea8e541a70296925e8a4b07572d1e5019b6896c6675205874d7b06a57b78f71d74e636b3125f99d7f3574880c9cc32df61a9cd946bf74c83c0f8d705acb6007b4757805fe612dab2a7be7c85c45eaf1db6aeef298ab994ba4c2ded42ede0b490d69fa069823aa7b215cfe9f3010001	\\x34c41d5e7cb9b4d4ee2fb6efe702661e67f5563b896e6b3eb934c32916a07f9afdd6a0dbd1604eed46becbc2fe231e6c4d6d88abee65263d43320a90b49d6b06	1651665941000000	1652270741000000	1715342741000000	1809950741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x5c33a0641f8dcbf8610f85bde211bda34e297626cf0dbd642042af945cbe1450ae2e7ef08e71b07dc3b5b23ad2dbf3f3ad2ee8a3ed72ff08a7dd4971806b4595	1	0	\\x000000010000000000800003a63c86430da4dc8fd8626d7bbab896e64f8c2ea791cccc09296f12dd1e8a8b503448f70a1670eae615bd7139b18f08d433bb6ad14e3e36ef8683b87782dccb7eb08a8054599d5af3da41f96425f6c28235a9fb393699eced782708c18e35d6aa1e6cfe2bf1cc8d6160091fdca0068635756149470ae341c684c375706dee4c13010001	\\x2fd02692caae31177cdfe56029f102d4a1574c2f67c81a94f9b9a727441a64902569c661ab04e7368a3a2f2ca8b9e1902c092e238e183cde571fed67c21ff205	1649852441000000	1650457241000000	1713529241000000	1808137241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x5f8bdd17987fb05907dc84538a511122ff3721e9ead4e76808357aec1cf41c4b14d1e9656e8a1fd0b19629ebe473538b76552185004156363f4699a0984f2e89	1	0	\\x000000010000000000800003dce760af7f327ac318621e0cfb3f8154326da982a0b3ca209bd0593320810081c6cb1818c82d115618aa586e319c05ad4c9f2c91bfe1f5cab5474ea0bdbd5d86b17f7298565a1bff3fbccc4d1fda509ad5ad7fe26ffaaa1156304a4eac4598a695763bb42af0ffb8accd74db40d2f98cb5a8cc314d3797f9bf8c81197dd8f967010001	\\xaa07c17b5fe4958b60769b79d9c6a7d27da64f210f9914b2125dbcdabbfa19dd6823cf550ef6ef7edb94a57c27cbade1fe9610f41d5f0cbebcd78ee1af89b20d	1645620941000000	1646225741000000	1709297741000000	1803905741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
357	\\x5fa3ff4d48c44a43bcca3ba8aa0f857f65337e98832c24ac5ca5025a7cb02e263eecb9e74a97d3343cc9723141d655308679103c004944e18b51a9a117275f9f	1	0	\\x000000010000000000800003b2db67f64ad412cb31b8f39fc0ac259cc96bba32aeb4ccbf6e70cd37380c03441539efc5692ce9fb11248ba8f46fb0216c30bc00b6b96bc3cdd9c0f1768163d090423a8417fddbac384f05bb53d52fe663087493b945867a264a62ecef7b82a4481af09dea1d308e5f768b3b0b4f485777c7637ead3d949a8a4ee6c7a04b9013010001	\\xbe212df34620034c9bcf7283305b11b8c77b400bc168a207997e76fcbc9e118037d9c9246583ba52d1f838e46abe5b98f55874ef878287b4d7ed65400a680307	1651061441000000	1651666241000000	1714738241000000	1809346241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x61b3e35f06c391b51653e9c90e2df68aa21e8fa74181a96c35774e9400d536aac64347720c33a97edce5c72b68e8d15dc3f965bedd32f96efa636f99d2f19615	1	0	\\x000000010000000000800003cae9abe7aeffebd175b4d44b9aa7116671afe8c2cca3a05de7a4634a8c415c3f32f4637faa9d1130be8ab6f4ed8bcc1d7a0238fc710200ca35a9ff686dad45b97a51a14f2c0f425bb7ca32f74075478273510a7de73a453500c5a4adc2005853f679a74c64b7902a1b4bb03b4bc4685693b2980ea39cf1a5aaa3d25018a17dbb010001	\\x936e44ad96a505edc9de7b190ecbe86aaca702a199674c4efe6976c5577fb7801fc40e76736687438ffed02cbc579c44bc8e7092a17b6ce92f8eee5873c69101	1649852441000000	1650457241000000	1713529241000000	1808137241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x687b3959e31a50a0306f75b37c062f33cc612e1d5c5b8a2b0c36aff9bee51bc5e7909595dc393b98a3df70c5db896773d50408c448b54b64a38a1da844707f3f	1	0	\\x000000010000000000800003bf306830773cd0df179572ea0d1e752a8ca1e82ff35e082dff4fca2694e67dd9b178f0fdf5975707722155afcd57de73ea35aaff8f96d332cf344c22f0b4f378ca96adb649b4602ce720e3810e750a9d990178de2fad8f0063411bfa7a05a64ae3c82c61707fada9148033b39b173faf68b4d2227897154e5cbcd4a35c435dbd010001	\\x00a91ca69aed45f4fa0afc4dc73e56613f95f89c2ca3eb4195deb12bc56f5aa37af7c829b22469474472219c6e6993f8ac6cf77efcaf12e642850fc4bb780403	1638366941000000	1638971741000000	1702043741000000	1796651741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x6953c1189920ce4f0a04fcb42164fc4b5d8bb1cb21da7edd1d3b53727ddb616ee75d958ba7d0734f107de1ee170aa2a50830fa32871b1fc6f4955102f92964db	1	0	\\x000000010000000000800003dbbb582d1e340e3c391e1d86c071bde48c33fed9aafd5d9aa798b71945ff36923ef24677bbc9ea67169ed61a95c9c09737b592eda19e5bce2908d2a881061154d61de001d92ea1f4128469ef0a8ed97bec42472eececf6dcc6ea3773d34b40d74bae1bb76227ff8b04e550462ea31ccf1dc280b68e78aae1d0e55c2603b8bce1010001	\\x3785357e93cf6610740b13d85c27a50bea854300931081b9c77416c25c842e6e4887c637ec8b316063084834fe6155c8f485126b68516c3bf27905e90cbf930a	1655292941000000	1655897741000000	1718969741000000	1813577741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x6ac395f083c28f3ab963d2f43494a14d9515a98f6b9918864d127004d2fccfc0bc027bd1c37550e8f2da6e74fcaa420ce9301cf74072d11d4b5da3f3383f554e	1	0	\\x000000010000000000800003c1c6cc1ace57dcd52c7e33b01eb61d13209dcb8eb9a1a2d4fc5cfef5c7a69a76b14fcdef80a3c1fb3d10c0888a9f1cd92be399401c971d45eb0a2f8107df510b6c9fd0929df872f2dea6ca33bf1b3d5143a2e2f7453e161c8441edb0174d26165f1592394a6fcf60a90128bc7be03ab3f0d2f07eeb071f260460a34cac4c7ac3010001	\\xa9042dc8d96018618ee87955c02aa4269448f9439e96d364bafed2817e6df25cc0463bb3944d1993f477311f2a6cb43873a2c401717dbb2b4d4960eaa876050c	1641389441000000	1641994241000000	1705066241000000	1799674241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
362	\\x6d237fced35e1dd2e8934ccab4e8dd0a1cdac8ad36538d5acdd69f600f9c2bc3cfdcf1e356eae8de19de2332cbffe4103ed49a93cce8241b283a2911d209ebcd	1	0	\\x000000010000000000800003c14ff972c042e6133ec4ad98d47bd0424dfbf7cfade6169ade7e49eb691eb144f644a7e284cd8db997c22be079162a1c988737e5762907384b327b54a8fbdb7c356d9162e6c21c6c8fff85db43a8d5a9758751eeaf03c549b216b5a141cf1822c3446bfa077c36bb6afc50669b8bbc5baca8abaa64193f548b1be1f94670d35b010001	\\x94cf2f249a6afaf99300b2c1ede946a9d9fdff223a6553e96ede355643e13c8cb9a5aa020390e179bb2581c5d05ef18f832a758f08a3f9175cc63e0f6083b60e	1649852441000000	1650457241000000	1713529241000000	1808137241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x6ee31625e90066f3e1b6f9c94234be6012ab945792fb8946b0f4fc0bb449097723ff616bc8550da4c3addeb1ff1c37c0b7a12adcd4fddcc4ebd6b44921351d75	1	0	\\x000000010000000000800003af185a0d19217deb0375afff283cfe2576c3e6f5dddbfaf7069740ae3bbf975ae59dfc8fbcf13fc99edff220c991767e1c1e59c862def237daeeb31dcbd6c667d02cec9b2d94e5843690e5fbce1a4ed4db93fb4271204213d3725be2db81ef737f9751d85f32edc01824aaa73b54f9d36aa7afea4a317d6fdc7bae1e6de36499010001	\\x18fe7ff43075918cee818c93107ac06e334ca53b0db4ab289785a27b0d4a0cdc1fee4bae2da306988ebd6f0541372611ae5d6cbc39c348aeaa75ed70e1b0730f	1643202941000000	1643807741000000	1706879741000000	1801487741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x6fd7d2197808d6eba21b1998283ebcb0f7d3daad396c7a7b3a7caebb04a935aae889daa1f7c5fdfa59dd5a165483f94f2d0910964fc424315118361cd134c46d	1	0	\\x000000010000000000800003be5be58b6ea8890a7a3e620ebf295864a52daae684489ae13a8d9c62584040cf11c13973a787cea43e53d04cd51a700ebcff6d36bdc39706f7f3f27f98dbd759b174afdb3e37f7bf794b9ec40492e6797a89e9f921d8e015ea5cc4d4edf6db8558d1326b2c90372916cdbf57ac44c9f868cc671657b34277eec9449f0dcd3501010001	\\x15fd01b6515f818294f319cb552ea92f48ef9fdc0c986d9bfff5443c3ee22fdc8e96c9803c0c503f95634fd9a1f1caea84fab326b403c9ce5ce375726365d40a	1638971441000000	1639576241000000	1702648241000000	1797256241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x70df11adad6bb56dc31f9a24cc3458fbbf5fe03ac3000b9d6e894e36a2f1600b7446ed4035605b71e9fc056830f06e135884c0b21323ca81694e3bcefd343afd	1	0	\\x000000010000000000800003a2a12e2244d1708dfa901eca5dd83c70133f9f4de143a4fa45b042b7c853c22b259b5f7e2da801151337dab395a00e66e42140be1d31ea329249922eefddbec9e70b8ee75a66a0bb8a19ec583b6784517623cddcd9d8f6ec3435dd63be6bf2c8b79c515fe468be13e092de6adb72aa8b735747cc2fdf5131ca8d76dcec56ac75010001	\\xbf6aed2776a31fe5972b6610fddd5bfaa5c5f8534b0262805c31f1cbb63dac0bc513829554803599e05ba8060a007eaad9cd26fc523c62c863aa29edf60a5a02	1663755941000000	1664360741000000	1727432741000000	1822040741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x72572b344cc7832223357033428be5debd0ee6213447ea8a7b6192a10dc70d089340fd27c354d420967a59ee53e64e38f106b8b18c75cb350d643631bf12c094	1	0	\\x000000010000000000800003ccaf52ec4918ac3461f4f16940e1bcc0ba49e7fd0443ddc6346c063e1c8c345640271d7355bd695685dfc68dc8fd445452bc5ddbe85ac84f13579aa502b394221f4a814ad4f22459b105c537b768ecd1c428583e8ce8624783af11bf70fa6fccb09ee331cb7b02f403a907715beb7533ff81c5352d6dd1888a49764e51438ca7010001	\\xc30f2430ad05ec7195bd83a5ee7a49243b82644f7ac55a0795440ccf6b50ba751d72a7b122653ca1409771f31934bdfac047665b97410213910db8965822a80e	1666173941000000	1666778741000000	1729850741000000	1824458741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x73a7c79c009ad5e05a1711b861d9cc9f8a41e356d13c039243f1d8c588bc33640b1c93ae49d12af38667449f03538d103ec13ba16b087a51a9798e936c4d1266	1	0	\\x000000010000000000800003c5d22cb511e921e51eeb842a9d45e64c6cf293ee121d12f538ebddfdf387036b6cc7cc0570c9451572eff5582a3fe52e303d4fac16471b40147add325cef38ac09506e130a1b626378849c602f39ded459963e12d9bc71dec31b0ca9dd25e796b7b6783a574fb4c347bff914be3973a08c7017b578d06ba665a66b870769295d010001	\\x72688957336e5be5cfd2b3b82303e15d1aaf77603d183ee3f1f9bfeffc19b076825f640d9c7024465c3b66792925c97284d47685d49dcf90c425d9f9087be807	1644411941000000	1645016741000000	1708088741000000	1802696741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
368	\\x7e9bac3cf5042ed82ea8428df4a02df921ba4b8ad5b06609431723c431526f01f65103556caeca50c90918079782dc12d69c672e7a9891ca438993c15067eb8d	1	0	\\x000000010000000000800003cdd86e933dbe23b195743e1831fdf2a2100a462e67b28dfb9a6969f4cdd9e43f431705388bd6df649d53f390c576144843174687788c8f785263edac0c6cfb9c4e10d8891ec3ce7d015968a8fcef448e06536329132c692b2b19e74c6059eb7d3819b61c1f330525fdbaffe38d2d40a7ab5240743912f3de7305c41341ad4b8f010001	\\x1be590d79a0702f579464b14377c87012fb2152a9e9db5a067d4c9d710a03873c8bc1cb5d54607f4337c6eb51d555940ce1be20d87f816bce2b4e9383c847202	1641389441000000	1641994241000000	1705066241000000	1799674241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x7ff73716fb203a7b7697e0fbd967a31ac1df5d69f41d0e509aa27aea7a2dceb03480ec04f6b7a8757bf163b6ebcd866d22f21cc50ee30759e23b3d7f90c17b3c	1	0	\\x000000010000000000800003bb3b0c252745446e4fac40a18bd8d7a70ad218fc1621ec4de9dc427b2fbf8ad61359b5404da9d68190d4b98c771585e3d64f528d26a86841274e2a4319e366f537427987db677e5558e05b908595dec70c6ecd4ec35d26897f768baac7b38189c335abaf243a117bea583b43d9b9c991575a498a09beba32365e5cae4b6c9d2b010001	\\x375701cfa37d2cd2a20b22725e0cf08ef7b429025d6096bc053bcad71fb5db5882de0fcc1d72e42dd2a27803dddf39a51a61699e3e9cb9b3a881d23bae9be00a	1639575941000000	1640180741000000	1703252741000000	1797860741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x866fb0d4d35b758a5039aa08be3541aa436dfb2ad7a1149ec421411dbb44806d794abf36772993a00fd42e01da24a2d716e929be143664cc2aeaeaabdeefe8f2	1	0	\\x000000010000000000800003a59d1fe6a9b4281b136852980e332146fe0c4b438467f857fa97e6a2c78a4170fb36ba0cff4989b88bf5062aa75504ef08b059ba190e2279481ccc2ee23580b785535007b3b390d42bad966b7bd09f27b7b05f613c5f79b34f0cb4e5756c6412d7ce3069007f911ef584725e150e10f5b82fbacba2773d1da5c66afcdc31148d010001	\\xf365d3b9bb099442d95d4ba6ce59ea10ede69c96583391383b91fcdd4c67154ba1519fea451489dcb4abf431755905e8c963223dc6e2264654c3e69f4258bb09	1653479441000000	1654084241000000	1717156241000000	1811764241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x867787ca2b0f6bf658513489e98266e4c161a4f59198365d612801f2feb962c5b34219025d94603518d4953ec99b03401341e661e85d541f2aac08c5afb54f68	1	0	\\x000000010000000000800003ce847030f8d8a45738f665f7595005e47ed8d9d46f56628580d7136c3d4858a23828612edc9946a574f0ea20247d8ba12f99da096547fa7d4a08440d17eff071b69227ce4170272160cc3083c4fe409dfdab0fa4bfc405edd7cf85e43210aaf1e98deae0264d65e7bd7945ce2bad8f7ab49007ae18c8036219ab207838fe031d010001	\\x4be9105f3deb47d3c584ec2fcc702a2eea07d98913eb5da67adf158cbaa4fe232b35e97b41d523723391e87aba800e121c05bfb5e0ab61649a20ec50a2914200	1667987441000000	1668592241000000	1731664241000000	1826272241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
372	\\x88074bfb299d9f2938acf2380b3cf0e22fbc0f455ccf3b66daedd9b84b71ea6d2a5272887a60334ab68b8ccf2c3db2a9a1f22d14b127455c2d5bd266af90dad2	1	0	\\x000000010000000000800003da8883d2ce0c09023855d9832660d46bb8f2b88f0fb567aa1ca15ab44204a68de529a0d7c14d15fd18efb6c358cb989aff08ee473d261115d975360aca3f4642ae977e2aab393569fd5fdf11e6e0090d67ba5bb8c04a8c9bd6e472b55e49ba849141b469f802333c2676bd556edeccde1c4a3582b6026a87e1817a4561a79907010001	\\x976b9c67d7c20d47dd237a4179682985c591f8f5d18115070880a876c1fab25933a68aac16bd1dc5af71fc7c44dc387e16f3ec9bb2842483c3cca62225319101	1662546941000000	1663151741000000	1726223741000000	1820831741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
373	\\x8933b2f8be4ef866568dfddef6cba7c17b382d93606476f30fcd8204a57dbdb3705e67fe5044220d157df523a82abda954a9a20c734b4c9eab96b69960eae89b	1	0	\\x000000010000000000800003b418e252ca3822299f468139bf04eac48cfc2281dcd03e063e9b0c994d95a99cba1ccdbaf186c95694f2335ab77cda5916d8fa60e8428bce7f9cc755eae5c1e478e86b9e794fddce9cf0515f487b45d806f4a5f86a3d36763361a6c2baed06440b552460e1b8cb6a5e4770d9c9fc65a7b5e3cf20f26c021d059a044ca5da78d1010001	\\xfba1d51f4fa46b3abac7e6f54c604684ced70662771f658bcbea5be5f42ed1793d3986796e5c5cc9d43ede468f20d55024b0f81f27922cded32b2257b9886106	1659524441000000	1660129241000000	1723201241000000	1817809241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x8e9b9a51a24b24e8fd372786fa224e510a2b9dc09923e503c2e0646d9fa45cddb85b9bb8a461a25ce07870df78a4e297f7e545258b1547690b25c4bf971612e3	1	0	\\x000000010000000000800003dca267a736ec8fe897225989b927e2a1b34bd9cd10da278a44b76c5850bb13b29d72cf153faa8e839ac4df9d346e32d9e4ad01afbd165e93f73a249f6fa8ff04efe47e38cc2769e28d8d26aaadde550996f2a52279b182378ca77dabaa591006266d19a43c41c8206305587681954d93ad351439d8e747937c7a127e74640617010001	\\x200845d9352b7ff267ce80159dfc1944e06e32698df2d3fb9d35a16acda772b2d724e19f9353a62ebbb48d88c4fde0cad3562720fb27895a55bfd8d36cac6407	1646829941000000	1647434741000000	1710506741000000	1805114741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
375	\\x90cf47b32fc8dae46e400a60b575e6f200f4d5c9f2cdbf87ed112dda0034aa791d2a1213593999dfea40d9926ffedb9f4d07ae8f38ab4b2bdbf2c51c9faded07	1	0	\\x000000010000000000800003cb908d3c4945b68bb74fff8f1beefadbef78f8da55dd9b45eae345eb65bc82b1b89a142f435d79a68945bf5a64437b7459e12c6a443f851beddfd0c44bdd69c63a5073a27b8007b75feb212a90e780eb75c3c5b532f4ebf87a91b4cb3a6602f12a54312b26ba326c3c04fdf9c7b3dfcb9cad808437ac9c10526e3c91d8d5d949010001	\\x393912d2d293cf00867bbede0fedcfcc01c30707b80aaef1a29483123f8933b18f42f02e5e6f9e6bea2eebfaae4a55ddb1f3d62d61f47f2c1025c33fdc20f705	1653479441000000	1654084241000000	1717156241000000	1811764241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x90673cb7e88acce21e08a342b01e6c19fedebbaf0f15c9986e6fa0c494fca630b45576fb3c0611de60c3b236e4b74a7a923b91181deebd41c178e0fbfafc00fb	1	0	\\x000000010000000000800003b4e9cc1afa463828aa32a7119f926c7475a21f57fc09a17decd233c766af80c3952f0129f649aa9be46ec9c31a05158e2c4d5abd207da4178e867634b135b96ca7619188ba0947765205b2cc76f133279f5198c09e6a64659aa2195309c3ef6f6e4281b9b7dfa7429c86e1daba7b00174155231545f305419816c698cf296c7f010001	\\x4d8240fb1af92e3ce457ce22ccec47e711010d845a39c852252da6f6847f0c1c47e80a8bc14321b7dcac634e553f578018415b53833dbd4a768fed027ee2c902	1669800941000000	1670405741000000	1733477741000000	1828085741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
377	\\x928f7f4a36cb088819e09edaba8b5816568bf50615cc1e6fa5688783586bcfe6534a4805e0da555fe570e32e82120b138087de370fa11db79e5c7637d8c6a785	1	0	\\x000000010000000000800003b96d0e84a3a4df7644421da988c306ea1592930e8b02da205f7be5cdf11bf6418cc79c759e7bb915af45f20908d9f0aaeb5ac44ee046c8a494d7594cd96b49003901b820e3688d7ff48bf6f2f1f0fb4ee248ab83280b5551fc4e30196a7b4ef2673b45ead277ebaecdc6a55561e64086277b2e1022c24be93e027c9ec0acba1b010001	\\xa1e466a033da2cd4ea8d0c4d141956f8250dfe7e8d87db89c189ea1f9d7e51d68e0387f9529853d10693a5ed9aaa10eebbe02f384be4ceda84df3a46199d500b	1650456941000000	1651061741000000	1714133741000000	1808741741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
378	\\x922bc419062265748bd4460fa55f6d6e633d2a1f1a8678da15d30d5845e5cc7a50f7f77434bed32b61c4acc910c50f206d2f75f08c5fa6d33b2d48f0086f88f7	1	0	\\x000000010000000000800003cc40c2a3fcb1bfebc6794035171a773bc0e76755d1df949cc3bb0e198e0394a712481ac10c95afc59e1f76beb88d775f06872a4ce5e380d127519c2d97f3761f5641d138f21f3b89a477ac7c12bb404cf1135f88b657b9f4f3a6e741c37c0f1788aea368c79e3d7137d9eabb170e420a372960ddefaf787293f458c4446f304f010001	\\x6440d765f55267e594da37fff9a04bd08fea94ccf653f908e6a05dd1a101f1cb2e02ce8408d71e24ed3181a40ed54a2ca8c265339bed6bb335e0e5f630473a09	1645016441000000	1645621241000000	1708693241000000	1803301241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
379	\\x9a2b04a85db809844b539c3423e2ecf82d08c84ddb6e95214d6f5c5c38c27077695c231e03df785f0d082386a9f1cf4add9437d6845ec8ebbd91683bb8d8f4bb	1	0	\\x000000010000000000800003c7f91f0bed90e5eb6d758c1dd6e41a26bc9ce4947487c76974e4af11556dd8c7435e9414e0b43115e253b36fa5a1e4376072e2d04fede63bc9b13ba370afeb6d1db27e80924b76ed231a288daf937bbfffabb0fd6e70c6270d7243696054d92373193df02d7b7b6b42375c41cda506c4df3f53c36d35dc6801143fd5b75a471d010001	\\x7adb3a6e813495059e7fa14622dafd79bf07076a9b7c827c424b7c9abdb1c3507b38832fdf82c1dcbaa69dd75739083d3c56add0a443ea2d7b7a0a061be2f904	1643202941000000	1643807741000000	1706879741000000	1801487741000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x9c2bd52f90d9256afa34ada132235c2add2ebf64304e741f8b502fc474ccd9afd86fa298ebebee1f72c3e2df7697e4a6dbfe3d3ed651a677b47eb461d8fd4d28	1	0	\\x000000010000000000800003c0f6a98a737932e9600eec5e51dcab9d003b03ee4f0d8d29b6bb7ae00029d10e0eb4047128f2a200f81701eb783c586e6637c7657bd94019732063e3b3c160c813d1587ce0cceecea7560a5e3dd9c2b8f11c7722d2c38cc263d70df9f957bfc87223a6663397192a51a12cad1f86e32bac965e1e9dd3dd720362c476daf20a6f010001	\\xcee37395bbdbdc8e5e130c430bf01eb65646859f468a33d8ddf92af60555ba5759fe2982cb8028cf49722ce9d8a9b80b08e2655e5dd2fa2fc0a92f1f6a1e2902	1645620941000000	1646225741000000	1709297741000000	1803905741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x9e67d622b2038a99a594c6fadc20d012e251dfc2a2606f87e066d51a62e2d90d65a1b604a2f5281a00be7c5c5822e6507d90026a9a625e6b44efa12320031f0e	1	0	\\x000000010000000000800003e0df25c090382dc5c2e4eae77ecd843955f713e9e87391ad3dad3e7030e32c16d4105c96600068cb1606b908f33de14be8ed0555293943ae8223daee0db5edb43515e006f0214403dc34f783266f22d5d85a20b9a4976870fea329d9ecac0c89f8362820885bb648a42aee450c3b6cc4879d341f2c7a67b7b720ade6f4ebed45010001	\\x0c7899f6eca1234ed1e11bd96be431990f0ca23656d80845011a4e54e6c964e6934c51032302d8c6a7f3ccce86818b71519b0a7677e2fe8a6bb04e1d3817a805	1647434441000000	1648039241000000	1711111241000000	1805719241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x9f43a6ef2f7a0b1f459a065ec6de46ae65ff22355097b3a3a1a26b96a1177fa8d97fbb08648a2166c0f7cb1b64d0d69f4832903592e5766e476a5b0966273a62	1	0	\\x000000010000000000800003bc61a25ea7dbe4e3c3452b177095d1beb43ece601ef5c43de2cd647afc45d32fdc8b2821417fe4ce4b3e24d5ccf180135d4802fb254e4420579842f609a801544685496aa3ca3a3e62b3223ad402ba7f5440bde1c86ba96c2e1884fe1807a6c14bf0ba08fbed3e726be8c58f4eeb2bd70dc7c135fa8300b1cb44a67b4aad5db9010001	\\xb3a4ad2b23ea32d9960cb3ce818965bb3806d295cc9c03f9a49ce8300701561c3af6eb981bbc64a6686bd17d02d1aad79aa9bdcabe623faab330e5b83e80cb01	1646225441000000	1646830241000000	1709902241000000	1804510241000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\xa0c70aecfad1c78ecd38c66537fd77495d8324b8d007b215c5a4724f05f78f3af9fe066c3b3eec8045d78136a5e9836db741b0e113a76e1a98c08d7b2c8d1ed2	1	0	\\x000000010000000000800003cbb04913be2d614e523976be0984ab64a1fad6f0a0804247e23db97e43309cc93bacadb8d27cbaaaf0a8e426fe0e3c76376388189d5713049908c08d8f19ec6b8f7d0e8232deed75b2e6d6be99f216e3056c2cb5a4fb6e82e1b82651d17b67385bc11c090eba2f911ae692d58272410fb95538a83bc791caf8cb91ed6aa18133010001	\\x2ed6e4525928c9f2c55e6b4e2d5217ab5a0a5a402eb211a9f0b847f42f34479afb647403af406067d125f13ef54d0b8eecd394698e09fe1cfdcee16d46cdcd04	1669196441000000	1669801241000000	1732873241000000	1827481241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xa163655c0ea07c740a3f11d97ed4da8b212444e6da839172687fc3d2b407e8e0d730fc2accc801d557c9673654c37c986bcc923f2e1c2855e744ef48ddb29f5d	1	0	\\x000000010000000000800003f27beded017424aa728e6512816482ac3dd869e3b7fb2757e81beaf472dfb11466545f1a09f63a373149bad356f265e40f398477e98cbd6c4bffdbd43f13e2a0595585616b9caaf2d3b6adff028678d31b5e9256271e284ab33648aa2fe6ad0a137d0349817739b316c4c8d14d9359cdcc08fd0c7e6de90c6bc33693d556cb29010001	\\xba58d6421c5b23ca2ed1ba06dac8bceb95bd0412a9ecd46e6c9c5787a4cee0a50a7f5e27fc459326d6786ee94e4cba0da678a6d7f01192e9c99a8a8639370a0e	1660128941000000	1660733741000000	1723805741000000	1818413741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xa357764af4e739a603e4eff5420086b0740d2cc4fde2f2d309f0750d5ac1ece589bc75fac70267db2795e68aeb375a9baa95d401e6ef6b82f3e246ea6952c438	1	0	\\x000000010000000000800003b176574c5997947a28a00e04dbab6f2f951420c52e2b54bb2baa86e22852bfaa90d57bd20e85cf4f870d88b779124a064282ec5945bb873ca2668a186acc07e22c924bc9448f57ff52a810cb3e0718780122738173f57d00c28b05956bf5bc1c4c16f6f45825de6b786a9d258b42ae729285c88082c9bc8ba790fced55f51057010001	\\xafbc4262654bdc8d324d0bf6672768fbb4cbe66c13dbc477ba9d26618aaeea2c84de90186ee7121fa94cab5bbe3a26dc6441bbdf106dbc16ab1203c04c3b8b0a	1649247941000000	1649852741000000	1712924741000000	1807532741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
386	\\xa35bfedd5065d82c9882591922e53e6266a11b2d35ed9a18b9294a331d3a0364bc406223d678049759493b98ba7ab6f0dfbaed4de26668340db2dd45251ddffe	1	0	\\x000000010000000000800003ec79dad8c1d134029a3c279744e57eb3f77780359aca235d54ff9d20914c93065b80ef7924700b5d3fe7b53389226f3e2a526f4f81b5b8b2ccf9792566941493afa7da1237769f9f2245faed7ebb9380f73c7f2718bf58c131085fc73bcaba6157d7f74e3b5d9e85ccfdf1a6f95a65e42be87595338d7952de0bd0b1898c24cb010001	\\xc2e292d5be82dba23e9953b20de760e85c49f9ed8c61ef5d8bbfb8b957b7e771aa3830537fc1958e20757adb7d961f1473e24588eb777f25c06b2c2eca29860f	1652874941000000	1653479741000000	1716551741000000	1811159741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\xa6d39a0670873a9e78405c70bff6832b44806a844f9040a7aa3c0a6516b3ebbe11ccd32ac6ac517489bba301716327a17695bdc3f7dc9d51b518da3fe4f37cbf	1	0	\\x000000010000000000800003f130be841ab51bd542cc2838a01301df25e68cbaa0a3a84ef1b1b44d895322940643836085a139dfe186ad8de6d674c299e9cd04313099214e02674dd17b37fb117972078c6e6a1b189bfbfcd85064781d9e616d01d61349cbcfdd2067b5589ca7c97281c3d80988083b5ae00c4a5e8290170c3fd5665bd4a34d79d5dd6b73c7010001	\\x6fe20022d3fbfba0e279db8c78498adf25d969b4ac2807f476571889e75123e53186a5464738eeeddc72e63dfd9b65a4545dcf3628cd9002bcfbf12c8587670f	1664964941000000	1665569741000000	1728641741000000	1823249741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xa763d3e25616a7a96629c0da34e3832d0d694edba6c4f6b1895ef7b7144385f70b552acae3329c9d3a498aa999777a0e6dd43b8904103202577200d0d56311a7	1	0	\\x000000010000000000800003a84f1b3994a5724462864df7266017e3b111f9c474b5bd0ac8817591c7440807b558493673711eebe9729a12fe04e5dd71953585af6a019c7e505c8720f5a88e99b643b49ee993740b585f29d13d74960cce99d70bc9955353099cd3d8abec12c036c4c998ad6b2b40283b77bdefb62a9dd8b6e4ba3f196d5d140c71b8ba4f2d010001	\\x1e339181d7eff23b4ea976c298e2f5194246a82e16474abcf66aa4b565982e8bb295b505091482337b463c6f3a79b288c7e8f561aafee88b26358854f1b06c01	1658919941000000	1659524741000000	1722596741000000	1817204741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xae2740addbecd8d6fe0e93be711c8c920f6d8d5bd6306284d52ee3c431e213f8d4dc19744b236c0275eb87c45128aee917dfd16ecbf30659873b846675b4488a	1	0	\\x000000010000000000800003b0abd73cf2474b54d423552e3f62261c9e1cd224f0b8744677c908dc4cf353ce31ce725b62bf777ca49b40fad4673ba0ccd77e73c4ad4128e35b8670a0c43d5a17af27732ca4ee91e691b4b4c0754cf34e0928352a9a8dc48e3fb98a541f7feff0352f548c5dac371a3ba335e050d395fe4456cf13438180163b418549928033010001	\\x1df506112f761b22358d3b3a33bae54df9707c4db728eb61b78f6b08790f08fd46e27eea94299921e7fe046aed143ee1c519b1570cc90930b8de1a91e7c4e106	1642598441000000	1643203241000000	1706275241000000	1800883241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xb42b894f73c444729cb10346a0c2150fd0fa7896e8654ae4647e6d889d0d3f3568ab7b5606a7e550ee87c08c5c66c4836af8c39076f56381ef78c1be3209247f	1	0	\\x000000010000000000800003c54a0eed9991b5137c70ce89d2e83a154459807ce86567653ab025afa1fd6913d4a6e0f204a87702bc1d0e8a779efe08389f5d958235229d0e8e268b0c8dcffd994bd3af1a03e57ce4848fcebb57bdf6b79ff8b9adf48425c0c4d0851dbbff92f374322f504ca7adff19f65f72305fb59c7a1ab4a9b9c24fdf15d905a7a09943010001	\\xeec55734d90e2445aee82e4fd588ccf7df9379f71216f9ba9c440873e206b5eaf0458cea6fcc02ebdaad2937db68c5d8af875e031afa27891c9c62b88e08f501	1652874941000000	1653479741000000	1716551741000000	1811159741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
391	\\xb84f329af187ff93cae002caf41c44b4507faf144373a6a6810faa606fe9f4457f2f7b50bacc3f0b3946b02dfe5c879efc47ac7b0ca14f218d996dbb91fbf51c	1	0	\\x000000010000000000800003be1525ecd6049c92bd88a280cc5a69363c57b7ecb4d3e309b7d3b5ffed2190a0af0114b57b7b35d6b5db1635b61f72095bac17def7960e515e5039c250c25f3f853e16defb22dd175a565b597d000381ddd1ac9f70ef6cbbbafc48f66f54c21c2c8c0d28f755dcd4f07ed9d58e6fc114c1c618f46b905c152d63a082834f0427010001	\\x760f409b997eeb1adeaef83e68bac8be7a403e6f7da3a02cd30e5c82bc929635c730742f17f111a1455c6c95d5e159b7c59248e49d41b0c6089fcaa98af93500	1668591941000000	1669196741000000	1732268741000000	1826876741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xb86399aac9118c85b0aa6e9ce93e3571f7d52f606bb28df0062213c250940dcd9f6205a14bbbf17017c49c001a17b2f97ab59e9ec1c25a738a1366e6d5ca3699	1	0	\\x000000010000000000800003c7bed422d205752655b0c5ea15262d5f59142f2e51a92cc984b81047842bd6c615ae7ee25cc237b628d51f11c450ee0e88ba48902139e8a39ec0626a92b0cb152c5f5ed860fc9c43dbebe868d7ecca65f63522f447e70cfe8fd7db840be1d958542ac6ef1410a29db227f180612109cd69b73957639cdaf0e601e81537d898af010001	\\x455cc6df7f0b1783bc92a641a6753c845c6957d90573cd9d751f309afca363e34c6f17afa51491e595cfa261982736a9be5751773c5fb08862b396676ebe5c00	1642598441000000	1643203241000000	1706275241000000	1800883241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xbd6f0064f33573678f779dfb47108675e2ef50a94bc70feedfeeb7c2fc240cfaf10dcdcd019db47febe0034a6954b8d7093d4a0ab289c9cd7adbaf7130b45426	1	0	\\x000000010000000000800003c927bc2a3d2e260ec5cc5ab3b2efd5ec98f3b78b4b5287485c20a5ffa0900e76a2690f6be99af9991f02139dd1f064795a6a54920baa7c2bc05371badb1d2f8f792fdf61ef6a56e5c14492b33754a7d1a43b861635fefcbd4d6f8030cdeab32f772f0bfae0ca31dda2e08c0a40f4b4080a86ae424fda3056bbb215b458aabb3d010001	\\xeef3203afe990657dfe8938dbd867f211fd28c995a57d10a6bd3689c28873205b8417ff5ef425cf0d75276fe3dd3e665de6873ecc89430443246a5870d752809	1651665941000000	1652270741000000	1715342741000000	1809950741000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xbebbd0416fd5afdf901231d06a595a77cc4479be7181ae05e727e98b7d03b65c47c7943773ef2d60b3898f85402a98b3191273660a30c001e7dd7c6d2582ac75	1	0	\\x000000010000000000800003d68dc811ad19d425cf45fc7e4941f71a6c7261cc296fd4dd2d8df87b70c969c01ee50feca0aee393e58c06425a898be64cbe08204f90a4d98612588024e9705c40cc193f99bf893df2df60959650a6c1e094fb1e954c773f42c7f2c264301af19b0909aeabc27b5e51d9bcdbaf9188be283841caf23a56942558adead3ae9d49010001	\\x622f490dec2c54d30b80b7fc19b5689ed8182c78516c7166a264d4fc277485b14af48a401647d68f3e48e4e26ec04a9f96d597a62b44f3b9918ec44a5308070b	1664360441000000	1664965241000000	1728037241000000	1822645241000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xc1cf078f282a2df3232f41cba057a639726126b9730e6d6a5c27abb6164ba59ae75dfbd3472b7adf3ba55cd7d738d10d65ffdba0622c1c568a8a4fa078e5d774	1	0	\\x0000000100000000008000039a4c0bf6085edb8acf96478672a90f3a03d6b89fe161eb58c37405517160e3e32ebf44ca833c8713cb26582a208ab2bb721f0b6972015837c931e191b332a58ca6d0c5de7d0285dbb5057a9a1129cec02950630d48d959aff76b0394345857a6ef772db1dc154366f79bacf17e1c99fc7db052ef26c645de6643237dcc177353010001	\\x3ced37d5e4fa6fac84d6b1e58b811f34517a122d7d5d53481f2da42253cdc1088aa28dd80e29f5fd4504d0a1c198f2f85bb900d7b07cc57bae8e5be8560c100e	1652270441000000	1652875241000000	1715947241000000	1810555241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xc1c765976431c318f33b4ed27eaeface2034118b0605a03d84078ca08494935f9bb28b7b037ee51e9dc4660768a167a5affbdec912ef2a5372fd8ce076e0ec76	1	0	\\x000000010000000000800003c6e4d742caf3d73505cd671b15b9f10a650f98878de2f81aacf8f68b6f195e231380d21f30c70dfa7316bfb375beb5a60a9f0755bb98dcefdcd6e9e58d8c816c93b8f17721872669d59aab7dde964c02830d1b6999bb85f02f2aeead10aff26dabaa1077772d0e97250a0a04014ad943842c694e368d1fb213e71c203222ab39010001	\\xc864f306bc3336cfa3311e956fc9b41ba8a4a43a45c622665dbee69aa4e5d57e203bbc87c868c376c32559b85194867b523009a819275ddbe1555ee888ae6305	1657710941000000	1658315741000000	1721387741000000	1815995741000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
397	\\xc367e72f237022de14ce361230b8a595e75484885a58a35c986be353e638d9dfcd2945a3b802f473c0c56dc4d3ecea59a04e21a7664f88c8880508482055ed6f	1	0	\\x000000010000000000800003b3e47ccc05010076179d458f22b79182c193690bb7d52c6b7cf27fae67c515d3ddc9e621ed72a28b32383eca28b46dcd7ce71329b8c93ce4d9d12e9a4aca67fc758d61136cad571b31e4f9698646e52690a6468b5b804b60e96dfd9bc11e515827dd0539c5ac019549ec4f1db3d0582fef576b6df8eb1ce40e1a785870ef17a5010001	\\xfbbc25b6385906ce135cb001f523f76f76e16b8ef0913b5d7cd014e11285b84c5a9657d35cb79592ab93023854f4c9861ba950394a2fcf7d568f331acad5fa09	1667987441000000	1668592241000000	1731664241000000	1826272241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xc92321b97e1cf48f5a3a186a8fb771013bd1da27c3e82d5fd156fef3753fc5990f17273c43f226fcdea8d273470a533237a713f0e0844bd3d0700219f812fd8e	1	0	\\x000000010000000000800003c7ccda951394998f625446f584b8eb4e7c6f9de591717e5a6bc0b25e7d72ff11cdfaa9edf367ea9730302dab8054598dc488cfbf509a04c8c5f56f4e376d81f30ae1b225a9a0116f340f57f6c4f6031ab478c28a1235c8f48af9d1572c9d786f34cc0b6b7ab1534d7e3660c055529bcc55625fa3cc833910d76c9c4c0bffbd51010001	\\xc85e56b220c0d7c8b9a75ec17f37a37893218b312cd6801ded405b991694c9930bb82983becd1ab0452ed0053a11b828fc0339696e6824ec3870c9d5c5c5ef00	1652874941000000	1653479741000000	1716551741000000	1811159741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xca1f16f1be37c3910220942ce3381557014148f719b8d3a909846b2672ecba3b82b578c845d3f7a71dc311c268e4ccaefa6ef01615ac7b8d9adb9161faf2b297	1	0	\\x000000010000000000800003bf0c74d27094f02300923d41edac812dfe55982ac0cc160487d7b412bdcea9ecbcd1f23726dbae073df77fd58b7098cd58ece4610404b1ec6506aa72f6d42ab54564c0f9a2425a1933bfa279d17ac4dab44bb209cfbb54c4ce94aaac5293db26a9ea6dc0f6b8d655c083424b69f78c87144b0335032f56606aeb80059f432051010001	\\x803c93acf15ba54619b85478038339a6994e1f15801efe4ee31659e3e95f81657ba3a2b41ad14c844fb64b8a4390473617881236010ff0eda3bec29d09afb506	1663755941000000	1664360741000000	1727432741000000	1822040741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xcb9fe635277fe51d852f7397799d246d6626a82dfbce57690e08029cf76abb6c27e4d322aa12a8b562e47e5dce820b451e43eba5f1f32d91a16fe303006f43ef	1	0	\\x000000010000000000800003b742510595b0ff33613f5bb477940f8141b6183eb72face0c6afa2379f3787ce9da0a2c44dad9a929378cddff25cbb613b8840615b007de2d79a65553bd247959a70926db0f2743a974518b4e158ac0cb696be493a6bb7cac2e5e4e78bedc5826fd3e638836c6f4305e778ae730211f12895eaa04cc49f7a11edcdc72e5dad7f010001	\\xa640e24a6c3773d9419099ab6cf6e051ff213a492d115845d3b4b43ce23339bdc92e7abf62b111a292c6d2bcd38c730be38afaeda18160b4958d6b1af8489f01	1641993941000000	1642598741000000	1705670741000000	1800278741000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xcca3f1425a9bbf19fc3d8e159bc1e82d6ec9535925cd1372c4b2abf4f3d2e9fd1188397bdd542316c864ebf3fb38c7654e2c27e36eb8f3e0a350633cf38e3661	1	0	\\x000000010000000000800003b37934c40249483645febdc00ba427872385b9d5d8bb8b22529f5eeba7288082e34781c927bb47f0108a4277d3f0f0bc11eb776306ef1b4b361ef0ee87781d1c71edc7f5ce2f203c5a353c47a5089ffcee9d08dadbaef83e371b2030d835b9297f722d3dee7b22f8b64dab1ad2769a2b5cd8a0f8783d6e74298671c2c77846c5010001	\\x9b4f202f8603c93e0b5fdabafead0318ecf3d11b20dd2aab046d6bd28dfba8f12281f0ebcfad5f3bc958593e533356dab468a8abc0fe3d3254508227a4c5d80e	1654688441000000	1655293241000000	1718365241000000	1812973241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xcc1fcafa24cd7b32a961767d6356085a4b01ba4b2c31ab95fc5ba815ff97cb7467ef1450416dd9e8e3be7ee3dfab82da7147b1485f0bd3eb6d729f31b6d9644f	1	0	\\x000000010000000000800003d185f9ef4809fe901f779d480213e70bb9d9118705606364752297a0dd213ab8f2d6ea20695025167a4cbc3ca9e03e4345d1dbb141b53ef272f27526103b180fe105b5c41f8089c3812522a6e9e082db7c4a04c44958343927e54367cfd46e983ef9175cbd34a2bff47ca727a6c3c953d9b9ddb2a7744c72c0f0502422dd6fa3010001	\\xa69d411b25574883100dfaad66f3bb3f6e59ba3a7993246d4237f809cc19ea74ada45b4ea2926b310f9a5658cef49b2df464911826e353511222d41008bf200c	1651061441000000	1651666241000000	1714738241000000	1809346241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xce433f122decfece95c95fb00659408944d70a62f91a10feb5909adb427797563879a919941737f0dbc07d9bbbc4cee9263b937bd630892d3bfc71694c561fe4	1	0	\\x000000010000000000800003b5d4f2250634d13c693e6ed5d7d6ab124473f591f5fb8fad90128cd83897f1348588aeb8b87d73028bc1f0815cf7df83f0c5b111ef57700069e26aa7456f09bae6d9c8339aa888ec040c5e055857315df2bb75528d0a4ec7911aa4a09a4eb876b771d7ad13d653622cfd7f3efe934f9bd84f80ddd7fa3917e5618bf50a234aa7010001	\\xd607c9a59b3ab914dbd60fd080e987b71b81b5d4b33f4f690a2d0a0134aaf578a01b32f69e0002a424b5e06206aadb762520b409220e2f4a9123a9081be31603	1660733441000000	1661338241000000	1724410241000000	1819018241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xd077add6aa614abfd92fe2807cb43c7eb52e41473a5f5739d7a1103e3a5abaa57ef92a0e62c672be20c97dcedb40b9d8a10f459a611031071a72c485643a5b07	1	0	\\x000000010000000000800003ea19bc56f70f9de8d08ad386713f428b69de6ef4c05c1423479c6c5a8e303d957ebbc01d25e057f3a8f60ec36126d8e9addf74bf31a9e4a9684e80018a0a1433fd16c7906bbc3121f0e35b49a7fde1967e779c383512cc919cfc8ee4df70eaed4cad2dd9d2a9b457b0d59f2499c6bfb2dc2d870840aa56de693f723c2180d46b010001	\\xba5bc6d4ed6a1d211d148df3f76256801487f88187630b05f0a7eb275ef6333881dbc859df8074845e5e4e26d7e1f12ddb786beb67ebe5a4567e5c96431ceb06	1666173941000000	1666778741000000	1729850741000000	1824458741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xdbdfba18050f3716660974a88f7e3baf880f6b6630afa4f95cb7905bed731ff146aa0da45993957fc400b46a5355dce992f61cbbfcfc4e24d3a3b1b219ffe7d6	1	0	\\x000000010000000000800003e026cca824eb16ccc3d2d71a7284df49ec4a079befd2fc9b914c4b60253f0698f5b86c7fd0d8000d7b6a6f9a7aea6e9a9823d52f635c5e2d0541fd41d90b970ec69e533657051a2263bf9d967f3bb32bdfe59b62d22955def860179ac1a37a9694dd6f2f35015641ba169e4f7cd66c83402cab980544379a2f5438698a826f43010001	\\x7a45caa035e34305631a79902e8c67fd70c1d6e4112c9d8ed51c99c7ab02b92d7d1509ed53310af47a0c8163307a7ca6b0b50b0c6f9b1b4e7c65c425d6ae1203	1643807441000000	1644412241000000	1707484241000000	1802092241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xdbffbac9896c9c8a9bd54dff46046b764aff6af0a8794a61c44bcd23f96e3b052943d59d2c13011103cd7872cf4929fd2a9b00627d267612e8a56a04cf5907d0	1	0	\\x000000010000000000800003bb7d1cceef242f764332971a9cd2c63323169ca4ae90b1f2f550df4b60f38a05ba1822e7490dfc45756153f8daaac6ee3ba83e1176a1141b485f2902632713aec383a0f31d1aecf61cea14133b0264ae4c44af8f8860ec25a3398ed1d71a207366d0e4fbf44182d216a3234a99fa418fbefcdb42da4bd66959787d653de1b529010001	\\xad59079cdc2832bc444004560aee3bd961339eba1b03d108234b03f5824f595a5cd12df11fd926b6c13f804e188260fd41ad8125a79787eab8f39bc9e4bfb809	1638971441000000	1639576241000000	1702648241000000	1797256241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
407	\\xdcfb9b1cd6b1b4572246ab4bf71ef6b87d47e279cff534bea266a537fa917b8a31e2cc086fb615c7cd7e39024a48550b20921668e8a1cbc56715856a4428f79e	1	0	\\x000000010000000000800003b72a3e02bf0df088ba43da1f2894d73daedecf4cd68f7643a9b0f0624582989bc8e2b0da7b7e0c8869bde10fd13680fe0744ced1343705b08186f1f5adb7c3c7825ecdd4d50af32f7c893a5edf428d34a14dfea5ec1de656c7b5c95e8c5950565271ae9fbc8081bba3671d30e5b2f2ff084240c3d11875fd886b3df52c801f25010001	\\x5ff6e007897f61caf93fc2641d8678a1ff90c0e4bf413619bc366975b3adb4850882d13ac17d06b3ce0eece6e75bb78e65d2780862219aedb6986ab4f39f700a	1640180441000000	1640785241000000	1703857241000000	1798465241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xdc2fa1ca9dc133ec3566476d4c8821ccf67acc7bdd7dd41cfb394750dfc18baa1f1a6f400c5468575a519827ef8b5a2a50cf8ba41bb68ae66847ce153dd1a031	1	0	\\x000000010000000000800003d730ed1aaf13897a1f5a6370505fc15ebe5e055b9250b02515d85cda2039063f17c9497b271d7002f058127ce1760805b1ecf0a71a1d708d40a2d98a5cef294f5a0c1fed4398dd1449ddb1d3775991f8748ddcfcc6e513a7f1676df38704cb97c2f5b93ba2eb7c197a74fd5eb8f540a5527a372347aa2cd0144bfd00b99e0aa9010001	\\x65af38ab40de4f6bb644ed7241d48e067127a4ecd136e8e6616a614565843c619ec2bb2c6c1702ed0a09324b66eb433fa2a7f3efe3105218527cd6fc2a6d130b	1659524441000000	1660129241000000	1723201241000000	1817809241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xdf57e9bf552d3f8069456ab17abe5e271946c60470d3c45ec2e72f1337041d78372a3f5214d6189e29392701f8bc5addf89e9f54e2aba27ec98013b3ee120f1b	1	0	\\x000000010000000000800003d7115b55bbeb6922feffd27f5e646a51e1afab6b3374b14a42de68db589015c1c20b7df6673017adf928d57f292a86e2125ad324085997040ee31a7e112c350b729d6bc16fb65a829e8a73768fd2b4513c56a0f6c79fbe1245d06bf8390c98d0f208fad8bbd0ec73c2457a33f72ad5c4a9a5d4821a63f72b325797e5681926c3010001	\\xf7ea14e707971da6c6fb326b668f2b45b3d27fc003629c8c5178060392fa5ac7ff7d2960f219ef7c2d4157fca3654ba3ef68c12735fd06dc6cba103934f38905	1660733441000000	1661338241000000	1724410241000000	1819018241000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xdfb3de8d94a6b50b68b3e3c56eec54b0ad51bea52f26da8cb26190a6ffe3be1bff004631e7d4cc9a78aaa4f518d91cedc428bc38fec66c759af995ad810abb9c	1	0	\\x000000010000000000800003bede262b11a02e27b6d8f340f1a17d32da27447700b0444587ac8eb92dbac381374c7b23b3f80da2f5e4c650852b8db9d65a17ce40622eb1043f96ec5b8ee11e0fb098f122b8b2c830317e7020c9fed23398db65ced007313321af3d23c7b57feb404ef404513e79d03c663853db7cbf8a07ed38214d9058c46b0871198f7ded010001	\\x52d920002037363d4c6eaf53b25b3ddd64d11a445c909c3f93d7c7936226693282f8959a212b235c20083d12ccc42f1e42a9ed31ddba86a00b106f57ffdad30f	1640784941000000	1641389741000000	1704461741000000	1799069741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xe2c3c0718e7bba758e08d67387176ba1408e8d07dc7eabad6aa1679823db8a6c470d3e3c3c309c8e1c67d2fe7f89e2d6a4184b3bc5b4295bae6b039ae813037a	1	0	\\x000000010000000000800003b3895302f664bd5b9c049255a37d8e9516d4025f851538b97f3a4a5bebf36717dac739231548f8d98782d8603e97a52e34fd62bc25c5913d047c35256e3cedffbb5563631928490773839e4c2d06df42e4097e519016410484579d05e3aa2714a31870f2bfaa78d8fad9c473e0c8d6f73cc8eb3b8ca38fb47393d99af86fd6cb010001	\\x528d30185287a4f3374a50281d193619e6bdfd3ecf3ba3db03f4619131b8c009de814da8a1ff3929f30584296fff2a732537b054dee13c5f9f1a2a651cb6b009	1657710941000000	1658315741000000	1721387741000000	1815995741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xe37bb44a3bb7aab6b85948bc6b5ea93dfe5d423aa0443053a6b4e6eb21b173cf3ae2719640916992d566c424a17eb59fdcfcafb9cbb4df78eea156fb7006d50a	1	0	\\x000000010000000000800003b871ff782a778d6db9dc10ace9926d2b7c357f14cd4226ec4658db9ed01344cbaa04f993c9a233de3c93267f1ef5a084fd6efdd1c11f86ea3cb90e0ee9f0e9c008e99a0a72247f68edd16936d0d8127c7216c485cba0aad378a3e26561fe4b85615116be6bbe941648bdf24405a1dcaaf9e56b116085aa2d3ca2108fc5d6f55f010001	\\xebaed6bedce35b49c7f756c280e3875e2bd6417e0656416a797a8df903951df51b2cb76859e11699e375b10f0ae6fa702e1c54c215d4c9a1affe82eac7907d09	1639575941000000	1640180741000000	1703252741000000	1797860741000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xe4f3dfc73e169df4c3d6d8e279617c0e481342ccf31f408ad15c7a3dad3fbd8c37195ecadf8ddda23af73a7d1189f414b4ccdff55d25165d510741fde0691a4a	1	0	\\x000000010000000000800003d1577dcf1fdf3a8e5d9462388e40c7180f66a0e6b254c25f82551bed13bee2158dcddf8df7e9d1ab0fd544868ecc995266ccc70576731b3b7e78ae686718fd3df4d63b7f36e05e3fe427f23b213b9b1b76620668a962ab7a2d68e5df7d7f05729b1e984c20a0e776a873310e8222b80cf9290ad434a7c225bc3e3865e29f4517010001	\\x854fe9efb4d98c968094d59a0f2bf3aed0090adf2c0d62c9c9e8573678d65d7767af525ab7ed43638b77491a7e32a3204a29be1c72c158314b339d8049956000	1643807441000000	1644412241000000	1707484241000000	1802092241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
414	\\xe54bddca1a76e4843c90646b979ff23ee3a64cda8a703871a2a03ab49ab2f8bef4a74551689115ce161d2199c68f37565ea1c3c2c85bbcccc7c5d542782451ba	1	0	\\x000000010000000000800003bd7245dd28d1db47d7d777c8a09614d8bde1f3ff3edc2a80878f5f9de72b474a8f46c6963896b6d9a88aab313af63062b09de7ab394f365ca718c176ba737085d9359c2a30b3da871b9a951920bac8f44025068716e85a36ade6e2de87baf90c5861c5919efee35ee06e39025ff0b4a53bdda4f2f30f97ef4b277981e310c591010001	\\xe9259b35a4edc0c4966e0aa4570a7bc7935a7290adf366dd92770bff6e6656b3e85c755bff0515c2cacb210bf7955562ac5e1cc965a352da68807b746fba8403	1655292941000000	1655897741000000	1718969741000000	1813577741000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xe74f5b204654c1bfd964308db62c84749ff2962118c73ce8bd383370edf031882a76eb517b508d79a81b84eadf49a6c675c6b21db39f21168d5993aafa48830e	1	0	\\x000000010000000000800003c86eabbcdf777d311f6d6ffd1812d319ee0e537a7001e8f0fd04e25505f27c41a6a956f0fa909f5095ff3ad053c899b035657e264bcf66434fdd46493a1bbb5ef2e4967e7fa95ecf70a47734c2390426b67fc5dd1ea383978913bd557f57293d2e8d5f341c69bf110b6ced04ffbb7b71bc2bf0e217bc1bfc7e61d494c1ed6339010001	\\x79929032fb0a2e5dbd4274bcfeab8c18e5f0f3f4f53ce3496e2bd892d795616e3c91566ac180283fa37b0987abc97575ac47aaa62d49b7aa73fed91cd16e3e03	1647434441000000	1648039241000000	1711111241000000	1805719241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xe8ab8b6cb9752605cdf6525dc4c8222d4ad1158ed3581460e59d3d72b8d153f9c7d8aaf25bf9d024c4cec44a1b8f9c386bdb942cfd96fcd7d56b4d897d6d4c34	1	0	\\x00000001000000000080000397a171c677503f8204221158b9d91654e7aa39862eb2c827dfdb41d08d862fa25d697e744e438afbe73dd07c5f7783c3d9813d00f285578372a3c2ebb94bcaa6a8f1ce9fb7d5079bed630d7588aeacb5793b59203510e62995b2720f25819f5aa65dac300e00605cbd367c88deb50931d93b6daa03f526bd4fed7e1ad1ef9b7b010001	\\xf8a195ac5172fef3f3c8d4f89bddbc648f2e05a490101b7e7bb8dd1ba80ace8789f94e660c6c64209e81ad45f543ba9a31f6711bd6759304fec909948e4c4a03	1663151441000000	1663756241000000	1726828241000000	1821436241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xed4b1aa39229de6b7f3ca9e2cef140c8212e4805a6709190bec77c2d6aa2288fc5eedcb53fcdb68b27db40fe51792e54266c9720dee48ce68e322b2cfef81d19	1	0	\\x000000010000000000800003bc10ee4fbab09921573331fd66289f926e2686cf9251f2620064d21b65bb6c672894b51bb3e33c2b948de29ce946d8d10376b70901b5653b93e011b590989db89e295dd6ecacda502bb4e5cec5260ba6abba5241ac1639e5284bf5a4746dd51a1cea4d3981da9d2c1a9e356c367cd2a0a6bbf16b036fef2c9a8cfe7d73e5c9fd010001	\\xcee0919a33bf0a5258bfc3a1554cdf6c2d52a311c417c1619e37d259719a5c71a715efd1440b9928b7a9e30d519d957ae0d1e8d7c0059d3727fdb2f809696307	1658315441000000	1658920241000000	1721992241000000	1816600241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xeff781b3eb7e34f795939d0f9684b6adeddd4d816205b0508054fdd9e6803d8742adf78986c28ee6a9ec914c2f28ab53bd1495043b69a7d1b1c8814afa4d8b55	1	0	\\x000000010000000000800003b7f4a975a2d195b83d959a70a762376ee2c03effca6ba84e5dd3d7fc09c6a99bff1d91da17e12e63bbb59d793fa0a60dc0a4b85053f5e560faea0a67f6f2aa85a9f8c6e449455fb8ab7cd2486ec3f7ebe505284f3a99053bc729feb96af2faf9945f007a697521585e04389a21f303e87ed30f6b62636b00bb3ea534d03cf247010001	\\x6b9b65b1809e48fe67e085113656c133a33cc89b395a713f3de948df81948c0af9b1e959da5f4a8d75cefc1535d514ac65a0a6dc0a4bba2bbcbb1e36fc7db40f	1641993941000000	1642598741000000	1705670741000000	1800278741000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf3833e9244db82be991db2f44a69405176c0dc70a023e90d16bdc9fde4b492ac1fce0979aaf78f17236cd6871d0cb5b1dcdae41127c35a7d873613dd87cf12f3	1	0	\\x000000010000000000800003c26f47e07c6cf3db541335762df029f17d5c9aa3cfbf0a58b68dddaad3688f500924fc7cf77e7f0288699910158dda337eaa4b53ca7b5dd876bf7e3e15a6f9f4dd4ea42e1caeac3702abab0d7e744ca122949563904d378f4fd95b1cf0b15e3fa6726a961955554985c076ea25695b0e1b74cc62f90b1d24dcf626eb875573a9010001	\\x83146e2c5e3118d47057b9f77d432dfaf79cf4f27693cd84c9328276ae7c502953152ebeaa8015546cdc46efc453575fba1226d5d9fa3ef914db690da3bf430b	1657106441000000	1657711241000000	1720783241000000	1815391241000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf36f44751be59c6e69ca2b312decf4ba502fafbc4ce9aaeb33723336979eb51f6cc9090fee72bd6c6ec5bd4b858a8fb732a9451b5cfab2df1f88addf037326f6	1	0	\\x000000010000000000800003ede8d78ca527403433b37b3da2aba37fcfa4bacf0dd72bdd0a202383a6fdb20c1dba628d30cdf66777cbfa000cb3a00adfbdd203d2902f6611c826c385174ef35ea4773c4225511f4a8276059bf09425b9c964d0a8ad7a64489edcf62fd31377f264edc981785551aaff61db6be16b9b65ceef2671f43cadf08c54f32a007fe1010001	\\x9f582b16d81d96722398b6a34f43ef3ac1d879150e04fbbd2dd7172742541abe0c3e41a73a538555646b8808e81f57b554c96242830b8d7ce1d8550111f3090e	1667987441000000	1668592241000000	1731664241000000	1826272241000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf3a3b30bbe27b788097d7a94f535b63f6f1fe45225033aa965c3994f34ff3a6ac7f055afa75e527bb9fbcdc5ddfad89a41c84cbfc1eb9fac97149012e1c8b408	1	0	\\x000000010000000000800003b942c43db27be3d33909d923f4e03208b2917ef5f12f7358872a14be2ce328c6d7b42015738b20a02587d094a1fc8b8fff74237e0eb58383745ae6186f29a8bbcbefa2159ed797366d5e91e51592394659b2f04651076e44b04f52f83a011d2619ac8443f7ec2c88c8f5380dacf916d63fbd7a68ff2a9469e5bf4e662b4d3cd7010001	\\x36d6aed24c64e025df33a24707c8e2fef9aa317e6573e41b6db5a58bb58e77d28ff69bcfb67b3f7defd4d9a272efc2bd000f9b2293567a506a2f32c8f52f270a	1640180441000000	1640785241000000	1703857241000000	1798465241000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf4b7e2748781e52ac477ca8772743ab7373eb2e3731b097f9e096c53e55b1627dda7c7523bd848665b1b3cc64b0ff27ea6834dbb4b6e20e03c53ef731b5057f0	1	0	\\x000000010000000000800003ba71ca2190c7c817d040f22c24a88651ef581fde2e2fd77ecfa49402018680a7036aadaeca6ca5b5808e20d351833263fc9cbb4b6fc49fafcc206291db9f97e1157b132d0930b8d5552950693cbfe3cc53f8b1fff88f85912befbe5bb23bfdabb7c89f113e39577ef6f531f8558afa44fa32ee758405392d4b965f1e2e71ab47010001	\\x42f14043b02bd030808b93db5124827e08cf3323b97710644c53f404b23f596d3439ffe1aea45c6c7594328c6a396055e15acc956c768acb1e259f474092400a	1663151441000000	1663756241000000	1726828241000000	1821436241000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xf8b3fa627081ec67f2d2a7410d250f8a6c8c63898051a363cd5c183973de0b12bf2451627e433181f92541828e7999dd7b8cb848b6036ea4726a0bc59ab00ce5	1	0	\\x000000010000000000800003bc04a44c36871c07828350d7a5c7ea1f76ec51bc6a03a7b571ce629477f022a86099b8d58693bd1ac60684545b8c6ea901170922d661a9d383f009436cb58845c1f1597aa36dc9c59c4aedfa69ded329bf57b7a2c740e574aaaaf5bab3c1bb5b3f565976f2be9fd2770589d9a09ca06f1c76e5916af9282150b2ae3f879f8c81010001	\\x7eaf2d488d985ae7ad5365b79f602b843df7bd353a6b576cbaf24b3789e4d3b9aa58997b317b6b306090e39f4a7a06676645ac384392c6eab3928a095ad1f60e	1666173941000000	1666778741000000	1729850741000000	1824458741000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xf8bf78861dcbe30a3fe5e847ed2885ec22ac744584840e127440a19df0e2b062a475e4f96f80e8297fdaf4a2e86b523f27486a747f61fd8ed989ad565a9d26a0	1	0	\\x000000010000000000800003bf9518bef6caf0d6d6cc92bf27a0211284bc9dd8539b982edae99539a21e1966100911ecd44f12a002301256f0e85ce15ed2ec6e1cb161b7db9d05df57a4f3b7a1d0e3a7ba1fe2ac99f0b457f12a9e5170d4f89fa08c50e59183eade6d7bc6d377fb36186bc473ce9f43333b3bd73d2604d5b5cdc58bf0f14f2803816b1cc6fb010001	\\x91ffd7617cec83053485a282698ce0905b743966923c8b6a5ee90cfc753303b223d691f607791ae67873ad262026c7c58662635b684bc68b130ede3cfba8310b	1655897441000000	1656502241000000	1719574241000000	1814182241000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	1	\\x4fe9e894a158a6880831024afb7768cf7e2bf63a0dbe851684770ec4fceae82037ce1e83e9994c88fa00c032fea966233753431cbca0e372c0e869fba879ae81	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc17edb67fb6fcda6be90eb485f2f68f617b6e51cc469db0757ca91f933c99bf01199f09519c503f4c830074cb4a7dc8f64d95044813df28801364f2f86df6252	1638366975000000	1638367873000000	1638367873000000	0	98000000	\\xa1413938dbb85af180050a3164a6664a171980c1bf8775778cca5b02f9ed078f	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\x4f0abb980d4559b25da2a9013004b5e2b2a3747e95f272fd9a3c5d6e61692c4a2dcdc310e690e62f1e49c8572475c2f1402eb94516244b888128511dcecf3600	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	\\xcbf64f03d2550000cbf64f03d2550000cbf64f03d2550000ebf64f03d255000011f74f03d2550000cbf64f03d255000011f74f03d25500000000000000000000
\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	2	\\xaadf168e1276328a987e5dbf06581844c0b6e5e508a4fd99289d8a9d2bcb071bd11a554c51e2db1cde926a8805fe8e81b1d961e62cbe0a753d5358005d199308	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc17edb67fb6fcda6be90eb485f2f68f617b6e51cc469db0757ca91f933c99bf01199f09519c503f4c830074cb4a7dc8f64d95044813df28801364f2f86df6252	1638971815000000	1638367911000000	1638367911000000	0	0	\\x09cd70968a5e3086cbb191a45afd0f0e96c578e671fb829723649fac30082571	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\x674671a0193eddea5bc2f651ff55e3778d092ca76a031ab5627679e5c5e49878be483c71ca8294a5b41b2023212fd36330d3c8898cb1d7251284a3cce6a97306	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	\\x6b245103d25500006b245103d25500006b245103d25500008b245103d2550000b1245103d25500006b245103d2550000b1245103d25500000000000000000000
\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	3	\\xaadf168e1276328a987e5dbf06581844c0b6e5e508a4fd99289d8a9d2bcb071bd11a554c51e2db1cde926a8805fe8e81b1d961e62cbe0a753d5358005d199308	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc17edb67fb6fcda6be90eb485f2f68f617b6e51cc469db0757ca91f933c99bf01199f09519c503f4c830074cb4a7dc8f64d95044813df28801364f2f86df6252	1638971815000000	1638367911000000	1638367911000000	0	0	\\x13d98aeecb195cef3fa231ac98ebc998abca490f09d0d0fe9ebc610ade1c3233	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\x86cc74e494459812974d86a13dccea2118a3f87d5a8a602bd5700503f4df724962b9e96942197bc2c6587bcf70667ef4b1f3dd792310ca102a75478fefe97f01	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	\\x6f245103d25500006f245103d25500006f245103d25500008f245103d2550000b5245103d25500006f245103d2550000b5245103d25500000000000000000000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_serial_id, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1382188551	2	1	0	1638366973000000	1638366975000000	1638367873000000	1638367873000000	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\x4fe9e894a158a6880831024afb7768cf7e2bf63a0dbe851684770ec4fceae82037ce1e83e9994c88fa00c032fea966233753431cbca0e372c0e869fba879ae81	\\xc3019d5a47e68b46bacae12d0a240097b204339a063ffac5e13f00ebe0ab52687ec04d338a1226d87169c061febafdf676fbdbe425911c75bfedb551474f5f05	\\x71cc75fe4952d09324d003da4118aa08	2	f	f	f	\N
2	1382188551	12	0	1000000	1638367011000000	1638971815000000	1638367911000000	1638367911000000	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\xaadf168e1276328a987e5dbf06581844c0b6e5e508a4fd99289d8a9d2bcb071bd11a554c51e2db1cde926a8805fe8e81b1d961e62cbe0a753d5358005d199308	\\x39c544e9ebd403b075dc5bca95b072cf35ccf8f10dca293449ddb1863ddeaab9236352216eb5d3402f4f898af062d7b163037faa9d082d2906209126c43cf809	\\x71cc75fe4952d09324d003da4118aa08	2	f	f	f	\N
3	1382188551	13	0	1000000	1638367011000000	1638971815000000	1638367911000000	1638367911000000	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	\\xaadf168e1276328a987e5dbf06581844c0b6e5e508a4fd99289d8a9d2bcb071bd11a554c51e2db1cde926a8805fe8e81b1d961e62cbe0a753d5358005d199308	\\x54cc11f856384da4bc295222895a1d454b2c7dd60f4cfa0e9120e5ed7e142dbe0fb489a9ac086996dd97f4473d7c9572c2603eb06a41f2920ea044629a111c0e	\\x71cc75fe4952d09324d003da4118aa08	2	f	f	f	\N
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
1	contenttypes	0001_initial	2021-12-01 14:55:41.279577+01
2	auth	0001_initial	2021-12-01 14:55:41.382701+01
3	app	0001_initial	2021-12-01 14:55:41.450952+01
4	app	0002_auto_20211103_1517	2021-12-01 14:55:41.453042+01
5	app	0003_auto_20211103_1518	2021-12-01 14:55:41.455097+01
6	app	0004_auto_20211103_1519	2021-12-01 14:55:41.457776+01
7	app	0005_auto_20211103_1519	2021-12-01 14:55:41.460569+01
8	app	0006_auto_20211103_1520	2021-12-01 14:55:41.462687+01
9	app	0007_auto_20211103_1520	2021-12-01 14:55:41.464554+01
10	contenttypes	0002_remove_content_type_name	2021-12-01 14:55:41.474418+01
11	auth	0002_alter_permission_name_max_length	2021-12-01 14:55:41.482812+01
12	auth	0003_alter_user_email_max_length	2021-12-01 14:55:41.489571+01
13	auth	0004_alter_user_username_opts	2021-12-01 14:55:41.495386+01
14	auth	0005_alter_user_last_login_null	2021-12-01 14:55:41.501046+01
15	auth	0006_require_contenttypes_0002	2021-12-01 14:55:41.503096+01
16	auth	0007_alter_validators_add_error_messages	2021-12-01 14:55:41.508524+01
17	auth	0008_alter_user_username_max_length	2021-12-01 14:55:41.518685+01
18	auth	0009_alter_user_last_name_max_length	2021-12-01 14:55:41.524606+01
19	auth	0010_alter_group_name_max_length	2021-12-01 14:55:41.531793+01
20	auth	0011_update_proxy_permissions	2021-12-01 14:55:41.538824+01
21	auth	0012_alter_user_first_name_max_length	2021-12-01 14:55:41.544625+01
22	sessions	0001_initial	2021-12-01 14:55:41.563641+01
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
1	\\xc09775c48b8cee11d08ba85669165ff54ccfe4c3232a2f1d206151b76296e945	\\x8dfbf026aec87e499c0eff6b8fd4e00fa02906d0d3495c824399d34385c34b61f264c483a224c68f210026d228cb0c9187252653eb6d2d973a32b753c408900d	1667396141000000	1674653741000000	1677072941000000
2	\\x21480f729e3e722a811a9261b0ee7ce65ad9837dabccd82fa944ef9bf61be83c	\\xfc791fc5a0e770feb0bfde4e5ea823becd33c097a2954e73554c163ff2d0dc8c651151ce7e6b001bf11b0d172514142e1a8d2dbdef1e735c1fa9b3a601be5c0c	1652881541000000	1660139141000000	1662558341000000
3	\\xb07d619aa2def3e5a311e5c2769821d3e35045361f6027f6075ac4bb608ad091	\\xe7119f45abe5088bb2ca954935096751626217a7b6b68c94b63db037129b38388c17ba5d17443bf66ef4925b42a044149f7b1d37ce1aacabaa75b736c1777609	1645624241000000	1652881841000000	1655301041000000
4	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	\\xa0d298ebc68805af02cb0f994d48b4c7cf88c9356a9ce46ccd55bee9053fc558462f46d171acb343b405e45d7429ab1a3fcfeef76f4269cfda2a88b656059a0e	1638366941000000	1645624541000000	1648043741000000
5	\\x74087dc33a9f3fdecd032a452e565aa8b7241bb6dd8c013298eafc2b3541fa6f	\\xff394faeafd8ccf73571c3d6de12b822c219d3423b6de29cdf2e5e8484d0e6165dfe6a1fad49c6c94f3b292d29e6bcbd05ad93093cb8eb69d5414110826c8805	1660138841000000	1667396441000000	1669815641000000
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
1	\\xe0186bf5b3febf38f761e298be270898c434e30dd87e29f58ac3d4078b56fd90	\N	92	\\x000000010000000027229e865b66cd52ddd3f59f13551670ff4f51b50f6f602d4c4f45f27d0a68be407f628a4da14e6b8bee309c0cb305445b2ca27f35cb1b45b43a8b56ade4209831fb2c21d6d40244f1de733590a7139f7e79f9f83aa18e99569aaf0b9749c8166ceeff024870d844ba9a77df49482c05664560503d6e2288198c41a3b0d83002
2	\\xa1413938dbb85af180050a3164a6664a171980c1bf8775778cca5b02f9ed078f	\N	134	\\x00000001000000002f5616d8bf60d805d528a76067eb31c8e927b6c7a7b13e1d50c312cf3ba41aa9a85e0f74d88c0e9786847adb9ecad65be64f3ae162472d37a1814338a8fd9e95167196d310683e05a9d1b73a38623b09e0686a2b358761f22712f0ece7520fef5f9d147c624c69dd29c13f73bec7a760804c0b2c4f63fb82a15f8417f80fd7a5
3	\\x728b8b6f25aba26ea7402af16fcc3ae6bf3180fd4e7115a714e52164d2c12558	\N	93	\\x00000001000000004d762e535c9bb8cdce66f8227fb5d91144bc00c49cc41a58ef1ae97c6b7d158fcaa25910fe5689c985c588652493c36f380716be0aeafe1483f5ca376764026fec0106bec061a145d8addbe9018e5c478038aa39d14c31917a91582cb209ff608315013fba52468cfd33ddb313b5f619f798bbfd26c6c05e965867f66d6f23c6
4	\\x20902e167b6e6d105471a1193e57e4e95e69472ec0c3109eb26b198d6be377eb	\N	364	\\x000000010000000095b82d67e39eda301d7cac22d109b63dbe2345dc09f7611722f9f7a6033968c58316eb76694a1d57a48c2ddb6624e4e55e194240233f668c12889d1f4d709862e9968d7324c3a4fb32028a07c925fce4871c26235a98cd0d89a908074ab7f493445a8020a2685f302c309a0f1f0431494e2a83a85c91e96dd1dfcc7526f809ad
5	\\xee2f5dea39c17cffb7872b274affccc002cf6283a67c392228e7f15b00f9fbcd	\N	364	\\x000000010000000027525bbdff513800e7b8a883b174ab8f9e3d1aa36da5c431b863aa6a11963286fc9f3b091375c88100c30e38215dc9b93a5523aa5727325e60403714f618b7f42f56e86583112debc26525dc0c7bae5f342b00a3715d4be33e7906f320e0d808be7cdf603e87020de930b81f85b62f02f7355843221389ed23f8217cc23a375b
6	\\x475a1b16b5edad2f9eb50a3b953ab83466f7bd60f4164b43d5de6f3096e84ff0	\N	364	\\x00000001000000007f72118902ac0946513fcad4ba35894006bd3043eb52e7f29717045276642dca23d5fdca2fba7ec613b5011a9ef4751650593f0602d844426f63a6b74dbb9c04a6daa11f883a84480e3f75031393ad953a65441513ae24de1e269f635f0d82bc3753211d828b5a4c4ad460202f7aa619df788be97a9200ace888ab67eeb93bbe
7	\\x69324983d0cd4727fb97daa6d7471b2f9fc8840d05219274a76bee146efb65cd	\N	364	\\x00000001000000007f9673351b68b149c79a945806186acdb90bc73fd166ecfddf97162246e3353a472a3486221146ed6c5e378bda7842961493b55916a1c59d78a7fb9f55fe6743ab4e906515b748846e77ee61b5fb9ebfa55bc7808bbb24f5e523936ce7efd23c5a1e5ba76ee0981b10e30501a5e961b414aa4cd4d6f8f203969163a724a496c8
8	\\x6dfafdc0ed2b116eee101cdd0c4372a9c567a24dfa626d3a9db0fe975117b514	\N	364	\\x0000000100000000b60e9b8b64572002792fa087e6bf432c4eb37497b0b9301ed4be7f6521988147b27a708188d7f7fe16b2dc1750839a2f5134480130b8025004a84e5c77a8103a2a09f8eb2b96245ce85936b9050068b4ede49f980348e3c81f6534f89e8684cdfc3aae8792e6fbfe45b9e8ea7746ed6cc74998ccbe6967c9f7d6daccf2793586
9	\\x755466d3375b26369bed54c4113d5106dd531609531bcb9e1e3eda13b3633653	\N	364	\\x00000001000000009a4ce4a19b35c81e181228d8fe32cd06a3b46d36833137aafce50d80944fd526555fbc0f90b45b81b9bc4c63ccca95a2d1e7b6397fccb1200674e7f8928f33de342a33837b7bdcef85d6420d63943070166423803c29cdd7f92b0d1f91322750b35f86081c236de8a5a97513f12d54755e596901911e77d630bca2f120c15f88
10	\\x82b08ecc189a01691e5500ad6ad870d287aae25234a1cf02a1e51b6c9770ba6f	\N	364	\\x00000001000000002e91a348c3efab2fc3c97755cc93aef4c6a9be5a717c3be0498c2c2d6e2f7f787699dd7f33990fc17a312551cde306adfd059fd3f9d2481a64bdf78b4a9627216c254c9b44134828efc29f263570656414a6fd09d10c1b869bc1db969519d4c9fccd228f1bbdc9716f5bde7e40def6d9d673d67dec4cd76246b590afa8d02104
11	\\xb521a0bdc5ff821d6309e71db85fade321871c708b49eded381d1eb225124d37	\N	364	\\x00000001000000009785a9ae858a3672cff7f9d4db8209f821731ee95a9a7a1a26f8cc733b15d0cbc60d6886150c9a81c2a0eb27ebab0e1b566c9640e0c1ea9e665ab42ddd95e0c3110b19a0870a5b3e265dbe827c6d895e60edf0871f65fc8deaec1ecbcd9ae8dbae13d3243b5cab6f2721a30c722afda3aa3662d2ceb5e1b7568720a565e44c15
12	\\x09cd70968a5e3086cbb191a45afd0f0e96c578e671fb829723649fac30082571	\N	264	\\x000000010000000084271e0f735f3460197868bdf964c54174a269a55975cc276b057f1f072b020aeb2a161f052e43ad366003ad8a59a683c279e37d6188bd3801dfafdb461fe9c594b4d0eecd9a126d2b8b79017442ca602a7129b9c8755f6052748eca65e4c6823adf2382c6620836a7a47874bc0b5b5acad3c997b1f067fee68cb84b3f9adfcc
13	\\x13d98aeecb195cef3fa231ac98ebc998abca490f09d0d0fe9ebc610ade1c3233	\N	264	\\x0000000100000000659d040133cbacee2f875fc579ceb6481a1a90dc05e77d414f27241381e7c08613261c79345c9eba19af74a0771a8d68d0d6822b2e3b1c0bba91f1795d3e324f81671bc07c23ddff2f64a17c54c323e93d482db7c5aa7c553c4e2da8914325c6ff2e45c68cab401c20791d5556e478c63bcc32508b13cf9ce9e6f15df486b6d0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xc17edb67fb6fcda6be90eb485f2f68f617b6e51cc469db0757ca91f933c99bf01199f09519c503f4c830074cb4a7dc8f64d95044813df28801364f2f86df6252	\\x71cc75fe4952d09324d003da4118aa08	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2021.335-02G3H7DHA6ECW	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383336373837333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383336373837333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2252355a4450535a56445a365444464d475844343559425638595242564453385752484d58503154515341385a4a4359394b465231333646474a4d435741305a4d53305230454b354d4d5a453859533653413132383246464a4830304b434b534647564650344d47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d30324733483744484136454357222c2274696d657374616d70223a7b22745f6d73223a313633383336363937333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383337303537333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239335052344d395752353457303436413444575235385632385432473934444a43574859304e4d42573253384e36573630415430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223533344750415252454a5636464353594d4e3038345256474a51334e52435a33474e5a5734504a45533044505848363333503547222c226e6f6e6365223a22484844595258584e564252534a56314d5852574853503937505433443138464732394745445a53544b57594b4a394b4a42575047227d	\\x4fe9e894a158a6880831024afb7768cf7e2bf63a0dbe851684770ec4fceae82037ce1e83e9994c88fa00c032fea966233753431cbca0e372c0e869fba879ae81	1638366973000000	1638370573000000	1638367873000000	t	f	taler://fulfillment-success/thank+you		\\x17dcb3df058180cd09068e1394edd744
2	1	2021.335-03P554SREPMMJ	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383336373931313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383336373931313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2252355a4450535a56445a365444464d475844343559425638595242564453385752484d58503154515341385a4a4359394b465231333646474a4d435741305a4d53305230454b354d4d5a453859533653413132383246464a4830304b434b534647564650344d47222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d303350353534535245504d4d4a222c2274696d657374616d70223a7b22745f6d73223a313633383336373031313030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383337303631313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2239335052344d395752353457303436413444575235385632385432473934444a43574859304e4d42573253384e36573630415430227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223533344750415252454a5636464353594d4e3038345256474a51334e52435a33474e5a5734504a45533044505848363333503547222c226e6f6e6365223a224e48483250394357475a563035574e31534658593846323432483333434e51504a5657594131414a384759374351435039385830227d	\\xaadf168e1276328a987e5dbf06581844c0b6e5e508a4fd99289d8a9d2bcb071bd11a554c51e2db1cde926a8805fe8e81b1d961e62cbe0a753d5358005d199308	1638367011000000	1638370611000000	1638367911000000	t	f	taler://fulfillment-success/thank+you		\\x517f5c871f3bc9b50635679d3c850bf3
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
1	1	1638366975000000	\\xa1413938dbb85af180050a3164a6664a171980c1bf8775778cca5b02f9ed078f	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x4f0abb980d4559b25da2a9013004b5e2b2a3747e95f272fd9a3c5d6e61692c4a2dcdc310e690e62f1e49c8572475c2f1402eb94516244b888128511dcecf3600	1
2	2	1638971815000000	\\x09cd70968a5e3086cbb191a45afd0f0e96c578e671fb829723649fac30082571	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x674671a0193eddea5bc2f651ff55e3778d092ca76a031ab5627679e5c5e49878be483c71ca8294a5b41b2023212fd36330d3c8898cb1d7251284a3cce6a97306	1
3	2	1638971815000000	\\x13d98aeecb195cef3fa231ac98ebc998abca490f09d0d0fe9ebc610ade1c3233	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x86cc74e494459812974d86a13dccea2118a3f87d5a8a602bd5700503f4df724962b9e96942197bc2c6587bcf70667ef4b1f3dd792310ca102a75478fefe97f01	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\xc09775c48b8cee11d08ba85669165ff54ccfe4c3232a2f1d206151b76296e945	1667396141000000	1674653741000000	1677072941000000	\\x8dfbf026aec87e499c0eff6b8fd4e00fa02906d0d3495c824399d34385c34b61f264c483a224c68f210026d228cb0c9187252653eb6d2d973a32b753c408900d
2	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\x21480f729e3e722a811a9261b0ee7ce65ad9837dabccd82fa944ef9bf61be83c	1652881541000000	1660139141000000	1662558341000000	\\xfc791fc5a0e770feb0bfde4e5ea823becd33c097a2954e73554c163ff2d0dc8c651151ce7e6b001bf11b0d172514142e1a8d2dbdef1e735c1fa9b3a601be5c0c
3	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\xb07d619aa2def3e5a311e5c2769821d3e35045361f6027f6075ac4bb608ad091	1645624241000000	1652881841000000	1655301041000000	\\xe7119f45abe5088bb2ca954935096751626217a7b6b68c94b63db037129b38388c17ba5d17443bf66ef4925b42a044149f7b1d37ce1aacabaa75b736c1777609
4	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\x7381fdf0de425ba7c87466c78b506c9f453784258154f22784ba2f4159d1d267	1638366941000000	1645624541000000	1648043741000000	\\xa0d298ebc68805af02cb0f994d48b4c7cf88c9356a9ce46ccd55bee9053fc558462f46d171acb343b405e45d7429ab1a3fcfeef76f4269cfda2a88b656059a0e
5	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\x74087dc33a9f3fdecd032a452e565aa8b7241bb6dd8c013298eafc2b3541fa6f	1660138841000000	1667396441000000	1669815641000000	\\xff394faeafd8ccf73571c3d6de12b822c219d3423b6de29cdf2e5e8484d0e6165dfe6a1fad49c6c94f3b292d29e6bcbd05ad93093cb8eb69d5414110826c8805
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x48ed82513cc149c010ca237982a36246850491b26723e0568be0b28a9b8602b4	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x403ddcb1ac9ae4bca73e915a1c1ef3d901b0c2a0aa4dcdfdad12276f18cc5d438c4e64057b4e11c76f8d05a3b5d6dc56fed992e05f0d76c06e892680b9458408
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
1	\\x28c90b2b1874b667b33ea54082637095c75c33e3857fc25a4ec81b6ec4c31d8b	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000
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
\\xe761e368e6cdd79523b5f53b2cad49a3938caebcf7d3c1ac336341dd751a74b6	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1638366975000000	f	\N	\N	2	1	http://localhost:8081/
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
1	1	\\x0be3f090d5d6ccf514532472983ef2636617c542809579bbc9df20e9f108b1ae00b37488e54fea5eaf2621c13a7827ab00ae795a73ca8b0aa430e5955b74df05	\\x807b9cff040f410ed34ecc188f990b1d47eff7fcbd14b1d17bc2c209587e83db	2	0	1638366969000000	2
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", rrc_serial) FROM stdin;
1	4	\\x45c50dd48da5b296a0e4b93ffd3c5a3857d8dd7bd99d82a4cea444ab5e6ca19c2b278d2021ff2522ac92cc31b245a8fe619d07c5aeed4684991d70dd05705704	\\x3d546f3cc5e433f3990f118640a4f30b1ce4a09639e21cb0f8fe9bf7ca885093	0	10000000	1638971800000000	4
2	5	\\x486b4a0ee92e0644266cd93fc98bc72a0e6d8bbbdc3ec9ed4fbeb560d40d0fd5bd99f2de0cbe67b2a5c374b7f552eb7131d49fae2de07a34b6e198025f5dce0f	\\x7273b371015234b67d1ca12af01736a0fad2e4d888736eda83c2ebf6de6c8d83	0	10000000	1638971800000000	3
3	6	\\xc7c4f026fa362f1a38f980b9e83e3df73562050bc14174fef9b0294d255f722687030a32ec10ecf92910d2c753014b972d4f5e49a60821451349d55599d35802	\\xb91ac2ee8bb986207af7f94d3e90c41d2d046ee1e31d3c4fa91be408a01f3839	0	10000000	1638971800000000	7
4	7	\\x29467ee969ee8f8a59848d9d474e51e4e867b1b44bb5133bd5f602b2e726a1e521afea26c30056d9ab0897b9f40346dd12019a7dfe172d7417f9399922de8c0a	\\x73193a9fbc71eb1995445f0ccdbbf650c9d81cda4bfef6724ecc371a1d10a2cc	0	10000000	1638971800000000	8
5	8	\\x750b2484c67d8a4740ba48ea4d636894d4e06ea6beea18ad87ce82c09fad21f5b00814cf871edc3f48dbb346164bd192b9bb7a57beced52e0b96e52084de4701	\\xe11653dec0c2540236840ab680a0560bcd9220ac22a0d3207ea64f9107e1b4a4	0	10000000	1638971800000000	5
6	9	\\x5ddc2111398eac860edd72374bf3877d843861f1d76c56f647860bc3f7f3b6a6f43ff2c77b96c0e9c35c07d4c219648b9dee42106354055296a46775466ad60c	\\x9785a7a7c20bb6afe7827a4983c6d0e7a5255faab81513323c38ecf04a808b73	0	10000000	1638971800000000	9
7	10	\\xd3cb8364b2194ea92c766db0e6a1a233910ca3f045abd9d34f778b7eac4a624846745ff2d2576b80d4ff5a620ecf3e20c36f2b867878fc56234d71ca374c3e04	\\x37812d2a76662c592341f29469ef84e16080f3bab1254aaf18008cf90312dd84	0	10000000	1638971800000000	6
8	11	\\x1dc368e868ee72db51579dd745226ac1d7668537a3b6aa27ef533e3c9eb61ecc3f387381de9bf19aa4663bb68179fe2a68248c1b07c2d3954f20a8cd0330a40d	\\x50d0adc0817193083ae0654a2f4f13a4bc58e8f51c3eb7df7623c04211012332	0	10000000	1638971800000000	2
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_known_coin_id, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x1a0b0eb52968acb6bdfc2599f4f8d54147fd90e4efde730bfc26abfc295abaad3a46439beb62df108498960faa9edbc7300c7daae1a83ea8fbebe44a9eab885a	3	\\xdd3e5f19563d35f68eec4dbe4be41b3edcc4799e7f4708ba1081afa15f566a4e8e392774acd54fa7a04d0ab65737e541c6021fcf9f02f4d92c7df4d34a93ca05	5	0	1
2	\\xfe095f2b3cd7cbbed98a95d7426c45604cbd4d0773ec908fc540c3901d6e64f5df889be6bd7937a3a26dbdd6c7d708756cf7a95c81c0d8811803d9c612e39e1e	3	\\x1097dd8cfcbbd0120c9b8779e758a54a7989ac62285e77e7d9498bd4283abf93555ef3528ae399f1dd42ac3732aa75b5c0ac8d7bb9bbb2153465efa3eeb4eb00	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig) FROM stdin;
1	1	0	\\x1fc0177b5a1801015180ef7b61a85f9f598a524f024c0153a15a7baef69eaf22cab2432d36b0394dbefaab11f3887a0876ba939644b87cf800c9bcc2db185d06	62	\\x18e5bbefe6693c424e0d4348005d772ff83d1c03fc345e239dbd5e10a57213030a97e2d13ac9b07d786311530ba8dea82baeb5f427c3f093a6792d92f58f9863995621b6eef754f3c281578dec66d93221ecb43a55b54a6c3e98aee7fdcf797fbf7a88ad6998b771020c0f19d3f737ed645beb528f6ff1c4f31781c6209e64bc	\\xaca7555d3ba80dea0fbf31883bdd249f2b17223734357e7c4f66035c037e9af58bb6cf91420586ba89f17a5d2516d883636b9449860c1a8cc8ff23ec9211ceeb	\\x00000001000000016d5f09da77249e882cafc90089f9f50251d4af54b7f4bc345f1eaf0723027663ffce1b9b1e7cfb6eb094c87dbd9edfb81f6929cd570c1ba5cf1a4ccbe30441ab6dd3c7841ba9b4662023fb4d148e82a31370ba09a1440c41eabf941ca082f7fe37e7daf431cd937dee301dccbf9d82967671ba7463cfceca4d793b411d92c116
2	1	1	\\x071493f53d1a2d3c3e2dbabd3e596878c0b232bbc54fdc6609154c043da10d8c09a9b660d84a05c529be9c33d14f0f15e30e9e65d643ae307914256f26a1660d	364	\\x615152e42b77c4a2c2ccc8e588cde22a0fc96a7add99bcfcc7d7a9ae4431294512cc6665973002a1c8cb3090323402c93b009f204cb8ce838d415d8c18c716c9e400fa9505b38dfb32434643b23fb5dcb125f0288b632413aeb01b3fd7ef670a559de96d1259bd218c5160f19494063925bb1149645c2c87c3f3ba45ecf5facc	\\x63c1827f442c35e1add6272308dfc148c748fd68e973e95c264a27d1f24f62ecf3c350d35a63836c029c71e338a60cc525894d439d5daecaebad242ff515eed3	\\x0000000100000001655c7d3a686266b0f873b307fbab5bdb7f30abd07393fe8b68534d1e6673ba9d65f5397d5750ba033ccc659376e7615450b2355d38961143d83c66d49100268a85a2d1a040d0ee8a41fc442883cfa954f1b67f57c92be243c97aae5bd963f905c8c2e82e1dfebf17c4110fc6fddd004eda8fa09a98bdf6094f28ab5ef063b7d4
3	1	2	\\x132d13315e707f02a9915f4da95176b4663c079f18bffa476a61e1c8bd5cbd0fa9240a5ace43ea7d008e389e16b58216acfc0a91a0a306f54f41d641d72f8e09	364	\\x0399a3f3b9f9317bea40d65f0f821556777cf84cb81b2d1c4ba4b314d771f33ecf7b39efc8abf765f4ff23a28d6fce367263c1f442fb000c9ccfde9b92ba427e6b8375495d92c539c0c61c42831471853dda4030d123d7b16c0fcf9733e7b92411f7d92819a6cd5cb5c4e9b3cfd535308bc41c236535bd6642b3e3c527a32f53	\\xfa1bb030624f246c6bdd844e0cacbe412c1264f56b43ea902c0de8fef78e241bb8851b9982592cd79e95fe03147c45a6137aa6cb6212ed77c3c34dfe9fec2d5b	\\x00000001000000016f5dcfe9242c6d81b04a637c4f683b14013b111a69113114873c6dffc5cea2523336e3818c7ce3d0dca1d9880397bb47ffefbf1d0fa0a28726908229394ea3403f3c0e510f8b8d218d087b02bb0357b6992549432276e925517d229d8438e67230f63b309b1cd8e0bdc33ab05a7030e363f6d8d9f0411482433760fda163f9fa
4	1	3	\\xb546608b00cca93a14613f1ba9433f4971606bf8739cc14aaca0156509af3ef5de5806f8d9a6a170f4043dc99712171a0388ac079c74bd7552a6a44b523ed302	364	\\x891717d560782516b0e53039dcce902061c14217e0b0d1bb1c674aead518e8a8a27db3f6409fba7369131a918e6d7c9a2816e510c121456ff57fb328414d3d4ed656ed42afb6ca1225a7d3f4943aef4971da913f755b6b49deb4bea8599d371a4fba7daaec1f805bf713463e948653d8234988ac63de9a05a2caa198ed10a98c	\\x04d64041888c2605d83d2bdfe5b27f9ab626e70feea4174167bead984e75299050cdf948e6243bb83c26c70b556f205bbfeccc2e4ca001c5f00025a4c208654e	\\x0000000100000001b557915fa19a0de7e6fea0a1390e7f8fd8ae0cbc65c958b51ade7e992e26aa5f2693ee8a4bdb4d8b1486149796f7f6e07fc8314ac580c3a116536df04647dbdf51b97c6c191a6ed617ca6326b46f94a1a59906b948fbafd3faa3ad26a9af63c5b1aed88af5d244c54c98e5881fdb941f3a23fad582c7c1654976bf38cd452151
5	1	4	\\x1fe2ee3f053bfbeda25b7acc61a5367a84db2c8c0e0686ee6f7637949f5271ec91fca762d19d04aa75e52ed7d8955d900bf685eb726b4f953707e1867dcfe00e	364	\\xb420691ab9e489317197bfa8ca759c65ba1104250a74d7f1da0da1c97975227645f943d146b5f93031e919c10101ffc6626298ba92654e750647fe41a57bf2f60bcbe64a6ee63f234d27672023ee75904f94501aa88fddab28fba8ea78fbf7ff5a6c4294903af54fc1a3f95d8af07d624cc6915f9ecc9ebac6e17a910cd79049	\\x27eecf0dc3854aa5cfe681277df01da9ba4de2c2136b2a0d0a842474f62699a99aa34aae957dfafa3a896a6ff98b9db0f3ff5cdfb603144d727aec9edc5723d1	\\x000000010000000136efa206c6c0a3c6f084b336a1244bdbc1a5c3628e4a528d704a4358e0a4519e17a7c563210600608deb860ce07af623a870ddcc39e168e6838049d7f4b7339dc5e8981213cfd4ea9ff33ca0616dad1dc4f580f302d89d0a7287a988924b58e814fbf091be8ee792470f49e94ea6271f776bb1f90bbba91e2f27343d3d78658a
6	1	5	\\xbf7415486b544e8a0b41a2c6fd766c0eb5196406b0aa5a1c8e6461474e4885b1a0b44448040593c00ea52a7366b2cd0d96d1e6bb52a6b32fd9f7f112f5169b08	364	\\x40ca2342d40fb89b2e60154cae37e7f1fed21ab0271c78e7ed14d662ff8b42e94b5335830252f8fd8d44f2fdad1a5a9a9b53c38a9312ef06aed8ca28a5f3af145b3847f6dcf18c4a1ac151e2bde09f929dd868aee155ef59fecf8076de0675fe3427c60346f93f3b7ed11bb1b6ad59d803d68bff368d59640336d1e7a61d3b96	\\x6ba172edc2704115ec3e4c42f0159c931acf8f6f2867329b70462c0d33689983517918b8107d2961d54a10b3534f429ae7990a2ba010d12ad472e02477e24a7e	\\x0000000100000001430d44473da6bfd141ecc9ecce15105e5f4b53a8730a7e2476a735c28e3395d3395e589fa26829529eb5aae9f001bbdfaa1eb7c6f5b652f923fb3916e4a4726f86d86007816de120a867bf8969ee5701ebae35feb940a5c1bb9106b27ed9ba46b45e1c7c2b2343f515ff31a5312b93ea36ab2a9cb9367cbcc95ae8b3be38b390
7	1	6	\\x0ab4db1961bda6a58067d2cfecc0b874369a62265e22e0008142ef16a95c90393c05b479f1694586e08e11bb888026493e70bfba1881e3d311e48775e9585d0b	364	\\x0cb44948e661f8db43dc1d285a6c7d98d62336fcde072250b44af359bd65e9bc2c3ed48448d46f9de94782057a9cbf0b9011cf8d03f0427a5ed25e9d6b25bc1711b2ade64dcbe1e2f376e1b05e5e22b386ec0d5a841ce646599a408c0120944b48cd436dfc773bb31c8434b57b1b869243d25ca9673f798e6dcc42711eecd9cc	\\x83985d6a978715a8e7ce6977cc72f6e2c6e902643a131df12e42d432aed77be5c1072688d5a9720e8eb55c8e92f3ac7780519044b38e55aa158a5e6a98742bd5	\\x000000010000000197f2371b77cd6445fe366e58a87c0ea8d1bf64a6d3a2483f0a14ffa834dc2cbab4fa86876d4010e91ad1cd36b2806d6acd636e7c895b93d1604eacbda7301c08fd265adc2e1225ca4ccc119b0819c2e8a80a4027744b2e7a3a9baeb0b8ba578fcff96edc8348bec61a386a0ef91173138952f1d9d105b34ce8935f51e2951966
8	1	7	\\x7fed579fa6e88eb03cdb6be9f7a84402f7c10fd55d0be068269b7b3d485eba4741fd14a55a974fe5eaef4c0f6a08b8cf940c85519b87f1c518e59bbb70028501	364	\\x6ce047ad4e0ccf0a7715472593983983064ab8e9b0b8cf966cd5a973f6f549b79805b60be570ef052e8b4588dbc37685f2ac02a40a586eef0082be43e23cce7f571a9a901032faa519884811442f8295164fa2109bfae76a93b69cfb26a3ff9852f07656b212ee53147414467ab1310b38a3a1456b82f695bcce4bb6d715af05	\\xb64f38a3928e5b7a0673505dc80875e07b68aab6db39d3b343a675968363337df5fbaf31fef7bed55cd59c2e26629b8ed5a117600801f3f09c315bb73094355b	\\x0000000100000001aa3cbd8d54034d2cad49f5c309883e909223fa6877da2309e5f6f37e4a0ff25fcf381cfc4c869b9a2d07913c45abd66285560643f657297d1b3636d6da50c11e008787a70c2bc3215c4275b332379e33e581290a554b0b58ee0930a1fe4e6b097007723530d74365b579760e2ec49c035d233b37ca8f63c828a8aab1d7676d64
9	1	8	\\xa3795c125b8b0e04f34c88afa0e7bce7daacb4ed67010602cb814dabb90b2e6b765e3795c5f429e665ec23aec9cf214f77e5043e7ba76bdfd78615c29cde1107	364	\\xa4aaa73e2850a54d33dfa9568cbbbfcf481aa22e2c6167865564bfb4e00d110819c77e59b59d1ab882e5c7a89ad7347dee6eb6e157c85c6f7fe183d4488dc66779291c9987c042f3cf609e7d2606b7862513cfc80da9d874b56b0d7c45bb4728078cfb336e7e613af613829418589a746035f2d98689ee72d3b4181f364ff3ed	\\x982df3d5d7b794ee880dd30fef58dec13ec6a12a07a6dfb2f6ff5e8b3296ffad0b93abbba1d2cea56c13589d8d9259712acbb7e797f6081ff5132abf3aecd47b	\\x0000000100000001543181e26ac8e091444d8bc02969d3fccc8d81579fbe70a63106b755d9887bc9b91ae9a5b923d202f29e425dd22a528608b2d2f9309b425400518d1ccdb31368921397785abc7a3ac6706f267799bdf6e58b7f3db9dc4d94e467dfa36b9ee6fc8f0a9668bd71075a11d9e0609ac9a429d5e4ff2868d192d686cea32fcd127172
10	1	9	\\xef27efb296cccdb2ffbc32c2f1bb645e5e4bf0c55ab76ccf7d8019f5ac844b4004e005fe87ae2b8eef2319fa31825fd6cb2fe74e0cdc9ced6ef31cc06558d007	264	\\xa035bc86a0dca9e3471d80eef35a84131b5e6ed4924ccab23d0b0852832778e44fa9bb8b3e096c9b963da5d7939a21eefb63dee37e5319c1c06f9c929db05885ef3f9e897e08fd96e59f889e59d39031d2175f1cf9db8c364024e264921520adc6245adbca9e2b345805833866db2bdd1d2040bbed1f30c40aa1f55ff7a9cfb4	\\xd0035f8b2805eda1b054ea96b75d29af29ff501f4f0d204845b33ead5d075102997622043014cd8b3c912f1c90ba9e61149853573b50e7a5f2f6338fe73abd6c	\\x000000010000000158e47f7033fd6ac4e8f96751ad96692032ead60d10f3798867a1d4f0bf773f8e9b75df7daaa5057709724448ff789e18bd8b453f824c3f06c7653f5500636554363204e2a329db6539075bcbe659cf2d5bd7772d52d2297a0f44b1de1e8399e45657daa6f7e0886e77a5e588aac2c513acb3ec99ef8a08629548da21600216bf
11	1	10	\\x718831fcefdc74725643fdac28124fcdfaf0450173461861df94324d9c94466fd7b927edc72c3f847630179d374306b03183057ce431436779dba2c3d660f905	264	\\xb44e0e2d18fae27afb3abee4b4e4999f52bc371b15eebea2abc4c79f8c2109610a285c6ecc1a7b5f7032e53f87f7acf2350228eb18a29529fd4e9a061a0072447391a9a52360c791b017c19b05e4352532ca16e2a9857ea3fccbddacc57b4329609b4fc30a9d17a00261a17409d694076912e90e23badcf523c8be48226ff2d9	\\x55d3be3aa0de5da8d02e7059790b7976bb8e90b9cf361dc52a2209f7f0f941b18898adc2e39317419a1e7cb7673b381057a3e3b396d80b4ecbb237d69ee7a3f2	\\x00000001000000016b5fe6d30ca464590b836c5e4db15e12a0a94b5ecca12b655924e7a3c4e5c87ce4a373759434d2ff573d11562e2db33faacf670415d56d5e28ed68111c9724c4aee92168fa3ada31220984fd66ec5d4e2173f1714c71244d3eb4d105c2854bdaeed0b4041c6d64b6912b497a25823f2c7018f5f8c574f855b16521906ffa6922
12	1	11	\\x2fb70b8ebab9e9fb1a407ec4f3e6fe1f8c6bd79c06e35810d4aad9d4c8e5f0c142d075e5135ed9acd2cb2af4028b5450396588d2cb452ce70635727ea10dbd0e	264	\\x7a6360fc08989948117884db598296109733b5fc4fc7462070fad7b69cc4a65f3d46fe51a3f176ad57d7dbc08c7e1422e30cffa381072a255dacbcb9c96cf071dfba983966c86b11756c405272eb08685136c8c493ffcef3c6c5fb855ca112438ef3841ca3f085198e2d80a0410336bea41084c93b436848e06cf8a70d6c1537	\\xe328a690f40b25d4fa3d00d0cb1ced96334f03e71f17ce3176f93b3e29a2d05dde576a12b2fb4b95c0481101920f80626f00c36b6569337a2332f3cf4fa68f3f	\\x0000000100000001aba928c1e9621e6613f9f3ae95e75400319952d5abd0a5551e3ee4697c43e9bba5a8df8552e4075702527fe143b30bdd231c39bc2abf2aca8843e630dfe7fcf19ee7d85ceaf0a6446c43fcd9b0d4da7e97ae2a7ff6354d68ba9616a2fc1e0e7afd7535657f60b848e402ecbb01e282fd8940588f035a59b27f6cbc1d2960f008
13	2	0	\\xd2efc0cea68967aa53d4d2405b054a9ede7ef545af3607e466ea42fa92d3f63f2b51326f6aaa56042ad247cf9651e4ca464d3fbe05f98f019c6475bd3aec7c04	264	\\x82f15b4d16df2e7c8cb21bd98863605f165984a6fb2e96d70bc44aa713c9362b2ddccc6326c7f01f3644db65f0dbf40a6aefdcaca3276c07b129920738e1db60194f713917777701d0de6b49fe4c778978f10544b4a0edeb9f6db4df6f9b13edc967be563de9130901861a90b1df2c816e8bce7773ff76698e087ed13a599892	\\xa9933d4589af8379feb525e44188ee6e43f0312ee9ce6925130fb1ad7c7162521ffe29390c409bc81a331bc1b73ae46c4b04978a7e0b42d15bc3539f27455273	\\x0000000100000001a4f10bae695ea2b01b6cfdb45edf3de8ac999e2afb3d781181cfba47a3c091781f324b8c55b4a740f7d821636adc91d93f8c7d112b255a21d1df64b216bfa5b843d575215dd235fe2a4350b70e42d913fa2fee63ef8057fbb80591b5e868d8806d74f5909d8e8a7766f3e86afbb54c4d29ff0aa92b4632b25ae37c9168f2b10f
14	2	1	\\x017871874bb19b7b407974c69aaf4b9b496edeee1d71faaee4349e52443148560c4939281c9bd641989abce8f3b4c54e91bd42c705cef623d018e3e9a9b78501	264	\\x0d3ddeee9902788081310aff2de9b478fea9251af358bf44cf443108989e0d487aaddcc5f09753c7e4cda8b5c57bd2bb1103bf5f752f154a680a9f5b1b41b69c75ba8a67793b0b8bc224f6f785c7f08af78152105034248189b36733f126ee6f95968062e187eaf0e6721eb1375cfd5903ad7353dea51193337a6d1bc04e7278	\\x476b98317908f6e5024059650e26f509ff259a90055729a273db84218dafb00e57011994c8a0ece12b5aac23f75805c20b8ec560d9da619b922f231f676c9812	\\x0000000100000001be8537069635761baa92774feafcacc86169297a178786970dff27da66da3a7261393160fd316a3214da9fa4b91b5a30cbacbc9c6bfaa3e4bef423509a7c45362ac8c1b372b76293c1842bf3bba2b55fa91a7e2cbad94e40e8b899d32561831a28f10bc8d933a01fdb671e02fc4d5d2f911d09cad923475825a2ad3eb2d44f60
15	2	2	\\xdd71a7e71fc17409ea527ea02cd0120801186d4d8b435c740b526b1e2f5fe14eba8b93726305a444941b3002d971c43d6730b8698234b57f0e9758dde4e1af00	264	\\x4186ea2ef92c29aa84e45be2f7e6c739f9e54881f3e686b24b1110fac6cf26f32d1c4d6f1772ff4f245e3084445e0f5f2939547d151b827b61c18f79b5fed1c176efd7d970b3908a1b6177ab44a06ec6dd07aa20008f1bfb8a010c175e8e8128d46ad9b7e27a81da3919d8ada5fc5fd0f342680dbfa0bc0aad96b052f6e392ac	\\xe525c5ffe6c8ddbff7ad00f11b2435a21dc7dad9f27f0430897c1a46a808f9a2d9a4f927337370b6623c1595a694a5e21aec46a75cf0ad7a0e969667d3c8bc0d	\\x0000000100000001021551474850876d72e2f8c924a64e9f13db798b90353d81a3a210eb02132fff40c2ccb3eb24d38c21c5dd06f5a8829f595d4b7e35bb484b899c439b69cabc63138c8c28c457661c6a355c1cecd5460678eb4110f7f83ebcc4a91f5cf61df1765b63fd59328ae345ca9010316e2efd6bedf35a4e7f3b06b0c3e5b9aebef3b55a
16	2	3	\\xa0a11daac4ddf3823249fb5cdf80068a8990f626c965c8741172c3e4af959900569a643f0b429ea8c93b30181374be20d63ee974a08b596188f8cc14857a4705	264	\\x3b8e2e8300fda57fb7bbd99a4856553e22fa140e60197c3de2917b0e51ceed4485c7a2abbc060b7bc80c9faa6ade54782a826ec48f87fbd025ccc42de24ed878aa5f3d80f190e7483a649a8b29abc03c5fe3dd9787f9aa38e50a89a46b12dad2c5d2901537d6933c9510c61b3a21a7615beb79d5eba713fe63f29e3011bcf4ad	\\x2d0ad0da6e0a37c8c28ae41fda8f442f01b8a0505c2c476a1334549a682e3ad794c8a40c6c45dd4eee09580949c7630f87b1d6cb2c193f1930d7ae229ac29b82	\\x0000000100000001a4c42269c402c8c346b4fe05ea97a6df23d6aa577a56887e5f2430874ee4ce0d7398f282d92db2741506d0fc02c1cc73eccbe32c41fd965f8443efec6f63a6e1dae20b437d4a28d49bd720aa2d61104e5da2e96102a63e042d9b6cf5642d5486787d948f64a6282c8fcff725bb511dcbab0e00d2cf3e0c5f953a63a5d45cc8a2
17	2	4	\\xe79fd588e29aa3b6d66a04e2088fa4ffcda1e18290ef09d83d90baf39d8a125aee6214104ca1149e5058c0b09f58a884dd92ca9309fd47608c91ba6df8602802	264	\\x98c2dba37c613c40ed854d4762bf8b165a18224a63cf74442cf2a4d061c66489cd3b51558c076605bdb1992a1fcb02af10964c5a3b3c0ed4a9c9638f0fcaca73a8dcdfe31e4423e79aea9a384436f50faae72fc3185a2d8fbeb37f12d6f521d75bc622431280c1a126056afdd86daf56836b57f38190d94a699cc7a1f026af4e	\\x7dd460452d34a201956d44903d036898209a3d56a6a367c2a3a0690e73e416612451a716dce325e46b7895208ae27f4461d34926feaa22a17825f39576463b68	\\x000000010000000109e77072ed160610ad4f538a4778fabff8893cff88a8cf572342ce63d7a0513863e12d3c4484b744e3a4d2bc48b891f20645ef43ac404323315ec6ed7acdd09e25b5d1d4142641d56bbad51dc73aab1a165471186e8a292a7695dbf6af0aad62480c00934b6121fb7eb3530a46fd2bae91a327824fe18ab3e951e4ea5d2b0dfa
18	2	5	\\x4aecd4642089723fdd008ee9df9d9daeb8668c61f3233178eb0390bcdf061cd6d02139062de4f10cc2b4d10f3520ffde29886f9d6532f842a362558e8583ff05	264	\\x8aca85daec10d3629bef831f0532ad27eea45ae43384f21d2458e6d46c1992596fe10a4520b251edefbe511a53c7768fb07ada48bd1fdf6f82faa276a4ca52908199133fe5b1e0acb0a64a944e22d3e75bcece70144a7dca86df8cf315a51b72d2763a1f1a562bcddffad9367593b5150dd2042695169fb3412a0e53d6e21184	\\x70cf619ae3d0f6c3b3f8a3d1ce5821d5bd098e655856075703a050a0cca5555b3b76b1dfe54035f9beeeeea6b01864dd31c30236eeb45997f5b02736405f944d	\\x0000000100000001297abd9f95bbb48a94798eb3ce99f2ac863a678d99a038c2edd6cc066a45d24801469c021ca9ca8664c5a365fd5802efd16d2af8978e372ca4573f1248a0511c7f9ab86081e9c4978d495eb9b0295ae08e5a40799acd6038acfb349636a01adda50397ef0d96c0d431b03dbf4b7980240d999b73ca082c34557090aa36f2f369
19	2	6	\\x163b3c0eddab72c33a7caeb653749c650e904b0e4611ae3acfe48f47f7e14b60778481c4e7928951c1fa74606306a7b1f71f19a4944578adab9786a4ab1be304	264	\\x6fd3e829f4c5c174497b6fb61396dd91e72bf52661d407d8ad14eb15efdccca38a9051a3eeab4e7a6045089ea9aea6905fb89400dc31efa4b55c67e409be7ec665736bda0cc66bf21955817f40681be5175ec99b8a679c56ec1c50eb7390f3a40d46b589f646a1fd5fd703df61c70f89d0c37798c6fcbeb56fbbc41b09fe40a6	\\xb74b6351d199bd83472724bea7cc23762416a0e96fa7cbee8579015d0d958927cbcd1b92acf632dc2e366cc19b06265fb432198f0b5d91038432c94263d452b4	\\x0000000100000001675c508497f62a26b95d4cf4600c2a078330234adb4b9fb168fe9667d5658a202b3240ef87bd040469e895fa760a57e3689ba74d86219e10ef07b02e825f237ae34b1918c5e6386681d58a8aeebef74a28d7c17639847e1a4b7dc340c2183dba09896266aeab9a67f531c70c5ac6e9de298bc66098645593622bf3e79066fc02
20	2	7	\\xc103d225cedce9a665234503d9cf69cd2c482b8d93c46f1f7785584848070e1f65508341be2cb12ffe857703ac380a7e40b2391af7b9fb7e018f680624f88903	264	\\x924f5fbbaa96298f375a2b36565f361d09f932c0ea124dfc17e6733ddc8d89eecac1b7b2b769ea47a7f6ec4b8c79dc56481371ff827f6951e90747da22bea45313808bf123d395438fb87b2096cc48a23c5e8ae5ea394be4ee39fbcd4ff6135ac64a7c87ff412ed8f7b586512443a1917b06ae639487884ee09bdeeecab69613	\\x05664b1c4c85563fe9cc62540c51229e256993746b117534ade242601b2653e78cc0fb9a3d36e49191a227d0686895c86108506b0d75cfecd67363362b1b2ae9	\\x0000000100000001ae5f55eb36405ea38c380db40be43b3706331211fa05779a9e774e8cdb923e522a4c5f33174a34566d06bdbbea10c93e3ef18c79ca815ff6b03ef36bc42aa247dd77880cb8d19d6b02db87c0a5dc2b26e0cd29ba1267038747f2346d5c2dec8ab56fc3a27fcefb560bd082d3e85b1a5afc32d16b9d9b4c85c3a9dc943910511a
21	2	8	\\x2ec87f6019de0a198f6bdc8265729887c360f5d675ca0055e2c0fe13a6a334d103a8c341cd0923aa8ec40fa3215d54bf9adc426e855b5cda81f5f2ffb5d67603	264	\\x21ee9fbf5fe880141fc29ce330fbf5b3038a564844c7cf9ec455973d808aa9144971dd5e6ddd6378c8c745e429bd6fd9fe07b88dce91984141e46778bbb3ae6c3db6c259ababc2bed1a4e7a9955112c6368c545a31fd8809bed08e20192fb4efa768fc53d16b2574042d0b55c11c0480b8028ecf5112cef123a97c9d421f644f	\\xa8e5eca24acc1e9bbe565b700d8580f34ca078a7587c9b4b998901108c7b354195b3288ce3650e9035a4ac56a8d4d5a71f179e526b9063a740717b287e3ab83e	\\x00000001000000012e642cc9151d8fc344aa2be05b80dbd900ff389cc1c82fac4f345378b96e18dec73addfa54e902c3f65d10bfe7a1cb1b406c6be60c250124a3eead59fd58ec34bc561c18f2f1d7ffa9d91d6a892c7825c35e14a47db6471fb5f21d9680b23bcf49f5d9a48f8c0ba9224db3939435ffa2c58d802a2d4297a1c0ae0f7900be52ce
22	2	9	\\x0b5a73ba8d2819fe1ca81a6652f7d1bc70fc37f9c2038ac6c33b0c2b597002e4e842e955d17511cda77bc28cbbd9662302cad7d0fcf539607d2caad321212f09	264	\\x9dbad097aaf21d3f8939aa3cf16dd0d5365c610af5d6e1b9b9447f341799df876b7f101e0f5839d117f7f27b1b01242d9ed3fc579c17a5916d2d6c41ffe7092becc4317a11522bb3d84613309fcaefde37a45b278d69aafa56d6eb8d9a30270cf52999ad38ed3c1b962f9784222c003257f5ff72232b3afd45973b1f55b52b66	\\x49676dbe51eb7d1baa971c83b0a04b70221a7a537c52677240458604c11958b078d9fa25b7abcaceecc7b2518c379395c6b57e3de34862792b6227d7f436adb1	\\x00000001000000011a3fbfe882ce4e34ace05195fa619dbe87dc250c03e23f57cfd34132ae587bc08ac2fc82ea31eb7122da19e2fc8118a20e4f45c9e6d0e2faa40136e329a784aec6990bb654baaa819b5c5fbd5366fac110390c6b789473a00339ee9aacc5773d8a8112ddedcdc9b707b510dfd91ad4f81fc9217e9e701ce7fb7b89ed911523a9
23	2	10	\\xfd92aba81adff23c71aafdd3899391f7c799964c94ddeb1e6cda565f0e0ddbb0cc361497324509104a2dcc222ab6068ff433aa27bb859f977cfb84516d932003	264	\\x7ae09fe8a12e220437f324a56bd30363ec6a75c314c73d4ddfa280e661065eb65f5f2e9475fc404c1da4617b5794b841b32172513d69526ab2151553bbd28d3bd611b710d80688d5d200804882ad42679a0e5c3046d6c4c20fb4ba612af6ceb2f2b979c7964e99bea30152986f18c13e39e9bbeec414960dcb8b1dd5547ebb64	\\x7f59ee4d8f8d4261b1ed75f199e5e3a08eadd8b971054dcaa16fb2c5489f35f5756af1402ec1679f77c5e9ac4005abd466ba361de02a70d2ce16c97d34280bcf	\\x00000001000000010856d097676fc94d950a7936b9416e6f4c891a4d97ed7375b23c29c07d078b7e4e7b69d98a2db9035b2e04b1faf129ff0583af552cb46289f2120e7f42397fbd373e0b165708d26cc21f3e26cd9ac3b3c70c5bda4045c0eabf358b2f34397a657721184719546392d2725333d274394911f31128f20914f9ae205fd0ca67769f
24	2	11	\\x4b1f2f7b8bd05c8f431a585a6c05b62ad6fdbb328459e6391bc8c9a42ace4d0202a74ba6f7acd534d226634abb8ae47a47a3d37f600e1a544ba7841c85e3c70e	264	\\x0e6f838c34916e38ac45dbeb203bc1f2ed6f699c7cfff074f4760771566bc122bc32bee299eae1a21632e64bdeaacbb07999e86bc78c6c7f87c8a7eb26ce161716503520165b3b4933b7c658abc72975355a3c04404d05d2de70f3208700c4687528fccd4ca274510980e05c03de83554d3231470515814534f5b80c76665235	\\x8358e7041474dfab6f843448117ee602761ed8fcdc102eb06cb9342cd1d36197c823eb3f28c5f1f67b6bce4337d1c4630aac0e3c6177337cece99d5f21ec80a4	\\x00000001000000016f86d5af3aaaaeea3ff993e0417e05d56020e60166766445e13aa76685afc5c0b0f45954a5929b90e32596aca2b910137a95d60e37b374e80826462907e48da7cee20bacc19491e9d5975fc6f6d870330d551ba5f7dc5a3aecc158acd721006d52cfb894dbd65150515fcb05c152fbd2a6b7585e218b87f52412343a79a75732
25	2	12	\\x02b3b77015c737a0c916b6f17afeb3574b75496759c4e13fe3bb427e465026f01ef20d0143484a785b6e75bc7a2e4152c6e58d3fe322301212a727d9d923b501	264	\\xbef81865eeec5d32ec3c44721d8c7c2994cb91ab544f41c832b8dd36dbea517d435f6c2d94cc79b8e3ab0e5953b9667fd18d4d493744ce5af0dccabd69e829a7cc643057a754a3aa3b31cffe0e94fe2bba366e66c881a2f6835d2a107c9fb623f00100cd36e3749cdbb06021a3567f140927d713da378f7b0df799d03b122067	\\xe4a24fa2a349b602d59567169d502c8889cd5cd4456f4fac79fac2d38be7cdf2ee4ef6875afda1d08939705f3aed0e6c7dd328853632123b3a51429dc7fb6d30	\\x0000000100000001a57ae57b00699f37e9f4a49cd8e2c69174f63aa647aaa9e104bd4da20a6145a9d49a87bd4b368dd926f0ed0516bc9004c631858c3bd30411c16bdd4dadc7e64f99d6f4bbbb70160740074a2b39344dc276a760eda3373813c2e04878920299a5d86fc1abae255e6f6d269e69f5802eec3ae82dd027ece735e901177971ec04b0
26	2	13	\\x49834e8827f71b186f0ff6f5c49e65c9c1336463acc9e25c0594c16f0e597e744f7248c16f890e31cd25c5d5ea2db89e6729eb9f5082a11ea4d6cacefd7a2a0c	264	\\x072ae67cd56ddc1bd46ac9290d8f5fc4020467d23e41008f79d541b6e698abcceb7cba0e5bb8463b7ff9e56fe7b23f297b2b107260675c626d37e40a7c31d9a3e47250f3f152f302901575506ed5e0345d5ce55585d31ad6cd8c244fb8d596c868d9039647ab388279e54c8de149eebc8767bccf44add33ad8d673cd10521ea6	\\x19f13563bd8a01c3bc429aa451f4e0330e155300d81b5c0b22e3a66aed09509e0049ec1c8b716403a9e518d4439e83c1b66ba271f82a7a9156c65436b14ac9f9	\\x000000010000000183d11323b86ce90818c899d4fd13757a95a30e24a3f6032a2d51c5608e5734b787e82fd0f52dac7dd950bb91bfbff2ae46fcdf405178015ca794ee65d6438f712a089ec97d2dad8d7e7fcf8997a520b75470b281ae01c541d65d8cb6153131f1c2f34e766762ddbaf43aca6833420d23f7d20f6889d8004c154ba6a8b62718a2
27	2	14	\\xa183b1cc525db141919afa520a1cde9ac1fa2b369996f0943404d9d18e5ebb7d23f535153545a0a238ac9f175d08a860f1ae6f36cd203e06271276dcbde1160c	264	\\xb97a30aba26139a91a63dbb6a87cbba29433f546e529ae48601f6be15d4f634a41000467e509611d4a5025ce070eccd851844cd913e0208770e06156a0c96842dbe7ea40f793e7e41e6966f5cc2379314d81607fae56dbefb23532e52fec38174da57b369c9dd9e4b917064201dccaa99d2bc180d16ab2dd161cfc85dfe60226	\\x686f1715b29fcc677b24c0ec9f4cf15249fb004fc73f97b5817827ad8b023e503a25b2eb827b1455284a1445f646aef1aa0e8651f41839d7c84d12a1183b43c5	\\x0000000100000001813ab426e0d5ed6f60830628ee5132c5ad874a6ee40a628dfe4e3b7093a1a0be22da8896f02691f14f068ae9cb1c7b69833d31fd4f3d9b09c13cd14ae459af36b2f475249c87b52ee179fa6258c1bcbca1ad47c8f6d15c482097e1e37f75a774237c723f322a4f64268bf72ff85969fff432e9aad53ec5a3849f55ab03b8ad87
28	2	15	\\xb7ca662746fde31ceba26a9a884744bbcb3ce3bc91338f0650dfef1e0d131500fa7e50053516d7aedd859460b63b3c050b265d3d21e8626ff3a32c9031a2b407	264	\\x30b81601ec6080f5e05f7cd67562f3fe9ce5687b5ad1d070a60c188d341bec921900fdd37624b1b98d13acdde325b95694c5a683b46d89421bd8826836dad1dc18d5b9a537ebe61d8fc949aab492af0c6deedc52baf8ff9f89bfd5643d94e1dc2d99721640eb1d50f62519c23240c87bdfb49c5261256c4528fb78c3e5a2f9d4	\\x9472b4da13d2f6109cc9a0efb9d6f668fb7188b91bd668f3119ee1efcb534cf56400e2f9e604b85b616242f6169c6d9edf35b298c708017108d950168afcdbca	\\x0000000100000001a2a822a2343a24b09bda177813a8abc2bd5bce977e7c306b0dfc474bf613e95e3d76d05c5213892d88878397380b2eec39c14224a07cee126b69fd7c54acf418fe1afde82e811bad59ae6ee621bf233d387976219a77be8fdfacd9fbdbcea561b87d5991426655aa7c33c21b89faca1fe636c03e363133ca9e8ed33115914588
29	2	16	\\x1fcb8f9d9b9deafc3c57d5fa8d4b0a2e31013cdf96ca293d3da097edc5eb905ddc9d2124407d05ebfeeffee44e5faecda19a00e181fe31c44883476496c0e00b	264	\\x4785401a0862d8b2e1a826a921f02bd99aafe4b49c774efdd291bd0aa8f5bd4c1234a71bfc7d3766b7f2b2b7240c3459b126f0ea268a06a492bdfad3a1c78dda9ceb3ce2c57eabebddec6e2b7f7868a03c38ea9fb960c445919f922ea77293244bb7807ca219a30d7667a8fc57ef8b0632d434fb65dc7ef669075ad32455353e	\\x8af26b24d8b75e84e74563a86e4ed5b901bebf1c957ca948c99f84954716cb8446c6e7fa15513f7e0114e1e50c8d664762218740e2c1d2da9c26b2825fe8a5fe	\\x00000001000000014ff0228750e3a387d155c146d62ae9ce3fc11be9dc17e6b50a3ee960a4a26bf4691216e536156ff8267029fd2dbe740674e4620e32638fc669078473f1000e15179a114f3fedb3988ba65cd03835eef247749ad3bd8f29ca1a66a82b5e8bb9395863946fe2b002007b04254f2e9c22ec93f7338ab28bbea682bd638aebf334d0
30	2	17	\\xa62d41cebf78f147293da0b62bff7be8e8270eb4643de89ea8884e42d37764636506e776eaf15d06287719e98c9500c25cb8dcc16093bee5145f1a4006949a05	264	\\xa8be262e9dac9cc936e0e68b1bc0d2a639d87027ecb8777434a45c186f8d33d92594f5f958e3bfcbb76814e3148bf63a5648d684cd0d096c93da51359c631ae9228480a89a1665714680622170df475ddaf2deb81b6f8fdbbeeea187d12e77e58c6bb9191579a738ba9e78b62e8c8adda1ed2140effdf292908a44764321c0f3	\\x6195721d2a632d8ee8354d7093541f1d8257ae0662c192b226ebce85b149e82c7bd0a8da4f52e2da45e04163e341fe3be36b844695ea5151a62bad68a4c5b3fc	\\x0000000100000001296325664fb139bc970b7460a13e24a0f919d2e4ec22fd0d8cfdb2d5ee7e8f09e5a6deeb1d8702d98e694fd898db97223e0523e015735bbae3f483e6f488e6289ed7a29cc29331c843442d29b71e80b80107bd7bdec5547c3666e1f30c7bdc0865b8a2f07105654ebf4d9d0405fe6bbba75642f659f54e3d7ee4c39a772fb502
31	2	18	\\x5068ad0ae89dc8525cff4208001cd842d65a7578d2375e04bf793fc4a5ac272b454d0c3e4a16c91d5003eb08106f2b8d2fb45ca64e32559d2d3cb07bd2c55602	264	\\xaaaf39a04a7f3c6758f2f0fe7e669e27f2d9ab53293ec371db052b85b6090bcbd3b04b768036788eb99055c5e771c27912be6533e4e94c4a668e860850d7fbe42327dbed90937dd606e2653ef8c6785d3cf43f9e7a3ea1dbd599338e6aa8572f95c6803069141b6f0c4aef98ffc463febc6d8b9c6700f13619ab749d0a6e96fd	\\xadf13ce5f7bff4a1232bd76755bc91969688a4e3cb9f8864fd878ca32468bf9d3b1b8039c7d75efd2500f98f193e817481deda71814905ee907cf024de0e26f0	\\x00000001000000012f946fd20a6fc7587c6372c7204cb68f06a801409d6afef21936535090c5b9b9bc77956a1949a386795d0ba9d039b65e0cf3eb3115211b27c0898639897c9a5ce9cc9a6f325769c5e10fc6687f0319036a32510dd4ce81b151ade6510f3d0f96d4536f7af42d549f1e87b3ddd1080c2103dd91ff11eb1ecaca2e3aad6ef02a3e
32	2	19	\\xd115472ec4f38de85c5232649ab704ab2c25078a59db5282575e98c03f7239c564be3c41d7a5ad38663d14dd40563450b04f019c9072e3ed65457fb7b90de407	264	\\x61cb0e0e129ea6bae520c8dfe9650bd9dbd0234ab5af143b7ef9a319e84ad9af45a3d055f7a81648af9ea3bd5b3e1b99176fd38c136a6f31e1633aa334e57bca2f43b37a36c3cc87cd8f0b1b039f681c192c3e132fb54c811f16d2366795ba738476e13487e43ee78e5cc52809f00baa7eaef822d6a2d84da0aba48209fd13bd	\\x08841aadeecb80099cfad8d6f075dd14f91a9cca32c9771b3634f2473b6b5fd45aeca98e1b44335909056f4203a857f2a5c44cea4a7cb2d0a3a5d6c9e18d0411	\\x000000010000000138e43f4091cb916f65ccb67df5f4ce9f021692723dcfd394dd0d875a87602d0744de0810c13d4a0459e61d2a8326fed6ee535aae8b06d1853a2d3f0f67bd884c3be7b548fe90d8aae1281aa6df6b77bdfe8263d6bea961757e4c2610d32ebb72deabba7276bd47f8fe9dc03bb1029e69cb5dfc2d849ab5bdbe80289210667685
33	2	20	\\x5adbf7e75200520caaa5730f243b2867b0a68dce77e1c04f4ab166f670bbf14b3f02e56d0cb98ea7f55aa63134df61bb8daee67f366b2568495aaaeacbe4ab02	264	\\x06e9f3a11c49626257d85890718dc63765204b59c25da14c77b37f87aa8248516dfb040a3e25751c289ab65f0f12a541d138b86183aa989cf59ea20447ae8f66d08042c1163db6f6afe69d271c44f2e0d01a656e1f68aa56c6daeae4d9861a76465ad5e1c9da571e03412e890744f09b13b811e035cfde1419a083a6a0c49e84	\\x775b81bfec7edf5841d08ec9990e3c132b23713f5503d8a1399371df858301beff4d67938d283ffcf82dd696a55131d1a2bb16c7b0427acd2ca1731735848653	\\x00000001000000010ac6a1987653cb085987c9b8d21b1da9cb89ddd3d711c71d7092da5f1fcb7ec9a66057348ee291b72ca5f5d975a9489dc21ee3a917ae7012775434bb5a20be9d7f82cea15114adb1f19048baed2c95d937a914aaf7a6214e40aacfc1b07dd48f44cd2ec2ab8fffae408670b2e66ec71b304bdd75f1610d20394edacf98debdd9
34	2	21	\\xac83027d7ad2c45a16e1521cae8af9d11d78a6da90be829e1da663ade3a7668ca83812557fab8db5c260c47288a2b699ba6bfedb6c28b82fd848eedac7ec110b	264	\\xc1a30c8ddf044f1a9c411ef9225c8edecf6e68cec1b47a9d60da744c9b29e9a591900d077427f12fe03453117912974928a09d0c3bddf8d1bd2c042018993fd3e97919e585bdd0c81434d472710e4787a7c48e85ebe85fcd69dd4ba6f26d302cc669f0b4489693eff040da525f30f26a254c6056f0662c59af17e24f41926acc	\\xbafaa6bd023431ff3fabcc17ea1148fbcfe0bbf6f8b2d4a7c33d6a0e8cfd83227ef28f65929f3bf3e487c7016887c8b4a53dd428cb62c518732769ef02f48e06	\\x0000000100000001124b4df367e3f5e291b216048c5367c9e94eb570605c51040f23901743ccff5633d267dca6a6c2a7b0cc8db5ba559818dfefa1a2ba985821d1fadb6fa689658597bbcedc2f54513b09b668d7a1d9dc474ca149c1b4040ea19cc3f8941c36efbc963b2d234913158b6a8cba99a6577106967f8fe2f861e9c7a41847975df719b7
35	2	22	\\x035a3f3d59a34001fb94b5fe2511a0cd19fa058bf48c95e0fcbaba66a7844db7d0b4049759e1b26240d3bbbcc64619a76cfa552c5db2317a16be43ae85f8d301	264	\\x8909a97e91d79b0c6f196942eb59117586b12ffac5697ef15d732aa03f935b6b349a70b6399b5645e10791f91738de2984a3f4be2d2a78cc56ba06f6888ea2ffc0b5540b08b1f26702dd12c82e08895e2025904de2a7e607b4a09626b7f3c3cd113fb72fc9768fd6577f477aa1e0fb1c22082ace3ea82f97f8c63179d49c4fef	\\xb4359af06a85f08d9abe4697758543fe9a921ad89ae91aeb1a53949436c145d8fc1260baf64ff5123f39ce116b65995ad9a5e021ee07b83b344190732497a459	\\x00000001000000016ee16bc9001312dc72de0ffef2027c4a78f1e63ae7b1188ac257c0161f5dae93a21a829fc8e0237b5ffe892f98be0659b040a20303802ad380883051626f3a1efd25148d7dfd4cb98963e6aafef837f49dce0ee112716684e18e50c3b39083c39676b8cb24eb27fe09a0cf3cb0db2fb73f080c44960db31987fa3f633d3b8d07
36	2	23	\\x98b996a58c5207adce6b5e3f37efb9f08d0eccf254eecb7496dcde1f566fdf6b25fcc671111418737e5b510d0201bc450ddf50b4b253217118adeceeb9814d03	264	\\x228cc70198f2f61a4a1d35fb6c9c9b0c88b65be290d3e103cbf40a573ddf055b14531f752ac481d03148feeeceb46940ebb3ca6d1750974b3afdd9ae9e3881966ed4839155f083457acf94f0c6870352c7efe34796a392de6353b6afdc1924e5efb5be9e3e32dd328e92cab3ee7b584901d5ab6206e2114bebde6046cd4cab48	\\xc47324b605dc1324f0e2380497555d138e62afc43f4d2d243b410b2e1ad0f14de92e327b24babf497d4e89c1a456d99f2191455523f1d0ab9fcf3b0e5d269750	\\x00000001000000010f2f318875cb3d8fed3d67a1e2e7466811bf683475813e3a0186efa877d5fe7e77c4083cefe5ea1079a46f618977b5e6ed74883072d80ae2129ddbd78cb081fc009490915717d48b46f38f108d1735bbf405a84fcdef4217b2e225ddc68e4cb22f91a80de584ab58ffaaab0a2faf093dde13c6d41f05f6ae31fbd834c4f74589
37	2	24	\\xbf1c7151ad4661556b1e492c0d0833d549483f0436a2dd0b3edb0c33061a55ec740ccc695a3501f0bf3a33feb73c2d5fea6275bcd883e4e2aa95b31eb92e9208	264	\\x348e5f23b69ecac984cb5117c6df7aa114926757a1d75559e821b70cad4f2548b3e456909403b20582c2048d4a864797c4e89e7b8ec7e38c6ec76fef6256b86a95d22f849ab08b4df1e5db02a6fdf0a5981b5e75023fb0bb271267994cb61948cf4c6a192209e6d553feaed0497eaaa20b96d50b7d7703673866018eda53590f	\\x6c6b783599442a4f70098d8278a9e7b82c05253b23a9d69ef45b4b93f0f2ff6e6d7568f26fc56753274c0cabc05ac1bece8430f218f2ed13d5e14bf7a4b3303f	\\x000000010000000173c6e3902d815d80366e8b111288fd4eeb18f76324339fd50577781b6d5dd589ac3c99722c0eab396e3bc1b7bfba0d20d85a2dfc723309e16d8c82e1e845555c51b8ecc4334362d17b7a6c496d20332521845bc1fff3e92adce7883695cc3ed9b5cb73a42cf3aa4de2cf8b130ae1a49ef04b250c53cd00dcb6d94e54b17feac1
38	2	25	\\xae9a04edb11464e50f090d908d1076c70d7f395f54b9de61a1d5706e463b606dc5d7d4d3e46f87414462afe7dfa1c1a8f0d8d2c953d86ee2ffe6e55b0e335408	264	\\x30e18900390e6b8a2b060131510a7cb6f072f30a1b55a0034861e0f819644475959840a7c4cd01d9d78de3aaeecdacc23ddcd45062fe3e07d6c509dda2d4668bfaf7f3ebba8a56bd032d92f3b30d814f10821445dc364636a80148688e0d728337882f9ff140f46dfe2e92d15ba69a0cac1f225ed4e1d5e221b9467edcd9dd01	\\x84bddf115e18f9100c8b50dab77c8254ec70eacdcb84c0ebd5c610d8cce4c4b4b09d80b13059048e175c5e45d3a61acc7a02e1684d684c523b849141e3bd2b69	\\x000000010000000154e9d88ee94fc84165a926ce002020b4d80446c8167eec749d48632ebe35bd05f01a139ada1d949a080c5e691451b2b811489884ce1acb4255e53c0753abf3151e781829ba2a5906d45078a89ab81c134815c32ed3c46b74156e56b6fd3ad010a9cd3ca9a5f1a8de97e78e2e2427fbba6441be9e9f16a5ab8d06607f74ebdeff
39	2	26	\\x1334e9d8829ed93c142c30bba8e469e3d94aa0b2b2cb3d5238025c1e379bb2cd00f8584a7f00aa5e962496024d497c55d24cbce3f22bcf0e441d42d06731b906	264	\\x611f900fb2fb36795a16afd6bab1365451fb2ed1e5220db6540e1a7aa1a6fe8098b568f011df2dfdb3b1c4d53df0aeda4510614bbec35c3b08c7f5d78e3f618390c970745f41db8e5cd03a424b06d3469e06706fd7eecc71764aaf3ba20c87a5924f99374fa74b266558f87234c7fc207765c4a24ad46303140a9a4298a0c4c2	\\x0b6988bb84bd0bdf5874cd5489d41911c26e4aad6944cea723b9369d40a7ccfa146c5499795f5f15d16b2d551e957ebdbf5845d1f6278c4c7542f2a188509c79	\\x00000001000000017b6b47e60bce706d37ff51443496518a5764054832f2fb371333e2b766354a97a49f2bfc82409d929015d52a1f42f7d02d0a3abeacf5c1e704c78826c41c29891834cedaf4376889aff893fc18050aae2f7006cb8ad96d82f3eb1b059f1a2845405294ec0e4fbb7881e772a0270e4b4dc2eab79fbf3a36af20fe19d0011bb673
40	2	27	\\xbf1a5c4e0b6b6a20a374b959055362767392b38bae35354060fdcaac878751cbf1a4434d972ef94952db51e338fafa7f6d94de6fb73d0c106ea530451f779b0f	264	\\x30aa2673a9eeced79879de6f6826559ec18104423eff556b7b609d600e373f372e42f4a7d2a300e4d910f91f2c4395afe5ff995240c84222170eb548f04c00f785cc9b633f03c022091248613a5d520a713b913dbc025dc4e595ce2aba8b3810c7ed90276db977b7ad28058a90b4f96fb4293a42ba8ca5e1002f45c3e7cfa8d8	\\xe9d870fa4340f332fdb0c93ea5a9edaaaa2f13731baa4f6c5452c440c54b59b664bc1453c80e59541628016e254f476639e88576fe20e9be2c7f58b201e4b5f5	\\x0000000100000001aba8c847541022b46419faf7408e532d16267edd5182ba8ceced57186f7a78741229bf11990ce57e2719b264955bd2d8b1bf3186b48941f586bb6c5d5f6befc74eae5cd1c46cb62beebcf9fdd3b12306bb9004b2f1bda71fa8349d5ac5a56739702dca57ec704d9dbfb46957196584b1b9958eaca967a15ccb279b6d03a1f800
41	2	28	\\x44ce310f9ba632c80374d2a0a259798e7fb312d85c3813e9874796f708921f69ad3fc898dd16e5dd0b3171e9de679ff2aecd8ae9a8b3d47bd1d15ff3b6ba620b	264	\\x11355c3c5f2863c76ff2398a65ea43bba70935db44cd29e1c4e15a7f0c733d86684f073bc900bb066ba824c0947b5b44529b3f78047687a288d46e90ea00fca3ae6facd124755f2aacfa2dad3902cbe1d0376db0783f46e001e53fdaf630bdf6fa1ab800399104ceff83f4c312f5523242b9152856391b39b255d9c15b81687c	\\x69501ce4067327a88a40676d160b5aa3ee3451cc4cffb65707346b849b44c0e85fdb693e86edb0485c34c393bee3042e0652023a6b1da2cccec889aa0041b794	\\x00000001000000017be83730bdcd60e5f2540cb8e4c8b164c607a97b40c4eb446f3070588b0c02e5d3053612a09c04092a022458a3343674d599ae65a7a20f1fc0fd1e2f976e93d2478df6517a94b0e1ffe9e4e056e9d8bf5f7fe0bde3c8a44ff3469ca36cb1917d802373a6e141191188691080b1e9986602daf7d602e97523ffce53843abdf36c
42	2	29	\\x3a3e5a84c16b13af76e500d839ed1037c59282875863ab731224e93e200b1c1dc1ecc8f5d830365ac17b723a25cd0bc4b4f1ebc669454626b3676ea9d2ba9d0e	264	\\x7c7efda399ed871156ec80a3ea69e914df5438e2ce7ccccad5866c8ee4d159b85aa8bc97a6dcb3cab492caeb4450eac8784a341124b8a1c543d77b90fd517a25e0583ee38efd9d8a87497096cf72d64165e525375ac905a0c7415897d3db55a67c564905fea492047a5dcccafd9213d9052ce5e9555868ee76e0b16b3cde99ae	\\x1f33cb7480bb33b9b51476005ad70f90f85888dac7ff6ea131afea9a2191465df75e9d8121c9d5c7834eeb68310de3545e0c290170749c456e40341d7b8079ad	\\x000000010000000153bc1c3f8de50454baca08fe39ddd47384d44b7c68d5dc97c7b6680d0ae1a0af4f9f8cb04aa7a04e558e20684db4bd489615eb0dde0929a49df37e43096f1733149fc00cd4f486e927a91f6f7162ef207913f46b6e77b91faefc84ee85a6ca2d200576800b4ac20aa24b6cf39ad610ce5cbb0d54e8f052b652dd997e9841311c
43	2	30	\\x2f0e5f0454e79b2cfc6da7c3530ae95c4d487edeac293ee540ce56fa655012a4e68a24b6c342ea46a714d7b85150d4a3b0780fa84e9641220a31bfdc43f1e10a	264	\\x4d1fd3de1b4cedee8654234e8ad7c552f42f482ba467c63a6ec6cf4fef0e2dcf7b311e6d03306d823a1ef8cde7e3250d022ec7980293b21c633cf17f72607794130150ebff798d0e4a7db0bd0ec913f686f3c9f27377a5bc8ea225746122a74fcb236654d566a376486749c16e3f9fb934a6b7a269f4fb714054b504f553b5c6	\\x95287bd29182eddb23c7d4087110cb71c1887fdd3b32a5163d6b138420f714487fc3a1f508c61ade71881710f82fb3d4deed951c90663f593b63b8cb7b4fd08a	\\x000000010000000118ca2310bb7ca7554f1e93aa65034df958cd2989dcfd22324c4d25eb7802c0e8067ea44c335e8933fe960d8c59ce18e7779f594d87ab1c709fec270e382724196d8d4db2431a648a6ebc61c288110d96be64b2082fcbbf4f0cb66c630582a243ba0893db0f8880af2b982b8c5c60f5336e8377d0e3770823aa0cea3cc7ca909d
44	2	31	\\xee15a0572cb883c71b45ee68b9f6119ab23061c491ace08db5aee0c033ab9c55bc45fd4cec46cfa0690693523c44773c22c188abad60e7b5a7580680ce8bf60f	264	\\x044b77f67158f3c63eca2692a69743b4ee2c241e1897da718f27703ea053e720ef98a1a15cc7a324efcb8b3c0f2c272b1701206d68484c52cd54422aa7445f4e10a3cd779a343ec47f0b2b2c947786a9ab76fe23d0f126cbe758285980eaf73d273a7884c030ff5a94e07f3fe162f51a988c6420ba467c4f1cd81baa13af6d12	\\x5808728b076b8fe1b31d84105a29b313e2d2677090acc2d8976bb12b20e39464598d3cf336a82e4177e782bbdbd10625ffa8cb1f90746b43539520f12bd051c2	\\x000000010000000167cb53191573ef3a3ee8b97c07623bf8e1854263fc20dd64764472e3f9e713e3541407a0e4a6b6dbb2153f4154a796d885078acbf04734d1e27fe33084b746697f69a3efc6b814cb4f9c5a0b9e7cbc6bfc9599f590c645767de33eba5ffc474e0b859a144fa92bfd3c1fbc76cc8d6a3e827f669b14fc6cd2b1a5e08e6aecda17
45	2	32	\\x4ba4f0a27242006c35ad59394747574a345d4467ad702f607241f849908bf2955ba486b4c3ed0fc3bca7a048173f7fc6b2fd80bfa5b77fbc18023f65153c6a0b	264	\\x4af883e3c9a0be22fb029074f827c808d12b98b561db3cb1a5ad74d3ca969af0640f07882b8fa44d499024e9126aba0ac5efe092e6d3b2adc95eaac66d193a33a270fcf58711e717c4e4f14df615d2b6aa2e94f6208020f641b1582aba0da01254eadc13958fc099d25d2527ea18cd964a1d057678b2f8a7553dd3cf9e94d573	\\x4155e854e5f2007164acbe3541b379f282d88d2481eb71683da55efb0948f479fe1fadd7404f39a1de0315f54d4031555e770d7a9b4cab6af05799dc9d48e512	\\x00000001000000017ebf3683024478512cca1e7227df1e5e58fe38019a23c6dd2a21668da682c266603fe4311cdc941bdec2cad11a3584d0d1fd82ff5a857f237e6ec0d1463a23ab30c2e067108852d7415e7686b7ad236a9779ec13f7e33b700dccc44fd8f8d5e3b868b4ee4e35d4d95020665311bc2e7b3d61edbb3414f56a846a677a3efaeca0
46	2	33	\\xff45a95251b6ad55304496bbe4181851f234cd72861069f4451b6d271c4e218b15d5e2a46d19b470a2384666ff52892e48258de0d446713651ce35e8449c590e	264	\\x3f4d00d275496d09d684f46a078d42d7edc1a0b40bcb1c2796d65811daba7d550c627801db004d2aabf56678e6f755254d37736e7d6db85b62fefa9c168a6013ecdf171951a2e64e8155c52b8fed02923239886577dc892b64e163511e94c821f148fb22973e92e136f402be5cf28859baba2719b998eb9e654ab21a6b5ed61c	\\x25de4e2370daad51493659b866d077e3650d4628b322cf3c28111b62f7712ec722915972b9e40f5b417fbfb28c567da8d3923c1eb5e3efeb3e8e983bbbd1c277	\\x0000000100000001924fa88f3bf3eb7cac1156196b0eff71b1f4996da58f30b66475a361aec797238bad20f566170c29f58a5b2616dbd1036122b608266aa4501418d96302d896f22605309bea2b3c0ecf85a4cf94452892432a1fb3c6d24631dadb43fb094d48335dcb414a74e03b880c054895feafe0e64ae67432b532261133cbcd57175dbf62
47	2	34	\\xbec718eec0650f486bb27fa753aad0732c97801406e396e493b0b292fd6803eba49aa75f80824f34b0bbb0c9a192a7fa697896803137df9714884cc7d65ecc0e	264	\\x44f271da45f1f87089d86abe77aea9d77ecb79d9dc2de3e2b5dd9b501736af74b5dc70435072f72f05ac9ecc3dd89ee9b31ecf9b08e4d9170875a13c659862ac121c82d81f3b20ff00f001142c02484633ce3d39fa6a4d89226c8cc1b3a060d3c23de2785e14e9d968d77bc0f0a038662ea9a069df83665f7f2c141685aac7e4	\\x7f45e69d97c57b7a08a0c0359de6bdc2c49ed0f3b7e0b6def9d58e4b9ca5c6f86229b1079ad3720eb416fd116eb9f6e33655660796f8f8ed86fad41861046ec7	\\x00000001000000015e2bdd55aa3b8f125601f474a1628f5bdf81c93756b151ae9d924dfe3029c97d0e03185d91e924fe8c1dd13b43fe09d317a6167dc1d140ffdc8128cd926d69e5b5b0cd4648d6073a4a7dfc1afcdfbefc1feaf977a0f315f9934b6301b4c66399784d4e4122a0866d762c37f461d47c9cd8fa477f6f0e9ea174163284866038e8
48	2	35	\\xc175551cdfc5d5bff90850ed5ea8cee4dc2621f0ae34eb481b2a7d2388dd8fcd251616efe5f2c682019923608db721f0e5320c3cc6b4db470a09832e3d7f090c	264	\\x4d3e181de332c453ecc705cd6a8dc44d80d8b2fdf6dec876cb902409d2ff76bde6c2ddcc45cd5ac5f572c24c94e918b323366773756279b4325be503c08734f4917cf50b079b64bebc029fbc6a7abeba5bc0f5880e964bbced84ed191313f46bb7d571e69d85cd9fd485513f0b3a479f4935cd5362a083b547378d4bca1f68aa	\\x1498e11af9e12bc0451dc5e1bf37c0e2bfe536a024ef9b9b6396c1d7a7eeecb414be309b5e6b073355533939559826edad9c51480ba8befe0ccfb48688ff0fce	\\x00000001000000010d2d0047ae1e5bcd2de62ddf46ea4630b8cc87e317a553e7613bd0eae057c531bc5362f3b005e0dcaa059c083c1109614422db2a23095b68eb426187abac99f809ec991fc879f99b53f18ac6e78b572adc107476a26854f67fcc1e27c51713c0dfd5afd33938190cf90580b2bf629315b6c477eb06cc8566c368ce92891dd863
49	2	36	\\x7cef4150f4d63c21872f04fd7d37240ed8d60db384c02213677f7aa1d5fe138bcb79f559da6e032e65f3a5cf91cab5ebeee259567fad5766851e403a053fdf0b	264	\\x7f4ac29ad1b5349e41deb216a83f11e2d6119c50737f1857d9aa3df045eff0b4f51b355f98162fb2fa962158e5f22ca31d1129c47504fd3b6316b9dfc083633d486f39f54733f59cf76751c966e173089df30754db18a375070f57f41464f2a6e189da7d9bbd6a244cc3d55c018572c4f691b6990d8f918c6f508849d075297c	\\xa919302ddfd6dd8aa5e22dba2c10b19bd217236d17ca16e29672d83f1c5344e27a0e3788f48a1829a28d9a2da12cd1df55d9da8ad3b91ab39455eb483ac95ac5	\\x0000000100000001b6c8fe613a6f0f2a44ccf672145d815fa5c591cbc7ae99b2dffc8757cdd13a4bdd3be68e19ea8a1a3ef39ae63561fb104bb3630946d6e01cd5293d372b5aaf353dfa919c2efd1d9db867931d85e3cd2c4e97b81ea06c0ea170ad40163b4f11adc1f82ac6d722db445f1cec1682e16a1a9cab69ca6efa08156004bd0728a7c8a2
50	2	37	\\x23ad840913cd7e3fc37d1d7b4bf2a9f1613bfe1058d1f59a3fe7052edbbb95d3171ec821de95b9a4f3e8427d3ea895f396c35d0ab2d55a2f530779f396666908	264	\\x2db183f7677e76193a4b5ea5e6000ddaff1873939a7ce60484fe3db609b3b727ef5f4fd5dd6c2388c208443d1959b03fa0db296469f52dcbf5d2f06a37cce0c25a8c837d6cc53de4e56680e609b2c1c602adbd78c3290688a2a1a45a134ea55e28b1c03adec25b6fd5432cf2a3529c24e2b29d8692636c741b8c645e2dd3fb84	\\xdbd11535c6c6396cdbfa76e7d5e6f75344f1cf15f68d1094f8d43f38dbcb664a9392d53949eb572836864568fb7d048635697e6cdbda71d92dc84ab75348b634	\\x0000000100000001518545dce779fd35e82fee2c0531ce5b19bb2c9a32a400aba6a76f9499a2195d90f15a3e52b84e545b9df46aeb92e8fe5f3d02c5a22bb30102ede6bee0ad39a154e16e4091523faefb64f3b7a13bd4b34fcd95c2ac70b96c3628e7833030265582e9818e3397d1cb069d28c256535e72fd42d70e57ca8b5f1801eb599d1b0785
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x160caea93a0af89d27e79fa785722096be5b06b618f765f481460c1bcfe70944	\\xad5ed6ad3ae7a922cc627d007acf84f2c1f2c2789e7b216358709202620f880389a4e1eaeffd9a9c85386d0dd9dfb7ecb8413b02e5721ea5634e580b6a089535
2	2	\\xc97f39eb021e2bfe41c42aa6cf36197c3f7a43182c5781566d3a1c91c0aa5417	\\x82c9ccf4103794e8794c199dd47ecc072dee1a3f5ffc2492b349e65858e2ee3c1a3101041b766a485c9a0d29b21a0ede935121e10e06b72e2347a287857f1fc1
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
1	\\x94f97286a448d956e59904f7dfef557b8dd6e47c7dc092f69bc1378c87ec7fe4	0	0	1640786169000000	1859118972000000
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
1	1	2	8	0	1	exchange-account-1	1638366955000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6c8a5bca690f8676594b2a753666431bc647518281aa2ece5a543573945ad15db4c9e735831c2d4d29967a15d7304b56f292fb88c57d6a72621e19ada97a4552	93	\\x0000000100000001babc1030733eae14ad29b2f00e4c92b9ac4897aa6eb2e0322fee41c6a2f40bbaba55d2f021bc073f2fcb413efbeb596552092e843e2d3c37102c1a34e538f404c2744711911ba6434b8d6f909e75fdd7862619a138637c7977a663111deb6f9747ddd385279aa42b29ade5ceeeb30e7bddba93f476c073371bbeac5800064fd2	1	\\xe6d69246e0b0b065938373c75634944f9a78b2bb8357dda030cd87739b9b5f06197ca8b9ed4f45c866f09f00edbe4c7d0cbc657240a29bda7b4adc7953a92e0a	1638366958000000	5	1000000
2	\\xb43e6b2ff516747e8392cd298a1ca485494d2d8117d54a7eabe9b1a16467af39b2086bc23c8d13a6c9b42b72c67952261df55fca0610cc53af9faf59b75df3fc	92	\\x00000001000000014f6895209252ccebad850275d9dde87e3ff727a65ba0bd5a05bb7564316766d14b3ce12046b02fe79e262f75d71a116757844a34545dd5408d4d491d2d2ca648e4109085d79f7a54861d8f761f1f984a01468f280028323455b5402bed50490c89d0ef7ef27b6bbb05ad130845093991ad5a59c9bf564c203a86624815223a61	1	\\x1cee98a79aa45ead1e5362dce5e3b65aab6450c407f9e7ec37b9471ccee2b2040f1f4bb06963dff1496ba32314ec1387af13aeb557006fcbe6023a08750c0b01	1638366958000000	2	3000000
3	\\xe96202116dbcf76962d8d3202949111410c58366d34fd15a599be1ccc1391fbbd070bd3fa937a51de8bc2f0baf39178d5baf78609fee80fcf87a52a007d31b5f	110	\\x000000010000000152b3a203ac44494a0006b1144d73d60b0324f62fec5a1ade6235d3cc04cc083f7c97fba23fb5526da98d6865d8376f049ec28f5d06bb9667ccf906d7790de9742a8d2ee6fbafa3f4dc687753a2a7d73d0e4bcca1b250b22aa8d9da75fc8b3a1f1a3eefdee731bdd047586aa942a96c7f7d6634291855197955a7f0db6c037da0	1	\\x5f87eb3b506c708106080e6fe1e6d92ccbfe9eb5babad08175425fbe9f20c69088a5cf4b88a68791c01f03477eef728f06672ba90e160f2a49a45a6465ea630e	1638366958000000	0	11000000
4	\\xc8b4f3a3067d3a0b72944bef56047c083c0b037e0727f7c151e4d6c6ee60c43caeec68e3aa686111de55c3d5c68d9beb2cd6951ee2c46af2404dfaacc2300fa3	110	\\x000000010000000142db2c6d21c5ea0306374db008e5611370f1ccec8fa8a1b17bebc54aa676dfd418a1f0d670d114903881b62c9d0d679b97ee2190d1c97ea7e2650cc8b0b672026e53efcb85f54c1d96fb3150c559624eb78a656ecd187970feb9af969afb980ef42ad2e26ec060125a8d947a4c5d00dce28058326cdea8bed5bbe7dc99ae9348	1	\\xef55393ce281f899d00d25869c9d6dd9a317354c099393c4d78a5f8abca2162caaa2b5548b3d8b3ec0f8c5f58d5c624846f6d8c8fc8b61259bb3cc9b175aa508	1638366958000000	0	11000000
5	\\xa388d1ef3c76b105eb438b2deb0ac7a9fcf9a90d9ce91d33819f4510b8ee122166fd09d0837518c56c41e1216dba72bfe50fa86e969e98444a88fbb1b3f1c8bc	110	\\x00000001000000012b32a8e3bf690588455490ea845016ad911ba610bd0ad2ad92473f7e762efc7f61d6c78d0045b5a60372337a681ff858a6bf47ded423d00d84712112be1a8c53155aec8d2c4d36020a9740ffb75f138edb6d6740264486e4ee53e7049fa23c146753976cd67199a08a9ed19292b6da4654abfcbd18287d93266f430619761406	1	\\x6ae530d29f70e9fc65afb1d97895365a96b7fed82356e26fe51b313dc71dabeb923eda6134dc5fa345604bd46487e65439ac7b44f1793725523a4e02715c7800	1638366958000000	0	11000000
6	\\x0cf47602e10010acbeb1bb3fe1d0639773212cc5756f215f0ccddfeb088e8ea60a6725fa8572490da9b506689f05ae71aa0510e19faff23cd81be69f82505fdc	110	\\x00000001000000019c569a66fe454dff2c5bbf38504ce2a6765bf4d979901b23addbf770db3774073dcd99a6f08ace44fc4776c983207d9dfab8c9f14497d37d6a18a00fbee5441b2f4f47f2b430ce5ecc2cca3c4fbf980ec44c4b94b81acf5e2c1c8b5a54d62a0af57570b4f0909b27d9a7cfd7a11806de4846067b35fda0359fefc9b1f617dcd6	1	\\x721e36730ad19653e483997c83c0d580a0509b96deecccda4cf075ef51571f70824a7c73cafe7d86efc9113a4ee1a55f30270c27cb4ebe6b17a18578e8ae6000	1638366958000000	0	11000000
7	\\xdcdc7cb3476a04340b3e8404ea73b04cea740f29a3d95d677f3a6fb264865f5520f72312687f3dee35adc8d316e1e5c4823361b9ca092ee6aef4f65eb8bd3838	110	\\x000000010000000131c965c99cb7fe2a822271eca04ef199a17c4c88699ecf7c3c9718877b7af5c9c262b2404750b20b486c3b2f2b0317c071b000e0eeb968f49dcb39818354b3fb3343fc5aee9a6c5a27be2d284f0b46537b3583d398e28fd252ece60bba7229e3da6eda662ec1c720492d9c629a02e1fe6fe6ae4ae0ff684f82e4f6f3272612e0	1	\\x330b6d555089dd79b492fe9f74760eb0a199a575441ce3f37930051f7cd020287058794531cfd66dccf780586dc938a46182c1ac7b304787d6fb191593826f0a	1638366958000000	0	11000000
8	\\xb301fe6e2308a170dcfbe7bd9aa68adcc0a73066a4a916a7cdd04a2442f3f907aa1386e33b64da853efea3bee6947e3acb7587c31a829f5039eebd2e3c7a94fc	110	\\x00000001000000012eaab3ccacba644bf3b400dc9fca35850a181a9274244134a0482a76ea53b3fc521abd02b1c01802c70f54e908f31cd6c26dfb412d8e380fa799699d895a51d622a4b88baa5115f291927ead11884457f5c178c97d228b314b5544edc69b504cea928c75fbfaa4a226a4f0298458a79f39e983e9a82948920406471f420780ee	1	\\xe6f4b588ce294350044853eacc4f2a561e909c07d58a8897fd5f995747d41829b167fc1dc86b0852c1b276d561cf2a42dbdd5d34b25a114771238077b28f4a06	1638366959000000	0	11000000
9	\\xc57f3fcfbf2ddd8e874537ad79eb825c0c8cece998e888b6cf7bd8aed755d21691de86020f7c849267d95546d89cd7f164d85656bc3a85e90c1b133cadf76fe9	110	\\x00000001000000017358a38bccdf500856764e3288c5d011efd8dae56f3c6098177930a5a68da804bf5c74dc776ba27970ea8f8cd6eb58c8cc79587d670712ec25bbb26ff3c90723ac76ed61bf668c5643cc50b1e4f5c19855e342c623210fa9d88e273d69b7e55a297fd6f1a12a52ff939dc1848bd8f895d38e1260198ae8af901c55084f1d149d	1	\\x27eac3fb12b3a4e12634e9c82640edb853bd20bb891696202242e8843ba5a1b114537b1b3eb02456b4585143247294f6131e3b25867e7a48e7a25f49750ce007	1638366959000000	0	11000000
10	\\x138e053c58270f0c2b45042f44b2217f974fef6c4e89bbedb9d797a05b542bbc4ca689890bbe8d2c585e994c7b926206e04273a189c2ba136a06ac24c446ab56	110	\\x00000001000000014b652885d17e00f735de7679786ee0d1044aea797e917d5373c58d91d3536c487c9117ac7e0a3ccdf5f3dc069fed958018345b6938830de7be2b788602cb55c5483738237ab4f9b03f41b750320cf56291f88ac2909c08825d9ee5b3febe922c9bc95f2fda23cee0c3d38a10ca8eb74622efbc69fe527b1ddad4643da8951a33	1	\\x4ce5d6245fe8ddc209e221df177b260a117e050788c8f88c34b5047ab2741931304429c5ad31a26e5acaa19d2f7ec59e69d7b06c329c3355067708d960186305	1638366959000000	0	11000000
11	\\x213105126931691da8f4427ab9892bf149042e935ae860ef349c108bc1f328cbfe6f78da56b70ca16c9828051607bc1a82c9106df7cb014c7e61fb903ee3a601	202	\\x00000001000000017108612ada8fcfd900dedafedb7f7e2ccf40d9eb30f313d261ab559fd492732939d89e9ea5007dff425a6599df8f7d68e9fc35db9287875a1757c96133748fbc34eaa65c82995dbe1fa601b12fbc985f4e026344613d387cf0fac263cac4b01a53ffcbc6473408a6f72f8f098703dbd2f132885bb9e0d459a02667c4cfd38559	1	\\x317078bb27be1df002fd5815036ea36ad5d0dcf5cdc01120a73a70ebb4c3209b6dc3f8da2c5c0827b3d0559f3a4fe30a54cf81ce740bb6f6a7ee3fd7d4f6360f	1638366959000000	0	2000000
12	\\xa88b59abfdf2e1a8bb9dbea733618dd7cefa3525d2e825dbb66e019b2e62726849cb669f0948642223fcf1698bba6afa6af773187c0b20071a05a614471a6149	202	\\x000000010000000139586de67f0069910c8378f5caa1873d2a7a0b162ecb24f58894a654087debb9ec328b39b69a480fa36d3f6e2ded2bb3461d90c42f7719510b8a7abd83b7be8b8f72b9979c7e65c01064697cce80802836e92b605a90e7f6b6c4a8f3e8f83f5cb3fd9ecbacf0a061359e65c527b89e67acb5a330edf7ddb5e62caa921ee68bde	1	\\x8fc8942bc26cc608677a97410b88f48b23f104a3829ca0c12d17febce41f9c886fbd1cb46fdfa82c895844fb26ddd02f968285790c02d146a79bc87f53c6290e	1638366959000000	0	2000000
13	\\x3f938dfe207933260dd8204bd3a9c2733beeeea01ec1c0c6cbc66cc875b4434569bd00f987f86234014643603357b4f05b819c775a8ac2c1d70c05650cd2c760	202	\\x000000010000000190531d0de21309b8ff9cf33d68e8fa80fd493b9c32a3092a0c683710a27b06f81c92bd244ddbdf7c862a3d3004aa6f22c2c2fb79778ad26a9309c72808f62e367f4867972b7936f5d874b0dd3d019747ba008c7ede2b65bd9d1182c8bc1551925189ceda5761ccd9fde28262fcc4491441f01479cf08927872662923ae12d665	1	\\x38ab3b2b9d47e0f66f3a693febfd9f04e6ef76a5c194b822b91daeec8560e43680bdf25520e444a5b39e1c4ac3dda6df1442e9ebb5e7a8d16be00918176a3206	1638366959000000	0	2000000
14	\\xd542051717a5a5b2d3613e69ef96b0e2de076817b0c478771473bb0a13df00d72234abe0b0b5827828ba8a8a8a053a51df0e9210d08f2823240613b3cbfdbd4b	202	\\x00000001000000016d33638f822ce5dd29ff699281e31909d51309722306c36d515046e0765de7448a4e337bf68202535f9b5815739506b37903038f8ee5993b34d19629e29a1552ed8a469c1b89138c1ab595231d52437dfef679d3405ccc84cc20c3de73279e2d4211071daa3eb50fa515243522c0beaa885a606b2ccf13391b3716015d73077a	1	\\xe06d0a37cdd4b804961508abe6d900d6c94bd3a91da738ea7010d03d21bd57919a263aba076ea94bdc49aee23b7a83b2f489a47e46dd935f3f30b48d6e83f80a	1638366959000000	0	2000000
15	\\xabf954b0e90151e7cdd96ab2c1829053c86f7a09e436cc76fd5a378a5dd3a6e4a5f66683af56ecf07518474b3ef8ca0b352db0e56a445a946af826420739f4c6	134	\\x00000001000000017a65cb8cb7ed2b4cc13d4718c61bacadf5dee5102d1af073aa2f0610f885e1e736ad63d9a698f685d97f7383d1c2f82ae38fbd4d1bf24a85c2c540bf7eb4859b17e180f2611e7b20deac61331042bdbe7993402073c9108aa34145ecde8d09667c6d0d706700b18b7d7bc5a3892d127d3e0a79afb4fded8c0dfcd5d3b0223e09	1	\\x8e4a711f4ee3c18aad8dca336801f304c116ea0cdf8a9b6cb84eddea2d71d8913219c8883b74c674b6b0f30ca46c8c5c075528ed5ff93fcc95b5d992940a8702	1638366971000000	1	2000000
16	\\x2b5534d87350ebde9146ba2deefed3a032eac6fee8ab3c4220c9a83d0d562ace4d4c5ba82bbac17eaaff540016915ed02a8320ad5c6ccdb60e51b2966508a0b4	110	\\x000000010000000128d0e74c5b51c32776ce8bf2111669dde790a2c7546ff9425baf1f078d4718a7d28e0e65743d99136ccfde35ee49df586095f1048ccb1e34562696e43cb76af580f4cc1cf74d933fc5913d800bf3518311fb78f9ebe9cabf8454668270d57db86f26b609d70820c550e78d1e8885dfbd0107f04c05e932d9793cf1ea7da90647	1	\\x6fe85bec303fc992643307219ec6bfbe22ba76555de9dc5e01473dace24b58641faec2d30a073bfb0df9b13b91b24b4d4c3fd894296c43b1de7b2a3e2416ea07	1638366971000000	0	11000000
17	\\x0fc20f75e8a3c80265371d9af373640693a94b52e8e7a25dc60a830bf970c617ac0bbf28aa3411a9819627c966654431131d804926f28536e03b44263b1ab3b3	110	\\x0000000100000001509a8fda90a578e10d55e97f58330a7fa72d82f5cb13d06d515c0e6e3ef50bff2817647d5eeee975c2fd37f46cf1ad41609c957f9f12f00212a9ac487f3c48969ddc616ebcf686851726bcd27e8dbb43ed38b23d1a3eac211ce78b013c301f54c9a7cb4773adeec965297911669d76bae763bab99b3e4d30ae9049fbdfff28ca	1	\\xe76d782db2f18d2101a1849561ab0e6f6ddebc00e355e9808e3ad0b813c2aaf9223c577414cba2436a44a71ee29ecf35251b7160d47f7c26ce7b92c2b3ad6b0c	1638366971000000	0	11000000
18	\\x58b9d1ea6a522da58cc1cd02b84c08d0d8476748f3c30bd3639285f8f392a7fae1063398ceea57e658a0d591a9c9e1cfa7a3d2013055611c8c3bf3bf81b02f3d	110	\\x00000001000000011ba56b23ceedf44a50bcc3ed2bc6cad4b329881a4debb3ca34593b3c5ba58b75c03f4839c01c9a15499da1393d4a67ce60d64da9ab9bd2ab2432ee1b04a16114c07311fde401ee289027b74d9b9b0980d647117c064c9a8e450b75dbffb37a9f559caca750eca79c4f2e6bb56ba3edc5c8550f6d073fff6e44034e59a2607485	1	\\x7604bc3f98992fc5a687851d5beec482c3657c37c2998459a3c659eada7121c9a6fb8a636a417b3266b3e69e179ab73d8428960a6a0f4b639446d2fc26bff008	1638366971000000	0	11000000
19	\\x11cf36bf76e5a5330fa711e9b472f6f93fe04fd63e0ac70758d0830fd0d1c8df84c94a0484b00b66fc118671a97eca38bc91d4508f3e2fd79160be5f2de5629c	110	\\x0000000100000001393a0db15cd8510d61d9205f3dfad16f6689e9835e44efc117d645f4d48d45b1fbd441ca54fe0c647a951424c7af38d3c4d8d29173960a4d9e08292f43e6b3874ebecf0573c3104b5b8d170a4391d64b44a65cce7da540a112e77a9206e7c07286a4be476bc62e45aac2c34ac4f944cfa360a354a4ad40cb9ecf65c3bea6f1aa	1	\\x51b37540ac730bf411b4cf0a8a56a6ac4acaf9d07d13d24bd11a077b4de9349cb200a073d8519f5a41067fa35cf85540b9e1b595fad6c13ff2fbd12ade1d740c	1638366971000000	0	11000000
20	\\x021bd092ee75ae5b673f51500f64b74a1fa3808523e0e9c096cde6079ee09625355d79e2aed89af0ef132ed1cff50b6132c05f631be1efa9f58a81e3a72b78f7	110	\\x0000000100000001a822d80c487c893e4528ab3748028cabd264c71e8ab05232c1dde0eccbdd172721183b22526e8a073cb83053f7032d2f1ceb3891a81722769945c918a1a04d90402a8d6fb4980e8dcad75d68fe79e53a7ff6531bca39fefa0f1f1f6891b918960c2702e9c1f1b00e4bd00cfa67a7909d6675809e61f5d1811913144464dc9c3c	1	\\x0743f7536e839497efdbb1d39139ad359096bf3e521b2ecffe7688db9e4231b774d08d400824c8bc142b666abd0c548fadc8e5f2cb7c9172987ded5fd0cf7b03	1638366971000000	0	11000000
21	\\x8804fb1f0e5845cf010a72de7c15862bd6f80e7c3f4de3360698a477b95bfea389c42ca41d2536045ad9fa22032643e985149d8c3adf9c85053da1fd091046d3	110	\\x0000000100000001aae5707b49f84f1a69595d3a383d1f9e8e22892c6b321d8548ad3e4276428cb3f32d0c0c0b99699e2387f0a02b8787cf207dbe521407ccf76f1cf70ef08a5ebeffb64b39bbbfb69524d9e905e6766554ad4e9fccef0264a80783bb8315a1a5b86c0f3bedecc629e6ff6e6c27cfd8ee237fc89df3824e271c558d28b80e480c7a	1	\\x610b9bf4849180e4f590ea66693efc6a0e3d60e5a9a242f240f96dc4fdc2198c0da89ab1efb8bf6a0be9d3525ff8e42e9d5c8c95317ff0cf16e79c50c0844205	1638366971000000	0	11000000
22	\\xf02b8bf8798f8164145f66cb7c7650a6320446ca9cf4816c33dea70449117346be81ff937d85e640a3f5f956f35289dee86f35ad0b608ff062c4f23474cad11b	110	\\x00000001000000014c86d79448fa4c2c331aad1e5698d0eedf4358f9d234dabda7a72a9cf2ceb92eb5f08476ce117effdda7222ba0ecb5194522073802a2a023dad47604ba610d5bd0aba9fadf31e98900afc313530a071352c6d5dce5dfd6ea13df11e60ac20b4732b3e93e521039fecf23f145e036bb278ed321fd86807bc7aa28f74b6de58f8f	1	\\xbe0761cd374628d8430e2c5414f473ec725087fb1c3fddf30ac38a7da1cb75c679fce669ec56a31307533e2061f95df8da929f9b99be937dda0965118534040a	1638366971000000	0	11000000
23	\\x5951a7b5587004fcb84f13f5db6217333aa0528aa911e1a7be8f60cb5ea7b26938ba83e7d786d837ce461b634a62fbb17747c065677ee093676c32398fc2de9f	110	\\x00000001000000014d1f8afff8d3d310b91cc2d1f99ab93de096f1dbdc682d02a8cfe31b2a266bbbf75801d916e8cb43538630c0742561784e0d702937d9c697c668ffc5d856796bc512de4fb86eab36d6d67ab9ea405f5dbf4360a007ec6d95c4c347438605da25e77731eb7e185612bc6b66cbfb0d37b5d8019bf5d145281dfa8c88b5e0de3739	1	\\xe978b5c3e6260ca7943bee0699fa539e9456cf334ead14296dc5f27fbda39f716aaef987007d0b7a47bba29525d5ab7a5e1d1ffae700e5ef28fe0919e0d01409	1638366971000000	0	11000000
24	\\x95ec71021ffbd83b7392fdc1d9f45876fd811f8a212e9a36c96b3efb802e02ff11bced7adab5a219c0cdc724718915d80a3bfc2804aa5f41b0864f838286f06c	202	\\x0000000100000001a6b740dfb9ec35a0ded3ce5837c0c8b18f1883d0d3f300396701b46e6dfb16592d0a633d5a0972e758825f7102ebcf4833efea8469328fc8855d2e4fc29c323b26fd16eeb3e0597e28e1c0bc3802d793c49a16dc7d06e77870121e039fe40b3ef3f410bb15ebb37d114a626f73cbb7023f3518535518dfbdf8f1370b54757d99	1	\\xcd1dcebdf90fb78447d8227fcaa9b1f1fab9dbb582b5fc4329f366adff209f5eb183bcb3311c1045ad5b01aaa4b13f3f500b895c0ea9cb9b9a87f55a15caae06	1638366971000000	0	2000000
25	\\x23dd245d1fc428ed1c30fe433bdab2090b6c343ce168fe078ddcd95804bfa341d11a45d1e1d9854fe2dcf9488b488f3562388bf6e293d515aa25597181603403	202	\\x00000001000000019d1d82faa5548980b9b6c49707cb7d7a365d1dabd8bf07fd01736406f629175acb4377dcd255193ed190664d7af13ae0171b3bf4531b45dee8a0f6c30ee2cdf8891076ddf486e3c460b3d2427f698ac15173a680337a60664db900e1ae992e3169d224efcd848f259b1c6ed63420cc87c19bde968f6d0b0e1329129bfc329ec6	1	\\x685f7065b2a04ddd30616c3ded92227dfdabcd5eb0371295e840e435b945ff41f67797827157338f1b5d944eda4e854f32e867e8fc907c35621230e73d4df90e	1638366971000000	0	2000000
26	\\xc242c224c89b04462540e5924c10d5f97b7db5758019da6b4ca7f1fa9e26ad0c1aa4153cb268ab1d6c3335075dbe10083f55af0e492f31287d5fa926ef47e116	202	\\x0000000100000001581512563b077b27184e234d8521c32f7cbe29042acdf9441a067683c2f866d13c185250603b9fffb77d626b59c22e178caf4098b95bbe39a766583670471f074f828dce728f2d2e10019b257542d092b68a24f957eeb66c37e2398a86ca648a2cf192149e25b8b3031ea0825a7a5f942e01b0ef65453759332e36221fa69682	1	\\x8e54e434df7e64b560e5cea86577b18af451d313148d98fbd2c991052e179f6ab15b01b0fc1502f921c5687f12bdaa2b6adf18f1f53dd224af46b2276afeaa0f	1638366971000000	0	2000000
27	\\xf8e710ce0b7bf9f7507865d7a02ddd101193364996beec1c8aa66f13dd247b2f146b7e1a73a1838590d68ed76e7099facfe67da8a3c72d4d642375bd07cb70a2	202	\\x000000010000000112fbb17e02b5285d2a923b8611d978149057e5f5685da913a833a6a4fa7d0380592a235c591d06403598bc18bdec83265410a9c5438743de76c10bad108acffaf67c4ee124b5c747358452c61b823aec494fd5c7ae3ab1e786f6c03c4707c5ad5b9a5541499cff50b0fa4a78138b6d4b9ef4298c0b050889f0326bcde6cd905c	1	\\x424adfc0ad9de5105c044bbbd0c4b83be87cbd0e551e34219aa86786e0ad03cb7132296bca9d0d5b8b8eb820e05d9ab6ed41e17248634569f31919d5e0b5ef05	1638366972000000	0	2000000
28	\\x8233331d8043891d5f7b6b454c4ca3a764bc9062b6251b59ca7d4a3843b999c2a3eb59b402ca498de4e22f6cc20464c8c6cf1ee40e7ce7daa0aba3adc7adc4ab	202	\\x000000010000000126406531aa8650cc26e478aa1f0ee61a8a65aacf01edc49fd6ef4561764f9deb0d60d135e01197ff0a232797217afbf125ae40cbf9704e1d806f5367c5ea036def7724698a00fb7b87f3fb2220d53449cce45dcdd871475f91ee6706d06e48b5962dcda5657df2f8dc58ac35ca32e3772a84c8185fd5f70b02c6e21fbd28105b	1	\\xa001577ce6b17eb1733bdfe3979c3c13e402381196b1653e3a2ae37132b3bae03c1c18f8581bafb312ecb1a8c87487887ecc0685bc49e80660679c8a70965c0d	1638366972000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x8a64f036b08e0efab21b86a7ad11ad43f86147ff2ef2344c6520793123b475e76e1f069414986ab7f00c24125732268c497e8514a9b23f962502afc286835c07	t	1638366947000000
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
1	x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x403ddcb1ac9ae4bca73e915a1c1ef3d901b0c2a0aa4dcdfdad12276f18cc5d438c4e64057b4e11c76f8d05a3b5d6dc56fed992e05f0d76c06e892680b9458408
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
1	\\xb40379f80360623e82237e306f5b52ef69a0a887a079ae54290b186f50b433109618d2eaeaf295659a376375cd6c1c2f95224954146495875dfc61e077f6b3b9	payto://x-taler-bank/localhost/testuser-kusufpjk	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660cb3a8ffd7e9e69c646815045edc179e5e7ea1ecd9584550d202ae951ebd572e98	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1638366941158878	0	1024	f	wirewatch-exchange-account-1
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

SELECT pg_catalog.setval('public.auth_user_id_seq', 12, true);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 2, true);


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

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 2, true);


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

