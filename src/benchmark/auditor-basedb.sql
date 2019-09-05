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
1	TESTKUDOS:10000000.00	Benevolent donation for 'Survey'	2019-09-05 02:36:44.582046+02	f	8	1
2	TESTKUDOS:100.00	Joining bonus	2019-09-05 02:36:51.090922+02	f	9	1
3	TESTKUDOS:10.00	5DQY1YPC9ZH6KECB9SMVZFXGVVKSM23MVXX1V1Q88KHXT7993M90	2019-09-05 02:36:51.315804+02	f	2	9
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
\\x5e9aaf2eee417a5480c408e07ab8d9fd34b2ba38778b984ed57ffa069be8706ff2b39c970be28bc654a6618027307dc2af29409757a2706abdba7a275aa7a3ae	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6141577a582447326f35a90a44fd3e27ab1a017cbb4bad6e025660f427add6100d5d002210aed7bf9e5f094b0670eba94e9b117ab5d0b087376639dc40d362ad	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddfb73a641357d56cbd929b8b6a7ba05b9c5bccde85d67fec77ff8cc970ef9861eecf003c8312cee108b92825b54b3fda9ab077df42484b9e9ca1a0230004187	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ceb934ea809d51a0da1009462377948fd0b346d4b38adce5307742dc474b3531fabe466b2acfe6cca4224dfc82fc234085962f3a65e26b3776fe4b3222a917a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccbf85c41c3ca68df43d99b5e04a02725cb78fc4ad5b7a819aeb5312a36e5bb05bed4dbed617d6d38715cdf2c6438d9149f2f021f00ccb67f600cfba3e13f39c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x41e59a4a387d74bac6431f13858f82ebd163bb9e248ae297456c351e5472bc2584874d202bc05d7548a435d294494bb687859812034ed544a7c29b72b04851a2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6d0854ba40741f476b0ae2c21b728158a23f2b30d617de84421af01e2d6233dd06e3aa8408b017393d06fa09f82e498078024cfd42000a148e58805e012b0740	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2712c7e0f21c1e69f8c5c3cad7696bfd1082f536d530bedfbcb2a08bca5d99bfba868e89dd3e5c1bd790a87da14b3d2d67e93acc66e47d97232122beba8382a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa89cd7cca16104f44c4b95f61b063024d22535b47e72834f63ceb5c73f0ca85c38bed6524f1dd0e50a56093dbb5fcb0e6280d7317567917794c114ec415b02de	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x849abc147b17b4082243600acbadaa3d9728aae358ad3e42f52a25d7650e8a8d7fb29f7682e0113d2b0da7eb19c14a83fa5c218f1c6cb3c7cfe8192d2c5fca43	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xefb87091b9d6ba3578efbb60ba9b61fd3f963e2f55f115270fee12deb56e68fb7dfade4d68c05e3428cb5f70fcd30c6ee716fdce4f14bd61525fa6f4cd94b6ac	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x22da8ce63bceca6576a904fa0de0fa0c50fd761ac28bbe16a9df29d4b58a09310cc8d3ac1079bd383170bb74c144646799f33714c654906b035002caff6c8354	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x561cad270af96893efe45db4fcab187933293b96fdd41852129a8097cff97f7d18d3382fa39633bc41e7e9940e25481e8e7ce3778018e1891c1d9e1bb7d39407	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x763b8eb479ac04c38c96e26780be9f26b80475c05b672f90b9061b5d077b2c730de0b5cdbe77c4f704e5ae21ce1e966c139a85959d423c98619e4e0feb385625	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0c1042afdd47e8dc9cfbbbc059ef1c7facbb22ce4814ca9fbc47a351d2dd08b2c4351901bb2ae8fbb815986ee1e126a8122edad8fc47f922ef2e5666fbea0aa1	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52bcb63a2c1c59a4dc6dfdde6be377723187e65ddc0687ef68e4c6aad332752aba8ef1b133f82a467760c8651a3ba82009a25efb72a8ef62f580f59749a4e116	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d86485b17a51b034772a39af8404200f229b0b6c5c1ccc9d3074180c00d9311ffa701961c7d3e60b29129b79159f4e7b62923a7ae853ff28bf0b6dc7bbf351f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6d9a462d5c2acfe38f717ab82f24000db8649666ba15f234a37b53f33d3b4cc98420c9500cd8587693f4b9c1d7f64cd352c204a9a677d4d3159f055c39dc8da	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08eec2bd0507c4ed470758d2a051edf53d23f89932757109c340f8c13e0f7687b94c1b79ed00e9e63727d71a3acd8a0ed8bc15f39998cb220e3736f691e26f0a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc01b6f347ef306e3ca2b0367422ab2263432bcadaadc89a58c9b47bbb700a7becaf19e8f0532d400f7239ee4df6f3b9ed5759b8154fc132f3dbe52488f2ce9bf	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd77d53a9e986f37ac650eed52915a8939c61140086d3709a20f9e723f979e22426e18c2e9054a1d2d1e98e252f4c74604db9e9e0b6fa92361cd94c9d47bfe9ac	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x428a64f6fe91ef10d73904cc63a4b4bf3f6dfe1761554bdeddc52b51a25003c8d87ca3da027464fbc95bf9b99f01d69983eb06596cb93d56590c045664971f7b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a52dc5af8605c2745cc26867c1fcc1978e8c9af932ff98784ee7096edf1f041d5cc70c838049edde80a63c6dd36fbee02d58ac32ac82b564f212f295db04817	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xce30652f7b8ea47e082b54c4e0cc9b4c2e39c4d081430abc200d412d4fe1ac90b4431178a82e95023bc8de831fe0d2f31fedfae866165a2dee1a73f24952a08f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31ab15040df6709408e1707861369c90b8c29690e94347f30533b47b31c8ff143e9bf2a68c2f10fe62863ed76184ad31cc82eac48a770a147091cba5127fa77f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f294edb029f93fb3054a1eab17e9409b48ffaca61349d2e34c0e100e6d22b034961ef10c295ad3c87a73bb6b930efb0b555e8b36d3e3461109db017cc89d017	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x417513241f7e92ac1a61039cc50e54e46c711507e31e8449b9a3125f13ea2d2bac7d29fd16dcac7e48769fee22b67c5f200cce62309a45815f7dda48e16d8511	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab78932a45c1d911f0e096bca6999abe97c64aa8ddcedcc30097121f1a9b232e90c817b0eb341a6c171c6235b8b4a613c10d0ca6c7e06d5e5627ba01d79d61dc	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7456b7ec5bfebbf109bfb7cd65f297a460954a900994701e8f72b9f35ef00e922bfb1b81dad5c2a97619f3a01b1855a891915e188f290b3339f51e775513047	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf5f26fb4febcf7d23c75a962964f2ac1118555d77562169a1f9613430fdd1a248f29223505798eab57f96ae5ce1fe305485c4bbfce043a92f3fa54d67c6c8420	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x090e2d5ac1314131a6decd525654f5b7f57fb0dd422e0cdf6cf0e660c4f7da1aabb8ea7b4faf38296e30eb70a3dd9f2c214be54f975636400f23406f4d6dc032	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfda42fef3ea12d78b878daafef1aa093f465a590f5802f5bb0216f3d65c9cc87084eaecc99a70fec4aafd11925cb1caa3fc4da520cbf3008d7cf645eaa579779	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe6e47b3d88336bdfad14c773b7e1a6ce9fa1aaf034ff609d9d8ac67ef96060b46e17a3c40a6fda0f45e10520f0f16a28060423b331bada7625d4f67560f89282	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0de7270c1520cde62ec903a1cf6d1eebc53feb9433a3459cd45ec6a1c42461ad22aa1a95d1e8210512a898f5c7c14ba79d1658a831ab6df3ea968e19c1677fb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24fc0df15163d95eb80f3272f9d17e0b8cb66feba4ffe17641ca894d643768672b3f6f643aaadfd920b0620f51658f28694dcfc41bd1d9460257f43f5c8ab3e3	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa735503ebd35d938e6da7f7c50cc41e6da85ea36fabf9eb03aa5f98fe54b93bb367e53582baaad9e075b9220491e34b0d01aafeb128e4c6690241281758ccf6a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x22f3ad9306cc7ae45ee3fb8876bcea0277bd76766b946cf412848c7f4b0ff27a6716c1aff2c22038ec2ea830632e58255cc530ffc885a2183b63590cdce52cc9	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7dad7b5564c9de0e1c8010a9e20aefea1377b3eb42989a9cfdebe168f9647f935a4f1a710bab4e242682e6c3cf27dea29ba5c61a9c0bb2e2b9eed7ef75db18e1	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa10298d133920ca46281e7ca934c6684d764ad94f4c0bc83ba067e71cf82d12b14bf380742eef79edba11b4b82711ab7ba61833f73bf33cb277524ff49c28a98	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x13097577adfec55ad036a0d99865cf3442e5d6ccd993421a3a1828da273c327185f47b65388056f73bfb390a2395d2bb7f87831516688a63d65cbd13ee96a283	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7bb9cc5d97888946f20ff90417caf18ad2e3ec73e07837329b71971cd56ca710bb8d6d8c7d6346c19301421fcebc1edb9301d2cfb360fc4431b8e12008c2a331	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcda7ab683e4c6ade43e7fbacede05f021dac181d601f1386f008ced270dec95ba15d90af1b6fccb32eff6b96ca705275158ee194ba69b328d9245b6966e78b75	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2ab95ce34be2f5522b199f2d01850f2614c50f71e2065776f179818baa5256dd4390b8a670050604a3d94f3af938b932205fc7158801d551234b3f9603dc7017	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x218119a5caacf8a2c8b67876ff61d53e1610fc25a6d57c35e571ee7df0c315594295f153f40958e2c29b2bfc669314287f44c7ad6b2479b467c862dc769cba28	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3230d194338be9b89a2de547cae41ad6ab24fbddc55006980383836dd02c5bd402ffdbe755e722f6d9d1884ce35d59d498dfb1da92f7941984c9ff3119040554	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4bf43d3c4fa4417e5adc0c9d8a55b07ed1bf0bf67ace71861805efb46ff791f42b4cb52068f653a7be74e12ff6bd2e505dbb412d6e8473ed3487831e84bce7d2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff464cd7a0ce0127c7251e1bebc9d5dffe6194ed423917e54c2946ed351008bd43c7d7a940fb62f6db5a3028f55d196aa72be7b294d9572b2fb8606a6fb284fc	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe323a2adcb6cc881cc8a38e3e66bebffb705502422ceb4abd3d65f626f21b56069aa1d0908ef04df3a5191afda9dd10697e778017a259d2a7d549acd9b8e843d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x57b921a9d0677a33cc6bec4fb99b85879c20e640a3af19be0f21f6947826cd99a8e1decc3c7526b6e203ec00f2eab6fa7dc7159b166ff62300679babb7996021	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5434805b80be004234a85e36ca734d2d5a83803598d8eb176ccbe46e242449de5456f2447c1eac6d068db6cea1aaab4c8429478e839c302261c340b3fee5b266	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5c56a178b43b0e6ee3d968b31a4732da184977e301961f1586f88544f133d3d6f8c0deea3d28a88b6282cb91a064f8a92d4b2a10b9f4267558b5071b7140bd39	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc444e2c643cc3a4a93d59185b35b57dbfe7a24297b4f6c60aaf31c2c25c0df4e7387f5892e72851abb2cea4651786a71e127167dab8e6844299b9beae89cb80b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4c24608102394b00b50e997a047e07cb3b1c719c23d64f0e9dfbd0d87ee89fcd33c84d7a3d79c11af7c93794de5c9dc327cad7f4825d574d9d508afe033afc49	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe48f08f2773b5322c8a76324402f97f9d945cf5b5cfcf3af1465d315387901160a3998a48cb4dc15311d55ec90995165b851aa1e62d262959a4d8c4f99f46579	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x786a97dbb321b15865fdd200d2f0557d2289afe671d47cd6fc7639a3afd003155d759ff79a558267b06633f5575d327df14a40a553157892a0b45e9638ffefdf	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x36ec682d3c11cca1799ff28d96aaa777a49f4d3f065c1695ec56a358b8b46e36d463a2b11980b4e0eabbde4b9184c424ec0489b25069cec87152e7e2e9a8111a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0b9fde028b7f457c851f72d4c517444dcac5f4dff11fa5c6f9723351a155586379cfcc02a7dc6f03e75b180042b1e2eaa12c7e10af740aedfe16deb0b16861a9	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x466dbbd2b80d64e174db3adfa004263f0b81c67d352f451d996e23d3fb057032b5e241e6f422936a9d2df85cbd96ff468b4f9c898c67bc0d1db6138e6d25cceb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8b98d9093aa533f8f13baccb18c287721da552c26f1556f2a043d93eeed5607c9effeb02b3a47fcddb693c6c480287a716cbd5a3624a4a575747c5cd6712bed0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x62ce93678dc71d2ce0bea8ffa0940cbdd8a103d8cac7485ed61ddfb847e3aea0f6abaea6554bbd961b55ab33b89df8612613e53251dd88391a35b601df1b30b5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x66ba7fcc59a27e740031e50383e128cc5e97d5fb2241a0ce46926d9775fe30c18cff7e2404c9cb100314b9b8ad848801eae72b145a4ade54845e73c00d849280	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x26f51864e1f0be5ba6b65af1b6fc9290edbea9bdf1244454aa90da785877ec9ab118e9bf395e9aaf594904f2a28ac9c3f37e62c816fdef8a49a071707d5b850d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x28926b6f2b6a535bb7300ba8b9df7d785dc8fb241c76340711ac43a1aad1d214535080e83a40699de29a81ee8ff82287dcc148a5970192f9df5a56a98cb38810	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6e93820702f8d5d7fd0bc683e036026e1206f7e85a4e09c466819cc5cba1a42bf5de510f92dbddb528dee2004f3afccf936f161c82689469747735c09daae40a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdba80e719379cce1bd802dc341a97ba859d17b47d30ec0c1cb2310f15f9b1fe79b79a47dcd8aa4a31ca8e0859bbb0845cf35fe8d6d1e922a3aee03d7bb66f1e4	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x09702e175943578b6a8440d212c600ef93d0e2c568e545c9af1b2716d73e3f96ff6b4d9494a81eca973ac5c43f141e32deb868d7de7e60e754f0a2a0842b1099	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x58c385b1a09d7cb925dbe71dc1526f2321895739b803294d221392f301701634dc28f8abbd8833220fe27606a078d5dc16541e1ec5f3c6c535439fb3059dacd8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bd4576b9e58abdff24e0fa89a3178b39b60e92e87196febcc9e43057b519203ecac7a47f35817393243e3714f96c3f632005289b62d7feae0404545e8855238	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x861ac77e2b218e655057df557b90215c83e5687e1f4a566ae11c2acf290cc03af5655e17ae0a275cd23a7d910d10a023c20a674c30fac3899bc1a6a64bac5618	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xea4c70d67aa4e1b80b46c14e2aea61899f9ae151c0cfc214d2319c17ee7042ad7ac4f672975fe25c38ae66f0d458106e1d8202b2924f4be6b18426c67634acbf	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7a2ab4af164346c9300d245c636e478901c6d03306217041958be31b54f95609383fe5596b4a01c3673c0e644afadf1df44934d6c1e774708078e676522090c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x92634d4bbc33dc53b7fa4a3aff77cbf7c0092e128ecc33ffd46913e7ec4954207fe424550873da1b111396e63524f2747d52133543c3130c683c75f4b7916977	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91e430a383bc737ff6fd076badddf20558e0fca32ad0b2a6363f73d71abbb468908cf67e243d6cca11a4545ffed6f7694f40e27954ad616109b7a6a49cf157d6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0b18edff0532d555f434e21a656dfc3c63cdb3109694b8b47401a4f8730b3cf4e7a8c8c8d39067a903e4d45e682e22e0d09eee8995ce65bded2ce019d94f9add	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7fe709adb6adf71f7a2a1102c3974e152c71964ee6c2c7422369b37d58fdbf779987104b62e2c53506dd873b14f78e4c1a877eaaff9daa5f51a02b75754224d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7104b987358728c51d1641175580648118a902fece29dfbec451e23bd4d4914d1a240ff0e1b3acc7193fb8a238e8aa9882e417955938933621cd14a3ac1a1cba	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x755a3f07d1889a55681d8f77807c4cca0f1d0142601a306678514a1dc7c88552c1121ab1e5df4f6663f957cb1a453dcc0da1d737e0934e09dccebd41627d61c5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5cb74b7237a408b409c2b83470bfa1e7a17ecb1f57cda5c2a84c31c1bf79a3154de3d65e4f15693240e6fea55da7dd3e5575c3fc9ebcafdbf93586169ff4c507	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbab94c5a8d7e90167e06cfff37cf768082197bfdde7cf0ba8a379e492297ea592ee992334a01aedce2e62ebca8d526e529600aed7143c9e79e8667841353fa5e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d68cc87070248e403e9786823af72f8662b5e6b7403b7df7a9234c93a9443108aa4a51db00611e7309c55d719b2b304b2db25ede415f1c6113aac09b71bf3b9	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf746db73ea5f41a648211fa8b6150dedb6e7825d79127db7b45da54dfcff04fe7c65053d5937aad1f06bdadb0af897b8dcaecf1d1d148bea2e547d64d372cfa	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbcd66d65cf55f2abdbab99fcb9e8b79b4fa7f1733fd42cbf42249a0f7a86dd6f7f77106318e539bc5edc98d36d769f6e90cd89d190d6aff65194a975472e0d4c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa04a447b4dfd8de653e901aa10900185cd906307a7c2ca40a21898944e29a1e337798c5b0ac46db3abb2921cbc9141e7b501c557f37236b0612f1a7877420125	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb869ee587ff2daae4d73e610098e26e83ae2658f9819f7898d8187ab238adf1d916baec93a0cb45d05e6f3fdc88ccbd486b6c9d6c8e465b04c4c20d8981a3117	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbecfd846fa83373098014ad34497936de83e27c11c35a4134a55b913325ace1abd0ac38a201a32ce76d56e63e68269b05d4ac984156bf455b6ae9cb9e438ea96	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4227c66e6f18118476bbd2b032ab22ad2cc850b1e74440288c49b704045d82b6010c9021c60742b2173fc4f37371ea206fa267786b33902b9a95487de0dbac3	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d484059ed7d8082eaf45a0645c070c3efcc8e541c48da4415661337c8a37ee9f3eed4d2b042d4d604eb75776a66fe2dc8359e3193eb7e3acf3ad3ea203ecd0c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ba465fdc560531688c9f9db371d80f1398681a37d16aa446cdb1388920d40fe77ceb3597bc6c5820a67a458c06bfda51902d503e488025f4de83f7fa6c51c1f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x102bd0418058c1d548c9adacbcb5e74232547461b2c306e742ee60a9b9ddd9f549491d76f963845e76befb965e6b07427706264162af537046a9294fb379071e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x12c689fbcf86aabcc93d95c72e54e538f56eeadaac52b230ba922f96df7cc462c1830653980e332502cb3d149406a9c81987b99229b120339b6a9d7b2d05d5b2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x31461b236571e46515a80f913a71c9839f73ac18b1df4b1016d85d13b1e8f8dfc5274fbfe49f799a6a6ffa40ef9a17227e7829aae0ebb25abf21d84346c584ff	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad158522e4e1a2525e9d4996ea0ea01cb1b5d49dc955177ccbe1b20c6df690cb92cc8cff4c79baa4e1e6d1c3cbf4dfbada75aa7cb95966bf8ebf4057926bec25	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5ac72d8da5162a60390ac27e82d5b465d06a0a25d9606027bc932e9cb77e8a27fd09930807e9556b685ae94ed4f6fc94b25d2a496f180e8dbec3b2d178bdb25	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd015111b14bcc49a21af68d65603d4e80c62e50821ef267d076c5ecf02b93da20fb49bb672dcbe8a9dc9e677bcd2de827a55c0605791d8d77e03fb49b7d798d0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d5f91cb19a8bb4dfb7e0939b7cd17b6b0ff5548b17a06ea96146e27ec2d44fe805ab9c0b49d964310e08b7ae41b4d43ab055d80facfbf1c30f61803b30adf35	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa8dbc992e6694a8386c6ec414a945d6d09af9ebc27120cdce77d3cda3df62cc253fda73f740fc3401f6f2f7ca600d7d37dd6ca7313a8a8e91ca9b00517a0219d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ca4058b4153ce5def75faf6388963d934a972f46f2c08c7a5c974c6dd7fb819daacb6295f6ec6bcf4cb16f5819e4c9c7ce11c92ea7a97975a3e3e9336fb1194	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x278179c5174a828bf98581a0993f3a1c2a7ce8168346e9d2d655527b364848302cd5cc6da2c64de0708ea70f0ec823bc08855a1ed9f3d6f45ae6073cc50ef48d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6ef696dcc3faa6ead76865a414e16c9d8a7f86f195f01eee85db59f8a7f1fb526dcd26d5d9df7b13f9ae8740bb9b4d61930d13a2d1ba86ad6c4f3f2080aa8b0b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x833d87f2ad05067cca2f1cdefbb7c1f5a9828b515228633e895e5b3d6a1b4554f7930569cdc8d8cf85dd295970e22bbfbbc4a7be759ee9f7ffbb6d8906f85463	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd617530d4373ba610abaf384d5decd6d56746a88ecb85ac89892ac0073cf937cc4c7eb6176a0c13bf8f38bd28644d9e24b1863e45c471abc5eac832215acde37	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb993f4fe55d966cb9488d1b7cbcb193a858089f1c930ba7d1341bedf85518020043fc987e2c68b00f95c2ac51d27738cbfb0749f062a1d2ea243aa1079d9e896	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4fbc2877d77484543e24c86f7815177c8862a7db4bf2c6d476e3f036e61ae351bcf89d5fdc6923022472f237e62d56e38e4ae3530efbecfeca76fcfbb491d6a7	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8214be70364a7b644be9ab7f08af3177ccdb6ac7da9249ab86af2610aa5af995435d97ac6a4a45c4116fc386dc8509256ba223909a4b20bfd610c05c24a3180e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x54c6fb231289be7c9c73209f01e0d13da007360bf73c92608d0f5e5c6b80988f14f1fec6dfbc54dfa75af17e43e5ccc3dc9fbab20e69f5342b61f5b703e73b3f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3d42570c328e938d502b5785ecc0eb3debf48dd8d811a86a6fc5f9deefaa1f17ccaefaf41b0d72fde11b34e0225497b2692a1f9c2c9f01d00ae898d42be6c40	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7b0765674b8c3d6582ddd881d4a5b157cf595ef9b3e45406e0d51829332c89a3242df750c996e1d963d56d43ad2b6786028b1710a8e66897ce75ee1c03b07b91	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a98ccbfd94946aa4a1e491111078e31e0a339d81213cd007e999c54462832029425aa7c462c187b61e5942bc2419993c64053ea988824132b253f8f03b55503	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5d415d0c65c5eddaa02405adbb72f9c3f5c1778c0a5b6e3b6d2940547c4b13904e5cf00665a991c183eb3fb1f68873f4988cf37702d2143d37105f726f714e7c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c46fe391dddfe78d9f02bc4c14fd187c57cdf7e22234701975b706e5fabe6aa35468fc882238c041d3516e257314ae698f23b52bbbe9343db670f5a84afbb26	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x249bc6b45c94275c647219c63d79eeb3c77a7142ea849c6065ba3a9f5c361a5a1d6f3343c91f453b55a9a37ba0383fcdc01bedb8a2eac9642bd5842200b3cfbe	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x09acd83e339e4edeca7a416c0611b3b106e4ce878b60e2fa17f325c1d2541ee954c306177b504f1202f6ab2ec3f0e759a90444c2d20fb3bac961fe172b67dec2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4d27b7c712c1a601bd436bdae242e4c20bc4dae2c3305fcabda1139a25df11e78e87083a26cc0c953e884637babf1fde4a8b5b2d0c19188f0bb4ca1047064f0d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2be663da74e97230e302a45c32235b57b63eb3283126620ed17aa45f1b2293f585f6364e19796b773334d375e9b90fd970e083c1987361f14bc7cec49827aa4d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbf8fd2ea119da891a2e4bfbe1540d68bdf60297bc1f48e4de5cbeade3c67b74bf82d0c763eb8fb6a5c8f574e0b60249694361d2c05f6fa4b9d7b5715b8afc766	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19236c6a7788f99567483ad6b9e9a06fe118e05674c592e02b74d7a810d9bcc0083fdf2f22b5a81be2bdee40b29f81d179191c308a84cc000afae6fa74fca271	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x18ab20bde4fba0d74a3b96d188821317ad251267bdc147bb8475385bd90e80a4e938c599b48de3cfbbfef9499727dfd63003b8d55047b9d0989162e6a16c638f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0bc0fa889eb4338846253421f9d06b2ce6654b72c44e43e1f13bbe2bdadde942f8ab477d4c8d98d47cbc24ed72c1bb85f4d41e337e99b390387f66ec78df5cda	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x901b05334386919ad6e47838cc4471fb220dbca3b9ff7669ce64a7694464d9528aa07b1d73a8cd732e46ebae6fe17f37b9583c107b8a79091bb5c6fe3dec020a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58167482f5f58ffa0b970aa158a9df48dd81b200e0d604dc1471cd3a5eba9fb442d598c42c984c4eed93331194a4b5082c76383adc526a8a090c370775ff9f11	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x06ff54558a492c204bc914360dc5dd74ef8389ae43409a2cc6c681bf9083d1d91296a1b85f0b3fb1af0265fd98edc55f5bd0ce976f57f1106f4e18657db73862	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99e20e031bff5fb4e82237a89a64868c3dc4bbe3354e8dd5d9bd287cc6d1042c9ea6141bfc3954da6980cbbb46fa54bed0f35eac7e47bf7ca0f8e208f570a5ce	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xddbe76ed735a2b4738e9c8a18a96f1dcb914cabaed74158643c050bc4d061f24d4007e2dfe179d41a4457ed7ce0b00c58b6125466fde2860cf8a39a79b9b0a72	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x05f3de4c6213fc00fba4979a06d25db436fc17b9232359694d02fdc114cb3cb669bd353bfe14e722870588555bcfaa8300377da966738ce906d3e1c780dac705	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd43dcb4d6dfd34278f66d79488a8b936827ffca2ef9102746f61538a90168d940bf551877ebae4455a6a654dfbbbeef95cce357f74c032181aae2c0bab101487	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x387a51ee27946aa5c9d0811e886491aedd90b8a6bf2acba6d9695f9daebcd9aa5ea146e01311d82de10e42841b4b8af92632955601a79fff652bad79b201ca49	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa5a362c072317ca806f16bdf6d536cf0f5f18188d334e4ec717ed6e99b3f17987314aa1ccb7ea8315a17f6383952666979283182aaac6a7e152fd046247f0a02	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9d7d2f65c7d22739dc8ee3c45edd3dfcc3591c46332f0544ee251a1a939c4e33cc4e1c4c56a5c9d4dc30230b553e03eed84e2b379270f6a92e53e1912b97a542	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5521b0ced5dc5ea1e94b18271e6b3fc7e983993ad3d20c75068067054daf66934103932332ccc6a8d748acd22756091d856f1e321fe847b02415d96ac354576c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde8e36e0a69f0ae7331b23f776f56cf98d96680ea9c31e478fdc13ec615b75ed90d5228a7d9e75fefd2037608fd63d810d96292b34a6dc467c3ecdcfce3173f4	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa113064d65d69098e49148d598c90915877ae7f0c2f3394233ca9fba9ba655fac38c9ec66912e7555a71796f442ba2f1667b6008fa93077c4aca2268313d41bd	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f08f1dee5751413eccf20661f9d35b851ea51d1d2f11ba299d25457576fb42d110470c132dae9efab9734fd4e41d7edcab81837e91dd9da4f5aa7a35f0c2c4b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe6fb8b3948e9f92b43079e94a9b77de96c975b013c55d43d2daf2a59cf6c22b60be410b45ee4718987131376060d3901c01796f5e7f46c2d02fbb0d3ce21229e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3ba49848a824fba431dbb8b42828a3457d7009605cce13077d9309176b2acdfdd2764ddf137e2795578024771c175c780c1719cdfa6664eda20ad85ea2e27c8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa85305590fac46365b19d0443c04152def0e1f247bfeed76e3218a3293b5b9a3c537a7a44d70ed5d20488698918818163bf8cd614b5c2ecefa80efa0a1454f0d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde74179959b245b0d39516ac918a9e439b7987b3dbd917c9a566a025abe715fb68c8643a4ddedec184b72e1b5736affcfe1a0bac9603f9d336d97ad016af1359	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ea70bb7cf68e371787c4d3ca712f41de204888ac94f9b4291c4251aa96447f3f9523b40d1727670d598dde5758090957cff2d164706c671550b2db925519197	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c7d5da360e6ae87c79a386ea2b987200b07297527325a1d52f127a410b9bcf538b6b8ea3de32db0a08578d752e07de3a8cab31c5d1bc3a04af0dd75be2ea842	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0c73b4681fc37ba94830b103abd3691a6932d4f2ab24a3460b9350b280c1b40cc03f99da9fb7a8bde13f33fd35f465d7ed75077b56170be81752be2b8e516407	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f15da518947c38db7aee58654c3b4e8393b71d89a911e9374233051fabb198880aa4ea0290f14ed29095356fc17f47862c3bbc6603e9894f50bf513fb92e6e0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x433e4b408d5183259e5b92e02a9043d4c8c07d19a5df4b127aad91fb1dbb7a4f42ddd55e0fb5a80c0691b96592b6573287e910d7aa1b196f4b19627dc23a2cda	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3ca1d1623c76687d8abb40c5ad457cc8d937fc40fe494e9cdcdbe221d7e9742367388bde8665ad2ee7bab7342508f6cfd5d7d305138a8a81aaad4086caf211a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf04e0d6ffd24c8138da44a50ae0ddffb035ffd1c8a73776c30e61ddbac4d24c9e1766856170a35257bde8ffcac0d73993693dcf18efd710f19493149d498c6e6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x70285237ce254e9b41a1a2141e487c1e479b00b5cc8fbba853fc2fa718667998b32ea844b5c3be05bad6fb7a404d8bc8e87a5167ef633e023fdc86b826e16d21	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa096be62c3712d96b9a065b899444f11d051137a93a2c3e6ec9445c7a1be644ba441b4d92e6ee9e03fb3495c37d8c289fa08a0e4e1254ec86f4ac2446fd0e4b8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8df6cebff51dc665af6616b3eb41da21c5fcd4aa43e77af2d0792aa9888a10196d5fa8675c83153b9ceb01ae729cd9050f9b0da5fba157314856296d4d395bda	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59c498757db82139ac73fded3c7fa6da92bc01235e2e9aff40d63e229cf65da5921554e4d557bc6659155c8cbc9b6c382db0dc9ebb54b571198249f4e49f3a86	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x896a99115fdf7b9d0c1b9874a01cdfc58e0ea8ccedadfe5565fef4359fcaaa7450be2ed7ae0799da57cd1efa8202b3617be6ef23e845b8d9abd29a18b95ec312	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd925c13144d9f72b910e8167046cc84b28bc201c260e9173fbc7eb28d05863e709529ddea9a4eb25aa57da012745a885c3f65ef87a24b2913a160a7fade8add0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe124f07b824e6569e7db7154a5dbb6a82541d278907162909cfed78ffdadec14cdaeca20598d4e7330e35b8ea3e6a158e859870cd5eff311b3221be541b15fb5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf6e0fa2d4ecf2ff33c1f1e659bd87cc9fb95204c44a61c8e1559e337239e444c6cb82e425a8196666af58a22dc6197236d59ca1467ddef7ff5fdd255efc20fcb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb82ffa47134b2a1bacfc1a0e1019195066b0a4ed815a9cc7cf4510d6d53100922af7fd0cc9bce20339615ad968a1bc8185a16cc5b67408ebfc4e555df30020a9	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x93c614639ae5ba3fe949f29476c0382115b49bd18e396f6946dd7df42c7c345e0b7ae5aacce10dbcdc54f65127e1ed2656c0631f9240ebbdcd4971e23423fed8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa0c3dd16a22536d1309151395e6a01146089a57745952b7db13df987dca32f63043217d89a1541fd0ba2f45fdf9d4a17d4a45af038adda535d943a17eb4b249f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbbfe68e1b5662ee1c7be5f63c9de02a7d5afadfee1d1844d2bdbe62aaf0b6ca714f305b6aec290204057ef12c276735ee93c0aa0c61426bd6db41d0469d837d7	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1e0a10ba1015adf4cd8ccc0909454f8bf87e5749bdc1d0d810a1de3b648ab1a0256e249e556df7281bf3dc9ca20735e6cac1021e7a631737359637aa8efa2882	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x49aae421c81887e4e645f63fdabada5af1aad330f50d3ccb7c62dc6adce42e48541c65bcf169162bc035ee5fb9adb09bb6604df7163a5c6ba1598ccd9e5476ec	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d44fe3c89a384577a2b514e38f2e02cf8ede104ab74d04a61bcba2083e6b563bd9fc7dfc29e77f1ac1fd1e231449e5dfa5e3c46e8a2e2bf5d1dffb741bb670e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdf0f50d7e22eeb55a269d9c260c68e90f8e724266847b493e3a5a85de2dc0d043c94d9d3cef7b64d5b9c7f8445101af288e9b38d07d5c9acc1a9d78186929adf	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf3b9d5fa2be3349c1bc4a58cd0ce3519ef3fa956277e210390f84ff55d35d5ee27a569f246fae8d1d45873627292c8cc8dc85552f664f67289b8f3e746ba28c8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa8607e921fce81eb3ed3145490400355d80bf17c96606cbac700546525d3250cfffd5b65e4a0715c17e2785eb9cf1da955447c73314b5127d9a795d89d1d29db	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd0f603ea4a871421ab55b7b1418c64233f84f296d574bae958a890c531cc454f10b50d2faf383631051771ef5178eb0645fdf48dd322550eef11a97e75e96ed0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0ba54bcfddf26cf1cdb440089c2dae8432a052d7dfc88af848e30ce8480563e1bbb28109bc85748837dbd2efbb50f3b2acf58c6df9600c64267fb440017f0a12	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe2b15e22b40cac04c805327a71778adfae8f771d241e1c48f117301ac5289c3b1f870777673f5a72ae205f3a4b009ccb1a28cab4cd6590181cc7bcad8923a1dd	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbddcae82f60faaf448f4e2f05e330691cb29f8f40705d01ee744ee96eff93989789b30c29a040e87b0c968f1e539b0b8fddf1887ba14d55bc6e3d14cdf7f8ff5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6aac86f2f844eb38e3649c419f5739120d5fc105c6d57a257e8921784a18a2e62f799be812aac4a3e09ff6bd3b8ffa2ccd1a79b3a9d838d38b3020a2edac53ae	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x43da04a446fefba3569db2674b90ad017d5537d944edf84b3ccf253e3f0266b543b71d0fdac116487854d063eb46c9c1560caf825bfb30b1a3f12ae28b4787a5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e82d8b62fddd6502f28f2d20ddc70242cdc2995264577856da3ec6a46283eefa3aee17bb0b8bd6273867508dc440178ef04d78c5de92e3484993a01e51f0ec6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe8fb52b78e8c2906334dd2abea35de47763ef8085c3d6586a5f9bac19b514f7df4366738226281ea772d32fd7e116bea12252738c7c07003e1b97398d17cfe72	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8f707ee668251acd2c6bb8ade966ce4d6e9b4a0446e6b9526abcd32d6f46584a541cb4c80736327d9c46dd6a98fa6b47604fc8aad01a48664e988537a68cd326	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x768be599350c66687884d1d5cf859770e035d77c8945a348b0dae873890b3fa96cce11dc4e644c59d97d825dabc9705e6f5707882b7e18406b531cbba83226aa	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x20fb6e6fb8fa95d41bc787d4aa0505ee4e5cb76618a9e1e58642d68fbc7a91fe791c0073a2d94206d11d0d564a3da91ede6acca37df32a094c2ab8cd0c480223	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x6e6360f9f29b170eefb1fe0c4dd3b334de16a9b9f5e1c9c6645b56a563509a200e488f0bcd2afb6db535cad8f36307f23dfa97fb51e2862ecaf8c2bffcf96d29	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1dfed1e1b49ffcd1d90331a0e1d623acf01756112741cb218917231b1eb03744a00103f6ab51800ae8a23c95f2233e406630c2cafe70aa8b443c5a7370519194	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf0fc109d16999379ae4ea7627a949c5315ba60d9e1fdfb4bd9947db3ea7daa3a9791b5096e0a0ad3480116b4fbc6fe1d61858110342498e641274ed60b319c93	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x42ff1a54ee460e0105a3542a629ddaa9b733f5d7d5e7d5177360df8ec2a869cfd9307faf8c0ea051018e1cbb4fa3b38bb14e3c37adf7d469ddaf8b02a014ed8f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3e9be67707c60845d3db1c9cff5bf88554cb98bc0d5bde0f31d9b87682173d5c7b3b69b9ee8f3bf3bfaf3b74a09035c400ff5d2e363c9959717b6a0fb82a6c1d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2b4f67fe93634e7529499c7e6e3d1b2991b000fb002af42b9588b812d687cbd45bc676c302c2f46a6797002358a585d3a44fbbd90322580518934eb829151007	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc11c96b2847e94a080d58bd08ee3e06a1bf6ac293648809dc2b2ee2465ad901b3ce21061dccab3a4517873473aa58fe62aad98bbe115acc31efdfa230bbb7c08	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x57a143bf09253624b04ac1457e3d27489efdffc2aae955f321db7137908ab67b8ff5f4af5d3f01b5330ac0dcef765da61a335318393d07adae80e72484f94053	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa31c777931ab70695621c3b064927d803a731bbbaaaedc5463703ba060f28d6b43840f9a02bb10cc21783bd66fdc678c98f8606786b168def8c1bf5a0e85cc70	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x25614d75b56b62d0d1291e5395302e86aadc6dbb94ab7fd54752eea0aa585dffe839fdbf25f424ff9b60e8f62736b1edb9978c91194d377556dbb6ade96838c2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb94db4e9e0616774309bcad003c4f0e2bb4400643d0394e5319fe3965d08a161dc54eb7f605f8c01a374c6805074b6908e692d3ef46963a610220eb539c3a736	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71b23145d577d07dd536a9f9d757d6be05b594ba4a3569f6df9b7c9de6c1106f7689d6ff9c485ebe727124fb245409db4a43319c599afde9f71e449ebf6a78be	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x63e0d5b18fe3d8579d2de8ac7b914f18a88f7ee68243389377677e60f69a749c3483083f0c92ee8c8c0320d7d68595eaeae999bda499cc1c2b15af86f6a1d7e2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4761d64d75d52971f1139ae3b4ec923fa582a3d3cd04302fc699fc30b0f54c54657bdcc06e460eb814a51517a921957d96b6049679c24d889fa81595e35d8097	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x41eb616ae3660652fb39d3e3d072b941218a3b7dd646fb36e90c1c294348aa63c2dd32b08ecda44da46060273ee8278191ca13d101c548a7fe4f08870c26a602	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc39f6782da7528506805f4aaf55dbb1162e4ca3c0314672d4c29f3e5d66b032a6b6b2e67c2713b0ac05d1ebe446757302ce0b85ee74de5d2e1accea875994c2b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7aceeba53dc8dd5321d3170a175c6a0f6f9cac9f8ea8b601137defd99b570fe2e37e1959cbabe46b254f4e8390cd07b6887b4b05de0b4cf35c58dee9d74d46c0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xef3adf2439a495a11ecde06ae05926eeb294f16a02b334b7252f47e896c72e877c388c5ba3920f950a1a8e802fe9c460eddde4679f4c23a1f2309fc6c92f362c	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x46f28094efa9e2a0683adc142d8e61ee1ed3971677c2ef520eb9509fba82c43069a01280b801e988e70d1a441c2aef1b86eefd7b59acc318a7b8a0972c9e6898	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8cb81dd55a7e0fa4d2b39e3c891113cbc5ffb38ca566d617d15d6bb632d44dbe0f7039012709c2fb29c8d999c4582c0d82312d93fb696aa23da471f4ba67c7dd	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x34771498ece65d5db491ebfe241a9e069ed9a0ffcc7d9880ebd79a5e53401d312e943e498ab8e6c79048946153a1c3f04c89d455b2b9e55ccbfa32324d8c5d5a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf41a78c161f5a780a49d8116a542ec884fb0a91dfa67382624154b8aacf7ca4d8ac866f1a7737bba6234ab2780047a6d9d16e9652c952f2fcd7d4d194706d447	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xeb0b85c33db0dd6d8015eeeb324b55781d14f3faa470aae411f7fb75d0bdc907d714b6df0d08651bd85c35f47c4e7b584878f607bf6cb82fe25e96c5f8f782cb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc71cda3a06b7f950b6b59245c805b3ecb8142c37b4beba7b4aa617e889c416580ef7dfb730de069ada6c42257a1a5e1cc6c5ada1e80491be5475ad1a005acb6f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7cbd5e1728f24920582e2dfd2fd32cef89b9622ee65566bc8ed63e1e428c0fad3b9521ea551063527b7dca0b9d70ebf6d997ddccc31a7617c705c520c100e159	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe0f8543a2f05ff9702c5e421ba1c7cc3ac99c9dc560d38bb78bd6ead2284add012e7cf361a5ccf954d871aea8490fc0e90fb923df4f056fb79445e6f54767f1b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb497ac0f6e0350077d655e7122efa9a4a7c563b2ed537e9a9b692409aa0c630ffc990c8a6107e3de41efd3e07200dbcf7943deeffbf0cc186b1ca44b54d14dfe	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55dac4251af794f4f971a61163342087661a1737fb6653335c26fb6cfa49a9fa2ca9cd65fee7f5ddb4e84bbb33a40d82c2e3ebefea8a5c97ab476fe65cd051d6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08478bfffdfa2c92b604ad44d10da79f13518823af2f0ff3714e8d4bf8774ae5eb243dd1f2fa0f69ef14de0a4e867e39141e8d716e83a7d5844c1727cdca54a0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f9fff3f37b33f3bad5e4dd9ab7fd050250f1e8d65bbef8cb1b10b1e131b1168a356de37b936d2274aba86dcfae48cafc956e3a2f4b75634ce36d623bc1cd09f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d2008ec6e30d36023fda43046b41f43f6b038bb4d1b3624aae9c22312ed5ab273ed1c28daf2582a0cbbcd81dc4cbced002b08703b5973683c7d61b39f10a4d8	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7aa16987363a75a79551a77ce8c1185db1d27986b19fdb68927f41cc2a247d88153056858655847aa2d6ae839fda026c38cfb13a15e5f207c9421fd23a72f547	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e4a201d6d19bb37f976e2cadc6087b67c40318659634f1a8e85ebca80abf185fd925ded7b13be5cfbe9d424535852b99cb665398687db8ce0e9e4b890918e3e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x497207bfee1783c8eb2c32fe0972cfd1c519da5897046a5b85176878c7645e983bd0b35fc3fe7eb31180b58d63fbadbd8b8b9fe63fc94701dba8b5191a9cca75	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x26caafab7c2dc866ebee4861efa0b356e6b17a363b6924e6db25108852cc1dbf7074525e907b72f51134b2fb443064a20e038e2b996090052b4730fd4b357d42	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0eaf736b41fde82239d524bfabb40ec24cba4531bbb0421fbaf6feee4d817290159efae0e07d5244fea7acb96531bbea1274ca59cbf90dba05e4a61bee44fe24	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9352fc36a7009104df1e28627459472ea35d528e2e6df9f0fcc728376e727af917f1e82d09af63adf714bacdf59f4f0c3d4de32dd4c368e55db5f13069bb597	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8cbcc8357213c298108aa0a871086ab4d9fe91929a28369aa641433869542917e83af90e37cd49485677cb1a5af460b484dc345c515eb7a131563890c0a53e30	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa67c527588fca9c08e3c9d901658192c8d0713c4bf0d123324da4b3d02e850c8419c51de61b3ac755b5bba97985167576f3172b0b38496aa8642283266a0938d	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x00aa10d1abffd9be47535c75b69fb25c1aeb80fe7d21bcc1a38d3578aa3b2c763a06744359097a1a7998f100f6af898ae00e8546f240230086a3d55df66c2d86	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x97c5a62b308a4f43ad123fce6eb0b9328c00662c7a3d00fd89e06e6c4cf23b27c1923f1109f0a1eaed4e14d441a8961679613b29a601fc72a5ec3208f2793bc6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x622522306be0d9afc9ea0329f956af6d3f4f3153bb3fbea017d0ea361d832e5a08d3094b2cc07cd06f7995b07bd442f878513484e6d66b5ea54a873ff2aa272a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x554879e8bc685c77dc01772b1eac6db13e13c2f2137f0ca89a139e7f746078ab4b69314390d0e9df9c4e1658386bfa9913dd5e87882e2a8a3d5a2309d772e9cd	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d32f1c3203f8fcd6a2b293a1d86bf9cf6cf759bd70ceb5981b8b41c7fb7faf3774264dde7c7238309b78dc9627350247499782f13590c81b68ae5c97192af6b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3e9dd97196119aee163b19fe3b2f897830593328cc39c24bf56f8a923182843d567d387689b404fa17bc32eeeec0250808fb4cddbfd76b9fbf6b3f18d263392	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x252be5ab45afec1d88c647227a46c0d2e23024e13a67b449ec691e9c21401f3d4ae1c914166ce9cf646ab858ff35db3a3454b903e063b19e41bab7b07ebb1940	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xade7120b7437c6054b22b461894d484719eaa2e2a1047f9b8f765780073c6893f633060a2f4b2a89af66fb4cb8888bfd67b491a0a00b81e0440528a2739d9533	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x812a785fc7e03c7dfbe808bd8398891e039bf5d40ef3b535de90dd1dd3cfaed9e1a6566a6c95eee247d1aacc36034070d107916636f0cc8a7562ea3ea86cf48a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c7831d83cdcc1d82b5ecd154abb2e9ded512d1def4e938b968e336d3697c62008a16e51587e31b548ede22bc8abe175067b54a225fb10d2bc9faa0d62479b12	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbeb8ec572bb2e7166f112c2d93554a381c09ddfadfd29134e9b008ad99b1bbda2e7c9693282d3068d50d5e390e5d0d0c6b0d4d48763d39246e2627da0f03d30b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe699b4df55bfadcde318535980bf15394af2a3f72588be04e688e7fb2091ebb22f80e445c54a33d652896561904d9bbb454fcafe09fd52bb8711c11dc23fa9d4	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2bdba9dc1f111b23ca3382677e9ac6d6729781539f38d81471f7dd5b9058106388b21d01c3ec04662859b62e27ed9e26e4592f836d2ecbdd6bff48b1c04191c4	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe5dc906e3b926eafc9297752d7ed3bda42ae80308744daa5f5767c330b49933925664df0b2fddd913dbdb977145f7a3556b1c88e5413d330eafde92ac032b3b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3d565f78ad306b0b55bec46a054d0539b58cae27d4ebc2966de48106254dc972422c10509dc69a32bf66881f975418cf4142a4223615975efc0ead528f71c0a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x817fc3bd128f8cea67c24295066225d603fbdcb560e53c0e9968f75b3117a85ab86c9654a3b211c34e63b57641308f6a93eaa1ef1cd603a80f7f2677fe4ae01f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2362bda073389086685bb69c348a112ffd57ad0148e27d2c61b81bf9a5c1091d2e97a44cffe0358d230c6576816dd4d9c64676d01a400bbbe5c640c7589000e3	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x62bdb6fe61f872a67491cb4f5603e5b725ca991b801f6a51df797b448ab4523f69a02400af3a6433ce5f01218755de791fc8a4d8b6eac73b07683fea1f009ba3	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d6c41cb13b20812508533eb4ac823670b471f059d0350e6be65ae1fbd2bc4e96508478719886fc9486c1504ce664d819b39bff8e3b7d271a38c035bc22ba446	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1567643781000000	1568248581000000	1630715781000000	1662251781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x02d6152ea0f916e76cb94e3688497f15c4e5451b51ae10052857028699f99ad481caf5d99bb159528a7ff19fa5b6ef50619f6ca80a7bd5c0c848d75e5b418926	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x149cbb6de079f4bdac0d3854276179dcdbbec5f4a49bc3040d153870b2b18fc44513525fac20f3a5803ea8e893f14bab84c5f4c25535320f1bdf04928ef8cc6a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1568852781000000	1569457581000000	1631924781000000	1663460781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x751d9347642b17d0abd5b19a82942edc5457c9424a6451535e0952307404a6e86423ebffd180e2842fec4f1184585a8737c868ff9428a5d878f309878b4d1bfb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x71b9a423a4d6b9c7b6f874adfdd5543e67a6652ab457f0c702a8f300faa7da748d118b55436cd38214bfaccec3e82f0167f8adbc7e6604324f627acf7421cad0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa8afa5e44de8d36c9c850be04103fb927a971e3909346263ede6d96a867efb4e5e93a055d1ad0a12d01fa8bb803a905ead67f5b89d859e932a40acfb84ab8b0e	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1570666281000000	1571271081000000	1633738281000000	1665274281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2531091d671471d154874cb823f3604373e3701465b7f7ae66e2936dfb137e9585d988edf3d0ac9da8c9c8ede2e709bdad9a1ec73f3eb7fb0e61a47ab507b7d6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571270781000000	1571875581000000	1634342781000000	1665878781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x271ebd18115251214ec1be15765ea23bb58a5b8cc954705043abb8d24d186c2538e715d572e32e677bbf511b07beeb89ab2d61f0d99a3c8e17169e3cca956954	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1571875281000000	1572480081000000	1634947281000000	1666483281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x782622668032026e2b647ad23759c30b7c2914e0d56f15671c4cf419e45c95480d10574a3d5d0521f578fa8e2f54475ccd4e0bc09e47b6a2c4a8a0823ce09232	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1572479781000000	1573084581000000	1635551781000000	1667087781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbc1da20d693f2408ceaf11c4700ab95c4be0a55a41b223f3f136823ffc3c741a1654d70ce142f3c03398b463368e8dc22fecc0db227ef646f9cd45656aca97d0	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573084281000000	1573689081000000	1636156281000000	1667692281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfbf39d88ef0b9aa475ec09eb693ff0b4a0047c76c46ef737182f5c4c540d30586489c603e746a2d9fe0250f1357b01dbf0ab9ffa7d93a8fc53513f5f66f549fb	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1573688781000000	1574293581000000	1636760781000000	1668296781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd6af7eb8bdc3e7e6e7902c8b75798fc3b7815f88dbf942b90b3ebf3012d537a34d3e654d8ddecbbb14994ba8600a8c5b865427549f8e317a6f150473e3f82ad2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574293281000000	1574898081000000	1637365281000000	1668901281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1556326735d408fe20d411546331923e26173293ac675b7b14501cc43968a5eb5f25ee233e680b7fe460dbbe98d96346b95facd1935b96ac8bae33f81681a0e3	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1574897781000000	1575502581000000	1637969781000000	1669505781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8578c4aa31b3600b4b1ca0de7cf0c88e0398ce8b09de758cf95d9b0f0a3c87495b3084167473c55374e7a6df50609e43c09cefbf00805c9abcaff99b8dc557c6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1575502281000000	1576107081000000	1638574281000000	1670110281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0351a3163415238e20876ff6c679fe5d5f6929716e0271d102065e32f86e2643c0c0a499e517786bbd0369c474f786e65c41c5f01d0fd8950b984385cae7a757	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576106781000000	1576711581000000	1639178781000000	1670714781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb2c8abfa46d8fd8abb3a602a62fab0da8753381de3f0bb8e2d24f59daba06a07eeefd94e0918327ea773b630dbbd2361919d201f6d4689caf14601194d027187	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1576711281000000	1577316081000000	1639783281000000	1671319281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7e1296bc7340d8ef33e2a90eac767398f8327b1f5e3bef94461430cbe1d4d907575f4d384b4035bd9b9edf0c2028dfc99c9472b1eff4fad5f3ac0ac90ded22c2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577315781000000	1577920581000000	1640387781000000	1671923781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x537fde37c0c1cb42f3066e421ce0dbadf2f8ddf8d124a28f587b3e5513ee85b19f3e142304f07bbbcababf29d1f9719ae80eab1cbb32b2ecfed5927c838c4ad2	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1577920281000000	1578525081000000	1640992281000000	1672528281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x77e4c8a2f4c10a87ffc286b22f65ec3fd216cfe42bba8f54f464aea88d8df41549bb6a052ba0c22434809e6c31a5c14fc37b9574cf829058fc68b4ed03d37ac6	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1578524781000000	1579129581000000	1641596781000000	1673132781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2585a99a4eb6bc2eff870cacb865d87d5af99555a4cde9e72aa4c0db6d85263e003dec4efee7e37d03b6052dceace5363077bfbb447ca471efcf441210e76c34	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579129281000000	1579734081000000	1642201281000000	1673737281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd1b3a2747c61994ad9e6645f19badc5f40396400838b5c454ffae3e86c34e3e0f6b309bd883d892a254262a43ae565d96317bec8c3c73d2d43a49f22fc9485da	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1579733781000000	1580338581000000	1642805781000000	1674341781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x64ec88d8eec889ae81af9b184d3ec9fece4f9e58399e654addb3dade0345a1ce7987d047bcac1b1edfe8ad839659f05c32ebd539cbe6d16af1c399bdefd2608f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580338281000000	1580943081000000	1643410281000000	1674946281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x038ac8e9840c93df4be415fd350b69121f0392e4002a44176ef6143dc0dacbf9b9b99934f76ca906f396b0bd14f7e766d7fc8e58d2d6fe7ce45524ab34643d1f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1580942781000000	1581547581000000	1644014781000000	1675550781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaba745c3b170983bef3c6cfd9c713fe51c1396df19118534674fc4c9ba8d6284888f014d2b2961531ea0f3027c524c2115a4baac88ffb39da44d06a88cd807e5	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1581547281000000	1582152081000000	1644619281000000	1676155281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x49bdac940c71f52eab73dcad518db3c48e845911990a8e07227ecd6989e631fbe8e6924576e6a4eb8a85fdbcb2e3729eac85316e264f67445dd95dd92654e767	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582151781000000	1582756581000000	1645223781000000	1676759781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa6aa9174a56a6df197a4bcb8dabc34030bc2a52b31cff70d1e56e972125604375827b9195b43e4f83f4e429eef3f091f2665973495c6ad3cbe5a4a52010e98ff	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1582756281000000	1583361081000000	1645828281000000	1677364281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x278032aa9e1602e411d39e419e2f883e842e90db7805c9d86e3fcaa5d27b91bee80051c4a6234d52a172f4db731738fa9fe1187a8d469dd50b1bb7de1b86a07b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583360781000000	1583965581000000	1646432781000000	1677968781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc1bf3ba17767475b18091d5dc5b573c79b53fce6949ac92411a9206e1550524f9269392e9ef7650d91a03a6ba301b34d0a48235841df9f68c42097a5087c2a18	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1583965281000000	1584570081000000	1647037281000000	1678573281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4d3927c8bccb021a1c4be4674c5f9c585a27ce273623881a3c99643e30ce7b8c83d6f884daa2a02ed87d6c22fbaac9148cc2695209e43c97253e81fe042803ba	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1584569781000000	1585174581000000	1647641781000000	1679177781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x54eaefe7fc4b5bab8d14f443ae1c248527598b9eaa2c444d91dc5462604d25c54d6f6bff50e6339557c302aed6e1c416a3cf7254edc9a1ab7d6702fd0732486f	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585174281000000	1585779081000000	1648246281000000	1679782281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0062bf6ba661835e79a127f730ba552bdd5e6318acac4eceaa801f84e1b234e419e7ad3984fa3619826f7f6d215f9a03925e2f8cb91b00fd50e6dc9679395e93	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1585778781000000	1586383581000000	1648850781000000	1680386781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x25aa975770e9157b0e8cabf4f6ceee3e6815d4145be1d63e8faab5b33d9e79a700220098a1bf1cf94c563537aee2068d8262412f38868c4a327bef55ef89621b	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586383281000000	1586988081000000	1649455281000000	1680991281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcd1daa221f76adf1c74cf46580ea73c65d36298e0de1fdf374ad56c1394d9311a2c4dfe5810a51b3832a77fe2cb07c350cfd8df3ca4a71b576c1052a5a9cdf36	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	1586987781000000	1587592581000000	1650059781000000	1681595781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	http://localhost:8081/
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
1	pbkdf2_sha256$150000$ZQFAaxtRDNrm$1j177FUck5EknZRZ4gY74MMC3hvSG0WcylEwNfIaVrc=	\N	f	Bank				f	t	2019-09-05 02:36:42.949696+02
2	pbkdf2_sha256$150000$UbztUfucgdp3$CWaeaIJJBzCx9W7yzVAh8e2yZeWymm2CqRV5UrHoORo=	\N	f	Exchange				f	t	2019-09-05 02:36:43.250622+02
3	pbkdf2_sha256$150000$oTGt1hgmhZTt$Bdo+QbsakJZbqsgi4UtgvkTxDuRTYwlRnWsNEp8GETE=	\N	f	Tor				f	t	2019-09-05 02:36:43.437804+02
4	pbkdf2_sha256$150000$FWk2YRhYoqA3$Pb8Tp8lJNsb8vez7yhV9gskyGVWY91T6Wc/9viuXhik=	\N	f	GNUnet				f	t	2019-09-05 02:36:43.626885+02
5	pbkdf2_sha256$150000$FTl52sbeIW1z$o/YrU9I9TrfKQ7dY9DRUiesoQv2VkddaDXpIaatPysg=	\N	f	Taler				f	t	2019-09-05 02:36:43.815795+02
6	pbkdf2_sha256$150000$rEshMSItCkSA$LjL8j1aa8tEKSw/HTZHfLqWWk7LDPLFdYWz+vhShNpo=	\N	f	FSF				f	t	2019-09-05 02:36:44.005084+02
7	pbkdf2_sha256$150000$AoRhXOfi7PZI$tfVnDZcsIrH27AOhZETUesOsohtZKwDJJCNjBEIXB40=	\N	f	Tutorial				f	t	2019-09-05 02:36:44.193457+02
8	pbkdf2_sha256$150000$voNmw0dyW45T$6o2GUWehd+yT15IzfTS+lngW/bzQX7awgwFjsVjZebM=	\N	f	Survey				f	t	2019-09-05 02:36:44.382339+02
9	pbkdf2_sha256$150000$l89tDpk0cE2V$JFRT2nRD2EavhwNqvTEWLntmeOLOvmvD8mxT1lRWWK4=	\N	f	testuser-rSRF4A9l				f	t	2019-09-05 02:36:50.870209+02
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
\\xd0de7270c1520cde62ec903a1cf6d1eebc53feb9433a3459cd45ec6a1c42461ad22aa1a95d1e8210512a898f5c7c14ba79d1658a831ab6df3ea968e19c1677fb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304536464345354334363746314432423636413136343933413138343839394537424236453538333432344436343030304445433342454641443337394237324441364232454332383541453237324644463937343535314444303030354435354433354330323736313141393032413537323731443445424242373836323136394236343844463432434337374233453338384533383038333035343338443139303741413532343333433037393639303243344137424538343532304438314345433437364530373531344341384243393642463830324132314336413239454230363735304645443141374133393141344136303739433730323343413323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x5d53ce96ea1beec43eb58039e48b16ae234d1ebc519048bd02f8cdf11405c66d2279f7c29a0bd4193815df3a8c6528a72fdce4bd8003fb51c727eaa680041407	1567643781000000	1568248581000000	1630715781000000	1662251781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24fc0df15163d95eb80f3272f9d17e0b8cb66feba4ffe17641ca894d643768672b3f6f643aaadfd920b0620f51658f28694dcfc41bd1d9460257f43f5c8ab3e3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139464230463138393046323435443733434344424534323231433532384432384131314434303632463145314534313043323944334533373334434142423241373732343535423832464535433030304242444443374446343038343937374237343734323434394544434442394245344132333237303735334646373234303237393130344431353238343836413937423430343735464236354137413843413432324637383932323045434637363838334437353734313436453430393242364541423545413738453833463334423038323932354637463444453634384138363233313130343745313346353631453346314632353536453738364223290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xe79d65118ec8c156de0090b602a0d09535283db3d186da43ca9344738bb243fc0df93b22d142d373c7f85f47e144e7d538b80b9d94f82a95932ca82e2a4b9f09	1568248281000000	1568853081000000	1631320281000000	1662856281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa735503ebd35d938e6da7f7c50cc41e6da85ea36fabf9eb03aa5f98fe54b93bb367e53582baaad9e075b9220491e34b0d01aafeb128e4c6690241281758ccf6a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338314335394544334641464443363330313530323635394145394534463639343032324245333333363737354336423746333632384133394443314133453746383339413542354342453843354236413446354430324635434333344132444639453342343737444538324239393143333933324444383734413145354239314141383537414135364239464341383936463043433133414534364331314538443132454143384433433139453933333945423131354331353037414642394130433635344139414445324438334332463231303643314338464345424439424142303933463239364444363036454241383545384546323333383146354623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xe10e27634c0aecb1afbad4054fafeceeb65be0e0329b68d5c669a64f004d3db473e4f4f881618e7f807da2f1fdb3a2f724ddb80ceffbb5f3ededf0da5dfe3a08	1568852781000000	1569457581000000	1631924781000000	1663460781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7dad7b5564c9de0e1c8010a9e20aefea1377b3eb42989a9cfdebe168f9647f935a4f1a710bab4e242682e6c3cf27dea29ba5c61a9c0bb2e2b9eed7ef75db18e1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304533373637383041373833454243313437343633374432424238424536353334354434313242313939453643463843413032323436423333303032324135384346384338433938453844383733463038413739313734383438353842453931463338424132364136313835343035343031363235333535433538303246363733444632383142464232303531434337353630333738304238383744314634364542303945454133464232393741343846443737413533463041333933323932383041323441434437414336423932443839393933364145323843374534333939363439343831333542423442454533424635454536323433323845304346333323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x5a8b9ac22d31a9cb54b73e44ee707e7963ae696a8f6f24662a606c4a12601d990775bff72e3832306742058400d45ce2623c1e2b5dee46ca8bfb215a09a9ad0e	1570061781000000	1570666581000000	1633133781000000	1664669781000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x22f3ad9306cc7ae45ee3fb8876bcea0277bd76766b946cf412848c7f4b0ff27a6716c1aff2c22038ec2ea830632e58255cc530ffc885a2183b63590cdce52cc9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304534424633444632363135374333424632433336443534303646323036323134383337364643374339324433303532423530434244453642434443463839443630413235443645433230363745463030364543383636313335433930374332353742353533453130324341324235453930463938314539314135453442434543314333394634323744433032363346433341304437413734463531414136334635454530433241394333363041373634353044363138314232314542423442373943333342433835423644364437444236343345453842434544423035383539323132463742463233364636363443424432424134343232304430334230463923290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xd87c8f435af938118db42572465a1dd50d1a2ed251fbcd22e7208d1d2b122c5185d87785380dce9627be944439b9ada774f2f669427886c7182f4f61433f160f	1569457281000000	1570062081000000	1632529281000000	1664065281000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5e9aaf2eee417a5480c408e07ab8d9fd34b2ba38778b984ed57ffa069be8706ff2b39c970be28bc654a6618027307dc2af29409757a2706abdba7a275aa7a3ae	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341373437393834454139383943343544363946313635384338323141413133343635314334354131304141413039463939374437323934413342444246373933463730343439423232423445374333373734344444364538303646383636303643433643423335364235374143454646463438383732434132334441424239363531424241463436363435333330353742444134454137464237353632313942353830363343453043303535363944303642343330343642453931324639314546443245303144354432323831394432434634303330414534434338344344463333314230343230323939313642343535353743394142383430354141443723290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x8fbbccf5bc2d3332c91c8b09c6d9ad4a15c80a129f5b53145ea7cb051b9ffd0702326ec73d6fc629c286604aa40bedf153edf64ba63b9ec4d4fe39a6336e5509	1567643781000000	1568248581000000	1630715781000000	1662251781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6141577a582447326f35a90a44fd3e27ab1a017cbb4bad6e025660f427add6100d5d002210aed7bf9e5f094b0670eba94e9b117ab5d0b087376639dc40d362ad	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244433337323745383634464436434239443044463842394635314539413231353433453237354638313537314245454232323939453734444238344646313936433032303145304131303930394444324138333032424645373530323230323838333243384138343638373444413246373639313744383942434533394341393235364639383838313730394338313539393544393438324545343032453238313535423442384234433031393434444432454141313033383045333034313543304444373035434345354136303234384434433643443733414432373230364543353134464233434646364246444332344136363342363646453744463723290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xad43827015a27dce7196c30615a5cec1d5d1551ca21aab006896c43b4dfe64f05031e8795116842b159b5c44943661d8abd74443c92cb66dea6b3e37f4c3ad0e	1568248281000000	1568853081000000	1631320281000000	1662856281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xddfb73a641357d56cbd929b8b6a7ba05b9c5bccde85d67fec77ff8cc970ef9861eecf003c8312cee108b92825b54b3fda9ab077df42484b9e9ca1a0230004187	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143313037413442344239313646373038463939464135453445413645313733363938453138364444444233354344413834303935363832353846314635433238364338334445354338414242383535453735394444333535414439333533454533304644324242443041373241364630443236444535364633334145304439324636364337393844443841443431463935444143393033373242433137423736343946374431393436353335424442464430424635384343354144344437314631433831303044443744413038383731383232343432373332334544373746313836333833464536444438414144314437353446434439423037384241383923290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xc66c4fa009449298b226b7d588ce544be9b77f734d74cd6f07d7b2f4161bc9fd8f4ac77521b6640d17794c9811734073580dace5927cfd2c3debaf65f588aa04	1568852781000000	1569457581000000	1631924781000000	1663460781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccbf85c41c3ca68df43d99b5e04a02725cb78fc4ad5b7a819aeb5312a36e5bb05bed4dbed617d6d38715cdf2c6438d9149f2f021f00ccb67f600cfba3e13f39c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334444144443042343437384446354233464644333737343431314131343239343343383232423732423735333842394645394534434333303838463237323435303535353533443633424532433535443038334537314130374246334544314543433831313036423444334437463046353230413446413938423544383436303738383539383532433143443534333043444146393230443145304332373645394542453641364639433930383638383041373834463442364643303043304245343644344134343932454146343536364634463732363430414636394330453942354139333445384535303030354345383235373345313343323432373323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x0d6e749ca56c7852d8949c9e29c7b5227e5b595731765e0bd6cd082248f6912a04426dfe95da48a94be537859190ef47d9ad048df27929c4afcc0eb15cb69b05	1570061781000000	1570666581000000	1633133781000000	1664669781000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ceb934ea809d51a0da1009462377948fd0b346d4b38adce5307742dc474b3531fabe466b2acfe6cca4224dfc82fc234085962f3a65e26b3776fe4b3222a917a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136464233443033383132434533314643313133374534373434444136464442463136313437343131464434413736433136333438304442354235444232443345413143333042383230423639313637443634464437454437314243443037353843343745413837433839304343344539324342443235383439393045443945443033303339393443303643314638413545393646454245344446454541424631443244353532333632393141414230384432414342353643354632364238424241374632363633423039314438463437424644304141313746464235313741463638433233423043413841463934313735364433384136363042443538393723290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x96b098865da7a9b367b12db35cf08a8512af80e3ad152b1df736ff6337c5066077e40dca7f5a55d3b3d5972eae2556aafa6b9ba2682e7fd9af11fdf33874540e	1569457281000000	1570062081000000	1632529281000000	1664065281000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58c385b1a09d7cb925dbe71dc1526f2321895739b803294d221392f301701634dc28f8abbd8833220fe27606a078d5dc16541e1ec5f3c6c535439fb3059dacd8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330323838383838324438303832413930323244453544463732354236384642364137433942413241383244314636463934383245324231383938363635324342373737444334424343433044323736413435384135334539453045413238453639303144303638393041414638353230323346384433423035464241393842424345363030453444363942413539323044464439393737303530393036314539393541373633333446353343423841313145393238363836304132323135363331413330333636303133384631394545303336353634343030434542424539463537433745383436324541344241444234313142453842314344373831424623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xa6512edf843efb63bf06a5bce1dd5ae7e9e1c3869ceecdb03d046cce71c35d94d6312cd9b0a3b6c8f6442674050cc94c2111a5eb402a5e08ccb146f418d2f00f	1567643781000000	1568248581000000	1630715781000000	1662251781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7bd4576b9e58abdff24e0fa89a3178b39b60e92e87196febcc9e43057b519203ecac7a47f35817393243e3714f96c3f632005289b62d7feae0404545e8855238	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304631314230323346323130353139354342323235383135453430303534414446303633323944384133343031454645413142384438434242313738454232464438464130434645393338324141393534323841434532443733334533453042383536343043373646334534334141304631353638313644323842303830394141353146424346363939453138423845333244394646373232354439324133323143313746433637433645414636343734313838453134364632433833343235393738393638443934463731414442433734383139323230443338334545434532344238433738413146354437423234463942333543433830454138333936384223290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xac098658084a38160910d012785f36cab845f80fd4e35e98cd6c82f1e0ece6fc4d765fad10700d128a46c21a91111c83829fce0699932f876bdef17c677a9704	1568248281000000	1568853081000000	1631320281000000	1662856281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x861ac77e2b218e655057df557b90215c83e5687e1f4a566ae11c2acf290cc03af5655e17ae0a275cd23a7d910d10a023c20a674c30fac3899bc1a6a64bac5618	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235393543304146424139373737453130384443413641444334453541423939423534434642444230433941413530463733313435313639303539384538383744353033354138424534323343303142334333334236333246324641443337323538334341333432393545413433463643394539464241343331394541333335343139364144444230333745323132423634413932343131434631323733363246383245353946444134323039424644373136383641453434324631433337313246394346423834363641333743454430443634303242323433394639444339463638303933324438393442344341433546353430383446393233323136454223290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x168cdeb9666dff2a2f888952cb791c95015771e71cfc3228e96c565a0426f77eb820496f1a6fdbcc822ceb37fba9a15cb787998bd7f3066de6aae296f7f4c80b	1568852781000000	1569457581000000	1631924781000000	1663460781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7a2ab4af164346c9300d245c636e478901c6d03306217041958be31b54f95609383fe5596b4a01c3673c0e644afadf1df44934d6c1e774708078e676522090c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435363933433535324638384439424432444434363038383830333644453538323730333437413837324630423942334438414334364134454238354346323330423835354143463333393837443542363641433944373531364134384134443136383833394145434644353932394235313243354546364337333943464142423742303738313337344433384437333639413832324332363142464341343642364337414645443935324332344145374144424330344245464330394537414646313345463344353446394232453339414432444532353337464146433146363130353246413244383643393346333034363439414538304143423743334623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xb39f3943ef0550480741b24f0cad0dfc1291dafd112fd0c28e4b16e548e8c3f03172f4680c0986809f037a3bf6b204d6c25124a8342fa7969fc23c7ace908009	1570061781000000	1570666581000000	1633133781000000	1664669781000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xea4c70d67aa4e1b80b46c14e2aea61899f9ae151c0cfc214d2319c17ee7042ad7ac4f672975fe25c38ae66f0d458106e1d8202b2924f4be6b18426c67634acbf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239334132343631453133393242413737314538313338313130464238353137374532333636453537313635424243383431363339313843394130413541373945443042433631434431323838383934454434373039333942454231343041434636324137383332363342334635413536373642443230323137354242414543383237453136333343314131414134373432314237383243434637443943343842393937334237454436454345314430374430384436353434383338354439324335453731324144353839323243423633413835393243444439304444443045313839353038414439383446463132374645383636434244453431413845464623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x431bfb1bbfa293ab9650e59cf508b9048d8cd34e9e434169ac49cb848b3a8b1efac3a5c7eaac769a113a1644c328c7ff84878be6bc5f7221cace9c8786c7e808	1569457281000000	1570062081000000	1632529281000000	1664065281000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x833d87f2ad05067cca2f1cdefbb7c1f5a9828b515228633e895e5b3d6a1b4554f7930569cdc8d8cf85dd295970e22bbfbbc4a7be759ee9f7ffbb6d8906f85463	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304145394145434230393738364134323932424244383030413838413032453644443132423538433837393244434632333646463538334641353544454636343732313345344141313946463533394637344145464346354538313936354338383336463237433941443943384544454343324342453538463634444336374635353032414544423039373644414432324333374335353430374641413133343734353645443544363032464139313738454434323745313434353243414634324341423831464444394343384644393546383442313541464444324246333836463438433434343944454341433243434334333830334530424638344442434623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x8dbd0c93f64fedcb4b1d11bc559f98c0beb335300b425fdb28e7053748855035919a9fd62410aa03e9f0ffd0d0e135daac1c7e0f3420e1caabef1757ce6a3c01	1567643781000000	1568248581000000	1630715781000000	1662251781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd617530d4373ba610abaf384d5decd6d56746a88ecb85ac89892ac0073cf937cc4c7eb6176a0c13bf8f38bd28644d9e24b1863e45c471abc5eac832215acde37	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531393741383035464546303037393539373242344641423331423331443541463535383636344338353932413733453038463234464339344331314135464145443830303433393034313230413042424230313436424645443433374445334242343246363646324642323031374241364344423943454235373841383037374239453030374345303645434531443132303732423733363232453144413032373335353037363442433432373943384337343941413638433746443332354236353139303143424639453731464339344437434634323438433132303435383344394539444534363146413946334641444541303034344436313941383523290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xa9b4626e5b40945dfcb7b2c6d1f79e90d36c6d4f9108c57cfefe16b7f781f4178a67f3fd7dc4c01f266c37ab9d8d37e6ca8e03ac6ec68f968fa26e63bd616503	1568248281000000	1568853081000000	1631320281000000	1662856281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb993f4fe55d966cb9488d1b7cbcb193a858089f1c930ba7d1341bedf85518020043fc987e2c68b00f95c2ac51d27738cbfb0749f062a1d2ea243aa1079d9e896	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304633343539393339324446374438453736454543463343343234313039314535464145373737443738333834304437454139383442334631414443414537383744424245334141413946353439443434453341423043324544463235333445324232304346433137364236313532353043324134343443313431323130443246343836413932413838453038333745463336363739333832313637464636393841413530333936363943413844323437453531323542393245393443463731313038463539414138393632324641374546304533333636344441303632363937354142454233333836333435373633303942434430424146444535393637353323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xd66328d3541ef0b8b4d064bc9584bf7ba04daf1056f77b8989e39652e4f397f2f725d77c8bf397329664dec216752731007efc65a848d0b8b7f7d2aefbbdfb08	1568852781000000	1569457581000000	1631924781000000	1663460781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8214be70364a7b644be9ab7f08af3177ccdb6ac7da9249ab86af2610aa5af995435d97ac6a4a45c4116fc386dc8509256ba223909a4b20bfd610c05c24a3180e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304635304336454139343131304143354530324332323533383846343836353944303330453430344333464235394631343535333137384543394438353633383041393631413036343939313632333437354241354435353146454131444545464339363935444342334236463045344145304530414134344531383437354142383238423831334430383237413735464544444343313438464441463133364130373330363345433139333944423146324143434542453038443244434338383642434430423436423732343532463936434334383331443241373433424145354246424630323038363336303032414232393730354142323545393532303323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x9ae80eccbfcce42624a152a25962a73d5522e55d17f7162d23bd0e7ddef63b7796405cba17933332f1f94fc884becb448b639843060514a817bb77e8b861040f	1570061781000000	1570666581000000	1633133781000000	1664669781000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4fbc2877d77484543e24c86f7815177c8862a7db4bf2c6d476e3f036e61ae351bcf89d5fdc6923022472f237e62d56e38e4ae3530efbecfeca76fcfbb491d6a7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430364536393235363931383232344434314330343544413136334436353331344430374531383731443242434338324435343331434539413831444642303846423246353935333831314545363333424130364443393542334341423844414534453443374534324633354242324231453032463039374646343238454333384235424142464235443036433632443344314632364331313446364636463833324346453143323539314243343830423742463436344532444646433444423843393739453538304131393536384542373743363631463644374630314636434341463136353936424435394531433343453830393838353336383339314423290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x0e4be8f459ff25097d4b86aa832d1b31e5de70c5b689521f3c1db159c91a33048594a5a4d9185ac9bb18890e05041219ae8d74e512ec49f2b5bf4c17916a070a	1569457281000000	1570062081000000	1632529281000000	1664065281000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6aac86f2f844eb38e3649c419f5739120d5fc105c6d57a257e8921784a18a2e62f799be812aac4a3e09ff6bd3b8ffa2ccd1a79b3a9d838d38b3020a2edac53ae	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304236464435383934314533393339353235313144414635303336304335354330333138433333444345353732433444323243304233373643423846443831454638324241324442434546373438463139384642334242343144454642413738303737413741323036323935414143413531364245443144354439303644313231374142423338333841393632453143423636424638443743353246414533413344454536314139354236314441394245434538463037323433313146323645384136333136454335444342454144333232384342393032333033394130453439433035364436414241444341373439323735344541413637413039313137313723290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xcd7c05ecd1c5a65eef4d2b36af7aa110f1e24e8f56707fbb82f422c404cf1b5abf015674f491fbcc5df5acbaf43728e40bf4b99d1d1a9477ee95dab118168501	1567643781000000	1568248581000000	1630715781000000	1662251781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x43da04a446fefba3569db2674b90ad017d5537d944edf84b3ccf253e3f0266b543b71d0fdac116487854d063eb46c9c1560caf825bfb30b1a3f12ae28b4787a5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239304443304437334334333441304239424243303733384142324242373531343843333036463132353533394242374541424445353532374632303132314339433146423434324437324636454239343838433044344133413331303037454430433043454443393637344246333543354433324234423246393239454630333445464344363835413339373636453746334136444438333043414430334139323244333934334644393836423039444232324630303930343036354638463543363930343838323842384143314342304631343230394545354646393946414545373934313232393834323636314433383537313037334631453144324423290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x367ebdedd715513e5f141bbba3ad980eb07e5074f36329749325972a9a7b65da1e9dce3f0df5c726627e15efa75c486e320979f2a96dfe4fdaee837c9576bd0d	1568248281000000	1568853081000000	1631320281000000	1662856281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e82d8b62fddd6502f28f2d20ddc70242cdc2995264577856da3ec6a46283eefa3aee17bb0b8bd6273867508dc440178ef04d78c5de92e3484993a01e51f0ec6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342393233433439364538303835374432313143323034304537334533363146444235434544323633453845373036433544343035424630303134463932314130454341323545323830454437313837314641433530433644393042323331323236423242303634343943434145313846333136394644323544443641313844443030314332444131323036364645373432413838444337413145453630353532333742423039454541464432374139434138433437384235443931333742383943443536394236424337453834334132373042324142433134433231394634414645443830413442444630323744313541344435383030354233313730383323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x2c37a91fea15c2fc40ec56ecfed58e18aa4cd069d13346f443e4aa35a82bbbe307e00ca29ab3eddf41d830aba93cb1972f2c9cd647301518c27f93f3883c0e0c	1568852781000000	1569457581000000	1631924781000000	1663460781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8f707ee668251acd2c6bb8ade966ce4d6e9b4a0446e6b9526abcd32d6f46584a541cb4c80736327d9c46dd6a98fa6b47604fc8aad01a48664e988537a68cd326	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442303034424433443233303131353131364339303945433131444244303932423834424235323543463742353931453734433843393631393845363441334639453330303543303241363130364246413241354542313742303531313446313745373531423645334131354331363531384342393330443535384431393038303637324232314143444234304235333139463543313135453541364137453533434138343933373844463933334243313432443334443730463934453332334633343342424145463234324633434138353638303533373246453931413030353241374542414432343339364345394235373136374130303332433844433723290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x3ce12b8157c901fae63e07182d437949c8a7e568cb074f09421cb0ae5fcd6c8c4ced0b3dc0c54c3a259b01579c0cc41dc72066e9d498a8d8d32c64818e1ffc08	1570061781000000	1570666581000000	1633133781000000	1664669781000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe8fb52b78e8c2906334dd2abea35de47763ef8085c3d6586a5f9bac19b514f7df4366738226281ea772d32fd7e116bea12252738c7c07003e1b97398d17cfe72	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245413446463038433032464545453045453741393333453641424341314631363043434645443235383736443142433236463836394346413232353236334541393430353946373139333433344438424343453142323730374237433943353541454241304436454632454331314437313436443037394344463545373932434244443038453644423238394338324230343531373641363535304533393936454136313341443133443641413632413838333044323130324145324338373738433746453330424146343644343130434444414133323045393845304442394230334243423838343345353936393042353139463233333935314335333523290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x3cb108e558c0f603b47dad608a552bcf6c1b1ddebc431f8a2f7d57ec61f941c7f892aad7bce9c3eab5efa3315756b8a1ad55f306b86d486fbda5478f65311005	1569457281000000	1570062081000000	1632529281000000	1664065281000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe6fb8b3948e9f92b43079e94a9b77de96c975b013c55d43d2daf2a59cf6c22b60be410b45ee4718987131376060d3901c01796f5e7f46c2d02fbb0d3ce21229e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432453143393838303835313545303141314633464639463936374238443142454143373743443041393844383935384535354138414344433231413739343241303445333335383334453345423236314242303441364331423535323141444131333744304643344344333437393641414145323531333041353435453431384132353230463635343737454534373334454546304346453041413346353736433733394139394231464138394143413939333737434442444641453432434345363035354534413941364239313638354245434146313244413930423138363932413537314639373645374132393345413538364143433731444632394423290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x358099f482bbd008cbf2f01c8957fcebd116684285d0553dd75245ec8b584208f3a387942e03ddeb2f84b3ccb965719ee1181549823895cab35884ab1e3b8208	1567643781000000	1568248581000000	1630715781000000	1662251781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3ba49848a824fba431dbb8b42828a3457d7009605cce13077d9309176b2acdfdd2764ddf137e2795578024771c175c780c1719cdfa6664eda20ad85ea2e27c8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304633373432353942354533384334394334443239364344443236443638413241364143374136463235314433413943303330323730364430413435374341373038333336443833373130423531413333413246373841343539314238354346323146413142444334333230453246444535394432333935424143443633414539463944344144393646463334393331313638424332374239384531443431374245433341423342333646343445433933323436343736374442443933443041383844463742303835373146453143363045313230413538394336333333374542394146393234323244394334304536333937354236444546374245304434413323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xdfb703fa3930005aa8b32a51d57a93180b78aaf8228949c259ed3a825a4ede913ef11dae370147f5a0c4d6da6a355631638719c885db76ef3700b37e58f2b901	1568248281000000	1568853081000000	1631320281000000	1662856281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa85305590fac46365b19d0443c04152def0e1f247bfeed76e3218a3293b5b9a3c537a7a44d70ed5d20488698918818163bf8cd614b5c2ecefa80efa0a1454f0d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338313046363542333645344344383135304232444543414146343139424241423831304644343034313834383839383244443536353835444137393046424531333733393534413433323746353030323744303336354632354638303133443932394245424233344639463238443439434135313533453534453630394543423931423732374244413331353345333835344432463145384342453033443041443535454239364642433631454334463441384637463341333137364339424443364339393442433642354336454430444133463044344139463432394333324541333542394144363542433641433830363342463434374542423734323923290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x1981d7fb41695e7e8b92e085c10f050f382b0753169bc94de3b676b4a6499f797accf877347196f7b09e38a6cddff060006efc3020c9fd78ffae141a01796a03	1568852781000000	1569457581000000	1631924781000000	1663460781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ea70bb7cf68e371787c4d3ca712f41de204888ac94f9b4291c4251aa96447f3f9523b40d1727670d598dde5758090957cff2d164706c671550b2db925519197	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230433741423743303236393932424143344646383446414135443137363446373944303935334437344446393131464541384638364638384146393341453938314133444544424246433346384439354145443134464146323045383335444542464541423332433141413536374132334139463345423938343945323943313938303537454536383939313136313139383444374333394636443533393434444346413836414132433931303530323538434441444539393439383733303739363242454231453036314542343636463431444345414534414545343334353437453745324545413832343942344139313234443436454430393436424623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x08b8ca299bbf184314ff6c710c096781c28aee2a58f158e7afc668282816406ff5ec184d25398e085d177991355e50496238f2290304b6394d0baf79d3e9360a	1570061781000000	1570666581000000	1633133781000000	1664669781000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xde74179959b245b0d39516ac918a9e439b7987b3dbd917c9a566a025abe715fb68c8643a4ddedec184b72e1b5736affcfe1a0bac9603f9d336d97ad016af1359	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436414139463543343438393636334645343241453631433232314434383434313438343630303446434241454545313342313437384641344230393034334436314639454238383739343035463241304131363131413243373532354132343244423243303532454438314441334136323231423532444538384432304143363832353943324645353345414341423941313732443742433137463045313539343043453530413645354237464630384445414637353943423635384132463739343539414641333037344530344546373242333133374345344546334543393741334546374130353636433631303842304646323946354133413635313323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x983c9e6f2faad315db7f173570ae5a227b987afe7ae98acdc11e9c62204d1d0f1f5b5d6c1554b5fac38de513603fedbf9b9c102c1eb6053f4083232557707e09	1569457281000000	1570062081000000	1632529281000000	1664065281000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242413231374435354138424436354639373338333637303143424642324341303532373943364541454138353434303143344134323241423930463942413235334437434544444136323335303733373236314433323935304345414344334246424334424633303039333533424534414439423042424136414345303233343342444442394334384644443739304237453236343941423339354235464233393337383146433230343242304432363037324130313332383234343038463235343142374537443030444438443930344635343146443146383043443436324438314442454637453731373131373235384130303231433041383444344223290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x11caa316995afe61830321d3b196b5e2daba35626a1cae78df94d263f8ce25f21da0f5b67af4904647d4dfa27697b537457d568e8de30e74cdbab302c005b30a	1567643781000000	1568248581000000	1630715781000000	1662251781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x02d6152ea0f916e76cb94e3688497f15c4e5451b51ae10052857028699f99ad481caf5d99bb159528a7ff19fa5b6ef50619f6ca80a7bd5c0c848d75e5b418926	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246303733354531424644383837433644374143364442453530433241433031383941413234334231433844354532423943393833373332303234324635343134444446373934423634384139424532464441313232354441343030314545464239333033324331433634454245304135333936344630413031354337413336464439383843383544413545333437353335443435333332464145353732344236353735304135414236434133423844423039394431413530433536383546423236393336384632453531393732314331313735423433443941343630464131383345393830384133304141424445434235363733364246364136374336323123290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xf5604adedcc0a33214101070d39a4c069925953f8742115898f786b554e01d8e143c0233e42c17c8d0fa3fc757918140a2fa0029dd13c096d7eaf09c599a3b0c	1568248281000000	1568853081000000	1631320281000000	1662856281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x149cbb6de079f4bdac0d3854276179dcdbbec5f4a49bc3040d153870b2b18fc44513525fac20f3a5803ea8e893f14bab84c5f4c25535320f1bdf04928ef8cc6a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436343944323545323334383243444536344130393434383234313746463038453530323743444530393136443643423138303744443038353046464642364535423345434542444139384238303938373542303333423530303537413336433833354234414234323437353243424535443039394538373735384239413139384431383233344338384636324238314132413543424436344632433334393239443245353645463738394341413831424241303337343841444238313539383134323033314330464631363738433442393745303646344444444645393030393332413335344637414246313534463830453831333532323446434645393123290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x1a90255f33ab0b73d87978975d572b90bd867b82641e9b8c40aa42f8d1f9b8240d6c873a1ff5289bc9ceebb639ff34e6463c8ceea81a8fec8bc966a9828a1900	1568852781000000	1569457581000000	1631924781000000	1663460781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x71b9a423a4d6b9c7b6f874adfdd5543e67a6652ab457f0c702a8f300faa7da748d118b55436cd38214bfaccec3e82f0167f8adbc7e6604324f627acf7421cad0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433323039454635424441443530454342334341344138303930353232333837344245344534464338324630384441313332433343393234333235343632364143394535343244463337343243414442463734433743463945433030443032414530423833423546354433383541343537353442444532353239463446374131423539373534443042454433413333394630314630373330463742323143464646384545364145373745453630314346424431424145333535413539454633343439423838443333433438304236434641423844343936323638313842463731394433434136384534333535334343334533444646433039363735453333384423290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x8f451a5023f25449ba536d5a5817fbc4fdcbcb346c27a4cf5e758af889616fb638e03fd0105bb6685c9e2baa9660a2f496d52122ddc04d72c00d39fe15a23c08	1570061781000000	1570666581000000	1633133781000000	1664669781000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x751d9347642b17d0abd5b19a82942edc5457c9424a6451535e0952307404a6e86423ebffd180e2842fec4f1184585a8737c868ff9428a5d878f309878b4d1bfb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330343241453337303342453732453343423332344542414646324439353746354646323339353633434445413637434138383938303936393133463530463239324236303738444641393541464430463346343939394632413530433237394135384235413534414141313434433445343730394543343238334539323237374441344246303541304446393532463934453630414442393344383433443431423636344632314244413132333745363830394537303732383343444632353132324531333633463639443238393144453633393746353130353341343643343643414132393442373135303433354146434133334342333443443135333323290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xcbd64a0cca154468f5303aa81fd157b93a9cad19f3834d24a9773b739db367d4f9d0e39c1f84ad5ec568c25f2d507fd6fd903296f1b20e0395fd5359a95dc707	1569457281000000	1570062081000000	1632529281000000	1664065281000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233453832333231313332304134383141464332304241333730364538363633414431463846383030313931363035353234363633384333454344424131384434443143433536443133433142343141333931434631414433323234374432344438364143313433313245303341393633433136453735413345364643373031413443353538393730423636373341343833353941364238334246424134303431313931334242353438313634394434443942463830323544413732383545344146443841333736434643424638413745433741323632433234444435413845313243343032353843324641363638393739343338313138383236303341353123290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x5930305efa5c20de0689e32ec6838f7348c1a5d3959a7610d70feef5074435030f145f1cb68ae765077272d144bd2808e95f05437cb655c4117a60973641d90f	1567643781000000	1568248581000000	1630715781000000	1662251781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb497ac0f6e0350077d655e7122efa9a4a7c563b2ed537e9a9b692409aa0c630ffc990c8a6107e3de41efd3e07200dbcf7943deeffbf0cc186b1ca44b54d14dfe	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431304545464134343633424439413332314330364134363331434244333346363135323334443833323131314430423733384139364330444235333935433535444238414444463230324634433245384245413232383933353944463632453643333345373241453434414141393846373737343446373630313543323630344332434545333238363330323430333136374144443433304634324636374141364141323834383836413039303941313035454134313344333233383444464131383032423536394435423142333731393131373434364141333333394636314639463444304544344537373839393233393233413643313831433539373923290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x16a03b3443addcee81e6a2fe29df099f339d71a0ed2a8fc27a5a13515d0323c8822c276db214cd31aa7d6d431e69f867a7503c1f982c9b3a75d2ad6f2d949a01	1568248281000000	1568853081000000	1631320281000000	1662856281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55dac4251af794f4f971a61163342087661a1737fb6653335c26fb6cfa49a9fa2ca9cd65fee7f5ddb4e84bbb33a40d82c2e3ebefea8a5c97ab476fe65cd051d6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304141454144313236314542453737464331303636354646333239344241323832324146323644334344464335433937363535393132374532313730423933463735333042424341433034424133384541333131443532383045303733323942363245424630413745323145343134333434424632414341424630323234453833433937423030333133424146343742374239443238303334344232464630453144463643384641443134453633333034433542453431363738343745383235343942394236383535463446453143434337323831353636374634443333433435373732463036364331323545363244333342443044374541304232414341443123290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x6cc39f3bde6555135c10676072c21f3166e79f892a7b6ce68c48164ed7ace4793926ca5a2ac490795eee222758b98d747d68ddf84a917ea7c1766cf80cf88608	1568852781000000	1569457581000000	1631924781000000	1663460781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f9fff3f37b33f3bad5e4dd9ab7fd050250f1e8d65bbef8cb1b10b1e131b1168a356de37b936d2274aba86dcfae48cafc956e3a2f4b75634ce36d623bc1cd09f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143313445303538323633433533383335413746383642394642424542323243333743394637424343393236353133383743424342344644423832314341324231413037414533463032443642374644324333453839323244373645344334314136394446353138343638383138453830433737374641383633453638463930333545433441333241374338363739454333303742343137423532383441453438334438343237323945383438454642453637394230363944463931353736304239373838373034333937373230383037463644414234363432434643384441433930333946324537353934303636343938443336454439354444314336344623290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\x18b17041d499f1c2c4ada4e2f8d3b25f588390dc6fd0aac0ecd47f2a0385099763509c33b78cbd4368e80ecde6608d87b6155f42b44f79f723fdddae8bf7f609	1570061781000000	1570666581000000	1633133781000000	1664669781000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08478bfffdfa2c92b604ad44d10da79f13518823af2f0ff3714e8d4bf8774ae5eb243dd1f2fa0f69ef14de0a4e867e39141e8d716e83a7d5844c1727cdca54a0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334303645373136433646383841313131413136393230324630333841314438413741394238453835304245413341383646423541444136323743313532373334313739393534433331333930323542364630364633463532394636383041314538353837314233374242303134384638393134373336393633323344463438384434323544463346383034454534313833393838394139363944423342424441314536464445384132443545314332363233414631424637363931413844323245393344354230464537434638414432393633443436383343463746394241314143424239333541373833374242453736333336374642334445443732344223290a20202865202330313030303123290a2020290a20290a	\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xc04934cfeb13d10f9ff73ffea21d7fdfcca445990070f13cb8c218d5ec5771c4ddc405109fb951cf95a67c5355d83a4cb3aa784fd4e25d5fe9a4af4de688360d	1569457281000000	1570062081000000	1632529281000000	1664065281000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\xdeb036fc45154eed620c6a5fb54f67a1c9735a7a59770d94e5be250a45d59818	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x31bc546bec7ca702eaff530104f2d43b090c8057d279844e8f2106775ded81369362fc3aa22498f988251b64a4e428e10dd8780876b7674a4b95725c4f2e7703	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
2	\\x9b6af0094b3edb8dc2ecea66a40bd7ff9079da5981d85ca96d62fc21ae9503d0	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x6b31e4d8a809b3630f065309aacb18dea638c8725531e8b2ee7582acc3bb72d395a918cdb03f3bca942ce90b97680aa8feac28f33c202aef8e721956c4fe820b	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
3	\\x7b640dc859a9a10b2e7118abdf585e74670690b258dd5ffc2303b08436dfc201	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\xe1d60433b2c2ff8ecefb9f86982b22f3b74ed4672ff405d703f58330bf81f39b1621299cbe00dab49cb875a9a300b492237c3003653437c51348dc2da8951f01	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
4	\\x6fa7b5b4923ae3255b60e5bd61ae9b14d78c4089d4b644f09b588729648a2864	2	22000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x6f675861499d7c3caef141428896dd33821d2061c0e68fe6abf2b8aa928053d1a090cd308c5261c5e4e4b853371008b4256e131ad4389395110fb62702bee907	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
5	\\x05fb2fe2e2c4964ad16a5eb16138cd142f2301cafd54aa90eea078ca7b0d453d	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\xc4604330c16f1aec99af7a902f3fd245c7db3d5d1b2bb19624b4fd1abdb2541599d3ec4ebebe5a0867ae5d32877633e6ee1263988600dccef1e156e98fe88706	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
6	\\xa16921c7f6befb8dc0b8bcbaa1f34e789a75bfeb9e77a6b9fe5bd7f8f9317219	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x2bc3ab4faab565aaade860572e6d40e43c4b43c4cfb85cf3202a058d8b2bcead59a92434ae87a3f17b9d03b55fcef7fb73af941c682356bd18f2f5a2f61bc800	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
7	\\xf2d3979554411de2b0253a6e253bd4d81961ac5ab704362d27077235bac385e5	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x8fe5c9193a779f39a80254b247df83e3e92d5400af7f6db26da45a1c3bff30d0459c3e4593f73b11dea122947a38dc7e8d6cb891b1acb315924593c5e0233b0c	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
8	\\xba8ce25398da5c47e7da660b871baaa1412dda4085304a6011fc7376889958a5	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x86285c64c7ef9f4ebeb90ad8087fd5b0fa0665e8855f1c843224216e2fd84698858328aa84a02c839002b7e14862e59a2c66fa3271cf8f6aa4a3905420cf4804	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
9	\\x83f76727b012ffde97b6f136e4f5f2a93267de22286c32826eca4dafa94c2270	1	0	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x8da2d629ba50ffc01c39f768e5c336ab2c6e26717c16f57869de87704c1d6a55519b67137d93ea39c4f4c4088dac89b6a5c92abd19ff8e8d555c5fda4b6c0a05	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
10	\\xa597c08644d255a6f6fe23adcc0c7dbdd563c182b456047d42ab85955072b2f0	0	10000000	1567643813000000	0	1567643873000000	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\x07168aac3db1238b5c06df4a113a6b2ada3af029651a8024e49b17cac0d8b33a1ef4a4e17e73afd85d52e51ac6f0d2829c1803c69e5f24d8b55f16cd38193ddb	\\x8d6a25d3a07be79c53da8c22b3245e79f54923652bff665ada5968afcb3dd652fc8bdca41ddbe26a30e8766b78ad5cdace24dc67a5f82c208aa8fc739f71080d	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"EQZ0MJWYYCN96R0ANVFAYN7A5G48B2TX1W1205CXW721C7A7P1RZBS7F7ZCEHZX95VR7FZ0FNA0NM1GQ5PPWSFXPZ91FCE2P808K950"}	f	f
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
1	contenttypes	0001_initial	2019-09-05 02:36:39.94563+02
2	auth	0001_initial	2019-09-05 02:36:40.661237+02
3	app	0001_initial	2019-09-05 02:36:42.061004+02
4	contenttypes	0002_remove_content_type_name	2019-09-05 02:36:42.284947+02
5	auth	0002_alter_permission_name_max_length	2019-09-05 02:36:42.297545+02
6	auth	0003_alter_user_email_max_length	2019-09-05 02:36:42.316011+02
7	auth	0004_alter_user_username_opts	2019-09-05 02:36:42.344901+02
8	auth	0005_alter_user_last_login_null	2019-09-05 02:36:42.371184+02
9	auth	0006_require_contenttypes_0002	2019-09-05 02:36:42.381845+02
10	auth	0007_alter_validators_add_error_messages	2019-09-05 02:36:42.407303+02
11	auth	0008_alter_user_username_max_length	2019-09-05 02:36:42.465224+02
12	auth	0009_alter_user_last_name_max_length	2019-09-05 02:36:42.500496+02
13	auth	0010_alter_group_name_max_length	2019-09-05 02:36:42.535179+02
14	auth	0011_update_proxy_permissions	2019-09-05 02:36:42.562994+02
15	sessions	0001_initial	2019-09-05 02:36:42.655181+02
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
\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x2295696741d8abbb90f8eddec04a8a23b6288da1634b0da3318b4dbfdba1afd70b06b95e9c33afc2c958893ddc60f16f5d098c024aa5bb7fb39b2513a0b33e01
\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x26a35c254b7deab27311c824f9a6eba9cc913ac985695c0f72aadd13814efcf8b55a2134ec60da1fb7339822d54e116726f1d171bcb55deb4d45d4c2552f120b
\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x99f94331a0494cb6b279ddc13f5da7e9e057c17bb010f024ceaf89ce4b5594cc2b25ba7d3eed2c1c538cbe0fff745ca62ea139fdea79adffbac2dbc7612d4707
\\xf2710ae8f3e74c955fdd8bf80be4c0699fc3ff3306343e34a778528edfc3460e	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x730650b810b9689cde17adcd1bd08fe3a24262a024d6adc3a430c0c3e992ba8280add9cd8ba5545a71460658f895fe6f1cfd7ab1ebeb4b22e0ef6bf7af4d3e09
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\xdeb036fc45154eed620c6a5fb54f67a1c9735a7a59770d94e5be250a45d59818	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233631413434324244433342414330314246364132324238363942374446413039453934453042443146353437363632454533373839303032374536453438463631313046423841383533314632463537313935443046363335374631343443384137393933394537413536304333364132343935304135393434374438314642434635344142433134333030443936303744313143444634333044424430333845343337323443383438364641383541373032444533353944323135354544344433354543414146353635363635464238383538443539433736303941393241313235313230454331344333393644303833384236304531343431463932433723290a2020290a20290a
\\x9b6af0094b3edb8dc2ecea66a40bd7ff9079da5981d85ca96d62fc21ae9503d0	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233644303446414642303146353635423037423538383833304337303844443246383731313243324243433239383032444132374336333844464632414343344536313933393443464241313645364545414636394535363143314334323630353441394546364645423442364139434133363143424142344434303145334630383641393746373246384343413141424331453335333946313038463630353135434141444431344437434130373932343930314442383730323339333638463744333230324539323330334145313344453137463244324344373734413341393136433246303439373941334231454644343933343745363634364133463823290a2020290a20290a
\\x7b640dc859a9a10b2e7118abdf585e74670690b258dd5ffc2303b08436dfc201	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320234233393238413238453644383630413231363641323638354442364435423131354639314346364233383731413042323930344533444243414535324444454332303430393634363038434535353941343231323432343239464436373438344230434632353136333835453444313336393946444431434445333930364334433134343735414638383641374239323841323433444331303331313039333632354644433541353837454433394637343341433842363630323745384536433439313634353430363046413246324641304231463839394136344539443335443936434333383432323033323035393745303530424637413541433330434223290a2020290a20290a
\\x6fa7b5b4923ae3255b60e5bd61ae9b14d78c4089d4b644f09b588729648a2864	\\xd0de7270c1520cde62ec903a1cf6d1eebc53feb9433a3459cd45ec6a1c42461ad22aa1a95d1e8210512a898f5c7c14ba79d1658a831ab6df3ea968e19c1677fb	\\x287369672d76616c200a2028727361200a2020287320233330343745323536324234384637354638463035334241304343453832323731363042453241353533443933343646344235304238313541313236363343303638414530413335413446353131354233413243323043323841333835433632303533413431423138323338353939334536303538423131433442333846363139463534444237343238343544313446434438464134414630313643384144343331383232343239344138374643303341374645313838354339343537304333344343464132413133314143373530353946453132383744363334363038434434393732463443464142393039314632353131333346433336334635313739343823290a2020290a20290a
\\x05fb2fe2e2c4964ad16a5eb16138cd142f2301cafd54aa90eea078ca7b0d453d	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233930424142423632463232304244413736373132433741434641303138424336383532454538453845454343303245464132443141394634364430463332413743393938353531393243314644423941324234354546444645363146344630364233353143333342464645323141434239413037423636414132413042303937374337423842333935323033433645463541424431393137304533373844304437304638463734413432393545434631464543374530454641464431313835454137453836463133354138303339333343444130313043304238334434343842303536423043454642394642334630393435384133423037333646384442373723290a2020290a20290a
\\xa16921c7f6befb8dc0b8bcbaa1f34e789a75bfeb9e77a6b9fe5bd7f8f9317219	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320234139414343304434393539383543454435343939353839424230414237343636424432394542463238333438344631393344314234323342443339384133393241464230443835333646314641444539423339313136344536373931463439433433374436394237393732364333363241354244453334393841393645413832353835393735333936463338344135463745353345383633383943363933303431313831374145394442424134384439433836384141334546443642363237423236444636313035374134383933334545443739374238424643343830303044334142393430394441454441374446463633343533363737424432323246393923290a2020290a20290a
\\xf2d3979554411de2b0253a6e253bd4d81961ac5ab704362d27077235bac385e5	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233132393935353646323045304243333236394138333237463931393033313935434133434542384234443633423137373433384131363543323437314142344538373630423130353743373335383136364231384432303238324231394230324431413433393739304543393643334341423743424537363936303839413639454336434242444643303545314332464430323435363637353831364643463443423138394545313941453630353244444445373043464239343437434344383443354242424233413938453543354432463638443246343832353235463535384534453937304437433733353637383642354233374131374643353842353223290a2020290a20290a
\\xba8ce25398da5c47e7da660b871baaa1412dda4085304a6011fc7376889958a5	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233243413543454342354234343634393435423646383338463738304434334444323442444132313446454145433538453336314335384444413834323638304544394535373641373037463830444434363733354544453532443537353044443245323332454137414339334243463433353337343737463139433941323232393138343430394232444638443335323044323437323336353431313742384137454237323139383831443233324431374242343733374438384134343243343546383742333846423635334535333846353342344436333034453138383541413433333446373043313232334630444331423935434135364334313735463823290a2020290a20290a
\\x83f76727b012ffde97b6f136e4f5f2a93267de22286c32826eca4dafa94c2270	\\x6aac86f2f844eb38e3649c419f5739120d5fc105c6d57a257e8921784a18a2e62f799be812aac4a3e09ff6bd3b8ffa2ccd1a79b3a9d838d38b3020a2edac53ae	\\x287369672d76616c200a2028727361200a2020287320233143313137424641384335383232373741374535344436424336393937464236384646313141314231374434354336313144363132393039343531394144414438363631303542383038324538453239343844384446393932363732413735363832343646323534463632443841303845394146464443453337303032414345344446463436433738383546333836424331353144323036324532324237433336463835434543313734433531453939314442423135303146333330354441343138413736444644374130423341334446304237333634343134344446384542413338434636334237324342464146314236393942463034363445303244424123290a2020290a20290a
\\xa597c08644d255a6f6fe23adcc0c7dbdd563c182b456047d42ab85955072b2f0	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233141453734334446374341353638344444383132444433453732453330364646413334343333373442393637414145354330453533364637424335444546304141463837433239363737383444323532454646383138313530303839414236383133354137353133323643423738463536383945314145353935414443433330343339373433344236413042314632383337424233313832453332354131384532343644353533383235444134443033453634354645353138343235343742444332413742363530333342433332453835374444423839334344314643363934383543394337393841393146334241313646363335443441343344444631334323290a2020290a20290a
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
2019.248.02.36.53-02W8AEHNV919T	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e30322e33362e35332d303257384145484e5639313954222c2274696d657374616d70223a222f446174652831353637363433383133292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373330323133292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22593952474e54374b5758363941515958484657305153363044364657375a534b3052543357443537463139385851593338523730227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22305742384e42315850344852505130365658353132454b42354244334e573139434d4438303937344b4342574e473652504358315858353457355a3737425952424e394541365036593339383537305230463339575153345632544e593550443730434b565052222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224d5154313039454a4848535933344b4d5a4a50364b5332425432533745545246444659584e58475346545a4d435a5748374d3347222c226e6f6e6365223a22445336525938313738424e42393737535759343431344637355a36444d344a52533841453945305a4e30304b4843353041414547227d	\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	1567643813000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\xdeb036fc45154eed620c6a5fb54f67a1c9735a7a59770d94e5be250a45d59818	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22504b38514452334551373441363558384e5a56415759375750533143584e52335848503837325a4e4248334848573258524751384844444d5843535644504b4338593647543338484b363134354430454645453358365239354246504250595348594456453252222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x9b6af0094b3edb8dc2ecea66a40bd7ff9079da5981d85ca96d62fc21ae9503d0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232594a53465652364141435844314a5a4552315731464851314134313937463053574441323837463957504b314a5850515745313432514a4a534b47434431364e30333835434341443544434b5134324541463633443748444257574e463050325a504d543352222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x7b640dc859a9a10b2e7118abdf585e74670690b258dd5ffc2303b08436dfc201	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d413652504150455031354d43344e5837575844365a37384430314435385234334d484b4756343733343530515150375936444445584d514536544b505a5a364a465743473036575a354630595950365a4e594135434d5738374b4331354b56414e4b4d453147222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x6fa7b5b4923ae3255b60e5bd61ae9b14d78c4089d4b644f09b588729648a2864	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2257585150384e5750374834374732594144415a534a4454484148505231573350394d4837324d50544d543336425a5a4e334b4b3956515a4754334542424d3644384750474752423834544e393031395a434d43543130443435395658524844574837594e343138222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x05fb2fe2e2c4964ad16a5eb16138cd142f2301cafd54aa90eea078ca7b0d453d	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a51464e37334a305a4444463352395945314e5a414b45575a35334b313141394a304734364a4643334347513858463153425931313733394742484d443952434b4d3231375643414b4a443435423046473046574833415a3133594253584552584e594a453330222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\xa16921c7f6befb8dc0b8bcbaa1f34e789a75bfeb9e77a6b9fe5bd7f8f9317219	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22314a424b4a545950393630304738365a5743395a305030564e5a5150524e5a375a384b44314d424658383639584458464d5135365430514d4d56334b46584a5a334647575831513347514a34375a5356394439584e344750334b5846383744365a525939573138222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\xf2d3979554411de2b0253a6e253bd4d81961ac5ab704362d27077235bac385e5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225059573934335441524a48324841303046323438593730484a4b47415a37324a51464e54444e5153444a4e4e30535148564646503551513134565856424b45394a325354354e3258444a50435750584a525653355443444b364b3156475a3238533041444d3130222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\xba8ce25398da5c47e7da660b871baaa1412dda4085304a6011fc7376889958a5	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224533344e3330445452423256464e505338424e314441303543443438314154514151314a335a305a50564b4d385053334b354136595a3654465642473146455639355635434a303258394838585445344e335041564235484d30323553545a4b524e42574d3052222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x83f76727b012ffde97b6f136e4f5f2a93267de22286c32826eca4dafa94c2270	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2230354e5257455948534246304548444e59545632593130594a4b374759394b355a51363845344e574b4832544643313351505a30593941355041485343435954424245484356383452434656355936483252474457474a5a594d56505442325935473941343330222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\\x4851ca19ed6bfd921fccabb201752cfa1e9f59a8eee3a059ef2dd84981dfd31e8fdacc85ded53613ad4a99215a7ff11d77bd4e360a76bbb2e24aab6a9f900547	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\xa597c08644d255a6f6fe23adcc0c7dbdd563c182b456047d42ab85955072b2f0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd60e283ddd3982ee032e1ef1e650d08af0ba2a00c0ba41b3058d2f7b0be35ebd	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2233454a384835385431454e52434d3144563742523341394234434545393754483336574d43564538453636544a56304a4d31485932574d38513644445059443557475a46514557573933455035543858324b41333333314b543744344d313131434a4238573130222c22707562223a225452373247464558373631455730534533565259434d3647484252424d4147305232583433435235484d515150325a3342545947227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.248.02.36.53-02W8AEHNV919T	\\xa5f41025d28c73e19274fcac69e44bd0b2776b0f6bfddaf6197ebf467f913d07	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e30322e33362e35332d303257384145484e5639313954222c2274696d657374616d70223a222f446174652831353637363433383133292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373330323133292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22593952474e54374b5758363941515958484657305153363044364657375a534b3052543357443537463139385851593338523730227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22305742384e42315850344852505130365658353132454b42354244334e573139434d4438303937344b4342574e473652504358315858353457355a3737425952424e394541365036593339383537305230463339575153345632544e593550443730434b565052222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224d5154313039454a4848535933344b4d5a4a50364b5332425432533745545246444659584e58475346545a4d435a5748374d3347227d	1567643813000000
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
1	\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	\\x6fa7b5b4923ae3255b60e5bd61ae9b14d78c4089d4b644f09b588729648a2864	\\xa1ec6dde7447d472110df45dac74913b34e26d76012be517cfb70eaeee1eb718e220bb6c97a727322cdfb596e04113d3a7498f862906db16af28b8b8bdf22c06	5	78000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	0	\\xd34104352c2a1fd071305545d6e36f81ca6f31d8306ef8465a6859bcb10f5e85add02f8b38caafd4fd181976fe156a0c8f59dd4b419692c1670f0e8aae169a04	\\x58c385b1a09d7cb925dbe71dc1526f2321895739b803294d221392f301701634dc28f8abbd8833220fe27606a078d5dc16541e1ec5f3c6c535439fb3059dacd8	\\x6ae5b00f72f4ade6658227350b727b7526c713f0c435567cf48a6d844544728687329aa18c4a120562191eb88dbea36d9271b69510d3981c08cb43a2f9d6dd00407b9abfff41fd35d14753c8ab048b4612c2af144634fa26945c638ef7ec149c211eff01651e353981aa8832ed33578264d7ed3ef184dadbbd8d667b911871d1	\\x3c128d202a3294e94e88dd509f40db7e6d2a2e5897f760ae8c1358e1827175e70e02c4fab618d193d41acb597f92e68cc8838e4e3f40d72e56ce4ffc10fcb8a1	\\x287369672d76616c200a2028727361200a2020287320233738313230464237333346444141393333343730453943434135334346373432323431323237423032323744304445303732303845434344383533423438463645434546384433454539454337363144444332343145383930314637434233443343463046463642453833314132333833423839364333423633383230443734433032363344434431393445354530333932463331344634413431323345424242334542443343314533363846434346303032434530333838343235383334334131464344344445453932423642424432334137444136354430353946303832344645424342434141373846323342374538334437324241363139314537343023290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	1	\\xe86053956c4cb00273f85ecc1d12a19a555acea59751f85a6739e1be5e137326316c890c63374db249ed5bd52c0cfbdf533bdb8250cd31ba3154f2d6c601d109	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x48cacf0f9f849e9ff96bdffbdda80d2972a38c29d614d8a11ae3c2d78befac60a691f168d47fd977cb0a9f89db81b0e9681514b11da92a756445b5e5c703e475ceb1ab6578a653a6ad9734d18eb0ac608eab852cefa67624d48b8628a207543c42314dca598dd9de0c9fd2e3e86a92cb9b047dd9b552f1a1776c190e3f29d877	\\x22451087a19e7d16a0245e0701c601af0ac57b0fa270a0937362d80710e53cfcfc3dff24dc8f22636a1d58ec78df4d99014c61ce91672c5a568108e5e16b0e10	\\x287369672d76616c200a2028727361200a2020287320233331323243363543344546384135453245393133383541353043443146363635314132464235443941424533314342393243414441314345443142303935313030314439334345324344443434443932434444343335353531323638434530343035464636303944453233463937373230314434373445313333304443334142414636303331443236383544463039414644383744464231424446343232443132343935313942423546394231324233383432394646324533384138443244423446323436374437324236454633343739453537423835343131443743354542314141394539414141363539313936364237383739414435363236464446373823290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	2	\\x446d0b6a172317de9f67c2a201f17995daa334c9e2305dae9c9908c48121890f2d4ba7e41f8c2f40fb7e5937d54ea76b28ad0cc2cd9eeb0d730a77971e556002	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x070adeb4ee9c53b3e235c8f03397b9af0f63761e2b8a23ba9ae25292dd2188f643ebb33dd0f03cd12d7805f8321fb5400044b7f62ead4a0d78b70a746047c9fda1b054233400eae6feb44988219342bcd6735db69668f1d5a7ea66fae122b53a81ce236c6fd3e7c21403e46a2831537a7313093018c64fe834fde96e5362ccd0	\\x60060dc74e848e1d0c10ad3d3cbf1e1fd0eb6de988ff8ed0e7f1178ead02238beea3ea99efff667271ef42e5502bac945b949612d766154ba3d433fda875dafc	\\x287369672d76616c200a2028727361200a2020287320233335304433424232433137374238443144423531363730413338464139323436383433433730443930413033373433454635363544363530443836413141464643413946363942353035323730313835333941353237373545304546463135303041444138313643334336333034354236323537454238334637304332454431354146453838374535463533333237363045423436343844454530464233464135444344423136394442413737373930393137453146344438354633373244383338353244414639344444303941463838313934433143353834363532353333394236453843413038343446313932433132313933373930324330413342393623290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	3	\\x10d3123dab4edfd929127d7064e0a22944318a496a2c7b18a049bfc2e805f27487746421105b15ef78dc0a2a1ffde90196a88ed6230cfd2a4cdee73ec54c6202	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x560c9a60780e0e73c849a1fd4307bb04c0de6c6e88283b9c0c5f625fbfc4db6d792a4f81e9d370ff02ab4a07d0d326aa1b900f39001be95a310c98c9182f0dfda6f5f44cc41af99772681b2bd80477f3f64d7387fbd85039239b2b1173d3c81a24f9f530ea5113859ed59656e076ec3243e2ecfd6c04700589b960709d136eba	\\x6b7a1c9ae613f095a1332c06a5cad22b6379957d8eea581402567f2366da080ec99a4baab02974265ab8fc514cb126ef81962e61a78868cf80c661bfd48849dc	\\x287369672d76616c200a2028727361200a2020287320233043324242323135383241353546463535343041303741414538424537413739384237464535413631433741363731383136373134343041353341413837314446313446364143303241434134303037313043343634304239383839354232343846333934374441414236433845453839444332433532393436343046444236463546344542413946334244313437414630383138313143343646443439344241303036454336303638344138413846414345383532313537413741433139353042464346313530374233413845354543424331373532373445383335364135333745333938393535313132433132373343343630374544324444364544363023290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	4	\\x2183685b29ed6c7d969fe1f01eb0913cc4315781f250f4acce443345916937f988f83499701d3f6bc930c3c8c49dccb1b32a178126552447d5b3f86b6bf6c50d	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x509759f846ad7dab5c669058f4a20b84ef15f9fe8a0b40467021b4c417ab33014e5898fa8c1b1a864f9eae87868a7d0cbb455fd8886e41c60d4f46772d59bb99c47bbe3c11b49a9942cd46808a682430f716de450e0890c70a42244c75758cb68980c986d3044df0b5f4c0cdbe5f4403550d4d42bc8316aa227e65930e851521	\\x34bef4a8178eee7008ee1d0e7ac66642f64b406821856c9b432fa5229e953d5f7000c2534e4819057929b27cbd1367e5c9ebd16bd941bb615a42ced6d09bc1dd	\\x287369672d76616c200a2028727361200a2020287320233434304336313835434439324645394235454238453442313934464342424643313231454630433032334538343235453241344530393835304146313232433234463338423941344338334231383837363733353041363034383036394444323145373638303141433441374637423836313838313241344633413538393941444343453734413034344136453130453535393946304137443039353242374334394434303239444346354131323836393038373934413043353235353033384339443745384436304243314438393644443730424345433230333243304536443134304230464130434437423942344135383335464344354537454246343523290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	5	\\x84319f76d4dcf081f72266df78abc3c45be1a52b16d1373f608bab1816bb4013bf6ccc15b295f734edc41ec63b414af1b76a2dd0c8702c589efb8a18e07df508	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x7a889b5b594ef6160e03fb45458b39f8f47997653f0a16542985cf1026e80947e3def3e153761e8033c92a7727653924a24e285261f3ac66d7dcfbc6c2ebdb84d81bd1069fbcb5ab376d355744286bc1d567ce2b1ce26687a54e6a6b8a956217a3bdb6ead0fbcbdfbfcfa756a3f69f49cf8e050ec21ffa034d41600c8e301712	\\x50bd7743495bd6f08806fb808e61091a79a32e6145a15d8b89ce457ba484deb1167a650b11e2d84bcfff4761caf00b6864357ffda58d02526f07177950c66d19	\\x287369672d76616c200a2028727361200a2020287320233142413635413530353832343143414542383146414643333738433241433335323241373834393937433734393638423337313636373135313532393132304246444341444533323231374643354438364141323538314542423836383933423138453236384445463541323845364636354344463044324639333643383845323737334534383034433330353735383346314438313137343832373543353446363346344232344231353544334246423346383334373735313435313944434230444137373835383341394442433346333745443934323344364230353142464130353035303531323945343546363242463944384544383432423245313823290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	6	\\xe9e678b722d446b5b3f3528e08848724d32107c40fa58fd8012d8e6d12fa468cc8647ff0370533ffe627bb0e253976c06f0643a43002a378b43d81e0c95e8803	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\xabf39024b8559a3f5b680f8475002694c8b0fcdb12e7d86554a0a7e4c962e2494737d512d8a94cc6f48d10612e5e4454f0aeac6136e1a2e289a4f6d8a7c08f0df9df16997fc878155f13b9d6ea539af1fc60a9a8f9033e6e572f7bc17b7fe63232a3903f45fd21fb1e626ec39e7a61e40fddaeb6b35285b752a4e73ffa4c8c66	\\xa3671ff23e838b2565c152e96b589463eea43534dc9add089dc5d0c090356b3948e29d0f29f84d034eb56efa86284a0dcf59663ef9390b61ec6b45c9fad2c036	\\x287369672d76616c200a2028727361200a2020287320233244394442453733453845333642364330343234423646383041374232423042363546334643414443453746443837443534353544383438314645313543303441444237464444393641363844313835463037413641464541433642453231323041423136463536324339393538333245393543343745394439383931453746344533324337323343384641394234414136394235343434333546353834343633374436304632363432364245313644343832373731393642323332443346363345304436383142303334393235443845373035463631363943323144344545443036393543463734363838364530373731323730344238303635383939393823290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	7	\\x7ab25e9483a9567274fecde2afc1cf6a0778033cfbe79e7b557ec389039e80fab6075983cfc4193eb9c134535beac910b08d9669322db0c9c0c360dd3aaffc01	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x33793395194660dd6060e87d47dbd793d34b18aefa7b8741339ef87c4ef048e2c6b878d73459611421438cf6eb0b0be0c6990d456d3d8e4c45a1382e52d1b00f0a4b0b663e35d0255a63e6d6ccc4ecbd59578633388b97f736a630d8a21c0bc0b8459136cb4489fa5599f5fc4996e728e64552e5ec8fa7508d0a482ff91bbc4d	\\x220ef36ff01c23b9f12950b12cb6525f1626ff7f90b5d850c2fa3f226569abcd91fdd758450b7a142e8c496134f4a8db681759d0334215cfd068e798f77af600	\\x287369672d76616c200a2028727361200a2020287320233735423835343339433338383435354231424131304243444139313533463932304137434631414639424546413932313042313145324333314530343233303535303839443333333145314241393245444443323745323841353841363432353246433045363442303938354231334434424246454534463446364138323531373633444346374139364137393342354631423033424246443631383442384537393631353032304635414433323436443834344243453942313635443738433831304346444230433441343639434636363732313746434538324336363838463742303533433531453837444235463133334432443832464435444338414423290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	8	\\x0dbd5172fe213a68f99c01b9cb3d75be364536eb0dfe176869292a0766f292bf8840fcc912811aca2f0172d14310be634be83934fad030eb49176d67f7dfe401	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x519e38e18061abc97d7f4be27d97e9e2ca6ccd18dbec3b05d988a57b8c2adfeabf5ee3f240515aba91202719367453973c9b6a2f7ef8117df35e21b734129ed1f540082f4ae0ab14217ca1da4f641ecdecbef71963c473dcb0ff06cbbc2eb28f4fd2849a2a8c46b916b200fe7206072125fa89d90619163c658d68d19a6523e0	\\x15738b30aba41b2bebd457dde173af66da3c16ae919acbd458de96a575c30cec8ec6002e464f07ebfe87b18f2fe0f162440f4ddb2e9b0e5b0fd3cbed445d9895	\\x287369672d76616c200a2028727361200a2020287320233930303036414246423244374635304136363239363246334437394243413744434236393746413235383733314444414238454631344533453041464231453945374237423032394644394644303537453044344631344542304531423139304430393031343133314141463539323931333741333046313537414336333941303444424333354533384632323733333246333139314538463933434235443642454541353144383537354444313345383139433939333336394332373445343536413843423733344230454434303939423646413137344630413236393131464133383935344431423034333037444436373845394135423136413133453223290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	9	\\x67f5bd7794014639803e2726b7ff0b9e235ce157326be8f2f45328ffb5ff5d55cd56d9f337f3a06262fa43e0b3960e3b0f8cecb11609b06b0f00f0cc26108d02	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x5d83ee5ab29304b5a9d67b3808f1433e152dc2ed8845a7632261edaa9292f4f69aa61dc18b3a6141d7b8ca79024a5f9ee1b81288f0a44a0a9f2e383ac6209345c6d0d38e672f830c52d10f2ac8574896d4b22eab5fc29b9b3ebdf7e7d3bf010a3fb45a7f3679fc464e5802dc0987c586d0a4951f3c2f404d018d985038622eb0	\\xf2cc45acbc729fe858a8658c8728a25aad4ba05063bd1f56cd333b80243def2023e135d606d2ff713ab35e1b617c0644d524b705ccd0842db121f59b760331f5	\\x287369672d76616c200a2028727361200a2020287320233146384439313744314145313235313741353734343432453432383931354232354441414444343046353135434333393734303932414643413535413645433146383135323641394646433533413543443730413732384534323230443132434439424445453644433335384630413046353343324134464434313539334145424136344241394541454631303344423230304144323945373645343742303445324134373836423638333633464242344145363931314641393335383835433741304646363343344145303336373742353642323432373233324633323533444139443236344530433534393933364245324232303941413745393333423923290a2020290a20290a
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	10	\\x1deef9bc0bce231880b414bb39f57a1122fe02ad73c8170760cccf147d03ff87cff11505c7d7e64afe05cd7a8b9686c8aef5751b37fd8cd29f57ec0ba21f220f	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x52f2b811cb89193c65906f1f0520575e53ee8ff8ff356736f9dd34b68cfb9a9a9b90971356d2760259ce3947389f543d5642351fb029cdc12d66686acd37c9cb1653cd4208866666752f0d6f43ffeadd07492ead2ec8927a9f8f28f5d56144a858a934a236a0cd333ec3bc8a884a7b4b417811daedf64409972dc7d4b6f27792	\\x12e7c29eb028d636581424d290e6b6a43a061e09c2c8ae47b93c593e3e32dc4b48ccc53020f2bb79565138925745a4fdb24dd4ae63cb4b17d406b003a3a4e0ce	\\x287369672d76616c200a2028727361200a2020287320233034364546383839413345443839323138364331454634383434414136343730414344324442363634364146323645384143363331333738454530423533393731433542323333333438453238373939334446444335363239303844393741443738434246374645453733413741304646344439353930443434453644383434383942323633463841334431363241373138343331364145453739433134464534374641323444413145364333333634414343333339444631343645354135373131394132334330453930313446323732463345324138363034414445373443373331423737443336303236344538303533453945453041324136313034324423290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x038cd228f46d352cce867a48d383d62071147876c5f79350ef49a9887395e05e5589048a1a850918168077642832cd405499d8c09838f677cd6934b60e8c7c20	\\x3d121a5a1881dcfa3ef4bfcdb38835ac8baeb109d150d7ce344e767ed69eabcd	\\xef0cb55926dd44d6550c2b17b08686fdea61aa3c4919ae3be692f66bfa81f5c843def2212d10423525db11831cc31cb16fdee27cff9ccd99675ef420a5388fd0
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
\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	payto://x-taler-bank/localhost:8082/9	0	1000000	1570063011000000	1788395813000000
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
1	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1567643811000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x9299e7b19f6f60fc3656a2adc4959a46a0d8b5f94e36ba76a520da424d50929f391419aae0f43844ec89b83059bbd3faffd47e84bba55cb9d28ae3c358084efd	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233241423735394143464235423232463841393930423837413346453443343639463945454332373644323543363235413044313143304636363734363330303342414530333945384436373934343131414533353433313844313333393543343036423633333537444644344334334641433836423142323130363037413638323443333342313344384146363237413033323036353730433635333932323542414237373242464635304130413530464638384636464537303342423032444332303930324442354133453731383334304639363139333434363541394546433045444135363931383644324132344433463538313631364632313031364223290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x8a9f707942105f09ef01e0c9268ca9750ecc174d77bee2c455488e7263e7a1b00a8b7498013956426d8b6600b23742878d08f0d9c1debe57a006a4071ae9020d	1567643812000000	0	11000000
2	\\x7dd04516f6c1be86b4c2e0bfc39ae5398efad5975820c11d2bcab49d58442ecb05696dbf249abcf20092a6fae78cff03be3226210797fe4aa6202b9277e85169	\\x6aac86f2f844eb38e3649c419f5739120d5fc105c6d57a257e8921784a18a2e62f799be812aac4a3e09ff6bd3b8ffa2ccd1a79b3a9d838d38b3020a2edac53ae	\\x287369672d76616c200a2028727361200a2020287320233730334142444333324142363944424533353146433737354333453146414644444338394533433533453835303542464435444432333244373344354446373646454533393831373137463443323230393530303337313635363339383738323946413931333736383237424430424238394334394635453542343039443838453536393042373932414342363333383232344341443231344432373433354444393932303938363936323033364236413934374445313735343544364132303634314635434244334338303945434630373934433744423641453732393838414141384644303038424432393730433941373532353444313338343741433423290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xb558de2392261e5ccaeb2621a2e7af7b9fbaecb51a330576f6c323ccd8207383090d67f1623f6357d99bc360cb1bfcdf3f805792cbb0e84626cdb5c813c8ea03	1567643812000000	1	2000000
3	\\xde41156f3baa68c6651d47a468b1927c5b0ac0ed2c875602f45ab50f1689f9a0baea5c51174abaecc55adb152bb3461c568a423838f38665a644f6c03f23a640	\\xd0de7270c1520cde62ec903a1cf6d1eebc53feb9433a3459cd45ec6a1c42461ad22aa1a95d1e8210512a898f5c7c14ba79d1658a831ab6df3ea968e19c1677fb	\\x287369672d76616c200a2028727361200a2020287320233842333941393135373631323945323846374244424342413535373044363341314542463434333737443637443832353231303534383433453038413331433445443530324130344144383944374638413436354131344144353730323032453132324534353233303635373134394631453241363031353732434339444641333343453836304331343834423734314643373032454645384635303930333230433641313234414541353942324634363031333731373135444238424244443035413130353739443442373945384535463642363533343139313939413433453538383639373132374345393446364142434338344442354533394439424323290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xddd27f6c659cf6951b4dd58cc874f237b76ec89ee1da7c44b89782af95c4fc1c05cd27d03b12631b8188ea49446f1bac4609e5aa8376cdbaef6a8d9c0d9b8602	1567643812000000	8	5000000
4	\\xb1aa22b7e32c488b14b891d7954da16fccd012e8b94feee04b30832b3f27fa13772cb470741bdc5ef55d46af185a875fc7d74b824e1debeb0e7fce45356b5338	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233432464336383130314643324544334343443533303042383736423646363445423835323436304534353136354345333644363045333030354537433338453633453433344145323839413437323333373832334146463933414143334642324342394230334141433643313032313932413746353738424333334243323942353734453542314645364143333130423334313436454131363341333830324343334133373542343244353336443245383734303942383232374532463230434343463845343839454433423637394530324533413042374635414241313138373830334134453330443535374136463338304532443239384633303646364623290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x52e136c1b0dd9e641429dc1a899b498729a1dfd4aae0819cabf5c95c94bbc49811b5a69abee88029920a43755f2423d7ca19b852336cb28fe0c62be63c330c0a	1567643812000000	0	11000000
5	\\x87b72556b2857f36667c1b5c1e2253d4458b0a52a06bbf2a2d4577bc68bbba1552b9e99602f862e539df1ec4120836d9f7693fafa445a50f98904c16888406e2	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233731383336384139313646423638413544323443323434463530443233433438433343363833313643373237343942443435453737314643433645453342463736374634394441324232443445333035314145363639463343374145374542413938463035343933373235344143424541394546334444384544353044304643414245463734323231433636454233344231343132314330353042413436394446344543374338434643303244363835334338363138444438303437393442383230383943394341354446374332354132333436303135323633443838463239433730323334453443373137314142433641423042394332313030363436304123290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xcaf4db9370f72e9f3dbaddf20b1d3bdd2b12c7fa047675266dfbd66b24fc1148dbe08d99115b9f8bd87b0fb74aa92e359aa862dcad8fb87270b86d0d15d44601	1567643812000000	0	11000000
6	\\xd8b42621e4e26d42ddbd0457df55d8ea78050677cdbaecc871395fcb03321bf83cc9a3c0ad0a91db42894affad8ca8cb78d3e464cea3613ee50a1b1aaa6d702f	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233239373746464434383330393431414635363142354345444531323231344642333339303739433533423442424245443242443346424646454341313743333935333942443635373339384633414332303542373734303132354632303836334546323446384237453338304145453235383931334144354342323543373837433337414231333130423137373235443632344437303741383639323638453838374342433346363639424143413035413145453746453734354133413438413330373144343235394332384243353934353136373433443643333334423330354239443630384433363134444642313939303039393734344336343931313523290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x56f8829d727de4de32f3ad7172c9d3f0890451f61564383025b4a0e964b20c762956736e188eef5d3da1682d1d86048412751c8d1c48ea9968f6de1d9a553d0f	1567643812000000	0	11000000
7	\\x86935a2a87956c45bf8600024f8781f3357a5064008af2de3bda703e28a891d8a794703a970a01779d17226835a7d66caa45a13ff9655776579e1c73612bdd4f	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233236303832323239383343414635363743314437353245454537363733413732304536363038383636313836334435443630373036423541364439443531463535423744314141374639444530413642344233464346314534373845314232463633443642434333414433354337463943333437343936313337414531333835334539443131333939354535413334463344334333304443354139453944393837413036453646303932303845354441393031303742464445314646434141453632363938334346313145384246463839373234464344324133333041454341423245394544464137304441334633423335353538354634303232433539323023290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x490e4cb39fbc2f1452b82aed20d5dec5c91c4d925d4a7795738f97033579e1288f5d63d7c56fccf8b5970a4892b39299ed9ec4d6e6b72280798b245f7508ef00	1567643812000000	0	11000000
8	\\xf038a8db280971d18f1bd26b6957d14ec2462f1c5c77f87d535b308d932701cbcea55a5b64bf2c203603286ff119ffe3e811229a32a9dfecf53d840d51274963	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233842424236323134414431383635383246463831434141383443454438393044393234393546424134373345413131434638433935373242383946454141393242393337444333413336343141383633373642324238364534433035443344313436303134464146454141423339413832463645324644374345364346414246444242393537343833323641343942334541463332363437343644373845463033343930353534453834393634304644343543333041453138344444424636443631344344423331433230303644464137323338374435343246303143354442464535463545364534453146353633354431343439413339393038394330453923290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xc38c057e3249fdd917854581b98f87a017b2f600936395ef23b4276a1e08105e58879c3a8826c5e7d40e4fa351868349db948ba0ba60a4ddc79606e4ca27b50f	1567643812000000	0	11000000
9	\\x2e064158569d60df1b922cff954fac8a962e25b0ccb58e94dedb394159f5f15e824291b393095ce5b09ac0ef44041c8a4454c0e3d6fd570d2a3404c30b099e6e	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233542443543463932433434463834433245383934353238423635444636463841333836383346433139413436444646344445444339414346334535423746353531363539324341383939313242414145443132413938443138363034323238313231453945324430413937413130343037443437333931324434393041444333363839434436433330343435414132413245343835424534433746393032343233343034344645314141303345393530464234304139453344434342423443334336363138463131433346383746413130313445433846424434373445344438354142423737303732354438374634383633393738443631443138424546393023290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xee79dae20375a69a2b81465f51af30f2aef6a84e8a9231058122222ed5bcee865ff8be6057d07c83b50ca26e32c5a07792813ce208f6964b7dd15c38d364a804	1567643813000000	0	11000000
10	\\xde1e2bda42e98df5b3db6422cf6e11d79050a66310d5396f803d0b47750bcd7d45c4ddda4fb811c346dfbf3b3c6d7f670cf732b55ceb641f13cf90cd69a7bdcd	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x287369672d76616c200a2028727361200a2020287320234133373933444339414242363538343339464637374637353545323836383730463345453731454238353631343131374236463446393141364633313137343044334238313233324431434534373144374236313330364638323637303641323146413035434339384234314541304537453136374238443631453034443032413637373030393735463731353435394330354135333035423132423733394636354138454335304538393242354433333435373336414534353444304543423743434545414343384237324637424232463633323036374431313439363337353338363937423930384535303141463542453837333438353533394137463823290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\xe2b1bded425885ce4a2e48f87d04baab338b2e4899a414f77f23c6a9f989e0235591f4b95cd96dacb17c584dc873a3c7a529eab1a0e11613238124c585d2b805	1567643813000000	0	2000000
11	\\xcf6619e371049437954e012e24fd1cfccbcd35fcead867044c239a41e07e4726157cb86291863bfc45ca8da2b68f3ec63fce2d2078eed36c26107f2b56bef217	\\xebfe48ee1483fea0e67a21293f798c5177496db674c505898a2f38e6281fdf38705775ebf33b772ad584a8a3d3d22c1e147d02f1b2e59ffdaefb1f9fc2c2d846	\\x287369672d76616c200a2028727361200a2020287320233634454334373941414535433531344335323437424242354337463134384330363442313033334338454334463141323232444638304331443842414141373638353737394645364633443237343043304343433845313034454241383243414131384238383042423842343232443436323044393335343833334446423842374531363846423341423836393432463443423033343041314133314646304143444136313342303937343734304444334245433436354343323935433232463034464142354435464435374244434330303343444136414334424433373542393530383135353131323246443534313033363030453445353933423834323923290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x34d5084bbdc2c03cf1761d4e0be8c8923f18f3d86a9756ce831204cdd753fce9f6f321e3623dd631339ebbef937a5c03cd983a438e3f9ddd47ea333a2c404e0c	1567643813000000	0	2000000
12	\\xf12f68e4a3cc1800b786bddd7a8019807a1cc78f592a36984113c6120c7be9cd08d0c2929c068cb0f19c26a75385bc9c0278fa331b028cd0eaf35ddb943a1b64	\\xb51b14fc3870731f415ebf64085cf648fdf8b289e0960eb8f64a787f90f2ee3b6fcb9efe2b4d0b6a872eba5be9e3837b6bddde5da03322640fd54821302f74f4	\\x287369672d76616c200a2028727361200a2020287320233242303742463346344232304635364332323746394531443643443232463539423844463235374238453030323130343543304442453036424131434245414636394538334645343831384642363645333931423545443637394646333331463439313246373542413938414532463437414434383631453536383937454345324544434234363039373238384543363630383939443331463530364635393837363234313245463532323535314344303231314334303335363845424437363244323832443031433930373744454443464137344346464135444339343439444533304234373235313746384136313834304344344533314430394343393323290a2020290a20290a	\\x2b6fe0facc4fe269b98b4e69bfbfb0dee79a0874df7a1d86e844e3dd1d291d12	\\x3e38ef99125b0fd1cc88161871b1976fb0186d28180682bbbd28bdc8925ccdb75eeec26eb5281e23ca63b47a7ea862f200df4d0bf6128313e901e28a0b061e05	1567643813000000	0	11000000
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

