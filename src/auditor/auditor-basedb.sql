--
-- PostgreSQL database dump
--

-- Dumped from database version 13.4 (Debian 13.4-3)
-- Dumped by pg_dump version 13.4 (Debian 13.4-3)

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
    shard integer DEFAULT 0 NOT NULL,
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
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding. Should be set based on h_wire, merchant_pub and a service salt. Default of 0 onlyapplies for columns migrated from a previous version without sharding support. 64-bit value because we need an *unsigned* 32-bit value.';


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
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    rrc_serial bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


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
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


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
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


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
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


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
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    deposit_serial_id bigint NOT NULL,
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
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';


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
-- Name: work_shards shard_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards ALTER COLUMN shard_serial_id SET DEFAULT nextval('public.work_shards_shard_serial_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2021-09-05 15:50:06.790312+02	grothoff	{}	{}
exchange-0002	2021-09-05 15:50:06.916554+02	grothoff	{}	{}
exchange-0003	2021-09-05 15:50:07.047827+02	grothoff	{}	{}
merchant-0001	2021-09-05 15:50:07.127287+02	grothoff	{}	{}
merchant-0002	2021-09-05 15:50:07.245712+02	grothoff	{}	{}
auditor-0001	2021-09-05 15:50:07.321642+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-09-05 15:50:15.403053+02	f	ce1cbc4c-9162-4442-85f2-f10410f4ed55	12	1
2	TESTKUDOS:10	7MH40SSAX042GEV0CBP3ZJD956K4BZ6Z9KNZ4MYN2EZ10P45P9M0	2021-09-05 15:50:19.108848+02	f	cfb0b530-5fbe-4bdb-ab95-2f5a1fb7d4d0	2	12
3	TESTKUDOS:100	Joining bonus	2021-09-05 15:50:26.766972+02	f	9e857c37-cf2b-47aa-b199-6ff0f0e20eba	13	1
4	TESTKUDOS:18	DVHAFSQXS8RFM6CBYSA377SPREM7QR9TGWZ9QCBXZVCV0WJNJEJ0	2021-09-05 15:50:27.54151+02	f	10c1c4f3-a188-4b30-9dc4-98ad8d55fc61	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
88145ad0-f8af-4461-a2d1-b87e08b5750b	TESTKUDOS:10	t	t	f	7MH40SSAX042GEV0CBP3ZJD956K4BZ6Z9KNZ4MYN2EZ10P45P9M0	2	12
966ecf96-19aa-4862-8cfc-639825621851	TESTKUDOS:18	t	t	f	DVHAFSQXS8RFM6CBYSA377SPREM7QR9TGWZ9QCBXZVCV0WJNJEJ0	2	13
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
1	1	58	\\x007d8eb38ec129c625b29316d4001940c5104985ce37e363fd51588a33b4d00689a2327446550cc917a138a89623fc64a5e6e23d86c8bf9483ef54c6b9b5dc00
2	1	319	\\x025447f83c972339eb11eb27a1559a6a54b61fff5ed9f5283f70094887bdea6f34430382b1391df33a3c824269c32abb82a22ee32f0701bc6c696cb6081add00
3	1	320	\\xa79b5e5614b9d0a9b6d3e9a512f63a461987e69ff0bf364a2160f84e6f77ca59c8b35bd761bdac728766640e09cbc7d7dbeb598a97f3eb719e82c5fc72c15b04
4	1	360	\\x93497a23a28f26199ffd95d28db8a5de916ac46815d6488fdbbd94080be7f568f707865b0a94c1fccbe77dfcc3545ae2ff422ba5874c77636facc5942ccb8303
5	1	423	\\x8c07713a18d42b28e3991b6cd08cc58041a3d6e176cb43e8ac0df34983f3f70c02d9c3456f29ad1942e162e8452fc509392e770a0179890e61d1ec6f1217a50f
6	1	179	\\xe4037e11e9aa35ec79584e973c2829c387037de6e5419dfab8e7c489f7e5fa03054678395ab3af93a9e6e26ecb38af362d393c2fef8dd050a80f9465c5f1ed0f
7	1	210	\\xa80c3ae52a0e8505e33bfd53934fdecd7d86c1dab75c8b0c9a822d10fbc21b966b56a729e8fceb0ff65794174c563fdc28acbf669d55d578e7162f4bf849a507
8	1	264	\\x918ffaa84143812d1961d652ef63814e18ff9f8f8db8b51f8373e2a1b168e580f638ac61cdc2cdf134a7d9548bc41f5fe765d5e3282952a26d1168a8742e280c
9	1	392	\\x2809418a5f96464be1eb8b9babe255a4faa010696c9130d405372274e6bac155bde31c05d5428ad92a3341424143bfff18a108bb581722e7c3426b3b6667350a
10	1	300	\\x5371b37ab9a909023860ac9d31043134fecdd2569b1e931cc109e73c5c65e37e3a746ad678dcb2f0fd37ff103b77958e9319301dfebf1394e11fccb936c81d04
11	1	115	\\x03d53c7e830446cbabb0bfb2252306d1c0d096120e19d7da69f7842c082d00450cf282dec06d16f166fceae525bc970dc6b7eb58626b3b86c2bd26452a76370c
12	1	195	\\x54c32e55beb7f6a0ab849a7ee1035e7d77abc1fd26bbc0e5c72c9b39d3156c3d8feec919fae86e7873ad8102adffe15407e67d0f3bf54981a31d62130dfe6a00
13	1	140	\\x06a882a2cc6d5581590e871d1b22806098a560d0f0fbb003eb39280ae0238802be86f4fe348a72f340bba21e5ca037425961417907f16f1334a5f72ef9f2a602
14	1	343	\\x596cf5d4ebb344b3f76deb4159aa93ce32b1348d6d6356bb1fb6bcd336bae23d619309e943790134fdde65a91bc5a5d5d24f3743276394d1c6f78c1d1228a70d
15	1	274	\\x9d0884f1d24bb19dcc00945697e7d0f05a4e599cf9f650a7f155a66ae03e06019be2ee17ad7ef6a22f9b480857e4f1f08a47c0205ff813f8f6788364e80dee03
16	1	421	\\x03b8803f065c02ab0a2d6f3995100956750bd2a967e6258c7eac06c18e14ec44993f5fdbda930da17fd6099f841dc122f22702d310a3edcabca21bf39db79809
17	1	194	\\x8a26b8e4fd321caeabd0232970311f23a87cdea509d641a4f5a16dcff418e86b1a6635be855401d04152776dfc5ab00966e5e8d2b422400f0026ab3c1bd67809
18	1	144	\\x9bdca495255ee18bc5e5ee5cac6fdac1161f226de6181f0b116fce2e02035a27f58aaf1a0917fc706156405bd6149ec9612e813413a8a12180fc062433d8eb02
19	1	402	\\xe2cc951c79290920ddf76293337d44afd69819e74495d031351ca6099082a39555693964d5f5dfc6734bfcf7c57f7bda8c2683539867a8a0d8f8d9c9946bb005
20	1	137	\\xbd79ac43e2f6b0eab3500a0dcf7c4ddc27dd1aa871a6fa6f857df76e61491ce6c1acdf016f1342f07659ed60d21ca24b97e070b0008562c55dc67dbdced69f00
21	1	30	\\x2ce40578b8f5616703e5c8c7f6e44a2385d778f1dd23df36402d6b881b24349e8c5fcb5eaae14ce72da0b6f13273fdfab7be16663f18ffc20dba87ea47414805
22	1	289	\\x4910c4afc10e2cf099d490e8cab933a69b74f13bea11387ef9381815ac91fc88e36c67ca244fd8d18aa2b0f0e63f6318dc8cc674abb6faf752e7153a2ee18f0d
23	1	209	\\x6fa121261147953f14877ebb4d0a88ff0574efa3d554ed573ea4757b9e86ef336c5902e165355d80e5414bd04c7ff0476d6fa61dfa559a5f0af532d3c4cca003
24	1	295	\\x83fa672c66140ef6ab606369b34635690a2d640fc23f83d41a412714ff529353fcdffaa16785ce80a52af17bbb693790057729f7eb83569b565043a9e4902401
25	1	230	\\xf73f0bb60e7e34747cfa25736a978ad2b0653ffbda1043ecc5da09e60912e31365770a6ab54a70c961f43ac12d8f6a81fa641ec2ba8a060913e72642ade69a07
26	1	403	\\x1d8dbfae62b0ea15cb60223e5ef900519732725bcc343d9a5107ea3d3db47ae99473ee04d378f226f4b31e39d7f6b688ee081aa213ae849141d04f5d5b8baf0f
27	1	333	\\x284ef67531e43728cfbf3e22352eb8a43a58bfef271551779af9eb96ddf9b510df2bcdf7fa77ed01ad65c0368feea5e11704d1fd4fb38316d6fb8623e911120e
28	1	39	\\x10bd5d7f2271ce08682640a48b2f02cbec650a924c930273e3d9208c1054926c43e153cd0ee6c760a387d2db5dfc7dcf74842e0c8d0fa8d659a9cf8c34266c0e
29	1	117	\\x5c5cdf0442b830a88b791d7d3bc5bdf3faefaf7c77254694f199c4d96667182b88301e1052ad192412f620b217d7707253059619a2f913c5e3e655bae2bb8204
30	1	90	\\x5712a01c7a884f62079b9e9413f4d92be1ed5cc59734441c16f9368536734e70ea95ccba26351dbc323cafb422a502ac75dee43af5b05a29ade0736c854b4d03
31	1	17	\\x89e5d9e42dd1cf34c89d5e59208261e36c9870f6c2275d8d5fcb9d6406e1f025bd9ada80f015cc8956a4c8380c1fabeefd7acd03cb11fe04a0527d4ae83f9409
32	1	45	\\x1fff5e80ed35ab3be0ec847ed1877a13d7c55bb0754b75d349890e8fe65a42159ac3011cfce31898705d1ca46a07c2ec49b767773fa4160f51ce7418c6d2df0a
33	1	29	\\x144386e56de58b0f642e111ed0e6c7291867c2aaabd402d4a58fe7967f2cff65700b01bfd585a74b933c0d2668554fe86b585eca051a599d83f5cc6d24f68c06
34	1	135	\\xab080de6ded678c5ea68c4a6c7b0cf9991028e83930700a7ee68e4c30fee7392d57cf00730ce0a8a9b2d490b459f51335563d57987014ddaefdf3b85a0bd9302
35	1	253	\\x653b45587d40882284edebca182a2592c941fa650ca8a42abd157209afbb2573160089446c70e0e709af8fd34cab87569d494feed67191bc43f3e37c45d43d09
36	1	54	\\x79d2d608edc35733dda12afb098ac89105049e48e3373365fd70a1258c485af11489862a662450c22dc4682b0b7fa362eb12adb3b845140d574e57b92392450e
37	1	335	\\xd6e31a7480a782c6b6b7d178733312fa7459663db31a0f8b7b1e6d121d484b8e6d0669c74b5f8df604bb96105b6646d0cd44600c8a86e947af84a77f333b6b01
38	1	265	\\x4d379f82d0396f0d20742154c661611b65e9c99ee11481763b87a21d21c25500508f33abb0c895f9ca840798e8d067fca6d28abdf9a23880bb22a50269ae540c
39	1	187	\\x11a662ca85bbba8164e46bb2484381e01d6d53623aeab5e5d46833f53fc01bb401e2b86aa68516fc40064e34ea375a80785386638b73357a6ccdb1bf82c2ac04
40	1	72	\\xeb09a54178bedf48e02e0d06c6fe3fa48ed5863396e98e7645dc39aa8846492a12f6a78a72bb05dc2bb4ef79fb0a80e2fd763c8015f2291ac483865376e59b04
41	1	371	\\xabe7d60294eb4bcf6037ac7176b478a99638c1088046213c3dfca624125ef616c3daef8b93ee98ca513b67af72326c99ce979763c16c2f3d6f5844663ae5e707
42	1	276	\\x4fbbfabc1735cadc928a322916a25697cc9efc10c8cde2f84f0a519fed32e706f70da050b2e9aeeb7ea743ea3d937ad6c58c9becfee3a37dee2bc190057d4e04
43	1	345	\\x5cea2b3d73be4a19db12fbf2f61b36f0895e5c8356f8e8eef4cb5bf54c25a35018379d277eca1590d2699acc43b63920bf5097fdedd07f590afd441cc9153800
44	1	40	\\xfcb2b88bb11326207e0d1773ed029b8a32c083875949e97fbefa5f7c02d41f203669aacfbf59e913238c5c7d4fea91970bd6327ec9ac56d5199c2a6180c51e0c
45	1	19	\\xbc3f874325ad7c07e0b4ce8761cf2dfa704a242d8471a3f886d9c75cb5a52da6ea4234e072cb3e2250aedd65efb0af46dad11fc93f89626ec5447ea4b8bbf201
46	1	233	\\x0f486412cb889e5f7d9e09bc16e5ddec02d013c980dd45bb7c32e8a85819e490bf0147c89760d70ce25efee1649e597ce9fa0e4bf1704848b75b641cb1c71a01
47	1	411	\\x234fe3504e0d6805c6be84a2ca32d1b2be1a8daee92bd24aae8663dcb1f525f38586a0c494b7ceef60618b9a87fada9902c9c8fef0b8593a1d6d90798d43cf02
48	1	354	\\xccfd1f20d151d263e98e75d795a6ee599a0fbe8a8021f13a48ea2e15746316bda3957138d9cd8954cfbad99b5ec865971b91ea9ed738652cfd530e3db4902003
49	1	42	\\x24087268c6480f6af1b8e67801dd2e35f3ceeeef87894d677a37ca31954727c831e89babfc57202db15673a084761aa6fa8bc8d04cd2b3a1313bd21e771dc308
50	1	141	\\x3ad5a936b61818c0368d4a68218748188e54763cf4e13467d74f73d69f897ecf3fa8e0886ff120c544ae40776e4af2e8d5f03a3d61db9f8c903b82dd497f3c0e
51	1	225	\\x32f03a3bfcb55e741862892f123fa087356c04c53aa6384f1fc55b3545a5f77e36b8836e34d4bc474e0a1cbd079ac0f81d41db722b8743f11574b51bf678ff04
52	1	397	\\x34e21b268bd017f6b751bddc44f1225d3cd9c2b80032e21c469d34302dea6abc08b3972d6fdca0be1c6ece33993b319b30bca3df4121dee3dcc53a958776d908
53	1	363	\\x396a4f470ef559c64ca534ab6099f2f38d875f285ed2d363706ac0afe9c123fa1152301351e05673a2f39a405577bfe24c3516602a53f9f6fef4dcc7b7e8ed04
54	1	358	\\x75dfad066ae67835be5c19ea480a50f76e47b142f6d47b5f853df525f38dfeed881ca3d90fe4662232f6500cdf97e472892faac4962c2adc6bbe7908a865890f
55	1	240	\\xc06ba438b4fb8b4283acba0833f25142d57c9a5ed0d82d98835fbd134003c9fd567fb7fff1c968c993ace05deb132b357e0d16b3dfdda02b7cc0d508cfa9de0d
56	1	15	\\x82610fc607b2ff5445a51868c1d857ab9ed2c378ee828c81b118252f62fe5b282225b882d70c6f816acd42b1dbd34077ea1966d0d89203c916ce11f637a94f06
57	1	266	\\x05c7308eec8dd313685f44d47edfe1122e6a50ad344bfed9cb2e817fd9544e360b8f9e9e0f4dfd7d25afc05e747df48aa76a7f4b0bc7c501fd9c459dda324c07
58	1	78	\\x85fbcd490cc7d923820ce09701cf7f411578b52da8f957b58c66c0a82ee877ba2115be7440879ac22eb5177bd983624dfd541e8f79e43de5d57490a52ea36304
59	1	262	\\xdffbcf571efaee20c23196525922e3460920b569725582157cf8edc6a7a17f766dd0851abb4787c8687dbcfe3bcc04aa4d9aa2014176d5a62c083b6ac2ccc10f
60	1	249	\\x35a2ad81f650263d90b69179f69fd4704050e4853837016210600776097e22d37f2453c4455c021159d42f2177a284c5f572253022f87993bd8dd052e95e9103
61	1	367	\\xa238e7f4cf2e3a68f000eaabfab3e9f813fc57211520de90bd1969f0fc6e1299e3beace220d5fb0399c6ecd28c63da535e4f8e273220a0bb6179067492e51e09
62	1	26	\\x8f87660ccb8025fd6f62c9d53f50465847eb00148185cf9de86e12833e211f1a36ebed053c13fe77c3a25cf8a84fc61f3077241cfe296131933e65c1299a9600
63	1	50	\\xbd613952c44e0b1f952514fc472b8b424444304b79f46dbfe9cc401c548498ac55e3f10400e645f3106dbfa55f9aa6dc6482379a420e88dd47e7d40cfac88708
64	1	314	\\x852ce26a26c3083ad05277eb31059bed727966e272ee0bfa2309738e58476cccd2e541d9759f91b55568ed0066cecdae01ea9707f5579fc8e6965721086b510e
65	1	413	\\x37b5a9dabc03756af7129f10912fbccb91e45b240573b1d3fb100866bf9e1aee4f611a8c5d0c6153b681d4bbc69f3f6dd13d1026719c23f9f5d4a06f26a6ea0c
66	1	91	\\xb33d9e96e377dc72c04765f75b4f3e81c441861fb72a0771f4b783c22b3f9a04f76d1f21dfb908b07d4249dad19fa5688d4efa0b8dcf11a22678e4adf7f4840d
67	1	110	\\x0903c3ef0912c166c7d4adbf40514daf14a4c345bb5409946dc4b2612cffc9500a4b45d47af30df88900dd78f21bb06e7617653b527ef5980c3ff5ddf4fba103
68	1	294	\\x7fc648c79c2cad6f241ebeae67db2ecc81c85e3000b324c343dff43e3877ce6324dfb46e929a9213a8d9bafe61ad810173255d820f1d83ef7bb6b2738e93f90d
69	1	112	\\xd60cd115674f65072477c2a0136aa999991d6a5318fd3a95322e91728b3bc8d85ba7cc41af5275d57665aca4cc19f2c477142aae9d4212349e7b36b1f1fe5305
70	1	122	\\xe7ce78211a6a98df8563962943ca2aa210fb0dce200748e7c5ec0810618f57817cca8489fd7fe811698953099add00c02648fd3975eb4aa84168d5827c272500
71	1	260	\\x6adb94b8a699cc99212aadb5bde16d55d30cf2f253e47264cfc236034735252a0625229277a8951694fb43cc9242022503e79352f8c5dc321937aca970462401
72	1	43	\\xc9d00d45339c576bb1d9fbca3ec5f94f7796480c74bde85fba17d59db60ca3f604c2bb658069e59ee365605a3d8664430f17a12b2bfb15953980174249d56e0c
73	1	161	\\x0ee6250ddde4cb8b003b6011851c930dc349c4b68ea5a6aa17d4098c31f2677d98be0d6eeed60e54fdab561e3252de3133b4c8381ad2c0c90fd5bec8a9e1ea07
74	1	20	\\xd7d288a168a3e0af147c684419331a3343df456b7690afdf6c576d5464bb9f5236b91c2480d5451c50ea0853377fbea59f5c93eaa3a0d2c3b66129b1fbbf6202
75	1	293	\\xa0f173bf51aaface3c0c841e7d2d5747efc541c783143b5f4a75ef8fb4f409f45e5bf7af3f384a45c484399f9875221b42210413ea6d6b7fb85b9838e9360b08
76	1	8	\\x383836ccbf2a43d8f1f69c824bc0de6982a909c2700b176add93bdc4c83bb7797f02d455ca441a35f6a94c8d45043b334b3dec075d23d5a88ab5e7dc59278e0a
77	1	322	\\xd8d581c64c21adf3fd726b79638d9e49b32d289e1bacf136f4b6b0dfe5dadf7692185de88244ee1689382a102bcb5ff3f484443a4a0b3d3ff15ca7d2d5ae5b0a
78	1	395	\\xd96f74c18ad03be5f7aa7dbd40556e0f204a9698a2aebe10a9b209c6fecbc946e6b6aa97a301518cf44406509edb88ba95df3dd11886d76ce6456b204f1a830a
79	1	208	\\xce47b593a72a751efda42d79958bcdb1987456e353d5571b209b3c542a428dc338ea5852016e51aa8501b9bb0dd3d585d7e3a7b9d169b2a96468b37d043a0f0f
80	1	142	\\x46e00569164e0cf4e88befa5cfbf65af6c269d6514707db13d63b31492f33d1a5c0e8491a7d087e18b9c000a819a2e3cda0f2635b7732e664c967c4d6a5e5308
81	1	204	\\xbec4276b3e4b089d9657cdeab7be7e1b4281741d4c84737636593393dd95b11e1b21f9a8e6c1e1608fa9963123172491f311fd469d7b500e26476ff441c38309
82	1	390	\\x101389a92789fc0166866fa6fd57640ba4f8bdbacb7c3c4374d84050751fc36be5c4945393ae88efe7f7b3fa4386f4b1159e3dc9bf96a534abae5c8d4f027c07
83	1	327	\\x8d0987fd5dd45e4e927861d2e320ea3d3af893ad2a377f4952a4898c1a6e8a8798909b47fa7f22f5c4cd390d25b0912698f9d6ac083fdedb1af58233dbb92e0b
84	1	377	\\xce36d63786650dab6fa447814e2a174f3fc637c3a00f9e88ffb9a86b238a725aec71c718c77f1eb6e6ea0f4b3e57fe1896d329fa1a08e33d2e50d31d6ee0ba09
85	1	370	\\x63ad5591c27c7570ea223d6ec78ffc67b07e95e2e5b899891214f4a36caa0355718b619c6e0562081a08d115a907127d2aa078997ef0bbd3abcf67096b55d504
86	1	63	\\xf9c3092a28bb3c7b794a710b7ea84f810176e0a3cb30e36f4c1fde46eef7d7e25bf823ba3ddb9207d9ccf1f51d31354af673d2a84e77c007f26bda741589ab03
87	1	263	\\x57c5ba6deafd5821535333af433c4af622c2167411b33b82eb9bd226ae8a8adc3526b429cef59b118a9b4657f45d74e24b15374a07a451f11c6a544a15e2d004
88	1	120	\\x207098a349005dd5e4c51df9c54b665c1d42ee2c54c821ce31ad9be50780e3f4a3d9282c893c846923e119fc57121a101beaa2dde56599a4cf712d1773843c0c
89	1	213	\\xc220b63b5c714aca4c63b9d4cff8d576627e76a2399ed76b441e8a887939a62d3b77c20ca6d86153d623b02ee88c1d3cf12e0b463bf1296ae4e400216a42420f
90	1	124	\\x6387e2bf85a0dccb1f0df7050248a8cd6741464c4ffa9ba0bc8a25133448153513e100d65c020ca027b1528dbc8ff01efa2b20c3a9d578aa89c44294cb8d2f05
91	1	393	\\x29b9df06d74931f7c3365748f442e67da66e4be2db55c7c01cac3144192a29b2b2707409abeb92f74c65a4568b5838e3606e0d4b5094ce7042fbe8750be09201
92	1	48	\\x709d68b40a2b3d976b481b1ac9469aaf6452ca49cafdd978530b8914fd40127cb79b58f1d0209ef9bc777706846de6b28233d43b6a3e54435b0d1b0335b4790f
93	1	23	\\x198e770040545b08e23282b584923ed626f74f475e14d9e508619e9c8bf6b4a36b2e854690311fd26229bad23fce48480f85eff7534628f1504dc82c5e5fa205
94	1	49	\\x45286ac9f9c457bd0dc7c50d94508814b42739b1b0be2533160f52804abc368c26b095b1a0d9a37ef31c37922cd50ca4e536452e305bfe64fa57a8be86ae730f
95	1	116	\\xf52ecb60b47c110d0ab80bc1ad95563e5c7ebbcedd50e311952bdfa0596bce0e1eb6c9272329719bee663bd82abf0c5040b3d2b4a0ed8aa08efd16b58420d103
96	1	73	\\x26af7430ac6312408ccdd4a0660b7bddb2d7d313c2900bcadf009c7e74358a7764901ef202875923a28daf0f5868d6ddbbc6e2e1513ac3ce16b1af4ef055eb06
97	1	220	\\x709dbc5721ce613f9e2de911441877b330114b65ba6295d90f76548362f06ae5232c06f5885cb9767a3d04db433d1859a3bd15aab4fc8edb77af7bc8acdb7c09
98	1	418	\\x4368ea86aab272a019bc52b51a04a80eefff9a26649023bc74c1255026a81a8ccd282e290590c885b0bc4b38c710d14cb98f59fd1b7a665497a08fc8a9d30a06
99	1	297	\\x78a20fffbc662ea2902853e41a6ceedeff0415af035f2b5a8ced4590bf9c0784126c7f47f0bfdeaad83fbe3027776c90a0aa5560ccdbd10e911e664c981e7f04
100	1	317	\\xaef962f85b29f2c84b0662f0a4d57ca9795dad4dacb23771a12de05f083e9c4d246a607fbf05e4e999770220e5542836cd5c0d53ffef937e81ecb1c22e81500d
101	1	193	\\x0039735829bc2a4496cfa0987ca1432579f0caa2ff3edb85dc65590e0ab8075df8c3fa60573ecda907fb013f987f63112d90205db2e159adc48e76e1e1907f0d
102	1	299	\\x2f2743acd47956a28481c17293b281438de36f8a9b2e7dfbaaa9f1f970cd22316180309ce9dc91b8cb589d8480b86e22a49cbd5ba3a9edde47297f3c7abd080a
103	1	419	\\x4b2b7fc4d05505e448611f4604ed9a6221385d562fd2b7caffe73f7787da91afb183b8475e3244f20eb4167240a07919e60a87330365dc36bcf0ca538ec9e401
104	1	32	\\xcf691f050e712e433832f79b316b881d9841a88571d75bdbb308d9c7ca3f4d2f33b00f619acfb14cd532900015b9a0825a344064fb11e0db96ad9fb4fe420d03
105	1	33	\\x08910167e0b87026ed89ac2aee3b7d97a815737daa81c90f0432f4cf5cff58d0f1da3ad3e75132c5a65483124e1f5d8767eb84dadc474a840a10bf025b35c106
106	1	348	\\x3158d4c8c0ab55e4791b2155b17fe7ec4aa1ee5f0bd861d5cfde3bf89dc77766590337bbefa07d1ced508bd247893177e6bdd30a46529d78165e473b8f5f530c
107	1	88	\\xabcd55bdea3ea5f5f1cc96c9659d7fa3667b06242d8b4fda1ba530c26d6276d1439e19285e6288c4be169053dc00a8fdbb9ef063faf602d391e8485dac76b307
108	1	332	\\xe24782bddf64527fdab51f0eda61a816d24d0d8d49687cbc9bb9ce38025beb03ab094e94da9fc764fa49e4aac192af59467cc777022540e71c6ca4afe39c840b
109	1	380	\\xbb1dcb2f5b0c8a2106d4e9760ca35a01a8fc0feae4c056b445d5755de93660686139788392acdc3c6447e9a4355203b6535132a3ccb55f1ef5d634738bb10702
110	1	219	\\x7e8462ebd2e450bfff04252f3c32b356d0c35e21ff256f383e9ff71cf024c9f08af2116eafb79a187038300dbf98a4f3d5e492fd36dc92edbb2983d02332950d
111	1	417	\\x26250e5c5e2934ad451f9fd9e8d561c93c817b36560d5bac763af8321e3061a6ee1dd58d9815dc626a43ebf0e37e0f28281ca28e2b4d7bc3c4c38bf71ed54009
112	1	368	\\x1a0e9f4ec53eb79eeb3d8fba26a28f45d015274d82dd36c1ac0fa9c1ca4de759b07e1d8f8a84bc73edb235c93cc063e5901b8474b3a68bc67d05f3c252d61b0d
113	1	162	\\xd22d609996b36814f6c799d71767fb6b17922ed04d42fb7dcb4fc67291588f7b41b9e351e1c7e35ff368afc715a3c529a3f16e88a44442f03aedc47289e9ba0a
114	1	313	\\x20e33611621ac0678b3da4746ab71a94e7c2c77740383cb976c0a3efdb8df9b465be96f721560f784dcf67cbd8ed37957801dfa6d45592cb128566734cb9a004
115	1	361	\\x9086d2df656441ce8e10aa38f9bbd2fd11ab69d57f68e9fd114817af294aa68422fb68745c2b233a3b9d805343dc85a5a55e274b7e81d6fac39c7f294a432507
116	1	4	\\x949f45d7f23460d5e2a96d519fb8a1523c2a9444488803f02224640ac1039fe52cc4dcd896f9ebe6a11b81be2b57f965e51c3484af4496806a779674f9b2840a
117	1	199	\\x3f5d91003544b6653fb2023dac38406f35da72af3cde1c8806b863a5f91f977e03c33bec8efd4e2c0a8ab9e27490860cb449f8f3a170b48c3474f9b70cb4420a
118	1	408	\\x3d93ce8a508d501750af6661542a71cba460e09c53a4cc7f518f2d1308de4a556b23574bed58674604a40e5800a72a581b3f63f4be753bdcf74eff8485ae0805
119	1	197	\\x37cd27dc99931f49afe6f1436b4b26c06746fcdbcdf663378f9ccd32b3f1b57037ffd656fd2cb887fdbedb62a7fb2e248de22a74f6b1be5483c14f9499bf200f
120	1	201	\\x98061ada974f169228e93a8cb31a6233ad85576c89c7ec2bada7193fed883acee6093add2beebf682e78e2776e4a825748e46a9d0f2f9141dd5489046adc7d09
121	1	298	\\xaecc357403cb611f36d0e72a00668a0fef10bbe35d19bb630b809a1044558a8da2f1dde11c5cee086e981b905e9cf9d373aa4dcb60e5e23957fab392884dc90e
122	1	283	\\x6bb5232fdfeb6f6682f0397a7a41967ef50e3f0b1fdead1b1d0ec25f3897bde9ead778a1886754fa183f037b44e0e15b079a28df5c7b5d116f5919f20fecdc01
123	1	254	\\x849d1229fe0ec360350454fea1f41a9760a7ae84e344e74b92702688e64afbe0fa6fa0d3e5da72fe3a8b8ba92400a83f96bf6d27e6a59555aef66cdbc9295e00
124	1	205	\\x28a351039a52dd41246f6e73250d59981c8dc16fde257a66cc6a2f0e5df5af79ab4e551816fca57c434aff54f2021f856969db7d28346ade15b982c6564fa505
125	1	60	\\xb1e9ea30218a43d9a1741d8f15174e93ce4d228c38523aeba25a8290e52fd5fa53c170fba8b5db7254be78ecd4132234b76f4d3e16edb9a60c9efcc369ae420b
126	1	149	\\x655ce9c2d493ad41d7937676eb8d46b7810ff828cd2ed5320abaf26a109abcd7e2089e6f0da5de0df9e8bfd8fdc25798206857bdc83a1a3bf1b70d2ce9b05a0d
127	1	273	\\xaff1c4065b155928496a052e0e28d149e905c12f2a57aa353f46bd69ed33eaf926a9cc0a74b17b6bb8e5a89bcbd41bb6e064e70c636f487266eb4c5bbc516e00
128	1	248	\\x93607ea8eba12a52761af178241c838ed2f4c408a11b64cafc5e15558db2ac3e7e00c61d32c01c0eca56571a397bd216c62928349a723b5558b1c0b3e0da460c
129	1	406	\\xe79f2a8304bed3490e180e0e2f6ce1636569ee88c457d9d7dd0f7cd93ebd96c1230e961df4ac78234e518e1d0a3a7aadd8cc6a5c8ef98b813d8353bccd7a340b
130	1	278	\\x5910533ad0edc6911c4d19d1f95c0f5d1eddb188a19431082957a439cfbe71bc718f036b28f59f76638aba32e1be168a4dd0aac5d676e8655849fee7ffe0a808
131	1	226	\\xd905c75956b9e02f4dd6c205b34acbd230c70f4059e286f17249f589b297cebc3ab03de62e161c00e7506eceb2a60209fa1b9916879aad5cccf9fdff806a420e
132	1	326	\\xd17ac6033a7ba34f1fc36ad236cb3837071380d4a6a6b154584af89aa22e05ca114aab17a1085992a53f44b133a94e01a07c8a2b19c5b71a4dd029e0baaf2802
133	1	330	\\x6d74f5e262ba01d84895b08ae061737c3729db5bb89892436f1c4f0a1f0b02a0ec82cb809c219c9b8a2fb75f1b550fc1e77e3e28096695f019e39125100ae900
134	1	146	\\x3b567ef98f70b664813a030417da1a517ccba503eea674fc5af344246450cdac0b7303bd40ed4300d07ce7ee1373d63fb81963eb6aa8e71875293dfd02031000
135	1	168	\\x107c592fc15ec4a4949213ae8c78ac6b98c91f6f0b2ab4a50a437e48634ed073236ada48ce8c7775cb0969731803e5e9947f11f39f883d4355ea743da12d5601
136	1	36	\\xc709dfa063719ab3021985f8745f065c69409cf70d47d8d5ffd8e6ce1d05dae9426fab0b9afc311728e7d0c1b5e8ed356eb25b7cd09b666f16faf0a30ecf6d0d
137	1	59	\\xf9b108e93c96031865716ce1222d5cee69c230eb298b21cdf29ba5915b00f00ba4da3605136922132744a621fc194fd36e3453ece4d32317824036d8425c8501
138	1	318	\\xb8af6c3f4bd594697cccad83e536ba2d08be6cd0d23a463ad44b164c8564c0f69681be15c0444faf7fd418bc6da00a2609771636f6a0779427ac0d8e57635a08
139	1	52	\\x333125ba2c0ff3db922d1f4688fe38f581043c353d1505c21c5ba3492aa51112f43695f594a009205a106ddf51d0f3530fbe1b1343a51313dae2ee8c9bb3490e
140	1	399	\\x7d28f76753832dff819e51db348e843b8100ee3ad2b3c15b183771992e1e0998c19837f68793804f36cc1a42d1bfad580058196126f5ad6a3631593ddd8f760f
141	1	156	\\xfb0b4e8e9fdf7f8d87ff60a706f407de5a753e5c74659c367d59964172aedb76b68578531fe5ed85aa9e6ed064d5876d77561a523b4fce7d57b80818ac6ad60f
142	1	172	\\x556318f030078754132ce040c96800ced844bf8d6306cf76ff61a0065880e886b2c7ca098a098c51f6e8bd831c583d814896851e05d96bc34a3c877956e43f09
143	1	331	\\x0c63cb1c67a11a80451a1c2e00dc5574a9767cab38442c601e051f868fb158e39d6b38dbb230aac5f241d8fa1a2ceaa3adb2e4671d759d9a58264cc70d7dc90a
144	1	401	\\x300eac0c2041199a65c8bd88b4691cb26048beb9088ecd863609f3b4df234317e700a3d3afcb82c0d3adff08aad11b090ff2225d0eb1f6905560918207bec905
145	1	111	\\xf914b31b1b8cc61833915c4ed8954fb62f9555163d5b57abc424f97a346f63559edd4435171652580802818c1035e2b27c34171c417dae600f28a551a4faa202
146	1	228	\\x45f24e13b8179a3c6bfa0b9029878e289431e691d0082d72fc985e89588b861786c109a2b882a7b1b612550418a5be621ecdfe3e912f5de912fa626ba4ee6b04
147	1	290	\\xdece6a3c204d7699c6698ff915dd4ca5b2e684f01d356bb868973f22d82495a137456472c001748bd2bc7a120c22dfc939eb8a9c0d0bff3171183bdaefe70101
148	1	154	\\xf3d6e8d5f841749616f4c19325b07d1f7cb16ee1d3bdc0e9863d2ada5fa9260d2ddf25a0c408dd06d169da27f6dc6bff384e04128e680a91db278ad9f7a49a07
149	1	71	\\x06e20dcf4fd57370c0effe9ac8e431ea4e89d1b119f6589d8d090ee1d4431c06f4acda6381adca562c07bdde7ac79dececc87a31286107297dc3cea228021e0f
150	1	106	\\xade6c872b1e8febe12be5258f6dd0ef9a21d58c6c7584c30c30681973c0c6bc58ded46e24d422d7d44854ecf99372a8a692cde25773020d933ea2dc95e8c8d05
151	1	288	\\xc4a5dca834c84639e9446a3b1cb4bcbe4b3b99c37da0a300bff7cc49288659bd25ea5151838349451b9b7da6b0016d5274010f86df2ffd3f6aaa1beea25afb03
152	1	252	\\x42c45793596a03e34b3b62c2fda3919a8a3aaafc5c05b023a14e5d3c099c3237ff22732ef4d1f62ebcc090277882f441fe30a3ffafcad858fa35855bb0877c00
153	1	323	\\xdd2b93dcaa4b1a01ff74ee0f48da0873183a3a1b3349e299620a29ab540c9f8177c765d830d404b4f04ff6dde54e6b4ae8f224a892ca7b1918be8081da807709
154	1	125	\\xe0a2acaae6110fa2dd8454c4ba0f9470580e2ea0dc5f66a03b064089acb3707b38ff6a197fa1d3004cbff2de885d30358aa0bdabc69cafabe50ee29b9672b300
155	1	282	\\xbca9fdc28e5149a08f9b5ce8ade869197305c714c4eaf4be3d7e026c3d0c41143c978ebe8decea5a32e7e970f1a3e40609dfef8fbb55408543937861646ba503
156	1	143	\\xc9351e9c26f41e959a2a6cd24705e11c5213fb216b30683df5de7c62a9f65f783bf047904d5814323cef491f044cdefec7130ea386808f8de2434aad667bd708
157	1	291	\\xccd6765995551b4c6ef3c6c91293caa405fe20842e136532c775eac0987d619f91ff0caf5bcf093c2d013ab5f7dd70aeb6709f57f697b68a85a2ca6b5b33aa06
158	1	28	\\x1fe39b15ac0f811d4118c08656a81b6fc9d6165277744d163d2c3680bbc1e9b844129615124c0365c2ac9d18ac097a91ec41f75fefb4b929c650fe1d0a1b1606
159	1	131	\\x3612cf044ddd0c57406c46a78f933b3a1107e7fff6f23711bac3f115cc63855d51bd45d6f5aeeadc7ca76171046fd37391beeab708c75d895c544ed96e6d4609
160	1	296	\\x6693209a98c5b52c3bb5100d836dd26b005ef45644e392da333d5f185ca30fb499d80788a6ea6da54e6bb4ab1090dd557170db1c83dfeef95d0378be995bc703
161	1	87	\\xb5b51227ab7fed53e92621efabc9a4b560c1493f9dc56277c8708975506395b53b4d6e28bffdd141bf36e4c6e404bf773df96a62a41ac6072e648862318e4a00
162	1	275	\\x5540a7da6a1923354ba0230a850a12c345cee8941e4b85015a236f3646912a9ea1bb91db4902d48483553077cc17f5f7497b1c5dd92ba8f80b6397d31bfaa007
163	1	280	\\x15e9a481e3e0388d3c9739903252b425e1e731081e9bf07a534264e06062446cd8e521b720c8110ad97d4ff4c63bfdb1920190a1c364eb2128cdc62048d0a703
164	1	415	\\x9d4709f18c81efc17507e9c64300e4b19264d9055617bde86530ecf78b8f63338db0e3f441746db3ee18f8b4b31d7257a05d719f96d7bc0e61f24138fa3c3200
165	1	325	\\x1fc62b9ad83813a218a170c8b00b0d125fec8fd2640fdebd6a2bc256aec78561188d76ca1d09753252861b6143c48a951c575728809d25392bb28ee88bd88000
166	1	79	\\x0ec807196ef312e126366f06a7db60b860df9da9a6144cb4d043e64afaaa281e6263df36b56182f0fdbc3830f8ff9d328fb4a6eb6357058e756535ea7dd96a03
167	1	85	\\x838925cc671f348267395f664b06a505c5b6ddad5476c60dcb588d8547d4255ac6c5eb6f1adbc16ef55058c8eec3bab1e2901d4c39810272011fd9636e6cf00f
168	1	217	\\x990bb675a278eed58e141bd278b08936bcc3c6f1260bc1f68b76b58466f213ae9b6e25124bc28f4b2c850a5f13fd362c9aba803f89392205315fb2f35d5f2d0d
169	1	342	\\xfa1d20c0f2b7e815a468761146e344a6dcc5d3a4322c0a4ac742a7e532909f611e7b4118dfab3b911ef2199d5a90b506f294bb9a8dcdf4e5ee9c1acef51cc30d
170	1	386	\\x7d733548f8754599e80301ced6f597b831c75923e6f59c6798f3bf66d1cd4ef4782167b655bd3aab3ab9c216fa608b89ba1d062d35d736bb0d3413ffb8c7870c
171	1	100	\\xaa427d1c56d7427db72f4008fba4f8e4c001562babddd2f4785aa239eecc0ac55515685a7354525001df9ed21a2358db94dbda44f7930f4ce4beb72cb5b7ed09
172	1	22	\\x13b6ad60ebc6443973bbf2f47e4ca606fb88c9f16fb92c8a48882a648c5da3d33205eb4ba5f9bde26e97d5ea064ce2a3e3edb9dc7a48b189279fda191d167709
173	1	420	\\xff343de1a44c7947f628fb36c8af11ff5acaff0a53ce8e09fbde621b95176d0462405a4493acb4730c33da22842a6e3e693a55eb8f085300f3fa2b28d765070a
174	1	292	\\x75636c06d81bc43b7d2e0a7f3e88344f976b3b7d69f1cc13caa2e3e6ba529bf0b12dedb345fa3696b04cb59f8d9e0453c4a6741146ad107bb915a15502c7ce04
175	1	365	\\x8a4f63e55adcd5ef21c06ea364c28c4baa663a11500ed09fee1ed02b444a9386dd4d1c329268758475db0f739a1ae12c905a83ababfe63fab4e8dab5a3f4ab0e
176	1	108	\\xd467c19a2916bfd5e7d56a628773bd32b8a05d659f87c90b677784aeb2a1e7176c62ae2a2abcd3aca0694cdaaf38c43a4b80d07cb2797f0f25b4411ca5848f0b
177	1	236	\\x72a862dbb5f2b68773306c47ce1bc44af8dab22e957ed8e9ea353d6e2f2ff767442a24a4e44add68aa398391e97bc953c8442e07e2bcef0b13ebe02a73c92d09
178	1	180	\\x417e96333289ba7899a0ad80ad4c049643dccf54c87c130d3988819403ca319daebfb79d45c3b4ec743df5fcdebc10ab31f7ad4789cdd10ac73440fb71d2d60b
179	1	355	\\xd4ba7431cbb3419b3ee2652e0e7def4c61308bc8bebadef084d4604fb350a2adb0aec20e0c7ea0e58692a5566fc8e3c2178508d1d96856c054fcafd0befc400b
180	1	339	\\xbb4410cd61c9d7614ff50e8184a3e990323e6557222294fb12f93a2b94ea24570b836284f065d612f1716081fa13549c8ef33caa179a1abf9dd72990c897c307
181	1	369	\\x9512fcf77c985c170f8f3a5006ee1836975df622bf7af7d5cd938221f40a74dc58ac53175dbce9ea8db8f9a0b5bd8260f8fde5be7b2e7f0f9f7265cd41ab880a
182	1	316	\\xb88b4cccce9367538a6fd538795c9588649d9ace353550b003c8496f6c6eb47cca2f41627bdaccdc5cf2c92a9c2b71ae187618a96f6d08816272c1693ca63c0f
183	1	396	\\xae394293f8056fcdb634a14b4a235b935f7996556065a2a972c5fa6afd86fe7f8ee05d5ee243809bf1ce9cd69fecae1c29dfa7ab7f075aedb579effec4115f0f
184	1	166	\\x090462c268850f19c69000aea11a5eef05a52ff38aa04d9a51119ab61ded6d83451086c4471f71b0db56f690a815b703dfa6e1f4d8e40f7a2eea9af026470503
185	1	315	\\x95749c59f6f54256e7816305d9b214f65447973a31b1076b149f434f6a2b8435fa66ae4b793ec28b7e53c43b6bc00fee4f082ff9dca45f9c2a5682bc052aca0c
186	1	242	\\xf6ae9a584a4c1a580f12e3eb2dcaa323cc87baf0f08cf3494264c0cc1a3eb9a017c4ffdaf7270eb4a39a515f8dee3853fc50a84796dd9a9383b1522739eb8701
187	1	114	\\xd79f16573fe46858aaf52084b868118ccd51f451504f6f5901aa7091932e381ceb7df42eeb513c605275c7b1994e8923e8a43d6697e7d0557e2190ff7328820b
188	1	243	\\xa18060096f7b155c5ef85b334a40f1c078441eee66f02ac3753d95d76008feb0d7dcf41082c0c1d28184833109e0ff1516bc71ba9b56b4877494b6044ca1da0b
189	1	207	\\x83fcabb13f10128d471eb7749a6f717fc5b083e469f5729df2eaf0e83068429c2946f5d8e3e3bdf2ae0dc2e6fb8ead859d339b043b31491a9f2b9a406c235008
190	1	121	\\xa67aacca8886dc85215779990bf60928484053c28fbc14259be0fe7541ded7fd95cbd87ba7d43be3769e5eb64abf6b8006e5b139d545d17d5e09c7e2e65e7709
191	1	177	\\xf5958253f9958409497ec1964e54a73695d8fef2360da05f538544362f23ad7ebc4a1c2fa22221bebe78acc5897f6fc069270ce56cc4e602aeb52bb732b5c708
192	1	150	\\x67fac3d1bea41f15a24c00b857be4e7085dfa1dd18c37fedd79331c72bf6e802de7ed40ae9f628fa2697081d250fa76f66eb8968d0fff8819a9f89f663ca8d06
193	1	148	\\x2cab368dc3035ef4f6b35ee432917da659bd94a3374117b4249a3c70f2ca765e1bc5d06fb4bee5ec5ec07a26b7e52b544cb0d16988483df56d0e42201cdb650a
194	1	27	\\x83669010b0958bb446d6301ec7b1f080eed7275a1a69837d4924525558293b06d6856c2f744a5c8c52379b4bc28ebe375c2c0d294423d7054bd96150a35b4b0d
195	1	68	\\x29253be068336248ccdf9bd7844fade5bf90935b2f08e5fc0be74b43d50da8127e453c22ff4f7b94c2ebbcf62c9572ef8c9c52b3912d042b30dce7535a039104
196	1	216	\\xfc702e1c2f6d838b755c28b1bead30e64cb25846d0798c2b8bb0a7ca61822687ff7afbb63d17e4f4db7085f86f9dc977ec0780cff365c0bdc6224b03be30c10b
197	1	309	\\x33c79e9cf8e7cb034750213a1e3c1ca62b0d3808bdc090ae52720bc6cff870fa103cc66b0a46aec8cda294d9b119b90c41feef2e137d587529aad2bf380edd01
198	1	31	\\x6c96dd8b748a9d1f8d526f406e1b58bba0e33e22784c521e3a68cc7f2e0dd16a9b926ca4f5cbf455073d41ff9397befbf417d4f38e874843f728f1f4f692dc0c
199	1	134	\\x7335288d0800b2b40547ff82bcc29d2dee97a94b4b511f08d5c98b0fb5d43792275f274b6cd1ed5ccd4ed14023573c3c8208239f6fc002e473e026c6a6761d09
200	1	103	\\x37fd4b29cb3e64f81af1b68be23b897f0cfcda3991c1d88fe0f6f858fa3074fdfd3d11e1047301b76e8d941bb121ad0c5b5edd02a2b2c49a3e15adfa1d4b0e01
201	1	364	\\x8a57e150209ceb778fabd527a7f24e7d9bcc7fbeb336b4228be10e78477656a53acfe6da267e5be11c6a2d91d875d1a86c177b32fb5e5c93f150663d0695890f
202	1	196	\\x44ca085e7cf10276dd52f17c74de5628fc58c26cd39a238ff7d4f37661512f14122ae9529420e53a33214552254cbc3fc489b2a84f32f1522d28c61b7297d404
203	1	311	\\x706d4d8e129f9ba9a8da3c4f5beea9d967bc4785788a2faf64334151718d8c4b4af53c039f64f6b78611fbfca3950ebc595a62e0b703ce6f10d081c829dd340e
204	1	321	\\x797f2fd129d0147b0589fc054d9aaa7c47fcb8114b6d0dea513daac09188c1591626cb2cd6915a3f1dec21a9ac23ed95d3bbb0a0279e7f82569125dbaa38e90b
205	1	346	\\x6d5b002f45e21bd8f7c31f87d6d59c402815749210c807d1aa47de59e8be714864cc01e2e264e589c2baf2e96061c9bde8b5a8973553f03828a146f037957608
206	1	56	\\x9590464f553ca82b99cc368befb8944eb727f4bfe8e6f83e8cfba46abeb38c33b41002767009c33003b9bd1be61da9ca9784a1bc6535d8fa92bc4de0042dfb07
207	1	191	\\xc86312282adacf43750e8a3d144386c74e73d598bc3a7489453c58e7445fb8144677068cc7e1017480049498dbf8ae8ae4f175d1305d0c6ccd4b820c987a4608
208	1	67	\\x53e7640b0b33c76d500e75ce224149fc99d39709517ec64d8f43fef55edc4e4a16bb1a4ff19360f63354058be6a61d81cb33137062a57fadf01cedce011ca00a
209	1	157	\\x2a4911f0b99c60f51d0330ad6a79c77803c88a8c27bdccb9f8f603db8267071e7187e48775569cc50f411e5511e4ec8b9dea877ec39eb5c6a2b9ce533f546309
210	1	338	\\xe82617ae2fe25d454aea473935f87f7402bab1be8ae13ad76699cab4a5b955c5245e3a707acd109965da68a3ef82f314db8c52ade69f913d8ad7a2113707b901
211	1	18	\\x80af7cec9655028bd2165c1f92c2d3979afe2f4efa55c6ad57327f8d8f00e8b2b37c3490e91acfc985eb648728a3792e82df5bb8b983aa05f4f42be276369a07
212	1	174	\\xe83a9f388cd4917a07a835db7d72ac75276ca3bf3ea70169e089a208ee61e1541ed5809d0d42f540da0d16cd9b7886332eea691d11d3305eaccacb01055a050d
213	1	167	\\xb5c6659396f1ea2bdd742a15a6e0f4b4a0e4c5dc6802b5e3dbaa01c465e80f5d225a6b076ba6b4e0c8cff1847e85817291825cbdb79a31deb6316d934b57d60e
214	1	312	\\x061ae6dd164d7dbbc2708d73a647c243c222b500ac27beb357000f0088fc6378555c6dead1c9fa75d11a6ac983836670547884ec8290c1d9ee33f5ab3dcc3202
215	1	416	\\xf679c520a93464cfdf10f166e9051c7f9407627134cf3ce0f9c8ec72221d1d53e43f4489a14c089d22b3d7945c109a25f207b7ac7bf99f39e07907898adaaf05
216	1	245	\\x52d9cea54bf8ffe976ea7eb2cb086477c517d15884d425f78a17159878195858402b6cca5222921fd2f9fea10a476909634b0447bf4e8eb1ef2f716c6b3cfb0e
217	1	41	\\x018a817132c432b62fc0a36b5a50314aaff00cf1aa279080fa98675d330269d6c11cc77cca98e35e4ed5888aa83ed7cf2563f05db68f85b1f46debfe41438705
218	1	136	\\x7a9a2c3a7663e1ee27d4b69a1df31eabb50ca8d82a0547167eafc4db4071c683a60020fa3bc6ff24e4f3eb031cea27c44923721f5184676e154f40ae8772cc0f
219	1	86	\\x687d3a477e56b0b62aae2d870c0e8156d4f01a06b8e90610c035009f5ac75cd387e28ad279a4c11b18867b1f2c87f3a6108ba71de7fc3c0165f431dbfc0f420a
220	1	147	\\x97a16c59e8f60206fe76e998aba3f72b47b32fda658882b18a4d0f90c362c6e17c38738b9c9049371c5572b487b363e1617bbb28ef7ef75cb7d8c66c9e929700
221	1	373	\\x28d2506d7c6f0a05f6706031c5b6e7bcb76a1a05c0ff0f149dc5d1b1b531d84bc5e0c0e7cb6020f74b77192bef593dc00b73a15c8f862ab52da1772d63b9d005
222	1	304	\\x7d6fdbb62456377a3e3209fdf7255a1fe49527823951681d209f1abd00687bf5300a372f17ddf131dd0074194d6e13742f56eacae6d14dc7e0f17affe1ea4c06
223	1	6	\\xb078ca2093f5307ab5919b2e3e9bcf7317286ca5337fbe2351a96f8ad3c36c58a42075df141b0e38b8336255f63ead04ab23d6eae42001d4e3986088f1f7e303
224	1	389	\\x7e057a6f1ca3004affa6efa7116b994b8554e74f160ced85f7fd801ec82b0a5e45b272d64994cc8bbd34a6921672ccf346446ae366cc2670af876f3b6dadec0b
225	1	176	\\x4403dcd58e88c7a10918f3d08d69f9ffab5784cac1c5996a433780994b26c5ed2b0cf6c451d51af3680cf1112acdec978d9c02257b853a7469d885e0ee58320a
226	1	407	\\x8085a4e34fab7672e9b6b23156576ad9da70c282bce36c5daaafc61f7518303f37a3ef67b5b7325770d6f7f8a1f5ecc56469d9a9cac113b1d3019cf5eb7ab407
227	1	384	\\x2116da17a8e4998c4afcc17b1035b08d29d4e419968b6ead199e7bc9009cffa346cf5db30529a01a6446de5cb0575905cf5c59507dbc2322032f82a41037d30e
228	1	229	\\x95946b9da5fee615c21ef7718f66ea449b1ff1ca764a33f96921de09baddcec5ac79910079dc930f233948b1288c2ab45f027ae5ccbefd8c1264a071a7893009
229	1	81	\\x9515c879a5d3d2f03a8893d1f222f59a5984b8637c7162c6ba2ddec2b6a8f05e0b3111e24511186ced9f063922c4d57bb39709505a63dfa01133cbba34ee8007
230	1	3	\\x9ff64fa0179de78ae8ce536e3bf3646c6bfc19bf642f69825c9885cabd2e210ef1869e71d93d1aa18b02492104cc02e2644aef25139bd7198266f7d2c5795a08
231	1	269	\\x61b0ab5cbb831715ba55088286b6831612dd76457dbaad089657f4951d2dbdd72bd82c63c18cc337554a04328c338bd1159c3d34d18e5472861dc72701c6cf0a
232	1	404	\\xa7612c6e26b4a7b0f267e62385b82ede0e58bf8b424212db530e2d689a405d4acf1e96247f58cfcce202aa3b2ec09dcf7cd66c6780420e6faffcc562e1cf2701
233	1	47	\\x96d196bbf7a08c301ddd14cbb56652faef49d6d47af7f81ee23faabe4cbbd5da16e8795fddfc109d4038317a58b1adbbc1653692e36c3ff5b92434f322aa3103
234	1	155	\\xef83da479f26603ca8cf014bb0e0cbd08eeb63971a2bbeafe93a91aa2f08e03157150f54f6c03002e03d35116a2e9c33a5a4db45ece64d2d86594352a017dc0e
235	1	362	\\x14709df68e0213cce61c6920707d035f43810ac46db955fc58d9583935cfeb94225b703fb4f0d91d9fc41dc94d4bf03defffa39a932acb92c89ed85a5ce23801
236	1	200	\\xdfe6d890cfb01d1a5bdf228fbcf289ec3846fdea587600f8ebe5cebaf251c4c93a31da69daf7e5a8cf39173b93137526ae6f7e98d1b37277b10175e0b3df9f06
237	1	119	\\x06582b09175ae97af470bc2d67e462b64efca105a8d01f4ed0d6217585944b6babeaf952ef887c65d7e47804105737fb69a68e80530061ef10844d550bce6003
238	1	182	\\xbfe3884bc8a6d551af4f9856f106d0be619c22ba911fde4bf71b85bbe72340deda32b03cf86817b684f59ecab61f993dbbb73ba062a6b7c85f95e098a4190700
239	1	258	\\x8376eea5ac138ebf02095e6f06bbce2f2c00084e33b9d4562fe623af5ba7b992b9285ad131391c1c145385eee7aa809bf496e87393a4222f157452191110e90d
240	1	10	\\x216db5ea786b6abe61abeb4908d8a908caed37ac93dfb079dea87db8ecb31ec0e8dedf1c443ef7f914cfdd7de92414b8118c4783d5a4c51a299472f69931900b
241	1	92	\\xd7dbc5c315d4b61906ea10a9830d42cde3889b8dcb7cf584f127220908d4a2dd3e8074104790f90164d38eb8d7caabe5a4e405eb346cdb4e1d5eba6ce2e6a40b
242	1	409	\\x3fe3350dc22ee85afcbfd0a372664a84eff421665a401ab308b9e2ca299d8c9f55f3cdc9b93480e2b8d969c523f3eb247e89e19c00495e7c1881e677a41ad804
243	1	222	\\x14f3e5675862f63cf06c5ae1d10ae85c12a5d074b8e8d4425383b61ad9cc905c309b153b15db36f6c743b58b9cb151792a5f77e3ee304e73b1805ff32adba20e
244	1	1	\\x470a58bb845bcefbcbaa37642694ef49675b56bfc0ea6abe65b5049def8c2d35083537e453d3dfe8ef8bf49d2f77eef2a721969d254412e41f64784e421f980e
245	1	301	\\xdec7119db20e52b693fc26d8b4f6fd7ef59b9e835c99efcf0446d67604700619b5bb97abbdacb2c99d4532d37935dfd237668aa3b6eb66730a903e1ba6efbf08
246	1	232	\\xa21246040b5946fd36727aac170d1ecbb7dfff8236f90195734a6f43e0e7a16c8d463c8618c7783a7312534e6920d4f792a531af0afdbddb95993679cde7df01
247	1	387	\\x8f4b890af99d339442d7bfb25a87b5d81fb57e18897a07076cf858bf71fd00a77f69b1ecf399c27934c9857dd66b0215c38b3b153376343e7ce8d22d62dfc106
248	1	164	\\xdeab11025f690a27f56d20c27da5a70c41bbdf460ca6187dd004bf5975b6fb6a4e0a7d1182a1dcc8426d32a4bb8808ba5954512df8e5d81fde46869520a4b704
249	1	261	\\xfe99b66aa890396144ab2d63a2574e40713349672f630907a531777a4c5a0c66de12fdfe591735e5887d4607938026dbd8b69f106d94208d000a5af5299b2e07
250	1	257	\\x611a27a9385a13f9e4689d0c56810e14e9806e25b9aa7deac37eebdb1ea6312ef225a31a4b4170c6b355be41a5eb56f2a082d83203bca88fafff4b7872a5ad07
251	1	239	\\xb9948b3200624cca2b0782a3f0cc3c213e2747a66750f603752f7acb7940c0d1d724424f6456cb684efd0b56c4180291f1bbb29acd499808b7e6bb429bb5fe00
252	1	34	\\x7db5e739c0d8b5d288e89437fd5ac00aacdf67e1c735e96a2111be74aae541a2a34d2318767fd36a98c6ed9919076099145669918916cd093730881b5d02ad09
253	1	169	\\x17607773d317319e8c06f47d3c0b39ac98407069aa846e3181a394d3944a523df0f0aed018eb4c7f32aa56ab89ec50db21e889521ab0b41ae4034df6d3f76c03
254	1	145	\\xb6e7cca350ffc5496e50cfcaed55a474b4a22414a1105625ac93e8006b0502eb01378104d884280ca131089472b6a69dd4833325725f8b98710be0d75a2f3603
255	1	218	\\xcefa4c8ad782fc0092d01b342a951a830f3ad85746a13377fa25ab58517afb432185ce3a74853237c0aa14c9bd6235556e854581b65da66ff7b5a3cb078ac60b
256	1	107	\\xc5e17d942c9e27b80f7c351d7ba5db039a81b9c09f0c65a5cbb76ecbf586bb2fec2ec3981777ee9d62d1394a2e5e1357993aac6dd80a134224784c01fb1b9a03
257	1	310	\\x6a13fd700ed5f8ea6b08b16b49f98258e5659852178d14c95e05bfd4dd3f6fd6c526cf1d012dc1e67aa0773d36f5855150cffbf85952ac9e4a9317d72c387700
258	1	250	\\xf34df6ef291374c4dc49d412bc7437982e3245af3f2bfbea017ac07c63e53bfd8461ccec89c520be04d5a7457cb5360e22912b60eaff5f5425207480f190ca0a
259	1	65	\\xbc699bf2ff54f98e6d449f1f03a4d57edd7ddbac0afbc469dac7ee7e8cff578dc3b55d6cb1a9fd3a0605c6bdadbf30a689be912d950b103490c833835aeb5505
260	1	382	\\xd53081aad6b3d1148761ca9923083471d6c0486ed3993e3609036ea660b7bf016f7c304dc3c9d48c9d5c620b2d2d72d63a033dc872fa5b5467191ff1e9e3680d
261	1	76	\\x0c9c088637e66204ea16b071a8f5f37193d2ee665a7a85e9bf446d187e0ad3470fccd8a3007e1574da3441d772d5109df19234c896f79add997c9cf7f1574303
262	1	175	\\x369f2bb5a18c483ea2b7359f660eb625aaea2335d135d1bd2cdfbfcf604c8662b85b246684bac62b0a85d7143a954d6a1174cab3514ebde5580ba28a90b58f07
263	1	410	\\x0b6ce6e8df895cfe7c16d66c9c5e345894b05fa88f5f1406fccdc538b883291c68b36c40d51c893d0f8570848b97c2a5e778131b5cbab30ec4046960e8c81e07
264	1	127	\\xfc0f90461b685db864c68806fe83301b04d5fea3c5c60406e15bd195b376ee844013ebae233e74ed71b553b35ff8e94913c264605743c7ee7db461f5da763507
265	1	24	\\x554cd7b184459dab3cdf41283bf565d3f72e14ea1b4cab2ffd537d2cc15122d3b0a162d435faa79d0eb03d53e5e4426a8785fa16370a467de612b4ca53141c0f
266	1	80	\\xeabfc6d08bcf4e9959b5a5b8d6b686d4c163495ff6d235453bd9cb13b7fc5f107d2a3b9c9ab5c4a9b533e977bc985e6635800540bb31342af9adb3db55387903
267	1	388	\\xf9cbeb39bdaa6e9d55c9948d3b1d5bdcaa0d918443a6c2078ac11bfcccfb9224441429dbcfe8e36baf56fc54a1a7b92f257b30a9102238017974f1fef70fff0d
268	1	340	\\x762f91e5960e0431e9263d30cdc963bc3a0efae929231b0220c3eabe7899e42d0970172b0042b2d652fc9e0576745f125df7887af939afb78f71d8ef1a6cd606
269	1	251	\\x36b2196d048410a1c80ee61d9a7fa410106fe067ed6fc6c16f37920e98846d9d5de11a620f4e5c68f25ac46f9975f302e4d6c44486677b29cbaab01b6881d709
270	1	129	\\x5cf41465e582dfba33f4bcb0b49f66eab238fb62b3e73b730695b707fdc52213474d6b1bda6c49ae23c8f284b02aa2486593c9b8d0db8bb2a72ff1a380436509
271	1	7	\\x121fd5b79851802d9623719f8a85678d256479362307b48464c19f4d5c7bd1d98e1e4269090b56e05bd43ff533b376db38ea4505feb97a2acf3a2767a701ca00
272	1	234	\\x34f484be789dceb179eed1ee12ff947b16707e5c187008aaa505412eb76d2c417810a731b761d85c3cb2fa50c7970968debe2ac22fd044d0a12505fb6327a80e
273	1	128	\\x22437a02017860e8442b755a7278acc55152e0fd37600c70dfbbcc78d864ff92355ad312c03fd870e743eb49e6b8be457a3ed86eb3462a4f01283308ea334707
274	1	35	\\xd76258a36712459457211bd876526c8144d618661dcd2791315a7756247bc902e0545074f095eac95fe2ef8fe4d0cc765cc36780c40247b5aff1e2d17e285a03
275	1	231	\\x481a669456e347c233f54d88d1ba885d33e2e1eab06049f3ba261187d3e68f0adf3f2eb6910610d2b4321168e29021854662a8bc58375ec64ba3e97c4240a705
276	1	188	\\xda0fd2b63b650be435e868edac0126ceed0847e3d208a35c82237c059aef1e2ed76e9d192de2ddc4bf58ff735ffd9e87831f12a27013d930e42df3a27ed25700
277	1	181	\\x7844c4f5524b36ebd853f0165c5fcdbb8f1b5d2e432adf72c24d4d94550db7f31dc50289b6902651a0eec7e477d578c34b24805e56af121656dfd54344d49500
278	1	139	\\x8c105092c6a679fc9bac1d7055834b95739179def6e06e2d4cd154cb7b70b1811a04e34cc25a691854da4a1cbdeb7921f88107387a0677f3d2b7df3d8fe47e05
279	1	412	\\x4e7d0f2c91aa4adb020bcaee29913f6303f37321e196f7a451eab0d108cf4fa9a5389ad2b9f7c73deba8d1d4cb2bb0419ba0ad9a6eea249989a8a86ff19d590f
280	1	212	\\x9bd7bd4d3aa5df27ff6554acc07637ade759fa3c1ba5f18c39785216ba00d27c2809cd7089879e62ad186473778451f79c2521057b10e8f8e9fd8723e2f09604
281	1	96	\\x8224d278232f59e38d13bac6dc8e781172b0ca6b5ebb84256f92a7e374ec2084e23dc2d474ab8869772d63d84b2586a7f7a5383e27cb604da6687b2fec292b03
282	1	189	\\x1513580065d371b52580fbd4491afe6af5a6764258de5f53b630c7394bf7ab3a325b923df31a1aa554cc9c34392b6a2a955137579d6e019f54734d4e3674ea0e
283	1	51	\\xb06c5dc907ca9063ae0164c4c3d1a750df7442792abeb61412154bd9cf3793c14336189bfb96001bcc3f5680cc8a17b2f279390eff1254e8b0d22ecac0824401
284	1	89	\\x6e9da79de5ffae46d66547ea77187e085ecb6c42fa8d088727855562e45c98a4d407b00625840877a161e1fb05ed2bf936545d8781bf56446c8c1c329a617501
285	1	307	\\x9455e9a13b74cfe93a153d47fd3be0269985f2a1ec884d4d0f38ae63b2a5605ea4c33a201741e28ec266dbc99464d9bf0766e29e6bc7032ff20f5a138165e50b
286	1	223	\\x4d348609218fcb13526923f49581f7da4845278d281393ab3d6e2db07a7aa0acfba998f0e958a8c52a62d2a52a0ce21c6a602c5acdc49ffe3b3e62f96687050f
287	1	357	\\x046c47cb06dffe9686d50200a434b5e0909cfe0c8b491780ef3f2592a88ae42736623737379d668448f0d507eac91e157ede8817b58df5f7c73cbc5b9ab1150c
288	1	306	\\xab1c867048e4d7b2a089a63756307016d1d8b2c27af970300d79e4a99da7f2a0f8c6f956ed363131d68b456db193f45659e04dda69e4e2c0a95299524d2b8f01
289	1	227	\\xda2324b85c5dc7bc928b528176bf61181caf523aad53d6cae7b5174d98d9a10ef6a56f8e16558957be928d086d3ecf16c4e5e36a269c017b72b60c9e1247aa04
290	1	347	\\x318eea0ac027d4c5f754c68c05b8ddfaf81284c3ebbedc239b90f12cde9cbd6538be89350e8570e3e5e98fd46c3e4cb163607f5c836f0d9f0b62bfe3ffb4e30f
291	1	25	\\xeef1efdc54ae5f313fb895afb4a56d363c1b6f4344c32f277e608a2fa08ae3a4448ff19135c53a20a8db4c561c761d7bf5c05810d09c562a8fb59e2d05604705
292	1	105	\\x543c3b353dcfaddfccd4a28138b102a8032c417e0b32a5828fb2680791b807b51e709466298b8f217264bbc332f3c47aebc4a1f602cd166fd329e2b115ae5b07
293	1	259	\\xffe52dde22c802290939c69f3f08189f1c01bc433f7cb912cf0e7fc0f7c1644859543bf0869d790c547a3311d61fd54af15e77cdfbb5e120cca5ca6b3a347807
294	1	281	\\xc9c2411ac602e4ff984c3264b93c410e8ae8626c5d2b2506ef6d02920c83f7709a497ea1104ddfa1d412c87b27b2969d22b17c56afbb2d7f51177bcce3a01409
295	1	329	\\x5c63c56bde4b54dd703372942b5ec9bb7095cd2516fcd8c220e688fbf09cbf45c6d4bf28553de61dca9acd15a00899917610e2d371b8c64b7c3641d52310aa0f
296	1	215	\\x021760ac095d328e9f57e10e6bf2c7ee7252879d43d495d00f6c9035bbb5603852723a6439752de0daa3571839200ebb1762710875d3b87f2ca93ded91a3bd03
297	1	414	\\x5892da75c72f68f344fc5af583b9f8c94f977b5aca73ced52d629cc41b69381b52a0f6778bd431d8db60f33fe37f40550639c153a44d069817422b43cc63920b
298	1	151	\\x113d0c0e0e76b4ae86ee43d9d11dadcd36a4150dd3d1ab8d75da5748d5978a7ea04ee5b4a11debd0b1a840a7c68ece854291fb1b0aa1800f31577ad147493f00
299	1	133	\\xf0339d08631dd42046ecc792449132247d1855c2f7e562e2971d71ba9aaa8df2cda8e3922cdad61c33c138f3bcff47be2acaf327d452301844c071b000cc9502
300	1	11	\\x471b881aba354f4cf08ba18a4646a0cdc026f528c65f55036ce7c5e26c2eed1abfd0b04faab6356442147bc008c1442d6e96161d742682feca1dc44ca6ffe50f
301	1	171	\\xdec4d9f485bdf5254d7910c28c5d0f2f71fce63bb9a52028bd5b88d136e23095740c8b2f585b4c983e19343a95c7c5463e339d4746e24f52082b7445fa485c0b
302	1	37	\\x16bae5919ab92bad245f4014cf099e700453c0e14add378b3f03d14f985dc11ed327b652a58d5157cd64eddbaaaf501f86a3dfc1cca7dbbc9dc6d99d46377309
303	1	101	\\xad0f04c1d832d765c18cb4e9624c41908698e1db4e36c1f8e3a9cf719debe2134bf785a85e03ddbd60156492396c16088b95efdf3b6f12a8f03490a784f60a06
304	1	211	\\x7aa5dbaa06fe2725f3ec55060e6414d4ceee2b8a4bfc27811147d628ae8e8d895aa21ba7eebd6bae059b2fd2c0b26b4cde46069354cd9ef1f5d6aa8d7fe25706
305	1	272	\\xb1926042031d39cee008ccd533567b497353b4095bb5b28768329206d4e1ca247dd61ee8b79695dfc8ab288fb07f1bfc1f1120347348debdc3c768caa2a6d507
306	1	94	\\xe6adc846190b12cee42e03665a35ced027de7f4ee1118afae3d42cae5c3ba4aa94c1df5a4e69c9bb1d352deb565f6d6d9b1a45eb0e038e036d19046e2beb020b
307	1	246	\\x81eec05b86b59784729209f73db29d04a7062fdcefb05cd80e84ae2f36d8219d3d0134d46e97b7b862f7dc2b7d2964af8352597543a48a354a6206594fd63d03
308	1	224	\\x5ff1e9aa8a4a2dbb14fdb26a92c82e2ac03d0d640db06e736c0eaaf26941adcf8da91f688f5f3d28017cb6ffab178ec072755a8bdbe05f00604b303ba02fbd02
309	1	123	\\x70d5649f0fc1d2349fb47e40318d41c54596dbbea898429bd2ed54ba180567f55e61268ca3eb392df85597a5a4d4b2ff9da8dad1d05b3cc27029c3de98c47c09
310	1	353	\\x1ceb72fec524651e33c52e45d4abaf96090b4a6484800c2e36b0f529406035a3575948d65aa504d38fa83f60da2940b10cc058b48f4de99437542ee3e637730e
311	1	12	\\x28e560d2225fae499b5621dae0f85add2b6eb87356a483de018ae4bb9b03c3515cb0c6d8d6baf5ae4574fcef18c9322ed7d97fa888e7f5a9df08d9df753ab601
312	1	400	\\x5280798c22a4876eacb078e84df61171d8f0a2c0d2a1c6af7de6f565a8d71731104e051f99568036f70c29ba0287b0f732feb46bf8f18915760156e0298fb705
313	1	126	\\xd5e61d2968e208538a28ef514b6eb98fd1e0651dd0fe6b0d15727d7b100319607a131825863d153e35228a511766289b7238b59cb2d51734ee2fe6b59876e108
314	1	398	\\x89a75a3bbd67420f079b857a667be5ed61e6559e0e1f2bae1b52b0037068d8b6126980776cafbeab19669eb13e53fe1197bf70d83a98dbe832945e92e7d6a90a
315	1	378	\\xdced4632d087aaefb84cb3d14954ec29b1894223a07c03ebd8958bfa1ca09743f96edd18e493e60109587938cffbafe4d0f572051215e5b0730afbee5d1ef909
316	1	285	\\xf06ea98cb1df3c0b79daa833745e4609188bb40a954843f09a38a42b1ac39190f1900d629fbf5f9a69012b5d27b45318c4b02e569aadcfd80506887c67006c04
317	1	84	\\x664ea2a0f04918e2367a53714008418cc20a57bbfdaf03c53fe4bcea20d2b0bffe812bd9de4ee22e093c18a5eb2eccb818d89a76dc1b50d9415d944e54113206
318	1	375	\\xaee98e9668cc05cccd9edc6391f4ad80228b68ff2ce75db38cd523877efbcc137eedd9dfef4622dfa8d44db98382b9afd9c4e9ddc8e87c6ce20c983217db8409
319	1	75	\\x9d3f39e9dd2cb174ffdc532e382def2d23db85338c0f868ee9955dbe65a72a8cf4d50afb19afcf957f868a2c71be41d1a298f733aa7cc485d0735c649a34b80f
320	1	160	\\xfb627251f85e63650582a77e7d43fde72b102a39b04a7b43991b5c87d2cdcc0d359c82125878518dc1b152eb86622244c6edc2eec91feae8c4266e04b2041809
321	1	165	\\x1b30e3f14b737c0e1738004315a455b82f5a6bcf0f74f67364b80a7a8c204aac719fe44ac43eb0272399c70566aa77d64a15fcb598e8a27a44f0f607cff09902
322	1	379	\\x93c62301d19d770d2bc0854800c877dfc8835e834b07f8643025602bc06ec19db767ac536a680e4036f9b618f57b82f4b6200d183000e395a5acdc2461b69708
323	1	366	\\x310b386d31bb0d175c48c686b8d7c654d7934ca59f54173c47fc2de5a9447c163c257ce05e00ca431d67879b043babc387034811da2cf90dcf2667740fd84f09
324	1	9	\\xae6de753bc6305115689b486bf5e4753e3ba698059ed9addc85dd6d6643c53edf0056e812ff6ccff259003215a93fb8ca06c064ce1cfc1f27d82eac989d7c505
325	1	235	\\x9678b47dc25dc2e927441101a78b3d746d7887fa9bc416801b4b2abc8de64e6c699a81248209b957df693eb56d153be8b6304a37bd532bb024b98a0fa477fb00
326	1	271	\\x23938d308a48c0088d42cf1274ce80c6c425650a2c1ee8af5124d51546d65252d7167e64b8196f3e9d3b3a4df65d4b757075521dd781e84a09d7d0fc47661004
327	1	152	\\x22cde5ec4ee456a859e0fce00423e12f308cabefb2309f3d14972bb537b5ad3e595a7b14971fb9ceb13ad300ae260838a4f77f39f6cb74be934a7f5efce59f04
328	1	159	\\xd1f4fa97719658c0ae324b8a30d86566ebd1b69e0d4190756d5524770a622aca9a19b5aefaef1e145fc342489d90176b5ae820b3925ec4ecffb5764dfd534e01
329	1	270	\\x1e2216c40c2ae61713ab8f5b8fb1ea525dc84d28d56898c4e74d0d331d2bf94cd3ff91ecb50e5773eacc08b5454eba8b8f294bd0f2ecbe5ac866038bbb2e050c
330	1	83	\\xa15911a129f0b46225fcb85f82f4c3f721e6fbc1faf119d9ce4822bceaae13a8185ce24a98e3e402e17559b1765a60310e6ef119df327ab58742efcccc4a5e07
331	1	424	\\x67777748365e632611e68e47d06922a66ab53e3ff8b01ab990bb540e76c1dae07f01b62de8cae43ecddc350d2906532fff5d569be3a63a7f2f94aa4bb1006201
332	1	99	\\xd77b65f3bc57f56f21c6e89cdd360ac9c51593347af91db8e88c83006f0bd7a732ed364ec6ce91c79a710e594bb7fcad638b13487993c77c306c834550c32b03
333	1	277	\\x4ba086f6c1fa9727a2adc6546427f058966222110e1f9c1568572368554a8c931fc57b5851dd4ae1eadeef0393cb406a63e0b4f671a52f893e89ea2d85c8fa0a
334	1	284	\\xe53c8eb2dec7dae8bc9d9edfa3867ce4c41d247ad6413925b3b2b3f8520c364e235d79971e000e02af7fe9958920db84372219625a371bc3f5e1365ab2638b0d
335	1	2	\\x2025887d0584d50b9359931d2ddbef5bbc02f250771d52b246a6a265efe3438db7fe47bc1a7844dbfed855820990c61aa5b9c3b0390631f4ecf5ea3cd6510f04
336	1	324	\\x501dfaa903d0b2bf40287bf838a27914b37b08642382463d6f6984d94f58d6ee4f2ef4adbc9a6a1d24b81278d017dc0a0839d56792e5896bcb72aa4e4ae1f701
337	1	178	\\x448614854a4c3688c1b5c50e4cc341c8103711d4c988e4ef6447aa24b50c7a81deca6d3927da791e24610db63be205fa90bedae863cea2c79372824e7a7b860c
338	1	303	\\xb7c5fd1407088a48e3c96160168c0998a3c40a3c74ad41760b0cb10b7feeee4d34bb3e2504d5da1ff009b59672accfb4aee77973243cfd236abeebf1dc32fd0a
339	1	341	\\x520084769eca8237d035f234f7c76c2e1349f0a2aede1af547ab1e5153c51d07911efd553b7347ba7e2b54980906c8159998efefc7f26280a575a43e65d66d0d
340	1	394	\\x0df045f5af54fab612aea7e8c1eb33f5e9013f9c57419fb7f962ab56fe55e0eee1a2d2309e040b2dc0922e55ead3846c6bacd85e7820100785790c3b932a9805
341	1	198	\\x74054d0123d5834d9d4b5055608ac2fc53184bf86ea348b00ebab52b438e86552963ccc8d4363aac0128a0bb8f60287e9961ae21ce5159ece30cf2b6e3213605
342	1	359	\\x27b49b6d4b65683d88e0c165bf6bc26b9381b3af718dd34c6a59db537c43d4426ba2ba74c96a8a3f96992a3389763c19d6bb95dedcf29a64ffa81d15d6c93709
343	1	95	\\x973ba1409947cbe0a169dd8b6a611c6a1763a37050d8ee88def26ad8e18e155597d22b94fb2b29cd4be95ea732d8455080d4891b2ddf86c4c241f14c31e0a900
344	1	62	\\xd653fcf6293b728bf5c71acd98e5d84f16f40927e1c00566eb3deddf2f9edec36cdf2cd7f01ab0e2220ad2516f2173bb84731278f65b03974fcf720bad56cf0f
345	1	16	\\xde10f04536f0beac3205fff395725f9023959cbc4f365d659c61eb34c71c55b19e25fce524520c22f5fc4dc9f253dc2debfbec5c13e3b254f771b87c13567407
346	1	356	\\xde2ff0fd6bd4027c3a7a305d60c46251c2566f7d20338a1e41e5c42aca5024778b6eb5d92c54f41ffccb0e77e96fc141951576e0fb02771d5435d7d79924ca02
347	1	385	\\xbe318c8af7cbad566ae9e588525701ca89441a0664a7cb6ee781dbc790f6e2c175392150581f27a0c7d7ee7031153b3a0c815a54ed4562fbbe1c7c78cb13ae0b
348	1	77	\\x07bc59bc5dfc05caa111a8c18385e9a0a291b64102f1a7e5bf703876ae94fa3e9e50b51a843f358209a68838be3933fa06f05d4e453aa3f8e45cb352757f4b0f
349	1	93	\\xadde27499aef67014fcae0a0514f54b05ea6c3e5ff9498aff13d4d347ee7d2566bdf578160b4250598b2867859ed800933e1221837395c974b46437a268f5b05
350	1	287	\\x2ceaa8116c8f4a73c52ac9a8081d3355b4742be6d1bd21bf1d6e64e4239c133280cf5d62696705186b9005473496e47f993e338372f7478d55d0c93c52b7310f
351	1	53	\\x682fd1e3ddb7b6717bb952c00665fd59fa873a2d6963f02c6fe36c9f9a6cd8c17186750f4c752292dd03aff43b94c186d21725111bdb36dfee622b76989dab0f
352	1	328	\\x46d390268d67010d5ded1e52d85f6af2e15620edad65f738d1462ea7feb66d8fe7f244feb01a24f6f519092eccd635676db984ce0e6b39d318a8cb6afb5de106
353	1	350	\\x72c803060fc84274d9d27acad05340b8b0e062e1f0a749e5b105621b6ae4d900eb9e9ef916e3bbb8a4ef45d0f974bc6a288d89fb55556d168aad9b416a348304
354	1	183	\\x302fe771fd5bf52d76629ce5e30068990bca9e97880892bfb3f4404ea5b062e8a78f0bf6319e62ec848dbdfe848afb9f35df760d72bb34ab75cc3e3036cf6301
355	1	130	\\x39b6bf219e7e3214a7930f424a888c4cbd2f251c4e53fd698061ad0fa23ddc1b52d5c8eddb6a59af1171efc21586064b9aada9bfc73794724c074e6c18aa4000
356	1	138	\\x0e43dbb2646dd2e7a9b36c711d190536327c2305f0eb0075ffc1e27d649a8ce91f47350671a48645dccaf25c1bed264f0922356bac0c1a87203594ad3426ab03
357	1	163	\\x595ac14fa17843bcdf080bcc3312e7205e3359cf67fad987a2b3abf8d9087504d563e3f67327ae781b58bd67ec5d4978c853c2fc40190be1d292c7839baf4d02
358	1	184	\\xe641efcf0a08bd6641fd6c5673a11cb55408d13c321374c5d729dd2473e16c7c56fb01069c5d2ea1a34fcace265a98c963bc8a45e5c87aec8fdd2fcb14bd9c00
359	1	255	\\x9a284d6cd47a6932ef8bcf9e8083d76da5529c85170fa3037106a303752e444f53b59ac5dcae659a7242c9a57837be05d3a3cee5852f38c368df1bad11bb8a01
360	1	82	\\x261e265e8c0f47175a9416d46802f7fb3aff4648168bab86adfbd4c659fb70322fc69616916df99fb4d9d935fa286ac80577df078a4efc490a3581cc4007a30d
361	1	351	\\xfab3169ec2ff1572ed7ac74984d90c362783721ff7ae33a9cdd5fadb62c56eee7d9de565824f5422dbfb44f5921046577deeb03751140996d64c340ed1b4fa00
362	1	302	\\xd0d49e6cd629cf6e7569e3908957c420a1df41ac3dbbbb1e58771a28cd35b924eb726cf4e837973988106457f2f471d62471e5b67cd5567926e0eb84fd66180a
363	1	69	\\xd2f25066b0445fff824b798496f456b5b149f328ea1aff14786d37b11ed66006194be401f44543673b1df09cb8cfd52a094b90b54f6213514b61cda6a53ddd06
364	1	308	\\xb2460dff04d0c595195eae5ba8597365177551ed37b3d6afa6083869dba53e90c1e145193da65d98343c26f78dd9c4922c3212e423244a67d00c15f4b07f4b01
365	1	256	\\xfbfa12af1dc14a0787157f0a053d132a1ee059db21f4fabc7da56df251934ae53ccd40dac54c877a32940dd5399b3f2b66b5869fee20a88da574b3fdc4968d07
366	1	202	\\x91eeb8d7ad9e8ec4c5e2bed2ba0ad3c7735c888c6f2658b0281920825fc45e70c7b1fe43d6a1cf15e520612b0b07bc68269261c4864ea6175a69c9f51e85b207
367	1	247	\\x940c6ec85abfce1c3635a847ba9c26a814db88b50b18f701b73b01f51d88f6a6507f15345a7d924eaa9a47debbed2ce31c1a136b828e8ee4c2edcd66c25f8705
368	1	268	\\x07a9f5c8f60bfcc9911d87f4daa5fa793858a6464f1195d94640da4b02f6153a3595fecc295b87c168cbd82bfa06d181abf682fb2f90cc8dddcdf089ef6a9a06
369	1	203	\\x0ee8d32d2048fbd8c7f7cf7e175ce1e95e74953d756e2c5b10bec2db12edad27e8072cc1a81f7e286ec4b35fcec2a4961a14528d2beca59ccc9c63ac506bd408
370	1	241	\\x6232469c00de5b1ec37dd9822dc4d8d07e593b4bc1061f5156fdc2c298b54e7dd29cd70e7c0678c72a80d086e519a4ca7f00d95fd79a0d5e7aab2f04b5cbc006
371	1	279	\\x5b55b878e7b0c2005ee0b3c811a032b79db217569012d0589f22d58f4eb3ddf92ac1b59e9d3eec85f17769c13ae1f35c259da54544f151d774b3a6e012fbfe05
372	1	305	\\x5339356381f45167f43811e9aaf1e928345954fdc9ecd9a74dc30068a15500e10cbf12f1ae30d6c2c243d93124629de0912f59102fe1660c2ff6b2efaa834e00
373	1	185	\\xe86c95ae737d6cc5e17640baa3c2ace700b98f4f14961b99b4f4040a4fdc6a494af4e99bcc61b9dbd2e7defc522cc977cfad6d8c6e0bec1c3ede8483a9877f0e
374	1	61	\\x282dfe93220af0758961a008304df35b8ebab65796b9f19362cb3c2df8aa03843e1d78088304faabfe266228e04bec36b2b9ae078666bb22e4c5a1ebb9f2ba02
375	1	383	\\xaee9874f2f7f4ab3ab1d2597dae42996fc8f9f4f4b0d9a2cb4d3d0a2f4f62bd7fff7ac98d143f5ad99cc88150739548e801469443dac88fc02a3e1c4b0d81b06
376	1	21	\\x7355b57c18a7d81d0f6b6437ad54933ff482114d7d7e29e3def9cf16f5c55321bc304bcb4902318ed9a886e09a7b3a17c8c2d3b9510a15d26239787b46ee820d
377	1	55	\\x407aef3f1dc0b89d19cff7b9b120486224e8acf5acb9053e499b9204dec23b1044eaf934d70c668ae2a25b363b52d8ef314e842967a430b608660ff22b4a5106
378	1	44	\\x5d6d800f696aa861b049c62e4b585ec42b241c549bfd1ed2dccec212db551332e470b35e5d9726bde7d35d1e7fa66766d6c344d318d49a5d0fae8946ee49f807
379	1	349	\\x6b5a64587b0346cee5d2eee84e75104f785846c3325696867d92ead97a2ea9867fa1d289b6835e39f46fadf98353dd4fc3764294fe64dce87deb4aaa00c5ac09
380	1	14	\\x2eeca4972b3aff2972ef11e0c37a7fad15388f70c73e2c36f6a0ea0ef7774006d6ec2db940407cf00b10f8caf4f6a2ff71c8bcd086436542e99c81f59e528502
381	1	97	\\x6fb85237a686e508c1d62ba3df102bc1a2e654c960b3e2ca193582c9c82ba6a1f9964da425aa6bec383c20c92cfb6119bdf715d194219075941d7f63bbfe4c07
382	1	98	\\xe4200e8d747fd0a81cde4e29108a7e57563c09a6660dab802b085535840b44ad3e2ce0839ea8fbb389d09cba34e14151ab2e48ec93d195da012a13561a256f08
383	1	422	\\xc3f9a005c59a4d9478e775bce1625f241b55b53ef71668b6cc3d0924c95845478c1391f8baadf612b93fe5761890a6139c3c6d7fc7746bdd0bef57d9eb8df30b
384	1	374	\\x14cd8630f9b55c24865bb63f59af616abf82292492c84304d52dab7f4eaba271ccb1dc7c9c250e1c48a038d021ecc05085806cb81b89b05564e5616c5b2e9a07
385	1	286	\\x6e575d28b706c23d7ab60c5a9df7971e16cc1061dd92dfa6de3ba540af85979b1ed04dc679604983da5da4da1e984ab14a8e561003f454c298873b8420c51b03
386	1	153	\\xd7482e991bf3941cfc40fb8e81a4b091583e3b4ab82c74827a09d4b80fb435ff21c1802fe2d910794d3dd4cda4eb8a30ed6677540122054f25fb725b589c6b09
387	1	158	\\x8c6fe5e3b307520b0a0aa7bcb2bd397512f243ea19b826a69e50505cf80cfb5a9eba56d8dc67c19bd5ecd7d73628ee2dfb63e0b51ee8d3e4ec811e79e0cfda07
388	1	113	\\xa14421de76e99f0ac91141490cd2ccc511708ba8e2d037922222ded640f9bce9d37e5b70efce2bd6d4cf2d0466772d273d7dda23bccb84b4dc9755e082d4f10c
389	1	70	\\x0036e8d74b5a0ededfb9d68840d96ab3d8fd424201c69d8fe4d9f90a34f52c9068cf7f185807d2f62fafa829783162d4825de7600f1c154f77a8ae348fa15700
390	1	186	\\xdf7d9ac6f9d2bb35798fa7b99c2940c7a8f436847fb99ac64f1d9048c34c8ddd65027fae2cae39861698e5a0260c83f68b6f64a542fc97e0cf962ac1f5e6b208
391	1	190	\\xc4e4dd74439df2bf16f121cef8ee91f2a7e9f1328ed36357917678848b4a755c736372de7d64b268c8da2ea7d5a92fedf13182e322ceb0517e726fee790faa0e
392	1	66	\\x5c161aa24e102e900fe907fe6926ed1d3674f7156819e97684554e4e1132372ce745a7eb411b44a6da63e95dfce479d965a95ae50514bdc068939d6a690d2e05
393	1	46	\\x377362eb7da20f1d57acf7e1d493d5cb1930e7d1dc40aa7ca8bb2117e0310a99dcbabf5e9a37e169d3ed2064f3ede1d5d03a0c486bad617911cd25bdaf8dec03
394	1	132	\\x549b5a330c5f8b8a61a8af0fcb8bdb42b1c022b92490d68b43fb51dd690f02ef3c478b2c9ab79fdb3e4dd78b4e580b726dd9de11034da4e4051587d894d3db00
395	1	102	\\x19a11e4ce2813daa2f02f3a628e077056103514f933cdc6182f103c965501848b51602ade4d67c69a17b315de1b280e961498e753ebc60bd1e6512b146b17e09
396	1	57	\\x042067413a92e334b484ba1e4c8a12403a8370dd7423272283f2f0707c2fb5cc52a99428a25a19cee54edd476125deea90e6719ddd1d4a51f43c92825bf24a09
397	1	74	\\x62cebefd582a5a1f1ebd557009edec392fb8428337911631e8c3937300a8dad953a880999a8d0d631a38659065f634d0fbfca5d713fda0a8a6b77f1a087d1d08
398	1	336	\\x298b8ed2df53e898e84e5dfafb7174fa63a61150dfe77d418fec16e0a5ead7a0a307cb6036f41fd0ec7eda2e968ab58297e100f62532d2f119bcb04472696107
399	1	104	\\xc89bc7a1aa7b3938e05caeb42282e5aee39583922d21685c827d20b0dd56a4edfd6f84992ece80557c1a1461955121aeab9c9d315f45d7d947a5b1f862d5020b
400	1	244	\\xf65e2ae698e275ddcec1ff11f7e1349e88d8c5c46d513bc078ca060c856ba156479cf489cd60b48c688fa8db9688594ea433172919247f5e29b852409edfeb0d
401	1	238	\\x8502146a68d2c6aa4a49e08b3cc78eee98f2ca093604f5088061219800b32fef99d891d37f5db5f3d27f7b755eb5ffcab991835d66e83fb9e30bf1b510ada601
402	1	38	\\x1eabdc53fdec37a60440fd5f30672c4db68201bdf2fa4242253b973596139eae32e273d1ccf2c98241d369003828b60e5cb6c0c2be1433be2718ce197cee420f
403	1	214	\\x57a64c61e1693840728c0a8aa364f21645bcacedd8a3b80d803f5c4f4dd52b27649024c8cfd62945ee2ef9f8cd7366477ab6e935e1eb77c6a6dbda8a9f0d9601
404	1	344	\\x7a7aee16798f9bd10feb93a0c73ac86bb7142f5db5e1fc10bb7cc4e87be7efc9b212cf0cd95a2af438d60d1cc1c125874bbad282c3d7f568b8bb78b148f3fd02
405	1	173	\\x93a434be76cb3824ba3421a2f060f4ee08d0c7b7f240bc5600660a272482e12cfe4b8daa8bcd9a5a3238a2305877607b457358bcb674033c55ee83ddabfa3904
406	1	221	\\x07130bc3dd0b643afa21f92fdf7cea6ce389c2fb5d93caed457718fda5272894acae3e645dd5b916b778539385cce8f43db71fa4605325ef4f27eb8a184a3403
407	1	381	\\xe699e4d229e001e2f3bc1604751b859f945909f40c87d7ad6c9777297c34b6eef2543e8f18c979754299755b804d13d6e1be5e01c7bcc6765977fa01d0b09f0c
408	1	337	\\x0bf68e360d2cbdb43beda7d3375c6ca2f5c0342255b32be1f9d6b604491bb0c2b4a905feedbf42c4b618319fd8fecfb7efe455445b1ec50e9689e788b9e62707
409	1	170	\\x47ce4a636bd8ee312d0ef2cd69b9fa73dc8dce61633ae96c9b4fc573a0e3be0149f3a84bb1ab2ee7c5fbf64c89d684ae9e8f998b0473186b1201bc7363ffd70f
410	1	5	\\x7f1d6eb37243c18d1a74c44d2286ef72ab21d37d435f331304856aa4ac31b1a253853e589c483f994abc938b9add4eb674e1108afd04d13cf7d18e3662922901
411	1	372	\\x3c89138423a245212ebd00a46e710693217a6bf33d200cf7d6e1f3a5ecc6d6ce66cc28666ed1cc1b5941aaeed1ab8bb927ca9528a76c683c41f5393b84b1c501
412	1	405	\\xe6fc1826d095dbdec104fa63f4b506a77eec135694b3c37b47861c00137f8935ad65dd10687bfb41e25b3ac6c4159d2d33e74da531eb70c3ccdf57acaa17df0b
413	1	109	\\xf78fa8065d498ab1c2c38f465292ff789cc625aeafba28550f0408d344c1cf27d08041254fe95baebd7c6daa1002658d44d8bb5ab796518c67d3d11a02ca9904
414	1	391	\\xab93e361a7626e7954605a585f645dc96b99338a9ec526b90bf2020974a4a9d85a905bb99c51069e69d6d1950325a53cbaef3b9c48ea05fd41083949329d6a00
415	1	118	\\x58c82ec22707b2a19a08012b958afb0a709fa4b57f5cb35516aa1f651dbe150c419886a84deb3dfd1d4519ceb5ff8bd79cbc41e9f881b9fab40a0e0c050f330d
416	1	376	\\xa6c03c2f54373fbb49a3936babe8d63b8a6a7181c73f853a0ba1eb14b6b7e465556b5ef9cdf1337bc1a2f800150a4bb1e83b32808a47f240acb7ec3681aa0701
417	1	352	\\x253309035a3c3878fa685d4d9840dd487bb7fb2c5a7b8b4c2c205e2f135802f2ce2267ae0438cc055fb8ab3ea68cc32202b637a4633f1d4334c04af3fa190809
418	1	64	\\x80498205c2a8dce0d00dc67b0b8c68a58471a64313fe1cf2d9de1c4420bf768afe97ce632015e953cce4e0344488c3d7dbda74ee063588281e059662f51a5a06
419	1	334	\\xfb1e19381cc581bfa46dc85b2b665613a5fb3e83e7a4ea18f9d2901a2e51bf8f9b3586ff6bde67fbf8efe6ec2424f7f4d509ebcbdf1875e6e833e178e76a020b
420	1	192	\\x8fdf86c3469d3ac9f86e916d1b170a11313487d2f12fcd69220a03a73bd45ce9c9edb93070aa55fa84a655f72e1d8d4686270e750bad7dec0ebbfd37fe6f5c07
421	1	267	\\xa48e6a85fde483bf47ef5aca571a4be2a245268ced2663e9a7bb0378931f243ce95e20e7ee63ba23f8561dbae2408502ec79eda1e682f8ee9ef58dd60378ce0a
422	1	206	\\x5c8d9bc7bba7c99b89ae2ec51803eb33101bf3313d23b6444ade80abdf12d79d1db851f4f5d6a19deb30eeced51040333d2bce2fccb51b695fb21a73ab3fc200
423	1	13	\\xb597846fce0470d3180f7b3b4d0c01be7f241ff595b82dd5e6caf6d366aae5b2b0e96a65aa0f0f81a6718d7ee1a438a266ae90900aed214cf7d740570b615d09
424	1	237	\\x7449666deae53fbedbc5fa43da62e2ec5fb39cc40b2409f0781b6c1bed49ed31db118aeef872ef54e0fd9467f965bc3b7effb5b6b4f60f2e115f749cad589204
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
\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	1630849807000000	1638107407000000	1640526607000000	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	\\x3833a475ae4efa15b172f03f514b50bdee2c5bb55a180606ce698c4725e01f10b5f0d194ee0a56dfbf3283b8640b3741988f6c0133bb13f27be36f5fdc3a810c
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	http://localhost:8081/
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
1	\\xb2e8fa53f97ab2b7c3d8529e3131801349424d0dbd38a9eb280ba998ea054332	TESTKUDOS Auditor	http://localhost:8083/	t	1630849813000000
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
1	pbkdf2_sha256$260000$U5C5Arnif4LKtBuNgCI4OG$3/fVMu1R4Y+7/czKqwBkX/HO6onaStOKW6AlCs1d/Tg=	\N	f	Bank				f	t	2021-09-05 15:50:07.878083+02
3	pbkdf2_sha256$260000$JNaW9f84CiFLnxlnZv6muk$q2thnwX5vT4Mua5nrvLWoTg70tjBNILarqldPO+U8/Q=	\N	f	blog				f	t	2021-09-05 15:50:08.071263+02
4	pbkdf2_sha256$260000$qbKuUCuXH2QgQWIhX1EUZd$ZFXWyLPB4HE3WZCH055TElrAI4yxgsMnuO9N5wjithQ=	\N	f	Tor				f	t	2021-09-05 15:50:08.16844+02
5	pbkdf2_sha256$260000$8EZmoZQshyrGDCbgqEEoti$vnVRMnimapdlIhrofxvHEtbYEPE6aa/vqJZwTBYaCQY=	\N	f	GNUnet				f	t	2021-09-05 15:50:08.264776+02
6	pbkdf2_sha256$260000$S3jvGkxtuXVFxrlc8fphJf$I84riOu+M5oU9nCWXnmN4XbWQ0DXOkRD2qTXuNAT9jI=	\N	f	Taler				f	t	2021-09-05 15:50:08.361993+02
7	pbkdf2_sha256$260000$WgNLuYq3iRjpfbgIpgRPKk$7nucd1uhSMA5TAT+Ipyc7y8CMx4Jog7qY//5TOepPwE=	\N	f	FSF				f	t	2021-09-05 15:50:08.457153+02
8	pbkdf2_sha256$260000$x4SZJgKqfpLLQwoyQohezE$knfhgdJqgNbXMi4L4B5PqvVq25MsQ407MGlEOuc62Og=	\N	f	Tutorial				f	t	2021-09-05 15:50:08.553534+02
9	pbkdf2_sha256$260000$eoJq2PyMNNEmhSGpXzjcH3$xH1IqSZK8ORwdOpondgKwww0jpRxadRhKKIlYvQFZVk=	\N	f	Survey				f	t	2021-09-05 15:50:08.648824+02
10	pbkdf2_sha256$260000$uswCLCdo1AxJXst5zDMuuH$oUxNU6NVi9XiiYrnmzMRY3oOvcrT2I+yyn9yNcTC4mc=	\N	f	42				f	t	2021-09-05 15:50:09.132035+02
11	pbkdf2_sha256$260000$JyR4Ip9iug0MWkufi4E2vw$A06cRLfr2Hvk5TJrdiJmc8ovRniTtXriUDL2RUiMp4U=	\N	f	43				f	t	2021-09-05 15:50:09.604178+02
2	pbkdf2_sha256$260000$q3zhF35J0Esb5Ueb2hjP8l$lRGvIpNgTHxTZkc9FzXVfB7b7y08jk6F3Ext44N9wpk=	\N	f	Exchange				f	t	2021-09-05 15:50:07.975646+02
12	pbkdf2_sha256$260000$LzdNVV2tZRcj4Up1nRJmX1$LXkT/I5KykR6p4onEqVBF7vJ5MOAmk5xBBdPMJ5LWig=	\N	f	testuser-SeeIXZft				f	t	2021-09-05 15:50:15.302391+02
13	pbkdf2_sha256$260000$eHLGJ1WCVmbZgmjwvYBkyl$mNv3+sRbWS1fjz23zNaAAKckVstSTDMgLyntzoRR4w4=	\N	f	testuser-0w9C8Kjf				f	t	2021-09-05 15:50:26.666257+02
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

COPY public.denominations (denom_pub_hash, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x0c58a20490aa85199ba4a7f052bf9f79c8173893c0721fe9d3d053f48828557727d675194dba38122a18a6e6605d2762bd83148d074adfbb0f337185a05f25c5	\\x0080000399ab35f0d3cda8b5d021691e3b62a464e293d545c21ed2073b90e35d4732a7da8b74845ec160916d66807f16d7df7f602cc4fb67025de7a9308f59719358344e547e7196266f995296ae7c3071da24e42d34abdcb54b19ee6a9dc88d97ce4ada8a1793b14b48359d85837fe2957533b1abefb1d1e34d488ee34d13b9f569bff9010001	\\x7a5d13fe0b10f54c19248faa423f6b032da9dfb9dd862166dab2957ca7abdb901ccf424df285ca683cb95e589993a1502ee9519a8677224aff76a0e6bc7c5309	1644148807000000	1644753607000000	1707825607000000	1802433607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	1
\\x0efc001c92629cf8aea007c45e3da5bbbcb446df025b41dafdbb29314f9b8d7a3155b755e7595fc06b3665f389ad11fadaeb7775705c57ba1faac51009dd75f0	\\x00800003b98400ecf224d14dcc2def3aca3f926046f95f44f0ea7e5358e02e82691cc530c5c30b1a6ad8fdabb1a3373fe9ae253a6b039cf25a72ba1fe14b76b440f0b41a7265535bc5e7b81df152f42f0ff90e48350a5f394514c6947f3d0d85f74bc537e5578be724f8188aeffe53262aa24cbe1e815f266ea7fb48707505dddee601e1010001	\\x89f54ddc2ea19a5cc170303e267a7a2057eb89597936b530acb629b88881e0cf131c8435e4e7b03c3dd7949661659bdae8f0e289593cc1f6104dc6512457a80c	1637499307000000	1638104107000000	1701176107000000	1795784107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	2
\\x0f9c6a864286ab183d3ad166ec51d0a3f8efbc0cbce9ce85fc1eac8d592e5660af1e5a755e10dc71203317e126ceab9746dc16e6d1f11e2f63c38b9d314c989f	\\x00800003d052b51320b73fb245fc4a1a48f4d63c2230bf5cda5cf9d87d0c030c10f498c7f724f987102ea7d7db632fd74d5372de83c7aaa1505094f8326dafe98111fba69f7990fe8d4dfb6cf691ab1380c359853a531abacbf6df5c95d519a875e48896a03e6ea643edb38a17eb5addeef98b0f34a58f9efb23b80b4e66dcddde5c732f010001	\\x498a9a0e149e3ed85dc7437062d63e7b2e243c5146b43206e767c02aae8b3ddb444b9b67734d77d3e099421a37cef0b29028fbbbbc3b43588c2f72023f3d3b09	1645357807000000	1645962607000000	1709034607000000	1803642607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	3
\\x10e0dc08cd00ee3621cdf80a3ce736418054ab5a6babc45f0f213a2050377cd7933923cf8924f10ebecedaccc51dc7725d491435faaecaf07be20238187e105b	\\x00800003c787a13634fd40c4a1ce5b3a81e3c9d8a714db7c219fa7751f4087118b0f23a66b9edcca9e30eab4c21d18658b2aa6ecca50f92e3a2f390b8b618c60f4afeb6eff543f4ce9777fdd9e75736499cf003fe8bb724232d5ad01170689a911f1026e2e7c616a621c5ff4a9d2e29fd95acb83da04e1429788591cb873cb92c048503f010001	\\x81966e449df5d187854320c55b1fa64fea4621457bd8c211bfcebe4d3cc275587e8ee05bf5cafb8e69402f2075940d9a1216ede39ef95753750e8b6a8ccf5100	1653820807000000	1654425607000000	1717497607000000	1812105607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	4
\\x11102da8ab8c388074bd0a3fa8146d66cc64caa142af49d608b494af00be8fb448ab77d2a3c588aa2fbee5c965fa471688066b690d35ca230d47d722d3609b88	\\x00800003c3add80779dd1db4106299edc1ecd82501bdd0e8804cf73bc9371c44e729610205edf047e94ecefc722b15590990938f9639aac0dd7ad052f02cc908de40c57a99786eb3757b25ccffb8dcb207f9c1025addc826d5ea8b6679c6644c451a329801e01c309f15cc85a57abfa999b748360f153f39575d62c3051d36027460c04f010001	\\x0a36714a79162f4a1f056b2efd74470978865c389cb3c0c6791662db3a01481c8cdef1a12b5d4bbaea5a7a0fada3b4067a05cb25b801182f8b65ab58fe7cef0d	1631454307000000	1632059107000000	1695131107000000	1789739107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	5
\\x13d414a2c8920d34b37ca6f22f037a31ce264bf5850e5e9ac554582815283735aeea3b942cc86bd6fd1bc410ab7e6f75dbfb44b7ba02ab8f2e8444064c680b07	\\x00800003cf1c28484603e653d4e8d1045b19b40a555b26a083b40c7752529bfe9d5b39e3c193b9e48281efc3d04343b85496e4c620a6b09bf6eb5cab2f0f9f0d0ebd70c30ed193a6d05e602a4daaa37b158d97ac24ef6227b014be340cf1ef395fffb31ac94c230be686e8e5f5a21e300ccfa2636551c35b136eef9cf90225c4f4674633010001	\\x15a73c57b374a610d0dd370e11089965fafd2ee2af218bff0c07fafaa84a5b94b8c14809d009722d8d6f79b9431ec8564ea5dc632ce37fc5f0cbd0536ac9020d	1645962307000000	1646567107000000	1709639107000000	1804247107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	6
\\x15c409e230b9070eaa1e377cf7a2ce8ae65e963baff77c08836b3561c58aa3cc2aabd83b3823e90699720464bfa850976f10d36589c4e16719d0336a632cd56f	\\x00800003b7cbabc85ad717844290f4f647cf3b73938c24a1ec56e2d380b629d4aae0ca47f245f0c775c9f93765b5eee61d7e0096f91fb6826b4eebfae4ef8401b3f23b5e2bdfd8306ad48895c0c86955bcbc854f9c2313a297723c9176959bfa7e6e16b3531ad2d2e7113b8768ffa7fe86e461e517417e60b325ae95aa2a5a6b74ba3ae7010001	\\xc0706a73327907dd2ad9aa4db0254bdbf95a7b992fda174d8d204829d01e9dca4e764a46cde29de0d5e4a13824840031a8b805c398df7cde15f52e0532333909	1642335307000000	1642940107000000	1706012107000000	1800620107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	7
\\x17c40adca242ee725e1baf6bf52e73139e1f2fcfd3946b87c9eedd6be53770a44cb45437c7e9d2ebaecad3633dd6667d220e3db648f9698dca8ae86bc99f8e72	\\x00800003c57fae5558f236775397fd09b25aea9474e4b602e1b96d0ebbdf8a11f1964cee47356e71ce6ca9f38644fccbd76010f9e3d9f3376bee3776e61ce8352d70215d693e1745f0c6df452e5166d8e3c6e338638c40454fc1bfb3487923e8caae43aa96e632bd50aa0482f31d0740150d56d7421d092127b0758130d1c6f044164097010001	\\xbe09947de5490e4c6cdb49d9cddd4b891c772c082a7f5a1376c83dd6ae6d5dcbd0dd3535b6f01e88fa6f98c71331f1d44ab3ef1bd74bd68c5055d4269cc7fe0c	1656843307000000	1657448107000000	1720520107000000	1815128107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x1788e069613e0b367abf49425603d953d4a13080a9af46403fca4198fe3f86b18959b30655591d0922b83f5ed831ae6f1fe2b5627072f31e319aea53f123ad22	\\x00800003bcb255a9a2086fda4dd07a8d728aaa2ef17bf4f7db6e16cc4838c483e7fda601ecff97fd8d383d175315e29081e9b6286d369c4d5868c3da8d89ce1cec98849f22f3db04a64d4d45e5a1f1826e7782df9bd36223c65ee6fe9f40449cd838d002a10e9cba83257fff57f6718f8572a5c6cd039e1db641c52d0986d90841c4c467010001	\\x58cf4ea3739960883745324ca14648bdc93113343feaaec381de58283335f1c77d04330dab36c8ab6979de5eabeaf7a5e21a944aa49b64571d5a3ebded5ceb0a	1638103807000000	1638708607000000	1701780607000000	1796388607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	9
\\x1c2c78e63144059dc0f735fafdce4a0cee5c307473629de3ef59f35e8e96508eb741bfe95989cfef72f96332959e2c16e0c49aafd4b139d2a660ae759bd4baeb	\\x00800003cd8619c75db5c99c7aebe4a37efa02d547b688785537145b7854ee6bae40b108ebecfc9bfe882864447de5446b01c6359c0eb6ce621e3bf8f12d8874ccef3fb813fb4231fdb514ff4a95ae066ee076ea52315a5ba28417f4b279a239f531adca300a66257f1dd25c6f4167a6f0e4341c16e6da8119ad91f963fba5be9db62369010001	\\x4a686222d6cb9648e07e311701fb055147b2583db782b4320dc33f8295eec47f4892dd6a8ecd34a4f68e817e7be7debf235e3c1dbd55a811888df79dc0f51104	1644753307000000	1645358107000000	1708430107000000	1803038107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	10
\\x1f7c74369fdd6fbc5720f63bf2f85eda5329dbc9559e1a31c8aafcaa13bfa77948326fd823fcf05c5ea2795241b97f449beb09ee88bc12daf7aa255ea82e1ec9	\\x00800003be2f82d3b87237c6dc1b8aedecc65e2e80548d19816032c8c06c273d7174baa54e93e44da603f3b2e873d3e6c7e4dfa10b959fcd3ce22b039b14588eb0c4143eace36b53eb9f8a3808f1e54c3e540862a6570b010affb9157b9ef620e59ab50e134ca35f8ac1dc8b1a3f32f89b935e83f5e6220c7336d6a396d9ae40cb0a621d010001	\\xec3b23720c532536f5f0f499599e3e737eccd1f3a98bfedce6d7957654110c024c948387d5d6e56d81bc46c5788676d9b9f8f9c830153480783ad8a37016b60a	1639917307000000	1640522107000000	1703594107000000	1798202107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	11
\\x2180e22c511d0be44d5055698b4cb50c82db57e84705103b1a2cd347da5c21ef9ad9f4676b27e7b5ebf23454b4d05443f5c4255e8de1c7bb9eb3a07f53e22a94	\\x00800003e8d0011185acb912126a1b580be73fda98394c331476e3091ae44b87b53adc2c299755b7d5f6a7e3001a3ea667d6bbec736737658e59df6da794725b9e068b22ad2370ee59c5e86742b42a332486a4c40da70fc94d0946578316381d475ec231eef1b7e4ba8a7cde2ea458cc4b73c7d0faab2c3c4d9b3d5adc8868a606aa1aeb010001	\\xdeb7b293e0444394868b56f0dc48d6640327a2ebfac021126111679929498bcc7fcdfb26cd3c08a47a9bf911c36b73a671390b168baab9f696859608816a8100	1639312807000000	1639917607000000	1702989607000000	1797597607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x244c270c7c882e17c2f31bb7c61de08258e3a6747b70e0691cab4958ab03e7a715a4e06aae3c04706889ad7a8cb1fb0e928fd73951725b7838b94fa7ad69f29a	\\x00800003c373763211f63ca27635f940c212097fac68599bfc560318c8a765250c568fe9aee24d2922edda7428816baa68e304c9cdc8b08e1c98ee20291485577985cffba54b59efe6d162257bbd588f07cf69319db38214822b4f21c4922dc620cb3f90795b46895f2a789ee1295b15be68bbe55b5c8295d02f0217d41f6d1dbcf4d3c7010001	\\xb338fe0d4f975a97b325348ebba23b7b254c6496308b060ce440012dffc730a188d7ad5e0c46840dfc43674b129a25f6d6170a4442346d9c57f6b7f7493afb06	1630849807000000	1631454607000000	1694526607000000	1789134607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	13
\\x257c29eaf7363e632d64f5dd761721d16115417c7a227170589d5b36bf82fe3ca35fbac4a23956988c05def1a19be95f5fbb49cc55e182f389c8ad137e3bc531	\\x00800003aff6f717e35c8e99b2961829e6b30480da006f3b99cc4271c4d0c11f5e382c7a751762d36e359bd6fc9eefedc44918dbaa9b8722362b8e31699372da6097f53da365fe76833bd36bc58a6b04ebd55d9b9687b85ca3f0cc9f7c34481e7f6373d55aca8922baca3f31a01d26dff6308750a7f785c9a0169e9af9a61023909a02d3010001	\\xd7ce33d69740c6b4cbb520814c4b68d8fce4b9c4fbf401d912f0d5463846a7bf7782a0d6b2bcfd568f4cd97748b1e79517582450ff9543058fc65ea837f4570f	1633872307000000	1634477107000000	1697549107000000	1792157107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	14
\\x273cf54b7ee0656823e9e85744aff226218896270d2753459ae9badcde32450fefefe54b95cb8444fdbe4fe2a1b73861213b071b9b9f4f3a0bcbeb6dbd0b60a9	\\x00800003e23f64a2e16a2b18791e585ac4b8644e4088321fdc988d3244f5177e92a63b1a2fed47a109d38e55a5e0efe369a2f3f86d8a9aadb1f92b4ba4a59e6d6f697888938abe51982c883dd636e2310e41e374668f07be20fd39821fa8d51a2b8a25a10761775c2f225064dc43073c06da468a214ce8cf89d1f7a960af20560975eebf010001	\\xcc1e4fb536de939d20510d309c7eaee0e701555294252b6ce800c0a8673fb4b15ff902e90ee2ce3aa6dc7e0b14d225a1b7e1ac9e795e816b7f0fd7ac7b35b20f	1658656807000000	1659261607000000	1722333607000000	1816941607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x2a1479fa867b17999f29318d2e4772d86e120e381e6b97bf8cc34d238bd075a29da61682cb374e553818c0a46e825eb636938eee63100b9aa5ae728de6bc8ac0	\\x00800003ad9accd85fe7ba96e79de305ee29c75d59cd258dcd071972d098d4cc1d00028d8fe379376a2514512168728b406e07d37f92b693f87761a6b9cee293c333e4059f3c1789314c89fcad3daa54a50807273ab969127f3c93da6c6f8cde3aa0573fd07acfbab030693ad77d55760d3eb882d6bec4cb9bbc5c813691b0bad22420b7010001	\\xc282e83b2cf4eba7206a96fc40df16713f5d6bb90dbce29640cb45d74cf6baca5652d01aeffbb43df3bc1e46ff1e818f3ad389e50405d25c46872f95c9639607	1636290307000000	1636895107000000	1699967107000000	1794575107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x2c7c548ffb822ef3936641f36a66d658236f82b93637eb56b5411c1c40feae0353aa1f087da8cd4f01b1b372894989bf87c07c47cb628dc01247f3b56c1e813d	\\x00800003b7ea57fa169fe7ef8f2b85ee5824416ca81eec16d5bb09843df485237df026c69ecc17ea6fbc02b6ff2195c46c273e703e7a173e4cafa46e41ddf5ec051fe90e4196a2f0a3992332eadca8c680453680262c29d73c66f5d314109a3f7e202dde125ed8c8bd87f70f8ac7f9bcc2e7fd6b7a7948baaa045623a83be0dbe41cb36f010001	\\x2f20ee2c0b30d3f38e4156141cbf96044bbed614fd62c2ece8a1044f0cba9fd543dbee9d707109ed0f35b16f688e029b52843c39f6f5cc263ea61572c065f20e	1660470307000000	1661075107000000	1724147107000000	1818755107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	17
\\x2ed431b7f068a19c8106459420a06ec621b8bf697b49189409b46cb941fec5af4979b0479e8a9b9a3ba85d5fb6adb3d795da1ebe78f2547717e24a4494bf9a7d	\\x00800003c420359bee2a0ec930e0def3b2257639383cdb67fd3b14d7fe835e31004d227ef394718fa1ef54645a34f978bbbf8a278790a44f717bc6a4bf70e7a80d3623bff7b87ab0cc68caf0d982ac7bc9c037011a504c28a861e73afe269c1b1238712defa1b5dee337432a7724a0ebc74fec4920c7f4003bead74037bde6bd6ee48a6b010001	\\x733c16f777efa4805b5d94287b40e3f7942d98aaf630eea195acc5ae5afb217a3c4d7f8bd1d1c03b997e7811014e2614dd332bfe21f96d44e8d93e1a7149440c	1646566807000000	1647171607000000	1710243607000000	1804851607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x2ee001f44d15200800c3ea72b4fd290974ab6dbedcb969ccb6218629158eac74580b6b767893dd69549227a2d1b8c9104ff30c1b60a7c9699c30235aaea41be1	\\x00800003e35047e69a148aa206124f9680ef38db507c511da8c94728907fb74993fc65904074c28e4a5c4e7494ce8070559ad8d4023a7efb2c3c1e173d4e082dcc07b50f4cc21ccb001a8e7c35ef46408dd12b9b0000ec5404379287a093247296e6c72def1ea526bfa8ba1dc3f7113ca88a45f8d4c48284f9fee852d4ddc989005ba88d010001	\\xb3c1fb471f1ca0c2e0ec5bd86f9556ca75baf779443293592dadd28d39fb8d0d66fa6b9354ef2485dee5845c7207477405d8adc6c9bcfdb47177592b61d8c602	1659261307000000	1659866107000000	1722938107000000	1817546107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	19
\\x3228465c757432f5457e97b92804f72734e16f31a8a8ebde9c2844742e4762b1d154e2cecdc46a9c1295b68e5759da292566833d3f5b7b18033dc535c96e8fdb	\\x00800003ae6c1bc43e71b45e875b90b2f9944279d24c1b8aa2dce0ffd0d398e7e905050ec5430f7aa2f73336f1fc3c6d1d1bf2b350874d3fddfd1703ca774da7f7d4964ff3f3268a8d891f00a9d0660decbcef683af6a92ae865f782346d238d23e584097a7d14f26cb398855e8eca01d49ce57350cb407412d280f592e5008cc653766f010001	\\xeac405003660cc5861accc03a567fb901e5bbb95bc25079c3720b099f0ebef2a105b72c58fc902526d1bea177781df01d0acc24ea707cfce4c96f88b0e1b2602	1656843307000000	1657448107000000	1720520107000000	1815128107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	20
\\x3360d9a064dd100334f9b29fca7e22806af24d4db8e83b64cd70e749d23b332b6d107d101792c6f7c1c3a0ba5846784aae30a797bbca09cd076a635595e74530	\\x00800003b03e7e3028246e3fd7e2a2e2c6447b3ca364884df9314398320ec4813d07addbd2e0c7bf0fa695a55d8051bb77758148e154b71f044dc6f62b07089f1ea9604065e99f2630fb8b618ece481b7f0929a791ab490ee5e75b418bb8c57002d41df90f004713978f0bc551d1cfd7ccb7ddddf8c7e84139faf1a8e27d115ff0100711010001	\\x803658716f5e401d40778b7aadc184231a1d12e2cb490e7e1d7b3446eb8f3f6e0b94d5d7c9497afdec9edee07bf55d6c76cd28b48e468a0f80baae2b8a9b3101	1634476807000000	1635081607000000	1698153607000000	1792761607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	21
\\x34c00e2f94040c24d6616933bd5e9cb2fd8aecfb4395185b5572645530ef0b0bfb483a06e9f1ffd1b0bed410237f348ff7a1d6087d410c2d3f7522522409bdf9	\\x00800003d2c7075b94d73507fdb96553a2b44cdbda7a4802f034bdd12541ce6da1c21a3ffe783306d74a8828a8d49f12828dc3e11928d2d69624d9a8a01f22035b4dfc5459de2bb5b82f38657fc60a6255f46e3754ec6da269f95250ed06108f5bdac249217ff68c9c5062d97bb92670a60526b6d5b8dcb70c4f4373376492c49b03dbd3010001	\\x5faa462a2974bc5defd8f6d21161206b344e0897dbed8cce7656f69e5664e6e892f9a079765afe3ba71e3efcf6ada03cc6e050f3d68160b33ce9dcdb201ca30a	1649589307000000	1650194107000000	1713266107000000	1807874107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x34845489285480ccedac08e7c6e42930c6c484436d23df225f0a6ec924ccde24e503224312c24a4029029e73ccc96e5ed32a97a279bdb5c28fe92899fda729be	\\x008000039f6c0b12062f912fcbcc1a1e9f7eeaa862a4647d1593111f40a49f4d3fe7c5929b65d71566ed218dd5428ea79d3f48c1a30de3163d3a4ce3fae42ede6f4e61ab0fd4c20f41adf32b9f8018e6a7fcdc6847eeeab7faee9bfebbaddbb40e6537b991a22637d66efb69235a829990e3379f07d4075b0a01d196620a1d2a00df9a47010001	\\x3c742ebe07235266d6819a36129d5209b55eec959e71f9a8d2bcd5640debe3076cdfb4d5f55ab1bf7ccc40d2e9a4bfd349aba87186d2709d46dc089c1e5cb504	1655634307000000	1656239107000000	1719311107000000	1813919107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	23
\\x35f01084c39cadaf3a727d8cd33b8ba8e188b3554eedeb41b2567a83d8cc691c1653001173180a70fbd99ca2d817e3507e4270cc60dc0dbe36a528d25d93388a	\\x00800003d2b3b95f50a91d4d30e74794b91cee7781c4f2ff50e8eba098f74172ba2a608359d8314e5ae6278a9f67eac1debb953a2c2e25a42971ac3f32097b8075bf39b7adefac1a9110bc1d763cd229cab543adb415e08a44a16ae49c5101d6fd8008dc0f64012296f36d57e084b4d1b4d03a69291bd5849ec9c1f463dcaf7c9dadd553010001	\\xa0996c9fa206afb0351bfd1a3ef6953483cf073a0425165918d3a2d2635e73e07b9a0adeeebc16dfa8b37bb89be16afbbfa62479152aef2b5be72c1d2397f306	1642335307000000	1642940107000000	1706012107000000	1800620107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	24
\\x37f4f71166481c0ca18fb036820b0757bb09d7d8c24d62093b0893e975e9e34eba2dbcf7f63f44651c71635c9de9b45aa8bca8496b3913c90f720b95ae145413	\\x00800003a8b17d84508e8393285f95464459d0adebce5787868109b9e3ae2bcbaaf0bc052fa1da0abf8c28e8e805bccfdc7fb3273cbffcb0d4c348c2a3c9953b611cbf0a4c1480b59da37c2fb99d49b8c4d59b151fece9540a6d2c801a6d13ed0f44e38f7f69033573eecb217b0442d2f8cda3ad4cd066e82686c3a598de14423c793e5d010001	\\x39c627e42a3c0f0bd5ea2fc0fd7f88674c5ecc86457453468d5cd424e404e94da7c41624f7b4968a69b54e292a5a01bed39d561d363007ae17e0c5a6aa28ec0a	1640521807000000	1641126607000000	1704198607000000	1798806607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	25
\\x3e2cabc8a478242e1fcd0550e5af41fac57f4cbe1af245060e8850b0254a5b32597e8407ba085f7aa4745c84749cbcab7bc4568cc6e8c22b0d7ec6bb0119f945	\\x00800003a1aac6817f749c2b7d1fc6087397c61b79bde54c7f1ff2d19ed753ed5ea836f360464968bcfd014815ffdf4ecba5e56de03d5371af83b6adc4ac08b8ca6da0ae555ad8e54324c2fb8eb1effb3c08d78a4a8db20e96f17926cc8a9bca55fc759aeae31195fc65ecc3a70314a8a5e6ebe5cbd0b180b84dfa918e7c8f175be2bd49010001	\\xc9d0d186bdd61855b9a9e2c1a4b98646cc9ef4ed54bcfdb3d7f6389299ddf2bf3e0ce9da79705961925d922f57b90edcff16e369fd0f56266c356a13edba5b09	1658052307000000	1658657107000000	1721729107000000	1816337107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	26
\\x40a8f9aa031d4ea96043521da1860ea9171ac7b86e77c395ea79d27b0cb8aed4dc847d322711d376a2f5fe64895b5e766d650a5032857488df659e882a3c13f4	\\x00800003b53ebe2b0bf18cb63a703ec3ecd3ed4557780383e2f3f51b97ffab10af3136052ca3fc49cbe4d3ce3f62f0f1a6babc3e67e180961616e27d4a551c72b58a2a30193f1f4d3f37be7c3cc3d010ba4eb7c8c756dfc350a0f8662abf7df873ef202096966bf7e1faeb33a0cd5f675022ceffb9644074a8a9062f8fbb4485824d4859010001	\\xa49c6c20f250043af4c9baad1c06ecd4abebb218ed823a1be4961c7f998aa54aabef3a3f3468c14710be19e7501fc3bc55406ff2f362de660f8cb7a943c0230a	1647775807000000	1648380607000000	1711452607000000	1806060607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	27
\\x42f0b51c1f746eca4926f4157a079ea4f675be0168c1be9e9420c3bf48b2392721ccc5f4e1e9706c4b3b12b1d37eb7461d9ad738ed6189b8264d9a5dda11173a	\\x00800003b453c645712a09ca064ab50775ec7fb3d909e9dd23a351e2b389cfe4dec29e3766fb27a1238103ed653f82c973b0755b2be34faad01434ba1cd7049a66132a1697d0086224c7646ff6d2b9c4cbd151ac0b7a4b9db862f175242309b023fbf688e40167a581de907799bd1b4ae49dd6460e85cab98cc621413b63d2eef2662fa1010001	\\x81fd133d808b857d95860ad796a71875d6e669c3c16e4ac33e9790d506a9353e5b69491a1d903a347b65275490812593cb6f2fc18aea2f9363786369d407300c	1650798307000000	1651403107000000	1714475107000000	1809083107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	28
\\x44f8929c44a22d85d52b24d03c0aaff5905afa05daf81c5637aad8a3c9d287990eb3407f8b2421a6c3dad9b7455da2d56514bd1a90002eb1ed6f2bd95b4ef1a3	\\x00800003d5056f76a306ea9fedfef538599225191522b5a8db7b5028819f570f48d39bcb27af5bebf33870be25e2b264dd816ea8938b23cdd0137c8eab1dbc54e28bba998c7156981a556eb0cfae32ab1cf63408898a83a8cbd878852e658edffa7b0af67a3f150bb3029962bd2a69cd0751fd58943352c03fbf581652a84580a6b28b5f010001	\\xfb2030fa1dd7d7e603fd29f64eb79d6ca731ac8173fd8c26f3729d6e69827a63eb7c96c106069ba3ce7d1717233e2384c7694c1fa5d4f5c82a83961ac108ee09	1659865807000000	1660470607000000	1723542607000000	1818150607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	29
\\x44d412f8e68f16e36c3735d1d2653fae64a26776cf78b8a323103c745c59e19a52c909a95437ca22adfb03946f6e374e0498d76e83a170b8171b27e81c694239	\\x00800003c30c795c69c323d06849a6e1e7c20e20968df3f0138fc0103e26582cc6728cf0b274b03a19096e44030f18c69acdfe8943b85d0cad43f4afffdb08f5a3e457fbd687a660386d98743399c0b7c88f2f08410145e7a507b43eabd8aef4e39de36395ccab672360c33c0babe8f604dc28340633151c88f5f607dbc8942a53c1d923010001	\\x7c8e1f37c4006125d5b0511659422f08c2e066c8de33e650a755e168a64737a6caa35b6959d8e80b428ee7d56ad8bcd80a6129826626958488881e620b1b4a03	1661074807000000	1661679607000000	1724751607000000	1819359607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	30
\\x47b8d687cdeb04d39c1ab01b68bb1473fd5ba2d95a9cc4c7c799c192a99ffd7dd7961472efcb9a289e5e09825435e1993e7aab5e8e80158706781d70fbb12a80	\\x00800003d5d50ab14178c9c75b52c00ccaadd7e19527e5efeb295d076bc8cf307fa140cc779f6afc6581e0d82e48f1eb461f97a26c2e333619e7666905d1fdee7c734cea0e024ac87bfcd3aff4afdaf382ef70314f5c095ff18e214dfea7515b7e2782c998e849ad135da250aad4d6d9695f80366358659d8c705d3b4a3512a5228affd1010001	\\xea4bf296fd721a3522d1adf96dfad0ba9a8563745f12881970f04421ed654919699f109d9a3f6135f49edf112a966b8ffbe60b3c130dea06f0c30265ed0f480e	1647775807000000	1648380607000000	1711452607000000	1806060607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	31
\\x4eb0be9e036db2b536d08e667bb2736c6b307bf1432fd2f88613e33e4b575a8e479a26528747ed2cddef9eeb34541c28beaf85844094d25f6693ac98338249b7	\\x00800003f0fb7ae063a6540d1e4d54a7368b6955d1f291c7bd1974ca36ad1c10a4e61d26f26f7a1cd9ed60721b002a767af7b105a6d69850bd28480d6cd0a759a9f44f26e325e4cfb4654010272463d651080ca8d52af436a1006a24de062c43c27044e7cd4959e5db24f57ba71f562db9fc9e08e2eb12a0f4ab20cd9060b4d5c8ad86e3010001	\\xd66dd6b465fa3677b88bf26e8a8466cf677799fae2ded09c137a7e00a66a14341f59409ecef3e42508a0d130a81fdbc7a28ed568b70b735e250d79997d315908	1655029807000000	1655634607000000	1718706607000000	1813314607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	32
\\x4fd846b9c7bdc0a6933a545ca8419a4bb46c2dffa0ce3fc5620b7cb5182e554d530fbc7f061fcebac8f3da73ac139280332eb924f18537bf09d67f7e335287a0	\\x00800003bebdb2f5f00151c699ef939e68457f9463464409fc8587f1ea277bbf3a793deddc02fb34a0d80e6feea29889c648258f983528a83d75214d6bf86e05e5eed088e00c56b089f127e05ae9de614f444d055aafa2a7b22361df31a08bd262b10b8dcfb3ccdbd52361affee724f0567eda5f1b2411916194e3d0e988c6709d854755010001	\\xe46cba3ad3608a5f2df90d00302f060d7ff5572f9c8699bcdfb46a8a7f8540b807cf66c77f0119f54e014b41102e76e224f12e9983793f6b784ba6ac72768805	1654425307000000	1655030107000000	1718102107000000	1812710107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	33
\\x572c1c4def36298d444a1adbbd47410d6da043e60f2b4a562dd835482762f233de59622c7219b66d923111478d258538289ef0db3c5122c28e641a4b9526c54f	\\x00800003c95fbb91def92359df605b0d04a285cb4952fc9c7e0d5e792971ae4fe4ea8c3fb1b81c1a80d5417224a14ef6aaada7882da202e1d705ed0beadfa66d7d5afdc2e9777c7b20d150fea898f8a15542e82d29df89cd9a59c4f3da282a1e81b18888d01703fa5d4efd3ae20e3b42eb1d812d8d837b1f889bfabe1c81e1a22e411a31010001	\\xf297e26689e2b0d0eac318471a390f23ec2707f527a61e43d459ac1f47c2d69ad361e2f2ef544e5ce9f79defc61595424e322dfccc33dde377d8a0b34cb4480c	1643544307000000	1644149107000000	1707221107000000	1801829107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	34
\\x58ac6739c5218258d0ec082138e407299693979e13a98fc1ced7a1a2aa94c5286ac804b231527b048f08a237ed722950b44629ba5644b5a1f86c7da5eeae17e2	\\x00800003a8576d578439b43d0c9b694ac076a0289f84b6cb6203dc693030609d6c420af76789473c5b5d1650bc8bd768975e02b87fe25b8dffb68a813d0a3af01163975692c5e0d1287b70e6e5d0db1814fce83e31a4f5dcc5ffd18b9958f78c7b11ea7781275ccf2959c5450d8090782a3ce1f20fcecf4746ac481446689b717ddc3a0b010001	\\x66b56fa50c68da99c892fc0a2043e5843077d830257ab8ce58f4f65a5563d237c2eac9b56eb09992e531206e5568c2f6a00eb50df06654e2f8c4325790f8440c	1641730807000000	1642335607000000	1705407607000000	1800015607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	35
\\x5b98fa808513e4eb65a9c189e67bc88c70981df6e6152b0b5295eed6295e13242eadddc3a933d7818bc4e82e5333fe56087f26c56aa7d5bf9da0ff6bfa84769a	\\x00800003c9a0380906792f4c23e32aef0b2c7d81174dd2202af41c966f1bd3ad65839b8a90dbc349919b2ffcf23a4e7a45a3388413e839b64b76088a8b49af2df868e295e83d521a78f43b9c7f2b15fe0c39e6e8d1ded4a6212408fd7f02453a381dbfb71a92c0a4848d1d2eb512c5a321afb961310d7bd5d9d765b990121a7dae284af3010001	\\x18b3203825ba1ce1727c72a4c5f3f60536e42c8678aa70cb6839943f45eeb881baa2002a2a31f7e7551bb02d87fd7b2d7f773d43be43686a5cf34310caf34b01	1652611807000000	1653216607000000	1716288607000000	1810896607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	36
\\x5c2c046fd953dcdfaa1036369c1b2d2d1b1d47cae9882bddf82e2a279c5c2a0e8a6708cbe534049eea03c20f35ac1b48c57dce2ae6a2529f5ff2c7219e65842a	\\x00800003bc4cef8b2c198c15ae6390537ac1b64c20b102337e9bfb9401005e33ffbc614e56de40ad4f20bd262155d5c0b1f33ceb1b1f49f3cd0c5ff500e2d850e45edcf41cfd07858305b5811e074131da207ce5aa6b81290ff93de1051d4617534b7e391b8710ea934c1187f3edd68ebcfff361374228cdda5ae6d3b8c6af3eec4d2457010001	\\x8fc95f85c81edd7c508c693038343763532df4eaf44533df1173332c62f5fff842e3e0d1cc4dcdbdee7dc6ec445f98e9d146c112439d5b72cee7f933a586f905	1639917307000000	1640522107000000	1703594107000000	1798202107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	37
\\x5e044482ca3ab98093e2f1a7b274966dd29a29d0ee8557485c771552ac35a73fb390537ea49490358384b18f5c79ff8e9929f8acbfc84ff17fe5ff5eec84257b	\\x00800003a3970f8e05456558750a3ab364145780e38e1d617e192c40b41d91748fd97559f53a9ba8c2057c550aa29668212cfd98b5f8681aec4a03ba793b6689ada1b46766cec0106c0e5ccb034f01d338d69711a7f67a4ba703e50c3e5f11c2108eba80ec11b11e0ef873d891e4387f0b7f7dad05cd87e9c933b6aed5d1be7b5c8035e3010001	\\x965d34362b51eae0fee1c25f6c1554245c5ddea73264cb3b5a3fb62e83972dcfb13190a9bd8bb248bb3c41a25edb598ce48d7cb9623107d0915562dccf34da07	1632058807000000	1632663607000000	1695735607000000	1790343607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	38
\\x61d4e23402d0ffd661ba0f0bba82932557e54fbe821f70d8bfa847be3fb96812d9d6556e58407998976c3dc5f312d49376fc824a69490f865990070bc73bc517	\\x00800003994f6ef247f602ad88d66d683c198e9d51f35203f18f1c88a7d753a599a93c2a8ec083d345b113c81a0bfc4df4e8fce7348ea22fbe3b8db690fa2f1034939a1eb02e4e45996cf0f091a4626ca06775f3c93cbe6a93f31cf964e9c4725ec835e30f1afd38111c16059557fc6d251b53e3ec50a413a82e279debba9547be3fb867010001	\\x7f4e9490a57be241299256cdda4a7c9e6437837753235f252b519201a8b08c7e94437285985643d158e12cc7735275804035ae3b99db5acf3f78c04ce7dc5905	1660470307000000	1661075107000000	1724147107000000	1818755107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	39
\\x612c533be0736e8a9bc9b49679a08d67b58b6872502186cec1fe7e9f6694657881955089617abd1afc38be12e75c44f4994a1b54c8e873415e396d51806f6312	\\x00800003dcfcef9ca3d0e95119009c5cc25e2820d12a635b89cd063c72db7981b6d6c0437e4a7eb6095a0decf9dd846a0a2b55487a2426faa06797fe20ee78622e89d01274f74b1e01be97b61dcd4c6f52618343eb24f910c00b645b4ac739521dd6e5ec3895844df23d414e6edd88ad80948f7843415342f3bd082f223580242bc1bc4f010001	\\x23c16e0e3914b31f24e46c13089359b1d27471aff9c9daa28633a331870deee9347cdb990569a5c0021d18cad85d652ccc22c68605809cd87d6eb7f4f0608a03	1659261307000000	1659866107000000	1722938107000000	1817546107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	40
\\x616c31d2caade7970d7841abcbf241188a223664be55a6d66c9738c62ccae0bab3bd688f6fd92f68cef68cbfd152664858f5ed0345c10dd9c0b5cef990158949	\\x00800003a775277c494f172413d2fa8d9d6f1d9d1528ec30d79fff7e80dd2fbdadd9a4f0e70018d22a10753bc7683a5822a1516093b70a8103517061bca7b39efc484c6a05fd753dedf57c73df320a840445857536361280fbda54ef76d26cb1730781bdb230f0b23776a6f335a7f82e6ae41004e36034b595d0e296ae56911e42d5763b010001	\\xd786e3f5db8cd4edd895077962a362825b3f7f97297cfd7f56008d086b73c5a94b090d39a4974ae726e030cd896fb743dac42661417cd9806a853e134cf36507	1645962307000000	1646567107000000	1709639107000000	1804247107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x65301ec825280322dea2a74a792b94ee6cddcec89c63eaf28c846aab2410dee7989a056072fe84a741aebce7dd23a10f79b02ea3883c324605ee20687010863d	\\x00800003bdd9e874749d437f4f3c3f56ada284213243196e6a333de9d72a02eb79a157c20c58c6d41835d3136290b0d9a3aa60f7518818da1ad8e2b685b306ba6aab5147d1fc58693faa36797176018e45ae9c69aedad356712706cc56c62d5cc65ee47eb5bb624d480570d14ba066f42aac9a89c10fc95180fa255e4298aa10ebd46d3f010001	\\xde8e21c8cf531df794916ed23a1086c4f320ae00adb45724b1e2348540bdaf982ddec032e45a388c55276fc2073db4988391338ebdf79f0dc9b8a4683dbd9706	1658656807000000	1659261607000000	1722333607000000	1816941607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x66f8eabd8b45fa3fefd678aaba38401517351cc17c0e5de5a77871940d1eeb3d88c73c06ecb8a7a4c435a3968dc1c64e1ca810abdbb43e54d49208e8031cc4a9	\\x00800003aa862847b46038cf1e619ee914e8edbd08d32074e4f7c14b24597d7db0d1ea587d64a48f9e2091a4e7043159c8d6250cda9d8b84e410433c8b0f2563cab255eeb68096282ecf04b36aa8ab86e2d45d4ae60e61d871ee9846c4072f608a648cf057072480a9d312db140ee5473253f8ba4851f12e1333a2727116943e6c6a801f010001	\\x4e52a226863c66f821c1bdc2c581eb4346487db3b49cf417eb8015271859b49ebc60bfd09809d155d44d4064b6ff635d7c6bb291a3572251fb2c5689dd984d01	1657447807000000	1658052607000000	1721124607000000	1815732607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	43
\\x67900a9ad6a6ecb62d5befe422efc2757f9799770913077b740fa2507e790c5807580a0e236e1af8a9cf4a9a30b1463a68ef39186d04a65a5c7eeffa83aafc13	\\x00800003df7084613f5ff3d08cd13fa8aeb38e47bacdd0a5fe50c0bac0d9240219e4533528c4bd5bf310bdc7f60d9a37d2b08009c973bb8367bebf437295c406cf3f4f061f9b998bacf51bc30b47e600538b28dfdb2661c058821ff38c1ed1767103d6521a7897d75d236347016c4ea64ff905ae04258f083295d5b7de6d6ae87ddae935010001	\\x3e7d2e43d4a77a5af7f509da32c0e7c4b745135e237d4635845f28ea8cf576adbc7e7387f5aa2d78f2dfa5bef70ad35820abe5b81bc4c4d7fd016ef82f389903	1633872307000000	1634477107000000	1697549107000000	1792157107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	44
\\x68c8d04942b1c98f89e3d9134a1a824b2064c2b2cac1d893f943e30323e7f8d317fe56777a40dfc6d31555b49c5fa0f8edba2670d2934a6699855778926d5c93	\\x00800003ca3923719220b5c15f2085d4712633ef0cf293baacec7a42d2d95e61dc4c1554681e889ba7a61fa648543207a0b82e062bb6df2c6e5da8b992dbd1e323640e2a512a59f9f7ae8dfd05ddf4ce914cc3476461aeb0845645252aaed240121fb2d70bfbe99c48d72cc2d95df846925b799073d44874ae6c60c5dd7e3cf39efa264d010001	\\x6a82d971d5bcb49c20de3f1e6d4a10928b0df7f3e182c20aec4cfeb70c604ef07e4563217e3185165ceb1297af98682424744712c69ea7bbdfee68ecf90d1f09	1660470307000000	1661075107000000	1724147107000000	1818755107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	45
\\x6ba433abf8810afe9d338502b0a6f30889bafa46eb9b93abdeed7a904fa2eb2db99b84950dc349edfcea43e730af5e854ed5c0804748871c254563cf1fe907ea	\\x00800003d07f87c186dd86f07abdfa65db35014dd92436858e69777e8bfa690f27be1264b5ad467400019894e2c3da7ab8fc3977dce8ad3b339f4367add05125715edda7660efb8d15263a5f2263baf0c8cce97077550b3fc1b83ed4f8800ab0d3c4ec3262e0ffb7550c55bc4edd6953466c72019b8db636bcaf6f0553881d75996ce0e1010001	\\x6a8f1515ef817bc3a33af7d3c9abeaff772895831bdfd56ac0dcfcf52a1f15cef34d27ad12b6405283c69ad255579fc308a2e1025576c55fc5e684ca4018230c	1632663307000000	1633268107000000	1696340107000000	1790948107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x7270c78b0d81e8de03e3b55e9e2fa309b62e995cb08ea0b3bee47b79672cd019382cedc8e156fbbf825ce33f09f06c92c694b83074ea5d04b9780923d6b4b0ae	\\x008000039d4a9e174cc3ff2b3c2c94dd24cd0c9b512a0b0fd51f22bee4d23dc7c6ac897cbe0dd26834d0412259d980606189d3cb0c04d8328771d0149caf3cb39b9c0f17c7e9e1695424808d1a26b5bad1751b547076101818ad9747353f5516d40587179aeb83f588e055f430a1afd09e2fd3b968160f057d375786e96fdda17171d2fd010001	\\x5ea78b2388adb1a9d4a5cd5a44ade0193f1395692f26df96ae8cc74b6b3b25ea2a26011d1388bd0b48effa4df981262acacd36e0ff2827552fb2415dc07a670c	1644753307000000	1645358107000000	1708430107000000	1803038107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	47
\\x73a463c319fce45c11b55815f15f0f07aada1148f4fed91f3b60a241cf0f4d7ec598f4f5263e9304fe10ca9e2631fc4e3445aa78b85a31a47be8fa48056416cb	\\x00800003b6eb33bfc3dc73d00b7af82acc43085602bdeae4161544163c6a4eacb9b839e153e18fde0fc4ae0505230b48ecf608d629d4937cab9efa84a1d5ca7056c20f1aa5496965550e65a6e5b1a3c79e1391ad35231fdc3f381ce022b037a0a7b819c58f916b47a87962d3c1f60549360a86fd8277a7c39395c3f08b37142917a4173d010001	\\x1eaafcb1cf3872e834e71c859c4deb54ed28abaacb69d8726b70692f8129477e787af5e4cf5ff4562a9e508a10b4b7f7ade2305b8b04f0cb12274b1407e5080d	1655634307000000	1656239107000000	1719311107000000	1813919107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	48
\\x777c3f453cdec285151f557c2cfe496dbeda804dd097f2fbfbf94dd665e3f396a3baafb741fa96d6abbeb75b8956f2148652a2142cee1a468d3e50245e2c734e	\\x00800003b49b7b8186ef6e3a6bb1600c94e72b4ff518c1bb53b56262fc4b4a231e6223d12e45420b072dd462e494334884ca7b0662f3d56cb26deb194eb2927324cb565082b73908e956cf579186d0edf31c1ded640829daa61fc6a8e20d3fb163ce34e961d1a38c81020086c0f7edc4a3fe2aa8fec1560aa00411e59b06ada2fd414cdb010001	\\xf6fab0fc9d074b05c7e2c7fdfa28335565aa2d076817e725ffd0b766c1629549ce217dcfe94a4e8b7887b805e897a1e904a7a7f2783d367556f3ad36cb69df06	1655634307000000	1656239107000000	1719311107000000	1813919107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	49
\\x7bf496515d3a9397a4fef0274542cc865d2af860f5792d8f7aa7e19731bdd643ddbda49d571e1377961e23eab69baa07c9bdd1b513cce424b9b15d2756267c8d	\\x00800003b6617b3ab2998dd01d2be5c04ab428e6f0323c55d56b78c3269cc7509ee6600e977164c78b6171d2b829681ab34bb6c5ec8b010e3581cf0907878cac39334bface005f6f4f502ee9b9f81f151deb371dbed3639286f95c4bc9dcd148094bcb1d0f7554cb51a378811d7cbf3a23ae9797269b675c568180c2d7e49f40968dee65010001	\\xe8d4db570a7e6a94ad91d99a3f16b28517d681395acc49e1e45ce24d15d8b8f3ee7c58633beccf896728ce8f7c165fc8c88d93f7ae91bc0b4ec3329ceeb6c609	1658052307000000	1658657107000000	1721729107000000	1816337107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	50
\\x7b50e60bb096aedc38bc9087ad6741f2c8f4238f4f7f57688b846a4f6b914bff4e57010557424e3787ecd65f0d1b8e5bb17fec3adb22f03aac5c87ae30e7b055	\\x00800003af1e8e93a4bea7a57f1dd359b6e07761e18a2f6e033c8490edfff5b587b77d115f86e1a4af507427cb991e7a3e06a4caa9bbad6166dffebabbe79669f92e0bb16c85aab5343278633396b4198c061011c2ec944aad181b8fee79127f8af3c4757f28f66e62876c3bd6573c265c8cba02f22010ab5c950111915cc5c3eec76b95010001	\\xf7ff0bc2efef0e6aeb64f31426f20afd6d3df751ff45d01c196934eca7fd47e1a9f6d21dde2b09544564a14c9b4efd5b98acce46705716e845fbd33e4847d807	1641126307000000	1641731107000000	1704803107000000	1799411107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	51
\\x7b28942e799a2f37c7d612e2bb438f181cd446abe66957cd19b03186f00674623e5a001be79940f637a3cc59e1afb88a9daf3240a6adb1df5401b49e20f9ae6a	\\x00800003d33fe5db3350ada88d2fd9dc4caac031846e5e02f2845029fc9145fec31d12d632057dec122a1b9147f73eea25697732bf47193d66aaf6b86cce3ca36e3d0d431e869cc61dfdbe4a4e035acbe66ffe13ee679a396ce2166ca58e0484d32511df9684cd34ddf78e1f746c656a9e3d2a20683783be0d18410c3549bfea7600f281010001	\\x8dec9c0a4a11f455bd729d63a3d907e9b358372129c73af2fb7752aef89dc7178e45344be6111f9793d49cfda7ce7e27b44da41c238d9f3275916da82048010f	1652007307000000	1652612107000000	1715684107000000	1810292107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	52
\\x7e70f50a519be768cae4dfea91012bbffff2aa930dff9dc7f244d56cfaaeb15cd1a403e0933ca8c41fc52dff4a341a05f86a7c3ee98cd0de830588e4c8c5e532	\\x00800003bd941f15a53a8984f287715fa16d8f0ba5ce904f922338b36a9c1cd8108659dfd3b8e1357b1ba733ce3b8e8a6446838e4c620c07347a7e2ded0c830885c6a5d05b978e11a6cad0a81a6b980ed9025c98095486de5a92c5a64f47500a6f14fb2f93d70f5ec4fa391f8424173c8ad6b5e25926e23b58862d664eef8c1567ba9f21010001	\\x26f7d1a4e38062d666f3297b5a9ab33c41e0aa23b9384ef8f78db2bff095ec2d39086aa2dfa2b53aa7d4d27ce4dfe6c51206919f94b949668ba304d50f47ec0d	1636290307000000	1636895107000000	1699967107000000	1794575107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	53
\\x8130bd72f94031b4f1dca8362e53d4cff13580f81605da6b05a28bc459f20a7f313762b76264c0200047218ad2612e4bce1336c0e941f1d3d3e37babf22c30d9	\\x00800003bca05c2b18d0b97a8a157aa821f261ace3b1da58ca45db4fbe1a12af6c011bd734710fdca14d7d9277821227b85f0628e1c1a9280efddb2fea32a493063c03465ba19e79bca761a1d484772971d94dbd964b7217c9adf4edf63e0f98b22adc88274994aa65aea23b51d8d6831ee677982ea82b6e28c02d1b633c08ea5bbbd683010001	\\xf2ebece6d920256f753ca60e82eb23e371fb3e1079700b580b1c49b95c616b92b01958f6781610b8520813a41caf7157dd1e5c051fa2b9b08488737905c38c05	1659865807000000	1660470607000000	1723542607000000	1818150607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	54
\\x84ecc0f3c3ba3f62670cadc517af43786cdb68ccc173223b22bf26fbf6005c80c8ebe49cccbb4a334383144fd8018db975bf700abe7c20e61910cd8100c7b98e	\\x00800003ccfb351ebc3d68dc92ddbca33157af659b01e91f142a0fd6a8824873187c7988299de97ecab5ee4350b690139dea57b6f29b67873cda5e4ab2ba7082f27f07501a22b7a8d6b5e9f4cab26b8a01d8e4327c3e6a62374fad6ad30e58bbd700fa07861fd30519b27ee4847d87873fb133416e4371e1f0f07a07f0addee177a9a569010001	\\x35243599b93f1a13e7c2ae3751837f1762d719659083a50edc044cc3ce506ab9f6b622481ce51c24093ba4780983a4faf325af9c37c5c8e80c7481ab96644c03	1633872307000000	1634477107000000	1697549107000000	1792157107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	55
\\x88e800039c9f8fbfdaaa145b6302844ef62ba75d8a9b419cdd0bfd4c639eedc00448afee016d50591ab212c813304c08e71b13496f1232520d606090004709ff	\\x00800003a60dc50490d04fb111e9ee11ca7807b6654fff59a1e3b5b52f7c54749968026b23027b88b9c40ed3c9d3a32ddfe0be8334145ccb19d91e7ebb020b1e5f34491ce2b76885cc9e409869e6c45896b5324fd45505ec0c44b40d22d4ff8b0ddb05f7d138fa09ff6b1f264df635f0a0b1e4badd810b7683cdd4d51597ba034e9a3063010001	\\x83fcf1f24a3cf078222fdcf7929c9ba808ed208491d3532f013fa1023a1a29c00adb81f6c2ceeaea1131f8dc343611e88b4f829e0ceffd8e65623ec053c73e01	1647171307000000	1647776107000000	1710848107000000	1805456107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	56
\\x88e01d096bafb82f64dedc96f5b8e7952b27ec3f74d5fd5065d94f93bb665e35893a84ed72181d8e90648ed257817b22c4da89e9f6749f3be5ac12b00dfe3ee4	\\x00800003dfe601eb8dab3c89b73f63b2b308ac1533ac10b02880ccc978e01b0553a67a04fd262fbaee203238f9100549ab266ebcedd130bbcbac85cc29af5bec614be7a28e034fb590dc47b49d463771c271badf2ba6102b1c9c7a89fa35aa6fc9b1eac82d1ced0b9f4edf9cdff863b52b9cfee9693b9ffa018b684bb999070f1b0e4adb010001	\\xf33d0c54c76dc87cf9e28afa92dd3a572f7d71e57a0ccc7c47114b5e694d7d0d93ea6b7352aa79f7cc0b00656572a65506cf98b47999f3af96b037cfb8b05904	1632663307000000	1633268107000000	1696340107000000	1790948107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	57
\\x89bc8fe465c3995f176ef3c376538c554bf66ed1446fc524759c6091fe66a462859bbc6e9b56703a336d3993a3b497b459c3d2767cbfeaf6bfb8ce69edfe680e	\\x00800003aa7202843fb20af865d9fafb4ec9f34304b74d698a57e0bba27c651b643bfebd28964cf808a686decb75e826f75cc6155d7e41782aea499d93f8dad82ee48560eb64a9e103cf52f6b37e4c3fa8f850e59b5a95bd766dc0af7e78645509d329fc74d77d5cb485667152549524f36a9b0c4bde3f1bbf5746126e39f531efab3ccf010001	\\x4d2ec064a43c358b335e50e10aa1543e45542296bb37f843540aed5ca39442c79f2256124bcca0314a9a21a13640cdf7065adc034ba4abf813f500d81a314100	1662283807000000	1662888607000000	1725960607000000	1820568607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	58
\\x8b5c6e8d7613a96f483d2231e15a4401d019833cf888e2a0c34c334cc00127d9628db10e013e9a1729f8ae9edf74b542f353cae4764014af496ba83f195ba2f0	\\x00800003c76f2300e2393b100662d1c01ccaeab651c1440fa1f0d664ad1f9d7ae5e890d143adfa5e2e5c882864cf1bfb014d5a9ae041df305965c2b27a5e7bc9ed63b7e116dedfac16677fc6fda7977879e07deff10da6157d1dfcb2643dd46c300660b3c46cacef0eacdcb9b0b70b03a2184307ec9e1bdc20875fa81ec69da262f3935b010001	\\x15d439fe44ab0c8f44ecb7bf5bd7c16cf1c923501991f5df5c62f820afa9bbac119fec1cdb37c5d47eeed3ad320f4096b84ba6c0cf3f81875f0edc9b61b8410e	1652007307000000	1652612107000000	1715684107000000	1810292107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	59
\\x8df0625308db083b31852bcc10c15706b53d32d9411109245ae44e632c88388e30dc6ed8347001d65c321572569ceed915e1bc4953983b13de9e2376fcad3a87	\\x00800003cf3898ad361fdf3707e878319557425fec7c11160284fc7988c17457448c3f2bd4b33c85df88c3c788ccab88941b3d64d1011f8634f6f86d548611a955b757c1f09831b95b965ae2c9317ce5a9e7c37c4b304de7e3aa8a9e3690598c69f4a9cbf0d7b2d25ed1e6110282209e67046dd38b57bec6c853ddd88ebda09e50771e73010001	\\x0017a3d7380e42ae8506b6e9a661d4c6b4d5ac852d0134223651a99e78fcd320ecf6043e24577d405ee00bb69358f04fed707a3a8d67657c93947d8cb36bdc0f	1653216307000000	1653821107000000	1716893107000000	1811501107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	60
\\x8f1cf63f6dd6a608d4c1c0e6e6c608fa956c6556b68655e0b6b233ec7ca303e88f153af348ada68b0a6ec85b436419efc876608ff854aba95ad65aaf60b98544	\\x00800003c1000cbeba5cd166f3eae0e604df2d42865f4d8fdf5c41ec47b312b875d6ac95b643127e69ce1e941d5336b73bf9e6d0ed960343ebd4491737e20b1103dfcde58959fa37ddd49d00ddd2d6024111643e981da5db49617d8966327c0abf623fbcac23677c01ef47ce1739a54045f339d3782da6ed1ac1b5b891c4c19948d86b3b010001	\\xf868fedca406f197efbc98a586c0df66f2d4456c333ff371d121db089c82987ab42c5dc97d2418a428d2e5d3060b1f03a5e39649f9cbce178491b4c789f2be06	1634476807000000	1635081607000000	1698153607000000	1792761607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	61
\\x93a4ac30143135bc6a5b56c1101bc1bf52fa77edece6abc1661b24d16d0428df4d84c4b7a69aae1a8e62ee31c16bce6e33d487fb9fa871ddc2916b8311fd914c	\\x00800003c2563e7ece764373b75edd890b42e79b1d2eace517ea5d169b2485ce57593feba9fcc6286a4e41b3cf2c9a82456222dfa5eca72812540787309105280fcfe2cc54c0fff6db1a3729c711240c8b7d922548149ca56730a5f42f02b9c2251887c62997160f0b91d9db53c51205be5f08154e5444ae89f0b95a7b2a52ebd6dc5773010001	\\x340021b6737d3e4595314efa555976a80ac323fda04f583ac620afa410107536608064b930e00983f75067029bbf953ef0ee45862037481c8307c988ab83f90a	1636894807000000	1637499607000000	1700571607000000	1795179607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	62
\\x954441187cb78923017515499ad7880b287968b5d2c3ecbcfdc101eba9741e4ee99ec168d9462ee5fcd072a3648784cc63ba6f4ea7e1799cdb6ee1ed7870ffc4	\\x00800003d4e81a1869e45c31ba99fffb59420315be63965ee4653f9750b05e1dea0ca33e5baad249f00690e13f9dcd2bfe71e198328bdf8ff21213e7790923d9d1f37bff770f0614efcd5c4b85033659fc62fe53cad24361630ae0b52a16ad17880aa13df0d5368a53214c52c25296fbe7976472918a5b756e4b0554316b128f03af7fbb010001	\\x9497bd573251d1fa5586f36bad9c17495964b75ecb41f7950f2e997da348ccfb74e37282c9083cc2d5b45c85d64ca033d30b3f3b4a569600e503ed5fb9a0ce04	1656238807000000	1656843607000000	1719915607000000	1814523607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x9618b8b80ad1b008f210c7e6859de2888e4e6531b4a10535cf35a492846049812a5b6d17e0304fdbbeca3c275d6903638e509b4df65205f71d1c5b8b3cf5ebda	\\x00800003c2e82101dbc3ae62d64518c09c794e16cff33a663461d28d5d2fac734f336b29c2d137ccf941cd6c827be44783df8de1024d60067765485ba9be897676808016e52331e8bbe754316c73ad3143a68b5c90147063a81e94b0b8a408d126f7aadea78428f96420594bc02d37871b798f1c846edcf3b6c28e39ce7ca813bff294c5010001	\\xa159cd9a87de4ec19d310f434801df8a5bedc4418027afcd752d0f8119ef4cb66423a2d4cd3301f742b33d0a50236b23ba879303107f83633aab210e647ff502	1630849807000000	1631454607000000	1694526607000000	1789134607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	64
\\x9fb851cee6a5f83495008c5e55b0192b6b80b07b5216b81a2315f0101f2fa03fac9e014b0c32e8b7a987ec9dc33b5fdf5421f318576821f688c85ff9ab2f3f53	\\x00800003c975856780d3a2d36f73bfc4f61b6c937143fd328ac1faeefa57c878e46c2cbf7d92bbb49fff30fedb88f39f8c1af7ca6d0a373d12016d4c1223b002243c140f062136a7ff5b06d04cdcb69becf6327aa199443d452a61e325bc995d7d2f7150e710dcd87bab79e27dc65f008ab383bd2c7a88988daa5d65423dbd869d7492bb010001	\\x697a935aeaf7b492e17520cba46505a7f1d44122adc05d938bb7b1ccf0878dcb0dc8bf57aeddde86724cf32aef18211c0b7e610109f8b70806deac3e7834ca00	1642939807000000	1643544607000000	1706616607000000	1801224607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	65
\\xa1bc54b4e9f535019c27025ba42e8b9be395e0834de4f6bb7acdf45daacc712207e0f15f90747da7b5567b948a653da2059845578e2b9da61966e61f9d76588a	\\x00800003c2b208890df807dafdf1baf8a7ee4e62ee950edaaabedd5ac318cc9c6e7bc9c8cab57ec921ddcdc6854b062887cb8eebf303b5dce274c73216b0b9a1d544b9ec2dca134ca206ff9427f337788358e5b289790cd8ad9da1212bd7d0fdae78498ae20c947f5a22584936cbd6b5ccd4484fba304735ecdef5d650bc33cb3b994387010001	\\x4e11b547620ca30070c0208455cd356bf51a5578d32a7820e04325c3539d52e3b0ca854f6e0e90c9a8916bf3efe2262c6387f6f222ca50473ca6f9293332240c	1633267807000000	1633872607000000	1696944607000000	1791552607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	66
\\xa3645ba55b81e7cbec9b12e756bbf3f432dddeb57edf5ef9ee39ef63a173ef140ff39279024310c6505738816a2783c94c5a8efb8ad81606ef6963c274eb55c2	\\x008000039cf22682c9e7448101ea33e0f7ea249c4198a65ecaa859ce850b4fd3f796c395344ca95308c92fda5a219c81561b0cce4754a8d75b4ddc035d9eb26fce924361ef45641cb8327e2b49bf83e4eb448cd5edee2c4edad42d88335283a59c6a3ee71afc94933f12990528b4122eed931f52540971d92587a3f390653918bd26ed13010001	\\x6707408a5e2a9b6e03335eccb37e994f3bca8a2a457a4535efdd65e4aa142da8cd1fcbd141111a6183a025b7bcad1f436125f4089fc7362389e8e19644f53c00	1647171307000000	1647776107000000	1710848107000000	1805456107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	67
\\xa448f198c5161582898b8fe17a06c20fec0d5a2a93c0221e177a56d237ba2ee6bb4c9ff52b66f5148a4380f51a76b463486c2ec4434afa6adeec6d5373e3b134	\\x00800003c537961e7122197f85e1dc25477b7e19cd85095f3aa67782217c99a30d7d7ca81b1dacf9f96e57843255d2bb25ac77d95c850b2739f551c20b2073471ccf9b0e84ac83130826e1b9218e07b9cfe3d6ed76f963cbd2a2da3493ecead6ef754e1cf391d886f773f42065a3423ba8af1b59e7f92f27b763bce7ecb65626954ea5b3010001	\\x52b3f6e00e6e342cb1758e31f75d379943ea79a962abcdbb81ac521736be3dbe1df10a8cbb564def6e0f9f1e54c8b3d5ca34f607d2085b0dac3e83f0bd856402	1647775807000000	1648380607000000	1711452607000000	1806060607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	68
\\xa8a49c4e4efc24b8e10ae70d5bc2216b65102e0d672a75333b23d4ee004e4ed2e3472ef20a075da00511c0a2ff8321c2bc9244f729dd3159a8bc375969a4e6ff	\\x00800003ad108235898bd7f3104b849c1123ae5a6e63f77818283b2d92ca96c43802f413abc7f602bd37ee319093ae717adea2c91664873e09f595eeea0d809547767e9b226f4f0b24e2fd230e23d423c833df25236dc2ac260f8fceb13bca516d46d09fc750f7b58d7d81e7f5fc14742dc2589e11d944696f3455a24651bb79de35e08d010001	\\x18ff4abfb1a78df3c845b8a818032899854c3e133b0746d182de950faf901d357c3cdb8d3d6690e7802bcb00683750fde0511aaf0fe9d611e35a2a0df5e5350e	1635081307000000	1635686107000000	1698758107000000	1793366107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	69
\\xab8817edc3ca7e71376eb0b728cdf90af63121cf17ec20e12e3f75299c7f1dbafdfb113250afe2bc1487aec6dd574d63dc0cc8840393b7cb671f2f3dc300101f	\\x00800003b0d694a7af43610bf08084ef4a71b59602fe5760a352e19bd21b505495e95ae72155cf1e813c635000daa6e3e784fb6c583273cd6e549cda5029e817fe3c36fdc4c7d104a67a364af7b65da59c40d5b915625222bc88bef5c2ea2fadf6cc2a46cf844a7739221ed2cb56e44b045f10a707a4be8165e3ccb3ce457e26a96a43cf010001	\\x697babea4721a4ec638753d0e25f571c2d256d906c4ccd84aec74ef71428648d97a414fe99d1006673e79fe8e6ccdad67bdffa65ec3dad25d23d880ae3312d0f	1633267807000000	1633872607000000	1696944607000000	1791552607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	70
\\xac185e8eacf9e296aeedc99d5a17b813fbab2a128ec6fbbb9c1994729aff0dfd01b2ff870c05cdabf75e51085a4b728b273c859a9b63f84656f95de4b15ee7f5	\\x0080000395aa3223ef8dd8d6e212e9c2f15a2fa6bfcde4a8c0537e0484ad6f4f4345aaa74ca5cfb1c3bd335bc0308a6c8647d8562f6210bf900f1cf149a832a85a7535482ffa5991d9af12f5a3075980952327e692e0f0e889b0d84288095be84bcbcc1d8f645be62755739a326f9c37cf31104525076b9db99216d1d15ee3b49a5568ef010001	\\x5f6220776e5c3f80f0cd229c3433723d856af2c3fd3c8d6bcf8315674ab37f21f800e51e1a17d728f02d14421f9ce470e0d8029c41e0140d5e461867dc08fe04	1651402807000000	1652007607000000	1715079607000000	1809687607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	71
\\xadf4a130f485cf890e4950c8c404bf7a71d5118d5e1051de7db79418473e1b280739fe1e4f48535a14f39b35774ed0daae7c74be6f7e9e7b7f6c64053ab5806e	\\x00800003af46caabc37b96911556be574fe24245e6c1034e0d0a6baa4df40503d8e6d21526436f91c0e586a0cd5a39aa3edf06869376c3c60d98edb9dfc517571942783c6b2ad5d9b6bff968e1c868c7358daab48fd8a0e4a836a1f959aabcfb514b3cb234ba2f815ce880fd5c7d33863890e3ce97ca73bc8a4d4566882d5e1fe0a674d5010001	\\x9d9e366a61dec03ba405f3648da7bb0b65b5acea5c17bf8a3dc70ee0714fecec68d4dd75f97b8e194f10a9b2227d13f18873179d7371d3d580deb055c3e33005	1659865807000000	1660470607000000	1723542607000000	1818150607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	72
\\xaee85e12f59c8c5b4255671d8670c9a937d7fa3c5905f099b76ea74f13e0a6fc53180ee7ba1a0039129b043eb5fb038c5f363aaa4de50e75d26ee3b07a9c3bd8	\\x00800003f01d8f60738aef41184b7a177d761cf1c5fa4a1e37f2c4d50c3e9468e9fc09e07bb229450fb1af0ff039403ecaf3e8b5cd79c0cd953ffd17dc18f70fe6d23e6fcb81e31a35cd3b69f8997874746b23463150f77c235bccef9d218b9b29ba4b5d25ec8ad472e7b1e4679b8c8c1d9701d6c9d1b162d82e06405f47f235ba8dfad9010001	\\xda9cd0ad4d08073a8295b3a158e014dfeff05c39d7681e2591f4b241ca4c3be09297c1b7ce051d0040a3ef45cb5e34293a4c673bd61ef0c2d37d8a8e31dc6d0e	1655634307000000	1656239107000000	1719311107000000	1813919107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	73
\\xb1bc5fc3d3b03f91a3d5b69bdb9f9fd4d6975d358449cf966d4db46e78913ca8f17329ff31d36c9ec71b57f1d8f5815a49a2e83b8c1c55e09444448fb14601dc	\\x00800003d18f11e44ae931d25fa41d792f58183e2f26d1082ce31e9c48027ee91dada0cf3838bdf40cad6f23a0a885fd24680c7541ecd0151b8d704996ab4825398ccc4c02fdabb975731cd6f7e1c345fbb45f1e9dc6065223db0b1c9d7c31eb3591f1647e8dfe116733c2f22cb6a1fa4906ef57a1eb435cdc3dfe8395a8f455d7a838e7010001	\\x8bdf8d77a77bfff0fcf23b3471812d3aa64efce87ae32faf81ba9a26534db3205933688bd8df73bfac4648cba0b624d43e51c798b24f71591b906ac480b47c0c	1632663307000000	1633268107000000	1696340107000000	1790948107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	74
\\xb6d0f001a514cac7cb2edc9d4c15a58e201231251c6b19413d48b67ba35f9ad3707aee59b0021406a92f01979eb21df0379179a1ccddca5018a08b08821e7627	\\x00800003b974ea0a82a32003127e2b8ccac3243155cbf46d53efd5ee605f93fcfd331ae55888e88e67f0e5b3248673e3b16178247d7aab79e21bd9c5f3843ecbf8b6531fc1951a8fc3477a770315df6a1f46298a375eaeb3fbf638d7a3a5d71edba9b15f6b896936d74edf97c789497e3e201edebe3ccec21bcab760487c934f5493ea97010001	\\x008f7be1cc86af94b23a43f6b627489d9ba10567aca4f7bc22ada177a2e3cf0eb126c415ff9631804d59c888932c1442b7e9cca3273f35ea942edc087ff60c08	1638708307000000	1639313107000000	1702385107000000	1796993107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	75
\\xb9e022018d40605a7da5321d76575e985a8b4630825f3008a7c697422a79089d2f5ebafadc702cbb6b2c36d18b31bf80ba331b7d473b4f8b13f498959cc5bcb1	\\x00800003af34502f5c0e96fc82f5417896ec3d745786c414a62effb7106e21985cd473320e9a5ec33285cb6b7955b83428068033888155c830289761d2d89d9d1e3e7ce7641e0a6a21080585fdaf56515e8f869831fe9d799a92d11f7c03ab41c9b91c738597b8c0b082dcbe64c6a5b05a3ebd30942b3330e8ece2d42491ec22b666d599010001	\\xac079457314a080a1e438f493a9ddd4f761d15c59f3c4bf1456e6d4b8d812def683619fac0538efffbd1676e9798620d2399e63c9fb3f0e6b930536f3834cf01	1642939807000000	1643544607000000	1706616607000000	1801224607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xbdd46e4706e93e2182211ea4d51985f925f850649d56dfe62039baa7c7b9971a1223fd5a48d1ad98476cd5f1e0b654b97000a205ce1aac64cb35bdd2ec78e61c	\\x00800003d0c50fd8c0f9083a1c74ac5af4131f26a31919913d4b36fc528a728b77ab10fd94524a886026788b1dca3a6b141a3c1717167c9ac67521772c8279281dba8a582d021acb103b8c11175120816b038ebe90e718f756f9616e45d7a3177139516c15f74247a3a66c2f0151b51f2818bbf21c31f56e7e6b4fe825833886ba574d0f010001	\\x8639499db270d48cd53db653a508f3ee9739a3d0c29bb2e0dda9af76759dca21884597eb1b8bd5d532195b356f3cf59bc1923c9b3ca733a786ef602abd103105	1636290307000000	1636895107000000	1699967107000000	1794575107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	77
\\xc0d8924944e28ba3496a147dbf7715a997349b53e99fc331abbf262bc5645b62f54b813683fff012114d4aeb49cf48dd0c37e331e2687cd6ff69f008b7fa5e4f	\\x00800003b94fe9f2ea1db144de57cc9ee961398076b8e6d8a0be59c51a74b7148ee80e74a4f55b70a0a1469145d48f90a657f32ce49454a628641052ada3284173e0667c7b241f6381db852a52865396c75c2ca61d404d5fb1f321f5efb29ed3e525f4173f1dd4eb42b196aaf24a4f250c85d916c6cb33f4e6d38a72c2cca9958c86b63f010001	\\x42ab7757c335eee6d491778b6840ea5bc54acafb0fb3030c9a035a9cdca10d8f55f42a3a09d31a68c6506392ee1afb1810d6d5ed248b4db86915dde64589ae0a	1658052307000000	1658657107000000	1721729107000000	1816337107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	78
\\xc4f02117492e7882da1c2754deed0b3b27fb5dde60db90f143d4a5bb016952958a015abec162c14120303f4100319ea9f6823354504d2e3a3f96c46244085d38	\\x00800003e8aa0b5bb737ef4fb79a242f6fcd9ef706220f41b1d7fd780baa9039310335498a116394f2b91d2a55a5a5562c6287a534336e575e9c3981214cb00bfac48f3ece0982ef4f29c056577cad00f06282e27e636b1c6ad305f0e1ef79fe2a2f4ba37f52fccd39b6062486c609a35fcff2e0f8858917d952f7e4c26decd32d3e48eb010001	\\xe8b2944c28e4fcb6b02ce035b48c5d94dae789409c933d54da1660ca0cf8d3e7bcddcef3064d19203a17654375c74a18abfdddbc2e84da72c51f2181c9ba9405	1650193807000000	1650798607000000	1713870607000000	1808478607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	79
\\xc6488c7ef649d08e1a193a61f65d7166fb243fe3f3d1fb7df70e76c278e7c61aaddbe11eced3b6fdb94a582ddd0582154f6eefbeb54c9b7ca68dfca3d7c60ac3	\\x008000039ab70f038be5bb95c012f5503808a1eccd7905f79b6990138344895741dfb6b4f03d2955ffaaa5318ee4e0f3d634ba40a4dab7d50d90da3116a4441e8cd93d0677ac02ae1b4214982fad310b63c8e3f48c7dda469674542880bfb975fc973cb6f41c1c7b1a3f8ac273d134d4241ff666b21b219e7a67656420779692a43946cf010001	\\x3404500a31c045af9e075d8fef91a25900d6b622339329db6f1906472186ef15f87ed710ea15fbd0c120ad13202c26a808d2fc93213f964abc0855dd6c998e0a	1642335307000000	1642940107000000	1706012107000000	1800620107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	80
\\xc6748d646105524d6c435ceafddedd5811d9c43ed3c5c8ff5fbe1156a0cac87e0adf1eb6d50f09c5bee648631fe6b1a2dd0e372ebfea5e662b3139e186ea04fc	\\x00800003bddbbaf9c93ee393c2a74c25159ce893ceeaae15efa26d644545cf42223311c977fce176af7651e4b9ca3dc7b6845faad0506880bd492babcdd097228b237fcfe3bac20852a35bccf06f0279afddd47ab04857f6d9074302c32737f7e24215be8b25adae43fdb6a87e15863330961ca7b5361fe44e1f8f39975b2f57708627cd010001	\\xd962c66c6970402b4cc5fe30c38d425a59f5fd30f748c9ab2e8ee2dee7fde43d09f588e7ccb6ee24ca15a77767b0e711cb179014820362bd9e3565d7a173ae07	1645357807000000	1645962607000000	1709034607000000	1803642607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	81
\\xc7446bc5438e39eccf3d7a61a5b8aaba74e214bd15312df89990f0800827009fd25f5c3fc0d7962088ddf19c354009a59bbaa0844d757ed231daba736967e90d	\\x00800003e6acd5c7c5a4ad28d944c82acf0e865f34c6c44861f7bf4df8ac160a73fad9fa541ffd711afdb88eaeff54334a801b32f0dddada2d2a3d9844c92f3913642d7a134b9bfa169268566dd7a39e5f298b90600c760adf3f7f00f290c2c17cec45635f4b2719bbe705db6453dc0e7a20a0ba2daf9fa85f6fa3a9cd3e1fa4006368a1010001	\\x0662cedb03db62d72f3c5f5afb1ca609e8edcea1c0ee7e491c546fff213479766df124057dbb0b9b9e92df3e1a26b4dcb4a5c7be41b6a34c9e1ae2d991e0a705	1635685807000000	1636290607000000	1699362607000000	1793970607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	82
\\xccb041096e1516ea11dd4adeacce86cbc751b36bef4285741c722f7e4cc225fe6cdfeab9e6586c9566076c37947be18698989c127367deca51f313818ff10d23	\\x00800003c191000abcf84af6c09e8441c2f45b45f9c9129728e32fa745f6c34e0854226d1699b8f169a77f5923e0d1d78de098a9f880c49baba23d1b8706ce56e07a7aadb222b36e7c0f94dd077ca0050e10129320eb71becad0599364d6353be72416ad575ad7e585c330bad690200906911e4b75104b49829cfbd6d80c35d5ee31ab0b010001	\\x86ab1add59dac32cdad6e9888f6111feec8f4382db51b28cdc16070ffff38e7797e9199ab6f9b2efb225f220df74d6d5d1d7cae057865fcc464079f9fb2ed507	1637499307000000	1638104107000000	1701176107000000	1795784107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	83
\\xd1a0911bd611eee08859616c20538c27546039d55d251863214e6aff904156c6f0194b71dc1ad98788aaf7969c4321d3f1b19b24440a4acb848c3d66f0ad63a4	\\x00800003ccd0fb1ec6341481097f94ec913802a93f26393a8f52fddf7bb7bf7916ed50d2a9e9893a13b2bb1258c44e9330c3a27509effefa8b7e29f3570a489f04fea0186482b58e5d2a06bc4d8b0ad93d3f225dc5dee08b09d9cdeb37c575603327e3e5fd8d0057b9a471ff577a0c399c0929d13131242faee241933d2f05f81ee3c603010001	\\xea82859efd60711b6f448d75fec02bef86a5e29a4445bd32d31949bc59bc1f89e5c007f390f41b75693446d476be438d3b691412a271189461b7e10a9bc3b50e	1638708307000000	1639313107000000	1702385107000000	1796993107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	84
\\xd490504d90cf1115145e116bcfd5223085cde35b2d9c5ea5b8f5d094fea1214a46153ee9744dcfba23a04fd97d47f07058c570e4e8f93149ca1db829fc158e88	\\x00800003c06741f9a6f82db6a99f22f3da73f1a46d21c4e1c2472b2d77bd61fbf5e86681e02106a819a5770f22c6d3659a0751e38996d4e760ae4a0e1563e9345c5a9284f9eef7e7c388a63f2eae7d715cb02a68b963173f91649a65b4b8f9f5601cbd5cb2a83e462d44140714b448f9a6ae6a2bfd48b1ac387163c55f23e17875e869e3010001	\\x42e012b835fced6e3eb2bc481be00f6a717d2f01ce27cde8082444537f7031ae92ff41da3e23f6f4c7cac1ded4a7528ade9088f1aba8c167ede5637e2a5aa30d	1650193807000000	1650798607000000	1713870607000000	1808478607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	85
\\xd4889daea12fb80930b76e45971226e0c3bd43018b155aa10a53c803400fff88247b5ee5fdb7b99e1ebe13f503de5a01b7f3bb3515d0da6028a36eb2c9c5a897	\\x00800003c43a4959ea7bd4d50aaf6363681ff57c2e2e587286a37eb57d11ef250771d2756607f4824f4deff304b3e97709e39176f6a56d8052bf422398ad8d9ca0c365fdf39ea3c4ca4aa633ffc39b109f096bf8938503e51ead73477ff923af67c9d31e30dd118fdd7e65f7b90a0770f572f92e4af1be7208d9cdfe10073e60597f7293010001	\\x7da65effbdae9fbe12920a16f33c9f632042d5d14b1186b47c051f52241c143f7c514a09cf51edaf523390ccc45ab550aafbfa766609bf6ca6f4f18cf5046f0e	1645962307000000	1646567107000000	1709639107000000	1804247107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xd6300cb0d03365e4fc6745c25426dcfa364bcf7f8e3f1ebb8874838a969080ac3c750c403b5e85a0f39eae75a25d6a3ce375f0125c0fb57d5b7185d9e6a1c6e5	\\x00800003c1d40e9a018b6011ea0558eafa1ea52a2280a7cdde402be462dae51a34c7b390546dbe3b1f5c8828b3bd7c8b23d7dc8a06cbc5cad6c138074f4ef25ddcb0a197833686c995f85d2b51773c5f7b0e78c6ffdbad33d356df6dc3cd8093d7e484e155631dd75a2baf3f727a3cffcb874a7be4edcba721328ccdae3aabe21252419d010001	\\x64d593074e19f5ccbca15666de12ed107a6b089734077f66d8326a6ad4dac2e231ac0ed6af99b5b12e4582fdb3265c5f6eac3213632da58fbc40b708666f0409	1650193807000000	1650798607000000	1713870607000000	1808478607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	87
\\xd880ed5fff546d7ae4e62f659032f7265eead113f6d5184dcb2b08f4ce33d114b5dc16a7817592eb7533742bf4db4aedb1fb55eefb5480073be41a5ad1528a18	\\x00800003abe685d085b2ce3fe060bbd1fa04fd8d6c0201d71d025a53616243488f84506456ea4527762310888407f693fdda0c01cb7855019aec28a13a6bed3d30cae202c2d0178bc4f0c56924a11808bc98f07f5067bbef3e139398fca94b6287df0e4ddb40a85c22cd2f9a59ece3142ce18ffc618a36d352ad907e7c4429dc91774eb7010001	\\x9382e2c9b11d8018eb3add1f7a16e0f1eb987fc499fff9be86f3e9e9d68b5e048ed1725d8143916ae1e81fe335e56fc9558d89c45c8ddc3f41369d19d8361104	1654425307000000	1655030107000000	1718102107000000	1812710107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	88
\\xd9b4671d5e643f6a402911ab567ef4b786e806143cbe5496a2f879196845d0360469ebd9c4396ec7072be420807f9ebaf0ea8e9258bd4d0106e858894133adc6	\\x00800003b88d08f47ed9755d8d3ef2e8c4ccabdc38e3b3643c16a4e23bfa374ddad094f79c8092d29d84877b855895ac9ab18c74067ba933988e8c4addb49f0dfb1d30e079c687763b7fe803826ab53bea031ac6c757c18b097b5326266eb58fb315f42c62d4f51ade038b9dc5187e2f9e3b0546b45c2c6509b69d82ee01a2559dbc7ca5010001	\\x7b1e0faa3409020b111a1d97574bd66a463b94d6c62de02a54fc05b1f358158154c6a5711218ea862cfdab674045d531fd84b50d4fc58afa109302a73da9f005	1641126307000000	1641731107000000	1704803107000000	1799411107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	89
\\xd96475da1a35fab1e411d6bb51a0f4566675a38b883a779fc019ff568064bca7bdb360ae2322ee446407456c82ede1e4a7af1a96f13da5c75ecb10c9c02631ae	\\x00800003c90e7e5ea5b7670b89c8842855f5bd8e3135f247141d96821cbd06233c2737340bee43aa21e4e1b90e2aa1c85e2576c6f7f3f7729ad0f134cdc6cfa5b21ec05fd538c322d807346cba1f11df8ea5c041d3d8545a9cd4d2bdb76aa8af07eb8462ca161cddb64033c7fad98e4f53d32b65befd8a68c40a907bf2f26da7e0808f69010001	\\x26a91e95a20e5d19a880ebf5c254e45a130f0021a24f444805e9b1d70a1968c92a24517d0f8047a03d041ac2bfa73a02b3eabe154b051ebbb069eb4fd3cc7e0c	1660470307000000	1661075107000000	1724147107000000	1818755107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	90
\\xdb88d33bed1fde371ebc9b3f3ecb829e2f79016c5b3acfb97e4bd448b84b37cde44eff31cadb8fa99293b2faef1b7d6c51c12b23c98b0760969d308bba5786a5	\\x00800003bb2ae76c4d56e115439c3a1fe12ac2a2b0e4960e72a2c829cee1a633b5b9b6e3cea71bcd0011403fb8b197e74c0c5a6762deb58f5ca75699f42b06229e8d41afcd79214e2cac05d6a7428c2e9be65a223b1e18405885ec53db25e6cf74b64286d305def6ed9b7ed91abdb09dfbb196f0f614ff613148616ab44b9f2cc769f793010001	\\x589bf2d8892617b4724199e51a94903482db1303f0ab52bf695d7c16e2487dbe02b5c2634c327a04c876489a97ec1a3ba4230253f97da97eb8e8ff912da8790f	1657447807000000	1658052607000000	1721124607000000	1815732607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xddd8d8d3d5ca45dd10a1e70a2a1fa1db0ce360d05536bf8f656b8d02bc147abf465118bd6f3a791bc08b738e94300ce39d64c8a57bb98c39879ca0310ffbc5cf	\\x00800003db7377ecf1df982b6c2d42e183670adc68d41eadba85306f0b976f0d0e272ad5771513069cd5b62286b1e10153e12c1084679e42510f8e1c98c6d5bf7a00ed5b41a730dabd8f46ee988e6c832c22a034a72d1726aae6122b464d298739cd6a9915cf87d9ed0d36ed7151c7b4cc2224833c5eab911bd21ddff61f9d2b2be59903010001	\\xab30fa1184df60a047db5e0943932fad04621bf0d97db7f33735469daf727c7c9cb199d6971c0df2049213f180ddb3ae97ad3c06f81658bda03042cbc2c0a60f	1644148807000000	1644753607000000	1707825607000000	1802433607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xdf78c3c7224a62a963275d70f6d58fb638b3694de02d4c094d5fc373a46423a51f3790beb55f8344e2dc3bf646906aeb64b9e306be9ece011056752cae167f22	\\x008000039b95bbe78b83ebb71de87c8bdb6f07e3d3003a76290335ece5d88802e13be66528be7c4ffe8e97e0b627f726691e53aad68b97d795bfa31cf787403514bdb372f5bbed652cd00c08b71180109a3d249b0c3e42039f795ccbde192e3c450d00b1c9efaa0cc9f675f661a4e964cd75e52ba283b51c5f0c31afdfcca7250f10a181010001	\\x363f42dd956a1b3dcd7fd7e22bcb019d372141c3bb39786785a6e76f7be4e3b97a65aa1bb642800020d31934636eb0d8c64466b1fb3cd28b1022680c4507fd02	1636290307000000	1636895107000000	1699967107000000	1794575107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	93
\\xe1684e68b54bb96431d483ab7469f21cb0cb189c1232dbf27a52e6997967914fc82bada4405add8a0018daa7fd7fd256c2446ac330eb0ea000e955185e026fa1	\\x00800003e1860bc0126c9b57656e97b04f96f965757803017928b7b4eb8d9730d94228b7b58962cf6aa41a6c1215e652898c6af67f44a192183bd7e2db4ca1fa3f3f73f0c448a652a3b56a47a88064fd3d147076de10ef98087a4f73390c56da1a9fe297d35b9217331b65b552541c327e3dc27796fcac44b271042d21c4fbd0fdb82a45010001	\\xcac3537b3c3aacb28352a5c603ddeaa4a2436b8e080de15a3e1e7cf281b93d42512c3dff84f7b9e78e362c7c61dec81e23bedad9cc3bc6c54bb4aea59859f809	1639312807000000	1639917607000000	1702989607000000	1797597607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	94
\\xe190c02f949319e8c4652616cdcd26c25be3f779e431f1b9e604c98bd4ac3a2ce925db4c81d9e27f36d63e14eb1ba1aa36e508ea574fa55f1f3bad6071fa209b	\\x00800003c8e03f54114d0a246b063cfec39ec836e84a7882abc8547bd07f9d42fe11c98015537a514c33cea12d4960d8d5e58a433010a27dc7b8cd1e42b607e48e8ed4517e9f67c30993c38d93256bf5d017da03762502546c60a0b3cdd2ceebb544b6daa3a50749374337875998114773ad6826cdb49b2e27af0baca656ef689c60774b010001	\\x89b692d14564c22d533cee5611a4da9ced326480a166e21a6c2385aaf34b9223f3252d0e9c6030bda2532e8f11486cbade6a3467c47441d8ab15466a3836670f	1636894807000000	1637499607000000	1700571607000000	1795179607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	95
\\xe3cc493cb774461d4696f6bd99bb9218b4f4cd0c8720997eb96751053ddf55f0f8431fa8bd247fd213ee043853a235deefc09dbeaf0b5d130577ad4107b5525b	\\x00800003be1424ab67bcb6980b0829e6d0a4349a39c9c851795180bdf87220e335771d03ec6ba06f1aecda87086900858ed25f3d8ce22630255146c0e242609680cf7237197b8ca96926d8b8fde359d311f5bb27fba9c1b9baf308a19038e596d98ab7883d8bbd7758fa3f4eb7197e90852941d939c8c7ec76ce4e430e80fee0c7cf87ed010001	\\xaf675454f79042b9539c9947320f0d1e40b3001f6da135287cc10afbf746eab9511195a5a6241f4b8ce5acc19d12b2f058e4e560a547f00b4e854bfeb032bc0c	1641126307000000	1641731107000000	1704803107000000	1799411107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	96
\\xe32490f94b12bc720ac2e83a2c96dfc0f07adcc2663d9b4f1be05e2434c0fd5f6d3d9b1947c89aff0d4b746b67d5c0fd2e049d3a8bd3a293d24b7db98cb0d684	\\x00800003bffe7b7321868f81b47dee1fa90aabd7115e6d5f19a6f219e9ab953dadfe0f53047ee0c1eb4a0f1faf5ce1e8cdec1f20bc00c5407de8af1c234a7f3b661ebd05954620a22abf6bb1dde03514c6eaee33715619ab9167a4e6025953ec603295419f51cc8dd2f3ea0d068b1e2370304a23d99feefc0babf91b2aba6a02d62a53ef010001	\\x4608c79cda622c2afa633df33890718be55c218d32dcdd43c8b4af16bef4e2247ab6f1d8de582ccfc44461a6e50d2384eecf2244432e4074cc09e844e5bd370b	1633872307000000	1634477107000000	1697549107000000	1792157107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	97
\\xe9b40212bb3cf8ff9d7efaae2e21e053c864ab5897bfa1c3a8b0024e6faa4d7bb9846b766504b180fe45a861507d527c54ed42a78167503e4fd1124f16249c36	\\x00800003e976fe60e63663b8bc8ad8eaa11c33e2c407abc74cf4f2fecd28dfa45b7cc6de9ea7bc71b4b63e50b821cdf9c2a472302ea62aa1a267962d5f5096a550794013c2823a30ff8d009eff2c1a63f0226a16e1a941a2ca43b37746b68ed70238b536b63ebed904be5627d6327ae05bb73ce2a1eedf0a7aa13978951aec66866a5303010001	\\x3de3cb3d19030463d43abfbea4faece9fcb8a39ad448eca1f26c4472ccbea13aa9ba6eb6f423f923bd1b23b4fd708d2a1a2d8478d2a03580fb31698e5d289b01	1633872307000000	1634477107000000	1697549107000000	1792157107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	98
\\xee1c6a4e9ce0406bbf4b0ae04ed3d16b8363baddf4839ced079882654420a39df2a8f7e1d6d8b5b79cf5e5003000cff255abd85f99dc394c20276aa2f7e18fc8	\\x00800003e5c7328cfb937b90ad8349d8b94b9f1dc0ae914f3a62016f549488f482054b227abedb7e0401fbe85dd512eb9ed7ba6bda1b85caa45b70e3a19d8bf3b10d2a8c13090ada1e617d465c62cbead21e078a5453a4f2130383fdc57bf95b5f3900eb45704680147df4c24f525d4fbee26310ccd5da72e5ab5594497096ac820dbc33010001	\\x3647c6098040dfaeb7a0a4587a1e8e619e43bbacfc71563400cdab46de1d047d3295c885088585bfa5af6959641c1dc396095f39cba2d2f20d2cdd294d031700	1637499307000000	1638104107000000	1701176107000000	1795784107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	99
\\xf0288b8f3c121f4abb69f7b184005c320778eb0fc7cd6788e2d05f148c0e1023d924f81ff061c8600795078952aa6fe15b0fe93b4f663f8d3608168175d405be	\\x00800003a8a29159f6be155f65acc2e2864fe072b631eb78b35df2a826a74f5a587dcdc78f172232b418b0a1f31e4279b17f675f6f72ac4970e2c6b40fe68d12218e8d899eef282d5267b87b59093ce131951beebec96680e0c87684cf565218965898ae8ec86d5cf47aa2124794f9ea5305b741d7ccbb0c54329c39617a0a60e8bf8845010001	\\xf1ca7a1441e4cb2a1854014f222c713c75142c4cd811dd7e884eb5523393f24f584e0e863cccaa25519da017be3fa9b2a137b12711bd257f15e4fced6906c605	1649589307000000	1650194107000000	1713266107000000	1807874107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\xf08c9ffeb4b7c1a9b086c1f6d2adf8d5dee5788244763e8bbab6e00fa3c3f2857c0e67df1349b5c1c33723a6aaf4bc73251f30a4bc17f7b9d984d54b3e8e36b6	\\x00800003bec79ad43c5414169a9b382c74e75ce697b5facb7cceb5846ce0a58861bd41b101e01635f3f07548589296ef3de9e3bc0a53fc13c151d655e71986124ea0fc1a666680c1e4d52d4e5ec2456773f57126cfc26da6933d892be10f3b3052111754134682a8ecef9b2e316d0bcf8a3c2ac8e84c47850e486b02d2cfd7f1856caae3010001	\\xb7ecd66b82eaa0cf0820fe98d0df0b379bafd5b026ab6ee18a0786664c479a19958d821b05fd66a647581596ece2c9bf5d0b92071e0a3a22bfbfcfee53aedd02	1639917307000000	1640522107000000	1703594107000000	1798202107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	101
\\xf2e8469d1ddfbbe2b37dfda3bf0dec3baa14f4f43beb09a287bce5b5bc248ecfa56b994e7ebf4ee9df0e7dc901d0376ba757e7ef4530ec146744554aacac362b	\\x00800003b927063853e5deaedaec0c250ec4d0aa625c1529fabf8a1bfb6539ad8e6144988dff7844874e8985ee4a7ecbeccaf808d5c18db12882db517b0fd2f24bf435cab8f85344c487bc24168fc93fc380398785933a462fd7b00af1d4d785dc12a5c77149f1b9f51f0fdd4451b98a6aa886a9ec0ae815da3d04c72334afb023e28b8b010001	\\x30ce6e299234f239a185cc47f61c4f277f45876cc73eedf25554479354afb38c319879c3e49b4c3f5ad1a812f81175b180b52a5be81b901b5005153d708ed108	1632663307000000	1633268107000000	1696340107000000	1790948107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	102
\\xf46c7f4d17719f422040dfb6b9d10e0c2fdaf09c37a0991a1037623e276448c7f8d614e68293bd7148c33da509ca27aa60ea2add08c0f9d819b435ef21824b72	\\x00800003c45dece3d2954fcd23625e677602f2d4a17c48dd9b47ce2a19dfac3050a0608502c1dcf76cfa84e45abe31541b26849ef6bdfc3e03db5d6047f668c30ac63db3cb81ce613c8ff4605be3dd444050cda193308f3d3bdb662c344cf8452c498c86b6f00ee29ca88a4fb20d10957ef099fded52e1783a3ab51e4c150cb0f654fd55010001	\\x2a7778e828d93d2b621ee4466cf06ea8c76c84d66ca9b570978e07283336e9154e9de94753c98b4844e1b0eda7663195b3234b0a34f7a4c77bc369b0adaa750a	1647775807000000	1648380607000000	1711452607000000	1806060607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	103
\\xf668743fadc90f665ae4a99a6709fba8f20a0d5b9c7c1c1a5d746a96daf8a5760cfbf7e2215e308aa073ea17fced457cf4756389ce6f144ed82cf2d5d9603064	\\x00800003eb89e0eea75b74a95cb8a78c2ec7dd1506e336e0569e170f89bc4d9b777050c967bb87e2ab75ead4299878a5d43302b3cba5812ce76ef3ed5631686b52bdc85810f415b8903b672915f5679eeceedc34927f5f2834c65afebea725366ce2845177dc8a7a37a93d457c312880924fd7bfa033315214a298562e512dd925e91c57010001	\\xa31c5a612faf836874767305786a2bcc525d1d4628cd4d58272685fa26ca1e0be2b98d5faf39e656315d50aa47b9b0f9aea0ec39250e32ba6ae4a2d75235e50a	1632663307000000	1633268107000000	1696340107000000	1790948107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	104
\\xf70c9029646ffd70515200cbb74fad1706915ad2bf3c8d0837bbcf3ec6d2dd780166398d7259fc7d5977a23bda1d6fd9fdb561f5d65b78fe8a7e3c6ba8e300b5	\\x00800003b82430a8f02c4bd17fe049979a004f978424b37ec3526a567832e4c29f01b1bf32fde276549c1ef1f8962c7c6bf82bf2c20dc87df4616bb6ab3ecde11055f2a4225fb871bed6e6f3259b5a62c200642a752231ffb6613a65416bfae3318711ceb4162554649058bcb5dc210b4860802674edf14ddb55a898a4302a8dc58fbcf3010001	\\x8d271379a071b18e2d2bff1cf78fba0b2b51faa8bff8e965d380d0da2db57ea1305a1ea4f1e3ff00ea9b2fd5138d7226842e74f037d7170fa5ebf4fb17466900	1640521807000000	1641126607000000	1704198607000000	1798806607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	105
\\xfab038bf38afde6e445390e16c79884b9e8799cae7ce98719f28d7f6b7aee33449f20db04f69bd72fa8c9c62dfbe2a73da3f7ab4d976684717ca704a45c3ce98	\\x008000039eb77a903e4b1dbdf821005e37162937b600d8c83e3e5722a17b6ea213a45de779cd7f37d528d01a494642581651b3d05c6dd41839672d7190bf12f2427390f22f7aff96a8f1f998be55e3e5bc72598e8b634f81599e23ae84ce3c3905ef92670b86274d88bfb58f071b7c1b60da8b840eef25eca135dbe6def591c13cebcdcb010001	\\xfb52c7d5b118b87ee1b53534a5460417fde29bfb41fa09fab517bdcef87c14b9bf5958482abea6085c7e0c46bd35be77e92c6340de3d7ee61986a88156d31800	1651402807000000	1652007607000000	1715079607000000	1809687607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	106
\\xfc58c276484d48595e50b731bf4f1f9af020daecbb61052b1629f8a8d45d784595f2afdf03b93d486e8f6437830560b1e098ef66b064bb3c3b03afc2f52c5d3a	\\x00800003c47bb48dad2ee355742d11bc779e6eddd421a130ff6bc24312998697a7b466cfaad908cd6ed603048e3b21e838f64e0cea1d4329ae3a3c4e7093ba13e9d7cf0256089f7e62730126f51bbc3763ae333f68cf7f14adaf0edae001915b523834dc8c59bbbf079887eb443e3923bc551270e1d8bfee6d21ed04222ca589e4382741010001	\\x7e43eeb4e418734d4eecd9dfe1ec27cf753aea1be5104bb6502df4586859b85a808cc59b1685d8c1d6670eeb07d35c2dbc97d466173fcc1279c24e0999ba5a0e	1643544307000000	1644149107000000	1707221107000000	1801829107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	107
\\xfef88eaf152fdbc16f1ac7adcb6945de75c8a0b77f603643b44a52bfd57d082487f26dcf765999cfe998ef4254309f6489096bddf53874ca5078ae201a7acd14	\\x00800003d9a9735df307d415f1dc248ad2991ac2fb551f67d161773d268b69ace9a30ef2c95b0c8e3e7369b397c46014fba54e3c869e0e7bd1524cb090077409b1a3067a787105268171dfa007cd2e9266e4b44b60d33158164d0ffe47c85a65f233679bdfc158041c15190fa667db419a55f5dd0c0c16213df95e469c9ecd0057718e41010001	\\xa1c537d0c31d203f672e1fc3ebb29e56d5425644acb24fb4ba090cd8735646e18f0b03ff1641e1e0d6afc0305ef2d3740a766a065587958b811ff837f056140b	1649589307000000	1650194107000000	1713266107000000	1807874107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xfe7ccc9d3723bd300d7be296dac0ad1fac4cb94b30e4ea74b86d611bfe2037015931b4843ca66f028995a56352e7b4e33389ea5f455967cfd84f0be5e3f87263	\\x00800003f24189c93e7ec36cb1ba3ba8b2a5a8d153eee21be26b8220f707051902145c5868946c5db3c7769ba25b2806d51c07354117465c5807a790abb1790b7d941dc082d3e5207c8d8bf746c26df3a3f7b2a30728c7a723c7a65ac818cbae1de32848f1976d229bb71c315d6785ca336f49a601792921f8913a8e5b7d29754821d37b010001	\\x158413ff3eae0c37d69d978beae22b9ca8f01bc7c7b6b2b76ec42d7be64bf0b55ef0e6734c85e3bae9f0c1158ca481c3aca32e728931fd4fafa4b9562f709101	1631454307000000	1632059107000000	1695131107000000	1789739107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	109
\\xff303723c8afb6f250bf9942479213a130284bab14aa419eb223451a237dfbe5778d95f274c5be62db74a0a931c79158f6a44b3ff97155b860c8696ae1da92ff	\\x00800003b6ce0d8bd8c976973ad0d401e6caec753af37c9ef96cc6e97330b55dc21805be3025d500255f156ae7b19a0eb18c32226e65c673b550384872219303a8b36706a52d8a25e8c8e95ad44c589c01030dafa84a94697422174bbbb6b740a19d6521629ab2fb3f58ea4f82def1c24699cc624455fbcad8ed7b1e84f4e2dfc6ce1193010001	\\x97ea87ff72d718ecce94725f686a6997aa5bc6caa451b0d54d4d6cbea0a4bee5c90e26b6c492ab8f00bf722b84a5b1ef74881c2f3779c461a20da92a2a25390a	1657447807000000	1658052607000000	1721124607000000	1815732607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	110
\\x00bddfb7fbe5b1cb35de1dd7e67484bbf5dd7a4bd15ce0da7986700c65ed793fd715ff6ff6b863739e2795fe907faf1970778bca3b9044c2ca276f015b1daff2	\\x00800003bbc233d8e7825c70f84b057666df83d77748791ffe1bdcc1d411a759eb5c47f2ca16f32ab7ec8149b7faa0c096d566523db929ca73923aa9bff8d61936ccb8324f28ef64b7d87dd94a5eb2affa7ed9485a9f3782fd2da9c167df9c1dd7224621adcd32222c9a6e23eaf93e66348aabdcd67b6179620879db8f7948420c548e27010001	\\x229ca224c61e33dea78310095e9c94f4a280827e8782d7729ab4fcdb054ad80aed1e926c379e33e197fae355cfb56ad26f856d96eef4159333c3ff9ed8089205	1651402807000000	1652007607000000	1715079607000000	1809687607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	111
\\x02bd46fa1df54b08441e502cd5c407dd7347741869629fd779dea1a72448018a4a41a105f017c403fa90d4f0195d5c7a9c0a5b029c1e61254a700d9334802969	\\x00800003c12fc739f357c9d1a0ad94e448898ea9a5f47a4d6cd95fce4edb39cbc8e0c514ab07e8256975074be9f5076917f9d038879eb8d7e385058f10398dd33e9be74ed5f7f846c8267a1ed650e14ffaaf7c602edfa3ec6f41596c2aa18ce79caa4f19de4cdbb4a8effeb6d6811296b1a06cd6541f0b10d100ef2f5aa0ff2604763d61010001	\\x604efcdae00794fe48db9c2fd91b6a67be9122001ee65263122aea3437399ea58cf029bd60ea3a5e05ed9a3e76e830b73200253bdc1fa5f19cf1ae91331daa08	1657447807000000	1658052607000000	1721124607000000	1815732607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	112
\\x0419ba4efb4c9cd3c2ec6538ed4e0e5179a42b254afb181236f22754316134bc9587a7531875dbca75f9b77a0bb6ff0a3d5d9d511544962a3d4f52f19b010908	\\x00800003c208b9e054b0f77ec39eeb6a473c4ea6831ae9760196c5f964a6256f6190ff06792ed6fec032d04e7fb516e7117f2f08f40446decf8f9f25a2af93d84fd12fc446af6eca5bb16fea77a9aebcb53e78aafcc9d2d465a662f2e257f345918e0c2061292799074181610fcea63963d579b081030e83518b88c1144e605fd8419495010001	\\xee2700d6424322182bb92b47acbadc9e694a01cf570f166065bdd6428b86d74b1605ed2ca218123748df1673b66f13e6b2856ec6b3ccd70ef7b84b6d19fce40c	1633267807000000	1633872607000000	1696944607000000	1791552607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	113
\\x0475446a8c6ab57cfb8fd032ccc59fbd5873dfc88b54dfa7d55e3ca02eb688bf6b5f4fa2bf7a7b37018e98687f87fda722b1baf847c77dc557658dca57e7dffc	\\x00800003d44e7291f134c49a5945368b3920f3b934437bc8e32f7c9266f18e8d459fd3147a33fbc3895423536bcf44d2822e2776db2eae627ec138894385e9b6a81a9cd1840644154a24386e5b95163dc2c6e035d30e8267be53ada07434dd95a31339b6521f6fb42c4070c5148c06b5afb020f4018d355a648141d0ba5fb2e8fd16ad7b010001	\\x2d72204f8fc4a87b1ccdfd65765485a4f791bd87f50b23046e810dbb3269bb72c19233627231c037e8b608eaa69d34e04f8bb0fa00a2fb3f7bc2a6c1b4020b0a	1648380307000000	1648985107000000	1712057107000000	1806665107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	114
\\x079542fd61c319d4a2dc92c4f7096655cc2a897a0ecad08fd2138526db8cde9be3885556b5bf42728ea9178ad53e811a8bddcb147692365cd1fe76e0f74de251	\\x00800003d53eb40f46fa78c43a4a6f1b1014845ebf694455642420bc9053ab6aa17e9f5139b65e8b76b657622f36dffb8d27aacdf1322b9d82728a9bee8cac7af696950563183bdc7b688da2f82a38f7631d5a005eda2eb30434606c4175364868402c959f33255461f3cb5e4aabb66a53d9332514184e4d03b8f50199fed7573e13de97010001	\\x4f75bd742918745bf8e9bfca07ee634a524f0ab1aef9223fca51a5440085e343b5e2978b49f660fc8cd421aed605c26515344b0853ea3bd01517833e033e920b	1661679307000000	1662284107000000	1725356107000000	1819964107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	115
\\x07a9313b33eda3c9307638c334e422bd1cf0f92ad1cd9c1982409b7cd2f7f77c5ab2d5c63f394a2e8b2b7ba077e289c1bf069d93e1fd27215a1f0682e90fe558	\\x00800003b6660b65ee3d16aa72487570cec1c99760278dc17728ce11fbfaeddedb85917bcc486af72f333c09c677411e5abb9733ac7aaea87e0118e22d639987f19ae13e5228caa1980e6acfaa6639d920b952cf879551ad02b288483be7460b78bda0e21bd1940e9eb6df9fd37883b5ee754b06f4154d569ce49e5f36cd1e369c985359010001	\\xdccea3e2348824fdb024dacff5cfc2a1c8d1b9e2ad267a7392b18f9f3410cb8b9b5a2ab416824eab0b3e763213a2bafd4c4f69af40dc8fb97e4960ff9cdbad0f	1655634307000000	1656239107000000	1719311107000000	1813919107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\x0a4d5aa524475bac354e3445d5eedb7b283098811a9d39e10dfc2bb5af9c2a7678ce066c647a497afed1b9d697403094648a2b9dc8f6267c9fac1de5f5a2f2cb	\\x00800003c33a1054c02817501041f0e7bbabc63c6a81aa37f6e6f4153b5f4aa4593e84cbb64189d6aa2893b02448e8534e6cc1efe323c468b0d574f563074e900167540c7b4ec68e7cf3e76696e2d31d1585a90bfb4c0a8031a252ccb6f73ce27f1f2896cff53373722fe6b7442b5cc0609956747b5985188a323e1e9dd0a07f31f72813010001	\\xcf5d3c522dc495c51cedddc109fc35570a3d3b81f0a75b662c26684fdbc49a4a5cc1b2bf59c82e565f998b6bcee7ca3268b143b781530dcd089117ecb85aae0b	1660470307000000	1661075107000000	1724147107000000	1818755107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	117
\\x0d315f9a4564bdba8ae75c0442349322489f84ebb371edacb7acb196b22c7497fbda325a27c0317ea6a3b81819b6c5448db1ea54f42f030dfb2d2ba9c5a81854	\\x00800003cdb4e9f70bec6738332f1d71b3b015408a2548de79267be9a60e1917868a6c01f9af67fd303cd4653014f6f676a8440f4e648177d6e91d758791005460ddcc23a0159c08255a4c7c3e9c1f039b63afa1ae971550a99e277ad5169343e78a26d52eed40826f662f80ed0977a6ba28d1724e3e70c33846849bd7232a5f35a104a7010001	\\x35da117c76abf68f953d47bb82fbfb9da65d0c797d2816bb7de509992057d03581864da0458499805bba1bdfa76d73352c0880a33a69c3930db7f98d4cc5a605	1631454307000000	1632059107000000	1695131107000000	1789739107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	118
\\x117924ddc7d5da2eb792b7bedaee4be16364991db69e79942e945b430c04105604c160a9bda9e509768b8dcc6adc36896875c3f6790ca63371a48dd9bef77ec8	\\x00800003c4717713e012d8e9eedd70f4204cf7657a9f96e1e708b8f835ac153f5785d8bc51a2542d5f133134ee5e4ecac0c3ee2133da6efaf3b5af5abaf21d4ef1ee34a0ae7e90a7fc0a49b1010b2d5b4124b0641898f4d7a2a0b186dec0bec77a92c478e6a0a94ff1d49c60acb8a6d1d683892c6343c4e115a0df6602fef736eadfdff1010001	\\x92343f474660043cc1bc0b1fbeb2c9232f062003e9b3fbd4ddb65e4d94635b65d9fdecbac1f1071859665f296a8741a7e66577ad17c871c210a3b25e9403530d	1644753307000000	1645358107000000	1708430107000000	1803038107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	119
\\x16453a92a277edba0b86fc0bae6658d6d7f4132a71549c8e9d33b52ad090e67cdee1661c30742c5f110908569be5a7557740d23e83aafb4da1c4bd520a24bbb0	\\x00800003b0b5cadf44d50e7fe9d76e897f935d4021f6ba9eedca07e80d52eb4cab358b10c21340fa2e56677d1e89fd0a09dedea38213c2523231d3d09fcd0120472ce236cb9ff600040d76be9e68241076bc154f37ff4261517bddfdea0b8069b52e680faf37d88be66cf43434220ac3323a4feaeb3c99db4910a01b680dafd8c483c343010001	\\x410ebe0c4e14727b14a4c38f557fd069b93c0a72f38352bdf5404421e2ed0f6c20920325d30691908ab117e3e0c8b37c5a76c4cfdbb024d6432f043d76a90903	1656238807000000	1656843607000000	1719915607000000	1814523607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	120
\\x1a8da117d5027c7fedf5f29576b09bd7aac072b51e7b0ecb1b7c68b1202408078c9dcf466da99c5733124a85f6ae68d3e46d0afa38c23064f6569f4286187680	\\x00800003a2c8559af03ea0cc3007048cfaab465a0f157fe28138bb37ab0ef965233e6fb651d539c80fb7ce107b987c8f384d7f1337227cd3ea1e79dcc1a24e33565fc4faab0757e8088795a51f9960a5554637c783bc3799c3a00ee15d1a090a07e93692894fb1d25071fd7ce34c0c61d3c4268d6ae9f5216c8bafca7c72e5f5d9987f91010001	\\xa7c76f5a43a93a1f80d0977c9041924d424ae4adef44252ea92b2def8394556bc53da507c63710098ca3c4dccd481fe559057a35e53d4c089f10927d0dba8e03	1648380307000000	1648985107000000	1712057107000000	1806665107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	121
\\x1ab910d7b49c9708a91f936485c9515fee8fac2319c795fa636f3ef892c483fab91222beecdd2633d9dedd6a5725a1666d9da15c21c2a2094e628294dc885a89	\\x00800003b41bd8a050e35fb535dc1878a1e95b3ac2e0cf27619037d63cc90f68d619047f8f96e8a18ad9b2d2800da93ab0d4d83435092329e3abbfd6a91c034fc7344cfbdb7fe382e17e1b5055b4aa6db461df46684c4d2e6a7990a22e7a8d0b2817dd9168e0d85c621f7045785fad2e6120525b7720677493b39b88de60810125999cdf010001	\\x3b8b5ed967be1a68b25d47bf0262a8c15d268d248d9ae00700413db86abdd3c9942bbec805d71f6e30716abb886e795bd56841cf3582738350339fd7fafb6803	1657447807000000	1658052607000000	1721124607000000	1815732607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	122
\\x1b512f80ded764ec387d78d3a3656bd7b3942ea83bb17fd3622be022ccebeee5e5d4ea703fe5be9005250d3944340a0fc7a882ee1b6f696493684ae35126a63f	\\x00800003cbd1fafe87cd79de28782683b89c53232d17ab1d97503c7851c9b37ff42dd4ad2e6f24764f5a88ee844e93424b36dfa899f39e7419b1126340e912d632f3f15cdbdbe550b7ad5350a13ab4c4ac6c50f0fedb04959eba536b7f1de1ef51bfb390b1fcfb3eb40b417475663a2a08be60381d7891371d074d1e52510e20e781030b010001	\\x73319ed338b311885d4c740869978d2feacdb49cc1875bf86cc653f8d6583a11174777a90678c824210bdc03b42ac24f0794116e53581646b4d5e1acd0033904	1639312807000000	1639917607000000	1702989607000000	1797597607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	123
\\x24f17fb616b865e171f6d677cb652fdffc59778af0572d897feba38af776d6bbcce7fb0f6ce07f15a27187ec2022d8a6cc0d603959ca0d844791f3d7b6cf9274	\\x00800003c7df1d506c95725ac1e7e0ec7233ed99133e0b964fac01d6ac2b924ef537b399f5e1c090a342c663a71ccd0c4bf493c70afc7a950b4f69b2ad12d61f069c8a4809873246453359a5b2e74bffa69455563ddbd0bebf26615e3d2d226bcd80b6cf6fec30d0dbef373ce02e87b138e687d2a11728479c0bc3d69c320683b5d02dc1010001	\\x86e2902f8ca7a19419fd0ea235580a30270084fa5a5fee0734d303574c96fab499f40c14a7e17f91355aac7f45fa679621a9163ee1b4bdd0e0841a035493e600	1655634307000000	1656239107000000	1719311107000000	1813919107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	124
\\x269154fc7afa3b08c055692797ad9515bbe933a365db72186d392f8c0cef7307f67c57806d7196df94dbdaf6a88c1b1417dec06ebb2aabde83087f2a6ee2ae85	\\x00800003c5229c52b27b929bb7ea770d28f5d0b3e116385c3ac77ca6c6b9bce6854c73528ab7a50502728010ce03424dd12ab2ac1e1a2014d3c990964328af734b619e9c802ee2e4d21c6cd5856b515bb1b61182dfb173eba14f837e252e2e54902173e654f95c03c1b54fa0be48a3881f758c27eab34d5990a81870fb9c7c9709747b51010001	\\xbae9c3bc9d1b6198094a9af1dcf04456066c102a637cccdbb90ee49ee55d3eb87c491e5eb3cbf903e6579453e424c7f1e3c6a370855c378521b5393844c4950c	1650798307000000	1651403107000000	1714475107000000	1809083107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	125
\\x26a1804ed7d8aae43eaaf4eb1d121ab013f27b334a3031257e310030ef0acf427d93a1da7d24540538744f62c4de898ef98129033af635c6a0bbc6281388147e	\\x00800003d27caadc84925747b1ccdffba2a1f13c87daeeae5fc43f3ab0c1e7aa673a2df94a283b3c325e93c8d13a70c24316f18935b63e988f5df7d4d402961dc95401ac76cd47a5e0e4de6822e6a004ab96d557aaff94cf8b385b004e6a3d60a88b4deb5674ae1a16843af876ba3dd6a05c02e28bed1ea40b31f091fa6890963471213b010001	\\x2c5e422cc089879d78cea8ee05b0bd15a1658920fa10d536407f39711eea607c4ee36963a8acdf8a67ef9260fcf5f5081cb9f7c0480f0a74ee4ab13471380803	1638708307000000	1639313107000000	1702385107000000	1796993107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	126
\\x2875c4d4c11b3a3c2d53a0e1f8740fc13082786b46051108641f062ef74d2cdb1ad9180333a8a12b99ef4c7de885952346fdffe95d791f0fd46653f32fd82f92	\\x0080000391b1e831a17f5c8f3ec47d4a71278972ea159ae8ed27e0fcd210e2c131161c32a38ef64e1247b7c1b15270405c7e3261774d9233ac7a1e5eec4fb5485c320cc5439160a728a40b06faf6c5fd2c98712edd7a9397b02fa33ad3ed32fe6efd4a1134e92bfd24e624400b69a575f80a6e482be28650f800911c37e2aa35c813f6b9010001	\\x3bc9046ff07094a7b4f5791da3b0d17058d7cff99e9e0c5eaab840d8269841620a3000190b2aec351f8aaf7e398a05c6d16d73311a26943d1406798bf9abf606	1642939807000000	1643544607000000	1706616607000000	1801224607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	127
\\x2af5538dcb50e3fb7d13d00bec6c1e364fab00bd65ff171b73fbf7f8be136913954142fcf59ee41582cfd5d1ca79a3b7db55c8a233d1416c147951b08392558a	\\x00800003abd993c692ef56d81dc22c6d9755ccc02c8f9adf2a59825406cc982dd7f978a947fa8c287a84a2a0cb0d56127f178557314e890a22b2ce5b41812dd46f15dee1ad06388642bbffb7428e96ca7da254c9d4b0028110fee0c72a53dfbe3abfbaf6d0a73e2c30e6a413258642604b2df7e85a1d6669ea8455399c9b71fdf9f020b5010001	\\xf41b1d27565c124dc7121e0ee19e16fd625c955ad069a936573223ebe6a39897b4e2b77d59e72aabd9a56031f2c0428c0c3d462d74236790fbf1476249dcc40d	1641730807000000	1642335607000000	1705407607000000	1800015607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	128
\\x2b013a87c20e8ba3e1647f51211d70c465f767920636371285bfc5b86f3d0a8ceb048d77b0cd7347c0e9d92286a2407661cf68569a39cb8a73d6bcf5281e49f4	\\x00800003ae35758e67b45af090bd611280c9a4c736b5bd97af28fbeaf660b71c58143689b2262d1575fc46217c70ec8c083e3158f7a7e6372b9307d48bc21ed3abe30bd65119576603ff551e5aeb0eea8b102a03691b955fa87ca660eb4e55b22659f61330fe237fdea819ff267103af5d00b528038f0b789b769784a657f1b4ce43f597010001	\\xfaba817502db4dd92058abf9f713235871ba791cfc5b5fb87fc7e0dae4cdf4ee2637ffac263f7cc8cda9edbc8ad1124931c7a9c94dbbd65230db11b5d1ae5204	1642335307000000	1642940107000000	1706012107000000	1800620107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x2f25cfabd6705a4bf36b7a8812d62790ae226e1eed4638fc9ce6848fb50cd38d8bf25b1eef6f03b2d237486244e9873ea401ced904f5c5cedc865ac18ad3fce9	\\x00800003dd488c9de89edcfe8c2147497a118aec4119f01223f0c185ffd37dd802899805398ad4f38426a1f2323b5e2ace41b10e006317ae8e6ecf2bba9dbebb8750077bc7a8a4c3792127cb686e48066a7fd3b72808ebbcfdc255983b51e96e6d7dd85168bf13faa5cf7ac878690df6134704ea7aff475fba75a0102ed1bc623494ea4b010001	\\xb30f2cbea8296461a49633cd6aaa2610767c0956a4bbb76fe7225c6ee48090bfa3e60d6a9a01ce3bb047522bd7c344076f56640f0c4e73a18054848a7521320b	1635685807000000	1636290607000000	1699362607000000	1793970607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	130
\\x301587669eeda6394ab0c82948d8b976469b6ad0b5e950b2d2c71214ef794b68f0af47cdd554debd76a110f78123ee5fe16c38f66303140e4177beb10121a8a3	\\x00800003b6b97fc060b95bb933a29e051eff2420387eb586fcfe1413309d8f376a79c5b4c3f34569225a5b2e099e368a748db33cf6640279979ac0d93ace307bc9b0092540d4593bda1ed3abf947b81ea1f1a364f8c3572bd2da4d1ecc3bbbac2cce63f945b5345b71c7e9b47e46ced413a807e07339f94f9fcf72a59f59250040f5eb81010001	\\x9a82b0e285c235b949bd62715bea83e5447c34d1ebd9e0769ee6e6676d98cec63c470e9455b5ada4465bec0b23499dd3ab2831e143dccb0fd3081879f183710a	1650798307000000	1651403107000000	1714475107000000	1809083107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	131
\\x31f9e18154b60dc81dfea7dd41836da55e78d1d23162c2323aefd5fcd4a776c4febb4e0bfe7b2fe65a59cf1e98c93fbc907a0c2fd463d235af88b8c38b468b9c	\\x00800003d070f7671d454346f32ba0e3da28ac93ce1d4c011a29d7dbf9e20091b07a6c59d9d9e5483f3cebedc9b6c3bbe05daecf00125c171b0620bbf06e34152bc13ad50156423644c8b43ff8c87dd7e663337eb4bbe16029d8e48cc6ae0225549dae6a0d1b14701a6241cd33f83f7034a8671edf63cbe8adc8c377b4c51f156d98a417010001	\\xee679ee1bd22748a92d51610a23f522e24a49a15bde1322dce6f48a9fd24c1f934e5be98f38839507c5e773112ca9c481033d9de0f7c3d8f0d8adac472f88909	1632663307000000	1633268107000000	1696340107000000	1790948107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	132
\\x3501fec5127ee497d8e25f0247d8ae98140533a694479e492a952a93a585bf94d11643abcba6240b798bbefc267842cc7b6f5084e57d3dc37136d36d3b992700	\\x00800003fe0f5ef8a7bca83d6b1787c03df3c8d5c1ca8a2b593677e54f0d4db06b4c722dcad0f9e9f6e9279f5b01624e72e2e00657a22593a1679780398cea75227487aedd9ddc5387fafd56f475cbb3400f370a00ad083846a611050f106e5f52c91f61291d82b355fd54f5d2dcab5bb530c99bfd56e8a7c6e645be00f0f6f9e10564dd010001	\\x97d9971ce0c4590fafeab565dbec85de20d66d99de66e7d2caf10ac5446dd5a0f018a923cf6ec00ca935a02e3ec4f394ff5ac2b7a0c8bf8d89a6ab10d943b206	1639917307000000	1640522107000000	1703594107000000	1798202107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	133
\\x37ad17b9afce7d8525c3bb2faa4228ea1cdf8629974a15d3d4673c9a6d8f666dfff0a4d693c663dbd3dd30fb2b4c40413dce4ab4976f57d0a6cf7d4af9c1b6f5	\\x00800003d750ca63286192eb819aa3ae1e6edffcbf0512047f9ff3b99635699cdb3d438a787e7a3fcd5341ceae39652afab3260473ef59643a36f942676849ff91feabaa1661213732859b2686252721c8825ebc4d095134f6b36a01b9003dd90e77e3e2c1c19983d0e9dfe3d667b233ad6efa9bb8d29fef6d702ecb75c92de88d551f63010001	\\x08e646b99b7ebc06e07691cc4c9fc619afc5dd7b997ae74817b10a86cf38fd444b95d71e8fc40c8d3541ea1557c5ce8d4e3634d65deaa2b71087ee32e00edb06	1647775807000000	1648380607000000	1711452607000000	1806060607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	134
\\x3b29bf59ac6c0b94acd21abedb4add7d81dcc41340cfa5b84ea6ea6c5914214d95f8052da745c6611ee81056dd6b648b02f1eab1cf63625ae0a2c4e8b5a9b181	\\x00800003b38f50334e5ac8d4cbcb00409e27d5e713a079b92407a31daa37254ab07a031387529fd58b9f2efac120053c5c6cdba276cdb910f0fab81acd34962b980bb3b1796e03bec42604a25bfc5680b9a9d6606bbc7140a5d9262716ff1bf267fde6ac6332a4a8a2f6212221af1b4143e46a85831d0906edcc34fea0236215cdda1b0d010001	\\x94b10fb6933d611666cc722e9b34c1f892939acdd1fcbeef048e82ddff4222b0b7d869343bab48b36f73e82cf61e8fe825e38d6ee0eb1a9320933f27295cf708	1659865807000000	1660470607000000	1723542607000000	1818150607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x4129360b46ce9da97df46813d7e8abede08e6a18f8e34362f8c5953ec21412d7ca61c5f54676b3a6fe60d4a868f69a6808a57888a8df9610388822cfdad021d3	\\x00800003aa204e5e89d8550a117370f74560bae5551880ce0dd47f8322833f206597839133f37c61c559362558545960b9d021650479564664ab1c0a902dbb54639d173b0b1da60d43a259276ab9f9d7efbf3799252a54667b3b2495c19f1be83b0556ccb074d00bff3bbbcde6a23fc7bbd8464f90f1d0ef3f88d716273668699d009287010001	\\xc295a07ebed2d761a07cf3651a4bded2a04d60eb9673ba9fd63a63a37f2c3932296602acc2d54e3df8921d8fb230b68a08acc1c171e185608452defac410e90b	1645962307000000	1646567107000000	1709639107000000	1804247107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	136
\\x4abd9a950028b71b9d98fa925904d347d2673abd72c88a39b18487a8f5471fb1d1ed37559c21ffeff79a74602e208348c617e4d2f6480f9ef4edd26e54fe05bc	\\x00800003dfa538703a49e0af2f05a3de5cf5b182023bc15fc6fd84de285465545f912681d31ba22caf31b23263f47db74bada10c95e143d8d37504d827c9dbc6dae09b55163653f4b183ca0b00df5286adcbf0affa7ef25ad73985609eae8e2883f370aef01b2a52016b3576356a41eeccbb355b0a98f930743780e49a212bb87cea0a55010001	\\xf0b2de3341d40c4eab2abf92c72a7550b67091bf1833071df9a689af148918f5410233f50dc44b2b6326e8d6d2c08592d711fada0bc655c08ba394c0c5d2940b	1661074807000000	1661679607000000	1724751607000000	1819359607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	137
\\x4aed71b3a84fd1485ecc8bb6a95127b608b10451c4af7a2566f3019fa149575ada3173abb5940b51bebdc8ed39563819fd43a56da2c95ab150f878fe09a7ce7a	\\x00800003f17b98a717f2b44baa7af15500fc1120ea083fc5506d579f60d46cddeb206d8c74a455b5c04ec00a6f3ce1e3f9a94907991b4be02922dc549ff88506179012b521f89a7614e9634fa4e425d2a3f861e40b21f0bfeefb114569cfd582386326b907d64d26bfbedaa742224fa73e07c8301dae52fae6a4487cc9828ca3dcc9969f010001	\\xcb720616d6a41194d7bdc6a9353e12324ae1694473ee2e66c25cf959486a027ed106fcc2b7501a49451f0e77616611286b6f6b92ad9b94f29d5bb45bc7d60904	1635685807000000	1636290607000000	1699362607000000	1793970607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x4bbdc353c0ac4ee2aec2300aba3cb7edee7013dfadaf2e1447162a8403bd50e519f204379d9e4c4a36d65f8c2691560a4c35e7ce9190ff706093b188426d5b88	\\x00800003e35460d68aaf7eac68bfd2a71780705999531046629957be0cfeb4aae9c449c6cbc0fca9db43c334ed3d19721902ff613f041818d39e3141898100d62fbccc099370cdd2283fd1489652d12a96ff7689788d774e387c38025a1e5d4a66b010123ac580194a80273fa8522297be498f774bd6f05a495b439089f63c7fa6cac455010001	\\x1e5d088b144b7b2a5a1e704708dac1c8736e5be56c0351fea93ae52dec98c9e358a59ff9b633c2ebf39196a4cd8413cab863d6cf33c28177590cc632986a9200	1641730807000000	1642335607000000	1705407607000000	1800015607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	139
\\x4be96f0b68326eb7922e21369a273674780174ed8296efb72c84531058e3a184ae204b0c09ea6630e001511183b0895227ad3f50345a583f4323287741df924a	\\x00800003d30693672cb92ad444107a49157c9fbb031f24b87d13fd82ae720db9bd701c4a5d4024c7857e2794c840c429b5328b07833e7b2b5ca07f9ab8cc42d0dbf4dfb51e8ecea848d89615e81076b04b45562d4691b40843d7ff8651feb166bc7140733be10466b1456f98e2c244df81ede3970331a0689db9535e36c458e4d6985c09010001	\\x6e39324cbe77699547033f5320fcfd7e31abd8000c96d323b45301c64a3e56328ea29621d5db5f84693cfaf2c26f262d02627b34a35b0d72cb003ca5c7be8709	1661679307000000	1662284107000000	1725356107000000	1819964107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x4b05d3d2881108089f20623af2d87a1c4f90c451f922b8539cf86cae2a237cfb4ed674c4286d5363c2ebe6fa1ac6b18d42ea333b13d7f9c0ffb86491d6498a08	\\x00800003de640c1f7894a7835a356524222ca9f915218a97bf306dc990b360f91668c68767aa1fc3264d0ad0cf771e807ccc5c353d2033149348bf6ca1ff0b50ea67e6cd80f6c976d9f397ce644b33c67aba2afe430ba3d5d9125097fef61fe13b5b1feeaaa2a1d7d22c37317bb29412235172867766b4f2277c36bc1f6008e63bf5067f010001	\\xfb7b43d472004165b21a125b995e668bc1c94fdf3d3ce9bdeabafc9e0ff9536e22d58274875d4edc15e1eddd773e995d4477a9d3cc5b4f5e00a6d18473893b02	1658656807000000	1659261607000000	1722333607000000	1816941607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	141
\\x4bb9f4be2e9d78a3b716ed074bf13b9658bc520e00296aa5b2046574b77c6b8216571e4235ed543e6d859f5ddd420cc54a516cac9c451627fdfb5fb7dc8f0bb5	\\x00800003c08058165cfc67482049c802bcdd2694f0b88b8afa0b0d630c9c2a96662fcc58f0c92decce1827dd8854ca0ec9ea7ee318f5282568a738b8304b1272c4e09e0f8c23c578a8cc616382ec3b68541e0c308e1dedd5f3b3157bc5a03e749a0e63ccadb0f513c6f4384d3dc775d12e0f8763dcb72432a3434d960669e43e76aad833010001	\\xd9ef9e180dc7c568213f14b99f011440351f84d77ed640e318a91707d51fe633318175cf29b4fa51d0c4361ea3e7f87d8152e682aa81c0bc5660c16f2312d106	1656843307000000	1657448107000000	1720520107000000	1815128107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	142
\\x4bf19f012d61606d0de8180c12be73aa080128a163d74c9ab810f0e61eecf582e6c644b1e9f268c53942f7b4ea28d1cd968c1ce6c46677fcd04e0e0613e55dc2	\\x00800003bb9210cb0d900b19c48f4a53b54b526865e32d48ec4e42cb72f443cc834fb556a7206645b8863e8b56291a8b6cc6023f835f215eb7d8466802448ec0a7972e8674f48d93362717d49e10b6cca4c0fcc1a00543c88f81a3797c95c634e7ce1f002740e4fb8ec38f87adb6b8ce7600a8c44e15634af52b152bd91fbab618b77e89010001	\\x1cd627d34c0bb9d78257332bcb1e8c5e54f570501cae4246a02b43fa167d3950ab0debbea910864955ca058ec4b13afac164c8163982a1d61c97e0737a685c02	1650798307000000	1651403107000000	1714475107000000	1809083107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x4c65f267b54e44d1f222cf54a671106d8a9b553c0fc0af6c15cd349ed819971b3c571e146fbf7ee225ae9a3c476b42c718bf72b70c119a4bc2da3a5cbc3cbbde	\\x00800003b3fc38f1edc72756fe32636fee113b8fb147bf1ffb9bb7032ba6094978b84cc4b27d27d0807ad9413252e7c2171f51caffac8592be6ce9e4534564d0a57b200d1639dfaabf461e48847173090673b604a6d299441acc92bfcb303e1fe8f15f8b636cedf41ebaff41ef67201b73fc820f37464f506cab6a6fc811a1e77b34e44b010001	\\x785486285d01e79109f9c8ff456298c190d7ae334db6c2c4282c6fc4c279ee1e65752fcc2c2badf29f95881a5473b8a9ffd4f79f857cd2fdc09a2b5826926b04	1661074807000000	1661679607000000	1724751607000000	1819359607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	144
\\x4d35fdad67d01f76f86541e617c58e442e5f7c1a013e172c747989a900b261b57f7c3fafa96ce92e5a83edd0aebb5f4407402c3c6f6646b505465b0c38c62f51	\\x00800003be754894559cf68f4c501db91cad7af6acdd75c91d7f3f11e4e0c2162c786e12a05362ba315bbcc977056b3bd300d7b73d5907f62f2843eb85c1efcb93d84b148c2f07d45cad77b5e6465e800b6c37f513a6a865d17330ea67ad6ee2bd7eafdb8021470d60ad23d0770a0948b099b9a971918cefbafecca0b127fa5d8550c465010001	\\x8da19f26c36b122f791861e4e8ccc831a10a0615920014774cd8dd2540c5714ba17cbbfda42202dcc90e12b4de99787a86e389eaa139f664f529fbe6debcc806	1643544307000000	1644149107000000	1707221107000000	1801829107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	145
\\x4f5d320367cd5ab2059d84fc80bf65b9855eed8391d237edbbb0a1f2ad0c3fd4f9752e6c6db3789d6971abab838c3c59e1b5fc3eaba8ca8f35d1611d17042547	\\x00800003bff06bfd27bbd713f8e00d3658694f1e85c1557df17ca61b40e7be2143b183600d6b50978e77a2ed0b8cf61ae5d730c201257977bd73818f6117e3a8dadc13567cbf93e6118e78f823c2f6df6718a382ae246dd823ec28acf791b9632a1bea4b51c54e3f532fd5c5bdc787ccda68ba06791e35abe70a83f0e69a3790f1ff1d1f010001	\\xede24d3a4845547f01a3c5746d3b858362f46124c264eca3e6984d0884de550ca56dc318fd4ac87c5544400f6ad535614da5833d468557caa65c9bc11db3e80a	1652611807000000	1653216607000000	1716288607000000	1810896607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	146
\\x53ad0867462efa5c38248c93e31460e3d7d9a9645787b36d4d203993ea4d281f3d693f92dc8f8c2239dbc28143aff7dc2919292642eb28ed6a34181deee97c0e	\\x00800003d76f59d86095fc0bd2a4d78270f4b786a9363eea38cf67a61b918111eef9afad2befbc2d5ab7e7c46cb2e4d781d447f424c8f154a5d747fbc17a6d7e380efa1836da9c3b4e108bbe248863c0bc7fd40b9b8b4e94f790fe631141d032a00185e75e247cff2ee99078b3497fb8c27368aa1c8bf03d55c55d02eddb9158b73a01d3010001	\\xa3709e789b79fe6d41eeaaccdb85faae105af39831fd17233a51f9eaa2483f0eb68e844d618b26168302a78efa88dae6cf97963dc98bf8ad8e7e3c723e44bf06	1645962307000000	1646567107000000	1709639107000000	1804247107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x54a9289e6e2a4f9b3ee54706749ad9c7b87eee5ab9452903c08fbcbb5bafb58fce10d441f1e086e92082a09de9b077ffd843f23c6afe6f20d27dd78e075cb203	\\x00800003c4504f0538c1374982b7d543c401c6bb9466508ad1acd5688fa3d29d344a802047bfaad0401b9359267e7af860de9b01c31e4281257bd05f193ba28f28aafb86b8b80493ffd404367136d1df858fd5a7cfe4f33bd254961df44154649aad1b516be78a2ddc654d74109595384c48b66e19e01cc59c6ebf06d0259e79dea73bbf010001	\\xe07224d22c4141bf6757bc6ed493d1a144636b5cdba188c4a9ab4bc633d1eeff5e0442c8ecc442509ff8b20597423adba7e2d2cdf4ff760f67bf652813066f0b	1647775807000000	1648380607000000	1711452607000000	1806060607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	148
\\x58edeecdb2086d5b6505b12025286d5cff4aff32ba05e2bde5a515677687573d121655ed89299f2c14d508ebc5678bf9bf42f39780c1ca3e5d64401a17d710c5	\\x00800003b266b2c33e5dc206445ab9e5cc9d977d97020d18fb149323f3a9686f52689e8930c7a41ddb019712a5ecf51050234314f426568e5fcdebf11c0db89b4fb8e12629f31ed09882a0f08b16ec60118cc8a519315379d5aa84fdc20fcb052724978b36492f1160c2509111ec51eadea07ee1f46ebd059a041ef20cb4a0e5a21e7e6d010001	\\x01da7ecb4ef08909a75d9c7abe6f342d1b8d7daf5d5bf207dfbade7a4b4a54a82fa7bac504460655938f2db3aac1e896ef419d53b0638680227ba84ffb2a5b0b	1653216307000000	1653821107000000	1716893107000000	1811501107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x5f013a084e7b504461814d14f8157fd7c6f8c20d26059bc74ebbc6872c755b6b47c5ff4f3e9009272c06e6c4e9822800039700e11eb80b2ad8aace60ec398c73	\\x00800003da7ef70f16c67dc03b2ae5b55eb350fb30274d5e2c92b8e474ab1d8bf6e44dfa6872f98536b2fa1abf621ca51e2b6c061a37daf7d436836c8135d0586d0142dfbbdb58d440100f4a68773244f78a7e3d5465f06450f83c1015292fc75c628a7ed1415c83ce5071875bed6b2ddbb9c153c994d63d3c4c00a296fcb068f4f6c96d010001	\\x7f4036e121df1f858be10b63746a3501837da70b14b6739e6efdf45d62e210d448d3a09070bcb26172a6b70675161e964ca5f0342ca7525fbec8c9eb7324ef09	1648380307000000	1648985107000000	1712057107000000	1806665107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	150
\\x6239ba67c4bee74a9ac514631fd108580de9e9b6daa8edd7176551aec46534529cbf8501f2110135933a7beec891f9b32e069967b73ac70dc60d8c0be69c8474	\\x00800003eb8569a08471af9470d73b5cd2c61333c6b662fd9cebda8c8d816c99cde5330600b33f2a30a36dd559251a5e5106ab45299cf67c7b9e30c2654d4119604a0c4687f64a39e6a0a74ee3a1dbc3d97ca970f89596dc0a10099afc1bdda5ade2b0ddbdf22af91575f500827bb14ffd1523b69876aee3559bdcf62d7ce08c6badad43010001	\\x0920d5ba7d7524b01976b7dfdf004d74269ebd35a7bdc549ac572ef19b05774d61be988eccb547c93675476eb0128927171da0af7c1001ce24eca9a0dfeec104	1639917307000000	1640522107000000	1703594107000000	1798202107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x62310c924dd8528747d0ad914703263fde7e5872d8811fcf13e21069de81c49eaa507e5f542ff80c9a8f677244958190936aca91bfffc7a104a14fe8e44fd529	\\x00800003d9db5a45ab656c067a2a36b7c7a7ca50dab151a49a74832f55529c2e4551c5780a7f5b691988edd8cd30054290457a6cc4fdbc76520673d1d2c6d5297c9a4447ffeb9e8eaafce740fe83588f5b217f10353c933b52e53782e3907bcd98f46568c93e2a89ebb140885183c22bcf839d2b6226a61c83d992bcfb137e440b4a7177010001	\\x2af04d566648345c59be599c364824cb2a4d86b678f6c382d9063bc5e2e854ab5a852202bd024c51719db588741f258c83ee61ed945fec0b56babaa4a4702701	1638103807000000	1638708607000000	1701780607000000	1796388607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x65b1830b7f7c588d605ee1053947d6d576fb8523cb8d5cff74b2738c0f4b88aa035e549792f5ac1aa1a770cdd5c7b2dcc89db2291a4cd6aff39e13a098a53032	\\x00800003c9602a0e938dbd957eab57d9581f511f91042bdcb36b986a6fc08c127568e28001d5e9128b10ca335a690a3759f767f35d6fac0222f920d0af786b210756bc043311c44369b959cc468ce21a64020e7779614441aa546b558b4248a96212c0cd4bb42c6e6af1cfd1d096f31109621d307e1aa3e139f04485cf201ebaedcf92dd010001	\\x9404c73bf6fe4a707168be329007bd625b5aa00bbf0fd0fb25c22ddcf545bc91a289748f968586bad7ace908391820188aa3533074e43c474f38342fd6d54107	1633267807000000	1633872607000000	1696944607000000	1791552607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	153
\\x6dd11aa4676ff67568af1f7ac2f599dd479bf87ae9bef5a824ac4a008c687019b73ddc89560eb7eb62d268b41f5608ebd54a16fcc9cca14c400721ee743f9384	\\x00800003ce3a01245155fda5e4425fb392d3a8fdfdd5099f99116af22a28ee4fe1eff99c877e3f03f0c454598fa131062b38027aaf8f604865aa7e9155fd7196f4065b9a35798be89e86beea8da18855232960f65f217522ea88b59ad94c884280a54e6be5df2bb0fa0ae100e1752c2f0905d23c471bedfd3a42486cbab55786e050b319010001	\\xdd992b8c724e0e93d63f4e3a3328139fc4c358b1ee17f93b07738d804a067dae16fe69e63476779854cd185b759b8551edcfa153ddf3544f62eb221b4e1f0b0e	1651402807000000	1652007607000000	1715079607000000	1809687607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	154
\\x6e311f8f606d77ef71995fdcd8b4d44b23743fd5966a2cb6616c79b3eda273facd235a699ca2e520eecb88a47fc97cdd6d846eb75e44ca113bc8a195d1d5d73a	\\x00800003ad0d8c1e794ae93cbebde92de3eac6956bf526d3f79c0fe833b4ec5079a3e2c300ec5f3435770a4301f41885beca956d07fdab8ca6a19500620045ab2e5d28393a4806b2538ca52a94f83c2f2da55435dd074d92d9e0158632be41e4ce96b215d3f0ae9eaeddf08e4576fbc6ed8cdfb9e67581ae6c9432aaf74e65562e955ba1010001	\\x12f038251fb9fd3a2fe37db985902c758c0acf47ee50d96e4bb260ef65d90bb436225edd6fad1bb1ff9f472ef5ed6f4dabe1c55ae4511a710b5b99ed26ad8909	1644753307000000	1645358107000000	1708430107000000	1803038107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	155
\\x703d226943e9769ee6fb00e1972295b4d3f633290f3aaa1cd69f44185c8b87d13edbf208ea3383dd1498df985abf2606b1ebab874434f6addfc43b8506ca7d5d	\\x00800003c09d33300e403cfd3a0f7671f6bdcb179ebb61df3b3a95218f85e900bae7cc6ea840af9366f47e8273c2126c83d79dc5ee20c5589e5bb48d2ab3dd33055da9b65044a7a0365cd41970ea8020406dc74274e1b4a45fc60aaa6b58c4641501d629aa3bd1677d19cc6613570c880cb63e2a46ac40388baf6242f2fe2e6d3b042147010001	\\x8deb519297cb518d815513fd50a3e4812ddfff19291991dc3b93d2a29e152012d20aede7cd4577d74d51d10055544881b3fb8d8cfdc04218cbeef9bd63bba20a	1652007307000000	1652612107000000	1715684107000000	1810292107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	156
\\x71bd6ec71fca187dbff0b3f7351d0b4e974d3da0cdf2ef9ea165720e8f250e53935cb619817b7136f9bbd346da6c445498889aea0efb9bf4236b109d77d91175	\\x00800003b7ca0f6c5611f089fcbdd0c0306258fa5064cee0a43c9210aad52b6b56654072f56c9509ae209ea29182f0f1a19d54e959fde39b2f7242fef80d36b3d63b2d16ef87da5a4f6b6e7a8d72d6dd1108b088069426f619199a598b6d76aa56a7cbbe6539b0ad518ab73323f66e3f1627c2d746bf65605843c3c8736b6e5b02410ffd010001	\\xf64c408e11aaaed01cee339e557ecb6e31a1f76b64372391b08c01139df1428e7d780104cea15816cfc6d28c5fed27deaa1983bf9b42b01956aa511be70c4705	1646566807000000	1647171607000000	1710243607000000	1804851607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	157
\\x72e5a1cfe423b488bf88aad6212d7f48db88daf3d8625fd827f1093b4d15fa47f419f0743e044ed06114275f2ea87dac066a3f389b1b2355719a6abd480bcf5a	\\x00800003c29e24d838060049af3bdbc169a36890aeddfb391f4a8ef911d2bb0cf3a137ab9ddc7f1df489fce7f7f9846a510ff89a7f7ef617192e3e72acfb3297744c94b60dee801df1f049cfd9b064b174779c884a4d7b102749fa1846f1d8756f6de432ca7639076e4e5d9b223b18545fe3870359a5fda46f0ee68f2593dca4c1dae989010001	\\x496f2355ba16843c33cc2c85d987da35e31ab58c9974f33b07cefe5be7d8fcee60432e0511fdffafa6bda706e22d5154d5dcb3a92863b2d897aaa4f7d28c4f00	1633267807000000	1633872607000000	1696944607000000	1791552607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x7565e2659a6c52e01ed9a4a069c7470979500328875e05d714550cb2e642b519ef1d26e206ef8122ebc8d1ed8a48039c67f668769c993f996cae441f735c7275	\\x00800003afa38b133b540213e13b51736256610d0c7a66f5240d3c2f3719c801080b7550736c6c5f72412bdd762ffccf651af226aadc72751328da8ffabed74047c9086238f631718c7bc6f6cb4803d5fe447d8cbe745bf3484ab9c731cb9ea57020afd8dd11dc3cba32429012fccf7598b114570e586b5466fc939c7d591508e76bb39d010001	\\x8a38e25f338d553216eee4d4edf1c712a71588b770f361ce3d188da9764ac8df903c85692156e899b4290cfd02293f4849b19f40fd0b1e9fbd6f44455f85cf0a	1638103807000000	1638708607000000	1701780607000000	1796388607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	159
\\x77e5677b77948fec66a07c9b1831b2267387d7625b10e412341335fa15e666753623b59177ede797c3576a34e859387d7fdd6376e61e4aa7aee3d1cc39f1a336	\\x00800003ec22e47522f3a76335f7c27d5f6ea5d716061a14d855d7908dbd3f989b9e4c40d7cef755f4674d8af1e60faae9f247895bf9e23b62fc6eccd1bacd8630dbd5c51f696f393e9ba9bd324a00ae8e49dca5da2c7759c743a0717a665abb8d814b15d47c53ff15b86f7a1e40102c3c982a6cfdd25556ff0e5d68cf78ed7537fe010b010001	\\xcf5d3016a31b9311a661a4de8e8f94db785be9cec590c6765e25d10b6ef6378c65c3f8af8c07cbc4d393b4e172db7d0b3c3d41a3ab68e04c3b31c23ac9d0fe06	1638708307000000	1639313107000000	1702385107000000	1796993107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x7c8954e2c59fbd51f8cb8cfe077e887712338f372b043e7a042f496605ec9b9b6129dee627ce5de7c453defc2454dcddbe122440150d37bfd6768216a7d8fbc3	\\x00800003a7baba87de1dd8ecc4bf50b448d60e207396bcb2504821068623d5c3fb87ac32fea5030cb76a6548aacb95fd50a7f4eccf2a05540e83b02d6d638c4976aba90eaa003f9bfcb08b655c233f45e43be007e0b97976587ed25948dc111f57b17f855baa38fc0f7307fd005bd3f55c8c0632a4760d18b96e53f9096f57de5e2e933d010001	\\xf39f2d3802b8b59f86793501a2e2462b5a78a80eaaaa7ea63412e99ee1541ae3a28b9941b01ac81af22bb895b03fe0e0fa11a66910cf3cffdd89df8dfe7c230a	1656843307000000	1657448107000000	1720520107000000	1815128107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	161
\\x82954b66bf42b22ea6d04da94180f95b3ce6cc099232285a265f2bd1123ac9828ea1dfb1a19072a44bcfae647253239348491e59a9f5a63a303a0b01c41978f8	\\x00800003c26c321a8dc5afcddc40ee82feff8de95b19bd8e9ffa171077f7169c452cdf982f1406b04b2b85bccf0c6647bef80e7d4a567ee209f4f1fe1653d41a4f27fb0b19e290aa817de85a3ac330c0290792cbf7646cf3ce7576a13c2b73e4194bee043a7ebf77a3b6e53d8bbd5fff30a03aec3610837f3416d9dd4d818f4aa8833229010001	\\xefb614f9a6f3704f084b16b20e391a2133d6925a527fde3e84b4fc7fecb68537ff1ff78a9eadfadbfc482383132afdf31053a99d00e2fc1f7cf5e50d44a4a60a	1653820807000000	1654425607000000	1717497607000000	1812105607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	162
\\x83616dace43d85164133c7c9d589f7cce64a8eecb0e0917df051514e9d8c8dfc7c55c3a1fbcd8c37b1b5bb2c1930a9dc38ce02318c61111538ddd4e99e342b0f	\\x00800003dbf5726d4e87e375af43e861e41f88208f1c611f80b336ce2107949dc51fc96c7b4335cf409b1c511df2e1792f078014ea607de9cacc69b64e1c2d6a077b1457914d94f516714b17863f0b91f01cb0ba34e07af9a104867a342aba008f249937d9c77432307f1cadcc6342d8674e786923a5d8a802ad90633b04a08adb27f7e5010001	\\x8d2e5f9fcaf8fc35bb62d9b83c7d1db26a4d8fb73e0ae56a0c816c16de009973c82bbfddb0093b7def4032cf4bc77667d0fd66d5346a7022432712767ae7ae0d	1635685807000000	1636290607000000	1699362607000000	1793970607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	163
\\x83558ea4a7d3ef3aa11eb99f69e94d3203b5ed95eb37cd4e2d56e7347df05a3cac8fdb2b9a1589a092bd8d4aba10d663959e1777bc82564e236853d3aab88814	\\x008000039a158c20a3d34fbbed469586447d1cfbb7164c9c14b96b8907ece02815a3a8b4d2e4b5d3919b8e3c604e1aac71548d507002deb7982b70e358c6043b6fed8c31210d619b9cfaa668cb8c134ee16cd26b22a4f570d394efb9f966d66b51cfcb7d96effe43ff4f3b71944f782bd86849853b6aecf6e10a6e69336469d87fb09145010001	\\x10f812f0ae4a541cc8bf94a0330289a6b18d6ef93d2341a147160c48fc8b0d4a3c778e4173d84ee81b909a92616e5511ceda7a8d51074d9ac8fcb437a945e20c	1644148807000000	1644753607000000	1707825607000000	1802433607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	164
\\x8729943f6dfb082a42be742abc84dac98bbd7251d1f8274fcbb438876332ebff3b29eb72d0bab19d8c73da3f22a00e11e575e5d82e22d5a9e7e737828687c7f5	\\x00800003c4caa75e405552d30aaa605d83cb0c1a00634c23f0e40b25653b925ab15e514dc4616c054253d9818c00d6557609443b12fe65fb7fe685da195ec3326e59e3a124394550b651f9107c08e0c3f0cd2d6b59cb798d9303e4b9512c285f7e63176cdfdb29114d4e70380a28bb60f3747ad6424db2d183c8dcbc7ddfce1d59e61b97010001	\\x6b9b62964c31b09d087e57da80e653dd168ca75ea7e63c1ef08ffabe5180293f44edfeb9c730558ae8a93ad13fcef1bf39a7568c7e928ea759aed2fd242e9405	1638103807000000	1638708607000000	1701780607000000	1796388607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	165
\\x876d12c9a0c2c92d653d555021b20b6a76d227756168e38b52952b5aa107b88600366b88a9c2823eebd7a992ecee55e5f382d4c864f37e1f0e88d60b07614c8b	\\x00800003d1f49fa435439fffd51e5d081d1f6b9e6d1984ce5b64dc3b547bd09d83dffb77997625a8df8f851b644c73f38b387e2a81889320d7f999a6196c8003d3954c0b25a0b70d8b696c201cd06d81fb06fa749a353252f6979c5f83ecea4cf6726ed833a0f605640a6446bc2fa14e869993ff8630020a9688f5cf97f4cfdd2937b99f010001	\\x7654a83068166c4b67594407494b6dd40d6d94028e4239e735e9e51373c0d854ff2dbf696e5a958349b76a29cd5b7de8f23c76ebc3330d4d89351aedb426ed02	1648984807000000	1649589607000000	1712661607000000	1807269607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	166
\\x8cf5e2e1c1c06769d9d966709954a9f909f0442917259bf87ea573bed2593c52a8eca3b8342998c593fe1e29e55e0fe3aa568020861d2819aeadb75b5950a648	\\x00800003c2cd2a2a01a221d6428ffa3cdbc9b36e4a70838c0271e2cc342f829f12b5c4860e47b764a09836d34449adb89ffc197c90990779fe20ab027675f07fa5a984f66700e2b12b1745703267b989d6881d3c80ef352ba3ad073c00180bfaef8098fab5113c85465dff16769506c3eb4ef6ec503bcd9f3c2cd843fc20993ceb4d191b010001	\\x37c7c18a5a368a06e8b805e0769593ff0de0385fb228cb2724e7dac20900b512aab4d74c62f8e6d89f1de7c306920127f773a86fca36f28314b04214f525220f	1646566807000000	1647171607000000	1710243607000000	1804851607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	167
\\x8c49f5ee31ae7a6a7f31fc8db514bf0ee354b7723399291abfb53340d9739f03d83ad94ce64b56782ac6fe6fa59ab6922a3fd0c5ed0c37dc6f23e0356425d7d1	\\x00800003e4396a64546b63d88e351d2aff6242d1675c65f077528d27b11e384c44cf52b4a83605da9c76e611dab565d27c29f295ee02c9f4225801b6184d1706be2aeb957581571a4b746a56fa334c973413aaaa15d1e3d6f14aebaa6887d628c22e086adb83f5a55a006fb153e62315690e0f98f6e5932914050b265f6a7f29ea97d4f1010001	\\xb1ec745a60e5a31ed7a95f15c52c74aba152fd8d5142368e8df3ce75c78d1a0cac82a25763b75141bb1757399d1b5aeb354b35d7a71270b9e6bb56e0314b8507	1652611807000000	1653216607000000	1716288607000000	1810896607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	168
\\x8ed566ebc8a17ea920cd7dd4bd99c6d2d1bb446753022957590d596d9632f7aa3ed98861a7975659e37f9be23b55b21d7e2e93173ca0666879ddcc955f814d46	\\x00800003a4056fd1b80e8d232bee629d7860798912a1d2be0c01792ed2a413a32f81abf9dbd0eb199bf89b22385484329e103ec3e5ca4af1cf0854fb63c7a471c1df92f52c053f5e7be96d6f170450739cb620df6d9830ddda97b0b79c5c3d975e32a8ee636060aeaa8a3f4066e92fee851fdfa2c274213236df62b7ff5cad71d9f3015b010001	\\x4c502685a4404222d905e1761562e2f8f6ab54f636bebcab97e84547d88ca9a0876c4c851a4f5264593c894247638b2787a749d17ef6c10a29565ad7c6949407	1643544307000000	1644149107000000	1707221107000000	1801829107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	169
\\x9049871e3c00cb1afcfe9844292912fcd9d34ae7da38d650d23f974398001d740c0e28faee9e7b1605cbd667fc2d7dd579c0add9a3452bcf977809270d8c549d	\\x00800003f44b101eea7402ac9754b2abb65fc2629bf8c077fbe7011870bcde560cfd305989fb693f8b601946133c4dc4bf920fa5a5dd93aa866d26c8fb4704b29bfd345f6e7cebcbd6fe1ea7e9ec16b0529998e8c7a20a6d2b3db3b1174e8b67e0003c92eab823aba721f36f8e548f246e0bd816394cfea1944a193cfa9057fd7a202e49010001	\\xd22a38f0e54ae3a1de786a33b70932e46e9cd5fa0aaee3a91b381da4f88ff6c03fcd1219b00230428b9371b67c98da4f553014370c3b3cddb371102780c7ff0e	1631454307000000	1632059107000000	1695131107000000	1789739107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	170
\\x90251185d0cb95e8c97826a9af06bc6f2b08e301cb17936f5f68ac38a2d04fb62270923aee9b615c94739a9b73e8848a6f474fa0d0d5d4f9bfd2a7271a030e82	\\x00800003a7950f66a13e7c0cdac6aed6d5260c50c665ca042b9184f50a02e876d7bda0ddce4e327fe3bc205366314e99fc7b5f85279e2ea4c58b94f2f33712e16a9689678a76d5c1b678dc2c52278c1de48ca586c90e533ad8b06cc24448c62ea42a2e87d83fe787418042f1e4478ddf572763ea446460e9eef147efbe081af7d98704f3010001	\\x7617973ee2be91caf133e597b404c53684912956c3bee6b017c0fb1330c3afdf9b8253728d4e2513a887e705b73eef8c4597d3525ba8ee495e3f35bc02cbbd06	1639917307000000	1640522107000000	1703594107000000	1798202107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\x94e5c218a0d4c8b416d51e9c6ed758824548e66d9361eb4919017da01627b3645755bb6d5113f787221f258e4a28ac73d52970a07b406298c88b32a2d5cd0ce1	\\x00800003b396a9dad3b095c273ca6b80dde4fbfd63ea401710f1773cb4d6220ec711d6b3aa5884184a2efb1160722fe8b33314e2e4232ced278fdfed507103ebb14caf1f72c437019a89d236d53c45e12fbd43a33ae3f545f08a65720251f43aefbd342f8a365ffb6d0bd4a732609798f51e69dc46b4cf73ce3856f39017917395109829010001	\\x00bffae324125e27db9b760e03fdb78c8950aea17c193c19fa76bdc5d68370ba4ee961dc7a1a5198bbf70f0aeb21331b611f4acb0426657e6d5a7326babb4704	1652007307000000	1652612107000000	1715684107000000	1810292107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	172
\\x943939bdca71710459cdfdaac018612f75d97bf6a4fd33a1f11e6d1549038fafb092a365e21445c66f0745690d7bfd6f8f014c0ce758e444677c4daa96dcbbef	\\x00800003f2fad10b2b5f9d1de0900a915dabe83c378bc13a868cc9ed2f3ce972826f3e87c80609cc8d5c19d3f7dfdd1022e4ce206cc4f2dd7f1746537a4c859beb33156965a36666c7ae9fdaac1e635bed5aaf56145da6414077dc0f14efaa4ff345861c49d446ad79b97c2bb505d2faef446c3345ebd6896bfdcbd2772b7df7dfeaaef7010001	\\x4e5f9f56a63342a35daa719d4f1c6a5571f5d1caec9618e93ccdf3a58718fad7f5005f598335874687a0e2430a631a0c2c96d6953dad9b478c9591e998508907	1632058807000000	1632663607000000	1695735607000000	1790343607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	173
\\x971dcaf60676cca02a8cb1399062ddb23c50712d9a913ede4794c4104914c9fb27d1e3f83c9e0a8b6d8f1f721f1ed928e9d2b695278eb99d65023b83b97249ed	\\x00800003b2238105c1c334db799e0530f8822f8c21f02673d31133d1e33f1b0a4cc9205634069cafb1b4434802d5fb25ea43c6dcb3eb7869f9e38fac37a46c866ef3abbb5427f5089c7ed6401d2de658190646581aa056f65067a197ebd13bc1b3e10c4d6095c20aebf05be09fe5072096447a6724edac96431443aced461d0890f6c437010001	\\x18cc3ac072907d481e5d8d969e922bbfd88a96a0a6b447fb8992b5c886a4b69bab2f82e322b5f370a56e6f666ce804aba3ad4daef4ce7252b33b16b4729d0305	1646566807000000	1647171607000000	1710243607000000	1804851607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	174
\\x9b3d9319a86b535139af3c203ab45c1bafd899354606ff9bdcc5f4a75bf986272aa48e43f87ebaf93eaaff71f352e3aa8d96f43a03d04b09813d8debeb6824e4	\\x00800003d184ef5ebc360619c91d8c0b53d03f97e264c5fdc1ccfcbd3dffc7edbed3f307e30b4ee781a34a198e0b8ac9d28ec98cc142d749796249795b474048b828495cb98900d41accbe358f2d5a629cc6b9f57589867c49b9f13cee39e87c5b5153bf239e2de6c22161061015e40329e2b65dac7494bb3f7b5de03c44bfb37a5311c3010001	\\xc1097f39974f8b80bc228feaef58e4bff81392d82cbc3dd6a1a94f17d6b351c80537dcf80dc0cc7feec328187b6ba209df321bc3a75993d71a969aeef51f340d	1642939807000000	1643544607000000	1706616607000000	1801224607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	175
\\x9b293c3ad918630b2a7d522e460c63025041a317c977bd12ecb58914da777d7eba6f15dadc91e337b9f8ad2a8c63f6c944b800abe8bbb1938f69bfef0269d119	\\x00800003e233e5ed1dc1a1e763bb6aa4dfc2378fd5740d6e55493dc58b5bf467c51f1734a5ed66663e1eab7bba14db278f4f86f2ecfa44d443a818f0ef0be17f63e94cf5e56659b3eddd5393432ae780119fa79dfe4f13f64ad5744749a39912aa9f2a1a0c30c5d27426d9866f95c25c5a329648eab5965a4a7a18de75add34abe4f306b010001	\\x952d50f60269c6257a8e7fb274c004378796a68f3b1eeae4b24bf26842d954a8acc2576d6e03713062aad00cb5033d8adec8787597b4e630b4463a3cf5ea100e	1645357807000000	1645962607000000	1709034607000000	1803642607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	176
\\x9cf9d6fc9015e8d7685266895332132dd23b9ee6211d54fbd5057222e7ce393abb37165674dc1604f8f139240daaff837849d5e1bca46bdd3f6e61bd696b395a	\\x00800003cfb691c65ee0c0b56f563cbb76ac154405991b68bc21ee1e31cc7efad2206c2b7ddf63d3d5ca9ace4282738883e0a28cd5bb6dbb3a12858b2734cbe8210c8660af1a7ef53b16deb10adfbcd02bfae124f853c453c9c761116d3ef234c951cdc33908f10d91f04fc9b816c6403709a839540778fe1c31564531b20d01a457a949010001	\\xcce4c01496e9592876e416cda5711fcc4351ec5d72db9669987340e4ebbe938bff35aebdc21b6c6d5673fe723c6a5d1eecc06b6cc150a8be0e1ef193052ce10f	1648380307000000	1648985107000000	1712057107000000	1806665107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\xa2a54badaa6fa8d82b370ab885cca781344366eba21278dc1f7818cc55d4a6fd37cb146bbc1ab9eaed103599ed48fe2df2811584336d8ce0f184beaff6405c68	\\x00800003aae12d5eec1fe57136c0ec4962b3b3529b74a523c31e58d5eee7d44d1b02e2ec277b6010e5f2a860f6b6170cd11790e403f5627ea8992c93f1aaff159c6c75965591a2228b37d894077ea140d8c9a531ddd9f42644d0be48ac353851b477686c9ce4f11baf96dcf3e011be046cf8413e768e57a968f86136f361480f5c5a30c9010001	\\x69dfe68344a90002776ce9d3838d1d369753551af12db5bcc4000e832f1e3a05b5bdfb77f9a77bc94d265f055dade13b7756a943a513c8c5fee1eeacf866cc06	1636894807000000	1637499607000000	1700571607000000	1795179607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	178
\\xad2de4c725688d768ca385520df303c4d324c54d5b7f1d821074eecb88eb6e75f1e92066e5661594b106c059afad72625e226e1a531ac9d8aed437ba520d1a3d	\\x00800003b3cd2d4b26cba07c3568e0c9deb051880cccef47cf6d2f8f143f5933d3ae2b872661566e1aa11ca8e22c4ce08740aca2cbb771368add5e8786e6906cdf8d81d2925840f7e62bd17d2da80794c5d96cbcca0d711ef7e4465db53a6a2150665109b19397916235ffb709eaf7c187a9251b2ef8e52ae5d515917f17706a12f80645010001	\\xbc6bb6b7627ccc6a4be177906574b05ea9dc2dbc0b5a9ad01a934a18a336be368d7223475778dba675f311ca2d3bd4507e9af0cc246480ddc52f8f27fde34501	1662283807000000	1662888607000000	1725960607000000	1820568607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	179
\\xad81ce64cb29310b0229d1873b58e469cad1bb6026569b3184682b70a363bae87d0765d3d96218645b5ba63850f05cac6db744cd26672cc92577edc9a51a5726	\\x00800003d20b1da9a778babe9e68de15b228836cca5ae451be3698796383f1fb002f2e1b038f4f0451ff73ed71e444805d693c7f1c093239107c52c4236bc6686d051396d8e371d32291da761819424be834f5eccc50a8a1f5bee6d4323df90ccfa8f3be458cad8ea2f43893373e81ec1aec99ef395dd693ac6e0126f1b41fb7c7bd6315010001	\\xcba4a6e8e4b07d375bb50341a148ab650dbc5d9aaff1556ba6b47d6eab0237c808c053594d6e20f7f950687e17240403cb8ee44c113c33db488e070b8ad84402	1648984807000000	1649589607000000	1712661607000000	1807269607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	180
\\xae892d90bec80d7059bc7e206538d89531a163f865d9beb931c5b9f3d3f0100587c02007c901fd335228386baec8ad9f072c9a7a6412caccd8cddf48fe6c4fb5	\\x00800003d722afb1dc31204f234f6a23ebdaf742395e3115dd1ec07c16fe961ac57868060ae4718440fa57f917b3c9e07178a7ecdc95e85d49f8b9ddbdc715a7fe960c45dae05e011bfbdef974fe4f1ac01aea063917b6ed59ffc9cd38f60c751a135160bcf4c1a9c9e41b64f57e46a7cbebc927c58c42d553db2f5f1ee8282bab3a2521010001	\\x9b1d480a5b71bfc877355694018de3c59cc46b66fc1fcd7ab8ac706720f7e54027502b9ed4f0a4d5fe27c23c57fc10bd8dc5f044fc58e5f63b7b8de1f9ea000d	1641730807000000	1642335607000000	1705407607000000	1800015607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	181
\\xaf31050f36e040c09823e0394eaa1b1c273d4ef5faf2dccf6d1d1e3d309d5d20e994a304d39caef8e7aced0c7edbc433ac48f6ac2aeb2390c67d0325e3d56b3c	\\x00800003c6ef868c4a64f65a742c815ceb3d88db9a4642dfd6610beea04e3d8355d2250eeb8458b595370c02172a48f597c6cc08cc716bb7800dc869c0dd55138aa287bbb739ea2ee656d2c1e3c98db491a6851ea9e88b2cc7a57a0359dcfe5cbfc8f832acdb64345eacfa46dd54633690d4fbbc360a995bfc327802910cd2a214f119ef010001	\\x7a86569789e51d790051148b7a9025d21a512d45e0f122fdf82fde657173db18066ff2457ad6ea1ef114cf552d1815f46db66ac8d7d8ecf80aabcc5b2c0dd608	1644753307000000	1645358107000000	1708430107000000	1803038107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xb399a3d2f034e5e29ee23806ec1021021030e82b57ee0d2776411738edecbd57c14f2b9598e7ede89d532cf883bc22798af066e6af8935fff88f71296a72e04f	\\x00800003cc65198f50654ad9507eb5db1b15ef8d0806fb0f630854c5051b10fd09d23f1e4731aa99d1908c2c6aa4fb3daac2ec255085cbb97c2ed829988a042b6bb1d1aa4882e55c709c562f531cebf5e8eb1a092e8d1803e9fb3e3e31bdb0973df10805161d9f3e959668e05c5d84e4deffb4e7c9944e3340f3323ff655b222d8950539010001	\\x53268cac71c27057748341312b25247b22070c988e3be8362e65b93656ae90280c411f7a61ad4f08ad62fb1a85ed433de4dba7819b347359069db51cdae1910d	1635685807000000	1636290607000000	1699362607000000	1793970607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	183
\\xb3bda15fba2951141f8e443cf41771112d38879e114f93b2cc3d96defe8e038c019c6f8bf3ce5295ee00175b339ffc12ae2f19cfdd2466864ddf0ff5afcb4adf	\\x00800003c6080f325438511134a393cfbe27b1511420bde8f03a43e8980483f338c8f57580284eff5a91ff19cb22cdfe51f4049b46423075dbaa658c65de8a4358b0727950270b5118cc7193fcfe88b5b1ee3ece59a59e58f8b2d72cc80ab6c019dc3dec22a4580fdc7ad65c6193b50857a2234a4920abd7bb546f3879b72420fa06f1a5010001	\\xdc0c9a69f35410831aa8d55d223303403bd81441ce77fcae79a706c57018780947bf60c8495aa6d31f198568b8f4732674e480cf685786202538d48980d1340c	1635685807000000	1636290607000000	1699362607000000	1793970607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	184
\\xb40971cd6053baeb55781e0101e966915299d6f75abb2793e8b4e3c3666275fee745e3a256ce0d912145f6f8393d41fff662c067255acf2d039d96fb71f021be	\\x00800003f364b9ec89ce70c6a2eddfb69f2156538746d4b6754e6107c372fbf82502b52d64245fee4dabfc9c41ef38ef08516869dc072b6d77808988b01152e02b268c2b03fda0475f84c2fa1297e0a67f119e4150187680ac6982a11acdf0a63a9fc85bf8f31f93dd863b51a87db0cccd278d3508e34a34c3f41fce28b2fba34206aa67010001	\\xfc571496f5c2b58ca393792f4817b771122d2b21e35f9ba467e8cc74df275c48202e5e823f8037288238308aa8f0e5549362182ade785115524f30faa15c1b08	1634476807000000	1635081607000000	1698153607000000	1792761607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	185
\\xb4099da81ad9b90d3f80f494406b4146bb0d9769b9824249a6392cd74081bac41d3b8d27f6ae60acf73230e87c92f1095d0005232c263ae864b3772060b34b6c	\\x00800003fae5c55eee248d3fc37e9125cf3110aa0138de260235185940d1683055465443ca8116cd7eade107247a8abadc337b7cb6fa170dc600c7068fd49668a73fcef06cf45d29d1809bb98d5d45b8ec3f4c3ff47d13f761c5a5034a8a94e8922990d583d42e0bc956e1a04b0ebd38cce6a73d8ca3e6b3934f811ae5e6688b762996d3010001	\\x3a44e3da095e006581fe1806de48ce5f90211182343585dd25ae4cd408f265e6ef880d2e22e0afb0c188612f9138ebd5f63c7b33c29a4c1867873803bf912001	1633267807000000	1633872607000000	1696944607000000	1791552607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	186
\\xb6bdadb9fda2c8a591ef130d66214863febe81d2509f419e69a63778a97284f0a6e4e9f5ddf9ce2c94048aa7dbcea3228472094ed554ab7691a43f81681152c3	\\x00800003ec9f81888301719cab9c0f09e05bfaead83a38ac5bba76ce0482f262414ce185dffbc83f9c6ec7c9931eb9c34935ed96f4b18c70c0fbeece995818a289a222686624f7b82101fb691af4b80125673729b35b427a7bbe7e753253f6316898378178c3c72b22246964fef37e209ed69ee5c11436f8995ebecc291e23db96757b31010001	\\x2dd4e695407475b0e67c06d3d5f23701d91a589f2dc25b5c3b56c9957c13237baa22bfe84e9c36388bb123a3c43e0fcb08139789858f36fa98dbcba5850ae40f	1659865807000000	1660470607000000	1723542607000000	1818150607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	187
\\xba4def331b4733f8ff1646850d080023079aa46be2abe1cd603a876a314a2e3dde8a410987fb3215e492aaf1c7480d4375741e66ef6d1df648f73586d28f9f0a	\\x00800003d63a4b0cbacff8e5862a97e4a3d11dfa2515e18a6f291578bc3753d91d7a9417a1b89bcc14800a85cbffe9a2248b02dc8b96d11d1f8c74f3e9b4979e28066644f290f94014adf4c71c42295f8611fe513b37e1e7fff22d055e20f1ba7d87900fac502e8c8cf257094bb2baa0b4522d2a0c2ac24f89f40c9f116d040fdb9cfee7010001	\\x9e9a87989c247bb288124c42f320a83e67320aac54baffd1c79f6b8d12a8f2a059df5981172af910355b8278fc1a5ba76f7522ce28c7b0582f2d65609e85a309	1641730807000000	1642335607000000	1705407607000000	1800015607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	188
\\xbab11533eba509880997a35a79f9fe65644cd666acbbf05d37cb21fb5f2a2c5f9c661d2324033bc0740fddaf5f15ad5ffe750c126088f7d2a0b63774f61e3bd3	\\x00800003c8a7c0c18f6498b05a9eb831dd5a48dde2b2d385e6a801944a8b5a0fcd799893cef49ac0c0c0036361d483c4e93d511652eb50fd9f8d5b51fbe8668b5d085eb20036ad14bec5d8e73c9412a38f8c9c150aa97467032d9801df6784c60914afbfc2eedbe696de918794ac717b0c3442a4da3282c239199b041bd2d9e48ce135c1010001	\\xf5f66ec59ef0888be9f177fd559f24cbaefa7641ef130aaa60daf59e48dfbeb55ff2b284d612482e723c92acb9509fe67138f6e0076c220795f2dc9d66c8c209	1641126307000000	1641731107000000	1704803107000000	1799411107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	189
\\xbc7d9dc4e88ca97bf109abf845ae26faf9897e305380938bd469c241a1fe71ec223730b1e944ffcc045436b6bd1f03cffbe5acfd340432a9e4c47a6a3d8e9d4d	\\x00800003c4c16ebc4c15ec33716cffddca4884fa558f90ad6b41df2cf8158d554013ec3ffc31464b1a573445a0ea58f8bbf87290e086335ae4cd95f1e302e96c91f96c05051d2dfde4260bad78d741ab1087f777939c8c12d19c275a658a03005fefde033007a289b893663c3e49b5f850f9a91bf78c664e51b34402ea84c8519a2b1839010001	\\x45b6dc46eb784b92f18d6ae46197c7500b92c4a7b289cd2efd0922a3ea6ade30c002cf7f0298529db8f8e81a4a525487a0d62a70d24d8cc6eb731b1846117507	1633267807000000	1633872607000000	1696944607000000	1791552607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	190
\\xbe555ca46bab4c2161c59998f8527eefc202ff72f8bd90944c3323f331f167c9d948d13fa73333f3eaadacb44fe05d36c08cc615fe6620e1bb4bf6b19acabd43	\\x00800003b57806ba924ea55acdc05cc32d5e1ca815a7bb76659139566507dc0a84dc772e5bb16740731cc2ab25c572b0dfe69380b21b2a3387a13f146ef61aac4d18744f6c98c93c3706041c608c70f1fd66f0798bcb6e0867675b6539232261bda30ae6c2839045f5eea37cb2a59a4b707071b309497b6c6fb02cc60a6d73a14a2837cd010001	\\xf1eec842008b08055a447e05668dbf918ff06a06432cb03e24dd6425751e447a0620845e070e7d045f1aab8376ef00ab2b20ae2107071a70afd53e1d58da3c0a	1647171307000000	1647776107000000	1710848107000000	1805456107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	191
\\xbee9a5c7b5382a5f3fc0c1b0b21de746d935e98bddda567d93395d3d9363d0cb03091189a10799b09c1f11a609d1fb6938933ddb3034b0de138ec640f81809c7	\\x00800003ab59482118f819ff44f010693808ed0a07c615313db31bee11638d2c85f3ef066bbf9e978bbd8314f5a15852c5439c2d21220bc7399d340fa07256bb62d7618fe1177f4052b6644c218386790d3f3277e0a798eb7651602822b97331eb0f04d6f2ac6f71d49799ff5309f732d37f23078ef05a9cae06dd927082a9608931a721010001	\\x3dfe4da09d20dba553e33470cebcefe2b623f4e9dc96fb87263e8d0b9de32880dbeec2dafb9aaf32f1bf973baf89b5740b595b6224b91ca5454dd72d691fd00c	1630849807000000	1631454607000000	1694526607000000	1789134607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	192
\\xc85d9b2e05c380a2d5dbfd99b20d8d6679a4e07a490dd975275e82d5c1577d2896eb0cba4ab8f5695044cf51ecdca3f0739d00ab61a47f83fe03f2ec137c6b9e	\\x00800003c37bbd8815807e6839903801e197fbdf0c4c3eee113ad5c93a60343dfda2bf0b1d441c4674cc47ba128c9e69bb96e8a383257e41c0705e463c5a5bded30e7d88daad6d71e6900b37bfb01ee2fc5ba339e321c3e17f3eda83434aec129a9dacce5c53dc60940f27f9cd99ccdb6d902fa4100f0678b44510b729954a8c16ab2647010001	\\xcef96de7721800819cded6bc9a8b5923a1cb75b1321e38d33fe89291d0dd4ac594d19d3942202841bd9a46403dea9af574e76728c7c3f49199564d9cb321b308	1655029807000000	1655634607000000	1718706607000000	1813314607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	193
\\xc901bbadfd9edd48a1cc8f39ede9a221672f9dddcfdce8439a4034825611936141fba6891ac208ae8ae3a27f12d0e7d457b38b794b665a34bc34adb5c74241e9	\\x00800003c5effe692e57fd59243f37ad60ecfecd1663cee27976e6f7685e98681beed0fa34d460fc57d402a8466f05773359465b2e0be847a18f7c8d3cafbb9e37ee9c416046879180eae05c0da2a48a027744af49467439f4917c321ff7fc05c82a879eb4bb5a8bc0eed7f521cc6b8c321d0e945ede6b16a9304246866431e48950c8d1010001	\\x9bb2ed448e2406eba784300a5cace92e480c796ec2b9a3c5e59cda8aad762f50c64587154c2ab927806da79b26021861f44c934b51a4e5fd851dd56d2af0a706	1661074807000000	1661679607000000	1724751607000000	1819359607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	194
\\xca51fc27294add2129a710be49e320942966b128204e550fea1aa59dafe6113d257df0ddd5f57867390369bed36b90f1af06292e5322a3864229780ade2774db	\\x00800003ccf07f99daa8a16752eb490fad50826072da816bca157aa68cc84eed645b40ec83bbd095c5aa5d27771b1b48e083dad47a172c2b2b7fb3c3ba5794faa41603ee91d28af799aa613bb1274b374f01097b4473ebafb72d0cfdda1f4fbd0ba0bff356c7b7b20a64ae763f3da778ebc0f897230889a656d821e576f6754289d44f29010001	\\x3ef88406b50796c70f372c515faa8fc5c2bdae13f77d7756cc34724e67d434b66f00b4428ffc0d1f69328d3097b12edde5780fddd8c3ffc98a85aa83ec493d06	1661679307000000	1662284107000000	1725356107000000	1819964107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	195
\\xcba14813fbb76319e644c7e00a15827024f4a6ca00e73726365d57e5e07d68e14aada652523de7d1336b3bffbf1f0095f63b2e45f9f79d0e8d9b5731d75d997a	\\x00800003d25feed35a8e321ae985b56243ade896a9ca367ba7c7f15a303f4928c35cdb6c561491be961600eae5c624a60c7c2d1a943c2dcec72739094dfaccb0393e9a9e34951c254647bd3d5bedeb661774cdd076529dd811b7f366b8adfc1c2e7555b6cc46a8e24e35311a72b1a8a7412dfcaadf39296a9654f0c09cabfdbd30a9b633010001	\\x0006efe06b6decacae0b61d7b46732e9b306efd169d995e41ef487f3c6e5ecd41927bcd537a5395a0c80e9fc6151f53dc147e0fcbe28818e93b6ae0223be0905	1647171307000000	1647776107000000	1710848107000000	1805456107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	196
\\xd0c16d0c1dd380fca26f038119182d57e0b1368a82a32227a1efa133c799483b366abed565417efb87e12470a7a71535fc39d4f84def37e2e21c75ccc75fb295	\\x00800003aadaeb4472d910498f5a6d1471e30e3340354bff84243a399138e9697727d0b0788002c8c72859654bc62834c459b8eb2b1fa0f978a93a2f85b34f127f60e185a67d1330d0c01e5dc157272a8d07fd29c9897cbb247419c75aa22d250f6ba80d68eab305b073728f0e691954740875aadb1181ece7249685d42eeb43413825cd010001	\\x5bd0f6f83ace2a4790be757d47cf0daf803f1e585f25a7b97c86ff297eac0c726d8a05457e0742f2467eda44a092dd8488ff1ecd0690cf4c0783abafb0d83a01	1653820807000000	1654425607000000	1717497607000000	1812105607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	197
\\xd10d0ab52bfd3cb16ac9cba76eaf71a425d395ca1f87d5c1bd63730ee90c9754609858e4f896429918686490d45def822b30450bb3d2340585957eb48c113be3	\\x00800003f624f59516e29ea9632482f8e667e4e79cda162404f0fd18f17f5d3d2133c08d54970f9f87fe3fc4a44380db3939dfa389286d9af1889c4688226fc0c594c772653c53b9fd5ac29e7c54e9d86e1b356734cbac6029925c3790d071162fbce4e04ceab6c18e31b19ce330336beefb4a94f99b1ca720eff2c8417c526ede4b6faf010001	\\xcf5c786c28ac29f1f52f0252b9d6c5794287bf6ba77efeb9b26306894eb861022a102db64fa2f276f14093079d90a5188c1ff5ab5479388aee2aad78a91c2709	1636894807000000	1637499607000000	1700571607000000	1795179607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	198
\\xd27196664034e317bb551a4eb50ea58e55aa70c355cc191b3a62ca0651da745b181b38ab315d05a4f3e70f8a02a8279fd5404a36a8e65e5b27deeeac5143e13c	\\x00800003c777ae9a90cecd3d44976871e0d77eee42445078e3fb19b469456d4601dc5f15014fb2b13d654351b64d38b8826d91c73bf2d21fc9d4b520ca44d0906453473013a789c92ac7c64524a9b0dee7c1242241156e9e1113cca2b0cd32413763e1df0560b8243cf5f34d62cd025b68c9aaa1ce7b978d758f5d957e89c6748e75666d010001	\\x7a55e32ce6d385c6647b8470f4eca4380e7c7663f62e2eb4f421c6585a9344aa4b1fdf5cdf6b2d4f5bc81a2b46ee8887b1955117a50849b931bd57458fae9f0c	1653820807000000	1654425607000000	1717497607000000	1812105607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	199
\\xd2c182c9b41d56c9b0c82e370a2b76871dbfb1b862b355475b731953298ad74ade81ddfe324d1624bd5f9a3f8e51d6be91549e628f949642dc6fa3f8b7f05af8	\\x00800003d41fe8266b09100710e6474f16233e6b2e3e37c716f12b467bdd53caa64071c857235de4a453f3694163b2bc709c81ed4f859a433b1d505079b08928283165aa03b09275d7c2e01ebb67862cf219a2d09c991ad2a96aeb412fdd5727bcb98ed5436646a8ce8368e3df98faa69962c0a89b288ee22138cc1f956f64c467ed18f9010001	\\xbb100c5a368ddb25a6972d6d31ce84405991038e88da327e09a528bf64551ae6013947f5db0f966dd9ce4630d37e6b51e2f0d2fea1ad694a639b75fe06f08301	1644753307000000	1645358107000000	1708430107000000	1803038107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	200
\\xd33deda2a3617b557e43722af660514336c3e75e362ab1186e0d8eb9399e497eb960598e334006bf5193eba3a9a32801c6595909c3c3530b4ec6778d97c55f54	\\x00800003cff34e1256570a147abc4c5036b3fd0466894437e27d219b6832bda93c4a748fb8e0cef6502353094dd4b3bc540b6ab79b1f576ba296026d805694144036d9f57559b67e5b63f885fee32b2fe616b78bac8a5964b2c2b339680d4522f9aec5e2c903a43c97d98f2dfd6c37e27388fbffb84307112665f5c00d57d03de51fe5db010001	\\x25df2c14f153f2cfc9dfdc048237ed7a4b7c8b57d2fffbbbb2bbe9b14ad6b3c5719b54fec40274044bbd1b75d42ec06537ccad13cb8211985ccc7dcf81aeaf02	1653820807000000	1654425607000000	1717497607000000	1812105607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	201
\\xd5791ca4be8a4ef55c399568f5090a3b8dc281f50ca3760d7b4a8251d784a4cc62d567cdc3cb1c77ee5c525c399eb2e6843b9a37298eb6e69232e22a2fcfc0bf	\\x00800003ad32947ac8b96d353e02f49ae7d706e514920f5351239d26ba2d6ad460016bc31eaaca51b6e1e90ea690bfd22abefedc2105a6c5e3c30f3a814075e24a2bf3f65f4cc3630dbb9dd03cb696f7d327bd75ada0e7459a101415876b80577a5624c86c5c726bc55f1d1863f766190961f02f677e1ac37f420bbe4f193c78efd011bf010001	\\xd9899cece94dcbedecb24db90f2e5b18a7cca5d21a8f84f5d958ad1567e7bb50388dcf723f3638e78c1f2d54be2b7f96432fe63ab45676dc7a72f0f056b7bb0c	1635081307000000	1635686107000000	1698758107000000	1793366107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	202
\\xd73d85d578124330479359f8f3099a68e0ecf1fd4c253598fac154be40f0bd0219a3b70a8b1a3d909d13480d599eb9cb689ec22fa25e00a1c605b9d602306b13	\\x00800003db110047c9ed1933a9bda6de346fe71a278ef8afc0c659dff01a18435a2c16f57b428e1745e81e5c526e03a045ae9ba98149c6f6dfe8701c52f41319796f390cfd5d4f6bf45f42008d0e46ff6e1363819f35a825f734e3d2e5e70aafb5255e76f993c05593e6d5fdee528b610f91ad4344fcc19ffe7846b507787964f7b65db7010001	\\xdcbd8f5bfde3198cf2afb840ce796353dfaf9026cf3a3bbf049bbd11031ceb1dfe186fb51991507b52057f80dfd3a24a5fe866b8ebd74f17d93a623e2de9000a	1634476807000000	1635081607000000	1698153607000000	1792761607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	203
\\xd9d5fe5dba4fea136ad28de188a7d93f0932ab35131963324fc8f9fa1b66271b0a4a1dab5ba5a81bf96ee8591478519767e6bcd24e5547eefd461cd5767457c3	\\x00800003b8edf72ff33a9564c6e4a96cb24005f761dc89841d3994409c2e3ee73243632ac386b42368a48c55df191c2d15d08d252f5fa3299d95dc07b974cb8916c3f01c0e84f850909ab30d4cde556e0f4c11ad20f755ca7fa3b93c4501e8b0a336a4a2a3d651f0c4b3b6d2463a926332ca53459662c833fc35fffc06b302844e216f13010001	\\x56cf60244d5ae2dfd347760ed6fd5ffab4f9a21fff38cdfe10155c6512a1fa49b97de6270346739016bfd6448d85a9e31f7104eba69a8e97d4ec2fd7f0fd670d	1656238807000000	1656843607000000	1719915607000000	1814523607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	204
\\xdb59e013103fdff860f1047a242fd068a1d3554d2aecdced1ba6c0e02bf51f254439804556b5560b0006454e2f3b3b8423fd7fa27d37d53f0097ba6cf5cdc047	\\x00800003bc3379097c7b3a9e1b6c89d8445759aab68811720fabd5cc1c832b4e8a8545586f5fbbc5f0acbb628786f9546e0cd1bed6ef8f44e3d677906a2b8dadf47f19a928669aa13dc3e634b2bf05ac521c38e5138b6eb495fa84b36840ffc50357b05c9add371b4d625563b6261bb491eb28d9ddf651b167142ed099ebd49ac96138c7010001	\\x20dcff2dd672ef09bd52a0a3ca28f2365285e16e2e91424a579585c4700805bdcfd94d0a07cfa927838ae8f32ede5f408100563cfd256a0dbfd013144bb5060c	1653216307000000	1653821107000000	1716893107000000	1811501107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	205
\\xdd555b6188dfcadd888059c86f84e36abfa68d731338f3e4f6c1f47f716ec03361bfab1564356c4e7b6cfb252a9e3747658c7e4fe1c375e2e5a1bd42e8dab944	\\x00800003cf5cf349d3ff8222d75c0922c29e68e0ca8bdf4e6fb26062284ecac992f21cf967201df4036d3b978793248520a2b7b67f7b54af4e41206ac4280ef0b995fffc365d305db1fe5012c4fba32e0094d7def3bc2fe4f1b1568d2714f63879e519c1de3b5f8a9b4db35c8df1be4d5b44fe788e93739f868f9a0b1329b240c3f5c631010001	\\x14b0648debb1a7caa71eb7bea2395f0ea2b6d34aedcda3354ee93d84417d25de4b6b450491b14dea068a40eeb048511aec9a19e3700280d303117c1a6524400f	1630849807000000	1631454607000000	1694526607000000	1789134607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	206
\\xea1112cdc85034e2298496e931a3348cd9e1a609bc2ea16f5f1e8d2a0bd3ababdbdb108ab38c412333d381fce9a055c1263ea92484bcac0fe345d193b3a1df4f	\\x00800003c0fee66a31077ecea94fe52b697c27c43b9e2ba6b2128c9f16c79d0ded6b7e6cbb8269e89bfa13e2c0af0240985f42a4268d72b4478fb8e2b9d1fc030b18b2230755e2bc55599682ba0f0c8bd013f98632e02dfeaa56e8a046939e8b0d34a3a08875fa81c4352c640a3e58c98e7a92120da300234439a963e09e64d7da5134d3010001	\\x7c8c46dcef2590b1aa720b680ed6951b3075a36e045407cb9bff66b3658645dcd93e971566bc0d8e5370d19a4e41a9f0e21d6a59d0886b10b2d233fce2b0ea08	1648380307000000	1648985107000000	1712057107000000	1806665107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	207
\\xeec1a1ce0235c9f36e917e09d24a580c99cd164a53a7972d08aa2ad97fc9bd37c16b25c01a567079b1c15c985349d66e5e77c258039c2b329b85df2924fc20b4	\\x00800003c3484ba3797c365a211700da7e1df3421d88170a40d18ed73d4a3a10e168fb266251d2c76b7da35d2f5b8a256a70eb5e72dc6acffb0afe363c4da1896673031b5a8548a2a8182fabc2e36842956dacf3f7d3183533849d91a48b3cd369c96bfbb16ab3f346aa01781db0abbe4bcbe2e5e87689119daba6f0fc0087994331b6eb010001	\\x6ba2ff50ddf48d66b407d69083c08bb7abad367b9e11362c80bd5b2b1eafe76af4fc786eb7a9691890a2c73c27690c3f2eb344fec48d4fd64abfcdf4d5cad40d	1656843307000000	1657448107000000	1720520107000000	1815128107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	208
\\xf155af2d6961327622a821b4a4facd8afab44c82974443d21e8a58831c8ec5c5add478ac8849a2d82099e9c231b33e7a5a89a42a5d251f540c124cfca1955fbb	\\x008000039e31c664e1115a781338b81455c1d9c14202a6c46bc66f64a6fcaf278f7074540b81cc7d62bdea40b86448594daeda6629dad6b93b2e662b59aa358b709d4ce303580af6ffbcda7857494b6f2958c6f8af6c6f2672677c2b02a2ab16e537162e4579f88570b55c222053daa8271375acfffb260f9872035fc5ceaf9d650ab769010001	\\x9bb29ce490d17399768d761aef008a9fd738e87c740a730d1c3cb0343cda5eea50211d590df678f13f394ae57f63be5b15aba9366b0226d7214481c8cd956c0e	1661074807000000	1661679607000000	1724751607000000	1819359607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	209
\\xf3e5c8dd0c6858ef279b2dcb236763f08f3b028f51315f308d68084c731b1e77d433e51a0a5e3e3fe5d4ffa64724d5c61d02b8c6460ef72abda1ab0032916074	\\x00800003b0adf32eec7d41ff074fe864e21b2a0c0dfb9825bb25afdb2e8a309965bb194f2439b7929ac14318844254495dffa00b14e0d8cdd3f35dcccdd35a55e13b212cbbdc1c66de9c61bdd18633ec1f9eda8c6429baa0f1173d09425fe36c0fc3737328b9f61c878540199968c98a590689cf5520cc08022dd4c7903e44381d26f2e3010001	\\xc92f9ab17e8f07688109abd0c40c42d146483b9bde575856e656bd09995b26499ca04276baa0a5e966f171a6c8f07990b5767dd20cf0542d80a9f55fead00908	1662283807000000	1662888607000000	1725960607000000	1820568607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	210
\\xf4a133caab323fbabbea60efed5a5794ea770a97d90edf17a3ac5d858b5fbd3dfa3a2cb95548ceeab5dbe41b811825aa0e7c9682fc6bda16b062995eafbf6745	\\x00800003abb4ded8fd5ee8adb1476757955471a505b9102de1986aa2af47d4a5c09b09ba08c25068467b2f0f31a64e20e2454f8e6bf34b09700564e8b6c83514e8597e187c85d73afcdd4a3b10084da51578a203898fb7781d09decd72a0e3b8f9876233dfae20ca809c07ee8001c33ec4e92262e4c47039894697eb9dd103e0cc945ec9010001	\\xd58524b0313af8b5f8033c63a1bcc0ebcf85e07c6a2dc21e4eb464b2d41a47732fc8e6c8f508bc51cb780de49b2266179aee12e9c8492c82c013749c03590504	1639917307000000	1640522107000000	1703594107000000	1798202107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	211
\\xf99127c7b176953f13a319c35a22581062a37b8abca61faf8c75e44992eb38c01d4d3670aaa2cda13064a3ef9dce64661ae7ac684e5cb96b51ed02b460d522f3	\\x00800003cea8dfa89508b7f4288c7843a218399474901d1f695b7f49c1eba19cb4faa4b5ce43a3d399a4bcc21cef02adb3ef1070c30a922dbab0e2ebd4bf7005798131343a161511fb1744a14289eca66b5dff13d25b182e54277553577ee1c3c6663ef3a665873ad1f1f4329f5b89b035052253e3fdc248ab4baddf41935686bd004cb1010001	\\x1b74cfb23bfc6c9358627428e94ddac1280eb4c5aeec7c4b973454c7fa738df5fa55cee57ca0669aec960287b65aaec02eae1e601d4583ee6edb93731f99360f	1641730807000000	1642335607000000	1705407607000000	1800015607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	212
\\xfbb19e98031031496967f4f5e0b8422ab445a8100ac90d7f3cff0b27248240ad989396cc2177bfba8007a9c00cc84ec89f43a900d067ba34b6764281fff0ac04	\\x00800003dcfddd7c28a9a6e6671bd945c5555296d325f2a228c87208c104dcc9b230316722f22d7ed5cab7b2d5ba5adcc39e5db48068b6d89452575b978d52bf04138548ceba94c101f6a4d2ebb89a64d896cb608ca183c68b60baf8e85fd9ee3aabada71c27562b300e5eaec7ae740ee5a8136a591d3fc7ecd9f9c954d8995a2bd58dbf010001	\\x5868a65dee09ab42033526c3e54cbec95be977393fdbf8739cf8ae4af1b140da7b480a46c36748ef9412e199531d7150458b31eecfad0c946870dda0340bd403	1655634307000000	1656239107000000	1719311107000000	1813919107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	213
\\x0416759a606716e2fc8bd869ecb528acecbc4326805ee21f90a89845ed44c825ab7a57b98744a8f54ede0392a3eadaf80c4501430eada329a72da8fd7b307d5c	\\x00800003c73ac90e187ef47cf1cfa7d8ff2423736899e7f4392782deea53d0b39763b52aaf44e10e8abe9f15f92561ffb41686a9cdefb8beebaa30da7b36c7cd53026b78e4f45530caf4f514a0f800bcfc1ce8f2bfd8007581463c1a66544e50e3b6be2a6c54a34857c59fb49b74743b4658d2b56608924052f879739ca487768a934ea5010001	\\x2d83841b09342da7133074495943b63ca30d84e455a506d20316ba1973889224b7c3216cbfcaf5fdd9062fcca3486b76530a266ceb754273b94d3993bfb25308	1632058807000000	1632663607000000	1695735607000000	1790343607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	214
\\x054294dd5a0ab3a7b4761bc28bacbcde9a59b00d5b1c6a4c5ab484f641027f3cce97e25541fb43104d83b3b4b8eb4ea58d92208f35c2632332e23538715ec24d	\\x00800003b63aa8a71aed86c68ce27eac7ead41be41ef15b30efa369f5b665acbb556da06fbf2125ec020a3bf8aa5a25cc17476070d94bd8c1561a95ece39c79338b9c4a599d102d9347942d651c74cc3b1cf13ea3870c86c2b6407e02c728e5770da112af947ae3c05cd37d0d319750567966b3ab7ccbf85db4bc496edf70b7fcf828471010001	\\xb853a49ac0ccd6dfb4339d62fb8992ef7fd60e86a752c6bc8860cc7b48df1f3600b842bd67c8cdb5c3a6d525db5f3dbdffcc4eb2e7b27c50b01827e06debb205	1640521807000000	1641126607000000	1704198607000000	1798806607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	215
\\x072625279d4fac566f495f5dc1159a1655c1bf24d39dd6978efc8a3e32134d648d02f89d030c77550b8876d1c73088e2417cb034d01d2e5d96da0776b1d54672	\\x00800003e1e7bb6090d6a2f9fef4e009c9f61bca9139d35ea03264032043c9c0fa2ec440e612fa452b4f616f98e504b1744892cca537775cae35ee661d495405f6362c75ac23605cb06286c053d7025b707e930acc746ae727cea356951e73308b9433bd41d8073c05fe81396ddf44ab021110f5212b3f62793fc82cb2088066966910e3010001	\\x967efd1964dabad53482508e7321158e154368f6b8e3b659096cb2cce13ef48fff1efd17b1282e5f439355e6dfb6e321f61b62bfce6de75567b61f06335b7f0b	1647775807000000	1648380607000000	1711452607000000	1806060607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	216
\\x0f7e35d8778bb90a9c11d846faafec875278513b1b7d98677cd634844664aed735e90dc516559cca4b96e401a5d3a0e3e2607cb9288cee39ee0162683c82d9f7	\\x00800003c755a68b58f149cd23661983f2ae7ade92cc067af944b680ad0ed014e52631e584db282d75b7fe41e9a9d51f0f204fa9c479235b5e87ca3a58da71a458b4a0e97c7547ae56159b26e5884be59f9e1adc8d0b3e42a6a69c12fcfec23d26040f5320fbb74809cea20f79f60ce7ca161d8d3b15f1e49b6d04b135755ddf14d309c5010001	\\xf5fee6a3cd35beefe784e2bce19b52adf8af379a0cdc35d29b2626cd194540208ad10c25e5e39f29c51c90d364b6aed341881f5ac38377ef48b12b7835f94e0c	1650193807000000	1650798607000000	1713870607000000	1808478607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	217
\\x17da21ff3c3942941032a4dd34764f3bd7448e1ce31755684ff26eef6b211cc8f85e93b34f9253fc88cb21fb1285b26c7b6ff27de3640f01c9ea07be634ff1e3	\\x00800003d3e53ca924b838d181cdc096677f8771c3b834427fb72b76f47ed4acd3edd0d993d3a8e2abe8cc2d099e4adf48a11f5404f333c6722b0e1c3e3c27a04484fa199b85b0f73bd9beabacb0f53908761884a3a6630923e16e4e0546364febfa5b64c9e7f58206ab65d393b29c39065291d3d66a6a81498a3ff2749870376ab27319010001	\\x5d50fff0265b927eee906f42306123877ff376077d2548b37f99a39d19cb24553393e84c20a9ca1d753452d7cb88230c8a7a044696c83d474f92c0852275e400	1643544307000000	1644149107000000	1707221107000000	1801829107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	218
\\x189e1e524e8d90acb6b731343013ea8369b69afdaec9c714cff8abf0df181c398871d47520437b3640acd2a8f058101c76572f950d0c5d0e5f5514f4cb135a8c	\\x00800003e1a7f90da24c7f9dd55fb0d290a861c83bdab797782fceb6a1955ab2a6f62acf8c27ef577fc41fe668fb9904b3df95773c62fbce461a7cafab33b805093beecfcc013d00ef7dcb07e24bec7ce2444162423d3000641fa157c801732b47e24a482b77007829ad54152899ae1a1986cf2913944e6c2e61ca5a1ffb70838785ff85010001	\\xcad48997aa5c151f544df4eca99f3490bbb978240158247979c14478b5b5b36fc104e44977b68ea8ced65ef009c4b5d203cee94a52f707878570ec28bf429e09	1654425307000000	1655030107000000	1718102107000000	1812710107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	219
\\x2856c7d83102e4a83a1a6e16220c54e4a9c2af430e70182e16eda625e2d1576c512232c4dbedf4394d203697919621c9ba997fa7670dd1f0ad70ea71429616ca	\\x00800003c02130fa628dd636d9f025432a19198674c0821c0031ddab3db057fc9cdd470397e74efecb57f4859df9b3e67ede7ad7968ce0cf3c2dfff25397a07e4f77e592bddc74d790599332cfcab53fff953623d2ad7d48f3a2aa0155f587e69db551cb7d4f78ff5fa781b0cdab28eaa17ded44a51b3ecf9892dc9322fa1aa59b4df871010001	\\x855ce8d550074c7978590a2f5d8d2b3d4a90195e2d5026495f53d938f4ca40e3201bcf2a0ed633e25e61652fba9487a6b380010cd93d78472e8d8e0b3a0f3501	1655029807000000	1655634607000000	1718706607000000	1813314607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	220
\\x28eec5061481a8e19621a5ffdcd38b78a42d44783629869b86c46d1aefb933b4c0646f08c5a11b7959044e4b9dc82d14606542f42bf58d74ae3684a60cf2cd2e	\\x00800003c3ff6860ba9827c237a8a2dbe22d72dc78886f2d88620ca8543ed48af5c5a93c6da033543d972c216136c28fdca61845bcf6b4fa845fb13eef6c52a456cbcc637f5dfb3e359c8e751df32915601a727841bad37a18006bf50eb31dc0f4d2a7e7b08a64ae471fad785406ca7b3c73ae83d60d398c96bfbc6b2f542a0f4e93c6d5010001	\\x452caf5c2a8eafa958b607a43e13228876a66459e95c239a14e6dc1899a1e1834418957b0810927b6a7856c42b5524f545477a18f7320c36fb3cc896597e3f00	1632058807000000	1632663607000000	1695735607000000	1790343607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	221
\\x2bb29dcb88372cc117a2bbfd22c5504769f1a19d23b0bc3b8217239406e51c2f61de1c76ed38c6c2b75bb26c0b9c63e97e6f6dfe39941e81ecb44ee7f0d8a45a	\\x00800003ecddc6a938f3945c2f19b13167c8477dfd7e727727ec6e6a066308bab0f56e3799d424ca31391a5ebeb77cfc81ef532a85dce90d01b3dd51504d96c1327931b86ab14a51d98411b8a0952b18299a58c7dc3e7fea89593edb86b5c12183730b331f6b7ebddb7158a5f0112e7798e249031d6da1e5e72996a7a6892ab25528b963010001	\\x4af1d119a561f50b73de93e6eceb41c7c7dac4b65220c39c7e21bfec17f943b6ab8664dc2f51b114b2af5b1c69f633e8a9473c43191cd60e071ab1a634de990a	1644148807000000	1644753607000000	1707825607000000	1802433607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	222
\\x2dbedc9297066a54c163b1de8f292d6c95d289c0bd011f2ac8ee699b9250402bb0cc53169a5422be918bbd1d8d099ca7fac895df653c11f71b1f0d3483403a1f	\\x00800003aed38ec60e66303ec8026a695974c7637d99f4a4a3d158e520a03d2035e177447f4f06b742875e7917de7c42439ee2aa52f682627c4deaf744b1f89c0f7c013562168ff6b9ce998c92b0e9eb387f68ef3f5b1ce57fb60e228517b379ca3e5407930bcbb3f9d9a0e27c20bb9d72847c1537a2b3c6e003c827348fa1efe783d2eb010001	\\x7b88f2588eacf458bbf2d4c4a22a0dd4a39a3026a3ea116f4d6ae5140ee00a4feb96e7f7fc75262367d02559b300ee7cf12f760e6e90d833a442210b8f94fc06	1641126307000000	1641731107000000	1704803107000000	1799411107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	223
\\x2fb6e9b4c73f5360d22f433adb4a4e19587304cf7408c6f36c209c6bbf4ace9f28bcf230525e8f1818853d7731732aa2b15b07ede48a7a837722684b7e4d82a4	\\x00800003df7560a863328a2cd80499b87609a3e0aad98b05dfd6b405fa3f153af4e6fdddf080c4e77342c409bd1d066db74cd3ed0c7231677740baf9bc3c804b1a50cdad9096a5c792961ec59a7e128396fe454c4e172090e576170b70c85cfb3dcea965d3bbfa893ecf27b5e46d9d148e601d622d185b24ede8f246aa13dbcd700e1629010001	\\x3b0befb4f8799ec38b205cfae8723c2d62346a224ddedc974e969d61e9262739bcee184bb79fe2de0c370764005b3a48f87e6a826103a3ae8e4ee59a2608fa00	1639312807000000	1639917607000000	1702989607000000	1797597607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	224
\\x2fcac248df4e9a78a5fcae8778a21a291a46c4adeddbb1b9770a2c50010ce02dc068146d6c736c6f0bea25a011385749af2b149a92789e54be2cbbeeff87a878	\\x00800003c4ca70197ca7aa25708d5b41ac300323939516fbefd22018a2942f2c4b53831af32b2a9fdfcab2cd45ebe62b8f3b0a1c029ecc4dce3c435fc41ca6bbe95caec122734be165cddbb10ddf1487778051bffa9915f6bd8bdf41bd4d55441f8d49263a72403b9c6daca58eabb6938fc51082eb94c7cb84f03997b42914500f23ba5d010001	\\x4b99f6381f9ad803ab7c0dcde6a71ffaf57a407d76f3025c587eaa23c280855a9d255467cad71e5da7b2203b06cbea3faccce907d729e713c7f03171d3f91604	1658656807000000	1659261607000000	1722333607000000	1816941607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	225
\\x2f82ee12c4c47698100207c43eef2f04f66749add4f3d56d664f23262e2749fa04af46b664166422127e11c65c22a1903ffbbf601412e53cb27a7e633f711055	\\x00800003e4a892a92c7c36a0511e04262f0a86e925b324fdcdcd0d48a66eca7cb69d014470e6ba48af135f9751aecf26d3698147f9e7284d07d266f5b45829ce4a4d8625d3d2a6826aaff8ce44b590ae85f5129c1d9e396432f5d16f14eb6d452df95010038f5ef4ed5d4103b70b15dc1d37677edc9d95ee88d84e4eaaa0300d956e9b6b010001	\\x512301f7a559ca60dc99fc8758017e0aaf717d6ac19bbc94604a02703336fb252fc05c62ac0f13089730ab042e83fd3d5b1238ce6de8c83ebe39dc8d689a030b	1652611807000000	1653216607000000	1716288607000000	1810896607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	226
\\x3042d956e3d655473ee26612d06795a34220efb7f1a5ccb2340cb098ab210b3a03bf60a2438a4410b21d4a0611c156159b3d54b01bbb1ccee3643260781169cf	\\x008000039b030690da897e23cd0d0eba46fbbbdd0a0e03305873d85b550acb468dc4d04ee9f9be02051656f9a67c5694145d5d40066a54d6b2e5f0ab9270eadc07720100926763456da3d2ab6f4627542dcc30f255f11af002bd537153cf3a7d005591696240c796261f08a61985db9e7bc625d2efd9e7cbfad7883c0bd531f418152427010001	\\x9410096008c338164d2f82c68b24db1ee78ce7e46f8a2ca25ee267f2a56d1a6d5e7c7292d79b24d8a179b062bf41fd2340f0e76a76c7054712de36adcc65bd09	1640521807000000	1641126607000000	1704198607000000	1798806607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	227
\\x3296f8448f5eabbeecc0a9877c9443e744a0c168ea9759ea8358903393f6784b69815f5cc9859f2904d6a390195df8aaa9fc17e609083eef9991b45c31d67b66	\\x00800003c3ee312e23d2a800ba0f2e08462fca68fab222242c89b5df816f9892c7536572639287ae4fd04f6aeeaea514f432ee032d8a46a1f7d8f0ad75c37cf0d476165b0061d5b286e099eac42ae8ca38574c0952640e1428e2bcdd8df7ff81c2f5b7c6c46b1f938a4d783afb7b1381799ee2f2f70731229605febca82138f3371840e9010001	\\xd8f327da9ab7eed5ef531b9eb0a98019d7ecb39a53577f91bf9c5c633c00d536330980ee1f4bcbffc694ea299a14549ee83cbd920db2cb8d2cd84762548caa0f	1651402807000000	1652007607000000	1715079607000000	1809687607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	228
\\x32f67029ed2713a066ef6f96e7ef364b8818310b4bacd4afe047467233edc407ec9b3af6409b516c542ad1def1b26323c9ad24f3b3b69959a8cc3e166d80d59f	\\x00800003b82a5fda787759d03a529af3dbf395af48299195fbfb4b04d5ff202fe144c9004c8871dbaaf3573f4117db726636af0578edade2d160cb1d997a38007300c53167c8e92a1ef83a84457852c4e1bc9dfa3867ea84eca0655693c529e3d6188249473ec50279dd3b93c767140bc3f247489d2406d64eb239512223d76d7196b3c5010001	\\x9f345368c57a0c1ffd1daf8b447159e0a60f9a244a850e80ecf0ac13ac1b370b72af68ea469eecf2e920f6f92a3d7fb55f208344a2ece12ca666efdaf4659902	1645357807000000	1645962607000000	1709034607000000	1803642607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	229
\\x34be1bc0c9f81097d7b03afe69d5590a5d48ebe6ba634b403ad62e1e0c5c8f842fabae5fef75cd23ef1dd136c860d66c6cb170428ddeaee95405730cbc13513f	\\x00800003e73391fe1a8af9a6061a82007231d9b12d94260a572393bdce115e0a6cf3be87dba29ead9ee0eb9b18d19fe13d6cc773d8cd4439bc0565e554014192dc343b0948228ae1ee0837b799b6826bdf5c34751c2c7ae561b75ee228d80101d32ff052dd4607a468102a093071ed9dc4b38c86dd091aa3a714c40f90a6deb38ed66adb010001	\\x5f5770e1691307fd31e4b8c1be799730b7d53636bbe5dfbf9f55f127dc913cde32ed5b148b14298b0f62ebf499af8d0482d514632c969ca908ab21da41f54706	1660470307000000	1661075107000000	1724147107000000	1818755107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x35aa7e821847a9105cffcce37923523ac31614d6aca5f5440b5fc643543be430ae6109b1fc06abad936d0b6250a51ba56bebd48e8ab36e7366375ad628ac025f	\\x00800003df9310790eaad0e4dd6902bc8400479ab95457ed660b65f052164c8b639c53f5de3635f82be122d5c23649e8a173500f0fdec778407f2b8ec6bcdd405d5608c7cf6f355b51c168aa550892a3f41d22f06898a1f9b917e12a09368fe054e93db86db7fedfefe2d00d141e6f6c47233dc139a0bf2f1486cc604462dd238dfdaf9d010001	\\x5b953e05c174e4979a54626ef03a7a69d2fcb00062981f395539277db6bdbf51b744ad63765f3e00984b1273e870b069f4980c8d7c5ca5a88d7aa99b0948b805	1641730807000000	1642335607000000	1705407607000000	1800015607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	231
\\x368add4b0d13a4d2e7ef34db9a504ffc5b22420d667a1ff74e727cd2ad048eec8d45ca2a5bea7b6fbe622e54a0033f0b703e069489424dcf45207b9cd0173b82	\\x00800003d67733a96e43c0dfc773c0f4ee73904dd702ba80115ad6aa40ffb9e58ffd1a37f44820311348e85dddf1f05af74c81f41f4b42e47033339fbc24bf472bbff9ad968e2f880ce78ac980c571179715b28a2949b16ae2f6474b42b036ce1ee2b158cea481c0a459e445814a939c2319a9c822a60cf45d2b6d377b73f5db79dbbd23010001	\\x14c601ea5c73e689a82eb4146b67f8644cd505958d16089a2ac9123173a1263a536bc5cb5986678afc6b36d42570519e8f39cbe726d7eb54435eb75bba448a0e	1644148807000000	1644753607000000	1707825607000000	1802433607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	232
\\x361e38a126b3c5e982e32fbfdf3aa9a3c24365480f40e4945ed92d6e75f7dddf05ef518c41f25e23804211829863d771773d6fcc1d1314fa5724bcfdfe7d9e67	\\x00800003b4f0b4918290bed1dd8bada30e52e319c426c17fe2d5169e9b9d34f1417ddacb1a5d37c364682fb8a8231d7bf29f68426a00f40f95610981d6aafa1a42d58e8197eaba5c91f080c014f5992d5bbaf313ce6ae9b228a331824d9f3c049a8a3270d74f0b022bb28845dbf79a92cd7963c0049e4f04f99a375ba92bf956aed0caa3010001	\\xc943ebe11af3c83a7e7b89328979b3e72a4926200185d95e4b1164d1a3de13c6e44654d5bde4da202634868240512393e019863c9f5a6252a2f4e9cc032d9405	1659261307000000	1659866107000000	1722938107000000	1817546107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	233
\\x3abaff1ddc5330fa1e70795023b4297171490d071c790d95c7e8b011ee5c20dbfc7fbe26e018f02b5dfc72c59eb431f099a695cc411a1591d52964a3ce52a108	\\x00800003caa3b6da45371e4a12910433309c773fcb4ce14a652b16ecc6d8009ac6cdbe35d77847c7bc7fdae3b85836cfd2aeeb595b0b331d0cf475aec538076fb2d866fdf2d47ff023fbb41d5729db777e7861f016b1bdd8d5501eda72c569d1820ceb739c759b5cdf3762fe37ff51d896841c587cdb2255280476a2d3d2d9adc268ba59010001	\\x46a795a68979d5df31041235e05359a5ab6954f0e55d924322f871a2ac08f6bb05720ed7a0a52c41c9ed2b157e3f2961260a8527ac2289538dd94febe6a4f002	1642335307000000	1642940107000000	1706012107000000	1800620107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	234
\\x3ad2de65589ac7e7aebd9eb74379016f0459bf54036add63f237aa5797b4598d0f3a8da76287cc02f96ae1bca874e4fbb26c8ed8ad68271b4e557e5a1d120cfc	\\x00800003c4bb9c34cdb9710b314964d075060ef4d293e67d63f17870663702e78b8a2de4353fc40dc8abd28278e379c44aaa2e0842075405a99ecbe4b0ea6a2f234c2d86f1387a4bc9b0ea3064912030657bcc6e18adb5f1dc01108704af15d895ba0223d273a17040760f484a212566425133d6eec6cb887bd2d88d650f5dd7be64a9a7010001	\\x4620bb138210a20332cadb547583234d8c0b784a20666e5fe36c7fddd8cec597fc32642a67d5e29fd0aa943961a49830cec48ba7258ad154c30ded271ad43a00	1638103807000000	1638708607000000	1701780607000000	1796388607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x3d5ecaddbe4cda82ffaff162c5edd012585c2a29de7cd463fd34f2bbc837e230532c22a8c04d6478dc160d47b1932d13540fa3aa1f976992087f24bdc529e108	\\x00800003ecd7c709b2e63a217939c8f619d01fe00f97ea4746a74f3f134790d3ad818f37e7383b4dfa88f36607cac4e5b5136fce8b98678410c4dd85d9dae40174c8fa720c292a7fd18d7ae9f0fbef53ec932bfeb61a83e7c46aa7e402ca5ca4fccb07604ed4f376ca1375a8cf80bd46f236d4a56c44a100ec1f10bda3686efc2e6380df010001	\\xf46f63c204614b6a8b8c4b15be42f565f9f47732e325140773d359ecbe5ce6181ce7376050d54d2d08c592e2f96275adb6086017fb1b80be9832a93999993701	1648984807000000	1649589607000000	1712661607000000	1807269607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	236
\\x3d2e03f662dbb6c7f9f1607e9811ceb82dfb88eb422b35c578a2fa6f0b8af96ad047f825d434f57b0976d3d4c11cb8c259f3be7f14a5f51c5615f7af1c83cd66	\\x00800003e5476069b20a87b61725274be07d84c3d97b3e23a891ae1e89ca9ec5d426809d699b99e46dcd6d40304c4d9339d308247e51967afbbf01041f9121ed956e817b25ae43d45607e29c36bc807d1213e7baaef2f62bc5575f80b394b3c5cc9d4d441e3119dee7fba634ba116ae2ccda17d9976d2df966ede98485c98d66096c2405010001	\\xe80cf237b21fb6a34c274fd8b2ee4734a7eb9c9f5a574d380e5324e8069d13438e2f111f37ec722a9161153540cfb6da229b644a1aa7fcff7a8a33eb49159e05	1630849807000000	1631454607000000	1694526607000000	1789134607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	237
\\x421a2c643fa67d6d08991fe8cba981b079da16f756ceaba9e907588084017863574adb7c29360ede1b5e77625e91096432e5d27d2d564f716adfb92a357c97f3	\\x00800003d941e398bd968e6485b5d031eb23a077cbea0fe17feeb04ea792a360d85821ff6153540523947516d4210a3b8e41df56030d0248b39cceae81d352349bd99f0fe142e68a6e6a726fcf84f6f4b7394bb6b0b6e5b2a5cbe42bf570ed0b435cd9a4171659ec3da19f19032edb0762253c87918b6d8d4177c3ab0dee7131be32d0eb010001	\\xc76dbbe77a23207b7a7be923d733ba56a9f2f31f5a0e6742c9c06d6bae7ced931eed6100a4fddd864c5edc4b1255f4ff54a8a54338c6b2cba2dee69177a4f50d	1632058807000000	1632663607000000	1695735607000000	1790343607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x458e8c7cd7bcdab2543a7a0d0f8301311460c88c7336d1d4ff1b929830fb9341b13b609de37dd4a58996bd78e22a3ad0efe94a43d01ffe6b8b4bd5a409b217c1	\\x00800003b54ab9f26ff310b2238016b4655f8eeeda11509f44183778f7cec1510645e809a776ed2e303f80e3d2a2e72f8a7e2a8cb8267634c6c23483717ab6af96331c52436fbdfc04c06c32a44adfd15556a68e09d5936cff4ef088d6d09e58e3fec9a161377aab425d7cc3f319383524327692494713fea37a10d67106c5c5a28c25f5010001	\\x17c4b21f8a7dc7321415492e96de69895829f7494438f745f224c8d1e00d02ea6c31dd2a0e6c2d1a17dd799c2f607b18c82a8cbd28a16a05a35ff96796be600a	1643544307000000	1644149107000000	1707221107000000	1801829107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	239
\\x46ae9100a4fa0d8d208b0e0dada76a85a5647a92507e82780d958fce8f5ad406d064981e804585218c550ee89623927a4fe0567e5f62bdc69f71286f81c5f0a7	\\x00800003ab91c6bb4614bbaef693ced56545cd07f899c76fb5425ac863a199ec318d7d3322a11b8d5815b739f0986df254586f4eaed6d368e4634bdf1d5999807b25a45449cfaee774d8ae6ffe4cf79681c5490cd4a677d621b34f21f6cde91b02536c99be9605b9e062e235cca4e40dddb121b54274888990aa95a4e60843c7a4388b25010001	\\x65118f4cd246a8b47eff751eae1780459b0751e0fb9b1f3878392fd73981a81fc832e6004287c7490406e376d88c075e1ffdbb20687aade6f82c303451fe8005	1658656807000000	1659261607000000	1722333607000000	1816941607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	240
\\x4606f2cb9eedd936e556ceae7e87a4e69daf91f3bbc9993544dcf68c2ad4b19c0a07ed2310bdc16e078f7f53548b01917de13e5ea48ed7069e814db561d2f99f	\\x00800003ce59437c6a332f7a438cfbcb8dfa7e96bc8b2d265f92bd8561545f3f4f5db1eff14bdf1681301a330081a80acd08e5508975ed6bb290bae828d973b02faaa58c75d63c4732d4271ede61bd6fc762c0e62770db4605249d8834c9c68d6744b3e4db4cea0829c8d82d5c73c4ff4a0a6de89cefc28c065e75abc9b164d212ae7a3f010001	\\xb8d1298f621f678971e01a6bb0262354c14444e788dd063f3efcf40c839da1891a5637fa9b86fe137e1294414d1ad00f6d0e36c6ee9a3b92265ac5a1719e1b0f	1634476807000000	1635081607000000	1698153607000000	1792761607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	241
\\x46123b61b5f24a5e98647a02855cbd3ac4372f12b8825fa7f404016c8e9210889d70ffbff76dafa856cc99bc52aee9a809d5420139bd777738b3fd6d3dd21588	\\x008000039dc47f305063e5625e0c0430423977070889c29e97a67ad3f926d38e6d5634a7d742659c4b2e25e57b021a594afbc571638ef1b56181fa69d99e81fb1442367f6dfd6b00e3cc3abd15f59a547afefb4f64ffc8b8e986d594b1fc9746eca2d1456a4078de499e33463ace75fecfd5fe4c22b6d630775c6b7c6c59176b290d67d5010001	\\xaba370085d4e89f905d4ee40d8f921efdf14624857f066b4277d9374d24965b9bcfa849b87b96698fc6927373daa8807a7540408146b1c382dee6ea2d91b3b0b	1648380307000000	1648985107000000	1712057107000000	1806665107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	242
\\x481205d6f04f39ec982108bc3c13030eccb1d58602ecdf68c6ed49a9adfbe8125af2581448999687313fc7964e783c80be6caf2dbe7e1e9f6a232afc827c42e8	\\x00800003c35261040551546efbe1bbd873c3dcd01b86f2199aa727617d2ea5900f30a25518b6477ada5b2fd35040286237cb61a9045c5366d7d12bf30a579bcc902e382da4e876e2d606b9ed7709a2269044a54a532f9c516477d083589829055451c2fc2349500f377015927e2bbd2be91d06ea95d6f0cc999a10293e520adccfdefab9010001	\\x65cbf82f614ac6e01a4321860e479f9bb1032a797180a570963a5a1e5010ab16eef102b3e69e2b03d55d9952ac2db073129f42156be5027fe6748fb485920e0d	1648380307000000	1648985107000000	1712057107000000	1806665107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	243
\\x49667933d825904bd491b0a41e7dd634a48c0978f50cff126364b862ac567f8e60ef80ea4697a63938b6327276a18dc18cef71d1fe80ee4ce141197d59044279	\\x00800003b6218ee417f9d423cb5737ad14f959db1330be4725776ded4b82e0925c76d8d2c16df0b9a369bfd2ab802a90af9efcc2f0e2d831f5d5f258a325f4f27734d691b8d13879620e30b84daa2516f04fa172362fced3562b303e476a627c75eaacc1f4368729fddf93c91e5c5f5bb083ff6e337036a8e44fef77eee4d4c6ffc2528f010001	\\x9b55675643719146a3e1d3749ab8884f12f8ebf110ed88b818adc0d0ae61924bea9f3acf782b2df7e3275f5073dcccf8f7f3659974ab72155ebfe58be6c23b06	1632663307000000	1633268107000000	1696340107000000	1790948107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	244
\\x4d660009f7ad982e95925b0244ff575ad3b7c8bb1c23bf8b6877e982dcb726f99d50458768b32bffd38b5cf72254e07332875eac296a4c312f9db7bf11ba967d	\\x00800003bb1042ce63e33738f90eec007685ae90a9017c38a9a484e3d01ce0cd017d9cb409e7a5798c1fa8bcadb622f869d26151adaea211b925bc289bbbd2c18aaa90b2d76647f57f3e656889cb94268326671cf1d3297ad6c3ac79928cf15926ba1df130a66a6fc1f78d8c838b92ced056020ea916f9f10be97e920431359d809fa0d5010001	\\x226de729c912c57b2b6f85cc1d3443372a8ca659834a21dac73a346bf7217bb6cac3a6200543edc9bbb9aaf6d3f118e82d9f5f8d2499559bb5a5836e15751009	1646566807000000	1647171607000000	1710243607000000	1804851607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x4e8e248d4138884994a9ef9d279290ad6b08b5eb368583ad548bb3933d5b59e20431c1699998e9ffc149c50cc279770735c45ff7d57f24d3382d0f9b2f8c20a5	\\x00800003b91878f5a32f2bc9da534914013d2809840d6a72c18f2fd951c0462133051984f9bc55117d6f732e137d54480b9f6fae6315495c093bd63f986259c622d54fd19e53d032d331319a758b1bb257c507f1a4664ecbbb81a585cc0e171b74c8070ee626d6003a50c9eaa9473df96a5e9c40e851173985747cb3e9dc3b1f0623ebf1010001	\\x017198690f38950018baf94dc7ef4b9ae55c6b72c85b389a31b2ea7fda1061aa5d4dfe49126187881a50eb83a44e20be9233d7cadec2efe3464fe39cea05950e	1639312807000000	1639917607000000	1702989607000000	1797597607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x513ef5bf07f1e24fe33399534078769af2515bb9d0d8746d164e2604c78842a671793512593674dce27e007785229460653bec1c9cd1b81344299eed2129558b	\\x00800003ca32f4abd9bc41bdb166929d97c0d6ec931c8900e18cd46a24646a5f1c7b0a041041ba8ba5b4a1c5d348f3a9dd2dbecbeb719006f9e90abf329203d6fd2bc55e914ae2449c43073c2cab6153ff142924ee8c48db8c3715567a226f6af8a816c8eee3a5aaa552a5576c63653ce43b1571df29dae44ed1fb08fa253279afa9d659010001	\\xdba1a939a7ef864ccf39d73d8005291859e91e1d9e89bdb2cb6ba35739b4e44a240be1c71e737010af34b3dfcb34464dd0bdb834a9d4c921769921d6111d6d01	1635081307000000	1635686107000000	1698758107000000	1793366107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	247
\\x54b2ad1d1dd883bb44f39e074ff9eeaf0ed5e3e73c2b385400dbc6991c76224456094c44cf3015ca93442feef135dd64e7fc6e0a9ace5ede99bb760c84255131	\\x00800003d3c87213cc2c92b78ece142263bec0bc7a75370bd90932dae43e3430e50234bdfe85ea1551dd66e6e4e539a4b701a970690badc2c511a96940ab1f5f4683715f45aef8ea7ae10b649c8ddfc63c071f6b70d7d1bfe588e3dd83a82ea3dec50ef9367c918770ffdaa8fb692665e4af6856a25a71d4de02a44d25ed5e3739fabfa7010001	\\x84cfc5daab95e66fbc6af972cad24a6311a9ccafff3f53a832e8884f4e21f5a7a1f797d2da9fb3c80afed46531ae7af97d0687f764679d3c0ae8af5e747ac003	1653216307000000	1653821107000000	1716893107000000	1811501107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	248
\\x553604b23931ec57aff402ff61f4a8bfb417e42a0e93365b045ad9372e253b7e65da68d72a1081ad4a83decc3e0baa271a204cb2524e47b37afed2a8d5b34950	\\x00800003d06ad39b0b7b1bb4a4ad1c36e09b403d11ac5e0f488ef69b38b393251af57d675f99bbdfb2c16354a79d2cf3c56c072e545c3bbdf8292352f534a0f7e9469b5161cf1d8fce7b794859757e63db00699140e6dc8bd4ef3a231fb4ae2ffc9d27cc399308ec8e319b3e86ac5613d145673659e695e7b9e90bff1460257bb83a4ed9010001	\\x151726c5fb0371f306ab991bb38745c515ef1651774d8bb75a77dec3f56071c357761346358b503d23ed5194729e25ef85cc5fc33800855d5618a6373189530e	1658052307000000	1658657107000000	1721729107000000	1816337107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x5b7e9e34e221a1b7ef6c2c921d367229883b90ba35a718324fb03d85a0c6754ec9edf15f53cf765efc95dbdc38608783508efd64f8f2c1cfb27dfe34f8928618	\\x00800003ddbda7c6c88e93dd356f1ab966712bd137ec50b49a9ca18ab92a3423bf0aceb15e6e86eb39b57f88f8f116250a2c5e419ec8c58dce93c590860d749ee8169d2c4ffd5be92c370868c9f4643d5b613ee80f6807598acea8b05259e227226a6e94ac22d2175775aac40d63f60d6bb4e27e8b6f71151183e4ed02e471dd1ce6c5fd010001	\\xfd7eec9472915559e2137fdeae8a19ae34c8c65f0bd81d7dc6e07c7de39cb04c89adf5ab118bb23ffa8d22a9b7cbf14fe0d710a739dfb52cebc41096bbde4d06	1642939807000000	1643544607000000	1706616607000000	1801224607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	250
\\x5caabbc7456754706301d76715bbedb6b73a3ad7f6d168683c656bddadaa0ddf580b78a754f34038024cb2feca49779634f3093bda3d8fa4895f01d4af7e2084	\\x00800003c907ba056b0df79d7dcfc0d10d660c5d8ed18ec12f70f995a26251360b88117cc7cf7acb55294e73af5610552243bc85c2d4354bf6c1ad9364d65acfc92e32f3554ea259d3df1b3d147ccdde2b6ecba4473cdc5e0162091a198b0c7ab4cb83bb8fa38d63a4c892e4543a049c9ee7fa0341d1b093c56c8a2976ef3be67ff3d44f010001	\\x1ac81298afa705d456ef9ac10bf7ff63094bd5b05726cd8fd97d7b2f0a5a3bdd1f7aecc77cadb8a704c5273c15375a5d3faef41ae918095dad72459b91f2c80c	1642335307000000	1642940107000000	1706012107000000	1800620107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	251
\\x5dce44410478f2334d28c5138d44d194922486b934040abe8a73e13aaa2c0d65bf1de1c3439f093289635c9f2fa351d7b639b59bd59c586c704411140b4f8d98	\\x0080000394134ad9433fc62345629cd4316ecce17c353a63afa11de4145e94a74ac8854504c9f8a8b41351d5891098553cf885694edf5198c1bf6b070a35bc562e1dd4456f52d359fe930ab9b271370a7c876fb52bd84651abccc1a2dee7eee9220f02902e6a5d488497a8573acd2e844b654f949360c042e69d5dafc7d7e8f989f7510f010001	\\xb0023d6787301c4c1bbaf711efac99a68351eee0b5bdc6deda595b2cde4bd962a1931252b670d822384165ae1104484d29d2a8d9206b7b1f883c203dde313002	1651402807000000	1652007607000000	1715079607000000	1809687607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	252
\\x6002b4e9051b9c3a803882354052cbdc430268f0f392e596968e8c00b090ccbd2bccd22e7602cc619025c350abb39efea5ab3a55b905f22e117834db0e3c2b03	\\x00800003c1ff1355991fbd76293f5447afe2b2c4bf9b60de777faf8db656a968dbc77169a861fc9c6e390ca406a42c141f01d6d11e3f66d3066f04d50cc7840f3b5f9511302cb7af65483987bab2f3f710d4df6bf8738c0c43da1a55eb9730f0149bc7babf7b5f9f7ce3f1c185439fcafc7630873be436e647424e6ce749d1584bd3c7b5010001	\\x6098c8df115af97153b956209591d900b6365a200e251a41fb602fc2350c8791d9556160985b924dd1a29875b09a3377d7188196cfefe7755b01959d5b32dc0d	1659865807000000	1660470607000000	1723542607000000	1818150607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	253
\\x63c6d1cf83a9aaae07a1f296f57978d41dd40a731fa6323f01e6967de7341e888395a5b61fcf30b3de64fdb3359c8d40aefdadeb209c1b7c34a2b9608a7f3730	\\x00800003ea0c664fef551325cf61d680935db8de3c51b857c041a797a70ce2ab930e8481ed5e2d3750d991abd65b9551bce28d6c36a31b7c34242c799ea9c81a443ebbf55d1a551395f2c77a8f731ef0f2edab21daa573a608c142d909dacc970abc03349048ba14d8a71a9405abcd2edc40bf49635b3212758802085632535842b3700b010001	\\x87d7e904729e457d1f4804d953bffe96a7ee47aa2efe5228b01b7b628361a46c94061d08291b069e3300b904f252fac5c44b0acb45cb824fc3415418fcf09708	1653216307000000	1653821107000000	1716893107000000	1811501107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	254
\\x6526eace191be9992f3e42fc3cd816963ced51f2e45eff5295835faac46a9b164ece661aad19615fe20f5be20b1927f29781a6af7b694017942210513a310f7d	\\x00800003da7956545311e30f84f7d712c43ee11feb6e5e79489f1e41f41fa553f1bee27793c37ef8418e07843e947034563a55b519a9b73f004f64ad46d944d6dc3be61d858923f25221bf3e8da82090a5369f27f0c1aa6ea52bf02df3c106f55e2383016fac17ca24aba60e30323db11c2f00139b811ce026a81c1527d064a109401fb7010001	\\x8a588f4532e0a79a7d981d95115bed8c112091f87a9cda6a56c07d258a3ea37298147545e6a2bbb8784474cd56c630505e73b7f133678e07c88696cc1e191f03	1635685807000000	1636290607000000	1699362607000000	1793970607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	255
\\x682628803431ae5b9ac2b69eaf9acf8ef728335ebc87ad007351292d40a0570e3940343e008e50d62d5b0487f50b1cff03c247f4324d5353997ed41482f3c396	\\x00800003d1a71a10471b79db5da2210c05cd7f205f9aa12731d7bc12334d4f84e605594b5a203f9375027d3b4c0eba83d1f08adc3e188a112ef2fd176d2b6fc23c5742fa0ba381f954795f6dc0f2c25bea6bf595a0bb697d68431ae1f2837f718584dc7f739c8ff24ac49af6596d5c13734bb6c18d80e5e09a9209fba4f7edc079c595c3010001	\\x1b5bbe1c9187b62a4ff57871bdfc3c3a8831db28cacbbb9a621390740a717f8d236c6086955db55884f36cf4019cc509463fb250304b1183aa90f81b3242bc01	1635081307000000	1635686107000000	1698758107000000	1793366107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	256
\\x6816e7fa432519995dbdd087e5a0c9d1ff837e19ce00b24ae6c92098f59d19258baf7a044a8a83a8b650add8bcb743ca3e39895f42286c13ebb01d53a8bd5b07	\\x00800003dd775fb4679af7a62db9b1e1be98eb07fa2e8131f74c64267defd99a02af68b978b8f835ac60e0116834bed1761dfae237d5c09f917519478e909bbdfd255c6e3efbb82400d9d543eb7515cec9af0ca47427c8fc1a250d9e35d159c72dd11c5375744e178b3e0e5302b6779e4828d1c21259b14a6a42e18df53a6cf5e07e2d77010001	\\x43981c1d34c4b322f7a45f4491123d0eb2700159a6737ff1d92cf39bcda9f9897fe65ecd47e3f5e804e5bb1bb84657cf35ce1ddfb768687c9a47be9260d88e09	1643544307000000	1644149107000000	1707221107000000	1801829107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	257
\\x69ea971383b1cbfb7293e79280c6ecc9cdd8be0ee991843e9954ae0d9e2579cff5359dd7235c21daead7bbfecc558d450872947a2a65a6eae8c29a22fb835ccc	\\x00800003e4f04f82ace050c2d293f03623fdd913af44fd8b3b01743b14bf0116c3ec71941da99ed35286dfb9b8bcff3a7e795f1fcac82ede5afae7f399360aa0a30f0aa8017dbc267e4ebf14fe24554bb9b061f0e5706c9305746c7734050f86c7448c3a684e9fe1dc1f8d0b5b3df8bc1b8caa6eb54df0dad0e689a2668baf775f3bdc1d010001	\\xe207b95222867789cad04459a762e5ec16aa17b46e09646daabadf31089968af998f43aa0308c3317555a2ab2172e83d0bdf209eacdbcd27a42a6776e6bdc008	1644753307000000	1645358107000000	1708430107000000	1803038107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	258
\\x6afa939ff1befb2f79fef8b087e311905620d7b8c1bd839357a32045280cedceb4815d39b759ea4ce13d0cc5443a5283cc87f612f0ec3104be2c11e66153d0ba	\\x00800003b95cbd76046c6a0696da8e90a59cd56bcc0952aa9d37b550eda56f66f33208ef55deabdb82fb21b813ff4c7f46e7f6c9810585f43a17ad685e0e1c9651b96f803790e25a8bf69ea04d2f942c977da89d7d314f95d676a64166edc3cce2a5ccfbb1d0974bd201933388d42fb44dbe9fc187063b5ab947a01718f1b7f519a8cba5010001	\\xee5e3d87e0b3b31a4488ddb412079a1bd04f27ad1582bfafe3d1561bbe33bdc667039c66806c76be6fb41eddacd7a8bd891748f32c864bbce25dfcfed8346605	1640521807000000	1641126607000000	1704198607000000	1798806607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x6b56e36abca314603d37ce509dc6b1d7a4619f31c1e62b2537faf711fbed81611f988cdde3757e5f65e50b9e700cee61f2594a16421dbf4e2bd8f48bbd8f0b20	\\x00800003c226c793c87ebc09ed07e9b8aea89e7c7be65350675fea1d7151832419193b6fee58e3805e9e899478ea34cfd00899c7a1d48be4ce7e4164fa0fbd2205c7cbb18f35a92081b8d7ea22fa6be4d71da3c0cd68ac16a7c979059f7d65945aed15f03496582077caefcedce83f2854f66ad14d34ef63f479a69460fd7939d2efd71d010001	\\xb8cba2c7c8e509d78f67398e982603985b2dc7add9ddfb6a06842219a89a96d54ef79e9f422a4deec03fbe892e56996d7ee16ea02dbd96b00c8c4d4ec75f3509	1657447807000000	1658052607000000	1721124607000000	1815732607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x7c924b8a4b97304b860bdfef9946d64a7f894bbe90c9a98769cd32ba9d511b2e2649e0d51f8b7ab2f202fd69249f4677aa6a522a588f212780c68475d61cb847	\\x00800003c1780b5bb71cf130f25907bf07366ca111b383a2aa2759a59e5620f90c7ff46a563c3d9f6c5c27283f6dbe13521cd1d9a307f445999c4da20180a465af61fe746ce27222047198a0be166686c7b4f42b3491925616370b38b604adac56a035a62ba45e7ff1bfe74484c4bfb5ec0e7765972238cecbebcb0f29f5ae759e561a11010001	\\xc294a0cb12d587de364c94e209e7107fdddabb2974b651fac46b142b3f55be25aeb449e3ab04e49f86decbb9821fe264ef343c2fd375aa03043ae28fa4d4820f	1643544307000000	1644149107000000	1707221107000000	1801829107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	261
\\x7ccee57f7b969beea0499b50d920e2f9d25556d1bc3c80e08494fefa2b048a0c070e21c88c61bd91b7a4c95e93e57c72e248e2d05232618835428b174dd5d7d4	\\x00800003d51a6e1f1b8619a172e1a4abaa866a85b35e53a4650e3990dbeffefb796195fda1189698d5766e6e6dfaf2bbff694a765cb086304ac0c19ab20acf69f0ffc438d1da411c2df7315fb0780711e9422b0e05c8ac38bfb8cdcc66ded3c82f67ccafd3043c42569561f076c5ec31d5dbc68c51d000a0ab4aa4f32b70620a42ff90ab010001	\\x0ce9ca14290bdf7a48628468f6cc7549c17cf32f14f18ac2607310e0f67108d7d90dd873a336635bcd637e50749fafd80676dcf1cdada6bbd0952f732e2c0a07	1658052307000000	1658657107000000	1721729107000000	1816337107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	262
\\x7d5a8bb5a17ba68628c6ea229ec10df4cc8a01aad85f6a09e71e69aee7837f20a031e22fed717f10cc67905eb61d88c6e43df43fdcce39430d737f409c52e081	\\x0080000394f385b743b8c910a2c9ad8f39d294973b464954d41b4f96a19ded2f2fae778a0a451308f76d20f2a8196ee7394fbd6db90120baf3d7b89b4f956c26e96d0cfed23dd85b7767db0d8825382cbb674a3c172ae508d72d85aec8c02bf5e15c89647c8de3f2f1d64d295b93ab99ca3068375e71a188bbf2ff977f52f55ee015a969010001	\\x0d5aa35ad343d207c776e7821a323d3cbf536c0f96dec2ba02e7ce19d0503e149aa4a8c4a80440957fc6152ce8ed3ae60f1209b55451b32c14064c52c6acfd0c	1656238807000000	1656843607000000	1719915607000000	1814523607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	263
\\x7f9a23196478141aea02ca86da28f89ef008ed75459a2a65cc6302a192ab847a72a37202183813959acd90ffcf0c66c57e6f0e8cd64252daa4b704064bec0663	\\x00800003c052c9de4b806541443d84cce67f43c90276369e354d2672b475d91d8e901e4ff5106e02ae46826e4492a2a14fa9b01cca3051f6a0fceb334778cfba88e0a1a26dc3ff05c83084c572731bd60d27d2dff8d2091cfaf26e19d8331c458c0b9e87415a1d1a023d1730e859e4dbfb3aa6d72f7e35fe720e93da10f9d17703cd965f010001	\\x5e37942d24aacd25867d9acda80ee6440d95cf48ac847255fd7e8a22a45c137e34bdf97d12734544b5f21c88a03656efe66b615c4c95a7450ca02c0a14423602	1662283807000000	1662888607000000	1725960607000000	1820568607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	264
\\x828a6e50e93e6bea84e14caee2c4038f297dddd2b92f368b77616a856f2f62a3f8ec6f66ce74b969ee0f5a195c554941b956a7e4d4410c33161eb2f9644ab817	\\x008000039c4ea01af184282f2f96ca96a0dc843bf94c7b2c678f6cab965a660c43f0fc5a42b25643615ef96884b2443df5e8cbcd580345e2eb6810f64a7418ef590241be92d2f0643f481ac63ecccb3d57f3e8e2471de15a82ab292439d0e0cf7136106dac52cdea98e225fd58710186c2e24ea988521b5d33c9ab8fa7be5f08d8dabcd1010001	\\x47597294372afda0656a093a0a7cd5f51f033235ce84289dd0cdba95c010e50437325fcf5034a0dcccf2f8fe9780844845ea02b177ae76ec21a91689966e0605	1659865807000000	1660470607000000	1723542607000000	1818150607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x835aa2b6ad836f8c1476300507802b37522c2749e33f39a8b38dbe09001231ac779d36f3247457e1797d04d8d73a1c988755b8049eaf5df0523fda502c08a7c6	\\x00800003e5c44358d61146954b6b01cfc9046c455b83c6f04f65ca94b3f06ab795a534e26c909eec172fc705122dbedad7fc077e16e188b20e5f9a9e1738d75fbbbeddaa35e0f4299880c73aa9bfd4e998aa987ace5d4bb428946a366a1beb2d3ff46cac3f564319fb80e692aa1bc657b4891f101a72919bf0cec00555535b1bafa468e7010001	\\xe76ad79125c1d504cda368cb5823d7a302a085bd618c53955cf374759c31eccd6e32cd7e9de138727250eadb3807bcc9a07e470dd532e863ce38951d6e5ef807	1658052307000000	1658657107000000	1721729107000000	1816337107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	266
\\x871258b8111d7092acf983ba8926d8ff69771159b3400c9179a3ab15a9ce45004cba2b696106414f3b5b961893d2a19e0d53b2061e928ecd25286e870ce1a4d9	\\x00800003e7131c21f0676d60ef0f1a06da5c107385471155edc86fabf082ed7319443056032d1f98af823c645c3cbfb1f4ea83890187ba23a90324ccc72a3f2e4c527dca93c08d70f6aa2f841db27a6e96b3528dba4fedfb500d91f34ac35532e205b9ef0ef0ada94265632d5298548ccddb94d01005b7bb343311cef3bc983c58da8e03010001	\\x550bab280640e4dc6e664c1ac3700faa59785e8c25015ffefaf6b1038dcd3a3f9f109bd7c21e06c6e5b9eedb5f4becf77e82cbb6626d7c437919966bb2fdcd08	1630849807000000	1631454607000000	1694526607000000	1789134607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	267
\\x887631ae182e9e7186b7b0efabc5c357d9c3a35ad522df6a70df9a2b57a759edb7950f58769ba604cfc919e2a14fd1633cad4f9a09eb8fd9410d664669a14588	\\x00800003a524fc3b961fa2e5993822100cb86c20f51d56490563114296e725153a6503f785138e8255cabed9223c2bc89427130dcde44e25c31904b62b4704e872684f0b09b0c96e0334fca756b71f6a458e3f31071fe23cda31ccde1ee99ca90b712a72042d15e5e35b3c227c6ccd9db8a52e454b40b9162e8f67f9451b7b6529adbf83010001	\\x73357406f717b2bbae477e864c945f8f4eb3bc61788b77af4d7a96ab559778c5c3486c8c172ce1b7231f042f2c08a2ac85b99ff9548287bdb8631d2e39db4e01	1635081307000000	1635686107000000	1698758107000000	1793366107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x8ec26fdf825bf2a84cc02642f9d95be3e82703c1c49ab032d40747be482bbaae090ee4c5b0863b36f5aa990be44a664c9b603ee9b7564574af536f6215ce6560	\\x00800003eddae91bf9dfc32cb0fe94012f2f4f07962f2e125e6a2b9a151bc126af450ac15944ff039ad51e6be89ef961671820953ec8eac1ae0a0596371d2e0583a163b0262ac2791d4bdda559afa58bca4936366eeb25a257add14cc0d5a310e608f45ffcdd465f8bcd2bdb4eb5b0c922257dd3e344f26f2341c37d2d3533b294c59d1b010001	\\x485eb88a8d2092d7d4dfca5ff60b3901384c36ecce21226fe710c103c4fc8572fdd07321d10089da9c664d048bcc230be39dc941861c9f3fa56b2e24890f170e	1645357807000000	1645962607000000	1709034607000000	1803642607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	269
\\x90e60de767015d3f30dad9284d5b0ff843252f1e29328d6f33a5a775bf73c5e88ca0a1fcee9f29bd14ce35908e073354ef577fecd416ff3d3ee4e134c0825716	\\x00800003f8b3eaa12a683ea8fc8948f613d1432c9d237de588a62f5662f3d03ce234871e03e199c0e66464e3eaadc8e190518d9d4b83dc70d69405660a59ac248e5bc2f4648e074905271ba143b5074300e680b36c319eb25f676dd7678d07f0972bbab49cc7973bd096dfc26bd98521855b93b4ded8941a98bfac528fe3ae6583b3fb01010001	\\x8072d0f944b1098e1448eceea3a4780a4b1b9fbaad6b81f9052707e820e6edf1bf96dacca50698a4544d39660cd6f39bbe77a3b2edd19187e65f76d2faa94404	1637499307000000	1638104107000000	1701176107000000	1795784107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	270
\\x916e506c430c0ac4a2336b14ff7b3147b5b263da7228e5d00dc2d40f6ef2290340332eead41c86bd6cd9d7b5ff6e7b0d88796e851db7da748351301867116389	\\x00800003bd0c480b32073c524a1d3ec3f47fa71b17b3c644321d53d55f80b6a873374bc02e8817b1121fabf7e52ce46c9051c24e5895bdbe968962d8cb2448748fe7f8be3ca8db6ee7feb4829932d6a3b92d9a4d58dfb3a47ab31029d37a5e0adde9eab788dd89f791f980efaae6f50966c58b7e1ea9922aba317ccc7b5d2f5d5b304c0b010001	\\x5cd1c6b2298167e28b044e5af44c3280a6647a0e21e6766bb87d4c1240be092a2a76436677bdbed9db193b87c684dcf1791b2b5829d5a7e35ae264da81ed9f03	1638103807000000	1638708607000000	1701780607000000	1796388607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	271
\\x9252050bb91db3338de89fa76f080bef56d786f95fe25c6e9a765dc5d549d4df520ca5c696a8f2b42cc861ff80643ef6e6bf54a8f550c9aec5e69172c2e1386c	\\x00800003df34392a60e7b058dae1c68ae02823cba0b39e64b5ceeeacdbabe71b7420d73dc4a978f2bd1ca2201940c00025f56179a3e16561eb3414632eb9b760f0bc46637766862570964f9286d6aafcba58a59c6def1c9a311ba4d74b584c4f1abad2ddbc193334c838d5acd6d4ac0dfc00688ad8298853ddd456467b4da7da2ab1069d010001	\\xce6776fe9022fe13a49bb5beca871911a39d943631ade62775e3d350ebf771274097c6aea0923077ffd9b2ea5f54d984166a6942510121a3aaa70a004ded6b0b	1639312807000000	1639917607000000	1702989607000000	1797597607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	272
\\x94261b7cffbb566a23bac93fa25c0d3489a713ba6b20d6c3c1a5ebe8b87b40795a1ca97e44cf3c5fa17b13d2e398e288e54c1587d60d01fb7be107afd1c96102	\\x00800003cd801c38debe507c8fa8a136a983c6021959f094ecbd426fc9c0feb7c06718663d2ee27a5d1b5e1659a14e66f106d8ff3cdf7b2560fe7c9c4dbeca952711cf5fbaa5aa4a6874d16ad9b7c63118527c3a63fa7b38602f4773488aafd130941b5d210f19db27bdf68f8c728deffdc909edb46fb7a20039c3431df91f27e9492a1d010001	\\xe2cdac7cbf06652c3fb4a0946c7fa13437abf74d8c0f4b91745cbf51f6fdd15f9977751dd8dad228c82135394ca2bfcbd85065fbbd76c9fdd4c04e1ae6397a0a	1653216307000000	1653821107000000	1716893107000000	1811501107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	273
\\x977eb93d4b797292b3a38dc7e1c41c5ef4daff1deaaa249318f654791144910250aebc3d0b1dbb0d22a594162ed9c6f16ecbb00fa1dec87644ca435e7ddc044c	\\x00800003d83dc77e9faa0c2211c189ea526d40f4b5767bfa92d3c183c3a49433f55ef47f26f24d5a02e4d66873c07ddb8fb6e75d0d4072c2091a2628ab34ba0794552c0f87297d547d21c3670cb142454d8f370154c7f098fc047edd8830f408e67b539cd09da9532da8e834c1e4cdf7336b445d02092e8968bb8a35ba65608a34262813010001	\\x86fc9efb8f78e59ede0a20a5cb53695c0adea616c3302aa90e5870900a300ba73f9a25e92131cd067cbd734c99bf86a953133da583affb43abb2c35f92fb3b08	1661679307000000	1662284107000000	1725356107000000	1819964107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	274
\\x9abaab404cf1ad5943c497aa6366e7a89f55abe0f3db8cab273f41053c6f2903b7143c73712c3cd6ff3bbef455331253f0dddbf3aa539fc566fe61af5c47007f	\\x00800003c9931ea6b9a8775a6ddcd2dcca188a576b6735f2ed5ce024a9bb6e77ff4cdc3aa10fdc72e20bf550bf08d825924d715897ff3f1253fd76ff4c962cc1843daaccd844233b7c55b975247c9a430cba08e3649dd9b377aa0d36d3b6fa246d048c3515414fba392b146ae48e4bfe2262891dddc81e045682261f3bd4bd65da10203f010001	\\x2b57c8a8fe0c6d7e75009f68513b180d6b2d1fb653d572ff1c6681c5d4628659afc2813d80f9e6c49f22f78b40dcdfc00069fd81c0a957d64b251c3ac044180b	1650193807000000	1650798607000000	1713870607000000	1808478607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	275
\\x9f9a65fa3688a00172b9dbce55449427b23675e324fc2c3a9ee62308a9e64ee565d8abb769022052866dcd92ffb3e58b5013e51ac2fb0a7f338d05cc2bb26491	\\x00800003daba1b1ebe45c280202a423d83af81dfdbf37276018ae4d82bc129cedfb041ebf1e3686fc8d4da29e4094e0e7072a6f3b702fae9ac71206c9df9a62b3f7cae54eb2329d61a3a326bbcb855b851423714634ae3a2c1fc65044eea5778e1a6eaa7cd7dfeeb3c1944167572d2ef63a62fda2e4007be528c9409902ebffcfffbd729010001	\\x7f5a9724e25b7ad71b1c3b063355cf5448c0e49b23d510f7536971d9cac6aef56b3caad0cf4be2adff2dede97558c7f78b0b1bce70a951eeaacf701f6002ba0d	1659261307000000	1659866107000000	1722938107000000	1817546107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	276
\\x9ff2edc6e079b36be5936496c8461329495594bf8de4cb7e178a74690ab4f03b4638f8de5db69d25d32680fcba08f5fa9f44ea6db617e0f1ac1007ab3d5256ca	\\x00800003d1a74da85eefc9169ca79268d523dc23a8db2de4b2e2a59f021a565a36735014e2b6f4e4b49d6b6f9ad529eb328441e807ad46fb8f21215401a2427bcc0311588da9217fc5e2654ae96afcbdece24a63eab61e72e7511c325477329d13e0e49afc01aed83e3ec819ced6e9f5db07c3f77673872b0636395ce5aeac69c34144ff010001	\\x6d2f7d6898828ea7c91f57b76963fc4c7bbf71926655289fc7d09ff09f7b70428cc4b8cb48710b22383f816cdf0136142c64436a1f62ea43635c1282b5337306	1637499307000000	1638104107000000	1701176107000000	1795784107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	277
\\x9f66f6bbec78c3b960988309ec40b3b69876864fe8502e1fecbb0710527dec0c13da5517ced62ac259a1c3224d53f2076f31c59367782a11ab18f14116f7efad	\\x00800003bcad0b4d206ae89eedbee02274820bc267ee74e34c343eb8b4e9172448c3f146209631236bb395cdf7117c5f0c63ebcda84a536789dbd4386f90deb11dfe915016448832e321bfea201b03922352b638eb379c200380e0c770e8a2d120ed2459934a628ef0b561ce8a9fde77c06dda2d8791e3322efdeb9c296100b98ce096bf010001	\\x431c96e7d18e318dbce398104a8d3d2ab72d6b5711217ab0a270b71c6d15f7a81d530d6d1e252495760eb61859ef499fd5c6e894558bf85592b01d36bc1ffb03	1652611807000000	1653216607000000	1716288607000000	1810896607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	278
\\xa146a8ccde11156df0f30d0d098b5cc33be50fb70ce0b1a4b6bb87ce73870beefcdfb00c9e571e1ef0c54f53bb585a5e907ce38ea28528a6e1682985e60221cf	\\x00800003c82e198357e0f7731d76e31bcf77e1f3d0f7ee4218f0ac34941ff6b574c30e310e2e50df9bafb5b746c06a49d1c8165298c6fc54efe6bccdccd1f2445c4a589a7172b9492ba0f2fba1a364bc493d7efce892b2f59457c0d570386e0b2bd9c09c306761e3ee967cc891e47b1591d12ced517e67b7c1bb07b2e00fce7adc2b7249010001	\\x32d7309dbd7d13b9785cb1b216163f5f9ebb4ac47fc09551e7598a1251c4a6953da82ca1e31f74e61a4bcb47ae41af7a8cb8b7c59ac353ee4dc7a79728a76c07	1634476807000000	1635081607000000	1698153607000000	1792761607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	279
\\xa29ea2eda348bb9b77b4aa09872e6c116905a87b1c58f14dce39d86df330f09297b45255b3f35d577883bb9ca81c48a35b364471d00a45ba46801c7ca67722b4	\\x00800003ea969debb26f51043614ff1d4daa8bdf47f9a06f73628108e7c1bbf923731ae65186f69eaca999afc42173e4cbc3aa3fc0eb53104b489980cf8cb319c8ec65b16d13bafec3b8bccfec1a18f7ccb8d3f77f8c349be061682c53e66f15a6cd53a4b8cc6f1a1ba201f7e02f1297fd55d06ca526e50c82e1c2c02c31d512a2c00487010001	\\x8fd0c1cfae7053a4464d7a45d3a1579bd99e15a44857c7e59b72445dd6adb94fc9f34c009dde29b85ee24f2a56b4f31806e2e4a01ab30ad5afcfe00d2bb1dc0f	1650193807000000	1650798607000000	1713870607000000	1808478607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	280
\\xa7bece825788cb224b9618fa1d085078d18f067b2e177fd0d42db61660367e39c0b3ccf545c06aa5cac3a9d8c16cd418f379a4a2ef80fc23d060da9cdc5e568b	\\x00800003ae327792b11990bbd1ad9addd02591b087e7c0bc6a4ddd771a1015feef4774fff7feb8297e8a2dcd88265b924395359f305227b94f21dec10bd397913befd8d14c2d7b3dc6291f82a4daadc77edc38a2809805d1b4396d1246304c362f609d0182200e82d300748b7c23c9d03e01fa8ea8572a3194f7acab0a677bdfc171b469010001	\\x87e691ab5b5aba67faa5f8ace3500328cee7c4427c76c54ae9b8e1087065e9c5e08ae4e4f2437870b9f74f59591a5cdbaabdc5171e48732c54a2b5bf09238600	1640521807000000	1641126607000000	1704198607000000	1798806607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\xabc2ca263522d4e1f6469fa7fb648bd96dce3dbc3ac928459a850b4abba89adf02442479f37328dca35e5f0f564201af5fed1ef92ef16a28b966a2f6ee2ca85d	\\x00800003ab58d61b68099a7d87f5dfe98f562c77f89a3f4882203b268009485f345a74729d38051a2e39cff1d358c20d300c87e26638e8dec7fcae26c418d4015645edd703445bc7496a475a2509ef1d644a63bf3f7db063b8242769a5cd9393ce9cf3cb7e0c3e8c8cadf6295683a635f6406d236010256ac6cbd09a81b87b96921cf19d010001	\\x4d8eec4707811893b349009a143f4483d41ef6c8b105e253797af66aa8defe0b6598df44a28e5fc3290187cd3743a00ec87d21f5ba0229a145f8c8357e55b70d	1650798307000000	1651403107000000	1714475107000000	1809083107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	282
\\xadae2f6fc02279cf48283b2ca1851a668d29e45b36cf0a906db8f137b14a2c9b517d4ca0615945e1caf1f18987714a2d450f0422acbffff85c15595556c96309	\\x00800003af1a83e76720737ff96a072336aa0f8851bebb55a5b93b76b9c3da3a29174fad0b011dc384694027260b5998479b9522dc0acabd9116f5623b9001a47ef1c478321ee78e31bcebcbddf3743f2a5cdaf2f4014d3a952862fc9593a8f70db1ae724c1133b8570fb40b411e4ea8ce2aa6f8d77e15b952ffe5caa71d72102c67e6e9010001	\\x4642278f4465d24662809bc4f56fc8c40e8692b16870adccd03362e52db3c0aacc2f8acf9992a4b6ee2e49230408ee048a15fdab48e0edcf040c3bf15db8ff0a	1653216307000000	1653821107000000	1716893107000000	1811501107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	283
\\xadfef6d1d4e2c70fe73ca4a8b2594ca56ec67764f9cca28f80fdf17fc9d17c55d4ba6c92e9e7091f92cff1941d8402ca02b1c2f46c923ec211959cd30d9acaa2	\\x00800003c60f32ef42fe1cb72410248cc5d308e38a34a872f1da37c4fb819772efe46309fd5807857fd098593896c0b0e0776fa78b2990c86b73cfde59cb259db4054f81a8aa49474fdeb971bc035c7b1f25d0f293528e8eef187d1b89f140a9739c8f71bb2fd99b742b790c7b6eba14a51aee40054f2c2569c7c6fb4bd8522cd95d235f010001	\\xd50516c50fd41d1900481968194fece047c13bd998ebdc59fce5d5ecc740a13a690aa35c134b5b4b289e650d1e708538e75a861a9769a220b8163256fe1dc50a	1637499307000000	1638104107000000	1701176107000000	1795784107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	284
\\xaf9adfa4046c174d17a6cf12933b9147dca97862f9b568ef643a1cb901d42984d7e51358fd44162424c66cfe6ac211280399f3a693760f61507b67990c8ac183	\\x00800003a5376101291663218fcaa28c420b2ae2f985fb88acdc0e305e4e600a78200b9ab3e14a01a8e8c04d7aad0b66bcaef3584029a49cf2335cbc4923e9e6f39701b0003536959a3eae1f178cccd94a4de945ed6257b911e9a27a198ea798b6f2cffdc3ce91c1d1c123d180ab48b1104820b13e3f060d2988b0dd3119542a182b1889010001	\\xf4bfd76e9cb9505cc123a365da1d0a1edbb49b93eb85e2cb86630f794afb658817553dee2b2e29a53afc4a34f2ef43bd555f2155ce81c9b1e840d4601487260b	1638708307000000	1639313107000000	1702385107000000	1796993107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	285
\\xaf469ec7e522125794d062f086804c402fb285d5fab13163270c7a57fba5fc8d2340382d8a0aa97127e9dc67e2f87d6ed1939aff5a90a7e5834d10ef872a00a8	\\x00800003c8a06f818b50f4708a3165a99e6406271992467cb57f833520f45e968314ec482441cf1b4b16dc6a9248feb3f4cbab1b8deefd1e0f945d9127e66632c1df562f4150093056c25ba24aa1589fcca774557164824b4461f5bc3b73b3bed5aee0bd418d4e56d924718f2550bb123376cdbc5a2a1b20e91e4f883e420298b8784b61010001	\\xd143e22c6d515600ed527a0eb7dd3eb1e772b3ee5e86db83dadd3375f06d544b2b79727b42e6553e701c0cd2a646757532b410c34908f63a17c73282e6ec6100	1633267807000000	1633872607000000	1696944607000000	1791552607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	286
\\xaf56056bc40757730b033f619f3fc92e0c5eef3cacc408719dd14c818b73c34742905fa8b93beb0e0510ee0d10fcca72054cf98a418177045ff5c007f7d4cbc5	\\x00800003bc73bc6ea8582d6c8ebe740a835a63456f12d972d9e66eff02b877cbe15219090183d7235357f0a609be3c24e093c20b7629fc96c40dd5934df99fc44726b8fedc71edba371b48fed7ac5196ffa045909e3fd36df64a967dfdb8b12a7d0799b4ec0a91739a0253d2c751ac89836520e627a5923a8408c837244f22d558350ef3010001	\\x98c90b1fc6ee8fae3826c900e24ff0333834d0b0291b457eb38686911cd20966faea38fc0fb77e29819b7b1c79f2dc1612317e6d620809acc52a7eeefd940f01	1636290307000000	1636895107000000	1699967107000000	1794575107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	287
\\xb14aeec53ce934c6d32becf30ecf7507f19109dee4e78efd0df2ec407da5e500e50c35ce52a3dba3e991f038d74858e2c7ddac43c221f3b098de48e7275c09d8	\\x00800003ad3fdf9c489c05d86e080a8980a23918d104e778675db0a7467df874121886033ce1ed0acce59bd134b72279cb03adb3b9e8f0e8e9e5893e328351475686eb646c6d5bb549bf435ba581aeefea369c2522f063fdb11198bc6cb432845ddc36c8488308c59a1c50fa56080694e453b4875fb5fcf4990b35bc8668a3163c747f37010001	\\xb76b746382c6102afbbaa9ab1ea901fa38ece434b8ac5d6478e33bf21b2312509041d85f0f62b4a7acf50756d82656ebc9e31d52638318177b1045e1d04d3b0f	1651402807000000	1652007607000000	1715079607000000	1809687607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	288
\\xb15a82f2a89951f813f48e0c4fc983763acb9453a8b821545eda2287112f7aab929cccf6a70574dd80d285a04071ad8aa85cfc5f7a5db9f65302c9167484d561	\\x00800003ceaab167c137692b8af2af852b8c31c0292e498eb03f4c096166ac8d4935df82dbf799dcfd71fd3e2e9409658efc0ba4ad54b29ab84d080d7ccf27d21c44e5a9d6472de177271206152f801a922a7bd6e987cb7beb5a37a03b125d609614adafabc811d21bc3393b0dd484e38ad9976287afd1cd8f53a93f3ec7406f6a0c8025010001	\\x21b9e3a174707e5123516971f1f1d350fa0e8b18d31695f8a52801d31fa499230ddc5c3c5a01da38de4d895623ee7ffabd562ff199a37ff7e32990e176fa3609	1661074807000000	1661679607000000	1724751607000000	1819359607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	289
\\xb266aeaef4989322f66cc73a6e9d71e82b25b6a07dfef50414fe337e69158307407452f651e603fb330d05a28dc2dee9c389a3f2f0a8f42c0f5392654e2e802d	\\x00800003cd110bda7aec5cce9bbcb0061c9c3a97eb4d785ba78eb39b1261b54269b0ec9843baaaa606a1f8fda5499006a814c0e3f2ebb1b325a6069572bf82cdca9928426969be5b10342c64af578f03780f1aaf04b0678c789314b2694de1b8329f3568045647e944887fcc1ba63c051f542267d7b39154a3c23139067395abc0ffde17010001	\\xfb5e48b571d3e0ff7f212d715d6fd01aec4bc8088311b3a34d3286f61386cc8fa1db19bdd146a7f48fd8e0193775bc15df3152c5a2a0b5dcc61630fe9ba9fe0f	1651402807000000	1652007607000000	1715079607000000	1809687607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xb852a882560b7940b7ce729d41dff70312b297bcfdfea4c8f2426946dad2cab8168564255f89b7a0fe0ad10ef4a24a55b5fc6a4b4e61157c600d45c0c653657a	\\x00800003b888c50af0a62f4bc01e93522b1bf54d910c1dbe019e98fd022f89e8fce3549618b1cbbba09056d359453883743127d03633f559c4f48c7ed49eb41a204befb61426cbf080c7cf82368aad0e072347b2da9113c68d718f0e11fd48e474168d6e28c592e8801af9ce44c5e71a31e4367a9a647029b11d1fd8f0fc599dfed8a5af010001	\\xc91181286e5f34c33f12f9034230efe1ef528cb7761c16a51de6fa2e3550a320f6bf976853ae975a89aa2bff73aa7cc2f6e565031e0c5de7e00da983ebce7c01	1650798307000000	1651403107000000	1714475107000000	1809083107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	291
\\xb9aee51773cc6030f672efb0b6dbc7663233dbf1f47711c323909d7125cf38d9fc2f541bd8fa74da6929f8edc85211ebfd979f75fa02fb6678a3fbd4c36bd6c3	\\x00800003d7b66b41214d21d2968bb615b4cc490539b3e23dd96f161bee9a5be175ae341ae04c73873238289c295b2e06983aefae38d9274cc64c13b214f0389fb03b4834bc1c61d8cb7a12c277de8448c7c1a5026d57d1c5ff0c0034ce6ae332c41bc92726b6a8b6935457efada85155f6bcdc31a8ab9fd3498b80cf5fe89b6ad63bfb8f010001	\\x929091a41a406635594e3eb1fe1b58ed3891dd9370b08816a0f31a7e2fb189ba2c0f41a96490f05e6d55ee799caa530e6d851a69d97064ed496bc237a3203609	1649589307000000	1650194107000000	1713266107000000	1807874107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	292
\\xba42f8f7a5349e6c98eff385a3579229db477577c67c16bf1dce8099011be583561366ae0b9f80109d3b5a83aef2240fb8be64614542cbc29c71338dca556554	\\x00800003c3aea30b854945fdf6ffc473bd34d3e5f674e038e03c7c3d191184cee526d04fea6a920eafc259d24d9a0b2116f9d15457b464145442ef0395078abfff812d529436a0f74b39adfc0da3e4e2357cc1c1db92cb844eac3dde45a7875b7a8cd3ae552e8a9323f2af7ab5a1d7383e53abb01766dd6c2957fe4708f45bfa72e42769010001	\\xb04c98510bfcda12485819148b62201264fee9e66d7f8da5614856f5e1cfeb1fc5b345ed1c9098fc1e9a62de34df9b1209dad47f77bf130f792954ebdb536804	1656843307000000	1657448107000000	1720520107000000	1815128107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	293
\\xc486bd643122346d7c73961321488778a5ac9dadd38f727ced0c60bb62468ddefb90fe85c1dee6ca69efbea3f5c794a6656b2ef99dccc323e20b2647a9af39b6	\\x00800003a2d24cd10081d1e7174ad651968c36e4be73f347f0d5b4212c7a501f74504a889ea082a6bbc4a1bda4b6c6a6a8bf1776a040071a7e44b7f715d4d0b53dfbfd990f5d15f4b6b9f034909ae3d144908dc2cdb08c7e093dd976e4ebcdb97e1309bb5d535f1808c31b6238805956112cfd0a39c5f5fa4fb624d63faa09177de3d875010001	\\xefe7a2e87ae0e6d2d875f866914e3b958755c3553330a0053fc6c58e5cb2169b71edf2039c835c730a62ee85a40676f549ae87acfa19641ce8d01db26c396407	1657447807000000	1658052607000000	1721124607000000	1815732607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xc636d25bb91f0ad929a3f20d49561d9b60abd7103912c7f97beb8a926244d8f8c9c456342d66cfa89042f11079c80792fd9ecf8291d71c5f7764beda37d6603d	\\x00800003d7a8b2d3ade72d44ab76d3373ce3240c804b2d99e5acd3bf68bb8a6b034cbe2869ff7451ef230a121d78ab8c690488cdcca37e3d32f7f238297b6d31991b18d5c2de835715c2d80c4e3a3c57243d088f366c76bd841f279da1eac701db3b175924d6d7237b7dc654a64ecd9a37015eb1af67c64f80633c8023581f0f357c67d9010001	\\x6aedab710441f120756c16d5eef10ef44869f9e4ddd841cfc4f43bfd35742cdec856be0e8242f8b9909918a6bef58e77b7f8880e1b0da98332bb915645378e0c	1661074807000000	1661679607000000	1724751607000000	1819359607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xc7badcc6257b3278c1cc2cae07feb86ed047ed20db38f4742c4bcbe1cceec8ce326ff9e1fef88b5f790bd30420a429d5fd47b11393403549d7a516aea57547f2	\\x00800003c12f7b96b1675ea01dd2bb41245059a4ea5a0e8c340f8a9a35c273a5c0c0850e284c5e5610f9acec988f8a589d368ca98c06fa91e62ea43e78718bbe3d7db9e9472779ef2bccb16a769c1c27dfdcc1739c12d3eba86a682d84749014d49fbdc156a8de2140806c2894b1836280f33ec837ac519c5ef860409163a969dbdd21eb010001	\\x7104e6add06274c50198aa3cec29a4b471403e94c00ae9bcf7cb304870532fab8de4f07ae09f05aef317e2f590e9df27a3cd9aa510d295a65d04d2b1d6142904	1650798307000000	1651403107000000	1714475107000000	1809083107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	296
\\xc912e87dbf3b9de8cb6a95da72410c1e51f6262e22c9107ad17cb6e4acec4354bcf6f225a3584f91fe13a7bcf17c8cc1811bea6d1e84469ba5544eaff347a371	\\x00800003acd57f60b0dc61a69acf78db3ad6f5b23c988c3229b95266270a19bff241c409fa5b215a79099e27cd2d2a402101c8ecb52deda1fcdb18f4b28ab734755fc2a0ea1aaf53d490fec9f4a6d19067273a8475d762e86def4083c9be0c654c01a28b13c740f748279c771209e8a713ba142a82d1b578bc0f065765793f6f0cab491d010001	\\x08056d27a7374dacb935cb84d7a07d2c28bb9066bc1ff9ec72d485a15d63d2ff2af545e4cb403968e18145aa1c61e84d9565dcfcde786715dcbd0722e6586a0f	1655029807000000	1655634607000000	1718706607000000	1813314607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	297
\\xcf166dec7a12a6d37a5aa154247c84a5ec78f766c9fb3e7fa8dbb3000b978b0575bb1217ed59dd01e61cf3aeaf47be0cffd629e2512077e7a7dc423d26750904	\\x00800003c891d401c9be58194277d96d69a91a7774972ebda175880473297c52996c4df5107a37c55b8c49cf14a80c7a9aef4963f04c2e798ce1dbae4417bf7404275127cc6a1da8e6b681d96face9e99e4c45abe2b39270d15bd69fc4ebee6264eb3547ded0a3e8ec96f0b5792b54563d8dccb1b5a77a2153d4effadaeee668ed061865010001	\\xbc6db9c510fbb49b3e225cb06e99b720ed3a241f02a5481bc116e968e789755de2fe7a7595ab9f7d967c58d5c80429dcf0d1b4c20a848a5f5c2ebf2e7d78ed01	1653216307000000	1653821107000000	1716893107000000	1811501107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	298
\\xd17efed7826452dab8aa4006f1d03de32272778b32ccf89d39b2ab35c4cc34d1e5965036a5e0825890efc55d726d33726cef00fadc3367930a5efe652cffa440	\\x00800003f8118ea17022ce2b6a46ed20da5b4dcaa008c1367da151343bbd8155136501820fab34fcd05175672ddcd1ba113cb5dcd8d0b080b54f5670829a364dd782d31c4194c24af48ba8edd9752198ff587e385916aeff60e6f0e2567134f1f7cbf2ff25c2f32013307528c5d886d4ca7df408e6000f186a7927d17dcd1a797f25a37b010001	\\x039ad2996ac5afa0e72ee14159c3eab7193ba3fd8f9a75f97482620a8aaf025f86f1d5e17d4fac04a825be8abadd1f16aa61f7f11fe993b3432ca98907986e05	1655029807000000	1655634607000000	1718706607000000	1813314607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	299
\\xd4c60701e3b55b8148f051e6899a1f69045350d5368156958bbcbb282fc301c627eabdc1760ebd1dbeaa21427203c9966e032dfa387062d35fd713ef45d60b31	\\x00800003aca9989d0e3907cda5a17b6fea949bb88677257fdc68e61493b07dcde632a0e08d0247c9b345258baa0c2991f8edccaa289b016ad1b38348efd551370f1ab71b076944216fd5cc092cbdd61ebdbe4bb8bde6fd5eb8e7c63c90a06f5fde5832fcb87439e97443dc8343893ac8e265c26a016e8aa54ad3dd858a0f48b1fe883165010001	\\xb504856d5d5820267f690478fe11caa53f540935c06f3c60b2f3edf2377c4b6980d21ea64531864112ab5359f362c03676332f21ee588b8ddaaf77b11472970a	1661679307000000	1662284107000000	1725356107000000	1819964107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	300
\\xd5727b05d7ac78c5cf9f24b47166431949d93d23e66a1d7647f918277538b6cdc641dfc5d39e903ed1a242672a84c516634f0ee650ae820312b187ff8eefafa5	\\x00800003ba8827e1b1b68f8dfd7437be2416d0d0834e54e87f896c73eb7a54df92448c3b3082ebafa0e82d866147dcdb186dbeee0557ef4033f6610651b7127b0d48a899cf1606e10c06039e4312c19249e844d59e063864246c110f3283f7a9ed23bfe75ea59596dcdcac5772a66f51aa42f079c360d66ef3b2a5750797e0f3914bf261010001	\\x85234d5089f9eb26c55eeeda22fff25601e00fa6dc4d4db554ac41352f070c6bf2b20e8d934ac5e04f41c8e59ab1aafcb9f2caf7a27a6e9914bf8e11062d9b02	1644148807000000	1644753607000000	1707825607000000	1802433607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	301
\\xd69a6aef87f8ce2f12e39250aa1a75176727da7d2eb500402a7bc5121dbffcfb5b24d5db9db84836655e091b3bc577721415075d7c42ca3b03066c5ea98ee0ef	\\x00800003e34ef617e8d17701e1fd034d73b827b7dd13b67d81af6e4074a56b4480095e3177e49c899a3c6d36deb73a9228e330972ea9bf3e73089e212ad3bf54b489f2c1395e0c2fa26b8ecea4f7c5e7cc03e822ff5b93bb9ca0b3b9a63eeaa564e57cb0981b9957db1bef4137b37f4b6d09132dbafeccca85fbaf05d357af461815a11f010001	\\xcf596de57ac3712ff6ce06f4f01c379752bde16b57c3baef0a89f13abcb4238d0418dc772f00cbb13c227d9818692d44b1e3cece255e86e58c1eca36f50f9705	1635081307000000	1635686107000000	1698758107000000	1793366107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xd8e25843114c5fce92d161a70a15a17751521b0ea1655ca9bc4b67d93fa368307554519eee16fc7e4d5d877a98db048c0b19b8f47f98d28c67f32f043515787c	\\x00800003c6df6a2c3420de1d713e01e564193d32424a5fdc0b2ae9d6ab916ed797933eaaf01c5c2ed4dac21d3e92addf851ed02a35a99ee4a294062e5ea391f33cf0edcf0657d033be5f297e55963779ef8048e3427a01375bc4ef1e58194f54e39939dbcc672a33dea8bbef50162a616672e0ccd0ee8685c4777151fe9326e661be9b6b010001	\\x7ff4c918e1e188f7044aeb04b6dc52783bf960254cf7710c7f2af401eda7fa3743740fc6994740cf63e31735424802f50cc427676e7e37b8b7c9ce2051202903	1636894807000000	1637499607000000	1700571607000000	1795179607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	303
\\xda3ed4038d52107a0815b11094480c4a8523a46613a1ddfae4c8190076f7703a1a3ba659983143d3b1772637d5f73ac1a42bf4a31316242653bff73dcb2dfbe7	\\x00800003bb0daaff6a6ac34b4da2bcf899a92a1ff260f9398c7643442b6d3d4bd2f928ca3dedc439d721267f2e2fa1d66a2f5a261e2db164b2d9445e7128d3bc788f597ce841b43ecc8ff83cd92d278c6f6621c2ee66aa8e7a52e00699d510e2e91d3490be0766467df80edfe6e5dd59d1e68279f2d0e23cd2e80e5aaa8ff1643de5eb87010001	\\x4f212e7c8418caf95b53871d0b2daabeae911c81e0632e17a9ada3d75e2ee7e3111f3740576a6d4ad8ed458d0af1cd6dfebcc1fd1fc06edc331daa8396db0209	1645962307000000	1646567107000000	1709639107000000	1804247107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	304
\\xdb7635586671e8f7658a146303214d32077d3bf135b992886b4498f4728aa2a363d45c39cadea49deb18556c72aa0b3cf0786e62e755adeeaed6b5e1515a71a3	\\x00800003d8cd14d99cdfa0b2bb384aa51ba45939453f7f16fdf0d0eb7522bae2493925cfd2d4293377dd0e407a9bfde2fc8ce67579c6d8ff1e73c4154320c08acb2d65a2a6c00225e0e4e5ec1385876acc6cfa2dd6df519b4ddc46f76e85dae2a9ff241a92e5a1db2c4e6b4e694b1b8c5f5877e32875a697840100edb8c414e27ea604e3010001	\\xacaa4975774905f67ab1182a9b8050779b4cd13e62123d258bf423c5d0f75099b710c9bb15e1ecfc30c8b5ced3dd998a3766539f8495c10dfebd7f53a2901203	1634476807000000	1635081607000000	1698153607000000	1792761607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	305
\\xdd6a7f87ad64b0b1a3fb60dff1a08033d3fd5e2fa06bb0fc5c0c3429b7eef40ccfe3e8ef5e52dc9451ce455bb49c9fe9873bfcee0fd23fd9e63e5c80c4b96178	\\x00800003cefb95f7e16caa5815d5cb9952f03a9e2142612bb7e24ddca7ad07cd7076793db0346fa25196e2f9e80ccbad60903f19ec5bbe2435c311ed2aa98752d0f08d44bbd3bdf299ebc13746c2245da5a0c1b41d8efa033dd7d5fddb798a9cad77e9941ca499cebc8b4fb6696c72f4ed0dd4335971378a8b0939923fad627fc39d8157010001	\\x09d60384e1479d17bbe3520e029c8cdbe2f8b8a701ed4b356fbba6cbe6678cf282657d61169746a282f64d67beb1148d4de960db863feafe1ee5cba2fca3ce00	1641126307000000	1641731107000000	1704803107000000	1799411107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	306
\\xe1a28d641926671fc647754dbcb6297a12fe9731c0e7a1561191804727689033f0786377edc0723c844d8cfcd00150fc5b06f2499c4c79eb800ed0a1ef89ac52	\\x00800003b405521e4bb65fd0c726ff250c843443c05c2f88be82397f1904054015fa76546593c32c41983729db02111f27e2bc51c03ccac2bc7ff90b3a17b0f33c67f145acf7ec303657d142d51268a8f079220a391339dec76016197fdf51bd23ec9b93b7da6094999fe31108be0e82fd19df98cc77776f47843e60306e27001c86bd8b010001	\\x29d38ba0c957761a3e13a0033ff4a74b8e265d12abdd19c11376e2bb40ea05cc61a51b67445b951732ad5d4d243353edcdd30c240371f09aad2d209a4a92f201	1641126307000000	1641731107000000	1704803107000000	1799411107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xe5b207ff6cce2daeb4eeaf954fb46e039c56dd90d08ae72dd1966ac5be33e487af4650a751307612b4781c59a41d45a374e20a4a4314e735df6f4bd75908729c	\\x00800003d77d64587242db7fa1001073fdc73aba40e4350041c648987fc23753464e8fc2a5855bc7b6ef5fa8d2c95487a9a9bda7efd9a04ce7cf1b035a2bb24181f9a877052649e3e71fb6f2743847beda53a933e0826ef3a42ab728ccae04ad3083094e7477016bd9f8850271860f89ce615e734cbb3851afcb7a0f80e90cd40c3a3211010001	\\x100e835a440580483ec1f7779eba95a6ec887ee8242b4c85a79574f3095c871b3d2f841033a3acddc1b283bbf33120f0daf017a1de7a123360d4b32cb3008207	1635081307000000	1635686107000000	1698758107000000	1793366107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	308
\\xe57e88bd273f187d284593e4930afe6e6945a8d3b3f66194d47e51083458303ab3113af9dca6dd99bea36686b2a031f748757a949766c3d55c1aca85a544629c	\\x00800003c636766964db7b273593721e4985416e0f508ca41aa96f718c3918badbceeb63bc5116477e75ff5bcb5cb9aa8b87c5af1fd3ed791f78361c50ef5ef1db294180604dc43723648dd12ba605847f617845a57f29e8836c5a6fb2a4de8864bfca1e900e85ef369e0a75ead67b5eb8a39b10ee4f0e85b1f36fc9ef2e5cbf75e69ec3010001	\\xfac31abf086e1b1d7d39496de159c9a6fdf47974253a9d30b1539189963d58992b334c7b3f327dcd11e76273b14a9bec8478f73061f0db9141376cb1ebcd6802	1647775807000000	1648380607000000	1711452607000000	1806060607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	309
\\xe6323a7fd24c29b364029d07d3219f1a968089ff1b616aabf4341108887124afab74b63f5433b39545d2eca73f1b63e4e527139c5e0fad22d4f6cf599322edf4	\\x00800003c31746b7cdcd4f1020b45e14f24d72185a21b91fbf2a2c3aa0e201d8a1a9007f13d89ed52897f9c05f5ed125116a84588bd2c6f4820139f5a0203d8886fdc6f94911a8fd06ad9005abd1cadfda87fd65718d39f495f56e20c903b19bf6e86e4c06f6299c67b0aeb19c26a090ef6928de0e7e3b4c87a2f849899ba7fc9030afa9010001	\\x0869490f2482db426c6cc85703bdf3d9013a2713b4ec161072b8ec521fadfaedf90cd82fb4dcd8b2b310ec20e921ad62dfb749e3a4636a93207e055e26144800	1642939807000000	1643544607000000	1706616607000000	1801224607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	310
\\xe75688de9eceeadbaa60b5df976fe8cb14ebf913f6e17359b3279750799c60c4ddffcf2a5511122fd073debfa92ad3b9120b1e5a3ab13479e148a2943acec6d4	\\x00800003b0f176ef2b13a4e018b45d1a17042067d47ba8189d28a9078d1bf877f3fbd6a475d31af98457f69767948b3b189d82f1eb1e5de05dfc1d7c5928c2c15242b6d484d7eb7aac4ba3695bb53416ae63ce158c9ffe47d62d4f59d7edb4c89916007625dfc011a38e64ebcd57a9847304b5d5205178b92858b15540f34eade61f3081010001	\\xf51d9c9a594644abef0c831462ec7d184adb9ddda8966053e7d54c29042cd53a2823588935394875514b1fca3121246467676093557652543489e278dae31301	1647171307000000	1647776107000000	1710848107000000	1805456107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	311
\\xe71adb28aeb1dcc5a596da4c666b1e57fa95f612a1378a2c6798ab694d72383f1138fa48a6b4452c6e0e385897742005306cba3a542ed55a0e1d7665110d54d5	\\x00800003dfe9e7950494179282f5dab5c3b98927a32cb211ab155f476d0ad9d38e5079e40afe4fa3fa845da06b5dd003d243e91f141a11187b8e748c472093bc9410656c890cf63dd1468ae0249b0b40b59fda41133ab0b92dccf2b2b9f12e8ebfed3ba188b8eefe1ae44b55110c15b1ebeebb36bd51fdf42007c96df2af9aa98efccb93010001	\\x888eb95287a244b493cbf98ac36444a377bc098fa844a71fd6b4356a3b603e60f30c22c05ede35a9b356c648c98c4e0e6af9a8f46d2d6be987544ecf3f77130e	1646566807000000	1647171607000000	1710243607000000	1804851607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	312
\\xedfaf95ad6432a4a27b83b07a5aca3b19729f9ac327af657199b24931f4b39a9463d08ab9f39a21d390e0e237adaab910e1528c84540a27707441b3061131a1b	\\x00800003b0016f16c3ea9ef795b4f85128c20eade25707fe9694a73738b1d53354eb40c813bbb5867e065382cae5e1070994fbeaee28e7692300fcbae4cb40206ee26d1b886403d616ca0f3d6dd5689b9853a55145e8308f95b4e5dffa8f65db87cfc5a4b66075d56f6fa9f27d7be45ebc1e50b347f1fe890496bc695dcac4ef288a49a7010001	\\x7f21b63fca7693b17bf590f2b6e1f23798aa2c1d9a6dbccf3e9f0cbc0a255e0c8a848b97c72f9d7c44a48d82b377ef724ed5abe7a3b273b438242f96371eb007	1653820807000000	1654425607000000	1717497607000000	1812105607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xeefa23360eaf1ec94b9b2f69d8cc3c8cbb6daca06889df0553208b2749b5897b863699e61deaa76623ec1a6191c789a978f1bb3e94cd256e2d403d6bee265dbc	\\x00800003e4d7a269c8ec008fda9c395e29514bd3ab540cd71d891489d5315e6ac4ff8a3266a65753d11f230bb5af9c792138a250d6e093bcece3738fb93496fa1545693fb5815742bfdba72ba473c7a3665ef385ed28b4c38956d59e9b53c80850d4c0c2fae4e0a15b36cc187c170dc2940e947ac30942239a4c699ebe2c5b05069f083b010001	\\xee9394aafc066472090668ac261760d988625bbef9b42c47eaefdf7b42a67c6ebbf6ee4e39c219fa2535dca512cc000fb90b0ff8b40117e037b17ccf80ef4406	1658052307000000	1658657107000000	1721729107000000	1816337107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	314
\\xeeb6f9b9d421587bde9c6a3a62fdc8d43d18cf120c352a40b9908526fa1eaec6f7eea8c8c9444662cf8ded885ad12728c31fd2a38c0cb98188d23405aa4e3195	\\x00800003d52b73a2aa2266d04c3fee74b77eecc49f809f17d89583ec4fbf37c00c5a6a1da8ab1fcdb0bced9a58169989c98baf5597490dde8ed907b5314b3e158661c8ef3fc187ab07ab61472587008014c8f82e7f4e2bc0f00720560b1a61d5a892144ad6e7f4d0f00ada7ea659a27d9a9a79225b969bf07024637cbc7bc7177d271a07010001	\\x8836905076cb2bbd4882b07f0cd133ba6d2c41728402fb134f96e594bc65821d16d751142246d3ac0b9e60e3a438ed693a8de8109c05514a25c2ee08521ab606	1648380307000000	1648985107000000	1712057107000000	1806665107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	315
\\xef3e136287e6e55d6eb120a5c2f8599533206c867153369b38594882f8fe26ab0d867758eed9126324a73025218ab951d3549f2572209da9cc8bd5cd54e4e143	\\x00800003af16b037ba9d383498b8803374b3deb79f615db34ec293f2e66171a4796f40d3903e8a35257de9050c96aef5c2fcad1a4b4becff89b984c88155ddfa0e4c5d612a2f4f46c8852959086a2c963681640f839f53cb83071147012c8b34194ae242ac1901f46acb763cfa741b32011a9052d882fb98924446fee55a8f8bc5d85c15010001	\\x9d5b3b3997c1be31ad4734f77c108ef81bf1681f1a52b031467d889e7682cc23aaa7af130790634bd9fab0c6639ce807426cf11374fae811bfd4408b74d5a709	1648984807000000	1649589607000000	1712661607000000	1807269607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	316
\\xf2c6b736132315b2e1eeb905168de5ab6f614209d575571c8729a82d4206576399cf8ffdfdebf245cd18d24b469d1c3b532257eb6a462a02bc88c40116ae6add	\\x00800003c05c59e023932e1850754e83acd4d0e5030e623ed1d749bbd08aaff743aac3ebfcfe11c274e7b7d4f39d2e357958f3d91d1f132ddfb99c6803d87f82807a2f75b0b446b0205d806dc4963b2e71e0ed73a226d3a1dd6c7528fd85b6f35557c552ce84e87dc9dac0dfc16e50150d063eb49f30a315fde794e817b5af21a6e6ff13010001	\\x810cfa1a5af1c761bb43e81edbed270bb4464612e3845915726242ffda27612aff67c1759ef45422a1d705ef452bcfc2ba3645a43ace7edcee3137a28d7d9800	1655029807000000	1655634607000000	1718706607000000	1813314607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xf2e667017b35d44ba0c1486a39d991b5edd776e300349e0900cab95312d0339fc094247a202566cf05f01a5954b57d5bdcaf86fffa1989bc6b2a19e201c92112	\\x00800003c92c2f9e8ce077a3aa45aacc1efbce0a678094b7b482818f013ac20b1dcd4f11dad632f95d364fe5bdbf391fe1ab1ff7f09d63444ca71c729e3bda4ccc2003ef47988ee1fea499407fab3d74aa0d090f83e1982a506f6d8566592d03c1a8ae55e178f1bd5cea19a7209b7106ddd5fd09dee82e7f9160469af673d16e79f37999010001	\\x6c02387e08ac8257680173dca8916444c6fd8596bd65ef9a09a3f8a33943f6cb43c325ed1d5a1cb67eb6c65af881e2dd7ce817b781c80170304b024d46304806	1652007307000000	1652612107000000	1715684107000000	1810292107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	318
\\xf3b21b32c24d6eb69291d20dcf551f616a1be6cf986af542612524fd7463d9eda9283fafbb2bdd6aa049d627e945f0c3f7972c17d06246826da75fdf3a35c202	\\x00800003cb31b6232dcb8567e738a2f35a29466bda8f8c8e7dc8a417f1a1975bb55f33c9ec075efd2955aeaa1e70807f66ba81e8ad9b374985df9b8433615c17625c18d0930a4ea9ba6bc6daab45f40060c1c13645d92c9faf9e0d0bd8f0eebcd4c09a9f2ab04314e5a6ab85fa1240ad208b47f9149071564b7017fec938eb1c303a51bd010001	\\x9a7c5e9b0a2724618a50533d702850ecce9be39fce5e302fbf39781a24b09fed57b57c297e80c7f7aa0574b99dbe6879c14b89052dc55e6f722e520426c33d08	1662283807000000	1662888607000000	1725960607000000	1820568607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	319
\\xfd8a80aade69fe1f658ecfd029c828bf589d336d891fbd9e93b707985ab9312e3cbdd5777fd41771687bacf8805f4eb513b00743f471772494edbc7a885e200b	\\x00800003b969b5236212788049609dbd9b8f62ed59794dec77eaad774fcc521a58e25e2f7d80b98f0fe1c30b2e8100de8baaf57aeebe9260c8da6f65302848b39bc7705949b1b5675f69ae6ac6ead4576fed60db9ed1ade7f049f6953373af45574a8b46240ad32bd6a847e06889641e0fefe1601009cb972b97cf8ec9c3d49aa4cb144b010001	\\x378194ce0a6e3e8f11d3b709ca349892f1da9cdb375e148083db1a68a18f768c976ee802da791a62cbab48487a4334f8aabe56acd142f40470fdbf4d8033990f	1662283807000000	1662888607000000	1725960607000000	1820568607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	320
\\xfdf69847e8e119418141b86c6ae358b89d7b42fdfe1099c0a098721253f3c5079c2ace898c57ab67594c3ce79a09ad694784cd8ccbbf7e591ed68119409919d5	\\x00800003ec51288d652e9c811681d0f3f729f3e2b6f6778a3365f084ef38b471c599edc0debe71b495e7460f51f7a550940aaefe5c787eca1cdd99b7cd8680bb58f9fb4473ab02589c1bfe4d573fa3eb283c8e5b6245c6d75fe5e48da6c311940589c931aa4d42f55fdb4891ccf35eda7d2ce400de7b83e5d3c1325f2010f75a22934fb1010001	\\x50a1f8ef6aacf491f5cc36c939c1282d6843e5681a867638f76245e18c49f58e841944994394973e51e68891eb9ff97baff1b2b014c8e26e5d669d8c9b153c06	1647171307000000	1647776107000000	1710848107000000	1805456107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	321
\\x00f794ff8a42e9d18567ac9a3c37465641741699433e4ac80c85daa485ade7b7cb8ab28084db2cde709cecda50aa9863d135dd7f5c56e581d3756bafd1da6db5	\\x00800003f4ea0ba8607c47c9e5cbcd975deb857d4dcccca03d22c4764067cb9986e03be87e26ce69dd49464680671458369bc8ecdfe5297bfae04e0cf3f9d9c8f32868ebfb627c88bea609e0496477715c08e371bbec0006f199f990e1ab0759b873dc07bc0979ed5a4a7194fefe764eb426dfe1a4c9c4167bf1c0e419019410e8dfb6d9010001	\\xee40267854aae06a8affcade46768028a8e79f1893fe54384d302b1fdc0d4bde4b63a04347fd46d800558708e3b4f55d84470e3d4812d0d204cf29610e18e50c	1656843307000000	1657448107000000	1720520107000000	1815128107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	322
\\x036706742917eb863d3322303613e21bc5bf5708c15fafde8822a4f94d190bd9e2dfb384facd92994599889e1bd8ac521c53628afc5f2a4612ef783d2264b733	\\x00800003be23b524caa3258c02b0d9aae64179370910e7464611172205b48e9463cca323fade79ee652fd1969ba0df01cbe1cded4cec9dab56b62a446f593060c64c6af39366359f97be42a58d5957591af7364adc9e9e8c02caa62027d6ffa61d3555e56711376a9b61568b128dedc23b136f79b3532b45fab26e769ccb2c081b1e3547010001	\\x1b58229e269969e19db26b6e175f0934cc2f6e1643f9dc6c07e598e82b09b4a473453b2bc36c84cbbc7519eb877e62ce22e251663c3c3a54118fbc4b5d135301	1650798307000000	1651403107000000	1714475107000000	1809083107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	323
\\x048b1080d9fdf5649695315fd6fe9bd1d382edc9d250db66911287a0baf85221b20b0a4b78a99469885f3d1cd25457ba340929af048849f9b35dda6bd482bdfc	\\x00800003d5404064cc5fe03b99d02efee303f9499b47bc61e91c77cfdbf2e8a1fcbfd50aeae81963a2755b0dd01db46b38c4f43a6140195bf15e81df502c509bd87e1600c3d311f231133b9615fc2a3ac58fe9741393d12350c5bf4b7047d485d26692f668fa8570e5eec4474c02a45016d7ce4b366efe800ceaa895a42155a94bf3e927010001	\\x3bcd6ac6cfe9186977a04fda5235def2eb9e093cfa8d441466056d4e65028ca06eb2349cc1b631efdce5d3201abd67bfaf0dc7568ced7c1dbb3b3c50711e4708	1637499307000000	1638104107000000	1701176107000000	1795784107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	324
\\x04675dd5a1a0bc22206a941e90ac71d5e627d630ec22f6624f9299b6e1a891894af6a9a94f1763914936e56f3c408232576eb7027af79e9ba15b733f7b35af5d	\\x00800003a57dadb2a7e12a5dbdfdfdc58b396b9e901bfbe4075e51b0c443ce1a94f0d04b8433763e50b6df38d0fdd515aebae6f8361968f97339893987099437223575ccd836a05a7fb64b14e2598ed206b09dea6a98301908264d1aa6bd98fcb7f6f14414116880f4c19a5747cff6bb7e6f7db1c9ed4a8cd54783a233d815a38f26791b010001	\\xd90ff7b192589e3d53d9b7a3e9a4adcc0209fa9e4f3866352027643af33cbe8e91b40a7106f400caed43137c3a89752ed6745dfd76a73c4e23646a4186dafb0d	1650193807000000	1650798607000000	1713870607000000	1808478607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	325
\\x0ab744a17801888e83f08d33fff0ac47eff8b02a6f7df0691085668817064b7d6c5cc9d619f8d6001937d5b04b729533bb1819507e865595139170e4da832dde	\\x00800003f03ac7901ad10a63a76d1e1cdb69d83a3901f9ef4de90c9fe81d92d3d103f68cc9c7463393fa01209dc3a379904a17612c7f09b8ee9fcd175c5cca0e356c511687205a0137c4f0853745ff1252a01a8b0aae9d4973fcfe43c12bf05857387d4192e6044a9aba2c73fdd8a5456778e9392204610b1d526a865e49298f5f8cd0b9010001	\\xd8e17449f226b3629b4a50b99a8adf1d0bbe7b579c4b1097a44333c0412e60302b7296c06878381cb02b81de145c38d0d3f6bc7aed506caf66548dde19b53c02	1652611807000000	1653216607000000	1716288607000000	1810896607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	326
\\x0c931b254108b907dce5d6d0d2a11f0e9b01bb1de6d7e3d1e485ef318e6d7dc0cd09ccf7a8beee4460fea62a02ab8efb81b182c08b4a4af1c22b0abbe39cbdce	\\x00800003ec49c00c4d71ab8f03787c0b6bcf3fa08eb5980faccd877814c4b6a9efa783404e5153053330b7d1311c560eec0a9e9aa2d6ff4fbfe86155c41a16d3f188e1625ecab148cb098f3e72df5761206cfffde23ee1b9f9459183902f05941d77de9cbfadb6deda0256110aa36dab2043339598985f7ea489ee73db5fa633bae18b49010001	\\x16424dcf393ae9461660b0776bc6c3f1b8ae7bd6a7718b6a99a64ebae4f7286e8de6afb5a31b91a958c6acbb805c8a78755a6806002535af87ee9c5b4d6a0507	1656238807000000	1656843607000000	1719915607000000	1814523607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	327
\\x0c7b59068a6a7b73493b0fce010f9454aba0760ed8203d175321193eadc5c6146dd9270f540c2e5bbda4f158eb35ba2d9b8a5e84e17eccd40a0705183af1f6d4	\\x008000039b9d687635d0e8d23e83db98066688d398bb8ef720a20635edbb86265b192be3024f398f1212043949de509a1c91e2e7cd40aa290792c8c632316345934ce9a5be91bbdc37228fa0be236b47b0a069bc9c9ef4edfdbc9c286e8b8a5901b1619b3db7b1055aecf9f52d7f86c1f644d27ce6bf9ed142e5d67e3f67d54867109afd010001	\\xc3cf07280c6d71badba89ca11aefc83086b87c483b174989e6c0958ed8b27c3d779612f99238b7f85588f99ff623eb2239ab229ca77e60526f6ba09f207fee01	1636290307000000	1636895107000000	1699967107000000	1794575107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	328
\\x0dc3091031dc1cc8b676e1eebd3fec7d66b3ba4cdad815e975462a015258db42ebb7af272fb80619a2d976b139eb9a54f5a759ad6e4d8ff51acdf13400714465	\\x00800003c839f972bdd2904e0cda3f7bf701e7bf18707b10f7d846d3440218545905bb3a867305507d28ed65e2d3f56d8e74ed52b505a69f2fa2812085b36cca3802364b3ec13573e7c1455e552d6e902e37e54a38c9e09d651307f231ea51da5ab4e3d7954dca66583480efddc1ac22f8cc758a8d56c8a57660da7daf82623d7a06ce15010001	\\x862fc4613df545ced269d27d4b557670c3e2104c02b837d28e8be6e542de8d81fe91d09f9b8a73d59fc1be6f92d7092d2f7dd52702f2ed61dbb2fbd8103bbd0a	1640521807000000	1641126607000000	1704198607000000	1798806607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	329
\\x0f4f6384c0c67d81a46d2a2ff4722f90bcf201932d0b9168dffc8022cb0dde6fe7c56c101de45f2bf13ac46aae022eb67161066e7f11af406d2c4b6fafb8bd2f	\\x008000039c1b198b4c7f1bf0c400a9477c292bcf5a7a2d6b27b53eb0db6e696b1a2e51e11bcbbc547f829d8319de37d932568668ea74117cc21daf08795aa7c503f0ed8b324c96f169a2c3af3ef49f26f7f2bf6c4737e16dbe48dd9486ae206d4d570a55bdadaa1109e1567fe92d793cf860218dd177b98f234da65b27404ad9e2451b83010001	\\x107ed773e63163d7a00f6d2f6e29a30b69dcbccedcb15f785dae4a2e34cb733ce17ee68fff23f9ff6cc0bb144402732bd55a003b2813759bad2fd90544346608	1652611807000000	1653216607000000	1716288607000000	1810896607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x104715693493bb102b4749f4d0e76e8fee9fd277240e62e62180a980d1fef5eeb5c63338cb080ed14dd70d603ff671e1a40381ecfc84f2c592a0dffcb677ce3c	\\x00800003add4cbb77e8cae198b07ca8146d45ccfb3a0d96fce44639cfd0eaded5fbcc915ce9a3be51cef8635b15ab71f881a9c4e7b5c0ddb1a64022306d616f5e7866cfaf9fe6ae11a2dce0000e6d9c21dc762aefd7baa64a10dfefc55173d0d9ee3be1a06b808093bbb748553b228b2bafe52be9fd8d77ae3489edd5bcd41c132413da1010001	\\xf40d7080734ee39d0f7c4bef919b599802827fc8133fa55ebc00cd76278abdf2cecea358aded3af7fe14f3a6e2cde9ff97683396f19bd79b28178ea2dca54604	1652007307000000	1652612107000000	1715684107000000	1810292107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	331
\\x119f75e1ab6024ff2fc12123bea94db778dd1511d93b64665ea7af62228a8a1320355d250eb5af0fe0b552b84e0dd588569bb6bcae00c2fba39d72c4d7cce2c4	\\x00800003a7e1a4b69407f247b479251f8020426288c06968e8f1a20cb45489ef65de79745ec63e646a9644b0e6a1673236df48006c1cbdd380b3862b4912a6b78725ca37245c42e145511ba1fca9b955d104f9c10887e6bab495bcd2cddac1dd2be9c1e17d9f9cec282251492b32aff159dc06e54c292f1c69336ac540a6c0698b703699010001	\\x3a9ca06a99ba8ba074fa84dc8bf8498446a26b89f8af9bcdf93d62f3f804d8e57adf753d93ceeacff8f7a565f3b9c42c2b34f5347d75ae29dee5dcf87e29e005	1654425307000000	1655030107000000	1718102107000000	1812710107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	332
\\x128b8f9db85f8ce086bdf524959913e427fc6be102982aec443f8b67567509080f0cc7e54b76fc6833de6e1d78f1fe9e94908e715a36a759192f506235d39540	\\x00800003e3a06771d6e82fb6c70be19c3370e58409cfa3546f3c956113f67553dc433165ca96f96e0bab06f3f8f38050f07b3b9632504a0764864c93dd5d9fcba2c5a58e40c8bc3090a136e4f4ce772381443e24ac69680d7414a6010897b45be3be88cd1fb49f5b9fdf691c41ecacee74a79264e5b31c1d902763c1d2e739ad0c6cc69d010001	\\x1450800819120e0c9ea68eed02916a9e5d31e923a205c4d8e9f7dc794b59c5f4bc9c964c53ce0c6614e1717d7b64c37cfb208d728a814c68c7aced1ece1aaf05	1660470307000000	1661075107000000	1724147107000000	1818755107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	333
\\x182382565f5468c96fd5e8e8a49b1a717a55c22133a8bf7ec5f69dcfaa7772099d87b653a6181c24adf6ce79db7091c69e2eec9246bf2d53e59c6f2a561e7aa0	\\x00800003c0dae55b6baca9e4efe07ac36aa282c5630c019a200bb95f4ea4ff2784a201fa590c0e227f64134d5b5f2d559136f150acdb7f30ee74e4296d868d98bba5673df1690149f6dfa16837fe32c39fb64091eccd2f0ce06304af5d3845c68770032e403cc4a2b5635a5736f4a5ab48ced3695b6d24298e8b174a98377113049b8391010001	\\x2d2dcf5113e2f8da0c64dca16f70578c334fae66a509e6bd3eff590c21d576af794ba15f986d975a67555af1c0faec2c63922a8a8d7376d9dfc36c8a03336602	1630849807000000	1631454607000000	1694526607000000	1789134607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	334
\\x1abb2c1926d6b8a8d7e5d0b05a761c312aea0e4339e51f3e81e1ae87d8ead376a8b888ef82ed1d6ea611ab91d880bac054a815ca3809463fcfe5a28b85052a56	\\x00800003c97623a2f8022b56c532f0ba819554f72e4a687ca78b192acfbc42b49f2264ab59da66718dd014f77954d079492197b7e9629cb23036d950cfb04cdec18b2140049daaf7e5177916512269688949ee5f191934c0c61f5f4fb87546c8a7ec6157ae32edb3708f33f5b7dcf2aa3023f728749de85ff72640989ffdef57b6b89831010001	\\xf6fdc1451e5ea6cca8699bdce366f2ad5a823b990d688d996169a2cbc5de0e1abb19eef727542b95ac87fc62341ef3d84597247b7c3e643af89a388f6774ec0e	1659865807000000	1660470607000000	1723542607000000	1818150607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	335
\\x1ca7d64b38e5830c24a55aa5484e21525e93fee19f384f98ac4d16f20f7bc7638cea784f0fa74f17c403d69f9cb795f37c245a347814f50cf43143ad8bd0be29	\\x00800003b2d20fc9d852c7b4279884187f5acc1f4d90c4c5fc69e55f6a48bd7be928d945ee36f598292dd3a5345b6050acc2374cd7340dc96be7b6d05f7ddecef80685e2a6fc3f149bde6f54bf6a348d83ccd8dc1678a5c58fc5c3c1b2985dc0d68556cd8777944c307a6d01e98095e465bdf6503920104e60d980a46a6f6d1457a3019b010001	\\xe8373857fe4f87db3cd6a846fec0e8740a97b614362fe5771795999d6debb43cf9069f9d518e854a4849e2707d3f6e00f7f9fb3a15bf30da271d447aeb5ee00a	1632663307000000	1633268107000000	1696340107000000	1790948107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	336
\\x1cdb3c4ebdb026a929998362d0c89d2897b862d72685a926300f579709baced16ecec2f008703d1fd4b2148414aade9e725eb8eb615fe085d624718d8bb212ba	\\x00800003c8bb127e407c424c6f30a183a514b8a0bfc978d947f7ce7f7a0327d67f1520149376109e55ca815091ed9556872be6b82b103fdf164d493db39f0c842e38e00bfa56854b85bd10674f5f35b3843936173d6bcba5ebbeda409df016dd1d77d0222736a1e3ea5daddcae067a462212e4fd1fbc108eb82f811b36cbe704cfa29351010001	\\x691c5e36d111376967b078feaeb7ac67e6ed79e17810ffda980e45e8769a613396780c8e12e02e4f8c547c5277c5478544337fde979b69eca79be412ffeda10d	1632058807000000	1632663607000000	1695735607000000	1790343607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	337
\\x2af3bfa78ba9093c65c643fb2dea4d8214c60b46da71afeb1a20d00b33b8cb6829379052cbfae090d02f5ef6034d74a28fa272c35cefe68fc1ad960ee0309d77	\\x008000039f068b26406fe9a0607e99a32631f3fb1f55f14dd45cfe81000fe4e51a353bf39c0a69a1d42e667cbcfb9b5406179d37d91870ccddd4b22328185ddfcc86bad86a9538379c3dabedaf0104dcef744594dccdd086ce74aa23a6a5edeb87d1a8d9c7bf2963570e215f4b82fd89b6a82fcd3cb2d8b3e10f563ab6d2e33c88521ba5010001	\\xa9bb7033c33938e8ac4a1b1dac20c88b931f817364cc38be542c6d64b335ba978e47ee9d0838e063375a88505b829b741571d004b12ad88eb3aa4057c00d7102	1646566807000000	1647171607000000	1710243607000000	1804851607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	338
\\x35a3abe5bf17011ec4922d1dcc06e2c10064b3480a9c8a7b2482f4323c25f218d9cb9fa3ebeed113239eff7ab47a0c53cd7d1ef22869a750bc8859a35eba7de1	\\x00800003bda18195cf90c92e4abc3ab89381bb6ca535658603b1483554eb047cd6c1806f55268ca5b810c6cd1df6ff6545ec192b9490fb09671fe8e7861e4d29516f945f50a70f5c2f44b731abc8723ec8e1f4e57086639d1045a802061c99b18cd05115a4bc3519137459c0ee42469a27b6a136e9a0f8ccd7494d6bfca75ca17bf602b7010001	\\x5a8bc8f1810e59348f902ab75b1917404e6b74c14b5710c28dec2b92c68674828c15308b631c3f42bbf4c851bfb581b664429f2648f8e916e3bdbf29889a3e07	1648984807000000	1649589607000000	1712661607000000	1807269607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	339
\\x357f8e74cd8a24aa5baf486c334a7b847c463de3b62e64ed0aec60f8caed71c0ab76f55616d7d229ae4b0da196439a9bddfa2a2d554d5a69365fe729c4338d43	\\x00800003bd424cc767150a7ec778d0237b514e5e939009ca13db876641ec57167986559be5cb49c967f0f2eab563649a402e5aadfc79878467ef3d6d327ff25604ba5c74ffde1c256bb736a484e1aaa5ae3bf7ead4ff4a5951bc14ab6e97066805ba6caf1e398c46f1091dd6f507854669c6c7a8ea9aad9fe81488294520194ec0ae594d010001	\\xbd52476c348811a529bf3a1447fa836f65b0d09858fd5d4f787e74d49c7ce01ab362035018f2a2d8eb414e97403f1aa8e0c466f4ae65b3dfb5c91313f93ea603	1642335307000000	1642940107000000	1706012107000000	1800620107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	340
\\x35332c22da04b21e581ad5fd606698850ce9e3c42426d339b1abbe6c62e93cd13c43c7cd5960cceb3f719b71b0651d5753daf8fc1918f04153db0bd73cb978f2	\\x00800003d43d850f85766a68123799bb48720696b68634908cfe9d247259cf938ca49728c2eb256f2f29d11c48f24bafc8350489329daba806f1dc2790c76b880d8fab78ca0f762d3451eb519f27f49ae4cf944b70dad8b99e322bc0025ec9a06963286ced2c1b2d7146f8cf3c80fa9d8cd686403ec3130eef2188f16463bc3a621c978d010001	\\xaff0ecfd77e4b547c5945010f8eb025dd2a81659bd60d1bdea8d8456474b53e571018c9f83f8850625c882f88dd8c31b2528aa1ea32a44f790671b45707f0a0d	1636894807000000	1637499607000000	1700571607000000	1795179607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	341
\\x3ca73c050f0d537e959d72c5c38f1909300ad93968eb02eb1f4c4bfed6532b5229e77dad9296ba31e645b969e0fcb6c8d993ec8b1f256a884848aeccfa11b2b6	\\x00800003cde6213436d23688e9271d8c83abaf291e28ecfffc4eabe05e0c18a93ac5475db8898141bc5c13015dce9a5cd87843c10cd85ef46765f8e542609c19fb468ba1582d3489198650cc40b9d12433b86071c06ba1b6ae2cfc25a89a4e65a2b4f0248e484ce4f274eaea26b07e4ed2febfc0cc06b3428a1ecf62e4822cba6c6a8f83010001	\\xf4ab4254755753f78b8758dceaab6f870359d71c2276a7987e3614e31ca51de86600bf9ad95ec94d639d25fc6df09055fe25fcfd6e248164c82c69c7c361f103	1649589307000000	1650194107000000	1713266107000000	1807874107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	342
\\x3f274fb8ed8f78791d8cf2e4b4a5dffb7dd6cb4edf197ab56e1cf0ff4a4e5a00be69766481be67d165b5b23ca9f35b5bdd3dd6ba198da43876392d444240bf56	\\x00800003b0b3dc43f6707777e0bb4d2e0b89677efa05395dd495593bc1b2d08aceb995b0bdf815ef7c83fdde3f6c9f4815c5ee1089429e6fa5f30b4a1700289f352f532077d480265f6c5099f21cd472696e3286667d6602af1c8ecdc79c28d68806e76db83941f6301426bb6b2a3bc12310c04db1e170a0b632278d43f1ba165ef5250d010001	\\x29580aa854887bb45ba19633fbbc635352ddcb8d28029dab205d66387ed321db15186688147700db2cd57634fcfd4964643f5df67ee0ba91963e5d05ba4b6706	1661679307000000	1662284107000000	1725356107000000	1819964107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	343
\\x3f1bc4439fc8796a0b51e151e17e97f6ae728e1b9dc60327d90ee9c547f38bbb0fcfab7247315b47038ec7f190661f93493524758c1b65e33ba8ec5639b8fe66	\\x00800003c6d8b95520e70e1d4e6cf0825f09502acf8ada978f8cbf1466f1e4a542630fa8fbc49b0f52c9f26e61050887702d0c648048bd45075479de1321bb98056afee27c562fc78fc0469cb2825e80fd7864e3956302f9e60bce2cfa8b043d64358f8a7d6de07a3616f974b3af9eb9ed4735cbba9d7175ff4e7227e8501366b3739cad010001	\\x882a369a33b71ac1ccfbeba60b5674e3d46bf134c51e0583e4a64dcf74a5546c43a4f38a2b2d945c8bd18556790bb422f5d7c369561ae974484dd23d1201550d	1632058807000000	1632663607000000	1695735607000000	1790343607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	344
\\x489bda667628e63d87a64182e10f2ec48495eca5e8610184e1f5249517bd053f58595ad74af219e30b893233186734c5ca8ccca3d854a0c761cf50f1e9bc9760	\\x00800003c8e478ac3f08a2e017b7548fa1a936c9b1d01e66ef80adb2f4ea372ffbe339f2ea52f8c797616dc2025cf1102c15dd69be23c94c76dc1771c86b15318b6a418add92f72e34f7cd6fedaa252c12491af8a58e7fb8c43c098a35138cca0bbae05f1c942da647cce88f9cfb988c005fc401a99bf36c2bccec8b3589889a38ce14c1010001	\\x5ff5ef440272f03baec12e885ac7ec6077744ee2d9a2d7c38a4ea6fdf8d8288a7ea4585b77f8fd1805d5ffe5d8f58384f7bc1e455f4090e29981460efaf6af0e	1659261307000000	1659866107000000	1722938107000000	1817546107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	345
\\x482fc343827ab39f202d609a57afd23ccac39c3918a6bd5f66a979a216b09220cf9a9a825bbe827400440dd57140f4c43fe9d35fe718c3ca17e4543d2de577ce	\\x00800003c44f5cabe83a17a867729561e8c5cb4f403ab59e0551936f02536e254c914b0fa69531a567f5788dd6aea67b26578eddfc3db6e3214c78ea3380a48f1c9f6df9487b85eb1a6a28f500310fda05541789fdc0b1d333008b07723b8f2d0d381b48422a1abd45900d8dae43605e6b1b619a388142ef4d1de2a1deca39d1cb3f43ab010001	\\x71c8b70ab911e87454c9e36652f775e1cd1ab074f36d5f71f6a24407fb9954a640224d6b3ff3cd2569196ec1ba602907190672a99ebc7bd5ef7f4e874038dc07	1647171307000000	1647776107000000	1710848107000000	1805456107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	346
\\x4a9bf856f8a053fdd555ab1aee85d9f43eb87b7627477ccb82384f6b4204f538a5c08bb92f04e3f68727aabbfabdb2ec0cb027dc90c0f50fd8d2458e2a0fd7ff	\\x00800003bc0f3b49f614f297d7d036dbe24e833a15136c3c46be1fce97ab261b98b93ee2ad99f9d4286bb7f2c04b12ae02ca4ec5aa0945e5903967ece6192b13310d0782bf245ba4eba433e89b4e880a4493d0302f43aaaaac06fbc25e1fd6c504ead2f1e62e389e667abf644ff23a734981e6da6331855e44e582877cf2fad2bbf9b169010001	\\x2c510e7ad8aa173a2a2d25d875110a2e0d02b03eea870083059f6012cf31e54e4e1481e97dfbb1d9d6e88b083e651264a480d27bae55f669a5c278c7fabf9603	1640521807000000	1641126607000000	1704198607000000	1798806607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	347
\\x4bbb5b0784a02cdbe6fce364c96cd7996a76c58fdc4e060bce3984c06f7eeed28f4ed784764837eb4c3e2eddf0c2556d51d263ad188732f48c767653976cc7e8	\\x00800003d0f18c4cee93da8b2dc42e5e9135fd0adde4d12b3d7a3bb7119dede68012a256a490ec09963be670dd6bd04d1b473033fdfa9943a261d0c6a7a8628546180c442ffa5edef873985f60f783f70a2fb367eaef1970b982d27af344a346f694c7ab0ef4cb44d5ef0e1e8f7de521849c2cd0c28e0cddab9e9ac8582d76856c3af4fb010001	\\x3d6a8f6d1dc51641248ace273c7ea45d19370ad2c7bf1cfabc775504e7be19361ad4cc94c4b7395e2a912ea59cd30f84f2e9671fffc78365e14f1f6326b6fc06	1654425307000000	1655030107000000	1718102107000000	1812710107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x4b4bd34b6c72e2ead47a1537918cabc8d360d89216660a7f1b8af0503235160f5edce82e8f8c4d3606155fab1d70e4094bc73d5f44f6f612b15a14709539581f	\\x00800003c26af30a3ac929b5883565e14390eea0454992db7cda93af7ad99c50edcfa05f0b0bac5580842ce0fa4c9e5b9567c913e7500891074408ff212942be899b7e283bd738ab3b043e98d57375bc7a74d0b3d83968c3d90952e7f315b37c18d89de84e1bca5f736aebd8bb953abd0300c8fc57e3cde3f94ce7ad96956f381e013829010001	\\x8bc951248ee943c4933dcb96df1e296834219edb30764306f6cbdc75205d39782e4ff79032851798dea589e2e829626486ee4f5faa2c25656892e69c14be6d0c	1633872307000000	1634477107000000	1697549107000000	1792157107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x4d0f9609ebd530c0187251e6fc8cc4533f7200df3ddc6352165e136e03dbfbab52cd0c04701bd2eca60d18ed359648cd8a2f8beb921d9159e798222463a9f142	\\x00800003bc07cb86d73f22dacdcbf4247d57c3cad0c33afadc1676ca15294413c7c2e68f27b576e6496ba8ab984b95422190738fd0ca0c80a5c38e81a6ee323e3ad38571df177513b0784878ed2a13510e13a04d55de209f6ad4566996c4477a0a866b95130ff8faf1a8323f7ee5c756a39dbecea3905385afffffa08420595fc21aed93010001	\\x034382b56fedb83e2aa34488f2411e6d03a796f93251eb494d1c3d89c73f6ad94f8d799ba81aca3f91c0064f44bff5607c8a29fe75dea4ce97ff992578519707	1635685807000000	1636290607000000	1699362607000000	1793970607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	350
\\x4d57cddf67d3b97b35ee045536c416c5526e1a63e1e05d75ca5b6c98bb51d3111233347ad191cad06742fcd04f55b0c67b7ccd37f948e9c6a5cd9a38d10021a8	\\x0080000397ed20e5ba835935d05596f12592202ec29e90b1de599f3f55e5df737f007a7b7d6bc17ecb7691c1bbc48fbf2e6e1d2f5aeaec28dbdb0ff100bf84ee6154c11bd652e25e76317ad0f3cbfeb80ec2f9d64671d31597c4f32d3404ee44aa170a07413cd2ac5af058d46d0188d5e880a2dbe1dc90a49092c0d45253778ceebc05a7010001	\\xb66155634e8a7636fe411b42e158c274eeaffcf054be4439290550edb46edc9d9e9dbb9173e87c356f0a4e2bfd42a946be26adb92343a3c07cfc3daf1770250c	1635081307000000	1635686107000000	1698758107000000	1793366107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	351
\\x512f52a406e7a8475fd332a6df1077ed99f6c6857811694538623cb19ad1ef724df1046208ae2e89292c68873dd3b8e3557fc853d34366de05b978cbe08dc652	\\x00800003bf72ffbd5ee519e9130f41940e11d3f6905c01e280adfaf72ee80ef9760c9372663f12839fa2e438acd7203098fb6c4b5cb84001e58ea17015b67fe35ba3909b76707a14d798319405b4785ff38e69ef584d4e20379f7cc244f9e1fd8204a30fa7aea564fa4a171bf77b258f8380cbec275797fdaa76d43e7e1fbb301b44270d010001	\\x9ed6ed850558ce4f86e23da271073ff64aefdfc916aae6a7e25d01d9e5d3a7d02b93ea1ae3b5c24cd858092df31fff1d4f6ef090379e34ef6876b601c840b005	1630849807000000	1631454607000000	1694526607000000	1789134607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	352
\\x565b348db52af66775c4a5596272365f21c789185e8c74f30e3e3c85df7047baaec5e538b8708cc52f19e5d65738aac41bc103eeee8ae83773c51214988ef6f6	\\x00800003fa76893eeec52ed867b3d6c126ee6a44d9ee1bb4632c0e5554e2e7c65a73e1366b1e940a7f48e5ac022af2605431636f9471c7521924433fd0eec3a25bc4a3964013055ace5b10e7dc7327333ea97226c9da81f2dc69ea7db4d5d64d760646ca69330cd9b1627bf5669c98d0ed67e3938f12cb2ef833c524ed6d890c607445ef010001	\\xfcef5950d8e3a5eb450eacf2b2d5431c8bd99090361a78629f3a8a03179ed046ce58969a67b106d8ee7a5cf3acf662f9f14d56dfd66b0fc985ac81cfced9060e	1639312807000000	1639917607000000	1702989607000000	1797597607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x57437a0a59d231814b9eef6e12daf4782c9231c76fdeec027cdcd1615e5f6f2b542b54168c0d9b816ba4ce6f8195558766718373769ce4b00f2fbf79d7747d7d	\\x00800003d002d0fd3fb770fff1b47076a5c63d584c9aca1b0337f442dc3e4b6efedfe41593788412dd270588a37631f4289c67f82d2fa80e13ee210bef41f3aa1491f3a8ec3efe23e1b050adc230f35142ce76295b17780ca33f212784ab17aeea4124855887f625c0a3f73cb1f80a532adead5ad107a7ed02439920f6df15bef9ec6187010001	\\x4ae15cfdcb71facad52de5c100f4e60463413b15c25cde9aafdcc7387f74548aabae5359d2531c4213d154aaf5af1c33fd23a2cd38dee7fa7c84e45da236dc00	1659261307000000	1659866107000000	1722938107000000	1817546107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x58676168463aa6ec276ce185e86f9db0fe894f890cd91e469133d3001b9a98443fb7f444dcdb0fc06e6058d3b47dbb8138a84110017ab403a38b10401b6a60d0	\\x00800003c9f88e16c4e4cc0046095bbdc606e9929e1dc676726126655356e6d0b0d27d53117e93eb5da542ff63196fb77a14d5e40f4d08edea391c507ecc76e64ef3f517da79442b3ef6d70241d7291c8ac4dfbbdd4a3059f768dcb5f39a8d7bb282dcedba5698fba7f57afe828a612f12fe377dc60584e23ec6913b892deda962c8cddf010001	\\x3d9e35715d75ad419f4b76f335c4bd9b0d7b8c8f15b5c300f4fd0d5502ad0243056203db65fb252115d680dbea12237c1bd467ab72238f0a6aca9ab8bb9bed08	1648984807000000	1649589607000000	1712661607000000	1807269607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	355
\\x5c5fa5a74a159ef3b3bf7b6ba669079071d127e6d36da2e7c135fa1b89de2f9ae75ca83b5fa8407fca15034fa17ef4e79ffc44d2d56199fa45235306bd0cddab	\\x00800003dca73a85b513e1df89c1a2ec9dd6b607324d91a534e03ceba89869b7c9e81f62cc80570547053c3dd76f4bc7ec14dd65c42787d791069a5056d0dc3c63daeff168ef7214334c071abc24d6de537eac6041b7b1fe628c1e564e862990b399a115ff2e7125aef21c2d8165d3f606dc37e9c68b90752d24164ccd838498fba8af7d010001	\\x7deefcbc70d8a8dca9505ef517671ff15c0749bce3e05b18b2009bc203a41fc90cf354415ee7ee5a400ff7cce269abe1b2256210094e4589cbb34328ccb8cc0b	1636290307000000	1636895107000000	1699967107000000	1794575107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	356
\\x5d1f9a117e136a38e407d6ec090fc7a09b5657b9e6b4e3a5cac1394d4c84034313c09eeab7f06cb6460b32aa054683d724981b53f25912fd926a701453761fca	\\x00800003c1aa72239c5cac631deeaff89603aa88e73f33d039b5fed5ec82b6dc73fc359b8692ac1b7340bc86d22dbd6022a2276049a627a19ae00c9da8468716ab9cd0d9bdc9c86dfd69c78d93b127582517a56c348a1e7b1bc02ed67777b2daa3d240e4a5e0b5c6c831a111cf5add6a96bdc9b12ee5e902ae38129c5688761a897e5571010001	\\x12d47447e131da2b6c0d4433f953a1768bb7ad7f77d5977b8d62ff74ec0c86f806160f603c98597113ea6e9ed6c72d4b1103889ebe1ae71c34f793113a099002	1641126307000000	1641731107000000	1704803107000000	1799411107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	357
\\x5ee7181c4ae9a27cb7f352bd3255d4163f1879457a19d5da9e9e18de8f335a1a9b6ff5c40b08857c567c9a1791b9213545d79b7e18dd2316d9ab19639c6d1460	\\x00800003d7f6876df8c1201c8166aa45219b71774fe2ce7b21426b7222a8e153d18670abc0e1cdc6d835ca1caceb9f890fa4d99dfacf332fa2adb2358d28ea663ba674da2be1fb80e36a167e0ed3bdea7afd24aa56730bceb8d3d86ffd4d85c90385e7c7047fe97c2254f459cb482e5040abd1c548a464c5e2134f06f80854bd18ab5ef9010001	\\x48c3f40aeade50744f82024cabe9a7b5c912b233f0f4e86e041e4d03703d9fdfaa64242088cf9f644a2be9ba1fd4ad967d4a4e960b43ad448cc00409732cb40c	1658656807000000	1659261607000000	1722333607000000	1816941607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	358
\\x5fc7da35f3a3c3b571529d7ff012f0408ac861586f2cfcbb69c802b3846ab18f1842733c23108f599821d466bee58ac35ce6f5d2b32d479c7f36e6895e305b9a	\\x00800003a879c2c305e9371d87139c318e3389d9c39195356b087d6cd686c63fd725895b0099a49b103103530316e1f9ebdcd0303eeaf39c3343a2a9b35fd5d25bda9e0d671822e37d212bb4df864806fc39bce11e2c872c3372852bf0fb77458d0f12fd9ad39b6168126aded3ad48013f5bed00c27559817a9bc5c279a79fe018c48e71010001	\\x72ede2c8b2e1d940fa28939272563c139dd5460ec615303c02868749141a291deac0af79fa6ecce3c8ed2707a22963a4bc641e19c172f39e420f770329574203	1636894807000000	1637499607000000	1700571607000000	1795179607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	359
\\x60136355ef3e40ffe8a01d025245886c68599189192a479f3d3854b346a023cdbaa4654fc0d764c1ba105342bc6fee91209c23a2ea79e69cda43397f374a615a	\\x00800003c32eb65f427e4374c7e95d1ee71e36102b9baa7315f54baa43cf163926988858d04f9aaed2d50a9f2b79a9de86569e3d555fc59fc610079340f533e9a3ac4cad6c233355dec337ec396466b8dd94a20f43ea9dfafc6f99db55361d2eab8eeea094147f288aca489ab2cad09c719e40ee4485d38210e306efd5a47d0f09aa1375010001	\\x04fd8c71ca6a7824fcbd3abfb32ace99b74e302e0725f54b827ed5f2da3f8b59f95edab78694c43968f822c72a319dcf44ba6f5ea85779efad93845a70b28b06	1662283807000000	1662888607000000	1725960607000000	1820568607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	360
\\x602708465be53cbc4e951a366ea4a7eadcf6fc3c13956be7fdf90aac67846428d34b4d404c68f775244061789f8c383fc148814b4ec7a44ec460c57b26525d35	\\x00800003bca2e5dd1c7da10defda58e4283944ac464f698e4073d44d39db471c6d705fb9ce9261385c11a93692632d7f5f2e0f3979adfb6baeddd06468fe580e25259685fab5190fd8b49c47d8b5ab39c293ff89cd219352523486b9ef219a7ef1943b9c0b8094c99a2929eb6978de344e786665d9ff2801b3c92b95b7f73128b8bc3b41010001	\\x96341ddca08f2e073924869723af30abba93495742e8b0f378bf158490cc09875889bbd0fbb5afbf09c15308b885a75f8b2c5ca0d60d9c17c3b2e2cb2c662807	1653820807000000	1654425607000000	1717497607000000	1812105607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	361
\\x61df581698e26105480318d86121893bd5a0bf613421dae53b4d2ea5dd4ae4f4233da92f883e0f5e0da8fc9e6aed96bc68c55e28cb04b215b388f03cdb58e359	\\x00800003ab811264fd472d0c7d725b00d8606dc8d8a5e94a0cbca6a6904262e362d4045eb5e21f34e2b6a9d87bf5b42080be5c26091149a2812db5f9cf18266b1ce70b8a4a25ecd8cc8f0306c8335d678b805609d82ed0e209f7e41598a84826126cf6ecbd99900a9c9e982249fc658e7ba9a2289da08e188f2cca278f3f1be75bb1da41010001	\\xbd1029908e48cad6ff7af1395bd7aeaff260f4e67dbf2fe7458b35f4571b83ce3f2e84b447189143f03a1f8c0fe118f3cd1645a306abbf37070a8052081f6608	1644753307000000	1645358107000000	1708430107000000	1803038107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	362
\\x6507d81c4915d3b01f6124aa643fa586310d1c839464c0ba04b0de21871c24028dbaf326a55894c6b362da8f8ef7be3938b95ab21a84043c3f86db3231929479	\\x00800003ed3d4d6e3fc8106124fbb0cc9ba909d2b1189de90e04ed696680136e183cd8a82b48ced46569846d5988d445224a937d9e327b1b8c55be2dd842168e8f4c3467df2d346263bf69df154ef34949cf3292d99cc8f955bdb8d8b37fecb2839c974a9a323e20733c43165d61ef36de967b2d8c57f8128d2249a29c144b187c121801010001	\\x1ff0b7da6dcfa5d14e476e7a6e4d995e7ababf5fb85b8b9cfaa7a675167ba9801f2396181734dba828effd9924b60b2027f34544d1c58317575aec204626f10d	1658656807000000	1659261607000000	1722333607000000	1816941607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x67ff28f83475495eddca4ba8a1454b2a4a90337ffd58fbb004c2636f8ca9fc6c37214c8938840ff593512087f68e43567af87e90cd8d17b3b6d43ec4b6d50264	\\x00800003c3b07e3a95e07e8d176d33c8573395e2ca0c155fddb8bf4c9965003229c92694ef53ac7b530ea62708ec74a2e26af1a71d5b5b33e51ff041f0f7a06e8b2f183fed982e477aa5a3f836dc130913417ab6124df2cdcd3be31840e750e0493548e71db34d5a9e33d98d287e5a671aab8fd2dacb301f4bb7e545af356c82cdebdc99010001	\\x307758ea5044c441292f83f53f935e6cd3155733c4c21cbd01b9b9d007728dd49c5f5a9c3f1f35a66573eed99588e97f005ce4192a8d0afa58babec2dc10820c	1647171307000000	1647776107000000	1710848107000000	1805456107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	364
\\x6a634b79da263cf0d8ff2c855a4f86452aaf6d40ba055ee9aa5b5d145acc6747c96ad6c866052102b132e16585539d6a99666189b7b8623f8cac5793a8b2edc0	\\x00800003b25a2edc44e08b279f169bfac989a7fa873511101d5474ce1c34e1832f68cef57625d7f03e50aad77f2273079a51e254fcb0e872142883197350ef4a378fa35f414ccd5e686a26113a25aeb4aca5519ba5f2bb8e465b7eff8c1e8809f014dac30683c536532cdb99e969369984dfd73ec42640472330e9756d480deeccb6c0bf010001	\\x3add420bef1b7e3c4e868a2b626184ecfa9256de8e9f8638a2fc6f3c994938377c8a3731970e0289f5dc4d7a8680589a0dc42edb111ee232eebe19b5463cb20a	1649589307000000	1650194107000000	1713266107000000	1807874107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	365
\\x6c1374e0a735cb49ff77e253c5db384970d9acdf9f929f184354923741996d6f5d18f3ad1aae49be79683493953a1a99248e8c7d820dc831a8faffb0b47cba00	\\x00800003d10cc5c93ed39302bda0a1a075d8fffc613682f1f0ce14bac6cce3761dc6eccc311d677d7df8dbcdfdafe4b66a6cacd57e5a10b5cffdba995f0d5ef791281448611f74428870bb41f24a5e0af6fa373c73a19c95c0797ebd677fb585d029b7c863a8de7a9079ffc98b1784d295e572473d5b9714ac8daac7cb17f9a94136d7b5010001	\\x325bac52bf86c71742cec5eddd33c485149ff3e213e1fc087d18e38b68d4d41fd2fd07d7bc01a8bea9e4dde51b4683232f10adc7170b667b585600a0d7396402	1638103807000000	1638708607000000	1701780607000000	1796388607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	366
\\x720b4c48bd8f7f83e148342de8739cf10fc357c56c7039cb99b1492d3b054ef5537e50473678b512749af4a0f3d3f33537c44b849b0c8546fcfd03c843101803	\\x00800003ba5f4fd0f4c5648cae82c133bfec1b243ff863a567aa340e3a25bc7ea4cfe19d3e50b18d2bd24458d25cbff7ab03163e7da09e157582c8b8f1c050f05c846295e7a87703fc2a809e45a5d4c12e4a25220b03782f54e3bf4f50adff2ec5df0fc39753f0822d4be31554d13047809a7eb33fcce712c7a5637cd1ee311beba138fb010001	\\xe44df8e212fb572fb320208c5c44c78b141c76f2a7b53b9c79919d708f3fc55cf7e7b52d3124102b47807066b975ce71c5b8d044389bb88d58e01a1f0364be06	1658052307000000	1658657107000000	1721729107000000	1816337107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	367
\\x7227c9fd1e6b3e8edb43645ad58424061d133a19dcdaace9f619c7c51bc52121c298d799edfe97bf382a1f893c7731897a86d094aebad88beff271803cd40515	\\x00800003a5ca47eb2ba1785dbfe615d65d0327270a4feae33414f46e5a4b1ff5dd378d602781d47f507bc3c2b8a853c00493c123ae9f4d7d6ac17fa05cd07245eff1f5ff8c1c1ef25b5fa059e98e703bd9383165ece3130d1a95505b1893e611bb4edc28f7b337144ceefca3a78231ecbe5f79958ef97293df9991380ef66427215f87f1010001	\\x5666310064435f5b503bab7b69c51db88ee56c9af2d182462b28739c0cd777194a6fbc096eac860f4fe63e534c273818c41feb64f35e72561428a6c18871b205	1654425307000000	1655030107000000	1718102107000000	1812710107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	368
\\x7607c3e337759e23f4600274818548d577117df8edc55158d1e7d408a57f758d4ba27191c484ae5849992663373f322d21605169caf664b93c7bad85ceaf7c87	\\x00800003f53a37159c99860c681ad31f76f5200ee793a58dff8e4ba11a393f97baa1b710bdcea879969aab05b5de437de65aa9e9f61f0e615f17bf8690fee6b42263736850ce0e2def0855069ed816ef5301dc3e27a6784bc26ba4b8b9df1be11a51b8ab553eadf999f7fba3eb441aad85e0c7ce6a9fb9d72b5b9623ec70aa82d67dfd8d010001	\\xc88513cdba0b75a4abc6a44851ea638ca8cca9d82e04f30832bfd82408bffa435d7b42d8f8e5827c481853355f6aaa58b7290d9b95f88355ba1ae36708df5f0d	1648984807000000	1649589607000000	1712661607000000	1807269607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	369
\\x780f1c41749dd5d05125959ac290bfd93526e4021ac6211ceadc954a842607a0f97edd03b9a398b25f1e60334f2692312c7f9a213257ed4a46bee61813d33d7a	\\x00800003c429a4959e4ea079c8adff97d3527a2fd7f589ec35ca4061e7366ca843446556b65f7429fd31ebc5666913d4238b82a5554fc3340919da3659f90869c8d0c4b1fb55d83c9bc1b903719036dbfb386e8845a6908c726fbea3b6b6b472e14e1c450b39fade0c0ee9974cbe91313c9df78d07349765c4a18647ebf992271801ace1010001	\\x89c82f3b890c9ff48089a1612d9934f1fd0b12f5f12193d9b33db62370fcfd5003272d3fa5dc8f04268edd0fa024c5b60ccf38a1e224befc6360f57b5c006400	1656238807000000	1656843607000000	1719915607000000	1814523607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	370
\\x7817d224d9cbe37c4fed3f1834b4fe4744a2891eb43a5dfa9260bf797af76f4793c7829b01128af2f243b8c2358d3c6229e730f207e24e206e35115c969b893a	\\x00800003c4b9e36652b3718cfe07b0aee2b3c57b35fb5f47c313307c9b7defdd96b12cc040c5b2943948fe509f3ded73d0faa5a9e01b845f4d095f3c3bebadb80e9995179e7e78e1bc76a323af05c44b5712226433761763ef3f1ef78546666e29e0028d5bf1dbeccd6e2a2afff2f600584ec5992c1912eea7a1445694860a4ff92486b7010001	\\x52f4a277d7bebc062c2b22b84fa0168ffd7ea83829e5b4560858b4c09820e7a785a62ae0233bde53dc7515769bac69f08516abbe02e8ce6e21b4e0caa7485809	1659261307000000	1659866107000000	1722938107000000	1817546107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	371
\\x79e70c510f46b5e42efc9f8fb4ce48e947f4a61ed7a6710bf5ec568072bc4adfc85e6d3543ce469c755b85479e8791e6d477c5a7f5357a34df20d2753088406e	\\x00800003d14be8b02c4dbb22db376980bcfb4135bee43419df1a878e576e63a1ede4feedeb3982155189eff8c9c205a7914dfd2f2b8195abb48bdcea0f22463f84c4854d1ca5eaa9bdc638fd6c2806bd0796fedb9d8a44e574fc4abf106299118f0173613d8776040d4e0f00aeb1603f803953961788ffdec2ada8c7835136a6536f38f9010001	\\x942dfad355b9b9bc27d69256acd9730834ef9acd556e364c5346fadd6f2f492a34f8328f6a88562a0282d2ee8377249fe3def3dd6179f30ea9a8fffcd0800c01	1631454307000000	1632059107000000	1695131107000000	1789739107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	372
\\x7a93083a6bbe0b7513d754a19ffcafd085dd5c879cc59906e3a2b4d84a51d44e76347ba733fd324d4bd9bed5e7fdba65655440b5b2618676ad6e079bc13c1373	\\x00800003c62c52da4abea6b60800bbf727ecb8e9bf2245a998c75e85e60b2a27794c09528ccdc2fcef4e83f06f76afe2cc782e7a4bd754dfe58bbdd065ffb0dda486f990f570af9d1cd4b8e3f5eee1c20f712381ff49e5af2be015552fa0e0c18d73691bb7b4ba66e8421bb8d9f71d099341a25510dd888250fb9ba7a45b67d517d811ad010001	\\x1153a4a0520cdce0b7227152e71d8929f7fec50ec25eb486de34a3ff91a484861eebb8ed7f64a080587f3a27d4934c14a919058caaadea600493b990b0edfc07	1645962307000000	1646567107000000	1709639107000000	1804247107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	373
\\x80d36d890ae6e945c1d1299e4b7de626f2a58ec40bcbfd6e7e81f553b9ce177805c1a7424dd5863560f72a093d69348a88fd49e3c8d03f32e4cfd30c6f1921a9	\\x00800003c15bfec6f71fade23cd744208c351826630f8f10b1da6e943c750f3733a8b73a16ede70b6411b36c15a0b235de1edb2b68a981de3946040c134af31b20e45a5e9f9de60ee10fd6c6f30147af8d45c0338afb83e6a4a861b6461a3ed125d59e38328255ab6217829c0e2d79fd7f631befae7adbbaecdd55324795b69e3657b421010001	\\x5222e0468e73cbf5107dc6cd88b643ae75d4880eb22d7af9009e2448c955bebe074275f1a669518c3a62c3ccf78e18c6ffe0ba12e1b5b788ab375c450d29de02	1633872307000000	1634477107000000	1697549107000000	1792157107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	374
\\x85cb7d7ea6e6911076c996ac478b1afe82e527edb89f6d2ee9a6f44b1e5ecc9de5510f09cb8817ab6a9f71bba9eeb543ea7fb05d6b5816cf7508222c9a6d31a9	\\x00800003dfd1f5672dc3f5f66dfd44a3da4c5d763fe6668a9dd9a54a157a25170bb9b3d74c85924de9be01085a74f709a49a42ed6e07027603d71be6cdc630f873c4aa9d49df946d1571604bbf838acd0f641e34fe2ce78672f6f72d100b2fbdf386854db9105fc6277dcbff0e0f7c0c4b8defc1b3227816f74c8dd2455b71d0b445220f010001	\\x9c516b829ace4991ebbed3656d90912ec9f7f0743164456a9cfedd3528a9b54a8a4da415e9454b263912206bf98a5c1690e25c65f5d7ff5ce922c525c13f310b	1638708307000000	1639313107000000	1702385107000000	1796993107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	375
\\x87ab7549ba58dad47106867a24c504e5b0da4e3942d12595914a30a45385b0be320a162145c18f0e35c10cbe9f94988dab240d60a822273d374c18ad97df2412	\\x00800003a33af4df243bca4e022397fc45185e6a0dbf749b5b6e585a6b749a3f366e048ad7caa2bba1b0deb6975f91156a870b6e3735e8df244d5e2821cbf245aa093f42b5430917eb6fb26c0ea74fc02c2140f7dbde56ec801e3e9057c27bb74efa7a1cedf55975750408818f2293370ec2d9044b1983398805849dac200bfe60a14a6f010001	\\xe3e0d02b09bbdcd6425b7aef74624af8c01bec03f513d231dcf1d0357012f11ce12d7ab01d90d6a5bb0d84fbc55d1f892e45c12d5f2686df180e1b49b291cc03	1631454307000000	1632059107000000	1695131107000000	1789739107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	376
\\x899fe3ca2ae61a43857e8846ec162d6105f2b069625ee1d05c26e45f9746847f756920dc91266665831b744b1cc2329894d5c28ccb0186e7cc0481208534ec80	\\x00800003ca3d7062a72728424909b8ff3727d2a74503a501b8fe5e8d4183f44cff32fd3d24fa528147efa7b3dc9ea2f9f58598ecc97a3f3a444369df57374f24b45de21dbf8b52bef63435c1f73f5b649b993eebac1f3ba7860f29addb9b63f2bba80a05939a5f1dd70d2354790138471ad1b033baefe04309b9cc2ad8a4bf405a8ef95f010001	\\xdfa9a31c419b23965da19d7034719f56df8fd6ae11bc7f6a826d7ae3ba8d1b57e26eb76d15d76f0638ff6a41b346b62c31513938624bc9cd30e91c1834db600d	1656238807000000	1656843607000000	1719915607000000	1814523607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	377
\\x9087dbb9904eceb1ab873a96d052087951df95b97f99d241a196ede92a4081ab80f6d97e7562cd74e68ca09580cf30e89de6ebd57757929ab0d003e54085c561	\\x00800003d9eb309a375640dce11be17f02750f26f6b565b7745f720849c5e2ffa67750703847f68bd2c3ec40ee761afe5b11d6c570b835fd30e113c3cf6db30b687b2759a433b22f485c918b661c1bb9dd7e604600f4b2073d0392abe951b3e3ef1db77f8c71b06298ec0c2e6fe843a5cb88c8505bbb682d5e873968ce1a559f4c89aa8b010001	\\xa9fe99e0dbf95394afc8ff997407f6bc16e3554e94f73f498009b2d2145a19b35f6d9517302d797e2e7f2366a647b70cc9445e13e0a7049d305fa65af5d12400	1638708307000000	1639313107000000	1702385107000000	1796993107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	378
\\x9397fb18919c1927073bbadb3ecc24efd8fdc224e14d18d60a7ad5582f89bfba232bef27935a0debeab61c1b7deec9f423a0616d0476fcf280d19a1491d1fe00	\\x00800003c35d09dab629e6e74a6de46c063492e3bfeea61e83b9b2c9194db5568d2ef4814b6d1912d1007b47cdcd0861178fc460993323d5be1d866b27f92da73d05aa5b0eb8be97d483e98a74ad5aa4b9b1362848f681f0988a2f19d4c932946a917b4912ef02dfae8946be2f4da331e41a7542161974afd008b03fe6c9bcd24d3f8bcf010001	\\xeb740ee390cfadf56be2d26c212da9c2715c8e20166d5f02be9cd0c58ec432967cb42c1d055d3d87dcf4cdcef0b2f6631ca0b76c8b4901862ddda990bf2ce80b	1638103807000000	1638708607000000	1701780607000000	1796388607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x9717ac10c8617d60c52875334881118139eaa8cc07c36eaa95134addecbf6b28bb0efb369d95231bf94a9ed128fca0e03bb7cf9b511684479b0660c7323bb3bd	\\x00800003c104aba25b608e4ccf324e76c362d686fce2f1a00558549784e36601d2b730902e98909436c828ff9ee0b1c3765a8243b47f96e7a8e791ade855f5ea3ce3141888fedffbca6cb316de7f31497ad66e7716c3f271fa606e4e1eb5edb96951b440bfe31e0b0072de3334d9e8e56ffd8f7057c2f85ad7cfa09dd6b3ed25e9b4102f010001	\\x1ab6f755966d6ea8e950ab4ee2e116dffabc90b387989ae31938507bba32284dba3520da6103724c8e66ae04c4d6acfd36e589064f1b181c485a667333ecd30a	1654425307000000	1655030107000000	1718102107000000	1812710107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	380
\\x975f3d942a93133d836cd8b7da70fad7daa553c7742b33650e91dda1c60511ea9b80067b9058342a57f1970b43b44f7f471d88acf7c0cb27d5d38c40f6017ff7	\\x00800003d00809b7b27836ff4272f932331c2c6ed1633e6e12456784ec86e033662e9c2a985b3be1c807809e26a0377af1b23a3a9385f80c379766a3e64a62592d3d40922ff08b3b003ddbbadc0b8a36cedfe4cd9bda156195f8876e5b237aeaadf14370708487f1a87f95fc58465233901739330aaa0e43c4a8f85f2d3f4f25803d8579010001	\\xf7cd74d16fab5ec8e789390b5097d35e018a3bf271290449e83ad3e975eed564dd5587148164a7b160c983d0eb9519ba456f35120a69a0ee6414e9f38fde3a0c	1632058807000000	1632663607000000	1695735607000000	1790343607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	381
\\x9d3be29f9cd11eff65aa9310dab63dae7458801dd2e97953bcc46c696acc9ccbc3547223c51a672e001bc3061aa4a5b53af13d9e8e4e1c5c6d54687148a68b0c	\\x008000039931aa622fa6228ef4349979ec079627bd647f5d93fd046539c044270d60f0c974ad125693081440838a47a707e818da0d6e634224d45f70e969e6583dc309abd8cbc6c015ed2911aaaf84368ce00b56f19cc18bff71d280b8da9de8bdba5038616b5e2670acfa65fd376113754921a6b72808cdcbc7e92ccaac3ae4a7bdd1c3010001	\\x9ddf0eb6df7883c66962b132a9c5a0a9bfa170cd4efca1a6b27d768b20b59d7b31141023993404b7e69c931c266f7720f87dd7d138cb0b47b2d2162aa8b6640b	1642939807000000	1643544607000000	1706616607000000	1801224607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	382
\\x9e0f055bf5d0d82e4afa488e6e8971023d2f705ec3ab6a7e089d6fcfb1b086762fff6d40e0ff4c275131bf7928fea48967e2ca4fa178622a4714cb9fd901aeda	\\x00800003b7fe4067645c6bdbbcf4b46fa88f7e1f1b1c2bd5d120fb018a753d198a4f0f1a842285c6a74e3ff00619b1c877d6149385f502278d487b4ab81228a63ad72589805d8f6fa5438b02cd27ead6c3a29509e26d031602341b7f07dd8fadac154b588827be402033a5f1015ff00c41e535e55841eba8da5e8b525711150b8535de57010001	\\x611be4aea92c66dce640381a296e83b84699af6899cf7bcd5f9b86c64bb220a55b8a494fba59e471b1069999e90057339245bfaa66909d8d8ae0c04293c0f106	1634476807000000	1635081607000000	1698153607000000	1792761607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	383
\\xa0a387a461d762e2897474b09f7f6efb785ceb4a8bb3dc972a1443658223148b6bca7f6389200f1bea651a2b0753d4e536ec6577330d89dabd8ca07c4088adb1	\\x00800003c95c53a4b13f29a3b97c77b0108ed5ad45eb5abad785a575d8854d63777a7f6be21e4f0fd56a1a24deac798dde18bf7195d235c2b4eea1a328aba224ef3811a1d6fd52cf6420ab0e838368d93157d58fac307eae06a2b8a8723aa1cb5813cc440aa422e677a27f885f7414b1e3b0d3d2d9e1f9bae5b9a9d88eadbb81a87dfe15010001	\\x864bb65b5285544e813807d97b91f909b2c48c0fa25f218865a555effe9a8d363ed361b4d2226d0f5b2c36780191b6a31cc357c9621d19c85d7ce0bd3d991505	1645357807000000	1645962607000000	1709034607000000	1803642607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\xa0478e5a34876fe9c18d04657a44139d783e761bd7a62670a7d856d9b5d244544cfc9743ddb1533ef4482270d9c6e1ce54e76dfb85bb42532b20b8dbd953d750	\\x00800003a74a174b334b9ba8bff307138a39351f391822fd4577cb277bad675bd9e61831b293d33f1065caec1c454227e4eef626ffe8936aaa77267933ef1deb26a46b9d83e5e8c193ecc202e551f225f30caf5070e4e1970a3e3cb2da7f89e9c97b6513550e3df5fb11c0eaacaaa777bb2ca3850aa63b0472c1e9e76f66c7de0a0bafab010001	\\xfc724c790f90423070755018020d2778d48a2e20647a6ac9e8da62dc4f18a99df524be50c8d997e658485ee55fcb0bfa7f8d1e0106c6e49f6ab18fad33432707	1636290307000000	1636895107000000	1699967107000000	1794575107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	385
\\xa4bb7c65458a654b8a0b51dd6cd9a7db2891b4d721b86d20d49978d57023b5d64841acf209a3c28a37844434344198c7fe2c2f20a96ee3a4a7031eea88839048	\\x00800003c59254ac5571306817e6eb914b6919245ec7a0a62f571974d46e41551ce289566bff379cf831412769e08a8ac89d5e3be030e24c9599afcaabc09a3b9bb3894bba7a81932bf647bb8fbf59ddde80004b6641e5ceca71ad72b620a58ea59885cc1f9d717d676f4d6b171441af39e1eb04a4c2071c3781ed8fb0ec61f5a8bc3335010001	\\x2f030e58cc95402d322fac67a7a1df3902d921c9ccc545ab9621d16de9cc957b39d6c6b5e138bdc60e48b775392434464172f1fe25ad92c78b30cfafdca5e505	1649589307000000	1650194107000000	1713266107000000	1807874107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	386
\\xa6832b60dac3a481cff01b1460a9ee39eb29a0d46a4021c6455b5b7b325f59bcf8822c0234f1ac9f90bd4b1279d141c344913b0da626ef3462f170f1d4729d60	\\x00800003abfe262bc94563396f526e1d766231b6814fa2a0e3be5ca62c10f18a4358791fd88adb6ea291a0c4461288435b4d49a0488c6321f590ae306a97464422d8027437af9c066a158a617850f08a8172123d17884582bfe28e60b8499205039d96b6073dfd4c546d4b6b0510a1dad56cf7f5e4772bc2224d2e3a8ca7468af58381ff010001	\\xff5cbf662e6c1d97d723fba379cb1e4341ff18253d3c8051d0bf5a50c2d814e28882d8376f6e7b35f765d29cd83525c7805b023f15a519cf75c26ba1fa7fd400	1644148807000000	1644753607000000	1707825607000000	1802433607000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	387
\\xa64753c0976961b1ffe221ecd15eddb9a47d174d7d409f001331530e7eee6c8eb883466bab9fd1a3ca199796c9f5ddedb7de1404c819c31d3c140cbf8cd5723e	\\x00800003a2f771b421c425922c6d52b05a04702072d9b50679dd912d74269f75394e9d2898bd5683645e09cfe3edce87ddfb0c8ed5b8dcac689f47485c80d1c8166634f8a9052f32aed2659d461d91c339dc31631d647e82b57370c40a1e58331f4c92ce5b42123ef2c3d7cf5e1852d49d88d70c8ccfa89d605377ef0058a05ad60a4c67010001	\\xff2fe2a59c0940d4a96b8fb17c76c27b6be3601aac9a94287f21cbde67938790a9d392cd97417434925730435d792c389e587b0168398610211634c153bdc30e	1642335307000000	1642940107000000	1706012107000000	1800620107000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	388
\\xa97705a48ac924c87ebe18ebc37315b7720c529eac02b25729d715ecfd2b00ade020b79fd8bda438579d4a2c9045c60697c9349773f0926eaeb6ef452944de36	\\x00800003d243897d7186709525386e135997911d5d74adddf51421d5f6987e42bcb055280cbf8a4f356c15966b05fdd94edc1f0df9608be52c246cc0dcf7cb2c58089e2009646b1a472e146d334bd9af740a26fd9ecafc12f489f5982339222612f9ebe915b94031efe96330c97f76bbd419aa7fdcc573bc1f3549cdad0df1ea0ad0b0e1010001	\\xcdf96f8d305ef2f843371feab342b62d7bb9919486035d90e90a696d05449ee97df10d0b1c7e1bc739c1a38d16d7a006a80a77b2d7993d6e4ae941b869a4400f	1645962307000000	1646567107000000	1709639107000000	1804247107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	389
\\xada36834b677c8ba4705636fb5ca99828cdd210c1c2989749fba2e5d4dc3caca3f4167fa41ac7f7a3ef2b884fe11f782d4dbe60fa093b292729e517faa364164	\\x00800003f97d615846804dde22aca8a950c6185add7148ce5e919f8f635af708ce02aa0354bb0776818cb1651343e3537366b869fb745de4fb1e96cd8a4e13cd2541ecf978a18c43c032f4f35b1d83580e95b5be681653b8376dc4f0ef4b2863e726b3afb97147de71bff057b0a88896e96086b99660cff49099218aa538164cd7e34cdd010001	\\x73281da571baf5b1d8d69ee38986ed4c3da3dbb422ffe23f669c313c6d41479595dfa47346b199e84e102c1f0e0af8d2279bf3e6e2ab190d9cd50c7991c64904	1656238807000000	1656843607000000	1719915607000000	1814523607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	390
\\xad47097f462200313030dfef1dadea4ee784d322aed61894177607d537ca9c1b43f1a202d3f9d411b12ebc713c645692e5913eaaaa162b0143c185811ee49fd5	\\x00800003d78f9d685b296de2740300e3a2f05cf7349ea287d2147c03751ed151b161bcde8c4ef22250249281d94e2974c6f9686bb134d24f0ed714bed4354668efc60994c64d48f9ca0aa7aa213548333400741075bf9c57682445fcae3f1363def54fcf82f3ce8ccc6721280ea0acaf47806eba6d85b1729805e1a10031725eedcd4417010001	\\xe7c09b5609e8191d42cb8eddf640f47e2d1ef33cffef727e8d45a2fec8f81cf1290a76474f3cd926741d41dc50889f2d91bdb8e95975441bf231d72df5087d02	1631454307000000	1632059107000000	1695131107000000	1789739107000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	391
\\xb3bfc81342fc5d8dc3ecea0fa7af8a9bc7de5e8362863e9ffa0d63277e611ca386f402e9bf93be3e844ea7b9a961cbdc6036bdd7dcd1e0abab1cc12b86076fd2	\\x00800003babc7eec3fd9659cb5f11e0495530c2d5c08fd094f5c995e394abfdd879ece58bac2d266395910a6898e9714ee8e86a285ae582ea7b87ca359c242862fd47b91daec3f83d3cf8ae905c9a1ac4b1a710caf6fe8abb8a6405d1c11c929021c8965d17adf18f95a2e024bfe40caf0acfa740ac1966daef043c23539697e66869b77010001	\\x82b77540945b8c5f3783d9b66575ce6c543df27bd76b05c6a47f8a294b4ad5eebf831408b61a9802533c7adad5065588f02cb2344ed65e6326218af88001d503	1661679307000000	1662284107000000	1725356107000000	1819964107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	392
\\xb577249952a2ab1a0a54ec91deb23b6da513e6630e93e49e13a1186f32b2075407293b107b219cf9b3a1bb553c5738ce75784bac73d8fd060957043fdf1cf9b1	\\x00800003b873173a41fcbf6e287a07f3b8177f31ad25d72da697e20c2a07b3c89038b5cc81d4041931f118536c8f10d44d72bdd3d3bb428162fcda8b6df4188bcfc83b2b891d3b950844e2740010c900895a7142d9fc0e5bf4fc5fc4cb12507cc23613c13552541f9c463e448342990e00ebc2807c202bbebcf925354acc37e4fe63fc95010001	\\x43572f12d2934ba5bd5f2ffed3951612207e8213a7bf6d92c22aec688f5c9ca057825c9728f1acc57ca00f0666abe47cb2633650a603432774de85ffc084a405	1655634307000000	1656239107000000	1719311107000000	1813919107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xb72baf2a5ff6a39101994227a5f06f16e12e9de214ed2853af90f8c21ab888b90b0d751a0af2cdea498de6d62135e5f194a951fadcec469c0a446dafb11fc189	\\x00800003cddea9a2a4c0444f79d40c4ca8afa8d999fdc6dbfbc67e34c8429aba36c958fe8c5693deb8a4b3c213f7cd52e21f36fda8c27163dcf31c09186accd6f7d23fac0c486cb1bcb0249106f6eb8f7c1a2b78a8c400579812b7ead106cb8c2177afa66ced50261d9eb89544bd29326819faf556614631fa5238954aaa2f0ba6e3830d010001	\\x5c1c8f01c7d6262a85a66cd8cd46e80322aaebb91e36a23f238f019eaadef70eca95c1a7f54e69ea688ba78ca91b55a6f1210b0f8398606acdf9479dedeb1802	1636894807000000	1637499607000000	1700571607000000	1795179607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	394
\\xbdcf8dfc22405465520ac857e6104687a1c8a4e7ffb00e3537bb95fb65837eddf9d4e644c0ab3c860bfeccd6664051369a98e594d603156e592595883f89a536	\\x00800003c584ab52aa76924408d230ef04bdea20d4fcb7aab78d6e4e029369ae41bd95da0a9a9584444bba2beec749d416ca8ac3505fe4f168f55ed44e6ddd3a8e2f7134a76ad106e5d3fc589207d0038c2f8433e4960bcea85dd14cb3a1ede2145b56ea1c7c03f8a166bff0479a395bec36a6e3914d1b7b1d3f1d3f8b77389e44de8833010001	\\x6d15a9f5e5ab80079362f019baba3842e9db4a38752b339581637b664e6e694394b1f7915a06cd022919f4116761280049fd942bcd6f78f786a950d36100f009	1656843307000000	1657448107000000	1720520107000000	1815128107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	395
\\xbe1f335ad8ecc301808f3704c3f8510deb9c16fe7ecf1394c0d6e39f4dd74d467413a510c8cc96317e438e7818360b93cc4c832bd5f543fe9620d4476b18f6b1	\\x00800003c6681fce8dffc0b9e78e3c2b0f9494d4eeeb63fc85c023facecc69a0ed88fb7319518a7387809ad215203466de79ac9151e37949132e9fd77be818a770fada7726d657baf056f772e16a2a9d9a70b930643867aaba569f87634c2fe5fc40d37722f116c22e5c04bfec997367ed75344353a39270d50317602eb53dbaa7964635010001	\\xee2751382030cb101578fa4e7b71723dcf112c3f82d7387c47ca48a50dcd231f44d7469a16123575413a1605737fbc53760638187d1668a4ea23fa40c4d76504	1648984807000000	1649589607000000	1712661607000000	1807269607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xbfd75f100092390dc8a66c9b87b67da3d366d37d10afabffd6f844eb376dfb31991ce9d550634673bf30534917d4d9cf58ed4235ea1d839ffeb2a01fec1859a1	\\x00800003b37611f8a5592b1bc4d727e2b6c284b243a2b41157280b49f6df86f33801fc08b3e00996f5a2e2d76601fec5b4c5aa99cece1059a15f9fcefe475c0ce165ef2cf6667b45557b890e193ac95465c38b221ffaec4485967545b300b06a10dee8b7e9362918fc728e562b73ebf1497425e9fad214578b308a865a209e46aa4743df010001	\\x17f232ea2afff2d56fca1a71ce4a59295b5c19ff3f47fd1b72877446a75d02a7baf31dcf7fa325568dba7c88e9943adacd15cfcad9b10ef01ec3eebffa16c409	1658656807000000	1659261607000000	1722333607000000	1816941607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	397
\\xc0af22e388c6b5729eac5161788792d3d6cd5fcc50cd580bd97b9375f2a25f8a8d8d571f10f8c85cf76d65513020228102f157dd604bfd954ac801f13e7021d3	\\x008000039ab0161cce18b08a28d22938d87a6167f8547942d7c71e9e284b5a6ba6018cc5eb7bb403a7cccf9698aa7ce4f6909fd4664bce0a86e1c2d1c8c24d96512cef4ad6603efdca5e6e977d4189401e87ba7054909cd73de9a134650fbe10cd540f05eba5b409879c4d6c3f87f77a358ae0199ddcc78538266efd7dfcad2e5465539d010001	\\x9e8e259d835f661970ef598281d6b361b1db63d4f0ca796ab1e4b9fefdc6d7d68e2e1d72a1dbcc626370880c8622d2ab3d6425b2f57ef89f3cc73339e1955d05	1638708307000000	1639313107000000	1702385107000000	1796993107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	398
\\xc20be45385029864a75ff0fd8c1e7bd2541cde3ef7d1ade53102d5fa4f99e17d31d992a904706f274016924e1b6f90e2601a8bea04135f36f8c61ddeb08a9b08	\\x00800003cb409e2511db07a91e2347358fa7b01c9882c59d5026f49062a9bcb8ec60ca47bf81bb2d42d554b1f5e80c52c8fb808c43b65877620159db48eb9840e361ba0a7e531aa830929351b2ebc0b2f8a4d7e9459fa8b4eb41a5d066594c14e813e29429373c677fb9eee57b1585894457b9de6e083534ed55abe7e298ce0fb3704eb3010001	\\xa03b5e2b48700d5e3789fb718ebb6bf449d7eb111ee363dcc98a7238296d7e40df6e3d48f25c5d3ad349ce60eae92d6381cf397dbf3dea4dc1fd296692161e0f	1652007307000000	1652612107000000	1715684107000000	1810292107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	399
\\xc24f4110306c89e325a98da72738566761413ed466d777a51aee5a6a2845c4d3f8b028d465dac5347b65b8ebcbc1783377884411730335d6ea5cf0ac3195b46a	\\x00800003dbcf4fdbf64fbad768c7066f640741a5b463241045491660a8a61a516ddb4c925a6ba53badf5a453562e109e9725f5b2165f46ec37e5586f2489355b05cfaf44611fe3bfb2a1c75c83c987dce2c3042fb3e7f046b24ddc28d23fae2d44ba77f4a5122d218bbc0b058706dcdff7d5cb1aa4f54e1e07ae4dca1fe5442519d2e917010001	\\x36327d619ec5c1e91a875d76e48bc1e0f028fee297b52bad4df02acd576077c3ac91f9a2da98b85ac37cd760c8699cf3b8f1256b2ddf07f7984c9b9298f0590a	1639312807000000	1639917607000000	1702989607000000	1797597607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	400
\\xc35f0a157e2b66f8fa9c2146800f68076e84959143005d63ce4bfe77a10e19d1779ff8b3b46ca7f7109032abace9dfc9d7ca229c89649af6df1eaf236adc4298	\\x00800003d1e1d9a29c446bccad8862b37069c94030080501fc1bd29ad81243f54d2dbd72bb335b3d7215738a401ef8e83ad804024cf445778b59cffacf1f29289321d5e364630110002a02e5b96d086744572041bd27c2248aeba6974c69539a2930db976f38c66cbf9e9621bf45cb05a27a612d5c17c26ab80e9b71f8aa9506d1d391b7010001	\\x98f0273be80da60ca056e74a34985a3f4c3ceb81f4eea8bdf788d95c711a3008bc6b42ea09640719b3b07a3df922c1c0248311cbb00418388a1324afc29e5b05	1652007307000000	1652612107000000	1715684107000000	1810292107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	401
\\xc4bbc87c49c7a024b00a6f398c00a6ce4776eb621723c25f1b626c24160c0c1b421ad81696baf019846a9212c4b2371ef489e0c4acc73c9c051a70328c04e42f	\\x00800003cbb6b868ac4aafa8a4b5404cd76ef942895f7af54fbf3e7fb05432b7f71c81c2ba9635d24d3dde05f1b3222050d663186db8aa59b707e18430f42353461d45080f5b086c8dd6abcaf7d18fe8eb96e1adec51a01882f8da1123ad85d05643ded58de6851b3748efd0dc3c74dcc71a5602aefe106ff7300d3ad89b2dcc24afd015010001	\\x0371243176b4a9801bf730c4c86716c45fa695f62e037e0fce7cb2e6bcf54b0842787607b540b22ff98f89011829f0212cb71240ccbd3d5bbbcc2b7f5fdd2f01	1661074807000000	1661679607000000	1724751607000000	1819359607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	402
\\xc6bf5a3b8f76a8796fa376822a275d417db2c59e67fee3bd68b90091010638602d2bea22126e25aa824d6b1f6a643b0ceeee9add3a8892b7675a3ebe521f87bf	\\x00800003ccb3eb988f0ee8c5ddf223a9ce96ce6fd68a5320f628fab0c46f4e3868618aed2408b0a568531632cbb9a5cd4129b399796d87c5eea4195ec966d9bee6cf38dfe24454dab2e4d155a42fad43fbcb8890f734d761b11522666e828c6baa20521a84b56bdf4e8f8d70a74a2d26d66fc2386a7b2bb38e036b4f1c493ad992018b09010001	\\xd0b063df1f4447886eb70cbbbc22e858c219bd1cf8d841a2c6f51a967883f405a2737a875d85b2e2f78026f998101b74ade0fd6f24d23e82b04ab6c4ea463d04	1660470307000000	1661075107000000	1724147107000000	1818755107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xcbab679e77788bc9d8f4132ba1b9db32bf3a814a4c74503b6a696e1188c6903552c3659a567518e48f8e9757c654921b5d4d7efb45c5598a338b5b439e9d7f99	\\x00800003f312a014551453e3cd229913debaf2595438bf4dcd112dca8cbcb859fb4d432d0defc1cca04cde1b5184aeb8fa853683e0bd9aff8753034b8a0972dddb82dc770da7946f9d9afa5d0a86d177bf86460a79fb4266040393007e9bbedc98c8de6fd4d81ca76c3688dddee2b32ae1161c887b4bac7fc9e12c3bf64129758f6b20df010001	\\xeb621f6d94bf3ec00c6344df4af839cc57cd9394145d8689ec2159601c8672ae761395c56fdd35bec22ddf10b08072e626a369910abce1d3667620c6300b2e04	1645357807000000	1645962607000000	1709034607000000	1803642607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	404
\\xcb0b233c4deeee7c045f0350493ef88c3db28c142c063cd1f8467882ce589fe3f35daa84e28eb12e1654f1188fa9e6965d25a2983f7e2ffcd7aedba761a3a4b0	\\x00800003aac76108c8f7208a45dca9c8d2ee21182b9b73c8d106be4c7a6c8173da13886a0da4aff01b0e376a93a53c21c4c90ac6eee3b05664d6c5d30dbd25781d21a9a436097d93f1d3c48e399efdd5a15b6e82373399ae3f1b097f636afee9fe68c9b646792e4b10663c624b27b8bc0c92f3188edba6c29a48c4306d9df7b5f3697389010001	\\x1ab0af96e061ad7b03f38df1ca9ce76640aecd44da43d1840c10c50d0112cb613fb96e9ea4eb2a9d155ef24db404bfbb9c9d9af92313072f9e8a4e37e8c6c40e	1631454307000000	1632059107000000	1695131107000000	1789739107000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	405
\\xce6fb61ffc2b582367af29a8cbf937c1515ba058e2bfbafcb06781a0dc6b9f0becf6b0dc2dbbc7d495491d1f7721133d2272803dd4c661728bedcee968e729a7	\\x00800003aefe1ac01d1be86d5bd931d3c477638550bd0b532acdc54bcb3124e92d8ecd397a1135a5231bdda9d86abe704ff4e566a94444c41668b2910a00aa6d01deb66a16996cf82e89635ec7f6f7b419f368b712b56f3ddf9489d87cf4bd5df2046bbc32b999837fe61463ae4a8deee0d4274d927ff64000ead60b087bdd73fe660d4b010001	\\xcd498e6dec53ccf74fcc754550c8f88e6cab8bec514a27c67133fc90acd024e637f21079b8f75b848df09b38bb25e195a9dcac3773ce695b0c1115887fa3bd0e	1652611807000000	1653216607000000	1716288607000000	1810896607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	406
\\xcf0bb8eada3a5ab863f7546de5071438ed854ea53fe2046f108d8a147bd0e6e00fdd3ccde180b158257d4413983210acd8b8e1b073a3ea8de975a9cc51b8a1df	\\x00800003d4c1eaf4491e1e1f3e90e2bb8231a020a0b1b8deaa9ff423b15ca0ccbf85133eefe8ed52ee3aa982d03aee13ad03c46cd54e8d82e9e56fb7f7a7ac6d81a13f32147ffd03c0dac54c2f9d9b4de57ab0c07e72f3430b9d232f766acd135d36d2eb820218b000708afd14e5eed424b99e50c7453b26fc5ded9b33171a267933a691010001	\\x1a36a9cd4362f9c96c4b733787f7a63f72468f957e7a6ac6ab65811c7e4eaa28df8cfb7100cacf9ea3417d8fda95c939b9ca2be5a4b9dd6955bdf43e8cd9f00f	1645357807000000	1645962607000000	1709034607000000	1803642607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	407
\\xcf231e0eca3df9b78249272801f6320e2b19d65bd3641ce8059c7320a1557645c138996b5f55eb68b6e311ba3c2fe3d6dcebdf8f85b1c13e88e5637cd30d08b0	\\x00800003aa2585b969f72f2d74348d9a4c18e3c95108789fd84bab2ac4387cacfe8c469ce76845031ab13887117d77778f2c88fc7cd3e00416706c21da0af213e632c1bc3679e387cf375ceed1b6e17b147c25f3ae38cdeab71022d270b338fd0dfdaaa8db29c25c2fce3b6e06cecb76f570d2120d7152c49e54a9377df95f3245abce13010001	\\xcbc2c3aef271d3f78d66fe67563af59aff9e3971bee8d4e321bac8bfdb0d9a071297c3810c4d55984559c98fdf33f010616315d23779e204ecdfc02d83887d0c	1653820807000000	1654425607000000	1717497607000000	1812105607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	408
\\xd00f3c3a35b8befd1d38eca76ac6d13f6e81a07b3df3fc6e8a5b723bb4f34ace657529c4bbb298bb40fe47a4b3a7228b65c45c00fbfe5194604f619062609b86	\\x00800003cd85ca910a50bc04afa309368c5cfea807810e8f0362cb4198f8b7dfa823a263f274b099bb1fef60a0e14605c0b617d2c9d294e32ed41006624e4ce1f061bf87d7960a39e8ff0edd1d84265d9b8ab728a43472f707df24b2ad56eb1f7faec65cb295522507635a3df6a14b1026096ab7ec088a423eb19e5147289083f2c0c70f010001	\\x8aa4ccdb02c1d1e2f1eb30cc256237bfd6d4d64099f7d721c0d2a2b3fb378e6898e94ef52cb626923ef716b3ca1bd630c4c55e35b4a985687d55e0b84aade208	1644148807000000	1644753607000000	1707825607000000	1802433607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xd3874ff6d64a867542e2c1025563c79e648eb82e44a1f73707c1b533f80f8c3c8756a79f7ae494b0f4c3179758b720d7e391f1f4e5274be5cd38619b168ed4b4	\\x00800003cb87b7010189d11480d07d28046098261294e70bb3629d1944e55bcf37a4c15468a0b205e42677534db2ec8f9ea4de28ef29be2c1b6c77e445b2d1acf87d35bfdef9cfe82535ca47ddb9a2ec7540df68ccdb622c1afcd09ea25d35a535d5d813db5bebb570327a3b0a21a40849212f0f38fedda13a1de44048124e038f41952b010001	\\x67e1395b10e8d65f1f57ecc52460e804fce124a10f9725eb682703cae8f048d8ab98c2bb10b82532dad5a8db9bdc81b8e23b6af1a156aeba65702e08d7e9920f	1642939807000000	1643544607000000	1706616607000000	1801224607000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	410
\\xd8277172842bd5886b403d542887f6aedb4962751922094626d97b1346998c2247f21910687f72db0e4d6b5c38e73cac0553dd73726f2969ff434b65a19d596d	\\x00800003b28db45baf35bf6fe0d5024492dcb333461e80e986b3a6c3845ea34bffb98f3c85c4a1fdf17d0ef0884a631f225bec574d4ffd6de4c72f0fa5ec47bd6c6b997511a6224c86fdbbb11e664b770b725dba00a6ccf4229c3eb490c85c6777caf44872e7c9d0a60b732a30243d3c8fd15c89972aa97a1174e235f07d58772031e59d010001	\\x03aac3b00898d9e34dc3186631d1e6c2819037ee26b1bb0de22edb25ae0514e8a97a519dfa560ebf4785f36e1fccb8cf54ad3e4aabd79ba018a4b79caa7f740c	1659261307000000	1659866107000000	1722938107000000	1817546107000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	411
\\xdb3b43176634c52bb16fa2339b1d8ba0b137324b0613533a3476faa2783919627798ab5962e405596e13d749b245a225a11a5a625fc8dd29fd054c869018d9a2	\\x00800003c7180fa93a4fc314ae0dc84cef25588439ef5a5070c804b230d1800b5556a11ffde0992938575ea40e1c153c3e823ba56efde8818a10c7a2f023fb40a63bfd3b2a88013ab7b7a9b078d1ce514253c8d9d3e9d7da2e34892d6925dec149e3c793f9fb5f85c8dbb72d210a6ff28e51cf1e47d2905e1f49f2f4f10c9ad406f3b9e7010001	\\xd5950b1f6ae371a3f901b2ec6dfe5e1fec1d8c9e1eaaac1c80a4d9bd8cb319706cd302e3fa52c46e1a0db1d061df526e7709e45cca2dcdf9696243ca8fe81f00	1641730807000000	1642335607000000	1705407607000000	1800015607000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	412
\\xdd235a2f0ffbdf528fe628545610fd6d795138db4a37efdbcca2e6d8f3a175a86cb4b5f11c6feba638e81287653a2da054218c024c5c73dc609c9c5925e32120	\\x00800003b5d2c181326ba15eb72176413d083eec2c9b345c073b0e2c7dfed8e5a5870e5c25c3260e98c2915b173af710e13cb34aa9f4ef62d677bd1afc5ff540cf7d3fae2abc9306a2c950e2fd2267733461f60aba5a4e28ee56f2c040e9cd0bfd8cd3acf03456724ed84d4ab53115feccf6bfe8f7829b30efa873045c69509757a1598d010001	\\xba1db2faf09a4a8df407eebbd9a680a6767b52911c1ede86c7e80a08257c836d8fa979d41e0f426c8a56e0287d5eacc7ab6aa232ec2960d424fdd30e66619709	1657447807000000	1658052607000000	1721124607000000	1815732607000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xdf0bf25904606393f6df0875c2b0554427bd7f4ed4a7bddb0f78ed0ea28b87a02e012c77911e1f80387471dea5b4edeecd69d9ea819a877156defb54d25dfeb8	\\x00800003caef1593554d8affee5ad04951b6a7dcd569d13a4dc22a085cc3a800a88569aa493d09f5ea1b1ccd37c1a44c2f105a0bfb8baad7beb9bfa28a6c6bc6328e6997787b375e63224471dd1b727166c52bc71e9cce84224d575fc47f0e76f8978b9df5cb127f6bfeda2516fb9257603669ed654400a6433e68f7d04b9df8816ec4a7010001	\\x9735fbb7e46207ca8a1066385a0f4f52ef42f236e626b00f3e90865fa73c286f938ddb39a1624f9537dfe58229072d758e5e480e6584dc4eeebf9487424a7104	1639917307000000	1640522107000000	1703594107000000	1798202107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	414
\\xe2d7c8e9a9028ef45703cfde3a8dcf1758efe209ff9cabfd44dd73fc2c8d60761bbc24bf2b5c4cac5c4bd6d504e5dc25aaf5ceccccbfb1bee89b15e114b6e526	\\x00800003a695c9868b4577ff5c6c696d8f430de9da22b24c2f424c12910ab28b0a8505d4beb7b0d326d677f764d768873dbf05666a9f458f045e3fb211cabe1da67133986d608714bb60a1332fe0da7e6833d8b01bf4736e94ba48d2fc44696903ca9aa2bf3ec4eef9decad25e553717306578b86948ea7b45ecb7cbd9742fef0d0d7551010001	\\xf395a2f5f45b98fe5259a04591fe0a4b29aff49481f2a3061eb30b5c6b2f32e199513f09da3811eb9ba5aead9792b05806b37135610ae8e0395a5893270de906	1650193807000000	1650798607000000	1713870607000000	1808478607000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	415
\\xe26782f39c3171bff50f6cf1949813a45eccad5478281bb726c27b5162c09224b808e31a0edb06fd8dfe57cc7c61fd42f95fcc986c504ee254eba0664bb00ef9	\\x00800003bd6fa1a672603162fcfc83c96b31a2df810a7addb5265433d4662f51db75bc48967f7387c9abd1379053203ac92690bfd9bb096bec7a7d60f688357dd8b4972df5f45dfa31c34c24e74acad2b36b2afc651207d83e0662567f8bd3ca239d66c280443de8fa615c18b558a1dea5dbc4e5bc0d73061d52582fd6869fd9ebf8dc31010001	\\xadc6ecfca41560bb6bf2a6551b30b1c2247cd44bb9fa4bff4fa90334c1863776ad566c1f3a0345755eac361b4ceff9349596be0ad150c1b26890dd1c41750d02	1646566807000000	1647171607000000	1710243607000000	1804851607000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	416
\\xeeabc1f5ebddf8be32492e93eedfdc24760c67f0407a78f925f05eeb4f3b52724e0074ee42f9f583c0ae4a2002c4fc2783c878194e811cb77a781dbb9b8477ef	\\x00800003ab9309a4fa09a3647df65c11ed5333cea2123fb69b6dd2ac041a58ceb413ee9db27a0f81bb68be59796ec1ca4a34cad831c5d67942e285ae73a875c8d81fa781fe68802b9964fec86caf4b48bf1266bb38d137d4df2dc824f63ab5ce5f4faed31f5e0600c666faa6498f61781c961456533d3d7e39ff5c1be5d6dc42042b333f010001	\\xf36be6962cbe990f5958090facea5f1fc732760c40620611098b0a9da1178d5d74056d81086c328f3d50d8f02fbe38f88b932cdd4a83676a6ac2c0d65c56b000	1654425307000000	1655030107000000	1718102107000000	1812710107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	417
\\xef7f5bedbc6be22c79ed09168a03b6fe281da24fb0b7264bbdc9afa36f95bfd386918bdff6b5b1daa370d3027c63ed2d71244fd256ae40dddb9a9239a5e9a680	\\x00800003c49a1f6dc903a8688276ff6777b5e53f3b06e3bab521e9767ea5f3a235106775097a334b1fc3e74a87ed2c7e3799131d66679c9e401e66a2f3073c5e6bd383988d5439dde34bfcf2f96ccc4185dc9c4a20279069a1a5f1a6066f8c90705f6cff1a0453acad92d7043bc5b4d6401488ea8c405f0b1ccdf497367e7aef4d4d8b01010001	\\x91e5992ca90ac57a07f429d0ec56d6989003fc2d9522c4cd6f3346813d2c4cafb5ad2772b7195bdbeef338a1c4542446e6b5f2fe49e18d42efdc458fa975f100	1655029807000000	1655634607000000	1718706607000000	1813314607000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	418
\\xf383aae9d7a240ebaec8869e03d74b338cc73e80baf6ae97e93831da071d2fb9b0e780e15b187cae47cb8711494bfe0796163686bec8b1e1c5ef975f85f3fca9	\\x00800003cc2b63fd319b86421b4831e714969bdce3c1fda920816e2ad19e1c4fcf2ecfb3fc6000e48ae5ca2191c7cd899052da2664dc439e629e22e848354f954cf99b190146c15b1d64d0417eea831e4941bbd9fcd5216cfc088e6a1822a98b249010270e733e15a702bf59927ce45e2a1da8a40066be61da0e4370086eca217756533b010001	\\x1d019d9d74527c36ad54239ebeb98cd31b6d70ca4cc2bccd2b9f8782d8b80de73492a3e6eb95a49dbfd8448fa72cfbaad6c496383a8cd0df13c00de30b5c200e	1655029807000000	1655634607000000	1718706607000000	1813314607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	419
\\xf4bbb414b3ad92173c31fc3726f29097016592350e93828c4ee183e9cf429cf5f6b95db6642bea45336ebdbf2d05562bbc2a75dd5daf834b9bb36f2fa929f051	\\x00800003ce8ae387038f5a9226f97b80634d8386bfc8dfb7ce72e70a37c2884eba6dbc41bf1d5f4f699a2cbdbd49c186b0cfbc535d6d13c4e9ddbb88664f4a15d72520c7602062c4c5e679f4ecb72ff2822033fec66713019fa7de282fff35cd268a08d004556e70b037e12ca2b0f1ff48085477c54d907f34d849a878cfe579f62d9861010001	\\x472c9c010f6eb5815013bd2bc52113ab473c5fca57b959f1355cb5de6aca9e7d9c4c49022213f25f3a27efd0de232f078ded19c119ca928f0a272c1a8936ee04	1649589307000000	1650194107000000	1713266107000000	1807874107000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	420
\\xf99b24db3a408c75c86f2bf8c34d6b8be364d31ab674edf4ac4815acab506735d0381bae2953e2edf018574af7f15584c272472f5d80c8e8289c0d21d0dc09af	\\x00800003dbcbe94ef4eb2a37b049796fcc2825f171b0b58cd674fe7b480eb74e6f5bc7220525ea619c1daba81c3f7ee94681596304a923d107b294eaedeb1533e3bf773a664d7921316959df4971c43bbec6d65834cee8caec3c2dfb53e2ecb808ee6a217bbe10838787a18905dd8426ff7caad02b38360eb99133e43d733a94a99b9059010001	\\xa0ab3df50442670fbd8f39be8de6752ca444fa29b85c7ebc128a6479219c11136c6508befef5976501d44667d53dcd3a24387db2ecdd6dd80eb33f2b722b2b0b	1661679307000000	1662284107000000	1725356107000000	1819964107000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	421
\\xfb0f4e92d6a1326cb41ef2d6be60184decb87b8d570b779952de163974099af2a5ebc0aa3f76f7ea06e6e6315942a7549776923fe2896e51d66c6fb3d8cc159a	\\x00800003abcbc2f77c56b997e6e27457cc25b01b6614bc039be3187d64181719e50d76ebec6a8c3ef78f2c3a1a14234cf0395b3198378cb8573244f6c087066099defec215182cc5807af2c0a74927b85d25f5b98f956434879505cbb6c887daacb06dcc6d9aed47aaa881e2c3b212baeb527bb15e0336deb9185b91b15403553c282529010001	\\xaf62851c78991cb83a4917dc919a4d378d6f5ddba0caab70783f9a8cdec7e25fc69c6a850214fd3df32c94755345ea2f03519aa1cdf6b3d58715069f00541308	1633872307000000	1634477107000000	1697549107000000	1792157107000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xfeeb23301168a05f78e9f339147f76eb5b3ea7a8546998b508d6643d9a8ffd757a3508a6d2c4a9ed791b97eaeb45a7eeb580c52440ba97bbff852a732ceec0a1	\\x008000039f68021c16d581e77573d8b54a6fb552c20603558e4286f31e6c2296820e9a545c7f02d7bb54c16920abb77c63779654cde117750ef5cb5fe9c8f550376676c89384f3e27733dd36001fb52f489825deea24822b76b41ebf508f2ab84bdf3039f05a0abb9e6798f26b1d55d666dde99de3b494b3de41f609d9564fecf8ad13c9010001	\\x5031ef28da4425011b8761dc9c8c092d0e8685d98783dc3160549ce97a2faa882a8c5ac1c93aa859981d487c8669a94c77d853fd36feb411e80b540ed10eb50c	1662283807000000	1662888607000000	1725960607000000	1820568607000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	423
\\xffd75dc036999023bf88bb91b3e79f425e5b0cd0682a2be40175bbe9b0ef5706e4c8ebfcf92647edba37ccffd22a2424512b024c2b9bf44c9b955a65aa5fbfbd	\\x00800003c8ed56f1331fd7b39aa2da29719dcf4ce8d7de2796f12809184959d29399f1a9d2ca5a0a56ec1a147170fe134fda6c3ec88a7532633af425f663d345e8b6d5acf4d0437bf6277b5df2199f693884b3340d19584df3387ad0477c4460d40e34f8fe1c285b988c1134ccd1d52078fa399fa348e097f686971565601b5105ea42ef010001	\\x538bcfc51cfd0b95abca00378393c4dd7d5a4f3cd80550754e166b36eb1cdb9423fab65883921cecd03198faa66766a9468ab7d50a6c25e941df8a559c0e3301	1637499307000000	1638104107000000	1701176107000000	1795784107000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	1	\\xedeb184c42d516520abeb6863d208dd62498828a6a6f68303c12505be8c521fea5012675cbff9d464a87779d2c491b027182f8adb34cb7e1e613beb84546cb1c	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	1630849824000000	1630850722000000	3	98000000	\\x78a0c45e38c0c25568e0e4b30f1df7a597ebffc9a4a30193053ba07002b0fdba	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\xc20faf906cb0abd7172b474d26034eed9782b82fa43d9e81ac58e98c472216d6d94464fa8f34a5013d4c62ba8ad1b17cc2636244d3bbf782077a5570ce4a870b	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	\\x816cb71f01000000005fbfe4fc7f00000000000000000000808ebe1f1a7f0000b094091000560000000000000000000000000000000000000000000000000000
\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	2	\\x6d471b4d534bd033bdbd2ed5da71c52324281fd4d3f01d75fa540560aef62afe056b3e19298ad7d668784418714cb3523089c15f846abb52e04c45e56bf48883	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	1630849832000000	1630850730000000	6	99000000	\\xf9ab3653d05c917cdb0936e5d250532a19cbc0dc37ae31c96cee0955dadfa5d4	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\x901cd72b866e01242b07c800c4f86a31ca10f889d5d9eb7153d3e17e1ba136e583328284771cbd49568f3da52d8a93e4c29b9acdb2f7b6ecb3b7554bfbc75c09	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	\\x816cb71f01000000005fbfe4fc7f00000000000000000000808ebe1f1a7f0000b094091000560000000000000000000000000000000000000000000000000000
\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	3	\\x4316e1112dd1c7a3583172d07a77d5a9a42645f48d506f4a5406477f5c77afd336269bba67e43940ed294d9764ad3b4887147816b70b6995ab6fe89746ab4cab	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	1630849839000000	1630850736000000	2	99000000	\\x7a329a4fe5e1bff6346e8b7af27e28c3abfc3a1261354d9c8c349492f4b7199b	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\xe18dc61c45f38a9fb1aee684fed20aff1f3c01e69c9738aec3268dabe2528ff9a0867d534d9427ad24305657987a81962db44ca83e01f5ba6b1e9662ef4a720e	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	\\x816cb71f01000000005fbfe4fc7f00000000000000000000808ebe1f1a7f0000b094091000560000000000000000000000000000000000000000000000000000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id, shard) FROM stdin;
1	4	0	1630849822000000	1630849824000000	1630850722000000	1630850722000000	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\xedeb184c42d516520abeb6863d208dd62498828a6a6f68303c12505be8c521fea5012675cbff9d464a87779d2c491b027182f8adb34cb7e1e613beb84546cb1c	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	\\x6c9322a5d0d579304d2f95e4326272c907009b083ef518a23c69c98e529cf31c87227f91041beaa33816780981c41edb71184e0aabbd8430240d520b1dd4d905	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"9PE256FT5N3YX8H3F1QCHXVNGWAGG3MHDN4J360TSVWTA6WSSMNB8MY4GN5HQAP89TDZH8ANKEG1FB1FJZMN7ZC6NH6QRB0CDDR4TJ8"}	f	f	1	915725870
2	7	0	1630849830000000	1630849832000000	1630850730000000	1630850730000000	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\x6d471b4d534bd033bdbd2ed5da71c52324281fd4d3f01d75fa540560aef62afe056b3e19298ad7d668784418714cb3523089c15f846abb52e04c45e56bf48883	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	\\xa5541783706bd451aec81bf91ee491eb0a222a128754332f3a8a02d1489fd65b48177b638230f4cd0adc8acde8a9d8d1ae1ca67bce16d675685d5906cccd3909	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"9PE256FT5N3YX8H3F1QCHXVNGWAGG3MHDN4J360TSVWTA6WSSMNB8MY4GN5HQAP89TDZH8ANKEG1FB1FJZMN7ZC6NH6QRB0CDDR4TJ8"}	f	f	2	915725870
3	3	0	1630849836000000	1630849839000000	1630850736000000	1630850736000000	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	\\x4316e1112dd1c7a3583172d07a77d5a9a42645f48d506f4a5406477f5c77afd336269bba67e43940ed294d9764ad3b4887147816b70b6995ab6fe89746ab4cab	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	\\x0326aae6d0977d9c71bd97f60c2d1c38bcdd2f331485a65bb91f289dfbedf669c886a24a17e19a0c30595d9a738cf23166ddfdf1421e58a653d060be35c4580e	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"9PE256FT5N3YX8H3F1QCHXVNGWAGG3MHDN4J360TSVWTA6WSSMNB8MY4GN5HQAP89TDZH8ANKEG1FB1FJZMN7ZC6NH6QRB0CDDR4TJ8"}	f	f	3	915725870
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
1	contenttypes	0001_initial	2021-09-05 15:50:07.603237+02
2	auth	0001_initial	2021-09-05 15:50:07.664178+02
3	app	0001_initial	2021-09-05 15:50:07.705779+02
4	contenttypes	0002_remove_content_type_name	2021-09-05 15:50:07.721215+02
5	auth	0002_alter_permission_name_max_length	2021-09-05 15:50:07.728437+02
6	auth	0003_alter_user_email_max_length	2021-09-05 15:50:07.737842+02
7	auth	0004_alter_user_username_opts	2021-09-05 15:50:07.743669+02
8	auth	0005_alter_user_last_login_null	2021-09-05 15:50:07.749838+02
9	auth	0006_require_contenttypes_0002	2021-09-05 15:50:07.751315+02
10	auth	0007_alter_validators_add_error_messages	2021-09-05 15:50:07.756768+02
11	auth	0008_alter_user_username_max_length	2021-09-05 15:50:07.766803+02
12	auth	0009_alter_user_last_name_max_length	2021-09-05 15:50:07.772834+02
13	auth	0010_alter_group_name_max_length	2021-09-05 15:50:07.783851+02
14	auth	0011_update_proxy_permissions	2021-09-05 15:50:07.790305+02
15	auth	0012_alter_user_first_name_max_length	2021-09-05 15:50:07.799901+02
16	sessions	0001_initial	2021-09-05 15:50:07.806475+02
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
1	\\x8e27725889563b53104fcca3d77de9febca01c2b03d56585ed32b224d0defe0e	\\xe20d66097a0e592ab2529c33e02ae829717cedb04333c1c79fe5344f4f4e16775e323c2daa0c93b14b823c3f61447f21ae6aab19edb34f7114f08bcb20e7a209	1652621707000000	1659879307000000	1662298507000000
2	\\xf39c2b0c142eb2b75b84dd7ce08eaa6a6fd52ddfc76bb380713305650733b49c	\\x89bf4ccc59b90c458235100b4d09175adc3aa23b8bad19b4dcef83938765d69dd02734a595d68793fd49d1bc406040069d6a019244d37164a4f3eb866a211207	1638107107000000	1645364707000000	1647783907000000
3	\\xf6a313e6eb5e0744d82104ab37d616df1c4f6e3708279aae34a9919004eddd47	\\xfe2a6e9214878c27a134a57e48097b6a5cc20aee7d5e4f5c6d95ed9ab6471dc18670ddfde9d8f9de1ac87a42eafecd6f3cf9776dc0f78382ee04286a2dc51e08	1659879007000000	1667136607000000	1669555807000000
4	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	\\x3833a475ae4efa15b172f03f514b50bdee2c5bb55a180606ce698c4725e01f10b5f0d194ee0a56dfbf3283b8640b3741988f6c0133bb13f27be36f5fdc3a810c	1630849807000000	1638107407000000	1640526607000000
5	\\x5da103c7425fe2926c96cdb7eca731ec3f6dc91c0bf550aa714918be8768d993	\\x769ecd06fffae45f20f247a9f1a5019e29709966ae546f58ab53e122f8213cf8326bc0269af78a161af9ea120280d399ad3b3c55364bb4564d7513545a17160a	1645364407000000	1652622007000000	1655041207000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x78a0c45e38c0c25568e0e4b30f1df7a597ebffc9a4a30193053ba07002b0fdba	\\x607850ef9c1673dc2e65e52ca37aa5ce575f664018b444b76ed1ce61ebf911e2e23724042a9b49f649355c5b5c0e56fda011f1f89fd3a6d62eb56cb373cdb57f07fd3b2ce74552ff508754aa732651efd22edd4e56d4a1e19880e6ad48b86bec37c62a4f16f2977320aa65d1e87b9f91e8868b523914edc58ae7dd009daa89c5	206
2	\\xf9ab3653d05c917cdb0936e5d250532a19cbc0dc37ae31c96cee0955dadfa5d4	\\x6ebe2f19fe37da73191317358ac1779a54df025a0e46e105ee2b30b64aa14d659aae56f2566da320f541d7e652e418c7925d06cfdef423e54908a0d24dc749ea5699f8143c7ea0dd8fb81fd53260b7f5fd1a65c9be3b0382a38f8fb3bdbcf67a7f2007a19ef05c9595381ca9c9a4dc3e931006fd80b0665f4b472a5c51f71df7	237
3	\\x7a329a4fe5e1bff6346e8b7af27e28c3abfc3a1261354d9c8c349492f4b7199b	\\x8a71b7e3803f6fc0ea2dd978e0bcbbeeeebd7fee9ac71925b5e6624da48b48e12013c7057ca225c6bfc3755cb382880efae542388c450d7b840119f2bbdf721e3dee259a25c9ad83e66183631e3429a540be44ade5cf5754c4b3d2adf6a89589e86a61188394f9dba28f11e9929682c816dc37aa4ffad19a93a6e0aeba2d0fed	267
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x9894ed87dfcc4c9c40782c78762a1c94ecde63e1c3727f062881c7ea1b4a159e283e6de481ea26cc7dd5271dc71b3c7e2b38fb719918de7e652ec78306b6c84c	\\x4d9c2299fa2d47eea223786ec8f7758715080e916d4921981acef9a51b99cd2ab453c4854b1baac84e9bf8a1559ba017ac2f97e953fd86ac4d7c2c0c6b704d49	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2021.248-02J7D252A8XM8	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633303835303732323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633303835303732323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b3241455631595a534836395247335235485737434147574a4b504457525a315244533759314838473733594d3654413250463247464b44574a30594d3950434651414a4537453733435937574153525a4452534a36365946534a4a5848573330545643474b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3234382d30324a37443235324138584d38222c2274696d657374616d70223a7b22745f6d73223a313633303834393832323030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633303835333432323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224b3958514b37313736463243564650585141574338454d595a4a4e56535730313145314d46395251453751544745314b4a584130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224a53344151595a5032564a58474257564852304733514b524258465333413035524856563958314436424b43304d4d45454d4547222c226e6f6e6365223a2241564130584d5831344546535843395a4a4b364236454a5038573658334139484639324b4d51464b3659564859444b3651394a30227d	\\xedeb184c42d516520abeb6863d208dd62498828a6a6f68303c12505be8c521fea5012675cbff9d464a87779d2c491b027182f8adb34cb7e1e613beb84546cb1c	1630849822000000	1630853422000000	1630850722000000	t	f	taler://fulfillment-success/thx		\\x8ab6168e21caddae548d37e75a3ced7c
2	1	2021.248-00H1EXG2J45KP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633303835303733303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633303835303733303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b3241455631595a534836395247335235485737434147574a4b504457525a315244533759314838473733594d3654413250463247464b44574a30594d3950434651414a4537453733435937574153525a4452534a36365946534a4a5848573330545643474b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3234382d30304831455847324a34354b50222c2274696d657374616d70223a7b22745f6d73223a313633303834393833303030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633303835333433303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224b3958514b37313736463243564650585141574338454d595a4a4e56535730313145314d46395251453751544745314b4a584130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224a53344151595a5032564a58474257564852304733514b524258465333413035524856563958314436424b43304d4d45454d4547222c226e6f6e6365223a22574638374e594836393953584546514d4353544e413144374b3837565446483939474442325746474a4d5732314b395937594a47227d	\\x6d471b4d534bd033bdbd2ed5da71c52324281fd4d3f01d75fa540560aef62afe056b3e19298ad7d668784418714cb3523089c15f846abb52e04c45e56bf48883	1630849830000000	1630853430000000	1630850730000000	t	f	taler://fulfillment-success/thx		\\xfd1260f90def43c7de64068a12cfdf19
3	1	2021.248-W12B01BP4BC04	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313633303835303733363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313633303835303733363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a224b3241455631595a534836395247335235485737434147574a4b504457525a315244533759314838473733594d3654413250463247464b44574a30594d3950434651414a4537453733435937574153525a4452534a36365946534a4a5848573330545643474b30222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3234382d57313242303142503442433034222c2274696d657374616d70223a7b22745f6d73223a313633303834393833363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313633303835333433363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224b3958514b37313736463243564650585141574338454d595a4a4e56535730313145314d46395251453751544745314b4a584130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224a53344151595a5032564a58474257564852304733514b524258465333413035524856563958314436424b43304d4d45454d4547222c226e6f6e6365223a224d574a4b584a4b4e4733394e3950584d56583656384e5159593542544e5756324531504a423346305139504a57584b5347323847227d	\\x4316e1112dd1c7a3583172d07a77d5a9a42645f48d506f4a5406477f5c77afd336269bba67e43940ed294d9764ad3b4887147816b70b6995ab6fe89746ab4cab	1630849836000000	1630853436000000	1630850736000000	t	f	taler://fulfillment-success/thx		\\x012169c02011e28cd10293a3d2bc0b32
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
1	1	1630849824000000	\\x78a0c45e38c0c25568e0e4b30f1df7a597ebffc9a4a30193053ba07002b0fdba	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	4	\\xc20faf906cb0abd7172b474d26034eed9782b82fa43d9e81ac58e98c472216d6d94464fa8f34a5013d4c62ba8ad1b17cc2636244d3bbf782077a5570ce4a870b	1
2	2	1630849832000000	\\xf9ab3653d05c917cdb0936e5d250532a19cbc0dc37ae31c96cee0955dadfa5d4	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	4	\\x901cd72b866e01242b07c800c4f86a31ca10f889d5d9eb7153d3e17e1ba136e583328284771cbd49568f3da52d8a93e4c29b9acdb2f7b6ecb3b7554bfbc75c09	1
3	3	1630849839000000	\\x7a329a4fe5e1bff6346e8b7af27e28c3abfc3a1261354d9c8c349492f4b7199b	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	4	\\xe18dc61c45f38a9fb1aee684fed20aff1f3c01e69c9738aec3268dabe2528ff9a0867d534d9427ad24305657987a81962db44ca83e01f5ba6b1e9662ef4a720e	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\x8e27725889563b53104fcca3d77de9febca01c2b03d56585ed32b224d0defe0e	1652621707000000	1659879307000000	1662298507000000	\\xe20d66097a0e592ab2529c33e02ae829717cedb04333c1c79fe5344f4f4e16775e323c2daa0c93b14b823c3f61447f21ae6aab19edb34f7114f08bcb20e7a209
2	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\xf39c2b0c142eb2b75b84dd7ce08eaa6a6fd52ddfc76bb380713305650733b49c	1638107107000000	1645364707000000	1647783907000000	\\x89bf4ccc59b90c458235100b4d09175adc3aa23b8bad19b4dcef83938765d69dd02734a595d68793fd49d1bc406040069d6a019244d37164a4f3eb866a211207
3	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\xf6a313e6eb5e0744d82104ab37d616df1c4f6e3708279aae34a9919004eddd47	1659879007000000	1667136607000000	1669555807000000	\\xfe2a6e9214878c27a134a57e48097b6a5cc20aee7d5e4f5c6d95ed9ab6471dc18670ddfde9d8f9de1ac87a42eafecd6f3cf9776dc0f78382ee04286a2dc51e08
4	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\xdb449a34be7027e6791ed93aeba92134eba52ba175dd28ef3990e4a11204214b	1630849807000000	1638107407000000	1640526607000000	\\x3833a475ae4efa15b172f03f514b50bdee2c5bb55a180606ce698c4725e01f10b5f0d194ee0a56dfbf3283b8640b3741988f6c0133bb13f27be36f5fdc3a810c
5	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\x5da103c7425fe2926c96cdb7eca731ec3f6dc91c0bf550aa714918be8768d993	1645364407000000	1652622007000000	1655041207000000	\\x769ecd06fffae45f20f247a9f1a5019e29709966ae546f58ab53e122f8213cf8326bc0269af78a161af9ea120280d399ad3b3c55364bb4564d7513545a17160a
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x9a7b799c2733c4cdbeddbab8c43a9efcabbcf0010b8347a71771efa838339754	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x496925bc0b8f1173348c45e67318c282fb4e0524407f5f808cae617cca25d9db1723d7b0628aaac5e47c58f7eef7f6d2bd25c2120b7f581007d7b27fd2b3fb0f
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
1	\\x9648abfbf616e5d82f9b8e0101de785f5f91a805c477b4f42d32e6c0528e751d	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000
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
\\x686422ee2a610ca159e191ca80771200f640d067181bf9c5c49443bed4a26e22	1
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
1	\\xb997d8b179aaeeb8ea841020e4dac3234fd4e49cddde59f1f2c2d59cb1266b781840cf0238ae5623b4b7fdeb505df331e703eda278376a241e34a81ec4c58b08	4
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1630849833000000	\\xf9ab3653d05c917cdb0936e5d250532a19cbc0dc37ae31c96cee0955dadfa5d4	test refund	6	0
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
1	\\xda47b5c20678cb547477f47193705bbe46e2b39071e9ffb264ab86b4d4ca750672c1e177bb1c52493730f26330714b7608521f525d1afaa87979f47dd8bd1da3	\\x7ca91115d85fd223a92f751778b42a81ba9be213ad10f3b25ed060a7dee1a6290b097b3ea5ec963b199db073201983fdc7d8c9c8d65c3171ca05fc3961726106	4	0	0	1
2	\\x88e37a582fb7fc30bfeae5692ae399b0e4e10e605ba09c15cde7ccd3b7d533933e8d2252acb73cf92d61311dd42936b51f4a2947fab09397ee4634ef6cbc27b4	\\xc376a42abbf21ac9b76be81472a6ae43588b6b1624ad9748b6c7bd7bad67a5f5f54efcbc88a9ae70d640e6ca4bc2ec9bca07ce2f3a52f7310d67d6362c7ff001	3	0	0	2
3	\\xceb4ae1956710a33ea9b6b378629d8fc944133f6d70871c45ff01c0ef0b31a71cd9da99fed50405170541994baba02d3ef8f318ca7eb02aa2cef43492db3c2f1	\\x52946ce421c3f9c89e72b78b7f67b59d81e28fc0bdda3521181e4cf083168650299988cbe0e5351ebe8430657a592dd32b97c7d8bee29c1276763ad10f890109	5	98000000	1	2
4	\\x63b5c28d1375dabe94760e64182058574c776b9ff8d65813e3c5313c66f5814aace2db9d564549930c38210d4f69c1e70258d4f3876767fd9efed67780736b34	\\x15b40295732519a97142a92ca15b2230cbb1ac59c540f280e8c0b3fe9c81f6d97e0ca1f3d8c4623450b90416b16c946889dd0814587fabf75ba20d5744f4a703	1	99000000	1	3
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial, melt_serial_id) FROM stdin;
0	\\xe5b57c988534c49cc53899c8867fbaf6b62e59ab8e85073ccaa3f4c22937fc70aba78ffd4d7848e427e31078d11144d2889f0f947fb58981a4cd4a9b095db70f	\\x4aa6896ccc5d23d5017533eed8e36686c3d4f7c40e600baf48ee842ad8c896fce5c09ac3ebd77193a7deca99f829bf5d142bfa6d9c6ff1c0b9922c5d19fcba81b55d3904fda7a66ffe84025f7ef66b7c0894b2de92607b1dec99c87cbf89cd4a16c0bcfbfa4d637dbf17c147bd262d3e1a419b31c7eadce6488d13b596e4b5e8	\\x8b24e4b44a0cfccbe2ea866df7e8d544689dabea0e455844b46ed93a62a50ce67835aa5cc3ca712526c015cd22e0575da6d3e43ef5264c7141396499df523ed7	\\x41a163a2f32ddd7e7692269039607fe4c152e525be4c2a749d0afe77a1c5ed6f02affa6c50523cb554419127dc36a41b8f9581ee6e4e49060e7a7573fdb4f104dd9fdaea82128b2744e5de792c5ec5e00cdea3d4927c0f73059ed0d2a8795eb91880e4aa24ea47e72087b5a88144c3e015c6f6faccf422631b352fb0a8f2ca7e	1	352	1
1	\\x02dbd53bee54bccf9f165be816b1f6edad64c057565dff7263517548d5025b9235d93df6b81161d11f5716662b44f39e27fedf96bb24ecf43232b30d15902f0b	\\x337b489a45b1f901b537a9daaccb091f907f90b81e6fd89083e466de69d24e168dacaa3bb66e62048c2ccea09ab8090737b1ebe0661bb5380816eb8baa5c0ca0afe68992241b7dd00ca725fcdfc426a00dfc7b733a04dff4a4c569b16837b6bfbce987c41e292d5fff34ee9cd463f4528159734bcdee5429c02245eb3489b563	\\xd0f200cb1605a5edf01ff06dd0e0d96a2621310eb4a786dc109d0d554e17be384c5a39dc9e7dc9454058a19eafd47cfe0a810283324f5f9860030d767d6518f3	\\x466642165c364d532a811bc344ffb9ba21860a37673ad299d7015fb8f0030432208869e718bdeb7a5f5402d0b588b20b245ec79f0d9858db2fac3e352eb0439bdb49cc58b6e9115651eb85fe92154d17e34e0315d95285b26ce4204b105d7c504431fc39d9d9aba6de08bad4b7b208e84df177b45a151fb817d064c3a8d4c7ba	2	192	1
2	\\xd6c0b2c7900553377de16f0c909d4cbe05b23b3d57b1ed1d737806c68e1b1b8fa867866f6a9fb1e460f7929ef3fcea6bd1f5ebd6eb2156bb636b273271285e06	\\x572cbf764994902e185382c1d25c0d5e5ee4bf94f24a14fd98643fd4b8ce4ddd7ed705c061d8d585ea10b2976b4e47957b5ca7d3244cea90f22ec2ee2112e8b507249614063154483530f71845b9e27ebbfd4f68291a52241f5b264156127635d4473e747d8fbd31fee47fedb623c7702f455879203ffab189fb38131d2c9f41	\\x5179205393dfb46e848fc69ac84237f00d2d8da087e6e9b9f9fffc5fcbd384d7d980d06b71701e996a0fc64f61215978931d499485504603ac09d5293f299782	\\x508a2cdd2d6c0b974ea52bb74e81c79afc6ccea146d44347a4cfabca6953a2285528b0d831b6f317216114c519d5c7892127a07e34fabfa4077a655329b0fd68f64b6a6fdc4a87019d0c2a114ed7010c53c6052e57550966ad55fe95a4cdf0f9ca36076b1e294f74ce8a2a4ff322af64f78fafb8036ca7f82ed2af72c4f4061e	3	13	1
3	\\x4160cc92f5398838d1db600721991c003026590c59bac36a63a40da978631aefbe24b27ed179bdee0029e11e97268ee18b6f5d512300d9664eb4c8bb8597b30f	\\x3619ee3b8ce0b9dc75db2f738ef10a7bacf1599e25840db569ace697b82b7cf9453d835a24127c37f884dd156eb586c1d70a1935b3a3728331a20ffc249ca4f7a8b66cf536b74ced68ea69d68c1532bb55f78b56f3ce3c5fbb43e3f3cf1de241c44c38f59b578662bbd2bbe1ed0ea6867ec53085f988fad9be641b2b94269665	\\xbb907ca20d519443ce10c9c7b1990ed6dd59f760ae96ff5fb199c65eb1a6ceb1597b598d973b3810e54f2c28fe2e848ad060c676f2b3bf2a777e907d7a6f1c5b	\\x6edae85ae34f7085c24e22e5c93a255fe247ab6cbb15f8d4a902b8b58b54c93c8a7307326f4bca71bbd1973a3627091cd2772b12846334a543fc0d0d5ead8d9e150a6ca4f4eaaf0ee9ac43b71a42207ad3149682174443bb27f7988fc9395e435e842ab9efb52771e42a503017932417c007784f805d4b7a866199343c2ff14a	4	13	1
4	\\x96688111edb73aab1d3f3ec98e59355c5928755a793c8fb9acc74a23abe3d04fc62e8bd6ef1d42bd551e4cddff91cda66b402604ee9038acfc35bdd77495640a	\\x41959644d4d0cd809671789a3aeae41f5178ba4a4f07948b2e2e79ba19d6b15ba5c20765c5cc551bfb1f491c794ddd7dcf8028b4c90f24fcd5662d29278f694f9e62206eeb5a3173cac1f7f450809eeec327ccab0838cdbdcbcb821b03ccb2bd51442a7d7e0956be3c2e0284ea1447850f7df8ec343df84c9a5cc047eebdab61	\\x97b41887cec7a26815b95162b454c6a7f58578d69e59f951711b9be5e910231985872ccb314149892aa97e007fce3429ea2d7663d2b96cc650f0cfa9765a0d24	\\x2fa1b875613b49ad0cc342ae09717a053bc762368ffbd7e6207d1bec50bfbf11da0fdba1a57e418018aef41ec1d1250161f8ec3cd9a41c7534339d128b08598c2e2747e67913bb62b64e72a8158bd11bb76e3f872c242736cb322d4fdbaf4b82baee3d727bc0d6fa54a37d1bb7409f9bea86d76d0ce118e026acadd114419134	5	13	1
5	\\x94ceb3cf89e26be6f1bede67a5d4f7f72e7ae8e6a061b1e0e85cd40e82c6e99f7f3073125964ba5b8fb07d5f7ad39b31d87cefb755f62a6972cdbfca8c2e7a02	\\x863830bdb71aaf7a2f549c7a6ac0510689c3a10340618d14ebe04fac0b6421cb111d389b8c3f31b186662c214d6d4807fe3852d3d59536de17a941670991d4a4dc2e0804f02d2e63e5de09f517581c572a301a827ee6933595a679723445337541df065269961a6a11f6bcd671037e4be9846a9880730e989188cc979ffa80e8	\\xfe7cebf48c7871b33ee465e79e7be276e788a26bc6eda2e5cb8f234e7eb4bebd72ef0892c47a486c7e838f7462d6bb16312c5d77992361a1030878acef5d9679	\\x89c22bfa60e81d13423be1853c2a8743dc259b67eb809b0cc16665bfb1737ac6b58686ddfeb7a16b4d9dd364f5f8387d7e95458794e4e9eb8c03b95ebcaa7afa038055abff127ea23f719e8b89afab2f0023441cc5bb830aae8f022215226d8afedbd2d3887c74e08c6330d5ea1efb3a4485a8f4c12465ffb28028616a58c883	6	13	1
6	\\x9a101060dcb9d2b9f9252e13def8b23b8d4f41d541939a7d9a0ce95f26149c8556376d68f66fa4e4976308702e5a030011eaba1e35152e2423cdd1b22bd76709	\\x9ba0b2a26edd2adee77514c796711602dda409281d735458f00766c8d07a8e4ec2d7bf5b5f296e25a716ba5b0f6a51404f5b1ea1a8ba4e4e490f79b002970e9ccefb5599493262d3ca51da6b083a73b6bc9ad34b319ffa53db42a8f73a5ede789bab260284893fd40e8caeba6b349175343b9a23bff35a9e4895be305ee1fdb4	\\x86ee7f8100548bf6398ae9a2b30affda254fea8bb428e06bf6ae4d6bfafe7583c650eb325ec8b4a188ecbf911100a18143a9234ade820130a2d981f79647da95	\\x0c42d07874bfb5b85306dc80d2eabb0f07cd8d1080d6582aa8edc2c4dad716f6181f114c7706d241471f1c6d7095ee897ca27d20db630ceb9307a6277ac8f64e89695ab2ebc8681a64eb0ea562506a55f30f7ed005e98763bd331f00b7cc6048f53a6bda2ae07f6e7f0825ab056067cd7e1fcb7771befd0e38b8f8a9370a8d6d	7	13	1
7	\\x7607dbc220e82a256218d701b80c0c7f3c9af1b588c1ae0f4505a3f9633a3d711985f9c8fe66ccf213b084fe91ede418461c079f7c250d08b3bdb30c697a2700	\\x8db2934b6ff767f8f513e9a206fbb1053aee4fdf65ccd944059792506c5785701ee8a8f8dc69975061d87822d5dbf5082f517eaf5431e2e869d781dabb5f3694e766d3fc92e199a535192bf302cf382364b79fcd9d17d937f13e72cf9a4873001095dd5b58daa6e292a91e3b4121bd846e59c57f0e2a518643ed4451c3b48aed	\\xa81a9111366e03ae96937e5f9ac3d20f2baf4fde2405e7928b908ac1f62615297609651d976a8bb4f3554081ab88386ef3fd7aab3f5f3ec9cb428b41ee75ee23	\\x7efc3c7fa80d98154a468f147e23cef302604a69ec9a5cd0bf4545eac70931b1424e5f9989022cf12c2093820e5ad97c226e106dc5379772305e15561084923ded90f0fe5661d88bad443352c0f78f50f2f3eed485e6ebc1d377707eff0c5b473cad06808bf111bf7469cccd4c5c60615de126b3c2710fa1f150b909724013b8	8	13	1
8	\\xbd5ef7602a580748a23fafdcf450ea473b9067c6550d8f2312d51fb59d610f3ee521e19c29777360d68c75ad6d5f05898dbafc2b99496a8f31b5bf7c30ba380e	\\x86d4c49f3e1eaf6c610f2e81b68d09b49459917706da6c683de4d6aee07255ec23c5dbd2bf947c73e43a295246613bd3fd1458cb437c3e1d58f4daaf369180d71e1968e7d0079e36d8983e29532dded4a4895161ddf70882e0abe8c290f2589156b383a8fe1dcfff60b3c38637c7e25ceb1f86f756941e52b208fbd331126234	\\x1d1acbbdabf34077070c9b002a9c1d93c1b986c72e8d5ebd86c06e5732725f00c6962fd037df62e3d41382ce32e22034ab0d22c4f8ed589bf8d4712135be0d2d	\\x5f560b81e2cb2ef66dcb8c663d8b349217859a337653ebffea615d157c42ac35a36026f5baf765b805c5a6f8846bc03b1f794dd1b2fdb31bbe6acc5e6dbb0dc633e35fa46bd85a551b0b32346eea0f8c2221a26b23e32bf67652c6643ba330622de6ad29fa5c234675fa47223cf9e7aa742ebfd764ffb58c0d06b180b71d0fc0	9	13	1
9	\\xc0dd27349d46c161677506adc2f1e049f24dbbcda7cbe44fb853488a405d1d0bc6887becd135dc1707ee8c25bea061c3511314d3704ba872c9bd61c9bb02aa0e	\\xbaed0e1edfd1a644d0d429942f002a9d8283d1b37838a47b14def7d4885a374fbdf084f54e3d8bde8664c01d3a930b8cc8d5f9c3c128b32e1d0ec100646c4b6ec1f842f5214c95504d0fc4bb48b5b7c61799ed9abe0bbe4d04f5a067bccdeb118485cd2f7e6c9363376942164e9ba5c6146742f6585a9109436a1dc9fd2a74e4	\\xde578357399bfe35dae2b8fed2971949f9d07876460f27ddfe3799a49b019f5a77ada872bc81700e343e5929a8661a05dcebf0b327e4de393aee39316246f820	\\xb742454cefe9a2f5b02dba840f7a16f91cc0b69cfab513bb3a8a0509f2765e95db106234d0d92135485b4826b0b4c4c48ee03f560fe4d248955495959df716ba6155b2cda42cbe3f4151d38c701b938073cc808cb84c43c40927570d0795a179e3a18f1dc2f53b93bc840eb0ec737f060813270c80144673fd25b1aee0ffa584	10	13	1
10	\\xe0ba61c0fcc09136809dd621abfd8385cd2940c58132d604160aaab29e2df42ee1bf79fdd777239d7fd16f620ab4037124a89d33ed56f35c42e2d95c7e511d06	\\x1043e2e40acaab79240367d99f8df5778f3b5e8b424cd8d1dff62b784ee9933505438e23db6d7cdd825fbff3658661f341bdf1f6295f41a96a5fe5e227639b775c9e5cd050db391a1639e9a88fc0265e9caad10f6a425f92d531f0bcefe60ad66477d9b7e0bec6181ff836475cbc0d6773ad8765c049fc207014d6f8032360f8	\\xe02c3e03caa6aaab094ba58ec2043bc49ea18e32aac6594db12d49991de69e1a9458593359a483593d932e8976b8c1d2c758113ed551e2627d99f4a55e9cdfaa	\\x38ac7459654de6022344746f0eec54dc23d13dcb9602758d01352f83bbb897241b4bced05c01636c40a2d941fef572a1f839141d7a3f4863d285c45f32231fad9d3fd888023041e102b990b798393c91a8028c6eb2ce96463bbb298d914780a4b61c619ce3f8088a17203e4dbc35f8dab767d65d4b612cfd3127e89e6011624f	11	334	1
11	\\x2bfa1d86f31e681b7298f494561ca423aa147c80749df665d509044a2ef4f9dcfeed7e473d46739aec1649dca61f89a7078bdc8165e4973785e8880e2bb2900a	\\xae9a46df0830c3330b8ae241abcfa96e4fba1e15ea8244dbc42e4691c187b83f2a902cba9236d38fbd4f858ac8154b3866fb5c7c2d5a1ce7191c098a2474fad0621659bc9be8b0fd791b7682b479074d079d016c5ced39d9a81b02328a40dcd278ce122ff0c222981fb7295f6dc8a3258d2d6b95b72fce2fea3cec42aefd4d92	\\xfbe4eb1adfb3da09cf3cf88c2ef1bb0b8de9885bde238b7c9b4e038ffdd326a13cedf8d113695ce4229183c8f9b9547da2ca1e386ea379ea888ee8c9f5f03777	\\x3dea638e1f624845e5a3606825849a8e15be0fde876dd5574502b9b3c09ff7be3ae1c23c4425dbfa2588bd944c4c7de9dc77507ab91d1e49079f5a77620c8a1bf8cd6c6cd3d709ea2dd6cdc03dfaa56c8dd162254842d8fedcbcf315647bb99e9c927e612608b2bab06a3d1df77c3609b2d729b59fc696b46f110b5e1a8dfaed	12	334	1
0	\\x8c07ec7f915212937482c1768c15e11c4ac7594529c8021fbc0eb10379897289fa10709151fd7d2d75b3dc34b96001253d19a7b55726287a4f758e5e32c0ef03	\\x0d4f2b6acc69380b6cc76bacc47bb9d58f0bd71595b29bb42c9240b79804ec022836df40b9c007658b833082df74950e6fdf90ebbf9767ffa89504b9feb4f332e8cebce39190491d04e230b1432c4b1835098dcac6bd090040f45257ec0a9573da4970e469b109cdcc5fc28b78205a99c649578fc10edccb740bbc6d9b26c689	\\x3fb670a8059e8413c0d1a66193bc9df570227f3e9267e418ee6392908917720c16acd05dcc998f6821212345ccc498da2923a1db4dd88a95945aa00ccdaff7ba	\\x420de4687f939f2bf6685f1525f5eb824e69e1d09a6e2f42f723cff45e3f5ee61549d33fc00cd49aba730248d4ba015d9be6e59d4663a43bebcedca0760375b1841103159bbb3110e6bd77fc07faff20b520ebf650f6e6122f99db68ae270fb7c50ff50a0d23b89f5cd291c01ddee70a4ccfe9e5ec3f3d9e7b77786c8220f564	13	352	2
1	\\x8ac8bce6c1aa2acc7f750e5181a9301d32f5f50e207750829df88e22e5113b7b6d316eb8f9e8e7cb98329bac6b245f80af2ac813445f4af7fe85a639bf33130a	\\xbba4b027a6909fd9db35697b5e204ca2dc443ae49e8a9ff6202d5bf342e442a590955836cae17867972dc6f3cbba7f61ce052181f9ea14ce72d65b0830eaaf18d479807e0e0af9e2fb2b8e8ae763ccbd34663c797767c1869e60135c5f5b44e2575ce77e725ace12bb9e4d139279a33901658677d3a6bdc3e55aa0504cdc6573	\\xd38c457e91a35400a2ac3dbbdcd4f0b4cc5f5aa6df820f51dcdf8027dbbf6e83e2196bc4fb54887807e03cf53ba6972ceaa8763ab12e51f23734fadfb0fdb654	\\x55a0ab7897ea0b8e5b06e48ef7aab329844e6d2fcce51afebcab59738007646638852088ff146f132b60edb23160245e53fd919f25a66d812ddad0831f02140eb7c89023ce3ca32775c7adc11f82bb3290b1ac45cf72f8f424a232f8e583a6e9e33d66948deab908b2a7476e14c75827d384be1bc612b4492b2445c8fbd0eedf	14	13	2
2	\\x959ae3a6c94c0081a0037d6aa4a683350ad0e1f8702510d1a7cf72f1b8de6c4fe85c0d996a5765356399ee1fb012a57791e9d25620fc4eee6f6895f2fe931d0c	\\x0ed9ed62347068afd42cf21029f70c04541b6d2735fcc270e77437b0d602e173edf087312e46a4a2223bee9e8eb8cc1a52fccfd4f25f3518cb819085ec39037e91480c20861300c47f6014b15b871f3bec6fb82660962140d8f28d035f18146faa5ca60e5b9b52d262381672aef8b48e0191394324922075599d81d7160aa479	\\x22d03e2c2a07ff27b20e429a2c1bac189139486b84e0ca0b1dadb79e5fa90747676f7e3a70a8325ecaf32f68cda117e39c6808989e1bc97641b1681d14eb9b73	\\x4a93baab33be99ef7bc907ac1d122e9ae162f6bf68e0913c58f5fe4ac90a932b9fe20a4d6b673d70c446cc985d4a657144964e148d851ce58a58f3b2c13831b6381c5d896dc3fe535f60c0f4752068a15330d4451d8f0db64dc1e81912ff0ede8d27d7c58f35356cab89e1a15a4179706ed3c3bd72517541e5cbc08a20f836d3	15	13	2
3	\\x68166bbf0c302485377bc6d5fbf23221d5809bdbcbb2083e91bb3612d0d2286b3ca9b5b9ab60d419d2a99544a0a9fd6ef8c1fb687fa67068dbbe231438d08a00	\\x2dc68aed9bf9579954fd115f334672340dc587cdf4c7452c7098cbe5e7072216a4045281d904507adfeda3ce781df001ea88da830bf5c306af9990f52b635597cdab5a100edc85427bda0022442038b3b06721c46df3512ac9dbecb21d053d25abe7a63897adbc794cf3e242aa9b7f47761a8243b44685538cad983a0a4a2d1d	\\x2d6be5e2f3ca1b2ab4540ec655ac29479a8ec39efa62d848d99c9958f427eb286fff2079c434a7ff9e6f4f71500c5a0de125ab13510bac23e73bbaf029818e45	\\x357835d8e69a0223de552c77c2943909834975967daf8942993c6b4bda7a06cb48af4122f590fed9724dfb20dd8fa2e3cde93b950f5a5911a8cfa5e49000103594b1254dd85707795ebbfffef9c13caaad22aebc347b1d98937f7005997c5f1c69d32e45ae7e16c76eb828a91174d44ee4b9fc61071aca818a9ed3b46577824d	16	13	2
4	\\xf28aac60db4679e863902763737f530f936d96891546c0bd79551e117d41829149b12d2433001414a949637d994f2dd00db72dc73c828c9f8f7bfda5ab1f3b06	\\xb9f74079c61f9be4fc088e29e231b39a4cf5e53a81693a6eb754b975f23c03b4739c558315fc5c9b14a4f20faf1f3ca6dfcafe6f51ac79d8f8246171d93a76347a1dc3b909c67764179ca72c00f15f07ec3f579d3958ca86ffcfca3abd0346ddea96aec7eb8badfa830b48ede2a0f970edd67df88601a1227d87e4b36dbecd46	\\x13c4d1e83826a0c2021b8776200e421a0fa2de9a3e16e06e03b159de86dfaa17d557a0485c2e07791a36b30114beade7fa03dafe9928e3500e081ce0c4e8bcc4	\\x50b8fe6ef88e5c2c8f6ce611130ea3d12ed5db3d00b5b733d2fdb85bdade42dea6f77eb98a3bce28ab18b0a5c0fe2264d3eeda27fbe3ba208306882e91a297e47aca72bd9e91eff1e15392b481cb5e4df17156e4a396af8c1545b7e71da3c707ab1b294933d6d43514feab6a419e925b71017bfe6cc08d76abe27572d06a076a	17	13	2
5	\\x606f9edd546e7d19f0600ab113c47e3cc3e255c5e7908fd9233188e91d5a2b6989a6b1cb0cac94d207ca0b051bebc928d8468470391a0484235d96f03f00ad00	\\x09503f4d99510717d4b777d8ff38bb86ff2789eda87b13d1d2c6c7b4198e78420140e251a578af8b06983659e8e86a43d342c28957ccc5df68b7b15f806521850ea15fe24bf2a63f4a2c9a4be7720ff83604ee8e9b85156f0057628e874ec72ff0457607470e882e974f2de47dcf424ffdb0ddfecdeb98ede537e07fdc664bd1	\\x2ec4662e7aef8b7c9792938330ea17d657c1f785be29490b90f1ff14dd9d93a184ef82ecf9c0c7734fbf806055d9822b2bcb00a596a23cc9db6fc0cac65ee801	\\xbfffad899ba5b0feeb257566bccb0a7735de3bb572e57583b41dec333a1b64b6d5852b1e3e1d9415c569328fafbf07553d2335f9906f509ef2de62e728ccd440b0fc682ec3aab5bb4dfeb58bc69cf876c51eb68a6d715c55e22cfd466a456da22521dcac2d1187304146b08f550b78a543cdd2997976034c34a06fd26c3f4ded	18	13	2
6	\\x9970343d047d38150670ccc22c4fd1be0579ffa9860579a0e5117261cf9542d314c376fa629f27d53826b8465a804c6970ed35d92f6e10749ad853cee1ede204	\\x0f4bb3487af0686dc80db1063909b7b3e15c9cc926dd075cc2b81e4b02d0fa8df3ec9fa076d084a1a924c6cc282d7a730b83b4b33afd776e59c79b6f9cb2231ea108753e28a908dc852c32cedeeb21e5188f4682c9fff4db535885d704fd277ce732501a1ac885b11c043af9f86bb3694522234fb0a4f21ce8d4ea5ff19c9379	\\x0e5d970159068b74dc74e607b2c202229f9b4ceef36f0e9693f70d63836f9674d3313eb22cac058de1556eaa5259d96626e1f43f9f415aff060f12988ee5ce7d	\\x9da321f2f83934a4d9eb3f860b49bde435eaa51bc248d36589c4fb4f125bc015128ac61cbb42fdfe2730194a93b42f4c025c6137c00c67fbeb9feb886eddc3fb5c4744d4e39cb10cc47136c1c8a8e1d67f755c251b0dc3aba7dd261eb5e49d141fae6618bce9cf221f7ed429b6a94651e0b4ebe4f4f632f214438fa9a7afaab9	19	13	2
7	\\x90e06592cc6ab804c7e0c842995fcf1b916cd602aee05c77f4b8e9ef24a8902f271ca39b5ae75389a3464c1431a3a0f5a182df126117bf3117bc31bd8149060f	\\x3d0204e14c0f184bb9eb6a3d6b8a530dc8de3dbce5318ab74f9d993a52e0b71d717fb66297a1b5b3553c15ce0bcbebd4560bd0a5574640dd46b0d35f9c4d0af5971294d4f0c3dbfc2fe57e583abb2b16622b5f6de8b524cf37a24f6c9e71c31ec3993ab7e7f4b182b8f935c288de0e9db0a992cf3e9d065043e01b722375b565	\\xe3f6ba5251f9e90607c4983f1d02b8ad737cdb25a236385d46b615ec65919b4063310d0fea6baa92ffe695068b56e659cae18e7982c7c2eaf721a40ab8ae5411	\\x64663a78bcf4f90de918553b2c265174849aaece285488f7bb051da20c55669eeb2a7bb26cbd2279e665fc6d02a51cfaa33e1b13249cd7ca81b8a6a640181b3b8b9187fac7fe660e0c376ac00a50aec653a879e9a5026c0d69dcf13f320a25638130036f046f004b5586ad86f9d0b5294749ff2832ffa42b5ae1afc443330560	20	13	2
8	\\xd1dd5f69a521e43fe0965a1fbf0327f205124aca036ad1fdcfa5a91a649427c4c54c8a84b6d1636f4a51afc22875fe13a9fc12741b7d9693bac87d637faa5d0d	\\x7eabb949f1d21dfd9931ceccf72e2f1134646e97c2fac2faeeffd27008599e05bb4d1dfb41cda5b941e2552e0ad13c7a27d734a95021227a4e40868defbe1888741ac6f3b0428fc2dd619403bf767100f4c3c5cf4b76984132f319f1606b641d3fad8925c9486e8e10b59e2c04694c3ed00cf651be817e70e4860ebbc6d44f02	\\x529c1e0fa7fa07392863e6a3e0868afb6a4d8fb1e9319ad6a03dba85bcbceca7cf2ac3fdb7f33d6b6cecba16630d96cff212db611fb99d4a6d49f7261179bb3e	\\xa8bdd6364c52a5d78a995fde184ad5e346eb7273e494c90b3ca77c2c0114f1a664227ed2df9f4e4634608d0b3983acb18db729ce0532df5962cebb0d3a85d05e9f83ae780266089cccd79ec565eb4d6d525c136543df82e632deb72d260da254f8a2c1ffcb16e54933eb4401e92d55a88eb1868941b7792a71dc866ae3bf8d06	21	13	2
9	\\xaf47a7b8a14f626275e5ce0a11cbbeaa03dda4a41e114c53e17e116d6502f9b5b5531f5220b329b0124bcc0dd5382afae332ee2ae247c71c80da6e699ab31306	\\x5d2c29840e6b848456378e711298ae6c6e516d4868a168ef0449a8093b726093bc03a4f61019d18d1dce7889a44f3833ccc35bfdc7ab2f8a7c1e9c49e0bbc4f4258c8dd5ff53c94e1092c7b9d11931f7b324fccdfd75df27b89de99c7451048c3c9e37c5a695042c4c0d4982c4b5a14aaa2fe50dfe1ca57f27436b6dc8e6dd4b	\\x75271384fb34482a438d50f99220502ed19bca78e9e3a8a9f7be8d49332ce6b8853380a9d6e9fe74f1429438301b2186c32efc8fa53d967940d9bb27e53b8eb8	\\x9655aa340bcbbcc011b95ddb33c5bef92fecb6a9fa4203ba79429ac6a1ffbdab835a3744d0ecd419e9c81b22ed43d9f9f54960ae9051c0f1df54ca639bdf79a67919327d9f3e08283049e908d9138fea4f732eb16622e38ee3457c7c1d596e2972ad41ae0fdccad25c9162230f706bc80330effc7df75213bde484231ab5eef4	22	334	2
10	\\xf48a8c7983180638f87ef68e42845b898b0a16dfa254dba62d5b60aaa644b51dcfb423a370d8f611ca7e45b831a2c818685538b8f1bddbfaed3c7cc690fcc80a	\\xae3f1752239bace4dad866fb49dde93f0be44d2646e614ad2da9445fb8749014122b67acb0290929e17d554fdf6935826e5f5f0359c2b27a57e59b86923d2cd17a47fb3e133c4c6e3c7c9572d041cd16fac6e351065f2a672a4b3fe9077303bef3b79fc489540a581075d65dcd0e05e2b75f3bc5c66a941624338236c5e42a36	\\x5aefe9b16f6d6159ecf8debb42425ca0ec17f091606696ea99f146974908b0018f225f528735f3edcb63e448fa46cc5933600d63221a5a92dc1c123e36a9f06e	\\x0f0114ae6f90e38a8c0ce36a97e9cbb1d907d80b9f67a10b942c7036a7d95ca31cab0653f7ef2aab0390c22c327c5918e3cc5fa58f3d3a539def76dec1496acb837f0d73a07f86c2b1e889bc6e939a7fe6e3fc5e37eb570102449bea37bf9d2efd5b71fa85292417314abd3c38831a5b3f89f77bdf00b87ac99a87b4a60a2666	23	334	2
11	\\x3f85c6642e55de5d66d6f63e2f87daaea37ecb01603f0a87a517706300431f7ddf1b66f8610ef8575d98e7d4395795e88ddd4de86d081aeec92368547d971905	\\x70b89d99dbe9fdf5aa9a2ee8a5caf6c9d6cf52c326c0b1684effba2549880772369025a0a28415699d641d4394d4c063834f28bf19d7ea0439d37a048972b30e1168cc4cfb42d387aa5bd220dab6eaf5130f1679f3a6adb101ae5dbd9cbba82421bf6347271274c2b57ae4750af7eeb95709a5013422f2679132919b620fd473	\\xdc28616e645f81412f4618f48b1e0ed4a74bd1630554a9e8f85133f29444c4248be1b7bba9651f94f2675654eda4df9679f7727514dc9d190a0d8eccb8b05d7c	\\x6ba07bf76277a1c57b41b57938791f12be221f3535031cc6b54dc6b477ec48b441c10066b2d8995bcd8ddccfdaa6e7202071cd6e95bfbbadb66303f264d4d72217a80f87168ff51ac1f87d26b53ee735a6ff744e563a7fa7603958227849a6fde706ef156c23f0b03121fb27b6d194e431432024b4c998057e766a5788f05662	24	334	2
0	\\xbc06f0a246c82bc939746e266de5e14904ad5a6b0e43c38feff2e642b667982070450a3f7c4718100aa8a9c5ba3b895acfd0c118470fc3372d89956ac3c6030f	\\xa95ed58ec9ba1f4c8d50f9f399b0dc2b1f1d7c0ef3676a02bd02ae131a934725aebe06a6d920f7a2807df7996ad1dccdd507967be39ef7f1150304b1650170a88c458b0cb5d46c6b0a7e86bb3dd6a9edb72e7eff5239c7b7524210c1f15a7ad552af2a319a447e1facfe993bfaff637b0b5c63bb1134acfdd75dd914883ea82c	\\x8887ebb07fd3757c0ba205f6b6cf6da888c91b4109acbb77438eaefa8cce811efc3226970a89eff8121af65a01247d83b2b40b4a2188182b79736497fd88c790	\\x84888d274b506adfcfa69128147e89add03988adc1defeaba71b38eec75bca2b75629aacd0f9d8d6f7fb28992b66fa0b0a75bffaccf5dca00e9a02914ff725f2c0f41323a37176c57dd2c5d092e5c64dda6e16fcc18e3e9dbef86cee51d04ac19aea8e7248317fc0c0abc0199364c069ec777c048f20bb5a18a90b8204e200c2	25	267	3
1	\\x088e799d5f57b50fa27b8267ad08ed28076b9589b5687ee28f4c65551bf304af007734dcea907a2f392c9f564a2b19e251f719809116b197d91e9d57364cf40a	\\x6227c61c3466d4241236febb6cf4ed30ff387298793e71117e7f372aa9a3825d2e16e448d9cc1b7979038b152d0a72a4ba89d527d9d73ecba9da0bd6e09ec4be97e8bb698de926dc0cfca99ed7ef646d2491d2c9d5af34eb353ca8c0b7880ac18ead9495a1eab5c50280c5b418df9275b516aaa1427b6ba3fb22d47440860b6d	\\xc93c3b12e82158b30a96385558f354bc9b44ff862da2bd133f2bf51bd23451a0b9d813edfafc8a870ecdcbe439998e98eb4e228f91a442e79b95222008ff2eef	\\x6417f02a13b963a570c7fbcedd3839e10e2b89a0afec54b7978deea88c7d0859f11e91c9d28ec3bef4c406e2e8999323b19035dc94671818b9fe2ca8ff7b7e9cb2b50001dadfa1bf8af1126e87933eded8a7e47494468cc7a059729b2b56a704522091690b331a928e6717cd4cdad0f1078490876afd50bec757852861408462	26	13	3
2	\\xd87257bd8e197e38b2e35cc2c6e455c85a44445e5d218161f47c379dd0082525afe6b476f9c0e5e1d42d30048fad87d8e9711bffc6a55b42fdb4aa3b9d6e3f00	\\x0b601122053d4d32b5a7ea65f570a5c7610fa686acb0b7407fa0cac083d203bb44a647ec82eeed7194d07dac85428b457915b10b554480190b2670a3872987948dfaa11cdf4d0037febe8fb3ca83a9c954918492dbc4528ad3ee16d824cbe176a676700cb2c17d52203b1b8856d1152ec040b88bb0dc72f2b5766f08a2be16ac	\\x7c7563c512ab2bd790237b4deada4d9ad303036e2dffe3b6b035ef702bd272767b2a2faff68f3771548208e52cc4f817a821e1e33c21396b04a001d31b35c3fa	\\x95cfe58fa8e28e95c531bec18d5355382bf41d61d04c3a983c6afffe67600d599829d56e228bed2e3a4922ed3599aaebd7aaaa244397d0f435a70bbb4966342b93c408821f07cd874ffe1d1cf5f2608d43ea72fff16574e91516627d0c898c8ba3d330c2221e23b5f32193f53658a6de087f599bbaa008fe65f3e54f4da2ceb8	27	13	3
3	\\x568a980179613dae959deb3f8e947b37cff37edd4e20cd0fb3d05efbaf434a407a6d90870f1fba8a7bc9f833ba8fed1123f6d49a9616137ee999f4a5c1145d07	\\x32ce7eafeadfb1d23f19447a6eb41226d2f6e4356c0943f6334e4b397ee12a6e292e5c3c212dbb8454f03faa07d304004ea65ad7159047edb1208b3303620dc668781c7a1ba9093d54ae3b02bf28b21b751d15a6c1729bf9f681a111fdd5550319cf46320a27c7a844179ec02bd30505a984f320c0a790ed927b194e657f5416	\\xdd2906c50a64d26b5f867aa09d240b22272b571df849f1a9c2344c39c0ad56e953f9627cd8a4c624da586fd3e7f1dccffe69393af5be9c322c306dcc0d19b842	\\xa87fb8f523ccfeb4ac43097c3c110c068588156fdfcfda753fef878c30d5b6858280232d128b1e8d7d79a6e6dee08f6b4136bcd42b9317a35b62bdb0a8f6bbe6c06af9858b519030af9a72a3d0fbc20e2a31dded83cc9658d07073bb0b1c2da950f6c57381692e3def0e9f0c347b87802c5d460347bca37add19c1f67d583a00	28	13	3
4	\\xe02ff15fe014c3bf96a1273536bff88a21c79b21781ff91f04c0b42f9183339b904ca8dd97d67666ddba6341ec0bf390d137256da9f2b76ca1d1a84d24e6e60d	\\x1833549ca7102da29807e208e690539a6aef7d401de9f9d7198f2157937f779189cc4e4b57592dc17af9cffc605662a85f4e1738f733b0d4c19046e0a4e77b32238e9d47b03ed76f537c53fe26845f1af9afa49c29e2be7be43940616cc52152a914909cdd468c587fa95536a6cda40551a210ff52dca5a62765b2ba42d96d7a	\\x0a85994676becccc7cebb22620c88dbec25f69d5c90a293cc19b9db4ddf8a2b6af7e58c19cc978aea4e0ce0e7b8bf57bcc92d09c83f4ec851d534b921e139730	\\x01e7d7a471cdc2ff74db7c69b02b9a7a5e4d7ddaa3e08a63a3e78e8026851a190b50e08f80389526c6544af40ead9956d7351f967969239fff4c3d8611a803667759a431b0e0f08d68cb2156ec9f998142aa296e822f86c54f2d9a6fb7d7773915f0529fe8613bec0db6b573a524642bdd420eb5f272b850f2a8e900a4276a4e	29	13	3
5	\\xd86624ebbcc9327a36836f8fd3964ba759b42b89b145e30d23a7ec76207661022a7fda51f6d8f75247ba26cbb49ff31ca55525777370bb1a0f94702a7c66490f	\\x1dc6a937b8c3c4d085a3421bf1c73117c60361b3bca783147a55baa0402de6ea75bad04369ac7c56cdcde567c14056d3a1f44db34dfc9b1b2577a36689b91b5b793dc1159b3866698c5a3be61d5daf7ec1703aeed34bd768e6b8775793e24bba36464fb1f1500f2bb3d4db857aea0e5182450191e296e9b6bc19b8f28bdec7c4	\\x6851f9c0b1c01dda6c06def306169bd05bfea168bec242e731b425c466a2b0736bd347de27e1eff2e6a59915afdd469ea08c19f1b62b040d19e2de8f9010c899	\\x34bec45e5d48b9b60cea4262e87e1752f3a229627701e808a9dbc403a93dce03fcc8eb92dfc9817fac1d76151f1b3b5bfc16310f4e69151d5ded1c4b73b48a279eafb50cab08c8e03eee2731bb22aa453329f0b11411e14df82ed86a3d7b2c29002df60665c75584e5cda32ab8a815f4ae7f115ea7c061c00c82b480556b8c7c	30	13	3
6	\\x0aa3338e1d7d6b44b8da8107de465e4d204e746eaf7b5ab7ba528f673ee375e1aa6c26c049b281ca0fcd30b0934646b496a334a0e1c97113d4b5e784ffe2e605	\\xa1061c89d1afe425d11014425560c44363225f6a30a14a2297f330e12717a15bd29f203c76770b0cd9a9e1ac3bd7b886d7b8aff674b63ffd80f7dd712cacd1f3fc904784a80fb8f84ffa7e454b5dfc62cde28b4094f6ae208830b3502e6e0b80b0b49d046d7afcf02da338ec6f78ad36cd72ee07aa0d21f6f13d3df5c51db3d8	\\x51269e7a39918466798810397c28124edf5265264b3bbb3e137aaa65719ffeaf5cf4293ca9ff6a6b1b8f157d9fac3f949e2096496b34906edc6b498be596fb77	\\x4866280cb3d87ae26b195ce200b872a8db5e52b408785abc7735577ffef3c3469f1c7b9d2580c90a70b17e8237608bbbdea713d2fc81a4505e3d152401370b3ec2a202134984f7b296054140ca961ece9688c0efb6b2c3232ae1e67c57e972f4d199fbfec9b8a911efb6399eea3b16153aa389e039ff4f65a53d2264f52c8b37	31	13	3
7	\\xc9f6848c2bfe5fe2773c6d417dc4f045fb22bf43d31c21cd887cdcd4bf6a65ec56a539b53d28ea70105a14262334b6c260e6864c55f53ccea316f95dfa967a06	\\x0e52f03c96888aac100de9abb0cd539f4873a81ad6b8a65e615437825f29be8467e2bbecb44afff1a7ed973e73b01f86f61e3db66c6bfbf56aa30a3d53d9789f9178bba75e84ef529614fbcb81bb4eadea9d00211afd5e01e5ccdca337a41dd0f2620a6d975bebc57ecf25194da296f7790ff7abd4a27a070315d8063f7fa6da	\\xefaa13eb753422d6303a3db867eea80428ae1fe28f615dfc07bf1996277511d87a1efe99e7381a137e6f639192cfdcaca2fa6d28d77af39cf95d503870ae01cf	\\x5b062968aec1100da68d440b761f68feae1adb5feebb078c304ad01230c5fcf4561f0b897cd739b9461b65e6f00970958176928858b569316944aa7db999c61b886acef54a0fc66a06376c3061dd80b1f777784874d31b2476cc4de977caaa8596d1e4677908840e92587480a533a1222527968ebb7ac9ef49f45aad615346b8	32	13	3
8	\\xf9b8108e26a6653e42305c89661505453dcb0639612404b0c5a3c09b4afa169ad7553a091a404206513cac7f6b9831ccd6824a257b516089c31321bcf3898002	\\x44e4c187b9b54de38850c7427945c5ede9e292af239dcc586c76897f3d9dcbee154d13eab1a14204d08c9ea6686a6fe25217e56b6c4086f8df20fa87a482b326aceb71b60329344cbe4514e52256ee2e4d1c108e9b29d458e9fc7464a95ff1366334e7d1e5fe38426a0b64516f7d096391837b379c90b883f82f7bb2058e1101	\\xcd35e255e3df6a53c8a94d1c24563f7f46728a116da76ab28f0c5f9c86b4ca7d7d51f9b77ca1a3d08373a80033bde03351d5d2799892c5f08e0790a3f7a3e675	\\xc34ec692b120afe5f3582217fac65d5974d0f184536db1cee4ca11e1e2df18eb8a98bcce2601a3d57b1d0aea8944ed0eedadf2a8cfb7aa49973e5cfc0667d78df751b78fe1c5604b0f64c80676c6fe7e24dfcea329762d52999aed8386537e00149a79f4d7261d0676fb6e5f68b933a58f20c86b132c4a6b424b46141ef1a9cd	33	13	3
9	\\x8172cb62f58a05893bd56c4c09d9b3eda98a2ff49c83e80bedef723d9d00091e8cb43cc8ca4237ed94648f714248cf42fd35becaee0dbde0bba945e2083f320c	\\x71a957a9baa2729d4cd420d28d0531228f5e51804d8544730bc09dda0390d490c94143ab50b058ed5f6dbf01e373065e4c3755e965ec1b809f5bb1d4188c12261dcf70a083bdc46304a39c9fd323847ac93bc9c6cc25c2f85801ede0c1517536b8fbfcf3490d1015c0a4300decd77cfef5822bb7fee313bd2765ce13de797814	\\xe1815073d0c0507fe243493982f5e0f366c97183a0cacb11f967672785a6d046c1480748de6aad2d6dbdc7bec756436f9d876c2fba44c52030e8dd39d3af9bd6	\\x61d4cef52b507442a5268d66f49f3a87648484bcdb347bf41b53de234980ce5f8b6bc953acd5e12a30adda8af8b549a47497f597bb0f719bb8287d753d10fb3d4bb4b1df7c7f5e3ac0718b1c4434fa13c4d467e649593d81c66e24b1383ebc6d8269437987031812f0883c75df7c8ad15225d7f5c1a9628647de14a9ff272779	34	334	3
10	\\x6b0efd307a40a17facd56a3d0178bb960733db23749f96bdc7f70bd8b0aac6b6a572547a43c9b6a3e9c5453e9f3a117167049cf0b5bb58279c866d420ced3600	\\x45ebfe302e0f489074bbc645d4b54d14b8f84867dcb4c160c9e83c4c6e810cf69894d8c4d904577963e16b2031b8806083f5c40a7153e33ad3ebc5b10d5bda1d04b109fbc62d6614dacec693fcc5b4bfbce3afabbbf841e2db806a7bf1066abe1514e7d81d40a97f01c278dd484e92e397f8f4d757edeca9c53c21f521b0c56d	\\xc33aeb0f865b8808bf8e7b053850fb1a9f18035c27b7a6665124f3c6b2c390f8a569882ec7db99626afb78955a2b8484618b0e8e776c38ef996882eb40e5642f	\\x7965c18a2f157af4fcf5da72190a84e174954fb12a85605e1baf5270313c1f4a8616cc3ac98fb76fb48fbc85f8edd1f69df19ddf295d5a74c644e4b838ee1ad21010dace252129f23928e8af9ffce8b4b909e8e3af35e6983229fed67cf363164600e4e9685d3f602fcf03902477a85b9f5124a3d8f56ac3ef2d304e53cf180a	35	334	3
11	\\xce79338c4e1c389e2e51c550aa075fd70e25e17ccab4ed3deee8c0bf4cf09b516e6841f4063e48ff934456afb05b1cd13fcf77d2b01f4b5f13d1293663935507	\\x79949db61513c413976090f37562555c8a4248fe5c3d4791909cf57c522f1da1076f277fa4d12cfae5e39796dc02f83d854dfb6e69a641126439beadcfcc71de1f51f1f31960900514f4d7231da5a0243d0585b5fd9b6710d1306c925c96a267d00595f553a694ea69006a0d50469260db7954aeeedee23255645e1b34ff7e22	\\x9255c274d81d48d8118c62b799017023f939e176722d9bec8dcfbba7db6df5f0057d3eb461b38bab3af15377b285e4460118d24be034473326e51139852a6ab9	\\x2f1de358c53b12491d7e29643f45945ff414c9e9a91f005eb93d97a877632cd567e94bc3d01269419a5ba22771c5dd11b747d33ee61cdcbe733678077237a2b32fe1f1b5f90e33e9f242455a924de4300d5b06a22ef0bb5edfbf2698147f081f84c87a4a06c349fd80f20e97641c98a5519d94ebc0879a068e3100a2c91688d9	36	334	3
0	\\x9ea832cec3c2061c16f3a40f07dbbc7f1bc41f2f69433353309cc778b5e93e8fdba2362c20a9fa2bad5b6c8a9c05080dfba7e078be5d1217c99810adf5907e09	\\x9e0f1a68a5f230eba62021aaa7f57c7e445365075b03b67f67730bdcbc263f68080aed8ebf29cdcb4042878503942c59b78e50ca9a128f4748bb74696d4ab6bf2ccd7043f1b29e341cb9ec5bc3c71772a2331a722a70561c172b017dbec5f8b13eae1f616c00e17b9b2c62e0d0416884133556d1a3c8dce6f0a1475b4ee0ad7d	\\x2179984e0bc039d92243683044b8711859b5793973e1ab466e9641e1a06766185432f3122e80c2f268deeb7fcc1a27cd734a10ce6f6dee459f5af3838f4b194c	\\xa7f2bb163422986c16bb6b0a49698dfae5ac5ea424187003f241dcdcd3ced7d7246b5e02555b9688b384315a54b51a67411e8237780ad78e6f2c6ac6c237ba54f2d227fd3ed76ec24f208f45871cec5b3e29aef1cbce5f7a4b413de113cfcc7f11b9b79b86dc03f104f27bcec9b093fe3920fcf22d7664a589a3b8ae3a63a2bd	37	192	4
1	\\x28dc20bf68647294e71456dbdbbfea50d057dc2310e4c71d89c74d32884f3c74a65aa6f2ba8a3c717283ed7d57580d8b89da9ea0cfa2eaf366b4d74d384eb80b	\\x8560d6e5f82ddc8b0c6516aebb2752350d2a79e822edc8ec5ae27906e3521f12d8eb12dd745739d216af1f1a6cae72c9e106f380a47de9b4b7d833a97b347618f2bd7129b6143308b8adee5d34c4669caf6f4a3edf0afe85a3db6de9ea0518be1a3402875ed036a57496318376bec39dc231d8978692d9a35e7e7cdafd913172	\\x1b9034e3f739955f7b0ef5d76808c9f66c4a70b5c124822356bba736718ac40cb749a2041ed9dc5358bed596f4a53526d8a132bb1ff9b43605f8f9c5c694d3e2	\\x63d425b1283906317605d2a0408f87a7d7fd846953df282520e3cc210a8aba488a8e3c5b426758cc0810d6c5d5820d9c6ffbf4dc9c1d5b14fd7ed577ee0eb0e50d1c86b2b083813828da0f4334c26df097cddcf329bf1e587351371c652bf62386344cb5579407c7534c7d4fe69b8f4b97df9d464085522ffbf3c06bd9d5da6d	38	13	4
2	\\x2558a92183f03a4cba530742ec0d372289257ba019af837ce86fef6f005b9b228241af62c62e741fd9c827541ba895747ae42e47ff79eae1c70f21a2833be208	\\x76fe4b6f8ca00ea378696603fc23642abeb70d5b54bb52523d9553a5e98037621b9f5fcf5a91a3839500e8fee5072c1d5beda91216967baed3a2c29662fdfcb7525591b973834c9cdb1ecd4c4ff8304b3855a8058c0c247ba0618fabb6af475a592e1512b87c66b3c955040ff13f02ed2a68daa1f2494dfefef3b54bcfae4c89	\\xcccac4679eb58e6d251d917640771fb2b8d05c8ed4e0c76520a616da43301bdc365f4440bed440b51474633a03450cc7db7231bc16ee79c9457468f885a826e7	\\xb32b8761c9d33fb75388388141513cff9780a6c36c3260c4e69dcccf60297f891246cbe5ecabb3b25eff1237a52a439a70f2e0deba7dd44a169513e589b11ff5ea6fa0914df2955a9e743ccdedcffaf0828e9055e67f64484ddc7ef84abbf1361e9371ddeab4c1e1effff8f4b807536350ff47d18cade9500f81b6e6b3e03d5c	39	13	4
3	\\x9a66a58b0d055f915a71de222a1b4b073939d79ff4c60b9985e708d5e60185a0a20f243906d0dd6863486527489328ad81d13bfe9a24cdd355cb04870421df08	\\x1c6c28cf47185459e6d8a1816044a46eb90b3693daffb654392ea986173a63baef2aa18e4264a95e6d4032ae0c338a135fb09b884bb1354e0da079d002dadfbe99b7b38ffa0b8ce2626b0dabbac12069969a1f7b57675b31af50057bcf4ea981c234a2dd69588ba382d7a88e9746122b2e3789cd96fbb2c9be6adc02511ed7fc	\\x17208ac4c5880da0020a521ee6d01edba438ddfd6a9dd9382d761219790e562d22bd82cbc1a86952ce69ff94ddd93d8585411ae74b555ef37db095fdcf5a07a5	\\x194278754133c5b24ff729b864bf0269d7a2a7f42b5d37eee3157bf06b94d23de461988aa0bb7b9c0c9af1891e3bcdb03370490d7709df433c88a512bd06ae799cb65a1d78a9c20524f14ee4a3674eb7b6261c10b56358f9b0c6a86514c1ee9b50823fa57166f540221f7ce6631d4772cea23b32bc71cbb6b22c97fefacccd50	40	13	4
4	\\xbdb0752334bf23d6c0dd318762d746897369429005e14a5ea60dc1357bb46f9c32c75d747269fa9835426a7d0cf3ae38e0e70a83ea222aa978cc88f71c57a906	\\x3f158d8a4f4bcc5b2597bbae99abf4cac21ae8996feb4336c723f66001731f50094b41882ad7d8d91c12d37a30acaf99209c1dd7b8488b33d95a1fbedc7ebb67e87ffa7087985b3fc2083bdcf9d7f77667a77c1ca7c5f80ff0362a6d7ed55b7f3ae6377219423d3a14efacca7d5a453975e876b3cbee242ab09c426fcd1ab875	\\xb8b4bc8e46bbbd069fc2793f2fd235c3202c657c1be79f4b245179768091e67ac11e3c32668e39c182c03d47fe5f720644e7da75bb96d133273d7195e8edf47e	\\x9ffbd8865ff74a2e60edd4e1fe67630434b59607be18a18bf2660630a931c3facd51cc3fd0a46eab1054208070da5a8124ca1e652ef65391519896e219f0a6abc58fa0d9b490b3869b80e2622db2b1693808aeb8bb9c9f047f89b56843e4ff71e718832a2541c40a0947d2d64d1b43c219e0c8eab5747ac35f11d2df30c55925	41	13	4
5	\\xbaf071bc74c3c4792d16561bd5e9223e43deb6b6368f78145dcae7bc3ef6b820278069ba42a28c3df43eee7d6f52bcd7d57a91ef39d274c1d26ac61b3890840e	\\x65d2fe9c3673291dfd5506255d79625e97839da1d7451be4c8fde9824fbab445c5d41324312652985c6dc4cde8805e0af71c7c497bebc5894e1ede51c4183c4ce03df63804e55cae1e34f0d700e0fe8ae3c178a8036dc36bc72dcd4a815de2c2fa0667a4a4cdaa5b7c3cd6f9e31ce9e2addb807b913a14602ab7e88ea3b082c5	\\xfccdf94176f25e609ce255a0249ffe8b09bd91f292156ca77a84bdf4f2bd0b216ea7e4b519d0b93aa144ba8d65ecbef1e0b337c946d85ffc557fb722ea583dd3	\\xbb31e054fcdd1da90996433b150fb5bc75f59b1408028e5da8cd470c80b74f44eaa9d36468a8f57d6ec468fe28dc8229196e01c835ef2269b3cce171a5a5696913a80bfba3844bce8bea9b1beb3722a8f2122b9e5fbbe7f96ff7ccce0854aedc9c88f7e78a33988384fe38724293f07dee937e5dfa4536af34c82bef7958d7c9	42	13	4
6	\\xd07cf2ce2f1eaa433d3e8f90a9e5a9be90feecd662fa347c7c35707ba67dbae14828e87df4c14b167cca0ea4601510d9a52f9543a55ca37120ebf4d6068f0000	\\xb006ed0cce25938836cc067a6829de9b23ca949caad68db72061261462d9ebd88478291e1e1061365fdf9ea06851105d7cec7c75f3e9c7df59451898b8f61e10a13389435522d61bbf8b022d6a5430a68a3d7440864458a4029bd1b163bc3e847170483dff2be285108eacdc9f720e58852b7c59ebc1869b232dc19677e06bab	\\x1586a5e3952046de496cc6a07c0da8f4090a1a48612c04fec5478232a2de73bb2ea9c36473d8ef8617743daecec4a255bbbfd26b770dbc1e4386c9c337ed57bb	\\x8c1b775215120512cac626a7aa2f0b43731c98da4a3705a3cfd664955b515dc235339ba731f60dd47c88df983b8282a231e6fab9db5dc84ffbd5bd2e02df6aec97ef0c4e7babb053244189dfb2d6e8d0d98e6a11c3d3446c4ec47f5a640abda87c2ea74d65e99f136d38e96feeb1859b9e4b2e081da9731a0aeb18be2ead8967	43	13	4
7	\\x87e355f965e3154372245103f7557dc05ad33711ff657581da8b82a7e0dc8fc5d9f04052c7201cd01aea2be39d4612c99c2642ace8496117c98faccbb76f7c0e	\\xa23c9b96595d75ade85331a355e41fc2410ff1af4394c8a1d7e42d1904552f87fc797c0d04c2c4f5bc32ce7881a3bae7bb028cd04bfd85936e9542b6c5640a577aa878dd5542c078d5cb4093a4cae4c2ef82eff77fba7f434ab61677ae04c12bd6207c5b0fbdbfe23c4ba8b684eb04d35d1ecb42aa244e207d0692350dd10500	\\x9383b741dc87180733dfae731ab630e4301ba6d5f635f6f40c4b4260faf63f296a858c65c723205fc12b322baee1f7dbaa4e3ad40edbc6fb1a8205652b68a662	\\x5dc668902e8a768950856d4a5fe404cfabf1c26380e6528e8ed2042206abed10bb0753b80782ab172d1ed96d6b51fc4b8d76446f21d0e9704d769f9978ec840c6abc22ae940e0a455df6597227e6448abe91cd0fc559bfc29a2d9fb6406fe38dbfa4aff24721370df59109b0c593cd26cabbd6c8ba2fce93bc091adcdd33fc9f	44	13	4
8	\\x9d7f743b04fae400158e2b9f585f43b3ab09ab419f365531ce15371488df63670b0f0c28a2df78b57704b6892eb6ff79f7ea3c065daf1641c0f149d372dee50d	\\x07097224474441500f98c846e95405d87b7a4015e4eb3d86abf237144a3194c8148cc014eaa0aafb6604bbd3d1a1cc66a566f25b3f29e237f88a79df6b76e470afb84d6c898962af1298932de8a36c88bb0129f372d88840fa1d2d11f6bbc315bbf3ebe036ec3c91046b025cfe0d8cbedb454e857726b6fc3eb6c3c5c5b68f6f	\\xda026ba773e67d55849cc03d01b87dc9ec0d34920ede47bd0c97c9764f48e2662a697f86c730a532e0a38ff0c042215102e6d76c5c96961e0f4235bbd8dfdb0d	\\x69024209cee5567eef42bf6f9572740cc2c53c6faad52b090bd94ceb1676911e085ff901945087699813c88421bcbedb6b3f52e631e4b587529820bce9f522f050dad9c32e1265ca75dc077f77347b5889726444b63acd42751d00f86a6bfbe8a73af5595159843ec812c84010d3aa7dc1ad0dac7d4e2e892a7fb62f1dfae989	45	13	4
9	\\x9961e4dfc5089af21d509da79069d471b7f1bcaa486b0944c1c683ce9391374f7bf638dadca6611c05caa4a8e8ba730cf75d5b0e7af42b0a822b28501479d00a	\\x798f6c4a30be812cef09a0e9bbb6e017a5766a491d0e9b8e8c8819ad7149afd46cfa06448675968c3d36bc840dc6ec83ac4968225dd83551a9947354656fc2b221fd36d803b0f0d41edb8b95656c13abe32d3fe5cdf35aa8df72516ff03950b779a543f9220ce56a46543d574cd1de2722debe3c9ebf2ed05c1b7036a1265bfe	\\xa227c173d27539e5dd9c253db9745fab4d25fc7c0396b89a0d9090ae76c794e5efeb2b804f1fc736bf900718fab12c5973e1690ba41112f59aff550d3439eb9e	\\x98f1cb240461cf9a8700115e8d93852a5784a9b11fe079a1c572c854119adaa1f1914670aed0308cf9ded7b5048681cb216a52cc74f0ac382ee26d5e65912b4c16195d40e58179a861f232650826d160ed349828ad4ef224e9582381bbb2720fa86d0d9ad8d9586b4e2fe493c321f02761c95cdc1592217e583d9a5dc004286b	46	334	4
10	\\x4a032e76fc4e293fd2ccb2f8eb94003671ada08de8aa7cc5b96764441ec56bee94e7bf68209edaa9443a71caa1bdcd210cd55f40451b8fea4a3e774eeedcec0f	\\x2b30c0674806226d3eb2f45d99cdb5d71db1d4411dd87489e01280344c17e507ecdf9dad86eb8128c42b505d2ecb7bf7050fa3efb657bd79b9c5e4ccd7742d5ab82e9368366210238787d78a17f71d7332fc4f4fc0d09f7e529b381bd29f7984a193567b6dc6ef4473d1d53a5a068428cda6c7c8fa8713e843840f8c2b282a11	\\xc5d0dd674a527df5e010c3e8036d686705c3c88fa2cc6726e094e7217d24aace12325319a0d19428f2d5564b42b939adec0334525c80fef8134b74f6be22bfe9	\\x42d6b725f7ac41d5446aa19a28e1d3265f10375970f7fa0c710c3522beee5c4baa25d365a53d488b00ee0c26bbf4bea84beedff496ec5e5f225d45a5aab577ad9084949dafdbdc5a37f282e4c9accce59065cb3d0c2e871171be56731dbd1b5cbfa6f5a816b64e74b7ce81a0e692c3ac212df3eda7a4b80b3213867c6d5adb1a	47	334	4
11	\\x8a4dcd3582d69777a63cbdafb9c31456235d716dc9b7bdb007ff4b86556157a2ac847986877f77e7fa20b08ceab54b4d89072a1e4c967627c2b1d31a9fd50f0f	\\x3a6620da1d3c416cee7eb680bfd925be5b51ae7e36c0bfbf89886a35f3065c1d2f1b15c3a32108d8aa751efa1e3175037c11d0d6a95736afa75f51f97bca468b6a8fb2ee74ef69d855fece9450ce2ca77ae8205c4b9e5b54f67455fc2dbf5b04300aa07266dc5502cf6fa7d1d685f092ab928d7214438165941dfba643c0046b	\\x836cb37678c73c817edf699acd5a6d52209a7cbe79afc650849639271d2051122ed0755cc0aab45f876e37a56e750e66f49a73d6c5a442e3c8badac9e19549ee	\\xa4b2418c67e1843908282653a0202e7b6f2a76313b6f70a541cdfb84d67c70566611efdbf7083790dfbb9811a31fe8bbb9dadae7b60a285efb50f27177b98fee7feb62bbc5cda1cc9db1de1ffd3dc1ee2f768b9fb94ee6e9ef23105db74b72c22c6d33b8d40f7fc68c839d5824aeb1818454cd60b79eb951a6ffb2f459edc74d	48	334	4
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (transfer_pub, transfer_privs, rtc_serial, melt_serial_id) FROM stdin;
\\x07f3c9ddb409d3ed43bdd68926f2e107eb52b26e4c627c8b951cb5648d16b233	\\xb471b5b2c1cda049b82eaf01474666f3950d8c47a8aa1a04201732328baccd400e73c2ca6f994f17ee995142a07d0d812f941a5dca37b745e2d3377022861540	1	1
\\xa48ee0e1b841bc2f7309d95b7ea9fe5beca3bc060c45c1c40738b792e0a98959	\\x54f988457226e0b002f762303f877bfc96f34bdf8017ad0fd12c482049fefe2739d43e2fa568247e52e0c675e8eb1081d6d94a6c1499e5e5b681a4b9558950c7	2	2
\\xc99d54afa90b6cf628ac0b093b18c3bed06e71369ae95cbe074c364dae544b46	\\xf68b6760b72aca3c190769ef58be8bd387038845ece19e9ba0c93eda74809ffb24ba580b60b24ae45208a7e822aee6fac55add1e21dfd792acbe948f4825156b	3	3
\\x80f9d4799d16c0236c753e43526e07f2e4915cf879f749d1d706eaacf689865c	\\xbb4f9223688a0a8f4433aa26b4b5864661d95d3eb4d98979c2848a458bf03456022192909b4224038dfd11f32b1149aa8003e1005aa6e7c8e59d81e025b592f0	4	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, deposit_serial_id) FROM stdin;
1	\\xbc404e2a594d23d0d6593c3e8dd39c9432f50452b17315a7746f533f0f4f5fd06aab5e3df91dfdaad52f4234eaea53aa01fab3ea7eb7e83be9983e63b8c3100d	1	6	0	2
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x3d2240672ae808283b6062ec3fc9a929a645fcdf4cebf253d513be105885b268	payto://x-taler-bank/localhost/testuser-SeeIXZft	0	1000000	1633269019000000	1851601822000000	1
\\x6ee2a7e6fdca30fa198bf654339f36c3a87be13a873e9bb17dfed9b0725593a4	payto://x-taler-bank/localhost/testuser-0w9C8Kjf	0	1000000	1633269027000000	1851601830000000	2
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
1	2	10	0	payto://x-taler-bank/localhost/testuser-SeeIXZft	exchange-account-1	1630849819000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-0w9C8Kjf	exchange-account-1	1630849827000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x018e75cc158b38285808068e7e727ad7a51eafc0b174189f696e72c4511339ec1f8367f3bb78f2f8a0d08bce73797165c86f8f0bea189e15f6a5268e5f26d6a2	\\x380ba9ae328a3dd1fa9a8fbfbc19e5c97e2571793dca652a2940ae82f000225dfb554d242a5fdc078493655bf1ea4ebf7c288ce42b70b0b973c5de807526fe3acd1bf259097fc5c6d74f1286cfddc884c0c0eef91788f974dd86a7e609ffcb96e787aebc39d76afcb34ba9b17c53e07d37a6401cac8d6e5676a94770e189d494	\\x2d1aac082d6351fef17bb30a5e23fedd83c0328d01f6e985f129a0793ed1a209f5c1211e058d5313d036c2432b5f746fb229f8e660f06991994243c739b27b0e	1630849821000000	8	5000000	1	206
2	\\xc1f009dae555f8683c9b0441a28b385faa3993713bb3fa1bf37a8e6b175cd02eb763022ca5c71d3b23749e0ef40b79da3a4e7cb1dcb0e96033bd15b1e727edd0	\\x76037c9f49c193757c391454358304b31a5d5603cc9d1a44cbe819665f54851b78120181c8e4de330bda0a0912a7694980df396b0197fe336e384a074e6b7378a179e6ed37814a5cfa65549c607cca1441f5b9a0fef3f976e1c70f40cec0792e62d7a4b6f7752bea7e69ca58a08c16fb07173201e5a2b8763d3e65ae1f29cfa7	\\x3917de0d77e1a1fc54804cb408665a94d95ee3a58302a82b0b3e10bcc42b3759763b53ca5e79076be016b0d447bd8fc916babf2f62c8f030cfafbb6c3f90d90d	1630849821000000	1	2000000	1	192
3	\\x027229591426a8f09c3dda386243e54732e477c39a90aa2770fb4d2ca67c66dfda8a9afcc42c2d2b26d57a465894f71a96f4df4c0c7223b57f0b735e494b23fd	\\x518639d9a0cb5b9e8cf7d2a5fe32463996a40ebbf89d3a89aec8020df24e6f625e07a2d38b2b259b80a1ff22caca13eb19ab35cca00c776408c5155b68cc07423b06fbbeed7ae442fa54500830251252ade614b49ca682ff40086851fbd1a4fb7846a20ae36df3beb2d92d56e5e38fff2229039f5dcdd7d0b66401e303cbd98c	\\xc6657d7529b5f9d99335e653045c5f3f5f664292ebd70d1f7b3cab0cd901052c020bc6771ebb6030b8e50c2e157b68dfa946751dbdfac85e0af51bbaad0f910c	1630849822000000	0	11000000	1	13
4	\\x7d88076a5330c37814f32587a1badb340a4928597be47e9b053d172714afaed4f0ed403f8c39dd6022437bb43970f2de308729087e613d2b9f43b067dbf56139	\\x72e1e6156b1c29a46ba7486118a20c624faedb2628658e1d6c3a04ec4062d753c26451574bf850719dc8679ffc5c3d8c7dae36b73744fbfa1d3b42a7635a8cfd53878d15399da576f2ac7640ed56bbc7bc8f85de36be8b51037a4910b41e78b41bc3b3867630c6b57656600a7a73c6d1cfe9f61b9931997baed8298d34cdfafd	\\xe21a501fe3e0aac93da650e9ea810750f8b71e7e60c3f2579c37609efee0ab19f91dea931745e11837d9f0f7e72ac0587bd2a3449e183d8391b026c49963df07	1630849822000000	0	11000000	1	13
5	\\x6e78880e85d5b0201564dbdf424988f0e0b3f8d96a34df9471b8b13725ed1671f51f03e8e85cbb288fff45de996101a124f0c897a20fb36b82c1318aa30145de	\\x381901453182c4b39100e9905fcd691b91165620e34e3c6c057079caf07ffe8e6923b2a631037b935ac39f006d6acb535d14b3a749dba43132c5cbd4759e8c2179f7bf46f2438983458d8b5d60a925b53f1238e27ed9c00a88e5a332436c74cb00b5372ab2b0a92271490d1287d68e854627c4225d7b7bf849d872aa27d89f0b	\\xdfe20dc1b9cf62f268fc2b548aa0fa21a1dc789d7082c343d4b6019aaaf24a612952f0cb7094a57fa726cbf6dd0bdfad667145a36ec72ff73a1b8334c4e43107	1630849822000000	0	11000000	1	13
6	\\x394c9e1f11b6648f43731f844c3865411e658a659361ad0aeef0387697861f641536f2f5ab983293df75ea1c83d864e2125b1c584330139d5feb062f0330c60f	\\x0f4aed8db02e47a00560d875a4807a8d87250658299d927db0da51ed6a0dcb67cab4ab08183385bc52b4eb39656e76e99c5a8cfe659c69d1eefc640607c7bd724c1348846c456196780ab162e1c5f51485ed664d95425ba2d6a484406639b77efec7cd13d3281562d1b406ca604dca5c481363a38734d0c5f3e5f0c59d8db0a2	\\x9fdbe11bed971a92a6f1fe2268822deedfeeee876a1f4206ca0c6e17f15614bbd4e8e7643e4cf9f6a56ac1b715904e573326ef417e4e97e660ae71b976b89a0d	1630849822000000	0	11000000	1	13
7	\\x9ab3d0257579715676287e98a8217590fbab42c6d27062b1b53082d789ac4ba418baca5ec9f21dcacfe0aabbc0d8804e3fecdaedeb020827ef3417ba8dc0d941	\\x34371a2982c2bbf7fb38ed285c7762c58dd8d3139bd710e4d0a51a8c6ce22ac3397950ea6d2ed7ea1e181058a8edef9e6c1dae4b6f0b50419e35ec898af9d1f1208723cf547a40d0edf2cab57d7c6d5ee900e3bf927817fe5959ecf143647f9f022eaa6bfff1a269046f092b28202f93d0607935228efb36dbe27e7a4a9ba017	\\xef861129399bebe9f4310a1d2d26afe9db568e2a693759c4f87a358ba479c8ff785709e2f09e27d2b95c32e9cbd18bac1e469604b7978c93ab2ac664b0f70003	1630849822000000	0	11000000	1	13
8	\\x6a2c39ce94c61c9280a4dceb7833458d95e02cafecd9b7eddd3b7fbb3a3a209807da73ef289aa798b3cc7f120a37ceb54d55e87f3721eddcf9c7197be5c23e06	\\x9451d80d55d2894a51e9f1262deea9f0fc798ccc0c685b685448871a46722baec8bcb8d6c922b014e608e1786ff955e32b4958bbd305024d23f2d9a55929f13400c781d233fd93929a55c6fa8875b3b106471d1079652a1502ca8741f907546182d64408681933c77598bc6457ee89b200707692eec459dff8cef5b77f763bb8	\\x12987326988eb54c426b60392cc9ff0db91ddcc4333d9de2a8eace7ccb3e46e3200c144ece5f0b51e0ed3e60fdfa6a03edc76a1c9d666b157f10c6d650ee8c09	1630849822000000	0	11000000	1	13
9	\\xe45389b6cbedeab5eaf101fe302a6b9d1f508ca9316dc7458450d3ba821e1dd3871024396c5b53474bb9fdc3c4044ff08359fd636c2cb6871443cc40c158be22	\\x391a696c1b717d81c21eb7b7b57b9ebc0b430aa116f7cffba3793993b7cdc8228e0e16fcd60da3f0f12ad4d83618cf5c8b5a2638a64748fbbdd9a48646b5c8328c8144f0737b078e7d75aeed71230487dde3819a096f525c3dc55edd32718249044a592e3f6000d87d8430738852dada1e193ed5c5db9152f44ec5eb4582721f	\\x04eba35e7b62b4fc0f3b0fc758e4b9609ce7993fb8516e8ea65ea6d9232ae12650d0984ef8805c0deccb18746f2694f1a2d2645dbfbcb4e167b7ca666af3330d	1630849822000000	0	11000000	1	13
10	\\x6146d95547f0528af9e079ba2b2c5e0da8a91729cd43257e81d5c68c77e70c1adcf819cc515fed29c3100489097742a488d74a2fd489e55ec619bb0f79608561	\\x77199753932ff36d7def801e538199007573bbe45b85b44e5110e9d2d5b42560f8ceb56c8e4af8320ebf63517a5fc3229f2a900558691914362a8c62cd21a834ddc1c77027de24d0e026f761f60d9e65f9d67b89580588150328d5a4d286ee3ae7297a41532d9a2c737beaf4b3c5fd92eeaf6eb7222e1da3dd7c1d46a2d0c5c6	\\xe91132a18ffb474f7ab81c49544e7c7aa01d29674ccd5311229468cc5b6a542972ef91ac85c0169bc5ce0b978581c835679e1a34687b07829c3f3b399527100c	1630849822000000	0	11000000	1	13
11	\\x336e8aacfde7e16265c957655b5c0e84441dabce3fa02ef274fd7720fbde15291663a81bffadd2d5778b7c4b16ccb5e84d9953bf95a1997ff3d37d5d6dbba06d	\\x22c0162e406c5e1b055b3310f22affed44b90c74787359fb37e8776c45355b48bb24c91aee8c002e6a2176631270e80251c21d2a47f1eb12fe2c32eb942f01cc72cb85cac2532dd03e2c2b4804b47360d2e2258aba7418c8cedeb8d4b4f5a1eec330501fa1afd98b509b1d69426a64d775746c53b0d9e1468a28e1e9aea6e1c8	\\xa6e740c4a202312a758ac931d5a48d94bb98bfee60a5d2a86bb35e05248a5661325230885ed7aab210d67282e1ac777340d875b1eacf04feb8b91246c81bc004	1630849822000000	0	2000000	1	334
12	\\x0766f29fe88a9bf77ab1bc269d8d0d81102403f42c0336038a34e8b9ca36ffc2a23c3342f7093a62c5ca2bed3d6e082b8a65f4d50ef6f778eafd2b778292f76e	\\x636a8f1cf257b3fe25caf7730f4c44af6d2a3c7d5f1f319a731b0f1b5232e2979f5a47e92402bb34ee233ab54d0e13055b198c6e4bc05fe0eadfdc4dedb447a70a53ccd0a5c5652c8a1f37581c971d60911058630060aa64840ae9a27d9c2004585b3d69253e0d615f37110cde0ac1840a2c49608c991a864758c2cfeb9e6587	\\x24ce038e613f537fd7c4a218922b8b29af3225abe2ce2cd6084755749d437bcf28c3b25e8ac6285532b27bbd78493b1b0d4ff5e380af2831c4baf4da3b538e09	1630849822000000	0	2000000	1	334
13	\\x4c211ce9534b2269d643e22383b1b354cd5e4096f3ca7d79c2f3b688eedbbd9c4aa4a2c9bffe8e80fd8af7f4133ba774f5ab6d0955fda573f14d2495f954da70	\\xbf5e4e97940913eb16cabb3ea3ec0de3204dfff07c20e68e7f2b20a0230c4bdd6db5a8c7525e7066e5c57bbc0999b239a792a21738ff4e30d8f49fa2790e215becfa2e93308dbef392650a608639be3d458f76d54aa6718805586754bdf64b9bcecb805b5c6d29246663897d4c27654ace970f5e47f64d4a4986e30901cf9462	\\x0946b82557789693ee0c03f9daf726c04bb0ea288fd916debbcda5a82fa7d72c0afa366bbadda9e58d916320184f631bdb785a4b597b17f0489007ea682e3801	1630849829000000	10	1000000	2	237
14	\\xb1f0e63e8a901cfd837fc36b2c7f02116734d231e5a3fc10116e0f1625884fc7e733ce150925525b62b6d1994a5f60e8b4d7a57e3476eb64e0342334f2775727	\\x4a345630c693db4f6dd54a4358aa45aeba0a986953987dec38475b17754961b9057bd20aba3643f6fe2040937ec9547616819ec4c292ac45c2f4019cd67917d4dc06b3f923f28a27328b3a0dbfb71cea06ef0de151b44f816c3d1fb46674a9db865f16e1c8339dd5f292d3e637029e5f3b68c7fbcf927675f73fc6a8d3801e7b	\\xb0377ac78ee98f79d1994be735e99476ec91abb57f3273ddbc6f958f6d8e4ee2c0df96610dd6410a1ea47559cf442203ced3fe3f665c64026abbae22fe8ff90e	1630849829000000	5	1000000	2	267
15	\\xb975c84a795b513ff1230b0ff3fadc61c7d18fe8475dcc0f034176b42f6772389ade5eedc23aa75a3642653a698fc999b1645698d3c97b29e1f00d2a970bf0dc	\\x7874f0bcc0c7b48585693317c8dc9739b1bb2b77b942100889841be179606d16881904758cf4b3ba76a6f826bf6ab26293d168cf075172ccab0a6b628d130611837b688a9f99cf2433ab8f4b4de30bc62d40e342640ec8c62d2d546c91943a5f438ade16819ad0e548bf5d5e0a70ad04929391012778e5167c70518d789c85ea	\\xea4c30ebfa65902c0c77c75c9c11fc13c2b6fea4a7055ebb17e34430c2c0106bb706bbb2eb7eb90926c3bd75940ceaeb8d485ec29f46c5ae4964a5593bff2507	1630849829000000	2	3000000	2	352
16	\\x33123a31734a016741d7f10e88e31e83062c465ab421a760d635e775ba8539639db815e5d5322b8fe012d620ba6899fd7f78402e101848983fef72dfa50432a2	\\xa63686c052d90a22a61506f48c70b79078d4a1d7aa0c5888f7e6c376c8e9416800a4f9321f9922af2fce60574a969eabe573c6f63d6e08709eb03f777a38eb738ee232c2d20014e19e1407f7cc64f0e6e57556b33f8a171cfaf4196b6bcbab9ec5a9492a8c7ade67255216fe51c48f859b8ad2c63d7d8fb876e009526f0dec27	\\x017b27202342fcbd1365073f6e0609eeb370c4b5dae2e8dcbaeecdb84668d0356dee11f029960f70956024fa4e6deb5d571577c8e53a2d9e060ddfe0a6a47306	1630849829000000	0	11000000	2	13
17	\\xe47efc38969dc79a365bede39d68007e3f358123f14a7cea5ac3099044ce885988743ab187e718a6f69a25bf877b05433e3477f8500f64384ae23d3f09e97558	\\xb3714b52a01a3f56c8f0044271168ff7d5589e227fc1b234456e0d05879e5149dd9f33734c38aebb257c4908a74113290e51f56fc301056cba50eb655c6fd1d1aa5d4c57aac73a7c925a664ddcedebd6197c720ff67ac9ad4a62e808e71515f60825662b7c5330e32e626c4ee846e3b931590f0a41b4afe1cc2541e3419c8718	\\x9a2683a16b83c57121acd0902b9fb29fe1a79358b31a9cff8aa6de755373846229c4f357bd2750203175f0121d9d96dc848a72e6a3e64dfca11e1de6c476dd09	1630849829000000	0	11000000	2	13
18	\\x7f1fc07ef8e31ec3956fcda42de23477c009da2954ec3c44240cec1e9e25590d1598e3c328cfd848d817b2de72c6310ca968e17a875ec41ed501153a36f71df6	\\x8490ca513498851acc59f80c0d181a44f99b6fe129da564a2b257f69fcccc307f6b122383ddca7b14e425d49a51bcf1aed2b9f0ca835c7fefefbadc3f851c155071e70472e6f383801edd59261ce1be2ccb0cb339eea477839aaac8ce41f00b884d752ba28ea2bcdfd1f02f47ddc1f3cc97336487c43316b81e768f0e39152ea	\\x079be36d8b2420064e64ef36f919d3dce6cbd2fae2c1b7c38e50d0e630d956dfa41c72ca0d4cb8bd35fa26560eb195d7620a679f968c4a7ced81d3830ace2204	1630849829000000	0	11000000	2	13
19	\\x52cbda76f894055fd43b073c4e32144ed9b8d3adeef19b95c9f8835661636a25ad6d73a9426ea83bf8404ef415781b58e34d437a75d4fd96aa0dc35a05745248	\\x7d9cc6562859c61d83d1b5252f3eb944226729185c095656b62f204d596be4cab898c8eef480f9a4c6b1eb3f1d5aa25e8635542aaf5f877b6537a2c997ff5d6cc0e5da6139aca15706edc8f0ce1e94debae2f7ec73db3358071e9777a2c0549638a10715769af5def60f8253efcbe85f5ed05d3f5140787c621905fe5c7b9621	\\x28e7235882ab810f293366f760a684c16c7828ff783ba5bd3cc49ec2d63f6198ebfc7e4ddb5b738c2f9dca703fb3bea492a090e0681ea06ec293b12d42398203	1630849829000000	0	11000000	2	13
20	\\xa0564c89762ab1c08c12afda9527ec8c845b4718157f2a3aaea47dbfc43a1d9a44544425715a2f4369cc9d7d5fc90274fe6d3ec15d8f9bcefcd390cd2f85c3a7	\\x402f442bbb0505990ebe477e66bc0aae4d9f8bc1bd339bef7975f649c5505c540fcbbc33206649933b442c499bebefc0307c0833a3dc15b1c3db3a2e22b0ff698b9a6b8c5f2b97dfea2d8493bb7e0940cd1b20552c29ebdcd4a6e24a0c152c50cf4af7745ebc190fde40790353d358d5bfa6b031e04186e2596f240e0417c338	\\x5a03f6bb9022ca42409f7284e697ac3519ddffb27780dcb76219c9e1e9041c2c841e09065f33f97e681e45c3d0696895c86031c9aac6ca9657962ebd7657700f	1630849830000000	0	11000000	2	13
21	\\xb33f32fe0388226da70e9c1aa9f1291f1f16bdb7bc08f358e972f90204d8f22dad62a3c719f65d2bc63738eebe2bf3f51e31c6a16f52ab4ce01e8ad126ece4e5	\\x023fd8df6cc40b45c87772a46eb4638c9c93421d732e778011ede42a28083a944333e74e7c29788db780f083ffb130b8379730105c371bf7babc40a33588913fbdd0e2a946f331beff9865ffefe7ff2ea8214efb8c43731909a202d167e6dcd5c96e75a4c63e532474618f806f0055913c61c953f8426d9f3e4058e9b20a80dc	\\xd448926d27e689c6320ed2b7ae63dfb62807ea95773a0a6b6b1229853b21cac8a5011770071cfd05a6768f131d66ea546a45f119d9f6d8b229d5b05feb2c8c0e	1630849830000000	0	11000000	2	13
22	\\x075ed9ab9eb7c2a63c21fbe5c6886c171117fba7762d19d7c8acced37b7d10149fdfd00dc5cda86594b0bc91f0a78218262208f881f35289bfba0a58b83129c1	\\x4c8eb0173a1f070e5e4c49bbccf5d1354624aadd13280f3c6ae930c5f8625c5b91fa731db178249d7533415d621a2456067d071aadb16a30eb5bdf15f9f2f55f0cdb931095be3f843e2ed63346afd9ea8706e724c438c24d18804628f368e8332eee8c075351bc4d6e4f891c2259ec6dc26c284e48c99c36f8fa2a7286f878a1	\\xcbdbfac320c2abf4412f4599433d29e09ec60fd1933e25ab8637903fe61191b8bf3f9478d418a150c97aa95aefae35582e960ee04e4cbc0f54a6d8a0ae746b0c	1630849830000000	0	11000000	2	13
23	\\xa3f8d50d7f08e006855c7eb8de0f195e14e55c827a08b9c5712f1c834807437b5211dac931c30973dd383be165339cd22ea20362065f8130080a7f4e467faff2	\\xbec6aa6191240efd9a9cfa8be9b0fc7d9d41407bde5fb53798b7cbb621306decd17d37be01e439db367fac5cd6085a55a3fc4b790af5cc3676f00a8cee47099af5babadea504b2a3b96b8c0ac2fdbaa6b831513b14a41363aa822f56e05842b3d2fbe4ecbcca44c46c1fac5b9c57185d6d5ead2d3821d3029b00c0b97cbcd32d	\\xfd713040fbc6861cc36186681a758df56ccfc79a543693f166a79ffd715795825d52b6297bae0645ea33dc78723fc074bc1fa59d451b88b080d42118122dd805	1630849830000000	0	11000000	2	13
24	\\x609d878d782ea7ac23462d1d62426a440c34159a510cc31ed60bf097a2ec3fbad0bb55bc41b3e35301d8f3daa935412532764c1598b89e86a1225488c79b7900	\\xa6e003b3de80a7326e8894829bf71edb7fe8ec6d2f2395f54c2cecdec2068a8e5c02fc4686c0924646e73689f12f9ee5a25f8a050ed7a8505f563f7a63fa7848d5100be0f41e7dcd270170b1bcaa5d1df4b0d4df4db1df3c5cff32bdd284265c75cffb9f6603ae624ad989e2a4cbec6d78e88c1fd27f908a0a200cbefc2a1c31	\\x9f6b02f85f3d46b28b4af8c5a0148963ba9a0bd31ac75fb9166e895acad4478010a3af8aaedc61fde10e7083a3a7b10b13687c21b484c80ac4af32fe6a805c09	1630849830000000	0	2000000	2	334
25	\\xe318f5c1f69d13949ef5b7730d882771950688ad939460c9f5077a713ae3a6d18539010658b4bdfc8e7b9c1f52a84348f4839a398b4ed82fbe7f7eaa429fd88f	\\xaecdfb205b358ea102e47344c46df2366a16724437dbe27940f80b9d65faa8fd6a3ad54a38fb947a13521a452a1a40d3e1a91df67594c108ed238d3854fbc778e69fd4a8e8a75c96f61a041aa2650b682ff6a350d8ae558f458584eaf90072aefe5cda1aeb64aa04c18353bafeefeea3b29fb778840c466b78ef2b816fe9fb8e	\\xdb7daf6925d4489a4f4524f1fcf2b5ff2c90c3788bf2ab08c4a089324a27e34213e2bc184723ba998bad6ada48419f313ccdc79a76bf49f94307575dc079ff01	1630849830000000	0	2000000	2	334
26	\\xf6e5ab3291ec031b9d663c083297e8ccc5847d915592209d6c5b2e828afbf0bca927ec5d58da628a578930ae258cad0f179a98c7047f45198e72c79bdc4f5426	\\x258e1d31d524cddc00837eedc64891f9a95159bbdc8dfca5dbe4a5ebf6768e908ac0e5f960f99880878dad461feb547e9b2366ba9ed5bc0cc28152ff5e064f622a3b6422c72e50a033fe9760e6d30ea448eb104d4b270493cf3c35c0edc0b0948acf59b3030fefef95f1d75c0d73cc18f6ce056e674d2a85187c18c2aef01307	\\x71068ad39706c14dbaba121aa88f543895b025d8d52775f70e0316e81ad1c6ea27073cf7f8447a198425b5dbcc103092fd18035389989437ed3348176345c301	1630849830000000	0	2000000	2	334
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
payto://x-taler-bank/localhost/Exchange	\\x9d17d81a1520ff0502661285bd9baca84627d104658c2560ada377adcb3d3eb9269c74640a271593e710302577b4be7a59f618d9aeab976a36f2c9f155a4f301	t	1630849813000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x496925bc0b8f1173348c45e67318c282fb4e0524407f5f808cae617cca25d9db1723d7b0628aaac5e47c58f7eef7f6d2bd25c2120b7f581007d7b27fd2b3fb0f	1
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1630849807512269	0	1024	f	wirewatch-exchange-account-1
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
-- Name: deposits deposit_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposit_unique UNIQUE (known_coin_id, merchant_pub, h_contract_terms);


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
-- Name: recoup_refresh recoup_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh
    ADD CONSTRAINT recoup_unique UNIQUE (rrc_serial);


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
-- Name: refresh_revealed_coins refresh_revealed_coins_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds refunds_primary_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_primary_key PRIMARY KEY (deposit_serial_id, rtransaction_id);


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
-- Name: reserves_in unique_in; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT unique_in PRIMARY KEY (reserve_uuid, wire_reference);


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
-- Name: denomination_revocations_by_denomination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denomination_revocations_by_denomination ON public.denomination_revocations USING btree (denominations_serial);


--
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (shard, tiny, done, wire_deadline, refund_deadline);


--
-- Name: INDEX deposits_get_ready_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_get_ready_index IS 'for deposits_get_ready';


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

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denominations_serial);


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
-- Name: refresh_commitments_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_old_coin_pub_index ON public.refresh_commitments USING btree (old_known_coin_id);


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

