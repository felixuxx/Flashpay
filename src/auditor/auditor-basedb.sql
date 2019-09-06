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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: get_chan_id(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_chan_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM channels WHERE pub_key=$1;$_$;


--
-- Name: get_slave_id(bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_slave_id(bytea) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$SELECT id FROM slaves WHERE pub_key=$1;$_$;


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea
);


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
    debit boolean NOT NULL,
    account_no integer NOT NULL,
    amount character varying NOT NULL,
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
    withdraw_done boolean NOT NULL,
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
    loss_frac integer NOT NULL
);


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
    payback_loss_val bigint NOT NULL,
    payback_loss_frac integer NOT NULL
);


--
-- Name: auditor_denominations; Type: TABLE; Schema: public; Owner: -
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
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


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
-- Name: auditor_historic_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_ledger (
    master_pub bytea,
    purpose character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


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
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_payback_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


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
    CONSTRAINT auditor_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


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
    first_name character varying(30) NOT NULL,
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


SET default_with_oids = true;

--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    max_state_message_id bigint,
    state_hash_message_id bigint,
    CONSTRAINT channels_pub_key_check CHECK ((length(pub_key) = 32))
);


--
-- Name: channels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channels_id_seq OWNED BY public.channels.id;


SET default_with_oids = false;

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
    CONSTRAINT denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64)),
    CONSTRAINT denominations_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
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
-- Name: exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    coin_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_sig bytea NOT NULL,
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);


SET default_with_oids = true;

--
-- Name: membership; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membership (
    channel_id bigint NOT NULL,
    slave_id bigint NOT NULL,
    did_join integer NOT NULL,
    announced_at bigint NOT NULL,
    effective_since bigint NOT NULL,
    group_generation bigint NOT NULL
);


SET default_with_oids = false;

--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_contract_terms_row_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_contract_terms_row_id_seq OWNED BY public.merchant_contract_terms.row_id;


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    contract_terms bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_orders_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: merchant_proofs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.merchant_refunds_rtransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.merchant_refunds_rtransaction_id_seq OWNED BY public.merchant_refunds.rtransaction_id;


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    tip_id bytea NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: merchant_tip_reserve_credits; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_priv bytea NOT NULL,
    expiration bigint NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    h_contract_terms bytea NOT NULL,
    coin_pub bytea NOT NULL,
    wtid bytea NOT NULL,
    CONSTRAINT merchant_transfers_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


SET default_with_oids = true;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
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


SET default_with_oids = false;

--
-- Name: payback; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_payback_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_payback_uuid_seq OWNED BY public.payback.payback_uuid;


--
-- Name: payback_refresh; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payback_refresh_payback_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payback_refresh_payback_refresh_uuid_seq OWNED BY public.payback_refresh.payback_refresh_uuid;


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    type text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);


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
    newcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rc bytea NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);


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
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: -
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
    reserve_pub bytea NOT NULL,
    wire_reference bytea NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    sender_account_details text NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
);


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
    reserve_pub bytea NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);


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


SET default_with_oids = true;

--
-- Name: slaves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slaves (
    id integer NOT NULL,
    pub_key bytea NOT NULL,
    CONSTRAINT slaves_pub_key_check CHECK ((length(pub_key) = 32))
);


--
-- Name: slaves_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.slaves_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: slaves_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.slaves_id_seq OWNED BY public.slaves.id;


--
-- Name: state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.state (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value_current bytea,
    value_signed bytea
);


--
-- Name: state_sync; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.state_sync (
    channel_id bigint NOT NULL,
    name text NOT NULL,
    value bytea
);


SET default_with_oids = false;

--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
);


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    last_timestamp bigint NOT NULL
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
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


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
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


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
-- Name: channels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels ALTER COLUMN id SET DEFAULT nextval('public.channels_id_seq'::regclass);


--
-- Name: denomination_revocations denom_revocations_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations ALTER COLUMN denom_revocations_serial_id SET DEFAULT nextval('public.denomination_revocations_denom_revocations_serial_id_seq'::regclass);


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
-- Name: merchant_contract_terms row_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms ALTER COLUMN row_id SET DEFAULT nextval('public.merchant_contract_terms_row_id_seq'::regclass);


--
-- Name: merchant_refunds rtransaction_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds ALTER COLUMN rtransaction_id SET DEFAULT nextval('public.merchant_refunds_rtransaction_id_seq'::regclass);


--
-- Name: payback payback_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback ALTER COLUMN payback_uuid SET DEFAULT nextval('public.payback_payback_uuid_seq'::regclass);


--
-- Name: payback_refresh payback_refresh_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh ALTER COLUMN payback_refresh_uuid SET DEFAULT nextval('public.payback_refresh_payback_refresh_uuid_seq'::regclass);


--
-- Name: prewire prewire_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire ALTER COLUMN prewire_uuid SET DEFAULT nextval('public.prewire_prewire_uuid_seq'::regclass);


--
-- Name: refresh_commitments melt_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments ALTER COLUMN melt_serial_id SET DEFAULT nextval('public.refresh_commitments_melt_serial_id_seq'::regclass);


--
-- Name: refunds refund_serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds ALTER COLUMN refund_serial_id SET DEFAULT nextval('public.refunds_refund_serial_id_seq'::regclass);


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
-- Name: slaves id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slaves ALTER COLUMN id SET DEFAULT nextval('public.slaves_id_seq'::regclass);


--
-- Name: wire_out wireout_uuid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out ALTER COLUMN wireout_uuid SET DEFAULT nextval('public.wire_out_wireout_uuid_seq'::regclass);


