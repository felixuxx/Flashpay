/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_common.h
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#ifndef EXCHANGE_API_COMMON_H
#define EXCHANGE_API_COMMON_H

#include "taler_json_lib.h"


/**
 * Check proof of a purse creation conflict.
 *
 * @param cpurse_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param purse_pub the public key (must match
 *        the signature from the proof)
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and conflicts with @a purse_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_create_conflict_ (
  const struct TALER_PurseContractSignatureP *cpurse_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof);


/**
 * Check proof of a purse merge conflict.
 *
 * @param cmerge_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param merge_pub the public key (must match
 *        the signature from the proof)
 * @param exchange_url the base URL of this exchange
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and conflicts with @a purse_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_merge_conflict_ (
  const struct TALER_PurseMergeSignatureP *cmerge_sig,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof);


/**
 * Check proof of a contract conflict.
 *
 * DESIGN-FIXME: this 'proof' doesn't really proof a conflict!
 *
 * @param ccontract_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param purse_pub public key of the purse
 * @param exchange_url the base URL of this exchange
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and conflicts with @a purse_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_econtract_conflict_ (
  const struct TALER_PurseContractSignatureP *ccontract_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof);


#endif
