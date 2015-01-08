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
 * @file taler-mint-keyup.c
 * @brief Update the mint's keys for coins and signatures,
 *        using the mint's offline master key.
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#ifndef TALER_SIGNATURES_H
#define TALER_SIGNATURES_H

/**
 * Purpose for signing public keys signed
 * by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_SIGNKEY 1

/**
 * Purpose for denomination keys signed
 * by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_DENOM 2

/**
 * Purpose for the state of a reserve,
 * signed by the mint's signing key.
 */
#define TALER_SIGNATURE_RESERVE_STATUS 3

/**
 * Signature where the reserve key
 * confirms a withdraw request.
 */
#define TALER_SIGNATURE_WITHDRAW 4

/**
 * Signature where the refresh session confirms
 * the list of melted coins and requested denominations.
 */
#define TALER_SIGNATURE_REFRESH_MELT 5

/**
 * Signature where the refresh session confirms
 * the commits.
 */
#define TALER_SIGNATURE_REFRESH_COMMIT 6

/**
 * Signature where the mint (current signing key)
 * confirms the list of blind session keys.
 */
#define TALER_SIGNATURE_REFRESH_MELT_RESPONSE 7

/**
 * Signature where the mint (current signing key)
 * confirms the no-reveal index for cut-and-choose.
 */
#define TALER_SIGNATURE_REFRESH_COMMIT_RESPONSE 8

/**
 * Signature where coins confirm that they want
 * to be melted into a certain session.
 */
#define TALER_SIGNATURE_REFRESH_MELT_CONFIRM 9

/***********************/
/* Merchant signatures */
/***********************/

/**
 * Signature where the merchant confirms a contract
 */
#define TALER_SIGNATURE_MERCHANT_CONTRACT 101

/*********************/
/* Wallet signatures */
/*********************/

/**
 * Signature made by the wallet of a user to confirm a deposit permission
 */
#define TALER_SIGNATURE_DEPOSIT 201

/**
 * Signature made by the wallet of a user to confirm a incremental deposit permission
 */
#define TALER_SIGNATURE_INCREMENTAL_DEPOSIT 202

#endif

