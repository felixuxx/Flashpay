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
 * @file util/crypto_contract.c
 * @brief functions for encrypting and decrypting contracts for P2P payments
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"


void
TALER_CRYPTO_contract_encrypt_for_merge (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const json_t *contract_terms,
  void **econtract,

  size_t *econtract_size)
{
}


json_t *
TALER_CRYPTO_contract_decrypt_for_merge (
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const void *econtract,
  size_t econtract_size,
  struct TALER_PurseMergePrivateKeyP *merge_priv)
{
  return NULL;
}
