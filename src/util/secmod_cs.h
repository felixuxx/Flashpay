/*
  This file is part of TALER
  Copyright (C) 2020-2022 Taler Systems SA

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
 * @file util/secmod_cs.h
 * @brief IPC messages for the CS crypto helper.
 * @author Christian Grothoff
 * @author Gian Demarmels
 * @author Lucien Heuzeveldt
 */
#ifndef TALER_EXCHANGE_SECMOD_CS_H
#define TALER_EXCHANGE_SECMOD_CS_H

#define TALER_HELPER_CS_MT_PURGE 1
#define TALER_HELPER_CS_MT_AVAIL 2

#define TALER_HELPER_CS_MT_REQ_INIT 3
#define TALER_HELPER_CS_MT_REQ_BATCH_SIGN 4
#define TALER_HELPER_CS_MT_REQ_SIGN 5
#define TALER_HELPER_CS_MT_REQ_REVOKE 6
#define TALER_HELPER_CS_MT_REQ_BATCH_RDERIVE 7
#define TALER_HELPER_CS_MT_REQ_RDERIVE 8

#define TALER_HELPER_CS_MT_RES_SIGNATURE 9
#define TALER_HELPER_CS_MT_RES_SIGN_FAILURE 10
#define TALER_HELPER_CS_MT_RES_BATCH_SIGN_FAILURE 11
#define TALER_HELPER_CS_MT_RES_RDERIVE 12
#define TALER_HELPER_CS_MT_RES_RDERIVE_FAILURE 13
#define TALER_HELPER_CS_MT_RES_BATCH_RDERIVE_FAILURE 14

#define TALER_HELPER_CS_SYNCED 15

GNUNET_NETWORK_STRUCT_BEGIN


/**
 * Message sent if a key is available.
 */
struct TALER_CRYPTO_CsKeyAvailableNotification
{
  /**
   * Type is #TALER_HELPER_CS_MT_AVAIL
   */
  struct GNUNET_MessageHeader header;

  /**
   * Number of bytes of the section name.
   */
  uint32_t section_name_len;

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
   * purpose #TALER_SIGNATURE_SM_CS_DENOMINATION_KEY.
   */
  struct TALER_SecurityModuleSignatureP secm_sig;

  /**
   * Denomination Public key
   */
  struct GNUNET_CRYPTO_CsPublicKey denom_pub;

  /* followed by @e section_name bytes of the configuration section name
     of the denomination of this key */

};


/**
 * Message sent if a key was purged.
 */
struct TALER_CRYPTO_CsKeyPurgeNotification
{
  /**
   * Type is #TALER_HELPER_CS_MT_PURGE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Hash of the public key of the purged CS key.
   */
  struct TALER_CsPubHashP h_cs;

};


/**
 * Message sent if a signature is requested.
 */
struct TALER_CRYPTO_CsSignRequestMessage
{
  /**
   * Type is #TALER_HELPER_CS_MT_REQ_SIGN.
   */
  struct GNUNET_MessageHeader header;

  /**
   * 0 for withdraw, 1 for melt, in NBO.
   */
  uint32_t for_melt;

  /**
   * Hash of the public key of the CS key to use for the signature.
   */
  struct TALER_CsPubHashP h_cs;

  /**
   * Message to sign.
   */
  struct GNUNET_CRYPTO_CsBlindedMessage message;

};


/**
 * Message sent if a batch of signatures is requested.
 */
struct TALER_CRYPTO_BatchSignRequest
{
  /**
   * Type is #TALER_HELPER_CS_MT_REQ_BATCH_SIGN.
   */
  struct GNUNET_MessageHeader header;

  /**
   * Number of signatures to create, in NBO.
   */
  uint32_t batch_size;

  /*
   * Followed by @e batch_size batch sign requests.
   */

};


/**
 * Message sent if a signature is requested.
 */
struct TALER_CRYPTO_CsRDeriveRequest
{
  /**
   * Type is #TALER_HELPER_CS_MT_REQ_RDERIVE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * 0 for withdraw, 1 for melt, in NBO.
   */
  uint32_t for_melt;

  /**
   * Hash of the public key of the CS key to use for the derivation.
   */
  struct TALER_CsPubHashP h_cs;

  /**
   * Withdraw nonce to derive R from
   */
  struct GNUNET_CRYPTO_CsSessionNonce nonce;
};


/**
 * Message sent if a batch of derivations is requested.
 */
struct TALER_CRYPTO_BatchDeriveRequest
{
  /**
   * Type is #TALER_HELPER_CS_MT_REQ_BATCH_RDERIVE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * Number of derivations to create, in NBO.
   */
  uint32_t batch_size;

  /*
   * Followed by @e batch_size derive requests.
   */

};


/**
 * Message sent if a key was revoked.
 */
struct TALER_CRYPTO_CsRevokeRequest
{
  /**
   * Type is #TALER_HELPER_CS_MT_REQ_REVOKE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Hash of the public key of the revoked CS key.
   */
  struct TALER_CsPubHashP h_cs;

};


/**
 * Message sent if a signature was successfully computed.
 */
struct TALER_CRYPTO_SignResponse
{
  /**
   * Type is #TALER_HELPER_CS_MT_RES_SIGNATURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * The chosen 'b' (0 or 1).
   */
  uint32_t b;

  /**
   * Contains the blindided s.
   */
  struct GNUNET_CRYPTO_CsBlindS cs_answer;
};

/**
 * Message sent if a R is successfully derived
 */
struct TALER_CRYPTO_RDeriveResponse
{
  /**
   * Type is #TALER_HELPER_CS_MT_RES_RDERIVE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * For now, always zero.
   */
  uint32_t reserved;

  /**
   * Pair of derived R values
   */
  struct GNUNET_CRYPTO_CSPublicRPairP r_pub;
};


/**
 * Message sent if signing failed.
 */
struct TALER_CRYPTO_SignFailure
{
  /**
   * Type is #TALER_HELPER_CS_MT_RES_SIGN_FAILURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * If available, Taler error code. In NBO.
   */
  uint32_t ec;

};

/**
 * Message sent if derivation failed.
 */
struct TALER_CRYPTO_RDeriveFailure
{
  /**
   * Type is #TALER_HELPER_CS_MT_RES_RDERIVE_FAILURE.
   */
  struct GNUNET_MessageHeader header;

  /**
   * If available, Taler error code. In NBO.
   */
  uint32_t ec;

};
GNUNET_NETWORK_STRUCT_END


#endif
