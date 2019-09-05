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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: get_chan_id(bytea); Type: FUNCTION; Schema: public; Owner: grothoff
--

CREATE FUNCTION public.get_chan_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM channels WHERE pub_key=$1;$_$;


ALTER FUNCTION public.get_chan_id(bytea) OWNER TO grothoff;

--
-- Name: get_slave_id(bytea); Type: FUNCTION; Schema: public; Owner: grothoff
--

CREATE FUNCTION public.get_slave_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM slaves WHERE pub_key=$1;$_$;


ALTER FUNCTION public.get_slave_id(bytea) OWNER TO grothoff;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


ALTER TABLE public.aggregation_tracking OWNER TO grothoff;

--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.aggregation_tracking_aggregation_serial_id_seq OWNER TO grothoff;

--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.aggregation_tracking_aggregation_serial_id_seq OWNED BY public.aggregation_tracking.aggregation_serial_id;


--
-- Name: app_bankaccount; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.app_bankaccount (
    is_public boolean NOT NULL,
    debit boolean NOT NULL,
    account_no integer NOT NULL,
    amount character varying NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.app_bankaccount OWNER TO grothoff;

--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.app_bankaccount_account_no_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.app_bankaccount_account_no_seq OWNER TO grothoff;

--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.app_bankaccount_account_no_seq OWNED BY public.app_bankaccount.account_no;


--
-- Name: app_banktransaction; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.app_banktransaction (
    id integer NOT NULL,
    amount character varying NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    cancelled boolean NOT NULL,
    credit_account_id integer NOT NULL,
    debit_account_id integer NOT NULL
);


ALTER TABLE public.app_banktransaction OWNER TO grothoff;

--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.app_banktransaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.app_banktransaction_id_seq OWNER TO grothoff;

--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.app_banktransaction_id_seq OWNED BY public.app_banktransaction.id;


--
-- Name: app_talerwithdrawoperation; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.app_talerwithdrawoperation (
    withdraw_id uuid NOT NULL,
    amount character varying NOT NULL,
    selection_done boolean NOT NULL,
    withdraw_done boolean NOT NULL,
    selected_reserve_pub text,
    selected_exchange_account_id integer,
    withdraw_account_id integer NOT NULL
);


ALTER TABLE public.app_talerwithdrawoperation OWNER TO grothoff;

--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: grothoff
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
    loss_frac integer NOT NULL
);


ALTER TABLE public.auditor_balance_summary OWNER TO grothoff;

--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: public; Owner: grothoff
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
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
);


ALTER TABLE public.auditor_denomination_pending OWNER TO grothoff;

