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

#include "taler_util.h"

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
  TALER_PQ_array_of_hash_code,
  /**
   * Amounts *without* currency.
   */
  TALER_PQ_array_of_amount,
  TALER_PQ_array_of_MAX,       /* must be last */
};

/**
 * Memory representation of an taler amount record for Postgres.
 *
 * All values need to be in network-byte-order.
 */
struct TALER_PQ_AmountP
{
  uint32_t cnt;   /* # elements in the tuple (== 2) */
  uint32_t oid_v; /* oid of .v  */
  uint32_t sz_v;  /* size of .v */
  uint64_t v;     /* value      */
  uint32_t oid_f; /* oid of .f  */
  uint32_t sz_f;  /* size of .f */
  uint32_t f;     /* fraction   */
} __attribute__((packed));


/**
 * Memory representation of an taler amount record with currency for Postgres.
 *
 * All values need to be in network-byte-order.
 */
struct TALER_PQ_AmountCurrencyP
{
  uint32_t cnt;   /* # elements in the tuple (== 3) */
  uint32_t oid_v; /* oid of .v  */
  uint32_t sz_v;  /* size of .v */
  uint64_t v;     /* value      */
  uint32_t oid_f; /* oid of .f  */
  uint32_t sz_f;  /* size of .f */
  uint32_t f;     /* fraction   */
  uint32_t oid_c; /* oid of .c  */
  uint32_t sz_c;  /* size of .c */
  uint8_t c[TALER_CURRENCY_LEN];  /* currency */
} __attribute__((packed));


/**
 * Create a `struct TALER_PQ_AmountP` for initialization
 *
 * @param amount amount of type `struct TALER_Amount *`
 * @param oid_v OID of the INT8 type in postgres
 * @param oid_f OID of the INT4 type in postgres
 */
struct TALER_PQ_AmountP
TALER_PQ_make_taler_pq_amount_ (
  const struct TALER_Amount *amount,
  uint32_t oid_v,
  uint32_t oid_f);


/**
 * Create a `struct TALER_PQ_AmountCurrencyP` for initialization
 *
 * @param amount amount of type `struct TALER_Amount *`
 * @param oid_v OID of the INT8 type in postgres
 * @param oid_f OID of the INT4 type in postgres
 * @param oid_c OID of the TEXT type in postgres
 * @param[out] rval set to encoded @a amount
 * @return actual (useful) size of @a rval for Postgres
 */
size_t
TALER_PQ_make_taler_pq_amount_currency_ (
  const struct TALER_Amount *amount,
  uint32_t oid_v,
  uint32_t oid_f,
  uint32_t oid_c,
  struct TALER_PQ_AmountCurrencyP *rval);


#endif  /* TALER_PQ_COMMON_H_ */
/* end of pg/pq_common.h */
