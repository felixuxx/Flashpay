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
    origin_account text,
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
-- Name: merchant_session_info; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_session_info (
    session_id character varying NOT NULL,
    fulfillment_url character varying NOT NULL,
    order_id character varying NOT NULL,
    merchant_pub bytea NOT NULL,
    "timestamp" bigint NOT NULL,
    CONSTRAINT merchant_session_info_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


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
    extra bytea NOT NULL,
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
t	f	8	TESTKUDOS:0.00	8
t	t	1	TESTKUDOS:100.00	1
f	f	9	TESTKUDOS:90.00	9
t	f	2	TESTKUDOS:10.00	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100.00	Joining bonus	2019-10-26 21:44:28.633243+02	f	9	1
2	TESTKUDOS:10.00	EA9EYDN1S8309C5VRJ006NQQ8QM7HXT1TA7ZXQ87Y7W3J5Q5CM3G	2019-10-26 21:44:28.717929+02	f	2	9
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
\\x5a330c271f866f39a3197a6e4ba58b6487dedf8eff0f8af41fbe245283e5c1c6c1253ed302ce5332316b8396abeb73f0f6e910e273431625de7f3c2c5faa230e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91f4c2d462bf28f505af9b2b9948f6f9c72f3fe3521a955f73cadc5e1ec0a41b3f360eed2fb3845ee61fa6a0d18a26825675c0f1f058ba26c0bee45b85fea614	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf17bfedd5b09e538a7cef03016842dfdd10f35d1813fccb22f41de4837e371c6da1d478d2c668f4511a3c426ef78c8179cab1ea26a63c8de705ea7e51628d40a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa6d69c92fc1291f62f1c510ab4c0158df0566354e341b0aaa41d38861d546fff2cdc8a57fdd7ac4ee2c69e8a4201e096595fc1b60a252b87e091cd5a800e9dc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eb022d19a1e9580b77dc79ae18592c2f26a457bdeecc3a0a34d5adc438660caa6de0a4241706901ed349e9204cc5b8349b296888cfcd4305e0a2011bd630c47	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdb2cba7f170866bb8fa092719e8e60b6035943c9175153c7c0f0066bcf8066d57094045361bf0fc3bc8b96f2322b27d10ce3b8b98b7ca29f9ecb97c6d520c0f3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2dffaeeae09b1c15f9176328032ac1cd3b1d3e338b3bc7788b0dad024160d21ded444065c555ad16d6c0c2dc870705297cb3a77bcc8dcfb5d8be48c8d65ba40f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43318f45e39fb3393b286f7643d04b30dcef2ec172ea28f39ffc4ab4890492cc2e8185ea30b01a39e1da79b9d7efd65b4b202318e836c89dc8416b48fa08ca87	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8564c3dc10995b2e867a60dfc537a17aa9774bcf2ac4edd4b0f51d1ab675bf2fb6c4a985d1662715f56d90ab1a0bf07a103bb299d4275129e523bb11458d346	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x82afc64f63b681439d16a19b98d4d7c98c99f02222c67de5e2adf357e735bd634bf7f6224389f11c9e5b648a006fc06b9b32277e596f361a33f719b140194604	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5fb6ef7d6e09825abe55c48cfb73083c6c560c801a5e343874444d84a045add93eb4e349d5d79321716ccb69d77812e954a8a76998b3287fb974c86e422cbdea	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x86b22f33adbc971fc1d5c51512680cd6f23a25ebea835e4780ffd7bc4b8931c76e2b08cf602bb5df1c60e223a544ac7bc2075e90aeeebac0c9b55112b559335b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6bd030b68b5759d650e8eaf6f2fe7f73e4683522e0817dafdae853ed7fd35c493962d37d85cf61dd5870f75ae041b941446c115f9abb32107603d756463264cc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x43f85f3576d3cc8e57bb266875e559ea0715d1a32f6534da0c8a49a08776aee373018e06053edc72718e874103e8ec0bc167f040553b3bf3ad246f11df082676	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98cf8b24f11036291ea211e6e4c5c51c2b8641fe9cb81a938825a62e3a524713cce4b7beffdb461c09510b8c094bcfc95eb40512e9c9aee3123990be642fa462	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x55627534f805b77bcf5d7a8bfd9cabceec2e0cc9f3aed07699f3bd2ecf1d11be74d68bef966a1b744c060c80d9201b3eb12f0efb0737a3947ef848f693d6746d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x66e4d2194d2af5314c61e489445ae0e9afcaf8c88c41de072dc47a1f3fcb5e0019012e9d97e5eae84ad568ce5049549fd9c61b72de6a4920d5d7adc2cc935858	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x068c0dc67e157c58556a55d85fe942e95196073e7b8359e16fe9c91414f1092d6e149527290beb3b57e43b7f716d6ca99228873976d5b05ce2afb215cf8ad67e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d909de4293b8dee9b63f71ba05f9c8c432269906a5fa229ea6b6e49fb3fc7df1b2bd7471273289658263b95399a3132a1e346e674231339e09dcfdaeb82357f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9eea143ed7cccc5c01542a1b05c6e13273b4c521e53f9698ec54c84df5c10ea37db20540d778f4981c35196f2e8627cbc5b3064256789fb1399b67889bec947	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7ffb6ede898b806d966072059cd2b2117b3f31b4329afae0f95b9fd0ab5ae17108097b844574024e44defee6d22df16dd3dc0bf68b8788a3c8a0f9750e6accf6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb3aa1dd80dd510a481c95de358a556a51be5bb7fddcde8a1ad1fc16bb27cdc5939cbd1789bddf23929d101cc50f876c65417b44c8564a7c267762c903be0f651	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x08ada1dde527af65789a502140a49ec2c1e735dbc6b86e71ddc6f37439dfc24a1128e06280f43df8a3f140441c1b556d31b5a574cae216cb49a6cde219b1f152	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4aef0d786a25945af4bfa5225a80fd4f47f62e558038e08104d5e7ad04e6102a4aef1b17377e4cc2ab25d4e972ec093846a713d0926c33e70b61544e00b0373f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc0b42ad0d1f2ce8c949fe4e1aa0e62ee900e4f1651a97c6514ea88129fffa1ff65f29e29d710ac19289011eeb3871daa57f59909899b2394e1427c8ca73fadfe	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xca8baef0de150d59d6351c688a38aad29d429cc37ab5040a141a9087b38eaa627332b2d7279b3678607954d8dacb7865796a30b7f5248360a054cd36171e2330	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xacefb828529c9ba9a91e592f38b371bd739a433926e246e9d8eb8e677633237ca6f88118cd25867fcd0549c10e59207cca8a4f0efab1326538cd119f236f9209	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xecfac32c9968646b806c726bf8f98d55c4ce9642116d148a7f6362f2fc967e7f91dc3df1a50cc862e05172751c738dbfd96906f2d42a6a253117224183395257	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a52693bd645624ad9d1f30ccf35e75be529fb320a41d3e5459f0ab42d49ef6c8905d6148ff3c5e1ad3bbed38123866580c09e27f7593a84a90d37612002d7e8	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd89881838598cab37b386b9764a2aaba1f9faa852f143ae36940cab3554b9d348eb5e55c19b3f14afa141086c02cb7f37c0d15f742bdcfe9535d98ad336063a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x443444267481f7569ea72deb53da1414b7b50af38034ff188325f3feeff0cbbe1799254cab6ca07246c586613c5adb31bf59b1b52a61f0bedc8d59c3077449c6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa745bd0fc0747710ebbd86c06697b2112d5ba835446750aa99ae3e1646e2703b7aa4bb26f1717d6a178ffcadf14d24441d0df0b39d7a50ea745de7163cc4e40c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4623ae26e46d7949ac19e41e17e6df9995779db07adf90a1c82eb3d64090396afc7130e063b7e09cf6eaf036eefa29f5ad4575f9e58156721bfb2f9120cd21d1	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec22e28f762e7f9d178463318cc4c00bd2c524e0adbdca3de845d2ddebbafaeb4fffdcaeac4b8cf1de4f43b107c7406c3baaaaa5e188ad4fb197d7fc3d3e0cd4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7432ac9e7af30e7e4c1367c3ed9077964f76f2123fdb3cf1bc066a9a33dc4580ffda9fc4b259539d176b7728574ea8d2c049fae22d2cdcc8b1cfb82c5361983	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff1fa8acb23225a0807036c20183674ffeea4b996ec5458d37bddafb757af9a26770db5db474b0999323c34895ef53930cf31dfdcd76c8579324ec4f02cb622a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb8d5cf1dcbee560e28770126845e82e688e3306fd1a7dbd7e203543789aadc82ebabfaa7714c074f23f7b05ae1895a804265692672b39220b823936e602631d3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe739cd6b89d5509224e08a669301ff07451d0b932a366f79423244e546b6c6ad82de24c029f4e13b7369f5c6dd5983bea260d2f26332e71c26bcc6da43db872b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x822343ea592f3f6ba1f3084a54446a66940077395ec5fe590a2a300d62869b83411c66d0eca2147edfd27ebde55a8d7053e973c72823c7e0eaddc418cb0e728b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa64de3d7765eab86593d2c5a0b49bdc92766de3988697cb58238a4b45f30bdfaad27927470b597355d12b9c191ec26ce6f646f60b0a81e36fa8c9adf6b8be90c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6129095b42d3889677c5780355f7167d9f7bc5f9de80a19f2fba896859922db7e927ff3a34fdda39e0d7fcaab18083e4132ee82ea29bd47a212751026f7931a2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x529696141d07e4011a704039206778eaff753a82ba8482281a483b8679a8aad14d25fd10f02db9ecb9095400bf3ae60f26d190b00b875604ceeeded35aced78a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xeee8982ccbc29d754b94e048966cbaa83ff6fc05509a9c36228838dea1b569cbc4db8f4afd6e50bfc9150b3414ba098b46575d9eb05623a14ea07c3a39f09041	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6d6b48694b58f0f34306da9137e901c8a7438487229aae96736b55e6d0169422ab63410b6ed086e537ca0c165594ba7a9a103a1ce8e4a25219e94bd3208a6134	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3cfa299b574d268eb0284ba91f7fe87717594053359685f16b3b497c8bb255c090ff8a7bbc40341fa0d3f338cf7482f4c8bfe4d346cd7f0537b73e91cafe2eb3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x786a29f8678eeab950fa932271d10991c4c63782f5587878547b906923ff4367a3a9918101eb9229d733d09faf34791b9b9e05cb444536430133b837fc1e5489	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9fcd29adb5750b639f3f9745422a15efd8a8bbfec6071cc6cd865057b228980622b0c919e2dec66ad7da10995b230befd07198542047e5dac700cbe4b3e40793	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53a2c928e3389cccfdb9ea257d785353215e5838d269288a42dec2c9767a7585b6f8ed3ca6193068adf5531141278c24c40e758fd78b8cf96d038a6da4204c84	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x90029c7f6f0a8388b55bb9c22e377ad42c31be253b563e5d2125f7a77026662d5d03d053a665535580466b354973bd05a8923def92b582d711cb74be01b9d6f8	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3106a65a6685b43154bf555dd9f856c81c5b3129dd74ee3ea1c730cf102463633cda705a5bf39da3e4b0b935afa5f936a4d91a7d37f6bc260ebb347f7296b6c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xd8adc7d207ba74f72319cca89d6061fdb856947e0cdba2dfde0f7de82a85b1c0ad4232d3cf0a16f54da375d705835096a89e4f78ff811234c7290d8ff352b785	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x65b684593891ec4c98f2882e60e4d5ac8c4ce7c3c9b8fcd4d82766c6ab6e410fd3fcc697af820aeb5565b788a981280b8041801625267c0f7a903777bbae051c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x36d3f92ccb0e687055ad6e4ae2bc63de056e6402e216719c628104779dc6b7371c5d4b7f0cc1ebb4f7df902c71db56f6a8d7ac12dc360ab0202a80b34a21f97b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x40b141dc3ede6b5414f0d30ee83e5a9fb6c9bcfee071e307e45608261fe9093f30028186c8c66a390e81287c2cf050b08c345e2ec639b504a355ad832b851dd4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6e8ed0b41d4adb332c49c02549b4658b76116b9597a9a109f7ae275c6e031f2d0fa78460c0ad38551f39276f2d510a12d9ea1fed19be2e4157614705150fb686	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf5668a62c7f7555160e6df6d4bd2c1516dcd6d217cbb8c0cd3cc83a5939ec675cb5ff57288598d49bf909bb49850a24d1b2145d5d7d35b772f463b4e7b080f1b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5cefbd2e2d005a9d58c7c107f0407e64556886e508c15da5b0badadc0798ad0bcd2097629ec4a9f947e09dd96afce87e5cfb0bec4564122173474f9357524ad6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfcf44b2344400fa68cf26b935b7774d9960e758e7b9aed4eddb6aad35799a6c58cd5327d7de3f7d93b4b68f21b83a748bc989a850a04b8a512b49668d66ccc80	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x77842d1a5704a5ce7ce22d927474736d3e4d81be5c54cb5d786cefe6b3c31d799b18170d548cb5a3214f2db9b1d6a8cd992c353ca8bc08b4533f9e37ac6d448c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xef95870f9a663e4ba2fa9e062f5cbc0288ab0b558d3be07d2df63d14285e46de292545de4d21bfccc2c6f4da9e20f4f59d751a8dc4216d5538d43877a23ea4ce	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xfdea1da310751155915c2a7b3f2eb6178cfe594554b7d31de90b9e52795b0ae2dcac01c9cbba2604757319069bee8188f3fdf4918be2f44ad37b941262be4a66	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc77d5d74083540135458dc4ff1608bd9c404ee5cb1be874e3f18503998e50b9c1b3cf9396c5d0daded093321cc588f4c0ede07e89b63cf8bc9497b1eef68d75c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x6ec1948db13d5c5448fc00c356453b4be628fc268fbca0db284e614b02c0942ec24f98b39ca9840574da55b903825158f7b158f04e338e1d6e5abf15855896b3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0836374c7717cb5a9330d0790961bb488859c4693236e6d8f06331f3c672e004e863ff1b84c4a1ad2469ada4c34fbc73b9f073d197b8fac87b7ed8486261560e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x93d64d45536bb255599f32a17a8b50ae976cd6a39e36d5aa48673551eb4af3e532776b166b5e5d9d80d44ae2de71ae6df053a1863844d63ea6132260c58fa5da	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb7ef9ca42603f5a93b0dff35d0c1dbc0ec358ee69cd430f5a5be572c733e53b9b251de7c0abd0e9e4030124f0cba7bf35bc131f425b80517481137700db134ca	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x53516391ef0542eb9a720a889e64760828bca1867c4e8a1377e63124cc53cda2f192ca2f2b977aef8f3d8a08bec2767e6b80076e294b81e1579415f485bc0edf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x236e64f53099da93ea8ce10054027717e9e4b0aeaa1cfd9f3773057ee2d22b5369e96116959bec842cf7f6f0c89543030f20fa8bcd86f720f89bb95808437676	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e7abeea06bbfd71f7d0d8b965acd347ad75194d2b198598261eca37b4a9a88ea5e23bcdc8ad9bb9b4ed0c99454e869dabb8d298daf5e2b2ca7203ce749fcd7f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7872f75550e689b77240c8a7fb1e96d9660e33d9f58d2c8ee13aae215282564745bb0dd9cc8380ec6eaf92ad321f8cb1c6024ced7057a9ea1d038d51bfcb2f64	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdae8e1d4eb8c83f8b527c2a71fc624639429bec053b0c8a02cd8c553cd0fddf5c32f2c8deb074ca3a8f9cc7be33024f6a5088f86e3c0aa4a78bee9f42ad6e760	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ad87a1a20cbf83b78a657191cecd2f6852e70323e9e7b80d7e8896bfcda5a10436d55d6ab83bed2631a6b025ff845885f9979fc808a80ea2dad80f1a2bbc49c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2fa258caa7923244bb31459cc255683632dab12a5fdf7bdfa7f9eaffd28259c606b6ebd961c784e1398a85b79361c6cb1d0f5f884ac0512631514d3edb884b6f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xab99e51455db90417195f294b8472998cdeea65eac3b9b7450c91ac8b0397de41a2ab8b3ac9382e5b69582e9388cfad88b3d9c60b11458755e8d2b5747d8cfe2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x922449dd87289e20bd1ec519ff6952525ba0dfd7d2f997e87e8ad4df771bce20dcecf46c18319efa75e792124a01691f7cdea26d619bf6d40c712ae7e10f4a1c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f1143bc0f36b444f3a738e6517502d4999645650f6eca95cc0625ee60e687c0d8f2f32d650f3369e06ae695185433a5d73e84a06da9f9d8e1c0dadd5eddd8b0	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x591bfdb0402bf82dd313a4a437d321b98064f0759e9be57670d6a552f79a80a35d1a6ae3cacf55737d8d28b194826803a19258720ace4afd181a34571c2ca157	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbe06a5097b6160e404831dd381d130165489d1d065237c5c02266ae3a4a6741265d02bbba2b2efea8ac226597ae9821bb523d5190993d9b6b4fa3da94b70d99	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x06b46ccfa03441e780e18d6cc02bdc79f9bb3789a9b72d5e02b245eeea8d09886a544db81e15bdec776dec283b1ee8308fedb7e365a2ba6899ddceda383a63c5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x506d25d41e3fcb64e872c06f35af0bcebb7b8a3c1cd9a7278de43809085ee9061cba32cea301e6d964366dcaf4d06c778f64fffb57477418240167e30d6c5545	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x97f0bfe4d230e7969e7e90ea54af53f4893cdbadb2ca182be025d7a9faad93f6cae9ebed34a0d25bd84aabb8f17d5443f137dbac355ba2f084a43a11fb295e0b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x81fc122754c0e7a05900cf0a282be4c9f311e9d04d1241a89e42321e1da019a71efe3cfeeaf7d6a57c290dcd9e99e5cc2bcb68dc1378b7dd24d2103a3b6886a3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x90d93516e4a4790fa1e185f0f360869c4ec3506adf637d232e2770a1d0f23f4f4ee08424cfc10d9b651c9d8e5e2354b7671302f6e0bec4e706063a018ebb80cb	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b2a40b516f289128aa8c8af4277699fbfc83722b71184f723e0a98c7840929ba44f7bf99dc489b90ed0ef65641e8aeebb8a26385c001e89e415fe440156e50b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x41086251cfc1d7382e7bf1f26e41e775a76036109a773f1209d2bac2b4ccc879540066011736c9b67a99f26f94c936a24cc604402b0656aa3bde6efdde32e25a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa24c6af23c5a3889e6e51c1079805ff2af95d259dcc68cdcc61f084d7e130246a66731e54128eb4f8a8f1910e68f5a7a33a320c61f89eb46dd602cd31dfcb374	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x880f2a2158bfca3451753249b66821264380b3ffce1332c6758f0b7b224fa59d957e9589e6be164104e72129ab674fea1867c3a6b3315be727cf0339376bcfe4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c46277f82258b22e613c94cb767e45ffbbcf5d5825f63038d8ab9087653629d2d34e299d893cc46626a24a7641816e645d5f94d16d0500f3a15d5e384b12aa2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8091e69b327194e5e6f0aabe7e0576dc294dce5a0dcbe35578fa5eb782e7c1821a301de7c238e1450212dc96f48c95b46514eec771aefe5b99b8137bb825ad9d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdd0bcbab82c4da2010d1cd14ea30593f4e0364a7bae0ca84081ddc593dc1523b7a1ff0547a8a4c7af679f3409818318d07dac59ff90a0f4b5ede30c846db9e82	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3ea261585449bc3d2816ab28de35b21c45f48da190891cd54f22081c16c433644cf5635d67a701aa6ae5971e2fd831661d71475c51efd39dbf01ed84cbe7a180	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d4eec1e63a389ac4850d90d7fd86aeea6af768ebf53a695bb635a60b05fa5f1cb21e42657cb646d7d3b338f9d59f870c76b0efde2b97a8e17ea3774275759c4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa24aae8662250d87b6b05ffdf7ab708d215e060f1ebed640f151a020a799dabc50c94f7f548f8969bc62329275472f95e564c4c758548c8b7710b0b3fca3abf4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4490c06508291d1e08ef3ad0643f28f8626f37a1ac248ab34f53595b3397b4c1832dc609779ab75c455d6cd3a7ed0a1877271b8d41cbae57845fc9613a5a2a4b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x061e506bdb4dae93abf26c079aaefa8145fb43929957288fd52e8bae61bf74ce5b50a8b20f8815cb8fb848d7ba213b9ab00b25d6dc749ddc8be96f65782d68d0	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c19bc08ebcccd5b3077873a8d74b2d2aa0aed03d634e7c6f1fc1fef2d80c7b1e3aa1e2b98f1995ea4a44437f76c3ed5e278e45a4e39be7aad24a32da54496bb	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b227249e3a61a846fb47c6ef00102bff9bc4db3537ede1742e067534f12f2b69966164af84d13507ac62a0dea1256da45615165f2d5450b55bce7ad5057cab8	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcb0fcedfcd0cc683d834efd1d8a42fd820acf06399d4a9a1327dc28beb469833d38aa4d5117edd4380d2670b54b4f4caba4c9f31994b20728ea214f1204db138	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98aadee6cd901035129232a348a6e43332988678c306d5991c5b32d341b41c901d51fbb1921c3a377c0b2edb1b96f981baed2ec3eac8aa11130523af675a337f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4c8fb51754caa4bba353651a27daf53801d1bcd65c6c37bc7aac5288186b112a45f61d4439ea4dc315562076437f834bf3df2cd2d93cf7d1f6efd28c313ea39	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfd5af29a90c288f012ca4f5885ce68e4d77c59ca077b6b03137e5d557addae20ccdb4fc9ea641956c20c2e489cacf8a9d454c9b5141ebbfe7aceddd4ae81b15a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd798c816ff5777ec0851866d646fddba035354bbd89236082c72c2744feb78930d5cea9b2ba167210303d441404046ab62a8d698499635db44168302f5fd45ec	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e93d153bdaa3817ed8edc40a1a46d0a09a1b6788285a39f644a71507b58b1861c501243d79267b834fb3683c74d3dcc7caafad1691bb7b375125d37cc8cd315	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e298d75bfd9130f3047e09704a4dbe71fc758c0e3d5dbd395fff0934a75e69c757cf2f25080bd6ce0762b47d6d7f805e3a8a5235f914f0ae3465b0f6896d5b2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd60d21fcc1b701f873488f8f58b9e7f8973fea7368755925a886b4f353b360dcc9234d59f953f2fb6ded6ff5d1c3f4c1cdad64d112d11d1a431c5811efe11cc5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x381b8f793e1117bddaab24ab26dc2a932ce95c49ddcf73ab0a617c3797b3c3cda4002b96da68507c9950c5c6bacdaa1e85107d6b2e183a0192353401614a3b39	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8c67eb9ba8011fbf1b1bc4c719dfaa16967eb39f9823670b0fcfc22aa69af1e738b421793cdbfdf1baecbbd35fdf3deea4a22939c34527445766b6822318418c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x320645eee89dd9f1ac28c60a33118ff4450427007ebfdf466b240c88e2b7820be92458eb1b7de3d514cf002214110c8c1f0fb37135da4e7401576f246b6d43db	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe3ae6aac91256832b8c67656f8fb7dbba5b9a35596180daad649865d7d91b7e0b4a227dd8939de9061ffb6bf12484ee36805c548bb151ced9848ffdd5fa51ec0	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd3c2f124bc9e0de43813fd463705373d5f7f28e1a4f27e2770a0d9325ecee5a95efbadab31641d940ded87c4238219d684178d51c173c0ec5c14bc371f60542e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x24956c97779c5f898ba737badbdba76ad11de4c1b7632607133c72ca42a992847e6273ceb81ecb9743d9873965f8854ae168d11203575c9c67c024e23481752d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4993ef9c2bcad5b48949be47169ac2882ace2e99a5aec5d15a63a83a79365b7bb633c8a35f84aefd955afa5cd9ea0b23fc61ee8dc60e5a83d23eab3f047bccc0	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x31bb1e848c2f1086e36776d5f5a855d8029d58a39eea26341e8f833b0f2093ee6f0b184bc949b22eccf77ed45099a0012f930a368c608a47c201d86adb0cbf5b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47e609a96b8ba80936637089f3e31e6742bebeac40fd951dfdf8f4b8a5b2137c07080f9630160f27cef595a941714367b7a6f5786ab4aa706d502d9565c869e5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x44f433d5d447459f22e2e90be5e868b0be80b0a25bc896df47161bff185b9e467277506ef4a3d013c15fe901dd8ec1aa7f4105aa5c4703becb8102b6e2e653e5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xc1969995e6631bebe011257fa93f5d8b2e55327f654953cf7abfde5fe9acdae236ab9ffbfdbf8d40ce0633ca9a5270178660b17dc53084bf9e76fab02a18380b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x955bde96bd78e07efe3060ed62b196538611ac14cc5035b5110b7b989b683c673e3b788eab96440da37eb41fbf22ce912eeae1b68f4007c9232b6c7d705b7a43	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5833dbbedf16e79519440100887a981701198e6da8c4ed8ea26d9f6e5f1c628f9665e3a7ba46afc42b8e0ae85eb008377d2f10e123554513516cc3591b707a2f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x99eabeb3b4c79a77606e01437ec947119ab61a0ba26c4ad52f01a8a6fce81503db5e139ec76723e57a95f506138ae8a80ade97bb0c84e34f2dac280636c2fd11	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x17326e8407c8e50052ab40cc7ffe935c17ec580fe475742df394b2799bcaf31f7764237f2bc4021f859da4ceb4e8e04631532fbe6c4949960a6ae89e23b281f2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x61d66f4b6ed2f9c55c2eb4599a9b1cb4afb5d90fdf21216662c224315ee6224c054fdf159a40de8ecc499a8c554392d0cb7d5220b3dd8dcb2ff22c9e5a986a0f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf8ebab34e8c7327399963050c2e2285ae5a3b62dc33f2367be3cdd8612f554cd2ca30ac6c12f4e06da9b7dc2dd3a95c2de785e338c57a74d260006f9eab4b930	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3204e8ee8918d6e94574e1b5e552f1be9044833390a7a9be3da1d2c9442ea90719698f34a3d8b33a1ccaf81f659d845219458c23452c2a467bdd477089154fb5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6e47341ce6371c74f0c9d93a59aab0718225e2ec22064311642fac4df22ccd1ecf0387a4dd2c07626f3ea85bce9fbeb057619acacc670045446c27cfede5fd31	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb120dbe7b84e339f162cdea71d97d5e9237f2474fac8eeb4cdb76453d1687ea12c674781439dfe605aba7f09371ea5d63ddb8c94d9c912de8f91250987f7b68a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x08bf75eb2049c422b3796f44c9a744703df7e3884bffeb4b61adcb9807aed1eafe8935c457f67a0107398aec12efe651775cbad98d4967e6515b5408ba963f5b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x69347db6370661b02fbba7757cdaa9d85d7a57d0ce6d4416dafc98585615f7f6c80a7eacfafd7f1a537707cb22298a5b23696e98147454f454ace54de6ffe8dc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5f89317514e051f9e5c92c6db7d3d5b85ac900020724c3c02306418f2d8ced7b4c6c91509053faccf0bf83ac5201bbf2f43e4328a51f32ec40599fa646e4979b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x379afb0870b432418cc8311727e43101e9ac8b16dac4eaa7396c5a187fdb8eeccad02f363696a449986210f59086283294c1f8d3b2e2984cb214e4a2bc24444c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4c35e7ba85f4884fd4b872279e4d9625578a159c45b6aad84864777f686956d355a865423253c09ad31e025dd1928bfd2f585f70990a51c7ad37e6f56fdff4d9	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x47efd93b5d4159fde62bfbf492cf093afff64028164349962037bd2e1afdab6a7a2311122ff7ef9ae273353578578ccabbd5297f5dc9edba4928569cf3d90a75	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x83a00ce4a23a366fcd6277e24a664b6a18d94176ececfad548ba31d142549b6a4a8fe34ce39de5c3c9705df7be5876e86c45371f68199ffd54ed25e6daecb49c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x337776215101b0e822f2cc23838faef059f1c3307ea40747cd49e43e1a2ed233eb27e07bd04c99d8a85fe5f2fa43c3321f72de2601f9d877ab1a9d4834310a12	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c89b66978fa14ffd317c438368a0316f62f52433e829db915a6e6d7e1c642644b0e4684f6ec33e2f7bbf0c54f0c94844f6d5824d66f028075bd6b1b047f22f8	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x309091bfdb914d6d3ad24380cbd04aba2975cea80fda1f4285933f43a6e95b6ec98a23a9d0e00f7805d39d17249388acd96f54dcd5f426b993408a2d1baea950	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x612c22e3cd19b47ba538dbe9e3c8fa574217a964e1bac909fd113abf9c7dcdb36fd7e2d19550c4a76523fb9e4b6527f5b887b6397a10fcacb1c4b5802309c0f2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x245310ea59c10d6bd363f1d53302037f2fd56f8a06f87e87e21f0fdfa29068be9c35af30aba5c5432fc28d50233cd4c3899b0c43ad6f14bfa5d535dec3a3c4df	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x928c6af06be9812c3ff16f4c1cc482c87a1161167f5825722a55b44399c114ac0535f7d417844a66bf95fbaaf17f218e867f9ce23a5f23e30aac6a052b2c858b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0a013622834dd4b0109994f6dc7d4e0bf352ccc030bb75eb3ea054567d0653c6abe5760d24968425b48e626436339a779935723b5ed8836c96ec665d3fa1e14b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x59115185687906caba5ad2df510048322e2c97931836e0481de81809789c41037ad28622fd5937e779a6718ab38e080fc12324dceb0e41b7c3b6a82371080250	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x886e913a6294d7b592fce6396876eefba459bd1b62c4d7cc687b4572fefebcbaf6cb7583662c882f363755ddf5b2435480e87524dd227f781d8434481864d67c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x21e939b17b17d06b1ccc1eda4a74e45a7e93e89efde0c900285799eaa89a9477359652ad1c1ba8135abe8a68dc547847de062226af0769afe9e5c3183f6576a7	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3066fdff774705d9fb28303343751a5c47b7d8ab6cb346ed4621de5ed905a6d2be23517092486a33a360f4b72423aae0b46c2a7dde90600f6b23bd384d49f2bf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb5b5a5e95f02483175b2a71fef44338abd7ad53986077fdb7a192d99ddda0edd9abc47e419cc80a50a8f43c6bddcbf39b4517440c41484e4813b3c634edbc952	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5be0dddd8bfcbb78938128fc8c7336efdc37f40ce00456697e7b395a3d013a81b7f9463db911425e1dfa031ef1c339808d80f78ba87f323c29e2027946efa358	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3fc8115304aa3b83b09d315ee181669634f64da4a9bc2eb31b964e39beb80ec0cb8228bdd32bc04ad0d5608a8555aa95f9fc2e562e8a03bdf265717354f98885	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x10b0bcd31241223582df2015c4270fd64d600b1f18342579836bd03b2b06461e1d1bb3b21dee086210086a9e117fc91aefc15e88b5ca22caf216149e0f8cd854	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9b6badb4b9d3ed7017d3767131db11cb7d72360d1712a057a0c0bf940f6f2b7447104064806126beb5f053a92948d3eab9dec6bea6b71b3391bc065c3de55211	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x563ff0957954ea0513cf84cabbb4945bbe96dfe8880bfe2537af2d4c1c3673f902549f58598882712113f7c680588651c2dcd4338ddb4d2b3a37dc97582fec78	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcce66ffdfc02a0626f646f15a37404e0ca6e3cc9f9a25de7e62b6244d9485b23e386ea4e783b2b39cfe2cb6aa4bd88e0a36d8b835b5b2d308da0f8d7de8bd43	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5ffc80546b8b1c1282f07c755485bbd269d8a4d72067ff93a5bd05371ab294c6d9e4c66970b7b178ef7d8d9baa45ff47e2e2217fd10047e876a1b85d2cfb174b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1fdbf30e8cba21babdc7b9f429a6fc120758dae065731da0eab62a2c1069828040f21f60ce9abd605788a66f22e007f5dab8d7f38ff7e0ed76351ab7d872a8e3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1ada7b4101013ac6ec3d1b6861cb8858ab9c8f5afe853e807cb5351b3f21de70b6724820259973e227bcba8044dd2bcca5d7e360dfb3756a12cf2277816547bc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c9ee3318f8f16996034361a4914b38eb0e9db2733a8fd8acde41877a76e33ad09c852df205e86a8b31ec7b96a062ea721dba8469b197e711c1d4c5afebc52d4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x5cd7398e086dab23a32d178ff2a665516ed7b477df32c89af9a034104f007b81740754b80a43993a491bea559fd3ae70de3a1f1335a3391b540603c9e7d874b5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x12b260cc4dc2ad2cb8d507a5d0b377c371b1ad2f71435ee9c4742100b02fa8b93389161ba7db58db1446f8a2bf1d661cfdb7e481cfb3f8fef9c65e6a3c6952cc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafcd49154bee1f0a62a83ac59da67555fe99e4fc9a42963d87b9e8d53bd15bebcc75ef6c0420c27c06c38781e96129c6f6458b45a66fda2b0ca168662671aa54	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xecada3132dfb56870f1bc2c61c9cfce1f2103af542b56f8455c0d0c2de059456425be392725bc45c885ba58e30714829d8568a6cda064b7057ceba79f9f09440	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x04efd6b5216ce1907aec28751ea6dd9ec31c1c544d1688c69b3ead8c64532e47b1ec01cfaeaed2f623228749eca3f04fa8c83331091d0cd99606b0021899c526	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9f3622a33fd00c33e78ff22d87295791c7f4f2ca45aeb4fc5ca882bc011552079cf1d46190ea619ace25a4260377297fb44472a07ebebe2ecb33e94b11ed787c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x038418cd065ba1620b3c44b35d901aecd5eb03a2e1cd78fedf5bc992cf99cd85b4795c17098fb0537f0a4d416da6e38701a1366fdeb9ed3742151fbd1c7ccf86	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2373c55dd86e9db78277856e0e51a63af4c9261f50beb6ad39f0340e6424bcd6b742c8793ae78a67ed1f5c234508486c66a4516c4fce73b1ef26f59b5415ca13	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x458ac35ae4b9f65c95c1bcc06df01f9aba1898f264b00bc073b14fca70bc5b93cd7c50f00f144d720535e928adfc969409043437834cbc1ce138d6c5d3392b11	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x43c966c4b8fa160a63a7f3be108e8903652db3e00459b4b1ae3a08ef10019ed4166df6232dbd3b4f4b6032f0bb0c1ad49ccc41ba827ad060888883e6302a0fd6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd707dd0663d70013ffd9e0f56fb0eedcc356d9faf63224fda67705617f427a192fec1b35139c0840ee01e7c35d67983e82ee6cc8e0062ed741b9bc35237f5d8e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1ab56c3b2713bcd5b0fde3d46b3a59381ab26419a890de9ffc6aa8759d1715c8d02638be30d8b82d237ca76870cc80b600d2eda38957965c1db722df24473f1c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x08597ed13154d3d1f35d02938c9cb19f73d41ed165c1c0bbeecbed20f88f639495c377e43b393747fdcc6f0005f0956779de59ad54e33976c6c7f299e9d88c7c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x760eded2fa90b7f8f6f03c6000d77536c503b86254a076b7d77245056b64ce7b0d27ed55614789b9eaeb11851d93438bd97e387c04c8373a54cf96e6d1c6734c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x261657d1271ba66fa0f1b013b259db28d57c30b2152d6fa16d7a2c5be0f84f4d2d99b2cc594a8c89c0e1a64eb6c1b2470fe91d15b4fab9cea3fad13eae61c0c5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3355dde633503809c65a7c90f7637c14ef720a6d3c66676272dbfb1b09cfb4dc45d5cf0cb2b83a2c6030d6c83bd40adf376c01496dd46a3c55288cb9c1046afc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x2c66503e2318db8f06bac7053f9df604ec62420ce9c2303a620b58c5df0a89d02014ab138a85e84b2f7e8d5159648ec05b3aa62f82886870d55befbf4eb5d0e3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf64adcc9d4021d2d59c2fbd0eb7e131609fe710c5150c8f54bd0297f1dbe6cd331fcd0fbd4b155a039b98b4a3ffc90f1e5f3bb16478309a312ba6449b2687fd2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0fe41d79536760dee95fe673a551f0e8d2d411d7aeae275e12f5e7f9c4448b670215d443f0259672289a76b9b40009f7d8c5769a68dc5392eba6d4d14f00e017	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe6b3f7d06ada0bf0c3efe76ddf4421255eab63cf3f981d501ee8f33a576d04c1261ec20d829cba6347fbc0ee8b4a234fc5c5acfc5c58c24aec0e6d5b8728a59c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x0f2be2df8c16555ad9305b31886523940749a83d332c6f8c3cfa9317881bf26fc927c498a9840b6971b0b93756098379ef4acbb1da68762abe498c7a76d8a292	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x093ea5ecd2c592c9c41435b2bd815b8b034755a1b6286284565a439cd994c4a8ec1b920bec067ecbd62635c3dd9494b26869e2af025df7a7aa4d79c32ac6a8c0	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x8cb42f6d4c322ae5766754932904f30e5890a9aa088b8985241efe6477833dd315bc939d41074264347e01aadb6a39fb2a0c4766b7fcc12fc5d78d8680664acf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc71f68bb0da4e7c879b2236733a9ea31bdac63486a06ba9b409630beadb5b35453dd0f2a5826d5cb3fd01b3aaea443d2c646f27ea4fb9f0278e1fa93fd153c71	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x27ebbf3e91fb9fac1115146e567bb2122da5a9e88f0a4079c0bbfd84bbf8373fa7cb1587d7ae64f0d372b4051ae00dee1db0ec0ff03235899144f8790adac280	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1120cfac1c5f88d099956b6b6c3df56b9679b00420228291cd8048abd338d4b6a5ff29ba8ab417658e7ab26fa5f4c588ae15d0477a749c5cc76fd683a89eef5b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4c2bbf59f9450fc6b0b0f5788b28820627c5607c41726e032a63ca9f2ade386159cae199f42c5414775318af4a3a9907dad7a9d41cf9ee8f60fa379f61a77e5d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xcfb5f81476dd449d74c0216b6878651f6b5eb2bb0a0972786f0844bac8557c763b638a6e1df120c56475ea37ab975d36ca846991119b9c4d173238455cdd929f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5ae37245de8415e16bc20a8b97eb09fe78372ddf24eaf77cf86953e8ee64707ee64a1b423367c169cdf8bee8c78cb0d7ff5582560055c6d72043d404a0cfab9a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x030e7eb70ad822002fb39016aba15cb926be2ec6a7119a7e622b36cdb18eb2988abd08928eeca20b555dd12ba4606a110d860ae7d137fcf3f032151b6e9cb513	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe0683aeeb0d53c7d6be73b8dd871bd4e1cd1b3ff3c209473f7377033667fceafdfbb4545afb6eb5d581c27887ec2c7978151c27dee479693384e634ac9a9c8ee	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd00dba985992ccfce8ca1e78b9b390de249d0f6959919b36c8584a54cadad93946ed238a7e0002de4776f4a4bc323925d38b782c55b376b1be281062b43da3da	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5a275955feef9c6e1c6e27395554ed97d3edc5d404949dceda8ba6207d967822850ee23c8f7b82a0015c9fb7c801b5842cf405844abcf859289683bb553f90c3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe284d6b1cf0b13143c3f8ac3760cf9148258d02abde3511d6c268ecb2f60632b567912037509804a0d4605e502470da62d434860309f3c2e80a612fd8c8ae3cf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xbe48a0bdba1b06802e782f63a4c938f986e9f9f9ea418251e5bde8ffe5ffe49db4eee5276b7ddd40992e2cf11d0891b1ee0fc7a6750041d697e6a023efa8670f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe25228d413652ee0c1a16bba9166a87f00c9567b96200743cab4891cc3bed1e52c21cab70418e1c2b14b42886b5a255a6c8819655eea604a421139cece99871d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x378274da8f0919cb1e061fe0664a50c4d6f362f36aacd52d43c1bc276d9b43bd7c34bc8be43be9731c1119722b778220366e786e315ffdbb9d5305da6c916e7e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x080c2c827435179832d105adcb9b5a5b6c5634148f847da8b070777a5162e1eb79c8531664b2caacb9aa14e89a88540dffcd5975b458923388c530c33e2f3008	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x97419edeab48568038eec70665da98fecee94e30f5386893b470388f3a554fdeabbd0719a082d2d99b31cd6fb47acde706a7529d08ab65416bdd51fd6c955358	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x48dd4bf08172430983bd72ade0d27848fbea1cf78fa56e61d44fcd45242d9bee4aeffc2a27b5f8c529f067d058ab84a2f84d5d648ac291c3a9a57b7168533658	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x610193352e2feb06872755c2fa4fb5373b4f065aa9beadd44c4d907e71f97042eda56a6a43d124d70515f316972a7941cf1b0825cddddf935ff5f2a04c41e5a3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x419edd79eb0cb0256155458c70f2e1664bada31a6bff53523f9101fd67b780e5019d12bed7d1c5031bd95af11f63fec2afbfdfa368c296cc6d87bbc7e626419a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9accada1f44aa9a9436b8c1e28548b652c8b5f9667cc9f93de88641d5f913bf9d5ded52df5cd4cb0f1a27d8fff8bf4db23d57f44844c2ac3a277ae5d057b2fe6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe325f5fd35f313bbc5cfb3c061a3b270ee8aeeca9241df9f4ff276404ff88ed8ee7c6d8cc5eefb36b2ef154d624267c9d37cf41a5e759e1ccbb3da4ffb606a68	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaed79b65003c30f2b6d1e2b99da2d46a21163e967cf80d89bc75a51a620ed769faf3e0d01925af3143f66d4106239afd8c0a8f5b16eb7f9e02c2b8f82824c716	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1275649a40486d409c47c0fa4ac68ec0d07f9426545c5e4e67dc4359f35c577fb253861b94e35ea6887a234be7a91cfb1f9e1aba18be572b015922351f0f57d3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb9661a113ce646a46cabfc71345de30d242b2ee86b5efdb11c8fc8bd8833292a0f3a2e26e2264e7382213f6ae01cc584c0cad333d8a6816e21b37f67030c6db2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x336a9cea490bb2273740fd863b7ea60c0a6674547e1761833bf1b4f4cd40b34b711dcc34d8f6b4051aaa8031482a8124f6735d60d56b4040c496d1fdccfdc633	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0e49cafd912919d164578cafbdcf5dd675015852614a4299810b5e3133fb33dfb45bb9518d327f3ad74c7df4628cc57517be91e888ea1be60b2e36d8baeed1c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfbdff546021fc8e70a9b41f1ab5885e800e7e6f4682c2531f06707a68a79fb287d71d7482490d59a24ff17c71cd9b2ab2486e37400bb19bf54264ccc6aa4c109	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x55f99c4f67c79093957f1ffe1e1b469babda559e3e5cf6e3ca8d285681ef4c0c23b1b7cb7f3224a2abb90861ac40ac17e132cd935f1aca2196762ac8d7a6900e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc00586e0cda2ac9ae51d3fe49322e2873a0766d751e3886f0b80afc3dbdeb4217607df3b0a7bf284f12a87259c15664e77c8b555c2eb00222825720d8cc0e17	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x855ea9b00f0ad7a1ff5b4690cfc514bc64e8fd79c9abc756e5f3218b95103ae855d2e458819260e59b23e24190b0a6ddead92b98e0bc3e9ec5bfbb70d7a12686	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2b65ba6efd7edfe057fe732e0501a46817a32d580630638a38046e0c2ca4ca4c31e5468f88018e3011e8c8e3aee30317092b0e4102166d822d753d803f3565a5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x26ca815a2c4a31d62498eebe71f293ec4ba966552c6755ac3a9a1bc896733d9201b70b4a74c95d8c4f2a955ccf9dd68bc810fe3532d497433d90884f2de6f055	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x667c9ff177105b0bc7df5ce24fa5da2d8f0b0d6bf8f5d435fc6c9aba870e6d64b9d97e6244a664e5d803746387544eac508bd2d9352fc7c6c357aba1c3b1a975	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2aa5b718c5f056622ae2f8157cc403dfde95f4b57daacb8cf3572384ce41bf5af8e753a92547120e49e2087bf0f8c5284e04fca75645bd02e8eb136741d314ae	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa96334e0530d83a1c0271c484f73dd5465594ff96b79728a6f310b4330f4151a2234f10deb62e6f41d1ce8a6bdfe90a85eaefe342c5240bb54b9c12d74634fa9	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x30dd5ae9f2d50f740a7a81aaef5dbe4a5ecb3a7847de684f3f816c4ef53519ee169dbc1d055e0e65a37bf8f188b3ca2e20405ad1b4eb3c8d53951e91c45b70ec	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe1c935ce7540591e2ada5e68305de66d7dfc7d9fe09f2828ecb6fea4e9cbe2f7e91fbfc3bc33e1f4fee221471bd2b41f5f21c5d5ba080334285dc0d2f8ae321a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x729be4502a2075fa941eef314d70d01cf01fb49adc0cfc128d0c5b0ca59088b659d496e3971a8b51c87d1c9df75d640495b8b6b5d45eeda8797628a0cae81f95	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x08f3b6f1abf6538da547a0deee0422c861f0d8a06ee245682fde9d2f070c06b86292291fa4805f506f124c7842ebbc44c6008434e02b1fc5cabeff9c784d3699	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x235b3fd7ef98e405a46a5cd56662b6385520eb9d82c923a760b179b10adab9f587ae2e6b9f137d8354cac23e0acbb438daee9f99d0dae54bb3311c0719d07da2	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x79579136d8d599cb550ba8ea7f58d996b69febcaa98e435f11cd937834cc3e19e9f1c4f8356c60ac998515781e43b5d5a3e1a4db863b625c004460f7db1dadf3	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xab11cee2975494720731664826bb051b34463d48c791b026d358f8a196aa51f29a604ab7de261436b5937c861814d96cd36fe99350d433b14170d3e827ef7f80	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x969af129482e91fa98536fdfa4e75ef1537df33702c189a685cc5088d49076ce519f5eab3315ba510dc58b713b8fbb9b291c798bb2da80fa50822ce84ee96308	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcffef0339c3c3611598409cf44321cf3502dbdd6add7b74bb244081c9cfde30e9cda039d1a9084dc337752376638a1875ff99cebd64482ee03118252dd7978f	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf8d44a263c7e06bad7c009b4af9a702c8d33a5f0056e2b62575da1f807352f38f40e81768e30eb61ca695fc90dc6a23d49b076017a03c58ae27d943c3867d50e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12a81150738dc48e2966888f91092b05019f5489cc0aa89bcacd027b679877234c69b3504cf5e7943bf8190b1563cdefa4eeb2415e25d2db2def8bdcb70a6dc9	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c2d019053df47053aaa972f6484e87ec358b2d8987442fdaca4eba50474683ff636e47386d1bf3f26234ded90567a631867b72ac4dda838fcba5403abb7fecf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xfabaace463c4aedb3808c0eaf0a2073bed59ad554187cb64f319b0092b3e4a76767bdd24faea794fc947a55bc3f4153e698f61f77d274c965cb40d55a5734e6d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x063b23d75ee260b37d2f4da3e50dd3073e5361a74fb0b6d0aec4244fb35d33f10ffecfe69afb4a2caddd86c6be07ca8eb9a90ff2df5cb5ac9e79bbd78bfaa6f5	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9021965a68e5901ff7ba7b75d0e835482ee067e1ffb6fc27d4f0f7a05e0c8549759d0a9af7e0592aacab05c194969b57e78ed545c51ca34f9b6f8632269f3f09	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8865a87de5e20d7a557b703d8af435f4d0f5393ac4ed19e49f971e8d64454b59a9e1414b19a2767b5baf2e1d6cb261dccc06142720582dad459c90685530f824	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5af9ace44e4d863d0cc66cc1ae4b316dca4a938c57ae540eaf7ba857d80d181ea16970cb103c50de4ac9f5bb71f1d21f5dd59f91f2c991b5408869039cdcd038	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xf992b6ff9a4bf379f80d98edf84c0ce7cd18229add16aa60201f540950198d476cc4dbea76031acd4acc65b177b37b626d224b542e21c5b731283b83a1cf29ba	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1572723860000000	1635191060000000	1666727060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x42e3e9908125057824b92f4fe3bc5b0c54f6e31a78d2acd6aa76e87e0fd148e635e43ed18a671ae369b773dc3164efd498221722b780b924496336a2f7fe8f3d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572723560000000	1573328360000000	1635795560000000	1667331560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xed42f1d800706a3468590fbe27b40a91930e486aa8032a7a5952f04af5542bb9dd1f54583224afbf76cc83c792c709173aa0a1326eb5106fb6dbe162fa83a0bc	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573328060000000	1573932860000000	1636400060000000	1667936060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xdcfe6184430b43d5685c74c49fbdfede4723d97056f837cd5cff7c0b719cb245745ddae6c81e83fb4c69f42784a64be7172c385cf84eef8ea47afb786fe84dd1	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1573932560000000	1574537360000000	1637004560000000	1668540560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3c62fecaf2eb2adb57e45f4b2bfe63bb5038e70cd05e603cbec0b7e5d7f10b19d08f08909fb1fcf6204ac1d301f0374247bfd7cd5bfa8d7d62e44188f35c14c9	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1574537060000000	1575141860000000	1637609060000000	1669145060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x1bb70e132b877f7add3880e22f59b4e3e6222d265700544b2cdb65048f2f7ae6f74fd3c7473a84e6a81fe7291f3bf8bfd8988bc66028c9eb4d6e84abaf257307	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575141560000000	1575746360000000	1638213560000000	1669749560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3e1c81be5a0382b53c4f6e81c2da3f78e371555eb551027933b040f7d2c8d664a681856e6b638c8edb7969629419843a9ce2148973361f185c53e4adce2ee866	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1575746060000000	1576350860000000	1638818060000000	1670354060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x828f00d09f435d4a003dcf59f1f417b1b9e7fb2e9951eb3bfbd0fdda322ab286e059cb75470df0a85c1a2144bf7b0701c638e18baa3b61b528372992b1b84b96	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576350560000000	1576955360000000	1639422560000000	1670958560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd54c606459f171457eedaa3c9322f83766f0fea3cdfb3f0af20390b90f7cb6b656f0c51e854be86d09a659c359f1ae0c06b0ea8cdda2d56449f19453a34727ed	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1576955060000000	1577559860000000	1640027060000000	1671563060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2809ea0696738907ef0ae54ef42cd2129269ff371a6f350854232cbf1328d67e9375326fe1c94c40efb072ebaca20dcba5413a7ff881ccdd754f508103cb3bc9	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1577559560000000	1578164360000000	1640631560000000	1672167560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x50582e3c9a3c4f0f47acf6348062c4144720efa47b5c37e18f1f7551a2b108cdb4cae91815c9f81f786fe1d627d13d6c9d7ba3cd296394bf97eae87bcbefc100	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578164060000000	1578768860000000	1641236060000000	1672772060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4483a3a0ebe05de1481657a036911b2489fc95932add56bd9086e575cd923375595240eddc9843ef6bf8c9e467e92286cfcf4bd8f744764bad7c738c83a56c8c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1578768560000000	1579373360000000	1641840560000000	1673376560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6672b166c5c06666eb8d00dffe8b282aed9350a0f61ffab8270486079eb476a15600d78098c5b06708a295781388b0dbe5d770a453b22b7d7b5509fe65c4f0e6	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579373060000000	1579977860000000	1642445060000000	1673981060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x82d12e80152a0c755e679c213d15732f0546f7fc06a08f06fbd54b0b8be5bc6f71e75ceb546a9aa9ad56c480eee5de1d9e6b8e0a48ba5a9c31e51697020ca06a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1579977560000000	1580582360000000	1643049560000000	1674585560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6300a4131cdc7414b6b3fc744e49c9fcdaf0d51cf85d65dc69f99e689107da80d247d6a66ba03e6ececbcabeea81b1a28c86e4867a454c7d1a81e2b234e7ed0e	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1580582060000000	1581186860000000	1643654060000000	1675190060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x327c15931a1ddc53559d494e71cb212da2ae6ba56f5551414cde3e114960e9ec81dc8c40575dc8247d08568a73e3e3ccfe5ee67907edb496cd4012b73b59273a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581186560000000	1581791360000000	1644258560000000	1675794560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3f6b36199878933b741db7f375a69e084cd9c76edbcc4f8c39745d0f5efeb28dcb2a9ed08b1ca4be81611e80e25462a8bd2323ce506ee422ef265cd6e80317ed	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1581791060000000	1582395860000000	1644863060000000	1676399060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x16396609b5f947d878e7eca5fa1def65033ed43a19220fc9d0bb4989d700c584db3caefbd5cf1356b276554adc3dc3de5ec05d878e53a83b93f6f29d0fd0af67	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1582395560000000	1583000360000000	1645467560000000	1677003560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xef4121c5fb0fe4cf7cbdc3c0b99d0656b92953b7d1fa9687f9c5d50260bd3b340beb0813c45b74932c2f91e5275d5ffefeb443ac8e1412a7d6e55dcaf1600420	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583000060000000	1583604860000000	1646072060000000	1677608060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0ef616479fe296b35bd91c744046ad34fa4e647e12c8b005185b856f65391fd2658641bfe58c8f1e0424b752d7a9c5858d12146be60fa756536cce3efbc427bb	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1583604560000000	1584209360000000	1646676560000000	1678212560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa6848cca344801522f2c26903773d0726824311f6ee6515b5f14d36abdf3ee7ae1824b623a741da8bd46f68ef9e99a57c6de63d54a8def0d78fe09df37991506	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584209060000000	1584813860000000	1647281060000000	1678817060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd6efcb994aab9ecb948ab84edb55540ec14ce4646d086a2c72ef5285e04188566c52d4e74123ed4eb5c233ea1a84e50f3f86c2d0a152496e60164999a7088b46	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1584813560000000	1585418360000000	1647885560000000	1679421560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6afdcc1136a1a24500d1dc3ab24dff0d82323afa69f6229061b7af5148866928f6577300aee619b05733db8195346c2e85d511de5054ea431cc658ad391daadf	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1585418060000000	1586022860000000	1648490060000000	1680026060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x18c1b15c6577ebc415f9438c575b62686805a61395e2dcdce00017117dd4b354de74448f7411bccdfabe2c25282fa0212b65283d873c153c30ca78add2cc16e7	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586022560000000	1586627360000000	1649094560000000	1680630560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe0bbd86af5d544ccfba6148a6e3402c6a9779648ba742982062b1e5f86080e8db735f3728ce5c1028cc947f9832302bbc9e237a7fc0d81b1442dd14c1230e385	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1586627060000000	1587231860000000	1649699060000000	1681235060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9dfb4387202edba4f249868ea517a7c832be3726eefbeb8b78821873e5124968a2da530a71d7d0b747c451b394017c5612fb0fa6d6924e8350a73a2e9d5d3282	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587231560000000	1587836360000000	1650303560000000	1681839560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf56d26ec90188fbbb217642ee1bcbb9aef7cec36ac152c9c86d601fe0a893a569d8b2113a9c91e41c8d4f338ed20db58adc3dbf01ae15fb28442fad98adf5390	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1587836060000000	1588440860000000	1650908060000000	1682444060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x51a4d388f1c24232ce3585cf58b6c918354cedc7dcad2be2e36267e9a96eae198dd9919afba9f88243aad1b362e4a6b5054166c92e45e06facb2705fba28188c	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1588440560000000	1589045360000000	1651512560000000	1683048560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x705b63979c72b01d316a3aa4bc8c1d07d5f631f82e013fac905536600b9a774071cf51b37b8dd19b68fae1300444d4d3048951f517bd64db4fdc52d83ac71e8b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589045060000000	1589649860000000	1652117060000000	1683653060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf92826e03381f144af7736b41b764f65e0b8194d84618d528a9cd946311190ff6cb000daa71ccbc92e97152681d4cad374ae1548f5e10e0c58ee5d20493beec4	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1589649560000000	1590254360000000	1652721560000000	1684257560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6134ffe6963ddf5691a342a1f147d1fc926c0bb0c818fa0ff7086b9fe2ac5019a77b9c5fda1c6ac09ca162bc7a35a8035418e0403d2b382f84741d6ffb55bcac	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590254060000000	1590858860000000	1653326060000000	1684862060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0365fa7be8287806dc4a0108020b648f2a460fdd1c606e41366c1f5859093297f3aa39bddcad24386c6afa1d47b4808a37dd7ba0148eedf3fcf8a0893e78ea7b	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1590858560000000	1591463360000000	1653930560000000	1685466560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xd7ea86824bd20e455e8f7b2eb7fc41c6a63804af1d7f0dbb2e00a7bf32f82ce8001fbc0f7280e658222e417fd816d41a324ab9a1afd132d8d570b19576a6fb0d	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1591463060000000	1592067860000000	1654535060000000	1686071060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1572119060000000	1574538260000000	1635191060000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x07679f7e9f633dea9a5e6fab64f08116c71f73348d1477877597abf786d8ddfeeaaaaf323d4e4680dd031b3506fe8d933fcc8f0c19f68b94b7e15c1a68e07c09
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	http://localhost:8081/
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

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid, origin_account) FROM stdin;
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
1	pbkdf2_sha256$150000$XdVoN5befA7u$rIlYvJemO7qlFmV3yQTT2fG1E23eHryqX4jC5S2MAKo=	\N	f	Bank				f	t	2019-10-26 21:44:26.870501+02
2	pbkdf2_sha256$150000$mB0xhLwHDnVy$3cP0D2E6QzvORO+NqqDgi5lzizauq46PaDpt7YIPxGs=	\N	f	Exchange				f	t	2019-10-26 21:44:26.928765+02
3	pbkdf2_sha256$150000$C4s7h9GOhrcR$rdrb0T+kHeTWuvqWwzL9sIHfrMwzeg3fbJT2DKdFd8s=	\N	f	Tor				f	t	2019-10-26 21:44:26.981177+02
4	pbkdf2_sha256$150000$0EWoJdjiE0rt$EIp6SaRFA74XYegUuZeNolsrZAnPuIOu2/hpUFQIQCo=	\N	f	GNUnet				f	t	2019-10-26 21:44:27.034326+02
5	pbkdf2_sha256$150000$9q3xDxWP5xve$ImHIhqBlUy4yJbk4gFT4+/WWjsWJ1/Ra5YWw3MLt0EY=	\N	f	Taler				f	t	2019-10-26 21:44:27.087008+02
6	pbkdf2_sha256$150000$anZ3uG4S1KPI$UrXKeiTeE3NwA6EiJa6CAnV+VkKvnYOrj3b0OBgYLw8=	\N	f	FSF				f	t	2019-10-26 21:44:27.138399+02
7	pbkdf2_sha256$150000$1muZlrWLEh6f$MG2xoWpV5OtMopNq941SAhgsmlLxAxJet/XLLb3eDcw=	\N	f	Tutorial				f	t	2019-10-26 21:44:27.190552+02
8	pbkdf2_sha256$150000$f35DUlIu5Psj$1Y0wcQtPAUem/Pzo9wa4ipaYm4rEo5qQ+SZOC8CllMc=	\N	f	Survey				f	t	2019-10-26 21:44:27.244479+02
9	pbkdf2_sha256$150000$MgFVDWJxkb5A$yU9V/sfLJKyvMIRXLzIwX8oIocoFb0rD3FZWrnhxIUM=	\N	f	testuser-TrCBoDyy				f	t	2019-10-26 21:44:28.565822+02
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

