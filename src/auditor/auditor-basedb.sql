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
1	TESTKUDOS:100.00	Joining bonus	2019-10-05 20:32:19.338742+02	f	9	1
2	TESTKUDOS:10.00	HVGWN5PJ996HNTEPTFXNXV935MXGSJ7BJ258J2653TSCBW9FNJDG	2019-10-05 20:32:19.483134+02	f	2	9
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
\\x77aeda0509631a96dbdb72f918f55358dbde83561b3d0d974a041879a92bb5944b1fab6fafc5476e15c152580311612db52d0be2ee787d6a251ad5ed8ecca26d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x470165e7b297f0801c73553658076447c6fdc80db27f83178ba07cce25bf89ee12dad3661af52604aa8ccb5850d1f37a2f36ca67f34cbc20f955c8ce94cc6a84	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x417265d8feae2e583a2c70ed1ef602c65fe496c0e25e46cd97dee99bc6a68206186877fc023c4e86e60166ae6be28e58ae0c36af13db207e1e7d9a423f014c4e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5417f6813ec73ccac9e0086453829562b60467d09a2a1d15a64efabaf0739e7899b55f2150a89a45723786f00bd737346777411ad80942ab7dd5c18f16fe4311	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2028ec91591e78a3105a35f38f3280c3ede8bf4d18863835987518a8e6638608c762796e0dd5a579587b3f41e626739338a8f158d7753c7cfcb89242d90a255	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2801c65f238bf5cd13e419c396e5260f2e24a7a723056795af6442b6e90887ba3e4fb1a9f290c319b08c61d1dec0cf72bcbff789929b33d2f563705a57e60620	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c2742f9bf9c72274821537f4debb36825b0cf38ed88336069128e941f34558c5d7c7a77afd2eee7f5f1cab655cec33e1631c2b72170c9613666badeef67d359	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xec8a0efb0d403448d3eadd095ccad5042b4725abb90f2e84625e22dca307ed61404367c34e4b974dd39acdffc223762a123eb23788dba1db514991509b19140f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4434409b91d01a206120d881a0590a188e5dfe9a94a6b034fe6768ab5d0cf5f5dc767a2531bc215c35ea2f7e8595abd947189bbcf3fd6240437bebac1aedaf33	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x82da0c58f5f95542b816a019735e2949340dbee1bf0c278274d8335d1eb72029a26e6fab95ada8c7f66a1e7fb2ad51f23927423471b1e03be01cc22c50a9a634	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x26485f3be7ac12f4647de2285bb93eaa1e0eaa592447afc6df422b6c87ea85897c55dede7e1400ee172985f60561a0fba8a8965bb851937add530ff330ffa7d7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x305e661f0ab10f3bfb050662069cc122f06030e41df819cdca3ad507cca7145d2b8fac275ebd67b235e2dcef12d4582854dc9e3eea95918b3e1b3e50753110c9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb63abea7f4db0a2f09399a4e5e45178e28744d4ce6eabf02124e355caf74ee165154f4553c10a58ad9075bc4f3a063be2b34eea010ddc1166d12ce7fa02eedcd	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd479895dc25a4ab6b6662e537da73e697a7abf8b765caf786cef8428060a1ce7a9ded6b946add6b2ef97648316baf540f1e11db7b1f41b961be211025893fa15	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x743befdb3bfe7c7d9d25cae4cb4bc71a85900fc8982cee48b33ec3491a6d401c7d81f31b437bc1c74cc5a98c17152eb576a8014ce641f674c43e64894ce3f52e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfa9ca1ceb8955ea9af3f1dc6798b73d331e9c430e195df34023fed7d304a7187bbd635b83e0322f23314e7a7e6976206dfc77459636b50fe38a2eb7d5fd06e9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae2656c63d5a56b4774945e6ed5134823b59025667093f0d0e41d26fb5025d307365d4ba6c341da5db8c5fd128248d3dda993580cbedddf4a06ef89799288391	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2d5222388f6f9fdb7b185cd3ad2cb6f144d089d3ba5985fbd947244587942c9ee833bb2d9b7dde1679ec3d566ceadeeb506d88c3b99d7b99e7d2a1be833eaeed	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x387bca463b3a8618544d5506ea4c274409fad6650c642f7d1e9a230a9f85cd2fa698114e575c3b2689c5c03f83a254bf82b6729fd590f88665ce4b9d27ce85e0	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf77236c93d954889b43c0de4fafd432e5fba45ee50f8511a2bb311b552295c51d9ca1609fc9dd969cf30b8271742dc6c85a5319aba6e72189f2e1695cd007e5b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x60c56f84afed693c221398f4e95f40da9ade1f7ff5e96c9af6f8106ab6d1c7970d8dec31ec697774aaca5699a2aa81da98734b3e764ecb37a08a82169461a670	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc01ae7fef69c484e0a2bcc6d56584b8845ca3bce0e14aead004c80e77112cceb407bbe541aed681295a4beacfa5eb58ef732874136af2ca497ade451e0453041	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x67c44c1b88ff7de3c96f026b7224d92130a11cb3b4616a2763188a866cc260c8b16ce3125695608650cee3b5a3c6c4f215dbccf1a70d26660a94a253b45ecdb1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4fc17a0891ef147b288e00baeb1636cf06d9d1d99f94da3b4c830cfa1f5db61c7c384d53608c511ae9d86b1e1873d4798c00a8217470b54e265578e209b3acbc	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae6bb0cecfded829e2c692711cb7771c1456a9b1bdb8cd3e9c2ff87172722d3412e678c821b973b9f6ad649d481c476471559dfcd84f929cc9691af6ad4d2993	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfe4b273403f2334454738fd600e3ddf542364b92cdb39553d51bf538952ffea970ac2401757ff2d351eb2aa27d2a517e39176d7f3a1b07cec9a97a852817a686	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6c571ccf06b7a169b25d0b1a6ae214417bad04a489a9c657b396d645b283d52d5a198400d7a74e8a2fda9b8c3abf9cb6f5689c92c336aa229486cb6ebf89e177	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x93738f957fa54783c70d7cf838bd844e2f0d15135010b60e498358df7efbf1f8fe6ab33773d3344c96d0823c56687907107eb08959578dfc5c181a76fca61908	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cb8907adffb8d5d8f484cdea04e02800c0e8acac2555d8a429ffe11bc2bc25e907eceae6c39bac5009f72f971f72e12d547359be096eba4ca355b81640c18fc	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd64d10e62f0b9bf7a9e215f74c8a2cf6735aee6b4e897cc39f3b6c62b90128e93b6e056b6572a6420009309870e6864582617288ee03d87c6ceed3eb7c73a2c8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x59a113d744fb38b3aef82336e6605d1315e84165b06fe5cc9fa1e02befae01176926319234853fc4571934282e7eab59bf8e36b0f307a1d5abaf9af086ab72b8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1bcd66be17f852b517093b721836e7624b2132aa88da8d21a4f472b9d0e4804fa3e7314bd3565903603201b42a3af5f276d7bfaaf2bd695f5e04fe8ce5b26e98	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb53e3e4c8b38cf7d4fadefbf7e86b14b8f0e44ce77b8a8713bcb13e80c0f27b5e38f79b5d5ad08d4a3628c168540178608fc5f077fd0b47ae09d9f54b069378e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdaadc565bcea053656fd90e9037931910e4e19fcdbf2523a701e8b44f26ed795d76584e677f01f608b6ad5458609b2a4212ebfe213bebcbb0940e6688f1d7fcf	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x590334541cd74de85faca38dde881b3bb3cd2c3c3b9e74b361ae054feba6c8662cebaa5974ed8350729a26fdcf8ba45bdc732377749b7f614d63330943ce15ee	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x7cf83c3dcf9ecb16743a30a94214977cbcfbff135021d234971003b149d6a0432839dbb81bcb22edbdd511ccf725b56ce4dc90b5236972c6a4dc83f663a9565e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3945e9889484dd9cfe7c734934b4b67bd055193181df19fffa9e780f087a369b177a6010d951290f4e1e9a8413e0b102699e848e68f1ac7be185b9285d5dabd6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8ff3d2655ce8f9934b0e5faf76467e03cb8a968aa7f287920fb936db34c4c39eb2965504d7aa354840bd19663ec9bbf66b5eadd81ed3903d41eaf59541e74840	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x05021f9d049d33b6654be69b40d6af3bae8d2419603e212a40ae7f596d300244ae1631448bb5efd7638ce8fc35abbb217fc6750b43b25ca64fc5815faee49f35	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x06191252f8a0cae31ce8b2c5377e6edff5259a8205e0ca1a5c7340c1d68798891734bbc99046e99052fdcf122518f6df2dd6afa99a92ed22c5dbdac99dc3f7f9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9b2611e933f43752ac9fceb49eb5868245868fb51ed3aab7198c59d566abbd31cee009401bf97abe7d67d47b12f142e65ec2e32da141c4f50da10b1488458cd1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc5998fe117d75f0241a053e2f3b4dd4c86bdeb6141ee44e22dfeb96da6348d44f3638d771c3b5227d1dd1c316987b97f343455c2cd25fcd6035ec2adc2a474ff	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf2582dbf9e71549b50038d9d2cab175c24d5ad5f913eeb358c19e4afca5591bcbc5c8306aa99e52e71ff04e605b18a97e698426e770d2bbfc4f4b8be9286b4c0	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x2dc2f8326938d267c7c9a170a2641d10672d35979526ea84634506c2b41fa7a401b4387bb7229a4b1469bf0676edcc6dac01b3f8d2feea1e514838c9f8b28478	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5303df86df34b607a9cad4cf7c153ed3120dc558909ab596891e16959dfd58e95f5db314407543d562bf49187263e5037b4b3302d45aae48fb5b62e05774e55b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x491bf17a6966893cfc3fcfdce40163d1fd64adbca1b8a6e7dd2e54a88e95206cc60da16915666e0d2eefc97607aaeac45d7b9039cea7d7a57f9d9a1fb1c73d58	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc3db3cf503b342f46187dc73bb1d2728b485fe436d129f9a4834dd5526483a5e4e775f8b73960090fac6d75e6d67b272d14976d80044c775284e84e0c4810b15	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xf33aad4e6c561e8f52d23a5c4fb3c459b1573e8ff8b1e329b2c186ad86202f6c34bec77eeb73c5babc07ef056f8153b3dc6e273a276d6aa3692f1212307dcf6c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x18cc95996ad80320ea601f22dd0720b22f70e725714398390b2e193d67d7e7eb84cce141feb0ad20c6e73b49ba200b0fba573053b5749122e26b3de6a090863a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x21a643750405b80a154b5c54f5477c5460737987b0d77d58966af1a6af18faaa2042244a46ee2df7f3b51edf6dcfd7bc11a884af508972bc037a6d21db6dd8cf	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdeffffb8eb405192d757561e60519940e6083da9883ea1b65b6749179b8342daf1352635020d03cfb4e0f544332a3a64b8df48a4517e263dd5e71ad8c8278dfc	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc672dac1f1160720625db778db7da4787744f058f437cd3e362c737d90f51d029c5db3188a0b188a928ba9c40f461bed07299edf112770b489006b32b4cc36af	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5449e9b0ab9f48c9246ba843808ea20ad716418ce69b1c9556c5a55a44f915a1b9a85a870f8d55b5e010a2e37d99aef2179a36d82271ec18657cb61887703964	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3109cbe1a07a27f0ac96490ff92c6ded4b35981a45a1dbbf411d21ae692da578c61e5fdc7e10a344b7fe81b6f5a1cd5bcbae43108d82d900f4243645ea977a51	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xefc59e0b65e78e70d0a892868715058f9f7e4edeeb4046a772e6223b98e6e61d2a96b2701b0e5affb61b7a1578e17bb83b406b705f1afcb221dff73f4d47481c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc27f790d5973c867a6fd1b099ce5fed829c7ff4a2fa7683ca8cb3d5c35eb5092df4f14c78eb6c6911f39964938cbcdc432ed48c2890f7fa686378fec2641e86d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1e2f477d315b13ca047921e1e38a379e6232a9fdcee4c5f824077b1155829b9672cbf603dbb46feec54594d63d0e6b41210c27f3c57c90cc3f2b0c6620d20913	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x03b219c23337aa1e5538004872da5e4fae476a3608052f2874a33470ca0d543888d0e664e61185f2bae54ad6f11e96ad3afee27b887476b45428b260ecb8d4d8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x982713ac3951c1d1c5de31959dd505a63f5de366968bad012ea22ed5336dba6461e8585a5c9fb0a8bcabc54d321cdf42ce769e0722992e0c394eae45a0d191a3	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xc8d022fbe7a932b5de1827e20162692063e19bea5c022a60058f8cc341c676603ab6a7e6085216b5c2da965dd1c26bfc482874bfa0affa6231a18e53fc120258	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x1c84f22fb92778373a2b7310a08e0405510b4ad311731def7c620457fd69f0b67569041c8cb1cc581aa10f9051606041714addad428b7930ea9a62166e064af0	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x0f44af779738f5f77def718d814d14f8205abfbac94c9676f721bdbececf1abdb068fd2ac6657bcd903bd157a51d392c53fe2a4163005f6e56f8cf3f8ff5194f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x34d75781b338e8e65a0d9a21b06cb361eb50782c3a8212a659a275842478468345763dabd2ed1685b09e11ea1675b95cdfd77e7064547900233548eb23db3ad4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x9110881ce87ada5a0471fcf1a3492959b43bd312fdd92a5bb846c8c96052ef6baec3c726d5b90bcdf52d25cdf4e93224b4f61d871f17b80a318cc0cc4106a8ab	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xa65d26bf6182a20666fb6a7b016578e0b7203dc060b37d5236c6236a01c4cc05c89285897ce4ec1c4daf469156c4e81e63466b4d8834c7c7df43524f2c84fd54	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x5b43ff319d120466ce5da993063a19de10ef8e3f457b9835cf3c872096b22fae1f55704d88798745e0d82b8d715aabfe0c62597b03c965e3a0553d0d7807d3d6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xb0f7ded2ebc65665220da9c5af7d64bcc1faf1cf88b3cd3bc9f2cf79d507b4aebb847fe84aca733fefab40a763a880c8b7165c3bfb3f75f52b601eb85eba237f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9541f9ac9a24195c7573e6b6280d2c55099d80b3dc4260b2bd7a2d9fdbf6ebc1e28835e7b85e81fd221abd92ca8369634defac10dbc1552edba4ba85d53b3da4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd0e0ce1475ef744de5296ede6db790a52bd47dc63efa22b5de74c49068a2be37a2474f724141ab345408d0e1747dd71cb498ac47645c144bcf377bacc8708102	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53f8603c75e27892ea09715e4c46cabdec59e1e091acfcadb24e6e680b8bc25c2b6bd3456725b557a7416580e9be1702426e6961a14d028c915240ace0e7ad1c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18efa06963fb57467776a49c643dae92c7c63238c3ee859712cab9b074dbb9b8999b95a0c30269218478407f0e971f167e6a37ad95e27a109095b9bc7ae35b13	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5591beb97d2ba2e06d90646378b9457d24eb0db243a5bc42bf9b4f3f7ed6b8ce2c0b985391e4ad00acb70a22b95f212863898863100bcaeddfa0c145353e396c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4e45f7a8f4ec2cb52ac9a307b604eb4999372fc2d2a4e2883a21daab0ab1a18445e31e835d04d7a3c4d2d2186600d17000d052c7c409aa084650825f74af8702	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x611ef907951cca8ab4fc6071eb36c59a1cbbb6c0119253b486117cc020b0d70c0c0a2ef0a67372b581ba10206eb6c0cf4255d3effabf738356b94ec15199010f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x094bcab791750f9d822454bb2fba12b2054b9968e0809bc88df5c75ee7e5fbce436723d6d65e6f73c512489df8f63024e35f28ac075c5f0440ec5685375a51f1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5030e222e980e0f97b3cab6e1fc641889191d835ecd8e717ae62ae12f451edf6d92429f54d4ee1901a50230a465a97391ae802300ba24645d28523f02fa36f9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbd3c4438af650d68b511da485488851de27139684e58d2709f0df8178c2cee7ffffa53fcf7a4962486a29863d1df2a6fcd4ad840409f96f7c59c1cfbde3b2c79	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x52fbe6f1e76e9e7b76d950df146332de5569cf90b08d93df3637826ce58800f2c1348aa9bf117c9fc04c1ea651ad296454f8e864069e00bc4a61017c92e63c15	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xef32c4cdfeb0c6ee6c8273fa978848783dfa7c689e18b2648460c2dd589d5b229f95ce6bc3b92ab226bc1fe85decccdab246eb1c50f8ba383bd00b93d9854c24	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf2a11fa6456ad063d767f942cb52da7d002404b131ec769fd724d8363caac55a3e4f674daa99d5e19884395ad090ddc323f562cb23cb52300306d72ed5121060	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa95c2d9e8a44b366be77f4447096fa4793cc6167f309499f2520f85060d296ce468e80c921f8274a932aec3b28478227677983183ee49f98c595be2b877e79d1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb93fe80b3fb275c8b5bcfba39439d6f2d2e3798c3632279d8f9ee55c5d56f5999ed09fcf0d6c892b70894f46357d8b84490fa70ea41cff6d12f8ac7168dad37	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe5d6da26731ceb2b144ab38de720d1009aaff3c0f8cfb1b9760a9e0b6ed6b1b7ef12df85552a926f0721e0060a891df35d566ead70a51dd1645a0200b0608e14	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6e9fb410b64d741973d07c07311c46d20055fb1bb9b43eecc9449246989f984d7b4042e73fc870fd9930646737cfdf760e09fbd1a624d239d87a54fbde7c325a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc13ac2eea3f4731586ebd00dd05ed63c02bdb449a4cdf1fe5760729fed313f66bebed646016c1ecc40cc215888ea8ee87e8dd5bd659ea77d1b635da3595cee91	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc48db57fc9546348c600996bd37e113cb6ca6bc3f31236e0540c8e8ce776174681de912c91033478e91bdb8d2797a532b60c3ce9bbfa07bdd3c4ec01c5454103	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5c9a23f87b168958246bd4fc17c6816f1cb38c216757839317353773271df08d1f09c6b3102b700d76e67607a0355de5ffc806c5d5c30460427d7cae8f98a337	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x523ec1ca5f15da26564f763692452a2115b785070320ad1a527b82af8e45961d16e11b0842694c0de0be5c8e7606e2d360e4444aaa9abb6028aa7b97d052acad	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa474db3e929676c021f4a63d937508009bf6a19c0b63e3066fdaa391d159387fa01ab0242dc01eb87a08baef6f848bbaeaf1e5f2ffe53310443a442ac5087f41	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x831ff6fc6e0ffad134e0adef0f0fc14fa4a92ade7becfe78135867cf6f5167d2398e8b401c8a9d8d9986b4d1e8c2c197ca44fb8f1ddbbd9e205734fcf817ba09	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5513116c4fc6c79d40f73d2236384bb035a6c8c6345e7c8ddd3a0eeb4e9b645bb860ba1cbb729dc2928f7089b5bae97d44f4dd0bf57a856533d8248691c53a7b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd02cc72f4343ceff0bfcd3241dabb04d194e58dbb9956b77b06fa8b16adeb9085a62a107ab81327a33c00e3f0494fb2fb04ab3932ef0c1779a7aaba3174f7d2b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd645408fcb4b14622d52c85d0d13663ebacfdd2ac7dbe6fcc882da6333aa57562387ec45e660a1fe7cc1f5eca957c24480a6af3440dacf64d0d2c77a8fdbd66	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d83f0f1451b5f9afcbae16174a99df35475057cb39ed39f1a9329da216b8dd13dcaff6e9cc7ff731a2f91aff4bc7afe3f24d96e26786f48bc4654d6eb182325	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf6c89d4f4f48c58d50b658b5749981babd905469c648721a9903cb0e9cda7326b695d57d2cccfd561c41b914bffbf05cb518dcafd4cf34f2130961c2af80a71c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4aa4de3370c2d95bed4875db78f7aa9fd6da1a3862b896c82807a330abf44d486bbf4b9ba483ee88498e2f2bee13f3b6cc934cb0d7be9112d687568e0b688653	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4adc8ff09410efac9027c7577158620f5cf7d3017fef1765ee85ab4048e9c3f7c77b5a0151bd62bf21ecb474cae43262afd17daaead2e51ed9cd5ab3d12ddf5e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xae826a5b15d20bba7582f5151832fdec5ab69b64b868fd31cdcea57f7be07e515613e04c75a7645faad5db80c124fd415ac43503c8e1aa7a75cfd0d22bbea943	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xba7c810505a97686f36ec2a1de16959e6fa97947c4c6e6eb49b5e26b2e147d51f14f5e4531c89ff1e598881a95cb3ad661ee7698f49d08bd47eea94439a3b8be	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8ac431294faebebcd8e272767f6e5bdc673fa811bea3d1a83e7bfad483b73cb40bc070d2be0f48194ec77443a77c633ac6e307a7524e565518eb29da82ea2179	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x61ed6b0b799e6267bb9665ec468f3864230de747467aa2fc2885b0cc0fc463c2c811df981d10f539569177cd3fc91015eda60d80bb0315214bfbb63be4a5ff30	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7971793feeb1712f82c259193231ff37667b5569e77420a00a45c4145470e7824f920cc356baa584db1f122163cb03de7be41702d4b3c08f1de799f51b93bbc4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f813f105d2bba37bb0b6247c85158a67c58f712af8df8acda9e7f85756562a388898a88dca647f3e7046aee62f7004d76b6ed0f889663492d5762c422e5b042	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4042071f23ebfbb5943913f5568ac62d19e5a977c2c876564c898f1890ae2fdf9fc401c505e025d365c85a74c965087be0f5828f55c8323b80ac1c2a969b7fa7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9c96ddcf0e5edac882c6ed80bf7347eaffe266f0de0549e0372605427dbb0007e26673ee83427416dfb251af47b2fd5db2463069386e27782ff2128c414f8735	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xafc4f74f57b696b9617dd82727ce0c157c319b9c89479932e9c2ffe35882df97b4cc8125601f227c7a6809f43aa505bb1d0ee461692d5d9102dce766093aee52	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x65e6b74088ffd20d7e63fcdcc397ebb4662296ce57f1705ba931741e1da4a7fef7dfca6b0dc366c389df9434f12e752caead4fdf361fd5b6525a75cd13dbc51f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf72df0dd1add2a874b4b45fa4b39ff96d9215042d75e5a442a2a2d6c6ce278487a49594e9553231eacc9e1fbafcd55b33bf89276082dbc78081491bf945be9a6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7413d154037605bf58e421b8b8c9b901df77066ee098b7edca70cc0d89982f49fa6495281c32c71f0efbf77bc278e3b2d8f19fd88fb870af8f7a0e6b0824740d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7eabf0749d7631d120e80115a1d9a3607059ece49473682cec68bcf4f58310ffcffb98fbf4435b6ed781ea2f2e0bf526c8dba1bed398ce234ecfc8e16f084508	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x3913a65dd9b554708b831aa9f569a9506d490f5527ce4228312c04302ae903764c5385d36ac6d506c7814f84621dd3fe4187124a202330c52720af3eb51cd035	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x304529444223cd9a1a065d7cac07d63dc873d5ff3bb91ad102d38f7b95f5ba390bc8c840cfcbd4f242ad8e52eebdc1fed828bee0543b7ad85398eeaec2458529	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9339d7f22aabfaed164cf36955660e5e5368b1d01babd7cad39cf1ea4099b274853e33986cb110d56cc67cfba79339368a4d64b8e25b2c81f50b7be440b8104f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbceab12b9077734a2d810c756e8403c841626e8af41f17e0ea26d29b3da10a41380aafc5d00292ac0d051ed1eae45035fd1f02958773db1d5a2ab213164a85f7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6c9a6cb8f7645eaa4dae194a49a70c7597fd3b1bb7b04b00f6fd24edae58377b14755691650d1963ea4194630265e26614607ffa3da78054a1c1da5da61eadf2	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x557cfedca9c9567c5d13fd0ce2aa8f4ba5879625cd7f3e32e01d6bfedcdef2870df50985eac843fa5f93eb9f4053c505208eebcc0709ed0044aecf8c7190d0c6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf7fc80bd161c0bec66a2955f84de3cb29a1289857f25b0ff30aa08557a68f388e5ac043bdb7dd9693019b0584ebd53e770f6f863502f14809bf9bbc0fab39e6b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0abb34aa077b3878960508e5998993e2421a4d8b406b19dfee1e1a74dcdae27ae466c94f66dc37f039e47fba4bff78a0c2655da37bff12d3a4edfd074f439105	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xfde7b7496e444321df158e130c4ee8ad7011fb163c2fd35125c2e3e05e0d2be43452cfec21e8f1e261b7f9f9e8da71cad149e02c1c0ececd224acee8e515a444	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa97b2846f44f62d3bde9760f3f78830d17e4d83cbdf2343adb0d2192f126843b16148b3253314a63f98bb5238e96870a828e1c088828c36f70e9880afc208c4e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xb6e780c1fea66b3aa6f7297470bf29816a17be71fb75470476a67c4f78b09a7c01a8467c901a434926b7b31c0c74c63ae2247727f017eee407f43e8b3974a332	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x16ad83024fe7f39ef0940a35f73f90ffd14a51765978eff3b38991f6badef7dfd76599c201ff61bf2a9bcd415d88140ee59b6a404c27e68c22a7e04a633dbfa5	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4ae645493e43783d8315e0a2ae4adcb8ec12f22b222452ef8b7b8feb1c5a44c3c085670df4316d8d2e3577c2e8d882bd0bb1127e932e4c20288f4e75aaf210c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x23a70265a919cf10de624c6985fa874a0460e4638f93327e60c8adbc59d716868fb4a2d1b02dcda71f0871d8f749cee01e6dc27c8f264a68ee1a8c6e3393a1d7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7a494b63570a7064efa7167422d8096387196372919cd96b90d346b204d20f3193f9df7157e6aaea5bac1d43362c794ee45eec755927e11e0a7fc57f92696c7c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x180ae33b302171a5942bc8b4873a82619bb4b08c36f22f7e0c2dcc7355530d4270ca35debcc19bf0dbf2b6e31310ffcc5e3675ba55e976a3c0b7b1aa509fb421	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xcdffa48fb78f5da2b84bf72f0c6a6426d8f2835aefc171c8622a309b0ee52efdbbca5866ebe60edbf3aee0a06263a22416e5e5fed89f4fbc75e5b5d5064712af	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe429e6dae18132b72b6f10ffe729f27338e22a4003202dbc3a280337fe5727073952b0975bce3b0a626b2556508b55f8594c623d73228e1bc700ee29f9b62bee	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x346f8e0e15a29f66d178c11a70a8ab0e87eebfc7c3e78d8defd7ef3967a667bbb2d312cd4e1a9c038cb14c89c4508425bef7b0d5812548a473240c0a0bf23d9d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x31d99f7e270ec148bc6d177e471a7b2f61a3456485ad6a7c276dc114e4634eab268bf61f645a70d60925118f99318e2b9b11511b29c044b91543ea523b2486b9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xdcefed8ba0b22c48e37d157e9b90dc01db6231c971672dbc8ab31f16e989e2372063f01f1e85c579e826a6c924092c8d9eb547eb029abb4666a73707a26bfaa1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x82d30ac8e74a3d4ec4ec95e123f1ed24eb0202e3449ce93450820c5730dbf0c8112af769f54f6521e124ba95608c02d4b28fb412334d435877892018cb8df656	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xec14c54687bb41d398f15393aa28f89f7d6cd70be0066468a60abadbdd3a3ae6f319eaf3cc4d3b2c338b9f32508ba042950163037bb162a4efff26af225bc389	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66ffc4bbe8cff514a1b5ad3de12554a5b39b45f2bdb1426a5b7a48e99769ab32d6d7e6ecafa73ffe03617265fcb995093d22adab44db84b51e64763f825d0d11	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x42f076d2b95bba036c2864faa73592e7ff6fa28c1e44c54799fcdeed81bbd50553b27d019f90910608764feaeb097431a41009e4aa8cd2f82fb0d38f88ac4689	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6a765c16cc6018b282a8d48048c028dc8aec7985f98941bcb2ef0fe0b9611d897326a8401f101c17b4aeb22c774b7eb3fa237ecbedee457da5abb51dd9f39d07	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf08c5433d98a86ad2413364e54c4107994fcae0e5ee03059679c32a658e46f9cffd1b98063b4afc0afb1bbeeb2fa182b0553733e0fd1a979ee1b4afaf72a00a0	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x56ec7d7f1a95924bc640287d56e2ef922d001bc39024fc7af9b40405e045081cc54676d4d400d678f19462966b47417ebc252b0692ee18d8f46761e3134f3ba3	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7252c371245a6cacdde361e522be264564f1f6c4bd1b0a89553e27369d40d3d498110eb11551b9965f4b32358a891ef086a3277120748d97d92bf337c6bf787d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf978f3310fcf86ab9dcd3c1d63e3f04a27ae4feabab39ae1a56958e16d3dd84b3cabdb01b3bd2421187505de4921dc66687e67d88388b51a8b7ad01e801f744d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1b5249431469283546dc019c254d0976d1d5de450cd0e0a64270ec6f8acd5a784acd3ac53668aa71b1066fd066513b0a05aed1932f356b91464eba021e8ad050	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x81c67b95078b45960e318af67c72ac98f51e1f13579a8470d26d09d4f24065d7db2930dbe7863bb81ba3b15b5f53423bbf37249b914723ed65830b7e45d40029	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66b1aa393e2f6a3eb978654224d4b5e8e6e22ea1e79be8966836afdfebcc38675bd49a2553d47f5615090e550998a0963043961d2aa98a6f406f240048dc27e9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2c884cb003a829128072625617bd522eb36915f1f174cfb8ab9ea2296eb092efe602a6fc42454b8377f05cb0bb1801e4e366f7955632174d6d00ecfccf352cd3	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xe7fb6690108099e3f31a43118c986f6f9cd3adf073fd08d779cd82ccb9fd4a42b2b48191d4d684cd9cb18636cde7dd66393b5b2c06a3cb74aca9f2070bd45b43	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1d16798353959efde987f349ab69503a2edbc58023719efbf3fab5b7cdd5d12db71388e9bd09a3243c9d2b2439fa91df57df577c65abeb8dc9459ab05f7a8366	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2bf200b591a8df87ae7e8d631533daf102290fd649ddd79585d14f70923010f7e4768bf80586b94e876b396e6ef93133e6ff4334403687d0c06174c38f64a316	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0658bf36a4b04cae6a9a3c398cfcf38b1c8188d4b1d3bddd53024bacfca93ca88b1a0dad319395abf0ac941a56417d963a856ae7251976f538af4960b416b061	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa6057affc9cc5585f551cce0a30f129df760d8d3ac2c3b5a4b9b7f696c949c669c827a5897d02e2a18d97c9dba9c5e7d25f4ab26690c13f7bab098aef32524e3	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x285ee355d1c131a358b9025644312aecd1b9cd8616b030079587c1b4c8d559e2cbcc842d5f9d5c37659c336f9f2f0f8bb2293839d6432f65e68a8fd44ac586d4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x22cf25291c81eeaa2279c9f0198f40c305a248461be29ebe0300eee4d0b19e94a09c031843b1cf595e8a86f225db7238bd22b99fe4e30b40ad8d8be661a39168	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf5202d404aa1b44599cf3b9bf74a699b40d759c3594f376054d1ae446f31875c07553b6bde95534bf8783e395584768de2097b8615bd286c78deb63f41ff5399	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x0f6efd74cb17cd75aeda58d9ed3e3be9d09b8a2794ed587da452ac1f5ba24fc57df3f7cdb599de6dc195b2d01cf2bf105f90db087f939cbd6a8d41fb97b078ac	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xbf6e3bf40614496f4fb6f50edc66599ddfc2c85168ca27b86ab827c63ef5a2454b53981559bd023a707726862e863b78e7eac495094b3231f9383bc23e04297d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x1c20d60c47ebc1f39ae2821ffc1dd2bbb3080e2c193c60238e0d4997c0d6f8a24490e158090d85815f51b2423ad283ee6d2c0df30134ed4c6f80e1b6caa7ca92	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9ec5b5e4406617fc0f0dbec95dd813e41c084970c0c92b70758eaaf3fcea4359e1713a55f56ee5732d284ef61162415225caee8eb3a479a4b5d5a546366a62a2	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa9bf77e66cf95bffea30ac16e5850d46b153e5f9cdfdefa9ae3611ed853e651f725f0d8bd5ef49aa8fdefb39975868467439a8bddaae8e55cfeffc306a2ed9fc	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8512d9afffde6114fce4ff01dd21315e7190d94d42cc1083c118b4a914272af8c15e3f1fc7ab7dbee6f3c0f0dfdc3b1f5a6d414fa35e4f5852cca01ea717fc2a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x2259cfdf52b275868e4def4520aaf12066ac41e3eaf08526d14fe063d3aa4708a58f709e8f137cacdfc2c3149ff188e85367e213b9b3adc84286e7ba6898c34d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x9a39ba823a0dd7ac450f5d5990813635c35e186d96e1f80a08b05deb0c0448ef2d7d81efba94d8f42e8f56a56fadb4a8d7ade56c6e4e66987faf16b95e371157	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x467669c0358aabf2583c15405e5c373c79528b470fa997379b12459e7219c1568c8f122becb717b7c1b390f9d7c4279bd95cb9c182ece89d3b8a4e783677751e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf78272f03a9846a63dceec453779b43ff51db787ecf9c47f41d41716ed5125536c6430a026cec7c222a4f7b104cca7873a11a67ae06ae6830b6f63f90c702000	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xa4f02b791f33a3b3de6ca7b75d5a30d15b92d74a186272571034f5eef3faa0d9acbb4dbc10654ef62c657953cb13b99ef440009bbfb7b5183359f8e076fb8b6d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x055e9081c79c1bc0463658e69a483d85e1c7a93d93e752ab20bf6124437a31a15d8dc9cc30a5c155777e1603a1fb1551655ddb025168a35ad7e72e700ed2bbb8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x15836ca88d0bb239aab6d31a0badc3a0291bcbb3a33ff40f0551c1477159eeab19eb17170155a156cc1987c6a14be21d68e3338636abbe93f803b45fc178c49e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x32e44d828de5ef6fef3f3886f46ef25deca7b9fa9e8b55b389c6f305764f3b2aaeacad416518f22b0429373b8a7d21aeb4d54d0d1929d7daf3e9cb6b1d897348	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd2ef5725e571d58a7c9953bc6c1380c7dc62ed5709654ca31e4efd294d18d6debf609c695df617368d5dd12eea71aa2c9826b256c70cc2984babcc7fda9dc218	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xf05c2fe15008ac30cce45ddcfa3632d650422a49bfb785dc03c9f60933ad0d36777f00efb25243af1d33affd1a357e30dbc5949fe7cfb1f14473705529065bd3	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x847562354ab1aa7a71ff2065d0d57246fa8d313b1ceb90d583e549742629f739e30e7ac59515d496924b36179fa82314097d953229be6022f5723530baba8cf4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc62f4738f9d604dd408b620ac4465830c1ef3cb9ee83c01d1ff7761adfbd75920ff4cc232d6852d9cc178ae5369143f35d4398a516bcded9735bdfe73aa13772	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x61040693f74603c31bdc6c7f53de307a26095a5c32fa0b5cb77b2b9a7c68349252afc2a28271b25e0decf1c2479dca40cc805407fa1006d9e6a53fc6e7f738bc	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x83715acd8f40b9eb18410e58ab33848233e256de5b0943096762fd86d1aae3568733c1e2594887ab692dc84700f8502831048d585d54676a7a62a1c9a671a613	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd0131578b50492e5eae6cbc2016e2539c0d4fd2913e43899bb2020e7b0c7a3d535ea1913dc5f07e549176642f4e1fd7d978db2fe7049eb62c0e73dae7c44289d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7075cb9365904db10b44fa463b7a0ce8d1141e13a5a2973d0df8886d814cde681c60ac07efbc742d1d17c6fc207581d83289c619ca9f7c3009790437b7fa5952	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x453c48b78dcb49e62aa44b2962877a2646ed51cd2a1386946fa9b4586d6f716e1dbad8cfc69f18bdaa609e603e32ee97cb3c60d95ad5f2dd83d2290f2e7c2e2b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa34a034010888c74772692bc0bec5922945748cdff28c8511c58469b4498b090834deda03d4e16475ab6d300180b6aa3cc7d7d3a3c04b53a3c67636af13fda91	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd57a99bb4e3540d280bae8a254bd213342364e8834003b4349287d571047777e5444163f0c0c669fc0b0410655bb3dfb085da11c9af2c8fce048dbc3a28bf8d9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x7785d30963e386db789c1ec4a124145753b15195ba6ea69c0185078c162106381b7487ec1b2fc6a1ce6f4730772a2ade38ea6cd8dcaffcb02cf9e0f78cb45970	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa9c71af4bdd8e47c9c703e0da882b3a01bead5bdafff11890ec3ddf0b1611cc8bead7f0f2d1a2313faa4a36715eef48d5852012c6c83dbf0c3611486407f240c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x75046faed5b88d7342fb68a38ccb3b4e46f3b564a0f0b7f6c7e40c2e5a9e6944c5e0365b3e7c0ca4b063e121f78df7a40966e32d6de64b405ebcd8d1f29a6694	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x608866c5e100abf1afd4d4adb6a9b10324037623effddf2e12a2f3af1d7310c541c6ad985d9639107070c8c0dd45cc3947fae1cb97aec2c0554cd25d8b8ccb83	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb20b17baa0a95fe3e2304d06d4971c341dfb090b3645987463e9696cf1dd69c38c4d9b7495b715c05ce621b0a70b57432c826a07a2beaba216522a76fa2b90dd	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x1504e67002516eb6709951bdea13b616b61cac2b9a862a3a6b0abc92e41bc5e25ef09a8bd02acc35dcf28800a856935f0d05c9d71ba54503c4453bc268d76e61	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xda0e2045b72f4eddaea5ad0e5ab330e568f37860db088a26150fa8d994d761a1fdbf4ee29c723d1a70ec2ffce58c214c3081b43a5a17db2f9b0f882a49ba29fa	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xe9bee89dde59a88cfdc608a0626f6a8ea66c77e3b4e45d4858edb4f3ad0ec2df01b1544caf3d060bc914d93c1b191053518afa083a115520d1cb37239332cc71	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x08d1686bb457b3cec5e55b152e6b9aa540e07f116cb8ad9b30811bf9a2be55e0c17dafc02d484565625753054ceafa2d79485e711a8e3c4561bf465bc895b074	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x902f9f435887426f923533a46617e8f449cfedc1dcffe743cf17594e4460cf07a7c3a46e0238a1d325aa487ea7a08be5ead6a87ad7ed54c50f6ae6a7d61e145d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x33e33b54715d72a54722a4f3a12c1911306b56e4c825bfaa5228e75014977d50ca9d965e7085cb8a1b521e7d36a06bcd39b921ec2f3ed3ebb5faa88d6dbbc9cb	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9540cb18b69ba4ead8525eef194ab093ddafefbf4726193e8c1c5368f25f8ee2c9cb9e5e8cd2d3fbbf0ae15af47f916ed30a29cb9331076c3f31371811652ea7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x95644092aaf564c1e2ebc1c82a59b79b5112da4e0e936f9279dc350b15316b248f85416de3727c4dae40c0c9935f12fca5fdd8dd3ef2c709bad53989845b131c	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x139c1504169634ca345ee85fe15894bdd6e3196427566da1e53f7e2cd0fda949e45054121a4463ad57ef5fc260d267aca5ccf8926fe06d10ebdfd4d68872b11a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x59b27853dfdcb7b3d0eaa60a6e1a29ab99e9e640711754f0935e4a5967001d6c0cfbcd4baede7a079992cc6ed13304a8f27ec3376d4e50dbffd95b09cb58d151	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd67b1889768ebc988fe252445af7475d9350c6469cb7073b7ebf9fa6bc900f3e11ba9263647add7538eaeea0c13c9014f231ae73d5da205c5971b28b25e66f2a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xed81d6abedd040aa92fb6286b8035921a4c0c3402f4450abdea98d84540d225d39a19f7b60f47be2521ea18a4eda812986dacb0cbf9becca65c1a0013f856343	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x9862e5e6643cbf5c1e6c2d5100d6ccead94919b327adf7bcde0f776fc9a129c078492e6c936c668b9295f83120a6f7f387bacf3693fe5a5fce94776209743913	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xaccd80872df8e27af301d5af77418abfb7b18bb7d7156d98b61cffea5f8bb938c57bbd7590a39b64a89b648b6da072c848383e7c38de44b3047fa1cba2068964	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x4cf1313177888e04f8e37ef3e7a9b22608773cafb435f11fd6c2fe8a8d0e283e7c8125dd70c5c1b06eace9d5de441de7508e44b2a197621adb0b198e45662ac4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xb811752afcb098d2e281884630f6c0c57fc3a3f7741865ac7ff62483f5e6e6d1a5039fca516cd185edca16391d9db74e2612c98c916362d8586412514f2e5243	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x07db921b1ebebcc4826e774b6ea9e4c8aa0efebf8b1aa1bc25aec360a232b2df42ef3d388b9f7efc59c57e2af7aa41a748796379c6dddfea0aa56de51448d83f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc72fed6b9313bc1e7378d44001499532520717171603900150c81b39953c442dd920a7faa5379b9b0c7bb69df7ef6660461903447b5532c4f86634a94aacc9ab	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x25ad0f342c7f3b72cbd5ef076dad4b3f2fdfcaccaef0e7d0797ad3c70bf2ea5604b069b376a96a8e505112a80a941c4b9b142facf614f7fa6cbb623cc0b1fe8a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d1bf7de1d6ce4dc408d50bb222c722de6506bb1c34d559fe9d5dee626690d1d6d54874cbc24949b83d3188db786ee1446ba42cddd4f6dcd6676959c917ca2dd	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x49d9441be37413de64f3034d6bfd09b6ea9708f0a1cdff921b1ef0fc5e915a679aa03f0848bf4ee9b91f6a088ffd348b7ff8fe43145ccd308d4c7d93aad5ce8d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc515762f29b14e1bf78b834d1e3151ed50d72772b62779adad03379d0b9b8d56358aa8dabffb12dd855e568d6412354396b6a87be85bb817bfb889fb813447d0	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xea4a483a1abb1ec293bee42bf0895ff8ae1cd969b9bf3fa017818d456b6725f6443edc8157b709e07044256e0022225ee97ecaa8552f6da199d4c20c5bfed28d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x43d6af0c18c59003dd4959139894f907eb48f1e5e3cceada687845ba6c215651822bf5d5028234ac5b00c0ba44602a5a6f9fcc2ce3365e1b5d1cb42228bd9e2e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x93ef1cbc761eac38c7c8aecba50c78be4c8bc0b532a7ef73da9b82454b14c23ae64a155d1d2db1f038224dc8eba6cdf2fd601d3dfaa4cc6b8f7387bdad31809f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd3eef647ecaa3876c2f1ecbd6103d5df045abc0ce9c24194b379857ceb58ea9c8ac6c8d19f3ab318aca2972da1cc6498b4f966c2d66c6d5a67f809c53cb06413	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8889d60c1070a0387169249bd6e9caa501b66fc0043e4164f75e31a2bbc9a78316bd740f15b653db4a3a8240f67dc0d65dd479bd7cf9d1323249745d3bc73f09	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x41aacc2e4f6626f2e7e7df2cfa50295953ae41cd6533f601bb406f44569008d0bcd6e257146a153c5018147338995731e2d0ed1d8bd1991f90b72b2e4be6877b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1406043bea46f67246396343a65394e28b146f2600940df126bbb6dd752f58a93281aa2c400dc3ffde595dbd47fe21a2f2e155e6e6911e7cf751745c92b5c10	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xba1236705a1aee24c5c6b9ea9b1cb1c17c911eb524e329a8bcf84b5e2eaa4644f6eb2e2c435ef3fb0dc29ad064fe5d503dba4fe8b381cc5b02d9c2a6fef7cbf9	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x40e60bf79971bed94587d26b9e6e6bbdcf41a8d4f0c6eee8454e108aa65d78e452bf722bc5dbd15633f6f9a70a324fd1f742ac46e8a7ffa2f785b33f57d40bae	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x878a9465da5769e65b51373ea74a3ef0c67ce7b434aca89adf05c7ba056b3e47903978db2fb34bab257703b213e8df43c779a01389c56464043d0965bca6fff5	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x18e4a218f32f0d1281a3f5e9c6608b19346178756f46a905bcab20a02fa9e917a7e1a4695ebca65ae18ee2cde6b6f04cfd4389ad5bfd173045745e6b63a6cee7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x950057ff0d2068f4a1ba88572217060316a1cf998d7a0db97c9eff62c17700b59cddd027de90d1f791ebc30e4eba7eb0a07289e8afbf89a6cb3cf78d91172415	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x748423c6582dbcf98e993d27ec0fb3db19e9d99bc3c97b26ba15e2ac625a80dc3db9cb6d1405df1182ad81baa0f86fe5a52d426bd2c63df05417ba514993b486	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22193f0f410ab7b8d0a0fa158f7c9de08b947f9b1a87a6043b1f4cfa9483a3fd278506627bef5d7f3a18abdbe9963bd876db7dd4de6ce3a9bd6aabb983303248	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdfdca3ac461eb7d10c86763a7e270d841dfb217b0437fc2576cbcdb546ebcb2d45050bee9b88b3dfaba156d5da63d556ad03a8de604ac3d1450c282afb8ce12e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x432575a31a3967553cfdf447b919a9e23e974f0c956a1ff4d3d64a7dac47afa75f71cd39fe3f17621d47df4b3d4cbdd2c61460d297cbc91221b16e38e3bcc655	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b4aea09cf328f4d26aeb276dfa2d20fe12e423365acc20f16d281082747d0fd34b7c44c1d83c74068b95c370c922bc5c2c2ad5b8ee15f38007225f3488282a7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x373efcf7ba0d2686964db80bda7b72ec799d2c15dfc287da5f2c09badaa5e740d79f8188d49ef957b91759d2b9dfbce5dc7962a806e710a8e8e4cbed80454989	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3e86e2484e181f0b68d2653b136ebb3634b91809e223434d1246d42dbba3880a771a43881681ec3e57ccefd4807386257e0ea791e2d5ef770377677dedcccda	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe3e3bb9780ea636e12913845352ce83475ac40d95c65d62e9c275b66cd6bfd19af01160d257fce3badea69423ae883f7c1cdf01f63a3c2145f52e80026667c54	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc7e451e0cace02dfd705caa2281145c02bbe2fa608f8fe1f95f3a5126164cc494801c6dea2922db58fee7b2a8898d36d04a064b6b2be863443349b36b7dd8fcd	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe7cd1ab12bb312f12e90beb518b763e6fe050dda20c94aee3dc9824661560b2b23e72454b2d9fb4a7287a8649b7535d545e06c22c4a9292a727c68957623a51d	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcd0394a37ec5b470741d03fad212516833f7c3eee10f1df95f6e06dee7466479c8c9c727c9a1981ed2c8e7912dd93e542e0e41a6cc3918d49b920250a8b55f4f	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xec76051b7aff19a4d9de8f0b2d700f5be568c7af88f1c6ee5c9b520e7e557b68fd596c7b61352fe19c842cf5eea409e67cfcda9f27aa6a7e0ad51fa0f6873c46	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x46c8bce57ba2efc684dd7aeb1229b09b28058acd52e155b315cf90f6cf7af346a466bd204da1bd83272d0b1016261cc6fb8414e6c3f7d03b3b6bbac4fac05a99	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9fcabff1519e01cfbd00789827ed18263f053a28c60c285ce47300b811535097e546b87dac1225321d2ed7ef130b414480d7a3d2c8d07ab1ffa8c02d33495c30	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570300322000000	1570905122000000	1633372322000000	1664908322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x152d743af72871faf6f3e1c24c8552d6acc94551413185718698a04ac027ef7f98e2477caca12e2ff02702e5da06c477d087d0f678ddedc810db373c15a52a90	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1570904822000000	1571509622000000	1633976822000000	1665512822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x818d9b5299febdace8c6732c6ae29a6c54b643411bc19eec8dbbd1cc4ebdd4a3f242c19c852c409dd21a3c403b6d1e249198d99f042a36c5cf5a54c1f69eab30	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1571509322000000	1572114122000000	1634581322000000	1666117322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa0be93fb737ee724262583900598a76353be86ce38b946c87332ffbc647ea57f6e6d255e88517a9beca554fbe4446a4a82709f6ab5a02b608980c191f0d38385	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572113822000000	1572718622000000	1635185822000000	1666721822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x41d211165a4102339e5c65a24103c196d3ea460aa0abd7698a083c8e65a05c91ce529aa9f940fab650bd17f2b3592f1292c51228607ed0446bc1b99b5de72688	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1572718322000000	1573323122000000	1635790322000000	1667326322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfc041e904da079a75c89fd8d10da7dafa6a9ab6acdec46a7852ca1ac1fdb48f329bd67c274216063a2843e27daf9a7648171e156f87358ae9f6b54101e0e39a1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573322822000000	1573927622000000	1636394822000000	1667930822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2b66a9ac704592d1a1f04bab61bdf038c6d623ddb7e3c044252b56c95cfb7475b97aec19d959a9da0e423aa95b04072f72f3f399e40b1a4cd0e0c2cf5f13b82b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1573927322000000	1574532122000000	1636999322000000	1668535322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x3456f69e6e20016b9d8d9089a1a447349e7cb798638582e4137f180d952ffdd38690c6ffcdb51c46fac1c541166fd2f83b5841cdb0a22074109e849686cc28c6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1574531822000000	1575136622000000	1637603822000000	1669139822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x7441a468d52fa2d7258952284498ba91bc27ca27ee5ece74f9b3045e4f0a297ddf25eca2336f4a5e1894957756d456ff2adda623f1dda6aca87fa1200082da66	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575136322000000	1575741122000000	1638208322000000	1669744322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x08a1282f685bf6c9734069a7dbcd05d41e94aba1df6fe39af54d0391b12cb9ba474afc4ecd36bcef1ce749f0eefbd58296e7dd0d0ed96e1ae1619f103a1fabe8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1575740822000000	1576345622000000	1638812822000000	1670348822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x92f79f7dec4e85a755bcd4ee385f0236d2bc5e75fa6582026fb7767cba1a0baceb8a76587daa0bfbcd5677f0071f4f0a746655414ee2870b6a43bd34480e48b5	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576345322000000	1576950122000000	1639417322000000	1670953322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa2998a01a67d35d5029820dd1d3aaa632d3b4b85f30ac8e63ff8229f40a7abaa3fd11e57d0424b619c68f2e4d87792558e88240c898ad0f87f529e0d09fc04e8	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1576949822000000	1577554622000000	1640021822000000	1671557822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xfeb4f3a0a1f519f0d97b01943b9309897f927b8cd84f601806f73343cc55c4125fb51eb168bc03a6f9789dd5172cc5e83675406878f72799941c6158fedf02f6	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1577554322000000	1578159122000000	1640626322000000	1672162322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x2b169d3e9fe23437ef229daf4067c1a20c8f8b8204ee2220547927980d3c73417d4155ef8c1b19451d5878647b78ab7a65e567ac4277c2336bd91b56c7d433d1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578158822000000	1578763622000000	1641230822000000	1672766822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x45cc1878595db28805b780fbdd82a06dde986fe09428912e0632e36108c6bf8c411e501c78e55904c8293002a32e01f991f891addd0aae9ada0b2ea6e42f863a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1578763322000000	1579368122000000	1641835322000000	1673371322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x939cdc09e9be0c5d97af9adb322a18be7571bd393399f3223dd36a58090cd7af977c371c350015089d063ed9be715234633f243fbfe0eab36dd525850c8bee56	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579367822000000	1579972622000000	1642439822000000	1673975822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x320fef8d499a4669cfb92ad1e838d43c5373e59b23da4e63f2065041c2d8322026ac3e30276fd9445951b082bf58f1c7c9784112b5a5a8b65e1b2f73eae56f8b	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1579972322000000	1580577122000000	1643044322000000	1674580322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x9aa683ca226d71a09922ad1f92b6ec531a4710a7d23ee3c8abb7eb5b64580822a4362b1ba654e5c2a71cd16445c561a27e63bbc22460b26fdb456065416fe2f7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1580576822000000	1581181622000000	1643648822000000	1675184822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x90a7296882c53dbfc001243335d8201bf38b8af658d20aa85e1ff950597693f5bc1f31816cfaaa3543d581bfe2152f975a6ccb30923f34fd114d07f5c041c9e5	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581181322000000	1581786122000000	1644253322000000	1675789322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6fd190b0c08cf1e76f080af5ed793ad524204bd740eecd395dcf38fb774dfd318d9660d43e6876ec66f5a2185a1ab9ae8f7ebdb051c02d7b98937c466a7a871e	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1581785822000000	1582390622000000	1644857822000000	1676393822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x09737f05f72509ef9cc1030673ca5f78813e73ed59b633f5aec1acb2d9015af55e94bdf4c1512db51ccb99326ba88fbbbb40f203254d310292e498e1bc808338	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582390322000000	1582995122000000	1645462322000000	1676998322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x4fd237b14dcce12e84e4381cd6a9013df7c93e91c6b580f17efb052ac093ce5194d397e4bf3acae5072f21ed165bb7dd921060e3ce8b9576e8706b7060d7d81a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1582994822000000	1583599622000000	1646066822000000	1677602822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x29eaf15e00d638a7e25a277f01e5ee5608543b2d817a34686797e3cca53f8378aa601b123242e886c9fb4b7c5211ffd28e095f8ac21e7841bea6a9cfff4b12d2	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1583599322000000	1584204122000000	1646671322000000	1678207322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc2fea24d6b0ccc89a7446f77369b6c705ac07e018d2d0e2b7a70bfb8d82e9b84409fb72e5b62565dcac3ce6ac8af84846adb11d6c1afda9e42381ef72257da73	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584203822000000	1584808622000000	1647275822000000	1678811822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe3c8f9d545004b9f9f0cbbc48f8c3ebf1c81a748d2b68fc8c659293e5d481b56170f312ee623b858f35ea2d9e3a615ae9a8314068b4ba11627f7d80a3d1b24ff	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1584808322000000	1585413122000000	1647880322000000	1679416322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xf0efbbfb60dbeecc1788a5f8e36d0167a074a4aa29c865bb665dae5f3153a4927ce5f70042fc2f6b26a22742bc004a2969b30b7840e8f9a8afa889498c7d3dd1	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1585412822000000	1586017622000000	1648484822000000	1680020822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x0fcbceca2063342ac42eca5eeca05c1edd778b36255453d35df034b592a821b3f872a9472db04f22712f4bd79b41de89bb01a3a8741c7239b3fd71c1b39851d4	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586017322000000	1586622122000000	1649089322000000	1680625322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xff7e3ee8d266370ff6edef44c64bbbc71ab66d3c2c2a49363e5015a5b96ed3cdff3518554faaffaab635075b9d04ebc59495548afa17f04505e4dbbb1f701049	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1586621822000000	1587226622000000	1649693822000000	1681229822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x88b5203d742ac66f65a4ddb26e24835de57876c0138aa99aca4fcf1bb0f558b41f7cc0b8d2d80c52b2e69de86136203d0de88ce9ac290705656383d82f0b3017	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587226322000000	1587831122000000	1650298322000000	1681834322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xe9bf4534877ef18a4ecf300f86ea7dd2ad6563357fa6263d77ff0ec4bd7b0306bc46628e2fb4d36ce9764f652d388cef216ec16bc66ada3d40287352ea786e74	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1587830822000000	1588435622000000	1650902822000000	1682438822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x6a32afeeb373470591319d39c8244714fddad31a8367c5acae9ca7f65baf101e5d978c1a7b81b3676f39c76d86b4393cfe16a909067142b806ece74f15f95f44	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1588435322000000	1589040122000000	1651507322000000	1683043322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xeb5d0da4121f79d3baf9c22774907a025ee6b440850246434caa5d1f02a0db1d6c4e0c678ddbe03a33746000e091548f8d17c1188022ec156c7ff486271c47a7	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589039822000000	1589644622000000	1652111822000000	1683647822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa71e3c59981be06e1d2f36e3b0ead3f61da610101eb4d9a41be17bea3579187f5416d5e949fcd0499171fe007db2bcb266aeb8a5e30c6d7836852d00c1513c03	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	1589644322000000	1590249122000000	1652716322000000	1684252322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
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
\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	http://localhost:8081/
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
1	pbkdf2_sha256$150000$iOlggYHrE0lW$S1wIbTFicsiYtlzHZJHR6Y21WbyyWCUdUcsCa/3LMDA=	\N	f	Bank				f	t	2019-10-05 20:32:08.884614+02
2	pbkdf2_sha256$150000$9ofKUnlw21gd$C3NH9PwCaq6hpVl4Mwli9wqdgYsbiiC5r43ifPxm2oQ=	\N	f	Exchange				f	t	2019-10-05 20:32:08.945334+02
3	pbkdf2_sha256$150000$qEt6CYAo5Nky$eSMn7L7kZdnqTwNkbuLeh3cpdzw8PPKE+brmdPrDoxk=	\N	f	Tor				f	t	2019-10-05 20:32:08.998567+02
4	pbkdf2_sha256$150000$atRfT3SxJ67c$IceXO2+D13nf0NG3HVj4g674EuBVdgBr8GOOrjChTM8=	\N	f	GNUnet				f	t	2019-10-05 20:32:09.051926+02
5	pbkdf2_sha256$150000$7UcgMrkbXMzQ$xB0NubZuNhHNED6uayzolywXyzbsLWNHRLFNKzU08yw=	\N	f	Taler				f	t	2019-10-05 20:32:09.10912+02
6	pbkdf2_sha256$150000$Dx9qxRXijUez$xTPd8UZ3NeixTh+ZEQyM85jCdZQiAiwwhEAOzeFTKeI=	\N	f	FSF				f	t	2019-10-05 20:32:09.161828+02
7	pbkdf2_sha256$150000$IJy8N5u9JFpS$rM8MABAqJ5NADviu61mxGpNvdcrasvFkVscteiT+Gmo=	\N	f	Tutorial				f	t	2019-10-05 20:32:09.213485+02
8	pbkdf2_sha256$150000$47Q2ZNRlVjh5$Nbx57FTNWQAXJxck6GE+ZAmKHu38cyiEM102REyED7I=	\N	f	Survey				f	t	2019-10-05 20:32:09.267243+02
9	pbkdf2_sha256$150000$iAS6pZiIFxdp$aI4Dha775AnQIsMLc4ypogRtGGcu15YTrEonuQaw1kg=	\N	f	testuser-VfsNIqNG				f	t	2019-10-05 20:32:19.270347+02
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
\\xd0e0ce1475ef744de5296ede6db790a52bd47dc63efa22b5de74c49068a2be37a2474f724141ab345408d0e1747dd71cb498ac47645c144bcf377bacc8708102	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233313638393133444236323146434537433336363343394433374237343631424630454131463239393137453442324331333536423339463745373542444338443143343730353139363639343446353741383141414245424438463544424437433634344543463045453336424636464143374341373631363332463038353041304636463139323433454436353344353239423137453945444132314642354641314445334331304643344438433231323241433446304246433531394539453641303145363546384237373542354143453633414639354330463635313943463130313141343946304430353037454336433037363644433437434223290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x393e0faba9b688b5c5eec47da0c447afb773e8712d30059e79c4ba44dd8ce276738d41665c4accd184840fc8cac9b89b18a4a4da8e6d2ee839e5bdc79b21300c	1571509322000000	1572114122000000	1634581322000000	1666117322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x18efa06963fb57467776a49c643dae92c7c63238c3ee859712cab9b074dbb9b8999b95a0c30269218478407f0e971f167e6a37ad95e27a109095b9bc7ae35b13	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304246433236333338453542363246343630444335303438314133433936454236443330343736413031464446383142353931433738444631353531394534393032413432454644434342394430324537373334323742433133364343323638463932453037323946424443413039453736433446354333413443424535343339393533444143443632434239414444373538393542353936353739444646434332333136383332423137373738413635394631304635433643383144304239373832313534363246393441434342333333464546424241314339383341414543324446343641394143353739454436463042463832313643363030383144433323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xca82cc071b05ea48906dedfb7efce1907e719867097212c1429f87c890dc7621813968e710acff33adfe7448147fc225abc4f3058981adabeba849b23623d90a	1572718322000000	1573323122000000	1635790322000000	1667326322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x53f8603c75e27892ea09715e4c46cabdec59e1e091acfcadb24e6e680b8bc25c2b6bd3456725b557a7416580e9be1702426e6961a14d028c915240ace0e7ad1c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304346424231433237444138343735423333423034364242443134304335454645343943383136314539313143434538393639423838343741314439464637323042383443443746383846373045343937414545313035333532393633374439314630454138443139423334374342453138363538304138373530463635443242303632363231313837303944334537434539393634354133323446433031463032343638323544414244353735413843383641314642414141373743323245454531343046333431324332303935333233363035374338343741383631364230373936323730463341413338314446333045394432364343354139414246434623290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x89323f1aa311d69bdec4e64c3ef2a7f518696fcfa7b5ed846501d4a52afe83d1fa615afd8038b342c6598bf0649b7d3d4030a16bbbdbb608d21d0c677e022c0d	1572113822000000	1572718622000000	1635185822000000	1666721822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb0f7ded2ebc65665220da9c5af7d64bcc1faf1cf88b3cd3bc9f2cf79d507b4aebb847fe84aca733fefab40a763a880c8b7165c3bfb3f75f52b601eb85eba237f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304335303930453742423839314437334130303636353733444436323537373733363531304341323630344131373743374342383242394339334236383839314133414531424242443236354335443344443637343635354339364444454646334232443035413435364434454635443845304634333334354335443446354231353735464444314643313533353742373737373046364231304146313042323634353842353143334143394545424444333642433833384130344545304331304638423635423043343334384532443645354632393736314631463644384645353233323744443431444343463435363138363034304342363731433230453323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x0fad713a7f98b6bb771724d2c80b7aab6d3ef8765d3502c100a4e7a86aa0f284779ffa60a9355e9ec699352455924bf9b37184c75daf374d4df0c92bf83d0d01	1570300322000000	1570905122000000	1633372322000000	1664908322000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9541f9ac9a24195c7573e6b6280d2c55099d80b3dc4260b2bd7a2d9fdbf6ebc1e28835e7b85e81fd221abd92ca8369634defac10dbc1552edba4ba85d53b3da4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436343544313234344433334532384138393735414333454135463743374533423039393433373841333732393835313541353546343344314336374538373034333139313338434336463836373938393543323044453137383038373943444345373833383343463638394341314641444643353733344545313233353530334339343430344433314336413538433043333239314334393030393732314230463542463141333844393435413546463438454344463745364644394432423045353742373034443237463531303133464246363938453246433246453642323530433236453032443533343433353836313038393731304541353232323923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x99820a4fe98b2e447cd4abe8c1d66847acb666999d9923b38b5182c4275e27237c615c786cc7c8f9e7f00a99444c805cceba403094ebbdbd6e929b0d9ee3aa03	1570904822000000	1571509622000000	1633976822000000	1665512822000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x417265d8feae2e583a2c70ed1ef602c65fe496c0e25e46cd97dee99bc6a68206186877fc023c4e86e60166ae6be28e58ae0c36af13db207e1e7d9a423f014c4e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304433323133424144353233324345383134353139414532394341393336303441374136354333344138383330443330443230363337363330343432443534384643374537323542344542463232373241313645433741463234434135364244433134333336394242393235304538333238454332343934423244454442334130343635334536383942423044384239344135383332343246413832423846444136363231334335324333383530463841323232384344453843354244353045384439333441453346313138393438363341354343384444363631363443454233394546443145333541393237303138453741423731393639353233353934463723290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x097da1a0dcfca2be197cc1e7ccff66448563546407b7e2e8cdb695cc19fdfbf2b6d094e80b3627c0cf6c510f7afd777244f086b1c6b0b574c04a2c472feb5a00	1571509322000000	1572114122000000	1634581322000000	1666117322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe2028ec91591e78a3105a35f38f3280c3ede8bf4d18863835987518a8e6638608c762796e0dd5a579587b3f41e626739338a8f158d7753c7cfcb89242d90a255	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304144314533444535423441444246323544383830453043444644373636394538313342333433373941363036353634354331443832383846433543303134324646423435414133433139443438363936444135304530373939314231414243324234444533424331354639343245313041334531433233443939364637393138434646314144314238314638444445334243343042313632333945374232343543344631363845323534354431463046413431333946443743433744363334363941394334433546464635303132454635373630313538423032363434413133343932434142384143453337313030324343333730433345313136373237363123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xfaa4efcefc1aef7ad33d8dfa6c5096c508d1ed45dbea5f18152b45df32b0b66a1236039e15eeac44c5b349247a0adc793fa94265b61c58a8ecb8fe9a6b950304	1572718322000000	1573323122000000	1635790322000000	1667326322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5417f6813ec73ccac9e0086453829562b60467d09a2a1d15a64efabaf0739e7899b55f2150a89a45723786f00bd737346777411ad80942ab7dd5c18f16fe4311	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304634354144453845464238333542373846364245334338343342453141373733364342443332363136354439303944443745423838323339423338413836464338464541464534413130443132443546323438424134334635443438384638343244344430373231313142423644433434324338353239464133464142434230463830304638424236433937424437334636303344464145434141383542313646433731423734383039304433323636453937304639323334413930423045393739433535454339383135414437433344343437464134374334353736363843333732323046383932454534373544353836424336383031423336333033424623290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x2661c43aefbb81047d4e51b92d6cd9a12f6bbe1238716093b671d0768408acd1fe6dc2c2af99adcf8dcaaa44de1ff84ca2cfea3693fb54d2cd99bf779e79bb0a	1572113822000000	1572718622000000	1635185822000000	1666721822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77aeda0509631a96dbdb72f918f55358dbde83561b3d0d974a041879a92bb5944b1fab6fafc5476e15c152580311612db52d0be2ee787d6a251ad5ed8ecca26d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304235374243333145423339423935413234313532373842353638394244354137433331383743464233383746323839464241343342353836384232344541373338444443323336384331423138454334454631354544444232464537393334413943394638453642393330413138463932384131343537394531333242353641333944354432374430433638343134384343413134393146333646364335354641463146433437373731334243374339383544433039343935383343363335453541384332303737323839414143303742323443333745433139334342344245313235393835443544424346463931364132454432374636373431303739413123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xcaf989c7aae6b3db483051e86e1e911297e52bce5a4881add67d99f8b7e5f82f3dcb99c782d90725dab8a184583c71312ea48faac1c20a0ae7d8716b58bc7d00	1570300322000000	1570905122000000	1633372322000000	1664908322000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x470165e7b297f0801c73553658076447c6fdc80db27f83178ba07cce25bf89ee12dad3661af52604aa8ccb5850d1f37a2f36ca67f34cbc20f955c8ce94cc6a84	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430443246333737433438343242373539313535463537444645394441414432433639364236453537303531463241453336383035433446433643433333314335383736454538463243343444424331334234444643363638343734343045374445443546323433323437413730324330323141423134453644444230334632353739413533373742363633304431363336424138303539304244373244464431313644464336343336373832444634434535453039353145333037424243363846444243463644423233423736393437413645323933353543304632384431323134454637374137363834323444373035423944444242313341424441384223290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xbe2d9c25f30bcb31e13cdc257b2fdd3ba73f6fff3247578f1636bdc7b2cce4f555dc0c556ea2c74ade887eac13fbe3cbcd8dff079bc68cdf38f3f4f6e1c91f06	1570904822000000	1571509622000000	1633976822000000	1665512822000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x42f076d2b95bba036c2864faa73592e7ff6fa28c1e44c54799fcdeed81bbd50553b27d019f90910608764feaeb097431a41009e4aa8cd2f82fb0d38f88ac4689	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304232354637303134363834304131433634333544413733454433333631314441303030424538334435373042383337424331393039434134343238453637414246464435323942463743363837443836463637444138363243434231413230463139384544353339374235463243353231413534333344353141303946354338314634424141443833353533353943354446453536454534434332324141463145423034363534394141323843393932324135413635384541334135374130373033454243344132443642423832393139364237333431424232364532413035304444394336453333444330433044333631424539383635304132383634384223290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xc2d70d116cf99876da284f857d449290ebfffd86aefae6d14aac10de337b4a6d06d46dc8dbc0e2ea27df7ae0e70002ab1c542ede2146cf3cd811f50854e93a04	1571509322000000	1572114122000000	1634581322000000	1666117322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf08c5433d98a86ad2413364e54c4107994fcae0e5ee03059679c32a658e46f9cffd1b98063b4afc0afb1bbeeb2fa182b0553733e0fd1a979ee1b4afaf72a00a0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304137463439433543423344343233393346424435314339353238323232414343443942353641363732343741373343464545303637414144384131383338453433313046303843364646463130343639433634394630364233443035454445413443464434424643394644343637393741423735414431374441463036333335344441433345373145434139314235343043373130353438414141424635373430394333423442333238314243313833354145364235313344373545394343334643344141453231433535303138363031463341413941384531314531463736424542363231324141383535464631463844453736453232453135414134433723290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xa9f04800e814f10e34f790943c16d13217bbc043cee9d5e2776f0cabd3913f0a74e410c4c888a702c4a8499ffeaca49c7cf1d91d52c5065d8a2a2502e6f8a70b	1572718322000000	1573323122000000	1635790322000000	1667326322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x6a765c16cc6018b282a8d48048c028dc8aec7985f98941bcb2ef0fe0b9611d897326a8401f101c17b4aeb22c774b7eb3fa237ecbedee457da5abb51dd9f39d07	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304631444544373233443745413132364246343346334532363335444633383935393046454535413143314232324535353042414239414535394546304434413546453545354243443433433032363838314236364534343641384442354232343931364234314133463436353730343942423046413832343636424344423031414143414435463243434437413645424544373843343537343639334233314542363837433533304637443930373935343538434130324239423030314132413742423844443942433832373541423643463844464245444130373237394530423043334444383638443145434531463932363236374444313532424241393723290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xef7783209cb2d59b3f3cda8371192a83b79799c50922506fac6f1066a7498419a6731258f725d199b264279196930615093d0f872b702e28e1a28c9614dd2f07	1572113822000000	1572718622000000	1635185822000000	1666721822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xec14c54687bb41d398f15393aa28f89f7d6cd70be0066468a60abadbdd3a3ae6f319eaf3cc4d3b2c338b9f32508ba042950163037bb162a4efff26af225bc389	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530374232433434393441423830413034423338393043423339314141313739354643444136383437333141314336354646454244383735443641393146413332374437303842423843364546363045443846454534334544363530353846424532334345393030453035424341353437343235323046443434373430303143383242383733453937323542363135384539333742393734413530463043323242334333324139414532383734394336414239353439443535334332313843463341453546313037324644374130384341463834323930453546353743444235304231364335443641393634453234334539464536363938453131393944373923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x06700fe22353164250e92e66da41275171043d6208b2fc85964be3d9e83e136f41baf7db8b0608c60d7d95fc3be4675174f1f8c85d5b67b79a7a57bc6273a20a	1570300322000000	1570905122000000	1633372322000000	1664908322000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x66ffc4bbe8cff514a1b5ad3de12554a5b39b45f2bdb1426a5b7a48e99769ab32d6d7e6ecafa73ffe03617265fcb995093d22adab44db84b51e64763f825d0d11	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332463532343145354644433530364446363439463338333031373635463431393134453038303741373638373837454133463943443838433931444241383833333631423646373533413739353944334331464345463637333431353033304130303633303836444646303242413546354138424232463434343441393241443435343845303544423344413031343845444138384137463834383645363041363031384143314534303631363238344632413241394645313730303234443842324437453842344544463930444245333445303743454430384132363636393630413743303938463736363838393831333238394534383736304135463723290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x5eb0a375a9e253b5d97d23131474d1c7856370d20e8c4990036bd3d3e944246257db9c6f8213231aa55d0da130244ff41b63c9a50872dbce2d94512405d7c003	1570904822000000	1571509622000000	1633976822000000	1665512822000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x7971793feeb1712f82c259193231ff37667b5569e77420a00a45c4145470e7824f920cc356baa584db1f122163cb03de7be41702d4b3c08f1de799f51b93bbc4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304137323242303442333035463233424146394236304234423243384542304239433731363433383937353532363531423339414434453845344344303531303432463136364238413130464334444130413030394433374431373139393431314445454641383945334531344232424541364130423735373742444130304639313346333439354536444335313746444531374337463831463246423933333542434431394539353544464236313245463635444433383532303943333246463031343231413644303441333635363837304245423343423436464442453837463342353142433937363636354334394541353244454345453941454233334423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xdd6698de017b562708cc0483f273609d4a7624fdcc5d2bb18aa5e416794939cc0c06c591c2a49e8d1aa4c2bca405d2acb43c64f0f2cbfbd114c8f21abe841008	1571509322000000	1572114122000000	1634581322000000	1666117322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x4042071f23ebfbb5943913f5568ac62d19e5a977c2c876564c898f1890ae2fdf9fc401c505e025d365c85a74c965087be0f5828f55c8323b80ac1c2a969b7fa7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330343343423038393933413841354343414141343133393737313342454239463945344137343545383937383436453935364337364143374134323942454334433038353031443831424336444237373837393144354543454544323131323936433339383942373544363733383234343943324231433931383830303442304446304445353235423131353038414442383133353935423130314238323743343641334641323546383446384234434333333843423233383841443345454633454544324132363445363833353036344533444539464445413638303530313933443437414244423335423744314537394532433942344444393431314423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x8d3f0271c25ec320531ff4899e1c9ef6a7b8fcb77afcd69f03a97b7e7165ea02125b42c26228f58ba26a8e0e341ab0a99e603c3a4234f6063b71095a9e05d80a	1572718322000000	1573323122000000	1635790322000000	1667326322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8f813f105d2bba37bb0b6247c85158a67c58f712af8df8acda9e7f85756562a388898a88dca647f3e7046aee62f7004d76b6ed0f889663492d5762c422e5b042	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304445463138434235423434383331354536323446384539374542354443433032444331354337433143354635384539383331384632453934373430464536334241363044463933363136433535463036433831393544324236373943394646344230424234413843344438333432353141343435353539374636423235364545323843323239353043303238343041353134464431313535374238394443313635313441413131374637453831353137434330373841463036394636453245324130414241303530383734313044383633323132313433414435303244393441314630374143453341393145343132363234433233443746424645304533374423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x32333aa8e339c3e42914f1140ec0f55341f8340acdb087f3e419d549e11aea2589107094bfe9fd20632ff831e270f4ac9d23c0c195e9c38846f79fb2568ff70e	1572113822000000	1572718622000000	1635185822000000	1666721822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x8ac431294faebebcd8e272767f6e5bdc673fa811bea3d1a83e7bfad483b73cb40bc070d2be0f48194ec77443a77c633ac6e307a7524e565518eb29da82ea2179	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304131373145433037313231413644424631453330414241433731383933423245394438454332354131384343343934414142453044303232343936313830333945463241463542324634434639464136323332344441373135353130454143373132374134304446333441423144323542464239324136343745453545463631393339364232303935374537314238383342364246353338343443333835464537394537363333303143383239453731433245394639394435413535463630464242364143353235363430443946433546413039353046423445453736434237453842374331323533384445433642303946384242323234373841373841303123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xb8f03f4ebdcf472555f7ae3bd0f17753e033d4c0ecd7ac261f9d190da4ad62646d8308460697311de63703e34473a65319b1e6da63607f52a68d7c4b3fe0e407	1570300322000000	1570905122000000	1633372322000000	1664908322000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\x61ed6b0b799e6267bb9665ec468f3864230de747467aa2fc2885b0cc0fc463c2c811df981d10f539569177cd3fc91015eda60d80bb0315214bfbb63be4a5ff30	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304537364538433336323646423230373641444541444330454432453946353930464633443844344545443531354236464235363737304533314336374531314435443130344543324442374345453732444138304345343744363131304436393144434338313943443246323135344630364141334338414635373746354138313637323838454445464246383835343143324437344246423237343438413145393544304541343832433834463545453930414239394342323343423230324141444545463539364136313739413441394630464436354141304442384642313343314236454243373030453046363536373035464644393132353330413123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xee2b5e3f95b2e293da273b9c31e2e8bd5362f38bfde08e55fdd8d093a64a4e7a6f2145a0705c3a8903b3fad2637f7d0fa6762da7e785369bf35588b9873cb506	1570904822000000	1571509622000000	1633976822000000	1665512822000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
\\xf05c2fe15008ac30cce45ddcfa3632d650422a49bfb785dc03c9f60933ad0d36777f00efb25243af1d33affd1a357e30dbc5949fe7cfb1f14473705529065bd3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241464638363236314345333844334344454337354535323945433338453045423435443233383534444338413735313246464533353930303630363343383944383933453438394537443246313246444444414637314234314536344345354138364235443242363646424244334136344335363646333438413136334133374234413846463331353937363742464231373733413633414245343131334632453035463435353336343935324137344535383441443045413542354342373030383231443344423434413331384530394346433635374244323031424138374343303936394142333431383633433738363330384644423632443438454423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x4481cbf1928419aa608770268fd36797d9711598ed7af1a916e62d70fc0a76404b6093d080866a823ca6448fc4d2f0aa6492c3ddae7830f17a30219f1bcaef05	1571509322000000	1572114122000000	1634581322000000	1666117322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xc62f4738f9d604dd408b620ac4465830c1ef3cb9ee83c01d1ff7761adfbd75920ff4cc232d6852d9cc178ae5369143f35d4398a516bcded9735bdfe73aa13772	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304535454543413737453330314232443730414137444242433530393242353030464538313742423541304333393443363634453831313832363034313738433838374534323845334332303334363134413632393831414334463932353330344542303831373839324141434343394246333338363730364245454632463334313031454431303133334644344332323130383837363743424333343045463738443236343645344536463843323834374630343434313035374146384631444330463845373241313141314246453241443531333531393545313331384343343835314236464237424139313546344643443233433130443331343736333123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xa2319fd871b31af10c4fb371fd72b5ca59ceb1bff5ef489435e78aeffdcb7651f6ef6471ee356c4115aebb1768a711c4e44f9db20a40624efc991c4cd9f7f00d	1572718322000000	1573323122000000	1635790322000000	1667326322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x847562354ab1aa7a71ff2065d0d57246fa8d313b1ceb90d583e549742629f739e30e7ac59515d496924b36179fa82314097d953229be6022f5723530baba8cf4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435363744314441394431343344453633413636303545423144363541364334334334304544343744433435304145373138463939304444383139323236303239424638434445393338323633444335323137354637363537434246463432353744303936413432363635324233353446444239424435423530323446333244353334353736393231434641353343373033354146344546304131303146313442384232414539454234314435414330323435393043363532383531324145313343464538344433434439373132313338324446453743463231324633323935304230454437374232374331303634353336423632444333373538443338413123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xbc503cad9589acc2ed018aa3a85cbfe89b8397af108abc160d2db050ae3d2c3b446e719fbbbb1da881b1346a5a70bcbf6ff97495e3fc343e02ef33f7b76af600	1572113822000000	1572718622000000	1635185822000000	1666721822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x32e44d828de5ef6fef3f3886f46ef25deca7b9fa9e8b55b389c6f305764f3b2aaeacad416518f22b0429373b8a7d21aeb4d54d0d1929d7daf3e9cb6b1d897348	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304632313542314246434142413145423231324434413242363135464445433734443533413934314633444130353746423135354232333239453735314634334632453533464539383735464135313832363335464339334543353044313133353839374238343637334235313134324137443037354143423943354246453641373230373642303132354446363234334539364543324445423636343043363139323643414144463245313035363139443134413742334243313642363142444133324146434443303045374131454145373642464644383933363930434246303931363944363732344245333238433135354241353033454145323539303723290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x97463efa9a92d096d5f4e0487de34d542333f034443ab1343a0926accd987e63ea96e7c2d5424e120b8a5394ae0abf41085eb27b723df10c40c7ed2f7cacc208	1570300322000000	1570905122000000	1633372322000000	1664908322000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\xd2ef5725e571d58a7c9953bc6c1380c7dc62ed5709654ca31e4efd294d18d6debf609c695df617368d5dd12eea71aa2c9826b256c70cc2984babcc7fda9dc218	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530423537443346304436323137383031424439344439414637444146383132464339323943383039304638313233393143303646453133393231324239413039443444373644384337393730444535373441463932303239424444363735394237463132453930463835354336333345333934424541454134344441434231384432333242314637373537313630353433303131324533334142443834324645354644373439303038333635303745434143434139443143393135304337373341464144383534433843323845324535373234423842433346393432373846303242343942414646444432384136454233333138434434304239304346413323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x287c0c6953b34d430e48a48dd9a63ddef17469b866ca7d4e8e1ce8aa6dd7425e0eb9dc55f7f3530e4e14610c53ed74b6dbbb2bbe9d3a5be0288da2b24784470e	1570904822000000	1571509622000000	1633976822000000	1665512822000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\\x818d9b5299febdace8c6732c6ae29a6c54b643411bc19eec8dbbd1cc4ebdd4a3f242c19c852c409dd21a3c403b6d1e249198d99f042a36c5cf5a54c1f69eab30	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946424237303937314443453037433941344646334138453839393845363844444538463634433132323545394130383139363831313031443035384330433735393136343343413632423737354531453842323836373242424646373746343834314541333544373533323441363246383536353132363231323735453739324431424535374237324242303937413536363043344632364134433836383634464238344236333336413534463343344346343141413644383034463732363738333137424536393538314643363631373845433745304344383630443743434139413546314330383341333436364632323233333441443535413735423323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xa4b28cf2d4c21da9e69992176879845dd76495e1b59fde4afe383f4e83bf50bd945c98479a79b47ebf116be801803b1bbc7753774969b25cd3ac90dba9641505	1571509322000000	1572114122000000	1634581322000000	1666117322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x41d211165a4102339e5c65a24103c196d3ea460aa0abd7698a083c8e65a05c91ce529aa9f940fab650bd17f2b3592f1292c51228607ed0446bc1b99b5de72688	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304133463232334434303830443845423136383344313535443644303641353642424245434341383937444330394338393538433032333734373846423133424339314445334430304246424341374530344443393444453844324638434235423035383438393746464636433139363444423142433835453645303530433845454139353731443035334144393538433738314146313837413044373731444233384244374444383441323435353339323744304239443045383542453941443239363732464632414645464239424436324639454537463330303738453343444134373837323939383033413634353936344145464637343446343946413923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xc0ebed0d3dc99bef1255502b7a142337ca31226c392b063ed6f69a7dd4697bbaec45206407a20d726d3b50f68c1d44f4d6a47a3e257e15e3513d441a10bcd90a	1572718322000000	1573323122000000	1635790322000000	1667326322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xa0be93fb737ee724262583900598a76353be86ce38b946c87332ffbc647ea57f6e6d255e88517a9beca554fbe4446a4a82709f6ab5a02b608980c191f0d38385	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304146444432443731304235423341324534394145353535393743333641444336424344303837383031453930413835333037413745313341333238333334333333344144324537343043324134343034433034413739443739423030323744323445413332393644443031303934324433423641363542383244463836383943454630434333303843353842363242434341453435304244424233334133383432424141314144354534394534324142434130413844373331303631414230464239363343313737333241354345314444354632373430444336353744364333393542433735464138393436373042324632413242454446463931454235334423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x8521375bf5351cdb8b87491e6d8e26944c222090f5f0b8e450e5a0d590c1bf6e00f2b2b864314071071822a7c582e3adede0333df8a4f243d9b240ec7dce2306	1572113822000000	1572718622000000	1635185822000000	1666721822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304339334241454637304132423642433236323044333643313944323734354130394642373330323938363836303334454346393439394334343643463745363233333742383937434145303846453837303233423846463843434445363438333436423532454139353730364430313232393646464438394243433730384630333131374341393339324234313246324337464144444442463937443435333538414246414543433236373645314535423931313730383341423136323342374545314244434339344239433638453845384441454633423030454242344130354546413545454134374435424641333431324245413046304246414239344623290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x54c4334a0d4af6e6a665ef1dee86d997695c7bf81ef13b4afc0b7686596dffdd999155d4b1a62d783abc3aec46c6c32c14fc1d0e440a6a339043661b4c349d02	1570300322000000	1570905122000000	1633372322000000	1664908322000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\x152d743af72871faf6f3e1c24c8552d6acc94551413185718698a04ac027ef7f98e2477caca12e2ff02702e5da06c477d087d0f678ddedc810db373c15a52a90	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237363230463541413039313836374132314533374243373345443145303934394239423032324346464631384141464239453633373244453545393438433538423434323942353037413444384644423142463734354436343532383837424436334137343645373638433642463537454235433236453041413331384246453937423536434644373242313544313646443046344438434445413132304338384246413745304636433345413036424245414644383833453845413635354439324339383933354546444644443634394343353241394431444336413438323435324539304343394342413231363639303946303835343545424145343123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x508aafda6ebb32fae7983d0c9d6842c83a6af618e02013c7d23b9fbb123a78940afa790197bf54d4e742393835895c881162994f0da69481b1d08a8ccb22ac0c	1570904822000000	1571509622000000	1633976822000000	1665512822000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\\xc72fed6b9313bc1e7378d44001499532520717171603900150c81b39953c442dd920a7faa5379b9b0c7bb69df7ef6660461903447b5532c4f86634a94aacc9ab	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304630373946353144413830424337373832314239423933313042463545434645444538443639363639373732333532353235353944323936443635424542384335413932333332354534384534423842363831424443384242383232413045354144423135303831463235383541423934304641353046333034393234433931354530334538353337353637333441384232323936454232304131423233364234384645393334414632393935354337423432434432324638413139434238434244354435364336393834423941443543333842444446333844423742304536313044333831434443323431343833464143394130363346303533313134343323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xa00afa79204d008db2c540df077f6ab70e01803bf725c108f9f32b4815026848f3b5e2acda1055c9f3084d98d91e8413b8cb4f616b8256b53d098f2be6583101	1571509322000000	1572114122000000	1634581322000000	1666117322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d1bf7de1d6ce4dc408d50bb222c722de6506bb1c34d559fe9d5dee626690d1d6d54874cbc24949b83d3188db786ee1446ba42cddd4f6dcd6676959c917ca2dd	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304144413841363131453344334242364230463441304345363845363143383835393533363942463137383533323144424536353444364236443038363735433944393433413346343746303543454243453043413041423136423230443445463332364631324230393632464532324531303234384434343535303832424438453135444543423145314338303344423133384532303832324243303837373330383745434243433333423144383842464130363239354430383039324632323339374246324438423141324446343134434433343534433845384534423237364533324145433142374233433731323842304430333330334432303043463123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x9f2eddff27d8efec66f20c36cfe801efc894a162e67263334f2d2bfea1cbb494cc45c0b70e7528117ab026722199092a0e0a65c94cc2b9d148dce26c81fc9206	1572718322000000	1573323122000000	1635790322000000	1667326322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x25ad0f342c7f3b72cbd5ef076dad4b3f2fdfcaccaef0e7d0797ad3c70bf2ea5604b069b376a96a8e505112a80a941c4b9b142facf614f7fa6cbb623cc0b1fe8a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237443844424631423236374130303044374245413443313033394637434244353334313434303237463631324235464445383139303135394331303631383844433634423541453442383046463431344644353441314245424245323446313543374244383046303245314441363036344630323239354442393742423346353541314545393446424142434245353543344643353436423233324339333644353644414135363531333731444138464245374643443732453839324336433737454330424435423937303841333039414341384246363545464143353145414239393032353632323931383637354146423939383835463635353032433323290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x2a88db490972175df48e64324999bc084b6bd066263c78789351e2d12fe8c2644d3185231c569396de5d0efd13d3aa5739dacfa0822b8904fca112bb0802e706	1572113822000000	1572718622000000	1635185822000000	1666721822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342303437444337464242393239373430454533383637373438323334304533363642314346393430464632313433454531343033303839323936433937433339413245413142383432303734333838433433454334464245463143343438433737313639344445444145303243323141423330464530424435433230433233314530353036393538383945343630313733414134393732334131454243394537354245414530323736303438443345303834464141383132393846434532333331373935304542353546303346323639343542303545423537303646314643454436343334354538363141303335454442363043353236303534393936333923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xb8bb17f713073d1cf1ae3c1be234059f300a006c4ceaa09a6681a27a3756cb9493b6752a935422b922a209f4cc5aae50b6fe89af1805cff14ffa3b1a05705407	1570300322000000	1570905122000000	1633372322000000	1664908322000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x07db921b1ebebcc4826e774b6ea9e4c8aa0efebf8b1aa1bc25aec360a232b2df42ef3d388b9f7efc59c57e2af7aa41a748796379c6dddfea0aa56de51448d83f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436413830304434313635444642433638443535313846334343423031344630424446304638364432353544384545313536413831304236303043413634423835424335303835383736354341374435383139423836424546354130414631353745333032364142413530323642373032324236433934323936424438413643464442313044313238374537303938363246364331423430463843373635393937444533324630383137344134373443343136453342323939444632423141333342324230414638433537354145443935423944383334363037453441454545324445393737464542453532464546373142454333323336323131373545354423290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x1d602f55a035f2f0464fe396046a428a0e6dc496363d814cf88d88d0209921e1156dcfd248918889144cda56b1449c7e5ca78ec21dc4068892c5bf5d2fe5220d	1570904822000000	1571509622000000	1633976822000000	1665512822000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7cf83c3dcf9ecb16743a30a94214977cbcfbff135021d234971003b149d6a0432839dbb81bcb22edbdd511ccf725b56ce4dc90b5236972c6a4dc83f663a9565e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245353041373333313245314230343844434543424145343535334331443937363341323238453246364546353944354338383442334244314530464642303345424638323641393036374434443235393938463138303633414537444639374345323643363744353730353643313238373442363631463439314533414445344535423938323137313137324444314646424339374138353932344346344342363641424635344646393445314531394237454346344137414444374445394330343646333636303834353438424442323344374641393635424642413038313134423941443832333931354345384346414430333533333745413346423123290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xc725848e223bfe6a7cf8083541d0aa65300bfb5e2bdc0275c10f0f39033a60582aab6abd217e170485b1bcd4e70bf988fda13026a1905f59e02338219c988d09	1571509322000000	1572114122000000	1634581322000000	1666117322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x8ff3d2655ce8f9934b0e5faf76467e03cb8a968aa7f287920fb936db34c4c39eb2965504d7aa354840bd19663ec9bbf66b5eadd81ed3903d41eaf59541e74840	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143464431373030334334424634393842413544343144394534344644424143354132394641313942423342363046353846383230354346413242414438444332453335373943323745443542343942464538363334324635353841303844383546434232333341334435363132393639443035313238393331373032373135463438434637323242373346323637374332373438304630423345354231443237353234463441463331303333413833423836353137434638414134344635464436433842343035313139413435334342314132373444324230393143434333344346363441463145394142323441393035394338433842393045414531453523290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xc24ba73cf65dca55416d8117d803d12770ac7b2f76b651e50889a8bbcb8d7360079ff6a873798c13aaea7721f6140cd980b0f3f16cbfb19fe9d400d5f84abc07	1572718322000000	1573323122000000	1635790322000000	1667326322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x3945e9889484dd9cfe7c734934b4b67bd055193181df19fffa9e780f087a369b177a6010d951290f4e1e9a8413e0b102699e848e68f1ac7be185b9285d5dabd6	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304335373833303830343438344138334644414538393942343635454632304641453033444442433945454341314332423530453846383135463939444533313333373239434231384335324244334537303432303631444434453535343234324137364446464637414236393142373143364643333135353531344441443231384533453934343143353536344535363945354337413643414637303334323539334643394630394638334135383242463634333132323842453744464644433430454139363535393635323445443838303838353032314236353339434231363045323635334141363430463341443635304241353832354243333530383523290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xc74cf3c91ef87592d3776640475ec6732e719cd32290b5450a0c5dfe634a24e3d9a90989f692fe078b0016d6135184be2b29fd9d9dc0d003c4de136dbd504407	1572113822000000	1572718622000000	1635185822000000	1666721822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\xdaadc565bcea053656fd90e9037931910e4e19fcdbf2523a701e8b44f26ed795d76584e677f01f608b6ad5458609b2a4212ebfe213bebcbb0940e6688f1d7fcf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434343243423035463636463239463338394535453334394137343132424544373033443036443136383735373930424332353446303234324436313936343737393832353738323539343433393839463533384430454341314439353143323939303535303536303639363446384339423843464539443934314636333235463638323731464630434341463338444131333543353431344544414237384242354432384237424639394443414346393641334244433632444131343635314146444234304631313732424542323835324530314631373236313044354445353939343934423930363235363130334243423236373542453146394234413923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x2d023a38a6026ed7342cd180325e055a9620c99d24ff89870452ff56e8b2a6732ea3f85055826ece4a4861767b20e6bd9cefdc61f6a7ccc78d581ea02236940e	1570300322000000	1570905122000000	1633372322000000	1664908322000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\\x590334541cd74de85faca38dde881b3bb3cd2c3c3b9e74b361ae054feba6c8662cebaa5974ed8350729a26fdcf8ba45bdc732377749b7f614d63330943ce15ee	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139373936343433303036383933343445374338313346383738453231423441463838393437434439464133353943424630423844423742374135413435343533443831394232303331443331413733364445304439464237303443433342433144393732313733324231374541393133383535394646364542374632303836304631323635393733303546314431343443343636313131414233383443353942414135393442383733413636354237303743463437423333393744464239314235373838414432433331363342303032353938393735433839423943364544363241303945383136434535374634414442374641314141303041353534333923290a20202865202330313030303123290a2020290a20290a	\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\x3550745fec67e27cbffd6ee28cb6679be2fd70a3d709c6ffe43fad5d51f9ecfe321db06c08d4bc2a35b4d7ef72fd1ecbd41e4cbc74660a393fc0fc68592cf60e	1570904822000000	1571509622000000	1633976822000000	1665512822000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
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
1	\\x74f3d1aecb78e298dc7617ae40634b515ac85ec8f5c5d5d034228d5c386a5c5b	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x01a90445cc78c2ac26b5b56138b1513c7c4fb3c3ed531099627e7247d418234fbe744fee6b1ca76423c4277b1362b42fa0398649449d785e8d6e2a4b19311005	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
2	\\x1a7fafc14262335d655a89cb451921887a354e89a45decc7cabab639688e5e41	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x5b68f07e8794e030391aed899002b5e1de70d184c8fa069f5b7c24463b8fbc341b7937b4fb44848e80b3166cc555a936c5a4ca8e657e17d188151ae22e3ed50a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
3	\\x2dba7dec0cb368be3075d9e307f6e49c6352811c5fcbf1d0d49d80d17c76bd73	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\xe3c5cdf4274da667618195cd1a5e9f5de630a44b5305a5480f88652a663362d36a5bc4f0e613fc0a117fcf81e47428b60033d34e982b81403745debb81adaf09	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
4	\\xd698d9b6fddb52bc5eb6932dfaf7f7092741cec538b03c05f558919f0e45d081	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x29322822fd93fedfd5796aa541d4cc948b50809d819f557717b86ec66f794c4f43295dd07b2c70f0f09de4b5e611d9d9b1356a625eb5475eeae52bee0e936305	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
5	\\x710def7a8aed62d29fed893375544996e4017b9b9b37773e0773d60d4153ff25	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\xde135cdb495d1371d8551e6158f7241d7bc7e327732b56960cffff9282a80653d267e98af47da60ba83f15a4ea039bd33fa2cdebbfbb682f6480795966c9ed09	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
6	\\x6f59d94d7de1c19e50b99def3e973eaa8108566c1bb27147a0419880395d45c3	3	20000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\xc455aedf2e42331618d6dcbb7f16333ca24f00d3dba48e6551629167338f6b161102ada2773aa8ddcc5ecb95592a5ca53cb2fd0ff89c9f95dd4b5ea4bfa3e90a	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
7	\\x8b7302c526db05f04e357752ff619aad5b5bb4b27610eefa2fca5cf0657cff5e	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x8dcd18892401438cb71ec4215ea8af69a651ddc03594ab3e36231d32a884818109b98e2f5f730bd8c3602d040b41118f709f45d17359b61ad6ef787fa22a7c07	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
8	\\x7fd064d33756cb7da6355c3a0d05619033d1f8c88f8357b5cd41961fe68095c4	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x08f97ab52eac85e0250b17ceb85b5a34101267e3fe9823abe8dbe0408741f20c0a5b22e1093107ad0fe53ea70d312b2ffc36e10d89f5284af407169a3f9b290c	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
9	\\x84b8b25c26100eb596692804e820eaa6221d2e318d568538a0c5e2fb279f3605	0	10000000	1570300342000000	0	1570300402000000	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\xf46b2891be4bb2a53f24edf3c5ea328efd6ca71e9457725a9d0c183bb559fbe18332a3ff21dfbd6a9ae92f3403b60e033d80a2a69e860710d76d9c7ac81e750a	\\x52076b7830d9901c514ca12b518ae431396847c3c0e9b08f5ee2413c7c1bc0b6c06bbb95d08ccdaaa2fcd350f853db865aaf1502e653c8f917e7ed24396cc302	{"url":"payto://x-taler-bank/localhost:8082/3","salt":"5EHAZF1WG6BSAQRKS42J58FYP1VPM6VVK7ZZJQB2S2SHE3CJMCVA3MDWM4KXDMH3JH8P0EB432Y5Z5FP5KNZXZ38TJ1109TS9SPZE78"}	f	f
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
1	contenttypes	0001_initial	2019-10-05 20:32:08.686239+02
2	auth	0001_initial	2019-10-05 20:32:08.710617+02
3	app	0001_initial	2019-10-05 20:32:08.750277+02
4	contenttypes	0002_remove_content_type_name	2019-10-05 20:32:08.771019+02
5	auth	0002_alter_permission_name_max_length	2019-10-05 20:32:08.774629+02
6	auth	0003_alter_user_email_max_length	2019-10-05 20:32:08.781412+02
7	auth	0004_alter_user_username_opts	2019-10-05 20:32:08.787864+02
8	auth	0005_alter_user_last_login_null	2019-10-05 20:32:08.794128+02
9	auth	0006_require_contenttypes_0002	2019-10-05 20:32:08.795389+02
10	auth	0007_alter_validators_add_error_messages	2019-10-05 20:32:08.800526+02
11	auth	0008_alter_user_username_max_length	2019-10-05 20:32:08.808101+02
12	auth	0009_alter_user_last_name_max_length	2019-10-05 20:32:08.814651+02
13	auth	0010_alter_group_name_max_length	2019-10-05 20:32:08.824074+02
14	auth	0011_update_proxy_permissions	2019-10-05 20:32:08.830593+02
15	sessions	0001_initial	2019-10-05 20:32:08.835559+02
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
\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\xaa286be6c7b17254933b6a87f3eb688cb7d07bd15312b9e6b940b5a26f2c9ed15102175c205ad317f7a9884146d890209f1f6a69a801b4cd7ebee5852bd42803
\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xfb8e8fc6e242900903406803a3d7f3c3975cedd1e2df4a037bc472b75c7a4999ac2c86be85994804ac044c44a4c9b5a83bfc3717744913035efe5d286f31b40c
\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x2467bcfab8ad8576afdb539b14486472efe822d2ea646c4930913ba9d959ed544918b6b5fe35c1a6645391fbecaed925b3559054373de1bac481eac8eec92502
\\x6b1015a9a1664330ac47b401354641fa98182becf9a3a0aa2735e96ed1c24cb8	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x0a78a842abe7c4bddad0f13ba7865a55acc08538e568d509b2ce1c76913c118f6f1d4458e7dfcf8076c7315dea07554912fbb3ff60f7a782397c01d4bbd4d70d
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x74f3d1aecb78e298dc7617ae40634b515ac85ec8f5c5d5d034228d5c386a5c5b	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320234339463639324631444445303038373346463433453243334142343334434242353835334233453639424534363743353141454531414136364631384136423036374542344541363539373936333143414334433742444431374234324330454341413032414346464146464631414239393145394544323444324239443741393332353944374142304338443146334231434434463339323146423046434238363635424539374138444241413041383946343534354336353831353937384442343439384339444536384535443042464632354137313939453339374635413434304543443843313237424339434634413745314338423943323132324523290a2020290a20290a
\\x1a7fafc14262335d655a89cb451921887a354e89a45decc7cabab639688e5e41	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320234242423736313336433543323639383834343432333837303635453339384432323936303038324645343145393235333838383243464641394338303934314542463233383237303234353833414142463038314635304333454545464231353146453335454433304542333344374537394138363539464539343839423343443732413142453442334337454144324232463846374430434442464134354333433744464443314632453343443838394635354642373445373441304643424341323539454336354638333333453946443032323243353832463241393531323241313646324137434230334631324638413643383833353537323137443023290a2020290a20290a
\\x2dba7dec0cb368be3075d9e307f6e49c6352811c5fcbf1d0d49d80d17c76bd73	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233830433738323634364236434431374630443739393937344337464339454134363639384242323441394230374241304442394631333737303742454437413430443344394446364130353437433543303738303543374142303937374637463044464633423743453537413733363531444445323444413837304339334645463638454545334346384537433232383442303346373142304244323432303637364543423636454343364535374438323931343944323238463236353037333931323237334639333632354232414344433537314641454145313241323533313335414345303641353332433132303632374136323341463242374432303523290a2020290a20290a
\\x6f59d94d7de1c19e50b99def3e973eaa8108566c1bb27147a0419880395d45c3	\\xdaadc565bcea053656fd90e9037931910e4e19fcdbf2523a701e8b44f26ed795d76584e677f01f608b6ad5458609b2a4212ebfe213bebcbb0940e6688f1d7fcf	\\x287369672d76616c200a2028727361200a2020287320234137324438453132453344344433353036314332344342434330463639323232323132384332434642423446454134464535433241383330463538343735363937343538413533463343434441334535444631444333343430423534423338383935313539454134463932443035344633314545354431414345413144464530323632463543363944393333453738373539374331423833353336363831424544384331373830303646443039414433304544344136303131374636423642353338324444333946394131433333394531433330393146393344464237324639313234363536313543373933414142363236363038453635434238354442423723290a2020290a20290a
\\x710def7a8aed62d29fed893375544996e4017b9b9b37773e0773d60d4153ff25	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233133464543454246413739363132383637464445343334383035384344373336393137304236363344423236384230303442383638354531313131413133363543433441423541424337433238443744423732424242324639444543454138364530364644333041424345363330344138303344423936393244323544363842383043363430333336333338444335334630373339343833423238424531413634433445324338373932434236344443363445364233343243394235323442323445464245353431353639433545333037463144393242434235434242373146384630323237453746313841304333303842373531373045424533464431394523290a2020290a20290a
\\xd698d9b6fddb52bc5eb6932dfaf7f7092741cec538b03c05f558919f0e45d081	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233241394632303445374439303646413444393142343235433346453537303536453738423343424232303335453439364538454343423039424235353645344536464237363332373931424542413639453845393039364138453937343544434530373543463838354237453141323341394537344145313630394533343736314238333436304637304346344436413333414630463541444231323235313742303943414642353830364144334246434544433434353742303835394641463536383937394631394237324135414236303945303338303930423338444537364631303542394630394430303534463930454344304630353135433236363423290a2020290a20290a
\\x8b7302c526db05f04e357752ff619aad5b5bb4b27610eefa2fca5cf0657cff5e	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320234132383239444444433032463244433334394646383435323731314435313437304434393036424531383845443933323544304234394535323136384135423243463444433542373142424430313130433932324333433739463137344139393830413334363543373944413037344335313544443635414236453533373635383931413534343445343945463533334537374535463835423145343941383044344233363443424541304635463441424232313142463931354637323831433544333143413741303541314435323438304544433642334141453730393639364143344231343534413032374544444232364345434543333333323531393323290a2020290a20290a
\\x7fd064d33756cb7da6355c3a0d05619033d1f8c88f8357b5cd41961fe68095c4	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233146353939433741303432343346443944353239453341364641383741384345453732383444303638313142424343383934384536383435433130333438383132334543323041334541423643384246394439424242443533353433393231343832374139333644443534413032423732304333413834364637333835423739353844464344343532353943394145323845354337463636453034443245454343303233434437433633433139344141413045453734434539433043424437304534373144343630303035453131353932354144303042344435343031454533433235414339363038353743363231423443314634333733454332383933323323290a2020290a20290a
\\x84b8b25c26100eb596692804e820eaa6221d2e318d568538a0c5e2fb279f3605	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233838454432323237343242453037434532343933383936413333413031334434354439314238373345343037434544353239334634323543344332423933423336313530333646393143463438334635313739343734334436343236433734383633463042334139393246413432373137373338383644393143313438433445343232413938434433314332363833343638434531363830393230383442423838303841443733423144414245343332413344413738443236363045303336303044324346434643343339393731343445464237304144323238374643343544433037414446433932383731383042303738393937394335383230344333373723290a2020290a20290a
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_id, merchant_pub, contract_terms, h_contract_terms, "timestamp", row_id, paid) FROM stdin;
2019.278-G2H1R324A470C	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3237382d47324831523332344134373043222c2274696d657374616d70223a222f446174652831353730333030333432292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353730333836373432292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2244433831424144314353314b314232375047304b41484a315a41433147415a435a3648543141483736514d50584d4532394a5730227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2259484e4a483444593945534141465334585153574254484a48565950533952594a48425134504d5831474333514441535a46475236434e335a5747585a4642414b424d4a5944303350523730364643304d414b3958314737323342505637335453304637413247222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224b414245433654414447514b4e345a325938445242393133525344454850355036424841314d59574a354d524235324d4b535447222c226e6f6e6365223a223753324d3345444b5353573330435651535245464e455947563158355858375059594544564d5151423238423244534a56515130227d	\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	1570300342000000	1	t
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x74f3d1aecb78e298dc7617ae40634b515ac85ec8f5c5d5d034228d5c386a5c5b	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2247394a37343445323630383334584747545a314d3142384859484332445a39395831524b4b3339445130514d425452545137314454434d314237364e5a54524d4a51573238394b59423644464632475358314d334a4e315834394d50594e59523042454b383138222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x1a7fafc14262335d655a89cb451921887a354e89a45decc7cabab639688e5e41	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225259504d355344395a59375759424335444b3157394330543831423243564b564d46594a344641483147464a4b5456334b445346374357514a383237594a3850445a56533658583234535256515651434e4d35384e433945595238584a3430534d5a3845303038222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x2dba7dec0cb368be3075d9e307f6e49c6352811c5fcbf1d0d49d80d17c76bd73	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a225253564a41343942585a4447563535574d5635325948454d3237345344444a4e505154394257373248463758373044314a573248383332514a5744474b564141364d37433850564e4b5732424b4e3630504153474e445732324a393556484439514a5743413038222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\xd698d9b6fddb52bc5eb6932dfaf7f7092741cec538b03c05f558919f0e45d081	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224a52593154535743573957413852305734574447474b54323337313146434558523358484d38433445445447395441594d344d5946375835315338384d35444745514a48594154304333483352594d3043524337565446393350323547425950345938364d3047222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x710def7a8aed62d29fed893375544996e4017b9b9b37773e0773d60d4153ff25	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22334859474a594d5257525a334a54444e3139323446383534534a5258525233384b4133424d46514b4838314534364331305251333441395658365032424a4a385631485741475931414457595a5352503044505a4d5145305a584e3747325850504a5959473030222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x6f59d94d7de1c19e50b99def3e973eaa8108566c1bb27147a0419880395d45c3	http://localhost:8081/	3	20000000	0	2000000	0	4000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2256325647325039463737324744583344384e5456444d394837415845474d5846334645474643595a545447393242515954324e42425a504447385030443752485356564e5938374a594d483945583944524654344458545a4444374d5331463746323643323147222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x7fd064d33756cb7da6355c3a0d05619033d1f8c88f8357b5cd41961fe68095c4	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22524d5342313057344e525a35594438445641484b38393532514e31324e583430585744365238394b455a47314153373931355956354547475230534b443657515a4a58523650364a3358454847383530414d564259365838583447453144365230574d53383147222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x8b7302c526db05f04e357752ff619aad5b5bb4b27610eefa2fca5cf0657cff5e	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2238375053584b534e423445484634395a30385632354b4b364d47424d56485a31425054533046315956415953453743325453474a42393758474d4851415a5647384b5a5a455231395a4d47575034454238533554424e4a3735534a3157325158513136444a3347222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\\x0556e7d985547c3d2e0276a985512ddb244e75cde646e1f0cec7d4ec734c4e6240958deda2d9147457ea498a1bacb29c1130bbf35fab55c7b10e06c63e3278b7	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x84b8b25c26100eb596692804e820eaa6221d2e318d568538a0c5e2fb279f3605	http://localhost:8081/	0	10000000	0	1000000	0	1000000	0	1000000	\\x763e83b99b8545fe956595137541397c7287b89af428fdd2a8edbec489b0d574	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2244453550434a54304246393447584647414b514757564b5442345050444d53305942524e594b4350444b33504648535a4b364b574647385859384630364335534134375351425943373245563543313054414d4e345752365745574b563138474244444e523147222c22707562223a2245525a3837454356474e325a583542354a4d395141473953464853384645345459474d46564d4e3858505a4339324447544e5430227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.278-G2H1R324A470C	\\x9a96e61b4a6c2f3a93e2f21b85a423c65ae8d8b632e2a0d3dc91698594549e75	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3237382d47324831523332344134373043222c2274696d657374616d70223a222f446174652831353730333030333432292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353730333836373432292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2244433831424144314353314b314232375047304b41484a315a41433147415a435a3648543141483736514d50584d4532394a5730227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a2259484e4a483444593945534141465334585153574254484a48565950533952594a48425134504d5831474333514441535a46475236434e335a5747585a4642414b424d4a5944303350523730364643304d414b3958314737323342505637335453304637413247222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224b414245433654414447514b4e345a325938445242393133525344454850355036424841314d59574a354d524235324d4b535447227d	1570300342000000
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
1	\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	\\x6f59d94d7de1c19e50b99def3e973eaa8108566c1bb27147a0419880395d45c3	\\x232b3f6d53f81143e0553d0accf1290f168563ca65b524fd69c375a7eaa5717ced0129215391aec060ecffd04a1f60135c6218e97fa38c1deab962ec94f11d04	4	80000000	2
\.


