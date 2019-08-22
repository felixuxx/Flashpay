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

--
-- Name: kyc_events; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.kyc_events (
    merchant_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    "timestamp" bigint NOT NULL
);


ALTER TABLE public.kyc_events OWNER TO grothoff;

--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.kyc_events_merchant_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.kyc_events_merchant_serial_id_seq OWNER TO grothoff;

--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.kyc_events_merchant_serial_id_seq OWNED BY public.kyc_events.merchant_serial_id;


--
-- Name: kyc_merchants; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.kyc_merchants (
    merchant_serial_id bigint NOT NULL,
    kyc_checked boolean DEFAULT false NOT NULL,
    payto_url character varying NOT NULL,
    general_id character varying NOT NULL
);


ALTER TABLE public.kyc_merchants OWNER TO grothoff;

--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: grothoff
--

CREATE SEQUENCE public.kyc_merchants_merchant_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.kyc_merchants_merchant_serial_id_seq OWNER TO grothoff;

--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: grothoff
--

ALTER SEQUENCE public.kyc_merchants_merchant_serial_id_seq OWNED BY public.kyc_merchants.merchant_serial_id;


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
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: grothoff
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_timestamp bigint NOT NULL,
    wire_in_off bytea,
    wire_out_off bytea
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
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


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
-- Name: kyc_events merchant_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_events ALTER COLUMN merchant_serial_id SET DEFAULT nextval('public.kyc_events_merchant_serial_id_seq'::regclass);