--
-- Data for Name: aggregation_tracking; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: -
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
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:10000000.00	Benevolent donation for 'Survey'	2019-09-05 11:50:50.025317+02	f	8	1
2	TESTKUDOS:100.00	Joining bonus	2019-09-05 11:50:57.585041+02	f	9	1
3	TESTKUDOS:10.00	KC771T612V89JC7XQJWW1Y50G5QREFD7NG7MBZC5J36W026BX070	2019-09-05 11:50:57.814091+02	f	2	9
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, withdraw_done, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, payback_loss_val, payback_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denominations (denom_pub_hash, master_pub, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x159024e3330ec693bdec916ef5d9731a7ce8fbf53195d6d3023b09b8d1afe400ace59ae6d5e55a8515a98a07d1bbbd77a6ac83e2f6e9aec4fc6a1b00627585c7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe35608f3b19f877d8c317e58e696fbdd038319ff9a0b759bb5680a3a0d02e8a1f5d084185c610123748335012a510b049ee3e798724b241b24bf62c94a3b7bf3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5acf1a2eec305b566893bb3f110b1efd477162c1168a3a58655c5f300dbe3fbc9e1e6018cac14336d05a8619032266a5c4c00d09978c929e4a3952948714511a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xafea2934e234cda1630518609c9a4856a5da1c09d8c5c5d90c81bd426884485c3980e1d7914567db3c65b6d2a951825b60f53a01d0ae6de506e937603957e8ac	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa2a2f6a1c9d7e7d1af58632dfe9b4fc502ab766b3f4110f034ad657b178fba633495af51ab6254b8f60b9685bfed620dc8a6313bbb5bcfd267d0035360bd269	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa0b85a6bd530772d6d4ab0dd9713d50e3b45b66daa3cf18809f6602612f17d30059488a8a97c4eadb386d0fea0718b15e52c86bfd49abcef6fc017872752a8d5	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1340e49a630031aae77ceb89d1637c5059b3959bd8961e6bbb16116ff8715d47acb59b7b0ee34ce686bd6097acace4224363690c509d4886bdc903e28fdf51b0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef6d35ac88025b5a6dcc0a3583c7e810f326a9de8f1b27627ed902a9b553caf3748983f4de579893fed055d9a7d0700f7fc23aebb5ec4a616e93c2dd6274aaa6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa4de5ca0213c8cd66f6041acab7a310e2246cb6b8f568fef574f6113f80c0f8ad26f697515e0ccc007ee09c17f149a44e1b9fe432f507207c0a2b7c612ab95ab	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb912a9733f00a04cd314685da156a4a22692b3fa386adca9428712b20f9eefe8ff2e6402d8cacbe672369bf11e92644f5a6ba6eded18250f626880ea77b80334	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ed71663181873ba8ac8b50f4f7f0b172276ee0dbde62604b22359726dd1cfbbd87d187cf99c368953d478ae5b52c1313d4630f32cb1cdad041b73d2f47cdfd5	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeccc115024ef074e23a234b81a20ffe2ff47ee91de669b277cafbc8645cc199e6e4abc817bdca3f50f05be375da27bb8d23f160bd6e0190e1fed5cf13aada37b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e36e676b7af34a45bfd3fda0289e6218b7293e2af70fafbf66bee444d27d1c84a38b2d9063ce1541a7b8618f13f20a1d7afcfb81214ac02b8cb645eed158a52	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x498118edf98c34ab0d577d893c891f99660ba49cf783cb1ebde64f93368f9bf3e3ef8f4cc309ebaf821939cd116f1afeb7a041df0d3ff748dc49cd75b719dbae	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x648708a2b906497c563e73e0b2694753bce6bfb66980930a165a4aa0ba94b3398ed5e18497c471be51751d24d538d5534a5980be28bc7a3e7f6a691f6590b6db	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfcc06eaff8e95b7d776e9a18b41bf7d517a4ebed9cc86673f0493d71c73d21d641034b6896215ae644d51d637dd6e251a12aed934bb5996a48c7d8d7fbcb9fd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9782416adedb3c461152a91107f404993dd46224ca96ebe9d7048d770378e6d2224d557f36da5a7a82a603f38d9f861dbacd50680e89ac8dae8d4173928306d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d6fc0387a111e1b93b14df80a98366adcac83e7d654c362e4816270f655e792a2ee99277cb272cdbf05f35af874a191990ac50f822af6e2d82497e3d7b1113d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb04f118d333cc7d94593069e32b77e236b6e6de7ac1fc6e7398d94a105b56423ce38934eeaad5477720defba1d0867cf0214d7265c54ab6d4c3400c66ddc7991	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8030bfddc158bb91cbce2276ae79d90a23c35cf95fa06438a89b8a1f726e74f8ec50ddd04cb68b4729ba9b34fa6d4cd6ddde8544c87771103d4a58a68f5d4635	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x124b7324e0479c83e54c23bb2690a073d6a31677c1b819c64c014a640cb051d5db28616aa554d24ec924689d7c2d0f9f1cbaba874d4359c27bd4e1626af01857	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb767f0735fc72a13361a701294af8a25a2373fc5c722cbf8bc7682e8a0f14da4b80e74e06ffaef1968a3d11042115655f402329bb36b91f7c9d7af5237b39a3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x54f4f4ca8c663edb116a4f810f85e96872984d7a47166571c20914820350bc0a3e30e0993343395446b69bbb2ee443bda2cd54e60d35b750870fb60ce6f0c2c8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf0b1bf08e758be8661b6576ad3b2ebdd8c40be2601fb44f62ed453ac6f8cbdc319f8bd9323108b46893523934296aca1069291f79371cfde5efc6a9a3eaec03f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaed993b7ddbb0a7879448e759a4d4c74dd133daec14a95545c37f1527dfbf6e2335bb7ae22d1bc79e939c7c3a5995c82f1ec2d5fd9352b200e77e3e20b7e4ef6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x74c512569fcb35cf0bfa43453069525454648b2a24c9605768aca68c75d17fecc9307f2692b13396d522fb9c213509c3a5e1617c0ae38e29a2fea0be6e00ac76	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53f9c3fef5eae421039d3d2acf452e982acc0b674f139260ff707b706ad9ddf27e59f02438385e9e6f5dc784be8699ad7ec4dce3e9185d87e0ea0109671c9445	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x982a2c9d4209797ccc5cd9914813dff9f1f0c291f775994b6481ff6e198620afa3835d8515f3b43ba0f37a5c8b7c8a4cfc1370377611cde45e9f693ad8d19cf2	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7408ed7bcc433173fe59f4af28d927108ca40b7add9e7b6874499a208105be863b45199633ee1b6f7030ccae691367fe69911288e78df9c4d941dd1efba8a695	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2f29ebd10dd19abde83c8bad5ab408bce5eb0ff92f2182e84e158d551547e0bd8ec497bc64e349685f5c9bdd46dbecf773974a4b0cf94d74c766f0a238741d07	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd611bfc06f303b1813d71eea1e3ecfc1c3114b99b2cd95f28a27e8acc028b3970a05b0dbb65ccffbf02992353ae9e70182b43848d5a4087afb364faf861890eb	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x879b25e3aa86247913fff0876156bf4fcffc336dbb109e6711752e203568f32943ba84adfd5471862aa98fb51df08da10aa184e77937dc6f81450b58601eac7d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x341e1e7fc12f3ffd82722c82cd6e98e72de961a3b32d20e8bc883875be079a57e7a920ce3c2de46b2ce6e34e021f7d09f8a12e4956a186009770a4ba438c12e3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef77d29ab4dfebefe7169cb4e5a0834288ce5d50f221e422c0667cdd27b372f4a486566f2d46ff8a8d238744106a2426c000c816030d8379c697f1ec2055c26e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a59395500b5facedbb0b30769d3d9004d63d02b0b5cb17358a27eb45d3f2547d5e1be33851407b864f2e011921c524e765041e0ac05d566daffeb6e17b13d46	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd760c77b8f3e5cdbd9d744610c91bc1f1f0939d67e1ce6255bd485d761004a1a517beb0611df87cce428455aa20f623f4cad107ba162edd3dc98f32e0ddce457	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xed54c128f49e3ecf42043272f298a790d942e948ede5a78c12141977895aa2ef8630db5d8f2b5a2e87b5a34c22705ec321cb018bb2f51fa7e766ff15fb20b834	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x568b432c7205460aef3f01505c130c89604fd1425d9f887c4987ae1414152d443ac4bec3d5e720c9536b550931a251d84bf34a027b6a66f642373b4ba51c6285	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xed1e105742a69887d2cbb83061c0fcff8ff919f254892d274ae819e5755699d0ab2b14fc06fc0b94e6f2f6e0e8b409d4aaab0ffe4140d8b0faab369120b9d7e3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x69bf3c423c8a367867dcf947e11c520a4404efdb77e6e567f39f74b78420d7e9ef1a0047b23f448cc00cc1b945d3ffc23c697b4c4754b9a54fd233aa57dcc5af	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x94ad158004d72e2d1bed125f6a81cb341b29a2596b4554bb6becdf0b8ae821398bad121a99c6403c379fb11b3d52b09fef313a83b00d9a8eae9e2fb04e34b64e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe4092e7d962c92e11673c34f40e23e6580f19502232f556b2a9d4921d299fbd9b0e02e73a56db963f7f71a85731c5e2b86d1749d6e064343ed60cbe2daf62457	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc0d45decc77a3fb150f4bed714f5716dbd8990fcefd89bf16ecfe6d7674177d10d5301b1367b2c5af1dd89a1944d46ff5c074cf82caa3e00561c1fbf0c888d18	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7061f5ce4aed46f716a5ea855ae0e1473ececb70e8d922d6fc361f50cad3a12f3a6bda1e5714d598bf64030e8687b75b4fc7bf3482af741090f48e707014d66d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x52f7063ade47b5ca33e966bec0362645dc905428f3b8ed99ca39f0ebef58848fb7b9a134ae4aab9ba288080b3e868ccdb8e48fd9d37b19395ed97d17799fb35b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc165274aa4daed654abf6ac72af678f95cbe4cf996df3b96424d6ef71d84fb15eb46732a1256da619f6f13f7154acd06fe62ee4490ab817f91ec2f37dc6595a8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5150982592cf080ba80380fd55e4976fcfaca57e00cc47893695142fc8cdbc8cdddc67100d81bdc4a8d5d3b8244a4c8aa07508e6551e32483c9a622297fd3b2c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x81638fb49b33241180becce1620227a4fb77bff7444b51db32a26c737ad31beacf65b4cd0e1ccbb57af2be7910bab536ffc1673a8995c0fb660d0a5c1a8c7e24	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x13447b1fab248630fe7a8163b97a40be7bd95de4fcf3d0b6f1c137578f5c65537fc5798ea82b8e88bf677bdabd6b9e546e3a096f052820e4fb49594816680217	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x71af3770cb63595a5904a44a2ee8254818c6cc9fd3bf39580d2689db34694e914f19873107dbca385905702e66e0e1f466b969ae9eaf66da98026bf2360759d4	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff0591032001182b1029383bcaabee8e50c5f590d050dffb1dce798a2bc9cde60cfaf66bc45c873a7efc9d54fbe1ab4e793c4419c3801ef9bd249540b57b7222	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6113f1d8bc6de4882d93bf8d79f3b168b46738c97c593ef0d524c3e6db441310841ab12afbdfaf88124cad83fe9e9ae8b9774ea208841778709b01b8656e88ae	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x09cb24ab338e3a01ead5c174537c572e929cdeeab4c8966aaa4f01fc4142850c4024d5a57fdddc7e3588152532f0c9fe9a4afc8dd7eddfdbba0bb1a3268bb1b8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x268c418697c56e91445aafe6f04fcaa0089c3123186bc790c335dc8edc7cfe07a4f0c8917d348687e85ef7b5f4214a4b5b1adc25614a2eafd0882cb7058ec142	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x49ae9b12dc3cab6271c8f5301a9d73861734f566b8a2cf0e70857831fd0d3fffe68ac41cf3961c811c7a7c0511a8df5b6ec1a3a539cc8765f6c355be67ac6fc7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb7b7df9222affecc86123650792187581fa96f4e2728fc783104fbed5d5772241bb18329ff22c05a371d7aeae3004b7ccc69e8c59d82558a44c55ab958649283	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf31aebd2e6d6b3ff4be06912fb08742bf4328b143d888ed5aa319f9695fef98f43927aa2b8a6b45ffee2714359259b63a685b013b48c8a7b79ceff8c5c2572d8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x96166e722d054efb3638544ddf8b3e2384f486e21bd47a143ba128c91b96f90efad16dcb1cc6cc33cfb4b6452dd00b03865b5a7dc63e77feeb5b79179c09d01d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5a9a7b92265ec001101c26b2e037fd3663b17402c6b61da800dc8e5cd19d557e39a9181105ad8f02445910966274c47e5c401560a155ed238b52b000653ee671	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x19bfd811f7d5fec3d8c212f90106b5fe6caa3ac2add9650ac896828d3fe64d60658b947c946fb8dbcf3fad90588edb0dad849b478652560f4d2adf4e0d9acb18	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeaadf15e6d90cce360ed02c97e2dcfde0d9451838d68dd82231e367a2966d2f0bdf254131945222b410a6b78a1267393a73ae7718ca5d8387f88bc0a0013e512	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd13d8e5c88360f73c17233ae44083fb67fcebf2a09c4b1d02a6c4154acf0556b8247022980a41367f104d67fed350ca0abe6ed755a5ba465df55ad5ee1116a2a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd8cbfd93d4e95d4473d7e4163930ae1752f6663453896c89d338e9a16cd91e6a5c427c971687d3917202f6d4656c35f44b34053496737ca4033f0ddb67490115	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7a5fd5a3f15bd63e2831838ff2e53651cabd315edb21e870e5d6919a79c94d7a4de6418b457ee28c4b7824d9396b9755ff510e6b11fc80d66953fbeaa8521810	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x318b744b6704eb46392ab924b0ef73d77ae077f03fdb91bc384618a21248b564caf03a45762fc70a9474b0f26f93b7f3e6f0f33a6d9e0d5f6482e90dcc2426fa	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xea4c1a2173507d3a3d752c809ef959813d4a0aa6aa17dad48c2a590e8e90a384d66fd3d6ad1eebcc0914a6c63d9d38c50d3f00c72d10e0ab7eb7e9d4b7b72c02	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xbc1f751bbac69b949e6b9b53e4330fc399bd067241a9dfc43a9aec7be594c82c272e10402cc336ab7a99cb73baa0a60c2a7678a78c0ca27d0039690d51ae31d5	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18233edcb65ce36791ffef858e77df1a8ed3cfa1dba571a789ad49c6b3b0cf88ae02d3ef7d07adff1a0e76667dad1f80bf8110974ed71df7bca7ad4e0f00103b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x54d8d10a2b729faafb576323ac813f0300933a0c06ddb1350d68347df5fd66b3f109f5bef776caec15eca9eed9a3a10dfa998ef676d72d47d1194d02021583dc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x055e6d97a972932cd958532d4b5a60bf4e298fb0b082464dde215c5bc6cb8908d2d22bb05ce6f3dc3527f8758a7b59afd18d9f9f11acaed95170579690897dc2	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x659d2dc9183b4fcfc09c2dc922c14c42045bfda88f1f2442588fe6286a9c5582e17234688d6dd75f42579ef5ed3e84a83cd3583804da3663130ac26d25ff2a10	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x611e4177a8a5876f4921ffecbd27b3a2625233f4823c643a81ff1cd5c647e8c811be9c3bdee727984826b2b727394d48e591f71df9246d5ed11bf9eab1bd60da	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5243ee45c469ce81e4846ef5b17078d9886c4c8eb29d283f463933b1767dca4dc3f4322d3d3db95ebe8a0f7a37572882bcefc611cbdfa979d298952371b0c551	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x132830e178b09c475e12303e1bad14af1c27e3be1b9fa0b6d971f89218257555ac43c512a38dbbf2bfc124083973e974d3450f9e544da5d8327aa758b4d402a8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa51b3389c6582376b3068f27610752e8505649b4e54db427b272b69fa819caff5b4f42a4afb36a0ad240040d506757b373f4bc8175a5ba3c60a66c40412f423	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1f88c678166ccbe6f6d6b8dc59b332f79b42088c373ed285bf3f0c7a30c055b96bd5ec57ad456839f1568f16677d161f89477cb214586b7e6c4c8ff39e7af987	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf4dbde836fa1b4d5d0831b4c9c62e6e1104e3035a4be0b6e3248101637a209c5200313d12b129f71b3131848169e1795df536d054be347651eea7943fec94338	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x524625c8a915a538b82534e44e8684beb7a7129d84ac1ddaf38f27604258e08c825212e18e22f5186d81d4a926b4b74866d203ad1b6fe6a0c9b467b562052e3f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8cbc53eed0171b24c5b717db1a6b47b67f7c9e7878545b43d3983e05bafba8e67b47475e6f8322f166041884cfebc65036e2f8b91d9a00c67c2809f1fef89383	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x24aa32d74b43b4dfc410cc19e3fb4e98489b9583c51d0b718c0e56c0840f179c40566592f626d1c55fdc8f147ccdb9332a19cd876daddd54e2abcdae0a2584f3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb7a62af538598ce02805e1a683b627850c7dcf8f5dc1a4123f856d5bcd84aea53f05c3358d5f58c934d42112f8b334917ea4435b000c7809740bee42ffcbb4cc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fac239f1b201d21b5b8e291315f72c71fe943dd8ac4f90057c348ba0ef44fb3005393eace8c1d0e5e76f7cb8bf10ec5ff06b6465dbfa3316d91a908f19d0263	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5ddcb0eb21b3a9f68e209251410bd843763c0ad76e1ea9520314c9f5f840939c3df4ae1b5fdeff71208efe9616d996a98c94dc1820489f11794e6caf8c991fd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x368ea2cf3fd4fbdf4d7a180f1985defa752c0742cac650e049e71d2c23e744a269328d26c96fe676ebace568a781b446b7254b9c132744d62f48e3863be2c837	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ccdee431fb052b88f0f40eb4536720ebcc76bcecb4a6b1de206780a749c7bc038f4e0484c988a2c189d0e92dac4d087869dea0556dff9ece25f3e3b42e31297	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x19959f2c3bdea8d44e84613c8ae976613f1545dd98f82ee7b0f245586714a3ca8e806c2dcfa02b88541a0cede05dd03df7f7eb80a3ad4adfd8bf7cc7bdc0a703	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a0dd7eb81367f8046c105b6e0b9760b0a6e4b5c20f6e933ead3a488e1afb559d1c7cf671cfc5f52951966fda68510fdbb4109c94d96e63bd0622a4c8c1f01f0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x35066273ec14fe671395333666f834e80deb2cd0aa9cafb310ce6794081f9b17a98fd18ac5c68d8983c77a3abc0fa9eaf48673e533fb2d2d0b2a69101afc8c63	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x57389bc7e1f820e497ef45c2783d9533a9ec728e4911be8f14f325c21c0964e97296f6a390f0d8924cb35c7364ad6a12107acccd02d8f416a70b63aaa54de192	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa1d2f4211eaa577cfdade8cad5493d0ae25a52cc62ec1d21fd643095954d5651e3700434cfaca534f8804ca94e6a84c0145c6049c7ff2c226630e6d063192147	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc92242e02cda1dcacbcd7c28f35f1c5bd19ee72922bba2d263d2a53e0032a78b8fe9f00b420f2d8c7eae7dc6dbc3e6ff8232c2847c0831b1168397ea9ed12af1	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ba627c5e0e5054388ae804438d14a4f990a6d5a19deed9f4203f5cb9bb119692e3a7fc0baa5030b5b97aaa28d5c914c22872a474e2d05587c4b3af173cc1ac8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b43883a5ccb2e481f649b95a76e598fe1f7700d484d979c0266da945f691e83eb8003f76187be70a1b9e72d10f586c73b12b2a16dd232e06916aede92612d66	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3b09946605f4fcd67129df3f495dc28f2fb2853346897369d151f69dddccc9ef037ab7cc4fa5c017af402ee9a7cf4c45dd198a71b8e1ec37caeddb27d19742e1	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdf6523bb636ceb6e28e6d6ebd8afe3979e7befc24c1bf3d3bb04aca83074e2994e7a110a1dae726c41127254c507f7fc2933f2c7deab1c299d36a3244a91a382	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9c6807a369e036f5b79a58c04d25e86c6f3d9d45c5db7cea9c4aab07be30825c363fc86ebc8dc314839b94526c5862dc23183f17747abf94a4c30203599d34d7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb3324bd625be2b0fe2ffcde137d0a3173f00439455c1af6550cdcfa4b91235edd4d477cc23602d31bca28b4f25a5ab0ccfd6a8da81a22ff4e631e142153db7fe	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90a11eb0845f83f3d1dc9877fa21b64ebe1c52ab5fee9a5dba09dc5b343a25980a415c21c215669dc5bd9d5813f639a2a70f65539db7162c30bcb55684899746	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e31c6f2f61e214d0ffbc082fadc2fbae55961a8697b8d258431d797ce3770dd78d74893e0142ec1d3640cbf9f16e1401464b4506f5f400238ebb2a40fe7a463	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a1c7f90cf5f6e294ed83b176d767625da64db9987285074785fe918d924e0aca97b63c5447c366d05f3f53bdc11078acc399e43879a21d9778959702f603cf6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x425ca1d79fea1eb6e689ccb2193419278bcb4794dd3e05ca72856eda4b1e838888831761cfad3ed5a067fb9d7a92faeaea433406abda7c3de7bddced05af2dd4	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe887ec22b3f9f8eaf9d61f97fb0224e9a7b3f2259720bd13d6b3cf96c7562ec1b46bd6a8524d31ca61060ff100ad83ceaa4858c2a8129a8d0882e98b8d57861d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcbb943dc336a99c30708393c917e32b7a20d0586a5b1a083415ae32d3cc8fbd686fcc1e13cff4694de462cc3441b19e13f080abac9204a139a3bdc1dd6be587f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x545e3f0dd5c4808c90e5e86b50f4d9f6d6908ce487ab36eaf2faef0cd6d1c942d0a06c5e3ef4241ded1a2d0e32e59fa6e81893508a186253689443023eacdb0b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x57198d4adddaa30de2094bbe08b6194e9f0cd64ddc6a9f497987c5ad2229acf2bbada339ff0c88ed1bd1127022a4e99e261c4d599da00ea3b2e8c945545defad	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe09fb112f9df35371630c64579d1ffff5d7c0dd1462d5dc7205f92a328cf299c98251d009eb6860fec8ad8baaa8a3648cbbafa053094e97002252a786ce903a8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfb34f0133787fac0fbc6a025fe2f9433a5cbef980ba48228e0b91f8e628b3fc490c30967ac6304ff4653dab7813abcda717aa0358260b57e1996977ed3f901fd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa28a64e80959704fb45464b1d94ae89d3addd685f480407e82df99cefb1786ed5c2a261c7d24e2c6cf070bffd2e31c56b3e42c8efa4f4b1cc2ecacc282b39f7a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x410d494a7104e14994c606d1cd90cc35f72926689611ec8dd7cee8e6d9cebd573e5339af9fadb66e9b9342fc210d312cbeaf43ae1597523998f4056528efb2c7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5802d6268ade23d1619d1da21fafd7498a643d773cab7e09cedd2516948044c56d98be01778d272a19e4dab9f97d328f7d2ba3e3211e346c753bb364c6c453cd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8bf70a16c92296475b36baa592a05122e186b37ec1c1adbf299887a18b8391f0ece3550a26030e99abbd6c5b9d985382b61bd4e07a30db201b5a322e164a9f22	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x96ea1a58dc184ce01aff6275c3f055f1039a79eadeba518adaf73d139006de6efd433afb18235760e5fcb03a86fde9b23f51fbd4a30e6aa0305107c2a1747427	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab9c2805753dbc9d4d1fc7eb7b9aeee0d8b8a200caeded57d468528443bff1e2e67bc39a1ebcff87181c839254bd72744cba950361438900b4e7b92e4a6b4047	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd25fb061c6c0e7c7feaee6907624460a5ff6900772a94d8a25db983b15a79d99d079d972cc5c792a6d41704617ccd4f2c1128bf7736e5e68083aba922bec9f03	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3cc81751a9156487f064a9e912db87d5e9785b80b7b60213b8862af6068fb992d0a54fd84ef0cb6b58abc6bdb1463d467fe502d0dad10be20ec5672d9d7b2dd6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x811842a80cb826ba9d0d64af1e8d4254fb9d58473c4adc6af1bd45f8a0d6ae79f4e39c6e6a6ff2f41815951b5da6155068228cd77ff5a93b5c7e067a41cc04ed	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81fd0b4ba4170662797578646526c64432e6a0c84505a4db012de980a5dc8d75645fe811016733efb8ca7ef4f8bd526c940955fd73ccbca487076a241675c951	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x40812a651b6e9817d4cf4421817a2cb1b2c43276488a8651d55eaf9b021e44372e0643e266530e54e13966cf11516d7e3c52e8d4bf389c591eb4cf567487dd48	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf427cd112e288f5033b7776e2ffde3d47a9d5b89cce5e3a02d6aa499d847e07563a00593f273572379e5ee1c20652e414b1322e8f859e0bd249148c3035dfa12	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xad5379b460c3277a2c08e5a57dbed8340613a87c76d725521ef0688c2fe88c8f82e9ac5564f1a7514ed1dfc458f2d0559168d57e5da1d58b8362c609bffaf36d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdefc94a2923775316513cba0fd3c16a54d58c52272b244c40b9c113aeb140187a951e4319b10adf43c911e52d6f39bebe26c695392ca313a5e2166bb00970efc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3d105cfafae6b01c040ec565131f4fc17b6bc4ffb106baf511bafec6430ac93e902309d014c587982706aa7988ae65032ad51e1c663524d59853346769d1290	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb3a6d038e8fb8828120621b76db0e3a8f62eaf6abc8f50049ae0e9fcf4970ea547857143c9685a42662741f4f96f50045e4dfa7952c8d8e2b9e552b42d0a3ee7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc7c5fca49cbb62bd2d768d8a1aef426a72cde4a9a26a4d0cbaafe1838622560c9421ced0cfb8a03bc8847dcf58a9a3258a501b5e41dee2936fe8f124f1306cd8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x92d63772d3a5fd8284567dcd327536ae5fb974256f8569b665be13f04e2f7d95f5a8400736f3eccf18dbd61de5bd3558daabdef498f184e913539570eb47ac2a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b66048e7fae8075a1b1b49f0737280b0d1e97862fe0f6f414a292d7daa8b4d5619824243eb6bfbd00dd67401a81fbea1675ac2820bf40ff693cdb51450bae4b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x749ffd9105ad6ae2dc4fa629d9ed06918e60d132bccd1f2cd2b7e0e5bde26e8946e7f158ad6b5e5a090d64328a074fec0a5853ae0bd0935d899b89cf329804e5	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x13bb86a4e52da5cd47ec0112f781e4b9ac068e59774154db8dbed657671424d936794bca123facd3f82649bed812e87e5d88d28653ee216997cf9c689c2746a0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf642b8c791a710448aebab4987af440c205076422c1550506e4ccae35b6e5bcbeb82129d974416a0d13eb28ba8fbe2b67db4564c10a349c01002a0781ac4396d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x37803d5f5820fce12517d33a98a88f36e38ec5a5eb5b648a3c1f82a9abec46aedbc8fb5cc3316d83c07dd689b2e440a0f8ff537a71e07bfe4b0898bdaa3369c8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2f79689c9a131e68d2e9c2121804a73a0eee9ec5e1a2efd47789b36b695fcffe968328a3ea8dd2477592df51fda856d3c331e63d3288feb1bdcf21e0df4cf199	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3af2de8c3e96548e0a7ff4a6ecacde54d7ca68015fbc16eb02f709dca94045051a5ee46c04fa8c3be30a306e5240e501466304b215e238e8809f836689ec37e8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd35716af21c5edd882cfc39b16e079f4192741fff1a052152451442d33fc167ed09cebdc561a608cbeca1c3b26b28a61798493772c9d4bb9b269005137141eea	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b946ac707780d8c4a6f5d4bcf1b77ca6dd50ae83ca32cdcf313c8772e5332c2776b1590e64d87693f65a8ae084b7c5eb578a5031c0de2c9a5c056cf9fa60e39	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x348eb1d0eb10c4b118e74cdc8fd967389d154d1401cb39683b51a06d4cc5168545022f3db973e289e45157cc567024d8af31633aa7c484e1a5bc7b320ae6d68d	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4649a9269cfcba9746f68a0025158f7f1eea3005666396bc0d1689b9f57dbe1575dec74ca9ed6657dd01dc3a33b06919ea3e3e09a757fc697a9f8ff79828d72c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c134e93d8a103db06f653759fee610132c24feb7d8b4c88e930fdec9c0fbce3f32fd16624e137ad7039e8c7d212fe874c3e92f8b56a70c228a6bc5ffc1a0e50	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x48696827d0dfaf6fdb8d4e25b1f4a1d79b5afb61b4d4859d373019953ea3f97491c2773e599728695d57b7f82b6eeca3994c601c9e8d04cb5dca65a4bfa34799	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5675bb0063cc3e3d7420fc69a3a40139734a180ddbbba9877c55257e34b2bb19f1e6fa9fe19bdffe42ba8a1ec4ceb5714e5a0553b8a49a365ea9644d77deeee8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43b15ecc260dd248cfe0bd85611b11492e98b17212acbf80330366651cf597cc93fc5769d7a8dc67bd673c274d94a973556ad83b1320a2265257bab9f1a338c9	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2241bd3496dca6a4d0e387324c88a5ab87385a81d831d3f76828a355e1681b7cfc2296d61e39da13026e5f7a6502f1273c35dea607e7514065791997b7b98b16	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x769f358dc08a454c28cdc889684c9224380ee6f32385b0fd481ec5eb56696ff1ec43600b349576024d5944956b00c589f675a32aba4875ae7c23ddac65aad4fd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5171ca9fb3dda4ea901240dbb43cbd92d34d7904b22d05d7c984ec42256a2a1dc1de7e03130a65770a0fd796ac24ab328447de5224fcd9ae162b74ce9b7d1e3a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xab95475678deeab35f370d34e79604b40d1254839e7607ced4191312f4ac02f5ecd5fd99ea675cb471700e923afcc9ce47e3bdeab5dc80db738efb99183af10e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1db525a091c7746fe38c15a549e94afca2a58d708c5d7af3d8952931388c5bc966a8f43f855c458bff15fbd20037887411c33d1261b6a95a1f2b0745eb80a8a8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x94f1a1b0a0f68d95b6f121fb9452d2bd8cea425d6bebdf900d865645b6cb16da39ca2b443f1814bc79af906abb13bd1d85866c850acc50b104e1949afa31ce56	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c7d4b7281e2b4fdba2f3c60ca607a66206ece85828c641dbe743eb6155f45cb0e4c8e8811fd4ba05c68a9c7d7715995a8d85bf9954e7caebc0541630561f8db	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6e40680d7423b9dd3fa0839f7deb2890b3b81d4c9aa58b9b3e328a852cdcc3f6d311cdce6cbb85081ef12eae6c3bc6927e71396ca49e7739564b58f2e94e4697	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x07609f7760ac327ab4ec2961642345bbfaaea785aad8980486a2f507a81fa914f7fdb8df4ff5df35582392e7db621ebbe60ae112e023fc47982856d678cd2b3a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8e3d6b099f1a9003912bff779a9c115907676b8ac727eb398c11badf70cc974c396847e24a58d9247854b7febf4091d493cbde63976a38c997820adccf92a532	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x93f54a96d74107c77749469d8f0341808c2dc87b8eb28089a84928f0fa43538895081be700391b6fe0849bfc9183f5c9c5035386e577d606407fa358f6e7382e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xaa319385eea0a32eef7de7b5f02040ae4cb724fa1546bc70c60aa1786a98752e242d626ccf7f290df0c70d44ea82a47756572faee10ab644ad300f3d73839cd0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9732f2cd2dd499ea8581ec8675aed718cba7d221400e2391fd1b711c65b332048646544940934e4e6ae0c568abce879368c4ecfeb79c69b9d504aa1801a1bacc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x493aef710d41b520153052a640e05aa65815f59e8d586b8f03dfae9c05d4cfbb043263f7a91848db770c0689cbf9d7b152a0921e08831c96c04c40ca622ed873	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x88d6312c5a7ced49cbc7dc002780063e255b935861de3bcca3709a8a787eaf70c5a9ff048052acf9acc7566ea3e3251170f556316c74210bb2588483ebcf3a61	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8772356bade5647772a5c50551e151817ffe70e505bb96a076361d0b9c48d53c8e8c862cba11779db3c7d4c178a3c83532428ddd08262c397b02cc5798b30e07	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2779ba0e691a7deaecd465f5d0cd6fdd7f111785a7bb5c0adeb5179d9c07d47d3827aa2df9a5c06c9323f54c164c4c60cca82fec22afd3a52cbbda8037daaeb0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x58340a052052bf9f7cbc51dee27b83e9f2fc93428cc1572d5a4c2dc81c9cb0e78a4e659411a098bf5acb3e1bc1fe557ae1f83a229b4923e1ed03caae66909ddb	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9dcb9df53dfb4d443dfb8d9fd236f99cce1202704ac3f357f6c8960222b66b30a0a216426e80f1f37a6024e7f970ae3e1ecfdc4ed43da11d28d1c3445cb253f9	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4fc58e3c5d420a6673a9f03698538247ff8e9e7aef0a79f005f96667bb46204d1565195349cefe6bd82f8b9f417764f294fb5e229abfc0723d32d04cda6f2239	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa840ab2db71709482fa1c008bbcc5f78aec1a403e8c676e5665f96aaf729d9e10915e68206dbcc390e9c80ca4c1c81ed39577fe4478c1beb65eae51b2f870265	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9adfe13ecd324405356159815ed3bba14cacf9d5ad2b654b490026a0a807d10f460f96df1fa12151c69431df1181f1175b8a122a24ee83bd677cdced14164dca	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf617acc4dc16a9a45dc23280e03394ce8e32128789d70ed32fa681c1c30fcf9557c087a69f1ea708dc35d5494c8367b9ce74a6fa1a072a3c6c5c7b7c2eeb49d8	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x362f79b9005cbc13f30163b433ec906656326bcea19dc8af4c92b7d9573a9380dc5e3f7199610babdf7674e481c11d1751a725c4e4d6a8c1833fe129187fefba	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x548d6c72500a4589ea3522f66eed4a43b14f0856b088a1dc49fa31dcba51847d2183a45bb6ee908cc950a7f388e5f5e6352e3eef18a3f2376a20f203fc24071b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe79b866e1793c50f1af8d0178701cc0b92fb636d0ae2c5ed7206b9263aa6d439841b3485e9dda3c510a8ba0b191389949a105544c8159e5ee555ffb5280ee76b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcb089acd9c5d03f6c82ff5840219250fd77ecc86b3d49f514145937f9c814bcfa324582a91561b9316d258c4ac51f77f5152e33054ae4a5d2bb1c6291989178e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x329bdc07e51327728cedda832872ad13a27cdcbf3f3e83c27ec7a77236c29f7e5c154db971f78f918da5aeb631aadf1b199774e5e0603492c24476d5e8ac584e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5c81a7ea4ad5574691892656f5286580f8d082ba15a7936e858358bc7a0052236a6cf46cbba26c38f11e5843c539a9a17253f8317a1f5d6e03e2c3112e0d8c32	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x800135305eb98d9247f7385dc4465f1b01c7d706d6e2a80d9e84332926fb003b9f04440a68acdc80bf999c71a63ba4d4ba9efe886b39637c1939cb1d901ec9dc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x173aefb342ebe3776c6b6b5c3adb996bfdddea3c72931ca4625661a873413e4e9e694fa5454399601068fd6582590078a8f38bd951e07d45fbcdd35e26afd90f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x109314f3c4e576327b0e987527f8f194f04674520a04db31b1d6a65abcf90804b5d030686a0e05e160f4f06851988563eab9503f2ed325bbcc82eb460d4ad5d5	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x71898d955a9e627685fe39bdfe3da985bba7321abf4a4fc83154f251054ad9cb30a3fd88f36853609b5fe4bace2bd49d15d8f473fcce15a1ed57e45cfc177e5a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xfe17efddfe92176bcf0a28e50f8e08533ec7d132c3d278d462dbedbb29ab562f77c59030392c951b21bee44fb97fb1b7a5c8aedf316fba6808cca3b63716aed7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x105fe0e30595977ceeaa1069ebaaaea0699c75ca6031ab78195dd2e1f5ac776aa75f3aa91fd02527e1549ca8bf63a1a7268f599d16567d8aad4682f086e4811a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1df052a3a57b2a13a611ecd05222784d69da5f5e1884f441eeaa5267bfab9719480b6d22dc6140ecd9dd8c03585761a07e45f6a80290660afe682e5e41471831	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x67032b0276006acd7bc46d47098b18ac700070e741bd1b5af1ae65a60499413296eadc008b357b4491f84b2becce718d0eae2ce0ae8492f259657f019b48b1d6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb95817d24e7b9dc9f4b5e33d37556472421ebd21de2afdf8829f35b793a23fa5c536dad98f43c95ea4a80d86bb2c831c729c5bc210a155497e50f9ae56795aa3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x83fd6bc361f8e2928d124055c928fc52599c277ebd051d7003c310aa5278e895f74d443003497a8e4c0ddeaa9a155823a3eee824c604574c598a962e7b2df722	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xac1bb4be420846889db245bfdc2f55061f8b0797b3eaa8179194127604f4ddef13ae962f35d56883d9690892e173cb19be8fe51976b039c4e16c95fc94f08a91	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc07de3e827c51bc72f85a40290f3339944017d132d4b6940e200fd8797f75992c234bc72815b04152a459cf864ae5309f4bcc2d0bc5a1473a4d15ab88ca3af99	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1887da687a7dbd96846e2887ec2014454e72f621e0506e7d53032cdf0ec8005d675957b9cbec91728c8fa967154202d9b2f17c4ecb1f56299093e84bd14893ed	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2e7f54f96e8a3182a380659d7459db3b78a4bd8183d18aaad8b28283d1c40fba979ca562dc591ded7aefc9b30365cecea5b234ab260c801ae4348fe364477038	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf6b0726ef5acc46bebfae393aa7b73985d3850a2d03e00a3abbd85e3308b8403428d8c96b23bf45e14789e86d19995c9c8b6317cf936b7bde5fbc7aef1d45671	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd1b537540558a52ae6a8b76c86214f7d0e8f27b3f468205626d303080bb4b4a50091e22ff7fec409b38b1346d3a64033132e56d953684873f15b0ea04981af94	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x126077e7f2ac8f16263c56082cd9b0abdd5b811d908afe65b826981b41afe56d14ae6d65de38ee8accfb97503dac76ed811291b7f13e18419f80a4411d262998	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xda7397bf9ae76a1b19161aa60958b06486daff3a349e53b8eee1894c1bc1980a8d0eefbd8c5665e2e0a62ef03c9137d74760a101df1a49659510b83e33c812fd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x000015992e7dd5b89889accf422457973b14b12f821e75b698636e275fb94dfde8fb54139218fe56f7e830cc2b48bedaed92f9c1290927ef14d0bfd2efb3e934	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd8ad1de3cc7a921ad6a4f357d2526f463516a6edaac7f06e73700f60acb13fe7b23a6bae4541c9672bb6e2ef7e3c0a4a2adad732fad128684da00c4f6e7c3cd6	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x342b4724c7af524e9dc3fc23f6c4803ee4ca205c894b82e3d0a745ef24a8964e285523d5d771d54f9d835c90ea269168bafeb87a22365d2ee3d92e34636de7e2	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0a67dc3b91a4ae32eeed06200dec80de1903e00fe5f66083a72b3d9f63d63a58fc14cd1a2edf098200918397e8deb54348d8dc58969001c90f725d358fc0f486	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x91f6e81e13d38df502d73d7a8a5c8bb11b27c9db7707695945897c7e9d3afb691073767b862732f7a030a5beba2d86ecdfefdfb142305bbb96b0277002c47114	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x66a0174c3582eab2095454de72cb7717d1772a5e0461f5c0788d694bc7e1271e4335cd7b4f3dbf9c98031af97e9bf61e36dade169d2626df143f7d3a83e89bd0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7e063f3b3c1746c27c5b9c12395f9cd7f3d833c1c4a06a32fb9950645da53c31eeaf181f8154fb2d2049a1ece46199fc435fd628dff97580d308f2a428c84bc1	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7f396957848b0da6b9353fce04d01e21353c7f08178c938f6ebcb7105cb91eadd09c14a2ae18839a328520f49dc2f21f656b5b43cf2869c22909fa33998f4951	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e285ab8e0140ad26e4c8667989efdd280ef7575e223792f1042ab586c4f422bf6f0b355ca434a6e7f6ced84d90f0f12f325608ceb5854dbf2b5f3046cf8ffce	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa2d7adc4924fe1b08acc86da40d0b67b59d51cd67335dc194bd541cf5c4235f17acdb1065170d969990c2061751a9519e8a4036f2480c20af1d56b103d74fa53	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x79abc451368dcf728c5e64873aa0dabc6aa8273181755b215e451a363b80fbfed08b4582e3d6b22f64f274403648126fbbd3ecc8ac8249c64b0220e1ec7f7f32	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a09c54d53905ce1af95922acc5e717a9e6533078e780870a1af834194c6e9bac399a4f564f2d3e8ab23267f0c4cdae8746f2fead6974d56d9e756e52335f0cc	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x910b56d18781fbdc31f9010876fcb56446744a9bec627b4a1d50620f680dbb71d5e28feaac08b6de51370c31a6f4fb0987125dd62758c2adbe40f6ead7bb6503	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x06bc6c0cfa316a4af8480ac87076c3220f143257d62f2ec748b91636cbde5706f4d553587edce58c5e64ee4bf2c424c16a42726dacc1e31c9cf2e7023c9b28e0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf39c22c2941c6076d16f969ae13cd73cdbed4511d22ac601f589c314a17735fa87621028fa27bd4721c361a63d0c42f40d5645a0d2e82d6f220d652e872a22e3	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x54f4ddfb53c1bfc220fd93fc9a4e5566b3fcb236144e2e4803b14131e8ecdfa6bca5f68e56a3162c719abfb911d7fa48bf43b37f78cff98ffd77d7516166db3b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x306d8ca69c4ddb506275d1279e58beec9324e69d2ea877f54ca3e89b636450145e415db96ff8ca900ddcc0df34a067d8bf7a51136925ec80b93f09d3281be559	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x45566c7f2754a348f4c3a9bd9a18e1afde65285e2a07597820e82c8129c8159b6cbb28cbcdd0a6c368dc6093301eed88111610432c6ec041739061be40e47328	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x03469688001743d1e40cabef7a2772968c636aa20fc1af14f9fc6a4f749e33d9e59cac6943a73cb2ec5b770c95f5268e193e1ee4dbd77a62e5f76e84d09e63ac	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xab05cee6e89bc90727ffdf09e16aecb90e7567ff37cce2b63f62420af77baf2ceb9fb0b765c134f2f74132d56b82fdf89a75541604496d7b04f22da4a5ce5611	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa4cb330c77acf4fa79d5289295c0aab3782430683d351f62dfdfb7762ef7ef35e5ad8124de8bf62b3ab439c504dc5ead222ee850c89b183b81ea4e82f14c7888	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbefa3ebcea5f0a7e665887924e43c19ef8749a585649b02051a252b39297461679c656409d526214e55447cf22f11c407c684169c8d46cb9056273c19b0f56ee	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x232bf6dc28f8242d041b36db08867c920c32b50f6969a6350f5de987b729240bea104424af5f713105b5a333a2d5751daa574e0d4f45e111f5b5ad018fee161c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x02d77d3f05aae5524db096186764dee241881bd9a1f06fffdd5d987389f2473b9d09f9f928c8d0d383bfbdd7e5db7ce33cacfa7dc4dd8ce4f977571763c20edb	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d0a1b1ab92389a71fad7d94c11833b25aceb617b9d77eee101ee7b3d649c58527d677f9bb9834f4e76ecf390e2921d1138b02caea467f052986ff3922778c54	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x94fa2813cb18f45b01e31f657a1ed2775d1a8767c336e6c76f8f6152d0028c9764472c0924b6fc9b37b394b96475dc8654d9db3c410f63863529a6d4b9336ad0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x26d06d8ec8201eb1ebd9e7ffbf5a7d2af8d52d77541011035fdcb518953870cb4e6e951793fef3018dab88036458708806515766b1e611e8191e852c9f49c222	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd92960fdb5c2fbb916998a10bebf0e21e8f0cdd73533ba51090a3e39c3dee07c21facd92e5f7e540c300bfce730fb2e099c46d72d1bb4ae5e810b187cbe59b23	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcebfacfcb859a2a967dfb2325080a11db8d79852d16eee0d72d33a48a5bebffbf7b5374e9dd26ef28ec47fb91d1abc2e6a351e75052deea54809c1dddc4d5594	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x21032edd31edc593dac34919043710417ff40c6ec340213d7d8530423afe2b5f3d0592ad9d91301a976f83d0d5dc5da1ec41fa9335e25d18b3c178902f4deeff	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x945473a597d5b85113d6b98e69f95a002d1a7e845442720fae286c708c42b9cd1b762cd3cbb9b042c0fb0490958e957ca1b6f173ba380bf55c8ad2d50ba209ac	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb5845be73571370f7b5d30fe2eede41afce66380542d327a3a1ea44edc2a0c7b0b8e50e21ef082c18626245be7d2f23fc91dc08c0bb339bdf2efe915dc8f3138	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4dce84603d6b086e7d62ddfa1a6a42d6137159bdc849fa9f252c53f7c9be763fd2e85078e689ec8276b4cf219beb44d3347cb31cc5dd923621ccaa2fbb31507	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd6b4206b890bd56f892424f96c38f2ffaaa17eb7cdf32a6167b89090aeadda8558d4e06a0ed6d18c1ad5f76d5397577b07f9d83c3c99b0d13f54311d8f8a88e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd935018aeede4472fba0ceb163e4d3f3b0ecd18f41dde085796951e82733cd7d592dd20af5b2ba96b9563b6d2f39b817114d766224a2091c0832af628a1c22ac	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe22ec71f3f896459289baf3c2f0d78a239832316a266d82a37a11b4bdc8e14c58e33cc7770b61a15baeab7c89807906ee27c9f7f2dcad1c63cf74b3dd0481a87	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5ee0609096e0a942e6061b061f4b8968a55b0a4fad4383dfab038f6e0c57d48c14ccba76a3d9604feec70876512d1a09b64a2736a4af2d1bbd53fbebf8feef6c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0c814a66a6d5cef0c55f2598a44066bed4a1127aad05391c403cd7e74af2eddd8275ac3181b3a3ffa5356dec69e966a1432d0cdc84e6ceb39e84fe2410c4dc4	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc906acc3a1f4c1fa60db2c32c3e7248be2c317ecd4a759ef4fa3fe05664cde0cd515d14ddd6ab1243b25ddeed36adcd8be4cf0694f0fe94b80b7e265be9ee580	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x996408541145584a64b5e9a2c347107922c0516491587ab5db6b9b20f7b4f879da7d76177a53f0044f3c7cc7d30c298cdcc8873d4217a983d3b47a6c9f1b1612	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa45ade1633472126ed883dbb2340e0d62f9c4b7c4cc5e474d429c42bd2cb9ba8949660b582be94c1465856d2d137da7940ae4419494d0120cb6079469db809c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x42183ebdd30adbdd577b71ac5b11003da2a31642d864176c26e290f75ad7a0599c774e0462b2ae2b345dc2854a3827806f4cf00b3a18df21abb6bd91ee522786	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2e8d190fffdad09be07c55bc0171b3673761eab2bca727ca0f65daa005141e20dc353246ea0728dbeb65a150ccfd8160606682ce9b916a70416c0fa052a0ffd7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1567677025000000	1568281825000000	1630749025000000	1662285025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9b99e91ef9f398ad586c777c4e4a44a12250639157372b68283ff93de8622e237b399dde516fe9234c6d19f1ada7f15c6ec406ba427835e6e367c89c2e37faab	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568281525000000	1568886325000000	1631353525000000	1662889525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xebb68b75c1fba5ef753cdeb95e4996923d168c58a99314ac84303bb0a47d094413f0024ed771ed7df5c0e6edacc2714479a96d8469189b9523d1733e161e1a0c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1568886025000000	1569490825000000	1631958025000000	1663494025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6679e5079778ea9b43c1a8e0a91b0a2f51eaa3eb59217b2892814e203863f2135f3f0f723e3d8ec433a99e87abc9dcc135adf9fbb545f9623eae694b7646ac75	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1569490525000000	1570095325000000	1632562525000000	1664098525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x662427de5251cdb3926db6faddd69a6aaca0a3823482a22cebfc00cb2446a65408d1ec974a52d8117110713c56b6888d77c2a69af49726001637ef636891278c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570095025000000	1570699825000000	1633167025000000	1664703025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xaa55c848786e3161aa5c4aa7de567c6b2a6d4a5cfae3518abb4560756cd8d7b711c02b01ab5fba632cb589c86fb152625ed68c25cefd5e4c8435e977c3c2a8cd	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1570699525000000	1571304325000000	1633771525000000	1665307525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb39ee0e6d0e31e020e9bb096fdd7574488c7c33721854ebd0f3b36d73f37e6f8d9011a0e47845fff5cf8f987528d6ac081895d0518bd3bd1b36d699ed1048110	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571304025000000	1571908825000000	1634376025000000	1665912025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x168c8f650091ac8c9fec72f8b928fcb43fdebb167123fbc24ce87113bba9653180a5f63747e16a511ea1472d42db52102f61cc3528b8f33ba287082742349e99	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1571908525000000	1572513325000000	1634980525000000	1666516525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xacad4b3ba861aff78b650f77920dddddc240a24c164cdb76e05292c9b23306af93c0a7868cc5794f740d162db67def819597c348ee241811931f9e1b775da180	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1572513025000000	1573117825000000	1635585025000000	1667121025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6cfdf6b727885f91a2bfd6f272eac4a281e93316cb574bccbf4076e9780ffe4237b7d248413e91c1cabad212686fa006c5147053b932cb4b111e9ced7777984f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573117525000000	1573722325000000	1636189525000000	1667725525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xae88eb7e5da4bc31d80aef5f6514df5194a1f2e724448be97a14bd35ba20d298b5250db354ba10b7ba0e7ac8afeab5f93af5d975385f9875458eea5f743c5035	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1573722025000000	1574326825000000	1636794025000000	1668330025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xcbd1fc9b30f907575aab4560c9e37e90818b61d468ff896a2743c69227420b5ffa9e2c9110f321445a1bdbdc19fb0939e15f06e468301696ea50bb88f42c79da	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574326525000000	1574931325000000	1637398525000000	1668934525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x301454a35f7536097213ce0f5e4aada8ffafdb0deef188264f4bea31caaebd0543ab2b78cb258a14346ce449176287621f09f3a0fb7ae53d0b64f8fae98f0212	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1574931025000000	1575535825000000	1638003025000000	1669539025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x528ebc0b42b4fe3bf2527918a6c79a93fedacf452cb3b7f366454a7825bed3ebcf983eaa64b76f414a691ff41d12154efdfd88e596602a33eba1d3a43186ac4b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1575535525000000	1576140325000000	1638607525000000	1670143525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x66c7b11590fce1796ded90f7307c451f7f98e09c17cd30c8172f3001b54265a48f15fb73214fda9d02782d08bb07d717e9d9829c4292116a3bc20be45a236a7f	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576140025000000	1576744825000000	1639212025000000	1670748025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x55aa520d3af6294df538455ef49f626ae0e3a4cb2fed3e7444c6b1bf430ff0c112e9f131ad0e9b0ba561d9c11e9ad964a5f2cb9a149e90e9e61d9d7e2e08616e	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1576744525000000	1577349325000000	1639816525000000	1671352525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2d4b4c0459d4a48bc183cfc479bffa5c909f0c3f21b77d3a5703ae61046c5a6d5d351186e622c14ed9088b2c5fe3c7e27f019b9ff0b18b7f10b342ebcdc943b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577349025000000	1577953825000000	1640421025000000	1671957025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x96c425f6ba6b93b22e5c4a1b8292dbc27d02674ad02628e40f671d61e793412160e837c93c37852d9f5f6fe153a395a9cad8187b3bc749d27fff44ef36cbeed1	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1577953525000000	1578558325000000	1641025525000000	1672561525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf6bad7e808d7feadc8de86cad3a3b6df2ffb15dd90a697f217a01970c32bf148a47586457397c651be648c9d44f436a8596ce0fff26d1859a9b8ea4a43deb74c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1578558025000000	1579162825000000	1641630025000000	1673166025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x344f7c1db4e41962be0721d66c4282a11b01e9067addd32fd2332aed186cc279ecd9a45de8cad9a6b38e4eb6b029c54b8b2c0c7b2578e2299c618b0e37af64ff	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579162525000000	1579767325000000	1642234525000000	1673770525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe2c4bd75ac6a83da0b1d8d0acdf3a2e358c21a54bfc59413039943f0f191fbf1a92f245774e8969f26f6b4fbf03fec32d15b14140f0fb104be3dd8654c868601	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1579767025000000	1580371825000000	1642839025000000	1674375025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x16a40a6f3aa5c068eb26a300cb1f80e6c725bc4110fc72ed1548432738fb668805620fb0731fe7642f401041a389a9658fa56ef967542c7f90fc22fd3994fdb9	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580371525000000	1580976325000000	1643443525000000	1674979525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x797c90533c1d3af5968d1c2baf3cfe5efbd00f1fab23c997de0a0201b947b31af52de091ddad4903f9e55366137ba29df4a81a9b30dea574df90bff766154022	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1580976025000000	1581580825000000	1644048025000000	1675584025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x435656d0a527371018aeb65077655efb055568e6fae7de6c40affa44bff3c92985ee8cc0e65ba76ca51eb5736f9147061a964342cd93daf11833894705939de1	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1581580525000000	1582185325000000	1644652525000000	1676188525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xebaf2776e9bcf69dafd536284e7f40334ef7cfdd87c4ad295df6707cc2263b3353bc963bf085ef33e6c1231642f8f9000516c93ee0949a36bc66ffe421da4cd0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582185025000000	1582789825000000	1645257025000000	1676793025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb4bea2cc56fda736340aa49dfd8d99dc95cb10f4f9f398a9cf4757066356302e2cf973ff8447762343b3687ddaaef40c836fb1877767e7a0202e0c944aef2a9c	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1582789525000000	1583394325000000	1645861525000000	1677397525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x056f5851d3333a872ed27e70cccf89b6a6c9cb4cdfb3ac47be919b479b47b5b9e20bfcc53e89b451e79c5204d66d5e4d3690d867f5e164d2ef47b14e63581005	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583394025000000	1583998825000000	1646466025000000	1678002025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc702fb1a0159e108e65f2d58f92ba7698d73276ea4b14392b445766ce93890e74d12956ed9b22b293e241d92ff03203b188c77a8738f785cd995082a5ff40ce0	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1583998525000000	1584603325000000	1647070525000000	1678606525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0e4fba79e77024bb53d2ea375b12b174e48b45e647c1835a0d926bb123374eee7f6fdde6aabb0fea2aa16a12be4a35d1c52970cb00c2495d24b841ba429f5a7b	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1584603025000000	1585207825000000	1647675025000000	1679211025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x625d0f7adcbb5f6ab3c7687b9e772006f98a7a68be6b658d196da18127cb945bfe2a52221e33fa794379afe37360439d132bef7c6362975dcc849e555764fcab	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585207525000000	1585812325000000	1648279525000000	1679815525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2676f59efa5075ac97e2872a4f9d711b2f8db55e00844c2db8104a633416c2d028e090e8ede68e25145df6de34df48bbaea5fc8992bccd7d81a522da3120d7a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1585812025000000	1586416825000000	1648884025000000	1680420025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6cee0a3039d4f79abf2924b7c3cb8c300f106c0cd43ac0aaabc605a86de58c2a80d49379510368ac16e74fadded8d7965e02a1199f1ebfdc9f46c3feddf1e626	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1586416525000000	1587021325000000	1649488525000000	1681024525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x5d2fa1fcc83f3fb1d5940832e417193d7745f327129ed740da92f39c5dc9c608cb7f0a87956fe12eeacf8b117c82aef1cd6ac23fc42b2736a9655cf000ff72c9	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	1587021025000000	1587625825000000	1650093025000000	1681629025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_ledger; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_ledger (master_pub, purpose, "timestamp", balance_val, balance_frac) FROM stdin;
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

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_payback_serial_id, last_payback_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_payback_serial_id, last_reserve_close_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
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
1	pbkdf2_sha256$150000$lxsm4Zh5blQs$+bwq+FEGxQIi3IXof3fL/jtvfOVpe12wR5zrtsn+mPk=	\N	f	Bank				f	t	2019-09-05 11:50:48.360344+02
2	pbkdf2_sha256$150000$DTkVAxPsW7Zq$qtBTPZys22sqk40kPU2Kmiffiyc8pgjoGuDIQD03S+Y=	\N	f	Exchange				f	t	2019-09-05 11:50:48.562498+02
3	pbkdf2_sha256$150000$0fmpW9YdJELV$AHTEGHdy8UGsJiH4pcy4WzUoyjd/+UvZW32nKuM9dTk=	\N	f	Tor				f	t	2019-09-05 11:50:48.751735+02
4	pbkdf2_sha256$150000$wWAUbDZYQSoM$kbD9S5usaC2eFhJwNmLJjDFKCpIR0K55GgPxeCKdNVk=	\N	f	GNUnet				f	t	2019-09-05 11:50:49.065007+02
5	pbkdf2_sha256$150000$dmn01RHaEqhl$zakYo+xsfsMBMWgpCu0Kuhi8dFOPIiS/n9M2OwwquUI=	\N	f	Taler				f	t	2019-09-05 11:50:49.263257+02
6	pbkdf2_sha256$150000$N6WGh2tYfZur$ylxDMQY7QD5wiqA7Oe/Ck+OBGAC9UCNcSA0hbUnfVCw=	\N	f	FSF				f	t	2019-09-05 11:50:49.452418+02
7	pbkdf2_sha256$150000$5KeVFIfiCFDi$Jz38R6rx5G2d3/p0yASDNh6mLYRWZ8w3OyNiiACQiVo=	\N	f	Tutorial				f	t	2019-09-05 11:50:49.641048+02
8	pbkdf2_sha256$150000$6vGk3yNC107y$iYXQJUuOu4/LQ7f2KYIrQlzbqVbjm+liAsMOq3LJDlA=	\N	f	Survey				f	t	2019-09-05 11:50:49.830933+02
9	pbkdf2_sha256$150000$hvUz6ytlLoZJ$IIhzY36zuKAbGjgwk4xPfdjjssBelqqhxmArkoluNvc=	\N	f	testuser-UCYG519s				f	t	2019-09-05 11:50:57.325312+02
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
-- Data for Name: channels; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.channels (id, pub_key, max_state_message_id, state_hash_message_id) FROM stdin;
1	\\xc95a97b1446c73f157f70e9fdf9495ad8b05ee95efae4268b66a2b5a1a7174ac	\N	\N
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\xed54c128f49e3ecf42043272f298a790d942e948ede5a78c12141977895aa2ef8630db5d8f2b5a2e87b5a34c22705ec321cb018bb2f51fa7e766ff15fb20b834	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304336413739443731414342453231353541313444384136334538373431413632433231393833394142463331413934423146364343323042414238373937384143304133464443433530424546433146354643373639463342454130304441443431393632314342364236324244323841454142314633464541423332323632413433363041374333383938304239423244354545393244333430453032454334433237383833393630304438324143364142464645464139314242354134414637353233383646353041384343364633364431454337373842344139313844463338313146343131423737414533423636463630313231413942384542364223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xb8a211bd1d8c0902ff17ca11f3ec5b8e8dde192773c3f4c3ac1600302e2303536b56a1e41c7a116d5c933ec0a7bf0b13c7d81be27f801858b4e3229f82081c02	1569490525000000	1570095325000000	1632562525000000	1664098525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd760c77b8f3e5cdbd9d744610c91bc1f1f0939d67e1ce6255bd485d761004a1a517beb0611df87cce428455aa20f623f4cad107ba162edd3dc98f32e0ddce457	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946463942343939354246364343374143383538394137334444453831423239323931343930314643433331394334313334444443353331433432413732303342393638353135314446313841323846413838353633453642453133303241383538394542453034343835383743463045423732424138464137423239434439323746303033343534413544433731394239413435353744364630424337393138433930323941413737423839423335394639444138384242384336384444394343303533413430304441353631414544433431323838333334313043353243343541304438313236433234423733324531454530443432313546463738464223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x970100bcffba9df1f1e5959381207696a9ee5a07b52dcc0041318ed7d5c2e3ac153e03592f6472f17fd3658c5bd1c814fb17990eee9d0a853f3a76de0dcdd104	1568886025000000	1569490825000000	1631958025000000	1663494025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef77d29ab4dfebefe7169cb4e5a0834288ce5d50f221e422c0667cdd27b372f4a486566f2d46ff8a8d238744106a2426c000c816030d8379c697f1ec2055c26e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304232414443413036444546413945383435363830414141453933414337353233423038333839344236444237453743314242364337344343463344324342373041334535454236394132384630464134303937364542413944373845433137333334353143364245314634413642364246363634353439433641444432414145333946454130444441423637443341333943384646383345343743444542463435443936444343364335374330444641453331423339354531323031383146423932443739364338384531433345463545364238434332324434443145313441363643463542373843364230333533413033314536313931363631363633324623290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x3f8e0ea0e773ac86780ab4201c9cb2887792d46aad0935f840c0b24d4f148fef157311b1f8491089f958a2a22746dd25c5134f15517cdd80d1db9bd159d1f80f	1567677025000000	1568281825000000	1630749025000000	1662285025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x568b432c7205460aef3f01505c130c89604fd1425d9f887c4987ae1414152d443ac4bec3d5e720c9536b550931a251d84bf34a027b6a66f642373b4ba51c6285	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345393234373343323843414533383544334346433945384135433244344346374637424632373039444346303938313631463544393641443639374435444238463535343336393044453141434345333933454639443434384431463533353032463831363730323738323042443030443738324233423041453632443434313531303038423845444545374541323239343235383541454141433531323143333744344335464641313935394631363333323231343434423732444535433741374646413734323537393730354535414144303041374131413033384341454638444643363741393745343032373633453239444446453444333131323923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xb15cd797ce41b2d1dd8ca970726074c856ba883a35fac36754735a2e2c6203d3c04984f3958cd9671bc740b62c88afa32fbed49dced0633c7fbbc77d5644a40f	1570095025000000	1570699825000000	1633167025000000	1664703025000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8a59395500b5facedbb0b30769d3d9004d63d02b0b5cb17358a27eb45d3f2547d5e1be33851407b864f2e011921c524e765041e0ac05d566daffeb6e17b13d46	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304546423938334434374338423138324639423744323043343435464341434534304239353543453532363038383435314332353639413842314244353932333141303337304646353242463036304442414239344637394438454437354432463336444137303833414439373745443231344130423837413135383036433330464241344236373343314443373032433243383646334543413036463846313842323036383346434437454238423443364246333134434535424443364646374636433443344533453134393031393832424137353238444643464638443934314138463832453931333334304246423031413236363441433345324543314223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x652c5131a0e7600ca9a541ccea37884787209ccbde284252b173472f1503bc9d1d49763c834b6fc0bd16c30bf10a9df2ffffdd0829f252409bd9402f198cf70a	1568281525000000	1568886325000000	1631353525000000	1662889525000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xafea2934e234cda1630518609c9a4856a5da1c09d8c5c5d90c81bd426884485c3980e1d7914567db3c65b6d2a951825b60f53a01d0ae6de506e937603957e8ac	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244443145464446443031463737383342463331444245373637464345363146443834444139464234423239393745453741324439464335414130323241323337444437373039314144423242423043443534453836374338333037443642424139454530393738363034444130354443343041453734304436413132464643363335363035423837373838393333384343443337344237334531453633364135343042434245314337363138433635393934384446423534324346373435353133434438383839343135344639334436374635373833373544423630374534444537453733373633393331343346314530463942424646334435344446303923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x3c6ccd5428059a0fb44ffb8e2544deddeae6fecfd767bcf038048af31f12d3a0c7af24f11ff0c214743166e399be20b1ee310a8b3d2402fd5a65bc3dce4c4308	1569490525000000	1570095325000000	1632562525000000	1664098525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5acf1a2eec305b566893bb3f110b1efd477162c1168a3a58655c5f300dbe3fbc9e1e6018cac14336d05a8619032266a5c4c00d09978c929e4a3952948714511a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439423935364437383930324442394334423438323730314142363631343632383345393035423535423133344335383232323738393235324242364231343639374645323043333042353231413037423435393744454133423734304332454333463436384436453143334441384645364430314430373144313542333939433443343946464436443537393445434432454639373146323245343939384146393546443232344432364544383334354435363945393642303042364443443736313138423830463439364442384636323941464246303134453436433042383844343141363037353033414137353433394339444336423930323039433323290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x31f26cfbeb73d85509c58166932bebcd82b8603dca4c83b410c15cc5cefb4b92f0b8b7d1dd65069726a2a911068bd9dc0e5c461dd0032a023091aebac0da0b07	1568886025000000	1569490825000000	1631958025000000	1663494025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x159024e3330ec693bdec916ef5d9731a7ce8fbf53195d6d3023b09b8d1afe400ace59ae6d5e55a8515a98a07d1bbbd77a6ac83e2f6e9aec4fc6a1b00627585c7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334314437414132303944433046353338464332443531443137353145353437304338313946374230334443363846383239413935373544383039353244353133303537394336453430303442343234313233334233314531384144313035323544344635463743303832303742383034313632444334314335354335373544394237413532334242383237434146413141363537434230333031313746324244413234453337353042303945443431364238423436443245423142414141394146343831393736304334433646333338324443463633313843413746463441444145364343423036373331413730374439383436324435413335444646364423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x5ba42536694fe587e9f42b1c03426c76a7e226841eb80a4937f27f4b2300f318c1da6d15887689bfe2e3ecc97e1f3b8c269342769e9a2946e8c33c4b48f99200	1567677025000000	1568281825000000	1630749025000000	1662285025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfa2a2f6a1c9d7e7d1af58632dfe9b4fc502ab766b3f4110f034ad657b178fba633495af51ab6254b8f60b9685bfed620dc8a6313bbb5bcfd267d0035360bd269	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304534323838453036424538443736304246334635463739334246373445393433323733314444333430453343353046423339363036394334363438443346363630443641453539363241433641384135373831303742424534373833413232423732384630373434443234354541364142454339343045313930313139333037374131363644364642443638303945423938353831363946394139414344344531333146453541353932394342423434333042324137304641343141364146304138423830414435374433394143324545313646464330343932434541344233443337394541453438384531354138413942304142343736463135323437344423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xbcec40783e6cff58af9a7242ab718cd3216d8d4cc6df450839d12157b4f4ecf515aa167579343c14a647e4786ad5283b1bbe32474b9ee69229e561814ebfd90a	1570095025000000	1570699825000000	1633167025000000	1664703025000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe35608f3b19f877d8c317e58e696fbdd038319ff9a0b759bb5680a3a0d02e8a1f5d084185c610123748335012a510b049ee3e798724b241b24bf62c94a3b7bf3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132354339383342313433363132374339464433353431363945373339343734373333363634374143364231444245443345414144393736334433414330373431453445453132424330393235383041453943353633433344303942303042343245363642303246394645353042324135434242453630363032314231393233343032464645323030443736333343323242363939323834344335463642313445383343304442364437444437384137333330453041454539363239384634464334453139333233424231454339324436444632464444373145383430464232344439463934393138413531314245433046433544443132443433444338463323290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xce50a229ed3645b3e5055649de4080c360684601f5e15fd8b01aff7a95c904ff1340402124a163749e9bfea2dedf80f6368e4b8109b9877fe42e5f2d1cefae04	1568281525000000	1568886325000000	1631353525000000	1662889525000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x055e6d97a972932cd958532d4b5a60bf4e298fb0b082464dde215c5bc6cb8908d2d22bb05ce6f3dc3527f8758a7b59afd18d9f9f11acaed95170579690897dc2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430373844464630423143334136383239303645303332354534463945463130383936343435343241324134443343343735314636453537413535433430424238433141463235383443314339343243443132304145333831444546423634414435394144383239433530423145314131424630433636303144413338383542414342393532413038463337373032463332353439363742453938343943443343453541413739364238303736313744364639324439334242434633394639334344433134393045433041303143343131383943353937374441453936304331413335334436313033464345363636413631374331414630304437443333363523290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x22f9bd448c096ceb79d917a7601dc28fdb44d453f99776708c618ee5b87f73456f8061dee1e8dd9e1d0304c3a103e8697e4ccccd69e05fb58aa7cbe55b6f2d08	1569490525000000	1570095325000000	1632562525000000	1664098525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x54d8d10a2b729faafb576323ac813f0300933a0c06ddb1350d68347df5fd66b3f109f5bef776caec15eca9eed9a3a10dfa998ef676d72d47d1194d02021583dc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304443423332463544313437424237354334383133433138324343414444464633344439434446393134434335424430374342344432434538323639443832453939393136343339343642413830454133314234334533353930434144313532384233303332304338353742444345393338443245353534363843344338313730364437453243463039444539314546373337414532383936343838313045304444453843323037394134464141363741434435354443373545343837423339463844454239443343314541334539313945334538434345433130354638393042423430303130303539454444423643374141443032373535303633374534413723290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x4f1fdfe51114a64a6c14aa2a0e63e80051087b21aa2cea3d39e116d67d90e5aecd3ba3d0333906b3a74958ed03cd4be2f69a9731fdbd87c5bb653272d038d405	1568886025000000	1569490825000000	1631958025000000	1663494025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc1f751bbac69b949e6b9b53e4330fc399bd067241a9dfc43a9aec7be594c82c272e10402cc336ab7a99cb73baa0a60c2a7678a78c0ca27d0039690d51ae31d5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132354343413345413441323844374646354132423143423646463741354532334537383034323132344542313244323531373745344345463137443642334534464230443031333342424434313530323542394230353631304631363836303731394342354543343035443343384233343241423432333932414646333931463632384442383144424132304242363744354630443937313735444530354538323835353637353534393739373631304331364336343036323134323842434342463533313739354544433342354541393936343043433538453635303436353337454439423935363432353936324336313636424233334643434334444223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xa372f73963bf76bb556b10bc9d249ed973f3b8b9235784bbc57e0e24c3e42f98822b4e0fd51273d5c5fa734228736ed73a7dacfebbffaa2106e2e7e4ff7acd0a	1567677025000000	1568281825000000	1630749025000000	1662285025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x659d2dc9183b4fcfc09c2dc922c14c42045bfda88f1f2442588fe6286a9c5582e17234688d6dd75f42579ef5ed3e84a83cd3583804da3663130ac26d25ff2a10	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143304246343841353743434432314244423242383444414145303534374534454137343745394438464233313532303231443743463346363543393432464546303635334144363535353042463545353138433134324432453838454144453839373938433745323239384544304330333945424345453942333242413234383145353244323244454432413538363545334439344636323431454137354641373339373445314434414343433741303443313542313345383930423446414338353031383631434638334238373246454434373233434443424539314438423230394233424231343238343831434446393844333833313742314539424423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x1a91535cba1eddc9197504d6080d42c52bff21f20d998f47406e442a8dc9bd6d0b0081b3e5de777adad826c0bb233a9ccbe602398f29a08bc8e827666133f70b	1570095025000000	1570699825000000	1633167025000000	1664703025000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18233edcb65ce36791ffef858e77df1a8ed3cfa1dba571a789ad49c6b3b0cf88ae02d3ef7d07adff1a0e76667dad1f80bf8110974ed71df7bca7ad4e0f00103b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303935464330414546363330313230383943423842363345304334453237444435394645343536393735353338333845384242343734333937374438464243413744373638433031433737434442353341413534423035353830313046443942333932374246443243454431364646344344373736453331453531363035324334364637353042413335423536304141444632424644334234463934304638324234364346303646433430324638353936323841374339344646463630304446364643303345434435453245394636453343413043314142454630374441333741354431463431423837364543414235453243434630303236323542324135344223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xe5e74cb975f83d8aa7f2506a6f438426e2e9a6ca32404b7f1ecc053fa15de57e2efd92d7fd1e94909692b7b0f486ff132e6b8743c2c65fde055a7d0074f44903	1568281525000000	1568886325000000	1631353525000000	1662889525000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcbb943dc336a99c30708393c917e32b7a20d0586a5b1a083415ae32d3cc8fbd686fcc1e13cff4694de462cc3441b19e13f080abac9204a139a3bdc1dd6be587f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303941463035414637423645333646343532424432423534363839374142364136414543344245323345463842364642433335343346453230303430363630453536373843373242394343333846383142453935344642384145354530334331343445463342393437463143464236303437433731333136464132454134383332444142464236424646313345364239364335453742334446353332464441413742313934423337314231413744453831333143463930434238443646433436463546444534454138443430363730383544463441334637333436413944384333413333354235383631303437343933343734433934463841423230463544324223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xdf67a8a9822c626a58fce3b52219b49796f9af321f28993099bfb6c8a83d925dbbfb78fe9ac051b2f4bc551ced4c281c426842a7d02be4ab5d20df192970b200	1569490525000000	1570095325000000	1632562525000000	1664098525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe887ec22b3f9f8eaf9d61f97fb0224e9a7b3f2259720bd13d6b3cf96c7562ec1b46bd6a8524d31ca61060ff100ad83ceaa4858c2a8129a8d0882e98b8d57861d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304533443334413341434343363243323844383143464137304137453339363234444336353231393242313939443936464531304132454239353043444336353545463838304437313039463533314139454238314541444343424630343445424144314341344231313138453241393933344441383444424242364635454645383238303636384446373136374635453539434642443341334646414137423737373646433539323238414643413736334534363735443330374142414443343344444630314334393337434343414336453745373932434133463134364636343134383541363942393339463837454330324338303646393536353846413723290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x0a5dcbb6190938176b145221d681ddba2aa51df904d3ebd37db8e8a6429dab55a9ec5bb4477ea54b89bb2575c5c7ad5b56952a03b780a8514841d77150ff7c02	1568886025000000	1569490825000000	1631958025000000	1663494025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3a1c7f90cf5f6e294ed83b176d767625da64db9987285074785fe918d924e0aca97b63c5447c366d05f3f53bdc11078acc399e43879a21d9778959702f603cf6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304532313034393845443943373730343132383238464242453235454242453539343738373241423033453531323632353737394443353035324331434446413338354332383445353032444533393130453146313243454645433038323439454443413044443044363836373746463235433741373838373138414446453734354339463732453845383235353937443435443333363031324546303836434534324141423838463544393236453444414239373145383841443833333646423344363746373331444246343846323337333635424436314446354439453930393232364241353036394434323336343139454437433233363533333130443923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xb8a0492a3ab30a82dbb1e6696eaf321e93975586e1ec9dabf3e5b4b5ef5465e1452a7bfc24f68ba0630547d1a8f4e7ee282f14bc99fb2aa17e48e2778339c90d	1567677025000000	1568281825000000	1630749025000000	1662285025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x545e3f0dd5c4808c90e5e86b50f4d9f6d6908ce487ab36eaf2faef0cd6d1c942d0a06c5e3ef4241ded1a2d0e32e59fa6e81893508a186253689443023eacdb0b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304542343441393136383342364330373239354245423532313533343944304145364330394642394644463238393041353541434244413437453741353236373742443338344635434246344330463433344144423436454445303235323031393735424236454130353632383930354138364135333131373843414238383131333735443734394137434139434245343338364237363131344234324542364434334337313032353231303941464136453232393230463045304331393638443141333838464245394232444434393641364339334542343139423639423742423030383032414445433342383842443338453034424337453245353643353123290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x6e97c6733497677dc7d59ab498d8fcd468e9c17749ea08b73b3a2933d05ba7437e5f38103890bd72b63d2f44e8e58364d199777331fb433d82be6872ae661109	1570095025000000	1570699825000000	1633167025000000	1664703025000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x425ca1d79fea1eb6e689ccb2193419278bcb4794dd3e05ca72856eda4b1e838888831761cfad3ed5a067fb9d7a92faeaea433406abda7c3de7bddced05af2dd4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304446303935424131413833353432423437313830394635433634413246394532333931434235343245353042433043444142363342343738363034434544353233334542303533333230363536333531333941424432334638334343463435444642463430453034334232434534324637343133363234434430333839443541323430443731343846333137313639384138383736444644424142353638374244433938334342384545454644433334464330394142463843413444443342443136364346363545303941434543333031454534373344464539443836354243323738464241424238374542373145383242323946364241343037424136453123290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xf9500df5c295394f4977dbca2fa26762349180821a6a7636437dac342fd5fd5810f7b1fd41a1fd057f0d7d527ed490fb0ce6402d483fc324f9141d8eb4ed350a	1568281525000000	1568886325000000	1631353525000000	1662889525000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5c81a7ea4ad5574691892656f5286580f8d082ba15a7936e858358bc7a0052236a6cf46cbba26c38f11e5843c539a9a17253f8317a1f5d6e03e2c3112e0d8c32	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230323232463944314642314346443630324442343132303536414636373246353438304437373544383145333344463636344644364337343645354144383233443030444539434534363432353332314132443945343543444431304638333744423935453035454532443133373539464232343234414531353830464136454241323630393233393435344331333845463542353639323337393434464537453039354134353344413141353445413531353739383038323042414532463445423741324336363842353333453346383443414632423246413032363334304145453338373434343439313936464234354342363631464139423135304623290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xfc85a3067b8ce5ad99b400e52cd9b0a56f43efd887a646438535bac25f4a1f975b735ccfa067aea1c643f5b6acae62a2867958123df0bc884d9ff49685d1450a	1569490525000000	1570095325000000	1632562525000000	1664098525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x329bdc07e51327728cedda832872ad13a27cdcbf3f3e83c27ec7a77236c29f7e5c154db971f78f918da5aeb631aadf1b199774e5e0603492c24476d5e8ac584e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304535434336443544353445414130414345353338323136443538383143373834354431334242413133333939453539373445383742424631454339333837444341303834413646423031303230433444353046424330303138444137303546323032424432323638343331364244434332323533333530343539463541454530303543333943363043444146424638373534304246374137433534354630303545354430434643434638453643434436353045433030423834323635314438374345423036354345353237383746343036453443423033363945414430463234424446333336343133463939393044414236433637414142383139323031413523290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x673b51de8cfefc4588031acb44b12e67ff38f895e3bfc95ca7b1afd596349c7933d55e6c7b869bbbb419cec31db7476fe5138d9abfea31c0a9b925fe5f451f0f	1568886025000000	1569490825000000	1631958025000000	1663494025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe79b866e1793c50f1af8d0178701cc0b92fb636d0ae2c5ed7206b9263aa6d439841b3485e9dda3c510a8ba0b191389949a105544c8159e5ee555ffb5280ee76b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304438304141464145304638373933414241324530453835304235454635393943353438434435393330433743383939453736344433334545443435304545353346464637303341353433424235464138363532464436383045353832434130373138373330324246424645464537464336313343353644444537414439333336344244454631364130353446463643343635393844334445434531363839344133453746453646363041373339463835303835324232454141313730364533313645413435313937463845324342423245394131453942314236443834393744424433383141424641373338334545333139464230423046334239443543323923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x05770c01b5b2d991c7f3c77c800dfbe4657bd4418b6f275ef9b30a4b0bc6a6ae2fa31a7e89c85cf0ec8cf6926083382c25370c9172cf9d1cda0859e924c1500f	1567677025000000	1568281825000000	1630749025000000	1662285025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x800135305eb98d9247f7385dc4465f1b01c7d706d6e2a80d9e84332926fb003b9f04440a68acdc80bf999c71a63ba4d4ba9efe886b39637c1939cb1d901ec9dc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332344646353737304346313945323436323944324245383834393239344135323938433931323344313945303643314646423739324437433730423334423831354536443632364432383242313935323142414231423439414242324138314344413546423846463638373444314439433835453942423434344534303943373034333432463233454441414634313137354243353531434633443042364543423236393733384543343145373739333633383344454536414230444137334343343037343045303845303739444533453246373944323242383144383238363131424142374644433043344437344635373231374431363637453936454623290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xc82a9e672f33c7836014414569a5dd1e82b42d3c06d22f67cafe1468a188c0aa9557d11995cb9020fa83532d11f9a85478f8a0a6f5308389b37689fe58d6c506	1570095025000000	1570699825000000	1633167025000000	1664703025000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcb089acd9c5d03f6c82ff5840219250fd77ecc86b3d49f514145937f9c814bcfa324582a91561b9316d258c4ac51f77f5152e33054ae4a5d2bb1c6291989178e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235453241414542364337433941393633343030363744463534383645454445333236384639433041353634364243303643463638363933463837383135363143414237313833334246333033333244333433364434363342433645454435394633464234433736323545324244354231364138444644363536304634323733443739394536344342343235413030423731443934323741383946364135343132393441363735334638394335424233373330353730463944323641323836354433463830374342363437394236423038383538453933383636394632463743364537443430444635384130304636413134323737343931394631344141434623290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x0a93a9c0cc96773a2c0ebf2309816a39508e97537756a4a90ccd99c143731855b3926b57877d1a69f2691e503a9a7b2316c09eca7a0c786965a25534d4ada10e	1568281525000000	1568886325000000	1631353525000000	1662889525000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4649a9269cfcba9746f68a0025158f7f1eea3005666396bc0d1689b9f57dbe1575dec74ca9ed6657dd01dc3a33b06919ea3e3e09a757fc697a9f8ff79828d72c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304630464344354342324246304339353136384342323243383838373746303835464446383145444632333539424346353836344346304630363746423133373930324137463538314446373036453643394138373830343531343630353144463032413344354131434234454145334236334136323544334145424546384646303744333130383543393933303637423831443741323539344632373733444135354134323930443645413445363143313645363043353944413833333839414143373331343636343742303343384646354333343438383044464234303141423632353135344431454643393036433546433238454436424633424338343723290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x3ff2ca9219238f49610a7a598186f492ae7a297e5e2a37dc53960393597f2f35c93730146be4b0ebf7aafa67ad9883bf22f75e133e2dad2f458ae523e162b204	1569490525000000	1570095325000000	1632562525000000	1664098525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x348eb1d0eb10c4b118e74cdc8fd967389d154d1401cb39683b51a06d4cc5168545022f3db973e289e45157cc567024d8af31633aa7c484e1a5bc7b320ae6d68d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242373232343834424237453441373143433942423736384137354241443138353033343830453731313039393838333138363539383941313634453537423641363539373836364237394536444142454636434338433042413330463932324545314433394333423843353142414337453644424333333945373335343034463336354438443132434546424233304333424144453737393542323034463830334142414536363639424343313439344444453333364139383639443237414144374439374644383742413636364134413339443335383242344242393330353841363034424237304139383342333043433742314437453130464245363923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x0eec8aa0365521108ed4e6a7c066fc23f17cde361446cf15edbe8ce4a23090dcba9f6e902b457f592a3c044f9fff190f2703319f7c0145719edb4b83b307b80f	1568886025000000	1569490825000000	1631958025000000	1663494025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd35716af21c5edd882cfc39b16e079f4192741fff1a052152451442d33fc167ed09cebdc561a608cbeca1c3b26b28a61798493772c9d4bb9b269005137141eea	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304633383743304632323135314546324430383236303532303935373537343345313934413144353836334444323233374244364346354633424438463130363246464144384442353844354635353144413146423034423432413338343931384530413441453838433531313639443133463842344546444545453146314441304341374431353846393043444443324638453036373934454332333139373944353339443932444439303439363642373446363837353036324437454332423241423534423643433341394335384144433630323638323935363143434339323645304331324642434533384632333736414534353435313943454636464423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xbaa6eb89f16310e8872a979fc9f7962b9dd09219cd7915a720b98874592f9248b211e3862759f484e140ac5c51857129e101033290377be1f42d1cfffc743f0c	1567677025000000	1568281825000000	1630749025000000	1662285025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c134e93d8a103db06f653759fee610132c24feb7d8b4c88e930fdec9c0fbce3f32fd16624e137ad7039e8c7d212fe874c3e92f8b56a70c228a6bc5ffc1a0e50	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442413143454641364432314133324133343344454244373436374544394333413935323835423341414344323639343831303746383034343139373938353646303635334338373336413930454646323335414431354131453843463541394438303633343142333531463242363646443442313530303538383638364330454639373542363530453446313735344545464237464230424137463533354442373430464443313832464136323633354243443439434345413145443441413845434246464535413444464138363630303239343331413036304237423431423633383930424246333544333343313237363241433145374630383337393723290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xe910bfbb7d77de36679e213806c6863de4ce5adcfc8019b4bdb9793dc6bfce240961c87bad33f58305f9276e0be05150aebf25a801257e055c3b4f64dc08b502	1570095025000000	1570699825000000	1633167025000000	1664703025000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b946ac707780d8c4a6f5d4bcf1b77ca6dd50ae83ca32cdcf313c8772e5332c2776b1590e64d87693f65a8ae084b7c5eb578a5031c0de2c9a5c056cf9fa60e39	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304344314645334339453234423537354246423639444245464243323837364237333932433430354445394331344444443030374543434137453630373832383234424346324234323645353534463739414332423436463737354439363232334131393441463736393237313246424331374336463230353432363842464137353239413341363235344534434539334241344546353330423145344334363338323345453443373433433036353031453343303931443143464542344241413731324437363041373138354335363830393744343045464437364343363945373936453044433731323033303845363631443042363132464435353535324423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x742302e648f1b733f4156f2c5790e0e162aefa513f1e5e2645096d2824d42b5107f32dd0139cfaf99b5c3d57fef6fdb425c09f632a453c2b86dbf28a55ede204	1568281525000000	1568886325000000	1631353525000000	1662889525000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6679e5079778ea9b43c1a8e0a91b0a2f51eaa3eb59217b2892814e203863f2135f3f0f723e3d8ec433a99e87abc9dcc135adf9fbb545f9623eae694b7646ac75	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304532313643423242303036444643383743314242463841463244303542344534314535394230334134313233453545433334453737413936334432413937303646363937413642423343453432443338313044453535304334373641374345374630383438304230413534363043414537373534323346383239344631384543303444444530333632433335303130353346394242414443324531434444363244314436423945413734333839304643393037303834383633453539363145323235374537444132423134463045373536454336434145454344413637444239464334423646433945453730374142354430363543304133413441303345363523290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x56b2d96794cf50c8399642893a67c2f552054f77bc90e2da65b61d4d3228fbe7fdf8ad371acbd44d054d75c02b9725211cacde43189850bb8c2eca6f22c2ae0b	1569490525000000	1570095325000000	1632562525000000	1664098525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xebb68b75c1fba5ef753cdeb95e4996923d168c58a99314ac84303bb0a47d094413f0024ed771ed7df5c0e6edacc2714479a96d8469189b9523d1733e161e1a0c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441384445423034363141413734374531444144444442454145384444333134304245334634343743454438363039454138413043464241393735343543323131334541374639393630323031443234303741353335324235343533314541443332393246393333463844364641393441413438314432443138323136343546433145353839304231424134443133333435393541374434314134434344454634443630424644444536414439453645383742304538353942453035384539453135323441394637343237373737383233323545324443433844314536333741374345443633344443314341313734394238353442303331333433423245373523290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x47cbadf35bba7767953c125c9aae5e8f8de79a34a63064ef3c8c99f831330c5a08fd4e2936799a272443375d0d3599da3efbda2783fd1083626e9205a6bb470e	1568886025000000	1569490825000000	1631958025000000	1663494025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230423541384246394535323330304341343039393533393034434430303531314232303242384234423732413534393245433433393332364533444242353632394636383838384245423430433837423143374144354433323933444236314435333235373834373641384334463237363030313334304533414630333544304444314142304535304434443545303231453445413036464132463432303136353435433543413232433630454246314246443233444138304332384334324636304346333443384534363643313139413545393135303036373133373235313245323146424338304632464338323145353535423437364332303436424423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xbdada0993fd06b48a0bb3950a1f40f6d5c5fd1b277b925c7cdb367b4349e9e95b1d0ae5e193ef77913cb3f69d48b0fbe02d0913a3be6d77809b0618fd206360c	1567677025000000	1568281825000000	1630749025000000	1662285025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x662427de5251cdb3926db6faddd69a6aaca0a3823482a22cebfc00cb2446a65408d1ec974a52d8117110713c56b6888d77c2a69af49726001637ef636891278c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234454433444345353638383736413734443130353841383736333341374442424537424344383630453739434535323042433131443032344145383941343844333734463635364546323944393338463137414439423936443346464235323439363646354335333032364333303335413432433642354233394635324238394232414642353334303733433634424246344446343734394646363546413946453639413730353834424136343634423734373831424333323937453841373633464532453232323545334436414446453345383241433541454335343130333941353835383632353346453235353745333346303841444533334633313923290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x9d91844c77e01584c970be1fce23adcf6be8537bd472aed641b53355cde8fa5d5ad312cabd272d12e36ee05631f9f46348524a7a6305453efd923afc1924c201	1570095025000000	1570699825000000	1633167025000000	1664703025000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9b99e91ef9f398ad586c777c4e4a44a12250639157372b68283ff93de8622e237b399dde516fe9234c6d19f1ada7f15c6ec406ba427835e6e367c89c2e37faab	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244374134363145463336383946354630333634334241443030364144303837453935363244463632333830443143453945393333423542323343363638434634333033443945334134453236464333463037463439364346424145414530374534453241443545354636453737323743383942313545454531313538434445413033323231393241303842373032463834334341383533433131373241373843344337453733344441393144423444393534323138413744314439414430354537383642384630444635314634394544323643354538384438384345313146443441344241414439413646374241453932424441464343343331313546303323290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x27a3e6e3d540a84e011e51f27e9c22522408e68b86230f68374e4c70354f0c101fea1acda3aa8b36439b846f7fe8bc9a60d94289b5b7c1dbb41fcb17a24b6806	1568281525000000	1568886325000000	1631353525000000	1662889525000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x06bc6c0cfa316a4af8480ac87076c3220f143257d62f2ec748b91636cbde5706f4d553587edce58c5e64ee4bf2c424c16a42726dacc1e31c9cf2e7023c9b28e0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139343939343436413541384342463139453845313932444545414333313731314342333337433738453630364644333535383642433143323830463842363535373939303935424642453143303446333244343237393534383336384134434133353438323039343635353435313141313736303437333131433838463431453744374345453638363135464346364537354138334345353836353041453346453846443742344342414142333736433041433136363536343344424344443632304236423237334346414543394139423346373144383535313345383236373130454535343733443642443633454642344132344438453746353345374423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x009bf29ce98550195d395a96cb7f800a973f3c507a5715f1e8f2163ef931bc4219e398f7621fc779c5f69e00264de169c4cb95ce098a10fa0a80f5dea68fb20c	1569490525000000	1570095325000000	1632562525000000	1664098525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x910b56d18781fbdc31f9010876fcb56446744a9bec627b4a1d50620f680dbb71d5e28feaac08b6de51370c31a6f4fb0987125dd62758c2adbe40f6ead7bb6503	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245303838464139333746463839424138394437313544353946443835374636343046423746354646433439463645424534413537453543354234453843374442313931443836354546374333313946393037454431353136413330313841373343444534413830364345353335443643423436324538414543383531443142353546423130433034333132444239384143443735464334393732443235383045433046433938394531373741424330303743453146333644384344303241303433303944424130333441413941354544383745304239353341303041463441333932414438313631374634343546363336433946443545324434364646384423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x90f9cc819b775906b5d688b5cf564310077408e506153877a1dcd0f2531528ea6cb9c1a0ab5ed5bd369c895015db647a213ba0c9e8c263f11c6af4c845d80a00	1568886025000000	1569490825000000	1631958025000000	1663494025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233344538434633393445343531424236333931383634343234443230443633433732414234374442414333394144334336324539373144354532334232303242303130353441343235443438433344444137414533423732464236334237453341363038303635314437444434463435423436414446463743333331413337454641354639303936414637374138423732443830323445363841463239444535433534444636314133463044453334434443324332463430314244383439353345303842374331423234323246343831303235443136304137443139434636343845434243303538463433444532444436463332414336414433394441464223290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x0dba56b8dc685eb09be02ab111bcce69a3e2c471ce2c5621b2431b07f1ae28d88213ef40c1fa829142cefe354d5aab021bff91d29c5ef6e6faceb2281ab85d0d	1567677025000000	1568281825000000	1630749025000000	1662285025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf39c22c2941c6076d16f969ae13cd73cdbed4511d22ac601f589c314a17735fa87621028fa27bd4721c361a63d0c42f40d5645a0d2e82d6f220d652e872a22e3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333334236363938383434373334304337344634423839344637323845433541454143413736344432463631453244454445304334363244314335424633393730413231413542413537364535303131453643303731314332343235314141303239413639373632343138393033303432444531463041393746354532354134333533324631423634344336394543333435333745394532463342313038463043333535383732354438433736464144383544373733423539443333414435304142303744394346313342384643323538453035373934394544323744384235353643453044443733373842303746464642354639453837323833353844444423290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x2435f8af1e0b3bc8ebbd734ffc141287808102f746f793ab22f6bf02e1ce6112f8e576236be8f1c3b74ce46b43f0c2c4d17253e2d051ab9dadf5deed73d9f104	1570095025000000	1570699825000000	1633167025000000	1664703025000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6a09c54d53905ce1af95922acc5e717a9e6533078e780870a1af834194c6e9bac399a4f564f2d3e8ab23267f0c4cdae8746f2fead6974d56d9e756e52335f0cc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132384235363442344237313439423441424231434134353130313235314432463446433446353236303137453043363146373341343542313230343043353830383335323536463738373234344137453342373745373030393436323731383246454632464335373933453136373433394235413735443934394336443434413337374238343331433241373932353034434332413833443341373338453045463236343338383036303441454241443431384332323932454635453033423146413641394432394631453035354144453046383332353943323637304543364432453439453637413232443632374635393634364335373035313430373723290a20202865202330313030303123290a2020290a20290a	\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\x4400b24bc2d369260d5b5612cb0c404395c7acd0d30a71eba44bc52a3b00bb0977ba6870a8b92874c4de41c157b02dae0a1b2c901741a94f24f8b633fa788e09	1568281525000000	1568886325000000	1631353525000000	1662889525000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x62aaab92b4c96c02333e000a4978a0829b50bab61242c26d7341df0dac44a150	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\xd27741be13e156096e8210c229804514cdec09613c16873b38a5b409b5ebe47c68687ab88344d6fff3abf15f719f8f265eee6d2223a2c6c42bc094b23aec580c	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
2	\\x95babf03daef5a45847737ecb99c14d113d50f80f5e8b2f1c94182a401c9a35b	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x404f30156137b13898d9d9b0bd8f23d13de5b5aa303b82e01a8b0d6e22c3d19e826da000d35bb005bd7a0920691903342db2750690397e080954c1b86934c40f	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
3	\\xed23e80ead6cfed100e8892021f8eebc8d79a3a04f6b9af43ecc44af76515477	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x5c622e2cf5dec63659932a72e1d7c2cb5f013869b2a1531a30dded00e4ffc45e8e63d60d9099f3a025dd7b9cc8decefbf6e248d78251d5cdd3e76a8d63a44106	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
4	\\xe2ca252705d6f528cef3513af51d565d689fb8032746d8d2cc1355c3c9265fa1	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x1e358dda08667505e9d08e39518b9cb19f5d175fbddf8c47277cb02a479766776b161b62aeecf5f475780243caa1d4d493c97309d2703cc1ebd1cac768d18f07	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
5	\\xf2a32ab03c43fa9de118b6df9b623ed27ef65bc5f5b5a8bd5da6f65ea11160e0	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\xbffdf7aa4da59f04e11d06ee68de8d1ba67a3ad04a1de601772e133a20f58f633b75404c19194d7c8dbc73ed305e5963cdef4a0ec1e93764d0c0064e0001a505	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
6	\\x1c616967029ef73c02eb8fdf0efa68afef27e1863fe5ae631ae7105bc82c6ab7	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x4ac71676d174733acfd191afc8178f2ef72a5a047ca6abbd427f423562685b44399c9deeb2b74ece3c1e5fca08cdbf57985683464d51a2f4c6f7a5852464c107	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
7	\\x213f2d7d2c57fffbbe8e5122fa86cfaec707684f598f9f495483a4f06f4bc8fb	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x58484325b90774861afffdef5c7c571dffa418cf26e98b758f83ba9990eccadfd178e089d12c2bb1203070179ca67040db717b3b3ae9f8e2f2a0ef8242080f0f	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
8	\\x9efaffef1c5a6134d8383bbc78bd32649335005fb68d411a5504afe4196d4523	0	10000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x7fe56e698fb14c4e4dc9f9e08101fc070e03fef85ad49288557870a8aa0cea69c56519f6cc84cb120ca11bba0f9f847741cc193dfa7748a7ff3bdba6320da20a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
9	\\x8690b22c0765299e985da6dea34db279dc9fbb4843fd9b7d229699bdff4d83bc	3	20000000	1567677060000000	0	1567677120000000	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\x0020bddb6fa7f449e5890e65b5f9b2a361dd03ac6eea81c66b2f7971259123769d3fbbda23650232e8dd8771cbe6792bb7b0cff94d5d214c6c4826013413debb	\\x1dc827bef85d0935de3fedb88a6419e004acf9240daf48f49931fb592f46c686b40ff05559b6012a214f203c854412acd3085edb3c807d390212567ac54b4606	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"M29H07W0E7C3N9E8SFCXTAJ3F8C81WJ65QT4SABEJ5W28XTT7QD14AD06QMGB4G02HTSZ7EYYRVA8T596E9TFPYA9HMFD6YHEQBASK0"}	f	f
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
1	contenttypes	0001_initial	2019-09-05 11:50:45.110844+02
2	auth	0001_initial	2019-09-05 11:50:45.773992+02
3	app	0001_initial	2019-09-05 11:50:47.331852+02
4	contenttypes	0002_remove_content_type_name	2019-09-05 11:50:47.749644+02
5	auth	0002_alter_permission_name_max_length	2019-09-05 11:50:47.778609+02
6	auth	0003_alter_user_email_max_length	2019-09-05 11:50:47.796364+02
7	auth	0004_alter_user_username_opts	2019-09-05 11:50:47.81938+02
8	auth	0005_alter_user_last_login_null	2019-09-05 11:50:47.842761+02
9	auth	0006_require_contenttypes_0002	2019-09-05 11:50:47.850727+02
10	auth	0007_alter_validators_add_error_messages	2019-09-05 11:50:47.873486+02
11	auth	0008_alter_user_username_max_length	2019-09-05 11:50:47.935121+02
12	auth	0009_alter_user_last_name_max_length	2019-09-05 11:50:47.96301+02
13	auth	0010_alter_group_name_max_length	2019-09-05 11:50:47.990253+02
14	auth	0011_update_proxy_permissions	2019-09-05 11:50:48.010183+02
15	sessions	0001_initial	2019-09-05 11:50:48.103252+02
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x02ed9952bb5cf153a3babed0975059768a047b2b883ec257d5d8369e1256d84677a80d6c2fd6e668f2b0a274e1aa9077accf2f2caf45a95529c246e685fd3b09
\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x05d4ac882d6884e712c90a196d5b16462963b3f249d055ccc621a07673e9c99b955d1f7a80256682d4489cba64fcc170a0ed88cf33f66e75efd914d57ec21e07
\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x40ea35357eae019a3c51a1b7a19d10f10b604278ac30e09c11a11fdd401ca3c85704ac6a1bf2f792065ba0077791e07e893aff13399b6ad08d5594f72da6ac05
\\x754bdead81038a1d62a069ff509deb66c4e0b99b890665ed142bc755576f7d32	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x00d00913bbeea2a274cfe047e2d96be58a4550afee1d2b812158ee545687d070f9bbbbcb1e34130afea4d08f66ffbfeadcd1138417a836772dd3d4db9f50230c
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x62aaab92b4c96c02333e000a4978a0829b50bab61242c26d7341df0dac44a150	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233545343437363141373337334130334646313343413232374235433432424134323132344246323842373643433633463744413844314541444332463539343639444434413943304543363439433835444538423845433638303039324436343036434641344546413338464530463837464439343631453338383845393830303936393931304238323143413045303043303230414544354231383437413933383237413735363135304144313142433936453632454334423232423536354543413731323845313746424637393337444537324544313036423433413045394442353439414237413630344145363335333544353444443538413944323923290a2020290a20290a
\\x95babf03daef5a45847737ecb99c14d113d50f80f5e8b2f1c94182a401c9a35b	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233633373232333843413543413330433438413342424436463233303439333945363932343538324246323132314445384630324537363330333734463537363439393531304230413944313636433437373836354234304636443837444646363331413735313630463337443839454643424146424632434130433835394239463242463030333637323246393144433730453244303431353438383644464635424335463431453937464433363742454234314146374333333532453744453333303046323043424142393346463146453946434332464236413037393139463732463630373837463834434438443530373134383146333241424146373923290a2020290a20290a
\\xed23e80ead6cfed100e8892021f8eebc8d79a3a04f6b9af43ecc44af76515477	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233742324245303032373433304630454431353744303342303436383936333444373732374441443141463137384541434131423037454435464238443335394233333043343342393339423942454535423735374538374133383332414242354245324535344534453537453431304232334232334444444343364146443431384544303538424539363231353235414133384534323233303431413638454543333332334230463846464142433541314146393832343237433741374239354537304133424330324141343842363542313036314439463744373342314237434246384141433331313236384434433234333531463233363633364138384523290a2020290a20290a
\\xe2ca252705d6f528cef3513af51d565d689fb8032746d8d2cc1355c3c9265fa1	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233739323037384144364245384141443633454138343930373636383141324245384345424646453138343542363230314542384533453834454441413642383045334146303732323733353730314436394635343536353145383238443239433943353245413437383031353434423742354434413132413930303141423633373142443339383143333445313330353044363544414134333543303737374642423642374145394630354142414546434230433036313732383231373146314531453238373941384439443632353430313735443446423830303734423738394344344545423239364541324539443245353135443438423035383034423123290a2020290a20290a
\\xf2a32ab03c43fa9de118b6df9b623ed27ef65bc5f5b5a8bd5da6f65ea11160e0	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233330333735413837343038414339334343394243354332444337383832323244314532464138393237463843314144323341384334363038353131394332344545344139323945454432463636444344433541303738344237334234354239463042433632344341423841413436444341383531353741463136303544353331314543433235464531334633323930364139334333353335443045394333414646414337304643354138364136463641363832383739413739373241324337364531413937444544313842343533434646463144364531364131414131373033313142463845414343333533413345363930303434354230303330334132363323290a2020290a20290a
\\x1c616967029ef73c02eb8fdf0efa68afef27e1863fe5ae631ae7105bc82c6ab7	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320234141444543453942393445394541453533343032443133423334363941314338443542323836313131334331444241423834463339313134384435364244454235313239453636453042303137324446434133303243304536433644433830453533303345433030303444373839333933334631433639344143443932424245384345434538373645393139374533433438333134394134383935413842424433383737393331304430373030384637433535343832373643373739424146373934464545433744343341343739313541354635384344324644313934343930333435324232433631413139374634303637443039373141343945384639464223290a2020290a20290a
\\x213f2d7d2c57fffbbe8e5122fa86cfaec707684f598f9f495483a4f06f4bc8fb	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233844353443364442333338434135393631313744464436374537433732394145303033364237334338324146414442463930363630383241463932433636384531444343423234433838444535374539463932394637383338364541373545313833424430434639454131303634314238343635353331353643373531423245454443464243363044343244453043354432343746313939334630314244424333454143433032363145334442304543463235344239334346444631313242343737383143333646314637303730304543354446374532453630314433373235464341413533373641393832424439393333384645444536394641414635373823290a2020290a20290a
\\x9efaffef1c5a6134d8383bbc78bd32649335005fb68d411a5504afe4196d4523	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233938363146343046433036393232323245313246353330444636383342464342413832323741373039333942344530334537394631353532444335443845354641413535344437433932324341303935364533363233424336394534424630314130384132313441433632363844343641373544463443423634364538453232343439354239304630443736373835353531424431393930433342384132433744314432303544373935424344363430314136453246374446463635413336383731333837393035303942423630343333464631354141413337363341374238333737333836323137454237333438333543394244324337433942323738313823290a2020290a20290a
\\x8690b22c0765299e985da6dea34db279dc9fbb4843fd9b7d229699bdff4d83bc	\\xef77d29ab4dfebefe7169cb4e5a0834288ce5d50f221e422c0667cdd27b372f4a486566f2d46ff8a8d238744106a2426c000c816030d8379c697f1ec2055c26e	\\x287369672d76616c200a2028727361200a2020287320233143443935333744343139313231343132463130414131454641314432334144344344434241383342343746444345393435463146303538364435383643393944444143323532304439304434303833313042383746373832304143434241314536383735454432413334363737303431363845374546314239364237374244344131383044383842323633414544353430333243444345313343343245374535433535414138413335334443353342353442333632333336314244413946363831394530314644353130374531303530324530454431353331454544463335304538434335374643373444334238393831444534453743443431393134383523290a2020290a20290a
\.


