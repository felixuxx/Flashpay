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
\\x0a8a2f49cbe24ee7f2e05f30191acaf0c358fd4ec37b5193d10796e98c06bca5c4df6117f47654bc6baaec777aa403e08b20f50baec29aae5b2d3c91518d10c1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e097a466662d87dfbb284775b00f184a72620a6da466dc2b6dc0f88dac68e2f42ca71489b8b9073348b057b1206fe465f18a94ede68d93531dc5f9f976ed1cf	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x70b7098dbe43211b8698daf2cbe7bac13c48bdedb9039323accb702083167519a329746528e3cc8e49934b4744a48a87148bfd9feb57cc9ce672615171e12f34	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1dfe20815fbfe068c005c38bc8173276fa76bb5d576bc5502cc1f66d622be3bfc72cb2f04939b8d67847154a4d2f6a24d586663840ffc0a23aa55760e10c5ba9	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77ab0eb55e2722cbb067152804b9eb8bfb43180445456fc7862a0f28cefe417606a3584013212d6f8f8501d15c0d1f72142b2ed8041da5df190a6f8612724da3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xf596761a78473cafbeb37c13d7a311152c1cce7a65717bfa952190e63e0cbd81fee6de85693b69ae3aa66ebf858ed55a939a0a60f27a24b168c202321dccbdee	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x15fb2b6a95807658d8578631540a513f4bd4ba605ae56486d22341014cda0b7f2dcd06f31152682edde4ab70b28c2ccfbc24cd3a139a06140cbc46abc3b646bc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8db1736cd730c091889ad2363ea3c4821d395b2a9e72579e4c2e5bf719e92232e60968238b195fbbb48ba912c822c90947569ba76ad2e56df96380d6cfa9809b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73c89be8622d028c1b8cf8770294aca0c2e65a01355042a7542f0738368c39c026504381eb36e1cf70e54c8b626e65bc76e18a7de60dd1f949ed2884f6a73887	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3a8cb821e6f5d0108f7a54c35729195957f2282fa38bc0cb429d9ee0c507407e02428d41e6e00ca967f82fc3ab890d3ce2c778cfc71fc6b57ea711c6487e85a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x14e0238ccc9c65a1b56fe07c2b2948772d1ea420d32adfc4b4fe82a6ae93d7a5545bc29b13b012da838c556e6d749459f257e3d52b183524929106cc40b20b4c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa65523f091161835078d57f3a9027de0b0bbb368e13193de2017bec188e6906efa5bf2fe530927c97a3bb88e0e9f083f9f00ab3f5632e01f13c8efca302ab50e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x212cd0a5e9ccc8985c7a420f9d6f001b1dbbe088bd159e1c6d7c5e70d3fe208511d80ff06b6abf27fb113227c41ca9732d2575c00e3ac17ab631ac277e2d0e5a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa788ed55d4d69c0a9719b2dc0ec255b1d5d5c165b1dcdb43f6af1d40f21b9605d31556c3c0fc1e0789ceaa6209f4f3d6411adef9b1a9d33350412482575b9bb7	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfad3079de7544f402c448a3d2cdc7789be202a94f38f067dcf97757568635335aba66be76817c060bae26f229b662234ed4f2a4dcef6b02efd8e783888b06829	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4f0bedf37b8ef641d012425cee20b8174e44d1e64040ecce4b7cb08aa93804cedf7b115f0ee614f6c07aa8e8b40a39df68d95276d5e0a468b6112f3aa4a8fa9b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfb1bc2f2cfe7eb564a6184b268acec7e5cf147b8e694407b98c9555175bef46af2ff1121b1c105f03684de429e79cc9de8977ae9f9b6e4cfdbcb7d7f2d09e448	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa847c0f6a5ef41abadd2dfff8b777fd56e29fad6e219cc0f227ac35295befc704f3b68d9f4c000c613a03d70aae3720c3a6f24fdf0a49d9a49ada27ae446f4b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x91b05707d18a705eff7c8ea877c206b64d2882e7788a26988b2021647bbf2458153ba8f07ae13a07c1561dd2caa8d1d4a4eb4712739f7d072561f24f51b1bb16	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd7ec20749aa4e6d3e721078cef09b950e4e08610f7ee3157396abfbb441ee94387a87a9403fcc0fca60ea4ddafba2fed1e80b5dd9a82c98d0ac75d21fbb166f8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8abf3df25c11c37f166e7fbc230f0a952b88c858762ce1e64021ca5aa0f68e216956ae9316e887c6cdfb82646baeb73ab78ba1b21608c1369422081f8057473b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x5d6a35b0039bd9f892d889a8d655cbe1dd6f218a4d27c2fb60c0ffea1dd42d88c44c94471a9ca7716285af86341162ab9dfda37e51907fbb734ca936c840b74a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb4dd9ca9bf06231dc0efb7117d89417e01200852951b49d5beff164515b623e82d80de13e6fb4a412ad91d3b8deac6ee9d3c447cf5b35c0b6e1372ba3a9cd465	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x253198ef5d832d1e9d86cda38fea7accaef34ac5c5598d4b6777543e20f8dee9cdf243cb2d3d357831ade8709e7410489a41e72caea8255feb0aefa1a6d91216	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd437027a31ca15a4380d6c803e120afdd9632e586c9ee7dc5367d385d8a7aec276141c5a2fdfbcabc8e6c0310bd2667f00d8d52fb8681ed9f3f568cf6c58e7c8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8f5e0aacfbd06c7b2a25b0e5dbe074e2677a325ae7ba7a41b5798522352c731228735f865d84084219733e1a4dbe554a90302597a133d8a9d6fae0b8d4bdf836	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4cc2e80871692b07b9c4919878bfbcdabe5374787417df53b184642451f52c286dc9ea946ad03d8da6a93b4450438334c5d105850a05aa0d1ba252c9006eb2df	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbfd352b8f215df815c7ffa67fa50be8aa7d6c91e1d7f8ccbcc54d4c53a96bc7f33d85b914f066c65391c506e6313675dc1216b58ac86d173d8ba9c0e5b991bb1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x2c0a29a09059c7fc25ad7f8bffe84782f6c28d5ed7301cf03896d93a374a0cf1e3e03aebd8ff1d11a66d9f52d280efbf2f1f933833fdbf488873863947282f69	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x30d5bb113e52f2d1acec13d067036ccbd0709ba8cfe6859d14f637eadb31fba1668297f15fe34b3364bb2f7864d51f00a9fde71418f09e4abadb6fbe06969d95	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb579b2a83efc4cec48e91ef2258c0522bd389dbf2d407bd86dc0ea9e419564a24cbd743db321563555f316e1699cab2357805bf25c6554719e075f2b6821dfe9	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa715ea55c69c8cbdc1cff56e9f1643f7fb7713020347d8a71604a1a83e64cdd58cf03395764428c27a6dde87eaae9873dc76ccbbe1362e22625bdf8edd061e5c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x460f7de8c4a4e67753d9208051c3b8f36c159e558a54c9d8644446395b26dcf5c8aeb6e6877f2e2442d3144b70b5c2ca7a14d199be798de39fed071da3ef7649	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc24416461566d94cd49df05cc2d9736c43707f8c0c94e2483e777092963726e5c91454b1100181e9408272a2ba57c8f161d095cfc82ade12326e353dc2ebc634	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	8	0	0	0	0	0	0	0	0	0
\\xa19dc1d781c0080dc36f0039c58bd5935110775ff84c876ba9427633ee31de02626a85dcd1fdffcf67b21947060deff0d6740722136159b68a4cdf5eec3b194a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	8	0	0	0	0	0	0	0	0	0
\\x21f51be1b55f9ffb04681052b588e70a1f3039e7c6419c6a4650fccb64ebe9bad213a27fb3f7e14d44bb1d1999be4dc8a99fd5e7fedc8d1578acb5d03f1febbd	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	8	0	0	0	0	0	0	0	0	0
\\xc04409ba4db16856ec1a6634ec79120eb89e26c765e66abfaa15a25b4712903047dbd6ffe62e84077adab51a317e593aa94ff0f320e796930b3be604e7219a7a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	8	0	0	0	0	0	0	0	0	0
\\x49b35e46f79ffa65c6c741a051928ae148ac5370453aa365fd23288d64445b25fdcf67623e9675fc716506cbbbbe2d26a736c81a0123b12dbffc5671bcd370a8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	8	0	0	0	0	0	0	0	0	0
\\xb78bc6fb1ccc05c2ecdac7364a9828b4537ed3d8e27153ea8c392fdfe1cb0809227ca921aae6670934ba4519e97b18b52f9620082ce3edbc8fcb61282b11a9c8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	8	0	0	0	0	0	0	0	0	0
\\x860dd966e3b87c4035b5bc02277dc284f9b8c35ede8c57e01c56b549280014eb40e23237572113c438b558dc042efee1a43c8fb67bd90be87a56afc33059f992	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	8	0	0	0	0	0	0	0	0	0
\\xc772074dcb622aa50b2138a62d0920beb9638a6660d2e0daf1909b4d30050b3a26daf7859230e998544d751ea95363651c2794c281aaa3325643f893973dc538	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	8	0	0	0	0	0	0	0	0	0
\\xb09baafdca29f583cf0c220b783bcdb17cf1bececae75ba403ff2c2e43623a6830abe38c65c65830ef22cb3012f09892c86b9d99d6f969995849d6b3f656b69f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	8	0	0	0	0	0	0	0	0	0
\\x3218f982f72390ace0d2cda17ac99041828b0680bc03dfd1dd1525863e43e788ea578a23547d9ed9e4ebaf6a39fb0fda8ea20996032ba6141fc3b22232098041	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	8	0	0	0	0	0	0	0	0	0
\\x6a35706dddc7bba8badae91a17952bc85b32b5cb1a8a42a125cf7d12c6fe067d354dfb3d6aa990e6676724609dd466a01759493fd167692fdaa91a2f4ce4ad4a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	8	0	0	0	0	0	0	0	0	0
\\xfc25b215861b6f808c9da4e0eccfe282666dc8b93ef8579ef8d5e20b586f1b682fe6f06aa9711dd7a3bb5a36369b5503ecdb696342ef4a2976f63dee1d5fad15	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	8	0	0	0	0	0	0	0	0	0
\\x125ebe17240926a07549268ba9cc5cb72d1fe1f278eb1cc1fbd79cd323e00651192c7478d1cac2af4a6f510fe3a83b0997219501341c235f88696e8b2f90b5ec	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	8	0	0	0	0	0	0	0	0	0
\\xb6006fa38112bd5feca8d67ef561a6bcf44c5bbf240e8042e22b8cd9f70ce013ea746d80c400b0f26f7dc6039b664c9b2556b55f98f2bbeb677b1fa7b7f9a70b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	8	0	0	0	0	0	0	0	0	0
\\x9340b355333beb73a40a999a9490b48a847657c5278c9a339b5f1d7ad385e8429acec50bc9ae54260f15648436710c4b15c17aa73a7c771cb233f1dfc59cd2d8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	8	0	0	0	0	0	0	0	0	0
\\x8ac7a1d466eb121c140ad1fdbbb244df9caba7947375770177d10abfa786177d34b877951f25887959e0859b2f828e798ae985d80dbf52270cc40da9d5418ce4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	8	0	0	0	0	0	0	0	0	0
\\xecde7c3a7c7bc7ef8b96f53153638328c85f261e7296bb4bea1e59f2051e4470b3810d094c45f637220eba3dbf27d7c07bfb03015468308a508221898574d504	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	8	0	0	0	0	0	0	0	0	0
\\x565b14a76b1ffa0b977f18c80d0eead965af12f467356795d989e0549028e1154285b70f7280dc6aca89c6fff598140625e5d31af9edee126786e56c6d5bdf47	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	8	0	0	0	0	0	0	0	0	0
\\x792a14735baa4f6091f48d30a157a6bf2922c4284c86acc34ca9818832728104988ead2da07cf62c17d9190bd9470ea141f1a1a7c95643ad81faedf43060d9d4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	8	0	0	0	0	0	0	0	0	0
\\x9d04de9098247e71420b282c17e335b5045a4a9e3c51145506158db9ecf7b0c5924176852749187417558641687363cbb15f8156b04ac213fe5c19e6f78aa52b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	8	0	0	0	0	0	0	0	0	0
\\xa613bcaffdc6b9e2e6d2d889d14211f9aef091abeb1b6cc2a49b070c6fa8c7583d64a29cd76fd495edfd78530a23e06757a4710904e93213dfda3f9cec113052	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	8	0	0	0	0	0	0	0	0	0
\\x31015661553ed6c591077331e4395299a48eb1f5820c31b93d91647b10a2c2555eccd171e98bc1a9518d117e2dc559a5010352f9220e62270e19b56541b5acdf	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	8	0	0	0	0	0	0	0	0	0
\\x447b69b64b8d4cc78aa622b256a4c903e255a944ff944bf9758b1afc2d1037d8f5672d0df640a74c258465b9a12eb97a05d1745a2a9f637265152c86976e48d0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	8	0	0	0	0	0	0	0	0	0
\\x5778c243418f324b5a454d7909e3f414816976a7078767fd90a457f550f0d3abadd31315a87cd1a82666240e3fa2227d59a482eaff0d063e610633a2e6b94d90	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	8	0	0	0	0	0	0	0	0	0
\\x44c938872e8e4c4939403b07da9f4fb2f4fee1a1332e5d427dde2b9655f05d4bcd532ae136a605213c66a3e970ef93072e6395880bcb0ca978c3734bb6c02941	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	8	0	0	0	0	0	0	0	0	0
\\x919e524b7e588f7993584313c56d3d0011969df569b662cb16c0f32ba93fd51beae9ddc8510f18c4eadbcb71c05b6dfe9c940e9613a94b3e6bbcf50fba8a023f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	8	0	0	0	0	0	0	0	0	0
\\x78326cc97b4e6597bfa528f8533c4c54def2f086d2b59d4de4b36513f17bd92fdca15077321e45d5520b1d2fa6ef249d8b051a1508224253c777d6f770f544e4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	8	0	0	0	0	0	0	0	0	0
\\x8f232ef1d29bccb9b71f2503208080ccde2f23a4e2a62874dd7979b182140eabba089210ca8f4a1839038de58f8356ba890b558ce4d73dcb8d14084c79498e70	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	8	0	0	0	0	0	0	0	0	0
\\x7001368bdc7a41f1f83bec7a90f2327c0d998a3234a72bc66baec3f7d2ebc7c5ef5e76a73537fe39beb58afaec94acd795074e41b35390efa0caa7616c19e0ba	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	8	0	0	0	0	0	0	0	0	0
\\x39fda68667b3e7e9b3639853aea0ed0e7308de4901bebfdd22b304b4badd2729f6e94716a47df37ebfb8be87aa091e140fcd582e088ef2e7254cdbc7f4d085ab	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	8	0	0	0	0	0	0	0	0	0
\\xe662001e4770f9ca50b20c5081575cbc61e607ee91bd012a2b8142b2d16a45bd698d8698e5d958e0e45be2ab5083cb6ec57dfaa56959da9b1a25733fd859356d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	8	0	0	0	0	0	0	0	0	0
\\x6d2cd90352e26f4ea3c5690e208cdb7c2b6abea8f12159c9b81c66ad7a0a2e3fb60fe72e68eaf215566d0820826f37ee92485504fe4019df457adf7fb4ab9c6a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	8	0	0	0	0	0	0	0	0	0
\\x7cb8a85a10560fb25dfec4b4c3199d9093f03f9e0cdf9b8947f16e39a8d65a0cc861540d1774a9f0d9e5ef91cd5f93591d4a94781cbca402f6c615979055b0c6	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	8	0	0	0	0	0	0	0	0	0
\\xb51be86aeb471046822a73026ca33a6b72044764b6f2dd0a7731dafee925adcad69246d7d6fb4f10ff5d22149507a6981d0d92b916b412d7513c57bcd98e06d7	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1281df4fd1e15f64e108b47a41c588d02b1d8232da4b43572e49868344e2b0953a499f7fde7fc8293bc7b5ede207d58fda477ebb7badadb29944ddb4e7037453	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8b9a92794eff8c68c5116b4924742c66bb53b7597ac24fb2ac269893d7e2d4f8abb06f614dd8aed0019cde32124abf8904d4b11a9c241784f02b911d314478f0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0db2780af722d30c707799be0492b2a3b85fd98441a4bc9e4fadc4a048cf053637304199a78fb87555ccc901a5ea4640351a98fdd26deea087e69916716f2655	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccd6695b525bace565fbb1a527dbb6413dccee290e5e1f7e1f513bd62b06ac0b8e8de2885ce79c184ce2770492b8fd90731cea7a9ccae932aaf6289dfd11a72a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb79a58be68f4f233cc62d7f83f13ed3b40b7dac64bb60d10f29eb011b906a6acce3fdd42a52ce7261609e15486876c9bbea88cc74446b298017698d6252e43a5	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2f458096ebba9ebb414066f5c6608d8f7c6c16ed49fc50e87fc6a5778ee570b0c2ca52abdaee2a92e55fb52872b98a96874f6d88d6291ff00bafdcad0d794af	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xbc4965012e9b5b67379cb7ae1973ce051f0faa163c6a2259441c58e6129f6d0cc5d8d8cf0ba515427232bde1093244a592712953b816742bf25e4f58abe48f59	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xc3bdcbb3ccae83c71577dbf668ed584af3af265c2b38ccd305b52c644ad2dc16b46e666d628ed639e4d2f9d1b9d9dda9345f0f98e4ef2f86d62c7164e111416a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe8d3e6c9a7ede5d17f221043da5e87ba737aeb4637356db392e4f562a7ee935e0261cea8ca4bbaecf80006012961b58fe6c4feabcd0702914cd45c9359dbec42	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x842663ade448cfc54dde9d0c959963be9cb02d10ffea44f6104157307238e924d99c5635401fcdddadf06fddc4edf25aa18fe8d11a100dbb6e4fe8b701fd2c2f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa5379312b65e839fe938766002311a79c98dc095ecf50cce22b1c92d25b604439999f9e40f99aceed7df900335f54bcc44eb815153874e359ce0d71b9b83d87c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xad2c6f6d9cac63444169ad62a03176d47a71cdd43aa0bcb02393fa127c8ca47aff47ee6fa4a6668eabface70b2b9efc1b1143a5dce50c87460bdd0b740f31a6e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xac8cc3bc7ab47926678cc8aacdaec3609314982f7413aa640dabbf58803d990be98c683d0d7e8d3d90a157c910d0fd7ab5376884aa85ff5f99d7bb8bd1af83bc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x71ced117ceb56bc29921befe3cce84677d844d47e58afb10896bbbac0f4d0241f12d4386ac27412b83e4bfc99c6f3bf9d5834e0b7e90d82c136dc6b0de781a68	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x3409b00a2f65bbf0073de98f9ccbfe716ab837d6eb09becd10ea2b7a0e40f0ad12b4a66daa887ca1f4bce21f81e5028eef5dc82bc870edfd250ced2bc19c9c28	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd9fda10992d761091ea02fb3717d563028e341a4fc7a7c77df5dbce53962a2e6d812fb82569831af92542e8aeee62b1ab347565b68adea6084d0a622c05a87c3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7f45727b55bd3bd87373b64951d154752cb36c0622f488644c62ebc1618e3c8e85a56c0c33dc9829b3879822fabfb3499c1360fc2b806637133f8c4535e96662	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x4307c8975974d7be51250422aed8ae58ee6f2b3aa44c07dca81f6243929aed2134558f74333579114732633a6aec37bded436ec98607321e77ddd22e1fb6e22c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x13da7df5de78fa7fc592d304d4cf35fee6d2f88c63908bdb2a24cfd1c863eff720c7df12e650314c82dbe4d2784b2470e2df85d4343868109df79e8518da25a4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xa3eadc0f7b03f944f3efa305295fc0e69e976d63de457d379c8f030f20091acc9db1d365fa7c645ce4722c7f1bce426489d5c9d862cc9e9f263c9519c365da75	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39223fe71a25a9bf879cc997f46f4a615bef188be35289dfe062028eb6bc49029a697dea9e4155d186e5fd48ec76a92d8a44770ae91d4b70cdf6c99c782b55be	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd89025158eb9955f21be8acdf7f240ccbcd76bcc24522082013fc29219f3e79577ff54e16b103cc1a02006369160f7a7ee84d5c0104f6b6a1f626f036bc23c99	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xabc7d3981956ac65c72197075647f692d80e0b29d40dcffe5079b8c673a1371038ed770ad6fc034bfe7dc2a717836d3bb5a79a4c1ed8af3ef331a6d69d6d4903	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xcc8415cfdce11de11d1c4f76ac125861cfc8b5399ac62419992fc2b5e3215c61d1381212f8c9711edf6fda83489bcd4c5b1f4271994c77ad9129222e3e364c26	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9ac9ed5778ec3f2f582db4b78b921d58877f413277fa2646af1b15e95b712bf23e51eba713969cd622b64eebfdd5a56c27b83a9dc122d74661ec462eff7671e0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xd2c09b24217fe5475e96b8e42242902cf8c2f9567991ea8d4c3b31d6f7280b92ff6ccdeaa18ff4143ef6f4414d286f873e5783beaf1d05f09a2c9dc6ec802b00	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x7488be9387065e5924c5857eb5dbf007fbd55ccaf17fbef4041cc8f5714ca4bd6eecb24fccbd358fdcb260a384406d5dfb0b2d7a041f6def2d090c6d7f3fa733	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x278216027d2fa091b4068c4fbe2f1884a6b049372c5bf063c204dbe632c8ca05bf504a8ab049beea1780031020ffa0d2b49cd87276c17e83716a3450e64d3461	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xfda68b4bdae1263b81cc33eb5715f346de8a9e86c8dcda304265c6bb450f9af021671ca7f5b587ba705b1537e1981f244d4245d7a5633d49df49e24f3b6accc1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x73fddc957a76606bd0c51dbb59b944a66a82597fb336620749a6af6246e0f499f514a326e650050354f6a01503a4663435a7a0078370e27534ddf6458ada3c13	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x107a03eecf4779d1d3fb6d76e841f451e649cf3891511f6772d3ff11fca73ff58bc7e28c9bb297f48cbc2da8b8fcd1cefb1578b0d30fbed50d3ee5cd5ffb9fff	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9034a2cfa82f60249464cd67f44b91af1e02f71cb6a93ece7e890e2a052383d9204a6212074a52a152cbb9329ee48ed8c5c0e9330bc497636cf6d44e086d58f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x39d99c4d8936c39a9f0e52fd0528605d89a2d35923de5ff68f73a616e779fd7a6fcec4ae0217f286823b98c874d17edbb5d95126dffb353c883c6d0f130703c4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	4	0	0	0	0	0	0	0	0	0
\\xae596bb7d18d0d6ec473e9a7eca8874a6337a6593ba96f0bf02b32529e31829585d71174f7ff8e2d8688aaaa73f6a3cfe41b76398b2c19ee457c5d27d402cd4f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	4	0	0	0	0	0	0	0	0	0
\\x80fc4e14191e19800b0eb200da9af0c6a87703638a4547596b30956278e4fb7a76657cec1ba88a075048d2ab000dfad4ce71ce4d52eca26c9d9be6e27172b66c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	4	0	0	0	0	0	0	0	0	0
\\xb55dff281977db9535bd6830314040e883b7edfd5ee6fab6fae9832a4b5eb76ec21eb6134b8b6582527ef085611166d13f7ca1aba0462562bb7a2e6a50cda23b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	4	0	0	0	0	0	0	0	0	0
\\xf75aafdf0147ecf21880dfd5843f37f9976ecdcbd0e013ccc38c42d0971cd24cb93f8c2f1416435341b50a75591ecbd746f5200b1d1cff66ba5a6032aa19d955	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	4	0	0	0	0	0	0	0	0	0
\\x2170d8a960f6a4371c3260691734420cda22c87237b722c67ff77ab37040f85fde15172d5b319f45cd6022dd71b3878187378e552e4d9af173fd414819485920	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	4	0	0	0	0	0	0	0	0	0
\\xf2ba270fa98096c9e23cd7f3e5fdffeb51940b6318dd6a4414167f2aae9f9fe601e8857eec63e33b734d16c2ea1fda5fb9cb8ce2b7e2337d76fc7cd60acef559	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	4	0	0	0	0	0	0	0	0	0
\\x444b048edfafa76ac16510780ca4b607cc7db131bb24f3a617d6a789661045c5f722f73d073fe2b5cb5a4959e24c89b0fe45a885697dc47d7464dd334e351589	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	4	0	0	0	0	0	0	0	0	0
\\xf32334d7ddf15d8af3023e499117124536349c60fac2d754f45cca9ecddc30f44774a77a0d362cc9ae649c8983605e17f7a881763255000ede93a260deeabcf9	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	4	0	0	0	0	0	0	0	0	0
\\x21c5e46fdc19c553acf34297bb01a8898c6b36ff0f4210dc71ffe856644abc4c3d8a56795f56e7ce516be91c1635ff40cf0bdf9c6af976261dcaa175c5c72cdc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	4	0	0	0	0	0	0	0	0	0
\\x0fa3a698e9663a1cf7e1926206e60d5fa9ac51219803a7183c3baf2d9b48209c193569cc4631110e8ba32409de0b9eaab16d7adfd85dbaf16a72643e4d48d0dc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	4	0	0	0	0	0	0	0	0	0
\\x4e10d6f46b32cb45f07c8628734773d6ed13a18c23f45eda499365bffc2a66189695207ddf263fa80046734392877742af37185548fe3373a509aeb3085cddc1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	4	0	0	0	0	0	0	0	0	0
\\x9db7b716ccd7588a30b7d1b1f187b38e18fa118e6557125c11073c0e74e33768d133441068be3ebf1c756aa105754269002ef66c5a996fe5bf81c2e408c5d7b3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	4	0	0	0	0	0	0	0	0	0
\\x8b8b67c868458bbc0e33ad4e4400edf2aa748dbaed2bccba86d29921900670f40774914dfdfff71b0aa0e8876bf38010b7c7a1ba21d1dde8d3166f7a04b8d232	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	4	0	0	0	0	0	0	0	0	0
\\x0a1d4175a471017d9d41273831ee00e7f900cf373ed377bedd843fc77b0a227f7a0ce785e1b94527fdf19b5ecb1fda0d97e1f4e6c882c173b8227810eb47140f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	4	0	0	0	0	0	0	0	0	0
\\x7695720d01d1bc3321db4ae68b072be6be2ea6822baca6cbf2a1df1d453acdaf8db22165dbe7fae259ad28e61e295bc9bef1fa7c69c8a5941fe27badd856d817	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	4	0	0	0	0	0	0	0	0	0
\\xad37469a8d1bc9a3de01eaa985d0b5834f8d95ac7cae023f5822e59d8e4b75444259699223389b3d0a5d14c14742838a758fbf20480fbf0c22490414a27966c0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	4	0	0	0	0	0	0	0	0	0
\\x713e7ba1a527873d01943f0669f6093ebad6732bbf17ff79ec0054ed71453661fba968d42d95fbf565a7018530b4dcffac8f624a82b5452cef163e9df1171f86	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	4	0	0	0	0	0	0	0	0	0
\\x918fe7cab4225e5ac0f7c2ecaf45fd049f25ed889a441d34766ed9b1be27454624548ba1c4019380638fc683adf6af726f904f767f21dcb9edfe1a1294258d0b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	4	0	0	0	0	0	0	0	0	0
\\xe1d2f1e819408b9ecf6f53b1b6233ba7a57377beabd417a5970e1e02381fb9f69dce7fe890db161bdf5d60ecc4ca9bedeef396e0432c5485820d39c90776fd61	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	4	0	0	0	0	0	0	0	0	0
\\xf6aa42463bfc2311ad6cfbb1317f94c2f71c05bf252dbcd5bd75b61ff7d51e4591381338b67b8a851e9e2135313851619fb838c4fe42154ef882ae2ff18df51e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	4	0	0	0	0	0	0	0	0	0
\\x060b27de7612111afafc29bdf0283f345aae12b72d8246d5f3a51795653b104b2099bcb3eef91c1b21b8ebb38181d56382e0fddd5a22d7e38d71fabd4585c6f0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	4	0	0	0	0	0	0	0	0	0
\\x290f2961524b07ad060e0fa27501efcf05fdff63a716bf7f083b70cd65e0c968587fc5ec135c0007cf7980fcbdfeb9dde684df9a6d126f9b4ad6ba469fc6f638	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	4	0	0	0	0	0	0	0	0	0
\\x5a7f804009ba5708cf1d16ecf92d9655b46781d50c623c161db66e9100921689a329a3d55eeece2fa6192955ece3fb9ffc7fa491c437b944d7a15ae9f21d21de	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	4	0	0	0	0	0	0	0	0	0
\\x198c8026f3d243afe886836d396d060824c305f76148c499308b30fd0b3c710fdcfba4e4b713e7623d8faec347010e3e0a4a8d9558fe0dbfab9a13d90cb8916a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	4	0	0	0	0	0	0	0	0	0
\\xc67a76516c1b3e4b4731a984d24562056c84d59d12f920591cd0bc529219ef7956e0df1df0266e3e452a5cb54251564ff4c024873872f63a3dad565680e7e692	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	4	0	0	0	0	0	0	0	0	0
\\x8d266fb5b82140f7af3b4a42f0531dd9c278891706deb92a7cb4ef2ff6b741eed8774341f6eaa421b20f0457452a75ac1c7615d8556402105a017bd00f40a142	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	4	0	0	0	0	0	0	0	0	0
\\xb2f9c59cfd1b53d3c1f6c6bad681da6c44673fa391e6c88bc7db6406689aafe5a70dac16b0a0bc2f0c9b160273d86d2c63c21a4cf8250905e9ac9012defa8ffa	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	4	0	0	0	0	0	0	0	0	0
\\xd71312f673930ce978555affb4cdcefcc66804d5d689be899daaee2f4fbbf0da1f4fd4382b14e8368fdee7c47bf4c6f4d5e21fa312399b6acfe1f6888f9d5f82	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	4	0	0	0	0	0	0	0	0	0
\\xca4a0b8102fd8ba8fa0808566025c8bddc4e55826ed55362798e90ca4967271b0aae79191d9de2e1049acd88454528e138d6aaf3fcd277117f43352d7530c1ff	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	4	0	0	0	0	0	0	0	0	0
\\x6615ca007deca5ebde8a9320c44868d3d7b33b0fd043f5b7fe99ec138a6eb4d6d9da92ab682632792d9f59da1e363a7c135f4dc9f5e456dc2e68e7f93c0360fb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	4	0	0	0	0	0	0	0	0	0
\\x26868ded549ba4b97e6c19a17e772a55889fcbf2acbccf8a933023d3b8351f8abd151ecaf4e30479cad2352bcdb000ae44a726b69a055431303cf25eab676bde	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	4	0	0	0	0	0	0	0	0	0
\\xa6938a745faa4da00957e4e1295bead0db7b4b4f8249fe501104226cd2f1f6e5993bdd8f9c58e92708723c3fd82a56ce04a3b7f3d6158eb5ea54bdaca5cd74dc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	4	0	0	0	0	0	0	0	0	0
\\x6fd4ecd17fe628bf6eeb987f60d1ad5b503637ada12f271855ca25e95e8a395f2d7b25fa6cf4a5bf725d5e82917b4b81729231100cb72ea16ccd653862bfa0f4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	2	0	0	0	0	0	0	0	0	0
\\x20c97275e330eebcb898f5887e504ddb1aeaf6f86d4e4663c6bfcdef2896c7c1e2838ca68c06bb457b3d8d6c21129c54877ce4004068aa81e8b44adec81a9287	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	2	0	0	0	0	0	0	0	0	0
\\x8e01f94f01df22ee86e150b7a1fe6caf76011f9ba9b8f879df6d6fbdd32ae25f3da8d7557de1c385f499182651e01436d6befa739aa032e9bd5f13531874f239	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	2	0	0	0	0	0	0	0	0	0
\\xea05a8ef82ab0641e6e37c1cf05f6709a512416f8e10f471149a3b04b1bd4348bf226bfcfcf013818fd269b09edf611d1afed9dc61352953afd17ce8ee6ddf4d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	2	0	0	0	0	0	0	0	0	0
\\x99fb2bc6183da5f6e89846056f2a581dc317cc6d9a6cbd07cac5ff73f3d67f30c89e1affb8929ea43c54e7712997ad8714d9efe24d2a9d9ecaac13a966c961f8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	2	0	0	0	0	0	0	0	0	0
\\xf419a52f204fc055b8de08423e987d76651d7c7a32108e7e7cf0400eb3e6ac5f91897235c454d80f7ea4757a7212dc426282da7a5a2ea81f31a933f8819de3d2	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	2	0	0	0	0	0	0	0	0	0
\\x83eeefa08f099c99050dd3310b3bd550dbb833fcb511ecbbb9100d8313d7067f1fe742e081237b59b4a7970082db9c2dac9cc70309134cf1f9985016f82db3ac	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	2	0	0	0	0	0	0	0	0	0
\\xc1040215e3bfb61c67304d4ea275173a81a2d9fb58dddf59f4907b67f86e32598b2b40ad6f697bf4c52426e930787b7b82bb2f9be9bdaa1601b299c89d1fbbd3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	2	0	0	0	0	0	0	0	0	0
\\xca97528076dd9122774a5e2a05ac768a67602e0baab1dddd11f2b0a8a21999a6101a6e28fcba86b23246a8ac7cb7c42f4f3eda62325909db8360eb28d8a8dcc5	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	2	0	0	0	0	0	0	0	0	0
\\x555ba619329394cfde60c47db57c871b818b070757a5bafc173613c5dc0b31293f003ae80c27c274830989f51afcd55df8cd6b8b605f7b8f53652863ac427380	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	2	0	0	0	0	0	0	0	0	0
\\xce32ebfec0d53249df9da4a53e96b266a40bd6ba4232f123bb74ea574d125fc081536268cc3d1530b8d088190817ccb47d8b45200c037e28427f9975afcbb9f0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	2	0	0	0	0	0	0	0	0	0
\\xd9616d2f0d91d3476c753bce7aded3960980c388bc0ccd48b50932ed7f5b5b7d8175101341350460460d5ba4ccf88d8c390579df67a465bf8c492e0f687fcd33	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	2	0	0	0	0	0	0	0	0	0
\\xbad5656336d3bd396ff6c2f7d01a822002259148040878cf54b4a224c757bd6b89fc977c4fa9ddecfd7842a05e2b5363ba7fdbc98ab43e17e3292fa4e53e5583	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	2	0	0	0	0	0	0	0	0	0
\\x242da8070e436507cd15e013e30363b43112c0dfe0926e596990f8572202a710af6a34efc61b2e5c5a475d3e910cb5c0de2a7911b1bd7327308c201c4c13ba48	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	2	0	0	0	0	0	0	0	0	0
\\x261505da8465b3e3249dde6dc6a738e1f9d9c5244087fd69d8bbded919a91c4ff21a6ef8e8975e54487b0dc25d93f905fc4313e0606c618e20afea1f1bf8d2f3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	2	0	0	0	0	0	0	0	0	0
\\xef1f168767a5557d20ffacbfd4ccbed312d7ba2ae02b46324c66b1b77161ca10f93d993ed1fe155e1d04a68acf6ef80ea8f46450fd12ee38f1799378a59765ea	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	2	0	0	0	0	0	0	0	0	0
\\xbfe0a8dcbdf941d71d7c8ec8ae1f38260b1eb4c13950148f564889d0c16cd96f3487130b8c15f6131b218a83db764409c3394987af80929dfb215f7b50a2df39	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	2	0	0	0	0	0	0	0	0	0
\\x640c842831213acba1a177aa8142055e5c28d5c0879be6818439d6728819349d612fc668be36a325fa39cb53019900793584918d036f9ca211a53c8bb041f38d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	2	0	0	0	0	0	0	0	0	0
\\x25c480bc2a30d4529c75bfe793611ef28b031f7566f25cbeab7d8292075eed7990797ea7b514e7759f61448f15f17e13f183164ae5412ec3453ae2875e146f60	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	2	0	0	0	0	0	0	0	0	0
\\x8735d4752dc1074dcd0c228f765e9e694f6d972b13b9256ac4e292b2cb584ef9885a24213cc52175a8c90f84bfa6089733a3a37ea9fea5db9729e919f8d5f097	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	2	0	0	0	0	0	0	0	0	0
\\xfe9bc6f3fe934daf29006cd0ea85ebd8b24b675c83ee3bddc4333259029a8d11676ad870f5854c28359ce29651dc270e8724e0c34216f18ede89e67a996d9874	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	2	0	0	0	0	0	0	0	0	0
\\xa93a25a1018d34fea47b4786f131f6cf025800fac272c7d28d04ab6408515f495088ce3a16d82ec0ff951103b787d9a43b1334b868dc10e7fd62251219fa79d8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	2	0	0	0	0	0	0	0	0	0
\\xda65678574c7cb85b6aa71e1a5d90268dd0af41e32d8addc88dc85fd656a420b43b974811d964f31237e198c6945d56733d26d9ddd2059070c0f21967ef4c879	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	2	0	0	0	0	0	0	0	0	0
\\x35b5fb643424f898e105afb91b69ea9f2ebb3da9af056228a7d24c7f6197eccc9a792918d52d1ee044c53b9742521fd8cdf40026c8e52eac7f026397b12bcfaf	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	2	0	0	0	0	0	0	0	0	0
\\x82620e1fe66436e7c7fab02d6ca4005334a84c20971b7c5417207ec9c9365c692e1701c6ff68f2d6a967ca1770e64d5069fce15d3cf29bea930ef17e1df09eee	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	2	0	0	0	0	0	0	0	0	0
\\x6dca7901bb4a39e8ac06d5e140f1bbf1cae9d8b864b42ca579d6ddbb18795d000fc2236b8ea59f8f0ed893b1a9d33a06f9acba3622711cc48ee8bc2e2f9325d1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	2	0	0	0	0	0	0	0	0	0
\\xed236b5b95e35a5b65d411eb49a4eaad519ecf4aa6beea85d9bf06ca797f84de830ef748ef60bb63814425381fa3f3924a62a2fdc29e08af6c0b884388af9cf7	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	2	0	0	0	0	0	0	0	0	0
\\xd362b088e4c59a904bd7320660322676c70d62403e906b627d0e3793b43582bf6e45af9c47c28d1f3b4f8edec04afadf1724294e2074047281bce91e7b180616	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	2	0	0	0	0	0	0	0	0	0
\\x3dc7713fd008050a2114ac3ff9ac7f6889c881eaedf18988db0045cbead0b6bee3b356167c6d2d2d0557530a93f6bc7996d6fb3cc6f9f9a71a20f12b0fe5bbc6	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	2	0	0	0	0	0	0	0	0	0
\\xc27a8d827dcde968b3ea4f5e5b521467f8b33c8b5812d7d6d52869bb9fba80c1c2d738c468135b25623ca09d830e86d4383a91c07d8fe3fecfd05e404eeb4804	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	2	0	0	0	0	0	0	0	0	0
\\x7422772c94e22969ec7b9dba85c3fc13f36556490f471997953ebb0586f86e859f64df0816f3d4085114ba4069fc187a25e58baa172be8c57e0186227d2d9926	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	2	0	0	0	0	0	0	0	0	0
\\x94475bd8fe9f8429567cec02118507378d548ec2327b1c9b6b001cd387be38892cc7493902a0769270df15cce6a74dcd71ff1534a36739657cd873ca1951196c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	2	0	0	0	0	0	0	0	0	0
\\x30336aabd5babc9a28d4b6eadc173f78d5589a16a71944e778505e68da30f4ae13e22469b435c7a025d9b6274031dfb5d1fd00b0672da90fe64445d6408873a7	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	2	0	0	0	0	0	0	0	0	0
\\x9756b1d8e49f72391e701a9df899f4813cb5db3d5794907b609f32669428153a7e047c033304c904314d5483ae39596b3b6aeb5371a3ee348bc897bf8a74118c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	1	0	0	0	0	0	0	0	0	0
\\x6338310a8fdd078ab9a7b690afab1c800e08f4fdff2ce642599fa7dc384d1477cfb7f2df86ae3f5c59739715c6131ddb3ba72371c1e3bd95ccc2e5ff5b5d928c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	1	0	0	0	0	0	0	0	0	0
\\x70f9c018f09613c8718de8b107768f0986442e87e9a8e29ae365fece22e45b63fb9f0f7e1275e91b3982f8a5dae79a899fb5dfa2c674f94ec3bce55c9c461c95	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	1	0	0	0	0	0	0	0	0	0
\\x8b32325989b33a4abebbf39c3adadfe01afc270bbb756f0fc470023929798ff5f19b861fd44f2fff17d9a1a9925ffef695be5aa5cedfaf216600d6a37d71d9dd	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	1	0	0	0	0	0	0	0	0	0
\\xd3216a14065935f4674cc7581be72b6d758755d76b08ef6c74dc953553fd3b6eabf0da413148121c04dbdc02cb5808d69504b11665bbbf40bb7ba4da982d180a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	1	0	0	0	0	0	0	0	0	0
\\x4f60647005119246243d4abaf0b58f4288828da8d411e5c2d75bd736cb6d686596f5b7c37b9a8a1896e55d1547e79c45d4c70d2fbbdb92773aeb5a878681cac3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	1	0	0	0	0	0	0	0	0	0
\\xd485e40bbb8be93595e7bcca236e2962d0c482e7ff00836d7ea04a4107cc571e77cc9b5f953314af06b60f78c043ed87500bf031da52efa8637416dc189b9d8a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	1	0	0	0	0	0	0	0	0	0
\\x5422ab23f8e1867ccd40001cdeaf7435b29e472e1dafcb019c2696a3e36acdac073ecd470d1bf7514864914d35b0384f7573944256d942b1aed90db431250776	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	1	0	0	0	0	0	0	0	0	0
\\x43ddf6243ad73ef2cbb9b17e9eab7ba3f0c7e76f03c107cc0fc03cd05dfb553a5ec2864c484e60e9259e0d0a41d7b3713f074f92ddd9b36e8f95fd9898c0f00f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	1	0	0	0	0	0	0	0	0	0
\\xb8922eab15397203d58386bb6209aefea12d297940f8ad9e3db59490a1275a6852999448da3480942a114c6f541993c374316e131a2fc0403a35b80fd6e6dab5	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	1	0	0	0	0	0	0	0	0	0
\\x0f9166f9ff862df54a04f4e535e7111994a11889dbd580aca7e88aa0ab8a6c2c4c41e887abe8ee50293432a1ecbe9a60fb454be0cd4ddbfbab54272aa7ded4d0	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	1	0	0	0	0	0	0	0	0	0
\\x67f5d5bf15c89237a31dea791bb8af8191a6ba602fc17b068dd501cd4345e61fec742e1355e6ca712ca446066bed415030985f556f123ebeebd3ec669696cacb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	1	0	0	0	0	0	0	0	0	0
\\xa9f2fe0b414fab0857f307a3bb9526fc95581f519c408a3ea8a441bfbf8e48b9693e13afc122d4eaa0babfeb69dac95ae874bb910e0c969864c43172c40579bd	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	1	0	0	0	0	0	0	0	0	0
\\x2ea52991fa2d2ba99122224165365bb1c796f2e7abf32e900a7299ebe4ca99b63d85644727cb87ef06f781191cab77ac050ea886b7aed8f4bf989e229ab5a0b1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	1	0	0	0	0	0	0	0	0	0
\\x988c018fe69e999080d093578300bc07945db9ef9c8d2ed2b76c1f41219ceb332034fb5987474e1fd5f7e59ca1b68e1e56931817f8bebdabf45a98c936f6f036	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	1	0	0	0	0	0	0	0	0	0
\\x0423404fafd9751ff3244687b842964a22be9e9e61f6f4ffb64ad79a5f209c36acd3a4251912b3bda0f56e22c35e60f191f74d028fcb0e59022ba9d03d864c8d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	1	0	0	0	0	0	0	0	0	0
\\xea42410963a9ece9effd586ee24a4c9f5c864df1e61edb8c2de03cf3d5bf3adf3060a0e6289bd75c450d58bfb82325a54351246fc8f898eee80d33367bf4a311	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	1	0	0	0	0	0	0	0	0	0
\\x0e2dae88a9e347345a69028ac11049355721f8ae6a1b4920ad224a6a71ca40beffad4ea96cab6330190c209acdb6b228abb8c516b89de58e2ebc3bf9be3fcbb6	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	1	0	0	0	0	0	0	0	0	0
\\x20dc561933bed8384a7228c42551baab4ada3198cdfbf056c9d900152b310fb3540c7b5ebd78af47360dd3c09b30577a29b9c52f67b1a4bc6e309fe83aae5b9d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	1	0	0	0	0	0	0	0	0	0
\\x711fd937b973b29a082b0f7debb3a857fbf7cc2a2349a6fa97c5ebdd70a4ef6ed1f63f141ee37ff87d3142062fe956098b774622e9eb1a8cfec2c2a7fe351493	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	1	0	0	0	0	0	0	0	0	0
\\x157dfaa658003a85a84eccb2e1f9c2b062e6b88e1dd19e1e91d2429f7629c0759e34e86ffc8bbf809e5915eb054f27aa96e97ef7d87e71b29803bf9e13dbbd5a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	1	0	0	0	0	0	0	0	0	0
\\xab64e86610693e054ec855a46b79f5f06c551ed9dd4c7870cf766420aa7497b7f45db603fa956998c26ebe1bde946b1db107b366cbbfc0ac1e4857149eb9509d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	1	0	0	0	0	0	0	0	0	0
\\xf6a6dfd7cba553fe128a0d0f68f639ec2a1adf7086ddb4262f1f2690aacf49d25adbcba350d07504267ba2c452d2501636b41020806b3a29f4ff3ec8a7ac3bdd	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	1	0	0	0	0	0	0	0	0	0
\\x82efe07cf4a715cce430d4f1cf6987eec792df5739a3ba524a3f03d837785adf2172be7a12cfb986b0157f6df0ba165a4288efdf2ae161241447890588d43f5d	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	1	0	0	0	0	0	0	0	0	0
\\xb13bcc3fc36335b31b496559d664dc40db1e154c203d59cdaa13e826179e1d519336f5ec5bca613797ea6af4ec0303420f629c87f8be4f6adaab9af8b7213dbe	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	1	0	0	0	0	0	0	0	0	0
\\xf834f4d092cfd86c16a8c9ba564e1a08bb69449538a01147ce0d49a36c86bc35ff2e6b582bac814a8939652ddb8a8161d957d0202e91861f463c511f08a18782	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	1	0	0	0	0	0	0	0	0	0
\\xfb7abb923a5a1ad7685fd7e5f0b13970f119c7f643e307993098b9a079d67938412c7a7b5f502cb20860fe049b967255de56067112736463a203ef5e0ccca556	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	1	0	0	0	0	0	0	0	0	0
\\xfa6ecd5e92352330be6b3ebd78fb3f1484f0316cf65dca56bf731987eeb5eb1d66ebbc90678e59c5684d840608e4972d3cbebcf409fbb3e2db04afb2bd541faa	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	1	0	0	0	0	0	0	0	0	0
\\x44fcbce04514eeec663e14fb64b5a870bfe57e1e07bb4bde5444b5712f2dc9f8de06ac050014bf85f694e753983ef1b7cc03585c5ce789c155fdf1000bb482cb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	1	0	0	0	0	0	0	0	0	0
\\x96a1eb6b8a50bc6cf7de272f704f2bbf9d00116314cae27babd786f18789e00eb8b1149e9ca704ec00dea9afcdf27225662aeacbdd74cfa1b2cf76da9b8cad2b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	1	0	0	0	0	0	0	0	0	0
\\xe13bcb98a438f643fdcaa924035ef15ae62c0740b4389c2c6da92b65a07d96910e5c353226b80857c188c3fa82db275687a4b8bd8cb43a2ce26933972c2b15c8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	1	0	0	0	0	0	0	0	0	0
\\x76b82107ffacf1fe922bcc6ed8baf220a0ff291a57942dc56fe09994879424dd7dd0914d430a98996a7595e4183307e2dc016165d06047d75290360323742df6	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	1	0	0	0	0	0	0	0	0	0
\\x08a966e339cb22bac6b38f9fb5ce7f1e01eb93a8866a76b8e1752c3c407db45400297554ec5632470dfb92975d514ed96bf73762a9fc0c99994abdc15fd99373	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	1	0	0	0	0	0	0	0	0	0
\\x75fb53b4b933f40469ab33e5d4b8c67be60035935a12e76ecc28ff9ad0fead0d97ad7bf8b4a22e7263285492135331b6cba6d80db6fd6968bb831a10eff5d44e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c96f89b98f56ad657f8e379423b6d74e203343e49d622f8226f187aaddfd73b9307d935550a6cbfbf9e5aaa42af1e3120288d0f12ea3505a4fd8fc2e17d206f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd71ad826b05b528b37b3313af07c3a3f33bf418760173553627826c61c0e3da80681d4b798d1b78e87a4b99594498f39230cb104c60075936a984e8ab06c8f1c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8acf1a2a804a8b66969e9c22c7aa4e10ea01cd394e3a2c56e065a7d2ff4178a4863cefeb553fa21a7a5de8421fda32ecfb0fa7f7c42c43be19d61135092d5c2	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x128f6ee283c1ff79b7bb8771fba7b8623a947f2acea62069b7cfd2faf5f0a8864bf87a0cda987c60faf0e16c0172ed04d53039a2127ffdb1b2c6cc6851635067	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x22f83e8e212f171529cfe7bcc0f694c28808463ee7815efe70540c34a37081b6017e34717e5cd4dffa927ac4d5efeb850dc8e83f7af62c0d12f094706883059b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7b9ec72ac17eebeb00946d2a87c9fec750f6e114fd97ac0f88973a369c32c9d6a6b67cb5bf4f4264a5264dc696065c84ee527c71512e0c1f9de2569d4d0750ea	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xaa835d8b8fe937c576fac0eef4f9132857b0f6d1efb8fd9869326add2cf6f442490bb7c2aea25dd5810beb6a09570a5143532fe87aacee3920a6e28334695239	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xd8111fd6425530945614910a62b98722d76b0ec78b69a54bc8e8f297c7e9b68183471816746a939a6ae05576f0ca8e910d17b16fd2b7ca0462f9e0dec858bd7b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe9e6c337daf9bd574ee619a6db90be35abab95abeae030818aba8b8f85f6d1a94da7fe824d17884beb4289d026130314976cd269816c0f090540fc83f67c7227	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xeafa9af09fc779d03c02982e874754cca32c1a8199f48f4df616b9933d9bc881ac354a07a776976c2b4b59e243aa36739adb2fbc1fbd8aadc19cef55eb4d4c84	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x10ebf1f08b3feb776975e87ea7ff2b8eef8df22d50cd80b85cd78634388f3b5fb350bd16ed000e8eeab9e980db18f1f20aab5aff905b2c418803bcf35c29961c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x3c31cad57b6d3b32dbb75831d66a33b00caa50052dec863f51c58a7a9db4983de7809ec3be86a08bc5c4824aeda0bea7e3dac4149a4a2dd9f8fbb2ef1834cb0e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xbab4d1e31a75361b3292558c919b7ddcf79e448dd4514c9e0c7c2d9e9949e1d2cf7cb3695fcd45f180b6b13a02aa992d670c6c9602dfc123dd33b9e6819158bd	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x676e231785de71c2156f77ace6d58ddb4d4d8fbc29516d7e3856ef12bd81a54922fb5b911631cb9adb4a27874e9c1558a908848d37a39b52294f723f42a45fa8	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x12a48f8f1e95d076228a8c5bf13042ff2f9f3658df73552435c5d705dda8adbc8dd31a478ec670f0f1861183f29decb40aff3ba7a96827c73d687585d42522fe	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x325018881d735c9976187f3407c3e9243e1c82222c3bb7accb639a4d60993d71680dba6f90e8266d39d46573cdf8f135e8764c12c25ebbc8a3031c83501b80c4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x81fa2027f246c185ffc62f9e64f9148fc506f2f7b7f8f46a7818aa8f9542fd33cceaae8af134c55d4131dcd6c9057110453256f8791b73431bc617387743398b	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xadc25dd0925bd6dcc0acdd965ad6ec6923d7531cb4e646cd5cc50213d5996f070e73c6d65cda681b265d2a8a23c71161db333fd8ea0c4b9aeeadb1436966ba18	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x74d5d213b4ab169a3674a54ac70c1352e254d86bd51b3e930aa5c14614b1a5e8f8b5d15970ebd3559a4bff48485edec207966661ab6d452017016b1d0c4df2b1	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x57dc2a948b861400e89155e9debff9405dc314dedbd3c7ab13f9a90da0c65e61c8ffe663d1edbc2d783b87d5f7ad8d5cd4169435815985e064e536e882cc2aa7	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x90021fc59201c95ffce889cb60b2fe671e0dd7e49709cb05a675b52e174b7b96d0c44fa05c95a205c6d12f052ead50c4c93c4134a8432cced0e4f9ddad353834	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xdecc38dd2f0e0b518638f28c0cc74b92e8c2d17c905700dc80a640ef1dad5b97a2cb6394b964645fe65a7e6db6821b10855e3e20df6fc2f6e51462efe6a2b6ca	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xff11322a28e2492acc17a3dc9ea6f97f21d6593dd8374f41087a82acbecb49aec8ac5126278e6c8ac3a64bdba9256331611cc527ec6d40dc0435b987ea71755c	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc1e5979c65125a6debf736cc4089ad91fa2f86b60ea29436e69f02712b9a59d51eb9f1cac0640adfcba07b7f5af461cd98691c95be81a6009c70cb8debe81f63	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7e54fb0a7a52068879d0b7bec3d1796a671b033628f0984f12f9140556bd0b8339e7ed2eb86d0026e61e0791c54667583ca12dfd85b70a9a773cc9c075bd8e5a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x19ef215ef4fabfbac0d016037bd6ffa774956365261acba8b223e50f81bb9ecec33c090931db3fabc79c42f0364b7d40e5d2e5e5592c668e0932ec56162f8717	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d1cce15492f1148fb477024ae02de05055c722043c198c36764cb27019410f562fabce2a483d14af37f92336cb0c54c00e584164355e7110fc092b90bcab666	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x81452d566ad9cc89b6ef4c1cb45ded50329d6e6cb72f7abf6633d62d7d468933d511ba67745a9c8766e144b5ef68f683ff6faa620a9e9f203349b9c990049635	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x65ea6d9ce23afcdd1d5a09bd291f6adc5d379ab71169d9c5829fac014e691f644c3383149f840d0955ffc4c50afa35b5b06655006e5236f7676f73c7278c1e3e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x2567e009bf526620789966265c976a380bae3c03edc85793be4cb6dd0035c222ec0a5eda2f84980ffe65e137a676dc88b2cbef8ef0c0c0e18c785c8f6c12bd23	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xe0822b8d8f49eabf62a77b0626e9b95e4a279fad21e8f1bdeb3f6c8502a8d90d14c580e8126c5481f1d7db9391d7a8ce05fcdca58805d6b1f9fac43275eacb07	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7d43878c3d282dab4ef386c27996408ff5bb4d4abff878979ea308d929926502f57bde0d87bbaaa2990b58be6b433d70e919adbab258d2c790ec50a74911fbcb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x298f210b006bcb16d20ec14105b8cc5cb7c4847331d16a16cad5eeec197691f426e85fef91d26ccbcc583d37e655afaa48f2591b840fb306c0291145b7fee30f	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1566476592000000	1567081392000000	1629548592000000	1661084592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfd0a0d18e3c29e519b1a11fb67c767db2e89446f03d390c87b52a1cb9f4e646aaa26fc5e69ea4242009a5f10be25af8f13bdc1bd6470e701aeefbbf4cf1ef78e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567081092000000	1567685892000000	1630153092000000	1661689092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0d5a0b45a61087d8888bf71471568d75d355ae783317bcb1c15a4d16ec7d755e74ba4a5f6b5865e7977b234136f2aacf56ba7db094c026fca2894fd80441ba47	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1567685592000000	1568290392000000	1630757592000000	1662293592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xed4a1a615287375ca9920298edbd96464eb03df9e3d332fc3ea45982ddc7f9a70ea33e3b10ece85dc4a8ad4acd0174afe0fe6ab6724c2542ea36f55380586ebe	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568290092000000	1568894892000000	1631362092000000	1662898092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9f6b6b20e56802e3c2a0164d452a39ef9385839c29f55f2696697663d95eb2dbcf08c124a2de147ae40e2a2cd93f6b8213210fdc01953f93033acef0245da567	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1568894592000000	1569499392000000	1631966592000000	1663502592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf337a13c1e291ab7a542ba1511f03ce5d5699c8f8d811f242be93735844c8232be7f38484f7dfe39eb4519a28361559f2db4ff94d54ff6e2b8567263ad83a110	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1569499092000000	1570103892000000	1632571092000000	1664107092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xedcbb939eb28bed8f259b472d5ed0202371b77fc56b1ba99e981031c29a80fe7c9c9701011ecfdc92ba5cb86f6eb1f3be5c5d313e2112913e9c42aaab53512e4	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570103592000000	1570708392000000	1633175592000000	1664711592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xc89ab8ab1e66ec692139372a849db8f0db7f19c98f2cb27b2000575564142794cb1c4ba0d35295904ad6b775f1ac07bed1e834a03f8fc47a7d7a480b9c6c49f2	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1570708092000000	1571312892000000	1633780092000000	1665316092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x95c05d6d47207a002bb63221d1ed98b1adc8b96a2c7cfda091d74e05cc42672d840794032412dd7027edb901df0aca362c53d92124c1f4fe312588eb29f36912	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571312592000000	1571917392000000	1634384592000000	1665920592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x890de8821d5355874ad290008de873eaf4539c3bbbc6bb3fbb92856c55150ccbf4f3b6223e719135e463df5bfa01095f65f484d46643992136d7d4fa8227607e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1571917092000000	1572521892000000	1634989092000000	1666525092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x039025ba4c1cab5360baaecaa627a15f25dd94f0268b5a0612524c8fa484ca92da0ff2b227021003557aebc36eca87e9240f029ed1316bb82a18f706e0153592	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1572521592000000	1573126392000000	1635593592000000	1667129592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x04b4688c24588a2b1697749e3d422baca9e564e578fb571e1256a06617bccc70a75a7fa00602a18d324ba0601862a5bbab1e447788668a31df7ac0b0cd124dcb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573126092000000	1573730892000000	1636198092000000	1667734092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x22c6f98994e795fd28760659d5440697d38fd19f7f502ac52fd1d1ed88a577de7607b9784a926058fc014fa0b268495822f64d49fb4883e65c2da0dcd742eb16	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1573730592000000	1574335392000000	1636802592000000	1668338592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x611a6f294cf4aedba029628917641757ae66c0360c7d02f43f339da1af4622c6b57ead77f7b7446effb4b37493d85704e9edd2a5bfe65d7381090e51db056dc3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574335092000000	1574939892000000	1637407092000000	1668943092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x3164b21d6f4a82afe14166e19f8bfc543402dfafd0d0a1b64f79f30c6894b50f935ab89f831ab8d8e21dedf79017c5db16d32d0f7af905d64ccac279b6539fe9	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1574939592000000	1575544392000000	1638011592000000	1669547592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8cc4049dfa1375b0902670af63011919a19cf6b5b47937c6346a328f934fabb9bfcf6413c3864774275e7562a49c0a9eba6d4816b28ac616b754be47e72e8142	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1575544092000000	1576148892000000	1638616092000000	1670152092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xcdbb110649222147124b40ad42fdceae9aff914d7fafbc317aa37f26c82228e1ec2c6eeb30bc94c257a88e1241af074ea706e4f7071bc483a79fa73b9a8671bb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576148592000000	1576753392000000	1639220592000000	1670756592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x2d57db65a48567dbe2e1c2d7ae0eafdf85d7b2033e9ad95a62dd045bdf9e0a68aa9c3859676a8751881eb13fdd9a3c81e1389a0d56ab632310106f78020ab973	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1576753092000000	1577357892000000	1639825092000000	1671361092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb445d264a26d0afd9abfe29c86610540346c5dce9b492192c3363bee3b107b7f8f1f3c82a17ae2697835df1a0cb5f895b7102d358e5aa9948ef4249b769fb686	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577357592000000	1577962392000000	1640429592000000	1671965592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xab25303060a5ffa7b9eacecca6299f0146e31eac085d95a9acbbb6f288a025a08d3c3a47a8dcc0678127c03b89df5af5246a731017ecff469d54f75a2dc79671	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1577962092000000	1578566892000000	1641034092000000	1672570092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8e7815b64230e7c43509acbbf9464aaea44b8305e2cd530068adae6f12c74a74fb26c58dfada7bdd23594c16606e4607b31df990f29aa4e7ccdaa8b83678708e	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1578566592000000	1579171392000000	1641638592000000	1673174592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xf599eb196d75777fb0dbe6b86095817a9284d4569c6fc0cb40badc71ed49b7a59642a3848c61878aba15be02cb1954112d5891dcd0efeddcaa72a55060cf6891	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579171092000000	1579775892000000	1642243092000000	1673779092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x3c3ec10287bfcef54fcb56e3814467520240de09d37025b6e6bfc7b64421d75de912982e21ab5a3ce4ae189c1fbb707a6fe658d4a3e6abfb53958ef3289d5719	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1579775592000000	1580380392000000	1642847592000000	1674383592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8a11e87e8b22feb18a6d4879eea038cee29670e62cc698257d53f152ba134d2b0d00c55948134cfdc45095b70e77f3cb859ef763d0d2f7f988cdef2fb7abe949	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580380092000000	1580984892000000	1643452092000000	1674988092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x14a0328273d359281c37991db723d2067eb1b313828ddde9a459f14d52dfa90166b11fb760a2be2322300962a71edad4832e3bad7e6ed5a0877be98cc2c4e2dc	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1580984592000000	1581589392000000	1644056592000000	1675592592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xe8e5884b7e41e7ca0a8861d7acf1eedd00f7b00a649ec1025c56055462a6925ef2b62e7912fabb39882609ce5f918ebd3498b74a38fdecc7731e918c3f558bcb	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1581589092000000	1582193892000000	1644661092000000	1676197092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x0f6227ebbd1a5955a055a193e36113846925946d97e265d12fbabf7c3c1ab983c666f33f58f0bdc38a6c9c6ede175a9d667d2bf9437950835507f4f9b57bb589	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582193592000000	1582798392000000	1645265592000000	1676801592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x5d8b30e5ba5e46a79f0d3bad05e7342e2652e456700ebd5b19d7146d8913beef1e7cdce47b84d984153fe9e2ba7c5b249499236168e88e527a9e235e875d4da3	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1582798092000000	1583402892000000	1645870092000000	1677406092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x43a657394b6d37fee8dac699cb8318e7bcc2de172e8d79c8f8535926a6ffe368c65d668307f5f5885b01d58d5589bdbc9902c043b9c2271b16297ca78480ee84	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1583402592000000	1584007392000000	1646474592000000	1678010592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x02a88d323f6c7eafeb450daeb6b7c87200d8f2e12d87404494af7534ebcce4ea9084d46424310ee5d8a8422eff9e36949df839561a5fc9842d98c5eca315e3fe	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584007092000000	1584611892000000	1647079092000000	1678615092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x88c1cac663abbe351f43999d8399c0c21a5b40e64e88f46cd86845dc9aaec3136bbcb74fe0dd94aee10c2a37f86774e39cc8b3d51a3ae8e96df2be3a29522957	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1584611592000000	1585216392000000	1647683592000000	1679219592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xb21114e7c63b1f1d8836f631276fee2babfe53f17a329c603f60f99d0b356b1ed05f5ef52a0ea6a73ea981b15c0d29bb9b5253751a1ebb59bd8f66e8c0235272	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585216092000000	1585820892000000	1648288092000000	1679824092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x08b36fd9befc513f2cb80fcfc6d1383cd23f2db39dc43d4c803e1421d66f18aaba5b75e1d0daaf9970e11fa93cee17d948a8c3b6095b605f12950bcf4666d827	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	1585820592000000	1586425392000000	1648892592000000	1680428592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
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
\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	http://localhost:8081/
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
\\x21f51be1b55f9ffb04681052b588e70a1f3039e7c6419c6a4650fccb64ebe9bad213a27fb3f7e14d44bb1d1999be4dc8a99fd5e7fedc8d1578acb5d03f1febbd	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432334446444146303837304442423041354532413330453638423337324246424530314241333938454233444642343643303333324141353533413631434231394434383532383334313234314338383938393933444331413332344534313244333941373342454444413742423235334242303030333437413630413637344641453932334438363535354142303438353035353239464534343243363138463239433143324346464545444138344139444233373446324531304334313544453036374535353536463841413543323738353441354242303144363137324146323145343041363544373332324241424431413433383037303132303923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf026e8c1cc8280ce3f1c7c4954ad0d6a411084d7e718d549e70118285fd24d5e518f5dd45a0dc2c57ddc3d87b3d68965701fd3e05773d4f3c75e7569b6a51505	1567685592000000	1568290392000000	1630757592000000	1662293592000000	8	0	0	0	0	0	0	0	0	0
\\xa19dc1d781c0080dc36f0039c58bd5935110775ff84c876ba9427633ee31de02626a85dcd1fdffcf67b21947060deff0d6740722136159b68a4cdf5eec3b194a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304542323739424237444335323042333237443645413335433837434342393733334443434546443036393542444442304137453633383538363746413746333244434234444546414637443044424639323546394631393644343843353339433331313241453845384332423834333946383931434634433744433233373534324136383837353946414135433343414441304433414238424332413645373645443537373638413132323942324638334330464544343636413230304538364431414638383646394542463437313431413142393339413730433636334137364246323639323330394543393631383846413034393839453443394136353323290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf8b601f278d12a194de662397d2b36633131b8fb009f47002daf3ab123bf0bdc8d53e9cda8db8b299e4c0e38a6760e1a59c26de9aafc1e7d1579247f5f8d3200	1567081092000000	1567685892000000	1630153092000000	1661689092000000	8	0	0	0	0	0	0	0	0	0
\\x49b35e46f79ffa65c6c741a051928ae148ac5370453aa365fd23288d64445b25fdcf67623e9675fc716506cbbbbe2d26a736c81a0123b12dbffc5671bcd370a8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304131453444333435454438394536323532454237414435363141434633454139303243414132333138383133443836354537363345393346453345383838373233353236353539394231363339414434414646383338364132323543434132323843374232303332343130433133383645364136434137334231453146423235443541443741384242423146343937364433424536304238323844333031304344433133444646303143443132413036323941323237454641383542323444453030454236423235363342384437363738383939333646374430314335364430394443413044454537363435433631444530334430464634443635334332433123290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x363cbc465dbfb9ed76e82b79c619109357337856cafea5001d61e159eda69634003d27e2d03dc9b4f0f9c3088439c04090c88071b177a4ff2d8cdbb72bdf7701	1568894592000000	1569499392000000	1631966592000000	1663502592000000	8	0	0	0	0	0	0	0	0	0
\\xc24416461566d94cd49df05cc2d9736c43707f8c0c94e2483e777092963726e5c91454b1100181e9408272a2ba57c8f161d095cfc82ade12326e353dc2ebc634	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304242333933373730463633364539344546304431434541314638313633343832424646423934373633414338314236383842444232323335394637344532394445363532454445394343354141413939433737313941363845424342443232314233453232464145344237433134364139434532383245314231344341344539393836414631344243454646374139304443413532354232454133333243363743383337414332423537423436334443373432374644433141303134413934424241434238303445413141333937384235313541324633394341433033424543454335384533323841454332393933344443354236463037434530393430333723290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x5dd8d5868b272ea256c775b15cdd6cf064d304902ee91b1d6341b75f903d856606c869f8cad812ae366cfcfeb089fd4a5903f989c955f995c21a0fbd252e3307	1566476592000000	1567081392000000	1629548592000000	1661084592000000	8	0	0	0	0	0	0	0	0	0
\\xc04409ba4db16856ec1a6634ec79120eb89e26c765e66abfaa15a25b4712903047dbd6ffe62e84077adab51a317e593aa94ff0f320e796930b3be604e7219a7a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304335314541373444353145353230373330323836423637303646384133424336433033414136374334464136344439313030383230323243413236373039393443433734463033304341343136364242314642354631383641423646303737364246393537323131434531393242324337313341444438353531443335364145334141333141303234314533444446314532313636454134464243423045353344393546324542463346394346423433334531303936373431304546364437384442414338393435424236414332303746324138383238423638383132453045323332353436443639423438333146433446303131313442443434314337423523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf99f2ae3bd3250abce7f4ee4ad47cbca6fd58c1a2639482356f0f919385d351c7e2ba67b8360836b5726e28ae84cd93543bb6a921e09e6d0c860df2bc0759509	1568290092000000	1568894892000000	1631362092000000	1662898092000000	8	0	0	0	0	0	0	0	0	0
\\x80fc4e14191e19800b0eb200da9af0c6a87703638a4547596b30956278e4fb7a76657cec1ba88a075048d2ab000dfad4ce71ce4d52eca26c9d9be6e27172b66c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304338434137373035413837453033464232343731323344354537363430384543453532444438433236373432444239383845463838383441423244444237463336443042433430373941353930443534303544463031424436433735373541344134363843333238434238304245314130444237444433384242374644383135343145393532363236433831393731453443463333324438384634333245303645324431343341434530384636333546394431453734423238464443423445354536443431413945353946373646423338364638364441423232383344383845373539383245343443453142453745393446383931413734393532374132303723290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x1b9516598181d65ff23ee7c5ec76df38d856fab4061fcbd88cb13aeb1b854eb57024d3c67c58d126b6a0ac71d073b8f7036628a012e8a42bb99b49566e1f610b	1567685592000000	1568290392000000	1630757592000000	1662293592000000	4	0	0	0	0	0	0	0	0	0
\\xae596bb7d18d0d6ec473e9a7eca8874a6337a6593ba96f0bf02b32529e31829585d71174f7ff8e2d8688aaaa73f6a3cfe41b76398b2c19ee457c5d27d402cd4f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304537373433433046373834304145423631433237334338443143303841433130374543443434364641444632423536443341303743424435303335464636454241423744383246363036453846364430423541334635303531423942324344304633423843464642323136434234373743363645413341333941374438314332373234344242304434413644453846324633414145453532424437314443423541353231463945314235313046313432313145303345353545363330313731464235384244313244334236393037413132394239323943383331353730363343363835463536433236383844383639333830333742393630423334373239323923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x437f9b7a481334ded4fbf9a18c289734ff1f1a8fb4639c0ab5b45e1c8ab4bdda7731912c6e24dd959994fc5f06af7a70a21c4001031fab18e72471cdf99b870d	1567081092000000	1567685892000000	1630153092000000	1661689092000000	4	0	0	0	0	0	0	0	0	0
\\xf75aafdf0147ecf21880dfd5843f37f9976ecdcbd0e013ccc38c42d0971cd24cb93f8c2f1416435341b50a75591ecbd746f5200b1d1cff66ba5a6032aa19d955	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304537313436363843433435364537324139393537384331354239394332353234433733413630383741363242353034443630413741344239303943443133463239324131394446414536384346444639443044424331304144383441354243443342363733463433373446353434304130394642444632303137344146444136453134363241343131363443354635334637433239334238324331433446393244383343383746414232353134354241304445463443324445433233364243344342454138373336303341383936313331464143333044454530443745433830333246333036303232363536463545443536343937383446374444463934443923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x59b4fd916bcf086b9a83a270cce9734162997249c9f04740eaeb0c1ed68e8f8a52bb312cac14147ddfcadfed768f3d15856fdd4260cedb8cc1ea4ead18f75908	1568894592000000	1569499392000000	1631966592000000	1663502592000000	4	0	0	0	0	0	0	0	0	0
\\x39d99c4d8936c39a9f0e52fd0528605d89a2d35923de5ff68f73a616e779fd7a6fcec4ae0217f286823b98c874d17edbb5d95126dffb353c883c6d0f130703c4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304536333638434245363942344446413843373844373534413138413138393641363136444543443035333745324243344439373645423938304641343243354433453237333534343939423341463634333145463844444335413930373645343939424246343744334242424639453042373830314530394430423434393733463542383545364537363143323843374543393739443938363935463439383334304346454134414645334133323134464143374330303635313645384342353532464231454436463431394342443339324334313544353934363336424432443438343636303535363736333937463737424439443532333339393333303123290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xd24a02e81e1c0137cdea2026671a8721e0da1684fb1c24b6c6c2a6917d12d78260cecd0aee9fcb2f7dd876278b04292d79d5cb1587c92ddb04cca10e67df840b	1566476592000000	1567081392000000	1629548592000000	1661084592000000	4	0	0	0	0	0	0	0	0	0
\\xb55dff281977db9535bd6830314040e883b7edfd5ee6fab6fae9832a4b5eb76ec21eb6134b8b6582527ef085611166d13f7ca1aba0462562bb7a2e6a50cda23b	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304138353131433946314530374431354131313542353137303037433842413743364133394137443245354639424631323145463046393836433937313332383630304639393341303245303641444539363936413635443936364542333543464542383743323345363036304346364431334339323736464538343131393936303035463645423334393145443143303144333131344331414337363444303539333741324434323342363543463846344137383735453635343143423339353232383736413341444146313645414339383535413743394333323632433737393537304533323437424645304638363437463435344534433136433844454423290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x9ce661d3b5b3f16fb9a21d063c7ced72fdc0e12d51279984cafe524ccd9585415e769cce1f50192fba61a08c0d191baea219a117d3718745ca58045c6ebb4f07	1568290092000000	1568894892000000	1631362092000000	1662898092000000	4	0	0	0	0	0	0	0	0	0
\\x70b7098dbe43211b8698daf2cbe7bac13c48bdedb9039323accb702083167519a329746528e3cc8e49934b4744a48a87148bfd9feb57cc9ce672615171e12f34	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345334233333530443932343846353630314244344645384230433144434645334433383344354541453432313935303437394531313335393137333039303233424242383130344337304546433633393839423831454530383831334245303634313832453444334331353935373241323839373034313132333342344344303539313232463446393532313637303430424343353336464544433546393830323031333642343541333843343231364138373144323843354131334244434530393944433044314337323137373442353343313230344436334435434542324645364436323737384237394637344633383943373631383037464638343323290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x78e3754aa24bef7392ba0103c509f8b69738b04e3962a4f6b021336d449c26b0ccd5be0ab35b1ee560b2dec034e97b2f90ae66e92d55bd99dca817c294274c03	1567685592000000	1568290392000000	1630757592000000	1662293592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x9e097a466662d87dfbb284775b00f184a72620a6da466dc2b6dc0f88dac68e2f42ca71489b8b9073348b057b1206fe465f18a94ede68d93531dc5f9f976ed1cf	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304137353830333638364434343632413545383243453238453632453539424533304335443546313734383141444445463344384137443238354543314135313043383142413334344335373135423741363036423741413730343832393335323235423539393645303633453443463035333336423645453337333036433235373532413237373332383534383636343445313842344137324246393035393043453830424234463839343237354439453646304336424235343942393130433045313735364641374532343239313732463133373544354242343445443034354436314143323942314131423830384533443546374339383239463135393723290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x1e954f1ee6fd89fa654742e1157455f197109e2c77e72a1f20ca5e2413511f9c374ae36231a68ff67f5fc8c423eb84efd03fc3f43fb533ef63f01b92a0733401	1567081092000000	1567685892000000	1630153092000000	1661689092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x77ab0eb55e2722cbb067152804b9eb8bfb43180445456fc7862a0f28cefe417606a3584013212d6f8f8501d15c0d1f72142b2ed8041da5df190a6f8612724da3	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304343303637333034363942313830343842304538413741434130443742373137433537453846303332443231314443363439413935334244303339354436453342313537383739303738444231304538333742443638333538334539383541364630373336374544423944433830433231443636313030313031353243333744444239464442384541433738323944444337323633443430444546463533413731384641363030424339383836303336434530363143443541423141384337323946463241434331343635353533363239334631364339344644323332394636433736324535413242464635344431323837393035413237393433463841423523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xfbf664a74c54812ca05825f0e1f0358d6131b0324db625c062cf2f9b41fbf8add597e03cced1d3b6aa961bece12e1c4daac78c235d660b73047a840165ac1207	1568894592000000	1569499392000000	1631966592000000	1663502592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0a8a2f49cbe24ee7f2e05f30191acaf0c358fd4ec37b5193d10796e98c06bca5c4df6117f47654bc6baaec777aa403e08b20f50baec29aae5b2d3c91518d10c1	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304432424545454443453142313431324532333230443441304545354535354546413938434531303742364646374543313145353341413435343738394533433646394131334336324333384637463641463443333939353346383544313142394238383746304438353630323145374443393134433943373732334146443937343642374443333531334236333143373146363237383136424243464541433632333435453538333934353033393246373441333943463130433536414235394431383439303944394344423942333538333232464238343737464441423746333432453043324143313932393733333837304534363743424437343644354223290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x291dbfe063ae369af34763853bf5ff8ab4db36430f53db376f9e8e2537c345a20246eb6a25cffd1d322daa3e3668a18871b44a28cc40ba1997aaf0842a79e30e	1566476592000000	1567081392000000	1629548592000000	1661084592000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1dfe20815fbfe068c005c38bc8173276fa76bb5d576bc5502cc1f66d622be3bfc72cb2f04939b8d67847154a4d2f6a24d586663840ffc0a23aa55760e10c5ba9	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304335393942373846443234434246414638373341353732343637423142373741384142423544433531353245304538323643433844443731313430453245453539343136393630373444334633463230344334453532343744464543453335353039433544393332413531413430413846464543314544424443334437313930413536373142394343323638374433424544363438453132303845373534314536353838433335344339364143324646434439394539434134383746354341333539333243323532444230393645374633394339463039354344393037384241324246454144323043453631423333414143454535333243374430374436343523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x37ac6f2627fb0bc4a31d0cc82c693f30b7aec2fe802a75c21db3625378f684867439637a59eaee86f5f852b63bfbf20bd9407273ccb66eefb955d6beeb11ef0b	1568290092000000	1568894892000000	1631362092000000	1662898092000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0d5a0b45a61087d8888bf71471568d75d355ae783317bcb1c15a4d16ec7d755e74ba4a5f6b5865e7977b234136f2aacf56ba7db094c026fca2894fd80441ba47	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304531363735464644384341333544463241424331453835383841313041433936333344363646304142373935353430373742394245423043384536334346353735313231313832393742423643343234313345343930333844463546433530324242373233364234353546413541463237364335373033433031353246344138393938333644413241464242363639374537314638323033313342303130433446444546303739463031423836463738324142383333413143323332433544424244323142374336364641453435413735413539434634463345314539444446303142334430393734333545343838453642454430303531413244453231303923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x0c99a9fe35cff3b2bb9619d6174a6c2a50dbed38c9028a8dea9a1bc2676e041b9c01e31beec639aa488b7396b0328fe84db54f61cb7fdfe2e3b5ffc817e8ad01	1567685592000000	1568290392000000	1630757592000000	1662293592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xfd0a0d18e3c29e519b1a11fb67c767db2e89446f03d390c87b52a1cb9f4e646aaa26fc5e69ea4242009a5f10be25af8f13bdc1bd6470e701aeefbbf4cf1ef78e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304530343936463037413942414231314542363135453436384333303746354633343939464441363938313237354142464239324144394443313633413535333341374138383536323235444638433543433731343237413134334537383043303838453941334334434130373735424233343437454644384334313436453130373930353130454143454631443945373843434537463730324643333539303034414341374334433234353543443031384246454234313936423541393037313333423631383935333136453635393537334639334232384645383842444643333141433645313345464339444235304532423535413545304537343932433723290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x37f703e2b80a6d262245ecd20e5c897c36f36a0e0c169581c670d208f5841d50355a621d3da6d8638cfa189f39d6d5a958b24963d8d3a75b0606dbb77b2a0902	1567081092000000	1567685892000000	1630153092000000	1661689092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x9f6b6b20e56802e3c2a0164d452a39ef9385839c29f55f2696697663d95eb2dbcf08c124a2de147ae40e2a2cd93f6b8213210fdc01953f93033acef0245da567	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304143374546323946393232383939423339384432464542343030333631333537434241303434384633393331383444393541344336313744303032303536394235453333394243413138433146303538414530343139414133314633304245383830383141424346314132393831453434324542374244383734343241344545343645443741443731304541334630313444313144423235343030423541313143313942314239363131383037333237434446324130303845414330444331364539303143303441333746324630363541444643344438433435333930433936333743314530414137423536434245414646433742453130374130394242314623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x1cb21181bb0932355a6109e5f31085b020b1cbe89c07e92c8da3838bef3f9ef111aef191d97bcd749194e4568ac4eca3e0dee79a27867039f0c5f03ba1d87505	1568894592000000	1569499392000000	1631966592000000	1663502592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x298f210b006bcb16d20ec14105b8cc5cb7c4847331d16a16cad5eeec197691f426e85fef91d26ccbcc583d37e655afaa48f2591b840fb306c0291145b7fee30f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442463841343239393933314533313239453530454332414445354237413930323533333841423533314541333839314444424543443138313946343636454234313743464346303543454446414338414333363846423830454532434445394337373936453139343037333839453236424537334437413432394542353632423541303931443036334231373143443642333141323635464531453935393643423634434345303346383433453230363435324235363146363346383344464245303730443831353334353536304346333339344435343839414533304642443537423341364331313030414135463945423436304641383733324432433723290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x6b639c8fedebbd3388bf6dde1fb5f9855aa7e284a85c6cf6da9ec3cd7c653a0aab599887a33284c4bd1af9d4c9dce2bb7143a156b29be5e5e05dcaa1ad10be0f	1566476592000000	1567081392000000	1629548592000000	1661084592000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\xed4a1a615287375ca9920298edbd96464eb03df9e3d332fc3ea45982ddc7f9a70ea33e3b10ece85dc4a8ad4acd0174afe0fe6ab6724c2542ea36f55380586ebe	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304331343946393535443735354633364630413042463744424635304345413437463645374634314341354644443444344542364243423332304236424633353946313633444239353831384137373836434436384133413446313545383330323444454331314345383344393538343138333143333046453044393531433646353141414645304141463432423939374634433141413942413246433133453342364536324142373832343939384638333737323631413645373130303746344330433135313642414441463837343841374442333642393938384533383730443830373735393532303337353542454344383344354639363838443142343523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xa2435db28e247a6afa4d22da6cecf899b7cfbb660d5a5f557fbd6e387675d656e7a298b6258efa50521f868570c6e92035c522190635f11cab4ec1545e349e06	1568290092000000	1568894892000000	1631362092000000	1662898092000000	0	1000000	0	0	0	0	0	1000000	0	1000000
\\x8b9a92794eff8c68c5116b4924742c66bb53b7597ac24fb2ac269893d7e2d4f8abb06f614dd8aed0019cde32124abf8904d4b11a9c241784f02b911d314478f0	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333414638413838443430354344314536423138434245333439384630463331383033383637423943433130454134414636443745454541313042424131324235334538463333353146303436343734423734354630423939433044323932424546314641323532383043423832444334443235313836453045354238463934333041343139343941413535323133333031364136423831363634303044313432383044413342303930454136413741344131303637453535393537453932463234323135444246373342304643443846394245354331333737444343314131384230304231333630444233303942333437333631423146453936424539373923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xceee792f2e9867092951f1f4ec3beb9da72d20ef2c14ab27ef2c2dc275916bf75a9a6b24dc8fc6dcd2ab647c11160bd7e45a441e89eed4cf96925721fcb11e09	1567685592000000	1568290392000000	1630757592000000	1662293592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x1281df4fd1e15f64e108b47a41c588d02b1d8232da4b43572e49868344e2b0953a499f7fde7fc8293bc7b5ede207d58fda477ebb7badadb29944ddb4e7037453	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333394545323337314435464331394441444545423843363137333332443546353046313641433233414435324132394539373941343846353441383746414142323839303137313933434234453534423234394433373846304641324236393144373930363544314344363636304132313838344130374234463635443441424332394236374337393436344436323639353434424244393141334445423531464236354641344533434337323246353030354133444546453544314137393138393536464334454433434136343342303644313446353731324238373943313831454439334532363233463030364134463434343931324235414633383323290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xea742b8bba8a197e3490ac7adc35a9bdaf83c72b378a17472a4ec45a9f35067c58e8dfaa6bbd57eb0d304d5f3db8d0d56e203d749d4fdd39225045642ebacb0c	1567081092000000	1567685892000000	1630153092000000	1661689092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xccd6695b525bace565fbb1a527dbb6413dccee290e5e1f7e1f513bd62b06ac0b8e8de2885ce79c184ce2770492b8fd90731cea7a9ccae932aaf6289dfd11a72a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304333454237424233383239463241323245463643384341423946443930413332424234374630304334363835433941373546393437373443444135393931443043453531344444443530333546383745313042433145454336433642374530313934343442363141344239384437364544383546343634354634323342413237324142314137384630383332433644423237353535363638303844414436304135423232363834383439363846373334414336304645443742413836393545434234344136304341463543333932453342364437354643453045354136303736363838444446304337303639444344353933393236454132333741393742324223290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xff54e9234e45ae1eb09419ed0f4bf3ad5bb8e19f4f2d0c882849c56e72b7c4999e2eaa219dc36b102951fe879218f1162317015e0239626011f1ce298f34cf07	1568894592000000	1569499392000000	1631966592000000	1663502592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\xb51be86aeb471046822a73026ca33a6b72044764b6f2dd0a7731dafee925adcad69246d7d6fb4f10ff5d22149507a6981d0d92b916b412d7513c57bcd98e06d7	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304139323745334346373034303635433430383030454244433936454238444337363244303439333439343932423343394634414430383632383244354533454143373946444546443446453839393733433635313443313845383930423331413345353243303138453343413246433630444543434635353234434236454642433342393536394537423846454538434237393446423043323734314336464244393538333830304539434637433035383744314333374446324430444438463039413343364635444546323838414346343043353633353738464630314146314541393442413530443233463244313234323338443833314434323734323123290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x783e668151fff6b397411b2e0ec1a836af9bed6a0fb5763ebf4b559a7f7df350c049c25635085d62f99e6f722c87e0616b8776cba4a0645700007a6d21837009	1566476592000000	1567081392000000	1629548592000000	1661084592000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x0db2780af722d30c707799be0492b2a3b85fd98441a4bc9e4fadc4a048cf053637304199a78fb87555ccc901a5ea4640351a98fdd26deea087e69916716f2655	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304231423145353239393233314445373531373243444535333241343441304632433244313337413731334331333133424330453445364137393432414444393142463535434536373945343937313331424233323234453831454536424144323444333931383537343232323831343331314638434232354442343838353841373133353630454136413837413031313846413838353044323944303844364635463541323243333030464532303146313430433042324542354533373541353632373032383830303135444645393742463738443839443132463831434344324632373543414133344635314445323534323830314539463641434134334623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x36e43c3f289237f286b5dbae19b8982ed88ac04fdabc07aff82b429d04e3e67e78f9efcc2f0c6625a0d7e83804482c9b4d75066ea322d28e0394b8283e87830c	1568290092000000	1568894892000000	1631362092000000	1662898092000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\\x8e01f94f01df22ee86e150b7a1fe6caf76011f9ba9b8f879df6d6fbdd32ae25f3da8d7557de1c385f499182651e01436d6befa739aa032e9bd5f13531874f239	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304332303537464239414344433431453642423933314535423436333633434239394536364246304635383342333944393444373139334445324332383245414534414232443737464332383741383041353846334133454446463946393442383538363539323943353535463935464234434544334246333133394436303238303932423436414637453435314446394241364639383946463130413042333846373138333639453633323346333032394433423730334534324241424143464431363141313943354145384234423736413636434335313846334546354243464231454336364646354142373036434636413939354643344639323741434623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x60aa08a5590e00b1c8786ae770e1f3c3a80a4a4d58778e59d4df3e9b6ebc8c42ead2fd56fb859bc9107ab7b23dcaf0cc72a76c0f841cc96b67cfcb3bad70940b	1567685592000000	1568290392000000	1630757592000000	1662293592000000	2	0	0	0	0	0	0	0	0	0
\\x20c97275e330eebcb898f5887e504ddb1aeaf6f86d4e4663c6bfcdef2896c7c1e2838ca68c06bb457b3d8d6c21129c54877ce4004068aa81e8b44adec81a9287	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304234393346323334453941463932383636353637304232393641463939334146323144303330433543333236364234364433324642463433333932464341414232393332393230353435384442433131424543393442314230454133343239413236444536304130414332363244363641354541444331333144413946373635374444353946393543463244444344383733333843393332414442413932423235373346463532443439343936383632343232393035343939453142383539323943393332344134454332333331423543343742413944453834413737334136423945353038463431413734463431423733464644444232444431303846443123290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xb0fb85856bee7cbd1f541727ccdce0f2790e4fa0bfc6277a7a47421c0beac4430bf60b30d22d6986cb51a973fa20b86d421b52f7c0cff62132481c6653179a09	1567081092000000	1567685892000000	1630153092000000	1661689092000000	2	0	0	0	0	0	0	0	0	0
\\x99fb2bc6183da5f6e89846056f2a581dc317cc6d9a6cbd07cac5ff73f3d67f30c89e1affb8929ea43c54e7712997ad8714d9efe24d2a9d9ecaac13a966c961f8	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304345343545434537323944304443324436453431414443353543314432324530423230464435444346313341333345324541463433334238383130334434373231354435464234354139463731314433453931353642454234413142444243323642423432353630343736384642424235393944454137323746463430423239343239363632374441353939334330313836313232434545423342344532454539313345374236433930314536464331343634303436433143463830383037323841333941324443363044374630324343373845373744423631413141304143343733313534364633333744383335303634393432363937304544354444433523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x8fecbb3958da19d7c38ae8b9d4978abea56dc673037e89728b1bb338ad19bbdadf62da85524f37fe706b67483963daf64941906a2f281707b49badbb99c89b08	1568894592000000	1569499392000000	1631966592000000	1663502592000000	2	0	0	0	0	0	0	0	0	0
\\x6fd4ecd17fe628bf6eeb987f60d1ad5b503637ada12f271855ca25e95e8a395f2d7b25fa6cf4a5bf725d5e82917b4b81729231100cb72ea16ccd653862bfa0f4	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304137453837354633304143363945424139333642393039433732373436334239463138304133383434333737423039463730324643434341384244343444453733454630344230324338363039433438373431434146464246464138433235443431383542313237424331393232364634393539413136434143314433363930443745433434304531393530463945433031363631463933433630414242323643413331423532374134313437323644424534443030364133463446444244464335413042444330424646383442364335303938333633413745444643424145363844463537313235303246464232323046413930413032373539463346443923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x3213f35b2e5b228f0a8269653344fb9d814f2c222ff4de7605165e8870c9f3007b403302f492ce290b4ce4c7c9317b854e427c38d2a2d973b34b84d88e3d3c0e	1566476592000000	1567081392000000	1629548592000000	1661084592000000	2	0	0	0	0	0	0	0	0	0
\\xea05a8ef82ab0641e6e37c1cf05f6709a512416f8e10f471149a3b04b1bd4348bf226bfcfcf013818fd269b09edf611d1afed9dc61352953afd17ce8ee6ddf4d	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304245464438334132393836303131304641423930383537333546303231314132423236443837304234423643313245353131333241333542363841383534394133373846453741433836414437453334443833323635384241393433424236314334303643453038343143383942373138413344463444314245374135393743454336354531303031334536334241303739323632443539334538343443423843304245413843373945413443333333383734343046383734323843303839464339464139383734394231423244324331313045344639423131343434323431334541463138303041333842373746453134343942453546344534384242434623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x5624dc7c3c59587c28c16cce56131d83dee9a6ff8f6e4a615dbd1567ca19d212788c1e34e4996287af39c3f06dd141b2432557cfad53bc882f27e456ecee1000	1568290092000000	1568894892000000	1631362092000000	1662898092000000	2	0	0	0	0	0	0	0	0	0
\\x70f9c018f09613c8718de8b107768f0986442e87e9a8e29ae365fece22e45b63fb9f0f7e1275e91b3982f8a5dae79a899fb5dfa2c674f94ec3bce55c9c461c95	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304342443943424237444144323843314234414242304333414644433239393934304545343834454144384344364345383138373043454134364544424232384533414432353033324642354245463136323737373841383643323242313733324533463131303537423638323030433945313633393143373645383446423232383243413036313539424443303034443639374630443030373132463835463041453333424333313435454136423036393246364633463938334142463538303632433641343037313637323033394543413042334630393246434133333735373236464145344138343933384131433041323544454633343632383237314423290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xe33e89e40524fe9e2a4aaf2b93787038bb7c683ab38157477ad9e5fd9f6541cb972e7001f77282590aa84b615a535d5a633f0da88c1b127a7df6ef55d1169908	1567685592000000	1568290392000000	1630757592000000	1662293592000000	1	0	0	0	0	0	0	0	0	0
\\x6338310a8fdd078ab9a7b690afab1c800e08f4fdff2ce642599fa7dc384d1477cfb7f2df86ae3f5c59739715c6131ddb3ba72371c1e3bd95ccc2e5ff5b5d928c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304243433046344433354430303631463534364533343339304132304131303636453635373444454435314134303341314234414335443036363636453233304238363439424543464532344546303842454141394444454339363637434531393536313030353034423845353332303139463038374330314130454546364141384146304233323933324643354433353136463937394644433734394531443138383730313642414235413846333946414130363344393034314246393938453933433845334336334241364130393344313337444436344438333830354545343631463644414332363141334343383935343038323535354331383446383523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x382e0f58a3497625e783b705dd00477c0a4926dd8e94c1765285c919f541712a58fe52bf441cc6b5207d8bd42b86848a55f5605d592726984508b15fb74ca507	1567081092000000	1567685892000000	1630153092000000	1661689092000000	1	0	0	0	0	0	0	0	0	0
\\xd3216a14065935f4674cc7581be72b6d758755d76b08ef6c74dc953553fd3b6eabf0da413148121c04dbdc02cb5808d69504b11665bbbf40bb7ba4da982d180a	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304236393244344634453038323339394537393144444432334139423541314543363932433045364543303234423534313737373436333330323746323232433931303343444533344634443834394634463933344146443845433445444235393245393037373543323046343445463933423230353246343138334542443441334542423533363831393835413641383644363632353146353930304334343431423338453234333030463943434534364135343131364230384445444642303635414339433044303635313641313044363031334436413630374535314631424632374342463734443544423745383339373038374434373239303533414623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x08daf7d1d52c8f3376f09fec79116ecc299949a97de138d28d8a0f40d1efac2df3e94a4a07f654abe7486abe1ace43b36cd90d549fe4b274e053aba181a47406	1568894592000000	1569499392000000	1631966592000000	1663502592000000	1	0	0	0	0	0	0	0	0	0
\\x9756b1d8e49f72391e701a9df899f4813cb5db3d5794907b609f32669428153a7e047c033304c904314d5483ae39596b3b6aeb5371a3ee348bc897bf8a74118c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304442303141463643453031464535323530313044433236384241453442373446453337323746393335463935394534394239453035433836334342383642433134433345314133313534383934344131333141423242423845393432303836423735353133343743453945444533303833423637423336333532354542314445354443343935313836364330433046463539373633344232353134374435383631454238343930334446323535393335464633423839444443303134443337463332313242384332324445363634424131463739413637394233353044463531393635314541333038423839304446303034423636414339304533434131323923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x887a88bd11f4d1e9b729ff6f85dace20948dcd59fb3bb1e195f359b497fa7e4fbc75c46b2341b71ba7504676aeb5d671a9340de149682d96d2c18d6d206b9f06	1566476592000000	1567081392000000	1629548592000000	1661084592000000	1	0	0	0	0	0	0	0	0	0
\\x8b32325989b33a4abebbf39c3adadfe01afc270bbb756f0fc470023929798ff5f19b861fd44f2fff17d9a1a9925ffef695be5aa5cedfaf216600d6a37d71d9dd	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304341313837333536373036413346304242324537333833344345453042453746313031303237303932443532374545393931444537413442364146374633453442383639343346423935343438324242433844323133454537313132413531394532394341353842343635444143344443414646453932304342383336434638444633313339373631463746374338354642304343433545423134394139363434433530363933343035383331353435424244433338344439364336344136354142453741334344383536364241414143414334414235383844454530414537413133424241384245313144444637323043383932423432463837363139334623290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x0a2135dba1781d05ea9f0e38046f029ba380abafdbced7ea8052d18d842abcc1368ef4482086c5fee4359597b38330e3feeeff0502c2cf29166d06ecc432a40d	1568290092000000	1568894892000000	1631362092000000	1662898092000000	1	0	0	0	0	0	0	0	0	0
\\xd71ad826b05b528b37b3313af07c3a3f33bf418760173553627826c61c0e3da80681d4b798d1b78e87a4b99594498f39230cb104c60075936a984e8ab06c8f1c	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304237333846373034394134324142434331363130353934433136393946424643304531333939314146443530343946323230373541323133464238393231414633423937303445313831423446463531434435353730313737353639393646383035413938333635313730314242444137314542423633443144423642414242343134413136463743433931383730423734453238353542413930443146343434393842433645324639413336363244433246303737413141334545363246394530424131373837363831333235383242434132353744463042354232413744423435333942393644333943304537464636463444413044374436374531304223290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x7d5d46dec834ca8bc1d52b8b76438b6bdd770661ae4a37b3836c5ffd25dff65472e4f110b30647c5b8c5693dec3e17c293dbb1572d610c7883946901df34a008	1567685592000000	1568290392000000	1630757592000000	1662293592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x7c96f89b98f56ad657f8e379423b6d74e203343e49d622f8226f187aaddfd73b9307d935550a6cbfbf9e5aaa42af1e3120288d0f12ea3505a4fd8fc2e17d206f	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304330323234433241414430334337453341464530424335413839373438434536443436464335363246423944363541444339343138333743304541343642324544464244333032373334454530433444314131453342334544353030363642304435374233343933314430333030353435364137464141373841313239453243373732313136353244433545414132324343304233304438364331394331463137363837344637313134444437414646413631304432414131423245373941464643453044464632443430363446423446374439303139353346353636454141444632443043394233453243323742383838363336313831453139413946434423290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xdd5e1aac8992a9f770101efc6f00474f02e7834937215c817709f6cff8f5adec969c3a30875089b4d293f8e9d557cb7ee46acad1d15e448ed626241783102e0c	1567081092000000	1567685892000000	1630153092000000	1661689092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x128f6ee283c1ff79b7bb8771fba7b8623a947f2acea62069b7cfd2faf5f0a8864bf87a0cda987c60faf0e16c0172ed04d53039a2127ffdb1b2c6cc6851635067	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304446333032374533453442393934313032374437394332353539463336423839423832413534444143433332394336444136383835463337354234364330354643433746303445463239433036353144394645454644433332393842333336323344363143424543313330333842394246313130323432344237314546334131433230424345313037434330463732393739324645323637433843364435363846374634414631434432303033413638434335314533433441313639443446303439334241303645423246383543383742454546373936433743463236343336303539323546333242333435363134314446463331324330394637373136433523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\x3ff07b0e85a43581bb28d557010984c244aa5b88608146ab595be9d2041ca34d1705045806ca4ddbb7fa2a545e495cd296a0e29df058195ca09650968d5eaf07	1568894592000000	1569499392000000	1631966592000000	1663502592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\x75fb53b4b933f40469ab33e5d4b8c67be60035935a12e76ecc28ff9ad0fead0d97ad7bf8b4a22e7263285492135331b6cba6d80db6fd6968bb831a10eff5d44e	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304145363439344133453632384339384545323837464438344435344333454146414343343034373434424134394435364539304532394543313834313043453539353732413539394533344336423930354541443046463734364333343144443837353643363536423830303541353733433538393430313732343830443146384130313144433438444244383836453245394233434134433845373445373944463635353633393246323745424239444145323045373236324531444641463435443435334241373041313339334131354141423945454535443046443442393236323731333934453238414545393130393733464636363345323142463523290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf26e54938910f903107ee2897401cbf9d601cb6b910321043e20dc2e11b6174fdd54c3fe065e831adc3e368fb3a391024bf176b4a385af543f2d61a296bc1909	1566476592000000	1567081392000000	1629548592000000	1661084592000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\\xc8acf1a2a804a8b66969e9c22c7aa4e10ea01cd394e3a2c56e065a7d2ff4178a4863cefeb553fa21a7a5de8421fda32ecfb0fa7f7c42c43be19d61135092d5c2	\\x287075626c69632d6b6579200a2028727361200a2020286e202330304430413738303444384532353144393231393731444244353041413330353731333634363646464234303139393935424241394532363431463231424430394142353736443545424136373531413445384137424232353443363935443835383645303038353339413344373544413441353046303541313546304538413032393641434342304346444245344443354244464544334145314636333435423645394242334535414144453243393344314246464232363636303545394639364432324342383430453933424336414233434438463641354234343745394342444239313244463239433332423044423731414636313933383238424436323923290a20202865202330313030303123290a2020290a20290a	\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xc6548f1e1f709c3cb33e1a899161f6257c353accc10bfb9ffd684737fc1a1756ebc7490e670b061520fe2640ccc74e65e3064ec3690893c5bcb2c37a66dd2e0f	1568290092000000	1568894892000000	1631362092000000	1662898092000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
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
1	\\x13dc19fb121998d4a21edc4be0e8e507509cad8b4a82ec63501ecafd810d409d	2	0	1566476617000000	0	1568291017000000	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\xf2e1673ad8f54b18ef21840d4b7842214b4cdf6b41ec4f70101fdaa3b76a4e4ca4cb120fe0dcab09600b473189960a3182e5322db2f77cf7555629b5ce012729	\\x1a91f4d2459106ac25ba26f4f388d64e1f7e2ff09cff214d4b05ccdb0ec29692032d5048cb1dd4dfdaa129192eb7d352702225e584cfd7103f5b4a181f94ffa7	\\xb4e2f1c8ed518e1b1dc9f81907342b003e1f0d3323a84b2a55eccf55221aad5894e9f45c5595b4eb872ba85dfe0621db42a0181b56166a7f0b3534def5131a0f	{"url":"payto://x-taler-bank/bank.test.taler.net:8082/3","salt":"HENN6YTS0J8522EEXJR5EXQHAVK2P1SQ34ZRNEQA8QMR7PFS9MX9NTBQZ8KG0Q92KKFE9XR8DKX9DSCNVY49DQYA7C949Z64JRTTJX0"}	f	f
2	\\x4fb1ccc179e2acddf922efd52fbbebdeee24b141fc7cfc1b5ef7e83bc4ba523d	3	0	1566476617000000	0	1568291017000000	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\xf2e1673ad8f54b18ef21840d4b7842214b4cdf6b41ec4f70101fdaa3b76a4e4ca4cb120fe0dcab09600b473189960a3182e5322db2f77cf7555629b5ce012729	\\x1a91f4d2459106ac25ba26f4f388d64e1f7e2ff09cff214d4b05ccdb0ec29692032d5048cb1dd4dfdaa129192eb7d352702225e584cfd7103f5b4a181f94ffa7	\\xc9f9a3a095a0324f2e7bdbea2f07dbf728c91f577426a7ebfee52b61310f4d5b8882662a3c1f32f135f18c7a17e1113c90c663f1f163d4033fb576ead198e302	{"url":"payto://x-taler-bank/bank.test.taler.net:8082/3","salt":"HENN6YTS0J8522EEXJR5EXQHAVK2P1SQ34ZRNEQA8QMR7PFS9MX9NTBQZ8KG0Q92KKFE9XR8DKX9DSCNVY49DQYA7C949Z64JRTTJX0"}	f	f
\.