--
-- Name: kyc_merchants merchant_serial_id; Type: DEFAULT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants ALTER COLUMN merchant_serial_id SET DEFAULT nextval('public.kyc_merchants_merchant_serial_id_seq'::regclass);


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
\\x7707c3da2c64fac4e92e8f25a596fec874197dbcf35a60ac819970c779f03799603e3c48e3578e1a3bbd049437a76f38f1ab0997f51fdab1491864171f04c038	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x650df74a7251749a3f32b36e95292e78025d170d00bf79012aa7993b0dc2e762fa96f3b0c0b6de50ad4469cc87d69cd4a7604fb576cd21d766b8a2510cbae007	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8d614a07a55046789f3c78bef9da832e0223b4b149e89c98bee061b780c24d5618f1d89efcd31900578f24e714950c570f049823ddb48f9616dfecfcb3c3c88	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a5b81507defc65a176ce3dd3c9d4ebdab05331840c0dae4a485a0cbd30b7ed61797ada10ffdd67e383707ae4c829427eeb0387fd79ef1a3a45a62d033fe33cc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2945894b42cedcb6e2d343c912f92c5d946f6a2983e1a394e65527902e645a4e14e7d672bd9f590f4650d7017a9f9421c7843aa6832ea505f17f29da04475bcc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1d77ad4994a14321169c915d23acec6fb12e65a9409544a9fe630492911ab13bdf46111a177e4b1ad78b9615e20cf9541edc5133c068d038ad0f504fdb1f009f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9b5625cb82f327eea54c023f592e23aed15f022d841435757ad487e5bbd72600c60043b50697242293a641159b7aef1fa94e329338026faccdf4fb19ce581bf0	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd6d5b3c435301141c0004a5c2ac8364a5fb9ae581b667d2d51a699ba80a80245271ed4309a02e8eaea2933b53e675333f302537311b56c77830107c96243ccfc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x12a3ec67bf4b4904aeafc663985d8f9aa66fa66154e2786fe386b0f28cb6624f113e6f63f56507f3518b66ec6ce53533fcd54460dc5581d238d7cfea01636462	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x704997521bf980d86ae434f813e83262998db7635cf628a30651992428b0d030b2537f67a5d34fa550f4e48e2f1dcfeefbbbb83d258a26a664c115c87f632e42	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2978fb1db852a974068f9633a0156b70b03f119684aca5e40592d102a6ebfc0e96db1442446a019dc51924d044574585c7c701fb8d79a20341d8fa150758623e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6acc2f77b0f1e80c22c941bcad4ff71b57d304ab2ddb661266c3c37d3e776ae64e9446b77a276a99e46c2c05a70d7a18770c95e6fc04d65f26d65d9eac36d9dc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf09bf7aa4269ef65aa98bc666187b1645e5a54d4ae8af5c19b43dc4178380ed7e12de1abd8cc2b9436fc90cb07eeafdfdf53543a129c79e63f53e486b66126f7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5bad14844d1d0bb9bd06231b62d636defc955c73b03cea9e07ce066de77745f6924531db4f4b4b0db37d2a43d4a537ccb0df088a7b86af6b6fffdb5bfd841ca	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x02a042e4cee6ac6e6ccd85ae6e66fcd73eb2cb3e0a36251ebff43b63f3f6a00a113122c6475b92480215dada8c73139857fe9c9adb96a2cb90250510d0cb191e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf7133dba341ace9f536056ade4c08952de7c89f9fe89836382b9ee303c8b34d62f24054eb4fe1a457fc9bd6d1e3609befe42d0cc6cbd5122fa606d9acf82b237	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1c22503aa5c6f9485bba01b7a5441bcf6adaab7b38841d67c0d594c0d725fc0a48572ba96ef7648de845fbed3b5d119d378727d2aed7a5e3c9309de97e9c1e18	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5199a430acae083bd7a8bf2a46fbf1a8299cc322031fd71f07872f2b9e4e693b82b061c5ad50610e0f265010576427811728e0d3db2ba29634451a1dd8dea936	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d24904a4c0b6d389eabf25cb942fcc1926a4a76f9e2511482c75e78824ca67f1350460427a00e332bc36fe00a95df95be66b433a7dc1029605ac2b74b424b86	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x95299f4fdfee2b773e0cd511f9c97bdade811d82308a364fa5b8201c34f40cc660cd4a0902a1a3054bf303660a7be7027846b382c61a960d8db71ea772f0560a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc2265a6a9371b5a886bf5d9170e1d403eeba2b8e410e22a5c30f802870acb07310972fc217439ee9da1c043b0a7ffa9f14b4fe1551ae5ced55fc9accc2a41eb8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3a79da2b59611f395ed6dc1656cafac7a45a8e15fccab79c55cd9c7644791205246a29b4d0a359aac90b30a969e22693a7f2cdf65f917bd523602ff049268207	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x34cd3c988f58fbdf269fc9c5cff704136fc52c15f9ca80c9acf731974e54b3b905543b0f90498afbea8afbf3c7f8fb83d1cde0d81e407c9c2ba6dcd14d834d70	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e8b07b05d45524ec16d4a9f22d12bb3ec647c6edb74ab8d7e02f29487d2c876d329d3fce872c307c43164edf6272c7de9bc863968f6567ea729971deaab1403	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ad51be4073c1332c8f32761c55c4225c04eb834ebcc39c836198f2f220911ab46dd74813d00e1e9d006bdcea848cc22e4b0bd97f26aca9bebe733e0de29f732	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1ca0d89e869936f9a0749759f778e8c19d1ffcc74976a4abacea0b808e3a1b63d177c5a88ca061c9369834e98888bf66c996e0fa0d097f8f80700037a15c451f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x198e5ddbbee86c3ac4aa5dff90b7af7a62022000eb5ca93a8c0d7ce8d689c5d7132118e456d7fce53fa2c59a4ac992ed5a6b74c7cf44fd261b24dd393de33714	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14bd49f5daac420f97e237e47b4fc94dac780303d7e049eb460951c51a60e3f06a06887222a290bac2f1dd914d03db094c98c81e2d59be0ffe7fd6e69dae3dc8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaff2e787365e7799755312e774c7299feaa32a9c7ad2dc464136b05434bf0c8e0e1b2303e011c76a486f6ed314ac8026f230d46fb45a3528405cfd6eaa9e1b6a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x45abcc8451b934b7b789a44fcb5b4bfa52929b4d3ce0d5478b1b6629205eb95bbdfd50eceefcd290ab8107317fc0ed0d700cd7f131e049369772f1240fca68a6	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x453a7a01cd02cfb3a99215e2c13feb27ecad83099b5d62cf6c1189dec651a605cfd3e731721d67430bd221715bcefe425cc197d97f4a6593fcaac39683edfd55	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd19450d500ba3d0c7ec961deb0fe070192f63869f1802469c51eec6e1af42e3edcf3a2c73a6524f7117ed2c7904c794d1027ecc8b7f75702e71fec9217d694f5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x98aa65bef3967d0cacfd828ef4ea6e3a2e99a099699d67531bd1b10549f22e83530816f822ac8ede8d2c80dd38c8bc7b6d71c3d0c3fd210ee100b5e95ab5ebb3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xacf90474218ef9b9114aa85e8ef1df6d0c48362621ad90c581e59654e9482ab94f5a32821563ee80291a510750d967e14031f75b7a2b59ffd96441652e2abd61	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	8	0	0	0	0	0	0	0	0	0
\\x59077480182f134f6894fe05eb75b81519d2a48b1d84c0f451a43fdeed61b9470d7d3bf4e4be1a68717f35728af2616cfba3cc059150fb46766600220e19758b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	8	0	0	0	0	0	0	0	0	0
\\x027be1e880351549bb49243fadcb17512bb14ac29f18d203bfc08acddbdde7965e7c74dcaaade9088ff38d518c2d071975703dba6ac2918aa890ce4c42377421	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	8	0	0	0	0	0	0	0	0	0
\\xea916e4a98687f7db18cb77a313c0d2fa9573dc58ad0480bfb232d9883a7c02d64d2cc9c6131ebe2acc53e9e5c32f08916e220b747f3beaa0836a71ea66fed1c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	8	0	0	0	0	0	0	0	0	0
\\x346ec50684592a6b5af4dfc5479c496ad004b25c88be34d4b0507bfdadb104e01d8e5af209d9db35a1ac8681062eb106251c68276ea079f3d50dab9fa9a1bbd2	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	8	0	0	0	0	0	0	0	0	0
\\x08e24dabef5c1e920b82d251e59488dbcfae89f0763a1bccf89ea0b44e7969f577b3c7fe0d7b69dda05319183ad9d5600f5db9fc40b5c76011322794c0d4e412	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	8	0	0	0	0	0	0	0	0	0
\\xfa51f1daf9b0974228bcda449fb9790988088af769334c91cb4db3dbe66a9828f13480af97c9c97815fdf99786b8734f4526eebffccfaf85311e4be025d43e14	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	8	0	0	0	0	0	0	0	0	0
\\x92aa8053cf5ea73915e390636aeb4e7992ee827f39b5ffccca5145b57bda727e2b6f07a2dcb17cbea7b7e58e53100fabdda48c6eae38b83e53694514e9ae0fe7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	8	0	0	0	0	0	0	0	0	0
\\x10ea933365658bea495257cc011419e7a3aa9d105be95ae2edab82c39ecbe3e1a0194bca141bec9a38ad2eeebd64a8812a5c11cbc36f2b7336ee0829aa1c576e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	8	0	0	0	0	0	0	0	0	0
\\xafba65ff74da9d9d7211cd1c331d3a9bf0dbd318c016a9b20cf5e011af88ae2e893a4fdd2fa6181f47b0418de994ac33db17d110455120a5c32c8a5ba58d994c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	8	0	0	0	0	0	0	0	0	0
\\xc3583f57bc7fae948ef0df515b3fb2d00e9e1f38f619b5fd29bc308bac7fd5301e1d601a789623eff7784c9b4baf50867594fc661ff165dc6fb29734e43c73e4	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	8	0	0	0	0	0	0	0	0	0
\\xcfa6f45a8b57e9fa293ef31954d890fb5841c77e400f458eb942e1dd257ec93fe5e80af6ccda81957fcb626ac582242344486c3c2570581364f7afd098d9e42e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	8	0	0	0	0	0	0	0	0	0
\\xd9353c204992cdcc9a3e71aaa18352245eb705fe7bc27bcaa9b8fcdf38afb95024d64db0249a27f5de61a9585aa3431c0faba56350877259b2a4bce3dee1c9a9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	8	0	0	0	0	0	0	0	0	0
\\x9c797c42ed62aa44f015fb384b5332535dec0ececb19a628b015833ab78486f2edcb55a757033277e096b00545e1d61d36a9fe17d602e6540f41c775053a3cd3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	8	0	0	0	0	0	0	0	0	0
\\x41bdf2586818d8070635e9c7ed2c1f69ce673702ffd62e7fd246a255aaf7711f107d6431ca643e022767a2f7cd5de8b2a9aa4fc60203fdf33c52589a8e497757	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	8	0	0	0	0	0	0	0	0	0
\\x33fbb8e2207b499d4a0b34efc0aa1cea2b8e547473bea44b409969e136ccedee334a3875011400071203f90381858c7c7d24992fb3cb78faf3268ef85ada4f90	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	8	0	0	0	0	0	0	0	0	0
\\xed4c4c5158d8383165f1668296477b4788fcd32c2e5d529e90b7ac723d56955e1b18b7d471f59c31bd873241e3c408ed3655d98c9d95740d06feef3f40609d62	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	8	0	0	0	0	0	0	0	0	0
\\x6bf97d69c732aac7d050c1e7775bc41f74cad1d823764630285598858df6692c6dbd7ce7fd829140ba27d39a6dce9443c2697dca6ed7ce53346aa54ccc5eb4e9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	8	0	0	0	0	0	0	0	0	0
\\x835c0b69b4d5966846c049e571d90e81a0dad2d2bd15fbb89d820b86a8a48c2354adc4b4bcedaf5e2acbf9c6ab2d918f09a6527bfeecd0defe56b8baf3e99a08	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	8	0	0	0	0	0	0	0	0	0
\\x98381b89f2e1ecfb5c638129091711e1983168c7e5d0ce51b0540526703b726e53310545ddb6f0c565f74f9a535e726ac92c6eaeb123914d410ddfc47f46055e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	8	0	0	0	0	0	0	0	0	0
\\x82449b54c64f0e155c2e7bbff014cdc5ff37ef3d1bb46d2ed46ab0d230731e50d2f2660701a965a389b26c913831c067f897c701a45ae39cc50c7f912d7c658c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	8	0	0	0	0	0	0	0	0	0
\\x126d1e2a455671b11989801ef01925f7d6c91453ee8939ef7deb1b7fe3f7f4fd22d124c729c9de5d833f544b74ae79c8fc604f61a04bd8cd721e90c5117b22de	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	8	0	0	0	0	0	0	0	0	0
\\xd2769e82a61dde7d4e0b71ef5667fa5a0ed7e4cc1e4337003afb1b6c83a252c3dcc8b2e7cfce45c84b18b1261fb4852a9d92c01b60bd49c20037d02127d2e2a7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	8	0	0	0	0	0	0	0	0	0
\\xc2ee1269352d0ffba2c7e3d75bffebad90fb2091c1c70c96a4ad567c07383dde399ad02c39f551ae3c8ca39ab8b476258a119f2cd441fb9173aa0bf62c38cad8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	8	0	0	0	0	0	0	0	0	0
\\x4c6a9ff04cd3a56cce741862d081d76024922a457237e1ba06be6d1ac8c487c8e1e5f32caeba78f29f96240fa6b7c7b0a7bc0bf24aa24a0b50a1d966914ed090	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	8	0	0	0	0	0	0	0	0	0
\\xea664746135900a788b045002a87c6b4e9b5c35dbeec80ce1a45a8d6c67971c3d4da5b53622308596aab328da88acba5accd9d3c1d66272394e2207692eaefd6	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	8	0	0	0	0	0	0	0	0	0
\\x9b785e43630220b1ff2504e97091aa0b520bdf142659331af5a6b24a4e403dcad4ae0796bb9f8d25f63e2782a3192dee0f916be4003f191a1307a9afbabbab43	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	8	0	0	0	0	0	0	0	0	0
\\x2720fc8e65d46ff745e8bc6fbdad2ae0931f43eb2dca2d3678c461ba665262c4efd343926d011310450f6e5773811312a9e7dea1ef8eef947a55658a70376d49	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	8	0	0	0	0	0	0	0	0	0
\\xf7adb74a05b77e3a799fa648d06294239fd5cde43eb70153a08bf665a489de4a9a40976e5fa35404b8dacd0398d4448d96095bbd9d182456d46bdb03cd5ed2b2	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	8	0	0	0	0	0	0	0	0	0
\\x0fca8197106fb0e8bac35c31daf6c2609810490ae3583a07c17f6b981b659dc3fd19fc27099607df2464cc13dde008c554daf0955924a942e50b63c18337af2b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	8	0	0	0	0	0	0	0	0	0
\\xffc8eaffcdeef0b8ef198cd0314546b584a1add461d49e0395fd88606642b40cd19d28f5013b60e85ed3ca9f5eb1571f7471bac62b732d31609256c5755ac36d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	8	0	0	0	0	0	0	0	0	0
\\x8af75f5b1e947eab4dfe5e7618b9eb93ca7e723dfb6b36d1430b9cf71377dab55cb9ebc860bb83b8d1c922c974cfdc180593c2df369a747bbd8a27386169412b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	8	0	0	0	0	0	0	0	0	0
\\x50b4cd88b7f8ce2da610203fc8a817176f61f048e193c8098d6d6f2f12d1b4f132253677590d9e43d7c25f722e7be4b7ec0371b3548f0db12a929c64d7e56f9e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	8	0	0	0	0	0	0	0	0	0
\\xad6acfa4f2cefdfe64f0b5d0ed5cb88329d526b7356d4291c0f6be28b97239c29f00d3ce5aa25aad8d75f1193dff84abd85db26e8f048968c60ac77973e59c8a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdde353cd7954cc9e794addd2466acd9ab9e0f56471e853fb273549d069f4a8ab9169816f5ff3a7e8a611c0d32416620e4cf1d002235eecca39957ff46fa05fc9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f075f1b3d8d6aa98e30e034df751cdec27ddb44fe76495da4d2dc97c8be72357bab591b4d98312abd0441fe82a89a354ba0ff79f9da69b4fc7e4d11b43fba1b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe40dff1ce920106813fd1e2d1b9529d0aaee8c9dbae444ed41dcb786d9810d10f8e69cc7cd4b1c652b268b43ab063d5d932564dc89b1e2a09d2fd0093fc5b1bc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x37a91e8e9ce8da884a93e10cfce79eea2aa74ea91f7cbe8d0a68416fcc907f46f01f3d13dcf4b1d8c6b07d7663c07675c096e11a0e4c10c37f5cfefadd59e46f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0af24aa471e0bbb79571dd5146f908d9cb3b4cbcc0c9c51da717a1286aa9e855b7ff54d706e0112d1812ff5bee5ebb2a85c1b88fb156a20f1a691b29fccfdc25	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c714936f721a52c1ea1fa7fca5637ca481b69f7dbdea06530dde4eae93ff7c71daa7a2128e1886de78aff38f1a4ee4a0c33f8e92c866dbeb097ae1d7438e893	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x588b6f6cf189ef64d333f0bdb4148eaa4e7bbe4b87754ff240047b69c1cd4e7642ed6d6b01d4ec3068eb7e37ddf73f82b3345c95695f226934b1b70559da820f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x517ed28c6081c817dbf2e355454400f3a277f95bd5d670e61fc8f32ee27848138313ebadaf0899b6880072367d4c183d82dd4287866916b47249fe473c12dcd3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xeb0c93dd048f2a19c5127d6eb67ffa0cbd515a93c0fed770c99b10d8c8a9d8e3c868cc0146782fc90b93f34a0a0b5c827116118f9836ab01d8bf330e58d17038	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc4a88a94facc90e41140868c87c82afcd7d5aecaa6ab0ecd3efcb3c4152fb9e70b724e393b1ee1791835c33ed85895a31937a6b8f597b6b2d17f90030d61047c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0ab52c0385ea106032e6af05e5cb4b726be394df2c2bd8fcb5163c3db133b1d85a82fb8f0c89b9c129e95afc8aea4853d5090372d2277b8555f8a8d6dddeab9b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x12c5c59fce1d0dc343d6f4ffb2389ed718a4417655a18f08d8bbd9f6c3077372958e9cb335e54d4bdd86ff8f6675cb5ea42eaf7c47db9d5a5d63ed3000429ced	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f8557193080b0d49bfa9c0ff039dab3594ba98781d1dfbbcf3cd913ae1e925d6d55f7cafe97a9458d46faa43b327f1d831850325f895f836f3043435ba60a2c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaf4c1e865d87f45084d76af4abab0fe51566ffe12a7081263166671a80818971b9fca20da9ea0f0c394590ba5c5b008b984e9d5afc751f7f7ac3b783b4de6654	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8887cef1e5413c360a4db486222531093eb7bd100d37fe36c80f15aaabeb9018c4b46244aad1b95927dc707d2e3527f426c58a684574083e6daaa5e5802ce47	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6b9eed78041d2e249e48923a813774c081b9e5e7cbdc832aa45901bc4f77c46e57a3ec286c3ac83dc4b131a497cfe3240e3e64397aa12a4b3fe74e9122b95b1a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x65469b5bd438657db63faccfe76e25d33b0bf327c2e123c0d27761afe65014fbc646fe6a6e694f1378a3ec815ee5ff8a0b5eee3362607e7c41e53f528435ff42	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9a26248cd5bdbb7db51d18d00d450081e1cf9efe88dc239f2278965d851cfa191f2b175a5b6af459b5431e9bfb94a87044ccd2f6261a1bca6a7884ed4774aec4	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4434828d431469295997a47b4d426204c0087809d93ca19999bf38a5b849a8124728705f45053cb90074dd99dcaf4c0e263c6ffc65648cf4428cd28a99601374	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb2764b73182d67d046585d9ef5428b315d956b8a0f0c9b4e47869d4d0cdb2cad6126374494e6fad7677ea3d094a1abdbf6b6c544bc71d11b3a0bb7d6261c1a0e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x6522cf97d96d26e17c42e439882a769f82d0a6244fdd73ec86057b6eb48d2ea8d599febc2e1e6099f1d4574a6b70eec9ae71788780eecb5b7d8eba05aff65675	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2f76b2107d1bc80cca87f0ac17caf26d10fab2b5a966c0f2c24f86312b616049878a4973d6108d0bfc79e9e32ee10de1895c87ec25534f92384781adb5da380	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe4cc96f3fcb173e5cab91c083c6974d81129b7f536c0ec7d468746fe9af026e523c92c4c88c2125ab56654657942e4283ca7739d51f4d34559704fd9a6797a15	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x538c0dda1ca36b1ae2147ad913041dae7654af241cc42eb43f7523b7f27ac8d52363259bca96bce6213c7af94d1c78e4be54b0024c82c4f1c6d3eda3392ee2f4	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xdcec278ac920b49a32d5f6723253a2b261da9c277eea78563816b69bf0efc16c09fea99ba86cca02141274f6827014cc0a9471be6f2fb9b4661cd12806a3a845	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3f7be2f275566e78979339a181ea7c70a6b1135356916948e08fc843de604dd725a343d771b5d35c0607cdd597acb1e0352b363da54a7fa8303c8b3e6f96ae95	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xda94110163ba4ea14eea85ecf0f13176d56522cbb47fcfa25f94b94221912efb1f8466a94187c17544f7c287c80f598520174a3e23650d73e0c16d87ed3207b0	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a3b9aedf145a502ddce9ce881e772d85384461460a7ce65ae84dda43d2c6ba8750b3b5f196e36275eb94ebdfc572000b9cab950de9c2677a3262c3190ef5fc7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb2b8b00853e3652962b857a61b2aaec7299b7532c8802254647df850a220ed6521187c0b03eb1a3b6cfad498d46795cbf207c5c42269ec6dc34a860b33c2201	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbe406964992f456361507b9c8531ae3f954c4a71185d95920452c03c5a2e3b6f09cd113c69efa5624b3ded6a9c50903feec3e51d6643c5c6e7788cf1fc64bb78	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7a95253b55557470626709e588c0a36eb751e489d104f8d808031d6304254a3270d1a3523a0cf656d33cc70f13eae411458a6483c008fbeb081e36030fe20cf4	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd932bf406d8bb55764e90a2b4f750e5002392e1399a7cce8cfbf64875a50fee782fe1c3e04c4e2baf98dbc77641594d398a03904289e64624684a3f56c053570	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb6eee945719bf92c3e082efda32aa41d218e2f855488f4d976d0ec48dc1ffeb69c1dc5e60afd6eefdb9d4a95c07bbb29b8836ddbbf20bf603ef5f6d52132a826	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	4	0	0	0	0	0	0	0	0	0
\\x23190d54c5e1a0b09863bb792869dcea0c3a516b4e7d9730b991e1c80971c31c96cef2549200cd8309b20c19e2cd7d9aa0a48b6d8dfac72a98a49dcdc3419bb2	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	4	0	0	0	0	0	0	0	0	0
\\x91ecfc6cce18958d083e51843c0244f19777fb128bea7cc480a16da89ff11ea3eb44a81233ef63da00dffab3b5eb07efbe7bee9275d905c2896f9a4afb21f86f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	4	0	0	0	0	0	0	0	0	0
\\x573d9bb0d35f4415485137a409f0fb957f19c969b7bfe58bcef654ad424ed49d91c686a78f2b5b9ec4622262262ec87f90c65cc7e646144fb84f69bdb2e8be4f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	4	0	0	0	0	0	0	0	0	0
\\x623f19b7f3557aa179d3af7acb6054a9e4fe6dda8a347ae0ba8a9255067f873a8ac414284bc9c390af528e46aa48115ef9599494ccff84f6ff52be9c4c870bd3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	4	0	0	0	0	0	0	0	0	0
\\x866213e33ff04f0be6926cb114d5d082ef5d81df92a9e87e2284b98060e2081eeae17aecbb6e40580330e59ebe3dfeaf6fe47142f9e5c7c3f50510946cf0b61b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	4	0	0	0	0	0	0	0	0	0
\\xefbec982189d1d8fe030acd8f214a8fa9aebb98ed11a77368146e585251be8dd067fb67a2ba399cb235092081f3250de91588181febeea9cc6ff8ddff4c3232a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	4	0	0	0	0	0	0	0	0	0
\\x6c2b74030279562592efe501418728730b5e5c0d0968593a51483e2b318d47c76a681916f8d2e9138e3d68e4e3ecd52fd18f398b5067dd0ed520423e41e9580d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	4	0	0	0	0	0	0	0	0	0
\\x7228920073f729dc8ae88abfcb9da1d45a7535a775725ec2ee60abb5a2275919e67d1ac106f0258ca72717272b6fa3609d3faa7e854e991e777a64cde8415390	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	4	0	0	0	0	0	0	0	0	0
\\xf2870753101f40adeb55d675712df0fd16540c20f73243034b004c82b5504aa17eb959363fcd1cf2ecf94d824ca7a89729f2bd681d21ff700d2dfb880b9cc335	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	4	0	0	0	0	0	0	0	0	0
\\x107ffe803d7d8296de60f8957e0bd7b8c8aec3e3e3694c08f71c27d4c44b35f8b0db023e55b5b2df9fed298ee91521f10c6e230c2b683a27140af18a929df2b7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	4	0	0	0	0	0	0	0	0	0
\\xb68f03d605e5b821b2501c5020d5b95b558bac8cb9cda33d0771632154a2c41e41981dfaf3cfe8d53062e6abd39912186a797c1d8ee52762a7f69321db34619d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	4	0	0	0	0	0	0	0	0	0
\\xb6405cfc0598074a7d4b9fce335cefeb3d97541e9e7d8b30d10a2e980ae939d1d2a655a078ba2be3516bd9fcce873a4db41a8d81144b49314d421d5d9e5e4c50	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	4	0	0	0	0	0	0	0	0	0
\\x4854c5fe7fd595877b60cde5c1b3cb5bcf62387ac01262a1945743a7697d691375831260493e561f554e8b3de646c34a8397b8117fc3f68db60b5b742f422915	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	4	0	0	0	0	0	0	0	0	0
\\xbe6e034a9625522c10dc4aadbf0912ae0d8fff5f09f88407b0eae45b5543ea40251a4a81a79a3335173b3b12e6a2b52f2d0151bfb985e474d5faced8cd95055b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	4	0	0	0	0	0	0	0	0	0
\\xc63913194bd18bdfc9272dd225dea9647c9162caafd1f3ffce90abb77f8d233f75b3187e0bd8abed08ed0ef575ba3850b7f87ab2aa969e272d3e19a47bb19466	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	4	0	0	0	0	0	0	0	0	0
\\x26386a3557a333cb645f60830bff72951e49cedc49d5e1d4dff5f20f17df3da8bf9146189857b2e84cf0fb27289f3a13b0608bbe64b7430b012c8ef97ca6c795	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	4	0	0	0	0	0	0	0	0	0
\\xb8cc953663f51b12ee0ab402530294f46cac80de5185dc9d8a4c3fb8d480cab75387c6abf5e37a79bd9c1f33e8d230ca468c3cc2401335fb3ab76c37821980ed	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	4	0	0	0	0	0	0	0	0	0
\\x6d015e1d4922861b768f7f13337805f621a4ce0691365b8298e8cfbad2c405e1868a692381bbcce9e9bc26c230df4f66a716b6bce9259a0cf107831e012e6b89	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	4	0	0	0	0	0	0	0	0	0
\\x2a11b83bce456d595d51aa69ca34ff4eb1f607f027c265cce20b15c24bf24827502cb890a8032d8fb6d7f79055d3dac739c4dcd5b4c8a16625f6c2f46065f893	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	4	0	0	0	0	0	0	0	0	0
\\xdda4fc65f28f338472ddf16e7052346968077f409c996f77e09aca7891a54c0589594456ba818ede1928900ab226d849b22372e491d333a2734b7bf75601e6f1	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	4	0	0	0	0	0	0	0	0	0
\\x1b301e21790ca76f2c75c863eb05f8ba7b602bc4bee9f0a2968eb3682b15d8893f6d225decd216b8320f1017a7d47002b98fc0c4661e489b9b5089d2851dc3e1	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	4	0	0	0	0	0	0	0	0	0
\\xf9fce8f7f1056123b522f1a0e2cde305e4d7eb61297297476627e05fa5dfbc911813d98704672cd259c5f41496faa58b6bffae86bebf976b5110f709027951c5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	4	0	0	0	0	0	0	0	0	0
\\xe05b8d1934eb783dbac9cb605aaa7976e944d223c46f6f2a4bd06b2e5c9bf62a0223aff35cbce729d99316080c9bb59c153f4ce7c0881795460046eae992483e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	4	0	0	0	0	0	0	0	0	0
\\x2cb932d6391b858b01c02113e0d4a8301be0782e259f751205cc2e1a44519f03fb844726d63efd45754f8307b6720321e7ed49c05b08d5d09c532fc3feb001cb	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	4	0	0	0	0	0	0	0	0	0
\\xdc6d8f290e0939cbbd2df2f94aa96ab7b786bdf27b89918645a4a66fc4995940db3185d2e2da40eedb4a923cc85b9f602e1d0fc249f47e718397d86ace020925	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	4	0	0	0	0	0	0	0	0	0
\\x2c7c3cd60d1bc5597213752950d91e6a8887bc834cfdbd46445a8b7084c5acd25b1574da8d8a677bd7e9e401ffd4fa918d7e1359cd5103729595d162e19fa86f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	4	0	0	0	0	0	0	0	0	0
\\xaf20639c0e099fa160ec4d62cf8359a9ed24a3b6a634fe5566f9c989d0358e0e8b6875013083da305e510351a00a2e9b4a5b6adc17b6318b69d8689aae3c0104	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	4	0	0	0	0	0	0	0	0	0
\\xded2b63f990384be67bb39170813b0c92bf1dbc0fe7be7ed1b91a793bd9431cf4c38ad09c3061a099da7834464c49c444f652e7fbdfc065cb2289ec2bfca5fa3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	4	0	0	0	0	0	0	0	0	0
\\x67d6258aee8998f140e74b8ca1c7eada342f5a7372a4041f55e5c4e54c0424a4ec1cfdf6f3bb894c0b8e1265185189525ddb407a6eed5850fc3d1d074d302932	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	4	0	0	0	0	0	0	0	0	0
\\xe210f57b77da95b9ceec9fe7bc5c10df3d5902caccadec93ea5216de706ef268398e27a3344f333e0e3499eb24ed618557776f33069a955302a82c429ed6776d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	4	0	0	0	0	0	0	0	0	0
\\xe4657931838841b82c57770e1caacd0660dee900d06623a419af94af00767707cd3158d19c597f345b6e3f1c30b8b7f3607371e5998bc61b39b09d9014843ddf	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	4	0	0	0	0	0	0	0	0	0
\\xf1b5162b2927dd12b8e09479517834de3e51bafe3af61e668e0d5a853c2ed82e17e5fb1540bb6a8cfc55510dfd7128e48714ed34397c7978a3a9cba1b0701e86	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	4	0	0	0	0	0	0	0	0	0
\\x32f04fe33aab830e5fca30c948bc820e3137142b5e35c29a43a5f100b30167891e435bcd5b9d83815417d3710c1cac2d2f494827b0ab0044b8c4d397986f75f5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	2	0	0	0	0	0	0	0	0	0
\\xcdc31ec50360d683ed3f15ed5a2084fc280033713592c732520178c34c8202e1661ebe32db137f5fa5f8e61a2438e0bfbd3f2013da6e35efa3a061b80dd21977	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	2	0	0	0	0	0	0	0	0	0
\\xbac3fac5f6d7c73fbfdef7b5f814045f061a49e38fe27c295405f3b9948524839f8f16092be31e464b7a98d173cdad4cc4cae852f9b5c1fcbc14c08db64117b8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	2	0	0	0	0	0	0	0	0	0
\\x089901668378bfc4b9cb775f080c9bc5a1674bc1da297bd8a9dc3548ef0dd4d81e4770efc57246a0bda00fb89729f7fa1e90abb13008a3a01eb8d3ebc8dbf32e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	2	0	0	0	0	0	0	0	0	0
\\xb3426e6a092444b204b0904411b9292d953d210ad4ef917e08038066aaa2bcb7d74cb24751c73d02b74dd643b9aed7aca308234198fcb91471c3a123f104a5cb	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	2	0	0	0	0	0	0	0	0	0
\\xee83083dfc76d524f6f27a408bebf232e6d8e66876d02dc6f9a81998e0367a815ce5b6f3f41baee08197b0be7782a5c4e36018a7b2521f4f3a0630048bd7653b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	2	0	0	0	0	0	0	0	0	0
\\x207338ad317baa21ce8a30fbeefa4c44ea91209d450989193f7cb7e97b5b1c9cf8d818715830e95e79bd67b1fedd926a19a03904b234ebd00e4f4a044f54e811	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	2	0	0	0	0	0	0	0	0	0
\\x50277fe962e151697d931210a33b63bd2f56c86e9dca966525b200b18d472c151ed35f4880395e5fd2916e52d82c78874e638348a0da6d0fb21a9b0472a20b86	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	2	0	0	0	0	0	0	0	0	0
\\x266ed08f39a51fa14ec4bdcd255121f4c4c1d871fc9755aefdd4a52df806e39cc19476693ae097cccec5efb846a32772202f7ed7e7066e6db826d8e786ecae10	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	2	0	0	0	0	0	0	0	0	0
\\xc31bdf7388336ded943dad7d05be75b0f535d2ac0c70807ab9b68274de68e80b32f91e5c624a539278e226bc30bbbae35ea77f2e77d3df0973532812fbd1bc56	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	2	0	0	0	0	0	0	0	0	0
\\xca9c1b88a69a9d75959c512075eb621c823d539362b77d039a3d6fa8f9d1606dcc89ee778e1c7d1d60faf2621d3632f70f52f529438dce9c7a48022d6628dc3f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	2	0	0	0	0	0	0	0	0	0
\\xac3b39ee245e7db0780f856be4abab80719be3eb018e87de7b8f0f93ae1ec019745da9f91fd9a8ee8ac4e839ba2af5a5d6695b8a9145272349dbbbb926b6b3d7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	2	0	0	0	0	0	0	0	0	0
\\x9a4bcfcabe05bae8b2919df1806099ebe6f0a7a8cdee1795af1932909c9431c08108f732d81e050686716ed61b76314d35356e0946b1eb8589700b5a9dd3b9c4	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	2	0	0	0	0	0	0	0	0	0
\\x8d19df97df9d97493452b3608c4d266fb28f2193e7e388a19e36a891744137d5e2c62dc07657798677ec45426aa25d4d84d8123da732855b95cdfc1d5a4bef39	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	2	0	0	0	0	0	0	0	0	0
\\x8406cc5257770350a6c534a93ad05452a94d6de3980c06ad93683fa5768bb3bd25fe52acfd4330f9ba7ed188f4db350fee865056d97d9d45b0994dc03037cc78	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	2	0	0	0	0	0	0	0	0	0
\\x02dc4848eddf6bfb30535c4313537ac6511f704f96ed4810d8376894630264f37011c65a4ce4eef3ee2ee0159e1adb6cd0c8c46b0cd724fdc27bd909db4c982a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	2	0	0	0	0	0	0	0	0	0
\\x74ea13c9c6c871ef6a0d03e178a717241b173a223ad8dbe8740e131281265ceaaf543714841a9e627b6b42bb28e571bee1ebca21f8e306da3f54b6d8fb842d83	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	2	0	0	0	0	0	0	0	0	0
\\xfd672fcec13acfeb44442393bb73897858e1c20daa86fa40bd1aa15ec8fe1520405363a03cd9fe2aa8944a341d7356b29d20a4d23630d2af1a368ad018ef52ca	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	2	0	0	0	0	0	0	0	0	0
\\x0366742da49d9de497378afa399b8699c37a227619b74c1ac058e88235752ce58c8efe6bccfe96d73e34f6ee9b30b24d821f23f177610a4b9f3d158a1549193a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	2	0	0	0	0	0	0	0	0	0
\\x0f26b5f3f7f3c8d4a69bbeb3b6784ab7d94fd42e9bfbee25ba849e582bc69bda5e7efbea1b93a0a4d1ecca4783d6fbe8ba30df034ff6dcbac596853824bcfc0a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	2	0	0	0	0	0	0	0	0	0
\\xa253843941059134cc67a2b8232c7723827619d26cd02a76245dfdd662fb502d4b6a889efb90b2459c81edc050a1b8e064c966a038776f1b7a2593d4e4520622	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	2	0	0	0	0	0	0	0	0	0
\\x8a9d86f2f7af487e6552f9f2b8e6815986259005fdbfdd7a46673ec28e40b06577bc4338c99c8d4188294b6d13b6c431f53d02f7ca13656ded3e1b0379cd0161	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	2	0	0	0	0	0	0	0	0	0
\\x7023a1d5f3f9ecd5713da64cfb3675cc4acdd499ca967a7bb31249355e67a1078d00a0865316d0671080c6e1db3301799be1513301601af585277c629cb02a50	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	2	0	0	0	0	0	0	0	0	0
\\x202255570608c22c3c4cd40e41fb121b0c5a9020f2fe405b06208c96f49e86d82d7256c9d7b0592c6786c0ac9048b73606edc00820a58e2261d3ce8b01979772	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	2	0	0	0	0	0	0	0	0	0
\\x0f44751392a04d90301c42f2029aa86983183e21eb68739a28d76c89243df87b0d21973692de30c30d53001544996468ed14918b6fc95d1b145e97c5bece3ff9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	2	0	0	0	0	0	0	0	0	0
\\xb5297de4d79926ba6a2a60a08335159e06708c8df8ea1451fd80eafebd74a88e01d13f1135840a6ac4b8ca6af17d14a9448d506014583beead22e25d098e86fe	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	2	0	0	0	0	0	0	0	0	0
\\xa5da27c20991842102b57ee58e724719707461dbde854a40c07321c307c14fe80f4e6c32eaa7ef116b8e13c6fc3a5ddad6a449e5873df66335647f0f2b0829ff	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	2	0	0	0	0	0	0	0	0	0
\\x578d9f49bff04e697013201991b72d667b003598560927460a18cdd0118d8bd9860a806cbd77a3eff2251a761cf1dda2caf128a5ce915dc295999ce99ababdc5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	2	0	0	0	0	0	0	0	0	0
\\x81728555466ca91140d5cc54d9fc1c3464ee10770d794d39cebeb4b8d5877a2a847f77c746215431f13203109a975f723520b16d609af856f5866eb4ccf75587	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	2	0	0	0	0	0	0	0	0	0
\\xf97c0a4143e6828fb37c1beb2239e445297006e4d3b46c6e871cbe460ffc52eee84ba8b2ca26ec576b31f643289a662b935270b1d59d0a0b088c13512948171b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	2	0	0	0	0	0	0	0	0	0
\\xf9f497182420809f8267e6a683cdb1cd06e96700e511c7d0446d696827e7f482f2e8e8e26cc336a1f54a1bc6f729107d45b65579b2a6abf23529908479d095fb	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	2	0	0	0	0	0	0	0	0	0
\\x125eff10a5a34e82c77b09133419707795ad923525accb29eacdf74e3b8e2921b6247658e51163bb6997143e9ce6b75e28c4302dd76d9f21d4a9144ec5da7c60	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	2	0	0	0	0	0	0	0	0	0
\\x4b009c1c37483e170281ace1cf540ca12c6e4fcf6fe187062c1a422bf7a6797086dfb825f729594682d51a8b00110bb23d25ab60e0496e1118ae37e370e92ae5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	2	0	0	0	0	0	0	0	0	0
\\x36a6d862f41c8a84e8f9964bbd05476b0170b76f9aea4f284a71c1377ffa4a70f59c5dc23c612cff323eaf0371f65692cd94fa90e57a2c312d0217ec2b0f2838	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	1	0	0	0	0	0	0	0	0	0
\\x65d6f5fefc621fc9feed381eee764f30cce31b3e5a644dd0bb5cbbb2104764d67cd80f7fefcad3b1d1ad39a43afe4d3c51573f5e4ae8eb7c975dd071c4fb2dbe	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	1	0	0	0	0	0	0	0	0	0
\\x3b0ff1f9c9da0cbc0505563bb32d90bfcc9535988922b4b46172479270b93373ae2674b3dceb4a91d57cfb1c90ab93e2d78b36e8f79128d2c498731659fd8932	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	1	0	0	0	0	0	0	0	0	0
\\x1706a5526366a6c0f68323cbe8f31a4ef23c7d4dffb5cbdfb1fac61a14aab5761f48aded11a89b8ca522f13be2065b7c6d443b585628f605d6e23a8ce5e2ebb2	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	1	0	0	0	0	0	0	0	0	0
\\xb00a85a2bbf304bcee8307625c10eaefdd4fb9e7840820fce73583f580f8c3ab420662a4dc6d410763e582c5935f25ea4af5dcc5ac7d199344ade946107f451a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	1	0	0	0	0	0	0	0	0	0
\\xe40b4bbf5ad00484b2760942e00d163b92debf0e79e37690c18347472c09480fbd5640ad4f4f953d6d85e5a12b2d35873bd11ba3eae4b33c2b4734d72107f2d6	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	1	0	0	0	0	0	0	0	0	0
\\x15d2e7cb910996fef8a0997aefa802ed72715ee9221acdd026795a14ffa2d9dc7c1fce909f5bd43f03ab3fea77a76dc41d3300596cbb6684bf0c3781297fe5fc	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	1	0	0	0	0	0	0	0	0	0
\\x887dec4e39f4b58bbda1a563719b823e76c21d22cbb0d9222dd947c0554c5976b7628b3762e55beda7ec620a95d16b3f0d7166bad20a4e951e792dfc403019c1	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	1	0	0	0	0	0	0	0	0	0
\\x609136f6035a725e6162baa76b73dbf43d4255281ef98420bfca9c6e0dd7dc88f8fc8a6afb64ba4eb04450cf3c1aec847547cea5840c3042162c8836821f767f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	1	0	0	0	0	0	0	0	0	0
\\xc97f2b7fca62436f930b05fead8a354d69289cc74d6141372aac10c1754a198a3314cc52556bc7494d08ddf21e9cce1688ac4230531e6d1b9a3b738578e174f6	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	1	0	0	0	0	0	0	0	0	0
\\x50dee66fc2e2aa60edc373cbd08f5f9008d8929aeeeb18c9b53137ff708a6b675cb38ea2db61381b3d24879ad674bee837e9b2f2d990a91398b039dda24d8b5c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	1	0	0	0	0	0	0	0	0	0
\\x99596e9ca7d1849ee26ad7824ff911f016216a8ec2fd7cbbe249a2c366ad6de8ae158eb4a0e349eeb73a19e665e4f9d3dd589f50487a7db80c5348b731061883	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	1	0	0	0	0	0	0	0	0	0
\\x415a291e894adbb39db01e1347275ed0790ace17184273a9db8f336d5b85419aaf85daf932d3cd53ca64346aec513429c8c2ae67a167e62e3a9664f16c8b9ebd	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	1	0	0	0	0	0	0	0	0	0
\\x90bb8cc921032ca2395532808060b3f021a3f35804e9f75158833e5fafb72e974d1631058bf1e411e334aea523af723ed2c86ccb332f07bd3ae2b6b8231997cf	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	1	0	0	0	0	0	0	0	0	0
\\x3d203692c12eb9923d55a0d6b6ab91e2ec89fac444f42fd112d9dea8f11695f4df574e048a9083fd9685a1e7d815605b36e1a6921c1219b0e2a8b5c42e477bde	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	1	0	0	0	0	0	0	0	0	0
\\x514f83b9c8b19643ba983b429ae8966695172e45b541e80edefea84df31fd6ae909c58cbdb43509266a1d6830bceff8fe090192d053afe8a9faf5172c9000b5c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	1	0	0	0	0	0	0	0	0	0
\\x212ce3e51c58e7655598261db863b8a19c468b0c34887760760e806c407e494816b09a33b795730eb6fbe2b9d620124353d5753611a6c9f79412e6ee3a3b245b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	1	0	0	0	0	0	0	0	0	0
\\xabd96c3e9931e1d233b7ed60cc6eacbfb49ebd9eea6e7fcb0589bcc68f08fd2038af5d1fc7c920c765d50d4724840e805dcd6d51cb98a6c6994d1216ae4eb85f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	1	0	0	0	0	0	0	0	0	0
\\x11467210350392346ef66230213e7a017c249fc7dcb937406ff065dfce0750f55777154cea27593a416e09d552407610ffe784ae03120195cc57edd02b3a2270	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	1	0	0	0	0	0	0	0	0	0
\\x0870e1f03f94307b2f93929c26a0c0c429beca747460efba4c088a0aa42fafd1307519698befffd053dc26a991d2fadbff073dbff242f5bb6d43acb6e10d7e6d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	1	0	0	0	0	0	0	0	0	0
\\x07e42cfe3db85ddc69883d40804a16c4b4881f6998e100de7f75043de63818d6defde38984f8e7c2e29f99be14d9780593e71738b05a016f19b6293046101356	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	1	0	0	0	0	0	0	0	0	0
\\x3f870816a77473f430c574c288649f6c3bf0df8f1b706ec4a4c855bf975464e0830ebe38529c687cc162b83ab27d3802e0d39717199fad4e7af25e1b369de732	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	1	0	0	0	0	0	0	0	0	0
\\x9333218df99c93e4df40f28f3fac536ffba5891f60cb87a12ce826946d3efa62db03c89ea5a625b89cfea422d3494222c0b827b171cb3b1774bf255b354c8a8c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	1	0	0	0	0	0	0	0	0	0
\\x29697e6d1712bdccba77abc34986b4292c8b8fba8bee9228c2c788d49a2f5ea5ddedbd98cb570d3a64664718fe16db31774d9e402c7f2e28fee93903a8cdbe8b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	1	0	0	0	0	0	0	0	0	0
\\xc3cefe3256308744a84b5cf89c95a2c30a13757d19c61c2663779bbc420ae22b90505e903a7423f5be27b5585ecebac464abb513e115a20353bde7ad9baa0cd9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	1	0	0	0	0	0	0	0	0	0
\\xc266634bd2db9ec85ed36775e357a0d819282e5c180dd3fbf56cdc2bef82e14534bf260ddd2dee5336efdbbe1f123d4dd282fb8f4901eb6d3cac73c4a1d138ee	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	1	0	0	0	0	0	0	0	0	0
\\xffe7b862e3c695fb176e9afca1d3cc064d1f3c0e139b10d09373f2da42a05bb6b2bd7998e247370b64923d97f09de55877ddef06887485d4e198d14d44510b26	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	1	0	0	0	0	0	0	0	0	0
\\x9f75172359358021693ff485f1222929e80ee5080cd7fe1cd09d1c494c7c83e267eb8c96640bb035a170ba674687fef5a5622357da286b56a0c5190a7f504333	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	1	0	0	0	0	0	0	0	0	0
\\x64dcdb0de7be1d285a6096e0c8527b81ccf6366f57c61703fa6ffea1514dc5533ba4a62bfca508b0724e4dc8dce838f797bcc53a72f23d3f406d91baa64e9ca8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	1	0	0	0	0	0	0	0	0	0
\\x0ee72c79b33006a3590bbc5dd6aa753b1bd4859d8761c8e8f9a3b2f5324f6fef4075dcd74219870737575b9e080c3f734573a81f4e52b74cb6be26d64a97a091	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	1	0	0	0	0	0	0	0	0	0
\\xb5dd7d342f98bc4e81c0b4c9081848d023623c5ebd6e771f9c12b1b7c8d98ed7e836949597abcde296e5d54cd02bda14ca9ffbdafdfd4041979270539a084e50	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	1	0	0	0	0	0	0	0	0	0
\\xecf0f5b0c72dddd23ec737eb8f651a6ed7a88156c8a19e5f1a14d8198faf9ce10294307f9ac655a715f7d3745d7d9b5ae2f97b4e7c1c6dec97c0ec259fa8ed88	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	1	0	0	0	0	0	0	0	0	0
\\x882152e9a91a2f95b2e48a90881c266b1fb3a53606d6303c659089da62857cfb19a805e2453cd0f5570e2e01f452477d784adc3e5c6959fa6591e96bed1d8195	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	1	0	0	0	0	0	0	0	0	0
\\xcc381f54608ff6a2184bf9a1564d78db0b02626b1b471ce90621dcb53c14b3ec786950cd6cb927055d74469555a00cfe9867b9fa180d411f465a6e147f2d0447	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8d83b3f334f1f1a25f10e62469a90eed0b4b80dc32566444d3bb9c8435907448229d602f28752ef2287e0fb754b844f39d1ccb6d2a59b5f098aac931b19a28ab	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x52c9c993a1ce634498f0ec98af8dd3a3a73d86daebe3defdb3eb90feb0cfefd649007ba749682428c0f69b21708c56f8cb6304126d51928a460eaa9aee567887	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5add7d5f44526109838b12044cf0490a44d2d28da55043a7d58eec653321280e923b7738d8246d8cdf826c4a0e9c3f2f54af33ddb4b022cf0976d113437d4c5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e345f8d351f401e5ad0834b7f3c0946f7cac8eed6b98dbc459b2139a3a045569e0beda6f575df50d17d302f96fa9ec571c8942f4d1575f51f233a2b41d7e09b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x6616ccd6cc3180ddeb5f73d04ada5c9f291db67f860475975c5675f767d2ae26f4471366cf2f9077d4671fc56ca4fdbe076e82d4ba940f8adcec17825e02f057	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x04d7cf21729b8ced93ae1059c28868ddc666d450b39747a373647f9185b2c93fdfaeb30ba78d01b1924f57cf95be01a6806d67c98d00a0fc4d9e726720b78a79	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x925e72365a5a918c752fdfb2289ccde677d4721746d4077483db4df209756b82512ee0663de0f11dbf67f7dade8d836a5b2e2814feaf547742213ecb47e26fac	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3d7c8c255d309dd29ce6e8d33bb125d664dfce3ff53fc06c5d8cc95f785228e66a5cd7ae3033e4178187778f64cee57c2842baf8567e3783b58e87d251fee7ef	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc54182a6781c3c00206b264eba3e382366280fda09fba57c5eacf1d65c5a12f2cf940eedf5cae6f769c011c4c78ae633d30b98e01f21b762ff1b22d6bf960f0	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x80ec5871379e7b8a68258613c4e46c374902aad24cc57d87a31f86fa0aaeb82524d8b31b01ed36dd5890b7a0d5387a6e683fbdfd58c5ca4c09be174dd115e8c7	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0d174906ff91aabf6e84fa9ce4db244760a17e4133c613ba200d31656f6c6969ce1eef2405067d8de2b537c4d587fc006ecf13808f2c6c0e75fd4ff40fb1418	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xa9c6d0bdc2d3c0569391fafc0b5a7e6e5ce9dc3ab36a8a56cb2e969032cb985999c3325f7a3768f094476ce833ddb603c1721ea7fd344027440e6515b2351f7c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2881c81426dc72e4b43d18e9eb92b1bdd82e330f12a8ec85000f9c4177fccc63b6fa11c4b4ed9ae437e7d7889324e86d7cfb21ba8742ab9594efcd73c69a4e8d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x15483a9c4dcb3d6fa94f617c981e10ff9ca0dde29c0bb545026442180c0ed8e3f2409c3f6530d187038bd38119e9a327236778870ab4dc0720b442c252cad160	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x93e15adcc567e28444720bc035c1efee111cada02fed8c430556990ab4717c7128ae6924fad853042a636151f4958b4c2aedb95e8ab50bcee9176163b5124dbe	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x071f3ce0f1f418c448f74c6509b18aca778142306b7e5ea53b92f4878485862d5012b98badb2a72ce0fe2e752c2ff12dc48f773e1ac722815986f765b4f59cff	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc9c5e9908161730d6fb5136d9254f28ff283add1c977dd186fc82b6da3fe6c0fd46ffa4893fca96283b18b22b99edce1e1a3349812e5198617da13e67342f923	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdc0d0c0b8b712d32a6cf859157b91d8efbf22dbb8d13e3ae49a5b289d485d9ee4a303f376f3697c9b11df0d5f4b7d891cc0ef95b4a3c73458c96776080a9ba51	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc83f04d2cba885bc1ab6696f3b7db52849ccd6d0fdba64f9d9b168593b7689f5ba858d57cd5ae764b821226c9ee89871ff4bf732f1d2745093c4b512aa2c0490	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a4acfba81f0911427dea3a61e804e39b451249245a7aa5cce76bde709865b4d182bc4474937f5f0cf7067408268778dafb97a14fe78698576e99caf6d784391	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb447c93aad8268d940c02b5babaa68f325a03bba6c64eaa98eed03df32df6178af81a39406e41416fa372b28b1ea1b553ce3feac9e1a3aa7ae2802f590c85779	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2ad21808e0ec2307baa7354bc60fc7e3e8d8ccd73bc6f88f0631e95cdc2e8d1d5aa9efa1a03495d4208b14b1ad8cbff530cf2171f26e1029047ccb5b007f1e6b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e791f503ff82e8a1ba0dc5010004ef51c7d1d7cb8db64e443f5d5039ef95ecc59d8bf31c77eea72a1ae8d18c21e0cf5dd80c0b6c751b935c3c078e7c9ce9bfb	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x9240867dd492875d923b1d7244a3002652706a9866b37fedf8330cf3124c0e389a3c284a6c82565639d0af73b40d6a2d297997ad002e477fd5841a19a49d9782	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x79875b39ef7b5a38e448a03cd9289f736da1563b7ce6f95261c40e6a06b80a2f114550000a49b22062e52a7112818193c6a1ebdd50080a6feef41177be0db67e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x33a46995279ebc8645fc980afb478a90acc77a3082eb3194df4c6358af0009826055651ff921c514c2c1dbea2c1de45a8f9957c47e0f593c5d899e1dfe876ae3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x863b65d7d87d89ae09496f59ae14aa10a63fc8dc642d6069296f7e74f059c446544d771a340a8f0569cb85929df06eeab233966132f49ee19ef5f7f9045273df	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x054f20ed574444009b530d5aa6f55fa58f47f724433a5bbf1248ed0b7e70da655c01f70a20e0aac3a9df023cc630f6782dbe928d4e804c70cfb7f7fd9068231d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x1a5debec1d5c74e65b689093cf52e730f74592ffc32e7e05a8e18aaa19d050a376c611b4e0cab869eacdf4681be37ff49b45c24c5b1f397e17eeff84b803f38e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x924c1fa04605e41c63b8022a9b48b53c1fafdd177843ada0dbdea3a3ee60101e5b8c39b22951988b9267b582a5e0f7f935f528be0e7db9e69215d93c3281bd04	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7143cf2457cfa3490c507a8205702cf02d4ead54ba2bd2c23c9ca6a193648f7a096ef203a43c60f71bd1cd96e8db56be0c8a946960ddf17f25ee21ad04b3ff64	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x4c457e0e83a0f3ea82170e770dae42feeaeff914bc5ca3bb5104d2870cca7510fb74d657b5de2758a88fe3ae4e7425f1d9a8a03305056c77a80bed63f56fa768	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xb027c1b0013ce8fe23687c0b65f3b806ab7e0c23747463947d446f8800047814c696877adfcc9dab8cc27363d9ca8a964b94bee25fe92b409b3fd30df0a1a47c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1566478875000000	1567083675000000	1629550875000000	1661086875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x62cbf68b67d8e0819c091eda952a987f116f6dc0372350a934c0c1eff2420a5c609376c1444e01ea4c47d0088afc0896e45a7e11d8f4061a09ba35394e3fe841	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567083375000000	1567688175000000	1630155375000000	1661691375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0af0af8bebb83fd41a9478946e4733e99cd68efc5107b877f28e002b93b6374acf691cc2c52add4175880fdc9d6205a845ac6f50d704c650513a233dd63d703d	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1567687875000000	1568292675000000	1630759875000000	1662295875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x95afd8de3f5399cce2738ff189cda489c1f797074f824066253379f3ce3279c632c759edb94dfd11b27106d4ca569370627126f5c430959a25ffa2a9a405536a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568292375000000	1568897175000000	1631364375000000	1662900375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x705e0794ec95961b906648e6260b7314b6e30a0f107d6e8f9e7dc02aa986be05cfa13331d520557cafc1d12a57ba5253ab646bbfdbcaeeea22d08079aa81f104	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x729b1e60dbcd734440418feb9f5eef8dc09a905ea309a0f514762e195309c6a3599172b6d04302ac3315f3ec808abcce5ede43a75b57e5975ecd50639822abd9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1569501375000000	1570106175000000	1632573375000000	1664109375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfffe8025b98cef9d246f4d77b0cfc67c2c9943ea0744a4be653307b45fee8513851734521139c29227f189c1040598a8f287fd421062414df6d5461e8e9dfe1f	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570105875000000	1570710675000000	1633177875000000	1664713875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x90d27850436975079057351bc2a27254c4262cfb7a1762b5fac19ea81bbd509577fb1e544d313872c60ccb525f71f74f5afc517fc5719bc1d530902ac7f09490	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1570710375000000	1571315175000000	1633782375000000	1665318375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x34b9e10ae26c1e444f33966b286c9a0aa36e5548bf1eb3e909c3641e1ae1d7b7e9a94ea08fc932e116f09131353db53830d435c95ebf41d6ff4387352e224b22	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571314875000000	1571919675000000	1634386875000000	1665922875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x3a7d6e2ec713ffe4ee6cb830e9ddc12caae478562991904773b656a30f26c76734324036c0b6d99f851fdf26c9099dc830d30ba078fc856de95252d59c856caa	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1571919375000000	1572524175000000	1634991375000000	1666527375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x6ff1a4400fbc70aa9493a85c93a1916d38fdcc6b4e1860693a217f897727a3c89bbd05910c0bdc498d3f7ee5bfd0e2fa365a3880d698789eaf697e78ee2ec8ae	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1572523875000000	1573128675000000	1635595875000000	1667131875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0ca9869b25b97e3051c54a9cb08dd47f4900dfdc82e9559c784b1ea48a709d1d16740c47948d64f7ca55d9a5a293e3730bec0571efdfc496c5268a885f7d949e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573128375000000	1573733175000000	1636200375000000	1667736375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x919e560dfbb4e9079eaed54aeed66ec6816626fd5666714341a358b59548d3d95f6e4bd7c714dbb6fef243d0a3ad323da6aef061c2015b7a7b95a02a6c2bb411	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1573732875000000	1574337675000000	1636804875000000	1668340875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x598dd70d7070ffe68ed795f39ae0d0b0b92a2ddee55c8b56d268040ed020f9c8df595ac56c9cc420c3b56cb70a7288b713fd22ed2b47a550eb6a0f16643ed7e8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574337375000000	1574942175000000	1637409375000000	1668945375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd5a48b4dc56eadf4819136806bf2e2e3bb96311b547c93763ec5c0e32a865f404103e15c237263822db9fea92bbfe7b6c435426771e5f795f3446a52b6d5c9c5	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1574941875000000	1575546675000000	1638013875000000	1669549875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xbaf0ec9c32e5e03e60fb842adc7bd84d295052d25a4d5ce39a26960aa2e80b54995e9d5a62b070f0dfbc85e1b5181f699d786e85bb5cf9711f81b5c18ca3fbd9	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1575546375000000	1576151175000000	1638618375000000	1670154375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8d230a72046bfca77620566d080691679706477ae7c26098c6388e794b7a31e9efeaa978d0749d5253490d887c65ff4fcec3d1a42c5121a6509ec162949bfb64	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576150875000000	1576755675000000	1639222875000000	1670758875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xce713bc5dd327708be310e0365a7ba0b8cb29eb5bc9856592d95e85ed1381c886ad48ce273d827388f34c77b7f24161e53e642a3acde975cd4ebc54840f7b90b	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1576755375000000	1577360175000000	1639827375000000	1671363375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2823e26dae94b8168f54a9e02e3c644f5fda538c50e7be4d2880c5b0c558d46c785e0091e3da69c2e3cf3acf677183612ab95b79daaebc38d19cfb6a91fbbeec	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577359875000000	1577964675000000	1640431875000000	1671967875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x80f059d264eac823bb92b31cba6e12a0ce59abe7cbdbf73e3957d89d22a821efdf2648886218c049ef5b96ca901ca6d43b6e7199eda92a2bd53f3b9dd748e7fd	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1577964375000000	1578569175000000	1641036375000000	1672572375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf9f31e1bac71c0af889a863112ef65e4dda3214c3065a9b7d01e0cb02510106dc895b1ea88961fc445d4d26c94eefe48866134a34f9c4eba77990796ff26d9d3	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1578568875000000	1579173675000000	1641640875000000	1673176875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2e957a3a86e6bfa5b54cbea5ffaf4ed301f1ce19728a6fc72d91f91bb5bf7627d7f2f8e825312420b28f5221a3436000fc190ff70de93e1dc18faa8a24e5ec22	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579173375000000	1579778175000000	1642245375000000	1673781375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x124be3f0fe7d2c3d2d4ba50f644c0b02b7a102a923fadf56d43f5fd92f3e984bdb12295ac266b971f99fd4a3fc93ea99166559293e973b24efcfbd70a237e139	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1579777875000000	1580382675000000	1642849875000000	1674385875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x32f69ab230825174f5be65f1fc758d5016096a61394de1bfccd69b6a5da8d6f00ce515e26c25f01ee432885b342dbd11651b5770521979f4dc9b940af375c7f0	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580382375000000	1580987175000000	1643454375000000	1674990375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x40da2c8ee708f1a3636cd4b4341f5aa08e7a0582f3881589e36b11486ddeb033ae28e70cd8938936354e0ffd8a541a9fa017f6b82f58def0bb5160c9d78bb11e	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1580986875000000	1581591675000000	1644058875000000	1675594875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe73c91b0e7a2e14bcc5d5207ceb91ccd4cbeb4a7bb367e8efa5457a18454ad9d6e3f025fe1e7b1d74036338cededf74663ec7df84ad882973065bb631bcec355	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1581591375000000	1582196175000000	1644663375000000	1676199375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x912d26044e3fe3a4bdd7069c29a5f251ae708dda34a6fcfb8620007d49ee8e172c2728aee25c2c3b12ace1d329f2fabde37a5964c70102de508fd9efc4077585	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582195875000000	1582800675000000	1645267875000000	1676803875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe31322db017965409574167342d517c79d7397f2a856354f2e3bb08b0b8a66e3efbef0cd3a536261ca1944cf32fc10c32cd85990597baf2fef7a72736da5bf46	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1582800375000000	1583405175000000	1645872375000000	1677408375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x067481ea7d200e302ade1720c04c5a4b9bee67ccb053cb81b1e46272cc93aed92ce5e2f36bcdb99f0230f9307141ca3a6c95361416dc9bb327648a488162cc29	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1583404875000000	1584009675000000	1646476875000000	1678012875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x73d7c3a05745e4b43910a1d9498c64885ffb1eefef7ac4734ae8afd2f9fceca7da3aaebda0e463763c359675c3a12c29d1b08ee88bb0ce218b1b542289b1d6e8	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584009375000000	1584614175000000	1647081375000000	1678617375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xeaf6697cf56c377732de356b7b513e9d77c7fc761b93c2d774610f23ca489fe764da5c0a36d068c72e39f207d3d52101505392d57eb2daabd6dd6532601fa0d2	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1584613875000000	1585218675000000	1647685875000000	1679221875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x3b34fb1e56355b088d1f5c8518ff6e70a109a05459acda8a9a675a494c4496daca10454875badb7bbd1688213293368457215b2eb2026a0b9dc89fee1ade667c	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585218375000000	1585823175000000	1648290375000000	1679826375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xd0562a81b774f6667e0c466000a93d33891d0d66f3ae6ae7387f09f37f9fae30dab18216c265ffde2549f6b1a162510a97b33875aae190c99e038b1f5e7e6c82	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	1585822875000000	1586427675000000	1648894875000000	1680430875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
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
\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	http://localhost:8081/
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
\\x59077480182f134f6894fe05eb75b81519d2a48b1d84c0f451a43fdeed61b9470d7d3bf4e4be1a68717f35728af2616cfba3cc059150fb46766600220e19758b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304335303144333336444146453045353235423134363441344341353030323030393845464245303132323444413130414536434445463132393542303045423833393231314145333232304142373546443831393935344633394635363033414344303634303432464442393744444437434445323333354330413437433146414537434530363230323945413834364237333430454439413236424630354546433739323843343242414544463535344131384435343146373142453033333945443746324336384632463233314433383139364634343631343444463734334234314342323135303742323543454537373234433938344343353444313723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x8a165369d71663d696e759778affda9843d63cbf0d251de2705088fd6e5796d387634a02f2abe837e2822b889434363cbfeeb14ba15abcd4b089b6ce1009f40d	1567083375000000	1567688175000000	1630155375000000	1661691375000000	8	0	0	0	0	0	0	0	0	0
\\xea916e4a98687f7db18cb77a313c0d2fa9573dc58ad0480bfb232d9883a7c02d64d2cc9c6131ebe2acc53e9e5c32f08916e220b747f3beaa0836a71ea66fed1c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432324342363034313131363036303432433633313738383432373633363737423336374342383130394344423936344242363738384541463237343542434141363441313233333831363335453236323743314233394634453735414431364232464336363037423343324131353242433233443830463138303933434145424144313436463346334139373946364232394630353434334431313041343442413631303431364630433637313638394630433343443036414435344430424633333346324137444343334136333844343443463336394430363443414144363831424443314237353237434534303634313535453234374330393032374423290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x3d158de906008112bdc51f5371f1b7eb6d26af19176da24673220d84434349407e3861372a1f58edef5dccf7cb43dce7d8faadd64c9c2f2674bb7aa5e627e703	1568292375000000	1568897175000000	1631364375000000	1662900375000000	8	0	0	0	0	0	0	0	0	0
\\x027be1e880351549bb49243fadcb17512bb14ac29f18d203bfc08acddbdde7965e7c74dcaaade9088ff38d518c2d071975703dba6ac2918aa890ce4c42377421	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342363031413338304435344439364542413442413335413031383145383932363641384230303037444631434237303233343239383633393739444337363334343235324438313639454531433037463530463034323946303446374432453733354232454445333639464442323442423437393738314245324638394335443341304634363936383039464435413639464332353345333143383331433731413741433143334645333937354432333338383039354330443442454430464330443037344330393444384441314538414141383030394330363937363731464338433031323135353631343145443235314539414436363446444637423323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x00e6d30ae36d0e30108796f321570455eb5a94d8d9e54d41b09cb9e3fe8847edab78f58ae719374b80955912cd48d22a64022ddbf5c9f8dd8c268a5e590e3d05	1567687875000000	1568292675000000	1630759875000000	1662295875000000	8	0	0	0	0	0	0	0	0	0
\\xacf90474218ef9b9114aa85e8ef1df6d0c48362621ad90c581e59654e9482ab94f5a32821563ee80291a510750d967e14031f75b7a2b59ffd96441652e2abd61	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303932434444303337323237383236364644424438463145353243353133313831453130413638413144383845394646413333453443304433453042443645344333393237313039463436433033383632453032313536303346343644463437383145434337433631413343304236354434454234393142444141333944344232364335393039394143433635464239444544323933333144434439393844334631373443343735423138304131423541333835463734433839433234413845454542354433393831353437414245424643433645323343434237454231454442354530443243414443433142463635393832384236344636383543353844383123290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x3575e2cc73c912c2292ad3d66c1ccd2ef2aff250c2059311f40c748b273d0937f6d9e41b31ff6409ce46649798b6798ec33715bbf07e5efc47727f1496bcfe0a	1566478875000000	1567083675000000	1629550875000000	1661086875000000	8	0	0	0	0	0	0	0	0	0
\\x346ec50684592a6b5af4dfc5479c496ad004b25c88be34d4b0507bfdadb104e01d8e5af209d9db35a1ac8681062eb106251c68276ea079f3d50dab9fa9a1bbd2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304239384636344445433643423336354544373742353844423346414337344345414135433941313739353544364633393335393232423946343141313135384444323341343234374130394334423346393132453533464230463741433035393838304431393339364644303946443838344444373538304135413946353735433639383232464542453931304642443031353432384634433937454533463739313346443836303031364231364639414434364531434330394443464545323934373539333346413534313732354343304332344633384633333041324233373946454235383336424143413030373041394535303933444533384644444223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xefcf04153a16b860179e2848543f41e36e37b80e512ff0919e7f231599881251178c073d326f1fd4135c468ae9c42107a72bc6bc15a894e688e98591042a200c	1568896875000000	1569501675000000	1631968875000000	1663504875000000	8	0	0	0	0	0	0	0	0	0
\\x23190d54c5e1a0b09863bb792869dcea0c3a516b4e7d9730b991e1c80971c31c96cef2549200cd8309b20c19e2cd7d9aa0a48b6d8dfac72a98a49dcdc3419bb2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341313231353839443335443535383243333039303733433331433839303932353037423041313539423145383331353030353845323232373836343831304630373833394432433935343730393331313634454131333845444142383232393536333542373745423139323845324342333038304432413941413139423239374238423637353843423641424637424334384636433835433032334138413336363636383235433034423142324534343539344533393936464646373245394445353334453744393930314645443939394246313446343931454330323337444441443535333642313233374431464431394242314346443836313845464423290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xe993ace991c68b725f5b2b96103399e94d27e0f3935b3da5145586c24ad5ea8e650e2da36110265efd6b11cbc955ff5028c1fd2b9106266076b96ab6f64e1908	1567083375000000	1567688175000000	1630155375000000	1661691375000000	4	0	0	0	0	0	0	0	0	0
\\x573d9bb0d35f4415485137a409f0fb957f19c969b7bfe58bcef654ad424ed49d91c686a78f2b5b9ec4622262262ec87f90c65cc7e646144fb84f69bdb2e8be4f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303938413937383341453342463246343042363537423332314345393138304132363446303046423144373044334641413636444539373742434444423331324639414338444435393946434130443838443532463944384346423244323943394338313436463735313946304346413335423846413632324538304334314537463132324142454434343339444239383742344442393346383337444543424246363043343138323843383536323645443438363536373834424237413635414435344337423735413730393141313333394441313236324144444635464632354345423531413442333545433439343446334531423144344541373732364423290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xb87c4f53685654208fda068cdf0bf96b99c120d54a0e65f7118e4a048f4f8ab0ca1ce8636f227df4c4e54f24aedee4d07e1a706d68fe668d080b31aba5c74e07	1568292375000000	1568897175000000	1631364375000000	1662900375000000	4	0	0	0	0	0	0	0	0	0
\\x91ecfc6cce18958d083e51843c0244f19777fb128bea7cc480a16da89ff11ea3eb44a81233ef63da00dffab3b5eb07efbe7bee9275d905c2896f9a4afb21f86f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333364635333141443930333342414130343545353342304533363034434445463835333931454437314645394636464538453133314438444442384130333135363845323538324344343033424636413134384338463530443839383044364534394538373531313346423944443536374442323739313032313138453231373338453743443434393232443637353539353046434341434436304438374642413439324632384637434239344244323037363838333831363535464138353438453744433332463937303137423830443444393936414530433137463136303738364542393532463232344444453831314545384332433731463339374223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x703e38b60dca296ba27e03c2200c9f3451b5969f8be6656d719772bf945562514cf1affe6387e94149c4efd0388f7d90f38cbead057b465e3dc38a49556e3a08	1567687875000000	1568292675000000	1630759875000000	1662295875000000	4	0	0	0	0	0	0	0	0	0
\\xb6eee945719bf92c3e082efda32aa41d218e2f855488f4d976d0ec48dc1ffeb69c1dc5e60afd6eefdb9d4a95c07bbb29b8836ddbbf20bf603ef5f6d52132a826	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304638444634314232413934303635323630374336354441443639343230303837354344304342333336453743433030433435324331364641363139304143364235383139433631463644304435334236374337443646413838443533373146353438423034313032463234423446423737413144304141384446354331444633364532463346394637314543374631373434314232393044463934313632393031364544383132394331444639463632323833343041434437453234463341303933354136314638364538393036423344384631444637373633303537303330393243354532324235454136303436383339304534424432453844414535384223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x9842be2c9ba2550947b21af35047d9096f570e28af126059bf03f388eb599bd0229d84e4dd6bee3b28d7150149b3e2e813bc81282ba1841c0d610b84fe2ab003	1566478875000000	1567083675000000	1629550875000000	1661086875000000	4	0	0	0	0	0	0	0	0	0
\\x623f19b7f3557aa179d3af7acb6054a9e4fe6dda8a347ae0ba8a9255067f873a8ac414284bc9c390af528e46aa48115ef9599494ccff84f6ff52be9c4c870bd3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431314430353737333441323336434445304532454333414645454138304241433037343644303433323933414233444234334139433539344237414445423032393244464342393339314632384336383246463335323041343437443142444441323435464235314339393842373030433531393144303533383235424536453735384242413234354646454244413043374143314235443538463845334342424335423442334344413446313231314331463231423138304138384432304331354332444442463041363043394632463831433635444242443734303542444241333733443731424445303737354446434239464446374436434138384423290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x7fcd29f92348cf51f74fa027fd72b9397e37867a9a4d13371c6ba9f3b714ff1fc315ab33bd618734717a884f8919faae669785fbebcbd7dcedea97c66b665401	1568896875000000	1569501675000000	1631968875000000	1663504875000000	4	0	0	0	0	0	0	0	0	0
\\x650df74a7251749a3f32b36e95292e78025d170d00bf79012aa7993b0dc2e762fa96f3b0c0b6de50ad4469cc87d69cd4a7604fb576cd21d766b8a2510cbae007	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435313835423443443733373135324234413434373844333241313931324145384531323241443833333444334136384643303630443645333742333936334539374230444232303931443035464532313130313046423142383730324634444441413432424445453741373943383731424239453937454432464638453438313333413542313731373336323236303136353131413933393239383146363746363938454230373842463935383736423839444644363041374238323739314538364642393043373945364145414336444441434135444331343242423542314137414339313644323833453945434336413934453930354346453739463323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x2924a35786c4d3f1f0cca9572e8d4012f7a3d10171f11dbc2f7f00b61d902d48e7dd6075203262c90b94efb15b3402d3e8cab3077581a847fc09a8a4ecf10b02	1567083375000000	1567688175000000	1630155375000000	1661691375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8a5b81507defc65a176ce3dd3c9d4ebdab05331840c0dae4a485a0cbd30b7ed61797ada10ffdd67e383707ae4c829427eeb0387fd79ef1a3a45a62d033fe33cc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442394434454143363236323536363443393632453239364131433545434435393436333945384539423639364439313544453632454241354339464344374442454245443044343138313946463038353434353341383730324644413335303233384446393743363543424239373346343230463641324544313546434533424441453645383546463141333431314631303139424236333133303335354135323841344137374436414431413434343331333243413439413433323638354239453535433936353430373545464144324146333645344644303446374334374141323634323631383536413237364534443745413435314634343943343923290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x6512d8592a9c3f11c69a3f5867a420eed2bcebf351d66a644cdf494514dbe6f6d10b4ad7e30d373b78210ce69b83de2e93c75cceeef1da1a8ba6bb743bf1d108	1568292375000000	1568897175000000	1631364375000000	1662900375000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8d614a07a55046789f3c78bef9da832e0223b4b149e89c98bee061b780c24d5618f1d89efcd31900578f24e714950c570f049823ddb48f9616dfecfcb3c3c88	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304439303441353431423346423133463532463039424435303933333839303842433145323944413637323332444234354443303342443343464138443744413430453045334131373542313732363139434137333842353531304645383338374141423936463232303830373030453235354541374245363243334335424541453233333444393237353633433739313130454638464335413536383739313446354238454538363135454639393534374235443142333133433135324238384535464537343833414535413634323243314434434333413642393034423730383044443042383631444135313443373336353331463331343631393843443723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xc40ba8c643ed48d25108fa704dad2253f19594f0e05da5e15f547cd8f53a683aa4ad144d3d3aa8dfb14112d9fc9651ac96059299e29cbd179c2bdc0ac08de40d	1567687875000000	1568292675000000	1630759875000000	1662295875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7707c3da2c64fac4e92e8f25a596fec874197dbcf35a60ac819970c779f03799603e3c48e3578e1a3bbd049437a76f38f1ab0997f51fdab1491864171f04c038	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304435313730414631413644383041454641424446344142434644444545343941414336453434444639354644384242313734443932443241414544463731324334393635353044314646413331353733323742433843303044414646443330454637353546323636434138323830444243303837463036434333374537324345303738323137313741373835353237443033374646313143394638363743344543303439433545433935313737454239384444323234464331414439434342303742303042433136413934393834393746343344304341443645454531444141333233303845304241333136334334353534423838464234443639303035464223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xe34a22492c0ce676e237fa13ae78c8745e1287bc02fb4bb403939e76959179ad6d56467becdc8a1d28a473cc44e1786240821a48fb04d5761807971673f5f90f	1566478875000000	1567083675000000	1629550875000000	1661086875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2945894b42cedcb6e2d343c912f92c5d946f6a2983e1a394e65527902e645a4e14e7d672bd9f590f4650d7017a9f9421c7843aa6832ea505f17f29da04475bcc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304230383332373443334233454535303430363946333130443235313338353542424432344434324131353832384336344543464334333041314646343745313844373534303536383835413033333546314539453332343531303841423136423637444641413938364542423537433641454245363644363836333832333835304130334334393733353742433335453935303645344136433334343237424145323337314534434334443633424445353631434544383934313137383541303131333339463843383330393133463933354337334237423446444446443438444630354342343131463435353037313734443734363133304642323241333323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x9ba33da9df7a865fe3426ba08526ed8ebe1de8093f7c5a26fe7ad073c4f5fa1d5e759f932129ea4d02b6c3adf58cf1acdeffc85ec3ac72de5ebf9ae42672da03	1568896875000000	1569501675000000	1631968875000000	1663504875000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x62cbf68b67d8e0819c091eda952a987f116f6dc0372350a934c0c1eff2420a5c609376c1444e01ea4c47d0088afc0896e45a7e11d8f4061a09ba35394e3fe841	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233413242443342464639383032344241433538394131434332424246364346423439413637323731324442413835433334344635343942324644433836464141434342383134443636324137334533343931433042313242354234433044364633334644463343464442364143413044344542423943304333343941424331454545333742433141463535434143343438303633354533353645303434423335413731393735354541304541383643463539443341364331363044443130373442463945394630344444414437383830414138443445443033444438324434453934413635433145464246354332313531363633323043323645304645444623290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xcc5ded4e48704df03e7608d4e39f3850a48e0e81960ec2b408fa32909fea6afa1c53d7cb154bd4340bc09bcff5369344ba96ac43dfa1fefe9a47eeab934ead08	1567083375000000	1567688175000000	1630155375000000	1661691375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x95afd8de3f5399cce2738ff189cda489c1f797074f824066253379f3ce3279c632c759edb94dfd11b27106d4ca569370627126f5c430959a25ffa2a9a405536a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334454136333532433842333244433344343132333839333945313930433535423243333144354634314237373046353535433336433042324633393034413138394539303231323142334235454530354144323539433131443735334635463335353833333433424439383845423337353430333142344338413536393239444433354230303131374337443746424430413637443138453042414538304446463632423137414244364239423146444137374233343334424244433735303638453943313633414634383430334143303741323641414235363342423233313645434430353946304239313533434138334538444631423044384546383723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x47ef8a58c149295487d3f6c1f11103ca5a0087b31a327bde11ba382541ebebbbb541153c4e15214d782807f047d2a9d17854b4c2b5b3950fc9ee08661f753c0b	1568292375000000	1568897175000000	1631364375000000	1662900375000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0af0af8bebb83fd41a9478946e4733e99cd68efc5107b877f28e002b93b6374acf691cc2c52add4175880fdc9d6205a845ac6f50d704c650513a233dd63d703d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304431464445413944443543394445433345464133423043343838313142424436353041344239334446353546313145424134393734303632314346374131363533373334454338453436424532383937383536313431314645384637353044443334413145353230413736373332393239313438463230303534333533394432374636383642323746414642444246373731444435303446453145453035364335323331324641323635354145443838443138343335323539344245373934433234443032414133324635444239463934383232323242393133373538433141343236424142373034383830334344303945353239333331424543324338364423290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x9f9290b617bc8ce33e0c083e46194659e6d03758dbd2c2306c9f8f7b71b1eea417bd707fe97f00058b65be1912fd2f1a6dd91ff583f66f8b79f5d844f9012f0d	1567687875000000	1568292675000000	1630759875000000	1662295875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb027c1b0013ce8fe23687c0b65f3b806ab7e0c23747463947d446f8800047814c696877adfcc9dab8cc27363d9ca8a964b94bee25fe92b409b3fd30df0a1a47c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304137413739444530413937324332303545443633303938303137383536434630394137454236343039333837373634423343394532433232424345363844453039433745354342423236343345313943383943433144334139343038454345363646454545393244413844393832303832354644353145413231423346413145433537333236393630423230383338393136443932314544364144363137323736453931303941423545344632373741344233454231313838383545374138313639343236354135463037424335393533374645304535304545413731434546433437464132433836383743353335443446333035303842323745434446443323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xa69dfd90c6ca38ec14d07059ee89b0a0bc4e52f1d866a99ec3d762527e5878d636732e3523843dd0327a70a62d8f55adca34e44c5ded2e7b1f7c570d5e4b8004	1566478875000000	1567083675000000	1629550875000000	1661086875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x705e0794ec95961b906648e6260b7314b6e30a0f107d6e8f9e7dc02aa986be05cfa13331d520557cafc1d12a57ba5253ab646bbfdbcaeeea22d08079aa81f104	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304436303935394441304434303937384436314438433846354243304642364233393043363233364244373731433630314246463939373934314245324337393538354341444334424233433334443043373039393142453332303645433343434133364139393438463235343043353834354333463644343433353334344530414636343230363346393830384339433531323238433932334435424546304530343038323239313944354632413933343235444531394130303942304636343038424146453831313236373134444131364243333435453432394539413236394531384644324233393042413333423545433839453230374437304631334223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xbf815846779aad38dec32721a22acf5e600ff6b96935056cbb0dbad4127a79f702aac5fff7e636ba8e9fb636565c30a8270f74fa13517be00b0dc44a18e58400	1568896875000000	1569501675000000	1631968875000000	1663504875000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xdde353cd7954cc9e794addd2466acd9ab9e0f56471e853fb273549d069f4a8ab9169816f5ff3a7e8a611c0d32416620e4cf1d002235eecca39957ff46fa05fc9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304434333844454237303946373730443937353245424642334441384630414242383631303735464431383645423644463036363231373939434246353032373032354530413137303239384142453439413239424538334241453738434443343945344231343144444541393542463036323837314635453032424643444635444543373946433436453841314135333134333337423342444635443137464430363137424345384338303135453137374645313245303539353932414639393334463245453441323542464233344645394630383738423146374334313636314337454535353042333244333141443733343745333532383843364436443523290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x53cb05cb86a060c4c2986d573dafd40036a2c97cec1e606cd7a5fa29180ad095465d1137d7ff85cb3cd03cc2b21696267a2c8eb52edbd00cb78281de5ce72c0d	1567083375000000	1567688175000000	1630155375000000	1661691375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe40dff1ce920106813fd1e2d1b9529d0aaee8c9dbae444ed41dcb786d9810d10f8e69cc7cd4b1c652b268b43ab063d5d932564dc89b1e2a09d2fd0093fc5b1bc	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530334433433343443936433131443036343130443437343734313132344339353742423731414139343946444630433434384642444334334631313833313738333636374436353243423542334233314533413437373839413844344439364237313430424539434434413530314333324141364539314639303241363337454135374141384142344135413139324331323432393543453742303734413034353930393835444644394239393738374134453434304431384132433033303744333543443839393538323731414444373033463636343032343733343431304330434437323534353039384433443141354642373242333544333736304623290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xd2221306797e4b308d319357afe606e68265df22c2a28d4442bfb982ab34444697397a54611500d27bcb30c4e917b6f1f8cb327841818bc1bab037c591b57f0f	1568292375000000	1568897175000000	1631364375000000	1662900375000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5f075f1b3d8d6aa98e30e034df751cdec27ddb44fe76495da4d2dc97c8be72357bab591b4d98312abd0441fe82a89a354ba0ff79f9da69b4fc7e4d11b43fba1b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330303537323741394337384339383235323135424535314642304346373330464535463839374438304137343542433230384637363037443832443238313930323134323145423538434533463137323145464143433145393645444439354343463831314634394633374131313141443734353045443541343343353042303137304444464243364437353043433245313535364644453935453932323731443633314444363434463244323534384442343046333941373545463644363839373331313234343044414134323934454643393330344441423741413441373734434535303530453231353742303933444346313031424131323834324223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x7926cb4e3d76b127ded348735b272c762f8deda7d8f0ea5102dc6bd46347b270987c9cc66e3d3a3e3d93ce82f9c081a32f10338be0052fed80dee0ccc325490b	1567687875000000	1568292675000000	1630759875000000	1662295875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad6acfa4f2cefdfe64f0b5d0ed5cb88329d526b7356d4291c0f6be28b97239c29f00d3ce5aa25aad8d75f1193dff84abd85db26e8f048968c60ac77973e59c8a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303946414138303733433546373846423038444330423732444238383646453345424537344137424339343141444236373434363635423632363633344432373335324242334133323936463339413639314642414138373843383934323330343534393038393545384236383342464335393441453933463435374139393645303434364331423430433939343234334242354631394331323837323333464143313142344638353932383742443930303937354531414442383631323644344544463131303233323334453046413930383845453041394337394443433331424242354130333545414345453530354643353143363539344342443732363723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xae8a5f4878d20dcd3be0d3dd9feb81fb463b4880a5b10e16435592928135f53474f3fada9f4fbb6b2537f7cd5c9305ca1361fc1ddbae860b047ed02be9a54e01	1566478875000000	1567083675000000	1629550875000000	1661086875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x37a91e8e9ce8da884a93e10cfce79eea2aa74ea91f7cbe8d0a68416fcc907f46f01f3d13dcf4b1d8c6b07d7663c07675c096e11a0e4c10c37f5cfefadd59e46f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304536463945434142453446374532443930443735464134313031464646354139303632304336463239464130414231333046413446334344353141383438333445413746343635414230354346314546323136413038324631313330453744394441334533373335453945323636323837333530333039443833343342424245384632423032454235433932433532383230354330463544453736313836383041413446373944433931373242464546423038443542454332323833393931433537364439323532413944413935393434303135333334344436454145413732424231303734343836453935364341383733394136423935453336384639373323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xc5fc442e0618a583f5530bbd2abb38aab4e44515fde4276d4e59c002ec9e9018c8e390d8a6aad47843a285411fcd436f41265531757ced3df40406a907d7cf09	1568896875000000	1569501675000000	1631968875000000	1663504875000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcdc31ec50360d683ed3f15ed5a2084fc280033713592c732520178c34c8202e1661ebe32db137f5fa5f8e61a2438e0bfbd3f2013da6e35efa3a061b80dd21977	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304232354130423633394138364342463241463538364441333545323345363343324644364334414441323546433943304333423138374635424136313336363434454242383639323937463641373937334634324539394242364330343436453335354542333138333846413632364231313345343636344444443444364137384345444642443735384336353539364639463733454630443134423443304137373834393630384346414633304432424636444232373232443131443146313938393739313636394341333538373631393338334543374441334245333935363335373441343630454133444339303636353139313242463131363145463123290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x12fcae8d5b55fc9c2b167d81335d801e37961ca2162949fefe6319daafc3cf72233032732d63941a5ded7fc3b703b5c3bc253f9274a4b1b363b7a9383f64d805	1567083375000000	1567688175000000	1630155375000000	1661691375000000	2	0	0	0	0	0	0	0	0	0
\\x089901668378bfc4b9cb775f080c9bc5a1674bc1da297bd8a9dc3548ef0dd4d81e4770efc57246a0bda00fb89729f7fa1e90abb13008a3a01eb8d3ebc8dbf32e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245373345414138384339424645433537453142393644343444454332424639453437323234444635334445393639333137313335393335454534314535433645323030324235323734303342313432303430423041353230344631433441453039303546453945313536334230363231344234323732383633424243314535313233394243343731333045384138344238324642443142444634453032374433324232363046323841464143453343364534424232383843464632424445463930394532373939433838313838453243333446343233373832344143453542383132454436413439364338364439454546334536453037353142464339383923290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x39945846d751cac36cf75a0651c140edc6d5806b29a0585b4b5881ea0dd62e5e8b186660f4513ae0117a8534f6ee69aef31205f612361b49d07df6675a33c602	1568292375000000	1568897175000000	1631364375000000	1662900375000000	2	0	0	0	0	0	0	0	0	0
\\xbac3fac5f6d7c73fbfdef7b5f814045f061a49e38fe27c295405f3b9948524839f8f16092be31e464b7a98d173cdad4cc4cae852f9b5c1fcbc14c08db64117b8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330393534343935324136354339443333363937363041393230434236313341423932393446323130444439353239363142374638433435303343333439373142373731313638324534384135444530354431443533373131413832443137433145434136303442393834444146314345453943343545394645354236324241433639374533423944353334374539383732353334394535363838363236353834324342453845364135444133374438303334344346303730303437313443303930304133344145383243354630383735383730363637433046304339343330323546414633374546354337434135443334423331444246314343343033313123290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xc2791a8c22cffd5a0880637837487fcb899fb59023aec3eafe5e821b254a2d35ad560e0a3b653841e48f8f8860059bd621625b494fe9745c65bc0fcfedf2f701	1567687875000000	1568292675000000	1630759875000000	1662295875000000	2	0	0	0	0	0	0	0	0	0
\\x32f04fe33aab830e5fca30c948bc820e3137142b5e35c29a43a5f100b30167891e435bcd5b9d83815417d3710c1cac2d2f494827b0ab0044b8c4d397986f75f5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304546314236413631423539384643384446313136333645323942454632383038453835344439464636463239434442313646443939384242353538423935444144383638304533344241393238443345363837384438324446414336304435373336303638324237393739444437343439313832343635463435303135333339323946444236433035433344433334433042393343364238383635424630443937463034353742414436353731324138373238463238324141304644343038303844443430373431374233433841463737354136344231424335424634413437383734384336353341363538364341414531303342353344303046393532353323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xa3b19a233c08f223222ac4be84d69dc71432eefe93985de95a5d5134f4b6673bb01571672ebf9fde546e25fbc9d8c5498ca0819f80aad5e17d14014e672f7a07	1566478875000000	1567083675000000	1629550875000000	1661086875000000	2	0	0	0	0	0	0	0	0	0
\\xb3426e6a092444b204b0904411b9292d953d210ad4ef917e08038066aaa2bcb7d74cb24751c73d02b74dd643b9aed7aca308234198fcb91471c3a123f104a5cb	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304336333435393235413541464333453244363135453742463530434443303442333734314339374131464238463935433533434537314230334245303731394139394144333738373445453333423142374330334338394642304144464631324241384335383439443634313345414330383630333331373935383933423942343642443039344433303430394146303331363930413145453439393446394443363131304245383445383841343339364130453635453336354636423045314432334136304537463335413831463030443431463537373636453632344135334546443944383846323931423543373839424131413437463133334441334223290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xaaec70199b865cdfe9e603f1d273f16556cc68ddc06a8eadc8263475ff793a2b0802222a025ab154fdad628557a1a1928240f67b7afc7e0110d2ba6beeb17303	1568896875000000	1569501675000000	1631968875000000	1663504875000000	2	0	0	0	0	0	0	0	0	0
\\x65d6f5fefc621fc9feed381eee764f30cce31b3e5a644dd0bb5cbbb2104764d67cd80f7fefcad3b1d1ad39a43afe4d3c51573f5e4ae8eb7c975dd071c4fb2dbe	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304334413541364342463732333542314542333937443832364146413034454531463032314235333244394535413232334342413636393943393445303839343442364437424641373039464244413332313238353838443745453035304537413837304433303142323231314230453035353641323132434542423236353739433946413439354239433132463032344435383246383741334346334545444443363238373134443134393832464534374345303532314236303037414536374537414133463544353238424342384533324633343234313339324333463035313644384134353035383334353941323333443838323432444145304246353723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xf8ddd927a86daaa2264dbd076dbd45591be110edafaadd94189e5e67a75a813ce92274f7b71fbb8685631a9310bdb3b9442d1bbf4c3a213f7107a86fa0a3d801	1567083375000000	1567688175000000	1630155375000000	1661691375000000	1	0	0	0	0	0	0	0	0	0
\\x1706a5526366a6c0f68323cbe8f31a4ef23c7d4dffb5cbdfb1fac61a14aab5761f48aded11a89b8ca522f13be2065b7c6d443b585628f605d6e23a8ce5e2ebb2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304344434233434431414231303037314142434446423732353645304231423133444241354136424239453845354546463730314142453541424337314346324641344630433637363143444543414435324433313831393441433530323437433032424543354144334431303435373941464346314546463830393443383843324341373639463031304632383030434245354334313939354234343535333142414145463734303137333646323436304246314443354638373035413732364531454636313141373831453539423137343744324244354544364638333531334639363631354246384131333036323039444232374632434232313031353123290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x457405d35713ecca7e574eda64c414fed26c3dbfde0000bfb51e43ad8969e231f65c71e0b9d19cb6d3bd19c1100143e6f2b674ce63130179c603b397b1434b01	1568292375000000	1568897175000000	1631364375000000	1662900375000000	1	0	0	0	0	0	0	0	0	0
\\x3b0ff1f9c9da0cbc0505563bb32d90bfcc9535988922b4b46172479270b93373ae2674b3dceb4a91d57cfb1c90ab93e2d78b36e8f79128d2c498731659fd8932	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304241303743444235463130343536323133454633303636414635444233364534384639433943423244363844433632463443443334374537423645353339383343394444443338334642413035424142394339463941393943423537364436463339394337453745303946393946303941343930314433464534383545453943453334313530323741453539463234333635344535373541383531384138323334373441303035323532443845443444333331423434393544343945384237394641384446334430333637444530394636423632313042434236353536433631454133324538343441423136423535433832313638433831454535333938363923290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xcef5712a998d4bdf4fb7642ac01cd9f3f09f142a482a741b0d3a837d377ed09661b984b5882fa4a0715b946a451d1ae45e24cec8fee361b606f12ac157281207	1567687875000000	1568292675000000	1630759875000000	1662295875000000	1	0	0	0	0	0	0	0	0	0
\\x36a6d862f41c8a84e8f9964bbd05476b0170b76f9aea4f284a71c1377ffa4a70f59c5dc23c612cff323eaf0371f65692cd94fa90e57a2c312d0217ec2b0f2838	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330433142454145344630313433433342313137463231454645463845333738324132423633303835303631444444464146453141323246333441364532343842393834373936383435374638453230344345444236303034423630463337313437343138364332314546324537393644313233383631393642443838464637443239303833434246393038373541383842303641413245343544313836334430313345454235323832423330434531383536303041324530304545354141363336414246423443434446413746433233363241373343463136393942314637454434343634363143304332374246333730394144303536414246454633423723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x897d3eb729db61f100340f0b7f38c57033b8301b5eee3cc8be1c0e29fab7452c16860e9191f6dd1ba6d0408505aaf5a834979769fd8cc28fa0231088cc805f0f	1566478875000000	1567083675000000	1629550875000000	1661086875000000	1	0	0	0	0	0	0	0	0	0
\\xb00a85a2bbf304bcee8307625c10eaefdd4fb9e7840820fce73583f580f8c3ab420662a4dc6d410763e582c5935f25ea4af5dcc5ac7d199344ade946107f451a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304244413038443146314438384644303346434433364335323633393039364544333645433236443131453645443831324133343143313939373039444135463042333043393246393646333245433446373830333231393132304336324142463432373144353034353133424536344530303531313238413245444638454245464431343137443435413145434544384643454337364238393945354535463944314231424446373034454144333343373435334531344241464131413441314637314331454345383033453546334232363237303335463035434631413945393241383937454631383443453034383632453832413734453745423833393323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x0138b259e109a10f1858646cbad01ba6bc5abb1fe008875923d9abb0394898a020bf95875317811b53b74a6dcda35ef2a8cb434606bf5b3e8277ee31b014a30b	1568896875000000	1569501675000000	1631968875000000	1663504875000000	1	0	0	0	0	0	0	0	0	0
\\x8d83b3f334f1f1a25f10e62469a90eed0b4b80dc32566444d3bb9c8435907448229d602f28752ef2287e0fb754b844f39d1ccb6d2a59b5f098aac931b19a28ab	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304233414131384130363833443846424644313144413534323643333441333344413432353044443734413935454439434241444342444543414137373536423635463837373446334446423046303044374342463935354536463541334131323837463445464443413132314237383145323345324433333045383436433436384239463639433031413031423439323942434533394530413532393842323341333633463739463442304635334438333630333246463446353034384336453732443730373833453135443546354543423031434241373146333135333544304543414336463238444646434430363938304345413838353832313236393523290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x49932b0978579ee9318234dd15bc09f59afe1a3b08de38cf76d867c2917ae8c1401f91f1915f99dcf18ab2197e0e4a29cff0b593457913513455114754f69b0a	1567083375000000	1567688175000000	1630155375000000	1661691375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd5add7d5f44526109838b12044cf0490a44d2d28da55043a7d58eec653321280e923b7738d8246d8cdf826c4a0e9c3f2f54af33ddb4b022cf0976d113437d4c5	\\x287075626c69632d6b6579200a2028727361200a2020286e202330303943353744453242354645353337383442394136463042334336463532363638304235444234423441364641393545314645353646363637424242413942384138324245303545454331353031423132384438323042453630453234453043314644433036373834383230313330383846303235443046384643333431383238373037364137364639463039434239393439343545364436413141304433303330394339463339333132313139354141393139324231354236383937464639313135363732423441413336364343354237463245304444364242464139443542413036364334414434423943383843423944354638424343424538314335363323290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x6e907dd11f492bb573b143610e25715ed2db0adf26f4753e4c3ae3c6781ceaa41b693c9b5d0da0a71e89a2382bc78ce3a65b7101f5260ebc22896aac76484a06	1568292375000000	1568897175000000	1631364375000000	1662900375000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x52c9c993a1ce634498f0ec98af8dd3a3a73d86daebe3defdb3eb90feb0cfefd649007ba749682428c0f69b21708c56f8cb6304126d51928a460eaa9aee567887	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304538464331394444364539303331453941433532423631313636304439434644413233444636384341354633324531354432374332313332384438373533334233423743323344333536444134384136303841453931393437413033433341313338314231463944364538373031383131353136373844394131353744323438434346433144304341373041433445393233363631453843313836353737464135364534384134454644463141304643433531353332343632314330384545413130423535453736304542314546304537433845383343443139383835353236343237304234333038363435443834424633323736424134323737423531353723290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xed837911b1ab6ae5540ffeaaec866d21cecdfa95d5dbef272eac164f97a17af35d6f5492f28cf1a33577f9a67fd27c05e34527c6579d0777935e81b8cf50b90e	1567687875000000	1568292675000000	1630759875000000	1662295875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc381f54608ff6a2184bf9a1564d78db0b02626b1b471ce90621dcb53c14b3ec786950cd6cb927055d74469555a00cfe9867b9fa180d411f465a6e147f2d0447	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304136314635354437463434454537453135313542443835373644413031354336303544433333434442364343413738304134323943443445333044393332423030414634393141363631393039373631343935374338324641464136383442414634344343334237323739344642434530323845413946384335383441464438453644423844414537423236383741303242353044303832333739443732343935323539314131313735393945343232394343463339304336303833374546423544363434373944413133333333374646303145433138313733454533303035313942433230323431374341413033464446334346454436373530463941423923290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x397a866c83f986c400ffb352fca356a2a09d25d3206cb3ad8b780ecf791a9d6c16fcc9eb717d0b5f13923a515f4792ae7f6c7b97222caf7861da2b201ce8ed02	1566478875000000	1567083675000000	1629550875000000	1661086875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3e345f8d351f401e5ad0834b7f3c0946f7cac8eed6b98dbc459b2139a3a045569e0beda6f575df50d17d302f96fa9ec571c8942f4d1575f51f233a2b41d7e09b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330444432443135413546343231353934363843383842443632354232383037464442453143393145394331363833394130413338414342383141324439424238394242343438314146384238383135434242463146413545464433424234414630394130394435333638304343463936363837324137363131454232454636374331383146333233364432324538393639314534333143363445413033433043453139313738303845423742314445303346423944413233434641323432454541383331383341463342323234323633303234324443383733384444333044453338343336413130304131383430323433373034423045334634453045324623290a20202865202330313030303123290a2020290a20290a	\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\x3e42a160ab601b715e9b74d18f903e2f9ae242cfa5c24f6787e184cecdbffe3e301b558e7d95a5bf3b449719f1c507e5cec64d7ff9b563756ad4c2c07c32440d	1568896875000000	1569501675000000	1631968875000000	1663504875000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\x9aa5deca35934acc08e762ec55f7a11243f998ff8c8c3cb499a97957f94ebdf0	5	0	1566478900000000	0	1568293300000000	\\x9d3c6c0d0d865d3758900dea5161d1efbb6ad0363b87abd2a41918e876b197eb	\\xc183fd5784280ae9669db4e5700021e6a982696e2f4269fa20175c642212f3a51bb4f426b98801bb4e3377617a772f5aa9ae4071052a84e4d6ba2b429b72c2b4	\\x06bc640ecbf1f09b29efd9ef5ff857d2a59e5c9208aa4e3b4f5cc1f6aaca86e1cffe4bb5a901105451ae240514616d52979a80c90dfa52dc82947e13df5d61cd	\\xc10cc32374a0547d3e5e3510b81e7db66e572b17e32086e23b2727732a265c2c2c7e5f5f74d08c5fefeef665051260028bfe13c78617cfbf6a31c6261cd37207	{"url":"payto://x-taler-bank/bank.test.taler.net:8082/3","salt":"16ZM33J0FXQGGR6ZKNVPQKBHNNG89CRBJYZNV24H5XT910ZCJNJ3CMQ7CEQWCVSRQMEENBK18P3XM5M2CHGW79WD4EC574PVEDB9850"}	f	f
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x2a016e761a622892479ab96cf7f71418048e744e0c92509a714e7b1172aac864ca1e26a6e4d415122055086b36f684ecb01e547feb701d0ccbf819e9b756a509
\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\x15627aa07a6e7ae0b0a0a44297903515a25b7018636947205389e4d6ac56daafc8bf497d67af8482aaa3ab5b5a8a45d2a4a0e52ab236d9405ec5f3dff49cb90a
\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\x638cb2d6d56ff714642fdaa1fe644906a83acb84cc9c52de96cfcb8cf236c61bf4d7577281094147be47b971ec3deb103b1cd4d64cb1ac1ff7ac20a98dbf0509
\\x5c8f6e18b32ea49c2323d3a7f2b04e8236576df71535132175b91b402067d77c	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x3d6d36e0002ec44ae34bceccc9a36884c4059a1807918e9a264c8f2d421e08dd27952cfe6bc55bab8cc77e0b45081677323d60a9b73a1cf889def07fd2d7b10b
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x9aa5deca35934acc08e762ec55f7a11243f998ff8c8c3cb499a97957f94ebdf0	\\xacf90474218ef9b9114aa85e8ef1df6d0c48362621ad90c581e59654e9482ab94f5a32821563ee80291a510750d967e14031f75b7a2b59ffd96441652e2abd61	\\x287369672d76616c200a2028727361200a2020287320233531434139313846354430313535463042434538354143343644413132344644303042343634383637413532324131334133303746304638413439333941453039373231364638343634453031394637314633363135464544303035323439313932303334303738363131423032443746374234433931384539324134373436363032463745453439353438383039353443324541383741373045413734453939384231454139394342453731374445353433343543374634303844344541353945353135343446384244354332453734383642463041334136314338344646463436333132433338424639374635394145384434373546333643344132453623290a2020290a20290a
\.