--
-- Data for Name: refresh_revealed_coins; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins (rc, newcoin_index, link_sig, denom_pub_hash, coin_ev, h_coin_ev, ev_sig) FROM stdin;
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	0	\\x664492c0bb37547d4afef062e0ebe8a1aaf6d3213f3fd9f8c5e34917fc2a1589ad679d84538088002956c6cad0795f82c3775d5e3b0f3286fe281de6f7a99e08	\\x8ac431294faebebcd8e272767f6e5bdc673fa811bea3d1a83e7bfad483b73cb40bc070d2be0f48194ec77443a77c633ac6e307a7524e565518eb29da82ea2179	\\x2a250766b6eac89ea9322c4c69e136e56581866e4d8aa470adadad2eb4b307e919c407459094740a599ff54cadd9d0757c2aa5f816ece1428decb0e426a5251bd876e926dc265dad51e11c504a804f7bb2835e17e67834ca529d487b33ac46b9c1db3f4409c1d7418315a67ce28ce1925949527e87832845039194fac3ac5434	\\x9f8fe635a04ab678aa0ec7d58a17b5b010a40b10871b5c90e2959bcf440c9477545fb26c8e5a5eaf64e4b0514ea3f1feac8ae198e9d7862598b8162c5d4e6a49	\\x287369672d76616c200a2028727361200a2020287320233730413844443942433444414638363831433946373031374434443031384541334532344230334131423442353539363743313536334334373735373641434638313646463137343936353734333831344244314238334335383732463839304536323244343244353835303343353733413638373445354338464637303643313932413139393830354538314136383235323446343939324332393334413533414343383742363331353844323230463033413941433032303146383045393539414432383539323544444135303042423338333442343333423031363338363036363634443936314333463739313231303537433837453146414535363923290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	1	\\x67115126296ec45cb5b61647425824e3a6f497efdd5518c0eae96add44526ce0714c44542989fc1e7fb90b6c12370c5630173446879e9d2b6640c95efcec9d01	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x2cdc47b9e72ceb657e03fb55fd92dabbd99d1f24cabf942ec11b8bd8713812877e1fcc2532b209cda1d52dff27cea7996518ae3b276a2f76938574e812dbcdaf7be7e8d55f7ae754f4e7cb642786b2d555f5a16cf6a3941646977d98f6bd410cfaf6b9e392f491835a8c66f269ad7bff5eece4ebcdb0ff9637ca5474f8c2de1e	\\x045caf27f9fc5cbd270bfd8740428866f4d6efc85cabe94689960731a3ad50eded2b97c6280e290c86852f3800daf78538a837deabe9b7ea3bac63445c4d2c0d	\\x287369672d76616c200a2028727361200a2020287320233634443042334433323731373334444132393336303844464530463331393236354633333536423643343438303538443244334230374134453437393332413135343335423739383731334645414331373234363044424146434536434238343636333438443542414630383232424238344241373841464335333545414341414641303936343232363833413235333444413838443631333745423935394630384536433032323334423642363941434144384433384637324230423836383444343039334243443938363334393831364235313230303542423235344243413244433943323334353134354236343336354331373946414642314237424123290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	2	\\x71ce55f2af82f57c921fdea3f8823e711bf55f5991d41f779566d17b2b2c549d090a352fb45225d5b28a90561a0d7c57ae5e9cdecf862654cafae0d5f1100b0f	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x0bad0dbbcf87bc232182e6bb1525cbf69a7367731236664b52fad0fe1f292fe7c17f78f0a84be33604f2addce16734cab8434dcd1a89b7cae7ef3733b4ec06b9cf056a111834faac97e6f5955d1cf70c5e22b36508e06f14a95ee6fc101b4a4a2b3a7b718a97eb625cb9212abf625936eb086a8ae4d736dd3fa0e0356a9aeb4b	\\x81930ad11c16808d263d337e362fcc5dd50372398d6836884777f3d0eef7ce76d69c65f4ca44b3c80db504717800742c1f5fb7f751a8fc4a8bcd47a8b52b1d32	\\x287369672d76616c200a2028727361200a2020287320233846353532394146363044433342334545333744434144453543393546384241334544333043303035453132343246443745393143414537464436374644373041454633434438374646364642393338433942423735433330413533374130354438424336373745323536454333304535443832334337393632304643334144413144323332353534303635304235464638383737393046363936324237433541364634453336363646334435383035423942374137463543353135414146463732464438353639333539313032313837383746424643423843454136393335313545463630414141343943333342303334343439343043364137383433303323290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	3	\\xec8ee762b85ace3cc8a1724f55cbcf9799e324db6c4b4f9cbe7e557f9b0b12de8e294a15d1d2a8d44f3ff8696e092acb304fc054300ac6ae783a9be5508a8e09	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x7830d9c8dd3ac113263ce9b5120db60f8f4d4b327bbf1259eca4af148b10d349ae16ea63e849bea907d7ade2d8ee79f454bc8991579ff6fb742c70bffed9886be9bff61b4c7af409c763cda6be54c273e6d06e199168331e56817510a5a9f3a602b35f676c7bd8091f82057d4070f8753319447e562e06e3c59722b5b4f76c89	\\x694b530d2a546f8ca4cf169c6504da9a62189599a8b826375921c6a0d7576e0c31d445b6cc59f5edf4ac9af5405d5bd5b3083396d0334db1e8fdb3ca09902446	\\x287369672d76616c200a2028727361200a2020287320233632304332443043303833333839344546343635373632363837444337373037383044313234383941304241413441373637344432424438434133433431383845313433313234323235334241393836463436453135443738334434324633353342423532453642443741423746464344413731393033384639314138383230344141333842323237453633444337313236394141333934324234383936353233353543464141333046383933453545454542464541453745443035334541353939363330423938333332393841353045364634353533454334374242344139394141453630354638463031313134363841343634314346303545373545443423290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	4	\\x7e76bf2a121492dc373f140f4dc85df626bd7a08a41fc0a341e8fa0d1fc1d37358491c7d9d07709e8a0848aff570040051e4975f45ba565569bed0eb9ac46001	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x9a24854a4afc92b2b9526b764f0a8cb197b0f3033a9224ac68279e0ebaae3d76bf409e71b5b57b9b0fa4f70ad8137e0edb4e7e089d371b543763261ab5d02baa5e28ee0f1ecc5897a87b8fa086b2c54b77d491f2f812bdb80ba4e3787ad311915388d06aea5dcf4f6631eca2d1ada233772a9f098d6169b81d95c25419da7f99	\\x272d942ae0c602674c84fea57546856ac4039032cc9af29b9d202d47f9a22809c57c389e2276f740badc0f4a76d81dedbfbb2384095aea174d06c27dc766e433	\\x287369672d76616c200a2028727361200a2020287320234335303242383642393841393039363134454631373942363841394631313737353732443745323232393234373235463932414534354144394132353938344232324541303746393243434643454543333444453136433230443739373032323239443935434537433842374132334632443944373532333231464634413838414130423331354537413438373844354445303330344146423436364546424139463531454135383335433443324138313139443732344138314333464133313331393246384231334535313932394534463838443236444635334237334230383836343937413839393232433234304241463930443835424630454245454423290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	5	\\x3dfc68c83536dfa2be50fd5b30bdeb4a259ac419417acffc3d88ec69d5fbf69cbba415f8c37a63f31b4787348ba42556548d2d24650197ba626b712cd95a870c	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x7b1903b7a37196a18874c4365f6aeeb0a82faacf239c2a96405d0aa3379e58f77a966fb2ceab8ba6cb462d8f4f1fd816c05254fb052979d00815756238163456df6683c671fd80a9c140df31438af95a18cf37300bbc659a807e9b72c20ecff37cd91cd30f288baf4fea60f100b87975dadceb09395a8fcd8bf9c5de53fe2d06	\\x0fa21e3ad9349368f6fce40fe108edc3dce9ed88f4d6092db8e9b8e662fe9dfd8a81354dfa379a4ab570626ed9160966770eb994ef15fd3b86e327c4c9920e32	\\x287369672d76616c200a2028727361200a2020287320233836374135423635303746304544334238333038414131394642444631444338394246423135423141393639353436454430383044303942384132344241363330393135303841353646304542323141363443333138393034324642434136464334393135384441343143323536463242413139304233384333393936423531383131464631413744424641423243463238313645373641344241353131303431323941373932343239374541443545303141334332434337424338354444413444463938424235414635433237383646323938353236453743313038394634314339434632444544384643444135463042384230354346324143463538443623290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	6	\\x2b65182b4e6c0d9704a3b6c8e1532afc1006d2f8de60b1feab33631067b759f3c08c7ef0a6b1be21856e6b43f8f3757799f2b025d5356159875fd7b668819e0a	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x336b460e64632821e7fd4632f780cfa7bff49831c029023b8c5b078fd1bb9747a64ff3d75919aed6243fa5a96dc15a413f4ed6cee0d11066714d8c954a81940dfc19b49f4b8787ac37212e5029e711a8840b39f96a92c21536b139fdf991f2ffab3ead63f62c7fea43528d6383d6481e765292fc815ed3d8975a70a0ac382ef7	\\x8c56fa7d439b80119d3e7d7380f53ca94f7cfa47901aa478f4e7f2cb163cff8d594dbb79468294c12da70079227d4f6d8d5ed8e6bfef2e361f8e0102880a1e6f	\\x287369672d76616c200a2028727361200a2020287320233035423932343438383341354631344244354433334542423235443743414646343036313435363243423638383342394341313937414546394644343735313046313930464544393541333743383533364130364130463543454144394136353744454545353441323341433841423535434237444546353938394533454138443546343837353242343342374537383133434146443034374243364236363043314632304645383346363736313136383033384531303346424642454535414237393335323233354536393342383238463638314342463133364635363639323637304531364231364634353230424237373542324234443332464246444423290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	7	\\x83c04b1f96a1ba2f25f8cec9479a15f577231544c54507b6cc7871dbe7e150e2cc7c4e4dc3fdb6a4aea995a299e9461cb728587e59f4278c5a345add236c860f	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x7de5da801c537bdea0cf68a75aa235aa8c900c1646638dcb1312c2eed7a12a0a9b10ed2a8b904cd5c98dc314e8dd58cce6fdb7672433dcb2b53c661e514c954988812e7fa7ba3d27bab681d3550bf94daf1b271814fa9c4c210208a9ff50b6f43c2d2ace93192216a95e61992f32723edba0c5da199e2b7d08b61f08a40415e6	\\x41b28ae34df2c8528a054c4be6eef0a4dacb9ca4b6a147e1a62979e3d124fbc2cbc3c9a6df40a1f6bd3dc4a3539b727df9a504fefb3d84f4d52513500dcfee6b	\\x287369672d76616c200a2028727361200a2020287320233732383044333938343645363239433145443832323133334342393044323231353633343335393338413534394345443733443339344146324236353643353133394536394141454441423045313137313737383645433737384135394646424239353441393334333135434431324330394443334437363838393932443835433732374335334435423031323935344534303044353431443536433633383741354344463432393130373143344545333531393743394343443836433031413739443645303143343035454331303837344245354435303041374543383943393645463837373039304233383738303843303244424645323135354430433623290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	8	\\x5c414c01b0c4cfe82def61b6098e142e5242361974c6aed221af23c2d8560286fbc40603dd7bcd5d82db01401a2b1eadfb4f78744f70f06c281045171113a609	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\xa43678b90e89374ca37760ab3efd1b4349b573baceaecc890a9e523c639f610859ae0f264f12541f69d5858ed96007b3957c88b5512ecdc45d5f1ec7d719b68536281e974a5c470a34d6eaa6acdba58856bd9c113f9706cb5ffecc90327c60b92ba24fb07b6a8d97d72cb797c72cd6a428e531f5346362245310eac9a4d8bfbd	\\x9e0d9ed7848d441ebcc9686c7f2790eaf4402c1010233920510a07d5a005faf813cd0cbf35fe395f4259cbb71214cfe432eef63b49c1f65f3535c87974e00c74	\\x287369672d76616c200a2028727361200a2020287320233839393133393332333335463645303937324535354138354634363233383532433337304345444130344643364432413546364439464637413334383544413334433133423632313634454241394443433233353039333236363645413146464138323741384437383245353931334630354139343037423835374237333442454442323634344234454431464544383843424135304236343539333030353738324346424335323337343533463936303338333145343941463638453645424638423335463239384130454641414332463534313235343232353345413732384141443341353845463539353245423337343041343044333538344230413023290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	9	\\x262a505cf210928b0f3916a8d7a8550c9b9abce9b65322acdb7f204cecbf3cb1b04240efe774c5eb6b5f74d42a47b5250b3eb2eb17f07b2eef7d511295fe7805	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\xaef1170f42d2816e29d3d6a7e892413d4feb717d2f0556059eb470b4c7f8b399b96de23f64e46f80d2019ed80d6374ec6fd631d67cd1c7fefc86ab6d2d657ed527d490fb91cad8aae0c90d5deb5b26d1c58f548090bd54b388779e301f0d953b0b8714ac78560c18b4292d4f7a1eb84a741a791552d8967cae86f8dec97ebe70	\\x1a95a2fd6c02ee69c79dab6b822565fa905c999d6ccaa0ef99ec3550744010db550c402167916c0b5b6ed6cd6e8e800ef387bbdd416aaed412dc671b558f0a72	\\x287369672d76616c200a2028727361200a2020287320233730354136313742334234344641443646453939334237353731354644384432413445314531313433304241334531423945304331373444313530364643394633304432423945334331353333383546414230324644353044433142413345353445433646463645344237363831423734354638304445323945453938354242303842384333433839304330443046433230343837374431314533374635424239423036374543424239413445453030424632433935314337353239374243394330333636363743363843313637433046413131423341453845354139333233434233354243444536414532384643323546344342384533424544463835374123290a2020290a20290a
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	10	\\xb7ba3aad56f8c4b22af786151a6dd5b9a47d4340451f7d381fab26706775120b2a099380c7c3cff3451d1b361745b510f9f30c0e9c2b05d6aa32468b27339700	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x2bffd2e4d20553d17577abeec6fea31d26188b0fd3254101a86da3cf489eb52b7bf545f4fe09db8dc6a946d5d3f1b91aaaaa74b6bc6f780b43dccaede7fba5020c1bf87cb19c07fb3298280d0f75e3217febfaa03da7f79bc421924a1ae8f17354b2d71a3625eb545dc5255f64a73c03e4d4b09ed421ff503dd427a8034fed71	\\x9056161be69c82fa017d946f6a9a2237599fa9e271eedaccf307989c99a8244ffd1d0e3387ca36983d0286b2651187b5eae337843af011edad81584fc16698dc	\\x287369672d76616c200a2028727361200a2020287320233644413232464637343939434446443141323443363941303343333132444130323439444131314344453335354338353933374438463233383730454632333339374531353346363239313137433830334346393642314141424445334139324135373844373630333034394332374330414534323745303532443342463431464244324346433337354233423737394635303230414543334641423035334146443234343637343744374238303343464546344634333638303142373941453041424445413330443135313745344331323745413632444345463133433935353736444442344446354241393238424142433739433744363830353932333823290a2020290a20290a
\.


