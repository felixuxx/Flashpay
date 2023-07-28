/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file pq/pq_common.h
 * @brief common defines for the pq functions
 * @author Özgür Kesim
 */
#ifndef TALER_PQ_COMMON_H_
#define TALER_PQ_COMMON_H_

#include "platform.h"
/**
 * Internal types that are supported as TALER-exchange-specific array types.
 *
 * To support a new type,
 *   1. add a new entry into this list,
 *   2. for query-support, implement the size calculation and memory copying in
 *      qconv_array() accordingly, in pq_query_helper.c
 *   3. provide a query-API for arrays of the type, by calling
 *      query_param_array_generic with the appropriate parameters,
 *      in pq_query_helper.c
 *   4. for result-support, implement memory copying by adding another case
 *      to extract_array_generic, in pq_result_helper.c
 *   5. provide a result-spec-API for arrays of the type,
 *      in pq_result_helper.c
 *   6. expose the API's in taler_pq_lib.h
 */
enum TALER_PQ_ArrayType
{
  TALER_PQ_array_of_blinded_denom_sig,
  TALER_PQ_array_of_blinded_coin_hash,
  TALER_PQ_array_of_denom_hash,
  /* TODO[oec]: Next up: TALER_PQ_array_of_amount, */
  TALER_PQ_array_of_MAX,       /* must be last */
};

/**
 * Memory representation of an taler amount record for Postgres.
 *
 * All values need to be in network-byte-order.
 */
struct TALER_PQ_Amount_P
{
  uint32_t oid_v; /* oid of .v  */
  uint32_t sz_v;  /* size of .v */
  uint64_t v;     /* value      */
  uint32_t oid_f; /* oid of .f  */
  uint32_t sz_f;  /* size of .f */
  uint32_t f;     /* fraction   */
} __attribute__((packed));

/**
 * Create a `struct TALER_PQ_Amount_P` for initialization
 *
 * @param db postgres-context of type `struct GNUNET_PQ_Context *`
 * @param amount amount of type `struct TALER_Amount *`
 */
#define MAKE_TALER_PQ_AMOUNT_P(db,amount) \
  { \
    .oid_v = htonl (GNUNET_PQ_get_oid ((db), GNUNET_PQ_DATATYPE_INT8)), \
    .oid_f = htonl (GNUNET_PQ_get_oid ((db), GNUNET_PQ_DATATYPE_INT4)), \
    .sz_v = htonl (sizeof((amount)->value)), \
    .sz_f = htonl (sizeof((amount)->fraction)), \
    .v = GNUNET_htonll ((amount)->value), \
    .f = htonl ((amount)->fraction) \
  }


#endif  /* TALER_PQ_COMMON_H_ */
/* end of pg/pq_common.h */
