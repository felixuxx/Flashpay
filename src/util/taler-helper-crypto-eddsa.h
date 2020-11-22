/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file util/taler-helper-crypto-eddsa.h
 * @brief IPC messages for the EDDSA crypto helper.
 * @author Christian Grothoff
 */
#ifndef TALER_HELPER_CRYPTO_EDDSA_H
#define TALER_HELPER_CRYPTO_EDDSA_H

#define TALER_HELPER_EDDSA_MT_PURGE 11
#define TALER_HELPER_EDDSA_MT_AVAIL 12

#define TALER_HELPER_EDDSA_MT_REQ_INIT 14
#define TALER_HELPER_EDDSA_MT_REQ_SIGN 15
#define TALER_HELPER_EDDSA_MT_REQ_REVOKE 16

#define TALER_HELPER_EDDSA_MT_RES_SIGNATURE 17
#define TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE 18

GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message sent if a key is available.
 */
struct TALER_CRYPTO_EddsaKeyAvailableNotification
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_AVAIL
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * When does the key become available?
   */
  struct GNUNET_TIME_AbsoluteNBO anchor_time;

  /**
   * How long is the key available after @e anchor_time?
   */
  struct GNUNET_TIME_RelativeNBO duration;

  /**
   * The public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

};


/**
 * Message sent if a key was purged.
 */
struct TALER_CRYPTO_EddsaKeyPurgeNotification
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_PURGE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * The public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

};


/**
 * Message sent if a signature is requested.
 */
struct TALER_CRYPTO_SignRequest
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_REQ_SIGN.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * What should be signed over.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /* followed by rest of data to sign */
};


/**
 * Message sent if a key was revoked.
 */
struct TALER_CRYPTO_RevokeRequest
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_REQ_REVOKE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * The public key to revoke.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

};


/**
 * Message sent if a signature was successfully computed.
 */
struct TALER_CRYPTO_SignResponse
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_RES_SIGNATURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * The public key used for the signature.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * The public key to use for the signature.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

};


/**
 * Message sent if signing failed.
 */
struct TALER_CRYPTO_SignFailure
{
  /**
   * Type is #TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * If available, Taler error code. In NBO.
   */
  uint32_t ec;

};


GNUNET_NETWORK_STRUCT_END


#endif
