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
 * @file util/taler-exchange-secmod-rsa.h
 * @brief IPC messages for the RSA crypto helper.
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_SECMOD_RSA_H
#define TALER_EXCHANGE_SECMOD_RSA_H

#define TALER_HELPER_RSA_MT_PURGE 1
#define TALER_HELPER_RSA_MT_AVAIL 2

#define TALER_HELPER_RSA_MT_REQ_INIT 4
#define TALER_HELPER_RSA_MT_REQ_SIGN 5
#define TALER_HELPER_RSA_MT_REQ_REVOKE 6

#define TALER_HELPER_RSA_MT_RES_SIGNATURE 7
#define TALER_HELPER_RSA_MT_RES_SIGN_FAILURE 8

#define TALER_HELPER_RSA_SYNCED 9

GNUNET_NETWORK_STRUCT_BEGIN


/**
 * Message sent if a key is available.
 */
struct TALER_CRYPTO_RsaKeyAvailableNotification
{
  /**
   * Type is #TALER_HELPER_RSA_MT_AVAIL
   */
  struct GNUNET_MessageHeader header;

  /**
   * Number of bytes of the public key.
   */
  uint16_t pub_size;

  /**
   * Number of bytes of the section name.
   */
  uint16_t section_name_len;

  /**
   * When does the key become available?
   */
  struct GNUNET_TIME_TimestampNBO anchor_time;

  /**
   * How long is the key available after @e anchor_time?
   */
  struct GNUNET_TIME_RelativeNBO duration_withdraw;

  /**
   * Public key used to generate the @e sicm_sig.
   */
  struct TALER_SecurityModulePublicKeyP secm_pub;

  /**
   * Signature affirming the announcement, of
   * purpose #TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY.
   */
  struct TALER_SecurityModuleSignatureP secm_sig;

  /* followed by @e pub_size bytes of the RSA public key */

  /* followed by @e section_name bytes of the configuration section name
     of the denomination of this key */

};


/**
 * Message sent if a key was purged.
 */
struct TALER_CRYPTO_RsaKeyPurgeNotification
{
  /**
   * Type is #TALER_HELPER_RSA_MT_PURGE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Hash of the public key of the purged RSA key.
   */
  struct TALER_RsaPubHashP h_rsa;

};


/**
 * Message sent if a signature is requested.
 */
struct TALER_CRYPTO_SignRequest
{
  /**
   * Type is #TALER_HELPER_RSA_MT_REQ_SIGN.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Hash of the public key of the RSA key to use for the signature.
   */
  struct TALER_RsaPubHashP h_rsa;

  /* followed by message to sign */
};


/**
 * Message sent if a key was revoked.
 */
struct TALER_CRYPTO_RevokeRequest
{
  /**
   * Type is #TALER_HELPER_RSA_MT_REQ_REVOKE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Hash of the public key of the revoked RSA key.
   */
  struct TALER_RsaPubHashP h_rsa;

};


/**
 * Message sent if a signature was successfully computed.
 */
struct TALER_CRYPTO_SignResponse
{
  /**
   * Type is #TALER_HELPER_RSA_MT_RES_SIGNATURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /* followed by RSA signature */
};


/**
 * Message sent if signing failed.
 */
struct TALER_CRYPTO_SignFailure
{
  /**
   * Type is #TALER_HELPER_RSA_MT_RES_SIGN_FAILURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * If available, Taler error code. In NBO.
   */
  uint32_t ec;

};


GNUNET_NETWORK_STRUCT_END


#endif
