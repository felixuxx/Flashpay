/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint/taler-mint_httpd_db.h
 * @brief Mint-specific database access
 * @author Chrisitan Grothoff
 *
 * TODO:
 * - revisit and document `struct Deposit` members.
 */
#ifndef TALER_MINT_HTTPD_DB_H
#define TALER_MINT_HTTPD_DB_H

#include <libpq-fe.h>
#include <microhttpd.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_rsa.h"


/**
 * Specification for a /deposit operation.
 */
struct Deposit
{
  /* FIXME: should be TALER_CoinPublicInfo */
  struct GNUNET_CRYPTO_EddsaPublicKey coin_pub;

  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;

  struct TALER_RSA_Signature coin_sig;

  struct TALER_RSA_Signature ubsig;

  /**
   * Type of the deposit (also purpose of the signature).  Either
   * #TALER_SIGNATURE_DEPOSIT or #TALER_SIGNATURE_INCREMENTAL_DEPOSIT.
   */
  struct TALER_RSA_SignaturePurpose purpose;

  uint64_t transaction_id;

  struct TALER_AmountNBO amount;

  struct GNUNET_CRYPTO_EddsaPublicKey merchant_pub;

  struct GNUNET_HashCode h_contract;

  struct GNUNET_HashCode h_wire;

  /* TODO: uint16_t wire_size */
  char wire[];                  /* string encoded wire JSON object */

};


/**
 * Execute a deposit.  The validity of the coin and signature
 * have already been checked.  The database must now check that
 * the coin is not (double or over) spent, and execute the
 * transaction (record details, generate success or failure response).
 *
 * @param connection the MHD connection to handle
 * @param deposit information about the deposit
 * @return MHD result code
 */
int
TALER_MINT_db_execute_deposit (struct MHD_Connection *connection,
                               const struct Deposit *deposit);


#endif /* _NEURO_MINT_DB_H */