--
-- Data for Name: membership; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.membership (channel_id, slave_id, did_join, announced_at, effective_since, group_generation) FROM stdin;
1	1	1	4	2	1
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid, last_session_id) FROM stdin;
2019.248.11.51.00-03JAPESYYBAHT	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e31312e35312e30302d30334a41504553595942414854222c2274696d657374616d70223a222f446174652831353637363737303630292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373633343630292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454e3558584243313045353154524e3044375a4e313746424356324531454356483433364256384d3546334e414e5646464d5330227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2230304742565056464d5a54344b53433931534a564259444a4d4447585430584344564e3833484b4235585751323943483444563954465856563848504130484a58334552455745425753574a51445847535a574d54513931394850344739473136473958584552222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2254353336415044474731415a3859374a4130363159305053343732574638414d5843325a4d4b5a3453583935483137444e354147222c226e6f6e6365223a225139355751345a335435333334464737445739415848484e46355651454854503957364a464b4e304a4132543831315750523847227d	\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	1567677060000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x62aaab92b4c96c02333e000a4978a0829b50bab61242c26d7341df0dac44a150	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22525a3447455635583551504e364738324d4632304e50595739544541375a47444253314147474b504a373743545759544139543342423547395844483151423536304b514e484b4a514a51504631533153304e354a575a304556415446414348324b4237343138222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x95babf03daef5a45847737ecb99c14d113d50f80f5e8b2f1c94182a401c9a35b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2239385a4b34444d5448584356344654364a5152365051394854323751545048464d5859454e5a54514a3159484b4738485034353247423932524754364e51393031594b4d5a3248395353524639385a385945484a32524a4d584345565334303553453939323038222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\xed23e80ead6cfed100e8892021f8eebc8d79a3a04f6b9af43ecc44af76515477	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224444353733585030314744393648454458564d324859334737385a51415036433642475a354a5243444451345a513650513532385a4847364b4d33575653394b434d4e414641325443304a50594743324430484d3251364148424650484e304342374a37593147222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\xe2ca252705d6f528cef3513af51d565d689fb8032746d8d2cc1355c3c9265fa1	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a223159453736355a3451523744464553434e44364e5341484733444633415632443538324e4d323847375058453335484b59333241584a324b5a56505248334546324a3859514b47424a39424e534638464a504d364344583850594b473844334d4130474e323247222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\xf2a32ab03c43fa9de118b6df9b623ed27ef65bc5f5b5a8bd5da6f65ea11160e0	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2237424d58333239523659325a435438423638433039415259304b544e54453138395a583145335352473147513341535356334a31513259355248473553385051563857453057445a435a3146573036365a334b51504a38465736415652414537474d5847343030222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x1c616967029ef73c02eb8fdf0efa68afef27e1863fe5ae631ae7105bc82c6ab7	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2254384e544830524e44305739433851505a4243333731583135585346475a324a343756573353524745363333364437474d5238325450583256593358363041564133344135423732425a334d5a4a4533383733545135324a5a4d41385059325750565331343247222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x213f2d7d2c57fffbbe8e5122fa86cfaec707684f598f9f495483a4f06f4bc8fb	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a31415a384d4b41563243333259483350504142385a56535142545a373158544156594842525a324350434534514e424b4e384d5152463550304859453631564e42384e4d573354474b4a4e5a5935524d5a593754314e354e57314a59485350564a4a52383152222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x9efaffef1c5a6134d8383bbc78bd32649335005fb68d411a5504afe4196d4523	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2242435133425a30395a454639544b42353556364a593552305a5334314a5938515748533053514d305941434b375839465159594838463846515a44425652354b565a57355030323252304a394d4e374436454e433259334734513237564d444b58454845523147222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\\x07a214a0d70f78bf20c2b70325f7260f70dea6ac0a87a5f270bb19ec364696d89d37b8df236b9c1291a1563dfbacd8d4534614879222e8b4048338d927ecf527	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x8690b22c0765299e985da6dea34db279dc9fbb4843fd9b7d229699bdff4d83bc	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\xd7e8f6308d1e407296aac0084b5c1e83b6f54a302f8be918a9ac36777dc8c51b	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224557355030585632594d4e4a3853525444563152543952443953353234445839443038513552563748583433454e3443453152364b4d4d46474b3942414a4e4b4450434858454d384251385a3358315835333134523758355046435734344139473934364a3052222c22707562223a22545a4d46434334443353303735354e41523034345051305947455646414a4847355935594a3635394e475637455a4538524d4447227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.248.11.51.00-03JAPESYYBAHT	\\xd1466559b08055f478f2500c1f02d921c5c7a154eb05fa4fe4cf525884eda955	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3234382e31312e35312e30302d30334a41504553595942414854222c2274696d657374616d70223a222f446174652831353637363737303630292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353637373633343630292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454e3558584243313045353154524e3044375a4e313746424356324531454356483433364256384d3546334e414e5646464d5330227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2230304742565056464d5a54344b53433931534a564259444a4d4447585430584344564e3833484b4235585751323943483444563954465856563848504130484a58334552455745425753574a51445847535a574d54513931394850344739473136473958584552222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a2254353336415044474731415a3859374a4130363159305053343732574638414d5843325a4d4b5a3453583935483137444e354147227d	1567677060000000
\.