--
-- Data for Name: refresh_transfer_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys (rc, transfer_pub, transfer_privs) FROM stdin;
\\x05decbe80452ea33149cb03085fbae7df31c1ea7c64bbfb2cfe3e3af25c8ccad56d4226072197e2d57795a439e4e055ee9667660fb5c8a6e4d930d3ad29a13fc	\\xf68620a01c421e9e397e69bdf85d03b2c83bdd4bd49126f8530fcbdb94deadbd	\\x3fc44c453e09a6d4853ce322770540f48ea31a553f1c00b8732b497831a63b58140bce26cbfef5910f36d00168d5353e95530e2e47d535bf9f627892287fef5e
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
\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	payto://x-taler-bank/localhost:8082/9	0	1000000	1572719539000000	1791052342000000
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
1	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x0000000000000002	10	0	payto://x-taler-bank/localhost:8082/9	account-1	1570300339000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xf05b766952ac30afd13daf8c67c8a6a59e37123c95b156b205750c2cdb8167c70fea9b37fdc75c14e8116dd30a189b92746373d3ccfea995ca9d10f994cff6bc	\\x32e44d828de5ef6fef3f3886f46ef25deca7b9fa9e8b55b389c6f305764f3b2aaeacad416518f22b0429373b8a7d21aeb4d54d0d1929d7daf3e9cb6b1d897348	\\x287369672d76616c200a2028727361200a2020287320234535344144343942353738393745344536333631464646383633373239373442343132313632363739443930463831304235374334363843363635354633434644373046443336444544323235454533464246444339384146383345413142383546464137463131423645453544424330313434464634433638374341413439303534334435333634323936343635304137463346434339464230324439333231354243424639423232453836323244433545423846373336393732323942364432453444444146353642423846444539334639343237394543373238414634443536364332383733354234313338393338463339364431433044383946394523290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\xb49968a3d92ce3b407e85048813681754e6d4bfabb9fffd11e67ad4fd1a284d4ced371b096c9da43ef5babba44501962e59772a20f1b73c347c503fa3d2e4b03	1570300342000000	1	2000000
2	\\xa53115ca85a30aa3e8efa86d400e394033b8bf3a8dadc6abfab6134a502f36f06e6cd4f080ded4c2fa333c3c73352b01f06e0f5cb890b7ffd29e7da2e47d91b4	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233537324236464432393635363044423631463038304633363532333936383537383235464434443741343630373144424235333134454341314337464345304232413734354430363937343642373333413532444344314638443042394341314131343341374646454544383644463034394430374344394539423230443439344645304132314346453638384531343141384139423338414230464133334445344635323131374633334430314137463331394438333530413245333235324445313739364345434235353443463936314339314634313535373131394242463545333545393634334432313941313744353134323931414233433042323823290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x0d91bd65def21d13e9f302e4d44a558a30a4e7eb1a5bad5845ec3ad314c74f64d14f4cbe1463365c6a4edbe44db7d35506aee968214a29e40fffdeff7d44080c	1570300342000000	0	11000000
3	\\x95d4f2c202c36e2bb8bfd5ce8f210489ce33391e4ba17556857d7a084bab9fc0add7a68e7cfec6942f3cdbd1099c5430ed0fec3239aacdc38ea609b220b92766	\\xdaadc565bcea053656fd90e9037931910e4e19fcdbf2523a701e8b44f26ed795d76584e677f01f608b6ad5458609b2a4212ebfe213bebcbb0940e6688f1d7fcf	\\x287369672d76616c200a2028727361200a2020287320233334343633363337444346394642364635314141423943433641383444343046393046363630343732333037314135303841303039343631444338464546444441363736443836414435333834383831373133433241384639393433343831423945303034424143444643314145304636374344304445364546373535393137353534394530353145423735383734383537303731324530393631323436314533423238463636463632414433394530333843383342443046434235334543463539304234303133453946453635454232354141413030343846394244313235464434303635454542363736363246414133333931314541323035353642464523290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x8c010749f2b3a96053d1e6e131cf477a70095b0db3868571f1675bcc9ea9920e693a42115dbd953a898a34e411c9c5544b1f2b33c1fa63a32945c9539ba5c80d	1570300342000000	8	5000000
4	\\x416d738377ad4f93d73f9ea038fba27e68ef4d229abb40c303c22fce21b31f6f4f994a3a7cc0d6eaf8ff5a70e4245bd4a265bffc69245a72d3a641a88044369e	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320234242444446383737444145333131413139413431433345363638414639353244363630463742313631433846384431363434304638314433424346324235384646364639313942314337333039353746353239444637324339433331324343464133373934363533393936313031383945324243374145424545354331423438383834444546373330333932434543304437314536304536424532413443454432303437323534423439383632323345313639464243313934384542383930423632443344413739414443434630414534354244423432414639314537364638304531423332303644394342373646324136443946303133333437323337364323290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x769b8640790944f229de1a3630518140380d54ba446951f44dfe6c2fac19ba4c70f428bd01a567115d9966909c8bdd1c9ebe7aadb96e7290c220a89b23e95802	1570300342000000	0	11000000
5	\\x859d192e87fee2575b8069b66dde1051cad343ce0a3a8b1a39ae56da015d70d19ac7d499b4d85825f69b3fed253c5953415e4dad447418c886ff264c1449b9e7	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233832343935433834383130394334414545353631464641393932423434384431304532423442323334384446414244453936413834374630433945453335303938384236463834433335444139413638363033424238413635443945454634464543343443303633353444384241413436464133303735344530433733313933373332303435434545443930313333363034304546384436303337344334304345383636424441424638434242353136324230353732434235413644453145464136383335423439353336363038364332314336304241393132393242314446393737373533333537444334414134423643313843364344333537464634304323290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x65f7e58b1742baa53b87227c7d772ebf4d45ccad28211666a03e7c1a60688a657905d91a10c1009d0928be5b78a417152bc4b117a338a394b1a039e5baac2907	1570300342000000	0	11000000
6	\\x92547df647f968a9233efafd112e1330e1d120bb4cf0c16b79f640cc4f2dd82e01eefe9f6f0e57beed7fd2b48621753e6a0a396aacd999dc728e032a6104aac3	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a202028732023443936433432463937304332424539364137413635433333344235334232414638374443453634433930333935364436464241363237413934393342354130304332304131423032384343424530414337463431443132303841373444363032363437443833423242434232324233443738424536363035444645433744453131463137424133353536354544304237363239363232363934343741303731303433464232434436383943453746434233363543444442353837343337324136353130384438464441393341303039443841324634423030423330433136314437424143373135344138314635334246384246314431363134303541463723290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x87224fbe6fcf3c7a1a9f191c3ba740487dc04266729ea192335d3ce7df281956d1153a174d6596248e1510f945c941e50571cb9dd6f1287a3745c66d9529f102	1570300342000000	0	11000000
7	\\x6fc799242c711a316886f12d23836b392d60f4b8d537bbdf2cf4520fbda16c1674b14b577f9039590d6ec1970ff9fe121bea519982986d79aa4a94dad8119c84	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233734313543413042363541303832324243443944314335463036384239344642333537313433434334313531313232443044394442384631363533303938333341463746333430354446343436393441353545334343384446393337323441463731323639383636343934433132333645434230314245443941333039423836444235464233464230393131324646334232364341433032343638314237463932413435384632323934433436424430384534414543374539323533413131344146443741353233353930453143433934304137313045344543394536364232444444334638393030323131414632434643393930324437433139414444324323290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x056561b7003d2853f7ccbff87428c2235e3abc83cacba205899c9039c5dc113df6d25016eceeb24abe7237dffe40743599422e802ac738b82ee4a09aa4e55d05	1570300342000000	0	11000000
8	\\xb3fdeac1219344c2174ad7078f380c0c0674e0f54c3b0318ca032a2517608010f79fe847f58fdfa4c40162e8939b6754f7e329cca408860d6c2b83a2089cbcf8	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x287369672d76616c200a2028727361200a2020287320233144384432463830333734344543463036363434383137464537454345463234363033413030353542433541443533463037354542374137353742374333304643383144323846363243423439304239354144373333344432413536383736384441443132464633323842433434353334414144464537344246324131313633443739463046434132443445313837443832373931304443383844393630423137384632313439443937333238363932343144303337334545343942383946414138423443433744453141354237373637373036333041424436314637344137454436383243464444373831343231423741423046304138413530444437364223290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\xc9f3edd77fbda800f9fdc99520d41cf792cb858892aaef642aab94bf2935c9ac88752bf4daf090ab347bb94f134ca8889effd4f10835546695971f2ee64adc02	1570300342000000	0	2000000
9	\\xaeec27e83fa36870868a1d0036fb9eca9581002205d7b2d1247c9f9d210d353761d5acbbfe34d688d7107725bbb0f24bc1513d023269830ad9e2cea60d7e6547	\\xbe93666484fde217ee173a5251f2f3ce217a9447870fb0bfe89a43c0e77bb70a585b64278a6f2c2f8acfd8632e6ab899f323147ada41d98b342dd1a1c4fd33a7	\\x287369672d76616c200a2028727361200a2020287320233334384331454630343532433143373141343243384330323031443838313043424437304236344539464338383333334432343144453746303243433139324645444338424633364644363439304138454331454232423333333838303041433830343030394343333734323143464441423838424241373342463841303437343142423338323845463835363535303737343542373543414642333743454644434539343341363641304332303536433938453132393643353932313933333741303542394645333445354233324146353139433533333235424642433136444645353737383236454445373933304242433235394444334541454243363123290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x9219579e6e2b1efd545451f33e3d9ffc0fe7485e162a2a29378094c5fcc9b0f428c4e258c1f89386764a95de3135a64c5dea89f4e72e1ea82d7b9ee72d422a00	1570300342000000	0	2000000
10	\\x6597893e558e76c601fbdc9b40e56b592a6623ddec8c741dcd61f6aca9f3ed8db6f8dae3377f20bf6589596a81f086dc9761207be4edd0c8754ae301a46425c7	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233930343631424344354435384133373541333443313034333342394444464144433545374338433139444333414645393541443442364235304439423135433442314141463039433542463045334642354643363843343042454338353036423043464434333645393246454645464539453441384334343845443843433045463841434439383134324632314238324136423238434630374231453730433435334236343230364644313035344339454542344236343841434232363343434634413730454633324338433635394538333135444432313242324131363944453138314536303133454433343033353836354646383031414644373039414523290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\x46a9a818378101fe55b10aee2c56f256e9325615a0206f2c65709a22d6c7c1d56b3dd400ed1fe0eee1fec6a2e0a8d0e0964b512febe25978c2e1fad999378700	1570300342000000	0	11000000
11	\\xe09aefbf8e8a65ddc645af8e0d3c8e019de9062c137c681058c3ff3d113ed356f1a6a98e0a1c4774553b6e2cf3fdb2c353749e83f2f0503a7aba507d261128f2	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233345423446363943363138343436424432334137353134313035433932384646393438364344304443444442333036323042394144353634434439333341323834454539454137424630373944434536434233433138374345413741384231413331344535324542323730324333333741334334323635354537393046323633393738433635353939443439413236394142343431443945343430393038423032454137414337353639394139373443363731433946333433383043463944353032303046443043343133343030394546373435384541344539383035373343443036324341314645323742463944383030423533464245394537423438324623290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\xd8c78779f6475aa422cf19135cd8724e9e32f0ded2caa46e0c0b4bba8d9ea0a1a370b6f77b5b3fe7d06dea59cbb49ee2bdf63c5e083c658fea89d608106cc409	1570300342000000	0	11000000
12	\\xd21bb8f91ff62f076bfb64e5b01ee53ed1f78c44d728512ee0cf4401dbaef208fe8c29c7b8f4d61d02788e553f13834acd7adb9f4cef9405608008009fc574d6	\\xa71f92b46f67c4b5cd8ec9f666abff53b81433138cbe2dfa750c1763591bd5db260afbf194b183098dc5613f33efffeb616080937ee373f835c62775a7fa19f7	\\x287369672d76616c200a2028727361200a2020287320233834444646303337423334323644393937324130373338393837443330323334313637314234433341463044434531434238303635453030364343444343413643414436353844324344353331374431353436354144324145314143383735364136373532383145424336363233394232424338464438354242423638344642433643444541324641413335414132353135334539373637304330413641443341433230464345443232433339353944334534344343304234383838333534383446333946324437364345354443454146324238324231333034353542424237463644414542323144393030303933304446423841353639354239314439353423290a2020290a20290a	\\x8ee1ca96d24a4d1ae9d6d3fb5eed232d3b0cc8eb908a8908c51eb2c5f12fac9b	\\xdedbeb2d27e611e415413ac025911fc95c0dd323ae90ec51be8c158f9a8a2deba1473eab0ff3fc9b2c5a2549f23e4b0adbe7af5464fa96e0524f2bf51cfe5a05	1570300342000000	0	11000000
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