--
-- Data for Name: exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.exchange_wire_fees (exchange_pub, h_wire_method, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, start_date, end_date, exchange_sig) FROM stdin;
\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1546297200000000	1577833200000000	\\x19c1d9d903b0a455438cf58d40b0eebb7364b24e588900305a6180407e811e9d94ab801b25263a5da8f6c96ca0a3a17942d89fc2262205ba79b6355771d3af0c
\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1577833200000000	1609455600000000	\\xe8cdaa7612c6ac6deeba68d321171a35922f3201bd6d67cda3e49ea0bb11c5b72eca13f4059976d6b8bfad0a5ab75455e4b2c39c6e827b232327d5c6bf1d7206
\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1609455600000000	1640991600000000	\\xeadc0029287e7c83ed40f0ce0770c00c5463f34686a822d646a27b6c4a3e0c6cb8ccde193925f26c323315d2b1490fc219eb57e0b55f57b6be2d369ebb38b707
\\x74ddcb21f23daaa57869f92ee290a5777c4a2522740cf78f72cd776a104023cc	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	0	1000000	0	1000000	1640991600000000	1672527600000000	\\x83992e1f5771083a211f8880475bbbcab3595c3eaca87bcd52910ebb53ef561a8481d4f5e02b2cfd7bb334a9758c598db86322da20bde02347db7452b20ee300
\.


