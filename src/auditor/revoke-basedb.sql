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
exchange-0001	2021-09-05 15:51:30.994406+02	grothoff	{}	{}
exchange-0002	2021-09-05 15:51:31.112835+02	grothoff	{}	{}
exchange-0003	2021-09-05 15:51:31.238693+02	grothoff	{}	{}
merchant-0001	2021-09-05 15:51:31.318529+02	grothoff	{}	{}
merchant-0002	2021-09-05 15:51:31.4434+02	grothoff	{}	{}
auditor-0001	2021-09-05 15:51:31.518039+02	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-09-05 15:51:39.43399+02	f	ac74297b-e74a-44db-9cca-b9a73b489f20	12	1
2	TESTKUDOS:8	EPDERZBEFA9AZRZ8VEZXS77QSMT5GW7YDQX4P907Z7A7MHJ19RAG	2021-09-05 15:51:43.187007+02	f	654d34f2-e853-4835-aebd-0957d33f3b25	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
302c25e0-8514-430c-9f1a-c64f9a939ff1	TESTKUDOS:8	t	t	f	EPDERZBEFA9AZRZ8VEZXS77QSMT5GW7YDQX4P907Z7A7MHJ19RAG	2	12
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
1	1	12	\\xe329be45d91a060ce220278f3e4aa16f04cc4aada9259c6208fa4d26529fa2f84e81d77ab3f9655ae5fdef9b80b187d237a6530f03e3ff13628e11552b3fa10b
2	1	35	\\x62f22de373436a7fd5c6bc93027055e3c3a17c20e2ed39a456e3e757a4202ab255941da258304f40800dc9ac2d302a7ebe67f703adc730a922a7e928c14fb10b
3	1	150	\\x0904571975cfc01338a5389bea266086dddae89baf854aca35d5887d1fbe0ad74ee39e6dc6408a05b0b11c0d6a90624fd56cce12e72eded4c2d8ecf3c963ef0a
4	1	216	\\x4f818c07a0a07215efda7864ea4e151451f1bab39dd45b71368a68eea7652874b052343aae84fa878c16129e83fff7c407f63d72a78a2d15489abd0fdf8ebc06
5	1	394	\\x2fef6e947f4cc7fbb66fa9e492b973c6ca62e69a5583d5f2bd86592fdccf1b85ff180409cfc2f36a1a305091ec18e7a5e4ae14766767dd7f2e58ab0ec950d106
6	1	398	\\x5e2afd7712763146b5c1ce4728e44d01ade776807a577c47cc8f1fa0534781e0c6dbf19a8041e54648fffaa7ba8eb5fa49d8d02d1c22ae89eda9c625159b7504
7	1	302	\\x7352c7aad6eb3ff603b808586a6e495cc7c8c1b7a12002df225d63f10ad4fa5e74d4ce77fccd88e1a8f7ff0712f80a1a4870e4c05bd8edb11d9f50fb7a854308
8	1	424	\\x653dfe96063599b790ca4521e681bd40a2c66c02b96d3b240d87fdddf33e8e63acdf9b257ed5a7c6018e1e85807a2f66d648c9c01b3db609cd992804d127e703
9	1	20	\\x7e4627b9751c1200fd403719391977c836d58ab04722cc19391e79ff5cebf38f7ad68ac1266defe1d246a921d1b1aac7da10fcbf9a7d8c40d389ca5c4c754100
10	1	28	\\x4346b330d264e60b292e75434214fa2039be27e09c2bb25099ae2532bd57bd0a83544770fecbc31ab810b350c75092d037f8ed3919c85d34565eea844f285102
11	1	283	\\xc3d9e2ae8048a42762807857c7a9194c1ca9c7b15b56a92eb8165f714032b203309bea3509f7d6d26dc95b325d1705f2bcfbaf2821c87802dcc556c1101c7a02
12	1	420	\\x08fc51afb307befd245854bf9acde793fb11f4fc7880aa40b25b2648bbd1c9481ea79525a5b28e3631566c6286cb3e375c1979241f1cf751c8ac23cb25706602
13	1	325	\\xe8127fe871b246e2c13e90aff877015071aa9e9967c3b6e68163cbc7b5f04a51e0d5103471eefd52ef79a24aae4f1034766482258c476c045a37ea2ef2733200
14	1	341	\\xe7dbfd6ac07ca1a1e4061e2da45021d242f6094f2611d290da5fcb253d29cf2a585beecb940b36fe07dd7414dc77cd1b5a00a400e265b1e21ac1f60be02cf20a
15	1	30	\\xcdd34053ddf7f561fbc769bde2a6828c0139f1b516ffc5af333a1da28b2a89ca2413d318512a5cf00a01cd2eb6a9c627cabec2c960dfa438ed996959936fd60e
16	1	132	\\xd572f08f14ecd34f0bc7b93dba04feb2f264dc691ff9b42e3e4cb7aca6a4b42b8ba40da9e6be244af2622914fd7c76487e7c4783beea3cf0d8f9787818c0440e
17	1	106	\\xadbe2c0500f202ed18ed3c191ca1a2a01820b76759ae66a28dbc232f3a1c74861d36ebd1e512dc580b06f20cc194186fb0bff502e96daf94c7387cded8b94505
18	1	48	\\xd26463c7589c186e0d21e1c4ba0388e2b46b4727307d5e49a3126a01debeeaf254c9093dfef27fb0e0084acb6ddb4587475d576ab63d1a59ffade13def9dff0a
19	1	287	\\x111d831b33322c0a97f130f80ebe7bb16decd8e980796d0788d08ebe07ea768416a77dc485ed17ad0f1567fadb879eccc8526c00420bf1abb62a95134f7f6506
20	1	317	\\x25049d8a507798c86bf3cf3b479652d9a47de082630381152499b98c061c0a47dabd338cfcdb2c7295f4ca21fec7936f074982f588b5f3ff7b416694b7714209
21	1	98	\\xfb0d880987c0a6fb965a8fbc21a59e94ba7e29e25255e542f4f34e4feb3485d2d9aecd1bf2740a7f652d0cbb705f1c175782e70987906f711f495b4a0cc9b80d
22	1	326	\\x75ce2fbe37051ac535fccdc18f3a7a0f131f2261e6e59007b0bdaef59b21568c48b79d6b12d828d0442a41b4550c4f497711383938ea8115a8df2a0309acae09
23	1	357	\\x141114570a85dc2e99b9976b6ffe2f2507a050ecd87356fd650f8c9bbe5b5849fa8e2f5addf1c73a6929c10789643a49ee3530ea17dbaf8134c8fe6f35a1ba0d
24	1	138	\\xb60d3a195ad0fae09cd89184494385777253cddcaa6e74676fae80b3070a634e5e68f74b2dd23c7cf24ada143973eaf34ca5e63f2c71bfbd7b71ff4a919cae0e
25	1	114	\\x59479a6a4be0fc14abceff37d928b08d67aa48c37a7f363689f8fd0b1609ecc9c99fd35939763ebc0393094c1bc1ffaca850d5f68c1f93a8352fb517f8eef701
26	1	49	\\x33e0433bd0ba0ffe65b9287179cf5462c16a3fdc715a962cbc824a90d8dfc147f668cae6623ac0e90173ad7362ec660d59e80deb0fd4e435ff07cf569e78c90b
27	1	116	\\x09af2c3c43f7a6e8bb0e16c4de508c5669098c5e7a53e31f86aece908f978bc4694bce4637c17b198acec82edddd886f21e6e1c4519632df4a3931f7622e1901
28	1	131	\\x028a5ef76db23897682d46618c9950bff30013852befd7e44ecb4b4d0719ea1f6f1389c2926b90084dc691e8b876d723e06d2850a574b015e0bd443063eb5709
29	1	175	\\xf01876774f0e935eb8e25b84e1caa934cad3428d411021d4233e00d44f115eba728bdf91e5d86daf495322c8ddc3beb317e437d758e1b5ff4b7c39960086d104
30	1	306	\\x67c9d20a9c2ec9b42d402fc8f8b0af0913b46c70a7cbcbfd84c4190845aa488b0aea3e529255ed7652ea2f3ad89e0681fa95570cb286a93ffb3b67f20cb3f70f
31	1	6	\\x7d36845d447ea114b96ceb2410b1fd139fd6273c38b5be63aeec5461a4b2d127597f083bd5d5dfbd3f82f71e6b546787b11f433cdae43efc1bf83352631bab09
32	1	415	\\xa6e98010254e688cc9cafc27125386175f841446fe6a349b65504af03a4c57a2acec24d3eb7a4f55aa760ceff8be856aed7da88b6fe706e269e7869eda83300f
33	1	413	\\x8fb96983d99163551866dc42f71e8e3747eb8f8e6198d47de478356927316dddff537542b032b67a1a531e65e68aeacb0ee1e3db92947d2945c53774b17ac20b
34	1	66	\\x9cf338131c8fc8048f10bd913300447c31f4381d9378fc012d5b78fea5749f555009c098709b25fc48d975e1b2d83e896e44453b46c655f07ed20a7b6052e10c
35	1	266	\\x5c80ea3717e6d6a2dc89282f349e2731e13f73b011b15732962fc7ba86215067626b822e862dd8fa7b5619188c59aa31f999be8e8d867d8fd64658eb9762a60d
36	1	361	\\x8db3f2e011c041f842eba7eb278150a4f0a870c1d621022865f1b69e96a4f705e7a2e3306d740ee90b01c2e0f4b461133e5c443c174c6ad20a5a73ec048e6003
37	1	50	\\x887f105b08d9f2cea5005f31ae2e71e7b15f979ba029d62c2f376d4c6359209f1b2562d93e88ba8193154cc34f1c86b703b1b81b8adbfcf6284bb32a0bea5a07
38	1	80	\\x8f37ab69a7afc376e040aa12e506ca7da4eeb734758060e790f74897870a61acb0a5c95e7c3f350e4033e225b80bacd54cc6ef74a9744575baeac14132b93406
39	1	282	\\x1b625c0a4a316582b9d159bcd0c9f931736b48cdaf460528cfae8a82aa2c5388aafca5de230b4555565474af898596555493d3fe569f87b08c9391016b08c109
40	1	76	\\x968d90bcbeed1cc54e5b46bfa6140f49f41c9d1f1f6fdcb178d70fbcdd1b920614d0d5242620159495a4fd1e5bd15ad7c660dcb45619a02f568ffc0e129fe10d
41	1	103	\\xc5f1aa6f9ffd11b271568111eb661c819281cb6786c2ff6d687e566da896da0be93802eefbe80c63e338dc3efbeafcc514ea1e334513a6f0b307ecc47983d505
42	1	248	\\xca0eb3d0eedf614a78a63fc8b23e3f10b3c324d013a53ddda290300078895dd01c9cc42e5cf5800e77c3c7c8c10141b5ac8658282ce62631e3c3a44df0776a06
43	1	393	\\x929eead726fd579df00712c81175e4a99dea6994a9f843eb2bed12a47441e4f9fb878706d50f6a701fad1dc3aca7b7bad2d70d338da3d74908f05afa40c4ef02
44	1	329	\\xc1067272738bdcdc3a261e4221de5373d32e805a547c868a5f2a6e490aaf1341cdffea5dc8cca8d9cd21c36d93f50177ed8310032f0cba52607a0ee3e36c0708
45	1	126	\\xce99d0b403bb551d33c6655f8ed7016d00164c504b7c6ce8b861271b70b3d970b3043aaf7f73fe015517dc317f3ad24c06659db0af7fc0afd2d22903e633c401
46	1	133	\\xbd7af5929fee84e5a67b7caaee45f872aad8f6fbd9255c4b6be744400814a3b9529f427fe1ccf94c709b088f9d59f006058252ca637477227c773ccf52b1f201
47	1	292	\\x2a523f90d98592482d839631ab66e40813fad95009d6086c5f7498f4edbfd4cfc6203dcf4b57cf7c185d19c0f0fc74b8f326eafbbdc4767eadf936f4611c1100
48	1	349	\\x500a3910060373a5cbb43ddbb72ef218cb17c16ee59e67ea1bed389980788ad3124220c9f1cdec1d3935498325ae9a1b6db3fb3d64b3063765eff72fdc1ead08
49	1	265	\\x419b812f4f3fbc6ee405d5d0520952a09dac0bc16e175eec9c98b2fb7e23f7a3891f1af15db70e57ae4e312fd1837a382bb0f63901ca92c7c9b61a35193b8b08
50	1	197	\\x3665298f648a69958bc654ba75728921d8efdb4620e6d7069aef85cb09c4982a1ab24dfadfffd20dbfb57003eece3a2a25208939e26e0392f8ab7ad403c98706
51	1	39	\\xefb4a6e3e12bea476ebfb54c3d2a40baece5186e1e467db4e1532918c35d3592b60b2665df87d40ef3c67e62e5076de2a5b4844297f20d3ced3c44ccc6febd01
52	1	153	\\x16756513b673319b8d68b130d8ba2899d754dc7c823e4a78d92055d221f0f74997c14c413c8f5e4f7c88e4a7759c2bdef63d41d0d69a9a0e6718ed71214f950b
53	1	323	\\xfa2bee239873bbb9da85ee05c5acc58967171df7226fd042bc94dd21521ce90e1c5bcd73dbce5d4c8537b82471d4ca8f772f3f1e21c316359be7998ee1f2b109
54	1	185	\\xfb99a44f7e308fccbd3cf1cc7af59f2967e5de85624bcb5f3c5de6c4f5bb723c35ddd9fca0e909fd670720915b9b50a9d6e48a4fdd269f38303a6a4f1bf5fa0f
55	1	298	\\xd5f43bf7118117dd96b709e5730cfa4f6b166081ea899353d35da49a674ff3a529ae8ed263f7ef5e3cd920da66eaaab2878416ba5ffcb5245d26d51f14881302
56	1	409	\\x2a7caf0f6a6eead4d8b8ac031c4746d40a7bd678a24bf0fde0917ae944fb6fa44720ee1213dbe31a1e5779ee5a4a4a0373133c12050de07aba981d2178950e08
57	1	379	\\x1e1d72474d0ca484155771ee1685e8524daa8479d7ed122014c38cb9aae61901b156cab6fee2d9986a9832701c66979a3f92ddf8010ee8dea575385f1c6dc60c
58	1	53	\\x80385e1fc3320c6aa025aa4ed84ac4c170713a4e88b5d37859f931904b09772ee767ca89788bcc17dbb23bee1a2942d491341525f0ff65337a109c135b6c3f08
59	1	382	\\xdfdb08d084d0b4beefa4b81d021daa9d30cfebe454a9b9a5697ab298b10836397fe457281f7b8aefea77d7d5d21146e9a614e7aa66dff1025e85f482b8f03c0a
60	1	253	\\x1085a49c4b37250f71886574c93e40a438866ab0612886c70e54737d5de60bf0b2a599ff1394d4966f0a5a3a6c6bda8168e8256dee550a27adffe60964d85108
61	1	71	\\x961cb564eeeda880925bd89fa2d9e5d285368b9c43c1970fc3ed4e92741ed49420624b3335a823b6ec4a0688fc15af918b21e0a49ee59cd9c65867fdd6f66407
62	1	176	\\xd850a7f9ac16461f1226bf29680ee6dea1997d73e164a3efd400ddebc7e273b9afe6196cc7fa0b18c95f29c3c8968b63538e9f9316aafd35ef11782e0eb5710f
63	1	21	\\x0575878ef6232fec879fa68388309f077fc87099c922a1bc0ccbd927705446a34e29aa0a62c4903f696698dbab3384dbf42e98c789e3ec615488af68790b0b04
64	1	271	\\x25d9d82f2929c7677b52abd597d9bb5f0e37a8e6a5384e79cc07ef4dd99ab10cb5a3a44826a34054d75f84d69cf0a254554703ba9e4a296fa6ed8ada0d39cb0b
65	1	73	\\xafd45534934dc2fcf7aab025a10466c27a0fe9da20064c3713d20ac4d3e956eb9a8486aa488af24cbe5ffae0f11b0deab9ec0fbd05087b69d7976d6df7076706
66	1	214	\\xae0010fa2412b944ea75c4e694c71b7324946f238cc08d2d5f28c95131b75a6ed41394ef1090efd73dabb7420ed233cb4388073a1d7d1a43d7fc23092a1e2a0e
67	1	115	\\x4d177702a4d5e44895293a9c3b0233352b6d77387f26532f65b7a3e1614b9f0527b407f863cd882e0b957ca01e014705aa17241be4a7c8f0880c1323d13e9808
68	1	171	\\x5680a3801ee51ca4b20aa8f5461de9c14dd776e569b01af1868efd55b6c8743a0e7a39adeab5b027d0f2d94770f792c0c87059ff744f34629f823ace655cf403
69	1	372	\\x949b017a979085729d6ba2dabf0246212402d2a6907c3465322e6bb19211caa1ed8ab726db68e193abcc1944ac8dbaf4f8ec08e9897a2c206820273bb5cb160d
70	1	108	\\x1cab955db15863090a2bcd4f2db328dec9a9e56d1b2eda1e8d1f986bf35eacac5383cc75629799ac94a5051844107e0e8e86e059181829a256e41ae901e63c01
71	1	72	\\x0b166b4b2c1f6720af8667f942cf5cf1da3897eb37ca1932f6b1af4b7fce74eedf2fb57f969aca01cd32d6afec1f0194c9269f2d8d82676a364508d504701d0f
72	1	347	\\x336f79863b538a0289db0bb37d68c90eea19b3b0c92b0f409c5c446476e879ecc80d17d56341883907918d5c227d29f005edf913cbc3ca7713dc414dc502000d
73	1	226	\\x855b17fc7e4f5f1ee4c29361ecc39371207f5977b8086716bba7e86c7b1994251427c36c53af79c303e7b0e2acdfe641846d8f6bdf607f342ae4224c6712e00c
74	1	94	\\x1955e9b6dd4d0f40bf34d25cbeedae6314daa6a4edf1e2825dd82856bfcf027d87e7b24aeeca08e277276d0cdd46a11e10004184dd471603346e76f8f3948e04
75	1	142	\\x67f92be35f3b7427b16db7baab0d6efd4c3c9b50f5b910493b3eddd0664af7939594b169204746efeef634092cce856a2283be8100aadca3d1f731c20a455204
76	1	422	\\x33781ef668b4fc0f63f5d43cb9d891f301b0b865b614be68fe71c9c96c7c47944b472b1be921a6a402150fe60b382b3ff250b9443c8a79f0db3e42491741140c
77	1	423	\\x8c5079c621abe1eb026d234197bd787c071f309ce010b36adeab5503cabcad06c6bb6fa21f51dec5084f9378b32a55fa0c170234c9df44307611988f6af39d06
78	1	285	\\xfa0432ab264d7d105c1c41f3d67fc1a0263130c72cb5c7f9830576072dd97529098a7e598ffe85719caa0f04f2b44c3e354c69c56b85ca295be6659c1b626307
79	1	111	\\xd36051ca27f1e6616aaff572598080711e5604090d30d6318adde472a18accaae26e6c68e15926a6677c702eab7758352fabf28d8e4a2bd6a1c5ad820ecdac08
80	1	277	\\xeb18f268a0c98a99d72f9525ad18a8c4c814f57b4e943b1bcd3c6dbc011def4dd3501f156fa898c4f6a305ef17adf1e3ec085f1a57370a72b10f9c1221aec50d
81	1	380	\\x74f6c79ef1e52f88625300ead892612e558fd0a29eb8552e3091b2bf52a74163ccc0401f79f1f5c76ea0fbbbd6fdd8db516d9f5fbc2eedfc9f88fb18a3a54d0b
82	1	368	\\x3743081d8152f11976e72334892f22e4e857d4c952dbeeb3101782e96bd4d50e67ba3b0e0e9958b1cbc0a2fbee26a0f31697fa0e8b8ecec3b67b981f44163901
83	1	330	\\xd8a559d67f222f07213392f47edfd296eec60c296971c5e523e3fb6a7a4f6ebe5551a614f8b4ecc4ad4c3d38a286d5dd5dce8066f30544c21c4cd2db3960110d
84	1	373	\\xcf0d9cace570a117220b477655415d71d15a44641eb3c4d74d7dda53d30eb99fd84e5fd51248aa52d1290debef95c24651e29b70b3846fa866c089be2501ed0b
85	1	210	\\xe51cbb0ad8e3791020ad96c3406b5b990d3e6026f63992ca5b0319ac0c5a0c23e7d46152450b281d05af47f5493a67b70cfc253ae9e6eb58af45c681eb4b4b0e
86	1	328	\\x68da722456b376c40c9ff3b5f3c4153c40d10b45225d500e85b6a481fd388d5a317a76991175f7cfda0b51ac91a35166b2b2da7d55ec5ba90cf2d0a43dee5d0e
87	1	257	\\xcd5df0b5db2bb94996fe85169e0ca5ca0ba629c96f97caa399f5edc6fc6f323e21d43bff5ac570d2918bd518ee105cc34f91a9bca25bda383b2a30b860460202
88	1	124	\\x63d5d8a15c1f9fc928c70813badf5957e9078a1099ca9f4179097322c3c5cb3e943870f894a310e438bcd48ba07ed8ee97336fb2e850454a2f51e445b3957f06
89	1	370	\\x6b766bae45b2b7ef515ad272baec75638059f4b579ab04ba99dfed43ccaa2abf5dd815b452efd86cc9ec5c7ed0de2617cd143fa91ae201c05772c55964f4bb07
90	1	215	\\xf0d62be5e5c761aa09ece6aea964487313d3ab83ff39abc8d805bfe4203771d7fcd911193cb2627e273f30c9f03286bc194de98f7bf37a618173e609cd94800e
91	1	231	\\x0c8074a98e9ef75f0233ce44eaa489fa5e28d455e1571a8e065ae5f9efd1c777e8fdf8bccd7071981624d8c2934ab7365073b8a29b9ec358abaa1f019bae9d0f
92	1	233	\\x996d833aae0a498b4af2cea84d5f7025c2173cf172446615812478f35bc16ce23c4d5e73ba342557c3cfe6638a83a4c2e14b526df8fa945b2c86fbb3aa2b3a01
93	1	148	\\x3ef10d2d58f876e4879ac9be873ea0f3f8471c734c26b337822446fe55ee8a3d0aadf425496c952f1c5b36ec66ee013ec0e53367151516b60dbb52f1f28c8200
94	1	313	\\x234f937d7ce01ad480448d9aeea4bedfe613c9dc90aa15f05677bfd7f808aaf14459a597e963c92271d86fee40d9f948a554cbc907a53f7570c5c795779f9809
95	1	264	\\x517da153cb36268f77dee9e6916fcf2d4f4b801d5d985639904411c9a9bf4052fb8c530706cdbbd5600b22005ebb7829185a2304b607a64c9e455de05700f205
96	1	296	\\x1da74fa9ef8e4700ffb5c54999f1badc7d350c0d10f19f4183c4d0331d61706bbcfa14ebd6efc352268498a5a506516d61a30355974689adf46dfdfed24fb707
97	1	62	\\xf70de650f3162c3ce45557522bbe0fd2c6d01d9936a681d5c788c760ae9bf6ad646c7ea0c4f745a6aed254df3010354088a544cdecb616a67b991dba9701e600
98	1	118	\\x8cbc7b070232b3dd87356544564d798c17961117b1eb79ebfdd86b44f90543aeecdbf25ac6d4dbbe56b24e3d052bd50c56c63cb95fa0f590ddec6c0da778f90d
99	1	37	\\xdc455095e9063d9b3872d197bc8732717322eccbaa3cd729a693b69785da79e8430669fbab667d8dc730eb20228c23abd9854d3fee4a4798fc79da6ce21ba708
100	1	70	\\x39d24580abdf8efe9be8c1ff84e1bf2729c280562dfd12b4fd8f67444b3db9fbcbc39a3afd9c2351e2977e01f6ea62482bc9d72491abdb9368616c882edd7c00
101	1	295	\\x698c33c5de4cddab015197aeabf320f845634bbbbddd3bb12537b0512a8d1bf3369557847c3c27d2f9eb62ef7254dfe86cbcf5d01e86e7b830475d7708486f08
102	1	41	\\xe7ac2fe3b1d1fe44587aad3d6098ea744443ab0d2aaf341f42a00f1ec1468c369799927d8c96f27ae652f56ae0b9bddc869180d570ff8f7b8e31a250341cc70c
103	1	294	\\xaa16a044adf8a544b67ad69cf089bf24f678d8de51801403ccefeafc515ff5c0be51be96a01755814314967babdbe3d1b83a20fa20fe261e377750bb3751ef07
104	1	319	\\x1aef00345c10acb3c625da7131bfa318eab7b50a7d55d8b946c15a771f785480a29da677e0189d845e99570f52b87b7e501fb834d94db69997c028dc96e2070f
105	1	315	\\x73a9d31cfd84f2415122ac77f750146aaf5a9eeec0d20d6aaa2714b02739adcfaff61334ce79da425eb2cf7689458bff20d400286a68d8b885f69d3e988d8301
106	1	222	\\xc19c9ce7be21270a0a534e5541e2e4a3d7375de886ef95d1925b281d35e7e26d6473ef6196dd5b8741d37ec4a6dd0d1b1abdd32a8097c615b5d258f304dac90a
107	1	407	\\x386f9fe2dee56a5736621e504bec9acd90c40a3d98fd84578a1bc58459c51c09aa9d9a840bd533aa51d91f080c38c85b4815898ae1a3699b4f26bd9015dba506
108	1	104	\\x6053fca5e3efc6d04bc4657045938eba713334f08e3c79b36ed2cf1ee23c3abec8e940b0d2ba30b9fc07809015c66ef1a7c4466169d9abdb4a08664729b02800
109	1	232	\\x4f3546d4c1a4fad45da01e8b07714bfc9117e7904107e22084010dd687e4c266930f278955f045a96222bd1e2fd5e395350fb3130e67e312cda37c24dab64a02
110	1	236	\\xd1190324ab6cf254fd966dbc7b70371f7ea8f03734427c0d6a48a6a83db1d1844366d9f50ceb908ab950b4df0c57f113cf7ea8c717d0aea3f54b417ee187dd0e
111	1	309	\\x900cca07af2ba6f3a8d42be83c53fdde8707effd789c085a012562b9b58c155af16d6118aeaf7260f8657f8b3125cba047228884ab7ccf5cf13ba074ab2d4a0d
112	1	212	\\x2fe683f8271da036693cc79d354d8542bfe9b1cf012e5f222fcb2522101f47c9cbaf77ea7914fca51edf4f5145cc8515d0d468c00b337a831c5e1d8dfbebfb0a
113	1	164	\\x4378cbae93556f68485ef7a6c974dc8c5f0e6074f03e1fbcd0085e90d649cbbafaa2a90e596aea9db58b1326bc6a982e10b88cadd1ae95e5149d35652973f805
114	1	293	\\x62416af44e729172647d92d57bf0c4a7ed8b67483e584c5e256420c02900f724817252dc4ef6386ac0e66a45f5b5ccef87d685c7a1bf0a9e252158d32b5af700
115	1	392	\\xdc0cbaa54230d790bc428350cc00227121cc748a808982be6f67eab2c052bc033e50dfffddd23ba373dac2affed023b43237e2e6b0f69ecb5b85338edaf4b30f
116	1	163	\\x788f682c4393a81a9cebabd11eb4851e1b81b1f6c6bb332bb5a9836e743551308c6ccaa6abf7dc3f93419fd68277e9d028599ce63bcf42d32adf5eb3e3ebe905
117	1	81	\\xeab249dcbb1b0f6f11e62e6a71e585b9de38d78fa0bbf4ec80c678db9fce7710bead5fa503649aad55221a04f7434a4f6d248029346e0517af157085a947750e
118	1	120	\\xd0fa3e03512786e3b8f05bfca0df12e6ef0988fa4fcb0b48191e6e427b0ac082328b332e1a19dc65a115ac331350deda3eb1037968503f98a3c1d55383e53609
119	1	367	\\xf419fb853347b5da4530e8aece1c82142d78404ee74dd0e0d8c50959aa00957e663a5b9e22449a846707caacd6d64c05698819eb0a939bf50fe0e70610bf370f
120	1	340	\\xac192e351cb8d26b89ac741343c026deb6cbedc632c1a68ab2e51be82a68a52afdfbcfa56e8cbcbcbdf2fa636057da9916d55017d4763f5d8099809ea318c102
121	1	166	\\xec53a40579ec3e726ef0691d4b9a4e9b562d78dfc830d5aa5171ec93f3c1d1a7d5b239094251223a8f5fd2e9b23954ebf8424ee297a95734d8cb96906c296409
122	1	134	\\x5e3d0508c0c503d55d5c55cde19b128fc72621b1142437ef2eaa4c8f0cc82566d344a19c7195306803f6b482e68fcfac19a425ee276288e7366cdd0a0c61f508
123	1	408	\\xf622624ea57e845ee4e3e41aac61e4dafb06deaba704f4e2336e43f93d20dc48feba4b129589a832265d4827a9e8519541912280161404095555b294366a8e05
124	1	158	\\xfe933f0f2be2bcbef2dfaf03e1099834cc1f429856911b2652fd7c1fa9f5d907df664f76876a95ae5e73023299f360c5969d695cf7e5370233e22e3f482a9100
125	1	417	\\x55a8c3413cce8da8bba002e05850cf45551365cde847fb33122ae5266bf65c00583d0bd4a5d341b2c0fb7f763459171d271eaf1f5d508fc2f0a3dd39aed3ba0a
126	1	255	\\x45f0c931d2e219b9caf5181f84815dc71dca2b3ed270be94cb6d27bb53b2b5aa3e57858f974c12e8a0b9a118ebc0f5aad8ca4f1e0684099510762f040f07c60e
127	1	225	\\xf7bf9ab9fa032fa4bfbfc0d8a349d716a7737d8c26fc35477e0c95dfd30448e6ee7151f02071c12a05476fa7cf3ea3d9d493dce04370c7659b83d7aefd8d4409
128	1	45	\\x846005212761ee189be123b6fd6797c625cdc33718f61c2e526fb80357a90e5af0d77af1c889b79f5f7fcc3f6178797874d71193ef13a5468364f75b2c79fa03
129	1	249	\\xe3001df16385599d7082d1b2dfdc6b97625873681a786a06da24c365974951e0ec56ddd75225d14d6351ee312b03952a8bdfd724c4fbacb9f134ff273aa70908
130	1	359	\\xaa930cab09ec05c44a2b16f5981b2dd13af02ae7a4d78805b4ab68fd1432b433ecbbf9d9e72f7414ef0355d22bacec4a5f7cb6a31e3d24972d185e1b2cffb000
131	1	55	\\x95cd483e8d401621d1a129a97682802a462b65f28848cccb324ae50eea2726d08b21edac4e7b51c167e847ad1b319d7be79b5fa9d53b173dfa5cc2c7d475ff0e
132	1	186	\\x7f780cfa64cf365483a237973c975cabab2aee93a637d2c77145b4a20d09bd406d2e302da1563f50c50f2ef78691809138247020d92eb36017788cd51d7b9709
133	1	57	\\x6caa8c12a2b97aaa0137c6317772bc1009ab615ba3e74118398a902d42ab707bafd4d735bb7bae5eab0ece7240d3f6fc723a218d551f8aa525a7b262fbc4cc0a
134	1	310	\\x30c5cf67d248314ba67433506661314958b09e9f64005f740479e004b4758090a272a64adc9ce627f57a5aeee554c6ade1bbf8e2a2ffa122e7f8dd30fa6dda0b
135	1	316	\\x685282d51e1b2b99b3a82f904a6d64d8c544f686b2f3d64a8544999bdae67d6be274b6803f2ecc7e595883e38f3801f4626baa39a519a8d399011e019f3ad906
136	1	237	\\x69a9cf256b2b3df260c5f7a9a1c86437946f61959e47c639133586227161cce5b1c21b414d5b53ba5c61875ea74a27a46d75d91554736354b6c0299baed1c204
137	1	353	\\x95737e35dbe4982de64b716be63cbaafcc1470a8ca448c8cd4e5598a3e63d3a1b21401b4d8d87e3e594b4e84394240d2391fc0e8b058e7475f2b1dda19aaaa0b
138	1	376	\\xec666b559a83f3a46219ea5fe146693200cdaae0439ee65fa4f79c91fef95c36538497b79af7167118c9bea78ec3df27f9b7339664ff4b9b6b835ae4fb4e7a0b
139	1	46	\\xf8f4881fcdb892c1279a0e4782dd0caa047e8b13263d0a5b2a3ec35e7f59162b838f3f602e806f662bed5dfc9a53274f5525dbfb3dc898448992c53fe2b5b409
140	1	79	\\x09918cac6fd0adb6879b408fc274d6f1c83f1312c89e111cbe25063dedbeb3f841970aca31324a4a298d4d0d52205520d616e278efb93c0dc0cfb261af34e40f
141	1	146	\\xca1f96e0db977425037cf131c1e834c089b67f4108a870f5b54bc55fb4b3eade6113f937db2182dd3bfe14186e161c5ff51b7518f28e275aa32028650b35b301
142	1	154	\\x6eff11a2f6e47809ca144f82e57971b51dd76ebb6f21a6f666e0fa2aebab7fdc9d5b8f3f004a169035e5e110be588ad6ee9aa2a932d3dd38c79747e773425e03
143	1	199	\\xa9827247ce25e11694dfd7c3e1612edd1b322d5f2ffc1971833167f34cae4e1c5c398d635762b914f31af026c36aeb6ad810747ffbb51b8e0abc09be0369730a
144	1	338	\\x77f2b2a532c158f0d0944a9a05d12d1d412790cca7dba783f79c829184c453f4c3bfb336521472b6406b3712314f9fef239a2c274a24c0937eb1aaba37bd850b
145	1	179	\\x7abecce0a80a964015a34baf8c72dde6565172bc9063de5ec5a762248a7baed95c701fee533fd90f1c390ccfb20a08d2a1d27955f468cf95061cda0b6667c303
146	1	261	\\xeb8b4cecc78287ae4ed190c8ad688eb933583acf9436e54e56d8e2a52e34c235a715aac36b34be5f27865e11d92e6118dd86dc87b9454dfdd050ce937daa1001
147	1	303	\\x935e4454bfb7fa3847715847d5e5f7c6a518a86a00b8230f1d6ab14f0c2c1a94f557a367793cdc1fe07844d66fd0cff93f0dcbba98b6313fad14d8f152f8570f
148	1	217	\\x200ff0300a12417cbc2e85fba8862b34057466a6a400ce06ce90a25615d3430416b4586fd21256ad0eab5438f6bf88bb253870dfafd749c9a34a646bd7547d03
149	1	228	\\x8aaa3c1d9505d0deec5143d54fa19ec75ad6787642a9f1f14fd5fc30cf4e10f2431fdc06ee043dc118a1fc559c707fb899dce9703da38213fe323a679f1cb40e
150	1	206	\\x5e2de849afa82ce3cdef0521bc9843599342de1a934b45f2dec6a9093f96e5cce499c2b45501b07ae869cd26e2783a398a74898acd645e49c06a141e769a2d0d
151	1	342	\\xffbe214eec0b34d3fff9a86f817f5c60dfa995a7b32cfa6c51dbb0eda5c1a7acf007d50105959e3aa55201c2c2ad70622f98a2b10c0eabb13ef7b9c7b341850f
152	1	223	\\x8bb33dea2aafe24238ad5677b78557c8eb4ed97d8c0740a5e5fcf45c6c529ad2f5cd97cc61d8ac931fef61f48472b6c542e35c6cbc136b94cbe6e988362e2b00
153	1	85	\\x21a801f374145b978537e49c403388b99f00c447953dffa977acd94be5ee1665f5947cf8f459052c439e5fb64336ccc7404331c689e1551efb73adc04927bb07
154	1	337	\\x55f95b641cbc360a826ceaa96ffe9ac448bb97668329063833f2b109fdf17775c53cebfa566135169f20dec21e20f3ff74cc430dcfe97cdb2b69d915b0a0810a
155	1	33	\\xaff7d899f3dea09c79e03818ae39c87a90a5a660ebab4246255367c0f16b794f33a7bd0957b4ec5a94e22c2e79c8490d6260ac14f48b435bfb7b11ab761e5e0e
156	1	273	\\x766ec00d8eefa7ca158504f4d723216f808faa3d0a397785ca44ae18d0a176e1ffe706da7678bd5764ac53456f6753f9ab47e7f040b57b24446af206c4bc820c
157	1	291	\\x109aa483ddf055a9943655d875b043a78bcf2d30132992b57ab941a3b424c678785da3271188ba1f3681917e78b880428153c65a0be3836efe7ad83abbb3ae02
158	1	300	\\x487af3f1bd26a8f9792cba2d0ff900771f95acc00137c1fed43a99d03ab4ff65bc15738af9f313b9a5d219befca5d22217532b0ec993abb9c35fc2aaba8f2e09
159	1	312	\\xc6102436770d0b16ab5206a0330982baca28d4ad12d8650771d02ed29ab1a0427814023378832dbf76901a99ca63efef48aeb4cc30ec7eda38c6b4a306686102
160	1	86	\\x1cab98bc4220c5a376ca7d538b17f844e4b4ca1f2e6df5a2b772ee13a0f7294e68f5f3844a60d319364757a66f004b706a9cb8effb548710680544e9118b1e0f
161	1	250	\\xf3b0200b82bb2c8ec2fa50effb28b27b8a2e5c99f60e8631db076d747be3b7f2136635985753625489be1423f1df436e702c1eb00279103ee1b586eb841ef007
162	1	42	\\xf98048960f5edd079d6340f145a34aeaa9d6f9d5f2e12a562e219bed90a6bac97f3ef8a3d66ae2be6fe36c4220c9f44da3da729c3404994ae97236775844b403
163	1	414	\\x148ed8ebe11b57a022165d84d71bc718a876a3881e4858ba5da937430d84f25e1bb16b1dd9c569e7aa9c755eba6d037d5fbb22729ff7397f08589024f2f0430e
164	1	90	\\x65bae5ba487ea4bc0c84915286a618f363aed0b478c877c2ccc83393744c667aa0a5c1d4b9348413eab3a0c91fb75dedb7bedf9bbbb2c57a75e0bf066c027f0b
165	1	184	\\xa8b8c25c70a87bf9f0a669cef497941d5855ea77e2ab664c6ed8fb8f99ad69a3aecd5b4cbd717e079bc3ecec1bed487782f38b3af9ed3f8013061807bbb8c80c
166	1	155	\\xdc026943d08314b8f1646f3f8d74fc52b7d99d1120136c39d2f1ffd1324baa84dc16eb2cc2f1b0a58d95fc30907326a469630a805c5c984e9111096370d0d601
167	1	254	\\xf22a9221de131da784a0f57041356076e48c9ffa8172ee8a71228ce2c57c791d9997569ed845e547281edc8a2ca96701c312a7590cb1f8f1bd0aa82a26374e08
168	1	364	\\xf3b8db95e0bb3595f57c8d024a63875bdb8fa9aef5a0bee95155c2d5f2e4cc13029063d3d98546b06600731342e4eb84734570c6f630edfb1a892820cb99b303
169	1	381	\\x4e895ec2391dced1da22947a10f906efc86922157463eca66cf2a4ff27fcf4fa56602917c065d593e05d3fdf61505d96cd7e645c9c5e073f3176566eaaa2640c
170	1	360	\\x62daf0b0bde2bff986e453e90ac2d2a68e57d218d6dd31c9e8d4ad89162d6b93505a0cbf702a234726eb5d42d574d2c659c2deac48494b749a46728dd885690c
171	1	203	\\xfcf092c576cc5816edd662ca0cd295f2ae7c7689965fe283deb8f9d45151b36a3a2091c9d417ecae5a8f445d280177ab92ee6222a1a294d5a07b23299f8e570f
172	1	288	\\x3911f9a17e2a72402579b4fc842bdc042a5ca00fd9476b29e16f3070adcb90882d9abdcfae4991867967ae0325f0479f2b0d079c5670441f9bed5d58923af903
173	1	259	\\x0896b0384e73690170e75e67a331c96e713a71b0ff2949320c611ab15ad7ba1375ec898659eab78b99bf94d675a72ea53a63ba89f355f6cb426596554b194a0f
174	1	362	\\xdb19fd57967f5300ce522e22d23f9a3d95825f5530687160838f412b5f6a01c90abc0c4699f4f0b9e18a486f49583374522eb85a30efed3ba5e649d7a5f4fa05
175	1	190	\\xd18ddae1dd154cf2b061328ed1f9b3bea80d37a7046e1c2edb9ae74c9c621aaae27104f11eaa33119e9b8f75627f367682f634af90de4c6fa5b6a7a28c89960f
176	1	29	\\xd4886809f9ac85280c0cf6be6062be6e1bc5dfd53ca9253998911e2526449a3db839b3700d255d6817c173ac97f52ace2a2b2cfa3cda9cf9824cb7ace03da106
177	1	26	\\x8ccd936dbffbd0f658ae52a142f6d4ebbdd03f7fdbf2fb5bf6427e2d02dd22e687790688377ae2e380d47ee63fc97a80f66c17ce614c9a0e1be63f7095a0f00d
178	1	191	\\xdfd24cf29efd076a4bd5f076df3d954681a815b41b619a628e2dcfb64e49473d141435517b02846fbbfb127e622eab0899a689b7f1145b5f30dd4f039d0c8100
179	1	343	\\x7e5f52e3e75239d903c33cad8bde838c6e875080e89d2724c6d0b5e93aa1f8b1f8983bbc6d6c31b184e7660e74317d7dd54eee36ad0ac80c81cfff262f38a306
180	1	168	\\x3e03fbb85b72be90070bebfac79440f9f31eef15a003a4debd4696104441a4dd830cb9bc21065b22ac533315bb57aad3ee059cdc1aff12caa1fa6fa88be20700
181	1	107	\\x4a55474365df352228fbfece303aab4660559514be6dbcd87573ca328782cccff6cf85219c9e06bd2ef61b3cb82631454cb3ff2cbd9c74393eee2f43c8cd5702
182	1	74	\\x50f35fb9fdd05871bb1ec63f33f6a929479ff09f09daa51c359deed990f831b9d99b15b5b70efcec61d992b70be1a9ab8ef5fd5c172a279ef4e5b5bc91211601
183	1	15	\\x9f54d5ca80de110dc664b2385eb5aa3001b996a3003e405f94bad8aa4a9d9e0fab04ddba8f1d9c1002ba0477531a7dc29b760660eaa4de581765f8c5669e600b
184	1	418	\\xb5e3746d71ab6e9cacf0cde826cf069ee0e5ff6532bd62ede1aa05054ab2e4e0cfd6b24474ded921225406b16b6d38c0739f301e4f75d109ce97528d153ce300
185	1	78	\\xc3911ffac36b3027f5cd367122a04da0c25d2896cd6a3a01b937b3c86d9606baa581e5b7b2bffe0d41199b0fd892c17f24e35c2cc864f93d880c207986221006
186	1	198	\\x38fc43b21e160d7bc0cfedd663a2b5c226dd36acfc808de4f779049619b6afc93783e26c85e5efc2aa39edfb1627a55575db9ccf19dc5c2626bafdbda9bea300
187	1	139	\\xabf4989f0c7ef976e0bb2734a226d6c0719520c9739bf973e39940b366cb2ccfe2180174aadf5d9f073468140ce1481e86c382799833b0f26c65a7fbf3662e0a
188	1	324	\\x0dfc0e3d3de2dfa219a06cc90b37eac71d6704b86da49d2b6faa8004b7c2d08558b9c7f0642c97febe6f53e8848ecba9b39f2cdf993dc5fe42c7bbea2fa86a04
189	1	263	\\xa6d2fac6e9f5e65fa455f9e2ff44738b0a6f5d7418211015bfd9011273b3d749d66ff8d803fcf911f6841f765354860291cc0929b94e3b5068400908a8b1d80f
190	1	403	\\x1eac06393e8299539923ecf69afee25bd02acdec3d53baa0c5f158e8acda4889b9007eb85ef9bbeb3727b271a91409ce392960af0309af87c76112074f772300
191	1	180	\\x9154645d2729c8687e138b76042480d55c4fc74021be75215990fa369c0c9af4b366d99fed40afe272a660a1e637bb39c31e8b9e12b71699b48d5af0c534e108
192	1	268	\\x7a269b10e8fc15bc0a0be5503146645aeb757475cf73b9f06e6e49f7553aa5d614a281ec1390dff400f00b79b02360eba7c8507e02d0de246a6d5107c939160a
193	1	122	\\xb750681c2c77eca4c1189154ddcab85795f89ec2bf8634c8fba867cd41d65a1249d160d12859f61082c708eadc14d4f72aeb3701f6e18a0aaf26adf224e2e604
194	1	246	\\x0999a6fa58cc71cc032a773336a4eae93fea4f9f3af83d2513ac6d14e219d6245ba5d0e3795fa13f2db20f2d03b1545b61d9f82a12478965f1e01d2d8c9e4d00
195	1	123	\\x01b108c0ea0e71c27b7f5b9b6ba2cc1c692d46317913caf2eaadc2b6bf440a6270057dc1877bf47e746902c96b1f429de0e41d3420f5b449bb806ae1ad8bd40f
196	1	93	\\xa3d71fb9937a50853e79aa83f6a9759a8e5284d251de57a85997348f10e99d5767cce5397c5fc9ca33eaa4db22efefc080409cf02b08f1e2271359f9a00ec105
197	1	102	\\x06ac96b0c33d711ce576749d8782963a6fe63be5a28467cdeb25febfc2237f3fc686363151cc0b70a2304f59a98ea0505b7ae228df6cb440ff5dee4e6ffaef06
198	1	13	\\x1545a5ac5f8ab10af1b77d467ea6a9b860a160e137503b705850509320c6312328fe01ca1f97746a918b8ceb85866deb5281b434ace26a1ae144462b3ac4a700
199	1	332	\\xb7ae33a1eaa2cdafd23cfd318ff1acfea7318c1994b0f48d787b7c0823b79f25f8e8f9e196c1bb880fe397e858740a6d3379092e6bce0edb4cafdd609f522e09
200	1	335	\\x7af85dd24a659675a1f0236395c590b11adc1fe94834944264ec7c747cebd64ac4590c8e93b6886678bc9947a7b19b39286ba091507e1052d3350b9c17e5d204
201	1	63	\\xe025283cc97f621e9b79a434f7c6738051e033af60f57e5833c42733b1bb17fcef1ac061d1863ac49347e5984c76e12f77a1000d3b0b9229ed3d79ded4ac7002
202	1	350	\\x5bfedee5f91b1b1ec8ee031551ed6927c0975bd5efff9adf2dd096354fc8625847f8c5a3fd6445f012770bd6ba1cefc96f7658624147dcc5d40f11b21710cb05
203	1	18	\\xbd4c471028a40e70925465fcb2cd0b932b8e2392bb0b92dda04a9f3bfcd1f9aa2b14776c65caac06c203ca30b95b4b356789c0656267109e6580b0b27cf66a06
204	1	280	\\xb07faf8d6320674bf9b1611515fbab56130b15a7de0aa9f37e16c18ab852f2390a7a7f83d7cf78cddcd07aa32480c99bc8921d9093137b85773a28dde496b308
205	1	333	\\x2b16bf57064cbb90a05c8255803faa5b40b72071107931b127c5b5117e0b33ec493c71e877ee131d9f5b09b2e4baae7659affb0629e9a827b7d79631fee4fa0e
206	1	182	\\xfe4814b9533fd77a85f547c2f692abccc9110830702b2f31a8b8cd3cc3d8b9294645a08a4526850bc7787cb37d461a34cfb891b6937b33f9a897d4d031d27e0c
207	1	397	\\x5ddb598022e147134941eba5901424a738b13efb364a8d654d98c27b1fa543bbdee93f1eb6c0ff0ac5e672649ab71894fe780a00e64682ce6b260fbf0b2bc109
208	1	112	\\xcf8cf8970e62e741d1d998f3eb11757b5bcc4487a0d13645131a86700470a23915b22c65f3f96b9cfa8ae8aa2bd1e4b36e83d0cc6cac9fe018ca7bc9547a8502
209	1	92	\\x86fec0a3081740e0b3f9a453465f4b40616a11b3f1b5768408d362a618e35a24c70cd5fa50290e334c1e6032bc492bcfe18f4d73f63facc9cf83ef3c0fbbea0b
210	1	143	\\x140a7e03e9022fbec873cd1883405871118d0553dd02b1eaa69f6f7bea55b90df02cfa4b8c8b9f644f3dad7ccdd3b165139bb005757f49b5e04350dbace35303
211	1	245	\\xfc39ca0c2699cdbee0a4eb6fd5099fbc7116fd733dfbed657d8a62db2e3778bde48377b1a97b12dc662305f1c8ee5e5e06942899cafe9b7db1b47e9c02ea6b0e
212	1	391	\\x7beaa8e704d5365f006468256a8c0a2ce02d5e9b8b5ac6ffabefb4e7f11bda1292516423fad6d1b6cb468aaa391ea703035e3d3aeeb4357fa9355f26192dff07
213	1	117	\\x96e0c8f9b71c5322d125a980f961d474f1147daec825aca84c9899faec2dc2aa4eb16ba3f3d804afd8105b18ba9123da82141009b5eb6eb7725f67c1eddfcd0a
214	1	31	\\xd42c145ce1d6ae9900222a0867a1a52be4ca9149535dc1eafcf1302f827658434ef865d14dce16904e330784cefd8d4f6efb2ed48b2e3bd901e41dd5cfaeb902
215	1	344	\\xa9f30de8d2f4754706a33b1c0b20c416061949371c0874ec8ae728ee23c6b47920ad212f3ed759ec49f2a079fe4243c538e03a2ae0787b03e3af66a25f59080a
216	1	348	\\xd49e2b8b473b40391cfeb33b852d97384c94fa02e41b44a200911c314d0460fd1fe85785c3d21328dfdfcca319e3ec6f34176f9da3f52ca373bc199539ad4e06
217	1	189	\\x62f94a02cb04e387960c29c6354a55daeb1d9a689f0f51127066ca7ee14b9070a6ce973ae2abae2303ac8b9570733f6bf330d3ba5570529b33d1f7dbb4cdf40a
218	1	121	\\x3792e66af4c15410aea92154a16c11288b11e9406054db5c9a6be83ad15e4513e1d1b80a7b07065792e1f1d1addd21877095acd6e8b7208160e1a7fa1d816b0d
219	1	405	\\xb74d27ba7b96ce1ad07cd36159a5f7f99f691f788be9c4d540f55f7d17cdf5e2932256081d9d3b567fc597fa08737b75b96ab5bfe19c47323a0ce7cb95549001
220	1	195	\\x124f9868a0fcd1cfe2582841bba2253f1f7b1da120b355a977d68089173c2791f6c7121420f51f9a1b4140c7d727fe5cec96698f0c8ad7a131033ba66137810a
221	1	59	\\xe79cbb730524dd2359ea531cc88910b3e8ac22637c0b2d367a0b86b1e0469245bb4ef13c623f8305c88da16949010c3c29c5a62d168deda82be7afa5d2ece703
222	1	44	\\x16c4609d42fc9c2faab89aa503b054ab4c0f3dc6e8c0e61732e397bbdcbf6c422344fdec93fcb9a47d48d70906ff1a93f07644c0f5d16ce4a6f29b9624d4e801
223	1	167	\\xd954e6e0b03178570b08832719b3dc04e3c5ae223ce69b0e5b2d06270570617782dc8e5384cd5120d69254b9e40621f7d1ea67555e2029535256e7d401bfae07
224	1	354	\\x50cc98340e7a790766b375dc0d0b25e7d75af409332e4cf03a726b6f5b28651cd05362bff7f4bf0fb241f9ae5fecb399ca6c521031f0ff38a115bff9888bae04
225	1	159	\\x390822622ed654efd9c1536f97274e00da21fbd3f527c7e20d0b8948dc9e230c9b4de5de94770c548806dbd29b2460da172de3ecf3ae9bc1bf9fa46997b01a01
226	1	144	\\xe1504901fbf373754fc98991a537091107b307c13fcdca89e806aa8db4936eefa4e859111c678ca55569f957a2d9112ac19d3d49588f72eba0d90c791ab7f300
227	1	321	\\xb72241a9c870678375b43030bb6cb6b30bd10507bf96732cacf99cf2f83bf526b4dae17c3e329dbc914ed4f5bfcb67e1dd4fc81df6194859be9723838c670a0b
228	1	230	\\x150ceda75649fbab9b3aeb322e9fbba487b1ca35cff3a8600109bcce56176a635892842461f4a3f967aa0f8ee6d1b03c7f7de4764f96d113757d2deef5bf5b06
229	1	339	\\xdc64d738e24b863b5e9465faf6fbf9805a7a8ba1fc286299b0ff237a831087688d9bc5d3f7411da1ea9baa3b5bb0adc1d283752d13d550611071984d46dd3502
230	1	284	\\x7e5960580cf4a16e19cb9847f2b41fed728746414814b5699ccb5a7d84fca215b5944375cbdef3c6f61d4d349a113639a839ceb52235f03f805e60a9da4c390d
231	1	318	\\xb6b6016ddb2d7fa0b90179f78e8fa74c86c7aa434b55e928246fdd65c0fe1cf3397e040618d865c55270a184d866ee4343bf2049839be971a2a580214d6fd803
232	1	412	\\x9c3f5d6bb17eab6c98c3322ff7e6d2049a4f93fc8cf1198434673c497a2ab8f6d9cc8cb5be4e3055a23387a2ff2489e5f5a65745380f8d496518c2026ba6c202
233	1	375	\\x8d40dca37103b3f35332d4781fce91f9ff477bc8056eea2a2e0dbc7cf52b79cfea6ecdba9c8dc519374b23395d2d276a0c10b27d0bbbd025f53b1a83b1797303
234	1	34	\\xf7f4bad4fcec29d482faa6f846dd80be30769c796eef87908a58dbbde48c5ad914c752d54527bde6ddceffb63989f08809a94732c37a8018d155dda814f4cc05
235	1	119	\\xc9c1f1826d27683153ad9fc90e5a2570939a21d4e7614ee65d32a1cb01c25773dc6ad6eca3a0a4f1a1fc9d1b9b40c9b90a88c1420b1d584c86784cc8ccfde70b
236	1	82	\\x998884ffb4121d25d8df8518923da3864b1139f3ee568f33bda078bcaad20a66a69520aaa4a0061969e41fb994149a193d5711695389bc19b411ea6d6041fc0c
237	1	40	\\x7cd49b959a80be5dae80ed77bb8aceaaaafed36607d7bdb983d77460b1d3be2d3ba781afea0336bcd92b5ab2d330fa72246cee5c28bd3fb187b3448fe7c5b20c
238	1	272	\\x489ad32e99fad32373961ce922e935af5c0e1d75511139587bec2c7a8f201ccd2fd3e2d5632b5e98e1731fe35086e9438a7f7cbdb8eb8435aa02979a4c763309
239	1	301	\\x375d179a23915d373ffe83ec63f786706600407301720e981da35ecaf0a967907c4236b700e6d54af4bc52868adf3505c013b76278dbb6b927f7af6b9a9bdc0d
240	1	152	\\x7ebfb0d4c51423c6fcc67216ec97c145466c42af338aac82f05c1c89d0819ca423b0439e851cb595c110ae2536ab765bc26a7987b066a474560aeaeabc0bcb0f
241	1	205	\\x080904e315e0ebee77a03e9e21f89c0b917bab77dc63409057e3c2459a83a05fb23f67da016979b833ac45a213290a7d849f27cb93e1c687175e674e33d10207
242	1	356	\\xd4a843afdf6c736e3541e16a379437e4b0e3c409eafeef23158a55c23e868df9d59e349202b70ffb703f30c3a5a7ebc80358cef68b09530ddfe09fd607a9c20e
243	1	161	\\x76bffacc5ee8e44745eb1b5afbfae0d4eed2807e6f9960f0e7c3f8d54e4e0533dfcfe82e4fa63d58f808c7a7902dfb882be2ea8e38bcc3b9f843c2259b68a007
244	1	289	\\x5515293afeef073508614fa870cb7609ce5b9caeb1ef4565fb77f45e6e6023e0b929e87a8ce898cfb3ad8b025c0655693d873c6b8709396c95de74e6a49b9808
245	1	331	\\xf47572d1febc3ceb91e45df48a3b12712e67eadb81e42c5ed3d7443be105794012816421311cd7e63c0dc9f631430d91f26f2206dce8c158d3f043cdd1a81806
246	1	385	\\xccd83892a613fa775e4fd451f536c5eb212a624096ce17abd32a8385d2456b2b6130ecb95c145768291a9044d1db8a5bdaa0a61d0f53acdfc79c3110035bfe08
247	1	386	\\xcc84bf340b1863ccc13e18937b818e1ca466e784ca48209d115f31aea77b72fc1ee7801d3143bc7922646faf075324c2ca69ceb6966aa9ccbbfa9db7454fed03
248	1	419	\\xad2ceeda740c50b88ccb79b863cde696e7b54c94f95ec190fb49e28cd7daa674380d03e4dbfa74e6724eb827b9ebd798eaac3b9563227205399626ccf1be6800
249	1	162	\\xb035a30efb961420967042ed811d1aada02dd65562e5c526ccdccdffcc600d1a564d7783dfaa71df0f7d8428a3c1f9402a2df1312ac0cd5472b7136379e09e02
250	1	365	\\xa1f4e31eb7507b9a0ab9d6a66d81e410701f6e7f5abc19d7d1fa28583da98414aefab352fd85edd79481afea87605bcad7f8e9f97012429a4d30b14f11f9e103
251	1	404	\\x3d679a40f383493abbb61d31176d1ffbd90b40a91cea2ba14c8f828a9c4786bde560c25eded1ee6e507ce57b8c3728ca249c7ad1f94527432ced7555836fc702
252	1	286	\\x759f82e32a32fad0a002c6a9c2439b1a2705dfeb3dde9a5c147444f33fcb56e280e9e99bfaae0d0fa0ea9f1cbbba54258c9775cd67b85748cdba5942ecbc010b
253	1	274	\\x4e2d9428225a383bf558d2e0407f7fda59bae883ee19d072f4c85fc4c791b90554cf1ac93cf10156c8c100f3b09403def74402f875a1b5d74caf7f09884f1509
254	1	87	\\xedfe586f2b07ae7d9f5366f63ab993f5aa4b034603e11750d454a50c664ca1bfa71966f2389d95280a820aa018f69bdb7bdf6d4bb38a8acdacc3f2a82dd82706
255	1	137	\\xf2cab6eae1a4ace96ef3042c5cc7e6aba50ed4b73ba7bfde1226e7f9c69845875bd1d745c31a6efc510214414b3c6ff2ba4de564f9b82203aa65ab02cea3230f
256	1	220	\\xa939ad3894ffbcac74368dc08f7311d98f6ec5ac4e9e9c1e18a261f9724c684732bc122e51ccfcf99f847572d6ac03a9679f0bbfc48cf12fc08d57151e97b20a
257	1	207	\\x0571f07c303abc50b5082d149e90b48e2b7c5f77101ad6fe1aefb08b5cc6b445bc7b019b85b935865ae9dbb6c43b3dff39a188d3ea851d5212d7cd2f812a390d
258	1	113	\\xc9e0e6b9798c8f9a66f7ccba1e930ebeebd356912aadc1fdadeeca3e3fc01a553ba2f8278ed6973aefeb70aad1c00a8104afb0e079ef617413b5a99f7bbb4109
259	1	64	\\x2d26a4f30947ba237d0144c65bca5692f6d12448c0662e53df503f98532cb3ca82d5d3231fe8dee304faa4f5296c4760bfce4125f80edf80831629745736550d
260	1	269	\\x25a27c5664e72417a655c26dd3f572c0ebc5a08e40039da7254147acf0865480bea31bf5125c2195a19f0f6df67a081e93cba020236686ab71f82106168cac08
261	1	314	\\x48e931e0e869f1e83c5a5475448ed4666dac331bec2687924cbc3cae72916b2f69a2900fad969f045c1bc4b3df2b97e65634faf17407324a8a00c868f6994603
262	1	177	\\xf9b94f43cde0762cf5061b2dac7f241fa782070199898c08b6a8c0fe512b89eb2a2bde0af9faab2ddd365819d070747d66bd672586a6c5d33b2155f8f066fc06
263	1	128	\\x2d3b930855021d42c88cdf809d9212dccb9e1253d36bc5acf0ed1bb667b14eb980b88c3725789d1fb7812086620530c879ea37c197f62b7c79eb6162fb0b9a04
264	1	366	\\x3fa250dffc51d1ce174c9bde88542761306f0a2a6b13126db37fe63b9239f158b13b00891ff28d86c8217037c6a869c4d38569f33822d9b72d094455f8841d0e
265	1	307	\\x94cf500f96fa0ea7ce82076d46d8a786a3b6e64837cf69f77eccd2a8bd9d57ceed8af481ff918d0f8e8512a5c7a8dcc98aa4579aba25a86d1a79020ae9621806
266	1	110	\\x8ba43d4b7f6c398463b32facad1657b9535267d6fa6a04ff9612744cedd23758472925af0f3ede5e768a56b7941ffb2565827af98b4939a4872c95f36cb58204
267	1	374	\\xa9d67970753111b7b3593bb5b3d0ac233e467476617531e346d50ac9ab49bf0097f30d2a7b9ca567f91834f63eb5cebfb082eff8a15d040fd3e84a4f6a976604
268	1	377	\\x3f4c20287dfc85a091c4c648cf29dfdc6121569387492755d345ab8ebaca0a345d5b38352ceebe9157056aaf397fc4920caf09dc997c4bcbcaaa5f5114993b09
269	1	384	\\x55fd2eeda4ded3af43857d7b7e0c9099af6db0d6d4973a38f033b3aaa4e765aada2004135018b9f23d8eb9eb149ae1ec5886265ea4a49028edda3acf894fa004
270	1	311	\\x5149cf80f6f53af0e5cfa4c4ecd2df6b525a8381b70f2d0936ca6e692a55447803fdd1e8950833f2effcf7c14b2ec050e7f5d9c312417223f3ae02a8922c8905
271	1	299	\\x98d9eae00a34e63f3e28d720597654ea27dc6465d04239fdbdb87da2977d919b0bad7cef0fb3089708649e8ebf4c09b3d3ab87a0f2af952a4542122078d8250c
272	1	218	\\xaa6338ce9ccf18e5c010b004256bc3fbc5a7f3848b12e4898fff4cff11c56c24e3b00c0b8ef847eb8377788ea2a1a3e5eed0daf0e2b568bb6bf666632e06af0c
273	1	27	\\xd471e66a60b27f946250de7badf00f5941c24cd0963a46bb42cdb0df2bc7075cfa3cc1715eb05992014f00cbf16fbae7c3c290fa1011d01958e4555df566fe09
274	1	109	\\xa2933b96dbd78587e2c93f9b859568de4bbddc05672354ebc267f6f2ec28b505d00c98cb580d5a18da1bc0f1c477accce417f1a7dacc6c330e670ead0f8a8b03
275	1	388	\\xf5b3b847b759eb8ac50d82dd9fd583115af292f4718b821222e922ab739e07d2d3ba76b12eefc9c142405d2adb3b8db0aeef81252d859696bf58727128b4900e
276	1	9	\\x0671d9a2bef843878db70bd7685e1d96293034bacc855699388c7e45d277db5a28dac8a7d3a69829cc33744f0f2b354a7249781fc231c684cd34f856ef477104
277	1	211	\\x16d251ae7725a13c8c807cb8038e7d392d2d5ffe0e594e2f4c2c6358d328a58d17e2e22ec65c4aef11c7820cf89ba4b21bac47ec61363e0cc3bd0e398a40d902
278	1	75	\\x97b45974f66804fc1cb71b5b80ac2917bfbfd38a1d7a5dfdfaa7a9c7933f2b503ff6877eaffdb9c0c9cd54b5066f374cd6c282041e02e19a26eb20aabafea309
279	1	52	\\x647c2e2f9fd14efe07c9d0f01fe49adf37fe07bdeb42aea920472ca1d9e37ac559427ce49579b3dc4d956811d921e37cc4a3e1af02f787dbd4d62f9e0a16b508
280	1	363	\\xcf193073bf68b96d4a253ce19b35e6dee8339b83d074997dcfb4bb3a25358f174fcc3b90adb9579e6baea46f3c14941596954fa6945c181a7d231ff75cc69c0a
281	1	60	\\x2f27e5c807eaf286d15e1aaa9beb622759a1f4c20ac4e0cdbe09c5e4dd0edf7c4201fe9bcc2966b407428bce439479870ffd233e2cc2dd7d0e89e25ff3cdcb01
282	1	346	\\x256c1447a6623f9dad5bbfee392e5d78b7c5767ad21459476d2480c97abc6a6a07874a5e17c54ee0c26b386bdd08a00850425211d7c9a09e0d7173025c5a0c0c
283	1	151	\\xf50c75dcaeb2bcb3086795bdf57bacbfba937f9390d5377c77487c0bab48cc0d02787b28fcfc7363d344062398f68ab05cadfb1cd601b73dd29cc43382543109
284	1	149	\\x7bc793728f136a3c6b695ef2c31b1106c2835e027636935a6187d76c1e6b7deec2343aa318759a3c1e1eca1112f271cd2e8125798c24e64f01a76b05e16b2a08
285	1	181	\\x5e14a756589de7ca179cdd30210ab9f6e66bd36c545045216c034e01024e781903decdeec3b4806d8201616c90cea6319ab91921cfff4acd68ba982df81a2209
286	1	276	\\xb3f4c1791502539536bd81212c68163318f9156fc401619faeb4a05bd1b44d8b258743171c8af673ea85e18f7cc7dff36a7383989ccb95dc056d1387b0311a00
287	1	169	\\xb10281050017d9f2637063d0c28947db070aa3c5f2eef78bda9553db5113818a3c1b6182c25cece2d7880d0ebbc784417790b21e13867ba36884b6e670ae760b
288	1	395	\\xf995f3f1f76a6b3c2625e89cdfa79163999c41bfd16059665577e2f76093da2b33e4103e8ce1ca6027cd7c78f3779be425f1ae122be23549ed45e5717542f006
289	1	389	\\xba9e221d4b2b80f151c80efd5f572566e0d2583811397e9ab638bb79a35dbdb97f29ed3ca6b361a5e3964cf9f9696fb67731c93e022e3d36c85ad57a525a9104
290	1	345	\\xd12680c83ce8482e88e9b1c88718848f94660dded2e2d17a034940fe6d9cf5f837085d3868efa6a7a0c765a4ffe45805856903b0970c70211fd2056df8041805
291	1	147	\\x42e035168b9e4df5ee1fa840c65eb0c2d87a170044a7f4e58c950953473ba778fbc5c84108a9300c783c94eb2db2b66877ad0f9d20a6916745750dc868d93505
292	1	10	\\xa251e710662631b8b6343bb0c54471b6c0958d51863687a398f94769083f9748730eb147816ea0c885ecc185c5609eea2cea5fc04e25b36bd81d8c581939c109
293	1	334	\\x9924b8d942152c078e210af1b54a6087c5b200fdc434def4d433867f7c0dab185801aae7f1a1282acd6bf2d8e10bfd39f84c5d40dca9e4553f0c6ca528193f02
294	1	193	\\xc95a37b733288b470831e5dbbf67ea4a078b04a78c5929b155f3360ef2570b2a60836c2c9baeb9f5a274b68f8790108b015627f6ca337038e316dab220857d03
295	1	24	\\x1a8609a52af5818c8c6b7b6dd292aa4dcc1c49c201e694b3c77c271d0481d59014d76e2e949ace17b6471cda29197cd69dc7fe58f589d2bc2c23c16835fbf304
296	1	25	\\xb4a37300a5ad7fb2516344e953bf28d44d81c5e64c97546fb063aea20cadf6df65a74a3e5005de292f7a2c291dff6bd48d7eca6418ce6517d2406101d457110b
297	1	290	\\x4508d6516ed5c805bfe4a8c6e081fa995e5bfab338cb8104a64ac974b1aa67f57b748a4ff3cb68b5c51745aa6d51bcb77ccf20294739fef12e8b3b23bf119709
298	1	178	\\xc8aeb3d889eb7ea80adf6197941f35df9bf3477b50acd4037ae3276d7b8de2c9c860274bc5da590481875f8926e15b3b3c0beef94807a6a4480785168449e604
299	1	183	\\x3038fe33adb232ec4e15f4feb1a754c1504fd86a2846c4794a96510add48616f4be04e0c1630e241a3233bed2f54b75e7d10a3314ed9158c648aab3b20965f05
300	1	160	\\xeda4e522097802c8816c8d8479119dc569aaef5dfac1930355d8cdefb589cc51f72b8d547f4da92fe616082fe15ead4ca204e1a2e8f43c06aa8c66bb8663890d
301	1	351	\\x304b07ba64ac6f7b78ba50e634ab439478faa4e2fe7dd2d1ee44205258f47ddea2c990fe0622dece1ae6e81d7a4e0936ecdabad56eab9fe7c2b01bb5edd0060c
302	1	127	\\xe615507d642fb46472530f65d708070c8411393319ef5e3cc988cfc4c7c1655ecc1f7cfc1ac623ee377e4cf658755449007fb0da0f5a198734f40a835218e20a
303	1	68	\\x65fbd0d8c1b9e83609eaeb9d9059e2a4bd2845e8d84afbfc249a9012564b4c13e1ea8b5ab68afebc76dd9d31e0babd21373e42eaf05cb7308554493b99c54a08
304	1	101	\\x02636b7bf329e114ac5bbbb3a4ceeccb8ad34798a2f91e95cc8da47d562ce832c3f4e618fc58e48a2f72d1c0dbdd07c0d7d7db92208ce97cc35a640b1fc6aa0c
305	1	47	\\x5eec4b8848b1dde7f5e89580f597943b4d4d96f6ec78e8c1b22c6793ba8e017428a003783c97adfa49c3b9c296c71bebd26ce742e4e34e91d12a6fc6062de008
306	1	187	\\xbdaeae8999374e0896bbd69faf5d84f1ff0f233c9f418c4b3259c082d28f6250dc70622a6b7ed48d5929e80acbc3e7746925a73d66970c895719763717ac4502
307	1	421	\\xd6808bee363c34578f63f71545a8f3f4cef6a39c45c5e877f3f6363860477390e7d7d7b9a4cb3ded3bd93934fc4d96373dcd6e9e259d04e579499d3be9c30704
308	1	77	\\x8aac87d7835e1884543d662030a582af7ea7f7349d744363ff92a6502c2e2ac436678b50bbe28e4e72648997631b55a560cda40bf7ff7c1a38e0544427ad7a01
309	1	208	\\x326cb181bcbba84fcb6118c0d5c99cb18acd44dc35402182d58cb76251df5f2c3e7ca6d25b63a4be85be8c0ceeb0bff68f5b6919fb6754e90d46ab2d5206cd08
310	1	67	\\x6ff7b3cb985e82e41ca1fe5bdef3cbe7dbaf38b7a59391cf8a626d8b141396175bfb95d2e5572641affb607d0d6231882bdde70ad49f075197db2da8cea59f04
311	1	188	\\xde6abd3c118c1b4cb681dd654b67b4688c0856aa5b0a4b55bfd4a6cdcb1affad8ed5677f5924a4b825e639f6c53cc16dcb75349c4a0e3f2de7afd7c5cfe15c00
312	1	229	\\x6a219e9e31782679bcfaa5a3a561347f1751205579659f4973dcae866e19f1e15920e0bfcf0f6765411e9d65cf1cb6cbf1f2c0dd3f98249020346810f1ded003
313	1	281	\\x87d290aadd7407fbd0966e90b75cf0552f6d0e13ffd2d12605f5395eb523b8c15d3ea6c4918916f6e75eaf78eac006e7d1c4626ab48437bf421527c881814b00
314	1	358	\\x66123d0087feb5e26f1f22f8fa683f88534ae4a7b3d853f4dcb960afa2b82e5fd81be8f271673a94de9e191c889ab17fd2bcb820d769b7ed60d477da2cf3b104
315	1	355	\\xcebc464e13d3c785d100bd3f727677ab40b1c9c7a59db73fc979bb26063bb339a1d434a8b631a917e521dbe5cc36b4d0c97f9a9369be7403abff8fd6349ec40d
316	1	105	\\x27c0ff19927cdb65f008e4506191bd72e85a89111da11a68f02487db3b782737e1624fd02566e87eb7a77bae6da273a52ca7db3ea60994a8466f582e64b3f306
317	1	327	\\xcd329cfe54497243100c8eee08a818ef05d6bba5c6e2ca86da57182e6dde9f85c7c070cd597a75548533c2132aeb60c20881a26f4ec27c8e68d4b2a113307e02
318	1	2	\\xd69cd65189ffc546e49095c22cfcdf3c629408662265c29406b19683f5c7517e6e4a50c5b71b729731e7bb8d0cec275ca73bb0cadd6cbd590ccb7c0adda59f0a
319	1	125	\\x945dd34adcc6202dee2952aa0bb18d588233914cce42dfdc9ba3d07882546eeff1d6d9c8f036d7665c6925d836a97716a568f075d4502fdbdfcb6ced3d928a0d
320	1	170	\\xf013ad64c5ac617f9e520af5e42998a9f46a1f7a403575b557d2d4edf4bd38c020a3220cdb81a2a4b2613c6463c49e609ab98c2b176eee5465c04e5f44d5500e
321	1	396	\\x163e55aef129ff5c9c82495e555d3a67d5723c8133bd7aad948ff6da0020ae5628fb7b9a535c474208ec9a7c60a7512d7a4a09c3f09d0fcaeb868681c7488301
322	1	1	\\x9fde58c1b3308e47ed477d355f9dd6574ddc22d8f182fcb4807173ecdcf1791b01fbbdeae1f933d856e11c216c914dcf4628f1821b9f8ee6fd96902b61d72d07
323	1	322	\\x87367ed33bd527f498d0529ba27cba0737729169e27ece998b29f9af4539a55a101f3b69d13c30a413011685547fcbd943028a609582befeab90a53936a08801
324	1	267	\\x3b60544c656d50b29d6c662f97f1f4d117c59438552279525cbd77681bec9f1814cbcbb1f14d1257385bf79e064b0a1c0a74561e7c45cfa46fc01b4836e6080c
325	1	200	\\x73beb208b235f8fd982e0e3d52c6a85c16eb9bd2c51f31aa449c10f181859f6d65c872d141e6f61c1d657102907189a5d3275a3c0f3f5132ab8b974944e69108
326	1	58	\\xb23614cfb5b409a9625c69a732f0b47489aa7f79b13b8e22214445cc6a502458e702d0dff12d649032e8e664022d7607459035fb2415b5b172257e729deb030c
327	1	270	\\xabf6559e24901c248b55c3b1751a8decba4355b06ad8b4734c5725810d5d51b5cd047b98800012a8bffd629d9376933fd22d991ea8929efe677801dceb94f002
328	1	400	\\x71fade9a9f2db3786321d001b1f7e7ff4766af72e083405ded1504df5f36b2e5e86906fa3ee335687216b26b8a6e89d271f70c21d2caae832e888b47af99e609
329	1	84	\\xb622d5b0e61c21d2656c34ee4478e9bfcc6fb7a572bbd09b0ad7d02b6f135fad56e03600801b319ada80cdbab949d0efbb5907576d0fde27d67271f79dbe1500
330	1	308	\\x61cfa1537976b0056faa3bd814c5df60dd60ae2a3a9a050737a1ade22c4ee3af5934905eb33ba39cdcd4948c04662fc4ae52082472954444ba201001286edb03
331	1	156	\\x72095f2f5cb36ff641731d3a0cf35354672a7b16d324ee71a3bda417af75621fa4fb19e5e22e86bc49852bde9615ac65aba6fed7a85661baaa06d907d9a59c09
332	1	390	\\x81a7136f2189ec7472bc81626cb3427083831ec9aea2a9a8ae79e703162a3f8cf4d3cfd7086d11eac7800367ab5561b0d4a73166d93a0c918cab882cd7f02d01
333	1	32	\\x442dd76b4d0f664d2d5b1cce2ac4ff01b7b9f76596d703726de5b46532c9511f7f7130b8712378c42afe221c3f7cb8c0b4b35f2a34a0724dbf14cbb8e21ba50c
334	1	5	\\x08201b65cbe07eda37865f4540fd75a17666db7496fcbc1acf39588871971c07ecb9d3a4f46a35d94b46b060f1c8924f29987cf99e53ae4b65d27e9bd1003c08
335	1	100	\\xaf96f617bfc435619d0926dff65d48a431dbe68740d32a36527be72fdc1d1e67fba3818c37bfa40bcac5ee9a0761bbcd38b0b0eda9ca0e51f85ea9775f2b3502
336	1	157	\\x6c3742973b7a4a9efff6641f75d81a717e4edbdc6186732d32d3c94baacaa8d90c57853f79e7062eb092ee918a3479438893309f35d0e5b168f5ec4a65114d09
337	1	43	\\xfe39ee547df8a8fbb8497887c9eab966754c782189298062ff9d75e90609f70141dcc43022effc8c51785372849f33375ba35331019f3b6430c1d4b6afc6f408
338	1	401	\\x476fa37ba98933998ee790a08624f6a933bb5d6bb6e47e8360f51401b58d8ab32e996a7e44d281e9b11cf2e1bd0649b6145f5426f0d773561593d390975ef40f
339	1	406	\\x52a01d6bf0d67bb1feaf74ad76e72eb66bb34b67a02057874b25656f11fb7beca1a37a0efab39e502a83dd16b2abcc344bc9a79a80c536a011ee1576788e0f0e
340	1	260	\\xce1498aa0131278d27488a3d951ee8bf0bfad32690e7e5c63b97d218be6ba6b507b89edcb0832097450a69998a1102077ca214c1b39ef3d1019ff45214c24903
341	1	251	\\xab037373e3dc5c5342a1bf4ec3833c148285ea50a25b98096a6786ddf780ae2c7aa3c2da15045420ea1718316d8e71e76d5dfbd1f28ecde1673911988ee7fa02
342	1	194	\\x159cd0a7a15ac8e971d14d3e6af9c5590f0d287cd59c1090ab753205d999f0a3d7cd66d951c083ba221ba4cc8634a663c7da4ef3389e8682571fbc3c78795c08
343	1	369	\\x8183a4be99226d0bc5e7d0382f66d7d3a9cef710c68cce5aa05698aa3b301af83e5ce13525ac65f642fe9cd7ce6567a52de98d6513460f7a395b547fbbd1800d
344	1	174	\\xeff47baa86abe1128f2a87dccda0b9518ead71b83a50f7472a708c6a0def1cb9580f752b4588db9729d0c5e825d6e0b0985c89715ca8a47f4f10dfd86793b60f
345	1	387	\\x0ba2618cc148a43dacc47b75e487be284c651bdcd866a5409cfd98d16071b87f1289d77c2c1d5247ff68c9c3e7ca298d72fb98c7b7b563e8a9aaa4d9c1c8b202
346	1	305	\\x19df5331bd80a2589e73176b05f4019bd414a89d677d6ee8982c520fa159b1f969e528f70d08bcc74afa3446285cfc0cd723155b69c688492eabbc9f393d3c0d
347	1	56	\\x7415ee9ff27c14e70d8f5dc98b7310879f8c63d82cbd49ea85caa1bb52a3dc5ed7185282d52698f6b5e3c5ecf5996f613b43894d85cec0d040880b9399311904
348	1	7	\\x859ddd6f8fda9813a998d4a370ba6328afbe389b1fd4996c401687c86cb706bb364c057eaf1437572c0a69cbb9c8f36f4fe126d518eab36a1694bdba43f3dc0e
349	1	239	\\xfe0a780694c91ce3333bd6910f9dcb1ad6b0e5a6b79c7946eea54cde55332baefb72d8a3da8249d7a066c43226181f7f2e3fec914d0c55db2ac3f6353db37407
350	1	136	\\x4b620bc1491dd09b3f279ee7eaba16e7193c2c19d472b382e1202e1ec534b4bdf00390cf8d8b0ce0ad2511a1d6b4d9dd3462dac0f83f232edc25d92b0b5f090b
351	1	402	\\x49995401d8aef70378a98100edc0f42adb9197e7a9506620ad9f1c71f5d4649ba23046696c3be7b4f16f98ce6452809fd4b91f8778317a494531b465bf381c0e
352	1	234	\\x793e171eacd197a427d9734053a8c476b7873a4c17218d091c6c64dbf93cd33fc3e2807fcc61a0e00e6bb7ac1a53c5686e67cc1ed23ce81ce82fe61c256abc06
353	1	11	\\x043ba1a70f8ae9f3b410ee4d15cd384074fb4a7529b5170d1ee1cc441479740161eaf2e4fad21c510c5f0d1a6009f8efbab06edeb875a55bb1de050db78c5d09
354	1	65	\\xf53ce9c7d82493f7ea4ff2b2ee48601377f07a1fb67dc7b92bf0d898da0a0fd2987376947ce274df584aae04327b9d5e48f9b9e9801468bad8ff29f443c1f60e
355	1	279	\\x8d197b8dc25ae6bb394f456689a3b7b00d2da12812c24915f89e34848203632c5cadaf362d2296ea57e7f3b64139fb148c228b53845924c175e717b3c44ab20e
356	1	258	\\xe0c235c2e70373e9c8b7abf15701125eecc3511551a1f25df111826e4df39539f762d7069e6c095d1a7b4508d2620ae397169afbc43c8dbc141343f379b90306
357	1	352	\\x07baf53af92984453d2282871175b06d0ba7430109f0cda30e19c3b3002d13049e92db2763c5d9bb5d7b62445eeea362f692f61aefd3cc856947a32454b48306
358	1	23	\\xa524767d5d0bc046c683c1def929c96bf29336ec8d8dd81d0004e9a343efdbb1a4e4565a3e3dba459b1d6dc78006bfd5b77665da99c1c02f51a1cfc490837100
359	1	83	\\x6d6d3fb9f88289eb7b0886cb22c8f20a26eba35bc2d574021319ffeb437d73936b6cda0c04cc5eaa27488ba2a484023d971a179207abd81939a4b3f821ccff0a
360	1	97	\\xeb6024a8a1e18a66a26fe21a6d5522e4ea72ff641d659b8da86f0298b9742adc852444381ae7a6fad123abc7ec78861076ae64d27f3f3a40a9eec6b4b0bf9c00
361	1	173	\\x34bea9de2640372419e9d87cff0eb6c6f26745452c7367f0d2c7f8963745d821a2d798e79ed315905aff944d5320292dde852a0a67a45ba4458aba26a384d10d
362	1	371	\\x13aa7a2f0f321af72360761c2b3507bfe27e63bc90645d14a9747900e1fb7a4e404f54a687d249ee9a4e890667ee0045af8467d12425f608647125b591166e00
363	1	202	\\xa1ac2deff87810940180ced7538205fdf534ff9cec3e4be4d160a144a83987c6e2a89641c0088ebc09960b178531ec52f9f51ed67ab317abb71bd46eec23ad0a
364	1	91	\\xd5a625e9f56c4372b15205505ffd5fa3bd70fa4416f8d14b77d5ab76db5ef49920559c329f81ee90fdeb04cc27f0e8c7cb0fae463ba31871f527e35f31583606
365	1	3	\\xa30cdba45e3e1ed10722639b1fb9e5a14118038ad4d6bf85981453104230b37acbb0491aa941ee712622453b9284c8694f57e57144091f7c9d63635c19048403
366	1	16	\\x00ef18ba4193211094951eaafc80521cb273737d7c212193222840c8e730a38efe2d2be1c89b3c5ec11702b149b4bae13a74f8d5fd045c57257c8cff013f1009
367	1	235	\\x8fd8683234ff3b005036b07b1b4cb26e757fe74686d1205a72247a5e7547db3129f438ac0ca66e8d4b129b649a8400b518d31a325dac441e3504158e139ea401
368	1	196	\\x165482181d66ff943e88e898acab35bd3653b0ab68d0b5e7a54f89026afe7a162ff88d262c97d94b5436cb880be27b08178d4b0b0bdb1337fa744fd424687808
369	1	297	\\x4dd0dc2a4a7cefa54cfc9433d0f145862479f4c147379fbb84171ec015fc49013916ab727600789998a9c6ef1822252d36791a9f793a68524b2c977f70d1e805
370	1	256	\\x93463462f3716c884c68a1d08734f5a91d59ca017cf79ee184b521130d6f92fd7305fc6d15947b3c13ff6ca4c00823a55cd3a378b81d6b5d71d66cae065f8201
371	1	238	\\x979adf4b28e54cfc0bfa71947d3ea7944cd07072aef1c8c14ab75b8f390fa7d32581c81e05d999a44ba795af605daca31c218d07e22d234f7cd9d578c288360f
372	1	135	\\x5ef51624a7205702452ef608a2c98fe65c5796ef56cda5f4a8777460397e6e141650d42f900593dae8c75fc29c9a897bb8c40c5eb24a947e65671f7f8514a10e
373	1	36	\\xc7a7db15f10e015c0db8f24aa589365ac55e31501f9f0be64450332e9391f1a9cd3b11987d0d227488e8e9987affa5540364234e37e1dd2d6cb21bf1afa59f02
374	1	88	\\xb16f8456926addf08f6b97fbabee84fd2f76f1411d3a99b547ab9d278cad4b9e213daf33cac545b389c900786cbad3ffd5a90973692ad30dcd49eb9f4fe1a504
375	1	275	\\x07a46c283df8cab8d5fccfe7987c3d0572ccd6deeebb2a2c58dc28aa4ad3d38304f7fa20dae4e39a3e31a0a96cb67070073ff3a3adb4d3c0ee2a80408c343900
376	1	243	\\xafa5f2bef6e7e95a08195b45a0e6268d289f5532e2eb3f8335e8c14933a4637ba79f6983f758cb67596f3a3c644955d865e845e14bc997417632b7ad882e0606
377	1	61	\\xd7e069812a348ce3d0850d9eea57289c45b2296a58bc85ec708d0fb17bc32aba9d58ab6b8e76202777bb1220d3e567d60f6e3d00d03f714dabff81f8fbb48f0b
378	1	141	\\x0e8c3b8303ecce9ebdf6bb4409d58f3a9733e2b20e78ffa3c36c248b5a75f8ba8951751ebaecfd0f2c16e95ab925c7aab3a445794bfbdad8ba799d1bbeda860e
379	1	209	\\xe72b41e64fae65cdf95f03ce7a57572f6c869698fbda3f9537e37b583cc7fc77e77bfa8b1172ef1e490a1383c07a96b55c082f9dbbb03c3cdddc0bad7bf95d02
380	1	304	\\x6a479a2e9264ef6ba81745c6d5ae58d23323fdef04afcf2234e92946c169305492bcdf767f420734921eaaa78bedf7e836ef52453f148192e73776eeb2570703
381	1	227	\\xd3a661816775e39fa304d51307c853dd6aee0c47704cbda194761cffeaf00050673e789cf464d7d7c35afe6ff1073e625ee5a4fb753c9bf8247e29f3a98cc109
382	1	17	\\x6ca5ef2898c41536f9ec72c6746344f003be1d7b677a902134a09d7bc5a82307f3a185e3c9aa2ed16b358512911069045785d779536c78482e61ce349ae34c00
383	1	278	\\x863712a2c726e3d4b90366d076650451e0ae5df9f16672f86c03237d8825c2a1182f4c82a366bc4418330703437aec3c2639e2740e315c61087e813551beb009
384	1	378	\\xa458ae0fbfbe6649ef7c0df9db26bbcf626185a71b1cd8ac3097744112dfa8150520a5eacf4eda711e26143cbfceef9edb0758742172f792324558d4287a6a0b
385	1	219	\\xcb1c1e58e5b39260e1e5622b274ca4fa5468a95f1905bf367a20b7d2617b4279b452196d1b011a774571bc6b9c63f2cccb74570c64f51e95c103cd2b12b9710a
386	1	336	\\x3f5a166b3f921c3ed24920648a1e0370cf5ed7ad03d52cdd7f2937008a766fbc62cc389d16ef1672dd4596d2fe9c27d0ac6ef5c9a3b6933feb5c47d273a1f405
387	1	221	\\xb9fdf713e47f07942ab28704c212e4b126b7047605905ce1c312338957fcc789fb16c27df81b053eced05ae50f5d8cdb1bc1c1a57fb2aa92db011eb2d09ff809
388	1	244	\\xb5641d76de623dc08003cb5d8bd683e27f1587bf75f465698b23eedae600fdff0cf48ff82bf123454d24fc9bb00c38a4f72555e656b23319c917e39a0cef9d07
389	1	54	\\xf9a4697a0a1f6e4f15a4e141a5f8786dc821304078cc9ac31d5abe2f3b8b0b457ef24b764cfeceb5843bcc5c24fbf9939d31e9f0b3b079b1b771e0d28355ea04
390	1	95	\\x80f9bc518c6d3b463beaf105b3a528f72293687a452a066de981d3a23af80780da597c4a87c74131f08c9538583476614690c3ee377015a77dc424d095fff201
391	1	22	\\xc4fca53e27c65c51f65193fa432d452e87f25c2868268e2ac4b7e4b33d368026877d6fde20b85101c8705cc53b9725d485c77ef7de0f217f277bb5ddbe7b760b
392	1	14	\\xd16da88e387776e0158a5ea9383ac3618f8a527a684ee980ba0967f302402d46e1d99403bc98fe69041869fc37141fa883b61b8784d0840b03469339180b540e
393	1	241	\\xd7d0438dbc7c89d1a79473f3abb47a361091fe9c293909af538d720c7769495c27efeed7658113f0b45bb653523f50e9c996ec4d7b10607b76edbed3cf84f009
394	1	201	\\x558ef9b92e95c1c3f43491aaa3c9779d0e8b3e85bd47191d9aba711403db24dafcfb42fdd099e2e5f65907a8cff07092be1e5228ab76c47639a0529ea035480e
395	1	145	\\xf0641fed07c024ca081eafd0e9bdc46c9a730025ccf3a04941aff48128895ed6f71764235b224583347624a5ac865a2fc1c8a2dbb757fa9b3255713bb6156d0c
396	1	224	\\xbae7eb648a592b995e0171a294556d934c19523bf82aa706ed7c6e0739433b39acf18e213367f7e988187f13179c24a937a2d89d0802b0609c5414b23f0bdd05
397	1	320	\\xcdee6a7a1b8755f9fd33716280037192b2bcca2e9142bf118bf5e3e97ade0b8b1c7a1600049295889296115f0d9f599e9231731c30ad2b56dd09e65d67ba7c0e
398	1	51	\\x9eea4d8480dd54c7d86a25fe7d04e6a203b65196876624059c8d8d257bbed56519db0a02eb1804c5fa2063a1fb3284e69c810d42bb3f52a754eaf5f995480c0e
399	1	69	\\xe5e36c4112df838a4af8e5301d0cadede061781411556381b81f6f556c2d594cb034fbbedf703b8e80814409b7d1dd63b7c1f9689cd3edb925f324e3c4306207
400	1	411	\\x99c7bb517749e38d520079c90ac3b2e12e8acf059e7d89339cb77c72b867f69006b2550bcaa7a5d20634bda4a0aa5b4954f932013533706c1053e96a0573610f
401	1	399	\\x95d0af0618793437360847b90ce7de018b4f36fd21dde2d84617dfd15d683294533f2d8cce5a674be4ccb3ca9ae0047b1d5b414ef46af9acc3ec2791e49ec905
402	1	416	\\x17dbf527390908ed42a36266c420c0d8f3f842a63ce33ef1fca63d50d26ca241423d902ab2e0791cfc4fbe7e790eada220ad160051d61af62b859dba7225720b
403	1	262	\\x783245a755f37e35f0766342e6496cec8912839bd2723e67bbb71aa7dd0fc8e206dd44c1194539c9434fbeca36f05bb7ef99ac81fc7a9aa01d557193dd0f560a
404	1	213	\\x1e66f068ba8592206c8ab5b8cfca0ade25036c9e99a6034f8b5c7416b2cccd4612175d5092e384ddb05e240560c2577cfc5fe699ed1d1474b8824def77429105
405	1	4	\\x21444994386d350046617492af45dae72a2feeab9988565ab53cb710db7c550c4c7c3762925fbdee259db79fd1a28ec28aa24e2ee7c179c603d0334eed47c00a
406	1	165	\\x22f0d74d06dc1b3ce621a01c3b0e6e6bd117c0deb33667f930e4e34d2904dbf6371eb6d2257661a220fbf2717e1e681ab0e8e9a12c717bfe1d8d67c80b3cd702
407	1	192	\\xa1a6b48706765aa06a6580530f813bdca5ff35707d438f95924a56ee29057486ef8ec6996ecc6e161a6733cea375b9425d2aa14abbddfd8cc1734d6a7d8c7a0e
408	1	19	\\x899e08fc30589ae57a960e79761fa67d432179241b273debbf4eb3c45b6abee6f1f6f633a887a71d89e0b2e1bf735fb94cda7144cf2c631856079d94b79ab500
409	1	140	\\x7543a0dcfddeef72a29397f97177db0c741a934d08985779ee22586c98d302182a9472f72ea1451c622a6de1c8514b66408af5ec13f5031227cb8b873f5dbb08
410	1	242	\\x62d58a6755c556841ca53437e628285ca1d8b0ab80c746dd4c76e30319483fc757bdfcc86837e36dbd3d23a344ec9d601282bf86ef909ffee46ecb4080083b0e
411	1	38	\\x415f9950947ccb83beb8f0b6fe075f6d82d13669dfe107e96823ae54902601ff07f0292c8d2793a6a44fa5146fa5f7a3e6a270c1f9e44a5cb9bb336f35f5ef09
412	1	383	\\x8bee76356f0b76b864652401335a66e13833c5727ff4d080934fb28e08364980c6b87ce4bd21fb699cfc103322b19f0e9e5d1a610a74189978d02e6d26338e05
413	1	89	\\x6d3b0040acf2e32959dc95e72d5a0181327a8c3bc4fce6412320836f4adc78d3484d8cfcd8daecc3cb8b888cdf18510083ce9ba32860e3866710106ef393a10a
414	1	99	\\xe6648f6fb51f32056b950b1eba2a8aab836dd1796b1c394a8900150563010de8f361f0244563a291cd1273e670e5d669cb27f7be941adbad0eb4e65480871700
415	1	204	\\x52c774d0a28c8e1299d12fe0fe4021876234498939d228ab5b329f721da935882c57588caa9fe7b25f94ce1ed8faae294954789fa2884efc41def04928c93b09
416	1	252	\\x537f134ab51f4c72a2dcea1892bb03a2a904abc1778f68826af3c6e008a0ed2437a2a1801ccf597267859c211368cc73dbe9b82b1b74e7c17f7231f57ba1c30b
417	1	240	\\xfa775697f9bb2e98de639840af14bad4132772a39a95476f76ea45e58961801e2da814a3ab9387606cd90249842a149c86db9ac9fb2e61fba9bea92fd535a406
418	1	247	\\xd9b95a73fd72d01352384bfa376ef71f0029054f9719905d042504d07775de4dcbb31c46a9031598b55ef769e7080fe00daf6ecded062634ffba86bc4380b800
419	1	96	\\xfb1107263925a872cc36fb68395af78cc31c727308cd0a47170bc1a95ca42e2b36c99c9b1fbf87efb44c08746524a5c9918a43f6cd2fc774ad4e02ff21af0305
420	1	172	\\xae284a6aac1763afbdbdf55f0fc3664ff338cb40864329307fd87f968969b74cf1d54d8c2f1ae36b966283aebd762b70cdb19dcbcbcfc9f8228ca64bf95e3a07
421	1	129	\\x8f8e6f0ca16233a372808af134f86e7a8a7d91ab58c8204eadcfeb2933108ed9bb13169b2f545a3dd5a60507c27a756b382d1d6b14827c60de5e65ecce541d06
422	1	8	\\x04501888f459901f326834de6336c165beb69cfd84fde8f0f0cf5c44f237adec63229fab344106e981179c4b42fd1c1dd1d63d8aaab5269af727deab9287f40a
423	1	410	\\xbcc5157d490e923ed746feecbeea14d070f6526d72d5d61d17611ee8a5681acecd4187e85ce9bb41137168e3edee1d321290ebe2c80fbd2aa016c6c55a18250e
424	1	130	\\x9228dd86d0cbfd0eec964f11a964955d1eef4ee0fc2b5162f480f40db29274212a35cb44b8c27323d4dd3e6060a5cad1200a9626f848fd40d031a631649e6d08
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
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	http://localhost:8081/
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
1	\\x93b7372d87ad8cd507f9169f6db9ffed6882377ce69cd7bc2a7cdc34fce3766f	TESTKUDOS Auditor	http://localhost:8083/	t	1630849897000000
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
1	pbkdf2_sha256$260000$o3MqaW7yRf1j5WzAv5uqhd$SblC/hdQt+HsCvDZ2U7akekEcr2P7CibIShTxi+R4ZU=	\N	f	Bank				f	t	2021-09-05 15:51:32.056774+02
3	pbkdf2_sha256$260000$rVzggBLXGX8E1AwWXaoKXE$A0Ip90/eI6+JTAwPzacI2pzlt1VYdWLNUQChAyoQpAo=	\N	f	blog				f	t	2021-09-05 15:51:32.243519+02
4	pbkdf2_sha256$260000$zDH09EC3ur9bMVlLc7kTAt$Ey0aeoeRR81a1yYRYUXNB3EuYyj+UbEOcFmvHUlQg5c=	\N	f	Tor				f	t	2021-09-05 15:51:32.336854+02
5	pbkdf2_sha256$260000$imKMTeTvtT8ti12MWlKXYR$Z01B5/TATb1ZhduAWqT1Tup4Ym5+n9vCrgqr1P8BlpA=	\N	f	GNUnet				f	t	2021-09-05 15:51:32.429807+02
6	pbkdf2_sha256$260000$awxecBqZm0X6SNv1x6jPme$DcmzjORUFpK3GFwgNbWfhTVIV06/HJfUHmOOyaZSbio=	\N	f	Taler				f	t	2021-09-05 15:51:32.522463+02
7	pbkdf2_sha256$260000$ezmTq2Lg4uYWahkWiU54VJ$B8Lmu5DeFVdRFQxkG2qo7zw7C4rHYJM2WuZr89LEWug=	\N	f	FSF				f	t	2021-09-05 15:51:32.61546+02
8	pbkdf2_sha256$260000$htHsj7pWIawPmChTFEMz80$wBSb2t1eBZGlt+Yjd2W8wFgWmvwvEtjrVEhvKVh90ss=	\N	f	Tutorial				f	t	2021-09-05 15:51:32.709012+02
9	pbkdf2_sha256$260000$Oi9TK5hyALq7gLz1gyZyeM$vc4wIMIp/s4BbvrjXYYIIpeEFuYypr2NabIMk29NpBY=	\N	f	Survey				f	t	2021-09-05 15:51:32.802829+02
10	pbkdf2_sha256$260000$KrXOO4581agIl4VwJ1ClUM$zfB79nLjdzpIARBGp4co6XvGIEeYGxtFQSrdMSwnKCE=	\N	f	42				f	t	2021-09-05 15:51:33.277712+02
11	pbkdf2_sha256$260000$vhdEBVUyJME21Pj5SRmzuR$1zKWnl1qHTu6jrrpQFV8THzZBnAAuIhW0c90y4dev/4=	\N	f	43				f	t	2021-09-05 15:51:33.754088+02
2	pbkdf2_sha256$260000$cXKez1EVbNHO2ORCN7mGtr$dp8mFQAqmQLHPVyHMir9F5G6zid9NCWgL8d7DFe+tso=	\N	f	Exchange				f	t	2021-09-05 15:51:32.151312+02
12	pbkdf2_sha256$260000$MqVYSEXYFZWY7yqLEmPbXI$y34Q0FdcejWUWHLt5QaWxGuVeVye9eK5+Q213Sfm8ig=	\N	f	testuser-e5NQTk6s				f	t	2021-09-05 15:51:39.336323+02
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
1	\\xcabc11838fb80a7dba9a5d6ddc612563cbddad48179f42c78362c0fdfe9bb9b82692a0324d6106916e3b3a281e7525c302c590f264744d1035065a3be8e0090e	247
2	\\x95437925326ace86bb8c323cb53ad55374771af3f54b3822228a8bb2b655bfd32dc4c24dca617e98728bda8e9737b56ff7e1b3996ac0a330cc1210df6f8d2100	89
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac, denominations_serial) FROM stdin;
\\x014c8ac74fe6388c417debf741de5c5e92f20b2ee5f86e0ee3b4ac721fbf8f20d4280d731601cea016d3d4b95b7597ad50cafa11d199506245bbc2915f51db6f	\\x00800003b8e07764a5d294dfa578dd285cc340f769d2ffa4440bae71a4e92c7b584802fe5180025f3bb88763395903bfef2551763282fa0a689df2ff51b2b93021ef0a29d9c8cd6426cc423ad7726bb9182e40e5f4a4a6d47a2bf8de6c0890361f970471649168ddd170bee1ad87e7915415f51f04e1f418ab69f79cc32caba1fdce5127010001	\\xf3090550f85be92007ba49fb0e79f030cf04ffd9177621bd19480e84e97a7285a29edbe04e03c25b0a7d44428b43220fa3a050400157cb7a2753b513abdea001	1638103891000000	1638708691000000	1701780691000000	1796388691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	1
\\x05389f978fea6ff910aeb3a737db0eb907cca1b71cbede004876d6ee40f529df2b9a0272440cbbe98f5779cb82338286f5c8b7bd0075a03f447e36a6c829b2e9	\\x00800003be3b3271c59f5e1f62d318403e6958073469511774056183f45e85f45a2fa9c58ef104d8a7012fe19aad9cf075e70a0ced97e22af87cef8c71d6842bb8e25dc48422f8b69b8198aff605545ac908a0c699be3842bfc21f030b5bcfd1f07909fbcb18c7b203c04410664412da5d29af174f76446e106091e8edc13c5f90ee79d5010001	\\x385924205369a2d4c98922bbc8c765a39e607002b6e84712b1d744318f82a273e765ecff9cf9ec84c3b9dd315a808cfc2c00d0554d00239c833e0cd1a06d5702	1638708391000000	1639313191000000	1702385191000000	1796993191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	2
\\x05d47e44bbbd981b2cee72547701fd8dd28a63075b328c19a284c3401a690ea32a316b20c1d46609b24bafe466c31c0cb5f2d4679525c6f19ee58c288b43f408	\\x00800003cf55ce6dad64e7408de26081074f33eee5caf928e21b3ad3dd60ac464061fab187317b7272a55aec7dff4842d2262aac323459268a2730169c58dfe07bb43e32c354e4e90aa12a1f5ffa876c669aa1eff7531b10530240bf52fdf43dd2934c4f54ced174c11095160feb9ee7f3f6f17b82139723b7a04e0d019c8da33ec73473010001	\\x787887ec8953f3f733e1c8316c09e1e8d40100d307410a5f6622eafc0a381c8584b6541b523f1619469308671dbd93d5bf3a0c996aab500e58af150269920609	1635081391000000	1635686191000000	1698758191000000	1793366191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	3
\\x06c8ec63f12b02142e5aefed7f2efa118dd11b07f62a0458118dd494e2f6c630e9bd44d24e3b62d7dce50695f657150356885fdbdf6d94f8511300c9079c3da2	\\x008000039f352aed2d612d8e93df8425e01da7b7f3b4f91624459b802754c63e7e6a0fb030c6f030cf77db436005ff09af1a7849a1f4ffe803733996f5c762b526c143464fee42c38bb2e3e886aa80bd3563353a62137865bfbed67fde21927f43bc9c298d167a3112b18777178a0adc44baa3d67e939842b28b72ce91a411ffbc34c095010001	\\xf25edfb7e3a070b964d6cea34417bebc37bf6a791bf585560886cdf64d70f8070b23b32882e3ce84cd576ceb4c22f59f5fced6729f48892ad902d57cb005c009	1632058891000000	1632663691000000	1695735691000000	1790343691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	4
\\x07bc9e6dfa0a22fdb5e8bceb34041d6d7c37ab75fec5fd2053a51ba88984ad343f52665b3c328a540acb87896767d4389bf1afe68a7a4ab784111b03bb491449	\\x008000039b3d64f11a70588c94f48aeaad417b8dff87ee654cc948542d0b1a450015892dfa8c24b31377ceae80d007229de5c3232555b702f711f5ff99f14df4d2c2a7d06bf1018272ea58609d21f17ee071df44a4e9c4e70fec2e341eaaf1e2cfdc170ff0b4a557742846be12654e2f18807cac18bc541b7746ac9a0995341d9581f9e9010001	\\x6f85b7d043737c77bd4cf75c6017910782c55228ed6392b73b0434b24329093a5e38c3cdfcbf3388a95fe6d3e26c68d6a79cbcdeacfc92454cbdbc1da7fca20f	1637499391000000	1638104191000000	1701176191000000	1795784191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	5
\\x08508428a4fbf81fb126cd06afe49345da8a6b4a0a81d3ecf08eaac277464f8123d1e2a52e8ae454a7cafec2d8ddad733b728f8ca5e8093c1594d069091441e0	\\x00800003d0feae420e8be2da8f1022b0c2494683d230b91bcd128679668f440a6f8a7220f9844e62c465b2f1a2f33e064473b13eb5a1895637740b24e7320c3468cf59ace62c18c1e7700ef27ea56d9b051d0810d74e17d35f09b92ce215708d6e797a9d334adaca0c44228d7e6d0ba5e4aaacb07b856ed333362e7007ebef4de9651473010001	\\xa15f57d6257b8f956a1b7775166e7554d1d648e2d20b85b216171ac46e6cecfd674e80f2fce3739997254640b73145f3ca0bf4a3bb2bfafad625df65d1ca0f0a	1660470391000000	1661075191000000	1724147191000000	1818755191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	6
\\x09e076545406206349cf120e0630b4878cac2a9676a644eb68a28a1508f6b08e8ce380f22942974ec90dde27ab4c3b47e6afdb656a68a61401717111db861c86	\\x00800003b682d04f673cce1c30f1164e4e34d27c07a4e784714cf4f427494e9ac59fcd885f909d24f1770f33f49a0e839b2d5acc8bdafdd6d0c2aa4a2b74745a9c2b71ca276f61c074fde9f009e28512883dfa14c34e2d80af7dd5dca3d81ff2af6b38c8a18cf39e0324c3c3f9185b7bd7013c1065e74835695f16fc328b26e738666b7d010001	\\x7a55afe3c6e8a266ab1159af22d4e333efc550ca0fa1b8d282d4b353cebcb6d0539312ea6d0c8acb75f47ee55c61f1000ac3c041fee51d2064a4c20a5617a30f	1636290391000000	1636895191000000	1699967191000000	1794575191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	7
\\x0a68e805dd3187b6a9e92ada4ef4cc1ed2fa9489c8efa67422ec2e8b7994b89c82b9161ceb09603715d3f379b31a49fa6e81ef64e227a4530aa33d3879c531d3	\\x00800003be6125be6ec5f52a0bd99d8a866d775b1e1df41a80e52700f07f1889c541d0d8bd559fa3f6a94a976a225a8f6e5d40c796a951f7be0e097694b71c177c9b4f9e11413e54d2423e0e6dd1cdac4991cbd2a27bee857e484a40f72ad0a229d7cd8e5a99ee5c81ef4192cc9c030940926518d8b031db43b94a2e820200b94259f1ef010001	\\x2f86bbe25ec8412a723a01f567f6ded8d761ffc93564931ddd2a24dfe5ba1a0454f2770be167c072b85141d898294eed12f2f51729524ee054a95064a3aa6f0b	1630849891000000	1631454691000000	1694526691000000	1789134691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	8
\\x0fc4a911b2df7cd3ff5736dd51c995b432e52c8c05e497afa274572ba55c15951e2dc9fdac60009296ae904a7df56c95bea92f39ce2f23377da9eeac33676236	\\x00800003ad5b180aec9fa60706168f9bd40160a38f1ed8cbd174501f908b5d0f463a505f9c35c69c43ce997677616d403d0a22f8361a125fbc03befc00257bb4975feb405324fa8ef8bfe4045ebe99a103a7229b80bdc8be20558f3ae539bf074e76ece67f205caa478aea4c9fa92b25293453c49964020fdc53b7d1e367e8e91f7c5dd5010001	\\xb60edd9f08876070433b5a0cfa4b4ebc34b899091778ca5a4a7d4a071c81644815b4bb811fa5fa1c7f66d6879e3abd1161e546b3c15a971c45c0af13e8603105	1641730891000000	1642335691000000	1705407691000000	1800015691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	9
\\x12ecbeeffc04c723e963d349e0d88e541a9e31297eca1d02660758f0ca66b29cb794570429628ea64fd71b6ebd6dcc7116ff70dd5488194ade3da2a7090e0cb5	\\x00800003c30c2a15c73e77fe0b2fb00afa0baca65e909033a19c7b9f9252e1268770726d6daed977ba66517da9d265a3a108b48a28f46fbec27748f1d6d0bb24355b9079d8670a9691a2c5a1ac793b30d53e361c480a2804bea3b544b12cda53e2f91f1ecab257c0be970be45f2b72e1113b644d29fe9925160a4be6191abb201c5c88cd010001	\\x2bf7df597a92d138eee7fb2b9cbd9b7976f6267aaa8268ee8979645681969383485c3c3773a52c1e45f62fcf7eb12408b1e80ad8c0bdf2689d9220c55ab89d0f	1640521891000000	1641126691000000	1704198691000000	1798806691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x13987c258ac2d85e13cf2fd970aefce9c08ca00c45cfc60015055904c8a1cfa87c9ae12857b0da308a0345b3e5d29055c9d27ddfdc8f5f5a83b76919860106bc	\\x00800003bbac2c492cead9315753c38bdce3b4d7cfaafde873dcff812071a09211010ec8e436625ceeba5a7774e22a8cbcdbb8d84a700958307d2b2519ebcc0ed897e0160e48b8022e900d7aeaf464e6c8c36b6889866aed202c11e5e2d38ac27054aacef8dc0d2546e5add65199fd99a82fd67c3105d526993da1aec58c864fea677b13010001	\\xaedc995f5db508329ada77dc8387ce01add8aa9da314bc668a5b685f1d4112bc4d3b39858e5e60e89f92dae73c36a0318e780fea802822b3ca8b9cc2274ecf00	1635685891000000	1636290691000000	1699362691000000	1793970691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	11
\\x2408b72d59dfd98ca8d54e6948b1533ed8950e47bc8d7ce83f8a1722ece792ac9aca5df404826c0a2ba9b4d19ed91a10bd68e12e79a3518bbe3108fc6bcbb0ce	\\x00800003e27ecb23ac1e543f69bd9be967d4e14e32b4b97fb174313431f2f85a8bb1cb2bf7e49e1ffa7af49c8983bd657d2f0bb3da7012f9b0dbb39e9f5915fd8f0289789f0645e952a335c54d0f13c960e23590c753e6d66d2a21dfbd86e512d5d940661bc023405219257299e859246135478db9917ce6d5c41d6347dec880d8de2f31010001	\\xef1c738f9d5306c7287e79842e8676879d40013161874337e727c809c1dc6ade8713fd8cb0bd7217dee240ab5f5a4262bfba326511b13ce3d30a5917da545809	1662283891000000	1662888691000000	1725960691000000	1820568691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	12
\\x2a604563ff7fa83f637c7d0d221364ec9858315955c37602d07aed574635a5db9661606e6e1905e39b1fc6e2ffe2a9d73512a4e64fbe0ebfcdb58c83bbaa7814	\\x00800003bb8195d7450a05422cacd9a745d1101f744bf186f7a153dc96bf88b0a837099df64ca01ecfc9171cd5f7c1c4fafa91f8155b8da74e03f2ca9dbc23196fdfffda51597a3999a5ae4ef496f7f82cc8a41ddc70aacca4ab35bc1097f18bb8087ac2b7d5a73b451cd2bfdbdcf962b362a37a446b72f2982250efb71a87891303c0f9010001	\\x7dd044fabc4d6b33f4ec83e36ea8f422b7f874c1e552071966d6304ad5a2f1229974d9d34e01eece3c3e8286f30f49abe33802e331dde595160b96d73a0d9107	1647775891000000	1648380691000000	1711452691000000	1806060691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	13
\\x2d7409bd226e0051cabd65e4290815fbfc8a112455542883ca3042c0a52e5b1eac99d60aedb8540c4c7a115aedc03606be4c2e3e7d94d14db4e630e8e3fde1c1	\\x00800003b8df82c4b813931b2383b1a3d48e17bbce9c1d8df7320ff561a0bbb77292d0b3ed786f820e6e6595a709e841512c00566d3debe456b26de4e33fc78ecc395d51aa440e7ffec36988f473f073a2c92db272857e43e6c42a65a6fdc67e51db7beb2ad672cf82569f1f43b9da15a2e9a8016748809207ab147cac736c165b2b64f1010001	\\x40de74e86ab01fb69763feb106faa423d461f3701fc51ea6b5c9d590cc36b14d747ff84cea63817402001db066ff20018ce301e174c952d71f2833e6b3413902	1633267891000000	1633872691000000	1696944691000000	1791552691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	14
\\x30207d2a582718a5dd09c6e33cf60d06acbd3b5b4776b212b05aa33a873b97c98b44cf62ff81814af7b2d693d5409988ab9d79bad19d2b42fe62b683bbdef739	\\x00800003c5a5d3d4b648d15685b0c4133ca4424800230086d186fadf48f1a32c69d32996f36a6407ca9a3751167fc4a96deab9f6f664e466539ee650fd3fd27944c30da889bcc8eff16370ceb36b0ca29e928e853ecec882744b89c53ea0078964013fd46bdc7b398846ec1b4812f90b84b13164623a5c1081252ff5a8c4aaf39bcd4561010001	\\x439d00f9546ab578cc510a2aa283537329a3b1977956a1913705648b0e1cbfccc3ffccaac3fbc6577ba680dd76e5938f37d0c8d9b22e4a007fdb8a5e049d040b	1648984891000000	1649589691000000	1712661691000000	1807269691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	15
\\x314cce1cb5b75ca3d89dc0bea8c3d7d40e3b3fdf3b97a1ea1e8d1c83a5050f5660977c9e80f9621b4ea583ec6c48b29a89dcb02fe6b500ad8f04c77702e11ba2	\\x00800003a4b66aa8fc87b1a205b42f0f90cc7db90bbb248b763ebb087e15832c192df0dec64399053fa40d06d985297d7061c24125393047c1a847b13cab5c281b00d6ed03d2e5f0a7cc40ac16f47f67ae30765bf408e3abae61ca6d7abdc44bec5e93d3f2c4f0d9c82504e1806176f77bd90d1047307fb3b2aa2b09de59efaec00b969b010001	\\x0dc118a63154d0f479273aaf7675c04b974854ac19c58ac38fc2c5e413183a86026cb39e74855150d462604ea1dd24ec5f4426b3741198dc61d6ae9199f76104	1635081391000000	1635686191000000	1698758191000000	1793366191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	16
\\x33b4df6f81c6d4a948bac6194ca4ad8e7ebf674d589a50c1aec941bae2ad2240c0a2d6e5687923547391d8b3fb66e81ec496f8591832c9dad2189f3bfd77b6a7	\\x00800003c76302d54795b1a1ac2bf3a7251c8983c26be2ee22f37ff1e4b79024655c0a1c33879c87bcef5f62754bb3fe4697a4e201a4dd321f68507b5156105c7efd7f275a949f63bfc6e7f232bfae6ed0e2cd11a84ab71bf46ea521246532efcb26213d7c50b6337fff56b94da7d931f10dc246190ac4e20454348faec650c0b09cfcd3010001	\\x700addb3a05bfcfa55381c91e9ac9cdf1c68a5cca3d9bfab59ea8e60e85e54ecf7a0bfa61d6c76d21f5ecee5380133531122d82139f01c46fbc77b3cf9007d0a	1633872391000000	1634477191000000	1697549191000000	1792157191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x3468b615d2c195f36f3f8976f6d8287d99108881a60a15a2d3ea62ffbfdf41604a1032bff29a927ea0e7c039b9b97f16d1e07382291dd2ddeac9a5e3e5e576c5	\\x00800003aa13186d359556b240a3c11afa76431371057c8fe8c06bfda2392ce5b8ad233501d759ea19880d83f9a83b81fab535262426737086174e1855305298c7e15276393dd53d9b9b185f70c4fc49759739d46835e0ee619713d3df089ec7c19d27ae88d6b339bf8d32ecacd552e95bf42a2310102551eacbf84f820721c286909391010001	\\xf91238884d530f620ee78e68404597338426e01e9405d208189ef26206dc3ae4a4ae2e8745291646694666bdcaf2839dd65c05fc1333328587b5e320eb78aa06	1647171391000000	1647776191000000	1710848191000000	1805456191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	18
\\x3720e05ba99db7d672bdd8851323277db63d01bef7af018d9fbccec37859b2fa8ba81926be4e250f5d037d65a0ae4ea788d3a23a7de1c38bccbd6d886ad6f1b7	\\x00800003b1668f6d18116eb136c66440a56c392621c5d3c7cf095d826b0105980ea6f4776510b5bd4cb40fc7e98f42a833775253e1477aee0efbc76b134f70066d30df2162872d1cf9ea9555e7a99f4393bc90dfe4df41e840ed8f7d04d1f1b5127e0e4f884b087105e24670e7eaaa2291c0bc5eb8ac79abb2f5afd116446042fb97181b010001	\\x9987cb8fdf4c41fe97b44dc41d3d35a588a2d88f05ec19e8a05c0007a698b6c92a27c2653c54999640fb9ac1c6208ea098024b86743696c615132040b7c9f707	1632058891000000	1632663691000000	1695735691000000	1790343691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	19
\\x373494009e8948429a35d9c8d392e8e2441d06f0adffb6269449e5d82898a9bf2a9d30ca859930be14c668e7fba0c738ba7741b8668c08112eff7105b9dc4d57	\\x00800003d24ecb32ba72ee278c9837885cb41e326617b4a556421a6e96c55130195098575764f89cde6d699815c968615b9770271043df102ebaf521415b0c98d809e4a4adc47618abd3b4d111d46ecf5a3139a4f06aa2fb7a8e9223ba84caeb7eebb2547124c717788533afd5c699fca9d7b00910b73f855cd14c72162e6ced15493f91010001	\\xcfee3e32aa3acaae9de9fed954a0d6d9ce39cded4db74483795956eb5cd5981d2a0c2ba97adac276d79fa97f15f963b218b0a0e53953c823c6d60489953aff09	1661679391000000	1662284191000000	1725356191000000	1819964191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	20
\\x3758860657d7435d2eac1935e970887b2c87df23ceb84259e668c3e4a8a3564ae46b55bfc0ab20986bfd16426ff1245fd34ce597fac0d03d1fc3d18588b27f57	\\x00800003c4aa579462cd96d4feeddebcda81fcb79bbfd7e89d58df98dfaa7b500d6a5c442fad5a80edfceacb1f19215c543513a709c8066d5c7a7dc84ed914f23aabbef62af6f2b09cf150cfb4a29917dba21d227293babffb865891765690a2a0b9c72ce362b34f4101bf10fe7b398b273692043baa7b21677d69ca7708df53bcd44fcb010001	\\xbe18a90b433ffa8aacb9ae29f0550537ff4efe5d60898f08f5db6d53f05efa10d443c1f56216e182075db234fc881598a5b1d4eb62df864c9a6eb3619d77f80f	1658052391000000	1658657191000000	1721729191000000	1816337191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	21
\\x384c1f9773103970eadbab72f1d7f511e66af219ce595755fb8c623c102c92379eacfcd47a0ada179bcd1bd1686ab0d1073e14178f88cd5d8544ae53217a9617	\\x00800003bbfa27af560daea59de30f8f89cbe1c5fad1ef9c23695478db7e624560bae0068be69bd588b5d01574b573861ffcd9ab74db852675348f78b698bccf2a6dd81c44a8338b6798aea6cb768b24ac922cae7b2f51d789e2043706cb6d4945386f1a38f5f06dd45f3f31531ee9424b869e9f3418c5b1b4720fa87119838754c31dc3010001	\\x93eabff6bd3caeacdf7f48e453fc71abd3db3b27b77c9dd2ccd260647321cc22a99e70428c1c9b4f8e2ed225bcc8c8260c7abaa2a11a466bae5bd4f09ed2bf0f	1633267891000000	1633872691000000	1696944691000000	1791552691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x3af8d6c3772b1d72640d5339aafc7f2c1b73508404faf77cc4e3a723de7619b0ef36d8b09e6da58af042cb1258509ad579f7e7ba9eb6c6f73adaabc1d9c0f3d6	\\x00800003ec9c19e18d57fa0cb9a2d3586604817a23673635057305bd01b5f0b3b68d4e5302d9dbd25211d87107c6777fa3f5ab409ec139ecc02dc4c86a34751765dbdd895c539afc292fdc0718e4257750e1025aa3c23e49495302a40419c7a1db32d7297e9b68f782e0a7eb05dde06beaea7962befbb0e32abefa8b79c87614b3c0a1d9010001	\\x9dc9ccfca5da038f2547a0f37a3830b31526d278599ebce1ccdf424fe7c1e78f57ce21bd8013ff9cfb7cdf35c9cdc693338ade0b1b5566950be6cd5c3ee4450e	1635685891000000	1636290691000000	1699362691000000	1793970691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	23
\\x3f7cd544801f690a03a6929e756554c8d8a58751dfb706f71519b141c7373b7dc18fa118310c335c46df780a0de053918959f398b1616d0e3ce12cd1bb35f0ea	\\x00800003af25c6d46b081af13bc7c2ebe8848d930a97ec2317c14753a40b3130168424db4c456542ab418736212c2a6d969bc7bac6219041ff745ff6a937c45cdc15bdb55386675244799b126e1bc18ea2394463b9564e54856ff857360584fc6f5479250a39d97176b65476e6c194b91abb324e542fc49a765aaa1755da11c530209f4f010001	\\x9a2c3711e0d22ea8ffe61b48a47a919655fb4e224d19c1d99879e66f405c2fad888522ef900741b5b4e19a187fe43dba9714a098a6ec6dc3597117a76505ed0d	1640521891000000	1641126691000000	1704198691000000	1798806691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	24
\\x44d0abfb74d47e440a2847f05422b6171ab1b1ac2b1aa9d4b1eb0cce20378d4a6507bcaa33b494d681d5a37476b9af210140a2f1e9f219d8d079a21244fcad98	\\x00800003ac46f399857a79d9536b0d816a7935bf808e35a35bff5e9a924592b64fab665e6df7046920fc7fe1d2737225232966fbe2ef62455cb4fb8e2eb05673e31f71631e1ec5afd1cb248a494e78a7d831d00007d6fa912ca54fbf8ae986db6c52894c9eb0c4264cae6dfdc48948c55b0c3af096679179349f426d5ad4d3b2c8d656f3010001	\\xacb0d2c15ff5b0a670caaf4f54749f7a651c3adf965b8d815a748010bb4f700074c387e757e9c1fffa3337e2f53f9431b1ba2f1412d82994c4ab26917985400f	1640521891000000	1641126691000000	1704198691000000	1798806691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	25
\\x44406bd467405364adf3cd8876d986ac8934f703ce239ebcfcdfa4c470d5bd4d905bc79078a4375faa50926075e8a03cbf3be09d178ac89a2e47d7990ac3cc14	\\x00800003ca5e06b29a29779a224ee70928b084e7befd45f4bb872836ac4e93a10b313efd3591bc148121aeb518981429926f019227e92ec6b783f5b405cf6c32ed1de172de56fd7857cc111258a7d935a641d8300b06e43ea933a06f3464133fd0a8e7d0e406502f7fa516b04ba5add71f02b7a784e95fc3e51ec22d24cfc2c7c5c50703010001	\\x326d0f60cd378112a83e3050bb4e35f110355af3a68d3431e630236d0a9477b75f8ff4a81069df6499ffddb096e836956a5d305e345020af9db72b276942590e	1648984891000000	1649589691000000	1712661691000000	1807269691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	26
\\x4578e37f7926e2ae96cbd6b9cb40fdecf01cda840c7da404d779b3f30b63a2494998d361ee2b458bed7e1b69a7d690085dfbb39b66a07ec575b63dc9df4b3f28	\\x00800003c6b35034030bea32984fda137c85687dd12e24dbb5498155ca40c51d918698275b9763d43402c109cef0dcb83ec7ee7d8c3b357a05c6c3040ad1e1c9384ec346235d4b99e81f05274df51c0943780e697dad7cf51bf6dc69c4e41a1031856677450146323ab0c888212f6cb9990d0e0218cf7186c3a91ec19d3bf1d844254f21010001	\\xe0059bf2277c6b37bc5253f59c6ed86fc8774541ddd2e580c461c24a70ad5a0b98c73d3cd7b1928a4e59edbdcb9efaabb0619d83396c8f6682052e495210840c	1641730891000000	1642335691000000	1705407691000000	1800015691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	27
\\x46e4ab128c1c63e851d338d7799562a239e3d7b6081a2c144979fd4c324635e1cb26c49e7e333ecc4b70da71524008a31bcdd1350f623aab8565caa2d13e952c	\\x00800003b64695e83ff39183422147fb89e1f83252fbcd1280e48ee82008d43568c5422f898b9dea8fcff975155e9986e5476527906cb70d9cdc87ce222cec02ea2d4d6d023483ac72fa23ab289f572eecdb31d9f006ceab46e2b43f746322c7697b4dcbd9cef49e6c5a0ed907c15c5f08c8df878b5ff9bf029460afa21e51b63a40dc9f010001	\\x1d12cb9cbfa2b2c039723e46208edac17a862b447dd7e7c97041d89ad0872bcf836fc24fc79f25d838e9938845fcf456fd57d0d78c29d92e58752eba653a0205	1661679391000000	1662284191000000	1725356191000000	1819964191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	28
\\x4d2811427754c052ae30d88b08397692ad25384d5ff202902bf63405d8bfc78e35a7bdfe086e48e85ebbe42fac3692c20418ff35e50521fc60398dbe0d8547e8	\\x00800003b41a57267a9be4220514d88187e38851d66eb6bf7a25343904ad23877a2917ca9f29ac74450b995c8471cfe69bd861ce3c44401f53c7fdb2d7e66c1698cc8bd2bfecae9eef7aac82a140106063fc9f52a28d8a1d346863b22b82c12daeaaa35251a84d6f0d48f8bdd451fc65f879ac10d72518fbe9d35bbf5dd0fe7ef2ec85cf010001	\\x8a25d65693c7d5e9320ddefe14002b8b0bae6a0778c56079cb299b414d2f0738aa849e131473c7da7582173aa6f7d61e5fce0faade3d75c42a7027a6cae6230f	1649589391000000	1650194191000000	1713266191000000	1807874191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	29
\\x4eac1340b61cffd10cf2be7b234716fab6f3b890d0465ba09b944add79997a69e9fb23abf314a8ee73d3e07637c89efd72f2b597c8ee0b5fc89a664c94e15e63	\\x00800003b9d8ff90f2bd2010e164b8a91888edd14cdec66e51c38464281205cdf21b10eab9193fc5c6ecd0f48a378b3ed436b8ee13870eba06af1a49a2b6da60bed45af001206ca1f4ce3bdfb854da10b88b0d1d37fb591add0c055834e8bbabc128b34722c47a1b4185d3eabd2243447ac85b46ba6179c5ea08165915aa48d84db8f797010001	\\xb7d3d08fb0ebcebd99230521993eb907e5ad226ccdc208847296ca7e09badb81a566fb4b2c304172b27e8ebdfcb90dd87a585b975f4164df628380a337f8340d	1661679391000000	1662284191000000	1725356191000000	1819964191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	30
\\x4e48cead2d2ed69e539080b6d5fbf46de6b0af3dc19ac4997d8a2b5b975997c75572c78ae4ed13ba8ec4c584ebdc24ab373f831795e9b22e35f57555f14f319c	\\x00800003c5f28810aacb1891d823c930283f29843ed77a60100e727b1d4846c0ac12c8e189b297b20e6997a68b600fc57fbee0f78dfc522d19f828ae1eed3d2cf3e74ba2092d1641c65f05c7bef56275047a868b74728c502146e51385bea0eadf4f6b9a43976b51ea312f56f8d4a3fe66e3a02fd74f78e15ea5abd2d50736edea9c374b010001	\\x9b5b5165c2899b2c1afa16d92168a774ed31305ae881424fa1e3dc71d4dc309a804f6e801fc8fb39ba07d550a5c2f9886b3bb366479b3bcabb4d0186a996440f	1646566891000000	1647171691000000	1710243691000000	1804851691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	31
\\x502001b8bfe17c4a25828b472f12a59da5568d12e9542ca654c0a2b1db3bd95e9c3d7fa151cee2f7acece610fee3245f84223016f868b4582210d22d31926c03	\\x00800003b25d17c48f598fccb41b72910edfb5c2a5b0ceffc670eb7d181092b4f848d3fe91e72be6b938a4f4e59bb85a750e09fdcaa8bd7990c6c7325c7d72b77c88684c9db75a2692ef1d90c0e3dd1f45aebdb2132cbd9f774d74912396cfa2de11af3f887ee6e14821c1b5c9f6c1f14e71baf8f2f5693cde4ba5f8ba0c76dca2fdfacb010001	\\x7e4e83ffd994cb482d8c641d430801febc6d0cb1a06189f29c313c84a3cde4c93da5d2dcb7b8d1581823f1d6b6b4fbd4207d55e2d361d1ea1ce8822eeb141603	1637499391000000	1638104191000000	1701176191000000	1795784191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	32
\\x501c4d45dc4ea01b4c0fb05bbce28c9f52d58536f1eb87fa9410a90727a6651000036b4ae5c6fc638c60f6af79201100be87ef82e3a6e0741c7333b0faf40ad4	\\x00800003b3e096b020d553c75d2eb4ffefd3cfe01fc9c506dab0b9d78efb9a1912d2f642f6629feb230d93a7c36cbff9f89349bf07b98ee9bb3e00ec95c03b30d33ebc526f4569a9ad59a0298a14797a6aa3c0046c4910472ece4e37da957879007759184c3c48edc576ed6de01669eebb02b0740e4b9eb66b38ee718d4a01262c44511b010001	\\x9b789b36825f08c63ea84fb6cdba084856c7e467fb26e34ffc070c0109f7f507737d6426004d719f93913f36ff643218be323b2d64761bbf6e8c5a23ddad4406	1650798391000000	1651403191000000	1714475191000000	1809083191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	33
\\x50c43fb5da2cb152825dc0e5b99ae8093de348de3f6c89e564d8a557a7c1b4528317cd2d5918b2d3bfe680a6a721388f210534b23f3a973e2d14e2009dc59005	\\x00800003be0b6bb4a190c2045bf5056dcceb97fa2562d259b4ca4b0b33710ad05ddfdade71a37f038696db6dd3c5d29d4cc415a503fe1fcbc693852a82e9c2ee6fb300a48c09236499d976b1e7fdbfd9c14f56b8b2e2a1283d9abc1944c206eac449a2951f68a3d9defa65b881f8250c3cfcd60f3349c60b6e073337ef94bbc1828c438f010001	\\x73ba17b77c80fe86901da9b53ce17924f11fb749c0e469aa1cc12a254f503688392d14ffa0bd5a66f824348c64fc00e8dd69ab0d8f81e5a9f95445c9accafb01	1644753391000000	1645358191000000	1708430191000000	1803038191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	34
\\x54ac81881633fef147ec6c72d29118defa52c5f94dc5263a56d893fa7393e91f66e33b3bfb0432dd449ceb3791a87e05ce5adbe235f4915022b41a71b2550e3f	\\x00800003a473310b031ed96cc0e37f89040cdb42933919ccb4b909e073cfc5db0d23e44fa545c96a8a7a9d24ff68f41cac96a7949564ed082c38d6cfb2e8647390f0fff1f5db0d65b35122cc66f1eb8e53004bdd979b7c21b80100b175b75d338a62c76be5c0b8622c4fd50610ec99e498bfc8fe16b1a06dd9e4480cdeab6b746da41547010001	\\xf138ff2c6436885fca7bddc3d83090a1a11d67d1448554b6cafcbc4860caeec7d758a01a377b9edc8948b1cf44ec7479a32425b355b563ee005bf47d5d67000c	1662283891000000	1662888691000000	1725960691000000	1820568691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	35
\\x55e8c98ea2bb9329e41205ddf71c3bd0425695ca4005d24f0ba1e3cd183264aeb2b522c278d8856460c14e24ba3b337674d1e16bb9772bf286020bb651dd2f4a	\\x00800003bf79a45cc06c8c873a74da7a6779e17c3e939ec7bc580d0a1231123218b5f9aaf486e95a22c0305d99ebbeab767fd001fbb04ce94b8ce71983814a0ec7b1866e47699d1e6e81422106112341b14cab581d5942fd39fd5bcae00d1e1197b56a8be5337866282f32d472cb1ec0991a56e2bfcd0f137535c455ddb0e727da6c1e25010001	\\x6923981b6c6c6b2dd7bf32facb4b35ce3bf73fd1c02fcb8daf86895247842d001e25527deb345b5b7995498891668af9f4f483cfefa7294616231ee820fb8908	1634476891000000	1635081691000000	1698153691000000	1792761691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x57ec9cb820625f7d6a3c91f06ed8d92fa980b00ac54f3b85641aef89020a787d8168c350e54a7962e810a53bc0dd72f324ff465a8140029ab1d68c4a678b58cc	\\x00800003a96c87e791450954c0feddf9e768d32dace27776973e51b5cd02f923e17447f426b2fad44a93faf0d8ca89365fc6a2339a45b75950bc892deec9e6f8e52f678baaf05c9e29b169c594ce92c2bf68f8d75a6a34f13e9734d6bc22375d6b1a0a9f3cf277cbf74e83ba5889e1c869a2d62eda14086bf4174add6a650d98062bf4d3010001	\\xf6fd2d1a05ae78c3e74531f3b0560cc1cb9dffbb7ae85d52f7f00e76c664de52c41392c7781d55d31801f447a2471fbdcdf7f9c9ad53792a8cd6d8799c16250e	1655029891000000	1655634691000000	1718706691000000	1813314691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	37
\\x5890a9115369470b076fc932eeba781f525e73d7baf257c79a34c6ee6d8f07e458b985ecaa20cb7c441db32b43c510e8f1591c9d89c182c7afef36dc831ebe4c	\\x00800003b430e96a52ff2618e3cac6452debfc3f5eea67a3f8efe80f096941786ef5410844077881e2e7bbbbef86cea40e67c79645829d85c9d5eaf4ae7d9776e30a1205e70514b6b41c2985d0af12cc7449689253abdef073734346599ba42931fa28c2fa3364051d62663a222cbe9210a83fb816d74e7012bb2d97be7059808412c2dd010001	\\x86847461fc7d72376c8f4e9db8a2f7f93b105e20144dda6ee380fea9c24b430d6aeb6f7eae56183b1753593fab702bc43009edcb9360ffbaedaceb6ca32c6e0d	1631454391000000	1632059191000000	1695131191000000	1789739191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	38
\\x5984292497f5502378256e58632f146170b3076f9c82e120a4e08cd9da720731ee56a92e7f6cb5ceabb3491ca5d1e58e4446c93df4a09dd94be0a440aa7a2d4e	\\x00800003b224b02abb5d811b40c8cb2b59c485f396fe4564190ceba0acc5f15ec971f5999f681e3c490e4fe89568a06433c76f492739fc0b61aae84a7773d1039329bfb384305d27c17eb74366d75134090343cb71b2f574789c9299b5343c7b7c995843a24036e7876fd91a0c263e8978f0d13eeefa4421a0b630dd3bd23ac87a76a1f7010001	\\xb41ce5c5bcfe65fb525268a2f3c5272ec032b23f63d0f919095c3deccccc82b3a50873ffd0955f58f1029cafd06ace24a1509241225216aca9d7232fc4f53502	1658656891000000	1659261691000000	1722333691000000	1816941691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	39
\\x59a4a58441aeff82bacc2c8eaafb2bf42d255f186be74f095a1d615d9be63fd1369cb0fe515dbf4280b11286f27714108067c03701b82aefc6008f2d664f4f2b	\\x00800003b3bc1b45609bfdb96fdced207266da3551c871bbd01810eab2b6f8c0f59ba7e2d51820e3ba001a26f08e173e372d7bc3e9b59eeb11b79fb1d7b8d51a37c53041249edf9d56bd9d395996f2c0aad3efcd0435fdcedf9793e27dada0a2a77a35ff874d7e6fda6ed6c6d6f044f35841309f7eea5bad6005b4fbe4f4d2bde995a745010001	\\x30cfb7e567d5c2cbbc7643699b896c90f12f963739294cb3e584eb6005935c50adcb22eba8354beca9279be55eb28b09f14a8aae2a486d9390860367b0f9da0f	1644753391000000	1645358191000000	1708430191000000	1803038191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	40
\\x5b10a81f47546a8f9bc3b3efb348d6215ab339084b3e892515ab9fea64cb82fd8296ad198bca2ea06e0902436d51c6b6030f62f463a154965286893fbd9ede63	\\x00800003b173cdfb083d2ae9d7588900d22717ec0451e68c92473b4ecc91dae8819133a7b3b37baecd87ec0f0347953b6161bc1c20b9efad1f19ac03cc571729afb05fd0c8f8d9dfb4123a8cac498d7a4a7d94f79bbe1f9746600e8ce6c78236c70feee49495864a84cbeabdd02816eb756391b27cc03bdaa8848aec72c9174778b0245f010001	\\x1cf099d0de13df3a1b927c54e569f85834938474199a80c96332e21612a60fd63475d080474dfd6f3cb8385a64ec97680fc50c9e4c13cb830f0fc4afc6594a06	1655029891000000	1655634691000000	1718706691000000	1813314691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	41
\\x5d9847ec88f1aff1b2146c40bded031dd43b86fb1898b0a846fa2803487edf819fb6b97d156da415cc4794e1dd623f6eb9caea91b5f8ff753dfb410636e457ce	\\x00800003bedd7af7d04e8aa53cddd6b3eb46bec8aa0897b8812e610404c796075553a2ee0cd8636948d53f4779cde3820999a41cb8147ae729536dada42ebb75166682c057034c9f3e40c6381a169e2de35de331bac6e86280ef08868c9a7e8b53663fee963b444cd89bd96513984efb28c3cd7bc41a3c7f272b12dbd8995eaf067097eb010001	\\x075df87ca67c4eab51cf7ebde35c628762b1d2ee75bc27933eff746327eac7e3babf2b7e1abc8f4fe373d2c6280cfd4ce11f800f797d013c8797f307ca3fd208	1650193891000000	1650798691000000	1713870691000000	1808478691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	42
\\x6024e28ee6451fa254ff5fe67e425523e8cb76b3b63321b859ea3d8311d23ded409e56779f3d0a090b5add8e60bdba6c3ddbecb9ed952b00e7ac477717632444	\\x00800003c6438bfdb0fadf0c791cb7c9ae312daa47265e964a33a02b06fcb9820101a3d10891773f451bfa35b2070320cd77c07ea5060489fe6bb112d746c4946eb4cb493b9e24c635e09518ab1b80f6bc81694182947dcb322b0497e17d8664319a655f8dbc46050ff9f9d4e1e1fad3bdc4e797b56141ef7fde0a5f78b2486e9d82237b010001	\\xf2ed13c1bba62b4e4e2cff170f1fc842d4860028607248109d4a068bae699f3a18cf3635e8e1157f122b484dd9571d49baf596a0ab02ed246099acb78709620b	1636894891000000	1637499691000000	1700571691000000	1795179691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	43
\\x64242f35d34a0ce5f383297c570746e64eddaf7c750acf74b361b21e85970e33fd58011c9e23fd23ae8192e1cc4be00df965b6149e00fb171108d70b3dd1f737	\\x00800003bbb6b1c3f95e938e2ec3c930c84734680c81bbbad30bd3383422c4f2b244358f6d74441c9b7310f92ddf62f575c29b65e21ed51b285c1d54ce86f81186e8cd5dc9556a936036e63055dca124ee29e6d4b6979a6b9c849cdd53e45f23cded84ba2faccb5de48b78248fba743ceeade22af927c2b12a1a954f57ee3f82a28513fb010001	\\xaffa2dc281c420b20dde8da203724bc797706618d8e55dfd7336a532f14ed4827cca3b87e3478ed92dd355019e8bd16ec3ddb412e45091fe60fb37df3eda770c	1645962391000000	1646567191000000	1709639191000000	1804247191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	44
\\x670cf2201b93c22b5a4299bb99324a5527dd16a34b377fdd64dce728f6ffb88a018dd3ae60c54bd1b64d946c9746a4828aa7952e6c90b71668566c315137eca9	\\x00800003c322e6f052e24086e84712b3382cbc36d422becb4f65e7e01712ccef4430cb35db005bce22498b3879f5238fd11d7790c3635be8a79dc5d2f325d5f5be3f9469543cc4c98f194fcb47b0bf537a6aa29d7e412d08bc66cf208fb4cdb65eed2f2d43fc08305339cd4af98e1afaad7ed3ac425cabb676f5b89dfd521242274c4c03010001	\\x17e830f4018986aacd868d3afb6e3d5f1e50e26cd87f5f8f93ec0034d4e14c24d6a5433e360383e2a29b2c478179ab05539f2adc58772f49f3dfea01fcac0603	1653216391000000	1653821191000000	1716893191000000	1811501191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x6808a6424f2c1ccc4c7459eb3e27fed3308442a72d43cd60881c8ebd6c15f938cad061f3d50662d3e0c7d0508883ad5e47fe56e2a9ef8bfa8c7fd4d6576bccad	\\x00800003e1fda11b2f8db58e0e93cb8a9ba78ee70faa4e5b0103a21326883861ee8c9c7e185d53a0954c50de57e69d9caa268ed2d5f3086f7834a6c77e90f04a479c221ae726f8866220e3970e73c86e3a7009993f665201b53a480ecfec190821c91c78a32de47084453dc1baae102016b09c603c7205addf4b8cbe40b7998f90784973010001	\\xf08ef149efc93e9e41e133bbce92a89e75ea82b6e1f1fbf965db12a9f1b7ef1e015ed83e34ea51eff9b8a71cefb42e940eb7eee27f32e536b83f3bf22a636a0a	1652007391000000	1652612191000000	1715684191000000	1810292191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	46
\\x68187b0894fa52c325a8ddab56ade427432eb4bd829e9dc8c65468a352adba692ccb50b39c41f4e20375cdc57a5a85e445eba396da3342607d3e96b8f76d2818	\\x00800003e8050aff4e12e184ded63ba0fc44cb40c84aa0334127ed06b3a0ce091a79e862fd6c2f4b8b2f9b9b8db43999249f107580b8b8dc1348acac98a04ac2c73fa3954970b325a0c19139ae5a1ce08ffd9ed35ec7f56518bbbb4f6de27044804f365db38cb1b4c3b511f7a1ea23e793b87ad176b684b18486d99af440e9ca3e5c18e7010001	\\x62cf1ae9854a67fd0761ccaa702665068a687cc99e6158634a1437f5f1d6ac76bfad7a27197a28b554bb65ac2bc3a5703d5b99537c9a1cb0aa10baf39ab9fb08	1639312891000000	1639917691000000	1702989691000000	1797597691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	47
\\x70f06cdcc6180681592ffc865a898687c3295a07e79bcab885ad96067d15788662a376a678f528238756600c916ad51188407b733126b4ebdc5a1e72e7878257	\\x00800003c7fbc2f41fbd7b78dd664e887eee08797e8941a6046aefe4f5f06f7e7e52e66993ea14261d8f52f22db5153692eccd9a422ed267ca81950db6675c3f52099707a839b28247ecffeadb0b0110eadfb813c27e31f2db60c672a44eb9fb8579ffa284b011f8a27a5ce54158476b67ceb8b61cff3aacefa1cf203a60a7cfbd81d109010001	\\x445da4bcb1d63116c2799891e98ee377db18227c899c7fd6816ec37dc0f439a4c072c25b3889ad5940c9cea3787addd3718cb7e8641d55d3d9d5749ba5f6b900	1661074891000000	1661679691000000	1724751691000000	1819359691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	48
\\x7068ad939680bef0ccb82dc1a0f0daedc4e7201f0493eae5d95b9a08501d2ed161888ac082389979b73989bccc9ae2f17c0a0ce9c63b155d9d1b6ed6f27ce803	\\x008000039fbdf18efcf6a2374aef442007f7ab2c863a9eda3dcfa2fea396dbec1cd482f6fc31787c2e6f1eff59107edcbde71d345ffc234697aa1ee5b9b321b1d6f512ff7b01529a8ee857d14e892d73520a8ba77e67c8463b27e13e486e1547d265eb2844a4e48731749c24b1182045a19c463266c627f8f31dffbaf736e744c739f487010001	\\x9ffaf4114b9828f1e95c0f4a393f768d9465e3c14894147aefb77642b15926aad691bdbefb1b17bd054fa169d979ca1ca3c462f6e135fdb015571e2cf3eb5101	1660470391000000	1661075191000000	1724147191000000	1818755191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	49
\\x71c07cc43f5267a9d06ba1965859a3c487ab011f5e73148ad4366b738dc9ae8b75099353b3e42898be9a9645813712ffca375e483665bac94b34c8dc6394bff8	\\x00800003e3ccb53cecc72e49874033558a64992e07c27ff0563072fa25b8cdac86fb19675c7e39fb2e5f0ddc3712a1691c610351fe8533906960522f2c88b85b123879aa6787b5a7e830cec26b2f5d1091187a1e976aa456960928439ea8083ffe2502b5c943c543d0d188d022407d0d888c7206881e1620e0a157aaa20fb8a05489d035010001	\\xf58ff9af548d8d91bc4da19b27bf0128ce127737d9b604bb8c01b8e911af5718a31661cb78330e3f11d65a871347c6b57fb39e8923bdbc71bba1e72e15195007	1659865891000000	1660470691000000	1723542691000000	1818150691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	50
\\x749c7c6666903b7030022c17a08a50366f5a271ce2e5df3cc6743931bde0066bb515f5e95b305b4e4e4c37b06ace197b7a57da260a892a131074954a864565ab	\\x00800003b384bb96d57f68530adaf8c049b491e26a2dac442d7e9591c081a1628fa578c107088e11d432eda2a8fa2c3f3100f658a8a9c9eb75c93450ff40ef4c92f64372f46fa6d71046ab27aeb452552612e657cff7604db7841c2a4228a3987e0941c1fe4b85ea6c6ba0f0d9cbfc6c23402846de52a9df924e6d03d254bedac022bd5d010001	\\x910f0154f367da5e812d7e79d3015c4d66d5a119978dcc08ff482a5e90eb7dcff65b3b428bc8163adf0dc936602eadbe0b2e9d9ac05e6e7ddbf1bbb61be75903	1632663391000000	1633268191000000	1696340191000000	1790948191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	51
\\x77f4b51a6c46e400bf0732d115b2fbefc5b193358a890ceef5f7a19c61e24b3e4640af41a03920eed43354a2d1c18e323229114aef6dc009926a069283f457e2	\\x00800003a662d9ae20a3d64d060b27a2beee95ae7c2f98c18a46755172baff692e1e0019edbc9f5925ebcb5f4053acd9f08dd5d72a23187acfec912d0f1d2f434041bae1077cd1439050b1b00d46d0a18be447d3eb87b44827b13027c59f4530a328e2b96cadf50174f43c098ef94f3a7d683688da3b7628eccd42cc2ea698c139532dc3010001	\\xb2b8b4f245c1154858fc188e11abfc0ffee79424f8adbb5ca759df8a9de5d2eb875a81ff37819d1754b871fd16c1dbdb99129c57109bdb54250d6b14b567000f	1641730891000000	1642335691000000	1705407691000000	1800015691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	52
\\x78ec7b494af2e47f482b69d109eb60f103eb9317251b7af1441095eeb59711f941244eb79288a631ee86feb38cad6b2f2055dcd8518bd434672f38a0244e8957	\\x00800003b337485d4a7a3c35afef762b7596746000c2031a3a30838e467d9a7cf302e8c54bdee8d541a582b41a82589c743bc01210eeab8b53419b6f836b3b4b42e0e1fb885293d4853a2d7988c0a2bdbd2e7bf2ee1ce31b0601edc5274b3aff31db88a81c4c6e13c060143e102b3e888ce1b45d23a98a9a975cd06f9db91db996d608eb010001	\\x40ee086227b82f5a3dd7646f5d696296533cf910a2e6acf3841083d1445aca9c5fb3907b6ddb70dc8bd6c02ff508dd2a7cc6abec98b53e319409e3dffe6bf607	1658052391000000	1658657191000000	1721729191000000	1816337191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	53
\\x78a4609eb51809669a0805c450c65423ab7500541c11128964720336d211c43d1747ee6bcde29ca5d553b7bd9f646b71f978d8ec5d4861a2fd1bca5ef1237e94	\\x00800003d4a856557c4d73eba034e54d1c07f3cea3cc3815c4f356fe95ad9e07e79a874c155451dbd2296877217a1ddb2da3cdac64532e2c2238ff093d15d119aa7e80a851dd2981b2ea9d5e6a0f9a54a19e63fbb6a3d4b049bbfecf082f00340ec0b093c2a749fd9269c2f88d937d24e096e5a45c484f2c1e978a6bff8d1e4bc1309605010001	\\x48d36e84490a21f2aff07cac247068516e9b581a931c2a3b19cdc23b05cbf6d7e03d4af7ea9bc8bf7b1fd937478402e3cbe4542eaf5de480233c5f25f7ab1706	1633267891000000	1633872691000000	1696944691000000	1791552691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	54
\\x7c5c7825581a3033017b7e02008795c79ba1626eac208b6723749692bbeb631a33945d0dda8c249b13f9f1098ec4d086fed669423d1012c85f47ba0128eac81d	\\x00800003fa018f53744ece57c9c7329f351a0f6fa3868c0d36526518f89f0337da521e96f5dce2568e3186cf6c613926d00dcf17e27fa8268b8dec7fb57b133925fac60d9aaca6285bc3c4ee1024935df64917d9fce83ce456eee59c3a01cc08c961e6a450e234f5a0327c1cb56d9ef01d3d0f4fffda65cc291ad87ac6c6d70a3aba632b010001	\\x859432258488578adb081468b82e3476a5680f888de9d839d347f503f1c31aa3ad3d5e95192fbad7dc6baf6d92f969690eb41680e678074d4ad2a291c44e620c	1652611891000000	1653216691000000	1716288691000000	1810896691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	55
\\x7ed888131f32d7bd074aa7745dc831dbcd2e602cec7cf10889a3fd7768801744cc2a282a3d8db03d6b48f1d2cfc63210988088a28c755ec13b1cca11593e9553	\\x00800003cfb09e209f29672e744feb3b66c563f335d624f3352640fb70cbd4c5916cdeb13be6c63a82fdda14a8924a136c2abda6ef031d9d01876555dcb5a3bc9a898ebc6127555571a07a6ccadbe1f6f7e17d9bfd473a4b3ea0161221b336dc01b8192766ff94bfc69b8bc3e11c22da18e4bd71377f4ff531d1f0ed92ec1da5bb307fe5010001	\\x25d26dd546e8367108143e479c75d38bb762ef9c50d5c26a3f38f44cb6114467b8c9f1e332ae70eaa32c17ddc23ecec2bc35c52a64dbb14fb5cbd6741d66400c	1636290391000000	1636895191000000	1699967191000000	1794575191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	56
\\x80bc44c96dff69858d79240dc609628b4229f2838c1662fbea494ecc4fd6bc8a8688b97ccad97f34a9e3f47466f16ed197cdd87139f39de1fd337f368c45e877	\\x00800003dc2340955e62644ee67544237335a843325e2fb6369afc3276a4906472b9d1c95fd976856c3534a7a4a4ef05816b677852215f2b15c33a8388630d74015765b9d6599569f6913c879a6d4a031e420c63512d50e6c418c791c72e6cf65782d5f6c318408f4e26ae3d451eb3e9e52a025d928b318229f9c9e4bfd4af93c08fe549010001	\\x49eab6eb6b849037c5ef004fd1af472a6569bbb3ec44d57d34aa0fe10488b7f0d00792fe225bf45c1cb57e12a81a873f01885732d836b6c5a8cb1e2d610d6900	1652611891000000	1653216691000000	1716288691000000	1810896691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	57
\\x81ac5c31014ced2afa5a4cf5ec282ed851a6ea96a65a34086f2ec6002268efc1bd2e2ca604fb50d701e3aa0397c128971a76a1625ef90ac885e5f251b82fadf2	\\x00800003ad4c81b2144557b034323ef4cc195605d3eefa9775187e22a1b49171a1930d7b661e16a299e91f8341a340970cddc337a4673d519c1ccf8a104bb0b886ae5358a2d91f5c11bd4f2cb6b95c47bb4ffdd4cceb990e9cadbecc35442b800da60bee4abddc051b7c68bf98a71444139fb2d2f674b60bc85ba755016d2822ce668435010001	\\x065dd643e923cf7c978c1d1910d8f1c33a3d3915a159a14280361c42fcc1cdf71828ee9eeeb8b41841d90c9797ea42dc05ca7cf0efe224cdd4208db5d7cb2607	1638103891000000	1638708691000000	1701780691000000	1796388691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	58
\\x82cc62068e86d3cb3796ebdba6fb280dcfe3306ff138e9a99ab8d00c2fbef33b37fffb25ddc127e00b11fccab068e76523d9e87a7679ec4dd0463b85184f1765	\\x00800003a882838c2048710955d68db2c79d5b81cfd501e02f51992b122855403cdada65b86558cc681f801c63864bec37169cd174f4e243264e06fda6016fa1e823c7cf4b7e39c6f6cb78a5c84ccc56040fb4fd931da4b73e927e729ea5097e5ab85ee21b25cdf17e412d4b46c21bbc83cae5ead24edc6451af0c65792f88ef397c6b97010001	\\x615fe70821e1394ddeb1902175aadfbcff6a8de4fceb3909fd686fcfddda0f530d5f776f46838cc2491d0d6f2a9eaacc7374f4f452d36b70a80a0f9df89e7b09	1645962391000000	1646567191000000	1709639191000000	1804247191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	59
\\x83cc617795b15d15759a1f2c724eb677d2b1a05ab3fc2de78f03e08fe4f4f0e8eee0889bdcf8a11d57aef4132628c173c2fede607039c9432b994df86601c21e	\\x00800003c021b7047731847c862c23310ed9d46d5dbe7698061621d6d3920f9b77b4f3bda3df5dcc6d642a28eb4397304164030f05151b7cba7aadb09caefee1d717323ee2791775b1bbfa65124fe5d77aa749424f0411eb07ed4a13d77499be33485f7022a7fb8bf5fdd0547b8a897b421c6e58cc77d078eda1ca52d95b560fddd7f1c7010001	\\xc0a98e2bb8964840f102d2db6f18aa9d423a91baa6fc7db30a17dff5109194b696bef2f01539141ac079800f630a5db46d781d04986f42553bc4f9e214b69a0d	1641126391000000	1641731191000000	1704803191000000	1799411191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	60
\\x834885fe39a03190703821a8cec8719eff4da29935625540fd58d1fb293d353fe45dbede4e5e9de17ba5ae3df27a94d7225f6f304e9c95910e34003036be9a74	\\x00800003987c455f1f96944ceb28a04c9d1fdc008ce13f0619c52647a963b3a093e4b7ea2cf7e6b96d9ee2ca555202421a8eb5308f5de1ba9d1b9501ab5325d8644d473fe421262ff20ee48101d60bbc4142679254c12687eb642b1c40f64da95e773b491ae60850068f1f93315f30b729ecf97b15e9d077b8d563e55efee37efb138e71010001	\\x3e8e0db774bf8e52d039340e641c2de4501ab9cc12b2d4c26661759c8336be5cdafdb0c8d352501c358e0f95a634a351cc0e1cc092279e5c041fe067fca3b20b	1633872391000000	1634477191000000	1697549191000000	1792157191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	61
\\x8420426c00858079651d3dfefad3e617deaa26f738d5c3151d0ceb6f53b7d971aea2f1c1298cc8a888662badbbe3ca3ed46f9e2d9bbc054c7fe539ad09363393	\\x00800003b1ea927338eb465b0d74cde793d10eb24d4849dcc9be913e5ab65aed5c09dfe5f47632d0f6263395337e26f6b3c72a7a051216739daaaffc30c7d2818d51254af116745ab76892dfddc6ab09339cd11d94a89a3f232558f9198087b735535290997d65ad5bbc7f289e22a6a5cb940d0c573ce9b908fb05b941c2a66522be7f61010001	\\x2a240d92e7199da39d118bbfe21207f2433db18c66a3e1f0ab0345c59caeba100e8b696031668c50997859b4eb9b89058fc7854791e833cb1563752244c40a0e	1655029891000000	1655634691000000	1718706691000000	1813314691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	62
\\x883ce3bbb0db91eaf3f1a07a0ca5e99f6c1d9ac4666c987020b3e064d7ca3c898de41097165672e47cb238fb7eee7191b9280f8e20ebbb0e3d904beb4c2ce983	\\x00800003b62997af6555e666578b7e1a10790448217c6085b39c0835aa953fbde13d12d098feb9decde42e3a555e076b5baf91067eebde34b3b32f9d9ef54ebc619dfc3ff223e7e119fb71066343118b381fa553797d1f03b4e39e3f649d2ad5921d3cdfb54ec4207331eec8c6bc6eaff6bdfb35fddfda6af83c31a71cd6c71a6dae584f010001	\\x17456bdf65546ccf8a8de93a6a5d166d14bf714d89b81b2da065642a59eefdb13a589f4201a4d8b994c224f2a1ec2ffe17d7c986b27ddbb1c5ab0aebb9731e0d	1647171391000000	1647776191000000	1710848191000000	1805456191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	63
\\x8b8c70dbeb49175c215a4e57e30aa72ea33baab4312f9b87c7c44223898a7ea0cf13aef9057984f6387ebc487b8c9d04ec00b4306fe84f70590daece8af60307	\\x00800003bded35a27dc16e0d35f183ec5ac3e50c91e2bd490fcd3cc0df465c276aa71bfd64a7cb73b98366758ff07ee76dcced8e52000cadcda56d9323ac11951be9336e82da77d56899182324349c1f8d1a8c18b88e9e99bf303d08b5c919c7c63ab87cc4c296c321f109da025b0b229c9f29c8ba4a9e3fc6ad6e2f0c513d6cda2adfd9010001	\\xbe7e947ce64c527e8da0b9411c8c2265f511a244aebca5322a16c8da3e755a624374cd70030279973eaabea745393335282596c142ba7594c50c433efde15404	1642939891000000	1643544691000000	1706616691000000	1801224691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	64
\\x8c3488f215c9e011ea535d230c73e10f8473a8c46f70b21ee4834042e33778ea2757e70decae3a867c0be3468e04072ab0ca5e42b44766c27652eaac1167a6c9	\\x00800003ba7302be891814e33aecf3f46db1406fbb861ad6c0139e1cc428ef4e7eb9e3d70343eca3c176cd5898879488a9e9df1f6dcf44d9bd307518de185c1a56858232c61b0f8db66e4c7c4c0775781dc475307273ba828824856ae5f4493e16df13cd5980e49a66e4cbd2bcfb03164f7c7a4a2f49b239d66942b939fc103eb00706eb010001	\\x4237f7addaf9c1116f4d729c0555da3718c0d974900b19792d202296f130040ed8ebf6f18007c310032071728849d697bb733b861687c9958f52f1522e395b08	1635685891000000	1636290691000000	1699362691000000	1793970691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	65
\\x8c5c0bf806416a4d8a7fcf8ad9c4253687d6efd196fe9211042278c7302927a2060763b790f4043bb6c1107f54daaf86ede8fb02d58645bb7df8e9b14b18b372	\\x00800003f4d470f7c210a251ada4149bebfa208644685070daeb5e2ef3d94464b9a9c09206f049c98710a212280ff165d793c9889966f9ef5fcb66d2ce56e43446172bf41f84a41be2619789a66c6c507c328289c4fb7569a7d5b4dfd38d82c68ebe972d924ce130d1bef68937561b1e2415d6e4a088a0387c8660dac85603f2c6a3389f010001	\\xa7385770af6c0e10e7bcb2635a375361ae25041e7f21bd9bbb4c834d2baf8e9d23b81ca704636b239c366fe60dc55967a8afc64b1d251316cab2a4d919135008	1659865891000000	1660470691000000	1723542691000000	1818150691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	66
\\x8db4f52ead5c6bd4534d349c142adf7faa1caeaf3a71195b1598d25e9b1997984718a0e4a735e0f1aa3614262237b6f64b7f80edfff627cdb417ecd87ea58a85	\\x00800003b6a29a71aabc305e410af3c50ad9e4e40bd4e1f0585c8afb9053bd48e7ca270bd20a36058ccce66a646e8829a04411873683f78b023f32afe7aab98bc5e322baf8f08bea055ab98b497a578bab861b0d3dfd85592b0e7eb08a141ffd5b3cf135ac57aedf5c7cbdc22edaf5c6c194461968d82d2b173142a868a6de32a599608b010001	\\x31f596c25b7bf216ff4cbaf588e108e691d3c98cbab31e13dcff44a7efd985019ef400b120c6a8437ddeb0b6b1e1d767e08ecb8a5dddf8360e2ca55a17a56407	1639312891000000	1639917691000000	1702989691000000	1797597691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	67
\\x91bce87a7a80016adc3b1d7960b3e207377bf58a2a46d583407faa5468831a2ad5ac8f39894a8c45866aa9f9a7934c7a0b02f2536f602f6560e8ec7fb357f75a	\\x00800003d8f42c23435002d4319802cbb265950924647f98a5e7e527311120486f18caa082446344b5c826b230aeb5b891935628d8647f8e4e0acc3d8ff7acfd421cc77a7d61b93fb9d388bfe2e4550ca818d9317bfdb008fd1242eeb93cf1b51e25252b10ec83f7c3be80da3fe529950c8d84127301fe261df326c00ff8f7d5e7fb48c1010001	\\xacc28cb4339093d1fe7c4cee9503908d412465ae0addf1b8cc90281a50a91d0bbbc94e62f9f957054237e8fc54139ef57345a455ead23202985f8a8cd451ad07	1639917391000000	1640522191000000	1703594191000000	1798202191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	68
\\x91f0f8e1363de60f767735948fa11177cf14b579a9fc7a5d56b5418a487ca64be6d5652e0ecae1056e33fecfa929ba2c30522d82dc00b776b78818804713ae87	\\x00800003a9af6d4773e102ec6d992f60bf91cb2ecad3fb2fcd3a06c0b38025d2f58dab6bc30ccd170cba38d7160378629987e93bc278407626916f51c4559ddf2a8d13a6112c5a0f8d7b2d783e3ff06718abeff3ae05b5ba9375d1b0d5ed4ac0cbc922d6788c12502f4da172565a3d57592239cc3b4c60135f1b7588116d9c350e09300d010001	\\xf9fc02dc18aa343010d143a41ae9d75292fd2f93e7a9be754978d8ac3e573744e40edc2257288911edb50431455a214eca7ae80bd20799832c47c2b79bc67004	1632663391000000	1633268191000000	1696340191000000	1790948191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	69
\\x95f021819a2b89c0023be64029ded36a81a6f4d6cc49578da650953d973d29504f282204c185f52e62e35cf8d73327cd442f987882721471cafab57dbe34ca69	\\x00800003d8e93764eb5331100285ecd6b6c46831f90dc777cb0ba9f5efdaee718b8c7b30b4791d1b7ff56371f7ad06893a2b1ed6296ed68abb144eb51b753ea01dd0c73d6036725effa7a8e56aeb5cb51803f04e536bee324483218c193aae1b4895a4240e7ad792509dc5f6d17bf54742d373dd0965748706abee7b7655834c02cc5c0f010001	\\x2ed6a78abe1704593f6d1899eefcb34166c0ec6eef95d9e8add752ae0fdb9dc839b85baccd5f3cb8212609bd785110dcb3467b14d1628827e64a9c7a96c5240b	1655029891000000	1655634691000000	1718706691000000	1813314691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	70
\\x99dcebd41a8d4fdb9e9f0ff456a63e9cac5f5d034119bbed2eac7e24cbaa6eed09cdf470c3ea4da7173039fc6823d74dd2d133f6de3ca9fbc02adb21edecd343	\\x008000039e2437e083727f9eb9550de2bc1028e131aef94e9463bae1d62e8bd85d557cb12c2cf60856b12ae90707decd565e166d25863b3e47027ca5b47beac89415094a50157bb99323e8b114769f9c067f6717838917be783d808d1cfeac0dfae1afd9eec654f9c3ea120e5c82dab43bc6d863b52fe6ad88ec0d87362049e73015eef1010001	\\x573cc21bd4c3d02ae732ee1ad8a1948c4c3285e6c608d89838f9c3a663654d7473dc793fffff9633c61aa80911ea4d7a9d527a8da390dee773858e8061530104	1658052391000000	1658657191000000	1721729191000000	1816337191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	71
\\x9db4b107f67dd8aa5b9027f5dc549b5e7f10fad3b32aefb985f37f2d016b9bbcb6742dbe2b606d12b2de6c5558605e362840e0d2d1f51492456fb9a72319ad03	\\x00800003b40f0e2b863d6b1838d8c88c9afde38ff9e2d72b367c49cb15ab47017ce98b1afb093d4745d137ea14403b5bd87977629d93dea635449b610f39f9e100f71409442cdacd2377fa557d9d79b646909af57e708ac06b1482ca110a7eb99ad012939cb4363e7b50920a3f28af8692188576e9703dc50f754c659f02fd51a84f2731010001	\\xce4b4f5c9d72fb464e6096c674b424fe68678ea0247b7d56a971170402fd6ac21225a6f9eae0906e528752eb350c6f5c53122a90b1a9c6741820778fc3191106	1657447891000000	1658052691000000	1721124691000000	1815732691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	72
\\xa18cc37eb4668060f03a32ff919eac03d0aaf12366ac51e899d6272974782f75f838c0553d553e1c1cdc21d9afbc2fa5764a4697cec6babb61cd37528daaa0bc	\\x00800003f22cc078215966890c2beb122e28f161aef0f39295a208084a83529f5f47ddb1e0f49b9b22efa78ff57ebe9ef281411d393bf79e34d025132998d4eeb537c6c16998f451833003d54218c4e3da88fca79af85197ef1245b473b77851be7d53a14bcd4d3a45fc24785c150be20d5b7728522e02a017450a5220a15ec1c4fb9543010001	\\x83dd5998651b6e531e6e78cc898c0826f3662d32d61a1e81282c23223106db679d07be75c09e1c58ab27a6315a0520279434f485a308635fc7913580ce03e509	1657447891000000	1658052691000000	1721124691000000	1815732691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	73
\\xa274287481b63025e501b9cc9f620d3ea8d2f78389d3f7641fcb10cc66f6dbe98aa22aa4e818667fe08437c3e6298a71aa88d8bf282e480a27e7bbd0628657c3	\\x00800003b6b2e2020ef294226ab942c5d83748123a96f79cdd937ec54d6d9dc7c0a006ad706b623184db1facebcb23387ab636d743e58bf820772db6a6cb6605af6f20278e5a35af46e020283dbb36901acfba6a429a2fd5d7eea8f0a2c2b7a6552bd74c0dbc912cbba6c41173dcedb06fe373e980bd4f4a0688cf7d67b573581e449b5d010001	\\xa40adf747b68bbe66c02d378be5e11950e6ac0b7b4df894959fd8357a1902248f07d986d1036d85e7285a9e7ce96f8b52ce596739334a5f043ea0150588b6301	1648984891000000	1649589691000000	1712661691000000	1807269691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	74
\\xa45010809828cc54b3ec223b48167c4efab4eddcf2ac351e67154938240285d47e28f2d7046c0c5c0f1931f0310b9c4d477ee07a84a2c47cdc08b08bd341634e	\\x00800003c594e98e67f349145a9cc6992fd7efa53531745faba7b671f88870ef835a226902668b9d86b9a19009b9b320db177b81e7e101ab5284af2a21d0fb12225f6c863d29da6709847a79500152f6de70ef76313220aefef82df68afd2eec343b25e9db7db7d1dc0bde09dd5104b527df7033dfb64e0c410ee01dba9473d8b09c6413010001	\\x648bf1e2cc2bfd0637868105b038d03c981435f2559864284fdc368b09d70d4e7a1e9544ee443f237f84836afd725676074b34eeaf73212164bb3b812eefd002	1641730891000000	1642335691000000	1705407691000000	1800015691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	75
\\xa5bcc752a3e6361f258959d85f69ed8323e25843c9a5862be76644af2f6dcfadc30ef97da3171ccc13a577a03808e384bf7cc64ad56451da62a5851347903f4c	\\x00800003b41e5c87aea641dc4304ae2515812527176b9f0f81fbd19d584e06b7cbf68eb08c12fddabe3bb7c9317ed24df08cdf1738619fa44962137b7570d61a4951c4c91cd4eb3999ba9c461e15dd17472799bae0cff535ed7478b78c5cb0d9afb6aa37be97ef1a07bfeb8f1a27f538a7c7d5727ae8d0e984e876d46b09d4076da9f211010001	\\x3c5448c34bc4a94a6cf710e7d0eb823b93316bb4122541eafa49b35e4e1ad105a726749940b3098874382f6a5ec3b702851294de7fe1525733c3a9f115664c0f	1659865891000000	1660470691000000	1723542691000000	1818150691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	76
\\xa97c39c5c9e57762c126f0d1d803b8120a84cbcf348f8f276a55e394de5b4eb027df26d2cd34ad4ce545b3367c940c96ae666ff39890cc17d63275f82f5c6458	\\x00800003af5c531549c0faeefd0d209fb357734394d4ca0db2ee8f7fca6e51e1b1fc140bf824774cefa0b8c0a3b8c2cb75b19b10896c654bef1bb3098282c90de83304d7740eacdb7d7b505f4a5691983e58a9067c094446c2b77774e112116c9c3f49c29463b7e215d70d38f6f728a8793e4939eb4c32fa9e026c778f8a98c623697cdd010001	\\x880aec6f16a1e58b5fca9ee064e74bfd15a1b0f76cb62e592058aaffc5e28f772f9f9e8092cd48a5002b791769e3b3ddd1f8b91fe4466e4e8100bcde6c8d6a07	1639312891000000	1639917691000000	1702989691000000	1797597691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	77
\\xac5cde174915a3f1d92fdf57b3788929d05d8a729ff9c4add5b852524f3963e50cad0d9d29b4f16b44177ec776ae2066ba5de1b2d1497f162717f8c5a17b4ee7	\\x00800003cacc57e35c896dfd58929d344ba04503e1ea0458834420156a382dff6351d8d7002e8d3628bf369eea8498f0ae5f7d653cd49d66d8c7b564e0fdac4d38207b8b1ff298a2c85f1274f86cb59cb9938dcc169b9e1961ec141f74a936a968a025bfce41b81abe3d2e0ec90da357474388545560fe9f379349539f9eabd31e09c97d010001	\\x8e88a2cf88520a2b601ed7e93957843acb72ee7d73b6278d90f86c4cb8d7b52e22bd4c29f2c8c5d76caec5e61423037e60b9171f5b505cdad06f9984f682f50f	1648380391000000	1648985191000000	1712057191000000	1806665191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	78
\\xac2850aac2130f94624101869ebd3a5fd9b6bb2f77a380b50991cc18e7ab7b3c641f65cb62dbe7392654b474b423dc16dda2b23f71cdfd0565565899899cfca5	\\x00800003c6e6c422c8c68924ed0d768cfde84317e87067e8c3b76e803c8a85f3b99f76e45edd199c8d867400ea979f907b14c23187a0914303eacd2020aefb4c74b2f201773dabbb5eeeaff5d73624ca42fbeacb464242097671f883f32843a3e5c82e0206709c08f9ceeb1cd292f3e52cf0be4a7f29d3211b7a0c67932f14b95ff7efdd010001	\\xffef58e6dd9d78662a55255bad5c8adf2dd0981d69a4cdd5e7a38437146dcdf34578e3b3e3d1db769c0c1ea2174c3825e2f97820a2f8d2b49ffe70bd7198cf0d	1652007391000000	1652612191000000	1715684191000000	1810292191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	79
\\xaf981ec2a179b0bb6b5e21632ad4e8a7e4a491b0ce47b606bd3c779d5c2cfe6c71b7d22edf396571ab4ccd1cf9e66508ef060d38071617cf4cdd2a2a4fd524c2	\\x00800003bd3a0998cf85cd43537e1fa4decf992121614c9d70df51460592d8dc3a200e7e22cfc263656b0c9d10b0def335628d3e1231250cc5101fdfe40f2cf35ec0dc0c41e730699c7df09791960b04a72c46e7fb03bf36262992fae48ff142812f3a1265ac249f5baed2a9a5d5f3c47db5dfb16cd2abcb759d122a72a0c4b71725dcfd010001	\\x40b94b9acbed4dfbec5fe1d019d526f4ea1e07861a03d845ca88bc99de73a37c559d427062a17e77e53e0e3cfe8ba7791e235a37b12da417762edf25907cb203	1659865891000000	1660470691000000	1723542691000000	1818150691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	80
\\xb200e448a17d17d17fdf01bf88543205f67b8bdf32342585049aba73cf6c6b1dc7c90a6213929880e7432446968e8eb0e76a16df3a25648074f3bcfa92e855e7	\\x00800003ca9331499121f0a9ef1f0255abde4f6a1bc1026954a836348fa5c4fd5ae0ef0a54e4627045f706b78d39e6f6a1c775517515d316a99ed3e8bdd629df544e07c7b36708ac7b9d513ecc80185bc7b8d4584930cfa943185aa9db5efdd701cbfaadc80ff5facca7ec4d7d4c95de5419ddceebb6a6d7ad83926defbe368a24068d6b010001	\\xb400309b092cd82ed8a5d4eb2e4bc716ab70b5046fbb39d8b31140bef482bcf2379df01ff5295286f1eee6945a6f7d91ed181e2d6ba2a7e9c96d7e38d9470d0a	1653820891000000	1654425691000000	1717497691000000	1812105691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	81
\\xb3187af74ccf0729617c5a8be1cc54b2549ce0f960dfb40c4d32747549f63a33459b4611a0b9568b107b893496fda8502f6c7245652125287d279a5f7d886d78	\\x00800003bb59f771fe216b02c527ab05028f1688fec0fc3bc21021356d3dd7301f8580f2fc5a8017c0cfcc1cd9be18fc7699ff1caff6db74aff24c0176a71a1401b6f34aafdc7f31d64da56ff1cca4ca3da609c231db290ef8695cd0d07ea13e42faff676a991c3e130ede380fce6ea273212741b9b33a0c43b9218fc883eb976be67477010001	\\x0ef8f76402f2d7bece4d7a86dfee648fca58cff39220ba910ae4278eb8d9fe4e777ba58310b897917a436128e80373564abb8022ac0c9e00f90f683c58ff860e	1644753391000000	1645358191000000	1708430191000000	1803038191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	82
\\xb3dc8f8f6ee7551c6f3811a576bb2242aa0d11b4a3d25ee29d5dda98efbfb5cba9046368bc84579a5fd43282030c1f4745c0c068130c35181445e7be05cdaa26	\\x00800003b993c2d176dc7df24176aea5dcd51cd7794f96253091e4ed2110fd2a53440e0d623c81e221b23266245b18cd8358bcfe7a27ef34848300d159c6dda59bccda4f224b8aaf8b5995c5561ffaa4375417688e0555677853f1d7453fb9e42cea6b1a3776074f6a514fdc230172b3dae6a8eb6b22c5a60bd32173dd7ec120d972cb89010001	\\x134dcceac015a60a9ba822aa0215f5b8d6092f40613748e4d43d79d53c026929c061fe059a422cb7bb94bf8fc7b0e3b673d11a6cf72bac839912d32ab0cb5f07	1635685891000000	1636290691000000	1699362691000000	1793970691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	83
\\xb80093f6faf269ecf6679dae6a34a35cb4cd1a3a3f588a32d912ceb3f81d18d9d51e84c389923c391e1b9d16509bf99817c7ce4913ce3908a6693ce86c96efab	\\x00800003decde92b229c241c5759f4fc1f385bee66617dfa031696dfa9fb0c656e33364ae9aedb9002291a71b8f4a237ec4f2b6c66866850b73b6da5a85276e5d321cdb6530d77e7526c38a5d5ef902f806aaeaf29a6b5719c2799a85aa96a121f22977f88798a51858eb9dce6ef843482ab4552ccb7a05d98ff023d57b58d36fdc664c5010001	\\x370d596ae4a386c84351c4675b2f15ca84f10264a8f94a2127ac3dfc8eac8865cbc2906a7ad6b96f5d96976a5ee1b497515422a3ace392a37d9cdd9e8eb8280e	1637499391000000	1638104191000000	1701176191000000	1795784191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	84
\\xbdbc72983ad8edc50b469dc1b6d96ff42cc72807a7915db9f13244a4925bc8297ad2a8f85928e23ed21b5edcd5d1a99f437779dec682d404abdc8e132b15549f	\\x00800003b6d7020dfa7a92c3cb25463f4049a443b4bd968e29b78451015cf82eb7914a69702f3ec0499c6bbe9f88214ffcabd0a6a9ec2424cd0b6ba0283032be5310da918718288d19f96af766839790312a6bd58ee9c5979afcdc1000f850ff78327d9d5e0ac5697c05f9aebd53d4993779611bf23aa21b3c2c77a666bc32cad40f4347010001	\\x1523076aa3ead36f6517e4be7281bb39fca5a45d7a54b8ee96e8afee7f94a4990653741e4d5b5d03709936dc964b65b26cf7f02c07d59b60ca578916fd79db0b	1650798391000000	1651403191000000	1714475191000000	1809083191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	85
\\xbfa4502143d7ede0cb1ffdbd129ad5e04b9e397447d7a6eb68aacb528b119a9cdbba643630c3e4fe1e118966a0104d2de568acf32b38cf541f51d3ea47a414ec	\\x00800003e90fbedcd1754070f50d2f4058f402392893886e7e2cf3bf7adde08136442e638cb6879b9615c281ff8203bf0b0c90e7ff22ac92a417298427c58c0a0e0a5c0429d55e91f9e09dcc0ea26ac11e0fd38de41bbe03e1e6cffd28567f4e9ad9c919258d0ae80ae761608ffdb583e9811b9a6b3ac967bc901ea729234a100f499033010001	\\x7ab8952825062bc73d5070ebf9c1b3afb92efe6675d39db1befc9002ba4c6ee119bf80506a8270d414b29f4fe3b91a553006dd834bcf8c3c2c4f2bebcc0ee408	1650798391000000	1651403191000000	1714475191000000	1809083191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xc0a86cfe3f33b6329c21a9000a18a352151284557e03d756cc2a9692a4cab452148d61430234660b83256afa47e51bb7906455959e5626eaf54ce6574de9d98e	\\x00800003c00ded656ab259212d0777b302c7cc2e09e2492647b6f60a6b23748ece9f5495fe914f3aec81bc33805cea5c8b1eb700305c461368c97f3933f1cac2acc1c06f7002316d311ff43806b496c585d7c37bf0c137b0adf1fb33bdec0a73ebba65f382ae038f42d90e1370fa036c96f2a695464f48c1bab2f1a967ede714fb9874c5010001	\\xe41ae0c3d73950bc1cfbaee84b99cbda87d127dfe3db668b0ccc96952f9ede2b043d2a235e11751c30b1f6a336e843b895b8f156115f478515641e4a7849850d	1643544391000000	1644149191000000	1707221191000000	1801829191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	87
\\xcb1c2453a741f03f172290ecce33b27d6be22b2624576eea008163688d64a70b0fc0488de917d0e44ae001d0b4de497ed5c74cd425ef37530e34af1f452aec70	\\x00800003b05f25862711b3224f07c0bc4faa922b75dbf24070dabce18810a2f79d615b84b0ef135ebd92182b19e5d259c2a96f61991633e8a085fc02b1809c0e6d3c7d6864d265ecba8b8c158a6ef0e55a7011fb7625a5fb6aa70ea6f78870c04bfa09f462b00d64153b154d17c60c5edf8148f5d2a9f6dd9a6be97660aa5843375f2aed010001	\\x06eb40134c3e2feb5299f001ea416f348515e3e831137f8151b84719bd6a5e5cb3b621924ba6c741165bb0a49edd84267fbe5e3b2a7b333392ec351e116b5800	1634476891000000	1635081691000000	1698153691000000	1792761691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	88
\\xcee88b72c698e86ff63de5ac990f025063b6a8060b186ce1f94c5522f56bf55f30fd8e17f9cfc590fb89b7ab45f7c3f02416f670fb9dd52d8c229dff02d94cdc	\\x00800003e7c5ee8db71c4c670be2be53a432e1cbe287198a05c3c3dd5a224a46cbe74bf2ab0f7aa1f54018cca3960c8ad9b93c21394c391f71c41be77759105ec74602d3a1548991ab8362dfd75e25c2a4caca50576871e8563571c26ec4e0f26cc3bddc0df0910bc90f3004e32ca2740786eedb93226ca6edacb446c3cc8fc9d128178d010001	\\x6b7342638d27313acfb1a676efc8b5aaab6e1b3f64f9ff0b88cfdd2ccb057dc0a5df219243d7ee3ead240de4f5bfe6fc497165d55ca787593c11a85e58ca0404	1631454391000000	1632059191000000	1695131191000000	1789739191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	89
\\xd000d9a3cf2f3c81fec22748e01b12143ef983e22dadf1d18d4e89221c893f1a6bca3e7a7a407a034aab32a7cd7190fb789e8d6ce7fe2120fac15c9e4d974011	\\x00800003e0891b538b6b29ea297beee01a246088be2674cabda11c451b231e42cf84f6625a5fac06f54bd69b407f2c35d2eacc8957d181b652e65a73048d8a3210f3d18af3f6f152b37fe7b77ee7f43d16c3498b81ba94860f9514e2f56505fa1ce5870de04e30a3ca2695e10a2eb62f451853d21b969e795e253fa84a930c9652cdc105010001	\\x3d9572e39d59a90d513a3cea191c14d520f558ab5737851fe699937d70996260811b776780e5e44826e2e2c08a3a5fda1280ffb269cb2fbf08e5168f58161804	1650193891000000	1650798691000000	1713870691000000	1808478691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	90
\\xd19c5ccb95fe0081f791594d9a3b63de1b0b2686078e3e81d9ee06c076bc0d5a592699dc2dcad1f1797644d48ca1817904e0fb5d1e533fb53ca9e1cc9b1ce12d	\\x00800003b164ad858f68a601e6a137aa705bc7e923e3a3e96cda5328e34b54f5927af01b288d88a6fc95b3f9e8307725a7f26fb9e6b001d04e0e43146fe985db58e79b055354e029ca5bae10361d79f30198e6e54eb05a4e8c5f39180a2cf6e7d97282413e536b156d8a2a88462d9f25af76174a033311a433664bc2553ec884471a25b5010001	\\xd26a5ceb1891d7e84f9adf5700daeb327c574a2c86750cfb425c882df9c7f8941e678a0ce5ab9289035a70a2d725044e963d81cb21801f61124ccc68974a480f	1635081391000000	1635686191000000	1698758191000000	1793366191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xd4105835e658041bbe00527591eaec1e45216435adc6fa217e6c5fed436851d874f63a4d5019a4cfe2c2d960caee83010264ab5703fdeb149e93d8c706aad7a1	\\x008000039e4db32624177ce20604302dbb6d1660f1f5682fcf7936f09c004d63cb29875c6d2270ae14a2ab45e1ffd53bb1351a3e79afc5fd9d320fdbd0918aa53287cce0a37c7954c437699171e9e63384d7637cbfa3964419d12f75f037b82ffa0c3dfb0df8ac9a97cf3fec44c865c4509ce343fc1e7b1e1b772e6ef1d69261dd67adfd010001	\\x18f0cb5c957b49bfee86bec1ec8b1169a454ed2ea2a11a4e3469a5a3b871b4a44880f05d581a93116be465000dfb9abdf276076f2073fcb5fba746d58a3d6404	1646566891000000	1647171691000000	1710243691000000	1804851691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	92
\\xd70402a254ecbc99c250ed053a735b388c38ca3f56f288f3174f2c0588ca527a4a31e2ef24fa02bb074bb0c71edca3f84b4bb8d012dc78caa6c610572d6f2bad	\\x00800003a789888e6210266babe82c15df35b41012d0928a68a2a3c5d1a5163df626a4fff07045c3152ba97d72fcc52052d7efe8ff27246bc25924a87ea011b009040a2ad403612777f6b130f13d3898d05a1da817956ba5ddfb625e4b3506d560b1275c3a60d0eca9ddc92e227f79894200a26f7662ce95e516b22a13eb8f2654f04d01010001	\\x4d06b867f4579538597e05b37d021f153f51e5f1ea5975508c51e86797872b43ff802ef009d139d459f53325286c69761fd03d8fb22bb8d29c62951ac61bf804	1647775891000000	1648380691000000	1711452691000000	1806060691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	93
\\xd848e1d564cefb254851a4a60eebbaa6e0d8f56bbc4cbe3aa380b4c181d53495118511599cb0a69015c1238dddbeaa58a2f6071d94cd462c2945f547fc5c8923	\\x00800003adbfc8964bf43cd572a1a264917cae39104129a51af1dab83ed7832981e6468089f20b5b60a3e9e74942b0642bb185c902078110d1b775b8728919c67a628a08a922c656d3689f8cf1613f7d755ddfa893edaa00aea388441a262e22b6a1b0eb08fe6f4e96187dac9a5cb196eaebe0cd47ff47619406284e45aae8826bba48e9010001	\\x1b33aa2edaaa72219a7fb41b219f83ba3fb0267f3cdbdf5ddbf3e2a77818ed119d3ba57965504db8c465194d5d13a51504845780c0520859b5e12b2c4f788f0f	1656843391000000	1657448191000000	1720520191000000	1815128191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	94
\\xdb00b5c73c4746bb1f888de5b84db92c87181716e987612b7c531c33ae4b92eb7de21dd152a6c6984cc54c2e27f412ced7ee89c7b890a49efeb6b15ea85df110	\\x00800003e0021484a10978e872791cdc9cfe9c5bdd5cd440bbf7aa3a6c58ac4c9502638ac2af7fb46cb3ee0d31c405deb4d76dccb3c36ac5c87ddc02bb9e5c32e11195921d1a41575cb4f1f99cbfb29ef7bdef5fb107e3621cce3b22f37d5a7173da32c1e25939347d0679146a72de2b83d61837d6f05a6fc8943a98175e404d9fe6076f010001	\\x67146fa5969e05c071643edb8ecdbfd3f65318c07ea35c108745f304be3ea35afa0349a35f02b83dd526b8d244a8ba2e90b52bc3cfec9572774cce42d86bfb09	1633267891000000	1633872691000000	1696944691000000	1791552691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xdf7c3fa7cb7d5a28ba3d8c9622a8ead20a6df9be16bbc0bdc9fe13cd6473ba8842b741ced2cb6b51d10d118667a84953a07cdda72f69db987a1c45da5c5dfacd	\\x00800003dfb381761d3cead417307d32754eca31f9bcb4fbe2660ee5728a0277cbcf51f30922d07964fef6f68867d25689a9e723d47ba44516806c639de61ddd6ed602df2458499181bf809357018ed8db6ccbbd05d2c4a0c770ab8518cb8e947065a21d2cd993bd07edcd8c0396113120687421ea9ab320aa5c53b823d29689a8222d8f010001	\\x3cd213e14f3f44f469eb8c680d7522abe623380c6c41e5c1f08c77d362e35607e0457501ea65c186ab5e8f91d389db1952bb53fb7b080d42476878608cf83103	1630849891000000	1631454691000000	1694526691000000	1789134691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	96
\\xe1502e70f1307094359e874fdb5124952782c550701f4ce5bf6399541b24996bfcc887e3f9b79d2e55790d1c9b0485c2439a4a3e832aba675c6c64d222e5fcda	\\x00800003aea697088f6dc7c5b8272f02fca8d99e8b5cd3120d91fc730a7b625c87474bd0c2c3095244f038e6c104a6d3a9499ac2bfb9f6b3c41a0568c367b7f41c01ef6e3676ebea91b43d864edbd1c413f2454ba1ef1951aadcad3f62245c19a8a36b2dcacfbc48a3533ac9c8dd5552f99fa3ce94fad67885abe180c725df5b115db0b5010001	\\xc69343096ef949ae2c4713b46d6354baea0d4afdf5327c9cfaf20f7b06e47226755b7ad664ed2cdfe8549346e2ac687152be05a56ab168ec0751f2e856a2c40f	1635685891000000	1636290691000000	1699362691000000	1793970691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	97
\\xe4083e8ffe2be924e63f0b6b6423f04c35ccae38c61aa7c41122370b958dcf45f446c322a53067de695e577b4a271a26ca685c22cd3214e7a2c88862671711c0	\\x00800003aede6727c70b981b13a24841c353b8ebdfd1483c5364e46973fc605384ed19c3a4d08b422a9c8418dee1ea0bb2269a9d943987a0268e8f5e4c0bec809c53203b8536bb29c8b640af07148270d1dfc5291444c06305338f23cd8bab9c28ffe109a2ef6fe51e9eded407c6ced2fe4358e807ac61cb569b1f5cc13d69680f746b15010001	\\xd023f98ac88eb49071e97ddc04d091a090cceb6aecdab8b7e89adbc126ca23dad0dfbbc4164cef23b5405d70f32bff43e577450d99de16139632bf3925494104	1661074891000000	1661679691000000	1724751691000000	1819359691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	98
\\xe66ceb7a83fe6189cb9afb0a02c5bed1929a8f031f81abc152063771b34c6994282c2dae65f0ba65059391fd404a12ef36f71fe9223ce72fd3a8400ab8cb8a0b	\\x00800003d2286266cd8995fa02ea60b30a94ec72c45bab46ef19815cfcfd3eadc4e9d5a54c1ceb5d88488799a835c5b48055cdab368218c0a5143b7e29e34f3f1591f825ba9482f62e3e4cce5d5811e45da0155c2cdaeb673d5280fd7244012ef0f491a2e44a98cac96dd557b041a3c1fcc19bda0597634bbfd9403243b44319ebf7be75010001	\\x5199fe999429572b9b54629dae7c671aff8ec5924426f6f84b1004fa629df4f627f9eb24f3eaa97a97fb334520bf8999286c496793bd9e5f9868275733b87b06	1631454391000000	1632059191000000	1695131191000000	1789739191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	99
\\xe8f48eaae2c6b0fc17a1c0e54b2cefa0dcb77bba320181adc183402136c0d2fc17d5688feb4bd958f8fc7ff39b051eb6e93decfe1cba52f5c731c6a968742d21	\\x00800003b7f1d8a6c6c3e94e2912f588927ba0e6a6217c0b4ce6b0902feba6e0dd56670fe4a9cb10d582788982690bec955a130c8b67fa138a8bf722b4fc1800093fd27c9d0c4e7fd2fb388c62dfdb5c88248bef1e1da4f4409638105cd927b807fd782ea5ecca37f60db9ce6762d4f25f2a6f90f32b0f0121a2b92c5e752229e3f06f2f010001	\\xf9cb42ebddc688cdaacaab81a2660b84439e5204fa12a0f9b9451c4131075d969899d8358b40523ca11ec9726d9c79b830361d527d1ff73b7976d37a2f320f0a	1637499391000000	1638104191000000	1701176191000000	1795784191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	100
\\xe8f4bed1c61a2a8a3e0a3a229d12c8d4377e68606a7c2e09281053e20f44e7fd37a18c92e35d2cdc41068cd30463bd95e30cb60fef304bbc370479acc71c76fe	\\x00800003cdc8af04ee243a6a83e58b6ae0ef1d2195c83259b79d2226a992009360e9fae3333bcd52aec9fa6a52bbf698a886979c3df56629296e3fd5da8535650c2c3523fa2f86a313f59a7a2ca25c272bbafc955e5cd0fdae0eb6092b7f434deb3197e4bdb5654e4881468cdf243e03e827e49a81593b3da00315fdb517349d31b025fb010001	\\x5c24e70f307e38e85ffe6e5ff36c41ca5fbe453cacea059f4783e78b80f5dd1eafce103b2242128c8f7a445b3ae919f49503a772ba1134e720314a7e7c5f490b	1639917391000000	1640522191000000	1703594191000000	1798202191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	101
\\xe930b81e59d4d50973cc395411e6abe1d025deb4a5884babdc7504c4aa0aedbfe473cfd91b9576f16031a48ef1d77daacacbe5845a1403cdf041cba2956cfd21	\\x00800003daf3e56044f8267b9def5a5b87d2eb4db1ffd0793d9dba89427cfa65dcbe6136b0cec14bc214b292ab0abd9bc6f0b8e517c30ca42502583bc36bba4a90d8a048911cec0ad25791109f3dce0d58f2b86d226a41d5acf4e889608cf454d27e231370057197432b5e4b4b91aaad325c7db861d1d1dc895f2113877ea5ae2bdc93c1010001	\\x46b23c8b401f6f2d4062ba9f2d11835f8f8f0a497bdf6492cb12cacbbbef3913e320c0d61c7368b9f8fad18bfe3ed51b7d714ef9c4847e2ce722282bc59d880d	1647775891000000	1648380691000000	1711452691000000	1806060691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	102
\\xe9bc7b7ecb3839cf2e3962514050facc1600a6cd158cce822e3fd2bc54e05e7e47bdae45695bd216267fddb5de37fbb15a2cdef0b03226c0c9ccd09c67f825b0	\\x00800003d14e6fc02c83ce7dbf70294c8421e588033c772bbde06d21d5f259047146f09a2b7b43a7679c28eb1268552f3927f09e15bfd9f282482ae5fa24ffb5d9417de84a45e548b69d69b325e43cba3436f168969f38045a36707886e99a057548169a8b49cc37ed61ebf22f0023f9a67ed1d127ac88441c8f30008ed7f6ad3a7c7b8d010001	\\xde1de03b4c198b1df2d4b841f4a8b792be4438f9a03df3e5e2ac1b37df327a746d7a2f862e18fb5c195426d1fe0865327fddb93e93a0036f53f6d84add04730f	1659261391000000	1659866191000000	1722938191000000	1817546191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	103
\\xed94cfdcf174c70f87060ee480a4170c0cf3bf5f15599420f5f3db5b8654255d81118305979d52066d20c1d37c50576c89a035a308390d4613dfe54cf9f32cfc	\\x00800003acec249624bd60cd8ef8256107dce494a2c4659fcab57a9467420a232f69875dbf46a4d5989005454ee4df27445655b716fc5baa3fa75ae0504e564e65ef83a6c85a40dcd8bcb1dc7551f542cd2545b1989a11072ae511a5033de0df9375994c90dd41c74602aa46717aa8813245168468e622b511678131c0d3d5027f31ffdb010001	\\x0efd50f52bec7f154860d52fead987f87a047d8f0a7ec4b7535896823afa53b5c7790c2254afb16fa3ff6874adcec254eeec7aa7f66381b35fd91e7ef17c1206	1654425391000000	1655030191000000	1718102191000000	1812710191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	104
\\xf4c08b9cab2f331f7c82ee40b9ad2e506e2357b8843010ab8e8908b5663531e635d7b7a2b2f836c3e9c960c39496d126cbc87e754691bfc02ac41483b2939065	\\x00800003cbfeed7621a4e1bb6b7896f9a39fb0f156b3553956832879a41b41f92cf1233378d66bc9445b75bd71bcf8341d34391093cb4c3b0d031091a2aa1f86057bb8a721a9d728f5cd15c27da7945b1f764c5aa3fc5c3b2dded1a87c038270143ef17407eb55e4392c2a1e9bd14cdaa9c7700b1168df32400074d020b5abcf52ee1787010001	\\xfe120e07522926b1402ad2298b64fae5f863fbf3239e2b0afcd88e77520a14798138a705f7176a87dd777b5b6e2fcfeb1d586617c86c902fb83f86e8056f6f0a	1638708391000000	1639313191000000	1702385191000000	1796993191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	105
\\xf6ec3f0af421311d4bc2441186b06009763ca25cfe23b37cbd4e0f49334e305543058609a7f6c86cdc7d9dd53a71aec81ea18a1f49fe06b9c480736917d02d9a	\\x00800003c5334aed00fd7b3adfea56aeaf937ca12f9ce0108aacdbb9e988c9d0a94a281f1830285cf81504ab2a6479bd0e536c00157b16bee4a81633ac7c01894b88b7a91e01e6f1ac3bf1d52551c0e40dad22cc53f7ef0ff8bd85a8a6f5aa37668e477b9697e15bb076f0e46f20a03bf84904860ec6ab2d763f57b6f0b4c06d94232bf5010001	\\xf03b28dc54bac5fe4f7aae3f165e8fb8173bf1fe475e86ff703df9c157f683fe3c263ece600b08cc3e9287eb26444c9e62ff63030881efa119289d11e5ae910c	1661074891000000	1661679691000000	1724751691000000	1819359691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	106
\\xf6785fdcd5ecdab35ceef500a8d0447fe8e63a2add33dccbd628c2c69f46863bb258579d361f67fa5d234506b40f43709767cdc8276db08a053887f1e7e822d3	\\x00800003e799b1d19826b3044c303dfcee18194026b966505af020f2fee89b1d9a706d8f59ec074ed6e2f8b6083793828ecafc3b2c678fa414f3de87a8703419e983275791d4a6e595214e3abe8556e2578290d88bea9b6af83b9c874a43c5036a0b28d9edf2acd782468e5546b85a924e1d5459a742d0125190b16d838b1c4a94c7b843010001	\\x18d35912245ce2015c64bc2e89a076c0b4a1f7bd72790946af9b5d2826745b6d21451d9931e47437a9b04174d92f259c5bef22cd968f4fe9748f0d8fc441a503	1648984891000000	1649589691000000	1712661691000000	1807269691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	107
\\xf9dcab18ad34721ad091c4b485a9ab49adb4a8eb55ba469c3e63f67c331595a97f6c9f43796400c573367822ec7908706635ca1b2b041fd197e651790f5b337d	\\x00800003b857230de7401526d7e817063586811bfc2008390297f4922508a566e0d6cce502c80d5d297d37528b5219b03e882df583f225f8d71c0cb47272513c0e039fda618d0b3d4df0870d3c8f33a94dac1e0f7e08752dc196fd7d8e3749c4f0ece947a5ba0ed96d3ae4f3ccc981c7aeacf3713bc0fc03e6bafef793921bbd9e3f4f3f010001	\\xbadc4edc70ed109f5fbe364fbbdd5bcf29d5b71016c83a3c195490d4914c677c4fc98a49eeaf7cc215bb133cefa2c8f06969aedaf71c4193db34bc747593fe07	1657447891000000	1658052691000000	1721124691000000	1815732691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\xfa9c9154191d4ea880c92f8bf8564874a0f5530b0f9a76a24e1900e27e24a7413f0519f41f950e9f6cfdb12edecf5d0b9c4ae6e201724b5e9bd6e8ec99de2fea	\\x00800003bb2f0edf65e2d99870545116efc335120f0b7859d43dd8994e7952a1986e196859f1de03b1734f2d1bdafb588f4742f2a0386a5a0b0b9443730cb759fd62735b8b9d6401250d8c2ed0a98a7c16d50a254d2e7df1bfb9641e9b662d89b02bd8bdda46b28436969da6baa3588c3ec886fbd53b4f64c05c8c0ac99877406e351887010001	\\x0d5f3d9fbe880a7fcd5f14cb6589d9bf69c2eea29af709a77dda61c0fe3cab859ba5eafa8a0c1d63cc024585db2513360a0b21a0adc9c81dfbe24cf2d1eb2808	1641730891000000	1642335691000000	1705407691000000	1800015691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	109
\\xfd04b9f2b7f46249f3294f85bccfd06b7991ef652171e1351eba471c4ef0776cf9918b05a74cbab77ddb03d143433d29f407be5fc18405d0fa1377b419fd0c82	\\x00800003dcc163ef6e3f8d20091b4dab9414d6bbd55c2ecaaa35ff2e08576d48ee5a6fd080e14f5f40242dfea34dbd2cd84f7e2dbe126252ff4ace7054c69938c48e58f5b7a7ec2d34b66fde0d5e6cb679bc3804f28b4bccb4c4057fb283ac91a9da503ae29dafdaca59478a5174cf0a34249f298c04d46d1519a9283b35fe6b87025b1b010001	\\x0ed14338a65209e28d7bdd9835a04a08ea545b3996b507de2f4659d587b921030adec1718dcdfd0443cbd9a5d5ce8380a2cb4abd76bd91ba4bb6666ec05e4a02	1642335391000000	1642940191000000	1706012191000000	1800620191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	110
\\xfe94861ea95ce10e868705a941f283aa0d07a34e6a2f32480e612404d0c9213a2c17f682b5dc9d7fc75cff48d4edb159a44d2d870dd8840386fdddad5eeff244	\\x00800003b554612198451cc230719f93222c3d087da1e151834567c0729bcf08332904effa6fc6765f3ebf5dfbeac37ce62e5023031bdc6b58c2dcee93b50b6188b090796a648da67f29363c2c9043fe2d34b06a193591a0ac4c188df73e0b73708912b71874f4d5562353fa88c919599c65350788237791a1bb611976b1b640b3c81e81010001	\\x4302c796800022d94085140fdb62561f1d35821d782613a16ea0540f4d68bb3ba0b5e672afba500ec1402361b9b060876f39af2272b634874b1c61b6c189bb0b	1656843391000000	1657448191000000	1720520191000000	1815128191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	111
\\xffac8ba162f1a8212ce78e5df2d188d98f1d99e489b2afa2bb7e912305506b307f6f3ac13d88d33f3a142a988a31545f46f1c815dbeee211102da32354bea92b	\\x00800003c59433f6f0933ab968b4b71e5c807c85513bae3aa1c1222c6b43dee29fc82f04a2486127d32c5bd66edb7ba52ef9cea340cfcb531050b27b3b3f4acd781cffae880212659d308ed28b120fbbfb28cbe3276189964623c7c7e992dc2c41c6d2f815a84c7fe88d798be3023c8b082dd876b77bbc3ed809530e356f81e747af9529010001	\\x18cfc8f67d46c33ed4d9e6f919c2542b4989a2b73fc0a56a124def5c556bb48a9059ddfb79ca228cc233f532d09f4b0cefd9f802ed4de8079d84126f8283a107	1647171391000000	1647776191000000	1710848191000000	1805456191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	112
\\x00a587e15f71aba8e06fcc0d84c01c469a7ebdce0d7f914664379cf9bb5c7ac0ffc094c631b76d2848b4485fd87be47b6d73d3e0f6a224e1e8c17d5415748f81	\\x00800003abc0c28dae88965bd3b8b0add30e5557462a343d09b5fa46381d03e3bfd6ffda43467bc442ef9984f5081e426d14f1a8b1cb8cfdc795acfeef841288d72cccd57917697300eba53667250f0ad7fa637a9dfea5e2c0434b445a2018785a73452d391c6d3362cec2cb2f0910293159a1b20287c6ef8e21df2c071daec8fdd4abdd010001	\\xe32847a98965d3746dc3ef495b5bb8fe76a05c5012063bc6be13dd2a786cdadf91592e9f92045645fea8c0f9eaefd684ec59e12005313e89e008fb289098450b	1642939891000000	1643544691000000	1706616691000000	1801224691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	113
\\x0459c9d90701c594a8734b691669b0922ee6eca76936aaa22a4bbf4e6aef5b990252e52d86da2a12c4529eb9a9cd9fd4f521c0e92ce3f69f85a4a1111cc955df	\\x00800003ce7d58cd91ad682779a4fc362d961c323aa84f886e3448f0694257f6ffbbfd1add4f33fd5d7257c8bcb64df6b56393fd35e81266a903b1ec9e51a44fceb57d8fda20885fbe90ca748513c62a6566cf12bb0c826b45d3043cbffaed6135b09c4f51c8a7b012960999f1fe5337043642204e44e994ef0aefd6fa4f7df5ed362235010001	\\x760495721e1f5d4e3fa9b471a4e8d605b824f4ba4e188601056c7213e732a79d849a5e78a4dee3c45fa5749413ce7d02c275d0c374a6e14ef5da962b14217106	1660470391000000	1661075191000000	1724147191000000	1818755191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	114
\\x05c9f8b8b187883ff2e0262014d9b04ba6ba399703d2bcfcf52083875fb8f0662d9b8486a56db8f25dfc782707eb5291dfb19d51f688a9939c533da783ab4acd	\\x00800003e58454de15f8ea4e42b4fc670529aeffdab518dcd8c1d58411989b06aaac22099c75b2d3d0678bdc61ee25b069442250fda07d2ea567e2b28de1ccbdf5e434467d0f5012a6363bb8d0430f93d91f27e3bf04caac44238fb562976f261b7e3f40478b445e045bdef9a975ce27c56c3bce23ab159f4dac469d0f3724ce4d4848c1010001	\\x73694478e84796eddff52e5dc0d49f5cca77d95fb12e5e98b140bc5148d03446a9e34528d527c9f88adc87bd383010467d8b5c83f468f4e6e7628bfc9769020a	1657447891000000	1658052691000000	1721124691000000	1815732691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	115
\\x093dfdb75e241d5bc76aaffff78afc73a12b131802c46e90b15a4978f9f8a1aa645e4db6f821767f184cdb2ae28c7afb18adc45254a82d0af3eb7e7421d56db7	\\x0080000392871e3b9402b1df4037a559043091611e2020d60b5033ba4fd5946b05b88e4ca2741d4c6d1f4accacb0536da7ed5d24c908f23a1394888424b28bebe5db5c05634745bb734f9ac0b389123b58891d1d18bedf201936b6fea07ac4eb6b3099b8657f8cab0fc24cdc3d1f2c7c2000e16c89030c9df5fe2ddf37859fdfb726e8af010001	\\xae85a5ffd2beeae7f712acd54f4ef937ddf08118d9d0d043e82b19c419fcfb0ef6220e54e426f89d4c8c85c27cae2aebd86eefc64b5652e5ea6e1e403216f303	1660470391000000	1661075191000000	1724147191000000	1818755191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	116
\\x0a555bf726ad37629b9147416ac12537a5ab16283048eeab0dd3fcbb76e74423f35e34559084dfb4178dc8bfc6fa19ab14da110a27a1976bb25ebee14fd3f52c	\\x00800003b601292240b59fa131b6c6041096e5086ffbc4a27e656fb04cfc67ed8d0869090c106e01dc5623f4a635103492bb11c6d900be425a240b4e99986f8d67003cc72fa5b54c75e55c5c77f3ddb9a60c5d1b5ba0cfbf47bd649c26cd5f4a902e6ffc2807976cbbe1b6a5ed9acb3b3aaec02513cd93eee33739cba8195f9530812651010001	\\x483ec25c40fcb5c19d1f663324266207ae3b07cbbf8d3c284b41b10b711a9a2488033315431ca6c69cdbdfcb439b96ee08581342a926f699f7c60bcc5b80aa03	1646566891000000	1647171691000000	1710243691000000	1804851691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	117
\\x0b8190e06b81c3538cd9c6e4f76e4c935d5678171b9d9d2a5d0270e262c2d1c68679323ca0e9bb3c187216e0bf4329d03a3c8e1ff48469d885fd4f082dfd78da	\\x00800003c0c8bcbceeea13847ec3190755f7dcff2042b633ebdda6a0078c6f77617872f613adc6c0f78f95fe177c1844c649689986cb6427802912905111d3bafc1b8c4ede1ae6c5fb0dd30ddbf5bbbb9f75637e2e8fa967ea97a0f16e23f355398fc4b3ac23eec407bd668974fcd96fd0b9be4a4376399cbd3a84ee9d014eef09ece14f010001	\\x422d778847f8fc3ed4abb678f54df8102e3b388f5253c183c38b41968c22eb40e202a520373c502fdf7c773eb14c533dbab8bbcc47a0c5e5d7c8308e82ab7f03	1655029891000000	1655634691000000	1718706691000000	1813314691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	118
\\x0ce53d7618e3ae3d27857411b1fff13256c097bb95842b882610ab97e1e98998dc3a21066f3bd67dcc48ce94d26488617d9daa9d750a485a6f0a150eb30b1453	\\x00800003d1c548722c946b0ee97e50e81623d89a11ca2ff3ec3c494946e3a6e129173c25f0d88ee2976ec856aa500610e9bddc4ea2a5f22c2834b376e3fee4a6b60ea0e6c38494b75655e599519fe84e5406ef9c047fd81563c868e5a763e456286416127e77b981da8b7203f63a6f4e1e600eee239f5983e33d24dfbed80ebfebdeaab7010001	\\x31374f885add0b398f02c5e158ea3905ae8f240586fb2fd11fd2ecd68ff851b57f52e8d8d37300b45f8d1c4bb10e10113389a69021687bc683022c6548e69c00	1644753391000000	1645358191000000	1708430191000000	1803038191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	119
\\x0e4949d986eb8953a43979f3c216191f603f41b9c7d5a4b0049bca3d2815bbb1b1b43292bd8add8a4f4bcf4e6a43038a034414c7ea97364ff16449f86c656a72	\\x00800003c00ccaeffb8ce2c3a7b936356dd3d80fa89c9741c89f2539563b188c7f80adeb1b568c438c783bc694d0babf36bcf51b6e5b008b02b0c5af5fe81c71381f76800053f1d820f0ab7cdd66962992b4ce20a091e9a46d46d5a7c57adaed8ad88c16decc644a71a89ab663ae431a904880b5f55a8c5f53e1b77c6285da242189a24b010001	\\x2a5261303ecffa7617d02d27f898f4349074d1b08c2a97043666d9e7e484e71675f0bb57fd69af1a807feea07d4c2a167caaa9d7d071b18de551faafe5dc5704	1653820891000000	1654425691000000	1717497691000000	1812105691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	120
\\x0fb989d6ac83b9a2a1e5307b43fdb433306e5687f15fd677f2346a2582e97a249c643799b6d4a0d6b61f899150ac40621df9c2f5fb53b8a99ef5fc6c7be65032	\\x00800003bdbaaf032570cdb31862843014b0f14d36f200f2d33310ed039addb89120fdbd7ac261d747c02c990597c611a27504df52b724d8c0f5933a4e1923835586391eee63da06c57f8a31d84abd34703348e2a1f5b79e0242641c78067918877e3358b2c7434b00e6d2b9eef049682309823a3eb550bf3dc47d0dc66d9e195fe5b6ad010001	\\x1349a2124e5162b81418a76346eea9790d026ba4ac5783bbfff3705f36d35d55bce609a813bf259a5b23799a472ee265165a4218369e195a904270fd32447006	1645962391000000	1646567191000000	1709639191000000	1804247191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	121
\\x11a17371ae67c7a9863899f7ecbab76ca1fe4041d3e36bf9ee5fa4e5115ea77903074b285aa58044b12b30257927667eb21a1327b11d5ddb52e3cb174ce9b81e	\\x00800003b3a7b09f0773758ec0c7c2f5867afe92769d37a52081b85b10f6f212ee40d27c31c907d99d44a6ae4f64607e254f581d1d6be414be0182d922c55301eaf39fe5424c35fc0a949accf2839fc86035fff99f493b9d4ab5e4274726cb44aacb1bc41dd190b7789f57cd1e1d0dc66657683f222b97afe8afeee9b1c5841acb6e1233010001	\\xb3058d89164923bc309347ee3bb7a05907ae21e8cce263ca765c81adfb782bf7d8cc7dc6b369343aa4f4f827de061592d566027c58bb6426969e0d0feb7b870b	1647775891000000	1648380691000000	1711452691000000	1806060691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	122
\\x14fd3eafc2537e24e7dbb700919ed73a3469a3351f982ad8a80f556baf283b1a11d224013503dec3a46d3c4a4ca8384dee27936a08e92f111241bc6862a3027a	\\x00800003e6037e10e8dd1732b5448ecbc1de7c70ab6d7b3f1f0af876e3ffa9987d25ded72d7d9a9dc710bcfa9ce09c6ce791923038dd69360645b7d5e52ba137453310d172553cb235f377857db2effa72ced3d8d5e2ceff5d999cfbe87528b7798d136a4ce7e3f7dc4d1d23e474ebc673d06238e6fdd0c7239d38b9e588ab569c320777010001	\\xabddc5d849c8b2b7bccae72383a6f3be8c7952213046aaa261c946575bb1b73b95c638dcac13514b2a2c9e773d619d53b1e5aed199114820e2bd13d84c525002	1647775891000000	1648380691000000	1711452691000000	1806060691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	123
\\x159d309125a81ea25254e8f69bb0773579a1f5e90c5b2528e96fd3f9b0fdf9b8fe263f72562d09448b6f614bef3badb7eecb54a33a2c63f2442bf5124b56e786	\\x00800003c38b806b4b6e1330206f0fdb15db7733fe814bc26391511048b9a8f9619e62c66b0ba6b16b6bfcd15f5b01dbf450e9ff904d0b3cb7d53b89d1bd78600f473405015444792fde41a721999bc6f8e5ab468ffd73d2b22c5ec98dd2daf5128816ba3d5035a7516985700b96125a1d0f1dda24c9ea8c85b19b382bba7e9d638e1223010001	\\xba61660593b4daf73860deb2e15d4d390e1f2ef0560293155ca97c5c372e329b4e15754f37430524f9b732d8d5ba4e8ae1f84ac3da1b9e782134a7f8ac5c9101	1656238891000000	1656843691000000	1719915691000000	1814523691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	124
\\x15f9030ccdf728b3211688089d30c56841bb110bd92b1e5bd814c8176c9f5cb6f05c15deafc277c0a8a78b47bb29642fcaf2a59fa873eaf0bc3bc6b7a3ba7d63	\\x00800003bc3aef83f693f8a7a68100250bf108442bc4008ced747a21a8e65dc2bb218b6d24cd2772c90610248b5b86a591e504b6a9b4c5408e0798b2bf33ded8554498ac0f18d70737812536881e6701d1d6cc7d85d4384f32e5f51d207e6553164e0934a57d747d2697cb36612f009abee7f9d8f100ed2534dfe707fdd091c46487340d010001	\\xcafa837fb0758cc1630d5fcbe9f2efaadb54ea760f23d11d3ba4bf30ba01de32d21bfba4fb97668b1162e477f461941dfc81f44f3cfc652bfdda6bd39a420309	1638708391000000	1639313191000000	1702385191000000	1796993191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	125
\\x17058d9640b38bc3f4f6407bb0367f74272a1132aa6c4437e2ad56949c33ac3d1dd74079b67635afcec77bd9dc4d8790f678b1dd00cef09a463d28d919d5465b	\\x00800003efbc96029837df0217a1e448cee3f7b845c09aef053970932671ca9393d94407a080753eba0a25467b1016bba5e9d912874f67858d162236d319942a2a72cfe4911ec6bd74eb37b3ab66fede52d08e8737c514bbc1b159e77bb7748d77d091f8a485f5b5beec128b4db286b5060e6a33e574d6ca9d3b74afea3a571eb2aee591010001	\\x3e37455c59c19900ce5b6f5fd796157090b9d38494a536e34fbbb01aa80cd93df2fce36314f7f07724c5a7184954e8b5e4c2c55219a5c878a6a0d93bb5413c03	1659261391000000	1659866191000000	1722938191000000	1817546191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	126
\\x1b3df176a3b44071a0d0a9b53408650a04dfd197818e8452068421134882c0e7c75dec9fdd72df860a431b72d01fbf3596410e646e5054b01d9b96cf204d50d4	\\x00800003cdf712145784d042175a33d77a4b5c8689eb659ecef79fdc9d380cab94178d7e23880dc2730633f74bcbc696afbaf8d869a612e08e74f3f1e608368c68de3fd6c162b79ab65a4e9bbff65e2bdb0232e32317734954cbe445e6685d8e428a2e6806a1fa4a7138772d7d07a70f6f8c4190a4855585956dfca10962faa4c5b6a941010001	\\xd929097f4d677a45b49dd4e6d5f6df07e8b8f936ce2b85cdf61af8de87d77bef56b7c2845308ec3fd2d401a8cec9612ad810866b0fac8611b3fa9c760c8aff0a	1639917391000000	1640522191000000	1703594191000000	1798202191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	127
\\x1c1953d84120d310200c1d1d52f4a7579b60b8f589eb3e605a7240a9054fbd2aa3716a70e6e213d9de57bd605e4f5cd1f68ea37eb3269e935459d05e8816ffae	\\x00800003deb072fd81acf4f7d595c4e0629059ef9ad268644d24a1a620e4bafee7b891f9e0d0b67477ed614ba02cc50b078ab94dff6ec3efcbe33e3f3596e77b192d44adc1cc21293d805b066f75ff6047e9edc9efb0abf1c1cd901f6abcb52d5b440d4f81e53d176ba99aa0518c1844c8d268fd20e5a27cd0edb557c835c5e29523eb67010001	\\xf3df0b554f6ef7e62a64189d272dc046d9930d209559900d7d28f1c64aae70be9e4d6145b4fc975403b4e3578117cd41dbfa84f04e8e3915416f41c3544cd404	1642939891000000	1643544691000000	1706616691000000	1801224691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x1f394a06b9e1377d7c222d5e9a4721858e7e5282c7c59311c2fe2ff2f0a974cb72bb2f7497acd1e9b8e2e0034d467624b21e28f253b03de9bbf8ff0bdd70894b	\\x00800003cb2b0c675a96b914c19c1d6d9f044dcd3225988445d04f4c5c9049ab2f2a5d65fe86f6052fc6f8e29f975f67f9982dea8d883c9431aada0b6c0402d8964f7249f16a09ad5be6675043350b2a95719d508e68e707c00c6058e5a3936a110586c3bdc08cda1fd74696762050b759892553ae65f2c083eb20f5bc27357199de3877010001	\\xff41843347826907d545951c8969ae2a38cca49c37afe3271df720b376f69a7eadffa03d6bbbbe93cb258c4659a19742e9fab8f31c444eafc8657cbba84ce802	1630849891000000	1631454691000000	1694526691000000	1789134691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x268d6861f0a39144edeb9a71cb671c540ec107a89cd22c777ff16680d4c00c0c79d33133d5a181d2ecd6b33b3c7987c5dbd735e4340eadc12a67116df110c3d5	\\x00800003eb8ebc72dd22f20f7235eb749b28c12e73d151ea3b6aa36177c09b57fc8dbd0d5a64bff4e5ad14d0ea86b6f584d778a23ed8cc29d77fafaf3a5decf2a53fd564a2dc106790496fe23839a8e5ef236e8089a2a5d5007e3884c9f0d87be616f1aa5b6766eb95da094fef22c48e4b2c3a4d2ec0311c1c49453cc63a2cbc0a08c965010001	\\x1f8df4990ff843370e81f5d45c39a4dd076791fc9f7b161f81c647c50ae78ccfcd96123d5a0f5eed4f75b301e0252cd239e4f0fc89a71d649a4027769e2fcd01	1630849891000000	1631454691000000	1694526691000000	1789134691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	130
\\x27a14945d022c108d171bae53feb0a8e9a2b7d0b51b5951dc9a596f0d91afe5049a715b48bc68b96b130d517af8b43910f14508c2b7d87c939649856b94cd4f3	\\x00800003ed7fc5ae81741e36d98f466c8b954bf2d9ac7252a1759014715349056269001b1e57187a06c91d9c247ba1d9afa82ee37ebe01140d950f131fbf2411c5d1396b442f4768f2684f3558f8099eda1aa3fafcb669541478e957b9013819f8c8bc022d164d892fee732aed8559467b00c481346814be46d545a6895458a278659af3010001	\\xd5068505a6d042b3778d6d4f1d50b71dad9702be95495df9d656f674eb89f2021afcbd9767eca8ec7ee5770e62171f83c7c03db84bd07c44fed3a332dc3fce0a	1660470391000000	1661075191000000	1724147191000000	1818755191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x27b14ae7a13a520083a2edcb24a98335ffd928e2aa6c380a1ad13599be0475e8f45910640b329f0329ac5cfcd8cdcbeaeeaca86a60a88bac1ce78699d85ec70c	\\x00800003d45ca7aa88c3da9f4f33bc5c36e6d24d52bbd6abdebd8f6ca5a2249d433c1d7cecd7df381746d35265b3f7dc3c3f590ca4e64ea2f6e7e8e66a649365fa5d79be9a541d8b550021e268f64c33ee06de62b3c29282e3e3c9d7c7cbd674b21b6a89b599b12eedb8168f71b0c35c745a2de5d89f26d71203be39f9fc7287c8beecc9010001	\\x336a2e0c6d174244f442d8aadcfa255ab9f95f3b6fa4fa8a5517912489ac07a345850b6cb143690b5a1dfdc7c61836d4d2fc66c24c635527140d9629ad638b02	1661679391000000	1662284191000000	1725356191000000	1819964191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	132
\\x29bd26928f6794f629e0627175c6d0d9ed80309a9f259e91f4b05595f8154985522b8b6ee889aaf5b7ca1d0ea1550105c6df693c8c306b784301a01b0430dc6a	\\x00800003c529f89436a2a9467e0fb98b0b38adfc720610b4b5473e4b19f7c12b12d43006a39a00ba16837b4e5520fa95fd654e552fef86d40fb52195348737247e9a568e280b57b4d4ea9c572dfa9eda5395a9a7b31f1a7b24745a9d92cd38bdef3d971f309ecaa42bf7cf00ecb0a48b84d60448ee9a4750d81c80063ddd7ad6a69cb981010001	\\x69d686b9f41cd8bc33318af133d8e2288ddbb445f51a6d52df331bb855382db2ce944e11c378f1c1a16de3450098bf1f77742f3a11a583484e0798f61d808204	1659261391000000	1659866191000000	1722938191000000	1817546191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	133
\\x2901c0715c516147a06c85cb52e7807ea9f7d292d5cb2fdc39a2783f658505c5c2e06077e592b83e8e141c476c9a798a326f21a97b63c2f153a5e695f281c348	\\x00800003da49243e939cd4eabe144f32c8375201f35fbf843d45e89a2e0d316371da8c005bc1f41d624d9cba9503113aba4787e8b77bd49a52f841dcc4b923a2e2bfc6d7a53a03d47ceb6174aa22f8f59fc20b587cd72755e736f58b7c609a7dd50f746f70247f59af167adc3ae1598db5a4cbfe97627cdc5fdc3d484aa5b23c8090dfcf010001	\\x20567e7ce629f588ca4abd784f8696fdb8f884edfe791f9a4afa6dc804ffc9500cf85c7234a591d6575e913cda145847404eaac7c209d30baea40853ac4e1007	1653216391000000	1653821191000000	1716893191000000	1811501191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	134
\\x296da48e033cf5a72bc0d393f75e1ce7e8ac8e070e6af1aac7ff1ff18807762cd26752b411ed3a0e6d9d19d04f7b7a2369ccc01c5f52096863031a3481a44c1b	\\x00800003c4af0878519249a0d58b5433f1b865d0cddd5469bf0d9711f357bb0bc7e4df618d2a8293fe17a6331001ad9e1b66fba694016107f63c9d7f8be9dca4e68879c29e6b5a81d27f4037f85bd0261f6e767ed426d4f03219b33785eeee4b7114b391a27011bbc23e7dd734a155f2712fab96b704a8f550de5257af683e876fa2a0f1010001	\\x86caebcbbc03056f33303f718e62c814a6b223b7fc21c5149d73f3f707f69e1169a101fc849f341d820946b7e1369c92239006c5b53caf2c7948cb096770d202	1634476891000000	1635081691000000	1698153691000000	1792761691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	135
\\x2cc157edd05217c158883a60bcc2723ea22f13c88c087940baa234d4e9c74e766b16ed12f074e50ca3e5a769f7071ebe6529ebf6877b5564933b5ee4b5368e6c	\\x00800003d9aed16d00e0534611fa3c7b5992e2c10903636164da64306e1edf30ee2bc894f48ac225656fe466b32a298183af2bc6c0d1d574dd8d8772f012cbc680a8ac0f7d09679ae5127be497c321b9e902f32eba5a82bda0afb00a5521faa1110dc4a3140a6d332854fb06d23c276ea29d701f63eeda4ccd32d816d7ddaaf4f03cf15b010001	\\xfcdd7957965ae067d201e79fdb629a94e1536956772271f622ba2c0ab88202bacae163d68ac98eb8db61c98995ef6f16e7b1ad5c8ff5c9d3cf78f35bda384e00	1636290391000000	1636895191000000	1699967191000000	1794575191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	136
\\x2d41deb86da0a08a5482fbbc1de0552a75074527a1c9f8ffc7ceeb5cfbbda8c4d91fc8073a21e1e8cadb32315cdcf0ad422fb7b36ccf5fff0259d5b8f5756af5	\\x00800003a4a23346efb380b4693dce3b5ca6406453ea4446ded2153409055c17d37c8bf3f7e31a88aa5d9a2ac4bed0bc4d5bffd628985e481823f6c5e76cfa49b1f63f669bf39a786a733862aabe035c6198e834e966a74ec8abfbdcd915963ff1d74b95c6642173d4c10af278820e06f304d9cf9832f59a274812a2af082d151e9189e7010001	\\xeb6195a92b2612e6f450dda576d576a75910646f64f5390f4550daa882c77ca77681445688191dacf7f9c1ceaa6e0ae796c723c5f57b2dac6abac89293f8c20d	1643544391000000	1644149191000000	1707221191000000	1801829191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	137
\\x2ea96200450d22c8c9b2bf6593ed1e63a314a044f8e492234ae05f22d3f99a19fbaf4d92dc8a618e9b1af318031bc7a6adf45c1833dbbdb9c693b201cd53184c	\\x00800003be571212633507cdb3e5fb30756189179eee6a0ed7e9f8e3672839efbed568ee9dd394bb9b00c1ea91c5fb3aa9756dbc58290804d30da92860947d626e1eb2c798ad0366a1ce2a63fc9193877a85ff246409f46faab7988bbfc0e5539599fb9fe7529bea1a5821a966734c86bd665826634ceb7276e144232097baf29c2ddcad010001	\\x37daac7bb25f064adba6fa31d33b1e53227ef14b4e08fc0c817de2eeaae1701e6cace8c1bad63d692e59fbc93d797b1fba30c58496ab59bd5e59d380508a660f	1661074891000000	1661679691000000	1724751691000000	1819359691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	138
\\x30116cd1836d99f498cc4ebafa06439c0fc562ed472cf4bd81297fc947e1d7623da142f6e2cc3be620b7aa6655e1bc61db0fe311067992d437befe6b4a4be909	\\x00800003c7c47fc52537120f28d17ab07169f72a6ad68c8801ee908733fb24af2817380e4e5a1f62c41f9c97790d9928ac4ad6406cccf1e2ae9cd645f88a33d0a7c5b6421e5ace13721647b57b3995d94fd5b861e6a35d339a883cd4fed9548c7729a27875461d409e816c20b5d608e3284b2f8de1ccef8f8208bb7241081f34ff680843010001	\\x25ac3f5743ef0be5ca4c0de22266c425d0b21f08018f540f05367f60d84139ccc9a081e1ebbe5febe06134e994f319ca427a5f8fea1ddad374bb6a891d431609	1648380391000000	1648985191000000	1712057191000000	1806665191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	139
\\x3741d9b6d06a308c3891c7f93869136fe5dd6a5fc3d7009808387b6ccb98d9f8337d9b959248d05e96f78603f5395e19bd8db654cfbdfb16b5097042f37db082	\\x00800003ec18273d755810fc4600ca3e43770f435773dbe641274fae53640e3d7460fda0200920921398155c0ee82c87a34f3547c70f29e249125ea2edd42e73f7ec7cdb788c1f8d09434a533c060f25d7c0e21fdf4c74aa144f0eca786343d9e22e37a0ac697927ecad314105f843abe60ccec4773fcfdb96130327923eb5402d69b089010001	\\x20c44c035e7cb274a254bb59c0efb1e993e1a6cef927708699b662cec6f04f0a7f3d29246d26f9e492353be5e0f23eb2ffb0d4d49899a9370de9773bead4b70b	1631454391000000	1632059191000000	1695131191000000	1789739191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	140
\\x3fdd95a242115e9d62e9920095e2a968f2405f038409e988c1768c419dd18542f53d893a35993bf60d0b185d16ef8b888493ca0d9b95747d6ae30b3d1e7d7297	\\x00800003baceee05afdfc50a35931e20f85406575c21ba1ad5373d1c5bb5ea2e099133d4dcecc4b6c71662565086e03553e66dd96d464c06eec82f44a13b82a46a916d349f340c84d5a1915c5befa3c9562c29fe5fd2509921e166284a2006557c3cd45accc38afe62bec5dfc8d65ba80e32fb388a767b390bc379b4d4ba4f436263ec19010001	\\x66dbb1d5d90cf98a7c545bccc39cb05d1b3fc8647848618506cc6af36020a0d51ab40b6048601263d6e6bb2091b90c180a011671417a70ea379aa11633945f0b	1633872391000000	1634477191000000	1697549191000000	1792157191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	141
\\x3f6dcb6b6493fc4b3b34ae3dcf7910efdc1b9f943cb4b696100a68e47584735662232d04894b3c1ea10f30d36f31c2d4238d78d6e43c546ea320b2f34ec4bf1a	\\x00800003e159c33e85c6d809f49d840382bbd7a3b901d21413922827ad3c9a7a70fc27f578960d4f8ffda74358b736a0b6ec51d71588eb0be7567bffdb79fa63425abe5104aa62fa5c87cf4c88549fb948af4aa06f307132d7dcb385f555399c3514732cd1feb42361a493bf393b69311f796a526af554a115f6bf2fc027dba156c28b2d010001	\\xf64a51c5b63de51971bf3ed3c5fdbd0e866cdc1c46ee917475faa7197a96200e8c3a27e85f85c6fd4091accd9c9dee86b99eec65c4e73f14ef3e5507d864ce0e	1656843391000000	1657448191000000	1720520191000000	1815128191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	142
\\x40f9257fde7ecce422fe5898ffca9fa3e77c8dffeed833f9dbdb55ab78b107be29f16c3ed74cecceb9b0201774f55c84398da394e6d98df1717edbaf125db66d	\\x00800003b08223e38c39116f82d2b4ae80a411f714e3acaebb8a136993180688e2472d4d3b97d50a2e449aaeae3b1fed7d385cd79e89bb64b6951b26b1d38e723e963ebee2ec17374f928a121073f3ddb059c7e77c1c1facf34b9be43b18592e4626a2594b689c1a6d145b0bde560b12c64fb5534ea724b50cfa50d26865d0ddc6dec1b1010001	\\x91f5cf60000514487d4f871576d1d3f450ff12072afad76f526fe867ad57843568d5d74eba8502246f9344f675ba5548e03c0dbd48534c3a147926adcae1b80a	1646566891000000	1647171691000000	1710243691000000	1804851691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	143
\\x432561e71e82b7b557c941a6436603144c6ab633f4d84dc85a7d8b94ce52f1599371d2b7bd301e83845d43ec851058dccb1ab08913bda3883e5f399b80ac4b1a	\\x00800003c31fd7f7780096742e4fc5c20955af58ef643555f29017969b790415976ae74e29378915fd58e2bf0edc901b42c524fd2b0d20122ebdbcb1c2265c912cc4f97100a66bee7a983f6aa6145838e1f6a4e314c246a8da895e449a8be3d11d6030d670ddcc6d3b825c6c0728427b672dc30b0a0d59504a3f29958ced8c4f9ee17bf3010001	\\xd7ca868b4b2ba9df8ead293519b80408fb9562cc564fe4a40b9e215dcd48d5b60c35fc083b55e2a44015cc02070f40d078b2e82abe6cc5a4be0177f70f998405	1645357891000000	1645962691000000	1709034691000000	1803642691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	144
\\x43f92244e6a169b215548fcf183e1c90f1d2ae26a7f701cb449276aaaa4ad27b139c0f4655dc978795b54136724e6da5de56c61d6afbbaaca7f80c1d1efca204	\\x00800003c2a6384b6c7054337c48abc7dcae18ee0ae1bf6dc25dcd4991de32f2286034bafc28c0b297a592d1bfb284d84a145971420e13bc7d07286ad4d2c0732da92464aa15fd5ceda9c7099e900412186fcfad5c248a2061b8e46ddd13479b6c826b819422227639deba705b290baa9db0c1bbad34cd505e37d52e51796feb802acbe7010001	\\xf15aa32cff74a777362d7bfab710127ab4956496b427135a1f56c9894f74df85ff7e7a547f345aec316b4568581724200c8b7cb08cf57c85a8ca2781e3ea9c06	1632663391000000	1633268191000000	1696340191000000	1790948191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	145
\\x441d68bb7d269526c2c6ba976fd6c440a54f4592a5c3686faa0158d947fac901bec7b5bfbe06c2e6a26d8cb8c792b2690ab884789e6e107479907996ed584d8e	\\x00800003bac12a7b1d7adbd21bd90e63af420e6f94efd5729301e26a677f12bd2c634a42369b7437516d88e5d183a09f5a77d7ea48bf3ac58b0bbc8a989b76d27b6a4d61af4936c59c957ff6cf9684bddca30c6840db85376c40ce029d168b9bbfbcc8dae82ba0f3be78c4d080bc95696007494598bb6f976938e3f6a7e5ba336f34651d010001	\\x88da868131776a348625ac1c729623677b9c3aed8e9ea0f4a85e41e858dde41df0d8d798aeebbc877d06aac85be972f56fb8df9938acee520058aed6ae653a07	1652007391000000	1652612191000000	1715684191000000	1810292191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	146
\\x4759dcdb8c62a36f9cbf816f27a61ac74eb0debb8faf79947d8aea20715053a895a93e1c0309589f40064a303de1847e41572df78da45bfd42bbd81b9e9f67ae	\\x00800003accf66747c8e4f32aaecc111ef36a2345ef0c4b05f134433dfe6fbe6d2ef85537a9de1719443b4010fbac7e797395f1d844075aba8f07e282950e5754265f4a1e3863c5d7a0e523e2fe7233e8a49f527f8f274db6cbfe06b120cfe64704d5d5382d074af28c15ed34402c06b2f5bc9a107a61185750b907f96bba7e43aec0de9010001	\\xc6c1014a28f2ee54cbd8b2feb66d2cec55cb057fc4a3bac5c0ca5d5010149def5bbdfcc86c4ee99da3242d739f908370174457f10884cc6ce8631e31815df60c	1640521891000000	1641126691000000	1704198691000000	1798806691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x49292c6d565d04ef097d4fe3deaff4cdcd81cbd55419affe0d84b0d8f04d124f4172518d928526015fad4bedf5623103b08e4585f92bddac4dbdefd13f92a366	\\x00800003bfa2a8642669758553e02b2ea33a77ddd9951204e449be3440bade5fd3763f295ad537c634b59d8425147f002704cc583e3eb40d0ef0807e64a74934a2fed52f3d487937ae9fe636de35ca6cb03cdb74caabbf837420227d1bf046e1396d51ff3fc89076a2d5fbc3a912643e0e88f2143dc547b9a7d8993827fd6b1c6c2fc357010001	\\x56add9c94510332d0995bd7438b8453aae5b4b0f1f8fdb001451e44c962d61ff02d08a0b10e6a8038d781a8456d98316c6527e44df2e9b7f3c34b522b0658c07	1655634391000000	1656239191000000	1719311191000000	1813919191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	148
\\x4e95cdf9ad76f90f3b77b3932b7a16175f2d1989591e454c356155d4273e65e0f1f0dd2fa2459f47d3f85f91d2750acd0a20ebb12d4aee04e408692554c04a5d	\\x00800003af7c87b21e4e958175da67b713034994dae9099123d99bf732193b728e35f200208e72b459aff738ef1b5ee60332530db9fd90bf4759f4d45c9f1a1e21dcb1b4795fb752ab80bbf4651ac17da724e4eeba1562d89be0b44e4b2e0b860655b6d04e835b68fd14550727686fb761e63b1b2e711b019ad710d5a532e99494ac0159010001	\\xb077206da12991433cf6c984bd81e9634b0aaf787873d1de3a3ed7ea3fe323e3bb8827ac44bdf0343c79d1a92ca282e588241e78d14797656ec7624cd2d2a90f	1641126391000000	1641731191000000	1704803191000000	1799411191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	149
\\x4fa174de1e4276e048a326446240a745a2354e5c6c6a03a4bdb51849d7a81e465d97435578eb816005b4f9636f8c9bcb0d4c4d48f0131f80a5bb2e89b9b6e784	\\x00800003b9deb4b1a28d6d4e43f0576336208f5a68cd4710f0100996f83ca7ac9482503db3683bdbbc00587b0d3fe402c70130ffcce80f8ee667b4d4d475d0272f24faa45f5c4dfd9b9e0fb8863d8854e5d2ed2c348175139397970c199f187a2d204cd78ac7148722ab3076eb2f8459a9af4e75dc3dd2eb5e7964147ff9d13f08343d27010001	\\xc63c5161d26d55573b91a3a6e55eeee4ae721493f6be8e78e31aa0bbd3fcb43ff51335dfaaa01241c78e2567b34884026b27f87dbc03434e3835e38e1457d900	1662283891000000	1662888691000000	1725960691000000	1820568691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	150
\\x4f4d89fd484fbac82ba87b5c90acb06cbad12ca56392c223299b9775aee445a6a6e39c7f73243c5e427b2e60ecb424551429570ae74a2644db996d7755506b7c	\\x008000039aa940ca723a28c00f57806edf3b0becff4ef087b734f765afd5695f300759ae9de9bb6acd331ae4b23abffb220945e2b1658d4ab096a6b9320ec5162f146113b34e4ffb6d6ed0b217bc8608e202a77156a518e47d5f7951fa1718988be4fc463f8b8c5e4dfaaf2902fdbd22c51ed2e68c82db85092d567f239cec618a3e2179010001	\\xb1329a5c77f3dab9014a290ea591b937050225021160eb483d5591adb8182816715924f092b4f3ca6b41962000843d8c27b201762046040e2754d02dde644201	1641126391000000	1641731191000000	1704803191000000	1799411191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x50a1120f5d626240e101df79aeb1e090b7ba33b7c8f4d66919118a19914a6c24aea04faf0be9676406ac6483973a35e769d24f235651f9ff9269a335f9f74bea	\\x00800003a2a234efe7364d285e5e4639e5cf43c90a5e30c30603bbfaa81b0287583b6725c1e7d912eae0ee0f631ebb67fb24714f0fbbd2750afb9ef67fa53cd91b663ad07142cdc0ce04fe3e825b95d1f1ea088d97fa45054f866aba50d56d140c463487cedd44f5009c02c0923708b6959b7091c41f9cb0a7d4474710f3f71a6586cbf5010001	\\xdb78105844000240949f35eeabc46d4e39e95aeeccec2ead1e76682c28fb58f6825875935155efe323f74f9bab1685541be27dbe754126abe9790e9742a6ad0a	1644753391000000	1645358191000000	1708430191000000	1803038191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x50459d6b1e30e0809a0447922cec0ebdb585ef391ee433da10675bf92c18aa586445424f1a570ee4ac3b46117576b25b8b87725ed946d5cf9c030df529fa6cf5	\\x00800003a8f8a72a5445e059f3899cefee4d74139b1b48fb0c5f3802f86916bf81dabe81faaa0a79583568f431e40202bd32052f200f0597fdbed92c146bfaa59ed87531d6b0a8ef887be44f209714cf8f6c6f6225b35b1d724d57ef6738b9b09ce00438dc44bdf2978278843913fbf7734653c7cbe6f289df7868fa16c8ecc00c6aaf47010001	\\x824bba5b3ab91d508aef33b7055f39f91d5bdaabf822e13727886c6af0ccd94fb2ee32d7542268e79a669c6b446b2fcda6415bd24afe6807860d694dc371a706	1658656891000000	1659261691000000	1722333691000000	1816941691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	153
\\x544d14880ee432cdf7ac847da3095b13f07ecb43a492f2a0aedd3f9122cae84469c6399e291e8d5f29a1b9aa1b6ed9d26bf7670a9b2c260ab7c1a1136917fbeb	\\x00800003a7696fd27aaa7c01f1d3d7858644ff408d1e57cec59f514187327b6b569a33d69a4e5a6d05e99411af916c32d26610accecbd7fa55a497a2e6c4da2461bb7c59af07e6b7f7c8e7787ea58b73ce5970ed0c544c0f60acc211d865f9971c59cc67964043f38a23dfb2dcc58cbe0a9acc826740add1b7bec3521f25e1e058dbe78b010001	\\xcf1ff322ce514750dde4c89f01c0d0e05af9b66f7650b516b5322d8419802b7b1be2fc56c4eac1ab03ca363b5fb350d2321dfdac577fd9f41d12e4aaaaf9be0e	1652007391000000	1652612191000000	1715684191000000	1810292191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	154
\\x55f14942f931a9195bf47beebd11fb6455ada33b6782170b43eefdacee58b093ae0bdb02e317cede3df2689fc673cf08bc91b2731b1ec9b26f169064a7faf46d	\\x00800003d6747ee4d0329ac6f2ee767e820dd8a8b540a19da043b2a64109efa06a3c8bc9f62553cb28e45bf17e53b33a48a9a35ffd564a2d3f8d6f226aa845da7460df70f57b42e471c4bfdcd16f2d5e03aa2e6fcaa35e8c818c99825619237b5dc7dd7b0ca06ac3318884e136575ea5c0b6b4f69cfde1b7204ec19c72bd6bcffd6311a7010001	\\x3d9b132ec9ac8fd235cf182b5d50b7bd55e4366fa22d5e7701827addabb5b75591bbe8d7c93ba83a19d39eedcb0caca42342f1df8411881a8eab21420575fd0b	1650193891000000	1650798691000000	1713870691000000	1808478691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	155
\\x558dc2d35725ad8936d35661aa26cb135e4e22c2179e174245dcbaf29a8ac8fa7ac425fe7fc93b9cd4c8048f469975e077f139167d81540da7e673d171e15cbd	\\x00800003c70d64d922a3b4b8932af82b79b4294080dc3408a3346344d3ddb26b6e8db167fa6f5dcc27bc3c1364d1a35473ad1c0bab49ba5a59914d73577483da5e948b7a733b8d83f8d8217990871d394abba91f20ab878a3d4e4abbda9a6cdd506bead828b8719e8aa7d4c14a0d645640241823d5178a50759d15ee2b01ff91e0bf0023010001	\\x9d965b1d326317253b48a26cdf53701a41c814b312c95148756405cb6b515cf1d350e79489c4657a84a539b6d8ec932a301ec31ba46238d76d13e21ba2f9900c	1637499391000000	1638104191000000	1701176191000000	1795784191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	156
\\x5a5525b1e527f604228d692b954ddab4f3f2c43b7cdb9f06775517ebd28a1c86dd6cfca1fbd4d582abc65550926c1ad1184b8384d44c0fc2d5693900b88ab4f3	\\x00800003b286ffbd55e0715da94607bee12f89b8fdf42d2fd5b6acc7476be3628c69398b5b140ccb5abdd43882777bdd58c4dfa10911b0d320a6da5e07ba9a93f5b3a2cd884e147587304bc4b54a0aba02ccd7e701469e6dc4f54e5018bf7767b674b3060c26c30a5424fa4cbd0ad0a104f40eae17e3f8acc1b83d1c4174c3db1c224d55010001	\\xb585f31e31eee2e0c12291a72486625c7f5fabfb74ed9421653f60db55f2247560a151ba751ee8ade75e23eba9c63e22b79927767e64ac8f8ab1df1f7ffb0a05	1637499391000000	1638104191000000	1701176191000000	1795784191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x5cf9fa21ef7adccf9b6e3ec9a852975725fb0ad1fa7fb7abc8255a4291cbfbcc1317a89f6074c4ed9cc64176a0e8d97ddf81a40808454f33f8c8f6fc8972928d	\\x00800003d942ad31a6842fbc6a5231686a7f0521e7bf666b00486714243da99742b4330defb1e74f945426705c295206eaf40a33924d368c504b806efe3686a2470742f63f2822c3d5e9146c95decb11ae9b43ad7ffe2e966e1dc81bc64eb5a756cb2f9d0d75404b34176171e999672288036b0d158bc9ca9857906a5b6c07d9b0bb470f010001	\\x50d4c7225ffd8819aed6347b6cbe7c5b5fbefd4bb5885a49847386275d53b8e7413edd3a06d82b26dfed75c3768e551591105d0a8eb1c1284d66b54ebee75c0c	1653216391000000	1653821191000000	1716893191000000	1811501191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	158
\\x5c39e82f73dde544e05e365d2630957c60b110ffb0210335fc7943b64c0c658bf5c9ab773b389c53a648ce4b07f495dbce0cdd8e34dc652e496036c2d68e3690	\\x00800003c282a015b2a4af8a87f3773144d2141361771dc0f47e2d5949c50422d774a563cc5a3437be7ed3362dac274302f22fc0c9a96e2766721b97a27fc1921aa437436996d33cb818defef85acf0d76bf9eb80d6d208af34251eb62ec3c7f6a7e905cd4735fcbb11179408458a85c5ecd0b31c6231a35545e681e560ad44680bc13f1010001	\\xe913c6cdb5f3aef9ab6b9ee1b1ce98a0aff77eb543879a6e8a2f2f81ff52dc98d0d7da7b53eefb56a0344130cb001a7b0aa17b99964a81b5907aea89bbe4c80e	1645357891000000	1645962691000000	1709034691000000	1803642691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	159
\\x5fc16d0be22e1185bfbd3a287d49d7138f6253da9db01ec85c900bee5f93dee0359e0cabe0920a31fc8d1d916e986b05bd3619c9c193d08c70a7053ea04c20f7	\\x00800003d1daae694dbf2883b35e1ae78852a4ab4b06de697b7f55b4d0437f0a7464e4828c06f37c6aa6a9a5c3dca4958f838a172a8db0cf1faa8ca30005298f8d4111d4761112cdb997508d4c96bfccb4dce2cc64c6ae9d923d25d0af18bd3be66acd2278fdfc23ea2f472bf04eb431ded751ea230b0075b56b558661c59bc47a193215010001	\\xb7988684acec32478bd3dff6110944e2eb05060564b0b88d9a8ad8f7f2a2029982e0a14305a86bcfd6d33562707f97ecff1c59cbc23701e47f7c602cf7941600	1639917391000000	1640522191000000	1703594191000000	1798202191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	160
\\x5f25ab4e0f8e5e9686732a55e290c00fc42d4c180d5e656c709d70f8b6db67118cc5a41c3c1fe2814ad0ec36f89d633652435a045c2fd40ff91b308b977a9f5c	\\x00800003abae8fa3ee407442a461d1e8a719790e3da0e186797877aee7f551a13a4b167e987d060672b076122495501d837d3e56470a66e072608888c8aa298d060d122e735bd98b6df07763018600356c08772612ff6ea939c26ae65ad44638bc19b2c3ebb12f277f34f08f1bde0122a3e41b2676eeb6d838c89c93762d4632c2507307010001	\\xfe48a18a576a38a33ee30f590aeb679685eb4a13655f5274c21c3c8d8c823def7e04d3bede615bba8c4a9bfa9a20ae341550302f5f2cabc679d5954ad2c05002	1644148891000000	1644753691000000	1707825691000000	1802433691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	161
\\x62697cbe06a27a8f54434c9335caf7ab14da985979cd7d038da24f4051d7852aca1f625afe8a9d5b021e19ddeb868f50ebd4b3e0f27c5614eb78d82ab45af1a5	\\x00800003a780e17a558cc96458379df2dd311b0ea4c075357000a0fcdc26342b5e2b5502c59207a4fa1b6defb3d36461cf771b7dd8724a44b076ae535030a2dc22f4e79b2d777333c5535d8968dfc12b9a60df5a211d3205d38beb9659513fd1b280797a6a3becb0f627d20391ba17a774735727122f892949093c0d897f27a503f0eaaf010001	\\x2d5a43d5eb99dc8e975886eb5e66f8b2f3cfdfd45c3501497580ffac354f1b8ac8b4a180311ef98f5695a92e4275adcf865eedd212a160b00892485448cf6d01	1643544391000000	1644149191000000	1707221191000000	1801829191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x682dce0218f8b44faac12402b0d44b5e4fdfbf9e06d870c16a96079baad93c5485b978d064e4a314de817e40b375129e6afba04ec1a20386091086fdedc13d2b	\\x00800003a9857e3ed368edf00a330623c167fbd78c2c5a9c123836b0605a674cf01288a4d65ff2d3d66bedea39c06f27e8088048c3fd797a49d6077bf3bcc80e1fd555a9019e507ef02b43f08b62a04f10dfaf69717c3223cce19214de371b5386c628b6e476ca33a6bc984b2e16d2894c19bdf3f0be850e5d0ce432cfb9c246d532e0b5010001	\\x4ddbd55f1deccbad893cff3762b09d77f75ea46da9b06e38427435ef1e70d4cf9c03ecce40b8ed5bc1bba65b40364583805fc3965cef2b33984680ccd8dd5308	1653820891000000	1654425691000000	1717497691000000	1812105691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	163
\\x69ad05e8b5a81a812f87474bd42054916b9ac8afa8542f3dd34452587e80e6d7ff77e0751ac936d38ed3f87f875882a08f937ceb84df253aa7e594cd1ba19b29	\\x00800003ead02bf4709cad7678ab074c708ac8840ab03f04f8b9308e5024a23e0ce487bfe301702b3a9b12287e7fb310b8159928c8493f168a2dc0c51d0399d662904fc107f7444d878d36a07ac5b83a0a31cbb6c70602ce1d345425a4560b5ed2d1237c4a5ef0c4c1370219e53f861542379b76c9e0b036c84400c439f2cd363136cf0d010001	\\xfd35c4cfa0c0f2868abeb97502a63abff7e423e37f076ca857d9912817c3555bc9aa5393ac981e251d79117dcdcd60e40384748654f8a88bf124a6c23563740f	1653820891000000	1654425691000000	1717497691000000	1812105691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	164
\\x6b518dc2204b9ed4a9df5b981b57728a42af0ce47c170640398d47c65b66d8bf6bd4d2ef966f915323aa24a56bfceeda87cfe535fe98b6217d21cf74f6208527	\\x00800003b391c21595989ef5cfc711988b18ab1387af0f8ef9c95ffae703bd6c0de70ddeed0432f919b739a6f84e697d4fc1edf5567ba2988794ff7ae80a5ebad1a25f704a6778a2701032d2ed34b819e523150fc11b01f152826213aeba8116b29dddb834228ccff8571754b8d8f3c8e8244d3e8e594efa890895048cd3fc0293c1584d010001	\\xa1d4b0d3eb7380aeed927ca02b2be215d009807791f85a4430950cd4b5f587e9a4fc68f2660be0474d19770784211c792dba772d8e194491a21b5c6ce9603e06	1632058891000000	1632663691000000	1695735691000000	1790343691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	165
\\x6c91b3f41e56d5a3754cf22a00b2e74f9d36256e6c50d30a871e907c5e169c4636d857bd327ce5330e232218df45bd83647fa940d3b77c8400b1ceeb7c9ed277	\\x00800003d60a631853294bbc0638ab255d118ee1bf44120f2504768691f37d1fb37e7a1a1064dc52ca10c68a754e0164eca9946f055205d77bf8e687801b1ed3657fc39b9b482fc87b239ca48469a388fec06a7c73392b9b6ca888e3d8f42a73549956820cb0fc7caaa88664fadc70d51c24043ab162454718b70044b4c012b69ea8d8b1010001	\\x713255a2ee53c29a170aa6a5da12175c1bc5f92597dc1ec91e1e4463f9cf1e3d6c58200ac3c04d7f3b38e678ff4c78d2e113e5bcd401afbee3a9ec2a3482e208	1653216391000000	1653821191000000	1716893191000000	1811501191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	166
\\x78a5597629607ee1d74bb3b41459b96dd9bed3e49dd828d555196deb36031e93d5830afb3ad70466e2d0a7b9062829d72ecc3c5643377ea73d012a9f3b157a02	\\x00800003d533cc573850a966a0c9884de2ad89548fc1a33c00ad57c4a178f51ef7b4791759c5a5b86d757172434d99eaad8d06845e3bfae530f097e2dc8a1a40e6a8073998b3b0815f99405d3a15deea8167ba5f6f034db5356bd5d29b9f5c74e2fbf6e96e6f74f59d48b7dc2953b30f1074a5b4e63ec11e88c9b7f0f7eb5e6db6995375010001	\\xbd5d30635d6a8f351b74688b9c7567b37346ee6cc8d618f9bc8a24425c12b9072bd0d2616da01461d0b6cc77392dee77d168f7cd17bae1a477a00bfbfe7b2700	1645962391000000	1646567191000000	1709639191000000	1804247191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	167
\\x781137cd0d15b9d279da9de9bfca7d6b62227b4a581e43260c561cfd426860f9ea6bb082c2931ea163c07a6161a6cbf1fe4eda84b9b5651f491733c3ea743dc3	\\x00800003a2326b03d5b053604cc4083528dc673bd832bbad1951569fdaae83ff98193322fe4356820f8ca349f3ae36af2567b74918f97993e8d10febd50be467aa8bd8fbdfa924a16c6ba4eb379881899db83e5f686c0cc3630f3e0484e439a3c26bc11234074641e1a0b866f41247929b5da977646b0f465a150dcb767aa378f351fe43010001	\\xa68a1ae1947eaaf2424a3a1f57e4bd73408e83ae31db5e9b209e3cb727621c20e67978df9a40a78e84f57819a667e7048b2ba227a51ec9dfc6c308b51da41908	1648984891000000	1649589691000000	1712661691000000	1807269691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	168
\\x790967b90e07b513b4baab6cd9266fdc4b86645f568728bc6f246c98870059a4b9af8eed2ce58f9d790c31deb814855b490022901d5106545a78621934f93344	\\x008000039843e9399bc2e7aa0431e080c67a5abae32ee96947d6de7a08f4b305952e0bc560daeb843ebb8cb662ae59b7ae8f23be546d62c0f7029a0ac00e1c2a9f439a2e94d941e60272ec7b7dcd27bf67cae63f7dafbff7bb12f7d1e1f921cf0a067ee1706875d23c2a6e0e8313b245e051f219fdf2e27af286bd37f7fefacfbc96635d010001	\\xbd418e01d589b4c2e90ce37f305cb764e12251d32d5a4cab20950d22272cd5f08dd9a864df6a542179ecfa111f334ba17e5305f57ecfc87c2c994b3b8749bd06	1641126391000000	1641731191000000	1704803191000000	1799411191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	169
\\x7a714403009e4720dec0362ee92677e2a4defd19c065d4cf62e7f062e09e236bb042d2c8e23dcbc030e008d26a78a3de2cdab4c9ea8ee624455c70f161ed05d9	\\x00800003b8730d2a49388d5707a41e289bd70b8f82beb0c42d7294c9d9b8a8fde728e41ba28290e9389a5cac382a0967c34164fc3108aab635a91b93a13d08cd5ae2d71190d7dd75f526f97826a2e8facd0cea8a3add9c80fb43deaa7c1f92874c357c284185d6c81e87e27b9f946d63bcc6e26fdb50eefbd4ad471aae4902d884b77261010001	\\xf11dd88576fdc397a33e54581fe20f93384a35f1d1c2fd4e4ba09811cf88b5dc11f58649b83dfe15f6714b093c7ca659e9a2b6b7fc5012ad48ed25835fc51e07	1638708391000000	1639313191000000	1702385191000000	1796993191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	170
\\x7c11e9faf235ee07d98b5091d26cb4ad126e622bdb8d451d3aa45ebc63f7e5f16d9f176828ea951b4b15b3d2111e2547352ff65b27df402468575c7ec694c23d	\\x00800003ba9aaa7c119535db73992c58ca3f0b4b9378c54cea803d892e34ab02eb9a82446a65f5ff6c9d9b77c2015e47451fca664143a9cf229572a25c5679788001397b091915210783dde880f2c3fdf48f398140c1646f40b6d7b61b80d48e557a0d04ffd01600538829e79798a57d3438bb1b993ccfe66c37a5811e7062b28b21a919010001	\\x08157db3ed300c421c571f8e51fdc3e163cff2e1ad508a6bb641c019305c8f18fe99a105c8bb96129f5e19812186f858949cf3d8d831238089dcfc9cfe2a9902	1657447891000000	1658052691000000	1721124691000000	1815732691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	171
\\x7fbd75de42e1d2c1a239200d9173d4e5830aa50df615ce24b11da11b0edf0b4d3e1405aca13e440c9b6fa71c49110e8f3e3ee96fda15fe53676fb7e36f89cc0f	\\x00800003c04cc5613dd9b895c3aa1e2983e8ffffbb00a4d0715f7670950cf356e0f4cab5ffa173f0d2f4ae2e28df0cd5c255806a9f61eb67e1b9f783eee0b975449ca601cdefa9f304c15f579f58b8593dee59076bf6e80720684206cf5ab6938ca36edac29ad21e32d34f34e2c47957728980db455dad83cf7d4df4f3b5804606286e61010001	\\x086be231bd23a2bc90392bb688ffdad7aea33a142dbf27f3414a1acd42f3daa806894933af632beb770b5f1d512c21cfcb2236261c55d42ee5524f002d4d1302	1630849891000000	1631454691000000	1694526691000000	1789134691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	172
\\x8365e5ffda7864d08e78c0f0fd514d81a25945bd1e67905add4193f590af1cb4af46d61a7469cfc07f1458aeb6d5dc54864dd7c65b1e0e9cf20a513fed7f0bd7	\\x00800003ca74da14088aea3043a36f020f613e9c140bb5610814e17e7c35ea85c5d3208b06c77b04b8e37bb6c596449fad14742b4db0a7fbffb221e920904ccdd509466408eeeda06188753f04a6630df87841c488700925578c8e4502c5048aaad763b425e38c6cc1c2ca01d7d2244aabc6e85bd8797170f8989be6a27dc96e02927ac1010001	\\xf05f8632129819246bd6ad81f4ee81dcc3c47378c1d14c999a2c0d3ea54275215fe045b434e5ae3699c2248013da34e5bc76735a703c63551b4bcf4eee592b04	1635081391000000	1635686191000000	1698758191000000	1793366191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	173
\\x860149d68e81c438645b1a34851195dd94e20952c67ec49610016174c15cd9003cf5b405d920e95ce473de98f4ce1b2778141fe3c04d4bb94271a70b1ca4ebd5	\\x00800003db5072f5598e305027fba5156f0b774ac3883ca391334dd8b32c69c759d41b57fa2b00a32f16aad2a7eda7322f7d7253be44a2adb3fa5036048f3df8dc9370a569ffd7a350b7c16e0a3f9ea9e94d0215a6b738e5da151da0f947709eef3253bcdbf3ce666f4ec9b92b549042d7181f703cfe8685781223b01fbe360e1f81322d010001	\\xba6590d188adb7ea59b91751eefa897adf7430544d1e8b49c51063fadc4e7e260baa35c04e2f3912e92484a0403f36071afe4cef6df94de3f86c73e57d61950d	1636894891000000	1637499691000000	1700571691000000	1795179691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	174
\\x8871cf2390d424e04cb3341a13c75add51ae4d39a5f07843f2b0c9eaaca18ff68b93e5339b2f5166a6a29743105e1528e606ebab844ac3398fddb6a8775c9525	\\x00800003cc1dcee0010701c8351440235d478487bd30eb0c851778d32fbbdccc6815e69f2ed1c9ebc49596eed5609feb38122a2a3dc2a83304cb0f2cbd0237f75e0c71736baa20191194396a2b7456cf14d429bd8776cbfb6f07f9325b0e9c76b99dbdccce5e1f1b87ce3d05c2eea92a140dad6598fb5988ec452b80567e7660c80ed0e9010001	\\x424c73ee8b772c7012359a25c5f33c4df808b749f3075b6e0b41f522f008f6167021ffa5876555edbb9877601c5d77e9212f5530ddd0087e86aa5342dea69b09	1660470391000000	1661075191000000	1724147191000000	1818755191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	175
\\x8871562a2f4e69d48cf55db483ff9aab40db089de9c208b175ee8bf9251c08388d0f4d9e1562019d492792675ce62ca5f2327044948f539deccd50866d34e2df	\\x00800003c625ccb6f5d952ef416566dd09c3b4247de639061bfaddfeae3b69b8276fdc00f4973359b522bb0bb11956b2a37e3539b3b59a6865f1138d623ab0011e7b2412beb678efe376a917267b9e61c23a0d2e8d8a47359d2fe7063da4c0a030ad652f20397119a82f1c53cbec18dddfcee9becb80a758369fd67da463b4b4ae538f91010001	\\x606fa9b8156608c899e38886eb6f4998a856805695e646554b560f10c86d5d8a4616032ba41d2a2a6d69db1dec0a9053ac8a72f8b23bd1c4a40f36009fb0490f	1658052391000000	1658657191000000	1721729191000000	1816337191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	176
\\x8cc1bc61f0c1395edc658342ae3d739d7519c240adc45aa1d45d6b9dfd0cce9d38550f8df85c33fb356488e196f5461462d41ac241006a7da55951c35e4c8429	\\x00800003c3acc826bcc9d56e40a687d054c6026dab92f96e5bf37016b89826378d37496d903c9574495f29583543a0d7df154cc4204ec21835d24df57b83bb2ed4a7f0eeda1d3bc76e34c507f173be34b9154844b5723d9fbb9c4baf26a6f3313f3bc475ca5fc83f415dac79600205162a28b2115077613444a25797d4374f7b714798ad010001	\\xfbaefcced32a1053c8bbcbd71e7105986fcc13c77f7be431b9421911f7dc70eb9a4c305baf7b92cd7616ab6757da82ba8d56b8978c58ed79ca125580b23c8e05	1642939891000000	1643544691000000	1706616691000000	1801224691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	177
\\x903d389e7376652e39589feb0d54607bdd20a215d1976253325b6c599bdbaee59301420a9ef4b1b46632c6a5dec64834b4b1d1e246d546c592a5cf2f20d35885	\\x00800003abe76fa0abfe1929e41173e86307f64ad2fa8b7e73123d3f3f060b4ee74a6301d845da0d49338bac71b64d32c6b8ae9e4cce9788ff58dba1c31784b3ae73a669536905e517303969665d757eab537c0bc2084888262b43fa8f4dee700211a6efb30f9391ef0765163ebace7d521bb933970b2c9bd9097b0dffca303d1d7a4645010001	\\x9ab57d0d5c6e6c5b18bbce051eb244bfee58bea17ae749e8b44c69f4ec1d9392be08b917b737c3a08b125428c0445d5cfab64afafe43e21a4d28c2ec37828106	1639917391000000	1640522191000000	1703594191000000	1798202191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	178
\\x91554ab383580183e309333fd15a6dc79f733ef9e27fdae23f774924eeb1631fc81f34b19b381b656157c7e791d6e025222514023821f5efd0f296f77a662107	\\x00800003bc6ce72bf65dc625fc802396a58b2796d366cc1da296739979fb4e40f5c8c3066a02d3c86ed32fc3394e4e2e4d69f20f1d56de8fe558d34044f6f7bf833c65a637bca2d5a164b95ccf8e2f600a7c1fb403b221e3a6189dcf7e030276466016e575026908b5c42370ea5ced0002aa46304896598dc794befa2686739d08e2b931010001	\\x3978636ae663970dc53c0e5d0ab3910989157b52d86d38da68e5615b1655677933ba115dd441a09dc6e7583eadafad750c1c793d450615a330cbba4c5180ad08	1651402891000000	1652007691000000	1715079691000000	1809687691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	179
\\x939da0db0f6df599ae95258858fd51e87ba69d6fb01db53ddde728d82279fbe51b34f03a8023e9fb5897d35986d2e3a6bed749eb46dfa5d9c44728c85cfe6626	\\x00800003cd5c77e4b9456710d7239c1f6b98e2a130c88b35eaf7be44544dfdb4d6bc0300dbaa25b916c8b57fbccecf294b0116abda326b8118c21a6ae849bd9bcb10c5dd40e37f0d21d0499c4c4e38c02264a26870605722146883df5657638cf9358c6038b22e9030532f7c3638d23f653024689c6471e46a28d5e6bcab36f7dc4bbb39010001	\\xe3199cf7c621ab66692c8ed9b710328d367aab71a30f392ba36e66288d077bcbbf45e5d1086d702d9e6bed14c65fb02efea794106820ddb460ac225e37df1e08	1648380391000000	1648985191000000	1712057191000000	1806665191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	180
\\x9be9bca022fafb3f1a712947b67cc1ef49713ff63c69d1b81b8ab7b468120cb4c359b90274914730153161cf57eb197046cc9c1b7077f22b6fd810a7fc4ee145	\\x00800003be317219e16d1f5f4276ff3e3335df12a17d846fede93f374f51b092026386e0da718248903ba2e77bd05c8b412404c9207799f35395aea6abf8413f8b1c127e8e3b0300ce1133076c5b12a2e1d520038cd0a697483bfa57c985e7002d9e7418631b141a07c122bf5a94f0e86764ef1402b38eac76a9cda84312002840b452df010001	\\x89838b977c46f36c7aa8607f07e89f226973e3d5470156dd7bb10e51904d5b4cf3619e0863ed3c85d70d90fd524a979326b665d377e3bd672e6f4050d441a903	1641126391000000	1641731191000000	1704803191000000	1799411191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	181
\\x9dbdcb261c234786b4a9ab7c9351f7d774835d83cda3966a3e9bce8a6de880f92e28f749dcbe0d19c7cea52089866123cdd51a820fab86c69fc1b1054da04bef	\\x00800003a1a74995a12052edb3f7c2e891768fdaec5363f2142b35e7d5b464062a111e893f5509e8f17d2e5235fd05be02ceec4474a2446f2fe2e17c91b7420aa08a439e140f5f488d2277a80031e9259253c899f3513592f0bae743ceaeea3bba9a11bb924f3d333d9a4aff130a3d7ec399e2e3ae8787530a49680f5126ced1e6b9f127010001	\\x0c7e040ef77d839d508fa440ba95ba541576cd8843795cf7f5e2d9fd412a76fed734042ef7cb2fd98a6cd83e9a34469f4060351c098c10c9f2cfc7493904390e	1647171391000000	1647776191000000	1710848191000000	1805456191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	182
\\x9e397487fae9fcdf872fbae018b2c745a1d0a6cf55c466db8f0af18ec66197bd858e0ac2bd28a40f35ec0163c727fae4251c21f07999e02478f34008dccf781b	\\x00800003dd74449f4fcb5086789e6ce81c3f22ce6d03e5380e576662e6cbfed01a04edca108671473a107c8249b78f5bf7b0c923c26fec4694980e3bbd6831221a1a41f9fddacadaeca08fc73d8926808eca78d6483643e0b712fc914464d2fbcffeccd0d478b8ff4e60d830993e98eaa8f88c7cd84095be0cc551e20a83b65c08044de9010001	\\xa2d921285b1a7b4e1bb88f563177dac10bd7c81a4592190bc6019af7f626b668b2f0b509128c23bf89d7a560f1f229e44d6122e631dc4d198ddbc6588d74930d	1639917391000000	1640522191000000	1703594191000000	1798202191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	183
\\x9e9590924f83b16d653857eb6eef34b24d4058982140ef7eb138c7b9b1b2f39fcda35a84da2cbc4977fe71559507ce4fc6302e312ac7f32e8cd639abae3d45b9	\\x00800003ac5e78361386ceba3eb276c3daf2e16291d7dda81612c833ffe71eff5c0cd7388fce5fc2d27fbcb9275626d95df341a9a46a78126a37e5fd470f4822203945b7580ed02214f438851d07fee74cdf026da7f939650b42221770eb9a48ef2dd492b988af59ba548542e8827a71ee7d0f475226dbe682f13a6f78064ac41bc5fe7b010001	\\x6a27ff048c547540dbcdf3888eb721d7a06e833764742e23920c8399d0a354e33bb29b40c1f720638a03431a5397866a673dc450b577a94bcea1447cf9285401	1650193891000000	1650798691000000	1713870691000000	1808478691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	184
\\x9f0dd436b1ed0daa436032ede2e793b174f662a9c0b2bb38ed49e6aeb2a7543d77e287dacf245e1f5a3744d66f686cfcade5e0d23c4bd6f9d7336342d9568836	\\x00800003d6b2d8dc2ad316dd3f5b455bc7ce73800f31944a55fb83135cdd5da210ac49a48d2f5860005d53b665fceeb6a950d3b92636726ceb97cba81a3524bcb964bf39cdb420d90e6bb94149e6092125e28a495fd2a8d7dac3c45ec98c65a96c4500f3e7bfdea690263c6f043a87fef0aa8867128780d30e8ac3235f83d3e53707888b010001	\\x66ed5ccbb4bda3fe931210e9445bcf692adfa7a41d53b016e098a4e03b9bf951b7fe5d86925de7b692ccc6b1db31c61423df85f80f263b1037abd2a6d4392007	1658656891000000	1659261691000000	1722333691000000	1816941691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	185
\\xa04172bdc07b891e7f9caf9e5e03a182dccdab9c48cbae9c97dcaf1942bea89e4261b138de3228e2d65df629494c1936ac4fbb58b9bf6f3d191320f5738542b2	\\x00800003d3e9406bba3fbaeb4fed54160ca529ae5b04b8e96a830688586c3cb3cee8544d41819140779434fe29789046ddfbf09eae87be852597d4843b23d2e76959fdf1a7835e989676c4433361c6e6112693553cd04529601a98a4fc242a2c60538f48148d983b77520286aaecaa669b20e7b5dfed9d18460522676a305914a6b2c6ef010001	\\x9dfbd1013e1c0e7e2d85f95846aa623eb34fb1717ccc81d3211aabc5e6b6f892b023406fa29b5f5a3690e4438d402e6ce305a2fc7351d0d0cf9310d71d103809	1652611891000000	1653216691000000	1716288691000000	1810896691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	186
\\xa1a9c1b82a1635120ea0c68f40267cb3fd7bea7a62ff8b5cca7ca4164a10c0f3c2b9d496a05931c896b45d079cd569761f4019cb6e99b580740a5e93d71db32b	\\x00800003bda30aa9d4917fb37a98b7ad53ff16c8a8bc23190d42560b17cf27f075deacee6048df68a7fec74a15428e49d8de1864007b00f8d24deed426316e0b4cf226343435618dbbfd5e5789b015af7212b9c1139d201f7ecad38e110bea7f0035c647518708d9c7e5e1ff4da9b36c604d989ac2c1ccefe9f9de59c722da8bb9a3efab010001	\\x8e39c9056a411c68af873bcd4e90a0186d0ce6a5d5fd64be14c4dfcb31544f1ba45c0b97fb39a6b136df35de960a273b97d9f402171c63967a7508381c056c07	1639312891000000	1639917691000000	1702989691000000	1797597691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	187
\\xa3855dabcaaee67c95d4fabe1f9ccc29b7578852f5d4cbb7f8e9bbb56137f8f248bf22351f8453c439349ed434997dcdb05b384b9ff70a27f57dd690caa7d479	\\x00800003cda9b4353c239df98c52180b3fb4b927d8979f142a0237d3758172a088cbdba5782d95a7ffe77f0ca37f75b2bbe18d6a61a864a7df33d5b73d88f15ae2ed554ddff1a7da19c77ea325e8f6edc67be34a269c34d43de5192d578c082586264f025f0bdaf21b0426859e817dfbf27e52ea2a785dc6d9cc12938609cbb08869580d010001	\\x2b25b05a81035f29c629db72a4889ec32de3d015deb6a43182722bfd4d742339e757a009a3d690862f584703f3b22ff3b5d5e7b87699716a36620f9b60359005	1639312891000000	1639917691000000	1702989691000000	1797597691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	188
\\xa6394cad2c839fa13c68036cc1d2fc65ce4a2bc5e6dd1eb6b2bfd395879c2400db1b8df5ba8048239dd5e6de918487b9f73abe4aad84f501864379e18229bac2	\\x00800003c2cd0ecfb94d6b6e3404468c939eda56d6edd4365ce776d29fc6f5a5979ced91a7eafd2d494abb5c60905c3afe7ad0ef3af46d5123cefcd71d14181d24cef7179fa87ee8e810e3f47d0e33bad0c6e23b6b6f23c4a503c708779b8ecf4d9d60c0bf144534fd9ac8a7dddc871180861c41ca918d4d50fc8df78d40f59f4ba703ef010001	\\x489990c7623d32979174b699f03fa17fee6a8a63977deab5fc39bbcf6ce3c28df06a7aab9edd06d4d559dfe33cdcc150bd7f89a47d9ded8ae515ebe72f3deb02	1645962391000000	1646567191000000	1709639191000000	1804247191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	189
\\xa7d5f0ee2fb7da3bf67490fc53a05f891cfd485f666f36345190a960df3d5375ff3a10d91540d3beba899f8f20289c4ccae38deda0ac1fb950dcb43476302e70	\\x00800003bee9fe76440a62019025616c572ba5bf98e0f932a431731ffbc74a612855495bf359e897f32f8533aa7120a8fada4bd46ef9f4f49d1a00e0fed3ee9179233a498b2a055b1a2fe30895c559a1795d080a26f774cf778ec2e7bae4759eedce11f01ce503b12a5dae9af452cd6fe851ebba342c62ea7eec1c188eb6ef0bc286b1af010001	\\xc83535539d18e47cd074fba9e092b267985b6e110db9122ce4c44cebc3856d623c5581682ca097a842e1758ca56406af3fc745c911864543d1c32f2cb058b90b	1649589391000000	1650194191000000	1713266191000000	1807874191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	190
\\xaf0d5bb8d172d1fc669cf5ef223b36c8dee7ea230cee242d2db69abfa425ae0c8d5a9c9eecc15e29a32d76616e5591348da8099a8c169e0537e1e7d94b1385c3	\\x00800003c673eeb2735a1208c305ae760da17419054664d3e2d41bda4543ca85590dd91881f90fd944f49e60ff4e3536b9cc8c5a58cab06214fa2b08cc6d2bd2dae36eb63a85f29de2ff598cf5096b3441e376a06f4d4fa44e67399b3be94617d3172fb4b1cc00d46991745cbb1468e218f92147fea6b5abf7e994c73a772b66ae32fb3d010001	\\x6567257cb15d00c7d2f63ddf00aaabbe146f6f3abdf2add653168eadf46c290b08717b85d2600ce99d2ed9d22ad8f25ef6c71c31dac8c114eac09809fd1be508	1648984891000000	1649589691000000	1712661691000000	1807269691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	191
\\xaf6d8f120d0696e515fbbefdf661dc44b94bbad866415e2d8fa3b1c28ebfa57c913c8e05091f415b7640e9e0456f01088d0557a591aace2ad31418ddd9473d1f	\\x00800003c49c064edea27dfcf162708a78d0dd5b55a8439c978e29be25d9f2710611220e6a27cd6b2e5e27d13dff70737c4793d09f7ad32e4247dd9dede944c418048d4f16672e47d9719d12ab0f14a768c4ec479da54370befc33b6b090e2645b80f62c5f14b892f823a8c759b8abedaf2d2a4dd3e157dc9814c1dff40d2bbd41ca7baf010001	\\x1e9c79e116ada3c849136f3a4be07cb840b01a65ed089ac0d2bc0e884110f86f22628f1840bc762ee7b49aed721a40c5ddc006bbcb86c660359ba05e60f25803	1632058891000000	1632663691000000	1695735691000000	1790343691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	192
\\xafa974a44197f43561aa8b7890d70e6e6ccb2be0ab866aaeb507ae40d49554c170034ef4f39327936eb10db0bcd1987ba2e18045ed090aea55693e4baa5c5d27	\\x00800003ccb4743de026ef57cbb6b567e4df289bd5f98b7043c6f78c1655e1dc1405bde26a84b71e57883a776a34e039aec1b0e3a1081b4619e01daaa768e7862547d801a3a934fc2c6320b1c6586d9c2ff45f9435f98e3f50a177d18cb332f2f0ede4187a63b529be7c3fd455e8e9b93c3bd70254de12d531e2c38bb5c9b5aa50a88fc1010001	\\x2621d7fe70707ee1fc1698979c2ee7148d083ef02395c07a244e542af25c2fc14381642302fd5f7a820e3d6c3e1725c5d01ea13179f55ce96aaec23e89c1fa0c	1640521891000000	1641126691000000	1704198691000000	1798806691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	193
\\xb0f5ef882f4bfa6279da0023e95804ef450840c686e9aad6e9e85a5c7e6b4773e7bf4c9dcabc11453b66d086b404619774fbf8f5b203529cf9fd3c0317ed0077	\\x00800003b96bdcb20bc77d5cdd309988f0cce1660fea9ebe8fb97987f2287b4980ab863024203b9c556e3433a6c0bce3714adb7ca39f7972b5f62a4e1c491a97a014bbe4d342a7949ca1b0d0038a6cbb26af2ae542467f07c0be6def712566712a62be425514c428117a5582e848438385ff4672d2191b9fc5b7848fff67911ed2658b67010001	\\x76c65b8e667b4c4923a1b176202463d41499be32e9d6fa1c0cacf6f7dfb286dac811d1077946b0f3339fe28cd03163669073057c4d6b808ae22244db8004f004	1636894891000000	1637499691000000	1700571691000000	1795179691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	194
\\xb37de67b0c1e6146d2d50fa4a74f1cc2c02ee8a093826e2d1c1cf3d52cdc9458718f8152378eff07ef9cc1fc78307bf7c9ee95e3a7f6d1e61cea80f04d1e669f	\\x00800003dbf57ac63c42b3a59c3a96b66035846693be69e5ad080d98fdf86534077cb806d2aa26574d3cac59fbab3066c855b620dfdf74922ccce0f370a1ecfaf6ee05e5708a92b994ce19d1804f866dd4dc3c2f7da5b0a81b59b5c738851c707bcb8234adc711332cd7bb58abc1f503e02c837dac43faa9045429d1ac93e40f281eaf77010001	\\x35844939d550e65b5a80ced796cd2cd222d01550af0bfada67e5db0ac543550055a99dff3cf88a1f700d16ab550beaa573aba057f10ad09f4f07befebd5f9b0d	1645962391000000	1646567191000000	1709639191000000	1804247191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	195
\\xb7edcf229b7cdf760d2833c2bf535289691f12234f012e445d0a3750aff38e0ea65bf7184cefef1bb346a5a40981cc7a7fd909a79070e86af5c252da20b02b55	\\x00800003c00393671f4eb4c2daa85902a765c1bd1e911f1bc560328b61cb6a5adfe4efc50009770b17eced97becd01971d9b87a029e6acad73a35354b8b1061288ea73c6bb9bed05fcdb22407daa88b135ac14924f0dd3c314ad2c7f894cd4a1f83545e5959ff0686418be652ff4488fb955fd8b10f1d68520a68fe7c757a09548c0428f010001	\\x5db9388fc05f8f0e5996dd563099e6c14ef34c63b5a566765825dc485efc6ac009784e71eb496c1fb79da4434459a78c5408677251c24db0588c12cfd4aac20b	1635081391000000	1635686191000000	1698758191000000	1793366191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	196
\\xbe697dc30f1bf7ecedb349bcf9eadf43a2c5db26a6b57753224a056a378144c0450229600f52b1e0ba50aa7e0c16596f986c47f06f03ca7ce3a535257d4f9cb5	\\x00800003d2fcd198095003ef80b5bfe09e441b570a693092b50f3c9d78e7003bdc41190fea6065e5dba20a7851814ab954c0fa6556313b2e32fb27b690b2b83f95e2494683d002f11581f4cb25f5f6a7b7a03013e031d3a248114c7cd53466bd8b34fb1b2d6b6b76a8f242f538eded13ae20c0a3c0079565050db38a2a05d9dfb59daefd010001	\\xae9a926a766769d79e67969bd5f8d0998a86ac024c0df184018c90a81462d76fc62e70c7e4a4dc0076792c9f93744f0b10a131ede0738506d5ba3e972c948f02	1658656891000000	1659261691000000	1722333691000000	1816941691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	197
\\xbe914fe17b64b8eeb479f0052e3eeb886fb44a875a4317d34568479e066eb76a1d81345348eb68be0ef7de1cc0fcc9b899ff1ce52bb8a94cd8ca1a7c216d333e	\\x00800003b0dd98d84685dbaa2b82848923fc4277e9b440ddf5540d4fac176e5f504b6670ea4a785681ce7d3bca924e4e5717425fea1ef0ab4363ceb9f9b5906b460b7ecd907b2a78447331424180391162dcdf2bf3b05e1d1111bf36cc3d73a1b45dafe67281a251dbe82d20f27149108ca40b3f1dc6cd2888d555e14b1f8343cefa681f010001	\\x15f3005987a58c806a0b26a85635799b66f4dab135d295b27da956b2d2403933a000b2b4351e69916ac1797c05da3b7d3d593ce9e7ad875b6a10c2a1f22e8207	1648380391000000	1648985191000000	1712057191000000	1806665191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xc059d106ac0e9e6f855817e98bedb09bc1a4ccea10cd2db1f576be118c9ccdd9bbe4394a90ab4a983c7afb24398d59bf0ef96bed1a9ebf6de3018dd9d80f0e5c	\\x00800003c2f7660b52c7f2ab098f1181c813a3f1ca76714a74ed4288b54011cea4c6a92edc35ae0b3197bea54be849a2490e958053cd0a007bbb81255645d93543d91a6bc6c835890062bfc1141275ac6f049aa85b59aaf50bec54ac2f4b7f8cbf6b85ce64fa2223c6b8596d6ca867f94ccc3eff16d2a7fe339ebaf3b89e69dfcad58b0f010001	\\x28175786f865580d2454cbabfca759daf0d73a7943212b196abf12ca0346a002e1ea5095d3c463fe45c91d6d76d62d07c573b6fff2c1c8eb72351b604393a406	1652007391000000	1652612191000000	1715684191000000	1810292191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	199
\\xc695034c62a84f7171cd9d7bafbaf4fdc21a2e0fbe7e080c322de92c38e957242bb98724acc98cf3c31e075fb41896e91087bb10f1fcb38b7c7d899010c58fa9	\\x00800003d1bec00ddad594cdc931a69e668af08a30c1f9517e2c61e995eaa27a5348a5c04781c9533d38645ac7495231c99a2caf6c30c827413ac86051fdfe3598625dab2899cd09d2a5feff4caa0b70c0e4d5b3512e6b95d5a1b08c4456b9a61013874da7b216c0fb66a2de2ef2f380f2bcfbc042e13a0948ee76f20049320de87632b9010001	\\x946c15e8406c00eb22a3c11de390f155c73ed7ba68014c04a2e3f6f2eab4ef6bb4796d31e1402eb1ecd0809a63e2cc2b582bd8f052f49d73d821107a806e5202	1638103891000000	1638708691000000	1701780691000000	1796388691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	200
\\xc6f1e1486c6c1a7a00bffc0fe8251e8f876bc871da9c27cec0a2903a61f609d0e583893590eaad0098f90b589dde454d234170e44aea028ce92866818005a6ab	\\x00800003c9f2e517b02c80123071f15c7dc55ed18ae7059eaf13a7f549f0ba7b893e488d9c616cbb1fc203164a68f83d659e7309229dd2d99a3ed1093984458bd23c1a3b5c2fe3dfa678a2b51deadadbcbfec8d4040db8c490f325d9dadc6a853fd207c5ada714cbedf4485ff5e192cb592bada3edae5695fcd0a804f6c993f606cba837010001	\\x8f9b5e7da011ada32fe2208a632eab6e19c344f4a6844b6278501e9212b036df91706dde1d1b18829025c0cc4601810801a83db83c8d03698b9b18f02886070f	1632663391000000	1633268191000000	1696340191000000	1790948191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	201
\\xc7f14c5b99383e0eacdb6991b7b8a978c547d00929068b3f908eefe0612aa6b3a8a97b7f29bd632e1a2da2171663d8589902709923d495bdbc064c05ae2a4c87	\\x00800003c98411ff7be38ef17f852519d45220a8fb909eda08126e6b1b62c03149373e4f92a34ca90a955af1d60794ea083ec0da371422a911a5272d434c3103b637bab54c383d874256b51d5b9d06733407f6b0a9b9dd15f63c6576f54d8be03059fb4fb784ce3b79855a237a25de25644cb11e8ccc090f7738f3fb937fca8cab2925d1010001	\\x922c4edbc578409a6cc372097835e814485f78d4bc2f8826065899de08b48df0402808195d23ca9f2f6b2c715ec75ed6f4fc6510bb4d67fa2afb44579da60f0e	1635081391000000	1635686191000000	1698758191000000	1793366191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	202
\\xc8bd0aae7455eebfffe4638fe43f0795283a4d136ee208dfb83a3654aaa5d71f804eefc0dd047f193504071263696d812b00ccba2f6becfae5db6ff1bca0ae7f	\\x00800003c7f92aebc8d98a18bfe097f6e8b15f4eb2ca3a55d390833e97649ad0f8eb0872ac51525970d72e47037cacf56be1e4ef675266f53b874a75e40d66e03f1f9a9f634c2119216fce3f39c3e4f9c224be4723559ca708d365cf15774c4e007e514ce1c3df6204aa50ccd5dc724d0777b5c9f23ee1408da360b8faf26346e9efc099010001	\\x5a663249ca8fd20f525f62d2d759c5971fd96ce0a65ef9f571fe821169a8684765525b79be124400cf7a85585e2e2588c3f597112002d5234ea8adaa783b0802	1649589391000000	1650194191000000	1713266191000000	1807874191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	203
\\xc9c148d590d7a3db611eaafb1e520c921ee339c1140bdcd0f575f27a6241a9dca5375c69d7715382fdec41b6052c754c590ca2a4fc7f3b949557f60b0918ef12	\\x00800003a69efea38c0f39b9707bd17ad175630cc3209fd091468501f0d4ac5973fc2f03ef4c4377104f25bfc6eae40a74bd5e83aea46380e1b6c4c4ab4c51b8354006b1dfa34a369a1b1bfb0a626712f4043b235474a5d0db1cebb801b66ec8b6c75111697a560022e950442d3005bad11e5e974b34c3c7c460976f8a5a909b630455f9010001	\\x80b017555efd2928f6a5fb7684df0d5d59b3cc1dd0629ab0d9dd46a35bfb5b09bad5757f523015381c89e60fea35fb0a75bcbf6877cef4aa84ded327a46c4405	1631454391000000	1632059191000000	1695131191000000	1789739191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	204
\\xca255e565ac055b944459e37c37a54b2d5c7090b00e446d00729b482fc7ad103000d52a76e13c442e44759119bb16550ca0b74fc1c2659400f9059db98fde1d6	\\x00800003be92ed337e5c2847d9cee247c38aee35842eba9b5df01b88178b6d5b9b4c5d4cbaa3fcc132c78a8fd2341487a9f4831a5bafe84e59573009dc0d7a1fb00b330c6b8b49daf2a41e40fb460a8803c4cc1f0171d6e70e8c931e50f99ac8f00b61da7fc642459a00fd5f8673a181d9b3623637e0e2501dc2e1ed6eb7a91efd70a11b010001	\\x19592a62ba72be169899235a948417694960341d6e4fdb03768368c334263c33a99414a1ae70c8786b6bdda092e3b59c172ba252416e1399dd07a5f5d25f7c00	1644148891000000	1644753691000000	1707825691000000	1802433691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	205
\\xca15bf198625f5c09b1d3cda3903df7c5278e1eb2a2e9f05974153fa681ac9506703503a4e85ea9afa4d5838c2203357aae0d0a32864d677dd64b2731a148ee5	\\x00800003b6daa00176000bdafe6047c0228870bc21105e5ffbc9c57cde2e814e21994a90ba58480ec481aeb0d0738b3e420fdd2097ae46402cca048ef849be402c6765fa82567e90d7c6260ba3b679661707e9bab0fdd2dc058f3b1274df8aaba8195c764a656cdd4f68d7f8553f5ec5bfd7fd42676d25a300b8a6e22b7d135c87625e5d010001	\\x722da467d2e750d0ecf2d95f9776ed194289426f0e61b2d3a1b52ebf64d1943a7f1449a468ba1d6dd1e421869b000ad7411253663bd5e42d588b219ddd8eff03	1651402891000000	1652007691000000	1715079691000000	1809687691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	206
\\xca41b21615c0f49e2f503a693267a9ba338425ce9966ba68d9f074d47fcbb64bcedb23ec78fd26aee75f38a75b7a7ec31315e5ad588dcdbf25033c0dd3f5f677	\\x00800003d298fb5d09f942e5258c6e704a3727ce188c60acbea4f1a256425415511bf6d32c994993181cf191002a274262a26dd9bb58c4717bd4b855d2a11315f72be2a8c6068286e248ab632ff56363899f01448148eadc3c2cf57cfa40bb9489b7c05f3e3bb6847969dfcfaac07ba4054c85bf188e572f59a6f1b03c63c8a950b63921010001	\\x3349c3e268dcd74fe3459b3bb589c80b2df68e2d0f964cd8a9c1f81d21a8bb56315babe57cbf1b0ebb4a033be44b4c0b7d5f72f2207842e8bdf7f48c66c66c03	1642939891000000	1643544691000000	1706616691000000	1801224691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	207
\\xccfd9931711de28a99c4f776039c0b8da91c64a0a0cd7b5985a2ca9ee591fbe4d4b41453ce9f8afdae6a2d40a71e9f2dfcda85670b803524ab8785077a8fd253	\\x00800003d3fc9fde88d802f0ab8e7db453940ff0ed51d7b1f488c81406247cef026af9cdffac39bbcc287cc6d23fb0677d974170b3c4a476544c94ceacb67a22e7c795b9c089f16d646f282fb6fc9b6f6bd3e0629e130abec30d4f41f3fc90f49a3445bf0055a9b5b0981866bb4600bdc4be0f6d4a72d72dff441345f6b977d0e88a3cdd010001	\\x74400a8dc4b3144865101f0b38369c9f4ed1b939846ca3f7428db57ad409cbb77c32a106f02247d85336b0d5554dd80513b4933604bc3c5993f9f9f6f0ee0201	1639312891000000	1639917691000000	1702989691000000	1797597691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\xd55147ff886e1bf3fa49fdba8a8728153c453130046a4cd77c6172e6fddea7501aa3304d14a1f359575785f82f9874d0b72badaf79e797d028c52e437a698e88	\\x00800003cabc5e4f485459c715d66bf5c7950ec26b0d34e8aa5b1b0bdf90818b13d1bc6ccc20fb95b5459749c13b38e9212f4d1df03212f68e3feed61002d637629b1e319a80b845e6cb349c3c8e9b3e3bd5c76a36881dd7a25413c71b628254367801aef99532745547a72b7a74a1d30e4045f6778186af29833bd34a6f586a1079b5eb010001	\\xc07d5b8fbfe5352fd6b3d595957414366a07aafcbeed7fc1a33699b426970c729224fde803b1ab4003705a8d270821015305039a58f11a2f61facaccf035d402	1633872391000000	1634477191000000	1697549191000000	1792157191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	209
\\xd6296defe55704267e094daa41434027007fd0407514b0761d09868140eed10a33d7c2df07cf5c2aef5c76a47927b064a01eaf03261a6b79532387a4e873be3d	\\x008000039e4ef3dba67af9b7e81f4aacdad9a22e9371e3cced9c6d6a1ad2514ec1236cdba69268ad0546bced9243d45e8c31d342974f879a608d12109e0380b49cba2ab2932d9bf79c3766586213aab200ef15f8880c171a19674313108bbf179b89996a524d28fac3bbbcc3e817420883bf084d6d8ada71f7bd94a0b9696c59b84593b9010001	\\x6bb9b62af0488d94d828556944d89a4f0e303548c4995638f596d4b99b704f31276c081307386f55be0d867d7d59381a19a82391882134a79452a40227f37d00	1656238891000000	1656843691000000	1719915691000000	1814523691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	210
\\xd7991804c5f08aa7c4af3604e2fb0bed2840a5d3615aa14a01083a4042c1fe0c5c456cf0a78232c1bf3a7b08a7cb5313f6027c6cde6f271b05a2c5488abdcdc9	\\x00800003cea5402f55806de5dd1d55f3f21a4e70447f9eeac818d86acc9050febe144c1c04ca9e45c8a43720e92ee77a587790a8827b0df3ae5162d678c4a7969fc3ae886b2c1a968afdb6526c0db02c70c2da35e41e02fd948e156c02c558a54d94324ff3ad276799a6303a2ca77cfbbead0bea5c2456538ebc76d25d3bbc17c3c889fb010001	\\x9268432dd982df31d0ef643a10e615103761196e78231383850b5a1dd955d38af6e7bec63e4ffa9a67d54990d0ae635857e28b3de915e46181d5b67cc2cc8c03	1641730891000000	1642335691000000	1705407691000000	1800015691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	211
\\xd809b82e60e34a09ff37b2635883dde386a0078149850d6b69473ef468b4cb9720243aeff13ccf041f4bb8415a9de17a16350f824b1d5a29485226d6f37d90b8	\\x00800003d6799eb175fc3f9a30396bc2473bd4183ec608ca713e01a5de3aa7f060d639c11eb70542d1dc8af7e07f1b8bd334bd1b31c5b162331aff842d74d7a46a9248a85b7a7a1cdb5676adc4d8772d34f64cbc9ed0c62f55592d1716ad41a27e5669f6f64ec867ec771b207958e24ceb602f87705981648b268fdc59287cbf5bf03b21010001	\\x2e949541d2276d5904364b536f52c50adbd68efa1ff70731ef976f02652a2cc764cd9e6838b15108dd4c43af2b63086aeadfdc5736f255ebdd346c9fa0c2b709	1654425391000000	1655030191000000	1718102191000000	1812710191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	212
\\xd8f9b22bb6a684b456fb8b375e6e98587497d268f3b66883f699f4a95779b444e4c1ca014c467b54d63ed67f18eec5dc91bfd400fa1e2495e69e5c727fbc2733	\\x00800003a9b7c6e49be5408b4277299ffa17b77cae32de0ff6e7d67da98a9124cd14ebbb85f2912a0fb71f6d13fabde861be6a8f28a9476416ba362b640e335426d3cb9a64be9928580ff92afa79db2c3a4d73b7f88192a1986d7738635a355280804c4308311829b8313fc1f3627abd1d29f854e3d04d3e3c95eaf30f951a8e8251660d010001	\\xb073f70acc9b7ffaa8b3ecfac44afff8da3ce845714833b40815a4f73c102534491c2561f510fc417f83653d64c2bfac229bff18be4ed529d05304f9a5973909	1632058891000000	1632663691000000	1695735691000000	1790343691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	213
\\xdb6550f078d956ec0a4e8dfcc010d00f59cdfb31e30349737d82d0fe9e65941f36fed0b42eb1ac3ad201ce6edb54449b9a09208bae089eb3aeee1036979fe8f9	\\x00800003d9c46a080da520c3e478cbf830c6447f2da3c32a069d452522fd8cdeae925fa682c659b446d46250c60dee18a1c3c8d83b1be78baa2a33ed04c7b45f83a39a9fdef68f45ef27ac4def188424508e818d6451ab8fc5bfac12a057396246dd8643921b92cd081e7bdd6d9de5a52769dd1013c0cf4baae34365055b6dad4dd24bb1010001	\\x3f7352bfd1f0b2bd41c7d4efbef73f567657dcfc7899d80bc7d05e4505ae2d37a4fa0183d0db439a2b40f316cf490b175a7ad52458b486b41907cb7edc9a320b	1657447891000000	1658052691000000	1721124691000000	1815732691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	214
\\xdc3d293df00184d2feaf6edf034a6ce81eca86d60a8daae22a190964325024dd0532b3958f0859a4665f81a625ad436183a730f46e2efa20fef6f70e40379e1a	\\x00800003c65645db09070a7eb68e37c33017080e9c193cc3cbf8e966cea4851d4ccfedd5e608d2104109c104c4b0ddc836b69c745e2f76034c5338a9bea909536059e3769db9cecd61b03a127e7bd2da054f2dffb8ab36da71c226281a0800303c891310f298726f36c09b10885d98cd43e4c5d4d4d0ea5b003f41eddd6f854f7e4fe7a5010001	\\x4d158b80740bacc9af66378e2c39b25b5c6459f79941c9c606b8be17decc240a999e03da981b3886f4ed1a4400be82f7c0feac30a0bb41a2b928c58ac0994903	1655634391000000	1656239191000000	1719311191000000	1813919191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	215
\\xdeb5b34aaa772d7d053ddbea99af7495205203088dcbecb6b46155595b4720478d835628db773c019302f2c39e35e323002dd6ef0bce041ab681cba7fbe35d66	\\x00800003b597185bcb3fd223d937516a37121d5c1e38536ffaf34ce05a5b01139b504175cc40a8a1c0be55e087710567ebe53d7e99ff56831e12f3d4ee3719edb2117f1a01b5fa08bb3de69f4568f564e81a1d8ad5a42047b44fe82b464125fc60a91f161525584d092e32cff9ffa60a0818e466a779d1d0329a359de64fc4e7dd05481d010001	\\xb5d97e250742289fdac5c9b86e82861c608007139b552398c02649d42d39004153bcb7c3d2531e56be2f7e0784038283a91c5fd3fd1c32e1f96830314b697c05	1662283891000000	1662888691000000	1725960691000000	1820568691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	216
\\xde81019cf44b018b746cc97ae957bebdc0f5b943dc33960bec5b23b434dd9cfe28b8447335bca35aa036ccf1c93d35f0cc5ed8df09a92f484a12c4f0926c07f7	\\x00800003c0408129c1e04fa7881b720317626e323332bf0da40045ad42ebe2045f6861eff5faba5a5d8cb2a7c1e37a702e6dbf7f3402a5e8f0b13d2dfc589b35b9484072b907485929a2225c55bb7c2df42b84cec412fe6fd70422de8dc0c27505ceba521a43b2ec25d38fb346d05a9ea9120e1f88d1102306f79658e34e540299e0bbd7010001	\\x19f70d5ccf0090c300dd4671f2a992ee3fb19cb33e31dacda3416259270f2a0366eedf6873dcd0d4bd3fb37797d82e989b8c51eb3d9d1c5f667d2c678fd78402	1651402891000000	1652007691000000	1715079691000000	1809687691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	217
\\xe2cde2db6e5a08d8901216b0e4672d6d6f079aa5b6961eeeffec3b20e5f62c5deed6b13352b220de213110c329fd9c104a2ea8d4a42344f31258e0889f26e968	\\x00800003e7077cd180862d9dab65c75c5c6c3f1da5b9061e5896644cf7101299294822cff118a95ab73d01ecc863ec86023e0e22aad5a2fa09a4bbb9db78cc7554ee291a9a172f6fa6b377992a7840ca8bc60a8c00e02abfedcd466b2660a239e8fc320f37f282d80b2d0a87094b775372aad856c09c928ebcc9e1458d962632c19d6f01010001	\\x52977010f68e5d9e52fb8a3961350a21c64e6449d6706b4af5c1d726174b52d69dc67d6ed97afd36502558b2704ff73d7eb1705b5edc5a460c391c9d3ae9b909	1642335391000000	1642940191000000	1706012191000000	1800620191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	218
\\xe59d86f9a93f36df0a13eebed38e34408f1a0a0d77d37fe023891588798716f979820ee43c62848651d2e7986215231cca90701e60c68f3fc65d319db2f68a2e	\\x008000039fa39b0614efa52346a268281bb2b4d5e564957aa13470bee6ab7d5578b10f932dfb5516067ff96ea486f18dbeefc2ae251e28ffd254780ce8f995b2db159236dd1e1c0ce88565826e40407083289b3b89ce705cb496085d6d08edd94f7116d56aea8d2e2fc32cad1ee3968ccdd4a32a4f593f7a024d56a44281c3129eee79e1010001	\\x5c4c752cd5f34630238c847c71fab65487cb72392dc8e4a5bddc6d4e2dc5bf2e566d64e31b79d7deda3a1553a26df17eeab83a7b26e9a24cab1acd48358c5802	1633267891000000	1633872691000000	1696944691000000	1791552691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	219
\\xece9eca2477ab213d0c7fdbc3d6d29f2cc6c4b3140baed856bcd75f1a626dfab5dd58b8a0108d5ff63247fa82703aa7b7abedd26a564a962350e77a2833cfd84	\\x00800003e1053ac497028c44cce3ac670a2a9bf05ae8b3420958aa0419ceb9e02d92d881df9bd0e99839d448a6d197a6968210c075a8a7c8c64072acc792bd9a977819e02a4df1e3e0de778f12c1f6c0eaad323ac58c3568a4b1a735c87303828d565f70fbfb838ac86e66f9c0d5b938e2b9750468b981f19664c9a5437f914f0b9a482d010001	\\x0904858a28cd1757fc3ebd21f3a97af7c5ee3c7f9f0df27def6b5fbbb30bfd22f8a7ba469745e97c7f9fa70dd4f6405d9e0e1d3397296afb8b5ae8b0147aa200	1643544391000000	1644149191000000	1707221191000000	1801829191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	220
\\xec61379b63608a41bb25a6c793f140d72bdcecc3dd5013ba16a2c580bfe0ad8eb70c6764c44e55616848b0db1eb4d5e06fddeeedb480e04f821ebf128a97d342	\\x00800003c7a7dd4d25a9d573f364f29f76559aae041e00110658778dc80f401647473106cea29b6242324ac37f03aa7d60e3d16c2a3d2c3b3fabaf1fe4dfe96cd702872703452bc3b68aee8a40ead0fa3fecf0fcff86c72aff219751da8944ce1f30206fc43efc5c49ec3bee580d68df956ff246058c50f4dafaf28ffed76c15ea12133f010001	\\x0640e8cad942c2f7f0c677c367d23482c00dc26dbf14c70c613f1aa32200e473d167e873a6420fd0ca94c055e375d5384512af70304721b1c8444bd7c4ebb205	1633267891000000	1633872691000000	1696944691000000	1791552691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	221
\\xeeb920c10f1c3ded81b1b15b4cf8da3424a7f6ae97707fb00d8e8e0f6e1c48a896a1165b9de3bbcac1eda17445ae162ae871c6eb370bfdd57e77bb091a897e79	\\x00800003ae2a57a5d0d39cf9a5ecbb9d552d80d222ee62640330087fe3aa5a1419bb2898aba14292df84209526750bcc7b402d20369a54935f0c9c88230f66ae9eac59a7ff36ae5f853eef5d24bb45a210cfaaa523bc6819e66d81b12c19655c1cecfb51ebc4836b2a4d16a194ea4075b0cf7b36352e55c5cd2482e42a45688f54780a85010001	\\x7742bd88e8d56ce7dde182e0be98f7aafef17f92547b036dd5ecc62ed847bb92fc35c7421635bf327f4517333c99dde2fcdb23cdf45279f9284c69f4d9321a01	1654425391000000	1655030191000000	1718102191000000	1812710191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	222
\\xf2a16e7944d5d02f25e455ad4da7559c54fb0d6215d2bdc1d397fc269e8cc0299189ea333aa45961d13c8ec7eaa3eb2c98828f991411be5919ba24ef29d7d4ba	\\x00800003af9362ac5d087925b2e1b0b3ee11d7d249433154f9a4d6fea9d87301c8e9a5ee9442ff3a82848194ece7709e1601536ffad01b81f09ac35a443c19a7d451c2625880c174b62e42d4f7d4ffdccd78fd79f80f8b28e42a67f81f8b3adad458173682c93913999aff44e9e03144234fd259914d950222da032eb4009654865cd8bd010001	\\xddceeea5e59a5770b4e35689431b7dc5825cd95ee70cf7e0bc03daeff9b62686e2ab9404854b253c8a487225473b4ab6e64daeea5a6953450df6588b88fe2101	1651402891000000	1652007691000000	1715079691000000	1809687691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	223
\\xf4351e46478bdafc72f32bb68334212eb9bcfff924c537f5c3bdd5b5204f685814f2c4dc38b50abc3b4512439ad4d5c3cc42189cbe6e13ba8f6cf247329baf0e	\\x00800003d812d58c2f10b7f7fa67edf41e3d678b09ac85da741ba2ca45ae570031c1640331e865417f879ea6ec4c14947c02487dbb28a0973817ea033b39487ce6cdc60a314a553e4b7c3dc5d433626714ac9a42ed4f4a30d6829e4b334ef89b82d8440e54a2aff0976fe2eda6a514cb003235491bb67f47dfd1b736e676af8cc90d0889010001	\\x787eacaf8c6890d8f8fab14a0c619fc0e9050d6e31f51ce87c530712396455d38831651c06e6152dc139a089f66d036bf3dc33788d05f30134a69ba7576f1902	1632663391000000	1633268191000000	1696340191000000	1790948191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\xf9853b10d0c63740575f273f11d23516cbd345d20fc68ad176226df64f7eab0cb677e985bdb926ebf56c246f201c2ac263182dbb25d503c858101b037d043af6	\\x00800003d1fc6636f42314e043d63a40e1ceec7037c26095c34d523d374fdef970a95c548b31342962a1bf32087171a76a94ce4c24f055b9a8ca6ee31f2eb17dbe532648051cc8b103157b2510b23669e5be11809adeea507bf7f20e557f8c5a2531332fe57ca88fb41dcded32826c1c65c9b620d4827ddeb455b2423990e9eef1fa9b5f010001	\\xea4f03ee9353357e5a504ccefbfdbad30a4d0ffcb2f80b105d7d36415a6e8ab09df9cfb4f69771ea780ecb51421ec8c59a77c81cfce90e5e9c1d518115fc550f	1653216391000000	1653821191000000	1716893191000000	1811501191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	225
\\xfaed165670c05aa85131c0db3d8fc806bd4a4fa7b7c0150e61fb41b18937ca236e2c37502cefc0778ed71c27730c1e25f27c3825cf846b7d41116402531e0ec8	\\x00800003a4b43ac21002a647d5ea3b2838be89c8d10549bf7b6ff11a8fdfce4b4063b9b50775fa6e2b5244b6a0914e213b53beed53d7fa65ed8bee227b8448fe804e21c73e09ae23008f441b305d0f7434b591d1049f9ed04007688d180456e7ad7b13e24a54a0b0b3c83ca9a682318c63104616d28f0d83e21af19a19be30282e36e285010001	\\xd4e08c01cb657805ee2d0f556401279a2dde743b42bafdab08c2e63bc49b5ccdd65dc84d93ccf0e13d7922523cc379ddc07232812c5653280b186335b914cd0f	1656843391000000	1657448191000000	1720520191000000	1815128191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	226
\\xfd05435245fe916819cf416b131c2bbc033aad0553e87c6e54f267a602b96e6c89b99075b3a10332f8c1e0ef67879544c48b462ff8d6d60aa917e7c359a16619	\\x00800003a1ba02daaa0489ca245c7de9b1007cf44a5bddea48e3d08bef04a4528f8486cb75bcbc52bce75905acc41604008aa314047c0325fc452b2831dfa94e4464e2c32864ae229f650e1496dcbf0dedbdecf6175a4fcdccf64d4f8dfd1aa4e4956406fe6263a67aa03e03bf9cc8160005624663f703d2890e036734f50b8c1b6fcbaf010001	\\x24b84ad9e79aacbd78b9c85c03b09731c24c5db1d450db25e3f137aea40837652b32e7ced69e8e5f2cc98e4c1faf33210ebe611ff62456df4b500f1db94d1b05	1633872391000000	1634477191000000	1697549191000000	1792157191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	227
\\x00ba5443af4ae2dbb9d220b397d11a1af7496dc4a5a8d8fe89e68955fbb2d8160f121eca9582e79cdbaf6cba5bdad804e1481e4bc5fa2e8fabaa4a8ab1f70a9c	\\x00800003cc779ab7115019e600049bc67d26c5a97a10db5285a7db5857d799a7888bf5dcf2ed1c56364669b06f07f70aacf22539fa023e211942434e8e0708ebd7ba0affe091645184f46c6b8d62865b6814dc09bcf8fbb436bbfb55b7dc8f90dbe699a68154516095e0a50071745677af5cebfc001efee2e10d1681d15f364917e006bd010001	\\x072d43d4a3d454af69e9f3e6d60dd5e41db98ce9d518ba61e0cd493b5ea62f3b97bc687524941d9f83c12e38e27c7fcac342e2016f9f4b859a7d2d71e6a1c006	1651402891000000	1652007691000000	1715079691000000	1809687691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	228
\\x062643153952388104fac280d1756b08fc0a508757e85563faa6b118df746ff1dfda2b2221b1d16336c4c3c507b99173a75d4988971aa1331793e24f39ac8d6e	\\x00800003d5e625434556637255e8865c3a591d52649c2afb9606d976aee302139faae7690272b8ee0d5fa2cbc302a467d2fd9468bcedfb9f6711e9303944c9702b73288d5264f16e8ffb44b567fd71c8e7f715e22ae03c8a9fd6a7e515ed30b47d2de40845035e0d00fff93ed618cc140e0e1cabe3cc308093b052efa2934f6ac00e3829010001	\\xdf8fdfbbd8b9e2e8c2e9320163da8120ac1fadfb1109ce0b1792bb0aaf20f6a9c86372bf63abe2f0562d28e2a72377579e3f916aed0d123bae622109c4a78101	1639312891000000	1639917691000000	1702989691000000	1797597691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	229
\\x0a768bda6dfcef2841aea33600d0180bc5593d97b24c85809cbdec3b79579559c5ca5e909041c4bd7fe127c27e82ffcb40a11a47d1cb9d73b8dd8d869d7cfd4c	\\x00800003b5831c05781b3dc7de5f3cfb8a19445b2a2f9b4e1a2ef1e4727fb0fd7540f3e624c10504a123017d276a58ef9f287b038c6abf90697c84370c364474a910dad19e0d5905544f26ddbde137371be80921b954eb876ac0289132f950fdadc2d38c31283ec84e86b9c68a60a51b151533211f9f18681efd5c6511dfead99d20cb1b010001	\\xd595c710829d227aa3be03ca355cfc330c1f95db230723ff594c935fe93299802a8a286c4b197a7c312feb90ed20552a6dc8e38187a5e7b895a6d3cd80661a0f	1645357891000000	1645962691000000	1709034691000000	1803642691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	230
\\x0e6a4983a344194f690c6e77d238e74741061c540542a0dfaf98befcd7f71075c6848807e077f6ccb9cdbb734b309feae3b48312140e69ed729c6d5448e1d479	\\x00800003b690653d2b9a1c63b7f92d655f3ced7bbef5bba85c463d20e81dab4e01512ebc9e03e5211a742cae4e2a776969c686b1b57243738f2dad938ff7dc19888aa8eb98ace7128d31af57c6908ccb8a6762ea73c88328d033f3076943391d7a6a6503c7bcb7884e65cf23d0019f50ac3bba45031786e22b987036609d4b96cd17ffa5010001	\\xbd3a8c1828873750ba742667d2c7d52f0e70bbe135ed287db8fcc244fcee51a238bcae8355935968d6ca477b25d9cbfab95b43dee2ffc348e9d4b6167656780b	1655634391000000	1656239191000000	1719311191000000	1813919191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	231
\\x0fa66c262e375ad40e02e2ecf988bc2da2d3cb750c8f7c68caa854e3916bff3146099e6257afa973c92168f4cda18c4f27b2873bd562a97fe0f1672112334a73	\\x00800003cddbb3d70873a1b06bb8343f9f121e3a041c2fa0aecd731cec55fed2cfbe540d795c5d22754af8dbd641b321fc9100e84bcd1c718f37073c4ce480c0a122dacca01ecc76c601c6f2764e2e60cac5b6dc0e9902938ddc11486d22f856b4ae3ffe724e6b1228eb21eae3b5898b0aa09b06196c25a535f8f903924f95cf5b080899010001	\\x02127760966234f93f98f80bb512bcb727e2c0b52a216fb78cbb471a355af64236c7bb2d26a103e760e139b00355b3ce4882391d254ddba4452a237727654603	1654425391000000	1655030191000000	1718102191000000	1812710191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	232
\\x116ae6da21f585a0366d077b050107d7e2628094949e3b24099831272e64890a773030e944ee0cdf9b91ecb8b8be1d82e9dd134bfa7f59cb70c19ad93ae3a088	\\x00800003b1f1b5170092252a0c1fb5ef0c0fd68263776eb1289ade050e44c3d6ee6fbd6923697622f78bd5f8cf659fe42eaa0417c85a041b590b777436a494e0faa2381e5eec2d157dca3878d0cc98e80e094ddfd448338198129533f396224a54062dcaa5d06c18cf1fdfb88f55358cd9b10ce1ef290ac5d3938e7511eb435f7438bfcf010001	\\x4c6f44ed20fecdc486d1e485fcce3df82c33a99bea500b71e2ceca6bf38341166730423750a0cc2842f99de9f57a1e067dfdc566a223c329355a53617d3a600c	1655634391000000	1656239191000000	1719311191000000	1813919191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	233
\\x15e67c803a3c88b11bf654c1612ba3f6b421b43b457005f1d8753bb0921d940cddaa1abf7effbd3e6457ffa460dd22b08270f6138f5b09fc7ae4fce10ede7523	\\x00800003b0ef541b67b0b9c8e5656c3fbee5807312422ca964f1a01d146322a08c7afcd92c8ea1dbadfce9e0fa5c0495a55d61cd4132031e69b71a93e680d7244997b3dbd86d88d7d80efcb9fad4c73cfea39942d9ebf364539efcc9c32d14d5d04bc10d7557b78796f0f2957281a314a88b4348364763e505e39c516c48133b5bb15aaf010001	\\x0feec0da9f78868acba4778c9a4c5caddd57e54f8b9e918a7b94c0eefdbb356ebe7fada4cbc5352bc7f002f29ba03fbc63a8d5af9f0b64685e101fd218efb404	1636290391000000	1636895191000000	1699967191000000	1794575191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	234
\\x16b2085d3904ef2f7b3f267781d361e5b63c899f0628fe048f1d76d46a455955a503e2a28dd4e74ffc5da7c68d5a3df2f4e4b198fe0b05ecf4a83c3c973b5c65	\\x00800003e505ec844194132e707f9a4388391c6f4b344c8e821edd0c7b646c578df385c69e070f030799bd05b1e0b8f650b5d7ed0834a7b363d64bd91a96ed3c864f2d65b0ce705379ec08cd9783c7a3db654211728805a1f00d7062d3034b7417e2a2f5388dc64997b32ddba446d7bab902a0f054545fe35a7095e6e3abe24cdf1b3d7f010001	\\x22d9ff519dc30bdeb2201319ab691578d2194b67763580af8f8e7dea76a4841c72f573958e16e93cbf09d3e6836bd6a40c2e846b18120f301c2bf50ede5c3e0d	1635081391000000	1635686191000000	1698758191000000	1793366191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x184e3d9bf4aa27338b554bb0761ef2e7b0a0ddc14225280af1b52dc74fc66546f079ef1f1f866cdb3f44c2ac2e4e3a86630d397916299202de77a02a748fd2c9	\\x00800003d879442cb209bf72e1a96a59f22edbb99c7e1affd7e0e2e9356c45b9f45a5c01bb64d23b1a0e37098a029d3336f05207d50158fe823dcc520ebc9ce7c4d39a90ead88e9627324a4ed2a069361fd9420290f1ce4305d6269b06c899ffb92bf320c387a5ee22083de7fe3228c3da71ad2d0a3ea17b7319903d6aeaa888ba1d99eb010001	\\x93301b3a34c0ffa19f753e355ad8c1aa4bafe85739efdcda41269e616ba37c488da393e0bfdb2f2f566aa5ff6424013ad114f20ab676b8d3ac24b3957a7e570c	1654425391000000	1655030191000000	1718102191000000	1812710191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	236
\\x19c274921ea0023d2199908490155bec074a6929155f60891ef4e08109f85df7f62ca3869d703d8c53615f018b0c8b4f7df3e483c8c884ea8c48e5d5a4828c26	\\x00800003accefab796e88b3bddc6d7c8c73bd096cdb34133d6e8e1891396663b335ed155cbf68625d8e365632d28c0083499932c2fd6e7b97a692da48786a393a7ad027a199fa17271207f4aa2d7a0dc1bc343075d3d08ca3a34badc0f4f559ce06159f495be7a58f1fdc00c156e551fd7e1f8774b629b6a2e3e97f37fa9c302f507c585010001	\\x12b64919213a69eac8580b0d9b131b03c544903acb2c2f667da5ca042085f21df88cb444d15eeebc57e8aef9432f89042184c8e4f5f76adb24eba92d9fc0ab06	1652611891000000	1653216691000000	1716288691000000	1810896691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	237
\\x19e65b80dc9d1e551130132337597d9286a634076d1e6c66f5f5fdbed1ecf4b95f81db91ae6360572ef9cac584b0ca9d4e3e3927cd1adc6fb02ac54c6c566cf5	\\x00800003b1b96cb120ef2251e6a933b8b6b5cfd258087a25932693ca26091bfe0024440f97064f6eba032b86749ea9e269928183c8f2676b422391d710c3b82cc7f2892798d2d41a6ef16092c6e556ad75f83063c817e7a1de9f5090825146c23db08459062bb6847b5089828e2969c9392f3f5704a7b5107a1136c864d3a3f6b98e947b010001	\\x16983efa9e9b946ddddaa8b617548f87c05c7eefc2a9a295185e2a4baf2ed7af94d61bb8da39b9b0f1523556f0514bcea1e173c0d3815e11aa67b86b1580b000	1634476891000000	1635081691000000	1698153691000000	1792761691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	238
\\x1c666b8b35ba77cd61ac558baec68d42d9c09ffaabf8d3e449512e68d44b71018b65a4d37a0ff7b1ce1f5255c1f3a52257e6c30530a4e43b81080e62e2755b2b	\\x00800003cfffea2de8393cf6a048208bfe002749cdd83a136fb8c29e336eb69f1fc2fb4f7d08c5cf13a70f59dade2616ca2c6b30b22d6909c9b0f71308756e80f3f4a8b4bccae15e1418bd100ea1d31f3e1667ef72b84aa299ee4faa0a5dac9a27f9d3ada8cd262cb3e30c3815fc23137cdf6bf450d40a2a57742a4e130e167d1552c829010001	\\x79ecc83db4968c74382bdcee616166a51324bd13e1114c40f2d2fd4dae6dedce660ab97868aa7cb7bbb806c1afee5e243759439b17c4048c5b3f182fe34f6d0f	1636290391000000	1636895191000000	1699967191000000	1794575191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	239
\\x1c5a009fd9d07c0beb8c41d72917c15400f774f16b9516315c6c0bbd2978ebb12b8a91b041763f45c7e31e9ba4d3af77c3ee7acd81068b6b85e986eb369565c0	\\x00800003ee40d6dd628b34268fecfb6eec406a805f0413a979ec7aaa7dd8143434c95c866f3262d5b6a41fc8f9b040b280114b845e1b234bc7f13d572767abc245a4e664f69bc75e69cdbd9a91e7569c9fdaf4a28e5ca33746e4f295f96f8e406fa00d694a58ec754761aeadfcdbac83e1a1e318e0046eb14af2f763ccb921aeb6a76d39010001	\\x3aed0d91de99cc2acc61ae144afe0939f86bf5efd9c0dc79793f2e0b9a4fe4bf8082a9304089088a7e5dcfc387c450f2a9c9eb2014349dcaff1c8afe0d036f01	1630849891000000	1631454691000000	1694526691000000	1789134691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	240
\\x1ec67dbf00c0e8d62678ae154a6a9d61c6023d107eca0e11f776a004955c982e1d2e76bba28d4fe7d0445f3220963e5e13184d720ccec205f6afcb625b79f973	\\x00800003d40753c96b9a166867c38ae97bfab6be08a17e92053f4e1686a91616c562cf50da9e2c6f8eff28be5c140471149e79038a63916e5cf7f799a7872e3a0e8b9ff8806611638a9374afd234a443a1bed8c0f577ea3fe2ef583ff4cc530d2d49bfcec1f029b0ef43ae29d0d67b1fdb546053a0bc4c1db7257aac2a493bc8fd6d374f010001	\\xd2735cef2c582a57ee092c6b213f3309701d467ecdfa1723d53bb5da6fc8fd8000eeeb5873f973bf6a080e00cb149b736e4208deb3afd95b07a67ee64dbf9006	1632663391000000	1633268191000000	1696340191000000	1790948191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	241
\\x23eed7c7c425678951148fc2ab4a938a3057870e5a4b39c61c20e5588881852a1181e449e85140b83736be38121b3d0469994d94abfc1f25f8fd5e9d744ac8a4	\\x00800003a123c67193279a38c05a260dc9c4a744b5a9271403e313df0364561b8b1244e1c01f96b99bd0af05f12b0636ac652e7617a0e46ce1b4640c0eef8f217a3d64dc87eb8ef7df2cdc1a1ca447a961014678b10f26b68f6f2f760dc3efd11c38bf0b6332b489fd3f984c7bc1cac5c6854f7b28deadc641e892e20feb043a7f247277010001	\\x017826b3b2cacfd28640d2b595576edf09a1451d427a29f4491c4c8e8bbbb80bf45d948f97bd6c108fbc329b144c7b00dcac2c13ec52857e63f249401bb4860b	1631454391000000	1632059191000000	1695131191000000	1789739191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	242
\\x248e25a02a5100bedbb2c91dcaf8ec3f32f2e1746ffd92bcfcae6642bda71ef349e7b779a08e48967ec5d8d0e3918eab5bf084cefeea83eacab83479973d8a5a	\\x00800003b20a26600ecb2b64a71c7c996d02c58a88b4af948e7bace8dbfa5cb0735427f470f1834c773a54b7a5b0a14f999ae3ab0f72ceefec38ed5fe35d3d248d2e15115800d7813059b694583b012fd95bd0e550bf882e37230834ccbcee7e1e831464247ed1e9fb19feba8fcb57a513fc412ce02bdefa20fee46061753e3205ddf2d9010001	\\xc5a4893c8cd8f0283f55cbfec7a9fd5c78ddf2acb85a38e410673545a165156b9f8d3327fec86931fa60282c84b114e99e68fca24c292121cdc007ad248f9a09	1634476891000000	1635081691000000	1698153691000000	1792761691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x243e8e8c4bc5ac3b47cac8dd5c5e44f99af9a29c72f4db884934873ba5f471215d33d826736e87d8e5088295b974856888deb5e3ef57846ff6665ad31cc87de8	\\x00800003e89e3b30c12396bef405052b30788b8ad83d2d37cb81aae772e87018e167a39647b47bc4a8d0ee3be8071dfd09debf9f8ce17a2f1bbe1a13e4fed630a8191f48bfc2388f121b2b98d12c61659df47e6c574a63fd854b77595e3798258fed639a126f01e060636b07df692b348fc4909762ae3124bf1fd664a03858b0b43867a5010001	\\xfe3ee9b1fc338fa44e8628f798a6aa33d992c696535c12a53688ae7a80556bd60cf3116f729e3c7d4d255e521dacc0036346a7f29eff393cc607943762f41f0e	1633267891000000	1633872691000000	1696944691000000	1791552691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	244
\\x25922bcc22b1370758e97d1b6f15a9b3cf806d3bfe7645f8ae3163da8f2f58ae0304dec5773b44494d8e5ed130a5124dab70fde8cd33901062da1617a29f77ba	\\x00800003c770f55919953ce60eccd3865df89ddda806ad56e89a47dd60e25819a337baa780a1a8b78fe9dce319743cde79840f8148d4dc02601b20bfd09012082986045172a7a48e0459f1e5a29726ec4300a2fb7ff528ae29f51fb2ea71bd1e6ba000f7fbaaaf3dd59235fd91c2126579358a73785701e96e0cd56aeee54834ee6f890d010001	\\x7fb131061e3b83efcc1018eec82d89ca27e9df869d5b6291f21c5e887df7722426b90c893d149593d6ba2aa6b3333d1ca54f63232079e5a52ec33de399176807	1646566891000000	1647171691000000	1710243691000000	1804851691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	245
\\x26926eb29b605c8cd71e4c67a91a9cb5b81c5921fee8d20cccb44219eaf828235d58afca696b2431e3e2aa6b442d28dc725bc9c7ef5e0cb7b168bc376b284bc1	\\x00800003b8cc98779665486ec72c86663ab0442cfe41e0f3b576cedfb33ad1d4dc5da50908b8af2ea245fcfb624e4f676edb4c57b392a5412ff3f14c5404426ff249ccddf0ef2b5f09ba99444afcc2e0faf72a56113a2650222ca39804697cb8ca012a88ec262f55457ab88dd02c8a432976e85fe191348ba64b0d0bb0e360378ecbe79b010001	\\x32547d6152dae9d87cab39e160c7ab2c079a12be7be1d0002048273af6096f410bd02ea66a35179b0cc65bf652c5716c71ea92d267b7814e2a38f254cc577a04	1647775891000000	1648380691000000	1711452691000000	1806060691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x2baa5019a8c9969d342ae66ec78d16196bedfb795a1545e7c8c8e1a863f22ce0a5c9a84c2a3efe59a6bd8f929a41b23d3597f0f540a46e35b67f3c616b8d278e	\\x00800003ad5768a8be0f7251163c0f268503b030cba9baa98c101f1372eaf47bc4c3b98b2a618e38c62131e2743f12f6a6b8a17b6e59cad03ae13b1d45f600f9eac3982ce5a1e567e7eb5b499ad030a6e70ef2800743b10265329ae490a3805d7426d7c5624a1aef0a70a8ce0cbb8c54a49204e89e8e51278e4ed6d29780e2b20eeadc49010001	\\x141d484b96aa93da1784133b80c2c760bfeeb861e483fe4b2125152b68432daaca21e17e2b245cdba9aaf258a1fa828f925bbdd5ef9482d76b8d48b4bd068e07	1630849891000000	1631454691000000	1694526691000000	1789134691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	247
\\x2c665ed70dc71ec94047f4b7e863b7abe4f83e7973e6ad746d23e7f8364853eda6d504d04384dca0c2dbc34ed555c1140052fa3ac11da29fb8ba753b28e529a6	\\x00800003d1952262d0d456e05a6908f566dc483e7e6a9b2500806a4427b88988f8e14b028a05f87d908a91d2eab129f05844ca6497928cd287c773bc6fc4446e43072461a8d46908a22b77a84cc767a644ac2cbad04c7c17820b1da7680cea17308febef503cb90590ec99751ba4bb59bb8f67669cd5a9066b8231016377d1a64eccb11d010001	\\x8be294847c5707e8552a9acc03b0db6cda9ff5f98eca2769820892c19ebd088d77e54a5931f6e1784aa73bd2aac632f6f77e9e1d6f398e05eac74dc885035005	1659261391000000	1659866191000000	1722938191000000	1817546191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	248
\\x2e729abe8b951c8e4cc28ac36d7f03d46d454c56e1004be2db2a79bf957c2aeef0619330791ce6c6e8cf7ae525c3d5fae14fae759befc66bd18429571a1d70a6	\\x00800003adcf0371cc7a5fa6cfe1d9e2c57ddb72a113f7cd4abce2f8f3348af27108546540efd61b0f84de53f9390419e40146fc1a6e11dbba67ad1cc3ac5458ad2bd251e19244b473b8096a57dc7beac5a9fa0a2e60002ee4d5b64bb2a354d85708e1aa2e607a8ffc0d58c32fc1c2c41e9593858565d8a175148978c405e02e3aec6907010001	\\x0d76079da00088e6f65983de0114dbfb91ddcaf211ca2091e402fcf2bbe362746fa10034c8e0709e4c7354c7339a9a757c9127cabc425b800f4d4c5bae168102	1652611891000000	1653216691000000	1716288691000000	1810896691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	249
\\x311e447a3826f579d24e241ba5e401dd562740f37a32bfd65e4658095eef57e8a1bae24baf0948289ee2a75cea02ce359cfe9b453d9550078405384947588227	\\x00800003d42e99ad013b10d658505e6a9b3b8664ffe553a869ff93688704994b5b904717fd0a175a1cc95f8b030ace814fb433b13ac531e83936e5089872e73f7d7d54c70d5a6d0f9a6b998003bef4b2531a2d5e5d638f995a83ca5b75fc6cfc4e1d6d7eb05985031cfefe9e10f39c2c7bd3a0a0e4838da0412921dd143838b33fb21133010001	\\xc00be5aa7b7f5f9390f879fee6d330e8ff710399c831d1c1e6126cae31320cbc9f0af607afc65911f492bf8a1ddd31e150b97efed11c8be44f9b19b1d3ed6c00	1650193891000000	1650798691000000	1713870691000000	1808478691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	250
\\x3172fd2bca71e74eeb18ba7944d100353c3ed3bc63b010c5549ea238bdf7d3e8c8246306cde5d09cd2c0ee319a2394afef62f6d537a9a48b4dab27914b24141c	\\x00800003b7b97609530979d8b968abf736cfe13c7d8a58c12a6591e0cbc5e945380af37bfb77685f3b8f9de40d2603150306d3b1c7a4037d11b37819367446e49715bd89e436d7b85a5b67430d7d3ca3a5a86f6199308d97804995b4e1cc8bda4e1da1cad87907c91857423864586f4bbfe5cc00643627851129b99c50f0c100fe5dcc0d010001	\\x8a74238a85fdece0e76c1b41b90639458ff6b6c1cdd4b1fbc4385d97a2d1cdeebe7ede6d196e6ab46c7e81dd9173044c3b06fb652ffb0911b5a8fdff38dd5204	1636894891000000	1637499691000000	1700571691000000	1795179691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	251
\\x334aae358d8f0c26cfc08ed5482e485ea040cff4faeb18c49a7b8d27da5dfeda4fbabf19037da78e9dd0b95dcaf621d316aa550a719f0a0dfd7691bff59ead6d	\\x00800003b96a8761c05da20aad4aa39ec789fc5cf61c4859eadde1a9c960ba14551fb500350fbfb04aada190cb154beb85a86a63220c308623845c7cf1c12c14fe50fcb82589e674e170772ec10356acad756b8a54623950257e2253257eac604be2e36815e773a4b4804c45fed1e170acdee8d76d3c629185b92aac3b5063fd94869ef3010001	\\x26c064237f7287c21beb06bdb69ac1cb453e4b1713f299363fc7cc7218f386693ba6a6741d63e2d0edb21dcba6405621f970bb3fafa0cf388c3e34925b50e903	1631454391000000	1632059191000000	1695131191000000	1789739191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	252
\\x3e36cb41d44f304809e585f4a22b4c000da5af6c3f67e6d664512f89fa38378823c762823f11af502342a0081d33adf29bcd155d1a8d48f508fb8a2224cccf37	\\x00800003b1a36ebebfc13f59abe73b4729c949348fcc86e8a087baaad84a1572eb8b908e0099e7c172f2b0fb77f9980bd25008323817d3d43a277a7e583e8bad9a4eaca4879f034ebbc2458c7d5d88734158754dfb5869d4bfa3d52d9c8728ecb7cd67128cc3502b121b2a560060dd03eec439c919b82c560f5fc618076cd7c89f141203010001	\\x522e43dd4b2fd4e704fa3699c95be56222e053c7ea3c8483046e0b49879ee6414eff84f858cd7f9bd354d04cb05feb2c2f0631b83b0541c4f62c324c6eeb820c	1658052391000000	1658657191000000	1721729191000000	1816337191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	253
\\x43d2527b85b078223efdb94ef66225149acccb9a8d9a13a22a145f6b1865d008400480c9c4497770291e8a5fa819bff6751ecb665927c9f06505b1753232492f	\\x00800003c8ed52ce9177712647dc2c643a30cbc5e076a50e4e7aec14758f4014d5a2fe0eddfbb4c79204070b0f5b61eef76d4fef90f5367662d9bbfe6fba5a702917d48931fd2b0fd76d68b76c375d8b685a3625842a6ba7d64c4cfd8fcbd90fd4b75ebb45f71fc90d54a40390ad0aabb49b2c4119fe718598fb16bb718474cb9c53a4e9010001	\\xf7aa87a2d91d342074405016e8a1aaf4c7133f8f0546ba392a6d307ce1ed669d8336603da30410705347399b14fc34069ceef26da425a054b8499991ef9a9106	1650193891000000	1650798691000000	1713870691000000	1808478691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x44ca05cff265bdd1c95da45cb7289e335fa9d581d89adfae7df9bb302be6fdc0561df351d6c5eb503259b9ffaa724d609f8b2d8900b3e08db2a7d674187f141f	\\x008000039c7df56b577b95544cbb89b2a91e783cd7a441d6f8b2f00a8380f621450111700a5e0bb3ea444eeb24b29a9cf0bbd9902024530c77cc7e0ed430dc721015d7098a0fc2e18c443a63a4d6a4bb90586880dccf7a1dcfa5e41775c9cf235ae9aefab070736a1e99d7e94affa48ff2b89ce19c7ad1df09a2d30a4c30fdaacedd3e77010001	\\x086c21d80398122284992289b11aa7419a8ab3cd9dcf08d9f4a72972d3bed92b1180f0236ed400c5d807d591b9f947615b96abd059df944e97e965b1832ff000	1653216391000000	1653821191000000	1716893191000000	1811501191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	255
\\x4cfa37e570226c4a08ca9e7ec6ff1d9221595e7b40e794e8507e9f378e2ffcbad1887df8266ef04576af49d06221547f87754ba43bf025911fd29497a6f527a0	\\x00800003b5d77529e56124ae9d752e191332cb685dfd0c6e549e9711663e528b253b21b2e99964e20897b0663b1ed0d028335f13ee009d325bcfe2fd6ea964a7f2141f7972a29b1cc5826f1b91ee6a8709068c875c8c7d819e12a5e55af00f90a09acb97776ac320c309af1da239b0ebdf5db2bcc2bf2e253aacc81b945c0a35bedce08b010001	\\x36e830ac232838b025850bf747b7eb8726423278e7e05bae2fba3e6336ce73d42ba176660b93f09d8d94940e49cfb58d5f5269afa19341c34a5c9e5b5e6c2409	1634476891000000	1635081691000000	1698153691000000	1792761691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	256
\\x4eb28570074870dc5f4173ad71a778fc6d2784cf116346b508f29021c7cedd443215dede3356b4f14536691f905d8e2897ce2c1468b66ab8ef66d960089fa356	\\x00800003bcc4cfb92f8ccd2828f80e69fabca5fa7bad3728aa8d03e0bb98ade6515c9fbc20e59f0688cd3065054eae89fa7057eabb11e709ab953acb4cc8d8222225fb2a2915cdee409cb268a1c508414b6a6d1d17384ed42bb92922f19c48289bd855481b6c1c520b680ba0316611c051336603b54012add33283a51309fe53e80760df010001	\\xa91c8c861a28c7a82f5aa9a8af82304a3713b22d9dee9e8b49ce500cd6ec08f27a8d0e433c1d01f4d8b5642ab8ed51709905d1b02633a254f26b7d1140c02306	1656238891000000	1656843691000000	1719915691000000	1814523691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	257
\\x522e66641a04e9e336551768ece2a7bb37a2feb3c2f7ac9ebb5d7c1793b1f9cfcd29b86841ccac6b6d6a6a81fa9d89c71b438411650c27564b9fa75108f7c322	\\x00800003995b7174dac7bc457ef2cd0933ad2ab81833e72648f7dbada1e099028c835cb4df697edc6396e21d5f00f825b5016c0e0cdf25b34e67f8a3e4cafb55637b42d14a284324bcae713089754317abaeb38260e38995fb0bb7406250dfc3ff75aa14920805a3385d37657aba449791cb548bf016b6fa5ddc7fc2ef720e6069ad26ad010001	\\x19e9b8283007af23679007a387082705420596bc888c9dc4e61aaa897956a593da83f74ab70c804df1c5219e1939dd9f442a1bba23cd4acc31886179445c8603	1635685891000000	1636290691000000	1699362691000000	1793970691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	258
\\x57aa0f388df0fd05c50f19f649aa17a7d5a4b70a6fde93ed6f6d065b11023bf9470382126a9262c78a7162ed128618263de639b69d111fa8fce31b2ec8c10fd6	\\x00800003c194b6967d19a1e4337529b686f96919a9a97c032047622d13287d625b3c3c9e194db15ef7ed674497aaf721dc6c573ec0df49ce8564c052c4496d54ab4e4e9c955cfee2152835f7d6d8eb90a4c6c8b7a6787f10a76eb72287deac52ab24edaac821adacf8550ddac3fba2688f3496869c229a4e989cad3d36688ade302ba77f010001	\\x466de7bde74148f2e255f1bf3e2041a994b428b660f489c2439131fc310933e0663542287b974dda83cdc9f3183733c1b9da2aa3cedbfe1dce3c7b2df0c6040f	1649589391000000	1650194191000000	1713266191000000	1807874191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	259
\\x59be73c97b2fa89da1ca18c0f1f5af4d9346c2b2f821c871d6c5f1ba8ac7b05fa7fb6a56373601b0db614b72a27155b905039c902e22dd2eb8db3d96394890ad	\\x00800003ef50435b7ebf75b397ec7828a64ce4843b03f0be80a2c3ea6aaa854aa76c73646c3ba1c1be020df8af1053e5918fec8d00b8a0460647e38b99b8d3c210d176ef974155a4e1e02210f0ec1e4e9a1d34ee48e3ea0dfa1d6b0fe65f3d93e656d08a9f189005d9bce813e775d7620b6a8b6b378553bfd7721a8bc6ff46b9525a6201010001	\\xe20ff1fcaa119642ad92ea5eee613c3c45c6033b858ff5420ce3906aac2ec88a70c5bc6f11fbaccd21882aa2b59ba1813735ca271dff84c5acf86993e87c0d04	1636894891000000	1637499691000000	1700571691000000	1795179691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x5b02bb5cc447e1e98318a493bbb5e00cbb9088b8c67e3dcc2b1d123e0ff0e47fddf888d5e72641990ed9223290ddf2cc5c6b542beb0640517f8f38faabfceae5	\\x00800003d3401705912279f8aa8bdff83ab9f135c28d54c833f0a556ce57b668c86113f94941cb62b2178c58fbb074b9c135f88f418c18c44e747744d0f30819e8ea129ae48cfa309d75aba42ead90b449e5fd7bc05494c5122f8cef49fbcce2d74b03e560b79da5df54455a205f98b6008dff84043a450c78b8be65ee8568f919b28225010001	\\x007d1a1d5254d1ed6ad0ba69ea20576ed29fb1f2351e7b88fb4cafba062ac5e5693fad6b85c27a18712be467d75bec682db62fbb3cb08c0f46a026b59896c60b	1651402891000000	1652007691000000	1715079691000000	1809687691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	261
\\x5b729afcab2c02495a00ed0d561554418574fe3b406fff98a73b3190a34c4e2515ffb4361120e709043a721b56de8fddbe544f6f366fef22827480a9a4bed2c8	\\x00800003c51916a77c43b151d4c515fc9294523df4009dfbf0d0f945d17589b7b96cfb24c4d109f64b2c1955144b18a9ea54cda84122ef8a02cf37c5fa32f533b044369c4b6fe1988005ccf1088f845bca45c89661ab150cf0357ecd7ca7b75277ddf0e06341c26a013289ba3ed7205ddb54591df17315972726fa40711abf633dac1c05010001	\\x96b39bb086d75a276912e111bc8da9677c61532f6c5c37da0b371d6fc8e44aa05f9f95d5215ce624b9a40723fe46c9fa6e6da255498925e79724a9da3d25f407	1632058891000000	1632663691000000	1695735691000000	1790343691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	262
\\x5c46025219100fd55936a07f340b3de1df7c97cdfaca192c1337165f73cd56ef9416f9350dec8a7418877957c2622d25c0c5fa2facd24615c320a72675a54867	\\x0080000398ed1a25c59fcd0e2da952b12e55fc28b634e25468104b094bde6d7e03c4ec387d87e33e5de630c9bf1f885d7e56b68ea1dafdeb14dc21d357da659b4d2bbc1694be0e64507d37661c4d8c6edede35f0f0e1b861a6310e712e31e9a987329678e5cf85d883f64a10cd6b7f6c6568c71b343dc72a56193f4ee5d96377de75b655010001	\\x484c48d65f35c5e7174624f3c9498197639bb5befdb8363cb46d170ff81466d5040a9f5f580d55ee1011863a4fe515dfc7fce7bcceabab5209ee03db8240890c	1648380391000000	1648985191000000	1712057191000000	1806665191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	263
\\x5d5aa0235d1f4371c25f06c38c05f57a29d930e2e36b7aeb3189501a05595dc9682a0904abee2b190b2413c73a688176c3b3bf60af2de837e9891419525d93b5	\\x00800003b772513d600fe0fe4d7e3c71bcb6bba2a40ef2cfdb60825b2913e521bd7eb8279ac1a2a9e6eb56ba27b97f347e1b2155b6a3ec36c4ad3bd273d1902bf18330c9808610cbf0b8ad95ac0ca0e33ef6d9cbf67494ceb64be74f223774eb20c70d703c1046d1816a940c004a17a04aa1f851df364a5e6803e263bde6ec7fcd8428c9010001	\\x08543247e985aceda85ea2442584cab15c2868b3e3d7d549d7eae0a223f7f420ed7b594f711c694a59eab0fb58beb2087be4640d6eb9d6e78b77954e1668ce0a	1655634391000000	1656239191000000	1719311191000000	1813919191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	264
\\x60b6cd3730b6aabc386e38d52cab62b60bfab9074b7b4eb51c2e142b6abb61a879afafc4fbf917f98fe085275a61659426367d68146134d6908f741c41c37e19	\\x008000039810fdda07158d0004cee8045eacb59d6e7165768ca2a4ca27bea315483540639a2c6c7d45edfeaa03ec628cfbcbd2b8b108231c901ece8a5a0c4fee6d3cdc111607422afb128cf1eda6a2d667b59afe55063d25daba415297f7a1402d954aca59a2b6ff3ac94315882023e501fc762e08fef30dc2cdee924d8414a5edd0f12d010001	\\x1339414c8c5899b1f8f12a5b97d4abc03de9005752ba28353bd4291ff32b6248f8014a83f10c817057f4ec9ab8d18dec4c12f8a4d39aaa7f2112d3aaaba92709	1658656891000000	1659261691000000	1722333691000000	1816941691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x600e09ab6b09b0f57c7b63a2724aa47ee23c47a6e356918b0e8deca5781b2f8a290124a1d287006d7a991bfecddd3767db16feeb0f4a5076504c7c410eddf35d	\\x00800003c205020e39d9b5970fa9ebb090e00a8316832e9606ccfa535de7844444d39c400938c951ab5db14a54b67fc7c232590036cd1ea96248bc49bc7d66676775f41c8e488b4ab07a3db91ed112545421bf4224886bcbd8d94b34a55552aac95045dfb33110b3c00b6d15b13ae5d57ef3e5e37f759c1dba9b506acc16bcfae2f3c33f010001	\\x4d30efd6ccb8007b76388e805ae5d8223c78b95882b2f165bb2df325c792ff575d570ac2540a21f317dca993461863d5ea2244b364b02e6ef3caa52d3a0b390c	1659865891000000	1660470691000000	1723542691000000	1818150691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	266
\\x626acf5366e44587d7f075c307bb57f3cd0cda620e5ff4a421bef0ab742854489e9a4afcc187b4c3566ac8b3926a490a871063b7837d4bd03e4c7c7db7240fa9	\\x0080000394f8256b8ab92f38007795e406a5fc7a0427cd1f97a0b757bfc166eca1ee609ba863f6c6abe1c012c7e0ca7b9008d702f9fccc2f5895995183e193a12e4dc0ffa4c4871fdae7aeb42d7874d708c53536c47dd739a7f22d512f8aff1fe474404dce4a60a20c6e88fd913e83b1e9f65e5d49e57fd2b0f9593a30780d38d3a0b161010001	\\x869a785f2214d0b911c4eaf2b874239113a0ae4fdb8813099c49a770f90e5321895eb38c79feac7cd5a330d9b737e3afd9a1081333c9062508c7d600d8a10505	1638103891000000	1638708691000000	1701780691000000	1796388691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	267
\\x63ceea374b5a7b77437e4082333eab276e410c46110f9855d2a8fc4a6cdff0358d3c6bcf89cb45736e242e4871104f63d2b8d2b22549b714bdaed8a50eb1cac5	\\x00800003cb057f349fd52fb7889d62e8d8e6919d92228fce26b6d6a7f5ebc689d64d5eabb33fa03481e93d3ca85b0ca91850564f9079812c51891377f45da92ef842b2459a48e8f71be7ce302ecf044c2fa1a5d018175268357b6fa4629b4832023023a70893851bd81b19bfd6fbfa6297683657a60135467fd09b59a1c7da83e2d33113010001	\\xfe73e05bd2e2d99ea70e39578c617e6833e1f80e3ba63d4e9dade6fed5c3fc91d2ca7fa40fdcecfa977d80eb478a1ac522afe631935ac82dfa3709661ff0d104	1648380391000000	1648985191000000	1712057191000000	1806665191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	268
\\x6682f24346da3fbf9841ed7302ad3365eecb3154d05ce2453fa9745d114d15a12cef990f96c40dca864f677a3ed7584481c112409b789d50e3d95d84f1d5b71f	\\x00800003aa85b09cb2ecda9c80690eaa9ba6d97b417cc0b8d6e514092be2d7c12ef0afae5d05360b5e6d07808032b46901f2ece92685805ff87785b3b0617e7bbdd29d0b32e16464422cf26e77a7036b269c318286ccbbe27185cfa8fad4ce408f2dbd55776c47ae9b512e1572a3b54f3c883f5d923776fae0a2db859026f2ed254e4cf9010001	\\x07291205ba9e6d701ed63757c96af39ecf0cddde9948d124056acd22beac788a08cb3576de7433209df0839da11e93872a703b4c6c967646f2fb41c5ad98700b	1642939891000000	1643544691000000	1706616691000000	1801224691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	269
\\x68f650399cc93488de1b7486d35bcf8641251581d6ecc5deb0850f632124cabdf15fe708718552970a89b36c5e133729bb8d66c6812deb68a594ec50ff4b8b73	\\x00800003bd62953c183acd2f84bd2d4d9511af58e8445d31fbb5e47c483c28a2d0a833b4c46436d1ef729e487e89951a3be4850447a9d12cfd0d6e741482fbb63011f989886f91d37ce66504c8dcf7ecc54f9c02b8a367119070108f5c69994aebecc815ba7454dabba7724d3d7e9854a70abcd8038f360570bbab354720cb117bc36465010001	\\x0468c4ba9f21ea77ddcf81fbeca5c8ec015dae1fe3353c738fc30c5c87acd2bf5b6b6196f0f8e7e3dd2431d0f133e93da08a95ff7b580415fa03f6bdcf12e20e	1638103891000000	1638708691000000	1701780691000000	1796388691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	270
\\x6932f805055c9bc2a562d5f1213cbb5133a204f0ea2eac545007f93a9e4cd87bce1dece47e11ca4458c628a9b8d0f4c520be1e4d17fb9598bd850dfe3408bd4a	\\x00800003d18c24f5d8fe3ba717ebb5944ccd1730885f42ecaccc596a7e3b8360eac1141eb973829025c8cb06b4365a20388812369f4147520a8aa188c407fb3b176eadbddb9b19f390c4452f79b3fab7d3ca524a6583de81adb111afbb4da3e4fd9a7cec8f17dc9b5142799b78a888767b14397fcdb614c770f5e1085c1ff0a515b0a88b010001	\\x5052608f72d2b1549211a671f9a77b3820d5b4089ba50a352e69e37b205681baadc325647f480d911712c394721602b4cca8096d8e560f3eab00483f6a54300f	1658052391000000	1658657191000000	1721729191000000	1816337191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	271
\\x6afe85e2152a1bbdeef8c50f55bf41453f88d032abdb85de42129e129edbb1021b307d498611dcff12717638aa97fef18ea1c1cb0eeb7134cc58172c5af6b640	\\x00800003d6a7966b3553ea786014912919a7ef7fe3920f16bcc1ac30f2030580e2d4cfeacd4071d891be4646f0d4e270adbe9c3672795f1e78f1d5d69c5b73cbcf0db7a63d5a88545d2b885a78161cfb59efda57accc8a91072cb261a94002d2ee3ad719e1a6d4e89f75abc0b661729b3b41ef8c840797afa4ada042c153dce24d9bd089010001	\\x54efd6057a0ab7e9acda24ed346cf9bf521bcc34aa34ed2317d162eeb246ca021dee67c096c31e52833192e7c4d551d7ed23305a72b71d4b55e2172256c20b0e	1644753391000000	1645358191000000	1708430191000000	1803038191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	272
\\x6dba26432eff84b3bd55beb3ba9c232619a8855e5947a36b6068862e897c9698f14b57de9e3f792f63b70ce3d6236822b237a4582d03fee9d9abd345bedf86b1	\\x00800003bc96ea0f723e711dce3b9a9e19ee46968e5ec2e3921509bded64c49ebd448581bfc041183ef80eaa22a833b5f91db10e73abdc86ea7e9d126e63ca7fe21c378a5ac4b74f941cad7af345239a77e9c499c2b8685ec4bed2f9fd7eb0e94a020c6d4465ce595ae6e10da6787e472ab14a7654a89701aab19f1caeda2bda4a0fdd21010001	\\x57d58203ae5245f85cba32f32e7aa1f3ffcf6e7b7fae1f863aa514d0ec081359d13a166fae0716ad6baf0221b475fe0089ee08c7703a8e8281eb549a4b72df07	1650798391000000	1651403191000000	1714475191000000	1809083191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	273
\\x6e5e05a8a924b315a7bdbe23f9b798e8394f32f1fcce35e3075e4e9409d1b1bbce259684cead560b5254897bad99e166078bb69e21936ebd3a9a68e82b18f681	\\x00800003b5c17ee26dfa401b3cb51f1003afcd3e34045152b01e3c6afd0b82822b0a3570f8521693d366163f67b2f884bd6e69fd8ea4c387322ed7ab2a9bfbd4800d11f483190b805549e0d7c6afe43828836c61a353a9ea3474d6d2ede49d8e8d2a7bec0ee0674a80fd820fd5bd5cc9c94435564887d4c3287e61fdf9d73477de36be75010001	\\x852e1827756ab1e2b9af23a080c2ffe283686735118b13b595fdbeb3c2c49e22c6a8e7b973fa1eb1795cfe61b6ac1eb5431331f16f59f6753559cdb1e9aad908	1643544391000000	1644149191000000	1707221191000000	1801829191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	274
\\x74f66ee3ccbb376c74862b9c52e587d64686decf0d189a586e5209e1702dd8ada6c26255497eac5dd7c153d79fc0c475630255f47b73d26d596a4e7ffbffeb12	\\x008000039b4f075c2dcc616a793337098921889d109e8753aee3d489cf8776d48dae6182db167ecb4be0989ba4f6fdd21c5ac5a695fde722d50a3e349c9008cb3320de908d93235cd48b035fda9bac53b27d87317aea8094189410ee044752b19a8ad9d20041cf44cc75f2337e2cad6a4bb6cd0eb31db8ffd99ca3aa932195ec66bc7cd9010001	\\xef150cde281639fc919462ad298536eb00ab920c97ae06da47d50df36e5a6225e8036ec01f5e4afed2d82525f2bb992bae038cff472435390c6fbfb52b4b520b	1634476891000000	1635081691000000	1698153691000000	1792761691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	275
\\x7baebe6199330020075c03ca7852a9bd4040ae0b7a372d92ec921371ee9a978e25b5dde2954f80f11997f57465f2549b954a142e7a73e1b4dc16738883d9660a	\\x00800003dba47bd148bb14a9fa4a4bfbb5808cee64901c08a5066c1f0fd9f261c796794eb7a6865591395817b2f22ca4eb0b616d607309ae20203b9c0af1b59ae7d7825a78a29d79f3c98b4deb1e06458e0035dbe47207f5c4e322c5e43aa86e6eb5a482ba257a0ccaacad3be599e21f608921332be50d016da79b2be1c6d2aec0ce9ee9010001	\\x9936dd1304043b67cd5f8789d566a6381785c86e8f1ff432e08006cb69146a5ea229943d7dcc85704dbde2bca702443a3e1abd7019c9456a3c66d1dd6b9e650a	1641126391000000	1641731191000000	1704803191000000	1799411191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	276
\\x814ece6fdafddf38eed8565cf9610f7de6d3e288dc2c253fab5e89a383f4d329b779aa2b3b982692ad0fa2ed976acd9eba36b9fac03ff488c9c7cf961651c0f3	\\x00800003b5c8e12612088e7360708a19b7c747c48a91a7a152fda9dab277a7f2ab0b65a707e826f571d53cf58106e706a2509d190748202191992059f173bcf2e2a80a85a8ba5ae8a0ffc483c29de600caa8746fccc50acefaa2a8ec935e86c05f1f748e56b1a4ab9e6174c6b3e0da1633b5a185115f917f651f432e6ae137ab2e1dbf2f010001	\\x7256eb395f5401e70cda0729ce56ec150d95d3dccfd16c665ddfd855c2d073d2bbb8696bf8af8b18f74a009d8924bc1326175797d8d064564bbfb23f9bb03801	1656843391000000	1657448191000000	1720520191000000	1815128191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	277
\\x811a79ab3e460479ab4e48681599471d8f440ec54f626373d253bfd76055124e1be49a0d1e1ee1f8fa40feada738d7c6938a185a1b8a1df4d6ac361778c7b286	\\x00800003c4b5c16d37cda734a1910cfa3a43c935aea692802fbf3523c050296a101aba842c84127be81c165bfa775a90e6c2a75c3c20d822529b54de5336b26a6b75f8599525ec4d87c066f5cc0974b4f13cc33f6f898f3682fc8b64364a417863d74f54d954dfec19ce87f103fd74c49f210f15c6abd8d56d5ba7368eb2c80fcb3bc3ff010001	\\xa8b1177b26a613697af502ce4ee03481c2014ce1c2398a48c1ca10e99eae71120951cb04773efb04c2b06f491ef54d1f8461cd011acca1a9fa4f2135991b5903	1633872391000000	1634477191000000	1697549191000000	1792157191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	278
\\x8b6a683e0ab625f7d004123edb8db419a60b9040701cf8717db9a9eeee0d422de9a2c6b3e3ddc497946a9fbe291aed921a028667a393a4d8fa7c7e80c8cbbbdc	\\x00800003b80fbf0513a8457186b068587b5cbf185b299f6a998ab7482344c246bf59498c80b49ea5dd2adaf15b8537da97cd556f3e3a8e1d65d0f325ab7fdcb0b602691991b75e22fdda9c800fd7def19f99e19d44d4a9177b497ad71ab16d4d222a7d95707552ebc89b32b6e3ad5170db807701b7b4090f3d9fab25d6dfbcc22ce0c99f010001	\\x369c1340a06d93891edf2b3b4a613200f8798eba28e26998ce1b2fefa7f41bdc23567208d1d8f5867b22e7a9ffea6ec1088bf371d73db9c9e7b66970131fa90c	1635685891000000	1636290691000000	1699362691000000	1793970691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	279
\\x8e96d205fb86dd51f0bf8b06e753c04772dacb3620469f23df1d8c2726c44b3b45a0db33bf589f18fcce3e296ac6b0712b0845bfa092c2141f18345aa52604ae	\\x00800003d5eefa3ae41aa44f5a89a1f68bcd17a0ce1a9c300607099be4e88ff6b80856686a1ac78c81427eb30005a88f0ba0db56019a582a017033333a67c3dca52682caec455a023101bafb9efdad8fd51f59b49de6d35e09d03861e2050e0d0593af72f61624360b1a017f64a2d20b72b0d6c8db36bba0262aa7e119f62a40cfad95e9010001	\\xe763554b68e1ce339ee64737f58453ea6fb68313cf249827d9ecfae861c5907237cb7e8b3205eac8878f38eae8ea6a245151ba2191a6c478d834e6e1730f910e	1647171391000000	1647776191000000	1710848191000000	1805456191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	280
\\x90163552916d125118f59f90119f0c65396a5371fd5b68a4e3a9032518a0a31e986d607dc4de5df9c7195049f7503dc5a9378c6155f40d90b57027d93d75a244	\\x00800003c5c209821e79e41a55f9496c03fed7b3c98bc2d9d88daa8677c977f41425e2746d6992f069d0f2535bc846b208fbfd3af9c61291d1d9339ca89757113e5a4bf95e5a8164df5f60b88ad184c2c0d238d4ab2dc67b0fe8246512c0379fae734618239d6574d9260e0060e8da122b545c3dbcc9204f0a6f715e2781516d59a5d499010001	\\xe8cbb9ecd2ee79d50bcd7dd11e669696c002b05194d18cbac92446323c4c22e6ce4943831d91c2888f2882880aa049d7d75b6db3fdd2e58e9702c43ab09e1d02	1638708391000000	1639313191000000	1702385191000000	1796993191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\x91361e6d3266365f618da85212ae0048f37f766652c2e11b1286195ea486a5e726588a75351842a9d54811f72d9bac3a1e04c2309da3491dd7324206a1a3e484	\\x00800003be9224874065dd632b2a84e8e75ac1b32885b0b526cb07f213caef819c2902363e21505d19d27811083154e19078691377750d3f79ca02246e584a4fc59752a2022d3314651cf9a3199570914c5e86990796f058820c57cd10fca1d9dbebf5eb3116bbbdd28b1d20cfe2baaf73a7da182f45d5314e3f4e28a94863fa5c3efabf010001	\\x34834d37733299c0b07d1ff02604e606d9f85bbc0a016f46f32cb23eb77b072d7bbfb7adc0d315f1a0ab2a9a82445fc91b77ea0aaad3c98303ea9e2a80c50604	1659865891000000	1660470691000000	1723542691000000	1818150691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	282
\\x931a071af4cd947942b0946e5fd1abc17c9d25e70be30ce74ccf8be545976952eb2ddc74ac9b1ce3aec1f3eae6d5b84aec8737ffdcc7cd1c603a3ff6958b7ef8	\\x00800003c42ad98ca741a3e715564c1de0fee09580f17eac3c2625322cf55158e7a1cfe6ed85004928612ebb1c1a06344f2d401f51511153a1c293ade62011cd0ef3688f35f83b42a1a7b6b8037694bbf2eb7b8b2c2fde5ef75f8194802f369ee7b27d0d1d1d205261a15082c0031ab39286d292d39c007a26e72415f57fcf8df440fe49010001	\\x55539231677e40cd471c23f06f02903c713f4da6e73ce53cc593d3fe2d8178dc12ea0320a3c93be4965b1325cd3a301003df235c11e79abd3312be14b0b38a02	1661679391000000	1662284191000000	1725356191000000	1819964191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	283
\\x937e76f80809f3b1bf038b3463d77caf25d732c7f4cb6edd3319afaee68dcc39bb4d8bcc3e488ee3899e2b00970b088b842d0811c56ceab793297e4847ef9e16	\\x00800003c118d08b95ce0cefa262ddd390a06b18a640996c966ed366c9443af06d20171aed76c3fa3948a9dbdad33c8cd1775b8ce6c055a5e37d0500a9a45448b61ce6a34e15299c3640c6f0eda8fce668d3f54345c1dc802f6618b64e319a19b96a9b6aa93b056ab7298ad825a86bd13331e64890dc7356820793d46627258924b7ade9010001	\\xddb21795d38caafd2dd25615f102f19a7fc42963a85aeb4141f765ba49da83bfa025b964ea409f2981daf833497bbbcd313747fc0496d5cc62cadac70f4d8206	1645357891000000	1645962691000000	1709034691000000	1803642691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	284
\\x96061da8cf5b37ef0d4d9d97e49960b6b3bdb97f79120f309be350ccc0a569e02f02ea734770b5b7b35671396fd35a75ddb54c25482d2758a812464fc5316588	\\x00800003d2751ea4a71489acf1470bc332ab7b8f91fbbe76e0f4b671a311596bc57ca00ca04fae99e9643d137b522b4e141d204573a26276374a9919e90fe58db52daa486ca2391030cb718a150d90e5b7603f344da09808a6517e2230f2240524a8f4740daba84ec0f827d346a36f943221a66ebd76c066b987c65230047b74d2963f57010001	\\x05b394902c9653f0d586bf6a2399191b55e7dffd6ce74bc5e5ca6e50c506e96fae5d1736b4610cf26b8b4487396a4446aacdda50735c6951cec03a77d7851c08	1656843391000000	1657448191000000	1720520191000000	1815128191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	285
\\x966ae9f8bd907f1d81a25461c38faf3e398050bb6b0f30f81e8fc1cbc9a641340b44c8410b1bc5ef0c14ce320c69ddd751b261f20a4fd5a1b4d8f1aeb2ce7773	\\x00800003d9adde0657ca79ef06739c571366a89f97a2042a246b945147e15af0f039b1936ccc7809f748d1b97374b1e7f7ff1a94a4b40f3c9ebe4869fc5fb7f9f18d7b439e4aa5a50714f964cd83f65dd56486a04ff3a76125ff884f50fda98e34f721b37fb0322f400396ec4d8fa04e6f36d81c1f973008b2ea0745b6a715eaa5564e31010001	\\x0905f5a22ca1d2a5c4c87ab6afe2a3940e03e84098da70f0d0657daaa495b126aa220ab46a8759bff20aa6d5e564bd3997ab5f0065d5d011f2fb0bbfc6074900	1643544391000000	1644149191000000	1707221191000000	1801829191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	286
\\x9982351152ff425ae2d27663dbc96a8e70c4f865c224aed5011065a717048eafbaf532bb7a4152cb18c0e961ff413863782cf36af2f4fed2edc946243d4e7ab8	\\x00800003d2f0814007adc51b2e7567361b2689b755d6deb66d256da1f7c95956c4acd3a01cdd97a7f76ca027657bdbc5e1e0562c73344247f07d6de6a3d559468ad1a183830a0fdaaa6a9d0a13bb7ccdc4725a92de259f0c5cf57ae7cbc4b0342065a6affa7bf40590fb99a92388c2657960178f8a76634a0ee3118407c75564835948e1010001	\\x5af0e4ba1aa0f371377f7d8c375992d0c1f80464cf5253e4cb5a3d080cc631c1b3c6d82dea52bffce1278d1e7f8ec59cfd98293456ef2d493aa635982ab4540c	1661074891000000	1661679691000000	1724751691000000	1819359691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	287
\\x9aa26574d20871d0a0cfd8b1dbfe96b45973a64450fac2d67d92cc9b6b97415cefb869bea63538f503eff4724a53451ea8b0af3a11647c4743fc5c06c5939747	\\x008000039cb78e4eba6f8ce70875cb01d922a11efb40c0f807639d4dd42008691611d7791496dc5fa59c69bd18bfe80675cee62c2eb58e61923e2f8b3f0e08ff7181da1732aecfae17902f75345343da90200c29a1958fc52a6927d86f37c191e470a8fc0aee6f92b326f65978344deea180c18a2c8c9955f26a7c3bf4f37c37bbab42af010001	\\x005c8b5ec885a4fe99116dd7bb55155b531dc0c4780a7632259e2698333d340db05b9d01f11434617b88c68b7973229d6bdf5561fac45c3efb5819143e3fef02	1649589391000000	1650194191000000	1713266191000000	1807874191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	288
\\x9a761f72f9597751717ef469d73c568ae3e924dcd0390c5fcea6b7b4e1aa029c705aa843ec27307b1eb116ed0a27b7bdc9939caedd6ac0c07a417aa1e58931a6	\\x00800003dd1037a96099285e6db7bf76d80b3bec405911b864faa7dc495cf155ed105f106115f2b01e9ac0eb34a3af70ca4ee3c655c18c5f5b708f6d0cdf61753f80218fa602aca8f2f484681f05781509eacc21027fded79f48e4220692b49f302c1b0fc8cfe2cb404323aca09444c58051924742701316498c19e64bace9d0da30e593010001	\\x97472d0b85609918ee0039bcaf479d2ab201b28a76480c395437a786adee0912dd200b42849147df925c84829c412ec065f0cd2caae850eb477b86f44ee7d509	1644148891000000	1644753691000000	1707825691000000	1802433691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	289
\\x9d6e2fba529c08c9ba4af55d4569f3283d3963795470cea1f9405e37080cec2b13cb1d07bc5484f65d1c548e0274d4b0c711ed8856200c4a97013cce3673c0ba	\\x00800003b8674041394a75f800cee22453e4d972079b1a2b24a006515729dbaa52e8cf8ae9889cd6ec16ca221bbb424e5804f31525e053bf4b35c9f2048f466766d1313d61f70c46d0635409b8d02eec9e4c8391c75dc9102c78c46dd99323bce2a8b72bb25c667259153daba5e85154ca0358c1bf2b9908b1903e786abb0f11d5aa38f9010001	\\xcea19424e6b7a0626a26ff29d014c6cb7cd5d656cebb643975de33bb2596096085e5b9eb5d1bd49e3af1d910b8c265a0a8a583628c50e026ebb76cafda53b90c	1639917391000000	1640522191000000	1703594191000000	1798202191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	290
\\xa0dac685acf4995e157acae9b0301484752b2c2e10a82bd3f5d581d9642f073d21bc7da545a204f1a10beafb6ecc92a507d4b571a3e34f0ba3ee5077fa3222e6	\\x00800003cb4258d74dad641fccb167c9731d1298e9c1fb8fbd390c633de4d928c71726ce0896eb01438a92af9782c613ae190c08ce293ab75d3fa915871dbeb4d47c77dd46cf84015a0d7dac1f5dc76e0bb2f07b21d8880a55183878276c9b050d85272669aecbe675689abb0ebf163bbeb1a866400eb2d57412cc4b0ae09918c03d4b27010001	\\x824d43cc472938bdc7676f577b964b2c3966f68c6eb23702ae3520a35fc4152b561184ecb3458c9d44f51ad0ffdedcfc68ba57d2a3e7e4e4adaedbf77c1a0c06	1650798391000000	1651403191000000	1714475191000000	1809083191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	291
\\xa0862c187c45857af4cc18fe157eb29dd877364517d38e8f9589025147e3de7f7e9a076b680eca3e115c51a2d00813ae667727e27912dfb51d1c60e19dcc3e89	\\x00800003f0570feadc65b80cb6be57538f71f1690e29a97e769414a985b2e11aebbfc16aaed01f7aa3651a1923732d0874940a64abe433b484366f8ba1ff9fcc9e504f14b2878747c675ad938694283ee77df5cc967ffa202b236a6b4d1262a37bb099704b209a3bc44de03052f0966acc097df5e44517591808d63332438011e0412a03010001	\\xe67ebb48900f6c1906923ee9546731445dfab3589b8081872cd02ea2ac545f8aa147fcad3e4624ed70132c90812e7db614ab4e85dc8de3bce099131950c2390c	1659261391000000	1659866191000000	1722938191000000	1817546191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	292
\\xa7aa75f7f886d60b5d5e7bb3c3ce3b5546325f99322b02dcd2e438d4163c4daea0b8e58c2739fd80483baa375e64e5877962fef1bb7fcf097e69e1f140f13e10	\\x00800003bfb5de8fd7016bb61e789395f3f568e8f839b7463970b0fd537785757205d3bc18801f58c7a684474b353d444593fc43a75ea3090e4dd13028d02efdc454a7698e2ff85453da1b194a77a9e0598fec0c8cddc10cfd5c2f70e42e73f468a3664701a5e5b816c5535dcfcb9630a646c7feb4a636c76c81879c1190807324650db3010001	\\x6a41da41bce8b70dea8a8465780aeacd192ce0812a3c6a26fcfb7d01bc28a2908126a017ec683f14e1cc7f55e5539c70af95f8f2e55458696cac4232d59bec0a	1653820891000000	1654425691000000	1717497691000000	1812105691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xa8ae4f2ad96d3476ac4ef64f457b4f0271cd63eec355b9cbce47d2b5f89202c0c94e23a7f681d3a539551ed4e08751cdd0a30e8971f9cebcc959875fa80f9b72	\\x00800003d31bb8abe82e871f386066c8d4b989fbd0b376c7773983cea4db4400a372a585c29c395432d1e6409f3a02ed2db8c182e1370e417ae6b04bcc456e45bb2c96bcfceef430cd7d2aa0ea960cef028945b165214b6afbb93e5d2a8289a4f68bd03465486b2a44bbf7ec6635999a0b6cb6cb2e9bc7557e578f7dbc23c413d6d0ab97010001	\\x72bed3bc8ad78cac2be6f82b7efaf9f58ce2f7e3a8409ba9a3c19b38e8d1402ffadc8ab0d36ec468260909c3f42e2037483d187957c81f1a992125b4d0371f04	1655029891000000	1655634691000000	1718706691000000	1813314691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	294
\\xaf7e08c500b923976ac4516304e07e0890c87b1980d6fd10b32de67bb484db3359935a932aaa413da89c3aa106c4787fd6a7648e0e39c5bbff004d423dbb8f5a	\\x008000039c9cca6cbae2f5da793c935fbccf6c749359e978da9e9fa078caf05923dd480386e43d8315d9765cc9a8b5d9c60e091bcfe19f45c9d949c600c47cfeba30bf56a95ca814838c3cd9a542eb51d2d71d48bc273d2e2b7e3f2faa65112397e2fc71cda8477d7dec9046da7b8ede165f0b672f0b4de52b255d823539069082f9411d010001	\\x636ee0363d61fad928d12ab06b05e22e70ed7ef41381d1989f7748790453fc9096d2d2ca6eadf3809c7497b07ddd765349c83f7f36c17f8b19ce3d08d8537d0f	1655029891000000	1655634691000000	1718706691000000	1813314691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	295
\\xb03aac67ab661df308dee3f1d75b5758fc2314fe80c12bc172f9a130c23780812a1026fa341880cfe39e66736533f42c0610296977f6fcb2c72357d515bca4a4	\\x00800003f666a57d96aaa14dcff9459549fb43256c3a513df687719115a8105b70662ef9d32acbc491a165472de6e80b9f8e37c9bc0de6e31818fd4024350a74e8199a57a9de14811b76c8db90cea5e53ffcd84e6f7926757c2dc5e82b6b3d7fb8b5928fd5240a37bbc2cae238927023d709fe87a2c1c7ef53ccb5ed05367b062187131f010001	\\x1ec61c25d07eddc0e34b8825a2f9ea39590efa72819a2ed56a1d08dfe7a20c19de0b1d1cfd8926f245a36dc27914b2265641f5895eadf916c6e13be480d20e0d	1655634391000000	1656239191000000	1719311191000000	1813919191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	296
\\xb39656cc91ce608cfa604cd9851f8ec189218a7efffe335e620723a761a451b3966ba17c2fe8fed39f4ee1cabdb9efcdbf7948364c5c298b35638c8dd8ec0d0f	\\x00800003bc4ccb3023ddb5eefd71e442a302953dd6b5879679a8c17b4bc1bb3ef2ba03d04caf211597be2aa140ae307e247aadd7f1457f9ae1f9e72d78b5affbb4dcb58efe1ea687557d08a0b7f2a57efe230881dd953397460fd0e09a2ba208fdad10dbdffc658ca7d613602a281f7f06b4bc316ae850192a29e052727ea874244efa05010001	\\x84bdcab87937c0c7b2d644cf039376adaad6168a4b58b2865a193164ef964a07e56e05f26584d2bee35629d1ee54b258f249566afa181294b8790580b9ef0b03	1634476891000000	1635081691000000	1698153691000000	1792761691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	297
\\xb5c6a4ec5bee76e538f6ddf7ded44f5e972402ea766be0289f916f666c6c4a291abe8ff43246de11084250d576654c7a1b075a2c822a5ef6461e770d713d5f04	\\x00800003d009ac8b3426edea7db7c30ac3975ff402c6a382e8e94fe683a1a1a4169907f9f95e58531b9345b0220a029544c10d9f805aecc77377d4b0e05bcbcc97083cd19f8eb1150badcc1a2bee7224219732e0ea1bae34bc0f467b43e5228e4bee8b3676db31b39af86dd6b70ca4420429b22d309ebd0a0af31c9364249f8c2083e6c7010001	\\x1a33c0d9cc730414fddf5cf609a14587648ece5e5ce1ea922164a48f60237e37bd6fbccab4ed1933c6dac11f78357c3ad1f738f831d615e6365c046bc32b0406	1658656891000000	1659261691000000	1722333691000000	1816941691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	298
\\xbca2f058af5d512f10bd19c7216234e3c4af742ed282696949ab8bdf4befcb45d592574f67692199b98a3cabdf4eb63cc36e63f69a1d316a8fb0f691fb6251be	\\x00800003c2e8fa3c99a940aa6b8744fc6c6833a107a2561f836f1599c78bf0cceaa0069b11984962a8bbb38293af6ffb0db265bb3e8e5a39974a85368481623cc9576f4089b9450144f0bbd17da221cb639cbba5c2b8009d2c37953a2735608779ddca1c05b19afcd8d3aa90d8b475a23bb0177fa4b81b36ba1fadb45b59f3b8625c4c89010001	\\x6ddf15a7753824fee139af7c39ca2d55c8d7a86ca5ad5feabce5faf28a2eeeb0b74ceb5a83048778df101830e2d415eaf52cfa631c219b63c77af6d37277e309	1642335391000000	1642940191000000	1706012191000000	1800620191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	299
\\xbfbe14565c113fef8e3e2f7399e1c55f2b7d1e64acdd01bd0ee2ff6246880383acde593c628da61de33c29780dcfb0f32cc416264eba20fdeaf7d288203b1a58	\\x0080000399c2ece5e9fcc0eceab205b8915445aaa24219049fff7d959cd21bbf1a98cb58c74cc9806c8ec9c6260a42a6361c7091c86160c1eef8ca10202947c60fe198870132a6f8c809110c882098c3a2bf1f67b1bcc6aec587fb899d37a7249c4d0b73bbb8d403cbdca12d8fb07bc00556aefd6c578e60596d65edbfbb19618dfb719d010001	\\x559ab7a44f1ebc477e30e549593bc5d19d82c87ea78f99cfa618ff5bc5202888ee0d37c1a0fb3b2358834c77c8396786b7b0c68154feafd296cdb759e52fdc07	1650798391000000	1651403191000000	1714475191000000	1809083191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	300
\\xc1f6f5757855b6b384d5707e77802feff15542d351accae8d337ccbbdb7bde24f747616a981bf64a21dce6b38ab5bf228a2ec0c42f85cbcff08e8d79f73de9be	\\x00800003bc11b4936d03b056382c4ca1f51d05633576fa174d879ad34ccfbfd9b448e4471aec63cb2494d25c2dcb89d348407eeed78c5c09b245ffc6835fa68674cd21c6d956df3cd5ab43d88a96cd3e8125918b89bda10d0e5360329cc8fdbafe2871beccfa0222dcec07b19ef10385a35c7e3738160055a6790619c4980f4314822785010001	\\x4c2dbe28dc9a4a90dc165f83bf4c78d9711dfb19d52c6528a2bad2403f19f7a83160fdeb3fa491f31d3cf25b2f1b51693ee567a98457841c4bd9617e26e4660f	1644753391000000	1645358191000000	1708430191000000	1803038191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	301
\\xc25ab1731590d898c9486ce3ae8e6027f451f73a9a49c1d5b634b097a8f43e3590bb3d2f5e137eb27ade7cea251b94e8b7e726aec2768cb9176c9f1078d17568	\\x00800003b46ba0a282496468579ff3d7324f00262a499d49f237aa449b511e4c89ed2625c494bdc6ffa1ce0c238a5ad03f171fa5592313241eb35e8a4ea074b1eeb2c065ab394d1e5dcf42cbbb0a1791be44ba1e05d87ac0d5c3916f147447ba95c86911b149528a7eb6196074f28901bbd2264cfcb697dff58de64d8fb20bf06bf6de71010001	\\xd1c6e015577ef8d079dec380d53b16d65f50a63df5aabfcca92dfaa4479e1a4608296ae8457a21b8ae7e071643deb8961d496effb1be7d26a2ff02c43e66350d	1662283891000000	1662888691000000	1725960691000000	1820568691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	302
\\xc7d21879cb4caaa7172e9b1e61e99951642f413697a7aeedc39e45cefef00009cb15fe2dc7f756facd9a402c7b695323b9639a889314f7cc8a014547017e1fc9	\\x00800003d815f8bcf515f775a921b2de07758e73feee39e595382ad38316eb7680549c7c081985ef04d4d4b7e4e8eefc3d74b0c95a604570ca5fefb9e59051cef0a7d1805f8e2c2f3831dc22410e7c10d32896f4788e16b705023d0ac6502ad8212fc83d88145bd5fc6f0cf2314caa9e81b75bd703051b345546113dc6ea90f217fe0181010001	\\x3eb5a0f93a93e3d6822b9c5f3025c46417349d77781d2fe32dcffd2d49f263dc0f7473706c6de3fdf58433c489a9b6edc2b07995951fcf034026e149b81a7f0b	1651402891000000	1652007691000000	1715079691000000	1809687691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	303
\\xc89a82b87f17b01b67ac88bc732c9f7e2c1e34a61339d1bf3e8f3df9ea84dfbe371afcb1e67c3b106be35edfd1f74d1524a93ed0b0b8877b13878afac3e30795	\\x00800003bc7d3cb05987edcad969d90551a457c7f3b938fb383c1afbfdb541dc83d935df5bc6658123e69103c5540a26e734dd25292630bd1430e7fd4acba14c7d898592fc31459d422782dff359bcc97de9810db3701eaffba26b1180ee9d3a8fd08bcf727a4e833dcee6f47eeadffdc08db3f3c6a7c4b9fcc21873658c186b32d2c205010001	\\xff9513b279e53b9b0644093f6458b35a86723a90b8aee61e5285eef94de6a5afdd7c4f4ce31bc73f2c2e6328317c210be1109f2b07aa33a23a0b171c61b9380e	1633872391000000	1634477191000000	1697549191000000	1792157191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	304
\\xcd96135d4cd9bd24c977a6cfdf9a9352ddb93aa0cfe0bfa24c93237804a471e0e241fecb14a54cfb7d919b51537387c2c50f2bf8b0f617fab3c6a66d2a71d867	\\x00800003ead72e9b98646b7d3182ae2abf74cabcfee7ab8ce4f1b98fb4fd1d7105f37300fb14284f0b5f59133e0c722d7e932765f53f68d3ce34d009e2fb12091fba93899a4b61fbbcc1edf346a22c4c67a5ce04a5284e668724c9d3060111a1e84b9d03a138a4338b29e4faf17c8d78f0a1e67a720c903ee594b08aa339f45f1a3bded3010001	\\xa99f9d01370b64e616ea0807ff8fe24d0064bd9f95d11b972fb313276fbc92018b390deae4e048aa4df94478083a9a427f9c463c6dabae0545f089efeed8100d	1636290391000000	1636895191000000	1699967191000000	1794575191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	305
\\xcd42f6fd161b92c76eea42a4f7ebb19b2f32cb267b5fb9c39b5e90d36e7859e67fcc464bf60839b075ea82b8f1ef5a1d9147922ef7c4c36ba15d66d1d403f29f	\\x00800003ba3dbb0b78b787cea08ea2fd9f248d4a8d55a7d4749d4602cf01fc98235adb66c3ea242f91589176edfd774f206c00fffe5ec7b7af4d33ee0c6511e6b5b659735b243b537d4e9c53d46cc4c020cefc671c0b31c552f2692a1f57ec6d027e4c956af0762d527d99e2e9bcb2a5167e580c3123348683453394d4d8cb8f2a93c4d7010001	\\x073330c7c0825ae3d7d2734774ccc759ec93b4f909406bd81d44f1f7675c413f028dc425a6c7255004395a489b47eeed593480cda84ce3719ae52dd1a6ecf90c	1660470391000000	1661075191000000	1724147191000000	1818755191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	306
\\xd1667704c6caf05eae26c7abfee852fe6d6f0b6a65abff556fca926f1b22e12348003933732caae100da416027da1ae6cbd17b3feb3974a0237ef4d90460f852	\\x00800003e883efd9629824001cc85886377f60bd90e8f74aa28f6d66e66fcf5645c2e340442566e4397f6a2d165cb20236facc711fab538571f674a20c9406feeb5aa6a99a3b63e920a8b844864441416d043d2a34be0596b968a1b68b10557207edb413ead84ce899e70b84862be665f3efbffc611e03279808456c98eeb48ffe1ca491010001	\\x1da1a855201ce3a08486eba062401a0de80369e4660a378ba99c59d63c8c9607ed7ba375134680dc146fbb746033544d59af500b9c03a9d966dffc7546feaa07	1642335391000000	1642940191000000	1706012191000000	1800620191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	307
\\xd17ad12acc6fff41702d10b99e20bf5adf0c3f1d0eb805770eaa7e9409afe8ea78156bd6cc60954744f4541e8bf7c8ef82f9b449d9aa4f3740b6dba4070c6c1a	\\x00800003d03a053c06b1d37e4cf96c8dc1ce8033679024f244b4fbebca0cfa2fd85405f1d695a8b20cdfeaf875a8ed4420e04afe30eaf6117edb7fd14cee99a679274e9366e886ea986bf7867ac9823be2876ee1c9a66080aa14fe635dcd97696db19a86e9fcf89531b88382e783518f11f5d9eeee603bb1e7a7d61a6fc254aa858a8ed1010001	\\x85a4c6e054ab4de1b6aea7d8a1e90b9c28f65eb9042dde547cac5cbbf5329121dd8d2634de7d600b30bf988609dd3918508572b9bb313fb03f5162e37b21350b	1637499391000000	1638104191000000	1701176191000000	1795784191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	308
\\xd4062df039e1a2920208f54fcb4c6f06a43b7d7cd98e733025a77fe0520e2b67de6cbdc120496a63af495f3c81dd48c164ab0f78940004eb660263811dc3f695	\\x00800003ba6b759a54b76a2c2e1adaa99034215cf446111c1ee07208c0c89ae3f1b125df7a4b802523aff49cc1eff730e710cd70fc8ebe01ecb2692e6d9ed566488a67cf34290652606baf9a58187aa2074df5acfb14921d0a35b6a019fa5b44d9c20cce3cb29b5f6ed70e879b9dbd08cc25747624a0d4bde8eb8a7c349b1f10232a7749010001	\\x5d77925c4329331d3be75b85d7d89515ec86f1f56d53ab49a5d16814fe5f9c419409cf939fd0e37d2fa6c943509b17933d04267dc9f6c439a6ee023843946700	1654425391000000	1655030191000000	1718102191000000	1812710191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	309
\\xd7c2765fed3ec7fe6c4a5704dcf18bd552a76f8e7808998f17d39ecd1958d73869b573e69f1c46008574669ff713ea0f3f7cbf099e57ec0fa55bee8536564c15	\\x00800003b579727cdc0f364e12c61d6d8274dd6f542bb9da480ab8e95a7ee61cd33faeaf6646d88118e94c26a588456cfc53d85160a3a8d1f4b3266e4541ed8b0398ad6b0fc26aa8d458173201d382d7e27808856f69b8dbf2f58ad1932c4c795eb5020ac1261ec4ebae1472a2deecd767d7729a3116c6ed9ca42e6e5bc7e5ef304f5d4f010001	\\xfbff4b9637d9aeec0baf7eba6eaa32c065742f06d89605f80ede9b0f74bd5ffcdb5569129f23c34f541c4ce9069d5d2caf1e01cc2866f16e7b4cf93046d66606	1652611891000000	1653216691000000	1716288691000000	1810896691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	310
\\xdc0a93b7410f30ecfd8fb8848ddc62169ac3e2cf80ae2bc136020bd47d20d278effcdb62a04e8b6b9b5ee16644dc4f70b36f51ce9871deaccd1a6f0a9c2c7b02	\\x00800003a86ec8a6c8cd2c753c9377b87aaaa934ce79bc543a6f3213a6f9d1327dce65ce2a9daa3d8aa9adf2ea56a15a261622ae5cd884f81e9a45e432e054f8a35210a4c956076cc727bb9be27d2b14202624d2fd7432f6aa6267fba7a3165ceca80b909fd04861fc018d8ff5eb16db203edb71061f57413909665077130e9f1c499e8d010001	\\xb56e7b299bf90af4c2aed8c33241ebf686bba7e441679e2a873854b306ffbd210cf720a8f291089b51433d9be8d7e9310df255966da958d38a56c0a22c07b300	1642335391000000	1642940191000000	1706012191000000	1800620191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	311
\\xdd3203797bf25736618f176b8a40f52f3963fb873db4f90a6e11d8282ac4afc924bc14a114378c650f02a068bb7792001c2118df67634606e1686bf95f0fd562	\\x00800003c4f1a402054f32743fc85523f5ce094a967d99a66bbcde6b62838711374f7ba04b5c8c36ee3ab69d6a666cbfce5f9562633f1db942abeb79de2142033ab5de637b2586324da2d5d9db2c3a9582dbbb9c046348d37897c1cff3f253f047698c010b67404c0b7901013933b078f866104248d940f91ed54caecc011c65ecfb0421010001	\\xc45a2e4317cb5c4b8f276e0bca6d64774e43225546f6697a6fd9d669a8c4723dc1ca90fb9fc8be7e6afb322f54c459e14f466312226f37888024cf72eceb3800	1650798391000000	1651403191000000	1714475191000000	1809083191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	312
\\xdf26ad259afd94b0fc0d448eccd0ec4eda113e1120cca916c85a327c2f4fcdfb91151ea345ade3fe86998197a2c903630ad8ef996701145b6f582201ac278a89	\\x00800003cfff18893f0661f7742414e129ce70bce3b103d986cea22d9260c152fb95d46fc0acbc2f029b09099d551b51b6dd084b71120ca6e4e07780bb9d3c6306e680e82527c2075735bb64ae76c48da6e17ca31bbde3610db54c0c9b93bea31d07460d4d5662154d807f87b45f8fe55ae22106ceaa7b3c54038d36bcf65e7c63c3df47010001	\\xaed372e1d324d16b92571af99ae0c04f08e06413345ee0fe366ade054ce17c492ab0f79fe95bfbed60b0589a58e557a15693dc8bada5a9c2904f02f545bbe70f	1655634391000000	1656239191000000	1719311191000000	1813919191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	313
\\xe03afda667d4e09ca16090b938d68f2e1baadb5e275e5ea8a046cc2d664aece6e2b2afaebe906da95afbd45b7c98072f48a48bab60cae7b9d1c8dccf175ed155	\\x00800003d8328d36ea9ab2eea98cc593375d2ab918a54a446ab000ac5f8e1bc237398ca686812fe746b1458759582cbfc9bbd510c1f9bc90de4d1e89551dd782c566021ebdc7e393065a6619625069c3f6abc315af5fab0c906ba69a22c19458c51e3fab085c02c90f73225fa29b7b80e06b29f60c7e42a73120cc7419aabf86fe4ce25b010001	\\xe14e1967ec593aaf621a04ba0c38d6ebc7aed1cd1e1341a0d6dc618609566e089edf804ebd73feebdc534dacd5ccc4fd51e61d9643dd457d3ed6530570a4e104	1642939891000000	1643544691000000	1706616691000000	1801224691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	314
\\xe566fd1356461dadbd3735bd7fd4ea6acb6e7bc785da5c2c44981c0a4de5ec5cc14e93dfe75d97f0f0338ebcf0cac3d652c6e97ad536d912e5304be109f85e46	\\x00800003ee705f940ef167bb7afa6ae20d99e5113df51d905089571dde651827b756d9785eb40670a7362ee7f61c93326dc8c529ab4893801a4a44b273568d073aa7ceac09d26d6047e6073a42bc5d2c3cdfac82292d311bd20037d9ade148444cf936a82a511629e8e164e0ee001efa0b8d1e278f25c36c5d47b31142d5aaa0963348bf010001	\\x57ab38f09cfdb05b88516bab276b71cf640ad2d3f3ed0787e0531bbd03eeb09e788645e2fc4ea43302268a02016bf8c6a80e0641017f4b073c4cea3189aac60f	1654425391000000	1655030191000000	1718102191000000	1812710191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	315
\\xecb24e8510ce5f86483883423c759ef0135905e8a6298052edc87f743ce8cd5f0aa5f907afac91e483c81b3d9978b82e1dbc87329677b0486972cddf18f9dd4b	\\x00800003983ea5287d8e5887269c4b9857dc80bef36bb383cb986b0a2c108292f4641250d1b29aa394665b680cc9cac710fec7352149e4cfe319d9140766403b7947cd18dd12cce0147a4efd4633c8d1a35051919b4c80d6d3e8cfa6bb85e8c6b471b968a1a879ecf0ca83377eb2ce9cb45afd7c564a5c7bbc8a0b405dbf19a76f26a4d3010001	\\xa47242b48d5db9a8c1d814e073eb5d012fb707912ce9045b0e021cbc581578be9087d62e575a598b1b6214f9206e31a7c3a97bb1b7232e92887304abcfe20c0f	1652611891000000	1653216691000000	1716288691000000	1810896691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	316
\\xedfa0a85d39f9eaef7d6a325f05bd45bb1025a297ec03e58e8221bf4e413deed627ddffb9816b44f850d23b214cec821083c47a33ad2a30ddc2140073c7ef951	\\x00800003c24e726e5c4bfcc2a1c88d49ccc39edc9f0f3efc1bfdf5f9d755ab543ad9bbc18f68b5a228d09c48bff055f02b40b65d7fcd695664c192c3e4e0c2292e2f8412adaf4552f8f4eb0783c80875b1fa03048ec318a0465f9bb5723bf68f287480c9eba989d3d923d2f474a312eda1c5b6c0623ca5416c277b41108cb518c054106f010001	\\x1e319f3528714c08db8798a725b1d5e88d28dd62afc35787ab39936582cbcc3f539fe141335e581c5df8d929a50b4f51181b794f97021b983a1f79b238ed9103	1661074891000000	1661679691000000	1724751691000000	1819359691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xeeae83d8db5757bdf04f514b7e33e2f7432ed181ac4dbd64f38743bf4037d9beaa0d9bc3eaad4e2f4ad5ffa605cef498a96c6a59a045826fe833a5931364c87e	\\x00800003a4e8051e5b6d7060cbdac6678dad22bdb3db72ccf560bfb8f242aac288465f3b4d82973756930f082111e29f73ce7dc869592474f635ca594efbbb662adb1f76d2b3746ea0467cba87a8de72c602abe65c8746533aaa7628af6cf70a3f00c44fa1895a6ea207f2c3cf5cd7a5ccf4f95723ea9d2d56d76bdc61a516e0469fad61010001	\\x9e8aea5fa51b938798c09fcc4282ca53378dd46399a1df65544f58a5925eed97a6001f31b130e7a6308a777e753ed0075f22493e9ea3cf187d8c111f5441a60c	1645357891000000	1645962691000000	1709034691000000	1803642691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	318
\\xf0a25a69a820c7d4c8644ac594228bddc36b59ff11d33e0774094148de4cd8020d40b11720adf5eca879bc5c3be77e9459c612471a501f2c928f81f961fd532d	\\x00800003e741e1bcac758d14766fea846726b3f47c8f6abd484a990afe3867116d8829a5fedd1c015c4a610f265de0e5361c70afe330fe1d1387d03e3f86c06833a442e5b48d6a4a5c7e0aa2dd71c2caca35e8e34889e9ab7d03db518e462bd47bb11d1e2bbf96eb57cf20e920182d3e8f8f7e20678f5bb817ccfc4671cfd81551db960f010001	\\xd97ccb6a7a8eed9287a6545ddacd746b98c30b11c71f7eb223cd8597d254972ccc6f488ade9d68dc84f5641c900b8879d81b4e6b15fadae9247ae264bb058400	1655029891000000	1655634691000000	1718706691000000	1813314691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	319
\\xf00a59c949e0d543a6b6bb4c518ef7886e96097a34bf271f6f1544878f4cb6e7f13eadcc1c807a1d30d63a43789c6ef8062f3c7cbc36c2afc6ccd1d0ab784473	\\x00800003bd1de3cb5f88feee7926b00b3b99cf7a34d31e505d4f2132719dd242db3c8d7ddfcae5cbb4590341bf3e970973cc9bcb00aacbb55fcbad5eb2b94cfa80709716c6cf44b0287f34376331c86be85039681560b261eb5c9470f62c576f0feccb7e0209c25cce03447e60d441ca51fec3e91a0c52d7537fb14f7d69115329d0aa35010001	\\xc4683163b69b5815a2b496b22bece81a2ed414625103eb538d10980095355b1f30ffafb6087df13ec2c0382d5ec7fd53b0ba87f3d19fbe2eac5531e0c16a390b	1632663391000000	1633268191000000	1696340191000000	1790948191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	320
\\xf2ca664d5ca7c9b655820d9aaeadb246c7ed79ab920604d172f67f059e03ce9cf545c5267ea25bcb0670061f8c56401d5847e7f3bf8ab1f58013125087f30340	\\x00800003abcacf8fcbfac7766376c3be003d2f4771328324bc644aaac54a05e4da5c9de297c32fe6b107d4a8ec78d46640ea8cc8b5d86af14022c9be350c166c1864bd0d469c741ed0038e674c2d143692c3583d0cc92524ae0b7bc3672b36e4d5c7a6522ae9df514a37896fd29f27436bbdd23add24db61ee12938292bf9874adff326f010001	\\x57720905807f9d57db09989d123c255053cb2be61c9c1d965221c2b1572be48fd98051874af5ede1b03c746c4e08c8f9604c0bf0393f609b4568a947ebb02c0f	1645357891000000	1645962691000000	1709034691000000	1803642691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	321
\\xf3d670b7ed62ccec8f42a6bba1af2f7bda17be21f401194cb29292a120c408ad51e9437497f93809d018183af0c062feca18a456cefd2c9c9ed4cbc1a8426c2a	\\x00800003f6a6aff98712154842c9cd397f6c414db2be2e1dfae68b830e9619c9536f8c7ad790de5bcdc3377127b5277fbb7ea412dc569d556a294187c14bf94da87a746a764bdfb8115d711eac5bd5d48061f50841b3f158cdd8a1d74b4a9fa59c87b39a459769a0b3664fe367525e337a01d95261114a254cae452983988782480238f5010001	\\x1fe45c16a95136efd571fd2d4792102aea03850bb1362108b255fe67babc3407c32f3a527dee99a82f7dcd4ea0b2ffda031242ef84ec2bc9b016f6562d77e80f	1638103891000000	1638708691000000	1701780691000000	1796388691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	322
\\xfaaa1e35174e82323017e4f600120012332a18ce14df2ccf498b4f0b5d8cd0309492f10b3ee735f67062181c3321c9d9c81b7eaf0b3689aa0e31bd410de9d7a4	\\x00800003e82018e774f8966a17ccec073fce30fc9ca348ef7f05d43db27b9b7c7273c61ff2847cf018f31b33e819f75d4e05848a134ebcbc1f95caaebe986b33b1036e84ae8baa105ac1cef2254f1b328ad38dad230097a08e9132e2249f05c97072ee1f03ef4c30671b345a683097ba7e1e539f53f506804db470feebaa314c1364c3f1010001	\\x728f8c65c7bdd458cf4b53d4bec94101ea2f1a0a028e54b960dcd4409af42f2b79c48f9bc1524a52164dc6a5e6df5f2de11758c994a7efd9f07455aeac093505	1658656891000000	1659261691000000	1722333691000000	1816941691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	323
\\xfb9ae7efb4801997a96ef9af797d4aa9ff78d7345ac1bdcedfc40777f480a20906ad214762fbe41fe885529a49e1f1899547fd6c1da7b214f491da7f78010c91	\\x00800003f288b1dd62f6e81add80b7cfe9add68a455bd601e01588ebcebe5a1b89de4a7a48e75d4172294cfc3ff1c711dfac2331d215aa4a2050d2e90f2e55a22f44aa50ae6d9868779b34aad1b67469a7751f1b82267901da1a5505c4816b40e1f6f3bbe244ff1ded45688b0d1fd94d168ae784511b77f749972a70505398e72403265f010001	\\x9cf8ad548eea398ddad341062820f3554273c18547ad6c16806135a3bd31688d0f3b3cca8692e3cfc9faebd54934d8a6e3bf9e02e38e2ee063236ae37bc64100	1648380391000000	1648985191000000	1712057191000000	1806665191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	324
\\x0087b31797e8ab5dae5a3207d286f9332b72571e183d5fb4f770ccc5a6fc6ffd1c7e8f0c4f9e3376be9c7a931a4bbb17b809321520ea3aa87cfe8c846313d437	\\x00800003904c566f39b586296328c6939ee7db330bb790a6d09aaa4b8d66dace1af46b9510863367007487f671beb35f06aa44f4f2abede670aca98235afcb18810c00359b5464dfb21997ec367de195ee3b861da59f00017506a320bc9118b1d8d5030f67b1080f9eea4197714c4a0194197644507b7d2213af90e1eb74282d016c10c1010001	\\xa8a5ba78cc5914944b3ca45bbd2f6d5eb51818a17702f223a1180bf33115741ab5c75e83347a141d164a3da28347d99e4daaa23123794e7943a0d6d1161b860a	1661679391000000	1662284191000000	1725356191000000	1819964191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	325
\\x02f741dad220236ba5d578ddc0fe36dd9a81f651b2943e40e0bcdbe75bd4ec43d8b81ed7eb947bb373be476c1cb4ce0645be0a1d3dd7c8526ed0117d765e1486	\\x00800003c96fb7e0ef6cc06c052ccb12a492a74a08fea63f534f94b675f4c04bbee63f5f7f9ee01e6c26a3846da41159e32510353080155adbdae27305cbaaffd218b90ddc5b1797fe613086abe2a033e1d59a468a51afca27539232e7c200e217a3b643f6cfa907fea173bf4103af0bfc303b9182ca9955cd2e414c7d4708bf23897305010001	\\xb515642b19dace8446f5fe6ffc1f4a8f1a7229afbac9e5bcdfe61ed0b1c9c816b4ef0ce947254e0b8b0b37bc15f198ced3a96d5de619af58bc5510075a2b7e02	1661074891000000	1661679691000000	1724751691000000	1819359691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	326
\\x0327e9aff0d7152e42403482af61db9417c508bea4273a942d8d21f6986a1909237680c2c15fb26701e7edc29d4c64bbd8afc0d26f16cd44f5ff7233063fad57	\\x00800003aee8442f34dd297015886b6e39d10922f3c7f740da8d23c1abf814a209e6a7cdd4fde742787dbdfed43b492111097aff121950278b62f187d6b889a854fc29386df2e4bf4715d834570c84ed194d9060024acc9c09fd11140a7e351806b9211966aea266296a650c7e309e73b4751daf397361721bd9d85abd9e065c913f865f010001	\\x40260bedf874afbfd1c237ed92424b4ef2d92f7d52b735d0e5118b532fb7ada5a7ecd1daf81268c92f7533be2adc540fbd97f6ce56766fb59f5828f8fdc80c01	1638708391000000	1639313191000000	1702385191000000	1796993191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	327
\\x030324c3880384d29df37cea4421818142288b8946708d1839ca2c0df9773317596822638bb4307619300afdb1d1a9e632ee5855d3b4d262475800e66d3d8d69	\\x00800003bc4f68f769b9dc7893b40f5da0fea5d318ea2612fd8a57f3730cfa2a261951dd30ba6fefe86593b42becd411954e05059ac2d255f36f1aadd91cfe7c0fd02509438b7f37b13d351c37ad63cf80b7a071a733851f78448cf61e843d6034ac1321152d0b502c08e318f816ae39c5bfcf3e9ee8befc63bb016c863cb7a3bba63ecf010001	\\x99dded651e5cf0cff4a7975bf8368f7b28b80c5f69fbec68171153beec8c2b8b980b7b0ab3f1daa0536f288ad87404c07ec2eb162ac79a5af870ef1ad85dd104	1656238891000000	1656843691000000	1719915691000000	1814523691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	328
\\x04d32c07b142cd77e2a5ca18ddf2bc88cdf3c7bd34c625ba0d671835817e708b6aca92f4e9c979f59ee719b8cfe8d30061f96acc025fee2256bd066b09f6e03c	\\x00800003ed1015760d285690c7cfa61c2d81fdcca49bc2ca1b26435727632e6b05290706bea2e1382f75175c55de86d5da7d73cb39c5970cf05c8284b022700c11979ec742ca14bc40d85a799f4a4e1bc3f0f6a5b951a469be00be2708ea02ef1af0f5fac916fa7da4d4e25fb4012b280fbe631ab6d9798c74e0f1f3f3281bcc87051d1d010001	\\xa6ada1479035cfebdeedd228feb3a193e417056dcf4e61c7764f7dea79fda3fcb59d25e368fecf109b188bca1bbdf5b24b500169536e29215d0705289df6ba08	1659261391000000	1659866191000000	1722938191000000	1817546191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	329
\\x07cbc5164975fd694467166a8de6b62724fc238be6fc83efdc7f66602872b3b45cf532674b03ac6f58d0112c666d6d873946171c2e6c6978975ef0d34fb222f7	\\x00800003d66ca6000d52e04991826e3b2bf0dec176d97b5dc5c98982b979a7715ecbe8d6b85f7782560f76f240ce591c2abb47389788b053409b9fe35d2f0e83fcab11f2d78482b92a079d8a16d87be6ff78f5c0f71e99b0b94d00dfcf500b9251b14266299e4d37cb5dad2a857f00ea12047b211871e586dbe78486079c9695320f199f010001	\\x92a68df2b6df99085263dd49b8c72a42e1d33eb5ce01228c8235ae04eabd845869e9b29585aaf88cdbaaced35b31294b290a31d2c9f204536afb5b26cf7bbd0b	1656238891000000	1656843691000000	1719915691000000	1814523691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	330
\\x0ef336327f2561c7ae2bc0a589ddfe90bfd2b944807918546da58ea0e7de183b1dd1ecd5ae7e023a3fc670bd2a86ed828222f1b6e03395a6576243f214db44cc	\\x00800003b27c0194969056148b5f9b51c3c122d01cea1db5a614ecf3f628c6193e858562cee457431ad1259c9d7a0254ffb75068185a1d8105362d6f84e80906568b3e8dd3d0bb697b8d64fda5b1e005c9d91ae0717045da64b77648a267b21b28785a6516d50ee501073edee9bc133c2b3167e82f62e6b99025324636c4374a45ced91b010001	\\xb113910ab16e31b5464c29766b159d2d3f682c36d4fb2bd7b5b975d427a383c81621f51c9fb2b62c30c00b6555e0078fcbe6ea63edf40c03913d0e18a9f2d003	1644148891000000	1644753691000000	1707825691000000	1802433691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	331
\\x0f93811ae5b11265a228be43c62ee18af95fea297fe365cae847a302445ad4acb7a69bd36c08133066df0feebd4b57cf5eeafa9bc6400db4133e60f9168416ca	\\x00800003f38653ea4c30df4c89c5aac837608a8ef15111431be7c3c4fa79e8c2fbf1b19f6c9586bc90ab280aca0c41d14ff4daadd221ee5f4bb04720406d177b7df9d702cf52315ee9cd92054bd4c31e319639688091afa336b634997468e3b61ee054291bf1eb50230bd368fbf8ad9caa470d07b6afd201d713aece4ab5261ced5022e9010001	\\xfc88026bda68e334cedf0165bcf30db5a7ffaf0b9cc440cfb46390e82da8d5ffdf063528bc517f7bc0a554dad4bee2e365208daa34e439933ded4065a5f16e0c	1647775891000000	1648380691000000	1711452691000000	1806060691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x11d70ec0167434deabaf91c652d7fea81d4fc83800da7a73feb0c157051564f3e4d24cb3614ff9b5dee2f0706f572fc6509783f1329d1870fc7395c596d90880	\\x00800003e77e5557826abc63de79f1db9bb33877ac72ea78fe609e8138e30b0876764d7ff392c9925c1cfc3be5e160e9ecacb648c38a219b2524935b10abe85f8ad265c97787c2d4ec1d94ac809d3421257503408d17d8269430bf75ba511a4ef179fa17e2491eae783dd4bac82a42796bf1edd243753a8fb196bb8e7986d5fc46dcb4e3010001	\\x30813874109e445272a49b128118b00a8a70b9a6db67c1ac1d5c4155687d4fa42c52357d66d6b6ddba89929fb3b678284cf98d06c818a66515f5b60a94e4010b	1647171391000000	1647776191000000	1710848191000000	1805456191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	333
\\x120fa398e4569679a1345975b047134d29dcb901c10613a763e3deefb30fe96a91222a135f17fe0ac36ea77b79a19b5e2364bcd6ee78e8787b508b5bac8294c9	\\x00800003d3da146fc02beb1fd373d649bb3a1be8e443c218ae54fc54f3b914894709bb7e38c45a038ae0bb78575361e63d91ca5214aba3ce17bd5b63ae838cca1ea068411cb3b6966523805249784f0877502dd932cf1a1df6ec186a3b9c3b3a9eddae0d205599330a86e0a60cba80fa10046b601e1171e6bb3e77a9789bd0dc74e23ce3010001	\\x7cf546c61f4a5ff4328fbbcdbac21156ec2adc04d8b7548457919c3f4976ab3f1c1b777ade0fa1a5cd992828b72f56a74570d13fabb8af5f2de94d23db43d802	1640521891000000	1641126691000000	1704198691000000	1798806691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x12b7cbc7315390672ee327adfcfb5eba52dbb3fc9e8143c55a49e61431acaa39724b4906799e33e9840bb167c912ccdd39ec73f01fc505918e5a48d1369f0704	\\x00800003a9f8734955d17dbfd82e039b46e93fca6e22f0c9ea427f308c7e49cd8cdf17a29cf2f13d868a64bce7d591b526f25598b1952ee10d19fce67d018730ca72ef53e4c189afe7c55ac61bdbf4d6ce55f776151ef86cb3afa31bc24755321521db949ac4ab13a5f0220e49fc83e3d06303803e7a59bf5c68d2db95d3f4fc61b25023010001	\\xd46f5da0ad458b7b68429cf93e3f3989fe620a0d9c47e8f8881f72cb73bb8d2bf21b2d39b633941935d4c94e720d253e85f45a1e3f82d46d61278382c0fd440d	1647775891000000	1648380691000000	1711452691000000	1806060691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	335
\\x1337bd40ba4c0cf85a51a32acacce01b6d75e5c9027c027f70cf4fa38db25446eced1cdb291d1e9c24e5f59513f0a6c3030ee8033b8c8e68026289ec5ca1b89d	\\x00800003c94ed8e85c98688d34ba501bb8d66c75a6d6c0dc65390fe22286aa2bcb9bd03d13b75c864a5df064a91f2f745ac50605f6a0e7c153a1a6786a4d2a2410aeeac4455bf38c9f3c5e1f5d4401830d38ac885dd74c43b6b284647adf4237abd9afa31ee31a135c38d14d1efd491a9216a0115f7bd2d0990dc46e6dc22e308049f843010001	\\x84c19b58b28fcf96e6ed66fcae0ca6db3e9f6099e113a9372e3c23dab28ebebbd7b3dd81bc50491b07179c1d494ad557659b816d49f3431d0f220037d3ef1c00	1633267891000000	1633872691000000	1696944691000000	1791552691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	336
\\x1493d1fc9bbe9130b109d7486a1544a7c0355d9870acd2c402ede5aa3c9e45ef8c76dd8f70423f1badbbb21f00f12d2c8144718b7b9b7c879833cd83bc1cbb6d	\\x00800003b4f000599fba4ce426af5e0f6f219e87fbe51079f0a6b742a64a924bdbc925911595d35566c15f40fe1276892d3ccbc111e1b76eff66abc825083d612f6639ef8c889c3b51355f2763ebf14127e255a6e6d7c645f7d9c35d5b67a8be2f97a802cedcec29234c26ab9aec00ba554a89ed9ec6d611623659f93176bd67f6b7c561010001	\\xf49bebe0baff0793835e8229720cb94f5b6570d8744b3c40f543502980586126f19f6db140dcbf79ca7adccff9a0fab09c2dfd1d9d5f33b58fcfdadbeba0d509	1650798391000000	1651403191000000	1714475191000000	1809083191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x1c1b1fa05c32d9980cf15ac4808c8468c83bc346abd72c468945e61fa2a0b7958871754332597e77f80e26e8be6a80ae8cb8bb6dc8f3aa10c9a0db6e2ec4d879	\\x00800003d8895a3efdc5e3d25689aefee446b212663a1417b901471dbeb9cf81928307106837e03681c8b1291fadc748bb32a988140cfed4565de1b2a3d822b821c634490d3656d7cf24966a7e4cfa8472480b8f9acb10463bd530c6dbe7fae9f2dc2baaaf5337d0eecd34778d40108d7d094683a6fbc2fc98af1411ff803450534b0497010001	\\x6c357ff1340dfcf766518f3e2f1881eef5f14aca6bd70f0f44337b108cb5c76c6a9f9925a213bdb8827969c5a1cdd555485e21ba6c8cd8d5196a27e8a475620c	1652007391000000	1652612191000000	1715684191000000	1810292191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	338
\\x1d1b6057fd5c7af511c86c9c33593848d523dcddab24021325b61c3ec1356f84058937a3c0d084b0d8fa4ad17ef5300473819422067ab6ded76dad8df323d56b	\\x0080000398abfc6e1ffa4a22b26cd00ad53568ce460108ea288d514e77cf5d847c476376fcda1241bec32aebf28b3a98f233be908bdb8b325161565e472f950d7db362c65458970e92c93699cf506514f306e5a55356edf367f409e32d2891bbdbe998322d3374247a75433ebf561fe79ebc6ab7881e61e91436eaf1a6ac821a0031dc35010001	\\xa29619dc4d51b34759838456ec995dfd2ac45ba263d726d9152907485d2741da5c1c5c6c28ca8a75cfcd33e4c9cd399c70e8d6a384a902607b15c50e1afd0c02	1645357891000000	1645962691000000	1709034691000000	1803642691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	339
\\x1eefdc92b390109ef816cf2384f3ef88875bfc737615a28b30a7a8727aec209b407c530ebaa709b39427e1efbbd5146fe233b189f05c31e7bd5593711c3dd2c8	\\x00800003c022d471bd1488daee8299b1f8f10814fdfe8f165d61c13c833473a4c44ea1adaa2b5e03f468e22b709bd8d6515f71de6cc9151690ea5e12f6c9fe85dcdff8574729a6d156343898647db8e920082826a6f3e394ee0ef0fa8f734625ed1be0deb19c09ad4eb8491fe071e5f698e43a483a016b46fea89559313b1535dd05a94b010001	\\xe9f6f06826424c069869739bb5d3aac8a6d873155eb62c39f72b4ec7786bb6e446c71190878414049230dfa6eba494419d3f06803bfe9d6b339184b4c369b504	1653820891000000	1654425691000000	1717497691000000	1812105691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	340
\\x21cfb14317aa952febdc7e6b83d9e258a50f528e18f20c9dae712acb4185b991019ba47cb6c80051a430f129d2584ecb1bae985747c58efbb433e2855db6906f	\\x00800003e13cfc805aa8fb673e03077314c92dd29e157de2403fb2331b63ed9fc737bbbb33873193ff9dff947ec808d4abb84e9c6aa0ad1763b0065b1eabd333abcc81ccc28d6b41c7cdfb45f183c9880988750c4a43af2bf8d8e43802eb37dba81a85b98a04f7d1e21292ae7923a7c37f40afc1430a50d4cc56e76b1032b75525cfa8eb010001	\\xaa72a077490bfef71574107ea6a6dae55829d3aab8448641783ff0840fc756e6bfc1f04f6dd245c87a859589f0a7961b8fe27439d1e20972cd591d88b343b30c	1661679391000000	1662284191000000	1725356191000000	1819964191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	341
\\x231bb9dfc8bfdcec6fc317fe7f806ca445f381c621e3693e6896f566f2b0207d52e1ebefd15d326ffc47ee5db4c4047732afe0a78cf2a8a8e19613f2f7d28d8d	\\x00800003ce0ce1186eed07c9d853429f52db1d055284e2edbcd5b005059383779103728ae082b64ec9b73457f970ce6d1fc42c8628ab02df349fe26b89c793449b63750447a3c1c8666ea3f77644b5d8e03360113f79cd52868232413a75aea626fca12d1fb983be8803d75cc9678b8025b5e6f6680505ab308639534d886bf494488ab9010001	\\xaaad661187d57ec05a839d87d3f106c2b595da1eca14f041f246454f66e6a267ec5afb9e8bf8e9905afa7380a066407c1ba080b9c80872165a48ceb84815ee0a	1651402891000000	1652007691000000	1715079691000000	1809687691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	342
\\x256bea433ae4844593ebdc663832909a1c5deb709610d9ebfc17626cc80cf9ad34d8714d22ea96d99d6419e7b1cf27a7d8c718b0fe1f14577ca706a9c54a0c85	\\x00800003bd8f752ab0b98c10a098d90fbdf04695776928604720e97c3c67d656005ecee356fb1d409c6b21ba6d472390fad6a8bb11f53236e5f056fd2525e2e6e55d803347f0b4db110110f45d8a70affd52f3d53ac74b9e08c37583eb4d89074d81e3a24ab2f112e29a6f45efcd131e9487e6b79f0d375e1ec054c6e2bf7416438db201010001	\\x915d647864f91435fed177cd39a39f248cfdeb1773436c3d111fd938be9ff8dd256de93a31ebec0c45a3934815cf6429a952b66e031250585c68598865ef2002	1648984891000000	1649589691000000	1712661691000000	1807269691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	343
\\x27c31268cefd5c92d179400f2bf9d8459beb5de7aa4dcfef74629244f752a1ff65af01e9e10ed94e7b23cc16b6ddc98cf6b433d02f24dc6ea80e037c19d04261	\\x00800003afb659df671059d45e23c5e4989e5a1f35dfd5000d213bfa2613002df0747b167ecbcb6a70c122e2c06f1eb4468b636887cfc26f38f5c3a3c41a796c2e128b144d2a4fc927243b0f13932cf99a7488538e2dfb92ee8d3607458e0ed70d6ad13ae56a62817b4d99a306b872e06cf4ce4db12a747d822020a12eceffccd73557af010001	\\x96a5062b177778bf36f12e36914c46a64f7c8e9974338db78f4db1de40065f12b92597c345d25fa13c1c1897b595773b2c4dee1b29c9a979eef7b69f91f0aa05	1646566891000000	1647171691000000	1710243691000000	1804851691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	344
\\x2a3f6c450123f7708469b49caf94591309cfe7df072a3a366e6168ab9271dfe9efa99192dc65cd35cf1c1ac2f3a646efd2677208442f19c40e69ca80e0765aef	\\x00800003aeca1816315739d73ffa979341cbc9ed8015e733929b77b37f0bfc5602fcea4d6f8844a5255cb17b3a373ae1830f605506d3182054619c7fab52d25af8f19d66971fea0b357e7257018bf85f38bdeedbc3316ef54100b31ef6f82bdf9625b302ad05cd9a842f309e438fe4ed91a47451b9ce3496272cbbf66495b680a955fa1b010001	\\xcb15dd1716a5ac1c2af46fb1d9b4f987952479067bf9e28a608648f8c54cc99fc75717859f137a2838b61da1acdc8e15e2c42c6e9b9c6a8f1e89ca2c6ef6c509	1640521891000000	1641126691000000	1704198691000000	1798806691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	345
\\x2eff4102ad2575d4310d8ebdbb38de441199bfc4a0331052d4646cbd9827b7e2afa88a8ffeb7eb761b4a9699f88766ba0d6660f842f33e05ea78db88b7dde73f	\\x00800003adf8460998ffc99c2b8689fdc0b3b2beaa3c01f4031ece4cafb374b89475acd607996d5542eab07cc47b4c19b06e3c0010d4ecad93d403cd79e8274b4d1e5cf5e24fb426ebd5826081046c26f8a0bba578a957ea7078a71905a8c83af886bbf1d960e08daf1ecb455ee045a0c5d843bff94615936cc21a6c2548b4003c7cfe35010001	\\xf8e0ce71d6773af551d74f0897f6b79a1099a01586e3e36a085c000fdc24a9c49443ca6ea9563591934217fcae9f9760b294c31cfb316ea9f00146960793330b	1641126391000000	1641731191000000	1704803191000000	1799411191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	346
\\x3023c733e9c1e30b8873c597175c9b3bd6ebef8f8b6db9a64ee266bd9f7aae36321b174ae60bafade015492bf8981d5a4690d1102ee0e2f649fb3124e2d901dc	\\x00800003d055920842aa6ba086d3bc011a75336efb91561c108d11e574328c03143d9fb610a2311a414936450eac7b0c683a75baf215a1e240d417786c53bb00e12194fb00b27c052dcd3f794c50e24ab36b38ca932b101072b263bfdb1021457e980585f4afa68ecc120e179a937f0f72d93199ac018ee3fe39c6d88b4cada43bd90157010001	\\xf2721d9f172afd666dfa27bcbf4befa2fb8d12f847e438209135f8ddf26710c052b26cdb24ac62f91b9699f815f8228741f420350c2b0ce27c236dcf2425bf09	1657447891000000	1658052691000000	1721124691000000	1815732691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	347
\\x326ff5407073aee98289a98ac39f1c666c9cbb729abdd911cc542e609464e6ac2ca8bd49eb883c82db3b12e61977a897a5d486bc5d40742ecf310b026dc06c59	\\x00800003bc964350944081d37d97223d9c70b228fede16ba5fb54554b4c0ff3388ad23343cb8cc25b7c994f4703c3b098cafb1dcdb4ef760c2fa5961ea0d9928758af18520f6dd26edd711744dbd361d3522030e9f6862e4031b154430736993dafd0d0cd6294dd2226a9982f37317a1f2a2086dfa065fea54cdf377c837697b0fa3cfb7010001	\\x71ca00e3536db8a387af0f638b02cfcf85e727efdf373eadaadff42aed6b14bea37ca458006bcb76b59fe90b6e3b0db78d5a883920bb5b03d3618e2ce66aa20f	1646566891000000	1647171691000000	1710243691000000	1804851691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	348
\\x34c3541502ae8b34fbaeb53f9a76f14fd4be750c521ea74530cf92a1df90d1cd091edb4f560527ae96a6a83aee7ed00075e127dd8907c64b3ce6c22087878bb5	\\x00800003ee81a1a4b60f70ac2a2a73ffdd909b90999db6cc94fea5f58c893c9b92ae399b32cfe9ef4349388a602ab6c08a52e0d798c3227dbef53a314cc804406568890467b1dcd3c5fff026a8823720ac359e284a4a85671d78ff3f9d3f4f98bd2d187877339fa77390b11bc7c79381e4da154c2e40649f9e5d12b151279c13f1007a09010001	\\x5a9d7faf30b772a0457581594b19245e07ab3cc4974a8e58795dd640283c3e40ec0c0706a36d69db0aa2e8358ebe96020747bec4de6cc2c03b1da867a2fba509	1659261391000000	1659866191000000	1722938191000000	1817546191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	349
\\x35f77b025ef981bbbac71d99f26081d6eadbcb4a5b55922771cbae04cda9d13ae81ad6d1f4bfdde53ab83d2815fb354d69758844c7d6cb854cb1e1fac24146c4	\\x00800003d499944b9773b8f3dd20337e89121c5b470086a5373b5554a0a96d842f3144b244fada5768ee5e6df65a606d5d2a38839c019d281c6be15991155c41a865a3cfdec5d7ee68ed4a7c0867a0393b66a5ee6c715f398d99eeb1f4ddcdb8ce138b6c11dbd8b02f98b0c43af20a26aa9c5d6a785941b6817782cb809362f2aadf94ff010001	\\xa505d84a5514c80745d524753554240bb06a6005be999c904f7c80aad912441d2c5e07e63a51e7f56047790ff591804a0f969f437f483d9e1b2d3ac1ae649f05	1647171391000000	1647776191000000	1710848191000000	1805456191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	350
\\x360fb36609494d03a0e32f82f52114a69595e1c5341ed052bc6eb5e749cb5a8340565ae1bd760b8a9ec46fa74c18be28338299ea688b1a5a8c1cf4255a41c3b7	\\x00800003cc74d30ad32a0875c8104044c6781a9d79fe5cd710b5135fbff9c3f7acf6080f0bf52ed72637a07877bdbfd21ffe9b714f15c095c84bdea1314413779213f701f2162d32b988c74e8a6f9dc3a6034c03a759e0c60651af2a1c94ccbcf00629d59877d706031b153c76c1add69a16f71c7fe2d3006e912bbc588224c20c21bdeb010001	\\x9e37b28420568ed2c65dd3fa3e112468a2b432b038196be404869baeb1924223a455275664f1660e1e4445d8fab11aca2b79fc23a465274e207564f9ba33cf0f	1639917391000000	1640522191000000	1703594191000000	1798202191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	351
\\x375f54abe70aee8ded9019f77b7bdee795840949abb5b1b58dc37e936042dddae1676cf339ee64bd515d1cce199023ee94175ad85de6122df38036370c6bb61f	\\x00800003b60471ff4ef8a4013fcdbeb33da571ae489764a469b12dcafba53523c6adcc9cb94473f8f8d8ca0ca23063e95e1e82650b1a1ddd001a6ae570f9ef4bbd6ff0ffe48dd8013608e14d74d1d812dcb6f22012d84083da1506290de6e09900acc78f0db4be048f4ab78112d66a39beafe527335c2526f7b43ad4d4e1b86b6d015353010001	\\x20b0c1d40ccc3d21b56dc82426d14d445bc1a75842fb2bd3010534b4c7ebad8f52e04f505d09ae345c32a6c1e003e103cc6f31a3caba718c49a8dbd8b410d201	1635685891000000	1636290691000000	1699362691000000	1793970691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	352
\\x39b39300c74816fafb5e6a2173d8f656c5ce95d9724beed3e93eb70b8b25dd0e1220d071d1435231fa92ce095e7f856b48ecbcb7032e3e9260e50266dc1f8e6b	\\x00800003e9ebf42f7fb63d3d6b79a0004b6e3f7796fcfa637bb0372256b3818d9fc3007c389d395af285f60842bd3f1ddeb0e3217d52a5e88b22da8c27abfafbc02cb9011c01d50d350026de73047085239ef2ed22c6ba059de292e672807f2b905659d8cd2102b10c6475a9a9256588ede236382475c465aaa1a39786fea7e21f19553f010001	\\xa076c02db0187d77de8683a3e3d5168a88a75003a3ed1c44ab1e5972ffafc26569b48c48d37966bdb7fa67e7100daa10d95f41eef1226dfa8ccd69113d088f00	1652007391000000	1652612191000000	1715684191000000	1810292191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	353
\\x39a3721858862af4758b3b4dc3e10de6b659c6dcd00f2ab50c271034fbc2e37f1a7683d4015aee522ab2bb8b6410388455cbb4e3a481862e1a9431089fb8764e	\\x00800003ce2f39f5177f2d46c40082a0af93cccbf85e773328cf89afa874e13c1ad1f0db34079537198102252748ddea7608bbe162e72f75f6e2b2210cf2f16bf13be18acffa8cbabf089fcaf0ad7d86ebbda4390c96558bcc1373ed95310f7a17fa7138d3a16af3624c55fd3c9c68e678a3ee086017bc7b794c9007c815000e352f8471010001	\\xbcffa0c8df063857755b60bb02bfdbe7344bcffffa8f0ba7087818cf265e3182922aa0ac0af2cb5b69d3ca14942e2efca2e903c9e56bf7cca95c5f777c431f0b	1645962391000000	1646567191000000	1709639191000000	1804247191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	354
\\x3b8b11d834701f5f7dcafbd80198a61eee699e778a2578676cc2d69d1f9ed2137902eca3847fb8b2ef3f66c48ce21f40f1cf1160e21f40f9a22ee637223bdc21	\\x00800003c5628dbb0a6d2b4b021579cc939bee96105a4258e279d6cb99a77119006381df3c016ec989c7033498354617e5d66b0da48c8eb9d6d2dd55af6256352d65c57a08599a0bd2f8812d01206663e6458e0f5128223b4bd1d2a4de467f68a95aecd31d89e8b17908f6b6e2163ded3ff88b1f3cb05fb79fc0600e032e9a0b2be24255010001	\\x5225d7f457e6653aa34e8427916a21141e47f33da2ac7d6704c463586ab1a53baa205f68c69af1d85eb5bb00b5940b557926fd039e415a028f78af8531124509	1638708391000000	1639313191000000	1702385191000000	1796993191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x429762a533121833d0785f84d14f9f6bcc470b56f904d601fec61a904f67553ce4c8e29febfe43f820c73d75999945fc11da09b4a92cb33d1a5707195c9f9814	\\x00800003cd5835494f0763858810c17d710b15807203e1f5b0a0be19b528b17440d7b245b0ac0127c6741bc8195703b39f3492a16eeefcaa685eb8940161f10e9b1c887c03771d0c382dad1814f4615aed7682fee24565108f359444290c53b035c902416915d3ff9ceeeb4d778cb6ae6fc3de56fc96bc9415d599005ecdda620042c1d1010001	\\x7f26f3c8dce74812cf3910ecd4d63f93be3d5e307a908b2aa3b930d45cd129466a867768f85a15869997cbd213d1d646a8006f821b9e5bd860259f81d249cd0e	1644148891000000	1644753691000000	1707825691000000	1802433691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	356
\\x4273e507dc9f19af7d1a98337513743d24da76104e6e6504a60de1f77b9914cf13a05bfec0197982efc1771995450b47b214532c1566165aad55c7a82a4f7f02	\\x00800003bb1ea99a3c4b7c535b766047348fd8287ebb7f5081360a9bbe05c3f9e174c2786c1c54f49cd1e2cf1cdb84af9a7c583b9a35636cfafed5d93e6badd2875d1ad221fac86029950f210a7cd0ad817f355d9f6fc99938d33e8120942068bd4135144b6664bac4d7b8296cefc3295584effbbfffba965e58cebc91ca08eeb00b2761010001	\\x21d9b395e8e8126ac9cd2d715e7b4c47e915107537c7b9d062556d402592571eed44fae48ad70c8edf817e85294392e9b79775b823a27a993dd86a3a92ead70e	1661074891000000	1661679691000000	1724751691000000	1819359691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	357
\\x45a73e3ecc9ae1937cc136c2fa6c10baab6bd23d1f5ccdedcfb250fdcc6289635b33cb4f37fba8a7e010381e433cb1e19aea88a3e6adc761e0c7192648cd1bf1	\\x00800003c204d22b9cf6aff900a006095e2eecef11eb28f527c9ac0b8752a1acfc2aba79d0b946a6765ba4e0f2d532f17ee6d39eb04f907bc52e364140f75f1590a64b95e896be955714221a9bc36b794f803ea4b87340ae4a46024699eb4985fda4fb08e467158828130e748a2b7181f638e08b166677dc70da12c98162cbfa623f8ba5010001	\\xef98216782cd51906634076ba5a16ef5b7bcbcaf9aa5eb7d680c233517c7b4332476c520cf79857e2ddda984c250dae29ae2afd04380e560fc8c36c22dea4e03	1638708391000000	1639313191000000	1702385191000000	1796993191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	358
\\x47039658b3011b61c08f8384145609faf6ca25976cb177e9ee4a16a168257ea5909ffeb6ab2232285c9462d2fae6be2c6a9ac4052aa961f096f82e7988a2ab56	\\x00800003a200b1ac68d721dc414d11c920c6009d6a6d91ea253beb25bfc4a2dee283041a59c94d1f9a64bb5df636a3edf2945f25c54c2375aa79f13803555404c147d3398826dec75944de253eef1727bea99341867f04fea6efbc4818914b7c15ac5364bf9a98b5ce6fcee805c30095eb13a7069cf5ec75e832fc587f1cb135e74fc4df010001	\\xcf7a1500ec98a087473c82a338fee3bcecc186b7fd030c31f752e105f3c60d9f7e7973926ba840aecd87a578859a830626cb01cc2cafa0265396c7f7a1cc2500	1652611891000000	1653216691000000	1716288691000000	1810896691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	359
\\x491bb1ce9c0f706cfd4379ab5d95d9d5b665f35f785541ae76c785a3a93545ad0719518f08efab0f2178f5ded1a2c25b03a657937488a2808d3d593323742719	\\x00800003d08e9f8b72bc6165b1d8208b2912761c0ba3c61cfc4af2c314d0841d08274b7e6eb663423a5d88e7b989d0e4cd57ef9e244e4acb180775fab2b3a652abb7a4ca9ef243c111af2afa5d2de4bcaa0f99b3c314399b89da1fa5b4b42b6d5f8cdb6c8a04afc6550e7ba0f0a92206c53876112026a82eb7db45c826f63691f4755879010001	\\x455f0c2610ce59209bfde5f57d5bf1288a4c46ace2ac29cbc1bbb846c56094ad5eec9403456895f9f2c868e59663ffdda2e79830f3feb44a9ebe1920d4c8370f	1649589391000000	1650194191000000	1713266191000000	1807874191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	360
\\x4fa758e90b8d849f36953b02ed83f4581ae02f4cf6ffc8d265c1125c99da5db3d77f0016394bbe416a6d350886c5ec315cdc714ec56c284a9e787cdf22f25672	\\x00800003a6e5f8433b45cbc2e55823889d447aeaaebd4ed1ed0a708a3d1242ba864140367c87d14a4df12e1c1ce91d80e7a30f511bdf8be481befb755b6a0aa0ca7b442b641db16dc7a0bffd552df3b68e0c77f8b85974aff202307af67009e3d13d12ee05a9c4737dd72cd564e17349e6a14e478f6a084bc6d432a6374c0c67df054e93010001	\\xff82b8525f655940aac95ec9519056f9d6f4ba74b3ed74513db9f15dd068fb8fa51c0cdae5504095c8358fd3e8e13b0bf6685fb5da430a649f922e55972ed10c	1659865891000000	1660470691000000	1723542691000000	1818150691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	361
\\x4f47fcfd4440c35f6c49a9b2031091a964909b15320281cb87ebd737e72c28db3e688b1e99ea7063875163eac8a770f000419aa72fecf27dfd3615db9314c6bf	\\x008000039952b1e79bae3bf320c442bc46d9e89624d32f66ccd6eecf0f1e833c0ed1c11f8a17d74144df7bfcff486900cbe7034bb46378381bfc84bb05d24d290ddb3d33a7f6de8432681ce0d1b4c426e04306435996a72c6844f6be0a240add734da7806dd12e41bb078ec0567470f30d85aabb3b1af16ed8fc7c68b2fec6db0f601fcf010001	\\xf4dfb385d3b59afd7369e6e846a6cbb818471c76b4b427d14a0e8f2de744c803ddee65514c0025092239d1e6b241d2bf1126efaae65df5d3ab92ffbbdb946703	1649589391000000	1650194191000000	1713266191000000	1807874191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	362
\\x5b173baeb031fe87a96f06dc7f9f97b62b300f55b3da259b7704afef6e89f333531f5e0530c4364dbca75d60135d883dbdebb5fbb5ed38375179b13723292c09	\\x00800003a5ee42e59baca463c3961ea4ac50fc695e4d31bb7f3f204cd1459b66a97230846280cce10682b3b46faebfc2aefe08bb356dfbda44a79c837271a5073498edfb454cc496807482e30b5d1302b1548d39e159cefb8c71cb84addb8744a31161f8d4dcccb437756e486042babff9c3284b8133bdafa5819871b47507c62bd1886f010001	\\x0a8447bc158e505cadc7122dc744b6a2ae43cafd488ff5649e5a8eb7677b4a70727e21923051df104cc5b08a45c1812ff6d32614e293bb05ff6bf75e4b53c60b	1641730891000000	1642335691000000	1705407691000000	1800015691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x5b47119536aabb01d115190f922c3f7fcfa5689d1d51476d5b435b65cf0c452546865b97a319cec21948f3f9514465e4ae3e494efeede560195ff73325890d0a	\\x00800003cc722967386739844e5353b42fc7e7f96b9185f525e1831177e17bc15f1b48fb06f818c29fe64e671207aa58e43e09ec4d3af34fb87c7e7423752b7bb72b4da542293fb69cd735fe5dbcca4c074c7607a26e9ac05e85622decb8cb9cad7bdecf41763ced5c1d9953f8ea81c895d50f3d1c8af494655f812315a1ba271139e395010001	\\xba5d52b5f44f14ff2ad60fe0f14f28fe7a89391af38988ff1c2ec1238e788391d68100855cbccd693017676f489ebcd3474fd91700c323e610d3666e10f15909	1650193891000000	1650798691000000	1713870691000000	1808478691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	364
\\x5e6f763117af50e82147b217381a2d71c0613dfd86ba740155c601174407ba1e9d7912ea8d4026181c370649d17f227c3cd32ddffb955d2ae049709a0e5e6606	\\x00800003d2d57f383136b30d34d2d8b4f8f9a59f50619576a2dd9376ad7c1e16bea3aea1a4ab7dd7187b5be35ae805c19aed2582bc8799a5cfaa6e83c0d9d766335f4b284e9b2816eaec4dc3540765db418afd64a787a31bbb92cd84a6d4a2bd53aac685beb65210297a65c2cff03629cc693fe1ebed2c1ca4e6e11c13d908791b41d305010001	\\xf8703cf2a03e7180b4917ea7f61cb4adf69016dd562e6d1f378e7e003c738ba4788b4242bca320f0ab17b8b26c7e9fcc8cbb1c167a97ea5aa2cc96164731ad08	1643544391000000	1644149191000000	1707221191000000	1801829191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	365
\\x5fbbda1149bf849e496d285d94065f1f404678114e172f34567395c640e6ebe23240711f4e323537cd058c8e7519b75696848b631b3a703621d4dd8888a40e43	\\x00800003c8e83ee606d032c47de6636a53c9e06fe1164160c86890bcced6ab7c4c1186c4f06ab8dfecdd8bac363c535c1fa5c158a3c3c140295ef394dfd0a8663006ead9fb948dec026435f5488d18c675bc1f8ba931e02e8e8f78b7752ba34ee5d9049d7202fc143b102888e9a36f2985f90fdc90e86e2024bd480db1dac15de6d3e875010001	\\x5a0fdd827cdbd19c93fd7074dd167ac55243f809814cef26defdd0ebeb0d4b1f629f149e007bfa0de12483ae6470261884c1da03a4973ab7a02796f41e233003	1642939891000000	1643544691000000	1706616691000000	1801224691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	366
\\x6247b1a2baa286a0bb9e2aa162c83849cd501c47e0dedce819ef5430d78596584467a2077cdaf70714b49047ff4de69d76be4c669cd13f2d203cbec3a0038487	\\x00800003c81660cfc534d3017970446509beab0bfa803cc8639c37eacc2f5b75a57c6f4a210d82f214f1700fbdbfdb47a352e011f97f279673b13bc2144f1f2b26c0d37c00e6932aee96c7484a883b3292db7fa256bd0f8e8b81582e4062c3888a97bf9efdee317c0726bb32c8307dae727f846cf31da506ccf09d447b17aed5f9e5bc47010001	\\x80ee1f205de50dc0b0ce547d9f5fb55e7c2db771110553b6d8b608706a5ba6cf5c3b6945888b4ca4bcd3c20d3b95d62ab061c120500dc9b187fee6a739650804	1653820891000000	1654425691000000	1717497691000000	1812105691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	367
\\x687fef11b23303d11f0b3f0d6d07adbc264fb4fd544ff8b99b19259f42d8e27f6b7b273696c22aaccd8e8c855da600d0cef0ee343b57fe6ca952b5d06c0f7ed7	\\x00800003d580d55600cab395cfcb7293753505d4ef7857aef64671cdec4af7a19f142417541f102ab7332adbe3e901c5f18f3988916c71b529dde71a9284e55b9ab6e8a80f850c8cefbc29dda7ab02418f1fba42d3c5abd63fb3763eb74e39436a60e91b7cc70036097a2c9de97aa6bbe1ef943a526d21c2cfdafab7252cacde7502d919010001	\\xaaa319fbec27993ee1fa0af95338254fcda0885e5cd41f8d783dfd30b49d0ed7b8110fe75e8c46ce5532fe5f4b19e9ed797c85beee9cf049fdf8272f7c233800	1656238891000000	1656843691000000	1719915691000000	1814523691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	368
\\x6b137a4f8a3230015eed8073402bc29c0240d2ceb2e457cdcc55f563cfb8ca6ea411625bd87d60ed2e3f1290fe30f5777271cb577e283e124859d47335da26a4	\\x00800003a33f74834f85d1168c835d267f1612ca4a2cd5b82d2f250368e9c284e9fdbf328ba817cf1ae183d36a30f2a412e096baed080a190bd4bb09b0f9fc635abe9be86cdeba66c2ab635e6e773c6d85c666420a17bf341019b746f99f1fe36b086c482c15ef1c4fd7606d9a36d413dcf06fab93484da3897863e785becc4e1478e16f010001	\\xafc38bdd8868303a59168b93b456ae7ce9aa399186f287e3ddf651acdc29ea0ecbc0e36c2469fff90f7affeff220e04f25608045e723a44855befd6a8dc2b00d	1636894891000000	1637499691000000	1700571691000000	1795179691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	369
\\x73eb0c24a5a9cef20f51f705583efccb10e43e44ff34ffeb5db072bf7d84a03f9d356fa56e001f9a1ecb912e228e7624b823b94d090a35496c5b30df5a6f2de2	\\x00800003eaa7b03fe22cbf1687e760657564ff8f7fc01c49e714bedb312c725b43dd5d9f685a1d6494b5be75841c70f13dbe4077246a0179b17f7d5bb21d4a04259e7a2112a19210698aa9027e65f713542b04685fe850eade9bea613bb9c9100839611dc4cfe2fba23cfb275fc131d02174341e58a9cf3da34c1fe736dd6b590c1beee5010001	\\xab4d2eb481776d4b0b589495014d6d591e6290d207ab609fb7578eb3900e83605ea4c07e65f2f86e89190bd3616188ec5c800ee77517d1bc3eaa5dbe15785402	1655634391000000	1656239191000000	1719311191000000	1813919191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	370
\\x7b573050e4ad31e4d8b259feabe8188b873f20b4649b456ceeb800b97e9b50a95db15703e16b5ff16f28e45d6736e674247578f9b2fd1fc479c52563f314624e	\\x00800003eb113cdf3d3b204e71cb122ae60a146f3c80142cf3c5772fa82d03c5d211e506d3d6f56c9a5dda506ee39ea8babbaeb7400ffa41a52b08761367fadccd2a9f8877a1668298918db0314fdfb67995e8cb7115838f78de0f4c0059790009a8c8cd431f79d21f9304546e1b665408e5cd444f52cfd5975ed3b8705e54f7fb2f630f010001	\\xdc29948d7709c822141896ef6ddc6e61ca6e190d1558e8c83dab5ad5148866f362711ff10ccc84d03285e5cb089ea52c8798587dc5475bb1cbb90ac9a8e31704	1635081391000000	1635686191000000	1698758191000000	1793366191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	371
\\x7c13806d5dec96b11d89ec2e9d6e95063e8aecc0852f670ebcb2a7625f1f8639098a547fcb52630c18d249448cce0bee3bb739c49d6833b9588861f05313e300	\\x00800003c531b26eaabd9b95fff163f85769f3ae2391f453875055ad9fd8bb08edc4484eec38fe636e62f722e8e624ac608afeb2bf87138de108d7d1a9f777b760b6524024c16c5f8d74895b3830d6a8f2087743fe9a92f7a1dff7c3a6fe655cce74815fcd4ca4472b63889286a346a23d6a0c8749b054f68ff66f8446602b7e59ac49b1010001	\\xcc4464bf6c6e3b054d4e04c66067f688f7e72aa0d5a99734983652bb0a0717ed33e21508f5002f60ed2278e498db565e6df19fca9ddd549d403101cc944fb409	1657447891000000	1658052691000000	1721124691000000	1815732691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	372
\\x80b7faa619ada7c7c49097c575273a7e1db6338d55c97720dd96a990cf453e4d23777159c9cd652908eccf28e955c8b4d34527c9bf879dd4c712bc3a964a2399	\\x00800003c01bc2e8281818c9c641c665f9b2fbc08351314b68d998bbd45da35337de0cb99d54e4283402c616f52884af4e5620506dd9444e851547e38d1320361b62eb616c870b58b191cc73a9424c693883c44ff227d61ac71303613b82c38b70e09a086cd013916c876e1210b19adb912555e4f51e197bba43efb609d29b0ffa1cb0fd010001	\\x609f163f48598cc632ad9f2df39d3162feca0e6ef28e97bd5ca6cfcbf0826847b5378fd6af367f71f0e1607aacec4d847e07da1cce44f0421707a9a746a6930f	1656238891000000	1656843691000000	1719915691000000	1814523691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	373
\\x82cfba0ea0f7116622b1fc4fdcf71beff973dd4fb4f227b4d5f5fbf91d29764ee4619597f96f0be2dbe8a2c630a991d0aa59825d0bde73256f87995051acff60	\\x00800003d145953696e5356df56f6a8ca66d36f5f837a0d2e1a4676c9f9d7c4ba7a4312e097d792830817046118c20ca726464239e813d59f9203d64b67d27ee120a6b050f5d7387e90939953adae6be832b4d248d93465f81a9daf21c04b5f7118a349e2aacc1a500314e90295578149d7142cab9c6cc1e1396cc5e607b9b484e43f565010001	\\x6d884604e6c0e035cb2a27dd62063824798fb30022e7c42aa9edf565aa1efb05385bf303fb39840fb447a06ef96f6e6c51463440346eb82185fda594843e4902	1642335391000000	1642940191000000	1706012191000000	1800620191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	374
\\x84c79b7e452098f0002f4fde861e66730ddc524976023d447ec6a725196b24336f81fd7dbd6c4ecac2b05108d86df096aa8545f27e11f22357ded646b8fd76ff	\\x00800003a21a373388466eb601a8021773c3f60ffb0efd322e60f2a484eff4f8795b6f4527ebed0710436adecce353280e7c9488cc7797a57603eac7e7ed070aeb207be41e23d5616169f2a4e63286f26ab47f4bfdb79e2b70386dac84aa9fd4b4cfdb913105f72ddd9e703b8f52d97de76e939475d9275e51df7f2d82287dd989030485010001	\\x41262237a0d17805d76952b7c461cb42a6466e645a4a4cf9454244e37cb7dc3d90e4a3ae9f32b904e578728743e0e083694752e84584f8bb4c8d9c7eb40b2001	1644753391000000	1645358191000000	1708430191000000	1803038191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	375
\\x86cba0bb419f73db3e6b490a3e81a1faff47f0df8f53537e412bbedd32c97fe85f4c2134910011516790827ebcefaf060bd225bf1124db291e84281eb2f0d586	\\x00800003dff894046495062072449bf90e3a22559f1850eb4f9b97da2169ccca4090db9240272f767a4273ab16bb744afb6ea6d12f17f8f31f74c68399083b52a91cbdb236a1c8590a0630b5b4030df0d6e5a4ea3cd56c93dc49b7446d4f4958faa3a1aee03aeaae35f473d29f8b5a3a2a2e1f8a8eb79ce507577c71dabf3fdf14537317010001	\\xa638ceb3c553f7bdeb07e85fbabb8c8527e2827cdb4e8179ffd8254971e850ed4bd8fdbb8a8997201e99cbd895e78d77543499aec254d7d46c2404f9fe04e60a	1652007391000000	1652612191000000	1715684191000000	1810292191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	376
\\x8643aacfa743966e00ff7d1a6da68e95b34a4a918b64c8f4dabd4f228bf15ba1b32a56466ea6ae73a16be448fdac5b888b7d56a714aa33252f1b20c0b878e5cf	\\x00800003a2f1933b9252b36e77058425013678d1d033b688014a61c4d0bbcb5623837e293d35312f4e5595bfaab60dfdc818b47b9ebab47eab1a8804be50eb74fc973a9ae71445fa636b8e2ddeca1d3217868d563f02e3dd084953eb1222967eca8da7cd4c60aaa3e8148be6d59a0a568194678456ba01f0214b33e676f145e31f5d134b010001	\\xd2c55d750bb09c166aac5f5368cd7b5807ec33c5dac427215078972baed8c97c122e899400fe7d8c93ac1654d307aac05dbac027c63bfc8f0d78e5048dee260d	1642335391000000	1642940191000000	1706012191000000	1800620191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	377
\\x87877b4aa36b2de28015eee1f05a2f605cb8712722230beb464c223422dc0049a78c271dfb6a4a3b6f5107a53bdafe10cdf6567ff3d3876309d33336b35e88fb	\\x00800003971abd92e58350117036e7feade6719884e3867f135829c06c75190a1557df7ac211bb4766696db388f13b65a49358ba0b3a44aa182d44f04aa1dae84896bf7b8b2a5e80dedbbc2781b2b22ac9568e0ba526545ba3210024eb1d85f4567faab2f584351a5f57770e717a758f73e45b271ee055d8ea3e4f12138222ff2d925b81010001	\\xd42d6f3c22378a06e1f88636201096baa8d52d02c207af03665ee2a51d93c5be463c43043aa092d4838aa8a2c4b0d8ced3fae114387d1895479fadb955404b06	1633872391000000	1634477191000000	1697549191000000	1792157191000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	378
\\x88fb491c1ed5927bf15928b2ed7972e0aea0b03330b7521f548cac4319eb3a9bc96ba638b42de3e53b520214f2207ae15a38ef85585a52b664d13283d9853efd	\\x00800003c537db2835a720a29372ee8530165b8c9923a21e3ea4c6b5524c6924b5ff187209a7404a1cbffbeccc479cd1397739674a7f01e168418086c4ab069c5b62c726d72a2c43fee3c10e54061345bf10c52aa836ca49ad80caab4b365134a2a4b0803ce05e01afc90826a28c051dc9be871b03eec87a747be151e2216d74450e2e17010001	\\x51a44c2ae0aefba089ef813842406f4e19cae5480fa094e94396f6b3c664e2054fec1a0f0a4fa1fa99541e21491b50f5328f4e9a822fb317ebeb4b936068f401	1658052391000000	1658657191000000	1721729191000000	1816337191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	379
\\x8b9f92ef1c29e8a8f76a840fd0c32cee1a95d8f2aeb957d9e86dbf254890808192d042f28e7d6069a286daa9a141ef51d0cfeccafb192744b4b9083fc1cd0345	\\x00800003a70538aaf6fce91a12b85eb1e1fa8ea8b075926459982f02db06de5a5e470ccbf84d72f33903f146060dc97b3bea5268c7b563476b6d1e7d3bb7eb2fc82dc7a6d0653985cc986e42526b60ca6fe39ae6182c6e4dbf735c5ae7c802891beed1149d61fd9df3b15561a67a6c7efaee4a39061a03ec72c8bcd984069cd88b8cb729010001	\\x665557927c89e379f21faf8c48dedf9b633a74c3d974eb362e4349825f7297a78bdf52d7b0ebde778a15938cc8ec265e9807394b26e1cbb94570c8c11a12320c	1656238891000000	1656843691000000	1719915691000000	1814523691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	380
\\x902321634a70fe9010b389db296cfc266843447b1954b30cd4dd8f8accc429297ee28daf12d0f0623b3f21208aa4e48753ee60163694a5561d306655adbed596	\\x00800003aff4f1ad329ffcdd0822a8b0fc00a787c704197bc7018e45efc2bc909ba8301f8daab22b9a28f8c3433a646e0e4eaff8cbf23d0788e1d11f99f3fec348f7508e8c849bbedac8d4eb208788a9d29131eec7183729ca80542b0be121989e72b244ebfd041f73ef86524ae94bacbb4287de3c4c53ddfd8c5b966726b895f75ac1ef010001	\\xf43db4d43bb8b050a25a0a2706afe6e2ad7cc43543ffdb23f9d03ae81518a858426b5e2c40efd4913fe0b8633e4d344a8c2529a33c5b34c2fa92ede105c3360c	1649589391000000	1650194191000000	1713266191000000	1807874191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	381
\\x99ffce0f332a80224f1aa0d503cfdf7044c50c738ee8e5dd207337eb807a93448fa7a5c400cd7bf5a93c7e60b41345f0cdfe97017bbdb91c8a75265c3782bbdf	\\x00800003b1f364a605406fd7e934b8ecda898aa87b764ec04c4a67d59ed01c48462cccb99b29806dba8b26cf0d4ebc00b5a4a9e4ab92887b9214c08c46abd5fceec4517467c88c8230fd37047c44b9a535a54478e522de234ca5220dbb27c86b536f37382502359063d03861a035c840f8ec8cfa514c51f5ef80e605a2ee78256c1db039010001	\\xd7529a8aec69d71561478af46f7affdd9da1f6e3d18a8a6251263799ee22e5541f35314ff6b20ef8c97ca2cd5c043cbb94559ad4673539cd89351b39bfb9d705	1658052391000000	1658657191000000	1721729191000000	1816337191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	382
\\x9fd7e5b6b6d325283c98a8e5ecb07fdda3245e92d8466032a35f4d1d3662e12ec958c6eb676e4583b28815494055476e4b368ccdff4639fc7854f48230647de1	\\x00800003da66d42e297b327c0ffca83abe1513b3191e4a0bc3af7c17e6b8d70d2c28f8feb154f8a5a052821107eb62cd5ab6bd90e65d28f819034d302c3c79d49a32237267f3563efae176da3ea7a72dad69c14e7569107886dfd5ae2f9fb49e30b2a5dd632e02256e760af5b2f4009885859140df33aa6acb1121316b4abd7b2a9520af010001	\\xa1907d48cc13701537212150e160489b86f102127e5293f1149759eaa5c87a63fd087f183433e841a934fddf20e7fdf532ed0d1ce1142712af911881fc5bbe09	1631454391000000	1632059191000000	1695131191000000	1789739191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	383
\\xa10b7d99acc56851e1e2737259607a11163de38636cd18584fb8273883df0ba44639b13e20aecc2f0902b44fd7bb21c57149fcd588e9622ccf31c722e7391023	\\x00800003b60981281ba01b42ad63013287012c8b215a873a3de150aa6085a90df2c6384c47216889e67746a2b59735ffbe9f1639cce306b5b54e9fcd67e26584a676df7475edac40354f28981b4222725a41d7cf3982711b4a8fb1133d2aaf4b2d2526625209ab3a3ba07c9f871131531d6ffcf5fc42b6e80f7930faf7ca038fa871201d010001	\\x965ace0a0a7e6df2735679868967711ad863a5401391a3a2366d73c84e2dd4d975d2a67cb8efd99fe9eaa64cec4a80714ff369fcf770c0dde82b4b24bb8aee02	1642335391000000	1642940191000000	1706012191000000	1800620191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	384
\\xa4174074d76495710d8f0707f8b4f00d8decfd78b8cd0999e7a15d102ab833c84b5a29da55c46f6411c5280ef1b93feb96691a528aa537948c4b316fac648c84	\\x00800003d6b17d30ec1610e4d597534471e384775324f5c42e5b1c7665c66f29b4cbd1f2bbf012653c1dd7330eb8b79c6bfe3d88f9dc65dd3821fc9959c312b76cc415c715e1558bd4ca66ee77cec5cfec86768fc3bad68b382d87516cda6d5a84568807ff3e1ac62345b30daa72498e4bfda205170cade33b3d0e49bdfbc1502f682d69010001	\\x85b9fe3c2481f8982658c9c9c4d675b6fa083adc201f7863604ebb72aa1ed30fe0763eb3d6280b52f1e8f8a1f0b196121d842f901786635d3108cd1e8e1fd50e	1644148891000000	1644753691000000	1707825691000000	1802433691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	385
\\xa60775fbeae94cc892afe0f9167c842b89910bd231519be549badfc6e3b1062fb78a4ae5d8ada996dc1860dd8b2b27531f4b273b04a93ded0a6396418956ebc9	\\x00800003f6b2d1b152994f00374bdbee4fbc0dede0c9e37b1cdb5eff27416543fceb0e625ffb32055235481e6fee444c6f285d9b449606ee8a3c9d6db6de54e28316c27757050c9d64c584c7053d0343ef5398490a1f5a9bef6e3adcc6cb1d14a71de496632a4060473b0141d07153eb240b97ae113eb1af7f7cd6f0839bbbba5b316199010001	\\x5090fe3f4f19900da1dc44b1ece98eb6b2f1a10e20d29184caab327582ea438d258ed6652224c9673c7b4f5b59236183b4eb8f32cbe4b95d500e8429c040d60e	1644148891000000	1644753691000000	1707825691000000	1802433691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	386
\\xa653d44576b26c155e29f129d5c1bf82647e420a1057643a05c13f683fbceffd41b45cc4e398c99011b40c6e3ad6ae00e6c83299448fc2fa60854377dc18a2c4	\\x00800003a606feae70b96bf11fd3523bb926568af6c6631ed66743cea7759652b0579c631877e9c994e2e5a8417c2accbc3ed20ebf9c9398e5a9907344fe1698f1d4da25f67d1d1f3c15b86b59f54ee8bd434c80b04a9899d55c520a627913762154b8fdbb3dd3827d9acc158b8cb1b874ab387b0732cfb130cba63a7ff845e24a38a2cd010001	\\x717e1e5c5bb2b37c837b46c90bbf9ae520faf1be7745c7eba3d48a3c0b95acaa93a03a832e1c1df361629179e5a7ad7f25713a42766a985f0f0e0e6731b02c08	1636290391000000	1636895191000000	1699967191000000	1794575191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	387
\\xa83fb0f013de6a59581ab3d6d71ddaaae79b21de5ae1c80780ddfbd1daad43992444b6b929b4e90357fadb291359746cf5e2992c82308375a91aebbdbdaab678	\\x00800003a90f4cd3b72a04086b25f4fd258262bbe53ced738504b36fba9e8a110c47c197fcc3e09488f199e47132d2cf1c9dd63bed30be2fe69aae57b1e56691915dd0d6afe7165d968b9ae0f809d3439fb81e2f7bd0e11d858e00e3477f043a2fd14d021ae9e26335477ddc9584b5ff39789b1e3927e0c4ba0a09193cef1cf2d7963de7010001	\\xc5fc48b089fee4fad13a4f9acc33085e12473fe2dec74ab2a94afcbd4760fe2d9d46294e61fd5e25a72336ee5aeff98cee645f341d4a7c21e99fd256c9316c07	1641730891000000	1642335691000000	1705407691000000	1800015691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	388
\\xac7b31dcbfe441f21824f2485eb150761ba3c56b4369fafd2456529a8af2b01dc95d05075241e5be8a3b313fea5d41e93e2f83f13b3537c102ca1bf811406da3	\\x00800003bd60214454a115fba21a22cbeda0d12a44e28c0ef4c60653ed5770720bde30dbc7d93f2d6e1897a63755f97f5df188a3e7f02c7cebdec012b94c53d4e0815e26a83128e999fb2e12d746d563df4f3a913adb0dd08578b72def7a7bb6413831308f896e865f35d477aa4307a3c57628fa9359a5f06ea82a1e49bb6260f96da3bf010001	\\x75b40c5a994ac8999226e70421fc51fe2b03e23c5459f751cd6afccafee94327216b8306624a5819994843478b3016d78bab2f947015c9cd8b2e1bb81d866e09	1640521891000000	1641126691000000	1704198691000000	1798806691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	389
\\xaeefc57070061c14d2869e7f64035d2d6c8259f14f6f14c24e93df900e3375b228db35e6b1921d638f391e949d5fdcdd6d2df803466cfb921b620fc201b7c565	\\x00800003b1edb3d5091199e25e96a3b1ae4d9c3dd11198dbdad17ee9cd6f1bb9f6fb3d9f64cc5994d7b83390a9a9fdd16379867602d20b6743ff67d7bdf69ad394a1ea78c70271e4d9c1988c4598765de84b5b3fd5b1ba4a7abcc38bebf5be1d310cee67898d70d447e41fbe0968a91d19c3571970ad7c122097ba3c6439460b537af3fd010001	\\x37e87225199bf7b47fd1a78d76878b39ffd15999fb54bce8f5168e9d329ed9859e23f4782cd3c7d04cc39a35d844d917ae760f6cc13651e347651fa527d1880b	1637499391000000	1638104191000000	1701176191000000	1795784191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	390
\\xb33719e1a3bbad7c4206f8637a38701a26629bbe3bddb4a82b9b8af47263c1ad7e6d62a1a548439f5fa0cd76ca8587884fd25986eb76c50bfe6cf354f698c004	\\x00800003c638527cbd29b700c507375a7581dd870c7c8ee545a2614c578130086cb0dd2ce305f9ef89d55c14db52f74c76625d61d31042842b9582b96bbec7bb0016b2d04357883d4bcef731ef3125df82e81335dcbe7c06bfee879038492ff251958b693fe074c86a57c67b65b941b3b6a7134ed9bc00bdb5d7f1733dc3fab670e63195010001	\\xd87c0b6287d0615d9fc73ecdc38c41c5960715ab8efba7310051a2dfad9424e0fe3ba44b7d27565400f5dad7285a0b2dc0c1505907c042fbab6fff6923d92705	1646566891000000	1647171691000000	1710243691000000	1804851691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	391
\\xb90b370a1fc94747e4da8e48fe7be433af80fffe1e6ef283a5c1da0f276f585270db1d5ccea340f42bf8e9b954cd9a75c9fda8a8a08af175094ae044039cc1e2	\\x00800003c733df9358e39a7491a8eec83fd20505bb1fd5560329e310b273ae16ab99c0c0187bcbb2fbe20a51e5330b9068b9589fb1b3cdf47f8361b317846f7d6c2d237a77d0c0db38fc7b56d1cbff9cae343e96065dc4d772bd2f4516de5371aebcfad844a94221fc2cfa3af51fd2e0113e894a27eefa353aec51cd0f149da4c62aa525010001	\\x1b8726a02c6c3ce3d2c63021fa99fb14886e1f6d720390f1ff3c13a9175744a49c3456fd8428fe458db19fc8f34b5e4b23359071e6e0f97a5ca5145635366e0f	1653820891000000	1654425691000000	1717497691000000	1812105691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	392
\\xbb2b8755321f1319e922484547a9f8de32da947603579dbc30552a68f1644b298af73d2e5efd3a38e022f0f31443f1dcfd74b8dc074eb9a161b6ebf4b39eefbe	\\x00800003be482cdc03fc169ef16a770c5233ca1ac3efef9e5ba55250cbc8e42feeb60727ac616585a335a135782bc18ba46956ca577464f051dcbd6a71b0d17086f9bc1fc79630d2508aad368a33a726925f824c80fa0f98239e794de6fb86d5690d814e22b342b83264cfda9a8121bbdf5fdfd1a64d9ffd66f472d0b08bb261833a7b23010001	\\xb69572826d0bbc8efa2c09861dc21c4fd1b60ea3a1165044fb3633ed11c212202b9a37a884d1b349a7863d1abec76cf33d8b431af3a692a39fe7ceae9e2dc902	1659261391000000	1659866191000000	1722938191000000	1817546191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	393
\\xbbffb80aa1fb0d588b6f9166189fe300813acaeebb04bf25124590ad48d430977f81dd84a753bb6e9af12e877119cfc717a12be5851350defe1fbbf2872d52a0	\\x00800003c8cac2c500dcd5264930c8ff287ade0fd534f4f8691362813f89d81a82cbe1fc71461548c0e9058ccf4799cc0fe13a7447fcc79fe156acc4b649e4f0642cde8387669c357871d142697462e0c03f34c0bd4d884a69345bf060bc6f72daf801b85b7baa721b792562b166bc3b7a84611904336d49c9914eb6deada06689b28d6d010001	\\x187364dc0ae54b0bfcf6c1e295ae58fe9edd93ed260b82376b8db1e29afe9ee9d2e20b395e7fb75c97173eca2be6c99cd8907697a012f550fcc401a70594fe03	1662283891000000	1662888691000000	1725960691000000	1820568691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	394
\\xbde7fc8a39bdec80d257ea6cf327a39e1ecdfe88d34717c88d64f729edd1c331403d4997db58ea985ec63232650d5e51b9959fd84fe977662ccd5a9f2d13b9db	\\x00800003ee15b9c90605f35267bd1e2c9f169a7eead52e573a111a31639bd52b33c7ca02a5c2bd0e5b8f72b9f4da902508766f8cc91837f8572807f686558d8498646d2d4c1b4431548a88a02ad71547ff0aece232393b9a740bc34812207a746a919cb31fcfb90b6bd8c848e693e5fff87eee7111d3f19e20bbe94c03489198666d0ef7010001	\\xc032afeca13e4fca7759753accc27ccab8c46b784c343fe76523a4caabfc2c60efdc966c738196c584f8a416639c03c4b13a0c4f82b5995478ac4b11cb2b7d06	1641126391000000	1641731191000000	1704803191000000	1799411191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	395
\\xbffb6e319e0082e33ece4efe1351f6ed8351800210ebe1d2a8ce3659e1fa8a93b01c508f736c6a653ea93eaf19b27312ea79e025fad42e6a702fac7d00c17d84	\\x00800003b52d844299d48508d43dc98b73905140ad6727074075b2e0bf3e776ea3ad3f432e58c08256e2f1be67026d48f75f3a9bb8da6640d6f1e5e55794e633e9c02c6303b06ff49cb251e4cf652d06a0dba1edb0acd37e19819b549ab51f3491465a19bc666cfc035aac24cf0d9cf8358d99e7c6bfbd2bae32ac2ba257ae8840c5e7d5010001	\\xc869f63a4e4cc67dcf3c1ddc11e21ff05de806b4a891709b4a6d6b7106a7e6d65e4acc7306fb39bc3d91df152b9561d56ecba0f40c6412efc9673b0961d0fb0f	1638103891000000	1638708691000000	1701780691000000	1796388691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	396
\\xc0775055c1d4149b4f9dceb5219563f076b3632da921cb57535a5cb886adbe5ef6b7f192fd38f92b0d2b0d323dd1f8d31476d9086141ef5ea3ba56739a78098b	\\x00800003c59ec00273d4b68ad25e6045117d8fea6f8a8932a9495e9cdb2edd43e552a96ca972aa6b2cc72c90767689ed897516b86f0f0c2c4352904bb9f5f9732ec126304a86a62d8efe12f3c32e7a8a074dca405f892f461631f1dc318de17dad6d87a276037d9fa4f8b94997d9b7e703e7cc4b7bcab0343b322810d701b7906a279e63010001	\\x7d99c760f65524774bbe5dba2719358ce371caeb1140985d68f7602cd7918056bc9c846fde333a4283facae73a870efb4e570bd6b8ba6200ae70289e08bdec01	1647171391000000	1647776191000000	1710848191000000	1805456191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	397
\\xc01b03eaff193bfecd20b14db88401e888f5ca401c7e09e1d385169b146de2438f4a0f2cefdc3feba3af596ba9b4535681cd53463c3521dea0371dc81f413de2	\\x00800003cf04f802bded34bc81578e47124ea69845e3ac081a9fb34f7ec5633c5f313b489f6d647207d99ecadc76228c9f3b1abbd38e13a1cd7d0e9be89bfb78073479be7a947a644ca2918c7dff8d03471d530fdaa8693e68ce8e2c3555f299f078c46e67b4e5581268f79fa349230106e77e6482595e5e6982ad2f45ec77359b133113010001	\\x2f72708eff574a756065b4f66d6893e2416f8b30f93f464db0b4b7f7a6532471090d2fd2489401e0c82fbe7e6e3718d12d5b14a9f0ce98ebd81e96442877390c	1662283891000000	1662888691000000	1725960691000000	1820568691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	398
\\xc12bb1898447e13831515490ff3cf54dd74c60af7efa098b667ade77a764d96a37d5dbb9382fb60a6913bbd6f6b9e08004d72d8dd732bc06c66ea5383e59595e	\\x008000039935ff047603f3e228cf36240a01353f935a18ba5bababfc7ff3a89c30994ab147d17081460f807000aba8ab1926fb86b4a3f2603daaee725867496075d867e10ca66b1c86d81890d61d19bb3e2a73e03afe5eb6c0fa4ff9df353daea581cae29f645ed0759e865150034595cd692b8e42437811ebe1741dde60ecc5f155feb3010001	\\xcb29ec7b9b1236f4098a11482e84cc55988b4d3ac0397413870b722d773de52db837e67a578ebd3b072f932383e81c43763c7d931e5e5f24a77b4de01bc7f50f	1632058891000000	1632663691000000	1695735691000000	1790343691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	399
\\xca974237e1f34a7c57092104cb0447921519b338ca78fe536ec2bbb11ab51063648cc3e07c9df8d43a3d20af73787fe2000efc5bce4670401222490ebe6be2e3	\\x00800003bb694937b8bb52fb112c688fc6dc814018ac5328296b43cec6e2cb334556684e254a23b1901b517880a3c56d949167f7c6139c9d502f4b2c136d68060008a5a94dc470f689498b80f6d879a6d6eb963f0bc8ebdb42db4cbaa5591bf8d335d86351d48f9195946b6eafb4656d059ab62dc72ba5c83a78a5c00d6aaa65b883a60b010001	\\xfd15e58f55612e2dd8ee7628ca62f4d3d0c572db479b5a3d547cbabedec055f5ab178100a942ac5439238727109320cb720325ce33647a653dfb877c4f5e8a09	1638103891000000	1638708691000000	1701780691000000	1796388691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	400
\\xcbcf70382a1893fbfeb6da1be9a686f7aa6f63c12066ffda8b0ef4673cef544a4a1bec68c458af47bbae84799e2ce3e35806f973243b28a430d40f19c4f9b34d	\\x00800003969789b8cd878fabac1f51c562aee695885469d7e35dd5da061bf5f7027f33140bc6cc96a70381040f17c6d676b54da0eb4749dfca29cc76b697bdf47cf26de0fd89c2cd2946741b4a44c5ff527998d7f815fa7c7809bb1bc845b363de59bcb806c40378055f5eef57893cd4e723aa5d18f89ab29a1aa9485c2b114fe7ec9f3d010001	\\xead25a20419656045b2edff7f94a2654391d30ef0254834f9e6e4377df7cebf6b2f6eb5ecce86a3be66991239b36f2ba2e441b1e6fb87285984b1493705fa008	1636894891000000	1637499691000000	1700571691000000	1795179691000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	401
\\xcbe7d15602fde3aa1b839728b1dd0ffed3a2fcecc73c7c931aa6241466cb4f7f8ec094b234fe31a1f19516a9830f4cacbfef7d38d8da644bd560028797647c80	\\x00800003d783d900ed5d3016d3566333833769b53d79f90594d6f4721fd1170830bbd96a2aeaf20a8cb7fd81168ebf68e50114e1f3e2efd32db4d68526d2714f00f50bdc3c872287e81daec447d1b71bbfc30b9a0e2f15151e99ee08187ae73ad7e3ee870355b3bef323fae930c6a46a89b1a5fdf6a23208f241e5a17b141955ff05ab61010001	\\xd911ad4325df28d8fbde43a89de5ef0dceb01077d0296512a7fe56db6f252953f6206cc67f03ef0e48442df7226a9560351e3ab6246e341a98ebe6e5ca01300b	1636290391000000	1636895191000000	1699967191000000	1794575191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	402
\\xcbf32a68acbee689ee57a7812d803094d845b56141c87f8a20a417ab68229f40f0d3c3d03b0547629dbc48f2af542782a37315134a94004e8fda272c21c0c694	\\x00800003d4963b0290afd5062a3e268fa89fb6eb3b1260671fbdfd57b0af6e05c37c2fb21c1fb4dacbae51a2164a0b5b719d01f7023bac6acce74671a2b21a7b45edb2e35eb9f0e7124d1cce123a9d0b274f766c3adda573ce4ce7c2ebc65d0ec618a937f24fce891c3fb4fb991590c83a3aa18c4d84bae07a8d0030c6a465e49f266513010001	\\x7697a7d15d8cfa6c4ed1ae71a8fd5befb74076d19639e5cd641f1c732b45cb99850c80179bc920aa30955a5aafcdd24f6503033ba5a32d2af87ee1d9674eed04	1648380391000000	1648985191000000	1712057191000000	1806665191000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xd01ba724633981a1439eb6bee98dfd83dca551a18f0f30a3faa510f47781b6269acfba28eff5b124f16f93626a7a70d48dc97d711dad45a119469c68927bd3bb	\\x00800003d54d974b5e224383ed0c48272f1ee85070368faf9780b418491b4a3820c1a4fc3e20e0f70303e38a019ddf3c3cbe946bb0c88fe31b5b1f9eeffe99ebebe0bd2957c24392c42f93f187241900b59d908f929b020c7abd6f3f44281b7ab89c5254a7e83c3fabd630487cb2008ec29c691d155d1b72b06bb0e91d2fd8c56ef0b211010001	\\x132d58d64440a1f8e696a717f4e68cf0a44de4dc11cd30155137d77408e7490e739d55919b31dc26a73fb7733866050fdfef3c3f8c49be5b2a95c887c6af5001	1643544391000000	1644149191000000	1707221191000000	1801829191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	404
\\xd26f0f04b3a17b30ae8c9ae26a5eb7e3b5884af9dbd0c0479b4cb0fba774b6e4085523afe364534453be78acae422ee7fb39213095b454707046c7cf8c66e81e	\\x00800003c1a8cdebaec73ad8536fd6a12c868860d30b101dd6dd64ecd1b123f8966d9eadcfdd490a0dd5a8b94c6810a14835fd08892361be760ffd91b8f3fe2070750ff27bc9c1ee79271f59b8732f882ed5404c402cec01fa67629ab031ab2a7a0e5d33feebaca9aead1f112886299a03d30ee727749d6d81a5ed762f5cd13055c845f1010001	\\x1a4be54a0b4bf5bd2b0700af4644e033ce925b11a9bf07b02db5fe888c84c530d5e0e25a038c425c7978e7270222f90db1617ea88f2fa7cdf751b865b52bb90f	1645962391000000	1646567191000000	1709639191000000	1804247191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	405
\\xd5873529cc768a20579b43be710604453701681ac51f9762264fb8188ebf2772cf96f485518a40cd658ab02b6ca2d73ade15049d505c59a036bf448b2442fe41	\\x008000039a58340052643001549f14be15c0fd24c0c029f30ad0b1d7960c089b1bda98d80b346a2b1d0602c515182fe4b244d5055b8e7ef12185e33adfb57fa73d50731a1c2ee0e1f9f362ec71ab51e86df1577a000f185224d74f8aa3dc0f9d78d9f42aab8285950d66b8e7ac4b74b26deda9aa11ca0e9f17dd4372f262c9a2ff341da3010001	\\x857c4ca5d318fdbea1faa42d7258b5bb55c38f6a66492bc3735b6af361b83792fbb1877b6c0f1d6ccf1ace785a80ddb4ad7d2444d2da38439db32fcb8fdc720b	1636894891000000	1637499691000000	1700571691000000	1795179691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	406
\\xd63b04410a2f039dba5e0549f5253b068f603d9ae9a79fb95be1c73b4fea5488f8becfa21cde041ead368a4c6add6822c0a076ba95a6ce682982ba7f67abd0e2	\\x00800003d0766061d6697788c3bd9dd1a909bb6849547d28daec4ddb6d63cac968eac4a0fbe46db6d09fffaa4e4abc78e397573001ea7f48ac0b3ccc21942965731ba5b8a12f31f43bb161a20f136c55a05e3e28cadfc2bf4eaf8ae73feb5700ffe6d64d3d6bd020518c5124445b3e237fed4a98d1df431e7f1ad1e64a256e8198fb26db010001	\\x15610a20356a63e8090a8d378c487110f53c7f810f9de15b26ba4fbcd63df5d0d41552a9792595a121e7925b751ea7a1a7013f78bbaccd71c5f62f647720c201	1654425391000000	1655030191000000	1718102191000000	1812710191000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	407
\\xd7ab20c2032b11899532afc16b72b1cfc98c3349963542fe279a3ad874bb3caed8a3173dff8c19e49af3ebc696a8fc8dbd101df67cda886b14f966a952ff6351	\\x00800003c8504199b40de7cb1fdb6d691944ea7924570f9f40063e4b9f17faee9e781c2241a58541169508ce826bb34aafe99467bd0082063c213ac69bd4f3afb564bef305da15499fb3019dd1d753b37c9731c519beb6b2b1787ad451182b10e99959ddb7a9e60c5b2c197cd1de4731403259ece73eafcdfdec39ec86a40cab6ecbee5f010001	\\xda426e9a956c76470b12ba30de7dc3515fde5beee5f82fe6f7d266d4edc7c4af2ab9ce9413af99323b0d7ef79edc374a5d4b0eefa1995cd47935ef49d63e9e04	1653216391000000	1653821191000000	1716893191000000	1811501191000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	408
\\xd953e8a63c35e2625e2c19a08df9ca5f30632419a612c52b74008e3302f8ed2fb6f7cfa034fc6ea93925d45e61704722f70a570100b71c79af63ad67822b3f27	\\x00800003eae354b6b8b901746d64bff9f6d0944d37da14fbd397990e81284152dec88c84e00708f62ca11b5a5ecd0ec55c287d8acdc896b9cabfa2a141dbe8571f1f0d003539c948addf4d74f5a981b18cb5fdd0cde94c9fb1d4031446c69b0bbc79a649f19b443b6ddccb920262a5a8a652bd8253f97a79c6e4c9ef41ad7837209096e5010001	\\x342de80404e333ac6ffa44c368493c6d73e23e577a3ef44c71214b908ec6e3947ef0ac01d96336c1a0e1c4ca537b7b84f35de9aad19cdedf988e978f9860690a	1658656891000000	1659261691000000	1722333691000000	1816941691000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	409
\\xe1ef462d121eee0aa66e97ea5d80efc8d561f45283ef2eaed02f3eace6952ff5af276cfa4d9784bde7c3e958382a89960c4c034f690075f31fcdb89a91b85d40	\\x00800003e1c1c8b0dab16e706ddf33e57275e3841718681c7783bca92da789ff6109d76d0b78ac1c85dbbbc2fe0242f02d70b461192123c0a33e4bb82be45497edfe17930fa5acbc29c18731080bf97b52f520643dc72d11da692376e3393dfb5a59d506e9127457647aa702723461d04a40ed2b685c5f4a8088ad45c225495becf5bb73010001	\\xf7b4e548710a4796f9afcf009c546737e9b9f71bb8e02a6bd360c4aee68bb3051bc79eccc8d657f187bf58f31e006f28feef2675aa54ab036c6728a952f9c709	1630849891000000	1631454691000000	1694526691000000	1789134691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	410
\\xe1236857bb1a1473c5dee47e8acd8d06b550d74f11bc5382d2120115d6ab75839456eea2b3e58a958e06ae04b3685447723cacf4e7b07344cfd8ed89650115b0	\\x00800003bbbd67123bc9ca6faa276ec98af20738703dfc908e43aab8cdbcfd5050d034f54ce0b7b9da40fe7e62e016f63fea1e2fe5fa316e74169cfdfc0a374aecd42cac37ae32d2a6318a50684231c3ecfba1a5c421670baf4b61f8ae1640e6972862958b2bc4652e30635cd3c4bdf402633d0a64b22186bddf2fa9729f04691733cea1010001	\\x118d0a653a1369cf25f6d3cb722a2cc6f571ab6583b17ee2f71e5d97d27d53bf631f4db1b28e0bc2e49ae312bc3b53624478edbbfab13b09135b13ea28c61f0a	1632663391000000	1633268191000000	1696340191000000	1790948191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	411
\\xe73f853c6a84e00c2241cbe62efb05a93c59c789a567eb428a04a2d89d9924a78c8ee874886840cbd072a32464abec08807bc401599168b110a372e264240f6a	\\x00800003b8e717d5b7c565b31021bcc351b45c711192539be71937924e64b26bb842b179f80cb7f26327ac60644f0cd654f31f14ec92287c870e146a4d7f0a6e42a7bd0e7bedb313c3cb8b7664c481831a82fb45af32a85a8834ab079c59a52aac76a43183d6b7b3ceffc55ee6099d8a1c772a4e93a3009452fced6cfec652700f130711010001	\\xc3e9fc008d116e0aefbc10de65e0c0c3bca9c5c02d56a79afab68cc57d08790668f79e08e83c4437638194fc4cc2581bc68bd76aa21335b685629be634039402	1645357891000000	1645962691000000	1709034691000000	1803642691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	412
\\xe8a793bb2352f1038dc9a710d29355c82844a530a1ab46c6e80565543540b546f991cb7d62746a3957da5bfb3ec240f3b75d6ac81a5747a82d93deb4dc11a8d2	\\x00800003d432f70b1e05efcfa1188537b351124e636b46f669e2916eb1eac19151fd782860ea9a94a7b028aec2bcf15de8c2777d38c44e46f98bbb08b1bd0df0b5f47aeabc8fc90fff9486bc76297efda65efde4825d112e1e17d47c9a02c22e1645b5946825c5df63641d0bd4d396e9e136cacf913e90dae33597154ef438b6e304d007010001	\\x2bf805ee0472ffcb5c6c24985d02f47b125e48567378a2affa07788635e31f463210ae8424e98bea3997559b86628609ac2ff3d9e8fc2e1da572a6928eeb220f	1659865891000000	1660470691000000	1723542691000000	1818150691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	413
\\xeb3b6e04334bd79bdc0ed8f7fd5edd72ed1c70101853722ab7fe96ac84182bf2b1952f46fdee36a78d4bd1fc6b17bbfaee0f90f13d1577efec865059fd7904b0	\\x00800003d59553e982d16c213570eef85d588c4f1326a1f4c5b16f84493166825e5e72674a5666e011c3f63d9cfded688bbe3906864c2e6ae1088cb96fdaee35b1aa7da0b99b95df63302fc658796ca1c84c3c21bf98a0493c77e5766db562260fa04d3dde5ad125107f22921ab382531da489a8ef859b512ab0c1624fc3daa3a38af743010001	\\x904f18a944e4c1c2b9827513c94b77b127691041e42357c3a9f6a8d0aca690119b37e1c398c5ccae22a67ab523546330f18abbe43d0e5984af1e0c1a66ab8808	1650193891000000	1650798691000000	1713870691000000	1808478691000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	414
\\xeebf2b470eaddd63a3b08342a4c979b40fb4c293e7bb451f0b124ab73602a7890b5be8336b7c4c204bb1c313b3a9f19c83794b6dcef6538c3293f9b48be57fc0	\\x00800003c8a891c8d817b01121249622d6de45d99ad4890aa32e72aed59b9d250924ebbc10e5c09874e719860e80d062c6503c2ae6cca911bebcb71a4f80b2bbc6d5d0ec6967190bb0f0be479e6280581a348d879721a4f79cb261ec8a5bb3aae973516e99e553979892a9656ce08149b9435c1b82c87c783b825375d6d309d0e0af46a5010001	\\xfe0b2b69b1bfc510f367858f8b8a4b0006722fd3e70b660fe098d71e43ba1caa3bc1efec7f2c05c6847a9cb11463c7c5f34e4afccef6abb60e6502005f492f07	1660470391000000	1661075191000000	1724147191000000	1818755191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	415
\\xefbb980290168ad63688dc4c4814f13aa62225196c4cbc6f50670254c2a8618b7f372008e40a30d4f5bfaa39a2a91f3c2b161be47bd0b731611d973c056cd171	\\x00800003d8dfd31082a1bdd47f2ff087ee72bbdcc8653122ad76670184e2f4f3ac1e3b6a0cc3d03a205c5390fc107742101d6bd7bf6c957ff62f03acee9eb28d6103ada71d8993c2bb14ffcb8a407783babddb9fa6e33f9be807a344e25bd71d2a1e72251d4af03e08c40b31c7cab2cc9b7f6462b293506aea0260f1b99ca893d27eb6c5010001	\\x5c7d1c3ed4c2c87e521b8e3589836e04ca2a1afd1a69ea6cf5e075177988b9b03e6b0773e45230a08132b5eff3d3a62dc8b28cda50e314762ac495d55e53740e	1632058891000000	1632663691000000	1695735691000000	1790343691000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	416
\\xf1c7c257f2ae0a63820be6523431789d8d9b3af819be7e0b6df1e50c5a191c47d1962d33757d49c860c33d7325896cddf98ed30066931824144c742439bad362	\\x00800003ecdcc46aa4e46d7c14e388f9832cae08ab177964795af0a2c226b560ecaa04bc5f4f4627f3e8d96bf21d2991667dd42c4dd3e441ed553c84d2e37343b058d8ab661896d14e9cb60d215467804f42bf90ed8882d921da1495a660f0ce98b53056f5826c97184955b663b7cb55111a4c71156b8e20f61276a69161e67b12734aab010001	\\x159386115f6666234a8073f10daccf7325b6cd1593ba785404f172875a7922958d497f5a6dc8d1db3230b8ef78ee7ad14b409b740567ac75f83dd481f2f6c90b	1653216391000000	1653821191000000	1716893191000000	1811501191000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	417
\\xf42f289cfdd06e2e7b9f46504a2b62d49d3235af64d8bc65d4ac68e6f9a2950e2f0378baa604e5b340520dc52f7f7b2394edc31be2703dda70d7885ea1fe129b	\\x00800003e4006b73018930db7a7824fa9b86e54baeebc6934c914fdde8c5fddcb17c846bf2f5d5d047fd3d3702e34eb2ae359cf71dbe05581329c2899b332f24da5154fdf179886929465cf2b1ff7869fdf9ffad985b09ef6d0d95138c71f928b13a07d024aa7114d83ba6a14e54134eec2fc5d3e53d119b19b48ef971d9a520e379de97010001	\\xd38ae3cc49732e5c94dcabb469be2f438dd65a8f7193285a5a575ef2f0cde3e3c0dee5cc7b5a2f4c9d090c0f0184c66f0098fd9be4b6515f353bec8a7eb0390a	1648984891000000	1649589691000000	1712661691000000	1807269691000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	418
\\xf8cf4d658c3a235ca047d486a3a0e3f0de4439c93b1e5bb54be9ace59cb9d67543339564ef8aa548923fa1670a791916e953c4c7932c35156d100f1665bddb21	\\x00800003bcc827ec07c459f8745cd2cb15a92f83175b7ea9e3e2d1127c99e3bdb48730683fed88476db0b0952c0889adce83ded40ea6903bf79b5d57aca52e1d391a994357f0a537fc237d261ce375d210b53d4320ad90f73d7d43b462bc4b011d3daf5b9ed17d52e01f2082e83f1dec6f505c18b8a75f1cedfdecbb3b8a6e042592402b010001	\\xc2039845c0b6299a44bd2009396b444ac3aebfe536710984f9244851d234828cc89ad5b3734132f1da4359cff073abdccdc75d4ba51bbd1fc619d3af59e1bf01	1644148891000000	1644753691000000	1707825691000000	1802433691000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	419
\\xfd43bbeb226b80dd982423fc2a6e1377c89783a32fa87ff86c9a2d16e6e6a9dbbdf43f98b113d17426dbf086f11ebd87a7cd9066452d50a112a49de4923ee937	\\x00800003c82a8a95b84f6b75af1043639014a8ee8738d2141919b1ecbf47a7b7f37b0454f176ea729aed4ad4c9f8535d872e38c14c0fca6fb97ac56e61ba1c35ab303e91576a8037dd49e28bebf97ca0373bf9eec34438f3195cb22bf6c75d99b34d3b3aecf548b456d8de97466f5c5f7db2539cd48d210a89c310f3f2afea77d654dc43010001	\\x370fd99f4e949aff146f84d2eccf4f1bcd61620da6d85dc3fe6cfa3b52927602a03061a6879c55a9e017c684b0af60560ab485bab78faef4dc11120c180b480e	1661679391000000	1662284191000000	1725356191000000	1819964191000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	420
\\xfd5f2f8dcda4ec6caf58a2e22b28e58941a31080cbbdb99ca0ab494e44e4b8daf625d1dfe78b4ad24ace51dc03d0b10fb0268b5056c988329a5da7c2e1c62500	\\x00800003c5e01fd5c5cf6e7c255def00d95a68ef739d74ee8d667237f746dde2c359fe6408fea126c532df1554e062acbe71dbc8068c8456aa73a4d9515f2cd77e857dd0077d3e34adc80287deddde658cf13bdb938d38a66aff052bb05bfa54f00073558c4df2e3e417b00404a7322d59a069d4ac1916f27c3998373898296f1f10b75d010001	\\xa7dd65afcdac81a94135c66aa8a14f3e3d561df47015ae7e93f6f7d2f46804c996f83311988c4deed81e30551c5c7e584977b1842de369ba2c7f6de8249b3308	1639312891000000	1639917691000000	1702989691000000	1797597691000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	421
\\xfe0b95a7f6576aedae5c320b5a68258faa2918c64e4f8a3a085ec4dc70e077c4c9eea93b220bf72c3454b25310e69ba1ef7d4929fc6ef30ac1226b156d4c6d77	\\x00800003b83c15b29ca78ab7a102b9cb053b4653abc611fa20e361803886005588375c38dc720ec4984d22bec450c180717fc690dd87a1149a755b8c5ef197bb705aa3cc00230edd9865be13bfddb4d348eb1f6680fa88cd8f4020aa040a62b1f1cea40ec48756fc064d60c9bcd6a5f632dc8decdba90f75d6c51efa11a74ee1ff0e806b010001	\\x129ff2d46d956b47dd04f449cfe0d779d910808632aecca252cf5eef38e9c5f5235700492e15ffa10bffc1fba0cfa4967e34d2410d390be8f95d05a8059a5f07	1656843391000000	1657448191000000	1720520191000000	1815128191000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	422
\\xfee7921706bf47cac53efdba42fee8ed80d3d5a227d97de0151ea6edda247fb7819c7f32adfea2b31f359e877618bc3baee2482e97c5e6d2be077b44750a8719	\\x00800003917d1248df553c5ac0c6e34fd95604a851e292fd81fcc7fa27524c1a44ba36f1fa6a83451e874cd31908f5750a4c9c669f769b5b26023dfb6e702b1240da746de3ada9cc9ea734f94b974ecae09657d8e2f77aa31b8034232179e03b019b9d889169495e28738f7761f5f5a7bb060338be1f5c50262d216747b84daa1407c873010001	\\xfa5c44973a3402928894b699b3246dc365d813be0901e760d487e737aa3e15f92932b5841e23cb7c09450a13286f877ee67ff232e078eed0822167c0153a3708	1656843391000000	1657448191000000	1720520191000000	1815128191000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xff971c27f67ffd758085ebc848ab1df0aba930ef90798c59847952614d2f4a51ecf89b226a87b233a6260d92ea21ffc415b9866cc594c191ad47ce8cf3253af4	\\x008000039ee8a7340322f16e4d525baaa0c6d2a2d5348d170b578f45681ef8174751ecc6795e86fb1e6cb0df5f0cf1535683a0b1950e9788108166d0360fbccb5ed90f377bb58cd9ef77b0741940694ea8172b62e042d2e3511325f9deb69ea46847cc6799b76db50a9f8099236cd5e36466dc4c430746ce79b6b954c23847996af386c5010001	\\x3d70b5f0e682e1593607c12861582280cf6de53da78e4221ca012d08f33c8ca676ff78d432af1732df716480750ff93f1a6447997030498b39dc6af2337e6c0e	1662283891000000	1662888691000000	1725960691000000	1820568691000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id, shard) FROM stdin;
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
1	contenttypes	0001_initial	2021-09-05 15:51:31.798082+02
2	auth	0001_initial	2021-09-05 15:51:31.854338+02
3	app	0001_initial	2021-09-05 15:51:31.892723+02
4	contenttypes	0002_remove_content_type_name	2021-09-05 15:51:31.90646+02
5	auth	0002_alter_permission_name_max_length	2021-09-05 15:51:31.913559+02
6	auth	0003_alter_user_email_max_length	2021-09-05 15:51:31.921876+02
7	auth	0004_alter_user_username_opts	2021-09-05 15:51:31.928196+02
8	auth	0005_alter_user_last_login_null	2021-09-05 15:51:31.934257+02
9	auth	0006_require_contenttypes_0002	2021-09-05 15:51:31.935654+02
10	auth	0007_alter_validators_add_error_messages	2021-09-05 15:51:31.940818+02
11	auth	0008_alter_user_username_max_length	2021-09-05 15:51:31.94948+02
12	auth	0009_alter_user_last_name_max_length	2021-09-05 15:51:31.957133+02
13	auth	0010_alter_group_name_max_length	2021-09-05 15:51:31.967293+02
14	auth	0011_update_proxy_permissions	2021-09-05 15:51:31.973802+02
15	auth	0012_alter_user_first_name_max_length	2021-09-05 15:51:31.981363+02
16	sessions	0001_initial	2021-09-05 15:51:31.988354+02
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
1	\\x266d9e9e6a622427d9a6bbacf278735c0442210fde343a68ecfc4f9b3e404260	\\x6c167ce6eb8dd908a3a13d1bb3de996630ff3add1eeb103eaf2f82619b89997cce448a308be98dded98d9645788e21bdddc73abe28f082373c2a572d773f6b03	1645364491000000	1652622091000000	1655041291000000
2	\\xeb9ecfc8df5b215b3f9fb666b1ba6bbe40d7a6506b58a833c7b58c79401d8c33	\\x5bae0e3d4f186b268a2acab9556cf1dc789f53b40685505a9e3e3eaee609c91e006dae262f21ffaa66c12e7bd66b4a060a6bfd8b7d190d7fbcb1c71b71f22c0e	1630849891000000	1638107491000000	1640526691000000
3	\\x4ea3faecfcce0400e230d0735e9a828552e68c71d41a61c74e8900adfe46590f	\\x3bafd53883f702d0ed01c89bd1613295d138ad7f23d37dcbd483e644dcf88d7ad2197c9f3d78d5d9951707e230dd91e1482667d3cc5702a5e0ee7e99e44fc20e	1659879091000000	1667136691000000	1669555891000000
4	\\x9a2ee6a72fa0ef71268f921a11063a095a92602dd7cb029531cb87066369f66e	\\xec1178186a2a6c6a8b516ac7bbad6accfacf4e7d1ee061aadee03d53f79a0c29d9a19eb44e48d385020f7b47bae5379d298507d286c31cbb5aa0c4adb6b8ab07	1652621791000000	1659879391000000	1662298591000000
5	\\x9bff17b46249b09c3ef85bb11bb95a962195da9183440dfd345ad2b07587aea1	\\xa0365f99d756874995a6840f8dcf91625a2d2236d214e3a6a724ea93b82912161b576c61fe601997ca46076212b1181794cb99cc4e659c54c741bcb7d358b800	1638107191000000	1645364791000000	1647783991000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\xb530f86758cff4dede3180bef49a301d5a561abb75a12c3f11668c94b1617953	\\x5dbe4cce7c02f62027fc3bf12052ed202fbfc58d64a96d08ab609e028b7377571909330b934c47f2b392c4a73c725d20c0ffe884005b489a903ab9a32232346663ceea4107eea71fb37029109d6ae833cf92699d8ae79984449f8aa664f0eb058e7a2bd812aa7618cbe75818c783cceec8f3b4361b56152e847cd03912fa27f2	247
2	\\x19b03dc657180d698969336c26975201e49f3606c0541786a4249bcd4c2160f4	\\x7dc208a3b4a087c7811bd68dd4e80599cde1521852eb598febe78040c919456f7c37a9388025f55e73d1eaefbf95fad6d9362366fab2a5c3f180f6ffc5c6d632a77343f4804d2860d8309e5c19dc4766e24a03ae808d08406d50582c62cd06503502e1165e390999c9f3d5fffbb52f149f0c95586392debfbc51f0ad94ac93eb	8
3	\\x0700b43896f75a968146ea50e56d384998fd9813908512908b0be23853f2fd11	\\x444f1516791566901e35b9cd64275ff273038f3ad07d871a33b21561e603c6fc8486cd29938fe73a2a0b27fd565b7a9cf7969ba873e3ded642a683d53e054bf09386ae2a9899bec55fac43364a33aba21dc5c779ddfa0c7e903eec3b703173e09571ea43642c8342cbedcd5a673154586acb4ab3bc6d81a095367f910d63835a	89
4	\\x6fea9f2b70c22ccd932bd1911c1c2666470d56616191a089d7a3b381271a4da8	\\x6ced8e80b744f5e32c55d8c3467b43d633911e7e3d171f670e0bf78643ef12b8c8f0710b0773313c9179e2a7446869fded767ea984029a2b13298b7a077bf5735d7fb8ffa125e36d764885531731b525128e8b08e573ccf19c1c60e5d64b81c86af88f7a93fb7c0519523c39dece5637fc4ff025ceb9d6325ac216dc6f6d7310	89
5	\\x6b7000a330b1116f9218c09bb1affe4a1f5572d9f0f0be1e9c3c6614d6475a6f	\\x45166b3810330ad89dc55668d0ef8598bf9b650b3a157ac22f38c883b81e87b178a89fcd16a7a9295f63782cd1d2bfa295dd97786e7558e508df0ba236881139b3258c2b50ce790acc5ea6f61ea89b4b0adb7f12ec3f059fe9670a12564727dc6e6c3a43085749f16e10f2fa84df4f5edc8c38f9651681098b09a53c9e305f7b	89
6	\\x6fd840f721f28ca4afcb091e010529b4b55a68d18f36a2cf05cdaa1c16e7a09f	\\xe1e097ead0924cfdaeb70caca7a9c1a4b2e518c7a0e07c96d74affbf9a5f32ca22641662adac66b2f14798bb54043edfab08cd3a0d781c283ccc40dca4fadc02720a5bc586feccf526476700d88af75437b26aefe3e363de90dac34f0983380912071dbc51b0a62f64602a6d0ed4c64c1077b98445114ae651ff1fb00ece8815	89
7	\\x345693fe722d87ff5172beec2cb13b44c0e4d966bf9feb1c71722e36e7d5e3d4	\\x3884b99daa4c0d525fe2d89f36ad99c427e5b194e1d81250d82687617fea07d62c58f293e12bc24d1cf826ab6a50fdc9788549bb70a1a903fcc7b186954caa58505d3ab07d94d3c1453cc15093b14844d555585688156313d1e9848329ae05e54fff8a63dad0c026317a944e7cc05e38ea7a738cbb080d2c7c4051bb01e51c18	89
8	\\x48f3784b67a3f45b9926c702db3e6e589c9816492a2e8ceb4a207170c95d8127	\\xccfaef14cba316fc5f9dcd977051fbaac717dbc3e59f52b95683bb8946bd14f6fa14b33cdc0e75a0745c36bf4ab2db4c636530202190236595ae8cb10ec5ea75bb3ca4c4d4da47a7141f28535291091f8c18bdb29304cbf386670dd9c5588d9ecb54b5a3aeaf067740ae2a5121cae2503d826946b35e07b8152c36649431996b	89
9	\\x8fe2ee04e8dc3fe224eb390f5f9be88ee7c12d017f6db888ef58339e375b912f	\\xcec4356c4da07e350719656b789d94a2a9c6cc493af2ed9b28cf3263e5a4d0947254a326640db58ab5408bf937a6675436d9995662c646a150dc82c8c8d38d9b5f261b9def66decb17549e3672f26f3a5c488a42ea9d887c4e7c33f73b30fd125a4a0507d4b3f1f46aa6929135849568047dea884c8d6ff1b34b77875f449fe3	89
10	\\xefb5fd64433fa6c987b907b19a812b63c9f8288679b732b7666d324af1d481b3	\\xd882f8a0f7efc903326ac60f24659095bbf44fb9a144b0ae769356af3140764c2ca3cf6a137e05aa94fbdfb8578d2dd98dd3ffbb61f846a1b52c9d1d5df42bd4df540117f9904d6a55440f2c455938d363671c04691e87495bacb4860b5dd4d01ba335c81916700bf8543cb3dbb630d730713bedce9eeaeccae79a4974872a25	89
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
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
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	\\x266d9e9e6a622427d9a6bbacf278735c0442210fde343a68ecfc4f9b3e404260	1645364491000000	1652622091000000	1655041291000000	\\x6c167ce6eb8dd908a3a13d1bb3de996630ff3add1eeb103eaf2f82619b89997cce448a308be98dded98d9645788e21bdddc73abe28f082373c2a572d773f6b03
2	\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	\\xeb9ecfc8df5b215b3f9fb666b1ba6bbe40d7a6506b58a833c7b58c79401d8c33	1630849891000000	1638107491000000	1640526691000000	\\x5bae0e3d4f186b268a2acab9556cf1dc789f53b40685505a9e3e3eaee609c91e006dae262f21ffaa66c12e7bd66b4a060a6bfd8b7d190d7fbcb1c71b71f22c0e
3	\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	\\x4ea3faecfcce0400e230d0735e9a828552e68c71d41a61c74e8900adfe46590f	1659879091000000	1667136691000000	1669555891000000	\\x3bafd53883f702d0ed01c89bd1613295d138ad7f23d37dcbd483e644dcf88d7ad2197c9f3d78d5d9951707e230dd91e1482667d3cc5702a5e0ee7e99e44fc20e
4	\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	\\x9a2ee6a72fa0ef71268f921a11063a095a92602dd7cb029531cb87066369f66e	1652621791000000	1659879391000000	1662298591000000	\\xec1178186a2a6c6a8b516ac7bbad6accfacf4e7d1ee061aadee03d53f79a0c29d9a19eb44e48d385020f7b47bae5379d298507d286c31cbb5aa0c4adb6b8ab07
5	\\x0367c12b033b8745fa884971678773a06c03a2764aae69a4f78ef3c88b901a90	\\x9bff17b46249b09c3ef85bb11bb95a962195da9183440dfd345ad2b07587aea1	1638107191000000	1645364791000000	1647783991000000	\\xa0365f99d756874995a6840f8dcf91625a2d2236d214e3a6a724ea93b82912161b576c61fe601997ca46076212b1181794cb99cc4e659c54c741bcb7d358b800
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
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

COPY public.prewire (prewire_uuid, type, finished, buf, failed) FROM stdin;
\.


--
-- Data for Name: recoup; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup (recoup_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, reserve_out_serial_id) FROM stdin;
1	\\xde5f4e26d90ab076b1fed0830bd497cf2d2ba8a7a69689237049bdd9fd818ab1633bffbbd91072f071f40d5e2080c23a71796c874e2f5fedce33342487d71a04	\\x8ad497db15d302d0dca29951630651781b7b126c0bfb96c2cf5c52b200e2c05a	2	0	1630849917000000	1	2
\.


--
-- Data for Name: recoup_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh (recoup_refresh_uuid, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", known_coin_id, rrc_serial) FROM stdin;
1	\\xcaa367df9edadce33fc2f8361189408cf4bd03fa55483865ec9a05b479ba5ace1031a95245ca8866da5793395a31aeb488a4464af0160d903d559770a86a9e09	\\x5c77569b3b2cc0cb15d313d58b2626c510d780273937b8dc016680de6cdf4a20	0	10000000	1631454741000000	3	7
2	\\x2804fde71c2e576f0ea165779d361221f08ef0cb900ebecee80c17ec10f5333433698d6e3f9372e86b838fa296d40744a15a3640dd640a4c2b9dbffe577dd70c	\\x053d2c10496879d15764414d8b5e7d6d31cff8c40d43a2a3c586d02410ad8702	0	10000000	1631454741000000	4	5
3	\\x695bd6664529df051fb3258be81d12a48d74be46f128c73ba97f73e7d67707a5336494cdf446ed4de2eb8667d5272d118cea4879a681010cb5bdbd8b96580601	\\xe624806601595ed75d2ae4077f0cbccd504147ae93ab62af7e99f50ad5c90c7e	0	10000000	1631454741000000	5	3
4	\\x5a2dfd53fae2bc1dd376952f1e4ba27d0d6718b2b22c906bcc0ec5ec526d8d4ee5d2b8771f0bdd2a4a94d5aea78ca0bad1702ade36c0782c81a32e947714290a	\\xac47952fcb19c11426529003d5423ebb2566e4c4db268aeee8d7cc0bdcad9cd6	0	10000000	1631454741000000	6	4
5	\\xbff84e619465af4291475497f06048a740e1975c7d7e2b7784a47a731012e3d04bbc8c20dfa088694aa9e198957c8cad5dc7ada656b4ca1bb04a4879d3914f06	\\x08238f3f6e942d648a9347f4b1caa100a252c1bf827a8a12fcd6d375913a8d62	0	10000000	1631454741000000	7	9
6	\\x642c8af67d0ed9ff941b6c65acc1272e2c3c53f96a51d105e242ca83c212f52b89042c9c607b1ca3d0c8d587e51e0fe052b00f4a661d5fe16a7e77ca5be9fa08	\\x39bf8461b10980496edd21e7ff051cbe7a93ba0b777bb33589c6f2bbabcb8bf3	0	10000000	1631454741000000	8	2
7	\\x60a391f913544c7ae1d168e3b9e4b5e92f0c413de76175f5907db0184bb5a451bcd59c0d24a34a9bf9fe6ab77b68a03f5f112d999416c1eada014e9375ba420f	\\x7ba958766af4224fbe81e27bf814c9fd2476960c8651b6d63cde78e6dca83ddc	0	10000000	1631454741000000	9	6
8	\\x9cf4736abf82fcdbb3ef62b03be3e66a88f6a6b06cea78798e2a867ccbca7c3cedc4203abeafcbd756e7e4654bd2c2590395b77f188b708cca3b33cbee13a80c	\\xb588ab9fea7ccbea1385603ad1fe01420e714a9dea2830563d20f66f786ebaf7	0	10000000	1631454741000000	10	8
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index, old_known_coin_id) FROM stdin;
1	\\x11de57a23018a7ce09637e755505e73a11eae3ef975260ba0eab830b8a90e71164cbb25f30525d3148c7da344021963d3a89740b8f6c6ae1c37b794ccb40ea3e	\\x0af80c6a444056cf2c28d7b7da834a48789f4dec53a3d564b062a8e6e7a65d45bbc4b693372689d77e7c00c4a57cdec8618c59e2b86002657206c10ee7e0d20a	5	0	0	2
2	\\xbb7e5c8b036df6827efc846f43c344ca03bd13e66845e444106d2a38cd8baa710af4656fde0ea1d99b523d8abdfd3355a791a5cbd0ad85d0e3e1e7d70f82a711	\\xf6bd12c5b4077932df556a6ce504ee9e84b9d536d6ba6c891d87e1f79a2bb0886db74004cb8b6010a817c38a4aa707d48aad3adb3bbac2a1a681c53482b6c70a	0	79000000	0	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial, melt_serial_id) FROM stdin;
0	\\x166b205c185b4b5daf1b196bd45734fb00766a66f9dc582a4528d338125a8f9cfc0cfa79373668e5a20f2f4394be0b19afc2e73bc4d29c948d35f82524fc6b0f	\\xa012ad9f5a7c47102e7edfc19b1244422e787613a9c42c49ef2d0558aefa55182db0d42318c258137d10d54f2c0b6a0a502397749382ed87748a2f4391e479050bd859d5a58ee1c4a611eb564a1434601ff28b7b2ba6e1f1c7a305b526521a50220f56541d7c9e328ed38abf381821f1514bbf95a91ab3fbacd6948ca244e1e6	\\xe05cbf083b9eb6977a83f6e87af95181c2d1949ac4be4ebdfc9f415158ec75960b9704f8c818304930c7978ea1ab65735c3c8355f035e1f63d4d45ba593dbe26	\\x248bfd5c8ad86c312688d58e1168c4a42d64068eee4d33c1ef5498e7113951008e49830c3546fd99ff522c14d303c04a291c7199f145a365b632cec2cb75fc1dd2252ca928d91c220314ee0459857e189ff2a078c9c8b7721576c7e700ebeea54a091e132c661765b6a9fd9281d4fc2754701c3b6f9d4a636c8cf6c63bdc24ec	1	242	1
1	\\x53830bbf97456564254f1fd5a741ea75cd7ddf9215de5c758bdc2d5987773c8f6075836e14a7169a62bcf76c3bfc6bccb521f156e1a0180e11d4862c82ba2f0d	\\x6b1f68d84ef5eddcea84e044c80bf9863243f0298a8a47660288920bd4847175469c02fa3df8c38d10436ba60001e2922806a080fca4a345ec7f13c87e6d789541d09d3fe964b02de7d5f5e8c2829fc31059b0caf565257133b0d47ee6d1b1e23f79c9d431580fdd01aacbae2a4302457714963d98776db0ab6271434e766516	\\xd39f1f0f2e1e1b4a883658a9f9fc32208b5824a5d9f7bd49ebd6b30c3631b4f2200be079cd6a4d201a1e3066a9fd5aa3150d4eebcb4d0e8c334f1700ff31f830	\\xb0c94f8489345fc18b653b070382982ec2dcf39aabdbf224dc12d14b3e69dc87cbc403beef1aa3351c05223c4bb9f831cfe5c8ecce7b42fccca97df4cda75da6ae34e9ea39d72bd06261894451583abcd942f93e13ded22bb4ff0baaf6989bc138ef9583ef09201965a6a6530a14bd1d0474352e2093be2ea2e50cfaa3e75d99	2	89	1
2	\\x7231ff9dfdd723ef2b9044c75421d7ad9ededdf627a0a4b73e7612fbf0f71b697ab8942554b9a6fba1a76f75efb09dbcf4d930787adfcf7e84b92602db526301	\\xa2e05640af36bb5db5858e8fb42c59b87a974e749371c60b4114ea65642401794c42a1607b2f59930491a07d88092238350acd867685ccb6858ce456cb6d27a586483db4e118c8b251cc3001f8b2daa4835bb96ee2dd35e397001ff5635e4e90abfdb958dfa6e7be49b32f878b38a226617b6dd62985a6245e65ed277a57667e	\\xdbaa5239e82a781156fbf7c821f686ddf3387bba9e5254aece47f23e06a3f1afae5e380626e06b90dd761187f21a9a79500fc68843f6751be012250314cd3ea4	\\xb79279ca52d5d58ce6d5e35d31864f8cad0704ceac5e2e3eb79cb0011e86dff00b8547490201d9c26870b87a8f9923f29edb2dce1e6fbc720d80be2d8552ca24108e04e8bb242e93bb378abbfc154838b18302bed4a4468c763afa8f4906f8195187e6ccbd7bc4ef3a32f0617a75ed0a36c9ad14ef6cedc18751435078c98555	3	89	1
3	\\x6e1368a09814723048c00334ed3d4ef65f8273680ba6b50cd8a6ca5b8ad4f6ef5de2337013f474e73aa46a94651b2dc3bccabcfd232c96fa64ba982f5a9f7c08	\\x0d600222bc5369eae0b707e35ad8feff670d8b13fe0af38d8385f18ed97d5e1c0351821da063d41f6fb46136756e5b40b79154501230a2b00146478c9535d4c17138c702b15acfa63cc93246bfca0f60658c8b2a365e64c66ca3032da4e2bfe6089e58f488f834ea91bedfca4295b7edbc7b09a6fc9d91fcb410c06c607dd017	\\x0d220e0191aeb295a8e5c4f6a34083e6c564fd31988045998077ba9a0189b2f336b0fa2078fabbbbe192312287c4fc6c184e47a303d49c2022fcd6f1f71fe9c6	\\xdfbb2d25381b153aaf09847d24ec27f1d4a5b5236601f2690fc41b36ec8c77b701781b9dc7caf251fba287b7ce1e6107707c5131b8ae8ffe4c20558ad2a4bab59eed36b4eeb375d6a44c0bfa82e5996bd9b1970ba3a309046a9542a7e617b29641b1c654f65f7f361d3bf3d7102a9281b6c98999da3473c912719505e466c65a	4	89	1
4	\\x92c798c1c3797c31e08231ee422fb6bed1c2d585ec21a6f82c7dac00518d1965bfe8b67bed75ab6d33765deb2747a522a3de6c4cafc869d22e8fa619eb294d06	\\x6d621dbff6afe7b1795db87c2696d8cddfeea177c9e4e514ce949b1cb69fc3b47b335ac85c9f9d6cf7f5fc8248d24d4b7f793c52cf965cb5e382639eee326986975b1c523d5f1e89aabfed93ee45c8ca9883374a13f84daea2aada219c8fbefa95ff9637b89d3b15308c962b922be4382762c1b93d61559414f8dbb0b5b33389	\\x0acdd58dc8e64d22079eda4708110dc6cd0554928008e03049e4c0ed6e1ff4142e97abf0a6ce31481b4e5f929ba23e2d5b5402d6fc4056df1f64882e21f9df9e	\\x174a6ce4faf48df73f77de723023891720056205d49759e88489941591ada33604343c78ec1a0d57cbae851e04dd3927618b23e09f8f85e8a03be72542d5dc397ef21a02c861086e9989c70fb46bb8d20f94778f145e7fb60ae1720fe98bf83265a6f6361611b4f2661ea232431ac1b845425b2f52b25b9022ef4cf93a5cd33b	5	89	1
5	\\x12a5f782ac82cdf2e99b837b6b123da7a432c2dfc80d116fb2ace077e53e121a40f1c46bf21023c392138fc316f6224908ae623b02206fdb1e51c0696a4ab00b	\\xd2bf4cfea0787e6e10b702eef20ecf2867ab0118af4a9beece13073543ee73478ef02a0575741e6e8db435f9bababa5a92140e5339d07aa60abf67068831aff91ea520af21ab32c25a1d0df8f2b5d4d863cb9c1455d1eba60b368b703cf53ee381c4925018d6e3f7bf88a653fd86df7cc24461adf5ceecdf9e785831964c6f6e	\\xca24d4a3b0cc319559db9694f4c76599488b86285771fe597aabc35c5c74de2c3317c0ff4ad7f7aaad0ce4376a98b43b72552e545034b4daea1be1044bede5ff	\\x3a547a39272bd3f0a05e29cec0660fd08017c6157384ef42d9448bf5f90fe415c3b444e47a576948e328c06637b2c062250d61d0b5ab528dc241e06fa9e05efd2cafd0e68fa5706892133e700748c8bdef6aacfcdc7ec346a0ec7a4491573f046dd3c64af6dc3ef55ae2b4e94a842ecd3c7398a0ef4307a2442ae95ff18414f3	6	89	1
6	\\x2b2cd6f708218548f8a85b5c86993ab2c9b22dffffa43f1077d9ca8b90b36af81385483c759d896ab29f7a5c654df88173097830e025d6bcf29883eb7406b40a	\\xce23a95eb544758897700b4f02b26ef8adc673f8b5d3bb6181764fca87227bccd807477ee4245d6e2b5d4cb43976be84021ee113122a05dd229306a9639708e09be1675646b8a520a82200967b3523b5074c1454b7d3f3f9cf8d4dde08f5e2de8c75892e80e6099bfc76883d24b6a549e1e01375a7f52ebb3f1d77681b39448c	\\x6aa5597810415985c7894d5eef452b267719cef12f66a5f93de1d7c2b0af487f8046a385bdbb7934d4ed27a2ce1a8d3c4c56ef2726c552c3c7c30d79b62a0145	\\x3981962e0d22701fff19d08be1a64a7df3ee141ab3e9972edb72b6d9872ab5dd735610bfb88ecd43847b78a819a557ea2e70bd763789fe8d2c5c6de4cedb7e890b8afeb028c93a55a69636046a3693a8755f430151c7c03599e68ec074b71625b0e9883f4eed2f913cdebab6b3613aa3cd9a9123e2cce3dead9cb5c25fa403f2	7	89	1
7	\\x503fde9e1916aa5c1ad7826b82e746b664fad4a2a23eeb4a93592567f559c97e625f94c3a8154a5ac0615caa3e99c70f13304d73cc155390b4af580fd49a3101	\\xc99eea6add6167add11566fa07a1a21c117387dc659f41d264f574e154100916f25c5b9c4d4fee851cc581e245dc1bf722ad5cdab159b7ea2ff7e796bb94fddba3b3819523d7a856710a8d35eaf03b96ca4acb22e2bae0cdb25018a1b8fbd9ef3b94b37f034607e3166babf5c408bf1189b1cb0f1833bc553e2325eea3b9620a	\\xd069e69fc8ad2c07122e3a69cf7c873f265a3b029604b7dbf7dd113b7a89855cfc6b1353d7833ea2b1ae1e5f0de9e0465ac6a83e1be925b9e4dad3a05aa3c71b	\\x265443b47dcdac5f38d02a0d5c29b27fc28e048a30a798e811395055016026098fe64cda0850f6045ba137e216c950e3a015681ed8666e47e2784756fe70de88d87a98912b7d946d9e5db4ce3b224e3f5e9cbfbe17808afddeeffe82c9b6da57ab99dde1f06399790b6f977a3be67fb224048b0ab396635cc0a8597811b4fe66	8	89	1
8	\\xf835618517c2b07262086390835af3d152375247f66f07258b374453f4aa50268e163bb125785ecf11e6288c0d95d63fc0775da4014d6f523bfe7e0fbeaad608	\\xa0e3d4d46bd320f25d197f3c9913d39efad9c99dc5b35c8de4e0f32f30007931c0781c958d771220a6fc054cea3dff826cd34cdcbef09fe973ba1311743882a2dc1975288814baca13bf4862a6b02465148b91095a33979edd86f0fe110e87493070364c9d64bae41fadd77f84b6beaa0ed180e6c760a314675ca64a9fb35a9c	\\x6f2b4a5cc03eecbb11e362a5cc708275f161ca614a5d231f57e8f893cd40997bafe3853f37332b2efb2bac88f8d8c3ea36de598daa2475ff66f9992033717f8f	\\x3e033600e8dc8c7f9a0cd8410b26e166c9992b9eaf10513748c1c3e73edc0109f93255da877dcf340745d6edad37b1ad7a12e2952afed6790c783a04d6f44d620a87a0786808c333e223c8bd0f5fe4c39795a6029683f0b55930fbd3fd5eb592139c20d5fd99671651b0036d7737413de63fcc24f66a83a1f49273c31b6e5c12	9	89	1
9	\\xfaeeee36c73f9c28240ef7d3b7debb8c65a0634f153cf8775ce1fc90ae52cb6daa0e8302d3baa3cd0ec8aea21f55fae0ea786df0800a77b4dcc8de52fb756a05	\\x17314b53554b6ffc58b51576090cfc40f704e475e6418f4bc54f6749ac1db31e7300d5414b1ecb4ed22cb15333cbbcfc6c33199a26650783f8a1297641f6646c8901ea91dcd449c38e26bd3225815bb0a7804a10d3da00105e8046a75f8767bee656661f2ba060c0478c60b13482d519d640d48043cea1e5064f75480648e622	\\xe452a8c76fef4171d29973b40308e22aab4333b058aab3d5a72bf1e2e1e09f182d2f18a2843a47e19bc3aafc99fd26ac6f375818e7721aa11fb482ad1f5d9d1a	\\x55a07d6ca4ed7edc0e8b0badf62330f60920bd61e68efb1084fa288bd6ac72ffe096bfea0fbd5f4b8787d2970c2b541e486fa21081983e7cd6f3b3432f2baf4daef42d82885d7099ed35397cf050906a44d7048d19da67d87f2c0207575b6b10982f2d09b5a08635ab4ced1cabdc254b2131e894a627822460453ad5a05a64cc	10	99	1
10	\\x79f43ffec22967ba67d8cd8d167e1adff025564c5282455b6d6167e3422610678305e7c3ed958c752f9c1756accb70adea5d19b7fd27b862fb95d9d37d9aed02	\\x40d93cde3dc7a7d48e04e4fa51c52e068c271db7d162df58cd9037a1f6bafb4742353e9e79fea0916f3ca5be4f69ea7b5eccb22893f5a1ab0d648c875cadb3a260c0918aac0d655b8776abf5c7780ac7db7c4e4f1798e9035ca887ec2d8a0d42f51c0b900c863636359e6292e0232e5cabd6e6b8acc65c56d7384f8eeb4747b1	\\x67ae5787caaf2e6331e85a659ae1f12a90c8611e30fc9070c71660bd26751581a441b4c0ba195fce058e6c0224e8727a3143b4eccad73edb3945ee9273584584	\\x8f9348f01ac36ef677b2ba2ecfe3fa7d28ffb5fe875d5029d0ffa0ee770894ea083cc4f57c81335469dc9e5f686d3cc3cda5872cc0b7ac994ed4943e16490a24e9523c9b5a7259786bd37b7c29416092e2907c041dc0b1581db508e6a2d8a136d87c0ba03686b17c637faed3a763e201a9906cb0a66e66c9b6ab24a1f1952b64	11	99	1
11	\\x8e33a95583c8d8733c44e0ada4f8009cdcbf1ebb42f5e03682cd44251f7890c609d2d957ca41c632f78ba7237d4b55cdfe782294f1377a8504f213c6819df00f	\\xa1899dc6050179380fe8cf078bc3d652981cf3ee9fb6fd010f2ed7d5087548e08ac60099531066d64625731d5e17b9789a97b9dfa0084eaddc442d6ff3417f8714d2d4eae851afb9815ce93e5957068929775ba0439ea75b086ca710a952a859f25bc9fc49df60d0e5e781d2972879f7136beace82e018d0fe845d37fcd8f7fd	\\xdde3d959e35f8ac1855a0dff35c22198ead4495e737929c70acbcede5289496b2025344b58fa6ec7380025791d3310856069d7238aaf801c0dc0e7dc08ee455d	\\x95297f7b66517154fb0c217d0c6e7b9ca86f252dfd996e1050f1c70ae330e8175524b70ec1bea4d7cd34127da49159fb3fa059f827d977df52d1fe4497d588d5b24d28feb9c9d995055e7250de21786df8c6be126a294e82adb8f4ad1e284a174984f90364b842d4163d6fdccfbc0827df6784d03eee1555be1bf7ee12348ac3	12	99	1
0	\\x0c3bb7b6a39fe4dfe5449eb8ec207467fea313868dcc03f0d0f4313772db94410a8b2c8d097bca0309db4aa1a31884b9cc7fbe031ea6ac303b977b6f7c18bc02	\\x1a84e6757953015f61c4ce15765cc17e43581bfc98efdc66672edeec523832d8174d9a170cc2b3c3d00851cd872a14d7324489caa7f43e7c06dac5619999bcae9e8d55babe091ea034ef2e0fe9ee6cb61e0d0818b62f054f05606cc7e7d6d36bb9ecd9e41029095c021a0f7f07714ccd9040965cba50c874b26e917c35ff064d	\\x568a76e83ee52b8838822b17b210e7e0157343da812255f870d3faf4a8de7b215a23a2d5008e195d3a00d8cfea7751d2be0790cdb570afeff74e2fa0a51f7cbe	\\x55dad828fa59836847c2fc656aaab6c6344deefecf28b11ab17db576773fe827efe65c2010ca0a13f165f1da903e99b7a07364ab3216b737e164ea34ae4470dafbaa77bd494ede79861e6d132049caa040a3f5a65605b31f51da78227abc8a7b7afb2f1651f2f10ddbcf52a1fe336e1841e2dd9c4808b365864a80de7e0c673f	13	99	2
1	\\x84e70b3646340d351d9b772cac7ac1d91fda787663558c5a8d6b0f2cb207a70837be3cc010a85b2d262a0085aa6daccd4cba6892c958e8c76f035a2d22183308	\\xc29207bbaeb70bfc1e9b5c81029057c7b95ae76b4237a2a5702f44a5d7bf75f089568ed010ee4282d628c6c6f02567a72c6dc58b806f3d0f2ef6906783edad76026c8fbbedd9617856ab337e6724886c23b269f5290c282475304bbed54083b211893d20c4cab7a52fd265ee78f24954e50e14017cbcea55ccb0ae1bf8bf0bb2	\\x84cebb1b3b1c1ad11902b60627725aeefdab0c55e4bb653e20f563daa7fbdc5b80b2b8da420cd5e3e1fb69a297ce3aa3b28f1f5a1e6d120c709f0fdaa39f16bc	\\xc840d9cfd6c773fc0a44af1e2ff8666976f0f3e5d0ce880b981dd1e0ffaf68adb341bbe44a662866aab2b7fe3e9304a6498b4c04b56913377c2718c942c6be2ee0b6eb412f2b7deb2999f44bb8c3cdbe3d00dc652a7c052c24e4f320a6abb72c576c8900958fa70d94ef51091dbd4fc7af5bd09fb2b0aadf987e632ce2becb4b	14	99	2
2	\\x71e7327f6211a9eb3ffc2ef975ad5d08af3f353545c656568ca99e7cd40bd32aab698a5f8429af3f46d89cb0e88f8c556cffc868859ac7c1a25682ec8f654f08	\\x2a44762eb94bba2e53d64d1f1aebfa681c4e088a40cdcf23171ee68889e26e7fd19505e56864684e03f25e64adbe9fd9e8e746e354200ffa4258ebd84fffcd3e0811d7c81267763ecdf14176e1819fea1b3794e749db283871341538fd198c26bd75fbd29e5a767f0755322190f510815c3001522325d24395caf92f50c99786	\\xd8819532a4a8eaafd5257b6e9d4097544c24f27a93d6cec1ee88ecd252604d8835f608738dba67889202a164e26766d96c818c4a225cb9691135d6db64403ee1	\\x785b53b837c0ad99a152a131a5ed3ffb84c1cb7a9ef9638eacdc1fb5ca814766fc3aaeacf3670efa4960a8c2f1bd71143a66b17bebd3dcf21d8aa745d67e6698eabc0c5c6e1bd7ac83e1b2e47e5f1e5dec66be0070ccc33deb4462d26d3adaae28fb820ac30ee8c8d9347ab3e30258223548132d4a3b986b9decbcf9de392b13	15	99	2
3	\\xc55c061587341e1f4eadbfd670f3d343fad553d86d87a924399a93fa5864f77f8df784b5c7c7cbc09576e2c5e31dafc87865ac7dacf9009331724295dbf96c05	\\x4c8bcd70e7c2d18e6a36adb067f818cb5fbb1bd3b17729b4843e91a42fa15983484735794cfa96c493df19d2997ec84eb2b055b9689c5881026b975d4121b2700a93abb6952ba4e9a15a383340ac1f33e2f08da6d61ee4cc40f667714bcd8222bf622cd21a61dc301654e3e4ac32d4e46245ee0f15ea0d33861f0b7a43c7532e	\\xedd00dad4280738bb902e87cdca4328d18dd071c3a7e01d8064343a13fd499f2239eaf7462b953e0244ee37ab38ac4efef7230b16d57b97917f24f041c96fe3e	\\x89a971b3d40f44be5d8d8f01f93429133bc7aeb73b4f42389ea4017fbaeaacac7de98cbbd1b1cd1c9347e55bd7b2210133dace80b5f98d0efc8ec7ebc603f3f8461264ca78438758a94a67ac0837ab4cabf2567db8b60be7baa5328aa9fb111290333c710f479957a4896fe670a5e092e08f245bb05cf13649897ec70dfbba5d	16	99	2
4	\\xafec8c23fbb2a67444e7a33a686e38c77a8a460cac5a0284c6c930eef2048e4ca18809e7f7c41bce0c20649a8c0b46a64d79fec64925d6341bc5f551702ec107	\\x541b032b576e2792f290010506d66a26deb4258e398b2e14cee5dafce8b003abeee75c46452d53cb5057a8bb222225aaf38c72bec0d9bc9c5e6a16c8c2806fec96a03c4ea23f183cef19c856f20f433e0c9312ba1e637d8a8d082001f05d9d3446e3cb339728af62b115c8465381bcd4a83ac4535b2fd32a63d3671f9af0b772	\\xd77d580ccc3ced6cd80f6629dab6ce75fa2a6ed3366fc4775deacf3792d9f0ced2b5235958448a42772b21fd8343f2669fdf7926ed63db44c718111ff61644bf	\\x5e210a935aea23727d0ab13d58fcf2d55f8f105f396857c8d8a2b2f4bf361529b299c5bcec6e912758de1d20323aac25026bd870413faa0708db57aea830e5804305359c38fd1587c3cdcfb02f488e84da0b3d078c5e052f9230e6483314826f59321528e16d8c9783b4ddab417a07ec5f9e069acb7d662bdc1274cc77073458	17	99	2
5	\\xd155160e7d743f8df93e9d21052caa82a68834153faf9095637f72632c39538ef9de27ecabfb49dba5ed1e9ac27e1e73ed12f387b67967287ee08b4e4e07f907	\\x55dc8a2766b08e459e4ea73959f26c6d8ee24369348416cadee693a56eaffdf9f13e9dce09eb2811dce38e6e9df34ad7d05b0453f85000f0a3611ec63299a4bd970adc8a6077fff55e0d9fb0d4bcd4602f3097b2aeea1453ac1af8d0ecb8ce7ad192309086fafa36d43151a0266a434beb46966b12393656ce903ab8ba4e0e8a	\\xac763a7427f41aadb71d3a1d68d168c1fdc3b3df1611a7247e1c8d7c744efb6d82ab9e9fe94d1491a785216365963f2f819f7015ec3e077c1f1c83771ee7b67f	\\xb737981957ca85b399b5d1eee2b0e45db711f06652d9aaf6ef4493e84f3bce68e8ef927bb297befb0777a6d2295f653d9454a5a458124d47a67457609872d67aa8d4f4373b6c5877f1907a66f18420cb5c3f09959aa9d1c5b35d5003957b01a32f6356025eaac4765b3c3f349d43d89018ce470130fa38a83d7ff3d1559c6d01	18	99	2
6	\\xdf2a0a1a8821790f21da4e4efee225efabcc0f709ccfc20c8683e1ce0ab9813e157d630963f182b01ae8df4900b7431e0e7398d9dc4e6f12cd66e5eb54047f09	\\x86828634ebc1124afdcebdeb982ab9aedad00a57651e34fec63ea917c637b22bcbdf0d294df97f22e1f79954482f1177fe1461175a4f60dc9a0821990c1efea0e53e09fc1e7ec421521ab5952cb55c216cd5daa1a62fffd9c6276d418ba3b3964ddc535e9e6e755b444e2561d79cbdd1b3d6c01a10e7de4cff58f31213a51aaa	\\x684df804eece76a0226d843f0f3c65ff6c3d13b1ac767f8001908e8f14a0deaad1064de2575854994fc4f1093251f2b43000bf2ecfcc66d8fc89f9618c74d520	\\x6e5d888c9a8522d3f98bcda61a4436927095d568116fab97ee954432d9de207d554b9a79f7455e2d2e76bf65ddbc0ff35aa0e8d7bd181537399203606ce8e8094aa4a5f11c83747c1a3d326287e298e496d4e05663d2d7762a73908efda3ebe53f2c511cfc027043ef6e132d04a5603626feb75a1261cf384cf6bf4d62c020d8	19	99	2
7	\\x9af0681e7de766af8760502e1c7250dfd2c5ce7adf2bd3ffc2bd027a98c8017c4c96e199c228653906c59c18ad69ccb4789f10391708f2bf889c42ad1433ea0c	\\x77121c3a4f793dff4010186b863c54ad170f4288c612e4ca65bbff13b00f77da2dd816d553793f6eb7c90d2fd49a0b2f4ef58eda304c0b8af67c4a1b79d978dc0ea462c7e7338e93b621b2503b0b4558039d63565b9c49f8b1df728e5c4744b51bd1efb47a5fc130e92c14fd2865a26cc7663f91dd3e574c044996c1a032eced	\\xf465859e1d00aead7f860eac88c063c3b4fa919b666b2315ffb1174590c6ee40cd655c3a6b9b3ea3df7c69e41ec1b4a3ed7835e0a8d1318f9a5e4d4d54247dc8	\\x53a59002a767cf9b53b5a8ec9687319fc025c6c71be287b6d073cbe6c6eee1c20d7a7d62c35dfc7373cc984b721c06f048be9ae63d9243601963db6b76936767094438ce51a6b6a3f59f27acef236346456704492090f544a7435a1342ffb2683ef8757a84477246c1604bfdfb79bf2a411144265b1b62c299631d4f7d4ac53d	20	99	2
8	\\xd04aca4a992c4e05063b33fd9fb6befbb111adc10598505dc8244e9e492b27ddac21793519b8c369978284a0089e53035470ea46f6dce988d1e986bebebd410c	\\x91bb00b620ffd15355bb0e52ccc0c1db5d5a72f0f636ca66eba9369c573cd6d03d07187e338bd237bba576866e72d26da0fcd086ee13f0be7320666a7a666ff0ddcab58e33236df3a20293c7ca7c80cec0ffd4e94c325e8f96c99e61439e23a048b9bdbc81b2948641e99b1e2e31bc69ea92b4d5a1f99736d9222f51fc3b77bf	\\xc0efe7acb56f3dc7805d8ab87543acacb07fb732a5e9426988eb721a528c6baaa9034aac9e7a78ecc17b05f23bd06f734ac11864adab92b387f8eb9d1aac832d	\\x6195ea26f3b06ef64b9a77d6d8df7a076b6dcae3f6ade30e8cb8f7315e6be1e1d88791597fd9b95e2e80dd07820acc491a0848a78361575bf4bc4d04181237d6d9ecc9e801d9693d9ce9fdb570be605ba97ba6e6ee398cef2d408f80a865e8d19ef93a6bc3b6775cb5e27ff542b547b373771ae4cd0c1177750e55f19dd2028d	21	99	2
9	\\x0830844e7e0651ac04134ad54e630567d5802213b4e1f35a269b45ee3a80ddff05a31531faf6116413763133857772a2ba55aa1d5f161f88c8bdabb4461fd40e	\\xc07e2d6bc9199d41a274787cf824287e12e21c198ea62fafac68c17fda881997ae5944beafbc450e614ad9d9c30651ae8a03232b9c78125e69c105dbc3dc0bf21ecb164bac8195e044099f0a2aacd48dfedc17e0e2881bcbc9d27c1a3237adc32bc74ecdefa2c89c7b8d20ac616a4e8465c517a1e68f268c097387ddbdf94c9f	\\x48e052435febb305dc85dd396ec2b7f8de806d1d391bdb7bfdaaa07779f87a8ad2536bd0e02eca35e6f678f110388898de2c6d3fab21e3233499d2186d3e7ef3	\\x2315b2f9d837ef5b6b7832bc6e1553f085a0ef9dbfcf9de6b15a2ebe1615abf74cabd2aa0b789956d229a466163193ee52490516f636590d42e8e2b92c2c887234a6ecca06510b3481b1feb1eac5d38b8b3b6a2192b39158f0b5a15bf978e2013ed28bc795cd314d92161737c80dd5366ff47b494df42b1e3491cb73279b93d5	22	99	2
10	\\xe088a9818d7093ba62255c47363d1d35549ca75c69d90f137e15635c67eb8eaecdae0cc382f9149cf093443dbf2f51af5c429be29b9c1f042a3f32c5c4f94a06	\\x79bfd8a260b655c1f72d30980f6afc80cbdf050ddb3ee262d4b2f65161ef4883ca38ad9d3218826f3e5123137c0101d1ca503e2876ebb917dc5b235b53a0dbf4ecb3a1471a10fc1ef76e2a54a24ccd9a3eae6b590c950e7230776af1f0e366c1d86242d8219baf71ad04440ff5f26d2f4971243a9f7ad3a83414626533a236b3	\\x109188cff81a318012f68152ed3f51b60eb99a66032b1778642cb54afdb1b32e36f41194dd003923d60658cc312a4a9f1620275080d29efe930c77b8193efb17	\\x2fa54046fd5922c3043d8c0ede79e25d4273f5088019d360e577eddf52f845fedddb76beb1e4278816d025fae53a7c58633eddebf9da8e76c1842344ccf45b90b09372eaa823b6b0cb50ffc8ad12abe1a5957a1db08487e1983847b76d3d3113c9f133048b25a58fa9e0165692b257907817f3f9be204783cb571b8a5eebe94e	23	99	2
11	\\xf721ae678acb78c6f1e7452fb95931db27cf571067e8baef27dc375a5207ac90a74f61a3eefa8439e9b7781bc233f5b3a0483be3ea14f4fd2dd54aeb8a982608	\\x5b7682dbe9d13c5b0423f7ec78b8cb57837cf92f414b4ea6ebbced51dfddd59882348fc9322b543cae80a34ac257b8c3f29085de3a831fcd6f6b23365a7009bb4f76a79e09b4442a605d250b0b9a4ae323de443df86223db03a5a036d14ced8c41b5b18e8656381f5115a6e33d26ad8fadc5ce3b06da76e4efbf20b3d1ae0b93	\\xc353514ced6e484c54edd335971694b1b6fb0aed3f5e0f67b5a0180dc3b4713a2265e6f95580677b667445171f7b8b4c0f0f9424d8d30fa07c41db0a302ba54b	\\x9f1aeddfcd0fec88513d40816bcb267059796ff3fe566a6b8392ca33ade7777250532fa9ebb7f200dd575da04a7aef5c19aca4d9190e0c1f03ebc635d07e53ef1148e0c48522838dfae3a9724eca06e6f55f61397f69db5966b224bc7dea089d42d17135e30b9581b5df365988153420e3068303c2cdc71674c2832c3e1e364f	24	99	2
12	\\x96ae0806863d2aadd999a07cc3a0ccfb4983cfd256b9c97e029b5e7a888d540b652dd2f8275669dce46be9646e126b83c98ddc2d00f8eea28cb942c74c1e3b0a	\\x23afa5c8a2ecf7d6681c9426bbce30e8bb4a8ebcd5b2feb09fb3bb9c830d9040f65a4aa16a4214755cb380d086ccde26bd19fbc47152512bd9dd89931a759c2dbc03719b3669602a58b1f4e655e4bc1fb8f6f51621b9aa4192912458d51f13679e0526a378fb96c6c733027b55ea1cf13397c479068d3b6a119a33e0d80dae75	\\xb5265c680bc67278355095c55c4238a98392ee330a9b87c0202d2791f497fd44656960645c277e85174d8d858dd1ece3508f54ab9e90b89fdaf4033b26f66c7f	\\x57f92c59d56c58acd0f8f321494b9c88c9388479abe5ad5b713963c632560117aa4c0ee41ff67b5d8f40cf5aa4efc3329dc5a9403b85cbcbd101cc275aa11bc405ead77a9cf3d7219a89e35402c828cbe0a677edede63ad8aa05c3e0098a0e5fd293333b3240411df70d8fbb99db7bc120fbdc21890cf57b917eb75c0646ad2d	25	99	2
13	\\x2afacbd335336f2ca80f172adc0af1053621f9432577c48fd0789cdce0912aecaefb1620f092590e53cdb16216a4515ebaba0d26632ad442f6fcac8b906f560f	\\x0c28b0f824e452cec6bbf60967a2a6943cc077dd5c36be786233f31d8e6782e9d64f560f61e645f541135968add9507788ccd69759737b1526790dc1cd3351ad9cf01307c42c29aacf5621ee8ac7e2f6b79069617a4c9269a25e7f61af234ce81111d3cb5465246754dd8654d95331b4d7d4b54c5cde4658d8021a1f4baaa2c0	\\xb5235a72d749df0a96584ba8279e34065dfcd81b9ee9b6654cda1bd2076ab749325f12c58e6dcd02add1bba2aed5f17f9c3c4b3bbca8088e3663ab12285a5dcf	\\x3cb2288fc7f7101fb32c6e6be657058d24da00eb808073a8092fe04a7dc56885327c45040199e396419a2c1cfad71024468921ff98044c1ac7176752c216e3865e2a8ce8ba538a9927bb763cdab5f97988fd64c0515f7e107e26b11fbd40dbf1d39d6c91728e57b9bbdbc104cfb6115cf5bf27d7214538f3c72082d40a9dff2f	26	99	2
14	\\xf31432cbcea11a8a400cedd370edd24b02363fb3283f83977bfcb6e931c7843698f15df1ce6fe2c6284efb0319473b76e2721e317c0f7f58cb605414cd7c2006	\\x3d43efb33f95b73b6276a1453ed6c3920a6c2072a7895a932deb9b8b0df49b777aef8ff9395a2b1b8190e32915fec504566e80f240e7664f4cb4c2eaad0fe7823ddad6dc28dbf634f608ea13e7731f3deccd00da30d9b5c66b879a32ba388e835d67afe542055e6a633e3415d62516dabd1813a85d3aca274a3512a9dd6566c1	\\x32df67ffab2a3b67f44cd71cc5e0449f8bc1f9225dbf58d84e0a07a174d0baf19e6899931e16ef85e58e1583ad47802eb4bdae2d1be59dc15bbecf81cefb612e	\\x2ccaaf2bc5c8857123f957a9fa625167d7a4692ba74bba45c2a6c49d0e9e36d73e41d4521536705a5d04fb724ea6cb797e7cc7cf75a0e7ae424d64e78ffd178a7cdb6b8397f8184f83548b8c18c23d9a7f5ab6f6d9ddacc125f670334908213c42c546b04c4a0d0bc1cd4b967dc2cbbea8b0244e07a572b9fb718dd2b64e836f	27	99	2
15	\\x425d98af7f303a36ea72b2ea804694f3113a30592959cfee2cfedf8227ff5071907ec431449cd3155fe64c85a235c384f5a699b92bee117d71787372501ffe01	\\x421fb0c39f4c205b4949a2b6312fa25a04c34af5bc3c5471d7d088d165f5ce869a4c3024a02542801c798a9bca2b132cea552e232d967afa45cc1174e72ac77666d1818e928e00bc2aad218a19d1de8772b47764bc06b6794ff21c39c6cbb2db627a5da3d1f62e873941fd8913c42bcaa6859df62478b78a72e45a06f0394a7b	\\x6861381bd5eee46ca0e5692bff693f0cda0349bd870c237de8c1b13161cd816b53af356307a69e539112572731114e551bc75f0f3adc78c0d913ad6bb797422d	\\x569daebf88a8a9868cacdfa77732b6c756757a0b3c6ea33854cffce20decc93be2b58065931450056517d30c3ddd2a3ba9ebd6d31f9d1e93aeac21a5a9002dd108c7ddcd594dccd6d4f6fc023da04e9f930b17c856e855097135334e38dcbda467c2b772430e4bb67496d9970a0242cf48415a26053a1af73f43c6cde062e9e3	28	99	2
16	\\x31fa24d7c0af1ca266590d94c89a4a271ddff95253e1bc6931535386cb884e3e6e41aafba3e94f958933407a9c6d5866efa417c75a542bd5aa4998194d16c900	\\xb862ec2d17fd9fc6da89477960478ef2ab2955d887e11b22c21f7922c184643d181f7f6ccc5bb4be2cfa8567bfc29486a33c62a83a1b2ef94825ba2843fc123ca2c4dc36f1d68f2efa8a35d58036b3d4330c5a5f0c3f10b8bc0145b8e0dca069e76d489536d2297c573d95691f18063c6f063ac3b14cd3592052ba0a2e702a21	\\x5e0ecb25845210b1bf42d21a1334ba7172d8b27285b30fb162d19dc75bcf0f6b0c8094d4958d35728cd2fd030fb02a34869bb108e6421c44d022453edb973a47	\\xaff778b8096fcba11befc32f8fc0235a742753a3a36b4d2ae412d98b11bac81f88b2e82ae9f53d22ba70a0858af4bba8a51695890afc2d73ea5d0349114a25c00508567562b9460992904458b5a207f86d199c2974f4b02c0b1189259dc6d97037306495735a47a87bb5f52e053c32beb8aa7dc837c630e866f4095211d32e62	29	99	2
17	\\x6c85a208ef5ec7c6b7f2d4378608b7d15cd6e035e1b096828710ec079e8622c75eda06102942dfac8b031021c5f5773f656612d81fd1aca48496144bb118c606	\\x12e72d45e87e0dcdff11a5c41aac7a8a5171d371f7398319a62d61bff49fde680f062a87900fc454b29d92eb82f7bf9cbf3710310af4cda0ca3ca520b0c586053f142e5b9b87ba02b359a64325676f29e8e5069b9c4e00a96b1effbe2d77a82da2e0da176c4a23eb72399f0f3ec56300c99175b753f3867991e96f6fbc36cedf	\\x737b07c2a093eae948f1d8db31f56f509a8188ae526e7a3c9383f701c34437ef7984f6fe59fc2d0276ffdd4a52c3582c19d6773a0cfafc172e79f08689eff248	\\xb6a1db64d2299dc3f3e25b4ac61dd90e28e6485f984e43cb436de61a9c77cd27ffda6fe21d24b0dd9ae54b8dc6c354a601d98c2efd578a3055ec1e596f68b60afb6ac9ec179ef0023e31e3b5a4463e7f9cfa183d1371cd4c602b322ed2ebdf99d7294e484ec5ea3d13e5c138b5cda0fe1351649fb3666f156a09afe2ff9052ce	30	99	2
18	\\x639e2a3eb5b46020648d086d833462f319c399eb8d1993bee64074c64641c42eede7c86150ec316b37a4d3c2d5d9605303c9bb9bdb358a3d4048749f36664803	\\x9bde9730b3a9458bb223a560032c728f5c6518b629b11ce8d08c4bc8c195a097d49b1cccbb8b640e3ebab355399c1b5c67b69ca594410f30782c38f672cdb1814ffbc1890a2f75b8bcb1207ee1781ec0136cdfec1a5da7216f106b904ef71994f6093a43f367e0bfce60814a546c7ecb3ff32db9666b45d2a6c54116d564e647	\\xd68d43cd3f255af8834a747635aca61a47f8709ffaafb8b087e10c3b7951eb2344ba0a535f39192f66b7ef6c64604b32222fa8356bf9a09be70cf74e730fdcbc	\\x5b538520cf4c49e6aa0724ccd51fc256c727fd4e5e6cb6ff4a563b7aa5a39c49851aae849a2cb248c48a0b5a0ec0cf06f2ed7e82a0cd66c22f18eaf1be6f56bb0074fd296cef04c52d918a912f3c50220d7fb7acbfe230627519c85985ffd69f33f47823f828182f22a26c37e9a72aa253e579461d0d8e116acfac089052e1d5	31	99	2
19	\\xc324cddd821d8686c5d78850bfa4c580c407b71f44f3dc894acd6cf585ca1fe51d7290901c571d98d173cafb9556264fbc04f4ab1c1b47d5f07bf32194c69d05	\\x5162f089c06951d549977bed6bcee5cb63c5b33ede8ad8206c9ec4f48eecc7ba3342f51481b6c2ef92e754758f97e92df59389e47bf4ed30efc739b1a9c266de39868adbfc1e591e4b65caa16b88a5abba30f395878346fdba0765a5427d42ffe2febf594ede020bed74d2d3e7b75ff486c4a51464fceb7e7806c828848cebf3	\\x3001f9b5e4ff6e6e275d07d06687eaa9636e12c085f5b84e0bae0579c45bf1d392553c26f5b3dd338e179c4588fac01dc5a5de1af34e7c9aace1633cf4373ea9	\\x88c9dee5fbff841ed32c63b96275a34e1d010b12cc74cff20bfe9855776542c7eee43ae004f25fc564a5094111fc146b091a8b9565dcf443bfd2d777d9e8f1d7ad1e462c9df0f2ad5255622536ab8c58d6a0c13bc29a5560c073d0734de74a3c8ed341db535fe0fc350284d16b848d05bde38b8f0d0e6330e63aa72ecf65de6c	32	99	2
20	\\xca98ffe7486936f735d90ad4c352c0a46676f24e89ef423630a69739ce8e9e6296eb97d47243093ca6cfd2310a2761085bbdb29e2afd626aa5f41163f4a39c07	\\x3efa777c337f615e07b7395b6574583825b04876d9e9b2c4716e5994ffe6d28f84660fc9e93306c2356a0211f9709fe6deeb543bae5e75f5bcf751a9f4641a60177b6cb3d0f15b5af9e4cd144ee8be18eeedc033c639f6c2c434821f016452755ab26c430cec41a847f05ef7f5a23320fb19f2e2f6fe43ac02cd97fb35d7fa6f	\\xf4878dc216ece0d5fa824fca52420db6329a6ee8390285b089859f0ae36cc71655c7b89c1132b605e154b2e7b723e574cb7206342a819206c2983c499e897954	\\x440498394dd457482c5c85ce9833cbb18a997b533be65517608931ca458410ed3a6cb8c7542467083311c805097756fcb13c9611aba6e7cfea76da5ef072d76cbb0561f66309ffa9426d3cdb9f2380bb1ce7f2ed2bfd252ac48b47d241b18f3dc14eb02719807e253f93c54a2aeee62ff8cdc4e56ee1c44a37e110c1a3e1372a	33	99	2
21	\\x906406f49a2908016eb96f0c8f8a2e4ce1b0413bc6c435d9b5a7727857b19ee59c82bd1f2f7584d53d8afb1b4a7106e596effaffa8c76826052b81c807e94e02	\\x0916670bd4bda9307fb140f4cbcc19f1d452cb72874f199e1ccc1450e44ea23a18587a41f360737a7559f77262929db3783167ea6d3e7a5a94eba2957396b582a78434e3ff73fb01beddaf5e166e668564d44755af379fd4c81afd0dcb25270733e02afba7971fd0daf27dd012259d1f2029797ffdf910968de44260e57c76ce	\\x53bae58090a598d1a6dcc686a904a80ddb6fb61aa29aee5b67d4a42481f101510729319b93cf6cfe0e8d8759f00f9cb06519eeb6f3b87538882a0fecb975a560	\\x1f5d8b58c606a05a5aa824751e0ec0be4e6a1df51ee434f0f6009274f104b69ec46a220758fcdd89c8d38799ce37d37e09c5ac84a75512fc749bd475668a9d021ef40d00e43222328ed632b80fed420c619cf430c816c5191973984cb7513ad63c29edf26a56158a22d5d39651ee5aa88a262bd78a9a6f122ddbbcb72dca9461	34	99	2
22	\\xf907ad96226a3c22415cebc267c876d9d3be4a7087a0879111639fc44cd6582bf73ac8a79c8e6798ad99730b9c9d92bb46bf2d78fda7b2a07121453224fe9006	\\x9c9acbd0c5e5c4fec80810c7e04f4726f4c296085d9dc8c404714a0fb8e7234d5b5144e4dd2a838525f4c6eaff18af7c1838f98b983d5c0eeb4d61b824ad8201e240f381d32f7993aa6e23aaad259c20c796967e5893c487e27c6b14b842cb92e45594d27ec42ac0439188c01cf86fbf72232bbaec3340ad4daeb226aac21f87	\\xcf84d32b3ea266714b6b8dfb4978447bfc615beb0e1eb1cd2a20fc503e5489788008686b29bc990630dd4f795482a726e1d0bfb0d8874e0f7d3c58ad5cf01290	\\xa684e09e4b7e20f38e662cf332bf9d1bee32ac620b7689aae5512ed8af6f2cc3310e8f856453815b284c0ca4dad719f8db851a17c94e5256efe9ede1c1502df12c5494e60f684f46e2286f9abbe0b325c5ff352c37735124a7919f6795c7ef7fc06639de868bb6852185600a0d805d8e07982e020f840b55032f54b43bb041af	35	99	2
23	\\x40bb7889b0c9b19c4a45cab851fc8323281b4dc2d2de42d802dfef877e0c0c5430d69a3378f708e1d39e426b3e1e610449ed5ab5034db1b16e9ff4371a073b0f	\\x3ec38a0c52eeb18abb46fef40e8617b6a871fc68154fb33827c08adcd4c2852797141b3423ed0d79fd8bf1e70f2f3c37f96ea621a212ae7a5514cad22a1f1897f23c6d7f098507bf760d18daf2c39c59673cbd39abba51eaed0c838b091b0fde40d0bdf2eb01ce781c01a30165488cd49bb17b52c2d6f6064b87d022da5fc9c7	\\x2e5ca7992e40187880c7770cb68fd87d34f0a84ab744bf7a9499aa28a5ebc49157da0a0727d3a2ba6f01aa08234e0ade4b96cfc46665270c533ac80af3158f58	\\x2f1258d112eace8a45f1b0bda66f6abdbac1c5329386893b61616ffe37d6dd0f9b1a6e0662efa51b919d5796112464081d851c9823d696273963dfa0133a1d0977ca57667ef0a87c3947d5a4a55d2409abb35ec749230327b7502ff4875b35cdfbccbaab1f4c201dac804fcb136bc25d6fde151bea76271504030e2826cade12	36	99	2
24	\\xcede295156773b0e7bd7f20555f2727e507fe4481acdd6c90091a571c6d33cd2e896092c8dc4313b7ee342526342ac065b9196197437e73213c5f6fc4c3e3207	\\x634ac2650ac0e5b4e829f83c1af072f6666f61769b4924de74be930db1552755414fb08546bb36688ef69f9960e16e8e9bb705679809fb9d77b04be94f67f51da6396fa8d7e9dffa6888957e9c80a5c517ac29cb579069b9892b8bdb5487456697e286a06cf59380483805b4ee50107ace5146525281a667d2e27906b3625283	\\x170f4a04b4d049f4be70ed48b3031894ee496df9b4b24b7cc4c1eca28c70c686b9e8f7fd3f0a52c9a39a63382792a2dba1c4d965e5dd9ab9d8b0e244bf3d61c3	\\x1384e96ca322665e611cdefd10b038488624a97066fbdc9cbc94dfbc0a3175d9b75871a758825c6bba9d12b314aac653b133a8d2a747737bcd11d6b7105cba7e2afc5975350ef2a5c821f30889849397bf39a56369c9368ccea97d624e9d479b041ec93f7b70e86773daefb66a666e628bbc064ce57233300f0fa07a558b9eab	37	99	2
25	\\xeb427faa9603c37995e301da72cdefb554d65748fb96990e069d5c1219ae0c11a36173843b45ec5073c14f40918a84e1d413952a58276ed348d372ab75d2d404	\\x8793d7e0e6193064b6175b9bf4aff1a3c5f5d066149c6cf1e5b4ea946c1ab7f17ce58820397e12c9c4cb64b1fe91395cf2e487f1ab1fcef5835176361ac48e47326310112921b8cc1aa85adaaf7b23e8dc8459787150c98e262834b0327752f044c9993b866f32cc242e60fe98d551fdc691e1638d72e00d6372b1a6059e84cc	\\x6e6a546e64df17b1a17b068929a1b6c6d67f19af4a62bcfdf4d7cedb80fb09f7c32ebda97eda0bdbd664a3c126486b4614649110add282682155b6b1319ad090	\\x5169b200fb8173e8cc6fd5652a6153f7b80401149cc506e9e6a7e5aba7894f9f971458eb4c9dccc06efca30d07bcb7ee23e68e90e2f1bc8518fa4dd76941405ab0523d5cb7268525eb6a9f59aaa6662a51e8572ede6a59f4ed39ab04ab8d1cc5b227ba1e10683f914b607539052ea71eb81aaf36132cf6b55e3b5b648925c449	38	99	2
26	\\x1db1ab2bccdeb87e9ad1f5953a751630e72f912fe01716c5243dd7f294127c342f85970bfe95b8c2ae115a7f0763f14e681b5aa0b187088cc7c49f19842a3e08	\\x212515bf752b7a511906270e2fa33698d4a193e0c9cd509659e66bbc6cc70567e192ed9ef785a105772191b4adc9561bf9a9b8df8f745f5e8cc8563c4017bce808420a9d388b597232982113f8a82e806fab7ac527dc7ef783c304ea23b60e3629420c3e6542da752d2bfb08830c4b3d73a195baa3675beb1212b6cff19a8298	\\xfd772b0f0b538701a5b0be2f9b839c503caa5b542cf1b3479500bc3ce353ca59fb0f482f00254ee459e8c9b4bd6fc35068f8542f82d9f3ec77d0a48cfa7d4c7a	\\x6b027302ce7a56496fe14379905368ad5186e1652f1ca0f018abb0464bd124eec7b9c8b08cab8fd94895d8f6a2ce38fbd7b8fe63185aa365407dc0b48be55240ef6851d6ca82efef59de7e286115657d2ccdd09b317d8b67cae71f4c06202147a995000fe9ce5dec799503ceb87b87181c5b2ec2299e20e9500d0eb4319ebed5	39	99	2
27	\\x6da1c1175e23e32917fe437c238008ab6d10e9c6be7002d02bae14f86a1261f87c3bf0e2a50ed0457f015cab257941a5e772ee93741d07685e7c8ab96582410a	\\xcea12c13988dfb635c99c6d27df537853b56a2512d32b5268e548709d2aee41f2633eda6d7779f6bd99661c2d0d8036eb1e93336670e1f15367a41ec93cd9508274e082a3904ba6e99ab7207b4d430e706737d47b319ffd0310114852e87fb99d9af8b4bf7602f87daf7d96e641e1f701bc403d3495809aca91651538b6ed0f4	\\x9a3b69a4de8d2cfab401ed7301a60a095dfc2f2da85e12ae4d36f64f403590f0ae5884eb68d9b86b2aa1c897c38bf7b969593a1e694705092a97af4458056ea5	\\x811d42846be745e8a753a6372fd031fc1d998a4527e7abc7f445ecce15dfa61787614f0e6aceaa45acf72fdb6e313991a029121d525a3d7768186272cde9b90927fb855af437ef1457e687c4dba6bfc0bc1693afc3009868d7701bb60e0c97042183d05e15281110ffafdbe9ede07c380514a89007d1f0e7b589ccb6a592ce6d	40	99	2
28	\\x2328b35ca5352d3a31e9c02a42b1120dab1599f62108019bc4af55f64bb91dd5f9c661975dbe242295b66df0515013f4a6afb57a76fa6d90045b42c90b4f0f08	\\x7bffa5681208bc44e3377f1bcef914ad2509382ab3b00643e477e0baadf88515ff151b1819edc542a688926dca24deccef65d7986f3590a56606eca0e6248ab4c1355f161b76dbe5914d5958b1dac27dc50bc11673267c000a245c83a354fbc62d9f9e916b2326c76cf80c6f96aa2352aa3a4301498a6a49a0f96916e5456cc6	\\x128d9b9c3ed96de696eae68a322bfd70c7f921029dc203bf3be2cc193b872f902073c3abf0131e09f2aa52b76d0d3a466a104ea323502e3fc6ee4065b6f4fa29	\\x8aea1db72c72518fc024aa5e9e2a20225da568df880b4fc65acc08e66d8df5f82d25949b69b563ed1f2d489845edd5e1a7b6160b1ddcb7f92ee157296f854a26f7c7e3274b1921d511621ff964bbff74592595400f860595220b6882efbf0504d2e3d319527df50ae0955c3b5570088ab9df9b6e81c46ae7d63fde1ab4587077	41	99	2
29	\\xf92d32496600008f0d58f91f2324ad4dedb7aa69e67d86729fe553c4083ebfd8a3533e8138c558371c43066087573e58ccfb7986b235b95544aeea27a5fb000b	\\x530446d93a5c540f2bf4bb057fd27032c488658868a318211c0f7f96de132997dc7d03c46872e8cf1a7a9d785dffb4d7007dd794ddcc22fc8b964b0c27ff789f97848f63d5f8ec84f4bfa21775b10989d53299d00ddd32fd404a2d06641fbc3fcdda5f91289fa98ea3687bb03cbbac00fa01a809f6c0fd8de029dcf8230b7aa7	\\x097a04fecd04e07f79ee3341702936d25376e03d885fc9c973e214c626ff7e84283cd30566fa65d961c1ad143eea1e7105855506b43d1898d411353c73caa176	\\x5f0a3e40c8ba2b1de7a1ab56806d78087f0050a50dd2fe73f93f86030a4a17cda36e90223ef36c372976ce71f0ed569e73c3a2c6b2fe7edf44043c76ab23db2fd3abf715f593acda5a1b6855c8d4923cc919a639b9dd7102e7145e777935d1a34a6c6e3179d76316825b90e12f1b67f5bdc7730c57ea23267ae3e17a8dc12b5f	42	99	2
30	\\xedf980f9f993101fd44fa9881ec27a4c97eef2a984ee502d40f42a044d592da31bd40d0e8595a84e035f0e22d22d359aab3e73381daa784a8738099fad911609	\\x5b32d9c8cd4eac2c9c1d675928a44b0c72041c0efb9940c91f62ba2ebf518c0c3c3e56761b44a6ef942e52b8898eab63019fce0658f11bbd86c2e69787d003b016f59825009fcac82a7b7f9327a4feaaf4681e1558dbccea27297ffa9329191969bec206fc7097d1bf90d9bd0c44988d43fdc3b112e1de54828d70a4252ada14	\\xa07173877d94fb97bd33b6638f44edcb8701f8e7438c1fca4ccb22b90d4cfb598bbd0c31ecb6ca45c06bbdb2c0c98876031bd013f6c134220d374d0c3e2b0d7d	\\x1fec82ca7f67d1ae3e16f2e19616562314e0fedefc39235427d6a4c598a639c207f075a6e373de7773fc7c55e3136110d7213903fef7d2ca97822292b0653f74e310f0dce032c2e87ef763e32f7cdac1f2c3ec42e49575d0a0ea21771af4fc0839ddb18ed4342713700f4520f06657f371c2b96875f14b38a10d3e43e2d7c61e	43	99	2
31	\\x253b91e737a2721eb48f8c84d1255fbfabad2444fac89dd618c52c382f8cc5d31925e8ce9d85a33a3cd663d33fa8d9186d87bdb18362d08826ac064675dc760e	\\x14ae16621db7e50273feb90c33299843af998432ab0e637be855e753737962801eed13dcefa0f29ac6c25ae052babd09e1ec3e9df6187d025e71af79738693914d956311e16efbf2902633015032a2f0f225de65f91f88e35076e7e18b5c74fc9d8d52acb5c52911a39a3e20f495cb00c013e698e1f672ebd28712ccfc6c6fe8	\\x610ecb3987c5e8a3a954becca642f963d34e80905a4b87012e60f808acb868200d4daefc4ac5d3e057233c66d6bc30d69e4c330790a70d7a181fc1a6b73ff719	\\x9f3eacbe5561d1308650e4733be38c8330828b4b9eb3f77a525fd3e08500ddda8df388b35ce781f795676737e7e373dc832a154985c7fe9c38326c72664a6dd42ff57b33c200f16bea462eb4262a28b01496f589b537c24a26da9ea914c242e97a357988e7cf0eaaf4be762d686d1ab3cb84945f124dea6f36573919ef00c7a2	44	99	2
32	\\x18cbedf0c87eefa63c141ff37cd8423f39c9c72360bd8dc01669573173fac760ff26f10c832cdc7ff25915069836f687c975c93a24500eb4021b8555bfc49501	\\xbf42c8230c607814b2c2c03399bbdf0187cbd9442e4f92d1fcc0fb4977280491dfd2bf7d7e770d44da04ee82fb0fba1d93e02b5f91e2190ffdf3371770f22c9d505ca246cb70cfb10d1d7ddb8ff2f563e31d2b31b5bee3701c0e49326dbaa6813459aa0b925c82ce3a5774cc6ef8125f74a91b642add2320c917b5ac3da702c1	\\x5be7d44e58a9b824fb83512fd03be999adb04e8c9f49d71cae586daa095cd39cbe707540538288d004193f4295a663de9ff9880bd699d867e58af81cf08de616	\\x3372281fb00198d68d4ecb5a25f822f661f8a1a4f5a60f1edafabd798edf56ed2ac5118549e5d551cd8ddbbafb3248f9a242a2b4337567c0c26bb1b842d29bf46acfc7df89b69e2bbfdbef8ed74d23d4992a4e63a070eb847628d0addb0ff4f075f7e804d28f59982c028b72ce92e140c80a00578b4fb30fa74403f545a050de	45	99	2
33	\\x022d127ec4717c3850641380562143ca2fafb3d0e6e67901d3982e3f4f91d3335088d49306d7587cf902328b58acb476143ee071455fb0c18d684d0c01202004	\\xa51abfdab00851904f6911b82e9b847d7c57c80e687d1c90aa0bc7c34827c6ad2bedebb0f5a475efaa03ef59507924d527929c0005da38dcc5df06d8a1f705a227fdfe10f39a733c80b462b46ef75072d4d679f12331ac831b5a3689bcaba62444310685ffa88efee61402be229473882068677eba8ee8708c5ec791205b46b9	\\x249bfab8189dc69f1315c11d9d6818fbc6dc40ca989c371c376f30e60a94c7be7f1921c79d3ed0449a8f1263d7ba243c9ec9cd708ee90a1b44b6337bf35f6d59	\\xb57d946dc55de2ef91f7255ced7a1e6a5a208270ce7bc556c58a30b3164eff39421d3fef51e3cea78ca45b20fbb4c0b0428a003e4744cbc8f480573f91fad67d898cc8be87db7a7efcb1979247dd86ee5e4acaaf359071bee32efc32c3cab6c8fd6a3c71b55776b5b47fba5712d88d0932b7014b1160729f6b8a3bdc4d81e696	46	99	2
34	\\x5e4e57a6addb342491c0e904c61f47d428e3e6a2bec6337ecbf33ac971edbd6e6830335caaee15f928a0007804410c7f09c91d6effd9a0821156ebd6f91b4407	\\x748f777ce25c785102170751919c8f570a1a49e2e3d85609d38430a2e5af7e846ca7934cf90d169c215a7e18305cd8e527212d035190ed11c733c4b02694c7e1ce6774e972f4c7ccb826d3d3ba35651fd695a7f7319d80c51ed18d5424856c1d82c06f0b7fcdcf5c065b9d4c8c02bbe2dcabe4c959b30f4258f9904bd3b22681	\\xc6e2db2dc907d6ee7e3c8a1120a03874d1f5d07e39387bd51ba8442d750e81db617561c265347a6ef5d2587f112772287d17aaf2b7adcbb99199901d5518a29d	\\x77ffce2365664da4356344a4871d73eaf24935def72aaa52dabf7cd4f04fbabdd6a6022ac25f08932b0e3ba872f28181b4bbc05ce5da4f3aef70718524eac6011480c041a7d5a3fba2ea69f09ea419616f8cdc8b5dbe6ae84e492c2ae6d41636f0bacdb92d4cea6948864f784daa6aa1b5c9963add4f4b4c48b9f6e3e1793352	47	99	2
35	\\xc31f9dd148a8be6ca963f0ec66bac38ea3cb9810950c08fa0dd2ec56fc0053bbe930d48abbbbd73800bcb9ce6da64aa4a34ef97b40628a9ae584193e5b9e0407	\\xb29a9af8a325bd5327fee3ec0ffe507696936e6b3eb24c8ea94d5d8dfa54856b9a531d8c583aef0a92faa15681e25e26646cb70c49bf626343269e8a0744cd7cd61aa9a7917e18ef081e42aa02d1b16291d99a9a9c41c8d54361d7aa85a879dc6f1e64e458ec73ef25b0f5cc4a4429205164fa2856e5df990ff1c53c55b124b0	\\x1c2fd421a941bd6c5a66d7f5854d10338160ae5c6b8922bb581e900dce0441d69e2abbd8cfb1a6a6ea8b1bbbd63e5c7c7a60bc5019a281e86f8c791822dada24	\\x4926978edbe4d5c7d61c2cc7d7c04d29ef3ae8f3bd2d4b6193275445db0547fefbe33f2afc9ce0ac6a07bee2a63cd76b69621ab88a5c882ffecc6a99157b431b4c64357ba4f2bc24220f35ab85ea7870e35fa2643dc4582b76aaf13aefbe2b8fed80d30d4709a1ae88f16a2e0ce5c9d0c361972024f5e3a16072d0f9010f1031	48	99	2
36	\\x33871cd64befdad5c8bb5c6615834b8e5edf40524cbfc4215f42c6eab5cf76a511d5b8ccc86c1690847f657322a2a876fddab578ce5012d7fbd036bf72b04006	\\xbae85120d3091d1f5c25806795b14dc026729d93e0a07d968d4d9917373569c31b0fb6dbfbe6922b3735728fcf3174fa061156a122e79196e0e85a1a97d2911f8dfe947179ee99ec0d89a170c1668cb64fc6fb4f9dc5ad4a035b0734543cf2642c9d052a1eae63607d03a184421acf66d763c797b17c4dda6e6e503cc1de599a	\\x3c385a30d32a91bef1ce0ea8825cfea882dfc3bd87ef552cdf7c924900ebd17fb4e1f7c57878c3cc179f584c162d4552739750f0833498df5ac27b01253f47e7	\\x065187836d334558b68938e852521976da76d1963eecc10eb2c62c55ee2ee80dbc93dbf2a12db1d29a2d9157475b32ceacd5b464ad26652ac7f3f1c31d0913fbad8f00462e8a095aa0745c5b3bc375ead509f6a8d0ba71e8066b5222938024f1872b6247d37e1a3a9adb6adf6cbc1fe1ec6292ce1d170dba252a8c47a0fd443e	49	99	2
37	\\xce51ac40376ca11b7399f30bb2d3b904c4a2c184c9a6434aaae70362d1cc2073fb856383752087d0771e828f09caf975a6ecc243220c4bd2bd1741194edfcd0f	\\x3ddec43d75b05a082ad6ae414cb5f818ade7000aa0ad4a1cd1368306e2042adf503a5190dfc7b068141e761d889df7c6cdc6100450212a06820117e7034b17c7cec60de96ff9702d13d09518beaa626d15d635971484b0183129eea3260608eece6e2bcfbd8fb2d00a1077430bac1503c8b30e73d0420f2a07531232895c17c6	\\x2b41e92d11494f55885835058ff7abd41a788d3fee3186acc6cf1af5b8f75f3456d396b59c7ed106bfd1f8ff22b6919901a5f4506df54e2ffba88437c521d000	\\xa2ba508c556965fff1554b9f02690f7d7fa87f1ea39f661824788f8a375d6ced7628576665180b8e4937e40ffec487c2751ac7e649d4303261ece00897e6fbd430dda2ed4d349a099cb4f75fe896cac53bf641eda1b2ff67c9fcad548fee3dca08dbea635fb804c61fcd9edcde20864c81843708d11571da733e36436470d58c	50	99	2
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (transfer_pub, transfer_privs, rtc_serial, melt_serial_id) FROM stdin;
\\x3510b0cd127bd926a0e78f2a65bfadeef66a91d193bd7f6e0193dc063801520e	\\xd078f2e9808a738073284b3fa8f6e0026baed6084b879fc8c8f144e3ae01995a105dc061094aebc5bba473abdef4206e1abe5d24355a1562039227ca36f729ff	1	1
\\x1c068485e155de486e048d251cf4fc22b4ceb343866eb10b12d3c64e9b086e7a	\\x21275e5cf43757015866f4719989b73e4d39f8c13464c52f1b3b127f1bdb946b9f2ec3d42018e5cdc7bfb8b0558169ce718b79e21d619317719b396793389de0	2	2
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, deposit_serial_id) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x759aec7d6e7a92afe3e8dbbfdc9cf7cd345870fe6dfa4b2407f9d47a46414e15	payto://x-taler-bank/localhost/testuser-e5NQTk6s	0	0	1633269117000000	1851601919000000	1
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
1	2	8	0	payto://x-taler-bank/localhost/testuser-e5NQTk6s	exchange-account-1	1630849903000000	1
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\x8b6df44208ee0a2531f9e6ef942c29d71578fc97e58bb184305e7f635fcd9ac8ecabbc65f4b91af6b1b50716a5509de6b4e318e89c632b22bd610c1c29ef89b8	\\x4d1f88927bad93f13eee8b7df4b9fe268a6a1a3d353c537ea0453d2e7d104bdc55fee35777ff491d275fa324039fc0b7346b667ee225b26a2803bbb8c34de753b944959757e92669d9a0c7deb80bb1b0457caa86fb72ac81abe6ff6f722d48a3953ff6bb629632d92e5e110b65a4ec021a19b521aa1f6d1206bb2ce3fc897ec0	\\x20264218816a64c996a4a1d1c781ec3cdb6d4064eef987331b2643d342b75446803e8036ca250f1f48417e2bf215ce6af55757c1760b67668462603b5e6bd10e	1630849906000000	5	1000000	1	8
2	\\xb7aa8e4e3553809b6e41fcca9e08954d8d23f717cfd96eefdbbb96f1461f7ebe133c4198aa42185be0722443e3771616fabaf15d727c346a749231721f6851a0	\\x736e2e4725286dc66a8aba647e7abd592a1adbe51875ee36503368e8f37086a16adbbc74c27a2cfc22e2e4e62dc1bf8115f19401a4ea12bc1a459180fa28507f8a87ea9193743c3b84375a39222882ea16e85517980c46c658ce449fcdf07eeca52fc7fa6caa90bbb665603fc44750a24f8182ed23ba1f97bd1c7e28ad73b2ce	\\x1b87494653055d456b8c1dd2634d71b04f36f1319b578f338ca853d25ff78a63f7daec78c2c802282a5c23494fe0ad22880867d2c8875a27a8648d993ef88c05	1630849906000000	2	3000000	1	247
3	\\x5b3541409f32ccddb71808e99b67becb666848f0d883d3b7c0a90d972fbfaf124400446b5eb30d0e3b8cd792ac34c0cea572dc9668f3c279a62600838ddd82b8	\\x56d964d453803c7a55e97d9cd3af6c16db253b03fd8972f289111ea832b21f9a7a262826146fbc41dec13e5b153e05ae252e95bf47808afacf6d19bb815a17c9904bfa00511e4b64d0af38c4daa517e1fb06a5e3a4030e9fc51e5d334218cc383d259560f1b67a783be6b143442c77ef682bb4574c83c52c880584a62f4879cd	\\xa3daf512c638aab2ba47125eb16ebbb31d36fbe365b18ad4dc25a7cec16ea72dd12c54fd004c22b207565f9a355dc65b90c9ba548914c0981477f097447e240b	1630849906000000	0	11000000	1	240
4	\\x683d212d8932aab73778d09a208db13a766ce3b857d6a6f00a731a47a573313f438a713a7714974e2974cda6425654319dd6d6779e72da2d729bffd3764357c4	\\xdc60da993511d7e69849a82d505aa0e0d5259fa8eabf4ea5cae8ece58584854092bbaa6eeb1c46dd5d3734442ff0c758c580cfa5372ae4da7c71d07af2b97b095859cbfac4c33716f10d94e4b38cd10a42a73e013b981aff44e51cf7615a76b70aca72e92aa19e8b3be3eb72f2afea3a672196efe323c38cf13792889b004cbe	\\xadb8efcd51be453780d44c1637429621c9705f1b2d87de0dbac29cc606de9aa2f96b9a02a2dcf06cef35d89c99ff7666595f27a36c18057a237011023a3d9f07	1630849906000000	0	11000000	1	240
5	\\xc520e1d40639d089ed0050341cef36a652514fef68d7a02242063be525dc3298d15211ca8c2691cec2e0649ccd2949b99ac5735187859c81f6d6e4be2236be1c	\\xa6a145e4fdd96435492c2fb09ef634ed5ef3e50412a664858cba43cb8a72df661563a2ef360fc4d91809716312ba071d432d31d9e9e4a81e0513440dd955362259746048545a1862f50641020462f4a05e3cd682d4f510ad2673739c49ee97b491a7fbec696db3e3cd7479b24757b4df3ed9133a60f6f0f9d91529b7798a52c2	\\x7dc1cd999905e7eef9323a2b797f76abe362cadb072f88b2d82f15f2be1e045d8ea375e99891ce0dad006ff305d11043024de93c744dc4451f262f3cab922d00	1630849906000000	0	11000000	1	240
6	\\x3c832765b5be6e2c433c26139140dcf122af7783853c2dff4be6e5a27ba521d9c7e1af412def695f7829f3b86a947b94cb8f96b2f03ee02a042deca480204d32	\\x5c9f8e14bc727604fa5f8f6295c263dbc44c8dddd9973ca71c9ce66c7c3282068a6ce9f185923c081d2427a6da10b8630eaad35bb2b93651eccce71639db063d59a1ee713302a98a1530ee2f5fdc033c28c6964c6f578b165e5abab7774c8d086ee686171b537dee0317674f762cca30af6bafd64f47e42f0c7578b64b7ef1ce	\\x264bb8d90d2b8a2ea1b685be26964ca897f66ae5b3b90bc0b455414dcc2ba5a67a6bae8162431b136492eb198679267c53a9c2aefbfbeadc8941f07f4a268306	1630849906000000	0	11000000	1	240
7	\\x5cb3ae67c5a44a77972e3eb279a5dc84ad7cd9a61adb2535069f314f64b1130b56a6a46f3135914dab303c1a74a2acfca414ca1f3a4ba8f5d7c4569067ca0bbe	\\x178490f31e8f71c8b842f4cc1ee0654aa9e4360745ac0dec55186c1f6eb4edd0a89b5413ac31ddc1271f88506233ab6b55c802d6b91d9de00199c5487709cf697ac0dca73a903ebb25c49a5f34a838dd5a2dca8ef45814fdbdcdf3ccb8085d46daee36866175089103c885bf1dfc1eb32ee94c70b0520d70380cadbeec65c1ce	\\xec7e89be563494facd18429a817a67d8cb45b4219d426fd014bc474c6d1caea38e8ced92a482ec9707714a2b3562e9d5fa4c66575a1da7b9f602ff7245c27c0b	1630849907000000	0	11000000	1	240
8	\\xb17a9cd763b369cfac2e6dfeb1634c753aa32f1f1e1803cbe4ec6fe2e080c132725bfe641ff6483fa847a017cb3af3942f1d67865316278c19751d64c6abddf3	\\x9e9c8bbc0f89f778f34241f0841eaf44d2ac586c37de22abe9ff67d1d6ff1ec75ac8c95e43deb51da8fc43897a2283dbcf124b117b9999c1b214d686238f180449d51ca2af3bb388f3f357258ff18da512898dff1174ca5d270c51eee9583341ed0c272773b092aeb1630f1a647cad5bc8c2c94d871c305fd7e4a7be576c1358	\\xb9e7a8e37dafea6cfeff7c82f69602132f7e0e7af0fc498062b6da209bd1f36ecc68afaa90c3928e2161fa865e15a452dd6db86c17250c8788e1e3e3d52d9a04	1630849907000000	0	11000000	1	240
9	\\xd52a31f4e887dbc28fd1e3466a6a32d285d93b3fabd3b756dd4b876b8cbe97152932931ed082ae137826906ef3a93a5ad7b83a0615e12229467a635afcab378d	\\xcc76bd9c50c9e3c5b86dff6d1e01755e2e56cc7788737e506f124c43ac571f77fed589e741e59d74b77e2f16103a98719f73a5e4a57751ad93b321bb7726427356ed6eeffa6781d40188fa67e3b633be25f840446b4428a82632c4ad79b1270a7784d7d52e500ecd1b1981e2569cceb2182e616f3bf10763e0da26b8a0caf732	\\xac7ae148974ba45445545db8748f1f4ffeb86d4aacf2ad31dcf3810746d2ef97ca81ff6d661cc13f580fc507b48c6159856f4888236dba68596e24e869a32a05	1630849907000000	0	11000000	1	240
10	\\xd08824c061b5c4864ce80918f5598d0abb1a064f62d33f397d86606f852f485fc57fc881912f21a991a3c7e8de2ff4604f66bffc66eadcd5749f986143715a03	\\x322ccff6366558d4379f5c3fb2574bb603375bf4cb5f496ed3792740c255cd791849895c2728683bd135fe48c81a39c987f71be65bffad06414d5c2d4c1171de51944abde9bdd035fbc4f66d6089c129da5e451c95350a8806ddf8a55b8141971f1b0bc7fa9882dc53daf33f7109f630b326a700c38816b72567215731e21c5b	\\xc7561f3388282f2995d9e9386f0d18722c80e216898c6fed21304aaf4062a6cae5468df2f503b9eb0d950f7708e1a60c98dc4c56c94b2a1504d4646136be9206	1630849907000000	0	11000000	1	240
11	\\x668eadded52bee223db41142b0b06454dea6a8e73d39e0e5eca265c54d27d3d03836de2b69121e00c0ced4e441aae5472de5d31dfcf6fd230b5b1ad3e705f266	\\x6ad0d0c90a7d75a3a05809bac1d4a9cadeb435ec1819875b400561c12ebc2a5466ad865159889d80996947b3c057a2ffb8207b9c143d19a179d37ad0fa68ae6e4479c73b2c75376e5aa28de57291de2ed8bb3d62a753e8403ecb2f909cf6c9f5b0c08303798d952316576efb063c09eb86431a3e8696da7e75bd76c5b8eda858	\\x14f822dd8abe43708029332ce383db652f03fec6f7dbbf6eba37564b60234f39566e0433e59e131c7809a1501b710bff65dfc2a60471c2a513855d173b0a8f02	1630849907000000	0	2000000	1	172
12	\\x6f093a34555cf01cd4dd891b773466010a2f09363fe27e1cc6684f4cdee1d8e87c536bfe4a41789d38199406497c62a3419087f2e1b73822462e754c366fb044	\\x690e1408b79dc00b7ea425c0a48e33d1aea41b5323478ce916d63f93eac109d944c501694fd441f75a4c9f15cae1fb794e7ddc1317585c062267a77956904e4a8f1c41a5b6780a8ad639e89bacbba09117a7b35bda73f6a0e9e1f0a040a00b853d7ab03544b1cfcf06377fba04c3a5c593cdbf6de49932e41548e2bf57d0b158	\\x00fffbae415d0190509ef1f56d40034da2aeb72720531c1a2114337aef0a311d32652c4c87f47d6e19a54f8bf9a75fb09478a7e21022b0f085a1cad90e9f3807	1630849907000000	0	2000000	1	172
13	\\x5683eb2b366e0f666da988eccdcd3254ad2848dbc2ee79eec61e0e22d580f7a1a22be996a8e03f5818d8f1f12668320818c9e3b64aea2a4b20e0c07f5c47a511	\\x7699f948250de1383a268573cb18795d9be401e4b0e96e85de552863bc957308552d2d151ac625022bc40b398592a480fa1c0b3be23e00868e4e2948eb566fcdeb0688cb6a3b4cf453cd7359af39f1e43c15cb125c5e88248d3d27449caa2d2c96596cb802a63d2999e3cba776c2e7b9cd74cea97001a394040e58ff3df62f93	\\xd7fc442620a023afbff8b8a6bd5cb25a7d63b6c8689b9590d28b2a87031c7f41dff6e5d932fcdc6942714ad8b930e620c5d22c03046efbd8b552b9ea2aa22603	1630849907000000	0	2000000	1	172
14	\\x52a4fb76d2c39ec47efb710bd559e462584cace698bb642f7ab5901533dc51deff507b2e6d31eb5d1ae2503a8d9e8f2bc301230356e6fad14b4d6b82707d7eeb	\\xb3573329356c95385ea157d2135a84d3b9467932d35a4b9df85ebbab95ab94b80ee66dacae34072aca9ea868f72ac24d5899c69d76b1b8c8b88e3696f876bf20e2098b51a8ecc39b9cc6065b3cb4fd2da85471a5699977f378fd23fcd6192819ba43f30f8d84a720e83fd993c7f2d42117ca272b9f406cee31427f9938707504	\\x8615be5c40f944814ece5d46fd51cf4f389a730e8bde53e432e0bea89a3c86c6fe27f28c78becedd07c92077234277611b2008d2cba46eb0cb17dea554b43101	1630849907000000	0	2000000	1	172
15	\\xe59b4c01ef880f279c1ec8e91517132c60f9fd789f6dad45347358581f351b68c191e1c0d414c7813dd66f6e12047035610c0d2842f6c89e22c0ea2a120d958a	\\x1bdef75484c054025491dad62e1af7ea79c38e97787b505e31b2c80e9d4289e1dd093705f811b4e955765918ee3adf2ebe3e066910c42c81039ab20d5a6daeeb80cf3ff7e5a9c485177712c85d4804a87ec77c4216d4b529eff8ca784a8d9a7bc772c7b77006a467d990ae598253ff4932f19b2d4ec0de422b257e09f646801e	\\xeca7d0ec52969274cd627ce7521b89ad816d4d9e5f15ba7c06cdc485279932fcbaeaf4d4e6f250b04a8f6f70feb9fc5c5529fbc6deba5f3801a9a29a4ec72909	1630849918000000	1	2000000	1	96
16	\\x255f464a9054c03875f0e47aa46e4d95c63d2a9bd0499c95d63ce1e3717713c433a961104cf564b91dc7942e7ffd61c88e8c7ddbd462f79e219be86a9d683527	\\xd415c51c497c1b5139403ef91690fde33178e58ca5ae4203f980ea828726f91368c27d9d6a08442b3baae2a9ae36233d40f5307fa71e0065bffd837f1f792343f266ced7476a49fdc2e84acf5342770beebc0b7a67c40670349827319d0c0ca6aac8a728ab517841af07de63ced493712bba25a1293605a7c18195ee6856cc97	\\x1092bccc5d8a5acaaca5dff57e8724d3332f9c483ac4c2e11118baa57cd16610909024ecaa3e6f83847c9f08c3294791ace0c3730c149e1cbd20ae9b0746770e	1630849918000000	0	11000000	1	240
17	\\x502eb1203dd2d37699cb573e6483d84e38c86a2b177d76a0408e64d9f706ab01228d6542506ea21c31d815c8e083bd0447a72053ebeaf3bd59d8aa3ecf269e03	\\xcd58f32cdda349846d713472148efaa34f7b137aef8361aa2b5c421811144e30930542db897977f09191b2655c9f1a0f52df3dd479d535de137f9dfe0788902e32d55be547d0fc5a8aac0dd6f1f64291c2316106260c9cfea6222bed130f853f1ad68369e29122966bfa833cc21be7b54d54858b75b60f713d8e9522b04f2f9f	\\xf8c9dee0085fa90dbe8115b840a00c50af5e2e14cdc7b6997668df872cd7775fce2b06f61e4cf3231844a8252438f597aaf8bdfa0ecd6dbc7c61e76f1a392006	1630849918000000	0	11000000	1	240
18	\\x037f105d4f10e68ee20475a41f6083c9ae9277468b2da99970e6676f9a1b70030c7271db4457e4fd0944116c52b130f1ac83f64281c3ec88e5769526fc096676	\\x15e0d30c42fbd894cf13b72a0f8e0b74ca7ff818938c4ae6d53d7818625eedb9232aaeda10c1e51bba5685d1efa391f525784bbd67dbf1b09e381a3ed2690f834b9a7f9251ac0b02097ab72118b071d92c6eed09ee5cfb13bfad16f0ad87558225a0fbc267425d394f94427f6495f11b7f1592daeec524b05afc60f0ff5f1308	\\xe7492f5bf4b1141aeacf3cc19ddca6d1b3dd1d102ea9a79cb132cd7a2b448ef9d29f8c96f04a3d98e78cb7122f1cd831fb68d6a4ff6d54b00afb660539470c06	1630849918000000	0	11000000	1	240
19	\\x1d939528190557ae89809e0844c59ff330fb67deec289d5a1f8b0cc17a9bb8ec2bd00df95a2a1c3ce5bb0d8d0e6fb33f1832fef767df466bd452f893103a7e04	\\x1a7bddde9a91f7ffabd1918317c7e3e02a09dd5931bee3b2ee965983fff84df5b16e23c0f18e0c380c58822ca9623699a3378217f0dd209201867b9e70ad4dd03d3201ed61b47f87097c37d1546eb1b5208b355f4745dca1ebe338838311776a3946a81c531554ab8ed356b8da69bde08eb52f0e33bc5b24c46f0e55e714abd4	\\x19b54d0f56af725e295438001b3d8e16188de92af0393b596b048c8aab9964d364eca00672387cf44b591644c3f3ac0a88c222b2b1c9b6cdbd8982803bb62704	1630849918000000	0	11000000	1	240
20	\\x87233e2b41772465047ba730cf6bc19fe23dc5c64745340123281ee3e0eb1f7bbd2ebe2b6fd77d27b119b5e04c9f0ed669486d745840ccdd2d54735b0a0fc999	\\x5c2f7eb5fb7c4a2c14c1616469b37bc109cf6ae40830cb0c24cc6cae9d5296c68ca97483b7418e0f2a600320c0e399017f132805209039088f2344ccd38b32caed6b8d9aaa567b31e778f3ef2260338f7012635cf5497003f03467bc18c6cb4ef1d227201724815c9c42307e27646b81131d728e4a0058af874b679c517ede15	\\x0408a07b45f1ba6ecf2181f51b2b26a87fa498a449e0ee62025011c5af780b945d4ee7303d03bc5ec836cb618ca188692c08c2c271aa54aae4deea74dc8d7c07	1630849918000000	0	11000000	1	240
21	\\x563b5a69f9ae9c44ce2fdf6cc2e78dec8eceecabfc31ec0b71bcee81f41f14357f5d84af122b5a4c232f19a113fda7ae743dc7d15242a365ad799f44ecbda895	\\xe850e47b6f9449144fda12d1c899f462eb09e22c4e91a8a2973cd401dd911b2cae1242b548c6352b4b6020c706e4cc76e6af512f9218c156eaca162f744cc3be88380b93742cb5d8459c03c5b602f632b4e791af5ff2ae4065205b31d09f27d56c584217f309186bc29cbd9ba6bc5820294f046203dc2dc3d8e612beb4a95ad5	\\x8f9e7ba7b4722b67d87ee84a30b03a625e351a6b02e7b64c8ef5e186875dc8e7f120524093427f15b965ca2636925827ef6d247c29e16a836761ad3cf806e600	1630849919000000	0	11000000	1	240
22	\\x03320815db76b8df5903250441a7fb71727d913d01e3cc68264facf3a21aa05b1e6690da166b5f5259808bb3a6057164147456483cadce9f72e8576679482d1a	\\x9ec796a150df968508c2b8b341649098e40862b3f2ec83eabc226dbe08807978883e03300db0ecf14d02486310e51fd16f0ae2c7679eed09a7232cd3ff609490e5f5b84e0b4db2f7a623d418c66c310b81436e54edd5cc24d99e7bb29d25540628083bbca0f92fc2b5bdcf26dac7c0a282fdd187000905916629b4bb63fb1158	\\x6bda5a45968efdc88c5b49bf20f1000fecb853ecfc6d39140b35ba4d91ae0c99573b8b289a0a3ee5e3b860fef2665ddc32d2f47d1de861971a1601290fcfe705	1630849919000000	0	11000000	1	240
23	\\x179bcc4fabecaa964cadf94dac228432702a4071f1ffd3ba15af24dfb95f29b52cf3af1e0d03237223898b544c34d483d65b7e8dfd56e5a22886912706f27e98	\\x57ec48950956ecce09b6c03a2b70cc86f27b21b681dd4c73f3057ceca2b74f7e7db1076eea06c0b619c19153d8a3e6f44d5ad16423d6e23c557e2874726ad7f9ce73b4a229440b79553ae3c3d832dcfcf936d35d9a8fef43269f27d82d1ee73ed4b9b3d4aa9695f44cb1d9f8c3ee6480245246dc2d6a1b6b232d5615277fb3b1	\\x1033fb69eb230d74020587e3bfd67fc86c3b2318e47c176fe98e4b8d3296b0e17e96ef93de1a74efc02951672a60aa4666fdca13c5f935af7d1bb79ef9621606	1630849919000000	0	11000000	1	240
24	\\xe364eba2f2db0a7576db8e3b2f7ac5929b26e05d006c6182bdf38c1019c9d889cde584c0d9a40506d62e157b8ff50bb19335ef1691c2a0138ff6a8472c6b90b4	\\x2f31f50faca631cbfb7d9f89895423879b49d8ccd41ac3581e75892d4a7ae25ac2318e165ee7183970d9ee91cddd632a07774e9351e82ec15720193baa39bc49d298d13336d6210f7697d8832ecc363938c722214ba3a6edd8a9087eec7f8a2862d249d22755428916d0a00d8b9ca336c8f4bb7eead04f2ca325f49278409c55	\\x439ae169c76da155775f48c5a2dff84bb3bb1e909554cc44a9dc5e116c8c2c3440c19866002bdf56bd7a8cbb452e61f3ae12ad1b45732af598e94afe2220980a	1630849919000000	0	2000000	1	172
25	\\x18b8c779fa2d999116a287cb0c127c5b6145a4d1927d1d96b9b2b4bcbb132f39bbe399df2126cc2ad35b4f5fe8a9a21680d81d527f55f204893457f4503eefe5	\\x05ea56a67cf5172b08c04e76a8644eb5c9b5ee51ea0835eaa12af67346d6673b791141d89e4e6110e4f5be1d3ac3c131f5c6dd5e5b7458b9821e97ef6cf9946e4cca777c1f94a75597ab3a4dc359fcbeffb45eddb5058a3ef7896defcea620a2a6f86b0f4a87fc72bfdf295096d94032a31e067f645bb29a1f1aa91ce3163da4	\\xe4f96594539f895952d84af3c582e6dd7420d41223ff3f7e09bbdea1b21e73bd145cf42c193d540681015350e589081bfbc11892e1ed0f8926f3cfa54c049f04	1630849919000000	0	2000000	1	172
26	\\x94eb0ce8868f350c650eaad54fae942ad6a52bc1febd548d7502147f1d24af7680e8ec897065835e51e0475cd696c1469905e7153368fc9e907b1c6be738f69e	\\xa97f1abad55165169ab8eff6fbce7cff4355d7ccc9f221102c4f3b58e9214b730dba9340bbbe97ad322d7546de1d818a03265652d7fa4ad65edecc65fe4accfa9f28141281320953926b6bc85608d37e3dcc227215e62591083183a98091bdbd6784256671428020944449e38894a1cc4ef85101db8766f3ad8a11bf7d3dbad5	\\xda19ef230507243809b70b229b1e0f65bc35bd8d4a292fa458042f6b00269e72e8a3411c66f9438ead03c33458fee65e8b14b33e25f4ee9403b502f9855eb705	1630849919000000	0	2000000	1	172
27	\\x2a1f378870832cdcaf144ee5b483e85b1e841aaf4aa674d3b824adff8498fe1e3b08915b900e538fae441157737ab0e7545065f7c6f2e532404f03dd16e6cc4e	\\x83ef7ac8337b11b9586a03cabcdb1e1bf1abb2af28226f271215349d1e460d0fb052208dbdcd0ecb7412c4f43405c8ee092f662d22b40765e377aa9be40d517ac3f37c4446325ba299ff253dda2bc2efbf11a4485c0648ddeb2434cc90b879bba5e118dabf46d59bd50af2c06e4c4168a96de423e1aab2e58b61d25b29677edd	\\xfb8e264db7c9a281855a75f338f459a5ccf685ab4c1e0eba01b55058efea2a86d74b467bcca709f9088b9bc3e8295f932b53997cc09b6fa6cbc5a3c51def4001	1630849919000000	0	2000000	1	172
28	\\xbacd6dfd6095f4b1101d02a44505f819e79deaa84615ccd5d1bdd070b35d39bbf8d6e15a8c4ea2bc8432ab6aa8b1529f06398014643ccd7ed16160691ac4686d	\\x6838135220509808a227a454d90dc10d498104ca7d563c9218e81bb949a6a08c5864e02431588924762d7d0eae180e0f6ab623f0e17fd1bc25cefb46b064b22efce0454545707e21bbf048754a22e6edd71b745e0fc8e7dbd0204c5b7850571051f92070604cab30dc1c35d47b885678e26a9707d2e4c82533cc54497c683f4d	\\x471978cbfe124e78cb1b6855ea8aeb9fe2d0a9b39c4190c1f6e73a4d525c8ac14a05d89bc5bd9f4d64852467c5a3e7b9b52cd252a31b324df6c4fca65aa9a603	1630849919000000	0	2000000	1	172
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
payto://x-taler-bank/localhost/Exchange	\\x5713c67de2664f172bb4f6785ac5c13d59e955f80b936c4e6d93d74bf87fc8bba60ee0731cd9c43d829cad9af0614d4990cdbfd3d523ef52a09a58df4848aa08	t	1630849897000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x25b0369e92f3cf16fee87c0888689cd8d26efa970bd6b3766e8b70be370834ae356d4622f47f4c75f2b03d47fefcfc244b90f0a8b34f5a2fe2516ff1d8605a00	1
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
1	1630849891714323	0	1024	f	wirewatch-exchange-account-1
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

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 10, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, false);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 1, false);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 1, false);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_instances_merchant_serial_seq', 1, false);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 1, false);


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