--
-- Name: auditor_denominations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_denominations (
    denom_pub_hash bytea NOT NULL,
    master_pub bytea,
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
    CONSTRAINT auditor_denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


ALTER TABLE public.auditor_denominations OWNER TO grothoff;

--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.auditor_exchange_signkeys OWNER TO grothoff;

--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


ALTER TABLE public.auditor_exchanges OWNER TO grothoff;

--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.auditor_historic_denomination_revenue OWNER TO grothoff;

--
-- Name: auditor_historic_ledger; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_historic_ledger (
    master_pub bytea,
    purpose character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_historic_ledger OWNER TO grothoff;

--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


ALTER TABLE public.auditor_historic_reserve_summary OWNER TO grothoff;

--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_predicted_result OWNER TO grothoff;

--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_aggregation OWNER TO grothoff;

--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_payback_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_coin OWNER TO grothoff;

--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_deposit_confirmation OWNER TO grothoff;

--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.auditor_progress_reserve OWNER TO grothoff;

--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_reserve_balance OWNER TO grothoff;

--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: grothoff
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
    CONSTRAINT auditor_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


ALTER TABLE public.auditor_reserves OWNER TO grothoff;

--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auditor_reserves_auditor_reserves_rowid_seq OWNER TO grothoff;

--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq OWNED BY public.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auditor_wire_fee_balance (
    master_pub bytea,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


ALTER TABLE public.auditor_wire_fee_balance OWNER TO grothoff;

--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO grothoff;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_id_seq OWNER TO grothoff;

--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_group_id_seq OWNED BY public.auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_group_permissions (
    id integer NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO grothoff;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_group_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_group_permissions_id_seq OWNER TO grothoff;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_group_permissions_id_seq OWNED BY public.auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO grothoff;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_permission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_permission_id_seq OWNER TO grothoff;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_permission_id_seq OWNED BY public.auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(30) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


ALTER TABLE public.auth_user OWNER TO grothoff;

--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user_groups (
    id integer NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.auth_user_groups OWNER TO grothoff;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_groups_id_seq OWNER TO grothoff;

--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_groups_id_seq OWNED BY public.auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_id_seq OWNER TO grothoff;

--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.auth_user_user_permissions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_user_user_permissions OWNER TO grothoff;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.auth_user_user_permissions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.auth_user_user_permissions_id_seq OWNER TO grothoff;

--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.auth_user_user_permissions_id_seq OWNED BY public.auth_user_user_permissions.id;


SET default_with_oids = true;

--
-- Name: channels; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.channels (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    max_state_message_id bigint,
    state_hash_message_id bigint,
    CONSTRAINT channels_pub_key_check CHECK ((length(pub_key) = 32))
);


ALTER TABLE public.channels OWNER TO grothoff;

--
-- Name: channels_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.channels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.channels_id_seq OWNER TO grothoff;

--
-- Name: channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.channels_id_seq OWNED BY public.channels.id;


SET default_with_oids = false;

--
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


ALTER TABLE public.denomination_revocations OWNER TO grothoff;

--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.denomination_revocations_denom_revocations_serial_id_seq OWNER TO grothoff;

--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.denomination_revocations_denom_revocations_serial_id_seq OWNED BY public.denomination_revocations.denom_revocations_serial_id;


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.denominations OWNER TO grothoff;

--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_wire bytea NOT NULL,
    "timestamp" bigint NOT NULL,
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


ALTER TABLE public.deposit_confirmations OWNER TO grothoff;

--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.deposit_confirmations_serial_id_seq OWNER TO grothoff;

--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.deposit_confirmations_serial_id_seq OWNED BY public.deposit_confirmations.serial_id;


--
-- Name: deposits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.deposits (
    deposit_serial_id bigint NOT NULL,
    coin_pub bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
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


ALTER TABLE public.deposits OWNER TO grothoff;

--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.deposits_deposit_serial_id_seq OWNER TO grothoff;

--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.deposits_deposit_serial_id_seq OWNED BY public.deposits.deposit_serial_id;


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO grothoff;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.django_content_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_content_type_id_seq OWNER TO grothoff;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.django_content_type_id_seq OWNED BY public.django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_migrations (
    id integer NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO grothoff;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.django_migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.django_migrations_id_seq OWNER TO grothoff;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.django_migrations_id_seq OWNED BY public.django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO grothoff;

--
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.exchange_wire_fees (
    exchange_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT exchange_wire_fees_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_wire_fees_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64))
);


ALTER TABLE public.exchange_wire_fees OWNER TO grothoff;

--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


ALTER TABLE public.known_coins OWNER TO grothoff;

SET default_with_oids = true;

--
-- Name: membership; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.membership (
    channel_id bigint NOT NULL,
    slave_id bigint NOT NULL,
    did_join integer NOT NULL,
    announced_at bigint NOT NULL,
    effective_since bigint NOT NULL,
    group_generation bigint NOT NULL
);


ALTER TABLE public.membership OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_contract_terms (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    row_id bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    last_session_id character varying DEFAULT ''::character varying NOT NULL,
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT merchant_contract_terms_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_contract_terms OWNER TO grothoff;

--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.merchant_contract_terms_row_id_seq OWNER TO grothoff;

--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_deposits (
    h_contract_terms bytea NOT NULL,
    merchant_pub bytea NOT NULL,
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
    signkey_pub bytea NOT NULL,
    exchange_proof bytea NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT merchant_deposits_signkey_pub_check CHECK ((length(signkey_pub) = 32))
);


ALTER TABLE public.merchant_deposits OWNER TO grothoff;

--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_orders OWNER TO grothoff;

--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_proofs (
    exchange_url character varying NOT NULL,
    wtid bytea NOT NULL,
    execution_time bigint NOT NULL,
    signkey_pub bytea NOT NULL,
    proof bytea NOT NULL,
    CONSTRAINT merchant_proofs_signkey_pub_check CHECK ((length(signkey_pub) = 32)),
    CONSTRAINT merchant_proofs_wtid_check CHECK ((length(wtid) = 32))
);


ALTER TABLE public.merchant_proofs OWNER TO grothoff;

--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_refunds (
    rtransaction_id bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    CONSTRAINT merchant_refunds_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_refunds_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


ALTER TABLE public.merchant_refunds OWNER TO grothoff;

--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.merchant_refunds_rtransaction_id_seq OWNER TO grothoff;

--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


ALTER TABLE public.merchant_tip_pickups OWNER TO grothoff;

--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_reserve_credits (
    reserve_priv bytea NOT NULL,
    credit_uuid bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserve_credits_credit_uuid_check CHECK ((length(credit_uuid) = 64)),
    CONSTRAINT merchant_tip_reserve_credits_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


ALTER TABLE public.merchant_tip_reserve_credits OWNER TO grothoff;

--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


ALTER TABLE public.merchant_tip_reserves OWNER TO grothoff;

--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_tips (
    reserve_priv bytea NOT NULL,
    tip_id bytea NOT NULL,
    exchange_url character varying NOT NULL,
    justification character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    left_val bigint NOT NULL,
    left_frac integer NOT NULL,
    CONSTRAINT merchant_tips_reserve_priv_check CHECK ((length(reserve_priv) = 32)),
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


ALTER TABLE public.merchant_tips OWNER TO grothoff;

--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


ALTER TABLE public.merchant_transfers OWNER TO grothoff;

SET default_with_oids = true;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.messages (
    channel_id bigint NOT NULL,
    hop_counter integer NOT NULL,
    signature bytea,
    purpose bytea,
    fragment_id bigint NOT NULL,
    fragment_offset bigint NOT NULL,
    message_id bigint NOT NULL,
    group_generation bigint NOT NULL,
    multicast_flags integer NOT NULL,
    psycstore_flags integer NOT NULL,
    data bytea,
    CONSTRAINT messages_purpose_check CHECK ((length(purpose) = 8)),
    CONSTRAINT messages_signature_check CHECK ((length(signature) = 64))
);


ALTER TABLE public.messages OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: payback; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.payback (
    payback_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_coin_sig_check CHECK ((length(coin_sig) = 64))
);


ALTER TABLE public.payback OWNER TO grothoff;

--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.payback_payback_uuid_seq OWNER TO grothoff;

--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.payback_refresh (
    payback_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL,
    h_blind_ev bytea NOT NULL,
    CONSTRAINT payback_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT payback_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);


ALTER TABLE public.payback_refresh OWNER TO grothoff;

--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.payback_refresh_payback_refresh_uuid_seq OWNER TO grothoff;

--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


ALTER TABLE public.prewire OWNER TO grothoff;

--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.prewire_prewire_uuid_seq OWNER TO grothoff;

--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.prewire_prewire_uuid_seq OWNED BY public.prewire.prewire_uuid;


--
-- Name: refresh_commitments; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.refresh_commitments OWNER TO grothoff;

--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.refresh_commitments_melt_serial_id_seq OWNER TO grothoff;

--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.refresh_commitments_melt_serial_id_seq OWNED BY public.refresh_commitments.melt_serial_id;


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.refresh_revealed_coins (
    rc bytea NOT NULL,
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


ALTER TABLE public.refresh_revealed_coins OWNER TO grothoff;

--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


ALTER TABLE public.refresh_transfer_keys OWNER TO grothoff;

--
-- Name: refunds; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.refunds OWNER TO grothoff;

--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.refunds_refund_serial_id_seq OWNER TO grothoff;

--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.refunds_refund_serial_id_seq OWNED BY public.refunds.refund_serial_id;


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves OWNER TO grothoff;

--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves_close OWNER TO grothoff;

--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_close_close_uuid_seq OWNER TO grothoff;

--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_close_close_uuid_seq OWNED BY public.reserves_close.close_uuid;


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bytea NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


ALTER TABLE public.reserves_in OWNER TO grothoff;

--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_in_reserve_in_serial_id_seq OWNER TO grothoff;

--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_in_reserve_in_serial_id_seq OWNED BY public.reserves_in.reserve_in_serial_id;


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.reserves_out OWNER TO grothoff;

--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reserves_out_reserve_out_serial_id_seq OWNER TO grothoff;

--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.reserves_out_reserve_out_serial_id_seq OWNED BY public.reserves_out.reserve_out_serial_id;


SET default_with_oids = true;

--
-- Name: slaves; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.slaves (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    CONSTRAINT slaves_pub_key_check CHECK ((length(pub_key) = 32))
);


ALTER TABLE public.slaves OWNER TO grothoff;

--
-- Name: slaves_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.slaves_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.slaves_id_seq OWNER TO grothoff;

--
-- Name: slaves_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.slaves_id_seq OWNED BY public.slaves.id;


--
-- Name: state; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.state (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value_current bytea,
    value_signed bytea
);


ALTER TABLE public.state OWNER TO grothoff;

--
-- Name: state_sync; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.state_sync (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value bytea
);


ALTER TABLE public.state_sync OWNER TO grothoff;

SET default_with_oids = false;

--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
);


ALTER TABLE public.wire_auditor_account_progress OWNER TO grothoff;

--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    last_timestamp bigint NOT NULL
);


ALTER TABLE public.wire_auditor_progress OWNER TO grothoff;

--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.wire_fee OWNER TO grothoff;

--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: grothoff
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


ALTER TABLE public.wire_out OWNER TO grothoff;

--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.wire_out_wireout_uuid_seq OWNER TO grothoff;

--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.wire_out_wireout_uuid_seq OWNED BY public.wire_out.wireout_uuid;


--
-- Name: aggregation_tracking aggregation_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking ALTER COLUMN aggregation_serial_id SET DEFAULT nextval('public.aggregation_tracking_aggregation_serial_id_seq'::regclass);


--
-- Name: app_bankaccount account_no; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount ALTER COLUMN account_no SET DEFAULT nextval('public.app_bankaccount_account_no_seq'::regclass);


--
-- Name: app_banktransaction id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction ALTER COLUMN id SET DEFAULT nextval('public.app_banktransaction_id_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group ALTER COLUMN id SET DEFAULT nextval('public.auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission ALTER COLUMN id SET DEFAULT nextval('public.auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user ALTER COLUMN id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups ALTER COLUMN id SET DEFAULT nextval('public.auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_user_user_permissions_id_seq'::regclass);


--
-- Name: channels id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.channels ALTER COLUMN id SET DEFAULT nextval('public.channels_id_seq'::regclass);


--
-- Name: denomination_revocations denom_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations ALTER COLUMN denom_revocations_serial_id SET DEFAULT nextval('public.denomination_revocations_denom_revocations_serial_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: deposits deposit_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits ALTER COLUMN deposit_serial_id SET DEFAULT nextval('public.deposits_deposit_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


--
-- Name: refresh_commitments melt_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments ALTER COLUMN melt_serial_id SET DEFAULT nextval('public.refresh_commitments_melt_serial_id_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


--
-- Name: reserves_close close_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close ALTER COLUMN close_uuid SET DEFAULT nextval('public.reserves_close_close_uuid_seq'::regclass);


--
-- Name: reserves_in reserve_in_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in ALTER COLUMN reserve_in_serial_id SET DEFAULT nextval('public.reserves_in_reserve_in_serial_id_seq'::regclass);


--
-- Name: reserves_out reserve_out_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out ALTER COLUMN reserve_out_serial_id SET DEFAULT nextval('public.reserves_out_reserve_out_serial_id_seq'::regclass);


--
-- Name: slaves id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.slaves ALTER COLUMN id SET DEFAULT nextval('public.slaves_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_bankaccount (is_public, debit, account_no, amount, user_id) FROM stdin;
t	f	3	TESTKUDOS:0.00	3
t	f	4	TESTKUDOS:0.00	4
t	f	5	TESTKUDOS:0.00	5
t	f	6	TESTKUDOS:0.00	6
t	f	7	TESTKUDOS:0.00	7
t	f	8	TESTKUDOS:10000000.00	8
t	t	1	TESTKUDOS:10000100.00	1
f	f	9	TESTKUDOS:90.00	9
t	f	2	TESTKUDOS:10.00	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:10000000.00	Benevolent donation for 'Survey'	2019-09-05 05:45:34.941448+02	f	8	1
2	TESTKUDOS:100.00	Joining bonus	2019-09-05 05:45:41.320921+02	f	9	1
3	TESTKUDOS:10.00	ETQWBBH2T198QMS20J6DFSVPR6VS8CV81T6B06YWW4VGC8V4B470	2019-09-05 05:45:41.544267+02	f	2	9
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xe6ce6a175766f104b1f9d45efe95d9d0a8f1d6d2919c5d95b9feb4245722e0ece99c6c72cce56eda3bd650b316524326b792863995860476768fe4be63f51aa2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe685f0e212ba2100d60568637c798f3b0a3eba6710e316ba3b7934d75658069d17492e0c0336776cbcffac7df054e2bfebc50f90e0ee006784a4b26bf8a32cdb	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19902484949e554d52635da8c9ee9ce9024ab05a153caa01dccf8908403c6cfeb7df5a373f4d2d2c5fa791ea2e709636f02043a1e5b2630e2985b153995b50bc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bfb0c3813e79040e4791fb87d27618095e804d20a538945c5cdd213d744b75c341fced01accd9313da4cc15830cbd11d4d02882dc67cac98402f62a4bd2fb92	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17c2acb5594ab4b717fd69f917af0fd4c25058c7ad91a0f746b5473a7420b6ac6d4731ef46366a94b2f536c3eae9761a320b31207bb09f770753dc0de602e6f4	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe411c56ed955078d02830f20d72ad45f8052b3dbd4f5cb0866b4e59c9cba9839334dc22a39226819507dc5f06198092983c81d35d8fd563d20259bc9b5c29f8c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x24d5ef452b9e72177a3afbe2b3dd2edc427ff0df4cd8b304694de5eb7fb2cd4dd79f1007192b22c0b7596f60512fd8bcc7e07a04c1328bd1bdff4449aa818759	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa037b1ca057260912fd52cf4e6fbee830ec6fa15ad78c7caf8ee76814b6541a0efdac89ff5f66c049d5e7a86ff35517beb1b6110ada3d49f24bbf8828d2f7883	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x533458bda27fedff909266eb45932b019b2b79fddf711b2bcd87175ad0636aa09beb72cad296d4ba3bd5cdb03063928727a826fd66aaf38f880fc7183ef63908	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc79088e9b04a6c34bc35fd3ec038e3598234081243118ba59e76c1c9a9af910a5386369e5dfcc1bf2c2af8408ca1fe60fcdd0ee29fc38976afab98f346725a36	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x475e370a06ae1ad7ebddbaebcb147f98fd4ff27d7390c104fc22da5f1e67625297f6c36a3dd31388257f384dbca8da4886fad693c11c3645c93dbb599b345079	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2cc1597b57b2a527f3dd154a5ccf65e340a5c0ca73034d2a79001f79ab9607e640f2d1a51f40f0bdcfdc71c301b177ce7d25c74c642e3d3b51ab42d342b4162b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcea6eabf3bbc84f7e7366eccf47e4aed6440991336af53b0678251fb77afb1762db676906673dfa7fdb8ff18fa0f0b3d0ff7fed8348a6ce691f5375c4992afd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3375673f25488c834d37f3eebfcfb2d1e9d9f5d901bda8ab55b0620dba2bb967a2f33e9eb899e9007c014a09b64bf03ca0632316a641b86e1c920728a0cf81bd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xefcdce82dbb6efa6c12a262a99c8cf0f043e93ace2adfde3516466179153453a60c9e759d24a1994862b9d29e2ab3569368a582972038500a51ad25720bb5096	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x76fd2604e67a7d2a1a2ed16ec3772978afcbfa575649ff873545951e7252f2d6c59825192ebf5dc31a9b8a938708afa46a596380ff3e0463a969e62d8fc7bdeb	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdaf471f21e2f045597db04086eade39566df009d5a80e37a999d466212b343ec6930a23593e6c97d1b31a2ccbe2c8ce58be975caa83274cef6ca55b9c05e254b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c66b125352f9e0740c3e2a09429432a22a89a212d5f6d321cfdb1fd399c37dd3b08898a2b06713c71b301649bd6b38f6ab7fb8c5533c944de58e6a408189ced	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a80af01b1187e69e869a54995632f77ca84148368544263124512890f45560e26ecd294be6d0ab34169b4114171f174631efe0cc7bd90d42542c04525b159f0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9938d90327b87f4e53fbac83a55d1af87bc5f0504125286208e44dd6e7290e653ee39479ef703ac9577ab9d95f7afe7e477e115093e62610a6bac146b54f34a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x959effeacccb93186d6c19b1eb3d53becd644c78e349adb9af2532f6a18acff4d0269a99e9d67ecf42c6920a3d43962d56429f8277c753733e72e69528277f14	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cb96ec33c8df0632ac7df82d474c7da0eeda37db18dcef7ed20483c3ebc6b8c9d887fde9fbf53ede3f58ae414f23537b7c18b22b9e8edd4311d319fb3260020	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3eedf094ad21dc1f5951737a2ce2cef4815bc82d08f045f9cb5b1d973fb48e8dabdb8be081158de3bbd7f86e0d497d0fc96ba30a639591a07742701509640de	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0689054e00e3de444677f89f7cd5804880033a7a33acbb360b166fb4dbf883f26244c250e3f96448cf9999cb26f930e4f3e5db5063b65075fdb3257555057c5a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90a03ebaa5edf49fd739cdffe0e1196cba59a1a595009f7e0eb1d3c6d41822a3145e83a9a8ff38167716294449788f5e536473fd675412fef533a4280c4b2dd9	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe25e9212a01005313c5a606a6b27d698456c120903e72ca90a16ddaed97121803476cacfbd00a8307a38954d7dc0598f3893214529c947f67a39273306903b05	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39cb40862adfc65c34027f9765d80fc46e369e4c98409fd11a3c2cbfcdc49741e05a93c923810ae0753b684679d0837678503867b749cb70ff95cf5db645364f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0428adffef5e36600d90557219904186a29d5c23f38db23bfe51b49ab83e649833c7ff19d6d8c8b22810018b4c88284468dad6d8efac0b448b156264fa31cfe3	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccf79a8acf6d4e041e8d1a618edca49ba0c81cfaa4c7cd8093ed333f1acd9d67dfc83a0e67ba0e15abb6241540cb0aed810f2e5cde45f1230a18d2184f9f649f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x34b4795b8b6e34cc02fc9ba3f5a888f7f611b3ea483926facd2bf56cd950ee205ee0817cee53e1772284f7c81ecb4fe2738f558d79204a557d3da3b340bbda16	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc4d22d1586a58c9063d27f577d27f7db4e2c6d39b8667a535527f6dcee5cc677bcf47b60d0529cdab00f890f5396ca878940a686420c5e0d28f8d2e9806f3bc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6445f2d3b74ad95f0c0bfd6c1365413eb5aa97afb583a52eeb2e181dc86551f94afb198becec03963e835b716af0d7ca9b2586586e0782dd0e00e869f941c26	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e28171dc21b57eff77918ab0e67c763abaf8669fdd0d353906aef1f383eda3940e20689412767906a863cda17aaab8a499c18b2f3186a5811ee30a390e88988	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc29fd4c0cead9296602907dc4c543655ec0b9719de115e1e1157d610d9309fec9f9dfcfce3e41908dba924b174b8a696ec07da544e7bfc71a323b3ec41082f23	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x93e7c85b11bd9fc613cd10baf5ac0819bef822a176e8a4870874a5800f29c879941e1f8b1b1f593a9d0751a70f5190a59a46979fa425f6dbe4ff2b46ca344903	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfa2bb2783038fe463409be527748574be6906b9864c9ccc8410ee4ce19c00f724774e438bea5608d42cc01fae8065c7f0d6daf7f608c2ff6090da56a08c2c0c8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0124486b0f2520388154107cf5ee7fe8e98e65b7d27b77c7637406c0cf4902805b55ab90a54f2f4a493310c692679d5e57f33891259f2bf4d0f59e817df268a9	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71dde100495716525b802127af0a5343afaeda47eb0f2d6e286a5afb6129e60023ef24db6d42c6d0e6bed6e0ab278b5b1b78f23e13e47f58c801ae5af22d3739	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x89211d48c061772d8b0be6ba373049e2ef82a5379162cbcf9c361f2ee93f287fe3895c0f5142fd93f6e2866c001a07232f05ddb6b9530c2596dade2db857c994	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa843f3218f8a6f46d6b817b17d5cb48558629474540f064bdf1b94514999df985395783f3a2e8829451d8a8b3f5704eb220950d89ae908256bba118c81218e19	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x20a74218f630435ae85d03d0fd89c60e0b23800377fc0f7f2944ff5f86b0852d7ee60e63d56317b137af59089d76d5442c279df16cbd5de760ff3c26d22ef1d6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3caedecfa2c8325caea846ee58b7297d143401a87dc4f0d5b404ea2423b4f99e925268561f889eb3e59e191e2db78eae327281ef4685416d5dd20a4172f73814	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1ec4be8ba52e8112deac99b73be3b8e7645a5647d87b2f7f7edad1add0fdda2a2ffeb0f07b8d536bf19a4701d1027377be09e1b56ecae5e453957caa3b155b36	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x77819a79bdfab66ee79a9e87d385bb9d8f6b88c62291a0b1e8fa8c53d430decfe833d9ea1624ec440d471a01b160eec66a02e1c5faed0aac0661ff7966a5f83a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x63f5fb9f4c84bf7a83e1d04fef72725536b943b12e8559a67f449f877936186a10dab5bb747bf8373d3c4d5b9c4572ad9fbcfb2f598b2be90d746714d3a3030d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe47210f77a5447aeb9902e51fbfe1a967522b97bb6aeb10519348b8e6fecdbec1aedb9c3eb956c7fa60f9eb5f2e5f75921ae3f8f572acf2c645ef82b07267d15	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x729ae75d2e83ab1c664252a3ae9d828883783ca637fb78dcbb9f76df74f27aff4196752d84b6d13d5a0e53e93b03f3575324f5d378b59f5dbe7357bd82fc9785	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x248a9542496786e8751c1528c9b4cde52b9c5f54af39c9349358d157cfce973581d4a4cb07dd13843dfcbf2fb154bf146fcc0a95170527ce65eb42c127e76f47	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x68e93282ac839a3078974f737a67a4badf7141b9fc86fc8a96fd075dd0cdaf7238b403c0ab7fa5803f288a4c2482f9fa5952d00c173b69d0a844044da30ecb3a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x91942a10e9a5577fdbdbf7dad23c1c047853e09df5d62aa01be31122f9ba90708561031798637f574c4438ee255ddf71e6a0651aa2b1d53a35d48ac44201edfa	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9b5a9da0239b5618dd3dda20ea30118b91743974d6c7b5f74dccfd9a3fa3f99760c2526293faec2668af19701d419b198fb0f3351c0c5f3c4019241ed305b5be	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd01087a5935ac6e5efebbe2b07e2c5349b47f3e26bd0bec9cf76ac4c2e0d0717f0d4a30e264c652c04ec7ed60fec02a28f074f593356a606749e9040d2627d08	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x10dad1c8e526919b0e8ccfc2463e114ffd4ae3aa6ba8e1658230384984fb39d4a3a2d252df37a076922baf48f49e67b6bf66aad26dc6d905f310d764ebe47024	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7901affdd80922ee3da5af21317cbeca5d248e76926dc7848aa22bde3ad0b53549c383fd2500ee9bfc6fd4c50ea540a26cdc59e2b4036a689ba87ceb8776380b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf65ffc32b14381b84451b0167d8002850938ca3beac0c09f01e58e08eb5a159be1c04bda173d4012473a42562e9aeda1beeceda24c1fc7d784e215f8c3534ceb	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x06405b90e9b60f8c7193aea49596e554bed7ab86d7a7f67eb743cbca75d6f8f42af0affa829a69704d7af64333b3f0e39061186955b725178d059bfa92451d7c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x18c4b506c279541e6a5ea22d0d93b1bd425eb696d8edc361d93d486737ec8cff9b40f979c053cbe91f0595897a1b2247beb76f8ea1f0059f4bff7d13caec4cba	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x561ffa48008042e2a7091936caf9a5a58dd97b5e7a0f0530723be20920982128fec226adda9d713c882053718aeb4d04f50435e1eba1c9b477217e5a1d8326cd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf9c6cca2822465e9db556da8bdf9b03e868d729ce574c1e30397d6488c23acc3ce372bf12f6e2a8601e0174385db430b85c927ab4cbb384cb4b72d7a02ce6886	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbc5397655de0c81724c5331ee94a6d4bf6eca3f8897fe32060181fdbaa423ab8147add5df323c1d303607884a3015aa9c605a0042dab84a9e1e89d830842a5a6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x73c2802bdcc359534b17f29d23ca1ddd2e004ffa9b4c017a652d31403819407040f81b0e3351844002cd2196419a45b064d06487c6f61d89dbf40ef447d4df82	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6640d0990d0063926b4d7de075cef66a917dbf625fe1369b844d51a3c4069b431189d92e17330b29003a13c14ee6dfd69f49c15df2710d64300105a3a60eb2fb	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe7ee58c00fc49f84d00e694261b8fff3739f7ffcaa14d407eebd21ef84c80cf786c2b1b77fbea70e836946220a20deac088bb0595347fdf4ce348aa86cdf9176	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd26fa37330a44ab3061123879f961b64e232cc8d0b41c316cc7e3f05da9064a3ccda7534a44d8215cc4b1e82d85b47720fada28c3ae32ebe6f0980e03c677be5	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2af69876d2deac3a7160a5f2041e44cfe9f1254ce6e9847d22f755f8b003133dcf3614e718dcb77b0f684933cda14a0fbe5d98bfbd73fb02b83760e80399ef0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcac5ea5742981e9845338a9cd8c5faaff25d4aab3c8f9eb4abc49bd1b7e179f9adf1e945eefec13363651aa5092c31c55fb8cdb15ec78d35e074ebcad10a8e97	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x22369e9156baf793750fea67c175f50a046767c2da78498e0757e3fbd18971daec1e964e881c2ea98d009f08748dd23669b6373cdd76eb719b28126c9f341d3e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a26c34ae18b2ebf5b1ea29a0b1e1c0fb21ae684d0ce48ad78750d83026a6fb0dc03bc5cb5b563c0680a6fdbd45646112788d854040fcb6c3ce2f39fcbc45bfc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5de1d29a2ae4fff55ddd1b08174171c8dca1bfda13b6b0eb6730a41313d740a1c343a409863f35deaad1861fac1e17a833f3db021a2de71eec8b63d6dde5a83d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6c4bb55d4d2338e7e815ce617075a84b2fb30b4c554d60abe234b0238f10ef17fdebd4fb2ac1a06335b7350a6c312c41f9ca30d2842298962f185fac11d0a90	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47a7218bea367b3c5d95adbd652e52578ef2cd4debcc1eabadcfa207ffcaee10ebc28ee8b13f12cdcfb72fdc983a5f2f604cb8a26dd5d352a766091c9f71235d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9d571702331a16763ad6ff95d48e3a562fdbb42566e62c3686a3bec1c485dfa841dc18c7d36c5a6d7645e464fed4b1569656f2076cc00ecf8ee62983f287b37e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc6ca59a037107e7312649eb1b16e64566daa5dd4b5191cd7d21dafec3b32b77a86fb884787fe3bc6d66c64123120a13b3cced742c445fd6a60fd493657089cd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ed610495be0aea8ed9ebc085f81f5394e9fcca46aab98dee67b832e02b8ff7b543094c2c08c86e47555566314e26cf97411247ad7216af5ef78945ce5a008b2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb095a4e82b5611ad07a731adfe77f319ce2ec1c7fa0d1a2e59d4348521dce19c81c1fef6fa74e8f41b314f342cd315b73a0a0a2abffbdb1b9927fe4389f7b319	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d64c7012702edd2c8c3380a805f748b04dad03daf45cb11574af96874f3697fad6e71df0552b7449162411a461632a23b4a9cdbed63cc4fac29bc139c9486b8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x300577a7f9086ff0fadfbf241d4050abb9af1887c90d8371be53f9cb7627b581b521a01b8e4e22b385397cf15c46a10893ef7ae21252d11f62f2b345fa5a4117	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xecf1771ad00012356794d2e6babb93a28fb26b6c60352e3ba2c0c010b43f3807acca44946a9fc54afcf60fcb578aabc4c5c1a02317c2bbf6b614402f725cf43c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb87c2e3bbf04652a2126bb466dcb4378c48c7adea59983b4096e7688b349962c079b0296d9619689937665665056ffa3c573107b9806d49c2890f79f198e568d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3359198e7fdd17300b2725c4e1b142122b798f67a6c4f049c4b231e4d2e18a527fe0004049cc07361b1dd117fcf4242f52b3359cbff4bfacdbb770a81376348c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf084937b60860d5dadf1f080f3b80d946dd4f0d58789e4498d79d068fcb64b79b4275598837d6f1b61d5b556a9af0554586ab47dfd5c77c49c71efd7ad22215	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf912eecdffa8e148988b6cb9106636c0d094980f21cc1833383b14219c73a391185fade4b6bfe928f123e48ae5161c15aa87e832b1a08c8ebafa3adbc25b3118	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x48597c0563379d27a161fbf5511ac0bea9cbb5ee5acf7c06ed4840814f9e218d655bfe70c4cb0532b193537f8ae4905d6af94a507a43cdd4f1c08fc1b916b0cd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9006e64e1b6f720f73e9503cc31fa1ea4ac78cedfc11f498e8b4752130827f9aef7bc383d24a7b732ad438190a80b623be40ce4063b4e26b6e56bf9e8d4ad130	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x631e6c052b063799b748122b8bb2f8c7a7d53a10eda4a1cb156acb78d7c53a2499c1f0f2332850365b0e181249fb8ddcff7bfac504d322fab88e9d5b794f59e6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13b77a6ff1bd7acbbf162d8d9a7f4e72e2b66d1ee1af50b4897e1f8058b56113fb9e5ec9ef40dfc1c63d85229d665e871ebfd380ae153b415772f1d099b51a5f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd91d78a76c4f3a5a5d00945694ef3c992b21a997bc0e7ab759326aac25a2a7f612477ffdaeb8024b21865d87ffbf3fcc78e61fb92ca52fe38053e2e4aa9f3d0e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31f411bce103f384628f57662b337a01e6e65fd0123bc0b94953e0d820a6922e07a3f697ba8858ef722f28c4524262350f2178b3d9f5c07ad1d24824c8ab2ac6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4548e139ba3925a14696e81398f18e4979b18f66f4cbd484ea784b8bc8ace53759e2d561da714accd30070c1dd5482dcfa6d5d55990a4a1e48316987cf0c676	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef1f1a5ba87d3c9ebeea3b0dd486b3cfc3c3130bb98cf7d8bf1ce4200a8c0e0a0770b3dd81023c5f6b44a755ace92c89c6ba35533c294a13a02ab7383d8a0392	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x01c90fd2a364e0a72d7dfae31739df084f655c1f0b6d4ab5fbfc29ac025c5d5882073890cb7056f9c6ac28592a291c621958551523070c315efc8d6ea1da806d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa13e33795b262dadba4c4767606fb39af421bff492ed80943f1004358da1352de27ab8f3de6a0dd4755ef071514a5f1c0ac39ad017e94a12238dbae1e3d399e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd44860ec7f7b91c240e07d80a81d3692cb42f208c63a57ef5614ea0128133fcb19b8ba5be0365fc41dec277479b243c146d15dd31e34522d77a9f0496560a4dd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1e50abb2d469dd7623705f5ee2a1caa3450a6e8f908be93567c0c15097975b3904bc3509480ca651bb98e81e7b1698bf41a96d931dc5737bbd052ca552c4e29d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7587a2e6357b343994d203b550ab17577227c74da7bac423a9d3896e0b28a833f2c8c18d995b46c13f946a1b416b0e3e93192b734d416ddf199134c2ad037d29	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x145db03e4e4c6d77f73bf26d8139a4d3f9153c7820380a9f780388d7128caec744f0ef0c8a271b876337e32c8226b203a34ba0d55ba64c2920fa9ed41943ca36	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2eaf16ec938578d57ef165f03398a4a64d9193e691b596b061fcd207c95bb8c008b6b267fcdfe5dd7236230f18e63a874338bc5556490779561c69d53a4bc8c0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1b54691860dd9035fa09af14a7a92613a5ac0ec91a345c9fced65e4562bc8b576a15377d075062ecfefe12707d1fdf5cc3259399f3e52158aec0e5cf03d3fa34	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c0b69c624591277658624ae310b0508ffd6c4a1f2ae9eca0e4f2d61d3004bd9197741265e78b248001fd0c7ca0c2707d4c5f20a2353394ea9b5f2dfe8137947	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa43885859b2c4de3344697f55e74b2bc694696021441deaa69c288784e652edb9250c935453f415c9e5e01c0781cb1de97951140e97c8d694ec7b65b66bfea09	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8695e229176c69fbfc51e4beb49f2fe2cd0d31733451d6265e536845ee3ceeaa348328141e3807331c7967f3851f600edf05fc85a84bc1792236e9febf1009ee	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x96c3d079d473aa9eb2b9d2c3f291132447ebaa76b4d5872d0964b471042e30e709e5ea0219a14f786b016253998c0b7c7e30006599d88c630153d9e2ef851398	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3c2ed18ac464825908ed92bf5383ef11cf5b27db0243ac7fed7a3c814b5dbd642e3fd810dcf3b9d0bee17583c33804309c51245bb2e4162cbc83781279922be	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f259bfa81d18f8c3023f206f2cc82bda4373761c2187c3e8685cc3e053dbef14c8bfb5b3513157621bd66303424877f306956f1c0d106731fd0358aaecd046d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0214c71a3b60b0a3881eb2bddcfee3a23409abe4aaabd8721185499ae58587203c59bfb70c78fa66172f026d70ebb7de8f2c3288f23419caa379d49d7824206d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13a88b6c609fb892347199199f93894d99c8274d75c2e6bf643106ba980959ab874e4c2c3a381f47fe942041ddc3de17049aa77da90fb3fc6deed3bbe7d709a9	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b8316449a21d7880e74381d0cf896b0e280ec8e40c299640f7f9b43ff447880116f2cc33f0b7d18084269de1669fedfc81221819722ab4d53f21bcf33d4f0c2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9615ebe9a5e2bcfab184bb00eaf87fa984d0ea5d50e14ced516a22ae519553098d88bfd6e5ddc65dddec97173fb749a98e94bb01883e2b203ea95ba0013b2892	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd04c3b41273957139878ce6125cd387d22ad7b994a5e06f5841940ca495c5679b0547b1fa07d055eece789f6b03295a362de1bdaf7beb7e962524fccd5c76524	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd46180d771a5ef02b5a8ae9a9ae693e4b8729dc0a3add79d6b6c5a08a8cb16411137f0ff7ffa50efa66399c5f78cbd4787fc5c8c3b5990228040c8ef053290bc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1aa4729a26515d9bc32fb9653817afb22c1bc3a54171f0de28be0e5dc69637d208d1b11dde74e30abc005b35a3c8a15600ddf0e581ecade274b5a5d5291bc34d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3803c079556acadd6d65ce150a95e6e8834f0345e5cdef330d097f27931c7dabe3a52625e57a8a8d4bdc4993a2a8076eba22e9652011aaac25ffdcea8a123b9b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb0f55272d6275a7dfb1f23297381d633e31251546199a39260bb6f4456718854fa8527be7d180c70e38d152833c6bd993d75995c56519cf70957e0dea303911c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2840c063a0d7a45a5b9573285751cae056de8bf8f905902389e148be68a68daa5eea99ba22e002bf5a093df850544d52fcbc12c9dd0ed731b1a065d758e5c49a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3f4fd2125e916630213c2ce056d90068ae9e3820787c462640e8f18068c7ed181a9d0a9c37ea1d2b8e9177a262643bd47007d5d85d69f683ae5e72d1ee6c9e7	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc3905532e36f1a605e86339271a6364bf89c748e6879cd5ce0aacd5099da75b921d5a9e4cce5d9e40f2e221074f5cd8494aca78adf245704217fb2d5a3bfc1c2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf2fd74f185f588d9138c8ad6459c7eb21a67e593be2c754b7e62b8ef304d896899d391bec738ada06863383fc6eb10d0325588ac39055b3865949020310df052	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3cfbce7535898119b2be135f47332422b23d51e620ec23c071b67c463e24ef755fe9ed2166d623ac0fea20bab4bd694a23e136c695da6daf993c356f6ed6990b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcc147e73d6904a9482d3397da4c0e9853ef2a7f1964a4b9e1106f99e03703d4cec3c61155f079db1b4d7d8c4c15de8aae7aee006a8f3e05d98f8b7649b18a9f0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb923c5a3414b2213ab8edc4b3183fe4c6233a9aaf2d387183dec7241db5aae27feb20d56c759c4e852dd331dada8aa20df53170708e2c7a730c79504c6e068cd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc8f237be6348414b4be07259895bf1ac91c8961622a14e0ff60534eb1e11a377135b3cac80a7cb3b3358698663d465da5f5d0896bff3b91bee36f5c0c540176f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd6c7f3c7e80cfcbad4cd6492639b68ffd9d747621c3bd00e5eaa860d73213a8f1c8b2eee1efe5a6d99ef695a513679aeb924a3c736307cc4861165bd30a77ea2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c4097d4f2e98ea767f5b5f53dade19807be325ec264feac3adba603b47312386f50f4f30cb21ea7c9d933877fe058eebc169677a58a4a3d7a037ebe63fca2cc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdff0beb61ab4ac585ff8958d4f751a3573f7a020ec95677a92fa20273af462576b76d39b74d8d485f4f33a59f626e1d7fa7f489f2fb834c724402996c815518a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x14ce1013cf4eebf0ba1af34905e745fd176a99ee433ae997fbd221d25050d5e602dfa877f0cbdc4df7178a91d9f7622209362350f97487d5939c50048a962abf	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5db01d9cf5d64c65deca6f4f8e2ee09919936bd1f59808c7dfdc66b450034254b2540dbacabd7d3cf09b02eed167bd06e3f58d640642182e51cb57c62f969ddc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x337f3a585cdcea90d68be39716e9f47872a349a2943f8d449e10881238949cfd4a77b711ab6f91911eebfd338762fa019b4926b89b45e1b7963290a476235b35	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59ce2ab8a4450b6789147150dc12a2cff8d3e87e08b4a3e20f79b61aa10355866be4e8d91c7c4046badb840a9747de31c167670db5e1cda09ce11244ba2f8b8b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf9d0457475066db4f00ccc3c5ed4e58bb4980f281b32c88ec1ba60929dd80779bb0c79919a06422f99394d4727b6a8cf9c0ceca781ea4abd9df3c504d33377a1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x725e4aaada5a8f59563baf14e3b9ba8add14a279635544cf141d7bb860c0afc97f9e939a43f3f5f237fe82b22d94b087dd5a429fccf82c87f6b3fd8e343ed866	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59af7898d190bd619d247293cd5cac9bfe5323a7e370fe30343524704ba2c6431dee1995ad11dafbe004640d4110cabb8a3e3faa681708c9d6451da8554de21e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb695b66945710e34a808e88b9bc67949b8ee264888d353658d91996c8b6838a0a7bf58d7bb143ec372a70eae69f7285ecc1b470786e29d86d63453ab44d5da59	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x815c0050f1d9cd5dca99f564b52ab0115bc7c44658cba49c70dabae2486598667efb56cdf816b8836f739aabb74855a34c92efb5be18e5f33df369d6677ce3e4	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47d29f4456371021d65b00a91aab6629917d99fa3fa55a665980dff5cb321844841f7b1bf4efd763f1e66fe33768d104054aec03cb87a46dfc7343010d11dc8e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x51c2d1629fc78cc5277adea3b73a579e6db923fcc430502a157ba23370c4c1ef1ffcee69bfe35ccfec0b46feb59760f0fa618cf22899f0dc2f4f86e27a4e6a4d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x80253b3ba7d0acb59c8e0f6151919a95198bb7271603d32336943908b8ddeef50bba19179f9e49ed797f8ff034a28cc18196ad1bbeadac5bba40e97cc47156d5	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a937f59fddc40a3fc79f795310199af6bad7ac496de825e3aa9aec4f31bfb4b933db2cd8d90e945ea8dd2b9877e71b070859334918c9663ae4af772b66cd1b1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaaced1ca63de6f8b11ef4fc9c2e739cfc8c63d10390f5712dcad68ad631c0ffed8480ec4f470a8c26690ab2a49b530a06fa15cd2c64beafcb2113fe5e51b1198	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f7bb554e5edd10328e31770b097c8e77ad07e9548a63ddda4154b249803b762667e57451a2528ac1db24a9f18e22e3cb72cdaec041821bf2e4b823cd38f807d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x708aa15c66967772861c41028222eecba739260f6a838ceef3a6df16354e74371b8e0a750d5f0b898256083f6a37dd2df5fe764beb90402cd5e27f23735cd800	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70a164d1940086e35b7c3faf3ae7be310d8ba09541f8ba0937e0c83620cbf57975ae279ed4edb8fa6aea0083178b9300ea8cf9f4102007d71811424b67297430	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8fa5a795adec84bd7f4a50008412e15c5319366213f8505098d861ad34ed6c2c0f1cc308285910b74654b5f2e24e371474b9a9f2445fac2f98c4e2a2b9d5f69e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x20d0fc706abc3ba782876f1f417bba5b8404f869f085c20a40a222898cfba68eb6ad1c86f5f77cb97f448edc07d9baa9c6df89b8a95592ceaf0eeabdc09cddce	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x42b356e550eef6a227185c7f957cfb87c843626ab7367c1298df6b67a64ad798891ccd897c31eabeacd424cd17cf9ab233347c9cbb3b3186327e2481e351630e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79157e0a6cbc56a0e87af33a58e6de126f1e3d44676da78989177f81f0cd2e4f8a5100ca97ba8b0d3e95b408beaa1e4e9aa281c411f2ce3ff955b1edbf53f608	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07b384e03c019d58343342203f00bdd19de55d0240b91734c1cb91e70366bb95b91b83ee2b4b3cf182d7daad8c4bf59b5e9b30f174a8dd0786857afb522ae8d0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4bf95772d32ec1a2d8fab44c9ebcd3b6caf0e2b4f3f677a7777c34f192090f292649f1ad435811ecb2b7c1b5d027f052e7518bd5db58e9b1ebf8e99d6731004e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc06c41eb8c545c10b05393d81a5b41a753e8198738c7bed0519815b3be62db3a724fc4711b268158af06a6ff10cac2359bf0c9051a0228e80fd9e49f9751ba55	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6f1e859dc55751e389a7831ffd26ebcc0db147d2892c7801e885d6717b73a6255bc0e523e4d1b54a609bcd46f148382421059dc3ff810beee08c1244af12d866	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xada0a176fd700c0b03f212f53dc73e1c90587944ac9beff712e8fdaee4240cfcffb009216cf1818a2b7a058db918cf95d63eca51cd31829bb103e9ca7a6961ae	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x807611243b0c0faba75e1c80833e587b9f14ac1d1479e9915ceac193e9b0162654680c0e19aff8eb341ce68c28fe22a9375903d288b90864cc3ee6701ee4437b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6392dbd266943929382affdac0fb2e1d1d55ed2ab911397858b80c01ea61492d44858834ad09dbd1339d91ca1cf73dcba9e71b05a5fb18cf1037b8f3aba664bc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13355dc0f19b9029f9638d7192a8f9fafde07d574c42b739b7a7417e7a1f46f1bac45195cb2e7440b668785f4e09be246d7b8319119e892ff5f629d1da28e32e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6523c5164f283016a8f4c322ee85d32e3c8039ce5c78f94eeda8ff344e178534e5c8ab8882ce32685e3dce7ffdbaa887e91cd0dd99c0e5a194cb369ff49e1a5d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x757709830f8b6723a527d80a400f356617aaf41b15aaf91036f27779e6a9f87a19dd0bf55ac24093b8f2533dc065c534c582ed351d8fe471bfb1f4bce4c377bd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bab94dd4df8e73ccb47b9bc7436d667250049a7c8d25e9fb45c69ead15b1bb9300700aa49aaf543eeac1dfc76f5c0d3d8231443d267a1f195d629d8a558aa97	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x03f077cac08d4ed61b24c35bbf1021c75755150bd3d3f525cb6a360f2b303f17bd011563b725095c57ac5d148d490295d8297b51a1e0259cae0b48d51eaabaad	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6ec9c132f2a485aa7dfe5499abe118c78708adccecf78bca5636beb3d5b2490197f4ff1fb87391e71bfc3c022ba987d9c43045b70fd0b4fb5bc9b7c70b609b2a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x39552d024917cd763d7a9afd7d94d00af9fd20a8faf03726458330cf8f776e8df077e0ff0345a73ea455b337068d1c6fac265457ae5048890c464765660ca7b1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab37c5057ad87b64b3be2d2c69a1982a2527df743579eb19653e5b2b705a0d25b9b1b23afb15c637de892f803893935b15930da41ba6e5563a7e5fe895abc1b9	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd12d330e25d3d10a7ca68288876d1545fb29452589bb2a910190ce4aefe9872bab84459287dedf6aee532ee7dc25033654db6e671cc9e00e51ce3e38f8d2b851	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc3de0a5449c52226670cfe3d1650e3cb9c496e28735bc2054ce487ce21e57d5528ebe67c0221e2505cb92211a640527e9c9934884ba9846d83abeb2bfe1394e8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x80d511b2f53a7fea6c7b65c437d2088dcce237bb2505fa010b5ea1ba04c2d281e253640611141bcbf28eff82845d10237d9a45d6e3198a719c0694845f2fae0d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a085414c306507ed24bf74771466709c78b80f9f05ad07d98e984755bbaff7aec771306efd62e2f180cd0f43d569bdce7fb0f8879beb175646118fd1a6969cd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5aceb016d1b730661deeb18321038ff9c905b9496b159e26698b837a5737e9ef115fdf916380ce0caea728742d43452cfbaff8ba43c0becb08e89601bab736f6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad63639cc3144f7f188cc8f6c612e482b2468cd490fa91e36d7acc6ae4de655f16ef34c4d42ee98dfbf3ed8ae8781c2786641bd851a89ef3ecd0953d7266ef8d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x55bd0907fb88a86c364aa63a9f9a76dd3c04fdb2ab3f88df4395462de06d051ff03616f9e872817a31b6350d71644e2743d5ae281e7961a3bea297078eb50d9d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a0b8e67af9212048f2b06de091566cdd458445eab003cbd3c6a3f41c6636e4840c0e6a1a9e44de53e2f7142bfa9aa63ac76f3b51cb2d0b1f60fe7931c4e58b8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2f952598552ae7684d42c3b6f080e507c71b8977e7d24bca77aad4e8640611ae171ce790aa567b6b348d9b9a35ec75e18f85582485acebd838536f6ec3b55496	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa080dd5f1f05e2621825cac7b425072294cd761734b8e47339db881053d279295d55d5567cca906cc9a73b47bb77913093485b95279e5f428b7a51dfbd68225b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4898194087f38a3889b8255fc34d0dfaa5a4c02155347b633f55e908e6384edbad46acfb8686075e02847a571091b78f9c4c1e6d183e0e72f88bafc2f70a64c7	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdd2c0a69afae2489e22768412c44fa77510decc4e86b162012ef2024605c6c610ec6204c37e0ef4d4a4815d1db11cfbd5d0d4f07e56f58e73fb095602e14f3dd	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7f0507856869960b07b6dac76ada162f42dfd2eda19430ef3b659bef8ae28a4298dc104b41341bc8b63bc16dc2b233717e9cd5e3d0f2d696011da12f1d802f4b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3e570becc278fa4d52f017bce529c96bb66c52d3b0493b9b7479b81b619b892c5a27c5638d2d80d8c6b4023ccee37f964a8553e90d514381b1585d105c745aa9	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x91a75934e13b030b5d8db669c2f277b13afb5f96974ed747bf718bfddbfc3b4794d3c994b87ff2dbae084c67afe8374994f580ac5e407e8d9dc39d45e715934e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd39f35d3b4da7c1f00adfcfa4a27873f5e80cbee3c19e650bc145e51b0592ed6a12daea3ef94121fa8193499cef1057aca14bcf6ec111c83ecf5adda4c510832	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xae87995455bdd00aebd9a6d1b81a9d564fffc664632d38ee9030fa0d688aa988d0802ba1cb4e312168224742c12b08aa7ac587f033b8453a6b98f4842271a6ea	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5cd4ce8c5835f834328f131efd435c09198be6bd6373b0c017d576aec0cde3f3089f226c8aaca6d7e4d7fdb19f3d817e4f759306c425c2fb874381238a96bb3b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x67492a16066e8df0d4bea4105230edf4815dc6f62cfc73a5bad26154c9503a2339dc452672bc39706020e57850abe78cf30323d044763c17aee133627cb7de58	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc48d4fa68df8ac5a4027f62b5a24be5680ed86ebb051a5a9c5e05167be466e0c52e52c6ec5865ae66c196385fde57f9084b4e3e6bc1d6f6d62da454447ea5777	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x384e890a6e5dc67a2e160407cfa60f7943e7d47b66e8f8f55d37026a90c4f4c9d79a20de66cc5fae125136192759ccdb8e2759b82aa378ae2e9afbeb2ba98524	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x388f6e4714e4e806a2cbcffb0fe016e5bc273681b170abab710ae836ed58d41801e6362dbde551d102cd26d4649391f2b87d1eeb08acdb9837ec1155add60033	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6eab4d4e841899d5f9758af6b2e4e88f552b0b2a6674f7c5621078bf6982148c2a9f90e636a468091a7f368c43c677151fbbcb7473599d6010a600bb889ddbdc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x023d8d46b4fa92065a58af2399a7f888c342b3db0f8fa493e66d1ce9c1027f59cb73bd615bbb65547b732409ef69fe20217ab47e331ed4220f7f5d82f27ffdb3	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5509d16058996d8d1687b55975796fda5dec6c060ed356007c1c1557c5d525a8fa0664bb34c052e5155a184bf24facfc1bbba643f5d8529f0c89d919cbeff881	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfcbbee89915890dc896694dfe07e086fc5b2d1761cefcc9afb389f1ca80e441c026e31899128228a3188a15861309f45e19870a76143b977fa7ae570da400242	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59a48a5272e2cbbcb8f28c73ca2fbcb819c4925308a19a01719e8b1624dd849ddb45155bbcfcee118b5861ac05a54cb78be0b71dc6cdde102a5c237102e36bf3	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6afd4c63860a0b5c4253966d3eabac89c3f57b9fa8f020fd2b6102188a3e230642b687d16e757e3b2e5993491d63513ebb77dc4714f8c0ee6fae54800ae6de90	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41f4765316e23bceec615372461cc3a7a1b79cf7c7de39948c473255f32752f2015b91c5515263ef795d82b3d45ce22b61ba36e1abe89079460cb7cfc95bf91e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb2194d4b160e0e1533965058b0f27f2a97076be8405457bc106bae7ab65755c51e06cbcfe7489f35b0bc78d7ea3a46c53bd904ae1731473523644b86dc2b0d57	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9c651dd0eb53482f39c27f6264d20ad69af180cbc6af51d810e19f02809bc5b4b30e0db1d5d138b0e71204d870d4035af4281fb17bc6d64c4311c3cf8796c636	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x54fb8ece5ed8e54ece1c11cd0cfd0254851ca4552a8c04c7a28cb299b23e49408bedb6d09e2a04f2e66590cdeb0126edaaffb0f1319213be0011ac8c14f07432	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e94b4b1ddce4cea18129887fb8bb1e6c4bb53b42e21d139ff7d88548dc793e9fb559c3898019511e997c31e316faf5f6d1b19d00a942668a21cc677f1129f92	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x601b95c37b300d53b53ac452b27bcca9a17164bf17f32309b4fc7b6980c94a54610612eff9d32d9922de8a64b0e82545410e80841c53579a5ba6f6a265178e60	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x32f6bf4e248c54806fd883db4c7bad940db4e84f7fc85da4cd08d2e08f08061e2eb51a0c91c6672b688394f49c2b481d16ef138952da47a63efa8b2274711428	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa6b8942dccb9f8df0d1472d9ee0d34b9565627212d3c5470883a3163bd1df4980854fb170738f3a297cd6bc20acd649d97aabacbf88eb7b5944aea343fcb3ac0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5119c303fc8b814c98daa0e3e9bf28ec1934c111fc49a27565c3b3a96a094e40cc1c5fd3ba4e8209376d9745ff1489f129e3e124439becf49c1893211968ab8c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbb5040420a1db5dd4e992525393942d498398cf3b409e1ed57004ab5d1504b8a1a6b0370c997d19a3cafd1c50025dcf0d4145cebcd2cd7e3252a047839ff8d0c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xba9eb4adf35d365d2478aa5526eb3f7ecf9637864c0b0d57dd0925a803a71af5d80aed231317b0cfe5225b8f851cc03baf84873b31f3fd1b18014496be3e85b8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13e34a6944bc8bd5486d196b90f822d58ae71bbb0afced686d1dec2492d42f1cb0a832a7c30d41aaa02937892a7baf9d33c10cf5dae5902d3a3ad94475ded4c2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0997507db3aa180cb4a631de0df84517c7ce2de7d44ca98c642461d52c7da378939bed225d5b00baa64162eae747a9668b7156d1ca9e767ee3bc4a2e09ce345d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x24748195be2038b728d7d7d7fb2ebadb7a12a3e44c4e8db3a7c308ebae043d0c8cae5af298244455f2871702044db34c1a835debd31e8a18d5ab3453187d2727	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x676e78b48169212f75df28df253cb4e7c659f1c977dde8e35fda0e0ff757f6c819c06b4b6bb68546ae42674fc055340c3a7f90c87315a8b2f58ddec889379b7d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12ac21efb6ce4f7ed183dc2a34ba6d8b689a30dfff51635187b9063e098780b9378523805f6eb26f026fb7ed9aa9e6e288cffee5157e6d4e385583719c78c69c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b3b43e51dd77dff3c24f725d0c42ac3a1cf9f1cccd35ca876f68fcc68b0a1bc5958d011ea841c2d982a639091156ed18d2fb18e2a9ef620cb19f249d0b09d23	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3bff0a02a2dfc678a18d617562df8b05cd6daffb2e926f9e37f497113e553fa43e02535dace4d5af6f86d2524607aede0170a1cc194f0d47cb7246ee33ca7f5	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc72588ba9a53a77796db355f25545445f645a68b237a89ed754e5cfe397d8aae6b6789944c40a82f81b71644814d77bad9568a9d7a3997a5d9af5e8b0343bb0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1a7eb24d69b15414f97808d6f978db97833e3f95b83230063f6ac2728e6dcc0b3ef025df5bad7d4b2e53b03908fa9fbcc8d6ab9698adec2f4f9e2dc33c01682	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e5726b3bcff3c69b43235fe6eacb8907faacc8456e4d66b0994b7a6af6585827e9fb403a6d8bf85abc447d1d842e9f235c9e3bf251654ff398be956e39f86ab	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x65958b6423a1855e2ad06aecb63b84042cd95a0d249540cca0c713fc28cca913ab179acac0df82fe2feea43f0817d21e297b72f78d61c794ed51f5cf91ede0ec	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x237dd386aa056c5f43dcba25242179540bdcbcf813d58235b01166ddaa10bfcd04bc611bb8ca3141e40e72b74a5931139f0bfad38b86b09bac1dbe49b1a68bf0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa5c97b8fe5d4804bd13cda6dd49c918c3696fbfab9126e0870cbc77609999e567e2b966fe68cc35cd99e0e5271ea4215673c76c44382ad21db8ad2f1abb178a4	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x96aa5059d0106f77d909e19b692c9bba6fc7813e86b984f2422baf1dce04c4adcc6b0e33636be12ef009453d7cfd6dd5a0c50332b8a6e340a0bf3fe1a8bd86d4	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8715828b32d8fbfad514b2796a05124cf9a9733f7ea299168acf784900105d0ef30b1575756b6274974028915e078e68de2384bcc2899326f48eda8b6c4c88a1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b682c2e5f26bbedcbec6e1858316359c0d534a6d4807bf71d944f3e0bf562d847abd14c9965172bd08f8f77412dcb70bbfbc71648e9478c4fda1091f07d3527	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d683e62e14736c17122017c503e6e69253117c208f88f617cd27cb05428e1d354826f24f67ac75253a74c42d4c66c4832f8460a972ff54eb761f9f9b7120203	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc74c493f033f4c96d2e774ce493c13b8ff31c91ec5bfb194a1b92d96e4978c993532ba1e8dc955e9d294f8726d34e9e4f6db4121d51eacf5da22b614998ba10a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x70028cc139be8bbe6d5c11275c79bb58068f663fce290c1a80a656d1f15674044c36b626ee4cb8f7f454c2934abffbe5301942cb434858c35c0af47d515f58d0	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6b610e204a21b543de55a59ac1fc2aaa6916946f29dc1309d2ef8a6342acf906feee9099316b4f0f56697eed5ecb6127df1cee82a918481a12fcf2ff5862dd2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3145b1e169d1cc24d7cd12de4c25cd9b8d9603030dc60dfd70b6efa8f8a6c80650b3853078cacb4b43edb58ebf5255d285d7c7eb526f9cbac35988c23c2f598f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2cfed6a356fb4fb300f3e2df91aada82ab5ce10b39707b254dea18829e0d490aa844f478d6e14d30823c528d05abab8b47242975dec3a047a9eb18442ffdf868	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x63daae266655b452a92fcdb438620076be6d8868aeee7d6da356e4abec8984cf30c843d76c8ae44bbbf5b093df0d37f1a4902926de1cbcd5642e879803477a47	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd1c2e528593f923934c2f9b81f59795b7ed6df6a6fdb7b90c06fb333bf701f464b0f150c07447d897678bb21cc03e9b5bb660dd608eb70c2d3af96aacd4f9380	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9db33a584ecd20edf36b8aef2e8b3b99c72d0e48a447d4d48f5f4a03206c00c9356a52fe60c622a78829fae4cf885f82ec47a109d7fd66c39d2df9a0176dfbf	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf8f9c77548373eecef53ff25e2434ff5fc4db91f1e81ced7191f0c7613fb8fb17fe05951b7de590d5810beb67fded3a236ef7e0be2ff7c32c5692e748174441	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x234a52dd414dd2321a0bc40183f12538597d0535805fa3a3c35dda0267fcb39f352f4fe83de3fd540a3dabd9a284f8c3404c927824868d5844838e3d25be8ccc	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfc77936e1bcc364e50c5dcf22a4b073024b5e08a31ef1159be322f0fdb33edc6a376615a07e2b2542be639f839590f2ba48771ea229ae7604595fefbcb4c5508	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f7c71ad3097fd6b85d9ad9c88d1ee6435f6cb37ee505601f8d9b2afaa00e06fb071d5f09b7cf963b705de258e1fe6b54c68d563e56d5b001737fd1f7c407bc1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1054335514706e1da1c15c88079716289bad64b2a41e44e10da67651f832b109ebf12471da86b67fff4b8df67aa5e05e5ce7bcf46d1e60b06a83efbf20a0224f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x749e27b5b0a25e2bc6489a99cb131883aa2c2825719710e7b16a59afb329478cc28873f6f9ef0d26bae0fbf36759acc88d9c6587f0a15479e96840d97715666c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1567655110000000	1568259910000000	1630727110000000	1662263110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3def52bdd4330fd488ad942e45860eedcb231ee237a7db539031963b82d6815f969b57bb7c5c3a80db1ce7577f0e353f6744029a14154909d0ed8ebd0e8061b8	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568259610000000	1568864410000000	1631331610000000	1662867610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x76e945d93c200c2f9e69d25a16ad1d18729786d8760f88ac4ad018c2f70eec0c20d770196cd0265bcb1a15f14633cafdd5bda99f7e3e52f92674ffea9b7b84aa	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1568864110000000	1569468910000000	1631936110000000	1663472110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x406ac90e139ef84e3b5e396bdc52265282e11a90ca6e84cc57e1534c97593a016eb1d0449d81e342ca075f3b3bbb090f0b3bb0cb6a2e1a602e4e896a75c8925b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1569468610000000	1570073410000000	1632540610000000	1664076610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x48cfccd22c6598b36c2087f33b22620a353e3d2593ebc04598781c270d8c0d309820f56f72db98199eb20f15936fed9747d747112f69d4b797afe328f38fb2eb	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570073110000000	1570677910000000	1633145110000000	1664681110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa64f2f2a294b6424ae286f579f710a780f2307c99061dc16ee7dea271c90862fecf664d370e985881055eba2a85debd5720573f153ff8a48e5aa0b3790babe39	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1570677610000000	1571282410000000	1633749610000000	1665285610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6f8f1ff9eff31ecf36d40bfa5ec0a0dcc91597bb0c0b490cacec3344107596afbde42053d90c0a7b65ab8763629b566d416864ba9a62216eb4d086a9de379363	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571282110000000	1571886910000000	1634354110000000	1665890110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa869a676cfc2550f66160192ad1afaaeff3830bfe9bcb8406a9bf26b9a9c219e5b73975cb6f4923dbe8e2844c162e19f5d693fe3181040744ad42ac7ecfbf6ee	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1571886610000000	1572491410000000	1634958610000000	1666494610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x147fe058e031b244a4e61e77d9813a2b5edbe178f7d98bdfbd50602c6726a398a20560f34e9ec6a3523bd885249ea420e23eb668cac4bb7ac35644476153c7b4	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1572491110000000	1573095910000000	1635563110000000	1667099110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4584254421e43027dc213c3d4e2d6290b007069f7561e5f4325c588e61dac08282a8bc1d4f7af4e52496332d5f3b1c0fc0aab6f1038c578e5b8d9d3eb1b12cd7	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573095610000000	1573700410000000	1636167610000000	1667703610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6479ba8051b2ff6e5267f0dba733572a5705fd712cec4135f1189784a5cd341ecfd1dbf8d32125f8bff1fb5d7cdb0e7df777b7aea70ab90edade3a551c2f9df2	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1573700110000000	1574304910000000	1636772110000000	1668308110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd655a6e2e608ab405a7b057ad0c624b7e0c9eef9a814092cefd814bc299c88d78752fc7df89a483f7482a71d5b578ef7bde845747fd73133734f31368dde151b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574304610000000	1574909410000000	1637376610000000	1668912610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6775b521440a48ef57e4eb6be96022f664f7e8e980a8d491730c939a58602b00917f76a5b06bf608017764316e014ebb54541b26706d6565deb1cb4daa224b17	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1574909110000000	1575513910000000	1637981110000000	1669517110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x439b9e9aab19c564479596b8d628bde9cdc8abd996d2439963a0c35ea047b909a51a0c93682afb4a3958352519cfc5d84bfde7c95e98688384f8282f647157fe	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1575513610000000	1576118410000000	1638585610000000	1670121610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xab09afe1e7d61bb17a94c884545f4514ce073be6f20d4a6568039c5f243074e6825c7e4c785ab496d9b1a763e418c138a3d863548e960449597a911bc46a2f46	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576118110000000	1576722910000000	1639190110000000	1670726110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x839b02184b4cbfd26e46a02cd9c78df7dfa62777a9b39224dfc2a128f7c93a7cbdf16a7a0b8d17fdb08ee577a6b1c5836e990d465cd0e50b824fa1801554b28c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1576722610000000	1577327410000000	1639794610000000	1671330610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc736792b7225c908cfb8631aadd43ed5eecd1743c727beadf0c9b6b2a8204a0ca74713237066478c63bb9c20e45d2b566c987dfac0ccf556a99191dfc88d251d	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577327110000000	1577931910000000	1640399110000000	1671935110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xddf7b6fb699cf1e6c6578c21c4f392a9fab8d9472c6c5f1f8fe0cf784775cf888081933a3041bf8dbd411267d8559facb9dbfba93b16b9f45235fbf3774c0762	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1577931610000000	1578536410000000	1641003610000000	1672539610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6eccae0e842f7212078c0379afa462a30b45ee63886fca6ca26197ec2cadf4f2f1d4fe7e4f72980320284d16ec8a31a071794d188704604e22af85c32f48f77f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1578536110000000	1579140910000000	1641608110000000	1673144110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb70e7e679f5925ef1634152b0d0dd3d23a473f7fc2dd9f954fab971b9d64375bcddf0d78265365e44487912297aab5ca472518f6d2fdb1e646f73bc0aa9bcd6f	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579140610000000	1579745410000000	1642212610000000	1673748610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x776795fcfb11cc50ed2243c66834d2cbce634402872dfdd577afde03a96c00c37500f65b47b35008eb21d936e8e2abafa3182782a89a8a0f6449bf02e5d38977	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1579745110000000	1580349910000000	1642817110000000	1674353110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdd3f5be2e0da081e57a8633b89c2db1008683458569943d33b2d1fd6cfcd046ae81334300a02ebd642c81d519924d779240b5b10b845c0ef510e7f528bd81fb1	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580349610000000	1580954410000000	1643421610000000	1674957610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3d3b43697a3581cc91be773e41b6447201d184dd5772a2e6250e51a6517fae4bfd431100558ca9ee2ea1c88266d1736ac4c7fb464b743b47886c24f5700f5919	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1580954110000000	1581558910000000	1644026110000000	1675562110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc48ef58a38b2b671352864f1ef0d86664739906c52a11189a9b0f53fcb587c3ec770d322d8794ff41678debabbfcaaa93292895531dd456a4e0e6666ea501790	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1581558610000000	1582163410000000	1644630610000000	1676166610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x17bba99c87865cbed1756994be3fd77587c1be82c8f835985dce87f16685e32c0578e12dff2c057e84fff30a3305e62c6421a9b343595dc186e9f25d4a799848	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582163110000000	1582767910000000	1645235110000000	1676771110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x85f0068ec7de9fb0d995a818958e12cfe6bb2a086be56dc31fb99409236724731a9eb609e6c809d33cc539d147bb1601bfa369a63da4889b56fec8c13d80351b	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1582767610000000	1583372410000000	1645839610000000	1677375610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc7adf1a4e99afc6b2edaeec53fc60612452666b4a890de7a935a551f797a5083801a7eb2b25d50a0fb4127536e0e4d455ed18764e08f128fc1d686eb2a667277	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583372110000000	1583976910000000	1646444110000000	1677980110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x99d8545583e83f69205eff8bb749525808693107b34b03d570e88040407fbfef1ae83bcf640ce370107e302d767fe4510f7e71d1ef2b44087883067aa391c898	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1583976610000000	1584581410000000	1647048610000000	1678584610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc857b6578a4f9fa2817507c28bd4326d3cc5616723aa07f78aff5e75673087f451cb31fc100e4c291ffec00a7acc078a5b795b0fffbd5456912080205a325d0c	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1584581110000000	1585185910000000	1647653110000000	1679189110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8d2b7163b08e5026031cad3b5ce5521dfd58e5b6352535088e911db461dda5f79f0b762c0cf5c3a8b89b9f9105a16d7d80ae9a9e5f46ae5d254ddc240cd14258	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585185610000000	1585790410000000	1648257610000000	1679793610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x78aea0ff997f76f053c9fac2376523fc9abd6427e7216d231255281d1811d2bf81b45e0116f55dade76d52c410b45483e8f5fc3f5ca998cb65d6b7ec24889080	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1585790110000000	1586394910000000	1648862110000000	1680398110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x29b88a145b5778afb76d508b136556df23ae48c9e80e46f079b5b373a4819fa89428e7b7aa34860d5022a7077a3a34871f8cdea32e13245ce8ba3f64bc6fd751	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586394610000000	1586999410000000	1649466610000000	1681002610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9be21c9377c5fe8ae2431d43be9e36866065f60097f21195afb2802605473eb49155e47b162af26a0c9ec5ebcd383d912c8c8b1296d8986b6a9fb29f954ff953	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	1586999110000000	1587603910000000	1650071110000000	1681607110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_ledger; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_ledger (master_pub, purpose, "timestamp", balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_predicted_result (master_pub, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: grothoff
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
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$150000$ZzG5hpQdu3DI$7GP1UFtwR/EuPhsiYOkuY+X7NMe+HFlUEwtl4P38+yY=	\N	f	Bank				f	t	2019-09-05 05:45:32.730843+02
2	pbkdf2_sha256$150000$1oFl9EpvFVTs$Q3SQya7jt/JcuITs0qGU/DRzp+AiUKuUYVMkHDHqKaA=	\N	f	Exchange				f	t	2019-09-05 05:45:33.014375+02
3	pbkdf2_sha256$150000$TMmnVvThAwhO$6lMsjr/TzgDcd85Z2ODOmQ3/x6pYjG6FYzSdPiFmBsk=	\N	f	Tor				f	t	2019-09-05 05:45:33.203206+02
4	pbkdf2_sha256$150000$pBC89aHH8iou$ODgj/A0rg2QeWdsv2o43BWAi0FZyPZoTekuv1iKaw4w=	\N	f	GNUnet				f	t	2019-09-05 05:45:33.58854+02
5	pbkdf2_sha256$150000$XyPbTg0pf4yr$Wgfhaglhg3BOZLn21LR4gNMK6UzhlHaOtySRfClCpCk=	\N	f	Taler				f	t	2019-09-05 05:45:34.170293+02
6	pbkdf2_sha256$150000$iF2E4Q1CnQDW$uV+T5WRyTndGxUEN+V9ps6CSx71fCl7JKz+F4BH3zxE=	\N	f	FSF				f	t	2019-09-05 05:45:34.369931+02
7	pbkdf2_sha256$150000$QEbELX1AYbEc$Y/MLwXmWXw/k9SpvhWx0R0VjRS9dk8ATvZQ02X1/N6A=	\N	f	Tutorial				f	t	2019-09-05 05:45:34.558847+02
8	pbkdf2_sha256$150000$tvJ0TQWSGsBC$ddXVhdV/EmC0nD4IDqyHd8D35aroA2fKfQkUzoSmgk4=	\N	f	Survey				f	t	2019-09-05 05:45:34.747795+02
9	pbkdf2_sha256$150000$d5SsdV5I3CxY$3JhfmUMXuh3OiUoiAmYOvDnK1lvL/C1XxWBKrkDgUJE=	\N	f	testuser-P4H0EaN5				f	t	2019-09-05 05:45:41.067466+02
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: channels; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.channels (id, pub_key, max_state_message_id, state_hash_message_id) FROM stdin;
1	\\xc95a97b1446c73f157f70e9fdf9495ad8b05ee95efae4268b66a2b5a1a7174ac	\N	\N
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xc29fd4c0cead9296602907dc4c543655ec0b9719de115e1e1157d610d9309fec9f9dfcfce3e41908dba924b174b8a696ec07da544e7bfc71a323b3ec41082f23	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304336373744343541384531324541444634354341393743323941353445363041433330373236373432304630383136343542423031393839374334324442443638453941343543333344364431353432373437424535433538423737304137383939303733333732334237354333383845434538323739324441453941304343334234453343393130343341453831343045334431444430463332394645373041333745373939303434433746323445433634413846353233304638334343393039434537304434364537323338314546454545354234424637454131443838374534464133353331303132313533363843353641423742304142373433443923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xc6ed3cdd81426ab69d52dc2cd84cecb5a85896d9240ae6c4a48cb254e4a74c89ef38012ea737d6d7dfc0134a7d9f6a446aac4f415e82003504ca03d2d621d600	1567655110000000	1568259910000000	1630727110000000	1662263110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfa2bb2783038fe463409be527748574be6906b9864c9ccc8410ee4ce19c00f724774e438bea5608d42cc01fae8065c7f0d6daf7f608c2ff6090da56a08c2c0c8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237363633383345463332363736424441413035434344453345463442384339374239363532413536434339343839323536383838454337353230463237393942383935383239443943433831314341333231383437454330353434423330393644424637384244443037464438373330333333423031363044314433453837363036344341323134454543374139463833423938394639303933463034314332453441433634464242413136344434383646413933373241374238323342333438344330373231313142454338463643373435413045373133354544363543424346393830364246363245444539364339413133393746423442363443443323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xebd8c85b83ce19b7cefe18900995c6814dcc71bf4a3b1dc8411b6dae90467898707ed16f208248d9a1058ffd33489d198de1787a77753c1caea95091ddf9cc07	1568864110000000	1569468910000000	1631936110000000	1663472110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x93e7c85b11bd9fc613cd10baf5ac0819bef822a176e8a4870874a5800f29c879941e1f8b1b1f593a9d0751a70f5190a59a46979fa425f6dbe4ff2b46ca344903	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136303343333041443035303532464142323130423039424346323036443846324131354135333139314646373343313441393138434438383033383833454144444643413133303031463245353532333943344646453242374246394442313634423036324637343633423344303830363546373135304146323531374342383841363834314538413032374644444230343132464134463737343337364430314437443931423841453739464541453545324339464630344446423038443541444142383241324645393035433130353639303437353335414444463935303331463843414546303944363134463446303533353439444438324334353123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xaf26901deefd6c9c9f6d84320bbc577f8dcd5196722594793f2f66a7d01fda4016132e10b0568051fd8d4bba246f37397014769dc9b1e3fc9538e9c751d33806	1568259610000000	1568864410000000	1631331610000000	1662867610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71dde100495716525b802127af0a5343afaeda47eb0f2d6e286a5afb6129e60023ef24db6d42c6d0e6bed6e0ab278b5b1b78f23e13e47f58c801ae5af22d3739	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435384430464430304438323337373435393737454146354139373139383034353836343134343845333830373731463135354343333546354642344531453232413745464545334332413736363642453444413534314336344535313941363334323042454135393035353332423337454131463137443431314443323934364444463042393038353838344436344430364433364439463539414133303337323546443239323639454634363931384134373544464343353439433844374243363039363645373846343045334241373146354131463137463931423636453630313638334144353937443230444141324343324638414335364236463923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x08f906b15b25a1251cbaed2a1a87e8d1608b8516a39294962ee1cea49040770bfa980ac46787d9417574ee89abd8c1359bbdcdfaeedbdfc4c7b6b3515dc8ee0d	1570073110000000	1570677910000000	1633145110000000	1664681110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0124486b0f2520388154107cf5ee7fe8e98e65b7d27b77c7637406c0cf4902805b55ab90a54f2f4a493310c692679d5e57f33891259f2bf4d0f59e817df268a9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239394533454131444542413834414534363930424445313638364635433831453838454436424446463737333735353744463533454332443839413639373743454542364532384135443938384632454546304130443746324344373843464633383531354241434139463935334137323233453242394541433043413545333637433431444132433744434542324342384131373439393230433441314244313133383941383831453241324546464343464532414444443338303441444345304135353143353642463333343345334644394441444432323543324538413946424442354239374645423938323241363044433230353441353931343523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xdb31150e6ba8b95a1c355621f1594342c7cdbcb016af2d6a63f99ed9fda393af134fdf871b8ecf93bac3102ec47d3a75f3861d5bab2a7b63a5b3646cccf9d807	1569468610000000	1570073410000000	1632540610000000	1664076610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe6ce6a175766f104b1f9d45efe95d9d0a8f1d6d2919c5d95b9feb4245722e0ece99c6c72cce56eda3bd650b316524326b792863995860476768fe4be63f51aa2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435394631303733334531383846424534343338413845423945343031434145443042314336303039444144373935463634414443384444413941433634423546463739373442333534433635384332383537443038393039324642393641414639453437333339334631304342304142353931334630413631443939434430304442333346314331453531323234333732343842393246394441353243353935333442464335334631453437304335413841423739453330443232414241344641353137343843313732414336444444443336313136373332313930423041424546413346453938353241324146303633353437323142443236363736393723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x182155fbdbbd4c7ac3b830510763fe2db0dffe3723201ec576d96c57fa5cc3320e2aefcf07bae0b9154a8e52be0206a3acf4e9e86d547b97b656d3ab1e2e8d09	1567655110000000	1568259910000000	1630727110000000	1662263110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19902484949e554d52635da8c9ee9ce9024ab05a153caa01dccf8908403c6cfeb7df5a373f4d2d2c5fa791ea2e709636f02043a1e5b2630e2985b153995b50bc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139314234383641323635374243303430453041444431423742373437373039324132394643374543433436313838363736423841453144454430334235363336453734453830394537313633354445373643433333413344363832453832453341463943383444324233434241393736393239423742363633323142423636353338363132323238384146343843393130353845443441313243313043433835454241454438333134373331333542324141333545383038374236353839354236433542443739334238424635453338413441464143394341413433373434323634463944324635344632374641363241424238433845424435314332393723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xd5f3f120d10b276abea41521af78a399d83056200aa5533c6d18365c7350ad6f0560c4fe8399c1a39ed7f329a9c1ac64d8314d2cfff04de5809a4028a581a50b	1568864110000000	1569468910000000	1631936110000000	1663472110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe685f0e212ba2100d60568637c798f3b0a3eba6710e316ba3b7934d75658069d17492e0c0336776cbcffac7df054e2bfebc50f90e0ee006784a4b26bf8a32cdb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330373131464537354430414138363033313534304143443936414632363041433934443543443245363433433932413145303238304541444431383434334143424536394142463737444332343532333332333341363545373135353743423742374232463231433738383338303532423342443438323932383335353335433645303335384631423941443133413631323431304243383032384542454132363633363545343034314435464133453330443334343436443737414143464239444238343139353937373534464635464139333237363441374330344446463844344135324134413041453638304241303935393539324541413031444623290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xfa8d11e08b518b79556a367dc9b6a4ee52c2ad03d26cc27681a26ce43b6645b0aafd7fc5b96ec859ecf1f749910924f26ac79e83985d88391fe8af792c78f40c	1568259610000000	1568864410000000	1631331610000000	1662867610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x17c2acb5594ab4b717fd69f917af0fd4c25058c7ad91a0f746b5473a7420b6ac6d4731ef46366a94b2f536c3eae9761a320b31207bb09f770753dc0de602e6f4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439393336353632453832464335453134433532304345373533303931424632384335364130443743333532313739423444344436344639313643354534343236433931464438314632303739393133373239333230414536324330303544443632383030354536453930423135413941364645374644394545393741354245423145413431314141303646414437394141323641304636433532363030304542383535383842394530463938353541334645434434464334343137393838394441334639463137303033464346303545303331363241394436433432323435374345303634344630463131373339313335303230424138334436383834353723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xee1a880f7e31118d4dd0285e9aa824ef14c17a4f84fb79943b88f02e350b406bdb88a850c641e143390a796ed2951de05f53bc79748f4b69328fffc292e1060a	1570073110000000	1570677910000000	1633145110000000	1664681110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bfb0c3813e79040e4791fb87d27618095e804d20a538945c5cdd213d744b75c341fced01accd9313da4cc15830cbd11d4d02882dc67cac98402f62a4bd2fb92	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233333732364534303443344232364446304143443231453642454135344331434133313735454542424546413834363335323346364139324342354135333931334130353638374443373633324642433832463239374630304434443446313733433741344344304432324445393636443244413232383442454242323938383335363437373041384446413232393644463033353336373338454230343338463733443943463139333343343533303032383342363632433932423942354243363938313635433246454139354535314131464233424646463042354532303838313436323537313332414633394543303941324239343344443543423923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x2952190dfdbc1445fc1100add506c8b2cf48dd790e83f5a631e151b96f0860d10f1396fe4a3c2bfebe759bf7ec4fc22ba30a0e9e8af6d0ff0a6504db904fbf0f	1569468610000000	1570073410000000	1632540610000000	1664076610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22369e9156baf793750fea67c175f50a046767c2da78498e0757e3fbd18971daec1e964e881c2ea98d009f08748dd23669b6373cdd76eb719b28126c9f341d3e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330363439324639443944463141324638393538303135333436343643353346424639364545453337423932453930433542324539324636343330303533424338343044343943434136394542353631413746423135463136334342324232373533313246374436424332313132334546323539414641353430424238363939424433343830343839384532413945363539353835454645384232353833303738463734424343454432363243463536434143344433323143383546313832354345323231343639384335314639353630333242423843354133303132334330463338364539313837454634303038313039303541453945394635433435363523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xecc4654ecb2be7c20af0732eba4f655ee515c5b8cd920ad0bb060cc99c71b88905878e594e31804eb5c54299944a1bbffae76c1cc5a0b86c0eb25712fe43bb0d	1567655110000000	1568259910000000	1630727110000000	1662263110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5de1d29a2ae4fff55ddd1b08174171c8dca1bfda13b6b0eb6730a41313d740a1c343a409863f35deaad1861fac1e17a833f3db021a2de71eec8b63d6dde5a83d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433353035303842413144394146443137424446423030443633443738383544343943454341303946304131304637323339303345393036363830444338433739393537464345313132353733454230313344413030373739373845344646384634383939454432443643394432453633323534433441343335354343303542453536383935424431454535464242304144304135393731463943313042303330394542333734304438443344464430394631343944384530383231304341303737464636354232453634374543353039374344313441414346463832393945314442413334443645444430443744303437324434464443433838343932433123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x8c6d94ce65a2df2e67b46616bcc8278eb2cbb87d539b3e2bdee4def8266187ac91022e21d955a5d8a267e0dfcfb5adf4876a0b89b063ab125ab1a68f769f770f	1568864110000000	1569468910000000	1631936110000000	1663472110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a26c34ae18b2ebf5b1ea29a0b1e1c0fb21ae684d0ce48ad78750d83026a6fb0dc03bc5cb5b563c0680a6fdbd45646112788d854040fcb6c3ce2f39fcbc45bfc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941433744463230453041334436384236443339343733463546313534333339393731433135333032334339323643304539433035453634363132303336463138333234423544393045383633373244423439463741453335414146363246434431373135333345333241454137433331423938394434463141453938373135354346443630334433364142334234323541453134373444414139434244424434393443363534353646433530394146303237324531443331453834443036383946373445333542343045334636324536383332343034304539413443433743444533434531423043323032373141364133463145413239383330373838333923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x7187e6243d576061d9b00dd88abcee261f05cd7a47151c55927ce04b9e741304688724c4d013074441783975ee3256a6f6f22082f884c5df53f7a58e7737cd0c	1568259610000000	1568864410000000	1631331610000000	1662867610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x47a7218bea367b3c5d95adbd652e52578ef2cd4debcc1eabadcfa207ffcaee10ebc28ee8b13f12cdcfb72fdc983a5f2f604cb8a26dd5d352a766091c9f71235d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946413346324434384239303142393142374438433337424145324233443838344139364335463045394230344632363933373034434245383842433334373738323633454433463334314344384535394543344644373132453431384235463442393831454433414231463639433642463536303936313641373332423042373436324539313838453344383845413046353343343836333534443444433536413136303838374345354642353130394543364144414143353542373430394343414632364633334541324345354233323038414141354337363134363845443334333137413131304334424434323341464132413137433138463245363523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x6f410933235532d62faf818ebdaff30ba39d1e04738b2f8e9225dba28aff7207f184129c62030461dc95be8f174ec34fff4943d253ba2a364af80389eab15f0b	1570073110000000	1570677910000000	1633145110000000	1664681110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6c4bb55d4d2338e7e815ce617075a84b2fb30b4c554d60abe234b0238f10ef17fdebd4fb2ac1a06335b7350a6c312c41f9ca30d2842298962f185fac11d0a90	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304236454642423543374538453343414439383931463538463944384531444437314641434632343633434144393938373843374443333541464232304637413531383944463144303541413339423535373345303241354238343534424333334446414239393934374545393941374531373143374444454645354345383145393831393137464138444436373833314532433336384646344234374444354444334336304436333137463345434530313830454634324645423536343031463639314338303838353644373336303441414446383631354635393744343746383033453136413639373539343839454237433643304137414139454346303523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xbc5f8f94181a36e7be093a342d620285024671a5299405e43e1c0a5fa254e5a283ac2c4d0e26be708574c2d04711b02ae77e18608ba0dd265cc952f0ab77ad07	1569468610000000	1570073410000000	1632540610000000	1664076610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa43885859b2c4de3344697f55e74b2bc694696021441deaa69c288784e652edb9250c935453f415c9e5e01c0781cb1de97951140e97c8d694ec7b65b66bfea09	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139304435384535313435463232303344353237344541384134364432314235393738463741373841413236304130313338324145444137354335393041444144423844373344363845354345353934423334423737324131314144303135314131374139383946384431464438313543444333373336333333463933394344344439364642324646313141414436334131354439453246344636313735303431373633433732463330464232303346443244354144383839393943414234334132333544354437334439333730333041413034313436374235363543373336304144313437313038453135443830314246313536313142353734333544453723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x22c7f25a01ce0b6f492f3ee0c9f40ab281e544cf11f813064a50062fbcb87ab28084d5443edd4ef657b1a1259bc75ef159c5f289a21f49378a465b016615240b	1567655110000000	1568259910000000	1630727110000000	1662263110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x96c3d079d473aa9eb2b9d2c3f291132447ebaa76b4d5872d0964b471042e30e709e5ea0219a14f786b016253998c0b7c7e30006599d88c630153d9e2ef851398	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304535413738433241303544314236313635354433423730334431433445454330424644413134424137383138463237314342364431453637414535413946433031304535313342373730323432394144393238454246343944303032323745334442414135433139343035303637413445393237334531323033443731463244394345443641393835374543343830434342424633344639354230464533333338333037384437324337334234453442333536334631453242343136423546413636464633303939433933333146353939423041463836443435443138343745313737323936464433393631373536324241433745324332453934414445464223290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xbc9443b63b134789ea293b74b08281aa15a54e658cb046a161b65a16e4d8526915c72c1621669d1514509cb5d4da48e3885a0e208591a1b5231a7ece5d8faa0f	1568864110000000	1569468910000000	1631936110000000	1663472110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8695e229176c69fbfc51e4beb49f2fe2cd0d31733451d6265e536845ee3ceeaa348328141e3807331c7967f3851f600edf05fc85a84bc1792236e9febf1009ee	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304639313132463737453644383839444135333536323736394438334443463930303232313444434337353739303846343031304137454444433443463746383834444442313731354145363833353336313233374539363732324139353232344646383632364545444444303537334646454246453032394338423330363234344543363932413232414136424546464332413039313645434332304545343534414238423932453445333445454241463039393138443546343837433832323844393038364544463435334243393930343933364437433032373745443334304531344538443944394134334144444335423738424438343233364332303323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x448396fdb5248e7d69a5114a7b60a4411419f89aebb1be15d6cc5019b87e858990dd66427f39016392b64da7a2681249e819ea8a5ed05a047c7bcf5707315a00	1568259610000000	1568864410000000	1631331610000000	1662867610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f259bfa81d18f8c3023f206f2cc82bda4373761c2187c3e8685cc3e053dbef14c8bfb5b3513157621bd66303424877f306956f1c0d106731fd0358aaecd046d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431433930343341313838363637304239464336413735353139464336393435354632453243453943373630374334363941444435304333394539413630433544304238384134344646374344364446423331443442344546383144323741434634423445423444334145453431434235364344463641394144443230383745383339413333463534333230433630413231363146383333423032323942373441384631344339363744344446454632393631373343313533343634364639333443353236304534373044324532374145304643353536453745333034383339393838453735463933463232364541464246323542363738363036443332364223290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x35d68e00b0039c7b9cb096832c378383b28d28bf11d0ece37198b3c414ec4fc63292b3f2be1f07970ebf7107ce0ca92b2622062b9319bb74c9b81c4aa04c2b09	1570073110000000	1570677910000000	1633145110000000	1664681110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3c2ed18ac464825908ed92bf5383ef11cf5b27db0243ac7fed7a3c814b5dbd642e3fd810dcf3b9d0bee17583c33804309c51245bb2e4162cbc83781279922be	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143363541323645374533394636394345343634433336303935434230343542393731433237304132333830303030463343344444453645444131393342353931433533453532414142453934463842373345394339414642393941393742323134363245423845303042303236363741453344364233314534344139443538344130313939373430393744394245433332304231353042454542383446453630453730433334414232354637373341463136323136383733313041453441413331433133343146303935414434393338424333393336323831443730313744423830323545383339324437343244364144313939313334423934423231363923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x368aa17d6e46e8b7ea0e1d64fa6c47fed7cf3dee4ee74dca8057db9000180462bbdd0b94c76163d3e22230128522972814a253a02c04c454699b3a72dd84df05	1569468610000000	1570073410000000	1632540610000000	1664076610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad63639cc3144f7f188cc8f6c612e482b2468cd490fa91e36d7acc6ae4de655f16ef34c4d42ee98dfbf3ed8ae8781c2786641bd851a89ef3ecd0953d7266ef8d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304142443837363143414643454336414635453842303139413439304137324436344635333337344643423939333436374139394137304245343537434344303031463746314233394339324642373046424145433143453541443342423234303046394341344639363037433031363631464131413141433538353332384343423445433143323730314444303341393245433545304341333246333135353842393036314342373746373238343344453145334335303130413732434341304532424631464533313135314635394335423541414235394645363631463231383436444430443832384438414431443643323435393431344542444230353123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xbe343fc52267fcdc0cb71615f8530176c166b82870adebb4bfa90822a068498efd249a17cf0a56ed2155385074229856c8f92ec08d10158dc674b622eb4a1e03	1567655110000000	1568259910000000	1630727110000000	1662263110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6a0b8e67af9212048f2b06de091566cdd458445eab003cbd3c6a3f41c6636e4840c0e6a1a9e44de53e2f7142bfa9aa63ac76f3b51cb2d0b1f60fe7931c4e58b8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230344538443432424245374230434137433435303833333742304337443135443333313045464645443241453936323843414343393434313535353732363636433041464542464442413846453745443443444146363243324141413639464345333344374643363142303535354333423036303845424334354333444532363531464545443635313331364135443034333142393943383334423441434441463139354630304245414536454339383534343234394332353430373032394134423143344242413936373031394146333935444538323538393046334641313145353043394137323338414542383142333142413846443337414133353123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x7fdfea07f308242c5ce7d2af6c8b3f5e93995021071a660346d680b561b5fccd8e570820e6101d85fb536a4483a5d090cc36e507ce869b322d5372992f7e8d04	1568864110000000	1569468910000000	1631936110000000	1663472110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x55bd0907fb88a86c364aa63a9f9a76dd3c04fdb2ab3f88df4395462de06d051ff03616f9e872817a31b6350d71644e2743d5ae281e7961a3bea297078eb50d9d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246313239424535303542443845434236353346344234344646444445383845463944464631443338383332453044313841343144334246304532343839393931394345324544384637354338443641463544453430324644363537313035323746423231343134383530433636333844343143413030333246413836393444323543324443444331313444433743313231334441313135413730434241444532393739433844304442374142343642383145304631453734453146453830433633433531343042314233303045393832384432393338333442384345383843453633433934453646413330343833434537363731423338334435453437434423290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x8831e731e75e8de17d556fc771ab4ba2a23c3366bae461e7ca56147dbfae0f032acab13437e1206095dd9ef11fc03f9f7992ca59dfcad48658f48d3ac203fa0d	1568259610000000	1568864410000000	1631331610000000	1662867610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa080dd5f1f05e2621825cac7b425072294cd761734b8e47339db881053d279295d55d5567cca906cc9a73b47bb77913093485b95279e5f428b7a51dfbd68225b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342394635324531373642413035453341304437384433374538313834323836353632443839434631424236373344364433333542393133363830453041303439433633454343383941383230314345344635374535453046463941454436314139343636423038313541443933323737323034343634434235333030413235414330423542454631463541324336333231303044443735344334383538373733343645384334393735334133463939364234314336383341303639384633433034373834444430433845423539314445334443394337303844434642374337414445303736413042434242453531463143424332423833393730323339333323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xff38c305c7e8ff3f05e37b818f58ee18d0e37a95b27f70ad01ec79060c28518be1fc8561e8b567f5f870ac57b1225aff98786e1ccd122fa15a1251191dec1a08	1570073110000000	1570677910000000	1633145110000000	1664681110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2f952598552ae7684d42c3b6f080e507c71b8977e7d24bca77aad4e8640611ae171ce790aa567b6b348d9b9a35ec75e18f85582485acebd838536f6ec3b55496	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304142424331363534304132394139343031354337383739353139424435314130363431313541433930413238423342304130324533383934363841423631434441383235374138433237353030384335383139444241363531363443394235314137323536344233384236373939423834443831424434364333424645343334373637464436363434354337323936314631443730323045343338443235303046394643374533363336373730353744353232453332363736383230334439364530453438333834394345313235374643443034393633394336353632374531324641343732334634323442414646434635334530353434353135433344383923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xd54f56af051fe041c0cf052f2a84a79be5210402e548acd6d9de57cb9fc7d0d5b0a6319ac92cdd673ee19f60869ae802c426a04dd9110b0b3ff1988dc2b2a306	1569468610000000	1570073410000000	1632540610000000	1664076610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x815c0050f1d9cd5dca99f564b52ab0115bc7c44658cba49c70dabae2486598667efb56cdf816b8836f739aabb74855a34c92efb5be18e5f33df369d6677ce3e4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331303035313131304133393634344633464643454636393434354445444346384231363242354130333342464232303433444445464531424532453930303144393934304434344646433134313837363939333833463134384342423544334533453732353542434433443835434142444530324536423746443842323041303933353645364238304230333041413938413439413844334534323944413046394430433637393445333437363142433532463632343533353246393344364132374131314639393536374432313842383036324439423235373435393343464639413831423945343739323536354543323145383745363245423144313923290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x64c96fa57b4b39438ccb0ded0358b17ca6ce9bc202e51f372bfaeb6f1fde798f737abd89d5cb2f7949208971fde3191500fa925070f254a3f766fc0784802e07	1567655110000000	1568259910000000	1630727110000000	1662263110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x51c2d1629fc78cc5277adea3b73a579e6db923fcc430502a157ba23370c4c1ef1ffcee69bfe35ccfec0b46feb59760f0fa618cf22899f0dc2f4f86e27a4e6a4d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441453139463335324543443432373941394441304146464232353132434343323535324541453738314144453731343444413935413246354144314239323146364333353041414138313932333533424430373739314445463037303641383530344333303138314645434242453343453837434332394631364231363235353143443130424246384435383241454337364137413635313730354432363936433734383846373345463036334636334532373145344241374334344634333231384539373533443736314641423543303730383743443632383342383446383037373736433930413743454239433043443034454632463643364644344223290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x61e651e057c8aa8f503305a2599298a0e5b77ac2ac3e3618d0cfeda80fc0f06e3be0ed2cfcbbb1fb1398eba65c491911d13310603ed0899d2348b26e23343906	1568864110000000	1569468910000000	1631936110000000	1663472110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47d29f4456371021d65b00a91aab6629917d99fa3fa55a665980dff5cb321844841f7b1bf4efd763f1e66fe33768d104054aec03cb87a46dfc7343010d11dc8e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237303638354146413330303134393035384643444545433539433935463237414441333143303442414638414230343543424246393846334344423844363635424430324238443543333236344331423244383031383342453533423434374342454539343544423533464143333842323037454341424534363332383944323836374639323537344144413839314344413233313637434630433631384634424534333531304344424230434142423835323330464146363330353432323943463034343346323735453532394330443443443146353138334432363741314537423635424542333539393031363837323937463741313745443442393523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xce3ee206a9d4b9f1039724e36e9a0eebbb407a8ab0cbf6acadc8ccaffcce6d19e63cf7c872efc053ca6d76c3791196b35843dc51828643a6d60dcaa7ec725207	1568259610000000	1568864410000000	1631331610000000	1662867610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a937f59fddc40a3fc79f795310199af6bad7ac496de825e3aa9aec4f31bfb4b933db2cd8d90e945ea8dd2b9877e71b070859334918c9663ae4af772b66cd1b1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342383032423732393944303745453330454143383938323235304546463439323334333746373844383438303538373034423941343030443137304236464538444235453146353233433934304432354232324145304145314537334639323543303439343042464336313132444136353241453536303436413637333433413632374230363131414546353630343438303133333735304231433931313544444441303432464141353442323642434433323343444330303935364335303442323444423039383334343438354443334245374343333945434231354242333344363143364437373932374346364433444442434539343831413032453523290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x462f05a75c00b361c8ed5e33c909bef17a71f443e47c780df3d9581a98268e3185c6395975888c9dd7523fedfe18054f9ba2a838db5af0e04c91203602209d05	1570073110000000	1570677910000000	1633145110000000	1664681110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x80253b3ba7d0acb59c8e0f6151919a95198bb7271603d32336943908b8ddeef50bba19179f9e49ed797f8ff034a28cc18196ad1bbeadac5bba40e97cc47156d5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341443632373535314332414633463030333241413930344437313038424638363143384136433443394137384130334338424635314342363543344643383732393636454136463145333637433037364141343446304146433036363432343142413737424143343730364434343435383531463242323837433241313534433733363044353933394636323932363844313037373443434546393144443539353636373541383746304346414634333644324238354334363546333034443232413943304133323742303232443446453432443635423836394131454239373143464337454637324143323045453744374643303030453931374632423723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x554e4845946a600cd3832c69e974748c145f7098672e9162057ddb003792e17d919cdb73f47b569696578e842d1216e09565e3bee5ae81e3b57aa53ccf692200	1569468610000000	1570073410000000	1632540610000000	1664076610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334463336353639453037343536354634373146443441344631374230423943423033374131334332393736343534454545444543373735433731343443434243464635413533463934443244463244314531393644373845354131334632374143363135324442433037383831334346324235353033383043443035464431424345383946433637463245343436324641314333423735303032424234383444303137344638363032384336364534313231443845423943454136373933393639333842314339333742323933314445453031443138413738374235394238364330374346374530363844424334393836314644393343303032363345463323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xc50fe333a2afd1127482e2de3242e93e3cd8ed433f58ac9f2970a2570039b1fc0a6660e679e099a55d2d27aaa5ce60ab1730d2e185a01eefc1ac4dfc7399fc04	1567655110000000	1568259910000000	1630727110000000	1662263110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x76e945d93c200c2f9e69d25a16ad1d18729786d8760f88ac4ad018c2f70eec0c20d770196cd0265bcb1a15f14633cafdd5bda99f7e3e52f92674ffea9b7b84aa	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246354643443231444442414239324445344439394436463434433845384236314446394430363541413235394445364333314142323033463131353234444436374143374637423845414133373333373536383037334635324633353844343545383643434537464436304132373145333234453043343239383936453138354342374234364445454431303039463039314236364233353439373441454535443843464530383341333639443832374531393334303143433136364633433238463945313742343337463434323734434532344637433944383936304433383941363532303037303430353331424331453435464244383141413336414423290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x8e5d21a529b5425f3a7ac3f3bdd6e8a22f3f0e0238c673dfd23a31ef8b2ced9d40498f36b7b4de3dab6c8aab41656071d370ef7a9bd47d1aad803ea778b06403	1568864110000000	1569468910000000	1631936110000000	1663472110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3def52bdd4330fd488ad942e45860eedcb231ee237a7db539031963b82d6815f969b57bb7c5c3a80db1ce7577f0e353f6744029a14154909d0ed8ebd0e8061b8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331314231443342373231464639444546424533313541323936414442364137343141394443423741304644433430323833344646423730393635363838354434333230323631314631453545343536383243454330453841433936354238394542303032384430343039463044304631313535414644453842433430453535373045303545354141383139383131353732443732363537393431383641463035453530383742343737344131353232303243464433353845433945423942303430353137393332434438363246413746353237303945384336413146323938454538373339463534363944334641324637413238464234384232454245373323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x7889cb148dd528ce726b79bab38ce8dbc27c4fda2d18fdc91d01bb668d0135234948e7e13904551947658f038146586188aa5ff9686669dc208b809cd545f904	1568259610000000	1568864410000000	1631331610000000	1662867610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x48cfccd22c6598b36c2087f33b22620a353e3d2593ebc04598781c270d8c0d309820f56f72db98199eb20f15936fed9747d747112f69d4b797afe328f38fb2eb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304231324544463444374436383836433144313345344346363144324537374430393345333932314633453641323039323139374232463237453234334641434436433539384432453146413646464438443038454234354332383433303036363842323936463230433033424538423032383744393437343736374538303335334134424139323238454536373833324546373737313542344236464233453743333033324344313144313942323933393042313531384138383436433735434431384542453237363932443137423935383341323844333441324446414442413237394142383036323932414541393046444346343343393230334238453123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x6cc3597b890a80b56ef49dfe70c8edfd3f5de600e606bda6def75cb7e4b7610a769c785aada0d9bac5ca94195979c5388668b240c48ad5148fa9bef83483f506	1570073110000000	1570677910000000	1633145110000000	1664681110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x406ac90e139ef84e3b5e396bdc52265282e11a90ca6e84cc57e1534c97593a016eb1d0449d81e342ca075f3b3bbb090f0b3bb0cb6a2e1a602e4e896a75c8925b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239443738393142384232343546333541454546433134433344373333323445463836453338354245363643444639334535414531423342414236444243413245373339423143423944444330324431383132343741423237463030413539413139393531323944463739413243363346334343393441314246343241414633384537334246334339383332334142443635343641364245334237374242464530354439343641304639313735413245324543443730374142383936383237424331463844393935333230354534443543323933373439323834303033424331394339364636463245313134413939313736413837434541383139343236433123290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xf25253959a88ffb5e8345e766acff37503fb4f21c4e90344313c1bf2b92ea74cda2d696f74586ee7da201ad8f6b3b54ecbd18c2ae43898c6a9c0d32ad7910407	1569468610000000	1570073410000000	1632540610000000	1664076610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436414632373844434441443935434631374530314545373232383443383344384630313533333435353834353435433138314534414641423931333332453134384342424541423146433238374635303544433938454432304332363433373343323734463645463832443139323834383934333845303233463630393931303241343145413338373845353031303030463130433731434336393738344330353344453745394244453832334145333139354341303842393630343845464437333732443130333139374636313737383043464543393030463734314433354143454542424631363939463644373142413837413837333331374133454423290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x367d148b84e921853deb3577b7f5ed5c78125893ba6716384d56d540831b790f9a2719a124792fe482739136d2f33de57aa53e65f2723adc19b1fcf7cca6ea05	1567655110000000	1568259910000000	1630727110000000	1662263110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x13e34a6944bc8bd5486d196b90f822d58ae71bbb0afced686d1dec2492d42f1cb0a832a7c30d41aaa02937892a7baf9d33c10cf5dae5902d3a3ad94475ded4c2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241463838313337323934454242334531393946353441334544313142414539304430443842374445433642463746464342413239363937374341344530313336354131463237314638464534424332423146343338353231414134423934323141373941323431433546324536303046383544313134303742313041443642433945444443303430383536383541394638423437423337394236313437413841413236444336313731323642443634313445303143423141353536433931354644364134363234303639444245394236443731343736353842373745454332334639383539443735344443363035393836464144303538383444463345314423290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x203ac83f7d688b5fe7e4edc73c6ce4f7c8257507b0e17482504f10686ce5a462376f7635ffc5014dd12e2bd731a80a13a719ad2f7f1b3ed53d60a812d869c706	1568864110000000	1569468910000000	1631936110000000	1663472110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xba9eb4adf35d365d2478aa5526eb3f7ecf9637864c0b0d57dd0925a803a71af5d80aed231317b0cfe5225b8f851cc03baf84873b31f3fd1b18014496be3e85b8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941373237333830464433424336323832423731393139324239353036314532363343373844453231353235303742454336313432394430343735314535353533444630414139453436313741453041464336463534454334384336343934433134413635414446304239314443314643394432313941433930453037413533363546303931454431453730443045383433433544454646323438463135413346443239423941453536373546453434323430343941363742443742443937393342363430463930374630313233373633383432423832454342374541424331313031383946433841443942333346453141324534453641313430343434444423290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xce2f57ae010d9a611554dabca456e26e0f6118c0e54dbc6b85663e34bc67e9ac71a3b59e772dcbb4058b8b7308c8e9ce8ca2bc69fc095c08ec7f58709560490f	1568259610000000	1568864410000000	1631331610000000	1662867610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x24748195be2038b728d7d7d7fb2ebadb7a12a3e44c4e8db3a7c308ebae043d0c8cae5af298244455f2871702044db34c1a835debd31e8a18d5ab3453187d2727	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304135454535394333433932394532374534313535454346333936434146423439413746373834363343313942463234333630333033363746433639393935373234464530343030423232304336363539433146393631363245323436393131424541353242304545343645453045314135423942413832353635393243344534363037343246374546323442354435343039394434393339303143324534463545313439453531303134363644313738424236333639433637314333463046444532423945303042433843443930334643413241303734443646434636364333364531383731304436363031423033363537383643434132314436354430363323290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xbf1893a4ef59076325e5cecbf0334373a5270c410c4936ae411869efc865440773f6179435ee78172ecec98235dbc8e85ee7f2afd36f4b5784daabd7a4166f04	1570073110000000	1570677910000000	1633145110000000	1664681110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0997507db3aa180cb4a631de0df84517c7ce2de7d44ca98c642461d52c7da378939bed225d5b00baa64162eae747a9668b7156d1ca9e767ee3bc4a2e09ce345d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946423945424544303945434543363733394239413734434231413231363431413342353138354142313742354330464134334437443332434335313835363137364145443735364245463539384632303242364244323143304335324639353039413846453639443130333336363336353931373841364339443344373543324638374642393246343546313931443244393138353146364636454334393138453532464339383434463339393845414335453346453343323335453637373643383136433145383030364345413542364633423344323941304435424435423545353237463932423137374436303946453730433331434634374132343723290a20202865202330313030303123290a2020290a20290a	\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\x63d7a6749fdf7984a8830cdf0126d06dfda4d5b9d73dafabac9430ecb8cab99255e15ba0035fe0d3a138bd24b179efcdcbfe59538e30c6bb226f68e955aa1108	1569468610000000	1570073410000000	1632540610000000	1664076610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x9c1189efc1c2b012fcb2cbf76877a1664964709f1e7fbf6c9b4aea8a6744fb1a	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xee73878b7722b6ab4898e4037a1cb06b140ca78d5c4457ea3e2e4f424e1c09776d6d47bb2ec7ffb6d18b64bb8528d92f86a57212315d21267a57cef679dc1f09	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
2	\\xb21b9dd0fd8c38bfdb7909a16646649594dd5858b7c0610c3d527100b7725c51	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xa48927077dbcc51dc910455df83826ebfc2eded4205defac7cad6880b928ea4b150967d40d4dbb98d4a92222eb7e054249ac8c83fb1050e98609f88d7b317b07	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
3	\\xf48908caa88423bd377db81c3a3a68794eaaec987da63ce92ee8565d7cb802ef	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\x585ea19eb832decfd214ac78abb7d4b60705951826e71d48c066793c11ac4cd3bf2f6c5ccdf0230743b9382b1fec42fa5d94d21ce59033e8e7d38f826f47700a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
4	\\xedbb09d5ea974d56789007041e70215e45cc17e9a8aee9fed82b4a9b49ad1102	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xcb61bd6e10c0273130aeecffacff4a2cf3f84fb1d89d9bb6333d64551529b70756ec9950019bb69aee91413ba24d8720b547f3cfba41ad20dde7510a1463e70a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
5	\\xf35155e86419de674bf7decf177307a9a937506db01128a4cc037a5508dc540a	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xf68522051631900e390cdcbb5e6de49974f70dbcf61e563e9c8b89f88aa1b75888b809e5c2c0f1f9215653c58bf5ebc965e05abf934de362a20eeeb7268ba707	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
6	\\x0f6368b30556a95d386451bc65808cdab57280bb4c7359948f74e8a724b16938	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\x2c060de8d2db908d63221f236ea5f990e53f0df0df2630a1fad5e4682dae175ed0825a4fe44770943ce9a8abc87bf68e2044f264d4566cd5adc0635449457b05	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
7	\\x9e87a191e9d35fc5bae38d36d6df9b2982e020549579da2a36e067ad6bad5ecf	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\x78cb56206714b25220dcf04f6773851da619b058542b7e8535ac8f2a111b3ab921f340cb120f95436b415787be5446b39fa71d2a3cdfa89eead2102c03066001	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
8	\\x440a3708f29296d54403a457d6cff4a8292cfaed0f840d22216e803f188fe6d8	1	0	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xcdadec85f9f11637f0de2816c89188a2ba66d85d8613e0d85e1e44a96cd06b38384c2f90f941f4116207806123ca4c5f3cda2e95d22bf932048b4b41966d970a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
9	\\x9196baaf5a72105e5ad9a579fab31f106e47b67078b3d8ec6d496a5eeff15a75	2	22000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\xd1794920b0775399ce1f385600dc4ab9291368b27e5d45f432cfe6613428fd1966d9a7a5e641d7485166b11a356d2ff93d8a4e69cd5cd48d574d1adbd6cf6c0e	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
10	\\xd4efc7e8249e637245889c0b6d92ca874a8fb3ff3f08b6aa50cd83171f941d41	0	10000000	1567655144000000	0	1567655204000000	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xba4738c41e66092dce11c37e058ff454093b2a9210baceef1e12edb68eac2fd8382d5a919d221d2187dcd72f14599bbf585d7a5fae7d3565e9290106eb1f7600	\\x28d10ed49b43ad64edb03a660ae1496bae489125477fd3f427764dd5658e98cbd58864eb25ea38414aae549eae5c005dddc25f5b4477ffc203bcb4b1b09ce900	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"FDHCPZP0HD0N528P0W73SY0FFFHJ8EMSAV75JX0B4EWYSPKEGDZK27R975S8D04F243W3BAQD4ZKX8J2VWW8RHAGAN6KNZ22QJPW9HG"}	f	f
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: grothoff
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
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2019-09-05 05:45:29.763098+02
2	auth	0001_initial	2019-09-05 05:45:30.436842+02
3	app	0001_initial	2019-09-05 05:45:31.89241+02
4	contenttypes	0002_remove_content_type_name	2019-09-05 05:45:32.143057+02
5	auth	0002_alter_permission_name_max_length	2019-09-05 05:45:32.161048+02
6	auth	0003_alter_user_email_max_length	2019-09-05 05:45:32.182852+02
7	auth	0004_alter_user_username_opts	2019-09-05 05:45:32.200085+02
8	auth	0005_alter_user_last_login_null	2019-09-05 05:45:32.229134+02
9	auth	0006_require_contenttypes_0002	2019-09-05 05:45:32.235939+02
10	auth	0007_alter_validators_add_error_messages	2019-09-05 05:45:32.260085+02
11	auth	0008_alter_user_username_max_length	2019-09-05 05:45:32.317154+02
12	auth	0009_alter_user_last_name_max_length	2019-09-05 05:45:32.348843+02
13	auth	0010_alter_group_name_max_length	2019-09-05 05:45:32.371459+02
14	auth	0011_update_proxy_permissions	2019-09-05 05:45:32.390437+02
15	sessions	0001_initial	2019-09-05 05:45:32.473337+02
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xb14892b582f7dbd9107fa9e7ca07e3768d78f9ddc956d4b204c59ca2f61b7fb2900baf202c864063d4c4c2b37c737a66aacf03140373cbcb4f2c6d69879e5909
\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xf848dfd4f38f4f67b1f284c2d7fd07124da7cb1e4ca5acb71346a70b85731ce40389f067991912fbac8c3cf82aef066d64857770d43d420c83de06e60ad62e07
\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x03f3491709dfd3d8e139492efbb89c2bd780f6438489f1a8e5f15656160e50b87bc4f9ea904448354ea613a96a4013c4508d23b6631bbec04e0c41840852eb04
\\xcdea85c3a03a32f8625b24688991ab1261f2ac46c5eb40efeedd3a2022a1f084	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xd600bb45f2b0c4bbd0715ecc7a4ca4b138853372c1e4c0309e187499a27b84c6bd114f78c623e050e3039b44f230a365ad2473efe31b6fd3641a34be202d3d01
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x9c1189efc1c2b012fcb2cbf76877a1664964709f1e7fbf6c9b4aea8a6744fb1a	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233230314532324635313845413046443636423543413744314436453034324233373839383332383932324234413631433045444637374334373334453533323544363243444130343734393642353844414344303739453430393636334136333334333743383545383231383439353035443539444339353246464446364635364238454243303938454535453436324237443646464344303232343844383939413030373638433333444438344244313346434631344643304631343337453141433339313137393337353038303438464431324446394143373333373544393536444435424530393433413938373535384130303533333938343742464623290a2020290a20290a
\\xb21b9dd0fd8c38bfdb7909a16646649594dd5858b7c0610c3d527100b7725c51	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233145443431343946333145443845383031324635364234314341354645333536303446424333373542454237384534423944424642313139393332353035333431364530463545443344343042443838333830414636433734373034444442453537434345394444374245434535354232433035363635364544384541324631394539384343464238343537323532373346323642323643413033453531414143313143434531303542394232344241333932443733443245434535374139453038313736324239313833303543434446443039344543343334343246313235383142304439364132373443314331463339423237323145384439444642423523290a2020290a20290a
\\xf48908caa88423bd377db81c3a3a68794eaaec987da63ce92ee8565d7cb802ef	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233931453435463637463646433345463341353230453641423833324533303246433138344145423742414539333045413444373436314539313534414236434130423235433032383538443845353841324630443944343835314642314136303541373941423135373534414437304436393645353445364536313435373230313143444234393034323231463632373343433343333339454342463846343332364546393530333435344343463642333141303039383244433734323446434145413138363531393635393939463239334534464138463245353331303143413833463742363235453844393144433545344635433136364632373839333023290a2020290a20290a
\\xedbb09d5ea974d56789007041e70215e45cc17e9a8aee9fed82b4a9b49ad1102	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320234246463434383639383039414636454144363735463438314336353639413843383430394133433534333637443731454541324533374245314332423246303444383444454341433432414245413631303035423338373736313030413146323030353543344245334446333231423737463130443333464445374646463837323741364344374634373241443836413434353041323136423834364645444534383433444136334545464236313436463634383441424242443646323035313835363138323543384630303944384139414131423037313037343234424244333430374541464234433942344337364345363544453344433933393331453223290a2020290a20290a
\\xf35155e86419de674bf7decf177307a9a937506db01128a4cc037a5508dc540a	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233144303035304139353839433537414336433042463538323438353133303835443536393244453736303435413333354541394645383733363138443830363031454530323145444233363132344236443330423634303946353946363143393832393439323835464236393934464443304438374246323934383346374242314436464330453843353234343136334441433139463633414332433443453045343031333146434334453633464232434636433538323533423845313830384436383832443638393344353842443343304145364433343938413031323236463945323136323736333436344339444243433239463332344439413531463623290a2020290a20290a
\\x0f6368b30556a95d386451bc65808cdab57280bb4c7359948f74e8a724b16938	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233732343431344342433333343438333245383744414246344639343338393241384136373442464344343235353938463145394245443945393345304538343235324633313445424142374638433835324432424645374638324339343831354543323334314641373336323237463830303138323531393644463430303446393646303441363332454334323338413236433146334542383133323832323736464635303445393439363635303345444531424245343637394143433933394330333937373745364539333237433043333742464135414538454142423543363931313936333039384331464445303830423646433131433435363338413923290a2020290a20290a
\\x9e87a191e9d35fc5bae38d36d6df9b2982e020549579da2a36e067ad6bad5ecf	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233139334445393330454535304343364542353633343430433944363634304138414332423242373532304646434638394331363841314239464433344441373344393435453031373345303846373536323931323241443336314534303734413345413836343432423938423145384443394339353844383445343545393835324545373541343946444236444336314230424632413045453332323246384144353435394139353534383341303930413645353230313346353138304645444544353543333335443436443430383342343033323644354534453843464534343746463034314343324233313934373145434641424133353743333530344523290a2020290a20290a
\\x440a3708f29296d54403a457d6cff4a8292cfaed0f840d22216e803f188fe6d8	\\xad63639cc3144f7f188cc8f6c612e482b2468cd490fa91e36d7acc6ae4de655f16ef34c4d42ee98dfbf3ed8ae8781c2786641bd851a89ef3ecd0953d7266ef8d	\\x287369672d76616c200a2028727361200a2020287320233039423730313545433246464638353842453545353636363430373137383346314344453532383538304533464635414535423246423138453837313438383841383544423833323632334438333936414643443746453133333839413041423439383336343845313144353734464539433937453836314445443130453131334137373430414344373643323543413143364644463841384643443036303833424430424435414536433538344434393446374238444544413942353931373135333642423231343039303730414537303344434639423534463635453236383231304334313135314337314644324439454435354231393137344236313123290a2020290a20290a
\\x9196baaf5a72105e5ad9a579fab31f106e47b67078b3d8ec6d496a5eeff15a75	\\xc29fd4c0cead9296602907dc4c543655ec0b9719de115e1e1157d610d9309fec9f9dfcfce3e41908dba924b174b8a696ec07da544e7bfc71a323b3ec41082f23	\\x287369672d76616c200a2028727361200a2020287320233042393237444631444634393133344139463144443546323045464439443030454138413843423341443846394539314638443339444241314232434346394330423936433335304533363446314441433933343230444331453734444234413743424545444333414334353133324530384542334643414337344332303741323931383133304235353839314235343743313938383733333430394541344144363944434431314546373544373033424346334331334235333743303737463341363446333843333441383030363531354644463242443937394143443530464633433736373443334530354237424634413734383246303744323833423123290a2020290a20290a
\\xd4efc7e8249e637245889c0b6d92ca874a8fb3ff3f08b6aa50cd83171f941d41	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320234335443132364235423338334342443136373838324344363835343030463341393033373941384435354546463339423441383346343335304142304335413934394441443742344339314237393645384437383043413243423534433845433346333335394132354334313343343033304244443835414139333339343130393932393546433834353136364339363841334239343246373031353735434433464541344438353241454635363334304644304536324537353137323636393941413236384635354331424144383639373841373730444642333638324242443736413731444638433838463941303745453833304245443935313446453423290a2020290a20290a
\.


--
-- Data for Name: membership; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.membership (channel_id, slave_id, did_join, announced_at, effective_since, group_generation) FROM stdin;
1	1	1	4	2	1
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid, last_session_id) FROM stdin;
2019.248.05.45.44-81S0M18W762G4	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e30352e34352e34342d383153304d3138573736324734222c2274696d657374616d70223a222f446174652831353637363535313434292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373431353434292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2253514e38424758303738534647524a5634484d384b3444423239475a3542323652514e4d31565a45564d583230384e3159323230227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a225139334b484830594352344a564b474852445a3042335a4d4147344b50414d4a32325843585652593242505644334e43355a4333474241544a36454a34373931475a45444542524d423644565950325846394654575a394e43514d4a4a30383658434651433030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22533336424e42364a5942513454564247304d3844383246304e583456565132524b373444564137475132364a4e45544139534730222c226e6f6e6365223a224b344e46483034384a41584b583732384d5936333534574e4d534b41355a50594646533342534d51543148544532574d58313930227d	\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	1567655144000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x9c1189efc1c2b012fcb2cbf76877a1664964709f1e7fbf6c9b4aea8a6744fb1a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223730334634345059433746304a39574e57383942333536434542465437424254343237504b42584a4a534d4535423437344254314a57593848524e464b444659573957594e39544756574747444e5843594d4442585848344430364154314b4234374239383238222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xb21b9dd0fd8c38bfdb7909a16646649594dd5858b7c0610c3d527100b7725c51	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223231363159415138445354454352364230443857445839574b4544454b4548335431305236373348485034313548425641324754485a38303650464246474a3542484a4647575838543153423344444d514456583432333037533759574d463439334d58473030222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf48908caa88423bd377db81c3a3a68794eaaec987da63ce92ee8565d7cb802ef	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223450304e36465151384853453442444d474a53444d4e43354b343331324d3251304444575a4d48544d4432354d3746474d51424141363643513246473038365247425133304d344338444e433458375244393043453348573845454b5a384d4d36324131343347222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xedbb09d5ea974d56789007041e70215e45cc17e9a8aee9fed82b4a9b49ad1102	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2257455059585357374650484b5346385a4b59395a515938353454314139443433463543584252354544573158543635303952474350535446375443434b324741545036315659305335475245444153444d4a5636545a47374856524643354b354b364e4b4a3247222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xf35155e86419de674bf7decf177307a9a937506db01128a4cc037a5508dc540a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22464856565752594534575a4e47324e3536565737325443533045474a425a4142323754424b51434b314e544738584857565141433857334d5235504343574b435045333136335350394331413237585843514842545033365146514a5a3945543147454d383038222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x0f6368b30556a95d386451bc65808cdab57280bb4c7359948f74e8a724b16938	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d445a47445752534359393843374e4748583656305444384d563946545152565a46514636515a4a4841534a3751483145534a484e48455833514843444a323231474141544b4333434d5654595a4a39314358375057394557314138504e4a4441463254573252222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x9e87a191e9d35fc5bae38d36d6df9b2982e020549579da2a36e067ad6bad5ecf	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224e3332533052393841474a353533424159534d58445639514230304d393156394145395736414833304b3144583247474a35483753534d454a59424359385148365938485a46454458353459593852454d59443741415443504b50303146594444314b59473147222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x440a3708f29296d54403a457d6cff4a8292cfaed0f840d22216e803f188fe6d8	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225045594e385235533453593137305a443653525053414a5a3930315853413842533046373441335454443159413159354e414551373148354a39415a58434a39364434564d3659544e3358365330374a36444358353232514230455932335a45343448484d3038222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x9196baaf5a72105e5ad9a579fab31f106e47b67078b3d8ec6d496a5eeff15a75	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2243565745523237565a343347374b365830354d4d563236535a473836545857344546343959424d38574e3657453544443043533159425a3645475150464735543243323848355a594e5257425059524a5438584737354d35325636314b3653314447344a573238222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\\xf1f38df3d50fd32c1b9aaad137de82bcd7fe536fa264f77cf07e9e8cbf764409f5f44e4332f652e25bc8fab4d5319110b9446b93a731eb58853b114f12a11900	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\xd4efc7e8249e637245889c0b6d92ca874a8fb3ff3f08b6aa50cd83171f941d41	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x19a3bfdbea0277a111d60cbbe87c228f14f216612743c26e0df994525b2f8947	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22434639315a32394d5656545252455834384a32364d545a36424b584158485a435046435859454143394442594531463043574e33574b584356364e56484151565642365354325239314d41443247595a354851594743424b3237474547355039444b574e323038222c22707562223a22333648565a505a413039565432344550314a5859475a31324857414634354b3134583157345647445a3641353450534648353347227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.248.05.45.44-81S0M18W762G4	\\xc8ccbaacd2f2ee4d6d700510d409e0af49bddc5899c8dda8f0b88d2abb4a4e60	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e30352e34352e34342d383153304d3138573736324734222c2274696d657374616d70223a222f446174652831353637363535313434292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373431353434292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2253514e38424758303738534647524a5634484d384b3444423239475a3542323652514e4d31565a45564d583230384e3159323230227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a225139334b484830594352344a564b474852445a3042335a4d4147344b50414d4a32325843585652593242505644334e43355a4333474241544a36454a34373931475a45444542524d423644565950325846394654575a394e43514d4a4a30383658434651433030222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22533336424e42364a5942513454564247304d3844383246304e583456565132524b373444564137475132364a4e45544139534730227d	1567655144000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.messages (channel_id, hop_counter, signature, purpose, fragment_id, fragment_offset, message_id, group_generation, multicast_flags, psycstore_flags, data) FROM stdin;
\.


--
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	\\x9196baaf5a72105e5ad9a579fab31f106e47b67078b3d8ec6d496a5eeff15a75	\\xba588af7c13c477dca1ac458f65cc484db8fba53b969b873f4353ecbd815e6b4c03f42c0cb63a2b609c2d726e612fd8e0c084906a41f409b6a23a08a83c89a01	5	78000000	0
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	0	\\xa7a6c00c5bad6c262e27f665224805a9c40d2810ef084175f761f8cfdfa896ec45038227f4f4c58832d8a51214de492388466d5578d6f1b335681fbaa3169a0e	\\x22369e9156baf793750fea67c175f50a046767c2da78498e0757e3fbd18971daec1e964e881c2ea98d009f08748dd23669b6373cdd76eb719b28126c9f341d3e	\\xbd5212a02c28e8ef793b027534fa018a00633ef49b153d4db3454bac7b9c79ef9803e9c1eb1f99db5c132836b76a0f61b6ecca10cdbe4b3db531fe0e8717d436f28ebc022b7e31c4bbbb2be7909ad2c8006a321b4c20f6d6da458dc56872ef01dd8ae22e6c5ac3b8a5de8742656093415c8bd55798c249e315e811dfb97e3916	\\x3ee25c77905cab0912f2d8b68e0410458a08d5a03d33905342efd479f6b791653cd466179a22cdd58c77a01942df88e4993a38a2e26d9646c71dd2e68d2fd681	\\x287369672d76616c200a2028727361200a2020287320233941303842353144333743383643303736434143363342443946354636373235423642434537424442324337383946383638343538433842303432323741453033334531373345324334314443433643393042344335304241413435414244413746354231454131324630413945383546434138423439413937453335463632373637383435384331423745303746374230343334463244313933444541353435393832333635384432414139414446464537333445453646333444324231383837393639433534363232383145393041374646363630384331304545414139314333324135353943444135394539353435454345303634353736313745423823290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	1	\\x480d113e66c69e203ed6ab46a1dddc1edcaed80943a5877597fb16521109b1a24d568325e49013726f0fe4fba844ccc4a67edaadd52d559d9a93fc3613936b0f	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x5f267c47e7fee2eb9dd5c8401bf0d1dff9385fd755ea9647adf9c9e7997988d7379e9a066c791c865193f12777d9d563fa0ef8d2776cb8ec6cbda0384511665e0ac75e88e44d3047e79760f9406c1006e6076f75fdda6ba925ff76c78badc80aa01d712ba2919c1160fe5795169f7ee13ebb074032239bbe19b1169a9a67eaf4	\\x50b9132a149b4630b21b41fdbeae22e1507ffb7e5bed53daace24252a1933c721fdd2a7a269852638c9512415d812fe8f816765da79cd49442a9a50d6108ca1a	\\x287369672d76616c200a2028727361200a2020287320233146383533343739333630454533454543364335393733434246383134323835344446453245303942333633324343313246394532303844324546323045444445434546363435384237303534314345443037463636314333324531394536424631444531313436344636384146443133364144423238383232443633333238314642303141454343333144343836443545303530453030314630383534324131433541334241443846454632363642444130463232303730433146383630354332443239373330363043413543353434423033343242393532453645334336393335443545363246434446423342373433363234343643354343374242453623290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	2	\\x38b7e63596f6f856be4b51b5a921d8d29707289980ec728fae18280e414927386bf488bbf86e72b440d5852a585cd88d70c0706d51d3bc77370406612261580e	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x13976244ea207ffd577222b8403c68590265bd5e7f48f3e3ff7c049138144807118e08a16fba51f7594ea14a2ac13da8f99e99a273c9cf865b7a5d5fed6b57ea8d98a3d8cc793aed73467ba17f55fa33ab7636cbbd7027e0ba42c1983991955f20d64c58f00bf7235171964d868ec1a83d3b0e4e7739d717c634beb91be0fb24	\\x09ca56fcad0e2b9086c0c82a2b100ee9631a3ced138490c79ac794607a21143baa3e423684b200c3f60b2a3786a2630255fb799a221fda7a3f4d43b07dd46343	\\x287369672d76616c200a2028727361200a2020287320233538363846374343423843383232393144394338363039344242453931423935334139334231374433324238433241323031413138384231384646363939443646353039444136313636313239314135354145464337394238343339333042433333304335413342303743323846343439333033313537393733353132313530394544323731303530333545313741414133304333383833334139423344304335303444313537333530313745463136463044413636373644453637313746464335333130353237443132364631334442413634364439433946344442334241324543414545424632383346423832383939393937353532374142303445313323290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	3	\\x7c8e6ea2382b073572dd8f2c2d47663f3283dd41e78e7b37c28ea7f8a09feabe33432b0c571d028b0fa55d529b141be7474c157e60513b2af5f2d99c7077850d	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x078b7736834735caf7737ac115c863592f06d391af2a4b89b6a3ad84ff5b579075de4df0116f67bc50d8742681b2994c2c7d7febc926fe181a73ffc9adff790e65daf08623f8e6f78eaba847b92bcaf6333b1384af23a0b6a173c23395bd4cbc9f5e8e16dbfe7063d0fcc6af319d5fc37664e7901f12f460ccc8ba10a3c33ab0	\\x45c1f3d1119b43b5d0a9edfbcbc1da421b7da28e5b6f308a57371219ac6ece45d4ce97669cfb1d8a66f4940776b37e191b1105d093f36447ae3ce3744de4d523	\\x287369672d76616c200a2028727361200a2020287320233342383536333043334238394542313339434132313243433331433532354538383837454636373231303033303238354543413446313539304343364534373643413235454146353638363943364443413633434433313241394434443836384241343738443145324239374139373639384243454332383643313445333139394336323434354334313630394241444446423142344335443632323545324241364341433844364335453441314232364643394641373044363434383945374345314337363344354537314432393436393141333532423933383643313841344243374245384533453745313141363446453944304132383444353943324623290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	4	\\x50d1c654eb96c38a005966da7efb52018f24748c1861f4df2cd0859036e72d703b45dcd4751a0401781db3d776428af1594a2cddf30d56bc5e45fdadbe5ced0a	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\xbc0e38cf1f61e74e95a7336c46b992a82b18c8d5c77829e64c8d28530ce69d2f44d5edf37d4610f95fa8b4cb85370db6f1e58b5b379b3fcc4b7de976ecd624a37b5dbbf2019e8423202231411b2337f7f32825062b999455fc3eb6c1bcfbe9bec0f5f16d7db261a7f0923887c4ce798a3f4e8b349f478e9ac1181283a0781df8	\\xbc0dae5c9034e15a4f3c7a29c47907f3f7fe304a9f5c1f3e2701469c4593f9c035dc5dec3edb644b954418ef9f1ea9b39db005eb29e0cae8cf79e4768b0f2d5b	\\x287369672d76616c200a2028727361200a2020287320233435453334353937414546364244394143334233424232413232303144454445383645373732384543303435333732393144394631464137373933333732354145453944394546423042303234384646364233444341334643394342423442444244454537433742323637394532454238393139383744313946454344364138333631423336414245333831424446413630454446423732303237443639353043384546323434424236383245444330303839353046424542333832423030454441363136463743413330454132454137343834394636433244383539444132304530433346463135444636433830444433373330443343344637374239363623290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	5	\\x7abe1d338c298c392093d879bc9de940bf0c50b8574bd9b5fdba8c41aa3be6243b38ce164a318f8117ada53f7bec08008bfd08e9c081f26bc87e9acd62e31c0f	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x9e15ae97e07ca89fe225c2f8627f63122be5e68ca9a773ba544db13d922bfa464403320c377642087c63cf7a40a774d11c8be98e53f6e597ec7d71998a7de28a10abeeb7b745c31b01ff8b426f97423cc45431e5833c194ffb0cb1f11343fb787e3f4b16f13fec880c8c749ab6c0e81daa63abda3ebc31d3ff0f98b96d5c162b	\\x9f98f209ade672658aa84bc4c66bdada529fcf33e4904fae83578ef3d1582121854306d6fec6c5889a3ec6cf0bc155fc1ab1b8e6b79bfa42f992f4128e6ae4d7	\\x287369672d76616c200a2028727361200a2020287320233045393744454246373746433545434433454331373041364443463837304641344142384237304246443931363345433732393144414430413245454142354143434537434135353345434442373935383831434144344632433639363236353641344336434431424446343536444446323841463838314245433641424639354238433133423830334144304143333443423135443845333936454437463930334236314243303641313636324531344437443630383242393430463034443741323233433733333842414445443546364236333138443133423033443938333134354434464334363734313933443244414343383945414545393046453023290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	6	\\x949b531b0377c05aa7f02899c7327998e313e3a2a82c2c83a4dbf2850b619c04c6e7a9111c408b11fa3894c2f101f15df32dba2596e507cb106c1abeba138705	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x5fd8a6fa520c16dac6b244e768e13b646390306d838330c1e0bc14f23db710c1b15954c538f1f89d68225d1cb7da8f1c58b99296ca2219e0c4da64d9bd4b413ee6641f26ae259db461b5258b98b7a23bb3966ec9560fe07a9ed0b8f49e7f59da7c1c3cbbd88c7f4ba21ec7edd3b3f677515170feb949cbdb1f05c5aacaaaf204	\\xc378293df1cfc89ee74fffb321cdb1a1211cfcab1eb69783915c2c59285b42568b296b3b81e021cf1f319281f4c7d031adf27e32ea123e34e10eef60389a0763	\\x287369672d76616c200a2028727361200a2020287320233741433144444342444239374541303332384146363531414338464646303743353330333133393444323443433636353443384339393944393133363246383736343835384144433844323235323538413438423244434433363341353139363234414643353746384343363338313632394634394638373743393943344646423434414139333830453131344445363737393435344338374645323637423546353844453034333442464432443830413842423439344535463841373530413746454234414332313436353133343641354344453838434541353734394231303734463641313834323041423637343643443443393842364331313238353823290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	7	\\x94daa3ea8b74a75e1c1e397664f0688cc5f231ce26227b399521d87b09b047d97a82ac80fbb0c6b012b39b735281818476c8e74077f45565b5a0d7310c260c00	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x9def23e2221a62cfe7c606207083ec0e18ac22f87e68a1a4085df1bf0abe3a6a0bba6e107a3269b725d77b67ff582c54b1e9a9f574287c980fe520ff307b7f20c50b28859025c53b0ed76574f3ac8804af1d0672f7bf7132d020c3a9251f0c7b2be059136bafeb6e2c3eb3eb46e18773b77d6ac25611cad804bd6f3eb898a793	\\xcbb5fb659a9c90147408e767c83c7727f67ef90e213ac440a42b3c4977df5986c3daa01080f3ad2ee40842c6309fb85088fe831b7de2e4ddf5295bf0fa4dc72b	\\x287369672d76616c200a2028727361200a2020287320233033304531304543443646323142394445393938383234393944343543424646374334454638333935463441444336354441464138453842344539384335314336453239314133413742373735334230333639353632453234453631353036373838353636364531453230383236343341464636384638423231373341314244314335424346363936453441383038374639463931393039353237434344393736323943363035333333343544444136453530373346454442314132323332314544344443363038444344314135384346434437353637454244323638414338324636333137364439434631434643393230343639303436304435393731433223290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	8	\\x88cc118d10ebc831af38e9e5bd374d3df227b9add2c63a459c7c48c5d93dc3e9fbbedfc1902fee5c566503da979e1b1581bb06737b68c5744e4187b41500180b	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x5ae21707c29287305393c893fdd7e314bc2ae1596a04f87fdeed9860c20fe3fc47db0cb4a9ef70be8dfed355e9b89db191104210cc6922fb08cd088784e8f783811ff57a35eacd2170547a03e3bf48d8097f93037a28d618be18e24a17dfdb8e8a0e64b9ac1c760e32be4cea6c3fc095378481f54b3397605686706caad502a1	\\xdb2f48d9174e2a9dad762e5ef87b8a9a77fd69a88623047fd4a8488effe9e9e21966f1e4a44826f29c749ae028d1d15164d7edc76a67d787300bc351d6d11d21	\\x287369672d76616c200a2028727361200a2020287320234132383738464134433030394141334542464133333535394139313946314139444335454538433242424536413138364141354530323241364334453132443930413738413837303845413439393636433239353343333737303439463030444246384233423534454633364433394438353937453444434333343337364330333344363043353046324641353834323236353134443433453239393041324445353641374146413033394235313536423841303541384536423531364346424341333332344346303546423334343544343343413242453541354145334638334245333544433943454142353243343930434334353038333743413236394423290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	9	\\xb357c1a10c15a9deadd235b0bdc4899ad55a6a559dbd933dac55c6ba4d1c965f3c388bd79763617a0d406b523fa8da496df5c57dae6af85695997a8a27bb620f	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x62f6c4872b90b25bf81a5c805d76145f8894f0d0696253c6fe62e4e4e767eb62dde6f17364a94a20e75e3e7f261730aeca77137ce637d23607212050322f5f9e7e6766afa6c5c7642da8079fe36485b9987f8bebc810d28e4378714c19301d9394fe7fa66568238e9e12746567f15e08f144a4b234977493a01bd109065aee2d	\\x8b3dfc12520c57c927384984fb09fd28d747331fbc1f3b06f748d2fc37fd9811311c7a2187bb7e6bdb7c25f6878dfd2b25f22a4d722f65d2ca8cff4ea1119c31	\\x287369672d76616c200a2028727361200a2020287320233635413937443737393139433735453330353330313639383734383838323536433536393630414433463231333936423541443732394236413745424238343737394437423930353233323741443135303132334333453633443238464536433932394144333537353941433039334632304433373133303437383441384132413445433135333938353839323744324337453234374243413339454430373337384239363244303939363439414236454441393338423245323938463945464638343246314630344444383845463446363438373944373632394142324646344330374343303439453839324537423842323736353043434242384334353123290a2020290a20290a
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	10	\\x0493ca6c58fb5537c6abd202dba30b57bb1dcb19c1e9e739effc58ffec15c815deb48676bd99df03ab5bf16a346ffe52a96d0f1921676adbf7c1351510fc9e0c	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x245c8e4495a07cabbec9e407a1d08e63584a316c91f75263475d174987c41c7b3d1737f7afe73f0b112accdced4a1e7bbc97497c3de1b191e6f07559ddfd5cde30d8e26a3926300047accef01c8fc45bedc705fd9b867c2988d490ff36c2f2927941c40b12eb885e8db2317de149462d3a1c01c176beda03d0d39c014f12f257	\\xb6fca14178f47d8df5cfa8442af974e0a128362432acfe71174591925ea575ad9c06c1b9520527828ef1195b8e05311cf8f0ca87513f9e023a67522f1055c2a4	\\x287369672d76616c200a2028727361200a2020287320233738393045354334373636453731344239343546433836343032433333344435443842333431423230463243393937424533454243373635363142463746334141323746383936313835394246383941463343354442443932383431414546353439394145353539364434433343443933343832413644364637303830393645383141463745343245433531343138363437453233374642424431443245363142393630324345304238383631364343393535434337373032393530343532374641454534304330334631344346443730444230344143383437453336303841384235433739384234414633344238424236383142423338393638313432304623290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xfec7f159d0c0913befd5a0399f4bb6c8ca8370fc815ec3937e64317b213bc725027122e12ec182a96d138dcbdd759d30c0447004a98ce79ea75460d9f4414c0c	\\xee6653b2d851bf09d138a2043df85d0ac8ce73117bb73094156b88e1c3643368	\\x977cd72839cd789161b9ffad94db0367e2426c1ed5d581cb5e161bcd066707def32b7b2c2f4b01ff0f97d88a10c5b5787d1229c8513663b3612535a689d6081e
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	payto://x-taler-bank/localhost:8082/9	0	1000000	1570074341000000	1788407143000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_close (close_uuid, reserve_pub, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_in (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date) FROM stdin;
1	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1567655141000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x0ce675c25bb19652595a8320d8d2c40f399eb432d5c4835671956d63ee6405b333b52a0b2f1868263db51a9225688c4914e063279347cf160c656307fbe16748	\\xc29fd4c0cead9296602907dc4c543655ec0b9719de115e1e1157d610d9309fec9f9dfcfce3e41908dba924b174b8a696ec07da544e7bfc71a323b3ec41082f23	\\x287369672d76616c200a2028727361200a2020287320233735374531344634354139464437313735414344313832303632423446323836393444363232423531433030423532304531364532364141373930454237323134304141303646393538353142333032433331334238303638384433343634343832464635343743443737454144353035344244363434393437324230343643424338453433363137443043343831323836354342374137443933324537444441354541443343413142444631303936313745333844444232394442353438453736313932343831304143433937413042343938373338393041443839313242363534423935303439334236393841323034363835384237393534434146374123290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\xb6bf008c53d9fafa9f04fabdbf6985cfac7f534f094671c2eb27b0f35a6fabe30d66101b555eadf6dc316d65fb14b09862b8c79237a3888239fbfc939a2b160c	1567655143000000	8	5000000
2	\\x76db7fb54887f6bc7f2e1c3af72bfabe83537f91381c20bbe96195fd6fc154814c2f831881b5ed96d6ba808bad2a25891855d7a448343789e80eff2a90afa7eb	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233744423432393638424534363832333633463637383142303541364237304435414132454644394544333442343346423939434233303738444136373630313332373834304345303745333446394233333335423443353744394130313746334245413741374441394336453046344239363441444246433838464232464331414130394343333344343135443532373941453936353533463632303633463730343742304142463535374330303635453946464442413241444641333743344545453044454244334130313434453838444642433841354332414531454545363536443535323731374543314542453442314543373345394638374535323423290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x2b252e245ce76da5b39d87b9027c0870e5b374286876a93bab2612102a10a7dedff18645e5438344a7623363ced10cd79d3afa2ad1a3dd2c4ccff1461982f20d	1567655143000000	0	11000000
3	\\x07610a3b98a0ceaabcb9d39eb3cc8dede0007af2c419efcfc96221b6aaf6bfce44abb7476b20918d76cc9766ea7947af8bf193ff24e12e08eb12228125bf6ad3	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233544393939413439344235414645374142354545433630433241303746323634444532353942373831383233383346363244384439434638374344453338464538374146434639344236303239413131353730464541324431453739353533414437393930413843303434393846423343383530364433313438443141323146304132393736353539443430393842323135343433363939413646394537333236373745414332373538343441463442444639323536424534313831343943334143433535313139373630333032313544443235414137433435383445464145413630453131384635454344453330304331363241394439434432363242463923290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x23de38f5ec4166ea2d9fa12e38b941025dd127e0acf0bcaccc1ec7d91bae2da240bee239c14f271ef5cc29c0e0da2d425501c2199a09a57fd2833ac3860f9c0c	1567655143000000	0	11000000
4	\\xfefc5bfc5aeb87092c6d0131fc0db9fa282f5b373e7d3e11b4954269cfdab9ea6d4fa445e7b1fc730cdafbcadcdb80ce2aa1a287dae1e3dd3d8bb961f6ddcb78	\\xad63639cc3144f7f188cc8f6c612e482b2468cd490fa91e36d7acc6ae4de655f16ef34c4d42ee98dfbf3ed8ae8781c2786641bd851a89ef3ecd0953d7266ef8d	\\x287369672d76616c200a2028727361200a2020287320233333463233303538333643433234393942373738344544393133464535393638354234313332333632344345364345424631423234383936333333324536303643374339333439424635364643324339363336373032313532463631353730423630423542384330303945373631324335443530384634353945343732463437363238383333414643323232423638443534304644423839463032393631303143363133313337413841413938394539373731434436374130463237433237334346463644394532363742424233454441353239323743443941314445454646453538413534313138383331323545454535443131423432383444354132353023290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x5fc5f05d5689c288a63f7e47862382620572e2817f25d5b271d81d235a0e67eaf0f0284c2ed0b56c6885abf93ad2cf9e1e21bda30069d0e6c6a0c34e86d6d505	1567655143000000	1	2000000
5	\\xb225320cebde2d9e997db02ba5bef9872ffedb1b3a9d661eefd515e2c8bf3dee21e0e41235935b8bf3d9886a0ba2711806b267e13803ed3306855a3368d717e0	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320234346454137353043373437423244433142463932314645304338434532443639453942443239394545393730304135334441424437393346423843374230323933443535313437303846334339303638454434363543443034454238354444344545423036454543413035344239454333314330384134363039393731443432413130384546423143423044363345313544343436414530343243463230424342353242454442383737414646454637324633383334303631324641363338324435344646364437434231353530303345313733333839443936323841413345464545443136364546464338464241383846413335333636363130463142414323290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x7b2ef3692c35e62ecff211a370a848ed2b59f757f7d795fec9d12ca3b16469574287928db2876bc6e9070e0d93668387d550174d7faec90a2f8e414dcc0b8207	1567655143000000	0	11000000
6	\\x15955e99f08e2741dccb16fb35d765b2b55789f6739680ae727adebcd21c618e56d52b01caf036ba22a5aa725cc2849549fd36d01d4a1161cba64d939f14d6e1	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320234344343444394546333043304532364241424537453741313443443933383137463442343442344535394431343946354331414436343436354132424230443043334234393834384138373645373845393143333337393142373642343842444144443936344646333246353441364633363135304334323136354643444543443843463231424131303838304130354339323333353932433230303535423239304645393437424633393441333841304146364332454330334535434646343235323032464245453045344243383133313845303646333536373437453135323232344436393034303935424230304334383332453236304433413744383823290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x8f52c1a8f6a709f1b4ce82cffa28942345af1a8d12f0985e0bf9290eabd037d0eea654a6f0adf303b0b30896821aead002dbd18662a044d7da26ee197558460b	1567655143000000	0	11000000
7	\\x2a7098d38d9493a2d592c4e6fe648975447f1b8475635b900f0d9ca4452568d5d5d316d3430a1b3ee2e9828bc6cf81596f037bdb7b0f25fe9a2e7528d0f952fa	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233845374246413342383733424137464231303038454242333644423439394231383346384635394135304244333630384542343342464544333334364231433836313636454343363942414146323032383131343944443844374643393830464230433042324430313046363342464237433845304243453234373444313533433044394541464131354434433342323834304130324534363631394431324632313543364231314231303637363638453442444241324334384637434244343130323630344641464239333143413943363031383542353943443238384346383233314534433238323737304130463334413346394236443735344142354323290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\xa853d2dd4fc1703dc5d7446e46fb0ea20d575992528fde44dedba7922ad7762fcfdf574afc0660fb290da408f96154f01de7d47e22be6d5ade35e2e01c22ed06	1567655143000000	0	11000000
8	\\x829285ca3e697cec66c0d9c9d849f5810d30f274ce5d9df4c60a6c74fb962bdc51d51961677ef3b74e22730d7a896c37d66ddbb269b004fe4391dfb37b2f0f2f	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320234144393638353743334436434346454442304236304346453031393035314438444542423746393941344431313746333438394542343234463430394344363846443237373145434133433832334644444431373034353231424332323535353839394332363845333134373336423044353445444432453841333543464131443434463541334230364134344638413041343536313245364535453232434135393630393039344143343345393635443842354331333845324335423644314132313334323343343641424239393845384145353232333634314445373245303035414337333444463236314532313734443642424538413846333445463123290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\xc59026ff6a5d0f4b4169154132bf0c8b68e49cac9b5e5e5fc989087bf418ee043fc1a518eefbd21af6c65325e1a3559b43693b0ec2ed28994195285a8074cc00	1567655143000000	0	11000000
9	\\x4ae3cfd1f656f3b0335a0703c3175d82577e20596753fd63c75a9979b2c91eedcad8aef45e25d2d0c70a31442f396d9311aeec83dac6c8c4074acbeac88d7011	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x287369672d76616c200a2028727361200a2020287320233542413538364134394241373033454532343535463735463835373137314530373742433145464232313844373546453633353730333732313831434438314633443431463834343343353044383633363334304434314239464641323332453045383231354134353941344345373041433445344531313637344134424244394542344346323541343830374132303238354542343936373534353139303535343637453038414245393746383831454631373539313439303632343946354436343045364242354337303546363035464643454233303543424435333036374631364533454530353833393938414241363333423634454145354541384423290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\xa9000d495e66470a178ae0b59e4e31446f39f135d4dcb534ec02f3e99345b966ae2acdd2a8a133b6e04eb5c69c0867e32059e457e8c5a3a77b2e7cf5e1272401	1567655143000000	0	2000000
10	\\x0236a3518fca4230ded3023d1f63e9b38409ee2454749b2ed21718a64f64acdca7d63abc4c2e973975950ee16be02d442f2abe2c21f715559df12d343e4f9a16	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233443384232464130453331333841363742444544303143364643414646383043443236383346374442454533413845373434444533424242424143354330413339413434463935353041433745343942414541423438334345413942443737444434394141364135313432434232363433393733303046413730394141314142324142394532324443414636423034393833363936343946304339454530463135454633343037364234454436373639374141344641414143384537303530383046333530304346343345334543444637443639353345424243343841423136393837383538373537333939424531374535373234353337423332384633414523290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x37f63229232c5123f2ea372e5c0e80ab8d177280c15a055a5ce222d03d86f72977f6cb72d50063cdb08cba496fb89b7412d1c5b65342558ade7f66d7e8e12201	1567655143000000	0	11000000
11	\\xd1ca58241b3c6758a9ee43570238cceac94622299d3845a9e7203a0126fa5080f274fe3c6f920f7b89b4b9a7a2764414ecd9add90661cfedb3e0d48cd62a2bdc	\\x75fc3173a136c9fe6742e2b95580b41f83fd1e520374f5393069731a8f261725a4ddc99741db77acd279bd882606c582edb53ffbffaf72f63705ab7b2ac9ea5e	\\x287369672d76616c200a2028727361200a2020287320234132424346323939353234354245453441363545343144323841444444314645363542433231313434344444414438354334313443353233353739443033354539314645424443343343384641463634393333363641453531383437373244313335433445353942314436313132313039424444323133464130384635304444463232304234354239354431443938463743383230433331433041364545343437324330393141344635333241303843413141344235304339414638303136414331313135363443383542394345393246463033343933434544323146423439304632453231444637444141443837343343343238443945443041443731433023290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x8366940b0c55116993c23c88e2f687b03eb398b92e30b48578a50dc205809293a4b5a55f9bcf779d31b252d37415f2b7089938fdeba611c8267d66831f28ba09	1567655143000000	0	2000000
12	\\x9db470a73c369d3af6b1e6f91ff356c31c9ed3d2f840c98808b5d599a1e78eddd61a845e770e028be93bb2e5ace02dc37bd67c51ffd9302279148f6566428fb7	\\xb25ee453f5770901686d799847c68b0fdd8864e30a8411d3a7a3ef2afbccb75ce755283ee1a095e020a834b0cb0dfbb9077deb12cf91d8160e96e1236d17d6e6	\\x287369672d76616c200a2028727361200a2020287320233743374133413632443738303546434545394130393342444335373846303543384142354634373237363831394537354543444336394142324535313730424135313542414537384631323245323834464636323035453631374136343042393130333039393135323039304636433838423546373342433741463430343844343145313631364633314241413844453938373132394438453331323736353635363944384332353631333844324541363938443839393942453432304135323746323346434231434236413345303244314446423836423536413336433130443737373038313337374243383744363232423833463042453530394130424623290a2020290a20290a	\\x76afc5ae22d0528bd322048cd7e776c1b79433680e8cb01bdce137062364590e	\\x3ccac69fa614fa6c526fa49c749d23412e3db373b68346b3d5829d41ca555576006ba8aa93c6d5cdb7fa101575b0be118c04df86bddea6a25b725142492ef802	1567655143000000	0	11000000
\.


--
-- Data for Name: slaves; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.slaves (id, pub_key) FROM stdin;
1	\\xab65d6c0ddaa77d3b1d90d83fcdf86918da7339c92fb502fc718e39bbb7c873d
\.


--
-- Data for Name: state; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.state (channel_id, name, value_current, value_signed) FROM stdin;
\.


--
-- Data for Name: state_sync; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.state_sync (channel_id, name, value) FROM stdin;
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_progress (master_pub, last_timestamp) FROM stdin;
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_out (wireout_uuid, execution_date, wtid_raw, wire_target, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 9, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 3, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 32, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 9, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: channels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.channels_id_seq', 1, true);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 15, true);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


--
-- Name: slaves_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.slaves_id_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: aggregation_tracking aggregation_tracking_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: app_bankaccount app_bankaccount_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_pkey PRIMARY KEY (account_no);


--
-- Name: app_bankaccount app_bankaccount_user_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_key UNIQUE (user_id);


--
-- Name: app_banktransaction app_banktransaction_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_pkey PRIMARY KEY (id);


--
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_denominations auditor_denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT auditor_denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: deposits deposits_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: messages messages_channel_id_message_id_fragment_offset_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_message_id_fragment_offset_key UNIQUE (channel_id, message_id, fragment_offset);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (channel_id, fragment_id);


--
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: refresh_commitments refresh_commitments_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins refresh_revealed_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id);


--
-- Name: refunds refunds_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close reserves_close_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub, wire_reference);


--
-- Name: reserves_in reserves_in_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_pkey PRIMARY KEY (h_blind_ev);


--
-- Name: reserves_out reserves_out_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: slaves slaves_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.slaves
    ADD CONSTRAINT slaves_pkey PRIMARY KEY (id);


--
-- Name: state state_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_pkey PRIMARY KEY (channel_id, name);


--
-- Name: state_sync state_sync_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_pkey PRIMARY KEY (channel_id, name);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_out wire_out_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: aggregation_tracking_wtid_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX aggregation_tracking_wtid_index ON public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: app_banktransaction_credit_account_id_a8ba05ac; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_credit_account_id_a8ba05ac ON public.app_banktransaction USING btree (credit_account_id);


--
-- Name: app_banktransaction_date_f72bcad6; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_date_f72bcad6 ON public.app_banktransaction USING btree (date);


--
-- Name: app_banktransaction_debit_account_id_5b1f7528; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_banktransaction_debit_account_id_5b1f7528 ON public.app_banktransaction USING btree (debit_account_id);


--
-- Name: app_talerwithdrawoperation_selected_exchange_account__6c8b96cf; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_talerwithdrawoperation_selected_exchange_account__6c8b96cf ON public.app_talerwithdrawoperation USING btree (selected_exchange_account_id);


--
-- Name: app_talerwithdrawoperation_withdraw_account_id_992dc5b3; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX app_talerwithdrawoperation_withdraw_account_id_992dc5b3 ON public.app_talerwithdrawoperation USING btree (withdraw_account_id);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: channel_pub_key_idx; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE UNIQUE INDEX channel_pub_key_idx ON public.channels USING btree (pub_key);


--
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_coin_pub_merchant_contract_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: history_ledger_by_master_pub_and_time; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX history_ledger_by_master_pub_and_time ON public.auditor_historic_ledger USING btree (master_pub, "timestamp");


--
-- Name: idx_membership_channel_id_slave_id; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX idx_membership_channel_id_slave_id ON public.membership USING btree (channel_id, slave_id);


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


--
-- Name: refresh_commitments_old_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_commitments_old_coin_pub_index ON public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_revealed_coins_coin_pub_index ON public.refresh_revealed_coins USING btree (denom_pub_hash);


--
-- Name: refresh_transfer_keys_coin_tpub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refresh_transfer_keys_coin_tpub ON public.refresh_transfer_keys USING btree (rc, transfer_pub);


--
-- Name: refunds_coin_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX refunds_coin_pub_index ON public.refunds USING btree (coin_pub);


--
-- Name: reserves_close_by_reserve; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_close_by_reserve ON public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_expiration_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_expiration_index ON public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_in_reserve_pub ON public.reserves_in USING btree (reserve_pub);


--
-- Name: reserves_out_execution_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_execution_date ON public.reserves_out USING btree (execution_date);


--
-- Name: reserves_out_for_get_withdraw_info; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denom_pub_hash, h_blind_ev);


--
-- Name: reserves_out_reserve_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_out_reserve_pub_index ON public.reserves_out USING btree (reserve_pub);


--
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


--
-- Name: slaves_pub_key_idx; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE UNIQUE INDEX slaves_pub_key_idx ON public.slaves USING btree (pub_key);


--
-- Name: wire_fee_gc_index; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX wire_fee_gc_index ON public.wire_fee USING btree (end_date);


--
-- Name: aggregation_tracking aggregation_tracking_deposit_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_deposit_serial_id_fkey FOREIGN KEY (deposit_serial_id) REFERENCES public.deposits(deposit_serial_id) ON DELETE CASCADE;


--
-- Name: app_bankaccount app_bankaccount_user_id_2722a34f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_2722a34f_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka FOREIGN KEY (credit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_debit_account_id_5b1f7528_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_debit_account_id_5b1f7528_fk_app_banka FOREIGN KEY (debit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka FOREIGN KEY (selected_exchange_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka FOREIGN KEY (withdraw_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: denomination_revocations denomination_revocations_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: deposits deposits_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_denominations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_ledger master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_historic_ledger
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: membership membership_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: membership membership_slave_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_slave_id_fkey FOREIGN KEY (slave_id) REFERENCES public.slaves(id);


--
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: messages messages_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refresh_transfer_keys refresh_transfer_keys_rc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_rc_fkey FOREIGN KEY (rc) REFERENCES public.refresh_commitments(rc) ON DELETE CASCADE;


--
-- Name: refunds refunds_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


--
-- Name: reserves_out reserves_out_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: state state_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: state_sync state_sync_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