COPY public.denomination_revocations (denom_revocations_serial_id, denom_pub_hash, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denom_pub_hash, denom_pub, master_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
\\x7872f75550e689b77240c8a7fb1e96d9660e33d9f58d2c8ee13aae215282564745bb0dd9cc8380ec6eaf92ad321f8cb1c6024ced7057a9ea1d038d51bfcb2f64	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304444323039464638444132334534464145303739444342313646393445393133324631464341354530463842343642353041453230303730373530303439304536363544454543304544384436453642463241384531353834464236433836313230304339393339454345314443444334393634363338373539303643383330464631373141344346433330364239424235383638443736333638364435343133354246434631353830464433374142373144354445433145423343453445464441443333413638353738363644463536413237413944464436364330423946384245454544453542454433383543323636314642434335373542344136343523290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x198a140eadcfac1ad287e87088833dbede327d040200514d73836db905fe09a770cad60eb6117e6897cc7a87951dd44f7ba1cefcaf1d8d5fda25f994413ba904	1573932560000000	1574537360000000	1637004560000000	1668540560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x236e64f53099da93ea8ce10054027717e9e4b0aeaa1cfd9f3773057ee2d22b5369e96116959bec842cf7f6f0c89543030f20fa8bcd86f720f89bb95808437676	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434333145343543333632354139353741413238413246444534444343373130463934414631393134443445334230384334433841423541374241324630433537343143433633444142463646334638374233384533464534363838364544443039424235414534333243343431323636414142453235413532354436354434363133314632353734444533323336323844314134324233393535324642374338414431314141393443354643384236444246353144464536324144433839303844413333353639434545313634444438313130353834353843313941433532453341463936383642353345443936423736373837384543333942353439374223290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x2c750fb8e119f6fbd553b560db7d52bd2933e84c580b546295f80b47fc7149e096d37c2ac63491e35980e20bcc1bc66024c9714e6e49f64e2af1b9eefeb1970e	1572723560000000	1573328360000000	1635795560000000	1667331560000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0e7abeea06bbfd71f7d0d8b965acd347ad75194d2b198598261eca37b4a9a88ea5e23bcdc8ad9bb9b4ed0c99454e869dabb8d298daf5e2b2ca7203ce749fcd7f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304441453943383536353039463742393845324446334231314234393936343936433244434144313742343535454232333333303437363630344341383841444442443230393033354537364143444239373639393544303937383741433332323542344631363837423243303336383839443544453333373832434431424341394534313546364139323334433630333130423442364533393943363944383831313335414431354445464530373437453137423943433930433245453435324638464139424231423336394236433035373144424444334135444334323731363841443935313032463645394136363737364544313946393746314642333723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xe9de6e818e72c7e14f3cc39343fef9642b472016007504849ec87acafe1715f887d40e9570c9b2843171c254528f9ec9fbde365dee6692b7142c548f1b859a0d	1573328060000000	1573932860000000	1636400060000000	1667936060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53516391ef0542eb9a720a889e64760828bca1867c4e8a1377e63124cc53cda2f192ca2f2b977aef8f3d8a08bec2767e6b80076e294b81e1579415f485bc0edf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237414233303245363843414241334234413939314234443032413134423331313630433346443333443238364333374333363546433936313736353644423146414243373346393839463441324145463643323337414641314439333843354231373035303338384431323730384235354235443936314231463042304231433632423241414342364536364545383133393535304331383133443343424435304235323945443039423037463845423842433442394445334231424132433138423732393135423030323944373932303945304632444137333432423733363732453431323135303045394634423237333935413433384346353839303723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x9d88f128560c97b0a648f2d0b15f6342c54321dc38565f6828e80d22be8c0d963aa44f7926e1f8bac7fb904c78134282dd1de4a3716ef489471245480eb5cb0a	1572119060000000	1572723860000000	1635191060000000	1666727060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdae8e1d4eb8c83f8b527c2a71fc624639429bec053b0c8a02cd8c553cd0fddf5c32f2c8deb074ca3a8f9cc7be33024f6a5088f86e3c0aa4a78bee9f42ad6e760	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303936323237344445303531384232374643333341373532463032464232454446414336373438364541463835464433454346413532443738304130344235463539304442454530383131453343373942363139464330424533394336343836443633343233343538364239353433314246373334444635423842433145413445444633333544423031343534443331343831343633313434333234343839383930353231324541393937423738443538343546434335333837433132423633353633394631454234344645443831453034413642423746453843444643453737313734343445373444314342333635323734343639384635373835333331363923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x26bebe133347b7f53b9303ee51cec0e2c59d376b79762d33861d661f59e81fcd6aa1e16434995705cc2bb6e997ec50b7aa94d1702caf47353c9335d5ca9bfb06	1574537060000000	1575141860000000	1637609060000000	1669145060000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa6d69c92fc1291f62f1c510ab4c0158df0566354e341b0aaa41d38861d546fff2cdc8a57fdd7ac4ee2c69e8a4201e096595fc1b60a252b87e091cd5a800e9dc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235443939413241413732313944423233434544343030313146354532323532434444463046423636463833454441303435363436334431383239463836424435354433423039334241393045353831413946333842374236384345374135464334314644363932453735354137423137464130343442323846303642433437394339353838424631364535423545353145443946313737413631353444433539423346374437323842374345433841444436393132383444384137333044323536393934363139444141353844343445363837463237344236363734353841303533463942354439394545353842313245363730313546333042414241433923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xb1988feaac5dd606d4e70962867813ef69700c9845ca324697aaa8be738eade8bdccfa8832117c2ae4390f13745dc139cd7210f5bb7527fd1e1c58626e436e0b	1573932560000000	1574537360000000	1637004560000000	1668540560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91f4c2d462bf28f505af9b2b9948f6f9c72f3fe3521a955f73cadc5e1ec0a41b3f360eed2fb3845ee61fa6a0d18a26825675c0f1f058ba26c0bee45b85fea614	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234443545444246353533394238313431424145323036373146464432333842434641453132413637413934313844333641353933463641374246343944323646354441324143343530394242373037343430453830394134464134374142454330384446364142434346313438313936423445373833353437354138454242453246323833424631304341443341353443384634334432414646323434304143383135413145453341414539413746313935303133394133384335303243304130303938434635363337353139383732304332383444313931363635324134353439314141453338363832433638324141413338453839323042313843323723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x0abaa3c8b89418e1d70eac1ba08a337d555412e5d9e3e8435efadeaed430d25318db12195d6b9334c737b4fc15895603a3dfb690ba35b04cf5530b0e31509709	1572723560000000	1573328360000000	1635795560000000	1667331560000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf17bfedd5b09e538a7cef03016842dfdd10f35d1813fccb22f41de4837e371c6da1d478d2c668f4511a3c426ef78c8179cab1ea26a63c8de705ea7e51628d40a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241343930383244323338323932463333443230423344373737353436343434334333413832454244453137323231454446333038373045443646423336443134454138313735314439364344414332394246323332453334323734394336444544374534453145433734453634383344363141413936313635393331463142433544413436353044323443434646383534303641313244434232343437344330413341443731453936423335373137444639423244354534453230334533434636413341343043444546313133314642363436423442433533314538354130363041354238314535344245373243323130353830314133333532374435374223290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x7d5b60d9dff7ef0148d9ad2710f801fbff448abb3508ba4606e347220477094d80d61c9703d86679fe91d2bdf1f9df2358d04e101e44a1b5976ebb7b888f390f	1573328060000000	1573932860000000	1636400060000000	1667936060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5a330c271f866f39a3197a6e4ba58b6487dedf8eff0f8af41fbe245283e5c1c6c1253ed302ce5332316b8396abeb73f0f6e910e273431625de7f3c2c5faa230e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430373739443741323233323244384537333035364438343234333042363931384435423137343035444235383245373142334633464230413938383939384135334246364543304245413537323637434437453530383745373332364341393842354345344132423738454441393138453843363444414131363039344441453744353836424142333335433143453031453630383337464241354643313743313737464539314438454132324144433734354132354346454534453538393035424439333842313937433946323932363243333734413532354443343038414143354539394441423642413736463246443030384335314130314236344223290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xb837a14361fb1b46b655f345160f88981a998ad573f5209e3bf60c70c24eec888ba8b99cdbb3c6a0df8fcf5ab68832e6fe67e807bf82f474331350fbaa61500d	1572119060000000	1572723860000000	1635191060000000	1666727060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4eb022d19a1e9580b77dc79ae18592c2f26a457bdeecc3a0a34d5adc438660caa6de0a4241706901ed349e9204cc5b8349b296888cfcd4305e0a2011bd630c47	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136313538413846303245414345393141433544333037304237314139413337333934303935374641383632304538313730424430363246343242424241304544314442443241393534464535313134433244464642413544304237464434363538423033413341323037424145423944313143383144364334353941463237383642443444433841384144413742333233394337374332314246344530373137453446334636413734324432414634414144393930453530434342413432393935324331334438393139343235463942423442423130363531383942323841303242363939314133373046353744333231353245303236324230454430363723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xa16b3b9e3c02c28df58c34a10866817e721676a6bc809a302c2571d41939f3602e4c65a98d0e3b92097925b9d536accd51e4e932c0012aafe6007118c6141802	1574537060000000	1575141860000000	1637609060000000	1669145060000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x612c22e3cd19b47ba538dbe9e3c8fa574217a964e1bac909fd113abf9c7dcdb36fd7e2d19550c4a76523fb9e4b6527f5b887b6397a10fcacb1c4b5802309c0f2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304638303136344642463442343837354644323735433533454346314145383337303242323541444444374331433346344246463539303238323539424146343636314545343139453444374138443437413741413530423035383037444336374132313846353634413838464645413144384536364533394633454443364144364142363939393134443636344433303139394637453334463544444134333735353031433141324144353930394246324143423735463333464238433845433742424146373146333845433632313539393033333533393145343737304237354336423144303839393341434234464442443839414442444439463538383923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x572dab0cf69182cbc054b097e0e0a6e22fd66fb5175e48aeec1975596eae848b693c1d3f8871650e6896b51aa69b2e31a30985e7e4716642797f5da7bc9fa601	1573932560000000	1574537360000000	1637004560000000	1668540560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c89b66978fa14ffd317c438368a0316f62f52433e829db915a6e6d7e1c642644b0e4684f6ec33e2f7bbf0c54f0c94844f6d5824d66f028075bd6b1b047f22f8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235374237434231443737334343314430413632323435353435363230454342314346443431434346453642344637453631364137383444353238333835434146443037323345463841394538393642433530443037323043463534374545334343333245313941433145423942433943373931343737313342374332313738304242393339354331313532444134443742343137364545374435304332304531373144324131324332314133333031363232384637393238384645304532434635334135424441394346464242304232313242383231364235423642384531423439434630383141434234303834424632364639463934364435324339374623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x862a328abe845788363425542b98f700d6a6c757d1e0050b9820600769d2ccad42c1b8fd56207f8a5dddba3859206b0f5de37f26d0cf2e59638bbf1c8c05c804	1572723560000000	1573328360000000	1635795560000000	1667331560000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x309091bfdb914d6d3ad24380cbd04aba2975cea80fda1f4285933f43a6e95b6ec98a23a9d0e00f7805d39d17249388acd96f54dcd5f426b993408a2d1baea950	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230313638384436363143444143424434354532363335343639353436383343363731333633454532453944343741363644454443433142384333334138434635393733463845364136344638413230433032383936434546374232374535373930383444323536423130373242423639433230364446424546383738364146463337384430413138333034344635303939364444343932393531313030414638373041393545433933363837303536323943304239443744454345433233444543343946324534464339424145373934363837323130384437313942384141443837314139443941433146354141363042354532384645343131334137433123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xdc243ab9f82f8751872a6bad8b4f52915f78c096661de750b08ac7ca40e4eedc6755232fede907e212981f6b93cd05ace8fc863595c2187fbab2cf01c8bdb60d	1573328060000000	1573932860000000	1636400060000000	1667936060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x337776215101b0e822f2cc23838faef059f1c3307ea40747cd49e43e1a2ed233eb27e07bd04c99d8a85fe5f2fa43c3321f72de2601f9d877ab1a9d4834310a12	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304232354546373036414238333243323639433435454630463239424231303134373043393339343834383538433337463046394130453031333245363735413337433443334445393739364244413432333446334532393131333630313938333832353544383136413033443239323446423534364239463932303732354534424230374331304232413345443237444542423241354545433139314235433334334133323843304432313942363339414243453637394543433036333630394631414439304633423031464332373944443038373339384334443442393738373930423938414633363339333337353745354534393245453933363641444623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x39435d72dfa5ff2641b551fc080dabf16f0a5fbf2ae2bb52ca51741b0525d19b0b0a0ed3e69c6d7a4c24a9bf735145cc90b15831c3c89211ae9ba1842f3d6506	1572119060000000	1572723860000000	1635191060000000	1666727060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x245310ea59c10d6bd363f1d53302037f2fd56f8a06f87e87e21f0fdfa29068be9c35af30aba5c5432fc28d50233cd4c3899b0c43ad6f14bfa5d535dec3a3c4df	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303936364341323138433035443143444545393444433544423437384143433632413539364246353835314135383538453934433033304332343842453043454444303236304241423831384545333645333636303533413934373741433345464143354145414541303538313136343945344437434136313035324136393933463232394133333431323431303630324342413938413745424139363336443344443138313931333934443444333933423334313537383932393631383546393030384633383643384345394630373337464133383937424636303736463832373539343831333431313438353633343441363638323739344136353245433923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x6c4fee42a0e55572b6c2c837efe8a2cbddbc02d92f0d201b748eb842b7c8b461666e18a6adda309bd5289815faf1dd04c993a32ab2e5f4999675f92119bced0c	1574537060000000	1575141860000000	1637609060000000	1669145060000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7e93d153bdaa3817ed8edc40a1a46d0a09a1b6788285a39f644a71507b58b1861c501243d79267b834fb3683c74d3dcc7caafad1691bb7b375125d37cc8cd315	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430304238384443343435463536394444463230343631414337414342333541393632313644433731464232363534444133363633423044324339453330454135444241303733364641353135413034383536453039323746363135433031424332303243453042353132383144333846364632444639323036463236364138453442443637354645413337304137333136334435334242364534344545354441304536323132374632363945333944393532413643314136423334354332304235384137464641384543343637414346363733433437323434304231463142343045384243394335434636383042393141364144374544394434414141423123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xfe802e666c309cfc8c8ea9bc8201409cc1d6862f9328a6462e2bd8f1c34189a7a55eae3bd30d6c6a96ee9756e154483e667ac0faa70d382ba4f9e95613c1ed01	1573932560000000	1574537360000000	1637004560000000	1668540560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfd5af29a90c288f012ca4f5885ce68e4d77c59ca077b6b03137e5d557addae20ccdb4fc9ea641956c20c2e489cacf8a9d454c9b5141ebbfe7aceddd4ae81b15a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433414531373634373531323538363141374241334133353632464331443243413042414138423046374538343441413944344342343239453845343931393130343139443036394437424346313244414331303737444331313742333044313935303138394230453034394431423433444331444234374332463045423642433538303835354131373043433335324139413234394445423131413836413546394445353133344134433637424431373937303433444235324332333836383239393043333946314141464641373044463343454632393431453835464144353831393243343338373930334438433143343046453139383135423745453523290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xdf52c156bc7b94db6ab616f0c5133d2ad6ee6a519a0e7b8a4131f5f4928cc810bdd3e262e05aeedd205d9c1c9f03c1f4645e33ac13f87dfaa05746ebc3e6b00f	1572723560000000	1573328360000000	1635795560000000	1667331560000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xd798c816ff5777ec0851866d646fddba035354bbd89236082c72c2744feb78930d5cea9b2ba167210303d441404046ab62a8d698499635db44168302f5fd45ec	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304638434243323831464438333045313135434332384530464442343446384643323846434533443331303742423942384444434443444331304342304543344542363342323730453031463037364241344345443830413042313742423734303934374346343643463143443333343042373631344137413843413643383630444237304135443530353435433538384638354430303743313234364333454334423639373331463435394137353645343745444646383930343030344346423330373739373434383334413131463139383231464642364332413041323236423242333244333137463130454343353236444131393939374341313434344423290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x84abc593b5d04a979e4bf2a4a8ce4e533e605a096b76667339219815a5e5045e7a7ed748ba307d458d3e342ec6dbc5ed6636722108c65235deeb24bdc4488304	1573328060000000	1573932860000000	1636400060000000	1667936060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb4c8fb51754caa4bba353651a27daf53801d1bcd65c6c37bc7aac5288186b112a45f61d4439ea4dc315562076437f834bf3df2cd2d93cf7d1f6efd28c313ea39	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304135303645424545434632304439324634423946424641443330383937453633443830363739354531344641313936423237433845394236453439363544303434313346433046344139464533313231334342323546354335434445343836313935444344434144413044384535433846324641384334333844444131313039393746393444444143313938314132393745344638344538334642354634393430343143443342444337393441453530463445454441313041384236454139384431413943343543313533434436333034413842443632353536353542344430444433354132373441423243423730374436373038343736324339303734424623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xceefdb182571262ff0928c601915eef94b13e9bf8d1f32e3b57ac76a118d6d467ccaac933fa0bab4b69c325a01f2f48e215bd769196e9aef4d0d175d44febb03	1572119060000000	1572723860000000	1635191060000000	1666727060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9e298d75bfd9130f3047e09704a4dbe71fc758c0e3d5dbd395fff0934a75e69c757cf2f25080bd6ce0762b47d6d7f805e3a8a5235f914f0ae3465b0f6896d5b2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431353738394435374434393542373131383033343741454545443743334543324645334433463835434444303334374438434543454231423744373243443038454133434137303236303932354144333736414231464443393842384330383141414237334130413834414232374142323341423835343345333938313333394438373843433131343236383443354643323636413239343031303744324530353830434533383430343243433541463144464244353030423333453739464338314631453938393342444242453545374642333436463445433331364339313336323843414343363644384641333043433732353444433231463245393323290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x80b81a83c8373f64dec4658336fa47bca3b8c0012817490e6502821d87b2ca540f3dca3958df34fb23a43d92750002a31eb0657c9c14f1280017b3fea0f3e907	1574537060000000	1575141860000000	1637609060000000	1669145060000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x261657d1271ba66fa0f1b013b259db28d57c30b2152d6fa16d7a2c5be0f84f4d2d99b2cc594a8c89c0e1a64eb6c1b2470fe91d15b4fab9cea3fad13eae61c0c5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331344644334544353234364430383342364535333638423636413441433830463246383234463735434233314644374236344445343739453838384633383544453137393931314338344532363744313945383338353738434436314437414644423546324342424335463643343231324433323443464236323642413439313644433645393045443032363636353441303142393636394446373141353633383339323546333345373031373430303145433341324643434146363342373531373841413432353130443242444445374630363931414643374534444245344444363734414136444538444344323842383436453642344335323344323523290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x0919b6c5380d2791da4b60ba2f50f3dbfe40342901f2e5a27368785ac37224494b93857d96febc9110eab2008a7f91eaadfebfec92a47e30601b38869ec8730c	1573932560000000	1574537360000000	1637004560000000	1668540560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x08597ed13154d3d1f35d02938c9cb19f73d41ed165c1c0bbeecbed20f88f639495c377e43b393747fdcc6f0005f0956779de59ad54e33976c6c7f299e9d88c7c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304634323335433436454146384344454141374537324636414130444143334444413435343642453539413937333932333535393646433634313836453337343932333841383932453343443345344644453833443934334134413137314146313036333942324336414134423342463632443835454537333041323042333845423341463934363235353337353244434245444339344439303045353033374543323438433135413439373732393035303730413433443536364346384337384233394433463539423643324144443537304335393145393546324446323831434333453141393539323445444342453844413843344435414538303844383723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xfcb41bef586f3d0048df14e54e7885575bb1a8e70513cfaa0c278c2250467b8456f32074d94cf9b54e1e7b61621a40696e27f271127d8fa509ced110b5356802	1572723560000000	1573328360000000	1635795560000000	1667331560000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x760eded2fa90b7f8f6f03c6000d77536c503b86254a076b7d77245056b64ce7b0d27ed55614789b9eaeb11851d93438bd97e387c04c8373a54cf96e6d1c6734c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143424231463938333231373832453137343243314334453831334430354236394332374330443537423636463438324533383842383141444531444337323346433744424646453444373838433541364641394444453635323030443832413138303136353343433330323431423433374231374130443338323232453846343543463432423430313133464344333839443945304241323136423030353034434334313932413731373235373746384339304138353443343436303235413432343038454234424443414442323334363739464546303430333930454146323235313330453933433632373645443741313437334545463730333643384623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x156e094d48f0598aaeef29dac71515508de3f79a66f661c8c0fbdfc6a85a855c7378dd9ef13e1b7d63c61311180aa148e6dc10b0fb310bee3f37d0651451090f	1573328060000000	1573932860000000	1636400060000000	1667936060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1ab56c3b2713bcd5b0fde3d46b3a59381ab26419a890de9ffc6aa8759d1715c8d02638be30d8b82d237ca76870cc80b600d2eda38957965c1db722df24473f1c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304144353436323739324144414436413446324335324438463242364143373843354339444542444242343937304244373530333243424632333638354130313630344637373633343244363941434531323831424342454431453134423935443043384634423742324232453544374641313545304234453630394235304344443033353843374345354143334637363335374546323835443830423746434642333034384542454541424234334431343542463735343634453933393141413142314536433544363234383244463041423033453446373336343238383536303039303344363545374345434435443339303537443446354231454346444623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x922c255e8bd1add5e58793d499b93c08ea1469e36a25ee261ce4e7209fc79d9d8769661cf1018dfa08d09fb9cb5bb4cfdc19104e36adc5b36ec3f3242a87a207	1572119060000000	1572723860000000	1635191060000000	1666727060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x3355dde633503809c65a7c90f7637c14ef720a6d3c66676272dbfb1b09cfb4dc45d5cf0cb2b83a2c6030d6c83bd40adf376c01496dd46a3c55288cb9c1046afc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342373036364532353938463535434535443834393235423541363346393344323945394442324236314232364643364537423636423933374134443939443536383533393634423246433543334536424138414343304135334341374336464134433038413935394632363734343937333445413646393041443646374431394344394141353643334631334630414543324439464638324433393644394641413542353939413244344544423639314246443038323036373146463433303133423134374345303431384544433631393736424432394131394538433733443943313937453236343036453745424241423431353041354343363941304223290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x679e8361a13c92cfd5dd23c5d888d1e94dafa057090813a3ded38cad335a04afed9cc934873e31a0130fc5da17c0ccafebf4df55b75f79eb76fe154ff646920d	1574537060000000	1575141860000000	1637609060000000	1669145060000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xdcfe6184430b43d5685c74c49fbdfede4723d97056f837cd5cff7c0b719cb245745ddae6c81e83fb4c69f42784a64be7172c385cf84eef8ea47afb786fe84dd1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439443233433839464643433245384630304230334431383332463146343036323046353633423244433531334635393236463135333334453444464643414145334338303436414331354138463635454337373433343032373235313437354246384333394235354339363231304431413943423135314630323933454543314635393743334546463143334438453231433046413542373643353134303331334131444134384238344433393334463736384638323044463634443744314143313935383131453236343433343731423735453434454231393339303645383134303633393544344245433041363633444338334444424338453737343323290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x49ad5423d9898c8c1a0e8a6af75c8dbe56f1df16d9bd11bfed96e42fad53e8eccbaa016bd198d905db9f2ecee487c6d0a7332ff00fe7ad84bf0f643428beeb0f	1573932560000000	1574537360000000	1637004560000000	1668540560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x42e3e9908125057824b92f4fe3bc5b0c54f6e31a78d2acd6aa76e87e0fd148e635e43ed18a671ae369b773dc3164efd498221722b780b924496336a2f7fe8f3d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304444334236444336334332374534373435363033373046373536313935413035354245313244373443433136353738314631373233354131343436464341363846344230353036314344393537424442314241313746314542463143304234393935323646303834453034413932344231443644364133323534373845393735384546453738393636463942344438324145443135313639413343413332393245343037393732313737384132454545384638433345383030443731444337464433434243393244323438393941303944393937333444363541353032393631464535463033364436414234324539444338323442333136353342353538423523290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x190f3cae5a194a43efce8ab2fc3baf99603b6e03f74699a16ef255f21f88802e81c43e9dbfa1d2e102378b38ec16c844558ea213ad29181f2dc291b185fcae03	1572723560000000	1573328360000000	1635795560000000	1667331560000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xed42f1d800706a3468590fbe27b40a91930e486aa8032a7a5952f04af5542bb9dd1f54583224afbf76cc83c792c709173aa0a1326eb5106fb6dbe162fa83a0bc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434454132433146464539443944443141394533364132453638354635303037443141433632433133383430374641383846444531333846454333343032414645433139393137393345423441374333433635374233333445443241463346374532374435314636344541393131443544384142354643363046334137353933303945333344444635424332454339333337334232463344433136453244373733303741433641343536423739463232303841303845323830333737394335414337334443323142373230324139443241454242463738304337323030384341413039324345304242343444344338313137443043384635394642374531354423290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xbe5d4725e79cd4037eb51f3ea1c191f5e388836e5d224881b3c1b5900e34a4fe964968d0d9b7e1618208f39d01b7125824d5dd270d933f10c5484ff0c6faec04	1573328060000000	1573932860000000	1636400060000000	1667936060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304138353436433230414144384637303835383833304144384445303835414438314335443539414446324544393532343331303637444539433530313034413642443930453443343932374439323231364138394538304138373742353038443543373834393543413931364141313736443137393242453134434539423934424534353433384242393438394336344232343734463435343738353339443637384646313832373944373544333331464446363538314238323644423932453644434131364136343344373331444433463643333839354330323433343636414636343435453030313643343934374245373031433430353834364443453123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x70c8ee121f7dfd911901c43b0ff8c54dc4cf2c6fb16eec74075498281266c8cb29994e8834162bd8b21b23da0e2b00bef7aa62149e58fd1937f17336d4948405	1572119060000000	1572723860000000	1635191060000000	1666727060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3c62fecaf2eb2adb57e45f4b2bfe63bb5038e70cd05e603cbec0b7e5d7f10b19d08f08909fb1fcf6204ac1d301f0374247bfd7cd5bfa8d7d62e44188f35c14c9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333343431344143384434333538454146413846413330333434324132453736374646364530434436423043353931373538373431314337463931324334463433424630333846334533303537314441454439303542424434413746303044463844314133343238383431434543413733353536423533464537364237394338313834443734353941343444424636313244373231363045443541363534424138443943423332453731414541414433383946453937313046364433433034394335323745464246343145463541314642444530433145463546464245313233313833423546374533343038443330393944353941374637383634464237353523290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x84d6341a57cc8b2a96cea84ccaa391baaec2833ea47c64ece3c8f5641f8f26785cb86873d828d11620cead674edcbd308aebd43a31c709c6624a35f95294d509	1574537060000000	1575141860000000	1637609060000000	1669145060000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xb9661a113ce646a46cabfc71345de30d242b2ee86b5efdb11c8fc8bd8833292a0f3a2e26e2264e7382213f6ae01cc584c0cad333d8a6816e21b37f67030c6db2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304336383846434239393637443331394142373235444541393831374445463044353638433644324336304633344342463434424344424238393643373532443345343231423845433838434546384637363337373343413443343334313935383338374639364439463535334346344542304544464338463242313744453937433442353938453136363938463934363039434233433843314346323430443145323833424541393234324443303145454133434143393031373731344333353433334137413830424531424630454535333934454537393046364235353531423135344133303034374333323137363132393645433345434239444639343123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x329acb5871e3c0dd72a0d27a3cac451f1ff07b98e33e0ac6db5475eb2c9842addd99f696d257658be01daba4abdfc2e9004ea6ea5582044aa365ec1cfe12180b	1573932560000000	1574537360000000	1637004560000000	1668540560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaed79b65003c30f2b6d1e2b99da2d46a21163e967cf80d89bc75a51a620ed769faf3e0d01925af3143f66d4106239afd8c0a8f5b16eb7f9e02c2b8f82824c716	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304132394441414646413938374441343637374634324541313042453341363937324644423844384143414442384634423436324439423846434643443331454432383831414430444241433239413433354532373144424532354442303431334230353938383839443745413032323346393735464541354136463437414543384239303341454641463241313144463434314537303132383734443343334633413041353237344137423444374437303833383942413135303846443331433143443332433533423441443338464333393544354633433938383344433831303346343933453032413732383538444134363132334637414536343531443923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xefb804e4cc8e61f832c3e4a620e5b3925667aaecacf1151e0c24e7f90bfe08c5288100a6fb829484f2d7db5f74fdaa69a5864e3cdc54c89a94d4376eda712b01	1572723560000000	1573328360000000	1635795560000000	1667331560000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1275649a40486d409c47c0fa4ac68ec0d07f9426545c5e4e67dc4359f35c577fb253861b94e35ea6887a234be7a91cfb1f9e1aba18be572b015922351f0f57d3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304544314244384643394237414535453145384246413343444433343931413231414434374146363639443744393741433746413944424243444330463644323143423743383945314233343437324636323745363442364434453339434634353443313539414338353136414543373137383242304134433042363442373032464230434335374333313945373946324230333335443331443530314431344432333633303532344531314145343943354541454235354232463236313135424634394142463345413735313034423939393639444532374531413638424242444345323039364137313644413338384337343442464132443630313132333123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x0c998398427531e12cc64c4707667154149e09862323f353f7c1cdc1eefd0147bef60374ece42a31ec58153b9facd2e9b16616ae591e2af616d8bf8e4f97f902	1573328060000000	1573932860000000	1636400060000000	1667936060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245394139303432463744423331413431383246363333423239323539354545463944373941363331433932394530434632443541393739423243413039434237303546394339333742443433383244393042344632343235333433464532374232423841323031354631463033363235414531323546444143313339313930383346343744423930353234313942374137423834333831323044443443414446303645363046333030444235383935443531394244424637343337303133454634343430383934344332354342424234463342443830364144444544394530454644363746324234414230314132383236443330353645353342454432363723290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xd648185f2748129d76c8c3273c50a952c6fd61c779fccd5986aa3f5df0e5612711651b1a46d5d84ad51f737ff78559bb4c76cd985daed58e9a4a4258abc13607	1572119060000000	1572723860000000	1635191060000000	1666727060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x336a9cea490bb2273740fd863b7ea60c0a6674547e1761833bf1b4f4cd40b34b711dcc34d8f6b4051aaa8031482a8124f6735d60d56b4040c496d1fdccfdc633	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233414142384536343039363931393637334145453242363633323946373038464333333644344442443237424539383736433846384237363535373845353230354634384237303338343846323435393046353644453135313037333841343644393536313141343237453030343339394433333238423132423036304635443846433441323635383643323935323241373435393142363243383037374634353645353645303544393330423336333437314144454645423233423732443139433641464637374144443333444332303438303133464336303934303631423732423138303939343730363136464141343435323833393033393131354223290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xc426b41009c8d222c8d9a562b4dff5b825ea5891877faddf41f3982dd0d32a68a234941b9d866ea5c01d00f1284ae59ce3531cf0828e758e6b244da20b994004	1574537060000000	1575141860000000	1637609060000000	1669145060000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb8d5cf1dcbee560e28770126845e82e688e3306fd1a7dbd7e203543789aadc82ebabfaa7714c074f23f7b05ae1895a804265692672b39220b823936e602631d3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304130393045314533423145463231414134414441333033434138444332323037323039374546423535373335383631333537413244333233453942353643383445354646383844363938454536383437343035343536344337353142363541324230374330374332393337463243434331463330434235443936324142333334324642313046454645324546384232324634453336323731374646334432313839323045364541353735314131463544433743304237333831343838413935393438453443433338323535414646464346304242353846343638373430333639463031323839344244454542463934334441423234433046463930423236383123290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x6b89be60861f1b829dfa5d3d54ee6980bb76ad3ef7ae2a86ee341ea7b469ad4814ccd7d6b8cb73853bb518fc2ef65be3cda4886977fd1bf37dc08f5e104cd00f	1573932560000000	1574537360000000	1637004560000000	1668540560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa7432ac9e7af30e7e4c1367c3ed9077964f76f2123fdb3cf1bc066a9a33dc4580ffda9fc4b259539d176b7728574ea8d2c049fae22d2cdcc8b1cfb82c5361983	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333423136394543463834423238394346363235434242304437464135453236343844323635423544393734393331303344313830463338363446413937453534373946353838413336303230373533344546464639323644323643454341344242434546364338324343333738463930353431333643304442444138303841324439334539363746454542374644373632444242324445393139443646423537313439313646354444383339453145323545353338444241323633393534364435424233463133313545313639363631463144383544323041454637313930363834444244453530344635443344334131443333443930314435303939434623290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x3c6f0d73e0c5e147f8a5f9a45fbadf35c363b8f5be6e9ed1754c5d88d445395f4f61124876e01b7c719fa2c1b3b6fc23f773e5412be5e114b1c2ded6a277e90c	1572723560000000	1573328360000000	1635795560000000	1667331560000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xff1fa8acb23225a0807036c20183674ffeea4b996ec5458d37bddafb757af9a26770db5db474b0999323c34895ef53930cf31dfdcd76c8579324ec4f02cb622a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946434133433633303239334531413634384443453031433845364435313039424142314433353736423146313538344638384645384143453534383034463941433334304338414242323736334136344146464534454131453033383534383142434430304146393434303533364645413836433936433134453739374641304330303338323145354346454643353846374239444541383943304131333542343945393444443534433134433746343334383043464546443346303343413736343434414636344243333441313435453438373933373132413839413244394642453034363737413842313331384137383035303746384641464644463323290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x6b1c15dedb669aa8e1e8d47c043d64d2de05737db0f0d38993064056eb901f30c179051a8097bae89853ad21f932b32c3c65a9a88656567ac7901b30b54a0e0b	1573328060000000	1573932860000000	1636400060000000	1667936060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xec22e28f762e7f9d178463318cc4c00bd2c524e0adbdca3de845d2ddebbafaeb4fffdcaeac4b8cf1de4f43b107c7406c3baaaaa5e188ad4fb197d7fc3d3e0cd4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304238343945444445364430353930334345423432364236383630314330314241463739323446413242304544314339323542323632393531444138414645464333323338344637383136363230393136413541443835423336453944343134303432443241433036463034313144383732303634343545433143413631343241353244314134463141463533344533434533414141433131343544313538453939423033463038373636393834423245373239364643453944413338364131373630333742384238314442354436314343394534363446363530414142363544443432353443384145364436394241433130333131363330393835303631304423290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x4843860d3bf699bd1ebef8ec8dbebed8e4d9d1f065a90da94a0b54bf7db2cf5dfecda607c40e51dd77494a21a30da6b65dbacbc07b2249156d7913f3a98e660c	1572119060000000	1572723860000000	1635191060000000	1666727060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xe739cd6b89d5509224e08a669301ff07451d0b932a366f79423244e546b6c6ad82de24c029f4e13b7369f5c6dd5983bea260d2f26332e71c26bcc6da43db872b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430424235323134343130413743413743313342373544393441393939363343424545383735463034304544393345414537313831433136354146383939423536334243423844384241433441454638464144393545303645373139323544394535323345444637414344363839454331434434373034363635324531353530453737384430324336313035313438424644344438384642343043433635383933353242374634413432304643454337453930364435343736434143313944453633423743314538303545324445464243464230444241303137443534363742443041363237304135433042463742453533303139463833443439393630363923290a20202865202330313030303123290a2020290a20290a	\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\x4993cbe097b5dbc00b8d4b8fea85cd23c299902b21db2ecc14feaefbc71bc117b31d1b334afe47581109cfa3f68d3beaeb95a6beb3987a62e8b5a4c52dc60e01	1574537060000000	1575141860000000	1637609060000000	1669145060000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_wire, "timestamp", refund_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	1	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\x26756b99c87c8847256827e19ef3fe0982c6f0e3b22a321b7af58e4560cb19ac	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xe8c9c9d765ceab2de6c93f4f3a5c80fc2f2b7dc5837a1009e1dbcbf588872e5e8a346bf90ea59b2a81dc1fef53ef3e590d81f609913ce4d5ed38123c2031ec03	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0e5ffa3607f0000cb50254793550000890d0084607f00000a0d0084607f0000f00c0084607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	2	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\xc34b9719ba69b9e2a5c6538d0990080b8df6e8894af892016689b7554d7e50ad	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xfd28f8c21005441ef02d1148f0a55fef62b4a7b53db0b71e3f18f422ff26416aa75da953f52a1a6fc1a2645d445dee09a8ba47c37404e78ccb388200f74a1406	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e085ffb0607f0000cb50254793550000890d0090607f00000a0d0090607f0000f00c0090607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	3	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\x06ae0fdcc0b8ef0f97b24041c2e23cca8c407b619aaf5931f91698368459abec	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x11da0388afeb1b37fcbaa2dc49a74e0cc2af0062d34f07a956830b257074b08502201749c1470f2a54bf587cccc307e49f7a12722e9bd8f80509d24854290e00	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0d57fa3607f0000cb50254793550000890d007c607f00000a0d007c607f0000f00c007c607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	4	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\xd2fb802705522fe06c6db4494eb28db9f103db5a7c81b91bb9f8a1181b9baacc	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x8edd932d5faa57376b96d411c43135c0de52ae0b91a989674c46557d1c7a93f1204585ed7f4f5f295ce73849ca31c10dc6bc933918b83ca4235453e262fe5d03	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0a5ffa1607f0000cb50254793550000890d0078607f00000a0d0078607f0000f00c0078607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	5	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	98000000	\\xb275e11b0d6cb259e07455d5961c043bbc8e9657af08ed3f7852f1d3d7376183	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x09a970b0d9e6ee2abb8c89bd85795a331483efe75ecdfcf22fd4c61448ee456a86c2a08aa8a9512a1bfc5117e37f91bdab54ed9b894aaf363f5d35b3dcf33f0d	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e085ffb0607f0000cb50254793550000f95e0190607f00007a5e0190607f0000605e0190607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	6	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\xd49c181a1a5c6d88e1f26428df418503c40544b5620f8d0d1e999bce0633909a	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x7cdae72c1c22745e7f3a0687d94e3bdfd04d298b3a1a234ac371067ffac156e458f563d8b2b8f8e26eb0392df6d27597410c5f1fdec2657550931548792e2e03	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0a5ffa1607f0000cb50254793550000095f0178607f00008a5e0178607f0000705e0178607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	7	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	2	20000000	\\x6c215358a41312c4714c559bad8d06239195223bf260b393784ea020da406ba4	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x7febfd2d1c67b3ecf3302527526a9408f91a99512e6cdba434446771b33044bf399dec5b57c8c6030a12b279095aa14421ad58e5998e9758437c1bd3154ea503	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0d57f8b607f0000cb50254793550000890d0068607f00000a0d0068607f0000f00c0068607f0000
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	8	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	1572119069000000	0	0	9000000	\\x1db4612ada38d763b5e6ddf9f3848012fbf6527ffbb2f939cda61f97a5eccc76	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x08e8c62cc9cf99518f71b1148929853e8412a3fb730b4e2381d288005c33137a8beac6aed623a407e2e4e81d8c4248bd1836583c3e4201f9704e8e46a06b3908	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x163513da607f0000000000000000000042cc07da01000000e0c5ff8a607f0000cb50254793550000890d005c607f00000a0d005c607f0000f00c005c607f0000
\.


--
-- Data for Name: deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits (deposit_serial_id, coin_pub, amount_with_fee_val, amount_with_fee_frac, "timestamp", refund_deadline, wire_deadline, merchant_pub, h_contract_terms, h_wire, coin_sig, wire, tiny, done) FROM stdin;
1	\\x06ae0fdcc0b8ef0f97b24041c2e23cca8c407b619aaf5931f91698368459abec	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\xfd01a89196aaefa6887d1f52deac9af2db483f44dadc4624cadaa2d4842c636db80a93a1a9061a5288e511469b83b1d18aea35ab74119be5db94e97a6dae6307	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
2	\\x26756b99c87c8847256827e19ef3fe0982c6f0e3b22a321b7af58e4560cb19ac	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x342f907942793c6f8a8c708929875f4806fd06febed7a5e598009efa32339d0175ae7b8832f589afeda866c5ea73857620c135fdbfd2c76548989bffc274480d	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
3	\\xd2fb802705522fe06c6db4494eb28db9f103db5a7c81b91bb9f8a1181b9baacc	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x87bc91bf703ae1778f740cb1e4f86e758b623f1cce16531c2650ced170c6f254116d4f8e097967b632f12222e7dd82a4e5f59dffa0ef3c0eb44f07c99262170b	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
4	\\x16fe7ce177a5088cccd1b2de7c02a5e26e70be059ecf02c3de098ae7857bc478	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x37ab4a665ac51ccc4a00758a76904330ad9bbf12b23c4d64d303a73977637caf91f000654a1d1426e8d7487159a686fc785ef97da9721d4261d2e9c7ec041b00	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
5	\\xc34b9719ba69b9e2a5c6538d0990080b8df6e8894af892016689b7554d7e50ad	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x0a231aa6dca4e2c7e9e39529731cb98684dbf519c7548b9990eed87295b20afb4ffc5c0fbc74e0ea50fc0a7e499b29bc27cd5eaf4217ae2b10da35c9d0d1fc08	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
6	\\xb3af1fcd3655db63ac43a10ec99ec8cfde3ea561951df5fc1f13611ac9a8bd74	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\xfe9406a116828f5a845ebe45b7fc0ad18bc07a8c93752a2b993af9f04b977b5f1f9a195418dfdcc8da4218216f074cfe675d7ca34142ca01463b5010fc0b0208	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
7	\\xd49c181a1a5c6d88e1f26428df418503c40544b5620f8d0d1e999bce0633909a	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x6790bc63a8f4218cb28ba51c3248da1a498244b472f501264b1573709eae496dcd0ea5f9798570aebaa05785427ea58eea60ae3b42db891ca00a226e39378001	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
8	\\x6c215358a41312c4714c559bad8d06239195223bf260b393784ea020da406ba4	2	22000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\xa567969bb8c95505665aa2074eefc2a131511790e9048289621d5df29daa0008748a88e8478c0bfaa991b53dbe53916a23cbb7e998a8d0df4f582a205a072202	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
9	\\xb275e11b0d6cb259e07455d5961c043bbc8e9657af08ed3f7852f1d3d7376183	1	0	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x0e5eeff92abf4858db8e94774926700cfbd5015fc9bf9df78aa99038140c5ecbf91eec523d48153bd78c8ff868534fed77f0f799bdcae3fa8d7de7085516940a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
10	\\x1db4612ada38d763b5e6ddf9f3848012fbf6527ffbb2f939cda61f97a5eccc76	0	10000000	1572119069000000	0	1572119129000000	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x91fc17bbc0286ba3d9ba533a6964115f042a07b7feac14356cdb0169be4ae3cdeeffd78fc2dffbcc20c9f4c788e0dc3659f326729b90e1452860e7f31bef82c4	\\x7adb5107f320e888a4b0494e1711215893c5476ebdc5f1fa4c0b55ad848452d86753c620f0a8d987dbbb5255fa26f9cdc9fd02e098c69ea6e845bce272725e08	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"0RTERV8CPEXPYXVXEASWZKE1WQHPACZWF8HNZN2G09PMAYS3Z4AGWNGQY15YTY8MW0ZC1RRP6AMHMNY2AREPKN69H12MT8X0SVKZRV8"}	f	f
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
1	contenttypes	0001_initial	2019-10-26 21:44:26.669487+02
2	auth	0001_initial	2019-10-26 21:44:26.692738+02
3	app	0001_initial	2019-10-26 21:44:26.734312+02
4	contenttypes	0002_remove_content_type_name	2019-10-26 21:44:26.759073+02
5	auth	0002_alter_permission_name_max_length	2019-10-26 21:44:26.762023+02
6	auth	0003_alter_user_email_max_length	2019-10-26 21:44:26.770662+02
7	auth	0004_alter_user_username_opts	2019-10-26 21:44:26.778843+02
8	auth	0005_alter_user_last_login_null	2019-10-26 21:44:26.784164+02
9	auth	0006_require_contenttypes_0002	2019-10-26 21:44:26.785351+02
10	auth	0007_alter_validators_add_error_messages	2019-10-26 21:44:26.790851+02
11	auth	0008_alter_user_username_max_length	2019-10-26 21:44:26.798574+02
12	auth	0009_alter_user_last_name_max_length	2019-10-26 21:44:26.804687+02
13	auth	0010_alter_group_name_max_length	2019-10-26 21:44:26.813664+02
14	auth	0011_update_proxy_permissions	2019-10-26 21:44:26.819608+02
15	sessions	0001_initial	2019-10-26 21:44:26.824319+02
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
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x37bf78fd1da20661beb3f92ef54d594d7c035d5f5506f07054930f9ec19f9de43d2232822ca047825615f7fcc141a723ec59ed913a6cfb17c33f48b349305201
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x170ecf1e2d9ea7fd9145a517fb075650d57af775780bb88e3270e3f123881366b3ee52c1930a830f786afa8732725d380ce800c6e778d4f04ac9d0d784d5650b
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x049f4a21e08b776c8513e6a9d6961fc99acc2a7b20ac620f808134dd64f5745e990ea49d7006e9a58478a78249b10e3b55f7e648a34fae68c1327016d2c0220f
\\x604409d15f2fa292707253440b8bb0b2374f36c340c331121704c0546c87a5c1	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\xc65dec7b9d081b517979d852b6562971d8b03997db2183ca8ea6f2516e57b8dcdcdec63514acb49ff0b8c73b36615cf45bbc50cd4768a3e0292c1c6626f75b06
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x26756b99c87c8847256827e19ef3fe0982c6f0e3b22a321b7af58e4560cb19ac	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233741374638393232444145303530344237344144413942413432434436433343383839363933464536313732464231374445343736424144373032384146433637364245363337423830334439394433384139413741463035454341303333343043333930384532383034423931464344323836433534373743453632383445393943374646353042344130333932383635414535453342333043423433383846334142384236363131383535464133394230434437314243373446424238303042343735354233423532323441393938463936373736364643324334394437454141414345313931303742384437343530394637363236324136433946393223290a2020290a20290a
\\x16fe7ce177a5088cccd1b2de7c02a5e26e70be059ecf02c3de098ae7857bc478	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233434353337413536454541323735313146463334353036334137464636304441413435463344424436423835413742384539323242353843303532453939343634454546354244383435423734454332334146424334374638363236303935423537443244364446303645373633313237433643423335304536304544364635363935423931363936323232304336314132354430343733453443304539353734313732423642323133414141374239323837453330413930463337453632364342463146424436383138383339413134423738464142423535384644373937424234443133414530394341363931363735313244464235323131413030373523290a2020290a20290a
\\x06ae0fdcc0b8ef0f97b24041c2e23cca8c407b619aaf5931f91698368459abec	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233235384146443635393744373237453645374330414246434631393142454430464634324639424141383433334635463935424543314533463632363434344645443439353139444346423235374137413432384144393442353932303636353131374133353031414638334233443331444530303442423939343139443741343137434137313744394638463733374244353537434343463443384141363044354639313846373445323544453443383135443742303732393241393244303431453945363546383232393338363038373931344339323145413238334430334637334238443434353144353130393346363243444239463845453732383323290a2020290a20290a
\\xd2fb802705522fe06c6db4494eb28db9f103db5a7c81b91bb9f8a1181b9baacc	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233937363843353130383845433944364637313732444143463644334344313438333138393835353546343838334142394439414636413345444631373035363533374635433041413632463736423231393736384234354339463437334638363946334531354130423033433244333731433734384231423539373634374333354331393745313236454638313239443339413630454646353635324346463234433733464543443138454132373941363539413543423944303844354631313339363046374636323242443545373432364342384443443446363842383743453333323841394341393133304437443934314333413431333930383443413023290a2020290a20290a
\\xc34b9719ba69b9e2a5c6538d0990080b8df6e8894af892016689b7554d7e50ad	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233539423044363034363032433632443545393738353245393846363139353842383537383533344246343037394434313737413046454543354238314536353841464435384436374539373037333438303446443833374441333134344341363943324631383931444542363639374232323930314230343535373139454237303946414237383132423137453841434632454435324236354434383037413842454237463435363141303441463845453331463331413631353731424239333932364544334646323141433542463545413646464237394639344430453331413231413739413338364236433443323437344231383533363546374341313523290a2020290a20290a
\\xb3af1fcd3655db63ac43a10ec99ec8cfde3ea561951df5fc1f13611ac9a8bd74	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233236383243303541423946444343354234333333313842353544454233314230343046333642413944423346343544424631444331343435354637334544464244383936313441303030343541393336394435433743383538444335333446444430383930453531464333314238443135394131333334354243463536393044343639393043333633343944423845384133453037303645363330454438343844333646334530464235394533453836313834384136323443453738463339304337324645413730363831434143413439413539364330373742413530464242353630384234393233423732383230354344393533344644324345344532303723290a2020290a20290a
\\x6c215358a41312c4714c559bad8d06239195223bf260b393784ea020da406ba4	\\xec22e28f762e7f9d178463318cc4c00bd2c524e0adbdca3de845d2ddebbafaeb4fffdcaeac4b8cf1de4f43b107c7406c3baaaaa5e188ad4fb197d7fc3d3e0cd4	\\x287369672d76616c200a2028727361200a2020287320233533464231344335394534453132384137464634353646454636343246364443433945444533333444373136423838323231443943413930383031363444453344453446423538344534433543433041343442373543413734454441463241393232314639323546324639343241373745313444413135413839464534443931414246303146393638413635383341364243363843373637303032333545303541363730363635383334353842323938364243363531343044343134323138333836433935313845354331374534413946413736434238433246353144334232373338444237383544464238303833383046373943383346364235433243423423290a2020290a20290a
\\xd49c181a1a5c6d88e1f26428df418503c40544b5620f8d0d1e999bce0633909a	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233731433032413838303139463645384235343735453934374335314342373244323231334142433741354639444434323634454445354331443744423444414339383830303237443933444431464544433143324542463233343031303144323033343744464330423535344241394646463541303641423646433539463038423739383530434637313733383041443939433138434645373033323338394635443143444144303642463536354337363846333945314330384544384133354238383139444638443932303136423939434132343536423141304445394636433230424636334131444346323335414546323445434536383633454533394123290a2020290a20290a
\\xb275e11b0d6cb259e07455d5961c043bbc8e9657af08ed3f7852f1d3d7376183	\\x1ab56c3b2713bcd5b0fde3d46b3a59381ab26419a890de9ffc6aa8759d1715c8d02638be30d8b82d237ca76870cc80b600d2eda38957965c1db722df24473f1c	\\x287369672d76616c200a2028727361200a2020287320233535353845353231383430423037304133353839464544363733443443433437313934314335343333373532313541463232343330363242423146363932333946373644393438423941413737343145334342374544323334424145353536364446463239303234384136354134334137344231354238343935303044304534353546314336303543324332333242384637313435363542413636443936413833453746353037343342453846374443424238413239393844394139383845454538434631353044393446464444424142314146453744424139313546324437393931393342443130324446414442383135363335364334423130414532363023290a2020290a20290a
\\x1db4612ada38d763b5e6ddf9f3848012fbf6527ffbb2f939cda61f97a5eccc76	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233042334434444446444430393737304233364444463837333546443039314632383445464443393145354246433032374641313646303535373446373135413331414530413038413839464142444338433836384542344433333831323446444131453632423931324246363142433635364337353143424636434633413834384245463039304342313632363737413238453433394344384242434431333746413335423338434334454232383430313041443441333630364431313232423541363146443036343834304145413632463830443131343830434238423742304441374139313344424630374444464130323036363532424632463739393823290a2020290a20290a
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.299-0082S9JX0RBD6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3239392d3030383253394a583052424436222c2274696d657374616d70223a222f446174652831353732313139303639292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353732323035343639292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22433132304b4d415a355948393457334a41443230513258475038564d594450333833314b32344751304b3035385634374d513047227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224a3759314645593035314e5437504454414358364a533048425732324d3158515a54503138444243564330504b464a4157463659585a5951485a31445a5959433433345a39485738573345334350464b3453533951343731384d4d3631535a4b33465152354830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22473342373557304859565643525032435057594d473350363458354d425348395635513332324e3658383134484a375432453247222c226e6f6e6365223a22545659585a41525144573745374d30475359355a5738415a303241454b4a304357525459474b455947564b593858485144575947227d	\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	1572119069000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x26756b99c87c8847256827e19ef3fe0982c6f0e3b22a321b7af58e4560cb19ac	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22583334574b4e563553544e4a565350393758374b4d5134305a47514a505a453547445831303246315646355a42323437355346384d4433425a34374142365341473745315a56544b58575a354a33433159523453324637345451504b4734485734305259523052222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x06ae0fdcc0b8ef0f97b24041c2e23cca8c407b619aaf5931f91698368459abec	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2232374430373235465843444b465a35544d4245344b395445314b31415930333254443747464141504743354a4157334d50323247343830513937304d45335341414a5a4e475a3643524333593937565432395332583659525a3032474b4d4a3841474d47573030222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x16fe7ce177a5088cccd1b2de7c02a5e26e70be059ecf02c3de098ae7857bc478	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22583945334e485243594b3347535932515a54433154503759335937475a5a4139565332324b39365648354338574159514b53384534585641384a44565936324146524734534b44414b563538443436543837385a5056304b533643435743514d52344a354d3038222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xc34b9719ba69b9e2a5c6538d0990080b8df6e8894af892016689b7554d7e50ad	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225a4d4d4648474747304e323158573144323534463139415a585848423939584e375052424537485a33335432355a533638354e41455144394146544a4d364b465236483638514134425151304b413554385a315138313737484b354b4830473059583531383147222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xd2fb802705522fe06c6db4494eb28db9f103db5a7c81b91bb9f8a1181b9baacc	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22485645533642415a4e39424b45545750544738573843394e52334635354247424a364d524a53544338534151543733544a46524a30484335584e5a4d59515339424b4b4b474a45413637304756484e574a435748484531574d47484e384d5a3243425a35543052222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x1db4612ada38d763b5e6ddf9f3848012fbf6527ffbb2f939cda61f97a5eccc76	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2231334d43434236395359434e33335648503441384a4143353754323135385a564543354d57385731544134303051314b32445838515450364e5642323739303757424a4547374343383934425436315042305933574747315a35523458334a364d314e4b4a3230222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xd49c181a1a5c6d88e1f26428df418503c40544b5620f8d0d1e999bce0633909a	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22464b44454542305734395435575a5354305433584a4b4856565a38345441434237384432364a5033453433375a59503141564a35485842335632534248593732445452334a42465054395453454738434257465858474b35454e38393635413846345132573052222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xb3af1fcd3655db63ac43a10ec99ec8cfde3ea561951df5fc1f13611ac9a8bd74	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22545054485739474d484a5a3747325a5131574d57484a47363539354d533034475a374b46325146424745305034394b30423156355a34305646314d54344b35413039353137584459315039373356354a324e444e3954595338384d535342384256465741363347222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\xb275e11b0d6cb259e07455d5961c043bbc8e9657af08ed3f7852f1d3d7376183	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2231364d5131433653575651324e45574348365952415941543643413837565a374256365a53574846544b3331384a3745384e4e3844474e3048414d414a4d39413346593532355a33465938565641544d585044524a4a4e4636525a4e5444444b564b534b593338222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\\xc7639d003353dd8e4b724636c65bead24eaab21ab4feedcdbcfd1f7760b525f5a6780e81d64a89830ded279aaa8945bbc2c00dba0bf8d1a0323296b852caeeb6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x6c215358a41312c4714c559bad8d06239195223bf260b393784ea020da406ba4	http://localhost:8081/	2	22000000	0	2000000	0	4000000	0	1000000	\\xbe2356f4434a4aa06389295d59a46436b58106fe2382a69ee0744234d2584bde	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22465a4e5a544238574359535953575347344d4b4e34544d4d313357484e364148355350445139314d38484b5133435347384a5a4b4b374643424442574848473331383942345938394241474d3838444442334a534b334d51423131515236594b324e3741413052222c22707562223a225152484e4458323339393541305257393535454e4b3933343654545232315159344531414437513045483133394d4a5239464630227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.299-0082S9JX0RBD6	\\x80d672f011f6f6cc584cb73d480ec6274b45e629d96e310aa6ea0248c8fa1385	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3239392d3030383253394a583052424436222c2274696d657374616d70223a222f446174652831353732313139303639292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353732323035343639292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22433132304b4d415a355948393457334a41443230513258475038564d594450333833314b32344751304b3035385634374d513047227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a224a3759314645593035314e5437504454414358364a533048425732324d3158515a54503138444243564330504b464a4157463659585a5951485a31445a5959433433345a39485738573345334350464b3453533951343731384d4d3631535a4b33465152354830222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22473342373557304859565643525032435057594d473350363458354d425348395635513332324e3658383134484a375432453247227d	1572119069000000
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
-- Data for Name: merchant_session_info; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_session_info (session_id, fulfillment_url, order_id, merchant_pub, "timestamp") FROM stdin;
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

