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
exchange-0001	2021-12-01 12:17:34.72529+01	dold	{}	{}
merchant-0001	2021-12-01 12:17:35.428355+01	dold	{}	{}
merchant-0002	2021-12-01 12:17:35.931792+01	dold	{}	{}
merchant-0003	2021-12-01 12:17:35.959596+01	dold	{}	{}
auditor-0001	2021-12-01 12:17:36.003155+01	dold	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-12-01 12:17:46.286512+01	f	5a70957a-672a-43ed-bce0-a791bbe044a5	12	1
2	TESTKUDOS:8	T2Q0Q7AWCDCM2F8PP2CTSHM82YA009D5V68WXCA5YY7Z29HB0460	2021-12-01 12:17:50.437225+01	f	c576882d-4d19-42c1-9ed9-ba5eca2d07a5	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
20a7bdb3-eccc-4cd9-8ea5-df404d75b417	TESTKUDOS:8	t	t	f	T2Q0Q7AWCDCM2F8PP2CTSHM82YA009D5V68WXCA5YY7Z29HB0460	2	12
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
1	1	58	\\x042eadf6b4dcaa99966e5fea7e8910cc708f49b64ef53c2c863c461d402a82a14bab73731ed88c415891c8cbe11f0addf8fa201d934ffe5895bcbdc43ca0d601
2	1	176	\\x8caf24e1e2c40ab4f8b2814493257846e589bc459cc2a6551b40d73b2efdf954c81972a9024387fc1e21dba7dfcc46d5bd57ae8af4ed8ba39f18111aa2020705
3	1	360	\\xe76ebae8e080bd5250fd166d2034ff6ef6d671ce8c88971c667493c087980ef13c8618832fe8e63eec81695a54593e757e54e48e71f027b3413c3e879a701b03
4	1	375	\\xb496d415c7b7545608a53d59e7a6672c71458c573ce0a3531bb4ca7fe540a6ec3f00406e3f85d39c4fe053688bf4ea2bc86600258f4e681fa5f73dde475aaa02
5	1	83	\\x60f8682243db327672c79a6130363db9948dac8f89eaf04c310567479139012370ebb325794b5a341dded07d1915f483597d301623db43e91729ac3e2197600a
6	1	146	\\x00766921552b21adf3113f68e6ff743b44e2fc3fc802c44b38bea8dee4422ab251dbe7cd1fcde9f7c3ae2b13764e2fd2311e80974411866e6bcb12cc5cdb750b
7	1	374	\\xfffa59ee77a5c24cb087e076d380adc982c7e7cab3e950196d19319f8ca73c42b979daf5baba29601d631c6c4058aceb397de71a59f4457521680e0152614902
8	1	107	\\x05e6ae64fddd3f4ff731b54ec2019fd2a9fd29b00d9843d6a134c1fff57bf21563b251d6b786c1474d9bd5418151ebf52cc622841afbeb76562ebc19c183780c
9	1	94	\\x8077f6c3a23b764cdd7344d5dff8ddf622f152d3c22783e20c03f88b55ab678879a5d6dfa1b34a6aa1a3bae4c1ec7296e9019d6239d40b7a3bd14a307266210c
10	1	114	\\x6ac7741d92ecb87b7ed2870b6364226ec5edaa3a80ce3f8ca1a265dc838abd35a74309c87f3a5107d357bf61624409110da35a9146c319caf1b2babd7fcfb30c
11	1	424	\\x595921283caaf515b3623700c0329da3bb7230fea5730759034bc3ade7763738c57c0e16f18e18050c036f44243a3f96013b866c15dc16784d40dc20f5ee4702
12	1	64	\\xca10e051d5ca12ec77645f08eb717cce135944da73a45c2280b8b0c09e8dd40d4f73a2485acc64c8b92d4e304f0ad7d5b1d7a043de71f7eb95ef16879c4e780e
13	1	9	\\x29ba767817f8cdef36f1341cd643ec38d12268f15a65d5538009dd32b1a16e799d047748fbd231c0f296c09d23ea96e148dfcceb664d19eb3255853007387504
14	1	258	\\x7dc418072666b7f746f848d123c30d1f07edc3ff1c179358629610e929022529e89c2b0993dcda8a6b4e796b150cbf4083ab6a302d43f47b0e6c7e1bb84ad707
15	1	227	\\xd3d3689b5f9efe5972e3e04ccedf868e91ff8ff68ab3118a6125cb81ac28eb1c8dfc52393e02d590aa5ed1cb225be625104435fa8b49281a7cc0eb94be19fc0f
16	1	14	\\x255a937bab0aa11f74cfe12b542639b24c3237a9cf60d17eb0a69f658db5c7decec859149de8f7bef9cfa75de9af3650841dc3e6f0518947d15009366cb20b0d
17	1	191	\\xc504028d0b1deb0dcebe297ca094bc675324b46dda35d0ff97cad905bfd16ee502f4e8ad3ebde82a339e9e80bff05dd6d601362b1c887504fe47c77778c94f06
18	1	319	\\x8d8ed31bf89d997e1f8cb5eb2cdb87b67551b24929219a7b59da767830d48345984a6eb6445ad4475243e95d2d620738030debebed34b731cbcc15b2cc538908
19	1	211	\\xeb5a3802c071b9885b6b1430bf2c8e610eb79fb53b0cfb00f68368ff28ff9ede0154feffe41f05931980bc726b138c22b862525e453394a0df05cfdd73ecba0a
20	1	329	\\x6f6022b7ae5fff4b78e129b7ed6819c3fe59f0e4c5b5d5707fdf06755e6cf0d2eaee50f7b2095414319c6867e5fcadba6efa583bd7a611775e556807d93d2507
21	1	289	\\xdc4d89cc2eac49f038a9888ded2f992103a7f0ac3bb42fbf61842a3e079157f28b803c71339fcf04939ec15c692a120274133e7a5d4497d43452e8872cb91f02
22	1	53	\\x6cbf682b455047d5423cfd6d7537f94d7583174743ff6e441077cf5506f5db607d770118ad3173a7ef67444f8ca7a423d1e42ea51876d4cf4de08b3f9433170d
23	1	124	\\x6b58f036837723f5f0615e0b8899e95365ca5b7642d3611b5766fce1214fb070127d442521da5abdd830e69580c2c98bfab7eb8982f17d248b12340a3ca29b0a
24	1	131	\\x8757d50b766f02f7ac35a502ec74a5028fefded88e55c7eed24270b8152f8c56e9b4bed302795f1a25a6946171fa4666f4d92acb33d700e9eb0e9722c430f107
25	1	345	\\x6c5e25a6cba36ac82a5ed17782e9c03633a7332e53fb11cf7ec71e3b1ab5864c88a7d7212825778cdda86685f84f14d99add73b8bf09025012610153f82e4805
26	1	252	\\xe1b7acc23df885daf6eee094b7a0c50a9d3b75e27ea388ef841ee5243f44ffac333e434dc81b7146aca80c80cbf8dab466560e4405c89202f5d5352092f0940b
27	1	31	\\xb773503fecde3708e8822a1f998ae01b56efa26c7cfc4e2af8904e0eb882e39f4cb2934ba8a33c9879210a2ccb3a637dbd384a1581fe31b19b7bb130d181fb04
28	1	193	\\xf479dc0e0e945246c8a523a8d641f8af1b717549a5e249d197a834e4f17d133873be7d00e7bd7604c4738151a51a5112a5424636962bbf63d032b32663511802
29	1	204	\\xc6d7b8827559f7600640e2688bfd5a004b4ac8f2a5c95c1c6e86027f5f6230c476ff6317058d946effad28b060b19e2fce89950c296e1d037ee27110a8b3810b
30	1	207	\\xcf84a51f877f841fba182222f6ebdbc7ddc5bb5aa914a65ce477b0cea01c0eaaf9b5b145cf96b4df9db30f65bc9a8dedf5209c238e949d125b64ca56e98df201
31	1	46	\\x0f91d8c21205c7d8bb72c999039a2c1f2d160551f2cda026e365c8290c59897a6c918ff00bf0fc5b6617a2610f37c93a1361b79b0a4fb6d4ecbcd88f2bab130b
32	1	250	\\x7ab4acc112e6264f75962e2015d982381c43c146dfb84e9cc3221e132830cf70178e28c57ab27899bc2adff3a256ab30c98335d256e85a1cd476c08da0cb8c0a
33	1	356	\\x4cee69cb40415486f86043df4a2899c043c4983b006f87b72984294cc17f1ee8a5b86e96d9f684731c5cc55978a545b2582904d40f62cb44883fcdb1e44e150c
34	1	347	\\x63b8f313d0011c7d365401bc00fcedf450b0ebdcc34b82f7de818a8415863e69c3f55352eaa4abb95a49a424f19be08b21c5fba283e1e929702c4aa2930c460e
35	1	129	\\x83fe11900db3fc884a5f8e0f6bb8dc95d5ae25e4585f505284ae776316605948d7153029998668b99cf1c9f3b23b693f93385a68f959e3cb067622a6297c680c
36	1	275	\\x0e1e454a03425608db6b617340ceb907306c86734144ba39b7391fcbfc290d7053b51b4ba253fd60b2660823d2eb3a427b7015ccbf9d22b9a180c6ca0650b30f
37	1	142	\\x71b407a092d89369b79f00894ffee2d66c22dc28052add88a49c05efe4a39440f911dea5840da473f0067aba81dc3d8b4ab18a76460e9c2a5319efa6e8d21a0a
38	1	285	\\x871d7186822eaf30fb5b6e13bdd66c51ea3d966d13bc4b314cb39f29458f1e0fece86f722821736b2bc68d2fb30c261b33a7793af98b95a612d71064766e030e
39	1	132	\\x594e0c506b0b5a221e43daf6b5e04efcd9b6302ad6ea04f7892221a76c6e5934926b080edba78a3a16ca35138f4680d5bdf2a08a8c502b030727b64e6211130a
40	1	376	\\x98f340efef598860c732256f03cc4d7257e1eafeb45987f5171b444c3161489228b50d8ac650344670c1a55e3e0cebadd23823fc2829995bcb4e72b6352c0f02
41	1	92	\\x6d3a7628d34cd58f476cd08b8ae13e544ea9f7f8ae20fa498f7287ed6e8f3b41a36cfa194311ba721cfe8b483c820c4f4009eb77e9f2ee39b482f27659f8c30b
42	1	57	\\x538ec35f84e6859e4880593c43c463cf3cf831b792f07175ef79bbe87c392df321c672b6805d1414db4f4b96bb8b5513c901acbeda82b5c49aa97d11376ca803
43	1	272	\\x321d873a1ffee208b4876f051543c5f36b849fa5f1f082fb50233dde2362ea8bc24a54e52edb97a7974ff9a6caf1285de47d4d7f94166491c414c52918320800
44	1	213	\\xc3fe347e7690b8687ad59c7e1e729ccdf53a316e4da710c4d4467e174da9924891563dfca26fe555e07f51a497d58f1f922607f33ab2b4df8bff6a028759b30e
45	1	113	\\x66522fb5686a6e13329f809674d3298420d7fb9c69d398a860df66bdcaa8d9463849394a01b5d7c679df778bbb1581859a67b2a519cec928b4ad6160b9252600
46	1	228	\\xcdb713196012ff54123de4aeab8cd31b0b74d386088e27401b0aae6a3448f95edd79580128ee181600767deb0f03172e1cd61f4f9e7d8d652bf485438d9d2806
47	1	178	\\x5ff23704bfd92227f72fab921cef4fb92fe00db1147d9b06de6d45c25734cfef0763107c103e8723156c5feca5a6c80c80b311142cf7afa9fc7506c800352304
48	1	234	\\x8fd4a32b1bbbf0bcc0e8edd44df23d32722ecbcf45c0fe043c69074e736636de1712774acc02c8dc024c47a01574d34e2ed3c3a6f7376f0532483b7f95eb8400
49	1	310	\\x380484640a526f4a38e859abb406c0992868106c587ce2b6e3af209df9c0b8cc6b0a3d2b15d0e5e7e5eed4e3f36d4a68b610b3f6b5330d8c56e38f019f946805
50	1	17	\\xfa970e81afc2195e4d6d8634c3939abf9f4787b1494fe79db32f853c7b57aea3fc1ddeaf05a21a3e700ded0910c65983b569ea489a6fcf0a9448a8e9a411fd09
51	1	335	\\x6821d258849fcff55340586df98a00e33a7873669e6174cea9f562558ff4ad47101315bfb4d3a56b399415b8e8e6dab6549bece04878f777d7b7ffb7281c0106
52	1	361	\\xd6cc0aa702571739ffc337ee616ab2f010075bae242f8ddc62017423d8d1ab4337d7ed16853b0408c7355edc341695839e040c4bc0484f48581f32302840700f
53	1	18	\\xbaa2f70a512c43e0a167734011c4e3c9ed2560bf3d91f53e21336392feaece97808487add82aac19c159a356be9f01296d38806cb28f7fbaf01d7e630a27a006
54	1	96	\\xb33a06ade536bfd11f68cdcb3a7f60ce7a850707e7734c537eb9677a596007d98a47c8c6a1cded6c4bbf7e04236613dc90b1e4a12300190e3d53b27373155806
55	1	391	\\x221bfcbe3adf8a68dedd6e4ab67459fea001b615a685842d93f5d043c65c187ac42ed0946addb78a02da9559f119006d1579a204ec11c6344962a2211ffd210e
56	1	358	\\xb5ba1b7a707c72786454528a9de955856767763845e69e3dfa3c8a6ff318448292835be2664bc7300dc97e074d7b719177c4db2ad5f19f7a328786de41390300
57	1	418	\\xaa67b1c643c1103bd20467a4e4f2e4fbc299fc59d965936e4f691774df6c1140695abff4595eb3ee84cf39b97b372476f6708e3e9a964e812a5086f35743ef03
58	1	97	\\x1576ddea622170ca524e821c6488e388fe811d560cdc615935e2fe543de1cdc204e47514d182f4df881cda30cac4d6d29c9bc6a003ff8b8ef391de09fbf65f04
59	1	71	\\x8d0f63ea60306b4afb225e1b0087a9e602ee4405e2d2da023523ed2c04d6176013febcac4700e27a18de6616bd85329da2f0780e38ce964e1a4e4e13fa1d5405
60	1	225	\\x5ee2edb336092023c9f4d87d646f2873ab6a3b956e95d67452f99a6a7c8fd79c449e5ba7a93f6f2332572d50bc15f45a37845c508fe49a023f64a83f6f1d180f
61	1	230	\\x47c96020a0cd09f6ee0174fbe34502e8b195eabb25591213b1ccadce16319bfa7e5b1ff4999f5704165844d5097b96fed54f0b5a2f74214e064d86b90293b501
62	1	394	\\x6920f437fb171e99803ee7e4bebabab6d425b5b5a3f94666af84b6e38b5377498e6e530fd94541403f27302ad9520a75bcce0fbcf62428f4090d62deedf13502
63	1	194	\\x848cd30620e2d93d214ab0aa53aef4138238a3e306dc8eb7f0ee06fe7ba6fde928cc19844308952bb694fa80fd056263fdc699392aaa1af5645e67894aec8407
64	1	118	\\x0d57c046872a2c856b124951b4fc397e17b7fe6854a2da352bf7f597a8799d680a974b7569979ae00bbb72bbe272313708a3eb314b5db07025b1e4d9abd61e00
65	1	233	\\x89f03b8b066dadae21b99feeff3b09081d8fa45709385cc45ffe695867e9ab1bd1141052a235c21e5c77438cda07be8017f4970296d795cad16e662d0fd06300
66	1	383	\\x6ec5a4fb3a937ce6cdac6aec06494e400aa3a31780253104c5192c1c32c52077be5d7ac3e4c41841504a572d44d8a036cd9f51236251a94f5f9f995b20d0ad09
67	1	277	\\xb19e4ed500a2947ce43e2322f7464c21c9a1a303fa152ebd3ebe2d8751d0bbe51a4e3ba911a985e1b9652473009ec953d0502ec80fbf9f30b171b97952b0ec0a
68	1	291	\\xaeae11715ace2eef17996884ee4b42371edf411e84b4e83aa25570c83f68c6508533ad1c22d8be4f2f8313f3a7f03f99ed4bdf410cbe18debbddb685919cdc0f
69	1	396	\\xbf1a68906d18e7d26fa3665b8b04fc2becbbf55076173f5f62154fa0900d384e40d78c493a4b3ae54b80cd0943104571274ef3b848ed8d0802543b8088858c06
70	1	395	\\x1febacee931e922a8af64860970985fb4d63364d26bf8948c87bd047f1e81e4d07981129b183d124cf2f26d0032ab5d1632ca7cf28acb8faabe7d0f92891a804
71	1	379	\\x659ee72e488f77a32e36e743d67e29b059db98c3f061bcc622e49b872cbefaeb5724d9ef78185b51408635dbaa24e2b659f461e84a63a4f2011293c7e35b8d08
72	1	423	\\x51edbc32863a6b4d99b321df028ad6443e93fac625a5256d9bb142faa9af60fc5de32cf4badb3a57ad6787dd04fec7e389500ac5d9888850aeec19af8678fa04
73	1	170	\\x7a4bc102c75fcc0be38222700dceab96c9a660cc1de970962320ee6639cd7029282120cb980af937478430ee7bcd2bf2bab2c128fd816c939c2681d1f133550a
74	1	202	\\xfed7ea5e5b96e67ba7ac62f008b26910f537fb1af94c794e86902ec6ed575741ae6adf1b3ddec80756df1a713e609b71eef767453f7f2e6019fe95e5cb88660c
75	1	210	\\x7387a079663379bcf27019b59641dfcddaf26834beeb1a4fa6124fae955f7edf89443ae9b12cb9026bcdf4cf7a6041f8e167bac3c657500cd3f0776b22266c05
76	1	7	\\xfe8f7bb6c3e088c970df4fca69f6f0c1e1a12cd60903e664ee2fee47b6cf6bbc7864c5bcb063935341fe95264382c5894bd8702cac0e3d7c8ea726b71f31a30c
77	1	300	\\x7b545aa6c93007f5fb866e1b994405de261c5b672983a47da7b99830e3602d800ea30ee9296a130638c03edf10a0d175128cb3107c531facc69277001599130f
78	1	321	\\x98930f7c07119a3945f4fc753de55173832bb223e900778cef98a7205858c6a2ec78767502a7e6b1821e72cb3214f54f2dddc7ee7b3f8ea8708d94472f9ea00a
79	1	309	\\x4acda67559ed8077d17ad5cba340367f623b9761dd738f92d9628a045706c5905ac2b0b99f3a6385d6f561916c6e2d822221dc4d83466cd8eae8fd8babe7a40c
80	1	152	\\x286af1d18bed674a448c051773f90aca0f7423efa036679c0825c26fe426598ce0d4e2ee1774eee3e85c033a2b043b74586b7e3ed0d11b5a9086ccfea0f68903
81	1	143	\\xcaa896cd5fa60386666cf9cea92ed2e47fadda0583bb8e713841df0f37d12f5a676a5015a207170eee960c5e7d219aa77e7925f9d55454c81ab4ccd874ee3707
82	1	337	\\x40633acbcd28acaa7b2eb8c92ba64fefeff0c27d5fd13a327d25391f100daa0bd8f5ca7a60aec8ac602a542d8df6ae79b56f0b6a6acef58f9163b36858dbe90f
83	1	188	\\x928b3cea20c3068b6334cbe5c483b9515cabd523ea21a4b7b49cc9dd0431070ee3bb962296171ccde49507d5058c2d56c7187f89fd0affef96426da59632050c
84	1	160	\\x033677c5eb1d51120a774d87986f138234bfb18a007d654a867a35544186ffdd7b2b102d10f6a8d84eadc1069ea9cf5c199d836fe7bc6e932047ec0d9b64f803
85	1	231	\\x850a52125e20aef2f9b7a01fc2ffb43f3b288383e9d7945278f2d19b135bbdbf4f65b26591bf6983b9d7d7e205796f8bf9e47aa763052fe5ca33a77885f20a0a
86	1	52	\\x380ac2cb69d20f21dccac606f034799f381fb32fe412be5f64887297e9ba262784d229c29551b853f8ac36cd6c60c6ee5821eebb51fe82cb5c9220e40869e209
87	1	161	\\xb756e71a1b2f8c1c4553860de7db9208a350073addb8d31d31f3822af85ec01eefd2a8be17539282302d18254bf46881e93d85a38fc528b2b4ea2c6682d8e906
88	1	203	\\x62c83d61533804b5d3d137ecda58115ae83bba64a41676da47f816a255bd02b451515947436281b9adae9900921b6749dcd98743345da3e7a9314487b1a3b301
89	1	199	\\x447bc11f2c8ed2b5018691175ffd920d06b86fa19fb210a5aa581302507e0dbfa4394f0f21a971a8e2cb77338ad1e476ba8ad34585233d72f688b05ca22c8e02
90	1	25	\\xfc62b44a64d3b4f0b1aaf002e214407ff8d91db85f41b3d51a17ea77d5e4574771fb7cd52454e803e2dcfb4dace9106d1d556360428a1d956a03d299c88a6600
91	1	246	\\xb7c7edfb82f32734f438593e709d41d4d96e55c583a19e77f4ca606395f0281a258375b159f400d6e0fd84833c14fecf9fcc3f70c0ffe234062117c41ef40507
92	1	126	\\x4d740df84c1e860d97d44342ea469f1fd42c1c11b3a7dc189e2b4afd246a55bfe0dab08e4bd60f872eaa14564657b43540a8193ae0b4cadffc4bb38d48482b09
93	1	232	\\xdce597e8dae605165b4a71c426d161a38ac219babb2e3e32cb457d44564c3a332989e02e07acaf36c2acda24b5df9eaa764376fd8cddf8b782442fa46a93770c
94	1	373	\\xe4f4969b12c6b187e5451c01aa8a6a5572c1c5f6e8e5fb09f309f9022a869d2262b93d1628ec1c695d25ae8155d201599fc181a314ba915682dafbf68148aa02
95	1	12	\\xfefc4eb88c7bfd030d9f4281fac6229e943f4e71f6a49edf30583221451ac2c5262cf268cb9f1e2afea735de8359c143da2cc54499e5a72ab7031df1d1405504
96	1	125	\\x3817f1a9239e193e53bff6664e7df8fadbbbb0cdd7c32a0510d847c13515e2fe109c0ba62cf8ca0a875ca8c6aeb79985e61754e3f99a69edc148d353c72cb306
97	1	26	\\x3e6275cc79d0c1bc25496e748edee78a50116832bb7822c2a96071dba280854482b6b4967bb4c2f964a690a2bce4de00717a16b1e4921efbc32c5ec462dcb708
98	1	237	\\x9c2469ea1128cc50aee7162d5c1cc5229e2b7410cc12a7e398dd4ec265a858af10f94a39bc492f61846fbd80b1575f2d35f5f8cbe334a0a729af82f3088fec07
99	1	4	\\x38a172553e472bf54b607c0641ac4d3dcbe29f922ac9417b2a1be6adea2a5d53558b05b5d980d25e539e324810d7286d5c6cd0331e09baaf03873f5312d5eb0e
100	1	351	\\xb6da9908527b727e224c3d3539c1da27f4f895cc345a23291b6012d77046e3c31c94b3dcc9a6c32f9000e8259249715426e430fb2ce673d5a8d5c2258f801f09
101	1	139	\\x9775540d4b74f3fa47df56ee36db8538b9eed9b48ea37dc677a6b8909dac57c5c69278f6361c425f51c66550c066c1531e3e9c70dacce39f2421df754a806303
102	1	48	\\xc51272de5d51ec18e9038cb85b737749d455128ebd4c558f096a05be82adedc2a066993cb73b1807894a0c4c131c6c93e5a7f0d370380097d2fa3dca59689b06
103	1	164	\\xe1088ca5148190b4e954da16569f85b1f7df9a0e34a473f7986b75abf78d8a9bd410827b7b548530bd3597ed4c2346c4a5d693f931c352d6154ed15c0a0e4d01
104	1	21	\\xafcaee222908291bd11ea680edc64e4e0de90f569db8d710ec0f34e06f7945946cba1aa3ce521e6e7cbf0b19d689abb907a21464e0d5d356e337a7cd8e7de00d
105	1	400	\\x74286354408cbb353a638fedaaaf7d897d055ca386cbb117d465b2c4b0ba498f1e4accd270f6df733ac0f200cbacb63d1cf99083f90d031c4fdcdffdfb32a50a
106	1	308	\\xc66acc0397db3218eedb1e848a69a80e5f3bb8cb1a9402b4c139715e755cd9018928da767ae149d39b958b9761dd9174c92af2c1a792ca1bab3909059131cf0a
107	1	98	\\x5a497444e4af4a6550423e2d16d88e6fc045adfd8e284d8182c2d4d0cd09b77eff3fb31429c1b771df038ba15db028e4dad3638567c754d98b9ccfef2bf03a0a
108	1	106	\\x319bf9951a53493736ab268e377011b4f07906852c6d63d4c72a0402d7fb016c06a4001cafa957a21e366b1b04de9f6ab7921776af6fc29bd58d537a9d020806
109	1	208	\\x8bc83ac129c0be1f9b7e9ea77c0b96d97397c0cce8e976d4b9d28436edcb2d8ad4baa5a0360b5eaf1b1a262bac10e7b515daea8c5c52996664b0ad88bb909b0a
110	1	67	\\x236b08e76d5bfbf2685aa855aa9e2d8c40d5086c9b86bb8fa9529909fe1f6ba714196d7e48aec567465d5a4cbfcd79de7f53218cb94ed9cf8fc0d1ac73771108
111	1	372	\\x8afbca9343ee71efb470c5abccacf65c5ae903b76e4c7ba623b0b49d1d200aa6cae76a333b9d8efbb881c5f9caba14a982d053c634661a89d665b52a459bfe04
112	1	221	\\x393447f7eb20f92dfb962047f5944a4e5c2ebc56ea66a7a142a56228e8abd5630e2dfaf09321e8f9c90efce08c8266da521a871e5841fcea7bf2d1da4266d70b
113	1	296	\\xce915d59eaf8326ee86c21fbddc364c347ee86ed5efd895d5f802fb00942fb05f9eb2345fb2eb150691d01cd8aa371bc326630b6713b2423cc622f8430f0fa0e
114	1	30	\\x8a931174c08143d0a49c2fd24c7f8243ed83c1eb210cbf6fb1e4d46826978e8ce77d83f32b1f3389322d560401fb24b416c6273e29f416a546888458072f690b
115	1	38	\\x1b1fefe4dc07d46697f054e1d4a297f049c07bf25f79626a7793f4932dee59b09d551553c42a62a995d917b0a5fab16946bcf78ba73b2486b8a7dc3acefaf80f
116	1	408	\\x36ee15a8077e48070f5347d48fe088305df3c5d9d86d1d636406b2fe03a3581b2221c4625212027eccde730cb11d1b5a64e986940eac3cba26e6a240b6915505
117	1	22	\\x5f0017c0a08003bb37ecbc19d427c7d81dd444d445fe155d2fd89c28632a178d392a097ca43146d0c0b8b9cc82c37927724d3d6a73eee74d6500b1ba16c5c608
118	1	145	\\xcee81426278a91a63886e1d0051ec1b694ba6615489d54971e68032e96df23680649dcd7b13b7b94d9a244a844ee254d14fd3bda1923344fbe74a5749bf0ba0e
119	1	75	\\x41918d6f2bec847ca4c58f4a55a82fbc7972f81d8ac2a7e0ac0a0dba842637e7e58baffbefbebe32f5c6670cac10d4653a0732a9a0a85cbd9f01f792f7a00c0a
120	1	42	\\x2b29919c82987909e7ce0842bfa712d54d6c0881f6afd4f650959273aed583573bfcfc17986830d5d5ea4864eeaed0986d2f51bf9c6673f7d1f74825feb8dc09
121	1	47	\\x902ef54cf2596d5920b34eb1bfdb03fbb1f3b41afffbb143c5a73413afb2b5bb8a2a8703a164369e7f9edb24d0882f2b79b8f06419afce50d2134dfd43151a0c
122	1	27	\\x1642a1f0aff56ccdb3106b0ffa1722b9425d10338eff3b31e38cf502c470e978b600afcc5abd73c146e651e748cbbb99671882762acd9ac4088f825fa7ab6c0a
123	1	121	\\x2bd2552adb8b857596c647ac4e0b421ec25540ea879ae03545f4d81623e9a3fad1e74a5947c4374292528b65f201b23a7a108dc88bea6c5a78d046061cfd330c
124	1	330	\\x8ddcadbedb2d74855aeec42c1fab847199330aaede971990626a57c280f05e5b52ae37c692e90daaa0368cab827dcee59a85c530361daa0ec804b885cde4f006
125	1	109	\\x241dbac582fffcd203187464efa573a36066f82f70da25de200b4343fdc3dcd858d42e507f63a9765a4ed6a65d33d606f245983df96b1ab21d5bf09bfad84705
126	1	311	\\x1f10122c4eb6d27b450c37da0dd013f4ceedd080fb0585e44cd0d866acae4e5ce266c03109018c89e1fb7559179ca5069767407cca196409c3de95135f205407
127	1	95	\\x4ce227e407bfa774c2253ada1d30c6422d430550ed1c5594bc69dbd09f0cbef11f6d96c93832c8e02de3ffe4b5f081ef904c70522f3925c841c1743927b08c04
128	1	218	\\xd739131ca91d4ef9f0f9d3326c5c3cec1456debf84fbc9106e4130ac383395920afc10b5c5796d83a58f4b1574069d35d90a952eee815ebf73e4f53570a6260e
129	1	34	\\xd4c6fde9a44af5b19d4e28734e39b0ca772e7b3b951bccd5750daab905e3090c0f17ca1eefcacb3e160338eb5ecdccb94c0781a5734f798df23bf6ed75de8601
130	1	88	\\x5629cd0e2d394e88cf37130a18f053f20d1644f37239b10e40bb3328c0bab5f26aaf97181c06039c0644bc2aa5beee209b4d0eebcb2f2b15c490debf8cdfae0c
131	1	219	\\xe69164f471f5578472a16c7fe60f0184a195e79aaa4bf8ac2955f84ba851a6ad1afdc3ffd5af0bc3a563e2b4d2172bb49c59d4f25add7cad3329ecb626f9aa03
132	1	331	\\xe02948610a9751b954dce1b79cffb28526486795a62ae4325ac19f248c99f5a81e99e377523c2b11bd624b70016297db5aa2933916f04e19e18cd976b3f71700
133	1	409	\\x696d1fca56fdd3398a1328cbac02a79e8603fbe45a5c5c4d96898d504865a6868f6ccbb3aedb1b07badc7ce4abb01e6b37bf347df4bc31de89852e7ca459e000
134	1	350	\\xd86e778236449684f2fb9fdebbcfa3fd6c83aaf54098242afdd39334364a3d20aa68c027ead964b19014e6d3860a69cb23628fb2deb8195aa651944366e77b06
135	1	365	\\x61af22cfc6faf79f749867ed0b9e54975d10d1b86d0e0d933ef7ebe7b526c1733ecefb204e527e3014054aeb85e05aa2d493c5b8cdd1fceccb401ef8e150b001
136	1	158	\\xc1083bbbf37049b633b158137f8b63c164b6f7eebbba6c6b773ec7889e0870bdeaf4a5254f4707662e10cdb1a7f9f568a97cda7bfe26c9985d8c4a3ec96b4608
137	1	349	\\x95bb7717bf8ac432f19f30966f49f963bacdc0c6b256bd8bca365d79d83f3a3055cfe2c44cb18e946288042f1980b2b6d3520e4e65b231a366830fa1ca6f7f09
138	1	214	\\xd08763d0e30ae1c4e1d5a9e3884470627e9494f20f9573e433950e550ea30ce09a871a85d749e569441ead4c478d749a08da14cdb63b13e90d8764d49b8b8b0d
139	1	115	\\x71a699d501171054c0eda692768b3c18db5ab5693a140f574ca2b4d93ce2e1170f48b57054de417a101a2730526227d0ded108e2be22f991697f094ccd3c0405
140	1	86	\\x08b26ab64eda44658d52dde3f5b2a54b2a35e290a3389b3062d911bbc641eb6af823c8abb304ee84b7acb96690cd3e28f5ade56bf71c886952863e2f6212370b
141	1	281	\\xaf8a58b4d79b66b04dbd15d166d87df759410e03cfc869ac2c1ffd3f705fcf5ab3ba8ba30aec4a7462b59909c1c130dbd72194d90642246a928e5e59ff98aa0c
142	1	313	\\xe3ac8dcc431e9c74f921988013c9fc5020196cd05b65f1f19f991954f3e1a36a00c97475733756fd86903970fae717c5d1e60fc22e5fd99326eecfe1292cef03
143	1	23	\\xf769a00ebb7076d6f58e04324c87c576b0ca706ac4b472ca1c3f4492a4fb636820774e89f594c4b4718b75b85bee10f3c17066ae8187fac689e03e7901cdea02
144	1	422	\\x3cc1f2d9000938b28df80fb37fd0c679d7f343d33f3ede44a6fca79b5b93a8cace54ff15f73dd81685d909057b1059f05f420548216048149692807419851500
145	1	271	\\xf677903714a02a05802a61d40c7c63d876b6d19f4049145ae6546f248f5331a9ee55a1da0823ce0ace56ad4fac436622c3489f6b086b2d50ace7c3e2ec728302
146	1	387	\\xe0064b268a4ca8e0f1a030fc538f1f3c79fd96c47bb441b149557fa21f939d070f90f42d98ab672b2f7387e3cadc072fff08ade0f6ecf8fac9a44502c7b61a02
147	1	171	\\x0e3bdc1237f75536de59ab2977cdbccd6e00862b9e39cc5fd6a95560640f8bcf7d576d7509832eef243a45fb51b91ec92c9b4672f9610a90030e0e02cb443c0c
148	1	127	\\xec8457f96176bc2929460ecfc4a3eb7da2fcd8e6c8550396fa95eb726abf06019fcdf4468dbc2b533922568b2f54f7af436aa5a7d6038187b2ec424a985bd301
149	1	168	\\x18ad98cbdba7c4e2d5b09290c0a2c3ea09557f308dcc5a70e61aac2f888e0c00b99e1284692c3769b5fd6f612a82b7fc2a324c647624c69cc8616c8b72a4480a
150	1	415	\\xf2ff85a0b7c3198e7dec9cb85c82bb9b73b4109d1c8409172033f5a115b4e7080702f748ede379ede5a836cab4b80cfe6e21c34a22d3462e1f02b395a29c4506
151	1	40	\\xaa0a98e5f74b9db71c6a618d693a53c249e96914c570b3b0779a343869e047a2bc5bb9bcfed84ac5a4c83e8e127e48e98b1e2e1e29b2cb1ba108741227c3f109
152	1	72	\\x49463b8be19d1b046470acd1d9f82233fa4bbaa4a81fc84ac095544c57b0a2915b6cce267e6ef337c04236ca7253526338731322861fb9afffd2ff839d76a60c
153	1	226	\\x242fcc80bbd75b43df2d6956e96efb80096673a73419dac73ff790b699de8c580f4e970eb449f088504d9fdeae3eecad429f4f46a83e4f7daed4537893df2d08
154	1	286	\\x634ebf1e5eac3f0c85cfabaa38897339d90d782544025d51b8b8a0b521a6de42a281c94c54cd50b29a09c9458522ef6837551090113b96e93e1a33ecb96e8c08
155	1	298	\\xd6a35a2f400697584919590d63857cfb1ee6a642ed970f9b10cebe6747db1e55cee52c1be6a978798cba65c3e769620d467d1b046a7bbf969f2532fc19e4c404
156	1	68	\\xce17ac0d4ff0b7260181f4aa552016815a7b892dd69d4dfacba645f9bc7f393c044f1ba3e9b3c7c9e7bb96c5ca52142c1ce36abd29e5f30fec000652caa4ef0e
157	1	79	\\x81c41cc9f70d8e1156496bd1d26593d480a7af23edec6b2f3260782ee2114c60e076b568f2bbd5f9723a31ef0f910985600d65e9d8515f081b3988ee1b198f0a
158	1	122	\\x156ba956d748377664ad1a361d075db95513533902c3aaa5d8793c69f4a741413eaf6a025010e53e777c47f1ce5324546e15722b65ebe99b6698d40e52584c00
159	1	259	\\x7764fb0ecc60ffa5ac39911ab62293035c21398e6c9091e80f823e0e3c256a0db6edabb05d3b898aee33f05eed64c69bdbeacf0a1462358123e47899d58fe80d
160	1	245	\\xae49f41bd745652766895227fdb59f5c7e9a410fb8e1d12875004e62886aa5dcfcdefeafd0b75e3278d5add2c27c9bf837c2ed8d8f427eb76abd5b8d79dbaa06
161	1	183	\\x4e9fdcd23d15481f137c60150079f9f7159b7c472d43f5af29cba10ca41047a445aace318e3a0d90c19af1f19335fe78fd2898bb0ff384cbc53c70b26f9f570f
162	1	284	\\xffa46a444deae8ac1b1035327d8a42d044c18e8ffbdf302063b2a4b004f4e56438cb0694cf8019a7accca4eb7be65ee714098e1c1f4a8a9cc45d9012f7faca0c
163	1	205	\\x50dc748c8f5d47c6195f03834495a1be08590c7e1b58a9619062e01935914ff661728c6debcdb0e83bf28de93274aa14c44ae2a014410065eb0d21e04270af0d
164	1	112	\\xacd611decf4f608a06e7eb5241f2229a61fe976b84c0fe9742a9cc2ac68f5e332c28a8a2bbb98a44f8a74194d9824d9b78bd82859949c3e9298b1924d4a71d08
165	1	182	\\x9955ef4249503038a3e699c70b7e88f455f536a0bf1cd4fe92062aecec32e5127459e83f2f8dc84f7202122caef87a25fe81577d76e2bea09c089fd8765a3c0c
166	1	388	\\xe75befbcb96725205f02635653b812c659af037efced9dcd8d0df6cb0aa2650702ad1172d706a55613d811241243c58b789abcfc35e307f5bdbf6d8233668508
167	1	260	\\x24fd0a59340ef3a1e023289491fd6d762b701237d7907d1af7175aab72e79b2af8c26cbf27db25792f8ca952f3ffa6dfb477c555ddbba3a451087a5b0d1ed205
168	1	77	\\x972eff65a7d187f246d08e1c9e563a8b7582fa2d6e5d4163cc8c0440a02351c5c82c4cfba3b6c05cb2e3b69fee73b1d85d652717a9ee3eaa6cb16b0f4f258104
169	1	1	\\xb3ede1bb117182aa997eb7a71e22fe6e16c243f229580496b8fb6f5bf5755f6ca07354cb2c3c46974d5307331b313902c60c063189a08f821808d8f61246e70f
170	1	2	\\x8b628d234928961f21b3e151a244a879f488502eca12d2763a02a1d2fbe465b50086895134efe9ce515a5d7623523090798f4eaa69fd9de8eddec326a374460e
171	1	51	\\xdd14ca2ed959416516d756633186b749ce8b7f351a73174d76ffc46ca931334c11c1c6e80a56f667429374bdeb41e254017509aa972a8002e5c32c17e8d6830d
172	1	283	\\x5738407757ef3995bce2ba42e275a611ac95904d724b4fa8074e76d2e2a0cbe5ef70b063ab7bb71859c5d6b53a29cef1148ab92af8d47f523618ded5432ffc07
173	1	82	\\x086ec5f04b12820e8ce7cadd63a58486b25d00d986f0c63b1f2789ca62248ca198316f365bc26a927d667e1b75e141d6b464a3fc995493549e19b95f47fb6b08
174	1	159	\\xe5d3226618659c61d8e85e3fec983c1ab76647e182650c060b638899367331e92b0e3464e100d7a48bc79286b70f59950bc7c9ed162ed7603d6af1051fff520d
175	1	60	\\xf3fbb2a40d1ae295ba81628d0c27ffec8f55e15b2490668d4112e7bbfbf4b1426c0807c6e0bcda169199814c7658a4d3cbe40b0b3e178ec4ce85cc84df060908
176	1	87	\\x374abb5a08a40b8e8bcb9f3a89557a6c81c45b46db9220e6c09697cd7c6ba81986efb15efdd53216c525d3caf2a80dcb8c6f036d913303c98447b3f282728403
177	1	84	\\x16bc0340a39a621758bfc78b7f67535549ad430b543a2bcd59aa24c54ebd583bcfb9dcf80bb6cf00315241259f9b4989a4be0da5a9b949b0705e6f75af91eb0b
178	1	270	\\xd5978fef70f63cb255af6f6aa9e688242a40d04689ef6a9f1e50f72b238bca8d33faa4eefccc7967e6b2d0137972cd1a65bcbbbbc2d7ee8749ccfc10b0a64109
179	1	247	\\x7afc956fcd58b7acb80065c1c902d61b0c856941b1d17f74bfe9d53aa9eee804e28ec30717b793004c63e54e65e37a3bb846f4f1b99b4f7cf2ee861ba9090d0d
180	1	340	\\x819db1de649c7a2f483a8d0ab2ca9abc31d923f73a1bbb354f4963042e67d14a86c364de9aefb7ae2f7df62e283dcfbc249335c833f13bd35b2c8e4a010d7205
181	1	117	\\x9c4c15a5ed9282e362792f9be94ed2930d64c51c18ddf28361c67d3633a829c45368356f9f7a67987c165edc96d3ad5cdf04e94d4c0ea078a8e6041ed672e609
182	1	138	\\xaaf5d7fddca2b218d6c0490e48230563116f14214db5cb534c2cbb2e4996693eb8ed0fbb7c3d8a107fd5d6349402b04889715afcc4752be7f3a123515cf09b0d
183	1	101	\\x6be821cdd46c5daa0360d5c3554bb3158c3372124f011675c2a4370d301f16ed5c5cad1a629448b1d92f071bd3926dd0281c6d2de53a869c7d59b85c26cedb0f
184	1	174	\\x448c4cd48daedd6a4793c0b84d5b2e12725e47672dcc2004aad33e43a1d1f175f11cf2f91003e23b28e2eb4613d4108fdb024807b97d50748d0e34990cab8202
185	1	141	\\x6c440e444f7f1877783d8af8826562f8e173393416f146dd1e9c117913557af32b3669994c22ad6d9b280c087156dcc9d83567a3d0a89ac9fb0931efdbe35c05
186	1	317	\\xd04251d32fa85f5c1ce768e1c0af88bd4adfd96b5d89b4161f79b6085c5dffb600c49497d2ba098f7b516470798d9f148ff1a5ba6d38664f1b5659394b2fb808
187	1	89	\\x14a10d2d5e153e35ea2a95afdce751af5dee08fe378d3ab96fcfddebe665442883c6b7bd21ee89c3941734f3d2c1db91e6c634bf6cfbb4cdbd2ea3dfc224d404
188	1	411	\\xda5a2da021d08d0726a1112c7fbedb5299805cc5d5ec32c1e96eb2bddb8c176d1542d04cf0b43093f546c6acbd0688bda3d98f274c6e94d480e263065e3df90b
189	1	111	\\x2c0f64ae345d558ac337fdc594664217435c2d38a9c8380fe4a9eb2efc9735ecaf7fc6ad26d63e8a209aabfc045588ff45751ab0be5a2d0ef6bca134eb7d5b0b
190	1	323	\\x89f5b53bbc71ac14f01d1167ef0108b23783b63109c0486c9c46da4efcb249d7396fd3b3d9a9e37c2a66334bc3b5ab1b0421ba4b7e7e4d0638afbfd837b84d08
191	1	262	\\x86cb74abcf7795f19b4628af9cde26c49df91cf7fe419fc41602684e1cc6e224e1c0df03ea2defccf4567443d92c345ef123c63ee361026adc0a6aef1b31920b
192	1	244	\\xacbd84a448776888541b7c9af5b1eef436056bdf9cba8f840745e2fb1e60f02b443e78abfee5e047f044a542d71647c101c96e9f3f25c902d25b3d6f5d2b4e09
193	1	371	\\xfb78227096592cfd8373765e03cf47358ef4a58353df182c3cc18360657fe2339dabe429fd03cb38f5bc19c6e89f77243cb434f151a637c94858ea48adec6608
194	1	248	\\x634fa34ee1bba6b8a4fbce1782fc923dfb1a0f488fa24632cde409eee2df334cfe87abc4ff9e52104474fc02a897c1949b1e5bea529af26bcb14f49ef4db8f0c
195	1	179	\\x7faaa1ec036d646f092d8b48fe3c445fe3086ce0c9c06ab0669e360fd74dcd3bb6a22e6c48b3e292ad459c7f314e7c361512349b2fa914afd2e1424f3d984e06
196	1	224	\\x8c2b1c0232d0a0377e225d1a0ed8eb8be0b75ca949feec9ec332934ab19e0e78135622b7284089c1a1278dcc781ffd65248c71bd6827f1ce7b4bdd4003572800
197	1	341	\\x5129041640a0dc9bab2044216b17e6d7a839e9e6918bcf148bcdcf182f64f237096b1f7ddfa11326b11393c682a07b10f6d7a062c3e316ed7490ca941304aa0d
198	1	62	\\x7b2c623056478dc4e4896fe1306f1cfced874c053c1a56ff479690bdc12e6e52d058c85b024ee41644e2a131aa4936f55eb741063b1e0641f3ad009847f75704
199	1	254	\\xf7dd95a75f844ee8f2241861a29398dcc152b65e2f6850572c7410e6fdf99aa9bc6f090f361d39e8c3265ac49ba8b58412f37b0835bb2577e34ca41df33b120c
200	1	381	\\x0025016ccfda323288870fecede93f5ba4e7b8fa4d07d082314ca72161e472d6198a55429cc5314d9edce48c6e66ace7d985449ccd533fea69d9ca5351dff800
201	1	267	\\xd1fc3bb01bd104369b3e755675a4305c620eec8618938e35cb0ede59a0fbb855797e1a3fb005bce78f4ea2834a1682dbd77bcd2208b620b55e836f777113e700
202	1	212	\\x46a89dd7de8a11b764dc39294752156116c1a28740cb37a11c613e615982472a1148d246d60e91c8a236f04fdcb26d03826fb1d6509bc335c473554cf0474d0a
203	1	37	\\xdd18a8af2abb974630f9f5dd30f090e5b3789b3b661584ccf53da4ef08ee3d51f85ee12bbebdc8c9837f569a1a01a0788795cee35d81b585752d5baa5bd9c805
204	1	180	\\xa7023f1eff815d0f40718e9067f6d0cd691f401567e145f5d5f365564554bc38a4916f26049d55b46b4491c0b1ef2de29a269a2be617e80aa9f9964d71977a0b
205	1	5	\\x98554b18f62ee410ee1ec0e4a036bfed903d4b00d02eefbc58727753898424659959c2f3cf8bbb5542e497e49aa9902aabfd130b24369213bca1c5616cd45a0e
206	1	399	\\xec60eeb68ff6bda1c6f1141df37d57f7e13d9488d1df3ba7338b499ff45aad7f276f9d0c8748ca35e40b76a28e009971d637cdfdce75fd997b2404a09f4a7e07
207	1	90	\\xa37c3b9cabff712cfca3395a0bcccb3c30f2bdb819dc822a3a3fd04814e0a78f4dffd04964e5ef8889cd50e85fbf46154c4f8d9b5d6d9d62f1cea5849776c908
208	1	155	\\x8ed3e009b7008c07945cf960bd38a8a6117c58d4b594db3304e934bf3b7b5b699115b2b32cfeec0441238bddfcff8dab30b2cbd541eddb0a029e091da0c78202
209	1	273	\\xf92c5fbb764ca1b0b7d1a55f95c96def6251d6bffe36b5151137d5f55c45172d9e20179ba2ea3911344dc4b29e79ee8e02008099fc9b04c8aeadc3c22716f30e
210	1	49	\\xf8047688ed467fceb53572785fcfe8aede2bb782b61ae44d8ea8e36c10c6c5275b55048501137f80ef7842f819571f19934d515bbac82589fdf457f85852350a
211	1	369	\\xa6bef5099ab2c537d3d23947ecf4532acedd62710dddae80633550a083b81fbf3af00c46569dcf1b7334469626f0988e20fd67a3442a97e314160f89d0326908
212	1	293	\\xcfb146ed6a18f5dca830e69b0c09155691864197c811743bb10087b2525421ff143c32d6c657a503fa8c31c12515a618df31022bdeba64b32e1cdcb6a7574209
213	1	354	\\x0ecc596dd79aafcc4731f3d75df2d439e3f4db9fd54095ad84827bb1ce1e23ea65bc029fd076a41a83a08c4baa74f90b0232089b9b03b05802d9d116ed48c40d
214	1	406	\\x63eb03c9582f518059e199d808c669af2bd09615ad20a16b13de5d8d072bdda875850a6d2aca3e6a79599286000b22f60ddf5898171814a8bc7621aef45a520f
215	1	255	\\xd7f295a2521c1251ec4827ef9be25781dea1e599cd8027c176f2a7cc83d0953da729ca3b8a86e3a543d92bffc55549923be1a070c9795dfe315c6d7a5dc06708
216	1	412	\\x22564abea137c53178da394eef3619cd87ee0bb90fb1c9ff45a2f8a443d27adf9089be644c3cfb94aff9cdf437e1ffaa31ad7ccd01e86e82351e5c5e06643305
217	1	104	\\x09e4ad297abb68c9894e199f2415eedfadc857f028d8a35f1972b8c4dcf53471b362faf42663e0311b87a5860f8b851a9bffb79abd8472b4310d4da00303f705
218	1	36	\\xec7e039a65bfe33caef28462e6ee66ce35e6777f3c48177bf44e5b726c7ac2fdff7bbb29aa34197d097cb8ee6b7480e32d5a54fc2349929c651089afba3dbb0a
219	1	154	\\x8b55acce32e6074c2817349f4a8e89483753b045c9d520f63616526204e22df5f76a7e4d2e44cdebc183d3a59d5c72a41bcc6875c051e4c6deda41fdde3f4307
220	1	382	\\x9817e7495a62f003a2ab59dcd25e2a115a1eca2fbaa205418b42a6010e04f827bd59c21721ab3c0deb4a8fb20190526a8cab143b41337f66d0644f1677358109
221	1	288	\\xa358e4df9a9ec23329d25dd8b0d795586fdbea9bff70e7847fc0a5694600de7b15d6534b7f64c59e1be4826453584806d65e993a782ea13a3fa24c0196eeab0a
222	1	169	\\x45fe7bfb964fd88817285754e302983328d63437ffc5e58e028ef15c781e54eb9f894322a069f9c3b7524741dce216c68f77ef406a47c17765c90bf5825e5c08
223	1	8	\\x36269ba641650d24443e6f54533ebe4e66bbc8b91ba2d260d221a86709f25e42ca48522d8134f2520aed05447262d1db2edd7cc64fb583ae4d382b4fda631001
224	1	392	\\x97ad8ad1d085dc1cf3dded3bf9ab3d648d4e8bbf4378eadf2223ff70f6329a9f1a211891a5d081921212edbb3fb006553928b249cea650baa273679693063508
225	1	249	\\x979e7b5493ecebe1fb4f480c6a2f230f80ab3d745e040d97646267db5646ef752f12355dc23ef9ed124503b6c2b7c7b5275170fae050349ae8f43ca7a2d3570d
226	1	276	\\xf01839d745c1ae73f2dcf56664128991435a958c96eba290e41544bd4d25e71f1394e353f717b6d82d580f7e4fc5102e1fbd5ac8e5197601059b16475670da07
227	1	348	\\x7e6a8274db2b1347e4ad08b4f86b578221f667b0e64eb0d62f3632df66dae6f3ac647de2f412471a486d5ce2efbfa7c222397298ffd008d78042cfc159b4f10d
228	1	43	\\x9d2d83e83d1c346fcaa04a95891996668b154a82edea726b182929f380071fb6906a52624e8111e827fb1ba71abe3edf117d8b128ceb123fe95a9285e4526606
229	1	167	\\x9e9436a29a58151d5080b90e678edc99ec78b7c5d8779e50d029e0a417b9a54f39fcc6dc02a0bc4f77a9453cae7c1d5e30406d926a09190524ce5a0cc4fa7e0b
230	1	100	\\xb67a7767012fa7d01f73a6fdc378ad13fed8a0f6d7b3e0b9951f63668b9e8523646bc9ad5a806d8fbe01de81e42057029317afede250cdb3a7e72e001d951a06
231	1	240	\\x611edbeac6f1fc9b6aad1ec7c9fa544c88952d426b26b9256e19a31a304834d1ad0610931f8c97d01a202eb4e59e169c8f19cfa3149e9a23681b5dec2ca43f06
232	1	417	\\xccdd459d7eed29722a1012f5388fcdb70a519da3086eafcd09820d4676ed949a2f98dabdb462a25b38b95fb9ded268a28f0013003bb59bcabd16d8694d504d08
233	1	130	\\xc0ce5fb8c0de191787ced1a384507f85fe6cafc82e88471ae386896617a1cfa7b4293618e8e10d5ee5d876bf8e0f6845384ea41f858626332e7cb7c8f511c307
234	1	280	\\x48bb2af40688e1f90fae2e2da180d801f2d4c268b87feaea306d19a76965bcbe0f6de5c024e24cc600ad78245e531667377cc2bad26fca0625e993fe30f1d10d
235	1	307	\\x25496e5d5c59505408c4405b9c269c24a328fc29069cb98358a6a31e38a64d4ab021206c6c9e47ebd919f41ee8cc33cf149ae2e6bad25e0c431440b1cc1b3f04
236	1	320	\\x3d1302bc2a7e35396f0d642541384ca6b496f573a61b922a60f39d82faa21f85fa02ec9b3f0777b559cc7393c4f124d11344d721dffef8a96ce7a52d7f1bd60a
237	1	181	\\x2d44fcb84da05c3b70538b10c5d9b0f0029f1f2eba7b15245664daed295cc6230aa02736a1758c0c880086c02638a09a879e422f711ccc069ca15534eb791509
238	1	45	\\xb6a3cfa5c5808e98124ce59fe054907f823ec7ea4a6030c71555cb8f5e478a58189abb5f69336ec71b2088d279d4302f473d0fd2ead8d4379957694254410704
239	1	54	\\xeccb7ff4859040fb2af32af167192df17701e0484baff7472a34ec13b2ec8a5514b64a02f1ce4f04fc2e98882efb827aadd3e7a4ea2196007818eb476b247c02
240	1	342	\\x899cf17a205bccf32f50850d35458ea55c17994868e7911b694cfb275e63009720df4a93102ad299e5258aa3b04c2ad79a859c47ef205f820ac803d789873705
241	1	336	\\x37f1a503c3cfb4c80ae5215c9190c5c7f620ce143729ea9f1f014bdbe602fe587631b4deebae93207d1fd83bfe544ae64b3a1da8632518572f7bd16ad9e9c40d
242	1	290	\\x92c482f7ce139e043427761d28e23ae6cc7de1143dee791bfefcfd1a1c6da8235f2ae09494b0e875b4461c2781f9673c23c96bb3883191d3d68ee0db5ad7390b
243	1	10	\\x37e5fff397e2a6c8ca83260b0ae33c0912a3d6911fbdb14fa2f457de23941326b12471b937a0981232d65b576338625f3b4c5a4c95fb3163f768ba6a89c50d0e
244	1	363	\\xd6647aba7991b56ef5630b5dec0f6c1628c54eebb0057cbdf1383721ef618e5a02e4a0bdfea2be9072ce4401881b0550c0cadf0e35e7bb28e8b73c732a4e3900
245	1	390	\\x4d87e391d6ee2e8631a00e8f795c8d16c71c558a42d5994ecb4b63de58028a81853c17a65999986d60e163897eecc5a5e983a1e6919cd9e84b490cd22d725809
246	1	378	\\x7340d2261a3a5f65eae6734137aa24194cec634d34f42b1c5365d4f88138e76208591aa966aaf3bbc42db899b3bf582893c242df5d43bad5030092feda19220a
247	1	414	\\xf922c38a87918a40e2e758bea52f0873eb6d42b5d5b66a517c85400095e321ca2560343ab261062bbb07742b62cc0764d32751c379c537bb3f88c4afa11f5801
248	1	223	\\x78fe9d2240a5910e366b5916d373997401e3a24ce2be422d15009add2af6a027155b8596635f8877c13461e43834068d5ddb8141c6aed39a956cca2c91a94109
249	1	325	\\x01a0b252ae771a5f42e422d4170cf089431ab20120a779d76da5948b663a000a53dfc7f55edb230ba97f0be444c452ce0f9c6247dd85d081b119b17fb3a0540d
250	1	165	\\xc160d5364eb159d0d0b8a5d730fbbe263dcc9e7c7cd60178d49015c2f58d9ebcb6cd0bb72bdb8d6d2d0b1a503bb8c1223be7e6d0bd92ffd7ab42c1f0c34fd106
251	1	41	\\xf4438b82f6135b1ade6e7ee8bbad415edb257d5c5d85809aad249bf8bd204783c4ae36d11cefd065e88b2777785ad8a85ea650c0fd0cc507215d33ca5f61050c
252	1	404	\\xcf658715b10f5659ea8deaf84b0cc83b622440a0bc54c6cf3c720d2b9dd91eac1a46ae00e671f94c9211395d9c69f81ebeed6b1ff7c4bc0498225ab528875808
253	1	197	\\x0b3299cc30de6ea0271a7d58bd5310ca5d8a3256d15d84af4744dfa2807050ed8277aa6e9ad2c432314597fed73bec4ff58ec0651e79584f4068466d6cd84705
254	1	314	\\xe05c20f839efcfd81e4f9ea0e898b1002400399f49e889d0dd553fc108fc9f9692fd01b137b71e5166227bc3deb39be77aafa1c1c00134abc1fa363c2d04e108
255	1	326	\\x7b511fa862da163c2abc4e56c2b7f69b56091d374e473f8eefbd8f9cba59cb8564474d15f5b76d75eaa6bee3600a2d5d9bd9ccd99b8db207655715a322c2000f
256	1	175	\\xb5ff3202afcc04b32c04791604a3c9c35143f5be5a0d1ec715d52bd07517436953891342af4e30fa7cf8d6de471be7da2b3d9c0cf87580f38625a3476bd83e05
257	1	63	\\xf54c0a62a4b5a50d2b7cfe6dbe9214ed17b95ee9686295b4bd9c08169e312a0b0d5e4cb6922321f72ca1d1dbbad2c9263a60d380e681c60ec5577cd20eb4c30b
258	1	33	\\x9555041f1cdd4816cfb95e04a94f30f42dac99c6eb4034226e908b08b27b619459ad4695dc88c3c7a1f77ca60816fd8e70fa3013610602cb185fa5aef7114c0d
259	1	76	\\xe1805a93531020e76e2b4d7a95b5ba253f68cb27cea9c68886cf108195ff8b8fe88b8d2012f50a0be21bdb024be244af609847859999a31be0ba7610ea31c209
260	1	147	\\xd8a62eca1fef22182718df261bdc66c913d24394a985ece3cdab58c4def0f9b70604981ff8d18f27d9a3d9c105f8aec670ac2baf0823070eff9557784e8e1d08
261	1	355	\\xe8b856fc454c93409dd2b3b9aefe5d51b5693dd242c624ac09a1934b5457c5c2740146736749c5e8085efdf2764f2d7704d5af466295d5519b3f09814abc930b
262	1	305	\\xcc50315887f524df09358397010a5e3231aafd91b3fe600a6eeb92ef5051796746710a87d761e3b36e50a6f046584c391a525857795437b5dda0293cb5bd200c
263	1	153	\\x301025365efa626750b26f548be26f7fdb840f6d8d096f78275318fc74a6178545a7df7ef038ca2cba1a800df4aa9d54777fa9d419552bf1d1b7bb25e0ef3f00
264	1	163	\\x60956c930d90e189ca65a6a40d490299e010bb12b9c22b20dd5ff1e4d76f69ef7bb11617608ac7e8212b2a41e345328b390f58c45ba3d7a534e593c9e30d480d
265	1	216	\\x07ca4152c194385583044b0e04843eb494f634c20c50a3895d3a154177a09af09e236d23e61cca61aad404fda985b89bcee3bad315ab625a2d5c6d853076bd0f
266	1	44	\\x7ace038451829e25b356539933ce836d3fdc067cb588528d0f6067f0623b9ab5b0f14725e5f7e5d429bac67df57898bffc8daf0156f55da8a1d81bc0c1f0c10b
267	1	110	\\xb87aaf4d1230f71440ce5680d91108ed15896c77d7c3ea0173d74cb1f1a29c5385387eea1eae33170097d62b8286ff3d4a4bbb7082fbeeb672f932dc6d5d720d
268	1	137	\\xa4e2e8336150b9977cf993f4e973aa654e7a5aea7728bf700d5c373fde08f587df0ccc1619176997ccedb2183537570fd31cb7474d20dbcea9fbf0493262cd0f
269	1	150	\\x2f21bfebec10bae52b0e5f816aadda2527d8ee07998198d62d6356e450764a7bdd71246214033047587b766fed1050e7d303e92fda8b5560937bedc9bfc10c04
270	1	78	\\xedeb5bdfc16555d5460e83116aebbc0cc57799ddaf8a6e20f18e6783d224270ed3aa202a49263fc8a2b82e8d968195f4c9c9ff751240eda1a36b57cd7591740a
271	1	61	\\x4b4230a14592b70bcfe1f208fce9cf40e26c769fa74acc32c7ef9289d422a70463c699810cd25d33191834026151ee5ef856e2a6ce3970d54f0f4aaa4170e602
272	1	402	\\xd92b305a7c540fa722a7835f09572b3a3c2a1f548efb7d0eb238cc1d0814a6c783eba2a782ae9fc1e65aa36d2b72d33b7924048c70e637157489a99cae33760f
273	1	20	\\xbccf98523fed12a60e5a4066b629413c5e33a6be7ec7393a20dad31ffcd7df4d0e8622f4a86ea32126f07043f232ec2bb8260bd2b15265a750c65d499edf2406
274	1	66	\\x4c9978a2e08f335e304100fb871b0c028114f736fe469e27d2e5194c88d9246571ce4c8c6ae0efc2c6b41b8428af89294637b018c57e5c8a49f6cacec2270a01
275	1	253	\\x7f8c19ec0636b5d20d2f1f07426b7915044c095790df183126b59567eb1c6b5fcf6d7d8aa33c5a208ba55c09fb816271b20e581228ba6ba65331fb58fd713e0c
276	1	184	\\x9e3e8baafd710e67751cfff6848972b662e9bcd545f90859e3300a5acf4adbb07785ef07bf2b1bddfee2c24296917082aaad0224712494cb6787266768357604
277	1	195	\\x27dcf87f845c8bc3dc455a7fa2b69803c44f67966f24a46bd38f9ebf711a51bd9bf7a3a410f8c1ce0bfb099dbca0d34285a2884983a4f9f5ee090772aab7fa05
278	1	343	\\xb245a45ccb342a972fce759f4c732070aed188991f20a5086d1c2fc35ada9e673d5fd83a10ff073d8bc191f313859e18e4bcd41d81f2cec428221eb3a2db5d04
279	1	346	\\x8b07f1650472ccac700bc854888c89b59c940be9846e80c6b43e053de05e1fcbf2e98417e3f3a861633bbef5ae25eadd9918b3096e1d4362c86f0b0188b94809
280	1	13	\\x47e2ecbcc5944f4894b45785a16f2fad82a21e59b1f675e3bf4b77a92ca19ce217b869de3f3295651d69c01a843233bfc4cd9b0228dc8e454d92ce9e1419760c
281	1	91	\\x2c153321cde57c2541968aabc4ef0280d240f5ed21639eb844f0190db53f18690e7ce53a275aa78af8c1714f8d759ad44cc6d690d53a8c79e90ab4ee0d4e4607
282	1	59	\\x9ab72ce3cb4f183d21678904f4b38ee8be45edf4abebcd76bec1851b1a9f5bdf5057eb91c141abfd31282679e1f62ab55ce8289dee3caa5f2508c14810957208
283	1	162	\\x98ad6f97eab38bfbd4cbe09024993a745d7f62acea5629cd9b4d2f8aece02675820250cd5323bb8f9e710f2b7829e51c0782ff91103195d5a97d2116bd0bb108
284	1	318	\\x87d132ebb82a7a5a80caa0ab3467a3719a15643270bb83527d7f0896ae689722deb8066d8762991445e687afeb2cf46ca5334edac05b27c0e4f79ac0d7422409
285	1	328	\\xbcba5cc0f5cd6ae0a29632b1e2b7d00546480982cc9dd02b53ac41433da70bb8204c4bdadc8d02a552541c5e2ff87e889662fd48bec0dcec091e9d139f4c080b
286	1	235	\\x3275992f9b7fd3f8ce8ca61eca9b874910eb5f17e57dd07d86775ede2738dd9af8395fac8d340e320bf77710c680d23c73e11e1f79c7444ebeedc2025abbbb02
287	1	69	\\xd3e6aa65717281ca8acad315ddf5eea576ac09ff88f6ef1ee47419c11d8e362913c7be7b30c39e14c5b1cb492df48a368072bf509dbd0183220482fbb055b100
288	1	206	\\xdfccef86f0742feb73300bd1becbbf21b731a190918ffa020687cd59f0fc5987edffc9996515151524398a31f8a8c3121b084782711a30459e17618d8d343b02
289	1	135	\\xec0474ba413fa0f118858acf32bfa933b04882e63294f1f3e84fe7bc639f780e0964af217333143ee43017068759789a61e08ff5ca655a3c63cbecd6e1da4c08
290	1	157	\\x70ee374c490781ab541fbad2b228941b3269619552a751142e7f3bd142aea355cbeecdf599494f2448f789e603f1a9868fd87d383c4acb1985d312a69132cd04
291	1	32	\\x991c11cca63dac859acfdcd32b334cc52a4c7f8d770897c9ed76276b3b4b88bc7665772e07c0119a93cd7cbee38f89b1408c26db829f47b2730bdbae1b4b9b0c
292	1	393	\\xa0402480e25ced1d129d5dc49cb859a4c2229fc1e10666f1b711a9cd98340646b5efba334068d51617e99ce10be2bdbab9d2561964df3ee0ae099d1ffe187503
293	1	413	\\x8170ea886af155de3b9fdf2322992357830a1bac2abcaf81609744abc2b77e4c43088f865c61117a0f9e39299bb4fdfe0c3698512e86014dd146a813c66b5902
294	1	35	\\xf629c2645b1f6d0ecc1257c2e500129a41eb72bb411562a1bc392f962c1d94d24b6ab520dfcb28557843c99570bc3f55a150dc50c4be3dd6d90fa09490dd2b0e
295	1	315	\\x715a01dfa21ebb7b78427f5661b87b5952ea1aff8eecabea474f9cc333cc52eaa146f617aa0f26099f08cfc15a37247053be7f91f24bb536a999a5b8f907f004
296	1	384	\\xea68a3bc1cb9481f476cea0d4f1033af7e042342e9ea7060b07b632d557c30812ac980ec2c539f88c0f9d0f1aa04b3acb5af2572685abf231c7798def2b38403
297	1	24	\\x651cd6dd4b80df3c68a9ba3c54647f028ff1c44a440354710d529be176533bdebec800fdfcd00f0ad688dec3b5ac71ac7d8ff7bd6c2e42da06923e0e65d53805
298	1	105	\\x2430356a0923c870bae4440f00e60b7eb1b96228ea97e5928de31b319e4e897a12ff32433bac2c1712b5cd05cd31954555979a19cbbe6d54440633a7f52eba0d
299	1	108	\\xc6cee333f77303eb7b6c8ab6621b00b2d6a91f44a595f1c586bb6e5e81f4e65740af7620d776d929591538243bacffa7ad635d41a7eb2d09bcd062f2f9266603
300	1	55	\\x1e65d8009188d09c2af7185525d62d8b1dc6dd5ec2e95857c840d3c8e815be430a182397f7428ed90130c3a41f8ca9f3bae8c55bac456b059a7dcfffa8d7fe0b
301	1	15	\\x5d0f6a116d63e533781826a9c9134f1f3d2cc75600446754189b3c3ec8d1a9eab0f031cb98a361d95577578b4cf9ad83a7c61d396d1c513468979aa02b556a07
302	1	287	\\x775cf95be1a57b7e7f8ed3993a7738b17237f632cb2ec7b506bdff400021c67170b3485ab9a7b5ddfa68944d1853876479524e558f5256056e7cc0f3573b0a0d
303	1	239	\\xd3bd20c3b5dcf93730a2f0dcfe9489a13905cdfb09b0224a2b5545b216a31b248ea895b3fff5da9d61247ae79e6e9979d83bf4823f62e86c06f26804c47dc50f
304	1	116	\\xd7a8926515bb0bdefa28d0ca2ee98a2e06ed7433c06c2472c97cc4f7b05a2df2a9e7eb5249381a3447e961102af31925cd34224d91a4b31f83a7adabf10ad309
305	1	322	\\x8b32a7addd9ea33964ebea77ad9e41839f067ec2b0ffc332c8a2871375e3fb2700b5510ea46e75ecf2aa92d604a1dc979557cf089a237007ebc6e05927fb260c
306	1	56	\\x7e082b25209bff8ab301927b038cadfbaaf05b3c00c14978e279d504ffcc6deb97bc734bf127e047fe45f9e1e99172e83ceacb1510ba5416950fae2039367302
307	1	151	\\x61153a5ceb3b0a675da58fbfad44796854ba988db3c8d03af8edaee86b3f867f7f56d2df679455812b336a8e201f975dd96236ee0dd080a535105ee403189a0e
308	1	344	\\x4d2f19b515e7f803e7c192f68885bec7b74842500712fe7248da14378b810b328e896b6548a8da5d29df0ad664c0f1dd7b0ba631a2acc5be9020e5661effa909
309	1	119	\\xc9ebcd4f0aeabe89146f4c9fb5011c78f23a16a54120441cfd208ea7031c18fa29236b0deb6d1498ec783f3862a324320d5ce1b544c05c412bbe234768d7b303
310	1	257	\\xef21d1c5b6ffd62c07afa049549e8530ef6fd98235f1b5df79fceb39fd7cdb68c03d4d6df54d7a0aae6766d4522657d0f8df6b9f0b932fbd285522c327cea805
311	1	301	\\x2732afdac9ff1830a213596212c1cc63982da36b1aa22f051ae2aab79d20624d43a1f3b61276b09d3e11b6dde242448ae7e38a7a9f85a0be7beb0457f8bff80b
312	1	352	\\xb2b06d964efdb167ed0f270e11710e5fd751537e4bc417239500349a11b4dc3f3aa303075a1358920fa49210a62c8a1cb9cfeaa73652305e1dd5edf9961ddb0f
313	1	339	\\x810f8dd55b5d8a7506800da8ac083366ccb2d1b81d0cdfe8326b61ecd18bd704fbdfa2b6a4c4a0fe061d1212f7598f69c9f88e69c743b7a8791fc84aa8a9aa02
314	1	397	\\x4700b48653f7b1bd19e8140f88a86ff91d048d793e36b1fda2217fd2201f356ed085f716decd83ce7199108e6ac453770fd309186a2473c4e2185c5a49be3001
315	1	357	\\x7674efbfe1879734e9d986ac9ac86770ea75fb40a51a6360627e1f79a49712a59a6257fe175e536c4bb0e2901640e441eeb41c2dbbf234bcf43bae12a38d0108
316	1	353	\\x54846710dccd75a1faa395fcd6c5e5fd0e0ecdf2a5cb01f2229b81b064b3c504c88996e5bc9b2ac94bf4045edeb20086f1c010547c3e25471174d8bbb7a85107
317	1	401	\\xfa426a4f206b2777d5d8d352f4af75135432080a16484a8d1abd03bb86a87551fa8a19ba6bb9f1179ac20739914768c5727ca75a933a58b8fbff350831384305
318	1	177	\\x389d8fa6d6d0e7300fa4436d4f554f1cdbe6c898fbba775be547e4692fc07ff5137fba30596b89420bff9a337beab48d1a0b305d9f6d121f2d2a9148bc51f504
319	1	362	\\xf407bcbac06b498b938828abb16ad42c37ed943d08134fd7e0941434cfd9b1ada3f51c28cacc6c055d1d72ee20cd9ca3cef82e987d35f03616b315c7b9ef1d0f
320	1	241	\\x400fcdd1b11d428c920744afefdc631083e611568e91abbcbe492c2db351153a8b29542458ee5d59f6a3f43d99bd27e27d88155c5f87410e9c686e4302ddda04
321	1	243	\\x6e76db5423a775640fcd79200a95fed68c9768c09c91c1b6cc5cdfdc8443c7a935b57b921eaf9ffccaa0f7909e359ea6057e717a372b8ee54065e2b348509507
322	1	389	\\x392c487a4d4afb7fbfed816e7cbb93b585859055f48fa0b986efae31d37a1f8915e9316a5bb5da226789aab4ef5deb411c9da329e123b7f82d87b1f327234c09
323	1	370	\\x2df576fc8d91711c0bb9070cd68b9be3189eb235c1d3323274159c39bc550a49f2690d558c6f8a663efc9c70b5219066d9f79ce9b0811b98a6589b64210e2e0a
324	1	102	\\x3085140074f4558fe451827d813ffe1c138d9cd7d344fe17b229c4c305f79a31c839db7863c00cc07482426c86181774506e3654be539925860d03940931500a
325	1	173	\\xca2284aaebeb7f31551614daee4cea6893a71b568d1e2ff7eef49a2bfe6f6c2be5309f0a6958fdc418caf2e03b300a85831fb5b14a83cffb734ce959db876100
326	1	215	\\xa7471fec8eea602be5cba0974eb449a3c169c006f39ef8de98da5eca721a9256b6d2baf1f2e11ac0314e2cb22e0bb2ce7c60eff17e491a9e5366f918a6bec407
327	1	332	\\x4b29e5bafd6e7d8a60682655d888eaa0f2c074e5f0f2ff65626043fa2328674bc551035460de9589cb1fce16d088896ca04ab964c779652c9fe4ecf1f1cf7302
328	1	410	\\xeac6a8cecfed7360cc697a799b03d022998872e242f6a6799c3833d13e12fc78205d97c2b456cca0fe2858feffb098909b19c370d0519c2cb32241e571f56103
329	1	222	\\x29650e76a23853c0497ef11b815d53e814bd1bf103ad6f1122070482bc65db89591893fae7aa8ef8a1d56d63ad2c69b79888ab3f6032e364f5a1f0c1b2435405
330	1	294	\\x9c68097c7c32f714886f04d9ded2831bb4a1417b2b911426643e9972059de0538db3c58a36c8cb25744e17966caab4cbf8162b69cfa6ec4d7f4c8de1b5c3ad08
331	1	274	\\x8e91595c814638458407d1a5e0979cc6f7b5f97a2d1472e20ace5cde101e4820a403ef4057256fc8d9553508afcfe3ac1c3ab85cbbdd602dd0c59e49376c9d0a
332	1	156	\\xb4de6c90283d3be0dabfdef734e0ea145943755e5ad535f348ddc888b1ed80f28b0a5e420a374eb9f2e02e3027057e871e328c2c944457f45f8f1e4753c3ab06
333	1	366	\\x6b021e1c1d1da984a104d739346e4448c535b1998b8dd4aebebed8ce6c1845436a265d0556e36a9e1fa469cc6df15612e7f370bbb95ceca2e6784d754838e003
334	1	279	\\x1865ab2913e5cce25ef51df5eb7be1b1f62e1a2918a0a56556840523bd2b0a5f55a38258adb6c33d7aeb7fb39d0d6e159ec4bf0911a87860836698d69718220b
335	1	386	\\xa06afe574b30d113f80b68a5ec1699967eed73fe7323783cc545523dfbb052e68ed3272694fae5c73d5841b1a2a553d9117724265e25a0ef9cee79647a82910a
336	1	316	\\x301875316c6e8c32dff6e46628d0176a805392e8c8821a958b5fc810d7c6a497d22c0228c6384cd24c9a01c2d6ebc80ee010f6cdaaea7f93ab3f64547b214a04
337	1	269	\\x9abd10bae8a3bd71fa3a6246b7b25702d2f45dbf5c8b740012ead5b6e25099a0ae56512f495e5212cb6eec968bdd503f2e44b954846c7ad9e7c3656e82d20006
338	1	133	\\xab228ca0f4b35548d2a0a1eed4682fed45d88edc56ac385352e2ddf0958b8b703487d09a5018f6dd10c2b73627b69b4fed22f03686d95f8f99e684eba9498d08
339	1	251	\\x1e900bb1f809fa11c74da29b53659724b617d94cb14c1d83df14ee54368235327f5dace781d9c1648802e9bf00ea1f599ec78cb195b2254863c4a299deeb790b
340	1	242	\\xffb2309c14b394238b58a76307767fc64a9ff653c9523b438444af6fccc36a02ff26dca1220aabb03388b9c5e7c856d84fcbc244cbeaa08f59927ceae9d9c50a
341	1	263	\\x15ac8aa616e34df160445d043b3cb197c4ddb765bc6ad3613c4dff9fd99b24b11f0a3679a78c7cbebd204f9b06f76cbb676a8fbae5d47e651e1528ef7252ad0f
342	1	256	\\xdb2d0ea6fecba9c4dd3efc6fce6ca53f54d0780066bf839bbe7191adff4200c861e588933232dd30450644b5deca38d50176acc69963064432af07bd859f9e0a
343	1	3	\\x9fea9269b9bfe1fb3abc0a71297a61ba6b7926e2f99d3a2e71c6df9a65f36cc46533dbf256f38031a6ff159beade38dc85a4351c5dd69a31684610e1b7ac0d0c
344	1	16	\\xbc655b30c6be9df372a9ccf7e1f5cc1a89a1f801b89bbc0d09bea30ce3d5d9fdc84038b7714ede632b1ced437368ad51ce126b892fbfaef42642ec77d2df7205
345	1	306	\\x8278607ddd5acbdc4351441520e178aecfc2ded20915b38d9d365f72d2411ec09acea474205873f932f24bb5038ed3af1bc214683142911df9425042f522000d
346	1	190	\\x3abaf5146b1a441612ebc3263caa3e3eeb5a62b1bb24e0581a1a0f7e91f254ced3cb61bf42cfa72a04e2e882cc3b482c9dbabdcda694ab229fbac8910ee35d02
347	1	266	\\xf5fa9a97c62fc74f6b260d17585ab4bf69370aa4fbbb7314650e939b8b94d273c4d5953b099a5dd62b6168849881759b14fc4ebab54bfdebc5bc14efa065a104
348	1	166	\\xc8790f4cff4ba0fd815def25d3d9b7a53a52bae7379490bb20b039b6e8120b5e0e526b749a33e6ee35c700edbf8bc2e33d6aefa21555e09c32eb6789fdb36200
349	1	65	\\xed6af747f4efd8dabcc65ec7db0b7fd52beb2731550181a6c7676f1fad758909e838a73287f80626060ad73b14b67726a12c468616922d96b1f1e68840e5d00e
350	1	186	\\xe795eeb7770c24489e2e674f5ecfa1e812e2a5d400700e4ea9f8c6e25fb24af8ddd728aa80bf96e7c05997ad23af9d22b3a444bccc7a38f965bc9d5b04d0dc0c
351	1	419	\\x9e002eae9de0057142c9522aaae29f13a954d3d3f36593dc5efd10fefcf593cb83b8aede635489db83629dd7f245e9d7534df75928ebe3693ccb117a3607940d
352	1	144	\\x3bf9bfe147ec426cbc1e3564c245ac3f0a08c80554e6c673d4391c3009927d593f639329e9a204a641d032da3eaa609844a7387387ef9fe187d8078aa7bd310b
353	1	19	\\xb4a03604b2cbed456cd6225863c1a2d14b285566af1f74a94211d91c934c77d84f00f4edb1d4918ba7499f48234b90e43ed8a686d876646cc364c531f1238f04
354	1	265	\\x5804d441f61a72fac6a481e1a74b50c00d5b517d8fceb7cc9d5908846302a715158ab37dfd771c95b09de017d22d52c2a701bd74baa55940b759092fca6edc0a
355	1	261	\\xfb6858436de850995362c9a7a819fa18b79f8215d74fff3db6ea9d4937c821e71cbddc31e8a80852179dedd310d708596862b73240fd1cf30df1ccdd1fdfb508
356	1	93	\\x221fc9409210527c8964ca46939b11e3ecb5cc90f50cbd9e759e76571e5c4e994b690110c881f95cb8049beaae607fc11a1fe9299479ae44069dfebc9f4f5d0e
357	1	333	\\x9d911b5b849c9acbd6cb5f3f2d9ea99843d73c8600610c78d33d3c5ecc556e02dbbfa4810688e24c3b0203f2b41571d51f878e714d73806367a0d2a19f05bf06
358	1	359	\\xf5ca3191965dfd151892916358e8b0ea89373ba9e7cdf76f33fc5536380c3599c55b26cd70614e6b2d750abb74edac4417f7ac19268514058d755107ddd8a90c
359	1	189	\\x155ce4923a0e431c40f4d8b1f0df377b6d1550f8a62b6780fd3743bce30182231489dc7fc19a83944415036fac97008e041115348353ff9ff2317454a372bd0d
360	1	185	\\xfe95ac8523e1651fe5966b4753ddef8c57373b5d0951c53832b974b8dc52a11c6879a3e18d2f3fa89160a9a9f67bfd92de4d247e1086322c93def8246aee9602
361	1	420	\\xd42c665fb10ea05574926c6c77017dce2dacb34010d42c00809b63b7af20c52e11182035d20e2d93991403d891943c0484c2f35e3bc8b55205edb2483babac01
362	1	209	\\x13cd06632c47654a90f629d4760e6b3665682752dd9dfd72d987c38f98ffb45a905698a952f563178cfffac560e35573e22b46a12601912bd2552a2e4229f004
363	1	81	\\x382c4183158e2db18551eb91977c20f6c819c92a092945ed5a1615b2eb2a9ee69809b81e2628f31d54b6b773444a511e88ee71c100b75336611f3475c2ad4108
364	1	416	\\x3461ca855219ba6aa69f3ba8aa84466783b42133d12f144c2f55bf30a2db5eb11e96c85517412005ae661b8ff53e8ebf41ddadadd48b0cef7a8a6d6b131f620f
365	1	278	\\x7cde25e5a279a8bc7334c2d6df7ebae3646b710591597bfb2dc3862a44d7e7832f9ba884e650b281779b68a492b813f8c9c5c399a87161a91080d2794ac47c0c
366	1	264	\\xa6215bc32e12a0650fb3dd330afb87d3f6ec58854f0be6f428a060360aea35091cbdd95d80a2314d4a92a89c0ff0206cff5ce12c3361c003d58190bec529200e
367	1	299	\\xaf0d92db5b068ccbbd41351252cb7d639a978253bfb579b7209012acbb2780115d6d82e87d083ededdeecb330b9fe517d4a7da519fe0db97638f3d237b123309
368	1	302	\\x9406fd91a80059ab79a7fd71ea88238a9ed495cd4f36d4130bc855380f72225901f75e85f82fc017f38132b36bbdd66c5ad80346f75cc4fc3549bf8feeb8d109
369	1	407	\\xac180b8c92cda3adc1335fed42d14c258d100db629ac0c24ab16b5c3bf71e2d81f760fabf462a251dd4048281c972463adb392e0d35abadb8364d554d5b3640c
370	1	103	\\xe47112672d84ea9274731f75d0c25d3e32ff851ee0ca72facfe6c56213889f2425f6f12bb3fe34e285dd5935af9484323b433c674fa3b3b6b7c9cd5fbc8f6103
371	1	192	\\xa7b6b7c9c0609cd1af8604ac11c810eac9862f6a7413f8f96583ef697c2393b839286262f0cc5904a6c676cabd7bb22b015894e564f284d7ada1209fef9fb700
372	1	238	\\x0c3580280b31c0c11b1326a17c78c77e4792afdf4b6564d832a5536f5689304e68de337dd8ff078b493db2c4ae31a39c100fd584830776535888326bcddd6c0e
373	1	28	\\x3af1e6b016ce87383ed2e935e7b26cbc386119e242c055f8570804e21c196e10dafe8f9308f37e75181195142433e1e276cb72cc66ae33b718ee8d44b48ab004
374	1	385	\\xa5264be194bb034c9bef5dda31ee9665187507fc914768d850c460d8116ae593f669ad222d598507b1e8f691bd929a0a83d61a6567adb860189aba21271f3901
375	1	229	\\xc291324e40257f842e960486b36ecf3b3d7a1e5f54e99515e9f67b2f1befee736ed9fd7509fd3cf65d5655552e9e7b7601196622867b00923c36b1551a46a904
376	1	297	\\x045b6c4c30fc4d294602fec544a12a7ffe67dd1bcd86d79463d55eb8219127dc8dd1e6d2189fef54a5da54e0cb6e2722500fc497ed9a7c69f4b03795a3f5020c
377	1	377	\\xb8492b8429e9e50cd8b03232dad4e27970ccc530da5bcd02fa047050180431a5d72d22b885c09654b525939eb1db10f6310639e0d5b3f4b11b0888616368bd0a
378	1	268	\\x936c6de9bd5d54ea226750e856eb4fe94f47f2002bb2d3c4f1b722bf5e26f85dc1fc345124abedfa187b283537328999154fcf9a52fd1f5c9eccccacfeb9400e
379	1	148	\\xefbd9d88f93918b03ac4e3cd39c2a371809123abfe0fd845d9261617826add22ef0d4397543f51aa3dcbe38dd3d696dac3c36f27deac29439a74fc5b51d2ce05
380	1	312	\\xcde79b10b9618f5fbbdff1c8fb23ad194c94aed54ed453bd18729300060a9201d149b7f87dd2a47d52daaaad065d2c140a92e3ef5164f72bd382befe01254600
381	1	200	\\xfe01e511f5bd8627a9fa01f225a05b49a30c6e16a59aed12406d5961bac5ec34caa00f196659212f6426ca468f41935d34ecd7e823c2360aab0028698f01a40a
382	1	198	\\x4e732d9850c94a509c43d10459481b24f40bdee2fd55e790d3dc023a6b0898f85b6a9540c4a32f16bef13688b806bf6d7f613f7f33b318f8250e88d4f192d401
383	1	364	\\x54c9267dae755129f5929842b215c1ad19b649e2a92661d3c40228ed92e2f3ed2e91031afc89b4038117a1e093f159f5ecd04b97ac0214ccc8f24bdd24e42e02
384	1	187	\\x7571c3301e7969ac3d086278623c56ca3848466328bf6780c77baead03ab6f7334fa630616182d62dfed230f41f2200fd8c53ca18d303822eb4d40d4d466530b
385	1	149	\\x8fcc6628b6097308a9e6ea7d286ece77996cd8938213aa1ff3427b68371840f681f6a2616eb77e2b0bb40fe4861e0011f89b657fcbe79f3bb0fe7f7a9191da06
386	1	217	\\xf4002bcefdfc8a45414ebb703f66162639078663464d75ea9729025fcc8e22b630226ab1e00fcf62697c49876f03de5a01b61a0616be137d534624e8f4169306
387	1	292	\\xc14a928419a870b2e8da36d04bea2628577b62f14cd48c2e69eef94c7e9f38020b211d7b785e4cf7ce6f3765ed0923ae617f294878e68ea215af0b06abc4b707
388	1	368	\\x914406fed9a16be04a05cf80ca90926590887cd1d27f68b115b1da182acaf7e90328521639a0e0c2dd9680539823ecd245c22a7745c04a6fd4213bdeed6d6702
389	1	201	\\x5088fc2dfc2b5ba80f1bae545fbc443c8388332252fde0db18587b6ec88672384fd1f115bf1eeba98769a865bded3741ee1f5222b0bde20ca800ee9e07850d07
390	1	380	\\xf1c814539770993df2eeac089cf3ce193d1979473970b0757a4f96445eeb5b5a7329b635fb65052ea016c3db232d0b48864bde4d520289a201105d5f2c58080d
391	1	324	\\x56b1fcecfb0527e3bb2145b14cbbbc8e7982fefb1f0108834afea382d56540b4f77050f7cdfa080deef69e6cb97483fe30a8317d443a741394ac42329b99960e
392	1	334	\\x0ea5ee2766bc74ceeced2bb94eb3a145dae13d69380e0071906e722a4e5efdebbfa272839c90f9ae9b2c0d6b71a63aa1b5c2d8880c3088b085f2df872a704a09
393	1	196	\\xdd814269a47525a8ff270c37b67e67071860c09251dc4b696d993bad81890ddf5be83b96a547b94a683f7aa201ace85acec3682cac1496f1807b2f1f1171f002
394	1	421	\\x6592c93c6cdf12459b973992aa47955147fd073d2ff6aaef01e911ad66262558261bfc4e5507a33e73e92e8a07c8b079a0c3d8d99e96e7ada97c63649d1fd609
395	1	172	\\x736f104d60e00d9512fe22743c34289b7bc00640df4b9a4c66c38fa719b86a8e54debd70c1e68cd15267c42f27222b9cf4f5fc0b63640d6146643ea8b8539807
396	1	11	\\x7df9f9714cb9ac8af85a23e8ab16c7d98e104fbd2a5f94bbbc27195b82e5a2a91ab9bab7ed7d4260a8b9c77b6f91353c29f5e73f412c186047fe2e68525c1601
397	1	120	\\x8e85b8188a9379d0a55202b55fae00eb2b6fb27320235bb48b24844d218aad82a7a3e05f69bf7de12e34e1ba6c68219fe07348748f06d82a2d889f5a1b4e840d
398	1	405	\\x371a646868f3a7a3c212eebb71ed54b7cff00e605fede4a62dc322bdcc055de42447034536034f5df9abb1eceb456c57893b7aa23ae584fa802cfe160fb9d102
399	1	6	\\x947ffefeeeb588a22d279445181e4bc6c33da4dcc0cd22a78231be59919f8084dc2380b490ccc52389270bc10bf8bb65ae074524a94c29e2f3136aa856a17d0a
400	1	338	\\xbd59c1732a304766e03e6275f284a33e3621963d00befa65055162603d9586f217402d4d9d76da8af73ec8e2088d128c9a026a1fcde736506436328296752008
401	1	367	\\xb82fddbfe5b03fca93113770b980e356bf1862f9e374692315a666c546f42db598a759b26e0415baee2666677a89cfffcfb08cdd40bef385536613cec05b2708
402	1	140	\\x0a0e37b3985a4e3b15e3e0187833f95dc40ccac31dda9dac80b421a46b10e282f5337ce8474f4db534abb35214e8e432d9a23c52f03be4f8777a1b1b648ae606
403	1	99	\\xc0bf18b8e3255a73a223835322bb3503f7e6c48a514df1bea65c058edc926f303545edf5fca70a379520ee5a219245131d6912b117ab804f338f7bb20479500f
404	1	398	\\x230b7714a49f3f7efc40f59b9c3be2a93c62b0706b5424ff2cd441429162ceaf2b21fa8fb0e5fb0b0c25c1cd494f1fba8b4cb652e4de54adc3694c74a801f40c
405	1	220	\\xbe68be7187421df52802f80e197d69f8042bcc19a7cca2f020fc2d92a62abb7f0eb6be913dbfacd0e8b088a406a8b1dea2aad44e68399e624dab13daffff3d07
406	1	39	\\x5ff448682958ebeb7bd835d6946071dd251fb834304fd4e6ba4bd89ae8889fc5f3417976cfdf0c504d3b92557a94f2544f286982a0d90f3aff9d24bfb8821400
407	1	282	\\x6f20f21102c7f7954c59f887b83b1364da2bc80262fadd015ff4021732d87530c49d04e4f7074a3c19fc9bdc58e4d36aa586e030448d87093b6af1433b9f780c
408	1	73	\\xa0892fb50463fdd80f19bc40be9eed48305d1a6efe58e864aa7b479cd4d5175c26f90021c5a3b0a080ba3e11835fed8058a0a987049c1396394884a014a43d01
409	1	236	\\xedc44eb8383ab55069a2f91f1884d50fa96e6b73fa6d6247397ec6f3330ca7ed6931e123c57f4f51ad867d70d78428cb67bf71c4b70595504b0971a629236309
410	1	304	\\x186eca9e6a72f6d97a376f7406b5dc11614a0fef4f92e2f26c7cc3c3917d9deb1c67f598c216ab630a513420d9a4a97ae531de0bf9d532aa2a757f7e54b36008
411	1	123	\\x88518c6139ffe2cd14b71e183c7662335840b9b2e7d4bd929e5205e932af29dd235b2666eff5fd960f9949aab498157b84d98528e002f0239da5fc767a1bfe0d
412	1	85	\\x2a3bf616d4321705e4a1bc955de24aa22a2fabb78f1aa84f124edf3044c3a95ba7c300b3aa3fc5453ecdf408831cc70b6eda3944fd83532027ee3ea131690e0b
413	1	403	\\x31bbae8705f50936895001d22aca30495565b9d98d2075fdb40d834d49a6e683d87a26064c57acbf921bc3c0e5e813a65a9ecf05ac5ba4285494f9e83980be0c
414	1	295	\\x6200a2e31f8daaa75e679e9bc70f1bc216d05622f8d80aa7eea6515da3f085b1025e564d37ba9b2a926f6de260fed8e4cb259a77488569e2acc265e8f171fd0e
415	1	303	\\x59e67794ff6ddef95ef46629e366d383555f13a1993e4bbbcb780100b51b491c2adc6aadd0f39edc08212dab0ba9c32c943bdb14c154eb375cdc8039dea0330b
416	1	327	\\x310e02c8bec66ff89adae2f31ac1581ffdef90d780544e94821221204bb413e416b654e0404fdfe772a09166651f415f5695281216f4aa53c75eb4335a816f04
417	1	50	\\xe8b2695cbf09e9baef6f67c4906ddce10a9a212fb27b0a25e8ce2bc5c5069653e51033b376b8d1a578eed464df01975000340fbbb2fd884e343f792ebdb11f08
418	1	80	\\x8f0d550d5842247183c7a31847bcb639af165c0530de42dc70f15d0357f59fd10dfc51505120e04b0eecd6f59ce94112e67096034092e9201acfa8534cedd509
419	1	74	\\xe4c14d2646ea0f61235fd27ba0c1bd17372dc895c60f22fc44507ef7032c237b2425d0a956c9eca7d030b9ef192c88f34cb2e2b35d858384d92925e337143300
420	1	134	\\x95949caf7a0a56bd45ceb50da84229a7d47f07c608d737a81a8b4a20e099f2e50ac826c448d222976ea426e3d0bd8c55ce0ba24d7458a3e85d20da384257e408
421	1	70	\\x6b59f5713dc6924f8af71673ded39c5ad1d19529129c239e3c6cac2fb586e200656e03db94c9ccf91e043d8174723c9ed2ba90471be9f21cc7588bc9a9475108
422	1	29	\\x5fb36a6520c0f6f8d1fe923f4d4fd8beb9f663c09e7027f84171667752bf4df85eefd44bf69bf4ee01de3a0253708aee03bf85a9c53c327919505d077066f505
423	1	136	\\xdef2b40e41f40430c078ced4ab9fc24e31537714ab6a6df2e8a07ce7b3701cbba9ff6fd800a2b9f8183f447372485d38daf822ddb1df1b2a10fd658e3cbb3303
424	1	128	\\xd7fea5d7254b4d3027178b8a8628459a9805f10d3d104dbf17528379dc976e44bde3e86f18600fb9eb80759d0dd3e9b4a37fdb6cb952a10dde0bc4f8ef3af00d
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
\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	1638357456000000	1645615056000000	1648034256000000	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	\\x83515e8f332f28b8c47b09e2a3f9d70fa2fec64f8b791bc6679f2e511b617580dd91b0d35a5b24891f9e031c1a4f71efba8ba914165bac866422c21930da910f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	http://localhost:8081/
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
1	\\x8f61f6010a1e859c5eb9cf910ac192df8300c6e4bc26145745c4c32e2b13a581	TESTKUDOS Auditor	http://localhost:8083/	t	1638357463000000
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
1	pbkdf2_sha256$260000$LLUitX2y0yG3Whx2jSGmDb$umW3rBTl0RW6giOTBjbV5UKaJ/t6X3QrB0n/NqOTDsM=	\N	f	Bank				f	t	2021-12-01 12:17:36.902401+01
3	pbkdf2_sha256$260000$dPmgMy887tyJjzdS3XuWZn$kcZY3O621/Mb6MM91weCGMNwS/a5E9BESKbu6qcs+6U=	\N	f	blog				f	t	2021-12-01 12:17:37.139416+01
4	pbkdf2_sha256$260000$deUrrF7618hdOCAH3UEiW9$Ya2WXFOpEYB9jH5A8tYlQpm/zTJntod5qmNp9rLziCo=	\N	f	Tor				f	t	2021-12-01 12:17:37.258273+01
5	pbkdf2_sha256$260000$UURKh9HJ9T5ZdLPNgYkcsf$8puUjHs9T5gdQdhqvy6ykn/EPDAXrq/Iqef7gJoLw44=	\N	f	GNUnet				f	t	2021-12-01 12:17:37.379676+01
6	pbkdf2_sha256$260000$R9w3eWH6BTHdU4w8VdCUP3$VirBa/+rgHvDX1rpCEB/m5XbmycTwZHdv1WLJnb0W8M=	\N	f	Taler				f	t	2021-12-01 12:17:37.49739+01
7	pbkdf2_sha256$260000$Jv72h3F1lI2Td6Ms4hIPCX$+V78S3Dw3FhJhm5ZEYkEQCHZ80UZxvP7Aqd1KPzj0K4=	\N	f	FSF				f	t	2021-12-01 12:17:37.618781+01
8	pbkdf2_sha256$260000$C77KUfLntt4p9uxAMsQsI9$yIY4dc5tfevvDY7zhs1sTaUk7tbRY+ZAoA7WACXvWpc=	\N	f	Tutorial				f	t	2021-12-01 12:17:37.737642+01
9	pbkdf2_sha256$260000$d2tHpHlC6aTyKJr1UqbW0i$w9a4L/MBJbU4okWhI6NIXzA+AALE3YKmWjNMbVyhHBg=	\N	f	Survey				f	t	2021-12-01 12:17:37.858298+01
10	pbkdf2_sha256$260000$xTAHbfXsxAC79E5EdSkwPy$28uITNUfA76EqzKE4Z2tfAxdZbiEUq6RAs1YpQErhSY=	\N	f	42				f	t	2021-12-01 12:17:38.300851+01
11	pbkdf2_sha256$260000$14MnwlRL66zQfq2YVwsATq$XsW3DT031dfqOfPyNmWO1c0+TqhGN6uDWAl+Nt5fE9s=	\N	f	43				f	t	2021-12-01 12:17:38.733731+01
2	pbkdf2_sha256$260000$cdwxAdXgiexwLoE9wiBdQc$NciHJ7OiNr330fm3itFQALnlDSls2bNITNdITzdyD0o=	\N	f	Exchange				f	t	2021-12-01 12:17:37.018185+01
12	pbkdf2_sha256$260000$RKPf7cG2OmdT2kXSds0m7E$zJQLaNMOSlrrPZsPrfOpVSiHECuZCAy0iiX9HJcEaY0=	\N	f	testuser-v8fyaraj				f	t	2021-12-01 12:17:46.174045+01
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
1	134	\\xe0576abb39e1b7af10ddcc61f263ae575b59eba64a0405d7e35cbd838ef569a4a044becd58fb30869dc582fa128df122f87a527eba62d46de4561c47ffdf1709
2	327	\\xe7efc843ae73c896906d214a2e03fad52701cf60da08a75b49627d102c31c642794d3b4e24f6d954ded2a8f938c394083ea40ba515886dde7211080a7c61d50c
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_restrictions, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x05b8030ff3aff3a2cbcd1470422161363e8f5b991d0f967647ac30326413eb8b49b7aaab65d7dbb144d524e7a5454c9db4fb90eb062aec39858ecc920f3f07f2	1	0	\\x000000010000000000800003cf0f9a1cf05243d5cf0b04e85cf79874b09a83e388059823678f172509e9f6d060ce9035f89fef600fc51af04230bf0b5ac1c48a51f851cb88b3a3a5bc7943a1dff6744a17ecf225d5b49b19183f82b92f4c4f2feaf3430fd020b156f8be4762b606f9577253e9c2ed8b35ea84ed838256b38ba363b112ef75109e942c4cdaa1010001	\\xe9d5d5ee2f36186cab8fc2e1a1c6e34ff6d2ef2372bb92c218434227af58ccd8cfa914457f1acea15d36d98f050d757c149f15849b6b257a3f0335e4ec449f0d	1657096956000000	1657701756000000	1720773756000000	1815381756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0c248f5f721cdbaf8dcbe6acd4b9fb13fbfeedcab4db5e25a202a9998bf4e0f24a22023b849a21e90a308cbe02baeb79bad08ec6ec4511729c643c1de9bdee5b	1	0	\\x000000010000000000800003c60656664e8cb0fca00b2d57b68019a80906426fc125a8f1a2b2f657c429d9550d18acc9e5ff07707283ee9dc2a3f8b5f8303b09e4aa7476419fe2b19085106d5b74d062503b73773be26eda48fd4068e6a3be352ede0b700bc419f7f5b071c0a86e1d19eb2792f675e49b6178ee993b3720211028763c32e047bf9a72d79695010001	\\xcf99c3575c196ff7a5ce65cdff75d30632dbed5b7d81124041405b01f8873829d7f652b2f0170a14f4dd9ea522936b2bb8c6353111574eef6f2127d78951df06	1657096956000000	1657701756000000	1720773756000000	1815381756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x0d20566a0b49084bca5b51c1795fbea46f813d58a89951fa9c99de77146724fce5b96ee4603bfb76a48d4d4fdd0955a873faa2969df14cd1f0235292172610a6	1	0	\\x000000010000000000800003d34d1c48ac5900c9da162f411a0e78a6e2900b16901b0ccefe72404a0b84a694316d885ec1f413f43987abfffdc673799da6559fa135e4c82210924e1ec64c94c55c8c6ce7564d4e10b0ed18a1a64ac14dee8a287abf7163bf9e9b5fca391ecc828b66900cef842f4be861b4bd487ad3d21589b44c49a36fe7a937f35c61a155010001	\\xee3379f8b75173212a1b57f817048a7db163c6d89e7bf29c9ce4a7b585f051194db014fdf428539402b2274447dafefa0391773536dc2dc38a177e7c84dc660f	1644402456000000	1645007256000000	1708079256000000	1802687256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x0f58f465cb9492c704805641776ebce2ca0c1f27c784ed9b4ee47fb93eb90cd8b20217c119182c010fb94323893ae0f72a7958e11bf616206153be746fbd4eac	1	0	\\x000000010000000000800003c6d55dfd4d7d14e253c594ae3aeb54b00cbefa21b2e4a76ccb694cfc6eb7f2407cf2f034572f0c02122f1367817cf69977aee8e6c69e696da3b2c501d8436b6a47106aa1f4c7256ef10f165bc5975a1edeb8db46168c564e442df71af7f35ce17661cc567411d41368d944a1cb89ae5dd0d56b5d496453ce27d55694f2e9271f010001	\\xccf55c27b937c3c0a48cee618980815e24b935595e4ef143376d0729779c5bc5379a6dbeaa96ac81b1e5280e2a5e1081f998ff8f670c877ecb94d5a51b26b50c	1662537456000000	1663142256000000	1726214256000000	1820822256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x108ca10461a6f343fac839feaf38e8ad8d85aba9b227afb5455021681e06fce072010242a5542051fce1827dbdc7e65cc3d279507288b8c91c16d8f5988d207a	1	0	\\x0000000100000000008000039da00256bbcdeff062ae6b5e7e17760bc3f0a0a6c91d8fa90e6a4a1238e74cc8f851cc32aed5b0b143eaa51c4e792cb46898531be706f099005cecaf24da04cfd7d2e3a364cfde331b864b733487e3f426be6f06bf0965f7efbea832afbf7a49e54c3da818bf9ceb2967022b2720397bd6e49fc7f47eab130c98768c2bbb8717010001	\\xa74e06873304fa86854291c367e05bb07d3a5a9ebbc0d22136b02e20a6744d95989fcd47d0d39a98969ebfb554c0925888010e3dbd003300fb8e5ad29bc00304	1654678956000000	1655283756000000	1718355756000000	1812963756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
6	\\x13607b1a67311a98e8cb8eb70e59fa965aba9e2a585af85a644fa7efe1ddd848fd24ad0b9a135afa87938f9f548fb5d0c59e2243da258c2b76dfe2b1c7d09ce6	1	0	\\x000000010000000000800003bc3afa272b0233280ed421413648e98d78f69806c864659c93b65c05691664e2e591f37ce81a31e4ee311a9dbe522cfdc539194012dc4f5bcbc49eb179ae1e766cbc9fc33e79d433bfb9ee90e34db534b57a2d822b6bbcc26b16f5a5f0703ae7cc4f6c3caba91e20ac311ade6b203278881fb6d9c98ef8e43b7c56257095d9cb010001	\\x99a9696d6fd116540c3f92be09e722ffa438e222d2b3f35bbfaa2e2d5eace13fd65303330300ea79c6af18a1c89d44efef92e16e170f6c40079f8c7d56fae000	1640170956000000	1640775756000000	1703847756000000	1798455756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x145831846b64f24a9e621f03853352aa4a3ebfecbaab41b9dd35f26a9fc26472786ce2521800a59b7dc257514a1035cb1975e079859df9f9a0ecfbc93e75ecb8	1	0	\\x000000010000000000800003b48c47762091ccecd1104c026b33274649d0da0f9a4d7c71f9c47fecda566a66d8558c16694c4b4bca48f3c9a96799c0727ba6cd5f8e2e2bd81ea5194c0fea0cc5b334cd0d8a7c72dd6c5525319e4b4af3a18277b4630058603a4cc91f84b377197f70b53fe3aadd85ac01de37b5013f7a4d37958894d8588253e210c563e025010001	\\xa2bf54ab2fc3b0e383b5aa7b19252a99e8c69f6f056a5eb1fe1d2bb18c613056ceba741dc1e190a050bafc0e90a5101b1232a76ca8df1ae8b44f625381a9ee05	1664350956000000	1664955756000000	1728027756000000	1822635756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x1624ec1a74cdceb45ac81c1d7473c39950e60d1985746020ac7300b41caebb0ee5bf33eae5793ed85600100dc2783e70260dc938269404d29f3987809bb2f733	1	0	\\x000000010000000000800003d1f166698fb6109b20edc0075aa465acb340c553d762cdc583106c3160cb4a2c343f404ec64685f9f035cfbdea97a8bebbbbc53e1ac12c928a47d69539e5ee2d500af4e460b7c06f4528c2a3bfaa19d6fe81fa524b4bc716fc50a73e570cc270c8f15c9344f30ae9fbb6fbede23b4e211122a175aa0f5dbc05a6a895b7f6efb7010001	\\xb498d92a5cf9be9a78589cfccc5ccce6c174c68388513f91ae4308b7c9b56f37df76a108891baf5d06daf8f8d89f191c6125ff8a786856015d0b880334806a0b	1653469956000000	1654074756000000	1717146756000000	1811754756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x1938268975805a6d8acd6e785ca2b3ffc13bd8ce56e8bbf837e2f353e483856d49d4be7cfbe814b789e473efc792b29c4134036c3eb583f77abc13f0024b02e2	1	0	\\x000000010000000000800003c9ee4d768c6df2db86bd6534796bbb02ea131622685e90fface2c564f2637600e28bd9f19314d2f57f7ee24f2737c3d4d63a6006cfb894137c398642c545a66da89d20a69d07968db896443c1c4548b9c4c399ef63bb1a176e57b8df0ecf3e8d0f2f05f20b71875bf83a447f04aa4b9d76e6921df9329a2b4ab98ce247c0f5f3010001	\\x6aaab44de224604879fe3a3ec137666d59c50341401c69b95d391a45cee7d9bcf71ed33681d63ccc39ee152e9b5b51b92364cfd1f5df487b9645fbd0a76c5902	1669186956000000	1669791756000000	1732863756000000	1827471756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x1efc62413b2dc16ac440c24bd85c07377c758b7a323317a9d4cf1975edecc5cc3be9b7528eca39238c091a69e609784d7ac0015e714235032a31c4736db1c7f3	1	0	\\x000000010000000000800003dbc16a0eeedfe1faaf469e407453500693880685b3c51414d4ad1085b0dcce2aac131ce8cbb412016ae601595c58014400ebb84a1eae56f36b527ce8cf99abc3672953788c497b452a13412e7aa5c577ac26be0f1915d1c8afc41e272302442a5e6f750001467f7940605ca365a6f59e94e8ba00620621a85532d29a0b3824e9010001	\\x47b7c7d94fc7dd09d9f5b853c6d38f2873865c7e8a35a868cd2529fdcf0ae7bd8dfa2227dfe324124532c1f5c2cdd8c312eed984871fa4188381dc8003ca6300	1651656456000000	1652261256000000	1715333256000000	1809941256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x20ccadba606d37c4f9505ae97aaec14cb925d83384d5994ab83ce2f5914f9c0c95fd3918b6940d25864002aa59f1c7e16d4b9df39bae21e0c9d9b2f0e9313dd8	1	0	\\x000000010000000000800003c4bbf838098b497a3c990a06f4a25a55f6d625ad194d51cecd0dbe655e62974640397690e692d39f154c4619cd07b5d3e476f3f76df3adeabda45ff113c0aef3672e4d163d65454544c6b455c06823f849d1bf93819666ee36f3cc195687acdcd7d465c526776c718afca69750b8003d23a96651ce398e2fa88b45fdfd665679010001	\\x73b93902913e1497cee4bb065398c42c53f613175e811a062eaf9447a68f205d1dc74ecae9f61db446e32d0266844a63fe56055c8e511c3de6ba3accb5a1440c	1640170956000000	1640775756000000	1703847756000000	1798455756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
12	\\x213471c23bd73c23be8aed77647fd02c448a9a8a747d528e4c9e1b8c4d60640afd0029494ad5fcec2bd929c3541f7c9374c26bf889c17f8363a743d186849c99	1	0	\\x000000010000000000800003b383e23ddbb89d478a536380022d0068e5206f7f17de8b6fcf5e057548a9103c5b7ed53415866d52e20069dd28913b5ae31bc18152a22f7711909ae1f6749f5c55075d5121a67a0b649b747c044c72a222141b080a0220267fd54bb0ba38f812e5cf057f5eeb5cfe57727a6827a1997430d0f81f9aab43ebf9e191a5444db843010001	\\x62b296a4fecb9109b9f62b343d55d6baeab8b996bec652f1da40ea78809dee97d619a34c8c32c7ec857f9f6d11e826b3a4f03798714e6cf14838b2ef1a7a250a	1663141956000000	1663746756000000	1726818756000000	1821426756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2160262174297fefac72d4cfefc571648f1f731186e7e40ac69c74207bafe5ee9c8a50ad9d2098a29abf7e6dc6cfeaa1b3a8fff42d3b614da3d9dec672c23792	1	0	\\x000000010000000000800003c1cc5c7c97e66921e7e4924b65e0fca1257972eda9c0b35b2ce82706634a652b1d22172123af3755883f085997a54ad62fcd66d01ebb8ae3aded789c13a587b55f63d0ea824a50cd8d98dc5abf5becfb99ff1c37508a00a26c011b42313c9cfa37e5b1d5752eaaca72d89f817842f92e829750d88d24bf7a7a25599c2f8e4a45010001	\\xda30fa3c50096b0b207a8a7d7ed3b3bc3256f65f03cbf76a6ac084d9cdce35c29bb0207adec0d9f6b4b70f899e931fcc694e59e3eb1a07f5ee54dc58284eda07	1649238456000000	1649843256000000	1712915256000000	1807523256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x254018fbb3c899400e7ae2e51d2d01cf5ca0b7f33fd50408509cb6427ab8412b51c2dc146089bb0ebc9b012347d1975317c1d97e98199e1be70f2342ab275036	1	0	\\x000000010000000000800003cf17b39292b8f75c675e1576d748948337f75518306471a8e4344493d8ce91a03e9f0968402c59d46fef4836044abb3c171898adb257c2e157337ab7d2523d04b51de31431ea14ca096875fac0ed06d88ce524a5a76e0cde2e0b438cd98bd700f0f9e6d9cda18bf93513370b21cbcc1002e31153ea6c5eec638e79e5f04f14e3010001	\\xafb81dc641e878de7f3ff095deeb93177f5157f83caf11d144604ee921d1f647dfb71818e99585f944540121fb3e96581c77c18510437ee0babd79967e21d90f	1669186956000000	1669791756000000	1732863756000000	1827471756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x290436c81364461d40abb871b52dcf4678c8a864923357923b3581ff16e20a3b929f5357e20dc4ed4ee7caf75ea317ad8f07b2b73c1fb9e8f3a190634674413f	1	0	\\x000000010000000000800003bcd54df88130ba0f450534e1a71386ce123fa90201d3c7e5544af13799026001e5160fef2f0c59c7f179192f8c42a1d2b07c414f97f0705e1289f4a84bab45b394ce03bdd0ccbdffcd2ef382d26ee295efc0c4f7e1ae2d3af6b78f68e6c14aa30c5c5d878bb695729e84319bcd7bcb10836d46259da70af197b06117db16d559010001	\\x9bbc986cc890b61f105fe9c5c11c2e1cf4750a08a2105db77c3ab3ac3727170e867fc7426639d05e92becfcfcc1a6ba0208f35d2de19796c5b41d7c05a003206	1647424956000000	1648029756000000	1711101756000000	1805709756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x2af41cba231425185dc123273c5dc124fa9590d830de81c244817eafb5c9d8220d161155e45fdc337a2744568e916f2183ec24bfaf8b3bd9eec602e85afb982d	1	0	\\x000000010000000000800003ce73e8833830e5272ee63fcdb7d045d06757c69c414f8ebec5017f421695581a329c330ae0fa0ede3e3deb3571290648b3a71e8ff133f9512eab487b910a760693b3a7062ab0556c961e2b4191a1c364eed61838bdbae64dda9a4ad824f9fc5555dcd7d41a9181692acf86876b30355f59ca23b5000cdf8a3ce6f67c1a29dccb010001	\\x7b004e6cfaac5bbc048d7453f2bb2118de08d7f87ab3b61b6ac5a2a96b72cd4c295c47e7cf658af91e34c2c611d0f34f382f7509b3b88db3c2a800fea4b22601	1644402456000000	1645007256000000	1708079256000000	1802687256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x2dc8f1da29886736b3349054c2ce8a90698501b3e94f728cece15997ae6def726f84d420c67ddb1c885af053981763dbfb89763646f479e003d03ae630e57e02	1	0	\\x000000010000000000800003cabfc366ed786e8f0db6127e430094529606a6695b81b34f24f1c0e71254a332037552c44680ea65b3fdcc267a507a83643b8507ef6171bdf12b244d0e449dddece9e9b43708e42edc160f148937dc996da57bbe30cd07e7c68231fc2b3319e651b3aebefe3e38dcec4ece35ed6bb64586a98ef8c7173620df8ec3368e691c65010001	\\x207fe11134d941775168464489b8191a3162a5d02f11d8882d2f10f859fa06a2594d5c28872e59ee19f7b3860ea84d2de789187082871c6bfeafee125554d608	1666164456000000	1666769256000000	1729841256000000	1824449256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
18	\\x366074dc8cc74f97f93daf074ee670241e56e53249e7b8c4fab7f28cc2a4cd78dee09401c55a3758def350ad964fc4d575c345d70d05be9562dff24ff9d85338	1	0	\\x000000010000000000800003c7c97093ef5a9367169dabebad58d51864ba06e794a678a87635a9ffed4c8f64745bc8ac2043781960ace062ab6f606cba3b5b66a578f0af3ba97c3152afe25b5aa03508d68e1ab78f0e6d1f627df15b324f2e11e1087fb41caaccf37486cdca7d4203163f3e41b95d12e7a8a4d97976dc45d389a478ba93391377a33277b053010001	\\xa4f7f98671ca9667be8cd9a5058b006426dca3765fafeb79ba3f3988ed29fb04d733cbadb01236fe831439565f30eb2ab320da98b2cf704f8fad23c239370103	1666164456000000	1666769256000000	1729841256000000	1824449256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x380ccf02912f8e4c8eb9d43d4aa18ce0ee23086cccce400c8a370423d63e3c94c4e4323dda47cf4d2218133f8dfd38c585abdb8cfb4e7ae5fde8343b339976c0	1	0	\\x000000010000000000800003b49dc98414c7e6b003549ebe17702fd0fa656a4925fafc880059acc9ee64f1c4b4cd08234457d9f96df48606686c0fb80943d66b1303221a4066c093879dd07b93ff4b183c189b126e088c64f3a41986beffb58f6d903121db00a72bee21d7a154c2755e5ba67e1d9466385ba70d165e0ad27f30a7857470b6b40f5e3e4be209010001	\\xc6c6ce7d88afdb1c0b241a830fdc1a6f18a48edd5e9c4b833c9fb998fa4cd20b3ae423ae1ad8b3ec24cd9704790459da9c6bd7cecc0418e51f491ee9952a5c06	1643193456000000	1643798256000000	1706870256000000	1801478256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x399000e5a7515582e10360b99c53de61e8e3abd939b056c8caeb2e28a75d340b5322091104fcb15673658dceea549f97495ca685d12658ec1937f2270165bdb5	1	0	\\x000000010000000000800003daf5813b981a539a95ba9172a6daa203dd702eae3ae3daf88abb4c55e0c26e3aa963ebedddc269cae7bcf789251993c44867ea84ccee0f9bc6466cc0650b323f9035dc485774f534f3b891965a8c27517833e08cc8f56b6bb6e7fecf5e5335e2e2f5291764247eaca3694ccdecfaeda44eabfd8f93e82cfea7703e9abcf4353d010001	\\x962b39a51253ded6b16db4e3b3f014f0abdf14a76dff1208776ace84c2a766da19fde1cdeb499bcdd83a26f04a5fd7d27c0e8eddc05211298d3a89dde2ecd202	1649238456000000	1649843256000000	1712915256000000	1807523256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x3960725f1ce75aaa8ad5963dbeb2a9fa06af1afeb1f29f07ed66b7d667cab0b5233328f565ea1b03d0bc01003d8e1f077e81145311c6520acdc792f5689a98e2	1	0	\\x000000010000000000800003dd880158bb3a1da24e99c16a03c92ff302cab5e010040960a27bffa576d48f024c98412482cafb9350b8253513fa0a2b2c5741e124eddc1c7e30cda22f0b30ec6d9e932fab4ebe6294bcba477b7d9f84c61fb5b8fa490f63f632989d4aae58acc394cdb9018bdee5093ca60500f1a68bed966d9c7751bb17fd4a120ff7b9a667010001	\\xcaccbb1c5f12e5d2b9068897b71c08cd2ebc0e212d86a1879036d55a63d758d28139051c30a373b8703f98b1075841853f0cbe30560b2c1ac6b93edd23530108	1662537456000000	1663142256000000	1726214256000000	1820822256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x40f087e4a23e98e8c68bc3d6414ee15fdfe33630c4e315c0bab45d33efef65260b35d1b1f9dd31c2685578d95a8628091a7024b473e172fccf5b53fd5edf516b	1	0	\\x000000010000000000800003c7315f21cfdb02673c35f200ac264b5e02fb17eaa3826db2b28dbd223db3315bdedb68990d90f915c5f7c51c82042c8aa7d6838e84302e4b1c5957dc8330e2d5f658c5ee9a66f85d4575cfd8071c2c3ed6e3713e2438cb0edd1f5b5de3b9859509f97bfffe7da7901021fd0bb924246625abb716a617a8f9d5b56946413d602d010001	\\xe4f63291ebeed96b60b32a7d76022ceca64bd8e13c4e5a5a6d1abf3b5e11d8de6cf828eb156ea67da24fd4d4404f788b64a13d1f37c9f72ed18df9b6ef99cd0b	1661328456000000	1661933256000000	1725005256000000	1819613256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
23	\\x42745104fa912d32fc9aa491350c38cd2dbf61c61a95b1973e2be63a97abdded1d09c737461b2d659814e9076a003b2bb26db0dd534e1ff3b9524576fa7372ce	1	0	\\x000000010000000000800003b337d4be41dfca74ad53465e611723d08a1a692f3ded9f99e7f90e69068ab2ac74007bab698ad1c615685035c38b2067005d2f5bab5872088f15aab3372e708264a9d48373975a906c3d7a5ade5aba2220808ace5c6d3501ab38cff1f040b303f547c677d7ae105f8927fed9eaa142dd9d97aa06c82419bce5fa84d484f813d3010001	\\x7f63f45d9a66a6b55604c21f3e41f9737ce71867ed1e513fc244cfb6fea34fdcd81456ae93a4aba78cc35b04d9abfa4dd2195047572f810a8b442b5e230a8f00	1659514956000000	1660119756000000	1723191756000000	1817799756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x466c4129e96878a7bc127f52e4d22f8b6336a2925ce7b2a7fedde2822954b6134b53f3396b9108575f0fd1a50078b40b2d3d48030f806814e2f6e0ca2344bf12	1	0	\\x000000010000000000800003cbfee2459343f602a0c45d95f0537255e99be5c3c0f99f2c83abf99ea0d36ce135080bd4d7d56d18a74a72b95c18b715d40357c818a82b4d6dc7ecc2ae3eda2f5860c08f007c6b5fda6950e9ca907ef7f0f6c77300bab730f3fef65d7997840a9331a7cc2a49c348b858f14003c6ece395e71b683c740eacf2e792097fe48655010001	\\x8c11ee99c4fe40cfae8e3b3380ebd67d978022a46510b4854d61e97646ad0ff207feffec08adfe5e51fda403d7b8c677cb12eae5152b62e19587c4cdec92ba02	1647424956000000	1648029756000000	1711101756000000	1805709756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x47e020cf2611a912963862fae0fe1d278354d10554b5bc8ff1e15492410f46902c3b3c53b44549054aceca1bb0793a9c8bb7ac70f66fa33b7849fc6d95559ebf	1	0	\\x000000010000000000800003c0505a555940676851ce89265e1b6707e6fd989c44b282db086b543e006bdaf10b1efa26f232afda6751f7a440d83efbe3f5c36d45e38f28af67e2d0bcfe3609d9cbb2fc64e4020fa8414bd387dc59b3b9b567f08d89c81193bd8b7418b7dc1d5fd2d352f1ffcd23186f55e47d06fb33e8fd96caac191f3aa1f5034076b8e153010001	\\xa3d6b67676258bce1c56e01f5b8ce2543263074d650dc1c866407b49dc467c4cc8fdfd3426394622c496cc91c9f70b7ff1e01631b26264f4b7475f98c0b76101	1663141956000000	1663746756000000	1726818756000000	1821426756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x4b6861c986cd9f60634f738cbce8e9e3cbe31c993e9513e2dbbafb64c02c3467df714124550fc96a40673b295cfade34a64ad0e87e07e85cb520566e3c139275	1	0	\\x000000010000000000800003d3d7b8502b1fa749daf98dc093662f9d56903c17c99935b3830d38ccb4ab772056878b41b5d25058486420a03bf13e936b53e7f9dd62d45a5b068270769162c0821bb281c2a0d83f89e5ef1097f69384006674f208c80a3d5f25918558fbddc6cad7ce7de4d393a740d84b8baa5a5b5dbb4a594243a11e80c9606fe7565fdeaf010001	\\xca3f57336dbd46d4c7b9aa48370ae93f5f33074124284c32eb84326adf029d35cd4124309f5545450563d9487f46f28814f75f2187cd21cac796435097aca60d	1662537456000000	1663142256000000	1726214256000000	1820822256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x4e28cf872666eedad1d289cb5f1541560a321c2820146e4205cb5555671d813e1fd5fefbcee06c5cc4e4b23d2cebcc09aea0359c1e333ef8af82536df0ff0856	1	0	\\x000000010000000000800003e510219a1a2d30ecb7f005ee6815fbbeb251f60da2a6816217cca7cc0ce6151585e2c90fb48312175e91e11dd52910842c4c453ae27dc83066f4b70a9f587d047d7dfcca2913d11c8bb56a2e51e6483ff94bf81b4fd97dae611d941d592412eec77f8bba1411f46226f477ff122fbe2124717cdb5f77915518e2901d5bf9abef010001	\\x439f4f9405960602bf5ac697bd6c14122d3a5dd6ca7f8831cd90f6b8d50e87c5f7f7e3bc8951fb48e361a46920865fb3fd09404c0dfd20dcd1f29087e107cb0f	1660723956000000	1661328756000000	1724400756000000	1819008756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x4fd0dfc9140ebcbb428e1d61e23f4d1107c4c77277212f4ba5411dc69fe99b076c30f237501e819a0218f35bcd3519ee2161e75250028dc002260fb8eea39dde	1	0	\\x000000010000000000800003c9f5db2f4b78ec3bd5b5be816858c0dd9d8022c815ec0b9cc90a550cffa1c502b18b2eda99dc2c35cb184ed48346c7bb7bdb4069efa8e668d0df4c3e112bfeed849f8b278532c5e94c9fdc3134ecbc0b48452d7cb0b2b331d0e3b28bf91a3ffb8942257dd9b046b1f76bcff973da169aa372cd0f606261311e3bd160e3bf57b7010001	\\x1139db18ee12353bc2468051e5bc947e5247fe5572f731d067ae54aead44ee26a3e711c664af2c9cadbc79841320797078a44a790eaedb484e1cdb4fe5a3fc07	1641984456000000	1642589256000000	1705661256000000	1800269256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x51a0279eccace49e202cba6ca3b52b9db181094fe3d808ead7f48fdc43ecb4a105d5d0bc94f3f6a690a43d13a41605ad895fccac1635d7abc450546783657b3d	1	0	\\x000000010000000000800003beb2e03bb57b9608ea2e355964f4dbfc0f9179f13eef25e969534f69d7dca8f4a56b08d231a8a07e4f4fa44ef9df055bd1879a64653c1ad2a40dbc1d320aee119cb19dbf4c075f5ae5aa0f988ed0a820c27a540130f95f61ce83578c31b8010cf4e75814005079f100e65934e4886048953af2793be86c2951e615994a87312d010001	\\x352c8f698b4bb2ee672cf56ccba4c702f5ad887a57a20e4f9086f21ea0982c28b0026fe57e3b55e92097455bada97c81e6f3307a136c6e0fbae7a5a37918ad02	1638357456000000	1638962256000000	1702034256000000	1796642256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x51381e98f83e890b72a80d91a0b35684d7f3fd8ba8d7773b04bcaf02c6b170edec53c11858a2cfe20ff26628db8608d3380486a721e64b6857c1c00615b51916	1	0	\\x000000010000000000800003db00cd720810d7507c861a7141dbf0a920d6d26ba7e91ed09ad5ef6e18342eab74d99006de1e50d0354386bc0e51124ecf327e0aa3d97b6b3f998196371f72e42bb4cf09f0afa77feef6b932151377b1c01fe8dabd38477e54ab55fbf55acdd719de0c759dd39e8aaece3f5a354a31894596b7dbdeface3d88ed2f2a8467d0d9010001	\\x33fc14984d74dbf9ca8d5d7c36416c192ec06cbf35998b74fd7ccae114f6ab4decaa49591c6c1878bf883972f69f933e38fbb298837dfdb4cc0b5fe61deb2e04	1661328456000000	1661933256000000	1725005256000000	1819613256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x51b48ac09013b711dee1cf9f7ecbefd6ef224052b48e810a17c6a21849a1a0de57fbb3a72cf78db44b626cd4d17fa0c601fde234760d170fed69fb4e50a84afe	1	0	\\x000000010000000000800003c75e52b6d6ba39b5e75597d7ddca9587a485145cd2f045f5d974ce4a40c1f887b434810e7a95116eb031845262b50b242e2e2bf1b4d073bdc882f744c8b9459bf9a5edc10e85917a61357d40bac3d3608eba2d12df1bd39d82b6ef64031dec73f630957ac4f797a831f480b7f8d222c61b65b36e7f7e4d9a9911ce762321d7b5010001	\\xffafd482c40aa4e6489aeb176ac91c28b71c1a454db4af72e0b9cfdd7e5379a84cf6afda977abf8afebef15df59491dcab2fa5a3bd7a17391eb1baf3d5923b08	1667977956000000	1668582756000000	1731654756000000	1826262756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
32	\\x5338993c93960380dbd65044abc7de037b876929b409825516d13ad56438f76cadb1c3c860e9779c8ee56283c7b812dbcd8b12b73e8f7139144285951efeecb5	1	0	\\x000000010000000000800003b8bd1ca2c0c34164f74617fed0e6b4a09fa242bfca6f3850bd22e8e1223801c75571f5b16efabe0bf070a5e3b64a664fc9f69343587e1072e778393cb5fa1aa74e7d1cac0d897e603cdb02d64491c35b49e81644d62b81ae310cd705bd813fa6b27a5eb43de00f1b5f01de93120130baac352c4ac63ca39f4000dd99b05910b9010001	\\xaed9b4093da8d4c282810d408e3ae75c2107d78dcfa3e8c65338f85f83427272fa9b5104bade3505e056b43b6eaa2051ad3e2c208a9e5acfe9619b9889d5df0b	1648029456000000	1648634256000000	1711706256000000	1806314256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x540cc62f1e1949855d6a28a656e2aba54e657c5b3cc12290fd45ec4470521b5c1788e7c98d6f750e26f29e9e953d9f3566bf19f00994118a750439eb02d4f896	1	0	\\x000000010000000000800003c6f50d7acdbcc874133ce6d90233d86c5bfcbc70394834ca3b3d644059be859b4bca008098bed863b44c046a832fba160333b5e2fcaa35fb9d3a60317f3d49daf02a4ab9d513e42c9f1ea940e4994a69ce07c96edd2a041f369ceb496a7c9d74456061dd37f3e424548cd7135498f18f0f9fef80297385fc8e86f64af3bd3171010001	\\x75860514a9039606eb1d5cce8093eb6131ae5d04dfb68ae404b1386a39693e24525fd6176b66f8a5e7b23fc5c32414ecc6234adef17cf92f42c47c0fc12fe90d	1650447456000000	1651052256000000	1714124256000000	1808732256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
34	\\x5550bd483c4336d086baedfa4c8911c8fe26bd7cf660c19aa0bc8e6acd110e64c63e238584a90fbe27a37bbe171670d375e09ff0b759e37c98ea9edcdd113483	1	0	\\x000000010000000000800003d4a9507768e11b4c2827fd7352ee0d7ef8a8b7405436d91a64df1f17df9dced426ea9ab18d87e8dffe61a7efede50df11c01d70dbb613dac4971d5be7d46697a1b64bff69f646359851d2b3f2625dcd9f55050ebd14d152c6d39d43992d5b0cd19b3272b6f80acc08a72dd34e2600dce4508efb629cd9fb949984b3d26a5895f010001	\\x35e2430b44fdcd15e3284dbbe988810459e4975c97b9e9b557cd0b4ab8852a6049955d7352e3883ff90a70c09440e97bdeb71e49b825b58f9d62a6a85a2f010a	1660119456000000	1660724256000000	1723796256000000	1818404256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x567c4a3cd37a0e28cf0a0d4f8504e05b4499b9a085d90c4a1fc4dd485141598cff7f9d6978a3a933ab348a7f5ae01ad06eb7ff5bb241c6f61db9eed0ab1d1a12	1	0	\\x000000010000000000800003a946bbf54974c9cda52fb00ceae23c8885924265df3381501b54854313d501131c86970559f12d7a43ba8343dbec4f5a6c2aff1211a18f1b15448daf591faa3242315dbc07bd28cb4f4614cd1c62e317510f7cf1166b170f083996d0e0c97205b5b12894523d17887d83120c4be0cc7560795ed00a7a8112285bf1dd6f969f79010001	\\x77d7ccb5965e0f0b7a792f2e40c8cca34c51f40bc20f61dcccbd09000827d528f265b481897e0142a2ab39a392d2ed8b0bcd558b24ef904a3c005f2e9c9d4f0f	1648029456000000	1648634256000000	1711706256000000	1806314256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x574077ef66be9b01a4635bcea98f2778231dcb0ab5b22be5c20e7adb4d12a51429acb462b9c9ed833f42fb4e75ab0d0f1ba9e262b80baa1522e21a52b5393564	1	0	\\x000000010000000000800003beda61d653b0b70875d597c3deab77bf6c93c5dc52183a28d4141a5f1ce846bfb61ccae0773be860378222d3593707e9c47fb22fdd251263fdaad228ed7db2d4ba04172e53227180fc58fcf254c10c524a41a545f9fc37e3a05ee2a80237b3d1acc64a618ab8b70a149764ce03a85631e3232b7348c97d3cae362a5bf98ba1e7010001	\\xd36857e4532c456c806ca86ac2a23abdb23e2ca2f8a1b7af302e5f56d42539cc94c3be2169e0b1dc9678acf6c0223f896f171d0199ada9e3af1fd113b0977c0b	1653469956000000	1654074756000000	1717146756000000	1811754756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x5c80e5ddba5cf8086a03070bc79e18512e138f4f8b123c3af9de2abe3c6435e33a5e90c43c5249df3f3ce2cc39a22f70a564d30717e8357616d523890dc2ffc0	1	0	\\x000000010000000000800003eaeb2b38b9d489a60840102500a0d4a9018b163afe76fd9ce23696ade71e1592774a0a407b2f90f5556b3b7b4744704b5e7972c03e676c1a25ce6e0dc1230de66e4af9f96c7ebd7e620c9f5eee2a6942240292dc1792e2f923737a2cc60aeb28f83926ba5b89fb1640e8c6975570821457c6c65278e261e5166652a714aacbc1010001	\\x54e3a067eea9d7b7cdd69888b3fc880b6e4cac019abfb65a639aff68f0b7b74d0735064c3aa576a39677a7ce390cde7c5a895233f684c152b89a590a4319f502	1654678956000000	1655283756000000	1718355756000000	1812963756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x5d74341a669444c33efe17bf7bae155dd6e2a057eca7d2a341c11144f281b0184524e96584db352c17b52b29bc2e3d33d51dd0c6e01838e3f6b3485877547aa7	1	0	\\x000000010000000000800003ba67cc80caa2f397a7511b29e01f9216e08f581f4b4519ac70d096a6f953f9b8c60e3b18f70c3ae9731f8ccab4e9bbe32ffa8f6d2cbf8632e0c8f5117b1a4b76d25fef2ce6cfe3d8f7facc22cee197375d24551f6220de5bd3117df6495c0ad584c59bf5a2e391f5cb3ac9336681e7e716e74bb458a717f94db5e074a1b8f4ff010001	\\xeea164bb71c797f504ac04ce31a5779dde5305782dcf300ed93f91c174ba4d30ed82bb0787a27a84f5b63847066496e794367ba69c1eb38905264bf8e722e704	1661328456000000	1661933256000000	1725005256000000	1819613256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x5f344299b7c794f05b5c7c47e4e4906825cc3e02e91c205e0674d8e1eeac540299792703e321b76736f5ca53c2a7aa7edc47d6122e4f26c885579b046535ccb6	1	0	\\x000000010000000000800003b278ef12b10e6279906ce46ea71aa31c716458165589985be9ac9aa6851b8c7926d6bc0b4936053f2bb4caa3f6881031dac028e90f75d5fb7e608950d792c1ba89982d8789c4bd1f61d9bc4706804a6a1afd730b6c698daea16fd4e4b173b8f427b0199cb5fc495d8cdc60588115980d7ba8c10c34f44a07d592180a4618b9a9010001	\\xf48ed260a74598127d68c4e0c3f6acd2b334ae0238449accb16b516895cebce0b5c18d0bc6e1f5fdb23832109001d7fd921d58b04b796a6526734f634234cf0b	1639566456000000	1640171256000000	1703243256000000	1797851256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
40	\\x607caed888607170c121303b22eec5337d8b85025406e1632a8f248cce22b06fd8ede880831d7e377279d31746418e39502febf0b07133d714da50fa159f3a27	1	0	\\x000000010000000000800003e6d24a5fe4fdb7ae7cf655debed56a562b2a1e9a3cce038b08bbb2987e788b0c493bc2e84fdb22461eebb8edbbffd3019e0ed86d1c3444afb2637de90950dc1c1b793e397a2fcf04c0ed65242c93457b6adab5849209e3eb49d594ea458b97fdbddc7331a2a30fa63a4968dfbd7f46e5a753dd8a50686f8f2b776aeb54f498ef010001	\\xfdc5439c42e37af9ab6fc8e776331af00541ef9792fdf56709748f01800a96516270c8839f855e5dcbc8ac163c6b4c71b44cf1a04c71baa6c12fd012e5f22809	1658910456000000	1659515256000000	1722587256000000	1817195256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x6450896696ddb92b1aaaf5008b95aa776e4435cd099748442ed98bd6cd8918979f20c32c6b2149f63e72373dec7a401cdd0795578a21c7106a0a2aa59e025fe7	1	0	\\x000000010000000000800003e33023f2e4f7478761339e4f6fba95ee7877a67f5b569136dcc96fe32588e5c4bf77fbc4c8d8977654eb9071c48b0bb660633ff1bf80ff4d586717da52e93ec60023c56e25777635d7d08b84f7f5cfe2af97b68a038ecf3280e7783f3454bed52a8aeea1debb3e5b966226e8f3c8ee1b8fbbdaf16cf701ec6ee280570b79c1f5010001	\\x4d8ebcf148ef0a3b658771dbc48027e325a04a66272dc868335770906a728375cc19ce217bda2a538d1d80caf810c622ec0ad23af320cbbecdaf41698a2c9007	1651051956000000	1651656756000000	1714728756000000	1809336756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x64d0d45f3a86e55012a4115610e52a53d6ac759647b8ed6927ae2d1fed9321035bbd6534961ca38796ea6790f40889846d2b912cd2c8956939bcbcb5db106478	1	0	\\x000000010000000000800003c475664eb3c7c499778b9f249b114109d46e665caf436228f509939b6d7c200095f1db3ff011c1d32fcc869a16ba7ebaa1a874961e722cb5d5edbdffe68622bb267cde3d732664d67e604f177ccdee77f0ecee897f9a16ad4f23f722e378feffcd0901ba0b418e1bff82fd5d9d4d1cc28e7ce8f950eb080b4242902f30ae128d010001	\\x7797bba055866f16791357daa97ba1c0d41608fd4802197257fec08d8eed12b9a9c57ccb8ada5008c8e21947071e352c7277ae5bf44c3f73e8ff21a964a7920a	1661328456000000	1661933256000000	1725005256000000	1819613256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x6608869a87563e09e4b49bf265a79ee89807e34cdd5c690ee928ed61fac3246b181361440cd06010eb935d58f3d52a513305441cf209b071a79236e052e23536	1	0	\\x000000010000000000800003c01b96475bbf5ded530111d212fedde57a576b68a9c87238caf2bac5c7afd114cb6048520ef03c4f07b0809be39279f5ea12fd3c1f06da5cc5d7625725a7a06131608c77d3f98e1d3299ed79ac7dabb536559b9f4096dc816322fbdeae45fc462b00b888b0dbc3fe66fbe0938a65ff3d5aa9738b8d373265cbacfe14877cbc5d010001	\\xeefc03369870fbae2785814e786c7b446411d7cfbdcad519988d02b26609cc41e54ea3a5baf52df6c7b8e973b547ed2a03ca54feea115ebcd97cfcd981c45206	1652865456000000	1653470256000000	1716542256000000	1811150256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
44	\\x66c0558d9d9ad096c7fbe4031b7d95f22a30b438cdf98e78c27a835de0367f43ea8fb6673cf27cbdd96203b155b3efd8b67528a0ed81c295a8b2cb65b3988299	1	0	\\x00000001000000000080000397592416e9ab7e37cfe2b3bb4f52025405bb66d9d7676c33c56a0278c48b63f193c0aac20b85a9a515c2a2726c2867b060b796ffa8281b31bf80afdb0876d47ebf7890c6a1faf4994a7727c356f57b99e03efb23e45daa400a4791bfd04431ebd55a1feee669cd17c9dd417082315ca44c3756bfb685bb9fa27ff54c9f5c373f010001	\\x8cdcb9a7eaef28c4730d8d390db62bbca4e2a90da89746d12f5e942987b52e29c30650c9fdb5ee4e7d13ee01496f0288edfbb9acc41517c6d38cbdfedab9db0a	1649842956000000	1650447756000000	1713519756000000	1808127756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
45	\\x678498b06cb22069be2b4bedc86077b0b740c1c7673a335c8c87e3663cfa15a065c492487dae11b11f8e26242a0a92ab1a85e1ccdb9c64d784dc9966e6f72c44	1	0	\\x000000010000000000800003d593ddd900ea7c22ed78a2607ea57612db6733816f1644c20f15710d705b7f2cb4a3469ddfca2561e6c2ee516df48bcd89b686dca68fd0e49eb9f33556a4cf583fcdd0c7b8579127206dae9ff3125ac7e61a319c1323ae21607ee570cd97dc772504e8ed577fb1271672ec16467e54f73d46c67fc375c770f89298cb6b61da33010001	\\x369d791ff2c760ea9410d0782b4247e1824bbaf13abb6f63b213eac60ea3e80f1e5a6b908826e0ea891f3253ae8b2cef311d4c0832044358e1ff008dcac8b609	1652260956000000	1652865756000000	1715937756000000	1810545756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x6840e1f50dd6df20ee0460df564fe4b14373bbe160970a4b1097573593a729907e2c154839321e4c0824f6ce015e63a7655c45b7b16c05dc112baa23845640dd	1	0	\\x000000010000000000800003e53652b2f48eab0a44d552c6e624ece5f080fbb51358dd0e6007150455fde9033bf56cb324e5bb10f4de6fe1c66480796e0e66d6afd2f5caeb8b5cdef19d8dea2d3f4f6cf914304c1db0719e063b0124bf8cc85b127388de195f98076887b346de652c81e7d7d90b5cd536d6e55b71b7ed194901e1e94023d8b32d10551f1461010001	\\x890dabb2415a2fba399e83674c402b150abdc548c599bca325ca362ad803f40cb7feb94f976f039abcbfbb31f0458342084987b4df55313e84470f5fe6741707	1667977956000000	1668582756000000	1731654756000000	1826262756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x68f4ab2d80277c9de2c1a2d75e88be67f9beb251b277dada0935f6b3ac500e735a1c604875e44380405f6d456b1caf4c6378d9383b1ea47a6ce5aa0050e552df	1	0	\\x000000010000000000800003f2a71eb19554949a374aee9a5b6c574d9e7fbecfcc0af0142534aa13403ee16699b19dc36ef35848d3827487c0fc8b2c76b9db8576a821fbe0f38baafe93ca1a215d6944b220d43055b8c860db129b9e4c937e39c8e1f0505696ceb35ac648c8675b4fbf30cbabd8d66c7b0778f80e6099f2916071fbbcd6a3062d28e5dcd045010001	\\x4677b314004879516d1d7f29ee18939af39f08b2639163886dab0d8c44df31deb64bbbed8af6b008f8044b79bad79d0dfb678b7a2a87a294563cefdaef3a6406	1660723956000000	1661328756000000	1724400756000000	1819008756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
48	\\x6c50204a922b7ec96e69859ba406944c3f2ebf350b4db3b84706fe5ad64fcd42d82734d742cd053bdcf546939af7d9857c0078a893473c35ea49ac25a3a6a554	1	0	\\x000000010000000000800003c377b69007a15e15ce1578f0f438d202cf874bbb687e64970333b5998b845e3ee023a6c8350c7accbd22dcb3ca8cef6d8aa5f625bc7879e01253455f295aa439b4818d086170fd8823a691a811fb47b6b3f5561845c6eef1c9aea6f18bdbf5d13ed77de5fd87a9d39f84e72be1a88f2c6653e7b3f4ba5ff22be61446509049a9010001	\\x0a6a830e4e158b3b20195ea70126950b2b0ee01887d34894785b710a47b6fc6bcf91f774be2fca036b805e43224e43cf1ece10a5ca0d3382cd1b4e0131d95c0c	1662537456000000	1663142256000000	1726214256000000	1820822256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x6cf888559066df991575daaeae49f59986c338a311a2f1ad3162b25615f051563030630aea8169ba06b6d010bebf243c630a2ee4328f49435534f0f686e89a48	1	0	\\x000000010000000000800003bfe0a605c4d0bd9bebe3f4b86d5c63b2f9c6e63c8fb01c8d06791e40f1a838ca6ccef343701a95cd81b61c1e23ab9b1924b794394a5bc333f9d7caca2b55d20459904ba0d15bf0990ae1465066846be6a604dc26226360931da32951c6271883b6bb4f3b2de91c18de8cbef5f684a4c22b348233e985dd67523db34546b05597010001	\\x29ca0a76ac329426f783047ef4234b9984a94a379429dc24f9cf4f51b647d736c1d79343ba0c8411e2fa0117271818fc4a3d3663c59ad7623b012a0d7f1b0507	1654074456000000	1654679256000000	1717751256000000	1812359256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x6dac933bc1a46bd70b30232061780ffbb6756fb146124429431658f459c1c305addc5d0cac9c48f6e274363797b0426694c036dbe561ab246a6cb3676e887812	1	0	\\x000000010000000000800003b69361bbb288a5ec2bb714f182c0278a2c9f29c2b60bb1c42f81060dffbe66b8c15116fdde3db2d0378d34bfcc88d478da80f257344474432d49b1a1b0e94cb4f102442a4dfa0f874ebf5f34291586a912f690e558462bd179eacc3cdac858db156b666c4299d9e23de8a67087f4940d0fe8a171db84406e69e52c5da209ed49010001	\\x4a2ac87add8124849ce7e1a9719621a89c897bac89d485da8d87447a3b088069bbfcd4b5fb566f8116fb6d9db4be364e7080e2e8e16df461d8c9b74d5180cf0e	1638357456000000	1638962256000000	1702034256000000	1796642256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x77f4e440b5af005debd704ae59140483d8bcca7355fe1407f04156f4006aac5f191fc7d1d83ccff237996ca71de173279581654a4c04cada8607b47bc952b228	1	0	\\x000000010000000000800003a0637bcdf89490da0bf97768b12678d9915227a8a9f7cfebe6980ff549d15d1a16d275350c2e4ff3c66eaf5c89cccf0d6b62d6f5470a3939fd7daa0944eefd014df67ecd4546cb45632d795306c01ffff78b55829fc2dc002957bef86e8491355a4914ea6d457abfa1a9a5b56453c076840e7ee606bb2661328e7a27dff900fb010001	\\xee4969e9ddfffc7d8230192fb30d9d9ff33c67754be8eeb968953d5b07289ee82a16d7ebd33609d44d8718075d3afac616deecdfd8a0145505e32d0f44c9e10f	1657096956000000	1657701756000000	1720773756000000	1815381756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x78cc2889b41f296227f88e8f4ac39e883b56098506e2e8539fbb5dcbe207bd08e703a2d9911289249ee9809ef88937512379f82204aaa3ac4924ab2c39fe6339	1	0	\\x000000010000000000800003fbbca88a9a432c7523e66c270096ed538e4b35cd21372f417b2bb24a1f5c834fba2f5fe30ccf9e0ad39bf9e373053b908ba7497073764a7e64d99ea54a2b43469bc919c0b15f4f6ef389484990457e3a3cea017f4b4042f57d5fb40b906165322d09a7bcfff830deb9565facf693969b21b7b9c5c41b17f62d3fb59db629084b010001	\\xe4c59f61ea00433acdd7865e7a06bd1ca433f053d4138c40a5843d83edacc84e01d1c91b474bd64f8b524f26c4d1065f532eb3368005dfc14504790bf8dc1b02	1663746456000000	1664351256000000	1727423256000000	1822031256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x79c493d37c1cd8648dfb62d9b6be709f2772fb093c2f1029c7f6746d5d17f82f64550a2e10d8e174ae3aeb8ba34ca9c1c1df1c5ce3d24ae62b61e6920007cc67	1	0	\\x000000010000000000800003a775b408d888c13c58e31996416d5e098eafcd1b7960feeb518c81d0782cbb92c6517db120b93d4603b1021877b99e22ecea5c91eb351fedb61c7d254807d01250e47352d9376fdd8003f9a28a0a74acd7be56a1e624be336eec70378a361f40c42f672861e8352e4f0bb02b088a5541a81e3749f823666b4a5295e95e7e9751010001	\\xa9305ff5a6fd365aef1187ab4475e9284d543d02ecdd6e19038385e0238354655277d5b23418edabc0d72a1ee2016b986d1e6d3d13e03bbfc68226ff1c5c5905	1668582456000000	1669187256000000	1732259256000000	1826867256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x7a58f42d2bc3aabe5e5594ccbfbbb249abcc39b9ed6a8726c5f535d0aad31a6e65f145cee4aaea7fd8ecf9d956baa2a1b0383b9fbc57ff5128ff8026f5222ce3	1	0	\\x000000010000000000800003a3fefa14b76d6f170e8ebd6b948b7da96d74cc2f80816ffb91354d2d2708823a1379cc41e0c3397d02957c7b09c721bff0d01e5b891b5967d27d11a23501c49f8892db57752d9f20764780e5b0ecede80ce12ed026a52f909cce46e0ccba66d206d360e39aea898e514ef5e3a49de8be62aa8aa7884ab2880cb7f88b65ecff65010001	\\xbe5a702cc3ab4361fa009ecedd4fccbdbc7415859489ee765e8e0fd24759fcacad4b9ba67f683c3a041202e7ffd9900ecbe3d3c06cf5e3c41d1a0f4c05819d0d	1652260956000000	1652865756000000	1715937756000000	1810545756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x7e60900cb8a0778328a8c404f6438b3c583b611c30441dce4f76cd7af162408b72896443aab05e81b6031fd9d1b0e54cfd2d8f1dad402542189dc0273d608edb	1	0	\\x000000010000000000800003b665c7873651aa5701cd85e675115d260dba8b5db4b7878df42e3719cf82da6d2788f67b4e54b0663dc0a65e156940c97f3b7b7d96c733c5107a9dbc0d1e41a77f2f79bf29fdf7386ffdf9baab5d1ff45fdd9df9b23fff356044ba5d5a772613f525ad656b548dbfd381de0aa8c5aaed1c70e24b69143a505a67c05c9c55918b010001	\\x46e34ad5af7e42dcbd4fec5845b21494c5f4a2bc39be15e31e423bbe46c5774bb26038b263609cd0bd857322d9f169fc418b50e34fa6d3d13bc5105415acd30c	1647424956000000	1648029756000000	1711101756000000	1805709756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x8080d2c12de644a285c0eb9aeef7a76c6b0c44b3f148b3b0fa13aad372d538630ee5d99ef7e37dd02621118d877896fb3c10082fe5f254f90209c3577cb6848c	1	0	\\x000000010000000000800003dd287bbea5324197afcc4505e09f5a654be9fbdaab5c765e7792a7d1c7dc1f6277c4e4dbd4a088f7113611f9a48a8f232e9486bf560efcd003b4e6a66c26b7aa2fe292689bfa5cae27c89262372259f80f3bcc3a3abdcf06f64260b5bc7e1e15661bab5767ca96a2e67834c67178184b951dab7b4951708dab417e50a30c39a3010001	\\xe1ba734eb512fb7e372662e7ae9231455b303d12582aa50f35f061f04385a0dfb6f672faa4e6f749e60d55695682c64603f44a557b1876f61649316f5c137f09	1646820456000000	1647425256000000	1710497256000000	1805105256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x829ca76b4ac7f9f3393e0113e7b8e55d3e3eb5df7c8bbd6f49f23874111d97d8a2c038a808ac2bbf80cddbe2997543e8081c1a476088d91950ee66c5113ab7d2	1	0	\\x000000010000000000800003d80b5a14e21e6dbd8c1fbce85e357a5cce1f57536dc0098a08b19d6a8714e9fb4dfbb273d61102da9472f8c9764f299056e1324b57d6761240559f95b01a0112c15fb2c7c1793cb57607ce24b1b16a534654f3a374ea54f4bfcb1ef6339714c0052259dcf1d979acff09361cf90e064c4e97ef68aea7748bc2e8f040ce227167010001	\\x92bc4536d9ef8c75475cac1a27f82de865ae5930a06eba62eb26482e7cb0be1c313a5b263d24046dff6fb9b9b9cd7d9bc0cc93727d527dc7b84342dfae68710d	1666768956000000	1667373756000000	1730445756000000	1825053756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x83004897f18ef6ad52ce00584e73b0c2f1f97cba1790622b900fdb01abd0c083a907ecc1d4257c8f7f177ce021b5fd4b49f600d9422808bbff086896cc52abd2	1	0	\\x000000010000000000800003d6eff5cb706ef2a15bf8983ea6de9ec8983276d800d0a53c0bb3eed91be2265bbb60f2758107cb0543916652e9684c79e3fcf918b0b0a59372ecb9086f4eacc3564761d5b32f8d12ef572ee5e201380a6856dc98aaff76dc2fcfd1bd2fb75cbd6832316e2fcb4f2e48bd83dad0eeb1f1d8f0275391c35873f832c5dd5ac82a9b010001	\\xe90d59d33a820e797c5d6ab076da7db2257f72d5f0dcac8ae8fac187981b179e2f05283af206641d8e703551fd7c2a32b1a8b1dbf2e5671e7e8bd010a43aab03	1669791456000000	1670396256000000	1733468256000000	1828076256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x84803aeb29889289e4f6c03410d3310c13329e74820e470c343147c6342339d054d1c1f1ddbf3d5a202dcc64c8381542d6ac6279b2dc130d1143e61664e18d05	1	0	\\x000000010000000000800003be935978a57ebebc34b8406bfe2de47115737a872efd83f8a118970c9df072877182ac028a343a2be3cf40867eafe1f724922b6000e3f33bf00cbc1129db68b869b5f06f1d2c9308a5282130c7ec65780434b08666f61096ca2d0b1414783bda452e3abbeb832b1c02c555b3e79a14d39046c1aa22393a4edadde67411ed7ce7010001	\\x3cd791a2c8b87177961ab35dbea418a63bce35899f1cf14a550b0f9e0023822460a4ef80b4ab3f7c10eded65db29a929a4f4ae095a3f3f32d69248901467fc0f	1648633956000000	1649238756000000	1712310756000000	1806918756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x85043a839b67fb8a3c044ffea3ab6a9b83b1fc2600cc2dd70e97f320b851702f54c0a72f77a9aa28cef8c3553d0758b0cb7a571fd09e422771fddcddfb115123	1	0	\\x000000010000000000800003b25b45d0dec32c054c454358acb06b94bb0336726454b62d9504da70a3177d3e6e8dd7760ef28e680ba7351dc1a85504eab6f7d22e6a9efaf4399fb330b0def556092849fd0bc052fea71e3fd2470053e5d104ebbf6b3173a7714b9c414cc1762e91565ecfdb4c5b359f7745bbb5766459fa1689c8b47e00aeaec815bde4e2af010001	\\xcec5aa126cbcc84abf7027c2925a2fe99ae9aebc4f64afdc5ba5ad7911c49e65dc632aff94670923056f5f4847930343f81c9854a6c684a133166cb890b90e05	1657096956000000	1657701756000000	1720773756000000	1815381756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x86243cffeeb4088f74c89d7a831c30ec5dbb08820238879c2c9b8225e17a27869d3cfc3a57a2bae529ffd138949a5e969f637a09f1e79733e1d1c0cebcc332d4	1	0	\\x000000010000000000800003c8743c9f9ea2a09deedb732f6d9c2b728faf62b001aba101631f779ffebad3635ac8fb489bf0a38f8ff20da5181c18746850cbd58f270bdd8485eaf8f1cb41d8b7db7dd46e962ccae2cb23ad621d4c26488369d8691005da2e8f6936de5a6eafd3c3ba9119c6b6704fe5a84ed1f7435af3cfdf97fceab2cd8f7e20d4098ca1f3010001	\\x3c330fe67ada389ed76477a92529956dfe610226ba8547d78a0d4b5ce4987199a36755270897ee267d9d0cf4275ead9be713d70a2ff8a9bd7b4fc38847600309	1649842956000000	1650447756000000	1713519756000000	1808127756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x87ec8eebb791cd76cb685978254a3625311b9e56f22e9665ee2bec3a8f002574c9dbd40ec5433095369b8d7c3e847f82054bde6e6d6c76d084e952d53814763f	1	0	\\x000000010000000000800003cb31d5bee7d8cd45a66e9b3523d11326c37ad4c6a8f37a80a19dd533385fa1f61db922fee2bd3ce5ba294b6d9db0e80113b625bfacd72b4429084878a43135ef08e521ea19fc9c026c0874a9b58147b7e7149f708aef83812b36c5b0684ae379f0e98d63191a6ce276240056f1319e6e1463e43da708d2e5c1cb6edbd543d943010001	\\x7315b55d2026a63a11601e2e7095c2fa7ba3b08b0dace66980c0ae1dd38a19c6dd839ece1025f42c76090c3c6249fc99c19c16fe754f9b293b8b900e7e93220d	1655283456000000	1655888256000000	1718960256000000	1813568256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\x8828f8f07f4a69cc90152802a4b051508b855ed22a55a12b91ac0d1121c0ce81c350e4667caff9a1ef1850b8fd3678b1d40d8a678245b10fcbd772182f670604	1	0	\\x000000010000000000800003c39883c1bcd03ddad593811165429bd2c353fe794bbd72cb88dbd35044f26be3fad23b99178538a170be605ddd9b2b21f35b4ca9dea9b4a1037d20ba707b7ee1ae8a638f6e099798f9f16d40a703563bb861c283e2036fac60db0d6d6ae32aa46891fd207715dc4053624e9005b403d8cce0cfe0d65f151c96c5036cd380e065010001	\\x1cb75ed708ec024aa73532f17035f1d2d3138d9f010dc03b06827a499d539969c1c7973d2d84bb5e8e019aab42de0fb506109246ec466efe2a32bec353b0b50b	1650447456000000	1651052256000000	1714124256000000	1808732256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x8974f137db39b3bc5e8f4d0f1b9ad2f01e2f579f9294ee02a6cb6ffc3034672a15e08d4607dc9f92ac32c388ca5e9f8d834008dc8e3bc9ca52ba0df1aa80b7de	1	0	\\x0000000100000000008000039d770b821f4dc20d03bbe593f3ab3ffc6b1ad2ebf4a199fee0922ed06ca5fbf081364249f80a4cd5f2e391307ec4553936b8d59035ed85604903180468c04cf243e773e5897c9e969f63e0d4068eb02692cc93b380f2544587f87152b34f1a411571fa0ba19386e572c90409cb49514ba266e9f0d744b8cae3ef2c4a65357b73010001	\\x820eebb83d70b235d07450e862598ee61d498aaafbca9e6fa2b5b1fb33b3e3fa2cb8629e788dc6649d195fd0e2773ecd0734e4493bae4b1dcda8547594ad870f	1669186956000000	1669791756000000	1732863756000000	1827471756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x8af4758f0cf800d2afb54beecefdd162bea5f3cf5d0a9eb0cb5d8fd37baa211952088ea88a8bfa46625d75e4d40a4e358ca79725a410c713446a55ecf7a82918	1	0	\\x000000010000000000800003cba923b688b8a354e6103ac919bf932d5a3286cb03e41418e498e7ac7e2c3c786a83832d179a1accec963e64e61a4763494fcda99847bad94eeb3e4b9cfa7978a724b4f6e225734d3d274045dc6b54a222e44ffa7aab1e2b3667c004659709d0f52eba36648d5cf399d7e46b141ab4cc5afc868032958c28e2e94b24e938b437010001	\\x99e934128199910851b042762ae44b11356399fb33ec8bb4efc1f9e5d768bbc31f002ebf15184de9b6a5bef7491d5e388b95875fa249002f00184c08d38f9106	1643797956000000	1644402756000000	1707474756000000	1802082756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
66	\\x8b0cbccf27523c0b470fa7b226d26249abf4aff227da4d6729962339d48b37e275b89fb8d726ebf448e6ffa1f519a0bda8b53c67f30b5f3c6de5a47a1de01c64	1	0	\\x000000010000000000800003ccc50ef2d76623b7c25b295476247e66f9d2a017407d9f948df5691f5d8a0effbc0ba1ed1fe4d4fc77bb9dcf9c797400055532e6e3138195fd7adc41389b9119b4002e7243d2a1ddc7dc7de00f5a2c774c1e4c420ca785c1c983225a75e08c924a191407ef4859d453d6ca047a00062474bd65ec099022b616b8a1c78442a4b9010001	\\x347fdaa7452b0cfac6aa38552f09257428da2b589c48fc1e49a9d7a8ad06d45c6cd6e08c73016c888dec2f7b4993428a5e93db82d598a602a26f3b3da7112f08	1649238456000000	1649843256000000	1712915256000000	1807523256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\x8df42b12abf311a4ede01ba7691647651b126f6bef0c6a28a75d2f511c02d3c655439e4e28206646acb7c63c26cd568bda4a36b84c6f1758392ed30de7d1b50b	1	0	\\x000000010000000000800003e014440a39ddf8ff2cb85fe46c1e1ad3d02414be011132cd25389058d525a1120143555dc30f61deef821636287b39a0ca47695caa428710a30f14283ebb02918e2b02dca08e0f9a4a120ea54885208003dcbc119bcdca1dd41b40ffd7653d4718c5caee7d14cc2b0a0dae0241e4ade85ab278d19c169a2dc5a035da960a3df9010001	\\x3d9ecc9095b2f583b06bdb925e2327dbbf9327437af099705dde3557630bfca301b438737bde44a1e7b5835be1d295575d5e6e799e8735994e1507177d410200	1661932956000000	1662537756000000	1725609756000000	1820217756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x97c0e03828a6777f3ca5e8f29f92d1623ec937263efbf7c298d1928ff4f4d0ba3225ec8a8526e16128bdf7f389fc73c12dafe3fd262f8d11ca22360e048f895e	1	0	\\x000000010000000000800003d594d86d16eee3760422a4edeccc25d0c8669ebbf1e2ae9e9ced5f109230459654e705415b75314f543e7909a31dbce2471903af3ac2aca0ca43cb0f66f48367ec3053a9e542e9713d21c678d72525c7b48584a1dd1e8fd97560a22dfcec7a4dd117d1e5d965ee8791d8d3198191792a31341acb5ddccf6a14fc70332080ed2f010001	\\xcd0dc166b11e07f57e97fd7d886a8dabc99c80840370f37d3ce1d2c22634f28c532ba33e641a5862ca10ed148af2865afda98b2576a96bc1aa44e1271eddd50f	1658305956000000	1658910756000000	1721982756000000	1816590756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\x97b8092eb63fb092ee94f5745d40fae0a21ad95373f83d3910bf689a88b41b51056bbb0bb99ded2e684174b84ff15758f1efb9b4384e0c9d554ad01047c02ddf	1	0	\\x000000010000000000800003df242f272ca39a7b2f9989879975503fdd05c6ccf1a9700b761c67aa87c1312ec30209f5063a70b20bc2ea0db340b20e58d923d64e31ea3deecfe737fe05c21c0d58bc1e7e0c95ce52f231c246d3f66d1b434a24259f51eb6d2a3ad48a8cdd904aa0a5205833d4d60b13ec2e71a173def437f6e7943310ddcbe6848b8d02191b010001	\\x5987edc11f3a6254ca693e02a1fec7939670df09767e89adda0bca2f86d12715363586ad00b7f254de546900f563378199733f93601960692b51a12e040b7b0b	1648633956000000	1649238756000000	1712310756000000	1806918756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x97884fa45ae35bd940b7ae9cc5fb6fc2798a40f633d91d6a0326f08902ec8ff2921a631823fcf96884546dd6cf5d41f034ebd538dc171c3d2aa6720eec614d30	1	0	\\x000000010000000000800003db54574a97945786702a21608dff696c6430a10e6615f2211501bd262047366273cf8e0b9cae6acb1bfb1385edc0192233116920cabb0faccda02937427d13bdccea154c4b9877627686a633a0811e7b6dc5f9a9fc21a0fec10c4543926cbe96182d2e9ee342b68859590f0a38219d576547e8c8bbdf1d930411d5713b6e18a9010001	\\x4bb4bef121b07ae9e44070ca93c5cea6f0804953ccc4382b54772bec71d141c583cbf4bd8ac9f4feedbc2e5a8c5c0042d732bca1f0aea8cbfaf15f57129f5703	1638357456000000	1638962256000000	1702034256000000	1796642256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
71	\\x9abceda0fa75a42e4d07a065d3efc1b8e95c86bf733f1bd57024d8582bf0e0476b627dc757a25017727a25f22508dd1154e898b7638832519cc55c6c05b380ba	1	0	\\x000000010000000000800003eca3f458b5b4faacc24325f7cf9fb794723adabfb3921ce61bad5f6ef587d1650280bd787bb6bd6e9f1a9cd7759964349c2d49c030f14e571722101eddb9a781bf8e179331a5139d33f099335b73aa0f30ee815f1c3a42abd5b5e31dbc3fd30b32549dcca3a8d4b28c5b1689a8ac24c71e812800d1741f513b72da0d1d9c2d77010001	\\xd7fbccca069292a89646d845e43d806d8c152d149566f44aaf726d8a591a1dc0b4c33f9fb7016c51946407f0565bf370dcacc98d2b636ee4dbfc78eeda736f0e	1665559956000000	1666164756000000	1729236756000000	1823844756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x9b78edee8528f72ccd2c5c9d4d715c9941ae438aa8328d7deed1fefad80ddde9a65376ecc8015b3b4e893c961ed66b6e89537a4466cf6fc9192d3b7fa5297844	1	0	\\x000000010000000000800003beb04139a740bd5360ca466fba985911e9d5abd2792263a67872543efaa8e67e696dab642e2499918f1787d66d493f95c6529cd564427528c34aa8dd38e877145a125c011d956128d7456ec22e68fc804a0161b3239114379597c9e6e27d0946bca685f0c3f4382f3b602cc9274cc5ad27e987a521d66d1c1ba4b5cc27f8dbdf010001	\\x34e1f1bd27d8b8e50d33df65596f4e875c9367c291e6a280c9504ba84a5db484cfca47931ad596bbf5eaba361183df5d9522c826bf9a61139883c28dc6bdcb0f	1658910456000000	1659515256000000	1722587256000000	1817195256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
73	\\x9c9cf6de4443592798b05fadbc3274760c4c8189f576dce1a87a25a948a0716089899bdaa1a1f3bb4d544a64803612b899e597dd46075e8afd688866001572e0	1	0	\\x000000010000000000800003d3b8be06cbbcc23d9a2d17c0eafe1a8a34474b4cfdca847b2c486b205effe2786e0bd830a1ceb174fab80d74e2274607e7440905ad37f5b8d20e298ee6fd4ca60c0ea2cd0ddc607f7211ca31b975d28b30b4971ab601717d0ea35f39cfe352c69273973ae5d48e3493da144dcd56800d4ca52bd2f171042fde7ce3a4e593d1bf010001	\\x9dfabf8572261871b0987835a192fc850c10f35a696bf441f48ab1603973f68314aa88fe12d1e195c27df0c7a49a882e4a8e0de37f284447486dd9b445e9950f	1639566456000000	1640171256000000	1703243256000000	1797851256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\x9f685d1722084d715bc032eefc892dfdc38b30c322fa0625848dfcb3cac6751d9d7adc9a0c0fa56d2cfb95c746ba36895c7a98ac01a07e8db0e79fc306478bbe	1	0	\\x000000010000000000800003a382ac817a56b05a3a908b151bb2ec0f5ea19f52399f034910ebeada6de1db9944cec4332da237e0fc1f4d904d4472a596c8d011b79ec6ffb57cb0035dd3d893488561e9079fc1adc5ed1b30536c9cdb9405f643743dc3f2a28282433afd81987fee3302ed07c2133756f048294b1706d427f5340ea121e0ee3d1c09b083ae67010001	\\x6d16245e9b7eff1efcd903f402fe08d63913ffe4a2502f83f5886d0f6fc5ce197a4ccea5cc4fd42e5e50e417fc476a687aaa79e5bdf2d98114b9ee9a8c09a10d	1638357456000000	1638962256000000	1702034256000000	1796642256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\x9f10dc0f9b58fb9f23da552000bc46194b289bd1f7ba773fe90fc6804240af4f525a55b6e356c1db7592c5364fdbebe03fce2132f256e9625a2a3957cc0476ca	1	0	\\x000000010000000000800003c9c1e68296e17fb7ff87d3d9ce9a550f7cde8d90e8c3d6cea42a4ed1e8be92427e8bcef0ac36c21bb9698f5e88894aa05308c9899046440a9ad279da98e27fba7998b3172b3c735f9e9e9b93090c609ff214d7f96cc32d0d548b2583af16c292ddacbb6f2dc3fc9eda6c7d56f9aff884db4580c8f26e5821447cf2ecb41f1adb010001	\\xd2a255d40679fcda63f3dabaf9c918498bc75aefee863d6d073f675c3427dd0fe831e386d4545d6c9010744af391de82cadbb48bb54d3de843de477d03047505	1661328456000000	1661933256000000	1725005256000000	1819613256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
76	\\xa1f0cb704e549de591e36e9df59e44d4bb0f1344ccb56a77538c29999f9cb25046b23a6bcbfb33637555287695ddd8e19dcd50c9110116fd9e5bc1220678786f	1	0	\\x000000010000000000800003ac90a338fc12759dcfaa1b90893a088b18f1e23800cdb09edfb15895ef79cbf0833b7e36ec6bd4804afeaf2ba1f5735e655496b69e4d3456b5373e5ddb7bcbb45bf7e2aeabc726021e650b13f1c8573518eacfa1be03b9320a7e4380361a162c234a45161bee7d02543819ca6243d831fa896ebd434fdab681262d3018c4a007010001	\\xeea04bb165520c7161b79fd2647a654dac8e04a0fe725704dfe1fd3d65f6e8b63f5ded298a5afdf21d1d7bd64a18e1101e48d19f9fc95ba8a342b05bc9722c0f	1650447456000000	1651052256000000	1714124256000000	1808732256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xa1f857651f28b2c3a801ea627c85085a6982279990d6071c1d6d144d67d56343b02352fa28040e29fb9e8bb2151291877577fde80a1999916dc19affb3d1b082	1	0	\\x000000010000000000800003bf7b22b991cf2c7e18d893ffceaa6d3a2880337fc4a335fdca615aeb176d567bb845cfd0ee450d0083e97a68509f7d4ca09c48c27a08f4156fbb35d13b97489e8618c1824f9915c99a0e4946f77fb31c7a90da11bdb5322b33c7bd87cab825ea2ea7abe25b8aae22ab3d0889d0248908786c99e3aa0fd4b2705cc176a3cd7cb5010001	\\xe4d270320ee68d3bde85f72953bd48f2b48467d660339dee06ef8279ff67a2e96c415f5ae74331a699c676e6e6bdb6a53ce7824271170ce4d27a88a441e1460c	1657701456000000	1658306256000000	1721378256000000	1815986256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xa56c60dfd5dcd1bb471b9f3fc6d73cead5a1bd6d04dc9d908fd5952b514aabbd1f331bf9fad093f40398a36b293eb7bbc46cb18dd599bc6bbfdb98018e4074f1	1	0	\\x000000010000000000800003c61fd0e77ee064005a080992e562434ecedba6a98d359ad3acea80ea22f248dc9682021e7b392a8ff3a165471b9c8e196aa6a4b74fa291ecc5e9809ffdf8e8eb139a425a90f4e9a78253604e2e4ab9d56b84ef8d3ef534f99d4f8fdef48e7a98186a54febc34388e5fcec06571ff61326e63d8bc9d0d75790612b7c48c8ccb41010001	\\xa2aa6a42f8e8c083ccb59c2ced9047291e10c709f6e622dfc953cfcb81a81de97dc6a988fb3f9451f98c18d92bfaa6111308f96c110bf1363414f11d13429405	1649842956000000	1650447756000000	1713519756000000	1808127756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xa98843507176f1240acafff809200626fffbc28050bea0ce521f4fa146c43bda6af1878cd2abe352800e22f8e4c58df3f6d48a412e8327dab529e59be9b321dd	1	0	\\x000000010000000000800003a4053fc5cedbaf9c799d78c2a71985c55f099423455cbccbff40f9439e05ed8b59d4a8a7306bb06f1bce1a64c25f6ec02c9047831a10c2db888bedc696ba676cb79b5bcf14e7cde509b7db6dc15116171da89cb30984a0e83fafb5037da37eee1b38fdc640e5ba2829e998df44f73f7d87c8a659d3a6d8c7465205bb8449ffdd010001	\\x023e06af21ec4c91cf2849b038b312eae8558902c8611ee5b2e15d21bed7724d4129ee3c002f664bb00b437b365e23edb90de9177b31eb1ca9a7412233c8b10f	1658305956000000	1658910756000000	1721982756000000	1816590756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xab1028f89bb429f49647a2856957c7b4f9d3d2aa8bfc1b4e4e19119cd5578e1a2001a3328b8217ccbd548066a12b4c88afb65a612ca7aa8e420efe6e70519617	1	0	\\x000000010000000000800003c95f4c02c286178b80cc0311d8b01dc100f284ff2aaec4bbbf35a3534ade25d5f65210da4900de0a70d389ce5bc9378f96cfcb41c5790f02b665715eb0891c1daa208f912f106a8a3fc723c1723a43a62b107c28ae4da851f6616acaf5df2ef46342e49dbf9e6701b6afc74e64174da25d3b7d677ff7f5fc486ad72b284e44d1010001	\\x68cd3d77f65cc34cda2510e0c00745df8aefddd446e338c18b26b1dd00280958638747488aa7dd6c7e9d3288d14cbd62e195e6f4a53d95d1e4991efc89cdd305	1638357456000000	1638962256000000	1702034256000000	1796642256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xae44a525d8a73334669dff03f71622ee4659cfa932590ca665c57a58835ac073c488bf9eab6aef3ff3dd0f3678ee404c2fc4b1e4c8fb099f16ce3e95e6151189	1	0	\\x000000010000000000800003f39f7fda021d982d17a6c36f81dd4b600050b2c67d06b433e2246e90d35203745b29abbaf9976ac1fcda718d20e5d6b6e97562fd13bb74a57656a9dc7528768acb118a53a7b3ed51ae5f24cf55693e1526e1bee07ed9922d4debde6d9e3715e36858c15325775c8ae4346e09f2e390cc9ec1ff2efbdd685ead2816b8c57b2f1d010001	\\x8f4244676dfa3ab995e0bd5d2634290de17a2739c5f5c747a0acc212fb7b35898d50df61dc0bf807125180827b2d21c1ace24606e0b81a5661de032f35267d01	1642588956000000	1643193756000000	1706265756000000	1800873756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xae84a1193ec9bb86ce9c54fbbbf7b9d5651f2c8fd6c54eefeb7b1e9636a1a5cf86306e2cb56e1c8d7f4be431535f3bcc6e4e926402a7f0be761e1d1a4154a880	1	0	\\x000000010000000000800003b405b4cd96ed6117ea0e69e71702eac49aaa2ef6a08038445d05cfd364dc98cce069d0c19863778c223ef891f72ce3d6e61ed0419c404a4fd37c81337fafa93ced6dc73434a4f757c9fa615b44723ff2c129d8290d09129fed11582a757d82f15d10518c395165c3453822410b7bbfba92bfd5db5105275257befd40e7e832c3010001	\\xe24b487753700ea548202a8c3d1226b8371f969543287c4fd924b1335228e3b7057f6c841b4a31bb10f270c9c8187a4e0f3ce33a6078c0eee623bc607f2c5209	1657096956000000	1657701756000000	1720773756000000	1815381756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xaea003c1283f5936b93f4495fd3ea60152b8256d473af3d1abbe545352179b3d105b531de999dabaddc275aa9686f91f48fa3c4df072585652c81d61deb570e8	1	0	\\x000000010000000000800003a74a933ca210e9c5fa90135540bdc8497e19d2172f05c668e484b24d199a564938384fd6cb80e3f58047b8fa0003973158eaa0aed792c5d4470553e72b9fb96b0abb3e6655660355707d4f9aed9122669518bec9314ea06cf6f189cea5fc749c09d3144a9e77266f45282e09fd07c0790e47c809ce0429dc6638abd82393bda9010001	\\x1ca822a7bf4b712e604e27014c83f814e5e79f111f4c8901e9d7b3cd672ef4d27fe4060630f976b8d703bbd4a5a7ceab7f4b438090d72fda29f4f9147ac3e903	1669791456000000	1670396256000000	1733468256000000	1828076256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xaf00768f5fd3da3ff38e7bed33dc863facdf4233a6572cc8fa3b418c9368e0ec58df158ea380f7f653eb608030f5b66dcced60fa0ef0e4c43a080027cf0d5242	1	0	\\x000000010000000000800003abca3699062a11ed6ca4f88cce17c868695aee8f62f8bee1b0a8afd6b53e162939385b4f18619eddae78009cb9b04ecb8f77f666b53ef75579bd8e43139108cc7699546fda80ed6c48779769533a0e222374b563f476c2a006490f770a20934b1394847059e9966d5f645e41f2fa6f8bc2458503844f4abe3fe28de3bb4350cf010001	\\x36c59fcf6f6f465143d390f9f0ebb1c74ec96c6f6ab8ff61c5e164de08c1ded83e763ab3f0f9f54c1c6ae9559a7c0276c86b478d88b1fb403e3f4f93f7bc6d03	1656492456000000	1657097256000000	1720169256000000	1814777256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xb1b40de627264c42a48bd490da1d7676ad8a03c904ab508d3754f141130dc91f0082049146082b99f8e559590e13ad970612648de4f2b7f4c18fe53516b77cf3	1	0	\\x000000010000000000800003c081dcfbd77bf88b2810723da339117b73a20a10e2d892e4c39f3ffe5803eb2c9f7f3f7bbd25e5d883e75bef2581d3a8b087b6d16f28d5e490b1ee3e8887f73b578b87eccdafea3485faad63ce88596dc079d6f749c63ceec05aa3a1b83155f33c571421df0921de0b261c72e35106649d9b6dbc7c9ca3594eea99b9c4a97201010001	\\x42e7aba026b2d0d3ae68226f95dfd2f136f9d3770962d7cd772b2df491625cd8e7cc941aabc910f8764a036f9169c4d0ad05f96536cfabe0eb1442ed3723a908	1638961956000000	1639566756000000	1702638756000000	1797246756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
86	\\xb3bcd54cba6fb7a0bdf47d2ebecb9b5d6d1d43688a747d1f5e2e0f41e3adb1eb3ef7f8e51603c8c45cd91fe7a6eec3aebe5d0771980cbc091fe0c9cc3531f994	1	0	\\x000000010000000000800003d3394397b4cf21f81dcb54c7e4f3a66eee908d701fcc360f1541c66d2ebfa2766975c16d02a206f212d4787950c826b0dc296dedc0425479b5c9517cdab17414edef0fc705ad2998c189397d42877ecfe3c8965affebc1ce0bd283ec57c73a5447cbeac07ab52a7a43c135c471fc8b7245f249b4616a1992eb49d63c20535aa1010001	\\x9f07fb11a7d028316762f0544157076bd7ac6c26134f3b479405a5a17f7b1232fe8c9b28b21ea6396e51f4e021d944be813ec9610b178482a96fe07b5626c804	1659514956000000	1660119756000000	1723191756000000	1817799756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
87	\\xb5b07f88b3a610bbaf76f96f6ec4dad3819e194a7ee447da4c20ed364b4bf99ff883120d0136310a2fa4bcbac918c5728723fb8f0259053a35be41c29cc81612	1	0	\\x000000010000000000800003ca54642b4efd13fbe4d71834a4eabc0617ed276bda7c531950b03fc6aebc52a0dc89a2f229ac1b4dc8238447b1248d3124c0f33a0b81a320dd54828d982341dc38f2495b692322190c36c39ce86c21cb2abc21e398278a7cc273677a96146abdafffd39f93df19095d8854d8ae6a2a0b103a7c97bca2c3308cfec2fca64e57af010001	\\xec58ede62684f3144cc6cb07508ff06d0903077e6bd41ca4c7a962eaa21fb91e465f71e9191dc8deaad1b5731309934e6d31a94436c78878422b6bbb20f3f00f	1657096956000000	1657701756000000	1720773756000000	1815381756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xb5b04c637ba6876fddec33fd85968109bc2524cdc192738ec7d2e7a91d2d7f7320cb18fdcebdf52b36125405210f4c46ac676af61edd843f94ba075d535d783e	1	0	\\x000000010000000000800003d52afce67c7affb161e4e9f4c6a6da895c4da0578b8c9146e334116e896955f947caa9bb8d9271ed8ea17ec582e05fd426594cf10976d9aec0fc0b442d8ee6b99858ceb5ec4e3b2ff83856b2a168c30cc920b32affbac91eac9fee271f5783189f2888652d19f80d1384ab9c458922bd3c1897c5094740b7ff48b8e5aab6037b010001	\\x1bbe63232fb96b79a1d55191cf875ff0862789842ade4f18be41d85cfefa3234717bd55cf91bee1804093aba30809452586f1aba1806171e3b157026b800af0a	1660119456000000	1660724256000000	1723796256000000	1818404256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xb8183f5fee93c656cf8435ecd28be2e3fd9ed847bf270fe4beef895eb0b3c105ac3796c3ece3772e3e5897d9d1588711b34ce8fcc4e56c491c37794af088d26b	1	0	\\x000000010000000000800003e5857af46d8af93f094880d649cc50c1eacdfc320aad40b6c4d098d2efacf66b05169e769dae31acc42bed35d607834dd6b9a7d63fe2e6d0aa9c40218172cbe2caa4d83e79b9a6cf575b3b3397191c6ab4f83e3f9b049769f167d538f9465444dbb239b66bb66d2248f7260f2b7b824fa4f3f6c777a55197127a5718ad0a614f010001	\\x4829bf09a209bc27fd652a9157724569f95f96711b781a3a492109cc575d4c35420c720b04683960900a5a102ac95f21e32a305f8b186c6de840f481339a720f	1655887956000000	1656492756000000	1719564756000000	1814172756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xba907e06411806e96e764a1ae20b4ba8712ecf518682bbba2dcd386fcb69699ccfd92c281b98f7818a1eaa2525ac27df7d06c467d738037f3729fb847e96d68d	1	0	\\x000000010000000000800003f5e0464b97a1305f7d8a0b7aafe3c2154242115e66cfd097330819a42b317cfed3fe2e0ec2818eb741de1855e90dc4b6f53b37645a869de927c2536a0796f5cd345ffc6e962df5d08e85906208bd3ac4c3580552f3bdaecfba26b0a379938a253c803b2fe49557dcc1759f32674143433be27a0e2161f2b4d421349fd4be0e81010001	\\x0effc4b6d5d4f2b8896c3dd8531e0b79ff9cd5126495a15ad625d9c61c0486714db468b77b8604a1fbda0fe9f3657976a2a1a26e3ebdf5ed0c463e72f4571005	1654678956000000	1655283756000000	1718355756000000	1812963756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xbd44789edd6d9e83a6a2462517ec260ce7dc3e0d0a0605b95962393877ac6b92048a7e3bfc0c7e214ec9b4b4bf1dc48f1497ce8784c79d3e71ae11c7338d2438	1	0	\\x000000010000000000800003ca17c70dab6d131dfa128c2024faad60eb9e0743c33a3936b64477745f96085f9f8257f066cbafe66787b234653d089fc2b18dbb424f16e536f94ad6acf981d0b10cb4104009fb8ff98b411fb5258ae6d7b5d207658ac5f13438e834d734a155b3954f24b86f2362692dd8be42e96253b5599919b2daa8c50d2313d13b62fdd3010001	\\x920921bd7021278ac5aed7e725d0e842f5c27565ee759ea488f4d2eb5ecee16944e2114419707463f8697daac43b4e449420c5d59c3c2759ba38a9621273e905	1648633956000000	1649238756000000	1712310756000000	1806918756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xbd94e6e10268334f38c4aae3fc76c38004cfc6882945400ca51b59f7518e7a1977f904846fb0f7dd58968ec975d048675038408f442e4504c701767465aff9de	1	0	\\x000000010000000000800003d32498ca45b0374edd7a82682c1c0d3a17a5a2c3a10313f3463013168a163ebe65e89aedc06a427cb8f29f9c091e2d49467baf58d21e440daaf1482453000d98b0e0a52cb6293126ff1b00e2967d16604269c28f1925d095a42d9f8e97a0d33723cff62bf983d43ab25c49d4730582223e65c5b191b60740f9a4a2c8df7d783b010001	\\x86add594405682f3600ba0c23c9fc153f9976c5cf78455dd4ae7bf88a1995234d0816c1ebf0dabca63128d53a5b81f538da294c30dfde6b6b736f27d8009bf01	1666768956000000	1667373756000000	1730445756000000	1825053756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xbff838364f0c56b4c96e0e2cf99c9c9ed210d715a84e9e2a4658f7657985ef260043369eaca77ff561acfedf3d23b87c43e47473968d3d6760deae563352b10e	1	0	\\x000000010000000000800003bb4577bd4e80d9f57c0b8b4c75425ecdc478be558c3b8815908c6ef082ce8fd0cec391619751f676e0c82afb87509c5159ec5504468c6928705cb577d6459577e12c54077ab6759694d69ec1eccbc3ac4781015b392f15545707b4f893b5deb88aad0b3822b8bc8bee303c5ccb8ef418ac57446b5f1d87deccfca7974101f0df010001	\\x2b95db725fba79a826517527104779dfbec586a49a43254b541a5658d002b28a09fecf367feaff1046d29442f1c5a57b47101b90d2c5bc2ee5afbd6be3b30601	1643193456000000	1643798256000000	1706870256000000	1801478256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xc13cdc09b5907c3a089ed27b65aeb1a7b52dfa2b4b5cc821401bd106c3f6724e4a39abef9799f50580961285706333741089dbfdf16f5bf203892d930fcf8c54	1	0	\\x000000010000000000800003c5aefa6bf78698bcfb3a904e2ed92a7882b4bc22c2c67f38705b9aa4519c66dc64876aa7b80ee3bb1b13cdfebf6b6147d8ae243522245f9c85028aa4affd634247d0d06888a093b3e738a1041b34da23342bf9df1915a9937874447768376bf6bf57d25551d18de022ec7e99313dd6df262ecf0154d2e6cf5768da0cc6e25ab5010001	\\x9a7f8ef515c14c86dd49aeafd55778f8689aaf7805cb0ca855d4813a264dfaacd711f111c17891372d92d8f9901e5b491496fdcfe0df1d9fb151c95d2e7a1e04	1669186956000000	1669791756000000	1732863756000000	1827471756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xc1c8d632d2fa420299186aa302e84ede58ef3ca32baef0e34ffa407b9659904df0a5b9ba1f4ba3a7e3a7930b5ac0f626a02ec3abd6df7508f2811518b4953fa1	1	0	\\x000000010000000000800003c19ab9b1789a8a4bd0742996f9460aacdf385b53400cee04d4744c50f74e7e55a7524d933e5adbd233210eabd0a1f14cf736a81405cd93771281ec114433c681b5ec3d9948c89a829b4c7e13504f305ab758d2dce97e41e4c00ae6b4938acc07a9f283d38fda6c3a1a91b49f90346da01b138b112fb162823ac6c68a05f2adcb010001	\\x81f829115f937b64795dcd65887aef6cd243d47df40044d0a9b8fdd95bd1fad7d592786fa5e2e99bc2303a637c058215adc34cf52a87d7b7096e544fa09bce09	1660723956000000	1661328756000000	1724400756000000	1819008756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xc32ccdbac270fe7e1c034bf3ae76ebbeb28a0a0d58408b18ca2ec8bb75aa311893da54e077e546c3c9573b73a778554ea4b4001b7a118d11469445c152412b16	1	0	\\x000000010000000000800003b85f7fc60b45f572b1f2bd3c486b59b31ef94bd4d46b9b64a1cb2fe46ff6648d6ea033f09ed372dd0118967694cb1be2033832ee9e0cdf9efbef4e93a0f5144d267600fb85800a2cca7fc472417b894867c7a432b0760777f82a742778f5ba0e4f21ee773418090d84862cfb3ecb57436fe1398806436cb6f2d5a8ecb721f2bb010001	\\x8667577dae8853c018739f5d5e646f8581f29646e249b3cad8c350710217220c693f5b8cb4aaf899254ac46b83984ad1a7d4dce4803007eb06004081e3fecc0f	1666164456000000	1666769256000000	1729841256000000	1824449256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xc5ccfeeda809b5783a10017c50b50372ba4cb0c7c4db5d6335c39053e4997157b80912ca90fb014d8b83a4dcfcebc61bb318fd9ed51949a99bdade2cba823ad8	1	0	\\x000000010000000000800003f1887925b278e16aeac968fc9fca91c85d6e8f7a21d72b7a6bc5f50e6b857f2d2fba579d0f88c18a9df7996321db3c5b7d773aa8a455914538fd6f80d4201fde2e63066f47797956544fd74e92ed5ee951ed98dc798a32518af696d7ff716ab037a259854c42bc4aa4df53147df01555cd604fb2368958a27fc903f874a0b1ed010001	\\xdd924a955a22583f800a742292ba325819ba14b0cff77cf15702fb26e11fe45411299a6d1d14a272717bdc9b5734fd2af4edd32fcf9632856994ad2fa0f6960a	1665559956000000	1666164756000000	1729236756000000	1823844756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xc8442e66fc4ff54c132b0f92885090f24f4fff3629aac049d74371f200ee92cf931d4a77f4dc0f0ebaffb26e3e4dfe8247cadc6969f24fdc9acc68133eb5e11e	1	0	\\x000000010000000000800003b5da8db77e57970168c3e09617289fd3d2d252a4f7acc08e7c851d02bfb48df937286106a7523fdbe67604f50c08efac1da33b39ebcc1ed1579dbd1b30a0e4fedc2b4fb79f0fc7da0e05bf2ac6840a3cf91c6d48e3eabd6e771953bc7c61d3cb6e9c53adbfbdef9c37778e27e97b2418e32886517d62e9eb249854e7143993c3010001	\\x32aa42f35702a0300b39e947772a47298e6288d104f819989e3db050b3cc1cf9c6761fc67b5954acde679b58fe8d5c9d99a090fe4825130335a05ab07e226b05	1661932956000000	1662537756000000	1725609756000000	1820217756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xc9dc3358ab3cab0ab916e401dbf2762347f780b164802519fab27b75fc50ce6d5d757c888bf97b1317f528557fe11d4660667af97e183a69bdd20eba26ca03ea	1	0	\\x000000010000000000800003cbec22ab6459e181134800a11cd985570699d30f60272b41dbf6dc48071586fda9af0b1cdfcfdbc9e4b70a47537335a3bc357e4e972ae2d99b5429c734b9aab9458cf8a8fea23f0bcb07e9dde7bcb2bc9c57359a62c8e53b53aa09025afd6e15ef4f403c0ed660d79c6957a5fae05dade021b94b3bc393b86dcf1a22b728afaf010001	\\x7444f984c55740905b25f10b806e081c4117ab71b6895e5b8f7dca53445fde5c3d38b9def3982048544572e8274f5baf521792377e07a727abc230cbe808cc08	1639566456000000	1640171256000000	1703243256000000	1797851256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xc9dca3fb5537f3dd561f5e54b4cde3b7c704f4b4865e6ab809785a07095bc48df94112964e47b6495bd0c3059c4e214811bf95cd4b5b373555f54236bb791d07	1	0	\\x000000010000000000800003ceb4161f1121235f0ccb4b3ca69f5f8fb53f82c9b94ef1ad8f546e998042330a7abc98e348a71bea8d1203a682fc25c9b2e888f5473572d6212e57bd35d1a8e34df5da5fdbd1ced698569b925eb4953b6966626cc5754b182fd3c0444a19625acc20e512a84b8d6bd223ba138747f4c397c4c979a97e9cc6d855299b0c64dc13010001	\\x2035b49810d749f7e92b397caa30ad04d0dd27aa3e0c3cdb4b59da81c0269ad64f4ba06b37efb42b6cf1983ed213267169dc339d328dd46358b634f5cd9b9d03	1652865456000000	1653470256000000	1716542256000000	1811150256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xcae4a42153926252442729d7e0e189022337ebfd5298ad1ea6d5396d6231273ed2b1dd3e24bac1cab524dd708eea859b9dd71a49eb8af78a138fc8bf691e758e	1	0	\\x000000010000000000800003b1d4d5cd43be271dc4baa6b1147a17595adfeddff0dfb7384e23d638989a6d85ca70d58bea67ebf3c64cf79203e1bfc9e98910e4c2458c0bd9e0bfde0b87680b0e930efd0896729c652b6df68e2f0910dd78c7d788e2223d2225b455965dcac34b6055ffecf662a2260f59a7fac34efdb0e560796fb5c9992d4525568f2d4071010001	\\x08218098b39229426dc838440f8d375bf62c95c3f8693d8498f6f6fffdacf60056a718d4bff8f5eae3690bfb2d865093ec6adec800a31126df97483e4d2b4a03	1656492456000000	1657097256000000	1720169256000000	1814777256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xcf70de8b6ded646413330fe31c0d642297281eb371df75865242d0fbd6a8809ec1610dcac6784a101f573a2fb1a3dc654fea392e60d1a375cbd8232f2397915d	1	0	\\x000000010000000000800003acc0a8f388ea7d25d40cdb9720a09a501265bd4581601e30eb6d5ccdf3795dd23bb8fc2566fa49a54692e251d99f078e3509b0e40913dd85e17c366d4bcef89dc8afab09e6aad82cbf420e5e4cfc7a2f5795a59a9a378f91b56b623f624c59d1b87a755d91b763ba249a36a83cfff133d7d9c68c91bd565c07fa78a577ac9b81010001	\\x1c3e3aaac03d4d4d493a2c6a4608f0a9e9520c3c5829f0c2f3223c721b9ec28f7881ea8a68735b1c0e323521dae46a430ce918387aa4a7d58d0e488bca08eb09	1645611456000000	1646216256000000	1709288256000000	1803896256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
103	\\xd35c75686a8eb60cbf2a0f0c833c359a3639f2bff6f0db94c8e91469d6d467cf611ab0e56200797cc364ae3795073dfa5714fdaad4ca46bfc1d12eb33825d752	1	0	\\x000000010000000000800003c9ebbb5936c2b7fb6c2581d62cd887c07cf4b25482475564dd58cea6097a675d72979cffc17caf1332251c02720506afd19282903d2f74b7264a94439462aaa3054cd7fdbdc40c4101a7e743f580323b9eb359daae16be249acc1023e26e1247ae4234c14b1c111f0e576dc7b9da90b70272cc9497f0032e6b06fb95f76dfd51010001	\\xaed7f4b487442493e3784428dc260d0d41e51ea686381f2b73b45f45343cea168b5c662d5e585327f42a207e862c7806fe1296308fb864f4763ea8753eb9b909	1641984456000000	1642589256000000	1705661256000000	1800269256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
104	\\xd89078274de3b31c43241b867e3beafbe716eb52b26456e3e4448a479ef85e179355ce72d5f8ba8ec1aa8dfd5ecacb0addab1e6907aefa587452e724e244f06b	1	0	\\x000000010000000000800003d0089280d46cb8d70aa9d5b619fae2a3cb2d609955d37c3f531f459c6670dbc0b41cee885c4cd980c68bef372a47f99ac1ba94b2921996e38e0d5328c9c90a77f30532529879380d5498f6f8e03cb70ffadc5050b8420bb95e16ef5cfadda4fceff03042ef10ed581f51b75b131005b920d07ae63f76652381ae20001fc08263010001	\\x38344a005244894306f901039ab5eb535c5a1582c1686dbbfd5ef540b9fa99f7166e672a17ae63055c035eebf54a3c16f092e636fa707a0fb807a7759efea40e	1653469956000000	1654074756000000	1717146756000000	1811754756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
105	\\xd9a4d0b4b433a7e42519c77c8279147ba90ed38e72a865179e9451eb608871510c7589b6b1e12ab1827426628f4b4ff5f6a97feb2051e48b0fa382b3a7ad77f7	1	0	\\x000000010000000000800003cf56a1bd95a605d38946a388b2b232d7ab379aaeb6680515630830d7e6624bf6f3f2655995ff4227520b029588864d80c98f9f11d2e68155c506d5e59549204deb059298827d5551189e916a4c07da0d91157a14995b168e777b33bcd2f94d487510de987e7eadfd14e564d78934041b22488f951bcb69fc904cb43ef1762d0d010001	\\x68976d390b36ec6e16e798e7ee12d93584156f03f79ec4d70100d6dd50f6bf33b755425ec3b8cce5cbcb5585f7aa7f5958f66d209e9856ff8d6e6777cef3ad08	1647424956000000	1648029756000000	1711101756000000	1805709756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
106	\\xda1c1d9bcaa26dcf76e91a32cbf4517cd9cdcb244bdfd983d025cf83c9cf46fae124ddec9318627b99f8cd34875a2be5e399dc40c7ccf3fae7825cb2c9cfa1f3	1	0	\\x000000010000000000800003de6da1a2e02161b0b55bfd1b138cfce065bc60dbb16884ab939e0243804b515d0ae23fcd3ea42c27a10826ca9d265d04574d7f2814ab5a864240fb4a1c6ab7caa3a1f8352beba10ce2d844076bfa05a3895828fab07813d632e88385171432da97ec718008c9cd8ad462b1394451990cf3e4c0bb97bd80b6b98b350203e901f7010001	\\xb0431d01348a91c96308bc7a8a54c6473332b05d5eba7815f517edec68a98cb1a515e617804817a28a423d6f92d7fa0540a27f7abe860bd04e8437b0f5efbb01	1661932956000000	1662537756000000	1725609756000000	1820217756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xdd74f4163d39494324de4cb1272ea365520983631a2ece097f01e66c661bd9316a1e2779b16beb1d170cd7f4d545f33c978f9d20c08cb3877aae01c1890bdb9b	1	0	\\x000000010000000000800003c0fdde4d42ece11b6db79874b3c7f7280b47254d6ba9cf3a5f46c669774a4d8512838b350cda979ec6aa99f9bb6fce6f1403abdd7e1126aaa3ab5a756f91955a3f0cdc2b4fce1a79afd303fce1e925e46f944c0e6bcf9beb5c25826aa7fe020a023bd49e8d23602b97748091952e51c30ddbcccabe0ede10e89103ad7f769d77010001	\\x0b88b441ab1e026526dbae5f9f7d193bcba7784dc7f92fbf559a1e841f3c11e80229a61ef76b178fa67a3fce9f9f3626f0bf31721a10b3e99c3ed0c5addc780c	1669791456000000	1670396256000000	1733468256000000	1828076256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xddc8386d4a4f81b0916af93666e9304f0f5f16210cdb69cf7ee8cd46013c6fc30adab94372b85d89840dc03e2067191ebdabb9da4fc600fa6278210ae07d3d14	1	0	\\x000000010000000000800003b4880c30b172554dbdf36f980708d07209825278b4046e26b9dde9542fec9850c38650bd78642a85c54178fdff08126188dc32b5b17dda7daddd0625d6f19e30e1a828ac83f2478589df2c4e5603c8abb63f893ab6ea392cd39943d2f27fc84432fb3d6a62495fb1ac5a4ae26f81f4916b0e10a0ae1bef92a980178493d38b25010001	\\xbc9ccc2bace2d14cd51707e5ac701ae8791078f7624d791b2bf7dfd895f2d135727892c442e3d5bbed830c2a56929779fbebd63a6534073142b3d16e7494d707	1647424956000000	1648029756000000	1711101756000000	1805709756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
109	\\xe5781c690c79b702cdf6a0642dd2589fdde2ae6f05529c280d793bc51fa4984a788ae1a8adbae5a5e847dc75cc8d1816d1c70594ea339bc6033d97d2e9bf0cc0	1	0	\\x000000010000000000800003ae88a2b8e87cf06ac8f61510dc7ef3cb0c8a744e9a14413741dcfb96d875084a56379089c432f8c96ca1d8f0eb6bf86eb3c7e482ba1906ebcd55e0eeb228a4ccc3ed43f0feb1f9bb62844c9153e5eca8d2ea9c9677ef2f71438855b1583510a4c1744527aec0c7c3c1b71f920548a492a799048b2d55030358d7d9a89503390b010001	\\x22c5eb8edac732cb5ddd5b40abb59cfcabdc3aacc96ee6f1c2a3b0df5bc2ec89782fed7343fda28a298a99864a2c0389a97c3de8ce9a4efe27ef337638a5cd01	1660723956000000	1661328756000000	1724400756000000	1819008756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\xe8d42b806b8c821d2e68fc1edb3a17e8da7dc38538c25327f40a1819826b63ddee14b738fe71c697d140175aabcc260d2bd4e566c6944bb4daf98d512e38180e	1	0	\\x000000010000000000800003ed2827cc9d38f6fbadb4f5ce0be76223b5b5235dd2a91930880e3d618255c6909eeeb17889f127cc8b3437b954b19c01d1f7ef7d46466ced18a473702ba256efe24778833053a6ab93c984841cffd07650bda4044f66311685b431ecd518d577e476f4fe60ab883f56b2861e195a3d1c61146f4d3d52d2c75309f8bc81b7b8a7010001	\\xa439196a80278fc9a690fb7f3e210ef6dcffd5c683829142f4020c65743941d2c4543e5ae6a92fa0c9489fbd3902d11cb2e497cda049e743df0e17c829451604	1649842956000000	1650447756000000	1713519756000000	1808127756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\xe9d02f95175c676f98648e20556ac94ccecb17f40f06a4b6d2cb6ca785617f972caee5af606135f9c888c547b92b3568e8db2970d205cc35eda9527f5790b737	1	0	\\x000000010000000000800003c9c4e647813237db301c6ac14e9069742d50aab6592a4aba5f916972edddc67397dd871070f09c165e365fed547a33e6626cd7c082d1d1829cea9edd6c7036c804d0a9c2e3b7cf4ed4337a8a9e3d701a73222580b85ca024fca0683d3af675a64546bdff80634508dccf454b549e44540a5d430427704fab2d0bb1cc097272eb010001	\\x66fe8991fa22701623d55af940187a1b6e64aab844e8e924e5b890ed177175e5f489675d107f54a3ed57b63f903c6e497747709b82840b2e5812ed039ab57100	1655887956000000	1656492756000000	1719564756000000	1814172756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
112	\\xeac868b90d9930c766ac24eeb1d8498ae919b40bb6b8cb6e2c9e37fb256451999deceba2061da1af82295170b43c7060dcc199b8c9d1cd15ae466d8a19091e0d	1	0	\\x000000010000000000800003e2fb7c9cfaf26d14e424ff8d4b55b0e7cdc286c5838cf3680bbb0d52b3d372ec07aec7142ebf049f0993647ccad0cd1de9a5c0dbd1ca85f6c7e1f164a142ceb5dc6fe6e329fc95eb18926c756ec7bc4e23c4a9d5d0396391eefb010df8c0e6952a6e5fa2020fa4382578273886468908dc40a0d7328ebd6b65ab9257a64c0a01010001	\\xf010fa94d59ac0f116313c03593f7aa4eeca758c63be1c2cb1524415c69ec7eadcedad12345d3901bc465f3601e3756e2024849069aa639aeaae5589dd689c02	1657701456000000	1658306256000000	1721378256000000	1815986256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xef94fcc1614423ea9cbddfa2a5ea77e8084f5596327662af4d8d4424efd9465e1b2b89bb4996b8c6ea9f370aeea1c78b813298225c5638a7d8505f5f3befd630	1	0	\\x000000010000000000800003e0483ef755b115c2e4aa424dd56d96143a7b09b6b49cfc91935ad89a153a5983feea6042630762fa1c0c95ddfe2d9e7710e2bf4a9e904f1aa7c65e2c08711f5fd30be8a217ff29b6936c25c1fa68f028ff3e6920f8667bd6393ca706ff2d367df7ae05b5eb5820caaecc5716b12a2c94323d780b1c39e8dea5b6b47ffde97dc1010001	\\x2b4666fbb6ebe1b21758106a3b514276fee8985995e34fe09d98f1c1574ad67f6dea472a3e664676dbc7de7171017b274a9e0b1be6fbf2bc789fb029d9fdb00e	1666768956000000	1667373756000000	1730445756000000	1825053756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\xef245aea646b4524b1b1063c89ce440193e5f152e76bf1992b549066871daf004bf8a298c86eda5a49a3184069a3c6d791b535e1e59a936f89688ea1eb4a16fd	1	0	\\x000000010000000000800003c58ecc82c8039768586f437fb89ff937308a76a1c0149fe970d39011b78ea8affe780caab88365f058f7383c8891543a2770231ba54765a32e2126d70318a9fb65553ea58c2e7589d04dfae6792b873b05f68d0731f34eba9c88d9116d3ae6e48bb2e119083b1f9b1ac137983421e944eea4fb2a6a22aed672b2fb627cec1139010001	\\x61a823bc380891f07bcb51b8bd0c733693b82f1c10145d4a31c95df8f6386f9b86f5dcb325f6cc39da7cd569c06a22223bc481eb4818782f65336958f631b205	1669186956000000	1669791756000000	1732863756000000	1827471756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
115	\\xef381beab39aac38f690dcc858374ce35927ee9fb6737aab4c637738e8054a4d427fbe6008398a56da578715a7fe9935d6471c9925604359d91410f42abd00d2	1	0	\\x000000010000000000800003c72766b81d14b3edc80ac2e99f9759cc2351775a6b3ada26039348903d1c68a698d18dd995e99283162167e9a9f018a1e10a474ebd1e1e93862ca74c40b2c290c91b9e12e3e495044525b735ce02215fb3f7a823a6aba8331da65e6ea1eccf25b4018d44cb77f7acc75b90ae2de23ab3b81d3ed55f97dcb09841e09c0912f94f010001	\\x1125bc001bfe021302e85c768ef4fa8a3dc95f30db9e6b8ef1f151a9a6990fafb0ee9bd7923873f495598ed8accc6d4bc1a49aabe0a151ada4fa0c7602943209	1659514956000000	1660119756000000	1723191756000000	1817799756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\xf10463c0abc33fca5e1f2e3b186bc60a30315b8d76dfcd8acbd5f452a02451c3bc1d402f7814b3ef549e53eb0ad1e37ba97f300b974045d4d777dce6e041a49c	1	0	\\x000000010000000000800003e6c9603e9cbb21338dd399ec2a9e2a7b539f6a366e16432415dc94bf4829b7cc64851fb3ef2224d70ac5c80d728cac60da52b56deddc2214949ca8f564b9a5420c3c00ea29635bec4559be8da7dc4fe749a55c88514b922100ed2582e4fb4d49912a2e9492e4dabf905843222d4c1d7d1e6b69ed54bee8ee2d587dd561b24ea3010001	\\xfe0026be98739d093c7043f63c432800fb064ada8ca810f0bbc5f3a961f23f3dcefed7ef0d708f86138ce6a3e9b923f72039dd235240cf930fb6bb86ba4a460c	1647424956000000	1648029756000000	1711101756000000	1805709756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\xf1e8313f0fb9abd9580cf104723d9bb68278195796942cfaf7c3a476ee9906347d70855325a938a357eb8634309cb6356cb3fed70d9fae3dc4e911341838c861	1	0	\\x000000010000000000800003aa9e3d00e1250cdffdc81c051c290a5a0f4c94f9f0d7a2069444f33c2973fbfe38f49854d82e20480232f879353ae615b26dd2b90573ee22c35fb02c9c20140bad63d3674a2b34d3cab433b4d7dd1657c6230a534811d15a551abf892e1409b6515f989f579907a988dd652a47f26d93039c29368705f8864813e2bdcfae1d67010001	\\x95bd118ddc7cef09e85fb65d13f844730bc7bb8c399582d8f6df27aecfd582cb44c05bff419aa553f467ef2a2e5b9585c22b55c86d2fc60c17d82d83dbb07807	1656492456000000	1657097256000000	1720169256000000	1814777256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
118	\\xf4bc830349aff254244ef3fcf2040630f0a8aeac12b24459c51ea0a12bfebd77294fe1228d6441f6f46b6c0edcd0bd28f09cadaf63dc477d3a2478203d93aa40	1	0	\\x000000010000000000800003cd8553be236815fc09fcd0ddbf8e989c0852c683fe16647b0054e5db5d8519a8c3b906d57111af0de47f3492b5a97f3b19c1befb084b1deda284b2a0bd917c749bfbea57033b0695a01bbf7380ac4ffc2e8ebf77d3e8db10652dfc42e079d576c4c6ad2380522810408edb07fc3fe645b26254af866845d1d1754319e1d03917010001	\\x7047eac31eb82494d329e7eccd2606d39283203b355e8e89f2c18cf55ed8bbda7f03c448a4919dc1f3500221e6b93fda5fc944594b613eb774b9f1b6164ea706	1665559956000000	1666164756000000	1729236756000000	1823844756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
119	\\xf7f810538dc3b690f44ab13c99bf7c477730e276797973a54f22879389eae0ba7549620af370806782f04c0f3f5a7bc41e6d89a659cbc7b5e54a89f5bcfd8df2	1	0	\\x000000010000000000800003bec29ef2b9c8641d71bbfc1180ee018d417856a0b60460bf83e1a3c4206b6dadb1bfa13278e96fe8cc7500e32a99f4c7f1f79e535906d9c717e4e103c0ac3d9e52a2b47721d9f0cfc51f8e1bcdaefc8fd247c072253163a83dced98a169b1fd1572b3b7340088d2940a5738ef1a8721ff9cbc051092bf26287415408e2d0764f010001	\\xb6ff375d19075fce2b89d6e844294c0f69751c6902beda298e90e23e890270150d5c0f2a5ae8f7cb61d80aaf6d3e2b8ead7a65012902618ee0ab2bf75726d308	1646820456000000	1647425256000000	1710497256000000	1805105256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\xf854421968cba341cc2c3240d6f4a69ef4f3a4bf0467c0f35bddd76e43586b53de036ab52175483928db80232b85ea6e75e36c54b3169e46856f8fc8249024c9	1	0	\\x000000010000000000800003b2ce16db2870436ec252122171a022a6df552c8c07a28bdfba36275201b583bc67555a9ed8a85d28f2c5df24d118178eac9c11b133242ec18fda5cd111e23211f0678e78d31a0c86f2ea87e77e8c1c789d3484f12ab1003f4540273c220835d563d9cbfbcce875f08e44f66c77cb6f63d8012c3f6186860f4bb220df95b11629010001	\\x09caec424141e368b7688e802172f51a1fcdc0a9b2d3f470aa3ac6dddc832f5cc54211f677a5a0190b8d4cd792fae5f009c69873747fb71a3a4b3cf9ed405c0e	1640170956000000	1640775756000000	1703847756000000	1798455756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\xfa782785c6304f2ccebd29fd4f503df02e61b086db1ccb5e325fdf3973b538072e07d179cb125d404bd83d57cc11a8261aaebeb633f71b30d707adea69d3eb8d	1	0	\\x000000010000000000800003ac9887a03af71d2fdd8c4384200b8ed35d8e2bc0ca075041034ce790732235e87e0872861f6290f609a781c3f8fb45e6a784fc3ad686fd0dce9c34bc0a5300d16c68783ee8bbb4240bd1327cd0b7f7e91eb008bc17b93e4d568c82f1fdbf21b6500b04faca8d44a7b087b93d075fcbba58deb38158bbb75f88ea7df205819d8d010001	\\x1d01b2cde8619a534be305a0a718a903b07c5af2efd80e3422b57fc7e8077ba222960be504c27fa9eb27575fca9c4a7330e9ecda867645d4eaeb5045f8d3340b	1660723956000000	1661328756000000	1724400756000000	1819008756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x01e1d03760c3deadbe390285c29a65e782881286fd96452e3b32c53aded525c0f23f5a893c74b392b541b26cec85753d560326a3b245a83c471b8e34b8138a90	1	0	\\x000000010000000000800003c993bf180a6513eb54f5986d1b4b8f6eb657297443c1ebb57fa8f741cdab853ce7973253886efbc30af7eea365860b05bbd7649a27b77abbf0c2f1877db2ffffac2dd1ceec37fdb63c9cdcc9c08a50a29d05ce6e375e8ccfe64c81424d617763fcc580fd44cba1af3a09f346da8838edb132a0093f29f1c61ebd558587211305010001	\\xfb902fe5483cd825b0e0d22b9a24871992f0f531a7148fb56be4abef0e5b8870be8ea9021a46c63e63c18946526daca55e067d3bf2c497fa1b6a857c77c12605	1658305956000000	1658910756000000	1721982756000000	1816590756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x0509167699ef12bf8ba971cb569378dc0fd366532ed9aee70160b4689e3938eeb984ef2dd4bb4b250d8b736e7225530c15ae3157c42aa38ec5f8d9176815728b	1	0	\\x000000010000000000800003e0f66a4f024d8efd790689dfa2be95d995c438a51bf3e230ff9d23a42919fa43f28ea2563aa3932a839f523a60dd52b854256443880fbb2f9befa518a6107762e0d50f4fb31e44bb0a38b032a6a574e9c03d1fde03c31ad98a459303476444a090c13f130b13981bef0e27b47c619fe787eab968ce1f6036ecb54e998cccd7b1010001	\\x398a3b8a95a9fef8054b80670d0e9d93168ff85e059fa25326716e26347d3e03601d92568b7d88c1f18dd0e83f0aaca1003d04f36d7df92ed5596fa814e9e90a	1638961956000000	1639566756000000	1702638756000000	1797246756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x05dd2be6733c5a83d2aef40a12117448f889711b7aa0c60e723986998dcc0456e39f28e74a666312acf40bce374ab6b43dde55bce5175c85ee0e25eb0a65c1ed	1	0	\\x000000010000000000800003a0f641405e0a70f47e1359550df587e9a7e650b6ff7a8a27441437b3947bff483b105f6cc9d42031df04d3ad9a4dc36fcf603003494249322fe4557da515330e10480e4beeda0d05de34118bdd46cbb8de4526c86f60a42ba18f512ff4bf847733361c4039ab610d15dbe52ea9d0deb6eebf4f35dc3c548b93148befab6bc2a5010001	\\xdc28f59ea80e79ff27fe93a0b0bcee0241b9c7c3ac06e6ba2e5fe01cbc7fc4789b8280a63e164b7516e2cd3b5915b16fc8f86c75d25f1b2e3872c15c5f036b0d	1668582456000000	1669187256000000	1732259256000000	1826867256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x077994449efaf067c90963507911b4466473a3546514b48efa3f1bec7fe8ba1d53ac909cc3badb3bc5bccf8302b3dac7ad4311f77cb876d35c2895822715655f	1	0	\\x000000010000000000800003c337e614de5f78ff30a8795f1fbca0ad42cb4e006eced93b65e0ed57c41c0a1502271ab0397e0ee17881ab18f3bac98547598bf7263cd8296c436443442f6759584fb44360d8c8b0911f5703dc1942c01d0bd1ae03d846d1d907fcf4e45da72dcb19a20e79d1de05213e9781b2a7c2af6d9053774a168ebccee87b83cb970e77010001	\\xffc3dadfe88c3feab9fc4eb8c8eca7c45427c29be7227c7f682bc6c71fcf913553b9b6a5fe37a0ffa031f1fd121e87019bda726783237abc4b4d9e79c85c040d	1663141956000000	1663746756000000	1726818756000000	1821426756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
126	\\x0971df49cb60b568b44b13ed9ff0e5cfbd64ca608300d022eaad953840ad2067b37afa527cbfe5997a8818d72ccc8c6505649656387ca47dbae6f876cf878d58	1	0	\\x000000010000000000800003c3007ab4af9eab79202c03aceafbf930841d2339c684cc52184a953e1b0abea1e76add20aa53ab4b94d89bcff455d43788e99f07ea7e39cf1a6649a1252c739b44a3dbb9b9e9c6c1ab96c31f833dc066626ec25e9148f9fdd8826e325ddface60e0b3bbfeb60052547b21ffa1e0852ee25383715a921984123cfc74ab5e67d2f010001	\\x43f8965177ba1bccafae166ddf600370c69dfb74c454e0c6f9ff76a660759a2ec7463a445a57a55f820ab757fd0f1e763a2313053077cc2d06d9f32abe7d7f0d	1663141956000000	1663746756000000	1726818756000000	1821426756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x0a912d60587f0c1683a43f8d04b23c8c0ca04eb3f1503130f495f906c9530a3ec5e559c8676d435ed8b94bfc0fa76854d6931d83992e83432496073d3ef060cc	1	0	\\x000000010000000000800003b1846d6793e1f8d71cc4db448b14befcffeb8d56b1e721766df756542141117e62f23430c76098726ac84f5bb7e5017c9af27970dfc32c964b814005964125ac61c593913d10ad03ecfc2814e0bdf5470e82dfe766abc6d583d5377981088ae28dbf661e206d6d77b8c0455d1dc723cf90e0d1adb52b9606dbe227809c3db20d010001	\\x0280c1123ecd81150e36120e637f445c7bd8e4128d45983e30999e209fd974c2c83d213761a1ec7071b2c255f3830dc05487a54a231aafd1bd4b0d1224271305	1658910456000000	1659515256000000	1722587256000000	1817195256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x0a4d8d254bb48746b28cc4233d4058e37a5564ba6e49fbac2bd1733cb53ca8f0dc52ae580cdfb4b24b422f4c3d5e97938ef1e06fcba227bc87376fd8796af4e3	1	0	\\x000000010000000000800003c5097ed9347c7841e6f546a9b678d7c0faad9fc0e87dd0f919e8b9713c7b475cfddba4e183d4a8743be59f5d9fb290b485e5871a4c2fb0016e36edca3cc51f544d830cf1969ae1ba4ff7669f49041c6b5dd8ad347a3717ac4988bd1cdf44ff7a80d8780898d8f0933de951e1225c89590bcef5d32c6fb0094811d52871a6156d010001	\\x679f1a37bb0f7bc1fcdc7f7ac28e364d2337369e111b94494824bac4bff292418e682ae205ed215c509e6a38f5dd62e6a58266a91406f5e5fe157b81f8868207	1638357456000000	1638962256000000	1702034256000000	1796642256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x132598bd3d1bf6d41f56eb5830efd6b224b04143dbb7c9de271d2cc01efa0bc64955038c63b768756785b73251c5405f2c0ae6d215f058abe74a4d70f6fe3ac0	1	0	\\x000000010000000000800003e389f10c6f69a89ef064cb88f8643ddc3cf78d8780d888d1c7879947eaf9efd9231dccb737418ce7462107d030663f75a2b9228ed140977fb725850d9eea567e7b10b81617a2bef0805123f0d4641a1f232473c7f5dc6c03dd62175e4c47e98db2574e42b669c4148be308f901c66ffabfadcb3a60ee93314490457d8813fa43010001	\\x6aef5b816fb5c3ffb5458a0fc7b346eae15771d4b2e7046f548dac5b6bc101d726011554ddefedc971ff8111a67fe7ae76e5cd4cc4c9c65ec9cf3bcdda585a02	1667373456000000	1667978256000000	1731050256000000	1825658256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x167d5cec3ee426de1dd7bf0e8e03a708cc77a2d39fea9df89de59a89142ae5abe3b1ac1c27688b66419d6f8017ba677d7afca08dec5dbe24b24c6f271b074a16	1	0	\\x000000010000000000800003e18fb6de4661c3810caa1e031456d93285b698139415f1705fcf651409668a2a962a26bf348495194f566c617eea7ed61624f520b4b1876243e11097a92b85b996cc76833dde9ba39fe7cf69ec8e9ca2ec7f8f16ddede6fa0e3d01e0873b245c2c473955ec74f5debc2c2112a08971f768b98c1f2343dfe3d22edc29f7e5fd07010001	\\xb19f8c0fbe8ec5ce34cb842612f63181dda8c6105d8cdb4e1e21f15575eaebb0bfade6a9e2ea7b3228c356abf64099627813f09abcbb87a100912ba76d561700	1652260956000000	1652865756000000	1715937756000000	1810545756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x194da47ffac72e36b8aaf94535f506a6916e93c8d937ab63b7b4bf0d25851d58fce1c3df13c1ae2fdce510a9a3f2d7b1c76e80fc37f01877acf248159669c941	1	0	\\x000000010000000000800003ccea4b0f150e7c048e8684b590b0e84f24379e9188fc9088234fb80136ba23db414fc99aee601f39ff9924e14d4b629fd79b7d4cbb73fca530092582129732f72bd3813b105e8d8005c0f62c10566bbdc8e66dbf6bd3a1a650f9e56359b7f17f2e4a6d5d925d0755fcd4c90bf170530bd67ff28fcdcc2f60e03932c240fc4621010001	\\xab57250b05b28205fcfcbd9afa64f7f37786b0b3a2fb801a619eb38241d123d0cd88ff81b3d67e826a58d486b288083add2e870153a44ede7ebf7039b5411309	1668582456000000	1669187256000000	1732259256000000	1826867256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x2075b1f1c47893815cab9ed8dd92f22e1cadd0f1521da9b9b2ad9b72a484c9748287dd1112726d82e6101dcdfe634a99213f6e6c265e9c7558b12d396906051d	1	0	\\x000000010000000000800003eab7ee5ff00606a949f408c1881a61ba4a90cd8cf25d0d140da0de5e023e1a10c5be3f070742e71adb3ad96a686886e305706e2f072321a4e644f108cbbf667ce812211fb1284adb3f6778caf593df234b88d4acd99e451e9c436cadc965c5f60cfd28c5905a4c51dfbe302d0165d67806ec22d43c1c61dc2269cdd919a7ffb3010001	\\x6c1e2460313911a92895aa4afb9ce59b02f4225e200a7ce1bd22ee5d01124368c94e938862a15ccd8663357264a325c98a1f9cca7cfd7251a8f388368c443705	1667373456000000	1667978256000000	1731050256000000	1825658256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
133	\\x2ca1f6a944171e6fa5f98c3762390d0957663c1c80f349fa0a9269541228e87d6a8f0c2e3ca616000a4501d549a4d6eaeb26d297e40f0501234e6c67dc2de19e	1	0	\\x000000010000000000800003a005e7c6cd65e632f58e72bd821b56e07b06b13167cfc5ea0f65e3e3c6155e2a655de02ed4ad5d543231f875237cea098ada489636ec9579a9c919ec5fa44da419b628c88533320f8fa31069614b6160b34162fc5850f56c3ee130e7c0cc8e4be328e4d1ee28ab0828b791113ba639f16daf4b18f040c467c129aba00803b003010001	\\x475868d2228c35fe95c95d6e60272ac781d57fa5f7fb48f82673c2b5ce41e6c63e4c53b75b0a4e1a1ef7c55566b54cc2a1e09a3cd683380cb0a7178eda50ec0b	1644402456000000	1645007256000000	1708079256000000	1802687256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x2e79d874dd63f9b71da92f11068b4f131b3740809c915fc48c3d44bbd16b990bdacac778703b23eb86d8cc522ef2ec6fe3350a62cf2129f7e9094a80216e3d10	1	0	\\x000000010000000000800003af6a9fbe3ddb3931e50528dc6b5827de168d2d79c0cf47d23cdad99558f1c825282c4b55f126453674d1c207d2c2fae565c8cd082692c152471195970e47eefb4cb8d46b659cde8a0bf2c21ea6b114ea402161ef84b76b362bd13108af068c743c8c2122bedf7ad1ce4e6a31ed372efc0fd3adb14f600fdd786e8662b04beb09010001	\\x20d2a7afba7d637f83903a928627ec573452dd30cc8143c83f6f6e8b0fc770338d1a66f8665f9233fce7688041e7e35cacef33336e756a79935307290ce6b402	1638357456000000	1638962256000000	1702034256000000	1796642256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x339d0491a815aa0c69b384a7295d3ac1c57152316c26c8846207b40894d4f560001c745343351474ee560734481521a71b6b4da5279ec38c9629372ef165450a	1	0	\\x000000010000000000800003e282fb9bc11deda2db6c7f3cace7a7ef78fa2a2d0c2ae63158cb50e7c274bf2b81d9d393c2debddbc5773fb7304aeedc0cdc6e87bfce23af42714621cf1777f1b2ffdfafc6c5d0774fc98b8f4e26c2f2cd1142052dbca2be6f2621bd55a7540589b8f12ba8bc77c47accb031892bcc1a8fec1e50b4bc905d4003ac4783fe62e9010001	\\xaf3d5d843246bdd20b5a0afde15afe1ab3dce26fff423c4838144b46f5c7b5467e8ea9a79c25a04c8cfaded5ae614f934961fcf68781ae0a90524e4081c2eb02	1648029456000000	1648634256000000	1711706256000000	1806314256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x382509589057eb536aa5514a05acacac22971aafac21831202c53050d7fbd5cf41beca31d76f00a14cd4387ab903e28bccebb5a1e8e7d7a072d41ff47aa3eb4b	1	0	\\x000000010000000000800003f99f0b5b533fa6afc0aef84d1cbc19c74e2031a93e0c631ca7c687aa4326fa3cf505de730d6667b9cf93d0e9ca613149d01626a22234c0e13695519ee46369893b3f2ebb9c3c98cac4dedd66107c93dd650badaaa353737c09407a77bfe0e197971977a60433d222fbd22b9a692a2a48c32c6757e3aa8472445602da52d121bd010001	\\xd283033f99ea30af0546e46bcc5b1abd3c6f69e751917d8c97a18b573cd1672f2f975cc40372cc2caad1ea2be1fcd5905d56f64a88ac1110dc3172f8d9c7df01	1638357456000000	1638962256000000	1702034256000000	1796642256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
137	\\x3f3154fd95fb6113968272c0445ff4dde5fd1f6e60f2783dd4057d06f5b7562bc5dc1b88ba57912d1aedd7f3113fa0de6a08b8cf7b829e49e42716da028c4f2d	1	0	\\x000000010000000000800003e00087226d929c48ef1f8daf8e6fb905ce274f812f1e0f37b9b9ad809a2714ee8a66b8753fae92fcff080fb54344e7bee83d601296b00c70af42d12cb887e7ebade2f36ab229158742863c02c95b7ab2800ba6a45e8909acfb1bc73abd3320b62914f67c67233620aefe4334712cb745b7428083465062e7896a7a70ac4cd669010001	\\xa5fb831864db5f4da3f346beebd5077754669eaaed257646f4e70dd9a333aebb8d4526275bd27979299b3fffd01beae56c00afc4af364973165f673a35c5b803	1649842956000000	1650447756000000	1713519756000000	1808127756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x478551eecb48335ed16a720c780a78d5bfb3d87657acac784a5034ea57918995243275e8f82ad7aa6c7a1b21c50cb5cad0a94a6930b186a2bbb860af00fac809	1	0	\\x000000010000000000800003cce0778a95f9025c2348ba59eaac067c6bbe8cf19fb5b6040635a282384014fe8086e11c0ca19c54a3d33e57859f0700ca8396b0d3cc86082672dd8ac54c8e2ca6c075bf743fc5e6ccdef7f72a6d6d421efe244381e446d74613f02f0b2c37c1507d56c444817eea501af52188292ec4f8f881bb5219cb2723120214c2dd473f010001	\\x4602a5f4957e531527bb09750755d5a7942d5560139a8df2974be83d432d9bd27dcbc350d4263f3f14936e6b96f7b87b8082db5b72d69f3ad37dc1870e5cc807	1656492456000000	1657097256000000	1720169256000000	1814777256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x486d6a84ee8fad357d57308113a95b596b1aa60fc4d88f256f683fd99f7b6f7819b0d93def07d0c86e8942f3541ab261154c72c5cc4f8cd80ef0c14a0835e1dd	1	0	\\x000000010000000000800003d93e03f511fa303d402f4548f09681213242337f6f92546028f51edf51508bf504c6f8e36b040f50c75618c9bc20842dce90b3535362ca4a672da269cf88cfa1dc08a7ed3643327e511c576036516d730afa51ab54d95d84c4d61727963c0a3e81329858618af469c0c75bf51f0d5f7b369afe3fd976552fe9bdd4fdff62d97b010001	\\x3e836e2078755e27e3c77164378fbb6d54544f3789f8b101645e5e4bd17e63417ed8d45bd78652243f3e3e0dc5d15357a455712f03dc397d5f3e92569d83ac0c	1662537456000000	1663142256000000	1726214256000000	1820822256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x48b132c68df012a495dce81c1c13784b37042c5ff650337f52ba6098dd4882a14b68e3e2783134d2e5d014fe59ddf2879cc10c3c3e6f7f3b614a6ff09666f9d2	1	0	\\x000000010000000000800003b39fc59b82542a21442c808f8f33dc39ff8f33a3df30300274ff4aa1bdd0b12655e1160838fbae76ca02292aa8d48813e31ace20beef013adf0c1625f6e9dc4e4d28cf9c9b3b94a9e8fd2cff30acfa323988d97c1a6830efa571689d4281ae2c4e30846a645ed092d3c000617833d28e4532bfa2064e260acc1ec28a23523cab010001	\\x39432b38924cce153ba28bed15ce73070fb65ace8f9a760b7ab95d2c4649ef261f605dddcc4fc7063d3646394020c05271c05cf76c742bba67aa0d12a529d505	1639566456000000	1640171256000000	1703243256000000	1797851256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x509d690186ee0854a5c872fb8f9c2ffc8054285bab38eefed07b6fab896114f48730ee5a335e243d7001533c619fccea82fca93618f4b4d1822fd7b7c85b40a0	1	0	\\x000000010000000000800003c3865da07daecb5d5435b39a5ad3131fb22b18801542f7dd9aa91b75c8a0e05afaece001bab1463403fb1e67640c16c483ce0a31f52be7c14c7996b9528706d7f35623a070fe5ac6476941a84fd34187dcbed611353d3c1aa0b203af2a27755cb6095cb6c1517b438cc858f3642be6df53d56f1ad4388a1b543ab42f6ad0a66d010001	\\x2ee16f11bba20fc346b786ddeb96f7d12112a06c1e5f2fd6e556280de7b8028b9233ae862b74ff30577fe91e9e27f0caf767e987b1729a012984824a6501bf0b	1655887956000000	1656492756000000	1719564756000000	1814172756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x52a5c279d7f164a8e5470d9b286fb3d5f173db3aa1c557b5c7d384d753ee36d9016e20f0d08f924837e81bc3975b8b589a4cfdc3d36c4cc14d702eda242c3e1a	1	0	\\x000000010000000000800003dada728fc54bdf8209bd312b9ac73d1f83c2c28862c623046bf8702029d14d20e4725681b2f429b4cbfc2b1e7d47d7a8803815b50e663a6f0a8bccc78b24f22227d8cf281fe7ba25714da3d934ff688388dcca0466b8d94230eb3ac42cd2497edf7726cd720a6fb6c4282115d9cb9ef3915005f8eb0b9ff340e0b1aa11599b15010001	\\xf3bb1348a36cece65f3434b06244964e5298bce3033836b0fda7c4ed311ee90ad7e5f8bbc8b43bd4e06b9903d2b5b7528a539efd65ad080729ac64bd8470850f	1667373456000000	1667978256000000	1731050256000000	1825658256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x53b1c94d5b8dc759b5cbd63eae23940c1b7bb3f0cdb7066fa47bc8712db08d31c8eec6c834533e0ed51de30f0840959f6ffb0a0b13792abe1eca5130c767d48b	1	0	\\x000000010000000000800003bfca078fe24ec3aeb77790b0db4a9fe11ab0e128d7ac89b0335acf22692923cdd4cf67b05f0c3c9d64a3dc55d1cc072c0c68888516f5f49c0f6a26f53386fb22dc2e03a85658d1fa552073477f8ed60c1901453b7c5e9c6cf8deac056b360889e3695f765a6ac964048803fd5fd75621f2903ad66ce4397590042b3a19154465010001	\\x30da204636a982c0b9759653612a080eea62da9093c5bcf752aa4e1cc6fd542e7ed95c539e5e7b5e8319d6548395fc90f21da96da311713c5ca27323a3f75203	1663746456000000	1664351256000000	1727423256000000	1822031256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5379ba5c6e3dd97912459762265e429d8a2df9860332fcb0d004d5437e5b96df6eaf60daaac14b2b718a8b65c9d9f11d636db32df063938954981a939dc7bb9f	1	0	\\x0000000100000000008000039df1a575a8b7749e63bed828cfb8079ad69976778c8bb51f9d56e5ebd6c0746867e1b07776c7813a428b41af14a6fcdb8d9f966ca6b5dc242a412d9dee994d562d84c53cf02ef417bd67fa7c1c739acf1746f8ab2f57cc9a6147a5ec3bc620b6d0d1193abfee634c88569e49be4f8167b2c64f5e6a88763a72b27a93a5ee8ffd010001	\\x33688ef922fa3781deed17e2fc4a6fabeb5231826a41dc3e9388a071aeb1dcef1938f5c648e44a6d12ff9eb6c66c464496ed5d38a7aa8bce976e18b2ca7c0f03	1643797956000000	1644402756000000	1707474756000000	1802082756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x54c5be4b265e431cb95612c0df45569437a2bff3d5ff093efb16cd44f9ce9d4ebe9e71140017841ffff4b82ef4617905285c5c19f0d42d6a9b1bfe435f3d7eaa	1	0	\\x000000010000000000800003c892b5fe3605f77b00890f4bd0113cd2713fa17de305fc7a56770d2202a4edf2b50c47c4260dc0f1244ff2cf90897c08b1e116414305b35273c5261e2e0337d19afe51163c33ced6510fb86a79065c7a3926ae4f7acce018ab4034022e35158941c7bd8a549c5be9ac91f04cd29ed74aa5cbb296f0489370eedc7e76e2c745bd010001	\\x11b847d3150444825a5e6b750ba40df739f04226518acd54ce4e93a49355632fd2215c32161f5bfbcdf8946f43e80288ef482d9bd77a77e84a95fe7fddefeb05	1661328456000000	1661933256000000	1725005256000000	1819613256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x574d7940c293eaad1caadee73f56a0adba27fb4220a69c87be560fd89b912a8b4f6661dbfc4f642fbaac16bdda5b4cde3ece7d0a5bcea2ddc87702a72d310487	1	0	\\x000000010000000000800003c9444c42db06087dcc5a862e503552e91999384b5a7ebdbdcbbc52d07ccb46210cbf9e62719dea2d66c0a7e4b20497133f55ef18507ce037115f4928d84435a57b75f72e5855d3a4b5e62aecbc26de50b751be7c85a4ab6fb833ba5bd7a935f83d13e0a61fe270663ae1d1edbe9050bdb2de1605634da069b6bad9d46ad08fc7010001	\\xda28319c224d30452cc91d5eb63eea3dc4e7a11d6cd24cf56b14286000a01b5a3702fa31bc3cb5bca0448c2715ad93eea736316540f2034ded9564ba0b226d0b	1669791456000000	1670396256000000	1733468256000000	1828076256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
147	\\x5dd545762dbdd75f333ad944c875b4db1f43929a8a66f9830ecce03b839e07056b31b19b5855f4f323371069fb58ad3dfa1452d429b58ef310ce5308eb929d2c	1	0	\\x000000010000000000800003b8157ea5c6c747c9768127227f0981fca14b4276c41d07d37617f8526665a447989d610f791a11bb61f999bb17d4ab81c9a2735885bb8a9717565e79123bf6778587af68d09bb1a2e9bbf0cba936f23681c186097096309f2ae4a88791e60ceb1c193fd999f5b77549b5d2101ff213d67c4afd6f0e5b7aef748a84c2cc9efd15010001	\\x6209f923cb0379fbea7e02a5b25ef446e83675088e7e4015c9499186078daa43395c48ac885f1f0a47d7d69cf2210992e0373b5394fa22c70a759eca917e020d	1650447456000000	1651052256000000	1714124256000000	1808732256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x5ea9b213bc8a09f0b4e64f41d68483c73fa92fc527c5fd6a62a2bc1098774323e624da8aaeda3160fcf6256fb3b1506ef5052428b42f69aae78dfc427e1dfd2b	1	0	\\x000000010000000000800003bc7383b36d2722376b982db44e20cb8063ea5aa65e2317e82593652c0f7303d487bf11c611fc114416c002ff69d8627e123f7b96bb04b1ee305c6304adade9928be5d222a07bb8ff6609975e26dfd46303e92fa3269169829b6745f18020ea9b67d9ff361758cba77989be16f20a6b71af6a0dd2276264982dea2c57ed5420e7010001	\\x0414b529013336c20ccd94aa753f6e19237241215124dda3c9c11c0d9c103edd307c1a7a61efb9ef5ebff7b5d3c0f9dd9eeafc666674bfb0a1907405cc4cbd01	1641379956000000	1641984756000000	1705056756000000	1799664756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x5e41f2926cc32357ecbb44f5203ec925c5bdb217e81fe2e8c633235f3942741b2f0295ec37d80f9d1959061a3fd276bbcbbdf5a0e666c37f22de40e8a7c73c2a	1	0	\\x000000010000000000800003b0472fa89871f7042a4b75551349b6239b41a1a68ff5cafe2f3a641c494870cc7761db66ba25ba9879c82404e04517583fec3ffb1b50974ecb72c060d53322c79106dea564aaf837b054fc49613c21a7e33abcb3bf627626e1546e1a3a1de675d2437bd88beb7b2dfd2a52daf8f3fccf07a5c08ebfa51ea57764f3e2e48a5e91010001	\\xb6748a9395e0fe9ef4678f03aa4a382e1edc2247ba6579c90c74485b8652bfd066e5ed4e044f6bbfc3a6f91acdd632a6fed1ed477443dd2aae12d25ddaa8c506	1640775456000000	1641380256000000	1704452256000000	1799060256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x5ec935458fb19b4c6fb0be186359511d839f2e3fddaff1d5debc481a90b742c9a1284e2ee409a3933440ec72e4d3ca1e341cefde8d163ca33ce4bd36b684d60a	1	0	\\x000000010000000000800003d9dce094fb04f248310c108c305393fd7c8863fa5f875d4c6daf2ad38f27c88a267ec927c2dd78a3ea97be141f412f47934d2503ac8d6f84ee92ae049f066e2973c19a99d33242b662934e8cf624639ef3b7a23a50ee7819167e969a2678ea959623abba7a0f444d834b95e00cff50bec3cfd9107e140ce6e1b93b93fdc09215010001	\\x98cbae3a64934646889075d684b91afe990b95eb213d8539e95c47a0e98da3be773248a3cfa34c4b4246b0e7fd3fe2dbc1a6610066d2b59ea55b8257cd1a210d	1649842956000000	1650447756000000	1713519756000000	1808127756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x60adc1ba49ca22d2f3ced3890ca0f933a9776703e8f20cf865b5617276c5db034dbc827d4c7b4c0b2a6a00d277cb1f6c3b7b745d6525b6a360d65ab99fffc817	1	0	\\x000000010000000000800003f5eaabda4d65b238cf2efaf07a7e3867aeb45b0cec8cfd56758aa120b6003a7b870a65a8a31179c6c3e01a14f2ca0385bce6163b2273bebed9c8dda7140713a45b66c3090419972854eec09d52b40b0461247e1bf237584895aae5b3c87aed0817857e41329cefc19a1730eb4646cbb670670a341bf69612913a90e31a6be0e9010001	\\xc2a46a30c36d7e5a3b27a4a0482977058cfcac6e2451905765187b53c22c6e43347ba8283f6a24297e61cc88b1362c33326f6ec6d4033c86bd3d35f092cdcd07	1646820456000000	1647425256000000	1710497256000000	1805105256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x61417d22c7374a4b3d603c1c7aa9c9cbfc3b40e73f26711105a0d1ceeac4c238def330171eab15b7b4e88eed4f085a8aaf928e809d9cafedcdd0f95115ae8631	1	0	\\x000000010000000000800003b67e985a00396171172899dbe783c55be3975418ffe7c0e0d1676197a37eff372cc7db0e8e3e69aead72db83bfc05de04e14ea8c992869492e5ef8570cc01fa20e187844cf628aa0ad9f87ccd88bba48b92ff85c1c0ebc6bf452120a78e381975dece2967756895cef5d5b12708b7b5fa577b15d079ee9ed296fcb6424b5b063010001	\\xa8931e509cb295c2956840d3a2c7cd171a9785a490df4ecc4c41662afa8ab6f6b871486495f4bfb0bff076e3062b19e05cc34dab8f2464e35fb45c053519c604	1664350956000000	1664955756000000	1728027756000000	1822635756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
153	\\x61cdc9d7b70b165c323669d716d099d0cc91633b4468664942c2a8e31bf00a1daf4cb8c5cae0e51666ebc2f30c92f53f9c6d8e9649c392b9613922d8b8d2b2b6	1	0	\\x000000010000000000800003bf25b321b03be1a0adfbd62ee2d908855d997bf7ef91208b15c4a4d7fed9d24370e1f4692fac6d53221c93a3e5bfd04d8f6e5a13dcc7323ea6ed89c73d53e91e3a77a09a41c2805ab54e4575bc8ea6bc47730da04432359bca07af98d118e4e9b26b34910d6c2ee4389a26e58d001eae2b63515dfc904efe64102efd5eb08bb3010001	\\x8b145c820e5a72d46042f0f82fa1581823cdf8c53f94a09763a539fd0ff33385906eff3ac59b13fd5665c4885cf189dc3f4f4e789c048c20da796993fe0ce104	1650447456000000	1651052256000000	1714124256000000	1808732256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x633d600a46a227b5d3dc02c09754cc684f0f98d485afd69cf40e9eef4fff27e4d818940d86355f3e90e038867de8637507fee84c3e181d2e3964d19ecd7b7362	1	0	\\x000000010000000000800003b79a08a73695d139bf1cd28ecb01907531e741c4f48d275848bdf768a108e90cc0766600d7ffbf685aaf01f84f827197c4bbff19f042c79dbe78701e75fe46288d83e7c9c39933c077f7b4b1fb0bd0b6f0a502b7186dd45738291b43be54dbc322024031105c87d23bb040482907737edd555ea4aa21133772d25b96d691e3ff010001	\\xa0059c78f6702ce4992f389487c78e32c8c5a43827dea138448eded6eedf263e02e1e6b7184b237c0620eca69a7e2ab1b0f1db38629c4b392adf1dbcf10cbb09	1653469956000000	1654074756000000	1717146756000000	1811754756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x67055592745883d9ce8b6b9de37916286e5c1c49015b9ff6d0ee0393297ef18339211744da0a795ce04f13ed2ecd53a958f8d6aba3e9bce5b0c11d6ba16b2292	1	0	\\x000000010000000000800003dec2b38f508ba30d00a9c1f346afcc5c8c7e238d6f312a312a99968f03907c9c655ef1b698d5517e186b49644e50ed083dd5cbb059837c44b58ec3da99fa629ee8454df26a4780550dee6a1ab2bd0a780c25bf0fa8f3e7d15c18b818005415f27edd1d70c9316ec5cfb5dbf391500d74d13ff8196539c76ad8341e40f1e2b64d010001	\\x17a7bf4ad9e7af9ea79f5b55473cf4c62547f6451fb2a511d561886a406f6ebd4823f026695c5b6a44cd63ba2a005c7f3be9581ac2cc5ffc5c4d300ea124dd03	1654678956000000	1655283756000000	1718355756000000	1812963756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x67dd8f00a4adfb9ccbf57a14dd2b49b48d5a238f6118c1ef0f82cf6f0b814ab2d1c0f4ad06e98c2cbd04190adde6930f5b884a71446f91ef79c3308b7f3ac21b	1	0	\\x000000010000000000800003b690732ab1fcaebb51a1cb924446068e7554a8e830076c53e177e5a19b2f9eedd01d7e6e17aed193a19b9676f7d997aa8f5c885a79de510c0a70b968e63268563f9738f989894edbfa5f8e2ba006309575bde2fb45b91f38c7b421e2dde5425940804ca5b7c7bd31c527cb829eb34a17f90b4e65829d64dce67adbf89537142b010001	\\xa1919aaf20dbb77ed84957a88fec42cacc50ad2b5b271a711b3911727793650ff6c6e8fc9a236c2dfc1439f19e17f22d279696e270cf5a5fd9491722a28fc40d	1645006956000000	1645611756000000	1708683756000000	1803291756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x679587aabe6de3022d4b3780c71a1822a72bb61486d241f78827b5ceb7b27e612d9f3d7275c50f5c9b09ba500efce1d6280b56dfa035564554562db7149a6d5a	1	0	\\x000000010000000000800003c836f8b717e297924f35a3157599478b15f5db6d535e67550fba11cef05e29d432210b710d72802b705f91ee80747a029db334a2baacb4024e9477106bd705d9f0b0fbef55b9979aee276c8bd9669446db6d5f858dd96ee9c1e5bc2e35cf3f280cef619411b018d8a962f7fd2347ad2558f4f76f789edff4d142b56d72d5c0df010001	\\xf576965763668b1723a149ebad1cfdafaa95a145284ce6f34cf4306f29f73e804d184370f107fb2d29acc561f64a615bf390d89bbdea01ac7ee876cf39eaab0e	1648029456000000	1648634256000000	1711706256000000	1806314256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x69c53bbc4a39deb780a38dd8721984d69562860bf74bf84a33755cbb61be0409a6fab7448a82f74c2cd649273aec158ec2a80880b00f15f3ec01fde0c2c8e630	1	0	\\x000000010000000000800003d2afd733a742f779c6c703cd58dc52bad46c83926b8d249b56ea695d2bb8754943d43379325e94ec1da057f13432e00165d6fbdf50f25ccf4ff5502b4357096df9f01de08159196b9cd1b94c70fdbf280c8059bb97959b026bbc4a41a331c2a0872ab495ea246244ac01529b75550717e544eddf3edc1f8e1978c2b07657021b010001	\\x82a05654de8eb860c63433c3b16e063b71de9c8a0cd622abb42dc0c13e24a4d956c1490ac1567aabc129f6efebdf7b5b058f418dc0e331ed6774d51cedabf403	1660119456000000	1660724256000000	1723796256000000	1818404256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x695de20836ef9025cc42734778a2abadeb12aa7eb030d84ccea44245eebb57e67d49d84fe1e7f5c6e716df8c77d14e5aa830fe5927a13ad7dc311e49fb348deb	1	0	\\x000000010000000000800003cdf7ff19c31a2f9e4317ad7bbf3acc02178c24dbad2dc1cb1dca8524c4a4e54ae624e87514d9f3b229b1e2c4d9f63d175b256b6c14d3198c3585fdedc7f9ca0e61445f6366d9e354564a4f4a0681f0687ed8976bd1a33c9a6f6cbb7bafef15c846258141c810f1d2d8c7cd72602b0f9442f4e6ce07a05dc01d17f9748614234f010001	\\x0e232d0249c5672ec8e7bef922e86d9765dcc7ee693bc36389f3707ff7ca1f9c81d92585062ed8b90b7f5100a93b6deee59b1b03e5d66f6ed2b66ef86d90c80a	1657096956000000	1657701756000000	1720773756000000	1815381756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x6aa968b024c0dc0876ac4ca7d8aec4f148306c0bcf12c8d783a1805db834ee88b17d13e1e05a2f4ca80a5b74ccc725f885306c0241151a23b56d40bc9ca5685d	1	0	\\x000000010000000000800003bd3018c40aadac39159808f0d9b1071830515d88db3e388e325672847f5811aa180ca4c74f0939195c32fac19fc65bf76969e525e749d77e77c5bc4c9047b3821ecb8384b38369fe8d6985f6edb663c5c2c2c3a19ea02f5d072b3927635bc375fd87208e1097e8f226fe275ea81c6836b0cad71eb06497ee79aca597df4575df010001	\\x4e2354ea1d652d5372672bc4856e9ee6a5f7daf0e99d06d108ffc4e4256fbb0472a7c86fcb912eb26c1f8f3592da0c7f731e73bf1016b35562ffc148f24e2f02	1663746456000000	1664351256000000	1727423256000000	1822031256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x6c292cef7b9e2d21b714f65c26a91ecb5f6a647dd6b9855d6453344ae8811562ac742b3f31322a17969ee0e1b05f8ded5def4d93f695461969351f1d1526eb56	1	0	\\x000000010000000000800003ccd23492092f532dad96a62a70abfc09c1e68f076ef95c3ecbed609946f5aa99aca96a08b5c23a73930ce8e82c3e8e7e89fbb141ae446177ff050714904265b356ec23fa2bad9c9a4ba59349ed69269e03ae65d522ef04ba50bf52b8b2507fb07cadd350e0a26603e01f49d411f529c3e1af3466873e1cb5bfb1c84542bac837010001	\\x9bfbf507b8cd2d4e277630fdaa9bcec5ea3f5888649a060d380a346049c385ee932cf4bab6dbebc260f1c7823531b3f85917b261a47c1cd148e9141f67cfe504	1663746456000000	1664351256000000	1727423256000000	1822031256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x6c09289716e8d21345aee79ee80f7fd30f70d43b4d653fd70fc14995cb4cf6acf0904a8911d98c287d556e2eb7552fdc36bff3fc709068a672bc56e8c7efbafe	1	0	\\x000000010000000000800003cafe0120d79ce332d51734ada97abc9e78cc5e56d6c4a77c542bd2ff8d58d448eb61fe525ecdb26421a456fda87141b1b4edd037d3ef5223cb06337721deb119d837e8d259724b6ad334a7c63c979623303a0b276d115b6f281bd8f064750458225b7e5b03d573ea06545f2f213aefbeab0ba46c31b2bbb50f842fc0d6b89e69010001	\\xd5d2a7c8e14f3e9209f50b388890e4581cd0b6d9ad86660054adeb2585ac66cd7757012ee33c87156ba4b0315f898d6119a36994dd93b2d9ecbc290dbcf9e402	1648633956000000	1649238756000000	1712310756000000	1806918756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x71891bce07e86d357d0775030334a618d8b36d55dae7ac60db76fbe69531e67dec4248879263c828391a41662dabd869893cab8d0484029cfd4a7b16b2bb8f80	1	0	\\x0000000100000000008000039cd08d90ca9f3d2c9ed0b29541166248248d87ff9a8ddeb76a41bf39ee20271e1d921f4ee506b78773f27f4021ec7005f544f7e25a451b2a4fd6a78e284685c9184ff9d79f1e2c15ba348d4b968c82fe7cd0641418a63e3546a3ea0e3bdf57afe8660b4a12bd015a1af8190990c2b21c48f65a1f5b461f69115b7e5629b050a7010001	\\xf9ec3128ee82a4260fb4b7e39aa016de1e8093380e96a7522729376ef5af79c4133c7c92dc368937d6181657ffc025963e5a89534367e2e72155232a17fbff03	1650447456000000	1651052256000000	1714124256000000	1808732256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x76814992a46bea9d548d974891c5b8cff7710a5885b995bdce3b69f6dc9c7e705cc9431fe62a62750ad2c5a749db5e95cff6693f71ef8f627e7de2cca5d5bae6	1	0	\\x000000010000000000800003e1e6ee6656fa9f3139ef300730713f29c58905159fbb5b304142681d3d1fecd19dfb98636a74db4f70649f72aabff48f605caad95bb27eaa3cfcd365da93c803e65eab9da784a964aadd33499a444c00a822d2add7819a919a624aea70956111194f2b17c3ef3d2f0652e31f0bf002254b3fe755126e3ce33e45dd1f2c0d0f49010001	\\x4a0737c4f9eb5f906aaa4b7b52033e42f6c14ae7bad0aa820c3ebd7416aad7024819c3d4141b67e5cce6af1ce4a52385a246e337522a131fe8dcacad9b72280f	1662537456000000	1663142256000000	1726214256000000	1820822256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x79f98ded0f11454091d2cbe097ea5e9e8008c24ddc866749146747b77996a6f20df5c9d5032f1c714b28c5e9f605c5f99ab5c1fee3a4162bbc2823f80c7a25fa	1	0	\\x000000010000000000800003f4a79d7c23c570173fd0ff74e02fae0e409aebaad032af84f4748f128eaa75f68d11af7a916511fdb01e3d527f86b32dd9aa23a21ae9ca0751e6e18c8b9036dedc407314838f446d06961a9c45783920d02bc63ced0fdb75a9537bcca91f5bc10628bd41fedf50c3c8a20db2aefcc060438016319477c841e4315e2c45273b3d010001	\\x9e79c33dd10f7856a2d736fe8ea55109c414f3a541fbb1fcad3de759ee4cd73f1d8b2da433ae34709eceee654572a61fb3279ca0914aa6985b5a847ff5466906	1651051956000000	1651656756000000	1714728756000000	1809336756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\x7c11564623cb26f7aee7eaaa44f45db16345635c495612e97c4cf465c3e2fc3e2a59111c302e63cc12c61d6adab7587195b84a07217adb13d5a07d2e158fd42e	1	0	\\x000000010000000000800003d046bea52c67589f70bad22563438056f65c554eaa4962152c22d3d5984cbc184af363d8cd3d9507f14205eb249b3cbca1087d5342437dfcfefdbffdb8e87ab934b627d6d2a23adeb957bcd2a8264bf8b996cb45e6a8821134a344e9eff0561a8fe5bc8cebc6432c11e4dbb1828f0b31e0914187060a26624b05112fc29287cd010001	\\xc1c60c16c19ffc8b4504021ab0b3b1c7f0ac8984bd88fd3e34d8e72508b23a36666151f7a4f308f4bcf7e02a57b76fb9031f53d60a59d68793411661f2725f00	1643797956000000	1644402756000000	1707474756000000	1802082756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7f8dcf8d2153206c2307bfbc527eb9d0301e8c69f087ffa98c723ad95408acf0a5ded14423596caaff498c5d6f08e69549245f69311325a9382c6c75476a0ea4	1	0	\\x000000010000000000800003b5bd61109ce5f0515d45066c69f78ed68deea11c00a7f4808d2ab51dd3d81bd31de8ce774e430f6d4225de621d94e18a220585a6e3b97b35ea42ce8f5b5a798fef8c3168f1673d72740441ac4798d5e78ec1ab2e9f6724c7712931b1348274756e51e67c0073f2c59fcb3b496b3223f531709a8be094819eb448f52f6ed27f27010001	\\xaffe96332f34c43f4c092cd6a9bb2d00b2a9d9cb62fac0e02d8d02d096cca9d0e50955fa9d1d2ee79a6194a5376ea4637d26c0c039aa2b9b6fe9d817b0f98c07	1652865456000000	1653470256000000	1716542256000000	1811150256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x84b9a12d22a9a958b6c8a3fc13c80d240f658071442bdc7538342ef995a4ed6176a549f0e87354b15c211317be3c155717ff81d7ddb991a687416aed6925949f	1	0	\\x000000010000000000800003b6c59b1f24f3bede1910d39cc92ed3f6c21ef1c8e2c37e362bdbbdbe7ab0ed11a7cd5b43fa548f037b9541d51c71f6280bfa368057598210fd0c8958879d7a3ff770d42201f347dc23c03200f1c6807d11181c47de3494f2b944f12411986d0685094690d2f0114437176b03e403303ac00c7a6a40ce8336b9f65bca76173997010001	\\x114e1621f25fc599f831b95038599179ba8414305912473a859c40c0ac07d7eb13726788ad9ca6c866f42a1dee100b77d2e688e6c4924f1a625941f1a654530e	1658910456000000	1659515256000000	1722587256000000	1817195256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x899184f6a93f0486ad4bf14a35fddfbf98100c5abd5305f09ed58d4939269a086ff7b323fa858bd115fdd00f503812e64033cb174f328106d8c726a9604e2786	1	0	\\x000000010000000000800003abe9cba80eb470bb031fa6eb46803b125dfe9b3aab1171f4b10b60ba437f891e14270c78793c8d3fe16edfd9bd154f7196e4fdbd8168617d02b1a0e1b4af0fc78956247ef71c4094ef89454661e8648b25f6f30b240a081154861fa4f19e0134be3cc729490638a47fea494c7439b50243804da44c0aa4b85d9443933636d1f9010001	\\x71c165df88b3d0ef5efb258c2af8ede7de7c6a27ba5886e031e414706914c57c31c934aacc7ba1cbf1e506c754c248aba058bf7a60b3aa24f5edcdb21725330e	1653469956000000	1654074756000000	1717146756000000	1811754756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x8f8da8896b2ab1d9b4fbbc10a2382860b7c810ac17e727614a4466e4f04595e5f3bd7763a91d9275e66c2f74189c4889bb8cc9f122247aeade390fc18e7b460a	1	0	\\x000000010000000000800003b5f6e874d4be271d84dd9c4c34e26b37bc4c9bcfc3b66fd555bb907387c811011d7fc570e7492eb0ccbaed59e420a4a8e7b0e97dfd825366b3a1998218d0a5f646c2bcf2d7b3311f7c358b642c01ad7f993478c70c6ba16ac52defe582f435a0c310b06bbcd4aa2e1fb8cacc9ef2bf7b733f40188a8b47892ed5a080c7a887e9010001	\\xee13b0f3add4c7c82b87c1967bc157813a1375daa9684e68d43a82917e7867d306133678f49595b5b1f3c50695c1b77697b5d8e53da3b6d5cdc60e9c1a458b0a	1664350956000000	1664955756000000	1728027756000000	1822635756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x91a97f6beff13d16b0a9c1a7ed57a2d9509756d9eaf60e8f38803ab1e2d0c5f1763f8d90eb7c9bf2f4ecf5bc1a6d693342d4594190a2881d9a236da18e7b9a2e	1	0	\\x000000010000000000800003d76e18e96809d0f1f3a2748bc66938fb28e03ce8f627a96f3a86ff97110cc19a2102f94c9622d77f24a100ca8e8737a6f5887ae98f1c71dcb307f52cda9d1fe686e0f062be6f5eb62ad8766e14f8af11d23bf5544db54b6e14764142ea111d8fc6fe5cf77ae513c47a08013dd93984539f5de3bd17cbaed55702a8d41df90f39010001	\\x22eedd9eb3a3b03d4817228e7125193630e12ea1d3bf99bf261a6b45b43e29cd147070b6d7788c4aee14cfe6257d298e10ce7b01dd3c5cec7453f6d1bd4ff901	1658910456000000	1659515256000000	1722587256000000	1817195256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
172	\\x921125983d006fe9fd8f3d0d5de148d677cb5f57d092f31274284df94c33a5a2b0ac975d2da8bb9bd8efec07e40eb8a1eb6d57aef1766092802dab55f2e3caeb	1	0	\\x000000010000000000800003b8f384ad6d7c7268e1667b04ddf0eb6e036a119a8402ca95496502a3a1e12e2d73a75edb38f9eca3ec30cbf67916643b0a4da198e533ba026faf01232c9c44bc904be5011b30d6681672aba385200ed2e599705d72626d2a66ece6ee0abd9f064ada8932ea73ba638da9ea3bc7ea260aa450947818775f82e1ce2f77a25925e5010001	\\x82b45a966dc5952e4b378f5b7c27aed134bcfe96696c756f4bf1371750d5af65356fc9544ce518292ff4e76522c32a0e7e73b347ba7f9911d9fb79f11745fa01	1640170956000000	1640775756000000	1703847756000000	1798455756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x98a1425f347a29452c32757c8b6bb8eb9810d34cedecfbb34fa62f44d77afb78f760dda629d3d6667693ff26b6d732491291f190a375b7cfe659ffa646103213	1	0	\\x00000001000000000080000397bec3473e665f38e0a9d91fffff45b5be97fffd1d279b1d7d2a3dfc73167a51edd85c3fbf5e40331b1de7e988deac8415019c7a77c0cc3b09b1a8e0e6d9682cf3afbe76edfcf51a8bbd0848ab172aeb36329b4a193485bc3b8279c34491bccfa5db5d89f4576dd120f2845c347bbece18d7cdda7807b15d8de0a696a5d57905010001	\\x0af60e3a1dc040de9f40bf2c5d73c3899917205bcc703f6925d40bfe4cd1aa1370695f04982327a5ee1386b1895ec8c4c113ad0ce4a8b635cbaf44a867e27505	1645611456000000	1646216256000000	1709288256000000	1803896256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x988ddf3e7203066682aa6b813d9582ed3fdf08a40878faf31ddd082d8152a179a74010e66b03d21622c55d84e4031c3f26d6502bbf290dffdf7c9b66a5554c75	1	0	\\x000000010000000000800003efe945dae360950132db382d528cd89c0a80f16c84becd65d040f2a8ea7d71f4d7990c6f8962eb2583e6ee367c587d639ca3e19fa8147ae8553f3c841eaa8ece1a9acd51b2a4d9acfee65c1238f0b2cbbdbd1b424a104ef89f3d46952dee043c1cc9a050e777cf2b65197b2d3e9773dc23563ad59c6739590fadfa10c1789de5010001	\\xed3636720d4269ee39a99b7f738a6a14b5f3dabc106b527541f2ed2e3c4c67636ed237b6863eb0cfc6f070b8be4fa790526cd65d15f1b18f9ae2d9eeb018e10f	1656492456000000	1657097256000000	1720169256000000	1814777256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\x991d4cea175c897bc93b944dbeca75ed76a26f9e577d5761151562ec6187c59aa480904ede300a85e3e3125458a9eb9c5df7f217b75d7f5c0f7c9bf14ec8f375	1	0	\\x000000010000000000800003d5f97e0e07be5f8cd9ff8a6e04e64411f4ef4e7caeb961323468ae9e798ace17e40f19c3e87c364806b5ead52c41294a046fae13e7d7c412270223be2bff741ada8e5756cd234476680db0f18d6661c495de05feeac4de05a17eafb3aab9267345bf04bf889fd19e5b94a92b2dfbb9b79c0b69b5d71e669ee4a9312945ecd04f010001	\\x4a9fb962b258af0225f421993ce4528eb97be158d5df0558fce5dc382a73d65305d201734b955a3ad544597c3731028f50d8fb46b076c6126b79e8f0dad54c00	1651051956000000	1651656756000000	1714728756000000	1809336756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x99f53c37e078e18112e3103cb7571c02efa4fdd68dd05366867f7564c3f00c5d2ab1fa89865a41768fa5a3db6e0356eec925b2c6507d12200dee7f1a817c7940	1	0	\\x000000010000000000800003b42f24b3d1d980ff237b398e6eddeacefc17b509e8d2f3b957f6048d9cd03ede0901b5c5a2ab3c81113d3ea28cd08ee3568887414346be3e98bb4fe5be77b94e1efceaf084357cc0a5421e67ab1248e43daa29d4a55163038714dc99401691ea871748871ff141c8ce318f68524ee068b893d9a822e48613231c76fb69b82201010001	\\x48269223bdc45fca2caa0b3582e261e159f85c290d9665e462d155a65026cc41ac503b5a5b4d0c0e00b75c4f073833ff05aa5eb331971dbdebfc9b37f4fe9709	1669791456000000	1670396256000000	1733468256000000	1828076256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x9cb57dec3a97c3ded850017c6cee4bbb126208ebb4f6b79a1dfe6d837d6230136b538a9a42a227e0365171540bff0a661d8b2e620503e78ff19e9ffb5feee270	1	0	\\x000000010000000000800003c9f951e3c5a95d3a85707c55cc8ef1fcc02c0d6966e75b9ae62112dc6e04b620ddefa7fd28df8aa2e8b35230ca854e1e6b1c69751d448a2168ab33e178616281b862d1ddbf944a66b53b807e05e79a508592e61d21dd961d7d1c92badf1db832db5962cd773f23fd4b57c70f68bab7cea99a22ec05c9880e8b10fefccd2aba3b010001	\\x89c11d3ee5a03f5a0affc32a9f9eaaecd5b38c37eb88d4067a1ef20dc55640187a73a2c36ce5fa774304ee19931fae965bf398b6681b017941177278840d7003	1646215956000000	1646820756000000	1709892756000000	1804500756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x9fc1052ffc6c745cd2b13841bbcac94da9d51ca9067c7e021fb2f4afac2c02eb338e18bf5f94d8345bc4dbd00f146e67f894fe748a2f357c935d7b0d7e8e1eb5	1	0	\\x000000010000000000800003e232554c9076d1406a6b5b8cafdd4c45a0a045c51277740650d004ab4d7d3acc1f8936da580ff6b67559db629a5d6d2f7735b2f3cdc2f1f7acb81ed63eb5286d8df843221c3aec505b818bef988fbc6a51f44c293ff489ec1111fca8a5b6cb8bc6b114709f135ff135d55caa3d58d53c2437f02c0ca60a3dde779fd41cb501b7010001	\\xcec26cc1078887dca662d5949231acff9ce870f6559826b0ae76d503e8a915f8272e77a466cdb133d37d74b5c705763e879e7badbfcc7d8e18489cac4c92330a	1666768956000000	1667373756000000	1730445756000000	1825053756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
179	\\xa0cd69bc61110b02dda3a0ea3c3d6d732c9f71cdd2a03bd214d459659f9f561b3553e0da3e5eace18f58526c3817d65f97f723ea870edd49547a5b2bd1a5e08c	1	0	\\x000000010000000000800003a8d0b6684f7b2b421036da7577a90ef606fde32d7f58bde23b9f8ec489c7b69119b010d9bcdb6b22506cff013037a696910997628bb25239d2da4ab140f549e518d4e1e796794c726395d15461e4e61f51f749902364bff5b8183e71c3a3b76e4083b483cd244382b4e9be10cacd59ccef5999f82a814881215d98697dd89811010001	\\xfc6bfed5877748b14ea014090cb5f0baa9072dd6de4a7062787d96369687f0f5db962526f202f19de308c1a1ad627886ccbbb89458a5d9354a34943a41df8802	1655283456000000	1655888256000000	1718960256000000	1813568256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\xa56db68d2ff5cef97b98d2a810cbecb74055cd101a38efd1526b12988663c344912d35fa5d06d1a13d55e980b52556526969460da79ef8e3818f63e80a1188df	1	0	\\x000000010000000000800003b4b4d0ecb9bdcb33212006d3940772d375ee3d97ce6e9d60a84a0089d8fb99eaa3dd525513b8855666644db45a464091c15f09024c9b88b54747c2a644c676deee86f539eedbb5dfc0b3faed39cc03c904bf3b44e6ee466a1f0d14be92a5b9218e912d5f92be4aae7d95dd7dccfbea2c7df736d37979a0221d41018f7f03f13d010001	\\x9ecb64cb8d5253af9ccfbb9497d2de83d2398bba58b6adb534112ec4688ebc0ae0f8a5d0e6ff7a8970919ac207db180f8bf104a6198e4025987cc2af208daf02	1654678956000000	1655283756000000	1718355756000000	1812963756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xa579db9e6a4977a660b3da349a0f55e5348ab5f521f314d170e74d91752a935b90409007c2d3c33b6fddbb596e00105198b47cd37c598687e671ff61af66540d	1	0	\\x000000010000000000800003b73f409717018de3e512a2767efb799a1412ebc1a865709084b09856fc6275c2fa0a4443ef56abfc9f43b88aa5e3aaa08fecaf97685fca54013e611165be16406fbb062075ba6004acdf3d954b21b1c41461aaaa3574bbfb12c7a75f650fc2c4463b2eaf218ea4c26d7ed5b8df10602adceabeefb92e6d8d15f8be21c0589b25010001	\\xdf2f20b5c062273abd5089515dadc569026fab06f40fefd098755e555ae62f5d252363e2a1fdb3feaf5b8404741cc4676b15a74c127469eed11363c2f6636108	1652260956000000	1652865756000000	1715937756000000	1810545756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xa715036767f1d1c000ad08916087d1a42316b46d6195de45b57be7589a2b1dee0807205ad3c7d91c0f0619a274047bf8014b4774d12a8397eb6353879bccfc6d	1	0	\\x00000001000000000080000398c8004c70df024df8a1bc2f21ef672f384c82db22f25687e4308d8e7dfa1d9d20038616ac43d1a7e2c95907fb778ca05875500ae0fedf07b65d83bbd9bd811ce8caecd4a22e2b7952bc51ee3df8a2d9736eea310c856f7bc4b33e301a8e01531bb9274821e0d8a117662219cd253c461d25f848b56410c57d968e65b3a07faf010001	\\x387008562b2a54fc6eeffc268758acb42cb3316ed78206fb879225ec4343717ab8be8f0e3d147efd0d553db69b9239e43aae8964077bd8230c9ff8a86a7cb00d	1657701456000000	1658306256000000	1721378256000000	1815986256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\xa8e162221219320fab6f97e2dfc505cb46ca5f59c8e6eed9000338efdfaaeef44ac8e0ce8591a7e6df6cf729e1507aa4a4c19e48c895f09bbdcaa42207484b4e	1	0	\\x000000010000000000800003d8337951b27e427276afe30cc9c97ee433c98348d9353e7ab0bb890875769442ccb12a4518b95945f7d487aa6b4223c02cdee87e9c0060ca5af984abeb759e05dff06d464d628f3e6f22838e6e4535b57681226ae15769f225f6ee0229ff21d340157b0bff478da3f972beabf428c02425b3c9cdabfd6efc8c004fdef80754bb010001	\\xaafcb0b5536c7b202b30678b56615f5475606da5731ef6e19675e8d5a7d041b634e35d244be0df272e5a5872feb71832206c73dc32082402d4af169470a5d80b	1657701456000000	1658306256000000	1721378256000000	1815986256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xa81978f7b581efc6c930fc494df1b299a92782cf10f93f1a42b0ad9d1b4496da3c3530676fc34c9887e246df0577385d8c1011dba9378c6dd289e944966fc3f5	1	0	\\x000000010000000000800003cff2c4ec114040a84a6729301cdaf657390347c63bc0f84eeff4dc5bdbc1dced8bfc6f1b54cc6d3acacba2942975780de9b482d5d03083d31da1154c9057ace22bf3e53d090bcf590fd2d59f1d6caef63a2f075ab892a496b84ad19f948d1e38bb2e3970004ed758f1827c3a50419621b7e8d09d3f234e9cd3b3023af715c171010001	\\xfc9a529fc6fa076268cc3fb262d57b7a29391fbfcc7d5980f6881df8cf91ac3387162fcbdfda544af6c3184f13b868d565832b8d1e2b6d76378dfc1bc8bdcb04	1649238456000000	1649843256000000	1712915256000000	1807523256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xaa153d8a0f5a58fb80d42e46d33624b0dd56de6d4f53a7b9c7e08753ce0f4920100bf0db012a79eb5a68917a0650990433623d9e79e7b1cef1b4d0e056435ad9	1	0	\\x000000010000000000800003c27825b5e78adbb7907e9cc082f21fef9432697a5b1cc5eebec6768fee73b9da4cca957f0555a90b64320ef24e1472ddcc49d788c3491765f2db8314be88006d3fc9cd5e22f717da81442f39b86df81e3b773277e6870902e4de9002988df8ff8c7cb1a5ff383e42c8da8d8b06cb80d73c15e512cbff84dd99a3b67454d2984b010001	\\xb7e6ceea9e6c52248531a4f36e11da369bf86f0690d1f486140e3dd751d6eab50b30b9ca1fbd1eb0a4d29611ab66b82ca46d66a3a424e8b7e3ad916cdb98fc03	1643193456000000	1643798256000000	1706870256000000	1801478256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
186	\\xaa09aff3e6d9a2143f25ec69a72c918c3dc595870799584261ec7fb70d7bfab93b4ec35b9dcdc71f832953af7de31f321fe02e6e69503017966eb45d250f5dde	1	0	\\x000000010000000000800003b7382bd8adf2efa154a80639d57dfe8d5be7d3f0e84df46ed14687974701edbb79c3b1a6bf7966ae5f39b41fd96dec03878ac07eca6631e8f3f06f0f74fd373cdf997d3c22f5350c655f58c0597f2172c18e9e57d93605415dfc1ceb6719ca3824f926773bc341f5a3f5bf63307810e2c1a2473eb57735ed2dbe39b9384c2391010001	\\x7dddc803c5ae067b65c81df00cb42fc7df632fe004b2cc71450b0eb988437abf55da29f960678bf8e213f3f64378b92069344f556ab6bd10213302761efc3903	1643797956000000	1644402756000000	1707474756000000	1802082756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
187	\\xabadb263cd6454389c249738137de78f6dabe9fffc1f569caa35ff0993de14c21ebd173af776301cc672acb62ddb8a5a0592b6adaa81323f0a92e5a1c0d3a185	1	0	\\x000000010000000000800003bbf265cbab4905ba8f163aecb51cdfbba28a4f958557e6ebc0bbeb5e0c178db434143b4aef9f17b6987f98646c6ede7dcba99afad4d79e46b6e437ec05cc85e68440ce6e6fe87b7d0612a925eb5fbb5c5c200e713c6a2214d6d4c80d9230904e1ec77edd83d7aa5fef1badbddff5bfa3280cea54fd91c26d68a10ba38bc5c721010001	\\x498b1857e5727a57986c21c30024c41416b1550ae95e2434d99f4ab269ed1255841832a35e201207562d77bf9b2dfd3139afac10e6174354177d99ab97d97f04	1641379956000000	1641984756000000	1705056756000000	1799664756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xace59741584f1f8af6e743ce66f8dcca061b12532b208df91c8533a7900272323afd8f114e038dc683ffd369945dd405dc55e67ef9852eb032aef7c874729165	1	0	\\x000000010000000000800003b1e8eede5d26a8e3a120234fcb42eeb39746f215841332b3d2452c8e76963d6f3ef36fcd48281297b4f9467fe836eefb32b7ccc7d11b01ef1932128d765689a4364362df2e87ec0184e88839c8235a9ae25e57fb713a4f1da6f3e1e3fc64c5dd4424c7be5693fe10982c347176b309d9c717f8e258df9735390630c2538be007010001	\\x14e21730cedbb805746eada518905d5c85dcb3fa32e0aed4de845891c9081b754924fca486661bc5426529cf0583613d44e3297c12e5e8d14cb84fa3a8dfab01	1663746456000000	1664351256000000	1727423256000000	1822031256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xac3da23ed50d6d0664556fcbb748e27dee8a65372f97d1764c860b0587be45293225615e8f3d8dfd2142fec86c8b008caf5dc5ee5a1e0046edbf57c189b75fb5	1	0	\\x000000010000000000800003c7e280d2e1cfd0085ba9bd6a7b21518bb68a83d84398305f91e8816107cc83802bd89ba4ca217f67656ca778593c97b4ce32a5d45c92bd2b880f882fe0e3d79f568bfc35d4fb9e2e0358047ba01692ea50477ee5f63f7cd4140a49f51af1d063eaa5454afe9da7914033fd86d6fb03e4cd0a0e71d5d0840181d2dad41c97941f010001	\\x60f621373ef0af65ea8c0a361a8d470cd2c172fc270be733f50141dbb1170805fc199525e104805f10aecd9a27ebcab19a6d9ec85b8a22ce2df6c587427a6e0b	1643193456000000	1643798256000000	1706870256000000	1801478256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xad559ae222a2fb5098a345a443520c14c0559017ff6b8b9c837cc06a212eb93032f64a97ed508d453c0b3212184ac6a46edd70a1e0a7e312abddc297b1d4c2eb	1	0	\\x000000010000000000800003abb5f2e6b74f6cf9dc7f3fefa208fb656ed10b362952623417199e2c110925caff200c354793f24f4f5a7164339108c7b328d9d8e17d16c853b791fddd817418a21fcf4621aca25f2d038b80b1ae1c068e2411ae63ba391008e2a586c559678bdace571af99225860fa6a7a6aa26da4ba88d125c38b4f6b81fc1f800fbd98df7010001	\\x2f014f391e6dd184ed64ad8bc6c016aa51b4461a9585a353f75cf1d2ecf48f1efb777e97e62913c99f4e42436ec963e479716d30b937bab34820c2aaffa61b09	1643797956000000	1644402756000000	1707474756000000	1802082756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xae11c9714ef846d7504f23666ec9b4a26173a2e61253686ff18d1852614b601d2399ee938a5c0705f6aa9ab20c9e63a95b1c78f298143a47154ae8303b2eba99	1	0	\\x000000010000000000800003c8cbdeeb5922b34f6b3aa93fecef7fa388cec6cecb47cebdaa259722f301a5adf89b46edbd68eca15ebf157342ae9cc57348e6815aa77363e82cc65aebc164e952e36085e5b0ec30ee07709fe0e64aa8a362edbc31dc7778a8062c77521cf8920370e0b1dd888773a16d2534947c571525cce46288b93809c0f8804c169b5249010001	\\xd9be445ab402b661500e93f64f1680284045ebe5e290300c3612c17582a992f9b8e64fb6f44132cad84bd0f2b92c60f45301373d05d174c379f2d5c3f58c7202	1668582456000000	1669187256000000	1732259256000000	1826867256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
192	\\xaf89392f7a2f5fc4f2db58f43139ac079605145bd7e95e97e5ae3d6e9efdc4f5bf6112cb206471e22eeff1ccdc680d7eb2c471b6e855c71c4266c1ede8ef824e	1	0	\\x000000010000000000800003e5152fe0e35f5f394333e31946c40e35cc668a95692e247d15f11bd72ea0fefb133d48d22c4fe970edf3097c98ba497a91fae4f0ed83f99def48d2a319225a05a3458bd43a82c5dac66fe35f809691b2ef084bd30e879d06e3ddeb712d6ae2404f163f9a470e587348ca323a41a1e1b723fe0758210531476b1b05f09d736c83010001	\\x8891ba2740a5c6a0280601561627ba872b8ef1d0835c1444b850cab28135a3c67972941049ebd35a7dba7073adc72f0b699d81f0269baf3a08db0138e2bf4504	1641984456000000	1642589256000000	1705661256000000	1800269256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xb08d38931a9a70ce92e891ac5e854a73e3630776154494d652bfc549ee3c4fc7b6cf08746ceb7923e9397513d67c65333313eb3274c30d8b341e3e9cb2c3630d	1	0	\\x000000010000000000800003c56260e919d7d1d3c1a4d0db9c853b774d5e5727c16cd778878c3f2331711aeae248eca2b28cf50b0abccbf139a9e537e8594f1ca6babf97dfa410a993a01dfef0f0f815e85dd84da6168487eb85e0fedb2f55fd462ab8345a06abf82dd4501ec4e04f3a39da17b85dadee49321c381557bfc5ff9da27c4c3af7877239a0bee1010001	\\x55b5c8538f6b02a940089b49d58ac3737ecc538838830db31902482a746750beee8d1cfeae17105d08089adcda42e2f6901aa69e6e98434d94d89735fabd5c0d	1667977956000000	1668582756000000	1731654756000000	1826262756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\xb6b9a358d74cee28120baf9a5a31e5d5a828159ad0971aaa63a381bf9402e1fe7f5065bec5d1fae46d23c26c2690ced7b6067cc1cd11438d2addc4fba1da1a78	1	0	\\x000000010000000000800003f3df659f9db45186f07ba42751f1363cae8686adb201ed1dc2a0956216215dada61dd8dcfa2711b82ebd17ca86ef05b4bb121cd1a06fd5804bcfc5d460a1f5208b4bdb9b18cd3eb5299ec9f42aad20e30e147a10927a0c44a7ccfa9ff02fab32f60e3a8aebb322749947f3176a64bcfaa73343c9db4e98b865e20ed0154bdff7010001	\\xbe59adeb89a82c453deaf54e03f7aa5e2860da44d01fa05ce54d5b86bc54ae3bb1c2180f21b46d446e3d6090b5a3066ca24627d0a977f02542278e267e1ff00b	1665559956000000	1666164756000000	1729236756000000	1823844756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
195	\\xb8d1224df674d96833ec759c4936b601f79eb5ad65d3a1c2dea2ac546b28896d37477a2fcfd9e4657157f2448b0bc5629ec6498426ac06b5e86f33cada042b96	1	0	\\x000000010000000000800003ab760ba07207c8e64917a0ce4c6bf5945a88d093b0af74a5062b21720fd3320e50f4e984671dfcbae620296f27c9d520625c1aa7e78e2c3b09aff23c6c3e818aec4f42b4723b1b890076daac69a29a35af3eb74c32c71e0b774f3d480d637833f28308ea43354b0517f466c648eded7170eaa52d8c2c3f9b52d798b3504eb537010001	\\xddf683e03f26e5c83184e12070fe68664efb0aeb9a411239d223a62ccbc49fb320610fbfda2a2f2dcbfb24b74179e93c3b0ead58eefa7a82808d74f5a515b900	1649238456000000	1649843256000000	1712915256000000	1807523256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xb9c98ff4b675e794166baab57f9472b24f6d4f3e1623c1080c561bb6e95a6e1b12e25d0763e2e675e2eadeb643e7731d8a6a6d998a40fcbac6e2eccfcf32977b	1	0	\\x000000010000000000800003bbd61921727e6be19dcfe621955ca420b207bad700a5754112c20ceaa6a3a4456ac87f8c37108abd73f963a71c4460fe9f2b975a2887c7f110440c024d392ad3dfdf1f8c194205b00e382fc37f185c6b7ef4e9a4c1483e586c8cf2dbe6b28a1756d13ccc1ab43b33427fdfa47e7f3bb273b6d8ce7a8bdb866a18bfdbceb121ab010001	\\xebfd419819001b8ad1ad326f67e8f04ee4fa29975feccf56f941629d57e277ac0836254e048380edd3f43c7b35bd4a8fbb444a8a212a9909b781c4a98c86b70f	1640170956000000	1640775756000000	1703847756000000	1798455756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xbab1b017bc47d448bd5cd6755cc4e9bf901bdfa0139dffafeca9f6c284d693d527445330190b8fbc373af232562d111a539c4babca8d647efb2ecd1dbc7e3134	1	0	\\x000000010000000000800003cbb6f5dc9aa55be55e49b87b2b2a4a17689624b2da80217f85b52610fcc1054e59e80381d827414d173e219391525f5d71986b6bf38cf305704819f8d8f2c8d0660a0e4262a3afc5b26edfc2267e8f5ff8ecfbbdf008dc5a6b32b46b103fa67d4c174db0c7eead1294c19bc76af52b7566670099c6def8bc14639c075dcca0e7010001	\\x0c6d2e3a3628f45d28b2fce862139b279c8b3647cd8523cf55a1bc3a86776fb878f0921e72e22ab02e2dae0f21a49f6c7b43f3ac41ff18e75de1e10f2a7a1404	1651051956000000	1651656756000000	1714728756000000	1809336756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
198	\\xbc918418c6456f93d4c965993fbb3d0034a8c78a41fc69460b09c5d798517d032c5ac328aecaeb7d622117cc9e24426589d86c35ccf22c4603aa8529e73b88f0	1	0	\\x000000010000000000800003de3135baf09e13f91fe8c37fe1e743754ad710a4665bb3e13f4b80152348652e0326282d492b5ace15e4fb2b7f6986130da42fd1e4f8d67f884dd3f500282b3b590dea8eb3348cbb60ba7bef3e9a0f4ff4f1a287dad512f5ce98ca167b7f4dcad46fb6a0e765ed72cadfb3a9e2339ae36140df53a688c9fd70f59d3e5653495f010001	\\x5e0886cc5924bf93dddd029e984f5303a59eac4d784a6ccfa26d1f4b84e1ed0327719a5556faf7b70174befc7e689d09773955dcd897adf8f1ee4257dd1fca0b	1641379956000000	1641984756000000	1705056756000000	1799664756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xbd21f75fc2430bc47a7b15cfb7d9857bf3c4f8787a3d3cf37b798df9c94ec156ae31f92c10e98e4012f1435c7690ca9058867f5a812b318419d676a289631e66	1	0	\\x000000010000000000800003b911cf2397ae52034220f625471c35255fb16a7f2cc0630cc7483cb7c876ccc8ea8c3fd472b75e33f60878b997ace568a84c1152afa1423337211501da3952b89c1840697d923156d85822f27e806ec207e746e3e9b6cd7acbcc94c124684e172feb14eb7a059876549bcd0437b1b60153ab7832e519b8be3896f00e0217b6bb010001	\\xcfc7bd6ae210e79adda6e374e4832e90d0bec9d24642b839f33623f77f69cab5b11e49781364c29aa430f4a857fec3affb67b456748a8a5c3e3c23d25924b60a	1663141956000000	1663746756000000	1726818756000000	1821426756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xc0c918a7569c9b1a919ce47c4fec6462ecfd0742fb3bcf728e1993334d25d1380d6e6a907659426341515ea2b611eb782dab152bcfbc5edc8b878bb9e4f264bd	1	0	\\x000000010000000000800003b060921470abfca42520e185b5a807459079da96659a00819e3804f1a14eaac309b457d07ff8efd7d83becd7682c2fa28b8190d1618d96e0cee32a9c7bb7698992928c550d16cbdca09d50f3e4aa0e77f3d396ddb6df56396224a36f1e1699ce1b83ed9f67be65125a74999560c9bacc896b6c8f1889d43f8cdc46aef3fad867010001	\\x46eb9d6dc022588408f66448deec820a7abc1b6a2ca46696cdeea229e575c95d39dd25a330f9786c6a310d75c429f44f1fdd1c8e57f8efc011c2490cb14e9202	1641379956000000	1641984756000000	1705056756000000	1799664756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xc2f5377488fd1ce4d0b3b9de6ebdddd14cac10b2fb5d16869162c7186c458715b6246ad3c7066a3d353a87e2d302bf6a32a5039842c6689c1ab104bc9c401cda	1	0	\\x000000010000000000800003d51b3c2a853358c7933e0b8071531f070f4b6e2bbd8c53ee8e478ca0fa15c3c5dfb6d81cb69cc55990b075bc17baa477dbbff87f28e124f1daf58c1ce974bc4d3c0eb5dbdca8f5eda3346c1d78ad0c8be873eb5850ee7b87f70487eaef37428ae1b364f7a2dcb1312689ebf22ad080dc3a6345073e6cdec39fb6786011ce1d0f010001	\\x988c358ad977f11ea588f61227b17d14b0228a19e416ee1b77464cffb58cdd2e4d05e3e0422cfe3c5e59b48c42dff2bacd183f0fd653329e4e44e3de9a5e4103	1640775456000000	1641380256000000	1704452256000000	1799060256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
202	\\xc48912d2313582b469ae141927ee965c0571ee7935efecf364734f2edabb0c6b0b4cccb4e30c6531d03f461190eba88785178c436728b8454d035926b242f651	1	0	\\x000000010000000000800003ec0c389ac58c1b14a47b32ba8e9c6630853145424a0031fdfe761685e67a76dd9b4c0a515ca1fcfbbf7f1ceb6f483322c5eb3588e915502f27048a46435858aa8d5b78f18b5a96e163ce0de431826d9ebb5c6d972c55bbb9b84b96b2ad27c7ac093a27edd9d4086d41ffdbc488f59bc253474a5435601274a76735c099243e7b010001	\\xecb5e48a8f98228a67bc405ed2a72f1935352df0b2ff9290f511334102f021b25e5194af3e4dc16ae7c7dfc359c4e5823510b350f5289eff691e4c79a4b6710d	1664350956000000	1664955756000000	1728027756000000	1822635756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
203	\\xc4d9666f4afa7022ef4256634ac139a70b964e1f6d4d5b09cb213c0e993eab45f350962bc29d021a3ba23438ed2102e2d34201709cf88782388e12b8cfa3eb82	1	0	\\x000000010000000000800003c7006674ead976fe4f88945b47b840d6246c752be3487163a1ec5a95a08e16d872388750f67ae5ca173d719777a83d050255780745296fd3ca2fdd996e15b55840bb1cd884db739b44ac22eb9c67f3107449c1ffb8219426cb4396ae976706b51bec770c24cdbf771f2f77ad3226a4c41dacd33ac7f94d3e3b0a45c7003bbc63010001	\\x36b2f975a693615be97df741a6050be5b5266b98fb747c00cab0ec99106a60f253adb4b694aa5342927ffb94650828ab276ca0c0e13a2e639e99f4f9b04c4c05	1663746456000000	1664351256000000	1727423256000000	1822031256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xc661584dfbf98c78a4194934e35033ff17daadde2c5235752248cc160e46125dad8109e4c5a22973dfbbe83a7d70070caf125b304292ff6bd64d75a237d42141	1	0	\\x000000010000000000800003d452149f62c8b1aefb66af457f090f17d43a783512e3f3c105fa058332adbefcddadecc217de25e8fc25dbd75b435986dcfcfb463552eb2cdb88d4fadadb7f3a818b25abe2226e987975fad1c597e6cbd62122c06b5c0c3db47ff5763371b4f279f0d727941b8ce866fe760ccf25bf3fc148c23764322a396f4791ced49345a3010001	\\xb69a47a539970e0c305626e9f30aee58558e186979b6857b08f6477b7eca6cf9f66b9ac325d01b2a869834059b97b44d035531b4092db90bd42b411da851f207	1667977956000000	1668582756000000	1731654756000000	1826262756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xc89165b06d4ff31c14452f0923539855b5a8d21551c35169ea3c4ba66a6bd0f6b3a7c35b4fe5b6e0b872a325fe09f6784dedeba924c4d304e7c3fc8eb493be0a	1	0	\\x000000010000000000800003b62ce6f2e8ad13a29097498c774687328efd8c359d8e6460569503caf8879c0aa99e931296feed0c5e4f3aa65e6daca1c8daa0235b51c4370e46a25c875fb24264a66370adbd8a9b3f87dd9778f341b5bf67ea1b9dc95b87a5a0794f487d65567adad5c5bb011e3371425ec6e7adfc0221d241deed8ba62ac80e62f05d4fa3c9010001	\\x9541d8637014929be2ccd126e28ee3f90e66baf8e840f455f455f22dcef01395006763e9c9c20a2b768876b637124764caf62400360e3a6486514f6bc9998e02	1657701456000000	1658306256000000	1721378256000000	1815986256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\xc92db92da2e695847a5a7278727fe095e2753d04eace3ef87277abac08c96cb4555c26cc2a900c1251eebc5640cc7d637b41b0e348abe4a25ec03637ff16d6b8	1	0	\\x000000010000000000800003b4a405ecbd1a8928b93b5921bc3a9589c7913aaba326f17d6eab00d2b47c859e5edf96de27a10ac99332772e18ab14b047074528068ef50228292dca465a5195496f42a6874eb504b503dc85d16049c803945b2c1f0d4173d3a3a9558fbe4c9f7fa10ab7f91f474c8febfe36498054fe691c72e88fd35bb6f7ab85319157516f010001	\\xdff71188a460e6fa0cf0f1c6fe6663af3c7e9b9efef27b7f91319e20db045f0a8d3430eb942c545101c8ffe7b44fe91f14bc39e7a9b983a401943cabb780890b	1648633956000000	1649238756000000	1712310756000000	1806918756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xc905a19df9f71c3dc012106c04e66f4139725e09fee55c520dc5e856b224406afbeb6b55ad6c39575031af4df56364ab91e2f9a32318196a3dda9b91cbd17f87	1	0	\\x000000010000000000800003b8bde36e5992f891d696fbcf0d77edd9efe2f34a8a93b5892cc48cca306bb00c40372164bd2c2ace0716651f03826095da5b81d129ee7b1720e4648bf7dc7e96956d3a73482562e9f962605844d74b79fb9a77a107fd2ed0a21f3c39c3b9d6407db1de2ad798ebc847939afa98a05d2e93b7b78f5bd5a05b001d9c77edabe7ab010001	\\xdbe822c7ba20452fb9a7db32defb243bd6730cdd4bc1491b4b34d25ad72ef30c18518a8ef42787e219808a29050be47eca9f3bba5b7ac08d776fd4f75985bd06	1667977956000000	1668582756000000	1731654756000000	1826262756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xc9bd0e3d270ab6bdb25db0ee1a0f8e690d50d1214f667390ae7f9ad115efbfc9e32d2c8588b5322f8b87181ef9cc74e7f5d3e3f63b8aa7d36bfec490866ce05f	1	0	\\x000000010000000000800003c8f2e0a245f369953435b6377f804f24413dfc5df11d08073a2c5a049748f4cd9e7c94006e37c903da280791bbc7c7740900b5cbfac0c666c8c001d5c0415256dfd36fce76c7c878d810668886e785ee7f02cf973a8a8a3bf453d6b2bf3541cba033db90c6cc8ecf1dfaf529ccb4f46d9846300828830bceab38d4dab07f3533010001	\\x10cca4e273220b1c29b80d2e88623d9ea018b87fe2dd9e173cbe25c0f279b415a6cc60fbeaaf4e5058bd63b5767875484831b7588732ec7f9bf24aa54a3cdb0e	1661932956000000	1662537756000000	1725609756000000	1820217756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xcdfdffc20d6b8ecdb774ab62243ff85312233b2b2c9b4a4522d915908e3cd55d920aa5e2470ca0ce80ff38b93aad450b7dd3817035c22f1cb0b0a66bbcb8ea77	1	0	\\x000000010000000000800003c628f38b40aef2276870bcb54c73c6a0e1f3b8cb53e41224244591c52505c33eb640e2286d32352378d915323e7ff677c2fadf895f8e492eefa4196c625e33f8e5287bf59d0e16da811a1244b411ae2d1f74b200e28e3919008a150363fac7fa99c81bed53b27a3e115dd50fdad9f34d0364968f0e1de90cc83dfdb8757cb85f010001	\\xe650222976ac99517b5c91cb009c1cfdd4206bdca1fefd3bbff377a7e421ce93dbdbd552ed73cfd9f15dcdd248db9d312966d2f51dcb3cbc4f9aded6c7806f0e	1642588956000000	1643193756000000	1706265756000000	1800873756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
210	\\xce9d3858367d39851fe5e6f28f386cd2435777f1c84915052d32682aa7e0bbde8018e3cdce417baff4e52ba711eeb9f2ead916513db70716984efb5917b51131	1	0	\\x000000010000000000800003aac655eb127177dc047f3d0ec28a35fe127ae060e4906eca963fef5d2a1592455a43d9e27549df566df0815ee26c3a9e4af52070a86233c7ea66dcdc90f21b8974a03208e7ca9785cb8d0a216abffb02d40980934b58193ecb73569fae6626a80ea88c3b422e41c1adc1128c8b6c571adbd648d105c9d7408ecb178be45b5481010001	\\xf80bfc15171964c15f7210402d40a667a63376ef423895302b5bc9b6f591fb8511ff3ab179457188de75b37eaec068734978dee0e708014e75424a388ca71608	1664350956000000	1664955756000000	1728027756000000	1822635756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\xcfe5e1a7830198a38a0cd86b4da41e96ac6dbf71efe08955c9dfdd5e317b49f7161487cd32b256e331f864c4e5e6a2eb0c3ef16f58ae3a6c4fa29fabfd7e3149	1	0	\\x000000010000000000800003e8e97998e1ac523011cb3007311133607e3ae1e18903be21506d598482c3df8afdac4d12e2f22bf26b62c03ae4ce42def073d40e8bfefcc1fd552b75c83ff195001614994839be947ab43db8b77ed2030ab257002c41ba3414e51d68253f0652156fc0050a3a46b0bf262c7889ea222a051a82963ef1bf96e4b1a6dcaa82bd7f010001	\\x9c81af2441f96b1894113bf7632d59addee8b8c150f608c6a3735a1e254e99a38b4eb5d214080bf3cbb56748feae10512a85f95e39294210c2dd2c7e69a56a0e	1668582456000000	1669187256000000	1732259256000000	1826867256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xd215e96f9ba1e2606a7bfa6a5603a49208a533de0581ac3fa7f3eb990e8e7fad8760d991e8f7e01c627232f0df40d6cea388e12cb2369fc2ea5b619b52118791	1	0	\\x000000010000000000800003d311808a2a04c0f08972bc70f72b5e2d10e1da87cafb2642b19d3cec268a518de7083a2cac9b09e6ed63b4ed6b157d4bce2c8b053e0b2ef85e4d78ef3860ab05a0050e2b921c1de3db61276e45f157d1f473353df73b0f1aaa4fa8d937cb881a1c1f37b40ea8b09d9c6ce8b17683e5fd27fce0a0e7d227d38165bbb31759fc45010001	\\xf90a25aca54f736d7698e8baa36889bf2ba82e413b002c352a027c49852e2667e53d932ea2cfa66d58660307ac5fe1ad065b7f65059d863969d539132ec3830c	1654678956000000	1655283756000000	1718355756000000	1812963756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xd4c16fff592a9e8c76925a4a21b3ac6ea1afe3087cdeed75dddb8176f23bb59f89c2beb3aa2920eea239541619ac6ca4a718cadde4d580136bcdabfd55647024	1	0	\\x000000010000000000800003a5ba0bc9a77b25b312e6f8283a3ecb42a4654c85ceacae0475e81d03b0b7fe1811982947acc5e3d5e31c54ee0a3501cdb7dba1f1f00185f64392f1f051fd00396691302ee1df88c7bb635d82cca48743405dd74818d828b71e88acc258e19943ccecd68b0623565e3b372d498c81c52d4b13204af2f963f8aa8fc6c1f530a7b5010001	\\x68bf54435480b1f2d114683d03168c1b5643cb4d5480c03f3ef8262ef0729dbba214925faad5b89dbd8ecb3c3b04f0e890d23fa8c3fa55f072d52cc383f47903	1666768956000000	1667373756000000	1730445756000000	1825053756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xd6e9fa7ef8852d4c962cff6025c547a0f7b398bbbf066025dfea17c4e0fc841fc2d19b2bb388c0eab95765a0f2c43a1336c3c72c68045438dbaaa726f9e3b6b3	1	0	\\x000000010000000000800003ac116208969aee99ac4253ec11a7a998b9794443bd7f194ea6030e8bbbc8ba2657afc369c3f571cb0b61c9484424ab02b29e02762ed2469902fd23b5cf98a6cd46b4c779732ff62b88eda1f63c29e3b4ba9ea7e86d66397020305499f3ca3a97eac764f37411694456bcb9dd7579bfe768e0a1035cf84523a932e2bbbd9de557010001	\\x0d84c270e39ebb6970ebfaa945eefc5c5b422c2bdcc0ff2a2b495037d71f77986fc62c92a8ddbeb3830f382304fa3824f99dfe49f2f10ceff054038033bf9e00	1659514956000000	1660119756000000	1723191756000000	1817799756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\xdaddb30cc26718e6b3f5d96d03f6d00ef863e8bb0eaf1bf5dd00bd1c39ff9c6df416da3f15598165969700e8ba00fe9a794fd889c44f2772e4e74c3bc4771209	1	0	\\x000000010000000000800003ce38046addfccc747540292929da4d386a54c41ed8ae4d78d3dedd6897a60ed785d8ce3d45e039e00bcf5cf0d64013098d6212d4a4ab37511932c93222bd1e2da97d258768c2282e6c9685e27aaeceb91cc388db91128cbd775b632b87227e7a15203f4b5b3b78cc872b6ac453dcc7968739f3dd41ea03aba699f61a61107d63010001	\\x736ef2bfe133f34ff3fc8c7311a961c07d85c5de927586cd097682a878d33aff87de4446ae0461c849225c7ae937e605ae453d7254923ea32ba9b50b92563908	1645611456000000	1646216256000000	1709288256000000	1803896256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
216	\\xdfed832ba9afc64bef1c8d0262d77053a0f5a1d95ca202501a367aa3d9fa0589ca3277d70c0009c8f1f6686d0e003a5b2018b727d83af08ab0030d4ab87cba68	1	0	\\x000000010000000000800003add5557dd28b3a5403ff4260c935e002af5b2009758a194acde5554f32d3d729226f554ba0010b3951a26c883a5018fb9902397a2a9c85e01550d53ce59bec3318a113494299fcfe2cf614324965f6abe80a5a1b03fe7b0b52235503f943df22a442ca1715be7796c43e0d12d3b8ba61a4f060dc385087226f2d20a4ddab5641010001	\\x1a113c0cf4d7bb193282a23b1da222e44b841f009c910d84926e529158a31a5611253477a986f26bf6fe50ba547931844c5752a43db4e93a646ec1947635390b	1649842956000000	1650447756000000	1713519756000000	1808127756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\xe231dd520ea53f58a7b97a6355c7fc51d78e7c91e95c3c7e86f11ba4c06fce813eecadeba92f5d6692a4e3ea9dc96cafb07f053cd25a6f49e0657869a81ed86f	1	0	\\x000000010000000000800003aa34219d18d7314b920dc1599035d5dc1696f5e727217c4e33aa7c9c60e414678437aec87eb09be232f67388e47a56953b113ab5bf27c9560416ae07555eeed881792b8e04ac895a58eef5883ad728fc8a7c2213eb4318e24855697c6fe3f4cdf3792db2cbc05b6adfeb2a990e6c53591400b7dd3d9c64b1dac626c08b769c23010001	\\x5dc1c8212c73a9ecdc126fc4fa89091a65153ab261d4a0bf2e0b983ff6fc984890062a9100cedfef2d07a86e1796d74c1a2143a980ac0e4dbf537dc4b4eb6700	1640775456000000	1641380256000000	1704452256000000	1799060256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xe691d6525a06b7a55f82e786afe05d9b8e1390112257abc954f9d360e555f3ca961b6935118ba9e905537874e68f63bd9034d580ed2750a4404c4699f1d77ebb	1	0	\\x000000010000000000800003e980ec987339594d0b42427d2b99ba9d60fcbf3591a7492d34d43ef9bfb0d8f117b5f869901ec2dc6bb8e2807853b4fbfbf15d9da5e3db215323254e8c6a4ce59203b371c240cbdae7969f3e06426e3dfedf83d937830b70a7553f547bebc271f2d42db5ac4c33c5f9a1db562b95cac44bff4dee12ccf0170f643738571222b9010001	\\x4f77b123192d1d0d2e9803b82f4f7fce522befe0ead11b361a2dd459eed1f6d00455ac7ffc1e5febb0e63b06f2712fe7a2495a72cf0cbe13de27b30ff0b7d102	1660723956000000	1661328756000000	1724400756000000	1819008756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\xee69571f8420cd26755f4db6f212bd3a16cab36035fe6e80ce0f2d7abf9fdef96c36914057768809bfe02885cfde24116012daaa691f5e7f922029d4eb353817	1	0	\\x000000010000000000800003ed06a81ab7700d82606ef7e14a9ee939eb2e27135f7db34f15e189b66c75af3ea3deb874ac4af06e5ec78321285d2faf0179d6e95ad8be4539d5550e69563860f78555cf0c822fd516311b0da4aa0006692fd552d87dc835f61e0708ca4a07c9711d9f04c0bdb1d9353419c4458c085876f4b01e79dacaf07aeaa68c5be1b635010001	\\xc7b2307fc934e031483531ac4d48d5456a4edbdf33c82023bc6d3cbfa9df895fd2140a09efa7c2c44b55fc2f3a946c5763b5f7c781c78f4ec3c658add5a06606	1660119456000000	1660724256000000	1723796256000000	1818404256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\xee299cffb0803693dd4d03c587292fa01d014c70c7dbeb7ca06d1355a5877dd17ef7964237960eaa0439fc2c40c60da43c1147096b7211352d26d9855bbce50a	1	0	\\x000000010000000000800003ac75e15aacbc2f39844d7cd25a8ff0a436b821795cec06200d4a0ed222bc57fcfe780b3d05249d1ddf993eb510e283ba30789f66546bb488475c2ca9119f34be4af54d6656432b2fbe721867c7a61ecb28c31baf474eb366986b53ca875595b87215a251ab3ed09c33edc4b8e997ac3a765ccd789a92bdda677e44b9d3eb4fef010001	\\x73c28a65d19bcd3a296fb57b5089fa2c13c538b55af0e39e62fe1ed2c255df034f3ec99b212187b4a58e856c9612be1b4a98cc939340f75cd022c849fe60cb0f	1639566456000000	1640171256000000	1703243256000000	1797851256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\xef35996ef7cb3c6e9f5d55a230e44b9fbc757d06041df0c1eb12425f8a0062f122d8fceb0e78c8ee7062057cc0619492f2e856e16dd4fa8e64655a0f5ac191a3	1	0	\\x000000010000000000800003a63ff160110f0d939d555f2f4e359886e49a9ed2081e077399a9a27a6f70ba551c84a75220e21edeb9275962e621a89105fb0c24d298fa7788aff77768cb3b40cf0317dc349398ca602e7723800f39bd7d2575370b9749ef85a083aca77aa5d4256affbed62996c568e4051c1c054fdbf7e24520d4bea08a903949b9af68a097010001	\\xbc46ccaddcf9845a534eac82e97d558db8718da891d40d95dd193c5c39a3ccb1ef9eabd9d70c920482fa8c7db11895cb98bc8d3ee8569f6e367c20d3f4db4500	1661932956000000	1662537756000000	1725609756000000	1820217756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
222	\\xefad188f1774470d0e2bd63f44b8009cf4cf0b538e4e8a6914a1c07e2ff69423de463b141b40792bbb4e2f6e3e758855516f22af8723b063f8d1c52c4625bd95	1	0	\\x000000010000000000800003c0cf35bed893bfd4225b52c12595cf873b0c9a1a35f59029585b1714c878974464afa49df1f46ba2ec9feaec6c0c4d2a41cc997dfac3afeb279675fed452dca98a00644e1246dded23575ff52753e00e0e5afe4a1928d001bc6f627de063c87d8fe8f00c846854b882bda90c14f728d4f1fa004f5223caaf4f190a7ac1ae2ee9010001	\\x387fe3a45b8dd5d6441b1fe6a817af91f8ab59c0b0b00a75daad1b323837e571deb54da9409cae688fecb868be9e609cd0f1041f1bb2e23fa9e1407f57bba104	1645006956000000	1645611756000000	1708683756000000	1803291756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
223	\\xf29529aa3be19f3321eeb666bcf08c2580d9357e2bba302e2387e2e6ed6d68f3a15f263dcb8f39ae132caabcf2264eb2b11200673c4452e86270b3e6b68a2290	1	0	\\x000000010000000000800003ae34001bab1212a019692ef3aea4092412f59c18a63e744debdd373c507b0da0f8790cdb939624cf59fa485f5f70bb2cc9941588f8c2975c6e3e4d91dd4f125ce618a011301c64cf4cf428960d54d07272afff4d729ab2b07bed687d0996ca41bd5065e43a6585ee841fce8a008eb4dbb3d552f1714eae61b76493491cff5513010001	\\xb23a1b9654105ed654b77fc4ad5bc29b380b8003611b669a107addaec7fe769a1d6d7383664df9cb6211679c0c3c447ee489e075f71ed56db500fedf7222d20c	1651656456000000	1652261256000000	1715333256000000	1809941256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\xf939a9245cab876d540cc7661fa65070cfb9120307c72fe4fedffdb72d3c0c04470e40e8e16145fc7d751fd9105599161b3e561a411113a4fec011ac9744d384	1	0	\\x000000010000000000800003b5d17fdce525e4aa00b41f6b7c538878f95ea72427842009e69b05915c3f53921a0861b4fb7f5601a0297c264e76a90cc4505aa06cb13e559a1b0f7e162d77ddbb4fe1fcc4f34fc7751550b8565e97661421edc0bb13da8f8ee4667d3ba12db693679177a9412e4d415b5de0f0e46db6f43454ecc7d57d8c1ac6ec91585ded9b010001	\\x07110ab337e5fe435a777395d627a457fae6fadcf63726c6a06ba2b81f5017e5dc07287869cde910b45098f74d2859c34d256f087b8ab5263cc55c060dc85a0c	1655283456000000	1655888256000000	1718960256000000	1813568256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\xf9e9bc826a02482c0caa246fd145cf42b6dce6891f49eb5be2cb3680ea8451f998656a03bd4b6fb201f88e544132d96bea63355a6196ba4114210ae46f762264	1	0	\\x000000010000000000800003d3f66489d17594ea109f50de85d1201d37bf5bcc773ac3436aaa20fa4e3ae7259c8cc7bef98d74e6abf3f7b18dce31a79195faa1adbbfbc53cb54e3a50a11c991eeda13f23a274b3defcae10496e890475cadbd0ec66495c78b7815e03c4515d98e8afb50b4b29320661a3681543c160badec96c70a7b4172289adb112bd8187010001	\\xf148590127bf128ff0204f8ff1d5f2acbfce0bed78afc26202f2cb867e53527545ef9906a1ed99b0e9fef6fd1310d20fce0678323dc221880a865861636f9606	1665559956000000	1666164756000000	1729236756000000	1823844756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\xff1d7f733d5bd336d81c2a687e5d6535d7c9f26b59fed780648a7127ce4de14e2d866afb6e2b0000384566edae1ff5ad578528038ed46fd39499f968a41ae864	1	0	\\x000000010000000000800003d5b1a1b23a927ce39d77f8203cd969777f4e871fb29a921cc57b4b32fc66ab420a3b66bdc5099be510e3fcb20a735869eab4c64c8188a2bf27c3cb56eda280b6e11916537245bb61d73e19fc062ba53f2a45dfdacdf13b66e22d0f69b7af6a3278e4a83af4f6a4ee8b2a60f0682b0c0a58295ace819556028ff8343a51a3219d010001	\\x53d5137d77da2f4a0b785b852a0470a8d04654d5e269ea3dd17505fd3d92a0b22548ec49e1b37d8f08840ae7f191685f901ff1a1ab2227af4afb397bdbf7f008	1658305956000000	1658910756000000	1721982756000000	1816590756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x006e3ccea92107deeb2160a003d76e3a78e1cab8b5db921a44f2d4ee2713aee0426adb5e8e4f56997d92a5bd652dc69195b30afbd71445f781f257b399a4c0c3	1	0	\\x000000010000000000800003fdcfc8f43e08cbac58a25d745163da55245eabc34e575dd87ef7a2dd5dff026576754f518073e045616f01eb4d6909db027370b6aab572ff0fd46669451f4b6df0cd5c68a57abd23cd83e2ed4ca81af5e8abf70b58ffaf90371f0d7df7897a614364b1fca4311697835d893bc1c97685f08934edfad0c59e9ddbb2aa9de5453b010001	\\xf752e3d10b3127eec8578a0b8660d5b758a319fa7863923630cd6d52c670dd2624865eb64bfe7293c10618d5674920696c504d9e6adb284dae41bafb5defd201	1669186956000000	1669791756000000	1732863756000000	1827471756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x0572b9b1cd25fb31a17c80f45a2272f532badb6d4bca4683f71e6a2c6b5ee8060240305aad33dc8d044b3c3a6ad5df2427bee25ce6465f142a5ec4addcfed9cd	1	0	\\x000000010000000000800003b4e0fd54cd11b952da6a4c2e7ec78b013664d2b2eb7a2191d7f809692d75e4b765b170250605019df3e635d2fff2f1872b8c5492983c5ebdca130cdba7f52567d5c2dfaf473e7649a8bd7a5d4c809d95a88b6aec86c097f793bf55060a41ac079fd6f393cb346e617c6cd0864152f6d122a81db87e40f12a1798bfdfbc7ccbdf010001	\\x4ed076cb40581d8163bd20bfe9caf9970de3ce8356b5a403d49f344202ff290cef5fd1b1d6a9243af0c85e1fdf4a11878da3e87b063692f23417d9d982b30005	1666768956000000	1667373756000000	1730445756000000	1825053756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x10aaee853dd4754f5cbfdb3a1205ff1ca4d20c0c0740321e9856f95e0ad201fdfa1b0e5947f9b86292c58fe2ed69e2572ed9eb98c92aec1c8eaaac420597c277	1	0	\\x000000010000000000800003d8df6f8e80d8fb4fd144689ddc641c59b634b6ff23c34abd05090d583731ad70cff6556848cf30e35c2ef126f6a6fdc17650c8eeeff4494b96b530dd26c2e0f04fa6bdc3618f3ec1277f233f4f1fcff23a025c3bc8262e6ade9a56b0f119d05685a647790943f45c71ccc64b9e4d32dfbe692eda4863254226ad4627ef51bb93010001	\\x35562571ad484a4f9838f8a7968792cc0a48f48aa5f697ac8d5d6a1428e676cfb0dbffbc8bb64ed56473d1b3db83b5fe2ea1c5c6e48c271a3bda5aa303f0fc0c	1641984456000000	1642589256000000	1705661256000000	1800269256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x1592e5384a02f573327d7dcb56cc1221b17917fa95ae2ab736d591ea54b577ec6e79818bfb31568c607bcb2a1cfd8f6d6597e82f21978efe62daa7f78456a527	1	0	\\x000000010000000000800003ee9b31f800229f5b9f6644172a8789423ffa6ac3b7f25d6acded44fc105f4133576eaffd1f631218818a776723db15d7d5fe49d60cb25c8196e7c4054e04615e89cfe40f0a6a8e19f6abbfe7ec6a7af3e7ce0883258f74bb7938703abe9f09e368e7c8c439f00ebdaa6726cef8bba55091f42c935c1bbec71d3bf70a183e0e2f010001	\\x6118849b9a1165383c8872c9427dc2ae79c259a16bbab6994fa5dbeff1b652e909758c0056d13cf4a2d1159bc1efaf4ac1294c1c1551969ae3b5ec980352d40c	1665559956000000	1666164756000000	1729236756000000	1823844756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x163e8f0d0a8e6d775acf6ec9956c6200cff2f27d0a9b4c4c4c267faa4aea8ae655d8f1d3add56b90cb6667ffacfb97b4ccda1014b79306d0b6147701c66be347	1	0	\\x000000010000000000800003d64e0d0b96832b29ad7f758e0f7497727fcb939672ae6d5d3330388caaa479b2352501f98807be46e7d163d8f527dacad9bc4201330ce236db8d6ff8b4a1a6e94db50d4c5341fe3feee5ab206e127dace38e8ed19ed282abfa594ff0c7fc7e41ab743c12068bb254a5e082cf088024df0aaca8cd13e2f89e922d3cb286465a5b010001	\\x1a235ad03f7197c1643ff015f40a168f5bc1084a08cd8662fe97b5218ba906df60d14c7370d75d4e408f9088464095d1e108198db2a50f7c1d71782ca4d25601	1663746456000000	1664351256000000	1727423256000000	1822031256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x1866a106fe646f6b1bdb07237b433a209bdff42ac594f92abf30d860bfd0c3b52d89016fd485f46100f566812e79eb07706999640055e74dd74f3a2eff2a0aa3	1	0	\\x000000010000000000800003b4c3d168125d66cf9de116973157b19e42c5d1cb477d7e331947a84350dd2ed42b84fe84d1ab1f9e91585148119641116fef2987fbdfec637c9d74c14b848f0b84cb7ac9c12555091a598606990ca3fc6500343127b700706329b4672f63f9fda43cf2ed5d2fa34e8a16800b4d4fc776d7701250f38a90c93fcd5ff8b7d1f89f010001	\\xa0c4cf80c502592869b74c392510af68d8828b3547dc00926c976825bdb42827a893ad09d4c7516a1ef96bc0b5abdeb13fe6483d5d8ad024ffe6492b51c2280d	1663141956000000	1663746756000000	1726818756000000	1821426756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
233	\\x1b6a890e31c5e404bbbb6dc81a4a74c52d649eeb104cfdbcb5cefd188442f23ca7bc22aa76e3c36c1a123805ce14022e6dea2df2b9c6648a8cd33a392ae6fa72	1	0	\\x000000010000000000800003b5ecae914322d35a7cde3c3dd6c0c6b66f871c58aff35a292b10e853476291b66a61650a67e5944c89a51e965d67eb0babf27959e85f48fa792c2672e241a532666cada3df6c9fb1213a8eb6c03bb1584ece891f42e30506d93097bb81af5689d7fb25cca4d4df57a2db5ef0d00e67bb10af99bea927d9c010185e57eced95f3010001	\\xce25a98f8f7f9b15f530c842d9846ccf62d53e38f81c43408c7e01442fd4cf15c04f0708e8b7e49073e52212538187501a127eebdd3fbda987138f9a38ff440a	1664955456000000	1665560256000000	1728632256000000	1823240256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x1db626a0f773d7ac8697bb5dc4441996119465a06713adc170bcf8a628a8e5c999b06939d72cfe72ba2b0cc5af86ceccad59d5c024f1b915077e0e49fe890006	1	0	\\x000000010000000000800003bf6916348ad85e044cc97db40c1e8c69fb2c9671173e183d7b1a6ca963f0af45b39d5ff06d33c2b8bb5ff687f285c61d1cfe07003164aff1c9c294f0d3f8ddea134a4a51b18a273d3d036a7db7efb748ce34a978e83f0ff9a5c8a5246de107b1a89168b01c521df25911aa16df1c33259cfc997818cdc88dc5c2a5694b68b6a5010001	\\x3e63e56a591362944b912ac6d01b92a48cec8da7d3e0eda5ae194eccb0b1ddcad554dcd6f8558e2a2480a44dffeb275350148354aa4257bd7e88eeba2ba1310d	1666768956000000	1667373756000000	1730445756000000	1825053756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x20ea2931cd3d64c4796fccb090cede6c58172073a331b3ed0d6c608e02882fffa2c4b1834c63b204c9bacf39f4072197fe60de8e381e413db6565b044e1c2f0f	1	0	\\x000000010000000000800003d53e99e433fa31d0972702566e8f63a2b4762ad58c9c594e701038924cef62fd653e0c25418e69f84a16c38654bf08b333a382e070a2f800c43de61b57a5a4f5bf64d0657d3c81de3dc465030b8d09f9e30099af8e6feb55441b6789f7a0b4baf27357946ab2d5b6d1a2f28297a1029c62752a6cca4b4052c03e0cc9f532b597010001	\\x924eff2eb9b6627dbd657e9aa5172dcd6c0d10b6d0f2ecdd6facc7cb6683fdce980ffb868fdfa769ac24b202c20f36391a8026b76bf055bc55af3f799961a60c	1648633956000000	1649238756000000	1712310756000000	1806918756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\x25c6606f7b3ebeb11eb3ab1567d9e513735f5c2faaa50355382648511bf7698650c9b9be98d0575dd45ce51987f5d631991939cefa5ce78a21e69f596461f1e4	1	0	\\x000000010000000000800003acda2bd918a7272689a98dbf4c7acee06ffcab18dd5c54d3e5fc58882b634226ff041cbc2e1d5a185b9e5d1bbffe1b14ed32e7a8adbd328bb10bb3c383e84790a0ad1daed260ff3fadcb1ad81ad8ab55d2d17d1c11d4fc55d9188c6f4ebdd5bc08116b5f9ee0bd238cbac34fa83e78380b55c811b3da23e13c72c3e06ce9f4c7010001	\\x6af71c9b284465dddc50bbf5d75c8581f8d5882573f7a627f79276eb5ff7d47b4648bb8b0ad170ebf4d2a68a03ef0f55af370f08811b69d741b55a881887ff0f	1638961956000000	1639566756000000	1702638756000000	1797246756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x26e676a6083bde62e64e2834d857f339486e8aaf4b7a4e3760fa066a3e5a7f5c736e30d8d70671db0c4c41fd3a66365b2e79a7450d2ee526bbe2d24733063d37	1	0	\\x000000010000000000800003ad10e134f4b3dcac4a3ecd96e3ab34f25f3615b150d00a4158ba536083b4512e86b5b2469f0f0cc4533d111f2e5d272d5e6dd7b6d0bf993884daa8369228f4a7a3fc4a977351e0d030e85ed908a23d1a50f4032a343686392f98d53f8b182cfbbb6baae9ba5ea162e9c88e17dc9b4f053fce0aa39f35618a09e52ab06795dbe3010001	\\x76e0165fe92a9d8e421becad9aa252ec963ede057d0c1d7fef696463a2d546c2508079f08006b187bb154bde91fc4077b0340133da588c0ac485e9f02df5c904	1662537456000000	1663142256000000	1726214256000000	1820822256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x27a68a1eede551ee95e099394d7a7b795a39d03897709494294270ef565e4611ac42698127a16f1eb6ad60ef27823afe5dc9121fe3b0ca9d2e74d324afecb661	1	0	\\x000000010000000000800003d1b5875f9c06b6e7135433971b626a67fd5d585f6c378accefba0526b959266eaae5b9a1e63378c7c3bfd05c100c49721eb112f5bd04d874a1c4e806c51ae73e049e91c661ef5dc54c951f902c9a1741b95233d8d46d281246df916081640305e9282a13d5ba4be3cc6af9fe01ac1d2c7aa6cc3caf7d0d3a5ba3c644c8d061cb010001	\\xa572ec19b44f2246d7dfe9d81407fef5cc69d58f7357991ee4f42db53721a5d1f4003f65ba5021e6194b13f10c330eaf8c936b54de44707a37a7505a5c1c0f02	1641984456000000	1642589256000000	1705661256000000	1800269256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x295ec450264fc524093b988d88df17a50b2f39acae84219b457f850874bb008f811c04a92387f67a55a2e727b15104ba6b5df1066ab5d03cd006b4eb5462441a	1	0	\\x000000010000000000800003ad7deb2e429bf65efc5506e51268290c25ca1ebf5d47036e0a52c5d94a02bfcbdf7da45d0ab7d3cf65de89682f599e892f9b863b7baf9fa9f391d62ed326e2f103f5f7e37f58b77fe06ca8cfc6fad73a76c30728eb0bd8205f10f7cb069edfae5f971d7bbb54f5297826eea78a163bdcb4551eb57d330d35241908e82a8df09d010001	\\x08eba28a1f03b3fb621f6baed1788bc79a2fe9918930452bace5dd50b2f2b3132e9028269b295106bbaaacd2e770bc9d89fc4374a522cca2344bce866ed1670d	1647424956000000	1648029756000000	1711101756000000	1805709756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x29ce7da4a49af70cd7ea30ae53979d012056020e51d6bb57c12a520ab3df5292b6d23d539be8b1cea0de1f95e591684602163b6a4a69961858f304fae206fe92	1	0	\\x0000000100000000008000039c97777b6a587da49d8b1a4f8073573a34c08e209fe6b335767d4c8a3a5f84a5c418a50d350a7358f9c1d7a7cb3badc469abefe4686c455e70c8a1402c236350c48075246216b733201236ed70d639916d8e3b3e2c43570b50153f6b418b2b4af9bb3bb2d986cad5bdb5139187951f4bb58154f38f7682c491754e384a639057010001	\\x5dd2b8ccd336336a059653842d143d627f1207d5876a76a361d6dfa706ff79e76896cc16251667136905edbdfa0320195dacedb7c782d61d4cc19933e74df401	1652865456000000	1653470256000000	1716542256000000	1811150256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x294efc09fce5006c6334f04f01a6a760365bda2ba516275ab5f7fb4fb03967680597c81d53938254021c51333780d7863bbf95cfc4548533dc8e94b7b63da98a	1	0	\\x000000010000000000800003cdf94a9cf21d3212095da7f053bded048e50a67359a4a40513834899a103c8afd65caadfa1e4af2451ef0435845ef020c61def3f68f2e13d2bfcbeb6bbbe17e984e1b0ea99d309d48dd2ff997eb47822a52c7b76bb0a8846522b1ddb87b8d5b71e386b21ffeeaf156f2e9dfaa13216e4534b4baa6881ccd64c666ce9ed849fe7010001	\\x49ec55da5faa9f17d04c954fe720d55ee6c927339b438b69b5865180ec0b596bea702d5afa0f7901437776dd86389eeeee7e81a53cfd632033a45f4829e86b05	1646215956000000	1646820756000000	1709892756000000	1804500756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x2baaeb42e98c74cd79951acbcdf602ff31791d1c8ac34af36a5263eceada8abc2ab25e361245c882a7083939e8335a4b9e29bedb428255d4793c75211e6eda48	1	0	\\x000000010000000000800003c2a16b6b30a915bf89051a27cf40ea605c192490bc20d45d6817687c82fdadc0f24084e4f2830d5f9c69774f8e4cff09ceb6f7044c94a7cd9ab66891469ad9a3a66ce2d3773af5df4bd3ae31b7938470b61d65bbfb07fca2ccd234eca2dd311b200b648510af54324b6b65cd85b9de38e74b39872bfd42dd521940c3fbbfd939010001	\\x95f12a7466c4b0dd94af7ed4bf48f4be4d792c43d406be9bbf3f1993f97c1e12951c58bd72dda6782f0edc5659c30cbaddba2f24075af65fdcff535cbd5fc70a	1644402456000000	1645007256000000	1708079256000000	1802687256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x2d76029c7e7b382ee448d3ccdd3a16b78133c22c23ad953149a071f8d610d3d4f9fabb46f27024a7df1acd8d28c02aa3b0f467f1f6b17473746034cddaf9c595	1	0	\\x000000010000000000800003d3e3cf2b81b5c53eb4dc1c98ece31cf4410bc19a611d5a118c45c534de92ff5be83b310056a6dd9481cbcab4c3f798a4fb3ee79277605f46cbf83cc4b2d10e6e70ed14f5fabb795e3fb5144982d7d42e071ffd6cd258d590e115087cfd3a6e73964c7f93fe892dc1d8f8e95d7db6609d3a6755c3d6e4682fd7e557bd574554dd010001	\\x2b649c7826d1f8ca4ab12185364d0100cbdef4ec36eaea05e0b677731a030c8f9d2027eac52f1fc6f9a5c8a5bebdbfafe9b52a4cc4de7365dd90d6c9acbc950e	1645611456000000	1646216256000000	1709288256000000	1803896256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
244	\\x2f2abe959acc8cf836eedc32c85a4bfb3952c7b5cebfa95688818bcc1dec42f43f706319d566fc2900db9217abf09b2442cd695ff230b880b58d26e4f029e4e2	1	0	\\x000000010000000000800003e3ff0e8b0952e3147ec349c76e949487e8cacb7bc61dfc262928bfa20fb64f0f773c4edc5f076e0df6497b1c9633885fa55184dacfe1da19c927b9f876ad83baff6c3c946deb9be5498cd88fdf4ff0788d54a1e3a5d81d7d1f4017e9d1d89233700c7002b98e779b1763606454e9c4fbd3f9435954dc74f6103077f9aadb1cc1010001	\\xd10faeb172d5a2996b56f277f99ac110562525b46273b578a37d29c6c5ba3c072c947220efb43067aa9aeae742687e0fd65c181ace36ffe60cd7d2bf3f4b5804	1655887956000000	1656492756000000	1719564756000000	1814172756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x3026f45eb0f35af42bebd78da16431cbcc1d42f7d2113e1bb6afdfa0cf7b9b86c45259e5863b7e6d60f7878f385e5e5f38eaa9aa5896128b6fcf394cb926ec94	1	0	\\x000000010000000000800003aa687bebea956e89d667f1f657e32cc28330d84e33e1daac137d2b75e7d23740894205941070d82623d735bcce94f68a5e6ea8115bdd503c4e901266dbc5d9f49cda65c52bab5721b35d98d4dbb36de338a70651ba2c870d9b6d02d1d07c874fb835104d40a2e511b94fffc55ecd2bddec0b47180c6513b0a4eed9b4d0b009d9010001	\\x47e363f0dcd2627f3b563041c5e7ce592e7603f28c565146a57b8a3b0220bcfa74b38878958728716c07f4892c1ea0d9e47f6ef8b3c8581609cad880d9d7220a	1658305956000000	1658910756000000	1721982756000000	1816590756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x30026dc99989df66b7fff8a5973e9ae5e6348eb90c6ef9e0a3513a4f8c67af668c5e1cc059437193030c13adf6740678b8e14dc5a3e25193d5f409cbadc53137	1	0	\\x000000010000000000800003c7c0b7b5bc637f63836279292109e22aa6495707673b3db83e4ff42f9cf32ae6850271b4285670dc7b5d7fd9574e4c10a116a1cc9c3de42215aabdebea54d1abd039ac8c3752e7b930211e793356f8c742821c8c50fb9e6114a6c99b746431b3d26e5af954690fc7fe56f2d6bd7ee29a6755396bf95611392142184dc4e15179010001	\\x9760c4866b29b6f82c73f43572779911840d7295a2671f5b449a653b07569bdd0aabc54fc2c9f3410c3e8ecbaeb096a3bcae2c1d7568a6f1be05bc9c2c04620d	1663141956000000	1663746756000000	1726818756000000	1821426756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x313a2495a35e61fbfd7435eec34f41e1a454bd86b77d27a0523d4d05f142aa3fcf366a202d13dd958157a7fdb4650b9e6acd90a66191c4ddc3dda21577372e36	1	0	\\x000000010000000000800003b0d93139631dbd3f669d4020d6e2372dca3a63fd10d54dadfd480dfb8dcb00fcfe865ad5960f34cabb48646356397a1384abb16ed88ab0d7ee203a344a17c992132d348eec94328ce6c13964bcbbf72ac87e65e87b466aa45a95e85192a5406d8544fc8f35f260b0f1b491fe78dfb37452a9dc2df40b2948758a08a8e47d46b1010001	\\x5b6a9b23d63b68dde5efda8137e619c32fb86ac6eafb16dfdef020c5763c814e8b7a15d41751a7585280f20c12029a61cbcc57494875c1e62cb250590f49b603	1656492456000000	1657097256000000	1720169256000000	1814777256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x321e97bd5459a4cba8b4e401ed18bd09e5ba8749e9af2fa63c71cce1dd33283a631e30b7e10451ac7d2df783e7805daf43d335ed9b8591a71225ca86e633b3ea	1	0	\\x000000010000000000800003bc202f8f93e3efc56e1cb96716641a492cdd4774f8668b2e301d2da00c48a7b86be2152d201d2e72398755510a67c48807c5d78698d05a54b7e39906549cc5e856c4ccacf1bd64ee0532019372a38bee3ffb0dac79a28106dff7e114f53afebe57773d970f148a5e134d051673ebc95ebd8373d45e06cbed65084030175c8877010001	\\x68fa04bb19928394f39868cd8ee4c4741e64272a9207df8b7c7de6186d34e7e825681b948a8c995125cbbd259da3f15e46247b645802e542914abc462a210108	1655283456000000	1655888256000000	1718960256000000	1813568256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x35dec23ef1bf636fb184a2359fbd24af8cf08b0ef85de6e10299c8c64bf93615138db00370a928b7e9727186a3d4c22e2cd744b2cb867a587492940d74353a91	1	0	\\x000000010000000000800003a8f09f3ba064f20a967f308529272dcdae6521c1241c6cbe61b08d8f7ffd4cec29c932574929e79b7ef2666e4d499795aa74a7a5b276b21d1d4d0defdae181639d951e3894c15f8109c0eb9b118fa4cc54a187cc260b4675af6768b8ef0e11b7a591b7f15d8418fd6a0cda4ee192bd5d8897bcb7518f3f113f25cccb5016be11010001	\\x4096e79c5b5f185cc5d19847fa9d4c12d0f3473719d6ff6f9f678948bab0529dc76d003f136b8cae9715ba95351bc086fe72767b34d65545cf275bb3e1af0309	1652865456000000	1653470256000000	1716542256000000	1811150256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x389e3bf60891f6627794fb3a22590559d826e2a4b2c2dc5622fee40ccd02c0d53f72637a1d07ce052ec8f30137abdc2b159b0612755c04c134be4fc7d79dbada	1	0	\\x000000010000000000800003e5eb8290d7945119366e54a38bf158a59b5d5466cc1d40d00421c4165d81e485fbbeab9e5b8f1e481c27d1415ac65e3b6b59affa76eff08c3f489fcd07185e189f8379a25bc73146a8dd031aa6135c8ce37fba9b2bab5f35fe8b9e7f096e5bd6abfced5ebff63a1e9d0d17657155b1179944d04565139cabd810704854019d79010001	\\x781bc22bb0b967cc503fe17863e24eec1185c9049461abce7bc364f35e3d6327ad56d23439b29430dbb3b12cdca99790b577081595cd64b060270efd125f4f06	1667977956000000	1668582756000000	1731654756000000	1826262756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x3aba712d560add9f0f14d0560e23c4d5028f6304caf28041632bd5ebe621ac6b5bbbffac524162b54b43beea7a375ade0c38df168c61b9cf99922e1f4b16eb53	1	0	\\x000000010000000000800003ca58966f845cc1a5b4bfa0f5f7bf3ed0b736422c386e7b8031429da2924a541d1b1ef64245122cde5ce47052f0ce65f548f68e2834cf6afd93ef6161488f75de6e1896b15bfed967bdc7b13c8bbd2caa91ce9d62210d000135921e20362aa84c2d0aaaa2457b65729cdaf53e3a4416c9631cf930b49e5cc440e23d44ec8e13bf010001	\\x5dcb6ae8e194aaf650d441e3b005d4f2962d8e59d1933c6720be91d8de39e093b0abde338e9c46dec1dc76bd251472ba2820893160c8cd9ebf4ea34fb852fa00	1644402456000000	1645007256000000	1708079256000000	1802687256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
252	\\x3e62e2a30f29ec2690686ab2c2402de991b9ddcd93e9b95fcfc945d3a76a61ceae167950f9531fd8f3d4e951fa464dbbfa48799296e01e94650ab415a981778d	1	0	\\x000000010000000000800003b5c8c9236236f760f648afa3885ac8112b2bee1bd896d93fd82be56e3006208a4a2ee4a3c49a623d34680a8e53269fec3173d4abc933e13875f872eba63e5ab49c62c5b213fe49343874bf8310e6183c70a15b4473e2ff9fd7dbdfd3a67751263de7048dc5d3e830c6131508edec097b0fce094c7409c3c47ff080915000327f010001	\\xd7f0993adbdba4ff0bb2af1ea05852493ef65ff7d90691f5f8b59362342ba25f9530a0dc09a4d34d158c0d08a3660dbfa0f9ecea606c3c1adda40bf7dab6500d	1667977956000000	1668582756000000	1731654756000000	1826262756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x3f667cc67a933361cf864ecf66cf2a68ab6e97258e588176ccd5a8b1757dd0e89b50c734aadc74189a9d900e08268460a7f46aaa5fa78bbdb523201ecfe32484	1	0	\\x000000010000000000800003b2cc05afad3f8034516d22ff33b44a0de6d67e419f1056c73e22f5d8e0d14fc35896a3cd832774d88afe3e3915d172b7d35a359ced5bf6aa4eb730b812c7b61a472cf075e68dea2753e1f4e0084cba9cb92722844c7e9f66231933672fd59f20a3ec7ba2ccaaa6a7986bb7809bf4e0a47089345a7ef284758b3bb024ede82da1010001	\\x3715df50a9caa094215cf404b2ec7c9fe41d70f95f4b6b42ae4b0df7f661520157018a0f6b6ff024baf4d31e443d3ba3911bf159e5972ef4687943147c93de07	1649238456000000	1649843256000000	1712915256000000	1807523256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x41bec73eb891f643fde562b4e8c258613e3736dad8e2ccd823d92d29f18448a73f987aafba0f4ceb6711fd5cd384170c9502c41197e8ae13f6475520175f4538	1	0	\\x000000010000000000800003bfcbc4e66e05b0c2a25838d174b2bfa487e6d911adddeedd6dc26ce42daa594edcbdf0dfb9768b03dc62e3a2b92b09a89903f1d5a946f42f88186091f4c055d47d5a767b46b6161711fbfae395036e070a837194dda85fab2244db894eb33db47171d8a2ff470ba6a34e90c75fac5f1691f1498bc734a591bdeeacce3b0e56f1010001	\\x32da6975983baba9ae0b766239d08cde0b7381cac5c1b4b3a1c856beb5cb73db77125a04b6e21478945a404e1e59422fb38c894d942d4d8354c58ed8feac3b06	1655283456000000	1655888256000000	1718960256000000	1813568256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x42066b7b3e597ff1b16c0bc6962ea8111315e7b704f3078127c88d617a50f5758bc141fb85e58a96047621ae98de6f4f91763e7a030deb1a7338858194b6b7a5	1	0	\\x000000010000000000800003b0f6aff35982e31204ba808861a721c748c1c0f12c6a6f01e6c2bfa9724021375bfc79003f54f6f08aec082cfc03a9887362eac22f95cd7d9ad72eff1e6d491715fb9cd99d093cb5e83b4aae0d296ccb863f6f7adb16d200fdf935dcebf62c71dd6b9fbdc94eeaed515ff5f762928eb5a5e17c3f2c1f98bec800a9471e45125b010001	\\xcb63e7ebfbf634d32b56b89fa458e2726fef701a712d041ee4922d038e732d192606eb7842f709625b40f0a88fff95472c7a0f577315bfacb78a5df6720d4706	1654074456000000	1654679256000000	1717751256000000	1812359256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x42322d32c47575e5a4e43407092858fa21d206f88178bc27abf376db6b2dc1aed5b98bdf39240a5da28fc511eb91214a709f0ae33b5b362c44a600effe629a0d	1	0	\\x000000010000000000800003c17bb5fe01091e286f025acc8742eb361b0b76fb6641b2b6677a2b4c71076dab4229681c0bdce551597059ddc85f065786906d8b7fb4d5dba682b7999d6dfd402d7122aea7c2449625f7cd45eb3f2a31ba6e29deea702f63fbe7c11a976c3c9447805669126d90deea9fb519d557b546adc3ebccb4b84631c36bd83b14dc5b61010001	\\x63fd82102ce92f0772410c076eff45a2434e70d1e799b3f7890a25d89f7db2d1a408f6a6c8abba5176947cbd2bc5bdeb1e380f04f7933bfc3291fe57a5469b07	1644402456000000	1645007256000000	1708079256000000	1802687256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x45b6106103d378a9f28fe94cc587a0523b33424570289f45b3e073657fd336f89ffea6f4679f5fd3648fb2756976abb06869231d41b01a5815b23c550af46a8f	1	0	\\x000000010000000000800003b0b08dc22778853d567e483a1f21caf1f2055bc5ca9cf5e1e4fb15188cc0c84a79fc44d535f0c83fd8824995e6fb01cbda4dc8568e4cd07327c2db9fa7a653589452bd063080c1be55b8e61038dd21aeeddfa7827cfd4523d5f45daf4f9a36ee84b49dcd6ab0776b83f791e1bcd2870a8946412d1793bf556b1b1c352d57290b010001	\\x51e5cf1ab093f2fabf24689e6013ccc761f4877f3cd35df4c41a179f2d2cfa13607ef10e1f52153af22e97fd4c29d0a9aeb5e3fecda3d553d4e9b0ca0b85e207	1646820456000000	1647425256000000	1710497256000000	1805105256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x4b72f6254f135b17678b1c368f2f3c825f5060718ecf08eca3b6571024ac58405c5356bafb2545d7984d780363e3cf2b1c1023aa756fd17fc056e896e08e77be	1	0	\\x000000010000000000800003f508a7ef30ccf889b00fa16a6f355aadb0d63e3c39de56beb0fd8d407aef261bd7d1a3a49474618af0c30e4ce3e1bcfe96e613f0ee146bfe5f6088b547b798c79d109a4565417791ab2b2f8d39bbe6b27a06a7e6024c13efa8717abcc6e82e3336dd00979781d7670923ae8c5d35f2a9313b46fdf56c0b4007a6f80fdf371349010001	\\xc180159da491de5571cec2c0c8fecea16307838d8228580105c666bc1df720db61c18acde6f451157e148c920aa2c1045c71ef92789fed22caee729d65ae030c	1669186956000000	1669791756000000	1732863756000000	1827471756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x4d36f4d24dbc76a5d45dafbb22bbaa128d2ac351b9ddf70f42d1dd20ef69cafb88c5de5cc58b350d586a304e0e996fda5df71950f18e4c1ff4b72c6475656ced	1	0	\\x000000010000000000800003b1447cd37290bee7a9ba3667de2e462deedd0bcdc134fbb9abb4fef56c91a3a2f6635c77914bf10c982aa1c2aa35f5d55809c5a9ef03a80afd3eaae6c9f5dccbd4a3c429e08421fef980a1382c33fb45e7e2bd175b5c782c3defffa9d45aa58aa81b42dd213a976e31c3ee25a3fb6ec38aa22a15b737c9d127132117ab77397f010001	\\xf2225d935b27797c7afb79a89d19f458f983dbb3185df414a612c625287826441de626e49532dc7807cdada9c5420116157ad3b3212c3259e901c6930e048f0a	1658305956000000	1658910756000000	1721982756000000	1816590756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x562a9e5f5bff5ca25fc85ebd07f640b4e8f981bf028a0ae949a23535e43060004a8c29fd7e212b71f8295b6bacdb9a20146d83bf7227123c2bf9e8e419ba6744	1	0	\\x000000010000000000800003f3c7b5cf053546d90632acdc6ad1b8a7892c9e116bda79d81867368358aaaecae68779e12acc9e5dd3c65e1b6606e18ee324610fa8490b8ca9ee906faa25e384cf4e5591986ef5339ae575d06a8807d2a38b12e104acd66a722520e6b92fd50d472ef3aad14bb31c15a9ae33c86380a0c49d30a04d32e986c73b593371e10f6f010001	\\x9bc5e526379031c4203658d873622286d996238b5136c2315fad9840b9fa0d2b666f358bd6bd1c6221664c462f47ce1d903c8dfbf683564a4a870a4712348a02	1657701456000000	1658306256000000	1721378256000000	1815986256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
261	\\x576658226b461840a5ceb7999ad48b46c32d13fb0f301eba9cce623be04d2c545a48d2ac246ba5b755fdfada930b74348281feeb43f7c88270156f4ac20b0521	1	0	\\x000000010000000000800003b825a4ca1603273c3e1e259141b4faf8f5ff0cef6a88b702f1240e20e880b587f4ff404fa1e66708ac383c92adb9463672e533b00615729b59fd1b4b0a5715c57165ec24852ff81f137e4a343c9316d0337b532300b864eb9b731dc4b874d71654173534c18d12a51e4aa5d1c07ac0479be8bbfd9e2f707afb8d8bcdce730669010001	\\x34b404abb0af4c8dd483817a3187b97aeb35f02dffde8fa8589130067ce4b5ecc9e3f233a3628b567497713f0a0eb6a0168d2cc41ea3335c78f5beb0878ebb0c	1643193456000000	1643798256000000	1706870256000000	1801478256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x57ee32a40bda5940670533fea69f1064ea586dcde4d1ba5c8704900ef1238233f9c0ec63d68b7cd44fe208ccf3c9db77f3b84519f6f900978c27da49f6e1dd7f	1	0	\\x000000010000000000800003b96040131291cae111f5c7e9d96d254d0e10de05b09f9b87cbdd04f731651cc958014e1a782a4cf801738b690a30e474d640d03ecdee1a6c6b7a4d3df0dbb5203e94364aa37d1f96456620e3edf653cec9aab3a45d4edf4b5cb2df0106b71d052183f64502909d9d46a713b10b679a2b5ea7304b7bc13b6ab175f47176da3f51010001	\\x9f57c282d21d6b43b6d28663d6dc402341af99e05cfc2c72cfcbe2558dd4cf60b81c8a7bbfce7a2ff323156b9e88a6ae1366e3c2990207787f9a76ff073fef08	1655887956000000	1656492756000000	1719564756000000	1814172756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x594227a1eaf12d2a88bf59ff903e9e65f037cd57c8d1172fab76c3d039d96def3cbde8fee1694298352fa6d0ac23c75e34206aa706397c8c648b1ec2dc8e84fd	1	0	\\x000000010000000000800003ad38f25809c19b45a91f9b0e8215989a26b1fddffe56ad86dee9c66676acd485eb92b3d8274f2efedbef71825f39a6d1469f62271ce5533f91d8b248ef97f7c4d6d9a558a0adb7d731a9c7d66820093781080d44d55e4ed213db485d7afa0ed1610e7ec503b6f52aade7e42785e9f695f5789172cf60545e692c13619abeba7f010001	\\xed0a23265a5ef9a8aa383b3062ddc3e0fe8a2fb75846cc304f881a27437c00d532b16347fcb621b9bd9ca13594ef37fc20638b3c7cc466b43aea2b776cef140a	1644402456000000	1645007256000000	1708079256000000	1802687256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x59ce83b8fd950cff042a1603d50f9c834e598a05b6ee4da2de91f3cc40c9a4fff3f456c79f0d377994069438a422839620147028f6ebcd9958456faed86fc83f	1	0	\\x000000010000000000800003ce927b3762c96ced1fdea68853337b969a114ec9f11d928e829dc179e6d0def2488b6751cbbf948f3c39e89ef207b00a3d768e249275801760cf61d4ca72a8bd73d319d698c095fba100fcd1dd6fe69ad28d1ea01511fe6acde729179315115b344184d5274470dfa81e027ec90d8f47e188026f809cb17c7db4b75ec06afd0f010001	\\x0e9853dfbef22cd28427d0a55f8e3e607a2a4b7de375df23bf9dacae5c68033c5a40625cb2974f09294ac512c5c7a184986704b02593681d919e2451ef1b6003	1642588956000000	1643193756000000	1706265756000000	1800873756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x5a8a9e33f3653c37e0e586d86f68d5a7657cfade0da77e4bebafa42cc4c194a4e54e5d9730ae18c8256d67d3f6d45effab4574b6ac481e8f8c6266f5eadae25b	1	0	\\x000000010000000000800003af7f6ea2d7925ee66b64dc540f29e3fde4aa72330b36196766b6ac007841060d6a6f136c0b60d78bfbd1247b1e48bd95505055b720d53065f9db0d661c247603a11ab724d07b39436cce4f564859edf6b75121e971f1684ed3f7505529e5afa09e0fe9da64d65811a025b7ab351cdc2a1235be978b631f975acd8d27c0d857f9010001	\\x9e381fab6899db71d9bbbe8a3ecc4708b93acce183dca3004fa32691b64bf2e89e5b9fa24f0578dc5a3f4baf7c7f35e804d6f7561300533b4cd62d0462fa3a0d	1643193456000000	1643798256000000	1706870256000000	1801478256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\x64a203b190afc1c0f5bb53f39cf9b7c9f3739a62b00f186dec453cc91a3407c2c1f91677ad0ac890005a3e454b79bcb1978c10650e765ba1eca5d8710f4dd872	1	0	\\x000000010000000000800003dc1a7547b69ed5119b64b06e7ece510434fe2d29e6c6f3c57d98cea17f6a42711e8f3ccdd82fdd5248c7d753c3cf5a76673ba98caa8f5869f94ec7aca049d946e03994625f9fc96e21aef99107a8f57d9633f49833ab86abdab19a7e1bec851aa5bb6b67128b83cc9d732a9733f00d57c006c863212aceccf3e544c67c71eb8b010001	\\x4187b8dd2baad3d6266f4362a226111bd8ba18301897c0fddd01dae8bd9d3908df9aad552816f4213c46b0fab74290c8a1a128793bb87eef249c7336ae52740b	1643797956000000	1644402756000000	1707474756000000	1802082756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
267	\\x65926013e2bfd66a478295ab0044a8d6080f89c467792171b7fb2eeee954dd868c1d3592da6197728b29927cd4535e89d604d6e969d67a6540b64494202b636a	1	0	\\x000000010000000000800003bf3ec87e6fd33370d8020b6f15db4a43317ec3f19ad79d5874f451bd1e1324e6403e2c695ba2d5d017cdfe7beb43d152d5ba7aba4d5d3e45d866db0a2df1c580beccf243626d67eaf3a7f51f12f531eb7e8b4518882c15b8d31e90d6453fe2e5d74c06f0129a66dea4e0f7d32ca8f54f5b6ce5590b60b90f9961f64da22ed7d9010001	\\x32c4041a0223d81d0668399b1d492a3b5f14098f0cbc7a663a43d35d90d83193d1a819aa8d3350e985afe86b4e1bd06b66acdcc8707b4a2bade1ba435ed1910d	1654678956000000	1655283756000000	1718355756000000	1812963756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
268	\\x66d6ef361c75d3cb012e07a2e272bc72725c63d425363487ee1626a06562214e1c0f719c9d7ccc0f0d3bedbbd2224aa2b1a5ebaddd30e3bb0578fb733d1f4ed0	1	0	\\x000000010000000000800003cbaa3ccb54a4a57da29ed8a186af923892835a4a23a9b125d1eb28f6df38a64ca39c147f2a13d01a3d9a7d1ed262b5daca8b8952648d0098dc0a0b0d36e0a95861569020698452c2566c8edd015a6a3999c53ab2667ee6a4b723429a10388463e9fb01edfe4aeb94c0a965690d923e10d2e9309ece6250d6f318ec9f7a0216f7010001	\\xcd5025f4309683d57da6fe01475836b30070a32264c6203d0663f6a7077737ea55c8b74ce9cea74bcb83a7d829c032bf96185f2e42e8618505970dea563f650d	1641379956000000	1641984756000000	1705056756000000	1799664756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x6e82aa02c386e8a711c6e265c583377a45db24b1b02e274d66abecfb7eb2c02b666a68bc30233f38856b8fe5490c023a493784a77c8101618914480b8b899b53	1	0	\\x000000010000000000800003cdf8cefe8daad7c772c82d0c7d08d729872d76d63ad74d95fce040388d89023c061dd459d21c6ea5c20a8d4bb5138231710680ebd4638c91d8de2b8876bc6d34f6a29454cd94e44bd14bedf281b090c63778c4516a8691c1cc3a57644db475a06afce12595fa3fcb041692b07c7779200efa7352bb5be2fcd4f7fccadeaf79f7010001	\\xaa26d3754d9f6090124acb7e130b997d3bb9422361ba3be3f08eeaa34aca8b1ed410a361cbd9744228348849cea2b3ddbeacec6fcebb8ad805272a7b6d68b900	1644402456000000	1645007256000000	1708079256000000	1802687256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\x6f32ed7b9befa264f5bdfb65dc3365598532974bc6a9c7e898d82271b66076c1082856398a385703bf44ed44eedf574e87a59c56425ab508a45266552336933c	1	0	\\x00000001000000000080000396b4bbde37e87ae6189f3bf1d24408967103d0badba97c5ee1c695b8932e847e3deaf29a45da9d7cdf214bd7332e20aca71b0a2f62420a2b21dca9ea3a41be45e29a0a8898e7f388872bd23e77a168d1dc68abfb363f85cde88228d891f5c3ba34e3ba363a49e5b00d01d17a8cde58320314430cd9e723e26a41e91cc5151463010001	\\x439a5670853c84e9417e6660a675777b2c61eeaa8ddade1762873ceec6b5b02a2edc08ff07fbe38a9463310d2ba8c99411ec63dcfcfd3ebd6ce15f4aab32dd0d	1656492456000000	1657097256000000	1720169256000000	1814777256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
271	\\x72ee98e8e0186f2204e615ac5c19bc66fd1a9572d96a4ed630f5298d09ec96209e864a5b758973fae3a6d5c9c626e9fa4fe5c7b6011256ba3bf6af3ccd95c008	1	0	\\x000000010000000000800003c128fc8ec2a4b85e829c55a8490a34de12fa8691b7316a86d1d4b0047874f58968334f9d1daf5ccd0d5da024ec7cfca4c6c3a83a77d9827ba08e3fa1d3a289c8c55022304747cbe98d28765940c4f380e79b95b7e033bad98b1ab743c738a5515fd7abb80835a1ceee67305ba0dcbf98412351872cfc47b5cfe72704d12a98c9010001	\\xa32350b5771e0dc28cb61be1ec75bb13f137484a32f46443daf9542b0a350bfda0b505f1bb0c6d172e377c6944e67929ddd369f5ea5bc7ed68ef58666f39460d	1658910456000000	1659515256000000	1722587256000000	1817195256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
272	\\x76ae19f2e12b863437a9aa9474b3f5bdeec585311917701fed52818fb8cec5be1cf0599db8fe307f70950a0a2b727515ee86f7f56d6aba9dc8da4771baee5fdf	1	0	\\x000000010000000000800003cc602e1848c9107e9b47206c07396b86cf94dac84215d3bda9dce5068dd575cd35ce33dad49e105dd78796da175fc4cec19852f17ee67f9ee1e3173e2c5f0447ff4fe9bdde311e9dba6eae03ebc1703ea3b248481c103b4907af485637da093f2448c5dad12bb677397157924c27bd8bdea21c7f69837aee56132d3b0c81af21010001	\\x9f65c1569eaa9e16c4c2dd6bfacddd87177dc1b0a46d50d14dc86d1d74f8602221be40daf8772edde8de3c2d5e031b44848ce89d97c1c87fae7e1b33b9f1380e	1666768956000000	1667373756000000	1730445756000000	1825053756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\x774203d5f25f380914982d045ece66c397f2ff7048ec425ab03d880d24de9c68c277f63c2585834c5097ee347051308e9935bd900e3764039f37c34d92554680	1	0	\\x000000010000000000800003dcbbfc13c342223283a63f812f385cd3e664bb26cc89227035d460300f62fc13cbc01eefce3e5fce560d52ca6b1ff462bd83d0a183e3213f98ae8c5488cb10f650d78a4ede3cdbbe0506668f703eec79db201b311a4f3e2c29488c30c3f6f5432ec4a9a338fae02131b6c8319e75836af293f18bf2bc95536de906d390470c11010001	\\xd2caff38fb609c58cdbba70d30d89c543c375dec64f8e96d0dc97240a2b299c3d2ed4c87ed1dd7908743ecd35588df65d2bd05271887900379918f7640e0c50f	1654074456000000	1654679256000000	1717751256000000	1812359256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x7b7eb323275d86dd584ea5ca6e8451f2b8bb23714f6c4ada79a83b94409a807cde5e7d7c5e9df3f6b6f719063d2812a6bf40953d21a60674b8025a53f0f912e6	1	0	\\x000000010000000000800003d394d3f9ce5bb0d94a56fb608a4f02048c5a0e1d7d30ddc3ce3c9475644f4b75773b08aad1f4c0cf4c3eb017b40491b51cdee1ec3801ba8f544408217b84adc26883bc79f7781ede25b08f7845ec0f8d9ad93e7f33b0886e47d98ee15d2af6813bf570b3d54100ab11c997a326a31e92799320419c2ee2f6ba0aaf9bda717fa7010001	\\x1e0906c6b89705f1eb077276cffaefacdd3dd2f1cc79373348bddcda43cf38c9eed501c94f13839931d13e0574c1fc6f91f051bdafeb25b0bd5a48084b878c08	1645006956000000	1645611756000000	1708683756000000	1803291756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
275	\\x7ee21880b7da2a44f1326998607885fbcbfd30fba77091e352f0bc05c563bcee8769a5f8a88da700d18d879827de428c843403c300940c932ca963eb10830645	1	0	\\x000000010000000000800003a3ef46eee21381b7a64c68bbb0a08b5db548a9afb397e8afa35b3a07dd13a6da19a8d5ce43ca7339a67a94cfe9f31705447f82a421274b19fceb79e9c3bd3a6eb4a49b582a962d246677d16f56c2e76e008af4b9c1e850403f6f00002bab1bc32217c6aa102667dfd68a5e8761152d6f7803c18f1d312e3cc0527386baa004d3010001	\\xbb74361ee66beb18bab8e02ff85375b086878bcb87f43ff9c8f34475068ad2a46bc03828a2159d43dcfbe5e4d9a11de8241af8a94c7f00a7cbc783a76107d909	1667373456000000	1667978256000000	1731050256000000	1825658256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x8252ee0c90be5783309140241fe99196074bb401756c1e8f4b4e34a076890812fd914ec674674cb03846edea9c70b01c26255d8c1aea6d8154f434314dad4173	1	0	\\x00000001000000000080000393ff60d8eded1de1af45e0e33e13fd87d6ab8f8d2175bd700583737576bfb1e2bd7dda7621d59a2eaa51a998f4c6733f3e481700204e5d6405bc1bdff3531340cc7a231c8a906a739ad70ebeb317791359b8617389177d3aa805a72117e594e2edae7b1e82c915961e1eeb2900575abe37d30950de9ec866dec179bebab90d65010001	\\xec3e431a92ae15f25d0a21a54f7afd562d1a9ff9fffb7a2480aafcf10688cf1ce75d31e304c2e9abcae71e13c224318008e8eba0f10961cc90ffb87a8a747200	1652865456000000	1653470256000000	1716542256000000	1811150256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x8b4abf929799a821f31e5fce396f842730651085f159b652ec3a218aebe84010ab60b98e6a0869eb345d28df57fe17b3bc9f01f658428a897b031f74a410c846	1	0	\\x000000010000000000800003dc908bbe1f28011ac890479d6ed47d62f00bad14489154c736f9284fc319a26bb73a5f1426f0d6b7912939bbf59c0d4adc497b6edaf743d75053033067f1e4555bf93b70143e6f674a3c85ba2d0f3fae00cd04b7e0aff5181fe21d7e23ee0f33b03101332b92e3b301844a58b1f3dfd63da08182e2a0626d38bf07dc6e06d773010001	\\xf99c68cf4de79d0312ef6a37c4ec2334c05be2aafd0729bd4733f0173878bee5f107640d4f98242663f7e544bd787aa2f8ed6a10c37820b3a38faafe64917208	1664955456000000	1665560256000000	1728632256000000	1823240256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x97e2c7c384b7bba6a97fb42157d92a968818af46395c06134447e947f6c8995550a240c8be2834126f348b97f23e8a33c5833fac890c30c10208d63602030536	1	0	\\x000000010000000000800003af00175c21d94533cea764b5abeb62003bf1283b5c021a1d2c8d39bcaaea2e911d2f1b202bddaabaf91588fbd4d3debcb0f313d5fc78a6b6bb77ab4a3a9c6c273309f52b207895f3f58c9ff1a92e50bb532c639483352e95349fe4b8665eb648dabf9825e94f0112f5a83c9d40c008b4eae9b146ef9fdfec5f65b634d021e0bf010001	\\xbf6c871f490dccde86a76d6df2a9c5cd8c40f07a93d7137f6d986e62a756319fd3bb0cc7f561a0afc8400bec1dc3f75619ca653527cdf0c14d5531b006940904	1642588956000000	1643193756000000	1706265756000000	1800873756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x984210fbc35a8f11360442d8cb78f9e2e3e92b0a82b4c581f89a8e2b70da0e04b5683fd15fa90a9c16dcec44c0f45ebe3e2492445d8652a54550108a8532552a	1	0	\\x000000010000000000800003c0546e772d20565e33e90d8a5991eab528de47be71f19b4526729062453c4aa09cf149c469ba930532dafd9eb07563a24f7ce996dee8473430a60ac2b49484caa7721aef9f6749b88e85d87474948d22efb485eb872e0ea1c1d898b086b773166f008a8c0f51e84dce1b102eeb78072863e89637e22e3971998ef79b646f5005010001	\\x7ea35e1d60dfa3f0087125e2e0dac6bbf37b59a94a03a9e4b1adf3ea4401f4a4f284eb2f67fcbbc9523c6af41b4ecb2b8ac163cc83c9abb613b37cf1cafd9d0b	1645006956000000	1645611756000000	1708683756000000	1803291756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x9f06df57477ecc5ab82f2e3932157e15315c71116aeab76922281138164e64ba835cfd90abf1fecf5b22538053065220ecc94cf0649b0423fa0ad6750e7ba651	1	0	\\x000000010000000000800003df9bd95560f1fa1b61cbbcdcfdead0b4f4c4de268cffb25c8081d00afacc35c38f7078992fdc0ba6db345bb651db359a7492bbb0b9b88e172b4d807a2b48ba117236708f39d341a823ca813d98377d658c268d60e7b9b1ed1bb1fee491a524ac946551fb654ff5a266024e84e365e2ccb9de40003c815959440b637f8fd27bf5010001	\\xebd203b1018fedc8049446162e954d50de0e6509540907a86bbd9e2ed6d907af1c8a286a4640a335f0175f2594706a16da578d6aaf5181d27575af19ab658f0b	1652260956000000	1652865756000000	1715937756000000	1810545756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\x9fa69ab4c842874c9016ddb7a742bccbf7713b17392c918756d9e01534225c9004296778a4a8c0a85108c4f533463f03fada7fb698282a8ec5ef6feb61ba5dd0	1	0	\\x000000010000000000800003e29c257f7eaca702fda526e9ee9526e7a71d213a9195c44f91e3af25825521136eafc2a04cb6a8a3c881156c2800357ce424431b1d9b3cce79553df4cde653188d631365a625b4dc86db8aaf110f364da34ab9e3d09ac64183ae0121c4f7fe2f8381c78dd2059b3e109ee93446ae869c813cac75d7f1c3dafdb706a86c01daf1010001	\\x366a16afbb945eeea1a7f0d9c2e2f2425a0794f067a4e7bb05e17832ccdc8724091233cd4bc11fffb772b32fc4bf60d23f96dbf6a74147e49b5fbbae1628400d	1659514956000000	1660119756000000	1723191756000000	1817799756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xa276b8187bea0ef006fe194d54e7731fee27292d821fc94739db941e0f8263723d88c2853af44bbbc9f580b6b031d7f98e67f3a302ff1bbfa415820b5121e925	1	0	\\x000000010000000000800003acabf584c6aa303632ba16be8b0d4bc4027d97ef2fe522a81c9b5e38906f36c76b88ee22a908a9b55fd1676cf84bf060adab3d953561b9552d37653e05cd25a42863d989ea8ab7c3b2a6835f2fdfa5f17b90fb67af3e9eb7eef4675c2b8ca1f7f16937aaff66190ca3369a3bfd9f7617e54b22b97aefa3ee767682cbc5c76f6f010001	\\x7afb53295420c9970c7c921f199c7f72078a99fd43f3812f083846f4104f3d6f4cb85af24a870c556052d9854a8a871f027689ca88398a094e3ab5a55a2c7e00	1639566456000000	1640171256000000	1703243256000000	1797851256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\xa34698fcdde19fe712da8cc508122583a555a5e2614370bbfd6861d9784b95a2a547890f982dfbcb6ce6e0670d6e151bfefc22be886b94b22857c56e958d5b86	1	0	\\x000000010000000000800003bb92b14b2975d55dd0299b71bcce437aeb1e81c1723768c50930c4b71eb9a439c4c16ba1db099abdb2f06d4e09d2b94bd5fd141f86561660985520ee20f61d658427bc4d4800b85fc27fa46940cf8b12cefc424279dc7c18a100753aba46a93268c6a0bb5f9aa1e71e884e9caa693b5cbe837b855a847140db25fc7c2d726ef9010001	\\x233e217f700b2ae0ec789ed340af9131da4d22a4804c6a8766391be8ac5618eaf778d7d036a6833efb94490637284ceabcc1770cfae735bc78e01b48b5a63f0e	1657096956000000	1657701756000000	1720773756000000	1815381756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xa4260f7cc4c799d22803903e91e90063a709164d49b97614ce0e91b53feb906a02e4599bb837656df4404b0a2d454ecf9d0ebfc3ac59f3ad2e288641a1998629	1	0	\\x000000010000000000800003b54b752683bb89d7bff999c4a99bddc8f2a53870a4f6c7c4d5ecf046e12892aa02eb6266fd57a29c72f6c00d09807528b60b85c333bed85d587db35b6494c9c6427ce64f603ee34f7952032f281014d608c4c13102b663f7b5e0b49bc35a9e32874daf6b244ddc431f6617527cff211fcf41a24bc725e1ab178b195f5a3d1e67010001	\\xd1dc20ff6f548adbced8647d74c81a391c95d65d76b17a0827ac329cc75019b898eb90c84df4342e98b62d4776ee5ed7f56899216ec3152c0996f414bd20790f	1657701456000000	1658306256000000	1721378256000000	1815986256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
285	\\xa752a095f17be380b698a1df6029cecce69cdc3ed2eea6beb291e6cdae44a55bb394bb6c4f57eb0bb546cd662961ca1a8730fe1c3baf89ea965b96d0096c6a00	1	0	\\x000000010000000000800003ae28c0b75d0654db44cf22358776957a18236e78ecf186a0160b9d7bccae5b8e8746b15ac11d2c382afe6441c1b3509f2d28e14e2ccef96eb17c72c54e4737f443bda34891a7c75bc1993c3cad35559f776df4baba99bce89cef4b96c1d34d21ce6048771df767b6e2b191afe9410975e7dce5ff82293b379dc57b52e7de5707010001	\\xbd0e51788fe597b97339b5c105f79b79a6d2ec592e62d7e01a3d4f3fb3076db1f4ff7d9894ec5c86b2237c72ec905dd4b69f890091ecb9c2a70dca3fd1f58d04	1667373456000000	1667978256000000	1731050256000000	1825658256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
286	\\xa9f636005f189fd26e9d3f49408b169f3648a201a7f4181cf82d6cc8c487db67b22fe9742b715cdd4b3c488ef0bdfb84eed59c8284ae1dd9702c377aa581e765	1	0	\\x000000010000000000800003b80c00a73da2442aa2000b4af6bbbef1fc407d4c70d35c387b36997eb6d9c4cf8b284bb81d8edec3da0be13da86f365ff8774bd88d1e9bbcc85e707fe14d50d6a2ab56af51dba78f65a5753f99a3db085e1cc3677e355429d70144e39857e04ffcc930689af66c644f04c2565a8096f5d28af068e26ea76cf67afcd48e754b37010001	\\x521bc7797cf270f901a5a2669881798e770998570e740b9c92211dbb924a862d8687ae3ce7d12437cdf8a922d4709e56e45df9203fd7dee7938c125604f00e0c	1658305956000000	1658910756000000	1721982756000000	1816590756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xaaf6647b2235a37749551de29e67d1ed06301fc492bbeda1eab6afa858ceb1793090e11ee9c748a7ed43f89a88db890fc3c24fde2162d96d2bd8c510bc13e57a	1	0	\\x000000010000000000800003d160ac11f01783b81d469fb9bac61238cf58112864abc0c38ca1aa35e312157fe24a5d044993a0be3aac6f6bae089053901d5d29a857e146a53215d3f62806c32e7c782ff272ee46b427ade2b5aec6bef32dc57979e78615cce9aa1cdd7cfe4a57173b06b90d7afa342deae8158f69795e000917b55edbd91f706834298eff7f010001	\\xaad3fc9263548f77f59f6520c9b078831b92386b72501c1b6ec902fc99adc917ea003e84dc39d31ae5a67b68ea67d65655b7d0b3f0366c756ca3895bc396690c	1647424956000000	1648029756000000	1711101756000000	1805709756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xaad2482ffb62ac6585d0d7ad05c7a9122dff261dc0fc1cc86a8cf3a98ba1def81a14a26c4cac4571b8b041feb6df6f4063b24d631ae8f8133c113560b0d13c29	1	0	\\x000000010000000000800003a1e2b99d30db2f65b6afebbfc0c6bfffb642ca3e907de773bb82f315e3887a2f2d9f81d499fc65d2a279fddc6b261d4b36f53db772d985747143a086fa4b7243ae36b2fa1ef65acd22ee43e5b177c2b5b8fb7e34729960eed3f6e70f8edde89325aece1829e70aa75a7d19d38dd068fc2058e7a39fa938b32d97bc39fa5f501f010001	\\xc57c095837fe396207a63973223a9ce59018e99843ddc5bd559753c58b76b7381573ca463980b7325422c62295c2e4afe8079888393f796a7b13e2dff4e15d00	1653469956000000	1654074756000000	1717146756000000	1811754756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xac9e96eefb49ab9427ae992a285ded4a25acfa5548cf44966f0e527cb57346a2e2f966d7def959fa0a6240f1663858c99764189a223c27a3066ebc86c52d252a	1	0	\\x000000010000000000800003d2271dce7d0fec37b5f17b0633eb663599f82ae40d9b66c1ea444acd9d43b573c9bf5180bc23bd3669b5a5887e2b4f8d5761ea3c222acc53a37ceb2fd01c649379746022713385dcceb183a31012096d9d31b08ebfd85e049b5caf0ddca301d2621607643cfd035cc6b6bb3903fd862a1c174ac7897e0fd50935b7777ebe58cd010001	\\x5f933ebf344ee77841cb747d85352b83e3a78043e6284df1348a85364e0dbc52329c7a9b2d46981aef5c2647989f9a7279bbdaa1f489bcdbcb3aa5fa04d46c08	1668582456000000	1669187256000000	1732259256000000	1826867256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xaca6e1109d88f5b7d7a830d2ab40ada0af8d50b717e00329bc0e7ea6559965c785063ceae55f4c14a401b41a373cc07312a203ab9f500cd6ed74e1917b47920a	1	0	\\x000000010000000000800003d010d55f8968faee861ff89cdf64612f5281d8aeadb26779aed313e7ca177a08eb5d29d65a7fef98e3ce3aef633ec1062ec91399020cd7af2059de9e18f0ff09e7de5bf3f984422bf4ae2588942c30622ac4ae52b6a831a7ee95cf76639dc18809f44f122415678e68170ef96539ad86bf43ac0a75a9803803d2b6045c53e919010001	\\x8db034721ff432bf4c143733a34e5de8d9749e5c6daf99dba6234edc5b6f7166ab2ff877ba4d417264e11199002004bbadd0918a59894bc750791be5bfdf4103	1651656456000000	1652261256000000	1715333256000000	1809941256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xaef2e31a6d6df7e6ec1c9c70f67f2d4e9a4e698f94c66469769d3d67a7a313f4a3d6ac1760a1a408ea89aaa8cb6c47f11f5f5836ed93f9ae59a6be679a33b6f6	1	0	\\x000000010000000000800003cd74f88f1d018c18a4bd90a23fdbcea2813af9bdceb326e2790348847e7493c43ec1b82c74cdd16eccffa97d793ab8fd0ad227324007835a3893505be44c842dbbc77f1b844edfcd6cce391c52dab2862292988e301dc0b95144dbb8e48157ef050ec75571adbbdff62f746b6f2517b5e319f2281c49000c653855861cbfe5ed010001	\\x88c5b42be9cdf2aaa91c62d00099c302a639233f5d35bc8036cf18eed0d460260fb10bd645e90fad82475dd7b1f5dd3ac0119e2792ed62c612ab9f9c87a1810f	1664955456000000	1665560256000000	1728632256000000	1823240256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xb1aa53982349ff8af8b48c95313db8d7a8e5fa1d701ff56f752a4011b7725bf76fc08c1e1a593208b1a558c7898d0d66d81b8a18d43bb0c5f05fa98e174d18d6	1	0	\\x000000010000000000800003c7ed42a40560b147ce0d4e9e19a34ff190d2cc262d32829f9fb8ef534f513866c8fe3193624013825b2d42037faea251948e298cde1df83414bf0d9f3241eb62913ae7613abbecbc08d8fc0fd321518dbf1c8afba6177a1ff4d03bbdeb5c1e4454a9e4fdf0b0508b9a7b8c051e5b2ab81671b739cdbb707a1760e27d3fab82df010001	\\xf5161609049dfc87ebe5356a9885ade5e107f6f59ad02aa594941e3d10ca3a1a60799003e1fbf9a7849e215d706c28bcf592374dfe524e708161de510083f707	1640775456000000	1641380256000000	1704452256000000	1799060256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xb32e42400b120f5f1f2f40d821e5bbf9b5d5e628c6fb5a73b89999528532211050ace24a51747af1b5eb90f98a8be8165be21cf04b1c9bd9d01643ee62e279b8	1	0	\\x000000010000000000800003a3caa7819389cd6607f91212807863e21567a951838f58a6dface32ad793ccc6dfc9b49005d59a286b9a1ba33b95ee77e8f36f21a7a54ac45eb528ef06ca18a6e9c16903286989a3e3b7c7336248d58299435d8f47f28fe6e125165870f1e723025d20d67bb02e6b2fe4a035f2fd001a96445108e920001086faba3e32b406cd010001	\\x0e56878c93c447cbcc3f98c60393d8790d5b6106243968d35fddca38de2f4c7f385948077849a3639dcfa6ca7e5ef4f3d7d086216b90ea4d112821b55688c908	1654074456000000	1654679256000000	1717751256000000	1812359256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\xb582a6f52305cdf1362dc43d3f4c50dfe48677c6f4e847269196046563595bd068e11bf2add33404bd6e67cabc16d3f8cf003e5fdb086513ff34516ead4f5066	1	0	\\x000000010000000000800003ace9a4b71f7628130fccda94ac0c40ed4d5433430e63ebb33f238bd056e58bfeb9f19bfc511cad3043ff2a9d06f6fd3d60ac5db3d9c52545e3dcd9e46c808eb5f1f4aa9eae9857335b83ea7d11cae8d3a807d1fe53c23aae0419551babfda5e26c08c91680050c15982f0be4768405b111d950826c5cc2a460783a3553b019ad010001	\\x3a01b4e236ca08bdce3b1774460a9d46a1e73fb404759c0c3bc22c142bf835063aaff6ddaaa5b09f27b005d8d8742edc7d021e0285005320d66b8ba1f2c9a401	1645006956000000	1645611756000000	1708683756000000	1803291756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xb85a5a4a279a0e692fff1a858141e8f7b464001ab53c9fb457caa9e031e65424a678f060e422fd989bf19a1b8b45a4d8b5c18ae093d8e9eab22a01e2d1021939	1	0	\\x000000010000000000800003ce5f3561cfba99c90590e5baff3a326ced52b30a2b088a596b2af14bdcd3228fb60e1f4a07c3ae7ffac4053f14d91882b658798fb2e950b43950e5261ac44428b4ceaebcb6df81018d890454d8b3e2af3d50483f74ab8943897ec574e9c7d617a5d6315f412ed14f4883ae1cf961d43fec2e98a3ae4672d25a1a5c2c45339591010001	\\x51553b639ffe2711ec9b2f86cd3a9a77f8353a3ef8dda62ead1569b82c8ec6c6f9c6c52486a4ed8bc59eca9902b3a81650e58122e0cadedf375c25f928ecce08	1638961956000000	1639566756000000	1702638756000000	1797246756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xbcfe3012775a5aa4e5bbd5315f596a5f098497130668d5cc23a7d0aa714f9740a1c7a61339bae8b9c64832954ef39edc0f86e4b3d90641f9389f1b63cabfed75	1	0	\\x000000010000000000800003d6d5e3f1f66a7b62baebb5e1f1679ea414609dd2a0d9b198f0828a49869ae1b198b4bc30aa830d42101ca652be74323db78d5e0942bf42587e152453f22ab9f08e0237ce596257dbcf469e7edafc56a837ef1368ea8e81ba1630d6b4e7583551f0116398877deac6f0fca96d6aefec39d6f68d91b9f92fbdda940273eb8a55f7010001	\\x19d329e0122bdc753adc5cb37a1a07d41d410df273d05606e13ca363090407a50c1b884c29c2921e2ad134d4780cb7933b6c3c8e6d02fd62c1c863353bb48b09	1661328456000000	1661933256000000	1725005256000000	1819613256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xbcf6653b7b54afe24506fef48e99922028bd4551b7dca2208e4e8b1574fadd40177a86ad11193af047c01bba42f28ec4676a3ea67812cf65f92a2f812920ce3d	1	0	\\x000000010000000000800003b1ae22bf600b5995419ef4f2832ee26a80e9cd14b384c0cf8b76b46d0b2723b5257b2e2b799fe4799e45bcbd7c9034db9dc8a7c8f60af929601ebc698d06b5e64ada5e1bcbc7a995d89d12942076534d394403bdaf95e67889981dcd9d3c041a53e61723602ae44c7ab0484e9d588494d35e0e31fd9d866d311c9c666abdb751010001	\\xb1591617328c152efc74032aa3742c4e3212d32474aa731746a1cbb9ccd93064749412e0a5c12450e2a90b658769604f75b0cac7ca57692811fdc7b1db70f608	1641984456000000	1642589256000000	1705661256000000	1800269256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xc1b6aab0f1af7cf75c888181a2d55791d920546df6fb17c95697c44a58642e53efd6cd2675f7a9592bc99088a360385b4e261f58c7365111a7390073bbb8dfb9	1	0	\\x000000010000000000800003c47e5d9c033c9e77b9ed0276166735f52d4a6b70fbf66752a23523d15d756f9bc9797b73d39655639942075b4ef3453d24a7e4c6915d595bd8e620499d5c94d319d7623278df0db499c25cbae48cfce97804d6c8041568662858625d6c4f73a44bdf35f04bed0a8114474c75dda033cdfdad6286082c56df477b8fecefa77e71010001	\\x095801f6f9ccfc6d8cc95ae911f77798e437efa3c72362219ed7b4a20a32aac5fe372aeacc7b553af6e15a04fb6ea4059eb02f2aea77e992c834ca0b93342801	1658305956000000	1658910756000000	1721982756000000	1816590756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xc3e691bc1f7db31694fb2a67825b53850af2ef42b52f95f689c1c7d20311b74d0de1898a3707742feefed7f54a1256393007271b7237a668213f69584cfb8ea1	1	0	\\x000000010000000000800003a8c6150aeca6a14b3e5688bc4251813d7523ddaf3462d2051308fb09a3c02829c04b5fa86e87b665b419280140bd26def55e0226fd09f19cb179371a4b5318adbb7575b3fe7071568e9a0a1ba1dc57f5d78754394adddab2b51f687b7e112e64ea89d3d235a76d6b187517b880cccda336740c0440679e22fb2e2bc0fa1da1df010001	\\x09ce69abd0af5964787ed9bd0e140c52328727ba5129406bb958aae73f0ecc8759f0136aeecd38f9747a6f16f6e6dee56e817cef98e79c32ef33a33ad17ee001	1642588956000000	1643193756000000	1706265756000000	1800873756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
300	\\xc7dafa6659f54d93f153476e68b6162d45a58dd3cf42cc34cdc47a3bfa015f49b01ae8fdf861384cebbc3f41c8b1ebffa358481189944e77c061d298a11d3027	1	0	\\x000000010000000000800003dd3c28fb57e9fd22b4d77858982ad9ce389e76db136202cf825bce73b7ffef1346da4f9e35c4e5aff526210b65ec5c63f7861d91a9432c025c3512d4f3ec53d5560ee14cecbff5c22b212966a68113f4da991e722ae4e9dd4583e201436d413808bd24566ad4bfdca159d24b6a5a62c2f4b1e26d7c5eac3e8c4e69127a602a65010001	\\x2acf4000927b8f98ce968ab15467a7d3a2a2d09e9848399cfc0a2bf0b64e04174aa099cbfffea3107e7ddf5a1d08830e6531e2ba74e7eadeebb611d382af3404	1664350956000000	1664955756000000	1728027756000000	1822635756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xc7724c3421d196c101da080bad47a2eeb5934cc2479d2171ab148448a6baae933d4741156c87ced3395aac168d0e084500c5b0363f7247ed20d34db765bf3511	1	0	\\x0000000100000000008000039842836fa25e0b76c6656be58a5569b31d2e732108d7f4047a15d67cb02fa4cc4c29a8dc480858547a451df4f21de2ecd3a7ac9197889732899f73a346a5a773d7e7f2445b306a94cb7d1664316f7559f7d8e4258adc0dd94f936f2ac6bcbc571312bb97615c7da05bc7c665407ce0e3e623c762989ada782fb7ebb0cbf4f1e3010001	\\x29e476ec2aeea121272769bb83520d087b915cea3d398510f7be4f475034a2500086f5222231741cb75c1dc32c2ae78c0ce69af8da806e9780f559070814530e	1646820456000000	1647425256000000	1710497256000000	1805105256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xc89e730a960ad1b7f6c5856949d2c2775126a70b88d004d7957e7ee51343b19217a1d1f56ea08b285dfb8ba5c2124219aa6d38fa22976d72c0dd6493c9fa33ec	1	0	\\x000000010000000000800003edf65b368705bba18736ae445470265b75ea5722e27fb4c37eaff2a9648806a3b41d4f6e50d761914bb914aeb29ac243b92db3bbb8d4f3b563767ee86f0b2538bb25304fcb71e23d240283fb79ac2a00108bf1a906b53f0c1b694953ac279488cf64060b59395b2c104c2eea73770789f8a58dd0155c576922538dab11f61817010001	\\x78d52ac5a542076f78dc5942c0f96a717afb493fb2510472ec181e4b2dc9d9f660b6024146f451b2be6f80083bb3c722c464738fa7518c1c83d0803e5f17f301	1642588956000000	1643193756000000	1706265756000000	1800873756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
303	\\xcb8e9e36729732b9af9c3bcf60684e657c773a4f6d8c29cf6f129fb6a57e51cb0c00c1ec5d79847cb05f23cd5246c22193c15f63627be0109547dd3ad586d14a	1	0	\\x000000010000000000800003d4b2cb2eede566b82de958e468f7b5a01102ed43eae74f4725647b216836436d32f71e183431b3268e7a1a111b18d9b1187d086a520447aac9aa66064ab256731908316ffc1b59930d9b89c244d3521801a521155c9690961d5d36ddf4aa2b163123f1bc955f309034af054a514792df5daad7287812f980b5be1a4d339e8315010001	\\xad7dfea831ce9c2d9357b18305d2b7c4a5893d349ad35fdbb31a8c9d86c030bcae0da84ebd9249e429cc5b3fff58ca2304136d77387ef8ad7b8746072c37900c	1638961956000000	1639566756000000	1702638756000000	1797246756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xccbe1a84bac8683f5018526027778c808e3e8892b0a198adc9eaff1b5c8273034f8c2b51d11ae4918bf4addacaeec751a1aa6b86811c9859db83c7564fcedac8	1	0	\\x000000010000000000800003ea3c36aa992a4012c03af033bd5c2a482931e5c840cc82f497ca169e301af1150ec08fe896a5b0edd18c174ce34ea6cdd390f5393704652e4f7009011815ca4ed5fa070f716410c82078955da0a771e060fe4eb7def9bd56452dd0d240f0ce33a8d7f4b1f98f192d2b150d5a033d24f5b8225552b292938d056f3c5a58cb4627010001	\\xd7ab46e475137b05de8019c93649c3c8c064a0c0cafabe3336da8187d0e93b1be48b90d1f0889d07b0c214bef5c1b0931b51d1f73d0151aadf1fb7c48f4b7004	1638961956000000	1639566756000000	1702638756000000	1797246756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xd0bae13fc3fe239a8f67ac83c2086974f98217f74fb9cd33919e9127d3491d8a476e8747a426a50b9f07efc1964c2dd01ed12c4198146f72be04e1848e4a995f	1	0	\\x000000010000000000800003ac662cf1e0653c81db1ae261eacae62543fe485b234df7ad7b8d49b07a3b6d6329dceba5a546820da958de70cb68046d44d517ebadb0f2c735f2580709f8cf44e974fd4afa7c72e680332c0c45e0bb6392156dcc58e9c9fada360576ac7d4b87bc8f35d7e17ce486fab7e953931ada222e24f4e8d17d9e52f8ad70cfed8bd611010001	\\x9a6c9c448c02652123d419b1227111a467f87796f76080624d2125cfe42f4e2bba7273a28e1480e17b97ad7834efc6bd628eb3feae27a3e131bc5f70f2cbfc0d	1650447456000000	1651052256000000	1714124256000000	1808732256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xd2820f7ffaf7620d2659d37ff1e5528cbcd717be97578948ec6d9b40141d9b221bdc515b4e73e18985abc2b433576b9790fde4d80db6f24c8c96a42fc8ca7590	1	0	\\x000000010000000000800003eb1e77ee07752a61d22f6073d653a661464d183d6f4347c6230879deefadcc3bea27017ba90327a68f434b9d9fdc3807e9c88f2d00fe225a929f25bc22814983f339a013e8d820e04f3c7ddab3b222694ba7f1f3a27f276b90979a4e32f665402c28b94465408ef7d7f1037797ba3cac2e58f6cb37a634e3b60bdbf0b3415dbf010001	\\x094c0ead29a56cc51d92cf7a438bccb71ec3f273d2794ba28215eacc17979b0e39019229d46de324f27d180d7e8b7f504b7325ae9e0d2d712d5337835e9a2103	1643797956000000	1644402756000000	1707474756000000	1802082756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xd906309eae3e52cb599445875b6a3dfb05335cd49ef17f2e65e791dbb0d678cf23e72d1e2a18b6afa036837225f8a072b0cd8508fd0ab4223e1f24d80102dd2a	1	0	\\x000000010000000000800003d82108a1867664d80520ca3323faf784ed44ddb669a73b2c53ba25aeaaae7e3728c959e235279d467a4544974fad8ca7c6ec3c88db40c607196564e05491e67b8bc8da9dd919ab169cd7cf7654d074cdec30858086abaf11e51a9a93b43b0e6da34fce1a1dfd88c3d2cf06d177e1211b6b36631281fe3d402ad03e3518dc0163010001	\\x15bc69ce617f0ed307f036f25dd493fb8d331f2128e176e9e8a08750b671df82ac181261fb9ff2be0647a28b612d3ce70d3c0fcf8c99206ba9116b081e19400c	1652260956000000	1652865756000000	1715937756000000	1810545756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xda7abcc0d68ec2a617d255972cb0f35954ac0e599e83154d3a344a82d17cd8568d34517f8c26d5a4f4a35fa8997c576fb983ff1f4b39e997061de1a76c70f393	1	0	\\x000000010000000000800003eeadfa3239bb2d226d71b0b94dfd9b4ce0aeb798c5d8ff6e229f8ac35c323f3f2ad1f4e2249a15cbd0dccfdcc8ca2c13b3059296dd9ac44b51f10222d222f2088dd119557469e395044aad72c7501597676e7c057e12fe5f02c9cfbcc0b159f6bf95ab7064072f4ab110705ce2779f5c039c7e5539c8a1f56265f2ea95bfb3d1010001	\\x77e7bb954177feb6854237d8ba1dbd4c816ecca47fcc42b0ad0727c08b90babe340742739c30e5a1e6e630a6a818f6dfde9a6cb1e197a8cea85a2d9426d3c10b	1661932956000000	1662537756000000	1725609756000000	1820217756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xdd925382d629ca5494f57ad6b116aae77b787b27959638950fa2d87925bcc1bf363f6e010109b824cae5bdfced1608b61dad8b618e2aa19458fc23cb19e3d260	1	0	\\x000000010000000000800003df339eb39ea805460f96881e1a7a40264899b8787ff060c8ced52e492575ffd5105ea7e5531a52519173885ec016e410f8f066746ea45163931e18e030cb134a84139a287d848b498218e76e9e8c847c35cfb7ae239ccae2a3a54d3b7541d29fd7fe6766f8c73a4d452281e46322bbd5462d5935801296c1946f793abe2dffe1010001	\\xb7167380fd19b4dff04e01f65d200c00e89b2bc2d83d2bc726db338a247f2acc164e085e28605afb35affe8125664ed23de5a90796d3c4543d154bff72f98201	1664350956000000	1664955756000000	1728027756000000	1822635756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xdd6a5d26096fb6a779a298035df017d03ebc53e01d8b6ab9095739c3cb21c7ef8dc225267d839c7b43c1c948fb0b11bc3005cb7ce5b248ffb9a1a7f9725f57c8	1	0	\\x000000010000000000800003eca8dde9e4c950cfb9336dd6123c83afb5d3939539d9b43c0afba42a9b4d99dc6e94d0d4540992babd9acbebaff14607005616bff118a29a72aac96cdfd68762b22773498470861e631055945c744592c21d7e99d347c24e8c8ff175698afc4fc5bab0f1aa8180c57124e241b9120cfd7aef3b7ef849943aa667fc5ea2ad7eff010001	\\x73c46085a4fd1d63da8b6efdf32d786ae05bbe627b21895cbefbbc5251c2d67023dc57a9697e0628a9ac0008d616d8d66ae0f836fcb525dfbd5cd6e77999a40b	1666164456000000	1666769256000000	1729841256000000	1824449256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xdd3aae1f9e7b8a14205e16adc5672d2e249cc5c3231b9dfa4a2fbe3af993dbfc8e699a21ef1be57ada4b6d595da280769848e48ca019ccf06c3303e50b388586	1	0	\\x000000010000000000800003ac96a0556c2693e2ac32838def6f8c26731bf24a128c3a06ad9102a186a4ef56c63b7f97507bdefd11109755d6c67b7a5f3085dadb1b952a4bdb7eb09ae21995051e86be967715be4c6a618628083862369af1f14fdddf3a36d18cb3fc4f4ab2b8b32582f5604b6af12cd7aaf1435b996639376a5b087c7f6ed5e384e542a4c3010001	\\x21b456bdf2516d3073020af8e0cb2a4310900940479df9dff9178e0024e5380b7cce62525568c26970c64a3488db47a72df67570374a2bf95ec2bdf9e756db0a	1660723956000000	1661328756000000	1724400756000000	1819008756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xe11e0b75072c996578a2be339700e24555b85132bef8f55355b27309ac67069be4e44afb6f4354f9829b280843033be3c197ee7a0ecb5cf6fe6182f0d452e005	1	0	\\x000000010000000000800003b0371063999f067ddde99ac12a0225ee53ea1fc69a401627b4d20c48d3499f9d11969c7b1c81d59ddbfc83b439d751d59d6c05f97ae0302a08e98a4d96d77068e2f6f1b8e86c8b455177d9d14b4d391075abb8d2024c448411f91c336586163f5e1ed48151efb2cc86fb217514ef74f5d13b5c6b71528ba3bc08a31d6b5df7ab010001	\\x718bf33d08ca26d9e59482f6124bf14109ebfa1ce9a7971c8b6fb5620752dff8cf67b4a8d823dddbf8c43ca66ad3d5b63fbb4b08c5ff24ea0980f27697bfec0e	1641379956000000	1641984756000000	1705056756000000	1799664756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\xe26a526b187324f3dd0b540de5a668f6ed8e49496e6d192a37dd7b4f56fbc1dff5f64b483b2243efaaf7cb82b9f52ee0e173cdecf074117baa3ea744ef8eb704	1	0	\\x000000010000000000800003d1e0ec7d8bd46c24ef6d55214282e67edc99d04b2bf013e71ffc47f8d2ba94ebbb5162c6cc62096f2935acf95d9854722df06990148f98d0782f56ccb28541a937bc31ccabe45325fe1350d40d73ea14e4871eebc8507155383fdf100c906095d1d14a8bba76d4b483d8630129252413af064cfc4bbe9da2a8a2b67e51c59403010001	\\x51e021bffd282cfce0aa7eca3115e18af1930a86a16f6baf9fa0c743f5a98bff763d0c1cf504e8832063510203b27a9b6ddd8665bb6768da668aa9595e90640e	1659514956000000	1660119756000000	1723191756000000	1817799756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xe2ae4e22728aade9dad20c66ca97dc36a17c5abe47bea2220d91e43532e63fb971d3bf1bbdb418a10f0b7c85be4592de0394f632cd849c4012334531de78434a	1	0	\\x000000010000000000800003e3422ecd6db852f29d4de54b0633eae48da66edc1a04964dc27d391f68719e0d393649ad252c5fed7ec5409abb5c3be28f2479634b19d3d25061fd4545bfef4541cb9f3bc569eb43821577f5dab0f460353215f5157133ddf9ffa3977d1706b999bde157e7dcab9706379732baf625533e3de5e97e136be63113dde982b6b6e9010001	\\x5cae47b0dbf5da58318b302fceb1ee25f714351f870d078f42ded7e16b7ff1ae9f93fab9824c4ea2f2dff47b8d0dad717f7a6561fbad16ac401637e3ac09b00b	1651051956000000	1651656756000000	1714728756000000	1809336756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xe6aa66a651434ddc013f62f85cdf7d56c45fc0966eb09e42a5ded2ab171dc3db2f46dcdc344fefd031f04926c8806465522b109108d9e8cf0ad8e11577f4849e	1	0	\\x000000010000000000800003986e7ef7a9410448cd26cbc3c0fa6cc8f0b7980733c91187cf18e1798171147512c9ef34bc459de1ef84f0f5018e26e2f91c4dbabbf2a19fb68e7b8875b11ae0bec35673ed35b961699d00cb60ac1be40e7062a36af006d79cb75107d68ca17bb04b1c5c6a2df85882130d4ce9a30cf5a74034bcd8cac616d3c95164ada47911010001	\\xa7ab2b39e670c4d7780e49c2a47874b4213bdb1f4faeb10c89369897ec6e57e80d2b73067a89eea77a8a995969515946aa8d2728254f880f4c0d71ce9a24f303	1648029456000000	1648634256000000	1711706256000000	1806314256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xe652a5284eeeadb3135c053d1913a4100f1e985a54d3cb6acc6e8d8cf2e47d83d8ec58f475949b6983693038f59ff51012236a1195ac01f4aed4ab05ebf1ba38	1	0	\\x000000010000000000800003dc416a81ef4c8342e62aab2563243817e492c78df10474bf44fb7c365d44ae095e454c489a814e6e656014c1dd7b6357e3d084a37cb32c7d1b1da67a2dbe0eb9fed47eac21ab4acdc32c04976cbc873151bfd91ec97d4d988f7b581c1553158bbd2eedd60a5a041f983a31153d655999ccac9a6fe5a167b055c5a26819b372bf010001	\\x5c394da2ccc8a7b4974f5ea317e9897d069dc6313b02e9990b1cb43a9c0e13b8f755b03eb51decbdc05d4a8407a99128158cbe6000183916a20fda4681718d04	1645006956000000	1645611756000000	1708683756000000	1803291756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xe6e29be6abfd8166dd87dc207379a50a91c48e51866c45cb0008361192aa1a127f390dfebe21ea530cf22d34653440adc6623039156c187dd771ddd513959c79	1	0	\\x000000010000000000800003e86d41cd4c156e178ccd19413a89bb8e5de73f21dde418f06039a46c27c8a56a66fde2bbb9e6b9fe234d536584a1c4796b184174209102afd9367740e13b87903d7e74f631877742ba8edce62142ec14e807c55ba09bff0cb7e173020e2a84d6633012dc439328fdc284dc69f1669f104793b77a217f7420926c54d99f48bd99010001	\\x446b24c3850de357cf0987eec4a880048ff5bab3838abfc78274a5f238f87329da4c3f4c2512f34d537cad96dc55b0f8e0047b8e1f5dc71a20cffab349e25d0f	1655887956000000	1656492756000000	1719564756000000	1814172756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
318	\\xe74a0b724eafbd0d448a1f77afb40b5502f34c071b27211a13e9e92763873d170b59771cb1f054e35d1e92b679e99dc516064dc6b48958855e86a79c5d43900b	1	0	\\x000000010000000000800003c1309ff5265b85027b9be6ff3dcd6166fd6dfe176338ef69e7f7aabafe13c076b5e2807a54e90f196e711c0f8af53d3c365dc584efd9f0a30802d6e6665e3178e31149cf91207239d233702a1017762fbd8455619433453a4018e8de6211ec3145e3972880222af49c60c7e559e56b48a22f8728c3403b6f5267331444110a5f010001	\\xb0c08b5a16917de71eb2016182cd1a985c2f457d4bb0a4aa883855db6c17bbc836d887a700e7d65c90de2396a3267d2e222eb77300ba129b186d7fde1a803a03	1648633956000000	1649238756000000	1712310756000000	1806918756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\xe736bbf705657c5ac3008d33ff4e6dc2bcc227de6507c1d051f8e467b3ed78b8cd27c524caae6fe8e93d05ce5f817128c5f05b0438b01a721b69dec8a11f8bf8	1	0	\\x000000010000000000800003982a23b8399df5c797c996636129bfb7df137a4e97fbcb779cd409373bb3cc4a57b6b07edecb6954b09ad1c5809659ce37a4afa02e15a60881766210c24742a87817bff65b7c9748a3e9b632c7fb7f7011c98504951c2d4de6c62f25715bded727cc2e5c1d57b1636850df83d32d40ab2c14c1fee8b153d25c1f2d8f6a8119f3010001	\\x2ec8665fbacf566c3171b661b338f6def60e519821f8297ba84f5d743d3d5c4868a86e77b1ccdc2f896cf020a98ee289164421d91b7c649ea330ff098b46e508	1668582456000000	1669187256000000	1732259256000000	1826867256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xea5666001a28784f8bea75a4399c1dafccc10c23fd375aa67987e94d6fa7ae202fae1adbc8fb10c99edd4d54b5f47703b179fedd849249c675dfdafa8adaa9ce	1	0	\\x000000010000000000800003e2774586f7f8d5fe24ad52ff45c7e6c0c8c8ea6897187c15dd1e50f5583b358bc06e1bf74a12484ab84a903d150fc8fceda1737544d2a25dff757bfc5955008c35d5ebe500df2e4a90586da12775363962166366a0f06ffd1d0a7ed0bc1485f2c909175eebafa63a08c34ff3d01acb1930c2a2130453e1c24245dc9f9793730b010001	\\x2478dd3e32ff5a6440ef9f9dbd5a7d7d225ecee05cfce881062ef179e3d22976f3a947e4b117a85d7e81404531163572d478352de293c181cd1f7eebb450bd0c	1652260956000000	1652865756000000	1715937756000000	1810545756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\xec9e38e6e682b747fc63089dc00fd678276d30742669335cbe60431ba6649ab447e2f6b11e1230a7410fd38321fbbc0f64092193cd48fa6cdfcf63aeee5fe127	1	0	\\x000000010000000000800003ce9e789f7323d0d4b0b4ed0124fc67406124d44f4c3dc13bc7214471ce70c99b99fdc62cd2ce1c14664c3e9d6596853c2517d102c25767d86d7b102bafb2d459d4ee7006dadaf206a5cce1214072afd43fc5276db54e42cc21864a5f1dfe5af4143e061f0889f5889133892982e155911ffa55e5c878388f3037660c37c8dd37010001	\\x995d0de327acbd364c8cfd9bef1d8811b6446606ab2314699baf92cc42f3d324f3f94c3a2926ee437f789088f83d81c7ff7e877e9744f91679c4d67055f5d606	1664350956000000	1664955756000000	1728027756000000	1822635756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xedd2c5c7d2d9c023aa146a65038f74a64d144bc5e4bb1db8ffa0aa28e0d6c2b95acf9761a63760ebb3d6c90528e0bfa7d8ba17ac1218f5d35f55ec6065331683	1	0	\\x000000010000000000800003cb15c9ddac636e55f8b160449a55f17f421fb3fac083671cea0371358493a7a47b7ca6f82419a21aeebe5a5086f13d23823b152ef6743937689a7dab05093ef66ed8a66cb331524952415ded393c1453ba69a672757917eb3a9794f6a6a51fb2c68031bd938904b8f2a7f09712e2d113de23c7d828e05cac06f8b643937d7df3010001	\\xf47a1ee6399eecf801134993e8da43bb39b2804682e6af447a9c76e7f451933ff74ea561ad31aad5ebcbaa6c85b6e0f3a6d7e3a550b680d8be91cb1238044c06	1646820456000000	1647425256000000	1710497256000000	1805105256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\xf5320dca2a6cf2022b077a0498fb8046731ba58af66ef5c8f08f4208ff83dbdd71b3f4b67dfda55d9639f03124d3e1598ecc6d1a28c2847e6cc5f460ddae5674	1	0	\\x000000010000000000800003e601f6279ce04b450425f1952351b7bb2eb7a61708e78e5efb74e91e91d9e3ce7f96856882c444f186c57a3bb2ac2f514d96706d581530daed72fa33618c955685c11fbfd1adeaedff17ca6bc1f50293c3ff1f86fcfa0c7ee51c323e2c3b0fc34456e22bd80628cd4a65f0983281198dc329cc48b083ae13e83d43d9e1e91c39010001	\\x5958ba1ff4d30b75d0a6514286ea55f202e6b73bb2451d6a69f7a9543a688cfea4be1afe8c1e7890ebcde599fdf08660ddd43ee133381e19fb78797232966903	1655887956000000	1656492756000000	1719564756000000	1814172756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\xf686fd63db47d1d1ceeda7eb69809de7b670bd886716257221730d91180c33c400296c8349f20da3ee3a1457fe251b4750e660cc810b10b559f01d1489bd421f	1	0	\\x000000010000000000800003c5760a0095debbed08a91290d504be5ae1c96f6496716530fb08c97c601b80c5eed319de66a4306bc8dc34969c196e99f0c4b8943b5f7cac0a31eded3649b1d03b7a175d92d020aacfeda167092f5c9cf835d443f2a3eb58a0212670d1ab4a627eed64ea029fc793c908ddbc92c22565ed74e675a6c0bc4f337c62dd1f78b7cb010001	\\xf7607497cb4f669667f7ee8eb6a95daeba349e1e03e809b5241cd2ddd1f72c80a081936458f419f573eec71c37c7713eba389e5ce9dc166d49274f3c1d0efe0f	1640775456000000	1641380256000000	1704452256000000	1799060256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xf68e7f4e5f08259769accf9241bb1fa1301e833b63af74e52c7e7565ccbdcb06d60135ff1dcf8e88a3fa9b7678fee318cd26bfa3a5da36ee52254a8d8e4c2f7a	1	0	\\x000000010000000000800003cb29068b50e2295e1389cbb76a63163e23f7e7101f5e69aebf276a0db23c1fa638e1e75c10af046f8a1785cd37ffb1ac8cb1560c818e6008bfdc688fbb83f7fa9765702723c190caa4f1ecb7eccdb67f05b90184ec757f73804ce6e00bda1d20638e5475c1a714604954e6fa1cc63c1b904ff1f1303ba8379d313508251579e7010001	\\x70ed43689b31a76dbe0a5465d608bffa22b98b6358a4b1f35305ae60c67381b6468e453b1890f52db7d383bd0bb69430a34be12fe94123df8bd15bfbd4195d00	1651051956000000	1651656756000000	1714728756000000	1809336756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\xf912ac416c58d652da12981d9cae0ad46a6fcd6a1222d73838d2ecd83f63a71816746f202381bb92af0743acca1795c044f6431bb94592b2996e4de0db35a71e	1	0	\\x000000010000000000800003c5c9c693aa576532a87e0546ebf182684ef33dc4044be7766d90ac40fe4152129ef5bb3857796439e2f24d4d04154c4fc269fbe792b11e1056a73f4c456fe6c0b7d3407a4b936ba6543e30d3ac6bfe63b5b50c421c2beeecfbef76bda03c853348219bec11811ebfeb61d0e163471c1c34d39ae3f86a2098aa9219dc9d9fb5a1010001	\\xd102523f972acb37a06a36c91a7e9ba16ba5b443ec52955f6d1f1a37ce0508ab89e8dae220795f8ed219b2f2981c17037d771983b58321ff1d4632a07e0afc09	1651051956000000	1651656756000000	1714728756000000	1809336756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\xfa2e65a3afbce984f203d968d7cbbb0469cd954fb1ef9232feec3c7f5aab21b498a7a465f9d2363015711d20440369572b8efbb93e0292ff4b671cf2dd434411	1	0	\\x000000010000000000800003aaffdfff0b45e9da4b369a062b69e997bc88524e0b142946a642fcbbe51e7f227a006bb267208d56ff20e22d810d48eebe255278ee69995a44e94654a038f0dfe3f168a14296d385885d84b52ea04231365d2ca741fe84e451803de136c87d0e24fdd761b1e30194bd7fc1b89ce46d36f856d4be1fcd2b380496d2ae3a4ef8b9010001	\\x4ece7cc5d803e99d7f8894eced1176ea39cd573d4bb8e9c4fea7433e06ae3ed3b06ca0e33b559dbed7950ba3975cb6218b00415685934b38a828bff2d73d5e0f	1638961956000000	1639566756000000	1702638756000000	1797246756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xfaf644cd1fa591a1414f8c72784947448d62bbbb2e135fe8395f62a3fee6299db9b30a90152e82b275f1446bfe287ed3d79a1300bf32c19ac9164d586c4bf3c4	1	0	\\x000000010000000000800003b0054ee6a35b13ae57458f81c64c86897a4daf16cf16c0fa29dace9b36a38d5ed5af0eb6d505920f137cfde5e28e735b0e3776d6db2a31ebd2689001d1375ce40631052b93caad385d5b4c0e6a89b7e7054a054132119f1822c9b3b8b132d348af44b2505398975f039eb1272523132907ba5e0e92222b3cfdeabfb0f19d0c3b010001	\\x2b4f604263a21fb7ac47869c2f090513c4f4452bd3edb320eb3060f8949ea688da2742002184751b795409cff4cfa9c76a935039c1894a6cecb2b2f12a99b804	1648633956000000	1649238756000000	1712310756000000	1806918756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\xffb6eb1dc83b78ccf2a0ff94f1c9a9adb6c347d26c48a7baa793bec32c59f9dfc137024d846fc8e986d06149065aca49c9ff28897b922cc5a832cc1df8f70b98	1	0	\\x000000010000000000800003c96486e1e43f34cbe5ade2881b036ecb83d0d5b7121b25571e6b582017a7b09c23b7fb6503d259a4e636bc972030d38490755f15b64521ae41f7bdf1731ed5473f9213c7532e91ad10dcc73d4b1acdbf6039223f9856c872751d19334e59305cd3ca3e6e20ed053b3934f839f3a6929227b404d7276298b8f8e12603b1fa2219010001	\\x8ded379c56aed985d4b329a5b40c6782006720e840acfc371ac1f829a704ac2efa4c1497409e996d557d1eda06533b4a5d2c13a83a4c2133ffc5a6b60a887b00	1668582456000000	1669187256000000	1732259256000000	1826867256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x0003ca578e36701c9be2743fd09e2d5a1a0b25f1ee131e537054d3a685236e9b1efb9f85383e31496fb14107f1f5062ffea3de8aac8e91f3aed1e5d8484bb481	1	0	\\x00000001000000000080000399ddfeac29a3c8c4e22d6a1d7edc1cba80d9e1ff29b193dcf0711e43388130d94b04968432a7a8be3e9a136239efa8d35e0f500ae2e5a8e6d0476c893395239ce036dc717bd1f4c4568ae74a05495d026a978b1641b0514b9a2bcd648cfcec78dce2fd5e79c5cfe7c7acfa8676c0ed45d349e5a89436f7c9e1b6cc94e48a0701010001	\\x55c4628d6588a0937f2ed42cc5a82bb9d4f3ec4a25020d152f029c1752242a68a71dbc061be99e04e9cd408fcf407abf506db6e103fefb0af48ec02ebdc53700	1660723956000000	1661328756000000	1724400756000000	1819008756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x07636a3c765aad1f9788ecf41797cf9ba84b6828771ef15b4b284edf39a3a484a175debcfb7939473c86d1a8b8348fc1511e8ce15b0fec7fb65c22606b9941d5	1	0	\\x000000010000000000800003bee3a29a9ddc6aee75b027637d9fb64f32ebdc3aaa661f736e72c22879639a6e6c6a42c444b28658b5ca48ece3cfc577a894d8b1da84af98d4f30f6fc5dfcb7546443ef78261bb94c42ac1f9c9dc8f29a26bca95e85c1f83f66a1025ddfbb9733a3eef8bc32348c72139c3af4039e6773a0069b41a082a489477e8d098bf40f5010001	\\xe5b023afe72423e59de85672514fb6ba05ecd03ed987fad57984c72a8df268f29cfe4dce08d28bc8f698d5523c3ee0db0d9a2bf0056be3df0bc0a0fef0751b0c	1660119456000000	1660724256000000	1723796256000000	1818404256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
332	\\x09f378145e57b842b259d6d9d07ecd2513687795dc634544bbf576e08da0d349fce35c2e976174580b5302b1c2df8222a5ff30f7eee70e2f0e8e815133652d09	1	0	\\x000000010000000000800003a00615674cd9f5f127de54b6e5a821627ef30bd06559c11c710c7d13609578245a6e9dbe7691bb7c798324859b03ad57bdcaf08cbbeccc1cf50da98cab6cef30d7416d6e1c9ac8d47f56c3fac0217f0b3b41c49bd1ab713a57c485b314cd40391a8e2680e9582e5df998101185af328cf00abb5bdac42e85a77c10c2b5213d23010001	\\xd7ea0bc847280de85c086c7b2988c1ab9a7ca61499c6c810fac3ca09ecf5291b7379b3556476b25ee6fdd1b60aa7b08d2abaee682aaef6c32d4b63a9ac1f7500	1645611456000000	1646216256000000	1709288256000000	1803896256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x09d783cf7bb8a5247a085df92d7ee4bfab0c2174e33e23fa863d27a9e494275f51fd034cffd735aecd6491aef3134e24f60f6d00de8eec5cca7491a04c93bdb9	1	0	\\x000000010000000000800003c50a86fdae1b5998ee13569f6220beb6b5cb016895e0682067756d98632242954a534b93da96b0c1ca5c946e34258010922897cd91a521b0db3ae16ce0b6c7769b92e26114b20c70f2701088d4d3bd0673122265edb41036d0fa76ef4526454ed24ceba0b824faff94ed3956126f5df3fab349b1391cd850eb22051be660325b010001	\\x93a52d0ccc2483ce76123fac2cf955d6be1bc96707a4632e1ab1d166b2c46ec72d2df6c1f485864175579e65137085f68a34c400946a7e3a0b236d53426f0d05	1643193456000000	1643798256000000	1706870256000000	1801478256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x0cffcc384698127811e4acbadfb20c9afa5031ce79fd344f9a0fa05e9a2d7ed446f9724061acd7338f21cd19f0a6ddbeb0032a3b7ea58700daaea23eb5c3df13	1	0	\\x000000010000000000800003bd10fce2b5cb566dd5c00142136fbf7de6e24de5f92c05b7e686ce2ea513cb2e8a58a4a6659cd396298c63c1cd3595f243b3e1d16c56c50ee2c4094ecb0339e926e9367f2bec6a65d751e26f192eb717ce5ac75119512dbec347bc7fe502df5edf3daecb6688fb61995c2dc65adace526a537f52a21fb7a0bbbc668772af3661010001	\\x0c3e4dbe4ddd9f13be8b6ebf161f10d9871eef98acd3e43bfd6d80f27e0a4fb3142f03f3d491c180dab89a5eb2e960bcda9c48bf09dd1914927226584cb1310e	1640775456000000	1641380256000000	1704452256000000	1799060256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x10ff57254a0e71974b1aea582474c88f0f67173f9a759e1da6a7a210528a9fab749a6c630fd96fd769674629d2e3e142131f4c4b6f72ac373ce17cce9354c792	1	0	\\x000000010000000000800003c29f70a5f9a613afe278fe5a8d5995b2a57dd4543f5158a7478c7a7110b4186c2453dcef4f13d1dc601570e99a7d0da5b0e38ec0032feefcba491a302ed8d445fdfa28bbc35baabd709b8b207765bd57beeea01109fcc233a10b43512468339e45675755e9f8e9af9b7e2bdf6b35df3e1ba1774404bdba8156f20160d71784b1010001	\\x4610e4ed8991c5e0b2129a632a3c98940b3be87b6c97be749552d9897a66b639cfc6aa99278092c16b374c19ef5901e48b95ea926903173bfaf117db7d940608	1666164456000000	1666769256000000	1729841256000000	1824449256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x147bdce70b57761fb81d085c5085dd3a3034c32bd55e35f3034ec2c5bc8d390ef0268e7d1fca3a419586d86bed8f47f731722e1274ed6cd5c85ee1b4e67036b7	1	0	\\x000000010000000000800003a33159c816eb7022c0d9ee4c70df5f2dd28aa3ed349a043368081ea03812be032dd8eb2664ab16863f2100059e2c0df4d19ccf653de0cfe1ad8095c0ea35ffc35b9aa4ecbf83a340f4fa0c0ec1c9d6f087fcd730714260da6fb0c79bb8d969912af97439d9da2ae8df3cdbaed45b49e30b714c8e92bdb1fa6977d4d8b8e07be3010001	\\xa18447ea8931bc1dfd334d83d7cfa4c5cfac8f0eb0f331596def24ebd8ec60834f7080f515ef0641fda2a975750266ba46d97adb4b1bd2598ce0fda0033fa202	1651656456000000	1652261256000000	1715333256000000	1809941256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x161b79b645f31a8bc9dac79142388d042fcf61b6eebc358e63d3b12f3917cf2aba57876aa6e6cfcfa33896b7bbeb969106e8d9056b136d640e3e85c20aa28bbe	1	0	\\x000000010000000000800003b9e8db6ddb2f949be7be1dc31fa57bce9746f72e653f727e3dd3cda1634096f837d6951ed078883f59240812623a7dbf53a042425903c84df6d016681f68c32d80b8c2417921522b46e4290df2e7b3c758426f2c86b218b6e94bc556ba8fea4610f206409c30e4ce85d4bb0416206b214a0d5ff51b4b27974821df019d3b9345010001	\\x66ea9e5102357ea44d213d3547455ca51880830c3411a5e6b225d7525b47cbe815de6c69ede5bc2411e7686b1708d27778947a3c25557b2d5239fbcc804f3400	1663746456000000	1664351256000000	1727423256000000	1822031256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x175360cd0453eeca891d7c4df22ada734fc1472e0182c5e2ee9707cec8222f8da11299ada663d8e0dc640ef6d06a0ceaf67106f2cce67cedfec8f6733c14421f	1	0	\\x000000010000000000800003a190d4f86631fbf2d833c9db4ab196aebf9cba57d0c6982edc2e2e26d1bd5436e710a3db5f32adcaf25a74ee70200568bff7e117d73914ba778904c38edee5882c1666a4751382c332782bb986ef0a6c3a18cc1bfb948ed8fa02dff0072240f9e4a0de56503275de25f18237dc163e86697ce69936a5643cb7c72d1a3270178f010001	\\x39ed5f60218faacc9766802417f4e55b75c05dcf486a0e032ba62794403525edaa17b01fe6e4c8fc2e9f4d89866400d58b8b4d49a80c5858bc6f2b584ca73107	1640170956000000	1640775756000000	1703847756000000	1798455756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x18cb4ebfc12541051dc27eca3092d1fc21036f2c01cb20ef52cce03f6952d315ffca7fd3e8d128817752b8dd3350cece2393f78c349814258a5697fa6e858635	1	0	\\x000000010000000000800003b55a21a5224051ff7b9a8a2577512ddb242e5f87df2373996eb4a35b274ff66d28196a64215883cc07db43bbc7b7f9cc377860ee169cd6ac61b4c0d0983f7fa74710d7d8c8b03af6d16e181982a24e6b417ef916fc2b444361f1dea8ab6be33655dfa11cc4947afc16edd2497e1096b919e16fc53b47fa7b791bee26eb98ef23010001	\\xf5ae6df091271a2e312185f06faeb0e4a9cc995aafd5e346b2673d359801ed032b0ae8badbe7d95662db3a216e2018534455b45e65bfd6037131f12085893709	1646215956000000	1646820756000000	1709892756000000	1804500756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
340	\\x1c0b512b79fc95ffabd1db00035a0ddabd46a4ad2ce92040756f265dd0933957c3ab6745561815eb14fd7f58553d7ba16f7016c0da0a05afb7e2e266d28fa04d	1	0	\\x000000010000000000800003b81634492a523a84cb45290929facfcca23b20792ca60ac379c4157676afaec649230f80179cfe8cc2df015c7b3ac52396f44ce432eef6b9815e3a61435e1d1a7fd4569a26f61d53456749aa6fe512d2426f15afa44d8f736879321e4e0ef2f422100d963cdf5dab995b667f7218e1e38f396840ef5e9b3d1051fb04eb66cfa3010001	\\x930cc6f52b7027c8b27ba528f78e3d8e44f526c1e99373f00734de5cca1393a7eb4025ce2322b1f5622bacd3010a3c17757d0705985f2f94ea6070ad26b25009	1656492456000000	1657097256000000	1720169256000000	1814777256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x2627fd31f9b2cf26909046b009d895b503f19ae337be15096ac4acc9a400846c2ce741fadd0f08a49d638fb77e503df41a173967bcd2fb58daa46cbabbaa8f60	1	0	\\x000000010000000000800003f2d55fa300410fff1696e903228da71fdc77a66af3d8364cdece47d08d9ff2a13b0b081a3147c912b4d0a413989d397bf37f8162a337d7d29b4626568f5a75e9daace9687b77ecfcc9efad476c57b69d825dbfb3b363a35f21bcea335b122e55f63e491cd21e15d714c86d27277f893ff98545d6220736e0316e2748ea7b013d010001	\\x407d8f09e8c91cefe3bac40dda20799c322af93c8afb92b9fea9eff1ca7078f58a2d9527e8f37ceb23fd3d82e1a6033bf380e8c5e9650970581bb1731dee5e0b	1655283456000000	1655888256000000	1718960256000000	1813568256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x264389c06f917f15865fd12d075e37f9ef149963d1faf3fe058dccc0053b9f223f82b0760163fb61873dddf64d054407a81d11ab0835d1c79f40e05d2d25a525	1	0	\\x000000010000000000800003d2a84f3e0adf1eae0b5e80f66a822f3e2b2df31c5085852a244dd3fa6f5134abe046d6ae425d78df9c3f43f15212cc164d040d64bf3c723b6e5c50512cff07ba373242bcebc174eda9a0a3c3832ee2fe73c4ae7a66123c7f51b956af3ab4d363d925bfc86ce6bf8419c4410a84cdd617ab79b9c190f3bebb8e4a0ec1d1032047010001	\\x7161db3ac2224dbfa8c38b148df94fdd751cab95e8ac2ddeb54eb05ed5d7aea7463c5b7fd436cb7aca32f0a722ead07a59f42bf7c7f40a8af8c9d69c8a51e506	1652260956000000	1652865756000000	1715937756000000	1810545756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x2a9fe80f57e5c854f32cea7e2fbf9506f5b5cc8efedb297844639bca1b4830cacde328afeb7090e5a344e4a25638b43cd849bdedd1a39166537e581e67fdfc90	1	0	\\x000000010000000000800003ea6efb4b135526a4c15dcf298d669e16e35f8e3065e5d14d9aeaadd2b4ba81ad0bfb048238fcc77dc7a28f29b3a2084dbae438db1db0267194fc75f4c9e9890ac89fae4e99369d599c793badea6f434269351bdf9398bc45e3bca38822ae45a30e892e04c02e618ad07a69308c4b752e589e0c5f96e9bfb4fc12cb8d8861d50f010001	\\x833b48396612cd7f41e878d1a080e3ad3417eeacbd94eb8357ff82d8f14d6ed98c7643df011d81b99dfe9470a6e5f1642fec957b48a9e0eb27c38b6235759806	1649238456000000	1649843256000000	1712915256000000	1807523256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x2e13133d761ac3291febc15dd955a09f6bbd91b2e23098c7ee4e1b5d88f5ac75110daa6766b077a879919f439cb64d538ff54001b7a65d64c6609a0700bc1168	1	0	\\x000000010000000000800003d058924a53bddea1e119f53375679bbb6806b2352582dd54cac76ce20ef1c57e87021c35b3fda678a964d08de8dad0042974b23e6af954cd65dbdbc00b6912ffacea7a01e9bfd86a9acafccf14e13f596c3859971385202d7675814cf9e875a841eac04dcf21316269663049990cb6121ec5df963df2871aba08eb63735aeccd010001	\\x14dc85bfb27210af6a7ffc0bbeebdbcb8e8ea0b0b00514e66b1b9dc5aee936986c8fbecaae7b400d64ee15d74a02c1bea53382f36be06b3eaf6f9407a5751605	1646820456000000	1647425256000000	1710497256000000	1805105256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x34af07b7e62f8335531b5802a51672d3735245a18030d29e264d2fa291bde14f4b3aa28a96d260a9feda8dbd1b9d13d45472dfaa20432b2c8b3d2da7490a0147	1	0	\\x000000010000000000800003a119375f7a50bb6a5c2782b6933de26fa05378244d86d53216d34a99725a0c85d49e1e345b9c8f1f5c94f11ae4e0cb74c62e938f9dde96df2a25efb56a6ca41d0c1da602b34e951d386fcecd3314e779840281a06bc1149f02b622abbd23d7accda1135813725f0c04e716c1c43b5f1fc315b1da60847476690fffb2008a88e9010001	\\x4062ab66b8ee400d75bcaf223014a5f2f88aaaae18268d01660e34a9849abcf34c90e9d799cf7aabe4559f9d27989854b086ba383325bbd1f510ac5110b30d0c	1667977956000000	1668582756000000	1731654756000000	1826262756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x343b0b0b78ea92b8ac25e5ef7905ce40f485cf51c50cfbcd109b4e87a322a87a3c1d2d35dc6f328df673dc2d0a9923f088998d753a71fe54a4e33bad2eef5949	1	0	\\x000000010000000000800003b13abfe7de53f73a8fbecd48da083ab706ed07cfe976d2605dd30a57755e35c887585a7397c29a5c08b310035825a2f973494d8dc7f9fa1876fe996a7e9571ac3d3094296ca4f7d860501309ee041acd5cc30ad29306c1a11774412ed8e4c905b98bda00f51a089b953df49f5bccdc8f0cb91c181600fb04951e08cf2d72c21b010001	\\xa2cf630d933951a4c6f33b23beb38590e1588774f04e0ab16b9e353ac193fe64cd0c7375bbb4f853b95c95fbd7dc28e3fe450d7f53c1f0989af4ea64c0e2b704	1649238456000000	1649843256000000	1712915256000000	1807523256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x346b8f03ffdbbabd4cc991804f41742f25d0a997af7b18eb8242dbfa341e8211fcf1a8380eaab9a42065065a3f4834aeffc58962dbfbe715b35146c5cdb377bf	1	0	\\x000000010000000000800003c8fb02b37d15a2cd7b92058aaca962c1646e4e772edb452b294e2bfdb07b9f6bba4d9b12cda044a4295b43190ebd672e5cb3e3c8348afaeaa57a6bf404b71c05458a09ee4cfd7bd1ede5bd9f690f9b0639b127b4f9b13fab42e535b39223c933c8b11ae549f2001ee79928d2d25910c1c1f31a1083bbeda2d333c62793e04ca9010001	\\xe1ce3b41dbf93fbaf731e54fb1a43dc0ec671ae89c929725be0e22be1068f25fcc4aec7626c2609ad923b266794cd2fe8d66a63b6a732c5323ae779e4de58301	1667373456000000	1667978256000000	1731050256000000	1825658256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x36fbe23801f2fd323100306cc8210d3b03902d55dfd2e79a84280880c45bcccb8115289d79f70650de6a1d5cc71bbb650554da64c1a5c5b570dd92a1ce7f463c	1	0	\\x000000010000000000800003d6480b3c4ebcbe5bd8e19e634c99b44ac604b22489705cdde8ee0b5f88b4e583e016f71d1a868f53b7e737e4f41f2c4096e20f22b2bbe82f28ef6a9bba4eb01a7088e1d16ac24a1817979b915a4a3bb3c2681e137be28a48f0e032284d686c55a25ab8708e070094608ac389643fc9443581bc8c14c37ee43f47371202c065bb010001	\\x686921b3c6ea5929ccc31eea7e23e708c747cd81b9a6c3125cdbd0f5d0f56686f85289b3b2529710b0d25394157cdaabb48084ef9059d8249f1c566ee7ec4c00	1652865456000000	1653470256000000	1716542256000000	1811150256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x36179768e88251e2a381bb1c48fbcb1478ffc2023f2d9efb161c1f2c6fa817bf5bef91deb741a1b8ea962ac8f7705ffd543d8a9f00fffac11c8ab37411dc1a6b	1	0	\\x000000010000000000800003c0f5d871017138e98e440b5f42a82d737fbeabd1b818a3a92b25d08646d1eb4426cfafe1a25dc5b64cfe04850feb1f7795cae4cbe564dbb16b81208ea82ade2bb2a9a4d22de5efae6c46164643d613c9e55ac7816f24666c88426f9877d087cd21ef82bf19dc0a2a3f6bcd36b4410cd06078108fdc505e57c1d176d334962911010001	\\xf60b87965e33c5b378b52b89ddf4d156ac5ca69de447da6f4db28f5d0ab7925e94703ef53449d0391ad6f1ebeb41a194f519405ffa160e0fd0053ea6276d2a0d	1659514956000000	1660119756000000	1723191756000000	1817799756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3bd392dcfa0b0251ed5030387606d5bec151f9138870071e6c48a040b194b6495b147b7827039d02dcfe896a346d957c6f79ed7fc72514a5e105b0805bf82861	1	0	\\x0000000100000000008000039d0fff9a0f8de88d0577e8f21489a1d7060927d6adf85847258f5bead62eaa078ba7379d5c96cf0a8bba4eb340202b10731aa0f1521f4da77bec26f195e4ab13f84eab1241505a51198bb8a51eac2ae37eaaeb765dc79134edc9dae5cd2e9ffccf08cef98f853d61b70144248c41b940e90cc0d254dbfd86994eae5607231c7b010001	\\xd8abe1a31752b1b44a3340f405b3499461d6aba56a4c8622f60a08a2f4c3953e2a78e48a64d20a721143145c1201d4ac7232b91e48ac4795bf53c5619c9e7f02	1660119456000000	1660724256000000	1723796256000000	1818404256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x3eaf5d32c1c5b228ea6ad285a34514ae0725364c3fdde2bc7e6b729401a7682d061d06f3ec36d65cd5ccec2caf9f2252a65b569bdd371f92f6888bdd5252f137	1	0	\\x000000010000000000800003cc62cac2da8f967f29fe0932dad9d38e401e2db21e3271082348e75c2a49a681fcc8f8e544a2900233fbb6d82250d164c49e96fe1169e3319d07ab80d8ff6c491d8de77148d90bd68d52b1a9804c5bf43fbc8c5ae42bd365de04823c54c2ed6a51eeab6826e77558c97f09dfaf26659179656ccfa89d3514cdde96ca1e35c0ef010001	\\x6dbc0ae8646fc72e4f5170dba22e74005b088ddbe2bce3f96c537195c6635c3b3c97968f45031bc26ed31ab8454e55ce1dd5db59bba77d8832798e21ff4d5705	1662537456000000	1663142256000000	1726214256000000	1820822256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x42c724c3cef3990d28b36b126226022b15a543e7e6482da4800b27224b53c6e8e83f606b2abb5745338de9217a38a544bf0279cc23fc6546a7ee71d84d4137f7	1	0	\\x000000010000000000800003df9dac24d53db64d99857e72a7947dcb9c93a2690e76de60457f0bf825e07a03baa09c9c619b87cc3ecaf47d2d90b9bc522ff197c530f54d1614c9a0e8a8a2a14d53963617eae9c59150f4c2ba326e2f8961ba4c98ae3119b7dbb015b72a083f25b0524d08a520e05b26d50f3cd96053b5b333f03aa368a3ef927476fccd9827010001	\\xa4e76c04f4db738b8a6f92f8899aa1afd9245eb1e408373a9c0788604c00dde8026f26cf7642c0b1d09ef5568377cf96c52a590ba3be947919ea5fee6c347e00	1646820456000000	1647425256000000	1710497256000000	1805105256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x43c3b967ddaced81797ef584fbb1e83aa78933cf8c4f74140db620a5388c3987a1005856b70daa3b07fe31011ca48a649f3f0f1ab876ba3d570c9f2e8117c4e1	1	0	\\x000000010000000000800003e60003feefc62960ea50ae938a6c6b362e8c0b1fe39ab49adf8532c44d768d9ad2ed30a72cb5c9e530ffb6f127d42bc15e906bce57c4b2540b7068289d98be0eb45bb5fefb965a4eeff1c99475b0261ec9dc3d10ca4207be7778338444462b75cd428cceba3914be0ffdd82c581a59cd11344f56532c77b722be534f1c730a97010001	\\x1017507962157266c458d36ae87f1965f420bda449053665e3c8f87b55bfce9a500eca1772ccf411cb40fe03d14f997ffb4a2fefa45b87f64627c3a82a46c107	1646215956000000	1646820756000000	1709892756000000	1804500756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x444736a124de7d75d1bcf254e175e229a91840262b4ea87cbbfa3dd5d0f9351885d4c9a50ffb12a43037a4eb6288c4aca6347633415a3f582b81d72e355a84d6	1	0	\\x000000010000000000800003e281e97377c4645c14ef2ba66d892fec351c6a9855023ecea48dc3086a2ac186d681e981c769839223850f6a81365ab9407fa08931ed3061053a5ea8f592c7de03631d9c52e8f47fd4826d9e0a1fb51aabcbf1a21210fd62b2a5b3cf04d06bf59a285b1088bf7dd1424fdfa67e932399fc80de7a12acb0dae8a709356a866b93010001	\\xb2b0dd096961169fb579daa27487e5eac1033b0197511238000a0cad9bf55607f9ed7c5430522b59bf886218ef71d0aeef8f9413796f5a7acd88033a21913e03	1654074456000000	1654679256000000	1717751256000000	1812359256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x4adffc81a880bcf729441217ca0ae53dc63bed68fa963e5573b487d409e8154a6c1e45606c000b3104881af86674a5bdf093813b1ea8b32d84e11fdd24963861	1	0	\\x000000010000000000800003afee58561a09fa11eaa418a1dabf8d71abd8e5265a6b1e53a5b56149fae56bc069ce708302a00914c478442be1e5eca59d1596a826a989a35ca2a3560fbbd7130c09aceac47f7fdeb3182500defd5406c32b1fb541dd1b95ec74b6af60eec4a5ca098dca7998b82c9cb0c99a8b587b50149fc003814ac02469ff10daad190beb010001	\\x7377eaf0b3549afd985fee5c5e54506c61f2d420200d958590c8c8512380bff4b35c54d24213a29cdab905f613991742d1ec168b027c38e6dfc8efdf92d38e0a	1650447456000000	1651052256000000	1714124256000000	1808732256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x4c53a6b7e0d017582ed225a9175d52b0727c019f2a39e3c80ba8baa7fb26a277e9033deaea53999f9718debd871ef73872c34d74e0ca6c902e4cb4e695bf08e4	1	0	\\x000000010000000000800003d4468751c89c8ff0e776739633371e2a3c289136e8df865e904a13fa761990af9dad48b7e2768a48c83a26e7b1957218b0f4afec53eeb1f7fee82b506807eacc6ab1db951a79184d18c6e59baa48b5650ee3cb1b835ab5f1f57773e80839b8ccebff20537f5621bc7bf5d5a0986821f50a0477bdf051884574942dd759757bd9010001	\\x689082ba17ba873aec11cb3723bc84236ef9f94d5f3c55999d277b75eee04cd7618bbecad43e459df7d7732f1f1a95cd953a5b763e1126842cc714b42102fe05	1667373456000000	1667978256000000	1731050256000000	1825658256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4d671563fc69b98cb6c754e948d980683b2d303530fc36e2352228e74b9fc7f48d914d7966674a3eb71fafced4529a515ae0981eba530c7b3af580ab8ee9b04e	1	0	\\x000000010000000000800003c32c19b84f6ac070309bb4004d56756bbfc2ca54c8193e418566fc567a2d594e59849fd090519332d5bcb767237d1bf73e75304de3a37b7c305dbde5f8af8b337d01408bc8306631799fd5b67f46dfdb6afd858e17b1720505e461ac36d7c30e8cf5fc4d2ffcb553b82481db390822e5eaacc58ca714e1569c3bfef62ffaab73010001	\\x1b4c776eea9efff42812fa4ede4a1ff5956509ce70f2cb5ef0f345c1ac62fbee19b432f5522f0798c6045ae3d5f79ee01808ac2fdc1fb0d0945072623e48750a	1646215956000000	1646820756000000	1709892756000000	1804500756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x4d2b348749e193403a7c668505bd286e748342f948849c2bcb0cd527d1ace88e4cd471507ff2edf6172a7adc8e80b1bc46f3fffbfbc4c60373787fa0e0a8f1dd	1	0	\\x000000010000000000800003b5ef0db435342ce2fb71d81201271b57bcfd68794cafbdf16b1c64b7577615a0c3c1386bde7ea1b296e6cf9e1d4e99558993a4d09d3fa2af7dd5b30467e9eb64c05086233bb02fc74fd33e84e7dcb5694e9d572947bb4a7c8f581e70d68b35213d3a6747f05316fb7210f82e6ef57ce6e3874567556410b53aeb48ef625b16ff010001	\\x17c2d8ca63cca4fc2b51faf220e7ceb9c2356168c211a2f3d123bd3cc2eb6942b955682dee36afb09fec28cab81ea898db53bf8dedc0dcdc260ad96083df0107	1666164456000000	1666769256000000	1729841256000000	1824449256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x5367b54d63450907b5e3abe3f177ce0bbb04de7f0abbba78cf2655b57807ccf215fd3b96d2579db735dd54018cbb353c440a5764eacd58f274920423445c9d9e	1	0	\\x000000010000000000800003bc65396e8359b052fa8377a935554dd6a775e3b6449e38f0cf5ac09dd2882b5bdc8f54557fcf830f7d9a2c94c14161e96aa4bf79a2fbb83432141948e584f65e1098f1efc623921eb8b16f63a1472165a56f0084e29c72965a04e5715ea986c9770777a366427a572cc86f888c21d5bc1aa511a3b404e6dfff406fa57ec7f387010001	\\xbf058c9f3125c38e5c68124b70e8226b15435f5c35991fb773861e678f52a31040594f43f47fb67a661a526d3559cf17b6dd2cd647c26bf1d43acf2dd8812207	1643193456000000	1643798256000000	1706870256000000	1801478256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x533341e7814646d23cf0d5df49ec7996126b265af6501a5b753c9369227988e0e07fd1697e847b848b96cdc885add1a6e3d65be382f15749cc34d4c2e909e273	1	0	\\x000000010000000000800003ba1b2e1ce67e7cd45ff9c1a4371be562369b5b122014e550c6412251c6eb56f1dc012a29d3b20d6d9cb8c257959d93d823d632c491bd77f9655323e0e707fe23aac5df2e2a90c3b3a4e223436157a6996b13d2a6d07cec26f3a4fb3f0f1bbbe7d8758cc160e001e6c1bedfd02faa53c6ad4abe1fd49c4e16b2fed8b4bd00efd1010001	\\x3586b591934f059b21f5f2645720ea88b10bffb4e340fcb9f9accf003b955bdb086faba70bddbd4b6d0904c03b02d0a860d586e06d12c5e52eabcd60e4c2a40a	1669791456000000	1670396256000000	1733468256000000	1828076256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x540b41578b360b15f6dbc7fa1e48cd72b9babaa484d85c5bd50bb416bd91e50a625493e634060b5cd2db349e6069c926fa341df34a47352c7bb4c7da43f0869e	1	0	\\x000000010000000000800003cec52b1b8797c0d666372522888d504aed448f8626eca373f963b4f66eabc20ed32a437e1ad4d7721d44713afae8f36626defeeb77f722ca47d4bd191c27a4e0b0d4beb5b9efb2203a07c37f8e8bf9793683cd913595d863563f3a0b52435c676f15d5201c63417cf3e65194f6f7965723b26d55d8450acfcf640382318588cf010001	\\x60c74c08db08e584b60549a681848c09fa21c1570fc22afb1d677f872a0fcc6eaea836c92ef54ce2e4354f099dafabed50c7456f232935f6ea84f4dc7eee7f0f	1666164456000000	1666769256000000	1729841256000000	1824449256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
362	\\x55cbee9333f270dbd1adf2f38fa8c205fafc61b547f2073ef173219d4d125c2e077e7af2b0431b56e7086ae9396205e81250f9a7768e2de9d9d394ce47b42775	1	0	\\x000000010000000000800003b0680bf22b60cefef50c8d8d0b8d11c05ccdf6a2d644ad8b997162722cc9464d9c76f2a2cc869118902b43d4098b5182f30386ba26494cd0dc4743cc36a409d7458b754ac228cc0fa35dbdb5e25ea66d456030dd8920b0cd0194c5e99f1c190a6dc56c08fc431c45b7cbf9356d45b6939a605ba7c4f40644febe8f16f97ccb7b010001	\\xb808e1e7ded755729482eb5362f8c3c534c2609bdd35242c0a63751ba374527d441b761a5480dc072cb286d93d277b0fd6ed4dae22ef936853dcbe31be84fa00	1646215956000000	1646820756000000	1709892756000000	1804500756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x5757d61e1f4343d2638f83de31f52988bb64891dc8e7ba7b9cf08eb952f999c330300b4ccf04eda0074ccafd9e0c494e56793e2bed35094bbbf0249387e634f6	1	0	\\x000000010000000000800003cb4d888c0171d9dd62712315280e1a2204fa653ab29fb9eeca126112c2da25a0a41bcde953ff0a35003cf100c13e2d51a3a1edd0e4b286084e2a43ff6f940f08aecd241e8c1358c9f8bbcc02c0c613a5bbaeb33ec6a44fecef19ed8fba684ed51330483a089de39eefddc005f91e310322c9c318b0b1e7f7a5c4a24a2a97f8c7010001	\\x866293deea3626e247eb6e51dda1b2f0cdf5ce59ab345ead4178d78e1b9c9eb5f434068f4d62c37289dabe213453a6d8be9e40d33a7e9d084859c50bb2eff70d	1651656456000000	1652261256000000	1715333256000000	1809941256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x598f9bbf6794cdde3a1088f9fc4ab4245713ca09d54e648f6ea6de206b2a9c4e4b6034744eebee5c8dbd2cd608b4ca4e5e7ef0e03f7a98aec6c5d12ed14d887b	1	0	\\x000000010000000000800003cdd694265151cf77a96a7ec264c448a3270e7870c60da1f5b807a4cbf44a816610e093e9feccc901d6e6659d02acd5597a2065dbe2853d9df5ebea0f4515dd544d3a966f3c309a01b2a8d00a1ec0f7d4ce7af814207572ca4fc992690316b8247bf706edf192287e72cd2b1bf20eb329abb4d3cc755836559d448d3a0c852b2f010001	\\xc19dfa979375be9c3d05753c2d644a073248a4f95db57f48b3287163db621bf015ce5311905291cb83e469636c4f310b73a7e3e4049b06072252bc75d0037605	1641379956000000	1641984756000000	1705056756000000	1799664756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x59bb7a450249c467550f9ac33dce7378186cbb970150b929f3766fc022ea75a4258f2860bd85acf94327880159f0358233c57b6b49207e1b0ba93e26946c1a0a	1	0	\\x000000010000000000800003d4f7239cd38e642807d76dcee0bbe11e2ea6ec1eb5b267de1432da2d94e38e1c772a3f8f8b85ea59e811d9467ea4615eb80d1707df2228dde2eb8e2fa3ac833e00851f16db7a78d6a279db0d3a9009fe8f9c3adaaa11a3419d933b4044bba363ea65a675ef01e9aef678e7abc1218dadb02eb26632105302d8e474de19c36b53010001	\\x35899f3c019e67641528659d7e487fc521bd39f643d5b66c57f2b815611becc9f5cf2af5b12b45d42a3d58e0c0d88c0477c17f75af4a2c6cbecfc5972ea46a0c	1660119456000000	1660724256000000	1723796256000000	1818404256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x5acf1e8316e48abe469ad79a2b2cd1c04f0acde52887cee1988403e545eb460a06d500f2dca1f92610d693d9967521ae8307db5e625fedb27a0c94051590ab4b	1	0	\\x000000010000000000800003c8905271e03a018b845937122cd91eac6b70176d579de67e7d5c7cd26b0f9292baa01336bd408c835d6d241b2bcb8d96526d074e05aecfa447ce9a304c48552ae464ffe16de91551672d1c4bc85818ca012ca0943b0be5c3f1931123f47609c9f7dbd299f2e194ee50cab85bd1108d034f6bbcec1a289e1ecd9f605450012e45010001	\\xf0b7f4cb6d436540ff3335ec1f7c3db91e26316e9f30bed3b8a9cb4dc472aac1e7ce3c736b2004297ab0d72c4071fbb87c6ef76d0ebe1f743731125ad7967207	1645006956000000	1645611756000000	1708683756000000	1803291756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x5bd7245f1e51c8d3207e02db00ef24ef103abf7a8ed67bcc4365f33d16cdf193c247bba7c59e0d7a01ef0d86cac16c2a6277cf22689a085745e133366e22769c	1	0	\\x000000010000000000800003cec5c462d24ec6ba36e25a81058223146c5d0ba3b5d6c118dc29d817d0a612b5516528e66ff451357f7496e1e1b3db7c26616895856b0c58bf8286cd98a804c2fbccdf02f5f5b4bdf4995a76ce6a889c1f797e47b23545780c228040f2a6e94cb370400ddf3e8a2aa0215a25f53add57395700f1a19e60ad364b9a5efc3b2197010001	\\xcc439f30b04bb8be61af4aaef796726cbd4d91ce9d1d90309e4ad45318d691b56b3d901881f54ae1a01eb490ff8b5a58d010aa268354b0068e08beb6b076d706	1639566456000000	1640171256000000	1703243256000000	1797851256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
368	\\x632338c0957c6dd1a33df284bc7e8df131eb09e09376b6c9b0b3fd34cb27b0c4e2b5713171a601002e0c5f4c9315a86d3888b6aa083408000ccd75c5307afaf2	1	0	\\x000000010000000000800003cc32f3c1e30f0d0cbe825dac2afe005de9e91b486228721265bb294597be23bbb16c25696969115c38ff1fe2aad6f16d71d12db2985da257b66dcde7c3b67515de02a28fb51e6472394fa9db9fec29383706d215a6654bb4d4ebd18ddec96f7d8c73e9bd0ea0e48852f6e720e966cfb1d7ae7befa6fd1891bb925bfb8592fb1b010001	\\x061052172123ae7b77efab89d13d2a5cf10f093eb12ffa286003974931c898b54df082bd7be66397b0e78a16f826ec1b9ef73e6da1020a99328de4e1c8190200	1640775456000000	1641380256000000	1704452256000000	1799060256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x69d3fa77227ebf4e4e3774e9cab97660c573ea3b3c43cb30dcf8c335a58012d1192062a7d3be297e63c7b8b3b7e5da5fa7b9050d0a4d0e2511c0e34c7f2818be	1	0	\\x000000010000000000800003f4967a01a389459b2260706777eff9932bc1cbe4bd5c95fa426e9e9d07d4b78503e37839bd7f14c30073fd4e83d5039d463157cd23ff314e593e3c68eeafb6152dff89b8f489e7345e742bd0a9ec39c1945710e6b046735243fc4ad49e4e6f34d3e162e401eb59d072ec1a12ba6e66481a7a9a8e22e9dc78ebb9e8c3dae43abb010001	\\x219d583b0ee869ae8a6f5d08030577819a3c184f240243c43eb94ff2dfec427cbb6bbbe43fcded5e327447c7de9424d712dd43a10cd58d71ef82afbeb5c6e002	1654074456000000	1654679256000000	1717751256000000	1812359256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x6bc3d758609dd32da87c6973c503d5e06dabd3388fa22a91b9eb57dbc570d0d87c2bbcef2a7ec9ef2dfe027d7744207f73b4b8e75f8b0e2a852806225b70f563	1	0	\\x000000010000000000800003d670b931493624a606da62e041bcead71d77e91449fea25e4ad5cca37dd9fe81cb4e113da29ee497af13f6aefb9470d9ef22663bcd55b42f47d0845ef45d44c53ace0cdf6d8968b1326eb9574e5d9d2c64e10651a6b806c0e53e31b3ae712c2dee427e54a55fdb58baf378cb66ae08f6db0f2fddc59871874f8b6b2af92a7007010001	\\xdae5ca614bb84d60e49b40094216a8b1bcb12873dfa043539a3673e6682e4532c6d5598cee06ee6d0cef6de1316ab7fd2d415373201230970ba8b7a0789d1b06	1645611456000000	1646216256000000	1709288256000000	1803896256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x6cbff924243d765ba227acf072e7237071beae5f4236c58bddc898ea62a9726b8393c37d4eb4e047aa80a0e150940cf17a9aa9eabca862f0c2890219149a38df	1	0	\\x000000010000000000800003d41e42b4e4f15e6da6fd25dda776664f7a663ca6ef9942acea4bfae59ee2d0dd84c02415dec58537fc3d5626203d357bd9bda4e5864945412ad5f90f0c750f0033eb44ba24a9e66e4f38379a037b5fbfa80504dbcc7b7d08c50d55ff38f9929f415d745ea80635f1ebc28845c19e5e66aa95552dfd7f45c0672720be711454fd010001	\\x155c529fe31c7638447c77d801fcdbddef103a07d290ae973ca7ed3d0240f61b43360a7d7abd9932b15eafec84be2abf58ab468d29ed387c2f1a47c55570b20b	1655283456000000	1655888256000000	1718960256000000	1813568256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x6d930a2615c06c2abe0d43537960e11838b1a3a2d351a1fbe21077af512ca22de0d4b4dc653e44f915cef6e393895f4b5db7a7281060da450ce1c7c2d8d4772e	1	0	\\x000000010000000000800003c51f5e35b7be3d717446ac4d89024e947c16338dcb71f7db030cef617df370bde11d25e6f7f8a0c96dd0d1be043e5d4c5ef2a07d2c67dfda2ee36c7fd5c1e1a3c9248edb11d2abe2c13291136bbca3256976a03e6e445ab3f35d1e4e54f59293e19ddb5ca2b2d112adfbe2ac4d5463d63a76e8a77265fca94bc928e0a705d921010001	\\xa1950dd423034d8000635a37ace53b5d081bfadfc121e5817f287a53bbc052a72ba1626377d1cb9537cf09218e4678658d7a991a6e455b3f05b242f47902470e	1661932956000000	1662537756000000	1725609756000000	1820217756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x71b336426da673e2b626aadbb8270ed71e247b3d0b33913cad192332988f2966dc3d11a9ab9580519bcad22b207a3bd5f9999af6273d7913fe9d930b353bd118	1	0	\\x00000001000000000080000398560236fc44bfcc92c82b352f4a68c166a1d2156cc3a19da1c2f65c290fb32a56f8382789d4fdfa4e5e281e05b21f9e5d611470c036ab769b877a41b40bdba881f8b7ab118c166bc386749e182a502c6ad28500a0f5b6019767175a75623239c721e823e2e350cf327db64b0848cb5e803f1e707555bc108b63c8573e28df71010001	\\xc196af5f3dbecdb62869f572d1634645355a6dd2749a8be18b7db989fba499e745efb5bbaf434b17ddcd3280b1a7fde32b91e94780e0cc54eea18434b9852501	1663141956000000	1663746756000000	1726818756000000	1821426756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x7253708a994cc11dc568fcb6297a1edf3cb4e394d7be2614a12294827f27f65ee103ae6649ac8603f14ae6cef5e694d35b3a24525ee4ed85410a30e9e0e4ae69	1	0	\\x000000010000000000800003e4c9fc89d9cbdbb3994381e6e838e4557e9b0589716292a6b07b17a7135cbb5b7866e5512918807399475d83f02c30c479ebdfd1786cef5a99115d4633981fe8f92c98d50d5b8208324ad0be20d2a1b998042c4e81c8ceaf35afc6d2fc7b352083f2571137b1b34e68735a3fec466c91ee387590c7d83a37181ae4ec402671e9010001	\\xcad244a827745c0e3bf427c4068d4db2c44f85d7e32393f6382c78768220d6c5b70b23a42081b49d6f841fe4b9d59dde182d377bce7f6239fde6ebe9c0d1dd07	1669791456000000	1670396256000000	1733468256000000	1828076256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x735b1694bfd955a22d33503f3f39360d217e926bca8be06ae094e16ef023253d04dbef149054afd3fc4a4d228b8aaacc7cde4eadcbfb163b1aac36b462601dde	1	0	\\x000000010000000000800003c543be96cc93992346c81fb1ca9f9bc744dcc02109ac2f749d9aaf37057f8c5628ea95138239264c1fca8209aa8786664867e9c2c3323e42462510bf2df91efe0a6518b3635ca1c9e0265b3e7f344ba356740d083dd0bd67822eccc8472f598c52a51ead1998710e030a49238d77653351572e0f0e758e95662b10969df5b651010001	\\xe504d8641fd5d45dc43513469b0cf5954ca07708e4780d9f5f46f918aaebb7c2447f8ec3ef282fd16bbff2ea74c9393b905bbeb41186fe4e9dae4b0d03a4cb0d	1669791456000000	1670396256000000	1733468256000000	1828076256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x751f0ae7b4fe59e8e92d42ee7fc348a1f5f875de4149809e6b2c082167aaec482368cbad983a037af9572d696966407a5009c5cf5f32f43beaa8b3180d9246f4	1	0	\\x000000010000000000800003bd54aa2993a190d0e25329b95f26962a3d23d47e557a10629a1a8df9e2cc339abc17ed3663c2f3905406e60956f2058c569024fd4e150c3cd86c64ad2425b363a79b6142bcfde7b29b9a701f7725d0fb74998f19a41b4b5c6cb272efc03b05eb39821ffee61ee766c36fd69cd85669c7da86d34db59baa2c7cc931ef6279ca2d010001	\\x0613846b934fd343b60d1703afd28dc86f18d1acfc6cfbef776688fbccfc36470b15fd5f29c4f984bb61439c9ef49f902f5ea1d5256e44e7b3aeef8dce5d0f0d	1667373456000000	1667978256000000	1731050256000000	1825658256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x76a366123d4fedfa7cc0f92a5c87254cf5f2aff0931d3fc624c40e940c19842239b46d8004b8e988c69f5e217b3a6af9dd62a3a82057f36be4136f79d104eeab	1	0	\\x000000010000000000800003d4ce235bcc49b9daecc941726c65779ec9679ac013916145ed3378ccb87ac7208bfd6232e0ebda76b90c076a9a643d2c06e3b7abef5ae141ab353ae0b482072c2021f40f1f89c1e8e44755cea1ce580d3ac7d919bf40f4da622e38af0ce408b60e3087b705208b5e4631ad8f5623491e8a2b620fba9036e57dd14eadf94da26f010001	\\x3ffab4d0ec7ffcc349c062156a37db353b3ff31e86a89d7de9905365d9fd57d154817ca70d905103ff4a19a9c77f9821f4f93c4e557e3901f2e22d884da8a90c	1641379956000000	1641984756000000	1705056756000000	1799664756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x79271a6eb73a73149c8880fdf4556793d35dbbfa80f1523953ca19c3a528476f4693b58292b4f5272ad372c644e61582f07d8cc89dac467b12f80e261811cb71	1	0	\\x000000010000000000800003b5f1824f5a004ad71c71471073434562cca462f1a3a4197e74dbac03f70e8b506fba619f0ba1d14305948171249ed300f56325f457efa9bc21e2f260dc9b32734c189089b0271e7e57b7bd6e268c7285453372472265cc36a1a15ea453e5b01bee58a0bc46ae8c2c2997698517380f8bcfd8227517f32831b7ee0b146c690291010001	\\x0325416bb5686bd3eecf534abaf5bdcf2ed9d28b2a922a569c3b2fb44c44efbb4c7cd6e0a8d83d44d785b821372c802417a27f854cbf6967808ddcca43b2f00e	1651656456000000	1652261256000000	1715333256000000	1809941256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x7b0f9b2ef7c457fa1dabcfc4fa2d15010cc98835d04e81d51a2cb3eaa1c7348a24a30483dbee682b20e0fe69bd4ccecc04c0eff471310371a43edbddc443f5f1	1	0	\\x000000010000000000800003cc0c10d2e2b70801849eb68c43f9405a7611d6007711f631c69ae8caf050e3dbf8e334c956844a51825e4897e7fad993df10a504d9273b2566a8f67eb98cbbadddf359d27dad411477989d81f37c2f7c73c1fae424f2b1d7ff6e0a5a5ab5836fdad925f0d3b5f1c70a91c9b5a2f8133166bde48dd54bb84b9b82dd22c6337d45010001	\\x5e8645de5a8f8d374427491bc5f3c6fecc8a15568a5af4a74d2eca9f43d77e68d149f565c1fd373bb755abc5aa996a3ec390e7ea83de1895ed3ddb97a4c3f507	1664955456000000	1665560256000000	1728632256000000	1823240256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
380	\\x83e7b87081ae9b20b0e661ad763b8e5d21fe8982d3a1ca576898ab15eb5eea4911d4466378fe163a88c82120a1a98d1138f14f8fc16e1ad95e475439ae69a593	1	0	\\x000000010000000000800003a0991eda4d197b726b4cdc97f65608b476add12287326516b63a927b9f3a6643acffac355899d1a3428811d5cc2a1ae5c6410397251d2400b9b59b300f2293e772e851b1d5c9cec4a432a54580fb054386b020d352170113b85eb28bbd74f259f8a0ced3bafda9adb74634b96039dac5c25f8ad703c1dd6c15ee4a4daa648151010001	\\xae816d01a15f0db2194aef50b6b751aa889a33234482ce7cdede5387844c100851efa91394b3b95f2decf79789faa6dea68fffb4e2a8771406f46b7ca0824701	1640775456000000	1641380256000000	1704452256000000	1799060256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
381	\\x8ab78bbbddac65517a11964fbae0f0c8aee38bfc005f9e028df023fa0b124c85ce239250bcf429e7cf1d1acb6474462975b2bbd730b9091033358cf161e4a16b	1	0	\\x000000010000000000800003b070c0ba59c103a2d5dc36d5c979edfabdab761c267753b92f61d917845f3c9b221a069dffd467c41466da601957f47ea4db48e50eddf510319a0f69ee4502e702ae89f7690a2ab50dbd2f7b9cbbe294e547b3d2f76d7a85250f508ebcd1535f4b7b0169e0ce1edb048fe69d19cc4f32353b1aa745be71e0a9feb372484d54dd010001	\\x68adbdfb7b1899b9b377b317f5972e8a0a815f785bc44845488bba25f9122d3c4f3b2f5da83a059c82eb89b0c7f3e29986575585a776cc0ce1ee772cd91dae05	1655283456000000	1655888256000000	1718960256000000	1813568256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x8bf3d97fee33b002c35f3942c9c1ac1ff29fcc41db84de1c127236475a3ed8b91b852996aa5c284a59d677b42504864615894436f837378e3c2dc2b42d7d689e	1	0	\\x000000010000000000800003bd902e660b6ed2b733709244c889482e7a4f0b0d2610756382a9da1c1dbb2b090eea67fc9e9490251d1da30dd4ae8d386d30bac414d203e6376ec287261c23f8aefa9fae14753a54c618862f0b6da24155ba485e2cd5362dcf527e5806febd35f45f3a385075ea0eef1b4b7c7f2fda5182fc7f2f77ceb1e41323293845d42791010001	\\x031efde4cd846b166564f99b984544a4d5b2d1f026b7e567e76fd932bc0d04e4b3324218b17f5380f4dd2ec433bed606d0b75c75f7adb30eaf7e8d206fab8801	1653469956000000	1654074756000000	1717146756000000	1811754756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x8debdbce0d4b523050477e355bebbc28272dbb1b851c04de8e79118ce4079c7fd0ff2a97aca1642dfe5e988749078b8f86d65685556dc70694f15b0130eba576	1	0	\\x000000010000000000800003be1f2d7daeb92b02cd826bac2453c6837d2a7d8340248a76adcd4b8ebdf658a97b7e3b62434ea985cbfc1b48c95ab5d4dfb4926f4dcf405574ad8385844a150d3610162c384760018f175943e958d4b85eb8b94bccb2c58abdbc87f3c138b818c2e09046be8881591feedb2dbf42349ae8c91b6d849d90c17104f9d35a434add010001	\\x54c75100bc3118c07cb2e5e2992a7eb82a58f58c2052923d01d2db287961ede4b12b02d13f152d5b395b54ed2db1e0b08af7b1778e4e20b555b613b5f2e2ad08	1664955456000000	1665560256000000	1728632256000000	1823240256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x8d1f703f971886ad26c02ca2949a273b59737312b8d8fc26e8f71c9e92500517cbac9e91fbb43e04ca517b3b5b23e5b82bec9a5c161527eddc8e04db7fc86630	1	0	\\x000000010000000000800003c15bba870e8e58b263709c2d89a50c760dc966d265c6a92ad665e72a0230cc8aeace47620b9ed2d36ecbc89ad4ca03889aac9f2deefca7dbce673a0f5c4b1e2771b79a2193e1e47fca83edebb91a2ade132e0cb93fcd15f6a429fd4f4c4fc8c5062ab5c5a33be00d50ef3f6244020b83f0be784514dfa3cdd0c4543ff8c96dff010001	\\xb16fb1fdff012e3540b55c318a4e8488142c48c10fd58014cbc55461e556eb19896ee5e427a9469c16bd85a2e15b6f3c32c382aa2ea6ba3fbdf17e755ae7a609	1648029456000000	1648634256000000	1711706256000000	1806314256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\x90631a49fd842ec3859fd9eef2676f6926bca4c9dd7c2f3210d1e0965b6ef9a5effe051b07851d9fd3ab0e0a1c9f55ba85f0c37b51f87e36dcb1a734717bad94	1	0	\\x000000010000000000800003bf9e621ccab5a9c06b9afad083d37ce22b4e3f148c6c74e243af577ff3086fbdb0ef5efea4d2f1ef0f833367b5c56a52789124fb6aaa435ebdd9cd1a28b5dd0d9c12cd2aca5736f86e367122566266a7f9aee93916ec3e2b5867dda31925484c72d7c9bd19324a5713c88d23c94cd1a0eb48de42df37613604141c5d2c1724df010001	\\x2c5cf4366fb670e4c27e08216af599f804a822c80de98a8a6e7e60a00446a6296c3b3e19086aba3e6adb27bc8d1f36ba1e59e2061bcfb8e91f4a31be008edc0f	1641984456000000	1642589256000000	1705661256000000	1800269256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
386	\\x91cfab141f413eb753a98c2ece2c7f298d56471978a939e256a66c2517365eef7aa6de263f4b9aca0420d4527771dc85f1a8c1f6419fc19437f83be21231cdad	1	0	\\x000000010000000000800003b3a1603edd01ab02247a3d5ffbfb6b7faa57ebd40d1f89c14e368b1095e280e16912004ca7dee0cd832c58600717a76a05136e357d250e78c5e0df2c8e187695514950992d9dd62a718aaa71f374e3339235132e5aebd5be314007b2adaff76c33fd2d96715e754469811ba8edd1252eac3d9a95d2cc57b46c4ac4d7277100bb010001	\\xc231611163a4e62d7186a545d46c379b0f2359872aa34f021fec96df452cfe69924d619f16de7cbd390989b5c676c91d9e16bf3258300ce51a2ff6d1b315330e	1645006956000000	1645611756000000	1708683756000000	1803291756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x93ebfd9dbe2dd3ac3e828479fa86266bed96ce8c68ed522bd9a7adb23dce3f1b4076075624b83a0193bd8263c7c9380c0f51f7af65cdea92fc70c5e8741824eb	1	0	\\x000000010000000000800003d8c36fd086d960b5b9192aa09a4cad4a7b291b223832d214a4f0504009a276d2e63cd725fa88953bb00402b145bf623b60406671fe99076c66e751562dc461140cfcae0505fbe395cd4a646f13790074a7fdb9e7d11e8ead653ad74e2deedaa24c0cdf9a9b95e1eb2e5e6b45a3a597f71a1e41f6e792a533eff0707c451bcf15010001	\\x57e44c6127a1f81ea172c6d79b46936db9e6a0794fea9d5752c2e71205a74585e2cfef254d8b7e9551cf63a641eecd307044a65f809243a312aad47f4320110a	1658910456000000	1659515256000000	1722587256000000	1817195256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x94bb0719a6a74e7e66e3341604beb5e89f65ebcaea066888e4a632c621cd47289b62c7ffed646006f201022ab821a843823f7dd6db9329ae41043dbe6198b62e	1	0	\\x000000010000000000800003d8c315714bf407b41609b8feced56137041fce19ac5294fe0db53c1708bb033a0d6659ce8704435a333219cc2acca15a4e5f96aeb316b96f628211607f4a0bc7df37a2058d3fbdbb79c10689a195ecd969018f185ecc692a9131943580f19b4754ca9fcb837fc902d0579f5c65d7326990131f7ccb09c06b326c5b9acff5ebd1010001	\\x74643e96e366d0b3eb17c766db188f98115264bdc80f4874031964fabd63e8ab00ffef13bcf229bacb34daaf034ddc6aee32f59e191a9da5d2f47aad0c062409	1657701456000000	1658306256000000	1721378256000000	1815986256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\x96d33feca02bad576e0e92e858f93589f57a5bd9b93aac00ca51f96070bed77f64fa5c2b9bd2e816a4db1ea745aecee836c276a4f45392bdb38b166221cda6e6	1	0	\\x000000010000000000800003cf9f040d7620f986a172e89c5ecee6950022f31ff2063df2afe2c2ad782cded967a4856ef71acaa598bd6b30d88ca00fbbb976a9c9b80c7db4faea3faea0e888e7e4c09e49c78aac5270666848006c62362e705d6805ea3f11d9261e3f8dbbad630664afe6a83b768ae50aca95c5065db6c509b50d4cefaf3b24bd2932b249f5010001	\\xed1a271956fca19b9655a931c61666a2f8c2782711c778239d016e42f913634b7301efec5e6fd80b76beab5b04beb7210b8212be13249a2f351cafda3eda060c	1645611456000000	1646216256000000	1709288256000000	1803896256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\x9c6b293cd60e5c5f3addeeaa52ee87e723604654f7d66334a82d775fc562eb094f5372f033d25895b11304af01e017c011d6a3c4bf9e37619205a7fe3732816b	1	0	\\x00000001000000000080000392d1c12001a6b411641ed35402405dc34859a77f97a48b44b677f899f08b42435c7b9d161b029bae368e2e5c12111b7b2cba2fb8bf243e35788be8192c22e15ea747718891e1186e1546dc609ce8be46683465ac8ddf2e820426b8171ebcc11e54a3bf4602fc86e141296808f566a4122b87b16b550e45c646c4cd9060d80c23010001	\\x53ee1883be3b77e163369b7a7dac1c9b5945e52ac8fae51d748213fed2830612665e5d85edaedd8c3464941cc503a817ccf516a2e8bd271588fcd19a83e29107	1651656456000000	1652261256000000	1715333256000000	1809941256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\x9c0321f4a5bd9f787d41f2d71520fb73459435960c494753aef8ee0287d82a92f64f7280253c26a7737b221533da75fc264075d605832b3ac62b64d9ea55cada	1	0	\\x000000010000000000800003c401fe8ea7e78ccabf8cb397a241a734c93f850d08dfc3a2f9a113ac0950669a169238e8186e9fe25184a9559cb5d01e65ec1078b87709f7db0a2c5e21dc925a468878860e3fb70af14bf59a17b6171d655febfe07c8e8cf2efd342cb815036a8ec15fd135d42edac250be070a2861e1f10ae6f6bb17b6227a4068873b083031010001	\\xe83b15ad312ed334b0d8420d1caafeeb068d797ee2b6660a062a7efdba48f714af202f83b87075e4243b7d4cb58f0967a424e0a62202b8ba5c51d85abe2bb106	1666164456000000	1666769256000000	1729841256000000	1824449256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
392	\\x9e2f9d90dfe5860fa0a99351fe96c589311eece1231387d63fe4f09be636ea0747e4b41631d4cdf43e72ee2f749c529a93d0044154ba2d7f463f1cc80c608d79	1	0	\\x000000010000000000800003e386649ecf60d0085fb13abdb00407d013ab9ee390f23f96e5ad71b90152ea8807c1a2eab82727725ab2f1676f8f33af254ffdb828ec2c1d156bce2f111cd9a5eb547bec46213e249f23bba93437a881f7dd9eba59b8d213eccfcd703d6d3c821222a8013f72e3021a3cdf6e2f0565f768126db4a2e9f695df3d949665cb504f010001	\\xa6b04c0d7c9b8908a9cec750a026e53509bc5636ef1665cccfe0af62d5b054f4f0ac40333fdd11c3ee7ab692b40fef267c52b94b78ccf609935a505bd391cb0a	1653469956000000	1654074756000000	1717146756000000	1811754756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xa5c35039820c11956f911f1b64143667174e0f931ea2892fbda01e5aa77f913b5eb7ebdc6299cb3cb6c4796e0939741d3821f1dcf2fdfc5afddd0185d948246f	1	0	\\x000000010000000000800003c61fd8ebd117af617e4da46ce2284919fe786196b6bd38733083c6921139b1324e706c75bb1ce92e399305b06ae1afaa5fee8285cd4f374648be9f3488197a04f907f8f0e141628153dbc45565264e9c921ad1578fd34909680149db2fa766aec52c33ce7a82dc2f8b656955065fc99ec7f4273178f7a1c7877afe3387af1ecf010001	\\x6cef3e6e91863ce1b23be7844b279e56eb97d1b07fc1abe419cb1e94d52fb84bc9ba502a7f346dcdf252206c57f8dc79ea31408156b574a3067e91f001378d0b	1648029456000000	1648634256000000	1711706256000000	1806314256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xa6633c769e34e9094518de47569ba1e19866456f968f0c696e63b73f3b879dfc3d5ac0581470ca5d32d4108aaf47eab6effc15a312a424a3de7757435f279bf5	1	0	\\x000000010000000000800003ddedc5d9b5a7bc0c809fde65abee0fe6d94eb6b9499fabf6e90c79fd07205d6742d93a1108d13466c81c29bbba3b4cf6455c2a414d1d5dac1f5b555deee0a3c18a9a8553424965272a050b7334717415ad93a1ad1f16eac8c7ccc84af31b8454947092841961a20295027434a26d623c988f676088d803891da2df0d1dd58755010001	\\x7473634a39eb164bab650561225d94f0a9ae312888d7dee1073b46bad06de8cd459db33e2c1d2b134d8cf68258b830a69b552a72ba186b8bc209c1fdc77c7904	1665559956000000	1666164756000000	1729236756000000	1823844756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xa6ef0566c9b8e06feb2ffbdeba5450911b470c7c9e75d16c9e492bc531d905921768312bce5bcac374c5fbb9cfce93a78522561eec6c71c4d645e030b8931530	1	0	\\x000000010000000000800003b797ccbcdc3adb1d893410f7db3791e939515ff87f9cccac20d8baf287958b347c6af3d432d8fbcdbe9fd256cec14bb623b663ab3acddfd2d767825e81c8bec50f2e263fad1239825731d0dc1f0252b24d655501d47cff0011b769e596a68e8ede86cc96b4c32798033dd1d1ba80e3762ff17a3783396b37a8c83065a10ab7f9010001	\\x68810f1a05114fb74a83beb9eb5d6d61193cc82cae04395071b9c9f0638cb7580f82f9948f57e5d0cf700ad70f6e6eeb091547a705198e0097e272bd8462b00a	1664955456000000	1665560256000000	1728632256000000	1823240256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xa73b74da233025341e7949951283c40beac3018b30cb81ff6d49b24474e0a80d2c208b5a265c36931f871e4cbb871e5bb00b46a6fc8266cd8602fb0e3a93ead6	1	0	\\x000000010000000000800003abe60b752e2aacceb6c2193ec01922e90b862534a419b2cebdc637894adb8ec2da85bda9df6ceaf6351186cb555c32782333e0a6f52319e6d0a5e7de10d49c3fe334c896c7a39842b2c3e5d9eb7aa2073b45d4ca0eb335c6f143c52843fc685d50bcb1019d946a629bed32ce953b84ac8d7a7a096a5abeaa5687048c2b6639a5010001	\\x3464a9384e38560d60c9dd201084a20c5f560a375d3090db1a4a7cf711ed6d2193b2a4f93b5559391f77bb9329af0f8ecf12302867eee63ae6c0b6e220eb3e0f	1664955456000000	1665560256000000	1728632256000000	1823240256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
397	\\xa747d22c8687e1ffa862ad669bdc31c78e9d782231a984ddafc78e30b0e67c4c9e825643d8e7b27fad75b91e464bde89b8ca7b714ca773ab028a12ef3e53146e	1	0	\\x000000010000000000800003b37052836de4359ae1a5bdea5afde87d30ebe32d892c123c43b6a16e1975913b7ea43d170e4381faeb9cb7894be800beff0865921500ca6da844a9edc457c005a4a7754b61514f64af79dfc876028a57b567722895ee32d87f08280fc8747c776915e6a30cb9182e99c069b4651379b7d30a80d38fa8ec64c6bb2bb8104a5b51010001	\\xc7f987a58f726847b3b2e888c566fe1265e16f1adebc9846cd387895c6a93384ca3758704a96eeace6f6f6de11dadd4aa60ea1d8012689b397758af02f2bcd01	1646215956000000	1646820756000000	1709892756000000	1804500756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xad2f2a374bf8536dcce845600981f579eac6ca6875088d067035af9e041782fc8090ef234395ea192fe207021ce482a66014b343ddcc9c38f310800ce10ced27	1	0	\\x000000010000000000800003b8819656cc30361b3d10564c2dddfdf66f7d73d5378ab61926a0c3becdafa28f61dfc456df7445b105004bbf1034f76fa1f430dfbad980e9ed0ee1bd9a910aaf649f7b4dd065ec4c8ffebbdb00d3eecb924e5aa0481116b02a46a71394b9e5b4c8f7ecac2ead8c6b1020b33582fd55d04a622a4d0400e02a032656364131a647010001	\\xfe86d7d52bdaa8c8fd8023ffe2daae3e62cf31be17627b592b17729d04a3355a5fa8fbe4b31d2d82e595b3f6badfc98a0b778154e585184fb49e1fff83f8b104	1639566456000000	1640171256000000	1703243256000000	1797851256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xaf0fdf7a5811b6ccc0a094a1bf3e509a995ceb9a4ade12e5da53bc4f05bb78917c849ce63f280b95f853892a05ade0695970969f70942202df9ae7343fdbc3b8	1	0	\\x000000010000000000800003c3a32b48edb448e2fd6d283dda49ff5f193347c0f291b700b43f650094fffa2193dce4d714eb49745c79def841ec6f7b21e2e884ad45126998a25ef93663905cf4817b6d9bcedf23facc7c5dc48465c16785630fe5e627b716e48af0f439b6c38811edd4f335e919bf04c08152170f50d2a3c1d9ee46e5d0f52ff7d2020cca03010001	\\x5ff8c1f3febc5f943699bbc10a8118e954556f5aacf185d805b190f774b040f1ee4582994c807145df498deb7bac5c79e0c5c9b7de37d5c6f1cc23a2875e050f	1654678956000000	1655283756000000	1718355756000000	1812963756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
400	\\xb0c3fb094a5dd521f492b4fe159767987edd61e05f449d074ef2b776b7bdf5d3347b73a9dbee02a9cd2f83b9e3b02f103a12f255c51dd3c5a416af37c6cc1d72	1	0	\\x000000010000000000800003b250b55ccda2a0cd50cef3f6fce77fc45d7f7bcfb33bdf4a2d3383c9edd26a7f5cb3d140844efa17ba19367665835800a7ad1919b017a3ea3a27c28319ae86b25d54120d3dc5632b9533452a88a8c27413de7685b0d2c7784a323aaaa96ed6ca15652afff4e85bfef723255ec37810c1642d24e73b909e1555858f589df2f7f3010001	\\x9dc9cf18ba29679fb36d6fe5a2f70c59e77450a2f2d113d50ebcc0ba905a96fa49355328e794993e9e31ec2f88beb1b217a5e057edeeceec891da630c881ce0b	1661932956000000	1662537756000000	1725609756000000	1820217756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xb2e30ff610d56eb31c12ff16cd2ccd909b6740e4f553733519743b8c8a388a5b4095041d781b9366bc4a3448b3d10fde75f6d385cc121c0c939a71b536aa22c7	1	0	\\x0000000100000000008000039b3de7a1ddd3948c8e4c8b383742d3f02e4bd3a2e8b729a1c44aa54efd2cf85c18070bc96139d69b2f0863612486fed9a1e397d7cf53409ca2421d84e20425bbbca09be961c7ed50ffc101eb1af38e0ba8425ae60c0d6c7c39c2f011308b37ed2460cb68c8f775b83dcd5b5b529329b06ec70b6e3d9dc1de6b6ad1b052a82e45010001	\\x43bef10b394f545eba8b62dc8b56ecf9cd49ad9bf7ee42dc954090192fa295ea49eb586eb5dfabd97d8188d0814cea36526407c10e2d121b554300058a035108	1646215956000000	1646820756000000	1709892756000000	1804500756000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xb353f769a2ef8a283d5b9a6ceee9c3e39f23de1346c550580f9b7eb6f443fa27a71aa068457ad4aa0ad643699f1f1c8f6ddc60fab22c6d5dd5af9282953dd854	1	0	\\x000000010000000000800003b32e37c93253714dcbca204de1c9aec0b0e9fd3a755a90694441589977d74cfc4a64c5ad7655264160b6ebac8c655a98b41bc04850a27e2133887003b302a048350570c0d7af8614f41bbc2398073d057d2881c6b86f82ba63c99a081fab1844a3502b668f1eefbf31b8d1bc5cf77db560157163f285c296bde937bf87573aaf010001	\\xb47b66b867a269d1b63f930911a36dd683eb9e5d0ff5aac81b15a2430158abed1eb2b2ab3b256d855c44176cff4fc77a35a7a4fcbd3b23fed8cf1b5f6278c108	1649842956000000	1650447756000000	1713519756000000	1808127756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
403	\\xbdefb1ae0fd8f9b84c357e2157a8ee3372ce1908383924f1c046b0eceb8d03a4beff33504b34b6b016830e9d064351f02735c6fdb6c43852786d699e1431ff75	1	0	\\x000000010000000000800003b359f30c4f20c7f2546643f1308c5abc6fb4e72eae671a58136aa736fabc19a35a2439a55d038d4e707932ea41f78db716d63bef207b93908ac5d308741dcbdec0908792e82eeb1cf2e27b9fa3e1bf515a10a60bf6f73f3e51f8c4b8a8723ff49a36a3b886684b492167d99966d4f388b0c19f519710e941f2ddf2e9e71b9fef010001	\\x2036f1cc6fd817d31700545fc5e72638bfbdef73b81eb0a616700eea25c1fa5db45af729b5674679e401ffd1b31c6a5134bfae6c254bda8f994fa93ac96af601	1638961956000000	1639566756000000	1702638756000000	1797246756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xc13f3e8c54a98116cf7f6cb2bc9ab511dec13a3ba5059565d3008ce7adc6b6c087b58fcfea631a304a56597c8a817daab929f27e6b8c62ebcad47c81e18adb6f	1	0	\\x000000010000000000800003b838d57684993254b239f90de5ba65ce13fc57f8c07c0c575f3a33c25ed86f60b6b1849786ff2924289316b61c6094ff800cdba06539216bbc3d355efa225345260c8ec136e823b56ba8affdea9945923744463d04c79340e938b76e2bd606dcd56807102e881e59f5490eebe514515204d110843decd5a7e86324ab0145caad010001	\\xe74d5075009d0458d6bff66c0f538ab7c790418ec13eae3f51380932e55c26e1555150cdcf2663d56fa8f51c826eafa873246a013468e51012311381be385a04	1651051956000000	1651656756000000	1714728756000000	1809336756000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xc25f41b2ffb9ba9231c14c5b1947b09f12d763567ded9eabc98f227de6046c3a63734e7680642855b70e8da87e746a4c7c1d1713ad952a5b1460fa7cc03faf5b	1	0	\\x000000010000000000800003d5467eb00b2f35c882a4d93d04f91a0eb558518e19121dcba6cb30c0e6b26a78c2105ccc848a6167d76953c35ac5846181e5bb6679b366a7ec085c8f88d9da8b34f94a749de5c971dc9b992bf21c376f72cc1b3a9c4fb74596fd9f10a1c1ab57b5bda430ce3307c2ae77a322583d768ad69c83a44a0ec60a9ae1ec57393130df010001	\\x67c91e4b0903f5d95f39a9e0d68af52e4dcaac792fd56b75d559d4c9a34b875361a19ea07de5cbea4bb7a22295732e034a7d9282db49f3a12bdbabbed13c0901	1640170956000000	1640775756000000	1703847756000000	1798455756000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xc27774139e4548b624057c0ccf0e4c51a089823d9884ea969d28078a70822a4ac4b658d1f1d99d7857ab70f611e3c934f67bbf3232aeba1bc698c72241fa9ae9	1	0	\\x000000010000000000800003c3f190f7b1a377933050f7d3dec94090f453f204f91b68591e475406b218fe03605d1dbfb88062f8d9d22471425a9682c5de5a0fc73cc6edbc17da54e25ceca04db357961eef8f5c50bf50af324fcf49234f73712ad391019821068ca414b2e3f90dc58f4c3c68bea52e6461ec2bcdbcd6eedabc69755620ece4986c7fd643ed010001	\\xb792bc932abce9afc7c83f81ea1bc1f8d5f642c51246d19cecff28ea501f00b862c2f3ee31418521b5828c5de26ad8149e77db6978be3e15a4350c47ad39c60c	1654074456000000	1654679256000000	1717751256000000	1812359256000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcc3b25e6f7680fada78206283dcbd4780dd91912e07e8ee8235e57e6fccc8b4812350b1703f80076fe5bf84754d9b6bf08b4ae88e20fcdef959b30dbf645b040	1	0	\\x000000010000000000800003ebb4af9290e020fa678fe5107fde993ed7794b7f3c3ad8ed540368bf5e5964212babc615716f4433a947ea5fa4defc0b1d1611330172d799d360cea42bc311c2dacb14338424fbc42ecb728233a122d440ed35bd20b178b08d021e321ddcdb9caa40759bb38b13b685c1f2e3d8dcc6272c676dff143599e824cb97d6811fef6f010001	\\xc4b62557c43b573dbed945c64b3bdb7bffe958169cbcb2425b3792d643fc067f7a59fccfae3fc26d5ed947228b60035b37c1dc5c418d126b4f036ea69ece440e	1641984456000000	1642589256000000	1705661256000000	1800269256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd613f92941d6d65e9d5d69f08dcf8ae6d22562ad15845c7aab8edf60b41b63772c73175c51ab992fcd41569b52f9ab8f3c8d50e3e8b03bbe08b516898dbce5cf	1	0	\\x000000010000000000800003d90bb4354e7c6942da0a6c41d308f7ba0d39b7a0f815d256bfc300951097b7bc36b69e1d0206f858b5c6b78ef5d5e92d399f5721563b83a3b3e6f62d7f299ebd1e66ad0e482cab51511e605b9fa7c70e385b8743478dd9875e5ad16faac37a566b8b464f1395602910852cbf96138ccee09282fbd04977dab2a0d38b67babf75010001	\\xed855ec75f4a9ba3ad2af57171a83ba23f4a54f88edaeb2e8173439654f26d52c1b714ea4e1dcb0aff13db0b1ec1e19221bf0082526376dde82d580ec619b70b	1661328456000000	1661933256000000	1725005256000000	1819613256000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd8df0f1a16bd0194c7943b35e4ef9904e2d785e3760fe4f677733c8a48712e195a9b9688ca19a9741c0fbdef33446f9c16271fd8d66e82b3d3214b1fcd116b3d	1	0	\\x000000010000000000800003e38236df09283a233a301d4a3dad95c7120afd69ccc103b3c61e94cb8c96066412053daf9a160fbccf86e68a5e2158a3319478c569e2240788abfc08b108f57594dedf8d038ba01600b0b050d00480f8c957b0f92d6d87a747b29925c5070821e12935e2731c75677100229cfd727d5be877c7fed7d01097cbc53db6306a73e5010001	\\xf597ffdb2add20095d9cd12f03ff7e15a7f4aeb2c6a976abe1dd271e0bc69a52f5d99ec728f343f3e4376152d3e30efeee8997877d7ae64e7cfb714c1c85cc0d	1660119456000000	1660724256000000	1723796256000000	1818404256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xdf3f4e28d2878241d94d1020eb841a5cbd1dabb5881ca5dd9d1d81bc977dea38dfc9b9dea3bae334cd4ecdb2ab50f5bd47e3cba2b904b947ff82c5c138007c00	1	0	\\x000000010000000000800003bcc780f54aaf1bfd181ea4a641362f3df8f2903bac1f2f13a91d689dcfb2822c7837c9528958ce4d4014b48f7f441b0afc2ccf0fbe0b532696767f7f6b3e0583ad6a98475803de28408793edb6f0b497c876ddaca3fc3d228660e975b671b80b74977d0440d71a15705e283de615d797889fc416e8d423e7cb58951d249b443d010001	\\x3906378aed7b5db33057f2919da266b5e043a392023a1afb7b93c71b756d4bd74b0c5b1a23413430e48586f18c3a8251663727b10a8f5dae703f53be58f9e70c	1645611456000000	1646216256000000	1709288256000000	1803896256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xe23bfbe2b491983ab9b1a760b57655889ee3694e67837d6f83ff6fba331c74c7402ccb440f95126f441e44494d32e22bcf55c0767054e9ffd4dd79b00edc2163	1	0	\\x000000010000000000800003c9d23141e7990044b7d3294f91d4856654b0c8e6549bcc05ad3ed7d5daec4d541314f95d430188054cb3e9857d3d4aac157369809547b2a6110c2223aa0a1a2605e8932744c4835cf3d36b1c55b334a36c375433504bb63ac50f3656da0659c546d0f5db3270a7d0e8477b450281099a9cc9008b7f99b2ece19edd31cfc45a6b010001	\\x6f26f7535f794b809c866d915d9adb63d918e45482966bda25e41885bf4459e921387fea3078375cfa4842be88b4b2642141a763e2e125e398e50a981e270e09	1655887956000000	1656492756000000	1719564756000000	1814172756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe69fdbb729f372682c05c36f5352d0755479a121ac2f88839dffec99ce1bcbf1f0062898f791bbf7b0c9f85f5b2abbda5365b1c0eca531c221db79130d47cc0f	1	0	\\x000000010000000000800003d7007c5bfaabb8d6e86d2757b205f6c6808289732b380c92054427a776a1ab0e3b13ff0e0628ef434651f89085edb28a41c2a0961f48989a39c29344f03de01209ad7f3efb10a0192e9d0b5fc33d0472ff1dc8fbb9f80c5b47ab93161e7d087cbfcd55888899326bbc744826cbaf7e0de705a8ba7c4a7a8c4f4ae8160cefda03010001	\\xe6580765961e830b1542334b2edad760cc9c736186323603146cbc56d6872b5cac2b1e7f8339ce60976ec5ad8165bc3a39d274d39074d96898ba9c0cb4815403	1654074456000000	1654679256000000	1717751256000000	1812359256000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
413	\\xe693d0ff8ffd3eed1dbaf7f54e6a3e5ea2b942bf601b0f6a9b5e79fbc788c9dcfb628148fb5aabf2f671d34de29c9491c96fa59d2bddd15d5f3b63ecf7372cab	1	0	\\x000000010000000000800003d8e7310a8585202637cae6f0836fff1177a89435f4fb3b4852d0bffc8ab6bb6e02f3a5e657009d1dc354a5f241672f4a9923602d0a4e438874269e1a119a31820f55ca35ae56f78f424e0b0205822a9895dfb974306cb074c33d289903c8643fa5b3b5e4d33b43d3394dcadb4075290a0e3a5b77cfeb40bcf8f56bace23a7029010001	\\x7a6880f64c1a2a91477eecda06e9df4bf7bfd1d8d3f101a2928ed29db8f98b92ae5f898dd994606d6afdeff73a209d68234571cb2be9f0dd0752ffe40c4b9c04	1648029456000000	1648634256000000	1711706256000000	1806314256000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xe89ff11d5606e1dc7064b4d05ce60f17439e70bb89690eb56ac02167ad5525b4c451319c0b0b358b5beecc70e010d490700997c9dc778ce43ba3d1b7f7495767	1	0	\\x000000010000000000800003bb9102d44a679b4cda2aebdf89a30ac10e6acecb56047b5fa0272b3e59c19860244242991db2492a102c73e595735bc46b165f53fb864c7b7e521cc9915cb167431701d91ac0e408898a3792ccfa561fa9c43b7e82545f1e46e6237b34d5a7693f7c71ffc4cff0ce61aeb990940c651e348b2a0424c161555510cb8a057faab9010001	\\xe5fe56fa3aedd325adc8b38fbb93fdbbe7bcf99b1dd777962eb4a8ca3a04969c5b870e0ac50a8addc07a8241ebd7b326abbdf6c20d82a29fe205682c157e2f0b	1651656456000000	1652261256000000	1715333256000000	1809941256000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe937880014c3b3e8701897c1f02fb6983228d04b4917700fd73d94d639407744b0f0797939567355a1c8ebaa2822ced6ffb53f6e79daefc61ffb98eaf8907e32	1	0	\\x0000000100000000008000039cc2223ba0be19ff11a7a3e544c683611c4c45967b9881626758f5f1bbb35ee9cf44ef74c7d589cb70bdbd15be6c46f2ccab78dc2880afc1360e94ad6a5cc6f5a7eb3a0d491d00d1c5d28b8d86aa8787638fa65909b4e088f50e500858c9550ea1e4704106aaff8616d66ba868c46057f0833474946147f84e521e6f0f831225010001	\\xc1412adc84e2a1cc577c45ad929e77c294b6da0c1fa8a2cdfebf53310b5dadea2d70b8990fcac1238f0c6a00b9723bcc5f68a22c467ce99d481e4cb5f4534008	1658910456000000	1659515256000000	1722587256000000	1817195256000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xee3bfd7d28b5e4d41d16b01b3dc0aa92c97c1cb329bb68a2d0f19faff61b5368745fb3d68b950495483eba7aa7f04d4c88f03612b1b09bb6c5d41e060dc3c341	1	0	\\x000000010000000000800003dfc6203da1ce5edf4ad66cfec73c706201e06f0526df55982ec9f4d34bae403650b25b4f332815e8db672ab2b8532d770e4ae9a602f19891bb0747da7068cba890786e3d8047a7fd3f627d127fc0c172c768eb59e750ecd080aab0237ac6ca115ef02b46ab5409c23158d5f58d1367afca56a30e1d39b6283232c8a52d08ab87010001	\\x6516d2b894ca8700a9db11eeec636db32220e000465978ce8b9224a4da349d6ab7055627b016a28d2368be3f971a44f4d1b9d95b9ac48b1b977ec72b9edc2e02	1642588956000000	1643193756000000	1706265756000000	1800873756000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf1630b1dc4cf665099823e322bb74b820747af634005c6ee68126446fc98b4343ece34965f88c994f7dd9b2292328b9b1badc3fd71e562e03132216015ebacb3	1	0	\\x000000010000000000800003a6e4817a7a6416492cb065e50ddc2f51130513597344966b016c63cff379fe4a61c591780bf1c694ee04a3c05b7887023aa646f563dc3f97d5d82dd1897aff2b404d1711f5318959a4fef59aee227c30ec078f0a62a682a432ec5f3789c3e94c88fe3c38fd6568e6a4c53003383bca8d24220226ddf016c2ad079312d09eb301010001	\\x6b7a342534df357287084be173a630c0d7406ee1d62c2f85e32375bc5c4479f280a78b81c10e4db4b06c543be90772d3acae8804e3a15fe8cfe1b08a0a64fe0f	1652865456000000	1653470256000000	1716542256000000	1811150256000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xf26721fdcb27f8c379d0f301218f964e19e6833d8c5a4ba8dae8864a6e5f70ff0edd9758a3d9a8f0afd8b4ca676fb3e73e66ebdff8bf8be79c9a9d4acb6e7e96	1	0	\\x000000010000000000800003ad3bba6b1de7ef662d6d8558fe2861b2d45fdce58939129ef5ffb9c67ae31d974e68c5c48ce6b5c27ccfa0d67a95aac14374f3eff627b88e39b2025f086974454a1d2e7290c90b2da6596189c492c20615bc289ad5d1baaf9dbb35edf246f28e20d7494cb82bee401d64e2236cf6f49475955d55fae690aa9fd44f58abfbd3bd010001	\\x22328dc3582d6b8256f65ae0fed876478b36700e0fa9e2f135f99d1c9aa49116b168074f72b8c7d6a7830b9d17cb0210d72e59051a88867761d816854fdfe30d	1665559956000000	1666164756000000	1729236756000000	1823844756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf6eb12e88486dc2661b79c211ccd633cd2ab809a2c7a5784d24c64ec4295c66c505d1b9f01d923ef15efe9b4500f9c4e7774bad3d3b8a763d767de37d7e90289	1	0	\\x000000010000000000800003cc5b3446bb2f10a75cbe7461d8b49675d3cf93e6414fe9c665b5fca22d83e99937b2ab13e096cc453bc75f91e4ab959ef871c7c346318174fa06e85c53b76f1bd93ab8078de7451a959986dc5a55c00691e126d458c6ffe9b28e49914bee26f7de75e68bf2bed520f89a68bf2357c74a30b7a8fb7ba6b63086354e3bd2e34a4f010001	\\xfc9b2b5a44dd3bdc1b833d0a0d593cf2ac9a028d01ed5a39d3c08ee643713e708b14680d84b576b05a9e1bdc3fe3fc9e20964e861f397b38ce170968a0b6b605	1643797956000000	1644402756000000	1707474756000000	1802082756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf8bbcf078acba1bfabc9cdb24d406c99160fc299864ba2f0e08d2e11053a5c1ac560c934c85b8f95b1dd21570f8c144a96ab17c068707d377d2aa65474e0d2cb	1	0	\\x000000010000000000800003c156de84ac7dcd7343df5e68080cb7fe0cc4b7992b3c32abc433174ff414fa7a0ba6a8456b3a38047a1ace18c5d4e7670d33c34390cd97a03ac23feceec30208ac22cdbcd3b0777cfc6590005d2378845fbadce981ff7f2281a8c4d5226ef993d60a5223c9901cb3c6c1663d478f09cd460b9e50eaa3d91b054b137618821a5f010001	\\xe73434bd13123810727d81c025351ca0b0a257a1a53b4720a680035d9ca6f998050d7704f268aec67fc0c3c6fbd35e1bb5b36528a66228c3316467a2c6b0540b	1642588956000000	1643193756000000	1706265756000000	1800873756000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf9ffd3fc226bfe4a15819683d4c7e599f6300438205c472f5942173467598eaf7e48025ce463c02ef5da39009ba648a97d12b9c7da84fd7bbdc6a80359554275	1	0	\\x000000010000000000800003dfaf008cdaf69e223d2f232fa7c08878ac00381613038bddb9dbff3bedde195977f4760d9f011a0d0ee0fd612f8ed4d078894fc64dca4dca94ac4da6ad4a5cb987c71fff131222102935fe686284abffbb40562d2b21004d4c4a46f25041f85ec93cd1ab8993c757527f00b04d44a76f96472eb7c6ddebd030b2ff740b0c9751010001	\\xa21eeb9babaaa4ffb30d2a459022870484bdcfd93a2374824a259a64039acce939248abbd40bd16a19f95c3bfef5a4cf75c70519914d1f3d9f335d9bef417e0c	1640170956000000	1640775756000000	1703847756000000	1798455756000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfabf6eeab8d95d3457312a3058b60dd105204f9c0ef4aa65fb97289fbdd92327544ba4ddf3e9bbf979f382910958f0f49dbbf7419b33021b8594696216756142	1	0	\\x0000000100000000008000039bb7a1f363fdfeafb2acaffaa341b0e124bd429a43b05ee0f7f8bd071cdbe80964525e2cfb1aca98aa80f40f86602ddc15c82bb8cd971c26f4ea5e1e56c12105cb06f4940c181cc7f3a16c56317792a4fb2d93c19af34610726005dca186c30a8d8805e1db2b88b45a03d3877435c04787a66c40d7fdc559932243454acea7f7010001	\\x76fdc9af758e086c560b1e19e0644939dd1d8313c272fd69d1d38af35d3a8b9788eb049e5d6eaece474cdbb146c36fe8e1d1a396b26d627f76740a42e018a10b	1659514956000000	1660119756000000	1723191756000000	1817799756000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfdc7568f62f446c0636e5e9d53c17ac31276b260bdfa08d1f07f666cd3b625c993342d12789f39bfc75db36e9905ac0cbefe2fd48813993bcf1086edd957e9ac	1	0	\\x000000010000000000800003bc51749fbc87878d9c673bbed2d8dcfaa5e3373a3a876228e1502ed05128b36ad1f3a80c4ccef87c85884f6b7497dc0df8bd21258b3c481327392c660158f3b0b5fad0166b52ee1134e595637713d625855834bb70f2137eaaf79a5746d668ebf43d871b493a58e1d3b4e63e330a20de614a0c0cc5f8c27d68b54738fe5f3f5f010001	\\x5c1afd24fdf01d74604706fbe600469bed894bc811ab725b58b2e6fc3b7a4fdf00dd43b9b82f578d52de5dd3a909ac36c9746b4c72b19294520cbbff12ca5f0a	1664955456000000	1665560256000000	1728632256000000	1823240256000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfedfc59f4e75a5b0a1f39f9ce2204de03cba01e5d78319ab6bd4db52e5db47f8dc7468d2d4988a4fb9924c779d5cac27137143f38380d5fa64ab86e904f6c386	1	0	\\x000000010000000000800003dcda1836f0f5d2c64dbbc6e432ebea8db02742079562430a57d8696830627ff9699b6aa3f955a23951ed0d91e9d4764bc9ed02d83c49dba4bdd211c54ee780cb016ef2618a94dffbb406cb66bcc3ec44d1797838c0794e360fc0d7ce8f0c9a09ff8c26fa7c75ae52f4be2191060d3cc9ccc5f155fbb5ab325c71f96c463e71c5010001	\\x1e540ff49ab8ba064b58d470b54a837c08121b51675e478dc9f57e9bf8ae3b3aba267aa8995e9ae41603f6c0b8153d54cbc898bd83b50b15ed1662e841c8cc0d	1669186956000000	1669791756000000	1732863756000000	1827471756000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	1	\\x67c01a980db9a9cd7a3cf99a733c610670862c881f54ba58366e5d931af84d6f24c82c64067a610a20a9eef5256fddd872354eab5d09443a88e3b4ad10d1ea0b	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb1a172323326b5c4db6c1bed27e83249b26d17fb423f1ee98ccde988fc26f92c9a6da1b5d338ccc5c2910e539e9597f842e4f9dc0d1c27bf894cab8db6067812	1638357490000000	1638358387000000	1638358387000000	0	98000000	\\x242545fb2841bf533814beb00367bc4c28d640b157932bf421f4e4f290361ae8	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x25a206a83e90b6a82222925599557c83c504b0d5069220ec1068441421e86fe807bb4a5be2128946586632b219528386e99c49d959449432f35c1f51c8733f0d	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	\\xcbd678931f560000cbd678931f560000cbd678931f560000ebd678931f56000011d778931f560000cbd678931f56000011d778931f5600000000000000000000
\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	2	\\x29739926990bcbfa3916f0d801c75a7f646deeaa3dd2576b2278866cb5e3d5e67da5e947972f1417814de44e354e8052a1fe9bc83edb2275bf2d6e1422b3229a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb1a172323326b5c4db6c1bed27e83249b26d17fb423f1ee98ccde988fc26f92c9a6da1b5d338ccc5c2910e539e9597f842e4f9dc0d1c27bf894cab8db6067812	1638962328000000	1638358424000000	1638358424000000	0	0	\\x017817b27cab7f22b88e47026d3aaa28261663fc00b6223673d8bc5d54032303	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x42be41908f5fcde1ebca9fef72afbcc12bf1f056113f852f309ed837c7b8cb1b35a831214b8e97745bede3bac62fc4c4945677133e3e911cb6c41426c50f030a	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	\\xcbd678931f560000cbd678931f560000cbd678931f560000ebd678931f56000011d778931f560000cbd678931f56000011d778931f5600000000000000000000
\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	3	\\x29739926990bcbfa3916f0d801c75a7f646deeaa3dd2576b2278866cb5e3d5e67da5e947972f1417814de44e354e8052a1fe9bc83edb2275bf2d6e1422b3229a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xb1a172323326b5c4db6c1bed27e83249b26d17fb423f1ee98ccde988fc26f92c9a6da1b5d338ccc5c2910e539e9597f842e4f9dc0d1c27bf894cab8db6067812	1638962328000000	1638358424000000	1638358424000000	0	0	\\x039ee2e6b3f3e15ebac6cd6c63bcf3336a8bbb87cc21ecd7b0a844ea51f47b3c	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x2f2c0366991abaf75ac95d48c73a444a23694ba2604bf92c5bacec1a4857ba3ae6da4674bc00e941b214a1fd6e29b041bd137c858313db5e0fa80125e818c907	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	\\xdf077a931f560000df077a931f560000df077a931f560000ff077a931f56000025087a931f560000df077a931f56000025087a931f5600000000000000000000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_serial_id, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1092892855	2	1	0	1638357487000000	1638357490000000	1638358387000000	1638358387000000	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x67c01a980db9a9cd7a3cf99a733c610670862c881f54ba58366e5d931af84d6f24c82c64067a610a20a9eef5256fddd872354eab5d09443a88e3b4ad10d1ea0b	\\xc90c5f0aefbf12df7b004933b49e8885b4c7063b7c4d0e685a742bd1c078b5d8993089c6885b182b34a92dd71c8abf7c3d04cb4a05fae50430c828870ce51e0a	\\x1fa29b2c1ab591bf5a7406353a500725	2	f	f	f	\N
2	1092892855	12	0	1000000	1638357524000000	1638962328000000	1638358424000000	1638358424000000	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x29739926990bcbfa3916f0d801c75a7f646deeaa3dd2576b2278866cb5e3d5e67da5e947972f1417814de44e354e8052a1fe9bc83edb2275bf2d6e1422b3229a	\\x3ae9d6ccd82a74a49afbb992236c7ec8c7f4123d58ed5321ab32fb30a86eb32c5715a69dec0a4fbb42f17297479e3112432dfd5ad2adc0186f8834e20e8bdc03	\\x1fa29b2c1ab591bf5a7406353a500725	2	f	f	f	\N
3	1092892855	13	0	1000000	1638357524000000	1638962328000000	1638358424000000	1638358424000000	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	\\x29739926990bcbfa3916f0d801c75a7f646deeaa3dd2576b2278866cb5e3d5e67da5e947972f1417814de44e354e8052a1fe9bc83edb2275bf2d6e1422b3229a	\\xcb7eb4a3b8da62e51d9293b86153a9ad9d82071306766d78f90f7c7f651d7bc3bfa8ae833459bb23314d8a30af46cb856dd6f2417bbc16d345982440f6616701	\\x1fa29b2c1ab591bf5a7406353a500725	2	f	f	f	\N
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
1	contenttypes	0001_initial	2021-12-01 12:17:36.546079+01
2	auth	0001_initial	2021-12-01 12:17:36.655612+01
3	app	0001_initial	2021-12-01 12:17:36.727321+01
4	app	0002_auto_20211103_1517	2021-12-01 12:17:36.73005+01
5	app	0003_auto_20211103_1518	2021-12-01 12:17:36.732628+01
6	app	0004_auto_20211103_1519	2021-12-01 12:17:36.735591+01
7	app	0005_auto_20211103_1519	2021-12-01 12:17:36.738151+01
8	app	0006_auto_20211103_1520	2021-12-01 12:17:36.740677+01
9	app	0007_auto_20211103_1520	2021-12-01 12:17:36.742918+01
10	contenttypes	0002_remove_content_type_name	2021-12-01 12:17:36.754005+01
11	auth	0002_alter_permission_name_max_length	2021-12-01 12:17:36.761829+01
12	auth	0003_alter_user_email_max_length	2021-12-01 12:17:36.767524+01
13	auth	0004_alter_user_username_opts	2021-12-01 12:17:36.772941+01
14	auth	0005_alter_user_last_login_null	2021-12-01 12:17:36.778563+01
15	auth	0006_require_contenttypes_0002	2021-12-01 12:17:36.78072+01
16	auth	0007_alter_validators_add_error_messages	2021-12-01 12:17:36.786248+01
17	auth	0008_alter_user_username_max_length	2021-12-01 12:17:36.796418+01
18	auth	0009_alter_user_last_name_max_length	2021-12-01 12:17:36.802453+01
19	auth	0010_alter_group_name_max_length	2021-12-01 12:17:36.809851+01
20	auth	0011_update_proxy_permissions	2021-12-01 12:17:36.817132+01
21	auth	0012_alter_user_first_name_max_length	2021-12-01 12:17:36.822844+01
22	sessions	0001_initial	2021-12-01 12:17:36.84183+01
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
1	\\x27e63d0d3f963e27173a83271a47ec8da56646a6bd053cc7946c6984e1ca7698	\\x060ed753f34a45ff23257ad93d785f3d4264f5967358d4e91a63b1db669bb2e8b3311caa1fae01bf687bb702fb56193698f084587fdbd8518420d382f0c3870f	1652872056000000	1660129656000000	1662548856000000
2	\\x70502350868c7e19375624ad75a1f1ecdc69e18629c84417306be0d5409b3881	\\x9f790bb955c15a876c2f5a0b4258f8a532ee68ec1193d0da67629e056b5df96f125890797768443ddc2e1b546c3aed73fe239afa2b42a892024f453d67c6740c	1660129356000000	1667386956000000	1669806156000000
3	\\xf52833a8942845e322799dc4984070712c3bf03ea2c4d5ed18bfe52bf08d1ad3	\\x2cd54d9edf124a110c65216131225af98c877bef63e4651e147e6aef50e7f45b2fa17277e6083cf6fed33a6c7fbb9e5d90358bc758e56f5670e4b478a1e1a805	1667386656000000	1674644256000000	1677063456000000
4	\\x55fe9579a6f903c9d1a1e5c220c7508d62943fff4cbbb55be43e02e820f64abf	\\x7659842853043981b9a2ff77359dd91381aaf99da946edebb5b94326047b3b7dc30add1ee26862e32c2a765b8d79836acc1b8e434ee1d2cbff464dc093187309	1645614756000000	1652872356000000	1655291556000000
5	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	\\x83515e8f332f28b8c47b09e2a3f9d70fa2fec64f8b791bc6679f2e511b617580dd91b0d35a5b24891f9e031c1a4f71efba8ba914165bac866422c21930da910f	1638357456000000	1645615056000000	1648034256000000
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
1	\\x2f31fb5f4bde01397f7c0654920bcf1939feb12e452181fa392ce1e5deb48085	\N	134	\\x000000010000000055e4e154ee5e537bcaf2e0292ecfc7f501181790673b69f4c6be73b13b81691dfb93d0eb9d8e2779552e4ea5c1d7eb0fe0069ba0aa9881cd10eb2fbab6dd59f16b32dccd33d41adc7ad78d2890d7e7ddcd8875b6d4465457ecedec7d56bc11152a2102ad91a2c129587d53b839d99d00f547aff95cd468e71115fc2b4a7a3fe4
2	\\x242545fb2841bf533814beb00367bc4c28d640b157932bf421f4e4f290361ae8	\N	50	\\x00000001000000008320c96e8316530abe34cd0de33efac38b92442eeee92e537914a31b328ea86ee99d212dadb62b07014b5fb4459ed8280677f4531ef991239fdc07ab903d035c740ae17b1c73fc39dee1781bd005616e7d1fdcb6d886e8ee7459e002320036cc907d79306e54bf6ef1ec033152caa6f29e606a3064528d18e16e708de8ccc2b3
3	\\xfa4d29fdfddebaa895d4c1f9e48bd04f84bd7ddf7294a3ae6754c68fa8aa1106	\N	128	\\x0000000100000000b9a9b9e67e9e4d1b8a2884a73b3dcd17e2192963e4fafb1a5ae07d83dc9f81bfcb6df5eb490f356d8b58aea088c357d5f9eb78f82be978e16393902d44afc2251f7085e85f4c60af7afcda6803986ce101fe30e20e082c51f5ba42768f47b9ff62b14e359d9dade860a4fdc605e984604dfd23219d4ae63244d9b59694c0d2bb
4	\\x2894e8ec662f839a21142448e17d2462587b56f4bfd33758030b9b6ce439c73c	\N	327	\\x0000000100000000643ca359e4e116c68133494817ef93e85244b76affb223a67e8e04e61133fb7ae978c4fa9c3860740d8c1cf476946533301a96c605780cafebd0457dccf8b30313e5d1fa8e4ba79ae2c70309cdf3a7e5132595b6c80aa37687ef9cc9d3abaf4cb91de19a513cab3005987e1b8552e57d7f76634050d426e05d881d32667269c0
5	\\xaa69d0881f1daba85f647d3f80ae81eb82ab8828b510c2c27484ad892dac0fc6	\N	327	\\x000000010000000035c9a553d6829b491d4e39fe48ba3e39c98a864ef02e757cf15980db2fcafe1e73dc6578b4fc823e499265b0089fb661cb58cfcf06c03a8635f2ea564ed110902c7c2868154907067d3ffed24052c26781bc1588262d1459dfab42c0827113a4ec1d040061d02350c7c61a68243fb4e813b9694b8f57dc8b1972697e38c1058e
6	\\x7676e9071f9c2f94199f96fa4043a89104cdd98e581b573f63b31ea87dc877bc	\N	327	\\x00000001000000000d5fbacbc652146e7dd4183ed4858d43fe0698e22db322de13f5cab866760cae02badcf111c78383730d7f7468c3789a9788806b68879851e9ff8920f539c4779a07d640d07ba90ab52edeb1b64815a354def3b9879e082f97169a3b9d20c3137ee7204617f36ac54952899f9fa2fb421060ba4f27ecda42d21483bac4190776
7	\\x9ab9399ba47d6064a72af88edf2a134c9a4df56ad024e25e8d6f21f8260c55f2	\N	327	\\x000000010000000094dd5df5cad1f4e67956eba2f21398a6f0fa8cb7e6a93e0399cc3e0ea43576b35db545703e5d3704449c9755b853592aad3c09f226e8974e811a46615cd2ec5d944f8f5bbe36a7b2cef0a7f55e0bf31cf4d0f41e8dea2814ab3cec8d97b136e0c7f2a50d9d0539740d0e1000199d71ad70d88be74d0db1eb5c27fb848b3eb6fe
8	\\x65fc1f504037a2010f4c1555ba19797aed8f8bbe0260b1b6c6c5d96d30978dce	\N	327	\\x00000001000000008750865afc704665c93ac3fbc4a4867f741ec309b12a0acdb1c2f5e271922a10c7dddb6c0c72968094752a712b63003e31ea2165e5e92aae99ba5fded573eeaa407cf1b192cc54202b01d85c973733b288da92af0675e16c2d9ae43d44f3af4a886c355088577c3c2de0c65067e18dfa363efa5982909e025e1673d97c248e
9	\\x9df1c1987ca004902502eba001e5ece91d87dcee8d1c268126aca709bab54511	\N	327	\\x000000010000000010f2dae15cdb1f7c17c28044c404d130ce4a7b6a2997d3fe06a70da87200a865a37922476f30c009d026595d7a5444d688aeaf28da65d858e1bc5ea2405203e484649843fd754fe98141e3bdb360e27ba9edad8ba1b274bec2479969b24c6ece7171deca73befde533c4fdca02cb19a96bc5aa9d5ad6abf0ef41f6c364265605
10	\\xab233237df0ccfbac413cd517deef4849e767a5e1b68bff4c8e135376e0a4f71	\N	327	\\x000000010000000043b7000c56f178b955261f84e3e9a40dc57d6ede3f59684dce7c6ed46932a490646a936e114e1bc5aedbabf3d04091c6160c3fed96cd8e7fad8fc1b2025472c6da560f770a94af67377e2490a147acc256d1aa6344c26145251692e0d7cf1360e21aa35a62574c06be2cc355b2a64ccfd508a05ba5d8873d33af865e007498c9
11	\\xf92f9ce55834a5e73d84f312b247f54e0e65b23c008e812d19ffd0d3ff610bc6	\N	327	\\x00000001000000001342c231f96606866dc897403be1ddbb24418ebe7b5008646b778e9052aab59880293f121b719fc62922077efa830b4e47b0fb1f10608961a2660d30ecfe19fe0595c0008091c0f88a048bd9fcd12dbb8271699c5e5525ef27f5b30db4a23c94b2b7999a610d911ae26d1cb5d6fa1f86a9f4ce4bf8d2ef9d7ea16bce6d3dd6d4
12	\\x017817b27cab7f22b88e47026d3aaa28261663fc00b6223673d8bc5d54032303	\N	303	\\x0000000100000000c2d83f69804f920843294dbbc8a4093a750a246ff572906b2a0bdd5a996426b58b81b7cfda59391713f71bda62e62b6bbb38e9d6f41473f41ce131cbf3a56dd254a8a3da8860d09a6474982f8a2fa3aa2277e59916098c4aad6dc9fddccea66ebae005da133dbeb081b8e46e281e7c0d0e1efda2921674d9c3f88a2222bf715a
13	\\x039ee2e6b3f3e15ebac6cd6c63bcf3336a8bbb87cc21ecd7b0a844ea51f47b3c	\N	303	\\x00000001000000009629d42a7757cbc22f19c22b0a59acb3866588a0627479627da9b4a1d906fa340f952d59ff3e996df96e7242e3b10858f6780034cc98351274af109b3ed4003492b19b7b3c694e55e8abd0dbc28ccc14d65fd8966957d653805d1b23968ac7317c7cac58100fbaabd512cda2eabab615815d63111d5fa2efce63c38cb817adb1
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xb1a172323326b5c4db6c1bed27e83249b26d17fb423f1ee98ccde988fc26f92c9a6da1b5d338ccc5c2910e539e9597f842e4f9dc0d1c27bf894cab8db6067812	\\x1fa29b2c1ab591bf5a7406353a500725	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2021.335-0143MZP748EVY	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383335383338373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383335383338373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22503647513443484b34545457395056433346504a4654314a3936533654355a5638385a485854434353514d52485a31365a3450394d5644315051394b484b363552413847574d57594a50425a474751345a374530543731375159344d5341574450523337473447222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d303134334d5a50373438455659222c2274696d657374616d70223a7b22745f6d73223a313633383335373438373030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383336313038373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2233393257584b3532375144394a514a4a44533456515a4a30304d37425256393930364e585438303139483536355a454a34464347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533839315841374a423430394e4a514242303958505635534459353453365858565a39474539314d4147425744414d474b595147222c226e6f6e6365223a22333543424e3948444e39475645463339333241465a54345631374337573643483633584e41434532395753325347565650364830227d	\\x67c01a980db9a9cd7a3cf99a733c610670862c881f54ba58366e5d931af84d6f24c82c64067a610a20a9eef5256fddd872354eab5d09443a88e3b4ad10d1ea0b	1638357487000000	1638361087000000	1638358387000000	t	f	taler://fulfillment-success/thank+you		\\x87a598daecc8afbeab518fd6fb45caee
2	1	2021.335-0388A00SX1180	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633383335383432343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633383335383432343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22503647513443484b34545457395056433346504a4654314a3936533654355a5638385a485854434353514d52485a31365a3450394d5644315051394b484b363552413847574d57594a50425a474751345a374530543731375159344d5341574450523337473447222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3333352d30333838413030535831313830222c2274696d657374616d70223a7b22745f6d73223a313633383335373532343030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633383336313132343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2233393257584b3532375144394a514a4a44533456515a4a30304d37425256393930364e585438303139483536355a454a34464347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22533839315841374a423430394e4a514242303958505635534459353453365858565a39474539314d4147425744414d474b595147222c226e6f6e6365223a225950484b4d4641324638375a563636593943385033345332454437413759373635594a4a384737365756425347484446314b3330227d	\\x29739926990bcbfa3916f0d801c75a7f646deeaa3dd2576b2278866cb5e3d5e67da5e947972f1417814de44e354e8052a1fe9bc83edb2275bf2d6e1422b3229a	1638357524000000	1638361124000000	1638358424000000	t	f	taler://fulfillment-success/thank+you		\\xaedb0dbb5c25b0f319d9a03c89d378f0
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
1	1	1638357490000000	\\x242545fb2841bf533814beb00367bc4c28d640b157932bf421f4e4f290361ae8	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\x25a206a83e90b6a82222925599557c83c504b0d5069220ec1068441421e86fe807bb4a5be2128946586632b219528386e99c49d959449432f35c1f51c8733f0d	1
2	2	1638962328000000	\\x017817b27cab7f22b88e47026d3aaa28261663fc00b6223673d8bc5d54032303	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x42be41908f5fcde1ebca9fef72afbcc12bf1f056113f852f309ed837c7b8cb1b35a831214b8e97745bede3bac62fc4c4945677133e3e911cb6c41426c50f030a	1
3	2	1638962328000000	\\x039ee2e6b3f3e15ebac6cd6c63bcf3336a8bbb87cc21ecd7b0a844ea51f47b3c	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x2f2c0366991abaf75ac95d48c73a444a23694ba2604bf92c5bacec1a4857ba3ae6da4674bc00e941b214a1fd6e29b041bd137c858313db5e0fa80125e818c907	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\x27e63d0d3f963e27173a83271a47ec8da56646a6bd053cc7946c6984e1ca7698	1652872056000000	1660129656000000	1662548856000000	\\x060ed753f34a45ff23257ad93d785f3d4264f5967358d4e91a63b1db669bb2e8b3311caa1fae01bf687bb702fb56193698f084587fdbd8518420d382f0c3870f
2	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\x70502350868c7e19375624ad75a1f1ecdc69e18629c84417306be0d5409b3881	1660129356000000	1667386956000000	1669806156000000	\\x9f790bb955c15a876c2f5a0b4258f8a532ee68ec1193d0da67629e056b5df96f125890797768443ddc2e1b546c3aed73fe239afa2b42a892024f453d67c6740c
3	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\x55fe9579a6f903c9d1a1e5c220c7508d62943fff4cbbb55be43e02e820f64abf	1645614756000000	1652872356000000	1655291556000000	\\x7659842853043981b9a2ff77359dd91381aaf99da946edebb5b94326047b3b7dc30add1ee26862e32c2a765b8d79836acc1b8e434ee1d2cbff464dc093187309
4	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\xf52833a8942845e322799dc4984070712c3bf03ea2c4d5ed18bfe52bf08d1ad3	1667386656000000	1674644256000000	1677063456000000	\\x2cd54d9edf124a110c65216131225af98c877bef63e4651e147e6aef50e7f45b2fa17277e6083cf6fed33a6c7fbb9e5d90358bc758e56f5670e4b478a1e1a805
5	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\x9a4e49d76bdb5b53546be1a8eeded796b4df3d3dc4258b89a6e3b3dde78e3f07	1638357456000000	1645615056000000	1648034256000000	\\x83515e8f332f28b8c47b09e2a3f9d70fa2fec64f8b791bc6679f2e511b617580dd91b0d35a5b24891f9e031c1a4f71efba8ba914165bac866422c21930da910f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x1a45cecca23dda995e526e49bbfe40050ebc6d2901abdd20014c4a62fdd223d9	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xcb89eab5e4b8a2e23e36c0bfcffb99bb9436708ce3d68f40d657a5ac3f676fa0a36e1fbfefec9ac4604fc53a04d31e60e571320a42097de80ff57b8700ea160f
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
1	\\xca121ea8f259009acaeb5813db6cb96f8a4c9bbddfd30724345417c6aa909faf	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000
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
\\xb98850eb3f4d89eb4f7cf5d36b259183b27e282bc83704614204c1b8b6d7a859	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1638357490000000	f	\N	\N	2	1	http://localhost:8081/
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
1	1	\\xad268d99f96e90eabe646e15784048b78bcaa5422d1a3117d61a7bbf2728dec284b63b8a3cd68279afe206d164bcae74504e5d0f956fac66f89832dcf8de0502	\\x6e61cd804fc1be92260a0d091be20bad148491a757cd3f2dfd48583e2ab497b7	2	0	1638357484000000	2
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", rrc_serial) FROM stdin;
1	4	\\x148835c5a209f1473490022676d00aac295889f1e3ec8125aa0f2337963dec2075f4a15b32afafbb2c08113a626a3de627064fad742fd406c4cce37a2bcb9a0d	\\x441cceef5fb84ebead80ee330c616dad4f9b9d1c057119a7da30fbf9984f0ac1	0	10000000	1638962313000000	7
2	5	\\x72c58c21e7e77e7ad11ed193aa09b84ecacb3540d5e321991295b8c4c9339128375e6f59441aadadf376fc71afb1da3c769372edd37c3e22f3abed9cfc488c08	\\x5b9995aef9257559648238b9083d237040c5f1116fb193d4d682ec4a6b3e0379	0	10000000	1638962313000000	3
3	6	\\x021f241819664b63e5b02e5209a102b65b76fca2190881038f11c83beebe146abebf411ed8260d0e78ef22dc4d065fa30e174f1a8e0f94afead7340d1f338300	\\xfc218df2eaefe171bff706f32934a64fbb43586dd878ae44a30862d382315586	0	10000000	1638962313000000	5
4	7	\\xc1a12095f95d74c14f03162bd7748f866f1cc79168441204680cd75150e6157dbe16988010f0a1ed3bccc7f72df2224d45be104f660b011a1d06d783cefb4e02	\\xd3f8f1512a9f5b750f791e9adf90107343736a12301c12c58e73869e4f70010f	0	10000000	1638962313000000	6
5	8	\\x3c1ac32db94f5dfc71ef564dc334ac8e58547e33fb303913f6dc2f6058369a5969d4ff61a5708780727d7f9061d4de492be43e72891a6d77a50aa27f5cd51003	\\xea46e660307ad53138e872488491c253b414fcf93baa931db48029d57a919b29	0	10000000	1638962313000000	2
6	9	\\xfa1a7e7d4c5d1429e77069f25e9ea463de6804841dfc5992931436cb0e98258c0784e7ab4e731c58023d460cdd7a56cec29c604dcf97f2246b92821d72507e06	\\xca1a325f2d477ab60051336096d3421c87ccfc94ccb3f37637cbf28abc618c1e	0	10000000	1638962313000000	8
7	10	\\xf05ee78715ec043e4a94a16f604cd5645fbdeb0a669fc69d6d34d42250a3e8257c22267f66e4c6a6f76668cef95886d33c1cbcef4ff38af3b12c182bf21aa60e	\\x77780d9e8794d023ad8c577b9fb4667b1bc2f6e3f27c40024b1759cbedeaa3f0	0	10000000	1638962313000000	4
8	11	\\xf61ced6028be03fa04ebd87ed2e92f1004438c9b858e584881d5edd78a026a59fad3c1ec54c2541111f8111b85e3e6b3e7a5c87243ba8cbde81384e6e6bb5f05	\\x53ac4f8d1c465522211c9c3ac5f3a81bd83c4cf61ee5a878c1885a26b250a993	0	10000000	1638962313000000	9
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_known_coin_id, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xdb02fd497731af48657f0ecf494f6dcc19a9da1aa9be0d882228ab64749caf90d0c515a00304944d257d80853d787624d8b39401f4eee7994167792f79fb4b1a	3	\\x363e552247e6829b1c9a46d67a80a62be7f22112c69583a22254cc238f4474c2a21e4a288cdfecbc90fd9954208d120b9687eb88896af6f859a9cf2288840a08	5	0	2
2	\\x734512a3abb5df130a5f0a060b47823dd3b87bffa6bbd1ff4045fe3552f8840ef8ba81693db46f165252bacfb64ffe92c1b79a3b5b67f1d9bee93318f37cebc8	3	\\x0610cd2100f002e055f39740f4b0ccecf8614fe03a0288cf01f543191fcbc2790863ce516a0a5b3efc31786b7745d55ce9b80c83eb1af06930db1c949f63e40d	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig) FROM stdin;
1	1	0	\\x8c60f82e249d498556bb3fafdce766b4744d635c2ec0fd601adcf7569c33dc4ff86c8c53ea9a8a4ddb565937592a7e62d1b5e6e74630a7b5333de950196eb80a	295	\\x116f2d1995d0f0f6ec2097ff6b05cd8fb028fc02bd813cb344afd1d921eb890b48ac4cc7f4abed2d5bf3811a858456149dba8042b05d7c4f2883efe26707ff65ff1d627500efc577ca9e41fe25ff44c1e64def37cc5c59eea03f3b87ec5b016417e5a9c7ecd3936a863cc2254c59709b54ab483e3f7a12a3d2a7d2597d318b8b	\\x210b0de8adaea1bcc47b5839863b4fcfb5c4d59368c00717c19132d95db8c7eba6fb8db8664ec8d29e2d6a740a232e0a70ca47d30c744501d33869c5cae0194e	\\x0000000100000001340de92c3fbf016a83f2bf2ddd6c3a012143d2722725fbf8def5b262c0a42118a72857177f643056a5771fc886fc6224c39132293227c9c90f78ee6977828cc3d12eeef2c20451100eeaf60123e0b48430f13711426f6c83f02f37826506a8d23ab41fcdb7183d249360a50c4daefd237ce7358af20629b83be5cefb6347a09b
2	1	1	\\xadd0e4eb792dc64884b80e478ae21f0990987ce77d92ca404a9c1d0ec5b2f6df64b02e0ae6dcbb0a0de7550a727a39e2da92c85eaa39220295ee6bae5e44c10d	327	\\x6d144dc6298643231017ee98ff4adb9de71b8b40e842a3952de93cebabc6b98115c3baad2043f0cbd02dac89c2570a8a04b275352c4802afe7f881d570e41ede35192b5cae46cc4083d326d885db0b6a2b7a312eb6e17d2eacb0b6bcd0108c23d3e7a01ddd7cb928c932587e2f8e5ebf486db824d23c08732ee10dc925c26de5	\\xf9926f95dd7bbafa3747f7bbc43e6790c250a11bb409ac5d42a9aac32b8ca5bcdca9089cf3caf8e00aad2cdd16c902f6309831ca5ba83c1bf7345308308100ce	\\x00000001000000011731ba86de6049685cbfb219c6109cbae2d460f4f1ab402f73cdcfe24d01c40926792aca79c17ae678026949223e7abdd01d5097e6e804b0bac1228f7d730ea7f95db26caf26fb43ce4970f0c541da788082186734c91c9b85968e81cd1b37fd7549a3f66a4c273766ffab66f18876013834e39dfafd3a958cd221176d750bd3
3	1	2	\\xc36904f6668031c90439c323af02b17ff3ed0f1ce6adcfe8d5605cf0f53409e0de741110725ddf7a8e063e5dc8cdff9e6874fa3422880c45c9563776cc385401	327	\\x2c1cd7df627dea108049569f3af4d73ff27154ea79af1e9331938c11877144c9d1f25d23690dbbb997a9bd9f1bf0fd4deef4bd79420885e0ad44985f807f0bae8cffb67c4463e0eb518557a0761e3bff2b346350692629f9d97ca891336bf8931ee7f87ed78c345ce5c59c4c6e1730e44237164953f3d2859662f7660379901b	\\xaf46a32b953c92ea92c9804e9ff3466915d6463855ecde88828fae8548ff9899c16670e11839916711551e3c324a687f8b52fe4552cd73a76c762cdd06b674b5	\\x000000010000000108f6dcab297e4ddf8c7894cbb47fec219f84d21ea549be3aa359bfe384f1e8930e7ef97766d1f7949bdc9e9372d66ec946e76bb2273b2af4b8415d895c802b3b2c9a6703dc0f085baf261f63f3184a051c2faa1efb10271b40e2b1ab240645d2963ea2efcd05ddeb31310760f9ca85ffe98931220a72c32fb6ae7bb1eb479c64
4	1	3	\\xda555db9c087dabde09801af13a472c55c411e038b4580131201014fd71f0d0bbe7ef23639d33ce368495b7e866463d36022690f9f8020aa00e36fd31a45f405	327	\\x21d723cb177d82741270190d3eb96161f42bcf494cc9c09cca9069984c01b5974b19b7968bcd213f680ee6b110dcaed3d024765419b793e3a054dd706f13912bc84b01b036621a00aa486718b164ad7e3d678374f4d0c82661a5451be47e7a24b40a1f8f9221dc139da196dc2c5d96ba9883cf4bfd525ee9cddf092157530776	\\x4597c931c4986793261795782af38833fa3969679b5fabd9069f360f760b732354ec3cf0497b2a2fcba8eaacc7a7d7d6f9d9dd0725b93629ab13a009b5a1b835	\\x0000000100000001601ad8dcce3d1e9d276d816c50f7acd9d11e5dceb518e12c84419519db284dbac9a40cf172e9289511d1255bdc7ef5aecbc29aaebe5ef66ea45013de2f8c2412005ce1cb8b51e63298e722277000ae742db386320930774540bb6797b95d40fd6c5ed0be9c606c60bd84b8456a59e1670c642a11d03d73433fed12c75f79c0fa
5	1	4	\\xaa7d51f32106cf1973e6edf1a21f5b1faf922289af44d5a36484315f8e3cba7ad910da8d7b62b6552cdccbdcb252e9ce99fa0015cd5c8a3be6d1057e76f2ea0d	327	\\x08a1fd92c385ce207037a6d50f3dcf97867cca10374fecd4d26f8fdf8c07a7f17325397deefc0825d9236e1901fd5a9af2bc1580e3bd07c6196762f600792aafc61402e1b7eaa27ed2d369f77baf532a52f5d0512248d418aea9c2e2c5d0effde9d7b935222f092fd3d57b945b31f9bddf6faef65e03ddbdf30b678deab75707	\\xf767ca995d45f49f23c64717c4ea211ea1004e63596eb639b9bf83be85d34f508d62892009ca62c2752b8120fcf88e45d0c004185a68d0d943cf92405f573fb7	\\x00000001000000018ce5162f453bac9ecab2244bdc64ca7b4dcfa7235e16b5ff017d8f9776ecfbf01ec5d8db2c7491de704fecc549a976fafd15a4c9ee7b2655c6eccba1dbccde7744435f646e2959313ec8cc284c3ab0805dd2c40e829c51781396766c7c52b024014731e66bf699dcdb7a34b8ef4ccc71b3638a79937d6229489d1b3eda2725d5
6	1	5	\\x8d8106bc599f1ca5ea843851db908d0d181c7bb589397559b6b65bb0bcf49762d7f1880537ec60130d3f054c628f9e1adcfbf26eb49fc79b7404690ffc419c07	327	\\x8d57015adc46b6066f1708fe456be5a05117be5d6bcce0471b941853f1e49bb875b7d5dfc9ac6782b49569b261164a02382aae180d31cd6233e8a0e9e90977cc11269e540e5def5b341f27f074462924cebaaf2bf20a18ff0010060f88763a7e0291869c45453dfc2a08115279cf26ef235e8051a21b6535a621a82d930e3568	\\xed7258cecd7c66cd207b7e3322774f9e0eb7a7e0d7e20f77070191e9601999690a77111528a4e36e5c40de0b810ee3f606f73c64061965e2106dad5af1921975	\\x00000001000000019b35248497aa13a15ddd596b71a819797dbf2183e3976a4aeb4a99bbf54a54b94dcec14a65018908e94c7485c61844163330127f2478f166ef4d324d3a7b7d68e4ed62692c6271c9e706d3225509df6b52546ee23d0a405b17e6bb2e602ec5c33e226d8d1ffff0eb0231a826f9fc7f3e06439a581b65c2a4bc02ef3625f3a582
7	1	6	\\xa018992f89360af044dde7161d13df1780f56f093d29d598c50f9c161acb48fe3efb4705fc23b2d71940945686c5f06b035baf71378f1c804b9a4ab0fd941504	327	\\x9bbcbaa08aec131ec8e0fb28247c7e5dfb91cfd168183fec4f6ba8cf5c6d847aa6d3788ec45d2169118e7cc1dd974fa05ed7fa8f69ce069649d40854445b9c586d199fc92ef69e4ff7aa4fe86672644bcc0dde56142bfbf2ffd3450ff922b23ba664cf86a24b581069ff7b95d622cb46c31a4d47b885d9842d78cb069e410439	\\x7496039b71760c1ff3cdeab9f50bee0839849de805c14308b23cf267a3a3f87738eb6d267b3a4f4917f6fb5f665648f76b1bb51f2b14120bf92a95ded5a49ba0	\\x00000001000000017dad847c61cf444d6c4b1f00c5a66fe9acaa80a4a5d223254836df51b0c92953d560e6a6cdc43b87f2733a7ebd61cbba00442a5d074bfcc48a80a135a3f4f4cfc2c301b16329f78ae3366ca71901901e8b1cfe1fc9935a00d1a468776e4b2f56e7e0e0acc58ea07dbc8c460d4850a7edb04fd5b0d48a25902c76f6486ca42598
8	1	7	\\x02a333e6c1b5bf8f3ae9628e364b375bc4634f9c0fa1cdec6676c6e0d844f380e23517ce31d78c6d762bc5eb4b0b5b5410ee3ac0a0cfde367a4bcf611a308f05	327	\\xa9dcd0ec4e766312e0c93882efaf7be38457c4a3dd40b294ea84b29d4be57219e47b53ab7ea35e1cb4d91375d90bbfccbc7123134bbf7a133a60bc06dcfff35bd2888d81970c7515f8d5c94c9197cb0816bd71c19ae7420a58d33b709318e8472a5bc30f11eabb7cff7dc524d93622ca0b653bed3ac13a618149345f5078d375	\\x14cd8d58e65b37e342ce2ad5151d566e826a3c5d73cba3a2c58dfa3e4290508017e99a148d271aa57b84094a1547fa8946b19b82fffabd0b5c715546772479a8	\\x00000001000000015cb344879f923d6ec76d4e992dca2698367af1a1d47c74432732090b32361347b468fb9b907204f553b286f092e5118c97a2f2c15d197bab5f9456a56caf638f66814f466a0355f9d6898bae019cc424395a9947bfbc827dbcefeb3862ecb90e34226c5319bd988fd9c83621ac18b3da5e53e694d9eaf96f45667b7936b9a125
9	1	8	\\x07cc71a61514a9bc5564ea8b5c7787256c3d1e3396b63af115b2aa2d13d520d433e6f7ea0efa3432dec8056ad274ef27edf3a362b540d06c17940e474a2ece09	327	\\x4384c3381b32afba998c693a123e24ea80ec2c27108f56cbd8d147ff298bee50f272b9deac5b45b4b416e243b3d8b45f92cdde59b7f32f56070fb45736f9f1861b7cca052d5f24516472246af8934b9b4d066a3d73d20a728b5b3f9d567df2ddd5c8368e38bfcb828423ec3c96365638ab3990c2a022bead5db58764a8a16e11	\\x71562d1772098cd3cb5c16a09589d57d6301dc7f1448c22eacad11f63c81ca15320a1789170eb26ac54da0a66b915f292b96283bd56303cf6f6d1145f35d0c95	\\x000000010000000197afb0953cedc7b0250e11cf92c11126e60d5ec67a3ef987eec36ce2b32ef2b0b1e5e572ae2adc38f38333775d3b3059d32910e48d04d4cda476f728305d393941987b2dd7b3ed208dc520535f088972cf33d7cd4e67922098a82faff64b33f331ae660866e20b8496db2d49784698f9b56a64ad572d5f046865d61645c8ddeb
10	1	9	\\xe82c6eab24d0db5b8c7f24e9b64cd5644642499942b75eb792ef65fc5d1cad82031448e82497632f5988e6c05653434228f476c2b36c1a91d50f62cdd6997d01	303	\\xa685c007f22bbc3ccf79f469427e23d01b6f6adc156cd35f966a7f9a9ab2f1050dee176bc72203b6fbbad307b96866a056e448e8c7486318c1db530d7f3b7ab063e6c02a2909e7dbc9bbac0e3f57123dea2e7ac4e9624559339091e4d24769fa31a6c0a0b56840394493f13edbd3c0ebcc7bc96ddd6150cea096fb450b39b0de	\\x4a05a3e97226e32c25e0284728b8b95f6b66e78edf101a5237df60f573afcdf8c1723f16c553a066b3358c72f6e65afb81775479b692dfb1cc802696d1ae4fb1	\\x00000001000000015cc24815508a8665ce51feaa826ffd8205f6aab861f62535f795148f372edcf774a3fe0dc881b6049529a50b7ca6d200363d2b498e161010ecaa4190036b8dee4468a66e04fd0892be9309f6635101efc096fd1f018a821645c3ebdb0493fa1e7f09cf57a11dacaf209b88e893d5bd4c50e1e284cdd467d4b57a915d52c40ac2
11	1	10	\\xdf4fc5870de35af3c0929ab46ff8f0237ad8f2c4c01a49e752d6dfdfa570fead85c52e46fbce48602f73035443b17a237b9f45050fb7bd469abc86b343544f07	303	\\x1515dc89fb4bd23d63818bc249607fd406aafc0d3ee8f90f52f75bbc99a1253e5f998180d980039b09126909d18026b699616f6acdc342e488c55822cfef378e93e401024e3646bf8db33537341f458a5da166f7fd19aaab081233a0fa7dacc57ccf8d6d3db5e77b46ea3552906a638d7207490ea7f39c275072a66ab634d6ef	\\x572d6eb6be8a7f6a5f5a6e737d945a77e53c930c0e9f7860b81deb0969875f01b901d541704cfa01947300d79050a1e994358147963376cf269697afd6f16bbb	\\x000000010000000120e010495c1df8669681ba5df37e62cf5abdff077abaf34f42e9b9cb92e87a1f0c524376180f2b43e9d3edaf78c2f9343689232ab3aa9bbc9e3523ccc40fc59f19036eb65dd906389172336949c5c4bf00bae2f4424bacc7b5ca76be32204a3fbfa2a1e954fa677d506a5ac2cde32603d3467a54d5eecaf840031c873779bcf3
12	1	11	\\x183dedefcedde0815696d339fd4349254752cba6e5b2aa253ccdddb11fd9541a001b645f7a7ba066d004bdcbd884a5056aa3864f88a6467a28d5d9bbd087c10d	303	\\x8be1c8b8a76946e6fffd744f778c765372895529562a5b6a4c2db305bcbd4f7f3e3dbca784004a70f0248a16d78ce200033b506cc7a272386e9a724c3dd5eaf32e5fd3efa16f24a7db555c18704bafa0ea38b5ff0a9b53e8763b23c28cc446995028456f0e5b54305f1cf7bdabccdbce6b9d3cd258a6cadebb2fd4cefefc4e62	\\x4df9b095a9fde4018e9807c45e87b2a34e6d2f085e1219f327ad6dd555f4bda8be4644a9ca9aa94f6339599b494cd1930759bb8efb34fe3eada014f02e351843	\\x00000001000000014e0b90c0dd66336650290bf5c202510d7620bda8a898fe3b3a13cc327bce1191b13ca96433a853204c5be7622d37a7b1b39d0062a433adc5af92c625e63f557c6bd876903af7af0c495081a64c971d643fd9f737e0f5241dc4b3e5efdaf327ac15cf39dcd6a7c422961f57ffc260106cd2668ce9a40a37caf849b7bd9c71d5e3
13	2	0	\\x7c3b54897aa5acf44d1a5ad8c5fe3f3fb3d6c06101f8e9f19ec05ce3527c14e2faee4a8842300b883f3526b41ed26a41fe96b66c0673542926b975502a458307	303	\\x7d5f43c6f61ecfda62978ae98c7cd417b7b78c30c80202e826c1b9d2a5bd39fbd1573c2a3d2b838e886af5e0f47a5bcee83ef5279b4a8fff090a374da81857538594919cafb435e578cf894cc0219341377b997c66dced0a9808901309651a060b8712577ccfbf61be82407e604c48e8f463db6b511571b3a2922acc185083a2	\\xa1c9bb5651164a604811dc04c60b726e8bc598d862b3789d7bcb66b4e05fe60a862fe94b6fdbe0ef1abedbd8d236220fe6fba70162160a294dad77f48b862761	\\x000000010000000188b468ee8c23cc685f7fb9bb36c69ae5c40c58b954c62329f97a1e92c1c774e0a447384940c4211f0b01ee07491fa982a5b64ddeaea492d391805586a8e4041144b0ab6b94d9c06affb30ca85db572fb2c8f60ae574762b91eae6ccf3a57bdc5531753172ee09038943916642c4ff1114b7caf129a03ff12b2944b59c9a2e4b4
14	2	1	\\x70dba3741fb6dff19840dd0ed98b352edb131a2e4a0246ff24210a4c0544bd92be98998d781fcc8f46490b8862cc66d9b01243e2ced505e7969d537e53b3ab0f	303	\\xa61df89fa20a7c91800c98c51be66e62f9d4c27ee64cea4e8cbf0ba870229cce518bd5df671abe6c2f2996985d492b0f86fac7f05009c93086104923643bef8a5d0fdf90823f29f52df81b56c3cd8dd572caeedce1fb13547befc596a117527fbfd9bcc72d0be0e951800b43975c299ae1b45cc36bcb47738ead6714a03c87b1	\\xb80c8e1fb951b21ec48632859b82fbbc9c40840fd02c51b0a6aea0b5780bdc748680341f6888c44e61fd187054e71796606ab80a913f38198678e6e3be2755b7	\\x0000000100000001c3c1c360410f875e7bb2184b066803db6aaee462864ea0e64c877ae66978f91ffdeadfcb56e7180d24e9c86226ec84d5f8149b6734cba5bfdaee01ad4198634f14f86970845faf273caadd50f82c32ff2afce0506aa09d424dfb890d973d1c65952928a9335c4e664a59fc25ab764674bc086a257f9019b54c18b09ed9611dbc
15	2	2	\\x2d29f3f6aced4be5ead06c26457b57192f5d5b4c56f5ab8073e3723a71dea53d68c8553aa76c82e6e6ebe057eed16404ff7a985cbb17594ba7118ffd7bd2c605	303	\\xbe71dfe7dfa0c6701f173851e7e0111aa1d02ec51916252130f1a64baef2c901b0dd2ec7c9f0382c0e56cf2f6fe1d4a126046f3eb0689485c30798cd64365148b9f28299da176cf5f4ef016402091b0740fa26925b5c4575d4b5dae3cd1b64c1ca9600de72e79a8975c9b1462e1c194a37d86bfbb838af083029991ed458452c	\\x596472f894537bc76a83d1cfb691dfa69f45497807173aa3100e5d47bb33b013ca6a231df9ca73bb3fede5cfb49eb3d5e508fda2f592b3e652f8f1483f98c945	\\x0000000100000001ceec229b94522cd20daf16de2f855bbdcabaef921231029e08bbbbf8173e7a0d581d985f1793c84b6b98b0e2d8825fe60c937c973ecf3b361478880dcfa480b33eb8d367a61de9b9a1dfa8d57c1b2749d25c3313b64865498c69f422f3d469aec5cf301476e06019ca5821b1097e5480cc18a361799e52acf914aceb968afc6f
16	2	3	\\x32280347f6b5b12c13f73d1f9b62ff8c090443ff62a85d78c3b75f8938a3f673a9d3fdf9e97d657b408ae8a8ab7eb68ed93557d67e82cbe0c02a5f663f1fc800	303	\\x036d9d6fe6e2ed835ac675c3c9eab7dd15bb8ec58a6c33c6f7cd6196f3b3aacbb1674d2c1e24f8a2ae9e9328c279e141783bf2eaae11e96a55c4e8513067d15d589b59ccdc718c168e9ba6edd08d28cb8d899ca2141734243b03c33ff974cf0e88073db2fbc25df0177f6e66a9db0762f766dd2ed7e194aed9b3c6dc8efd2c43	\\x267e50bf6b63c7446b929d56c1187c9b29ec0e72f20e68e8556b732eeec333b2ecf6fa57b59773126b35d734dd7b57ae4439d1ee74cbfc3e228d1b06f33d6405	\\x0000000100000001b68fac555ca91bb85f74dca06dcfd8bad48ec6f133324542885a1a54c621eca1ba89b4672dd0faeb15009d470aa943e22cd15fa044f38b68757ffa2a3816f6cbdfeb10252412b5a539d0e0d3677c7a7b700b30db86ca2e73ef1cd9deb6c77facddda6dc5e3cbc392eac3a0ef2114b214c3da1f9571e29d99dcb95c265ac661dc
17	2	4	\\x0506d6b5f17ac673e53bffe0d7faddc35a1f35eb6320602cf7cd182e18c17a593738a970ff78b2f0669b9f991771ee4f0719360857e77f02fab7343ce147b80b	303	\\x93f750410f0a66f349c765160f6df59785692b5a8c1a90a7b02caae49db88aaa64ca90137f127227435fa8e5894095f3b75c2a3f23ff1cf095cd1de04c1eef4fb894780a853bd25735e1e705bee6d45d905b92bdbc26b01d8067b0992ecd1a6b32011f5bdc3472dd137294bf6e2ccd41d47f7be787ab7e0b0785e123030751ad	\\xaf19cb5bef1e3c9a98cc614cd08c0b4a061cc78f2c281e5fd15e57cc74bdee5bc856c0eaf5a6da851dbb1b5c3e0f73fc8a8319f3dfc4ac55f2c21be01dbf4702	\\x000000010000000167466fc3b15ef5ffd5d155d3f12999d3800fe3c0fdeb799627e1e1936f16e9897b11b1ced189916da5cd1ee8d05f214bed376fda6eda51ef5b93265c5f7f3b0da93de1214343ce33aeee8d6fa4adbb2908e66bb8c424350ad422ef3dabadea00743b02cf57f31d841a6fc4e9e81102bd3ee4a08be952df64544ad10c994e4748
18	2	5	\\xfc7c3e60373e1b3d2c622567c7dd8199634289b8a4c12e2dd503c8940800b01e6661fb5dcb1d6074cb68d45ed92ad56ff177a8c675b3fb98d0b4b37bca272f09	303	\\x173cb18abc9e1840e92a5478e7d539a8afe225cc417c5ecc42ed3197c288446f831cbee7f94945c3000c1e77352bb3ca2a74128a6f96c3bf2089f17e935b1ad31343e5a0869e03656911f7b0703afe3638c031e17266eb6ebec03c05549e358f94b7044b5e2c0985f277d7d93567c567e32751cd6836f10b3dda5accdd8c9ce1	\\x58cb2891e6fecb589a1f842b6e3956968d26ec46daea72abe770db066cdcdb9bc9748747ef2af9f1de5d837cd6db45aec5c63aded66765dd6e2c7f5f85a1cb65	\\x0000000100000001aca2fba3e5b76ebf82aba102db85ebbb5438b7e39d65dfeb7d33668cfe6cdd6fac1ffc52b37da6e8135e249ee708ddbf743bedeb758650539124462948f29a554796930d0b704b62317fae77388a0878097540166a03cef585f876efb51f730a15f249c26f774137b0aaabd50e830cfc51bf2532700c15d823c754f43b40b02d
19	2	6	\\xaddbae9f5ae9fe520464da04c6fd71fc220bb590a3a936309a2d71211cfaab3bffa38c66bfa51009818cf2a2699085f6b381191703ca7576d346e04cf580580a	303	\\xbf7174dd3d3fc6693c5b12dfd1c97d888ae755b0598acebc95e846c3cc6e50c1a76a36d1a48fb37209f97eaab6423bd28f742462305a901adb12ad058a7def8044f98be2209ae4d52b50c36a0850fd9b718ca04635f45c50f587f394a175db5a182bb7d7de809edbb51ef9f3866daf5b1dfc74e947e459152185aea819e1c252	\\xbe41a522d64bf49d318de4c7ab1da03d58ae28bf31c86dccafff9838318dc8eed089d0631908706273d7340eeb48709f890b13c3b9fc688200c24857859cacc2	\\x0000000100000001a02561f134e3a3337f8e22efe1c9e498ecdf0106f03684ccb29e50601d42cb87e4e0b0489d71bd613dc12da3e6d7c94f68f5de533a38f6e5453702bd646a2137e59c290475b52a77f680ba6b024da652e45e7b1b0e390bfe4e7315e4d85ec25e90567163f05888ad0372a71fb48ff660d7f6e17e8e740654b56222db75fc74a6
20	2	7	\\x7b7cfbad9e809d7e93f61486c420a0d10506b39868b3f787ac0dc123928137a8fa321c7e512937e6825dacbbebae9e546f39e2f5a6dda7e604748ec73b8e850d	303	\\x02748b15468f00e5a8795e120389cf1be32aea0cbca27e8cdc1686b92772f2e476f4c504c6a06652806ac5673396ddc5ccc21c57c95aad14f100f3d90d2ffb28c292b53abe25550a0684549930371acb0ef4c5dbd9ecfaa51628d868f815d3a1e67ac47a1c4412166ce441acfb0250aff0f7964e1b136f55c83bb8075955132f	\\x24be2cd6da5207706d81c4eed737285584f15c77105d492bbadbad459446a7349bc33f0816238f88c159b0f754c8d967fe936630706b5391262d3bdde40763b3	\\x00000001000000011dd15e0214b8fb413bcf57e561ec11c43507319309531fe9983c330c8f3d3437c326174341e31a053be00348220a91f5968384c1fc814604c2d9fdd4d59c2cb63ed5b75de11dcfd0e76feeea0cb589c1f2fe35c69f4d1f687698dabb7e05e4f02335d369553ef5a98bd7176fb409c8789f03aed4ff4764b5f9181b64ade4ef4e
21	2	8	\\xd4d94fbdc2f74acef53d6a436cccbf80a600c163d9bbeeec027196d665355ae727146ee2028537175d53f1d75e2b7b6fa4dd6fa9dddf6356859cfabf2fbc7904	303	\\x1012160d0945ef6c84eafd0b2d86ab58b4e4bdfe7b3afce17d616f642031b6dc2fe080eedb346a9b026889f7e191b9ef60f1f433d7bdaebf96902962ba30181645c5e872431b063151979031597123df4f528d4bf9a98556a7f252a9ae9a0483b5cd3ff175a2e2c51e4cc5fabc5c093fb7550c5628050abbb802eb5a41bd7931	\\x4683e7a3a8212ca2c9a93b467bd42eb94533826feb2f9a0cb2e9f9b9df03e8b9e5d9a89911c02a336a3b9d87a5dc026c5ceaa5c1f6a1b4a52b8decc0f6e01542	\\x0000000100000001cb9ca772c761f44ab97e9ba23a61e25da76b9d6642b6f8fb61d4ed69996409407505175b480dbbb5d479d3f6816fb9ef173e03e88bf53df7a243e31dc854b0d724f02c031949bbf5afe89be536e1efbef4e04f072ca8dd4be787c1dd1e2f58c7f9afac4a99cc0a6b120069ecb2c774db841813ada37a84904a380facc57c2b85
22	2	9	\\x9f679a21f1f23e3338bac368645372910da12211823c61ddb14d69ed759d65acea59b5f27dd41837dc78e34e8c6f715f96c5ed7630c5b10f8c76e8e30eec6a01	303	\\xa4e38ce6cda4c44bc645a982c3ebec1e45d7259769bf8e27ac5a3571320640e340610244bdff4db3322134d7b41e9c674bb450b892e6042daa806e2de15aff86c9e0123f566eb74392ebb1a019f56fac9ea46f816e760915131524f06840bc098f73f95440256e5bb37980d34d3a4c3454e671fbdad640bce77dea02e512538e	\\x962474964384545e134c9b1e672b8062c62097102f0aa53c55b4c4028a92f185c4fa4988cd2c24e46d2367a6f2decc0705069e0a0ff30bdba6de86d55e31e853	\\x00000001000000015af9e84d3f77199c03d2b956f2b280806edea9b4f28d59353fd68f6155020500e5a6552820ecddfe3c22039f452e32f730b13501dbc92f63b7e3d4c118ce53ac01a32b47d47a4145805bb1279573123415ae6edfee1515535665197f18d4093920fdf0303eb1d67fdc0a5fbbc442a52d22c8f7fcdf64a64e52807a0caf7092a8
23	2	10	\\x000c732e916853ebc99dcd39d7bb249448dc09974bb4334ef5d924f1960cf586d1f7cfb9ea7f963a9fb09d88c660fe8f42a89f58e490929ab483903147ee0003	303	\\xcec6c00c641b9df0e51b0fdc5323dceb5aa311c63b1bd8d49be262cbfdecb7b820bb69e239c7e935b382706c62b1cd354343441104bb9fe0e16e5df78991637036f2bf0bbebec9fa6aa512c7e4002dd47ffbb962502ac7e0298fd4e8691628515cd5ba072de37d4709da3b3f24121a0c945805700c7217e4c46bca9a88aea53b	\\xe926816801e164b26d8bfc5c3466fa4b8664da3c93c42b7ce76648b4242347ed6789825db8ac155bea216640e4ef9abcffb35ac4254cc10375f54fc69ae62078	\\x0000000100000001243c6e61654749f1cad53f49a6acc369d1e736cd08b97ac3273e579a5c58d097bc8c8a589943088402d0d812b824df6ea9fc6ac69ed696ac5148ba18036476f373dfca0abd8b44c0b5ebf699b0b3cd5b3b84aba301c79bea14559020a4431656391d98c5ee8697491fd838a6671801cf344006a80a726f3ff2f64cfc67e78c13
24	2	11	\\xfeaba8e1a596c6908dda06e2e9a4a8d1b0b504d964e2bc78641c213a80a83a8897b0ac89eb298272d3a7f5d1f2aa1c24396a741c19f38319ab4c919bacae7006	303	\\xbd62093bf21d71e0468e37d8fc44b10c79ca5c5c15c71bf205d6bb19057cfb63ab813e3c79bf5ba28259914eb2bf9be63b8f2bf3d34606c141645870ba0760f20a31297bc9de4410ab1b06a58778f3997ed2fd44b1d945d8b4e56470ed91d89c26e4f07ad15477954efbd6f5af3eea146d45ee3b83396092afd43dd963060c11	\\x97b99577acaed1f8560c5c9fb5acee3510e6e2e54cff6e709bf0f913dd311fb4895ddef9ef6c9edb79bdea935d2e05d41f15cd0c1c44e36e43ec689fda3a5e6a	\\x000000010000000113fb44dafe1b7c84cbeb2dbdc22660f980d8895cc94ff9dbc0a4bd85e7502ffae3b547bd9bdd49f50a366006e5e6ae08700693704a3fd47f52c7374b0d931a09934dfe4cbaab6a9eefbdeff752e06a9542690e80ab69996f3b25efe3c00ebe3ddf8b52e39fa3dbee3fffa2c6f7f87bd5d100607c0060105988eab00f01016b3e
25	2	12	\\x50e2bd3952b710b90d5c1e5b75a771e3af4c6bf89dc604d424bad9b935f4c95b40bfc3fb7892080c2ec416c7cdcfc1ef1b54b3cecc88c5fbc4765a8b0665680d	303	\\x0ffb8f1bfa795fe15ce49df8a237f862268c8d3c0bf2abb1de01f52ddbf5d3067995bf3d45f80fffdcc9101dbfedd256355a6dcff4ba482c5eee8179675d3ab6d2717c26ec397ebf957dfb68412e9e3bfaef5159b77e1390bed312bcd082af8ce71ea392b80ab1043ad83fdb5810c12a8f1864ed74d4fc4031cd791b904a4cc3	\\x75ce0ccdafd980a07b22d7e5e20bb4b3ad17d7a5be1a887246146be1f1a0178d9085f9ade2d8ee3e7c095ed0a54ed0f1c88efd1805d34e4a3bbcb411e162821f	\\x000000010000000192ca6340b84da3cd8b3aa1f8b824a4f7e6512071b15fe733240197d8535197756814126ac623e5d8bd8a40218e929eb07dffd97c6c5b59c8348f7e4509e78e61f5f913cfd3131b8af13398de82dbb43c69b507b9b51616c2a7b8a6e6bc6c945f78740346ecb27dba8b7e90fa0d2b3ea6e1ae993334c6186d0939f4e49d216fb0
26	2	13	\\x6c42cff63b155c15d2a53e035444d7b1dc540e77095232b506b384432bad4ffe0bcc80205b223a5e10c34d320c665a3aac158e17a48b3faf120682f3f9c20503	303	\\x4b0e23cdfdb48931e4b7ad50fd8d3f7da61eb47467565991e50d973a40edc16906e1fa5fda414bed059267c9856d023b5de6caba61c22d4820072b874cb8ff33a7850ef88581458b4d9640a53613f160da9fe377db3634e74afed5f62a1bcbbd83e58fc98d171b00c0f39b39a7953c6e05edaf06d32d48e8e5e98fc859e9e180	\\xa35ce61c4facbb6e15f417961fc38976ee807685d8b1b3c6734e4a4de17b9110a3fa84449124fc350bc8d0a21049199f43b75227b368c81a63c29bfee577b6fa	\\x000000010000000104c030ebad8b677da91f1ce20c235378117c28bab18fa18ed534b2079abaf9bfb1a808b8449cad790c67918eecb315c189316579c0d30df6c204794430e62b6e1a75b1d9534f2d47cacf1e97301f6e57f98465798d0ed9842b7f73acddd3347f0a1ac3c8e456b204439bd23670b968a4e92a16fcf1ec818e3b0044d40e9b06ef
27	2	14	\\xc128884bcf3e251d71eb22fc6b7f3549de2f914319bd38c08cd4498e3c200709775ba250474aa575d6c191ba8ddad58beb4771422e02068578a5eb3525dce403	303	\\xa41fa992197f19e0a6d10539a69b60af86bdad51c3169d13a07a312415b3f217a07bd6f6e05ef2110ab3086ded93699c9c4af5c077f5c3516d5dd0cd5153ffb3e91e2c0128c1121a1b84c13dc3b776f140dd8b222a5cd40101f9a227115fc9b58d9f11b6743c092d1bef48068cfcae5a4bdb66f51ef989f3b89803cfecc4ed88	\\xd96e177342d516def17231116be577a770dbee9a1a9147864af1b3cb976ee0840d25dfe55b432028e468fce9507342fff77f37ac0ec809763f01dc8d73694786	\\x00000001000000013edb78b814f06122548bbbd19269cf2d8e752f47a701868d339bb34759904b9cc0d0648eec5d0658ac8fac83eaa662f7f99031694f1bce931006f79033625313e03c50bef16ca992d625f59c90eb2e084865ff9dc49ec9d980d1d9fa83aaeb3d133315d9a16283db9e09fc8ac81c1f4e334f18758683ac84ba462db4402bfe3f
28	2	15	\\x5c2948741c2b79c2cdb1f10bd0749dc76eea512fe2cd0569351501018a2e2b1157ce960a780cc3b79b882e9fc6d2f4c7619c09a92f52daa74bec723255c04902	303	\\xa1a813557b67cf2f5661e2a6af026b547d7580ad386d9d69b07e7c064c5da9ae93501ab7d67cee1c1fe52ea07871278cd33f3ecc61619810ea8d486def30819e6e6872f5ee2208bcf6c10051ab697e689031cb837d89f458571e707de863b057efc1479d2d81c171c294a0dd575ce1259e8a0e35d5c47cccb8f573e0f080d5b9	\\x7e7e4471d83dd853d528d5308f9d62f422359d3d2cad3fa7ba99dc58d3b85bedb12d20ecd804329230495ecfa250ecee2ea36f69763b8a1161e9f5d1da37884e	\\x0000000100000001111137336dc7588148628bd0beb2694c8066151160ab9ee5f58b04320981cce62c29a1cd676a89bb7c3a8053e06a59abb851b5da9b9180f193de97e7ec192f8fcef895292518200593c6366d32da64188b5865580be96786a6b3223bc7cd0824dc1abf6b3e57a0786b91ae2914f22595475fcafcdf0a5a9a5e67e5c106fdec0d
29	2	16	\\x00873ea74f49f51f256bc2a50091ededeb74e068c153571f239206d08e4169469a5cb9e7a2ed73f60e426c8d7993eaaa0780036af7d054c0f92dc3cd70c9ca0b	303	\\x7b092bafe97ce91de70c08c92cf52c625cf84c5bb9acdd8d725c42e1a2ea4d071a66ca3831669baaf895433ae95254d2d670a88b900541b99589b07fd3d92c70b8bf03ce1bcbf560758b6160a09d0ff08af4eb930f146a55bbcbd512a9e5ea4bde5d038bd42d7894ef561826d4bb09d03c2431936839965feb72a304bbc90761	\\xff8d4d519885b081e6f18fbb1f061be05e2f885007bc61debfab71195a632009ac3a646da71a4dff37f6332aa95e927793ac76126f5c1685d156944569ab4c9b	\\x000000010000000132e2f240b8a4374e8ffcfc2af26626daa10ae2f849384cf8434a64e62fa4ce0fdccf4e77ca57810273894459b2950ba49faaef5722d5227d55a8ccf21e1ccb0f23ef3ca7fbd6fed477456ebb6d679a6bce634bfa33a20cbb69c89bcb93f0f50a16033036969b68bebd1c17cff98382eda9bc565cc71c7360a41fd6cd2d7d0c46
30	2	17	\\x0f8953a9942c06ed4a81a6c2435c5210cc84d49fc6c857d2feb8524e0780fe28f4933c540a95136f421e2c05db6cb02b1fcc8cc250b6dd431ae39978ca1bf60a	303	\\x836212a612f77949484be97149620a5020c9a7c356ef93d29f45e1cd79fda7dc2a027536979f83cb0b35b7c1437c106743efcf70d2a7175a5b23a497ae90ca518712dd680bfd3cc4700d14ac7a2acd2ed584e967971d2562b50d0b5e7a5e0c8ded4f76a09ac6b1f2ba7c7ba867deba6780c52acb44146e3ddadc66d472cf57f0	\\x2d9cd989981eca6b0eda1c4a7118dc48d881799747fae5f8c99bd78d00f150f62545256ada0058016859f71c29056a69d7a09224bf34f4c30711816b2b12335b	\\x00000001000000017b74a77e575f0a4ecd9d4920b7c3521be1e0e494f55f677cbd68306c2267c11833d677b0fa0f75b7b0d4ef971c8c1d3840fe1a4891efc401503619ae2d35af83dd90c3895508ae39ef04d4f02775c23425e96839e6d4102f948050982027e19f307bfa93431f8497b0b7424a6dcf5e4f1dd9e6b9b039ecee05a58e5935ddf503
31	2	18	\\x046d73dee097c3e6d0bf0de574c1b6350aee81048dbf9b878d3f4d39187a1b040e8fc117f011d47cce7e64ef9f66e481c2adbef76e3aac0c72d8602ddfa7fe0b	303	\\xb524eee1cfe8ab660bc8a058361de70f8a462c4b9fafbc7e5345f89e24cc2c6a435895c26a563b0bb5fca912e00a8bef8d5f6ee7c92729adba0f0fcd6956e4e34ad15f1db721285f2beebe669cc2de4283048f00a0b6ef0d5a83bfee1503181a6c38a21751f04dc1935da0fd1ff91b741278b49538ee639a6857215e0c71f863	\\x7a82c5224349d4b9b4733371d836c6dcac6a8f24d563395ccaa6544920e5e62cecfc3a23f95f6e37a534197259c228eb05a9188064942fb2e972dbc4ba65885b	\\x000000010000000157a2cf24947f60a3666af04b42221b37a9730126adf1d83dd19e4645dc8438493da3afa324e405a91f0166e6c47effcc827b415ec39a97972b92f10b4ad7491c4eeec6e2d6b613d0f6c7459d16705a30218420b83f412a6308fd09a90dccb1639cdf559a339681d751b8da995d12da6a9375637bed47c7c5d02b0a8d8bbe9882
32	2	19	\\xd1a81a9e56c2d23e968a03c70754c770c4b384bd2de2f77278761669a5a7ebd44aac7fe2dcb2c61363ae7a39e17d8dafd0799b966d5c7f4bd6345ada15a36705	303	\\x8c0dd257426bb35824ff5342c37c630da71bd391b245cc5266408935bd5619dfe507b50c5251e9f27eeca1d89b35c08beb10070549aaf12a014ad8f9279775c8b5c2effd7e1df7f2d05fbe0b6e45cd7ba03a5ef90c6585db9e1ff4532ee58c34db336c5e66c67bb5c33b0d2cd624b69484ff16132e02efc528d8b1d312f29566	\\x3fd9c626d071b7ed0bb836318ca0a49bfdcf1194de181fc613d71ac8ea23d8700418d241f8fe5bce48545543424bb556c70f2a6c8ba59473908bb1f70f58c815	\\x0000000100000001ab1828b7e775996ee323271414a2e82534a9ae2ef98de58b3cecb2690fa7ecf5a9f32c09867a71cae347cadef6255e70622df26f8578d7a568568951abe8a10a9139221dd5ad04d60f04b04511f32cb854343d5423ddb38c7b348ac476bab7f7efc41a5afe64aab2c753f7953659a818bc804f3546b6c04d981925db43daa42f
33	2	20	\\x62c66b9cb9f94777f914e65e199136461149620aa0aaf8ce199b9f290ba45638e8ffbb8a7815cafd06f6e79c5e8c9b3deae0bbdd451de0a35f76ca673399e007	303	\\x46a5391a8beddd5c528b29018d0beec6099409820fdb8760305b83478fa086b93719f5c37561aeb178db6352f7be92301c61b30067660a75708cd0c0db964d6ad9e9d847d8e97864a727e581581fc6a5934dfddd45c2d3d548c00ab48f53e7ca7fa76f3d2f683f49f1b20d2e0b2294db7c211afeafba3d24d3e12dfd660d7d85	\\xd759fef6b89df687e72bc4a932a6c28833cb6b6c5338be6c4a9e6f38ce694f9acb4be97478cfd9aae675bca2f7d6dbf267091f2dd459ce072987e085f55ed121	\\x0000000100000001b6a2b1118d399f0e1c6134a321b785052c73b840d7362ee6e321e40c7f62e86c773f1da3ff139fceec23089e92558be328454653e11d5a77c45d50412dfd7276f9c517472e9c959a239ccc838e33f26babd15f6d2a611e3654009710b3b4a59308c04dc869df293b5e6efa4827d4bcc938f1a734506f6706c43aad10afa82d90
34	2	21	\\x232ad4fb5bd21920051b34a16994e037ad837f81b2d76c258d3dbbddedb6bb3e0a29ddff6882eb505c397b0eb5982d8ced0868a5ca9f35b5315684746a36e90b	303	\\x453f2f1608640fcd40be129cc7ea7e5b4750ed86c5d451cb928b89b1731e52274b51f9cae29c12cd0b0453805a2d1f271d95cfead4d1c70201ba3718ffbed70e91fbc34a6b5a75c654267bb949362df40201bc0d8db0ac47a6d298c7f1ebf9163df62c4eba6d2cea64422ab3adb3d9d5cc39e72b70e3dc795e685f97ebb591cd	\\x644e19ef84d480e32b47443a17af0d7558681bb93150d2c70d416fe96096d27d36dfacca1e9128f0d6a46b5eb943fe9e2170faaa5919d17332e39c021437e14e	\\x0000000100000001bc2aaeca954578dda0ac8cf8a974e95aaa53549958fa986b329b88a7568ede985961af6203bc8b9ea33ea2b8b627eaffa989c6ff5a5e6e95e1b8cd113035e9fa58bac1d256ca2d221f044639d81db19d1e3e5d79009383ebc1784c14f5b1b9bbf3618ddd0101ab3fa4d4aaf69282a434e5e19a0c9b9434ea2aa6f12645745b58
35	2	22	\\x4bd72c8725d1f49eead122332a559f8a9f0152e19b5f87b5133e62357a518146bfe1cf1f746131275aacbb66b9a943cc82c5fa7a270b9f910fe804f45c934e08	303	\\x0854719e9ddb6481c3bbe59a2d739717d95a9fa8187c57d0006667ff4c9512e3b27adca0d7ef081e5f81b1dad7c494b30a874f47d8ca19ef941f97b990de52fcf35eeee78541283d409f3760e843dc12e11d2c5460332599a155b01575fb24806a473e8bc2b9eb9b3623f0cc9fc7a5bc7f5baa0f390766924b67368b62ede74d	\\x6501998b288dbfaf3715e5269bb8e17db5c5a2bc01c578b1f58f2c23f31eeb616634097c5494c7ae64a06ba1f5904a7ba1d3689bf519b31d2542500fa1c8aca5	\\x000000010000000187b71d96fd8ba4339bb95a260f81c401d0eb7e43c0628e7d69f042d25707a712b7140ce5a2a793169c5b84da11d2c6247e9db4ed3f66c0be10c2d612385e23ce5f30b50e4c11ab7dfaad88a54709033564f6d15a5c7d3b7d183f2b92d130375464201b72e7810ff9c1ac9cb243f6052124f3cf6580114704e3404ec748e68b52
36	2	23	\\x27a1582c6bf17089f80dae3264352ac72e4f13e1216015513e87500c6646d5c44d9a89a71ad6601d3061d73090062a2903cf39101860e16404d50a59eed8e508	303	\\x872596789f4a309e3592860232431f5a0e8acc1693a25720e8d0b4d23063668a7c1fa74bb2c4d8358998a0c12cdde9616deebd393748388a509b0184d8849d013fe67af8ec23de42ff70ab9d013fc5059666b471d1cabdc5f2ee640df78ff45640a0b389386358ce9fa099e2fd6d8e71e06fd7b39943b9fa0166a51dbdd398a0	\\xa72303267856089b2bad6dbcfbe1d094e07421b45ed81a84863377c7f38e5bd99075833a08022a6e23beb21ff05da1c05ed5f4f7d2ef9a2fea014d805a5c27c1	\\x00000001000000018be92c392d2f775c0e7cb94a0d69f929f7e45c1089b389ec209f0a716a9e9c267777250a722f97eaea0feec6239a10cbbcf467bcb41abcd8dc8b80c0c4ff56f872c116af29819d6571ef7a0d78a86c6d1a71327b843aaa5616e84c93fe63b4e11f20cdcdaab10cbd1081d3ea5d1af7c15d654ecdd95e6446eec131d467879310
37	2	24	\\x6b6133a69daece4b0c35186afdef43a80911a0431d94cfb66dd616ed822cbd7817f18f6e69c9c65d7698944bfeec553140b688deec879c4a27713ae885a67709	303	\\xb27f2be25f5e596c769b2ca70de473d6cc3fc200e976c7452474a6832f7ef8174b6e57f08edd92659cf9a0c5f801968abb4f2a40d13791b174196cf14391a3ab42ad1fae93fafbbee85ea74878cf5072c31a1bb16a8820318ec23393c88361001e8e9f227300b88003631f36ceb704d9c8f4c3c8e1aeacb8195576c25c2c0409	\\x362ab230e85f0118d5be94472c5d27927782796b274a0e9ae55ebf933572fb9ab7f990417feff50608dd4e322abc9744ba9788c4fceb2cf01292f1ad05ad18ed	\\x000000010000000173aa6768afafed68985260bc71f718b3c80d602f0d4bd5ff0c4280a673bf327981c76b908b084707c5c56ef8b47b539d9a058cc53a48f36fbd1baea67606876ff582602db835c27d8e9190282eb092e5d9ae7784de40570de3b7b94e4f33f136142c998b503b8fbae3a2783632f2f85e909f067639248ac6e8b1df2a620c031a
38	2	25	\\x91d8c69817b998969b9314044ab8a542e4e283a8dd433e521a473924fc2696883bdf0ab9cac379b526e402ec4499859d636f877e5464ebb5fdcad3a94b289f0c	303	\\xd28604812a87b5a837e502aae51cba0a3c89f59f0c3da6f962ec8713ca49b128436b31448fcda25499b0a5361516b980d1d737755b40e4342d862a5d673674af43862ee38a968424fa55a8633fd408bd662ab78d9bc54017ad8e22bb54f37f883809f19bf521501eaa9d89c75cf91debf1be0bf7ea8c56039fd6aeb8c9c43a92	\\x40e13f94c0e8a0a21ff0acd2eb5699f0e5498fabfc1fce2d65036bc7a3d955e04195187a48e585e33c50cb2a7a69f773a8fa4baf01aa21d7ba0a82dcc7398278	\\x0000000100000001aa4bfd14ef3135d011de4c075a0d0406e0c7092161c5d4dca76e8851decdf42993eb610b06f6f790bad9d434de72ef4c9ee13de7ee36d84fc672c8c773f1781878df297b50e51d965b8e9fd8242179ac8c203d36fa9451ab3cf34c69c4531ea202a370429a7135766fc60b2570a47ad9a81c579dd4faca37d62dbf4aaa8e5d4e
39	2	26	\\xd29f793e652f865cbc90379b910929ca942e2edc99faf13c38515ec9b4a241d75a65974f701d0e19abe0687b9131b5638058147b608082e9b5f5e2d00b86360c	303	\\xad96809443cb1d5a695f86ab5ba95271aa7af2db1da0eae1b90ffa3ef936ea7a1f5e36443c48d9ab96ade71dbcdb2a0e27d71d96e73c38ea86aff6a9b6af4382ca722f97be3cccc1c9e3c12ebacab1a3c7bc1213593e05288214781edc1b563efd2d3a81b18321b6982569803d1c27dd49599bef5fbe1e657343555d1360b7f8	\\x1d94e6444632d99940549fedff1ab1c8635e288afea64ff009316fe8f21a6a3785f249c5c3d5cbc84a7320e6c708541a707b1ed597e96a926a8e10379fd5c25d	\\x000000010000000151bac0939cdd159b42f2b8f4e6f198b4150b682c42ce369b232043bb99f57d3547e4e900cb4c56f1b2989aacdc78ddab59735d0122831e1d12c88498f4a9fa3cdf2f6fbd93f9db6fd7a7b71f7ede6552970317a85b1c20b4b1676f8c63953f50b8700b33c463a4d8e3244f3afc66fef9760cd1ef402d36632e4727e01b674994
40	2	27	\\x61eb5fd062ed2f49630d69facd21c97b0624df8e4e01bd0fb7a1f1cd2fbed017fd7e283a9dc018c09192f9a348bc79d681c0234d57aa1f71f3126adf93fc420f	303	\\x2b64a98aab97a19ef0a11a9583e8ac0913d10555ee6c317e2a95001b4ee4810fd41be2fe42724b41bab7f8b6ede6ecb32d0cf1e9e583cef8a46e0689c015b9ce0492b34a7cdbcae3d86584a4e094b09cc101bcb15f691f6695df8ca42e0c41ee93bed0a62aa0bfd83c519714624ec0a97f242f7e0e6e6604c38bdad6ae1121c2	\\xb48916e8290bebfb96d84a0454c5b56015be5794c922a3d52aa2feaec868a836a31e25e39614e44b487652531cf2409e9f17be0d5dbefda7236691f7df18b040	\\x000000010000000159e3539d99b98b3134a81f3cd0c4c6ca6556b9fa8b553f6bdf408b30c4043ed0818179ea0e6efb515a81b33047434ec238b08488e74a57c0fd6295cfb541dc3d2bf8e9b726aecd9d53ed8cefd55b9e246b07b5941713b59054f3311daa4d414e9f9fb6356d5198990c910d0d79d0a739e0cfa1d8dc30ef55cb73cd56899b34b7
41	2	28	\\x3ee1768394dccd89c3efe585a0228ec39d6ede831702f0cb6468cb20e303dcd20deaf22260056545655c50983114cb7cb2be4335a2df76ee6ce28507007e8604	303	\\x330357a08a5fe96d7405afe1865b40921db72edf03fbd4b22ca4daff32ca26656dd17257e3bf326923d913d99c6caa4c6fa0dc40a67c647ffbfb75d2365c04b2246c9791eb504a0741f0ebbb45ff3a29ca142c8d29af95c3dffd9b2504a5303cde895e6ae2f9779391012f21dc2b52928f9a01ea30ce05c7fe76815110893f35	\\x37733c4b06e3c9058fa12c5e714ca579ab882c0e5b3e29eaf757791e735c9fe073694ed2127dc3834c9daeec8f801de67692f7936b2de2e5068e5b94e4e822f4	\\x00000001000000010ed38e837d62094291bba46cfc1b834bbac970517f11ec35be02d38147b176f211e75f8ffb477f92935db2563854cbf697af42d2453458498a9509f1caf6682cb6dbf4abadb464e322861167673b0c39e5f96697c4b66608a62748658bd7fa12633855b31539691f1fdc59e83d338a0c0b1b82133eb06dd778b61cfa7fb50046
42	2	29	\\xe2a5936193337c0cfb9346a640a287282eeeb487fe09433a0d87ab0d8608eabe1f2ebe51a91a0e59f1ae9ef1b85a1f2cb6562e7396b9746f0d789f19c5db420c	303	\\x5f530631f6994195c2c6b41ab239f26b3a9cb3ac648dd7e997ef8cb94b53e2e095568e095f129f625c0eb9cffc62237025c2b3536074c65cfdcb10110e93b25ea5cc1e5fd8482dfec9fa51fb4a697ac85ce14ee448a2ec47bb9616ece5cd61ca7cc2a20e37058ae87ad348bcc27785ee7a93b5854cfca12b48080b3c48f84dea	\\x440e42a592532110dcf583dda17e7e1db97cf905264ab83684878695412c73bffdc851cb1e8e99f94ca725a01bdf760b75a5d9b91f6395c3bf3fa0a568926cb5	\\x00000001000000018c9e90426592cfc02f579fdd6c3de868c5291b3c2019b920b99944b2162efe347cac04ff6ba0734fffc6c86af576686984e373a329b27c741e919193cb98b775235451f08b33650e09509233df03ea3e7a631b0cdee3c98bb1dc3deb932e2b01598e1e20bf9658e74a427759499fc53e10e800a4912ea38952e4139ab2a7d6d3
43	2	30	\\x3a9cca8053684e38fab51d945b3cd733ffd52826df12440618ef893ecc283ca351beceaf93f2d4b74233794719bc4457556202e4b5581fac75c51a4467befe01	303	\\x16d2de0bcb18d5bec4ae77e559fcb4794e36c064220fb805ac0076150a6e906acbb7c91fccc9676ca98f02954331368de4a0c37ac451c9ac15101b27297c166ea9b46d0de4357fbe63f0f7e9f3ded567de5751666b14f9a7a2ee0b5ddaf46ef6ad96f0a29364532fc50b0cc1524ee5dd52e902cb3dc4dc8073d64b74bc91b652	\\x9ecd2ec0691991325c945d763a292ba49bb5df4a600ef7ae71b2dbcbc833256b8e5f5997f654e0716d2468167c034a8d1ab2b5dee8ca66cebe3ee0db4ab08ae5	\\x00000001000000014cc163b2dedc705bc6ac849052c7f993b2f97369c1490a8b85f7c62dd36c3c647bc1e3cc72232e2b5de1f159e0afa19d8992bc9517be4150c1d30dd4b44ebf7aa87b58aede67bee4f3ae2b92ea42da3f582492dfce0c9c0698295df66fbb8e060f71f474780ae6701da6142a56dca94c2b7bb055e8243c7fc2e8da5a2c793d59
44	2	31	\\x869203b701ad5abc058cfd0eb13341517f8898e927bc907de5b899b7ecb8a2b6859f6491ce29ab146522c8b2d02ddeff921bcd1041f85ab33310d5c465f9880a	303	\\xb67bc4893eaa6d84214df533cada3cf055fe77f96184c9d1dcf1fe2df1b72a0e65aecb1d8028b22791a6778711cd4bb50e43404bf141d585693e7149b74b79839ba73f363fba1c579ad6decba6197d65f72fda3e4b50e24cc197021ff9808d4b1e02c2222f716ef8e77b0579bcdac6c2ea39b0cab892172f039cc386b05d66a3	\\x817cbacdf011c99ac1323f2517bee3e00d5919d0d2d3ba79d31ca5502e416521e339ac5f3ad2611703c24ab626d5b78adadd6fd2d898857778b8477ae16eb973	\\x00000001000000014c0165e0fb0b46d3ee2f425493196f63073d0e52c160c402876a6d6b99d4d60653b060c8b221bc20a908a1da10caa486ddc6995a086a5404bf0fe21ed2a4e537086bdd5358ce407d5b6cf2c4cd59acc5416a90fc05bf5615afb3fb377fb67b3e2a999d8d2b3d2fd26460edd65e0eaf5df68f77a2f63c5232a87e27462c6b7c7c
45	2	32	\\x2ae17d752792728bf8933a2c6d32c7ce4056bb4003d96621b7b8348611d4312413989657d3804749b9207ecfc0843fbc65b09dc73cd1bc19a2c1f36f14fab608	303	\\x6d0acabc666de3c4ff71682de4a06557fb2354834c949d79909b7cbad0a0f00913678cf84fe1ee6ee16bb894d9b3e51388ee45f94027ce3e5e455c95cce06c2575338bc32e68c71897c83ad877286278af222a1ddf86514d3450fe5023e667dafab44acfe1253c5f80f890fd6f9bb067e26a24d49dc6ae4430f348d7a0f6a7c2	\\x22a0d9aff01f594178f512a859dd054f71d97151dc4a8f5126199f511e99792adc87e59b6b78fc9ffdbb601a9311d4132f42fdd2ee34b4e7c0027f81b32e36f4	\\x000000010000000180e330494f6c0b6b2f66b04296b954273da40057fe02f1d7027bdfa8eba8b3b62ebf3029957bc2ae1f026a4db51538a808c2161b3d1493ee4d323d9c85795fea5adb7dc6af9aba93d24adce1acf297e1913d8b7c6756c5410a2816a2db09bc67d6d4b86172404b95a2cbde8c00bac618c29fae2c337f5b197c71fe3a9e29742f
46	2	33	\\x000f79fc2e8fe6e10c080436213b37a574469ffa07ec964ee7d0284705e5c9d3bee162866704d6aa6a891cb87fb96a8412e94d4fb0b597dccb039e83372fb902	303	\\xd076a2da420700f2674d96bfa78b1e32677b3a3ef12bd8914300022c0f4857b74baeb65f66ca33e2b72d3a698e4941488416b0b4950c9558f0463dce48feca407bd3eb62760f81484d28c42f731047e6cca2d90263306ea37971e77aa696c06e7e75c4a59fea1b824ceb9e6c95c7b55c21b30c81cbd6b4b1d3dbe564fd4867c5	\\xcc10b80a3cc68a6adc61b190c80bdadac2f82b0c72a8f57f44b39ed9b92ede8aaa2c8cfb3e2b3b43b0ecf3bfb139fa7a313834b39e21ed33a679355b7717910b	\\x0000000100000001c4b9d8e276ec1e9a9a677a9d98456e6218002a6ba4ffadfb5011e6535fe1e3a727d6bdbedc7f0f719ceb819db6704aad6737e343462a53e87954a931e3f8d20b8cfb4370bd761242ed2733fe3addf6d189d697ccec1e19cd5cae3af18513cc42f98185f78018d743cadec1372a3b7cc43b2fac7ab19c6731c618e747a7d97d47
47	2	34	\\x1812a8504ec425c691fbf5e6ffb16db25455e328c91a723d68b03262ca665f9205432cf61081d5e9cfbdcf28967640b158aad7b916dae17f4d111126f9d32804	303	\\x851bda2a3667e415981d720eac1ce6ea34a343b73bba19ac300970143bd800090282c761e3548b68fd01ef58852429c4344ebf102322f913a6b7f2943a3551bfea2ce76e9159c7e9665e24717501bd59bf6a526d50fa6c7291a62c87cb8f397756a1bbfb84df6fb96e62ccdf852ba6b38ae4db87210f71ff45810b7670942e1a	\\x4da5f328c8a2deb4f74bc7725fc36bca4eaee90bd7a5456620a422080b1ef16cbde4b058712fa8df4e4fd2807f467fffa923ea826eae510505600da467795415	\\x0000000100000001859b8cf93885cf0d75f14fe4c69c0690076c6f2a8e453214e99704d29d95881a5ff8b2b2b55d3ee46fa4fa7576d489ff76a852a6e3e14a150dc9c386cc73c6aa1f1e5883b69b1a12cc7738c50c599ea5c096b8701dbbf201f7a33c3778d38b6f2b63121de0f3f5fb4244152996993b7118cdb1f236a965733d5187ed77d96689
48	2	35	\\x6d717b40bdb7ec83a45995f1fc09c9869fc6b4c3ea34a2e7af805388dfcc9dea1501e069bf8117a707fe4bd8d4ce52fed5e25c2c014a660811ac04ef2bffa205	303	\\x83b730fb1fb7bf6e1f634fc9510a770e396b9cea1efab4003d3ab4a52a75cc3658111decfa1734cbae427fc63d59d5afa5e6387d00e5aba4b88cc302c69e8e46e544e1c0e526d3ed97890f58ae68185609be5fcce4fb8d323df172261b6466976197c16b359e4b6d36409e4fffb2450644fd57a3a605f33731fe2ad0fe46edb4	\\x6e172a61fc6a58b460b70232a922035f1f47e1366b49cdcf505773080df5b3fae7ad35c3a3ef266430f374bcb9468012f85bf47a074b8e0682a68a6c1928d69e	\\x00000001000000015b18d69d4d5c79800f200522b16dbe346bb61e6831c418d9b9951a2f8803a859ace0ba854015a7bfa61f95ad48755935a32dafaec56011d5902aeaff86c6917eb118e1e3c0b1a89036dfa724f9ba37462c2d81ce44711ff63fbfade7d1f3016711e071c403a6e845fd8cc23dc63402cfc2a5c4051c0ffc51539424a78eff2915
49	2	36	\\x0018b2fc03aa633fdeb383b7e24d2a93d7f670fe0c5eff3c6f31ae25594cf76e8a5af8bb849d5d04df5f0f328196cff6229c35f43e1f417d888024d16a428306	303	\\x6fea7df69b0ebde417a67be4e3a715913961aefdb33ac664074bf823453ae08985556f281495bc0c98d247c300b9a4882b210c98d56594aa42e1d05c0691834665dd8d8ebc277073f6766b224b176b3ddb23822a91474c45dc617e167a2e51d21b82c87cedb67cb8a21b32ec7e7465a5a912a7bc18858f52fd3b3997cb8fe4f9	\\x4769fb6bd4b35cbb35ce43fb11ebed9f290576cad858b249e27b7026e406fc2724fd2e043c2c04e8d1af68a643719bbe17d8f8e9d338a3c9020629e3782747e5	\\x0000000100000001ba31f4354a0ab5d7f0205dbccc9db8f7012f4bfdb5e06e28750a1e0daced344406dd191752a246be3d3174434e0175ce081e0eed7f1e76a9172df1014f0eb15c73bcf7b861cee927b65fc42342ea3d00a19ae7cdaa90d38f7520248597f3eaea7a4de26a60ebb071ad5991009e466b346d6726eb0195e2b3f61fe93b01d236e6
50	2	37	\\xfd476e414c236214b5a2ee2d4b8dea14719e0eec7a05826b58271db553a61fe33e7c83fde90d651eea78782b283fe5a3fec34f18043848e2ed08af4eb66da60d	303	\\x92f0fb610d6eb7b0989eb9308a6fcc50ddec2752b4058bea8d61a850a6fbe1967e7f1e2f4bfb81441d4e1b4dc24068e66546f6002bbbc38404979a2e17d08581bfec0248eddf46865ee8b4f15a4f34e605caab0a03b86f3ca436ad9f32e3c0bccbfb62cf1d571e41bafb6451f684c5f423bf19f15c6c4de61a9f5563fff865d8	\\x30964ad56f4fb0999e349b864d500f5e9f18dcd258c8f3d88a2b1967e76a63a030b781ba13bffa2df5481faf11e3d66f847c27cdad80277e1b83f32c10e84b2b	\\x0000000100000001adbed56522a3f165654bde1842037bbcd982db3a63dd22dde791d6708828af67e5ea2b6b89fe7dc60aff3d2d65cc41e35e3333fdf37f8ac3a39a35e3386639c66264b174d19db31398b6c779d2cdca91e755b98d11c4e643f565e3056dfd8eb595630db1ec6ab83f74286ec0b16e984579ad58f543690547c3d4438c004e0ca7
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x6e134d87ae88382890113d9295b7d7db0ca18043370e1c530f6c08c99cb7a540	\\xf357fb6ce8d914735604bbce7716e253f8cbcae0b26adc8b2f8bb32a7d1c4be7c930bfc3d614c756ec7d2275dbd21b7f1fe68e49370eb11ce57dcdca098477b7
2	2	\\x55f615cc0a1564efbcb770e19b3378b5b7d2690ef3fe507fa924670aa85cea32	\\xdae83b786838689cf62197d2a5097b1ae22f7a8c5c976f9cfc59dcbe56168f2aab224d5f2c3ee0ccc9b19c6c4aba6c5338a144f5d1e7e7570f47f579d08ba68a
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
1	\\xd0ae0b9d5c6359413d16b099acc68817940025a5d991ceb145f78ff1262b010c	0	0	1640776684000000	1859109486000000
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
1	1	2	8	0	1	exchange-account-1	1638357470000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x3d7302a03d7253077dccd645c0c9981f5a663bf7368ad87f0b4eb36f4e63d7ad1c41b8121bedbdf31497a67b7036821492987e8673919a5d7149b75df478081f	128	\\x00000001000000014153ef93557a0b280cf25028f028dddadbdb92f8472c8a695b55bcb99e2e6d928bcc2c46041b7e5cbcd7532ebe1e846e4efa6205f138fbeaa729337476e7753f9ab3806d85d5afdab9e9e25178f5cb2ee2a3b7cc58b267e4632612fab21519604b94ab3ef0674059fe5196f1c8c3765e6d53efa5fe0092dd712ef7bcf01237f1	1	\\xa655d5009bb29f5d8a159367664227eae5aa2edb388547d4816d9f0179670c172dd4d7373df004e308b4ab69f7e8fba645dc6c0393e133d10dde8fa873c65c04	1638357474000000	5	1000000
2	\\xff3f623d7f25877b8783986b19c5eb72b9190edd42437f8a16989a2e75343c3cff894ef56a1d482f5b86a0ceee69290797415a1bbc7d772f814887a925ca7571	134	\\x00000001000000013d7b3049ac92ba3575e1416849ca5082944c8b2bdc25644b31fdd1b8916b1e7d77a08a8bcd1de7388092530baa624694e49b22e3550ed2934eac40cc02944b90cd6fafac20ce3de54dca152522e96d6b82c40e86cca75f35dd6d9f794e7275d5ae3efae1408a6c6eb32de263ac839f8203ac60cfe5ab66ee28555aeecc8d4449	1	\\xb02f78740a79d105e23e0f2568ed10c6210fc470bbec24dd580b490ba94240e880f6c2930110e7677971b325c104c097d5b13282da5e53d7c3235c366f2b8f03	1638357474000000	2	3000000
3	\\xc08be7b9a9af1eb1ed292215fd2ed9488334ad5de2ffe39e78e0734bc21503215bb17a7ac951c276ca1b066d85cf0aae7237f28422c0225a7f764a88557b09a4	80	\\x0000000100000001157f21ae074dfa531a1a4115bab4b5a9687de81895e796a4415d93d80455b2f1a002537e28f3bec632358d06f7a5ccf75c1c10f9c6a5fd854c0b6743c634eead1c1f0c7192335948288daadb60132a412debb4889b6588d7ac1757dc0765261f2a9b0aa121d14b83a6936b0d7cec52b0e1518cccf8ce7efda571ad0981e8ab51	1	\\x368b8983cc072492c54f876e46adc00b863c76434815b90926dad51ce8f9eb3256dac5113a8b77c3a60dacd3a08807214f42ab365c418d770388bace66f2fe09	1638357474000000	0	11000000
4	\\xa7c3472c1bcdf287cadde4f93056560516cd2d82f801c3f1ce3d0f60195cef558ba6aee1219bd2ce7ae18d409e1e3ab104337b8611a9e646118840a8b51577f1	80	\\x000000010000000103406238d8091f3e680c843b12e16bce38c7c224181c681d193e53d71ffbf4ddc5bf4a234b1d3afa8bbc5af362c9eb4bff944cb9bedfad3c3f57c3d97934deea999683a2b1368ebfa168334507a073915bba431cf2f1a95e8cd013f54098c0e2b936135feff073ba45a3b2ffb0327124f6989312269785ef2806152f18976663	1	\\x42532a4165d051c5cb24f4e305876cd4cc63d03f80598e54e4e0617482a15d638ec709e313c99802cfe3e3a6960c6f6d0519652abb44feecb6360800d1af7405	1638357474000000	0	11000000
5	\\x91e9de412b52c90cf91b453588559cd95fd9e634d88f0c0f49e59282a6f0914d7dc17b62ae3dd32caeba7611a724dc96eb5deaef13a12bd1472a18517c1e378e	80	\\x000000010000000124ab34df9a35dcd88f756e8a9505e35278846229e764904068a150abcd70c22c2cb15182945e4881437ac34ae176faa0c5a12aa6c19d37741fa8ddf9d67602c7442b55e8bef54156bc181c21463867232822f26c5a8571324bd1f100f360536ff4876de13e216bfc9db9cf5b607053465bb4914bfb3ed82325388a77052c64ab	1	\\x518c0b630ffdc71074c2bd166fc9fe2960f2cf74947ec3edc4524ca1dc6fd68162b8544ad327f36bc5622dd004afc63edc536feed6ca5130939aff9538d5c703	1638357474000000	0	11000000
6	\\xd6a94bbaaa24d047925b7ceca7e89279a14387fa5924e3edf63f3534df6e9885eb8fb75edcd474001e69f5db3621cc26ab839d649be31a50393616c9c8319b25	80	\\x000000010000000123e9d98747dd11d514e824072d06d4d0374d78e007929f562282e4ae2aa82f9b955671daadd2c05e5c3546b9db9a84d4a6e5226e5861b0e769ebe7731cbfc94864514b8b4496e454b3df621b0824100a44ea913360bf5d4c724efda2be2393e31a120f8936d92437951794967fd3bcde5fc80f3a3be0b183a2f58df347fcd8f3	1	\\x05ae294f770372c84ad2f25b90c5f8f611fcda191ced7da4338b8954401707951bacf08f18954e9c0604bfe5ba552fb8150bf7d69422092ade5dd02af89a9b07	1638357474000000	0	11000000
7	\\x3dd86408339db7d9c8d48082023e602db5720262b6db58f5986a54a94b674529038587b177e12e09f996754ef33964437c5aa6b3d901caa5815ccc0961bb1a7d	80	\\x00000001000000017c7917e7d9ac609f1f80af6071cfae021d4c420d9b962cbf1769e7cfabf303ad489cfe48192e84656f789f4296b38ae425eb8b58c85b24f8dd4d417bffc590faa135a045e18362c6d2fdf83d38204c87c9c5350a5b6d4cbf6027485dedad724f654b78727e293e5d65640b7895ff6c6a57adb5219cb9b9c9c2254592c588522b	1	\\xc605ed14fbb885bdde0ebfd3adb077e56e5c7c52d5165bd03d8d382eea0270d58e649d0378670915b173d3c3b399543f7272b06316abcb9d7afc2a06c72abb0c	1638357474000000	0	11000000
8	\\x5ec9c8b3669d50e52118614b505941f5c9c0165b81674c1eaed526999417f73e11c64bb90850705efc09c25f70e1810ca8c01f92b0e8d6d849288f1726dfe1f7	80	\\x00000001000000019613d9d13f08e5b1b8a423af2ec0eedb735fb7ace0a6f1c07240849d67448a82712a525c9dae31087b270399f0dbef654538e8bd230d41929a2414f26612a24045767680fe772fcf4f6dc632edcace27428a0cb5b31347a06a98a76856586395a44e09795d8ab0c7e14d57ea86c4143eadca348c07c977e25ba1750ca5db8bc5	1	\\xbc34066594735d437950a0d6b7d1eedb9ea2fb74ab7ff11e2cc44b9a6eb710f35a2081ffee13d3177736a026850caac03a571480a1a3d92e9cbe90ed2c218e0b	1638357474000000	0	11000000
9	\\xfcbb394cbf9174e70647a25e0ce7891db319239b1e51f9ab6ae9247cd8607afc71e9c2f18a023a84f8fde280e497b9ff07398639f4e4f80395c52b74a81ac391	80	\\x000000010000000171c47f4e8d2759a6c034fa741874825519a0b5efcc916380d1dd5e6289ba0ace617ac12490abee537498915cfe63c2e729c406fe4d109b35cf052173a219623a7b5048a55cea907f7957ed9c1c8534da7999e2e8338ca2d0d96c2838bedcde70983bda0b1214a9fc4526e8ae8c86412f7daf1b60bc04bfbf7b9836ef42266bf6	1	\\xfd9eef815b45874a4050d60db21454f3d53a5f9122f3905633f4ea2cfeadf9690ad4dab5d088d93f31ee82cdd3d70b8d3a702d5a0984197e01d61e3bf8fab90c	1638357474000000	0	11000000
10	\\xe7dcb9014b594a064b6a90046cb54036de4599021ef8a883a49fee2c9e6e200f1aac7afc9956185df5b6b2787c71ac5bff23a0d567dedb1be59d697d653e63a6	80	\\x0000000100000001b374585a71346a5916d7d807bdccecb10dcadf7fe10df873e62be95c7e3643d8e61eadf5a30796efba48bf95b593c198606ada103a9a2cf802688273d6f4712a5e23e6096020758ea53a859bbc4fbf5ea3daa83271846f1e5e99d9fb53b40caf33a4405a20b2e27927eb820d956c6c762e21fcc0e9bfa4d69a12a2d587ef790a	1	\\xa332ccc3162e637611818260e7aa27783d0f68d7c76d6a0ea86ac16bb12127f466ca3c91e95b454a57abd314e17fd846da9eb77eef9af2096f144a44ba902c0a	1638357474000000	0	11000000
11	\\x6b06bd6fbe1a1fae1b3456fb7fc96a04fb56afe54f4a89a573dafdb56d64f9753971a8fd7302014b7903d0a0a32edbbd23078b7a6ebca026c06d2d56224584e3	70	\\x000000010000000195a62f3e378e0aac556b866b0ec0524d0db88b1ca4effc4b82197a0bc9643a3a53a9ee81d5e19432c7011efa1d0dab14472abe92ebe7063aafcc2c76dc196ad553a4412f3e41c8a764b8ee3c10a993a76f534cfb246399d4fff41d4993efdefde73fe3e05b88e11b43514393f0609c95ed86dd52d6262e9261cc40cb33fd00cd	1	\\x05051b94637a8166c4041556e6db3f24a4b33228e81bd6be53edbf40ab435082fc0ba6a159bb92b29b4d6de72e05fb60319294c4cc4a17ca494e00004f02bb04	1638357474000000	0	2000000
12	\\xf59fedf9647ea013dd6bea502c8e7fbe000cbdea151bacb21b62521c00ca5806d27daed5b69a4e109f90c8395084b049c07af03d0acc329069f729ccf9d88c7e	70	\\x000000010000000102919e62657e60222d5539295745e04d8eaa0e66ec338c20f84c4018df7f4a55848f58d16dcd7a0cba697e2cb01c21e5ec6dbd7a6470aba729cd1c194794c9fe7dce41269c09ed229ef4a1ca024bbb0d044e9af73c5906fe676cb7f7240d00a2ed9a098b43d65a5ad227005caf2c4c81e1a07570e3ee3ffdbfbab7cdee578866	1	\\xb771203f268329f9aa89b7cddee0f9be63720d9364ba60e20fa64f7637472ca1e15b3a935a349e8a17d4ae2ec34b3d125ab7f1c453a831130ff7bf27a40a4300	1638357474000000	0	2000000
13	\\x6f5b8f5528d876bd3bddf512e3913e7f9c931a75e45f92669fe43d9dc5f909ef89edbcbcc9b6a8ef953d1209b8632ead3e9a942579e77d32c77596cc3186d2c7	70	\\x00000001000000013091924c47f97c5c43907ce6defeb8546543bd90f44dad322a40f4982c8bb03710023f928983a5dac3c45b5676434e734566d76a8f5340a6c2b5f6213b4b021cba4a83e709c8f5819f517c40baa3402d4d0c84bc6517d4f60d873f55abb8dc416263be70a337ca98da8664a2d6bb7b4cabd096023e577ebba0128e465c6942d7	1	\\x3482e0dbb37a5e21ef307e5135bf20bc77f303f6fdc84e8457489f259628ac1f2ca9e61e30ce33511dad9b8cc7a52a67fb510d46905b082c9080940be6427b0a	1638357474000000	0	2000000
14	\\xc8482b7c3c859d24e365d3598cf9fca42bc6e5b65e669dee25c7c9e6515f503a3ffaf2ffe48fc557d802092735dab58cbe1da6972ac1aa12a4982edf93a5da3a	70	\\x0000000100000001c35a3a8d53e8034b54dced90d7fcd9ab39ff7c4127fa25d351b381855e450c28059acd345226477f98f318602f2dc4ad3f1c986d57fb74bb7bce018d65d5ec77ecddb76721a5b4ce1567f1d001b90f3a62960badb330840565690349a18a248b1a67d22c6ce8797eb6ee96f0051048abb258d40418d362740e94af7ed33dd506	1	\\xd4b5b7539fcab993ceb6abad435f855e6f798eb718449350b8868edb88c49dc5643d2b2455f162f6a3124feea2f0c24e99e3c3c55b2fae0b752e942c751bca02	1638357474000000	0	2000000
15	\\xc4bd0a5c771bded99914bf90ca9e01115f9df8eee6fbec2ce23669c4afafbea4a6d1584c1dc92184b74cde42be51acbb11faf8254ef6432a4e8347ba9e0aee34	50	\\x0000000100000001943ba5dd8c59dddfffa1257bd65e44ac91fb41726eaab14b005b959e4f5e025f1378495a7559d5ba66960f25f302a800448ec935669878261b5dbb029b7d658531401bb5b6d71db8e57d9d5ab8bd09d17ba93c5da1dae64cf123e1cfb722881b12b716b2e1f844cac6fb8c636d2b42c5ddc5e80f7e0a57705602104ca460d9c1	1	\\xd725cffbcdeea00600aa56eaeba724cb519a9e243b5be6552f3807fc4d6c52bda089ef4b1fcf57455b0dc69e8b094a1b939e365e43f1a375c239c2be9b08290a	1638357486000000	1	2000000
16	\\x0ca644d1fd7e010835f9650486c54454ef2f2b47298519f7f14e570b162fd257d5bb70e4ef40b1e7927a31ab2297c58a3e89d349ccc50b9d4a0c9b5a80415f99	80	\\x00000001000000012ff6dd51784c6f9a5f2bb12f4677e19c549f28798b3790d6e9a83b299a5f0568006cb45c31a70f84d5c56adec91fda4db071f003b6a19f55fd4ed2c4ee6ab24dc12d24bcca233dd57d3cf6b89d223e6c6e7efbb1215686dff5c4e36d58181bfd44dfa08dcef0d2694ec91d00b8157139186af15575c730e28d43639fb22e3156	1	\\x1c6e23178f98e332083b239cde479004873102d10bb167dac0754934fe2fa7427df6fc124468072b03c108a7978fa899e903c427ea0f92e9807a5f2abb4ba107	1638357486000000	0	11000000
17	\\x600ec867dc714e85d335e7069a9dd8575364787660c1e63b546a88c78e48664ea43c5111fe27966cc7e5ff321d6e173e7357f6a182f2740c18aeaf69fe58665e	80	\\x00000001000000018ca98ae2923498c1d5e5b738a55b5dc66ee5ec7f0be7d6c657ee44d359dbc03691af9d74afaab0403a5c10f6707d7d33c5f4030e96ae807261993311fcf248eb13959ba0fb8be37e19d2200a72415a626efc2d7e02d9217634968908bb314397ebdc1ea8ee884fb12761182893db3d2f0a27ddfc6c38112f0a9b2ea755624d2a	1	\\x56cc3ed15f298c1fe512e2a77be09112915fcba90af40a36e55904c89b61d79ad2e5d96b4814250ecbc4b7ef819809a5a40b1d77536ae2f41015de37d0ef7406	1638357486000000	0	11000000
18	\\x375550200668073302808fb0865f471923648da98a8c4712ebde9019c17dfc992d62d58b804d1b9a97642ddbb7a3a9e7199f137339ca97ee766626c9d848d12c	80	\\x000000010000000162fde0ee9183952645ec5d4669b049e12a335893dd9d3f99a07dcb35fef76756bd22b52ba803221cb02da755b18614410f86a2d9e6c7d89e3cc8f795fa79e003deff008b9c69509ccdc93bf9c10b091320ed5bfc21c2d5ccdd85307dac0ab4d62bf4634dfc9aac524af13605b8a21b3c8875054ce6256ece545e1fa5e2366b6a	1	\\x69f7a0a27a87bf8c6b7bd2260819d73f88b92358f8d7c3b95cea4ee490a6d3135a13bec26d120948e65e577d979908befa54d0f34880756cd6577804aace3101	1638357486000000	0	11000000
19	\\xd94772745d2d3db6c473d7d3a331bd5483871915ff9149fcd981be7447766aa848e6ffa998dc21d582615bdee2ed97adee3c1792f41d840826dcc2841f85b6a6	80	\\x00000001000000015f7b9093275413f4fe68fea1123ffe6ebb71ae06a811d435ae2900d44ce033a473c83116e54095d0671bc87a88b5d6bbf8c0d5256a3935503f498244b19fba7896d4f24e3f1a674825c66f8543b0a2945c80dc31c1463ba78c8c69f5a55918c9915ea4dbb82917bbbb1e4e32f2d4374110577d384f047cc0f4482c7cfa1932fb	1	\\xa9010aa509074f2ef34dc58ff09f482825e009ad48813d3efe7f881dc6a30d93671ebe185c205aa41849631320526564a46e2cecb68a8169c1b62cc59ab15f05	1638357486000000	0	11000000
20	\\xfa4d56bc3a6dc440495aa7fde67b3cee383177b4bb47c9d90ffcf676ea04f6309db2d9b35bb2cc65df38c6b0e9fe3240741ed00da488ed8010e798c4613c3e2d	80	\\x000000010000000132e7d1fc5a1976f5d66946b4b2021294e88ec0390f2b4c2236363de9bff2aa29164903da59853491c945d2609e5716eec271a549cb57e82f0db604dde470d9aeb1d01b6c6f5b71cc1ca5cd7b3b683592ab32940be2d3763f0482e9f5f9cc97551a1d92b6f6f06a7b9cdf18cd23db5e379c7afca7d9e94142459aaa262af17e51	1	\\x54400cd9f30e0c23c4afd0fd270ba6f4147725b96a91cfb689c97641515d638bf385f00cf256ee517946b3710a89159d00e406dc92a0cd90a879fb942fdddf0d	1638357486000000	0	11000000
21	\\xe3be03ae53bfb65dfc0677f877595c9b91084eb5223358bc36d6d8f9ffe58942b275af7276f6d23d88f38e3c7147cf7aac960faed33d252b3dbbcf5f8f742f36	80	\\x00000001000000018c78e286324fc03764c7a47ee9fbfa7244b35dcd9f212364c1afc71ed0666b9360f9ee8f627881f272cb29c92cb422992918e97319640b92a5795bf0173806e80d9541bf5627678d6340f1d6b9b2523a194d4e845070d4616ff1ad136c9bf69e0bf45c6be2a739be39187c3d25f367d0159ccb1dc44ffba53f22a40dd0f8cb20	1	\\xce39c5d784fd9ed892c91c2aadf9c21c44d41a769d13c5356ebd35f16d14c300c4217dc6e259ba85b722e7903f27ce4f0791c1f9d941b5baa5807772e05a5e08	1638357486000000	0	11000000
22	\\xb11d6003132f95e902a528a227f17c20a88a2a282c4758de51a6bec41437a7d4e66f1635ce48d582982e58a795b48520697dab79d5767b10614545168e3ad162	80	\\x00000001000000011a0cb4786a0c64306325e4834e826006b4f69f5d6275f4b8dad29decdff3ab7ec0f8c6c8da664927767c4a5c7be66bde558a1b4a61c9b6f1c104686cca1a264562f8469fd4212490fcff34999db8990ec38c96417421fc6a48ef8f97d4e532ed73ef25d6675ebe6abf468e7c7c683d2af57a007c077820f07de9fb6a04bea284	1	\\x8a9b1d78abefc3c7d9a0c5cf9953a2675a77dca8328098570657e81786b38a876833527ab7b089390398f43c7a925d2f0bd1e0524b709b815f4f75d7aa602606	1638357486000000	0	11000000
23	\\x9d5cc6629e5356102a00164e079c51c90439d7fc226eb863e167efe7626425386e8d4521f32daeda8d68a0a78fa6e49099cc8b794cf20d9e8b8acd785faf8760	80	\\x000000010000000154c2032fa00071d3f1570ab28ba823af5e006e2ece0da65bc8a1cc6f424f223f678cecf18bcd6d91e0f99f8b2ce4df5f27bad14d345858733d9be116fcd63f2c11a246eb34a7504247008f7d9994acb37f5a9529af7e25552f05d1c739a8593814932dd2cbd604e3fb6f89fbc69441fadc0424ed9f35c4c9c4e536508559e0a5	1	\\xff552dfa027e90d51d61b3851ef6376af1af3dd299dc5d5a9037887fe57f4658120daae61ae6770926e179016458c602b9d3c02161e96c22221d69dd73854100	1638357486000000	0	11000000
24	\\x35339c23f3b327cc148eab2d0523e1cb3e64b1d0e0ba9159d4d83c9bb09cb97769f744be8a4b87792d5026ac623cae12ad2b0b1f806a06dd629d3786872bce5c	70	\\x00000001000000014225e6f8f3a20875693e21cabbe039c47986df2f2657b0b9b2436318ef38e4f43eddfbb51a7085043d76bcc8edd3ab462d4efa1772a3b14cd5dfdd61781b229f1ab7177ae251d2f31516ad604404b23c5415f08ab6d6b08a19e2bb3bb9e2303f07518dffdfbb3585b3fb2a6ee102d5cfeb998361d3af4a6ada047ce6fb8b842a	1	\\xb05c670647ac661c15bb9533d89c1ed68e978bc6f0bd4fccde6b7713285939c931650c1eb9878168bfd9d32e6c8f2f3fda948fc3860434fbfcde22f5191b540a	1638357486000000	0	2000000
25	\\x4b20d80218f4cff2dd06ae0f023566e2aa288646dc6d09cdbae487a0150577483a91f9691e809423450260b10924170f9533781d57cb5a7a2fa082ea8c0d9093	70	\\x00000001000000015c00516be2ad8aa17e9ccaccee42e9ddab2c2c8925a940243fdd05efb196290c5742030d81d3c7f719eb4537d0b531762fe25ba0c7053dbd17b721755e303407808473b34785f5a64b4ec07634363a2e303e03e4011ca146fac23789fe0eab0e0815e0509408b00ce25d583c2d9cc8907c729fb06eb647eb3a2ff8dab37853ef	1	\\x596318cbd51c0907c122de46cce2c115397601d553dd0f0929696cc79fe9e31168ee0d75a56265a929673f9a4ea8af001d20f5d00375a92b5432730748da5109	1638357486000000	0	2000000
26	\\x45b205954142e2ec6b83b843c717f4d312e62ef97efb87c39e67ba54087ddadebe8b7a0dfeea8d1e7cd215d6a0043da47aef74fde4d4ffcbe6724d374531a091	70	\\x0000000100000001143992f51e458cad1dfef94954e05f2a61625df5f319ac6afa6c3898478dfa0414e215537ec4d76f84c3b51e61c22f346db2b5b99c695ae5cca4bc51937779d88b7b0d746f6a57f7f6aa81a1605a57353e03595f1e4d0fc93d171e1421e1c375046c48a15b720cd5e7a9a473e0901fbb27b2f6171d2edac0f2864a49b7198522	1	\\x4b4c65e3050ffef45a92e8e806d4213f6f5f7688f28cc8fd63223249c99026eeb5093afccf7eeb00cfd9423c630b8e884d0b895a5557b5779d8ff6d5c6eb0506	1638357486000000	0	2000000
27	\\x6f819f83af6eac5d61209e16f4ebfcdfc21d881ede4fa8ce5d6772654c24c7963271a9107613f71fe62edc2557d5fd6f905bffd6c41afe2830bf9bd9eed86cca	70	\\x000000010000000115d833c8e67185dd600d8e65d14ba15a9d795dffd9eb5661aa340aa94a465a47ad5db2377d50f9db13eacbc1fbebd262b2bd1cfa1d7a5a761ffa700f10b23ffea5ebf1c4627b53d26a5f36c5e41a4bde202525b7e43b71037c0e52af5edf7f9c576d631a284d4a2049d4c7353d1b31579532f089e7327cc8b5cce387a98cabe1	1	\\xdebdf3b9efbce945bda78582d99f0878159703e33b26436b6aaac773652d808ebfc137c143be1c1de03b1a3ad096612dad5eb61121f49bf12e154e92a07b4b09	1638357486000000	0	2000000
28	\\xd64159126aa657698067a75cf5186b0bb66eac8fc0b53b198d6a970b3fa1e816f109f694b156a86eecebf2acf016708b546cb8a60e206d8079daf80fc90496ee	70	\\x000000010000000161cdc0a3a0900a09c7cd6cc6aa298f376c235c00dbb31b237ec93a10bbdaff644226c49d6a259c243bbad99c090761de8809a87bc3e2c1544aacc3e3281bb81d8c70af61a056c2c5cfbcb2f9c12840b51b3d47dcd8ad9eaf5ea2747c6506d7617790ef455ce66fdf46fb113954f35ed515933902ae5abb202b959ce851dac8ef	1	\\xbdd0cd2c3db17842a14c5c848a22c70fbc2b8ed976e52c2a829e1411e8a5581a61efc385e1dfe011947263a9cce69a2a3e328577ba4c0027e481b7fa0a6e6601	1638357486000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x845e6657b43a04bdbd290d9835d3d8d1ca04ed7dff20541284c27fb421978d11eac6dadbb1420239e63fda1bb687e0cb3479216585f60ca1464ea2d6a889c502	t	1638357463000000
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
1	x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\xcb89eab5e4b8a2e23e36c0bfcffb99bb9436708ce3d68f40d657a5ac3f676fa0a36e1fbfefec9ac4604fc53a04d31e60e571320a42097de80ff57b8700ea160f
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
1	\\x65f608c068a8d7cfc54152e57ed9b472adc08cf8329ec185c7caa668cc52ee15e4c065b52d2f323e096c5d2894a9896315c3a902800a667237af877ef512af29	payto://x-taler-bank/localhost/testuser-v8fyaraj	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660cb3a8ffd7e9e69c646815045edc179e5e7ea1ecd9584550d202ae951ebd572e98	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1638357456440645	0	1024	f	wirewatch-exchange-account-1
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

