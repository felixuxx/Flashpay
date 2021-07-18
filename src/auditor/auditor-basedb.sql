--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3 (Debian 13.3-1)
-- Dumped by pg_dump version 13.3 (Debian 13.3-1)

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
exchange-0001	2021-01-11 09:50:49.780705+01	grothoff	{}	{}
exchange-0002	2021-01-11 09:50:49.88573+01	grothoff	{}	{}
merchant-0001	2021-01-11 09:50:50.10513+01	grothoff	{}	{}
auditor-0001	2021-01-11 09:50:50.240694+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2021-01-11 09:50:57.877176+01	f	3939458c-c042-447a-a1a0-35ed367bef67	11	1
2	TESTKUDOS:10	0WVTEBTQ5Q6GVMVFBPSS036WK4XAWMFZWXV4X79Y2J196E9Q9KD0	2021-01-11 09:51:14.20022+01	f	6998009a-3e61-4c90-91b0-945f0f331507	2	11
3	TESTKUDOS:100	Joining bonus	2021-01-11 09:51:17.696531+01	f	da94ad44-922e-432b-8bad-1b603c079586	12	1
4	TESTKUDOS:18	WH1KY13K1B79YC5Z5R9KD1DPB604KWTS0WFSCVYMZ023FXP916BG	2021-01-11 09:51:18.44673+01	f	8a8fc8b6-1a21-467c-9256-4b6733fed9cb	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
41f21e5c-0deb-4919-ac3b-c035563ef110	TESTKUDOS:10	t	t	f	0WVTEBTQ5Q6GVMVFBPSS036WK4XAWMFZWXV4X79Y2J196E9Q9KD0	2	11
1aa111b9-7ba2-4484-b772-518f17f843c4	TESTKUDOS:18	t	t	f	WH1KY13K1B79YC5Z5R9KD1DPB604KWTS0WFSCVYMZ023FXP916BG	2	12
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
1	1	254	\\xa2cc5454bf4a07a192f5c7461f2547e9943625b26e4fe8e3bcad2e63676fbbe929b9c7e8be59e079a1e47e97768404865b3fe2941af5b3a0a01e9ae95a211502
2	1	193	\\x6eb05cdea698d8aa4d5ce8db01da62080a869a6628af45754794757fee371b738866110edfdf3164b0181b99b4bfb332d182a3b75c0af05d5cb4ad7bbfe7e907
3	1	290	\\xa19cad44cc9bd72c46d1e0f478bdff02fafd56cc4b3350e7989732178303314101ce470f7409c1d7a256fd1d69d761db7832b7ef4a2c8aca00d7890fc2858a0c
4	1	146	\\x1e27b4e13fbd17b3af06fb6d797542a4d8ad7fe4eb280d17940d4b548fd1e8d64646423a9b9fe33c52bb4116d3ed2496056bd76a23553210d35c3ea7cdcc1501
5	1	392	\\xd29b19989576934ebb94fee2d6cd00c77c9934ac8ef0c58ec68a658503bcf42cb65a9925c2ccc793c92cfad01f24011c8010d35f65e7be5bd296ea7278065204
6	1	327	\\x0d79f1c9c12ceeebbd11e3cb6395cb6d30ec2fb2327f940d27bb16045e75c17bcc44de85446474552aca431931a98a22510b5a25b5e45132b71a44a1af6d660c
8	1	375	\\x3cd97f23af8499b0377c9ad607bc691ecfda4721badd37462c1c1817316025b86da77317afe064531028a38910ae4710e99140542c9d864fe8e0d9aaf515150a
7	1	293	\\x004cb3d181a9c514b199bca9909b9561f5651bb56b3093025f658b7460c45676501b4e4a7a6203ffe58c1493ddfc21de94fb27cbad43352f72d84512e2b8dc0c
9	1	390	\\xa08ae7620f4a31f2059bd5e6a175754bd3e52b4a460e21d20271ee125bba8fd530d834e6e9be15350bd587db65af71e2aa262abc7f5fdbb58f2ac0db1a9ad608
10	1	243	\\x57516a320d883da386e23b5c928d540d689fbab58df5b6e960da4cf1e39495027a4832f11319f4fab7f9d1d54659672c60722b74052ca35b73d97e5e7f644608
11	1	232	\\x1c42b6b66773ef43a47c1b230170e42d68893d35d1b6ac22f732f1360f5c15214c52d6733e882bbe72fd022bffa4ab7eb3590ff4af521d25c56d8627f92c1906
12	1	237	\\x46def4292ed6f427c26c0e66d24ac01f1a11f81f0cdcbdca56aa8054f30b99f202b8a8d20f1a3cde6584e2366c0aec8c33e44db263d39878d5605bbb8c4b1d0e
13	1	217	\\x3df180c7262c988cf8b215260036efb160a5eb6450a427a00dd9666036461e5b95ab416f519f9973cb37854e2ffa7554f82149a71980f5646fc9878902955505
14	1	127	\\x47dc0eace1ac9707502ad0fea979a218cf36aaf3909f17a01dd26fc8885e68ef05d851fa50c6f5e123a194fe68704bcf5730e3aa3f23ba3f77464d1eb640c70d
15	1	117	\\x22dae91bc7b8d7214d9937c36fceed6a72f61c8b6c6e694f1dd0d7fd6191627d124aba56e8149b27414b3a8253d982ccdc002afa57b2d3c7c44d3172889e200f
17	1	116	\\x88fe136b4cb088e8cf90c02491c375d361a46acd5aeed5d8d345ddf60ccc8df7fdde88feb894701680656ae9a3595adeec46deaefc53f328cdc21d17b7925505
16	1	114	\\xbecfdaf7ecf6523c30bf8fc04a76887a0b1c424f8438204e2a908e5dab6375b148bc65e9f8f61a320f912f26811e2ee4bee7e7b8f0baaf4cc87da6676982350c
18	1	167	\\xc797475ab88ec07d4a403ac2986ee04400db44eadd8bee1e0d22129ef509d0bc64ae6642ec054ca020e23f01e7f0517e06b7337f540a69c972f89579c2222f0a
19	1	199	\\x58d059235c05e919f28c9e5bd20222be361ad0f695ec94daef052550f03a2492a668735eaf47fb4bb52dc13c21c9deac40b70119feb34f911a979dcaee08d10b
20	1	238	\\x29ab8ab5dcdc1b2ee35a0c6f42221000cdba1e408b43541eb592b3c894988e4456797c200c06bd7788dd2eba29aede37673e1d5e15dbea629b3ab310a690f80f
21	1	206	\\x69e34a348f480fabe1d5a1913b62298e096a5e0e82455db6d6c984077e9ea0eaa060a51ad58e7fdac3266cc823e004674abaf3fb8ebc08fce8dd0b43a43f9c00
23	1	405	\\xc4f09e8f47129a4ac9a6b8a0354adec150481d87af5605896f081c6400a16acf93bddd401f478ca2e6847f065139efca9c5b25993377d94b7cda7946cfd47d0c
22	1	303	\\x124df60622a0656a8935ad4c93386286096b23e1db0c1c5b90273bd93582f3dd9b428562fe747095442aead974eba8e42233606544d1b2f63fab9ecfcf8d3309
24	1	176	\\x7571c50d98557ea4b99b0e691865bcebe32a31c183d6648119c91e25949bb64385115ae4280dd63d881279a22e6353a5bf7f120cf416506f475ad0f8bffd260f
25	1	152	\\x3e5f146f2ad913b7906bdc220d06bce66edea6d5ce17a399165c55e4c0a99a66667ab9d8fff70ce7f0f4bf345d09e527256c48d078469abed9d31f7479c96806
26	1	18	\\x2e50ba568e8d133fcc2be66c7adcff8e7953e9ccdcccb326a6d88f9e8563d1e226bf03b78e119b3261faed90d63214bcf36ee5af104e6f7c6b2121d5857e2c04
27	1	180	\\xf6baa201f72bb876c6e43ea81633d99a95d460a4245649d59793d3f1edb81968836fe0c919fdc9a410728e8a9fb6c96a1db5db92de27c9383f30eb54e926010b
28	1	126	\\x77d4d05d08c2a1b43b396dac64755814b0fd8398ff86a83861569b8c9a2869670184c67b91447998e050aebe52060f3cc5b4fac4b6a592ead678bdef4a45f50e
29	1	187	\\x9f0519f94d9a4991ac8777f0a85bb5777525a456303b254d1c6e586f7cae9ad29662c2b9a86bd0c8d24b2de87565aefa8c01a67561ecd34ffef58e469a78b901
30	1	292	\\xa4ccded11d8e69b8159844cb5e11f171c7245835e45dbecccf428bdf694d930019b70f43f0de027eb883450e3db456c4f22f39d7958a9bfd81271541cf17a207
31	1	277	\\x16f6b80e558363499a9a8bfc33ed4c330816f0aee209efe0c723943db142f1465d455ea0ef237cab53e6f7fa7b38a454e72271088e73e6f983302917b578a90d
32	1	288	\\x63bdbc214a739e16a4f202ec034a96e4ede897ba96378b9ee25dbec27681e1a37a3e1a06403137ff2588f4fd93f3c8a1d9d0c019275d6f2c08d6318f1bb3ae0e
33	1	88	\\x1223f7048e9fcdc4143536754872735636ddcb16274f18e525e1631d80de517943378dcef537e708321de8d83e3e19673a92a0307e52f27ee2d27ec9932fc90e
34	1	410	\\x8ba8fb3bbdda35bbeeede119505b1e5fc485b45bb890fad8143f08aa096ac0e03477492107dd49749bf5805a38fe2cdf4d04c191d61b90c37dcd9fedb7f0910c
35	1	135	\\x4b0e08c7328ba952713d943cc5943d1b9986a2cac18b23a35c64a6edeeb18c650fb2e17c4f0aea15eea4b39d723bdaacac0df9481adff9c79c7eea487423b401
36	1	270	\\x10b61fce5220025635239897571d345a547a23dcc470cfe3d35696bd490b3ed577486a05b9aa192150b22376fb07efc804843fca1e2bf3019f7db15040f55208
37	1	65	\\x67c11f840b5588e1333f1e4cd026fe6dd0d5feefaad47751842707dc013aa3d5f93256941ac3be0d972900bd5640e6029019b03d1981b6d74b209d7bd4a13e04
38	1	387	\\x70fa5d2f1dd7b549271cc0259803a95feddaea61e96904b7978d6c8b2e153733c6012ccf3e3634a6bed0018113302e0fbcb462f7043023e38d320b046c68fb05
39	1	388	\\xd9d6e1d61bb396e53c71923195c888fdb2f0c3dada3a02b5b466b780a047fa6763090a7913f7a09505fba2d0bec3d722b6a9d3103b58a94b6a262ec503132a0f
40	1	158	\\x7836bcf424f9449e740c1561cd2caa1a0ae2ff0d9f6f9aec6b6cfdd653dacd6f8b2312ffd056063dd7ea139941412bedbf73a5fc705f29154f9e4c3eb0f83804
42	1	358	\\xc33eb9d031287244aa87d40d5ec7795b93101e9d87365d2a053e9ce99ce2d57a2b02a54fff7aa65231687d9c61181d9705b2d6db5c3d8b9cd78aa47578756900
41	1	378	\\xcc2a40fefd52d73f08a01ddbbbe40a429f04e44aa127f276780a0dbd305c7e805211a7155b71f17479e3e84c76a7ffe8e81bfad96a78fd4b6fddea01f717e505
43	1	289	\\xa62924d2d7ba70806919cba757a82a4e55966d214e79567bac031de13ad666fa8aeb402a49ba26eef6580c4151c6cb3065e62b2b5305b9c09f58020c61422501
44	1	271	\\xab504a8cf44c4f59ef5f1ee4152d2e68fcdf0bdbb933e58f4d73a0d94017abe099ed9508d7d6e79e9433725bb889d2ae90d3a5b28ad636f674f8f34a82856602
45	1	408	\\xfaf135eda09bdc84481a040db5126e88696502112d59d84b46f5fc1e8fcefa6a01b1e5a9d55460860f1574d00ce754a0b96bd47e96641931a2bec9fd9486690a
46	1	233	\\x0b96487ded06a0791486717d19946971ae2ad48d915d4c29eb3d63970fa2132590b7cfcd60235ca32a6febb30bbd0f90d7a41e59b98477a643226bd62737e400
47	1	186	\\x6df573746be43aaeb68f76eb4ee560e36aaf8058444e41ab7671a73f8f52769392be7ca095985fe22dfc04eaee110436e0dfbd647c3d20af0b9b526f0cdb1b0f
48	1	259	\\xc79411615ccb2239b3855ae0fe10f9f88b3fff01bfb7be57864da756a50881ab895ee9df26f23a70aed0e6ed5db3f4dff387e0ead38ad506e4dbabadb87bbb06
49	1	142	\\x523cf3f694837bdbb76a43ba1ae3470a1b83c425ca97c81d6e763fe0ee8d09c9599a58eae7180be974994dfa0fc075f49d05daabab22795e9e30d339855f1102
50	1	169	\\x9c03b0135f89aa5847618019be45d3fa3045b69025483628a4d607b3400cc09430cfeca912ca049eb87070da31ba518d9de35e71ab48118c8fc57f84e6461d07
51	1	344	\\x6dd0f9d47388b8d95a0d66f7d3f57c7155607099413bd923fd372d73c268ca34eb0ac59b1e68cdf5de99de20f57f492c2bffe5a0470d96cfa80ceeae92cda502
52	1	250	\\x4016890ee712169ace81ac65d0db4331a23b4067e721d105f4c54d35acbf350f200724865c8f5cad553b0b93d248ac63c24c091cb74507df46c053913195bf0d
54	1	401	\\x1a8f260e1302193457480d0bd8a9293087716a0fc008934660c3ea10dfba426cc1c2ee6161e9b64e07b5593c854e9c2113f7d3f87837a50fb99abaafcb3cf403
53	1	313	\\x78b19b0b9dcb3c1118d549277553ac0a07d8766c8cc400807adfe0701ab5a7d8cd96d8da402d3fe93f47f4a43004cf18ecaf63048422b459cdfe388535c6ba03
55	1	97	\\xc8f207e47cf0df4320a7d953e8cf196ac688185f718cf4c3050b2d5e08ed3ec6ce03b8f52420c01be0c67b7eca95a452f02f63bbc28e074bed86e1f233075c04
56	1	423	\\x2882743dd2dcd1902fd5a93551e88c5450ae064a84ab0bf2c4db0b293ee466631a8fe4aed3cd47f638ad87d559fcc9d78fc0092797c92c06b760b119b6454405
57	1	8	\\xa78a43c6ae027eb6117ce90545c4cb6cd484a31a24016cc1fd0027c2aa0c0136341c369b941c7141dd6bfcb8237752d83a73dae8ea2a6c618f42b9db07a8d506
58	1	262	\\xdbd633d0f34b76bc0f6549048ede43a2f7d6fd566e6df455631e81a68eb705f055b830ed175e9481646aefdb47da8bf206fa30a425dcae70d9082602f6722101
59	1	350	\\xcc1a060acba9fdf25e435a2b0da2b078d007a8c0bacd8b468cad901e5f669a99eb3603b005d8f101f9d45d3d18bd9b38f40e262855845a53e5d8b69f8d777a0d
60	1	137	\\x0159ce4fe7dd77b4363c7c7acccd4e25ea9b4d6d4dc8fa77160a479c571d7e07cc5cba5a893a7276f0378a74b8b52839a106e09e99f03477b158bd7b4afca00d
61	1	216	\\x9fd11497b3126fe6f2dbf822a630b55d3d99fd1a7aab55f381cfae7191eba722b2f8ec690af41b358d3b5eec73c4162d350b686df1ccc6a89569f1ea4f91d704
62	1	151	\\x30e3c14c863a0fca9166d3415c25e63ba4b29730364f00c9bfdf20694d1e2cdfb32f4b62ab4b55c56282b89492a3f785f5183d56a29c50e1ca99be08a575b60f
63	1	385	\\x6e496e798b0a6c2104ab0d9fb1ba80ca1382c59fa552f5e3ff05e5f9596759a22a16607dac8de33289fee80f956add73e145769fbb679f26d39f839b629a430c
64	1	71	\\x1e403baec5a384ba087af9f7b46c3dc0b33446b33dee59e1dc6c93a664e34827d85366a2ed89d8f55344a53f2e33275806ac1443156aadd5d56b5d647d11a603
65	1	190	\\x5dc95669dd018e9d3581ae17a92ef5f3666bf1870029a7c9fc404c5599d0a52c007b9432368b1e0f2bea544c78f34c367fcbe45eb09045066e7f3c06e8eca309
66	1	372	\\xb1afdc6d46caf55f499e02a01a691bc64b4f7f56492db134b5fa01ab2005849f5412ee669baddd795588bb1285a5ab952a962a7d6c9657cbfd4464128933170c
76	1	36	\\xa041621e76cb849773cccc8877d7edfcd55ff57e5850d14e855915b02283c5070385fa70a0ca67d780621c5eb9c8ac61707f03fcf2d48d34d3e052533ba46b0d
82	1	331	\\x18c8199e9c03c919ae60261507770651d99f9974abc2a962b0404958dc58086f57d202009b82c06a4a1a6f3471023ef81a78aee2e9eb16a317686bd9a528730b
89	1	311	\\xb63dbfbd813835bb47b5789e437102091a81a8913a4f9c4d2e5ff86851f2f8c88e1e60a26e53e1e887c58f0c24c8bc7a59d52f2b50b3ac8b6487437e427d8805
96	1	248	\\xb9e366d0dd05ef77f346caa3a7f58bc2ee6d3b487907b6970a5dee26454c414efea5cb62d6b0393592fa62f8879300a23df4de65f5957b044a8b3cac7ae4a40e
105	1	163	\\x68d22d590f6473bf9a642635a4848a26252883627bc39d2156e8c72b469d04191a137fdbb61cfeec14dca47069d7c1fe6a5c3cd449497028f2d9da37a176900c
112	1	416	\\x7d5a6ad3d65da094b40edc248e328bdf7e265eb32d8c2dae777991d0a6a37d046f5cc2064e3c75227b7309146cca2326be3ad643bf25aab2e492c168b45f0204
117	1	103	\\x36558562ceb8cc3c1c1a1610ca775a16c2c2c61091fbb2220a7078d17c5a375fc5e8435abdd84763b2c73ae94aebe7647ff3341384a9adce00e788b4b47bdf0c
125	1	37	\\xd398c5dd731447b64c51661f329b8391fd2e9e94f28ec357f2c40ba5ec6debb283d1164c2f84007124058bcf295bbea6f1d51fddf36e7f716c716849cbdc8406
133	1	38	\\x797defdb5627b7a43b16380f72033f04bbec4e54e85384da889da0ca794e480695c6c16ea1c5315b56964b7bd6ff4b03eb31cbc50791d4b92f981754b40d330d
139	1	3	\\x79ceeff828cfb0e51512cf2bcf82a909dbd61e5321ec68a09d75e522ce441e45d057fd9c1d5bceecb6312b369fbddcf4710302fdf0cf39c4169932f80fa45005
169	1	370	\\x93d44b85d6c70c202a1b45c26a8a0929f93ed27bc14624741774c273287c2c4a88103d8cf4a1faea3744491dc108d542487507bccaa92a46b7289e4f49a64a0e
197	1	211	\\x27a938490274f094001b09bfd3c8ec58b6f4250f851599e3e3ae563a92d9b05753315266bc06f0c673bfb9bd5cf00fb7de0b2fa4ccdd5408b4e1de95d439590b
215	1	62	\\x95c58e346a48d4ea28fb3606c228967dd7f49cdc1499011a9ef8c6fde7769da758b356b6aae426018177c4ebaf00e5586aeac35b2f6e2dc21d1f42083defbe0d
250	1	367	\\x38852eec04e76d6df2ef1d5ab8afba86775d47703c4f04aa4fdbba48889439bfdadb5360593e12517f5a82bf9c697860a952e040f6f4372386617ce281f29e0d
328	1	351	\\xb7776496e1373c18c8f31e3611c179344b7aaafc1b36af45a540ae1a871883b9575c7d8d2719b08e3cf66ec1cdda8c338e47f9922eb90a83f3c11af0f3dffe04
411	1	304	\\xd52f0e80223fcdfbf992a1bdedd32bf15072ab9ab42ed647ad259802e0e0de60f6bbcbdfe29d748bb3b1da9592e13568708444d68f6465c88ad6dd08ad02a10a
71	1	181	\\x862f1dc963a6b0b311791bfd2712a0d3babcf03af024bdbc217aed0cabffa6a6b77a0587ef048f5bd897440499c4eedb406ba5c8f081a09cb613fba1ef30430b
73	1	63	\\x163aee2b76f97fd51d5ddc3b946e9736aed5b96b05d8e9c081bcbf598d22a25bff26e547f563017eb3163b874eea133f8475c3ea34543d11686b3740feb23600
78	1	20	\\x4872c19ee916926e38e377014263b0b258aab12fdfd844a551235e9f3ca2bdf778e3bb7ac14a51e6f9eaa1cf03ff0425207228a6f9e07b43aa5fc3c2405c470c
86	1	407	\\xe952e7e0e4f5b99557f5741e486843e284c2184c32801e4dcd696ca0fdbb5b2ae93b2ef25419d9f7c984cc7a6bc311313ade9c432b392ace5fe9e99ba307920c
94	1	102	\\x81fe6f7d56307c837d960afdda6b991d47cc386f73d3f22638b7d161b81a7f15438e8615021c461d777a46688da76e726de0812a20724aa309060baf08348909
100	1	185	\\x3bc7c7bda8a7dce0786dd715c57225f7e1d5697b0ea7ccb63076a18b8057a09bf22595f2dd0fd1e3843ee451e63ab7ebab0b7584c53bf49669ffd9eb37d8cc03
107	1	417	\\xc075e7aa9b5c4b4e9cbd8cb267220a31918f6586cebce6f99e5e0398f4059aec1a7a64ac6690817ce65604c6b22b8f5f39a2fb9e8578255d5c0bd36787559302
118	1	110	\\xd927a63bb3bc71096dbb77ff45edcdfd236724b5c5c2c4df63ac42d743112d4dad369e5b83b589895a39b29aed1aa23b574c54989d809012178de347d5e49902
124	1	53	\\x86620f509b3ef0d17236cfe936126fa713c92de295ac4bebda7b6e35fae75dc78e82a4e38763be14057ab5d50354658f57e5f6254272eebc9a7c5ff16277c100
132	1	134	\\xe779ebc75c9fa3352d1d5975f24c276e5f06be05aacf4869780074eae89efc74b0a8bec3752d5484148ea49e05ba34efd844a234ef70a2fb7551145c41f7c306
140	1	191	\\x56b67e91c2e539803ab620bd9f610a4ab48010ea7273d12132a4fea3d9f77bf3d97e8b7259131571d527d0894aa71cf1c8b38fe6ca8813417a290aae0f07560d
174	1	412	\\x53c4d23c074964c923506501afe10c322e2d0ddadc1376575e65b58f5e36c7e40c5987db6dd6a54fb6594bc90d98d21c93e0128531c66ada15800b35a408c80f
205	1	40	\\xc4a0e52d26e8d4e16849fac1941af02dd651a3279d959993c4f75443cdd126ec25da3b83538530e36defd0c595d59d57b1317581995f414b290cf2eef652560a
224	1	381	\\x1ac04a90352b9b9a5b7a006540d700c6d0198adf252100dd1adac39250e23f0d998ff7cbf03206f4e52bc52eecc3e05d7305de22e61565b52543c27cf6a0b20f
252	1	220	\\xe7d87793c43d5f991b22d4a533d547b3695aefac54dd355819fb403c42bc66cf976ff45b4e83f17cc436120aae68ca9ce39b71a32c707389edeabfad7b461300
313	1	140	\\xaf4b920e0703ac306725e6722ecbae1bf0477311b99e35c2848c8e63606b866b01621a36b2627126bd3fadb0c2b3210c2c8507114efe0acfdb3472bf399a8e07
353	1	118	\\x1785ed14257beba53f54119436d5359108890d2e44ad21bec32c290576beab676e7cee9d3fad48da01e59dbaa1a020c40c8e027e1c184cd0adf366ccd2b4d30b
372	1	106	\\x6468649d1343d90b017e345582676352667498cf293aa31cd1d33eaae29b0ba35263a748a85ee9775fc2186c5349ade7d322e3632cf47317d0fe1d1b85009f07
387	1	406	\\x66fb321ab6fa5ce8d2e2999f3d29ff5b185bca82c80699eebb5594ac7ebf38c40e2a09f2eace25bebda0c41fc925ad3afe4286b060f682579ae612e29613e705
401	1	409	\\x8bcde45d65fdaf84c524363947b440af787c71de2e1918a5bc7137c850eba1dc63866353dfac9f2f97db621edbda619079221be1b2773d3197a4c569502e6b09
72	1	27	\\xd293343a2b4964284d01e5e8bc1f66282a917a6b173af36209b865dd80d6cd5325db6cefba1831a4c4b8fc4c4722b5bf6b35c9808c59560f76ab740c05bd0d0e
74	1	297	\\x552a1ab9591c63a079e334112fea9f0929413fd1e234211080d08cf0dda66cac370c0274a2ac5467bf461d681d3c97184e14d1334b3460f82ea6a435aca49409
77	1	86	\\x013bf58a6d80a367bde21311b01c59aea921e4ec885fbd2395f3f938c9d9e7fb176cd43d27fb1014d7d6deda7809f7b606a1999e9e837d702fb8171db4ffc40f
83	1	128	\\x3df85db58e2f90ed6bbd0194b7e6ded34ea61f1025c9512c8d2ad51ba9ad5566b27bc64af12c6ba189d27e0fd04ff970637cd631a289781b1614e5001c1d3302
91	1	411	\\x8b141770bd0d8584aa6480e5458b2673d9370b17197e2ae8f54365bf36d8c68ee8f98a74d68ba9e57d57a48fea4feb24182e6b907bb70f20f66fc2df1bcd4409
99	1	402	\\x59a43c5aab8826df754aa28f28210ab141c5e10c3b9db2b787118ad0eacd8dde467ad2daa388f7b254f3f5bd71b6e718e8a6985037b081302c72a207a17ac606
119	1	164	\\xb0dd9ea932bdec739ecf77cb94a3ece0a0b2bcd31bb9a09d7899663925173522ba346c19cca437dbd73f060bf98c6ae50ebb8d4a5827b73401a743dfb250f10c
126	1	107	\\x4e6084782f7247334355f082062c7618917099008b892e6332c0c3979d8b5669b5aa1c818aa0065e2024cc7756b98e850287e77cc1c162832d84020cadf1a20a
134	1	267	\\x82dc944d867861bb1418ee72174a491ae3e69a1eb280afa998010e4eba0b51016c062fbef11aeadc19a6b197d232e2060bfd5ed1160342a96fc9d5852ebd3900
136	1	153	\\x445389a002bdfe0984a87f03bbfbab40272d19a464a4c182aa4b8aa52159555c960b6adc2b41bfca7c1a72b079272ae7d8a280cadbe10e4a5eee8d4900405208
168	1	79	\\x67ea983d7703ca8e7a12bf94e571ea496e18b9d8330cdaf9a70f7614b02db6832bf1baf418e6447b5092326d5f5005b8e79f1b0bf101e917bd4dd0a244e2fd0a
200	1	244	\\x7cb91c200be0dc2d2882bebc2a2af371126196c6efd87b5ade11db08e7969f859fd1266b4f7519983a8728b3eeaf844a6d545def1274997ec68c61c502b5e60a
226	1	50	\\xc9d3f9246f89a2684f188bed88a115c5ae94ba923692d76126c18be67bc0511685d4e521f86c1eb92774bebff1da1f1f228fb63fa8ea465e6f040423d18c2b0f
242	1	82	\\x8aee0bb952242fd50339cde8f91140d72a317138f29e10d31d3474fb7ceece653562e72c3dba4d20acffd1368ba27776a7c2cd1cbe66f6cf018e215ef539240f
292	1	335	\\x0b2d82d2ed9f2a63a4524834439206c3bed17dbf3740d08c132a49e62807f6c5326d73bf990b9592d3f0fa918ce8892beed870f3c2dc3c808128c9b8117cb906
336	1	394	\\xab065688bb12f87ca441d084483abb05b3cb5f9826eb8a8a18aa28c4f7ff189cf3b6b962ab3bc337c607d2fd319f2d79fe174d89f64af17a618dd9dd1dac4c03
350	1	170	\\xa61e66a49951763e8ef3b972a1cef54ad5a5a769563b3da6a704972fc87f9052b837183387724cf67756942fe4adc8ecc389f76842426d6b113f70d040b6ba08
363	1	342	\\xb723aa87be3500300b10237e19c7b0f0c7ca36bd2799b237ce03b87bceb8418b67c668cd914ab53f7ea07cd006963dbd13dd8b03283c776ad9b3d790b6740d00
402	1	99	\\x88df4a31899232ca9efbf5e2f2aab51478add9cadbc9629f480745df180a1ac1c15516e7734b4e25e083afae69cd1cd919608e80928a3cfa0ef6f3441ef83403
67	1	395	\\x378a29d9c650562e8136924c0b342fb2725520934ba77e7469c2a95a6c5798e1a31d391f77b90c2318c344d1d77f89c7c93d0ad1067b96e8b1a8fec1c8dabc08
80	1	195	\\x41d9037805fc78b9bbe572519201f1e331b33fdc3bcd4f2dc287f5b1d384993dab8de28eef06c0f411002cdaf7b20e227cdbc4066f6ff616e7e89f75c86cb204
88	1	382	\\xa574186478f7bcb7cd8293d67a41bae617d272417bca339f5602888afd377d8a8f26a17d9dbef7d9eb3894a371a3b4f0ac275acb797711b0fd243c42e30f5707
95	1	52	\\xc76cefa62aa5b6dce47fce4c4d255f8e531327ee4d1c4f6c5625eba795c11c1ef48e7d88ce4b88930797a557078d8b174e1a4f4bdb2b632c4c881893b7e1050f
102	1	144	\\x05d7936c49f51377096ce4dc033840b55f9190bc6174593bfa72ce82083da7d6f3adc22fc5d322ab20ac9958accb26019d14b9a576016500c718f6cc89ff8d01
109	1	72	\\xfc0aab1813bcda40b6df6f15378348ccb1bc694054cfbd963d3f7fc0904563be1ce9310e6f44dcb979f0ab63d9f6d9e11b6bfeff914d59ee18f4dbab19c1a901
115	1	276	\\x9d52b038c1b77d0d70a3264fef1ec063bcd64caaa681a8b51a3b42bb0ffadd6bfe100c033820f5ef14652a4230094d160cd341bb6e43af533ea4bdd5c0898a0b
122	1	59	\\x819187cf9207a893308064c88a2925d2494a3afefe2b25ffc1e9f575b655650f49a51d03d30a46a61f53bfffa7ac9c8eaf1f3edb6fb3545f532ff9f600a7d90c
135	1	302	\\x74526dbc4c711f53e4e3f8d69d23fb1e2fe94ca129286371b990d7cd8869b681da9b2fc96639fa8f28c0b2163f0597d97950981cb73cc752684fe717659b100e
137	1	245	\\x1b112a2a2e2cacbd4552f67dd5715eecb321df7be470bf393305ceb93d12c3dad1891ba5d5ca1d2b7269c86765642a6818352fb58c653ed0d8b6f6adddf34609
172	1	356	\\x5218a246f91eefbd9cc9eb87fd93f9c4ca0fc7521b36539359c177709c9bb5266fcdd11b2dc12e33570bdf075491921015f9ede90ea488f84db9e9bef3c4140c
199	1	201	\\xf0b0275ed3337d872d304cee4aab047659448f3faa6a62fa8eac79f5e4251405e745d3a39aaaf40e062f890a22aeba2ad7e1e85c43b14770ba80c9896f323608
220	1	353	\\x7e273b635cd54de6ed735d8c1631eb6955f5e32dc10c8fac99dc6df77d65fda338b2634c436fc5fda6fe44eb636d021df6fcb9d53ab031868797b711ebdabf01
244	1	159	\\x2ba0c914f98282252553b8a360e5f4bff3c648ac8b956364b4ca19c8d53499319c9e137352f90ff1a426b1d2fc627e730aac4dad8f7b9ce4af050869fd5f720a
270	1	225	\\x49fb1d4bc1d676174fc3b8fede3896e699736e87e33275ec58570a0f189bcf8020d28599cb74c0db0e281679da998ea81618bcb53afaac985f8631870ad3c002
302	1	47	\\xc462a5126809c08539fd2639407c644fdad8f211342d2c9d9df8fa4c87db0c7d76ea9206e6d016ed112f61496325483fbb5f0030a04564b1993a6f214ce9a30a
345	1	89	\\x42eb9dca1a18c6fd9f6ae8e5518b96d0a499d6e84b706c56906177832c19823052c27f090602aafcf5fcc1aed0e2faa99add54e54cc78ea71fc2bdff47140a05
420	1	415	\\xfa69d981f2128b350e7223bef0c24042f1adf6af4a46ad2c2485727cef0b6ed0a8bf0de41afbb49dc413a7a1ea276abf95219c74a8bb0b5732cda0de71b87006
70	1	9	\\x566496f8f755d37f9c25658fc3357ccf5bffeba8030b8184b956e171115b9c212c58c423a1dbe5a9601ba488898be631c0674693804f931411d1eee3dd82790e
85	1	348	\\x365574366a48a4747124e702cd5305efb6c3d281a649729f50a7ac61bad71b34852fad651d08fe0ea9e8b2df3f0c72a1f0e2cddc2baa7f8bbffa95b5bdd1f309
97	1	362	\\x8f880e63cc14418e09b88e7dd336020a5145409034cb7adf92b62b5f214105a23ad3401b33f64a1d9b4bc9e5363a161c33fe675445a2ca4af1544581ebf76a0d
106	1	240	\\x31f6fff70ae02c821bd785f376b8ff08f4a56b4d7b15480c52067a3aa4e78b82bb0b9451b1d355937e473c1d9587ff1c89847325136686045d585d9707eb420a
113	1	96	\\xd7f84048cbe49fe20b0b248c7d482d719a6bdc98c922e74fa11c7513e3e33435d7783e856ee4745a27212020edcff9a6de05d9a82969708a0234522b2aaf2a05
128	1	4	\\xdec3bb5e944506e8977ef046221de604bd97fc596c134d187f90084106be86b05d5ec3b016dc19f1e22bdaaf2d30a5d8f21dd08bb3d93d9d10f150881fcc6e00
143	1	269	\\x6e8b630c60c947ccb9a93f490cd6607b565561e263fa592726a0d6968b474c4bff0506593bdbb90a95b0997763f907ea57e491a903ea7d3d8b2a4e722f322f0f
178	1	354	\\x1b64f386a01569727e8d940e4413deb5120c3511bdef130af3c26f7296d531e7f1f53abcd23c00064aa453a843b86c7f13eef9e2e9424b861f3e9ca5f7a1ea0b
204	1	421	\\xac2a49c477cb562fc484cd1a08a9bbf02ac7f9098717e19bede1df0ae1b36cc95d21835680eab8771af7415794e538235da0c9404d724c32f77c3b7c95299b0d
230	1	210	\\x1fc16d1545e1873c07f97962990ff25c85b44b9a006a0476f850edc08ecdec04630534d919647d7ab4f1ceba4c550a61b44e88a7d4e8b092849b6ec8e99c9c0f
294	1	341	\\xc4166384631abcf20aa3b58de61f50f8d949ed18eaa9184278e693a3e262358c6df69fbdc78f40ea079d8b05d9f69b4fb8527d6cd656438b52deaddc7b2bb80d
311	1	319	\\x7a0d5ce3c8c053ac8592955a97f12acd57d62e9dfc7b2689de67d58efe2fafe23f73b69865e43479321773bf6b540cd60f3f2641fbee5838c5ee92fce8f31309
325	1	198	\\xe32368d023d3ef7621510970b2138f9fa2a1149d3da96d0ac5a55a9c3e7262fba1876d3ad04bea7402f449601a691ddd6c4598e29dc78cb296273e81ab498509
339	1	228	\\x83d463808604ce5745c88dd78c14711647a82ee5fa0eb2e0f338d25337a2898918939d0f9207a355f08110eda88f1ba220cbf54b11ecc4c662b27cc5b618ca0a
367	1	138	\\x81af6d85d27fbb804a0917ef03867883638a4973f277d07445357a8272dfffcb04e184b17bd4199b2dddc8a2ca818ae56822577f9e166c6c1a858d2e5f35f204
398	1	234	\\x4cd70d5697a50bdc32c821115b375e2a9ad14401274b0805a1f992f9da5089db1dbc5726fa268850102c94a62686af3e919f16dc89546642b6af7adf4ad9d309
415	1	175	\\xa9d050f6d382dfe7c61b40611e3d409cb244fffae023784c19f174a145147520c0263f993401f485e6e554613b605669525e5bfcd1e839717e39120d42aa4505
68	1	296	\\xa7f102ecd5dbbdf6ee955fdd38a1b30f32aac0a3dfcfe7c26b7c3c8c18646e2e6c5c355250dc0c6a788caa3d48fbb97387e65c2642257c97a5f18e455483b609
81	1	51	\\x5a939686a85062ea2d2ed7e2da9e1e873c9c03e6de34f972ae66bfc8d1e3477e33c2182255a9e6411a32ee237c0213828dc4e460f7128ceab5a2d210d64ba50c
87	1	194	\\xdf6fb7c31a992566f131ae04e619680c72669d887a537b124e7c8ecc4668276faf84569699295b8d3f43fcaf142e916cf6e5c17f05560297a4f194473dc61f06
93	1	119	\\xf3e05dc189c7e3501ff1775404ec9f43f87bc1fc9578c9e152b11ab9835d98d33203290cbc12615f04e17f80c7ab2411855a31ce58e7d3988b94cc3536c0510a
98	1	252	\\x432d62f5ca315322000580649bdb584a148055a1c01aa7b34402d6ce861c47029250c65644e4c68b8f09a29e25d1f36a50f653f0bcdb1ade7b572e2075dd530a
104	1	157	\\x8b2a6b39cbc295dd36ee9d20a020e936822c83d3d2a78ee14b5ef7fbe37123b14176aff89f4658a83f5b2a74186dc3d1cd5d3c40b88b5335cb97c900c53a1b07
110	1	317	\\x0bb7a7e617ecd524c51e636fd72ed8e906de5d6deb05985dfafc1d0ae77a94e669124edac61b0090010ecec0fdebb4989fda124f840ea728c7941db0dcd6c40b
114	1	22	\\x61f9ac8a285d82d3de5da5678ea931c8ef0121a4848359c15e876aeb452cb7430e21b03c036bb3a3ecad13fbe492041b894f669e19484d1b8347119214a1080c
123	1	202	\\xaca62c37716e1c7986fe280f15ebeb15e274fc08e23945e3155dfb34c323bc3e29b55ae4700bc60980a6662e76e54bac4fa037f21d87bc139d4a9c8222447308
130	1	182	\\xe5a2d00368ecb4c5503f55bac9afcd8fb36363eeeded684c0f58f17ff2178ec59a7f165c702b1b37592770153e4a71d2b9bea4c67bbf84f9b6843da3d8694e00
141	1	24	\\x237ad0bd7a4e9cf334422ab95fc8798c693d47634e14a30eb5ffd7802c2d98e11c635fae78cb102726046b9a58fbe37dca0b83c64c48f9637ab75bc036d68e0c
170	1	184	\\xa60d2ca06e24b6b50503e9910bacb8e7db4b1ca0e604b0e7a4dbf09307046462954b7da6720270ac29cf310b174ec34b37160cbd03cc56e1dddecd98b7926108
202	1	301	\\xd17f0feaf35030dffb167a16d1a6254ac3f9f8377697eecf97e5872bfd9968565cb665ba3ea325e4b789bf4e5f86ef07434294f28973063f6c1bf696d28d9809
229	1	383	\\xe2539576704d1b534e3bce6cabbab7249971c8032ba4f37144437c3b5b3296aa44d437b235e1894d1dc262d9ec2322adf5464119ee85cb50a1f0d0a73c149801
258	1	236	\\x3730fa040a9ad9edfa00667f1209f3c1f6556466be61728c112821eccdd61e502d742ab2fdeb0708b7f32bed24a1711fa0fa14cf6b23297c5fb69870ec98fd0c
279	1	257	\\x292308caf3a08bd49439c9de55df1ce2ae6d33ad4cde61880cc4fef1b9b5ca250f572be2c2d063bdefd4f26bd52316c76f6921b2fd857349bd3c5c099749d509
346	1	85	\\xecf1267dc142c3a6d03e2aaa08ae6568ef612abe9ab8e031a4120b29314fd9c8096c74dbcfdeecec0f0f8df081ee1dbb31df4c8c354fff3a8ae89e2e96439b0c
362	1	310	\\xf103296fd5092c840989e95a5459594d36e9cc023d53484f0205a1d8dbf5de5fc8ef4c540c027c6c786534bd5a97282e8ad1ed709976f9114d9fd10becf35f04
390	1	156	\\x9bd8cd2fdcc15b047dd23db338f132d4ece099627a2b367d138dfdeb5c515bfc2b0f850de9d8003da6ab62ea65ec7fea62eb96d34b57cf3f8a810aec92628a0f
75	1	404	\\x8d2cb7fd2c2f353af45023959ecf7583298378517f6ca3a17269261230658f51ce99790446c7bf3daed9f9644001307182599fcf86d189c368fe6b5616627d0d
84	1	312	\\xf53d15f1254f2463a4a99a96f58d2064d7cd448fb8d863a8daa244aedbcae9adf26010aa8873d95b8d31855bc1e68217b5e1fdbcc0211ff908131395b1ca3f04
92	1	26	\\x9894b2379196550dd8e290a523f9383986d465d13e85a7aff7bea7a859e23d6083a720f24f299e2a2f611d544e28a588bcf03e8da945adea2187604eb92f6c05
103	1	256	\\x235d4c511c5b554b3679b3331c311033281d490a4bdf25f921e45ff5807ad15d829643f14e4b00906d0efec75d69e6b6771fb7817dbf398eae041ba7116dfb03
111	1	266	\\x2169f6731419a15ce31cffdcdf688a0a7646e0cf2aa60c32fddd57013c8fd64641405feb14e5ce2d79c2cb0f127c2646755fdd3b6351018ef9d7f74e62cee209
120	1	364	\\xe50c9462768880bb4303ebf3cde14248929d15c9fef22cc01df24e95a8a4a1f446f0a8fdffc88a3654a30d3059ab83783eb160d97d8b8224ea71787a6b45a306
127	1	281	\\x79c88d58a82c1db0440488cc85689fe38d80f046119ec8cc13d0e036646f14f30d035eea6c92ba679273d5b765e8884460aabeafa868c24ed3e934642993940e
131	1	300	\\xafc776e45ebedb0f7b7a76ccef30a0fc4a09c6faf7195be27e01e133207457eb986e43f3e4daafd87d5c4f46e18ab4a4cebd66878de9a8c88803a3f4ac7ec904
142	1	178	\\x58c92422e970cc10ed56c07b83424b67179682eb2c588a394feeb9faed960160df197984249cc195284d9e0ec866fcbabc7c36209e5f544e9fe7dbb83210ee0c
176	1	218	\\xa13c5ead5021966e050694b7da9012dc98e727f814c4e9df5b43ec03ae2cda781174ce74fe8c72c2900a5dcf5206239a4e1972960173fb48f6241b539600fa03
203	1	46	\\x5af88f7f6248fa8234c135921177d88851b027f63ac38df45f6e7c182b3f2de202970e2efe646ec8663690f0c7a8d6db4bbea867ed62df528b0e545e20615f03
241	1	396	\\x95278961b957c146ec7dcc728ac0e381113276c5252e76e920bf54517fc9064e5d05b53293b7d61a9ad0989941a60ed7251c2115af0d52368400aeab0bc1e904
278	1	100	\\x758647600992984553e18d82ce70532a3eed563d8538c437c45814e53eee3167571e88d2ea1d5ee0d92d16c708f4a017bfac5996957cdeffa5add5cfc480b406
295	1	320	\\x31f173180641c93de12794c0d65b71e2e6e104b7e3c9267546d72dfd973845ff5a444aaf59828ce9fbc8ed23b1bcf1fbf8d1d878de7685d3bf96c099182afe08
308	1	162	\\x0f0b50e40796828550343df7f53fb0ffae0cff403f2ced9637c959b337c95e9c688195ce6d6f9edb433560a2d90c7b8bdd87dfd2bec7e7b31c6cdaf5738e470e
375	1	189	\\x8b5f3fdd7d4e3665ca0ee89be92caa338168f2d3e1e47951ac7335534414181e8a719aba066d1bcfbd92efb42c9aaba48c4bcc3f3d01a17a181d5439ba4a6209
386	1	420	\\xe81eee89b0d7e36ce265bcd6e2776f94df168e3b648da197800d018a5361158c0ac1fee6f7db5b06debd378337206268e808d68ba4c9308c0bffb5901e8af309
417	1	373	\\x56e98057234dfcd39642f0a55830aa85f9a21504245d9d8df29c54f6085715df86ed98dfc63faeccbfc54d66fb9795c120648bcb01233e2f8ac94a83e8350e07
144	1	111	\\xd2e41fff114ebc9397b1b4ee241d74f35ed3b681ad66bbf6644cdaa00a36461e5923ace94909db9eb1ceab362d64b700f357116d5722c53ad0560d9786c5f801
195	1	246	\\x9e79a02ad9eec3e8e7584c17fcfcf2bba2675a1df945704cf2c6e1aef60060215c90b81f0789d9a52d2988c229e939754b420df6cf4c2c88193b68fe3b709a08
225	1	121	\\x5677de390c4cfca9925eacfc7128d800aa5dfc25616d22b609766de9ea2d3bf3f65344f93e98b1187b0f136536827553632093a66895ba09dbee41ebfecb670a
253	1	349	\\xa7c72021ff217bd2bc5adb1b4aadd4f94b7b6d6f066320a422ea6bcbd54db601e85e118a41c3d9eead9188cc17dd0fec92987c6fd2859dbc17549c699570de00
304	1	113	\\x123a1143874bcbdd463ac02a9fb4674be65943053733b97cc45b4c201e7505038fbbddf463b1bedf67dedf3d26d460e6e4bf802817c86f64698af86edea1180c
357	1	132	\\x23d5790c2e449c6e369e880499ce2d70ef86c6b938c0a9623fd570464784c8ab60e7e7b6df6bed8d1082702cf077792d6cf37d0c48e1740464d6c4b8c5a5a305
371	1	166	\\xd13f350f3e58ad524ca3cd658c18f65321a541905e1d90e5a1bdda493cc5066565cd5f855e344ae88ce381ff8db0cc90b3eac7c57840554293245988b8558d06
380	1	338	\\x75bb764c0e770d4b8ebc9800df0a8dba513e7aecaa47e4bcd61f676689110afeb5ee1e282ea635b213618e057e870de804bd12250e7ce80a42ddea1468bdd007
391	1	328	\\xd6bf3f6711daaa51f3ff1091f695c0fa1d2252d228378b2450d86e6388d7489c9acf46b2c4ffd64713ad32837170af2bf8f22365b3c1ca3e37e2a4fc3ad44c05
422	1	221	\\x0b323dac3dd480f7c41fa7932a3143f3f90bd3610ffd925ce9fca14603c5b2b1cc67c51686bfe04e5221315053f19afb57bdf468054914e27d8233593ee8a406
145	1	241	\\x6f66c2031a2e2bf529eb166c6e1e09c3ee3e58e48c8759b5732d717406ea1e0387deab26cdd8274e5c6172082d369f686f8cadcf43ef8b112554bdd5a12e120b
190	1	330	\\xc1f6a9f8ced2d8e8a09a4101e6b294962f92c001166ff8088c682ad04580d5e2ada279f3cda4ed7e6b7dc2b1745c87464d379df835a1b3f2ee0996f926aee906
227	1	67	\\x2e3a99b363bfdc5328a69493865d7812ce78df7d3803bd00a5192a6211f2b9a83d1c940e15afbf6ae796f4e159fdc492f6362843595b6a572bf75b846e34a306
259	1	314	\\x3dba4f012e5b8d48c04274a36f36b49ab2b7302943e36544c560aa088cb0859f55cf42efeb4ef3e5d6d4007dce2c409e351167ff0a52d9b24d557902b0ede701
293	1	337	\\xbb6b370d470d456b424059ab3a4a64bed6d341457bd4707b5271bccd197dfdd3535dfc795df6f6fbb40d0c61b742b38cc928c7b8a0e007b1ed5c975d45f64c0c
407	1	139	\\x79ea81600f2b7522272a36531d84deabd73f79920e329ca15e4ead81381ce343535fb68a4f53b6e495d71b2e5b211b83b4be5181221cf60f85f3ac449df0c40a
146	1	174	\\xd49d017cb0811c0a7995c479e06ac5dfd468bf79e92617ea7a08f0a78a29d9e6bf576f8f07bd872c500e153e46d873e91b47f41ea7051e25cb44d5c3a55e9802
194	1	286	\\x4afc9bf769a9b7a0442f52302ab6943d2c552afb4beaeec8c323afabc90a05c34d1dc9614c4efcb37ce53e9364647287ffa4df4a5b84a829b257329975f39002
236	1	357	\\xa4c6cc8ab53ce260eae48d1f768c302a12193fd246e8d7e8d58ad1152ecfa45af10dee9ff3bf8141bfbdc344b5a35381996818d3d81b9647869044c463600e01
262	1	15	\\x2975d354dca3903b941820f5cb70ae3d1580a73105841d8c2f3e43efd0017ab9052a60b327fb99f6a806ffd725a76466e1852c82594a012ebe1c06ac07db6002
280	1	61	\\x0f1a98ab341e5bea820f272f4350223f782baf897fd6f3591c9bb40c9433114a87a00815e25f11653aa938e5afd87dbd3aa79dfc5a7d50cca5f69412c803b70c
326	1	16	\\x89958e1fa36d8ef57f0852c28758cd955600089835e2a835cc5d7c24620af01a052827af044e23368a0dc810a44e7d476322f7cd00f0179a67b7796d5e4b0e03
385	1	115	\\x174eebdfdd5fba61094d2a3d0fcdd771f499d2d5d21724e0bdfd5c170fe7354119811c831c83a2aadaa5ae9c54401357b25d215ea927ca96a13402528b685c01
406	1	403	\\xa7c1d7a7e707fc18b578ca80d7a6d68c2c6f64de1ffe7dadb025fd396f69d3db839b9e45f7763a108865e3ff36ddbd38ca0df8cdab03dac87a53a0e6f1a82a0b
147	1	188	\\x7263b7dd814b717218ae85203c0c056719b7437726837d1381745364aceb65ce48c077ccca6ee6a4c5514c6d9debb3b2a5803aedc06a15a7f77f66e24fb67503
173	1	306	\\x1634c0c6c5d5d274ff17da9ba424efe059f79368db2aa763f55e4d828f5a50b8e0c180ce555b44c23b61d6a832a74fff294f7261b21ffaaf17356634578cb80c
212	1	21	\\x1580ef671d3ee2618db638afdc201babcf3e41010b405b6de6716b2de14a086f08bf28b78cb74b62e2058183f71b78c3085f44147a39eccc0decbd717adf6900
237	1	299	\\xc93f622e5130bbe3fb976f93df5fe382561675c34a89a325ea2961ca76407d66721159b65018fe0f3bab1123de190b92025599e925aab3ac9fb5d9aa0d64e807
289	1	258	\\xcca8c35acdd2a2b0f999adb5df8c69da971e56b7eea3d2bae6118bbb44d3a5b7c37021ba2595e2ed6a4691a5020dd7350e7bf741fa9baeaa29d9acfa726cf60b
309	1	315	\\xe2d71d3cf584ac86fbe97ae3f00a56e6ffc1464497ed57cc648841f298cefcafe6ffe58c94cd7cd3387fcabaa02c6edadba640c78b057408139fbceda18bd903
351	1	272	\\xa527de4eb6b3c163f5c00f828ccca79953cad4c2db4c4178ccbd735669d062fd45777949d03b02ce5409e2bfdecada662b827f23f8e283ca25fb08047d3f4206
397	1	282	\\xb9d4cb44625286b3bc63e8d89d47fa4cda59a6a75b4adc1572aa4301abbdddc689ed5905886a5de31d9437973acdfa6b5438144996388150006541cdb9808104
148	1	376	\\xb3715e042ede25d03a8ffa66c545e5f0a88f6df157f46ca1384d7d284d83e87f27baa8df0993fef7f1f20d8ca13e93e433a1e46d7eaacabce2757ffc789fb20b
198	1	287	\\x311c56b127e2c71d87b94668e7b733a317ed9b63a9c073be4885490e06b52bd1465dacef9d3ef6db21bc8149aa2f3e096f2c218cd192c8fe9648956ad9b0c002
243	1	360	\\xb0aea91ee83d5e349a163ab29cf805444d7872ad0df752882bfbedb87d819c091519f9e1ba7cb6a225e59fce6a50a89a037044d9fca903160a3a7e9a79016503
261	1	77	\\x8de2d618af9bc4729db84fba6b485b7df15051811968b083a23812277c093aa4c3827353cf30179070524a4cfcd5319f959ef5330ad66dbd3c3ab73105f45509
284	1	260	\\x7b918c9c5a3a41326837bf8739a60071489e75e3ca92c9c7c9c1f91059599bac79d59d8d56807ba03a55593862ff556524bd0d5ee1184e6661240261204f3e02
296	1	274	\\x32fc106f964e56ab930a31342b9ad04b2fb400e2602c577b8e88a49fda0081b0d86a2cdc02668f449a221f43bfbd037c8d55063f8f2dcd44f75011bba2a50803
305	1	295	\\xd464656fee395a719263e69be0c50ccd531acc037e067a5d72f5991f128914bd685c1e58c6d5873c3a6cbd5cdb9eb068fa4eb0bcb67ebd3ab4d7ab8410931d03
321	1	298	\\x48331082f58649d14a6e14ec9b0d32c8a60e8dcd8dbc9a86d9f70af0ab8a5b004129dfedd5d90ccbed4b0ebcd1febe36ae2d78da644b1f43f0af98e0236f4b0a
347	1	208	\\x17a5b8242cee3e6911a970c603c68dce4bb921a6ed51201455e3ecd1ee4dca86ef00ba5f05cd4eb094d492489ba4488ec60f1ec75066779ded4e743aa0797b00
365	1	279	\\xa3b741e5c887808701b6aae3d84427278a8417197dc967664bd29a16ff9cd3c811d252e9891607eccc0f354d8149a340c9dfcd4ae63e088ad2f4723b9c21770f
377	1	131	\\x49710520d1a6070516909dcc381236ca52c0610eb18100918ba45b266b9343771b12f6da69de97013def3b742ffe1972271e48dc83e20ba97e68ec6b65880f03
393	1	316	\\x81ecc72d71b4a90f4c9eb3fa2eb8b316326ea82dd31f711e67144bbc52cf258d581357942020d617838e8e49ce40a550fb79e9472e2c2ee915c18a42b0a65104
408	1	419	\\x385faf4a7331313903e757436e9d09d7570d249057575bface2bfd2b312059c483ae912cf868dfa340a5d1c3729a411ff2abe4ffff471ad8d1c932f179383e0a
149	1	49	\\xbf3e4880d1de7b5911cacf54f080bc2fc6f43e4d53785321be47d3b9801e37395d690e2227814f0098f1be2e0fe7a87644c1319df7af77ebb4d0d41f5e77d106
210	1	226	\\xede9b914d6ecdc8b58ebdefba633ed975a140e4634d4183e10878eded54f89b38f7b4107a220cd21693d39d766d0d518e9fcee9247ec134d0c3a4b1186ee0f00
246	1	308	\\x6b03eeb3d40629d4a76355c4e0a1f153ed4294c6de8b0a2fdc40141fec39071a74ed4a31d8eab94e8d83e22c555e86c296611601e56d0ab647a3ed023371a703
275	1	55	\\x3df2d7d895e9720146c04f2ddb8914742b2d216d82ac87f37a30b59235e2dd2b20a7d637483160b733c0fcf772342eb14891dadfdd382c8f1d2b6484f1f78c03
299	1	145	\\xf5b96a6872cce8b915fc91e81a559a3cebf09f2361e90d1f2898ee4052745f30b7563be3bf4a8e9b47092cb00fa802a1557aef12add01e01c821947777a24008
316	1	32	\\x075ce0cca5392d8f923ccd9fbebb3a0e10dca45bbcd6111a1edca40fd73b497a192cd279def2b1781a548801077413b7fd41f56ac91d9d2a2429ff88a6906b05
330	1	105	\\x38c47aa6cd4c53353d0c37f0f9e47e77f447843135b46227f1a419ee2e1b7e7a7ec2f8e35be9535c10d4af2ded31d9f256b31d991d352ba71dd67cf2ed22ac0f
358	1	56	\\x4b6f9476273cd5359a97be68fdfe0a5a4e61d4140e3e578cec99424ba0accb8618ce977f0d90d34b4744dd24f8788402da6a24fd33e8e3c3369a1df2881a180c
409	1	305	\\x0f1c128a7f0bedb8d39d676c9b9d362074cc779baba4aab52b854d05635db30201407428f60d33a06337f20dbcc475b3dee7122aa198c2a4f6b52c3a894b2b09
150	1	284	\\xec37717bee0475c4d60352eb5dd54130f011e15a0d5c02ab0edf1e4280165291cc7613254dcd9ebb639b87cae1477a8c5a0d04cc08a81bb50df325b3d2a9fd0a
183	1	389	\\x467335c8de1ae3e9755ec84e38f16fe0dfab922f247f0aba1b46c5cceaf904d081d00bf6ecfc102461c6374d65ea0632e9a13db223e59d4375144fe52311a507
240	1	19	\\xa1d07b413d34d6596bd713d21976f89d2af4a6f84047a40ece44c97387a83f2ed9338b6b7682051871324601ab044c852d5eed1162696c5725405c301041c905
274	1	374	\\x5645ec09342b3e409c24eb6cbed6dba8c49ee75b9e80f108d3b404f11935471bf91c96d0fca68d2a098d4c6ac1363abec7f54e0b436d3859b2213c3acee32b08
298	1	214	\\xa48730f51e735d5ed47774180738fda46db0d0dcd2bc10aeb200af3f9934ab7e04a1cd554f0b83949dd91b9c51b1d1638e4cc4b9d801ac0acd7eb5397664ea03
334	1	13	\\x335cf4ef0b884d3541a3eaa5b99cc67fd38c24831c8441a75c96ecf7fc473c430cab39c4a37b42b69dc9583d1cb9f65129065e4c1457358673b90dc2803b140c
368	1	352	\\x0799e340bd45ed5142fcb353047dcede3e0a6e1f49708a3c50758e246ce580960d128dbfd438f7a8f13e3a9c8a93b9bd8491cb9285dc4b41afc42e51f794c904
421	1	69	\\xf4a4e7295404720e55c16c95cf731b0262daede3534172b964cefc94e0b627245a441c716cdbc808e58858e7cfe916287d2b68e828477bc9c1fb7be9ac65da05
151	1	204	\\x9605873cc2e8143c9c2da306ec0488bc52ee2e4ba2d8c2aa8a2761a83b1bfa0abd467c69cad9f833f5f20ee7e4f8accb1b293e2a622e7aa985b7935e937d420e
184	1	253	\\x368125726b5f17e787b5694e77ae80dab9f261a472f7717b63888dba51f57eeff4f13cad3c5a4f9aa9f8ea03ef24bbfbd3e5abbc8a8e01d400780fe5a62ad600
213	1	68	\\xeb5b7e797769d752986872ee959838588595a6e98b36fd92e8411fe453acb419a91654176436c38d82081b50d34001a8feab23af9a57869f364c8d5b14fb270b
249	1	227	\\x8a73b4e959cb78db2eb5e1bef61c8888d31338d85d64d8310be21477f668d5311b9456a24a79518d807c0d2bf85f8299d1f0996139a370a12511d6d45a847700
277	1	74	\\xcdde03f7b2d06f5cebd1e2f4839fa28f070a4924575458d49d0415c3101d96eaa6196f32ec34e7973386c7f7e3d1b688ef9d38fb20794c463eab8bc9ed89cc0e
324	1	278	\\x4e878cb6a9236068b93a332384d9eccac781d37af5703eb1efa765b83f87caed74ace952037fe8885e0d99cd4ca0ef391e18f8105f3443664a070568bc8e2100
356	1	76	\\x641d2bd6203d06d42f85101d7118c83c3565e05f0362d42092dc42b465d123ed07b11835ef546252af31c49c38627a47510c91ddb6cbd9f41c19ab32135da103
378	1	219	\\xf8ebe7dd9320255cc0018179764f64ab43208ed89cdecc6af5b625be773dd907122ebff624bd4c3b2a3166e0cfbee9b6fb1783a709334a6f96071f92df336500
152	1	165	\\xb28725b3663096c122c3df9b0e8d463c2030b7be964d5840869d7a9e612ea79767aa89677c1cd4fae13f6b759d1cab02da5a06aac5d2cf749d9dfb7c883bda01
187	1	369	\\x4a5f3cdc40c108735785df154d8da781d46b01749e2111b313df4bbd391ac93370f2959ba876c8b6eef1ffd543bd0ba909bf64d43facc4e5a2855a491826cb01
231	1	359	\\x9f9e2220b6098cb965a733d1ae4110e936115437ee7fda8202f7b6f7b00c58d2ac3e192ab6d4bcf2120c4998038af5a583c50df82fa90731a0c0c80b3ef7940a
263	1	294	\\x28474e10b82ca369730685d1544f88e09657253e351a7cc82a346441b663200b92ce848f0b7db583b92159b18354be48c538a6193127ce019987dba76886190c
281	1	336	\\xf4870eb74fb69c7b1345ead71526e4046007a1e02205eaa827a7f0bb2c5bf61b4038f8e5c5ed188f6b521c9e459f9868d05ff23735f4163f4453f51eb111e209
332	1	207	\\x933b955f0bacab449bce9cb22b550cfd67e765afc5cb50295e8de4e29b13f7f27a682a60c3f6111a5ae3ab77157fe44bfa5382b5680cd2841f86f0e1547b3701
373	1	339	\\x08d7e08a1017f5579bfdf727e3154596335499df3ab61c3061b16bd8ce2b6356030878e0ba0c2543166c9bbbd064c1e2f089f48f3a6ec6a0019b799f1415fa08
384	1	255	\\x424cf5ad0f74ecf6336a6b24ac71305795769cd359637c0cfdd85f6d69813a648655c8242b493bf63afa989f732a98a5f1b3c096a3acb0cbce9f2749c268e807
405	1	197	\\x622b672735c29866e1de739d5d45f85d0c67e562e524b994c38e6fba74488321528b5c6e847d087e3149d797f4fd21219b545109d78cf5472260fe4b11825e0d
419	1	91	\\x1ba43927937ef95525634013d5ad7e3ed8f9dd9cc4ed614fa240403d00a19b34155d335c474d86f649faa420ce42b1690af2934328057a667808bbc2da54ee0d
153	1	365	\\x4e16d9f559cad8f98c7b1ac9d136b2a60583b6bb19f4499fb05812aea9245915f9364212cee2d0a0116ec43f4dc3a42f04816f8da888998dfb43f87dd49d3f0a
196	1	161	\\xffb8655e1da5528d3dd64281f1dbb50f4f7e3d5169690c6227c94df6808d271f745219c9f5a352df9a7ad97c4bf448b0876411f29377a63e7f4c69972d3ab907
218	1	377	\\xf6922452262068dddbacc14da6c672375e7edae74513753760925dc5c485dd80512aa3c3e4cfeffc7c5d97cf4e18e2ceaaf80ebae4794868c8a65950a2589401
264	1	332	\\x824e1624b00961dae51a9b2de642cf031f93fe40d45055a448891cc5f460edb8671b33e3d11d3b4c34aa1e2848fdd19e09e1e176c1ca511e2b5fc252d6b6c80d
286	1	80	\\xeee1b3ea21651761d2b166a4151e659e4d86c6325a659d31c8e720fc195cf847a76159c916be1e4174765ff4872b57a3cc8907596c06964998268c852b19590c
306	1	2	\\xb3d5c16b88a58cd6a15260c9e3daf5975f9208e67ea99e2de1e79326e14bd03650f1d524d292af1b6e26ed35d4d67a4c48b039a5ed371527ebe4fad9e5506e0c
319	1	229	\\x00352af37bdd5c90ce31d1d588d031913bc963b15ba1e833d2f3a7388d6c7010491579eaca309b2d2dfd88bc70f6ed811ba8d7d9278b427b4dacdac6d7cf5201
331	1	179	\\x1faf45d7c42cba5385fa90f91a64733b79ff112da741af496b8bf3f86f3815ea7617a7062016e823c29efa8d5f65b1ebac688a413fec61ec538323b04ea1950a
359	1	235	\\xa34e32f90b31fb23092336c3f198c792acbd30ce1fc1e72ef731ad0def1b2d30a31eb00dbc2536cd8e13987c3f7af88ef0a6a85d5ac102f6f3369c6bbe8d7400
369	1	397	\\x00799ea6745184ba58ce0adb792a99b31d63864aa5335c15b390706b7bc1b85f0201c052d66b607e367ffbd56add363f9fa0c659fa7e3f3f9f1b8d95bf9c620d
381	1	35	\\xedbe401506b93f5b89391340275d1fe5849394fa4bc5ac5b01be4db35440add9b733e484a709e39bc2d3647c2d6ef5642ab9c28700cbb311d00552ecff521604
414	1	122	\\xb94a4e0133b2750df891b36a1d21ead999b7b26ec58d8a3c0829788c98cfb05ca02758433ced8ca3c2a6b28662f936208e2676ffbbe85213061970592bd3ae0f
154	1	73	\\xbb4bb7c3ee693efac9501f014cd76ff3748cc85b9baf25445eff3ebe73cc2463be059eea19f74fa0548192a4e45617e39c285e6d00fbf48161d22132ac827008
192	1	413	\\x0982ffeec21b77f549fdc287087db0572210e6a7402a03755c897c60767eaf95161992bb771148e56bff543ad71b628a102109e14cd802e28124f873f85fde0d
234	1	379	\\x1a7c770c2dcfaf40dee769b1636306fd325489fb656579a6a0733f53381dbaf7460f884216c9d493411f74eb04cb2cc52f2451b83e0769acdd77e5ff0e211404
266	1	231	\\xc617c323af23b2f9f2003f0aa709572374c312c64f1017456e0b308e6eb90370fac2b0c6eeeba8ecaa9a24e8b13f473581294d602315119dbfa4630c7ec3d106
312	1	326	\\x349951483cb941f65ded2da018e37b29e6a6939ad3914e2ce9bb98aae6eb07eeee9a15dfe391e917e26b0819910f410ba522d10f74d3068955800076359fb505
354	1	1	\\xf47d55152b94cfe7d8a917142ebaf5bd44015a5130e96c615e7d96540e14dca01e7fb0f2faad387ee85d61c622247eab66d9c2d5c10a7bec810bafe9155b130e
423	1	92	\\x41a389b644577a52a3c597f2fa0056d5b52c79037412cef7f7231f2572521887dbcac907d32187e407937aa78485be37b7485daa13e36a3e0c7941f47434ac06
155	1	78	\\xad6cfc39b0eb63f565f1ce2aec037cc7fd3c5defde85ab26e896173987d46a5186f7cbfb2a01ff0c828a0cb3f7709ef2535e4261530b4c7c27484c9f439a080b
189	1	120	\\xa65134c09953d7ca278fb63c7a1bfbc7c7565403c75ae36127568d59918689a2eea29b8d0972709a556a305b6567bf2cc579d993dfd6da910284cf3986ca870e
217	1	6	\\x6a7707596ce9adc06509e5f321f69b09df435609b244138814ccc76def0b7b1b76520ebaa2b0a1712e3b3bd1a7a33e5a6f89fe4b20e2ad0d525a2c4f1e2dc500
248	1	81	\\x77371cded1bebc6fd3727a2e045080d9457a7d065216df805a49bf86b5cd57a97bd17d1fd48e8f17f2fc2df9204a4209a38160f02cb4d199439067dc7fdb540a
269	1	324	\\x7c90b68f8a862a3ad6f6ea35126f66d746851b50b87b8d2e75d408cec7d25df1a82004c68e4277454c1a667f57e8e472e823bbd6dab1f1a0aff8a219012abc0f
322	1	130	\\xe50bcd4a048429720a640747a3b593f4252ca1b91b23cc26dc4006a473f85cae53e96ca548cb223f0daeea18f7f1605dd16e155b9905ce52d9ba38cd9b94db01
335	1	325	\\xa9ed5113171911b566532965d9969dd1f5a2e3fd6efaaf444e23d66914fce0ef8566e619d23bd90656546be2db888c58283c9fdf0f1d615370e6239b5cbd990e
389	1	261	\\xec83c5d09788dac9bff2ca5fa4a027770d896aa0e3f3daf0bf2e79506da593bf0c87718f12972cefcde5a44bf0b851ab6036293bfc78c6b2a621c73f8a3dba06
404	1	141	\\x64105d1a97a3b0de56cc51537c2071aa04bc0f1ae5a2043eb02885aebc63cd84acc689099d81dc4a2c8914ad9ca3d19d909a4329a5dc52b6cc1e0516ce6a5b04
156	1	5	\\xc7c0c4a2e2b87092c2734c57a16b2633e6434b25ecd3e297cd06c5b83144b87924a300ff2218e1209dc52fc633a7237750e84f1f3b4a7f241171173d81d00406
179	1	212	\\x10bebd67147bce604836948f167a56439ca86cd10087ffd25604cd9d39aad584e1f8fd4b5df8cbdbfe97603b017b4f6a5c9ddc0197c1388906ac31fd0dd0ce0d
208	1	346	\\x639707dce998bd66c241fd920c21da0e9b107777a6df7e042bab95c63e2b7acddac5a4b16786c1eec06dc8be8acf7323af6b80fe2de2a550f9d86d56108b3c02
235	1	203	\\xc7b24b0ff1ded84d907bcc7e65e2dc0978fa1b5d09f6300cb1ce4a0498915c638c798e5f4200cc0ba0effbf4f19eda0c243454f425eaefe59aaace499b60ec08
285	1	45	\\xc2add54bdb5043fe81991c94098f7572552900d671b5861a3866336678f520e61589e99bf27972b4f50b1965e8b72a49a7b6ad0ec504ca08a1a5581cfbcea506
329	1	265	\\x5647bcef2d0229a0809d1bb32408917f7d0411229abc320abcb74963847d7d42155b571e934415624810f37f5ecfa33f1977e75e53d29d5e9ee85f75dd33f80b
376	1	112	\\x8f6aee0391d7642ded92c6b2423a8e6d124a079056cfe5596849fa6e43652044887abfc18b432ef90617a36497f6b567d9040f28d923882f66e4161e9b7a5605
388	1	323	\\x0be6ac45cb6ed7f580368678446a47a8de27d806992dd480efd4144617599cc209d618003e86bb31efd0a72c31483a0cf06018463f7448117b9c6e9a1e621b09
400	1	171	\\x38bcf8d7989fe65a5abefeaed24918892845eadd30726f8d6c6f5bc118e7f25e3d120eae1d2c5dcfbbd2008b9f7745a9a904f51cadb6c6c4cce793f2759d970a
157	1	205	\\x66c4e05d0351932d2373e5b21fada74f319a1460360db29f463510d785e78da889e89339dda4a4381d4d9a610763cf5313823b6e7f1b0e5fc65f827650dcb404
201	1	209	\\xee0174d24e731365ccd5cf5cfc81383e9ac70b1124cfc3a3712e687e9058301caf45f80de551bf5a65d27e45e1f44041e3586087f50ee458f78ef2d87c0b4505
233	1	414	\\x90a815cc6203e96064835c19d420a66cd60ed760691bca579d3bbdbb3214dcafeda8a2612fc2bf4e4b59f42e8ab4023216b8c6818df5d97859d27529e2f38200
265	1	57	\\x9d5e5f2cc48b5e2d99d9cc088f30c5241362e4a41ba695a6393a366fc340e398a44af25905d7431c31580d51b7011bdffd30b2b6279aa535a35a89b1eb4c6200
300	1	275	\\x569a516ca6468474a56ae4b7c043e27a49a6b32c031ea6c4b1005391033fe419545d36c605c33618de7484c7631a733d49df277789049d974d11ed11639d4a07
399	1	285	\\x697e7e3e44518a43108f3dfd680c14deda97fc60859e062423c4aa333b960297786d7411491cfb31d7295912ea6c9914b3b47fe2a4e717688548fb44cb934e09
158	1	10	\\xd17c8f634240715a1beaf645d4b626e28011027ba0fbbf90ae66dbbca22991928d2f48cb85d996072a2861765e66043aa9bf1fb2cbf81d05f29c4cea5177c80d
182	1	230	\\xf6e9c7d60ac47aeab73cf9197a1cb4be00287a899f71d31b60a567a84c33a98217e6d6de4c103aa0903dde283d42c3615ab8e68b4c572b17b86ceefe597dfd03
223	1	368	\\xdab7e661bb7f6753454fe0c84116dc0cc150992706e4671fe9aa6cebef6d8666a99c85c2c0285ea24f00a00a0634dfd9412731ae09d1885787db197a6c2e8b04
256	1	366	\\x80f0c4d79cf589be55657b3dbfb9495f56342594cf2f9260726f9b9e6867036d94f625006d7dbc47f3cb684972905175bd01f3c2cb9ffc86be79d83a403b0208
291	1	123	\\x7a8722d0e9a632a31c027367be77bcf3ad324b93c9fcaf681dd822654b4d2f9cfaec53707c84518052364ee98adf91ae94aea39599f7656954802368e47ef209
317	1	149	\\x2add1ebbc7f7defeb54b5b0f7ba136980014d134e51b92da787de76494ce7251f9798bc68b50a158f85931b7d513f7ad53fc940d0199a8cc2656c7d2ea6d0204
343	1	393	\\xc32d90ca557076cb20166cb8cf127e7eb8551a0fa7dd3fe26180d0ac3c1941f57594c910ef65deda18036f2044df184d37d5df869bcbf7d318e7cbd467d2540c
355	1	34	\\x2ba32b6fe2c0b9d98eddab1118861a8fe88edde3a0fea123a30e5c5133026d0bc9f8a21cc8bd4cae2defc3f1a8d13244b1fc5ebd6ce308e11473eef0c9e0c301
374	1	33	\\x13785fdf15e9550d3c2d05f3c9d06a3b9c29b0674eb10f6e5b052b5d14f25567d3cefcca0fed705227ea8a0f1fbbfccf48a175f47aeb17d5886c4cc604be1603
418	1	23	\\x1fe1e9b61b1ead3f408bbf83876a664ef8cb6e49af437c68a0a222196e3d20ddd4d765fdd45d5d26e784c64af6703c6a30fd4cc6215080df78b03922722aeb03
159	1	90	\\xe5bcc7adcdfa76bcb9c6a268188da6d40596943c7729d5cab950ef113a7610c3282fa2d4e897c792de328691cc83544df54933ea5d0a4f0b58b3c5584d261b0d
193	1	48	\\x4aa834e2b966a5d8cb2a3866488cd49079227de16b12dd7cbacbf821eddfeae0ff430c3eada6399dd52f3725f8c739e54621fe3c13ef42177252f8cc7d038d06
214	1	196	\\x7b3de910fc5f9d1722d2602d422c4f2e4762461ad47adf7f4abed5dc1625b1349a7c404c0f5188cfaf6ad65a84dbf52c80749aa379d1bf093970d7f20a294b02
228	1	343	\\x573fea5d9617c7f8ce3866a6b695659a7dff773b6e9023b378bb0c6ab6c4f075c4895c83f42bcadb1a02edf9a6acf9891c46aa08a906830ab181b78ce798af0f
282	1	75	\\x5b769ccefd336c8e2bcb5b387044c4f54d9fb4772cd022fdadc63d53bf166357e10984a58e685e1d0fb6518dfb2d15e6cf21b1faa69273778c6fe8a452c21c0b
297	1	155	\\x0f924e077e22151c9ee6e2e07054204357a5be9460d4ba61a5e945ba9c03ed792dcf300356985bf2329aa8b5674849fcb536c6c34eb8cf7e6d49d34998551a09
320	1	371	\\x54fad0bc54a8ff8703a4b738d659abdcba16748ce94bcfb9563de26aafe764f45375f444305f9440cc46f0bef380bd499e4e62d4590fa147e71546e99d5df80b
366	1	391	\\x39f61e4fe4abd8d27e95166681fabbb3f9b3c30b22591e03fa83b45ce7250df566a6087d834c158996bdf2dca97f08e5092385af6ef9443e8c8e4b5f8baee604
382	1	213	\\x2194ce0b90d987dbf352af103c117d11dcd394a935986f77a0a99356fc5206bf4ea731b6191e56d9448255e1f0aecf013b6262c0d76d9a226379e67ad08a320d
395	1	12	\\xe1557ef21c51679f3cc5f0065b17d8d68e5f5d4c0a827c6793d25ddd2ec381fc186f59fdb1fb7119e97d2d7974837ab013ce629268310fcb449a80f2a5e18f04
416	1	183	\\x862ba0a8aecb33b0278352dcc174b68c377dde06b64331f58af900113c2959a5da1bf01e3c3b8d0948295c9a36845b7624c1a22ece404b4249315ce1e3b08a0a
160	1	41	\\x09912ecb1ad3d6551392f789e2068d42ea34c567c95742c10c1db8c2879815690b2f452b89f45493e7a9411ef867148c63caa33ef91969f21737a342daef950d
191	1	94	\\x2b0b33b90b6b3878316b62be2124c86a8798969a1a2386b829dc43c3b8da5f7552abb9707ac1293d8c4058172b7322b60997746064610fdcffad00730cb62a06
219	1	363	\\x5c83acd04e35849877928e27a5a4475c05a4a854dc03c2d020bba71481cb8baed0881b84aebf6166b941eb802337aefab81b73136a5c5a9d09e16e9a28c97e04
254	1	101	\\xacf3f2840e85a433de03571ef4ef8baf5908fab5339bfee176cff9836a144db42f323f0bf3d4930ca484b9a7976cd147ddf2b152ce52e5c317067e020c521201
310	1	87	\\xd2bc98acc8a4da79c76f097553aa0fb8fe1a982c2a8f1f77d5d5d3c83031e9e65b9072d8bdbfd1a6d8895301ddadfa42ec69941311c23d71ca4680b807455907
323	1	283	\\xb80d7a3e25c4375913c7e0fe13b2281b76f0207238f65d0667c40f92bdbfa1d1f60f856866f404fef2ab9a3b4d8c01b73bb09ffa3707d30866bd8e287c92a10b
338	1	11	\\x88c2839c46bc991197551022ef6c4bb8f392b7689b0e9850b69dabe97efb9e81ebf47f678e0ec4e488773acbd5f504df4dc7dbd159636e1fa44c89e5d2e43a00
392	1	39	\\xa68f0eff23687bcfa5bc46c8835f94824bfb692d782ae6c17ab985b3036712d9fffa5eba64d8bf7d2e9b56554b42355660ec6ce810f809772906fa1b6cc3e80a
161	1	273	\\x1223d68042a0e63fbc12236e507fa69ac262c3a4d2906c8955986a9fe7dbb25a7897a4cba958776a715c8556e7ccdcd2754e11179db1762133d156573fde8c06
186	1	84	\\xb2b0820a1eb9eaa8bb6b688d4869425f02c9fc06c6be83f7f0d61b734509b9a92efc0c379c068781bdb864e65157ee9006a7af4bb01d49452176d56c1c188303
238	1	384	\\x3cc20250a377386d4ce889a87e7880ddccb4ecb1a28696ca03e64e2e2f3eb34423649b61f5a314ceab1de1da1f7ec314c18ff40b752cfca176be880940b0b905
260	1	424	\\xcc261253fbbb67ec97f1b1154402aa1eaf4a5422539e7edb4413570e0a9623b206fe12373915f9a7249ea043803fe0183b5d723140c1cebd5cd7ca80f027b909
272	1	249	\\xf3e109f0f328a951efb8bf98a71056b29371ede50f035a0bf0f5916bd131a939b00aa2716f872d632467235dc5a22278de8c30460585188383a2fa9592baef02
333	1	309	\\xa8640fc3736e5959981d91ec9766f403d0bcb113f03c57375ed25710d57cf6f3c278230f3dfcb74f933a6bf938a62bd4844d43c269cedfad59a8819c9bb6b60d
349	1	215	\\x135ccbb235f4b1f6228680493b2e77c7fa99917149313ca6b42396c1e02d4ef38dc1c8d91c6010db6446a39b123a94fef657b1968df9fa228525f651c71f0c0b
379	1	60	\\x27083c30cb57ddb53aec28448b081f8bd946c1d6b4bc2a2c75f729c2009ea9b6fdfdacb2c13323e30a9006ec94532478d4a0294b82fd84c7c6e7dd9b63b4af0d
162	1	280	\\xa76d3fc104fad7cefdf2d3013fb8a382cb225bf818a3f9e1c122ce3f3f91ad3b2b47b96e52d736adb7c4f4341dbb59309756d4dcda11950c5c0d01d7cd23df0d
175	1	172	\\x4bc5c2d3cd990136118e3d37b5ad504b6a3375c35d7daabfe302e200cd9ad4ffdef239478a5615044014846c6fd936c8763a5aca1311f7154783de80e29cd703
206	1	104	\\xf82205a3b14796ae7c2adca73f671c981fc73144430039994ddd4ac646ae0d0aea56533947fe35477dfcc6934b787f3d8dcac82280fc9d08a65f05d8b0536a03
245	1	340	\\x3a0f5e7e325fb6b66a35134425f639311dbb0a9c2b2bbc955ea346efe3283d636163d7aacae40c758b689911b593f26622065abaf2bde5a99ab4d4c919c8c406
267	1	148	\\xebd1d7b7270b6a1d77e162649bb5d49ab9fe8448b3ca843e00d20a9de68cfd325ffbd1244d4649b624e3159483143f1df6245860ef5d3a82741c6656fbe81a0f
268	1	160	\\x67a8bf33500321c825765394949fbc161f955f7d98188a417cac6e6f9849a7f5e7fcd8b94e055235b63bf5239f774068b14608ddd1a6097382c0ec31460a2c0f
290	1	168	\\x250acae6c1859aba99ad2c0674e72e7a037063546434e5e11436bc00e93fa263ec36674c9b5691e589a61fc70332a900067fb2b222e184b3eceeb263c946ef0f
348	1	345	\\x86865ecbb229fdbc66d6b9c45643b67c890b1a657b3c96a776491d95e3b92ca7f610d058198233359f3ff5a20d65886244adf242f56d00df2377a1bcd7300000
360	1	14	\\x9174e5aa704132d46201fef3ad172af8dc2a18c250e31d0df5166be708639cc3ff1c64b41d828ec6115cdcfa7fe98a68578b533ef74adf46bb227d3b6cc2fc0b
163	1	109	\\x484bb8f380413d59d3e96fbfc951ee3a3fd062d6c0e921e75be85d38ce18ff766a8e3d74ffd1943b0094ba9eeb2a86996572b390e9fd00cec4131660c597590e
180	1	264	\\xf1a62ad655f39543594ee5fc20fc2fd39f0ef6440e83eaaac3e0ad82219c5164bff8cf1674c7de051b9ac170df9a616d5c361727e6355f6d4a17a1a8e04f4e0d
209	1	98	\\xdf038985aebad1a54f7a4b66d9e83e40c25af9431aab4d919beca35b43069f0397583d3dde489211fbb8d20f1a03afcd32b87ff52b39cf55ed4f8078cc5cd30c
232	1	7	\\xaacc9214fdcc7dec067ce44e70f36b9b47e7012be6b8e6ed06f42eaede975f31e6c15311b740a7adc9ca131dd0552ed1a845b86b47de66d3c2b565d1d639e60f
271	1	239	\\xf534e0e917aa429aeae33d445723f94346f33df61d3ff395513c2861f34cb6effe0bca6f19e5952c3246033b467e82fdca8977e39fccdb815d3739ef6bd0e40f
283	1	318	\\x9da6880b6290316d415b4caec6a2b3e164ac1f3898c0ee3ffe2a6466268dd7539f019e83325e142e4216c76c51f15645261f36f18b45ebcb0769f072b2155407
314	1	43	\\xd290a0edb186b8938ab26fdc88e77be59e3acc5bdcb6cec38795a3e7addec18aa8ad3ca1fd93295fd2bebb5d4a669a616da75decb068ec72b388e7fb0f812502
340	1	108	\\x7d021f062558b758b77be1af5c0e9fbb93714e4be34c07106f5f056e46a307a89464b22babe91ccea5e8190bfdc4c611a9193bda5946622640782b12ae2df90c
352	1	31	\\x6c99102bc9face210eee1d2095aff1e659a37800639e8c55de5f21073557d94f2445f05c84daf28d2f73555b2c2943995d54a6c6169b8eb25ffcaeba324a4c00
370	1	125	\\x664e40afe978cb0498171de7de58e0430e7b763b5d361a0da20b0c0c8cb74c32b827c9c0153229f26a8b10184660dda0ba7165c7589895eb5e0bc16eb46c700b
383	1	400	\\x4a9907c83e2572b29e918fd8f9901940c2e1220206bb9e5728bc4213d5d9619c5f16d113f23d4ce35cb166f118f47bcff2b8c4a8a95f31741489c4003c32220f
412	1	355	\\xcb33d13b12ec33147aef7e94f28ffe7b16a377c909db759eaf4f3bd09c7176b8cf2cef84114877ae58d996ee8bbb5e8fc0dcf64ed0cf3ba56a591f1c77331709
164	1	29	\\x3e35d54aeaa6185439fddcadc0d7fe1c1684e933f61c08b31ebc42811bc11b0e733be882cc169051575c7a0eea6d6f76dfbf3bd1cada61530046c6cf75e2250f
185	1	83	\\xee8801a6cb868870d7fdb6d80e70a87d9319fc3a8c922b623ac37fa6c476323a4642060c4860bd158f3fe5e86927e8ab40414213410f0f514a05b6dc46c06c0d
222	1	200	\\x1c8423a5d694320a2b545e5476fb9d2d9bc511f57c1d8927443360277055b666b449bf178c7ddf1cedd309c9720b3441e86e40b8eb2c7dc149d2090298b10c0b
251	1	133	\\xe701c929a245fa66b3fc194eca24497cb8bbcdc8719760f0b0bb39d05a066199bc9d04389e8393d86e4a105896c163173e397f10c6ab477438085c5940f6c80d
303	1	70	\\x834e0eee3d5d127745d5b264aa7a94432b47887502f00e9979a8cb5f60e5425f80ecca1abfe119a2cc8f9cf70b620df926ab997fec2a8b32d2e72865f2d99203
318	1	334	\\x1c355d0935f91b048d22a037b63e3249556f35e6d6b900358204145bb19934a0c4383292b13a15375c893473fa3fca229d5127dec04411c6b4c7c02ec343fb0c
344	1	95	\\x49b25da5689db8e2bb22d0b6673c5e1e3e1049f97805561787080e53839fb8d01b5e231a4e3b239613157eb13fd2db1a50aa2462b509b1d6b7e88d836f05ba05
394	1	143	\\xa8e45834e1c7182a31a80df80d6baaf601f7f94a28b69b49f52da0a80b751b4a59dc931958737c83c59ad22b9064a7bac47fed458c7968bbc25c4c238cdcd207
410	1	42	\\x5fbd2692910dd4f450cd82af679a342c635bb2ab7e084ffe1b71603aeb31c0c004d99b491b9a15126dffd227e4da263b405788cfe53d93efdc032b016cd8ae09
165	1	418	\\x3834cbb65f314c3e27ad207751648767c18f2416897ee113804b7436e91b0557dd8700980c73f564776050991ae14128933a0fa3ed42b1cd5774a76be5950704
181	1	361	\\x6192cc9dcea88ae384ff9040f43dee1e2f9c426e18d116103a6e10e39da1287cfdf7cf4792a72b26678075c830e2235935154e5dcd672d4deafebdec7f3a4e03
211	1	66	\\x2979032c5e6585b128936671781891e9f2db59cb6f212e0f488437c4a86ed561babff93adb9387a763660700d880626ce02a8f1b5386f051e6d3ee3699af4a03
247	1	177	\\x56f20b160ffe2185895296404855aeaea3f5487bf1cd5832b77bd595051c52abcb0a88ca3ec2afe477b10166991e644739bb05df56206d338d867ee303cd7601
276	1	64	\\xc9cdd4de6cb3de1e44411affe55e089adc036c54772db99c72a783fc763757630782686e980a30fe933a321503eaf9ca26e80ce3a48827fa26b198d662eb9c05
337	1	380	\\x68440d472a65da8ffc251c007ebd8b3f258b2769b5d021263edb285df12d722dfcd00286e80826c22e5c04e30e6e120769a413748cd11fcc1a4369695136f502
413	1	44	\\xc8043a137bacbd9d442a390efe84442334ca2f627e0794fd00711e64e8d6a25dce76b4f4fb6f8890faeeb12463eb052cf39ba5056d30a2f63981a38a4c8e1a01
166	1	422	\\x822db3389d5246830cdec3a34b39df5a0f559784450e2b309c3fd6e9399c073ad4233f60b1c50e67bc896d46cc5eef295712c18da67bcf51f86db955176fd100
177	1	173	\\xd092f785ed1170f47794944fdedf5bcfd1585be7e1fe8124e24d8ded04612aeaa700217e16f190d11c9f8e4532c96b32876713fdefbf958f622e610a6b4a8700
216	1	192	\\x22f0f8132c3cfa42d3e233941674126f962954c1e1fe5b6088ddb6b619d61689badcc1df01840e5a54c7ffe2df64bf68dc74f5bfd068c4f342edce6d9f96da0a
257	1	291	\\x163bfc9c744305bb3655a76b3c427794cb917f91754415cccccf78d34bb056144a57ce96353a37d5f2e57c7b5e4ec53b8a4827a274d5a98084a3d5f01373c902
273	1	268	\\xda1ff25710c058585478ca05153e113a65eeea3a95e5c870c3a006ff4c39fecc3881a760f7171744d9b3d646db474c0d8f6aef1df9a02d176b59ae3291d0f80e
301	1	386	\\x2650a1d8baea0f34d56eb59636a3a8886ba649df22494be56ceb95fda6328f596e80258b169b9b05e7e53628370ca20955f095d2dc09a7c036fe1b5b152f9700
315	1	54	\\x51e2f294b17cb24e7a4d7b37fb7b35b5879d5dd0a61f1f5dc89b57dd7086e69cc2b30483994a42a02fc24421de90f4907722433b6b679393e82671ef1c97cf0f
327	1	25	\\x55ffdc8bdd302a40dedcbda1e7647b09de17a8a2f443162cdbcc0f8e781db10977749d481088c2736f8e50d6d08aa8e675d6103dfd9d7029670161e7dce7df03
342	1	307	\\x5c148a67dc5e8fca787694e231dcc0abe3916917a74cdbb37d56255f30f5f9031373e4bc2f0dab3fe7f3ac894e22e9d2975cd4e0af97fba2415cfd691bd7950f
361	1	30	\\x7716c917db1fd8444d6e1c74e5085bf9fa6c545d6ec2f38457b27a2967bd2a0bb7a0f045a5c062bd6858eaac9dc449defdf3e7a77ae05791c04c1e9235279902
424	1	251	\\x741097a90aa3748de4db7a5da874b43978ca27053ca56efbbb52130d6f6c009d101584b94d1b2852425b5e264913d65777791aa75c7eaa68a7ab6f87d6379b0f
167	1	28	\\x27c52c841ed145b02d30e384501919713a5aca5c1739d8f9c63be304e27f3e92fbd4047ec51b982ca45487cce5cc34f3e6ff08f62137038a6d096c6bfdd0ce0e
188	1	223	\\x8a29ad5776a36665708e585756ae4c2f331ed46eca922c48a328297e7ac8418aed391b45091b5b901ea18edcf30f38e6300ee28b8a0cdf56a4abc8f2aaa49006
221	1	333	\\x887c8d83e673e56966b7f30f72cd6d8d80968be3cafba8ebfc2f2435ed4b336a8b1263250572c04c6479d65c71c18aa369052919b1c23f98b4eaa2a895439f04
255	1	322	\\x4412a7655ab01cd8b67dea4ed7111c7bad897026676512d1bc56ec17f9bbf8b26c9e555804282e7aafdbbe4b015c42a9bedd4d1e9a409dfa4d39611943c9170e
288	1	58	\\x07b2e60e0557a2f4cc086b10ce0e82e2b702c65f0da156f4b69abaeafcccd4e00c4759fc4fac5e57ff4faa6d51bf5d0ef52d4555f6d9fa60ca7fcd2d9c9f520e
307	1	222	\\xd5defa5267f6ff4107dbd9021b60759d6597a36ae5cdd9dce057de0b34275999d90626b585c3a4d3390e7af7e923c33db03ea6764f7479706995f06f2c83ef05
341	1	224	\\x4d0ff2fbb39d4ef2e33869135321c3ed857a80ce18f4f08891b79a39478160fe2d654d385042a9c046b00e8ebcc98a1978555098cf86f8a374fc050407353c05
364	1	93	\\x772dc4f053faf02c3160817902f2d2a6d52b1cd4922941063bf7f168cfd486f3932f337c424075d368ed5fc319f40148006fb224ae32e85a8c371ed588088007
396	1	347	\\xdeb042db70f16f4e4911f7ee6bc9f744d85deaf7e333712d814eccd93aa813f99c7c5239f187090839aa6ce805edf1787b3a38f26875be7cb5a5d71db87ede0b
69	1	321	\\xdf9b2ae3438abbc73e12f9bf4f8f15f7989e812cceed09ae1fb76a6eb109155d885bfbdd81661b7a4218d2d91b7acc0c54e58aa892864fb622115a2ab1fcb803
79	1	150	\\x7062cfef95e4011154931ddd4d89f2d5bd21b1210d6c201d0d7746f088fcda5764d4d7025c556fb77a366609edaaa9066c3f5b591967a99cd4f678ae76795c0e
90	1	247	\\xd3a7a2d2d7295e635f6f5b8c0c6109bd99397b28f503a5ff8da7063ec843fb65868ef34681ee46bc5da11d3c7823f23afcf79ba9f9ebefae92ffa6cc61612b00
101	1	154	\\xdb796a8e571b13a5c4ed407c960e6c132ad2d61fcf97c1468fc927c24718f5998017b822702550da3fce6a153cb232a4a84fe43a914f2964e3b7e6f87214b101
108	1	147	\\x0d937847aff94573c41bd4521eb0722bb117f468397cf730b7e02f06d72e7a594af4627e97854af015f69d6b0228b338b3dc1db807fc6c8ae27e14ba786ed503
116	1	399	\\x70b5374e401c4d39236c6e045aec10a878a6f05392bd224b290eb5c3d58918823dab7f28fe33de084b97e3559b9a12f373f4af42d7cfbb223e409d04c078c802
121	1	329	\\x7537e607b17a96a97ad670e8a0bb4cdad609965bec1dc442c56d2d8a1b2db813f44d95674308cce8413746e5ce460a1bf335830bcefb297ae0b64ac7cd569a08
129	1	398	\\x37cbfad6d85fffed475abd9b9190a38415e1bd1fb2178bc4ca33a3bae159fec97a59f293a87f0137019813507c10da0aa93537ca2bd8bd6db7d03e17201d2808
138	1	17	\\x7dc540e29262bc52343ec3389320a73b0908b121b6247eca2ecd3cbbec3e5ceede17db2e46a7b0f7581aa1d3a51717e247ca9077acbd38e0b91be5154e4e020c
171	1	124	\\xc2b3eb233011737e106e2968f785c3f3ba22236d127914254144faeeea48ec043f62117d0667c51c5bc0d52bf0f67ce7c976ed653487867879994a9a4f370100
207	1	129	\\x35647702b6ddd13bb813510dbd46498538be974578bf531116c4fa55f564d78b4f95272997596d38344417224cb8f2c0fd8222e55c9308298731fce88141ce0f
239	1	263	\\x200d28a86799f99e2f2e66d20ffe2d0a367818d068330ac66b26600eb7a01822b1ef1c2eb06ec383344865c57e2c90d43c271473f01ad0b95c3d140e842cb506
287	1	242	\\x96c77af01f93be8e8749e803c3a1baf80fb73dbba03fa671c9cd539b946d30d9d68290383617ae74be4f29a8581b3dd96271741edd45a9e0c13d7e1be055c007
403	1	136	\\xc76d930c5e25e30b74eb57db1dfee171f8e084c33b1a853d492395d42ee02838570fc85e0eac191504ae98ecbae8ed5d55fb000bfc0ed325f2d7c5d5afcdce04
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
\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	1610355050000000	1617612650000000	1620031850000000	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	\\x254979e46fb63853c0cd3a0e81e13ea102fa808e694b4f44497b0b7fb68784647c9de7780790726214f695ab6e838875a58a492b7612ecf4a518bc8982e7330b
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	http://localhost:8081/
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
1	\\x31bbb9dd0ba51c6c31cbce9bed40ffd72710c20db2c7be0aa12a18fe63e047da	TESTKUDOS Auditor	http://localhost:8083/	t	1610355056000000
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
1	pbkdf2_sha256$216000$SyXgWvYU0OKg$CRwoL4aGzYDi31tTG2IBPLYCv3Siu2XntCiLcIFrr2s=	\N	f	Bank				f	t	2021-01-11 09:50:50.967457+01
3	pbkdf2_sha256$216000$33L7PdumWBob$5hHTBkJ5ALEDCmCtJEK7GikArl9rkI1xSGNnd8zVP4s=	\N	f	Tor				f	t	2021-01-11 09:50:51.141579+01
4	pbkdf2_sha256$216000$WlyCCt0HYlpG$cno6FtHEQmbQNyo4TsNZqyVbAc34KlG8zWEdary9omc=	\N	f	GNUnet				f	t	2021-01-11 09:50:51.219239+01
5	pbkdf2_sha256$216000$G8pu48ob3lfd$9lBLEK2Zbl1BXBw6FcghLHlE41bfRj6qIv392AOpljw=	\N	f	Taler				f	t	2021-01-11 09:50:51.297608+01
6	pbkdf2_sha256$216000$64Nbz6qu9XxN$Jv1JG4ngvdTBYoTOcT+QwUfNNN3FyUtCc4GpvTU2QJ8=	\N	f	FSF				f	t	2021-01-11 09:50:51.376256+01
7	pbkdf2_sha256$216000$FQopmmKlVj70$dITzExeV9dSbzuDglvP7PHDDA7s2oHuE6qKgKtFvCuM=	\N	f	Tutorial				f	t	2021-01-11 09:50:51.453579+01
8	pbkdf2_sha256$216000$wPbrKqknUM7l$XIAvjNgcVZFghtUt9ynEnf2AZFe/DTgPBzMIHEPM8mY=	\N	f	Survey				f	t	2021-01-11 09:50:51.530716+01
9	pbkdf2_sha256$216000$Xjt8HFdYy95q$TSwKaymlbGX3Xldn60q2gLLWdv0cGAzxHnqTJ8tN8/s=	\N	f	42				f	t	2021-01-11 09:50:51.98423+01
10	pbkdf2_sha256$216000$oS632cBNX7SA$yai4qTOISo+5hIyz9g72eyZQspKqP1IBiowjkO6aU9I=	\N	f	43				f	t	2021-01-11 09:50:52.43671+01
2	pbkdf2_sha256$216000$tw35MmXygOIG$c2FxSQudLpPfvk+GACUzkxDI8ko6ZhfflfKRgJXcvsE=	\N	f	Exchange				f	t	2021-01-11 09:50:51.060082+01
11	pbkdf2_sha256$216000$Cs03GSxkemZn$yKrq/7tttmVQ393tXpjBo7lUWdm0ZTbXmjaHh/keVyA=	\N	f	testuser-396TEX7B				f	t	2021-01-11 09:50:57.776375+01
12	pbkdf2_sha256$216000$d3wpkXYdmODt$5tNah50BdLzapAw0bPHqneRwvrHtbyV9ES8dtwBpA6I=	\N	f	testuser-Nukq3Gg5				f	t	2021-01-11 09:51:17.597275+01
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
\\x030c201cb4cdad6f1a8c13867af5e7772d70714711883626b1b528f70baeb74842ffd1fbbc73cd263fb558bde913bd64e005d76181d61868a18e627623b7e6a8	\\x00800003be3b559171a8d9e699920929ea275c401152b76ad8ae1550024cf0583d35d46f203ed85a83ddcb74716813999c9e7ff1fa7d72cd2c1ba7dd6a8241f12bf32402edf4810d49a1bca4394838e670b6085a69df3e16505d6613abfe4b4a32554e2f387dc8c5cb0697764bb93d62e4b162c93d4cda84248de6c38eca3e3f098235d7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x634e22611187af30415650f0558bdd5d54899ceac4abb78539934399ced30e23e1f84362c35fcaa3e3ac855009a1585a3ba152b093a80896756f7cb6b754880c	1634535050000000	1635139850000000	1698211850000000	1792819850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	1
\\x04a814b82c096e42bdff9ee14c1e98d23ad9ec1f3c7d25da3a58d189fdb76bb065477090526dd36e9c988ce34dd9a329ae7f85b56aea116596aa1690788dfde5	\\x00800003b64e06c10d9f765aa65d6d1cb8f328242db7c6ccb995c667cd3309c4572f3e0a1419d202269628dfb4ad20a5a32df40349eecf41ae37851115ca5b0a315f1f359692f93dea507daa8beeb6c0a5765975a39732ced1605bbe0ae42d95d59a6d754429b87de789821985dfdd8a3cfe22e3f3fd29e3428f5873bc0ced7983fcdc7f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x28340f8b36980f205469bbbf4908e44b9f7ea3301f6b5e7bc53c6ab4e5a6092c0da8a57107431f3e00990136b96427f3aa8609262194f9040625d28dd6fbd60f	1630303550000000	1630908350000000	1693980350000000	1788588350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	2
\\x04542d10d2f7b05c25cf1a05e278984fbaa917e29b4d2b42be6fbb091dab64da9ef2fe465baf2000db720703e9b7ab2ec36438724d051bd0738c059c354863a4	\\x00800003b23f414d0c500cd65153e42d958f70d7ebaeec98bec074fc19e679f03ffd080f537407bd381651f2ff292b7065c4c13dd929e8d5e04ee12be957ab2ab2cb3a346938ba584dbe93e560b4c2072b0cc0c8b27816bae46a4098c244ac3394843309eec8fe4f7e612072ef627aa3375bc7257a775c0f53bb4ab535423d1172a42a37010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x297a837e68467bd635fa2aed02c92444126ea588cc563f7dcca9b376bea60487a68bd32f624079833bc349baa6352baa9a39f640b2da52102061ca7de255850a	1622445050000000	1623049850000000	1686121850000000	1780729850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	3
\\x051c9a0c8557882fcb7247672dc964b4f2dda4366dac8fba0ea39d4d2f51b4315a16f7e06f028b96dad318da8f9c3ab511867fdd83969d25f946e8720dee3595	\\x00800003c897d1c005ebe31e44d1e57e11eda7b55bea615f79a8979fcb6dfdb55b45f8205b0bd48aaad84763162c67497b8b56eeca1db06f7447df69222122bf287c142eb2f9a80c552f03dde68f4ab0389d8d5844a6707aacea81c7eeab7c5e2bbcafdf1c9935eec0d9cea6d02ca9dd7b46283981e85992fba25878f410b4a3d00b696b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x34fec0c79732303d7ea475f2c323896e3243fc21954b177631ad29336cc3f51c6789c653244ac994d722b0eb6d7236305ada1f4e697f8d7d5a02ed8690875805	1621236050000000	1621840850000000	1684912850000000	1779520850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	4
\\x0a34d8448e6d8092abab03508c2395f9bbfa00d58ce829320a7c6891c42a93d238384719e38e034aefe338913cf8f87bba3d253c6df2307232aec7ba704cb471	\\x00800003d099c329a437d84b20eec38a3d21fefee035747cff210012e9a8c885379f1d8a4c73ca0080a30847f7a1dd029f8454c906806bd53e51dddc57c59720972e2b63ba037306bda0713dc94599a8657ff73e545168b04730f862d0071ad2e1850133c70c7530da02357ac5dfa0a331009923b2013d5e41fa02e8d386c3026f7cddd7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xce0bb7739680b22c0b16df84925347e6b87e5e0e180329064a7318e1ec63f3205b9a046bbc206da22cf37663a79a2a9656d9d39212ae843a0cea7964a187ee03	1610959550000000	1611564350000000	1674636350000000	1769244350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	5
\\x0b9c6184e9b713d44ceabd96c9613a00c2551959f23b9cc0d91fb861744b7640996aca030eba02c7de2e9547c76165656138d444e6221cc1938a31cfa14cf9a2	\\x00800003e848fb71ab72a78680fb4c5e6e36ea446f8b02b2c2c9368afc01bb90dc7023acae1dda46548a0a16a55139955911c33ea3e30a4493b644624c1101a89989898c3f69b1cc07ed478865c347159d4a3aac2a470e4d0029fb4786b81f56f9c251c4054ea7f2675efe09034df4962342d33438514b4f51f039d2f756b66f99c4f583010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x40a1da32cc85d567070ef735b653266d188fdb07a56c4aae3198370949bb213d6c8601dd28634898b855d731ec5d869b9dea412eede7ccceeb8033b770a7e90f	1626072050000000	1626676850000000	1689748850000000	1784356850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	6
\\x0b0842f8ce68a9df0d85559f4bc71383f99687a733421aaea783dbe7a949b90fc21d0614cfbba692bfdca8b0cbaca1fee989f78910c2ea9f17f8832cc289d56e	\\x0080000397ee34659c70761e12de35d7a6f5ca4593b797ce48fbf90d6b9062be2fd4ef61ca46ff1585fa22640822262efa49d37087c723d08a221da73ed8e164a0f92e27fa985dd3a352d8832346a9361244db8dee9a503eccfa3237ecc3f8a5a3e402defa982b50f47581e927a477e37df155261fddbec7bc052e83b775e8b9522d78c9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x436d6d3c7e4735217c0b5cff2801c821f58e4b32e8a0fdef368250c162e20340e97da2e68d695c93b992e54d6cff5c110e35649d437a9af29fe7cb436fa9eb0a	1635744050000000	1636348850000000	1699420850000000	1794028850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	7
\\x0b381b6a758216febc32cbc3aeaafdff1c57699cae05e1cb5be150aba4062f3f68459b4c73770a73376dda881480da3cad43e2d4af640dad330429096f47cc85	\\x00800003bcf6d4fb020ccdcf814a429eb97c71a4d5af4b513af24579483f00ede5f8761344dab9760df5045a6a4105a5e74965b2835d4e8233f318204fc3e8fa4f55c0672f8ac34eb3aa3bf024f0b390fdff3347ae17b006d6db4fa188419244172739f981e906a4e001a1b5ca058c5e310c36b1cba757d09464b3ecb8697f6909a1b30b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa6bd207871612e80266f7a729d57a4fdc7a308a4580b7a116db85660d926bf2ac59f190ccbd85fe08dc876d7a89dfd594bcec47d6f5a5471eb840b097964100e	1615795550000000	1616400350000000	1679472350000000	1774080350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	8
\\x0fa020005bc37b77ab4f3ec6a9792a19c2ccb094cfac7e217393ba548f8d496a7172de0f47cc47616c8e6e20ca2607c5b9ed0392da9da35aac8e4c395c80094e	\\x00800003dd0730adde3f3c4f23033231b7006a85d8c3e9e994bbc2892fec7783a083ce6b8c58c0012bf46d5a40c49187540b8c8390688530f9e1bce2c607c7a6b778df7ba039709bd374362d673c749a95f554b93d62783dcef75f6a2060fc1b892d2fe3a4537ca271814ab81b631bbeeb7694f916dcf8c4e3bf9b94a9f906d272ac242d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x89b10b2db575ce114b1d4197afeee38117a831d5f39415727dc9293def0c3263cae3a67225d523d98132f9b03190dd8f758f0aad9728d9955461f8eef9e7c80f	1617004550000000	1617609350000000	1680681350000000	1775289350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	9
\\x145030309f3680828af8e6bd86fb406cea1014bd433a076f8a5ec7af11e563e854200112dbc5753bfb038ca486c2d29e66d32a8c8ac4c00c142b65fb9e8c5a77	\\x00800003ba6f59432f4ca322967d4cc28b1cc5145cc250eb5c32bf53120cab8b08b101966b4d0c82f8d3fd5890de08f43199f9089d99a9125db0955864076ae78cad2bd34a4867981305eb78925aa0d4b7e99b65a94b9b27297fa915386cc7ab4b5e0acbf295a861554a842c27dd157b1aef732308326ac84078d2447f5ba8a660ebbd41010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0f00ac44ee956f1b53c2e56da6812a8393719fc59dbf7a10dc4142829963a5fbb00dbf6eb8314c9271685e7b3ea89063e1fa00f566bbd9290439dd81fd82920a	1611564050000000	1612168850000000	1675240850000000	1769848850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	10
\\x149489a0252adfdc6310ab6186b45ca685fdca75a00d352b369da79033d5484b051ad99807040b038cf7b30146ffc4381f18c39351b23ce42bb3a0fc79c4e0a6	\\x008000039966d4ff6145aea6888a3757629ae0d387054de6003673761eb2408e44a4a05e6ec4795f87c2a62c093e61d70319de9620b44f2589d067838f01e00cb1128040a7e8832ae43b9cd1ff9acccf2817b83af60d34a785496b3879bfb781f474965ba530d7c054c1087aa9366cacecebfe6a2aa829ad261cee70b224cd9792fcd0c5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x85ae1e5ddbfd65474fb1db7e9f4458cc711139e8299ecc76e484efb7e041cd77d2f6d267f74274ffae7b06b7b0f758d7a9b0d71d446a8fbead96fde320e7da0d	1633326050000000	1633930850000000	1697002850000000	1791610850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	11
\\x158411f21fcbe71d7bd9d6137a6979baa25437c9cceefbaac0e5912031c3e70c5118b4e1bbaf02eaf93f1d86571f699e8519e0d4d44feacf03d1c65726734dac	\\x00800003e1eeaf6602dcbb70229461d5e35b3ed22e4f4b5cc9829f0fabeb2bb976271b52c56d2465ab084e5e237a3f6462cc01a9d3502b7d86959135f4ea62fa160daf0b62e8cd0cfde02d748cc3f38ffe892a627c19716b04f983ca470959db4459128e4386bf40700c67fba36f44af8fa1668464f1f59a3900212d101459386e9bce73010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x941d101b5e222c4164e314e16178a6a36e52035a5acb2bc64a9638b15e5757c5313d386f2ec090a19a7e058f0c0380b8d87cba67406146f0703b5b18fbb1f102	1639371050000000	1639975850000000	1703047850000000	1797655850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	12
\\x15bc04403906ddb60a66c42a303731db166bd58fcf985b263b8265dc80c9c0e187d50d322196c0a4549dfe92ca52652fedf990566c10c25b0f362f59bb6c3ab4	\\x00800003d58bd6ba85e32cbe04e7b1e9b8c06260f8e60e1a00345dc57c6a5f066bf7537bc0ffce86c84d2877e652c4cae2d51e909fe133ad2c79d1a35e8c459b016785f95afd34b8ea542cb628d82574bf7a23e8019f9e322aa6659b5e194b930c727864a4b275d826f17b7ce032dda2afe15369d6d83399ef930bec031fed6565eddf91010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x31ed9a0cc88d1ca44914103a6efe59559f0df7ebef4409c18fd357e52111938943ee5c4bc372ab981e32c8e6cb17d83fa859e0a18d9de1a8e60ed13b2c292e0a	1632721550000000	1633326350000000	1696398350000000	1791006350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	13
\\x18c006f8c548725c8f552ecdc3526348f37d807b3495bad01e91e3f606ba02ba30a1a24a4a4d6577b8396ea9a91f598745def075c84aed31a6b27e83e9d13e13	\\x00800003c8dd69749f28753aef40e665bed50c8dbd71ddd357a0fa2f1b3edf959431b36e5ea4061474687d6b585d9d9b532a831543fbb723fbd2701f743052841cf4d8bf7329ed808ba228a95c3f04175ac8bdad45bfc67b5f34499b74ebcf6075588abd328f149786452d64a5b1fcf81b5c4129ae75e4a00838e4a2cd49dd8866138af9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xeefb188d6bb17ec96ce83510fb50b443bbbedfbdb6364d7f2927bd480616cba85033f773cfd462e4da622c3d3edea0fb83895641d5d379e1fd102d9e24b3960b	1635139550000000	1635744350000000	1698816350000000	1793424350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	14
\\x22e4c7b16d867de5f9629e202a4bd39adee140fabd63c50918f1bc01d6c66ca8f1703a61979e3f4d31870ed67fb2085871582d9caf92ceaaca637564f99c9b0a	\\x00800003dd045e50d0e659cb0bde82063592e095d596c448309953e0e05c233b6deceb24af07587ed0d7d2b9f0b084a44640a83cf760245f6b77ea4c9bd4a9bb025be59bd274e0fb88aa0f53f53993f50ded51ae5c958d2be8fecb4a21b7e1d4e5e47822ab003cd133c17579acba44054dad5052a02467b23238efc17705873348f951d5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x36a9b50f34a17717eaebc479cc4163b09b00077af5e259bf7c19cbe07dc88fc968c5f87637980fe07735a3d788614edda6b48ff87baa4781555bb24b9b3f920d	1639975550000000	1640580350000000	1703652350000000	1798260350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	15
\\x22147c170544c2e4fb236018401131630c35d4c2f839c10647e284eb2d9bc81eebfc8119f27d77a01cce9c6df660de0e120923f253d681cfca11d2c3671d5ca9	\\x00800003d26c5ae4292ade6f6df7777c1a85972166e796c075ed195e0c8d9ef63e8cccd4dabeec8e3fb2b951e6e8532ab9b29322ee7fcdf228ba2ecdd708602a03d8a1ffaa15a0f81e1edf286fd28aabb4f95f1ca0847a17fab31a77ff56863781f2eb60b3bb055e861a805da4d900fe8f5b5fe9a4838e4cb3906400199ad78105076857010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1eeb63de47505fd3fcf2d36ee9ddd9c5af9956fecb6c9a4e7ad086b34e36182b870e4e30da25d208d0e997934a1fd4dd795f40d6105a671db75813a0b8c9a808	1632117050000000	1632721850000000	1695793850000000	1790401850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	16
\\x2354a8c97d2d9535a3902414875b302a71f6aeda0a1a70b8abd94115ac7c4a10ae5f373042ab1e53edc059763a47f48a5241c58bebe5035d103acd041df1efe6	\\x00800003ede07db0d65b3f2323f49f44447483ac0899369b4c11dbb31b3c576f9b7c569e859d0881751c60826e3ee78268f6619c2035a703c11d11c65b4ed29f0e789398add632328f4acb0e700089fa63a93bdb2bf458b931f5f72e1f42018b0d763bf4c5ca1b4c963c79b458666138ff3116b7b3cab616060e8533265bf75558e8f67d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5cf96e834307961bf3700218877df9cd1ae68018f11c0edd241a7475decad42afae8932a41adf387d29bcecc2c6fb681fb0de69ab0672839e48e19720139d20d	1622445050000000	1623049850000000	1686121850000000	1780729850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	17
\\x259098d2008a3ea2da19619c59f8a3dede89a74a5c4eafe6689eac6b9302ec5447bc6f6f295f4772a4f1817ef95ae4ac1b4291a9f5e782691f2c404db66113c3	\\x00800003ad7cbb0913944f04f339e606bff8df0305481191778b91a1f3b7c9c0adfd0156c83cab4fd66d777c1a46f5ef8d33010dc2f6a7329474aeb0928536ebf49bc4ad9b69ac18951303e77bb3164d84ae052461a5cff543d3a2e65ce9b707b037036469c0c7774abf44fdc13bddce7e61a4d63eda7f2a3629ac2eb4b0b99eb0cc40d7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc96b5cff66e066a8e99fc47a57f288d72e2717f531ebab0b582eca8fb51c3fb58d65cc4f8f28e8d05f0de482edb4faf93e1fba6d0b17423fa91237682ab09a0d	1612773050000000	1613377850000000	1676449850000000	1771057850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	18
\\x26d4601fb1713216c1d7ab7ce86d866b055227e22118fe2397d8e44b6a1836b221875d1b5ce96ffd6d4431b404ebfa46c2e7db4eced6c84f98389c77fd674899	\\x00800003defef23b537af1c13b50d233e7a0292db61488ce8c572e063e28f6b356dda2fa7d3ee6a7cc91c41971f1ea6d603d51e4b28094b28cc3a2e1b0c2271294f14201c6abbb8563f15b5c3a22c9310784cd9cd0f08c2890e52bcdf8de5c1839d3aa85fe1d96d93d82c334552889df542b25d6f3e4d4cd54bd34ac3ee125fc5125be57010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2d8ce8a3de3c5471b2b46ce0fe7a8a0bd417477bd7cef1ec88794d9ec8a9ebd9bedcb63fdc8a809924d530e8c5e491e223771e2de5974df5cdee12f1bec7c407	1624258550000000	1624863350000000	1687935350000000	1782543350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	19
\\x26a0dac490abc66aab0eafdceb8d3cdad50f4a0852390bdaa2ff99c300338b3a8dd0aa991c4e2bfa68152f6ab05f47fdba8b75f56247ba9f4d390af44cdafb58	\\x00800003ae508a45cffc92b06c505c96e71b6cf3fa8f7fe31cebc59576f2c0af92d7fc381bf62b520b33eb0ebe4f9067536963379242dc2872bd7535262e50fca51912912c576b6fa3989a6c8b068a64affd9a053eac85032f3ad6dabca609223336f9f6e430fb39b9d0c92367e07ab1036488d11365a63a83d57147f144e0e040709fbb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8fd6ba941c87fbc8d3a4420457ad8cd851a8f89bbc6a333bc570c9d77055caac0f1197e55047f46b34b043a4f6e1a29b0950a33588e5f3af9f98b7238e722f0d	1618213550000000	1618818350000000	1681890350000000	1776498350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	20
\\x27801ea4044e8775bda24ee3d8f0ca6cd2ffaa468b3f89a0465dde21305207ec0c12910d416d155445caab50c81a071b5be3aa6dbf758746445a830fff9c5169	\\x00800003cc1b68a99663c804f0c83d629df880b77dc9402fe06e80824b741d90bf48d00eba6ad96fd389ac813750c2ac456d883b759cd636390f8186f08e633e29f18fdc7ed1bf6077cd964d866722487e49ab09485b3470106224b42fca8e68bf6f3ad02f2166aa1b34c1f6576caf8622ba41cd33e32f2a3411f780f65e6e83591bf219010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9d855f6369ce23bff42920f699d9f66d6ca422e9a6643e55cd95cb311329f949733d3e4b03a04c337e7415c45ec3421d31e6f4e95c0bc06f32bbd4c0f708be09	1624258550000000	1624863350000000	1687935350000000	1782543350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	21
\\x2948535ad71032ab478f87a689f7c092c02f321d120f3b48da0a2905d5b5b7bfd0585d203ca45562ed3072009e60b743c99b5532b84621c8feaccf05403963fb	\\x00800003c4cd3dc09cb42664b385b114cfd8cbe22c323ac2718f6a358e9d5c52a093282cfd05053df4472f69022083b6dec016c1e21131a35f0c2e032f5c67b83ec80da518e1e3fea3b7037667c21fe52ec3f68753913a580c87a1492768c05b5419705ecce2bbd829a9a300057c148cda6491d94733805c1961b99516c62157e296abd1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2ae18dcb4b425500dbd7350dea04e70edf4e4fe028d5ee64f3d638af25ed95b40ff8786d76ad9426ea9bf460dccb2a2b5d5e8408a116f4257663538c51e1f000	1621236050000000	1621840850000000	1684912850000000	1779520850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	22
\\x2ce8776f37524b5a5cb428d3b57bb50cbb8bd783554196fb76209950e2eb146eff03518a3c29e22cf4d32e1645de54d811e90b301cc153db6aa0bc568cbe285a	\\x00800003bc97996575dd962eab74a4c9158183671b4815f70a7c26643a997f305435b21ef325914b64e2e112f33e9033b543660af29955f735806348175e5339d0a65ac145ff81bb1d6af4cd3fb0c3a52172a843246470a916081ccac61f26dd71b4bc86b28bf298daac1a496f9c1ce75fc8bdfa31f3b2aeaf90f1a79e19e645b49b4a0f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xebfb0820c58cd4df982fd181884b88e7da4b1fbe049652aad60a4a3f4959be528c395361dd804f0db6a8d4db3ade906d4bac284d163056a87dbe4822e7980e05	1641789050000000	1642393850000000	1705465850000000	1800073850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	23
\\x2c74af888574f4411aa85ad18ada63971b8c638690c671f52195f7a0f86beac90455852ac3651338110cc830f0eea0586c396de34ace3a8f51e34b9af212955a	\\x00800003dc0b4dcf17853aac3a795fbe3e15f79be746bbb1c09d5abddfadecc6cd2d7e2cd4c0f496a07afac5a2eb0f80817d438a613a32f7ec7545b2fe83b205d70cba03b89b3413b4f6e4b18bac1980ef643fdfedadb17a0d1c8753c23ddffd1c690d35051aea137fff832d465ff6e851e635549cd708bf2d26a761d5af184b0899965b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x33e1c01282cf8f3051ae7fcb1ac7cb8e8e679f08fac81f8e55c2c201c93506124095b88832623669a0f90746526e474da272e6a2f693f8c314a13bff39409100	1622445050000000	1623049850000000	1686121850000000	1780729850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	24
\\x2f982269b370cbbc480b05443bd3da8c1d4f8d6eee234129b700e412d156782bf3da301321b66b2df3edd412ead98a9a76add1bb71fee99614087f9af9d1004e	\\x00800003f8d892fdf64dacb5937f42a11ac9ce8a8b28ae9e36ba809881e79a70edcb4a80baa830144005a9ff2d7b6be1d709efbf980a4bbb08cbe70b7aa2ce28c2a3a8d9be01bc6ff5ffc7f88276144e8ace7486d12d8e02ec5f0ca243aaf9c86158a5f1bcecb562f67d95015f13e7a4d74138db6d561ef93623d9e50d7d2450479211a9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x12717d9eeeb68c97ac31b32489dec288a80f26336e0a34ae465c0f858f114b78f90dc53053101b22c9f2263b6c5006f45ec9ff097ad6f0dc20b238f9ac04cb0d	1632117050000000	1632721850000000	1695793850000000	1790401850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	25
\\x32e0b03fc07d07b99e24945db8b84a11f39281fa48ea39e686559689f522455dbf77292cd1b223549af1ed1e308b20a327f58114b79775628dfc00e549e9976a	\\x00800003c6e2f03dfa5835d663628ca3cf22ed67f002780eadd41d9b51015d279a291a307e15df5e62c2b6a478c12537b6e5ffee346e89c3c3719214dfbc739b621c9e5322aec624e9536e2f2f1568b766bb03af427dcbb9185cfd5fbca662c719a5ae26fb347faa50ec1e9e39bb78d8bec9ea4374fa2f18f1e0d87d55af9e3ca67f84cf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x223d54349d4ea169b9944c2d30ecc3c67a526a55520b605a390dddfe44a54be715eb70f258b303682400307ef1ea0818d96fe32b5d55b78c014cc82e3a647301	1618818050000000	1619422850000000	1682494850000000	1777102850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	26
\\x32f872094c03c8e178454c5b363eb3fd27c8b81a6a7c6a03bd83a1bab65b17a8b64575b63945ad0022e37b99d49d65cce0055ea53c9f4918e025332121c03a2b	\\x00800003abb4e719d06f37ad285360691c055b0747b9fe73bc8cc394f5ca5be881995cc69eb06f12686edb9976c71ef2b4b2d8c4848e4a405820f04d7fe1567d64cd72945fba1c1ead360c9b3f2111b176a305dc74af9745f9cc4a0962f4ee74ec1b47a7086c195da475627790c28b04939e123001cee198a2198d548a36e38482e473f7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe94fe8ebf0f2bd21c84779d6598ae02a6dfc3d310b8049b5aa461f666c6edae4945ba5e02b2a61900c92b1482c0579dcc8593ed7772f1ef4299f13e94598900e	1617004550000000	1617609350000000	1680681350000000	1775289350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	27
\\x37b8cd8a37e9155e8438fbb154a3a9f88733657888f009983c68f669a5ebf90f2b0c54baf9e19984e7f5b388656e3764ab53aee22ae34a125f42cab480d16270	\\x00800003da0216c3f5920fe1e83df723ac4bdb65990e9c89943ddf04ac8a3b2aa4a85b76ed415e4499617272b69e5934140b82cbbef5a82e5475c993c5d9f12b2eb64e6ca495707c19d40aa270adfa46a43025f60ba861dabb175f6929245828920bf39ad8d3b71f26fe1a968c3cb4b779b1a0f179d826bbfbef15b53f2e7e12962bac7f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb83d29b655284d757a0f81367183a970936929a315ef60d4e4b8144139f0bf5dd6d88a9677758c941f70ad9d5dbeaf746e6ff2b9d8ced7215185f51f5ee7ab0c	1612168550000000	1612773350000000	1675845350000000	1770453350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	28
\\x3da463a280dc57ce492cc73c273d9bdd4b39ddec1b1d54f0deb1b497db0de175d630c8c34bac4bb9638461c17e49dd5fc809464d8667484e779ec5d7c18585f1	\\x00800003cc3724aa2818270e25eed6f73bc952cabeb4436ba9f3a2e540d8809965d7abae9429ad2606a80f7f6ae2c36fc0a4e0cabf3fa34bdb13b93cfeeacce37a942ea6ef5f095a04bee0540a0fd3af5332fa97ff1727863f4550d4be789c481bc5178000da74e644f599b715fe943997f83bd22c960c0e2d8e065f587e60514fcf362f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3c87b5090399dd424473ff63ada3b50ed05548655eef7dfe2a7537427599e7c7cabea49915a841a0143b3cb29a9ff28c5657fbb1914a1c408481832496aed30e	1611564050000000	1612168850000000	1675240850000000	1769848850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	29
\\x484c4f1ef996825a253285edc8202bf28c3f52fbf604f3cc6907bebb42cf9ca2d2936565bfeec3f87eadcbedd5df9b04cdff6bbd56e5d94ad5749f58ee7f89a1	\\x00800003c366dc11961a0825c18396cdd6f9cff7caa2bed02ebfb2fdd26a7084b33b5e58f07263d1ecf4d4cbcbbf05413c448c99bf057c9f7528fb21acf73906b6e0a0622d8b372f98799dfcdac487f35827af3612154841ac92437c7413523f51ede4a392c71ac2aebb95b8bc164786f77976bdba14dbb4d065cf123e80602ac28e39c7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3f5a10039d88565a70bbc7d602463b648925abb49c074d59173722e5cc2460968157e58ce646d0e8867df79b7bf6fdac1cdf5ff02fd7eed9402be38587160606	1635139550000000	1635744350000000	1698816350000000	1793424350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	30
\\x4bd0d39f945a92d750d78ffa4bd7bee1b6bcfb979d8da5c0768543655bc3e347ea7dd5725297b88c63d77a0cb21116e1a7a4988e3e394b17226d54ddb80e390e	\\x00800003e872c1fad58929a8977bd0ef7f3abe798b4e317729c394b370b8b793ef1a70b1768a4a26881512c9555096f31df7c42f9c3bfee9b1be4cb527e203f462e95314726b67ab7f8d8293cc4d6b10eed0b65a2b4589a24d56eda89ad9b65d1b7c7b3c39761981bc51d9bc326a6620dc8aabe2a290ddcae2262283f05758fc937399fb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x18b62e5e460a2dd482db3022fd866a347ddc4f9e54ab88aba5d97b5aefb870178bda9a5470c4ef4a95ccff5db497c828e988f35f221b60d8b446f1a817572e04	1634535050000000	1635139850000000	1698211850000000	1792819850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	31
\\x4b145f1445f76f464c9c5ef22e3dfa27dd47d6780380227bc254a2085f70eb562568a389c1fb7e6d0e983d90f56b5eee2a39ff2dcc1e40ae43873ed2a5002490	\\x00800003ca4276538e67cef5f516e1ee50913b4b11851aec0f53ecd16fbc490f9f89062fcce58d0e29e2519a05d5fa045db3f062085427230c740ad96e0611463a11c27029a36822f760960ee3d08a9b73fce1273ddb62694cf78ed8d96c5f3f2fdc0f5c441885f76d61eb7bf941b0a03e1c5444c42e5e60dbc78f51790511e4bd633865010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3b46f646cf912b043c52438a9b520ee0f9337a6cff9bb36201c6e14102dc1b7b0319aac2f0aeefb08377ace167c03f503fc6b862e1de2f50e556f4fc8820ef02	1631512550000000	1632117350000000	1695189350000000	1789797350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	32
\\x51482b44b5387d8b95d27db7de33a2c44c28597beb6022de6a4ea6e27ed8c3e1586a1f8aa50a6c593c4f8a24678dcbb412f8d525ca91f960bae8985c08df4fe2	\\x00800003cd3a3bcc13c4bd9d38e006a2925a3a183f27289ace925ba92ddd5db1ff835c2f3e6b66696618f8fca9e1b30a516b1dfc5959ee9bdb2942e169b4f1f0f945554bebddde1ea19dfe14c3fd081166425298a0f2a74a389fae2b3bea98d4a4c68e4f3ce0a0e92dd5dc3e386971c3db326adaf59755c9733b5269e4ba0eaa7ff968b1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x884364bfae9604b11609b930a2afc1604f7e82a3f8125b5c4d4304ef21be84648a98c171d5f70c8ccd1d616432e7853bb3840911b00f11039a1e1c2da54eb409	1636348550000000	1636953350000000	1700025350000000	1794633350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	33
\\x5154d6ace358a49f0351afdc4ff4858145f19f2622ae3d1394b3b942a29a2ee56266a7ecace554c44a24e77217cab460ccf41979361f983c81d78e41cd7d0def	\\x00800003a64b851c7080e81f57296e2d1b2da45cd63a407c3068f794e649b6045d06fcb0025ce9235e66062595a3b62a483ac884e9ed2b97a5ecfd5ad8cd43a92aea5c2bd76f0f5d5b0ee059007bad9b36041b11d8dc6459502ffdc5501ed541c3dee7af6534e1c2f86aa44ddefc77f5f52fc69f66d7ac19e1f6010416b8d8678ac947fb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdce31e2e5d9ec01edfa23f1ef8fda0eafae96054909303a94bb7c0b08aaf97d4082349abaa97ed69819a3ce38b88f36c6b25e160caa08b1e3d1ac91c291b570d	1634535050000000	1635139850000000	1698211850000000	1792819850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	34
\\x5670309bb6324a2b289162adbe7d6635b6eaccd42a81430fb89f68499bcfde13290459f43902a394609fd61963537f5c21ec2e58edb4e4e84921b0091e7342d5	\\x00800003a708b551553af8381389664869ce848ceda72220a76ba6f2434913ce784b24677d31eb1a383c55e9dbc8d7a2a81b2282a9debcdb5cabb58c90bfb53ef2bfefee24fa88074ce82bf4dc12c5664426b495e4c82d27b430166e9cd239da98597754ecec3ca291968b70144d033bf0bcfe221512e98bf3e7a5a5fb20affd59a57b17010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x51fe8cc876c190d62fa8ddeee4dfeb18fdcc0630060dc9347ee7efe50aa5b5b7ad3c15e388f8939853cc57cf20b1daaa32f271c812fd01b44b02e5c17c8b7a08	1637557550000000	1638162350000000	1701234350000000	1795842350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	35
\\x5aac8dd101da7a5f9690c9417ca9c5ab90f514a006c0245effa76f77217ef14a73c71e8c61aebafa7c3c007e961f19feb58f88a468390826b75032c3b043889c	\\x00800003e851be785380ab095455c9ef47ede3010691892d0b2618a043e40663aab6050af53b975031ba251607fa5a32bd9fe3d7fb201d534c9dd5673182d5e36b784dfb1e4e3d6486f54b8a9f52f9601908723aa326a74394a3b328834a9518de8e08bede06ad7cfaec373033658a66b52991267b57872b190194a4e4f42bf3a3d18f23010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x59d1848a2d5d992e2e37fc3dfd584b2709c8a8f0a58717dbbf866da47fc0abbcc6076fdc31c1d02767b3b74d499486d0f92bb47b305029af0827d6486b082e02	1617609050000000	1618213850000000	1681285850000000	1775893850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	36
\\x5fbcd70fcd20a8d8567ed629b09e595ab0e41ed65348c21b4b1b02eec928560d9b5f921796fe56029a0347aecbf9a37c252db1ae631731f1c742105c269628ea	\\x00800003e5cbf375ece5070909605f59864f59ff530073635cbd9f943c93ba197607a43806910ac7bf33cf48ed587c88579e5605c02712381cce5a30cec05d5e89e1edc0b8a1cd20321d3df903dbce5782043d68b4e1ec6d1a3624018f618193cc20091bc6ea813185c1eec47fdb7b0a59a3bed42275505a14199315c8db36b7389e2f8d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xbf8f2d73314865be3bc4bfbd40ee537ff43c0ef6e966347d068e3c39738c8a82f751b1c3f3a928c9ffb2eaefce9aea7077ea4855525ab33953384eed6b842608	1621236050000000	1621840850000000	1684912850000000	1779520850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	37
\\x61e4c52e795a9d0a1c1422b0f8012204c1766e63a41579678827a5efa8cee9400df76ce682b9d1448d2bf0a83b53e5a25c4b797e1625437f9bc92e1013376639	\\x00800003c26a036e474470896893999994430a79a02166d2302ac6962017a75f7785dd38328ce3a4e292ec89da3fe394d8eba2a2908287f59d2e99a99ee044a666b089e26bab118a835aed6d40cf861c8b2d7715ec1b5dbb694a396cb1e9990de509cad489e555ec2603859831af27987f62d3f31e473d0c1d71223188bba4ac079e8981010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5e7865fc8ab09303b4d8155e323e0b2d9acfef22f3d1a1bd05549cff6d837e5601621352701c02e4d038c8ad38c74efcb84b5d833e5a41cdde9994e412364b0a	1621840550000000	1622445350000000	1685517350000000	1780125350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	38
\\x633c95a3df09a7d8bea40dea9c3dcd4da59084f2383ab679762ffa358e91f68b39000b16fa09a495d3d2eaab1e96fbf96e154f72afa4b41e44cbe66d46efdaf8	\\x00800003d0f9a0428d4ddf46040d88a2d10fe38ee9da0e067b6d666af762e72107563686b5a7f40e549ae9baa5db06767f2fded4fd86c4a06acb993e915807cdad9ff2cab282480b147a9e855476e96a517653872063b48c432312d4cdaf959566d925b1cb3d97cae407b291d344597583e4bdedcdc5e0d22d6b7f063c734f7bd7db6f41010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x85d3e6f7094663971d45d9efd545189826daf734d8b0d2cfa5d8291993b1fdd118b472c5f639aa5ebae41da226f6b887372c79d69378e1bc659bd67572c8950c	1638766550000000	1639371350000000	1702443350000000	1797051350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	39
\\x63483814d03cdad8c8f7ed5b47840790c07598218069f683cad2ee2a68686d9a30d347c64b29de1c540c486e43aeb847d868be025d1e49c4669cfa49f8fffff2	\\x00800003bedb38f77bdf32b63fc88f7ca5e23e8f3b644f2a60114b396141d85ef5a210d529f048261e36c96b62a49ff87686302ba731ea52491e08c61c6e53d90fb25d118118f37e04da0fe7cc50f52de186d0278fa8dbe3f32f1d70345ceb09d98925d9153b6990333567a9273b503eb0e07afd9bd5dee5ce65b14310ff35b1fa8755c9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1280079ad3ad47817740f134c092e86022896fe38a123161637c92a0df6132f954e50926db39a134462ca76a0819cd9d77e616c9363bb9828ff935a914738704	1624258550000000	1624863350000000	1687935350000000	1782543350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	40
\\x6498d858aaffc77d410b6e4bcc9013401b7a861c7007139ba3c53c87dc85d50f4dc8da56e36e6b75fdea8bfc4a98117ddca98b490c08575d2fdbfcdc43e6368c	\\x00800003e40d2f8a0050a6ce489405a85b6696a30153ce5f5e3b2028af8a5f450a85905d7a31d70902966c7ef4d0039303e75d430a7982890fff93a4aa2588539901315b38f2b1815d3fadc1d94cb01dfe83e211a6aff1583623721f7e4caac858d944e4df1c9db7524bac8adeacad5236fd6a8912774c993f1a29a07a2d02683adf7f97010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7cd3289923d7b402e1770672e49ee20d44d727d32a13ff4561a8e307bc68d74897398f6ab430b54c08cdedb7db8b65ce251c29120b2da391dd8d96157635da0d	1610959550000000	1611564350000000	1674636350000000	1769244350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	41
\\x6538a450e0c89642957d594ae1f7073b56b1c6504aa89fe223ccb050621fbea597a80bab679dac5ea9e2f5ac3ec74218aaa2c65bd294dd1627ce98e399baa679	\\x00800003999ff292c822a7a021f3a4c1b945299d2567c56da56f6585f8f5387773ad8dd42586f53a69015d0764ee054bba23232c20431cdf6c875fdea7c72717869f94047a152aa32209ec12eadbf2abcd7cdb0dfc0aed30d84ba49f7544ecd362d879a8c2982da4300cf98945721072eab9086f919b9bb8644c6abd0a631a6a40c40aab010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9363028b177576f6d0104850c8361ae49829ae7c911b1d31854e9851c334b132b02555fa59f21293231cd19a8b1d74490f9318547162a1bd8a55b1e81522b904	1641184550000000	1641789350000000	1704861350000000	1799469350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	42
\\x6504bc796088e56b2afa223b403d04a717255bab07107d885d70db0e171ebeb18284cc2a140733aa0ca83cc1fccbcab52f8ff6bee4b94e78f61ffd35a0b51a2f	\\x00800003aa19f5a9cd6cbf0cf0dd13e3770ec424274618f93218341bf3f7dd4cd980df563c40d1f63b10f3538a9f90caf3a00eedcea3b7087cdb7aea2814dd9e895ab9164e80919710a43ff95384db17f6d922ebc2568d01212b369b645ba2a14608c2ecb9bef335250b4f1cf8360ba51014f9f63a62e32df5e4927359d091b408b7c9ad010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa4da9b40df5209746610bce3746e27dbd4ed0e6bcaa49b85272ca7e1d2f6b292a995f2eadb3a3c6793455ce3b76904606293907216a9fa06593417191cd53a0f	1630908050000000	1631512850000000	1694584850000000	1789192850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	43
\\x7020447a0475d7ed5ce817755ba8afb98fc268aafb7a47f71a1f109b0e00c8aad5e1268657f40d1c6fcf97a986e322d01551bdf5952e12ce4e0060783d191ffd	\\x00800003bb9b68b5b97d7e55cf86e3b6dad51b0cc5e97179ae3fef3c5015aa5d09143dd6bdde448aba1283a517bc655f062606cc4d7284e9592b669e7ca332ec296f64d53fb49b758291a0acd98067377dc5d42a06c1e225b2e4068f43376c0c8db81a27ecae0e458e4a83546dfcb90c4b2290400826f2736f9cc78acda917f9d876af55010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe37c85eb5f1e7e441e51b8d94808c4bb1eb48ef8eadb3eb8ea54674767bc80c09e2429329b508aaeadd3b40c99f5cc747657367e7a3dad80fd2fe91230580b0c	1641184550000000	1641789350000000	1704861350000000	1799469350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	44
\\x7134fd0c0e767a7cdb562b9f11b2b19b491f72e7f747d24a6b8056d955e2dce939e521db77c509bd925cb63d22720ae8f62e1d9643f0f17c8abb15f461fd8799	\\x00800003b3920c9fbd8ceeee272a02f0b150bc4fca11be300c477a2bbabae263f1d633793d44c277b7846dfd266268390ed2a2112a598e10598b46575e055c6951c4be5856cc40a43b3819a4a962f75f45b507782ecf0e074fc864d30f2151216166a37c5ee7fd5c17a78ce8375e7b012f5b1f0bf2cbf7be73ae650c89c43be38c462b31010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1ce708be253e0a4c5b3b1c65b49cb09fe5c5656f76d050b53821632ef15737efd744450594eaf92c6c37cab096b2e8f568176f6ccb22bf3eb2568150b18d6e01	1627885550000000	1628490350000000	1691562350000000	1786170350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	45
\\x72d886e366315d201aa330ed6994d1ae5e775eac8e8fba1eea4300a6a73ca8f692ef90f692be47309ffa9e99021568c26878528a9751e2ef807a7a7bcab52548	\\x00800003b76441640c8beba3841f0cd20c7e288fa8cc09acc4197a1b5c1c193ca88313abdb2efc51bb80d8789e0ac33cfd0a6ff9a719f4c726e0a2c60515c11489938bee37dcec3c01d4ef9019ea672824e11a118757e65951c136aba1498df6a61c1193a6d9b0749b941734a579a714522895dd38506aad73c2be0edebbbdb139cb3515010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9aff339aca12bcf084cb4108265dc51cca78e93d557c0e501ac277a5bde6f84ce89ce82772b5944a5db66336f3b9f934a0397b20677afded4538601d4053e90d	1624863050000000	1625467850000000	1688539850000000	1783147850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	46
\\x7754a374a2a4d25cd186aabbed447a7d7cb8792a3f2c1f1205a0dd0e1df7965878a0e69f635cf724f31b510e2ae8ee79b38530fc0ce23d765712feda12635e3b	\\x00800003d2ad39a642256b0792130d01eb6a15048f23c02ecfa872936a07a94bf7ea67f8e385ea438991ad4ad13def8a9370f79cad14dcb18f5ad34b8372d86d1dd64a150809abd903533ba44843a356dec10fd1abe3b508d2666e23bc03ab8eda7fd678032e41fad446273eeda608acf84887e3614313ccd1f25155ea7b88f4801e0131010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc6aff991bcbe26d6320ccdcc69a5fee6229893e9186655dca1eeca6c6ab14573ce64d4baa431533762a340835c920f46d8af4eac2f58eebfc9a0233d1e67b902	1630303550000000	1630908350000000	1693980350000000	1788588350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	47
\\x7dd07fe64b0a544e534213f51fa7374d3590285f2a153c58819f92a4cd87c3b2b7dd7292a3401074bacd76bf1d78a11584ee19814d7a2c0be2a5f28447d98694	\\x00800003dbed6b6dcfa0795e492d218217f3de8a6bc42810ec0979da1cafd4f7e77518c508810c7212475d90a4d65019f2aff42cf3e7dc925c04222a171377423dade66dd5d057f1d866193b67705f8c8c2920d13899b10f4e86a79e696db01013b554e291d3452c940013c5fc1c401d059ba1b674b288e8371a77e5fc6bde82c0c4384d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa2b738ef89189bd8edc212ae150c88c47f869f1098ff45632c0efbda757053474d1d88b56b0fb37397f47b3189fe14b3561c02c308db6d07d2e0f144020fe004	1626072050000000	1626676850000000	1689748850000000	1784356850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	48
\\x7e7c0b592aeeea139c7393e9b908ad8e811ad366df50c010e2ce58a283af79421e2bfa8afbe6c82988850f83f9d432bcda7bea6d78c1ea7f0fa9b8864df0c6b8	\\x00800003c5e33ec301b3aed8874dac56eaf4459441efef4fc103d1825e9552b2730fc06194d4d59b662ccb94087d6ec60d618c29cfa8ad435f783df89649300b84a119cf3b7392ad35ed4cfdf24e35b28b7b8f576679eae08ddf4a7decef73a4eeb675d10a2b5b3f22d23cebcbc24f7c5e0445a103ab6492b6c635270861b0c06f3e15d1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5ad6a214f21636db9b7b3d26ccc9b3d15b0c434f1b1539b437400a09a197decac2bcaff6fed483ef4cba98d3b5ac6352ffaa1515791329f0a00b27665041a50d	1610355050000000	1610959850000000	1674031850000000	1768639850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	49
\\x82301a69a31ce666bfcdf3f2f375f5ed4412d7672ac5101a6ad8521083738efd9876f93eda350a96fba11f41ca3cbc1ecfd2cecbafca594f2c2e4ba2f9a9517f	\\x00800003c3fcd2281074d7279f23ac69e7e6f4d9c87a4ca47b98822e8b8558cab2d7f871e61c672fb15672b3c36971a5f01c8b21d4f6b60c6304bdb4c6eee59dfa6252079cfef2acb16b1e5d8ad64591834aa0a60bd439bf2713461474ef3d990647e15831b9750fd782e0e2c5600777a23556394ee026c711a3942c02a9b9d982d26b61010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6c0ca461262a8636c8a4db7625c6333d6f0af7abe0f70f73db6f0ebc28b5161cb897f5774d812382f8321755fd77aec276dab80d48ad6fb8a4b3ca34fff93e06	1630908050000000	1631512850000000	1694584850000000	1789192850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	50
\\x8398127fac33db0b3a70585cf4189af6ba3d1cc324b399e99058654e3ffdd8616a54e1f319160a5ef443d3edacd4bcf3a03381d3ddf4195f0187260c10d6255a	\\x00800003c289eb56f47906ab1e085d0c94601bbd869dbcbd27315dca422ba9cf2fd5a42138de4532521e9c815c27c7e048d771f1eae9f86356921629f662267f71f6888ff30428591f66485d22fafd6a7a74b2fd1680cbc8493a4a97937bf8b96e73174cea7f16e11f87c1670208b0acd40674299decf462f2711a22b8ab0d201c003b15010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8e62ba86474f6411a89da12ad530e48de61be8dda076f1373296357d2a90527fa9f8a17fb9afb630a016f1cca85d7fdc7f6152a6dbb1d17dcb06213c8459e90c	1617609050000000	1618213850000000	1681285850000000	1775893850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	51
\\x8488029266adef84d2e682c8c301e5a0b1a0d718d0b212148ab16bcd0a5a63b4efa578c25bd85d153be8f56dce2fbc7ef89eee0f92ea0888112b7d50d06f5441	\\x00800003bca912ab9d737407f9daa3694369fe7974baa2f0d5215393c1c2992035da77ae8c59219d4eaea4755f27eb66259988946aea26652988532c513e9669b62b7448fc9dbf56291f19ac3ecf009b79c90b32e925fcdbfa3b3d4a1f19c2edf51fe82c18ef63c43fb37578bd8115c00c40f17376f34876701bdddfdfa61f7dd3384007010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfccd98a1aa4813561531def5f09456dbee062b9d5bee0b6374ef6306b2a192dcb3c122c9e705a70b224eac7f26e8654f96bf177a3e5d76f7c7ae9639351a1608	1618818050000000	1619422850000000	1682494850000000	1777102850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	52
\\x857c9e4be498a7e72d32e17d9e53e90fff92a36636ca0d4c0b3e8e9be1d3ae3ac36899fbbe4d772d0309c7a31adea4be9b5c56291695b15764f30ad2dfba2bb6	\\x00800003fbe05ebb78797baeabfb218095febf69bf330f715f4778f91dc3dd8ddcf64aa62e701b3284e64c6edeaf2ea085c54b5be131fb971369ed46bf1b605142050a0affae8c33df4f82e05b2689d43478732806975038d37b4f1146832d4a057d67851ba6fa1436945b43312489efa2a0deac006a5d35ef50cb6086d950144dade4bf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf6ffb3e82242591d51f2d5242c15be12628d3ac2b16e4772b926df698cb804d3922505397bb5603621c5d91dfc2dc2350ef66d3255db5c5f26685d5954515208	1621236050000000	1621840850000000	1684912850000000	1779520850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	53
\\x8670e39544538402506a527bcdf58f1a351504dac89f162af0e2db36f58dbd8860aa5a9a9fd482185f80b2122b80992e5fdff3a63bc1d4f948215e2b9a663180	\\x00800003ed9a4b0bd819ef4c0a05e068e3c8e52816db37d7440c7356f9f0c2e7b7a9346b6a4779c51e64f0ed0da225a52f3401e71f275b0165275520760a18bcc31bcba3f16d16b37c35122b9ec89bdd7d8ea19463066f9368cfe0ce59bf2f687ae50f1749b7cb92d68d34c77d911fde5b6273555787e0e931cd657d51f82c60bd01bf9d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x581dda9d6ff8ba1bea3a0f30b9b4fe36d1403544b847cec6b69f5dbfa5b0802e316c1ab3cb393a2aa6b5d3a66307189e2efcecc596bc3b4b19da70bd47e07f04	1631512550000000	1632117350000000	1695189350000000	1789797350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	54
\\x863406369beab37bb28fe5fb5d0f3afd128084b7803e09a0ce4b2a4adb99cf7603ec78811edc6a95ae43818c5d284afec59fc5fd07a6725662b97075655b4d6d	\\x00800003c928082202535b8890b3cfbcff1614ed6f703018317650b46dc7ae5acfbbb2760376e186a298815c012762d8b553c4b01e595ec29dcbadd3793f78743520da4062e7272c0d1af0e61359a071020677c2811e633a3349b44bad6988c79ad0eccc5b1e2e99309120c3fb24978b12e13c0f5a4316fa60d52ab9bbda78193ade0a61010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3a9dbfc086d20ed5bea76162fcc64d654ea878ffb3eb2234edcd775eaf0b56267731868c32aae7aad9eb07957bb2c359f7dc7db13638ee2976b37b4b84899108	1627281050000000	1627885850000000	1690957850000000	1785565850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	55
\\x87042e53f8cf9d83cd15e434132c719f9f3cf223866a5676fab18d36d18293bd42d45bb2449b2a80695ea1db491ad4152a62c82efd69b3a7420026e37f22ae38	\\x00800003dc909f28cbf25442a8182f2dc4a15e92102629e206775c40f3d6bd0aa7dcdafbfcb05156842b792eacc7ff4eb5d39ba2cb8c8838afad44c3c51ab7d919fd2f84aee486e82c3721bbbe9ffa1cba6c19088d5b822857d1d5874b16168d93d8e1bec413dd1fc3373bcad298b2e4831d14609078fc5c4d1a5c66aa610a90cb63a19d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x280588117dbd9509e5ecc0137687a69347cb2d546af897c4827bd743d4403dc60972eccd2c920c8e1a3b8ea14e29089de7966c11f9581c5cec028a736b460507	1635139550000000	1635744350000000	1698816350000000	1793424350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	56
\\x9110f99c3270fa456526b5661d858ed15aa362919cded337778092f0dd8a40d36c946e772ad3e32387a24444e5d27484d2e79e255f801e12f80ae46dd8592138	\\x00800003c00561ebc502f9db42259034f1b5ae1861d97c706ffa255b7a2562b5ac83f26b72d15d2ce073869691fd8f73f0112930120c09ae4d353c7ab6613bd5f5e0aea56cb89c4d8de113458e0a8f93261a6a11988d827223291f7f9f758b42e32376785068dcbcb3b1000327f68bc4bf26aad60bf545674d71a6db450ce5dbbfa504f7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfc154caa7fbc0c220ac93011bccecce718ca141d5818504688a08023e9f4e51469e08ec624f444c995aceb68e0466ff032794bd41ad0779c568bb0eed094810f	1640580050000000	1641184850000000	1704256850000000	1798864850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	57
\\x9300e4172c9fc04ce86128b2c3a656ce9936dfdeff522420409ca3085ad1103e2af5ee5d7a4da5611c27432416ba59d1a0d95f718408454cc6c5354e10a0751d	\\x00800003d986839d188b74fa7bc4a9c3b715d7aad460572d33d90e678947a7a8cdf2b97e2018e5658ceaad6c508ce6602dd16c04627ed9fa4b8ea6d325e84ecb0aa01eae19ba396a08ede37cb954c4c3920aa8598d8cc557ed02a01861dbcc8f93c81017c421530d075640a6d32d53991e203e912d74d4e935bc9a18bf86bf55cdd73efb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0fdf98d89f3e0981d2f57eb674593e47285772e2bf8b217e8bdd1ea63336da5f944e2786fd73fc963ce0ed5649adcbd4b9f1bf1c27ddd2564aeb57121439c90a	1628490050000000	1629094850000000	1692166850000000	1786774850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	58
\\x9418d54e0005613bda8ce81bf8101a0f1dc63edb9f41263cd6e7794cb326e865f99623878a6f3c560bcb6ed978b76bbef91d009476431b09d10a23b530861050	\\x00800003aece00f5500e55eb4d52037987be1d673183b8626c4cf1a5d2a6948758ccfc0da06bc7432708e32a2c8c1601cbb4ee0217044db0f059da35e989803a7e93c238b86c5f7e14c7ed3af9a518b0482e9075574a0bd9a527803a093908d536cd647cfbe5021aedf133606909c44dc759a1f40dbd3888cbe2d881d6664ad70a18ff6d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x758d798a4abf6c2e42718fdc6db57899158bf75401cf86fbab496bba240ba98d199b4fe9f35aae34fb0a79b7a70a9078eb8cb7e52182b03fc56f26fc535bd30d	1621236050000000	1621840850000000	1684912850000000	1779520850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	59
\\x983c1cfe4b21c5ea13bad8dc39f291180a80479654265aeee5ba4991646a6eecc0e2457f5b7809cebd4d629d700c0a169760e47cbf412c3cbc069e9a2307705b	\\x00800003d5b9de93701c10e1704bdf89c6944a52181458486b61391f6acd9d6d1f5679300cfa6ab9e020f9119ae3ce3625895e1eabb5409b750298e2b75947c58eaea4bbca6d02b7b8fc566069b9f7ff71a7d511cc14a9810143a134d3e3b5ca8db2f63137e2464361a388868b9195ce414f85303a61a4db4bbd7beda09d7289f35aa91d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x770ee70cef76727df40b88dc78410e3585c53cf5859b350467900eb6054da50c2c9bab82e01b6b66792bbb014342b87afbc5aa2714763061576940053474ba09	1637557550000000	1638162350000000	1701234350000000	1795842350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	60
\\x9c1cf20237eed1cc666a20d7ab2a191eef441042a5a47a892996c865af9dceefa2975b439d076f90191b55802facd83196a911c32b60daa55ca1f239f4951e41	\\x00800003cc7003f3cb20c3db992056846c0ddb3983d14633d26d364f3d611de8c1d3065e8ef09c97a9e85042cb495dc36fe5a4514216faf73c2c89d1fad2fab51611f95a3536851a4c254391baa47ce1ca6de4ba6d43545c0f375d0695c1c7bd6a1836c1f0217c7fedca3cf5eb6c0d2fbc3f75e71ba7e8d04e7e9590a5c626478f6320d9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x66b3ed8c482c8639bff350a48fd79451ffb07d98ebe40ec376f51ef8bf820b7dd03fc13e7107fe4a5823e687640b5d9404799cf18174ed423d8d441a913c7508	1627281050000000	1627885850000000	1690957850000000	1785565850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	61
\\x9eec7df99d902da11f9c69532b2cbd298ae853445c0b683a7927d1abde4d4a7484e306f369804347207bbef4a5281d47bbe4695664aec79d22f3b185426ae1e7	\\x00800003abde94d9e930c22aac4215eda658102556eb3698ba702123ee45187911e6ba0de8ce05459fbf14a611764cc24c64108494051b905b811fa4a0094f561ff09882429e43a9b0af6d0a7f4a1942ac9156ead66ff353d0559170efe89a2309a103cd0cfc1a839a90bf593f1079fabfbca69a1e22582fe12697719847f1c887c53ca3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfd3db7a4b64a8c6f69c05dc5d5b569342401338f0b4ca40140909680bf3f7d92b8ac83934be1a2ff0ee213b20e9a3789b077ea4cb53a564996d28233828c7906	1630908050000000	1631512850000000	1694584850000000	1789192850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	62
\\xa1080705f82e1bb00e66054574c04cda87e6f40fe1fb147297bbd63e70a8cd0563b659da94ed73c68d07a9d66204d1a526c284933470f5e9e2f5e6c1cf5315d8	\\x00800003b658cf3b9bda35535150827951c2ad0e0416d607f809e45f12fcebbabf6dbb2e6ce13470e9b86ffe1d2c0126ca1a9a584967b1cb315cfb127a45fa76286839f72cff18735f23cc26ed803733b918bd084d39f80e80a35268b13fc62ad7885c89e92e99e820c11507b093a9574335238dc8c7a37ea8e8a589061d0b603def69ef010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x36c9e08b3da708bd83bc525874f071867e01e82a29e16b95cbd1f177b1d56af5cd57f1b655a04e16cbdc066a516a1f54b69e90d8e4b8da5a87706fee13ade808	1617609050000000	1618213850000000	1681285850000000	1775893850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	63
\\xa270f6a5829bb0deb81d6e888e1fd2d95e321c8a336f38992dfd574e3045b64464aa802238c313b776244b3cd22ed4588683960bc030db81b43711616f21e9a1	\\x00800003d0c4773b58f8a2114f0468b65fcd87a334d9ddc34add6cf5e6d1f72ecc0675e9e457af16252094c0557f93ddbd8025b1b737482864465d9f0c318886eec8352331d184645fa8ef98eadeb38b47203adce8eeff3283d78a2c098da80e069d8c03ae354e36ed3839bda1f34fbd28df339ecc867004ff2b79486c2ae74a1c9609c7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd4ece504dce70469b27d3d7c1405210a7bb670ad678b8d2f264f90e9bed23fae9c60bc7b96805222b1eebe922818b5b60fa61e711bc592d013095b4934aaf105	1626676550000000	1627281350000000	1690353350000000	1784961350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	64
\\xa460cf820de0b4b839de3f7f8a1cb3e941cffb6c419607fe193d195a9ce13180e8227df731ecf11bbe6910fa32e8803439db31fcef14356275a091572e352179	\\x00800003df41632de99ed2ae7da11d0277c07c08d0f01881e19e868d4420f2d1abf38be27083b1cd2aaae1d6b588c2b4a703a9e54e6284e11ac8c3f3c9ca40341b4361a99811e386eb4f273f4fc097e478a35e691f3578e0d5063fa99cf4da1ac847268800d39715b6aa73f2fbe935aacc464054a88a5b5e41bd0b361de1fa60b058ae95010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x51501dac97a1180578b3f4d30336dcc73d58dc5486898593a1d1d3c00185318aa12dd65a739171dff77c07e3e3a1c1cbee87490adc21e2ca0763b19746baf003	1614586550000000	1615191350000000	1678263350000000	1772871350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	65
\\xa6c0ea309288d7ebfe51751f07e4b54064267f42efc462bbe0b04225089cbaf48753fa59198dbd281556c64bd42c78a0f16e098f3c225696071d0e2719854782	\\x00800003b3bfa12ddf95a553a9983936fe036ea8680daa25d3e035f86f8938ab8da69fab1d75f074b167b5b894cb491386f7ae6ed8e3b1dae6f4d0d8343effe783054d4d6043b75ba518c5e03a6bd8f57a66a7bfb2f66808dbf1d60cc32269f6a3ecebb7481296fa64d78fb168235f1d01fe4592606450189f987ce2928d2990796bdf97010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc6325de11a01e046c4372a4f0fb2392b8c1cd7b842a6684a5f6720ec368bca5ab968f8c7963410575b52ff4a026d67980cc76223e8ee48d84f188285f7f24904	1625467550000000	1626072350000000	1689144350000000	1783752350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	66
\\xa608d1cf799f384c416660b1e18826c77116743208360dd65e766b37f0a0e37e26f325d6ba510a88da32b529121b9b7585eb67806db0c607c7034720ca13b14e	\\x00800003ac6653abc0be931f7a05f94cd21e1dd57bbb41943869a46ff5d9b243776d708773931071b1aba8aed5f0572810a10fa95cfcb5f31cd9bb5e4c2bd5a0897467f6150347dbd636ed4584c5734fcef41bc63783d9b6747935a9aad19ba274d63e2e7a7c4d369c101f63ecfd22ffa99456fdf8e3e436c02cee2df3a7a13b55f81b89010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x00083a915038e597be74715a42451bfa0ac871c8afa4bef81c5b4b9f7cc06aca7018e41ea0be7d8973353b846f7b598408508d191c325bcec865f9c15354ff0d	1629699050000000	1630303850000000	1693375850000000	1787983850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	67
\\xa8d018470eea397de35364f2fd39d283bfced2dcc8306dcdf3ad0ab8684ce3e1c20ffaf9eb9bc68f570d06f375ba457a70ceae3982d5468d288a6c4a5c1d2c32	\\x00800003bb5e4dbbaabf9e6ad79c40c23630fc917132507d04d0b3a8286d957d83b9f4f8d82f353cadb14a0e3cc863220a1d4e703f643fb14e034346152f3f4adf2ab6b51d78e2d727868f4cb1401294f06f0d76e5dca85bf0247e13745b00c94f62870488f44baf085452921fb1005b3ac323c86ccd7fe795e0668d017500f90d1de433010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x62976de54d0b798e86271b75bf2b197464956c5f0e4505e99d733b937d3616a425727b159eab3f4715582e41eb9d352d9ed62466db27602260f5d609d0e1e302	1626072050000000	1626676850000000	1689748850000000	1784356850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	68
\\xa99421120c70cccfaf717175c112f03b676573eb6864dad741cdcbd7393bbfe7cd85c2289e46b6fa3c4c0f32c46e0d217940c0924998307fe3e5be8fad45ce0c	\\x00800003e5dfd8d571644ad5bad9f10580edc132c79779f1df7023463f996b5f34b10654e0424d9e670315472892d2630e8e7f2495cfdce137c503f7eb90d7a17d4d5d390cb22c8afe65587617e73a9f193dd8a1be790c05ccf72173f2541d0c45c48da31798847ee9fdde00ba0bc078ac7540081e17eba3703d3826e19b837d8af85083010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x88d4350c0f1fcb2aa7f5b02275e11193f4b580475051bd28979be7914b6d50b8487e9bc84b089c19023689b55d83051a9db30fd8ab4049d6dfc7a8bd0f96cf0f	1641789050000000	1642393850000000	1705465850000000	1800073850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	69
\\xab2846f0f27c1b6221eeee1f307b01345f0b264a446ff0de2f097ac8c79b1959092b4a6a9de4026d9da89242669f154e383b02d10eaf6be43f6e253cb2051588	\\x00800003ee9aa84d052d2beeb39c03a7cab00d3ca020fb7ed715b605001fd0e5944a901b1ed92605cbab26c28a68a22c818178e35c1a11fa0ab8a223a9d89a9d58546d49168f2d6fccafd251891f003cd9de4f60e49904d7b5a7a45255e096e0de9975ad3b2ab274e1f39a9a2b7f1ca2b6da70ec36d9863d013a9be929aa0e2b53a1fdad010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcf20196ec82bcab817309d66620a6b72a6bb3ac2e620031496c63f111d10ee37b69103186979fcfee8a971ee482b608665d54582d6082fb1465888d60000960c	1629699050000000	1630303850000000	1693375850000000	1787983850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	70
\\xad20606572a136a856e5f41abe519a70b1c09a4e4b4a7affa264761950700c22fb09a6672e3edb233213b1ed98f3b30e50fc51c01123a41ca0aedad898d61642	\\x00800003c854e0b98e1794746985441ee70b77af9ffe4e224c9f43a2a6926fd29b4556d23c407d561ddbe57e3f7d0c9a1050beab7916d3a6464316a704fe71d2b30b80f7da322c7da770dc0b2f0a3d31ab61dd2714937ee35dd6f075ee51115349cc6470a4298ebada58afe12689150b36e45680819d0eb14bad3f6535ecb254478eca41010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7e180ec62fff6df8495b2a1b01e85bf6ad2c4825fc2492b8483e1879b88217848073c787a93b728da2644710838d763831c6bcc204718be1d64556e360169401	1617004550000000	1617609350000000	1680681350000000	1775289350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	71
\\xafc061745a45ed723c9664543d7efbae237ff6b4236bcde4480805369581669b46f2e322eb51eb7a0687f7806bc556d62786a9ffaf513c326028c89cd59ea178	\\x00800003e5c4b5049bfcbce91df4eddeff2a6b48be2cc41b3e7069ceb17d063daa033090dc2cd619e5c3fb4fecbc11647b6fbb2b9ab189fafc18ebbfab68270311af9f8e1845ed3202a19df4e5023bb650a79dcca10db9a6c7042345a70ff70e1f6d50adfe55516d06b0d311986538c025c1a72b13430e0a63113c646a738ced383185bf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb86f98743f52eb1d94c7087b05d3b8224c43c5aa9396d14c3e468c2566013da005f22941d559307d6010d93a780cd53b4fdda820beb36f1a2766586a54bfa403	1620027050000000	1620631850000000	1683703850000000	1778311850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	72
\\xb54cc21c4935de66a04199c5827b204f9923d75e1c60756286c51c3d0bada0d3d60028f4d0b8d1a06e9d9e41156c139b96662fb7adf7fea0616db34435fc629e	\\x00800003bef7efd4bc2d25dd18fb5cd0a756c91098a6d69f98166dc3b632ef29a6d9c07facde7a45a7fdb432411e4d88d98289dc28055645872c06f27545495503fc96947eb93c8adca9fcea56033f78fa283f2ce228e5a355de605e5db84b4d7c07bc9d88b85661b77aed2eb0c9cc5805524789b0d85e927563bfff5799823fea823565010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xba37fcdeddf951c9b587ef023e4db4a6e99e0a07820dc601d68f18d6d75faeca018757ebbb2cc011a698d697cdb7ba5fb290e1709ca3340cbfae34e52e83000e	1610959550000000	1611564350000000	1674636350000000	1769244350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	73
\\xb67003dff5a4166e984307caa1c9fa3db1ff69fbc34c5dfa5fc328be4a22f2ecd68bb8cbe638033b50587745c807b75257d6332bb66730ab2c4dccc668f99678	\\x00800003aca2505006333bdfa178a929450b467d62f47c5d25b33d81cc961c9e305f3aea4afd77489ecada9d90ad34658f3e2c06bb51e17d686af2bbe15d2d7924c2ebc934bcc4a4352c7fb7de6b588479daf68c44d4281fb66fde3ce924c4d2de3b17e07a398c7f0e683a96a17a28e3622fac8283c9d523aa98e0615b4bd248166ca081010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x753a0a0941fa09e02b92ae3b434dda5aea95626ada965d0ce64d5ee126c913ee4eb47978776ceb783bbb761d6478a1a5be8ba1f5d1e84ebc6d44c07a48363c01	1627281050000000	1627885850000000	1690957850000000	1785565850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	74
\\xb9d00acb8f514bf0280430926ece05bdabc499b376f801838cee90b6652abc92fc7c39667509cb471e0f6401ef36fa6347833cda5f7b298522962c2ef4891446	\\x00800003e9f36e7a4f1efe5be8c97c88d7c32add1985862540a55f4f78919e71fc640ce837cf581e12377b17358a4ccd88a5593e48be718d143a0fccd48a0b276d77c4ed00a118f0c57abcabd9986f6b67fd831e9bd267cbc9a0214221bd1388afbda1d793feb4910bd74e127a5f8bb06a5dc2ccf1d19f6351d49615cd7325dfd7c83321010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x91efb7a9c1f706a6e0f49429814ba28300a7dfe696b3ee8eaa7f9e1b9d0aca8b5d35704d0411a132d09863a4bc4c8ac39a5d6328250228aefa30ff59a2346e0c	1627885550000000	1628490350000000	1691562350000000	1786170350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	75
\\xbad4566af2482467d1d0bcc1a2266b52b8a91f98b0627b2a3dd8144ab922e00cf2cd0233724fe4802e3cc16260ba4aa7f46607739fd949196eb0b99dd4c91659	\\x00800003aab5ba1fd0d1860eb305d8df8de6bc593fc08d3f3125861b675df144bc0f5488e5ce188b900f934eb27c6ca20100c9ac5ebb39f03346388d5ac72867bbb741ec1b158c8965964f7c9d73fa482a4901d9fabb84e3f849a62befe61a37dc5ec8fdf0973330cd1cb3f4732c168d47d383f2680e26dde063ed984a6d647cf433cf0d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe19710b128b8e22eadd7cddfa7e7f097090d02095f36a5d300164a26aff27bd10108ac3cb09cb91744269655ffa39ce17279c17b1cf0a64cf6d94e8886c42607	1635139550000000	1635744350000000	1698816350000000	1793424350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	76
\\xba48f9130378f5895effd2fb6c0cc97ee43cc0fafb57be1f3626dab6e324bcc0f48f5f319c86b9e0016de0a0f43e4f25f6d6d72e4ea173b27d6f7492c93bb090	\\x00800003bcd67ab7d0faac86f0f09cd099c9d6d098c687d38a37ef4fa4621a46b942c28f9a55969fcefb0db8d7acaeddeab2acffd979c48745ddc81b5848fc4d8e8b11d0a0febb3679de05c45d547dccf422eb0e6e3ca42dae56f6a2d8de851a39289ac564c733856cfc986a07cc1913b2c4bc6650202be6891a616dd41ac2cf8792d221010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x42d212bd5e0fd745b1667205247b87e47451f1183a9073e03f5753833d568c77f9552c718a399ec681bbffa03599e3313f799383ac3580d3f2a02134e01eb409	1638766550000000	1639371350000000	1702443350000000	1797051350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	77
\\xba2cce609b3781a7b32bd80b2503408d76dd9750486cc91bc091fb12a1ac9c4a28dba11a9746bfdf9d3d167db067566a276365d58d927f5706bdff4e17b8d72f	\\x00800003d832605f382a61fd97a2daf39ad048ad35f06b2bc6a4b6a909624b60cfc00852c5b70899b2b457c40cbd6dab1c882fc019d8c33e857c158c88f4376a26e41a2010365357bb27f29e9de2c004169ee4ab5b523e8032a9a1bf171df091ddd1f627ea08dd5ff2a2bf7d16d5df469abbbcfab25c55690a0488e8f7be4ca3000c7f4b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5ef43e761cb69fbe808e9441ac279e29589d2b505e7dc47de6a9f263f336c033eb166412eebece540fdea1258ba8e2c5a008f5db368f539589d268e7732f1a0b	1611564050000000	1612168850000000	1675240850000000	1769848850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	78
\\xbdd8ed5d6ebe6b161758dfbab802f601fe3fe1cf1f3cf85aeb7d02c933ab878b5f6453641c367e8d637e6b4bcbde4d67b14bb8a2d838589425ff4fff121eec29	\\x00800003dcee1c4d5700f0ace34788a03bcd2e5c946735f9637002e7125a20a2fb7ad851304ed8d879530a69cac97077e8e8fb3cf43365200c5f82304a24bd271eaf7dd3bfe71dd1957a0af88ff845fadca67bdeba7fe49eb56a17f4ac20af7df417a26b7d21c8335a15413d307e0d090c045184c5e26bc4664ef18e6132a03c73504ca5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa03129f53b15a812241b8944ccdbedd48455e27116c6e522f3b03989897880f2f0b68a989bae7a189865b7f66d1fe0b0446b89e6487d7051ca42e5084c928b05	1622445050000000	1623049850000000	1686121850000000	1780729850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	79
\\xbfb846065cedb1dc3f067491610254f326de90c0bbf496bebec79627f07d70cd377cf4037825134565e2fa68e0a4087f677c084a8ed1facf8bb0603a63c2c9f3	\\x00800003d1d42d92d66a505484b70289d949c4e8be4f62a1e508c7330482c5b1912937648a33570424e3e268b80b8b3a59914e5a1e55775eec16d5fc81a7edd098adff87369e75ac6eeab88852a79637974563bdf6414f11772d4e2d67f31e1f620a03fba2c71fcce3504d03afe24fdbfc9b34c0163a662c12a4f7db2fcffed8924581af010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb14ec87d8fb1facff924a7c8bf6021f783d5216265e0956730d3b16733ace46674a55351ed7e997a1333633de6c892c3205e0860ffae50e1fbb7b70b7e2dc004	1628490050000000	1629094850000000	1692166850000000	1786774850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	80
\\xc39cfa34c3f36193e01dffd0fc5357dce491d84a9da30bd09c64832b241ce74c9eab72bbef4f30d136f7ba7dcac91a6bbaab9f858bcdf3701140c90471261dd5	\\x00800003c3472d24bfdb807d0bd14654a57766cc589a05d83c6519a875d6c52548745f44f61778be0f84cfae1de31dd0383a9ca1314b6abd6cbe8f7f646aa2eae49ac56bdbf04d3560da978c1cde8eabb2e8ba454300cdb8c8d34b019a83b48ad16798403475ad9756985201bf0c03d669e5c1bd50b5fa4ad69e58fc2daacd5eac267c7b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x771bcccd2371c9520f950ae289917f1c375015a01952a5c5c43595ae5fbfe2984a5653b3b1cdceae41a5a45b93abb713c379391acbd7d120bfec11b855fdc00e	1636953050000000	1637557850000000	1700629850000000	1795237850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	81
\\xc4a81621cbaf73f40045b2183ac33837d6b6399ee4d26a78dbfbf490295b931bedb1c5dddfaf8d1239f985d5ad5eea1f7d7fd2e510972e5975299a2e3c89624f	\\x00800003c2e7e0be9bb4aee3993b45ad53d0fe5bca8bd97c0d7b2655427e9d6ae3200b3593e7f6b243f969c9e138488d33f9dc778209afac85d4c1c985b31e5fc275e7ffa3fe961156d499fb4e61026b2d7148559bec279f672c3d6d683f936d11fbba7b3bf56f1a1b3634dce8431b94cefabe4f673e624270cd4334a1ff806674f3bd0d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x60b12eb19d844236bab55513246c78b198ca558d577924be8f0054db466b4e598d5fc87abbff16a75463f5b9553991c8b398cf7c623555497204d27bd2f62b02	1638162050000000	1638766850000000	1701838850000000	1796446850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	82
\\xc6404b2cc56d1f44c638624ac474f1357127475030fcd233d5a148de345c36b8de7b347a4d36a900298ae92d1cc3ddc84a178b6d23f026c2942ccb877c61855a	\\x00800003c3615c3dacac0b7a9d363e887cb211ee4360a3e5cbfbf81ad6e88f4743052fe6dfd3678a07c185d750b602871fba0e0d799602360684d74a0d85d7647cde2fb43678e3c1b1d447d3cc1a2c5304852a4f94e375a0378912b9a39fdea7de4bbc07620c5b6b845db811126899d73d55ba1fc8cdbee5fdac4926f913a9b23322ec81010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x876e5790b26c4e2b490f2183fc0f5c2fc66cc56c2da70ca580f44a69686970bfb8c900b922aa9a1e2908d861659af6f5552935acb326ad18fee8470a09c60a09	1624258550000000	1624863350000000	1687935350000000	1782543350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	83
\\xc9000b02c3b1a811dd1d4b0ab492fb597be48dc1df364a49eee4151bdd85d5f186cfe8fda068e7da6c0ce447734bda442a72c85bd056435f0e3d238f1a7e0e79	\\x00800003f7063291c5c67bab05b8677b969c0a10a2adc85420352c9a9c39db581fdd74fc48671afd18e82df58c5737c25c3e7849907f2fb8b43a3e442e83a3a53b898fd380fbfa4d0c8cd448d2177effb140db3b787cd46e84d26faffcec28e2274302ccd029ca34460bf4ccfb17afb32b4ce019d60a35b0b7985dbf8f4fc0e5cddf3adb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfb70349e5b616820ab43bc714dc7fc99cc67ebf087136bc02668da8aa95f45e5518803a4824ba5d08eb74833b553442b91fdea93d0e2d14574a6594bd74c8408	1624863050000000	1625467850000000	1688539850000000	1783147850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	84
\\xca74d853b3e43feb145f6feb86ad288e310b87b72fd7ab0338c07371444d9ae6d87ccdb261fa45e6bbcc042b7bf29d4fd0032cc844a15f14599fb78620a1a86d	\\x00800003c99e953092eada2806d42c81d3354eba0d942d07aae8c28f759fd0b0e25e5294baadea2fc732af8b6dfdd1a578b99c2f85b083fc654e04b2f2c987f2e7fe97d9b3f35a706bf48c14917f243bc4ad4d213db676c2c7aebe8b85af1cc8cb25430e4ad9c9f5aefabbdc176e20d49e9b7b6ec36a33ef6e5a71da59da00bb9167c5ad010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xbef2f552201bd682e942672a57bd2371faa812b9fdf6046282231e8b8d1587a0f43a210eb07245f5b7ba9ace0b3f779fa04b8e9c61b191ab14be1c2d7f2b5603	1633930550000000	1634535350000000	1697607350000000	1792215350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	85
\\xcb94fe4102daa03e778948b9f6bfcd2cb6043290cce44b0904ba3774bb82c9e13f9dd69420560ae953c2c70a90761049743791a4822693e0ef6b8c3839bf1489	\\x00800003c300e93db8d0ca41187459672eb83dab8d72fe5adfef8dda82b6db54e48ebfaf943d4dc6882d7636189f507612b6afe2ea3e0312250820c1b681a46923b4ac7cbbd4f687f45b8ebd855305e87ac0c68097da6e57ea6a4d6758c5c3773df1eda6b9dbebeb15c08cdde77e5faaa4a3aecee316ad51d61885363e43c276f5f6a893010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x754bd125cb28bb791e58f9e7de3e217c5a957471ad744ddc124d6cc84c2e403f9b03dd3434660378a1fc7119255f30554762418bd90bc1fcf11ddf9a323a9e01	1618213550000000	1618818350000000	1681890350000000	1776498350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	86
\\xce3cdab212b02ab646474cdbea74df9c7384351f7cba386e613201ba3c29422e43aef467a6aa426d0b240bf77db80931676220e395e714b8a1f6f5841db9f5e2	\\x00800003b238c983ea3443f5b8a822ba822bb0fe882126dfd9a9f6b222780bdfb11bc3d3650a128b0a17645ca566f89bcb12d9fb4846d6d2783f4b3cb42c86d921d9e67921f0b6d0452f4e40215732c76e3d6288c03a7ac86727c7ed9f7d22772955e082a22d67a024f021ef7f4f1604b29dc59d3796c9bd9794d55bb397841a52f6a735010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8082ad1a5756cb587b4f7ab0e45c969c3769ff710c48dfa2e58fa92ea1bfba5db5e96409993c6e2d7c62ff2ff1ab542acf80b5a25f9d372bc348562abbe5ad08	1630908050000000	1631512850000000	1694584850000000	1789192850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	87
\\xd060b1acafaeb4d990a29e84ce8b1e7351f3bff732159589a230f86bb02334af1b32c5954bdf8780336390406fac0e5bff249801eca0047ef0debb7449b2a604	\\x00800003af19ff39acb0588979fbcd5e4c15b67132f677a1f8f4648dde46b2d2ecac9aa17a3f5b9d54293b41768d738c41edb8f94fdbfddaf3a372980e62d87bbe836880855999e47a29e75ec46c67c749d6c0d7344afe489b25cdfa49a758913fce95d6dcd5e7ff08f1efa1a9fbb912545b00f742ccb8d31eea68f898dd35e8f9ab7a09010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdd6137e5877cf0c2f3f2773b9ecc41b7499b480a523bd75c95b9d74dea7b56a9fef7f1afe1488c6de91f38040d83dcf1e1a7508ee330032d3ac47960c7d00209	1614586550000000	1615191350000000	1678263350000000	1772871350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	88
\\xd2a48b28994d8595905fc89e1c54b34db70b69149ccbd92b0ac1a4ef8c535c23516556e56ff5198938cce91203ffddb2d757da6195ad9ba37b39072c0f06e461	\\x00800003cd32ba6cfe4adf341c0b63e2111ac1b9de04eb1d2725a181e4bae151cc0fa61fb710bc2a11d46421fac563eab12f5b3886141f3b58dc33622ac2e4c552ca0116555ff883a4dee26c9b4b905f4e82b7be35cae26b2ca5d18dcd9685cbc9fc5582ae2f32a6e0a9334557b8baac45f99151bea5466ca79c89f3816249db69fb091f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x924180eafb1720086f84e5e5acc29e58f1dd44692250d534073e86f6b880c41f265b6dd67d19121f2da07ac562f4bb42e537fa30af4fcf76b27ceff4052ced05	1633930550000000	1634535350000000	1697607350000000	1792215350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	89
\\xd4e45d29a3c2f341f0293bb05ec66b0d0b7d37f42c8814abb735ee0609d28cbde694016498a223d90453d3134ef27c9977c22e61e992e53cc1273d4db5200dd9	\\x00800003b0cc73eeb3a8362deec8497721ef8eb0d0c07ae0c38f8f132f9475314d6e7991eccc95b4b0825c6a6a2865bff0ad66485322c7457adda94c827bdbb3fe29cc8c0f2ce8d60c4b5ae7250afc36cf7e46c35b82be60b79eee146f7694182da3c45a5f5c1f5f80844e0e20ae8def8500d9f55ab00a3a78c27bf46a01e2b95d848593010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5f2e4be706df22427d3f4a429c065dbffe1bdf18b03d7007667935fe6c3ae70bc829b785cc63b0a944a979dc52c5dd27ef92502f7048784966e900e3e3ac3207	1612168550000000	1612773350000000	1675845350000000	1770453350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	90
\\xd9f0459c4232d204a059203c194c5fb6e9dad8509273d8f163b2fad9bd407c9a43d8d01fe542cac67ab67ec885115d341f9d8509d24196d3628ddff41de5f54b	\\x00800003b9a94718a5d713d11b0a93ea430192382ebac19769b1b850a4ef65eea95064d753ae4300dfcef4da03b165a47c4729598197bd0e4d45f886239e92875e5c7c49ebcb685194b53871c59c83f133cc3d3f72f74cfccd11610cadac104f490bfa88d47c4ad126ff1f82e8618d9a2b025b219fc0372e0250245a8e3668a3d90c1aab010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x408fff392200d1c8a004f71b03ba007a2ed1fef7d9419bff7be8eea762df9d17e6faf6b9960425fd0219ad6fc0b9e70e2f7a790228e8ae0285e38c658e621804	1641789050000000	1642393850000000	1705465850000000	1800073850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	91
\\xde54f589c2dfeceb9a872fd5871337a645f3493d760857c14aac0a88801ba0bcd3bcc74a882cfeb2542de444c7859d3c06498db61b3ff5044b4448c4376d4a00	\\x00800003aeb56a20c6b739b484225fe5c2b0f8bd0a413147b8bcadd2693d2baeae5aa1a093b0e69f47f1075e12b5786dbd4d0756d38afb795c46b908856587214a890e2bed2c4c1ca9d56069432cf2980e9c1c920b797b8db608ee9fec59b9c471154ec4ce97f3021363bf92f07ae1437bd47adab9546e4766211744ccfb0c4e6d701621010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb037de31e7d7a22f3a067d39c665062a0a997d5ff27cc06eddf3334cb9a1114ab6b9f85c403cbefdb59b586ce7bedbb65adfd774096b3519199b500417d9580f	1641789050000000	1642393850000000	1705465850000000	1800073850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	92
\\xe08006451f4cb127818815ea0a96c2f15cee7b7a10bfecbbcc32ff2abbeabfec5390d2e8122e83cfe52ac0e25ec414671b3592d0a2c0c003b2a461ec969d1a75	\\x00800003c7975463ebf78b0612041c0a7713e7dac0d1cb9c0bd2e5f7960fa4446e5d4f8d610e411e4faaee42bf40c7794e658de90d92c76176b396ea7aa80f6ad25c031fe23762fbf690e61a078f725a38f960f044b17413c0d753f2751f16786a6f7799f6e41fcf52a998817335237ff50f776e8f6ddae73fbf086b8e7dbc203a2874e7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5b3268c2360d1de33e1b45cc151c5587f15fc3f09ca40c85032d664b738bc361695a657f03fbc6411c4ccbba1078139fc9b5fe622657bf22dba4b0c634752004	1635139550000000	1635744350000000	1698816350000000	1793424350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	93
\\xe49c50cee708682f47933b084a72bc65d4bf9d408dcc1eaa9bbf67cad42fb3546417e5ffba432f2424825af9528aa651b6dc0b41124e1786f951236fe6b788f1	\\x00800003c4f21de7f2d22c1fa2c04bd3eafb2e42781a211594adac71ccb30742a962ee950d2f84bfaafaa0b4780eed6cea57743456447105990d62660d9be37cb7314134fe4a1a6fb1901ced09e47f05b4fb10986159cefeef14935535de996252d2bb84b65e488d018e5c865696d9ff275fe910b0daa2b05ae854a3086617703ef7cc53010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43a6432e9209581e7989311c4f0ace096687022a7b058aeffee93c00ce431710d9a40a727f259fb7e00b3dba3172cf5a548db8b2bc362d5251b559add7d11908	1624863050000000	1625467850000000	1688539850000000	1783147850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	94
\\xe93489cf77b2adba18a255b0a15b42227d5f95fcfb7dc173478aac1cab9a4b2f002b4aeb322a4c1be73e837ab83c5a9786cca35ff445fb02217c5016a77ff50d	\\x008000039cd6b96a0539d660c36db9e3977321acbcbd823a027458adcef32039037e70c15ebe9bf5b41522b7585ff2752063aa8dce876d12cbb114d7f60213fef0e96497cbc125d5ea683e690275a6dbce14ad54f1b27d5a33bfa9162422415ac4742f6bf21c7031f6caa366d7a7150f8da576b1d869ea2cd32f597109d79670a0db0bef010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6bb6a6788f63f4f4714d8c23bd3fe9647ccd31de79c94393a27e16bd38df6100554d3f156ae563fedd849c36b4e686c6f0e1350174dedfbeaf0e697f4bf8fb01	1633930550000000	1634535350000000	1697607350000000	1792215350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	95
\\xe90023cd52b6963b8791c89c3c9ebf6355643ab66eb7dce5c436adad9dd89ef267d48b48f0c772f5c089ec68261a58e2b39cffde2f274542d7ee32078388b2fb	\\x00800003a809f9a9efac85c39e99b8796a64be4c6c9f0d96c57235fe779d21ce85919f6dbea049752249b11b2de0b65c15547d6bc868bbd538b35651a2b4a4d1490c0a20e101da920aab31a411e3c4cfad9bf608795bcca9086563d528ed4ded41d93b0654dd5b97398213f9d0fd726c66b28109012cdfc1541eeb1958655bdab75b8f77010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xaa11a1f99dc994f67493d2ffc2c0fbdcb86aeaa2d83edd787aa33070a385d04007a6c8ce33afb5dd0370ef4459a0c219c3f6ce8eb223e114f0c4f5ea386e6f0c	1620631550000000	1621236350000000	1684308350000000	1778916350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	96
\\xea74f0aa70847a38e315891c70794f2ed85bc56ccd0fc5050526dc5f1f70ee75f178082cc6cc92145cd0092a930e0c3437cd9c075c59efa5a1a4700157cf33b6	\\x00800003df4b49d9a553018d283def2e91d3b1cb5adba2b808bcd25641102228a96361d8d088b51731a5b9c98a9a7a7dce99eb174d25629d821d12c24865f790a4a0b6c9ef65521e3d935523c6b01efa9d94a72fdda3712f6cd5e75c476569c7046b3620db6b4b0cfe3ae6573af5b09c3930f8d7353406eb4f42c0d8d4d7362947189ca7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6d7b146e1eff2e24978e194a4b960156a5e104941c4acdcbbc617a0b489f3610e885013607b9e1d4535f5ae93d18ac8ba6e673fac1c69997a17b547739551903	1615191050000000	1615795850000000	1678867850000000	1773475850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	97
\\xee4081e1d556806f197805f4fcc2af6aac34a09e2fbb3c0dac5f07d0e1e7219f185f0221c2d6b2badfd148de53c26042e55cf172d15cbae5583a1731dfe17234	\\x00800003a3d2276a390c0a7d9463c646ccd9570302dac70e8490827887ac0aaef35a85b5efbaf1c6617e575170105506ec82ba892343e1e15470244b26b28a279b18add6e0f1cd64e291fcc78b60b9e35e8fd5696c0375967077e8aee5a007bcc4f06dff5684e3ca171398e40d19554adde5d2b1ee081e9329d913d3fe9ee968645060f5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1b2f301fd6709142f1c828dc376cc1a296abff8e049b572e5731954111378669ec733f0751529ac903f56fd6429b1c9a1c2d3bfa45606c81b0569216d5963306	1629094550000000	1629699350000000	1692771350000000	1787379350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	98
\\xef00caa8d142eb4b348bb290117b6bfa3787f0316655df4391f2f8b2edeafa2b3522c84c4740217a1d5c2f96491a7514461cbfb5a42adc6c23858f084f585620	\\x00800003dc4356dd819be01854983df6a3c4713320f1559cdc741f909229e88645936f3faba176dbb41424ccfe66f045f9b148454cc39bc005337b13183a9199be777276ea1d511f3453c4e487af665e341fd495a63f7c815f31929016e30a6301ecc70537ad59ec6a5ec1a702dc834f01b170e41cd80183113ca5d3ab039e2508c05ed1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfb06a8040da9d606c2c677b8f8eab7264147f8e81af1936eb7d235b00e5c0baf48affa094d80a659abe2362049239496b31967b7ecc7ffbf0d5a3cf90e9a6808	1639371050000000	1639975850000000	1703047850000000	1797655850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	99
\\xf2b8b10ad6c2b46782f277d081854b4a433f25f61f131c4442f8dbf9b082d0eb2d64b199dbb0fdd71886754d40bbbbf0cecaa5c9b235ac8d944beb37628921d8	\\x00800003edad4c443e8efa4d8fa1f4365c71e42d05ca6bd56197ccc756aff4ebd58151736d262960d0a65fef75f9c4baf7e58d1da7ac9645f5d995e7327288a5afe3178dd26d3f057e3fa6a1625d2cfdcd274b5fb281d7c8af4967914eca4c7ff14ba1ced2c141d2391d73c2d99870def93c34828e0734c332ac4af57481b946902afcb3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8cb5e5184af197764bfb53afa4532b72f7df04394065cb6d418a394ee5bb8f7e908de6e74fa41f745ec165e3afd5818d470ff101ffccd8057242770e2e8aa306	1627281050000000	1627885850000000	1690957850000000	1785565850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	100
\\xf20488115f313b2affd68257a9e7602a847801f467a2d67b76114e4ff5a888a94f99175bf039b59808fb91a6aef4f7e230b923534450b2ca09b85c888503e16b	\\x00800003f687e00d8a74d14f3de3426af76aa7cb71d105d14d10bfa85c1ffc9f0095e2b227f395d6d45b66cd5ce8172f47da67c66a3e5d3baf191b606a1f2f9d0564a0a24c77aa5718c267d1d7228f6811f63f0de6478a05896040fa81e4f73b4594e9adf25c7d587016f118de25d2278eab0bf072e8994229572d99a302f65eef421353010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x414256463f91a18019daa8cdbb3f7b51667f1ec8862b5c631a279e30a75f8eafbb156d83136777049029294e4cf1051d5f7bedc701d658afb73d9469fcdd3a0b	1638162050000000	1638766850000000	1701838850000000	1796446850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	101
\\xf3c85d757063e4f99bddc4f99ca0e997d6609a68545bba369835c656e6f82b4a91f923dca73660889bf3a58ae5bbd89c671f347cae38b40e7944852c342a7da0	\\x00800003dfe14d2046f09aeb6d951176ef76dd7fa86469f9c0231619f794a2855b25f90cac2c818da00e09ee9a4829dcca724764d679abc69e57e6216b8fb139be727ed74cfd0d4ff53ef9178e489ca7754a9297d6928e1ce059d6bd0ded66dd5a5f317f0ee239721d17eb2d8c22c9d191ed0af0f68748e0976679f8a0a37cb4750b79c1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1e47f758be081756ccf45a8fa2f0b8c4cf4fb51deb522ff48a7b698e88e6560e647449418c2dfa6a0270f48110aaebea8ec95b78769c7e7e39d4896bdd93550c	1619422550000000	1620027350000000	1683099350000000	1777707350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	102
\\xfd94ff1971f12a7f093f6de7d34c064f2c9eac4e9b1d5f5b4c7dd8de8b6e162c209cf4c0290a5f6f9ee0d052e63ef54bf98315debaa3807890a17fd3cbd59263	\\x00800003be845dc871cf03f7fbf683e91a67949f791afeb220678911f855e603ef705179bb8c99d7a6adf110f53bc6f6ef2172e36926d125e52a8b0f6a624571d5e694adee12b6e9ddd55c94ecff6b4cf91f33bac1a4798d193e28541435be543267d40d8384c635979b1a289aa03c02d84d69e12cce80bb63e2c18db0e1e8a8225d4b21010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xbeed59d7908207c1d547feebeb35238b01b081ff136bf6fecb1d0970c3195c109000bdac374a04b04b185953a8e0fc6089134589621758da31fd7c0b7db9f804	1620631550000000	1621236350000000	1684308350000000	1778916350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	103
\\xfe18bba80c6c860a6a4eceba1944a8dfeb3272d0663c240c1b939a9b9b8a4f99dafce9c4639ed25e302eddf1eebdecc643f6b25d69018abdc9a45b2b13c467ac	\\x00800003d1774ed4aebc873a19ea4a85d1951a0c5156eb16c82e2c71a39cca59b76b3ffa7071090d90a8d65dda3669f60a61d1764ddf85959b5840573ac080f343ab343b4a4fca2c974115d99f7897beef6af9e91e970897f2f325bd9a372e56b584512f67981a701c48a59f05eb409c4fe786d91a8e7529a19aaa107e724b2a855133b1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6bbb6d2574a999b3fad35f944b6740605daf0d0a935cabcca5836e3a2de65388fb02cc00042add91f23dda7b5c196e0153b8fe1b2320275ce96f3b718a040b0a	1627885550000000	1628490350000000	1691562350000000	1786170350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	104
\\x0009ad3d43f19b9c9634d38182f27687ba3d694c4c85ee7ec80e793ac3b8b8965a106701c73e271e1f57ccc52c6d54551323d5ff4ef1ae012acc1705ade3bbbc	\\x00800003abc033660bd346a590a3a7d6e3436b254736912ad20fbf23cba91968795d4bd7250254864044073ef46163d70560842c347b2e891c033319345fa14f12b4211ff0c75294c1db2ac3ff7bf7b6995224fad312e04126f30346d7176123a50e72ed3d48aa1eac4baaebf85dea13e808d2d905d06d5a5ed125686945500ac794ca93010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9cca08800888fb1d81fabfc12623fca3c893ebd32fe062a43f9a57c4438e2098aa94d541519a56c8965a55f05c39bc34cdae3dde2feb7360e729b9d1aa0efc05	1632721550000000	1633326350000000	1696398350000000	1791006350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	105
\\x04b54fe1d7e224413e7443a0cb136ef15996c3772ee2564264bff9def4f4364b3e6c096892bb75522bbe286d22d9d390e5a7d85978c511befbd018ed5d409241	\\x00800003b79be761f90fa7102099feaebbafd628f58ba4f11956c6d4e1d22799be70aef93c821c72d22104ff9fde738d8d4c2fe1189e3b7f0709c01fa8524ce72a38c2ede9561a3863e2a7d4716f9973d7cdaf628f487327089072e402d7c52d811db42a0f8de6fe4b1f41b063f4b167b050f23026d33bd50401b5071f3914aedcffc89b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9992e7cd968f77160fa57c95da91a6ffb665a73b20db016d4049dac0dc0ab2047127ca9f06d382de7f1c9a8ddd475096ca3d8f03098c2baf2c1c176f22a6180c	1636348550000000	1636953350000000	1700025350000000	1794633350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	106
\\x05b5b5d81e1f3cab585eff737deb90ece663d18624f1bed137fc712f5338bc5b3bf371cd44ffa2a000fb1da08d78185350fd2721ab326d5fe5362035c8763d30	\\x00800003c7f9c242ffbc04a5d63c61b4b70fab537820ac38cac0efc9ad5c24e97d78cf1c7887ae38ae51ff023aecb828c13adfa7c9e61d61828b6a0bc6ad53d61f2eca7b0e7a10341c91ff98826ad5003e5b812d54bbe52002df075758552a7518f9d41c5d6e54edee20e2403c3ffaf4d9b57ca70de5ee233ec5b15e204dcd6323905f1d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x06a62644e966a13fb00647536a10a2c788b9da627c62120856c2302dfd56b9ac06695f56aaef56b434c753c444bb44f69b7f2bafde508cd9f1bad4bc0137b302	1620631550000000	1621236350000000	1684308350000000	1778916350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	107
\\x06113b886667c7a7b3e1472c9f44eb7dda87779548d34e7f3a17847d7131c616fe7df15ac70584f7bdddbe4cd0e2822e49d75dae1d3538ad63c50995fae09364	\\x00800003bf19d57e080aea66a66a101a625b64a133a08f5c777a4553b5783e0b0e14f2630f9063e42063089360f157919f2086cf13c779724a89c0c464594850bd900b1c65ca684b0518a754903b49906abd9a6e08c63b854d58d97cf5675e288195c0db95827151bbe0ad6abb36dbdafd5ad040a5b627f9407885f00af61f4fdece4f0b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x594d456cd1b39d19dd76acb0a6009f09bbc89da6d4bc852d9ed447a320d6f90a50335cb811eefc6fa7efd16802008752d8f16a289149a0eb74a39eeb8117b307	1633930550000000	1634535350000000	1697607350000000	1792215350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	108
\\x0af91c2775ca85d259db30fe36189450ac6d538b220fc7a0c5a29f62da2973ccb8571544b000e6e0b22d537c228efe3b160d3635fa0c44c18bc2e3af79b96b71	\\x00800003b9d8893f6a247e2ba631e8ce9d5eeee6b99114d1750fd833f33f97503d37bcba7062ee7ae8d952cc2d2ffe7a3baa4c4c0bd2cfa5aacfb4859a4c21981eae621fcd9eb56604a1beb290d465f9aba76128c9b79d9936b7d134f6f7c2f14ecdd16fa68e83b201508fa6a7e70afff2f541537af0a99cde9489a1e3852ad5494f7b6d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43ed0c64ffb0648602e897ca3b3a12fe6a1fd41496a8319726610964b360c125c9ba369c866e459cb6b0a12c57b469e665586b020f3c7ce990d39990463da406	1611564050000000	1612168850000000	1675240850000000	1769848850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	109
\\x0a85d84cb1bae6a00811a32de563a697c430456575dca71998e2e06074b2671dc0371e8a0f2f9063622ac8f6c44b03f0b151fcb9440a22488a050fab5c1077f8	\\x00800003d8f963b9a2b70a86871e058a67eb4c3c3ed31b462e7d2a28c3cc2fe93982484a26fa84eeefea40d7b789b4701edb9b7331f4e294cf36f4bb1d34b75395eb83abb68fe8f707c5b998eb39b8cb81a55bf5bc93cf8515581ea681bf2a69c03ec4446051de69d9044d00870105f452a9387d8b2a5285e8f0ace7b239205aa3ea97c7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf713ef17152374a822a7a71c4c1ea2c789eefc6ea72c6b44b3a680610be22201c41cefe757f62f9abdadc684a1259cddede5c2d7a1e83cd4161b4423f07c6e01	1620631550000000	1621236350000000	1684308350000000	1778916350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	110
\\x0b89032729d1e6f404f445a602111764c4bc8ddea34ce43d9b728cebc6415fbb6fc6e2f9285322bc670103671461ea82ac14779d7b48827cbb16c4492b484e86	\\x00800003cc7c0c72260eb6770879e5849c3821f8668a71bf5d81a9f405b83f0c0b73a68f672a20f746c87dcfe815606dbc11719a57df517775f0651938e49b65d63ca42311ecbc1e057753d6eeb2d6d4224079ed20819726a55a1fdbaf7c9b8d8b1561635d0737955deca53d064be01f725d2d7ea8c3a40b3edbba57cab9850bb1a63037010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe99ef22c576c73b39ebdf75265264b3b1501b9d35b9e18c04fb13b42e78a28868dced60c137a7445425c2d2145d1b5d3301ad137ea280461da248364a681ed04	1610355050000000	1610959850000000	1674031850000000	1768639850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	111
\\x0b7d2e69e9d2453189416e3052021fea692ee7ab757e33cc84907661fc91535eceef132787a9230b5faba631d1a21b49ffa52340fb98b61a0d2144aa0f38f99e	\\x00800003bf8d9afb08012cd7c44b4e28e6ea8827dead3ce3304fe7b127f3fdfc16e664f13fafe51a4232e3403f23d9c1e079a566fa1730134b7248da41292889212d6d1ec8ba0d9af8b5926a6a92562b896b14c5d606431cf8c3b89afe76dc5c145b5d04909840d779fd8d2082c6363e4d38176d56c3eb993731c4e253796c5128578a01010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd6436e0a185868d456dc7d061027c322d97756b18f4a067d6c5e69158a20771e3ffbcd1de05ade6f5736c9ff5400f005a9f130faa1698320a8eedc23606be002	1636953050000000	1637557850000000	1700629850000000	1795237850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	112
\\x0ead6b70f156506c29cf59ec5f6842509c774f0b8c1e0e3986fc99519f6d45b5de907f2d8297d3d85c843295d4b96c8b9260d6efa7e21c9a09525b41fc59c342	\\x00800003d111eff0fec43fc38f52d2dedd7b909c1be970ba772499a9f3e69e337430d6ba50122da81b21a3a3baa9c4eb06e33d59dd07932cda942c024eeaa183674b57d4bc862f243ed0ff7c1951cfd50b69df40ce30b19260a74a78a7dea221ac92322b6ef84aa1295ed67080e029d201fe33621eaaeadfcfe37bdba5d016ffec2c9085010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x864e8662a6592d53d1a51ce5b254a718c61f2afa547c0fe3dee276b7b3976ea02c866f85a375f1bea856ced42f4970da996aeb0e1ec2b0ddbe9340e7e9de7d05	1630303550000000	1630908350000000	1693980350000000	1788588350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	113
\\x0f45cf065faa5526c474867a786e1dc1ebc42f395f1b1c632a990a66c42524c929018ca7c94cd43816c18182a4f51812db2f166ee5aa82d1a268f43e356153e6	\\x00800003f530ba0af16b9b552dec69025f4f356ba0f82cd4afd765590f0efa8edd6b4abd2025a24d70fd0168ead15335583ded0f4225e7ea513160bc323761870afdd9f1351ff7f3ab9e948868a9690cf548f9fbc31d35234ba08e1d00f693e375549b9059f93c37ba254f391b69ea13794897ad43a69fd43fe4a6b808b6b2d16ad7860b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8375bb691465ec48d24909fcd8b30f2d85803f09cd6f418b7ce7e3a34eb2978620cb185550b99def96bfa21234bbcd496ead312348ce0ae718d3fbb59c7ad401	1612773050000000	1613377850000000	1676449850000000	1771057850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	114
\\x0fe5af448054d4fe9a35d41cf2c3c8ad6d84c82c0d502cd0dde9a0ffdca7d3c102de5d01dc3259d2394dc2a44ecdc79bb17a4ca5044e0f4646b9578c3d5aa1ea	\\x00800003dafdc3ffacd0d2b447ba5163ad207ad690a341f504154996acce6c176754d23964233d67d6544b2b4cb5e05085e7e2107e972a289d98cffffa220588c7aac539715c0837a752627e2b976dfa8e48368887cf0a82a82f5be5a8d42b62f67be9d2da8a6e0e922a3c57ab8e690b70482e3bb405812f314710f0b4db3469d7437a27010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4a271e64b8b672ce5bf9333526244a134710bd23843ac0aa845fe9a7ee3b0c36ae4b23cc01f885bc675c2bdfc34ab0b14d860b5f47ed87b99c9ebe244a72880e	1638162050000000	1638766850000000	1701838850000000	1796446850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	115
\\x10a1b968e6df9bd10ee557ee3e396a309f577abf984a7575130d8170f7935c7141fa5a7070787f60090249b399ace85ec331b7b18463ffbdcb85e31526c2a296	\\x00800003bcc9a68a25a013d5274be09a042a9f2558644d47b4c2e6f51c012f27700f5acc64e5888b711245ad7a49253207eb1c6db2bff4e3eb558384b01442df5ce479154a8488ddd94559f4f17f10750ae5af5d212a999819ecf7f10e8b7a575fca273d25ade0c41815327e12ca5f7736bad8c4d6eeac1b1140bcfbc52c84ff4826f14f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2e3358e5e3a1063b17a37eb566514a4db0beb6cad39b7d9d23baadfccbd1eb7a0421cdb2b76d33cb3e9d6c46459d1223896cca82208033292d5caba4a5850907	1613377550000000	1613982350000000	1677054350000000	1771662350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	116
\\x1249177548f8499c697af49aabfea002bc9eb211e65dce1ea7d7fa07f977d43c952b0a12ce957d4746a03edce1ee21f371aa0c7304000298d61c0981159c194c	\\x00800003cbea24c4e7a25d4d9fed89468db83b8769973f0106e682c8e435652e6952f03f7f28f61ad8f3431275b453a1aa46ee2abb2e965d31a181e6ece5c06e8b89f824e7873b35a8064d1ec45dd5b1f51a25442a5cb5be8b473b59f3d610c734855267d98b905391cb1995ed1b2c10b34f181f5889accb4278102ff269418102402b55010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x65a991a453cc07f768c08243d2565d0b065840004757248340ff556074533ef691c4905084c019458dc8b6ab4b723b8b0e313acf3c01167390d0d0f5fc32c005	1613377550000000	1613982350000000	1677054350000000	1771662350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	117
\\x13714cfde4de7164d0966c173b770e3f411125bf091f43c0f8f0a13cc4b09d897c0781ab13efa6f3dc850cb7a2abfecddd35ffd6aecca116daec2af988439655	\\x00800003c52163fdfed8de76a34dfaa9bdcb8d9273bd171e7dd508973b259d36034736b5985d7a4942d60c623230caf1250f27c4912fa3b887720336b3a6ac4bd92ce887816721ad1ca777721f66b648237a720ec5ecc700e2df4883b7ee82bb605b6579b4222f655d8c05e8ceb9700273aeae3e8d72334378dbca76fc1f3c98278e97eb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1915086d5f2a4971ce4a06d03f9b5090061a09b94119bc5b33d6b241af40796bb95ea6816f7ee47b73e83cde216dc648cb41fd840cf260571add55fe65ac160c	1634535050000000	1635139850000000	1698211850000000	1792819850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	118
\\x13f1289794ff3b438f4430b6d1a86a002de8910240d707407ce418990739a63dce2af79b99780f6f339e1535e65b4f11d229f9dac4d2ddf8d35214a1b46c4e85	\\x00800003b1985d0daca059808f776650456fd465f7e11dec6bfcdeee4d801c820bb20d4bf1eea25a798755fdb0b015e2f0bac9b46f540fb9550bf034d87f960f8a67b0f762435bee0aacac81f5860910e6ea0772a1011e0fd4723d6777ed44d8f50e7863e5bd67d8252ebfcaa4afa22bda027944f9518a82378e7c1e28cff01bbb44479d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x22cfe8a7cc770f560adbf2c9e38f5a699556df060ccca64d30bab4a8db47239a9b1df184106e33480211dd3254ced8387263e3f1122f55e9d4bda05286f11902	1618818050000000	1619422850000000	1682494850000000	1777102850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	119
\\x16f1b9a1747ba9a5b6b8052279fce01e6b09c0e018893c22a68dd8e084309858f6d5a7fc6edfbd0b2ff03365e79093725320ecd1218e986e829bd6079598bf39	\\x00800003a580ff7eb46cb556f4a031dbd9b043ff810480292cbf5600ba5cacc7fccbfbdbf2a75b498bccf857470e1be00d319220378c4226c2cfd9acc5458b8f80c2a67cfb88f1bd475c6f36eb78d9afe33971786fca1d17f77edc031af85a4fc2ddb5e9c524d8614b56e6d0dddba0ddff269653fd8acea370d594a58df8d80c88b0222f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc1976085e6567b7810d5a2883357dc6bc28dc5939dc06a91186ee716e389c9a06fac2015d6f4584422c865f6c45da097bd567644d3d73738576ef2e1fc8c8d00	1623654050000000	1624258850000000	1687330850000000	1781938850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	120
\\x176d3a34a542193a57c43d4d21773646825081eb89d730423a280ea6bdc8ca31456df1b170443e493dd42f5133bcb42f011a29bbe4c1d71c31cdd7b49c4af8b3	\\x00800003c8402053bb7fbdbce4b752b5a1ecfc2baa63ab35e3507231ffb62c3845aca38bd55d31b899786d2eb34babaf7a799ba6f44b53bf8bc5b2d64021b792c66210a4db9e2d309ea2bcf34b2fb06eb15d4021d4443427fada5d5723d5af541364a084e04ac3b0972a3c6ef7335892fb5aa90ea7af6757de714f0c527b0f1951efc3b5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x187bc7ec54146ca6d655efce175de483b024aaea74051ad5bfb02164899596d8cb7d9344c4323644c134a2806a14c0177dea99b85ad83a22c1d8ca6b7df1270d	1624258550000000	1624863350000000	1687935350000000	1782543350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	121
\\x17e5c08f8eced8c093ccd2261432727ccf7fe2f07542d59fcf4eefaae269a3f72a756c378e7fa12d7731f5723a319bf7e8fad649d7a42f907bf62d03212ef96c	\\x00800003d8a86917348fdcf319862b1f98eb96727de9778708180ad461059ac5b0e74e2e9c297c47a1d804a41d668a8088e9e377b547380f708d9d34e92b5f6f1d0126ead66bd5d42a3cb7eab5616414dc3e71881ded542abb772d6822cc59a5662e7046bf32f3e6184cc8aa327c58ad49ebb093c5fcae6774fb01ebe115398ee7f47b2d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf1c7b419a539fdb30dcb6753d2556fec2f737d29f2d1d5dda3763e05da5f3c24f6d9ad90dd76b0eee97ca12dede289bf5c5623dd2b6a02fba1b4d9ce43adfd00	1641184550000000	1641789350000000	1704861350000000	1799469350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	122
\\x1b311ad8fbb96da34f2f56c485ee85e1d82bc23c226a93160796c21f6b923590488c366cee179c86517881758a0cb1c4bb21c6b87ebb1670dc0199120de58f1d	\\x00800003d1476698922dc94703847c30d58385f279f8d72b73714dac1b44eb58c550cdea2c605cd3186a9ca9e5afeb73d7288bcebe8be588884c4ec1067a138bb7d986a5196f5dbcc9be9cb9f01f23422b969113929a8134596c393c1e0b53c0320fed43e7a3af20145eaf0055f11985e141eb8111774014a8325b1d4bdce02d50dd0dc5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3a4a38ddf16a1620fd5b26bec591ebb3f2bb137ab24b43108017a8d4ae2b6b169aab30c5f5d265c74dca8d722c1ee214117a6ac4b1a83df766be24610c481f0a	1628490050000000	1629094850000000	1692166850000000	1786774850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	123
\\x1f0d08b900f20b784574d668447ec8c787c7457bf6cdcf8826a1710f7f2aa67492ba6b8267dbf1913b751a79133ef39049407a647b56c5717239d19e50723d93	\\x00800003c03ee5e82c6076e651f2c8635932483d4a1086a8a9d7f233ad0b5e7ab1aefb717ff3e3ede972ccd2ed90cf866069c3b114bc5635d242fd4bbb9de616463c9dee68406595b20933a9ad6c9b7939fb5585c58752b7b41d93b80426e888aa3f3f7102c570b39cf679624e982d9949087487fc0849332f291771a1048cf5f7bb279f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x60a010099405d841a489451e08c9bda9919a3727009a3abfa611d2d1a87993c47b215177275038efc9d64ac19a66c7ea83a4b2861dfc136bff8b2354a642ec07	1623049550000000	1623654350000000	1686726350000000	1781334350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	124
\\x21fdd3f14be9ba99321f490ef6deec07e6241b24b7370b619dcabd77b158b8facba7ae7b3a9d64a5d99c4b0dc41b40a3a5bd2511214f8ee720afccfca0689764	\\x00800003b12f2a5667c4ba7b9534c0653345dec95bd73874a6419a6f17bdc4878aefae0245f10a106f7fc853e1a9c465c4b99dcad20036584dfe5239e53c5de71a6400237edf7147516b65702282a58710b8083f4d6fd0ba10ccc1057a42b099d75a46ae3a77ccc4a252bd54a67e776eedff0f5068e8212faabed14e7ec77948b654a793010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1927037cf7aa35deadba002c4c523fb93137805a5134a8d23f915f052e17cdd04f9a894e0b92632def7ff879ee0db88fc31653f1b060c456e993d75a91ff0806	1635744050000000	1636348850000000	1699420850000000	1794028850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	125
\\x227576b9e82960d4a294e0548add9b8375621885e79e37950882cfdc82b1ae4ff677557cc9654415cebac6aa386bf58800f30013aa6463f289fa38de9a91a61e	\\x00800003b107a928682a8903879893a1f4e51ea59ecc2879ec96310e5beeb16e139420090a399091c61333e94b3cb39e865bc4b94890f5c268704d9168b342d41d91b7e3df9b6fa87ab49e29cb754803ea7df2e955656f85d7ee397e3a746883f92073f3243f719f45eb1e8a8abd7a55a20c25773b8019724b4c2885a6e35fe8caf97173010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa9e58a30fddb8b9955d58ac6f0ac8034dff64a035f19a2b2ea6c6a6dd27d20d865a383eb75daae2eead763c60204a788460b307ef6fadc577f1daacb8f6af207	1613982050000000	1614586850000000	1677658850000000	1772266850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	126
\\x230dd2e5b5e1798012eca4b71eeba8b8d6a804288bab044d8621e8145c68c51b14b128590d77180c2c6daec123f29b6b37bc8615be320ed94b88859687ed185b	\\x00800003c46fdb2477e9e3a5bddf066d84efdbc4880d999c04b173548bf71f7f22e864bc5220fff437018efbcf249cec9fecd530f0530caa07906158c67e624eba5633daf11395ca36f95f15e67df42aad43bc95700390613a59f9bd2fcc8c9d573c7535a4a95923cda31861fa6c90bc1ebe8af883ac0fbb6eb2288d1fe8c9131a4e189b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa0baac4db0f214711abaff484615685bd5f4eafddc3fdfa2f6cb6493689989d4063b6c7c7e627120432a5b796f2f2bed05c6220ecbc20a65f449950e9cf11400	1613377550000000	1613982350000000	1677054350000000	1771662350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	127
\\x25d5f86c4913372e18c379ad7a4fd5eebc151ebfa7be9f1ec413b3350bf2b3f0cbe69fbb9c12732107d38b0a822676c18a39082cd5dfe2eef1e21d3a1000a6d2	\\x00800003da363e7d440c498387346ff583f5e9037fb9e4c2489273d49a2ae79d74a2417b45380f8e1e95917911fed7151829276c65e779395854ed318130045f12e7b072f648f974ee59ba99132f769991bf0647087266c574c3d029e50ba3f953d26a469815826ebd1570be4a19b7a17225705b6c610a6efd8ee41e0831efde3aba410f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe4c51e548f76df7bf06fa6c0c7752ac324cf283da8ecd3b899565207b1d8fafb3dd980930e4e7ddf08acdc9fbf80d3d2d89759264068829cbedc9bb707adb709	1618213550000000	1618818350000000	1681890350000000	1776498350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	128
\\x290d5199cc98b0d6e8c419349572c126b289c9d8c0bb6021e334cdeda912899bee89e64fd4ea13b84f4e28be6e00b4d1ce8f17d1680dfbd5e14db38959b3acba	\\x00800003aee72a17bc9f272d0839406ffd30a1522c3b6e798d5c9036d65f8a138255f98319d8d32d1695ce34b39135d18f245b5f4e7286b4752b686002d720eaabf3475de9402f2b21979e5f64f865470548d473516e272bc8981fcffd37913a7f718e562a1d9adc3560b1a6d4ee4a59bea077e5b42c4f449fdba8b0fdb38f6bacea2049010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb1da21b2ec5b20d1e9cbb8829e30e879717ad6f5df574ea0daa0988cc57106574d87f44ff0dceb4ab61622a143aa2fa672e590f96b3b38e2f3dc45b00eea4e05	1627281050000000	1627885850000000	1690957850000000	1785565850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	129
\\x2a75940f62f9a09115c3e336659aa086497ac3a1e3718cea989b961e1b1e00e92d30b2e1f0b24a14a889b2d992b6193ebb5f9c7e9d1254dc593b022a4c550f66	\\x00800003f463a5a1d2e9b2b3d8e808ae62b8b8596be627ac9592616e8d9e1c97b30b7bc8e23f44cc211f86a6cb0af43f0e485023ba6d08fad5f3aa1302917f0acf3f1bdf39a0d70ac1ad1b930c2c15103cd80f91904284cf9971c3cad26dac4ab42c121534a2ee2e5fe12b5def679d0e3e6037d2aee98be019230ade4f55e0444033e7b5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa1d64c47841fb7be6c6170b877f6f9159fd14ae4f27a6b5788e4e95a267ff2bca6f34ba292d5327fad8daf72b00315109cfe182c0bed590a9d376bc202df720f	1631512550000000	1632117350000000	1695189350000000	1789797350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	130
\\x2bd1f1b0747fb5ece148cd30ab9254d448d488e20957f4f893fe28012137e76c9f1f4802edddea5e5d5e64ad47dda06e95a8035646d655757afc5124092cee32	\\x00800003a8e5f70a1d7e8d56767c56d8d778bfe96e388d65987f4fc29217729c2e99a26901f7b13b5be05ce1e4dce7ed23692f65e13bd14135668777284cee1e7ca2234660df567215a03170c3b4c531e9e588b885d1bb703a5d99cc19ebc5ca9a975af45882c9988f3982b6a41c2573075011f697cd9dbe07d27fa1c59c8c1006cff481010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4df0bffaab3156313037956e1e36024c5eb6f867d35b5f8a1dc98ef7c4588b14cd295f65006b03200afdfb160911c0ce01fee13ce110e37ebbe7085a68485900	1637557550000000	1638162350000000	1701234350000000	1795842350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	131
\\x2c85f9b30f0b070655af6cc6a7e36a225caacbb571e5aadfb525c29b2866b717023e8c3ca4807f12b0e58273a024458d2aeb68bde4ccf9ad383f4b132298ac77	\\x00800003b92779d00c83bbaa3806bf46e2ca6f1f72a21badc7461b3efc086479cf837bb87d75a693c18e1b4889d9aacf0cd3163af0fcc429a2cb5bf4317419235f8e46d41ac8b07615f89a6a876172b8e076515dd44b810708cfb70d1ac82ddcfceeec6866fd2bc2f13d165779de849d8d3f3976cae64f3fa0fa2b1826175d49fab32273010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x28ff76ab43e258b7a9b8c39d2c1eadad0022ef3979e56a86b4ac7d54fe1e8b48c37db217cda8cfde19aaaf853c0f8c69de113f76e19c67b986c8d764c1ac4701	1635139550000000	1635744350000000	1698816350000000	1793424350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	132
\\x2d655877117328cae1e890497fe4bf9f9c03bb8446c7d276ca62e2d0668263f60d69d8eb494323a03f86e49a8bf3e5427053bd7b6f4fb437a3b40dc3a9db699c	\\x00800003d576237c6999e2ff4e857377113b7a8d4f83066ee1c50f7b8eec2101232c34342d1c593e18f9ff9fdeb4ed29f3dbcac5ac3b873338b4c2310e14d317f915b8b06c70dbe203309f3fc578b5f9ca7b57999fbe480d1fec371a5939f1d24c05ad30ef71051a183bb7dc8ea947097cb26a90e6ccf45d6f9e3b94c06e06576ab17b47010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa331af1193cb22b9f53f7ddacea37ca5efe961f3104ea85d5b58c07af45adc57aa6746a37349996c5c12c7e08c4faa0cec66c4341ce9725ca7f07c4677acdc0d	1638162050000000	1638766850000000	1701838850000000	1796446850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	133
\\x2fdd67c9fea5c5a88ca7b69f3692c92359817af24b4009d9ab4755fa93d5ad0bff27804dc5ed4f20844848d049f8b8c8b83e09a2db5634f261c55ca8294be53a	\\x00800003b1a52dcf69d97c98aa9f67466a9a27f92fa25240543b26491a43abf28193667eb0feca558f3dc4d8ca4fed05493abac40993367284f15605a03698d24b4c5d6770cd47f83223f91849bec72c933aec03703f2fa23b952edfc0b3e6d6f98168d7faaf6fabd24db9031fb32efa2c4db9226344aac94a80bf1c2599260d4a51f681010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5da69ffa699d917fee5db54083f44442236665af016db6ac407a4d41333b2bac1127c1ae6a07b3c37c4ad98391f8e82a344894daa412c867919bba32d8470608	1621840550000000	1622445350000000	1685517350000000	1780125350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	134
\\x3079a6c254d97cc2207f7ef882cbf7e750880c861e20e27460d7569c8064189fc4da30b3669da0461b08d6cc90c44135d28c5544fd5c08be8c0cad9d7f9b7585	\\x00800003ba9a9e53b0312cb6215800761fed9cbb706028239966fe8aee9a1d06019c77413fe544e726ac4183dd1d56e8aa4496a145fd31a135eefbeeb221f5927fe2407fa8c9f9b3e90fbb564604aca7e12b4ca66ed1f031926c8f9e7c1fd5aa0a4d54c32d85532b9bded27cef56d299a48c442e2e5eb05405dbc319d61744ff0d48a03d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb5aceb0fae69bdba5178edea1fc722102e237b3c3639edefbc14a32bb07996cbc953190d8c88f4022fd21a7976e3ad90ebe7a3e270ed791dc50a170f85b0c80e	1614586550000000	1615191350000000	1678263350000000	1772871350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	135
\\x327de625aa564658a9e9bfb7a3f0d2e9788cf10b9ab8db1c9537f36354dd21448d1abe9adb45a1540332ac47270a5d3f21fa8342c4bcfc9913282b700d6d2edd	\\x00800003d30b3353c6ff6510958e76f30809e51e293907fadb730b0fd1e8b818f8a5dd3ecb2fa9f8853a9c01906f3417a5187593003300513cd1dcf9a33c6d358cb3f34cda69882d450875fc9cc7bf769c66acd191b1fdaf448d9b7e0e703d5756107f5dfe28fe411f49dfa8d5ca5f70ff86b1dd12c8b8c36fe4dd260d19e83a47ab0b9d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8ca10d2ca7396a9b9c39b9eccf5cc6ccaf498394a13ab6f08d56c583e2c98f2dedd76966d9d8cd10e28c7bd9a798d7f3da09b17e09dd6fc9fe4b3280e3e2890e	1639975550000000	1640580350000000	1703652350000000	1798260350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	136
\\x32c919b0a05ed890ba62022d3de3a4a60e12f68571f850704d54926d5d3ceded43cbb9f1b8c1318c24bd3fcbb70d1da6f0e6f0ceaf97b4c0a6c114f89a4d8a47	\\x00800003be116ff86745e67f05e42720bf6c4c9c86c7ad264e44259ad14b1910a264200c13299fd942a8e5403421e07297a9874383abce5908a400471664e78a5d195dfb7544e4fb13b990fba9a46f5b75ea9261af7d0eb21605a5e13c0633bd981e5751de7bf054108a618014fdf3ede97265a75705093957c2394ce76c473a8762707d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8c5e39e9a5106c868be18a34fd45096a06b50e9c1dac5b74be874cb1d8319a14fbd8494c02962023ed67daecfab87cd9d83407bad737938a3bad04c879670000	1616400050000000	1617004850000000	1680076850000000	1774684850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	137
\\x38412cef0b844306e5e5c3ed23a81f0d9effc8c117d0b8679a3dec260b34ee64b878912ca91631f9bd859f3f650e64dd62efdadf876dc24b714c1f094cb30680	\\x008000039cf16e404ea6ee34f9824e5829cb5ffebf03a33f245397fbee12c1e73d205e2fb18a9db46a17c2fae06531ac80d697a3c444402de3844e33b0aab8688dd83651fe108c141ff2025cf77eb13ffa0097cd3cb5feafe42f1b226936e50231628a43eedd33c03a6ab2250aba17e0ecd8b9de915cff29f3e673fed5b7e305a0e4b131010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1572c1e21ef79dac57d83723a68848c191b60fd882863a1a7465377fc7e470d84f52a99bb042588c23ad46634b058b29c4b9666467c23cbb097a0375ae08b207	1635744050000000	1636348850000000	1699420850000000	1794028850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	138
\\x390165f80666303d4059384004c89ead7dd08947bc044a74a49ee2759e906063d83cab7d0d2950c04fe35f82b157c271ea6e2373b6a7a01500dfe4c8ed3316fa	\\x00800003c4e4968e98ce5f6d97775b61d68b37b318790319c91a0f09430f9e93a395b4eae01582519f8bea2c10fadabe9cc78f49ba555dff7320d43c30ce487e41939b740c9064ab9621d8be668bb7c381bb9ceb3be10364b494a75884dfd6411404ef880dbf9c3a327e83e89aad360e3ffd680b7794862563982126c2ef2308ed8df1e1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x63007d9a88b8d6df25f361f67aa0cce1d09087efac76b8e085a9813aaebf2bf00678120734bc2b59784ee760ff63ee7e59a802b5572a4dfc5c12be306ae00f06	1639975550000000	1640580350000000	1703652350000000	1798260350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	139
\\x3ba9f84590537cd89749a562b9d6aab3dcecf1826b74d2a8351bbf898d3c3fae14ef07fc6d7f03fe956f864761076c58955517c66cb48440219ededa14627cd3	\\x00800003b104e8f176b7e26e094f6a06313e550b9a29f141dc305358bb6272c08fe7cc4a8cd498c5d01c7841db8016b93efe38e825c4209d504eb4d881f5db6d27c08103a961527d1cf0d1611a00965d2186a8f1605287ce58b1a7a387bdf1ab7feaa4d40b6c53d2d93130e4d391ada86bf8cd998ba8287b2a634d6556000c61c6472225010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x119c12639b75e7e5e75e9c0e047879ad26c03e7473f923715152dda5ab54e0a07617a45fd0f6f7933aa6d8794f9d65be6a8f76b9bd9695cb7ecc6131c2ee8f00	1630908050000000	1631512850000000	1694584850000000	1789192850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	140
\\x3bed0b547f0bc8198a21464e683145d54a16c44f76a4af8b0905d55fb210b85af0c04dd28d515b32d55d0c6bdaa48dbf43b4a733ca432bf2e4b08fe3f90df3cb	\\x00800003e83d7ed4b6d57ce8e0ceb3be21a6926edcfad50253ebd62e385cd4c6bc0f6fd9cbfd1fdc9de7005e894b3a869fe38485a7f83e0614a6f921e3932ef890da1b878bb5018d3f6dc214858d1688e9d165004ee75ff810d9c5a63a9a949568ba1578bdd36f50ad023e884ee5bf4adbf1eb218f194240899f5cdff5c6fce428e72b49010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcd697dcf2116b6d5e6a7f1aaadbe2d3f7f1519ad30b1b630ac33a0d2e54801e2ebc08344a57095d59c08e790a3d715f852b703f2cc1c206c007377da5c480e02	1639975550000000	1640580350000000	1703652350000000	1798260350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	141
\\x44fd0714235afa5d637dfc4cb94795b67a43b2e9bc943d7a05b00358d3e7b5315bdee83e2d2c494b00789c1ac92c2f1462fb30fd24c5f899476f766d5aaf49c0	\\x00800003ac9faed012b5801e4e7fa3482cadbed6c1f84bf1bcc461a83d30132ac4077f3ae49562652876166ecfc2829340b3abf8ea2893bada61d981f726a647d8c5e1f0667966a97df6fcaac0c09bf2238bd5bfcd220389833a28a9d8795a752667653449ad43bd2a37dab98e25fddda8c0e1f5b325d8af5ccbabb2ac53b54e4ff78707010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4a77c1e4aaa97cb8b259f82fc5a37255fecb4376f3ee8a871e2a7cd41017a061494d0b8f11596a8327214f0e67e943675c4a60f944483026cf1a542c9ec5e70d	1615795550000000	1616400350000000	1679472350000000	1774080350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	142
\\x466d7c69d76022cd298acdc8e4d1e533789cd4fe4390704ff09a9ee70b7cdf19ba601918edaa2d0beccae9995330534f06efea3c3b13a36ad0b5113e1f0f1ece	\\x00800003952d6b0aa76b00f515a16672683afaaecb3d0aa66fb506cd319d29e4faf9ae8066a0889d7ad731fb8660168dc155a405d1d00c963e1d42e0fd63ccd9586af1f620823ef7949ab142621906a7ef668b1cc8131451351926418d372fe2fe7a5f44060115e3f9b3d3bdab02023e3ec2ad5b405194b2ff7311e4c7c834621bbc3ce5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x26fbc3c312509e78995882243aa77eb952464d001ea45d817367817779cbea76d054c463b9ad4f776a4c15a28a45605d99509eafe4c22efe7ed8c5cdf49e240e	1638766550000000	1639371350000000	1702443350000000	1797051350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	143
\\x464d6a9256defdb18eaa1b45ba0319e985176174484fd1923c93626e403c5e784e4912887e8beeb679b90de7de98eaafe2f3666921a4cdacf02158c39108c993	\\x00800003d942f174383de0de39bda8ce02c8cb1e83c49c2afbacc1d9e1044836be964ad9efe9a8d8fa6aca5bbb921fe070d58133bf35954761f7dc89ba56fd0a1a8d6f97a2568ed1de8338371e801d7a73c450a533606e9ae446528eefad7bc1cbd7cd6767ea9672490da06a0a9d605f39ce1a80885f96746c009c7a734614edb8d82377010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9736c99b629b1d72f18a71fcce16e08eafe1a820a160c98eec88a489484d90bfa62814f8b9bf31abf03ef8d9d6279c4141bc7e53ccf1432e6b1215b66a6cf40d	1619422550000000	1620027350000000	1683099350000000	1777707350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	144
\\x4dd9e07f3de9a509f099bf17a86f103720364091dc0e78a2ec4c3bd72d2fe191d8d815c6cb7bcf2b5f559e8b7c0f48a1b0c4c084126362da717c6b53637992e2	\\x00800003ca4a60ac95ac3ab661d18b546db2bbbbc3ffb7953c6bd26ee2c12132976f8d6eb7553e5d6ca2cf929f06e00983b57b460e8a81953da42add258309c607ae46aa0e4ab95922d8e560f7cc46d0c58edbf82412906f4284316ffbd1bfb570672c83552930249251e7a318f59af878fa76cfc360c8e77a72046aec8f5c46047dafa9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x446f039755e4881c67244079887acd010b4f806d2c1378af454b024004bc2d805db7d2d97a074c328749ed30ebe52246a53d4197e6337a8ad25e1482b1f0e40c	1629094550000000	1629699350000000	1692771350000000	1787379350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	145
\\x4dadee3389c23541b51b1bf319e9fe70fd9dec37251212553efd40183227e26ef3908d587cc2b9e4ca38573ccf6fc582b3e733c3814764218a63e4e37fb105ba	\\x00800003d4cc97f12bb6545a1df1030726aa55f6a88a52483fc1dbbf29f63807a7f4ceb92a18a20562a510a65f9ab5b0579c90cfb5fc9ac2a294ca98ef58d9ad670986f94911a60bb8767c7532781c6d1b0ec14c6f70bac4698ac8137399e2ad4729ff172c4bb0ac25b89a6cfee9a616b28eac2bb0585d317d8ae61b978cd55147eed775010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc4c1fafd3468fdcb2771bf3a21e54d18939a308798bece6072660fd66efd0d16bc6f407a48844266745135a05fe6cf89bbc19f6e755c958a6b0ab7ef6aef9107	1611564050000000	1612168850000000	1675240850000000	1769848850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	146
\\x4f8537c9fc502954cf118f28e12971bb84778e779b75712a2f92b7a5fba827a71321fcb164ded60c86feb6e6fce2163209ab4be1c35d866e61718461adaad0a6	\\x00800003c94292eeefc0876175ba41339fd549c106ad4c6e9e959f60703023d1f9c0d8776d2481211f319960fdecc54ce927de33f3f47ccc029f58071529120cf630144da7964adaa3ceae7a200a102af05c0ea9c960aecd3fb4e2bcc90d69e4b28b994de5761bb61b368871456041cb0f65bec70fa91b9e3234ecbbbf6a845fc007bd8f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3de8c6f1aaa99fd8bb9673d6ffefc7cd13a35ea7331698f9b612700ba065c3e8715d9f4a3f907f820569d117ca75d919df168e8c522862fea94ae7b5453c1608	1620027050000000	1620631850000000	1683703850000000	1778311850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	147
\\x5255bb76bb0290d3d1406b96530aa4d8d57789e29ef07555362dc039e38304c6e25fd0accb91ad1a593406604b3f60e87fdbe780d49dadaa4660c3d649c9ca7f	\\x00800003b09608e82da41c7dd42bb9b7c947c09d37a25580c043d430860ef83ae16cf4e7d74e32f5bda5a61088b8154e725aa9c3c1251c9a7b8cddb3a1dca7b665965b98016c7b5307e34357da3335d94557be9b80e916b830280471ae0d67ee25af67f9c111c391e90f21d4c1fd1804f637edc27beebb09191a7eb8b047900bb063ff9f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x38e83b2e2280887aaf095c788b2b75bde0f3c8b0979826843d5ef19e3271600feb97ca47644c4692e3cb49a30a284be2ab803aa165cae031b73d0964d89d3c08	1639975550000000	1640580350000000	1703652350000000	1798260350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	148
\\x52a9cac2420f821205b1a7f9bb0a452fa63d92cff81025397ffcac4be92d4690a0dd37a9c083c1489af916e2a912be58f83d9fdd518ee1385142702055fc92e9	\\x00800003bf595056fc46b9769e5708a99829fa4ac7521844c326ea003fc5e51c35dedbb3d9b2727ee6fb9a95c7bd46c87eaab6cc8fa9e769ef36956f09021e192bbb8bb18782e6750a36fe2a3fd95e62e7f664748f06a3e44d0cf64a737ed704c094fc0d831247725069ab306bfa3f0c1b381257efc15c0bcb2b990aa1a99f9218d9713f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2ac9cbc7ba663fd32c7bf5ff54c586c9e324bfad55050a0859d2429d21eadce9d1d5c1beed6721fc045272eec9afc3979684dbeafb73a5d6c276a75f9555770a	1631512550000000	1632117350000000	1695189350000000	1789797350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	149
\\x54d1ac94bcce42528b4e6ef9055bd941db0ad235f3c924a0d1eeca2913bb9eccefc6a3a494a40063fc145f2011bb800d3f6f30bf97f24ca91b65ea07eb8edc42	\\x008000039809d267066049c0fb8605002cd8ae9624ad496448e94ff9776404cb7222c688a6d5adcb692aaa5f470513faa2975f8f46eb09143e2f1d9f65179a6b8df85a81cd57ae5ba0204391dddf207c193fb11bd23ef2e500bef8aa18e74a1f8f2ffc81aeedf807306157df563eec2ec9fa4865776def17c9a6b9bf23a75e9c69af4b13010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0e3e67c5df5d44a3b68bf6e5dbdbd662f3c6a0cb7554887555a4c49a36496a5e168b725ab0b3602ef1f5e8ae381ab0310468c2c90a309acee03a74b800ca4a07	1617609050000000	1618213850000000	1681285850000000	1775893850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	150
\\x56edb608e520e7f62d04e7b560ef3540db49b4233613c9b420c28a5c47f5a2b746da1171b3c5d8d4ea9c590b7df9668f940e3ee89920a8adb46bc64f50ef4b62	\\x00800003bd8aa17051fba40a024930aa228f6040a74755578d768f1a32eeabce696c7129a754323a5754cf87095cca28329f8fe68fb38428ad1197617d14de1f9ef71a61f83ae8eb6da687bc5ba37219a44d67dd7d2bf320ddf5ed23002d31c2d9c57f9651bcb48931eef2802247a4435407776256ecba386cf8508aea7c2b536631d823010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x18a896cfcce028c6de9bcf4e5c5f7367e13af3323ed95b44fa9b86836cd75c37f713f7da14344ebecb60cea5c8071ece3b9ca09d2a98dfc4c51c487a0d2e4603	1616400050000000	1617004850000000	1680076850000000	1774684850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	151
\\x6259a9a22719394cb2445db97d996c28a142c2fee4280f362da8427e2f711ea7ee9603bd73b594c340115e0c6912c2aada2677f6291b020c8b2e399a207f7108	\\x00800003a8b9b7f2605775d7f26e91fec1c76aad2a7abe96f11b3aae470116c8254317cd21899613fd9454140a09dc87cf6493655c0ed885680ead3d082c129c1dd271a9db7ee702f7cca29f1b239679855f36257a8c49739997d576e389dcfbbfcc6a50b8c2b09273d79badc22dfcd5ed67ea0322bcbcce657e1b933354d057bd3ebd85010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xab3266bf4e93a6822e307f299a5bb9fafe79906cff6a02c84d74382d4c5db51f85a540db2b5fea926d9aaaca5114bb7bb64c0f2228cf00397f036d2acda19d07	1613982050000000	1614586850000000	1677658850000000	1772266850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	152
\\x6441c2579d8ad541400804d99580acbe56cb82275e58f12453e771f6fb81bbbebddbae5e2980ee2e9596c02a235f50cf962e122ac902630e6f8fb84e48b63b75	\\x00800003a7248386d908da2148efa0bfc4de3c413919b0387e24a7b167bb36de733abdd57b077453b993c970d68ae9d4d1a975d41d8a7ac2400d04a095cf5920d4475695f78b22117d94c5cc8a95bd929daf29d9dd9b819b42346c3e37aa836b84eb4a8fc73947e3bb48c807d2a0a87678c4ab9d590c8c97d0d23afeb92d451c38755421010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xae27a3ffae15e1400a3db2b0800e74812021ebd9614032ac6c9720cf691f33803c32ad4ca3c9a23641365395402b91c7bd4c69860c3d3750fbecb3a7adacc309	1622445050000000	1623049850000000	1686121850000000	1780729850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	153
\\x6481487675571005e732cc74c4eb4809a4cee079e2ec6e51672b6cb66e408cc6606dbbe8c88762273eae8b176cfcd519e55bd7391f345c44bbbb5612b62952b9	\\x00800003f3c2469cc17b5b101e90ff117e274b4538d36f0039459be8a23cd34c40d0ecd9b0dce9749b4861a17055e3ccff1e0f8095b859b443d20fec068b57e18435aa7706787fed56b1a5b75913bacad757e2bec80842a59c96d7b2c4b80744b7df171bbba4ffd77c433bd4a3f02c3d49581bd3632bc341cef2a88cc76b38b136dabcff010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x30f561a7c79832c44993e130f42966b4cabdd9b9290bb8fec10eb73251610669dbf71f84185507a2cf7ac8f9dfad5a901d8c74a46958c6e941400f6bb05f6600	1618818050000000	1619422850000000	1682494850000000	1777102850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	154
\\x6499df7654f6ebfff4815692bb9fac8f2d9252b4118462a034a886aa545d7a7ca9c9746de6d0e91034861194e47cafbd8a3deb3c274cbbc6878438a630b2a19b	\\x00800003c224f1099e4ddea4145f6f8e19f58aff663357543ee51bef3ea1036f7448be6babc9a4cae4dc14786b999d6f9725f123dc36d2be080412b4bf08856706d6c484c27f3584fbc302e576139d0f10a0281c65bc0dd748b1f8cdc9f26f9fc06181b9c530f14d00d7ec72c9212c4abc08e6910ff0c17ada01423548d31f53b41adadf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x00a95460f28ab11b0cb06022142b83d2a1aa8a56cfbb32bc684414da633312c1634cc16f1d2d71bfc8d6e9865238a1898f16b444623300b69b32e0f096f74f02	1629094550000000	1629699350000000	1692771350000000	1787379350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	155
\\x67f9ddc04e54e1307038f4d2a02b3a757693203f35d78c7dc737e8f61fb1f2c1a6f0bd4c457c09fe839b7f1b6d3827f4ef1fd1cb5485ead2c1744327aa1a6359	\\x00800003ec03137aac5dbecc5e54a4763c97c7aff7e7acb9710875def6c50e96c5d5d122eff477fd252d2c83517d0ca9e43c520f4cefbe6cbdd3c3edd36622c99264afe3ba3d7eec4e575fbda2186725e8cae3bf202047abd55cbc08bfb984f591f6138f2d4620598277ac931405d9672f3bc6a4b380f4e72cbdcf24e309ce5ab1fbdb51010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xec1cd986a0ed0e10d19affce095778249beb8f5731ca92311162ac035d3d8a6a6c10f82b02a159656affc0fe147fb7761b4afae3d30535c3287ba33904d55707	1638766550000000	1639371350000000	1702443350000000	1797051350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	156
\\x6871c15808aaea754909f877792ce57ac0aba2e1d1cd730c4fba2570701a65562da9d22f5a2379dd6bd2f58ec9d1a74d3cc8dda3a85d420d9459ea95b2f0a965	\\x00800003c18cfe9524b7035b2ab88e0989a919f3f6f91156bf23cf4b5fef94290c509548c1d53ad3421f17b9ca1ec38ac6a1bd24227b0b49b36963bebaa25650b83063683022699ca12a52078c0597c0ae05b7c5bf06853981f6850bcc2139d3f12d693f05e41345086b23d25fd8ed20c449aeb5041126365824d23aad57fcb1b3aaf825010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8a82770578f98accc41a3e76233d5df22a0fed29a7d6e389cb024ac036046d5f5756d5e18f3ed5f3c2f2a12111fb534bde28f28fc259239d8ef0b79202dad809	1620027050000000	1620631850000000	1683703850000000	1778311850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	157
\\x689d838edddb84ccc1c84ac5184e7218a9cc7879afb8b13e3c37f4937dab814e6098952a41a2a74edd04189fa70e11625f02c504571a281c04a3c623bfa51835	\\x00800003bef89ce18f000c01a62c92364859ddfaf2e4177ac5120c54e8bc209965fbed2a2b3c8df25213abdc9718e69876aae166720eea5f2b904b512769a09da88589e3912c9c635c10bd223a39d7bede17079fa38c3dfdb1d672e54a0ef3102dc0d7bf398c5b94edf418fc040bb3715d9dc52cd8fcad8477ae01b7d5f664be5f1920fd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7f3cd03a4f5f48e211cc214339632e931569559dcb6f0e93e9fcae149a0a5a13d0bd46439797df58ea8074950ae1c7f42d20ea1c61590776c779cc6a8e094a04	1615191050000000	1615795850000000	1678867850000000	1773475850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	158
\\x6a21f8ceb67ae709c63793a491d34065f64d17e9347e439f3792d852ac51f6cb78b960fc196264c797d0a6e2d285dcff447604fecbf1b1a40defbcc27a4dc22a	\\x00800003ce21baa946eb419c1878ce1733d1070fcfba5792ae2046a9219397798195621bed42f871e960bfb70aa3f4e7f7b0456c57e514dd27312e513fcb3167a8fee2cfb07ecfa81bc9c767cd2c1c2054f2601b408a5af75d8daa564f479b1224ad4e594a8e6cb4d1755707ba7da5ce2dbf72a2b6005dfea4c6b5c5443bba8eec778efd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x766cd89534ad43a6a5a3c78256649c3dcb480497d42f7a1764dd8f98beba062795625043d7d2c31604d8150f1dc41c46cd0ce516611dcba33bd7bb83d37c230b	1636953050000000	1637557850000000	1700629850000000	1795237850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	159
\\x6c396be89c04c2f50b5d5d167e17b38022112026d968158e32e942ca0ff1d703510319cb7e6323ca5e175f247b9a6329faf914aa6dfb702e65844e6ea1cd17e5	\\x00800003b77d6b0c00a89a06bb3fdc7985800d2af5903632a488b7d1728611a57d735992efaab5c1f51bbcf50935a13c463dbb46d7f2829bd7cdc10c15e10fd3fd16d6d33082612d0e08b6e26b3438cd6e798afa10270e2113d4c586275dec65dc9a69f7437415e3c69d945e74d702caef0a14af23d855c0fb2c0930096a27cc131d4e39010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb582867df6f4b9f6806e690e7d3e7ca891c9c4136f5c1eadbb43f3a5a6e7605bcb622dfb17c9e3562622a14a05897374a799025d0dba22bb640df233f008570e	1626072050000000	1626676850000000	1689748850000000	1784356850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	160
\\x710d504487743bbc676f5b56102ee515c118dfb0b7e9617bd5d07bb2480753da9bbff6c4549e1e740b12de677c2c372c38cfeb94dcb8326859a2f2aba85da931	\\x00800003c5cfb0b0eeb3708559476e8f4503aae5d02b872d0356e5d1fcab6d5b31838b3e56cdad5dcea130492785e4c1fbc7bd822116e320ca16dc043014e42aec6903a99fa58f8f0c4208f0656c410967f392129188c9ef9c19ffa36aaef1bc2c09db9efd72ab3bf58a04f5980d0a28441b0312bbc25611948350dd01fc8751b83db375010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd5a895e9da54f85d627c606448bdae60ba2a3335185a6c1056140df72f78e04f08ef2f6ee684f738a3e9532c84c482f4a130a9652a0032216a219cc20fa14207	1626072050000000	1626676850000000	1689748850000000	1784356850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	161
\\x726551fb33190362eefcac1dc7aa5b9260064c71deb0b9e1a408192c9f684c4659c9c4297fe873f3075ce3acd26e734f7ee97c27df1a735f5cd8623237062f4a	\\x00800003ce1bcf192df97c18fb2fc1cd2afecbd1a00d9a7f81720ddfc1f0e271fec28037722024fd3d3dfbfe961adbb339c20b71ea66c529aa752fcdbec5baf64eccf300d0c57c7cacfae5f04b052071115dda26f4e0b1a135a279ba0f02d3ad49585c7b9437c435d7a5b65026891b41feee9ba11538948bd29767f66bf589b2033db2b3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x76e38111e5966f93447a9645f69c43968b6dc2e4fc23529e4b70563223555d926774d101abdc838c25ba261ef64dd41ed319b8919db747cc14778182f742cb04	1630908050000000	1631512850000000	1694584850000000	1789192850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	162
\\x746d56fe229a0a4aa0de8bd013e2b9e6039707ff9cdada70fd91b7abaa56651ff682e81ecfd3490750ef1145fccc683ff9645c3d97a81fde851b9baecc30a5a1	\\x00800003c58dda94c4eb65fb8faf8114eb2c72e46fda7fa574a48ec8ef808464654483006bad903c7949b4ed11601c8b1f195d94ea1ee64538446648ad8ab30deab6d4f684babcb64fdde523051640ab26f429a719d2949051ba0a318b375fc8303396023c6c77bc558741b3a35ecc033cbe217d1beace6d86fa6abdb67591c2ec8b470d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x259619144c4d265e94c1b18f4f1816e71a0d28e5624cfe37fdcbaf892e3844aec2bd166dc1786045827db84620a49e926846240f61e2ecf0a64c6d244558f804	1619422550000000	1620027350000000	1683099350000000	1777707350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	163
\\x750d2cc305db792910ed8a8679830837a2c1b3af0d05e4b76d47d8834c6d20632fe2367170bfbdb7d1c7a979f972d45ac4c8152d1b88c4c2384e7c81bed75d02	\\x00800003d2b1a0aa69aa8a20c1d868706178c6c9760ae277a13aa0ec88ddce489b0dce781a674c550a66a0a2cc151031e7acea5c5f8b8289f2e3b1aaa922b3954b29eb3e32de0a2678f0eb7550f049de6a87806ac2c489ec9120ea248da9e5bb75ab0b706bcfda641f184cd3bd6ca7c8f0c225184292a020f1375c3af349a3444f150289010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x40213fbd469c9d1283b062805b17b4c13004b76c04da0f0a789dfa62cecedbedb0a92378c74897312582ec42313c5ca639fae15f7dc66a83d5261b066fa05503	1620027050000000	1620631850000000	1683703850000000	1778311850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	164
\\x75a10e7861d8573cca9ccb9561c3972023cb9bc6a7c18deec21a62de84f1a45638beccecc990c21ebdb368a97101cac22943dfb10109c7361fc40c59611de6d8	\\x00800003b7e1d208f6ec419b4eefa9158b378670b36fe109a1cc20f0dc186d9f0a8fabafc018285646acfed04d6c9fe1a79cdab40c01f5a74c7f961db4da8df73e11d5e322c54c8fbca4362b03bc2f7b69f38bbd70b817526cea156ef45f8da592d5715b27d84e67756afcd47be3ea13fe5080c0c2a67962c536d2ebb2b7636d96d4575b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa30c86004859ecb059d9d4400ff1e7496926fc87ea41ca3ff963ea3910086221d90b055e17fadee6e796d0e90351db7f0825ca41bdde4d7d55a164f4bbbf0f07	1610355050000000	1610959850000000	1674031850000000	1768639850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	165
\\x77599e78f7f20a5ed4e867c1ad9e7a48ce99dfd7ffdecdd39d7b5387f6d8f4f010d022f5230493d5d9efbbf077319d6f079a4720a038aa27da32a235a90612fc	\\x00800003a1ee877294d4800e7dd20f115e5eea4e0dde39d35038cf929f38be298ea886a37e6ca900c385aef685abb19b0a5b0982cc535adba7febabf33fc06f47bf78f9dddd43463faa15a739328f57fbced0cabe8baae0bc63d125427c4fc89211296354be49e4331ffaa57ff40499abb8af01448b40b2ccec431913134499432e6ba75010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0baf0e538a63c7acbf0e7a29be8f86eea0d282bdc9e8227b190856c2abfb3db3851a8b59d8325b5d6a102f50f7dbcc0c761d9c66af3991e203a2ae6fe482ef0b	1636348550000000	1636953350000000	1700025350000000	1794633350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	166
\\x861d83fef2401334453fd195f06518d9bf3acae1ac7c3b3e4a9a5469cc56f0882fac2db460782893a4f10695be70bacd69b6caf92b4be0897291814695248e77	\\x00800003c95895479f1340cd63ccf0ccfa977726d8d2c0d72c776941b5679d7da3bf7cb85ddf3afe9025293fe9ca2c95fb73e68353f98d9b31aa33ba87accaf48eaa365bfdf39f2816884b14a0d27f9b3fb2b65e43eb4a7b45c68ec0e1a8abbdc772cac8ba165e2b2dbf83715fe95bd42af4d4c6638b930e632d9f3cee7796234bc35095010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x01dbe41477176ab12282d55862fad45d4407f793e3df4234f6067f9a3984fb7b4a5a9c8b8d4a708dcb7142fd279228fa108dc69484ec82e0dc6671c7794c9f07	1613377550000000	1613982350000000	1677054350000000	1771662350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	167
\\x8719b76475b933682ddf3e8e6102b705d77b095ecd0a1a25977a373baf004d74565bc6024f74286daab96f91d02edb6692085a65708e77be3d491837d11a2a1c	\\x00800003d2d78d7493ce48737e0f73972ed83236136f69b3757058c693d4a232d8f98d2c4fd7ebbd6d6cd09776ba70707dbfe95be978de5880b8fe06e864067f9f27160e8099314adec5a8d0c06ca2934cc8be4e76edf42cfb5f1d285d21e6678123d0a7b3448ddf588c80d1c6af687684557aa1d4d44875ff2144940bfdb39e06da739d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5afbb55f43b1a41acd362921707495b9edd80f25bbc502ed8e51aedc19a946fba6e8a1519c8fe795fb92cbcaa33c4cf29426890d5563a99713920d8f7642ff08	1628490050000000	1629094850000000	1692166850000000	1786774850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	168
\\x88754c524322a73430870019af373001479cfa4d60c013c4b5c93ac2ab96c61db4d7f9a9d5456683135fcaf8074e3c3483da5b53d5e38000ec3e03e3e521d7e9	\\x00800003b3efe9333e82a9bec4a90967d925b5a628938c112dd192e8dea7e42db69e137437f6b13dfafbad4e0f997e2085bc2235529c36471fc89bf40d7bce6cd7394dff9a0e402cf594315d693f6aa9487ae456867f9db5529785e7980078410ede63cf51d2b85829a369d32066ff919b177b39914e1b0f6ae6e06c698533b80c6a8c0b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf68f5eb24ea91b2c6506e6c30edd5b67794c40484a904a9f3c245163b3ab1928c3af9e8b72e9f7dbe5c9894da8508956a20564607569421231b74e5910234d09	1615795550000000	1616400350000000	1679472350000000	1774080350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	169
\\x8acd69c35993f35599488e17950ceda3a49cdd827d7aa88bb9d0cda6168550e72d469f099ee6cf132e80e165e1f749cde8da2107141aa0c4d83f17525a65533d	\\x00800003a7b56074e34f2822d5ebd77fbbbab9b3987bbf6979d14d797c27cfb9452315ae7db3b8dc5f18289491b093741a33b9722d4b74fdc4b18702f24bdc4281c737c9e8c5988cf0a5d0991f800cd268c7ed56825f14f6c89a53a97765fbc233ab58499b637c77cbe6f55992b96fd370470f6376164c509648ece76f25f26c4f9ddd61010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x897dfe3c42f09ed4f409bb4a420feba1fc006c9782068b1f06146c5ea51bc0d0b2a291693a8945a878b244dbc9632eb0115ccfa3843012a531a5f64ec386db01	1633326050000000	1633930850000000	1697002850000000	1791610850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	170
\\x8e999672158938ce19a328ee3d851ec835105d097c53ca2f00edf006692fd97c732fb29770df92373cbfd4c179c695d4479a8e58a3db3cc4af37ac1bef2d39a5	\\x00800003a835007e5ffbf246fb54bf8c58b2059ff6affb655e06736de56045d45baa80cee144d8e6840bfb14d73357a41955d813408e927f3e288a530f60caedb67701a7e861a3cc6d922f171973fe2aec44ffe7ea995af7bdf5662850038b00ee70ab5d3e07c7e49aa0ecbf392624775b29fb483071b945eb8c40d8c3a1c768df659651010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x405fd0a6e9d6cf0f4dfc22336037c82544c5a3d234248c53ef0cd646047ee84a9ec99141a2e748ade808856f304a62fb849b0966fe5b58baed06e91a4a2c360d	1639975550000000	1640580350000000	1703652350000000	1798260350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	171
\\x8e7de7f6ad4839012511abde511212b5a3d02cf6f443dc4564dbd49db478afc52658b1e45f57c280ff277152a5dd41db42b4dfba179d75c3e633e686f4463490	\\x00800003b9aa1f10230c36e280c47e6402fbf293938c4408b13b0dbf2f7f3eed6329604a340c8885ccf98efcdfa802de296b797ffb98e7423fc1bad09d77d6b7726894016dc04f259a8076710ca07f1515ae67c27e544b0d027637940a93587f7700a3396860aa4e4ac33493d4f82dfc83656592e4efde0a407eb1d604521725dca816a1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa20f07e0f4bbba77f0040774dd1a42d6ffffa0e6fa6739c64990f64187672268c3be02b27cc9c0e647f0ab055a406762c42ef91d21961f2187b5f50456ae4a03	1623654050000000	1624258850000000	1687330850000000	1781938850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	172
\\x989548cfc6f732088aa27c29bce5b5f7d7b8fc8922ee6966453c5d3cf79247b38b515de52c3565b313f3960cc59312380efbe8e22a510e0087165e3ec1220f93	\\x00800003cbd8a40e836c1ed05c9da57292dd2b10e567a2b1e734d3bd7f802bcfc5f5f9c94ae2a727ccff1a0330ddb636f0a4de8a4629942bddcb12d6955d41f1c86622412ec011770cd2664c06c26aac77741225f3a5564785d0e97b60b23afee1bb6a034676a461844200d04ae2bc86d40f9a3a992ff52bbafd7e5af4d7b73599520985010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe10379431c12342be8a388c3c8c8c1eadc8202c587c151310bf665319616559bdcc064c6728b71834f64ebc335f151d4e1e370b5510b9e6ff309449d3953880f	1624863050000000	1625467850000000	1688539850000000	1783147850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	173
\\x99855f977659c6c23878d718d4a7853ecbc4a708955cd8e61017fe1958792bcb39f3b43282437b8b1132839a424c30ebb3c2d98a3729472dc558d8362ad2b989	\\x00800003e661fa72208c45fa36f0763c7e606d7904e5b0a125784367ed15da6eaa90cc90dc5aa3f5ca65f253ac1c339d617e29b8398d362865324bac3d0b348fd791777be496c5ad1623988a33d3457b931520b42b050721207252f9ec548281724e41d10412bd411c544b191b93d6af8ae598de511db47f3a441ce07fede6978efa7e2f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2c34a488a689bdfc5afe83f848f66ebc50ecb7f6220bd2c343d80a210678a17a9b069e68cecce9e209f0079320917e944ca0ecb6b0b3ee2f0f9f9b413123850e	1610355050000000	1610959850000000	1674031850000000	1768639850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	174
\\x9a8dbbe879eddbec83003baf371d260adaaafabb1395760d762c783da9de540a32a2c12248eb1eb36d9cc2c8a294492a753ba7378767afe911317f847069af56	\\x00800003e6298718189da288bae1721ddd91e913dd310834fc6841f188f94b985ba41987afb62de8b0422c3bc3e0aa7cd5d45d26056de53974745da0bfb7b065467d41d0d545b61836b6cccd17d7ce93c67de96b4aaaa9bc75b508a5cb19db717b41b7de7f396955f52174537e6d5dd0cd5e237a57428469ecff0da74d81f9d3d35b3445010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x94e9728389edd8a515fda6fc142549c1398257e6f1f37bd4ab87afd0fcef94839983a1a6a24a55e2569ca464488a2bf7dfa0aaf5f82317db552defd73e70820e	1641184550000000	1641789350000000	1704861350000000	1799469350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	175
\\xa0b1a1aaaa32b0ad168adb4e3550455a4639765a372d203d3c220424caea108d4baeb5fe8f9beda396811db5f596f204065287847780a158a882a01863851781	\\x00800003d5fdd94becefec88a7636998d73a2e8955283b93a10bfcbf8989067b2c1c95fdbafbbd9c09299f0271b9bee3a30e073822405a71cf1bd1930032166989cd49f196b0a47b853d18dcfc0728ea42ffa64f62d1586ab720367ae3f35c8e8abd514656c2ba1d83bbce332e81b162d0be5a0e3042ff8fa601bc9aa878e45670219b2b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1b346c7111cb9ffbc0a51b92e54ee5cbd4c8161875c2ca190431d0eba7dffa89e628269c0b2b8c656395ebc6690b88094b113ed21a836ceabc48f9bf8f174309	1613377550000000	1613982350000000	1677054350000000	1771662350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	176
\\xa3450ef8ee58f162127624867ed6275a09466411ce47e4f7917fc6eb008d6245125be746c4199121bbd6307af2948a99c2e7983a7ceb03630f54ba956f7617c6	\\x00800003a8345d66ad54509989d6734731f66dcd1a7ca5460e4e6811eddadc58ad73218c9f713c15fa70d1ec13d674b37ce9e7e2f0147c5d6ce2e588700f870c261b04b5d07d9ad9ff3d897a72f59da0cb447c49ff94f0290db3e32fadb053c8bcfa7482138ed1f34522f085b5a4abc4739f2b476bd782a2ad2edf8c2bb840c2d80bb67d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf9e81cdd150f2da5923904690e3ec38b40f4d2bae71131f175a9b9d8d8cd89c1971a5f0bfc28e4981ca5f573f26a81cfcd052ac4a59241bcb4dac76ab49a930b	1636348550000000	1636953350000000	1700025350000000	1794633350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	177
\\xa591ec10ed942a7f85e80d8ae506865ee87d4e39eb541e1c24436c2e0496baf7565ec165cc482809b8422f4c2aa1c2cdca979b2e84db5d9728135e695f61fee3	\\x00800003cdf116c92779d1b3818a05481cde8d35ef6bf0a39cc0a1ca3be62e28201913b5a350def77a144512f93b16107b25caf2b9d66832c4d6236572aae7c3a51fca5fe0a72aa2ce3587be7c6b9d05cb8d57be8c15853089bda601e9656abc68ce85d67585d8d30e355df907869b444d025d721e7c99fbdf71d0693a229b443c251a37010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x146d9a2f79b7dcc00b1a21a70870deb3d5aacd49d1b2941eadefbdcb44648542055ee310861cf89d07581f1e3aee8127d14a6dfdb08c6ff119168a18141ddb0c	1622445050000000	1623049850000000	1686121850000000	1780729850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	178
\\xa6890bdf42de1085aa341658dd9e3099c31c5f06ec588e54cea6f55661d210408a72e602cd0e8265f280851b0d5e2a46741d341ae9ef82d5c74597aea6f4879e	\\x00800003d39b29c14c5ef71716b5af1488ddb91038053bdbf1f45f23be21452e5bb19d6108a4e060f48301f1c2ad79f3573ff7168a2e1fad7c21574bef968e8fecdc4b5886a6320637b160d2de9f36d3ed51851d73da3e6dc1667f1468e715d534605220d55d46a9469fb5ae449c93e2ebaffb44adcff309690f7ec86f38a1b9b4258523010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa27eb31a1c3f3af1c53e35072600649416d2ac9a998036bf98600a62bcb95c44fdf3975d608ffbbfe1f3b07dab06b91bb95f8c2f2a8d64430129331f97e4580b	1632721550000000	1633326350000000	1696398350000000	1791006350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	179
\\xa93903a466ae5ba6f104e370666ca5eb302d2d5ce70aa691e2bd6f3f1dee40931e9806f1e10adb8da187924bcfff5e7e0e2f7a4df5256ef6eecf8646cf4d4896	\\x008000039fef11f2f8c32e7aaf1406545c556de33f3924ada06c7d82eaf4014c2aa70b9b36570fff0d938f8c9bd46e95d34268d36d1fedc65413dc8759e053f98e34e8e0583d27b96fd1decdbe594cf7f7fd82cefb20462509e2edc6daf04824b3cad969bb6f58a7fa6a84544657a1d277224f5277921c4086174be97c426745d4d127bb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x96bdefcc6914a57ca5fd1a4be3de681e67d25d44f9181d2fc109395206bc49bb5428bce39f686cc27cf64986cda1bd5f5588a727d2cc91dbb14c320098ac220b	1613982050000000	1614586850000000	1677658850000000	1772266850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	180
\\xacd1713b7af40321ac9bc3c378c7e7a80869617153f2b53072d5bb4c7c471630c650033df8238e81c21850f5a34b7a23f836ef30c7ed40df425d4b2fb2fb2583	\\x00800003c93154b9becf6bce59332e62f8f49df845db784474febff524034a52fb2e524ba86f497a6d42a3f7444fad5e4033690bf6f8a168da214888f334aab631f48199d3aeb72a1289caa76cd7c269e95764727fb1589632490ab19d59147201cd58ccfed848b1f91cf828bcc00757e328523e59cdc7ee053f2d43f9391801391a27bf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8775f8d66a71114d240a572e1f3cfa2b4d07d3e844268d7a13fe0b4a419cad5b9b6f57831eaec36e4d4d6488eeba5c01e33afea9771ed7b5757f0bc3a52c2808	1617609050000000	1618213850000000	1681285850000000	1775893850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	181
\\xb2ed7fa7c9fb0e06e07548a82cf196673db2dbe158b8d88c04f5e85bed32bb125b7bb3addf344d7fd3065a89fddecaf24795c21a84d1e1905f33a2a2bbc90cf7	\\x00800003b79114fb7434ca454fcd8f2414286a94499c7c2434a5d400157397c0140840fda4571cac3ff3604888535e791dd69f7c18b274f0685eef4bd160698c19753aebfcfc32fdb384c72b266cf1408edbd02fa078f0e21536a41e3e17a35d4760822d86daabca98ececd0d8f217d21dad951d1626cf3b74229f2b760037b70c84275b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x32b45eed397a100dc1b4d620e94aba6bd5488ea098cfb51f16b1ca8fb0fbc1115c6495addd12783c4c8c360f41927d2aa25fc201c401e8fcdcce6d8f984c8c02	1621840550000000	1622445350000000	1685517350000000	1780125350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	182
\\xb3851267c694a201848aa7abc71b2710d6c0a61865a58acaccb680fa8d55dc2c1cb1cd6f657c314f497aa79b2b6a4c9f17c977bccfbe2f3998572aa8339cbca9	\\x00800003a53e8d533369f3c7fe483dbfcd5a954c50918073fb29aaf45d5282552f71d64f6d7064df44b50281b19bd4cfe23a4df836bad1bf87a7632e9d36fad9bc35cf1cd47ae300671d45b3ee9985613563beb6263e639a3095d2ca5acf0053e20527cc869f96d32c1203a9935d968d98cb6927c8fed57a7a2ecfd49a4a8c2a49d05e81010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x539c18aaa7be907f371ce76fcdc3117a31a1c6f2845158afc2b2b831753870e982efebdf38553cbbff6b0f281d735eafc67945787afb1c6518521ac03a687d09	1641184550000000	1641789350000000	1704861350000000	1799469350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	183
\\xb9f9d417ff04512c448c2469bef84c9563521a457a07cf178e4da8749af4f5772f1863ae471a423271d08c51f30b75b80803743705ac476de36993344d3b39f8	\\x00800003c2615fc228dcc084f25bb131decdb86c889cd1ab43b69660e38e58805d67d5086c7be6dc8f223841f57da4b8016a185ef3f895ab8741b682a61d3710a0da43e67e28b5f424b76fce58c55ddec205732bc9db69fb34fb5b8cfc455c4c18366e644a2333f7c6cda46335b7029f753ce824d9988ffa5e1d48f5690cd91fcd365aa5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2f7d2f229d6a991a1111405f67f6529215326f03ea9b0f1b3e57a4416d6448acbbb3fe4ae9f3488b6e6102144546305a848a7dd8c885467e13bb7cdb69409a0f	1623049550000000	1623654350000000	1686726350000000	1781334350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	184
\\xbb89825c84d7a97a5480b1664bcc8d3148a1911cbcc79b19ff992351653c38910ff4fcc4e8a35ca413d7270a6734b82109b0a5a4dbbd20d4b382215fe7f686ed	\\x00800003bc3e025ee647ca8e50d97f81fca8666b790538244b3c3beaa06d3c1feebd606526f45ee41127aa943361c3c4ad20f4d32c960f54db3a5f01145bee0ddeaa18f6b34af6468636609d24efd09780e31b10c7b506db0c4008734400a846b7ec640526e521c82ec1ef8eb984b83a9ad6d124712f4a39dd95630b85f6c1d2db615b79010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x873e5f74c2e851f3a26c7123f248f628d7d019d04254226ba51c88f7bbc12ebfd26a4b22e321ecaa74c349dd14a19ca16dc82c360c70d48860782b074cc69401	1619422550000000	1620027350000000	1683099350000000	1777707350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	185
\\xc2cd34549d724a960655a4f3d65093f448dd4a85d81d0156f39fd18dcba758897c35db6c1d2aefed70d72f05ef669b9d2e120fda81d150c1b629964e79f112e5	\\x00800003a8a767b272947afafbe1bd99a3f5a317120a7b1ff2d67ff6472656f7b267a8dfd72188cc62f473ad0ed13a847c0da4a0230172bee269f719c825be853ef9769adf9533768e8ae5626b96da05213ec33d9baa18f640c244ff0a87994bd2365da0a6dbd2b8953661af95b920b70b676982ebb78d1216d75524100c5ac049515e2f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfbbea405f25d644e21ec27c4ab141b3c019aa907fee6d1793028b85a4b9604d9e0597f1056b84228586fc47142db108669b2040652e54783444e7eb35db2f009	1615795550000000	1616400350000000	1679472350000000	1774080350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	186
\\xc69d3da6edcc688e9a23e4b5a89f47ffbcc5fc67e3fec10988822868f3288a66ee77542084066f5121004a0f8d4996f40460f52388e47d8e0d298a677d7902d0	\\x00800003d75c16c0ee7fa4d40ef996af77d4e0c05113baa7bb16356ccfc0cad208102942a83454b507b66ccce5ef07135637c84badac4d226711072981e267d8a70aa0ad62f6d3b555a12a689a74361ca758d04fa89f2f4afa9d465f5db016115a340c9a6728098cae61e3deccf077bffb3ce7a157e5a17c9c53f70b8859468b6ee73799010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x64ef6d694901e05b801b0cb43469b6a916a51620269cdb3751848c947846029be83d4bfcb4da8d51cfa52f626333e861edc0ee8fb5cb4aedce544133b415850f	1613982050000000	1614586850000000	1677658850000000	1772266850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	187
\\xc7955d21a8a2d1b8a64a6ca08e894a709b054326fdbf19b91c7b9622ac1770ac9b36ff761929597578748413683866f07b56d1e41e44fa4e35f9036300bad4af	\\x00800003b51772a8cffb4400027c01ba41a20661628849291fb1f3e17f0b85f769e8e70b7a78924f3359aa2a207c4845bfbbaaa7a8ab2f7e99d54b13299fef3fa2582e3d62f84324c73d98cc4b730c0c38f461ff765da90b32d75c4a64fef5524160c48609c857f8a72de0c6c61d0d8299f13ef4cbf0877a9da544a01c399b1807ce679d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4cc1305320ecda5d5cad10742aa12274459919a01008ec4429b2a2d9574f3e284a8deaa5a23285976be1187d634ee927f8ba9e186f92a7be6048f5843baeb104	1610959550000000	1611564350000000	1674636350000000	1769244350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	188
\\xcad1b697274d72399d370934ea84aaabf5b15b645226e1fb75ad6ca352856f5f6aaed314e1fcb6eebaea16280a4054bac982c881e4f3c6bfd0dd2d340e9fd8f0	\\x00800003990cc0e5ec9ddac66c6d5816fa1ef0a2cdcc031b9c012d269c0cb1983330ce3ede7bdfdd8439a23139b94b560ab3cae1159db6305d7d0ca78f02a6409719541ac90c4d5510fb84aa3cd7fc579f6a222f47c45a3669d61d99902c38317e1fd262ca9366f2b15a9c10ce737f8237a2ec938a04ddc3c1ffc31fcd52dd1e4751136f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xad928cce5b9285b2f9790564fce98b6695e4175258ca5ca51f144d3d53aa55d0be5a3ce7f771fa4b9537d7006b1f60ae4400860daa3242959f5cf35105c7a801	1636953050000000	1637557850000000	1700629850000000	1795237850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	189
\\xcf4d0360986bd7181a0055dbfd516099c0e087dac6a32e4ebb716334d8fb315e71e757b9407d0ee633daf15fd4c6ac9023b1417ddc82bd1fe4cea4eadc1931b4	\\x00800003ecf2a9cfcc2aa7f009f5e00408c3df6aaa0c25ff8605a890d91a05301c61c651f54a3a4cbf3b175df0406eb13a8ddbe51b57b749d3ce3faab6472ae5aed3cbd93364fce798f496d0ac5d9772ee9539899f5a8e99214e8389e8a1cdc960d6a08fb2ee7f25d815783d31c49fd04ed3a4a44c9825c983ff2995915b5fae2c3a614f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd7389236d0c9f775151665ecfea8d76412cc926efa5c57ab3afc299f83bc45e371ad944c9c0dcadaff227ca1ac1b98d6bd8cc9030b3e2c6871c8abd8bccf4d0d	1617004550000000	1617609350000000	1680681350000000	1775289350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	190
\\xd01938a9d299393597197633c7c2fe0c3fa595491fdb8723cb4b3c925b1f4910b3b7ba980d39531e2719d9c16bd1cc43105dd1ec79c6b01499e5e7dc763d8242	\\x00800003c5423a0259bc7a7ff2549f3cd60449ff0cef89731821cc6c09717a9b7365a6cd6f984381dcc21a2ded44d0c0841dfe3753fe07eaff37de64270748a55461ba8ed4c27d42bfe837c3d7a7656a7b84f0e35d54bcc8216af0ed2da11236aedb98a4589d516abaf0d0e14c2694158a5ef4b992c26538ead64e1b5620939f821d2c81010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x040935b2a0aae1b343d8826440193ef1f74ab225781334c9e01e3d60748463ee34620b66abb11c032166e9c9cf72c06cd9beddbc37c11d3199882e24a44cfd04	1622445050000000	1623049850000000	1686121850000000	1780729850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	191
\\xd23dcd9a67a60ca45492bb782afddc1e6c520b0c5a2ff4bf62d8b5508fe12ef594a9c9aab37bc49a23cab53c9b329f47c1fb2f84e83abf4a5fd18d4add4cc199	\\x00800003c353b642f8fd254460e0f47b99185eb877d090ac887da4538325e862060f2a63beec62eb245332f016ef5bf2b64c15a74c2eb9b390826c9a8f2f9c7ea3097a559b91506f03c40457bd87f9a2a950a6623429ac97237759f3a8542250e8ca9a1eed51b941b6f55e2ac4c8f8d7fb924bc8f7615805b47dcbe710891cd83ec99aa1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6497253f048bb302b0e89178f81df2fc26963c53a56b1e01eb05a8c1a5f5118ae5abb6ea2c82163c11dc592475972f25ea50f16c1f5bfc073c69b93a50d9bf0e	1627885550000000	1628490350000000	1691562350000000	1786170350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	192
\\xd261a58070332616f5e34a0a9b849b902f927d15cf1c48dba7b1181756f2ee00f990149a8b030463417e1062dc5cafca84463fe41e79b6ed764f505d0eb351b8	\\x00800003e35f103588c2ec0d21d14436105cf55887c8c663c23f2740c28f3202e5e99a34d88b2e444025aafd5a5eacfeab7ac6994a7a6b05349773639e941dce1016e1681e922f20b38fea1c30fb4c3be9dc6cd6e4967011478fd3182a9f42d899190ca5a708114fbe9db6366dcf71106fcf22001fbebb693a24fe4433b7b1486c689fab010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa132431c9cd629f4da7dc350eac2ab5ecab9b70d47897f69bbb283c1c3987bf3ef7b708a10787579fff3f733b8115877207a251aaaa168278de434ab6426b804	1610355050000000	1610959850000000	1674031850000000	1768639850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	193
\\xd749e13712db1f8f4814a22accf32938b422cf60cbcdde743b01d0279850e45e5ae65c2577b90a0699be417759f0674ccb21b1398754995ff630191d9f0dc365	\\x00800003c7fa477016334e341e32cd73d2fc4a5568a9a88f8d842eeb8d36154d9cea09ee84f824de32aec750f5a74ee94dd193849bcb4f475e00afe09847b66ca5f63d068707fec87b42286b15cb2d98a455770f1b7f3841ac8103cbd79f2d0d748c68e96befdb0055eedb6f0a6ef20ef214bb9e88260960b07a2dde12e5a35cce1c09d1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x02a60d4043957e7f538f06ab79e87d5b32ee68fde9c7f4e07d787af1fc82aac34eeaf66831d5f764e078119d0895a129d4e78b143518bea17340d697d8367b09	1618818050000000	1619422850000000	1682494850000000	1777102850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	194
\\xdaa56eb4bad8590d6a833fadcdb00ae3f8e239b3e1e7ec806f60cd22ee242f88f8ff44d9746393b98714267979aa46a81c5d29b80320f22a5301d4caf283b17f	\\x00800003bcf15260f07b005e18307462fd1c0fad51ea3db7f489361fae512f28ce396bacb4b71c7343593d3d4bbde6563605275ad7b99c521f8d66af82e8544a88b857fba01e47e2049797e16c8a29d3c1fab9921de3d9237039e001ac706fe134df49265276fe441b54091d3d2749ab9036835e90a55f852265c440e91d0ee6bb87c4a7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3f86bba84e49036a6bef848e996fa68fafba028282547a26f3e4b1741c01fd2b8b7c5cc5c43fbbb560f49db4ad0e2018d0d00dd4a48fc3b3e37af60f8f3b5407	1617609050000000	1618213850000000	1681285850000000	1775893850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	195
\\xde11df6dacb5e2e570d290aa04c3efd47e7b7aa2728996cf73e541601b24bbbe3f07860bb7f0cecac56428d0628b81ee8577e2702d78ab528504d8b21dd76486	\\x00800003e79bba24686a82855be2c20f18ceedb12e037016861dfcfd731c77d9e51b3c76e246255aaaa1a15a3165c330215d1d682c5eb16824405d755ca654ced85fb9e08486f916b6ece405d71ea7407051c085e9fd7b35729d38ca277bc538bf1f54e32f3f5f98f7d61f1a75e73908d4ca991e0159b905403ae1cedc22f6c341cf8675010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc603a8242bc327af82aea3d713f05d4a04750303ba83a274b6fb8ba512acccd816c64a7b02dea7567b632fc45be67ebd988c15583363d017d9c95fbbc83a0f0d	1629699050000000	1630303850000000	1693375850000000	1787983850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	196
\\xe57d05ea2b520a170d89dcff36d97c31dfad333bb3cf3d24f79fe417b1651818823c7ebb05fbfdcade95207f8debb992de1d363b5846dce1743034ecd5627e19	\\x00800003b1b5184625771d0fc5baa47761500f9c4bfd85b52f15c701a1dfdb1fcd21c94f6cb5e6188e02512af8e5e225197ba622b3b3aef7288811c701a5af959f71ee0ed249e55f131f457ea00bdccb08bbef422a93567508814a599693350a5ae4becf373b490482ff437f8e7c06d7b96e4f274f8777bc99565ab12593e9880b4c94cd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1f9b815733da3421124560544bc16aa18395ff7cff15da11b06f67d083ec2d035d397a1f5ed432e2173fe63583e047f63a510fecf421db5987119ce7e806940d	1640580050000000	1641184850000000	1704256850000000	1798864850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	197
\\xe6410a2d82bec8a79d31005479fca76f3354715964e3bf14cbfe7295c10aa0808bb556c0f711aefdcc88ce9bb6eaab97403e174c802e94a4f6e3fc76ba847d48	\\x00800003c2b2b47c410f8efc6b094a7cc2d224746e393f0dc532735fe9fb3707df4f9d6705088409e261ba1f5d3d9e208eebab5b5839d28af5a6d052b02b80bb2deb46602eafbd9d69135d13173cab3bef5428b93abdcb1e03e21e5a47fa34b737085378d3ce34fb3497f7476726b9093191a84d892da219db90ce8d5ca18358d099d0b9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x104f57f4c0ec1f50a18240b1646a0cc1e5a4809d9541fde829a4e5cde5b1102f4c51460946f665984e743ac3e58944538757dce418daebfd425cb1ddd2f2ab0c	1632117050000000	1632721850000000	1695793850000000	1790401850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	198
\\xe781b87812c59731224c8f47a34cf16cc2f0f9509383b8f97ddd772e3cbf4f7a345baea195eed474cb848555a57b8cb47d654e430b62183789bd4e8988ec2e20	\\x00800003c2af1dab92dddba89138bc7e38ebf6d1150036b1c06516990e72c430e1ece72e8525a8deb172221a19d0fa761828941854cf5f0f6af756fc1a7e2cf046e3232fb644fe9bb13a758e4f2af612215ec11372215d42cf748b1a00a1eb982ec3c89cb3fa566a11c5b9dc67cf671a0d1addd68f0a2b9850a2d9cb8a2b7832661481e3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x82c090868ab0cd752ef7712a3c02a41b5e994bdb71cf4b929e67df926fe59a88c6ab8d62bbdf4d35e3ffb58e2505896403f70358c12f752a4adfc56d30fd5e03	1613982050000000	1614586850000000	1677658850000000	1772266850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	199
\\xe9fd578ea58a696a1e67a383472ba2019b945946a38a4b68952933b0db53c895654280bbc272d0972474b48cf45ef8fa7ac7db1fdae81f293fc02b3c8d95c70f	\\x00800003dbb1e538f7503e65d5adda6462cbda99b0016afc7f6e08b07f2307b9d33e7950649ab02f9af1357dc7eaf6c2d652195e5faba61994c22e226541c5bb9361aa03fe011d8f3b096f9437094ae34e33f52a8725e0eb50ec97afb4a8454d7955d23d6b193ed66bb97f2743f7aff5b1f37389a9c2b03e05c2d65507f6e1b3dfb510ef010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb04be324a7cf523abbbd08c39238a21184bdbb4186ef65725506523365c1b8f656f78f6dce63675a9d4d1417c67e2cb1520a5a25383bca1436adc20bba4cc506	1625467550000000	1626072350000000	1689144350000000	1783752350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	200
\\xeaf1b1771389a5659fb2cdcfce64b05024dccc35c800e8f18f8881ba16bb76c858cd11eb5304a70772a9ef6706ca04d4d5fa17edbec2c4c095b1514e49888e9a	\\x00800003bf220ae6c29e9ed10be443d47c6bf1b816ac6a25113c2eb8458697dbf44f3c351bac940d1e87168b684a3c6ace0c3ddf5c2075f391e3f7e56b2a7bcd1bc43ee1e07d1bcf71936ae3834cccceacb90ef429b3b4e54371f7b1720d0eb49adb9b1be439c1ef175b37976b50e67316cb6ec8b45cd138baff3c70c4df6f06633118dd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x588d78f96e23f8eefff6afa2ab8638a23aaeb463bd56d64bd5fff037da3223d017ec3fe252209a95db664063dff44b280130cbb5d19c0b6ea1894febf34b7407	1624863050000000	1625467850000000	1688539850000000	1783147850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	201
\\xec81a5832e62251e2523373392894aba5fa590c584fe9885d3690207f786b95ec87751682494fccb4178e17e589468fefdd99d1bd84cb777d3d82bbd5c635448	\\x00800003be8ceabba0a9ff9ae087c596821e933f8ba2d7d61b730e40d03c4c8c16efdc81cb5729fe67d7318a520fe8076811959ee4e970234aa01d5e4a28984ba262f2046f41609a7e421e9ed0910a760b7c321d2518d2a2d9184051a58edb781fb9135d9aa81933644195035c69b1f9cb91f421c5f29ca466f5d6cdd4fa2ef902035c21010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x77cba7f9b670fa1e24c7c86b61ffc25c066948143d6bb61128deffe104de3564555e8dbde9c69b65b1d1cf5f16c27283976bd4d39519cb9648f6686c0f31be03	1621236050000000	1621840850000000	1684912850000000	1779520850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	202
\\xed558cd9e35834de68ce8e236ddaa48c8488d3c453b3688a17293adb9d0b035bef8baf0df3eb85c1b06a8f02e2f17bb3999d9446009e299f834c8283a8386cb7	\\x00800003d0d5ebeb3c4df823a3b5fa17b4d04d37de5467da050a741f5bd96c1b250082fb26882875febc2d4204db8f2b3ba60420b32eb7e5ee0a13ce360cd6b5bc418306d69b6a8cf5dfab086e5955f1fb7cb6b8afa8b1475ff406a7487c0378c550f610139a8bf4821868cbe46592145479d1a00237a988ee9419d58c1b3e7bc0b3b60f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x672bae192718670ace1506792106590a5c19f148bd645d469b86bab3813c11b4efc7ba8266d00f1776aa3d2b8501cbbbb389b5a11d37d6f54c182edb8b5f5e07	1635744050000000	1636348850000000	1699420850000000	1794028850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	203
\\xf4315335f4fb8cd48ab8806711f5ab467667cc665d8649e9b35039a39cc1a676a348654d6f75d032691257c65544854f03ba8be5170a47fc4779e067f5765e7e	\\x00800003b720283c6c3707a31a61ff6eb34e80947fdb6170d68c367ca657b4ed7708da36b55dcb0c7b0847e6c846b193b875d05d6952eb5062c67a8f882b2ae429c90ceabb05eee3de94556f8d8c9ee242fb0d943db519a096bf1a2941c978c0fd9f96f671dae15f7717d5da10c4a91672fd6f4684357fc7bc84c0789b37402709a33a3d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf37b52902bc9bd929fbd5a6fd7d4017df5a8560ea1d883088edea0eb95b0177099656fd22200e629c49e9d01e725df4ed11b8139164d5efe27b69b19386b2c0e	1610355050000000	1610959850000000	1674031850000000	1768639850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	204
\\xf4b17b09c9d5b1f1f34bafc60405b34e1b5abf741c35e343409c8071682b296de5582bbf5922a68f892dbfafb24d37e1ecab2f6d030291949973ccb0d73d0728	\\x00800003f0a648a07b0c325899e88cb3b27f158d830844b83f290acf1cd2563ad38c85ec61c6c498152de9d4f6135e21951817f5a67a35a1d235b3090bde7e998ec182a989f60b4d603091dd4dd6fb412882aa591e5895d1dd43512ba0a083b4b65d34ce7e9b10407700972b4d327f1926b29ec1b743f12cefe54db83b19a2aa13506273010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0fc311cbe8d7e47d18d7cc0b301abfaad6ea06794283e061d2cd9a328e7e3362476b50382b87375f1be2275ba6c14c018aaaa001945c981024b8b796e6aed008	1611564050000000	1612168850000000	1675240850000000	1769848850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	205
\\xf6bd4cc7e4850f24ead5476ccac80ede34b4dafb7282c4e2e13ba467b150239509a47425e978fe745f8ef5915a1c2f33fa1862ad2eaf43c125fd75ed79ad6030	\\x00800003c0381eb438b7ffa179d290841e0886530bc0ff9a70dfd4d003bc80a649be624e23e466d67c60ae4bfc83081e5aa7f3b1573d6bf02267d71ecd255e818402897255263797ad99da5f0b7f3a56bcec2754d28582953be88f25d77d7076c70085d6df3894202b6d389c835bb0ab50c7df30d7fb8223a1edf79d2531db6565d756e7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x81d16d1df53d621375de0a545b42da5a144981a8a42d50cae502745d46402a79c83d9f4118859f4dae504d45f24f47110a2d59144138c17160143948b1a1b303	1613377550000000	1613982350000000	1677054350000000	1771662350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	206
\\xfc31b067ae3546352898539a542a9dad96ebff2ff0b72174af9f53e6eb955bbea0dfa3208f849a1a23e3c92ef13e6d04c6fa1a3208ba8ea1d33f30fa54ac2311	\\x00800003af01ee2f25b61a16efd841386c5f4fa64207e3df17f15bf68ed6642c1bcd6ea8d2821916584db5b1dc7fc7668f386b841600d4e8c42db4e5d2dbbcaff9bb5383ef3d892389577ace8583c0aaa20f6f04ac9338993de6613f49b35cd03dbeef82a057ec5d281520d32f3f3606059958238c28b26e30c0d07dee94d0e387e4ae5f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x27751b5dba4a492037986a4c5ddc4a1b0bba8c5a37b14b7af7587802c943ead9cc0c3bae55acab98ac4042791df874285ac018f665ef4592878e261ea14a8d0f	1632721550000000	1633326350000000	1696398350000000	1791006350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	207
\\xff357e72081d573154108df6c8b22676d586197989af81c92d510b983191ec421fb3d1398c9db26243cd9480e9bd920f4b0c6fb31eacc1ca69dd7bc78677ac15	\\x00800003d2ad71d26499781b174fa46dab5c53edb207af5313a41a15933204100d2d40b29860fa697215f734c8e0fb32f935f84a169fc1fe19174d9966ea1c9d41f55bdc90f2f6c07fe60880e92b0000368a8d4a938ddd540afde32488962688ca97395a5b5dd860febf7df44b66d1596e42776b9138af063f4d654bb2aa9c0c85544fe1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5764d982e76e6594b3745ab54977916968ac8da1a10fc4dbf3d6505be1898dc386ee91e5b8055c36caa0be63c132dac2c8be4e51198924fae6c4c89544e3db05	1634535050000000	1635139850000000	1698211850000000	1792819850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	208
\\xffd5b0d43f4f51df73379c169425cfaefcb78b9f8db0aeb67b919b892baa0a28f8b7075df66ce2c941076a1dddec5d36d24d91685066f367f08d54f5989f3487	\\x00800003bb5a06fd1b57c6748575e388069b551521ae6b35f563d3de24031f6ac4ace3abcebb8415e1c2daec4b2343be9fa01c24b91338d2fbac977c47788e17fc6f33debed94a878c652d50e5007cec7ad59fdcfd30ec7388a41e0e6bbacdba2c1bbc2c28f296debac30f19f9bd88e8aca57ff0a5973d97d2206ff4c44c2226ccbb0507010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x953006b5468108f72e7b4dc53c76521b72f5c5df0f1061e16dd84de5afbcc87ac0870dc31cbc423485ffaa5cc8365e64a178f8436b73ce556912647ac5ddd606	1623654050000000	1624258850000000	1687330850000000	1781938850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	209
\\x00063c080d4f2dbb8b8902780cc10d36ca26edd36bc0cee474a2553789a16aed92e3b6f5d1f0cf40154ff87650d98e27acac54dd36dbfebdeefd3d4e245c873f	\\x00800003cea297e4ee8fe0a8fa921150c06d4f106a2bf2846978b3771e92d029a040aa9bee21da46aa3be283e2b679779bd6c812536b1440b43f7124a814528024b92431c861db34940571fb901c5683b3f8ce84e082fd1d86dadcc1dcb750b19952c2fc4679098a9687195a03e6f242db55fd9a99cf6b5afc68447c28b50fd469eb467b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9bdd774c9001011b1e12db76fa03aa60425806d76f87266313ef8de3fb6e47409607c20d8d3ed7c4f2976b1d7b5507376b5978fe9192ab19607872b57e7e9f0a	1634535050000000	1635139850000000	1698211850000000	1792819850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	210
\\x00c2e3b3f178a69d21f1bf4dcd7143d3f0d0fe23cd477b63d4cb885a9b55c8df90c893b33ef729043cb0f4ad31edcfe38e86307ec2a437e344cde681bef6ef80	\\x00800003a3daaa9732b206246966299753c140a52f2ce8a486001e7a119a9305aaeb6d81fe6eac838300d4b13d56d8b3b6b64e230a5cc00caf4d52fdbf0bcfa24de5f4f1a4df2f49a568246d9990f35cf1bc363045a351faef52133886f42bea9314d69bec7915adfc05f76131ee5182cf94515654acd3411e49ff6d416e1794bdb9b8b1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x222804861fce83595bf3bd77967cca136a26d9bb38dd4d4df6962f7839fa8a00e462c2c29885d793c1f649950eea8485c2a25fc016d958e5ce96e97b00a5920c	1624258550000000	1624863350000000	1687935350000000	1782543350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	211
\\x0202f65dff479375556a2b35eb2a09116aac5940460875d32c266872644751453e3d748a3ee613a1468aa24f2cada2c786c12fc076306462549f55eab7bd7608	\\x00800003a77e43183e7dd3bb1d90084c2daad6a794b8724bfa45c0dde1ae927d03dbe6772192c28e55a1bba2d55d0eb19dd1ebfbb39d442665e4e74b01034f99b7b0da98107895094a13901307f789b9ed5fa513c267a71687620ebbd03e2fe85a61ee1700270480be7c49b862e9b0e246862182e26b396fe66cf1515fcbebeb4edb2755010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xff8f7c4201161add22e00f2bda3127f4fd590a9fc0b664977e81de9ea76d6cfb640b76d777f262dabdd0e22d0eadae3fab3df7622fe78828545d54484d1a2306	1623654050000000	1624258850000000	1687330850000000	1781938850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	212
\\x066213b651d76b588aa8fe0123d2726ae8feb673b70c31c7fa35fc2ea45ffaf9329a5f8b6b1b38d6050c323556a9674fcd0215ae55ce8505b284a8831f973b3e	\\x00800003ae1deeec2a90da4a8c9ada407a3361413aa5029939b712d47b53ba7c3738216552da735c6d113d75ea8604ce383aae60838acf24f105aa87bc4ea9471b1c9a0f932eacaa9b14df907a259aa5218899bf25d2d50a2fe44e44c998fe70d156c4fbb1c7230c421b774ce0ecc031ff92fec6cf6585c7dee1b0f14360dbb10508b2f1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x87197b94eb3ace7f27b46ed09478b7c43be9eec82460e97b14eabcb86856dbf404618e6fe17cc43528fc72e366369e5e2941a2f2acbe9925716d53abbff9f909	1637557550000000	1638162350000000	1701234350000000	1795842350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	213
\\x08ded735c5c8847b1aa4247bf7c72992f23144e9d424cf30a10e8496ffc37c2c0158e4ee04b9b55c9708f675bdc0262dfb42db890b836246ac545bc5cac858f6	\\x00800003a4526f5f8ac77201b66ebf2d8f95971263705093bc373a94955872cedfa911f10cab5b21178ccfdb5c31c054610c14ff347983562b86eae6974844d38f05a865a46e42ba50a8c086c562e736ee48256b48aaa8d49d78fa46fd8c209b34113eff928c3f68264a147953bd8bb84723d2ad2614a075b9c088d453d12e3cd4f6e189010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9c1e95105376d66e192393ce7f6d2a620a1356bd90da22830521c247ebbeb0f358a83aa85e3d06fbd79f506f029cd79c0b31d04515dcb1b53f8f5b12aaea6102	1629094550000000	1629699350000000	1692771350000000	1787379350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	214
\\x09865add5a4fd44c369199d6ed123d86ccf67b06f54aeeba0f7358754e2ce877427bca7edc99446847027f3684d8057bddbe576dbe9c5ef963f920aa7e5fbf5f	\\x00800003e7fb26e3a0ed52c6722d0b7192e9fd2dde135cb128a6e5f9cacc7d062202be8c960f0581379858b3d6f743d3b788ee19507b220535ec650f7c3cce578a8c2f1a1a0baf53cdac2ca3bd07d11f63c7656cc1fcde552d27aa094de25d3bdb08eb9177db382fa46e240b2761ed42fb84cb594979513657a4f32ee4a7877227fbcf07010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfe736a1344599e69aba2eb515fa4455d020c7cc25c9967b39df8493b2fb9ac7dbfb7fa1c8613924c4e439f2d1063619432cd6f4190e20069c5a27efbaa607e0b	1634535050000000	1635139850000000	1698211850000000	1792819850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	215
\\x0e3a19aaae4168d178e8f5940843f1d80de6d196a8c9c30706993f4d2e72a09000c67fa827e19a9ec6de50ef43bf35fee16e6b56a78f9d63ebe6bb75f6107399	\\x00800003aaf9f67ee12ebf9c2354f4e64f81cfcbb747eafeecf2572263af8287303572a362e91ab4a0aa969cbcbbb1d36cf45d51a0b0a4df6601d35d9ad20ad65f6a7d26db3352258bb8c40534ae051985ada13dc1b3e643235e1a8864d7b021b38b9d3d457047d8ed915a9a0896bce6752b3102f3b350ec4a2b0cf5d03b9e77a8d7a1d9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x80c79885a85d52f5be9f63f6e9de8818810039196637787f980431ff24b7595faf998a844f50e69129d90e10bb9f7976b5ea51abd20ae5dee649783c4bc09b0c	1616400050000000	1617004850000000	1680076850000000	1774684850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	216
\\x0eaa521be012a0b1b6a0242ae513c435ce59281d04a34a12d3e78baa8a8d2eac1b5abaeb7b1bfbea53a66725465bc0c2c74e3151bf51da4142eabfa6ffaf75d2	\\x00800003b6905c041f78990c4e59ae5cdeef673f458a86541000a126d7196fd5a3421b24134561907150987471183de64dc3e93fde9761899786fbc6ce7e6299f9266542578ab248b8586c651f2e482a98dfbc7a0ff3b7470400bc6e47602938e8bbcacf26ad39c98f4226af3834fda62cc01eb81bc1e8a1b058c4481327c9e47659a4bb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd118bba63f80c777406e101b7956da048550a621d6210b4852487a0c9b4b5610a00fca87a424d99d0ee2383c4b2c958c8f9ec4519308ce5c20e999e7f6adad0c	1612773050000000	1613377850000000	1676449850000000	1771057850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	217
\\x10aac0dc0ab969e1c3589cf52dbfa8cc9535c84df661c494dafa6455f9632af73a36aa427171e0238802e0c029e77eb594565ea267df7f96bd279ee3c750cca7	\\x00800003cf43fcffa07d362eef84ddd76b00d8cbd63c289a2eff9a5620f06bf4f5cee94125e8671f0fe8b6139bd151c16dba4d22ac2e1bb2154776d1991f5111d79c21ee4cc33a7c90a20311ef51fdb8e228fcd7614395ed932b4567f38f672332024101c057a1388cfc1992b83726bd25d2a9c0ce5f313524e541b6ca42e819e2c0dea5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4f55487e0437a4817993a8df35ba276079805254be46f9606074cf5aab2856bef1ae51d5f0fadb1382bc7a873b1650d8aba77a04275f27d5d0cd405721677c07	1623049550000000	1623654350000000	1686726350000000	1781334350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	218
\\x183a6a550ace6d0beb0fedb74fe28fe88be8b4c7b8220f58ce06c85556200c54096467d7ce2c5619c1e09bd4934d45919f42fb012a56c3226fa412ee862c9e4c	\\x00800003ce0f069ebe1e54e9953774f4aa84cf7dcac9ad7024784a714eb0a886fdc9e9b82fc1ec7d7abfc4d6a6eda9bfee9425e1975ed7f6c02a94bc811309f6484cc15a29f3b36bc5ee38b555dc2c87769dc0842f17951ea9e787298cbff8fbd47c072324a4cad7c1c79afc979ea156fbc1cf53f059225cac31c9abc5fd668e8b48690f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8245b5f55b33c3d4893c06ee2145da8ed3d16d753b0a37d21be228a4af19a342059262d4e6dc2910add86677d03422c842912fff28cc555ad226c0330b1d3602	1637557550000000	1638162350000000	1701234350000000	1795842350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	219
\\x19a67439e0680a464e94218cd26de554b098dd4e5ec4bc5c52091d56bb0302e0c50baca564b608c11c328e5ebfec54d677f3dad71378798592763a861079dafe	\\x00800003c79428ba85ba458a050cc0a958b8d4a0815009571d9d9cbd8aac5a56570b5214fef388cbcb690d13bb922a2d9a71f6e83a591f8698419aecbcc0090764d734d173c13cda2436ac5f995558ad42604323ef97bb0e95f0e852c44decb81a76d523fc090feff685f8dad940dd86c4fb29a19d295804e744682f02cab5b9fa6c20e9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x90abc3b753ad7cde6c817cc02816954c05421b9498d72ada20800aa2851e659b995ee8d92ec36190082912afd80107c53bcf371f01669ca789f0fdd560d2ac0b	1640580050000000	1641184850000000	1704256850000000	1798864850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	220
\\x1d4a96674fba27b16dd78cd648a725ba003096e653300134fa5f4df477b02dcf6168d357de8a93e5c64b9b209eeb70abf295e16aaa58ff4d5ff10f158f8de51b	\\x00800003d543318d99e57e1f278c270bb699a2dd727039e38911616e849e58aa3cb7f9cc48f9c2ac543d4a4ef085bc3d0d0455d38b1636cfd92a670e811c93a814afac95980c9b30f032c4c397b2561009c58d40337068787065c5808b92cb6f6b60e2f3dc10a7a32733377b12130fc451e4ef492b6a55cd895953e778af58502dfd9f3b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd240ab75b52a1102e107b592d13a30d1a0cb88beb6d6d5d38ea1176e99387b92049d11849de33b8cee4a36b7f775505c8d6fe974b74568b34ca6abad2b08ce07	1641789050000000	1642393850000000	1705465850000000	1800073850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	221
\\x23ee99c47a74b83a8c79d74e04902443aca2f36480b6d6413d6265f41cc9ac4aa5abb152911f143f8f8dea31840d255ac6b220a29681ef8b21307928359b45db	\\x00800003bb1157accf26c389a9d6c034e7bd88ba692d2ee1bf98f873af7790616ddf94f66873479e85fb85e3550a63afbd042af58266f2ab7697db8e772ce3fdd54f297fb7c5925dc72bbd3956bda1388e42b4a2a66825a27106f742c0c26a5270c30934b397a991dd5d7727edf291ffcd035beeb88c7af18390c20fe5903a7aca9f3987010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x16cf57676e6740a6a8f5ce5fb4874b1ab84cd32715e0a2e41f11bb7cab347bd0cece35d6a2b920550b8193a56d009bdc19eb20f8740fffe0ccdc08ea35d81400	1630303550000000	1630908350000000	1693980350000000	1788588350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	222
\\x2782d37d4d6fe3d4caabd32438d0bbaf19d0561157f51311d3e959518b9785e3a28ab3b0e39154d5528de5fc3abc15447b7cb72c10f1e139a0749dbfe6153e01	\\x00800003b1c1c162c3852fbcb9eaf2fa1e9e3c4474e5c31b5590d066168a2521d4e2e219bde1598faf301fdcc863881436cc214ddd1ebb85435040ef645f2019737d46534d6690e30bd57d9e3de7077839b177633d5b446baddb76c30da276240de6a998fae196642bad2d1bd18aaf19aa188e0d6a577fdb60629eb13a6af3efcca0e061010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x15671d4714046be57adc0893569b719aa164b60cafc93641a54c7ee25b48f21ccf06306c9106411018a97f40601840620319cd318d8d8db7fb1b6a909e7f7301	1624863050000000	1625467850000000	1688539850000000	1783147850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	223
\\x2722dc22f8aca95918bbaf4e85513723c84649238381d61632e8dea4af40fbc8f553412bc008c93339f710273c9a875fdc6e9e1b5b6c4e0245f1e1224e5c23cf	\\x00800003c7e630dde26aa90dab662c8c099e06f4609380be33a2ba7e2b048094d769960bedcfb84f9e5e971aeb481def0703ce5c93e5122fba039998497f0cc6e379b7ded05f72defaff837bbb526e424ca94a2d27cb7db3189802470d53a36ad3bfa43b541f910cb357b72de8748add86a34bd7421ed7eb74d2ae9bcc4c03028402dfff010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcd5ba37d7a545718b36d5efe8c921b873c82aaa3d9a8829a2a9727a962d1d8ef52cb4c4cb187be1136591e7242a7d10ea10f75a4ca6dd413b51859f9144ad60a	1633326050000000	1633930850000000	1697002850000000	1791610850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	224
\\x27525d6c57751126ef38398b09a16efc2d42fb5533e80d10e5d96d3d53d5386fae96559bbbf1642bebbe7a13e6a62a51ae23d5575ed8240da0f5cf4db4252c3c	\\x00800003a1caccb46f28c181f17e69cc59a1b4d2ae276c641a8694ae574106653ea09c207adcd329d68945dddb94a64acd26dd0bb8c548cce7168de5e9f9cc5fd3136dd97af31330af16fa6b96df2e502cb3aebdb17215a554c19ef821fc7d301d0f6c5f8dbb63ecaf72cabc9e20e496a2430dddf07ec7395432b89eee228cd727569e87010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5d9d5714c13976ab9089c83647997ccf42c44a1922dceb36d5a7df39bab94210f0563dc208d5591ae08535ca55fb1ca6f1848f25f80d947ce4fb4181feb84800	1626676550000000	1627281350000000	1690353350000000	1784961350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	225
\\x298e55c554de70e432449be99bf961c38b74f515d10dcec811472cf33431d152f56b71acc4a557bf38e87a7f954e7f7d85e502ce52e85baacaff4ab99914a08f	\\x008000039f0dd3c3cfd5283806480a177228bf49bd5b3a8fa20216728956ebe18e899782cd2a2e9787ee010be1c333972bcdea57e72b0f124d9219be3ae0a76bbc7b7befa72ba3d158c0fc6b0a3bf10e0470ff6a92f4495f58e4a511edd7461749cb8aeba7ca39943436905d64c0a3ca73e19af9803bf0b1c9114d6fcfce3ef2d94534f3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc9701dfb6a102579cdf61b29705d494597c83aef4b120b4668e31967a1fa438df3b81462a2f342dbfc9cbb09294da35e0debc2a88cf9624c0c4c0f9631f5ac08	1626072050000000	1626676850000000	1689748850000000	1784356850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	226
\\x29b257760fd70903f6d2cac4e6be0976e16ab2b6f86113100e6ef4e0050d3ecb4a041f5167e72cfbabcc434051635c31b5c4960cf9f073052ec68134f549b89f	\\x00800003acea62d986232fba25461cfbfdec29933360df507839ed3e0e97b011c94eb8e2d342557ba0d6ac13607f88a5b2eea26eaa851f66bd242bc24e5c45c9536e30ea7f839c60b126c745a3d21497bb313f4414232cfb7c8ef55b8d6c7f4e3ec2d15d4b298af2796c3b4fc1e7af86a2f7c4c965214d8e99be58192acd3a5165186d91010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb1ffd7d3525e2e9bca3e7391721009803af7cc1af180648b96ba36dc48bb86cbb31466bc71d30901473ccfbc766a97e517bcc12a894b34cef91f60f038b7af08	1636348550000000	1636953350000000	1700025350000000	1794633350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	227
\\x2bf61c7b4388f5900c4ae4a47cf0965b86958d96a5a9dec44449ea646b0bc6bf8f5c6ee046bba7bfe503f0a7b49bcbeea9220616256c4cebc864f0d7614cc123	\\x008000039af1f9552a1537bdc5c8b693f16c4654d2ffdb9ed0e63e96594aba6960304b4e882c64146c3157f7ef9d2cc9203ddac12f08c07bbf357d942c94cc7cf3c2f7cb3d1541a6e6b363cc6d8e967a43428247934d5cae99f2021cf9b211674f5f55794e6585a908995b45dcbe121d53d71e0d5098335ddfba4fa41d3d4335c5236df3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x34af1ded8909498cd7946bf4a93f69a5696c498e4da1733306d39e0ae11c3f66b924e118f252b2e8d61fdb2a568032f43c71e7c9c2f567a499b387c544b89b0e	1633326050000000	1633930850000000	1697002850000000	1791610850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	228
\\x2b7264c300e21912cd558d0a4bca027e082c2b60d1facdddb76dcddbc78164bc46ba76168582047e7b016918638c8c08d694f3a36a78a1880db92b3855fce36d	\\x00800003b3b0f9a4692429566bd1b8ca1c7274ced8d80b6421e74c9b885e308d9fa4704a1099d8386a5cd1ed922fee691818016cb1b60e257e81e90d072cb757e4309d9ab818552522de72ebf00ea2e08078b4317591b89ce738cf5732436030e4d498ad0b0e6962ed7e87c5b38433b4517469ef6d3bcf106e7a86b5857fdf9bd2d6f985010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x045498340e6303ab8557a6b70fc7f63e8236a2a41ac2d8a75edd18d072a68a957732fe0d8aaa4df273840a43f67f0f0dca5d1197fde18a7c3e1ddfea0f13b009	1631512550000000	1632117350000000	1695189350000000	1789797350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	229
\\x2ed671d51172af1899fd17fb501d03d5d4ef2747c39e97e0e00915a940df6297b8280596e09ac4cc0a07796395a61d155a27f4d4b552f91437deb1ce2af994a8	\\x00800003c5c5fa57c3e401a6a843df3bdd3a4c0a748864661e1d759cc2e2106100f90da1bea571a8c8bca6152f5a1d90d25c1bfc275f9cb0262aa4cf52e0987120ef8a4b7cc6e69ebfc9175762bfe110a35a15d10ed564474f07cd7c1932d4739b87f8f10bdf28d2777704cbd1064271bf669c264463866ca7b0051ed663c39e5be51aa9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe3ad792985fc9f51477a8832ba0a9d77a08ab302425f3f6e7c4e81d688ed80374eea477a7dc17cc4b8ccf66943de94dd3743c06d074e2024f93d1e3cdd77ad0c	1626072050000000	1626676850000000	1689748850000000	1784356850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	230
\\x35e2703083a66fd042a62da4987989e8277065956920a5f0e33e45f75946ec730e5f4157c929a1241009839eb3da29d0771f0be2faabb64af01860eb666bcecd	\\x00800003b8b282c830923684858860d43ec035b3e3ffa43fba7f717d79921e79e27629bf0f1dfc79b3325e71ae22d3d32ab54869ce270df9635c06891f69586b9e393aedbe1209257bf750f2f046209d151827060fc21872b1643bd87a1ab41c3e3e03a65bc91ae1d8e953a0b8449bdc39c4ea6e93c915593158ad8d7960f9461cbea403010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1f15377818aa5252cec9e1bbdcfc7bb77939250c05a14adb8cb570b23d6f7850b798fd2e5cd93b97742e283f137ea7b4f41de005aa3a0034c999883ddce60904	1641789050000000	1642393850000000	1705465850000000	1800073850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	231
\\x35e228e41b0a7f1d1952987a240a738d6e2694f541dc209937f0b9dc947d8a580c7e5a970582f882bef46ed6dc846d4085f31952b7d95fea6096940be5bdad02	\\x00800003c2fe575e5b4964223ea8f58e19ebf840d882b72a4f39ad48873a932da4358fd1726ac0b55771455afd0eca6cc1aab380a76bc8113bbd87e25bf75c5d64e2c15b6c967de8cdffc02cf1d50420a289d8a9864188bbc15e67fbc55d794cf67f0b151b7e76242e24efa736bf2c2cae6804ad4ba3271c0f081fe9073d65420a588173010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x674ebfe8a9c553c912f9c1d8586ee223e13fadf9ac9111814daa6582c147efaec947e88bb9ef802dde1afba1b5ac7577ae23f77f9e38d22e37f0c88312842603	1612168550000000	1612773350000000	1675845350000000	1770453350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	232
\\x374668ec14b0c7ee9b19b3275fd1900b023b87bd6c7e49fd968f894be52ee81306f595fd91f84441d80ee82590a1564ba7391532a575edad3c0238b2d5f826c0	\\x00800003b9efe4e693c500294b6d555afeaf681690a082d6adf84236fb4720b0ba4a1e52d2c35ff2eb16267e4169a719febbcd27948a34e012ee1ffd31898c9fa7488aea1fd600a5c3b63c6f6ca9c22c9753212f7f66a049cf030a978fb100c60dcefc9ea9e3206bf6a2bc90b77f715dc97f7630558526b8e9a5c07bf01ecad4bd60ef81010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdf4415f2528b17eebd0824b9f4fc044f006976923d45b2ba2dbc178abdfa34cc7c89ce3190684c457a21412817e0b294c77df53eaf861299650f19210981fd00	1615191050000000	1615795850000000	1678867850000000	1773475850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	233
\\x38e2c5d345d71145c43173f7391145a90f3384098056df1f4df736923ac656e7ae807e7485fdb9013f5d7dc956ffbe7d474f4331328aa7310e5d797f62d74f6d	\\x00800003f4545d6554a15f4c3a99ea8d5bbc8bade3598fa052fd96d8c04eda920c3908c0d421f5fe2a8667dce5756de704c41939d7b00dc5b07f4621de050c042b619ab9f262f391c7585dcaa6fb458109b9dee4c48f4f1478dd8272025dba6c56212f1c385e2d5e4b9f7d51ceccd7398a365ce37c867fc3af1c02cfdc993cdaaf4e1329010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2a33d970d7aa8adbaa368d0e47635888670512aa46cfc198ae4d8a07dc9e8a297778375488dc18f6e342eb25c1833e10e7de0485d92c860caf486a600e302902	1639371050000000	1639975850000000	1703047850000000	1797655850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	234
\\x393a0b1a296456ff72f0756c52f04e8f68809e56bf095bbc774d252792b0015b484c38dae9d6f8b84470cce839b2881ec26ab8229e16460c6635e2cbdf7a19cc	\\x00800003b8be495c904c07ea6c98d3ee6e881317ce50e1f768a90963cd6a6919ab8cd23c273a4ba39d1c92a298db93e2858747b7d3b42df85cdf39d39656a8c9ab72c1f2a7370b1562f710a0b4fdf6bea902a4fb19fde980300b357fbf7f7b469ff0b3304bd2de4de0be73485618f27c112faf4e06399ad7bcf8687844a07d95864089ed010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd9b8d95c2390e3d1dbe40f5bf6fadc441fa49c96e02202d8193cda586bac474dc9383430a3bb2c266ab902fe4b5d7ccfcc6269452cd51b9ca91a9b604eac3708	1635139550000000	1635744350000000	1698816350000000	1793424350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	235
\\x3cea9d9d4bb068a7b02e2b7a1434f33f180cb2c1f146e7be002d8b8416cc352619ef1919503f8f1e3ef578c0b4756924e066d6d665e3fc1e27a2f14ba9137145	\\x00800003a6f128eea248ad9897e4568f326f5690c4c2839976888734620d1c412d152a8a932d3e9e3d3f4e359511a7f3a82d4560fb5ea44f34ed0ef67a564db5f317d8f96ce4aa42dd2abe85689f00b8cd18473abaa9d6c3986ffaf5408394617e87b1c48093a375d5dde5a040bb0c563c5424a30865668f747b5b863fee6dc6dc6fc5e9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43e6913ccb9f33be748158262b403b4f07d678992790f3f6cb29be90bca62434b129b0b99c4a4a2c42837fa0e29287510dbdfdef9a29a25e8cd575c468234700	1639975550000000	1640580350000000	1703652350000000	1798260350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	236
\\x3d664aa5e3ae5bac50fe00052d23f83af10a4d3cdd26a2513fef582ec664538f9b188810b21e1ebc6592265216de4cb3dac843baa58b5668c80649cf44db4de9	\\x00800003c84869012b78cf6b6d72d52755ee805a156e9f2c383739decb311a954b07e77dd083e262be20c0ea214b255215fefb95fbc23fa0abe7fb97f4603817cdc61cf0e8a5818351c19dfff53e65a2646d2af36e22c87d32cd09bb95f60844228647348f8b4745806688fa53f0e5292d768480caa003c828d81046ffa1dc461de40f23010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xabe9c27455ec32c2a73f7411123c0025b2d63c2229588b37688177e365f8d8ad882157eb97863e750b86386f5f36de1a4e229804405111e58922cae628080c07	1612168550000000	1612773350000000	1675845350000000	1770453350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	237
\\x440a27b42d0595247e13c654cbdf845306ec37fcb3afd63a0f6cfbaf063fad06af5c17478a8d8844704c9747052ee11c25254fa31a0acb574c60025c99622498	\\x00800003c4372a1e0910acf992ba7a115f45196266d4cfed38d329f03deaa386878b2f9ba0ca95d5ebd750e4087bba4928448795169347cc243b2c4cdd84ac3f11171578f97a419682e65687d1ffbf97b679c99762006a4db22b3e4296eba42d77e2fc728c9a5f38875135b3a97951eb5102b15dca049cf7b82f7f676eb2e35d91cf73e5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb61760a90b779dbd3ae12aa9314b341cb2a4781f3b25ae486a3de29f68f9a6f327b2e3e46cbaabafa37981d330b5e94116ab03d3c001864ca75266dc9973440c	1612773050000000	1613377850000000	1676449850000000	1771057850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	238
\\x46069da2095d4a68ec545911f672a14421d23b3f074470496c11ddd006adb2ea5f03c4e0fd512d810c11172054dcaa632a0f6e938592b955b15fb5f32ad22cfd	\\x00800003caee1d3334c6902504e453e04c8633c5fe20423b90a9c409869c7c552e2bb39381e88172e2289a605c0cf2e3bf004326a61c188bf8121dea17c521e3ccc09afe2545e93c6d9298641660906450926689ce931cf999b92407c9738098b97e930484a39e1d3c61fc076432439656994d1dff4a0fbb23598a5f66e27d0fe58e389f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb974cf82d32a8f309ae7466cb208da057267a32aabe65df595f51763362c25c1e78e8d289d7c884b83fce2648c9c7f2853a62277be746b29dc697c42240b9c0c	1626676550000000	1627281350000000	1690353350000000	1784961350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	239
\\x494eb580fc1c009c19cb8b5ebce138654af4f2272400bb50ab8ab769764859ceb14fd5587c3d2682125fd498e5f543d220518f635359017f541c899f5751c770	\\x00800003baa2360f690be4a37e301b08445ac768a6daaabe459f222b132dacfcf4675e359a7b3f2c56ea51f4c0a7d65f60490ce5ab08374dde432986138aa8713db0f6ae84aaeb011b86ea74a035b091f575d756094ceee1a9b0d855533001835e88a7e46bdca99d670fe5ae6f6a756dc9509bea95da378ad8661c16e22586e870d31e05010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x692fc09f3f9b4f0d02dc6ea49f422329bd24bcaa4251013278103396565d18168b899c5cd723da6a0f6724dbb58c37107936cfed540939efb4a39b71feaa7500	1620027050000000	1620631850000000	1683703850000000	1778311850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	240
\\x4afed03581acadb989135e4036d9d32fd2ba6a6e0b3300bd5ce17f1eb3cbd54b107ebda8fea34b426fce150fd323e25ab362f5f86701a5db41ffaae6ab38fbe9	\\x00800003d1eaa129ca41ddd25c8668458483ba78f8954d8cca9e84e524d9d50bfaa6ebaab195248ba142a369c3fa015a88d9d494e3ca3546bc66164c633e82239eb58f21c940ff4775d86da8d521099dc02c5dd63be6a91c0d9ae9bf2050601339c1a979a804f990c6c8396b9166cb1f24caf46335d52bfb5cc9d79b8cd139079b097c3d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd9c23878fa3ec240dc7de55446870e9623c4c10baa21f1a7caac177e9a0fb702661447a79a46e88530cdf46d785004ff7e30ef9a6a2d64ea2d28692a5d969800	1610959550000000	1611564350000000	1674636350000000	1769244350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	241
\\x4af6b0d1b598b888f6c1372c08f3bdbf56c053f88478133f86fd19b9e322bb7996f7fad7d4e2cd4b2edc869b1e285af09d44bcf411387a379701a8e44753a0ab	\\x00800003cb7b57e598b0971aa0c136046e8646228255ad1087caa91e2fd6d11e333dea19b7aff3874614a8311a765f4c4a08e5bdc91e6b6ee31e5b71f6ab4d49b0548534e31330b40631e6929c4b9a5a9e31d2e2b42fd0118ae2a279a01436c99a33aa1b7b2d6101167d5c3472cf3c470fdfc892fd748879b6aae8eb21fb55045913bfdd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfabd8ed355dc39fb79ba9d18d70167561333bae53e3eb0899bf2027e1b8d3866bd2eef9dee435d5d432ecb1f125af439278611aec723a580ad7587fc00639903	1628490050000000	1629094850000000	1692166850000000	1786774850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	242
\\x4cce21c94ff85a6bb3568e805a81e437f152d39b805303656e962b63502a97b1a963c81ed40cd3cf4ba855f363142b9caf29bebd083e41e74123c29b109ffae1	\\x00800003cae9924e6385ecc9253f6edbd6c6ba875a8a37ae48160186fd61c1d4b3c22a436ec75497395e11873f121f48d19303f33b43568d424174142be5a93c49afce1e6a966f0fee6db6f115eaab141f7afe8d8d6edd0ea6ceced7635f748b381bfeddfaaf75402b540e9607525bcb28bf76761713d911375458c23b3893585cf1c803010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xed078540cee1eef18d66931da62dcf7a90c6677e57ceb045cc5aee49bffdf328b22587bca461c8bb764ad2e55d1930a412cecab8f0cc7f87af9bb25aa2a36d0e	1612773050000000	1613377850000000	1676449850000000	1771057850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	243
\\x4d6662c20e6585b1babecfec7efc4a623455a24527b9115554288373560127c97f2d6b59fbbec8ae95df3f8dd00ba1b8805a7d11c3ed35afb3b064e54c29824b	\\x00800003ca671ac77060d8ab0c10fa35da42dd9018da1da2b0a344369c087268166f08102f62ce4db03b6446a225c6a7a3ac499239f92abe0c609b327d4d960a4258f7ad40a826c901a7a9c97dcb7a7e6ab4408b8832ee8f8b7c063668bbb797b169c6e003e10584063ba1405b05779e6ee02887ba3f2b0ac5dbe0e3cf16f36416f7ddaf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe749bc8550fddb5d4d6999ea7d0204a92b6dcd38b05c7ad25a99518312cc6421bf18e2e64667e6e092a8b9dc12757bef178247841eefa23488dd3e8476bf2203	1623049550000000	1623654350000000	1686726350000000	1781334350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	244
\\x4e92c983b853b995cb64bd71a8805eebd4136ac9c069c3acca9abfe5a656d9b1ade9c3c94a9e09d3f290263bdff10917256ad5ab4dfbed6c61b8db488ed47e36	\\x00800003a25965db2bfc5568133d130fb239db79182e8e6c904cec79666605e49705d3aa0274f771a83b1b449faa116aec5c7560faf00a7c2ed6dfea10913eca86808ed20758f8d52e95d3ac3c5b15452758189b0f824968169d5e257019415376a0404db6b204e7e89aa9a68555073c0534ce14ebc5b3cfce54518fdd79de595b2c8925010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0d3151da876076e9d81c82abdf1664e47bc3ba37991582ce99dff474b66b6532e97b33b8457775dc8c5e6385b6a82d40b2f40b4b3f7fca933853d2ed34c40609	1622445050000000	1623049850000000	1686121850000000	1780729850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	245
\\x4ed2e60a75ed622c6b1908779a3265f98beaaaa312fd586a44437f4b3888bfe51eff70cba003a125ba639d85eb799a88ff3e6bf0d07b0e27ae2d3d983b889799	\\x00800003bd19989c1658f42e84412a13b21a94920157acd3aef2926821ca2f28b2e3295b82fdf6cb07055cddc4ae01f5e46f5b50520af39d9d2b162101f7692e4b922f027d0a7d2060661798578f62cefe8e4020eb33813753e41d28b382993284be6f015dd1c2a96ce9818fd67ae1df2dc547175c4109ee20d6288d8932653ac56d4a7f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd7c40b4b6dd69c1b4d4dcd3d5ac4f2fdbb95e829c51de2500a362d1c61c558f2af5e47cb78ad6e3304a668fc3e2de5428b4359d9142b3b98b26e71d4dfec420b	1623654050000000	1624258850000000	1687330850000000	1781938850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	246
\\x4f2e033744f868904e17d73e66617f78b908c6ae0583df3335d1a8e06a3fdc1e952d66e2cac08b0c566b35abe981d8d1a37066bc65f86bd1d6c7b3380d64130b	\\x00800003b977951c2e7312bbe92ef6e1408fc3430c6e1a1c5dbbd9f557ba5c84f4a42ad7c91ef29b712c4b208e78b284aefb5d47c136b1799bbc7e5f90850a60ec2a43fd1f7da9f9bb6f2aa819bd4141e554b2ee011e3dd6e9b75b8301493f4e6b102338bfb403ca9b1fd0fea05212344ff6ddc4ea24e70c56ac3390a36a018e4f4f6375010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x95df36da4655b711a17dbdcf7584f952c066190edf157a2f24bcdc59ebb0637f961495af2705f7723acce5fa9564dcb10b5de6e88abec875ac8ab6e1a70f010d	1618213550000000	1618818350000000	1681890350000000	1776498350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	247
\\x568e8a558d9a5486c7d5e4b418541cad6615d43f9b5e0aee69492266b4d903144bd373b919269e67846763c7b943b8294f5bfa4d4bb76e1dd0e6edd30586d25e	\\x00800003df2c08a53c9b073f1622a872d8df60f057ea29ee9956333caa980f28e65f8f999a20f5f1d8593ee6d626757a4979fe035dcff3ad97419a334d473bea4c09c7fd94d51a66652ae2a274c35016eb47d506eacad541aa5b770f36a1da88c979d4c3a53e5b2821328a8c23ffff3e24adfdb1ed9250b11d61655a1d45031b8e32efe1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5b5498e54fc88ddc364a7f46fa2d3e556872e530cf5b6fb838925d80b8a9e9050079855952cd40521aa3514cc9dc280c699eea29298f98501f2eaa3ca3bd2d05	1619422550000000	1620027350000000	1683099350000000	1777707350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	248
\\x5f0659b9f07a53af5b87d2b1bd39000ca6e8f592335dfd367c8fbe8f378c60e535913a1de9ef2fe581bbe69bef9f240c9c835c55a1d1aea235be910529655af7	\\x00800003de7fe4762ba2bc47dd0666333a9f5a03b5a4871cc0adb4642c09609b21d3368603f4945056725a93dc434b45aee45c4ed2562012ccede4fe0c230771f82c9661e7ae260f98ceb94780d8c8df36755a89d8dee4e8969228f4cff3c73e4d01c71ec265c4d00675de3149b61fc36e6d702766cd58243e47e183ec1b89cfee0668b5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb6af3facfedf7a9da8d6f740648659750b685b9ed747dfa218ee01350fcd63557af5489f454a6fa8d9b8f41baf9f0d41a5e2fb513ba01c4e3745d6cd588e5d03	1626676550000000	1627281350000000	1690353350000000	1784961350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	249
\\x5f7ea22be28466e684722e723a73a7fae168e4b5a8f0bbf65e843b3230af711d2475268675e48ebc988cef62b2d08e49654bcc64d404f771e65aef6c76d70f26	\\x00800003e350ece008213504d7b92300147d0db24aeff79ebfffd18adc186a896381aca8689670ddc0ac9e3e23c8dd5ee43e36e94e6d2a667f8b61fb3252c0787dfc9a2cd4784e415410a51512fc8e4ca15d33f5496db3312ee047eb462d0f6660d48dccee4ce960f19e5d2fb79a1f555c6cb2fd5e6aa7ca2c0b0f01fdca8e3adb23cdb3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8c9b5baaa297cc04eb85fdadb1bfc5d7d3123afca7d9cc51a877d769b943e5ce243ec923dbbd206e0e770b93a24a76ed26da4230fc6b645ad1bd82ae9145a406	1615795550000000	1616400350000000	1679472350000000	1774080350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	250
\\x6092b55380129bdb57fe42bd1392f0f406e4edcce0126c181ef1fd5bb2860818df67c3135ef67e1d5e01a9f0a0a1fd2c53f0639805dda2bb0abc1afbcaecc355	\\x00800003dcc8c891bb49b99ff3f46f6fb8cddfae9931e7eebf9b9a3fd469d0c22df0d4e38091f3138483ed626327e02b32cf4fe71f9564fd8597af2276b87ea3800d59a1972b4830e225df58ae6013891aad56df1fab3ed3cd0a1e0273fa97c3698af32eccca82319f8b0a25d25969aefe6273d8ba467da182a9f43c9b3076e838eef567010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcef44d00d18f588ea71711c5030aef93977a710937b860f71bf99e7d019debc8c3b2af5bd1f218fd389fe53bb5dd27ded11ad0a86b4e3f36a57945cb594c2c0f	1641789050000000	1642393850000000	1705465850000000	1800073850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	251
\\x635aefaac372cd29ffe9609ec93002dd15be08e93fda638604cf117d78c481629ae7623ba5623a91f3b174129a4ecd9111229fed51395ee16278df82fbc9cbb0	\\x00800003b0c4541e283c43f5ae6e517011130475cc8be4b2f87b7948f05dcf76b88cb1f70d7bc270512bad31f1f17849a5cfb6e96d1384e9eb82aa22c4c8ee6630c2558bec4f1f6290abd45633af1c6678ec178145beb4c66e64d1e55e3043b21f2cfd6f75b961310653164f2ab3195563d03eefc4137cd32dfd48f6794ec19287bfa3bd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xbb79b5e30e6cc4e3b222f9f3d9d6753d57803ab1e2b08c6fb2b5eef7710b95ba4ba3ae6d226edded93bff214ac4c3f000837151ef2fb7417a00dc9d57d5a1509	1619422550000000	1620027350000000	1683099350000000	1777707350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	252
\\x6612c5f3356460df6ede5058037552309fef02340331e01ce2ad3b3f9ddd13e2181be0fd38cb436c9e99510cd4e72a920af0c4763f0ff18641216822981262de	\\x00800003b52553a4ccf967fca029b9e3ae9c1df82c2cad6c88c6dc3421923cc620d1e47a8d981a846bc6c900194b131086b567f319889d0dab69856a685876f6528127f4140c92639f7eaa1e3b07d3bc3911e91e4f5b462546511b2af63f6cfd1dd8f732ad278501193528d2aea408a7a83697f3f638841aed88756a9d4aca9f98296569010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xaf86403e2226f5045a766092f2604995b9c2ed2db753bc81ef8af5aa582caa6ec4197259f8bc64fa2d0fcd2e55eedc2d9c73b45913260ae3f7d79fc3ec6c020b	1623654050000000	1624258850000000	1687330850000000	1781938850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	253
\\x67f29a992c3fdeaba52c7cdd0ed1cf5188847b576923e9ce4310425d7115db175fd4f109cbd181a61d1f89db3aebe46031331f5af5e3502bafa9ad32d37c6f50	\\x00800003be59b890bdd9967dee4f0c9ece9b93a5c44be0dae0bbceb99f6389fb7d69ca797103caa88ab384eb0c23680e9f53f586bed877cc96c3d3acf5916ad1afe5d78b3ae681396453e6d0a1aa6c6e7c970034acbad9fc7ff17bccc78b106355cd4764d13992ab5144353d0eb83fe591dbf5b57b383700e3aa507cd126c1004d9fd279010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x26cfda97ee3e00404a570b29a405d0db8d72308e011dd4948051b13295130a65577eda3bcf1584861688ba1dd8eeee067799be136c79615c4b24a29d4664910f	1610355050000000	1610959850000000	1674031850000000	1768639850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	254
\\x6b62910f867d76ff5ec8741ae23320b86bea3197fa434ad949c05cfec947c0c42db26ab94c5973777961cfd55918dde038d973bf218c5e8eabc91c13e72af1f3	\\x00800003aa39dac7cc5a413453bb62ee45e99b279d164afff1e6cdb9576f08020c55f85ea524e2eb0b9eecb5a96a52ac71d3b09fc133d8e99a9c836db41534e09f5ec36241736875a978b89e6285a59fa1ec69693a73dfbe0a3718dcd68f9ecadc335c23ea8640e1522a0d1db4e0022a682ed04025495e69d6301a3cd02b09b7c893c05b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x45fd9f42871a09a8dc4972057a06b06b88b3038eda047f9cfe1df20006b921c0c8e5ac21a28883bbf287bf8114d76e8e1014067c1388cbc6d7637a36c224a303	1638162050000000	1638766850000000	1701838850000000	1796446850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	255
\\x6b56d23bd7d399fc2a9a12654b6bb1a5f7efce1acf822ccccbc9c1bb8b77507afd51277074f9f0260b6280ac1acf9888cfb97a131b818ab34fb5ed0dfb1bf97e	\\x00800003b47e8ef855450777dd502e8dadea98e249f302e46d2cc2547daa6211117047cdaeff76876cdf1fdb2e2f71d4364cd2a0db8b94f77c10bbfad8e6ffc25f753a2d565a15a8e87bb6e0f2384c680ca12ea4901743885d9eed787e52ceb4f74798973e2eb3d10a15190217f82d419585794f0dffb5ac2f2405cce50cb7d1b555365d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xbd48a3fc351d92d9c06fcab2aa64ecc97237b9d481b736a6c1330605d8a8bdaf7ff01b75fb7e075034f4a5cc56d28b545b79c81ce1550f27d230e9804208b30e	1619422550000000	1620027350000000	1683099350000000	1777707350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	256
\\x6fa21efa0d33a1eabe7a6fbf9802c9f4f606b41653b6d6e712d2ae94e0c97e4f02861998bce7f54aa20f0aab516a161f54244797a8f65af26ea4fa2d565f6dec	\\x00800003a558eaba19ac0ec804bf1ab287e58c3d2c1233c15f3dc0d55a70e72d4399c21865dd6db742c6310205ae03560ba79511cc551ff777961af7ad76b474327a53d7f9f14765431791b6c22ad36daf354b3c23104979c22320f4ad768d9698da60d471a3462606ea26ce050e27f1ca14baaa72ea96ce1bbd4978d642521485bb363f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa15d0b206cd7c580aa1b818ee111db32fa336fe9519d8fc8dea90aca7e850534ae690c564e9f184ee62d69936a19b6782bc233b53d5646507ae44bfa731b8103	1627281050000000	1627885850000000	1690957850000000	1785565850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	257
\\x72627138d47c0757dc3550f423535428670991d5ce3939db44285c57f07172d8352146d9969cff3f1cd0fcab0100eff5bf46ba0238b96d6e8a33e2854ca447fb	\\x00800003e973afcfbf32b6d9fb325fd7a89897a09f2442183ad62b83afce0305d01c5e2363acf4b517aad8dd71a6c0ae35d0ee1d164751039759400420b0d23817a41c903828e95b1f078f01879d8d7b454dfcf20f8a435dec6af84b156e558bd69a8004476e812545317596095692b4034b1decc03111378a6656ad9d2431acee2e1443010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x878a00997478e91f9f0b79919b62b8871a55e718abb6f9c6b08f642d8861e8b75e39fa482ddb4483e1fbf835f90360f8afa5d5b8aa8c0a4d2218cade6db2af00	1628490050000000	1629094850000000	1692166850000000	1786774850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	258
\\x7916dd75047ed4ba037d5d6946e4ad9dc3b9d4483ece17dd6c2603e89f4d3ac95577fc3a8aaf59347174e9745a3a205e11a3a2a56802885b77db83da6116ffe9	\\x00800003d31bcbaf6fe2945752106829b13140c5027e60e365897530c04b3eb0ebb9987ad321bfa65c1950b8b84254191d640625a3ac0bd27e3829ea3cba3423ad70a1f11c4216025794bc3c3a016cfcf6b8d34cd42ab142aa1fe5292e8bbd371b7c712f9797016b36ead345126a7cbff257aa7f61850db01da752f49b1807d0e55c4df9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb0075d3cd758a7b180dd5ec809280fa0906560d3276eac724318a23983c86fe5e725623c9310e59638236066516db207f3b95aee622b4a611e4e44ed152bb403	1615191050000000	1615795850000000	1678867850000000	1773475850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	259
\\x7a9e234bc48a1a942c53432a7418328a5485b0ddcbf02282cee4946fe74bebcf84263385e5c0526ff7d56844bf1b68d714d122387daf2edab7d14bf850de9a99	\\x00800003a01386df19213c9c16cf76ce7360fcea285380e637fb01919b3ab6d6fe49a34453538e16bbe74d0e4da21f7e4a51d18cf01593e6aa25ebc8375b479f18d7e9ef28f20226539f7d70dc7c1e92a76d94486f9d1c38e1b3096dd336f32a08b033c962b0635bee8ae32b5f5d59547ca45540b4939d57c81204b0eefecf6ff4aab437010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43eb97612d78b9f539cee4f55858d69a9250c710af2166c0a1778669b93e1c556d3e34bd2e90833d19211d02f6fbbb31e9d0f73fc179ce29b6ecdf5df2370b09	1627885550000000	1628490350000000	1691562350000000	1786170350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	260
\\x7b3e63058fb6d516f20c7ae846d98a836e04bd37b780f2090adc94e63742fc375c90f64bfca36fb66c7db23203585118a05cd16673d98463a57d05ed08ac14b9	\\x00800003c77593451b123c0f9a6a350478c38822868166992377ccf5e4573c30704076a25097f8b176d792cab2c69c88c8739f04cf87a715c3d343c4b7ec456e5ecea511294a22db0aa1b9f4f81bc9dfa808cf373b534792161c4b23a65ca03cabf7f0bc1be4f679c4eed67a42340055e8b7d673f16174d1e4606eb7293da2486195c21d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd2c8a6d09bd4fc53d48c1685aa00cb4923d63dff6a38a13add09331c0a3f6ca8093fa77a411a1cdd2ec94f4cdcad9e7d0821ef20ed289b82f2719ce194a1040b	1638766550000000	1639371350000000	1702443350000000	1797051350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	261
\\x7c8e0a774e4cfba1ee10b150ab5362eb5c228a1793bc5413a5bfc89cd2203d1a110a7cb418eae09348bd6d0088f2793697394839a14e821766e2d89b8a3e95e8	\\x00800003b5fb7e27928fe6b28fbc4e728537728b1d13fbd93b7a9e02bcf1c3fc448bc3107cb50312ae5128239d27809399bb91e7b0c9c76eeb825ab24c8adfaf6773bceb18473cb2530fcbb689cc0b8c254592d7fcb39bae768ec17e9e3c8f2e4161b03d75d4320aebb3bf33e3dde6b7c4e0e635018cc294fc1b31710ac4eab561602f5d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x88ab587a3b942448f666307685719e9db9d5a7801466ca41f111c8f9cc7f641377e549dbe009cc1a0fd53b001e5dab42befad8993580ade5e97778cf25209801	1616400050000000	1617004850000000	1680076850000000	1774684850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	262
\\x7d5aaee0a641d3fb476847967a632973bad5edf066c38f507fabdd7730cea8dc55a30a44e604aea88e538c47c394d73f454b2c0e0fa2ca8339f98825c3d26baf	\\x00800003c4744adb2a1c6700cc48033618ba76d04e841425c063e131594916430310a40faff3f58ff446d374895f87a05818506e3bb7ecd75f88071cd4267405683aa204fe50d85d73320a6e046b652da2fabc4cec4ba72166301d97311adddba5aff9a7a8cf4e0dc02192e41b5b57e44be86affe0980adce188015fa175b7b6f626563b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x58fcdddc993f12265e4d45961f7eac1b64bb7ebf1de0e6281893dc9bc589cc4f55008c904f1b07552fb192d0a7612d006ee8e3a9be46acb326073ece0b8c2101	1632721550000000	1633326350000000	1696398350000000	1791006350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	263
\\x7f2e5716aa8dc28f25e4e46fee1d6cc4d6c634250bec59d882fe602d44aafacdfba1c58c2acd1a702d92f09a945d6c4a69275c0dd8c17eb69036db35ebf8f74e	\\x00800003ca40504a84fbe562de9b9d4a2f31380ab23a15811753a29ec84fe16c530449653665aa3683b5c1e7961be54239c557382df61cec190a5d642ad88594f813bf687dccc27c6dff4afea26965410c83e4ca6e54169c217db262d634cd45bdc9d24f2c44bec36d5afbe385d3c12365fbb6ed404fe41db873543c7f2989dc34d137f7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x06521d593359f28483c79b411f9626b14dd02829fef7b7d8370a93854804125229d96c02508a7473826bca26a075035432189094a3796aee0a2a412c924df206	1624863050000000	1625467850000000	1688539850000000	1783147850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	264
\\x80aa2b29f896b0df52ed98edbd22cdd617573bae926a7927f2901e754abeec8cee4adc1db8faff2fae4f838e73bac45b14d2d6ebe67092d5a641a8b6e33b0266	\\x00800003949ba134ed092370dc7c3e977c48a4198601e698d7070fc79af374ce2e50c79a78f58ad8c0973e4198b7bcf0b18d3034376c7e23ff66d508f88f248e07ceeead88080ac361a10c0d1a6936b0f67bd54c066721232e727e07ea4514051fe18e7ae48c33f99ec6d14bfe92c187a3c12ec2ab611aaebf1c91b5808982ca37b47a71010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4346a1489c1937bc6974c2dba271cbf48dea51cd8d883f9b2eb2651591eaf24b1cdc5c69f88765816a82ee6117c7eec2d68a2076a20c3af7f3b1d49c2782da03	1632117050000000	1632721850000000	1695793850000000	1790401850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	265
\\x810ed5ff6db949793f55cffeb6931cdaedde91a5260d1c53713e592b03738e736b1e159d9eabb9672fc5deb03376164f773db65d2ba951c0e99536433584fb3e	\\x00800003beedc9aaca80ee0e613184a656db070b17b72c12ebd1f0a330cd8febfb98c3a8554219a665954ad9e0de90410aa62db93d7da867ebd125da0766b170e5d861ceb581ca9a2dec11c0fe2336b021f467837362e12fe06930637981c82f4c3d00901e3fea41451f17606e3a8162b3f2a071f6e515c1352a03488a31bcadf969a677010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43930227f93b92358c799f1533ea571a7b9c1c8101762649712794e93c5a27cbb62cca835c6815238ef394006753bf7e80b7ca81456379678f0ad207a3ee8c02	1620027050000000	1620631850000000	1683703850000000	1778311850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	266
\\x83ded7e1c87def45fc34d511170ce3350f869cd991680138c3b03ddf2d1f9ef4c41291031de9bf17794d9b37e83b3f477984f516175b40c87aff9438a3c4fd36	\\x00800003c34b8027906ace5f04b888e655e5b4b76ed929c5e2644ef14fe72f00c096243ee16bd03aed74437af1a7cfb8b50f91cfff485709ca1346df1533d0957e06cb49dfcc863e8a40734f4760b773ec7680ba02c49cefc5516a11f2fdbadb4b2a01d52f1b1401c6ed6b4aee6fc937b7863fe380bf5376fb56efd8fdb7f642f95ce181010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3a3b2d12a76dc2b08743ef9e6c17b60850d1f89cd82d7f34722d00b16260a77a18b77f6b0708c10ff57dd8d610bf2760496099f77534d52894be6a65b3219200	1621840550000000	1622445350000000	1685517350000000	1780125350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	267
\\x8456ad635aa0cf1dd7715611404f68de0fc43f95929dcf6afe231c6f08bc186b155fa4c295ceb6914b644e280a9dcaff507f498ef351643463a2ab31da4c0cc2	\\x00800003c6525df91fbaeb73bc5fe7afd4cc26e03b325d9ae3c28da3ed7a99d44e7cdbc36a3599ee7dadc7f1a093a44670926cc82213306ab080265229fb0306ec917b58d7df1e78fa0a192e604a5b2ee4f439cd181d9d11e5ca92807eca574710821b1b9eccf17d091f46cf6afe6ea72b796bc3e9aebdbf4303bad9e9c253c3f99c0b6f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x85a8cd12961a70944625403a0ba415e0435bdc5fabb50273c65f479d44979ae282a931d3acdbf6e8f19c13a74e6e295cd99d388c90da9a3e4e50c418ae0fa702	1626676550000000	1627281350000000	1690353350000000	1784961350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	268
\\x89bac079e479a7e5968e8cc3f0ea704dd0c6227dba328f989a6b13578a67de59fed984bd61b8ec2f469ac512dd5b4ca1617fb25c1d0e254d4fa3f14ad5e5f6df	\\x00800003c3e69a39a624d8e479a06ece792cff18879bb7a8b7138c5ab6b276af202c8a5ff2a7d76b4ee3157421029cd06e7875c36cfa85f3ed3f3b1fcff3facde20a34ae802503a417b81708b27f5b3c8bb444a151f37d811e2721b71d69c91fde36cb819a305ae6b0837e271799866b46ef10f84ba850c1073f1c91da598d9c5a675199010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdbc5a266f1ed45029bc08a2e4ca98f4980bf19dab60422f3829a82a96490b341f49dec739824e3ba9d9e6ea9fba2112c40853399795426b8e0a2ff8ad5d1d30f	1621840550000000	1622445350000000	1685517350000000	1780125350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	269
\\x8c5e1506d309e7835ce518a4540f054e0457f15702070254a4a23aeed21d6213292f523e599771d76bbdad0f3bd718d36ce56269351a2c5c03d9a0c6eec5936a	\\x00800003eb241a291769b3063a0825604814bd87b56263f178311b216313fef0b8360028741a6fa3b00faeb91c3516c88ccd4b9bc3baed21fe93bd5f596e3aab19f70816fbfa650c55d47659def70344266e997712df5ed17575fe6cc1819b4e34c1e576b7c7141e237f7568a3b51dda9731e18d2adb27b83b238c323cb30ca9b575ad9d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x691ef9dd0ea1b2cbbf570c98b6b9a681fdbecc9482797957eda10d34c0be8cce4fffaa6a7a9dca04b80d1bdae7d80ea3b5ecf88fa5dec408e69adb69fa573301	1614586550000000	1615191350000000	1678263350000000	1772871350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	270
\\x8d122f8e86964ad15ed8776fdbd9ab7f221b7849cb9a069e8864025294d6a04020ff18eecc2dc99b6540002211a9080c7e7bb8e5380680c32117ddd26e5643ba	\\x00800003e8aeac2b6df645adb21f5322d53572e845063e6778937f0b35c6ffb043db7420b18212de94a5dd3044bc6933e461b50dcae6cf49ad9155a60ee7970ae673550d1a42ef5cf023c0ab949b72df759d3501017a65b3fc1cb1e686c9b9cb3b6fd5d504a02aa5b42142316bbaac4d6c4f0574c78c2e0fa8e0608c21c37e48df68a971010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe9151b890d82cf21e9c33b5a05d2e1f9f353da42a98c666ad818935cfa92e50a44ecf4b85917f0f81ed11fb7b73039ae993599ee9c73c13167f226b7f8afb504	1615191050000000	1615795850000000	1678867850000000	1773475850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	271
\\x8dd651c6845c498acb583a20d68d1729ac3711c7417ae000ff660f702bf5a2ae76133217d1a1e768832e17f05171b388a60d4cb001307e80353936c83aa266a2	\\x00800003c06b5d21ee50103636744d49fa794242711ff14794d8f890896a6ec4652d6b3441a1caf2430b3ac0033adbc451fd3b9525419a13475658b042b9ec81b9a5cc0d370fb49732b3d057ea9bab350ed724c64aec5d7e5ad96e88e7f39b86a59e1b1638a28f720efd38688482cc01fbc721d794dd167a78b29a3074fc6206eeee9529010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1065e65c9b225b1831d2226af3c86f3f0420d3fafe7e0b2b478f69078249000a4b3629f48c248cdd41b88294591915124359cf47d0d5cda12802565eb0568e00	1634535050000000	1635139850000000	1698211850000000	1792819850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	272
\\x8f62071600e26ccc193f55f0d79b990103b202344a62682a8f76bfed5eb775d7053aa199b368656c1200dd7c28effc0f64ec202c0b2fc94ecb83d3bf013892ea	\\x00800003e7b7379fae65c6191658334df3519a4fd599c4fc39e16e284659a86c5d682f9f00e5c55e16bec58168df68739959a0a4c10c08a0f74d18f4b847d4c00e19695923c19701ccb18d62effa98bc3fd248a8b2139b665f0d3ec3eb5860fb86a97916ef34adc85442d19d487d63651d4189b5684e62d8d438c64da6f16494f5811aef010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x10dc2c0a37910cc51c97966b44694726c4cedf0a01174c2b646ce578156ba5c87c0884e8890758af1d15410c6728928da429789b91183ac5310df78d90c1af0d	1611564050000000	1612168850000000	1675240850000000	1769848850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	273
\\x8ffaaeb6bd8226a4e567de733c8c8f31dcd7e5a0826e94b9050d34d2928930cc6dd90c7de5f8f86116574a2f49421a08e269be50d73fa6789c2ee5eec22ec1ff	\\x00800003c009b09b6e5782406ae0f0aceab5a258dbcb31b7a7730fd7fbe02884cf43961135ed750f7e326e84adb7213657f2ef6833027de5af396775c87844a0824d4e13af215fa58c7a871a1e179ac7b948d0804af7985f90ce3223aa08510bf25cddf5a2f01f8ff3da4856fe89459ed85c298b93dafe221ff05b5e07dfc93d4dfc61ed010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1a5c501fa1afa95b3545cf0256151034cc44410e6d3595e60f27f275e18a1bcf960f7184429cef28fb898a96c0655b8d9722a5aae8ad70ef8c4f18e7102b7808	1629094550000000	1629699350000000	1692771350000000	1787379350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	274
\\x95e2323fb42a3940755b0bbb3c2de48c7816e63e7e17b92f8c8631ab6cfd5c33361557d4184582c65783448a9d9d5ba94a75556ce17756a8911fcd4a6b3f1b0e	\\x008000039fe8781bddf29136972e825ef2ec4b4aa2ca6f25b2ee3ca3c1caf7c7412d5244165c1bbb255858ea02e6dfc37a15d4bbd7031bde27c05c3375448c9ff34a056a47fcb495590b8d53600a00bf1fac1365c1fb6d5ad07bd2e3d95895e9895785ca9a7ed175b494c37de1e808c15763627c6dfbbab285eaa132067f56d074a025bf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x40397bcd0ac79e7ff0ea91620302b5539fc74642562d95850d939052911110860c9085814ea526e8bf363e72e287f06192cb822d0596747550940a72c34f9701	1629699050000000	1630303850000000	1693375850000000	1787983850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	275
\\x96a222081e0ecb9645600db0b24393c59aa8567dbe170c467a1e3f7c58fb22df9e115a7fbf5afd8d1f4ed74486b22ba0a0b40b16808c6bd6ff041cd2c3d13ea4	\\x00800003e29f40070fd4c13cca4c32b4843ba23905aeb59922ee0a30964b24cf269061ec040d490ea64654d1973f768747535eb1b2e63fcf6a0e77ce8b041b0ae0092ca529c84c254034784c44e8efd9b905499391876b71820c44f8736150c7bbfd3a549d700dc689d7176aa2f07d1680ef8c2dc4b53f0644c1082590de82438521d167010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x46a540f0e8d289d9c8ab36c479e13eecb4b7ab239127526adff72304b10c147391aa49f4c63f5ef3ac78cd921b8b69810ad3c5859da646d99c0b88d43862550f	1620631550000000	1621236350000000	1684308350000000	1778916350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	276
\\x97965d223ec240f6aba94f1eb344060f760257155940f77a28641824ab92e1d9f3d4617ce0a9b3fece8ee03cad8a3d21102dc7bc5f03727cbabd5719a2c085a6	\\x00800003b399f9a0efed4f3a11def132e5fe45a2e622818956ed3a22104319f88ee0f86829234a5589cc88d50843a7b053e73dc114839db5045f02e63b94beee01568e0247b58e7cf1ee2698567d8917b3bf8bf2d9124f45a0b86dbef0781651917b562d4aaf41d1a690c15f53342e913c99d0a281de6682f025af71207b5d1c72d5170d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3842b58ddcf23e5710b2590bcb29c6c068dd797202df86eb907ad51971251dbd61380055e8760f5c9f56e56849932d73edb3e374faf6527bbd359125f4167703	1613982050000000	1614586850000000	1677658850000000	1772266850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	277
\\x9a92472c8300f9d55fc6abb6c88022632a612afb80a2d4be34db46b1aef7092be4881bd1ac6b86ffd9d9c1bf39f54b02b089d66522782d974ef649e4e5b6c57a	\\x00800003ed7d0a9f0b5455c1aceb44100966ba92b0507b24438ba6fab7366a6f6c1d34e30c88e8be28241bc2a004781ec2357fcbc8359e15895d4fd16a86f7c3b8a315594f15a715af0f15a91bacf9194dcd6cad1ca98f58a44372d3f8f58ea52bbf0a109672f94abdd65c4008947fdc2e29f7001b8c770783be9ac1362a88d7c440a637010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcb3ea681b179eec54c55d441d24363b31aabb1223f4427ca4f100843926cc0ab0a4a9e7e4dfe30ce0c54c594df086315a1159942aa6767d8b9d4c3c5df64f806	1632117050000000	1632721850000000	1695793850000000	1790401850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	278
\\x9ad23baefe2854b0d9991e10ad4ed90093bfc1f5b5703f08fda0924f62b3fc55d156afe3e24a0bea82470c857dcca0a040ae930a7735f02c855f2ce4939449fe	\\x00800003e90333710bebf83bc68a2bb395f31b79a125220d4a849b1f13c3018a93a46e3d8da1a68de14071fc3419a2774854b47a921f216928180ab2c73cd7ed275b76998545a509104707bd3216adeb00a29126a5e2b3968039527fc96b27a34e9d386f37e56e3fcee815ea491a9343f3eff2d726c4f8b495073124f3bbd0f3fac70a51010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43129df1770de0a71360cbeb31a71389155d01ccc5313c7c5c44650930e9f58e76eb1cb013ea8682800667c2021d8e62e1556628355b32bb733a56746d8e3903	1635744050000000	1636348850000000	1699420850000000	1794028850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	279
\\x9b6e327359e4721c29681ae5bf220c8d13d915af7a87152bf6dfb55916c77f5d34c193dad0bc1695fe782db80bd5f05af36aad73952e571da94af827440c0d3f	\\x00800003b55d0093542b1d7510c23b006df8362b1ca90c11f2edb671d6dbd5b8091aa785ca2d3f219a648927dfcc9ce45b95078e9bf8cdfc3f9db482830ffb098192c2e3c683132c2bcdf86a499081387889f011bc722f042b10a4a46302b3763a00c6f7c6ee7a78d6d6e0f0542688b98fcc162db971c1f425e717332bb8a856cdc7f0d3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfeccdf39d3a34426e164cc7d53541d110e100f277dd1a7534a53546c7779c5cec50c5f69174ef5fe94ed93ceba0e550277678319f4da7d591e125ac3a007660f	1611564050000000	1612168850000000	1675240850000000	1769848850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	280
\\x9d8ea283167174510e0141feaf14adbc7f94f846d0388d4c4c779eb3d2e158f1fe294e838ec43855c1834a7e90ac1a9dc1633a264e143c46ba3d95370ec7b8d6	\\x00800003b79a03aee8f2c95b6dec5f0026726821d65e568b4e6840d6f46e5abcca00ef03ecdabb09de568c1bc80ab9f96142c97f963748dc197b29fc47892766c4cedf40b00f2d9f02afc9f931a099b6ae848f9acfeb3795046616e6c2c17822ae32d9b187728fea0f7e1286f75c7710ce955cd68b80965e4f42acbdb64e472c239ee8d7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x37985c69c052f4484475e3b747029daa3a4e2cdec5d70215ba70e85d668fa4a978b11926ee0aeae77bf7a203be74c3150f46b56238436a44c52ebc5c5595ba0d	1621236050000000	1621840850000000	1684912850000000	1779520850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	281
\\x9e76a14d2e6a63f712407e38f557d7f552dccd04e53c6163e8dd6aafe79652906fac4c5686faaf23d55e2d6f6eea3a6f9052c8131c82b9a91cebc9d8ccaf261e	\\x00800003c67295b9985cd270225a5feb76829806e533b16f239e04101f7fbe97bc0a2c573961ecbdba5f8869e8e6f872ec39e74daccb7e1e012df483ecb79fd041ee63ab5fadba98b275d14ec67773b46ab3e1f05bf3a9658615aae5f6f8421b6d7525e020258dee548daf086743e59ad30ce6accd4a62f64796f0536ef11a62089dfb9d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x00cf3f1df8113e94287e6fb2bd445d249e738daaba96af636ff7a415523c213da7332b89ce29e24c649dc287f6fb7f1a57db579c60114dbe92e3071e7b2aeb01	1639371050000000	1639975850000000	1703047850000000	1797655850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	282
\\x9fcafa0c9554a1584e25b4ae1536260a07fae9074de94c8610031386af78517959a76aca6a715b32894ada0174e9798a8983a35ad63eeefba31b4a08a3545ddb	\\x00800003ad67008f2577a5e92e095cb02e0d026004dfbe17a39ed8ab29bf75d96f87ee686b88c988f75e872bf3be1f151ee5853984c1c3b5eeeb5b7b7e67b09a60f7710fc4a37f4ddc3c1012aabcca5be3609f0e15b5a94d4ebd828d7b99d06ad1be63e634c4f73c06586cd93a5f626d05d1f4198c0f1085a073bcf62c9613f4b3f81f09010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2eb88bd1bba2f2bde32098fd4ab8c340dfafec45c558992a1fbe17bdc10a5c1fbccee7d08181fd6e4aebb792996f907170db3f4daa150aacb2a959843285130f	1632117050000000	1632721850000000	1695793850000000	1790401850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	283
\\x9f16b8c1f8edc9cbc9dd2664d387bb4a249d373fcdc5bcf9f6ace26edba9576fb60a2d22f50af3e0810123f84f9f78a00e76045423334764433d2e5b7263ceff	\\x00800003c70387ce95e2d0efe41d738d006739489210bcf179c3a73371e71a5da5cf9f401bfe9cdb5d6d27f12dbd207ac296d960bf84a22610ae527f65911fac9607f92c7c11e142dd954dfd7f62a8275444b206f28f622733bfcae61991a95b2a0f44dba845f3b7b3c15faf7c8fdf094b6429869b8c8f7cb47d7ef6337633fd1bb1a105010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0bea8d410cdf5529ec9dbaaeee9e01dc87bb0cea4cad90795b192a32164d6e62f91290a649780e39b213d1550f2b620e89ec6e1ad824a519e469381b14bbe80b	1610959550000000	1611564350000000	1674636350000000	1769244350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	284
\\xa18e64437c74b48fc384c9deac85cbe03dc5a884596d28ded4a5f4bdeee80d1972b539d97c91381ed6c775fb4361bd395b1c68a09c42132d9d993bfed043ff6a	\\x00800003d9903187e09490dbf295b4f0de209178de1f98127d7481c4c7653869dec5a79219da88077a843d310585be4e913de2f58a67b4dcbc3c94975cae80d6c9ed146a1d766c85f1cf86d14d76a0f9c8d37393bc1e6220fc1d411cc39f81b7c8ad8d6b5c9d297453d570923453f390b1481a33570aef69e8d2e322bcbc9de71a42841d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3358c4f966fc677f3f75b96b16cf6e987e97a0f2df7c7ee604b1ab2ab878fcd0b3f12818d40866a7bcea0808d02b894c33b8ac0613eabf81f7df5aa517d1f40c	1639371050000000	1639975850000000	1703047850000000	1797655850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	285
\\xa31a51ac24ce65d9b397fd83b14c03798795591a4f09c6a4dfb890f1c50c22fc287e5f5d70ecc81fdc39329b5c36e252aebbfb0acc5dca82cb75047355d3d50a	\\x00800003b9c2aa601982f3c949fdd12a47971810aeac703a7352643edaf23d93530bb89aee7fc4b60878522db31f7c7f150135694e10dfb6f5cd557cb0719b29934bde3fd80a2c7e6fe062e5af69581029502dc12328907c4096118e09bb685bab4e75548536789139965fca3a9004f0743bca20a2b7e3d6cf0b3b8a0b15257242300a31010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf939f323c48566bfbe6868669ec4fa77cb35e3a4b65d23ec16e0eaa5e7ffc724f9a112aa41454afaae8bae5156884e9f7ab417906aede60b921835f1f1d7a803	1626676550000000	1627281350000000	1690353350000000	1784961350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	286
\\xa7dec82bfb7cd5cb5cff8eb4dd7d8823f76a11fcbeb7e8f64b3b81e7e8bd2cde97632c1fffaabdcfef5ad78dc9bc37ce06673924545c899c61cecabd8d1fdcc9	\\x00800003c073bcfca9d3aa8033f5df1dd6b1608dbe1c18100b9072042ebf4a980c571131b5adb2703e9bfc3fa3a10c70b02e4e2055b1d2fd0b991682316ff6aba4f492327fb4ed464416fd2e3b42f07dee6c20c89afd605eb4cd0fddfeb65dabeb44f1e059b4ef3d7aef84b293e716ebf161dd1b9dd6c77c0f0a166ca3001eca39042225010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4121b491260d24c353db8d6cc542aca4e188c86460ded5723f9a77496d18377c68d51a95570525a2d93aea4119b17506c2aaca6e5028366e38571fdda6502702	1627281050000000	1627885850000000	1690957850000000	1785565850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	287
\\xa8627e7db5a42dc8577aa8aeadc02a2436d31c61f7654e8088adae0526d955bd2537731ed330dc29e8b0e6df7aeb36bd7a5b401ebbe8db2fc0e0a1d516ed6a13	\\x00800003b20a3a1efa97934674a1177697b7073d2392dc32413527d8884fe129259371c2d280247b410446744746ba6cad686364cdc4bfed7141900128a5a169ea2f03f2250fd0dc1643ed56e22003f980a7815aced287b5d2957b99dee60fda965053382cb6456f945a70175b7d5264edbc34d198bc436a92f0a6067d1f6d46bf719c5b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6770cbc8bd73482b3f526f8e4a2a754beedb0b6cea1f079fc889a907a4eb4d58106bfc3236006c61a1939c40e7b6d3b03a62db88e4ed9236f1f7ae481b8bf40a	1613982050000000	1614586850000000	1677658850000000	1772266850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	288
\\xaa06640ca84a5616bf0379697cf64e1df28d7c738f14e8b9abc5862fe9758fedbb6903dfe21ba30cc16a01a6fd66268871c7cb9d53c7c8c65758ef71d170e902	\\x00800003bb2c2405c57fbcfff4fd866e11ae6541a889d8a01b7047d4fa88945911fce0400f6be76f084d05f562a89832a04e94ad62517be099c367b71b645e63847d2c2f6ce604b8829b30b170fc28a9f331a28790decf674ecc7184e591ab41571c3f82d045d98b00923547e784684bb2329358b527c4830149aea3efd9b914c1849643010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9e9c268c3b5305767d1c5d62a4623257e7a6ff002187f230806359f74d4d5a1fda4f99097f9a52213cfe79f8840768752356e34ac89f1010fb06b95d39ba1909	1615191050000000	1615795850000000	1678867850000000	1773475850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	289
\\xacb22370d2dcb77fdb381460d801c15b99fb2832c059306e9ea33ba5b55e7fcc13f17c9aaa8bf72ddb682d807f49a52db3f4b25cae39d2268d15ee0c9a241b8b	\\x00800003b4e2a77dbfcf4cd21eaf2ff32d10bfd37b7fd9e6b9db3eb297a6bf1a3536e2a58c248b9e24d63be499c274484a0a369965569a1d40bec9a16a4997e5b57f992d69f1886f9a98316789e4dccae516533b78d089da0c9283e5106c299dbe4c5cca83cf9b1c71c61446cbf4cdee2d6b71db02c7aa6b845bf7df282cc5bc08fbf157010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x783f455d3e30c2610b8f16193fa119972332edf53d62a076c7ca1d018831144a1ef00f9cabff830be517d47ebd6164b022bf8f023d7450002a9559d52c7b2802	1610355050000000	1610959850000000	1674031850000000	1768639850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	290
\\xaea244a52b6891fb09eeb7a7e21dbeb28ea01a9e6889250f6b33caea4f4fc5dd4127cb921f0a8ada07a26b6f2089236bda0809b576e3aaf01f5f5946eea018f8	\\x00800003ea82122ca4d71f54df5b3c667db9f906d3b658c6fbbde0bf385644c5a5a04c157bd19dff41eab1aad07f6731dbbc07710e139514041238fe3f1336906109b3284c7e13ca3c022c7d19696233e7e5650a0f8c117ccdbf020e76bb30ab2d27cb888b4ed28b253684ed5ddf4431703f4e6f5f74e1b5d9879ad3295979d11b2bdc21010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x9bd6a3bdf6f806f768dfd75b8ff0b6996a6ac8c2efc7cb3193336709c1f7b31abddfafb5f965e4371324d9ba71f2f33d43f6263ca874f3a1d8f964a92030d207	1636953050000000	1637557850000000	1700629850000000	1795237850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	291
\\xb05e55040a08539569f300ebcffcbfde8b2e8217c6939beafedace1d859cdd4c19c6d6be3cb29a57dc09805b4a691ed97d0304bae6b522b293603a38eacfabc1	\\x00800003bd31db6b504180ffb9c6acd0b689b15a6da2ee5246dc64449d5a1b2a44c48bd748c2f4da394ef543f9cbd3f4e36a2d6651a20d4f1f8dc92ba829d7d87bbb966303604295e15d71f63b04230ef312329dc325994c1704f36cd240ddde5e7081e74bb0f22b9bf2a91bd5ba94480abea5ed6b1832f099cfeca9a1be34ba15f9d755010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x967881f1c9d686599859452c1791e3814bf235444c092ec9d163d8a186acc31491c0ebea222937aa500adf0d70173b014ea72059ac37e7f45249cb7129aec004	1613982050000000	1614586850000000	1677658850000000	1772266850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	292
\\xb7464d91570ef340e0ad4a6631be6eb99fbea6ebc2706cb5029843188b57399f985a5a991ef5ec3faeede5aaadea24905cf1970ac6cde219426b1b5b6a50d95f	\\x00800003e62bb7d40ad22062ef06c4ea211df07b69d4864442b44a149007d1fb4757fd1acd0ec4735b24af64bb7f386da5a401a5b2a4740340195463f455afc84033bbf48212aa28f9e8b90c20f51b7b752aedef086f5e85d32f5b6aa13bffbe8cdb57ade70f6f06f5a0466e7c2900b82e07fba18ca06de3adf2de2734d55db0a9746c0d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x53e34e965984034bbba333a69ba5d800589531c35e29f5b9afc82930689fff1dfdff1e5dc34163358ed9f7c5fcaaa052ba425e1d406d6d270eea464466ea7108	1612168550000000	1612773350000000	1675845350000000	1770453350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	293
\\xb84ab0e2f3ac07b9b460fe9b5f0e8423c4dc0ca08b40e9f79512e60c0dfa38464362fc38d6528006a762473ef751a04e5f358a55ad52b43f31e7191283714b72	\\x008000039a64a6347d346af067051224afba1e935a54e43eecfc4c0be7c08566cb0ed3e56065166701ce7d62d15d68e5b3f8f37834091bd543768d7dc942e7f2dbea09830ec84c7c26ccf2374557d9417d2d7b591c1d12e477e7658c9ce7310a8b3abb764ad72c51907dff0604544d21ce4edf034dff0c8efca422a42309b5926419c2b7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd6152259c9d418de46b984539a211ad9d4901d23a915f3740e5b418d064093b92fb12baff3408c50ce1f1d5a499cc802b96ccefac6b2fd28e5df154827aa4908	1640580050000000	1641184850000000	1704256850000000	1798864850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	294
\\xb9468dbb1b68811e7d51c155b4cebf60fe2062206d223e082ae24cfb6daa127f41e848400267df54f487628bc43f7da1032c3b86fb8fcec0253766f765d8f29f	\\x00800003e1dd72afa52ce682540ed67c0f9ac117d389cf454575ef776088ea33ed5f539225448a816a299f7ee9a90869be89c109f6ac2ff5ed4b373620ba01f8f99dd8f86d210292222b0d5c629193dd2d1e00d05bb2186efbaa909ff99891ec985473ed4ba444627b696da408130a158ac523793e7bf0296b1bda2e21e69616ab5fd5d1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x38b2e62bf3f56ad1e34f59c4e5b7adbd120fcd376b4e0a0f35577b8a7712bed8303dc25ea4bca02bfb288e943d88682a29c610c361fb28c00961753e95516302	1630908050000000	1631512850000000	1694584850000000	1789192850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	295
\\xb9123dea437b282702ebd781d8e813ace07a5f40b172e57c2941d0324b144545d861bebbd5907c83f0a07b497eb29b19eac88f3841b53e7664f90566fc39536d	\\x00800003bb29d2056cf113a8c23fe49e0fe8d0ce950714326726e4473fcbb197377dcc3008a1c2fab34de1c984142b91f906ae79702d5c4cef939c3ef49a662f08a15f3706377fb49052bcf43722a4ef6d964939b891308590eeaeaeabaeeba3d83e81e6f5d33a6e97e237532b63a8bbffe4edfdfb90d834fab4fed327be8d1e9ab00cdf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x981910009d8d1d2b3fed23693b7c9f2e058330395b691db22de826e6d040b4acf7abdf819fa122cd6563a9f66608e9b3a12ed54785e35dd3cacaecd05a512b07	1617004550000000	1617609350000000	1680681350000000	1775289350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	296
\\xbd067d6e9b881a382090659ba6a74e971d80e7e9f2191101cd90d80e4ea2ed50eb95d45d75ef765e42686e85fc717e5b29bba438e97cac516d60e522d4c6bb1d	\\x00800003cd18bfe4c280e9f8278e087afb7c0fa6b04f9a689e8063fddf4786227a5d9eef3b2b481020fba980865f8f0924e1e0b585332ccf942f6d5bd6dfe961f52f825c0cfa4adfb17bfaa8ca5c16469543c50029965524aa8107c42e7b57ae38e3b938f4bb1bc1d22825a31ce5bf360b227b258e99452bbac22b58994728a5bae72b07010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdfc0ede993c045be3d6bf50ed8576162bc7632ef94afcc4f9a200bdeb1a224109bc705e9379cccaefb9c7b740318dac17eee1d7aaaaa394dc1cb58c7e8713903	1617609050000000	1618213850000000	1681285850000000	1775893850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	297
\\xc08e775f2abb741c46e4f4856d1954ca8b1a72fc27eb306243b2bb5377e67f1e00b9fb157b7e97fa5c7a224ccedc3fbf562ba6e57590600920ba83c895fd5b31	\\x00800003e99552a9789523ff8f80e6675ec11dded31cfb8fb8076ebd1a970c3e0e7b56472573b545e56858f77fba68d650c483a9ea5a2fcf8a43a7f154761673352898c92e06c7ba3db3505676ba8a4a89e8f95df8c164b3ee0201ddd41b7587841ab87b809bc56ca10bd0e0702297121ea7b9ba6614ed04efa026288e42959fb4c7f30d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x11beda27e96272b87ca68194b654471b6a5dd742d911a6f6f63ee8c8e0904c7552f28c4522e1d4a83b5a937ab07107a0e1a6938943bcb1140d1c61f8d958df0f	1632117050000000	1632721850000000	1695793850000000	1790401850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	298
\\xc0d634be0173efcede11fc9426e9c7e90e9eadb84e78209bee82f301e39226d4989addd494ffddfb23c160fb2694cbd8af2e3f195c8dadf0149663bd216c6c41	\\x00800003c73db2d689d6fb851bf4ebe9026a966c477ec3261ae4bc6452c4bd272bc4b2e2ced34075c998acf5b44e4b06c9eeb804adce9cb8a4e7d0e390455159ff56f2dd5285cb16c46a5ae9d62c06c31742fe642664e2d50b50e859cf6f9e71ade372bd4ad555b5ec38b457906734112f8a08f1ef3a1105f65deed38c20a94afdf9544d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x291fef1980c565b3ae669a47a049fb2279baf227f29b2167e1addf0f7f0ea1cd164384f153663b8fc8dfb476c1f2fa88edb5c45495d30af19b3dab0eadb3b20d	1636348550000000	1636953350000000	1700025350000000	1794633350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	299
\\xc68e4b6044ed48076e0feebf596c8e7a91d364efb0962781826399a87c4133a9c2ff4e66766488b35f8758dd3e5b6b5fdb502caeaaef141e002e21e6a5c0bf09	\\x00800003bc4689d5061424d329ba737f07f0c143da1fb29337f9c9e0ac021d07018fdcdf44d25942d4d5aab79fb038190307f60340aa643f1a0f64afa2bd098ac583afd8bb80f7fdbe248e6945ac9b84c63116bed43ba27933321d964e645e3816e3e2707bb0c9d48e7bb4fd0c232aaa6cc84668d890b70961fe8624e7cdc07d4d7659e9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xed341a74e8f479c21ae19c16a9b618a24eb3734d98127960ef153e9f5fef5d503626287cf818b6c831c85ee9263afa9353e279a11aeef9bf70d3431bbdcf1003	1621840550000000	1622445350000000	1685517350000000	1780125350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	300
\\xc70e6b95888ab17c017dc89d99c0537375f00271da938f78ed09509d1859bbb1e0e282f0aab53719527bb20f6ee0f8ddd108922e386a7e3b4e68cbfe063ffb10	\\x00800003e696850262880b3faadf0153b3c55424fdd40c21c24e3adeb9f700f1731b168c00fd73ac5e360b0566b673a928638957bd811851d7f4b9dc4a331ca956f5deeebe7ea572eb221fb2c355e5d3205a077802bbd7821a9d45462ab2a12bde5d49912386116d58df39cc549036889e67fc4b2016189d9e3d35488e8da7d9fa1fc545010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x478c558cc6b9e91238c1c4903c1b44e2751c1d3884eb60fea59d9675b3829c69e685155c00cd6ddab09f0a8c418516da0df2860d5d44354a893b415739e85e08	1625467550000000	1626072350000000	1689144350000000	1783752350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	301
\\xc7ae21ad15197e553541ff0aa3cb853681921935c784fd9a9ac7322cb7ac141d0e85278ab6db510f819d20b14f049c31ba44035dab83265d888f63b0fe3fc55d	\\x00800003ce0f44c4116a6657fdc0c6b2147beb805a4dd3f20885bdbe03e194aabfe9e5aa5f8190ef6c7a6373c54c2052c6762d1856bb39ad8863409ecf391b4c07ca37813b2b9be54449a18a453bdaba255e4676029e7626df755243100b47922fd74783605bb23a30db3f9cef31435514fbe9a45a0f460b1cba404ad8f30cb3df509c5d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2e08590d95494f7b661ba8832228f9ef049df746983a7386ef40a5a33b835b3c8ed150c424a95347acdc1395ff91b3cdd440b847b1dfd4df59788c6545ad890d	1621840550000000	1622445350000000	1685517350000000	1780125350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	302
\\xca462e1d762dfc94fba9b118f6e1e2be3f2d920d3179128014e9c0d046869d185a8b186400e5c963dc998417daf633f50c63f1fc97d80a91882b50368d12403d	\\x00800003c0899ee7b60ab8d32dcdd5ef619be41013f9b328f18f8f6708f65b51b7276f09050c5bd9a01258501754489a40fb1e9cb9df92fa133d6aaa993ac2ac0d85ea450a4a2170e082064abc01fac4317df5c3771f948b1480ed7c8f20f348e9b4a1c6b5a36723145e51e70d374e090bb3f188b08fff1a93d4d96ef37aa65081cab053010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x041717e5247369595d02146503f19ff185f66df146a6b6a61c6343039913f5c8b620aec683ddd76885055b96721bf2cafb1fc4f4856b2970428eff3075484a05	1613377550000000	1613982350000000	1677054350000000	1771662350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	303
\\xd19a92a2e42180ed29e17948ad13a0f0cc17a7b3b625c13f6f5c502bb05c4a03fe68278c5be9117410d8fa1f492e927db7b377fc3191b2392a4c6f4ca4122abd	\\x00800003e5966c7e8706f1b7dd31aceed1bf28bc161b8923a02563b9b48e6b7b40d8c0898e540b2aaf6d558d557e70b795c98dccdb5758657d6adf5321a8bd2bcf292de451feb91a5048c56ebcc7e0e9a51792dbc369eec3b26ef70bf888010e51df3671974dbd6245802569eba5351aa43e939d8e66540bde480c57d3c9b8d8afed3a2d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5213b78bd031024fe9ff6ce81ab8acc9501cd5a5cc087201389cd73789bfb505f9956f80be7bbb20b8775f1587e297ee3aed5f3e087e1f996f762bbbdc1e3108	1640580050000000	1641184850000000	1704256850000000	1798864850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	304
\\xd4ba800cbea1b11ce05cf0a3b6a0290fb196a25428bad66ecc6a7b1273c02d39003b5c4019ab50a039e0e536c4dfe78df9bd1dcd9f7b2189c2b72c02c62edb11	\\x00800003f1dd7b1afd1d295e5a9ff09d93c390dd65037f935129b41798452c71596d35e36e3db34aa674a66709b25102f6cc9181f0b974d5e45ff0d1b3121a8432d3ec6191affe3b9080d7c79dee8116addb1a3e31ed19941e628cac1389d17ee20bc1409aa8e5443f9ca47b18a9343113adaa9c0486d494c24b8491255adfdf7bdd5acb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x02eeed3d4c17aef57c9781e71185c8669a1450855d1e06cb04c8b87c71dbd8efafa16c4a7cd89deeca8af89f585fd2e2f88eabfe2e19b655ac369304ce36ef08	1640580050000000	1641184850000000	1704256850000000	1798864850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	305
\\xd7ee65c247842e5d9eea90cb35d3aea4297cf2b4e8666f8dca6061c653d42b9058ff68e026b6bf679f6a3394a1b75c9ec4371e83a059b3df4ebfdefbbe5a7c31	\\x00800003c2af753cadc14ffa7ab956ac64669e91fe225e5d2c0cb39197953224715461f80ea285f4b177203bf5e5ddebae15e1fb31589e9fa833baa19f2b1a6af1c50b9c2bc8c2e4b3170e7fae2d96d56227b8d822075bf6b344ccaf8849065dbe508b4be1805bd9b323a036391835eedf9c4a9c466214afb8ee0ac06396338c21ec44a3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x414a8de6232b55fdd0e56399d9ea4a9fddf1e2834a20cbdf833f382135528570f00ebaaa561f622c38ac312f3090255705f9da6f038947eb033edc7e309fd806	1624258550000000	1624863350000000	1687935350000000	1782543350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	306
\\xdb2a8239a00e68dfa11d7b06bbb8da824051a6e26cace4d464bf88911a3f59325983a3c8b130f944be25604c10e59648b3403c95b4f5cae302683331391127b7	\\x00800003a446740ca15e1f0e4065993f0c072463598ded75840109fdb7dcf3dc50eb734114c88f955987bc47b9a9477d4c83fbe9efd8829ef8f84d26274b2c9e74275b4afd355f138d4e01ac9e77e7d0fb18d209043c9143fdee13b89afe592a0c2e110374f7fb811547ffe9b50eb6077f20e8d02f30133c23d00f9bb562ee91adc49707010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x07399831b39baa4108163508bd5181cb46d26bffa5956d1a96245ffdcace195576cbc0bfc710146f7f647c8c0a8d19bf5bb1df2503c95ac922ea78cc8f2b7603	1633326050000000	1633930850000000	1697002850000000	1791610850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	307
\\xdb8e2090c6da48fe684c02499ba5f32b4a6229074c6493c80cf45f8823280274e3c60afda122eb8a0238acf59d189deba20dd92129571742fded4b996bc70c65	\\x00800003cb6d38ab2f81204a16235155c1e9cae4c6bef363d051c769314cf76e9ae21134210705b137442f632beb9956f3917c65e68fa46b408174b036f1318c250082d17eec580b8258d25674fcb910eb512d811cc6a4790dff1846cae9bedcc8fbfeecc2babc805fb21580e74971b2b99b53b8fa7c6840af0f70a073c1caaace2b7b35010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc7f63828290b7fb539ea6aa93b3e114fe24b8233504cab071cddac8e68ac22d4a77b5807231690c6e13100ed25cfecd6f1e5aae9b35cead994b231cf4f302b01	1629699050000000	1630303850000000	1693375850000000	1787983850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	308
\\xdc367e62623dfe4e91aab2e5c67f4dd147fac0a370a4c716133df8afe4cc3fc4e04194bc70cdd330813de1c4a9b3d2af6f5facb3e1ebd9ba7f70aa468f5f8819	\\x00800003ce27879d8d82c9fb9cfa407edc5c39204198d8d3f4c3238ca5a119a938648b127834cf6b94d5046658ebde91e18a461542863b8504786d74ae62782dc9203668ef388705b1cf620a56d9a470c2921f69fe33964c6ddb36c2c32323c7b484ae803f9a08619cf4bb98c836c5ba02bb9214a194489027db9c99adfe72e06feb1c43010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe6a49e0de23e3c4fe85f4d512c2e53b257a44cd8e4d3c42c5d13fcd3b501c5e3f8d99faaabf93cb7e3fd2279fc4eb5b2057d15454a0a03d7b6bc939feb835b01	1632721550000000	1633326350000000	1696398350000000	1791006350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	309
\\xe4f6dc8182ce3e4a244b9de1362901cf89b69f82442c7e71695273315bdaeb508ae47052ebc3dde76454bca7b8bff2f2594867dd4aaaa04eda139bfbcebb244f	\\x00800003a84839019342e119f8f82d6f383719cbdd5b548c865cca0fd41ee99d3e54c2d8611d15165ea6b69c789f45b9d68e0726384c336709eeeb6ff8a91d4a0c4f747598650ab246e122af87fc76c4427c30599b263158a062e194c2bec62557fb341205f14072ed333c26b7cd1cc51132a20bfbe008029506645067a48b87c564a289010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x310fb9f3096a781b690c7ce1caa47394433f4de9338390e7a16f5369129a1132d918dedf83b1953d81dc9905482b065d40c3d7bfa01e213729e2195b67934a02	1635744050000000	1636348850000000	1699420850000000	1794028850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	310
\\xe65a6f9d40e5d0e870b4e21cf777ff05d630a21c65809afc895a9b019201fb85f55c002f8ca19e6e1907234fe67cac069fba93e964c6146d4479d62d8e57295a	\\x00800003b1910235fcc3b506f92074ba2a012234b2c83866aafbcff99c2693c7d47086c66c1976a8c948375b328c7464b2a4cffa1c4a6e4df301a0dd2a36bafcc7c3dec0eafafd9c033284286e3181bea423489c88e6a3d1dfdc33377d32f80af00149bbb41cf392a2ca038ecd92bf928ed4c9ebd5588fc01e15c54ca5806d2de2f50479010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3d104fc600efdcda8cf9a8a53942d5c64d216b0f3ea02fac4e4f24098cd3e46ce42bc147d2b322e649c7fda397602659974d705ba09ac3e641941987067c5a0f	1618818050000000	1619422850000000	1682494850000000	1777102850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	311
\\xec82cd26f2c3abd32ba1524de0be5b7564db220e36ba065c18f3a09dd764ac73e894eb239854d4c7cb82025b61b7d83d60ad87c3cbe7498d2346fdb94eeb8f62	\\x0080000399d817d94157a83e97748c2dd33e8b65eefbaa9f238266997a6696fd047c172951a9fb120dc2058dad6b774d62768d6bc3beb0b587c7f70848bb2b92e9ff11926a28c8d3e8cfd73557401b9fadf5f7929e40388eb2ef1f46c6a856983d87be41917cd878fd239fff95cc8d59ec1b55e69b91c04e435d30d0e7c5b349dd7c17b3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x33a7bdc3fa9ae7556ea958f7e57efc5d19686a9b050b583652c97fc0866b0e4a6a6ce65ed9f6dfd8418619b12dfb9d78300dd843374665b3552b7dde9819b709	1618213550000000	1618818350000000	1681890350000000	1776498350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	312
\\xec5a34731806f371de4f1f07da42a6067600526c88fb40e5fafdb63f9bf96c0ddf9127d7c308ea4ca4cdc3615255dddc8a2536f3e6e3361fe49644ba9783e24b	\\x00800003f34bf6bcf62d4201be0b6a28c5983eeb4039e62b2f432a35624d7f67430c9eb03f556d91c18655a4f73468161566479443f8d788fa81ab23ecd14c8e5ce90a9b8ee50bb8d37c6a3d2e9f597707fae70348b22de64b97239a24fe4fb5cebd140e64fca33f31a1594bfb549232b07092f2ca250408412704ea6a26d2331a732fd7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3c6cdab62c56305d59dc8e2768175e831f7e68064180fed80220ecfbc3be859df489454cff02f5f4948964f0ac1e4fe87d3ea6549002b783b63e2e145905bd06	1615795550000000	1616400350000000	1679472350000000	1774080350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	313
\\xec6ad15ce879dd8363c5fb0bef2514de0889264b0c60f801a0201d8c795e4544345fb44ce51fe24d3b48d2b323dc813ebd88484eb16a9980934bb3e5b0d2955b	\\x00800003bf3299e69efc73343ae88492ba667ecc4fc4eecf0614769e1d6cf32454444482a6a4c4a8e8c88aff0d8b297054f965c7564487694879befd84bf2ba9804e3483f1af1fd611f48f49b7284c7003bbc62dcbf09d1f3208d18cd76fc9cf6609e897869f3109ead84221c1cd2c8867bbd6b34d3b932eaedfb6a8af5ccb5137b5bffd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfbbaeebda28d6d15e0f0b9b5e7e59ac4d5a3e05ca126df31530b4df34be70c51b7df30376451ffc9281ccdc6b8591f7a962e5cfd7c9b6cc76d9cf4ac2ed8c005	1637557550000000	1638162350000000	1701234350000000	1795842350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	314
\\xeddea912ff595990036db1035601e58302d814f7ac01291d4586111c1aecfefcf71deb7cd1aa100db903b10ea2b9595b1bccb336cc7132b8b191165fc2ea1e70	\\x00800003a770d654919848f475c05b4f98db51db3d7ba63024d6dc58bd5e75adb34d7b42d1babb2672d6dd867ed05752b22def666ac94da6d9f2ace21788624743c73791048005556b2f4ecb9ffc3aced0aa3e982d442a958b4d0edca61f821b6be223d8c915a84651d0ab74a812cdc8fbcec6a27277e087f6db63552bd52bf44c49842b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4af6e39ffcd2edb31df9f97a805d43601d50b3a7a409f77df831757c11c76a65519c7a5fd6570341740028b5da613b0a704f59673e2e7a65800f7c5fb6b2da04	1630303550000000	1630908350000000	1693980350000000	1788588350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	315
\\xee0ab709db16c62250947d817a2173b40b12d3bb8531f5037ddc9462b3a1d4df358bbed14aea9ed669eaea29b73ce172a3a89b3dffa6f45b514c5a3fad6e2c7d	\\x00800003de07723d06da563e36fd68395532a44df67081cc9bcfa43f87333cbffdd6207430e88d628cd2894bf5fb2a5d409bc3f2a24c544ce38b35ce26c53dd8a5c8dfd5a327ba39e0997532253c516cda550d6beef2df975b3e0bbd6d22b1f36336b1e29abb7de60746b87669ec587fd3288ff8bf3e0f64b72d1bd937cac68c84c5539d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3980ff0db208040750fccfc548719ff15b7857c7aab872a72aa9df3de8d39ee7cae0a08b0105603e2efce11818648bc8ee1bd3a9516b7a92eaccbf74d87e8305	1639371050000000	1639975850000000	1703047850000000	1797655850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	316
\\xf0ded23355a402e4212ec84028899dafaf4747c61b9e47bf8bdfe481f85e808dcb0ca555ffab2e95bd2611d1950e8c5f0d73b7c6667b6974e148dc3aa1ba6629	\\x00800003b754dfb9a5519727bbf02418e7ffae96c2b0857e3713224dff7bfd30e3f71ad06b82ec83b39d2cbc23392ba22b83d04a9024ab462f8764f6ef1522af7596444ee9747b9022b1278a8f4ff068c040d63638f987c1ba9ede0be95f186d98c6475535e48641b9bfa609bf2e53372c806c5bb9089edbe0c505be104863ee9eda9fa7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x16391995ebabe0ba9443c24d53ef407a4661c660f0e4fa1708fdfcd5e59e13f62f8c6dfde7ae13746135f6ee8e41f961efd69eaa3afe219b1ae499383dbf3404	1620631550000000	1621236350000000	1684308350000000	1778916350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	317
\\xf21a3e48ad130530e893eec636f1afa36551288dfaa1105978d0293d4df26c6580c6226ead6c48c784260f9e8bd3f2cc50d84d34a6f0e532b5ee0164b0b54967	\\x00800003c6f60948016f89326d27dd3e401094e47abdaf07b47cf1cfca00bb088c5a67d2f9c293bc6c83bf1bd697e07db99648c888b193d08a0c77d1d887948f3cd9431f6ca9aa069d5788fb1d8a7000a9c2a740e8bbabcc8817614c05357e028551a34dd987ba730ca289e9eab5e06626493cda6794a5427b174b015f04a69ad1f6d0f5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3b942f14ad7ecf139df042b948117e5580c742d24ce1d71938a19f960caaf36a5ff50ca80f684b388ec216fdabd05d8d5c0635b8b8fab0f734b6e3b8b90bc008	1627885550000000	1628490350000000	1691562350000000	1786170350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	318
\\xf282068931710587698fea48f9aa2f0bb85248f26d78ea464e39eb3a4de6fc8464f7341fee2423081943dd5c310d75ff2c7c0d3084c47aa636b887a13c96c047	\\x00800003ce8a30c0b9175998b779b77568068b7691153870801ee59cec28f05d30628781b30e44cf16209e7dc038e0b64d8ea4e770917a9d3dac596f9d9a6a462ebc227108e4fe25af98027104b225ef1f16bbf4b0dce5dd21993071d4b3b92574bbfd1f7ae715ce2d772593fa9543b3399c873a06d5f8ee7b09a897d1ccc6575ca52f29010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf2e72f49001ab0ce7cdda5d898bb6473e10683e14b4d1dc08dafceb06e9aebb825726ba53dc3bea6ff0790ef11c21f1a2123e1d4d44cf9c263df713db831db02	1630908050000000	1631512850000000	1694584850000000	1789192850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	319
\\xf20215b27be2c05fadcb0a385991d797b8aa9c2f4f863ff9888696a793b2ff106f4b6d567295e0ada90ce614b39edfb2dd4f676cf832c4442dbb1d4806743e0a	\\x00800003c3106502a1ce7495041c1e6700e7286c2ca18d0ceb4190e91eb1effa51e1400d1de542a9de3ce0caae589bee7612045feaefeb9787b806f399749145109edee4b2d9dbecf6cc0ae057a05861994d7e4714d1463275c024bfabf3fd818cd32fc9d12ef980421b79f11705a101c42ad12f73b03e34491522b66182651980722d95010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcda7983e40d6bdd4c3263456f80df2364c23b25dba52cb0d38de717e06ee4fa226f8724f1d7b10cddc8a9af2092c862f8a413c41744e16dd1a9274763b834e0a	1629094550000000	1629699350000000	1692771350000000	1787379350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	320
\\xf2c2b1af2b7ddd718ce742b8b7c94f1c48225434b5bea0564b81e733af77e113b726e2e93cf17971abf192ae9d427308673da20c52332e1286722b359df0aab4	\\x00800003d358eede540c667082d2e12dc52ea91880ca11b4e771517517235c8cdd69c948e563dd44b619fbf192382c21b3dd086d5b168ed6d1ef4710c0813a15eb6be8526b235e531a26390eacea96bd1ec3204f54b59285f9ce06216d3632062488ab260eb5d62170030223904f68d365ef4d441dcc301df08f5ea09c3f69fa6482d21b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1f9f548a9ab8b6fb1a7a9abff5f8bb522f1f6dd293c85904a80e5d750d1f0a9b3fdc0871ec316eff06ac3c2032b34841e48a6f0359b08d3f4fb8d24da3f6840d	1617004550000000	1617609350000000	1680681350000000	1775289350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	321
\\x028faf614e3332311b457d3ce58a9ccd8f6ca8c0d6851d53e8ca05cfd22be3cd35c87170bb1dc980f7072fd01d0c603af7393f5f63a4fe931047dd2b2c3e216a	\\x00800003c6c3836fc79cfb4391eb77d031bcdd08e622d8d1b2ede33d6e825f6d28aecf5358ae5e608b2cabda795b665f1c880e24ac4d7a8be8bbd3ff502ba379e64fdb00491459b0e5427acfafbb3ecdf794f35bbf4ef1f339e7b5eb8d4dbc9cd328595c59bd8757ca2e62721e4aa3ab4a7c4ac2e342b3107b61efede6bdd6db1258d729010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xea4416f635663f3d84880fbf36efcad522a577d04c6b45f9e0e3b8f9f6a96b975dd67546c85196607d5c0093a01f22935561703bbe987e4373394eafa64b1405	1638162050000000	1638766850000000	1701838850000000	1796446850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	322
\\x02c3d89a926d638fded69ecff5ce3577cdd73d6f6dda9eebad82c04153ba18d5f6b40768de077a588f4f767bb8b6eaf870088d473c53d921924960c10dba7c62	\\x00800003b96870677763a3964e8415b09e665a526c56095b7e9111c735252ce3fd0e5a4830a9c01e5f95a4ad97a723afacae14a02a8234503dd5e3fca439603658b3bccd742f65bb1a33654178cc3bd575b1d4017a526d22201fb78c25153ddf886f57b6287a7592963f5bd0a3bc6242818845015f62ca95449a433ce09271cc0c8eb831010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2cdca5b783232daaceece8a324758cc029d9c5baaa94e9223699ae7ced65b818d722cd23b5e4b84b63f00a97c664ebaa0e5a8f53f53d420d27ef0c3691c8810d	1638766550000000	1639371350000000	1702443350000000	1797051350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	323
\\x02035a7e422b25e81edb9683c44dcfca6a1c0e1afad34f06f9e9d1ac002c90549e6da55816031cf08f83619d17ec486bcc01bdce85bd99ae8b784c1b73a6e232	\\x00800003ddcd3236fa84b0b0be6eaa317e59ad5ebeef2f3db993f96975069b1c2f48e32214a3b21fb3a88abffcdd8dc55d201a72c592424f5918b3669ff6b04732819201b35afd5d452790fddbfd61dd735bf96c96b921c40e68567905df6bba9b70b6c89650e4b38781ed88369eb76a731ef1676ecc2512cc77c7775be0ef48e96dbb25010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa46e2b7911dd02fa03d72e930e3dbf4b26bc799e1000bd95a64cc998d5c4ca3e21c6b94ec28b6eabe6fa843a6a3d3f1fe4b40adcf53c0c7ddc69e277ed73d90f	1626072050000000	1626676850000000	1689748850000000	1784356850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	324
\\x05c35b55597ac842c1460380afd3f748fb5dd68c6a4c36a8287d74f79674cf2448e2900ca0c0d959cbf1ec341e591bc03e5fed39ee61c733abd841c605e5cfc8	\\x00800003cab48e902961b644b591115945483f1eb90cc7e50d0788d5ddfc27573112b42485c52981e9125a7c112072ded3a6a44b94dc7d39d8c2b61336cb676a5b042d24926d50b3d566c40cda52b1f42f03c180d67f28eefcb09bc0d0421a62663b94e0013f4fe8c838bba712163a54caf4479a57112d7b3c869c1291aa442dff5d7525010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x818bbd1c7d5cd214819e6434acd2904f67ff28b957c5ea136350e46e91147510d7770b5041eacd6ca0ff22aa34113a8f92668593d323bfa2fc9823b58e59f20e	1633326050000000	1633930850000000	1697002850000000	1791610850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	325
\\x0d2fca5e03100c23ef97a0c90590ae819689bfc1e245d28d45804872b0fe6e006d17516d7d2399c8efe428f2b5e95a7c63feddba9694a19138315e5773261849	\\x00800003bf64b86ff47e2c25f8758f00831f24b017228b6718a5b82778092b7f3b36fc26f60d6ccfdb376997abfe9e31954807ddb9a0fe761dc23934b4b508569cff17d1fe0717e703bd529c840b5a81614a37dff942554edc2ce0b39e46a1085c76357fbaca7c2acd8698a57ad79df6da51bfaeafbcbbf53f1ec438813c76882ae3f8b7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xfbf216b742f0b900cb2afed830075da06052dda11714eabdb963f4dcd4e80e4b978495cfe7d731137995d2b25ea84918f802ebbbfbb965ac1ae9cde138ee8300	1630303550000000	1630908350000000	1693980350000000	1788588350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	326
\\x0e0f9bbe7ed022bdaa2eaa6d9837a484a9f67dc9c2fb4dd59c2f5d514a54d8808a5f41e421f9c2f66eccd8d3432e1b0af4f51c9cf05707febad94278ef9f83c1	\\x00800003cc0d5c5a60a9bfb5afb1d0606bc3eeba348cd60a3c6117ac0d512fce9ee559b72944e7cc53008e338a11115213f20e6fc3fefac2b96073409eb9227a53aa61e2ca6443427dea565f6c3c92deeb3b3575d59c336df4cd14f0e9923663bb6ac295251da73bb8451770157a32a5e0a3de473bb251231d9d3b9db69868b24fb3d61d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4bacc52e0c402728f872155985ffcc212b6df899b0ccebd9d65aee721c5b3d3245b1a749ab6087aed50394fb5ca7ceeadd72ddf29cf5260b386d54f3c48d6508	1612168550000000	1612773350000000	1675845350000000	1770453350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	327
\\x10b3a0084268e03c3078beff452595595fb4360364df9c47518c5e929967cefe9f8c5372372762183da1e27ddb69ee1d68fca804aae22e1c74e882a28ff6b8cd	\\x00800003cbfaaec03f03def0b1a64f63fd43cd1cb56d0090b8af3c3deaee95d150aefa1fb4d0bdb6b9f88f5458a09da04f8a3cdb02176c5f9780f9062bcaac9b58c2a1358fca13e66e9fab6f772b5b8bb84fba2c40c8fae1e27caf7babcf0599f1e6c6b9802ecc045efb41550ef437886e83290b626b6b12234ba0f5571bb7ea7f84c0eb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x678cb91c997252b341b6d15b773d8b872f07bd12f82779dcd35ec25df3dcb784a5e418b39e1945be70b30851de893f5619a3b206bb616f488f6a48ab9c77880f	1638766550000000	1639371350000000	1702443350000000	1797051350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	328
\\x16b7ccef2376ba4cb133f7f588bec2fd351fba7d5bef777e36fc4ba46fc53b4255e3715df8e0f36eafd4f020bd6090305a566eb0b0505653cf82c3d2a2488c0f	\\x00800003c24c108310d3a28373f2c28878f640a1069507fd19c7e7a5a32add39650ad4f234f9248a83a7b3bba4b9ff71005e924eb4d4bef3f45fe64ca2287dabc0d73051dcc79869187d2a6cd2a26de1c1fafba60164c13f6c217b90b86e4d48a665095f4c78a84703e687153f46df58931b5a7316f47091efaceb38ffc7010d06145515010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x110b38ae8a63c6cf98e36548de4607f5c2c529e179b5b75565c4b71c0ae0878ea4dda9fb285049aa94800d364d7b68d76209fde616a4decb0f1cd34385e3c20a	1621236050000000	1621840850000000	1684912850000000	1779520850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	329
\\x17734f4dfcd69a024d0020e41ccafd9b0edcadefd66f0bd8bf19bb1cc7c4e1c4aef3a3e3b81e2b9b6fb16df8b164f9b435931682a1e0ff729968c1a26a435355	\\x00800003d54baadc9d987d55c812ce6fc5d680d4cb7908eeba0fde7b009e5c71a1aee7b67a167bc7d414199289fbc56493feb4b7e4cc6c6dc22847268df18782c74070c07ae13047b99fbb4c53a531a829fd7125e46cc3457e5b911a806b9dba710e1ee9633f78e96392626bc90ef95fa14b1383506e719f2572c96da551520b8c65a845010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x37a6d479f4260c1365ddef20b88332398150a9138875b86ce0ffdfafcdfd1a9d4ff434c1b57032e2aa3059e3350ae3e1748191441d559a00644c1fc3a90c0506	1626676550000000	1627281350000000	1690353350000000	1784961350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	330
\\x1b8ff3eeff98358a4bcafe8a11915690ab9ca6108764850a1945b791d8ddfa29c2bee2fe071f8ffb00a3dc0469109a85805901a7242b9a40a75dc13183b49d18	\\x00800003c0c502c63f5fce6fa1706099d985c12e50e7c96bca80e06a42f5619c66568ee8a7d0ac918feca6f6111a254e2703c7a0bbb0a7447cb535d5fe88893ae1ed76b1af9cbf7c11f3e24da64a0f3d64fadb9075cb7de7eaf3044a7da05b1690c14dd6cafa216744af30587b35623f5fd9cdf26ff33be3c9bae59a35ff8ce0b6a16633010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8de245760dcfb8429e55ffe625a0b198d1bafbd256ed0a8f02b2b2f0bf3cfd507476f64ce490fe1fb72e4b7d8398db46c8f339c676a76be7cc2d0b43264d8c06	1618213550000000	1618818350000000	1681890350000000	1776498350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	331
\\x1fe77a900cb0ffdfc223a50724ca317d8c0ca10af25006e6ad9a3a979650b568eafaaf58286dfef1ec39f276789d57f45957bf60d8ce4f747bc0ef46f7bd53ed	\\x00800003eb3d7bbdaa717a26059c20e066b7f3dac55b1debd659ee4ea424ee1f13a16f92756faa72c2dd24c20114e5a7942968a1f58c668abfe073fa234b1d5eb9e8eab6a624cbc030bde044efe943209558e5a0dbea823d2f17f69563e40f9c4a6921cf4157e6634fa2d77f8da2bef55c2e3b32f77bd8e24d6b1faa7eab76e552fa8807010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x0a22f405e7f39e2b2ee6041b08f32da21662393972cc7a39fefda8690c87a99e4b499f2208954e8a0e6984539ce04be333f14a92e1514500496a0094df091104	1636953050000000	1637557850000000	1700629850000000	1795237850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	332
\\x23b76b1a773bf4e19d79f29b33e6563a38021640b77555970169ff9d54b8ad8b6c243b66e9a4bf118c6ba745032acd1651a299185d66e06b31cb43cc24d773e2	\\x00800003b960f28740a411b4769d8822402ee1af773411f145f3d76e2158381d103d1d7afd3241fd64ec8fcdc70e730e4ed2bccbd9055d6265e2c3e2a652830fb726187de73206f863f19c2233bbe841a54b0d8769d01ec8b17f093b2e56d232e0d5d0ef853635632bd32252968cc46e17af506867eb1b2459b905e27d244aa18790910b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x158a92b0d0ae70ef15237084541f873420138b0e939168b468849c8c6a22856f7aee9518548fd5e2025f8a2536b64f0e4d254e570fedba6cceb988dfb6abb50f	1625467550000000	1626072350000000	1689144350000000	1783752350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	333
\\x248f3d50e5c75b157e1549e044e33b8c989060acccebc9e0fe6694b44d82ddc73d466b541ff779dde22eef54f37b149e9c20eb6e0846b2aaeaf6c9a90093d94f	\\x00800003b0a19227cab894b4156acafc3b3fd5b5822eb7270af024def1dccc7d3a16eeb2ea0bab47abc05190618cfd0d4fac0fe0f1af79cde7b021ca067b11e0dca6ddc182d3265a5ba4399a8613696104e7142915a29ebe5acedc6651d9c37117b019fc9d28363726db690a9f344f822195e0b20ddce983d38d42d0b8a42e924687ad93010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x02e392282f7369e9f7e99ec06646b7359bb755c3837e64cf93eccd056ad74cca1c30b4afdd64707b18e6d40cda65dfea5c284178cf9f6ec7b9912a2725fc0305	1631512550000000	1632117350000000	1695189350000000	1789797350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	334
\\x24973f1e765b5bba121706438bfc89fe64ed1093add2769887405540b57cb50419d3edecb0cbe373ae4b2a5429d95efccd0c6457c4581f8be881e01274f1c2ea	\\x00800003b7d5582b8a09afa3bbdb360294b0add6a624ec227df364248f91c6e5d196093476652c69d346e432a36719bd20b5b93dd141b6f9526088e3a022ddfbddeec457eb2e5ab28f1fa0655cf8d5cdc5d712e42f5958ee102f9da0939c1eed68bb63f37264d1821f2cc5eb50122ac8fe45c3293388c00ff25d4ec87701a9ea9c35f517010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdea5ae19ae70243e77cc5a21ad3346aee084a51dd50fbf8fa5fecc0a404129b6de1cb2cdaacd8df8f225e0ff55d615226d857dc7862aa080eaedb323f5a72b0d	1629094550000000	1629699350000000	1692771350000000	1787379350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	335
\\x2467606022c97bb98f83939283e432f417e0cf30af4acf08cd73a9d81a1570b07b2ce83460b81e77fab731674274f46a85acf5b0a2c52b63a8de56a0ef83daf3	\\x00800003abafdb78402364623b097d17849471401767e0392210b4600e15d943da7609b8fd062afd651e1dc01d5a7c312ae21ba05dd621f433ce96ea201cd9952c4ce9618e57eea1aabba9d57cefb781cd68b74886d07a31b06e4e0defcbf53d8dcad8acbc968f76b3c500f3e454b36c8d1acf8c57d42202aa13e4b9911325cc4185195b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x87afe07b08644356f02f0936c2fa1079b0948eb65af2bb6e9700e10e93e47d2d0de3e44b69ff7602226daf17cf159feabdd38873615c2bdb0dd291577ff4ab00	1627281050000000	1627885850000000	1690957850000000	1785565850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	336
\\x2643b9eaf1219e15e1be8347e27ce20561bfd7d142291fc2362bb6946d5ea4d7db667083afd3b7f38db30a1570c8696c93b88c4ef2757c14127969d900952b31	\\x00800003cbc20f496e09d80e1d3b5cf88768f1e17c34e080bb6a2bdb4a976dcc5def13b5048335d68fdeea47f44838e7d55496188cd03916fb782ec76fab50532fb893f6f056ab49a8d2731030a8df5fc5ddf676138f9655f929221cf16f860161e19465aa799f116af1824efbd86701e92aa2133a488a6dbbc1086237068509a374d7ff010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb5cf80cfeefcafa9e35733237fc3d2e9a221a0ce42652956882774d702aee7268e5614b1200e1facd86024783b30acd982d9492aa657712227addf3734a5200c	1628490050000000	1629094850000000	1692166850000000	1786774850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	337
\\x295b8349d5b450dd9b12a9a32e71287fa9b72e290852d4c5158a9a9d7a0987bf553ef7bff49b7628f94a6e4f0d9ddd9ab2440afb1c59804d064ac60705c8ca79	\\x00800003ee93e3fcee28895590b411d03a43f92d002bbe006057a60e7a5887bbc6ac367c40b418969365642f2ae30ddc9f167eb658a85bd5516360087bee303fd038c6c21d9db92ca9d6ed0e1ce31b83caf2b22d5518eabcb98abfc36f3eaeb250c1b7cf18486f0bdc8ceaf7b38143b5044b7e2b881923a346e0504c3d06205b2ced28c5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcb2ca18aa09ddefc74dcb3cb85c9b872f892c951372d0737259811a3f382f32d520c4930d8a609bb0511568dc8e803b79a0fbeb9a84fcde33b8b316d14962802	1637557550000000	1638162350000000	1701234350000000	1795842350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	338
\\x2bffb13e411e824ba1a930b1d5ef702f7928a53a4c3fe60e99266a0a06fbd5a364e9b57ccb14f439ca587f5058bd9832fed632a6d2501a0afe3e23cb46a15830	\\x00800003db6de875031b28115c4dd3e548bb86c96797dfb8bbe91175c7c1c88462ccb81c2cb3b7d9a0c3f7f5dcf14f0f4b46e12334419c038430fb30f8a3c1ef655d01f24042f7cd6c6c8a5a3170d2bf00b8fa71c8489a642e9aed18b841182f5c3a9f7095479128704375096bb3c1629979df869deaed09c05590404f653d846bf7f107010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe7d8ca32632e45dab316d9f1bf29394a5422e1680d5d8a7b7948ae4aff10f47d5978c51de58d685280c4f5bcc50ba8553fb5ce8ebd69de6b99b3ac10ef88a301	1636348550000000	1636953350000000	1700025350000000	1794633350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	339
\\x2d07a8991ee24a4e7f3b081ec9526d35eed30ce924aa0199ac5c1469be1673bb6bf12506a1960cce1ce2bd1bf736a9d7414f4febbbe872a69ea5454f01fdfb29	\\x00800003a2f9629f2266c6bf92e3f7a29276914ae722daecde24145305a298ee7ae47765e739f388aebd5758b4d104707d4c3b014c086184587da11bbf3ad446bc06b9c0a8243cd13f94190b91854ad0ce08e00868b41c7950c0f7cb7fa87a2b7686e7d074d7e457f5434b36aaa42a95204ad9fc9480f7a54a4098d3c70db29a9886b78b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6446793f870a461824d15bf3f73de440399235626ff0a41c037b789372db1f0a9e567f85cd3ad7934fb2e65badc0b5436810ff21ea4cdf9cdadfebf5a6e33e02	1632721550000000	1633326350000000	1696398350000000	1791006350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	340
\\x2d838d4ac64fb2c8493d2b893a3d972f19249f9d8cdd89ef55be833cc0f04902850838c4f3f697f2e264eede415b95ca4ca5597315b587c445edf7f5fc865f21	\\x00800003e2e65cd6eb711680dd0a4794a269249b1d3c7db17d5407e6d04726f8d989354dfc22370fe14aa2e3355260800a28b9e6333e2b6581cd63603779be6b7dde29690781b252818df4b15e087d3f0f34833f9189899884c519d434bc36f8ff1de3550ec2b8203ee2a063918fc681dbc1d3cad939ff38ab7c7d39b52cee5767ff9695010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb9c73008b087d03a43fc5e9dfa045f359b3603ed48fd24c15bd7b49979e60e8a04fe262328bce1de93d6d9b95a60208aab0ef9b75b96899bfb9dbd755584dd0b	1628490050000000	1629094850000000	1692166850000000	1786774850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	341
\\x33fbb33c1237f3afb589d5dc5373dda2f81938685184a7a782d22f710bef60c47744f32d7b62550970ffad6989a4b61b5e7c2a50e4a330fc463adc65ad57febb	\\x00800003afc40f4e679076bea25a6cc9680450ea60c001e2d16024657d1e3f9e854ba738b5ab18cf9040a952f0cff4d63a9e71c97676510de5589e941ea295bf8029b8f6757bcd992f68fa77975160f0634841dc5add06cf9bd4ee06f72760ece8abbf8fd14a0de2fbf8fa0ad30b474b87145c1f913efa5af7cece8bb4e76ddd23c79319010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x543907850c42d5d58492f65d89ebb5cb9971d7516a09af4ff986ba3f46a11beee7caf58c57bb4789ab41c8ab05ca1591b7e8f13f0bc2651b97a9e408efa84809	1635139550000000	1635744350000000	1698816350000000	1793424350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	342
\\x337f60ea62b5c75c9979fe39563e68e39555edeff0f064147d11e07a540da4d745687de4a60131cc37c19c09263b8a353da2dd0e464035559654ec3f9f90cb72	\\x00800003b2c61049db186e66a13ace81e6563943c1a8f8f15d3e20c5f304d722d10c96e58d17f5c2baccbf2c27bebbc3e33e4b5c5fac9451a6634e2e9b712e96e7d48da732054d780c6ceec79325c49005c92241e22120bcf19693f951c34149ce2ce0b2d8896578f875580e5476ac60b4b9be9a0a8efbaabe26427bf39b17c345dc31cd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x63d2a6996c64bf3d270d5537165da3d68267648f7f5cb538d0b9306569590445c0baa4b7809d1067dff16e418dd252d36cbdc079e2a8cc3c75b42e32f2394f05	1636953050000000	1637557850000000	1700629850000000	1795237850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	343
\\x345b9b416a0b253f9afb821d518a47283da4a6e22354efd5b6f9cabf95ad9e7a05c7e04e108547035235a2f31bd3d2aa8bd452dae257ec6dcb8edcedbf28300a	\\x00800003bc7e32febaf82402eda142077b26a2803a033a5c9ff0ceb33200ee44849b9be92e91f6195c5fa194adfe057b210ac4db36b2316ac901ac14cb621e2b9a59b5de38f4d54a81afa3c3b35a9edbb7a7c9ecdfcf18fda21cc58d4e45653046fd8a2e6d5efe76dc2367eccf90039b0ef929f1eb923e332dca285f66439bfa5239fb31010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x379d806d91869598fee32643d3196ca3f89ca53cbb8fb2417a0f0e0014402fe6c565b321db573d9aaf96f2c3563c13ce2142aaca60ac138e2d867d203a8aca00	1615795550000000	1616400350000000	1679472350000000	1774080350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	344
\\x37d36adf33f8afa773dacc85916c62073d4d438bcbebce8a0dbefed9dd51223730667fc2ff51f3e9357f3bc42c715e3c27ef617c89fc26c5b6135502b7d1433a	\\x00800003a5beb4f4a47ac96d1e3eaa793278cecff22668d83dea2c833e709cdf2f0a1fef5917204704803821a8c3bbbd483185e8187eb7822a4a042d8a111599ef68b84d4a73f7a386eee4debadec7a5330b2aca70c47aa9e96a4820c7461d836ea07d70c66735361a2cc1e34455e82454e85c5986ea486ace5b9c6fdfbdeb2af637ea47010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf82d876ad0d3a0a88cade9eaaf15a48156a8bf3e2ef381e0cfa210b54cde89b233f3a524dc6325e32af0cdd6416f180ce65241a5cd75a34eb2d0ca717a787307	1633930550000000	1634535350000000	1697607350000000	1792215350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	345
\\x39f7cade2a614866ceddae65949082980650868f0882b10f43bcfacdf2d8217bd8daa2622e08b7695151f2dc6f8b0432f6d789417460ac8e710b63714cae814e	\\x00800003c56369e400eae2646064b24cf05509db4e9043395d33e54bba98b87c2430dec4d5d1e1fb1d5acda1a0398582d6c12c4b9b6ba5607ec7fa2817b0eac5b7ef0532b9b364590e923f24ccb32852016b8d73d12b1b00674f723e84523b982b100c2e5bb7a242ac1bc15385ff5ee24a327aad379abdce35b4eea0dbb31adcfd2dfddb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7bced7a93f33b79922b367a59ab95bc6aba3575b2d070b02db99bc1d07f2c5b084403fcd5f9ffd0c87013eb85859d3b40b48519db6eb0ff4156c621ee82fa105	1625467550000000	1626072350000000	1689144350000000	1783752350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	346
\\x3cf3b81beb60212e06d39e72d4fbbca8f45b751d89cb3a23cdea6996dcd8c5b86c9f632851db88edc917fd60415998c0e6bf86c787850053afc327f17ed8c0d8	\\x00800003b7b985c9774f62f46a05c0b78d2086f32223e8aceeda2b56e22ce0cf88a9358b2a43ccc3055cb44a2dde24b0c511a5e363d563416390d981be402860d7fc98ca6d0cd9a54c7d7ba10754e7231415d70861a48270469bc1cd8bc51afa1c789a0c57365d11629494b8f0e0c929a16d28f38c6919fd3f7f1c8f1d7889c581929b67010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x04eee2084e82922dd1a33f5024e9f0b1bd120ce21bb0599d1c4a7ed849a33fc070fdc1a2f2835523e5f338f0c85c1efcfb49219f47c2b57093e117d9c8412c08	1639371050000000	1639975850000000	1703047850000000	1797655850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	347
\\x4337f388c4ecd6678ecbe9365b7c6d705634775bb69125d054378cbe34383cbaad6dd71dfcaadd573231e65bdffdb7ecff72ce2818148b29d925c27bb0c738dc	\\x00800003b03e0a6d4e66eab810e335a5d6762eca4633183a8f72c805699da2f1d0600c774843da9bcb4b8faef5460e939d4e431ca5f648935e68e445785ce284ec025a493eabeab9df73fb0710a10a0065896ee83c7bce285cfafe4f00516f6a665d2929f483ae904c187583d80faa37f00dda148a591ad2e73ee1e0e900e36a7dc0f0c5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7ac66e920652cbafc1d90195e754695ad6df99f8f6c456c349195cb1ea1cc03858d56b70f20fd2264dd99f51497b48baa226fede6fe3a707b720341b24eb5b06	1617609050000000	1618213850000000	1681285850000000	1775893850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	348
\\x44d7744fe8f2016e8c734a057bc0b47a457486bf1fc2402332722399bd5281f875c7a5d084478910ea6a9c0d47802089c500ce3c4e0d9eaba12e1dc5c113dc12	\\x00800003b826f3c6932eb0c5f12e3dce1156b047cebd2f100c67f92390fbaa73cc999c595c68b2f654136a0f36afb7addcd19ec460e3f9f10857d9108a6497b8c81b532c1a4229a485750c7b2c12c272e89c570074ba7fea948581942d95e8f3821727b3e8a76b540b952c034ad5f0a17245dfddcb45c7a8edff3efe6a04d9cba387a54d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x612f2f311f878bdc6f64d78d5b786dffc4f116117a366f54d6613eee00a46e3dfbb326f5b3b3839807de8caf931471a2845b550ae1301ad8edbaadfacf554e08	1639975550000000	1640580350000000	1703652350000000	1798260350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	349
\\x49bf801e3a8ca1f0e410147c67d30d5c99a08ea8faba20d3770a84bee880c4ba55cb29eb28d00e45de2f122b19e28b2b3151c2a792c5d27c46d9214261bbff59	\\x00800003ea66f9cfcb40959ea5d979dde4c7fb1322f44ac2c2a0da5b4edddbb9112d32d73b72451f718e6d3b267b691ad615a233afe3bb137fbc5e0ba5984e49e0b6d4ebd422bee907abd601f9a52f72aebf5cfdd7ccc8f97ec7b5ff83f2fffa49766b0cec92ef44b900dd80b3830edb7efe1a52adae2d8f7af3b87c2e2c9716a956f66b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe75cf088ae9a31d3de19e43440e7a6db6e700dd9cfee2fe1d093adfdf92ab34eef14cacbb49fec66bd865f5bde6af1d01e6b71cd301afaf8813137325a8f460e	1616400050000000	1617004850000000	1680076850000000	1774684850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	350
\\x4b2b7c2d7b26798c397db0ddf510b96f030f23486197f40ca7ef097f01655059576208d6175ec40d1dd8f69f01f2b333ae9cd50a4682b35ab5269b159ee5eb40	\\x00800003a0ccbee65e3bce0386f8b48fd1f451a1e7fd0fef698eab5d14bfdb59667c3698eb097551b4eacc43a5cc8538a67eec8846decb753a115dd5922c303ecb55f385138ce78ffff0a874ae8e4a213052161dbd22cfa350c7d6776ab3f76f805ba2f1466e6a69ba72a032bb06e2703cda64124724374c78a47f5b7152e40f3a9d6df3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xedcf7a2ae918033049a095d23924a496b834b523945c52ef80cf41312140048162ae05b795c6bb4071b553d2db613d505af975498ca62cf5484fa29cd0e98c08	1632117050000000	1632721850000000	1695793850000000	1790401850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	351
\\x4cc7def9cbf4532fbb6dd4e12225dee08631d87cb1711680462e85aa5a4934f458f945cec1cd3a29856acf7a7712f554ddf9dfd5a01928239f687b0aadca3803	\\x00800003cb5251392a83efa22af57687c1c3403968bf91ea13f880f476f9ed01c9daf725a543b3fd135d46965740c6ba833d38a969f375977563cac0e4a01b0422377c68c10ea0de3de5745ddf4cd46d10e4c510eefd9441971c326e40629828f876b8e3c12cb445d935828dc64b23512ac6bfc89147e5e5ed945ceb08c3eba3bd641f7b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe464d6c47377c136411335305a2471a24c545b6bf39c13826ea433fe94b35f5f7e652c5914ca66baa53b51e68b7f2aa2cd2ea5633c95e71e370f7087411b280e	1635744050000000	1636348850000000	1699420850000000	1794028850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	352
\\x4dffcce3caeeaf74a7a6d01547458d53311b8fd2a7a20f10d5124acded2ed72829937469acff6bbdb88e90884219333766f1e74f3135ef3cf0511bb7733a887a	\\x00800003ebce6cf200d92cfe1387088432160da01076afd2bb08c5297d35632d1b6c7f8bc54f6917f4edd2dc968347d256c14bbf4c54f6bc5f40811eeb21e702e5d60d92b67b88dadeeec9ab12067c5febec46480f1512c628df551ca28c89a797650c94d15ce75a8dd32a757a72511b2adff87261e572b92898b6e516a516802960af7f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x1c38ac91512ac778a9390459497f41cda5f4857e4ef0c1da930622b671597c2f17091235e0cd691023b63b993b2dbfc96b33e536bba460a5a1e71b818b406306	1632721550000000	1633326350000000	1696398350000000	1791006350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	353
\\x4dcf07033310b2fc775f93af90716519d11f10338b9f1b8c3d4fccee0d7ca66879392aba4122a4603f1345555db99038277ae9f6b59e20c4fa8e520c17efba34	\\x00800003d082ae0ca6a0f60b4bd27321c1b8cb8ee2898a6be9bc7ce839130c7db350f4caab4fbea47860e148744addd176fbbc1083586f9f67e87f0cd67ac1913c37c7ffbff3e301bb3202d19c51ab08bdc4a2578f2575b4aa0942b8d8205bb5238b761b6e6086038452a4de990318b63abca2d8d639551e52baf053bccab63a80e7d3ff010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x72e1c26a456c0725379fc5f93dc6fc66c36197f7e748245551b5adbf773a6fe442b5f011041e240484050e66396f42af93137aaf5e70e2504667e3198c520e0d	1623049550000000	1623654350000000	1686726350000000	1781334350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	354
\\x549f524c23346442c82fb0587c04be95e49a04b803c14f65ba2f1d8b1887e13a87082bd91f6324d7c6fdd41e2773d498f5689a38839d399f7cda7b2851e332c4	\\x00800003b02913214fbbf4b924a35257126520a746f27a291028a8bec8d0cdf5805f5e62b85995ba0779c253cc391c04fe5224e65ee6b77345000a516fd2dce2a34e347780842019220ad386a438a1154476317ecf1df965e130133d08dbbc3874aed2e067e384c6836d302d2c3c701a2837b8452a7b4fae2919c03378de05b80dd66d75010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x39631fdd5a17355b2e705682c78833cb2f9c61f922fc5494c30eab6c7f627f80840382bf7e13ae31f284497d3375e0dd9f045f145889f925ebe3190bbfcf810b	1641184550000000	1641789350000000	1704861350000000	1799469350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	355
\\x61c39fe79badc12b1fce8b79cee9d556303207518c46f96054489cdb6d0fe90444e87f47b789813545c5fe6f0479b163ccb40c778532d8547fb3fc4113235825	\\x00800003c62d1ffc6fb9321549e7a8c2d43b6b9d8ded578d4a30c4bdf43d8974a8de5697e055f03768c5194ff583adbf1a57d246062ff84b24ef50baa78157d2c945e0c54441e3ffd86fa1a341468d0ee89c73021ad4938b213afd29f903b227f9ef1941faea2ff5cb0cf827f9ff4bc9e40cf3f9edc12a53855ef4081c3f4b5aff551b8b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x49a2ac2d3b754b08f0498e432842ccb51d7aac658ed51962f3c36f5097bfdd6fb92aac89636f4ccde60841807b1d76cd62a8c6148a2538a90d9a83233a78df05	1623049550000000	1623654350000000	1686726350000000	1781334350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	356
\\x65c3f255277a3336bd7ddd77a7c01c2d4df2cf9d8b444e19d527e4195255c504fcd005c45d7ce826d4453e6115b18355490bf531d30e8fb47b6bf12f9a4aa01d	\\x00800003a80e23dd114f97e10651cbd8d43d060493fbead350b3c85a58f0467f598b3387802f54a3ca60e7bb402da463aeb52f76d224209984b2cefd75bcc15e24927d0cfbf5968686ff3607af16f2c25f206a639158c81b674ea0ecfbebb5006a5a7a14d5006246f125091e5ccf581952d29bcbbbc7c1944e65c022f6bf783d0f85a2e5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x928fdd30aa6e7bb22a2bdfef226fc096e299d7657c1259de887a326d17c48a7d9ac11b5ef7f0c2d1242c46bdd2eee8391883fc056ad523cc7e02b056828c4d08	1629699050000000	1630303850000000	1693375850000000	1787983850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	357
\\x68ef5ada4071d656eeee1c4dc4bc9fca5ad95153e4a0644593d4583f2d05870491ca15a5ce60693a0bdd33ccc91a298558d633656b66c17fb01ff9f489210fea	\\x0080000392febe0426e1b9e286fa59fb06c6b3becff283c341e5e7b30129ceba1bd7caaf31455c81963f128214c3dad7ab2f28de9c4cb45c61cc0acdd6102dd3a93e1fb68cc323cf57f0e1e7b2917ea19a55019ef00571f565e1c519ebd6ed991e4cf790914be7b105973914daa25ee154927526a6f92c1d31dab2bf72a6a7bc9b66e501010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x02a0841ce1a320c7588dce65bb9d7ec0daec37a0c8037fe64585740dce1d0f468995e034cc451e12ef8a036c14783b5ef1e56d4027aade47aa0d138a3e554b03	1615191050000000	1615795850000000	1678867850000000	1773475850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	358
\\x68f7a0ceecd7e1fbd738444df508c280321f74a0a7967360bde2937d84b84eb0a9ea6474aca1f19523f0e73b836398d73cc3f05f5e437690d6ff3d681f464f2d	\\x00800003d33e259135fd55761088c8b8550c26a7214a67c248c246a0813155afcc7a42448b8057862b387f306a9d7fd9c7d27c1c2e72ea9091d308a46104306243496e189139f7c1c45bfa16b07a7f1bd1c76f47cc7d2e20f25fb20db40013ffdfd4ab40a38691efab1c2f0e64ee1ae9dc241426d16deabdc2f90e7cc52e439723c5a8b1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7ca998a9eba5a3d71375892d34c01bc48a119629693ec799448be3e2a1135c0d3d0022a2fbd5bbd047b438ce098f2df10105da2bbfb41a5c0826126ca86c1300	1627885550000000	1628490350000000	1691562350000000	1786170350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	359
\\x714fa699ac73fe25ed16132e19c6e26aba290f0f4b640f003d10cb1b765d67dcd3c611f6ff3d3b7577273f9dc15142b7ed53eb6390d630511cc9de45118de571	\\x00800003d7ba7e8d2455768ceefa565b8fa1fd2091a53ea54c0a74ae91382c4561a462c70893bd6590b8da457dc9d133eac6b17e5d803e80668c123ce420113438595342ba8d1d17425ff43d03361eecb3fbaab2d8bb33c92888feb5467c6a11e88dd4d7b93241be33288abfe7fd782e91e0ca1afd974109f089cd96aa3654e0ee077d53010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x99097aa05dec9c52c4825935d7ddf7287f5bcdfc5aa76f9f1bdc1fcaf96c2c747434deed499743f82091647e741542b63a58f45e97516dfade0bd6a58e671805	1630303550000000	1630908350000000	1693980350000000	1788588350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	360
\\x76f3f98a34c6d42720dfb7805902a64d74913a1766524f68e596da2ab469416a46271bb614fab3b2daffa3f0713da463bcf8dee95fbd7407077cf171cd25aa93	\\x00800003bf346b1b26a96ba486b9f2f90b988a3bc5b325c59d23c842a75c19d97774fb6fbc7cc224b8084a6e496a661c64dc1baa1c6e9706067c8225378d8eab07195444e9b63b286fe3425926d55e2e48c0c26c15d5fbf79bf64aed14f75fc6737aba7f02d99dd0f6f61b4a49bdc12db9421e1f72953fc2df4bc8d7926525d9c7f429e5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcda274f8b0c87149995aea80fbaefd31211625ab27e0fd7917030ec24276febe2c73e2fd62438d185c0c5a37b6491df04da103da9a9598a7c0d00e4ade474b0c	1623654050000000	1624258850000000	1687330850000000	1781938850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	361
\\x78bfc54daacb42fc5d0ca3ceace0142e85d9d7fc5f765bedf978c19189faf4e82927bc6f494d2f11c11449e06239445393d9e3a43ae8e1bb8418d9bc2b957601	\\x00800003d79aa88b1e2a05bd3b38c8a0ce931ac08d4050859ffa5d517c72360325ee5b363eed0167d117aeafa621c033e606fcda405643b98d6501044ac38560828012d2ec0ec9d90668f07d22bfee8bcc56c30089ddb5225266005724918102bbb705358fc25643091cde734549de5f1eddc7e6975cc48ecd33767be3b083f319eacd63010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb5f404de22d9edfd6bdc21d1ab5b5c482de7cbdf57f44db724ea3743d2e9fa1852710f4c216a9e0a7a85512e79de79bf229bc4534386b28a3cbbac4bb15ffb0a	1618818050000000	1619422850000000	1682494850000000	1777102850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	362
\\x7aeb45d2d06fd8bf87b9d086254b9a5c8774dfa53c3ec953efe22578ba436f4b18f19a02691d8f104beeac021e950d67e2cd3a6cadf6a95567bffa407ad8d4f8	\\x00800003b98c65526c84c61ade16518e27a7537c4dcbd8b3ea787461bbd343ba29cab8a87d5f3b2ea1a26b86f2a2d332f4b41f2aa928f375420cd7a198767f1011dc8eb2a07923b66cbbc8be2b0f81a665ee65299bfb088ab3c83a51ec40bb45d74b052db8670dca6b6d73a642e787ac2eb41103daf9b02fc78262f196b9d31ca04688e1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3b97f7272ac622329f424f9095fcf2cb37fc5a051be8f8146b24bf0c757bcbec51b9ef232704cb21f1272762ebea868971bbe8c21381fd17a757706f872e5602	1625467550000000	1626072350000000	1689144350000000	1783752350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	363
\\x7d8731ae8c6bfe75560dbe87f8d5651a6269d3231f3acf49728dd18c0a2f9effbc299e3c70fa87e8d4d5e12e0f9190bebba94d9f8da2dc3090d43693a9329c81	\\x00800003aaa5f6de4564842ddac1190393cf65c5dceeb0082b173f77922e65de63589569db9048dc8707470baeba7a23ccbc506274cad26a542be6d2349ad2d0b513fa76cdc3ec1c1c99dc259692b4530f5b10a42c32d6be7fe0c155c5db8b98cdb34289c9298a28741199366f0471472ff4b0e4db4de0f967c5bf6d241933e238d824c3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x70ac8f93011119d09c429a0ad83694b6eea83b634c7903b0fd2e16e59cae48474bcd6c378f8403484d675c293705ee0e18164c97281689f479ab8d9113a33a0c	1620631550000000	1621236350000000	1684308350000000	1778916350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	364
\\x7d6b9868f5eb6e4fc7855001985e66b7c275e2e11aab88cd121c2089cddcf9fc375de6ea8a16ceedb3cda434b591e0a0d6aa424da4f52042f94fb518f2bb8bb7	\\x00800003c45b26092cfa6459a8ad291b7f135e0f0e934a8c3d1dc6550447c7a340a6aa9f119ab35142821a65131683386baf1e623e3c390a5d9fee1c05be47d48a0d5ae8bd41ca80553c046f86c4665f82b1721b1b317feb13441b7a3685c16bfe77c70c03766cd031a3f8a2a1806e4cec2526bbc95a76558d1a017f4c532fa5f2488ce9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6f429524381775c4a11f0502f37d6b2cfd62ab8fcd148724e99dbaa13ccc4b92246c9484c492022c20bb74deda17d6de26a36f89f435a4e7f400b392068c210d	1610959550000000	1611564350000000	1674636350000000	1769244350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	365
\\x841f4f00c5cb57516bb67a9d913c7b606241e70ea442023371416a81da2aad17e7136e92616b7fc6e7675e00d603da040c9a4bfccfbb90d3982c2f138f10d05e	\\x00800003ee8999a3d8796b38f06fb561506620803fd1340c4ba86810da74bf090ecbb92c3d2fb941f61e6076f7e10cc536a996f4df0459ec83a4637791b2c75b2f8cf54b7cfd813e007d71ffe0570ecdb2642485f6fa454ed669c2eebd984fb1632fc348358b5d41206395ad6bb131f92f63f515f8fdfb73d8823af4a5869f9235ac2da7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x750399c77bc950bab35a27a023fa41ef69d4e90d891c6f6f342f863bfcb670cb99a39fd1772e18805fa0b38ec33a21517a3e3d492d2068c3f913ffc790ce270b	1638162050000000	1638766850000000	1701838850000000	1796446850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	366
\\x840faf13cfa39ca57477fb8a86238d18cf87c3dc5548231e6fccd021fc5a0aa52538bd88a9fd9483a8a3186b52749694e9aba20aa41e49939302b371fb16e2f5	\\x00800003bd00e051476af8b73ccf308dc86eec7e13f3ed8d9e9aa105d7fc6b6d3afc718019d874e769877bf3d28b88a13faa402ca7fcd2733b55a456a0037afb4a25d854ad1c9094fcde06a281c6755d51cc52985b551f0e2a6ed3f76a93a864cb0d1b6a7eff0f374141a0a1c25ca11550b941934a78bde106abf4536dff07c0411586d7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x574959465ce03a9a1b95edec2541b07e3aa8554f1f4557d35f26aa5e1cdb3576238b82ae14269c9de43717c41a0252fd181c92fa11c571b4643df7176d778a0f	1636953050000000	1637557850000000	1700629850000000	1795237850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	367
\\x889fe29ed8ba2b2826d668907f6958bfe7b275da845a2183b40b7fef9b2ee0164b960821db8368ac14e8c59268f3a9d49b0cc1bee1c07581cf32ab45c0d5b338	\\x00800003a213176762c92a1b4fbb9f2909708d4459b2d9ccc8a9b8c4f7f814084501299d80788cf75101abe9ec3f2daf1bc474de6a023e5ee54ea7b35e6e2a88a1c4a79716458179f5fb1ca8718f9ee62f4cc83b8ba4b75bb8404ec889ab3974c8c56705af4713dc395b960b7bcc56c8416aeba6d836c60bf90a3271a14179aa658c4f19010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xea1e1b558477eebaf96276258a37cfbfc9f57ffbdb7be8ad972f2686b6040bee90ca51a4ca212f9ad00155e1b8850101b3013e5fb1219d492f050ca9b179b80b	1629094550000000	1629699350000000	1692771350000000	1787379350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	368
\\x8baf774068130af8188e9c9eb48739fe653d18f6f40f3d7b13c1245cdb35a02ea07ed907794723948279e23a76ace05606dd54e74075fa8579ee45092311b8cc	\\x00800003ad37979f81710f2788c6468521e1ca26a2e272be2a47bc1b95b8e93b0d17bdc369578d9f4259b25e864e1d6dfdbc0ccea309017aba3c4e4dcdcc8e301d76d3938b191b88e0b854dbaa8eb4a02af91e5e7a0bf3375103b2a361d28b3024253dc203bf66721c33e58d5e018e6a2b48987209d5191dd9247c2812d0a4a41a2b72e7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe303eb76bab822760f0de9235e49c3d14320c4a74bf4096a2964d4b171091e9b81d6e3c6b46a68586efe87434c01913b7bf25ac7ecad6a007833456d1a1d7e01	1624258550000000	1624863350000000	1687935350000000	1782543350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	369
\\x8c9b8948d62a65969116dbbabaf95250b7d6febfeaf7524b1001bc485b4cc742bd615307290c11a307d752a3b1f556f4c7fe8183fc0ab125bfda1e8ab7d9e26a	\\x00800003add4c352aad4befa5526b7e2953e84a1dd3d9fddf51775ff501230677a6812e691471dcbb439ba76f0889a77d312051ca4ac860695a56a05d2f664a638157a5c3be68c0a352d492b5bb10f9e3ebb998ab2ca47fb3c5556693c457d2e12cc2bf36fc070c5e19a609464be78131cbc408f07276ecfe4407f16e6d513345d7d4499010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x84576f624107a7328bc3954373fcdf9eb3d9bf9fa8a810d87a8d83e53650a08cd05f836d82d13aa2c12bcc1a1aab84a96c039a85a5bb4daabbb6f8c444598e00	1623049550000000	1623654350000000	1686726350000000	1781334350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	370
\\x93371b582c081834abb2e66d3f8b88aabf24239c198506e1a9f5bee8c558d0a92c95a5820153469a18119a99ed09151b2bf952479caa570f8b92e1a2789a8ff1	\\x00800003c2a9a752d4d791656185826e969d0b32ffaf9900c6c3ab4bf1293831034d6680c6e4dcc7eb890ae3df4e6471d944adfa69552c4ec388f83e57c31aa70aefcb3f03509ce167eac5a06dcfd10bc70af24cea935b5b067be89a0a37d0d0051371f538a8645ebdbeb503336dd4697ebb5fc67ca784e0c6e0f7f21daea5557e979269010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4be1e95e0544166b43833591f4014260ec9cd61fb144adba373762e700ff75e8261ee941f5d861980aeb4d3add4e93970049827506c3cc10211ab8809fc4940c	1631512550000000	1632117350000000	1695189350000000	1789797350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	371
\\x943b3ce6cc8e553506efa0fa74b18beb229a62643fd90fc86a7baccb4b12725bbb3754e04cf7ec25d621220a56bb7b17128d54e35ecf0f000de5fb6451342ebe	\\x00800003b111ced916eeaa3e38af48e3133b6af9f280d624501275485d90031ff04b50b97e1ee770bd5e8f39ac193524b31dd9dc50e1290e7a9b756f16ee830ab92dcd4bb24d9ac3b62beb6c5947da67872f2ccb6d12be104e5db9dcef3dc60f6589c2b4287a0c75a825d40ca2a5ea55c35cce821df5897381715ef89de7fef922405f05010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe5c7a83d4adadb8071513872c94a24c22aa1ab7575ebceb5e237927416bea2c3bae946419f1557d6f5a4dde5dd245d29ec0959429cdbef73decc65980a66c403	1616400050000000	1617004850000000	1680076850000000	1774684850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	372
\\x94777feb7c9405c14bfac413d455d3c997859d2a2789540efab6142221663f6bb209214c32ce2b24cb8c124587b34403f5c4cdcca59ae177e7203e4d8cac7fd9	\\x00800003c63d21f4914727d27f6def640969efb6f20d302808d7aba732daeeb7facd5ed676935db98a20179970a32e3b2265c28997a38b38979720b640cd34f4e8124a9b7a9cbc3ab57e06806e209c8b0fae933430662733c1da62edc22d0ac18969bbff4df48eb3d14b5f7850439d8a4a753761514fe174576cffd22b9c016003739413010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x244d8c440e537a7e2873e6e8bb17bbf014fc9f79d03d4f078d1dfc880f735c5a222c20950f90c6b76c865ebafce8eff3529e29aac5efe393c9c964a4dfa6a608	1641184550000000	1641789350000000	1704861350000000	1799469350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	373
\\x959bffb4e12fe8c2022499bcd5abd5c109994a40616fe2cb12c88ec19397749a77a3451203c315f622cc768af58009c6f0879f2dbc2f0f4f4270d5f4feb4e576	\\x00800003dc867b992527c91f13ebe0784a72758b48212fbc7fd6899dadee08d5adb2284f4781b8e860921ccffe1199bc53292848cb738f87e4d8cdc317b718dc74aa43bd284b0d4bbbce37c81cd5196d96005d397217c850a86e2b30281aec505e1ea7aa1a478853800c979e5d58d81b33436dac420ee329ea77da08dc3071b1f4c34f15010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xdcf4f6ee0f16d9694245b1bcfa84900b701b303573b59980e28727c8b1254f307b5f0c68c8e1c7fdaf2fd9712cb432b750f9d60e829853adfb789d48c214310e	1626676550000000	1627281350000000	1690353350000000	1784961350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	374
\\x950318c3b0113557e8379122d25b9ac707b6ec67170548734be44bdeac4747a255023f492ae41608bc1ed75c962383e40e3e3690d399da47fdaf5ee251514636	\\x00800003be6e92b946c3c200a4a17c028cde9b34b90450e117db8df6d2f323d9048f6ca5d0a3fb827d94acfc30137aa8992392d9eec55406caa755ce1ea2408a2bf4f9475322d60406d0397cacb0d5e8b308f78102c71c088cc1ea7fd019565fdeebe6210b5a64949d5539f20741d9e01d3c37b9314d2e81ee87c901bab19dcce793e007010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc1001a70890cf3de943795e25cf8afaf1d6b8a3836ec5cba09b043350b645e535cbcfc4cfed2dccb177d9710c500568a983f6ff40c5fb155d5bf3c6e4f415201	1612773050000000	1613377850000000	1676449850000000	1771057850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	375
\\x97eb714f554b5bda034ad24e5e3868feee78aeff3646f282f2b4912aac68519cbdd539ba7870214ad1ccbaf337270e8391120c02c346031532d61eccfee65709	\\x00800003e02913c066c0fd1ce58e461b5f8fd901afcb74aceb67782b58eaa182eba26c2397a2d689d3248dca8798888a0c830982ae3b0eee904860681edb7ba382ffee14261727ed450279119132a9985b55e753738b7460252c590bc8452e5de5774784c2bc32fcd5b2afc570427205c480497f92afb78935cb65ef50db809d7f70de9b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5f04359c75291b7215cfbaeffdeca379445863de25ebe8920c4d5105df0aa6d44129513a8cf5bd5eb09ac2fa2417bd1fea1ed8f84abc917db9a7d53aaf477006	1610959550000000	1611564350000000	1674636350000000	1769244350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	376
\\x9a8f82171991063b11135cb255e07fb0a749d31d3fcf2189c3ae13648ee715c923c04aec5f9a84f8a5e22cb5ce9cfa08da129b4ce3f4a55794fa1f0bd551b33f	\\x00800003a45a1392c84eb51e1bd49d3e4f374035edd12074ff9edd258891a19642a9c33b582d30a4cccd7a3ab5d1e7b79ced574d688509cc771cf16fd7096531dc7936d0ab8c494d070f3196de3a150c131c1f57180d31b46ac3552ce8f162e7a65569ffb4c544a76ba7a4e0c45aa0640ebd4028521a07ee7947aabdc9353634937e828b010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x016a27fb31bb9f44f5c8ca08166b429b61181ffc3460b5e9fcd41cf8d580ed59e86d3e85ea185da2b9672926cd25a6c0e3eac1212abb24438e78eac37379a40c	1629699050000000	1630303850000000	1693375850000000	1787983850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	377
\\x9bbbc6cfe3103ede3fa847fb288d20b3a564ba4d4e0a963c9c8331155550f10b1a46c0dc265996e65610317c374fd08f40fff20360889623a4e5c33aecd6d9c1	\\x00800003c52b437a30013565b4534e392684e436f21d5b8ac73aa37aa530cffeee2742e005e6ea8371af7effd14911aa2d9f75ee9de0f568ac5e4059aa712c0a190ae2842860122bccbb09452aff4f3acf116659478af0dce36f0448f1309159273c6d38de3d3ad90d01d03000f696ad52ab7eb98abb5e8b97c501c6e024dcb72c7b60d7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x073917419ab8259e43e8d16ff011c0ae47bbda79de4634a9cab62f38a538cee2d306b870aa2ad058795bcd6345cc453cd107edbdea1a2c4af049d92800d73f03	1614586550000000	1615191350000000	1678263350000000	1772871350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	378
\\x9cf3619e3cde077445ebc227e3f4157a7f0a19cfb84422d929a3ffd7fe94a9d52eadbc1db1f47f2a834b3d99ba4738aad1393a716042abba29538126fabad7bd	\\x00800003a711ff31da510c5db18934203239b28d68e6cf4c712c59f4ce6a75de73d5f7150a28fab6b5bfcaf84f8d200adb4583c5f47db3a9b7be62a6ebe3525165ee384e815e0e2a3dedf3c6976e251c0bc218300574e80206a4a70a79084b7dba7a86379dc381f89360f1193512d9c6549f3bb43a0c72efa2b1af30b28a97d664638b03010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcc3b55bdb71ee70563b8019a0a11707d34ade5f9d6aa55549e6d84234c9baaa88781b9277e87284293ac8c4fa6ad3edf0a036417384866e02a0fd3c14cc48b06	1629699050000000	1630303850000000	1693375850000000	1787983850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	379
\\xa0cfd504c5537e22e6fa3d7dcdb64fa3a0fbafa7c240c7134126d9c5b6987841593f0d45e739caa324b6954eaac2c72aa66bf731f07a657ad192890036d9a014	\\x00800003963cb82d96e67d4bc784163c418bad049c47a59910624c08b832ceabcc4739418ec9a4f071f9e512ad9d4fa5a408c01a598ada7b46cd278c1a60ce7e54cac0f3a83432e9aa9890f98b0ebc7c6e88b1d33811204be6e0d3f000d735fae04cc0ebb9a026465d438f42cb01065b617ec57724cdce6df9064da88a841c262dc7ddbf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3fbb4c89965b128e67b50f76e2825553d848a4f007808e13660b1de194c73d300c9182123397de3e0a88f56cac9a40bf17180c12aa46ea2b3e45118280e54804	1633326050000000	1633930850000000	1697002850000000	1791610850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	380
\\xa1cfc537710cf9f2c60955f15654b868527a38ef4b917c969794fa01faab79cb5efefb61ea88074a8f5cb9212123d0446173c54389f41e3d428aa5fca7e182e2	\\x00800003c284f36bd471b6a48e5425895df2df2a5533936d1a19b2be471a95edd18d404cc0c769da5023783121618d402f944f10c58c92f50ce3f2f4dc4acf2e193d56f9d3a6c5f977130fe2d549745696a330159846104b217acd890f57cf82c9feafa014660f3f8a7d0fd4de5d377a49b8b139b7c73ddefc6fed66fced653f5e31550f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x76f8d73b4db802e5bf119c764ceac21067e9805b52711f1378a194151efbf86ddb40b444f0d1ecb62d0f78a384d0403efc19c78ddbb22279994c396b4fced300	1633930550000000	1634535350000000	1697607350000000	1792215350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	381
\\xa20ff32a217edab99a178e78e5a2947024239278563199c42a8248aedf66a154ad427fe4433abe5a040c79fbf83b006b3acf7f762d251d1f44c488b710301976	\\x00800003d7034beeab1ca5b3cac18f8c2a6b2aaaae06c06aede37691826fb684d9dbccf7c9344788ca0df7ff079f01c6c0e022eac2487d1b55cde2ddc8e543e90116ebc2e4b49d60e07d4af67a8aae457f566d4c1ef59c9dd45592d2dba50c1c74e94260a8fe8b7b0394c5e417f41b586ce192f2a8032e13058437440951380c51477665010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4174dec634a26505bf12eaf79054a523ccb07681bfc84477dfef791e84d658579fb6fe85c1ef744fcf20524fa8a0baca048593e1f067fe51f5415f44dde45b04	1618213550000000	1618818350000000	1681890350000000	1776498350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	382
\\xa2c39bfa0f9c28d5d930e93bfb2fb158b9cdbfd29b80d4754562a586593221c1b202c48858b82dbca5a4bd3afd47019ea6de303e95cea99a519468730184d0ae	\\x00800003e08a9ee68857eba5da01973b80d16c06a84d8befcddedb466113bb02b678d4a215574be74f1961c00d21d27b254f1fdef941852d63599b2dc666ec28c7f16918a48cd892db518046d89d579509f6ba7a55402aa0c39af08e7f314821a1db6754bdafc6f9708181bb8851b4f8298d81bcafead972aaae0b2f4523624d965c85bd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x41d14670eaff74bc7611d5e55e73fdc1ec60afbc4b53a984edb88595c27f02baf7f951d8a9e3134f0d81afb86347dab76c2ba1f760f5bb64fc31f6b0da009d01	1631512550000000	1632117350000000	1695189350000000	1789797350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	383
\\xa45b916d66befaa04a90594b96c71d6932e9274b02169c9bf4255cc7dc603d298a604108ee50544b2fbbbdda5109e1313e9eb2b356d47707226e0c1fc3d21916	\\x00800003c3e59a1006a7fb0c9a2a3d42fc7c18601008ce07145e41d9ebacea1dbf45c40075403a76486be3fc82496a4e7f166fb42cfc8b30213a1cb3308cd545f7409339cc63ff518348498b13c1ffc7c9bc8d91302fbd3ab3ff084bd2b0c894ed41facb30d291c4c0292ddac3c80a501e75e26951c97dc94bb7290c5c4fde5f71612997010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb1fe98cc54602d58f09dcb50b00d2cabc655856e9c7ebc1f30fc0d8a62b88a8202f94f6a9136836cf2eb09d9ad78ea394e1f3f9141eb46fb58b7c6fd20594605	1627885550000000	1628490350000000	1691562350000000	1786170350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	384
\\xa787cb260166a3feeaf0f01c31a0ffb7df6586d8f51f6e4bd53bf8cbb601e9084f750767392a0bf102fdf2c655e726abf7bbf910db4d5250b0926c0a362c521b	\\x00800003ae59e6cc5d51f9b2412967af0af67a06588a59756c0aa3bb1b82b0d2056db73ae204f9f90974f577868772f8a97e81e059f1811e41850e5395796e9b0f6e327e8bf2e967c154868d223eb20fe5c3eb42145524d4157ddc542e07a2b50672a5aefb08e16f48e5c9ab2309592afd5f8a8501ee941de2bf11e6b46ce6ba9322c4cf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf624250a5debc3db90c62c05abfcb3250ea3f8fa61cbf8af1f50cd96643de11160b2562cf5b91a128cb765f3c621fd8ab14270ac5fea9034b81b60b29cb96d03	1616400050000000	1617004850000000	1680076850000000	1774684850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	385
\\xa7bbc4d3eeb84a7e19a3bdebbcdb56f416081b02867a3b26739c0018f718f73381811ed0b2f75317302822852e6548c01e90badafbfb6c9a33245e80fb421a35	\\x00800003f3af622eda6ed1bc004bf49a805ec43b0d28fe99660eb4664e8b35768d7f833f5cbad3f4dd67ba1023996e8816412c165ff73249153816116b045d19101b9cf9e5df4d874eaf9e3983e26279371a4d235a4f9a39039874ac2906acbd0fb95c41db87e3a1191ad827a884b0528620dd4f1335f4ceaac1b78055dbab422617dd61010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf6c88050e289140eaea1f8cdb522d0bef6962398b4755a6bf5b4e7de1ff34dcdc4a3dda974fdabc193e5497865dc8dcc21b6473235e0e35e03bda74325096d00	1630303550000000	1630908350000000	1693980350000000	1788588350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	386
\\xae8bae90d54f7f47b167bb2d0c7759392bea561636947ce3c807902130b2ec11516314832700f601d0c0290c07ca7f97e04d5e09f0e4ab2162c3d86de1bbfb5f	\\x00800003d71e2d8d2058ea3fc890c2e16047c7203cae134d07373e4ad5854494d1ea0c3915e25d8e57f13b8e2c6bc9b7405361c75ca974e8b558f5a03b1ee571225c13ed28f7d905ad404b18bccd72fedbd900b14ca50b567771e930a997b44941cf4ee72e4589d09642619ce02c9eb1dd67202d6f09d71f7a2048f9f3efe20a2f2c9333010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc5b9a5e6eb33c0a5cdc9c88f1c195aea18055d6212002c22ae947673b9e649791da453830dfb5c6cc12411f07bce5b59a1cc469ce937024b3b0214fc4ac2e00c	1614586550000000	1615191350000000	1678263350000000	1772871350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	387
\\xb1cbb5f65b3f47b81893f4c4616de0ba1e66804b85b81c6a6a4ee3f6043fbfde31bc07265be65c31b09570e67c7ff78e5b78ad78e8bd368073905247d86113fc	\\x00800003b5c382158ae66dcc80a1d6ede37853588110bb839622bd475a48d73e1078f693ff6fefa347df9c538e556645fa8854463fbd9f227556d17099a6f3c3936965dc4878d64e61fbf8b44f6908a12aab4c1d6bc029ee436aa76833c1172f0f6a03136fc61624912191ae246ade452325f03f09290ac8377f80d973e40bd904325571010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2a6bf627767197275ea8e1d0c0ac02b7168ada48589b98ca1b2e28fe44cf42ce37f59116ae58637ca382c13c52c8d0a893d01cecd8d8041edcb84cb74ba10903	1614586550000000	1615191350000000	1678263350000000	1772871350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	388
\\xb273de8d184bd5f7269d2a6a0bc7c03b32c1dfd020bf75ed6365c9e5b0c94850880779e3c84c02accce15bf2291d966e30aaf100adee43c8d42f9715bfcf5406	\\x008000039fb8e1f657449ffb8d276d050142ba4b1fecda0f8abbd26d1bfd15841d706e67a33a5d2c86f3b6591867f12f57a1dc5dc930d248d2bc14cfb8b6d9360b49421334ba2f8f31aea7241f7d0e8f667befac5fd94a888399f22474a7f5f524b09ebf7b0d70a81e47851d8c29ec58166330b6a9b1a9400178fd43ff120f6db67898fb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x65617a9d686c9af5a2e54b1e81b5a3d968a6efa5582cd6fc48c3136903b3879c66de32af23e7724c78a75798b90f2ef2743a9e041e89980aab6e0b6065dea503	1623654050000000	1624258850000000	1687330850000000	1781938850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	389
\\xb2ab68e3b8af2f26b83e3e9327dc963f6b8f4216ac7e2db222408cea76350e2078882cdb1eb5f30b35deafdfe2ae1191d0519671a539b10132396426bdf58643	\\x00800003e8b46b918cb108dfcea93a4ca9b0aab21afa76e4ed764afb0f88f2775e0a1b845a21d716ba0c9e496c299c8c647dafefaae1fe2dc7c7287752fa2fd15853726ab27c1700397b25c8f4705254622491e6a31f8104b6c3b73c4a8bf187f2a1423bfdcefc5aa092182e6e02bce0b47038e9ceb2743a086e93bba8ab41d36d065fa9010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x814a9a4defcdf6a6e4503ab928cb4183f785c293675b0a9a6a43d1f885770614323f04de69924798dc2c18ea74379d87bd438badab8e285e0a05f9de89f3de08	1612773050000000	1613377850000000	1676449850000000	1771057850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	390
\\xb34f3e99d5c2998680668390ab0ad6b83de12283366ed947765adf345e94a1c80b45553016c89e5842dfca95132518896588ff964d2c5b3d2d4d4adaa61475eb	\\x00800003f1caddb7b0d0943e2cbeaf6b22c13766b9835189deb47f7d094f4e9a3d1483129645c2502711cc790f7531c7bd0b2b0eada0761b85a579cf1fe4af964f436076af8d6af7ad6b5cac8abd2b36195a9413dfce0fa16ea16159e74a787411d07ad4ad364e5503e948de26d6ea8c156348b98a2083b748c6e25bfc680bc1e9c35267010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x34c036dfbad4f04d66b3ab330a6d3ddb24b0c664920b94d07d6ea3a45e9ea1a6d7d337dd7bab948f7a1f44b7299f51bec62c65999a44b2d9b12dd30d94145003	1635744050000000	1636348850000000	1699420850000000	1794028850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	391
\\xb3c7bce6342e22ea0fe55c8cc5ad30ee380b40c1b33431a87a1e0deb5878516fc74e89018351fda80006f023d0582e3f89ae986b459dd1dc18360a270e970173	\\x00800003adc979bbac2a115596b64ed70d2de3a6530facdaa951b43a9ab72b8016cdaef8ee7658800e2f4b6990ae987411bb276da5b9c17ecb5ffd91e4f7b8b67b1750daeca3a5b041f705cd53c88953da556d4d5d72c4c39a407b18fb77b2f147399758776e74b2cd499cb8416af6b077e803b5d23cf15fc213c64791efd078d04b67bf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2066a9c0f51b7753c766de47bd8c795085876ee12ea648f93ea1f6abe46a7f23fade3253c54362636b2c50fc5ac7146f7b877bc6289716e7e790c90bedf83f0d	1612773050000000	1613377850000000	1676449850000000	1771057850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	392
\\xb6df46b15ad89e1ef76121beae812f0f6ccdb49746e99f253c6f4a0c1834d8f8dd06b790f9b05b8ff4ea57360904fa16ffcc1b7b248762da265e21a50cf1e45f	\\x00800003afb15b9d0e15d27d23d13da6d420f204c908a08471a3bdb3e279137c65d9fb93442fa2735ce4a8579cefdba38f109cc29758e48e0fd60ec9c9b2526b160d26264a1e19a46bee074fbaed40e0e996c71284b8d6b1d0cf6bfe6b4b844cbcbb226a4bde482aa7eae58b5c93b3dac784647a628a754050fb5dda3e8543b0bb831589010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xde4fec114a6d3fd39bf6d61241fbf0d04718e9b3ae6be65d0ae4f7b12265dedf99dd9108c8772ee69df583f2b94124a714c6f8b4b74b215e108acc829923c70f	1633930550000000	1634535350000000	1697607350000000	1792215350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	393
\\xb76733509ac63e864e339fb634f3edbeec5356a8bafcee7129d0a0530577b851c7669bdb62e6f54a3015188b301fb681f8c964164c0138111e2f0cc0b7440c2b	\\x00800003b2eb0ddbf4b73d50ae8c833bcc764ad240299f5717dd867bee13d84b29c4cec198701042d7e13d95f670533a0dc3eb9ef185d42efa2d731532e43a890d815b8e119b70dd760a9267894a8eec92f9a3226ad43ab1695c75d7a3f2cbcc6539c35df4f9d567397a9fb1350fa3791eecf3e28d96292347a076266606b6de92ceac17010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6dca0953c4ae62255702e89263e798b23bef66910709b3410c2d706a247e25f31082b0ab5e17fdd10ee1c07977cf820b0aa0fa3f21fe3eea6424811a317a1107	1633326050000000	1633930850000000	1697002850000000	1791610850000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	394
\\xbdd3758f2e195f2392a723f275efb65ea5bccae95d9a922864962a646668be01f3d1f047e626aba1f7346ad05d90242a87f211acf67b66fa065b660923c8c5cb	\\x00800003cbd1ac1c1aba7adb2f59998263bca6d5baf33e3d6ee51addfece383ca2c7a9bbd6efc40b0b2a255c4a4f33b2353f2e3fbe7e85071fc001a917dd9ffacf5eb5a1f0caae1bb7078dfa868cd45bb8ff35600508cd16f47be3300ce01b7d21bb70152adaf28917e59de6af837763c1b71059291684717c05864ec1d6c6303edb7a65010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xcde2a1fc739e6fedc25070799b91ba1870023da8d1ec9cd8a1503c233e4b856c20b54657a13374fb73d97838a4fba2d89eb40b68e86f56c4e42148c1065f270d	1617004550000000	1617609350000000	1680681350000000	1775289350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	395
\\xbfe75af43722942d55087e7c0840bbb6026695debc4efe148d0405a84e572bbb51c25671d6422fb9f615aa1f97ba606a08fc620914da6e551192aa48d15debb6	\\x00800003ae27b009e4d6ec3d01a055014d7154cd133d56896e7a7a84ed75b59842ca0e76a2431c0f7b89b354d5b778e00f711de8e0499e6c0318212d30243db6d6b7925a7945cfab82b3b02ec8235528c4b2d4ff1a3501906c2c1c99625c26263a5421937377833eb42385cfa5b45c4aa8a30e24f2768bdad202d153d8506d68e3db8175010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x497c506bbcac7505ed555d1a99baa6c346566c219341924e7f96e1959b3d68ad8d4e3378754c5849dc405fbf4d95be3c2960a1aad2b10b7fa177f5e290b9970a	1633930550000000	1634535350000000	1697607350000000	1792215350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	396
\\xc07759f4c77f7085616c1d8c0430aba732e9b6425ff6d20e4dd39bc3d17ab0e9ffdc5d92af59236e654b03f8d4f3fc8c9cbfe0d2e9f281f991d94376df500afe	\\x00800003be0d1aa78c62dec765829080ee43a6ad3e983d25fed32504e44b23c8c6fe85ca7512e9c3b9c8b902e83880ea36d31a08ce85230353bf173cea0a1faea42c145c2197344df47cf793adfce7177eb0a1d21e6457b1d9c1785e0f3848b089130d2edcbe768a02405a52f0f9b49d284265fecbee47858674c4b91ad6f31e90e69eeb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xa0affac9daf67aa9dc30cd32b5f624bfa12b54963efee1a8b6df7b9e626c9816d9e08c8ee6a811bfeca14e84eaaf325d146aff9b247255ea0bca8de9db5f3b09	1636348550000000	1636953350000000	1700025350000000	1794633350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	397
\\xc457c2166a6709ca81889dfb4580308e0a6d57a9faf5656492b616cbcbc16308cab56a784d580badf76b1082a1a92db34c6f1a85f4540143c34f6f55ad37cb14	\\x00800003c8f8e4dc9eb86896ecd76345e5dd2fdb6cd1c5af43fc55bf969bd19677b099743c7937edbd01572a9eba48be2de76fe7bd4605403a911082eb077cf25a47e813cc1b36347c0ffabb880a39035e6fee5050979ccd869a4681a298cf31405ac6e4811f6c12f61192420335f62f556fefef3d2a61e696d02ba7c6ae88fdbfa4b57f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x6095740f9a98d897032e448d82e785e0243379bf89d6558d7e9d1957ddad250491f1f1e0a8fe0cdf12741659001dd84f68188f6ea394f34ccf5c73c21956d00e	1621840550000000	1622445350000000	1685517350000000	1780125350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	398
\\xc7435657cf9af6029765bd3a69988595e83113cc2d0b255a23bdef2d0b3704a13414591cef3875679921a55dbd4ad7adf8815e1af3692ef62f75de5cc7168d56	\\x00800003c75884b283551e8b58fbb2b05219db64941f8357c99b0aac08629a39fd51a41f33642f5fc44fba057edc4b178a7adcd3d1b0fc5e24d1438783e2a1cc160786f60d3d0185090a6cd38374e267686748faa32664bb0898690e4a0d761f291244ebb5ccc746d36097ee31d776795345fcf698f5a374566bf602cae492c2e8bf5fed010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x22b00b28a9d4f6e5b328235b4b130e47a1b5839345a3ee3ea3a2b0dbfc79638bf939fb4d980fd1b538fdf17f2373fb67dff1b6bc27fc89478c6e9baa7af63f0d	1620631550000000	1621236350000000	1684308350000000	1778916350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	399
\\xc8f32b0c34be145b66cd32840f6f7d5b99981dfd399d8a6e9bf31e2c952c8c3f0766cbc432d35bb4b7e28832ce0293b5edea7e99fefca1260071ae2801b74212	\\x00800003cd976ade4d7634711672c8afc68f1fca0dd10dd335fc7bea14025dfc4004bc98f18441786829e7b9d57a4fd04bb00179a8e73b0286a3e56ef1ec5ebf12bab0c01192b10cd1b243471f9eb111e06b5b65e4bdcc8723e52560c50969500aedc2f451e38eebb057a3cb22956dbe69e24877621ea9b2dd8d41d04c361d0fa5223cff010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3ac7932e75af4a97e77bec0075003570bd4d04aeba3e8bfd0129cf47fe95f34b58481ce310231d30fe808e338edd50e5f04c0bf743555d7b410d2e51dcc7bd00	1637557550000000	1638162350000000	1701234350000000	1795842350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	400
\\xcb0f1c96d07fb7a8f7fd0a4fd3249a1cc0735fe1db817e1a9f958708446b0bb333620913b8df4c612d9cea55f7ff9161763896fb3a5be4a3f99ee671ebbeb699	\\x00800003bb2be9ff387a3eb3f2fb4fc0b15f7add9f8712f1f4a7cfb4bc5aa4b680836106225492b97b36328fef98301f401e890b9006caac34390cea6b18bec01a065f6c050eea0a6c9039436b62be8f287c5798885edfbb19ecbab10e2fe92b4edf2e267b08b05d1abb0aaec16927c07832b8c5e51d4081158d5c5539d87d14d7d5d19f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd95b9616d6ed146c58fc73a9b9709807bb605e6a2acca26411f2a939e5f4bccc4d945920d6ae4ded4a987ded75e72844325a794039493e4f1058c8d459cf8e0a	1616400050000000	1617004850000000	1680076850000000	1774684850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	401
\\xcfef785fee09ec84620491cd05477f13db17bbeb8488b90d4a280a3f09d4be0dbad06e4248b9e531b63b8d356ecca3251199975e21c24d28085d237880a837a0	\\x00800003c66468ea66b5bea7a51d9172388ee428355de062234fe92443bbe59b4902c211080180820317546559dcb2522390d1635cc237981902d48260e5facd0b1dae3c445fab038a203b0239ce2df20788c06de0d3f3dfc68dde9e9d3c8106011c93411de96c448f76e70de950c846a7dac912b4883519d3e8171affd90fc9b7fa64bb010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xddd96e03ef887cd6c3e28273e6197a156ceaa4e586b926a503e4753c1ca3ce6870793b846dd6d0b360c5f16fc09c64f3160c66a325ca3c86745d786f8b6adb0c	1619422550000000	1620027350000000	1683099350000000	1777707350000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	402
\\xd2279cabaeb024546e76d31ada57ab2e32de3fd148c709759d686ca606fb556cdf0589b09d80aa14d04ed8eed8865515bc868314c39340c22bfbc5898cdbd058	\\x00800003a3f0c72c411b6f7324f05f9d42ba4c0db1fa7a72169c4c527b3f714ce26543d6915c882190096508c1f6051c542493a566a1b64a91260e79163945be3273b449922456edbe7459d0b7dd62b353421317f7b0266608d0324a7a1e9992cbab3fe115773b9d1682a057cd1a586967974eb0f0b1fb47e905ffde2c17238b93ef9cb1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x2a85d9bb782b2177150c384a376e08813efd1bc863d9c1adf43bfef1c398235aaa7d49603c64ee1faa61cc914cb3f5f606b7933d212d055dfc6913412ab7350f	1640580050000000	1641184850000000	1704256850000000	1798864850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	403
\\xd35bcb9a39e302a15e61befb2098e5eb2b38237c214a6c062b684f88baa2072b4988152ca6389dcce29ede69d34ef169bebc03998cf328944b5cf4dad0c45a0e	\\x00800003c231cd039ec3d4e8d1f05336a8de94a2a40102789b4da3947f1bf60e9b1f74da025748a78add5c965723f4a9dbba5090116501c766cbd08cca593d3679fd3a0e5aeba3b8a1e7359db8d70c0d087218043ecf8a822f7c220351a9089309287239237197fa6cee4a925c5b5363d827dae92f0ff0d1b3912b311f03db9b77079c61010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe43401d6166d85297d3a52b61ff6bb068e2f7494d9ab73d74ccef471d86030023dbee744c47d038c1a200b01c0662ae5b2e95ab0ee53ad7648f1651a3a678403	1617004550000000	1617609350000000	1680681350000000	1775289350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	404
\\xd5d3810a2bdd351697984e7b818c7e8fab9c620df681dc302e7a361434bf5949c173d7de2c005412e1f7a1256304da12ef2a8d240ad0775bd7550f34cd6fdd86	\\x00800003d796fea5668b5bf07c09be8709b4d6db48b7bd9ecf974070ffd1d057378b39ad37080ed286adffc1607144a1ff7d2fff1f6a630c1c055e973dbd6e92c56d38ba9af7b580a94545d910c86641ca110525b30960dcfb2b964c8c8c582c2a5218eb3f29f0dfdf11e6b379f8cf39643723fede0f71fc520a674f12c5da52a856fbd7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x981327586ed1514a5ce842dfb17ebeab032a5d29ac94199bf4e0902e212258465c83c6f2d4d18f9c4d49065f67b1e824d70325f811c596e7996fd76d935d8f02	1613377550000000	1613982350000000	1677054350000000	1771662350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	405
\\xd63b158b67b53cf6ad15092ccf03124fa8898638457811790ca7afa7b637a89cb880dbcb718f8259be8fa75ee4f3ef067a019a0dc046d798d9351a064bfad291	\\x00800003d8a88525780958446d0c4723cfa7283fabc8c67fdc8a361a1e96fdf1132b3487322c54a72d557a934bf057be8b4656cfd12ca2a096b984de9a6a577e5645873071a7dcc96aa943d778ad0488e339c7dc8707e8f1804480e8aea50f7c10358041e79fc88c8ab3e211a5adfa4c3a469bb68a4446c0c6db333abed46f81e3953c21010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x4a5739510ff3ebfd5c7e5ea1be85e417051f5fcf5cb2a0b1c54af7b8c827a0531d862562a2eed5c3abc47bfe944c6c9eeda12b607c722f370f623895ec9f960f	1638766550000000	1639371350000000	1702443350000000	1797051350000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	406
\\xdb4f49b9c7de213abea440d71259c3ca1815f87dd2413886418958bddf20006550770442db954dd8b2542840b2722ed386bf71daeee2e32a99f1ca56bcf9bd30	\\x00800003cdd3bc819070b680a2467ef9120786e4777e8a342e89e215148f804a23bdb180921fe789891e983abff6d6f51d9307ed0340ae956abb6902040af6a34f15e3bbe9f8c80edadd433dc38ab87defa555bdc91057809b961633c3589c677e2f320e83b8d5c0686632bc49a3483e437872ca706784aa9e3ecf2ffd68b256fb46ba37010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xc9c937e23dda60efb69e8e2f4e23cf246c6bfc970bde5935585cf2eda26f88c04f4e47de3bab13d9fcd597dd17c235c46ea6847e78fd57a3c7104fa98971d20d	1618213550000000	1618818350000000	1681890350000000	1776498350000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	407
\\xdc03e1ca018b99749c2af4691c61ab7731104b4f4913fc3c7183d820cea8439cf5439b526c05d270d6198b7c903553deca071d42b5a09c0d408f53bdfaef931e	\\x00800003ba03140f702a054ab65bac4e7c63bfeffb61848e352a9ae6ad5882a2ec71da22e3fb19dcc56f8bbdc5788b72edaaf1db725b7150dd37ecd20fb3d60b16c3b78b3a235d051734cda35ebcaf1e0cdba50448e45b18dd9b848f48b2b0c244877436a9be019437b9296a523306207eabee78d90504fe45647b2919bd574624194a6f010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x5f9220e6392a31672cfbf26addaa892036db2c7c940eb396a5c95d4509d685ed115dcff69455dd85e72f9f7cda2487363690e8cf46620791377eebe6ad4dd209	1615191050000000	1615795850000000	1678867850000000	1773475850000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000	408
\\xde63ce8e7ce9b00344f10d5c7f891721753748237fcef18d12b32450c9273177e60b259d5d2f1fef80338032d8b9be9d4388534732b96825298c994053aea680	\\x00800003aaa65ccd60bfca2d50dea6c0f3a0bf952adb0cc02482ac62ff70b1e33400bc532e448ff9b520bef454b11bb99eec8a426af47964d37f14ab7c87332920196dbab720d6a7143f8c056f4f302a9cf76e54c519412e49446ddd22a9fa9e9d50c4e051a13219b14f83396285c64b44f52c4a8f27e7c98cc0bf197672d5d856ae1fbd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x676e11e13b450992dacd35323af3e527ab87dd94bb007cbc02792a254786ba87b6fd1fefc683b8aef2a8f06e151ece8b891b2e1af5a61b1bd9b600377f700709	1639371050000000	1639975850000000	1703047850000000	1797655850000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000	409
\\xdf7399bad28d84c9fc1519b00780784550718166944ddafeb69839e8551749dc95057fda9c50f4622cab479dc42a3c60c4d1e81b67556b74ad688371cd268f85	\\x00800003d58090701420d4ab032be36f72a3d50b73b941f1fb490ae78d9d439f1e25f22c99609a5ce1242802970af125bcea70591e9499061e79a2bf6b0720cc33097144c9bf0a5f5ab8b383f00768729fef56c4b1a5b5c0056e19aef15d4929bf2e8841697bfea361aa477ba2076f6aa35661388dfeedae8c5409f0dd679700055ca625010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x45e2c1da1eab72b09fda8425b6f4d876f805fc4473250927596f8315813306d096b7edec4f20cbf225a613a0e9b954659859e433b65b7603ee024774d28e3c06	1614586550000000	1615191350000000	1678263350000000	1772871350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	410
\\xdf67f1a8fa1865eac324e7f25e8486ce261713135b2c6ba432ed9fb0624f9acf1b7b4922b756ff50c034295d880d064432bafacd24d4399f3333675ab2687843	\\x008000039d2a7057a141f5b77b41133eb468ed6e1c5e23436bee8ddba92b292ab903ad533650cb5afb0e8eff90be40fa61abc4f38ce7ecc038d13b450f7aa5f12aed63ffe31c2fdbcbe731897975f832fdc9f46ae3cea25582ed6c2e1a2a396ce2673af092d20d5d2e6fcb3cbfe0638810620d07a081217513d1f3ada5430f7a9fca63bd010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7bbd823642be5b5825a02d8dfba833104d246d40b162499d4d77a1d2e2da56643fb4c50fdd4e161745431b28bc481c13ab40ceba84c290861ae3d4700178770f	1618818050000000	1619422850000000	1682494850000000	1777102850000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	411
\\xe13f6caab1c3a7c5d33396bd7656c3ce0774356bda305f892668ccb292f41e03ae290ac3c339b2be1c4ccf8ba6261f5a14b59457d0d0aba315e48078ab2ff430	\\x00800003c105f683e0d6f6f1841a7a9081f84b6973c67dfd70998927d75f827ce41d9e4c8dd641a6d7da898824ab3a75fa6617fff637601ada1cd33a77055316e67727fa40536988bc1e7fff0dcdbb5e3ccebea82a180a8c5b257e914f2063f5af2e8dce3a00d42c6045daa2bbced59ecb61843f2252c6fcf1c0be6ba523814286697bcf010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x8b1a62997ebbf78db9e6d7f48e28226b42b33c023f3528245db03b3de9ce0a0a4dd00e6d652579a82c59d4c009e13d436f5d474a3b5f12bc4e9a54b29ca9ae04	1623049550000000	1623654350000000	1686726350000000	1781334350000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	412
\\xe3c3f0c3741fbf6434f4faed76868ebb5558d7655cde7a3e59e5d808fef7505201823c99bfa66a05edc1c1b1e820a1cfc50241fcb083870eaaa6e03ab1a3bf77	\\x00800003d10f3f88184b8379b299dd5e9fcb6ea730bb3ffe5b3b77a3dea907032db6dce98a7d545fe435a5f91ce2de224727e1644f84c05abb9080c154e2c214f1cf4661ec9fe2ab178b7327829c6346131e1b4ffd83ca47f3d3aded7b5519d508efa6d1ec4fe926c1fcf63754720f0a5926db7ebae36c36c6cdf4b5442282c898e4c8b7010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x55f4606691f17d18c6a2728d91e84a5a343f79e74dbc482fcd105191dff017af1e372546fe7049c155ee834b97a37ed7f5182419dc0cb217bfc308776bf55900	1625467550000000	1626072350000000	1689144350000000	1783752350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	413
\\xe49b77cf069b8f2a7c29300136bf372f4ec36196bb4889cdf7105216de593b37b26dc52eedaef3b8f5f0dbf70a57a5eefa7cb18a9b00c8827b3b8037a1cb8ef2	\\x008000039a74f4008ac856601833b9c05ac77adb6a385848f31f161934d819b0a6a4437c70c034f2fba8520cfba5860f85736d7618bae4d6b02ef7ddce58353bdabf0d6c341ae84c757bf19d476db3b96d5fb38cfc4b05439c41fa6c02a8f38ece1f7ea952612a4ea8a98ed6c967a958f681430648825b3340b5c507c32437e65835aa27010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb0ba09671e78d65df6352e74124d70c0ed553dc481577e1808e221438f9251189ade6f513b700bec704868c318f8d8fc96132ff839ecd9b2eb2f57cae260160d	1625467550000000	1626072350000000	1689144350000000	1783752350000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000	414
\\xe5475b8236d47057133cfdfc112ba5beca3044a4e2708b7216147ed28b259c2f4c6848c5c34f8de6523b3ac598cab6b5acf7d7b61e942146be10b0364295498a	\\x00800003c8cf2d190e6efa6f968bd413579c1bc3532a9d0f66f2ea92eec20eb03c75269998c0cb52b247780d106b4bb03881ca19f6dbd27064a3c0541f7bc605d1be1885b3ed53d77460c9a08600afc9d48c1c60fed029c9f9cc09d6dd616a678eab59871428ea04d98b4490b59f7c5f0396d44a2c078598fa0725c36aeb06a57a50de33010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x7dcaeffeeec8e90d40da26cba0178b394aef95851df3f8e9674a2b4876d5a5455880923f50a5e4b7d7263bc37ada902b91ce61331b31ca1b0b706901528f1d01	1641789050000000	1642393850000000	1705465850000000	1800073850000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	415
\\xe92b669539e8257d60336680ea4a0242eb59da096efccc64fb9b0c7f094843d31d8c17766dc5c6193e124bd0385e0153280b7badf63672ecd1867e7e1f9f3fcd	\\x00800003b497f62459a2d9a616586206438344995bcc85dbff6d2992e7835cb84e0a3650058a1b9a606155fdb970e2e8d120a93e5b4d7715e61cb2f2fe1a54e2f825c9c24403e0039bb1b4524c0c44b8aaaee0e441a58a53e72f46aed67959055962042521a4b76dbbd95fc1d3a69b3a8bac1c895437f2b9b4476f013a1b1f4925d80911010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe239bea31bdc0886ec5362d3376122859d664540223987fb1dbe9384087ff7483cd7391bc37f0f9f024ab2e6b1d39cf340724b0fe20814659946de3840e94801	1620027050000000	1620631850000000	1683703850000000	1778311850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	416
\\xeb8fb66e45ed717b7e7234b4a0f22b998eeb8adb75d85cdabad7dcaabc942c22818654f13c9cfdeb129bad4834c4e9c2c334610ffdab927d16b93c1e9786d319	\\x00800003f43ee48c80dcd3af7fd3bfab22de3a9ace9a2fff05f5c7e300af6c978b5eeadbb21c9d9eb7117b838bbc908fca3741da7f8e20566a53a434d0b2ea4fc66b8bddf571a90050d4af8503e6df71023f51a6c9b1cb048f5410cc53e6564ac1b68453cf6f5f33d978b132a11daf3b91a970704758deb73b035a675c3fea8479f367b3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x559756aa206f0200582387a18270c9682b14f2b3b18da8269929fbd4bdce3a2bac3f67b1f118e40100f708f948730a79a2f1b178a30b65c20eaba582a7d7e106	1620027050000000	1620631850000000	1683703850000000	1778311850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	417
\\xecf7c5acf6d4414bc31ef014c84f5b9178b2ca15389ed633893f7600bb0d611fdcc4a01e567b1bd26da02a122a21db32c22da137efb1ac6ecbadda43b1fded6f	\\x00800003cc6d027b25e24efb81bfeb0d3cbcbaa0880895d70e08c219c1f596c9d29a0575cdf88d3b01ab598346183b5cc6acb4c689bf091f1f53399f442846a669724d9ef40ce941fc1c0fc8e3a79ec3858b60269cd4d7d4a6ae2a7070d00e384c0ef092476ad315eafa5f89aa55b1d09159ae5692c32879b81794a020ef5c70e6babcb1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xb8fff810de6479c02ade44ceac2bfa30b1f4b0fc440941ef2057e0d87a7a1213dd61734d8fdeab924545fbcee39db17665d94607d4063dda9de0caf6d83a9401	1612168550000000	1612773350000000	1675845350000000	1770453350000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000	418
\\xee570a00034391ffbe89194b6535c4970958a9b6edbc91cb07731f856d07f4e7e1609c4c262a64a5b2c571de5329c5ccec5784f0358e5023f8f0003a0341544d	\\x008000039b4a21be3c23f73026954c324ac999e1b3ba8a31548079ea8d48263424360e7a33dd3681fec29d9579c5192525fcff4fda41364375c74999f885cdb5a2232bd32e8592e2cad385a084b43786a509a6084cd2aa565732516bffcb0c75e962d55e78b6a88d2fabac761672e9b06b9ce0bc5ab40ee0588daa540540c251077ffa29010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x56a98d80b79c8746f10e0be2485880fb13cdc483e639b4ce5a19374bd92c0b87c20f581f1414f95c73842b8a5ae983d0a12a8e35999f4ba10a4a9cd1349d7903	1641184550000000	1641789350000000	1704861350000000	1799469350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	419
\\xeee7af61665996140373dfd93659d6bbad6ecf9a95644320adf314467188876e7f0b2d5cc57d55c8ec1f5c1d003e6baac62cb1d9bde848b89958ece60dc9c75f	\\x00800003edb67c61de11e49239a4326036ece3a8ce4cff5b9fe4b597c2aa7c1165398e840358b0ca4285ca604c2ca667077456923908ab96f5918ee1fd930eefc55f656aca7e302867a2f6c70c61ae1c4f635a8d9e101b544b9138a5e637c60afcb156d17b5cc8af7a0e6e9e795dcdff54948dd394de445f3917a05b1fb0be14f11c5a3d010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xe99fc59fb3db5523747404c5250fa3321b5a40984727d148b97184c9c1acba707fd51a1200818982610ef307b091d2a1aed04f768979e899f48a7242735eb407	1638162050000000	1638766850000000	1701838850000000	1796446850000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	420
\\xeec3f3f49bba304a8f12a2112285d53e3fa3b5b74d48607a0be7be9529c86fd1dfe20da2fba0e2af0c2ad344227743b5869abb6046b1f3f7c9faef25c1b0716d	\\x00800003af39433610e95bc61dfe2ef6d42f4de8c39e842c80fb5aaa7e453e31aae12cd2c2c9053cbd056b164b3061a9980bb77a9b61403bb1868d89ec70d072ebff6019ed865beeae409e52ac7ddc83f8548faae2393bca7feb120f00e3f97b630e9597942404003cbd21c771423515c172f037d9280e772b08dc40cd8e5041ff09afc3010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x13cc9f724967157b6ff92928a0d56c2878f7cf0640f865c4b892d2334934d01c9858f57c3facdc2c5bc2e7abb217a7a6deea1211a3e0ab6ac79aaf1678ef5b0c	1624863050000000	1625467850000000	1688539850000000	1783147850000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000	421
\\xef4b5b888f446489e6c56ea17c6666086f23253727baba6c0a860339cd5451ef6a1cb7553d015c1bf15bc809376aa8d797ccc07695e164b529a397cbd40cba40	\\x00800003bf44d285cfc0cb8b0111099011c4c1377d2f2fd1f178146dcf19e90a86baa70df886f0d782a26a0ecc62814838a8552fdc1f38e5372f98c99fc7a2faaec6cbc0de419c4b7f59d1a0f665c0eb985dd406b76d7a4579c850ccd5e23c8d4a1b84d4c2ade4cfd671a736d269d9a6ecc8850e72354d8b3c32aa6b6d2b67df645b5e05010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x869b69a41301e00085faa2f9bcee5b436ff8f76c92ee387d0d759ce66f7ee396fd941211ce889ab8f3fb9d0387e03227deb66c4b9ee2d01109d7c3c0014e2a0f	1612168550000000	1612773350000000	1675845350000000	1770453350000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000	422
\\xf47b56abe346b92197e3d05ad93a095f8a2b8694d56f5e364ad6776110b03f4e62880a65284c1d1ab699c5032815f319fa0b46660cfd3b93fea079b898cca568	\\x00800003c125976605f481667cb3f51c369ad72178e7ea5c4d4ac27b9740abee0e238c9bb9374a5cdb1113f642d78a27a33a99e315cea4d1500f68093324ebeaa23237a7188ac4dbe3d36d17a1acedbc74fc8c9f27067b2c4d74f1cf24bca028bdbf295f3085258914064eea4e344122c09f2d56974786096aad8f8531f73fb8b0b631c1010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xd38459ed1d8a443d627d6c0abeae73ee9d99b3c95dd97a879bd8d17947db41feda72431993ef42276bd3913d524cf2fe527b0926f47563cbcb80bfbdcec5aa06	1615795550000000	1616400350000000	1679472350000000	1774080350000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000	423
\\xfecfb7ecaa1c53d18ed4d801edcf8ef11db5a608066d54889ef94ee3001eb3226a74bcfda54d9e3c3f1b25ab6d3edd2007ba0050c9e0149a1db717f602e84a30	\\x00800003d4c98da1b4d79d7e81d6fb475824ab468cafad03c0f0c26a2762110d89506de0742cb2e7f1214dda9fb8685104369513f7dbe384419deca732456b7632a0a941eaa635c5faccfed3d67c03f828a5c7ad1a372cf4ff4ad6cd10028cb6a618ddeabcb50877ec09e0f930d3767dc77b0fb15341cd4df8aefcc75267699c15c491b5010001	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x756526ca8d7b4b34c1ddcd10921113a4353cf81ed40d182a93980a2ef9a9e2be2075493cd214703f7719684f4bf0f705fd06f35dc4ef3b16434ab991d14fce0c	1640580050000000	1641184850000000	1704256850000000	1798864850000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000	424
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, exchange_timestamp, refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	1	\\x0ddb75312662ab63ecc16003666a47e6a56d971e6609bf006b3e95507f77ec8818b8b9464eed754be5ccfaa779c43b2d00105489457517ddb4937eb593a15011	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	1610355076000000	1610355976000000	3	98000000	\\x646f301a00b12420d8bc5b6c8cd52a0714a3d5f52272181bf51d710952c6926b	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\x2098e63cefbffe44278ef3361b42946a1617c9b291a38d68e389913f250a994e617cebbb5d5e643ec5d1c06632b74b5aacd2042ab52a880e8c281abf4143be0f	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	\\x299e663701000000608e7fc9357f0000073fa73ccf550000f90d00ac357f00007a0d00ac357f0000600d00ac357f0000640d00ac357f0000600b00ac357f0000
\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	2	\\x21a27562bc99c3f9ad0645b80c06091025170fd8165e5c7709a51fc7f1737fe8da22b00e54295c4ca72e3486771388c816608b2e4821c59f5a56bb853244307b	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	1610355084000000	1610355983000000	6	99000000	\\x223b13b12ab3ae81a47b2bf7d78ab50e45c1c3d82d674d0be4ff16d071f950a6	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\xea7fe7e3368d1669e6e00530e0b4c80e47b7e4bf9c0048f1e7fa06ce6e7b68e2449b3e94e190afdc615e7fbbfe642ff7333272a1a0422c283875c62b82124208	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	\\x299e663701000000609efff5357f0000073fa73ccf550000998f00d0357f00001a8f00d0357f0000008f00d0357f0000048f00d0357f0000600d00d0357f0000
\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	3	\\x58029ce22a69b90e90ca40f9d144f1c606d60ba7f824fdf685222b91a5fa94848e6d085cdc604e67236c800884fa3b3d5203eb32a5fadfca3c73a6e41e9e690f	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	1610355085000000	1610355985000000	2	99000000	\\x3ca6f451be76403a038230a2c0c8b52a1399ff3c9551e2af24b91d8a09d37746	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\xc8414ee13b3f22462f8e0317faf5d02a38b8da298fdc76f6bb009c4e708ac2371f3926753d948a138e3d5f17b268247c0c8483b3c6566672cc9eadd786553408	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	\\x299e66370100000060ce7f13367f0000073fa73ccf550000f90d00fc357f00007a0d00fc357f0000600d00fc357f0000640d00fc357f0000600b00fc357f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done, known_coin_id) FROM stdin;
1	4	0	1610355076000000	1610355076000000	1610355976000000	1610355976000000	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\x0ddb75312662ab63ecc16003666a47e6a56d971e6609bf006b3e95507f77ec8818b8b9464eed754be5ccfaa779c43b2d00105489457517ddb4937eb593a15011	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	\\xe1c113495855f82f5ccbd953f2cc3f56e2c988116e05f67d4b9a46b053c4fde3729438e8fc568cc409320ba9131a64c467c62705ca20eadaad464f7296b96e07	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"MYY786897CFZ28266WWKHSAM1JSTZTCS8532MA31PDZ29TZP97R1EAK8GXPFZ69BVC6RVQQ0P12JT4J7A1J1H597MA30C584E4VPVZ8"}	f	f	1
2	7	0	1610355083000000	1610355084000000	1610355983000000	1610355983000000	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\x21a27562bc99c3f9ad0645b80c06091025170fd8165e5c7709a51fc7f1737fe8da22b00e54295c4ca72e3486771388c816608b2e4821c59f5a56bb853244307b	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	\\x698d77ade9f8eb1d6e379769957bea500cab5581bdacfbac497e8647b02ebe867962021a1f54cb8af71ebed939434048255f23f6e9d3dee5c8ef9c1c19480e03	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"MYY786897CFZ28266WWKHSAM1JSTZTCS8532MA31PDZ29TZP97R1EAK8GXPFZ69BVC6RVQQ0P12JT4J7A1J1H597MA30C584E4VPVZ8"}	f	f	2
3	3	0	1610355085000000	1610355085000000	1610355985000000	1610355985000000	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	\\x58029ce22a69b90e90ca40f9d144f1c606d60ba7f824fdf685222b91a5fa94848e6d085cdc604e67236c800884fa3b3d5203eb32a5fadfca3c73a6e41e9e690f	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	\\x849e93495d79c0efc17e3aed12610c3d1a04e3b778ab75d3b737aec8096b3cbd0180a172f594dc433f28fb9209e018a88ee9289b7055dbe5e06e593b6fdf040d	{"payto_uri":"payto://x-taler-bank/localhost/43","salt":"MYY786897CFZ28266WWKHSAM1JSTZTCS8532MA31PDZ29TZP97R1EAK8GXPFZ69BVC6RVQQ0P12JT4J7A1J1H597MA30C584E4VPVZ8"}	f	f	3
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
1	contenttypes	0001_initial	2021-01-11 09:50:50.652349+01
2	auth	0001_initial	2021-01-11 09:50:50.695692+01
3	app	0001_initial	2021-01-11 09:50:50.736911+01
4	contenttypes	0002_remove_content_type_name	2021-01-11 09:50:50.75876+01
5	auth	0002_alter_permission_name_max_length	2021-01-11 09:50:50.766622+01
6	auth	0003_alter_user_email_max_length	2021-01-11 09:50:50.772789+01
7	auth	0004_alter_user_username_opts	2021-01-11 09:50:50.77815+01
8	auth	0005_alter_user_last_login_null	2021-01-11 09:50:50.785614+01
9	auth	0006_require_contenttypes_0002	2021-01-11 09:50:50.787331+01
10	auth	0007_alter_validators_add_error_messages	2021-01-11 09:50:50.794196+01
11	auth	0008_alter_user_username_max_length	2021-01-11 09:50:50.806699+01
12	auth	0009_alter_user_last_name_max_length	2021-01-11 09:50:50.814112+01
13	auth	0010_alter_group_name_max_length	2021-01-11 09:50:50.827639+01
14	auth	0011_update_proxy_permissions	2021-01-11 09:50:50.837697+01
15	auth	0012_alter_user_first_name_max_length	2021-01-11 09:50:50.845105+01
16	sessions	0001_initial	2021-01-11 09:50:50.849608+01
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
1	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	\\x254979e46fb63853c0cd3a0e81e13ea102fa808e694b4f44497b0b7fb68784647c9de7780790726214f695ab6e838875a58a492b7612ecf4a518bc8982e7330b	1610355050000000	1617612650000000	1620031850000000
2	\\x43080946192489c44a40d89c9b7952429bbf62e4ea9fc331ad78417a0201664a	\\x80c5fad1f2bf11724bc6b7a620e9f2c8730092d7f20d67b5d58745351bd831326098fb4718ed7ed80bfdd5296939504106401af0d18a95ec91d782a171740804	1632126950000000	1639384550000000	1641803750000000
3	\\x52a8664754e374e60f807c16c068de39b32d5c513c0eef4ba75f35c662057ab7	\\x5e613028a5d4e74240bccd5f294b6a3c8b9e9ac5db363074b0f8eda3f21f248b8f296b3b393764d1b4f8f9556dbf5ce6b1dbeecd280e4f4d77ca863012b1b20a	1639384250000000	1646641850000000	1649061050000000
4	\\x73c91410be7ddf5519e7e3f943a5531f0a4129342a68752dfff55bee7ed816f9	\\x257a977590fe7601d189ffc89bf1f9317837518edc9724951aa8a86fef5568d398916970f7be4ffc980ed2f874a1ab01ecafaf497a5d3b43d232236c78f17c0f	1624869650000000	1632127250000000	1634546450000000
5	\\x3e69a04f9ffa3e66606d47f4ca0954811535bee9c2157ac4bc120ccdd0e654a9	\\x2e49355dbfe23b43068b093a3bb736a95064b221a5a734cb93e66757c93dc6523506e8a7ec330f800d6f6afc3a0469cf822c31f14dce7d1a97a78f32ea3ef108	1617612350000000	1624869950000000	1627289150000000
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (known_coin_id, coin_pub, denom_sig, denominations_serial) FROM stdin;
1	\\x646f301a00b12420d8bc5b6c8cd52a0714a3d5f52272181bf51d710952c6926b	\\x6f78c88f4e34b7cf9f343a089b15ab8a544d546c867be66deb7d71d128529f5fd671b3f332acfd7a3fda017dd198d50c34744081811163ac9ee88c236173d1fd3b2bb37f1502ad7a251d4fc8b5fe1f6f253dfd2113d7135fa07197d92d058e4811ac74698d650513e06b430b196e05a25fae7b6919d24c2948f4980d68885e5d	111
2	\\x223b13b12ab3ae81a47b2bf7d78ab50e45c1c3d82d674d0be4ff16d071f950a6	\\x6c7ca404ba3da8c1d1d652774b7f8c291c4c38604285d75b5bce46bc3d634933e888646c77c54adb4152d2a05e65a8524d887628672a25b41d329420b3284abecb7473e826d3aac4f3b2602ea1d71faa74769ea64d76cb906e924bd92022a9fc6d4bd4d9713d92c1f647ce84a30beab4e3d64bc38304a411e685e981ae1a2320	204
3	\\x3ca6f451be76403a038230a2c0c8b52a1399ff3c9551e2af24b91d8a09d37746	\\x125786798aadcd26d22de892c0eb3ccc599ae0421426c7281a5593fbbc6edd3b972ec3bdc6e98732b6b05d2311c77483a1bb262f7f05facb9bc085c1babda57ae09341973bc43fa763a2132992ff748107ef6cf31ae524219e6123a3f637ab19b18dfb4e2351ad428f3fcedabe6ca19a3fd4519addf00877d1be242a25c0aac5	254
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xf3f54acd1b1725b5eda117844aa607398dfe64a81ee8744bf6f4e3fa91c5fea1a646916dd05d8924a145ecc4f4dd91fabf521ec0792e4caba959accaefe31588	\\xa7bc7419093b1ff12046373938e5540cb3afe99941462a2861b37e24ebf649f0172a68876cff992bdb0d8ddee0b0452d12475064189527a28606150471376dfd	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id) FROM stdin;
1	1	2021.011-AKS8401AF50G0	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335353937363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335353937363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225946544d4e4b385632574a5642564431325932344e3947373736365a5753353833564d37384a5a50594b485a4e3445355a54475443484d4844513835563239344d3532595348374d5650385a4e46544a335630374a424a434e454d4e4b423641585a4848423230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d414b5338343031414635304730222c2274696d657374616d70223a7b22745f6d73223a313631303335353037363030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383637363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22304e5a45354e4735354a50444a4b53334b4e524b545a3344504d4639304a344a484839474335304a35545454514b564a43355447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2237564e39305837514e5648323448464a4d584a4450474e5a4e50364741334645533034445836514a34463458534d454d42515347222c226e6f6e6365223a2258333044355736355044474b414b3251355659304b394535374b434d38533044455130303452585952334e39365a343551575747227d	\\x0ddb75312662ab63ecc16003666a47e6a56d971e6609bf006b3e95507f77ec8818b8b9464eed754be5ccfaa779c43b2d00105489457517ddb4937eb593a15011	1610355076000000	1610358676000000	1610355976000000	t	f	taler://fulfillment-success/thx	
2	1	2021.011-01G89XA95V1FM	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335353938333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335353938333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225946544d4e4b385632574a5642564431325932344e3947373736365a5753353833564d37384a5a50594b485a4e3445355a54475443484d4844513835563239344d3532595348374d5650385a4e46544a335630374a424a434e454d4e4b423641585a4848423230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d3031473839584139355631464d222c2274696d657374616d70223a7b22745f6d73223a313631303335353038333030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383638333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22304e5a45354e4735354a50444a4b53334b4e524b545a3344504d4639304a344a484839474335304a35545454514b564a43355447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2237564e39305837514e5648323448464a4d584a4450474e5a4e50364741334645533034445836514a34463458534d454d42515347222c226e6f6e6365223a224654454b32585345524751323442394d4434544a365145584842384b475145565654304550535236374a483456374759414b5330227d	\\x21a27562bc99c3f9ad0645b80c06091025170fd8165e5c7709a51fc7f1737fe8da22b00e54295c4ca72e3486771388c816608b2e4821c59f5a56bb853244307b	1610355083000000	1610358683000000	1610355983000000	t	f	taler://fulfillment-success/thx	
3	1	2021.011-0049H0MV0D6C2	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313631303335353938353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313631303335353938353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225946544d4e4b385632574a5642564431325932344e3947373736365a5753353833564d37384a5a50594b485a4e3445355a54475443484d4844513835563239344d3532595348374d5650385a4e46544a335630374a424a434e454d4e4b423641585a4848423230222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032312e3031312d3030343948304d563044364332222c2274696d657374616d70223a7b22745f6d73223a313631303335353038353030307d2c227061795f646561646c696e65223a7b22745f6d73223a313631303335383638353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c22696e7374616e6365223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22304e5a45354e4735354a50444a4b53334b4e524b545a3344504d4639304a344a484839474335304a35545454514b564a43355447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2237564e39305837514e5648323448464a4d584a4450474e5a4e50364741334645533034445836514a34463458534d454d42515347222c226e6f6e6365223a2247533350534156344358365956453544413831384a423736314431375644315346565248373239355a474b4b4d5947354d444230227d	\\x58029ce22a69b90e90ca40f9d144f1c606d60ba7f824fdf685222b91a5fa94848e6d085cdc604e67236c800884fa3b3d5203eb32a5fadfca3c73a6e41e9e690f	1610355085000000	1610358685000000	1610355985000000	t	f	taler://fulfillment-success/thx	
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
1	1	1610355076000000	\\x646f301a00b12420d8bc5b6c8cd52a0714a3d5f52272181bf51d710952c6926b	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x2098e63cefbffe44278ef3361b42946a1617c9b291a38d68e389913f250a994e617cebbb5d5e643ec5d1c06632b74b5aacd2042ab52a880e8c281abf4143be0f	1
2	2	1610355084000000	\\x223b13b12ab3ae81a47b2bf7d78ab50e45c1c3d82d674d0be4ff16d071f950a6	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xea7fe7e3368d1669e6e00530e0b4c80e47b7e4bf9c0048f1e7fa06ce6e7b68e2449b3e94e190afdc615e7fbbfe642ff7333272a1a0422c283875c62b82124208	1
3	3	1610355085000000	\\x3ca6f451be76403a038230a2c0c8b52a1399ff3c9551e2af24b91d8a09d37746	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\xc8414ee13b3f22462f8e0317faf5d02a38b8da298fdc76f6bb009c4e708ac2371f3926753d948a138e3d5f17b268247c0c8483b3c6566672cc9eadd786553408	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x609c6774d9896adc68a06ef6c3e22f6e06c44bc7dfeaed37f8bcb7bb9720fb31	1610355050000000	1617612650000000	1620031850000000	\\x254979e46fb63853c0cd3a0e81e13ea102fa808e694b4f44497b0b7fb68784647c9de7780790726214f695ab6e838875a58a492b7612ecf4a518bc8982e7330b
2	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x43080946192489c44a40d89c9b7952429bbf62e4ea9fc331ad78417a0201664a	1632126950000000	1639384550000000	1641803750000000	\\x80c5fad1f2bf11724bc6b7a620e9f2c8730092d7f20d67b5d58745351bd831326098fb4718ed7ed80bfdd5296939504106401af0d18a95ec91d782a171740804
3	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x52a8664754e374e60f807c16c068de39b32d5c513c0eef4ba75f35c662057ab7	1639384250000000	1646641850000000	1649061050000000	\\x5e613028a5d4e74240bccd5f294b6a3c8b9e9ac5db363074b0f8eda3f21f248b8f296b3b393764d1b4f8f9556dbf5ce6b1dbeecd280e4f4d77ca863012b1b20a
4	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x73c91410be7ddf5519e7e3f943a5531f0a4129342a68752dfff55bee7ed816f9	1624869650000000	1632127250000000	1634546450000000	\\x257a977590fe7601d189ffc89bf1f9317837518edc9724951aa8a86fef5568d398916970f7be4ffc980ed2f874a1ab01ecafaf497a5d3b43d232236c78f17c0f
5	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\x3e69a04f9ffa3e66606d47f4ca0954811535bee9c2157ac4bc120ccdd0e654a9	1617612350000000	1624869950000000	1627289150000000	\\x2e49355dbfe23b43068b093a3bb736a95064b221a5a734cb93e66757c93dc6523506e8a7ec330f800d6f6afc3a0469cf822c31f14dce7d1a97a78f32ea3ef108
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\x057ee2d6052cacd94f239d713d7c6db51e9048928c530614122eb5abcf726175	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x50674cc6bcfbe5faf1d4fb62f6e275eabd681aee0df8af0901e73ba3d219d0881baba68ebf1d55584c7080cf5c4511da76456deb3bb2f675b39a5d4bd2bd8a0e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x3eea9074f7aee22245f2a764db42bfad8d050deec808de9af223c9dcd1d45df3	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x158507b2f60206d947521201392e8041c296fe8a64318fe54729c0fa529fbc54	1
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
1	\\x71725e0c0505f27cbd61bc63307e09a47a7ffe36af243a79af6344f5e1505330781b9a0c842289de400e0d21834afb1c0f93b26431bb3608502383356dc0f303	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1610355084000000	\\x223b13b12ab3ae81a47b2bf7d78ab50e45c1c3d82d674d0be4ff16d071f950a6	test refund	6	0
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
1	\\x004ecd077353a3861f789cbf1e48051bf9f1f7fdc5633d5a371ee2d3d745e8e40c536978d6c03c9878e0d26690be6b3db7efcc7848a6553cc0a63a7972533376	\\x61cd9ded7ecbcc0b7119f37960ac993095b4bb726bca6a1196e7b449d83be9bcca28ea00406d803eb99122a2373fa930602db3141861da4e04218f16427b7203	4	0	1	1
2	\\xf59455364f46d213f12cccac4e681888200493c0476d946a756375aefdb6a99395b99a75bc2a0d6e45dc3d35869568be82a2c7712301cefb2e6325974d1ef10c	\\x8e74287672971a69626ec898f777e4160643af5778294e6e849b24241b0081a6d865c48fa159b1a730d4ca04473ab797bb2b49083ab030729e9a6d6f6e9b530f	3	0	2	2
3	\\xdf2643790ffdd66534938faa145f8bdcb2091f7130570288450bd937c6bac78b32480ca7a5711aef892743381281500ccaa8109c0ebb2737079953e55858701f	\\xb1d88f76f52446674ff9819a91952fd951ee1d2aaf4dea9f69e4bb3b3cc9b526650b0db8cdc33409d3d0e749517d35106d32968d520802d0061952c83ad94d0e	5	98000000	2	2
4	\\x3a395d33b85ed1a7b1b34ddefc2eb2a1e0609b5531ce6913325a410fe35df53e767b4acd05c0b224301dacc81bf22d2cc1d2cac574dbdb56cd852ad61892f75c	\\x176a9ed010ae7101f90b5829a6154c76633b814ae69eba9c0bd895ed2ffd70e4cf5d8f5370dfbb5d0c1ad0561f6e826ea3d72103f21a264676a3cafb2663a902	1	99000000	0	3
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (freshcoin_index, link_sig, coin_ev, h_coin_ev, ev_sig, rrc_serial, denominations_serial, melt_serial_id) FROM stdin;
0	\\x741454299d85769ae4a59196b3af679b031b6f704add8f61487a730290a68465d74b1a563df0f767889696ca8bfe793d5ec69440a07884cf1c14fcf723487204	\\x4eb904c31077cdbb36870cc86dd27218f02b825287fe1e49b31c807a6997366e12e5c1ed56f5d052c95b46600e239e3b622f2dd4c63aecd6983b4793b5b336b7dddf5bd426d56ef01770b2fcb939342d015958e8869da86d8c6929bc9b597d597146afc04d4ca06594467f900b1309d628426904cef0bb261886d92248c75add	\\x83e71f000553f36e8650139f63f3eafed9f9a5e104e59edd6ab07d5274bf864da1563211f2038085bc63ed69aa7342febc4510ba98e4dd6bbca52e09112f4e56	\\x1c52de18954b99409047dd227fa7e703fc20ce18bffece432998fc9fb5d06ff05ecca907f170b0042d83531a33ebde872f6a7be4d522cc545b9c2ab3940c4411fa1594922e80f0c83ce3168a4913f4347247a4dcdfcd7b248905d2bce1e08f455caffe2de6d2af692658052f4cde651fcb390d1c12e2937f6d6c3c03dd7fa462	1	165	1
1	\\x1244b09373afaeaa9c647a23be1c7af8fd0187277803ef919017b5e1e83d56223ce5080ae28c6d3a47c2610cafe05bff0b69c354f15719578eab0396e2b37c0c	\\x3830fd5e5770f439ef3e34896e15b606f456886d544b6f5c33d4d62b98457bb70d84bffb2654a84010dfd53081efb423c72a996d3c3551d0d3b1c53bf629f9f6e5b03653bc53305c6eb745a15ed78db7cb169ab1a0d96cb35e59e3d23266795dd44610705388e7de0c850e388d6e8f82716814fd9efe01a98cb9d982c7e9bad5	\\xd1e6d017578ff363033fb66bc6b68d43fe1d6eab136ff5d8dd80547f38b01e5bac21a014d378f26d58ef463506bf067c6dfffa438c286dacf0c1087283424546	\\x87d09762e4e5c103385571b57db27e746b1a31d1684024577df79c6402e47b9fe07212edfe15c390b585b9892423d829403a906dadba951eaffe73fec8cb154098a3e7c7023150030a3a704db06d9fdba215ade04fcfff29904886ac28f9b9dbb4690379a775d7703c6aa5f02e0803dd69a98429b20f7d3135918464b99caf64	2	49	1
2	\\x16245dcb830eec935f5435037e4d8f3a6ec70f80c0ae0b716001bf881cdf58e9855bddf730c7f6a73a04fe8de607dbaa328431fb0936fc2ca8804f123b27df04	\\xadb0f47b56dde21a93e73e7923fd77d98d21036e6b0a3413bfef6b0ea5919f39901167f8bec3fb27f14eede0af0df207b95af6e27de80bb54a84bac351f613b5e79b383cbb7558d7ef4e231b3ccd7bbb9122765093b5810997934cdf1a987e21df9199a1a3bb724a079de308872804618adfbbed9855c2a032bbf99ff6c4fcc6	\\x5c907d5297425755da1dc527d8b034420bb2f0f1f408268381ce679effd74aff40611b8bad9d5191653b0d679b67e6415d98c86badd68f2f5e4322ccdd9c70ef	\\x14afc779f40ef04d76d278e645b2c91b7e2aa7e00680d61d9b384f6d5abd445c1ad8293372155af4a4c7615846a0719738fe05b3d5d43d338dd5fb8a4571fcd3992eb6dfeedc087e2e8963f71322f9bbfda74853c1041c862c7bbc30eff2906d857aff5849dcbb5c2162844d9412fb0d17fa4b6636885f916f1628efe1a980a2	3	290	1
3	\\xd206a53bb0fe56638003e23b76439d49be4e44b643677ca9172b966632130e8711355a5c1b82a85ef4d9ab05453453c13b9e883de094860b3172b04dade25107	\\x17833dbe543e1e46eff6dbcf3772833c942652dcb87b4352168741aba344bfb7cc59de22b6e48b9af66baa03dd70cc8cd93142dcdacf735756ecb4e8369b2c521f1ac56696ca1cf0de7a7271f7a1faca4d5f47886947183e0d1b853db160d615df5cd4769d4c00ce3eb1e6fff3d3f4b6147be1dc216785023de1eec96dbf0af8	\\x6b1dd1e39e098fc86d010e0c6d8edab613b53cc51f5a352a66f63a4de59e8fbc62cfbbc26099e8fdf001b940e9bf0f317ca1cb275427c7cd5d8d54255ab41f31	\\x30e1bafa18b61054b439bab50ef813ef9e7cb60c2ff0977e378786af2ea49340132e7271906537441c88a97ad308b2615779225b646a33ab40dfaa51e44f79cf1e4dbddfde17f13bebe20d75c8a45817732f9271eef7e54913fd9d26719f32c129412d57beb00259aec84d7b328c8c2b1c9d4f0d354bf893591b75d8f7173196	4	290	1
4	\\x13fe545bfa1458600d0ad1f071e5c4eebd563f9eb1c18aea79c5da62c6419649f523cd0435ade8bc08297426c719bc1722a48de35acb2759cc5a18d60758f101	\\x0ad26c2017c3d02d17227a441080c3e30c9a04d15a7e281e6962a7e69e66a64ab0ae8172d346f01f215aa69de3c7d3ed7e0333682797cf8784c85c81c8fe45ca74c4859d7feebab28ce10979364d604ef4e4cf634ae09a6df7ad535fec8a0d22cad12e09aabcbab5984f3e07637aaeae0a5e6a4a3d7f9498270e362788d38dd8	\\x28a61026f0205ed4df74ef9be5422d3ca57e03059ee8a9c5cc04a9df5a9fbc2114e16b956be5946d56e0c0888f7e54496cfe7773a76454abf096e2094152570e	\\x4bec1a15e74ce0f2a14e3b18b3a3424a971a6d5e479fde7d98094a90210591af758e51a74fbb9df8f6a35d2ed63804f0b821137fe1fe84d8ea9e1581bc9961a9f4c02901181f59fd0f7e7a69c09c294f09631db9ee9e4140148d34552265a20094d255781afec12ed94b8ef6b82bd7594749b1d1754c48f4fe2870e02540b36a	5	290	1
5	\\xf8ba63b3ee966e03a64697bb08009818effd1e037e8efbaa439de9867daff056d1815b15a416e8a4e88e436ebde36aaf7b89a772ade40c57b417eb1fab67410f	\\xab89165a76af34501301b77a7e6ac8b7ae4aca5b203433d2471cc6638e637f3fda5f200fc19936cfcc80471fbba358385be84dc91ffb83a35e415e5ab12296cd2060bb4a99bf0c8ad7494f1cd8faa817a06c00689b9e360c861abe668a71196ede8d3e661ccb5325c494e346d6dd2dc3c2e85d9f4cf3c70657e9be398b0dcb7f	\\x8d173e98d84ae9112bb85685bfbf68ce55122deb80951b2b0189a0f767b43b7910e171affc39158d9818f2db0064f7d58220dfeb743217eb461fae8d85e1ba2e	\\x0fe7d3744c439925f9d21f7174d379ea67857326c3d55d8b073ac39b3b6846a515a743c130544e2dae01a181f6d692f458edc3ea5e995e73dd0c1eef06d6b0d08d7131b300d0f99f5ccbd68f532ec90eb859b8889395f39b09325ad1b82f5aeca38136a20b52c81e70a3bf2fdf2987dfad325e7e3e9edbf130b5ba6e6b4d0907	6	290	1
6	\\x4ccfe8e4c6dbc880135b967c6091adb5840ea176f4dedf670ad5564c3020b7b007e591e49b1434d177ae1568848caef3ecc4885b5a3e5567ac9173444b096d0f	\\x16d5d79a33818c50ec8012908e66bdb8546aac8a356df38144560e102615f4ce713f94c3ad272f42da8e9185cff06bd351c410bd30dcc72a1ce58b9e95788b842a55e44ee03e505050e1041ed6eaf99eafb3e27441b094a12573eb7e1b1e0c162abcc67ed536343fddee97c8d12e3d7a1d9e727aefff1eb0bf9123ecec5ad6d2	\\x850250946197158e9408685c3c51e2c7d39b4fb99d7646b21fd1e12259dd063689c92f6d3ce269d27a450919ed23cdc5880d4b4db70641ef5cc9ef5025284eb8	\\x52ad714a8603ed240a55047ec4b354d37b45371fb61149f369100a363fc5e332aea13304c9eb2d3f8bddca85e34c0fb552774b8b58a1df0f456a3e807b2bf64c527e183a660d7b8225e5f2634db87931cf7cdebca665f766490c87b50651e955a9cae5d9f5174d45cc3ec14b7cdd13fd27b9543c24519354d4386178091cc2cb	7	290	1
7	\\x566eefc074ce810dc69e7067bc6e8c397a9dff4d770f7ad1428e06b8f21764067ab3ad84c1f5213ad83b456806a202485ea1929d4553df5c6606edbcd6e9d10a	\\x7cecb9ce87abb5fcdfefa2928a92d501661450284a87b30197d691d0d5a409d1240c56561f4d1866ec8b5bb610374fbed5512e1d88a8175e174f2aad20a8a8c7de165be04f95f40b202df2535287e57c089ea11b8c90badb3eb9454864b146eecda80120d6eddc97c78a2882fa24cfcb671b1edc2e797dea4ac2da75f7fa4a83	\\x196ba8c9a7c4d2fdce76a122baefbd777dac8be2bd11a8c045484a1a62b7bea3eb162873669305ff7679b856991a4fe2f28734b2dbc6a9c1e24ee5a017427cd0	\\x512009b6bb85345c875146bb6c43cbb75f1851a909c92de35dac705fc9923b173e8a5f548a3d6027e73934ea55c124b1a7ed126912e896bc1431e2e20eaf2f45e855001d6e8afb01def8178d12be7b19a0b9e129fcb89f3dc40bbe3d2495602769d0c34e816a631a5ab6d53aada0534ba769e9ded966654587e5d2fadaa7bf06	8	290	1
8	\\xa81df628e6489baa9a53b41bd700d3fa6aaf3edf714057a7e80f4ef8db636b11c3cd05e75220fb3d4ec2d258b80bd2a5470866080baf81d58d7004433e1f1401	\\x89d17380368bfd24e47d1f503c6d845bd4646971311ee4cca0451922609a660f918846190dbe1886613f956c67a01a96181f8c8c687f0a80fa8f777cd9e27d83a93726f9f171ef00a87581e314dd30b592bd1ed60ebb350f85071f9db266ecdcb253953d385e859cddb8421e7050061b222077d560d707043d65fa1a484638e1	\\x66219e2b7074e1b908c1414cfcb43143b867c37e7d94a2d20a38379fd15ce0821c7c7b1814552fbbcc6a721e1af0cd8e13b16c51dcdaede92c5717d9ed925e62	\\x1baa3629e4737d8e25488d094578ffa19d25073d428b23d939788a73f346e7b621d2de4321404ed2af70d38b06643567503f699f2184b8d485c3166b8fe3d59cfa479ac30240b7a5467c2f7237a486e090c7e9ba5accdbc14fee94e89c4dfd08957d150e7214ae6061eaf4ee4f11972b9ac000d7055bd331accecea3cec6331c	9	290	1
9	\\x2822060514d4e6b6cff96a2be02b0537983b6746474e863e92360b6cbcb17e1d038b92cc89f6246ac120d604bb1c203c93bb9254bb701a513682778b33974008	\\x57d69d4de9a015b8d5b8a64061f205f5593bd2c1940b8231b2776d7edc8c4d267dadcdf5062e8daf3ceb4cf8fb6dc078b7baa9360a2f87673b75cb52b5966a832ff401e41c68976a546f849f3fc1180cb67464d62f53250b14380597cff149901e7342413ac9cf3c56c88020534cc10ea5b735e49781d43ba6891d3d0562d186	\\xe49365e0739245807e1f720a1f70785d5dedddf6cf8e9cfdb7eeca77ebab233e1987178351b7cc21468201d5e8b352915396c1df1d7eb78d21afeeb4cb011edf	\\x98801a3b383218bc456f5af468b8ef7f7e67aa3d069542a0c456ad5d990ad6b85236936ebd523cde21eb169ba429bd9a0bf07451a86584b4ad4b3e4f549b8db1b81288ca315e3751b51b99a98d228df905dfd419cd963d0dd6e6b7314a62a6d1f9947bb8ee443f23280d3e4bb3c2179d3ceecc03ea2b772d861317d73d17882d	10	290	1
10	\\x3ccf2d0c4c3186d1c8e660317a3df08192043ecd3335fc97451ea451bd98c401bc4200b747bacbc95ac73d5089bfd2ccc2a3b20386c3a3c0878a8f686248bf0b	\\x8fdb33b409a04f8f7f1e9a953ac1064ab00ded5be88a5f3d0490473f5c49616d9d39608d66dc9dc862c10f940d796643dcd9b68f15530341eb8a5a32058ebd116042f4b91f453aa8a0d2da0eecf9ffa062ee650f2e60b57a5b150b3f84c229365d5e4e0d64820fe3b81b7be033fadbd0dd26434977725144f4ecb21c21adc240	\\xd2247cf0caea9850bff1f457f6d34ee705562ac42670a5e29202ac8a029b7f85532c3b8e3557188e268524c74f6a826d6a4a28558bc213b2884a29fc76c4f4f5	\\x45f0945e61a0d454b663fb2ae7dc70f4a43cf67a01133d5d97330ef47aefe75120c559f7da66ab7c59f8c28d6146c27d5c45cb2b65f330382ca92a6eea2bd4891e8dd6c30f9398f5781cd2d46ee32882bd2b22765c25699f50e4f81040ae6568ac156c015812b424a4aaa8df057a938f25ac3b31ddc66ed04093c596fa584407	11	193	1
11	\\x3e2c155fb9a4f6f3eda7be095c58db125f01042464b2887596ac0b82c919ff2e5b2ebe487f88924b70b83974959546be4262b2b18152ec5de1cbfdc3d88a6502	\\x33613768b2d85c44c34fcd051a80c4318d6e8614ad77876e755390547e934e263e22320ba048578c71a5dd6c35188d15e2fa1445fcd903b1d950bc187341869e5a323f7c5a3659ed2793c81c494dae4aa71bf34827c2fb0268857b387afc3a123b32c0adda60c50f55f01c2ae93d85112bea429148140d2ed8748527c3c206c2	\\xcc3ba7a546ce150fd797c08e521a698d3d65a63adbc3ba4a8d0c73a329584ba8a191ae862fa4e15c8c187e65741eea3fdc9ec36c7704e18100382e3bb01d6c6c	\\x8b6a68b69122cdf99e0a9390401b0ff8e16ef7c3b1b26ca4b60bad57ec72f8b8c6e6b9ad9e9189453d84b578a5e5527203dc4d4f0dacf253c53db89f2441ead3e2446e2c644abb902ff7c8e04b995bc89ea3aeb68778c6e5158b3911b942909824f92166cd56132ab3992bfab428f61ffc871411f68fa3889a97eb78bf4b2602	12	193	1
0	\\xc444c50243b2096e3ef08d546b7640c4f3d3c846d0cfbf8bc9b65fb6cff5f587cb72a9ef6b0d9c8e6f199a003453e41d3239acbab81004ebf4683fa957360608	\\xa2c0da7e207a1d68a27552bc1112f9547c8e5473e48657f974e185f1cb8beccab0027bc44cc010a003b66be3f93d979c978fb7742ad719e23cce786c93c60281f36984f925dc556dfe3055ce66f0257283f09d36944364d83f1bd4f8af9aa2c4e254fb7b8c7b52947a2847980178ed7811890d415df0839bbdc0cd5369a6c875	\\x585203cce0b6f0975925438017acfe3a89f812043caf2ecd65fe888d0c263507cfd78f1e3f19b840e5149b4b87670d93b348e6698be69a70b9f5af46fce336bd	\\x027ae4425e6821cb8f1e16a933ef0c542eabda7baabf70680fc05e100187148288735a1c9a99719ff9d81578b4afef5a919a9fe4f728b0a79174b297f427db714dbcd53d5632ea364ce255562dfc8cfa87243d3cfa052db1616e999d98398c1ee327d00e5931069e95416102e26f352af1e3934aea80bbaba5f7411f86585d29	13	165	2
1	\\x373fcc3b9e66fd9af480b11dfd33105ce593b16455731e78d4dd104c41c4a6ae4d4a4f758fbf8e8e38e647b0a19c6b7ccf182f215ad5a6dfc84e6cb2cad3c405	\\x4a27b54fb18ca0971ec5d23a2c8c6cfc7d8a5de745a43d6817b7cb1dae42d8d3edce755ebc8461f82d0094aa68608a324db1537b9fe28275224beea4994f6278660838418d4497cbf6e6b051eec71fa880b1489b7c31ca07476de0d527b81bfee0223fac0ac55db06fc408009c133479fb400b0e1ff4a9ddd33eeb0e02e2a667	\\xe626447cbb8137be14ec3fa93c815963691163cd976b4347cdaf197b2616c2c9eb7ccceae8a7051c44df061072ce1a2ae7ce007e31e0c104d9f01b211cfbad91	\\x6bc7759c5d886c623fe03be634cd961c4cff710f0eac562998533d88a35c5985209168ac3bf59d8ba4cfc7fb58747a6515ed42912bc1ece06243a973946659fe8af7099d0f1a0422b78e97c90e1d30915e250f77dd53212bc445dcfdb7338bb9ef1f52884dca4d7730e4a2ca4e673d48f1c26e69b30218220bbf15a62e0a9611	14	290	2
2	\\x048dbbfd43e2e7feeecdd3e5c8321219620cdefeb737adc24d001ba0b7e5022056dab6c5ebb99e9c0f8edaa6d970e26d68bcef4fb1cfc13817d169706ac18605	\\xb13e860bc9e75becd2df8d91ddefdd5a7990906b3ca5defc265f6a8916fb60645db31274f6a6b5d1f4d3bb81ecab0f44492c618fab64ec6cf23c97304507ca788adfc1ea931696f7b59632102bd62274a26c238126ce68a76a93f5a077ff9c584aa7400ebc7c694ce66fb95321443d16f3dec640ad885063564fe4a66416228a	\\xe1053ee14672909b2d93f3afe2a6353493d6f7bf231e7b296dfc4a064087bdcb99fac806c2ca0873c159f9dfe7d429c1941026f35a41d9a575338ed252bfc169	\\x397869d8fdc932e0823905bce92ea60a7fc5b8718dfe5cc83082205d071579af3e6e911c873145f2b985ab43f2bb7e7503394d7b2f75a7cc04ec2e6de3bac5a054134c716c0a4e00d485ddda81e108731e6882723e1ba7d43ea03c8186dedf8f3152070281125ca57c8b5be59803ddc8abd507346331b23539d977ba978da3	15	290	2
3	\\x36f72f1eefbcec916ce226c472509ec91211171214b622f66cb1e00f8517340384a09c30cab2e293cc3455ed27f9ac26063f5d02974ee856acebe4309f15c00b	\\x79d1a5fc11f6c4bcae74d78d665132c12a06852f5dc66c6acbbcee701a65f9cf53f878d58d66e984a3d8364fc08ac456aed27c48e13ee9c79808959275f0210e5057af98689dfa0552f4e0c3e7b6f80be2573e5d504877934b801edffcdde0768e3532d65d5f96433b260a5f6b1030dfe5c4a97d4f7df3501ab513d1a3d45bb8	\\x42a4391d606c8e8112b3362d6c209691d3bcad0c0c14f5e2bd3cec79186fa116225a34fe1b746e490a5a4a028da0294496e6b85eb1cbcf3a412672069e394c71	\\x26385eabdfdc9b63672191d4f28a93f70e86fb9527777f82518b259218861bb699c58c9f22ade945b750df6db921909d210c607945a19c8c62f084f1a2a7d80e4949b1d79176c1a6812f80292af069cd5748293a83082545619c36357156c8e1000681decf7cfaabb949c2ed953531e2cd4ba1479c959163a6577f4f8341669f	16	290	2
4	\\xf2ebb7b3e80588ba4942e04ddcc1d30d2fef15285e62c12211ab00c8f8361366bbfb34e73604809646b0c2868452bf731f8705fa4f309e8752911abb6549ee00	\\x3ff5447995d26cea442cab6fcb6081b585374dc26f9a8de26d06210986a9ffee14c1135d00af7b9ea963cd26446e5b974f235784956f960f547d19112a3da73b0dd3856cdd1393317776677053e8c7ca93dcb01d2bc6ae8420e8aa78ac5dca5c34495153799eb9f02186b16712547c04856d33cd2ddbf8d769d7927f4e6a8876	\\x7253b072a4455cd1d9f5a177cec1fd0c5a6daf40583d7a44410749ba6d56deb0209a435a3207e95a1d25696fb757660443d17c2c456e7f7d872befbf397d6c81	\\x0f00e37b072c7a120d48e08db4e08636954fa7bd1466e8a679dfbada2040ee94ca836c3ee5166b4842ff2fb17c9bd33dfde8e868a6e9e14edc77ea5c7e9d87e7d512aa19c3fb47ae7db695ac6065cd2025b0964f8593fd4835e417f1d3f4ffd680bd6ffbf5b45b8bfa1c0cc3842181c074f989368fc2c3ae4d6a3be5fea02463	17	290	2
5	\\xe58810bb49601055fc65fe881296943447fe5db81a3d07f28b8697f9bc6262b0982eb1f0b7d0969cf3fbff3927a28dafd15be4d8454fe88a151374fd4b8da20d	\\x131d1c05f4960b5d3898e4efde15f690efa78ea291706d99fde7da60814cae88b0564322e0975ba8b2ffd73356690c881947843efaaa5dc2aa6a9bfdabd2f876dd1ad095aa9cd8e5fde3cbf4aa9ac147c4f07272a6ac6ccbd34c001d382f8017cd70c0888d5e6b854ad4c79607322696e65e8654a31d51ecde7d01a1091234b8	\\x29dc9793acc6f6aff620a18e11990d37ea2d7716bd999f23379c91295fd8e2a84ee137f1b157f6c9aa471cbfea5974bfc4b20328729016b666681b1df5a96a97	\\x772d13c97f86d17e2b6d417b972d771695a20b695da6321e795f80d162a671dc486c3a5a13a63ef96e0d4146fbcc0e4d711d43dda7c41932ef009ec50efac17d21f2add2ca736a8ea2a44878653ab65827b8043bf70f476d64878b4a8d08e5e0008190819c1224be892367be2017ffbdacf5b2ee5e123d6171d07567df8f5ecb	18	290	2
6	\\x6d6aab4166009c992d697559d33ac30b31d8b5a09154e1949046802169bc199b7a8026386b2916d6c4e11d73d7ee9cb3f3fc7b2fed17f9df09897096447ccd08	\\x9e98a004b31882c5ca19c15acb023e3422017dd9725123636ce2d7c1a68e728e22fa90560c0ad10d322822abf2cac8ef78787d721f68af78fa4c4ad6c541a1b32b684a4720c394c1472f841f083e946b04cfea431a5432ae8cc8d068f6ceaeefecd3ba5e7d1afb695ccef784e722eb67a7e5429cf1e0e399966e44de96fd0aed	\\xdfe9593ce4e03cb912268f764bd1d5f860e77a7627f6db9f9e832d55b2fe6b07b6ec04d5f954729ef3a68b7570e7c0a400051a90efd4bdd6c780c6f2c6bfca6e	\\x69ba3d1de30c95b688aa63f95b8bd63f1944880f227f765c2ad57cc95b467057962b6cfcd902dded8e66e208f2c68fed7cc5697606168cb7f902d3d2af77836a4119e11247a71c8751ce12f87ade8a9319fa9a72dbd0ba4709f56fd6969d087228bc6a38a089c7fbde469d3f5292d453fa529665eeac3edaf7f506fe027702c8	19	290	2
7	\\x3d21d2f9df592424217c7ffb9e83a60d408abca211205f3b3821772bc720a01b0869bf6df49e5377e0af954efceb63e8be985aa4bf0251e84bdb86ca185f7502	\\x2b970dcbeb8bdc27e6812ed27358cf0e53f896b15b9f26c4acaab550895288bd9cab2eb1b62e372d6f68440ee3c12935c0d1dcaf2fa23018ca7be55f8ab78b81a4a5910ecf25140a82433dc892156386df5cbc86398c780b55d6b115489034b1afe1ffad734037413363114cf501f707c95c4f536f64ae86ea710f6c4bac0ed6	\\xd3074f7bda262dcffc64eeccb107c0605829fa56ae76a168ae1238b975658ed33dc2e4c9e45faaed34cbded8f7afc2546911a294aadd5fb5fc120ace3e083ae2	\\x6a346af92fe7538566a49b71d4904d4b69804eadc968797129c0b666975e88a1d88cfc30decf9dc79f8ee9f75b9d64c75f6490d34ae9d1bcea5ff71e5fc0cdc009637974e9f0d788baff54d6910272e41e3235b782f6eb9d5cdd3f01ee4adb50d5c4be864899a43a0be329960bb675ed127748f41b4b953fd853f2879c7af1bc	20	290	2
8	\\x219c3ef3418259870358a8cc0e9aac45ea8253cdaf368a42aa56e17a135c7345597d2536515f8d643f32940ab054a633dfb52c9b622fcef4a5ca04ebd9cb7f0b	\\x66a1ca12d87c495df2f03d10588ad4f757c13c59679d8617e7ed8fcd0ff27fed3a327c59151a1f781736778526f89dafbcc9eb417786025b98f2ec8d399e5bf9275a4e59c561ea5b2f2626a638b5ddf9f5eca908fa993b8af426c947f56fadb4819c4fabcc26b2eac25121037be1f24fbbf3a160b69b352354bbbcd02e865af4	\\xd6f9ace92e36723ec9a594769be42ff9e1291e2c66490bcbb76fa174921e6145315229da74786b9d19e040307fd59d4e5fab35891d82203551c5df6c08d0bb64	\\x781a30ae1cf922de8a1ce8ea11bae479843afa34406b784be9f6811a3487f378b784f77ffc369ad53e872abcbe6afd3372b93276a17bc8d97c669a9084f16f0ba4eff5edfa0c36cb283730cd050fa9c3c383f3950310540a27998c4338dad4f793e332434ef4c0c67bb8e766d388120bb0a7cd67be2495eeb3cdb06638660747	21	290	2
9	\\xc1709035b8140e697855f72ac8e2d7f8c6b58eabc06a81aa2f30909d92083fdb3478fb4f70d0f6cad3dd35f6f5a4bb51f0faf8c1130bd854d21ef478d6987e05	\\x78826f7dca493ae1a139bd9f388555c2cb136c757362e4bcd59bfd8aac741fd8e74366fdc82e16ecc148e25b866e81b0f65e56be8e94addd85d613452057dff89e63e3a9091d3c09ccf9c293bc0b6d827481c8253568b15ed5604b9672da99eb4ce7cbe432cb5c998a06e8104af0ca6ff503823803740c5b5b093c6cc5c33dcb	\\x53f2f6574bce39d50816c123d7706327aa61186bbf4a297a984402200f78bde84e55ec8b939ab5bed186c26750431b605832aef4bc7688a8aa19177658a79218	\\xd327fc5087a1e60b082c6c5fac0fc37b3ae0393d4f0e1da99c1d0b73308db3a8eaa18ee051bd7ff55a84f0aa9246185eeed9ea924303dae7edb4b846558cc94ff24f99f0908e3240493ee5685cdd5ac94c4fd8cec5bf057bd87c5af342c2c12d325fc99cdc577c35ba66353998e3ca2acc6c3fe74dff330746eacf6c2e463085	22	193	2
10	\\x2d70286fdbd9b4f25747b7f7b3ffa9620175fff8d5c7a8be61c1a35ad2adb85838f5f738cf6d664a8589a1657ae5c052b0b20830e143e3bbb230c469669e3200	\\x12fb7239359184ea7c6aedc9f7a9dc9de0d9a3e99a33eaea742f94def88ad48ea995f9afc2a2010a875f75edb270c94458b1411671feb90a166a5bd9d4b395791687b33a2477595c5cb8217c8fb999865103d90a222a9971458932eec70d46ce296aaf70298576c866c687c5fe4bddffa2034b51be28ff45c7622df2db4c7970	\\xd5d8f6e7eea0fd3429192a824183e349290df86ef55a3b25078fba292668629f22a9d2db15fbf00f590be90157a36e7c05d2e9a801e3a0d37df6e3f7a8662079	\\x333920c5e355db186d6d2c5a713bbd68064b7a2128df4072031d4790c853fcd90c586cf993a96f657174a0bfea225619fea90db1d60b5805447f93be68d55567a0abdd41823a9f0f0aff0e6a5d53817c4bc0dbb8e8ddf1ea2a5c61d4a14c81755538d22f7de4f2fbc4579247ef345400dd8e8e47fcffc25720edada423f24b60	23	193	2
11	\\x77fb8e14d5da150956338b2641616cb0677684913968fcdc9d7723fb42b7eea9c6add237785417a498d55326b5cc68607b18a20bd44240fb02c2a3e8eb33480e	\\x1ebab51b33b6fdb82c5cc1d89cecd088466ffc4ebf1c9d631c2b628980622a6c80c9492dd8b83486c70855f2cb9047dfa0fdfa5e71dbf227412bc276bff04354cc6747c32925651609d527660873d7740a2343ae4e1dad358a846d889661667a5a1dab9dcf01b3efcd5e63dd3f20a8a13f820ceccc859230507b42bc7dee3b68	\\x8d236ee13d116fcac09a44ac5b2b721e4ace91cb8a76943035f68847374f76475eb8ed0dc1488ac199fff728b38f473d785f07b56c958732c00c05b128519bda	\\xa17aa809f42c9e85b65c5e34b637a1f679798d998a5a1d2a62a71491e60fbd538a85b3362308c9277f68eb8e217906649827059674ce2fc1f119ccc424b8a2b3c05c991aa9ed6ef98a98fc69c57c303aac6c3615f8de163328951af6e818536abe62b396bdbb3d22aae96e4ee1ad58b62c189d05e5bce95ff90768a6367fc3ba	24	193	2
0	\\x99fc8974e38f95d87769c93de920d234b5f052e5c0133883bfb3d4991b157440f54db7bda00cdcb090eaf8bcfed64a382472fa0e9809008fe15a4fd24e2b1c00	\\x9f5ef1e38daca0e0cf16fe361f52a51911dab0ed0e1062fe50dea003989d603e789ebdb1ff6fa927e2d0edb8d829dbd5110561c67c15580478238d5e31e5c8228ea799e6721cd82d6c585cb6fb3579436ee36680472d99679bdaf66bb3d7112224a6e24c099b257804289ce8ea62f89bd45c9dba6de3e3b67ef627f7f8bb05eb	\\x90ab58b0ba009485aea98716f3230d1e7e444f9e2eae35f7fee687b8df35dfe8b2c8fb9e136601733f17562bbfe2008ce5272054ac63216c86bd2d5b8f2e20e7	\\x821df3228295a9e791b45786ab673de4ffb4444ca483add2895e0a05d3a3522b86dbac98813540e7d6091b8499a7e035c3a123da418347691e218602c2621977dc8c5ead9449339002d02c535a042698c2574eddc7ce73462cabb22d0b13a91e1d3d3e81be0ac1a1ccbb0bee4d975020e134180c3294e2d0a43c05283575ee84	25	254	3
1	\\xd3711f9eeaff3c1409ad90090a85ffabe15b85c74e1ea1e926a3fa8e1c500eadfce72146a2059d1515a6709b6752558225c90b587cbf09b841b694530d940f0f	\\x0c40a692c50e06ae1e3762e51bf47ec25728aa96712617083a4171abeb10507579154dab7fe5a0db99dc8ab4498f4529067226c1e0cfb404b67285ae504f12101e47953c04c4f935fc9ef325dc80d7cd6e22d60c8b2d61caea67c34e59083f63126421ddad4e5b2aa385127c18fea26202d9bfc6311806a79d234002c81d2d7f	\\x6113d500a4d81e4f100bc219d93ad11749eef72f47e22dc8b03869077882b8692941c7d73d6b572b8454eb619b7ad976babf5ec365aa7e7d18c0e3121cb96997	\\x7ca2e8d7602b2a36a48a219dc69fcc174d66ae3a4534a0725c69c9ea8fba3a7bffa1b70d30e8cce5598d0a3c601cf9e27d24679caf0155d4fafbb6028962e1a877a3ed78cf04b2ff2eaaa552b0f759f9bfe07fc0d3e0a28ac9cac430e5baed9363d6561eb8f4fdab48b2a0354e1c1194d6801acabd8a5d0befb59b17f594fdf5	26	290	3
2	\\x1e4672ccd137a29e28adf9b3be826f13a69e8622ddf9505ec2ec0cd5a1b8f0e07b0899c5ae8eee81274a3dffb7a178f2be028ac074fe4c56707d77e4a8fcd304	\\x960368ae6631922cc3e604689acfc427850fa75133048ce20b91e63ff8dabe7c895309f83fc7db2cdf7f253262b7e1dd1fa44f2864ed2bea457ae4202ef27c084d1d18dce56c085b10b378599a612c23099e29bdb841e541699f1f9a6a8b47e36759501ed0c2d0979ea3981ec7117c3f8eca08e951c316b5a6da9fff04647d69	\\x4813ce438c9edc18890d7b9a927b517cfbdf7096e63cea779eff02e12ecb90dabe46594226cf1eacf0babfbbbdaf0373fbe6224b09b9dd1a7259a6e393d54227	\\x9593536ac9dba5ccf49cff076004d2c3b871d7049e690ba1c0045b7740dc698f0b3195a0c2910df7b91eb3803143a43b0b7f9e0ebee1c6d525ea52ebb6a4b27c49edc943a0396925521a51f61a6d55db0163fcce6711ee14c254ca9dfca1ad4693359459e6a399d775ddb9c048c095cc4f8fe9e7b11c15ab74d22230b0e03ee0	27	290	3
3	\\x9ccd7225fd9a68ea1a3908efbbdd1c11bae3efcce9b63c4db6a77b3c8a965aef652308a67bb67b60ae09fbf453efa5d4c6706b4ee91089f733db45224dcfbf01	\\x829c62ed4bcd642d9eac7ba6463d5606353cc59c2c881fece78f5bc265d79398dcaf1b6424dc30254b6d78119e883803d3227e2c9f83be5f706378d1c83d24994fc80ed240c8583f4db3bb0060a24957fbfedb5e160085c1d455ea4f3665b6af3077edc42664a8740d3baba066f5ae048f729269aa756b4e9b6170e20ec0e26c	\\x61ffb8c3a0d36f875ed7abc0993920c4573b44f4c00caae4bcb54adca8d625981c4f360e6e3b4cc533d3a0f0bbd6fd2614e1abd46544f33a25b4c6b9c330d70a	\\x83e4df6a0b6e6695a62ba3f8374806f6e6c4aabffe2b8486611c58700f685402b60da93a8cb94f40984aa1d13d559cf0e7e5c378cb68bed6a392c572b31ddc7d2d075cc9aef1fa30cbbeb66ec6eb744aff9bef2cb9c68c8ff63f2655b99528cd52d195a54f32cd276a2009181a918aae87e3f3efa73a670b0cae7241b08de8e2	28	290	3
4	\\xcfbfc74264ed9d095ee97687901e4379a76192b55c97ba449e8f1ac3c637cb3eb1beba429e511558b454b645943c14c80d92b6353de9f815012a76d63ba26905	\\x96e3d6f2e2da6d1eaa6d4152e1a437c6db23c8a89609085b179e91e6fb759a4ccaa70673dd9b70996e99bc40537aea4ff573cab5c98601f31f3269ddf6f354da62f3aecb3885520887b91e18c7fa48530e27608dffd94f9ec1df7a05666e2a38dc3dc728df19259cc59e8f2ccce80bad93e5a4a5785750bad8f3cac57543d72f	\\xaa73ee73e083f826f740a34978eb631d78843161d47e525886cac5eaee7a0d711c0c9e01c751789957b159da0116edf191f9864ecee09d8f3ae24a2ce89916a9	\\x7a3b06bbebc65b7178743fe76307d0265d20d1ecb618aa74a34ca0321a97a7a68e498b994f30be4f520bdfd627df702cdd9c331cd85f4ff268163b3c048cadc2e234ffd29a69909e92b3201633bbc03b6c1e14ce2f719127e2fdbdf0aadac68318315b25d0b4c8a9ee9305fe68de0f2d110ea59431fcf2e94b54931a10cf6bf1	29	290	3
5	\\xd8d84c7f5e2200930f57282149ff2b0b9784ef9d386cbe199edcf3036a5b886874b6fde5b864db75746f53b16dfd1e292a0b6e4b64c3ac2d3c6e44e99cb19e0d	\\x50c48d0cc8947826c262621f9794b645a5583f3526130b21d9e9cd06cad5b606024f36246813087956ead09c8e61adf146b43d9f4b9cb9c6a7f6e3a614cc953e8dda6da2372ad3b7f1845c97d2533d45b324c732f09302c379191623600dcde9efbace90c100a9171dfae41ab3f16f983e1b3e479b6a60c8c989de274c366f8d	\\x4dc90057ccc7e9178b773c887cc99195ae1504c78d6f184750a5585ca08ce332b4990c1607646771413f571a0272a82065557fad038653552c36bb265e7b0103	\\x84b8cafcbd381bbd727dd2025165a3634f5557010873c08735521f743e246cc8bca2bc40e0fef3a25eb3ff498c4fb7182f8b659ca67a67fe5c10280a313df5aa915c8419462d6213944b9c83b3a0a7ede16fcaebb45804905a179774893ce1546ddcdc73047782700fa0bfaf64edc5f5b7e3af8a29409e8ed78d9760958b57fa	30	290	3
6	\\xdec26357f6123776a66f5941d5da46679110cb80a9bfd978322104128335bfa682d6f9c4feb3a621dadf66110f6b1ee3fbc2f075397abd7d4ddcb01a62b2d70c	\\x32bffae76d26aba3aa5cf9050c45e8be180bd1c4f83811f106ad07ec99bb407a23be020b7696d149d6350ec10927344adacaa6f2bf0cd9ed39ed74d4f6cd09de643cbcc3d5928c3035841b6297d73a2b80dbd1ed0c840d6a98d33265e53635dfff505e82d790bd632042e9267ae19dce96830e5039fe112b45b9e08475421c44	\\xd95ce300bb1827516677a56b85d847b31e4eecc825b71a71fe02a834081fc307d28432d189f9e0df619f107470e8e0abf30ef9770b7ae0abc36cd9678b7f6353	\\x8ade9a1371be42fc77e518e64cd4742fe57baf435b0df7d3cdaf5209c481b3c2864d0aca741c6d221ebf9e7a1c1382160d5fb2edb4636528d24b3cf10b468b643f59b98d74bc2a53ca53770a37056571ae9ee24cfd04ed251ba08daade4d2a8cdb51159975a15c66f0534d5855d2359bdd16bc175bc79a07281e1338ba59bff5	31	290	3
7	\\xcb31218b6a3a20e59c9424b4d1d5856d6abdf2160d64cc191bcdc204c3894291248f168f9a1b550533060a7a215d2c346d811c7b7cf238709941b3b3f68dc404	\\x524d5e9a6118a067374239c2f89d6a7b3fb9314b0672dfaf8fd3e882931d1dab7be2c7a43111c99599001b843926072c68796cea8b307324f29c061b879c131512b157a5f096739860a7c3eb861d038a2e8726f1a4a86f17732a772fadc132a00453f8ac2ecef6ae40fb5e31a5ea461a7f3726ae08fce03efc6c8e7e39b48a80	\\xee9a32b0a9afabba76e163e1535801e9aafb083988984d3108ec4368002b7b1ba2f17a27ad25b556fffd093d930a2c38b293946fda4983281b4016f973ff8345	\\x825feddd712ed75489cd275ac9a5d85402e7f5ad8866840b7057d41881e56eaa6af45abe8a6f4b7e83b1efe4456f068ec67fce4b473099f9be0338c711088284a5b97a8466268604aaf6a2615a8af64b399460b0cfb8f3f94389cebbb83bc4876567ab0ddbce1aa752a8db77aa627b3cb1dc4b3ae79256eb8456786c17196d07	32	290	3
8	\\x9faa37976824f27ca039c31be0a8bc16f658a865df0c4572a44717c02fdc83500c5c551bd38c34b5973c43f50d8a63151e0f43926da848602d31a7ec5e39de09	\\x09a55bb56f306becf19651077fc6d0245a5150df673c6de6aac82a46b0d21c69c1b0d7b9f4ceb3d642fc91b81a3456ecd5ff44ace66aeba900e37b391613b5376f7216618f4deb1b80d9e13d2873c6cea0a52dad0bb69c695a66f14e8c787cd4262e867fcc7be27c41da945d2cf765b3ffd11c44f9e7d89ceade2062400446d0	\\x1dfe39aefb4cd7525135cdcb3149ac4c1789eb20192b43c8d42288f5d94557a17a4068746a665c8475b4f5837d889dfc951c04c40c969eae363500f8a6f0985a	\\x8049c91fab444ed9419452ce136659b0ccb66f467adc097dbd2b3c5e0f9773b2f061a94267506a9d9177cdc308611d718fb2930598a4612f2a03fe4a054e8238983872683e1b58f35217614eb2ecd4c011a115c740644629730888917346a4edd7721c0d448a7018c13ecb755590a0b5d2657e9c46f92185156b6774a73bba15	33	290	3
9	\\xb667a14f679203c3e64ea963be94a45e181b2cac171ee2d20445bf389fad44f3aa3216ecb205a1456fad6ac2c64c366d16591c0c2edfe61f56e0a22194740c05	\\xc4b5099dacd372a8d7d813311c3d54b7c3d029e4bec54352373b0d67b7041a9c13aa98755a62bddbe000cc2a640a18cea0fac3f3f21472506fe9a4138935be52279f59e74778eb3d19a167351aa0a8db7533fda556cd3c7850ac5da1c813fb0290d78c90b20cac2e235f0d02233bf635456f6b81487a6c7c64a47cf462017ca9	\\x49cbebf654bce2472df4b87951d6dc19fb949871c8cb831646efe73cab7f0cd3c5bffa4af6674a303c8481ec72ae797405300dcf530ab537777514113583efb4	\\x51a6864c64c2155056dfb1b3516ea099274336f17a4b3ef9d49a59f6633aa241c5fb15ddaf1d61f3d774f513bd6664eeeafb10414ee78656aca4896c3d17f2c6e66a08d568c06dd2befd78ce2f6de038d944df625fbc34474d1b2f7963b5c1b8234b19f3fa25021367f281596419b3e3383710460f6a62d0a8c69a24b0be0db0	34	193	3
10	\\xe94bc30dda2fd4d612ca38907041bdcc2dd4c8a26195785c8d41a89fa277f1af3c8893de916073d78fc450f304043bd474e9aaf8d43f8dbc65d499fd248de80b	\\xa9b2be4af9de6a428e7ab7b519c1cf42f016c871e48956fa2d19907aeca60ce9eb18ae0cdf53231ab9ecd132c5bf21be95c67b26bc2dff4cfca9a18cd7d55fcf386a2a114b6a468dbf61775b7387e6a585fdae2d66a8aea75c0b547d2e8b3b62d536dd4e26334b0956142084eff602563d302fca37b079e6760ad5bce0a94c18	\\x7b4e1769d6dc507b8a7f9f6917e83e29f136a1ec3662e532b1f14e73a9582773b29e5d237fa9a2d4d72b8d829e2f19266a0a9c97bbb02ef64e992fcc46f69201	\\x4940df9d9a829dfdaddc8012befacb2449d46c554923d4aedd3e54926f71615ac3024a77edd9ee4493fcf64f98898f0d816754ff496c5780e2335983f7e69f878be852c586c442e1c71f9ff4842b39714003945ba8d26990adeb367672f383c34e97b1fcc610c88c416396e804f170a0b1269043797d5cc377c0dcd2d3c2e134	35	193	3
11	\\xd9d70db04eff7d2106a7a5b74dd8e01d5d76b743532d7f979273a7c096e71170c1d65def6ff5bd4715dadf81e92147d59cee91daa3df9777cf3e4b5b8bbb900b	\\xadc16d662d59eb0f768b5d13449e847151d20a478bd1d086a72c305384461452473345420d7d31e8fd8ffac22d7329ca16a3f569ee92329ebf5d18ddbfa4bbb50381644a5c850a47ead868986830da66f8e4da8d6296bb3899303a817ebcbfa11091ef1fd431f41afdc2021b6a6b1c6a92ed2ee2cb1881f0763bd4b538e9f394	\\x03de45ccf22a6efb86f5416c28730663ffb05232ff889f24e876980b8a6912efb2375e47c6366e0c82466398e19825b2e17d982ece8938d8ccf0ddcd7eda3bcf	\\x7e877573424cfa809e5ddc1d6931b72659556e1971a6951bbef49b21cfb273d60984db68fe80ebda31e47f43850ad9379a50b0b22340b67f1ed909be8f297aaea27e641cbcd03f7c9efbd486dc1060e783579c9e1b801ba12dfb3585d3e0681dcce3a6a7b9540bcf39727498e4963abf389a239f33f4f9348bc7e6cd20785b0e	36	193	3
0	\\x95663587065156485caafe2a992cd65d70b368dbccd23f8f116d08d324ded3f16f8396b31fc05a9429eb4702e0043fcc12f43696643345bec0b0bcfecd68fe05	\\x3ecc9bb6ce0fe72d8835c2781337f4b78d490c8cfe6f08aa4d48b15f63845fa42f0e375c40edb9dc8e279759ccded5518283ea97c092dfaededb2d6f4becfecc836becf3802aa3ca0446a12170d1b78b3f37c2f0a0a5325144d6dc12f85739e77282063a6bae231491984a6fe8680f8042ff941388df8c70b611f86f00687611	\\x1746f9e6289a800643d0a9aaecf043bc6c438919ec03305e634a302a46d076190b097cea4686cd4fe88db3309ea2982e66a6772e4189f50a1b9f2d6902845f74	\\x54f638b4a74b9dedb74a8f4609236e2dd5f111406f419f53535cc6857fed5946cfc433a9ea1ccc06faff7cd0d50a5bd9ee8ed001359f2c5cda466f867513471672204d24f7cb88d182f636600524b19f131a5aa23b640656a5eb7d16db35c1e18c5fea9ee79a9c57e38714cbe19ab95c504a61890031618db27730faca00965d	37	49	4
1	\\x90bf44b146cf321c10a07ba718b5409ae9c1b8d61f5cdbfadfc5041d27b1066b375dcc5d4ca0468ce64e1dc5ae23c63f70672435fac736085efde30bbbeb4f0a	\\x26990fc0070fed3482aaff71402918d6ff8fd1beac5042df392f55a7377becb0537bd49fea8b6fb66ee729cc53485bb25f12845f59b0c0a4a86ff02f42708720d464797ee4f3a4983c17479c77c823a5779a98cfe7348ad7b7d90693471912b57b9d3ae94146c8bf41053948e819916798ad6a2cd29c3c84e3dbd50d02632c57	\\xcfda632ca2b675e39f991aca2d400580fdc8563a3f1f6b73942e56bf0dfbeed726281e6f0f615eb949ddd5643ccefe6f2b5b3c79eaaa09dcfff4d5d439fe208b	\\x6c5383fb0f1b216ff94f22445c209d81dc69790ae74ab961eba484f773ee24b7ee647d3ae0ccf183bde1d6a830bc9bb3b8e9a2d07f190f6b7c0ae1ee10de60bf9143d02cd0ced023343a8e03f3f074d546b01ebc88329b881d3bbad3ccbf6e188e1d7009eca508ac08ad36ef2e3adf6675d395af7cf9f9833b7fe4b2d66f285e	38	290	4
2	\\x9ad5fffb1b76d6fb990d42ab6d522f77fd6158213667767a45505ec98d7c7fc2dcbb20ec7454a3fc74d235c2b5a4aab9ca1e25b0f6d51122ed80186bd9b8e00c	\\x0d243e730526ace8368f3916fbd70b528e1143da0f2439d44229ee2b13dce497cca0d0df795d304450fc81c8fec600c664fb1833f83029572ad1df21c9e5039d4ca6df2de2cd356e3251beac466a9a88227b848dc211d5ec9cd52da98a9ea1f194ca3a96529dbfca5ee1e7c9291ec497ea9c8784ffd2352b80689b55ee5f7dfa	\\x7f7ae4074fc8409fd7bff7d0c0829fc1a0e1709fed3cdcf1b9dd3f304f6247d11215aa30497168685d510c445b5fe1ab6fadc7262a8afbd0205303d5b1cec1fc	\\x47f4446fc59fd197b6a5c4d0d903f3d775df291b9b7a739a10341229396c6f9cae37e117ee7ae30d7c42dcd26e8587034b894f0a2535aa86f41baffe6abdfcbc92b57e4800d77e1f487dffdaf98459567b688fa99103ae39a9ed46344bb1e9bf6db0903795cb7e2d9205c6dd1bfc58bbd6eb30ff9efc2e57c451ba41127fc54b	39	290	4
3	\\xd82b50cf0497d48d097ab94aa985862eab53b18e2fa1970b1ec42659bb354b911fa49b6ea1ef8cd10430e21c129c0f319acae61d1f3921bdb02b40424f3cb504	\\x2da6ef63f1efb3787e2b67c90fccbd3ef85735fedb540acbab8abc09196f00ad68d0a1253ec5566d6349d489153bf4457fc7b8a22fe4466a101f85fd043e52315cbe2536a358ab89c41e91c182e15645c3cf18411fe77a9fe69314935c1a0dd0b1ed8e586ee1238bebfb6888f59d872a6bd40ac3629c199c583d7390cfa9423c	\\xa303b31680bb467f581f55cd896387a8b39fdaefc48201c50abfda73cae216fd0c270c579157cf12b6b5a72ef2847f39ae30386f6ffa7e8070217acb76ae3bb2	\\xa29786b10911a085da62e6030ad5143b0d17cb667c43575989ef82b655240aadea54942e5b8fd2bdc64fda08fa60f5b9b7a5b4d6536d5cd10d3cba2895ffc4f7e0907c7e035ff946de5d34fe290f24ed2b74e6aff29f29d5d54b460a4478016f4c9b94b571aa0d20631131d753596812699d031abf63af9f3cf71cc7c2434789	40	290	4
4	\\x0b66cef38c1f4e724f78a9427e485d23fa20ce6899dc1a64ca0292cd23fcf02ead183de9bdd8d6e8657090f6abdbebd4e5291280a3adea8bcc3b661bad241401	\\x33424aad313b80995b659e17dddf040087c41f0d4b0753addae7f5f1e8df9a903076d452aa2755d4e15a1cfb10a86862998a67a89b2b94caf36c9a195ac5f75170e90238c8cee083715873109eea69acb919b0723ae216efa5eb20ed82d3ad3e66c714513c84e4546c08b38e7a36292096a87a6cc1b0a4f2e8a8389c110a1ab7	\\x6886a35cdcce934a5f5a89277815b3be8e2e97815e65da76f5c9640776d90cc64b84309fffa48e09ddd31d23715b24e0bf1f055850808f92388f12f83bef4691	\\x71eb66a111f195b39c2ad9eed5e1b3edea8d432cc80f79d86276f784ee9fdf988dd0eec234cec0bea88b8dc04ff79195bfcd18a5e12aa9df7a97e7e0d33c31acfa23f500461da4dcd2944ad2b783dc9258317d2f0b8be12bbbb7491b7dd3281c5290a272961dab413647cea1ff8584c6cc105912be25c84e8246b631fb247775	41	290	4
5	\\x08f05751a7a8c96d420619997f98be224c3da1a46db8c5316e371572203fb93637a3d5416208b0c6e180328485110de17c382b08af2b390046edd31b7116300b	\\x75fa7df1223f618e23a2f9b81a87dc9a5dfd798bb9aa14b6704d6181a2a2b6a810adb1ac8e42bf411125596d3ceed90d7c6b1ed4dbc8c8d1b70ae4039b74ac164d547e737215e35abdb3b0129c7f4dddbcfe71306d77d2eba31bb42195e0ceabd89e8a48b46ffbe74e1186438ba237c5e1a1f048ae3f086e0da7a89f8973851b	\\xbb669971246e9e32416f13d2eabcf554942225449a516ba231635b8e423cd235bf2b75d40180c9c9765ab27d5c3e19ae73feebbc236063b0597eadc27719db4f	\\x5d58b423a5ab9e299c67107355e67cd57cc94f67a5a18e596429a2fe31f389afff3aedbadff2a0a548a10d93ca71a148073a105fd6b3e646c4432b7702c5d8e9d849e8ae96d487edd41636bcc4dd219046cf76249c2bf236a37967de33db5e4c7b36b159b67faae03697d7b4bc77655a69dab625b711790b2ccff91296a55907	42	290	4
6	\\x0477a85ab29faf1d13caf38b83c1c7864b5d8229034a5b2ebe1c0d960203351f69e43ea38d7e650bc85b6ab27f93cf9fe999f067e9365237c846e11f08506004	\\x0bc250e2793b2f3fd6fc19366aec9c9c9b5a54cdeb3fbe1b411d9ebeebd14baf3c858a2ba7bfa952d3731358146e64028d1f86259ebc55069dca25721062e1e6c12b36ce0c1e0bb465496f50c9080d77365a083717151c149c24be8623a26851b4085b16f1f00282c689414218495dd6cfc5ed1445855eb7373cf0d83a81a77f	\\x1e4062ede2427de0453c702cb9d14497def495a39ed550f1d8ef723fd3b4acfee3700dc18883fbc7c46ef7060d1798095f77b2d7c09775cb18c79f672a8445f4	\\x1174fb4ff05d5f0dce0cb71653ba7c83a2013208ae22591ae2f9c6930a87e4685a4e42aa88131b0a811877c35bd888b454cc170066cc2cada4799dc04059c4f20441269a56c7dc7feb6333e7828a8421052aa4b03c8332116ec9a66d5fb8154326109c3b140d70fde3ba2fb70aaad5bc9101270fe1f973266f7e7cbb348448bd	43	290	4
7	\\x4c905b39dfc62fbfc91f62b7d47b663a278da0ede415c150c6ea19faa619696543b181d4cedce4f01f5a234e60ae6181b1ba87299f29a74fa33f29fe2006780e	\\x7f8c5cae052bca447c5ebbe0b9a868ca53b39e33fe2705585b427a456b1f0856a6bcc68c2ef869a27e8099fde9a1c2040a9023c89681e29a795621ed3a6bf26646a4e881250e4c28d942c18651853183fe851f068e153b00d7e33b9621c87fcbc4588084388387ccacfcaeafb92e6a092d75d0bf1ff331949247375251a4fa06	\\xb2668433558ac88b3bc62ab6a3d12988d22286d425dc18ef06e1175fcbd15433a9b44e71aeedf28028c58f93a712eecdeb59c968b8c333ac974d090f870206df	\\xaf06de814dbddb2915243b3116f5595d173bf838c4e1dcb2ec5ebffef804d9475e18cf5584039013179fa41152c3a0e91020e68b3e125a137d1d9fcc3487cdb94aa4549e4173deeba2241b3dc260f7bacf9843ef4ddeb59b08be990885153748cc885f12c590b0604695007c3c547a848817d7d2aa5f49460f0b6e7ed77adc6b	44	290	4
8	\\x0deb0a46e6df82a92ce6d714509186c6f0061ba71de48189bee896ce1ad002c101b62bb1568581b1b2fa70fab34136a4e58971cb90a8e9b22ffefcceb9eee101	\\x59655bd1cbe4760fdcf5ffc34a976639a24fad8509a408641e237a18ca8617892549c70d28859a2d4fe7148948380660eaeac262414f3e3e972aca1e9b51d39ebfffaa88c8824bfebed993a4aeb139e2c4fb9cba17424987d50fbb5b8ad095443bdc848442135b9902b69116e39e694ad368d20a581c2a1feb12b4eefb72839a	\\xb5f81daddfbd20e975cf3d81b0884bca9981ef7aa0481d9d05ae739e0618cb8bbe77cc40c25ccf30a1b5b94bf593da06f8c48db300eab0d808a7ad5c851dda9e	\\x26f3872b6c71f1e383e3d20df1daf51a6c3c18cbf219b0af45c20a3f9d90739a82b174d5dafde39bd6874db779c9730c021fae1bf6f8fab9b7f7f46d00c9f10c5957d9b3dbbeac48ca0678bba37d08f8f1d7ac53ed5de8cba5004c3ada28bfde6dab26697e5560fa0e0e8b0f3f33d55f3053bade280ee8af42f443d830a5675a	45	290	4
9	\\xa9bcd97b3391ad7cb9879bbece3148f4d673e2fdbd8acfa2dafef288c28fb88484158bba25a995362e950d20fe2460e3eb1bc00425dd6acf6fe7fdc7b80ff707	\\x3997623e582058a1222894893717b12b0eb7659f8d7ae9c35f9b118c96dc243423f46dbef0bff8ce8c5bf482de1c3d0e0e610f4cc19dac484068d5d677321087265b766297a19b11fb1a291291a489152767e5f767ee0c91e96fc327ea2b083306b47c3b12a4b106bce12dfe685444dc43e272ebb679a90b373e2d929e3a698f	\\x4cd8f40d9412a7a289970b1a6416b2be867cdd45a20ee44d8fb7e4fb81e0e6de4e74e4135f288cd692870199589c63f76a71e061de0bce7ae512f4ae64fe904e	\\xdede3032f1c4043fc25220a1a82ba4394fd49c72bec7b435e1ba7ad32bbeabae187bd26251a7272fee9b10c78a483c5e9136d302d079590dc3f1bfb72f363f1b4c4fc7c716b0c9356388347af96f99bff7a5e9d21c9b447d29eca7f20c700b107f415b25dcb9ac3e621dc3c94d4a238f3a4ae92aae0f4fcaaa48d60f5e7abb71	46	193	4
10	\\x02eef91f89e6f82792259a7b3d07cc57214c89bfb2db34a3abcfca5a5fa534782a0a393920041d6f893119b4fb676cf33161b59684c2a892e323a5fff15e2905	\\x8bc342ed72ee3d96697ec9593c039397f5a4f23a73b581bbe5048669b6412eb7a512cb30eef02ca02e0c23224a9660780e6f90af663f81f7f899596319b8b91d03f1892e001a4337e0411ee3a18eee335895606f32e9406bb66c6ff32d40a14529740f2a538d5975bca3ae3e2220f4be6b0c35214ec1480c8fa40f484f0f3bbd	\\x45e89f5523b7bee1924e958783edb936e1e53d81bf8681ecd1c781b3423e2ca0a4ac3b4a3fbe87a28c48997c375876e6e6e8f243347d9e9b52571b9838806012	\\x7d1b0f59a9c1577499681d8268ed57fc5c35ecf6b26928b1c4f0fa30aa6e221251798f0f75089f7b3d4a462f6e9dc52c253d03f7e17906773e21a7490115218f4df351ecc5ad55a4d0140d30ee1c9806867cf0d89c4458edf9845d2b83ad7099773613722b2e7212231fc14155b5286c89e3e439aad16e7f0cd4bb43b56cb607	47	193	4
11	\\x386a02e903d532cc954ef9de83a1f1213b9e469458ff8830b723d6cf0b068288a2664c039a140661aead8863655967dde8386414550e09e4153de35941b39f02	\\x45db5a391791c059811e917546d67ec4d50c0f52418e3e41fabe1e0772663ff0c780f7679204c3d215fdd6152b525ccd60ea04119d4133f42567afc26d8d985547fb73f5c93a7582beec4a160a58fe4f4acb98befcc0697da05bb0fb4fa1cac21d5bc60af52b3def1728b217005d26ee811ca0630c8d330b86d917a98f73c45f	\\xb349e2f1d9efffea255ffc5a7d29825947853808f1276b168f92001276d7ab2bb45b06b7e4a5db30ed7c9fc8db92d6229a97ee172d67e4c407f4b3d3497fc061	\\xa9241a6b221a7340b7618aad199fe49dfc36adce9fb0b3fae3c635dfa07f311de47a6c91346c6df9c0d5cbed0117c21fc8777a6fe5b480aba9989c26cfb4b8e00a8809dc8e905bc9ec1ca48fb7dd6ca32c33df81bb5da0750cbbf2212c5b14474892f498649a920f7673989410cbceb68ebbceed5d11a50a9d3e302ebbdad4d2	48	193	4
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (transfer_pub, transfer_privs, rtc_serial, melt_serial_id) FROM stdin;
\\xd042ed8a058e6692c4054b3889f13a8fcc1b10ab6c7dd40eb9e9ab5a3796c064	\\x25237cd3ce8058c84265c865f123b6508e0200b34445e439b964d40c6c3f53f6a7534139c17cee8180af42968b89984ff565fe6fd05a68f056aabaa311ead34c	1	1
\\x0836d34d8b9ed202cb799d9290edaa05f1c40754c750b87e09cf43bf7352cf1f	\\xc69af9f1a0e2f44592bc36ff83073ad77c8f24eb8f53c9c6fc80867175c912b83ac18bc3d109b7703f8e2d104f1886e2037364c3201a21afee6c92e688d141f8	2	2
\\x834fda148cace1bd6454eef1f97b52e5f778c25eeaf73919d1debb7c4e4b102b	\\xa8a119899f651bd4809d9e7eb258572e6bb1ecad944aa988d22636b3bb942cacfaa5d8202110634ac5926a31341de7feccf4e37cdc6db0d1f69936e269788ea5	3	3
\\x7f7baca3772846ded0b5be7efeede2965597d69d7e58f36e38c296a482b0770b	\\x78dd1107d54af3a1f92ad9945ae1e69ff6fd4316fca7947f5e67d681f6269b131b6c208a28e9262d08c297bf073bc37071348a3e617efc9c3ed888e0d258df5c	4	4
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac, deposit_serial_id) FROM stdin;
1	\\x0445e50bb18da48f33d9db2af3dc18c0ac4e3276baf5f76e9b4ce017e690d4f8533602915fa3460da65d59daebcd2ae863573178a6d2f4c8b580ba201a732403	1	6	0	2
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date, reserve_uuid) FROM stdin;
\\x0737a72f572dcd0dd36f5db3900cdc993aae51ffe7764e9d3e14829339374cda	payto://x-taler-bank/localhost/testuser-396TEX7B	0	1000000	1612774274000000	1831107076000000	1
\\xe4433f04730ace9f30bf2e133685b6598049f359071f966fd4f80437f6c90997	payto://x-taler-bank/localhost/testuser-Nukq3Gg5	0	1000000	1612774278000000	1831107083000000	2
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
1	2	10	0	payto://x-taler-bank/localhost/testuser-396TEX7B	exchange-account-1	1610355074000000	1
2	4	18	0	payto://x-taler-bank/localhost/testuser-Nukq3Gg5	exchange-account-1	1610355078000000	2
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_sig, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac, reserve_uuid, denominations_serial) FROM stdin;
1	\\xfdb258b26324a13fc7ff7a81f202f8b632c8b1f00983feeb1e282dea6d62fa530e560245be10a2b43c0925da5e8a92a4a7da856dfd0dbb700e4b2467b5d0ea0e	\\x7c358226d9d11715f7e5c18fc80f10cd00b0f6342dba0034a83d53e8bb9bed64176c04440df8ec4a10a6660f966d2a144469d3bbf019fa49981185c6477615717f005b210fbf154d769e77031bef6ef7254d7f270a019421f8803bcfaa18fa2179a482301b8cbab442976763295aa40a2cb34e80c85dc86d2590b5bbf09109bb	\\xae85d96ce663b8c1d0ca89acda5437011513bec0b696827dcb7818863d719eedef098dfc9ae0ec39b687f86143c168449c4b62cbbd03d10db8432be5c6a6c107	1610355075000000	8	5000000	1	111
2	\\xcd3cede27a449253f134407240e738ab46efa7007098c6acb87b89f8fbecae5f27398af16511d82d8d0034d6cdd5144d9eadada614e4a076de8bd92ed05934aa	\\x8d849c442da6a361718d975914e12bbb18ea8a479ffadf11dc21805f340ce9b88f8d90d3641500d467426338a6eff39609aae1ba700a764627b869624ca1376d0ec75938d90a55d40d2c79fdfe44ee3a0f598025ff74fde67dc908c0d6116cb0a5da6f4071412c66c52f0fb68bec11ab731eb4eaa46b5df3688242aa43a74ea6	\\x43ca3decb8ed0333b9543ed8482c427b838ecf95094c8cb2f835b5c68b4d00fa78bac57d1444d92a9fc160d550b196aa524d2221dfd516d81ab490a614089a01	1610355075000000	1	2000000	1	49
3	\\x3407b97697223ef87cb9725b7de0931952003bf53bb385c3d04b1f82078d3aa254cb9ae020ae928fff187eebc7f16072ee76d89e12416b2f166d7c33f77c9ed0	\\x6b2a72a285935bad55177d90f8673d85dad3d8b6f36120613f30120b373e1f3a3b61f23d9ad5c9057cd1c0b43b926249b65d7c810af2d31736eba77dcc635ce23210dbf30d71435e919f7387f4d7f128c391e97fcdd1bb798ab608e87b54977b9c4780c3c28100e63e2dc3c44e3cf74ef95fa49fefb2841cfb231075d4665a46	\\x20bb7b5d4e866f638f6aa18dffdf82c48daaee3307338281005fb9edd995b1eb077446753c83511cf94261150e0ad2d57f69a46856fa4a73824c828f8bd53c0c	1610355075000000	0	11000000	1	290
4	\\x53e8e1235de29be7960615ebe1282ba372dfd87eb30fec1d1f0745d0040d7db33d06ea15ba1c44a586949cdb13855d822ac7ae81f18624228277feb1e929ee33	\\x34b49571480389db9460a2148e61db9a8a455da9aceb797b2e241a76fe9586401592bfc61baf5990e12c337a47b0f18bfa8a5d92daffcae25204b39a79a1f454a5596cb91716e1745bfb65c0e36d2ce69114db36349c1830fabe3b53775e0f5d318fdaf71877a95af321f3e4cec8250cfaa563e9cda49bf7103ac00cd97f9ace	\\xc0e503c28c66bcf108cd55be5e2bf1e3734c045616be0d25467b73c2d4360e97c8da58bf0f26ec37f113efb87a6ffed964bbf2976d24f9e5fb79340d29fe5306	1610355075000000	0	11000000	1	290
5	\\xaa1aecf6ec28d89eda312ef47083770476e14cca764d39b393b9d69bccc1f07cd7f268f63c182d193cad257f8937ca632cb6735bd83472d26f9b857381ee2512	\\x975d1f43e2a1c8314da528736f05ad089c70fc6a34925a1c3285f5435403cdb1368a0fe80de74bb2a24ae41c8dc38d64ca5c3153bbc6ef783cb740cc879eb74f8518c7ab92815365319f3ce12e094444b02496f78d5787825b558bdeffe6eb30d8fd04843b63673aa2805abb01b42a5108c1a3717e26e5fa505dbc9fd885d4a1	\\x8c09e2975a0df79762fb894869e1b881617b31db2c7df96325e7eabb75991908cbe73929aaba4f731144871ee77472b47a1ff0848ce101986b29bc2cc74b7c01	1610355075000000	0	11000000	1	290
6	\\xd6a30cacf909948c8908e591c976ac7a9d46ca68391cb9b66c55422dbaf046059def4c0e32353cf369460dddfe717810b29f9bc9bbd2a3eafd74ecf13f65bf0b	\\x4b4d317052d91d161170879239b6850eb172f9c5f2cfa9a2728568cf6c243a2242baccc1d024b63646fac409e62549cbd2153594b8e81d1fbc648817ab59ebe83411ce567c60b9597f4970d9a7569dbfd24520e88c0d22b5f53a2a44f725d1bb9f9270b15f32615070b59d3b1d52e4090b0fca946359a21037beaed4cf05e126	\\x3a498cdc8bcac96349accf0bc5a6d62fddff03c5442e99a0f9065d74c978d966e24f6af586f586f60a8d5e93973835eb7806485630326113223e3ada19b03c00	1610355075000000	0	11000000	1	290
7	\\xb0f0aa65d017f9508a8becd9aa7302859520fe8607cad20ef9fbca23c4a170faee5e59044bd15a3585777d3e48d9fb6541c66550226ec69b2b8023b7e955d1a8	\\x1ac082a6b2c7062ca3e3babdae5f8b23ce372f942552158edcd49af0070aa95bbfc30235fbdd9a9ef6110bc0fa6537b089716245b5ab10cc6caef615fb995162bb7ffdd0366540b0ead68b1d1e4485d716a342cae2c1c05320b1218b9b07ab8b90f66badb76bc1bd791eaaba085f3087732a9a96fa5b98c8f6b7cf15c65308a0	\\x3d2f48e2c1cf44c14dfe0aed9cc86f75d8f29d58bcf3fb54a2458af8416824d12836dce765fdc462707da01ed3d9a3ba04e82e97e77abcc7d1a9ac53508ec307	1610355075000000	0	11000000	1	290
8	\\x46af175e10dae437c83eb05febacdf8d2ad9b420b5f7f1f07ef239fc227dd6651304e3aae0cd7096020caf00fb23c2f217bdc5f0dc0b4810f2c47eb38f1289c0	\\x5c04512b1df6d04768ba3ff4c54841b90768f5527dda74d58c263944db97181d30666ede07a566bbb71dd984a733ac88e230d6fb4e87e173416936759103a10bca57f45de21f2ee4c8260c7f3d3543f4d5a1bab8ab51996b9c713e0e4892649a0a48c1bb85de3a2dd84c1cdcc6afbb6780be2dc341a001ad80868aca5f417d02	\\x516365b835f167e0da794fb5ac5cfb2ccf13540ab3b83cf1f3aeda5d301970c3910c4bea440e5a82adac74352b9594ca6c677a461976d2e8c640b50c7f1dd70d	1610355075000000	0	11000000	1	290
9	\\x0632d3946509890d75fc11623676ca737d65867b596e2e68e20e13951cfb609f2775d30b161ef05687ff80a70286d514eeefb64857c3f3a5c685410e490ff135	\\x1a54d17056c2f80ce342fadcf2c245300509b4b6efe6f46e3844acaa1422eb5dd7cc81c08ce7d7fa9da36518ca838b33f759bf707ee3da01ca81b1c16efdadd9c5aea39df260dac41c4936f7360418167dafe31d429c539070cc784f71a58468215f7bd46bc426db019078c02c253b9b8bf024fdc230129cf9e86aece19236c2	\\x72b0269cf5bd09b910b654bf0ec32b4e0461faf867c2b50d80a16369a474545ea2b953d267c9052e6f274337a3aa3784e886349090bdf0e44bab5393b3a9bc03	1610355076000000	0	11000000	1	290
10	\\x6bb42724406ffeb2204641097cdb44ce41558682efa02889193e364335b0720d7d01c85aade37bdd1c4721de168316f16a43b86d46033e4bb853b12d7dfcb0c8	\\x360a43f0c2de7187a34938fdf35df5e26f586be7298e8f79107e28903a7330efeeb7cb9605a9bd399c794ff8495a65946c25814635c0f805789d726808f6a832db8bbca0aef1960a2914c643136078e12f76ef01d14f2f70e864137acc3e12748153edb2c22cba0c4c903e687cad8c4a582476dbfad354129ffe8f0f0faf0769	\\x18b2d0f831b99bf236b12b5755c233d5217d3d38133572e4ca6332b94189408cf0c41da0938ee18a10f1afdc2efe7a9e9d8ed31b3dcf11899deb882feef64e05	1610355076000000	0	11000000	1	290
11	\\xbbeac777193d5d46c970d8cc64dd39d5e0c27a7fa7fe99a9d965c1ec7d99fadf61f5d28a76ede05aeb7640b4dec50c2f1f9706bdb4930beb40c9e644c023a8d2	\\xc732b141ea8e35a2f303df523f0dee738d93bfb65366376e3322a7c8d1976208a5db6bba40fb13d505fb88271514508b0134d5dc2148e5f6802443d9ebf0b334b0a795d5dd6f747a7e88359fd36ac88b24b3ee53ea53d5afc806e43013955e5c2724f3f425c148f3384fd1340b01f1240adc53da44064aadfa2de19b151ac41f	\\x9a015c72ed1941dd40a1b748ed5d9bc397b4918c0a4ddf6ed35c3f19c1bbcd02a196bc215a9784d6b6b69b1b20fd41efe460748bcdd7ee3815c86c404f2f1e05	1610355076000000	0	2000000	1	193
12	\\x9f11497c9d08781f51bd07999fcd9b7dfbdfeef28263b4f95d944ef71f58ef6623381d8080710d980014db1313ce20fb04b0f1ee7e7176c72a6ec9e31af72f59	\\x1ddce8da3c7d78c72572da6bb5b3a9c150c2effe6d340bcaa9bf494ff7d2aa29fede2cc976a343e17d87dad0c4dffc09538970450e1f0e32e6733434fe6c8656704459ce26e0a41db43f3cd421060e5aafbae5449db6eca46261d7ec6108fb3f9169a734bd1bcb89fad2a41b1fbd241426da00e6dcacf5b8dbb0bbf75a550098	\\xd3f079791cdfd258313efea0f02c0457ab49dc943a233fac88e8e158f238602ad3a873709e723ba60107de7c86c1fcc5ed057d968d1f88043d7e98eecd015e0d	1610355076000000	0	2000000	1	193
13	\\x16b4256039751abb11aa73fb8015dffae1ac4dbbd442047fc2b8dbff881e6773646424aab4ff7183e8d736d1e28dddc6fcdf1885e2b0af2d9a3dc915673f102d	\\x1a627b6e9b9fd55c47a463636bc736a246df68d474dbfcb925ca525af53f664eac01e75f374ce1870da1a5080c485d934ea8e782d1a4f315a5519b1bbf892ef3bd9a42fdd000bc08deef274b07e36b8b553a824da71580ba64b2721fd24d2ff1ac140bf40e13a4f67e997f491c46571fd5070244d7097ea0dc07936b34ad5124	\\x5ef70c8691c6f274c9bf0571da1ddd77fea08e2c92ca267ab9f0f14ba11ed414bc90c53768569f57802e80632374a6c74564f549bdb87a242030ba9c5ea5f70f	1610355083000000	10	1000000	2	204
14	\\x482fa3f8d70ffcbd8e9aa46c329b6bbeb740dc70cf5e0230dd11412a26d83017c8aa9430be1ce8ee54ff6d98b7a36187e850d2e53aed32d3f4510fee95ef94a6	\\x24754cd91ab99af65e8cbc96ff05eca45305008412daf5aa6e890c123582f825d98900a522ac0c6d85a72a8855b0dd2b2bf7ceea4962a28931ae583df735167295050189262c90757fc2c88199923421f98fa774f41dd80f137b7e34d910d1996862e00aef3bf62abbe6a62ffd89a52e4179d5dc7556265853951442b9d4b908	\\x3a601229fd6e3949ff6fcccae68d19f1ab8443cc7d3c0772846968b9cd88db0e1dc6ecc06df9f2f9391442c5757e423fba72d01cdd4612f3152cdfe6e59c2d08	1610355083000000	5	1000000	2	254
15	\\x0f5a835e927a66b5d20fed73ea66967e5b7ac812d5405e256d813058635069c71e898ce2e72ab52ecddf9c127d628a63ef4cb8f447ec8a2bf63deb8bcc2acb99	\\xa3b751d05f979174d8113021a4be18ed619a2c4e3b98227215aac812c15ea2c7769be95bb2aea6c6f99982cc1f53bdb204602673540ea5288c13a5de63fb7555adc82736dccf0008ebfd4335051deba7740c488574427a1eaa9503c2a3f25a8ece6f0ca7807f1b98ab6448b69d787f2f3aa43e59aa8e18cb884265c309f8a750	\\x53b1a38107b3afb66886ee548d3ab3e73d0384d4d5fb91925f6602f769a839aac5d4d3f0e35a2a0d7d599a98e39c13f10fd47955ba1c499912c14e5b03c02103	1610355083000000	2	3000000	2	165
16	\\x3c493d32c661f905fa6bf3ca489e4d7e35e6bb7fe3c80575352c241696c56e7bbb8c42c58e2876d47814fb704a2e0c2fb33d9bf0e132f2cff28a648e83112709	\\xa9a35ac3e8d7198964ba9292e067bade6004fbe7670f4daa708aa19819e43d2462d12f79f0cf5eedfda4a8a07fa92b1b692078203c1c3dc48c423e8c4299a203742e76fbec1b9ce45fdba3b5cb91758951b9d2677ddb0e3bbb65fb40e0dff7dd0349348108e1155c0fd01515c2d3df4e43ad45c05bf1b074b23cfec2a1f6edd4	\\xb00e8ed33755cca9dbfcd318b79d6b64fe4c232192570634b5cfebc057f91566316c2aadccbaae8df1ba022921e9c8c7097aa4eac3a119ff19279579773c7408	1610355083000000	0	11000000	2	290
17	\\x727515d28b2d8529effb2d1527b47cc5622eb81e02e6271c82f38aea7857b054f52ebc6744981d700ddd46952dc60b77d532f66fa987642feecdc8742f2daac4	\\x1727f1675a605eb1d8f57a0640d94f29f37272c139bd48e4b51a19655a867f293f62b5b9d84ec705bf7e274ec33d009ac2fced89df3ad8fd3ca336473ed2058b02656f1315329d8c183c93dc67b1272cb741451a8096811accab5218e073e2fe70c4a74cf8fb2c38db7cbddc51787d12f9affd4c85198d8f9fba25803c0451f7	\\xd6057c475f8dc105a031ee7e7bc4360397f750171c97e9b6e881bfa62557da35707618616ff0ab04469bb9742093c7ac83bd8f91a315fce5af8a088b3bd55c0d	1610355083000000	0	11000000	2	290
18	\\x398cd3cc8f7b89a223be64345a38c4eaf0362926bb1413a1b0fd42e3290aafc93016431f5fa59634d10ca4e87f15e549a17f836d99b27f974d55104f069cfffd	\\x34e9009acb0d64786118c65a16ad55f93f58deb49023034d914b25d09e59f2e7afc4d80a6a136d623477f7a39c5d13e8cd49b0c159c9492dd05b2e37490af95f79f9f360e3634bbf65e39a8be1809293a75519f32e8b978741fb92c2746f019e78ed4c7aadfd21da77c77b54f108a8345738831c3fee890f45efccf71b08ffdc	\\x903bceb1c20fa627fbc8701b287e177748ec51b00714348532a91a0a0ed39d6a620b3636fd05c4fa10d1625598915f6b91170c868a8aad6f52d2cd81ba8ae106	1610355083000000	0	11000000	2	290
19	\\x1ce07a8d72388c6ecff5b14841a87f9c3d09e1bc337f26a84276d2f2b20ceea82c358a370205104457cbfacc2baff8cf67ed06f31734adee4191323bb6af6670	\\x26089d388b403d7fc0e9c6bba6325c8ee9d26ffbdc41a4cb4741bb10ff292c11543bac108d98f09e9e14f545634658a507db6d9429d3c93555fa34821162b949f5773795300c24eb5d7a49506578f2e56800b1118f7ebd4a91810db642a23f981728fb099bbc243c689923e5bca39425143c3e7e7a6502dfea912a43b9a72f8a	\\x5cb30868887b7acbfc0ae314a31054c14bd0d7cad55036f3003892014de3c70b1231d5a4df908763b81d04d7e99d53a42d7816bd1944bd028388e080aebbe40e	1610355083000000	0	11000000	2	290
20	\\x20782eaa97d50bf0afaeea8b4876a922af28a1ed293a08f2e6f075dc8e0883cc281bcbfb4c28c6cb205ed13ac59aad5180b8b2e09c2fb0734585068b91684202	\\x2685e91deef17135ef2887969f41adf81d1f77ac671ca5a9b122090668fdcf238e55c1e549f789f54ad8eb750c7a3c4e672bafc2676f6647531b953382c823f66eb607577e7333f736c573779e9bac05ae3bc09216b7f4b66feaafc55ddb67090b850ddb11d0079fa61ff5eb097a6a937e842be2a3e6a6860249575a59986495	\\x439fe411a0244d67cf7f08c61a0deee206e57fbc4953310b6d029fde83118989b0a8c8a6dd79db4ed0e6a35d03a0d5c94310d2f74951428b3baf4dd123b3f605	1610355083000000	0	11000000	2	290
21	\\x4a1e2c025e9c7f9a10ab67522255b320e1f2446c6674e058710b826fff9135e3fe54be697bd7e6d2b479b8722aee8545fb8b03b43773da5785c58456a9036e0d	\\x25ac90088c51dc4a7fee36ab9f71eb41947cbb726ef5f1d9ce1e32c3c454eeee1c21c539aada5edddd7908c95ca6b4881f74027360774ea2b5e5852556620b722ef73f21e2ed2c327cb8b5cce724226a92a42d889d744903281cc7ebb8399c40511ed5133811971876470c6753d3cde0454395c7bd3561d90614a06e2c9311e3	\\x8cfad25f61e21a9bc6c5bab99e00fa54ace5e4b4e5e1354648bc58984d4ddd1669fd6ebed8eae26a9eeaa67d814676fdc367671f7c41f3b9012110d083f27f02	1610355083000000	0	11000000	2	290
22	\\xf070c1043bd5fc63faff46217d883d2b103d4b9efa53765769c24d293a9f86957c563dac5ce44c58ea35c53e99f7c6c58a1e3da9609d2adc86a4b86fa01f6190	\\x4bccba78d24d95b25f40b06d9655f775a68fbcd65e3dc1731174efcbd8040f0fe48083d8b94830b1cfcd1eabf16ed03d542eaf6eda161ba4e8b0cf77e4694a2fd31e23426960c2732fd6a236f404532a4def029efc723179a7138cb93cf25439b0800d987dc317f55b898b345f7bf084d93a7d012225bc9a03ac8fe9beeef2d8	\\xeb5f451c1162c6300b1f7ea19221610c3379334d94c474efc315dcf0f046a7ed651c823b12303e96e917d2c8997fcad3e3a60e74e611a5b40732dcac3aa2e30b	1610355083000000	0	11000000	2	290
23	\\xab4abe72f2f61dd3fc0bf2a40d5f6b0ea01e303dd4ebb04b347f9ae9b42876d1378ed0aaba90317be27920e3e638e4b6c79b68e9aecaad69b4a49fb3f8425917	\\x47c273f2a588997687de8b2ca6fd8099f40109564af2113e1e70d8e5b6c3da2aaec9614fc84caa7ca3c380c69d9b5954d58101e6a55e1f06d4f47a5c911bed52c8193c0d91c1ece3a540ba4f45848cef18f54a11c7d0b80eecdef329a565172192c56b1cbabb126aa3e9488f22a0d8132425e744d0fd3382a9eb90e8808041c9	\\x962162907d054177f4a7fe7ceb3488a7bd9f47a3072146ab838b731b78c991978d14ee18e5a95c5f775f6d548a2b65656a320cee447b3479b59e7c46a3cd8d03	1610355083000000	0	11000000	2	290
24	\\x62251fdafc52dec13445caa1f18159ece9e25af525766849638d1d0a54958215fa47d22c66d19d4d9c2d23e669ee8dec388a2059eec271810eb7ae58b12e2fe5	\\x3283f070e05d45f7ad335bd5c9d099ee8fe30d2d95c5f193ad9d99ac9afb41b710de9d3f7d1397d31638b8896c20486dfe0bd871c50108aa4eddbfde49d141cfdfbf0627e7fb38d3d9a3c6b60d44097893d83fd9a442291fd324bd8228a811f91d5a5ff7480a2096efad4745856e3ec5f2479b0291a5d8cde0fca832bd3ad786	\\xa6526d731091b0e1c8bbe69f94de9485cd226de0bc4b61bcbe0ecd3f2c35953698f7c9c8a5099a026de768118c746d534681258a1daa285a2c01caad5488120f	1610355083000000	0	2000000	2	193
25	\\x86538359c17c04e4d3ed64c1aa86ca9d8d3b739331b9acc8da867ab459764d4bc559a43cb2be38bd4a5a61648689c8a8b9ae141e0b505b77a00890a0da1bfa07	\\xa52594f51d5064c31999aebba1008846174a5f64df23ffa053af11bf12dc8796d3bf13631c86fb6403988123e8f9b71c28fba146271693d956d704778f92cf0eb176274e30e32225c0409695e8f798f744c32df535631aefd946f51d3f5c972a34732633d7489f84df65faaf217a7a1ac24fe6b91f23c270a01af3a3cbfca733	\\xe1f8700f39f8dcd0c886f9bf238cef8d2ae2e32b8c32c2267dad3279da033eb0ee594651aac974fdf7e533628e2429731902560a1d33aefaf16d17034fe9d90d	1610355083000000	0	2000000	2	193
26	\\x286baa5cdda5bd7705bc4df6135e900b7a6d46efcafbd61937ab75e44503aa1c6d0f47fb525ff7626296026d257ced711e7b7f6aaaa6046d33232ac1a16acf62	\\xd643c660dd179167faacc7f7624b48d29bc883f6bc81cb3cbe12dcad5ee089e8e09f74442828482da7f603043ab30d04a716a8fe79e1eb801bed4c6233b31d56c7ec37be6bd6e20d60d7e487e66a05d883bdd7b80bf26b3798a531d16e3ef3e1b81c49d3dd09a34d945c891b391ab32149e4302294c9a577f844a485adcaa6b0	\\xae721672b77a04184bf99733818827297b3d5ee206bff5da2fc936545fa29a49fe6074234d0c8b282ddae13cb88f63ab418935ff575d391b4b29c36d31d04209	1610355083000000	0	2000000	2	193
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
payto://x-taler-bank/localhost/Exchange	\\x5ba3b9fc6ddb6c21278df31a377e067579352b099c96d8283ccd2dee5b59e1492b7b474fc0471db0f902c57b1a2891ffd19a852b232d411dc83439d3075d260e	t	1610355056000000
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
x-taler-bank	1609459200000000	1640995200000000	0	1000000	0	1000000	\\x50674cc6bcfbe5faf1d4fb62f6e275eabd681aee0df8af0901e73ba3d219d0881baba68ebf1d55584c7080cf5c4511da76456deb3bb2f675b39a5d4bd2bd8a0e	1
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
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_shards_shard_serial_id_seq', 1, false);


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

