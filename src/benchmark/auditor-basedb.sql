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
    user_id integer NOT NULL,
    amount character varying NOT NULL
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
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    credit_account_id integer NOT NULL,
    debit_account_id integer NOT NULL,
    amount character varying NOT NULL,
    cancelled boolean NOT NULL
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
    name character varying(80) NOT NULL
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
    last_name character varying(30) NOT NULL,
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

COPY public.app_bankaccount (is_public, debit, account_no, user_id, amount) FROM stdin;
t	f	3	3	TESTKUDOS:0.00
t	f	4	4	TESTKUDOS:0.00
t	f	5	5	TESTKUDOS:0.00
t	f	6	6	TESTKUDOS:0.00
t	f	7	7	TESTKUDOS:0.00
t	f	8	8	TESTKUDOS:10000000.00
t	t	1	1	TESTKUDOS:10000100.00
f	f	9	9	TESTKUDOS:90.00
t	f	2	2	TESTKUDOS:10.00
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.app_banktransaction (id, subject, date, credit_account_id, debit_account_id, amount, cancelled) FROM stdin;
1	Benevolent donation for 'Survey'	2019-09-02 03:32:22.157846+02	8	1	TESTKUDOS:10000000.00	f
2	Joining bonus	2019-09-02 03:32:31.542601+02	9	1	TESTKUDOS:100.00	f
3	950EZ8KXD1VRSN2EC2RYSY0RPEG5E1HKTQEEXG7K7MFV1A18WHQ0	2019-09-02 03:32:31.65819+02	2	9	TESTKUDOS:10.00	f
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x045ffbbfdd63a9be10ee2ea24532916da1228aea0cb039d46907c89bee4b07dd88af0f1c91ec5c7c302aff91d98cd6322cc5bcb2488b4f0e7400acee336ad7b4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05251c1faecd6d69491bd1f25c9225f2e00f67b3e931227f17b7e8978861f7cd9625f7d68c84efb216afb3c33639b95d6a311294d84610a62c1b520dbf1d4b71	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x578608dcc88dfba519a39046e31680feb64de5481eb3fe5388321d5548aa104718771ae37823aef539c572e16cd43f9536aae4ff9e1ea3616b9d3ef412473feb	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53022566c4ad9ea3f872a11bd3f8448e79bd271af180a75d3fa13cc9d10722b7fbe0e997af720c444e78bc07f8a27f963b2b2e75399d662a21dd12038d8d5f09	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde76198e28dd4bdb77de929967d8dd9798e63ca5f5a7404ddf28638c15499810a46c4eba8e9187cf11ac62653f8a020dca12bf5894f7660f1455b4a38c1b4de1	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x72a81a22a1290975168f8a28163857e7ee106e35d5b306a43d520ebe6b5163d867383f88a59dd86a7a6c86dae7645f16385e565935634ddfe7490a40c0d9aa83	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1414b0a2fa5f9533ebbaa19284fe007b225188d27cd1e3747cf3efadf3bebd4ed4a86a417a8e9bc4b16abda1ef659dd607d05f8c25fce3eabe8f8d3215d34a5	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x489789d220d5c8aea44096b677ecaa599c055cd38af2a847897e3145b9fcde6bb8fb8666c910a629312476c0d3a73fa1c49c440d6f79a1baf2ff06500d35383c	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a5288ca5f69bff33f886712e8bd19d0520a082d483ec2213a0ad70cdeb3b9af4ec4dba130a9d15d60bc5e8c36ea62250e1578d9d701256915f3b0a8ab8a2671	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf3b093e8f406e2aae985205dc3cdb85521d32fe289e11e91238decc2dfcb80c4bce54e08e4558fa994ffced9e25edcfcf61068353a82aa21a5fc8848a48b3294	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5b693bdcbb720f0cb8c513dff49b97d1fe60b45233349e36e174735b65245899115b47d9fccc6db6ffa2662244395814d1e99b7f1ccf93f7337042ec27bd17b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x062e7bee8a429cb76072d05706a643944cee2bd98b92f019c0ef11832116ce6cea0f8ecdde4f1c38c895ac3ee5f51ecc7d4950f76ec73a7bb846ee27631ad7f0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc051dbcef6cd7dc15a4ba609a835edfd6de5cb8cf68c4b4187cbe5bda668c4befa90bb9485c7cdb621561cda10e9dca7b840b0158dc31fc150c329b70765192	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4ef7b0e0ab8ae98aab7820ade60292c0ce9502f58c6f06461ecb4130ea9d6d905212afe84c227b2e835cd39b9dd4635a63cb9a8eab6f08813075ecda035d18f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x344b599b0bc5082db749ffa066e0baed7b437e1ace5d742451738211a9c9ace9a5c8a4216e20cea038ddd7383c39a6b07718ae4a81f7ee03c5043e4b64be3aa3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x68996e7b4a82e7635294f4d1605245aab31ceecb5bd317e9e5383136cc51d451b0449b667210d01564019a00e71305b679dd710b07d133bca2b02eb4f8306b31	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0cb3bdfe10ceb1b4a76f936341310f6f4e16c7db79ce1d528315e0c3c6ac07e9c3060fe54f3dc0d0ba53976035ad2420626b577b4ea026571cd36a470c140175	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ad8f448f9b0347195954e3bfd4f33e5eb8026da89be8ed08a9c9e4149e63aea14916d87590e1bfd26c73dc30a30f26a38d3d23a65836d689c3cef5d9f677a10	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x27f4502466596f8ff40281420a66b899b33547df08948350c8ccf0dc98042520b0f20ddff8122324ae50fb949607da1e4ca2ad4bd87f5c56bff0c6206687a68a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a43d5428d811f0c5ff84ac640440deaf394acf265909e96f67dc2a4010ba775bee4dc822ee680421c099b0a988f8b04f4a8916bdf1e7764cc0dc54529f44095	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf44fcadc1edab337a6e83a3786fbb4808eec15bef31cc28209a7d26d16544b36d517913fff95ea589433a974f685e3cdb79bfd102f2c051a7efb558a1f72e6e9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c72b38c9e2f7c02c165ce24be73e5a5e153155919202e78e44221eb434384c329d86dc8ab25f4bf9b8ea9babf062409d3862884df88c4f309809d93a5ef1307	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb71e590233f84dd150de67d5916ab2cf2d1b63d8d5770e4e6eaf640da9ddaa4f76c3a06790f32d97f52f5a8d596fa8cd17ffe19c83ec14e2c81fb14c420dd343	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x58aa7a7f37c48db3e1675310c23a990bd4e162732948da136984285ab3efea293aca30e53acbfaa34b4bd189f4270b43d6bc4ab67ae679dd6f1322222f264681	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2775fa71b348a4a8feaa04fcc7562f306c6379baa1a8a2c4c14df63339a865657dfe9c73712702cde9dfa240f3cf92cbc564bd03f5e68450b27d818c5709992e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0d48b76144e19b0b3c98319da87ddb113f600e06f0b659244491509abde01b8db1cfa6b988c2b2807242cf4873d9d120287f49410c565e9c3f78fd150eaa1a5	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f0320ed2a718587cdca7986e8ec8f072fd45e7156a5c0af8c47f9a5fe9a2b724a13ef21ee3117320699628044263e71106c6609b1116b0a3267199f2895ea50	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2457fe33a1d62eece92c453cd654a7d8e832a71e7c05544d5e19c1b549d8e960e9e918ac39e8010916f809219f5d083097c8e09880bee66f41d67234d1eb3364	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf443811a4907daabde45417e00f1d7c331a217752472a0f42e394e53dc29b486cb3640b185a94297b128b0fb17d0c909363262ff58807d839c94e3f9d55d1870	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x69c8a34f44aa15d18f386d9ee522442c4b438964514b63ef5d63e4756681480db290256c5fdc4a0c70fddc4ba03b699231685f6a948316bf0d0f7391e8a943e1	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x94114a5eba9810f08078a7bf8a3f492faf438817f06e4a17b66db0758638f3561e0ab2fec7a81bdc8e4a21cae5dfa5e41d4434d9da6605948063a576354282c9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa485b2d3d382609cef1899666058f831d5c081c6d11b3c5a47bee9f18332e690079a239f7e56cd3531692f5bc245825022708621fa240c618eecb7b827674912	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91e0c2e5aac2e70ee788bd0b3769d75186905d905b87e2b26cec8d9f59a1de71ec8d442d7ecd03b3bfe9110c4cac744f5591909d1afafc60d22f67d42c59efca	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7fce153c7ae6f3a74f2cfa37822a412b24e9958b73d98506ce6dd6a461dc1731f851c34462521244ee4336cda36165e923b1fa28dc55ec14e5b1d2161796fd25	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb08da8c9476d63d7e06c10346ce1298a1800adbe68c2f72eb02d8ae914433cf32fd513e30a6195bd52ae154823217acd7db72ce81487ce07103e3d8eebe68796	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x81e9200934772bf51c014250ed245075d4ef5c7c6bec17b4003ae92715572b0051bbbf4f7a113646fdbb4601158f7e9f669151993dfa64cb248b3b859846e1b8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4d79212bab2301b38b857c0cf8259ff29abe39d6777b4c25d28fd070f29248fb2f43879c789a3c8ba9daa34fd4a1019f9c7efd3b7dd6dea3de5a6dac346f0574	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x921e2a2d60a8d8b9f08e420ef36175ec35de70c34eda7e7c6ae3e2776373b10f801ee906956b39625efb411fe8a034f9939bbd6896451458413dad146672192f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbbab32891854540bf12ede5d5feca10ee10343ffcbe47b2d42968112f63762270de44d285d31ad9b0118675bbd8e1a7c7f16ba1e2168df484dba45af47c3e687	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8fb46469cc314ed2686f84e8f0bc97129505f9630ca26c914cdd79c98354a7eae7fa65cdcbbc386cbe9d8c016e4e0d0d62590b07ba61b1ed3196de7a2141627a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb9bbd2375eeb8540e35c9418c8f3496367b214347561f974a0b0673b1773541394154faaa665a214375f966003f4095e734435bd534f3bf8275c3d114f9825d2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5c52b68e4cecfc87202e744236e3afd962e128e10d2fd69ba0c76bcb95baff811e77cc0aaa6852572c65a08a6d531aea30179169738b147102bde81628ca2567	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x24608e349eb546a3fbc948651a5233f1bfb2f79668dd885496158c6db130626364e82a42c0d830aa300e769901ed0db729e0a8c579f5e720f5b1d9a02dc704aa	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc59cdd70dfd9c0c3e44788d9bca44490fa48807da9170bdbbf37b720cdb4c758b6a0ef76dc17c23ce2fa9bada8a7016cfb98804877157d0bf65660ce73e71e30	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd2a7869f61b49659399f66d755371ed15fc5770768d57eca823b3976e0c0f3c9d48a93a8cf587a9a65872c3df96e8e4d1eba31f4ac671621b8b500d06aa72522	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec837de1b26969f79c5a8bc8c059421f1cf3ee70f4d0ecbd9c24110eded2bef23d1522d459001588d6a6eef8981e32890142b8e8eff03886a89618b3e020f263	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x12a227a1aafcd27e2879d4fce2985662b1f54073ca809840753be1b9b60309a614650e11960117c0d2792e8e228c39f11227e7675f722214f3927a1508022222	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1a0bb9bb4950cc13a4514bf4dac29d6b8eee5e971d5372b47c3b53c6efb61e0d1fec8b51dcf1d1241596542cb0f79990cd213fc8e1d007d2c7b044b3af48c419	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x85aa697156f320245030241109ea4870ee95633e13808829e616e80ba4fb3af03dd09ddb7176117558515f977fec11091cedd1924e186be81ef4aafd9c96bc1e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4b9e097d3e98d65992e45aec7ca53cbe8628c354526f0dacce987087ccf474e96eee7392744dd9be308db0890be22227f8cecc9e9be57284f2834770c921ce39	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1d34975292c941452fd3003faee64c9e114de411c05f92f082e9efbf29c7aadae30008eaf2b21faa20ffe407ba95b987edf2e0aa3ff87271f98ddc43b8308373	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3c8aa91873c98eb16a43ae744da37b117432b1f502333ce0a0452406b37008f37a601c5b681b5dfb0e82e7063f64f18700533067d50d2a3bb82100eac5bd0223	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x81ae59b0c3c4ba5be3a462be33982afc6a6b89fedd50f5b8beb04f9de0658b0840e42e91fd26182e7e3ced83192991c96e8dce4d823626ab9e155a26f5555e87	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa3169f67e2086b1520d463b07fdad9017a9bbb2775e22e010f76c4b5b8db97283cd2e001bb76d5618a58001a855d48ee7c5e514d966b232798788741791417cf	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x174f72599b969f3ee7101b1c3b671af6231099c4b9e7fc66d7e16a9e3b39bb1b00277e0caf815089358ef39c8e9350bbbbd4ce2a07d86522610a3aee88f45a7d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xcd73c7a1005fec37934f16087fba970277deef046d1a4ba601a8e7e821716579f147973bb3e5e4328b4db74defaa57aee064738c61bb9d6533c71aec0bbdcda9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd60e9265a2585a0778092d9888dca3e1079faec3c6517fe23bddb54fa364a10a59998d1fd9ae9020ff4e188d7a76f27c0c98067b12102be8e13ce727f7d9bf6d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5871f7be4c6e52a452bd3adfd3f5e6998a690907d3fc99f26b9136a9339c034798e04c820bb6ce7c812349397b36e2a6d60bf1f1c1ccb8d4603b2af33627fe4d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x455ad8baa8d757708e92c435990151cd0507ecc89167e39dcc0e9229dec4d109f2a00271eff8b92c397503266d079ea717ae69ede39018a1d9e8c9bb52f2984f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7b17072c4f3d4d9ed6fe743cf8802bb33062dba473af673cb0e1a8660f45db78b9c80b4ecdeaee1708405fe91dc5db31b707e8b4b87818ce8b6128886215f8d2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9e28eade41dc09428ddb9a11c1c3653cafabe8c284fce1d5810ab9f5e0c66ff0f9602c12bb260055e52e6e86dd6b13fc24fd3eed771b296141903049310c1160	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8e2f1066b7b8638597b4a9168f35e437fa4a90b2bf27d0604492954dc476b5bc6882f5d84ef22986aa12bb2b997052eb659227f67439a659ef247ae5dc834124	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7fc280f60953cf8194cc97d73210491b805912238c5a80443de02b0aa55a7cf60917f9758db080bbe860c33b29ad5d5b55387a2804eb29b33cc1f3538431e856	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x86651e459e347c05f116ab488e0f84661cd4a9b612fa465326126733cc7773af0fa97de0e9b5f7902e59c7d67474e67233d90f2729f85c75ea206ad797a73af1	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2e5899050c69eaa309bc0075710778773d090c26e0c6c0db73e505f01c0fc63afe5005b2cfcfb48ca411bb3bfba88ed774d87eea5977817d994f37c2c60ce5f2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd4418f9f1bf2eeacdf9a61da4ff45df6f184efda4ad66b05b45fca85c2be85814f3f2e351406b251b9d7cc354909d04ed7ac3b2f1f6c030d030c64d3982c3547	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x4bf7b1906c4ce631dcb8e35a06acdeaa51238ad95b34fe0484f410bcd62811ffa0923f29d6993d1dbf10a23e0df78edf8737b8f8f651d2495f56599d45e87e17	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61485bc4cf53af50a30802938756964a38c920759384bc1485b0e8c580740974c7f1e3a7e9a196f3e2d8608edae02ed8e24a2e64092b8a611523644107597d97	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73581611f6ca6275d1c22287104a97b07b3800ca74c602860f7f38348e6e57c908875882ca6203e64f19adb610b1a6ac88a3582db90d60c2a648a5d39fba97f1	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29c24f1a5677f61c124c6d89bacd1d5884deb47baf0d7a991c196d6a1f59af9712dbdde85a6cccdfd162c244974d2fe52b8c8068b12671a996c6cc2a8e8660a8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e5a4ac728f4d1d2c70524d8cd0814ea395a4ad8f9676cbcab7c065a6ba2c300c92d36c3879fc9e2be575fb8f18d0815a6653bfef0f1b2f36bafce30ac4a12a4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad34d15f88280eb413c91fa40926b7884f6a33ff7d53c51baf06e22ae6ce421c75d49bb8660d3debb66a7d64c069e8e71444df70d778c383441b4f3969dd42f8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x706408ff5600b4dacff31c2fff3f60842c9bff612e885aee78e651ef73b205bdf2775bdde4766135239d12fc1650f0943aa25d1f9a4b07c7cbb7c9239183ed5a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2a880e6d1ac5532fbad1f0b3d3c10edf3d7bcb176f59361ef129c1f070742af8bd932a37cb9ec3c561f59c4695fc88c561173a1f22243fdcb58e3e93134962a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0212859ab1c116201b9592b52faccac2b2c625b96552ce1cf54500658e56fede814feddfe4657b7f6e811686c9ce62c9d17debf3bc0f8ab925e1a843a1f450c7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd10567163bc10e988886cb25f375d8c570138ba50cb9e78b3b6b052ac15b9beac7764e77960824e004d1e1fdc8aec7058957a42956e869abea655d184775cc2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0374f298d53f1e9296f4d3ce85f07d4b047b7916d0dee31b85956a161ed44e2a18b46ceb2633106714b32b13f1efca475cb5c3906d7c7dfdcb6b59c2d125fa5e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7af343a66c84148b04a247a521458a1985af6922d0c786a4c99ec465637661c61301044e0f1e9e42e421db5de6ff94673553be42e7e4bedaa0c62026bd51a998	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x79466b865d6db3e2ade34c8fca6781e302b610b110eff9ea6fd44f4d15367a77ff1ce131e870fb01b7e90b78887b035451c205ee1d823c03520e0010eae42b80	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x99fe63e9a0ebe63d7d17a07563f79ab4aba5d3415e143316d334c819f860a802e0930a6ca62450c70c0b3d7447b80458958eedf7cc5e13c671a14483d787733f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13a3a00f0b314b60ef9a73159bd2478e97de74876156cd0e627d98c44a5aee28e695776c50c006fab084bcc73baf0b8977b0e9160bd6b7d3e22ac79b713da518	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf920e7a5af3c6bc66dda3f9dafeed4057316d6a60c5d567b2ebe6a8280f9eedc803df3deeb92444cb61fa74c911f4b9b4349fe338f7211dc9f4d14832aa5bc76	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf1fb4695c6f3882a2dba09f4f15b827c49d4fb5ef1d76a25193e1a49f6d180b10047ac23ccf3ee27431e8159ee5fd5e3d8649d9572fd00ad4f1bee837237e7c	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x314bb2fc63d7527ae2d227a7eba9412ad16c16130f40a54d6d598b9ab93cc8ff6f61fce19d587390659d515e5d16d0259ea79a567304cbf1eec546286b2f01ff	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e491025e3104c696baaa69a6bdde703e2880fe551a39b281d4c1a346046a3bd7bd98d97add3dc5b0496ece834787a52fb49dd25c332ca2f8d120d3cc4e57831	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeda014f82236f28d368fc4b1c05de15a5cd8950e60452bac33ca189bcf1b8f7aea58f15aafdd64c60d4685429af4222e02ca11a91764888b5d460e5777f5d26e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3235d89d97b3ee5c418d7c8de5e24ab3b574d22a2a4c1cf7d45c68aa95accb91bdfdcd3da8b173fc92789b0ccfec95ab6a3858028ded417f2a0b78b803daadcc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x337f1a52bac3789a22bb13d585853d1c16c43e5ffcb1ceceb2e64a7e04d382384aae0d88bee5b5b3c79561135a82ae57d35a84c279718a7a08de359e5d90ea14	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x169f141c02d43d5ee17e08ac18560b3d96501af60fc0a174957a4157325a59263ea35a6141c7e2c76f6b75904c55f98e251d0d55c5052bd06e208d101a1bbd89	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9b98305f5bbd6d34add0252680ce7a747b48033a7b2d8f385a29f8aeb4f4dac92797d51d75f4eaf09530aef59877eb0809d430d885ba4058a5325280da62d9c	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71a4a93dddef150556b6c68d3f97b53f9ac489097d3d5bf03ebbff8106c562eb48ad657b0e9c55af24a1232285342b84eec466984bbc5013b72ac51de818a716	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6bacc2ff24e2f429e00cee9c4d866041f128797aaace874110388582ab8132465e36ca93245c8a2ba262eff0ee9d768f6840d8b004a6d98beb9ff74c4ed64111	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3580f269981c628594ce1b6adda9cfd4f15d9a4fa30a77c216b36b39a7d13433cf6ff73b99169d9496b16c3929dbc5cee5062bcfd5d55b214356b9a6218aff02	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa839562c30b0941b7233c734d2bbc5426c62241d746cc2f708c16e0d5da429fa4e12138a9a2f6b6efabead25774a4d57b2f6a017d38dfd003a6d49c323c886c0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d182bf0043988aa8d1bad9fa8fb1eb84f415eb1209b5cecdf40843a3b593d0fb98d82d0fafc0c43616af5f2111b86ce19e2853f013d9e1cc9c07adf5d8ba037	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa6aa7ea0c538aad57f4ca58b7192d5c2b8a33599d02d3ff9bc49641613cc24c22fdaf1d39303b53d19e4b0405bde428e36ea1febb5eac7e5adda21d0e78b3d10	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9111f5c97d7b508851c3997d57e2024855dd562504b50564fea37fb591af80f1c2abcdbd2d59b21de2e095cc73566d92c8b87ae4b5b9116425e1e616a1ff2503	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x21620e10f443b3437549f79d92ad5ec293f735b11d973ab731a268698b520ef5c6e03d559dcf4c94c1e4dd6c059edca5aa488a7b2c2837744a439f5dffbf981e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4b5b0f47030a7cae626ecad6f8cf385ab30a11a35a94cdfd469562e5337750f994083ce06f4354f6cdf3f60f3747e2ab0ffcd3d0f55d9dd6690bbc61b2acea2f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3491e05d76cf13b09fb39bc9da4a66e73bca7b331d9cf6c0747ed7014202f53cc1e52170cc70772169a2abac4388d44c23518c29acd3e258ece12a94c2317417	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02fae721800535fe19edb9c94bcb6bca4883922010c2d16f3b62a92167bbf8c18b361843874c0ab0123c745a9b947a1c2abee7409eb4ca341f201ed7d7849dba	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3901f16ae7ceb282fe6923f2a29887d368bf3d25630916058a5a08c173e202a7930bacba9082e0d89e70d02574bf5de2f45ac499c4c004dbc09588ed7fffb2b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9828d4aca18577240693a0772dd64dc735f30cb8930ef98612d6cf09d2af1b3bf92e434ec2463abc2d92a844dc6107ccba3d5807f04a6b90681cd202586df51d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2f7658fc31a3c107de1389e73182b44dafb8918bf0bf20e5cc47e72ab174e45b431cd3a8c773376e9b700e8c55b4db5ceb2114d12e8a1f74c22adb784ab0d99	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfe1662effd0df4d2d625894f8b94c9ab3c1341d00f2ef9033099894af8f21b3ddb8d0da3df5474091d9a851d4ee4bc058b4fa76d6802f5ea9d9c74e04f18d263	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58ab0fddf2a46dcd7ad011882d49619dfac070b33f450df4606a5577c1ee02ba38ef03ed16ca6d5e1994fcb43957254053a7cde7ecf7e647b0a0012b0dcd2d18	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc2241bd63ab326cd24507869001a73d6867d0d247f1e27683c6648167419ec6c9d9a0efb0a030b8cb46713072a3bea879bab2751791443a201b9af0ff3f42888	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe5debe92054ed7ec5b37b960f02a305a174803a2705515890de07e874b1871b2a2bfb4144d1992f8ccd4beb325a4003bc9a972c33f2a661b3f62c49ba104d80b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85bdf6887deaf36c3c58dc3499f704684127fd4d9eb147fd63127f98dde6b4e70b99f21b2237fc1ecdde2cbe9e3d6298515a8f27ec4768f09e1f31dc4cba4b1c	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc5f4eb826c3695e132cb4e068d07c2acac02690af810ded593a3c206dcd1ae8c90160b5cf9cd46d8386e03e6b428bcad31d47537fb2695d3f149d5e5ce9fd622	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1bc3b623019e2d7aa8b7d5858b1b26fab1ecda9731cf925d9160fe144ee0055572e9a0ea34101ce65bcd6ed170b7f3004227d5c1498e92a86edbddf84e10f65d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x85e37e7bd424f3b947643c06f0a62e7f54ab639855c22570aa70a57d9c369ed7cc22e61347a54c7f02ee926ea9d20e02d16e7dd58ea30809581f0d5dce5f0508	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x653b0651ac4651a84a5a58314e3c2f341ac1269c58613d9f7f2bfd10d5d816e1ac2aea2ba6b006c63b9b4db2449b9e5364c65403e335bccd6ca6e7a49c37eee9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x79ee190d900530ae7506271288ac9b004a1f3d726b11fd4bcb3d713f84b6f81eccbacf35a42c59895f216884ff3da20798122737171b515c0f352a4247523c4a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb69055258547a55d9985642d18b2ed19b222c890f423d672bfe71325871cbc06dd7bf5c2097098fa5149bd236c79ff0d0d4ca3ee98e9c148ba092b57d05517b3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa44d6d31e4b8643708e4517ee8dce3d231bd0efd7fbfc5b70cadcb3393e44ba2e3a26ca496c44d69db10e28d9828530e99e5eade647e808efa67c0c5256279eb	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0cae1115b3b2c247eb5d496c1e89ac44e5fadf27b970946f3596fd0c96187cf67c146e9520c119d98122c4cbc5b05899c7a31344c73709130e55a97eeec0cd02	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x34dc1c2da296409fc9193ecd5c189318a3f6a5f0699a4c5d5950252f38d6b74fdae656c27af25aee4a6d66833c29cce94b7bdfe1105cfe52d8b0d525d2c8dbc6	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2d71b7014a49051950f2dfb18d000f6ee877a6511cf3c36393c8e4ebff5e6d87e2a3c01a555c54981f839ea13ab504a8da487faaabe0777d0995320cfb070197	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x637f528ed6e6273ae9dd9cf57f4053a92bc34c9e275567f46c37509679cf6b8d29563cc04831531edc52404ae7faa9e8f8ed5a5c25153a1b8747ce06cb44bd86	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1abffee1803ac0adea892737c1df94be3a49dd580d241dd7f190cdd93083f61567e0bdffc728f8165b874cf8239fd53862632424e27c9b2c8382c5c53b331bc0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7bea23b76fcd4194c34813ae7a81ef95206cbedbce7ad14be6307a04d7032d7e148c2aaf2f17286e8ab79e76088c13e0455536ca22b0a366a7b9ce9b5e8a4bb6	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb15dc91a5fe38d7ba196ee69e896d7b900588c8681f56bb513aa5abc384c0f51ca53746491d98db4c59c7bcb0e97af8d2189da7369ab2553907f07b2a0ae9b41	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x190fb86d9931874e15f2457cdab503c2d42ff4a8334595db2ef6de1325c975ef4a1e23d0362304bc70364b3771655a1fd2a76cf4b1487ea312f11aadcc113498	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8d8e5c37762bbc93e239c9e537e5739e3a4f0e8e7fbf829b62e959f63b852ab5cac36c9ef30f82346b7c98d02c57802d8efca1c0fb2b77a2d8c55026e4e371c0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a65d04912b7b6bc5116034653d8ac2fde183838c9d002eafbbde6fab97f774c166f66936ec589736b2cd71a38de40fd60e88d09ba5ea38e3cfd8d95eba96ee4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaab4e40a9611a1fe930c5dee3fc7da1e1eb05ed29004ea618ee62a56547ab9d2cb8a90cb2d42dc9ce6ffa4ac0b557155cc8bb7d24eb1c4be864830c32df19acb	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x19c6f2af56aa43c22b9e1c0a94ff2e694d6b8c9210905cd5858cbae89cc69d49810e4e0f2932d41a1ee5a774c21f269e9ca8553552238b39e2fe00e8d3c821f0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3b6fbe2f2d6fbc74dc965f2c6c89589696754a90b60786fc2c5153b2a6002cecf4c2b076a7bb7ea3400ad88d1143e78077e719b21d07418f93ebda95215ed6a7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b13c9f6bbf473a6d3b6c31771583b172c9d66c49ba9bb04e84a30dc2b62bd0cb44bc00a87159f7f4aa54b35b8c206d99da772c014db9a3af3b4f94910a882c6	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe10f7778c46481ec32ca033cf6f84d0320198e65005c36d578e3bcecc032ae5823b478f509846df255485127f81902e07423dd1cc4ea829bfb21191c2ad26649	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x368d509749eeef309c72e667aae467e7e3d5b14a57c417a3cd37368b4192c6f72da5ebc500b3980a3f4064bab35ee06d24611f43fc1273ce9b146cdd958fb3c3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c8d8e8ebd129b5608357392d322c930610526417567642c324d1f06898dbf0cd73f5ea3dcf5421226cd5d3fe7363ef8a91ed608f79c6c79011ffa6a3689072b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3b5d94fc0e964b7c952763074784d18a2898ba70cabbc2cdc82a30a9fdfd5cc3c5390bed15a0339803ee4421ae261eee521b158a8d2adba37f8b4b15eba303a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12d1afa48ba0c66496da9398ad7f8c7bea45ca7cceea629c3d881e6f7eb9251da4bdaae4c0ae8a933da20cff389b1124de6fa943204f97c7890aeefa840a0ab6	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24df5661bf0eeb5ddac62f803ce8545c683d1b0e032a2935bb1041062bf2128fee218fdd4fbf72345432a0c4598811451c70474995153b4c30941661abc19454	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28c51acb876b9bb2888fb74ff7cc2ac6e512a6b2b743bf02acbf1e3946b3f875d190ed12378ea97dd1d5e9532fa441de8bddb7e7dbf0dea6fac36a4bd77785d4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0352e2bdea088842f97be680f758c28d03156f5743b44bb2d8af85ee8f9e7738c09a45626f41468cca82bcdce08a71a78b6b181007da1240a407d38a66e39540	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7516228d166e7335d39292349f6f667657cae2144a2f850be5406920c8275e955adc143a4032eb02055bb5d7cfcec3177a4aeb8ba8a88c4e3592aff5fedddb15	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x01a13c18cf1a45a42ae2c571359f95e5a6dbd735a6b72df7f8cedde3e3502ffca6ab8de47a9eb7ea18eb7d179169cec23538693b029b04a82b8195c3b61bef78	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bc1d1d3399f993da0fbfea839466307f283c2ed9525f8c5e01f4f1624d6bc0b662299cbee9c48e079c899724c2cb23bda842cdbc272f1e5377f3e0923dfc504	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4b5fb2c6490445566323b44fedde3797e97cba7a467dc2ff4ab3dac3a69d1fd3e3208b9ca307ea6b3a8340dac2eb7067fcd51f7926d5458980161c72910e9003	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbd286ac09b96bdb548e6faa3f3061e793b9d3404078642261803591724da811a6dcb50ba497ade7c1d52cf476e299e8588a6295c8efcfdda66e55ae7d3b9f21f	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66b46a0d554dd7eef23f02da9eafd1244f684a4635439b215a8593ad34aec3b14e0b45a8c906227814ff70521dd8ba27151913c397ae67e00eb65d214d2f777e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd522093ed2df4c5b2a4aa1b396fed86b9b1eed219368dcdf847c22e4862c225bc7ce7ab144ff2718966828b36a7dc38cb97ab3f98c3bf41ea98d322818e3f249	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7a0732e15aec799287ba27349ccf4e6ce2ca32b1bc490eea75e76163c2e0ea8e6f7ddfcbaf1c8771ab203d3396f9613a5c6db35cb4b2b3e6a4065f7ff02bea8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x30cd47c7d5a1d38ad5ce3864bb247e3e64cc4ab739ca0f80cbec68eab7c1290e14d457f9df49bd122f8488eec92642869b404e85f621c352cefb29aa7f651abb	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37ad6333dca88b47f716ef8f6902b28c5c46984dc0cad60489515df769a00e0f7c50ebe58b2843f30d09edd73efdb3cd235325532d3be78a7df58ff8927e61fa	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe77b7cdf73687c071572ea9650918c42d0f49085abd4b280b32c1ca2e0597411738f108d56d234cee8c6c227853827a36ee2ee13066aad17c6d4e0a5b329e4ff	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a934ad739632b1998466d1fa6d266e22e500797963b93314b636c9feec4d02ae7eef11f557d1099d4e323758e056094cf3a6a586995a405f01f4b8ade8db4f3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd823da6e1d4a63c1c10e5b4a30f8978f46ed376f47d9ea22f15043f4a9b5ce2b9072c4b2c15dc29fa9082083c6e07b7ae3a4af259a9a6e5ec8b1e659234244a7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc1bd4d21120b10371ecf16e3644f7b1267138d0c20fdd5bb06d42c77f0712a5fc3b6a585d145c84556cceb9ead1ec24400e095e99b72a78fc5272f26b83185a2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c3436618dc1c28689787a16968811a7f7400c4d3dccf2bc44258c6130898422fda56a90f741a013eb64dbae11816a3a09179369517a9364f7b2473ce7175f30	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x53926d155dee835ab211f2c3af780b115c99a7f4d82e1a4db8ede1335d0e0973a18e49212d967c52f4b7c04d60cf2c0a2727b511facf93e33327dd77db1a2660	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf7c08fa0b080d7db59b3b81561aebc6fe3ffa0acad60797ac15ea6cba04e4ff0dd8c8922f0be5784798b8a2f654f1dbdededea36c519a8e0455406f57d85682e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xecf710ffc0d5674d0c70c17907bef17bd5e81a54219038187b607a90d1c654b577e8c2dddff077a1b7ac319491a9e8ed32bd121776faa59d55956381c5362229	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c43877f9bd6b9298daf2f27cdd120aacbebc96557096ecb7078aa8a80c3536f10af597dde48ac5c7da88977e39dd530057cbf18a198dfaff4679f9a774e3685	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7adc175db61efcb0822c83a1824477eae129473aef7d64d58a560e6e314024914ea5a84f678f00b55a47e9a88c862fe9183a58e2d748c20fee4376d709873345	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44ba168d8a54784e56ec3a03e72b9907db003270df1fdf78cbd4c7b480ec892e7475d95f90379e1bf39539ceeb090bf5b2a0b8f8ced9e9eee28c1f53e4e2a462	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c98478c4be71b54000ba38c0fa8cc25276d94cebeac24211f863b4129ffbec70696374289e46be42cab3d3cfbdfbbacb254345111cbf8d2fa7382f1e3f93b14	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8032bf8197fc018269d41ff37eed964b62d667408f53170e8329f51342d193f9b9956ec829b02bab77823f3e01f873e5babef75b20b6b256374b69e4f4be742e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x054f9908ba4293a85cf3f47ef93a6e86cd077e7bf47c7af2b564bb7a3bbb05edbee660753c33b2b033c7dece03599d6e20c678861e74e6ce12dea8814282a0a1	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xca4549d2c2e7f61153320a62b4f7861c55c9f313f9a0735d94c3b912511c7acd0e12e151c248ad33d41d1cce16bb6d1e3161e5ea12b2bdbcf4c64fc19105df71	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc66c62253c57fe7cd6e11ce2d5ce3c30a1ab7fa1aeb4c97004f976a3f9afab80393bb31713508b5296f36cf5ffc1a2db51b83b51f0665be7bee35a918af7c517	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69d6bac6e89ab16e056d416fcd74684f7bb8c00d47dcba8b25a9f41d23f066342e7e49a15aaed14a294db0cef0d488fcb8609ac9db618664a9c1c9f19ddf45a4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaab072a2885a0c82531c1d71454ccffbd9da46cae394cde7ac7b9b2c1832457415aa6be6185be0ee2ad446d3389c051f393715168d1e9973914627fbf2e0c5c7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52d1bfad725718f845ceaddc68b7ff59c7f782082461f74765b391e562df9b0ef3aae613fcaeb99730c4ef261abb9a5e75900d5953220e0500dd362e82c970b0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x53fbc35b01d347f6a7fec63a3f7df5b35a42d4b0c7a5550b629fb80a26b17e06de6a4adab8fb5bd9234723b55196c3b9c9475186c1fedc03339689a1e71a0256	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x987469b88a71be9a01137d4cf9b30d77cac0be1b8617458c9df810f3800ead502c4c51f9780b359126ffbe9a8511b02f2a369f4ce093b7b8faa006418c642fb0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4419699fab928dc29e550290a53d72285e2c09cf15df641c669e4194af79c52aff8b859e6354a4152a03124f4e4c2ba4b6cc68c976c4d26a438d8df5c9c0ebe9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xac68147cc16bf25bff90c448e7dc5b48cbaf8f8465229011e9fdbeff14a95a4ad6809d70ff349538874f19c733273415aa977cc6471f8c26c22c54caad99ebfe	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9001a05a1982c97d1623a1fad126821ec5e846d2dd40bc0d9bdcb5bc56d5185a967b8a994cf00fb2424f7b2dbc4900c283b878b2319284285b045509e300e610	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1e8ba6d531b5944ad3b04b736396c44f64ddf05d3a52bfdc9aabfa2a74efb31b995de24d36e524c7c3645f96d6b6614cfe0c7782b64f5d0133f4794f186733dc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3275b43d99179aa1567ff331ea7f06ea52f4460bdfe54b79625d84a4123e17d67ea7856a9a8cd7682906c70573a5af4dce4fd4593c35a0f06605bd4cbf71c3cc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4b5eb64bd2684c5bec3934df79e32079a4cfa007d719c1f1ca98b8ccbfbc4a502674f09a3820536a18421d1242f40b5945e5e2f748dc7ce9699725eb793dff17	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xba7f68d35cac0839f4fae2c1ac3afff5946cf1707f715a4035842d6c8acf77dd47a7753e2f2b88eabb7fe08d7f1cf8ba85cdcdb31c7a04230451fce497ea99ca	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf824490057753ebe516d5c5d2a26f552d38480cca7e0274515a56d6c97f8a8da367ca5d05d0ed6df56048da87d4f9b50be48d3ebcb33b8a7b7330c61a5546385	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb2190058191d3583798ac49604e0771a181e340e4ea328b5c99e714afb2eb983c4409d6701a08db86ed208abbd61cccf80d572a959647db68025b5c7667ab075	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1a388a5d01c124ba22dd1048206463972fcc628e7b07208ddb81857e7f8b5fa9f463021134f89a3aaf13bb1176d91dc872e94f37d793c418941ca0eb05c9160c	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9aa14ee21a9eb1e72daa4e1839d78c38fdbdfb8c11b39354ec3ff8c7d80aeffe2fb753933a05d690546a96c63bc4def03fb8795d9dd38f9c62b57cc6c0c95097	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1ca66cacff5862d123b00655e496eefa65bf705860b4fcc4ed3c5b48f3eef48a9f4b63c7ad91f9ac5d289c1d367d29897e0dd79c2f42e3bfdd07e5c2681f5b11	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c90d860b9d689198c5888814c533b4b0efa3f9204fe9824d297bc2a3bc2346cfb6c729063bc9a11929582f4b4d6415458c21fba514678ccd6e808aa6a6b8c7e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3dede7e3e5f8c2382034b162c96fd259bde1f2d2e59394be8573778d477004a9b7ec4031a2eb3b5e1c42ecb18b40623953d493c43d5c04bb7516f9c96b6d97c2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcceeea14fe94fea38d1aa1ca380b55295f3e1335b73470b40047c1ed894618327ce09115c95f81c8dd79ff6359147ce4ce21a4b7e6e154de878745f6514b3f23	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x06ff7c80a72e1468fa5e1755af795fdbeebdd776b6377e1b1178c4b471781ca902bd68c0ad5925304b9d5d4ea40bb0a026876e838c2af89554775cdfda35eeb0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe68fc182f713eb11d2287656953020cd0a361ba767b08ad721b0edc9a136b13a4176495ae394ca58c9fd40d01dbba930d7fada7b1b47020485fc134aac548401	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x712ac021862d0933f50e05ec98ecf66dc8f23c0d06e2c0d9681808fa6bcf35b568e320722752a94d2e8ccb411b187a1619eaf707acf89e14ed0abfb2638445c8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x18d0761d4e40fb2574ed90b14a89ee4b3db62c70229febadcacd1f7d603a8d92c5fed23206ca904aad1869886bed4cbdf6107b13191262f13d02bd0df4ab30f7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4dbb0e20725848b922a641dde2e4b6e5904089e1b11e0607918559f48de3a5e642d9e64711da5060f42557a7f4c092935a25166cb4be0a606a900d5d2b732b14	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf05c73500b51422de098f8db359c084e284f6cec9e076b72505c965e86f5079ddd8bab0489d16999f466ebb2259744674cd15e2bf1bf118ff0d028fe0219f902	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5bed90d94922fc6deeb38cc084cf676edd6ca4b3bf9f8ed4c3a4515e28f3feda70441284f19bcb1472309ee6deac3088f0fc6008b5ae754b91e4100c98d6bca0	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x45c268a4abff7101fd8f7b2c82214ba26a03e4d5208baddf62a8a2d5a9c0adcd4b13d1441919496dfc7bd33e3a42265770417975b4bbf22c1f3926bc0693d360	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa79126ac9cf3394213e6677ef78a73b53ca4e792655f6927d5a2e7b2b5099fa301043ea884cfa3f4ce6970e83657033adbdf9b46526d5b929d03d1b464774068	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x15cbdafcc85d792913f6475b79337d2541c6f9b2c3d2190c5c31a03f4f7e344c12c76455f24cba9f47552a7d3dd26339a3aaeeda79944f0ed36e046621ee0ebd	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1f4cfe0ff0e34de9cfc38937c44457edf95cfd834154ae6526bc1bba0bacdf1fc78d7ad21fa4147653ad87a835eb42f91c584ee219a7eec3c347b9551405c1d2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xacef454b9d1d9417c5070c5fa9bc0e7bd039085fe33ca8bdcbf0624620d8feeb08aeb927fdd42cfc03b8389eaea261d5a3a944af9d40b06b058182ed6eae3f4a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xba8beb4d1a5aa9c6ee20c661f835f05419f8a86999a657898f3a4a22f45570c893efa71e2b49f5025639560ba5cb82968e438a7a9fd8ee9c25dff718f9d24a5e	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfc65f1fd7cf514e1df8ec6e12abb6ab84d588ea69f1f01b0359e71c6259f186670cf5762a47a7ac0a5092b08904e8a5a762ba8bbd0273b863ba201c553b0ef3b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x72c1a3644e5634163b16fd0c8de7fb9c55e449fc765143fb977b5ca7f93c91c27bc12e5fbd720931473670f7aa2c8e73acc716b3227e26ef053084129ab1dce2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa00afe7e77f5b4bd1f7342d5798f6324c5b7a03ce01c21a4a9c547c42fb8328ece94935337389043b5321dc2545d49e13f236de9eb93e98881c5914828ae52d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x51b29f2e753d3df1c2850ed6e52c42476614a746447a5456e225c1d1da0248f8243a2c768543489853bc93b87bf6740fe6c1a05289a72a98386a48e46ae2e080	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xac928f7465c613751e8ac57b58f4d27f7fbeeaec78d9a40f93959c48f09bfa53137fb1d2101a1019bfdaf28363fe1006852fdebef32526ef69b8fa182a4166a5	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9345d71d48fa5fa052b14f3770ebb07777ac843806144974ae0f229b7a1fd1cabe137b21e9114022ece041109905610733b46ae150aeaa9b094f3cfc81c40891	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc90d25105728506a419a05a4152e04823868453946e47775e4ff51dcac11f31287e1b66eb3dbe7dfd62bbcfbb2a58a2b923f579097ce3705ca6ce4b30a0b848b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2037fd01e75efa189b9583b7c7e8c62958d9d6783f3f7985e59cf6f7318a7cd6d915f99f3b4fc72a3d17e002e1439311c80902fdb4601081937eef7ae93ca239	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x27c79279d0c7e80e8be04371de7ea1377b604c289068ccf58b54a4fbbd9b945c530a9d3e3c317f365c8213b43a8d546b72c1bb7a24023a90b4541e437c1874c8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a84cc73119766c9514b03d32e20172158320b56b79f4b8cd699ff5748c053740342dde1dadb841075acb7dcd7b996c3815465c86454c5b1e1f9710d271d4648	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0196f339f7d34b3167cc983f45462cb0ac7d0bfed8d598fc474369e02103950fe789510c20557cdd88bbdd86157d4af0335ee1b7075e6022d7e5f07eb6ab88d9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x11df9eb561afd758110b756ae15a86468b09524fb48367126c334728b2d65f3fa8ecc4431382226a3d584142d1288f82025c8e0813e41aa665d117bc8fb25c4b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d37bd02794823c6a7d09b93227cb67e458e07c5458d91e66533b6956441336b4924727865e99eb57c750d63f98f8c4a125e2baae9065ac83dcaf2a4d0b8b122	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xccf02315d5f5bb061d6affb9aec37788d98bf2f5696ef84b4d3687defe8297f7e5945f14136b9b1f2d7a746b8ced85447604dba97a07ad960535edd968a115df	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb512ac9975d76a1aa035b6254254bda672ac4e6c78ef347e90f723df13bbbe4cb983d1a416272d2c1c1894489fa186d6e8866ad500050fec4e227489136aa3cc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x35de7cb89fe1a73754400662670f8eced3f53ee94d3aa9ddc7511e507c859467e47bf17561cbd7563c62fb2cf7e6dc0f54bda24bbcb279b04e204324e70dd946	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2c5a8a8241cff8351f77bf1ecc3572c74a99a8a7a457f7bb78f631af78274a454fff575ae59da379e5dfca2ba99da066a705b8757aa517905a59c51d8476ada	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeeccae04fc86837348b3a718afe6294e11906dc50a9da3ccd09451efe3a6d34cba17d754f7c62baf6598ecac535fd609cc2fd253d02edc026df4936784156d2d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7f0b8f5c47e776d880b7c2a33c1f46acbbffdd32820ca77b97e661c3f6188619f2eaec9de72365dc24f419ccc732857f1ea7030100d2a57cb876230b4eeaed4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0fb6b11dbd19e769e55ba85ecdb7ed5ce46d9c2c5fdb937efc4f935df3ad8f9c401c9c20d6928fde56978b6ed955775b4aaa9a6c68740a87207ec788d4a965c7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x73729a010835f0c7ce0ac60ba29441ac0f7ff2c2db9f8a06373e7a979f59b86c6b90276f786907d5403e9f07eb6800002138947447590678120ea1c25f3f84f4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f17a7cc8ae02fc09e63f8b0eb0567d685296073ee1b036daa4ca5b597fc100c224ba6600643dffd7266795ff754323785feddba0af675019fc487311202aca3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x62bbdcfd71decf9685e3dbb6d5a74b6f06033018b7e8e4019e65b56018f192258776fd83704e2faed8989179dd5fd345e2ebbbdd8d45166be4a17b18c721e362	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec666517daa66b3393ff548aadde9b637b1986b7b520fce20ad9df71ece41ed065a044396a328c976677191b3ee7a51b5e90fea23b37c53261588c3216e9c5bb	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x579f2eaff0f23be6229e31154aec490ea2c4dc718da7546983e495d18806bb00c2736b5511a61723b8f0a5285f2c600623a59efa308ebb7e5e18c04e11535573	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x820c575d0963575f5d15aacd2306fbadcb6f33bfb90258d69d1150855f43ffe5046f644066c06efe42583cd47d397f208993e01e0b008d2582c9818f53b090ba	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x339bee8fa13dd737713740e35d0350033e410c9e5feedd644ac82f84f855bcb35cdca4944c74ae4cf1f54824ef2c0ac2094cf96ef3bd18333c9dc194f3b06071	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2b984f1cd713672e2f09ddc9f43992aa759509f25c43e69b2573f0a4253f718e7fd93e793219f3fdb2e17a5e2f73ba886997682c43b6697f543f3f07d53fc48	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x804d40e2fa09f261408e0ee54d9e651cabe6f6431046847e3d61043d5e952edc3c22a4cb1db52fe0975a65bb8b11980f1a6022eab91ecd387d15e82fb7c36b84	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33e69a0ebdbbb26555000c975085a8f5733da52dd3096153a8a523a350f8bcd163c203f3ca30ae6d169ddf8d4b795a9fdb3fb3857658614bdb93af706d051316	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d85d41ba279d7e561ee368abe4a5d327131eaae8c2617bca4623d319d07c2577731fe37cf27582802dd8678321df92d09efb332049e90cf5d2b063a81a12a71	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e957e77b51eda251a2918018507adf0d61772833c5f58d793e8ec72a31787379288d7cab908d1a775b5a04058b5de2d9c526bd1a1b3f77627fc5063efcbd4ac	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3f18bc508fd9ef0e1d4a963a30ff23a95f6bcb90439f5f3a66913f9d2b5fb12f892dc32f438a5455140bc8d76ee867db97f2b6ef18e412ae16fa4df78633f44	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf217e3d883654ee30b61b914869afbb05213896e92ac866e3fb32ebae8b97e1c723fc394a6a9ac62ea6cc231298a0c165609a3ac192fdbbab97f3c0795eb8edc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567387918000000	1567992718000000	1630459918000000	1661995918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x60c40d70ffffee93c411d75ae87e5e28fec5e3b7178fc1e4c8ce55c9f75ede31f96c22d43ff0779d7b7d1b9e41e539bec99585a581ece1da21993c4c02381de7	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1567992418000000	1568597218000000	1631064418000000	1662600418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf887303386d31bfe24c0fd5cabb61c80a69b0053fc0cb0411db0aa5ee87adc856fc02278aa29bf6cd58835258b1bff1f5f3dcd39db77baaf21699c672e388991	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1568596918000000	1569201718000000	1631668918000000	1663204918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x574a5422469976a1ac55e79fc750ae84e52eed8918c4d98a9e9d6cab2342c95d5eede460622061681e2088dc49d07e7d4857b78dc98d776106935484cf3ebf84	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569201418000000	1569806218000000	1632273418000000	1663809418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97c022e6cc047727696ce0578de15bfbaf9db153ee3002ea831b90648eae2d0c2bf03e7473bc8913c76a205ec679984dadae29ee8ae3ab5fae96a5c73b07ecfa	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1569805918000000	1570410718000000	1632877918000000	1664413918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x756eb2e1d3b84b9160fec894de2df3ae861f37faa147297fc87b10785253c07c22751b6058298fb9896c75360b2e32d3cff028813dd435333c42ce5868116e26	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1570410418000000	1571015218000000	1633482418000000	1665018418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcd88fd8663830c1db3193e25500a396d384fc1442480b33c345c9786c10a51bf0c6d4108b870d8bbe08f5463a5592c4faf63eb6e874314831a0ca4ce5af6fed6	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571014918000000	1571619718000000	1634086918000000	1665622918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9e6afff838d0683c241ae6e8b22a568b5abc0da5a12b46dd2d3fdbaf59c8682ad190436d74205c011295991e7b452a61172fa40215309ba3e08c66b8cbb87564	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1571619418000000	1572224218000000	1634691418000000	1666227418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x8ff6768bcf0d4ac351e36986ce24da09bc8caeb0260c6d3d0fa8270aa6d4c2e5400681420b47969a24f1e16696aaf5f516987a44385a336f68c7c417d4109399	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572223918000000	1572828718000000	1635295918000000	1666831918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x029f535999c8771e19f45ebeccaf838678148ab9bd0d28a8cadcdb38b67c27c008a02cb43f02e766f615dbaaf048ac83b838ac2f036e414a99f6861d6b6a18b4	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1572828418000000	1573433218000000	1635900418000000	1667436418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf847facd6801fc56db1f4c0ca04fce7c4a8f079e7f06a9340e4f475bcefffb3e9c877c57ff04ae99f9fdce4e7dd8eb42498907ceaf1c7e9572c08238175358d9	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1573432918000000	1574037718000000	1636504918000000	1668040918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x945a575a95a40cdb92a97008d4a1164cea98f01400614545e596b474306302492e8f7331f4a7cb38295a050d934612b88aa27981a097dacbd5bd44605c477211	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574037418000000	1574642218000000	1637109418000000	1668645418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5dbd36176ad24a16400b1f7ea44c5d00b826f8051cf5243a45310437590d8bf1d6a596766e5c8b278ec2dbe5e58a942e4e4280a5e5cc73a84a17007e76f52006	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1574641918000000	1575246718000000	1637713918000000	1669249918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdccb99db4ec7955f2187f6e6d3b5d46fc8c7c558d4997d5e9643dbd921286f7bdf5ec14c72fcbd4350198ba84a458a4b5d5de03eef0873d63ce0bee71a46e830	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575246418000000	1575851218000000	1638318418000000	1669854418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1b6daa48735b9d1179546f63d251742c28d44dec556409ea274ec3137dfcaae9f508659719ae611793bea162f52c072065a2f3985eda48c449a2022eaf076537	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1575850918000000	1576455718000000	1638922918000000	1670458918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x271d211badb4f81e759a2d0c198aa02d360cc96a4241514f896f45748f9b976a3f2cf006626bd2568373f80242707ca9922953914dcedf560b4dfd4211f71422	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1576455418000000	1577060218000000	1639527418000000	1671063418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa3320d9ebaea37e3af4b56fc91901157006820a6396137ebc02cf160534e2c8d1ed75d1a80dd10f91517b5d3814f654caa7b4f4e50490ff14a919cd70bb6cc0a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577059918000000	1577664718000000	1640131918000000	1671667918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x19193aa20086a8ba9b255d305f86a6a99cc99ab7c75781e0145cf1219c7d968b0e61974c4ee10aefc898d68f429e5677f2f53398ec49343c185fb9d594a6859d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1577664418000000	1578269218000000	1640736418000000	1672272418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc4c1ea03a8ae0f26ebaa519476fd2b2ddeaf2484113556bcb9881ecbf59cf178958d874bd4c4a14d428c6dd45ae6fefb4bd891d0358046a4dba9b015d505167d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578268918000000	1578873718000000	1641340918000000	1672876918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe44ffcbcab0837d3b6c537b6527c6b0b24155a9890a3d9fdea1a7900c7dddcc719f0fc54cbbe0f1650904c47c167796a8e88f5268988f34c2220154b923c2596	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1578873418000000	1579478218000000	1641945418000000	1673481418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf3e0d8459614c3a38db36a6981d1987e8b1cf58f27052ad4c2d02cf9ef7ecc061ed73246d4f9e4a44a9ce80ad3214e7dda24fddf3d858d3dcb35e67a3bc1317d	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1579477918000000	1580082718000000	1642549918000000	1674085918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd4cd6b4ec1ac2f2a494854cfa6ba0577c777b51ad29da4bb4c9ae2f9e06ff1f01ff99da3ee759f093bfb46c0f5d51a05aa81647ac2130a14b1962c3d82898bb8	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580082418000000	1580687218000000	1643154418000000	1674690418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc662b370567899cbd0e3d753a4d6b48d16acc7277938ca648bee2d26dcc18b6ca627bf91a58512774e851facad2e0461bc2a49c05c7acadd7423caf2832160fc	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1580686918000000	1581291718000000	1643758918000000	1675294918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbf3f8eb19916cfca3b991ca7e38d4d6be6dddfe5ad1013243dfaf654846e6c4f035d8fce4a4f3e0db308cf046c1494c61eb099abda77ed2c0852ca58b2d4d0f2	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581291418000000	1581896218000000	1644363418000000	1675899418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x52d844ee81c4e9f1b5f2544b9c7119137c7a87a150baa949626674fe111f607f1574cdf457cfe1f3b0fb4d50525701a3bc8ed8010f0a62e9bb57b9507033f2c3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1581895918000000	1582500718000000	1644967918000000	1676503918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf07618f3d899b893e8e342c4b9827638dbd8db4a2777d50f59d2c705135b924dbdd783c64125ddb7495de983e2924f061acc0d39671909bd3c23db2a83d7b7fd	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1582500418000000	1583105218000000	1645572418000000	1677108418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa759f864006094a41fab6591b51cdc923726ff5208590dfd780c9119075e4d120da61b28393b22570e73f2e1bba87514aa5b3af0e51160d51dd60f798bfc5182	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583104918000000	1583709718000000	1646176918000000	1677712918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x02c1a03537ca46175ae53f307324969282cc58e08bfa8bd8c3c84038db759de4463dce7e56f80b0e6c777395d156236c09961e44e98370f98c3ea3a02fee8d6b	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1583709418000000	1584314218000000	1646781418000000	1678317418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfd832b2c94b1b5d5de3733920f918b2233d9dd6b193a8b96ee6f16737128438d2091306cdb76f9b73a59c6112e3ef75ebdec27922bb05344e22c4d4afb29b583	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584313918000000	1584918718000000	1647385918000000	1678921918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb465eebec0402abef0f85dbaffacb1188634cced4b81ebcb80cc7319ce7643752db2f0fe00e8e966540da82ea6a4cca7b55ee4f11f0b98fcb98e9a9dc705f203	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1584918418000000	1585523218000000	1647990418000000	1679526418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x51b13955bc711bd5162e0a5b64efdd1aa978c675eacd6e780b0e2632e9965a60db53669afe5f53bff7024812dc853a7cdb1632b74be37765d8b3f5d233b8cbb3	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1585522918000000	1586127718000000	1648594918000000	1680130918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x99c64875336f9958683f7516dfa7998866f8045b0dabeeb1367ea3764c408c652b354e27f52f80756c8a467431609aa7ee0b4745233efce7b73ce7c441146ccf	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586127418000000	1586732218000000	1649199418000000	1680735418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbd49ebb09751dfd72e136555346b5e2f2d3a829a5707da06fd31716d25e1e0be210e96c350adbf6db9d9e8cca70a55a275a89dc7d20fbefe0d8f950641310434	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	1586731918000000	1587336718000000	1649803918000000	1681339918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	http://localhost:8081/
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
4	Can add group	2	add_group
5	Can change group	2	change_group
6	Can delete group	2	delete_group
7	Can add user	3	add_user
8	Can change user	3	change_user
9	Can delete user	3	delete_user
10	Can add content type	4	add_contenttype
11	Can change content type	4	change_contenttype
12	Can delete content type	4	delete_contenttype
13	Can add session	5	add_session
14	Can change session	5	change_session
15	Can delete session	5	delete_session
16	Can add bank account	6	add_bankaccount
17	Can change bank account	6	change_bankaccount
18	Can delete bank account	6	delete_bankaccount
19	Can add bank transaction	7	add_banktransaction
20	Can change bank transaction	7	change_banktransaction
21	Can delete bank transaction	7	delete_banktransaction
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$36000$jxInYBM13ph2$j1dC/wLcjea3JrPxP+bBllrR0xZw9jfbMZvgN0Kt4ro=	\N	f	Bank				f	t	2019-09-02 03:32:21.569969+02
2	pbkdf2_sha256$36000$UQPrsNGNbOII$PtD0hblEUbDDzh9nHcU9oYFEl7GkYUN4D9Am74e7UNM=	\N	f	Exchange				f	t	2019-09-02 03:32:21.681541+02
3	pbkdf2_sha256$36000$Fp7GT8rE7rFv$cjyX7L4Bt5JIHVQzGn0JYppBBiWBcG5Qs/OF480Zoko=	\N	f	Tor				f	t	2019-09-02 03:32:21.747065+02
4	pbkdf2_sha256$36000$UgC4hxHd6c42$9AHjai6a++benBvrmPyfhWgWIkrkI33aq9Y/8hbPPKk=	\N	f	GNUnet				f	t	2019-09-02 03:32:21.814018+02
5	pbkdf2_sha256$36000$jQWG1vVbKJkd$3wXTyrXc2Th2t/wfzp75y88BXiGhnn0euAB7LC4MJ5o=	\N	f	Taler				f	t	2019-09-02 03:32:21.880165+02
6	pbkdf2_sha256$36000$8KnYIXBy718z$7q8MHc4ymQuIHtC8fTWSJAOtMkmeDdhErIW6CIvCbkw=	\N	f	FSF				f	t	2019-09-02 03:32:21.94667+02
7	pbkdf2_sha256$36000$grALZTeoT5k0$kwarcnbTlt5yU7c8NzUFS0Wu6ikkf44p5I50UFYQ6vs=	\N	f	Tutorial				f	t	2019-09-02 03:32:22.013865+02
8	pbkdf2_sha256$36000$1Gb40ckINupy$X/b7ALz5FUwkWV+88qezTIUK0NLb/3LIKcpxVjoLZ1g=	\N	f	Survey				f	t	2019-09-02 03:32:22.080215+02
9	pbkdf2_sha256$36000$wk2Zs6dkXRDv$seH9DfKvt2dhV8HKzW2LQ7ku+rkPi98RYHz1MtPNyvM=	\N	f	testuser-vSGQl1fS				f	t	2019-09-02 03:32:31.381193+02
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
\\x4d79212bab2301b38b857c0cf8259ff29abe39d6777b4c25d28fd070f29248fb2f43879c789a3c8ba9daa34fd4a1019f9c7efd3b7dd6dea3de5a6dac346f0574	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435313243433243303534304233424244423535343036444131394645443741453439373330393135413736314236444243423337463934413745353643333245373933393642353239414131363531344543443439463235374434364139343931424531393032444135324345314343324531444437364339423634433735343939324135363530304233434144343837364442343230313837313338333742394330433236444542454442464633383631433444324144394146313543433137394433334133374441313942363032334130314632413537383235364145384230363945323333384545443845434336343145443338464336304336454423290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x0aee9603be12a616c9ddbafcb693ae687f8f97bfb915627e05167325c7cff2a2f209457b3100e486c9f46da0c32aab9c0d2f3ec7c68bea0e8471a6dc4ffad804	1569201418000000	1569806218000000	1632273418000000	1663809418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb08da8c9476d63d7e06c10346ce1298a1800adbe68c2f72eb02d8ae914433cf32fd513e30a6195bd52ae154823217acd7db72ce81487ce07103e3d8eebe68796	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238364346373737373645333734424537313434363445373245374434463531324531313131313434453130393634343545394344344436314339373530423137323446383337364430423246303236313441374243413342374335393535454132383938433536454645354636413043303139453441443230444145384138383241334143333439313334443837433435444344374146363136434332323730353644353234323943363235454339433636464632344645303232364632303339373633304441433339323835304531393446423539413435383543373946413431383630303735304130324636363537344641463331454644463936313723290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xc77b22d80fa9b0af6b1a79db78f588b62c816a8edba92878f553e1c623a18484821d746ebcb852fd45c7efef4a778a3cbcc58287fc1c6774f34fa7da0945af0c	1567992418000000	1568597218000000	1631064418000000	1662600418000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x81e9200934772bf51c014250ed245075d4ef5c7c6bec17b4003ae92715572b0051bbbf4f7a113646fdbb4601158f7e9f669151993dfa64cb248b3b859846e1b8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333423846424533423931443842354146423431453936444331454230384143384443433845304633423843444441344346324233344437464542344332374243374339313143393544424137334545433542423139353041343732444231314538364339333931343632424643324236323234333041303546304535383239313732453536464134364132354531393341384535353234424433363741363338363443413236433245313342464231333645314145313743364442313238454235373842334335454644374430353839344145434344393139453933414545414539304546414137414331424633364233364445344436373946323045423323290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x2152e0fb9496acb12e1bb82c2e2117573b833bcc65853fcff41e0ad11a96c0cccd70a17957b418348230186051d8f56301b7d4151daa80046ba475d55d10f208	1568596918000000	1569201718000000	1631668918000000	1663204918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x921e2a2d60a8d8b9f08e420ef36175ec35de70c34eda7e7c6ae3e2776373b10f801ee906956b39625efb411fe8a034f9939bbd6896451458413dad146672192f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136353939313839383237433935443545384443423842414143323734314130344244303834413537444431363632303341373041444133313439343333453037343542354130323132443246454133433732413644454633433143313632373331313037333645413343334442463531413331393738383537443038424137433831384345303241463145423936304646363230304530303830414632343545323931333544314143353533364335333845323545394542384343353643383745393536364332324237353334433341333839443241353442444236313642334637323135334443303631374635384546394232433134383243434343463123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x226b4053f44a905c7607bd57ce41f2a9fefe278d063a33963748fbe1e0c32a7097943662756581f3336f6c6f7499f37f732da39693acbb30a3ff064abe17aa07	1569805918000000	1570410718000000	1632877918000000	1664413918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7fce153c7ae6f3a74f2cfa37822a412b24e9958b73d98506ce6dd6a461dc1731f851c34462521244ee4336cda36165e923b1fa28dc55ec14e5b1d2161796fd25	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136453032304136453137423936374343323246423239394246313933373639303134433834303337443841433145443445463138323934384543353846433532303535313746444146313144413635423638414431464637383141413541354641463931454532333239423042433133343533464435354343423734324639343041303233363846303433334331453832413644324643324336443643414241453938373533324433354134383833454234303046383142394533423534463032453837373338444437433744443133383934374446364130323634384645434642424446463230384336343146454632374432343539424437393838464623290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x9fdae2b7d91b87aa28c4199d30f249d0b13afbfce2d45faffd1208df0d0b77e663e8ade8e05bb4a21ac0cf2da07a578e97385136dd05d880f7c3b27d4a1a5c02	1567387918000000	1567992718000000	1630459918000000	1661995918000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53022566c4ad9ea3f872a11bd3f8448e79bd271af180a75d3fa13cc9d10722b7fbe0e997af720c444e78bc07f8a27f963b2b2e75399d662a21dd12038d8d5f09	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243453146353332443343374132413337383730433544453030333046384343393830424437453635343430433635373135334539463039434633313933383731353533413543333238364633433138384137384146413544463139463136354537444345443431394445393034373745424146443243314532324341393937333045463643373434413434433734454433303433444643353138464632303442303845433835383644303033383845373543314345454234413433393736424432324235313443453242323645314143333942344542384135413346343637313035363233343446344534413330423636343538324436303645434544343523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x4a20d2de7ff502aa7c12c4942a9747597f78a08aeca6885040001563fc7479c9f77a20ee8be82a41437a1b7b57f160e13775fc3bcd4b2eeb8b59b0cdf7931b09	1569201418000000	1569806218000000	1632273418000000	1663809418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x05251c1faecd6d69491bd1f25c9225f2e00f67b3e931227f17b7e8978861f7cd9625f7d68c84efb216afb3c33639b95d6a311294d84610a62c1b520dbf1d4b71	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341464534363339393143374539414537424635333038453635373532393839333745324235454530373042364441303334314431333535384330463741354332323345413944413635384242384139393641444432363936303235464634454337343434303930393341394135323837453142344334303333373744413544394136383942373435463545413944324633413837383343333135303339374533314641383132324234423336334545394533304642453732344434383246363731443946413237324537464135363043433430424643423136373535433235314546384441434531413133333630413337363433443046423942354133353323290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x27fa94be25a395afaa4835bc9669b6e645627766c133c75a0f02a6ec8af197424a0f1b5cc255bdbdd6d115176601d76ca5044e8e76b45f5e3a8f016fab634c03	1567992418000000	1568597218000000	1631064418000000	1662600418000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x578608dcc88dfba519a39046e31680feb64de5481eb3fe5388321d5548aa104718771ae37823aef539c572e16cd43f9536aae4ff9e1ea3616b9d3ef412473feb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238364345373844393841413341363243344546373634444245434141303933373833393543313838383233313933464545463332393036454338423139343635384245394142423831393138303341383541323139443839424431454544323231453839324143413742373735444541363246454530424633383632423041344143323638433046424443323131453034343536364645363836313134453534443938463642453434423146433132463630303534353739354535354246364143433730313945383441354534313442323042463735333531383244424130433932464142443234454242343639343141303846413845384230314630323123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x29e3216f20ab45df0b4f7cf1d0d98b798282a19b120349497b5f1c6bccaf721c0350bc6081993fc0f908ef6c9f42b9dd36af41b456833790fa80a0bd2b4e1900	1568596918000000	1569201718000000	1631668918000000	1663204918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xde76198e28dd4bdb77de929967d8dd9798e63ca5f5a7404ddf28638c15499810a46c4eba8e9187cf11ac62653f8a020dca12bf5894f7660f1455b4a38c1b4de1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304146334241433341344241333830434638333845314439464339323439433932304634453033393533433731433233393543333645333242333837383432384630453031384346343646423339463843313441413443333943373842394139443637323034413631453832394246393935414335393237363436363934314330454239413135314342333841434341423238413546393536384437374545314546303432393945324438314337393344453335363835413836453137313539393935303036363441314138464632444433333434374243393243353736343433364646413730424236443243444246374135314636334637424545313032343523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x058ba2cd8753f26d255c603a9662f849351de37392f42af273e6ff63c07fd9dcdc10111212ab8adba9542b991901da3900f45c7d802ee3ef6123c93e33d3a30a	1569805918000000	1570410718000000	1632877918000000	1664413918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x045ffbbfdd63a9be10ee2ea24532916da1228aea0cb039d46907c89bee4b07dd88af0f1c91ec5c7c302aff91d98cd6322cc5bcb2488b4f0e7400acee336ad7b4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304443354636303136394246393131364231394345413232354230303039383546334143423833383045394444353438303235384639453836363431393932363338344643423231323035373138413230383244364641464431373639314445343436363839423131464437353834383237453846433830453236354534383642364136343836413832363434343431433846414239343634453730323443413238374431423943334541383244393136323737453131444430374531454545443639443534324631383636383243444641433442433435443834443439463146333746454436443935334631423931334638304537423736413841413545433923290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xc723368f789c0d688cbb45969fc87d37ba6385c7c16040b881e635b7e6a2475e4ce832fdc1427c19919b8e366f70a20e0aadb63099d200d3c3b8641f3dacc90d	1567387918000000	1567992718000000	1630459918000000	1661995918000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x29c24f1a5677f61c124c6d89bacd1d5884deb47baf0d7a991c196d6a1f59af9712dbdde85a6cccdfd162c244974d2fe52b8c8068b12671a996c6cc2a8e8660a8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442353341353445434242414443394539393541383930353139374535364538334441464634433832304433324542334432373832433242374544303837303831373142303942433337373042454645433836313146353844374333423736323045394534463230454244383837453837373336343133433137333144423331364432413735354643453936304134364339303732383034383143333330393333383030373633363044323532313544373446434238463645343546334530324534303444424538313331453634333039384141423332303233373131374141364438324635453039444232344237373736374438343343433132393930314223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x7dda4b036c7b449fddfd3f9a1ccb4755fe5ff38c2c9e382219828547c439b61c2db4765aab83f0b50526dd226adfc00b79610482438b10690dc6676382417404	1569201418000000	1569806218000000	1632273418000000	1663809418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x61485bc4cf53af50a30802938756964a38c920759384bc1485b0e8c580740974c7f1e3a7e9a196f3e2d8608edae02ed8e24a2e64092b8a611523644107597d97	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238363731343930464237343637313645453036463541343337334234393538453934433238454536393134353631463735453846393244423746443241343635353039343945333038363643454533333134363845343734453243453834313143343734354644303133443043374333333542383136423833344333463343443037333546463345433742374431343438373330313641363235323239344636393033463737354237454535343830433637363942333536353936353139453146393231383741434443454532374237394635393441423443353444424245383734464236433743363331443039413743413446323633303336344636413123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xd4b7bc2f219c6a2f37656e6779ab9e355add7ef58cbed19d8c3ceeda628b39b2633ac3868e235711106831927948a9c0e4e1778180807f322f01fe1da89fc400	1567992418000000	1568597218000000	1631064418000000	1662600418000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73581611f6ca6275d1c22287104a97b07b3800ca74c602860f7f38348e6e57c908875882ca6203e64f19adb610b1a6ac88a3582db90d60c2a648a5d39fba97f1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431343033463237344441413646394442414632304446394132344344303833463333384235394443414135413146394133333637323534373243413444393043463435344342334138383934324336323644394241424630323442313138463539364341423230314433434245463033363542393641313137383135343935413445453046434331413343304138433546323630323635393831383234344334463135353531313746334234303431414144454239393337373941343733364146383743464230433445363632303338394446453932313434314131373045313134344639423034413133373344413432444338464233303842433935334223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xc2141cee463094e49068ba010ca18875d21f12c83f256796cc522743f5dd55231612cadeaa64719f7f3f780f606d8b58f91b3d23d2c323029fa0984d78a14a02	1568596918000000	1569201718000000	1631668918000000	1663204918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e5a4ac728f4d1d2c70524d8cd0814ea395a4ad8f9676cbcab7c065a6ba2c300c92d36c3879fc9e2be575fb8f18d0815a6653bfef0f1b2f36bafce30ac4a12a4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244413341323945363136423637323836433430373036464634434530313638343644344243363139463543354243383435453545313843344341324433443242443346353046453832413036423038384444304141363243324536373845434144334134363445363646433838353334413142313537343246433030393535423732363943313534333132304546354331343644373242313935323534324134374143374331394238393442314431364534364446384637383641383238343032374345424439383641344346333032323245324333314335303236314443464541443433353731344541343042304631394130424332324246334145363723290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x38b66641d7ca300a7931f329b4f2d131e851291985a5ba5942b8e84bbd94185fc5b3562195f94bf8e457643c93edfd79727f4f98f5bbad228eff6c20b349ad0e	1569805918000000	1570410718000000	1632877918000000	1664413918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4bf7b1906c4ce631dcb8e35a06acdeaa51238ad95b34fe0484f410bcd62811ffa0923f29d6993d1dbf10a23e0df78edf8737b8f8f651d2495f56599d45e87e17	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433304642453032333735344533333239443334414336363642303743453634334636433039453337353945373943424442383236463330453133373432323133364642313141383332423945433331383238373832333837313537324445324530433433343433313643444336433430344435344530353833374436353932384230424236414545373837314130414330373639384634374634433543343743384630444544443835384144393646324539333642353341383131413439443831314445453131313144423638333235324231373034354138373639323146304443434445444231373036363835423443373432424537393244424538303923290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x1cf974e1a4da8c763aeada801b961c73ac5a5e8b34ef71b27825f0750494cc37ce00c83f95812ea5abc6f22c69889f36f1d67d79861e8b05b6eb60ad10a37b06	1567387918000000	1567992718000000	1630459918000000	1661995918000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9828d4aca18577240693a0772dd64dc735f30cb8930ef98612d6cf09d2af1b3bf92e434ec2463abc2d92a844dc6107ccba3d5807f04a6b90681cd202586df51d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436354341333134354542373746373734373142334342304346374637414532304646454342434533383642364244414141393632364243313730334335413337414343313541414439444342414331464532393337434441393241453830303630393835334142434145393930414446343737394144353732464430454544383730333632344331343833454345383137444543453341314644333538383634373943334635364442374134384643384637363244383946364635343541383741384244313336413730443630344132463845393644424234303038463431433233324342453935334430384134444432424543443230383341323335373523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x02eaf3e9ab3f862be4f0d974cded468829c7f97c5169e21a45bebbe85937d91779b24a8747254ac422f26008886a2971dad806b4dbd68708a954788ca905a205	1569201418000000	1569806218000000	1632273418000000	1663809418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x02fae721800535fe19edb9c94bcb6bca4883922010c2d16f3b62a92167bbf8c18b361843874c0ab0123c745a9b947a1c2abee7409eb4ca341f201ed7d7849dba	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434374538443846383143334643353741464132333739343744444639424134384437393933334344384230443536443834364539343945323736373431333537443235364532353530393935353838363244324230413738424641364332344143374343394431353431453141374344393132443634414536453541314136303335444236313346343930353835343036464237373641363446344133393437443035343744424534323336313038354433314336323846364432354537353836323832393832343344443332324438464530363636393233304341453335463735363139413839313430333633303041363830463830364143374642393523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf3787012d793a62d9214a406cac8e0f6546c34fa7b8b50e83d5e24140fd879dbdc25b2daad1c491216ce8b8842b0cf73aaaae4f37bbf5c7ca7517b77456bf601	1567992418000000	1568597218000000	1631064418000000	1662600418000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa3901f16ae7ceb282fe6923f2a29887d368bf3d25630916058a5a08c173e202a7930bacba9082e0d89e70d02574bf5de2f45ac499c4c004dbc09588ed7fffb2b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531383535303636443339444446353135354243383938314344423230414430304430383734393532463833394444323641434533314239323739333130413334434434324344454339424144353038373231314142363230333644434631464143394636334144344132423631433032353042393438334535373942433535463941373139323833314636453537453943463230364342454236464543394437353838374339323930353446353643393938443041374232374639304538314545414430343131424639314446313343363832344134383241353643443738353337433238383942463941433546454434374135363439363432304437373523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x8f3fea838b7d8aeee61dcf0e73ac86b15e424227e09b29bd67f8dfe82fff872c9b3cdf32c3a86942adcac140285a1f045fcd07c87530f235306e8af3a77a0f04	1568596918000000	1569201718000000	1631668918000000	1663204918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd2f7658fc31a3c107de1389e73182b44dafb8918bf0bf20e5cc47e72ab174e45b431cd3a8c773376e9b700e8c55b4db5ceb2114d12e8a1f74c22adb784ab0d99	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303944393038374639384237443041463341343732303541414138443831443736353632364343303730323037333042433446444142343644423635303545323445373035324437374235463130364343344433323833414437454139363039414135444339383736323338323641313745344433434644424233334338313731444332443339344446383331373734393643323139394231343144364633343435444334463045423444354432453538423935324430344645413431434431463541303139353042393344373437383546334330393845454336433635393831323241434345374236453836363535313633423535374344324334344132324223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x86af1da79162d4aa624323673e41cc5982b6bac8bf40d301e5ff5b568e0a4addeba0a0f1528be94986946d701c374eefd41610aeca790c15166488288ffa240e	1569805918000000	1570410718000000	1632877918000000	1664413918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3491e05d76cf13b09fb39bc9da4a66e73bca7b331d9cf6c0747ed7014202f53cc1e52170cc70772169a2abac4388d44c23518c29acd3e258ece12a94c2317417	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143384232454234424245413532313631303541373934343742383934414633363938464338353246383742344444423432454343364231423832363939344432453934444633393333374142353636384638393830384243433836454533393834434643304532314234323231433345413032374445373043433544323437383838344139313245374235333143343742464233383537314634443243304239353542303946374639303241373246334235323039313232304630374637323231374345373133454241333938394339393030333131423838423830303139353943424644343339463331334334333841463442324532353136313938333723290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x7af7e99fdf5fb876e09eb428ed943e9a61c58eba99cda07a4071e1e8f636e61904ec0f75e6f3df0bfcc5311b250333c44f0d1ec26b819f0bf800fdfccd4f540f	1567387918000000	1567992718000000	1630459918000000	1661995918000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x987469b88a71be9a01137d4cf9b30d77cac0be1b8617458c9df810f3800ead502c4c51f9780b359126ffbe9a8511b02f2a369f4ce093b7b8faa006418c642fb0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304134394435353341324335443536373845313737344534444235463339443836454339383034373033353130334632463734313246414341444637464434353031393034363037413844374530303833314230364346353831353341343536373835354633373743413643454534393143344441333532413034414146303033363031394133373035383338433231313146354138394138353943334639434635313031443336453743324546374532463138393730343030414333433235334242354145424639414439364143384542463341363435364330423934423032313241313245323732333134424441383533393241344642313135343630453123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x1f1e3d7981726424d47dbe422a8c335877b0f15a2ba67bb7faf2e8a401b1874eaa0512c7d03a4ae764a2faa9c098ed8557acff93dad211fc6f51fc0831ab3306	1569201418000000	1569806218000000	1632273418000000	1663809418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x52d1bfad725718f845ceaddc68b7ff59c7f782082461f74765b391e562df9b0ef3aae613fcaeb99730c4ef261abb9a5e75900d5953220e0500dd362e82c970b0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430323942433935343938393145384443373637414145373232354644314142324143383034453933313145333735343131383242374538374230433537313038394443383139323939343441464430443142314334423341374538333934393536323444303233383045383837374330423034413337413330414437344133333336414239304532343241444430353641423836353843413136323341423734373434304233333737363133383842344344354134383137373146373937344434313133444336323042333137363238364238423031413137363431383343433738433831464335323042353737383534383030453843313739443436304223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x242fa3e2865fc215a5bc5cb73b07289b7a90347cf364d2a455496728b755bba83dc5ce2741226e66e5649a336bab26ecdd2c8af1e2a3e953e6813985e4232806	1567992418000000	1568597218000000	1631064418000000	1662600418000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x53fbc35b01d347f6a7fec63a3f7df5b35a42d4b0c7a5550b629fb80a26b17e06de6a4adab8fb5bd9234723b55196c3b9c9475186c1fedc03339689a1e71a0256	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531444632413733314533453639323339394135453134443943443439394638424639423941433835383730434534343943454635343237413632354536424238363131314541433338343143423744384145443944454646334234373635343030443146393738433044453732373033304139333343354344423938303531393445314441323230444234443439343644333333313342383446353232344346313032313141343336353632433937313835463038434246463545423938353638324546363441363946344339363431343732324146464342323744413537353846354632373835303346343437313834423738324432383841454238453923290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x3f67be80f0c10b87d01f924de4739123efc4f64817741f600f470855e4475dbba96643c502f3920c89aedb46c5181b085783bb14a29ca49f8a383ea72e98b501	1568596918000000	1569201718000000	1631668918000000	1663204918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4419699fab928dc29e550290a53d72285e2c09cf15df641c669e4194af79c52aff8b859e6354a4152a03124f4e4c2ba4b6cc68c976c4d26a438d8df5c9c0ebe9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246453432364330323334374241424537353732393939413738353739423532413230414334463438363046303232334444433735374546343835393843373837383538453135373236313632343146444434353842304239314136414437424535393243354434374135453437434431354441443433384431423543433832463837373735364435353236324542374631463946433936313242313237313535324239333530353442373145333034353532373634324536363435353045354645364236453142304443453144424530423537323934344133394636333431463146454238313630394234434230424341443245303344414244394443314623290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x9d61c4a0a38ea26c93c760fd06011609e951b98d20610f3a215b0d69d4e7100889381295effb9e6e52c14029d1007f66a118aef0dea3b8cbb80b7388c401e002	1569805918000000	1570410718000000	1632877918000000	1664413918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaab072a2885a0c82531c1d71454ccffbd9da46cae394cde7ac7b9b2c1832457415aa6be6185be0ee2ad446d3389c051f393715168d1e9973914627fbf2e0c5c7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244303531334335353741413642363933413730383732443135434331373741453534383531463338454231313531353444303438424438343743394345383641413142423234363831393135374242373835383543343643413243453145383135373039334343383642414632423534464146424131343832443644333034334234333936334130453631313544354138393536303534413331363237364439384236383939313944373636434342414546424346423341433644333233393744364241323941303731434538353431453531383845413333364337414631313439303838433542464533314444303444313546443944463634333939443323290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x5ab9916be95f0c87105983d5570b64726cc0cf30f0a41d4adc88c8c2899d745e2f6afb1496d95d09f8ea857e0ff2a1ffa2acf5cbbce0a9f230f2d04bdec2b10d	1567387918000000	1567992718000000	1630459918000000	1661995918000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x24df5661bf0eeb5ddac62f803ce8545c683d1b0e032a2935bb1041062bf2128fee218fdd4fbf72345432a0c4598811451c70474995153b4c30941661abc19454	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304438424645433245433231393537393637434535454539464530344545383445373433383635364538453132444131383536433234374336304439454545303546393831454233454346393145454539433430353837333633433431364630353843323734444132433138373538303032414344384134414133443634393241464337333433344345443234343434363235394238433134373841304234314343413735343533343743393636383346323631353145343545323634363034304642364530454233363839433941324438444133393939374639353732413138324446394637303443334642324142324641334243304137353230323638463923290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x6ca116fd719f6ef9e0a3cc4b0715c12db293050473095bcba03870c721b7d77bb4f46dea55f01554202e038ebd0766c436987f2c397fa1936eeb55dde7780d0e	1569201418000000	1569806218000000	1632273418000000	1663809418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3b5d94fc0e964b7c952763074784d18a2898ba70cabbc2cdc82a30a9fdfd5cc3c5390bed15a0339803ee4421ae261eee521b158a8d2adba37f8b4b15eba303a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339383932364439423233413736314146413638454446344142464630363541373145443832454632443042333436434230423444444132354633373233454530393736324634373637313241313734323431373735414441324244333642393730373431394638423130383431304545303638394446373134344343413237413841453234423445363943313342444535334633313734373339423335343236303637374245333234453034354542313933354334313141394144354337383231463538343639433446363030343236463542443537463946443543353732454546394636413736443331323235363131324641393042334131434238413523290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x4aea564df355d6c3defbe085d4303875c7b67d8933fce5fab647d5f8333298d242bae32d5d7e69c54928e44f119bdeeeeb1f66ab21390fcc79531bc60d139a02	1567992418000000	1568597218000000	1631064418000000	1662600418000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12d1afa48ba0c66496da9398ad7f8c7bea45ca7cceea629c3d881e6f7eb9251da4bdaae4c0ae8a933da20cff389b1124de6fa943204f97c7890aeefa840a0ab6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304135363145433345394244413635323033303735443246464534433036433542363443393742374335334543353732384442393931414435383346333435434235433033434143444546443544414134313239394338394430363534444636443743384437344145323745414339313145444444343744374238383739374141423038423138303444454535333644433845454446413633453937334538374235444636384145343345443931343237343436313235373938453230423335383933453933373945393431333942394242313133393934393136303234423434433738383234313632334333454343313730333332443131333545443345463123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x6cc9c67cf0d27f19f6475f12c8582944846e47f67c13cf5651833bc7d565ad7f9bb7eb7342e69353785c17f32c27d662e5287da4b349f84f1c216c617ca8380b	1568596918000000	1569201718000000	1631668918000000	1663204918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x28c51acb876b9bb2888fb74ff7cc2ac6e512a6b2b743bf02acbf1e3946b3f875d190ed12378ea97dd1d5e9532fa441de8bddb7e7dbf0dea6fac36a4bd77785d4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433393239304341413842454646413444344631313130453237464335433839334635324533413145433933353436373643383632303333353046363443434542314437313645343733413334303136323735343941423835434542383836463332324137413333443536373130363536334330444339443436304139454432393542384634323931414430363133423946393431364337364641393830414245343242423436463739364432384142373539314145443730393232424342304643364438423636303438323944383632373230463045463933304334433834433945353632323839384431384239453838433445373744344432383743364423290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x158994b7c0b7b5d404a81c484814477f760114056260f1e1532748a31a7eaff1b86758c15677507df32239bffe5eba8a315e69d4a314adc4572987a62f30b807	1569805918000000	1570410718000000	1632877918000000	1664413918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c8d8e8ebd129b5608357392d322c930610526417567642c324d1f06898dbf0cd73f5ea3dcf5421226cd5d3fe7363ef8a91ed608f79c6c79011ffa6a3689072b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230373143343130454541323545353444383143424438413936434139443535423332364638353635323544324141383135373436383045303338423130373330423539374546423336443645333842304244363837353036373044353430393037414446454133343641393143304144374635353730423431313536364535354243463331454546304344334241413741423736453730433636343937304231413642423946464642413546413744453044364146464233374530453734383846373043313742344439394530314639333838313843334635313834393434304231343846303439373531453144464133413836363546374546303946363323290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf344a3b1c546389d80cd3cb6d9b8bad2e13a68c235b267cfdbd98aac4de7ad5adef847d0ba8d7c481065561f2cd7dcf5338d0cd42d463f808254d0603100590e	1567387918000000	1567992718000000	1630459918000000	1661995918000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x574a5422469976a1ac55e79fc750ae84e52eed8918c4d98a9e9d6cab2342c95d5eede460622061681e2088dc49d07e7d4857b78dc98d776106935484cf3ebf84	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435394542324234344531323135373233334242423335353841414139314635443135463035413045363344364345413433384430393035413930433139323344373542324439394342433230323535424432464641363432374432453431413146393241343934413539384245334542394331363946433238434338354537393545373236423843383934373436383335363935463241394642463131323634373430343034303032313134343430423937393044353834363843344331423243423934383241303636303535384133323634444641423034373338413937363438423332433834334634454139363030413934393342433344423030423923290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x3e3e0cba7f7f5a4cd38bf69f8684793b94a31b8aab9c43aea4c729f280cd33ff0890d2dcf93698849b9a1408b1782c91f98016e24b5ddfd478a3f7bceb635c08	1569201418000000	1569806218000000	1632273418000000	1663809418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x60c40d70ffffee93c411d75ae87e5e28fec5e3b7178fc1e4c8ce55c9f75ede31f96c22d43ff0779d7b7d1b9e41e539bec99585a581ece1da21993c4c02381de7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304141464432334539444145314142394641443138464237334139373034444446434133353933354235423241353735384446443930353443323337334233304436374543464544314144303133463245463141433846453241443938453530304534344243463446463936463037413531434333353646353436303444393841383633434435354436303630323146303746444146454437454341453741344430323030333742424143453144363943323936393742384238383337363737324332343444454636363236443132413738384439304539364138433846374642394137394235373632453930323543303236333635463836313236463732393123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xa5949eda30cd8379c4365b25f9c9c707ae64e3da35170f995af8e1bfbba32d27a98650ffd5753346cc07d1e3fbb17e3875793e63007308d251e0f8edacb6e80d	1567992418000000	1568597218000000	1631064418000000	1662600418000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf887303386d31bfe24c0fd5cabb61c80a69b0053fc0cb0411db0aa5ee87adc856fc02278aa29bf6cd58835258b1bff1f5f3dcd39db77baaf21699c672e388991	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238423343423639313533353541434141453831444344383231384639333137383033343334433331303733393832373737424431363836424441433243434334393046374545333136343234413536443742313544433236453946323134464531414143304337363842313446313745423245364333383542413131433030314236363736394539413436393033444642313841444436413843363641343634413842423245414139413736444233373836324242343946304535423634463839323231454534464634453333343130373846423145343941433346423434423334324442334142363944424132433136463837314142424344344131313123290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x9cd77309a7c1882bb6eca37a91228d785a9d9231e26de9b01859f985923b65656d9e3f9133d08c71e13aa62b11ef895f35fa390ba3fd48caf116c0c331c7650b	1568596918000000	1569201718000000	1631668918000000	1663204918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x97c022e6cc047727696ce0578de15bfbaf9db153ee3002ea831b90648eae2d0c2bf03e7473bc8913c76a205ec679984dadae29ee8ae3ab5fae96a5c73b07ecfa	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304437303337363935464139324542433838374634454630354241444333363133364138393037423245343832303332353241343943434246423434343633323541423535303141433131433739454641353331364346304543444334454141393746413539463133443342364330354639434146324141393445433730423241313143443934333844463842463030434531373132443445323341433030443338313734454344333433314138343343323635303741384330373931373739354244383737304130464336423538344243424433353344464433313439434130383037304143393335324638453939363641353531313534323645374633324223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x939f9627928fa19df68bff413ea824fa35b042c92f1a37309f7f5c435a88155712a49867ded47e9af466701477b5e4e86f94a261ec220b3f9631429a058cfc0a	1569805918000000	1570410718000000	1632877918000000	1664413918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf217e3d883654ee30b61b914869afbb05213896e92ac866e3fb32ebae8b97e1c723fc394a6a9ac62ea6cc231298a0c165609a3ac192fdbbab97f3c0795eb8edc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304138373230304437373644374335344132344543383142304630443931424239413036433646313434373134383746303844363541424230424435353939454439303730353537374633333732373839453846354337413239444437354341364132433834413942343036323545464543463830433937303936453637314443314631453746453638424132314443433146324631424335464345443441353445323635323644364631313134343339353533443738333241303541374245364445413139393535423733393333414632304445433633363939413038443736373135413343453634383631463538333346383039443841364631384638344223290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x0bfef24877228ca15c9f0478656d456e68ae64dadaea85e2b415120ef0e957581ecb233268d192d6b6780768b9547bec7a76db8495bdc77703ce1240d7a23807	1567387918000000	1567992718000000	1630459918000000	1661995918000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x51b29f2e753d3df1c2850ed6e52c42476614a746447a5456e225c1d1da0248f8243a2c768543489853bc93b87bf6740fe6c1a05289a72a98386a48e46ae2e080	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439433635413343303834464430303534313337443733463330434444304237313533434138383145434142453834443430303334424232423138324239383946334437414533384243414236453131304541353635333145384138333643353946393138354645443736383530453238463037363135383336313739324241454137353536373738374430443339393137304333433541463741424545434346463838304630383534354241304437303235454338383238373630324444423241454335464638383532323135444536463734443842303338364634433435354136413733333841394433353439333538463432464235454345323842374423290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x738bc64d97582804b86e82535f4b8be5b2396d3cfbf6edb3c86e326d16d3cc790fff7dd2eaa3fa32e36ff849dc5045fdcf7a211e1509a7ad488e54b047c3ae0b	1569201418000000	1569806218000000	1632273418000000	1663809418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x72c1a3644e5634163b16fd0c8de7fb9c55e449fc765143fb977b5ca7f93c91c27bc12e5fbd720931473670f7aa2c8e73acc716b3227e26ef053084129ab1dce2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304141393139303637363337454446423738343741463230464542424446383135434538314646333834384130443935363145313941433230413742394636314331453933463035464131414132424131453039343243423739444439354245434135444232373134434138353038413430343234313242323439463441393735313843373744413844433832333344343430303546463444373131383630313045343345304442443737413945413030303446313644373537394235453039384445313339383041454642333230443235453836354239314632313542464642434435443233443032393639364245303139433746324246323731313733394623290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x10e4fc603415689a016e65360ead68999212a50d339cd687df7ece5872dd766b2d5ae39761170aa86a0812c9e7a96db7606994570b90bbaae3c82770ec847c0f	1567992418000000	1568597218000000	1631064418000000	1662600418000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa00afe7e77f5b4bd1f7342d5798f6324c5b7a03ce01c21a4a9c547c42fb8328ece94935337389043b5321dc2545d49e13f236de9eb93e98881c5914828ae52d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234314442384339464231414642304539344543323238413045344544324338334633363531463634443342383543383044434439323334383842363135453830363042434446424433443643414130303036423045343237463041344642453641323438433737313742343742383245373134303938354634343437363939353146423045333037333330313537433135343841393546304143453744333736443846423235463335424539354133453637323132414136453937333632363139313541363743313839434645343241344133373746313142364641464636313439374541433144353935364642414546453144313732314533333833423723290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xac5af27b04b3eb5c0cca4166a3f4a852cadb047894b53a8f4a61ec12f1af94a6650c95af252e1a2bbe70e897d4169c09192ac86506fb6f875d20470ce9ab4801	1568596918000000	1569201718000000	1631668918000000	1663204918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xac928f7465c613751e8ac57b58f4d27f7fbeeaec78d9a40f93959c48f09bfa53137fb1d2101a1019bfdaf28363fe1006852fdebef32526ef69b8fa182a4166a5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304437373437373332454138304231373634333146463041313233464538384631354445354633363939373645444234303232374333413043454638424441384143393237383037413634434635443937363731353034454237433839454336324433414535333338363137373936423743374537364431433930463238343536334538423644394138344444363745334544303245343038354245433438414338354438333336303330443438464438463345353936334430453744393532384245413937443436334139434245304239433333353642463537434531343038434641383232323742333830384245443835343832334231304541463039453723290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xaf0c7038c7fa1fd40144d4357153a1486cffa9d299d3fce2eb6e83538bde28527fbc9fef89b88072db21c63fc5826411dcbeccd31f0552838b310674f8c5b208	1569805918000000	1570410718000000	1632877918000000	1664413918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235303832373835334639354238373832463246374435353031463039334142383437314142354544333130423931413834354431303545323342413544313446363744304231323941373535464431444643333331324341363838454641384232304135313939304537454636464231444337333535393744433043454331433836373044414434303938464544363035364338453234444539434142464335303538364246353042344330443543413246373533354139333042413939464632363132453136433237414130304442383034454236343939324641454336414441324334384243413739433041443332444531464541374243334344433323290a20202865202330313030303123290a2020290a20290a	\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\x58fba11fe0462336a6304fb87b33c1960b08859b37c5596008a819d05d67315b2cbacbd33944877edc36f12d861723596c47dc5f119732c77dc4569d199fe50d	1567387918000000	1567992718000000	1630459918000000	1661995918000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\x2c4fb02468126fde91320cd6be8cdeca0d0e7c6db9c7b97e577eab40c4d4e534	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x66fe206dceb70ba7269621b20fff50e86c55c8f65230cca903aa0305c06070c8ada38941ee7a9f8334ef28c5367ec7dd7c7fdccf85c2794996f8e72aabcdd304	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
2	\\x873584982c7efa252d5d8bb309a5feca5ba2b8aeb52c1613a698c37ef6e76f91	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x99477ea3ce9f169ebb5f462e3e68989b34b5c1815e7ce2bdeaa0c4c2905b04e362f5b0f2c01ee893f824b43b9bb5214ebd2d36a0b9439270e00a0b7899ba7e06	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
3	\\x7f999d1854f6492bdab1eec0a935b397ab68207266928ad10f2348ac71b13625	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\xcbb5e37e4f0b80ed2ad1cfd0cc8cc94371747e7d6a05c8dd9aa5a2c7e6af7e2db1740357382962f187d4af37f2fdb66344947e46b07755fb98f04d3ea03c6709	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
4	\\x3fff091c8e230d936391f2741b3a1a7e54e475148c15ad67ff50467d13f63b00	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\xd14c7f34251608ea4aaefd9d9b9d6217b11746d7798a02afbb27c93d9d1cebb84fa2bafa75d28bfb46ee902235f148d93a9429fd84154759545108dbbb91fe03	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
5	\\xa0a7d5f2d14175db90163fd1f251b21879777ea7ef71926274c2d68109a1b9be	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x6e825487c727510292601ce370c179acc2129e9dee7f392e7076cff7ac70f8bd1aa3e46139a48b8e73d86693d66433655db9eeca873cafc61579bacc039ec408	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
6	\\xfbc1b803b0885f08d5790f9a86e72dca55fdcd863076b5e128f3ac2245c18434	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x5da3af0084fbd4a534336f02a76cd259874e65be3c6f9d13c845c1f16f242959fae3bc82fef3c56785d8546c21d6e52b687b3fbe22bf3494f8a3821079d09e0b	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
7	\\xf706fe2f8ecebbc16d6222f7a3ac0e37329bcc3195702a9bd9ec86a604a60ecd	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x33d3ab1ae4142a9e6482839776068d90159035392b412ae5fb804db077f090478ec837279a47249b20c0efde652a6a104edb4bccb1493e740979ec1ac6583d04	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
8	\\x88f249d77bb721a9081078684490636955bddc6b63473ea6167072d27d7ee808	0	10000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\xca2d285614372dbecb3b5d057518aaf37167763cb827097751f7cfff0a8130c19c5271daf7298804a56e807d6e67a00efa2bdfb8f21744ef13168d0c152d4f00	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
9	\\xc6e5ccac351463e2197f58acc50590c53c0cf730bf9da1e4465bab41820e1e73	4	20000000	1567387953000000	0	1569202353000000	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x9aeba0d3cb4ecbc77b624831af70a0fe585465c7fe88630a7ac971cd3f57dab25f66adeb6611857bf7931d8138e3a4ff8510edaf9e9069c35fa52f4490383098	\\x791b9cb5c49f6a46950d3cb05d8b2fa0dd40d0b8b1c0c808b137bd9ec5f5b7b43b9dc5fbd1bafb352774689410f41108f62d953aad9de9f5234134855d936602	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"SH6JQX9ZRJKFEMX0FNHNFAXZJ8FGV4Q2TFCJYTE26RRMZ1BTY2FG19T3BCCVDFHBVAF51ZP2GY8M63JB01HKC45D9A4HG16YFXBBEM8"}	f	f
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
7	app	banktransaction
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2019-09-02 03:32:18.185902+02
2	auth	0001_initial	2019-09-02 03:32:20.134277+02
3	app	0001_initial	2019-09-02 03:32:20.769386+02
4	app	0002_bankaccount_amount	2019-09-02 03:32:20.77921+02
5	app	0003_auto_20171030_1346	2019-09-02 03:32:20.790645+02
6	app	0004_auto_20171030_1428	2019-09-02 03:32:20.802106+02
7	app	0005_remove_banktransaction_currency	2019-09-02 03:32:20.81358+02
8	app	0006_auto_20171031_0823	2019-09-02 03:32:20.825248+02
9	app	0007_auto_20171031_0906	2019-09-02 03:32:20.836978+02
10	app	0008_auto_20171031_0938	2019-09-02 03:32:20.847144+02
11	app	0009_auto_20171120_1642	2019-09-02 03:32:20.858701+02
12	app	0010_banktransaction_cancelled	2019-09-02 03:32:20.869487+02
13	app	0011_banktransaction_reimburses	2019-09-02 03:32:20.880419+02
14	app	0012_auto_20171212_1540	2019-09-02 03:32:20.892019+02
15	app	0013_remove_banktransaction_reimburses	2019-09-02 03:32:20.902046+02
16	contenttypes	0002_remove_content_type_name	2019-09-02 03:32:20.957674+02
17	auth	0002_alter_permission_name_max_length	2019-09-02 03:32:20.991003+02
18	auth	0003_alter_user_email_max_length	2019-09-02 03:32:21.035309+02
19	auth	0004_alter_user_username_opts	2019-09-02 03:32:21.061421+02
20	auth	0005_alter_user_last_login_null	2019-09-02 03:32:21.091497+02
21	auth	0006_require_contenttypes_0002	2019-09-02 03:32:21.103549+02
22	auth	0007_alter_validators_add_error_messages	2019-09-02 03:32:21.128608+02
23	auth	0008_alter_user_username_max_length	2019-09-02 03:32:21.203375+02
24	sessions	0001_initial	2019-09-02 03:32:21.382037+02
25	app	0001_squashed_0013_remove_banktransaction_reimburses	2019-09-02 03:32:21.396413+02
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
\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x922432819c0309a5a38a7ba3fbfa418541699e7f801f3a4c06d1ebf85f14b0418ec89b731bf9f191ce93ecebdd30fecb93f186a8becd79d357dfd14fb4eef90a
\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x0267ccb32d9f3415c18a5d2eaa254b173b9e8e33d9c469765c9bf7db9dee329f32f53c4b58b832c7ad2d174d2411c27f0888d4a5ad2bc4da78884a8e33f17d02
\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x741d0e1f4257ff0512fba2ebcd3daee6b5a91b50bb6af1bc5f8f1e0343ecab01da88b4ccf6c654a7581bfab100332e2e19a5813b1f49d20f0ad6f2c6ad3b700a
\\x6cfdabad759063d258466161da5ad6fd8c9aed4bc5b45079c294704a69867df3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x3f00bfc029f34987a826219e6964bf84590fe34f939a65b2fcdd8b94d4c7277fcd12b145d0bd6afa467a3f306c572b8a9b553d5ffdcfe1d26fe27d6ae9acd10c
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x2c4fb02468126fde91320cd6be8cdeca0d0e7c6db9c7b97e577eab40c4d4e534	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233338463238383838453531434236324334303135423734303636423146453942394344333736313843433931464241303832413236323544343634443735423539464539444237334438393234374434323631343837444232334235454530463743304236303146413634333738353937423338463542413538303433464432433130353236373541363237423837393736414137434334343233463331393743444238373432423444443531303738393243314438463533343430423738384542333237443941383736433537423038394432384533343934303837443834343136374441453433444431364446443039323038414439413936343343453223290a2020290a20290a
\\x873584982c7efa252d5d8bb309a5feca5ba2b8aeb52c1613a698c37ef6e76f91	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233837323541313730414333464633314636393130393836433232353033353442383941374443313037333033363742393739354433353130454132343941314244453933304138313136464636344630393844393032423744363430314542374146323237363538323939304142433432343035344634334134434331444336463630323336334539383644413032433341444646314641414536363139453637384343313133314136313232344145304334423946384546454435353046423432333334364233363445363034323546433237363634444231303041413830334344453841463743423734443041414130314333413334434545384537414623290a2020290a20290a
\\x7f999d1854f6492bdab1eec0a935b397ab68207266928ad10f2348ac71b13625	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233046464331364444333337414337324546303633383831353131353530394337434541454336344431374142463637303345384336343338384635354637423433453932454133424131434137313030333933433738424346393045343437453839364642463545364346423535333936383146324143464337303736364141363643303634353646414344443536443643303339393634463130414532453344363132343033373846443637343332313841334535434644414446364543383343424538444536394436423241383437393235453835444443304245444544433244343845314246463232354135303330333239314642363432373931344623290a2020290a20290a
\\x3fff091c8e230d936391f2741b3a1a7e54e475148c15ad67ff50467d13f63b00	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233242453538423841383430433639313439303231423245304144353937303245343132433130313644463044433230324331413842363239343542354141323541444142324545453341363941363945353138324145354146414634393942383433423343454330323138354232373542363533313438394239423246363641443235344646383945333446433530433433464334303033373838443946394230324139333345304334374437383845414234384635343033434338364435434342333945364431414238433443313035453135453744383934354439334141414635314445323444313937383836384133363543363546314238333236363323290a2020290a20290a
\\xa0a7d5f2d14175db90163fd1f251b21879777ea7ef71926274c2d68109a1b9be	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233234314239353038393938334335423444314344453139373939424434353132343338304145343830313736434245393137343246374436423944413641393845303431464339353933313645344243433233453745433935313139464539453733373133323145354641393738433646393935304531423634394439383041394643463843373942453046353135464344453844413338353930304544443034464339313636313432373833324232354336453030303934303839414230413642363732453532354335343438304541354543433237344245353032463931463943343337303238423930424134304243393643464646333439394635464623290a2020290a20290a
\\xfbc1b803b0885f08d5790f9a86e72dca55fdcd863076b5e128f3ac2245c18434	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233535393943443441443841423237394236374335314338373245303830424539443844453745424636443845303032433344324232334434343336453937313230303445454238393939423545323546443545453130454638334637354432364144353732383937323639453131444137463739363946423633323136433731304233333044324431444635463939334230333230393741384332323238374437373535424132393535444141454130444138343439453030323335413836463637373537414436413343313845413733423846434242383430453946344232434446463844363439434446333444303930433046373143374642334432363223290a2020290a20290a
\\xf706fe2f8ecebbc16d6222f7a3ac0e37329bcc3195702a9bd9ec86a604a60ecd	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233444383941373739423638343336334337303832313633354646453236344130364630424137393743363230453941354233363044393336464239303643353535353746394234463533463532384139314535434239364338323945394535373830313542303433453746413031303230304232383739393830334642334332323239354237383431363944304138453344464642334542424339423942443038384334323137453631424539333837323232304343443137413431363745444430443234353641384646354543443438304331433535394131414246313134314137413530463444333332354633423336434436313531334135363633394623290a2020290a20290a
\\x88f249d77bb721a9081078684490636955bddc6b63473ea6167072d27d7ee808	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233744334632374131374346463038383433333937414530353441453336364337323639303330413143424543423642374443413643413636373746443536463344344531463731463538453145463741334437423339323734363036434443433036393839423837363143453244443837453230444146383746464246323139313435373541413745303439344541303635423536443530413341363932413741413630434332373832444146354245353042334341313942433930353238414330333143443637364644303834313541434445423638343537453844333137464442303036383031323434444338313231363545454532433843323245444123290a2020290a20290a
\\xc6e5ccac351463e2197f58acc50590c53c0cf730bf9da1e4465bab41820e1e73	\\x7fce153c7ae6f3a74f2cfa37822a412b24e9958b73d98506ce6dd6a461dc1731f851c34462521244ee4336cda36165e923b1fa28dc55ec14e5b1d2161796fd25	\\x287369672d76616c200a2028727361200a2020287320233646314634393942303142344134423437433933323643393739353839454138433844413833303635393942314332363942304235433545434243454434454244324336343543383132394635353942384439303945334633453637354132463746314331384236413038373145323431334536443638353544353142383433354232304436453041363641343435394441453834444632393232393736454531373939343532454531343138413930344344463931333341334331373446373441323535443734464232363442324143424443423143383534383534433538414542433134454532313237414342423844424646353244334336363331443023290a2020290a20290a
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
2019.245.03.32.33-01M39CR96JDDJ	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234352e30332e33322e33332d30314d3339435239364a44444a222c2274696d657374616d70223a222f446174652831353637333837393533292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637343734333533292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22444b59545142424e4a31485834503236433547584d5050505a5036394e56414252505435305945324a4852344d54433646515347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224b424e54314d5942395635574559563239305254595735305a534335385345375a54343636324b5453355257544654515641533559534e4458444b3133314256595939485630395257454a465a313847585051535834333952444654414254344a305733313630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223641514334535a58344838463333304439504b544b454b35444d50423954334b3551313631564a564454475a4a31585334575030222c226e6f6e6365223a22454b4d51465937364434373859534533324b57445a47594836504441324a445146594b474a415738573353434651325a50344830227d	\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	1567387953000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x2c4fb02468126fde91320cd6be8cdeca0d0e7c6db9c7b97e577eab40c4d4e534	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2248504244525144565353364353385a375648423332423637304e4733435950414e3956375441444343535156414836473344473331345742513044523357345441455a464546365036344852315a42303654424b5152484b4450354d3242474631364b35523130222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x873584982c7efa252d5d8bb309a5feca5ba2b8aeb52c1613a698c37ef6e76f91	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22373956364d324e4836595037304651544551375833453048544b325859524a41454b4d30524b58414b4d484630365434354b57314a4d54414a38395a574450454a4837464b36564845355a5847394559434d5a3048524d52474842343052574631304857593238222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x7f999d1854f6492bdab1eec0a935b397ab68207266928ad10f2348ac71b13625	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223456364a5233574436314a4a5151573830393232384348384d3338525745575a504a5056563247523738474a563747515841325a54563335534347305648455758465a52383230573232344a3758544458573757514a365237303958303732525a304134323047222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x3fff091c8e230d936391f2741b3a1a7e54e475148c15ad67ff50467d13f63b00	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a545250534a444254594e4452335a59334d324633534e4d444d303156335235374859523731454e4e5230364456334a43515031434e5a46333730323339374a3041535946465738533433304d3441304d354e30593642595a4230474246534b34503034323347222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xa0a7d5f2d14175db90163fd1f251b21879777ea7ef71926274c2d68109a1b9be	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224d594a525630484d584554585054324a383330444d45334738543556514534354b384e46344a5830574d5a434553453458564d3236364745463253324d415847394a39384e3736503448305244474433465a304e54303042473056534d545048364b5456433147222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xfbc1b803b0885f08d5790f9a86e72dca55fdcd863076b5e128f3ac2245c18434	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224230544635454756594a413659354159315a465a5a4d3638484139463059414235584132355a5a5a575634413056544544454d445a3636465246565a5958443144455451323242325751533132314251453038484e3136563439354d4830484445484645473252222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xf706fe2f8ecebbc16d6222f7a3ac0e37329bcc3195702a9bd9ec86a604a60ecd	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22503131564452394a393158453434504242463235394437344e375652304633515830475a37425435333332415247305646413131574e4b3441545a4a573330384a46354336343352484354465259454637424448524b334b334d425056573538543134464d3330222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x88f249d77bb721a9081078684490636955bddc6b63473ea6167072d27d7ee808	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223535344539414139374b525058355636545a36364438313858304735373451575a354b4e50373557395a51433059515231335744564d5843363933505147435a364357443447444132424246525a56585344303743343356473254414b35314535525a4d4a3152222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\\xf32fa08f3666c331a42349bae1ca6ae6187fbc85adcec0acc348442f5c7938af1dfad8581693e75f33654b8815d77b23d9b7f120c0e28a13018bfac4eae29645	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\xc6e5ccac351463e2197f58acc50590c53c0cf730bf9da1e4465bab41820e1e73	http://localhost:8081/	4	20000000	0	2000000	0	4000000	0	1000000	\\x3f413887c490f272efedc3193174921e5d531942962fba2521a3a0d1312175e1	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22524835453537484a41453241594d59444d51464e453331355341464650314b34505248365a3536395436515057444b593133574e59323238334148483152483259483853444b3045435346513943514d4151384d5a5a34564236383636305054474b324a323347222c22707562223a223758304b483159344a33533735565a445243434b3258344a3353454e363641324a5251564d3939314d4547443243393145514747227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.245.03.32.33-01M39CR96JDDJ	\\x32aec267fd2450f18c0d4da7a9ba656d2cb4e8732dc260ee5b6ea1f907b9272c	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234352e30332e33322e33332d30314d3339435239364a44444a222c2274696d657374616d70223a222f446174652831353637333837393533292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637343734333533292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22444b59545142424e4a31485834503236433547584d5050505a5036394e56414252505435305945324a4852344d54433646515347227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224b424e54314d5942395635574559563239305254595735305a534335385345375a54343636324b5453355257544654515641533559534e4458444b3133314256595939485630395257454a465a313847585051535834333952444654414254344a305733313630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a223641514334535a58344838463333304439504b544b454b35444d50423954334b3551313631564a564454475a4a31585334575030227d	1567387953000000
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
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
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
\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	payto://x-taler-bank/localhost:8082/9	0	1000000	1569807151000000	1788139953000000
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
1	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1567387951000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x30873eded933aa7e2fb71352ad99893fb93019b43477bb9206fa20660e911d67f4f981520248342acd1d833269ee96487f74ab1a45cffc2db313222907513905	\\x7fce153c7ae6f3a74f2cfa37822a412b24e9958b73d98506ce6dd6a461dc1731f851c34462521244ee4336cda36165e923b1fa28dc55ec14e5b1d2161796fd25	\\x287369672d76616c200a2028727361200a2020287320233237413041324631333237463246393844374645423132423038453344324336394544383145463633383036434632354530413643354233453144333734343637423843424635443233324232383433374135354631334131434542324245314636313141334431463036334344413543443739383235324233363644424244434431304639423446323939443545333039433030314646393541393742464343423431323445313932304338344445443844414233354635373745393433463737333344363631383942413439333341323245453735433735443343373241343330414141364236323933383542313038343436373538304538314136383823290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\xf0a5c4723b6706da8a85ac2ba484bd4aa04c710c0c67936ba5a630eeb5020660fdf5fd37aea75b64223e1941fde0b720d4e3a7c2068ae611e4c9bc6a3cfd860e	1567387953000000	8	5000000
2	\\x3280fbbbd3763f06bb1a4a27b2c081566321d40d2353c48d12842b9469f758a30936cce832142bdd04f76ed9cf23783cb77fa7420a95ceaca870a8a15c999d9e	\\xaab072a2885a0c82531c1d71454ccffbd9da46cae394cde7ac7b9b2c1832457415aa6be6185be0ee2ad446d3389c051f393715168d1e9973914627fbf2e0c5c7	\\x287369672d76616c200a2028727361200a2020287320233843344339363830434237443530433342454537443243303231463446433334323341453641394546463041383631313436343830303844414541333131313443354333433235343036394643384338373735444146364232323944444342343135434332324635323334394546324342423943443741354430444243334231463031464145374336353843363731303438433842454342344336343942384238303436394541423435423838443139354634454646313242454441443942443931324433303843344438444236344344393433433331443530443737344236444231423145413843324431414245444643313333343436303041464644393223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x50e2c79ffafd48b22230ea7556f3fd718930a73f8eba8ac199eb76094800958d0fb4d44e851a9bc37190b4987de71072500bb33f6597d2689b741babc1337e0d	1567387953000000	1	2000000
3	\\x2ac5bf4fb9708206db6c01139a88af24129df500fc22ae589a12e03aff3c46947ac71233a5d9adf838ac4c7a596ce5d9332dda018cb8e339b3d0a077e1b64792	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320234137433733334231394646314237463439334239344332314638413542333130313743434233393830383543463936363935323335384531393545373646443532383334463136383839324634394438463634463231324545324446414231364231453936443446344534303732354135314130434130413533334131303836463830313446354233373932463238413541303246463930383846323146423832344542433246343034333143423837394243343139443531344139443642454637414338373438363039343731333135354539424342323542393844463333414441454646363136454438413235324137384138323143374237364232313223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x352aeeb0ba4778881c88f7a7f8047351669d374bd2610d9f78b73459be4c162d8a609ed3b7026fc64128f2268791c03993aba9834db085f689bf071a36aca202	1567387953000000	0	11000000
4	\\x93c359a4ae19867480e68dc0faade7f11fc5217de139f991ba0a72015399207fa6975e9fe645ca2cd3610d9a899fbc439cf60404cd0d1419716f9e1420ce6609	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233344414243374142323031314237383539384242323534373832343839344544424142433037313141363732373345423142443030424334393533343042333931464636383933343546363145353036354434303833444232394342433230384244364243303143443830314542423446343344373233354546423834433245363146314632343830383332353344313839364631313936454143393238463044373637343631423041354332313130333235433036324238333941373944423643453945313846314245324644363233443145444342364630373244334244424635384646463237413944464230353143424230374543373836363331314223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\xad5a53d07a50b46fce8a4717e8730561d00177be2163aabff191425b35d66df49f15457b1ec666b5000e174d1b967db373633c8a0dc495a8e4bf038fa6c1fa05	1567387953000000	0	11000000
5	\\x0fc5864fe95aa4697d497eab91a79382cf82415c07e0f4ec8be93d6b789c34da71cd2c1088798fb4d4aa9f881b6035d6e22884a76a68ef37fb9ad4d7e2f7faea	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233442323433453334394545444336313442463433363937454544394643443839363041364533343543303141443431313534374638453444433630464333394637363738463536373346383533383246333431393137333444363239443242303946453239443934333631434346383545353544393431394236433535394346373431364642374534374532393342374431464330454634454442343445383338374435314230453342394537313937303739314146373433413038334432384138413532384132423346374636393933344637303535423045453043344537414542453146354142353330434539423037353545353542423446433637353423290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x26aae5a1a62c1f940e7049a0f512b99ccbd01842e983fec44534485ffc0564d6e65a359d066dbecacfbcb8a561b0082fae26a20917f0112237152be0e0000602	1567387953000000	0	11000000
6	\\xf5a643d4339a554ef2d73acf2ea63f23b2b1b33e79d88aad03b489aaf43cb21ea8a4e8889dca6ca1bd6234b6228bfacb9410040d44dfb1efd061eafef9441d7d	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233633424332424436443334333133353937434334334230453046323046444444433433313938324338433644323331334446354241333332393641453436343731413834413246364331373730374438463841384132374635313134423435424641433637434446464344313145363537334134394646394633454536324238413437464344334433454642304234414543333133333043333635334134303936303635443333443842323545353333464338423334444338333242304435423237444437313739383842334438344230384643413242434337364433354536393938303246384335354132424645393644364337333746364238394431434123290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\xefe22605049f02fbe77c1a61cd3df9d94df0a7e96b215280af43433aa9c3ef0504ffffba4a4582cb97e0a4f4ae7afe69d51225d91fdb2f398eb5d2ddba6ce903	1567387953000000	0	11000000
7	\\xb1f3216732728f543d416044ab22b6f6a42b5a49df4e283ea62fba11c1b600d43cbcbfe420400d29781f0b5cf4f0cd165892fd2633a0501f258cf7c97c19527a	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233033313530384637303739333535314438384546443544424438413943384135413443364635323343323741304138443643423745353338334439423544423330303831303135453341423345333244373442443735463830373846313932343446383841463731334441374637453946443839343235423536363941323443453637314146394343303534364142354243323435394444373938454441314342383032383638383139353439334631364238364630343736334442433543383430313631343042324643354334424136394331383145324535433734424445393341373746343635434633443643304444314442344544353539363336453023290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x084d1824ea7e8c513ea71ffebc1f84e7e7f9923f5e5b46e81d6fef91e14f83e914a1f1f0975c7b4cb6bc1afbd6a17e1892d860275fef943d7cc7679e87d2520a	1567387953000000	0	11000000
8	\\x6df54084c32b185f85923a39c24cf9a5892a87d6f57259e88b48cb07791d2546f7acee08864dc1472ba28c9cbdfb1755b1b5ea498b23dfa2df5a72821d16e4f9	\\xf217e3d883654ee30b61b914869afbb05213896e92ac866e3fb32ebae8b97e1c723fc394a6a9ac62ea6cc231298a0c165609a3ac192fdbbab97f3c0795eb8edc	\\x287369672d76616c200a2028727361200a2020287320233939373546443435333843423332413533463338443931314630364630423039453835394642424243453932333244323438324143354639444143323641363535423346323144333332304542334330323233393936444537443645364143394342344435444437413935323234323337344338423642374634463042454338324445323432444334434635393235303545313239454334384342443739394536363336413545353533443036324434463845384236443936383036313636343835344234394542393835393245333434463442353835374345373643373539324232463033464339433736423934334641333141443533303338354145433723290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x61e96bb772a9737cc040a8fe8195476d5aaecc7a7e37e60f5dce1abc0ab94a204a1b909b1f28301c02f47c322977e5855a218f88a9505d04144be84c4b62e204	1567387953000000	0	2000000
9	\\x614b0e2b15ae1f7aadf328a8f743a398f8a49a2f6386a8b900ea366ddf45d6860e49102704c456d58c9bd84195bbee4d8d800ce4a8797568b787356c101b0594	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320234230374532453234453632463332363230424335363439334536303835443833463633413934393030383046313431423335343146433135383731453545413241354134313944453443363338354634353343463830304144434232443342393339423046354142393632453130313537303033413638313241463046333031373239373244364436383033464336353234443036454139323436353534313235433131464438303932464636453133333937374244434231464245303136443533374235463931373238463033313337324146383532384134454443363032373833313446423844323744394331413638353741443846363937443343434223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x3f3cc988b0934576781ccfa92309d14a4a97fd6b76707a0b25c3d97b8f1f3ac1771c7e7f2767f672706638b9387b1cc30d74850c91008ab8d93422e9b7bcbc0f	1567387953000000	0	11000000
10	\\xff4e2f01bc26dc0c97eb388a4ff27fb460bce0d20ba5185e9c83e44fd642ec745559ecca61dd700fb586fef21ee379694db6f0237cfea1c5bb019959276e3db4	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233442463941303334444338364134333639314241464241314535413432393041424636374637303245334145433334373145304138454144334330383834393732343631363337374643423046333234413734363041383736303137444545304136373546334543464330354134454542424439313235453039303936323844343832363845433731413145343344354339383437304142333043394146394635353237324641343830324346373041324339433236313043444337424342443241333044334542454145453244414534423037464146463537303833434631333330303535423744443832443439414233374633453531353231413035394323290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x88284ab98ef975f6665c76117cf85f73644b20edee31db61ae8e81cbf78c69e5eaa8020ff149100b832eeb47c2161585552c5e67b01cdffcc287cb15fe459d06	1567387953000000	0	11000000
11	\\x4365eb72d0bfc22d23893ebe284689f0454d110dfd5bf843d4c9076b6ab80152276df4075b1c427d6700241c77bb30ae1c4266c095c42172e730e93c903b72ad	\\xf217e3d883654ee30b61b914869afbb05213896e92ac866e3fb32ebae8b97e1c723fc394a6a9ac62ea6cc231298a0c165609a3ac192fdbbab97f3c0795eb8edc	\\x287369672d76616c200a2028727361200a2020287320233237314337373843333935363746313437343031343036374141313744374431333142303533394146463243423435304435394337303536454444443341343044453936454145394530333335393439323732344237303245373236344442433343333338434634343041463242363430324242313332393146463038433837343045423742443936353443363635393639333246453335363130464438303939424444383342443932464139443532373934453446444130304645413132423333423445394346313834343742454138324333333946323444463943324538443833323444373734374430453535354638363530464241324337433830464223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x245b04d6e782b3c4bc033e698dde4ce8fb11db1c3a0300c0807e9e641da755e887eb5d32c21cb3d09a2ed07ff62758a32109e94b8f64da9f9d2d99aea4a6e902	1567387953000000	0	2000000
12	\\x8d92964847bf2fc06f01b1413e31836d7ceab83943035f426d0c7f91e7192cd285b57217df5ca6ddf4e0832c6c576a38bfd178b7f0421ab53d857eed06ef6742	\\x27005f9e0e82fd330bb30520c22009ce6ec1808cf4f6c8fe87557448df33ea46bd7e9e7a799c4a344e9ee0f01325893cd79b9850497c2cf0a7a7f46cb87ac657	\\x287369672d76616c200a2028727361200a2020287320233839353139453132413741313535393631383745364646384437464342343737463335303631304137344233373131463846414242304144423346433337444230384531384131353645343935334233344233443031373844314343373930453731424642433045443532423245454643444645353338354445363845313432303046394139353638304636374137433843384145423132333632353946424342433346413538313738423637423642324537334331434232363845393641433235354636373130334542313831394546443243413846443634413733373832383145383930353242454636313336323741433739324538364537393034463223290a2020290a20290a	\\x4940efa27d68778cd44e60b1ecf818b3a0570633d5dceec0f33d1fb0a828e46e	\\x02aefb7fa5bbab3ecd3994d048d2577502e8bbcec198e6779efe028595a1060506aa0ab239fa4c85e28a0b02923417cf60481427ec6310547dfc0cd8ea078607	1567387953000000	0	11000000
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

SELECT pg_catalog.setval('public.auth_permission_id_seq', 21, true);


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

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 9, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 7, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 25, true);


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

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, false);


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