COPY public.merchant_tips (reserve_priv, tip_id, exchange_url, justification, extra, "timestamp", amount_val, amount_frac, left_val, left_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (h_contract_terms, coin_pub, wtid) FROM stdin;
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
1	\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	\\x6c215358a41312c4714c559bad8d06239195223bf260b393784ea020da406ba4	\\x5e4fdc4f33207264db2a4c938121aa2053367085d9af9a2e84f0ffd31dbe7fe7e5a8d83ce67d8ababc8f9443514225a2f16ff75787390485371eac7d1500fc06	5	78000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	0	\\x21690131699e7a4706b35ddd137e62bf45299badc16eba485567a489c1589027e6d66b98b755267d95a090c9f91f027dce95872e653cc1090232803494de3904	\\x53516391ef0542eb9a720a889e64760828bca1867c4e8a1377e63124cc53cda2f192ca2f2b977aef8f3d8a08bec2767e6b80076e294b81e1579415f485bc0edf	\\x97c8ffa4a07c5f40e60c9f22d354cf1f745a88a4cfb2d1b3aeef929a13c8559326975aecd6b223f3967bc277850076ca71c79fa291d524d6fdc8521d77d168dc932011d2fa13d4680be1a615cd31f1ab84a6ec33781c7ddae02e363b33b7b1ca50fae38b6ff58b60dadadf5017224b6ba9386fd8c83644ee0e71835291e2e26a	\\x816991a9699f2e67879745db5e35642f8db9914923deb89db2d5e718fbe4cb36f4f412edf3d1b925b9c9331eb70706c7861dbd434f6f77dd696a941b947fab33	\\x287369672d76616c200a2028727361200a2020287320233842353041393535463246434432363936393846313134363534413838384630364644373832323634423142374145413331353731443242443344423045354245464343383437444144444244384243414542423134463244433636393937454531333941434537344637333733313145334233363832373443354634394245313044383143373142364134353836323938434541344141464630463836323842394236343638413141303045383144373941464434324236433232394430353243334142313044333141304138443935344134353142434638374433364435433838344635323234413930394439444439453645463633424439313643434323290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	1	\\xd81150bfd21d6f0e055db7b8ed133ae20c21166bd46b2fc0f0f1ecdba593ae0f547aae5a79927676e5fbc372e69e58ac55da76b924db547cc0153981c2627802	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x123e6adba0bc422296dd75c725042627c42cfb486e1e642b9f0560d4465ffff72237229d3149c47cb7ab8fdd49c298125ee811370cceb912a4ebf4ea535e0d39556ad9e8af66fff895f379e27f52d804ee432fc32f8e95c84928c2e98b6b8f8ce0a6a5608d4847667d5abd9aa453b3424d65c986f2025d0cb28424e681f8b702	\\xdcc2ac31493b6ebe63c9730d4750b7f6ae61e8793ee9b18a77e1509425110c96cd6d498dbdf1abd5c902ac5c9dc5baa82188584574205f3be090a20b805f053d	\\x287369672d76616c200a2028727361200a2020287320234143393330373835373035363342463132414345313237453432354339453937363735384433384238364431434145394537323232423430353832463135443139353431313637464534433744333536354237324345383032424443353431463232383541333342354246464239413544464143313138433137383131394334423233413345463046463831443142323933464132433532344244343045373933453933463145363043374234374334344133413635363635453132433637324532353034424235424331433932393143364145323946343531303337303146453031323636323538353042313734353030443344343932444643343133323623290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	2	\\xaf189b8e6511e9da9ffe2475b0c0e06332c86b1b1896c445b2da2be1ee89301d0482d1c67b382e94e13733dd8f03e1e645ed56ba704227ef316babc7b8350a07	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x507088c266e323ebdd23d666c47ea76c3f0411520e945b47522e8d89635ad53e3197c2873db49c5333027fc668ca9826279b9c40a5821b32f294986f9e73e3ee9d112843a3e363c73c0c69c8902a8ec4edc5e3055d2bebcfdcf788bcf4c2cf3c4c7a9cf049e5adeb307fd2156cec6d721b8e58dd1ba64545507f06121d7f8923	\\xa7abb78f7e536ddcf076e02928d67fb8bfb237ded1ea3feeabe6f37d81260c693ea9252e1787824dc2ae02d3220eac5a931270ccf2043fa1d6f4866d8b350edb	\\x287369672d76616c200a2028727361200a2020287320233644433341314434464639324241383646354636373744454638413845453441453934384430354442353042414535353236313846383641433641434436373437344637303139423531423133344634314643423938373534393438414537334145364539443933443643394533444132374643424246423437464437434639443541314230423533454436423242413230393632323232433041463634363642443837363339363331314130373235413837344438394441414241433034453242464143343036463532454145413031464433323245313432374330464542463635363835464536373746463231344130343433374438374434433844374123290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	3	\\xe1d313634bee2c06127f1bdd578ba9c8c46cc0ada7177532bbbb04fc17ebf4861cc48e2d3e4eefe741f4526b6848b35099a5156bd96eefdcc32f5a01fdfc7908	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x4b8d75c112ae0705cd587cbdf2afa9905d6439a36e4905c500b91938cfd5f903f84456c022734cc8bc7b9d54fc804d4d4efb1423fdb0621794c63b07d0b9c1a13a8970e6d3c32966574a827eac5227f41db8c7322ef98990e02f5e9d6b60db1670a041154c91b0344b1793b3fbf0db01236a129bcc1e4e679062830b60dc65e9	\\x18dfe856a1bf38d3141fb4debd00b31f865efbad77739082575be5aa8f864cd96059d6f677c5c8d7171282500cf2ee3a1be8340bdf8fd78883a55b3b50184e25	\\x287369672d76616c200a2028727361200a2020287320234144423331323533463145343745343133383734343233314141414238454441433637314336394546373544453036463237303345353341344533343335433334454434353245374445303739314445303143393035353043363233333142334430424130454545463746384342384243424141344636353431314446343237344246333042344237383434323042424245393346413932304334363331343131453341343744314145354244353334424542423436423235463531454546443344393137374243334336373534333837364532414443424246464631304645414636414243344537303333444433363044353341373746424231383245323623290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	4	\\x4dda70b8ae82938ffa588e0c3a533e4d715683ad41df95773f816863ae5b4a38788e1b8854e5f8b5e9c72aabb448568a9ce08696e2e0ffda770f503030f4960b	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x7f3b1252fc95a29ff42163a2a78931e5692f595364869171f0bf8786dd04eaf8ac260098e44c7bd537f3db08c2f0e9f6f5e891e93c8913ae4cad861a8bc685162ce863414dda2682251450294e0583719315e2096494a06f2b63080e589b5834d5a1d58783ef62879bd4816f3e39fa488c0866469f04f27a2409e152338dde0e	\\xf80de99484a9fc01e56e623be85dc3c0f1ab0581495fa441df5e68326fd728528c0995ad5ac8f936e18651f72e1423e4fb169373060eea3b8708ecad4ebce109	\\x287369672d76616c200a2028727361200a2020287320233232304636344345433639453437334336343535333039334246303244453438393738344336444130454634353643383443454232463337464136343630373246333141393139433736343042453239333533393936353244313445413235334133394438333331364345344439303433454143353943433944464239424644303631394645354431414532304441414630443146383731453039383846363131363536324330344438443942363344363532383141344330394344353935343342414544453136394541434130383044453134413741413233393034383232434331333145433233354633463431453537433433303332343439353741313823290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	5	\\xc5b5971836f50dc742a42eab977fb80df37ecb0e0a394563b215ebc508bb17ee7c0108d67007c177a9f9fc3f88e86aa6264aaad8eb5720de9032fb4671187e03	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x38c69b4ae62541b9b6406888049166a6443ecd31773c21d370b9aba25febc6da7df299499380e502011bfb62002fb1b81cc89245497b4fb54a27b884a5c32d0b36b726b5cca535490bbccc5eb726b0795d0445e70adb96933431ebcc158ab6226754459e60c5b21e2833f5da085b801c2705c115fcebf3e0a7c1286f2843d8d7	\\xe6558b98cc93d15386cefdbf5729e108aa6302cbc0c02da95254eecfae91c0598cc656d78dc2b4e1ab46325b4cd0afece0976fd3c9fb5c5780efb0c1c16c2463	\\x287369672d76616c200a2028727361200a2020287320234239353830463139304336353341374146314543344141303242313638423837444145373437363036444434434144423237343846453836344634413943383432384143333731373235373237374139343739354634463342363745353138453645443139384345454538433931313137333246303737303543424633394145433241313032323441443131374546324544433645304338454533444130304335304330434131434631383737414139454145324142323034333343304138453535394345393937444431323130454342363143464144354145363135423746313934313532364335303142393039334143373233313344314542443232453923290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	6	\\x260047160cfbf8069211614d1277595a40db5ae13e03fbb380134415d703ffb104d7a288c7732d8e05baae3e0fb9bdac3d5f81dd4cb80c29770ba76b6c029002	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x3b4ed7cd40705ff997f1e1956375ebb946bfa8b9c0b4244f0d6386fd1c7b0da9afc8307a2888094110c3e6eeafde7824c783783c5adb18cdce0c0d3cbccf537b23db3f4d5871f340a73908e69f96cf12e5d7ba127aba464d1b53bed667d65331ea7a04b2654ed4d79aea993d156e0abde8a90dac298b4fc4c3f9f4f2200825a8	\\x68dfdce6208937fc9201492ae5a50147e246506845c6f33c29ca8eba8ecd03e83abd3cb6398b9a2e775956cb64285273d35bcbeef5012fb94d07b390e11c7eec	\\x287369672d76616c200a2028727361200a2020287320233436364430444336434134363645333543463245414444313446333932454439314146463243343138414432443044343238343944364342313146444238393134423038424132393736393943343645464546443744303546444641443435383237353439353239413243424232433541333331463139353644413331453146464646353436363741454245364634333343433345393136334132464431463934343946393841433530333831424536344544464131304232424534413442393139434341334532444343433143373233413531433743413437354542413542414534383530434230423746353138333246423938393332453530444644393523290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	7	\\xded14f50d67e69239beccf2bba6b284c28dfefa898fc3b0a7613ff22eb71b7ac1cff9b73ea069ab21fcdfa9705cae2ef668218fb40b68a6d5f51fed9dbaacf05	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x8e75c51ca80c84867bd16d1b4d20e4f8e2606d5a29562804b6fcbdcf4d5f63dc0f5736eac8a9d652b1c3f9d7af2815698fb67fb52426996ce28ed4eb49199f9fb44aaafd06321d2d005bd66f8dc3ec62c9bb1674a84b6df814dfa7116998dc39e7534e22bc31d4da2adc23f7c626e2afccfd1a33390bd0b59fc0a31a73b98c09	\\x2850025fb0f5bf91f633da51e7ef08c199386254be0ddd8c5ded5be450e9805798c62b639755e6ac3ac65e92354000b4fca7dd2b403be40c9d35a1176352776d	\\x287369672d76616c200a2028727361200a2020287320233832303130373538433645443442413630374132343334443434384246384235423636303234344538374231343430423736323036354141373236434332363341414135363031364235333342364638313536444530394543443435393246323444413442393035424636314645414331363832353230433545314535384334433532424232383330444638393045424143413635324633373138374144313332373841393533323546444443444432343534383543393233333946313739354142433846393030393333373531423633433145303244313342423738423541453842463637464645444545333832363545413745323737373137424639454323290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	8	\\xf0a003bce761c282f7979c34ed964364df1dcf6ff04b05411cda08a27c0a975e11b19b8b69c0acc6a26567ec2f4a5cee2068425387e292d8d44d0e4b327f5f04	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x212b402ee2ef7c17944caa4f9a5bfab2a1dcd4cc2557d38abdc7da40a6abbb2e0a35b686181f453fa7e61dfd2f0e6ac2ead43f24baae86807115661cfbf00ce098892f14008b3d0305a0f6a535ecebbf190496395853f66ca24ebb318a8a5b46b525d9d8a8ed53c09cc6d19738da666318f6fe97ff34643308affdc64dd5e0cb	\\x75542576d3ed3e405b86b907746cece11c79c33246e96a6af27b55aed8441d2903f1e7f72d824bbf272772d1d444fe77060c4129a420b4f72d6277e01a08df2d	\\x287369672d76616c200a2028727361200a2020287320233830444433453343354638324442464141413136323945333146324146344238334543353834443938343644453139393337333135323437324438384231393134444642463136464134453938443339423539453441424444453132463036304430464644354137353434423939423131354234393838303630353238443639453443343832453743384441383238314534384232333245353032303730323338424546413630313930314134303542394342363345324633373038453536303643364346324645423836463930383734453230413839374545373932394437323533384245323146394244443737363246424533433632334530383031384623290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	9	\\xabaf3182b924f4d17ea05ff3d6532d461fd748a11cd3cf38533444e5dc6216308f4e9724d63840e06d6a61cbf0d6add007938a9c50c49aab144286f86eeb7505	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x766deeafafd7f80c2b5237ffdb81a18f89fb497c65cdfee0aea02d9e7e9a05dcd23386883c9dd5475c5e2a5b3981f73aa58f44266c29d49379307342d5fe3dea9fdffa1a192fa6430b69f1418840688212d0f6c2f3d23bf7360d86dacca8d135abbf14af35bd16cbcfe6a20f6f4937c70a950380e624b3e4cc519c8cd8b2a8e9	\\xcfdbed7a2c794e04f8ded19c67dc6a0adf5d22b4164acdfd75a73041e81a3ba1ac20d5b8a5a56636e5f0194701c68174f5afda2d2ca70fd55a2d437b8950e0dc	\\x287369672d76616c200a2028727361200a2020287320233739384339384332384145383735333636363145344144353035423446343944324542324641383441464139433533423436353638434539424341303744443131393645464637464543453332433136453038443132363445413442313530453333374430423946334239414646444634313034334241433045363435434337414241393632384445463543354433343730413646313237443141344533374339433846323946353741433537303732383537304142443433444244324634313146373333383938443630383246434232303330423232304144343545344330323230303844453231463039383345383943343542304538463532364634433623290a2020290a20290a
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	10	\\x5acedfe78f7211d725b7b55462cb7b0dd7fd8d50630b0080077edb3b0230483080c1dfb460bc5df2e5b5bec3b53a5ed0fef085c9fa8f9a5563189e9c7951af03	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x7109316aa65603ccfb301d79717be9e17fae13cde0ffd27bc842def1db218e7693828314b1aae086f91d92159429767d798ba23214c0d69e62167465aa229319d1852cd6834f5db0c2e0afd01c1b7d1afeb6a1e579cdb4cb0fd00e280a26ec142a673fa51ab12e74346ab8fda0017c2debee5689cb9e82bf9529f0c5758432ac	\\xfbe47c641f7677c734a539ccee43cf357cb2c50a464f3adb6d009c15394ccabba366fce3b1d6adec9f08a69c54c0d0468928ff4e662ffe07cb76f90ab60cf227	\\x287369672d76616c200a2028727361200a2020287320233342304646463431453532443341453131343032424231433330463339373231463843463041393045354442433141424543323445314639433738323831433431434133383746453532414333363936463144383133443333394544424141423344383133463132343636333130383931444338353030394641313143353334353942394432413437323144393345463136463333413331414631393241443746454234433338314441323933333831443331324243344243394430323939423741344638414136443837374145454245463045334239414233434434323930444446464233353538303738444245413645333546383546353542363238344423290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\xff166b3925f5bed87ee86c137adb95c291f91baaeeebfe8567ba112a4450940e17dd07bcae12432dc4525b63a5f3ddfddf40411dcec10cce63948675a9ee4b5d	\\xe85193a2860cb9850fe0dd52abb0823e5142452442d23294049913dbc8cdfe9f	\\xd1425c6d4fca5fb80fdba42b11e5416d1b189c43215bcc4c40092b06731f156609cac57e2a25b84a548d3c4c7d0935ce7b9a3143716b1a1a9556ee48e11f1b38
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
\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	payto://x-taler-bank/localhost:8082/9	0	1000000	1574538268000000	1792871069000000
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
1	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x0000000000000002	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1572119068000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x5b686283886c27dc763ab1a43ab32db1df005b78329869e508eed21a645da14aa5fe30a3cfc218d8f9b07c89a8a42ccd43bb39ad6588b78b597eb11626064434	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233835384538443832313638313834344437383634313730304635453643413337304542443235443537414643373031344645324441313637454543464545354632333638424432364432423542454230354131383631353044424432313334373846444634463536393845454144354333434438464438433932333235414630383242303332413842343231394136443844423032373544423932353637363238434634364339323346373443363545393444313636323036323730364235313039333435393437413933363445313239303330313946333041373546354144414644453039304130303246373031433232453741424332323135444443324123290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\xb5b36463a203d8e7a3c93c0cef1f0fd889bab84a6fdddc1230a6cde7d85677e709d744f62a69424311cd464d326ca4e8d04d0c7d785109f690b17e1cd7459809	1572119069000000	0	11000000
2	\\x57a8672a0f33c9b76de132b657be10617baacd515760ecae40a97a3f12b775619d09c8c50ddebebe245a9d14b42fc344de14a4cc6dd6df0428eb6227a033af63	\\xec22e28f762e7f9d178463318cc4c00bd2c524e0adbdca3de845d2ddebbafaeb4fffdcaeac4b8cf1de4f43b107c7406c3baaaaa5e188ad4fb197d7fc3d3e0cd4	\\x287369672d76616c200a2028727361200a2020287320233838383545393038313342424642443433453534344635344237413133384136374543384331344241304241363242314139393530444434444534383933314246344142303343433842393141354444464431413433444436303935384535323043444542383733464630373830393933314630333937443446373139464236444343454434453431373332413942434141373443413542423441304631364136374635303231314233304539393635324543463136424435364436343946313241393842303845453933363332374335323730334234343441314131383939313733303142373346393839353944344537373231354234463941454245384523290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x24fe01df19bbef8d2d2802f02cbc3980d51255f41d544ca45131a5602c77ac846c37f74c4888ca5925529cd54968163e9dbff2d2da9f2d43850c74ffc02daa04	1572119069000000	8	5000000
3	\\x833df9479b036b13f044976ae2b4af75dc703615cd9c1f5656b2ef3f3237c893a6190f89633eb171f8b15609011fc45175b8ef8ffa7abc2db5184898a08282a2	\\x1ab56c3b2713bcd5b0fde3d46b3a59381ab26419a890de9ffc6aa8759d1715c8d02638be30d8b82d237ca76870cc80b600d2eda38957965c1db722df24473f1c	\\x287369672d76616c200a2028727361200a2020287320233637453630343845344143304633354338454646334244343945304142454136443938313343463836453433383631423930463333354139374439423234463031324637354132364245374230364133383445423132453239313942414242384430423537443834393544303635353630424142363632323831323241334437303438304143353641463337444343363333454233384537424131434339423035423243463633303733383637413442434233333141373036434339383535413345334635334638383145373730343945303437433138313836304433373843373146463646383038304130333841363131334537353441303937443631433123290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x45eb42a757fa7d782014b71e1b8b171d4a33a7320eeae1b9e95dfe119d3fd3e8d4c697d943466f1148b10b6c8fcc76d86f7eaa9bde629594ddec3a66f7f9d806	1572119069000000	1	2000000
4	\\x094ac7f8d7d47eb6394c1ebb40bc70bf824a296d3ffec845ada7c60e890f009e83f79c088a83845f78de576f325f14159a6d05e0db9a6cdb7a7a9d83979ec0c2	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233841324143363833364435344534453535373334433142313842453335444545384232443239334437463535444342343235414431413137384546454337384338343544354443374342343732313235373945313646303344304244334243314136383246373731373835383241334145323043344532313946363731413942443033323235313541304130393836304541423541334239444131453032373845374135343235454646454342334538434144434432413733353537383938304137463838394534463144313941384637363042374144384142443641353142433443424133423738373141334330364243383239354635393138413446463323290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x8947f61030cfd621d7bb75718620d0fb3439bb211b79a7cd38d780714caf5974909d049b5ce9d8c3563bd4cfbdbf06718aed8368b94f8c9fdf612d94dd2c060a	1572119069000000	0	11000000
5	\\x95b090d22fda9baaf6d0393bdda80087c88ebbae8f468995ab7cb8f5c806adc52b75c236d698cdcc2e9bbe61f1132ad6ca67579034eea12b3b619ef76337a154	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233641384636313136393933413636394333393044384342333746384346434241414531463646443945464237363333453144373535323036413843434441343036383046314438343243414533424435434146304145343935394144464534354438433441303036423839443337314330314338324639444632313531374142423835434244443733453033464346423033324533343541444630454445364339384443464637333530413441344236413535414639324334313643433937354132423437413841353346383633423045323836443543433045373341353842414444323544423844304538434642434137373532363831413732313735344123290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x2872e5f1bda7936731642bf795a105923c7d955595a2e41a0a89716c2fe2cf70fbf9d1de0c9c3802b89526bccd454eee1eb3b1769a1b53ab9b007d0b0a977a05	1572119069000000	0	11000000
6	\\xaf6bbc0e44aeeb5abb1dc4b8e26b60a880cf016e376a8e47db2175589036538fd5c8b722ec6c638ac42183004a6f333f4b965cb2a9ec204d6e2e516c7599386e	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233032423131353443343742313833344539313734303246373144304533314245443139453433434235313545443441333533353536314339333736423746464242463646413130393546343935353541303146464632323033383631333434343743323745453542414539314345444545424139464631433344443933363532304134433837434537464331424438343032393938353530424146343233423938383137463638323945323236373930394432434236383439433330323230463945463830364643374438373431323642434246344244313535413937443633323935394431324341444544373038383833444136324638414538433241303623290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x8a92dbe392ec70cc845da62c91cb1a2d12ac93c06aca9968447b6398ef8bb4d01ad2ba9b1f27532e9f01cfbb657873b9410f3d8555ece5d0b41c0ac4ed4a9504	1572119069000000	0	11000000
7	\\x6d96781a2a00ba094f8dd3e2cc4aebcabf648720e591b874662ab547f4d7741ae2eb38d46a31f225a8e4c84c7c32e5935fd0e5a3c26b16608606aa0b69276d82	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320234242443542353634333830453844333245423043364243313136383843314532423633383632393331303635444136304644373837383632373536323742354534414344393530374439363844324434424133324633363839414135353433304337373341334330384245363438453044323843353445363043363337463643303342444641343345464339433032304635443330453431463832323137424638363739323339413035373537343335324341343533374233313135313939423444444539373238434331374237444634414232323443304537303232333636463944333933433431434538463730434437313730453236434533393932463723290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x0b344f0efb5790025d0110b398f2fe4986adca400706df15d6b8c71b39858ca07fdf5fb819b97b73565009cbf30d9b8cd983fa8835c9550b02057250ca4c0c04	1572119069000000	0	11000000
8	\\x08859b7315db1b440a3bac64e42cad3c850d4ace057cf0415b737cb9c21af45de4e97ee146aa45f5d6cc35269991819f04ee2a1e5b454be7bef81af82edf7a85	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233443374444334546313830363831344238354338313045353630333036334433354631384539354635364642364233363131303442413541454331413842334331394335314130453243353834433130383433373838423444303838384630414644333830443046323331324632443437413242353131313045364141393738413043373843393330303138324443413030393245453237313142443737463930384231313132423236433535393231314636374445363139463634394130443238433534314542394635383939434533464644394332303343443842343043394431303841354535434543323233394339353443313831454337393934383523290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\xc3e60f3b1dd0485a381d88e686a8d27e0f49f4920b16fdf0fd9b8c53cf8606436e39c620375f43ed22bf6f5dad5184f0efe65d8b6c95c1dd6ea9fac6fb84f606	1572119069000000	0	11000000
9	\\x3925f244cfc5bcc19662c098e2f5d5b9e2f0f81015a48fd41295b97249ce37e86bcfaa0495bbd99f23300e230414c0bf312260a54dff2c7e30913651660b7740	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x287369672d76616c200a2028727361200a2020287320233544363631363031433833434439323536444543393643413239354132373844364243334432463230393536334646463339353542373037313444314446433133383337374538304136383833383331353630424444304233383142313430303832363130323646353141353144303445393731383330433631413536413044454342414643363542413837333936434241304137374342393735463534363637363344303746313130333839334335434635304438304537304241304645383946463132423530364244364337364234353638323641374136453231443937434245323344343033324235323335323534303845343536313734443030424523290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x2a7f70b69ec830beec95579a094df78eb9a5257d9f1b38d1d52f4b031ce9ddec716ff7a738a6af240f1fc954e936e8b1bfd31d378ed5ae5cb0755d427383f109	1572119069000000	0	2000000
10	\\xac4d3b66ce85804af2ff3585b122d200f10c7d80ca83cc12309adbbb902afd0b9dce9f96f50002f0635006f931651cfdf79481877fa5c27134509d17139f33f0	\\xa9d65cd740de39f11c297a615ab736cd552218af2dfb98e2f7af79c330578501f07c9e3b36bcfdee59a27a961511db3952fc44228dd0bb16bf8930c14bb2bb0a	\\x287369672d76616c200a2028727361200a2020287320233734414637433230463439333343344344374144433931303537413343393630463646383537383330433730424243333246343639463334413943384445423139303334443033333243323931344236423443423638453441363238343941434338363244453631324243434634363644383939444136394433313039314230393733444138313832334544443432423942374535463933304338333932383934423436433541444145434230414130464332433945414234313932433230303135434539323330353331373241344342393442443138393633454239334331353337353943444532433745463041323032444342393133414638304343383723290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x47cd4b2cfdce3e408d6a00afc377159f03813678c967cc7bd8f8af050dafe0beeb4d63883a58fa3f582db577210f691ce7ab3deca0b172802069aecad9ae2706	1572119069000000	0	2000000
11	\\x10f6d239860bba714328e4666ef123b55bf08542234e74598d977c86afccc0560956c67996274e31fdce13c3000fe6ee03abd8cef4ca2d7c4ea4f09622e71c0c	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320233033434334444430354531333436324441393134363641414645334233453546434644434338443830394646443432443039413744373138423738443938344333443530324238353438324134394336463235334339464442463146354531333944384345324531434631364639323330313538443732423734463343463046304343384637334231454239314631383434384136343145394132433142433637373436354244303130344232303846443534434332444144454336453246354346424630424641443638393238304438333646343432303536393139453237433239323435393431374141354631453537393234303944454246463745364623290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x138c069fd71a42e7a52405dedd4e840245e3be75a927316f8ffc5c5617d1fa384580b782563730c14f933061422234a3fe0862b5d95def637383a160fef79700	1572119069000000	0	11000000
12	\\xa155ffd36817bd86fca3cb980075f7df4a1728f814ea237711efe77933f5b206616be8e887db72e385a865f1960c99edbb988edc58bc4a91b66bb4ef7ab9ac5a	\\x5e13be035e84f2681c9700f301c4aa0208fe69d4166893d26e3a7f3d77c5163068c274ca1a31d2f66af69810664768b7d9fd53a12e7999031b0d31c7067eb667	\\x287369672d76616c200a2028727361200a2020287320234135453633413437333645354345434330363946423638393644364335443241444442353530343331333545413531303343444431324345333843323535314544334130413245364339343334384641384244383245443434313335324339373834374442303043393032304439363232434633464436393037443234384539344532303143373736464538463635423741454437353744423545344130453242453932433136384444443938354146334341323543334238433242464545464332303031413732374132443134374534333236303030374446393233433042443432343136333144383845363146344242314133453530333235323545393823290a2020290a20290a	\\x7292ef36a1ca0604b0bbc4800356f745e878f741d28ffedd07f1f83916e56507	\\x1ddd14f9b5f1b1eb8d1028dc9d68071d2805a2cb915678a83da95e9e655552e3495467789cdc8d9a51230080b2109d53b555884d41760f3a1cf2c88d786fe50a	1572119069000000	0	11000000
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

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 2, true);


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
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 8, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 10, true);


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
-- Name: merchant_session_info merchant_session_info_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_pkey PRIMARY KEY (session_id, fulfillment_url, merchant_pub);


--
-- Name: merchant_session_info merchant_session_info_session_id_fulfillment_url_order_id_m_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_session_info
    ADD CONSTRAINT merchant_session_info_session_id_fulfillment_url_order_id_m_key UNIQUE (session_id, fulfillment_url, order_id, merchant_pub);


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
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