--
-- Data for Name: kyc_events; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.kyc_events (merchant_serial_id, amount_val, amount_frac, "timestamp") FROM stdin;
\.


--
-- Data for Name: kyc_merchants; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.kyc_merchants (merchant_serial_id, kyc_checked, payto_url, general_id) FROM stdin;
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
2019.234.15.01.40-0345FW3SWCNZG	\\x9d3c6c0d0d865d3758900dea5161d1efbb6ad0363b87abd2a41918e876b197eb	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233342e31352e30312e34302d303334354657335357434e5a47222c2274696d657374616d70223a222f446174652831353636343738393030292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636353635333030292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22424a37505736354b35544a395238533354454b5a354332454738563545564651324d54483638424e5134444d3038333754585930227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22305459363833504259375239504146465637514e5a59325154414a535751344a31324e3457455446424b305a44415041475647575a5a4a4250504d473234324d413651323831384d4335504e353557544733344756594a4a564a3139385a474b56584550334b38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224b4d5936523338444753454b4550344731514e3532524548585958504e4d315037453354514d4e343334434547584e484a5a4e47222c226e6f6e6365223a22514d574b37415742574331585246484d543748334452535831345641434b474d594e54314a4743593643474b4136595751384147227d	\\xc183fd5784280ae9669db4e5700021e6a982696e2f4269fa20175c642212f3a51bb4f426b98801bb4e3377617a772f5aa9ae4071052a84e4d6ba2b429b72c2b4	1566478900000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xc183fd5784280ae9669db4e5700021e6a982696e2f4269fa20175c642212f3a51bb4f426b98801bb4e3377617a772f5aa9ae4071052a84e4d6ba2b429b72c2b4	\\x9d3c6c0d0d865d3758900dea5161d1efbb6ad0363b87abd2a41918e876b197eb	\\x9aa5deca35934acc08e762ec55f7a11243f998ff8c8c3cb499a97957f94ebdf0	http://localhost:8081/	5	0	0	0	0	0	0	1000000	\\x8ddbc7b38f4e93b387b6598a4ddf160b6617039d3e326e84692db0ad425c3db5	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a224b365154444e5a36594d3751585853504156454a4d575a3434594753434e34384d474d4134355a36454d4e58414b33504434354850303959503751463838584b4136395734585a3531454d3058535830424d57354753444646524130444358434a593252503152222c22707562223a2248514457464357463954395637315850423635345651525031444b314530575837525336583133393550524154474a5737505447227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.234.15.01.40-0345FW3SWCNZG	\\x9d3c6c0d0d865d3758900dea5161d1efbb6ad0363b87abd2a41918e876b197eb	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233342e31352e30312e34302d303334354657335357434e5a47222c2274696d657374616d70223a222f446174652831353636343738393030292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636353635333030292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22424a37505736354b35544a395238533354454b5a354332454738563545564651324d54483638424e5134444d3038333754585930227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a22305459363833504259375239504146465637514e5a59325154414a535751344a31324e3457455446424b305a44415041475647575a5a4a4250504d473234324d413651323831384d4335504e353557544733344756594a4a564a3139385a474b56584550334b38222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a224b4d5936523338444753454b4550344731514e3532524548585958504e4d315037453354514d4e343334434547584e484a5a4e47227d	1566478900000000
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
\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	payto://x-taler-bank/bank.test.taler.net/396	10	0	1568895815000000	1568895815000000
\\xe6dacd272de8282c0b32344101c61815e3921c4564cc346a991918b21904cedd	payto://x-taler-bank/bank.test.taler.net/395	10	0	1568895620000000	1568895620000000
\\x66ec99ef569ba5b8262b5451943f743d82db4d46d850f56295229bc941e06d0c	payto://x-taler-bank/bank.test.taler.net/394	10	0	1568895335000000	1568895335000000
\\x5a4622282f4ca44630980efeb12cbb2a8c3c46daa0d676186ccdad1103910954	payto://x-taler-bank/bank.test.taler.net/393	10	0	1568895214000000	1568895214000000
\\x1c18ce673522c676d133d3fd38fc525c06f9139256f97733392aa476b38da935	payto://x-taler-bank/bank.test.taler.net/392	10	0	1568894477000000	1568894477000000
\\x4d93a5159d2a5bd6910267a91c3111ac495329410097a1adcf772d3a240df2bb	payto://x-taler-bank/bank.test.taler.net/391	10	0	1568846228000000	1568846228000000
\\xbd46bfe36609883ca276710aa7446bdf49d7a03f005472630e50a0784a53a741	payto://x-taler-bank/bank.test.taler.net/390	10	0	1568846206000000	1568846206000000
\\x2dbb53c2f3627f50b18ec54e15246c7b5f81a15683f53a7177029814f8da8bc2	payto://x-taler-bank/bank.test.taler.net/389	10	0	1568824576000000	1568824576000000
\\x1f4681908ed2f225632346cc1e3b4988ce8fa6c1c8ab179f978b3bcff3c21bf1	payto://x-taler-bank/bank.test.taler.net/388	10	0	1568824226000000	1568824226000000
\\x688b922cfa19931ba3d9030b747bdc2da9716aac4e53f21a15c5988456915581	payto://x-taler-bank/bank.test.taler.net/387	10	0	1568824145000000	1568824145000000
\\x012e41df79ff63a8f39d2817a86bbc0e60f14e70440fbab3c234fc4a8d05d439	payto://x-taler-bank/bank.test.taler.net/386	10	0	1568816698000000	1568816698000000
\\x6c3a52338741d0f462f571f42daf5be81b7a945da9ad871cc9f58ddd700193aa	payto://x-taler-bank/bank.test.taler.net/385	10	0	1568813452000000	1568813452000000
\\xc8e442c5c85ef054a27974ba39c3745c9d017f4bf8e52768c5e8669ba8583e66	payto://x-taler-bank/bank.test.taler.net/384	10	0	1568813422000000	1568813422000000
\\xc9675953172121e16dab952fc11a250245a5682fc6c5cb921cbe1753869d3299	payto://x-taler-bank/bank.test.taler.net/383	10	0	1568813158000000	1568813158000000
\\xc37168aec489a6472db4efc0a85feeb19f6c8cdf1de3723945bba9bd8a7fb634	payto://x-taler-bank/bank.test.taler.net/382	10	0	1568812543000000	1568812543000000
\\x0a26d1acfe138d947700857a157a007c0f8b44cb2cd5387c4e4ba1dc21603e6c	payto://x-taler-bank/bank.test.taler.net/381	10	0	1568812517000000	1568812517000000
\\xc7624530ea124cca7e8661163d6b4016d2a4252b63c901a77a9d1771245da8f9	payto://x-taler-bank/bank.test.taler.net/380	10	0	1568811877000000	1568811877000000
\\xb71c07fdff675806af9e20022b7bf5ec0ec16f0892d3b866436f659da502a25f	payto://x-taler-bank/bank.test.taler.net/379	10	0	1568811745000000	1568811745000000
\\xc8f38a375831272de806e769f96d6c4c142b9c249a5110eb26c35117f69014a3	payto://x-taler-bank/bank.test.taler.net/378	10	0	1568808452000000	1568808452000000
\\xe67cf6c190418a44ff772b5af0075de9f50ecb27d168c907837528575531a747	payto://x-taler-bank/bank.test.taler.net/377	10	0	1568808378000000	1568808378000000
\\x74a4f75e0092c7f48bacfcdc2b3eac5fa93c61548b0bdd053e0bfbb741d9af51	payto://x-taler-bank/bank.test.taler.net/376	10	0	1568806348000000	1568806348000000
\\x62ce130deab667ded5da342d4a7c8a48259c5464e4c11f9a41a155622f736d8a	payto://x-taler-bank/bank.test.taler.net/375	10	0	1568806014000000	1568806014000000
\\x53339a2bc10f6d6dc9f3c275269fab85e67ea25dc2853d5c25898ed41d51331e	payto://x-taler-bank/bank.test.taler.net/374	10	0	1568805562000000	1568805562000000
\\xb2f0675021b8b2b2c82a33d7de06a6188014ef6f641ec1f63b98574adc4a5a79	payto://x-taler-bank/bank.test.taler.net/373	10	0	1568805471000000	1568805471000000
\\x64de8ad09221295cda8823d29797b5335c3c40efd0111a20134fef96bbd9ac9a	payto://x-taler-bank/bank.test.taler.net/372	10	0	1568805285000000	1568805285000000
\\x7140831bef79c6208bca40a3b926a8045cc19cd504f0502261d8d8c5872c9de9	payto://x-taler-bank/bank.test.taler.net/371	10	0	1568805095000000	1568805095000000
\\xe3c38f7f9a1f808655c624f450bd9e1d084ac6448d9f42fbe56dc99c017b176e	payto://x-taler-bank/bank.test.taler.net/370	10	0	1568805033000000	1568805033000000
\\xfc13820602150f5b065d5e8c34ad9c01b28403af35f155bf471c478399382725	payto://x-taler-bank/bank.test.taler.net/369	10	0	1568796092000000	1568796092000000
\\x5d7b8eea903cbe3c4926db1c8c8cce69482ecbc196bd65813388ce3237d77f56	payto://x-taler-bank/bank.test.taler.net/368	10	0	1568795992000000	1568795992000000
\\x77e1ae7a8bfaadc974396088d2fd22fee5398df641a7c3dba0760765875cf6b5	payto://x-taler-bank/bank.test.taler.net/367	10	0	1568792649000000	1568792649000000
\\xdd6e5ecaad109e27520aacc88c39cc4830235f280e8bd11779f38ebee15b237f	payto://x-taler-bank/bank.test.taler.net/366	10	0	1568753032000000	1568753032000000
\\xc856b9453e72fc92eeecf9614cba6acfdfb67a39d1f1017b59803ec0f8f5f8ad	payto://x-taler-bank/bank.test.taler.net/365	10	0	1568752992000000	1568752992000000
\\x119efdc91109466f9d6c8bcf33f956d0046b01380ce66b44ebc3a2902d827d89	payto://x-taler-bank/bank.test.taler.net/364	10	0	1568752884000000	1568752884000000
\\x38cc57b994cf977e00c6c4c25357796e9c2d79b44ce890ce49925cdc6c3d54ac	payto://x-taler-bank/bank.test.taler.net/363	10	0	1568751641000000	1568751641000000
\\x0f352c26485d153ab1654b49a06dc5a47a0b4a14bf4a42cb4cbd18b87fb07374	payto://x-taler-bank/bank.test.taler.net/362	10	0	1568751004000000	1568751004000000
\\xa2f9f8326db9d373b252fcc3a0401bc85b3e97618dc3a432487ef38cd9a6517a	payto://x-taler-bank/bank.test.taler.net/361	10	0	1568749661000000	1568749661000000
\\x46e452f1184d8f6d218534b68b79b8cf6143f1ebaf118a9773546aa200996955	payto://x-taler-bank/bank.test.taler.net/360	10	0	1568749520000000	1568749520000000
\\x47dbd1fbb39cee3d39c117e376c472fa0d0fc6fceccd5f5e978bace5a6af0ab0	payto://x-taler-bank/bank.test.taler.net/359	10	0	1568749286000000	1568749286000000
\\x5941c4d722de161c804086ea30952008b7dd1a6aaf10ef708e2fa122102bae7b	payto://x-taler-bank/bank.test.taler.net/358	10	0	1568748429000000	1568748429000000
\\x051cbec08070f5a75e6de51d35e1aeb7b01a36036a141d2066181092d1d39b11	payto://x-taler-bank/bank.test.taler.net/357	10	0	1568747795000000	1568747795000000
\\x69cff834caa39abbb70820d036158ce6cd3a7f99cb8cec263337660b7383bcee	payto://x-taler-bank/bank.test.taler.net/356	10	0	1568745690000000	1568745690000000
\\x6874b7482af6d0ad81a6d31e6fd08c7ab18503c28e053bda598bfd0acb180c7e	payto://x-taler-bank/bank.test.taler.net/355	10	0	1568745385000000	1568745385000000
\\xdeaaddb0ca6611d9ed384e3b729028fcc22d2fa5764e3843aad3172958ef79d3	payto://x-taler-bank/bank.test.taler.net/354	10	0	1568745018000000	1568745018000000
\\xcbeb4efeee8f755ad46a4cbbe367284d0a31e8355b703eaf3c62a90c25bb6815	payto://x-taler-bank/bank.test.taler.net/353	10	0	1568739569000000	1568739569000000
\\xa044250c7644a8664c2d7dd4f4146946c7d7a74cc9d3c72f24861cca285e515e	payto://x-taler-bank/bank.test.taler.net/352	10	0	1568735421000000	1568735421000000
\\x9ad482c0b94c3fe5403c0093d5609a77e459422795cc0ad7b091f6a28039c281	payto://x-taler-bank/bank.test.taler.net/351	10	0	1568735262000000	1568735262000000
\\x06f725b34ff44ea72a88e0d72d9c754462176850b63841e5ac62eeaa0107da8e	payto://x-taler-bank/bank.test.taler.net/350	10	0	1568732644000000	1568732644000000
\\x4aba78fd0c360bd6bdfb1be8c0033adc09d669e7363ff4f75c7addbead866087	payto://x-taler-bank/bank.test.taler.net/349	10	0	1568731335000000	1568731335000000
\\x003756a82312c1f165d22735a4d91a0931970335d69739be893422b3630bd5df	payto://x-taler-bank/bank.test.taler.net/348	10	0	1568731249000000	1568731249000000
\\x7274923e113464192d274534a3b8dd38572393cf8b6b9a26973ce0c657f830fd	payto://x-taler-bank/bank.test.taler.net/347	10	0	1568719297000000	1568719297000000
\\xb353ec37ab0e6c7b624ae1779404f65f4b7c3dc601a72ca2e0d7f23633946144	payto://x-taler-bank/bank.test.taler.net/346	10	0	1568719279000000	1568719279000000
\\xf6157d960f7b08f4ecd45e8f856090fcb22e069858394a4e7fc97488a88852a5	payto://x-taler-bank/bank.test.taler.net/345	10	0	1568719269000000	1568719269000000
\\x14a56bea0d1606f7636eb8ddcbbfcd8a9479130b22589f154e37ee1575842e1e	payto://x-taler-bank/bank.test.taler.net/344	10	0	1568717156000000	1568717156000000
\\x3eceb3f3a13e966853b828a49921188a0305ccfc88be178f2a76a7e210f174ec	payto://x-taler-bank/bank.test.taler.net/343	10	0	1568717147000000	1568717147000000
\\xf939b9ad110e76af9ee82c5924c812709f610e73f651a120b7b93a35ad8a9462	payto://x-taler-bank/bank.test.taler.net/342	10	0	1568717133000000	1568717133000000
\\xfefdc664b156a8956c22392708056f7771beb50eef224383e7be4e7178a6a8bb	payto://x-taler-bank/bank.test.taler.net/341	10	0	1568717122000000	1568717122000000
\\x0e2d0beab43b0b4fd20157e8b373f21b1fee2a513ebe0fcd18464bfe22889272	payto://x-taler-bank/bank.test.taler.net/340	10	0	1568716930000000	1568716930000000
\\x0425ba60520bbc67ea59dd44fdac94d44aec328d4a504f9a96cd7115d2d7718b	payto://x-taler-bank/bank.test.taler.net/339	10	0	1568716801000000	1568716801000000
\\x6e9d183ab868e7ff9d40138dd763896cb8ee9b230e2de94f73b0d788b738f8a4	payto://x-taler-bank/bank.test.taler.net/338	10	0	1568664673000000	1568664673000000
\\x813db9bd108f103f010eee5c9347a0f8d36da0076ecdfc2aef7e02d643234196	payto://x-taler-bank/bank.test.taler.net/337	10	0	1568664673000000	1568664673000000
\\x59c56af7431f2115a0c22aa89892d170a9a9471db5014e8a824fbc19dcc2d843	payto://x-taler-bank/bank.test.taler.net/335	10	0	1568664673000000	1568664673000000
\\x53d4ea53beca2041bb9b7885f1bf52fbac6b87c44ee7c27b8d5e9eb6d17cc0e5	payto://x-taler-bank/bank.test.taler.net/336	10	0	1568664673000000	1568664673000000
\\xfe59643d79bcc5ecf39a4fda8016c47fd7c8c3635f1bba0a7f6e0c13c134a4b8	payto://x-taler-bank/bank.test.taler.net/334	10	0	1568664672000000	1568664672000000
\\xccc34040dbcf81f0f68cf8c23a5c381c48a8819bf7f0f2d83b24c409023361e6	payto://x-taler-bank/bank.test.taler.net/333	10	0	1568664261000000	1568664261000000
\\x9abf75e6216b8039d914aa14b8c6ef77952b49f8f4b25cc29ee0a6e0cacbfc70	payto://x-taler-bank/bank.test.taler.net/332	10	0	1568664206000000	1568664206000000
\\x76c21837710c2e390b9fe23674f581e87e07ce96e4972c1af82ec1a0847ae95d	payto://x-taler-bank/bank.test.taler.net/331	10	0	1568664157000000	1568664157000000
\\xc725d349c67fd479c2c512e29e33055753da64877d33335fb1b2432e7a32d999	payto://x-taler-bank/bank.test.taler.net/330	10	0	1568664150000000	1568664150000000
\\x2af399b74d0691fb36c2e2b6c00631694b51607c332fd97f29a8d4ecca5c7ef6	payto://x-taler-bank/bank.test.taler.net/329	10	0	1568663224000000	1568663224000000
\\xd58aa182bdc6b8f4463bf392e0bb003325bfb653ad7c18f32d39e38fd20e7ed0	payto://x-taler-bank/bank.test.taler.net/328	10	0	1568662769000000	1568662769000000
\\xe7ac2051b945e977cdb2a613d4434c04c26dd3b102a1bc82d29d08a81ae86b2b	payto://x-taler-bank/bank.test.taler.net/327	10	0	1568662739000000	1568662739000000
\\x2f45b07e937fd0a1feb3d9fcc7aa6c149a96e84338fa251f53f148ceca4b96d5	payto://x-taler-bank/bank.test.taler.net/326	10	0	1568662521000000	1568662521000000
\\x204f1f80cd9e66810bbf74e58cb1838d904ee5941ed205aba33bf9f1e236e49d	payto://x-taler-bank/bank.test.taler.net/325	10	0	1568662509000000	1568662509000000
\\xdb41e9f1ad98bb9bf42c952b770c69c4019fa6c4524f77f92cb4189e96bca115	payto://x-taler-bank/bank.test.taler.net/324	10	0	1568662000000000	1568662000000000
\\x30fba371e70b4ebc0a40f952c43d50d18719b36d310b891059808ea5a21c3710	payto://x-taler-bank/bank.test.taler.net/323	10	0	1568661988000000	1568661988000000
\\x26bd0786ce312f0aec4cc46d8c2a0368974f065f61ecc345c713aa0fc8fa5c2a	payto://x-taler-bank/bank.test.taler.net/322	10	0	1568661972000000	1568661972000000
\\x3e6809817ca4477f5ec4ac74c0bbb76e48448176043a2cb456b0dc455a79632f	payto://x-taler-bank/bank.test.taler.net/321	10	0	1568661948000000	1568661948000000
\\x5a374956e5ff8785db62f4deccdc41d65aad3bb1927344122447acc016aa44f9	payto://x-taler-bank/bank.test.taler.net/320	10	0	1568661856000000	1568661856000000
\\xc3c6006069c05603856ac9e6bf25192f6684467721b96350bdfabc8008bbec9d	payto://x-taler-bank/bank.test.taler.net/319	10	0	1568661738000000	1568661738000000
\\xa5d0664f9f0fdfb4407c6e90712d57e98e824dc1bbc75c79620f68f97d8fd5ca	payto://x-taler-bank/bank.test.taler.net/318	10	0	1568661596000000	1568661596000000
\\x7039453d2727338652a5432ffca59220fe15ebb3e09399d238215311f015107d	payto://x-taler-bank/bank.test.taler.net/317	10	0	1568661538000000	1568661538000000
\\x3428bcdcd2725e6038bba0d5e3189f3caf0c342d55a25d02be539d6ab97cc20c	payto://x-taler-bank/bank.test.taler.net/316	10	0	1568660494000000	1568660494000000
\\x22c98e04feee74f42fba4ab3f00627a118c4d8279df397776bb785903e07ab1e	payto://x-taler-bank/bank.test.taler.net/315	10	0	1568659836000000	1568659836000000
\\x59998f08f6e8f35ea10c51c5700aae79b9f6d6b5f684a377a7f5b2fa6a64a269	payto://x-taler-bank/bank.test.taler.net/314	10	0	1568659436000000	1568659436000000
\\x10dd95f3a5de768b7690839be29f2d8974b0654d13f20b5f7437d768d14f51bc	payto://x-taler-bank/bank.test.taler.net/313	10	0	1568659359000000	1568659359000000
\\x87a6b79a88d73b92f7169010d401421224a6a24b67f40471c4a4761cc0f0bfb2	payto://x-taler-bank/bank.test.taler.net/312	10	0	1568659237000000	1568659237000000
\\x33396f85d648a84af67f09d35532751fa8d90e22b218d0798bd444b12ddac3a2	payto://x-taler-bank/bank.test.taler.net/311	10	0	1568658508000000	1568658508000000
\\x91837011a5b129b2a1ecdaf92cf0fe157479e26044f16705f06aab77c7157879	payto://x-taler-bank/bank.test.taler.net/310	10	0	1568658453000000	1568658453000000
\\x789a55c8a99464a9a7c9c3640e917aa0b4ee760cd49850b1c2c0173480e1486d	payto://x-taler-bank/bank.test.taler.net/309	10	0	1568658210000000	1568658210000000
\\xed4538ca12e87d07f8a036054059c92f875b1fdf5f5cbe12a0dd8c72efc0ef1b	payto://x-taler-bank/bank.test.taler.net/308	10	0	1568658180000000	1568658180000000
\\x1c524fbbb8045eaff17a3935d67f85234f342c943933fb1a0e827f99330bcf05	payto://x-taler-bank/bank.test.taler.net/307	10	0	1568658113000000	1568658113000000
\\x29bb82bedb668a22791007266113a81977b54d9524bfb195812eb4637f449d1d	payto://x-taler-bank/bank.test.taler.net/306	10	0	1568658097000000	1568658097000000
\\xcd9a6ca7e8cf43aabcf1b7e3403139c2ac1d990f78334360d326660ceec8df15	payto://x-taler-bank/bank.test.taler.net/305	10	0	1568657983000000	1568657983000000
\\xbaf74548c792dea461ca5aaf83a69b3a7c9c220a910ab45c286a1ae7df7f1d77	payto://x-taler-bank/bank.test.taler.net/304	10	0	1568657256000000	1568657256000000
\\x7e63f67c1940a9b23d13697aa6582a1fe69581bbd2f1c5098cd3561a989eba3a	payto://x-taler-bank/bank.test.taler.net/303	10	0	1568655719000000	1568655719000000
\\x59bfd4e6dbaa2dfdb58244208e88533a7849ceb3e3e235e427d516ccd69ac5fc	payto://x-taler-bank/bank.test.taler.net/302	10	0	1568655271000000	1568655271000000
\\x268c99db0a689c8fe3544e83745f2c5e3d476ae6e6abe8b62babdcdc62208ee1	payto://x-taler-bank/bank.test.taler.net/301	10	0	1568652065000000	1568652065000000
\\xe7e3ffe3752203bbfa38003e5c6ea51c395c2aa4056b258461f0b24dfbc5a773	payto://x-taler-bank/bank.test.taler.net/300	10	0	1568652002000000	1568652002000000
\\x3b34626e4bd1d6a90a17685dffa13b1de5eaaaefee9dff5b62531b6f9c2b25cb	payto://x-taler-bank/bank.test.taler.net/299	10	0	1568651351000000	1568651351000000
\\x1c50880a086245f96b09dbc9262696d31570b359e9aa847c62dc724e1bbc3904	payto://x-taler-bank/bank.test.taler.net/298	10	0	1568631492000000	1568631492000000
\\xe532b4eaa3a651af35fe482844cf4ee58d9933594e1d07348db46d507d44d136	payto://x-taler-bank/bank.test.taler.net/297	10	0	1568630992000000	1568630992000000
\\xa9508cf654f874b6ac7c137c67a34daadd7566c01452359b0c1974fd866c88a9	payto://x-taler-bank/bank.test.taler.net/296	10	0	1568581997000000	1568581997000000
\\xb6dd4e754c04f7f454fc76eeea421a02db0ab80cadd6e095913aa6a467d08df8	payto://x-taler-bank/bank.test.taler.net/295	10	0	1568581522000000	1568581522000000
\\xc484befd64ce803855834b06e849343331d654f98d2c681c28ae2547533afb07	payto://x-taler-bank/bank.test.taler.net/294	10	0	1568581399000000	1568581399000000
\\x9222bf7c3c95fb9eda6f228d44573407bfbd4c440351830f2d770ac84ab44e36	payto://x-taler-bank/bank.test.taler.net/293	10	0	1568581383000000	1568581383000000
\\x9c377c7a5181ac3a9cd7609eea358428156380615afc3730f87bee265213a756	payto://x-taler-bank/bank.test.taler.net/292	10	0	1568580908000000	1568580908000000
\\xb800e06c8b550082d031a22fde02d8654c27fc7e778c33ab8296349365f72347	payto://x-taler-bank/bank.test.taler.net/291	10	0	1568580857000000	1568580857000000
\\xe57325eea480ac0c9b3434a30b1952ba7deac6d00106b6b9974878edcdf40e7e	payto://x-taler-bank/bank.test.taler.net/290	10	0	1568580734000000	1568580734000000
\\x406b9add395d06468c5828d686b1e78e58f7b6972a25201f452626a4f7dd7d7a	payto://x-taler-bank/bank.test.taler.net/289	10	0	1568580673000000	1568580673000000
\\x89470dee4c3110f9cdc4b7f851b003d1de5417379f473bbdb57454e1997c0a0c	payto://x-taler-bank/bank.test.taler.net/287	10	0	1568580489000000	1568580489000000
\\xda46933e2a492f1c30d56d18176082a5bfb1b9b073abd0cce747f5111137a8b1	payto://x-taler-bank/bank.test.taler.net/286	10	0	1568580423000000	1568580423000000
\\x4c7d9dde23ca42d415f01730f0b19c4ac60560c40095652048b08d2633aa2810	payto://x-taler-bank/bank.test.taler.net/285	10	0	1568580405000000	1568580405000000
\\x5e293aeb6c08a5bcbb1e61df798220451f07f36d00affaa9190775a5f7180caa	payto://x-taler-bank/bank.test.taler.net/284	10	0	1568580055000000	1568580055000000
\\xefe525ec2968cd6845b8c92b02a73c0a0af9af88de003d82ca12deb9e22e9dc0	payto://x-taler-bank/bank.test.taler.net/283	10	0	1568579703000000	1568579703000000
\\xaa87f84bcc4744d63b96cff8436a5f88405dfb5f22a39fd9f9552e8633de9942	payto://x-taler-bank/bank.test.taler.net/282	10	0	1568579523000000	1568579523000000
\\x6ded4375cd71b389104b9096226a89fa1a1846cb7af324842e4a62ca4f32072d	payto://x-taler-bank/bank.test.taler.net/281	10	0	1568579471000000	1568579471000000
\\x1b0e3b898562b405d5989b3617178871f6a0e73f1ca2ade7c293ed29ad760c72	payto://x-taler-bank/bank.test.taler.net/280	10	0	1568578478000000	1568578478000000
\\xd7a6cb733790839a79bed1e9d2ee4b7d8fd66ae70f1645c84edbc535b0d77e33	payto://x-taler-bank/bank.test.taler.net/279	10	0	1568578363000000	1568578363000000
\\xad658d529cb575c0d1d025056f724ad59c2f0efadfc052d4300d4066669f5f20	payto://x-taler-bank/bank.test.taler.net/278	10	0	1568576890000000	1568576890000000
\\xe0b3f02bf670cd068c2483b252c2a47ca204d46b6821ea94f58444345d2004c7	payto://x-taler-bank/bank.test.taler.net/277	10	0	1568571813000000	1568571813000000
\\x66af8e219c20e49afe73128b8687a39e0b8a36f6ce79286714c058e0efdd9669	payto://x-taler-bank/bank.test.taler.net/276	10	0	1568571722000000	1568571722000000
\\x7a218bdf8b9e773794613b3db323fcc95867819c59e24726f7dcf4a13be842d9	payto://x-taler-bank/bank.test.taler.net/275	10	0	1568569242000000	1568569242000000
\\x33453afe5db166f0aa10e4acda686dba022990a845753f3d6d06a61b24cd46a5	payto://x-taler-bank/bank.test.taler.net/274	10	0	1568569167000000	1568569167000000
\\x6b7cede5ceb81248262a13b1d86f2d3b392c18e0c93788fecb5284917523a57d	payto://x-taler-bank/bank.test.taler.net/273	10	0	1568569130000000	1568569130000000
\\xb9d4fdfed4243cf830cebc3195b0d2659649d8a8b4aa885301f83410ae0024e4	payto://x-taler-bank/bank.test.taler.net/271	10	0	1568569059000000	1568569059000000
\\xd5da4a1a66b10dc4e12ab7461fe65023ee0ab2bacbef8fff13a0c0a1de15b66d	payto://x-taler-bank/bank.test.taler.net/270	10	0	1568558061000000	1568558061000000
\\x3af59e0132735e05e27b112d6392ee58a11489cf568bbb5c25bb595405521ff3	payto://x-taler-bank/bank.test.taler.net/269	10	0	1568557887000000	1568557887000000
\\x469bf9c86abb396de1863568f5789599dc6a439450f3f1905f6212bad9f4df9a	payto://x-taler-bank/bank.test.taler.net/268	10	0	1568557765000000	1568557765000000
\\xa5b58e2c15151cc21b2a6d64a01f9358d6c0850067a34f9162351ecac4a57222	payto://x-taler-bank/bank.test.taler.net/267	10	0	1568557594000000	1568557594000000
\\x271ee8933b0258c5551dcdc999da5b708b36ed97dad53800c45bc72d49a39cd7	payto://x-taler-bank/bank.test.taler.net/266	10	0	1568557413000000	1568557413000000
\\x0ccff4d54e80cb3dd68f6e916973508e77051caaae735dd03bc306cfe0afae74	payto://x-taler-bank/bank.test.taler.net/265	10	0	1568557273000000	1568557273000000
\\x6363234157eab234dc540d977e06cf6681bae43e7d2d87beed4739c08f6377c6	payto://x-taler-bank/bank.test.taler.net/264	10	0	1568557141000000	1568557141000000
\\x294eb33578c0dd1135de2b6cc411cd59881a9add9f786995118673899e9c3e87	payto://x-taler-bank/bank.test.taler.net/263	10	0	1568556944000000	1568556944000000
\\xa9d62c09b31f66606af346d0c7e64f77a92954a999e50ffcf574a217e8cb31e4	payto://x-taler-bank/bank.test.taler.net/262	10	0	1568556574000000	1568556574000000
\\xe4d05ad2b0b5e27f3695806e468d54592cd5405e281485196ffa234e63fc68cb	payto://x-taler-bank/bank.test.taler.net/261	10	0	1568556357000000	1568556357000000
\\xf0fda0cd3dda1d31a598c5b9e850a7c54456f8c482af6c1f70b380fd3a659c46	payto://x-taler-bank/bank.test.taler.net/260	10	0	1568556148000000	1568556148000000
\\x695a2de3e0bfdee784b2409b58d18e069f55768745622205a4cb2a99016d976e	payto://x-taler-bank/bank.test.taler.net/259	10	0	1568556033000000	1568556033000000
\\x59ba84ccb16e2a8c0197ae704c9805452d9f91203f0e2a2414865fb43b11b60d	payto://x-taler-bank/bank.test.taler.net/258	10	0	1568555782000000	1568555782000000
\\xf7afb294f813be7682bda81a109f8cebc21c7dde782f897359ce3c4503a915f3	payto://x-taler-bank/bank.test.taler.net/257	10	0	1568554537000000	1568554537000000
\\xa242dcf952f7a0284907e66479db7510f74fff91ce0c318c69e30cc42ac22b28	payto://x-taler-bank/bank.test.taler.net/256	10	0	1568554208000000	1568554208000000
\\xa46479979b59dac9665291fe8c99f56fafd020ab6378518b24a7de4162c0a8fe	payto://x-taler-bank/bank.test.taler.net/255	10	0	1568552868000000	1568552868000000
\\x9307406b793081d213b291e1220b05afa8f8dbe8f0a297729a78228d7b4f5363	payto://x-taler-bank/bank.test.taler.net/254	10	0	1568552853000000	1568552853000000
\\x935c559fcf339b66ea197098e4a7165a373cada72ce6326c6649f21bb2b6958a	payto://x-taler-bank/bank.test.taler.net/252	10	0	1568481483000000	1568481483000000
\\x44884e596728d1764a441c476b6d1600f4e172b82224579a7a9c96d0264db3f3	payto://x-taler-bank/bank.test.taler.net/251	10	0	1568480381000000	1568480381000000
\\xa47e3ec298a912ce770d6f76505ab6bad3bc4f43012ea0a7d02018359ced5e77	payto://x-taler-bank/bank.test.taler.net/247	10	0	1568479255000000	1568479255000000
\\xec426b2ba4cd2036d645ace13c17ec24d034c47123f9b7259b19bddd75bbc282	payto://x-taler-bank/bank.test.taler.net/246	10	0	1568479249000000	1568479249000000
\\xfa6430afd028e2230004a93f5f989f716b04f07f22075c0f71f0de7fb885556d	payto://x-taler-bank/bank.test.taler.net/245	10	0	1568479236000000	1568479236000000
\\x59d46300018a3020106c7635630a580763c94359e41bb30381a5234ffb259462	payto://x-taler-bank/bank.test.taler.net/243	10	0	1568468829000000	1568468829000000
\\x3735705df5fdb4391e2c7308b6efd8aefb2cd17feed80c7d7409b062c4a7020b	payto://x-taler-bank/bank.test.taler.net/241	10	0	1568468789000000	1568468789000000
\\xb7c7fa0443475b8a8f7612bfeb862c3e27c75ef08c2ed9f4ee524e95ba215155	payto://x-taler-bank/bank.test.taler.net/240	10	0	1568468175000000	1568468175000000
\\xe5021623374e4f73a1021b432393316a64b9ff7d8a55b08fa4889bc3ea14cd5a	payto://x-taler-bank/bank.test.taler.net/239	10	0	1568463641000000	1568463641000000
\\x9c9aee06fecf3caa3de9173ae0afb78a3df2361f4a1c98bbaa2fa124dc774d3b	payto://x-taler-bank/bank.test.taler.net/238	10	0	1568418685000000	1568418685000000
\\x0f44803fb16fff27d5b00d0ff093c089dc7671feef732783d98b6057c78795ee	payto://x-taler-bank/bank.test.taler.net/237	10	0	1568418677000000	1568418677000000
\\xcb5d2f41dae0505e076d87da9c209b574708290b94ee53eb7c58b719ff9f8e4c	payto://x-taler-bank/bank.test.taler.net/236	10	0	1568418660000000	1568418660000000
\\xd66e178d92b2c62fec79634fb20a21c5700507111b36bde3a838a9e6afdcd962	payto://x-taler-bank/bank.test.taler.net/235	10	0	1568418560000000	1568418560000000
\\xd0afe6a042bd0d72502690e9b60cc521f101fe75eb854595e3679b3ff1d1f913	payto://x-taler-bank/bank.test.taler.net/234	10	0	1568418554000000	1568418554000000
\\x5180d87442313b7237f1be51fb363524f197ee48e304d04b33f4f46aec114410	payto://x-taler-bank/bank.test.taler.net/233	10	0	1568418501000000	1568418501000000
\\x6189f786c04b5e735b639da1779c9806f86c4dd9324d92cb9ef9dbc6fc515b7b	payto://x-taler-bank/bank.test.taler.net/232	10	0	1568418483000000	1568418483000000
\\x866ec7f2b2123ead9e3500c0ff1f83e386f392c49e2f163ffe697ffd41e0f90d	payto://x-taler-bank/bank.test.taler.net/231	10	0	1568418476000000	1568418476000000
\\x99ecea1c2119254d96d98ef43424b4cbe314fb5bb440e838f6a8a140301bce6d	payto://x-taler-bank/bank.test.taler.net/230	10	0	1568418155000000	1568418155000000
\\x99fbc0d1d5729fd3f0b33736844196fff3d8d278053a60b9b27b47916c3ddd0d	payto://x-taler-bank/bank.test.taler.net/229	10	0	1568418110000000	1568418110000000
\\x5a385ed4779a13d58684098b70882788437bab11102b38ad277aef41baada706	payto://x-taler-bank/bank.test.taler.net/228	10	0	1568417863000000	1568417863000000
\\xb52d325f032b2791d504a532ef9834b033e8ef87eb597bc1a26aa89a2365d212	payto://x-taler-bank/bank.test.taler.net/227	10	0	1568417836000000	1568417836000000
\\x5b63460c0b825d0eaa613f1fca865184b48d04dc105437eb67a267109daf0f02	payto://x-taler-bank/bank.test.taler.net/226	10	0	1568417826000000	1568417826000000
\\x66b219ab9cd23f25e4a3d93fcc72bd87fed8ee4f85fefd13df14c8942018584f	payto://x-taler-bank/bank.test.taler.net/225	10	0	1568417704000000	1568417704000000
\\xbdac584b91a8b1e39cce9f2063853822e248b424f3e68d46af1c6763a7a8c77d	payto://x-taler-bank/bank.test.taler.net/224	10	0	1568417207000000	1568417207000000
\\x8cd98bc82b641ec56a1685ce5e308cf2657281fa219d6325a66221bb16fff090	payto://x-taler-bank/bank.test.taler.net/223	10	0	1568416910000000	1568416910000000
\\x82018291d5681e391d52e11f0fe99dd7af9ba088ef8a04703d47c39c1131661a	payto://x-taler-bank/bank.test.taler.net/222	10	0	1568416778000000	1568416778000000
\\xc77e537ef13fd7c51e61cef89d2022c16b0686ff1c55764969a96ee4c87a3052	payto://x-taler-bank/bank.test.taler.net/221	10	0	1568416490000000	1568416490000000
\\x1d76762600f8bd3f4795f62f03add0c65566e6688292c8646a6b5da12cacf1dc	payto://x-taler-bank/bank.test.taler.net/220	10	0	1568416347000000	1568416347000000
\\xfcfcdc8cd2791777397249d4c3da52e1863f55ad0c6882e2d751bbd405302095	payto://x-taler-bank/bank.test.taler.net/219	10	0	1568416330000000	1568416330000000
\\x3f619c26dc967addb49cae026b9f91709a030e15addc6ca6a5127e72cc930001	payto://x-taler-bank/bank.test.taler.net/218	10	0	1568416200000000	1568416200000000
\\xf5d83929494f27bfa0a816711d37f72cb65f822e8de11668fc52aebf6ce55682	payto://x-taler-bank/bank.test.taler.net/217	10	0	1568416175000000	1568416175000000
\\xa4d33108e549c5f07de36bb4d46529b1e368ace2ad4c34606eb1dfff199efd6d	payto://x-taler-bank/bank.test.taler.net/216	10	0	1568416170000000	1568416170000000
\\x7c002a0774ba18250483639e653c545867bd19c9a7e5e469f6867be5322a772b	payto://x-taler-bank/bank.test.taler.net/215	10	0	1568416163000000	1568416163000000
\\xb4de597a51faf7dba502d6b7d4d08809f423fe4e25218590e3fb05ccfc2824cd	payto://x-taler-bank/bank.test.taler.net/214	10	0	1568416159000000	1568416159000000
\\xf7719f9def9a2234ca81e166c0233b2468cbacd10b699d3cf61a6bd46c032a81	payto://x-taler-bank/bank.test.taler.net/213	10	0	1568416113000000	1568416113000000
\\x6bf8404ce889b919973f0dadfd10a1497e3fd6e794b7e64c6df8011a37511623	payto://x-taler-bank/bank.test.taler.net/212	10	0	1568416107000000	1568416107000000
\\x5608e9a6b49d5da56c6e306f6f35d37d71f5cd1f709a4ea4403ca1335b952dbb	payto://x-taler-bank/bank.test.taler.net/211	10	0	1568416095000000	1568416095000000
\\x093d02b628a9974e33fcf8a6d5fc6d74c70427960d524fd8674977d819163e72	payto://x-taler-bank/bank.test.taler.net/210	10	0	1568416086000000	1568416086000000
\\xbb61ab42b47a032fb8809a0fd1b2cd13f509c1e922863d9e84ac188bba2ba4a2	payto://x-taler-bank/bank.test.taler.net/209	10	0	1568416071000000	1568416071000000
\\x231459f058a65e3e280e888cec88737c2452fcdd1317322b92898372c8eee53f	payto://x-taler-bank/bank.test.taler.net/208	10	0	1568416067000000	1568416067000000
\\xb800dddd6ca1525b45937f3638762afba97df01c8fd68589b332cc6af8c17f6b	payto://x-taler-bank/bank.test.taler.net/207	10	0	1568415497000000	1568415497000000
\\x6edc8a322e33a069a0c0fe3ad6461c677dee1f9445deb38e243ce53bce2c5606	payto://x-taler-bank/bank.test.taler.net/206	10	0	1568414925000000	1568414925000000
\\x12fba7c03a70173a50b46399a5d848b0639b0c59f4465af5a923fecf0306356b	payto://x-taler-bank/bank.test.taler.net/205	10	0	1568411236000000	1568411236000000
\\x8b90d565724439977467feb78f95468ca325a6a583ec42eb9e528ed9ee67acfd	payto://x-taler-bank/bank.test.taler.net/204	10	0	1568406062000000	1568406062000000
\\x52b90c06be123b6979ec5d9ba1032013ce60a91dacddbecafee7302d9ce709b7	payto://x-taler-bank/bank.test.taler.net/203	10	0	1568400506000000	1568400506000000
\\x92077db0eb754e8074b64199e68906e04614d790042aed5d9cc84db1f80e8aca	payto://x-taler-bank/bank.test.taler.net/201	5	0	1568379510000000	1568379510000000
\\x31b91dbf4e89506f09d918dffa3a1800813f8e7fe1a7356c3a92681f62b9066f	payto://x-taler-bank/bank.test.taler.net/200	10	0	1568372128000000	1568372128000000
\\x6e846e63f3d4d2639febf8c3ef0bc3ff60acdb5d81de4d83e02d5ae36885a82b	payto://x-taler-bank/bank.test.taler.net/199	10	0	1568372022000000	1568372022000000
\\xd569191f67bff925e2e14f1a15e5392546b5bbc64ff1e7de72ad32c47a3959c0	payto://x-taler-bank/bank.test.taler.net/198	10	0	1568371849000000	1568371849000000
\\xefeeaed84eef3241f90f8713642986f5a806911a899d461f4c88e8b0af61ffe4	payto://x-taler-bank/bank.test.taler.net/197	10	0	1568371820000000	1568371820000000
\\xc1d651a7160f70ad594d9ee5cd188d42687fe99db4c41a61fe82633e626fa083	payto://x-taler-bank/bank.test.taler.net/196	10	0	1568371810000000	1568371810000000
\\xe57f5d46511d0e766c18a6ca9fc54d3283a2bb102eb8bfdf8e32266c74bcc241	payto://x-taler-bank/bank.test.taler.net/195	10	0	1568364092000000	1568364092000000
\\xf04ba9bc678428207d91776a9464b3b108b58c38fa268bc1b7a227eda49819e8	payto://x-taler-bank/bank.test.taler.net/194	10	0	1568364021000000	1568364021000000
\\xed16aa8942792639654d1f6023e09d1d650f2b8c93a63c1009efe130b00bb1ca	payto://x-taler-bank/bank.test.taler.net/193	10	0	1568360830000000	1568360830000000
\\x0a0d4eb5d1abbb8cea07fee2ba1ed90bd1ebc7e22daf4a368a03cb1ba3ace1ad	payto://x-taler-bank/bank.test.taler.net/192	10	0	1568359272000000	1568359272000000
\\xed3384e769e63bbb3a3b0e7e0d7a695c87cb83beb68a07aea69dbd28a02a00f0	payto://x-taler-bank/bank.test.taler.net/191	10	0	1568356583000000	1568356583000000
\\x6fceae6ef52dfe039f42c029ded6f5083158b76460d1a4415de2a13e0d6b141a	payto://x-taler-bank/bank.test.taler.net/190	10	0	1568354996000000	1568354996000000
\\xe079bd72ea08e0f54d38e00c0eebecf518d7e81b60d03082e929fdf76954aad4	payto://x-taler-bank/bank.test.taler.net/189	10	0	1568329346000000	1568329346000000
\\x9be84bc3757bc122966d499f582bb9f053dd837cffebec5317e28f0076820ac9	payto://x-taler-bank/bank.test.taler.net/188	10	0	1568328931000000	1568328931000000
\\x5e203725f5da7b3a43eb8c55bf3bc7674a8c9aaf19e5706516da2d337a623e83	payto://x-taler-bank/bank.test.taler.net/187	10	0	1568328925000000	1568328925000000
\\xf5d0a679138775b0bd2c7025d52533a4d3c663a2a8e790fbcbf1323c7038edea	payto://x-taler-bank/bank.test.taler.net/186	10	0	1568328866000000	1568328866000000
\\x352ca9fad07eb58ff536e649e5257e8153c2d6388f4b50caaf6464d8c312ffa5	payto://x-taler-bank/bank.test.taler.net/185	10	0	1568328797000000	1568328797000000
\\x2e199e3752fa0de89b8336f28ac07d39e835b663da6d875321332681524ef8b2	payto://x-taler-bank/bank.test.taler.net/184	10	0	1568328667000000	1568328667000000
\\x354145bcdd8f777d8f7450e7364e6546d3b5bb2b81e285ce342e2d57022acb5a	payto://x-taler-bank/bank.test.taler.net/183	10	0	1568328594000000	1568328594000000
\\xf8ad117b767116b4b6ecd1946e5c8258a9d0e26f10f5aeb83a2c96d9a4e801b5	payto://x-taler-bank/bank.test.taler.net/182	10	0	1568328286000000	1568328286000000
\\x2d841e2844b84613d06e1871ce1ff7c7aeb6e6272d643d95cf83b800d83f6fa5	payto://x-taler-bank/bank.test.taler.net/181	10	0	1568328249000000	1568328249000000
\\x099c38804d748d134f237668a8c22970981a1666cee497cab15a5b3761d95fe2	payto://x-taler-bank/bank.test.taler.net/180	10	0	1568326803000000	1568326803000000
\\x0534b703fcf4fb1bcc5c98894919ce8f6c647409c80ecb2f6784ea736f52a258	payto://x-taler-bank/bank.test.taler.net/179	10	0	1568326729000000	1568326729000000
\\x4ef3a8013f6c1fd371954afdf7db5831e2a4b08a24a46d47ce0d0fe71db27450	payto://x-taler-bank/bank.test.taler.net/178	10	0	1568326453000000	1568326453000000
\\x7e5c973417676e8adab516ab8ae8e867a929f1d5b49f19fa01cb129e1333557a	payto://x-taler-bank/bank.test.taler.net/177	10	0	1568325553000000	1568325553000000
\\xdaf21c4d7d0506e761794bfd54286da9cccfbd5dcffec91d4de685ddeb2d9874	payto://x-taler-bank/bank.test.taler.net/176	10	0	1568325480000000	1568325480000000
\\x37e05777be1d12227329799c20ceb6392c437fa7ff2f7cd9b73fb6942d97b674	payto://x-taler-bank/bank.test.taler.net/175	10	0	1568324546000000	1568324546000000
\\xab61e6dc949dd1f35b2bcf8aa92155a61b37dc8ff002513db10988d72c10f85c	payto://x-taler-bank/bank.test.taler.net/174	10	0	1568323859000000	1568323859000000
\\x9d7bdee2ad68d7850d99dc3009925e3fff8faf821c782c75b9e58d8401f492a6	payto://x-taler-bank/bank.test.taler.net/173	10	0	1568323193000000	1568323193000000
\\xfbcab337efa5cad7f030026dd568ce0a9f6b32a3f0647b6c23d9055c4272ae38	payto://x-taler-bank/bank.test.taler.net/172	10	0	1568322988000000	1568322988000000
\\xd24bceae2f137c7a7a33a7e27490f2ee051ca8303fee7d4dd8e78d7a1f0aee62	payto://x-taler-bank/bank.test.taler.net/171	10	0	1568322789000000	1568322789000000
\\x5039d714051dc54f8a12d638d99d6ee2cbba8f84417d239ba13a6dae52a106d8	payto://x-taler-bank/bank.test.taler.net/170	10	0	1568322728000000	1568322728000000
\\xe3885032e24de4aff2214d768134ee11d500559f69b92befe92a9b475fdbbeee	payto://x-taler-bank/bank.test.taler.net/169	10	0	1568322655000000	1568322655000000
\\x92f04e72829581397d5d7af2cfbe8c1eb98769ed2a1dc49f9502e4efb1387ca4	payto://x-taler-bank/bank.test.taler.net/168	10	0	1568322583000000	1568322583000000
\\xcbb9acd062ab443328e6050dbe93e2b8f84c6e2d06b4d98e8aace06251e06033	payto://x-taler-bank/bank.test.taler.net/167	10	0	1568322477000000	1568322477000000
\\xe9cd9bd7e64730ffcca680c79dc186180f44228b2b64146e3e98689c074bf5a7	payto://x-taler-bank/bank.test.taler.net/166	10	0	1568322277000000	1568322277000000
\\xe9475fffced36d5aa6e26073dd28ccc50f2ca4448b3089ecc9c13030abd8f60b	payto://x-taler-bank/bank.test.taler.net/165	10	0	1568322056000000	1568322056000000
\\x87df20e293f6c021efdb3408e1f3121f79a5f1000cbdd3d2b09eade6969f07c8	payto://x-taler-bank/bank.test.taler.net/164	10	0	1568321984000000	1568321984000000
\\xddb8dfe63ae9995f4846435d10bbb0b27887c5bd911082781c4efedd0df40f67	payto://x-taler-bank/bank.test.taler.net/163	10	0	1568321733000000	1568321733000000
\\xf236ae1b03f5896bb57da63548778c065c31c5d30ca2e1b257b98e8a40a1f498	payto://x-taler-bank/bank.test.taler.net/162	10	0	1568321019000000	1568321019000000
\\x245663abb3929008134cfadcd585d8c30189eac85a59ac3f63b57ee150394031	payto://x-taler-bank/bank.test.taler.net/161	10	0	1568320829000000	1568320829000000
\\x7920ef3246557b9add917c3b24df7557e597b9ea132d7a6ade8147463f20d88e	payto://x-taler-bank/bank.test.taler.net/160	10	0	1568320502000000	1568320502000000
\\x383faa3efbad6ba618b9a0518c726b968c093da880aa325e0815c26d302baa8d	payto://x-taler-bank/bank.test.taler.net/159	10	0	1568320449000000	1568320449000000
\\x0c5cd55b9766b103527762452a1e81367c77bf6d24403a15b94ea0fa87904776	payto://x-taler-bank/bank.test.taler.net/158	10	0	1568320045000000	1568320045000000
\\xd0310cbff1f595d844e540ff10e9e2de78fcb27fdba221f4243ec5bf69585c82	payto://x-taler-bank/bank.test.taler.net/157	10	0	1568320015000000	1568320015000000
\\xb21a34488c76adf57605deef27a970d6d9d33da99fd10d5b34f971283282b936	payto://x-taler-bank/bank.test.taler.net/156	10	0	1568319524000000	1568319524000000
\\x038996dfe9ad38f23e619fd7633f3074e88b03d48e59d818047613fe6617f725	payto://x-taler-bank/bank.test.taler.net/155	10	0	1568318945000000	1568318945000000
\\xba2946c6883d1ed6f2770b5902b2b08f6ee0a02148b277b60a085f88118d3ddc	payto://x-taler-bank/bank.test.taler.net/154	10	0	1568318879000000	1568318879000000
\\xb233d5a9840e928cb977bceb516306951f3690c14183539824dd61ee466f08c2	payto://x-taler-bank/bank.test.taler.net/153	10	0	1568318181000000	1568318181000000
\\xa42e64a59afcf6bb9f1c76f9cb00613f067bc49f5e81b8e242d813bafccea2fc	payto://x-taler-bank/bank.test.taler.net/152	10	0	1568315915000000	1568315915000000
\\x3ec53b2ead912ef64ac90c74d5a68e5b60ae65f0249af37ea6eb9e05b9164898	payto://x-taler-bank/bank.test.taler.net/151	10	0	1568308050000000	1568308050000000
\\x21d76dcb3902f1dbdde706d80a37b852666435bbeca78bfdc5cef62d72686d43	payto://x-taler-bank/bank.test.taler.net/150	10	0	1568293486000000	1568293486000000
\\xf1c90d032747f3cc1d8738eb9c888c1e4013f9e7064ffd521a7eaded85cfbc9f	payto://x-taler-bank/bank.test.taler.net/149	10	0	1568220556000000	1568220556000000
\\xaf086d1b12d87e90235d15156afdafefe8fcd38f4de456e9bbfeb62b3d6c3ad4	payto://x-taler-bank/bank.test.taler.net/148	10	0	1568219633000000	1568219633000000
\\x06ac13492eace96f3e5a49e44e0f18c4a356c77b1d4a8e856b976d9e9a436edc	payto://x-taler-bank/bank.test.taler.net/147	10	0	1568219489000000	1568219489000000
\\xea06a92933ce6035f37c58c4476a5b661228594d98b62e4b8f8c2458fe451303	payto://x-taler-bank/bank.test.taler.net/146	10	0	1568219435000000	1568219435000000
\\x64a12dded192a4f8edc3614e4acf52fbe27c78cbed3ab815f4627723ca14e4ab	payto://x-taler-bank/bank.test.taler.net/145	10	0	1567621794000000	1567621794000000
\\xfb949fb3cf8195cd6424b1475ea365019a9a4fbb25041e94af644e201c7c83d6	payto://x-taler-bank/bank.test.taler.net/144	10	0	1567621602000000	1567621602000000
\\xe566a9c140e79572592dfeb3dcf5cea94c9dd8da30dc292d8fe44a284ce5d481	payto://x-taler-bank/bank.test.taler.net/143	10	0	1567620402000000	1567620402000000
\\xc2cabf67c5f7bdc043a7f62ed26cb12fd43b1492aabb44bf5db7f0d70e57dbf8	payto://x-taler-bank/bank.test.taler.net/142	10	0	1567116022000000	1567116022000000
\\x07339becf40893d3ae5d1240e79f1f24c8289ce9ba616c570c50f7f58cd81169	payto://x-taler-bank/bank.test.taler.net/141	10	0	1567115004000000	1567115004000000
\\x23e715a7d521c72f5b14338fea8ef018b42e255c3047d0a381ba1b892951a584	payto://x-taler-bank/bank.test.taler.net/140	10	0	1567114996000000	1567114996000000
\\x18191bb360a5f0a52525101988c41ed8c9244511d8813371023d44164dd3ff9b	payto://x-taler-bank/bank.test.taler.net/139	10	0	1567113527000000	1567113527000000
\\xbf0ff9a0ee337e7af907db7c46888d79a3f4e0dcc96ee1476a8bd4bb0b063a30	payto://x-taler-bank/bank.test.taler.net/138	10	0	1567113433000000	1567113433000000
\\xdd974f8782ead8c4f65996e45e14cbdedd05b5ff194f2e069086c2918819b75c	payto://x-taler-bank/bank.test.taler.net/137	10	0	1567113353000000	1567113353000000
\\x24bfdf65d4f1f9d4569b886e727b9aa0dc6880614899b27f5663d8b72e1b583e	payto://x-taler-bank/bank.test.taler.net/136	10	0	1567113304000000	1567113304000000
\\xf03f57d32b04d85adbce1409248b6b5fb37321cd9d9cf87501d21db209336cdf	payto://x-taler-bank/bank.test.taler.net/135	10	0	1567113214000000	1567113214000000
\\xb808d9b7228568c2da8a58e1f0f5bab7af279d1db94592f1117e42163aeee7be	payto://x-taler-bank/bank.test.taler.net/134	10	0	1567113025000000	1567113025000000
\\x96b4b1dda4cf071443b4981f1d19d2f2f2e18c134355b9fee726e8f36bbdd2da	payto://x-taler-bank/bank.test.taler.net/133	10	0	1567112977000000	1567112977000000
\\xc18211fa8c81102e6fc987ba80a04caa028b1982b816a5d2785614d6ebec3c96	payto://x-taler-bank/bank.test.taler.net/132	10	0	1567111961000000	1567111961000000
\\x7085f00e9a48f4678899788358172b7447cd456c276a20d7313ca474be88b8a7	payto://x-taler-bank/bank.test.taler.net/131	10	0	1567111847000000	1567111847000000
\\x6803c62ef4992666d21fd5571e2807134d1aaa6f7fbb7f8333ddbab7910e0a00	payto://x-taler-bank/bank.test.taler.net/130	10	0	1567111766000000	1567111766000000
\\xd9639612a99db4d4527d907179d1649575ade0db21205bb984928d59916ff575	payto://x-taler-bank/bank.test.taler.net/129	10	0	1567111738000000	1567111738000000
\\xb4a2cee738ce45ecc226c07766148a710e68875ae06b92447f79d3615a279da7	payto://x-taler-bank/bank.test.taler.net/128	10	0	1567111678000000	1567111678000000
\\x66f3faced265ce5d6c8b67ca3566edf511e61b0caada94bf08ba538d01357b70	payto://x-taler-bank/bank.test.taler.net/127	10	0	1567111633000000	1567111633000000
\\x48df8b7cfd2999012b0004f8d0746d4c1ccf02051b6c55b071bf0bc3f92aee9c	payto://x-taler-bank/bank.test.taler.net/126	10	0	1567111611000000	1567111611000000
\\x548a4bc745f4033c770ed431c2321bbe70d609d881190f970251bda60052c5a5	payto://x-taler-bank/bank.test.taler.net/125	10	0	1567110765000000	1567110765000000
\\x63a477040824f3cd55ac8dbc628274a9107608c423fc51643ac25d2ed61d0de8	payto://x-taler-bank/bank.test.taler.net/124	10	0	1567110351000000	1567110351000000
\\x2c1b8d0b80acb5f6e3049190ff613726a4b5441553b3d3ec77deb232594e7218	payto://x-taler-bank/bank.test.taler.net/123	10	0	1567110305000000	1567110305000000
\\xd78dde36de2139fa86f2a0f7bf8a13b2f654d9fc3cd303ebb2eab186cb9f0040	payto://x-taler-bank/bank.test.taler.net/122	10	0	1567110171000000	1567110171000000
\\x1fdc52e5e5aaf87add91e7a1fec0fbf332ce7bd9c9d64154317e670798fe7fbb	payto://x-taler-bank/bank.test.taler.net/121	10	0	1567033624000000	1567033624000000
\\x1380f5e214357cb2e7717dff93edbdfe1a0ea3d38abaab37ab80e1c0c68ae71a	payto://x-taler-bank/bank.test.taler.net/120	10	0	1567027799000000	1567027799000000
\\x954518ac86a57cd7f8e87ee130a700fa82dfc8bebfe203ca3b74d2cd17e1cb26	payto://x-taler-bank/bank.test.taler.net/119	10	0	1567027748000000	1567027748000000
\\xbb8902b13a6baac9f348816b3c3b9ec1b3c3c806416a64c73dcc454e09227a92	payto://x-taler-bank/bank.test.taler.net/118	10	0	1567027440000000	1567027440000000
\\xe4d26be5cacceef7912af71ecde66d520cb080386e12e595f003247e1f936722	payto://x-taler-bank/bank.test.taler.net/117	10	0	1567026602000000	1567026602000000
\\x16b8099673434e13daef88b354ddde89a8ab8803a78a262ee01ff241af07951a	payto://x-taler-bank/bank.test.taler.net/116	10	0	1567026500000000	1567026500000000
\\xcd29f44596d41578562294edaa5f9d225da864c18d222ebc64186656208213c3	payto://x-taler-bank/bank.test.taler.net/115	10	0	1567025876000000	1567025876000000
\\x24f5e83ab46b9b876a6d044bdbfd86edd0d5ac06e34f822f73537f9e86ddd27e	payto://x-taler-bank/bank.test.taler.net/114	10	0	1567025847000000	1567025847000000
\\xa8120c712e0045d452667af538614c2ede7fa93e574b98c2568dc94f1200ed2f	payto://x-taler-bank/bank.test.taler.net/113	10	0	1567025769000000	1567025769000000
\\x8de9216933cf74b32a0ba183c5d47f07deb8d1ba6aeab2558d27933f8f46251a	payto://x-taler-bank/bank.test.taler.net/112	10	0	1567025697000000	1567025697000000
\\x86d56a0cf7a3981f71b607a9673ee2fe4ad3a8710274073cbe9dfb7ad73a2510	payto://x-taler-bank/bank.test.taler.net/111	10	0	1567024729000000	1567024729000000
\\x536fbc82c3257adfb45db4a7c3fea6661442a2edf4eb3413121e86916d84c559	payto://x-taler-bank/bank.test.taler.net/110	10	0	1566958033000000	1566958033000000
\\xc5665b33302b94735b0f53fabe3e4b28005be2cd6ea7b9f8ee133bc35f397ed3	payto://x-taler-bank/bank.test.taler.net/109	10	0	1566957974000000	1566957974000000
\\xa85e72dc53fad0966b30f675487aac5810e20b3bf7f36c63233bea2d1c9370e7	payto://x-taler-bank/bank.test.taler.net/108	10	0	1566957801000000	1566957801000000
\\x58964c1bcebf6b5513e15eb0eef739d38f1478e1cd53bf661342b9c62038cbe2	payto://x-taler-bank/bank.test.taler.net/107	10	0	1566957759000000	1566957759000000
\\xd3be87219e455c130fb5d5976ec829cdf39359a7d0a3e37cdabd0e42f2fad9b2	payto://x-taler-bank/bank.test.taler.net/106	10	0	1566957604000000	1566957604000000
\\x62d223b400193c59c2e72fbccbe09b9184ac7c1a028da0035d53461ca495555e	payto://x-taler-bank/bank.test.taler.net/105	10	0	1566957547000000	1566957547000000
\\x00c831aa5b629c775dc9a0175875c435262392e8ec98c820efab3c40f59c3fe8	payto://x-taler-bank/bank.test.taler.net/104	10	0	1566957467000000	1566957467000000
\\x1997040916524f5640cc195c47cb5c032164e8c192fa255e85a3ae9d5800660c	payto://x-taler-bank/bank.test.taler.net/103	10	0	1566957397000000	1566957397000000
\\xa3e78ad0d30b125cd2d8a415ca3b9a43b971ac8e43647a68064b78943ef65e7c	payto://x-taler-bank/bank.test.taler.net/102	10	0	1566957375000000	1566957375000000
\\x43204e72736000d5ddee27e781d5ad4b45bfde4b3e83173311189ab720af0dca	payto://x-taler-bank/bank.test.taler.net/101	10	0	1566957344000000	1566957344000000
\\xa6ea849bc978b07d539c37404ce74dafb28b94d46d3d929a9ddba72d176fc5fb	payto://x-taler-bank/bank.test.taler.net/100	10	0	1566957236000000	1566957236000000
\\x35641ad074a9b19579b03e68c2bd128dd15deaf8684af5c4a346801372d41b90	payto://x-taler-bank/bank.test.taler.net/99	10	0	1566957190000000	1566957190000000
\\xaae06b233c96780d6afd620b1edd6f821d14a5bf432fbc5f4aeb689e7fe3d938	payto://x-taler-bank/bank.test.taler.net/98	10	0	1566957154000000	1566957154000000
\\x4c6d212fba5c61423aad80c8af8b1d5f3c94b267d920f53851caadf2166d49b0	payto://x-taler-bank/bank.test.taler.net/97	10	0	1566957128000000	1566957128000000
\\xd0c7accb37f6345703dfb0502fa150066094c681ed319b1dc2fcd234eb6fb767	payto://x-taler-bank/bank.test.taler.net/96	10	0	1566957088000000	1566957088000000
\\x64aed8c33abf2c05cefa50c0ecaf5e1f20201e747be1339b8d04fbb29b59cb57	payto://x-taler-bank/bank.test.taler.net/95	10	0	1566957083000000	1566957083000000
\\x69958928499e2c55da1ea6fb7833bd6a3e80962996c4a821fe95d05b58f96a26	payto://x-taler-bank/bank.test.taler.net/94	10	0	1566956929000000	1566956929000000
\\x5cb50417e9ab996297eb90960b33772f344ae83bc6ef32ebe96318d09cb331f0	payto://x-taler-bank/bank.test.taler.net/93	10	0	1566956914000000	1566956914000000
\\x06ea81e28c450fd05b5a0c912fef872fe3adf22a8ca70425cfd38ff2a65649e1	payto://x-taler-bank/bank.test.taler.net/92	10	0	1566956897000000	1566956897000000
\\x81f75ad9675c95ba5078825b565c0f824f40359308975309996a4da4a5644f10	payto://x-taler-bank/bank.test.taler.net/91	10	0	1566956890000000	1566956890000000
\\xb2c11ab01be7ce2856f045ae71e075b7773c0ee212d4fe17a6c3b7357610517d	payto://x-taler-bank/bank.test.taler.net/90	10	0	1566956883000000	1566956883000000
\\x9656ed83ad3aa5cc92c0f8164a1be450f5f275de8ac3cbe3269a5b2bc67a4e8c	payto://x-taler-bank/bank.test.taler.net/89	10	0	1566956855000000	1566956855000000
\\xb0f9afccc0e0e6db8ff80daafbe7e3402de21e2f37d57f22348397c5d5d28940	payto://x-taler-bank/bank.test.taler.net/88	10	0	1566956844000000	1566956844000000
\\x302417b3226366b7893c3cf6ea0a9914d7f12ee9c4f7e68f4b0a743dddc2daad	payto://x-taler-bank/bank.test.taler.net/87	10	0	1566956797000000	1566956797000000
\\xbebc635004c1523c36f749753b8d7df3e3a535d657529c88edda82aa8372688e	payto://x-taler-bank/bank.test.taler.net/86	10	0	1566956735000000	1566956735000000
\\xd97382f3adeb334efc19beb626b79a465cf10e6722370f4158811962ea18bafa	payto://x-taler-bank/bank.test.taler.net/85	10	0	1566956686000000	1566956686000000
\\x1da515d261a0b861b1c937b34bf6cbf0dfe0baf10646daec02035c888775be0f	payto://x-taler-bank/bank.test.taler.net/84	10	0	1566956680000000	1566956680000000
\\x9f5bf80861719ced68d14c652154ef31251800dfb9b9d131fd211072cbe1dfe0	payto://x-taler-bank/bank.test.taler.net/83	10	0	1566956673000000	1566956673000000
\\xf405b7257a8a5538d422ef6357ad1bf283cc4c11fffc5d0cfa766f72513618b6	payto://x-taler-bank/bank.test.taler.net/82	10	0	1566956613000000	1566956613000000
\\x22f8a5abcfd602cc882981bb71b6369295be2134d32634f3f977149bcdcb58f0	payto://x-taler-bank/bank.test.taler.net/81	10	0	1566955610000000	1566955610000000
\\xe28be2d1c6b322cf70742df0d1770adab4273af10f2a141ff703bbd24a9a9ac8	payto://x-taler-bank/bank.test.taler.net/80	10	0	1566955571000000	1566955571000000
\\x6a0d97fb945b3b91e17b1e40f3e8b6d7b595a57e4bbffbea232987e427b5a1d1	payto://x-taler-bank/bank.test.taler.net/79	10	0	1566955531000000	1566955531000000
\\xfb87bd1deed3e5c30cdd323ef440e77e42d859262962e9f99c03a5c740e4afaa	payto://x-taler-bank/bank.test.taler.net/78	10	0	1566955463000000	1566955463000000
\\x312118463312133bf9537123a3930ac4a4d2c245baea11dd8fd32fd8351bed29	payto://x-taler-bank/bank.test.taler.net/77	10	0	1566955398000000	1566955398000000
\\x4685b36210f4a6c7e87d9f88b5a45f834a0d5b58c9d138fd705aaf442e9ad8c4	payto://x-taler-bank/bank.test.taler.net/76	10	0	1566955271000000	1566955271000000
\\xfb380400ea4f5a8fbc5b8bb4a09b779aaf217474955c02d02e6c2f7067293e2e	payto://x-taler-bank/bank.test.taler.net/75	10	0	1566955253000000	1566955253000000
\\xbc40482ef0b8339c6ca1a7fdb65773a0e8a025c9c132fb6be01e73f7034e6e55	payto://x-taler-bank/bank.test.taler.net/74	10	0	1566954949000000	1566954949000000
\\xd681ec996bf4ca985c7fa9577709158416c88988a29f20d8ea16dfbc27e494ff	payto://x-taler-bank/bank.test.taler.net/73	10	0	1566954783000000	1566954783000000
\\x4deda68ee9c75e3eafa0727067c4778ca01a8e2adc85eb1a8b45035552a98578	payto://x-taler-bank/bank.test.taler.net/72	10	0	1566954376000000	1566954376000000
\\xa83105590f3561f861081fcfd5f885a01585b325ffb3263c6a7c9c8d2a10c34c	payto://x-taler-bank/bank.test.taler.net/71	10	0	1566954367000000	1566954367000000
\\x54b48db3c7833a4a43d7433a7443c0a43ca5eccdae6760937e9fe4c074b2a3da	payto://x-taler-bank/bank.test.taler.net/70	10	0	1566954008000000	1566954008000000
\\xf4ce5a6636d9042b66f1633ae30b2aa5cd262a189ed20f793f72307dc9c248f0	payto://x-taler-bank/bank.test.taler.net/69	10	0	1566953834000000	1566953834000000
\\xe6aec2213578fe4de5fee32f82d79ce13f168f9ddd1861ea50c2f13d62c9f4ad	payto://x-taler-bank/bank.test.taler.net/68	10	0	1566953270000000	1566953270000000
\\x832ba7bf73d5b86429f3be7f245e0b8880f2e6feb29e6b3d6d5f13d586bf9fcc	payto://x-taler-bank/bank.test.taler.net/67	10	0	1566953055000000	1566953055000000
\\xd3ff34a089de9aec918e3b75a0178136171af9a84fbee676ea5a8cc2a947c060	payto://x-taler-bank/bank.test.taler.net/66	10	0	1566952736000000	1566952736000000
\\xe7fd68fd42067d407b98d1f30f80307353f5348047dc2649c82684240886e4fd	payto://x-taler-bank/bank.test.taler.net/65	10	0	1566952570000000	1566952570000000
\\xb65138b306c3a742753688438123087da53e07319fc30ddb769baec37780d204	payto://x-taler-bank/bank.test.taler.net/64	10	0	1566952542000000	1566952542000000
\\xf66b6fc40bfd70532fa6da42e8d746a20a74415647f99be6c5e5a855c97aa0a7	payto://x-taler-bank/bank.test.taler.net/63	10	0	1566952498000000	1566952498000000
\\x95a1d91c014ba399e5f7494c4135cb3c81b0f69eeed821c85da402fc07c9daac	payto://x-taler-bank/bank.test.taler.net/62	10	0	1566951959000000	1566951959000000
\\xcf622a2c3767c9f871100f9d782b792e1e6a5404833445d522789f924d169b4d	payto://x-taler-bank/bank.test.taler.net/61	10	0	1566951257000000	1566951257000000
\\x8d40f84bf39a8ca60e00d36825f2b156afaad70dff784f434ddfdb48682d53b6	payto://x-taler-bank/bank.test.taler.net/60	10	0	1566951247000000	1566951247000000
\\x5604e4942174f8ead3e75d576e38c5264e65757cc2a07c4e8ac1bf4da6b95b14	payto://x-taler-bank/bank.test.taler.net/59	10	0	1566950957000000	1566950957000000
\\x39a22bfce8e62bb9bf56113cc0272dc3c776cac1efa3c307d0fb84671d805d76	payto://x-taler-bank/bank.test.taler.net/58	10	0	1566950933000000	1566950933000000
\\xde8480cf26f349a625f9fcd83aa6498570479fad5c1193f9dda3f1ad683239db	payto://x-taler-bank/bank.test.taler.net/57	10	0	1566950662000000	1566950662000000
\\xb452f9eca6986c08f8c23a978e0f0be057a8ac79005640f87a993e16b95764fa	payto://x-taler-bank/bank.test.taler.net/56	10	0	1566949416000000	1566949416000000
\\x9f049ed6dbb886f85e6b62c86a9ce709d0d2de3abb8f6578d50233f88bc7f93d	payto://x-taler-bank/bank.test.taler.net/55	10	0	1566949255000000	1566949255000000
\\x4e7946826a660b06b17634fc4ead6f9ce8ca563ba56eb8e9569cbcec1a279ce8	payto://x-taler-bank/bank.test.taler.net/54	10	0	1566948664000000	1566948664000000
\\xf1c097c68600d04fd93be5c44fe7c67ee577d2c372eb981bf1889e669c1ee203	payto://x-taler-bank/bank.test.taler.net/53	10	0	1566948528000000	1566948528000000
\\xee80e518448d549e9319687310248ea6a8885dfa94ba0f78bf62a12c84825e9e	payto://x-taler-bank/bank.test.taler.net/52	10	0	1566948420000000	1566948420000000
\\x420480d63995c7c69bded84145ce20c13743f51cb83296d0b38713d4c3307dac	payto://x-taler-bank/bank.test.taler.net/51	10	0	1566947169000000	1566947169000000
\\x16dcd603b509d4829fc4f2c6ed34a7fc5d20be15dcd3c50248f97e609eedf3b1	payto://x-taler-bank/bank.test.taler.net/50	10	0	1566947161000000	1566947161000000
\\xc3109d60cc5a3adf527ad26fd6cb17223bcddf138cedd775ff8174a6b0d4d57f	payto://x-taler-bank/bank.test.taler.net/49	10	0	1566945900000000	1566945900000000
\\x285c1be3eddd195f60d19a0d35e7d9ac677db3414e3dbeb45a744740bf2ceade	payto://x-taler-bank/bank.test.taler.net/48	10	0	1566945799000000	1566945799000000
\\x38ab0a9f30c7bc5c524a634bd65ffa7d34fc8f1086531d20e69d055f5f6117c5	payto://x-taler-bank/bank.test.taler.net/47	10	0	1566939135000000	1566939135000000
\\x6ce4ed71b0493afa505c82bce3cf35fbb9ab1fbedd739d56de8fd0aeef256086	payto://x-taler-bank/bank.test.taler.net/46	10	0	1566939065000000	1566939065000000
\\xabf0b85b85cf80b41e0b39ab792ae7581b9855bfcf5e28d2a9a367476a84f754	payto://x-taler-bank/bank.test.taler.net/45	10	0	1566938932000000	1566938932000000
\\x5022184bf2d4433c31601ce1cbd91210cf746a47ea5e2986ccaafa8f44c73cb2	payto://x-taler-bank/bank.test.taler.net/44	10	0	1566810261000000	1566810261000000
\\x9a0403092f3d26c4f6e972e7790340048a3cd685cde9ea78564d8764434cdf9c	payto://x-taler-bank/bank.test.taler.net/43	10	0	1566810109000000	1566810109000000
\\xcc142afa684afbda15d34a034120d2e432ff922155baa4fe9c0ee650d0ff46cb	payto://x-taler-bank/bank.test.taler.net/42	10	0	1566809448000000	1566809448000000
\\xfc81c49fd4757e5ec657c9a2def34982bcbb006e9fe97021c0abeaf1734ec94a	payto://x-taler-bank/bank.test.taler.net/41	10	0	1566809376000000	1566809376000000
\\x897ae32910f7abed434f0610dd49237b33e444d0f8bd249430ca3dc95a10a2af	payto://x-taler-bank/bank.test.taler.net/40	10	0	1566807501000000	1566807501000000
\\xcc86e634723b519276a556ad6ad6b60f380f21b02032c0740ded5e35603bc478	payto://x-taler-bank/bank.test.taler.net/39	10	0	1566806872000000	1566806872000000
\\x90daeab4cbd5cb952510b3d199f3a0fefa8d45f77902390505db05bcfed8bf99	payto://x-taler-bank/bank.test.taler.net/38	10	0	1566806744000000	1566806744000000
\\xcd23da780b5f93611ac993fc63575d2bafacd46d2ca7a9397316ba08b70fcbb6	payto://x-taler-bank/bank.test.taler.net/37	10	0	1566806704000000	1566806704000000
\\x2155645ea096b73957f56c776e2e785db994dcec138fc4be4c41344322197551	payto://x-taler-bank/bank.test.taler.net/36	10	0	1566764816000000	1566764816000000
\\x7bcf85a0af25010d0df96e5826302329f4a0dba7056f7390c14e240916320a55	payto://x-taler-bank/bank.test.taler.net/35	10	0	1566764678000000	1566764678000000
\\x09c2c3d8d54d9183221a1afdee2873370eb17cb7ae6bbe259d1770a05082ec04	payto://x-taler-bank/bank.test.taler.net/34	10	0	1566764470000000	1566764470000000
\\x19d245eda964fadc2d68c0c1d05ee8ab761212dec72a0e151f670e9028cdf0b4	payto://x-taler-bank/bank.test.taler.net/33	10	0	1566764283000000	1566764283000000
\\xc2caebf149e241165f50e4b82c51e322f5bef5fd0c12dcf41f4ab597cf2d0919	payto://x-taler-bank/bank.test.taler.net/32	10	0	1566763196000000	1566763196000000
\\xb53d31ec78090b17be2ea17aedb42bf74a985215946d0674fa06c7c326fcaefe	payto://x-taler-bank/bank.test.taler.net/31	10	0	1566763185000000	1566763185000000
\\xdfcf3f95ec6a159fd971b8afc5203432523d38ca3fac1bd0dc11cee7c67d186b	payto://x-taler-bank/bank.test.taler.net/30	10	0	1566597556000000	1566597556000000
\\x3049fdf6ffd673a6711558e0b2cd34e53dbd3d0150407f12c896dd17056f80a9	payto://x-taler-bank/bank.test.taler.net/29	10	0	1566596474000000	1566596474000000
\\xd8457bd02eb1f93640e440d374168378a3a26810eaf6f462e0bb48ddf5fa25b1	payto://x-taler-bank/bank.test.taler.net/28	10	0	1566595257000000	1566595257000000
\\xac8df807cb36ef64846816ab0947cb59348b116f7cccb7fe378b486bcb06adbf	payto://x-taler-bank/bank.test.taler.net/27	10	0	1566594656000000	1566594656000000
\\x5350dea1916bd3d4324025fa70d64fcc7ca583520e6ca4ce3ce1b56f838e8bab	payto://x-taler-bank/bank.test.taler.net/26	10	0	1566594635000000	1566594635000000
\\x661e8a0a01acb4cbb4b3678b52e36cef107ecceb1bc34ae2c534a2105b6dbdba	payto://x-taler-bank/bank.test.taler.net/25	10	0	1566594212000000	1566594212000000
\\x1eea5a98a6944c6daa73ff98448f602b64f5a6008af7d5ec04e0948cd12521fd	payto://x-taler-bank/bank.test.taler.net/24	10	0	1566593124000000	1566593124000000
\\x9a76b3e571ceb844d248de54ef2edcc829a8e166da4cd0f4ee0ce1606fc49d67	payto://x-taler-bank/bank.test.taler.net/23	10	0	1566593002000000	1566593002000000
\\x4b640f53f10a01dba1998894b439df71831eff0fdaa4bf1e149a7399a879dfa7	payto://x-taler-bank/bank.test.taler.net/22	10	0	1566592884000000	1566592884000000
\\x18e56584f16f9f023708933014b179e9b810231b40217ecc257216ca139d6510	payto://x-taler-bank/bank.test.taler.net/21	10	0	1566592875000000	1566592875000000
\\x2d85cac3344b67052aeaaaeac0312e3bf3814781ae182d7b11e0fa6d7c301021	payto://x-taler-bank/bank.test.taler.net/20	10	0	1566592836000000	1566592836000000
\\xbe6c6cf37b37e4ac11f5efefffa16111e32ce79981d192ada976a329a30fda7e	payto://x-taler-bank/bank.test.taler.net/19	10	0	1566592711000000	1566592711000000
\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	payto://x-taler-bank/bank.test.taler.net/397	0	0	1568898098000000	1787230900000000
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
1	\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	\\x0000000000000354	10	0	payto://x-taler-bank/bank.test.taler.net/396	account-1	1566476615000000
2	\\xe6dacd272de8282c0b32344101c61815e3921c4564cc346a991918b21904cedd	\\x0000000000000352	10	0	payto://x-taler-bank/bank.test.taler.net/395	account-1	1566476420000000
3	\\x66ec99ef569ba5b8262b5451943f743d82db4d46d850f56295229bc941e06d0c	\\x0000000000000350	10	0	payto://x-taler-bank/bank.test.taler.net/394	account-1	1566476135000000
4	\\x5a4622282f4ca44630980efeb12cbb2a8c3c46daa0d676186ccdad1103910954	\\x000000000000034e	10	0	payto://x-taler-bank/bank.test.taler.net/393	account-1	1566476014000000
5	\\x1c18ce673522c676d133d3fd38fc525c06f9139256f97733392aa476b38da935	\\x000000000000034c	10	0	payto://x-taler-bank/bank.test.taler.net/392	account-1	1566475277000000
6	\\x4d93a5159d2a5bd6910267a91c3111ac495329410097a1adcf772d3a240df2bb	\\x000000000000034a	10	0	payto://x-taler-bank/bank.test.taler.net/391	account-1	1566427028000000
7	\\xbd46bfe36609883ca276710aa7446bdf49d7a03f005472630e50a0784a53a741	\\x0000000000000348	10	0	payto://x-taler-bank/bank.test.taler.net/390	account-1	1566427006000000
8	\\x2dbb53c2f3627f50b18ec54e15246c7b5f81a15683f53a7177029814f8da8bc2	\\x0000000000000345	10	0	payto://x-taler-bank/bank.test.taler.net/389	account-1	1566405376000000
9	\\x1f4681908ed2f225632346cc1e3b4988ce8fa6c1c8ab179f978b3bcff3c21bf1	\\x0000000000000343	10	0	payto://x-taler-bank/bank.test.taler.net/388	account-1	1566405026000000
10	\\x688b922cfa19931ba3d9030b747bdc2da9716aac4e53f21a15c5988456915581	\\x0000000000000341	10	0	payto://x-taler-bank/bank.test.taler.net/387	account-1	1566404945000000
11	\\x012e41df79ff63a8f39d2817a86bbc0e60f14e70440fbab3c234fc4a8d05d439	\\x000000000000033e	10	0	payto://x-taler-bank/bank.test.taler.net/386	account-1	1566397498000000
12	\\x6c3a52338741d0f462f571f42daf5be81b7a945da9ad871cc9f58ddd700193aa	\\x000000000000033b	10	0	payto://x-taler-bank/bank.test.taler.net/385	account-1	1566394252000000
13	\\xc8e442c5c85ef054a27974ba39c3745c9d017f4bf8e52768c5e8669ba8583e66	\\x0000000000000339	10	0	payto://x-taler-bank/bank.test.taler.net/384	account-1	1566394222000000
14	\\xc9675953172121e16dab952fc11a250245a5682fc6c5cb921cbe1753869d3299	\\x0000000000000337	10	0	payto://x-taler-bank/bank.test.taler.net/383	account-1	1566393958000000
15	\\xc37168aec489a6472db4efc0a85feeb19f6c8cdf1de3723945bba9bd8a7fb634	\\x0000000000000335	10	0	payto://x-taler-bank/bank.test.taler.net/382	account-1	1566393343000000
16	\\x0a26d1acfe138d947700857a157a007c0f8b44cb2cd5387c4e4ba1dc21603e6c	\\x0000000000000333	10	0	payto://x-taler-bank/bank.test.taler.net/381	account-1	1566393317000000
17	\\xc7624530ea124cca7e8661163d6b4016d2a4252b63c901a77a9d1771245da8f9	\\x0000000000000331	10	0	payto://x-taler-bank/bank.test.taler.net/380	account-1	1566392677000000
18	\\xb71c07fdff675806af9e20022b7bf5ec0ec16f0892d3b866436f659da502a25f	\\x000000000000032f	10	0	payto://x-taler-bank/bank.test.taler.net/379	account-1	1566392545000000
19	\\xc8f38a375831272de806e769f96d6c4c142b9c249a5110eb26c35117f69014a3	\\x000000000000032d	10	0	payto://x-taler-bank/bank.test.taler.net/378	account-1	1566389252000000
20	\\xe67cf6c190418a44ff772b5af0075de9f50ecb27d168c907837528575531a747	\\x000000000000032b	10	0	payto://x-taler-bank/bank.test.taler.net/377	account-1	1566389178000000
21	\\x74a4f75e0092c7f48bacfcdc2b3eac5fa93c61548b0bdd053e0bfbb741d9af51	\\x0000000000000325	10	0	payto://x-taler-bank/bank.test.taler.net/376	account-1	1566387148000000
22	\\x62ce130deab667ded5da342d4a7c8a48259c5464e4c11f9a41a155622f736d8a	\\x0000000000000321	10	0	payto://x-taler-bank/bank.test.taler.net/375	account-1	1566386814000000
23	\\x53339a2bc10f6d6dc9f3c275269fab85e67ea25dc2853d5c25898ed41d51331e	\\x000000000000031c	10	0	payto://x-taler-bank/bank.test.taler.net/374	account-1	1566386362000000
24	\\xb2f0675021b8b2b2c82a33d7de06a6188014ef6f641ec1f63b98574adc4a5a79	\\x0000000000000319	10	0	payto://x-taler-bank/bank.test.taler.net/373	account-1	1566386271000000
25	\\x64de8ad09221295cda8823d29797b5335c3c40efd0111a20134fef96bbd9ac9a	\\x0000000000000317	10	0	payto://x-taler-bank/bank.test.taler.net/372	account-1	1566386085000000
26	\\x7140831bef79c6208bca40a3b926a8045cc19cd504f0502261d8d8c5872c9de9	\\x0000000000000314	10	0	payto://x-taler-bank/bank.test.taler.net/371	account-1	1566385895000000
27	\\xe3c38f7f9a1f808655c624f450bd9e1d084ac6448d9f42fbe56dc99c017b176e	\\x0000000000000311	10	0	payto://x-taler-bank/bank.test.taler.net/370	account-1	1566385833000000
28	\\xfc13820602150f5b065d5e8c34ad9c01b28403af35f155bf471c478399382725	\\x000000000000030e	10	0	payto://x-taler-bank/bank.test.taler.net/369	account-1	1566376892000000
29	\\x5d7b8eea903cbe3c4926db1c8c8cce69482ecbc196bd65813388ce3237d77f56	\\x000000000000030c	10	0	payto://x-taler-bank/bank.test.taler.net/368	account-1	1566376792000000
30	\\x77e1ae7a8bfaadc974396088d2fd22fee5398df641a7c3dba0760765875cf6b5	\\x000000000000030a	10	0	payto://x-taler-bank/bank.test.taler.net/367	account-1	1566373449000000
31	\\xdd6e5ecaad109e27520aacc88c39cc4830235f280e8bd11779f38ebee15b237f	\\x0000000000000307	10	0	payto://x-taler-bank/bank.test.taler.net/366	account-1	1566333832000000
32	\\xc856b9453e72fc92eeecf9614cba6acfdfb67a39d1f1017b59803ec0f8f5f8ad	\\x0000000000000305	10	0	payto://x-taler-bank/bank.test.taler.net/365	account-1	1566333792000000
33	\\x119efdc91109466f9d6c8bcf33f956d0046b01380ce66b44ebc3a2902d827d89	\\x0000000000000303	10	0	payto://x-taler-bank/bank.test.taler.net/364	account-1	1566333684000000
34	\\x38cc57b994cf977e00c6c4c25357796e9c2d79b44ce890ce49925cdc6c3d54ac	\\x0000000000000301	10	0	payto://x-taler-bank/bank.test.taler.net/363	account-1	1566332441000000
35	\\x0f352c26485d153ab1654b49a06dc5a47a0b4a14bf4a42cb4cbd18b87fb07374	\\x00000000000002ff	10	0	payto://x-taler-bank/bank.test.taler.net/362	account-1	1566331804000000
36	\\xa2f9f8326db9d373b252fcc3a0401bc85b3e97618dc3a432487ef38cd9a6517a	\\x00000000000002fc	10	0	payto://x-taler-bank/bank.test.taler.net/361	account-1	1566330461000000
37	\\x46e452f1184d8f6d218534b68b79b8cf6143f1ebaf118a9773546aa200996955	\\x00000000000002f9	10	0	payto://x-taler-bank/bank.test.taler.net/360	account-1	1566330320000000
38	\\x47dbd1fbb39cee3d39c117e376c472fa0d0fc6fceccd5f5e978bace5a6af0ab0	\\x00000000000002f6	10	0	payto://x-taler-bank/bank.test.taler.net/359	account-1	1566330086000000
39	\\x5941c4d722de161c804086ea30952008b7dd1a6aaf10ef708e2fa122102bae7b	\\x00000000000002f3	10	0	payto://x-taler-bank/bank.test.taler.net/358	account-1	1566329229000000
40	\\x051cbec08070f5a75e6de51d35e1aeb7b01a36036a141d2066181092d1d39b11	\\x00000000000002f1	10	0	payto://x-taler-bank/bank.test.taler.net/357	account-1	1566328595000000
41	\\x69cff834caa39abbb70820d036158ce6cd3a7f99cb8cec263337660b7383bcee	\\x00000000000002ec	10	0	payto://x-taler-bank/bank.test.taler.net/356	account-1	1566326490000000
42	\\x6874b7482af6d0ad81a6d31e6fd08c7ab18503c28e053bda598bfd0acb180c7e	\\x00000000000002e9	10	0	payto://x-taler-bank/bank.test.taler.net/355	account-1	1566326185000000
43	\\xdeaaddb0ca6611d9ed384e3b729028fcc22d2fa5764e3843aad3172958ef79d3	\\x00000000000002e7	10	0	payto://x-taler-bank/bank.test.taler.net/354	account-1	1566325818000000
44	\\xcbeb4efeee8f755ad46a4cbbe367284d0a31e8355b703eaf3c62a90c25bb6815	\\x00000000000002e4	10	0	payto://x-taler-bank/bank.test.taler.net/353	account-1	1566320369000000
45	\\xa044250c7644a8664c2d7dd4f4146946c7d7a74cc9d3c72f24861cca285e515e	\\x00000000000002e0	10	0	payto://x-taler-bank/bank.test.taler.net/352	account-1	1566316221000000
46	\\x9ad482c0b94c3fe5403c0093d5609a77e459422795cc0ad7b091f6a28039c281	\\x00000000000002de	10	0	payto://x-taler-bank/bank.test.taler.net/351	account-1	1566316062000000
47	\\x06f725b34ff44ea72a88e0d72d9c754462176850b63841e5ac62eeaa0107da8e	\\x00000000000002da	10	0	payto://x-taler-bank/bank.test.taler.net/350	account-1	1566313444000000
48	\\x4aba78fd0c360bd6bdfb1be8c0033adc09d669e7363ff4f75c7addbead866087	\\x00000000000002d8	10	0	payto://x-taler-bank/bank.test.taler.net/349	account-1	1566312135000000
49	\\x003756a82312c1f165d22735a4d91a0931970335d69739be893422b3630bd5df	\\x00000000000002d6	10	0	payto://x-taler-bank/bank.test.taler.net/348	account-1	1566312049000000
50	\\x7274923e113464192d274534a3b8dd38572393cf8b6b9a26973ce0c657f830fd	\\x00000000000002d4	10	0	payto://x-taler-bank/bank.test.taler.net/347	account-1	1566300097000000
51	\\xb353ec37ab0e6c7b624ae1779404f65f4b7c3dc601a72ca2e0d7f23633946144	\\x00000000000002d2	10	0	payto://x-taler-bank/bank.test.taler.net/346	account-1	1566300079000000
52	\\xf6157d960f7b08f4ecd45e8f856090fcb22e069858394a4e7fc97488a88852a5	\\x00000000000002d0	10	0	payto://x-taler-bank/bank.test.taler.net/345	account-1	1566300069000000
53	\\x14a56bea0d1606f7636eb8ddcbbfcd8a9479130b22589f154e37ee1575842e1e	\\x00000000000002ce	10	0	payto://x-taler-bank/bank.test.taler.net/344	account-1	1566297956000000
54	\\x3eceb3f3a13e966853b828a49921188a0305ccfc88be178f2a76a7e210f174ec	\\x00000000000002cc	10	0	payto://x-taler-bank/bank.test.taler.net/343	account-1	1566297947000000
55	\\xf939b9ad110e76af9ee82c5924c812709f610e73f651a120b7b93a35ad8a9462	\\x00000000000002ca	10	0	payto://x-taler-bank/bank.test.taler.net/342	account-1	1566297933000000
56	\\xfefdc664b156a8956c22392708056f7771beb50eef224383e7be4e7178a6a8bb	\\x00000000000002c8	10	0	payto://x-taler-bank/bank.test.taler.net/341	account-1	1566297922000000
57	\\x0e2d0beab43b0b4fd20157e8b373f21b1fee2a513ebe0fcd18464bfe22889272	\\x00000000000002c6	10	0	payto://x-taler-bank/bank.test.taler.net/340	account-1	1566297730000000
58	\\x0425ba60520bbc67ea59dd44fdac94d44aec328d4a504f9a96cd7115d2d7718b	\\x00000000000002c4	10	0	payto://x-taler-bank/bank.test.taler.net/339	account-1	1566297601000000
59	\\x6e9d183ab868e7ff9d40138dd763896cb8ee9b230e2de94f73b0d788b738f8a4	\\x00000000000002c2	10	0	payto://x-taler-bank/bank.test.taler.net/338	account-1	1566245473000000
60	\\x813db9bd108f103f010eee5c9347a0f8d36da0076ecdfc2aef7e02d643234196	\\x00000000000002c1	10	0	payto://x-taler-bank/bank.test.taler.net/337	account-1	1566245473000000
61	\\x59c56af7431f2115a0c22aa89892d170a9a9471db5014e8a824fbc19dcc2d843	\\x00000000000002c0	10	0	payto://x-taler-bank/bank.test.taler.net/335	account-1	1566245473000000
62	\\x53d4ea53beca2041bb9b7885f1bf52fbac6b87c44ee7c27b8d5e9eb6d17cc0e5	\\x00000000000002bf	10	0	payto://x-taler-bank/bank.test.taler.net/336	account-1	1566245473000000
63	\\xfe59643d79bcc5ecf39a4fda8016c47fd7c8c3635f1bba0a7f6e0c13c134a4b8	\\x00000000000002be	10	0	payto://x-taler-bank/bank.test.taler.net/334	account-1	1566245472000000
64	\\xccc34040dbcf81f0f68cf8c23a5c381c48a8819bf7f0f2d83b24c409023361e6	\\x00000000000002b8	10	0	payto://x-taler-bank/bank.test.taler.net/333	account-1	1566245061000000
65	\\x9abf75e6216b8039d914aa14b8c6ef77952b49f8f4b25cc29ee0a6e0cacbfc70	\\x00000000000002b6	10	0	payto://x-taler-bank/bank.test.taler.net/332	account-1	1566245006000000
66	\\x76c21837710c2e390b9fe23674f581e87e07ce96e4972c1af82ec1a0847ae95d	\\x00000000000002b4	10	0	payto://x-taler-bank/bank.test.taler.net/331	account-1	1566244957000000
67	\\xc725d349c67fd479c2c512e29e33055753da64877d33335fb1b2432e7a32d999	\\x00000000000002b2	10	0	payto://x-taler-bank/bank.test.taler.net/330	account-1	1566244950000000
68	\\x2af399b74d0691fb36c2e2b6c00631694b51607c332fd97f29a8d4ecca5c7ef6	\\x00000000000002b0	10	0	payto://x-taler-bank/bank.test.taler.net/329	account-1	1566244024000000
69	\\xd58aa182bdc6b8f4463bf392e0bb003325bfb653ad7c18f32d39e38fd20e7ed0	\\x00000000000002ae	10	0	payto://x-taler-bank/bank.test.taler.net/328	account-1	1566243569000000
70	\\xe7ac2051b945e977cdb2a613d4434c04c26dd3b102a1bc82d29d08a81ae86b2b	\\x00000000000002ac	10	0	payto://x-taler-bank/bank.test.taler.net/327	account-1	1566243539000000
71	\\x2f45b07e937fd0a1feb3d9fcc7aa6c149a96e84338fa251f53f148ceca4b96d5	\\x00000000000002aa	10	0	payto://x-taler-bank/bank.test.taler.net/326	account-1	1566243321000000
72	\\x204f1f80cd9e66810bbf74e58cb1838d904ee5941ed205aba33bf9f1e236e49d	\\x00000000000002a8	10	0	payto://x-taler-bank/bank.test.taler.net/325	account-1	1566243309000000
73	\\xdb41e9f1ad98bb9bf42c952b770c69c4019fa6c4524f77f92cb4189e96bca115	\\x00000000000002a6	10	0	payto://x-taler-bank/bank.test.taler.net/324	account-1	1566242800000000
74	\\x30fba371e70b4ebc0a40f952c43d50d18719b36d310b891059808ea5a21c3710	\\x00000000000002a4	10	0	payto://x-taler-bank/bank.test.taler.net/323	account-1	1566242788000000
75	\\x26bd0786ce312f0aec4cc46d8c2a0368974f065f61ecc345c713aa0fc8fa5c2a	\\x00000000000002a2	10	0	payto://x-taler-bank/bank.test.taler.net/322	account-1	1566242772000000
76	\\x3e6809817ca4477f5ec4ac74c0bbb76e48448176043a2cb456b0dc455a79632f	\\x00000000000002a0	10	0	payto://x-taler-bank/bank.test.taler.net/321	account-1	1566242748000000
77	\\x5a374956e5ff8785db62f4deccdc41d65aad3bb1927344122447acc016aa44f9	\\x000000000000029e	10	0	payto://x-taler-bank/bank.test.taler.net/320	account-1	1566242656000000
78	\\xc3c6006069c05603856ac9e6bf25192f6684467721b96350bdfabc8008bbec9d	\\x000000000000029c	10	0	payto://x-taler-bank/bank.test.taler.net/319	account-1	1566242538000000
79	\\xa5d0664f9f0fdfb4407c6e90712d57e98e824dc1bbc75c79620f68f97d8fd5ca	\\x000000000000029a	10	0	payto://x-taler-bank/bank.test.taler.net/318	account-1	1566242396000000
80	\\x7039453d2727338652a5432ffca59220fe15ebb3e09399d238215311f015107d	\\x0000000000000298	10	0	payto://x-taler-bank/bank.test.taler.net/317	account-1	1566242338000000
81	\\x3428bcdcd2725e6038bba0d5e3189f3caf0c342d55a25d02be539d6ab97cc20c	\\x0000000000000296	10	0	payto://x-taler-bank/bank.test.taler.net/316	account-1	1566241294000000
82	\\x22c98e04feee74f42fba4ab3f00627a118c4d8279df397776bb785903e07ab1e	\\x0000000000000294	10	0	payto://x-taler-bank/bank.test.taler.net/315	account-1	1566240636000000
83	\\x59998f08f6e8f35ea10c51c5700aae79b9f6d6b5f684a377a7f5b2fa6a64a269	\\x0000000000000292	10	0	payto://x-taler-bank/bank.test.taler.net/314	account-1	1566240236000000
84	\\x10dd95f3a5de768b7690839be29f2d8974b0654d13f20b5f7437d768d14f51bc	\\x0000000000000290	10	0	payto://x-taler-bank/bank.test.taler.net/313	account-1	1566240159000000
85	\\x87a6b79a88d73b92f7169010d401421224a6a24b67f40471c4a4761cc0f0bfb2	\\x000000000000028e	10	0	payto://x-taler-bank/bank.test.taler.net/312	account-1	1566240037000000
86	\\x33396f85d648a84af67f09d35532751fa8d90e22b218d0798bd444b12ddac3a2	\\x000000000000028c	10	0	payto://x-taler-bank/bank.test.taler.net/311	account-1	1566239308000000
87	\\x91837011a5b129b2a1ecdaf92cf0fe157479e26044f16705f06aab77c7157879	\\x000000000000028a	10	0	payto://x-taler-bank/bank.test.taler.net/310	account-1	1566239253000000
88	\\x789a55c8a99464a9a7c9c3640e917aa0b4ee760cd49850b1c2c0173480e1486d	\\x0000000000000288	10	0	payto://x-taler-bank/bank.test.taler.net/309	account-1	1566239010000000
89	\\xed4538ca12e87d07f8a036054059c92f875b1fdf5f5cbe12a0dd8c72efc0ef1b	\\x0000000000000286	10	0	payto://x-taler-bank/bank.test.taler.net/308	account-1	1566238980000000
90	\\x1c524fbbb8045eaff17a3935d67f85234f342c943933fb1a0e827f99330bcf05	\\x0000000000000284	10	0	payto://x-taler-bank/bank.test.taler.net/307	account-1	1566238913000000
91	\\x29bb82bedb668a22791007266113a81977b54d9524bfb195812eb4637f449d1d	\\x0000000000000282	10	0	payto://x-taler-bank/bank.test.taler.net/306	account-1	1566238897000000
92	\\xcd9a6ca7e8cf43aabcf1b7e3403139c2ac1d990f78334360d326660ceec8df15	\\x0000000000000280	10	0	payto://x-taler-bank/bank.test.taler.net/305	account-1	1566238783000000
93	\\xbaf74548c792dea461ca5aaf83a69b3a7c9c220a910ab45c286a1ae7df7f1d77	\\x000000000000027e	10	0	payto://x-taler-bank/bank.test.taler.net/304	account-1	1566238056000000
94	\\x7e63f67c1940a9b23d13697aa6582a1fe69581bbd2f1c5098cd3561a989eba3a	\\x000000000000027c	10	0	payto://x-taler-bank/bank.test.taler.net/303	account-1	1566236519000000
95	\\x59bfd4e6dbaa2dfdb58244208e88533a7849ceb3e3e235e427d516ccd69ac5fc	\\x000000000000027a	10	0	payto://x-taler-bank/bank.test.taler.net/302	account-1	1566236071000000
96	\\x268c99db0a689c8fe3544e83745f2c5e3d476ae6e6abe8b62babdcdc62208ee1	\\x0000000000000278	10	0	payto://x-taler-bank/bank.test.taler.net/301	account-1	1566232865000000
97	\\xe7e3ffe3752203bbfa38003e5c6ea51c395c2aa4056b258461f0b24dfbc5a773	\\x0000000000000276	10	0	payto://x-taler-bank/bank.test.taler.net/300	account-1	1566232802000000
98	\\x3b34626e4bd1d6a90a17685dffa13b1de5eaaaefee9dff5b62531b6f9c2b25cb	\\x0000000000000274	10	0	payto://x-taler-bank/bank.test.taler.net/299	account-1	1566232151000000
99	\\x1c50880a086245f96b09dbc9262696d31570b359e9aa847c62dc724e1bbc3904	\\x0000000000000272	10	0	payto://x-taler-bank/bank.test.taler.net/298	account-1	1566212292000000
100	\\xe532b4eaa3a651af35fe482844cf4ee58d9933594e1d07348db46d507d44d136	\\x0000000000000270	10	0	payto://x-taler-bank/bank.test.taler.net/297	account-1	1566211792000000
101	\\xa9508cf654f874b6ac7c137c67a34daadd7566c01452359b0c1974fd866c88a9	\\x000000000000026d	10	0	payto://x-taler-bank/bank.test.taler.net/296	account-1	1566162797000000
102	\\xb6dd4e754c04f7f454fc76eeea421a02db0ab80cadd6e095913aa6a467d08df8	\\x000000000000026a	10	0	payto://x-taler-bank/bank.test.taler.net/295	account-1	1566162322000000
103	\\xc484befd64ce803855834b06e849343331d654f98d2c681c28ae2547533afb07	\\x0000000000000266	10	0	payto://x-taler-bank/bank.test.taler.net/294	account-1	1566162199000000
104	\\x9222bf7c3c95fb9eda6f228d44573407bfbd4c440351830f2d770ac84ab44e36	\\x0000000000000264	10	0	payto://x-taler-bank/bank.test.taler.net/293	account-1	1566162183000000
105	\\x9c377c7a5181ac3a9cd7609eea358428156380615afc3730f87bee265213a756	\\x0000000000000261	10	0	payto://x-taler-bank/bank.test.taler.net/292	account-1	1566161708000000
106	\\xb800e06c8b550082d031a22fde02d8654c27fc7e778c33ab8296349365f72347	\\x000000000000025f	10	0	payto://x-taler-bank/bank.test.taler.net/291	account-1	1566161657000000
107	\\xe57325eea480ac0c9b3434a30b1952ba7deac6d00106b6b9974878edcdf40e7e	\\x000000000000025c	10	0	payto://x-taler-bank/bank.test.taler.net/290	account-1	1566161534000000
108	\\x406b9add395d06468c5828d686b1e78e58f7b6972a25201f452626a4f7dd7d7a	\\x000000000000025a	10	0	payto://x-taler-bank/bank.test.taler.net/289	account-1	1566161473000000
109	\\x89470dee4c3110f9cdc4b7f851b003d1de5417379f473bbdb57454e1997c0a0c	\\x0000000000000256	10	0	payto://x-taler-bank/bank.test.taler.net/287	account-1	1566161289000000
110	\\xda46933e2a492f1c30d56d18176082a5bfb1b9b073abd0cce747f5111137a8b1	\\x0000000000000253	10	0	payto://x-taler-bank/bank.test.taler.net/286	account-1	1566161223000000
111	\\x4c7d9dde23ca42d415f01730f0b19c4ac60560c40095652048b08d2633aa2810	\\x0000000000000251	10	0	payto://x-taler-bank/bank.test.taler.net/285	account-1	1566161205000000
112	\\x5e293aeb6c08a5bcbb1e61df798220451f07f36d00affaa9190775a5f7180caa	\\x000000000000024f	10	0	payto://x-taler-bank/bank.test.taler.net/284	account-1	1566160855000000
113	\\xefe525ec2968cd6845b8c92b02a73c0a0af9af88de003d82ca12deb9e22e9dc0	\\x000000000000024d	10	0	payto://x-taler-bank/bank.test.taler.net/283	account-1	1566160503000000
114	\\xaa87f84bcc4744d63b96cff8436a5f88405dfb5f22a39fd9f9552e8633de9942	\\x000000000000024b	10	0	payto://x-taler-bank/bank.test.taler.net/282	account-1	1566160323000000
115	\\x6ded4375cd71b389104b9096226a89fa1a1846cb7af324842e4a62ca4f32072d	\\x0000000000000249	10	0	payto://x-taler-bank/bank.test.taler.net/281	account-1	1566160271000000
116	\\x1b0e3b898562b405d5989b3617178871f6a0e73f1ca2ade7c293ed29ad760c72	\\x0000000000000246	10	0	payto://x-taler-bank/bank.test.taler.net/280	account-1	1566159278000000
117	\\xd7a6cb733790839a79bed1e9d2ee4b7d8fd66ae70f1645c84edbc535b0d77e33	\\x0000000000000244	10	0	payto://x-taler-bank/bank.test.taler.net/279	account-1	1566159163000000
118	\\xad658d529cb575c0d1d025056f724ad59c2f0efadfc052d4300d4066669f5f20	\\x0000000000000242	10	0	payto://x-taler-bank/bank.test.taler.net/278	account-1	1566157690000000
119	\\xe0b3f02bf670cd068c2483b252c2a47ca204d46b6821ea94f58444345d2004c7	\\x000000000000023f	10	0	payto://x-taler-bank/bank.test.taler.net/277	account-1	1566152613000000
120	\\x66af8e219c20e49afe73128b8687a39e0b8a36f6ce79286714c058e0efdd9669	\\x000000000000023d	10	0	payto://x-taler-bank/bank.test.taler.net/276	account-1	1566152522000000
121	\\x7a218bdf8b9e773794613b3db323fcc95867819c59e24726f7dcf4a13be842d9	\\x000000000000023b	10	0	payto://x-taler-bank/bank.test.taler.net/275	account-1	1566150042000000
122	\\x33453afe5db166f0aa10e4acda686dba022990a845753f3d6d06a61b24cd46a5	\\x0000000000000239	10	0	payto://x-taler-bank/bank.test.taler.net/274	account-1	1566149967000000
123	\\x6b7cede5ceb81248262a13b1d86f2d3b392c18e0c93788fecb5284917523a57d	\\x0000000000000237	10	0	payto://x-taler-bank/bank.test.taler.net/273	account-1	1566149930000000
124	\\xb9d4fdfed4243cf830cebc3195b0d2659649d8a8b4aa885301f83410ae0024e4	\\x0000000000000234	10	0	payto://x-taler-bank/bank.test.taler.net/271	account-1	1566149859000000
125	\\xd5da4a1a66b10dc4e12ab7461fe65023ee0ab2bacbef8fff13a0c0a1de15b66d	\\x0000000000000231	10	0	payto://x-taler-bank/bank.test.taler.net/270	account-1	1566138861000000
126	\\x3af59e0132735e05e27b112d6392ee58a11489cf568bbb5c25bb595405521ff3	\\x000000000000022e	10	0	payto://x-taler-bank/bank.test.taler.net/269	account-1	1566138687000000
127	\\x469bf9c86abb396de1863568f5789599dc6a439450f3f1905f6212bad9f4df9a	\\x000000000000022b	10	0	payto://x-taler-bank/bank.test.taler.net/268	account-1	1566138565000000
128	\\xa5b58e2c15151cc21b2a6d64a01f9358d6c0850067a34f9162351ecac4a57222	\\x0000000000000228	10	0	payto://x-taler-bank/bank.test.taler.net/267	account-1	1566138394000000
129	\\x271ee8933b0258c5551dcdc999da5b708b36ed97dad53800c45bc72d49a39cd7	\\x0000000000000225	10	0	payto://x-taler-bank/bank.test.taler.net/266	account-1	1566138213000000
130	\\x0ccff4d54e80cb3dd68f6e916973508e77051caaae735dd03bc306cfe0afae74	\\x0000000000000222	10	0	payto://x-taler-bank/bank.test.taler.net/265	account-1	1566138073000000
131	\\x6363234157eab234dc540d977e06cf6681bae43e7d2d87beed4739c08f6377c6	\\x000000000000021f	10	0	payto://x-taler-bank/bank.test.taler.net/264	account-1	1566137941000000
132	\\x294eb33578c0dd1135de2b6cc411cd59881a9add9f786995118673899e9c3e87	\\x000000000000021c	10	0	payto://x-taler-bank/bank.test.taler.net/263	account-1	1566137744000000
133	\\xa9d62c09b31f66606af346d0c7e64f77a92954a999e50ffcf574a217e8cb31e4	\\x0000000000000219	10	0	payto://x-taler-bank/bank.test.taler.net/262	account-1	1566137374000000
134	\\xe4d05ad2b0b5e27f3695806e468d54592cd5405e281485196ffa234e63fc68cb	\\x0000000000000216	10	0	payto://x-taler-bank/bank.test.taler.net/261	account-1	1566137157000000
135	\\xf0fda0cd3dda1d31a598c5b9e850a7c54456f8c482af6c1f70b380fd3a659c46	\\x0000000000000213	10	0	payto://x-taler-bank/bank.test.taler.net/260	account-1	1566136948000000
136	\\x695a2de3e0bfdee784b2409b58d18e069f55768745622205a4cb2a99016d976e	\\x0000000000000210	10	0	payto://x-taler-bank/bank.test.taler.net/259	account-1	1566136833000000
137	\\x59ba84ccb16e2a8c0197ae704c9805452d9f91203f0e2a2414865fb43b11b60d	\\x000000000000020d	10	0	payto://x-taler-bank/bank.test.taler.net/258	account-1	1566136582000000
138	\\xf7afb294f813be7682bda81a109f8cebc21c7dde782f897359ce3c4503a915f3	\\x000000000000020a	10	0	payto://x-taler-bank/bank.test.taler.net/257	account-1	1566135337000000
139	\\xa242dcf952f7a0284907e66479db7510f74fff91ce0c318c69e30cc42ac22b28	\\x0000000000000207	10	0	payto://x-taler-bank/bank.test.taler.net/256	account-1	1566135008000000
140	\\xa46479979b59dac9665291fe8c99f56fafd020ab6378518b24a7de4162c0a8fe	\\x0000000000000204	10	0	payto://x-taler-bank/bank.test.taler.net/255	account-1	1566133668000000
141	\\x9307406b793081d213b291e1220b05afa8f8dbe8f0a297729a78228d7b4f5363	\\x0000000000000202	10	0	payto://x-taler-bank/bank.test.taler.net/254	account-1	1566133653000000
142	\\x935c559fcf339b66ea197098e4a7165a373cada72ce6326c6649f21bb2b6958a	\\x00000000000001fe	10	0	payto://x-taler-bank/bank.test.taler.net/252	account-1	1566062283000000
143	\\x44884e596728d1764a441c476b6d1600f4e172b82224579a7a9c96d0264db3f3	\\x00000000000001fb	10	0	payto://x-taler-bank/bank.test.taler.net/251	account-1	1566061181000000
144	\\xa47e3ec298a912ce770d6f76505ab6bad3bc4f43012ea0a7d02018359ced5e77	\\x00000000000001f6	10	0	payto://x-taler-bank/bank.test.taler.net/247	account-1	1566060055000000
145	\\xec426b2ba4cd2036d645ace13c17ec24d034c47123f9b7259b19bddd75bbc282	\\x00000000000001f4	10	0	payto://x-taler-bank/bank.test.taler.net/246	account-1	1566060049000000
146	\\xfa6430afd028e2230004a93f5f989f716b04f07f22075c0f71f0de7fb885556d	\\x00000000000001f2	10	0	payto://x-taler-bank/bank.test.taler.net/245	account-1	1566060036000000
147	\\x59d46300018a3020106c7635630a580763c94359e41bb30381a5234ffb259462	\\x00000000000001ef	10	0	payto://x-taler-bank/bank.test.taler.net/243	account-1	1566049629000000
148	\\x3735705df5fdb4391e2c7308b6efd8aefb2cd17feed80c7d7409b062c4a7020b	\\x00000000000001ec	10	0	payto://x-taler-bank/bank.test.taler.net/241	account-1	1566049589000000
149	\\xb7c7fa0443475b8a8f7612bfeb862c3e27c75ef08c2ed9f4ee524e95ba215155	\\x00000000000001ea	10	0	payto://x-taler-bank/bank.test.taler.net/240	account-1	1566048975000000
150	\\xe5021623374e4f73a1021b432393316a64b9ff7d8a55b08fa4889bc3ea14cd5a	\\x00000000000001e8	10	0	payto://x-taler-bank/bank.test.taler.net/239	account-1	1566044441000000
151	\\x9c9aee06fecf3caa3de9173ae0afb78a3df2361f4a1c98bbaa2fa124dc774d3b	\\x00000000000001e6	10	0	payto://x-taler-bank/bank.test.taler.net/238	account-1	1565999485000000
152	\\x0f44803fb16fff27d5b00d0ff093c089dc7671feef732783d98b6057c78795ee	\\x00000000000001e4	10	0	payto://x-taler-bank/bank.test.taler.net/237	account-1	1565999477000000
153	\\xcb5d2f41dae0505e076d87da9c209b574708290b94ee53eb7c58b719ff9f8e4c	\\x00000000000001e2	10	0	payto://x-taler-bank/bank.test.taler.net/236	account-1	1565999460000000
154	\\xd66e178d92b2c62fec79634fb20a21c5700507111b36bde3a838a9e6afdcd962	\\x00000000000001e0	10	0	payto://x-taler-bank/bank.test.taler.net/235	account-1	1565999360000000
155	\\xd0afe6a042bd0d72502690e9b60cc521f101fe75eb854595e3679b3ff1d1f913	\\x00000000000001de	10	0	payto://x-taler-bank/bank.test.taler.net/234	account-1	1565999354000000
156	\\x5180d87442313b7237f1be51fb363524f197ee48e304d04b33f4f46aec114410	\\x00000000000001dc	10	0	payto://x-taler-bank/bank.test.taler.net/233	account-1	1565999301000000
157	\\x6189f786c04b5e735b639da1779c9806f86c4dd9324d92cb9ef9dbc6fc515b7b	\\x00000000000001da	10	0	payto://x-taler-bank/bank.test.taler.net/232	account-1	1565999283000000
158	\\x866ec7f2b2123ead9e3500c0ff1f83e386f392c49e2f163ffe697ffd41e0f90d	\\x00000000000001d8	10	0	payto://x-taler-bank/bank.test.taler.net/231	account-1	1565999276000000
159	\\x99ecea1c2119254d96d98ef43424b4cbe314fb5bb440e838f6a8a140301bce6d	\\x00000000000001d6	10	0	payto://x-taler-bank/bank.test.taler.net/230	account-1	1565998955000000
160	\\x99fbc0d1d5729fd3f0b33736844196fff3d8d278053a60b9b27b47916c3ddd0d	\\x00000000000001d4	10	0	payto://x-taler-bank/bank.test.taler.net/229	account-1	1565998910000000
161	\\x5a385ed4779a13d58684098b70882788437bab11102b38ad277aef41baada706	\\x00000000000001d2	10	0	payto://x-taler-bank/bank.test.taler.net/228	account-1	1565998663000000
162	\\xb52d325f032b2791d504a532ef9834b033e8ef87eb597bc1a26aa89a2365d212	\\x00000000000001d0	10	0	payto://x-taler-bank/bank.test.taler.net/227	account-1	1565998636000000
163	\\x5b63460c0b825d0eaa613f1fca865184b48d04dc105437eb67a267109daf0f02	\\x00000000000001ce	10	0	payto://x-taler-bank/bank.test.taler.net/226	account-1	1565998626000000
164	\\x66b219ab9cd23f25e4a3d93fcc72bd87fed8ee4f85fefd13df14c8942018584f	\\x00000000000001cc	10	0	payto://x-taler-bank/bank.test.taler.net/225	account-1	1565998504000000
165	\\xbdac584b91a8b1e39cce9f2063853822e248b424f3e68d46af1c6763a7a8c77d	\\x00000000000001ca	10	0	payto://x-taler-bank/bank.test.taler.net/224	account-1	1565998007000000
166	\\x8cd98bc82b641ec56a1685ce5e308cf2657281fa219d6325a66221bb16fff090	\\x00000000000001c8	10	0	payto://x-taler-bank/bank.test.taler.net/223	account-1	1565997710000000
167	\\x82018291d5681e391d52e11f0fe99dd7af9ba088ef8a04703d47c39c1131661a	\\x00000000000001c6	10	0	payto://x-taler-bank/bank.test.taler.net/222	account-1	1565997578000000
168	\\xc77e537ef13fd7c51e61cef89d2022c16b0686ff1c55764969a96ee4c87a3052	\\x00000000000001c4	10	0	payto://x-taler-bank/bank.test.taler.net/221	account-1	1565997290000000
169	\\x1d76762600f8bd3f4795f62f03add0c65566e6688292c8646a6b5da12cacf1dc	\\x00000000000001c2	10	0	payto://x-taler-bank/bank.test.taler.net/220	account-1	1565997147000000
170	\\xfcfcdc8cd2791777397249d4c3da52e1863f55ad0c6882e2d751bbd405302095	\\x00000000000001c0	10	0	payto://x-taler-bank/bank.test.taler.net/219	account-1	1565997130000000
171	\\x3f619c26dc967addb49cae026b9f91709a030e15addc6ca6a5127e72cc930001	\\x00000000000001be	10	0	payto://x-taler-bank/bank.test.taler.net/218	account-1	1565997000000000
172	\\xf5d83929494f27bfa0a816711d37f72cb65f822e8de11668fc52aebf6ce55682	\\x00000000000001bc	10	0	payto://x-taler-bank/bank.test.taler.net/217	account-1	1565996975000000
173	\\xa4d33108e549c5f07de36bb4d46529b1e368ace2ad4c34606eb1dfff199efd6d	\\x00000000000001ba	10	0	payto://x-taler-bank/bank.test.taler.net/216	account-1	1565996970000000
174	\\x7c002a0774ba18250483639e653c545867bd19c9a7e5e469f6867be5322a772b	\\x00000000000001b8	10	0	payto://x-taler-bank/bank.test.taler.net/215	account-1	1565996963000000
175	\\xb4de597a51faf7dba502d6b7d4d08809f423fe4e25218590e3fb05ccfc2824cd	\\x00000000000001b6	10	0	payto://x-taler-bank/bank.test.taler.net/214	account-1	1565996959000000
176	\\xf7719f9def9a2234ca81e166c0233b2468cbacd10b699d3cf61a6bd46c032a81	\\x00000000000001b4	10	0	payto://x-taler-bank/bank.test.taler.net/213	account-1	1565996913000000
177	\\x6bf8404ce889b919973f0dadfd10a1497e3fd6e794b7e64c6df8011a37511623	\\x00000000000001b2	10	0	payto://x-taler-bank/bank.test.taler.net/212	account-1	1565996907000000
178	\\x5608e9a6b49d5da56c6e306f6f35d37d71f5cd1f709a4ea4403ca1335b952dbb	\\x00000000000001b0	10	0	payto://x-taler-bank/bank.test.taler.net/211	account-1	1565996895000000
179	\\x093d02b628a9974e33fcf8a6d5fc6d74c70427960d524fd8674977d819163e72	\\x00000000000001ae	10	0	payto://x-taler-bank/bank.test.taler.net/210	account-1	1565996886000000
180	\\xbb61ab42b47a032fb8809a0fd1b2cd13f509c1e922863d9e84ac188bba2ba4a2	\\x00000000000001ac	10	0	payto://x-taler-bank/bank.test.taler.net/209	account-1	1565996871000000
181	\\x231459f058a65e3e280e888cec88737c2452fcdd1317322b92898372c8eee53f	\\x00000000000001aa	10	0	payto://x-taler-bank/bank.test.taler.net/208	account-1	1565996867000000
182	\\xb800dddd6ca1525b45937f3638762afba97df01c8fd68589b332cc6af8c17f6b	\\x00000000000001a8	10	0	payto://x-taler-bank/bank.test.taler.net/207	account-1	1565996297000000
183	\\x6edc8a322e33a069a0c0fe3ad6461c677dee1f9445deb38e243ce53bce2c5606	\\x00000000000001a6	10	0	payto://x-taler-bank/bank.test.taler.net/206	account-1	1565995725000000
184	\\x12fba7c03a70173a50b46399a5d848b0639b0c59f4465af5a923fecf0306356b	\\x00000000000001a4	10	0	payto://x-taler-bank/bank.test.taler.net/205	account-1	1565992036000000
185	\\x8b90d565724439977467feb78f95468ca325a6a583ec42eb9e528ed9ee67acfd	\\x00000000000001a1	10	0	payto://x-taler-bank/bank.test.taler.net/204	account-1	1565986862000000
186	\\x52b90c06be123b6979ec5d9ba1032013ce60a91dacddbecafee7302d9ce709b7	\\x000000000000019e	10	0	payto://x-taler-bank/bank.test.taler.net/203	account-1	1565981306000000
187	\\x92077db0eb754e8074b64199e68906e04614d790042aed5d9cc84db1f80e8aca	\\x000000000000019b	5	0	payto://x-taler-bank/bank.test.taler.net/201	account-1	1565960310000000
188	\\x31b91dbf4e89506f09d918dffa3a1800813f8e7fe1a7356c3a92681f62b9066f	\\x0000000000000198	10	0	payto://x-taler-bank/bank.test.taler.net/200	account-1	1565952928000000
189	\\x6e846e63f3d4d2639febf8c3ef0bc3ff60acdb5d81de4d83e02d5ae36885a82b	\\x0000000000000195	10	0	payto://x-taler-bank/bank.test.taler.net/199	account-1	1565952822000000
190	\\xd569191f67bff925e2e14f1a15e5392546b5bbc64ff1e7de72ad32c47a3959c0	\\x0000000000000192	10	0	payto://x-taler-bank/bank.test.taler.net/198	account-1	1565952649000000
191	\\xefeeaed84eef3241f90f8713642986f5a806911a899d461f4c88e8b0af61ffe4	\\x000000000000018f	10	0	payto://x-taler-bank/bank.test.taler.net/197	account-1	1565952620000000
192	\\xc1d651a7160f70ad594d9ee5cd188d42687fe99db4c41a61fe82633e626fa083	\\x000000000000018d	10	0	payto://x-taler-bank/bank.test.taler.net/196	account-1	1565952610000000
193	\\xe57f5d46511d0e766c18a6ca9fc54d3283a2bb102eb8bfdf8e32266c74bcc241	\\x000000000000018b	10	0	payto://x-taler-bank/bank.test.taler.net/195	account-1	1565944892000000
194	\\xf04ba9bc678428207d91776a9464b3b108b58c38fa268bc1b7a227eda49819e8	\\x0000000000000189	10	0	payto://x-taler-bank/bank.test.taler.net/194	account-1	1565944821000000
195	\\xed16aa8942792639654d1f6023e09d1d650f2b8c93a63c1009efe130b00bb1ca	\\x0000000000000186	10	0	payto://x-taler-bank/bank.test.taler.net/193	account-1	1565941630000000
196	\\x0a0d4eb5d1abbb8cea07fee2ba1ed90bd1ebc7e22daf4a368a03cb1ba3ace1ad	\\x0000000000000184	10	0	payto://x-taler-bank/bank.test.taler.net/192	account-1	1565940072000000
197	\\xed3384e769e63bbb3a3b0e7e0d7a695c87cb83beb68a07aea69dbd28a02a00f0	\\x0000000000000181	10	0	payto://x-taler-bank/bank.test.taler.net/191	account-1	1565937383000000
198	\\x6fceae6ef52dfe039f42c029ded6f5083158b76460d1a4415de2a13e0d6b141a	\\x000000000000017e	10	0	payto://x-taler-bank/bank.test.taler.net/190	account-1	1565935796000000
199	\\xe079bd72ea08e0f54d38e00c0eebecf518d7e81b60d03082e929fdf76954aad4	\\x000000000000017c	10	0	payto://x-taler-bank/bank.test.taler.net/189	account-1	1565910146000000
200	\\x9be84bc3757bc122966d499f582bb9f053dd837cffebec5317e28f0076820ac9	\\x000000000000017a	10	0	payto://x-taler-bank/bank.test.taler.net/188	account-1	1565909731000000
201	\\x5e203725f5da7b3a43eb8c55bf3bc7674a8c9aaf19e5706516da2d337a623e83	\\x0000000000000178	10	0	payto://x-taler-bank/bank.test.taler.net/187	account-1	1565909725000000
202	\\xf5d0a679138775b0bd2c7025d52533a4d3c663a2a8e790fbcbf1323c7038edea	\\x0000000000000176	10	0	payto://x-taler-bank/bank.test.taler.net/186	account-1	1565909666000000
203	\\x352ca9fad07eb58ff536e649e5257e8153c2d6388f4b50caaf6464d8c312ffa5	\\x0000000000000174	10	0	payto://x-taler-bank/bank.test.taler.net/185	account-1	1565909597000000
204	\\x2e199e3752fa0de89b8336f28ac07d39e835b663da6d875321332681524ef8b2	\\x0000000000000172	10	0	payto://x-taler-bank/bank.test.taler.net/184	account-1	1565909467000000
205	\\x354145bcdd8f777d8f7450e7364e6546d3b5bb2b81e285ce342e2d57022acb5a	\\x000000000000016f	10	0	payto://x-taler-bank/bank.test.taler.net/183	account-1	1565909394000000
206	\\xf8ad117b767116b4b6ecd1946e5c8258a9d0e26f10f5aeb83a2c96d9a4e801b5	\\x000000000000016c	10	0	payto://x-taler-bank/bank.test.taler.net/182	account-1	1565909086000000
207	\\x2d841e2844b84613d06e1871ce1ff7c7aeb6e6272d643d95cf83b800d83f6fa5	\\x000000000000016a	10	0	payto://x-taler-bank/bank.test.taler.net/181	account-1	1565909049000000
208	\\x099c38804d748d134f237668a8c22970981a1666cee497cab15a5b3761d95fe2	\\x0000000000000167	10	0	payto://x-taler-bank/bank.test.taler.net/180	account-1	1565907603000000
209	\\x0534b703fcf4fb1bcc5c98894919ce8f6c647409c80ecb2f6784ea736f52a258	\\x0000000000000165	10	0	payto://x-taler-bank/bank.test.taler.net/179	account-1	1565907529000000
210	\\x4ef3a8013f6c1fd371954afdf7db5831e2a4b08a24a46d47ce0d0fe71db27450	\\x0000000000000162	10	0	payto://x-taler-bank/bank.test.taler.net/178	account-1	1565907253000000
211	\\x7e5c973417676e8adab516ab8ae8e867a929f1d5b49f19fa01cb129e1333557a	\\x000000000000015f	10	0	payto://x-taler-bank/bank.test.taler.net/177	account-1	1565906353000000
212	\\xdaf21c4d7d0506e761794bfd54286da9cccfbd5dcffec91d4de685ddeb2d9874	\\x000000000000015d	10	0	payto://x-taler-bank/bank.test.taler.net/176	account-1	1565906280000000
213	\\x37e05777be1d12227329799c20ceb6392c437fa7ff2f7cd9b73fb6942d97b674	\\x000000000000015a	10	0	payto://x-taler-bank/bank.test.taler.net/175	account-1	1565905346000000
214	\\xab61e6dc949dd1f35b2bcf8aa92155a61b37dc8ff002513db10988d72c10f85c	\\x0000000000000157	10	0	payto://x-taler-bank/bank.test.taler.net/174	account-1	1565904659000000
215	\\x9d7bdee2ad68d7850d99dc3009925e3fff8faf821c782c75b9e58d8401f492a6	\\x0000000000000154	10	0	payto://x-taler-bank/bank.test.taler.net/173	account-1	1565903993000000
216	\\xfbcab337efa5cad7f030026dd568ce0a9f6b32a3f0647b6c23d9055c4272ae38	\\x0000000000000152	10	0	payto://x-taler-bank/bank.test.taler.net/172	account-1	1565903788000000
217	\\xd24bceae2f137c7a7a33a7e27490f2ee051ca8303fee7d4dd8e78d7a1f0aee62	\\x0000000000000150	10	0	payto://x-taler-bank/bank.test.taler.net/171	account-1	1565903589000000
218	\\x5039d714051dc54f8a12d638d99d6ee2cbba8f84417d239ba13a6dae52a106d8	\\x000000000000014e	10	0	payto://x-taler-bank/bank.test.taler.net/170	account-1	1565903528000000
219	\\xe3885032e24de4aff2214d768134ee11d500559f69b92befe92a9b475fdbbeee	\\x000000000000014c	10	0	payto://x-taler-bank/bank.test.taler.net/169	account-1	1565903455000000
220	\\x92f04e72829581397d5d7af2cfbe8c1eb98769ed2a1dc49f9502e4efb1387ca4	\\x000000000000014a	10	0	payto://x-taler-bank/bank.test.taler.net/168	account-1	1565903383000000
221	\\xcbb9acd062ab443328e6050dbe93e2b8f84c6e2d06b4d98e8aace06251e06033	\\x0000000000000148	10	0	payto://x-taler-bank/bank.test.taler.net/167	account-1	1565903277000000
222	\\xe9cd9bd7e64730ffcca680c79dc186180f44228b2b64146e3e98689c074bf5a7	\\x0000000000000146	10	0	payto://x-taler-bank/bank.test.taler.net/166	account-1	1565903077000000
223	\\xe9475fffced36d5aa6e26073dd28ccc50f2ca4448b3089ecc9c13030abd8f60b	\\x0000000000000144	10	0	payto://x-taler-bank/bank.test.taler.net/165	account-1	1565902856000000
224	\\x87df20e293f6c021efdb3408e1f3121f79a5f1000cbdd3d2b09eade6969f07c8	\\x0000000000000142	10	0	payto://x-taler-bank/bank.test.taler.net/164	account-1	1565902784000000
225	\\xddb8dfe63ae9995f4846435d10bbb0b27887c5bd911082781c4efedd0df40f67	\\x0000000000000140	10	0	payto://x-taler-bank/bank.test.taler.net/163	account-1	1565902533000000
226	\\xf236ae1b03f5896bb57da63548778c065c31c5d30ca2e1b257b98e8a40a1f498	\\x000000000000013e	10	0	payto://x-taler-bank/bank.test.taler.net/162	account-1	1565901819000000
227	\\x245663abb3929008134cfadcd585d8c30189eac85a59ac3f63b57ee150394031	\\x000000000000013c	10	0	payto://x-taler-bank/bank.test.taler.net/161	account-1	1565901629000000
228	\\x7920ef3246557b9add917c3b24df7557e597b9ea132d7a6ade8147463f20d88e	\\x000000000000013a	10	0	payto://x-taler-bank/bank.test.taler.net/160	account-1	1565901302000000
229	\\x383faa3efbad6ba618b9a0518c726b968c093da880aa325e0815c26d302baa8d	\\x0000000000000138	10	0	payto://x-taler-bank/bank.test.taler.net/159	account-1	1565901249000000
230	\\x0c5cd55b9766b103527762452a1e81367c77bf6d24403a15b94ea0fa87904776	\\x0000000000000136	10	0	payto://x-taler-bank/bank.test.taler.net/158	account-1	1565900845000000
231	\\xd0310cbff1f595d844e540ff10e9e2de78fcb27fdba221f4243ec5bf69585c82	\\x0000000000000134	10	0	payto://x-taler-bank/bank.test.taler.net/157	account-1	1565900815000000
232	\\xb21a34488c76adf57605deef27a970d6d9d33da99fd10d5b34f971283282b936	\\x0000000000000132	10	0	payto://x-taler-bank/bank.test.taler.net/156	account-1	1565900324000000
233	\\x038996dfe9ad38f23e619fd7633f3074e88b03d48e59d818047613fe6617f725	\\x0000000000000130	10	0	payto://x-taler-bank/bank.test.taler.net/155	account-1	1565899745000000
234	\\xba2946c6883d1ed6f2770b5902b2b08f6ee0a02148b277b60a085f88118d3ddc	\\x000000000000012e	10	0	payto://x-taler-bank/bank.test.taler.net/154	account-1	1565899679000000
235	\\xb233d5a9840e928cb977bceb516306951f3690c14183539824dd61ee466f08c2	\\x000000000000012b	10	0	payto://x-taler-bank/bank.test.taler.net/153	account-1	1565898981000000
236	\\xa42e64a59afcf6bb9f1c76f9cb00613f067bc49f5e81b8e242d813bafccea2fc	\\x0000000000000128	10	0	payto://x-taler-bank/bank.test.taler.net/152	account-1	1565896715000000
237	\\x3ec53b2ead912ef64ac90c74d5a68e5b60ae65f0249af37ea6eb9e05b9164898	\\x0000000000000125	10	0	payto://x-taler-bank/bank.test.taler.net/151	account-1	1565888850000000
238	\\x21d76dcb3902f1dbdde706d80a37b852666435bbeca78bfdc5cef62d72686d43	\\x0000000000000122	10	0	payto://x-taler-bank/bank.test.taler.net/150	account-1	1565874286000000
239	\\xf1c90d032747f3cc1d8738eb9c888c1e4013f9e7064ffd521a7eaded85cfbc9f	\\x000000000000011f	10	0	payto://x-taler-bank/bank.test.taler.net/149	account-1	1565801356000000
240	\\xaf086d1b12d87e90235d15156afdafefe8fcd38f4de456e9bbfeb62b3d6c3ad4	\\x000000000000011c	10	0	payto://x-taler-bank/bank.test.taler.net/148	account-1	1565800433000000
241	\\x06ac13492eace96f3e5a49e44e0f18c4a356c77b1d4a8e856b976d9e9a436edc	\\x0000000000000119	10	0	payto://x-taler-bank/bank.test.taler.net/147	account-1	1565800289000000
242	\\xea06a92933ce6035f37c58c4476a5b661228594d98b62e4b8f8c2458fe451303	\\x0000000000000117	10	0	payto://x-taler-bank/bank.test.taler.net/146	account-1	1565800235000000
243	\\x64a12dded192a4f8edc3614e4acf52fbe27c78cbed3ab815f4627723ca14e4ab	\\x0000000000000114	10	0	payto://x-taler-bank/bank.test.taler.net/145	account-1	1565202594000000
244	\\xfb949fb3cf8195cd6424b1475ea365019a9a4fbb25041e94af644e201c7c83d6	\\x0000000000000111	10	0	payto://x-taler-bank/bank.test.taler.net/144	account-1	1565202402000000
245	\\xe566a9c140e79572592dfeb3dcf5cea94c9dd8da30dc292d8fe44a284ce5d481	\\x000000000000010f	10	0	payto://x-taler-bank/bank.test.taler.net/143	account-1	1565201202000000
246	\\xc2cabf67c5f7bdc043a7f62ed26cb12fd43b1492aabb44bf5db7f0d70e57dbf8	\\x000000000000010c	10	0	payto://x-taler-bank/bank.test.taler.net/142	account-1	1564696822000000
247	\\x07339becf40893d3ae5d1240e79f1f24c8289ce9ba616c570c50f7f58cd81169	\\x0000000000000109	10	0	payto://x-taler-bank/bank.test.taler.net/141	account-1	1564695804000000
248	\\x23e715a7d521c72f5b14338fea8ef018b42e255c3047d0a381ba1b892951a584	\\x0000000000000107	10	0	payto://x-taler-bank/bank.test.taler.net/140	account-1	1564695796000000
249	\\x18191bb360a5f0a52525101988c41ed8c9244511d8813371023d44164dd3ff9b	\\x0000000000000104	10	0	payto://x-taler-bank/bank.test.taler.net/139	account-1	1564694327000000
250	\\xbf0ff9a0ee337e7af907db7c46888d79a3f4e0dcc96ee1476a8bd4bb0b063a30	\\x0000000000000101	10	0	payto://x-taler-bank/bank.test.taler.net/138	account-1	1564694233000000
251	\\xdd974f8782ead8c4f65996e45e14cbdedd05b5ff194f2e069086c2918819b75c	\\x00000000000000fe	10	0	payto://x-taler-bank/bank.test.taler.net/137	account-1	1564694153000000
252	\\x24bfdf65d4f1f9d4569b886e727b9aa0dc6880614899b27f5663d8b72e1b583e	\\x00000000000000fc	10	0	payto://x-taler-bank/bank.test.taler.net/136	account-1	1564694104000000
253	\\xf03f57d32b04d85adbce1409248b6b5fb37321cd9d9cf87501d21db209336cdf	\\x00000000000000f9	10	0	payto://x-taler-bank/bank.test.taler.net/135	account-1	1564694014000000
254	\\xb808d9b7228568c2da8a58e1f0f5bab7af279d1db94592f1117e42163aeee7be	\\x00000000000000f6	10	0	payto://x-taler-bank/bank.test.taler.net/134	account-1	1564693825000000
255	\\x96b4b1dda4cf071443b4981f1d19d2f2f2e18c134355b9fee726e8f36bbdd2da	\\x00000000000000f3	10	0	payto://x-taler-bank/bank.test.taler.net/133	account-1	1564693777000000
256	\\xc18211fa8c81102e6fc987ba80a04caa028b1982b816a5d2785614d6ebec3c96	\\x00000000000000f0	10	0	payto://x-taler-bank/bank.test.taler.net/132	account-1	1564692761000000
257	\\x7085f00e9a48f4678899788358172b7447cd456c276a20d7313ca474be88b8a7	\\x00000000000000ed	10	0	payto://x-taler-bank/bank.test.taler.net/131	account-1	1564692647000000
258	\\x6803c62ef4992666d21fd5571e2807134d1aaa6f7fbb7f8333ddbab7910e0a00	\\x00000000000000eb	10	0	payto://x-taler-bank/bank.test.taler.net/130	account-1	1564692566000000
259	\\xd9639612a99db4d4527d907179d1649575ade0db21205bb984928d59916ff575	\\x00000000000000e9	10	0	payto://x-taler-bank/bank.test.taler.net/129	account-1	1564692538000000
260	\\xb4a2cee738ce45ecc226c07766148a710e68875ae06b92447f79d3615a279da7	\\x00000000000000e7	10	0	payto://x-taler-bank/bank.test.taler.net/128	account-1	1564692478000000
261	\\x66f3faced265ce5d6c8b67ca3566edf511e61b0caada94bf08ba538d01357b70	\\x00000000000000e5	10	0	payto://x-taler-bank/bank.test.taler.net/127	account-1	1564692433000000
262	\\x48df8b7cfd2999012b0004f8d0746d4c1ccf02051b6c55b071bf0bc3f92aee9c	\\x00000000000000e3	10	0	payto://x-taler-bank/bank.test.taler.net/126	account-1	1564692411000000
263	\\x548a4bc745f4033c770ed431c2321bbe70d609d881190f970251bda60052c5a5	\\x00000000000000e1	10	0	payto://x-taler-bank/bank.test.taler.net/125	account-1	1564691565000000
264	\\x63a477040824f3cd55ac8dbc628274a9107608c423fc51643ac25d2ed61d0de8	\\x00000000000000df	10	0	payto://x-taler-bank/bank.test.taler.net/124	account-1	1564691151000000
265	\\x2c1b8d0b80acb5f6e3049190ff613726a4b5441553b3d3ec77deb232594e7218	\\x00000000000000dd	10	0	payto://x-taler-bank/bank.test.taler.net/123	account-1	1564691105000000
266	\\xd78dde36de2139fa86f2a0f7bf8a13b2f654d9fc3cd303ebb2eab186cb9f0040	\\x00000000000000db	10	0	payto://x-taler-bank/bank.test.taler.net/122	account-1	1564690971000000
267	\\x1fdc52e5e5aaf87add91e7a1fec0fbf332ce7bd9c9d64154317e670798fe7fbb	\\x00000000000000d9	10	0	payto://x-taler-bank/bank.test.taler.net/121	account-1	1564614424000000
268	\\x1380f5e214357cb2e7717dff93edbdfe1a0ea3d38abaab37ab80e1c0c68ae71a	\\x00000000000000d7	10	0	payto://x-taler-bank/bank.test.taler.net/120	account-1	1564608599000000
269	\\x954518ac86a57cd7f8e87ee130a700fa82dfc8bebfe203ca3b74d2cd17e1cb26	\\x00000000000000d5	10	0	payto://x-taler-bank/bank.test.taler.net/119	account-1	1564608548000000
270	\\xbb8902b13a6baac9f348816b3c3b9ec1b3c3c806416a64c73dcc454e09227a92	\\x00000000000000d3	10	0	payto://x-taler-bank/bank.test.taler.net/118	account-1	1564608240000000
271	\\xe4d26be5cacceef7912af71ecde66d520cb080386e12e595f003247e1f936722	\\x00000000000000d1	10	0	payto://x-taler-bank/bank.test.taler.net/117	account-1	1564607402000000
272	\\x16b8099673434e13daef88b354ddde89a8ab8803a78a262ee01ff241af07951a	\\x00000000000000cf	10	0	payto://x-taler-bank/bank.test.taler.net/116	account-1	1564607300000000
273	\\xcd29f44596d41578562294edaa5f9d225da864c18d222ebc64186656208213c3	\\x00000000000000cd	10	0	payto://x-taler-bank/bank.test.taler.net/115	account-1	1564606676000000
274	\\x24f5e83ab46b9b876a6d044bdbfd86edd0d5ac06e34f822f73537f9e86ddd27e	\\x00000000000000cb	10	0	payto://x-taler-bank/bank.test.taler.net/114	account-1	1564606647000000
275	\\xa8120c712e0045d452667af538614c2ede7fa93e574b98c2568dc94f1200ed2f	\\x00000000000000c9	10	0	payto://x-taler-bank/bank.test.taler.net/113	account-1	1564606569000000
276	\\x8de9216933cf74b32a0ba183c5d47f07deb8d1ba6aeab2558d27933f8f46251a	\\x00000000000000c7	10	0	payto://x-taler-bank/bank.test.taler.net/112	account-1	1564606497000000
277	\\x86d56a0cf7a3981f71b607a9673ee2fe4ad3a8710274073cbe9dfb7ad73a2510	\\x00000000000000c5	10	0	payto://x-taler-bank/bank.test.taler.net/111	account-1	1564605529000000
278	\\x536fbc82c3257adfb45db4a7c3fea6661442a2edf4eb3413121e86916d84c559	\\x00000000000000c3	10	0	payto://x-taler-bank/bank.test.taler.net/110	account-1	1564538833000000
279	\\xc5665b33302b94735b0f53fabe3e4b28005be2cd6ea7b9f8ee133bc35f397ed3	\\x00000000000000c1	10	0	payto://x-taler-bank/bank.test.taler.net/109	account-1	1564538774000000
280	\\xa85e72dc53fad0966b30f675487aac5810e20b3bf7f36c63233bea2d1c9370e7	\\x00000000000000bf	10	0	payto://x-taler-bank/bank.test.taler.net/108	account-1	1564538601000000
281	\\x58964c1bcebf6b5513e15eb0eef739d38f1478e1cd53bf661342b9c62038cbe2	\\x00000000000000bd	10	0	payto://x-taler-bank/bank.test.taler.net/107	account-1	1564538559000000
282	\\xd3be87219e455c130fb5d5976ec829cdf39359a7d0a3e37cdabd0e42f2fad9b2	\\x00000000000000bb	10	0	payto://x-taler-bank/bank.test.taler.net/106	account-1	1564538404000000
283	\\x62d223b400193c59c2e72fbccbe09b9184ac7c1a028da0035d53461ca495555e	\\x00000000000000b9	10	0	payto://x-taler-bank/bank.test.taler.net/105	account-1	1564538347000000
284	\\x00c831aa5b629c775dc9a0175875c435262392e8ec98c820efab3c40f59c3fe8	\\x00000000000000b7	10	0	payto://x-taler-bank/bank.test.taler.net/104	account-1	1564538267000000
285	\\x1997040916524f5640cc195c47cb5c032164e8c192fa255e85a3ae9d5800660c	\\x00000000000000b5	10	0	payto://x-taler-bank/bank.test.taler.net/103	account-1	1564538197000000
286	\\xa3e78ad0d30b125cd2d8a415ca3b9a43b971ac8e43647a68064b78943ef65e7c	\\x00000000000000b3	10	0	payto://x-taler-bank/bank.test.taler.net/102	account-1	1564538175000000
287	\\x43204e72736000d5ddee27e781d5ad4b45bfde4b3e83173311189ab720af0dca	\\x00000000000000b1	10	0	payto://x-taler-bank/bank.test.taler.net/101	account-1	1564538144000000
288	\\xa6ea849bc978b07d539c37404ce74dafb28b94d46d3d929a9ddba72d176fc5fb	\\x00000000000000af	10	0	payto://x-taler-bank/bank.test.taler.net/100	account-1	1564538036000000
289	\\x35641ad074a9b19579b03e68c2bd128dd15deaf8684af5c4a346801372d41b90	\\x00000000000000ad	10	0	payto://x-taler-bank/bank.test.taler.net/99	account-1	1564537990000000
290	\\xaae06b233c96780d6afd620b1edd6f821d14a5bf432fbc5f4aeb689e7fe3d938	\\x00000000000000ab	10	0	payto://x-taler-bank/bank.test.taler.net/98	account-1	1564537954000000
291	\\x4c6d212fba5c61423aad80c8af8b1d5f3c94b267d920f53851caadf2166d49b0	\\x00000000000000a9	10	0	payto://x-taler-bank/bank.test.taler.net/97	account-1	1564537928000000
292	\\xd0c7accb37f6345703dfb0502fa150066094c681ed319b1dc2fcd234eb6fb767	\\x00000000000000a7	10	0	payto://x-taler-bank/bank.test.taler.net/96	account-1	1564537888000000
293	\\x64aed8c33abf2c05cefa50c0ecaf5e1f20201e747be1339b8d04fbb29b59cb57	\\x00000000000000a5	10	0	payto://x-taler-bank/bank.test.taler.net/95	account-1	1564537883000000
294	\\x69958928499e2c55da1ea6fb7833bd6a3e80962996c4a821fe95d05b58f96a26	\\x00000000000000a3	10	0	payto://x-taler-bank/bank.test.taler.net/94	account-1	1564537729000000
295	\\x5cb50417e9ab996297eb90960b33772f344ae83bc6ef32ebe96318d09cb331f0	\\x00000000000000a1	10	0	payto://x-taler-bank/bank.test.taler.net/93	account-1	1564537714000000
296	\\x06ea81e28c450fd05b5a0c912fef872fe3adf22a8ca70425cfd38ff2a65649e1	\\x000000000000009f	10	0	payto://x-taler-bank/bank.test.taler.net/92	account-1	1564537697000000
297	\\x81f75ad9675c95ba5078825b565c0f824f40359308975309996a4da4a5644f10	\\x000000000000009d	10	0	payto://x-taler-bank/bank.test.taler.net/91	account-1	1564537690000000
298	\\xb2c11ab01be7ce2856f045ae71e075b7773c0ee212d4fe17a6c3b7357610517d	\\x000000000000009b	10	0	payto://x-taler-bank/bank.test.taler.net/90	account-1	1564537683000000
299	\\x9656ed83ad3aa5cc92c0f8164a1be450f5f275de8ac3cbe3269a5b2bc67a4e8c	\\x0000000000000099	10	0	payto://x-taler-bank/bank.test.taler.net/89	account-1	1564537655000000
300	\\xb0f9afccc0e0e6db8ff80daafbe7e3402de21e2f37d57f22348397c5d5d28940	\\x0000000000000097	10	0	payto://x-taler-bank/bank.test.taler.net/88	account-1	1564537644000000
301	\\x302417b3226366b7893c3cf6ea0a9914d7f12ee9c4f7e68f4b0a743dddc2daad	\\x0000000000000095	10	0	payto://x-taler-bank/bank.test.taler.net/87	account-1	1564537597000000
302	\\xbebc635004c1523c36f749753b8d7df3e3a535d657529c88edda82aa8372688e	\\x0000000000000093	10	0	payto://x-taler-bank/bank.test.taler.net/86	account-1	1564537535000000
303	\\xd97382f3adeb334efc19beb626b79a465cf10e6722370f4158811962ea18bafa	\\x0000000000000091	10	0	payto://x-taler-bank/bank.test.taler.net/85	account-1	1564537486000000
304	\\x1da515d261a0b861b1c937b34bf6cbf0dfe0baf10646daec02035c888775be0f	\\x000000000000008f	10	0	payto://x-taler-bank/bank.test.taler.net/84	account-1	1564537480000000
305	\\x9f5bf80861719ced68d14c652154ef31251800dfb9b9d131fd211072cbe1dfe0	\\x000000000000008d	10	0	payto://x-taler-bank/bank.test.taler.net/83	account-1	1564537473000000
306	\\xf405b7257a8a5538d422ef6357ad1bf283cc4c11fffc5d0cfa766f72513618b6	\\x000000000000008b	10	0	payto://x-taler-bank/bank.test.taler.net/82	account-1	1564537413000000
307	\\x22f8a5abcfd602cc882981bb71b6369295be2134d32634f3f977149bcdcb58f0	\\x0000000000000089	10	0	payto://x-taler-bank/bank.test.taler.net/81	account-1	1564536410000000
308	\\xe28be2d1c6b322cf70742df0d1770adab4273af10f2a141ff703bbd24a9a9ac8	\\x0000000000000087	10	0	payto://x-taler-bank/bank.test.taler.net/80	account-1	1564536371000000
309	\\x6a0d97fb945b3b91e17b1e40f3e8b6d7b595a57e4bbffbea232987e427b5a1d1	\\x0000000000000085	10	0	payto://x-taler-bank/bank.test.taler.net/79	account-1	1564536331000000
310	\\xfb87bd1deed3e5c30cdd323ef440e77e42d859262962e9f99c03a5c740e4afaa	\\x0000000000000083	10	0	payto://x-taler-bank/bank.test.taler.net/78	account-1	1564536263000000
311	\\x312118463312133bf9537123a3930ac4a4d2c245baea11dd8fd32fd8351bed29	\\x0000000000000081	10	0	payto://x-taler-bank/bank.test.taler.net/77	account-1	1564536198000000
312	\\x4685b36210f4a6c7e87d9f88b5a45f834a0d5b58c9d138fd705aaf442e9ad8c4	\\x000000000000007f	10	0	payto://x-taler-bank/bank.test.taler.net/76	account-1	1564536071000000
313	\\xfb380400ea4f5a8fbc5b8bb4a09b779aaf217474955c02d02e6c2f7067293e2e	\\x000000000000007d	10	0	payto://x-taler-bank/bank.test.taler.net/75	account-1	1564536053000000
314	\\xbc40482ef0b8339c6ca1a7fdb65773a0e8a025c9c132fb6be01e73f7034e6e55	\\x000000000000007b	10	0	payto://x-taler-bank/bank.test.taler.net/74	account-1	1564535749000000
315	\\xd681ec996bf4ca985c7fa9577709158416c88988a29f20d8ea16dfbc27e494ff	\\x0000000000000079	10	0	payto://x-taler-bank/bank.test.taler.net/73	account-1	1564535583000000
316	\\x4deda68ee9c75e3eafa0727067c4778ca01a8e2adc85eb1a8b45035552a98578	\\x0000000000000077	10	0	payto://x-taler-bank/bank.test.taler.net/72	account-1	1564535176000000
317	\\xa83105590f3561f861081fcfd5f885a01585b325ffb3263c6a7c9c8d2a10c34c	\\x0000000000000075	10	0	payto://x-taler-bank/bank.test.taler.net/71	account-1	1564535167000000
318	\\x54b48db3c7833a4a43d7433a7443c0a43ca5eccdae6760937e9fe4c074b2a3da	\\x0000000000000073	10	0	payto://x-taler-bank/bank.test.taler.net/70	account-1	1564534808000000
319	\\xf4ce5a6636d9042b66f1633ae30b2aa5cd262a189ed20f793f72307dc9c248f0	\\x0000000000000071	10	0	payto://x-taler-bank/bank.test.taler.net/69	account-1	1564534634000000
320	\\xe6aec2213578fe4de5fee32f82d79ce13f168f9ddd1861ea50c2f13d62c9f4ad	\\x000000000000006f	10	0	payto://x-taler-bank/bank.test.taler.net/68	account-1	1564534070000000
321	\\x832ba7bf73d5b86429f3be7f245e0b8880f2e6feb29e6b3d6d5f13d586bf9fcc	\\x000000000000006d	10	0	payto://x-taler-bank/bank.test.taler.net/67	account-1	1564533855000000
322	\\xd3ff34a089de9aec918e3b75a0178136171af9a84fbee676ea5a8cc2a947c060	\\x000000000000006b	10	0	payto://x-taler-bank/bank.test.taler.net/66	account-1	1564533536000000
323	\\xe7fd68fd42067d407b98d1f30f80307353f5348047dc2649c82684240886e4fd	\\x0000000000000069	10	0	payto://x-taler-bank/bank.test.taler.net/65	account-1	1564533370000000
324	\\xb65138b306c3a742753688438123087da53e07319fc30ddb769baec37780d204	\\x0000000000000067	10	0	payto://x-taler-bank/bank.test.taler.net/64	account-1	1564533342000000
325	\\xf66b6fc40bfd70532fa6da42e8d746a20a74415647f99be6c5e5a855c97aa0a7	\\x0000000000000065	10	0	payto://x-taler-bank/bank.test.taler.net/63	account-1	1564533298000000
326	\\x95a1d91c014ba399e5f7494c4135cb3c81b0f69eeed821c85da402fc07c9daac	\\x0000000000000063	10	0	payto://x-taler-bank/bank.test.taler.net/62	account-1	1564532759000000
327	\\xcf622a2c3767c9f871100f9d782b792e1e6a5404833445d522789f924d169b4d	\\x0000000000000061	10	0	payto://x-taler-bank/bank.test.taler.net/61	account-1	1564532057000000
328	\\x8d40f84bf39a8ca60e00d36825f2b156afaad70dff784f434ddfdb48682d53b6	\\x000000000000005f	10	0	payto://x-taler-bank/bank.test.taler.net/60	account-1	1564532047000000
329	\\x5604e4942174f8ead3e75d576e38c5264e65757cc2a07c4e8ac1bf4da6b95b14	\\x000000000000005d	10	0	payto://x-taler-bank/bank.test.taler.net/59	account-1	1564531757000000
330	\\x39a22bfce8e62bb9bf56113cc0272dc3c776cac1efa3c307d0fb84671d805d76	\\x000000000000005b	10	0	payto://x-taler-bank/bank.test.taler.net/58	account-1	1564531733000000
331	\\xde8480cf26f349a625f9fcd83aa6498570479fad5c1193f9dda3f1ad683239db	\\x0000000000000059	10	0	payto://x-taler-bank/bank.test.taler.net/57	account-1	1564531462000000
332	\\xb452f9eca6986c08f8c23a978e0f0be057a8ac79005640f87a993e16b95764fa	\\x0000000000000057	10	0	payto://x-taler-bank/bank.test.taler.net/56	account-1	1564530216000000
333	\\x9f049ed6dbb886f85e6b62c86a9ce709d0d2de3abb8f6578d50233f88bc7f93d	\\x0000000000000055	10	0	payto://x-taler-bank/bank.test.taler.net/55	account-1	1564530055000000
334	\\x4e7946826a660b06b17634fc4ead6f9ce8ca563ba56eb8e9569cbcec1a279ce8	\\x0000000000000053	10	0	payto://x-taler-bank/bank.test.taler.net/54	account-1	1564529464000000
335	\\xf1c097c68600d04fd93be5c44fe7c67ee577d2c372eb981bf1889e669c1ee203	\\x0000000000000051	10	0	payto://x-taler-bank/bank.test.taler.net/53	account-1	1564529328000000
336	\\xee80e518448d549e9319687310248ea6a8885dfa94ba0f78bf62a12c84825e9e	\\x000000000000004f	10	0	payto://x-taler-bank/bank.test.taler.net/52	account-1	1564529220000000
337	\\x420480d63995c7c69bded84145ce20c13743f51cb83296d0b38713d4c3307dac	\\x000000000000004d	10	0	payto://x-taler-bank/bank.test.taler.net/51	account-1	1564527969000000
338	\\x16dcd603b509d4829fc4f2c6ed34a7fc5d20be15dcd3c50248f97e609eedf3b1	\\x000000000000004b	10	0	payto://x-taler-bank/bank.test.taler.net/50	account-1	1564527961000000
339	\\xc3109d60cc5a3adf527ad26fd6cb17223bcddf138cedd775ff8174a6b0d4d57f	\\x0000000000000049	10	0	payto://x-taler-bank/bank.test.taler.net/49	account-1	1564526700000000
340	\\x285c1be3eddd195f60d19a0d35e7d9ac677db3414e3dbeb45a744740bf2ceade	\\x0000000000000047	10	0	payto://x-taler-bank/bank.test.taler.net/48	account-1	1564526599000000
341	\\x38ab0a9f30c7bc5c524a634bd65ffa7d34fc8f1086531d20e69d055f5f6117c5	\\x0000000000000045	10	0	payto://x-taler-bank/bank.test.taler.net/47	account-1	1564519935000000
342	\\x6ce4ed71b0493afa505c82bce3cf35fbb9ab1fbedd739d56de8fd0aeef256086	\\x0000000000000043	10	0	payto://x-taler-bank/bank.test.taler.net/46	account-1	1564519865000000
343	\\xabf0b85b85cf80b41e0b39ab792ae7581b9855bfcf5e28d2a9a367476a84f754	\\x0000000000000041	10	0	payto://x-taler-bank/bank.test.taler.net/45	account-1	1564519732000000
344	\\x5022184bf2d4433c31601ce1cbd91210cf746a47ea5e2986ccaafa8f44c73cb2	\\x000000000000003f	10	0	payto://x-taler-bank/bank.test.taler.net/44	account-1	1564391061000000
345	\\x9a0403092f3d26c4f6e972e7790340048a3cd685cde9ea78564d8764434cdf9c	\\x000000000000003d	10	0	payto://x-taler-bank/bank.test.taler.net/43	account-1	1564390909000000
346	\\xcc142afa684afbda15d34a034120d2e432ff922155baa4fe9c0ee650d0ff46cb	\\x000000000000003b	10	0	payto://x-taler-bank/bank.test.taler.net/42	account-1	1564390248000000
347	\\xfc81c49fd4757e5ec657c9a2def34982bcbb006e9fe97021c0abeaf1734ec94a	\\x0000000000000039	10	0	payto://x-taler-bank/bank.test.taler.net/41	account-1	1564390176000000
348	\\x897ae32910f7abed434f0610dd49237b33e444d0f8bd249430ca3dc95a10a2af	\\x0000000000000037	10	0	payto://x-taler-bank/bank.test.taler.net/40	account-1	1564388301000000
349	\\xcc86e634723b519276a556ad6ad6b60f380f21b02032c0740ded5e35603bc478	\\x0000000000000035	10	0	payto://x-taler-bank/bank.test.taler.net/39	account-1	1564387672000000
350	\\x90daeab4cbd5cb952510b3d199f3a0fefa8d45f77902390505db05bcfed8bf99	\\x0000000000000033	10	0	payto://x-taler-bank/bank.test.taler.net/38	account-1	1564387544000000
351	\\xcd23da780b5f93611ac993fc63575d2bafacd46d2ca7a9397316ba08b70fcbb6	\\x0000000000000031	10	0	payto://x-taler-bank/bank.test.taler.net/37	account-1	1564387504000000
352	\\x2155645ea096b73957f56c776e2e785db994dcec138fc4be4c41344322197551	\\x000000000000002f	10	0	payto://x-taler-bank/bank.test.taler.net/36	account-1	1564345616000000
353	\\x7bcf85a0af25010d0df96e5826302329f4a0dba7056f7390c14e240916320a55	\\x000000000000002d	10	0	payto://x-taler-bank/bank.test.taler.net/35	account-1	1564345478000000
354	\\x09c2c3d8d54d9183221a1afdee2873370eb17cb7ae6bbe259d1770a05082ec04	\\x000000000000002b	10	0	payto://x-taler-bank/bank.test.taler.net/34	account-1	1564345270000000
355	\\x19d245eda964fadc2d68c0c1d05ee8ab761212dec72a0e151f670e9028cdf0b4	\\x0000000000000029	10	0	payto://x-taler-bank/bank.test.taler.net/33	account-1	1564345083000000
356	\\xc2caebf149e241165f50e4b82c51e322f5bef5fd0c12dcf41f4ab597cf2d0919	\\x0000000000000027	10	0	payto://x-taler-bank/bank.test.taler.net/32	account-1	1564343996000000
357	\\xb53d31ec78090b17be2ea17aedb42bf74a985215946d0674fa06c7c326fcaefe	\\x0000000000000025	10	0	payto://x-taler-bank/bank.test.taler.net/31	account-1	1564343985000000
358	\\xdfcf3f95ec6a159fd971b8afc5203432523d38ca3fac1bd0dc11cee7c67d186b	\\x0000000000000023	10	0	payto://x-taler-bank/bank.test.taler.net/30	account-1	1564178356000000
359	\\x3049fdf6ffd673a6711558e0b2cd34e53dbd3d0150407f12c896dd17056f80a9	\\x0000000000000021	10	0	payto://x-taler-bank/bank.test.taler.net/29	account-1	1564177274000000
360	\\xd8457bd02eb1f93640e440d374168378a3a26810eaf6f462e0bb48ddf5fa25b1	\\x000000000000001f	10	0	payto://x-taler-bank/bank.test.taler.net/28	account-1	1564176057000000
361	\\xac8df807cb36ef64846816ab0947cb59348b116f7cccb7fe378b486bcb06adbf	\\x000000000000001d	10	0	payto://x-taler-bank/bank.test.taler.net/27	account-1	1564175456000000
362	\\x5350dea1916bd3d4324025fa70d64fcc7ca583520e6ca4ce3ce1b56f838e8bab	\\x000000000000001b	10	0	payto://x-taler-bank/bank.test.taler.net/26	account-1	1564175435000000
363	\\x661e8a0a01acb4cbb4b3678b52e36cef107ecceb1bc34ae2c534a2105b6dbdba	\\x0000000000000019	10	0	payto://x-taler-bank/bank.test.taler.net/25	account-1	1564175012000000
364	\\x1eea5a98a6944c6daa73ff98448f602b64f5a6008af7d5ec04e0948cd12521fd	\\x0000000000000017	10	0	payto://x-taler-bank/bank.test.taler.net/24	account-1	1564173924000000
365	\\x9a76b3e571ceb844d248de54ef2edcc829a8e166da4cd0f4ee0ce1606fc49d67	\\x0000000000000015	10	0	payto://x-taler-bank/bank.test.taler.net/23	account-1	1564173802000000
366	\\x4b640f53f10a01dba1998894b439df71831eff0fdaa4bf1e149a7399a879dfa7	\\x0000000000000013	10	0	payto://x-taler-bank/bank.test.taler.net/22	account-1	1564173684000000
367	\\x18e56584f16f9f023708933014b179e9b810231b40217ecc257216ca139d6510	\\x0000000000000011	10	0	payto://x-taler-bank/bank.test.taler.net/21	account-1	1564173675000000
368	\\x2d85cac3344b67052aeaaaeac0312e3bf3814781ae182d7b11e0fa6d7c301021	\\x000000000000000f	10	0	payto://x-taler-bank/bank.test.taler.net/20	account-1	1564173636000000
369	\\xbe6c6cf37b37e4ac11f5efefffa16111e32ce79981d192ada976a329a30fda7e	\\x000000000000000d	10	0	payto://x-taler-bank/bank.test.taler.net/19	account-1	1564173511000000
738	\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	\\x0000000000000356	10	0	payto://x-taler-bank/bank.test.taler.net/397	account-1	1566478898000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xebc8b38350aa7cc7b2ca2fe22d9d1a14a1f2fa8a030ec316ebf2ff57d9238dfadafd480d89ec679dfcf93a932efda037785afb765e9c0302376bcb3252dcb8f2	\\x32f04fe33aab830e5fca30c948bc820e3137142b5e35c29a43a5f100b30167891e435bcd5b9d83815417d3710c1cac2d2f494827b0ab0044b8c4d397986f75f5	\\x287369672d76616c200a2028727361200a2020287320234437433731453339353233383246344530454345393331344545313032323130453844433934364434363538333135463835353135373331304530353245343835314143333431393539454142383333383439443530434345323539304446444531304136434638434535363443393741323044413533364637464432304144463936333143454137374432353942394337423444303137414639453542413044313339443645353637453531453042313334413044453736393646363038323038363935344630433436334532313739303541413046333832383330424234433541463536434638334137393630454242463441344536333130453238364423290a2020290a20290a	\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	\\x7694395f81c2fa35d2eaac0e73f015a58e153d0d4facc8b56a3b9750d173a4d0e0321b4ffe377abc7a7b13c2499d4e1bc2377b8e91458a5e261cd93a768fb507	1566478900000000	2	0
2	\\x06031b4dffdc3bc7eeff854ca0e1e994d7f7ee25a961d10f3891440b86ed85aeff24c81ccbf04a064f10abb800e77fbee40c532f91ca3b5b49a433e05389024e	\\xacf90474218ef9b9114aa85e8ef1df6d0c48362621ad90c581e59654e9482ab94f5a32821563ee80291a510750d967e14031f75b7a2b59ffd96441652e2abd61	\\x287369672d76616c200a2028727361200a2020287320233044343641343231313338334541313536464242393746373439333443423743304343343244344542364436384333354546443046434644424230373237443130463838344543303939363630363233383734333145323443314130433730463631464244444636413643454646414434443832313630373632463243393231454443363431434634314532343336433344304241363338323441454542434530374532304136353333393639443130314143314642464543424139444337333341363330324141383545463645443035424246433034454639453533383636373631383834364246323436333846433241453231433430333533324330453023290a2020290a20290a	\\x671ba24af73a74eddd46e524cd11f3741d141980038a3c9844d1187ce82bf463	\\x19bacd701333dac575dc355c8001b22a82ece85a254b10fd3238df7c915db836475429992d3a6c4830a87539a7db9b71f92f4e7c44cd4acf4de28cd2522b800b	1566478900000000	8	0
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
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.wire_auditor_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, last_timestamp, wire_in_off, wire_out_off) FROM stdin;
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
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


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

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 1, true);


