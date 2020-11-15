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
 * @file util/taler-helper-crypto-rsa.h
 * @brief IPC messages for the RSA crypto helper.
 * @author Christian Grothoff
 */
#ifndef TALER_HELPER_CRYPTO_RSA_H
#define TALER_HELPER_CRYPTO_RSA_H

#define TALER_HELPER_RSA_MT_PURGE 1
#define TALER_HELPER_RSA_MT_AVAIL 2

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
  struct GNUNET_TIME_AbsoluteNBO anchor_time;

  /**
   * How long is the key available after @e anchor_time?
   */
  struct GNUNET_TIME_RelativeNBO duration_withdraw;

  /* followed by @e pub_size bytes of the public key */

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
  struct GNUNET_HashCode h_denom_pub;

};


GNUNET_NETWORK_STRUCT_END


#endif