--
-- Data for Name: known_coins; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.known_coins (coin_pub, denom_pub_hash, denom_sig) FROM stdin;
\\x13dc19fb121998d4a21edc4be0e8e507509cad8b4a82ec63501ecafd810d409d	\\x6fd4ecd17fe628bf6eeb987f60d1ad5b503637ada12f271855ca25e95e8a395f2d7b25fa6cf4a5bf725d5e82917b4b81729231100cb72ea16ccd653862bfa0f4	\\x287369672d76616c200a2028727361200a2020287320233436414243443745343134393945463746353545313939313238453831343332334632373942343932323933423437363730413533413032383035414637444437354443314645334638413330363938323644354439463134393337433838444231463430433735464233394438443946384132464234384243354433343138323643433131373741384533304438424345333933454233464138314641353242383935304336314537333744424545344141394345393539464137463131433045464139363834383534413844453836444641304435353644463433443845323443383131453532463844313638353941373041373446443031363844364523290a2020290a20290a
\\x4fb1ccc179e2acddf922efd52fbbebdeee24b141fc7cfc1b5ef7e83bc4ba523d	\\xc24416461566d94cd49df05cc2d9736c43707f8c0c94e2483e777092963726e5c91454b1100181e9408272a2ba57c8f161d095cfc82ade12326e353dc2ebc634	\\x287369672d76616c200a2028727361200a2020287320233841384143424536333131443532433733433431384142464242353432314239303043313746444331463131333632424545434338413637333436383631414643423831344433463143324137373833393232313034424645353242443033354543383542414545323044393232433044364139453832374241463735303542414441343532443944383032423938323930333539373644393737384437394334314137444142303342414144463841383332413141393133353246313534323331374441444338453332463846463541393946373741343235363035373136423244433539303942333244323932433737444230304238343737303230353723290a2020290a20290a
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
2019.234.14.23.37-01W7X1WS7JZW6	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233342e31342e32332e33372d3031573758315753374a5a5736222c2274696d657374616d70223a222f446174652831353636343736363137292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636353633303137292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454b45575038464a37504e41415933395a34514535343535455859344d393932454736464633564a534e56504d34323034463630227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a223341385a394d4a354a3433415239445434565446373236503952465157425a474b4b5a4a324b414230513644503350324a5439303642414739333548564e365a5641474a4a363945505a394e3457313234514a52394b595132305a4e504a4752335941465a3952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22593146423339565859334648434745394352364d47354d414e36334446574d4b45525830393854505253344553434a4b41563730222c226e6f6e6365223a224146465a464b5635474145444d324b5351393850303043435845534d303635374d5057303750453633504e4b4444484531424230227d	\\xf2e1673ad8f54b18ef21840d4b7842214b4cdf6b41ec4f70101fdaa3b76a4e4ca4cb120fe0dcab09600b473189960a3182e5322db2f77cf7555629b5ce012729	1566476617000000	1	t	
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_deposits (h_contract_terms, merchant_pub, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_pub, exchange_proof) FROM stdin;
\\xf2e1673ad8f54b18ef21840d4b7842214b4cdf6b41ec4f70101fdaa3b76a4e4ca4cb120fe0dcab09600b473189960a3182e5322db2f77cf7555629b5ce012729	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\x13dc19fb121998d4a21edc4be0e8e507509cad8b4a82ec63501ecafd810d409d	http://localhost:8081/	2	0	0	0	0	0	0	1000000	\\x1cb7f7239821b8e237b68d4226d6112869cfa0b9cf33ba03ebe817a843a8a363	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a22394e394d525938574b4739474d5957444551533832525a384359433831364b51414443563154515333395147305636355147345a4e35503141484732485642545451435a4a47303751354a34524242393430465346473139413545435034335935573833343147222c22707562223a22334a565a453857523436574534445850484e3132444e474835314d575a383553535753564d305a4258304254474758384d444847227d
\\xf2e1673ad8f54b18ef21840d4b7842214b4cdf6b41ec4f70101fdaa3b76a4e4ca4cb120fe0dcab09600b473189960a3182e5322db2f77cf7555629b5ce012729	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\x4fb1ccc179e2acddf922efd52fbbebdeee24b141fc7cfc1b5ef7e83bc4ba523d	http://localhost:8081/	3	0	0	0	0	0	0	1000000	\\x1cb7f7239821b8e237b68d4226d6112869cfa0b9cf33ba03ebe817a843a8a363	\\x7b22737461747573223a224445504f5349545f4f4b222c22736967223a2243364539314e3841563151343348593136575039474a5a4e41514a5947484e3659373344355445414a4d4a5a314e35325a5954524a3056524b325a574748355233345a5342505330535131514e314a464844345a56434a5335454a584152475137385a4a303247222c22707562223a22334a565a453857523436574534445850484e3132444e474835314d575a383553535753564d305a4258304254474758384d444847227d
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.merchant_orders (order_id, merchant_pub, contract_terms, "timestamp") FROM stdin;
2019.234.14.23.37-01W7X1WS7JZW6	\\xf05eb1a77df0df1641c9660d48168aa986d7f293763a04a356c648ecb25356ce	\\x7b22616d6f756e74223a22544553544b55444f533a35222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2268747470733a2f2f6578616d706c652e636f6d2f222c226f726465725f6964223a22323031392e3233342e31342e32332e33372d3031573758315753374a5a5736222c2274696d657374616d70223a222f446174652831353636343736363137292f222c22726566756e645f646561646c696e65223a222f446174652830292f222c227061795f646561646c696e65223a222f446174652831353636353633303137292f222c226d61785f776972655f666565223a22544553544b55444f533a302e31222c226d61785f666565223a22544553544b55444f533a302e31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c227061795f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f7075626c69632f706179222c2270726f6475637473223a5b5d2c226d65726368616e74223a7b226e616d65223a224d65726368616e7420496e632e222c22696e7374616e6365223a2264656661756c74227d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22454b45575038464a37504e41415933395a34514535343535455859344d393932454736464633564a534e56504d34323034463630227d5d2c2261756469746f7273223a5b5d2c22485f77697265223a223341385a394d4a354a3433415239445434565446373236503952465157425a474b4b5a4a324b414230513644503350324a5439303642414739333548564e365a5641474a4a363945505a394e3457313234514a52394b595132305a4e504a4752335941465a3952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226d65726368616e745f707562223a22593146423339565859334648434745394352364d47354d414e36334446574d4b45525830393854505253344553434a4b41563730227d	1566476617000000
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
\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	payto://x-taler-bank/bank.test.taler.net/396	0	0	1568895815000000	1787228617000000
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
1	\\xe6dacd272de8282c0b32344101c61815e3921c4564cc346a991918b21904cedd	\\x0000000000000352	10	0	payto://x-taler-bank/bank.test.taler.net/395	account-1	1566476420000000
2	\\x66ec99ef569ba5b8262b5451943f743d82db4d46d850f56295229bc941e06d0c	\\x0000000000000350	10	0	payto://x-taler-bank/bank.test.taler.net/394	account-1	1566476135000000
3	\\x5a4622282f4ca44630980efeb12cbb2a8c3c46daa0d676186ccdad1103910954	\\x000000000000034e	10	0	payto://x-taler-bank/bank.test.taler.net/393	account-1	1566476014000000
4	\\x1c18ce673522c676d133d3fd38fc525c06f9139256f97733392aa476b38da935	\\x000000000000034c	10	0	payto://x-taler-bank/bank.test.taler.net/392	account-1	1566475277000000
5	\\x4d93a5159d2a5bd6910267a91c3111ac495329410097a1adcf772d3a240df2bb	\\x000000000000034a	10	0	payto://x-taler-bank/bank.test.taler.net/391	account-1	1566427028000000
6	\\xbd46bfe36609883ca276710aa7446bdf49d7a03f005472630e50a0784a53a741	\\x0000000000000348	10	0	payto://x-taler-bank/bank.test.taler.net/390	account-1	1566427006000000
7	\\x2dbb53c2f3627f50b18ec54e15246c7b5f81a15683f53a7177029814f8da8bc2	\\x0000000000000345	10	0	payto://x-taler-bank/bank.test.taler.net/389	account-1	1566405376000000
8	\\x1f4681908ed2f225632346cc1e3b4988ce8fa6c1c8ab179f978b3bcff3c21bf1	\\x0000000000000343	10	0	payto://x-taler-bank/bank.test.taler.net/388	account-1	1566405026000000
9	\\x688b922cfa19931ba3d9030b747bdc2da9716aac4e53f21a15c5988456915581	\\x0000000000000341	10	0	payto://x-taler-bank/bank.test.taler.net/387	account-1	1566404945000000
10	\\x012e41df79ff63a8f39d2817a86bbc0e60f14e70440fbab3c234fc4a8d05d439	\\x000000000000033e	10	0	payto://x-taler-bank/bank.test.taler.net/386	account-1	1566397498000000
11	\\x6c3a52338741d0f462f571f42daf5be81b7a945da9ad871cc9f58ddd700193aa	\\x000000000000033b	10	0	payto://x-taler-bank/bank.test.taler.net/385	account-1	1566394252000000
12	\\xc8e442c5c85ef054a27974ba39c3745c9d017f4bf8e52768c5e8669ba8583e66	\\x0000000000000339	10	0	payto://x-taler-bank/bank.test.taler.net/384	account-1	1566394222000000
13	\\xc9675953172121e16dab952fc11a250245a5682fc6c5cb921cbe1753869d3299	\\x0000000000000337	10	0	payto://x-taler-bank/bank.test.taler.net/383	account-1	1566393958000000
14	\\xc37168aec489a6472db4efc0a85feeb19f6c8cdf1de3723945bba9bd8a7fb634	\\x0000000000000335	10	0	payto://x-taler-bank/bank.test.taler.net/382	account-1	1566393343000000
15	\\x0a26d1acfe138d947700857a157a007c0f8b44cb2cd5387c4e4ba1dc21603e6c	\\x0000000000000333	10	0	payto://x-taler-bank/bank.test.taler.net/381	account-1	1566393317000000
16	\\xc7624530ea124cca7e8661163d6b4016d2a4252b63c901a77a9d1771245da8f9	\\x0000000000000331	10	0	payto://x-taler-bank/bank.test.taler.net/380	account-1	1566392677000000
17	\\xb71c07fdff675806af9e20022b7bf5ec0ec16f0892d3b866436f659da502a25f	\\x000000000000032f	10	0	payto://x-taler-bank/bank.test.taler.net/379	account-1	1566392545000000
18	\\xc8f38a375831272de806e769f96d6c4c142b9c249a5110eb26c35117f69014a3	\\x000000000000032d	10	0	payto://x-taler-bank/bank.test.taler.net/378	account-1	1566389252000000
19	\\xe67cf6c190418a44ff772b5af0075de9f50ecb27d168c907837528575531a747	\\x000000000000032b	10	0	payto://x-taler-bank/bank.test.taler.net/377	account-1	1566389178000000
20	\\x74a4f75e0092c7f48bacfcdc2b3eac5fa93c61548b0bdd053e0bfbb741d9af51	\\x0000000000000325	10	0	payto://x-taler-bank/bank.test.taler.net/376	account-1	1566387148000000
21	\\x62ce130deab667ded5da342d4a7c8a48259c5464e4c11f9a41a155622f736d8a	\\x0000000000000321	10	0	payto://x-taler-bank/bank.test.taler.net/375	account-1	1566386814000000
22	\\x53339a2bc10f6d6dc9f3c275269fab85e67ea25dc2853d5c25898ed41d51331e	\\x000000000000031c	10	0	payto://x-taler-bank/bank.test.taler.net/374	account-1	1566386362000000
23	\\xb2f0675021b8b2b2c82a33d7de06a6188014ef6f641ec1f63b98574adc4a5a79	\\x0000000000000319	10	0	payto://x-taler-bank/bank.test.taler.net/373	account-1	1566386271000000
24	\\x64de8ad09221295cda8823d29797b5335c3c40efd0111a20134fef96bbd9ac9a	\\x0000000000000317	10	0	payto://x-taler-bank/bank.test.taler.net/372	account-1	1566386085000000
25	\\x7140831bef79c6208bca40a3b926a8045cc19cd504f0502261d8d8c5872c9de9	\\x0000000000000314	10	0	payto://x-taler-bank/bank.test.taler.net/371	account-1	1566385895000000
26	\\xe3c38f7f9a1f808655c624f450bd9e1d084ac6448d9f42fbe56dc99c017b176e	\\x0000000000000311	10	0	payto://x-taler-bank/bank.test.taler.net/370	account-1	1566385833000000
27	\\xfc13820602150f5b065d5e8c34ad9c01b28403af35f155bf471c478399382725	\\x000000000000030e	10	0	payto://x-taler-bank/bank.test.taler.net/369	account-1	1566376892000000
28	\\x5d7b8eea903cbe3c4926db1c8c8cce69482ecbc196bd65813388ce3237d77f56	\\x000000000000030c	10	0	payto://x-taler-bank/bank.test.taler.net/368	account-1	1566376792000000
29	\\x77e1ae7a8bfaadc974396088d2fd22fee5398df641a7c3dba0760765875cf6b5	\\x000000000000030a	10	0	payto://x-taler-bank/bank.test.taler.net/367	account-1	1566373449000000
30	\\xdd6e5ecaad109e27520aacc88c39cc4830235f280e8bd11779f38ebee15b237f	\\x0000000000000307	10	0	payto://x-taler-bank/bank.test.taler.net/366	account-1	1566333832000000
31	\\xc856b9453e72fc92eeecf9614cba6acfdfb67a39d1f1017b59803ec0f8f5f8ad	\\x0000000000000305	10	0	payto://x-taler-bank/bank.test.taler.net/365	account-1	1566333792000000
32	\\x119efdc91109466f9d6c8bcf33f956d0046b01380ce66b44ebc3a2902d827d89	\\x0000000000000303	10	0	payto://x-taler-bank/bank.test.taler.net/364	account-1	1566333684000000
33	\\x38cc57b994cf977e00c6c4c25357796e9c2d79b44ce890ce49925cdc6c3d54ac	\\x0000000000000301	10	0	payto://x-taler-bank/bank.test.taler.net/363	account-1	1566332441000000
34	\\x0f352c26485d153ab1654b49a06dc5a47a0b4a14bf4a42cb4cbd18b87fb07374	\\x00000000000002ff	10	0	payto://x-taler-bank/bank.test.taler.net/362	account-1	1566331804000000
35	\\xa2f9f8326db9d373b252fcc3a0401bc85b3e97618dc3a432487ef38cd9a6517a	\\x00000000000002fc	10	0	payto://x-taler-bank/bank.test.taler.net/361	account-1	1566330461000000
36	\\x46e452f1184d8f6d218534b68b79b8cf6143f1ebaf118a9773546aa200996955	\\x00000000000002f9	10	0	payto://x-taler-bank/bank.test.taler.net/360	account-1	1566330320000000
37	\\x47dbd1fbb39cee3d39c117e376c472fa0d0fc6fceccd5f5e978bace5a6af0ab0	\\x00000000000002f6	10	0	payto://x-taler-bank/bank.test.taler.net/359	account-1	1566330086000000
38	\\x5941c4d722de161c804086ea30952008b7dd1a6aaf10ef708e2fa122102bae7b	\\x00000000000002f3	10	0	payto://x-taler-bank/bank.test.taler.net/358	account-1	1566329229000000
39	\\x051cbec08070f5a75e6de51d35e1aeb7b01a36036a141d2066181092d1d39b11	\\x00000000000002f1	10	0	payto://x-taler-bank/bank.test.taler.net/357	account-1	1566328595000000
40	\\x69cff834caa39abbb70820d036158ce6cd3a7f99cb8cec263337660b7383bcee	\\x00000000000002ec	10	0	payto://x-taler-bank/bank.test.taler.net/356	account-1	1566326490000000
41	\\x6874b7482af6d0ad81a6d31e6fd08c7ab18503c28e053bda598bfd0acb180c7e	\\x00000000000002e9	10	0	payto://x-taler-bank/bank.test.taler.net/355	account-1	1566326185000000
42	\\xdeaaddb0ca6611d9ed384e3b729028fcc22d2fa5764e3843aad3172958ef79d3	\\x00000000000002e7	10	0	payto://x-taler-bank/bank.test.taler.net/354	account-1	1566325818000000
43	\\xcbeb4efeee8f755ad46a4cbbe367284d0a31e8355b703eaf3c62a90c25bb6815	\\x00000000000002e4	10	0	payto://x-taler-bank/bank.test.taler.net/353	account-1	1566320369000000
44	\\xa044250c7644a8664c2d7dd4f4146946c7d7a74cc9d3c72f24861cca285e515e	\\x00000000000002e0	10	0	payto://x-taler-bank/bank.test.taler.net/352	account-1	1566316221000000
45	\\x9ad482c0b94c3fe5403c0093d5609a77e459422795cc0ad7b091f6a28039c281	\\x00000000000002de	10	0	payto://x-taler-bank/bank.test.taler.net/351	account-1	1566316062000000
46	\\x06f725b34ff44ea72a88e0d72d9c754462176850b63841e5ac62eeaa0107da8e	\\x00000000000002da	10	0	payto://x-taler-bank/bank.test.taler.net/350	account-1	1566313444000000
47	\\x4aba78fd0c360bd6bdfb1be8c0033adc09d669e7363ff4f75c7addbead866087	\\x00000000000002d8	10	0	payto://x-taler-bank/bank.test.taler.net/349	account-1	1566312135000000
48	\\x003756a82312c1f165d22735a4d91a0931970335d69739be893422b3630bd5df	\\x00000000000002d6	10	0	payto://x-taler-bank/bank.test.taler.net/348	account-1	1566312049000000
49	\\x7274923e113464192d274534a3b8dd38572393cf8b6b9a26973ce0c657f830fd	\\x00000000000002d4	10	0	payto://x-taler-bank/bank.test.taler.net/347	account-1	1566300097000000
50	\\xb353ec37ab0e6c7b624ae1779404f65f4b7c3dc601a72ca2e0d7f23633946144	\\x00000000000002d2	10	0	payto://x-taler-bank/bank.test.taler.net/346	account-1	1566300079000000
51	\\xf6157d960f7b08f4ecd45e8f856090fcb22e069858394a4e7fc97488a88852a5	\\x00000000000002d0	10	0	payto://x-taler-bank/bank.test.taler.net/345	account-1	1566300069000000
52	\\x14a56bea0d1606f7636eb8ddcbbfcd8a9479130b22589f154e37ee1575842e1e	\\x00000000000002ce	10	0	payto://x-taler-bank/bank.test.taler.net/344	account-1	1566297956000000
53	\\x3eceb3f3a13e966853b828a49921188a0305ccfc88be178f2a76a7e210f174ec	\\x00000000000002cc	10	0	payto://x-taler-bank/bank.test.taler.net/343	account-1	1566297947000000
54	\\xf939b9ad110e76af9ee82c5924c812709f610e73f651a120b7b93a35ad8a9462	\\x00000000000002ca	10	0	payto://x-taler-bank/bank.test.taler.net/342	account-1	1566297933000000
55	\\xfefdc664b156a8956c22392708056f7771beb50eef224383e7be4e7178a6a8bb	\\x00000000000002c8	10	0	payto://x-taler-bank/bank.test.taler.net/341	account-1	1566297922000000
56	\\x0e2d0beab43b0b4fd20157e8b373f21b1fee2a513ebe0fcd18464bfe22889272	\\x00000000000002c6	10	0	payto://x-taler-bank/bank.test.taler.net/340	account-1	1566297730000000
57	\\x0425ba60520bbc67ea59dd44fdac94d44aec328d4a504f9a96cd7115d2d7718b	\\x00000000000002c4	10	0	payto://x-taler-bank/bank.test.taler.net/339	account-1	1566297601000000
58	\\x6e9d183ab868e7ff9d40138dd763896cb8ee9b230e2de94f73b0d788b738f8a4	\\x00000000000002c2	10	0	payto://x-taler-bank/bank.test.taler.net/338	account-1	1566245473000000
59	\\x813db9bd108f103f010eee5c9347a0f8d36da0076ecdfc2aef7e02d643234196	\\x00000000000002c1	10	0	payto://x-taler-bank/bank.test.taler.net/337	account-1	1566245473000000
60	\\x59c56af7431f2115a0c22aa89892d170a9a9471db5014e8a824fbc19dcc2d843	\\x00000000000002c0	10	0	payto://x-taler-bank/bank.test.taler.net/335	account-1	1566245473000000
61	\\x53d4ea53beca2041bb9b7885f1bf52fbac6b87c44ee7c27b8d5e9eb6d17cc0e5	\\x00000000000002bf	10	0	payto://x-taler-bank/bank.test.taler.net/336	account-1	1566245473000000
62	\\xfe59643d79bcc5ecf39a4fda8016c47fd7c8c3635f1bba0a7f6e0c13c134a4b8	\\x00000000000002be	10	0	payto://x-taler-bank/bank.test.taler.net/334	account-1	1566245472000000
63	\\xccc34040dbcf81f0f68cf8c23a5c381c48a8819bf7f0f2d83b24c409023361e6	\\x00000000000002b8	10	0	payto://x-taler-bank/bank.test.taler.net/333	account-1	1566245061000000
64	\\x9abf75e6216b8039d914aa14b8c6ef77952b49f8f4b25cc29ee0a6e0cacbfc70	\\x00000000000002b6	10	0	payto://x-taler-bank/bank.test.taler.net/332	account-1	1566245006000000
65	\\x76c21837710c2e390b9fe23674f581e87e07ce96e4972c1af82ec1a0847ae95d	\\x00000000000002b4	10	0	payto://x-taler-bank/bank.test.taler.net/331	account-1	1566244957000000
66	\\xc725d349c67fd479c2c512e29e33055753da64877d33335fb1b2432e7a32d999	\\x00000000000002b2	10	0	payto://x-taler-bank/bank.test.taler.net/330	account-1	1566244950000000
67	\\x2af399b74d0691fb36c2e2b6c00631694b51607c332fd97f29a8d4ecca5c7ef6	\\x00000000000002b0	10	0	payto://x-taler-bank/bank.test.taler.net/329	account-1	1566244024000000
68	\\xd58aa182bdc6b8f4463bf392e0bb003325bfb653ad7c18f32d39e38fd20e7ed0	\\x00000000000002ae	10	0	payto://x-taler-bank/bank.test.taler.net/328	account-1	1566243569000000
69	\\xe7ac2051b945e977cdb2a613d4434c04c26dd3b102a1bc82d29d08a81ae86b2b	\\x00000000000002ac	10	0	payto://x-taler-bank/bank.test.taler.net/327	account-1	1566243539000000
70	\\x2f45b07e937fd0a1feb3d9fcc7aa6c149a96e84338fa251f53f148ceca4b96d5	\\x00000000000002aa	10	0	payto://x-taler-bank/bank.test.taler.net/326	account-1	1566243321000000
71	\\x204f1f80cd9e66810bbf74e58cb1838d904ee5941ed205aba33bf9f1e236e49d	\\x00000000000002a8	10	0	payto://x-taler-bank/bank.test.taler.net/325	account-1	1566243309000000
72	\\xdb41e9f1ad98bb9bf42c952b770c69c4019fa6c4524f77f92cb4189e96bca115	\\x00000000000002a6	10	0	payto://x-taler-bank/bank.test.taler.net/324	account-1	1566242800000000
73	\\x30fba371e70b4ebc0a40f952c43d50d18719b36d310b891059808ea5a21c3710	\\x00000000000002a4	10	0	payto://x-taler-bank/bank.test.taler.net/323	account-1	1566242788000000
74	\\x26bd0786ce312f0aec4cc46d8c2a0368974f065f61ecc345c713aa0fc8fa5c2a	\\x00000000000002a2	10	0	payto://x-taler-bank/bank.test.taler.net/322	account-1	1566242772000000
75	\\x3e6809817ca4477f5ec4ac74c0bbb76e48448176043a2cb456b0dc455a79632f	\\x00000000000002a0	10	0	payto://x-taler-bank/bank.test.taler.net/321	account-1	1566242748000000
76	\\x5a374956e5ff8785db62f4deccdc41d65aad3bb1927344122447acc016aa44f9	\\x000000000000029e	10	0	payto://x-taler-bank/bank.test.taler.net/320	account-1	1566242656000000
77	\\xc3c6006069c05603856ac9e6bf25192f6684467721b96350bdfabc8008bbec9d	\\x000000000000029c	10	0	payto://x-taler-bank/bank.test.taler.net/319	account-1	1566242538000000
78	\\xa5d0664f9f0fdfb4407c6e90712d57e98e824dc1bbc75c79620f68f97d8fd5ca	\\x000000000000029a	10	0	payto://x-taler-bank/bank.test.taler.net/318	account-1	1566242396000000
79	\\x7039453d2727338652a5432ffca59220fe15ebb3e09399d238215311f015107d	\\x0000000000000298	10	0	payto://x-taler-bank/bank.test.taler.net/317	account-1	1566242338000000
80	\\x3428bcdcd2725e6038bba0d5e3189f3caf0c342d55a25d02be539d6ab97cc20c	\\x0000000000000296	10	0	payto://x-taler-bank/bank.test.taler.net/316	account-1	1566241294000000
81	\\x22c98e04feee74f42fba4ab3f00627a118c4d8279df397776bb785903e07ab1e	\\x0000000000000294	10	0	payto://x-taler-bank/bank.test.taler.net/315	account-1	1566240636000000
82	\\x59998f08f6e8f35ea10c51c5700aae79b9f6d6b5f684a377a7f5b2fa6a64a269	\\x0000000000000292	10	0	payto://x-taler-bank/bank.test.taler.net/314	account-1	1566240236000000
83	\\x10dd95f3a5de768b7690839be29f2d8974b0654d13f20b5f7437d768d14f51bc	\\x0000000000000290	10	0	payto://x-taler-bank/bank.test.taler.net/313	account-1	1566240159000000
84	\\x87a6b79a88d73b92f7169010d401421224a6a24b67f40471c4a4761cc0f0bfb2	\\x000000000000028e	10	0	payto://x-taler-bank/bank.test.taler.net/312	account-1	1566240037000000
85	\\x33396f85d648a84af67f09d35532751fa8d90e22b218d0798bd444b12ddac3a2	\\x000000000000028c	10	0	payto://x-taler-bank/bank.test.taler.net/311	account-1	1566239308000000
86	\\x91837011a5b129b2a1ecdaf92cf0fe157479e26044f16705f06aab77c7157879	\\x000000000000028a	10	0	payto://x-taler-bank/bank.test.taler.net/310	account-1	1566239253000000
87	\\x789a55c8a99464a9a7c9c3640e917aa0b4ee760cd49850b1c2c0173480e1486d	\\x0000000000000288	10	0	payto://x-taler-bank/bank.test.taler.net/309	account-1	1566239010000000
88	\\xed4538ca12e87d07f8a036054059c92f875b1fdf5f5cbe12a0dd8c72efc0ef1b	\\x0000000000000286	10	0	payto://x-taler-bank/bank.test.taler.net/308	account-1	1566238980000000
89	\\x1c524fbbb8045eaff17a3935d67f85234f342c943933fb1a0e827f99330bcf05	\\x0000000000000284	10	0	payto://x-taler-bank/bank.test.taler.net/307	account-1	1566238913000000
90	\\x29bb82bedb668a22791007266113a81977b54d9524bfb195812eb4637f449d1d	\\x0000000000000282	10	0	payto://x-taler-bank/bank.test.taler.net/306	account-1	1566238897000000
91	\\xcd9a6ca7e8cf43aabcf1b7e3403139c2ac1d990f78334360d326660ceec8df15	\\x0000000000000280	10	0	payto://x-taler-bank/bank.test.taler.net/305	account-1	1566238783000000
92	\\xbaf74548c792dea461ca5aaf83a69b3a7c9c220a910ab45c286a1ae7df7f1d77	\\x000000000000027e	10	0	payto://x-taler-bank/bank.test.taler.net/304	account-1	1566238056000000
93	\\x7e63f67c1940a9b23d13697aa6582a1fe69581bbd2f1c5098cd3561a989eba3a	\\x000000000000027c	10	0	payto://x-taler-bank/bank.test.taler.net/303	account-1	1566236519000000
94	\\x59bfd4e6dbaa2dfdb58244208e88533a7849ceb3e3e235e427d516ccd69ac5fc	\\x000000000000027a	10	0	payto://x-taler-bank/bank.test.taler.net/302	account-1	1566236071000000
95	\\x268c99db0a689c8fe3544e83745f2c5e3d476ae6e6abe8b62babdcdc62208ee1	\\x0000000000000278	10	0	payto://x-taler-bank/bank.test.taler.net/301	account-1	1566232865000000
96	\\xe7e3ffe3752203bbfa38003e5c6ea51c395c2aa4056b258461f0b24dfbc5a773	\\x0000000000000276	10	0	payto://x-taler-bank/bank.test.taler.net/300	account-1	1566232802000000
97	\\x3b34626e4bd1d6a90a17685dffa13b1de5eaaaefee9dff5b62531b6f9c2b25cb	\\x0000000000000274	10	0	payto://x-taler-bank/bank.test.taler.net/299	account-1	1566232151000000
98	\\x1c50880a086245f96b09dbc9262696d31570b359e9aa847c62dc724e1bbc3904	\\x0000000000000272	10	0	payto://x-taler-bank/bank.test.taler.net/298	account-1	1566212292000000
99	\\xe532b4eaa3a651af35fe482844cf4ee58d9933594e1d07348db46d507d44d136	\\x0000000000000270	10	0	payto://x-taler-bank/bank.test.taler.net/297	account-1	1566211792000000
100	\\xa9508cf654f874b6ac7c137c67a34daadd7566c01452359b0c1974fd866c88a9	\\x000000000000026d	10	0	payto://x-taler-bank/bank.test.taler.net/296	account-1	1566162797000000
101	\\xb6dd4e754c04f7f454fc76eeea421a02db0ab80cadd6e095913aa6a467d08df8	\\x000000000000026a	10	0	payto://x-taler-bank/bank.test.taler.net/295	account-1	1566162322000000
102	\\xc484befd64ce803855834b06e849343331d654f98d2c681c28ae2547533afb07	\\x0000000000000266	10	0	payto://x-taler-bank/bank.test.taler.net/294	account-1	1566162199000000
103	\\x9222bf7c3c95fb9eda6f228d44573407bfbd4c440351830f2d770ac84ab44e36	\\x0000000000000264	10	0	payto://x-taler-bank/bank.test.taler.net/293	account-1	1566162183000000
104	\\x9c377c7a5181ac3a9cd7609eea358428156380615afc3730f87bee265213a756	\\x0000000000000261	10	0	payto://x-taler-bank/bank.test.taler.net/292	account-1	1566161708000000
105	\\xb800e06c8b550082d031a22fde02d8654c27fc7e778c33ab8296349365f72347	\\x000000000000025f	10	0	payto://x-taler-bank/bank.test.taler.net/291	account-1	1566161657000000
106	\\xe57325eea480ac0c9b3434a30b1952ba7deac6d00106b6b9974878edcdf40e7e	\\x000000000000025c	10	0	payto://x-taler-bank/bank.test.taler.net/290	account-1	1566161534000000
107	\\x406b9add395d06468c5828d686b1e78e58f7b6972a25201f452626a4f7dd7d7a	\\x000000000000025a	10	0	payto://x-taler-bank/bank.test.taler.net/289	account-1	1566161473000000
108	\\x89470dee4c3110f9cdc4b7f851b003d1de5417379f473bbdb57454e1997c0a0c	\\x0000000000000256	10	0	payto://x-taler-bank/bank.test.taler.net/287	account-1	1566161289000000
109	\\xda46933e2a492f1c30d56d18176082a5bfb1b9b073abd0cce747f5111137a8b1	\\x0000000000000253	10	0	payto://x-taler-bank/bank.test.taler.net/286	account-1	1566161223000000
110	\\x4c7d9dde23ca42d415f01730f0b19c4ac60560c40095652048b08d2633aa2810	\\x0000000000000251	10	0	payto://x-taler-bank/bank.test.taler.net/285	account-1	1566161205000000
111	\\x5e293aeb6c08a5bcbb1e61df798220451f07f36d00affaa9190775a5f7180caa	\\x000000000000024f	10	0	payto://x-taler-bank/bank.test.taler.net/284	account-1	1566160855000000
112	\\xefe525ec2968cd6845b8c92b02a73c0a0af9af88de003d82ca12deb9e22e9dc0	\\x000000000000024d	10	0	payto://x-taler-bank/bank.test.taler.net/283	account-1	1566160503000000
113	\\xaa87f84bcc4744d63b96cff8436a5f88405dfb5f22a39fd9f9552e8633de9942	\\x000000000000024b	10	0	payto://x-taler-bank/bank.test.taler.net/282	account-1	1566160323000000
114	\\x6ded4375cd71b389104b9096226a89fa1a1846cb7af324842e4a62ca4f32072d	\\x0000000000000249	10	0	payto://x-taler-bank/bank.test.taler.net/281	account-1	1566160271000000
115	\\x1b0e3b898562b405d5989b3617178871f6a0e73f1ca2ade7c293ed29ad760c72	\\x0000000000000246	10	0	payto://x-taler-bank/bank.test.taler.net/280	account-1	1566159278000000
116	\\xd7a6cb733790839a79bed1e9d2ee4b7d8fd66ae70f1645c84edbc535b0d77e33	\\x0000000000000244	10	0	payto://x-taler-bank/bank.test.taler.net/279	account-1	1566159163000000
117	\\xad658d529cb575c0d1d025056f724ad59c2f0efadfc052d4300d4066669f5f20	\\x0000000000000242	10	0	payto://x-taler-bank/bank.test.taler.net/278	account-1	1566157690000000
118	\\xe0b3f02bf670cd068c2483b252c2a47ca204d46b6821ea94f58444345d2004c7	\\x000000000000023f	10	0	payto://x-taler-bank/bank.test.taler.net/277	account-1	1566152613000000
119	\\x66af8e219c20e49afe73128b8687a39e0b8a36f6ce79286714c058e0efdd9669	\\x000000000000023d	10	0	payto://x-taler-bank/bank.test.taler.net/276	account-1	1566152522000000
120	\\x7a218bdf8b9e773794613b3db323fcc95867819c59e24726f7dcf4a13be842d9	\\x000000000000023b	10	0	payto://x-taler-bank/bank.test.taler.net/275	account-1	1566150042000000
121	\\x33453afe5db166f0aa10e4acda686dba022990a845753f3d6d06a61b24cd46a5	\\x0000000000000239	10	0	payto://x-taler-bank/bank.test.taler.net/274	account-1	1566149967000000
122	\\x6b7cede5ceb81248262a13b1d86f2d3b392c18e0c93788fecb5284917523a57d	\\x0000000000000237	10	0	payto://x-taler-bank/bank.test.taler.net/273	account-1	1566149930000000
123	\\xb9d4fdfed4243cf830cebc3195b0d2659649d8a8b4aa885301f83410ae0024e4	\\x0000000000000234	10	0	payto://x-taler-bank/bank.test.taler.net/271	account-1	1566149859000000
124	\\xd5da4a1a66b10dc4e12ab7461fe65023ee0ab2bacbef8fff13a0c0a1de15b66d	\\x0000000000000231	10	0	payto://x-taler-bank/bank.test.taler.net/270	account-1	1566138861000000
125	\\x3af59e0132735e05e27b112d6392ee58a11489cf568bbb5c25bb595405521ff3	\\x000000000000022e	10	0	payto://x-taler-bank/bank.test.taler.net/269	account-1	1566138687000000
126	\\x469bf9c86abb396de1863568f5789599dc6a439450f3f1905f6212bad9f4df9a	\\x000000000000022b	10	0	payto://x-taler-bank/bank.test.taler.net/268	account-1	1566138565000000
127	\\xa5b58e2c15151cc21b2a6d64a01f9358d6c0850067a34f9162351ecac4a57222	\\x0000000000000228	10	0	payto://x-taler-bank/bank.test.taler.net/267	account-1	1566138394000000
128	\\x271ee8933b0258c5551dcdc999da5b708b36ed97dad53800c45bc72d49a39cd7	\\x0000000000000225	10	0	payto://x-taler-bank/bank.test.taler.net/266	account-1	1566138213000000
129	\\x0ccff4d54e80cb3dd68f6e916973508e77051caaae735dd03bc306cfe0afae74	\\x0000000000000222	10	0	payto://x-taler-bank/bank.test.taler.net/265	account-1	1566138073000000
130	\\x6363234157eab234dc540d977e06cf6681bae43e7d2d87beed4739c08f6377c6	\\x000000000000021f	10	0	payto://x-taler-bank/bank.test.taler.net/264	account-1	1566137941000000
131	\\x294eb33578c0dd1135de2b6cc411cd59881a9add9f786995118673899e9c3e87	\\x000000000000021c	10	0	payto://x-taler-bank/bank.test.taler.net/263	account-1	1566137744000000
132	\\xa9d62c09b31f66606af346d0c7e64f77a92954a999e50ffcf574a217e8cb31e4	\\x0000000000000219	10	0	payto://x-taler-bank/bank.test.taler.net/262	account-1	1566137374000000
133	\\xe4d05ad2b0b5e27f3695806e468d54592cd5405e281485196ffa234e63fc68cb	\\x0000000000000216	10	0	payto://x-taler-bank/bank.test.taler.net/261	account-1	1566137157000000
134	\\xf0fda0cd3dda1d31a598c5b9e850a7c54456f8c482af6c1f70b380fd3a659c46	\\x0000000000000213	10	0	payto://x-taler-bank/bank.test.taler.net/260	account-1	1566136948000000
135	\\x695a2de3e0bfdee784b2409b58d18e069f55768745622205a4cb2a99016d976e	\\x0000000000000210	10	0	payto://x-taler-bank/bank.test.taler.net/259	account-1	1566136833000000
136	\\x59ba84ccb16e2a8c0197ae704c9805452d9f91203f0e2a2414865fb43b11b60d	\\x000000000000020d	10	0	payto://x-taler-bank/bank.test.taler.net/258	account-1	1566136582000000
137	\\xf7afb294f813be7682bda81a109f8cebc21c7dde782f897359ce3c4503a915f3	\\x000000000000020a	10	0	payto://x-taler-bank/bank.test.taler.net/257	account-1	1566135337000000
138	\\xa242dcf952f7a0284907e66479db7510f74fff91ce0c318c69e30cc42ac22b28	\\x0000000000000207	10	0	payto://x-taler-bank/bank.test.taler.net/256	account-1	1566135008000000
139	\\xa46479979b59dac9665291fe8c99f56fafd020ab6378518b24a7de4162c0a8fe	\\x0000000000000204	10	0	payto://x-taler-bank/bank.test.taler.net/255	account-1	1566133668000000
140	\\x9307406b793081d213b291e1220b05afa8f8dbe8f0a297729a78228d7b4f5363	\\x0000000000000202	10	0	payto://x-taler-bank/bank.test.taler.net/254	account-1	1566133653000000
141	\\x935c559fcf339b66ea197098e4a7165a373cada72ce6326c6649f21bb2b6958a	\\x00000000000001fe	10	0	payto://x-taler-bank/bank.test.taler.net/252	account-1	1566062283000000
142	\\x44884e596728d1764a441c476b6d1600f4e172b82224579a7a9c96d0264db3f3	\\x00000000000001fb	10	0	payto://x-taler-bank/bank.test.taler.net/251	account-1	1566061181000000
143	\\xa47e3ec298a912ce770d6f76505ab6bad3bc4f43012ea0a7d02018359ced5e77	\\x00000000000001f6	10	0	payto://x-taler-bank/bank.test.taler.net/247	account-1	1566060055000000
144	\\xec426b2ba4cd2036d645ace13c17ec24d034c47123f9b7259b19bddd75bbc282	\\x00000000000001f4	10	0	payto://x-taler-bank/bank.test.taler.net/246	account-1	1566060049000000
145	\\xfa6430afd028e2230004a93f5f989f716b04f07f22075c0f71f0de7fb885556d	\\x00000000000001f2	10	0	payto://x-taler-bank/bank.test.taler.net/245	account-1	1566060036000000
146	\\x59d46300018a3020106c7635630a580763c94359e41bb30381a5234ffb259462	\\x00000000000001ef	10	0	payto://x-taler-bank/bank.test.taler.net/243	account-1	1566049629000000
147	\\x3735705df5fdb4391e2c7308b6efd8aefb2cd17feed80c7d7409b062c4a7020b	\\x00000000000001ec	10	0	payto://x-taler-bank/bank.test.taler.net/241	account-1	1566049589000000
148	\\xb7c7fa0443475b8a8f7612bfeb862c3e27c75ef08c2ed9f4ee524e95ba215155	\\x00000000000001ea	10	0	payto://x-taler-bank/bank.test.taler.net/240	account-1	1566048975000000
149	\\xe5021623374e4f73a1021b432393316a64b9ff7d8a55b08fa4889bc3ea14cd5a	\\x00000000000001e8	10	0	payto://x-taler-bank/bank.test.taler.net/239	account-1	1566044441000000
150	\\x9c9aee06fecf3caa3de9173ae0afb78a3df2361f4a1c98bbaa2fa124dc774d3b	\\x00000000000001e6	10	0	payto://x-taler-bank/bank.test.taler.net/238	account-1	1565999485000000
151	\\x0f44803fb16fff27d5b00d0ff093c089dc7671feef732783d98b6057c78795ee	\\x00000000000001e4	10	0	payto://x-taler-bank/bank.test.taler.net/237	account-1	1565999477000000
152	\\xcb5d2f41dae0505e076d87da9c209b574708290b94ee53eb7c58b719ff9f8e4c	\\x00000000000001e2	10	0	payto://x-taler-bank/bank.test.taler.net/236	account-1	1565999460000000
153	\\xd66e178d92b2c62fec79634fb20a21c5700507111b36bde3a838a9e6afdcd962	\\x00000000000001e0	10	0	payto://x-taler-bank/bank.test.taler.net/235	account-1	1565999360000000
154	\\xd0afe6a042bd0d72502690e9b60cc521f101fe75eb854595e3679b3ff1d1f913	\\x00000000000001de	10	0	payto://x-taler-bank/bank.test.taler.net/234	account-1	1565999354000000
155	\\x5180d87442313b7237f1be51fb363524f197ee48e304d04b33f4f46aec114410	\\x00000000000001dc	10	0	payto://x-taler-bank/bank.test.taler.net/233	account-1	1565999301000000
156	\\x6189f786c04b5e735b639da1779c9806f86c4dd9324d92cb9ef9dbc6fc515b7b	\\x00000000000001da	10	0	payto://x-taler-bank/bank.test.taler.net/232	account-1	1565999283000000
157	\\x866ec7f2b2123ead9e3500c0ff1f83e386f392c49e2f163ffe697ffd41e0f90d	\\x00000000000001d8	10	0	payto://x-taler-bank/bank.test.taler.net/231	account-1	1565999276000000
158	\\x99ecea1c2119254d96d98ef43424b4cbe314fb5bb440e838f6a8a140301bce6d	\\x00000000000001d6	10	0	payto://x-taler-bank/bank.test.taler.net/230	account-1	1565998955000000
159	\\x99fbc0d1d5729fd3f0b33736844196fff3d8d278053a60b9b27b47916c3ddd0d	\\x00000000000001d4	10	0	payto://x-taler-bank/bank.test.taler.net/229	account-1	1565998910000000
160	\\x5a385ed4779a13d58684098b70882788437bab11102b38ad277aef41baada706	\\x00000000000001d2	10	0	payto://x-taler-bank/bank.test.taler.net/228	account-1	1565998663000000
161	\\xb52d325f032b2791d504a532ef9834b033e8ef87eb597bc1a26aa89a2365d212	\\x00000000000001d0	10	0	payto://x-taler-bank/bank.test.taler.net/227	account-1	1565998636000000
162	\\x5b63460c0b825d0eaa613f1fca865184b48d04dc105437eb67a267109daf0f02	\\x00000000000001ce	10	0	payto://x-taler-bank/bank.test.taler.net/226	account-1	1565998626000000
163	\\x66b219ab9cd23f25e4a3d93fcc72bd87fed8ee4f85fefd13df14c8942018584f	\\x00000000000001cc	10	0	payto://x-taler-bank/bank.test.taler.net/225	account-1	1565998504000000
164	\\xbdac584b91a8b1e39cce9f2063853822e248b424f3e68d46af1c6763a7a8c77d	\\x00000000000001ca	10	0	payto://x-taler-bank/bank.test.taler.net/224	account-1	1565998007000000
165	\\x8cd98bc82b641ec56a1685ce5e308cf2657281fa219d6325a66221bb16fff090	\\x00000000000001c8	10	0	payto://x-taler-bank/bank.test.taler.net/223	account-1	1565997710000000
166	\\x82018291d5681e391d52e11f0fe99dd7af9ba088ef8a04703d47c39c1131661a	\\x00000000000001c6	10	0	payto://x-taler-bank/bank.test.taler.net/222	account-1	1565997578000000
167	\\xc77e537ef13fd7c51e61cef89d2022c16b0686ff1c55764969a96ee4c87a3052	\\x00000000000001c4	10	0	payto://x-taler-bank/bank.test.taler.net/221	account-1	1565997290000000
168	\\x1d76762600f8bd3f4795f62f03add0c65566e6688292c8646a6b5da12cacf1dc	\\x00000000000001c2	10	0	payto://x-taler-bank/bank.test.taler.net/220	account-1	1565997147000000
169	\\xfcfcdc8cd2791777397249d4c3da52e1863f55ad0c6882e2d751bbd405302095	\\x00000000000001c0	10	0	payto://x-taler-bank/bank.test.taler.net/219	account-1	1565997130000000
170	\\x3f619c26dc967addb49cae026b9f91709a030e15addc6ca6a5127e72cc930001	\\x00000000000001be	10	0	payto://x-taler-bank/bank.test.taler.net/218	account-1	1565997000000000
171	\\xf5d83929494f27bfa0a816711d37f72cb65f822e8de11668fc52aebf6ce55682	\\x00000000000001bc	10	0	payto://x-taler-bank/bank.test.taler.net/217	account-1	1565996975000000
172	\\xa4d33108e549c5f07de36bb4d46529b1e368ace2ad4c34606eb1dfff199efd6d	\\x00000000000001ba	10	0	payto://x-taler-bank/bank.test.taler.net/216	account-1	1565996970000000
173	\\x7c002a0774ba18250483639e653c545867bd19c9a7e5e469f6867be5322a772b	\\x00000000000001b8	10	0	payto://x-taler-bank/bank.test.taler.net/215	account-1	1565996963000000
174	\\xb4de597a51faf7dba502d6b7d4d08809f423fe4e25218590e3fb05ccfc2824cd	\\x00000000000001b6	10	0	payto://x-taler-bank/bank.test.taler.net/214	account-1	1565996959000000
175	\\xf7719f9def9a2234ca81e166c0233b2468cbacd10b699d3cf61a6bd46c032a81	\\x00000000000001b4	10	0	payto://x-taler-bank/bank.test.taler.net/213	account-1	1565996913000000
176	\\x6bf8404ce889b919973f0dadfd10a1497e3fd6e794b7e64c6df8011a37511623	\\x00000000000001b2	10	0	payto://x-taler-bank/bank.test.taler.net/212	account-1	1565996907000000
177	\\x5608e9a6b49d5da56c6e306f6f35d37d71f5cd1f709a4ea4403ca1335b952dbb	\\x00000000000001b0	10	0	payto://x-taler-bank/bank.test.taler.net/211	account-1	1565996895000000
178	\\x093d02b628a9974e33fcf8a6d5fc6d74c70427960d524fd8674977d819163e72	\\x00000000000001ae	10	0	payto://x-taler-bank/bank.test.taler.net/210	account-1	1565996886000000
179	\\xbb61ab42b47a032fb8809a0fd1b2cd13f509c1e922863d9e84ac188bba2ba4a2	\\x00000000000001ac	10	0	payto://x-taler-bank/bank.test.taler.net/209	account-1	1565996871000000
180	\\x231459f058a65e3e280e888cec88737c2452fcdd1317322b92898372c8eee53f	\\x00000000000001aa	10	0	payto://x-taler-bank/bank.test.taler.net/208	account-1	1565996867000000
181	\\xb800dddd6ca1525b45937f3638762afba97df01c8fd68589b332cc6af8c17f6b	\\x00000000000001a8	10	0	payto://x-taler-bank/bank.test.taler.net/207	account-1	1565996297000000
182	\\x6edc8a322e33a069a0c0fe3ad6461c677dee1f9445deb38e243ce53bce2c5606	\\x00000000000001a6	10	0	payto://x-taler-bank/bank.test.taler.net/206	account-1	1565995725000000
183	\\x12fba7c03a70173a50b46399a5d848b0639b0c59f4465af5a923fecf0306356b	\\x00000000000001a4	10	0	payto://x-taler-bank/bank.test.taler.net/205	account-1	1565992036000000
184	\\x8b90d565724439977467feb78f95468ca325a6a583ec42eb9e528ed9ee67acfd	\\x00000000000001a1	10	0	payto://x-taler-bank/bank.test.taler.net/204	account-1	1565986862000000
185	\\x52b90c06be123b6979ec5d9ba1032013ce60a91dacddbecafee7302d9ce709b7	\\x000000000000019e	10	0	payto://x-taler-bank/bank.test.taler.net/203	account-1	1565981306000000
186	\\x92077db0eb754e8074b64199e68906e04614d790042aed5d9cc84db1f80e8aca	\\x000000000000019b	5	0	payto://x-taler-bank/bank.test.taler.net/201	account-1	1565960310000000
187	\\x31b91dbf4e89506f09d918dffa3a1800813f8e7fe1a7356c3a92681f62b9066f	\\x0000000000000198	10	0	payto://x-taler-bank/bank.test.taler.net/200	account-1	1565952928000000
188	\\x6e846e63f3d4d2639febf8c3ef0bc3ff60acdb5d81de4d83e02d5ae36885a82b	\\x0000000000000195	10	0	payto://x-taler-bank/bank.test.taler.net/199	account-1	1565952822000000
189	\\xd569191f67bff925e2e14f1a15e5392546b5bbc64ff1e7de72ad32c47a3959c0	\\x0000000000000192	10	0	payto://x-taler-bank/bank.test.taler.net/198	account-1	1565952649000000
190	\\xefeeaed84eef3241f90f8713642986f5a806911a899d461f4c88e8b0af61ffe4	\\x000000000000018f	10	0	payto://x-taler-bank/bank.test.taler.net/197	account-1	1565952620000000
191	\\xc1d651a7160f70ad594d9ee5cd188d42687fe99db4c41a61fe82633e626fa083	\\x000000000000018d	10	0	payto://x-taler-bank/bank.test.taler.net/196	account-1	1565952610000000
192	\\xe57f5d46511d0e766c18a6ca9fc54d3283a2bb102eb8bfdf8e32266c74bcc241	\\x000000000000018b	10	0	payto://x-taler-bank/bank.test.taler.net/195	account-1	1565944892000000
193	\\xf04ba9bc678428207d91776a9464b3b108b58c38fa268bc1b7a227eda49819e8	\\x0000000000000189	10	0	payto://x-taler-bank/bank.test.taler.net/194	account-1	1565944821000000
194	\\xed16aa8942792639654d1f6023e09d1d650f2b8c93a63c1009efe130b00bb1ca	\\x0000000000000186	10	0	payto://x-taler-bank/bank.test.taler.net/193	account-1	1565941630000000
195	\\x0a0d4eb5d1abbb8cea07fee2ba1ed90bd1ebc7e22daf4a368a03cb1ba3ace1ad	\\x0000000000000184	10	0	payto://x-taler-bank/bank.test.taler.net/192	account-1	1565940072000000
196	\\xed3384e769e63bbb3a3b0e7e0d7a695c87cb83beb68a07aea69dbd28a02a00f0	\\x0000000000000181	10	0	payto://x-taler-bank/bank.test.taler.net/191	account-1	1565937383000000
197	\\x6fceae6ef52dfe039f42c029ded6f5083158b76460d1a4415de2a13e0d6b141a	\\x000000000000017e	10	0	payto://x-taler-bank/bank.test.taler.net/190	account-1	1565935796000000
198	\\xe079bd72ea08e0f54d38e00c0eebecf518d7e81b60d03082e929fdf76954aad4	\\x000000000000017c	10	0	payto://x-taler-bank/bank.test.taler.net/189	account-1	1565910146000000
199	\\x9be84bc3757bc122966d499f582bb9f053dd837cffebec5317e28f0076820ac9	\\x000000000000017a	10	0	payto://x-taler-bank/bank.test.taler.net/188	account-1	1565909731000000
200	\\x5e203725f5da7b3a43eb8c55bf3bc7674a8c9aaf19e5706516da2d337a623e83	\\x0000000000000178	10	0	payto://x-taler-bank/bank.test.taler.net/187	account-1	1565909725000000
201	\\xf5d0a679138775b0bd2c7025d52533a4d3c663a2a8e790fbcbf1323c7038edea	\\x0000000000000176	10	0	payto://x-taler-bank/bank.test.taler.net/186	account-1	1565909666000000
202	\\x352ca9fad07eb58ff536e649e5257e8153c2d6388f4b50caaf6464d8c312ffa5	\\x0000000000000174	10	0	payto://x-taler-bank/bank.test.taler.net/185	account-1	1565909597000000
203	\\x2e199e3752fa0de89b8336f28ac07d39e835b663da6d875321332681524ef8b2	\\x0000000000000172	10	0	payto://x-taler-bank/bank.test.taler.net/184	account-1	1565909467000000
204	\\x354145bcdd8f777d8f7450e7364e6546d3b5bb2b81e285ce342e2d57022acb5a	\\x000000000000016f	10	0	payto://x-taler-bank/bank.test.taler.net/183	account-1	1565909394000000
205	\\xf8ad117b767116b4b6ecd1946e5c8258a9d0e26f10f5aeb83a2c96d9a4e801b5	\\x000000000000016c	10	0	payto://x-taler-bank/bank.test.taler.net/182	account-1	1565909086000000
206	\\x2d841e2844b84613d06e1871ce1ff7c7aeb6e6272d643d95cf83b800d83f6fa5	\\x000000000000016a	10	0	payto://x-taler-bank/bank.test.taler.net/181	account-1	1565909049000000
207	\\x099c38804d748d134f237668a8c22970981a1666cee497cab15a5b3761d95fe2	\\x0000000000000167	10	0	payto://x-taler-bank/bank.test.taler.net/180	account-1	1565907603000000
208	\\x0534b703fcf4fb1bcc5c98894919ce8f6c647409c80ecb2f6784ea736f52a258	\\x0000000000000165	10	0	payto://x-taler-bank/bank.test.taler.net/179	account-1	1565907529000000
209	\\x4ef3a8013f6c1fd371954afdf7db5831e2a4b08a24a46d47ce0d0fe71db27450	\\x0000000000000162	10	0	payto://x-taler-bank/bank.test.taler.net/178	account-1	1565907253000000
210	\\x7e5c973417676e8adab516ab8ae8e867a929f1d5b49f19fa01cb129e1333557a	\\x000000000000015f	10	0	payto://x-taler-bank/bank.test.taler.net/177	account-1	1565906353000000
211	\\xdaf21c4d7d0506e761794bfd54286da9cccfbd5dcffec91d4de685ddeb2d9874	\\x000000000000015d	10	0	payto://x-taler-bank/bank.test.taler.net/176	account-1	1565906280000000
212	\\x37e05777be1d12227329799c20ceb6392c437fa7ff2f7cd9b73fb6942d97b674	\\x000000000000015a	10	0	payto://x-taler-bank/bank.test.taler.net/175	account-1	1565905346000000
213	\\xab61e6dc949dd1f35b2bcf8aa92155a61b37dc8ff002513db10988d72c10f85c	\\x0000000000000157	10	0	payto://x-taler-bank/bank.test.taler.net/174	account-1	1565904659000000
214	\\x9d7bdee2ad68d7850d99dc3009925e3fff8faf821c782c75b9e58d8401f492a6	\\x0000000000000154	10	0	payto://x-taler-bank/bank.test.taler.net/173	account-1	1565903993000000
215	\\xfbcab337efa5cad7f030026dd568ce0a9f6b32a3f0647b6c23d9055c4272ae38	\\x0000000000000152	10	0	payto://x-taler-bank/bank.test.taler.net/172	account-1	1565903788000000
216	\\xd24bceae2f137c7a7a33a7e27490f2ee051ca8303fee7d4dd8e78d7a1f0aee62	\\x0000000000000150	10	0	payto://x-taler-bank/bank.test.taler.net/171	account-1	1565903589000000
217	\\x5039d714051dc54f8a12d638d99d6ee2cbba8f84417d239ba13a6dae52a106d8	\\x000000000000014e	10	0	payto://x-taler-bank/bank.test.taler.net/170	account-1	1565903528000000
218	\\xe3885032e24de4aff2214d768134ee11d500559f69b92befe92a9b475fdbbeee	\\x000000000000014c	10	0	payto://x-taler-bank/bank.test.taler.net/169	account-1	1565903455000000
219	\\x92f04e72829581397d5d7af2cfbe8c1eb98769ed2a1dc49f9502e4efb1387ca4	\\x000000000000014a	10	0	payto://x-taler-bank/bank.test.taler.net/168	account-1	1565903383000000
220	\\xcbb9acd062ab443328e6050dbe93e2b8f84c6e2d06b4d98e8aace06251e06033	\\x0000000000000148	10	0	payto://x-taler-bank/bank.test.taler.net/167	account-1	1565903277000000
221	\\xe9cd9bd7e64730ffcca680c79dc186180f44228b2b64146e3e98689c074bf5a7	\\x0000000000000146	10	0	payto://x-taler-bank/bank.test.taler.net/166	account-1	1565903077000000
222	\\xe9475fffced36d5aa6e26073dd28ccc50f2ca4448b3089ecc9c13030abd8f60b	\\x0000000000000144	10	0	payto://x-taler-bank/bank.test.taler.net/165	account-1	1565902856000000
223	\\x87df20e293f6c021efdb3408e1f3121f79a5f1000cbdd3d2b09eade6969f07c8	\\x0000000000000142	10	0	payto://x-taler-bank/bank.test.taler.net/164	account-1	1565902784000000
224	\\xddb8dfe63ae9995f4846435d10bbb0b27887c5bd911082781c4efedd0df40f67	\\x0000000000000140	10	0	payto://x-taler-bank/bank.test.taler.net/163	account-1	1565902533000000
225	\\xf236ae1b03f5896bb57da63548778c065c31c5d30ca2e1b257b98e8a40a1f498	\\x000000000000013e	10	0	payto://x-taler-bank/bank.test.taler.net/162	account-1	1565901819000000
226	\\x245663abb3929008134cfadcd585d8c30189eac85a59ac3f63b57ee150394031	\\x000000000000013c	10	0	payto://x-taler-bank/bank.test.taler.net/161	account-1	1565901629000000
227	\\x7920ef3246557b9add917c3b24df7557e597b9ea132d7a6ade8147463f20d88e	\\x000000000000013a	10	0	payto://x-taler-bank/bank.test.taler.net/160	account-1	1565901302000000
228	\\x383faa3efbad6ba618b9a0518c726b968c093da880aa325e0815c26d302baa8d	\\x0000000000000138	10	0	payto://x-taler-bank/bank.test.taler.net/159	account-1	1565901249000000
229	\\x0c5cd55b9766b103527762452a1e81367c77bf6d24403a15b94ea0fa87904776	\\x0000000000000136	10	0	payto://x-taler-bank/bank.test.taler.net/158	account-1	1565900845000000
230	\\xd0310cbff1f595d844e540ff10e9e2de78fcb27fdba221f4243ec5bf69585c82	\\x0000000000000134	10	0	payto://x-taler-bank/bank.test.taler.net/157	account-1	1565900815000000
231	\\xb21a34488c76adf57605deef27a970d6d9d33da99fd10d5b34f971283282b936	\\x0000000000000132	10	0	payto://x-taler-bank/bank.test.taler.net/156	account-1	1565900324000000
232	\\x038996dfe9ad38f23e619fd7633f3074e88b03d48e59d818047613fe6617f725	\\x0000000000000130	10	0	payto://x-taler-bank/bank.test.taler.net/155	account-1	1565899745000000
233	\\xba2946c6883d1ed6f2770b5902b2b08f6ee0a02148b277b60a085f88118d3ddc	\\x000000000000012e	10	0	payto://x-taler-bank/bank.test.taler.net/154	account-1	1565899679000000
234	\\xb233d5a9840e928cb977bceb516306951f3690c14183539824dd61ee466f08c2	\\x000000000000012b	10	0	payto://x-taler-bank/bank.test.taler.net/153	account-1	1565898981000000
235	\\xa42e64a59afcf6bb9f1c76f9cb00613f067bc49f5e81b8e242d813bafccea2fc	\\x0000000000000128	10	0	payto://x-taler-bank/bank.test.taler.net/152	account-1	1565896715000000
236	\\x3ec53b2ead912ef64ac90c74d5a68e5b60ae65f0249af37ea6eb9e05b9164898	\\x0000000000000125	10	0	payto://x-taler-bank/bank.test.taler.net/151	account-1	1565888850000000
237	\\x21d76dcb3902f1dbdde706d80a37b852666435bbeca78bfdc5cef62d72686d43	\\x0000000000000122	10	0	payto://x-taler-bank/bank.test.taler.net/150	account-1	1565874286000000
238	\\xf1c90d032747f3cc1d8738eb9c888c1e4013f9e7064ffd521a7eaded85cfbc9f	\\x000000000000011f	10	0	payto://x-taler-bank/bank.test.taler.net/149	account-1	1565801356000000
239	\\xaf086d1b12d87e90235d15156afdafefe8fcd38f4de456e9bbfeb62b3d6c3ad4	\\x000000000000011c	10	0	payto://x-taler-bank/bank.test.taler.net/148	account-1	1565800433000000
240	\\x06ac13492eace96f3e5a49e44e0f18c4a356c77b1d4a8e856b976d9e9a436edc	\\x0000000000000119	10	0	payto://x-taler-bank/bank.test.taler.net/147	account-1	1565800289000000
241	\\xea06a92933ce6035f37c58c4476a5b661228594d98b62e4b8f8c2458fe451303	\\x0000000000000117	10	0	payto://x-taler-bank/bank.test.taler.net/146	account-1	1565800235000000
242	\\x64a12dded192a4f8edc3614e4acf52fbe27c78cbed3ab815f4627723ca14e4ab	\\x0000000000000114	10	0	payto://x-taler-bank/bank.test.taler.net/145	account-1	1565202594000000
243	\\xfb949fb3cf8195cd6424b1475ea365019a9a4fbb25041e94af644e201c7c83d6	\\x0000000000000111	10	0	payto://x-taler-bank/bank.test.taler.net/144	account-1	1565202402000000
244	\\xe566a9c140e79572592dfeb3dcf5cea94c9dd8da30dc292d8fe44a284ce5d481	\\x000000000000010f	10	0	payto://x-taler-bank/bank.test.taler.net/143	account-1	1565201202000000
245	\\xc2cabf67c5f7bdc043a7f62ed26cb12fd43b1492aabb44bf5db7f0d70e57dbf8	\\x000000000000010c	10	0	payto://x-taler-bank/bank.test.taler.net/142	account-1	1564696822000000
246	\\x07339becf40893d3ae5d1240e79f1f24c8289ce9ba616c570c50f7f58cd81169	\\x0000000000000109	10	0	payto://x-taler-bank/bank.test.taler.net/141	account-1	1564695804000000
247	\\x23e715a7d521c72f5b14338fea8ef018b42e255c3047d0a381ba1b892951a584	\\x0000000000000107	10	0	payto://x-taler-bank/bank.test.taler.net/140	account-1	1564695796000000
248	\\x18191bb360a5f0a52525101988c41ed8c9244511d8813371023d44164dd3ff9b	\\x0000000000000104	10	0	payto://x-taler-bank/bank.test.taler.net/139	account-1	1564694327000000
249	\\xbf0ff9a0ee337e7af907db7c46888d79a3f4e0dcc96ee1476a8bd4bb0b063a30	\\x0000000000000101	10	0	payto://x-taler-bank/bank.test.taler.net/138	account-1	1564694233000000
250	\\xdd974f8782ead8c4f65996e45e14cbdedd05b5ff194f2e069086c2918819b75c	\\x00000000000000fe	10	0	payto://x-taler-bank/bank.test.taler.net/137	account-1	1564694153000000
251	\\x24bfdf65d4f1f9d4569b886e727b9aa0dc6880614899b27f5663d8b72e1b583e	\\x00000000000000fc	10	0	payto://x-taler-bank/bank.test.taler.net/136	account-1	1564694104000000
252	\\xf03f57d32b04d85adbce1409248b6b5fb37321cd9d9cf87501d21db209336cdf	\\x00000000000000f9	10	0	payto://x-taler-bank/bank.test.taler.net/135	account-1	1564694014000000
253	\\xb808d9b7228568c2da8a58e1f0f5bab7af279d1db94592f1117e42163aeee7be	\\x00000000000000f6	10	0	payto://x-taler-bank/bank.test.taler.net/134	account-1	1564693825000000
254	\\x96b4b1dda4cf071443b4981f1d19d2f2f2e18c134355b9fee726e8f36bbdd2da	\\x00000000000000f3	10	0	payto://x-taler-bank/bank.test.taler.net/133	account-1	1564693777000000
255	\\xc18211fa8c81102e6fc987ba80a04caa028b1982b816a5d2785614d6ebec3c96	\\x00000000000000f0	10	0	payto://x-taler-bank/bank.test.taler.net/132	account-1	1564692761000000
256	\\x7085f00e9a48f4678899788358172b7447cd456c276a20d7313ca474be88b8a7	\\x00000000000000ed	10	0	payto://x-taler-bank/bank.test.taler.net/131	account-1	1564692647000000
257	\\x6803c62ef4992666d21fd5571e2807134d1aaa6f7fbb7f8333ddbab7910e0a00	\\x00000000000000eb	10	0	payto://x-taler-bank/bank.test.taler.net/130	account-1	1564692566000000
258	\\xd9639612a99db4d4527d907179d1649575ade0db21205bb984928d59916ff575	\\x00000000000000e9	10	0	payto://x-taler-bank/bank.test.taler.net/129	account-1	1564692538000000
259	\\xb4a2cee738ce45ecc226c07766148a710e68875ae06b92447f79d3615a279da7	\\x00000000000000e7	10	0	payto://x-taler-bank/bank.test.taler.net/128	account-1	1564692478000000
260	\\x66f3faced265ce5d6c8b67ca3566edf511e61b0caada94bf08ba538d01357b70	\\x00000000000000e5	10	0	payto://x-taler-bank/bank.test.taler.net/127	account-1	1564692433000000
261	\\x48df8b7cfd2999012b0004f8d0746d4c1ccf02051b6c55b071bf0bc3f92aee9c	\\x00000000000000e3	10	0	payto://x-taler-bank/bank.test.taler.net/126	account-1	1564692411000000
262	\\x548a4bc745f4033c770ed431c2321bbe70d609d881190f970251bda60052c5a5	\\x00000000000000e1	10	0	payto://x-taler-bank/bank.test.taler.net/125	account-1	1564691565000000
263	\\x63a477040824f3cd55ac8dbc628274a9107608c423fc51643ac25d2ed61d0de8	\\x00000000000000df	10	0	payto://x-taler-bank/bank.test.taler.net/124	account-1	1564691151000000
264	\\x2c1b8d0b80acb5f6e3049190ff613726a4b5441553b3d3ec77deb232594e7218	\\x00000000000000dd	10	0	payto://x-taler-bank/bank.test.taler.net/123	account-1	1564691105000000
265	\\xd78dde36de2139fa86f2a0f7bf8a13b2f654d9fc3cd303ebb2eab186cb9f0040	\\x00000000000000db	10	0	payto://x-taler-bank/bank.test.taler.net/122	account-1	1564690971000000
266	\\x1fdc52e5e5aaf87add91e7a1fec0fbf332ce7bd9c9d64154317e670798fe7fbb	\\x00000000000000d9	10	0	payto://x-taler-bank/bank.test.taler.net/121	account-1	1564614424000000
267	\\x1380f5e214357cb2e7717dff93edbdfe1a0ea3d38abaab37ab80e1c0c68ae71a	\\x00000000000000d7	10	0	payto://x-taler-bank/bank.test.taler.net/120	account-1	1564608599000000
268	\\x954518ac86a57cd7f8e87ee130a700fa82dfc8bebfe203ca3b74d2cd17e1cb26	\\x00000000000000d5	10	0	payto://x-taler-bank/bank.test.taler.net/119	account-1	1564608548000000
269	\\xbb8902b13a6baac9f348816b3c3b9ec1b3c3c806416a64c73dcc454e09227a92	\\x00000000000000d3	10	0	payto://x-taler-bank/bank.test.taler.net/118	account-1	1564608240000000
270	\\xe4d26be5cacceef7912af71ecde66d520cb080386e12e595f003247e1f936722	\\x00000000000000d1	10	0	payto://x-taler-bank/bank.test.taler.net/117	account-1	1564607402000000
271	\\x16b8099673434e13daef88b354ddde89a8ab8803a78a262ee01ff241af07951a	\\x00000000000000cf	10	0	payto://x-taler-bank/bank.test.taler.net/116	account-1	1564607300000000
272	\\xcd29f44596d41578562294edaa5f9d225da864c18d222ebc64186656208213c3	\\x00000000000000cd	10	0	payto://x-taler-bank/bank.test.taler.net/115	account-1	1564606676000000
273	\\x24f5e83ab46b9b876a6d044bdbfd86edd0d5ac06e34f822f73537f9e86ddd27e	\\x00000000000000cb	10	0	payto://x-taler-bank/bank.test.taler.net/114	account-1	1564606647000000
274	\\xa8120c712e0045d452667af538614c2ede7fa93e574b98c2568dc94f1200ed2f	\\x00000000000000c9	10	0	payto://x-taler-bank/bank.test.taler.net/113	account-1	1564606569000000
275	\\x8de9216933cf74b32a0ba183c5d47f07deb8d1ba6aeab2558d27933f8f46251a	\\x00000000000000c7	10	0	payto://x-taler-bank/bank.test.taler.net/112	account-1	1564606497000000
276	\\x86d56a0cf7a3981f71b607a9673ee2fe4ad3a8710274073cbe9dfb7ad73a2510	\\x00000000000000c5	10	0	payto://x-taler-bank/bank.test.taler.net/111	account-1	1564605529000000
277	\\x536fbc82c3257adfb45db4a7c3fea6661442a2edf4eb3413121e86916d84c559	\\x00000000000000c3	10	0	payto://x-taler-bank/bank.test.taler.net/110	account-1	1564538833000000
278	\\xc5665b33302b94735b0f53fabe3e4b28005be2cd6ea7b9f8ee133bc35f397ed3	\\x00000000000000c1	10	0	payto://x-taler-bank/bank.test.taler.net/109	account-1	1564538774000000
279	\\xa85e72dc53fad0966b30f675487aac5810e20b3bf7f36c63233bea2d1c9370e7	\\x00000000000000bf	10	0	payto://x-taler-bank/bank.test.taler.net/108	account-1	1564538601000000
280	\\x58964c1bcebf6b5513e15eb0eef739d38f1478e1cd53bf661342b9c62038cbe2	\\x00000000000000bd	10	0	payto://x-taler-bank/bank.test.taler.net/107	account-1	1564538559000000
281	\\xd3be87219e455c130fb5d5976ec829cdf39359a7d0a3e37cdabd0e42f2fad9b2	\\x00000000000000bb	10	0	payto://x-taler-bank/bank.test.taler.net/106	account-1	1564538404000000
282	\\x62d223b400193c59c2e72fbccbe09b9184ac7c1a028da0035d53461ca495555e	\\x00000000000000b9	10	0	payto://x-taler-bank/bank.test.taler.net/105	account-1	1564538347000000
283	\\x00c831aa5b629c775dc9a0175875c435262392e8ec98c820efab3c40f59c3fe8	\\x00000000000000b7	10	0	payto://x-taler-bank/bank.test.taler.net/104	account-1	1564538267000000
284	\\x1997040916524f5640cc195c47cb5c032164e8c192fa255e85a3ae9d5800660c	\\x00000000000000b5	10	0	payto://x-taler-bank/bank.test.taler.net/103	account-1	1564538197000000
285	\\xa3e78ad0d30b125cd2d8a415ca3b9a43b971ac8e43647a68064b78943ef65e7c	\\x00000000000000b3	10	0	payto://x-taler-bank/bank.test.taler.net/102	account-1	1564538175000000
286	\\x43204e72736000d5ddee27e781d5ad4b45bfde4b3e83173311189ab720af0dca	\\x00000000000000b1	10	0	payto://x-taler-bank/bank.test.taler.net/101	account-1	1564538144000000
287	\\xa6ea849bc978b07d539c37404ce74dafb28b94d46d3d929a9ddba72d176fc5fb	\\x00000000000000af	10	0	payto://x-taler-bank/bank.test.taler.net/100	account-1	1564538036000000
288	\\x35641ad074a9b19579b03e68c2bd128dd15deaf8684af5c4a346801372d41b90	\\x00000000000000ad	10	0	payto://x-taler-bank/bank.test.taler.net/99	account-1	1564537990000000
289	\\xaae06b233c96780d6afd620b1edd6f821d14a5bf432fbc5f4aeb689e7fe3d938	\\x00000000000000ab	10	0	payto://x-taler-bank/bank.test.taler.net/98	account-1	1564537954000000
290	\\x4c6d212fba5c61423aad80c8af8b1d5f3c94b267d920f53851caadf2166d49b0	\\x00000000000000a9	10	0	payto://x-taler-bank/bank.test.taler.net/97	account-1	1564537928000000
291	\\xd0c7accb37f6345703dfb0502fa150066094c681ed319b1dc2fcd234eb6fb767	\\x00000000000000a7	10	0	payto://x-taler-bank/bank.test.taler.net/96	account-1	1564537888000000
292	\\x64aed8c33abf2c05cefa50c0ecaf5e1f20201e747be1339b8d04fbb29b59cb57	\\x00000000000000a5	10	0	payto://x-taler-bank/bank.test.taler.net/95	account-1	1564537883000000
293	\\x69958928499e2c55da1ea6fb7833bd6a3e80962996c4a821fe95d05b58f96a26	\\x00000000000000a3	10	0	payto://x-taler-bank/bank.test.taler.net/94	account-1	1564537729000000
294	\\x5cb50417e9ab996297eb90960b33772f344ae83bc6ef32ebe96318d09cb331f0	\\x00000000000000a1	10	0	payto://x-taler-bank/bank.test.taler.net/93	account-1	1564537714000000
295	\\x06ea81e28c450fd05b5a0c912fef872fe3adf22a8ca70425cfd38ff2a65649e1	\\x000000000000009f	10	0	payto://x-taler-bank/bank.test.taler.net/92	account-1	1564537697000000
296	\\x81f75ad9675c95ba5078825b565c0f824f40359308975309996a4da4a5644f10	\\x000000000000009d	10	0	payto://x-taler-bank/bank.test.taler.net/91	account-1	1564537690000000
297	\\xb2c11ab01be7ce2856f045ae71e075b7773c0ee212d4fe17a6c3b7357610517d	\\x000000000000009b	10	0	payto://x-taler-bank/bank.test.taler.net/90	account-1	1564537683000000
298	\\x9656ed83ad3aa5cc92c0f8164a1be450f5f275de8ac3cbe3269a5b2bc67a4e8c	\\x0000000000000099	10	0	payto://x-taler-bank/bank.test.taler.net/89	account-1	1564537655000000
299	\\xb0f9afccc0e0e6db8ff80daafbe7e3402de21e2f37d57f22348397c5d5d28940	\\x0000000000000097	10	0	payto://x-taler-bank/bank.test.taler.net/88	account-1	1564537644000000
300	\\x302417b3226366b7893c3cf6ea0a9914d7f12ee9c4f7e68f4b0a743dddc2daad	\\x0000000000000095	10	0	payto://x-taler-bank/bank.test.taler.net/87	account-1	1564537597000000
301	\\xbebc635004c1523c36f749753b8d7df3e3a535d657529c88edda82aa8372688e	\\x0000000000000093	10	0	payto://x-taler-bank/bank.test.taler.net/86	account-1	1564537535000000
302	\\xd97382f3adeb334efc19beb626b79a465cf10e6722370f4158811962ea18bafa	\\x0000000000000091	10	0	payto://x-taler-bank/bank.test.taler.net/85	account-1	1564537486000000
303	\\x1da515d261a0b861b1c937b34bf6cbf0dfe0baf10646daec02035c888775be0f	\\x000000000000008f	10	0	payto://x-taler-bank/bank.test.taler.net/84	account-1	1564537480000000
304	\\x9f5bf80861719ced68d14c652154ef31251800dfb9b9d131fd211072cbe1dfe0	\\x000000000000008d	10	0	payto://x-taler-bank/bank.test.taler.net/83	account-1	1564537473000000
305	\\xf405b7257a8a5538d422ef6357ad1bf283cc4c11fffc5d0cfa766f72513618b6	\\x000000000000008b	10	0	payto://x-taler-bank/bank.test.taler.net/82	account-1	1564537413000000
306	\\x22f8a5abcfd602cc882981bb71b6369295be2134d32634f3f977149bcdcb58f0	\\x0000000000000089	10	0	payto://x-taler-bank/bank.test.taler.net/81	account-1	1564536410000000
307	\\xe28be2d1c6b322cf70742df0d1770adab4273af10f2a141ff703bbd24a9a9ac8	\\x0000000000000087	10	0	payto://x-taler-bank/bank.test.taler.net/80	account-1	1564536371000000
308	\\x6a0d97fb945b3b91e17b1e40f3e8b6d7b595a57e4bbffbea232987e427b5a1d1	\\x0000000000000085	10	0	payto://x-taler-bank/bank.test.taler.net/79	account-1	1564536331000000
309	\\xfb87bd1deed3e5c30cdd323ef440e77e42d859262962e9f99c03a5c740e4afaa	\\x0000000000000083	10	0	payto://x-taler-bank/bank.test.taler.net/78	account-1	1564536263000000
310	\\x312118463312133bf9537123a3930ac4a4d2c245baea11dd8fd32fd8351bed29	\\x0000000000000081	10	0	payto://x-taler-bank/bank.test.taler.net/77	account-1	1564536198000000
311	\\x4685b36210f4a6c7e87d9f88b5a45f834a0d5b58c9d138fd705aaf442e9ad8c4	\\x000000000000007f	10	0	payto://x-taler-bank/bank.test.taler.net/76	account-1	1564536071000000
312	\\xfb380400ea4f5a8fbc5b8bb4a09b779aaf217474955c02d02e6c2f7067293e2e	\\x000000000000007d	10	0	payto://x-taler-bank/bank.test.taler.net/75	account-1	1564536053000000
313	\\xbc40482ef0b8339c6ca1a7fdb65773a0e8a025c9c132fb6be01e73f7034e6e55	\\x000000000000007b	10	0	payto://x-taler-bank/bank.test.taler.net/74	account-1	1564535749000000
314	\\xd681ec996bf4ca985c7fa9577709158416c88988a29f20d8ea16dfbc27e494ff	\\x0000000000000079	10	0	payto://x-taler-bank/bank.test.taler.net/73	account-1	1564535583000000
315	\\x4deda68ee9c75e3eafa0727067c4778ca01a8e2adc85eb1a8b45035552a98578	\\x0000000000000077	10	0	payto://x-taler-bank/bank.test.taler.net/72	account-1	1564535176000000
316	\\xa83105590f3561f861081fcfd5f885a01585b325ffb3263c6a7c9c8d2a10c34c	\\x0000000000000075	10	0	payto://x-taler-bank/bank.test.taler.net/71	account-1	1564535167000000
317	\\x54b48db3c7833a4a43d7433a7443c0a43ca5eccdae6760937e9fe4c074b2a3da	\\x0000000000000073	10	0	payto://x-taler-bank/bank.test.taler.net/70	account-1	1564534808000000
318	\\xf4ce5a6636d9042b66f1633ae30b2aa5cd262a189ed20f793f72307dc9c248f0	\\x0000000000000071	10	0	payto://x-taler-bank/bank.test.taler.net/69	account-1	1564534634000000
319	\\xe6aec2213578fe4de5fee32f82d79ce13f168f9ddd1861ea50c2f13d62c9f4ad	\\x000000000000006f	10	0	payto://x-taler-bank/bank.test.taler.net/68	account-1	1564534070000000
320	\\x832ba7bf73d5b86429f3be7f245e0b8880f2e6feb29e6b3d6d5f13d586bf9fcc	\\x000000000000006d	10	0	payto://x-taler-bank/bank.test.taler.net/67	account-1	1564533855000000
321	\\xd3ff34a089de9aec918e3b75a0178136171af9a84fbee676ea5a8cc2a947c060	\\x000000000000006b	10	0	payto://x-taler-bank/bank.test.taler.net/66	account-1	1564533536000000
322	\\xe7fd68fd42067d407b98d1f30f80307353f5348047dc2649c82684240886e4fd	\\x0000000000000069	10	0	payto://x-taler-bank/bank.test.taler.net/65	account-1	1564533370000000
323	\\xb65138b306c3a742753688438123087da53e07319fc30ddb769baec37780d204	\\x0000000000000067	10	0	payto://x-taler-bank/bank.test.taler.net/64	account-1	1564533342000000
324	\\xf66b6fc40bfd70532fa6da42e8d746a20a74415647f99be6c5e5a855c97aa0a7	\\x0000000000000065	10	0	payto://x-taler-bank/bank.test.taler.net/63	account-1	1564533298000000
325	\\x95a1d91c014ba399e5f7494c4135cb3c81b0f69eeed821c85da402fc07c9daac	\\x0000000000000063	10	0	payto://x-taler-bank/bank.test.taler.net/62	account-1	1564532759000000
326	\\xcf622a2c3767c9f871100f9d782b792e1e6a5404833445d522789f924d169b4d	\\x0000000000000061	10	0	payto://x-taler-bank/bank.test.taler.net/61	account-1	1564532057000000
327	\\x8d40f84bf39a8ca60e00d36825f2b156afaad70dff784f434ddfdb48682d53b6	\\x000000000000005f	10	0	payto://x-taler-bank/bank.test.taler.net/60	account-1	1564532047000000
328	\\x5604e4942174f8ead3e75d576e38c5264e65757cc2a07c4e8ac1bf4da6b95b14	\\x000000000000005d	10	0	payto://x-taler-bank/bank.test.taler.net/59	account-1	1564531757000000
329	\\x39a22bfce8e62bb9bf56113cc0272dc3c776cac1efa3c307d0fb84671d805d76	\\x000000000000005b	10	0	payto://x-taler-bank/bank.test.taler.net/58	account-1	1564531733000000
330	\\xde8480cf26f349a625f9fcd83aa6498570479fad5c1193f9dda3f1ad683239db	\\x0000000000000059	10	0	payto://x-taler-bank/bank.test.taler.net/57	account-1	1564531462000000
331	\\xb452f9eca6986c08f8c23a978e0f0be057a8ac79005640f87a993e16b95764fa	\\x0000000000000057	10	0	payto://x-taler-bank/bank.test.taler.net/56	account-1	1564530216000000
332	\\x9f049ed6dbb886f85e6b62c86a9ce709d0d2de3abb8f6578d50233f88bc7f93d	\\x0000000000000055	10	0	payto://x-taler-bank/bank.test.taler.net/55	account-1	1564530055000000
333	\\x4e7946826a660b06b17634fc4ead6f9ce8ca563ba56eb8e9569cbcec1a279ce8	\\x0000000000000053	10	0	payto://x-taler-bank/bank.test.taler.net/54	account-1	1564529464000000
334	\\xf1c097c68600d04fd93be5c44fe7c67ee577d2c372eb981bf1889e669c1ee203	\\x0000000000000051	10	0	payto://x-taler-bank/bank.test.taler.net/53	account-1	1564529328000000
335	\\xee80e518448d549e9319687310248ea6a8885dfa94ba0f78bf62a12c84825e9e	\\x000000000000004f	10	0	payto://x-taler-bank/bank.test.taler.net/52	account-1	1564529220000000
336	\\x420480d63995c7c69bded84145ce20c13743f51cb83296d0b38713d4c3307dac	\\x000000000000004d	10	0	payto://x-taler-bank/bank.test.taler.net/51	account-1	1564527969000000
337	\\x16dcd603b509d4829fc4f2c6ed34a7fc5d20be15dcd3c50248f97e609eedf3b1	\\x000000000000004b	10	0	payto://x-taler-bank/bank.test.taler.net/50	account-1	1564527961000000
338	\\xc3109d60cc5a3adf527ad26fd6cb17223bcddf138cedd775ff8174a6b0d4d57f	\\x0000000000000049	10	0	payto://x-taler-bank/bank.test.taler.net/49	account-1	1564526700000000
339	\\x285c1be3eddd195f60d19a0d35e7d9ac677db3414e3dbeb45a744740bf2ceade	\\x0000000000000047	10	0	payto://x-taler-bank/bank.test.taler.net/48	account-1	1564526599000000
340	\\x38ab0a9f30c7bc5c524a634bd65ffa7d34fc8f1086531d20e69d055f5f6117c5	\\x0000000000000045	10	0	payto://x-taler-bank/bank.test.taler.net/47	account-1	1564519935000000
341	\\x6ce4ed71b0493afa505c82bce3cf35fbb9ab1fbedd739d56de8fd0aeef256086	\\x0000000000000043	10	0	payto://x-taler-bank/bank.test.taler.net/46	account-1	1564519865000000
342	\\xabf0b85b85cf80b41e0b39ab792ae7581b9855bfcf5e28d2a9a367476a84f754	\\x0000000000000041	10	0	payto://x-taler-bank/bank.test.taler.net/45	account-1	1564519732000000
343	\\x5022184bf2d4433c31601ce1cbd91210cf746a47ea5e2986ccaafa8f44c73cb2	\\x000000000000003f	10	0	payto://x-taler-bank/bank.test.taler.net/44	account-1	1564391061000000
344	\\x9a0403092f3d26c4f6e972e7790340048a3cd685cde9ea78564d8764434cdf9c	\\x000000000000003d	10	0	payto://x-taler-bank/bank.test.taler.net/43	account-1	1564390909000000
345	\\xcc142afa684afbda15d34a034120d2e432ff922155baa4fe9c0ee650d0ff46cb	\\x000000000000003b	10	0	payto://x-taler-bank/bank.test.taler.net/42	account-1	1564390248000000
346	\\xfc81c49fd4757e5ec657c9a2def34982bcbb006e9fe97021c0abeaf1734ec94a	\\x0000000000000039	10	0	payto://x-taler-bank/bank.test.taler.net/41	account-1	1564390176000000
347	\\x897ae32910f7abed434f0610dd49237b33e444d0f8bd249430ca3dc95a10a2af	\\x0000000000000037	10	0	payto://x-taler-bank/bank.test.taler.net/40	account-1	1564388301000000
348	\\xcc86e634723b519276a556ad6ad6b60f380f21b02032c0740ded5e35603bc478	\\x0000000000000035	10	0	payto://x-taler-bank/bank.test.taler.net/39	account-1	1564387672000000
349	\\x90daeab4cbd5cb952510b3d199f3a0fefa8d45f77902390505db05bcfed8bf99	\\x0000000000000033	10	0	payto://x-taler-bank/bank.test.taler.net/38	account-1	1564387544000000
350	\\xcd23da780b5f93611ac993fc63575d2bafacd46d2ca7a9397316ba08b70fcbb6	\\x0000000000000031	10	0	payto://x-taler-bank/bank.test.taler.net/37	account-1	1564387504000000
351	\\x2155645ea096b73957f56c776e2e785db994dcec138fc4be4c41344322197551	\\x000000000000002f	10	0	payto://x-taler-bank/bank.test.taler.net/36	account-1	1564345616000000
352	\\x7bcf85a0af25010d0df96e5826302329f4a0dba7056f7390c14e240916320a55	\\x000000000000002d	10	0	payto://x-taler-bank/bank.test.taler.net/35	account-1	1564345478000000
353	\\x09c2c3d8d54d9183221a1afdee2873370eb17cb7ae6bbe259d1770a05082ec04	\\x000000000000002b	10	0	payto://x-taler-bank/bank.test.taler.net/34	account-1	1564345270000000
354	\\x19d245eda964fadc2d68c0c1d05ee8ab761212dec72a0e151f670e9028cdf0b4	\\x0000000000000029	10	0	payto://x-taler-bank/bank.test.taler.net/33	account-1	1564345083000000
355	\\xc2caebf149e241165f50e4b82c51e322f5bef5fd0c12dcf41f4ab597cf2d0919	\\x0000000000000027	10	0	payto://x-taler-bank/bank.test.taler.net/32	account-1	1564343996000000
356	\\xb53d31ec78090b17be2ea17aedb42bf74a985215946d0674fa06c7c326fcaefe	\\x0000000000000025	10	0	payto://x-taler-bank/bank.test.taler.net/31	account-1	1564343985000000
357	\\xdfcf3f95ec6a159fd971b8afc5203432523d38ca3fac1bd0dc11cee7c67d186b	\\x0000000000000023	10	0	payto://x-taler-bank/bank.test.taler.net/30	account-1	1564178356000000
358	\\x3049fdf6ffd673a6711558e0b2cd34e53dbd3d0150407f12c896dd17056f80a9	\\x0000000000000021	10	0	payto://x-taler-bank/bank.test.taler.net/29	account-1	1564177274000000
359	\\xd8457bd02eb1f93640e440d374168378a3a26810eaf6f462e0bb48ddf5fa25b1	\\x000000000000001f	10	0	payto://x-taler-bank/bank.test.taler.net/28	account-1	1564176057000000
360	\\xac8df807cb36ef64846816ab0947cb59348b116f7cccb7fe378b486bcb06adbf	\\x000000000000001d	10	0	payto://x-taler-bank/bank.test.taler.net/27	account-1	1564175456000000
361	\\x5350dea1916bd3d4324025fa70d64fcc7ca583520e6ca4ce3ce1b56f838e8bab	\\x000000000000001b	10	0	payto://x-taler-bank/bank.test.taler.net/26	account-1	1564175435000000
362	\\x661e8a0a01acb4cbb4b3678b52e36cef107ecceb1bc34ae2c534a2105b6dbdba	\\x0000000000000019	10	0	payto://x-taler-bank/bank.test.taler.net/25	account-1	1564175012000000
363	\\x1eea5a98a6944c6daa73ff98448f602b64f5a6008af7d5ec04e0948cd12521fd	\\x0000000000000017	10	0	payto://x-taler-bank/bank.test.taler.net/24	account-1	1564173924000000
364	\\x9a76b3e571ceb844d248de54ef2edcc829a8e166da4cd0f4ee0ce1606fc49d67	\\x0000000000000015	10	0	payto://x-taler-bank/bank.test.taler.net/23	account-1	1564173802000000
365	\\x4b640f53f10a01dba1998894b439df71831eff0fdaa4bf1e149a7399a879dfa7	\\x0000000000000013	10	0	payto://x-taler-bank/bank.test.taler.net/22	account-1	1564173684000000
366	\\x18e56584f16f9f023708933014b179e9b810231b40217ecc257216ca139d6510	\\x0000000000000011	10	0	payto://x-taler-bank/bank.test.taler.net/21	account-1	1564173675000000
367	\\x2d85cac3344b67052aeaaaeac0312e3bf3814781ae182d7b11e0fa6d7c301021	\\x000000000000000f	10	0	payto://x-taler-bank/bank.test.taler.net/20	account-1	1564173636000000
368	\\xbe6c6cf37b37e4ac11f5efefffa16111e32ce79981d192ada976a329a30fda7e	\\x000000000000000d	10	0	payto://x-taler-bank/bank.test.taler.net/19	account-1	1564173511000000
736	\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	\\x0000000000000354	10	0	payto://x-taler-bank/bank.test.taler.net/396	account-1	1566476615000000
\.