--
-- Name: kyc_events_merchant_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.kyc_events_merchant_serial_id_seq', 1, false);


--
-- Name: kyc_merchants_merchant_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.kyc_merchants_merchant_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1106, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: grothoff
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 2, true);


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
-- Name: kyc_merchants kyc_merchants_payto_url_key; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants
    ADD CONSTRAINT kyc_merchants_payto_url_key UNIQUE (payto_url);


--
-- Name: kyc_merchants kyc_merchants_pkey; Type: CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_merchants
    ADD CONSTRAINT kyc_merchants_pkey PRIMARY KEY (merchant_serial_id);


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
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


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
-- Name: kyc_events_timestamp; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX kyc_events_timestamp ON public.kyc_events USING btree ("timestamp");


--
-- Name: kyc_merchants_payto_url; Type: INDEX; Schema: public; Owner: grothoff
--

CREATE INDEX kyc_merchants_payto_url ON public.kyc_merchants USING btree (payto_url);


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
-- Name: auditor_denomination_pending auditor_denomination_pending_denom_pub_hash_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_denom_pub_hash_fkey FOREIGN KEY (denom_pub_hash) REFERENCES public.auditor_denominations(denom_pub_hash) ON DELETE CASCADE;


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
-- Name: kyc_events kyc_events_merchant_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grothoff
--

ALTER TABLE ONLY public.kyc_events
    ADD CONSTRAINT kyc_events_merchant_serial_id_fkey FOREIGN KEY (merchant_serial_id) REFERENCES public.kyc_merchants(merchant_serial_id) ON DELETE CASCADE;


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

