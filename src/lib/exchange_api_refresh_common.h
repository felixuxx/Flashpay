/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
 * @file lib/exchange_api_refresh.c
 * @brief Implementation of the /refresh/melt+reveal requests of the exchange's HTTP API
 * @author Christian Grothoff
 */
#ifndef REFRESH_COMMON_H
#define REFRESH_COMMON_H
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "taler_signatures.h"


/* structures for committing refresh data to disk before doing the
   network interaction(s) */

GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Header of serialized information about a coin we are melting.
 */
struct MeltedCoinP
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Amount this coin contributes to the melt, including fee.
   */
  struct TALER_AmountNBO melt_amount_with_fee;

  /**
   * The applicable fee for withdrawing a coin of this denomination
   */
  struct TALER_AmountNBO fee_melt;

  /**
   * The original value of the coin.
   */
  struct TALER_AmountNBO original_value;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_deposit;

  /**
   * Size of the encoded public key that follows.
   */
  uint16_t pbuf_size;

  /**
   * Size of the encoded signature that follows.
   */
  uint16_t sbuf_size;

  /* Followed by serializations of:
     1) struct TALER_DenominationPublicKey pub_key;
     2) struct TALER_DenominationSignature sig;
  */
};


/**
 * Header of serialized data about a melt operation, suitable for
 * persisting it on disk.
 */
struct MeltDataP
{

  /**
   * Hash over the melting session.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * Number of coins we are melting, in NBO
   */
  uint16_t num_melted_coins GNUNET_PACKED;

  /**
   * Number of coins we are creating, in NBO
   */
  uint16_t num_fresh_coins GNUNET_PACKED;

  /* Followed by serializations of:
     1) struct MeltedCoinP melted_coins[num_melted_coins];
     2) struct TALER_EXCHANGE_DenomPublicKey fresh_pks[num_fresh_coins];
     3) TALER_CNC_KAPPA times:
        3a) struct TALER_PlanchetSecretsP fresh_coins[num_fresh_coins];
  */
};


GNUNET_NETWORK_STRUCT_END


/**
 * Information about a coin we are melting.
 */
struct MeltedCoin
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Amount this coin contributes to the melt, including fee.
   */
  struct TALER_Amount melt_amount_with_fee;

  /**
   * The applicable fee for melting a coin of this denomination
   */
  struct TALER_Amount fee_melt;

  /**
   * The original value of the coin.
   */
  struct TALER_Amount original_value;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Absolute expire_deposit;

  /**
   * Denomination key of the original coin.
   */
  struct TALER_DenominationPublicKey pub_key;

  /**
   * Exchange's signature over the coin.
   */
  struct TALER_DenominationSignature sig;

};


/**
 * Melt data in non-serialized format for convenient processing.
 */
struct MeltData
{

  /**
   * Hash over the committed data during refresh operation.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * Number of coins we are creating
   */
  uint16_t num_fresh_coins;

  /**
   * Information about the melted coin.
   */
  struct MeltedCoin melted_coin;

  /**
   * Array of @e num_fresh_coins denomination keys for the coins to be
   * freshly exchangeed.
   */
  struct TALER_DenominationPublicKey *fresh_pks;

  /**
   * Arrays of @e num_fresh_coins with information about the fresh
   * coins to be created, for each cut-and-choose dimension.
   */
  struct TALER_PlanchetSecretsP *fresh_coins[TALER_CNC_KAPPA];
};


/**
 * Serialize melt data.
 *
 * @param md data to serialize
 * @param[out] res_size size of buffer returned
 * @return serialized melt data
 */
char *
TALER_EXCHANGE_serialize_melt_data_ (const struct MeltData *md,
                                     size_t *res_size);


/**
 * Deserialize melt data.
 *
 * @param buf serialized data
 * @param buf_size size of @a buf
 * @return deserialized melt data, NULL on error
 */
struct MeltData *
TALER_EXCHANGE_deserialize_melt_data_ (const char *buf,
                                       size_t buf_size);


/**
 * Free all information associated with a melting session.  Note
 * that we allow the melting session to be only partially initialized,
 * as we use this function also when freeing melt data that was not
 * fully initialized (i.e. due to failures in #deserialize_melt_data()).
 *
 * @param md melting data to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
void
TALER_EXCHANGE_free_melt_data_ (struct MeltData *md);

#endif
