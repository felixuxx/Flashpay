--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
--
-- TALER is free software; you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3, or (at your option) any later version.
--
-- TALER is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
--

--------------------------------

INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
   ,('auditors', 'exchange-0001', 'create', FALSE, FALSE)
   ,('auditor_denom_sigs', 'exchange-0001', 'create', FALSE, FALSE)
   ,('exchange_sign_keys', 'exchange-0001', 'create', FALSE, FALSE)
   ,('signkey_revocations', 'exchange-0001', 'create', FALSE, FALSE)
   ,('extensions', 'exchange-0001', 'create', FALSE, FALSE)
   ,('wire_fee', 'exchange-0001', 'create', FALSE, FALSE)
   ,('global_fee', 'exchange-0001', 'create', FALSE, FALSE)
   ,('wire_accounts', 'exchange-0001', 'create', FALSE, FALSE)
   ,('work_shards', 'exchange-0001', 'create', FALSE, FALSE)
   ,('revolving_work_shards', 'exchange-0001', 'create', FALSE, FALSE)
   ,('partners', 'exchange-0001', 'create', FALSE, FALSE)
   ,('partner_accounts', 'exchange-0001', 'create', FALSE, FALSE)
   ,('purse_actions', 'exchange-0001', 'create', FALSE, FALSE)
   ,('policy_fulfillments', 'exchange-0001', 'create', FALSE, FALSE) -- bad!
   ,('policy_details', 'exchange-0001', 'create', FALSE, FALSE) -- bad!
   ,('wire_targets''exchange-0001', 'create', TRUE, FALSE)
   ,('legitimization_processes', 'exchange-0001', 'create', TRUE, FALSE)
   ,('legitimization_requirements', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_in', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_close', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_open_requests', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_open_deposits', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_out', 'exchange-0001', 'create', TRUE, FALSE)
   ,('reserves_out_by_reserve', 'exchange-0001', 'create', TRUE, FALSE)
   ,('known_coins', 'exchange-0001', 'create', TRUE, FALSE)
   ,('refresh_commitments', 'exchange-0001', 'create', TRUE, FALSE)
   ,('refresh_revealed_coins', 'exchange-0001', 'create', TRUE, FALSE)
   ,('refresh_transfer_keys', 'exchange-0001', 'create', TRUE, FALSE)
   ,('refunds', 'exchange-0001', 'create', TRUE, FALSE)
   ,('deposits', 'exchange-0001', 'create', TRUE, FALSE)
   ,('deposits_by_ready', 'exchange-0001', 'create', TRUE, TRUE)
   ,('deposits_for_matching', 'exchange-0001', 'create', TRUE, TRUE)
   ,('wire_out', 'exchange-0001', 'create', TRUE, FALSE)
   ,('aggregation_transient', 'exchange-0001', 'create', TRUE, FALSE)
   ,('aggregation_tracking', 'exchange-0001', 'create', TRUE, FALSE)
   ,('recoup', 'exchange-0001', 'create', TRUE, FALSE)
   ,('recoup_by_reserve', 'exchange-0001', 'create', TRUE, FALSE)
   ,('recoup_refresh', 'exchange-0001', 'create', TRUE, FALSE)
   ,('prewire', 'exchange-0001', 'create', TRUE, FALSE)
   ,('cs_nonce_locks', 'exchange-0001', 'create', TRUE, FALSE)
   ,('purse_requests', 'exchange-0001', 'create', TRUE, FALSE)
   ,('purse_decision', 'exchange-0001', 'create', TRUE, FALSE)
   ,('purse_merges', 'exchange-0001', 'create', TRUE, FALSE)
   ,('account_merges', 'exchange-0001', 'create', TRUE, FALSE)
   ,('contracts', 'exchange-0001', 'create', TRUE, FALSE)
   ,('history_requests', 'exchange-0001', 'create', TRUE, FALSE)
   ,('close_requests', 'exchange-0001', 'create', TRUE, FALSE)
   ,('purse_deposists', 'exchange-0001', 'create', TRUE, FALSE)
   ,('wads_out', 'exchange-0001', 'create', TRUE, FALSE)
   ,('wads_out_entries', 'exchange-0001', 'create', TRUE, FALSE)
   ,('wads_in', 'exchange-0001', 'create', TRUE, FALSE)
   ,('wads_in_entries', 'exchange-0001', 'create', TRUE, FALSE)
 ON CONFLICT DO NOTHING;



-------------------- Tables ----------------------------