--
-- Data for Name: reserves_out; Type: TABLE DATA; Schema: public; Owner: grothoff
--

COPY public.reserves_out (reserve_out_serial_id, h_blind_ev, denom_pub_hash, denom_sig, reserve_pub, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x90e8850161557f7f2b55e7729ba35e512dd0f8ca83b8b3793fd4d1d4ffcf69ac67533697ebc8efca35a48b24cc77f333e9f726bf3b59c41ab38eda4fde8b7b35	\\xc24416461566d94cd49df05cc2d9736c43707f8c0c94e2483e777092963726e5c91454b1100181e9408272a2ba57c8f161d095cfc82ade12326e353dc2ebc634	\\x287369672d76616c200a2028727361200a2020287320233439343131393234324231333635433738453841413945363746444330363945363545364632393435413539314530363438373742364539393032423339413438394437374236313334324432433345383639394236374133353332453537313742324646323438374436344343393246424232333733334343353136343446363036383331383033434335354430304333444443423133323937314144424336444230433831434632353141463646443636333736454235363034354532434137393232324635463038364338413136303433384534303534414131374636304239463934463339444437303534363441444635434337303543463831364223290a2020290a20290a	\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	\\xd91c549139798e23d8486d555753d8c5b52b7d69e84b4684dc3285af5791b3db08787835c5555703e6f4c05379aa705dfb90949f953531ee83f08ac9dad6aa0b	1566476617000000	8	0
2	\\xfea922e8f01814bee05be96d059b96ea98dd698eca6df5eff0c8f453f4625fc5c9015e141cf0cbc7bc83ad5910d0e900a5c536e75d01d8619f8ccb41151bf8d4	\\x6fd4ecd17fe628bf6eeb987f60d1ad5b503637ada12f271855ca25e95e8a395f2d7b25fa6cf4a5bf725d5e82917b4b81729231100cb72ea16ccd653862bfa0f4	\\x287369672d76616c200a2028727361200a2020287320233044303332313331323838464345343231354238313432333030443144354346343644333944313541363930323537454546313443353934304430423830354243353738424441323531313031373145423237424345313631463431353041303841334642433137363245364331383545424538393830423932413533313331353845304139384144414332433945324334464544354338413233373034374638423344323634304541314542343945433034413934354543364234394430344644304334394332423938363630423336383446414341364132413537393335383739423739464538363135354336343543364236383432304534363836313723290a2020290a20290a	\\xa37ddde0e4477e1345a42dbe9aa3927d3ea4083d7de85a4f4f7bb118e00ddb60	\\x611539d3591fcc5f48a1645387b61c8f08c8c8d7126e74ae6ef3ad62d3aa8b0ae029cd8f261a30e544a7e4fb4b37071995db1b0809fd33c88c373ff64bde550b	1566476617000000	2	0
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

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 2, true);


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

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1103, true);


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

