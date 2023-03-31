/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file exchangedb/pg_select_contract.h
 * @brief implementation of the select_contract function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_CONTRACT_H
#define PG_SELECT_CONTRACT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to retrieve an encrypted contract.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub key to lookup the contract by
 * @param[out] pub_ckey set to the ephemeral DH used to encrypt the contract
 * @param[out] econtract_sig set to the signature over the encrypted contract
 * @param[out] econtract_size set to the number of bytes in @a econtract
 * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_contract (void *cls,
                        const struct TALER_ContractDiffiePublicP *pub_ckey,
                        struct TALER_PurseContractPublicKeyP *purse_pub,
                        struct TALER_PurseContractSignatureP *econtract_sig,
                        size_t *econtract_size,
                        void **econtract);

#endif