--
-- Data for Name: merchant_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_proofs (exchange_url, wtid, execution_time, signkey_pub, proof) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (rtransaction_id, merchant_pub, h_contract_terms, coin_pub, reason, refund_amount_val, refund_amount_frac, refund_fee_val, refund_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (tip_id, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_credits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_credits (reserve_priv, credit_uuid, "timestamp", amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_priv, expiration, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.messages (channel_id, hop_counter, signature, purpose, fragment_id, fragment_offset, message_id, group_generation, multicast_flags, psycstore_flags, data) FROM stdin;
\.


--
-- Data for Name: payback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback (payback_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: payback_refresh; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payback_refresh (payback_refresh_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, "timestamp", h_blind_ev) FROM stdin;
\.


--
-- Data for Name: prewire; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire (prewire_uuid, type, finished, buf) FROM stdin;
\.


--
-- Data for Name: refresh_commitments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	\\x8690b22c0765299e985da6dea34db279dc9fbb4843fd9b7d229699bdff4d83bc	\\xad308eb7df74e60c5cb07a0afd691996da6e3b4ef7df4641db6e2c1b15eeaadd9fb24957b583be5cea17b00896d130da937a666720a87abf879781b8fff4e506	4	80000000	1
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	0	\\x8dede2863a20ce8cc585729356fca8e9ba1ab9d7098d50af7bffc35facc9b0b70a86cc6297a4d2e19fa7d7c55494f64ca5a114a2ef2493e3d29e1a1cc364e902	\\x3a1c7f90cf5f6e294ed83b176d767625da64db9987285074785fe918d924e0aca97b63c5447c366d05f3f53bdc11078acc399e43879a21d9778959702f603cf6	\\x8b8cf61e0e3cd70ac3384e35cfca154b6689ba6c36e18d30c37125b78c0b5f7af74c63eb0baa9c234aecaf2233d582f13ad73863f4879491c7ed9a7e36406e33e14d75da9950225249daa1ce118efbd45854ddcb330ec798338dd7cd50d9f5af162a7a69adad0810d31968009b5713cc549c90016a37c9f1c171293c7d7cc4db	\\xbbaf6fc757a0fd3a465d0696fef7c982d2d5222c76790ea123b33a22e02905e90e64223b76673541dbcb09edd6805d34a84995568f429e5daa863dc49f5a12f9	\\x287369672d76616c200a2028727361200a2020287320233338323242323637364535314339373131443845434334463631343738344238443835324537384239344346324239413939373937344335304131353543394241384637414537414230324134303230414646463733353432444335383933303930383431443343413937374238383042373144384544334533463338424234444346384434433844323543423831464538443130343244334236424242323039334246413934384634453945414345383244394441374441464638373442363138343431453241444443414437423737464338303835434634323536334644433035343746344533424631354231323731304144333037433035453738464323290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	1	\\x01daddf40e982e2dbbdfd6172d32648af5d85bab3ebf89109026ee65ca6bd8b0f5a4cc5df20f5996cd803b8b576ec458fc7188059f8387717e083015ea562000	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x6f1887283f54dd5254c5d9d2f53cda370fbe87f8dc7181b293c69aba340379f2daeacf1fff1a9f0e7d652927caec242ed3827376c20e30c62d8cc9677ebe21ed00b3229e8db74965f636e1bc8b41084fd555d15777e1f8daff6de05fafe4e6134a1ef10b7549363f016587270d1bbabbc2f38190ec442438ca6b7e8bce47b303	\\xf01d0dc6d2120d9cce4ac1f9604a64bfc34c2add05b94abb5d3c679f720f4b6b7c97f7aa5b083b4e87e6ce8183b4bd0f920af5faf68673248f6baf348f830b25	\\x287369672d76616c200a2028727361200a2020287320234135303931373633464436324346343435303335434636453032453841413539383843313031454635423732303636443930314237423635353738323533463237443237414239444545304542333931373036463832363436444544383337353635343930394232344141393235363038463541463143333231423834433241463032414345363935464532314146303431353735353138393946303338324531453636313830394242304130343231423432323132364446364536433543434435383042444238343938323244393933453642423434353246423141353636334435393841414239423232303536364233313241443631443336353630333523290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	2	\\xf8366db620419910eed607dcbb6d846eafa1543adca29e807011ba9e51ac3438697d344a53458f14510460986561ce03f9aa7189b08a746acf5fbef474d0380e	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\xb08848d5e949d77a7dfa380f86ccdb522e5cb71a63cf9900199e61d25835d471e326543facae324f0a12f2e67a651a76d1c617680a40d11a60320c3af36baf3a5fd8bcdeab946cc9e71678db9c3f6057f37583b0488aa494b06bb78cde344c09314664b26098cc0bf837bf74b010614c60e52fd5f3cfdb018a148297cdf075b4	\\xd72308f621bd7697456d48011a445cc1dc90442f5a4130e053095f1eb92f2fabc659ed831e30a299a69e4825ede3ae8afff1a14bbca7c5dd05d5b7b7800c569e	\\x287369672d76616c200a2028727361200a2020287320233734323431413131344342444441353638413633393837453439314445313835334334423838343339343443413133463442354135303430333444373738444336364637323237424641353943363937383632373830444636314434433734433444323135344445453338463342364644313738303842434433343144423536374535373133313537353631393634413934343038353439333936323644384431303231333344324343374441333236394335314532314539334142313336434239374634304534343938363830433944354230313035463837433943363039443443433943323031463535383244373036354631383933383443344635454623290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	3	\\xebe9769e98546a89080878a49c7802f57c27d98637c9076a877ddc808fdfb532ec2290e4960dd15e16a2077a5ea3ed5676bc1236c1d401f8a614ff497615a807	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x22cb4b3cba2cc4cda91a5fd3f30af50e5022204b03a1ea9226a322ad161c164eb93cfa09c137c0a67682a45ddbee7f43eeadf5c15193832393a6d970e49930290893d1f55761aeba8a0133379ffc40e4ed85b0755302dba695d91cf3efaea359bb0b66434b7edebc15690df2f69af6833362556164d4b8f7d8680f958ac0a955	\\x8440cf2beb795e417e174cbecaf7dbdf7aca10d4663d21d95b39fc98c1a19242e53512865a54816010861c7c2d88987b213582ebb5261f1e1cf5d994d6e5738b	\\x287369672d76616c200a2028727361200a2020287320233932433233303930303038454346463739454330414446454430373342464342333031363843323739344445304330373844394237333939444545433333343441323146373935454331414645304436313242394443333139454232463335304134454239394639414445353846324446453535334245313339303138454241383834333145394244354535443044353936304334333046373144343244443335433531454641434437413645303831454442363945374530314439454239333633394532394337443544424639443538333033333641373446424630433832373939353234344337423535393537333731333642383635413534384144423623290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	4	\\xb8860040911ebb0353d7a31a264ad28d458f0346d512d5875b5dfcbbeb49bc113630fdbd2c086fd0b2e5c05f2fe6cb125d5a13f5e9235bc06862d234fc341f08	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x8fa036a3b6c0f7deeaae4520954234ef4028896c3702470f423dbf68f747232e17fb2494bf73b0b1e40eb00378fc5e97defcc48697f662f00bc6985516f9cb0b79e7e5a8d6332bb3575e11281e87aaf8e342b177eafe82ee2ef23868f07c8106816fe0b21146cd42123d4552643ba54d658c575fdf1f2a257bd6335b3ef78742	\\x3731a5c2d7a3d69c83c107108358e834ed48835e30494f419e1ae5fa52ce38c422fc40ba89f0476248c0751deff6c25599742be66db2aac2da3a471afcf5a960	\\x287369672d76616c200a2028727361200a2020287320233243433941453330394546373844413546343946343233344339353737384331364439414641424237394343374336443246423941444641383041324632453739453431393630324146314343334331383331373439363133323144393432433331343745444433414634464432304230314536443836373143454331393832433432324630303742303041433444324534453845374635323534323445433344434433343633353236433041384638374536453738454144394238324636424141313534394534383246344534393535433746313831433839424541383238393344353542384332393337353736374233444542393932423936304238333823290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	5	\\xc193e5577e1a2c93eab01bac6872f460dcc6f97641d6679c8a585cd232606854f38c6b493d3354978cfc506fd18c08200c8bfd50c9da243e0a6dabd532dd140a	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x8b8c901534715b5dcca977032b0f0a01e58c6dbb4f244b74fa112a5cdf8ce0bfd2784c463fdc08821b1c1c6f287c74183c19148517eb75d65fee309288cf411df98e8696cf4b2b264fe09445f29fd05749613fc024ecbabad5254f96b5553ed030d0a43745b7055ffd1599b81fed07c2004f99d30da994b017438a85a022c77a	\\xf0153f6ef9759a6b3e816e79e68df07937c3a32a3bccb80eed3947f02a579901350709fcdb48050f54437a9eb918d13d0145a2d5d0c13d5bddfce8d2bf500735	\\x287369672d76616c200a2028727361200a2020287320233738314336453946464546373743413031443036344641433030463139464345393635374637373933424132413743393730393233303546333846433935334434343831463246363733353132444144383431413941383345443141413631384343423930434544363234393536393235413943324241303837304534443138433036433441363942464342414246393736334234444137453731333737394433333131343034444330393941383446343841383038423335323431394333324436463035414645343844383141444545453939333532304237394242354244423531393445463135444536303137423731334533463234444338433439464123290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	6	\\xbc52a598748670aee1bb8e282c9b520ff1417137189d3b3efebf0c939751e2effd4d7ff82ea9af449bc678c4f62a616a247edd0ee448abaa4b23f1f0058c2a0e	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x2a7676aaf949aa3240efc4e253322e2efe0c5c8a03f1e321c5b82b369c810b36f9ca8773f7ccbfb98e5982e169a96579f9117b8f68d29b2bb3988f880190ff87169449b1bcb99ad391e9e2244f222324f33ef6b5b318f3ea489c18f415c506f11cb0c928d9060ade0614c58afcc76b4cfd75cf5a78fb4e67708d6547e86fcec0	\\x078c9b9b62757925ffc40226c6fded3006405a91c1ed204f681115d63745ab6d57a86e271ca4ed8250c7d84dd11023f6cc0c6a5a576c69f1d2d6638c0344c821	\\x287369672d76616c200a2028727361200a2020287320233441424434454241324233433433464430423134444542354131423343313831323438453242434234353043413731394534423943303033313636423933334533464143373944443545383439374231393041344146364131373844423037454139393246423339323836344344354444433039414634333638444137454431364639443135323430363641463137313233413530413731444432303035304142324143354531463443454138413433333236423134453336454142433033413131454430423744304638463537443232413337343036444532324538313846424535343142433139354139354242323831303934324546304130433537423623290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	7	\\x2f3c709060bc0633599dd352de9d4fbd2add65f1c30cb86c25b373737248966281dfe9ab22c20670a2079a9f51b1c8533244ce14ed62df49b2473c99bce64d08	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x42144b055a396d1cba2771a132239126f479b021f6aaedcd7c4bb6fbad475d4cee1b0328b996fa59e009d8ab38e120ec8122ebe5f8aa0bf2c2b9d006c1a0f130555f6dc04388a6e5dc36068adbc6ebf03484cd729ec6a60271f592372a3dc7f25ab512f5c2cc5157fd6420eee2f9027efaa51492b8afbc1a52fc00dfe25e0ddc	\\x4cd817973e6f05f64528d1814b753cad4efa6d53b80f207b1716f5f35149a3d172b378b6733d4e50ad5407de52aa2e3d615e6e4fc56d9e9c0dabcfcf175b91a4	\\x287369672d76616c200a2028727361200a2020287320233636353733344245303544463834344130343145464539314236414634343941453143334244304438423042334139414244383644333337353345323439413637303735374338394631393942444641423133353445424138353535413138373838384435353430433339363842304439314431434145324144444542413742314232413845383033363243383634393745344336323046364642334243414346444541393934373545414136313532323843463334333335383639333031343146373143343642383245434131353046323731324342344138333944364435394537413634413432313031383633383532423439313430453046443339463923290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	8	\\x670c189e633de14eafbe256eb6ab946373b75e2d7fc9875a16633996417b5faf4bb2b2d2ae32c58632706892ed34eb4b7aeb07e37c7bebcb6609556ffeee2801	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x103458ce7e2d3a31433dda75f9e45179a2ab4a54cb28228933fc923ec159f39871fb54580a0f2c60fc4a5fc8f3197c5e9c41710bdf3f76a716ec5f6219d1e44a6c7512944e1eccbc49d351f2915bd678110a413ea3161594964a7f8b66ca36e6aa0ae20397ddf5c788d41869878ce48b94b292e9e50ddc95b6d3ac3e91cad80e	\\xf0ce011ffe261cc9def1a7ae6963f843d2648eeda202441b3532e648b73855a91d43c3f4a1c7973dc956db190101869b56fcf80a3e07755875b4f4536bee0e0b	\\x287369672d76616c200a2028727361200a2020287320233241414236453636343343364642424644363335433434423833354339313339353630363939413844433932443137313135343938393643463032463335443845384346434234443138313530384635323631334337333130374541334131323332343043444333363946433731373343313246373241373844463846444432463635353838394144313942373546384439334444344245363246464444354235363732364135303141424334374230463632353333424433453046454336354236344445304641353437423330333236413736333546414231373039314333343030364339373846374435333738314644423433384135333841384337444123290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	9	\\x6affa924746aa01cba5b8d864dd466d19c1a8c1e3b4715eb64d700c76e50208d0307de601efab475bf1a3d73197d7ba810fad6c54637e8fe1b0d69b59cdb4a0f	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x022601355a042069abd535b595cff54b345879596e6da80ef6719a3e306f73b556d9f6f4754e614f07cd2325f0806d019dde2817fe0ab31346c1efbc5bcd343e555918f7c7462a374e0bc98d509cc9c53711899482d84afd6633442afba85f2380f2a3c5965fc536a77cd9b0504b03b4ee399af71b07503df1e0c8be0c2dcbc0	\\x0d628eae95dda808064bb3f09e62677f072e5a9265834f1ff5b2effd26d646df7f1bce61d4d69e7c08664479f382b0f7786c0463d1353fef14994424a7d35938	\\x287369672d76616c200a2028727361200a2020287320233533354344344631453741373237454535413345393234323332334141353832343239463937343337453736424643333946354541453735383538373844333031463638453744324431383836343331353137394241314537323636424134313145373033333346393436423030383330443644424634443335343730374139304642324631353334434639463835343139303041434241373238343537333230323839324646414135424436393935453137443839353338383045393843304641373742433339343836444136324441333838454439383644303537434542383237374145374243363639433130393730424235433346324539464541333823290a2020290a20290a
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	10	\\xe48bbeb0ab5e0809a3ff0d527cf66327300a409159f4641b290eb3169f94cc86c7283ba374a6834947a70b25b6fffe6bc5e176367b530c94031c0488e229490c	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\xa981fa2eaae521393560bf6a54026168dd44883a4c3852b103c9e4ced33bfd50766a1cad163d9e16874e7544fb2c27965e8eca5e6409707b93b720e3f3e709c4a7ceea224a53451d8902c3f907259ed53d630e0f59f509e17ed6d195fdac8b4c3cd7ec5c0f4210fe10a1e98d2e5cadbd16417e490bb64a0edfac374271e48252	\\x145b9eb3c442c5628f8f6519082e7f9e7f751833cd24c7f93de8d2e2a1eee63df6daf7145a279ed2ceb6c689dfeb4fa0870cfa52722b8e2015be72a510760f0f	\\x287369672d76616c200a2028727361200a2020287320233731433245313337423139303636354137304245424130314142363630323131383539413039364131353532353446423441354233313843343434433834383237454146464132363638313337414538444532353643464239383343453642363142303831453639374334394434463643333633464333383435353041324242384435363244363232433436423438433633313945414442333134423543303046414531433036374334353341463332394531424135444335444141353539373843433245383045384645333633414535383934394445353535454537424244464246303942423243433834444141423733443033333731373130363238443323290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x48d2b3c536cb32332d50e902173dba6b3ad582c5720256c6bf6ae76c36468f454b69e276209c61020492eb253a9f14f7bc8c1414322257cabce8e4bb66f14d9b	\\xd7963935979b9fb307db6e46536b4ddd787e0ac580b99fb4e0d799086415950b	\\x5896bc6edf73fb01a056dc5b8e30eeabfbeb7ddf264d8f6a746275c966241921a135c5376f9e1d788be96fff6b5ba9b08c12d94463bbc8f8cf73527b7be9eded
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (refund_serial_id, coin_pub, merchant_pub, merchant_sig, h_contract_terms, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves (reserve_pub, account_details, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	payto://x-taler-bank/localhost:8082/9	0	1000000	1570096257000000	1788429060000000
\.


--
-- Data for Name: reserves_close; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close (close_uuid, reserve_pub, execution_date, wtid, receiver_account, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_in; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, sender_account_details, exchange_account_section, execution_date) FROM stdin;
1	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x0000000000000003	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1567677057000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x94516dbca31ed956e0c70869cde96e270f46ea05c899db9080f643ee30d114de8b25849bace8c5f7869fc0e3afeb3d30957ca7df86c74b09014e04f31ca45f4c	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233338363532363530343631304336334435354543384430333743414441433239393034444645323536433645434244454246463133354539443532454346394145463630433337303432354231324245413836334237323733343943303634384538333743454634413339444133444638453032413530433036353345333134444345363735363136374331463236444330353243413534324644413836374635463734303635304241424141463635374333323941424539453745383834413737453446423539383431364141444142423931383046444543413144313238453044424434383944413633354544314344393144383038413944334541453223290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\xc3f3ed7f6b43fda9ae2f080459b8205a2a5927c6ddbe64b21ac271cb418bcb867b146c517adf4ec621136999f8b740c9539bb627726db5988124b49d4543d102	1567677059000000	0	11000000
2	\\x4b50854ad13cf58ddca86bfbc58ace16c71f2817c024fde670dc748f9852e723a8bdd380d5e2c0468ea2417ec343c055ac14b447baf073fe41ea7e81ce6a58e9	\\xe79b866e1793c50f1af8d0178701cc0b92fb636d0ae2c5ed7206b9263aa6d439841b3485e9dda3c510a8ba0b191389949a105544c8159e5ee555ffb5280ee76b	\\x287369672d76616c200a2028727361200a2020287320233044384146373030414143433036374537374142373033394636423232434245304130303642363442323237413944344442303238383243353736424439394537393536443732423442414233323939323136464530363145433036413739353730333837414345424343424639333843344131414439394439393533384345464542354531323546423543444435393730424134374636363339354139423737443038354330383232354339393846463830413236324639344236323733373838324436353043303034383044303245363441373835423537304341324238453731414232453239414141413246313330383042453134424131333934443323290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x1bdf80b227bd7f84c3528210c904d3d178aabeef4ff5bf40503bf648275f774d6289196db92b6baaa2272d55c033cd656558e2518fba5a47532e432d71e71302	1567677059000000	1	2000000
3	\\xc6a9f427de898d525d532a984e2c89bf58d84bc0af13ee004f694ec9ef1a22a3c0fef08d94483aae5f6a2175fa0b307813e8b88fbba665c911cabb2b0b2c1227	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233742383741453936313041454637414330314645423638383732383638343038333844444132383142444638353734414330314237364637303641434634413544344633453732384232454431423438314536463234454635353143343244464243343541343634423045323337354636324431453643333546443733313842323930363134463835433039374333423533413736344436464643453746423834364134354331333232424532353431303836464545323733344131454630413746343341444245363031394333354336393534324238453145454646434145433231423939464642313839383333373539463235304246433231383833334223290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x3f1612a4664f7ff4bc921d7257c2bcd00a41e4c8db418d18699f106e706436dd2eb748cef99cb5129eabf96c0b1d5336c7436e6a7b79f130c1143d407eb3b903	1567677059000000	0	11000000
4	\\x56ea72798c4a0b5c6eff82360f05a6c948b1f99ec31e7564b6bb2f1cc6f85d0d3d222c65f26159b98f0737ebc879118550c5222ea215eafb5562286d58c39635	\\xef77d29ab4dfebefe7169cb4e5a0834288ce5d50f221e422c0667cdd27b372f4a486566f2d46ff8a8d238744106a2426c000c816030d8379c697f1ec2055c26e	\\x287369672d76616c200a2028727361200a2020287320233233453035433438334243393032383141323734353538463239373632433032413431354238383339303339453232394231393531444241393532464639374642333535384441323933333643323642424237463638374544333845313944353043394432393742383644363038454630383032464143433737314430444641334337303241354643464146453637394446333746423535343037333942323933313544453534384444354644323632383142393945413844373145304643333436343144344637354532363132304141344433354544354636344642313238393832343144423346453035334234323744444131413942333231464144374323290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\xde84b12183d2d9e617e70a488e0840a7c9ea6e4c172850ad0cb6a37a749336816e345e60b4c2b23bba10c0ce64bd917773be9449ad88a37e2355d26098f0ac0f	1567677059000000	8	5000000
5	\\x4ea5f737ef5ab3da29724650c18427272db1c03cca200705a7ec01100e4fdd4370c7c395741b79bc8c4be9764f3573fa6e02c815b845643486e54422293148c1	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233131423732364533374636464544443045394636314130374346354334443042424632454630364133383832433837414433453532354242443636314343333734314538313936374441413237323046343339343042323643313032354338333545363431423030463431303837443746463844414333424244463835344236443336393234313243353243323439453732343433443332313337423739393841383744303036353131363444394231363046354442343030443044344537433031393636383136364645373836363935453333363446464441413738373138303141354141373338323245363139433837344630304342413533303745334323290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\xa2730bc4e6e5f4529caec2326130cdde8c83678c61033cdbb8dba251001384d16a8a9041ac5e9c7c647af6f182919863fc6393e8bac9a3368385e8536de92b02	1567677059000000	0	11000000
6	\\xf76bc733ea32fe65209ee7ccf359bde51f3698101ae3a95d9292b0cb5c7f09d91b46efb661a7c236978376f3cb25a3a3097519be75f3a354a7be18baa5d1bd19	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233642303332344432323145323135454636383746423930414531343242353234413645353135393644333232313044343432363631344533374144413045423431424133303244463444393441383241343742363042413843314138464638393132313846464645433143444439353546383336383634413846353139314245393738463731414431413945443434423438304345324336333030454443343443433043343138414533383446444237333546303632313634393837433931333631413235453436324638413633384430373138463330453431443936373037424543463434383933324346384332323032343643423334313938343531314423290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\xda1a877d90fb19aa584687dfc786280d1f4b39f218cb4989387f69cf6b1bd907436523e4b6e14443814b08dce578d325dbcf4870ca6cc60e1f2638298849a107	1567677059000000	0	11000000
7	\\xb696029b7005313db3c2ce650e0c0d9c669f48021420bea0741deb08d48ff5ff3f450e979a5bc988c8cc9ee984a9a3724b19f3826edad521fff223eec06e0671	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320234145353635353032383638334246453838353030364434393334383233363038363645323042434435324242453037433838303936423941364633334146443335443143393042303237384332314139463533363330303838413534343635323942323632313638313636394535413243423535394434464543413638443035413835383642434542364234344139443435463030353532453433304332343235354337324244464533373846353433464437413343413837463936464433443338393445304430423143434346434531434631334530373539453146393231384535373841374146414244433346394345323937333238324536424543313323290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x49b64cc18c49531f14c428299fa352145ae9f7a86736dc6f25178e7cd3fb4e2830738a760abe21482b14a2ebf5f7f074c98d73441a7a4ad4aec57786a540a80d	1567677059000000	0	11000000
8	\\xbed7965d3e38ca81325087080f8bd75603256ed98d38b938583945d999181e87ff726768d6128dfff40712c578f4682dda859d83ee161a5b331b4bb74a5d9a97	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233137394343323038303635303338333342353736423338333930434235383035443642304332303237374634383535304530364243464544454233434330464343414141374637423245343343423230364145394235464446363438384446393145413234393142443145364543343746363731313030443337343446333434353245363533433532364333363242393230384437313546424137353046464634363132453631324435424230444132303139333336384330424332433633434346344635394330314230383036433831333537453637313841303832364333394235443443423835444646433337353033383243394446323031363930393723290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x8c000594bee224bc13e71627e52fadce3ace975fe88161da7967308ab2874920613d31b6df877b30da33e78fa5e07f5b9dbd2cea2d2e3b0a598672e075f03a04	1567677059000000	0	11000000
9	\\x765300cf503bdec477a5716d06e61327becd0dad2dfb70e22ebfe2be48196255d0ba8a7b0c7ebfc1bbbc6e6d79d49d56e06922382246aa3720ab2aac956384ef	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x287369672d76616c200a2028727361200a2020287320233038393534303737313543423241363433323442373238323833414138333832463743384146384437354538364441313237424435433041303734463942433746423742423744353846373231304132383236463638343130303543454146453536423341364336393335313235443836313039454632304231353739323839363138393234383636324139353946384630364433323939313033453034384645353843433243424637444338353746324143383144323546344641433443463445363536393943323441353132304443324530353832353934374635454136313244324142333933304244423535454237393942463445464635393346393323290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x49ce2d98d54a0b80a36111a13d8d65e27b971c55ed574dfc6367b9b3900e3bd7a96d356fcc07b323c66f0c1e8071a29f5dba1054f886032bb628271051e9cc07	1567677060000000	0	2000000
10	\\xffd61a2a9ce0a6c2ab4747015479dcf5e26b6f2d731cf7fdd7e4835730ba78fa9dafa7c3602214f1561dfb3e5a6b99fde6e37d4043300155f93ce6af5c922471	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233934453836344130394442423141314146373542363445443636453345443732454136313843423136314246333941333838334537464532373143353641374133384646383946453641413846373337433130353545314443373442323130304336453535454542414645324336414539464633333033384542433830463244464536313137423032303343423933304646423042394631314432383835383138434230413944434445464630464535463630333545334643364437334139314233454530334445343244444438303337463546434336353538383733433432333136433736323732303534393832373834384438433045373933394635453923290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x9c8cb82c987a87cb99acc2800654d99680e09054a85f6a956ee0b9d2251559b915ebe686eb28dcc50217e02a825419980134942308da38733dfafe78b42f3e06	1567677060000000	0	11000000
11	\\xdc2c24b73dea9d575673405f9abc458c13d8b3d2d3b7a3a4e5e548d6aff407d4e307225298999dd66582936be54b884b158a63940dbc27e4ba65edba33b20833	\\xedfba07f2fccbd5b46ac590d66ed1e5a6a3079a7463999f5f34155b9f4f2dd02d274e339101599bb0e325eed18401f2ecce767f647b6f53975ef08d660780fd7	\\x287369672d76616c200a2028727361200a2020287320233430344339414137433533393236443333324236443238414141463434453242444544433736344541383530343330453134313742433634344642393031414145314542383343424439393443383346413443353936363941423545303830423442463638343546433337334532444241374546433339344345313544373643353538303146453341343331324131323838413044394442343537334235443739364537363145343041384543453637414330393932333438464442353342443739393230443945373143413435464136333041453231464236393734343430363934413435314343303637314143463744443546334133364530423931303023290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\x0566d7f960b2bc686f1b762234a0e940960c9f3011c1d9c00c61e2ecf13e8b5516f7df5e2ad1d50f483a9ea39fa30b70d597a8aefaf64c78815a8e45d243e70a	1567677060000000	0	2000000
12	\\xfec3bfc0116a4030050ce5530b9703c727451a6bea6c761d54f2786ebd02aa26a3dcc7b94e035b40b332065f074348513e0e4c3190e60a7380fa15363c5fa5f2	\\x8c66acfd0b2d16a63f7d1df0eab57f4753d58f0d840548f4a0cbab5b35c9a229316ffed12388d7b2a3373bb09db15e7a51ed37f5a1affe3e7ac7d82988ef07c7	\\x287369672d76616c200a2028727361200a2020287320233133383630313038363633303241424231353830304436463330413430434538384439344445464434333841453839393243463035363745454639383543343446323437413432363938413534413843464643303946314538364138453146313545464234383238443231303433423132413835464245343637313635423533343744354131353937433938313042393435383344304535453043303541373136354232333041343446463245453131413233314237453635353443324333323742423934353135333830433446384233424537334638453934424346433645343642313643414136433938304631323542464143393930464238384241413723290a2020290a20290a	\\x9b0e70e8c116d09930fdbcb9c0f8a0816f873da7ac0f45fd8590cdc008cbe80e	\\xd9ca5d9035247b72261f55833dba7bfcf880a250df868954f4d63aacc1bfefdfd5110d7ba14fdb909ccaf5480e1d95b257308f74bce304215485ffc7c1de370b	1567677060000000	0	11000000
\.


--
-- Data for Name: slaves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.slaves (id, pub_key) FROM stdin;
1	\\xab65d6c0ddaa77d3b1d90d83fcdf86918da7339c92fb502fc718e39bbb7c873d
\.


--
-- Data for Name: state; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.state (channel_id, name, value_current, value_signed) FROM stdin;
\.


--
-- Data for Name: state_sync; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.state_sync (channel_id, name, value) FROM stdin;
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_progress (master_pub, last_timestamp) FROM stdin;
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_fee (wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
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

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 9, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 3, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 9, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: channels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.channels_id_seq', 1, true);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 1, false);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 9, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 15, true);


--
-- Name: merchant_contract_terms_row_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_contract_terms_row_id_seq', 1, true);


--
-- Name: merchant_refunds_rtransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_rtransaction_id_seq', 1, false);


--
-- Name: payback_payback_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_payback_uuid_seq', 1, false);


--
-- Name: payback_refresh_payback_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payback_refresh_payback_refresh_uuid_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 1, true);


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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 12, true);


--
-- Name: slaves_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.slaves_id_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


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
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_denominations auditor_denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
    ADD CONSTRAINT auditor_denominations_pkey PRIMARY KEY (denom_pub_hash);


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
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


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
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


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
-- Name: exchange_wire_fees exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_wire_fees
    ADD CONSTRAINT exchange_wire_fees_pkey PRIMARY KEY (exchange_pub, h_wire_method, start_date, end_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_h_contract_terms_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_h_contract_terms_merchant_pub_key UNIQUE (h_contract_terms, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_contract_terms merchant_contract_terms_row_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_row_id_key UNIQUE (row_id);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_id, merchant_pub);


--
-- Name: merchant_proofs merchant_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_proofs
    ADD CONSTRAINT merchant_proofs_pkey PRIMARY KEY (wtid, exchange_url);


--
-- Name: merchant_refunds merchant_refunds_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_rtransaction_id_key UNIQUE (rtransaction_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_id);


--
-- Name: merchant_tip_reserve_credits merchant_tip_reserve_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_credits
    ADD CONSTRAINT merchant_tip_reserve_credits_pkey PRIMARY KEY (credit_uuid);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_priv);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_id);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (h_contract_terms, coin_pub);


--
-- Name: messages messages_channel_id_message_id_fragment_offset_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_message_id_fragment_offset_key UNIQUE (channel_id, message_id, fragment_offset);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (channel_id, fragment_id);


--
-- Name: payback payback_payback_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_payback_uuid_key UNIQUE (payback_uuid);


--
-- Name: payback_refresh payback_refresh_payback_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_payback_refresh_uuid_key UNIQUE (payback_refresh_uuid);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


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
    ADD CONSTRAINT refresh_revealed_coins_pkey PRIMARY KEY (rc, newcoin_index);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (rc);


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
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub, wire_reference);


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
-- Name: slaves slaves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slaves
    ADD CONSTRAINT slaves_pkey PRIMARY KEY (id);


--
-- Name: state state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_pkey PRIMARY KEY (channel_id, name);


--
-- Name: state_sync state_sync_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_pkey PRIMARY KEY (channel_id, name);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


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
-- Name: channel_pub_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX channel_pub_key_idx ON public.channels USING btree (pub_key);


--
-- Name: denominations_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_coin_pub_merchant_contract_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_coin_pub_merchant_contract_index ON public.deposits USING btree (coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_get_ready_index ON public.deposits USING btree (tiny, done, wire_deadline, refund_deadline);


--
-- Name: deposits_iterate_matching; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_iterate_matching ON public.deposits USING btree (merchant_pub, h_wire, done, wire_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: history_ledger_by_master_pub_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX history_ledger_by_master_pub_and_time ON public.auditor_historic_ledger USING btree (master_pub, "timestamp");


--
-- Name: idx_membership_channel_id_slave_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_channel_id_slave_id ON public.membership USING btree (channel_id, slave_id);


--
-- Name: known_coins_by_denomination; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_denomination ON public.known_coins USING btree (denom_pub_hash);


--
-- Name: merchant_transfers_by_coin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_coin ON public.merchant_transfers USING btree (h_contract_terms, coin_pub);


--
-- Name: merchant_transfers_by_wtid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_wtid ON public.merchant_transfers USING btree (wtid);


--
-- Name: payback_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_coin_index ON public.payback USING btree (coin_pub);


--
-- Name: payback_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_by_h_blind_ev ON public.payback USING btree (h_blind_ev);


--
-- Name: payback_refresh_by_coin_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_coin_index ON public.payback_refresh USING btree (coin_pub);


--
-- Name: payback_refresh_by_h_blind_ev; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payback_refresh_by_h_blind_ev ON public.payback_refresh USING btree (h_blind_ev);


--
-- Name: prepare_iteration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prepare_iteration_index ON public.prewire USING btree (finished);


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
-- Name: refunds_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_coin_pub_index ON public.refunds USING btree (coin_pub);


--
-- Name: reserves_close_by_reserve; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_reserve ON public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_expiration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_expiration_index ON public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_gc_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_gc_index ON public.reserves USING btree (gc_date);


--
-- Name: reserves_in_exchange_account_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_exchange_account_serial ON public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_execution_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_execution_index ON public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_reserve_pub ON public.reserves_in USING btree (reserve_pub);


--
-- Name: reserves_out_execution_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_execution_date ON public.reserves_out USING btree (execution_date);


--
-- Name: reserves_out_for_get_withdraw_info; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_for_get_withdraw_info ON public.reserves_out USING btree (denom_pub_hash, h_blind_ev);


--
-- Name: reserves_out_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_reserve_pub_index ON public.reserves_out USING btree (reserve_pub);


--
-- Name: reserves_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_reserve_pub_index ON public.reserves USING btree (reserve_pub);


--
-- Name: slaves_pub_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX slaves_pub_key_idx ON public.slaves USING btree (pub_key);


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
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


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
-- Name: auditor_denominations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denominations
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
-- Name: auditor_historic_ledger master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_ledger
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: membership membership_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: membership membership_slave_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_slave_id_fkey FOREIGN KEY (slave_id) REFERENCES public.slaves(id);


--
-- Name: merchant_deposits merchant_deposits_h_contract_terms_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_h_contract_terms_fkey FOREIGN KEY (h_contract_terms, merchant_pub) REFERENCES public.merchant_contract_terms(h_contract_terms, merchant_pub);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_id_fkey FOREIGN KEY (tip_id) REFERENCES public.merchant_tips(tip_id) ON DELETE CASCADE;


--
-- Name: messages messages_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: payback payback_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback payback_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback
    ADD CONSTRAINT payback_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.reserves_out(h_blind_ev) ON DELETE CASCADE;


--
-- Name: payback_refresh payback_refresh_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_coin_pub_fkey FOREIGN KEY (coin_pub) REFERENCES public.known_coins(coin_pub);


--
-- Name: payback_refresh payback_refresh_h_blind_ev_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payback_refresh
    ADD CONSTRAINT payback_refresh_h_blind_ev_fkey FOREIGN KEY (h_blind_ev) REFERENCES public.refresh_revealed_coins(h_coin_ev) ON DELETE CASCADE;


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
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.denominations(denom_pub_hash);


--
-- Name: reserves_out reserves_out_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: state state_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: state_sync state_sync_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.state_sync
    ADD CONSTRAINT state_sync_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

