/*
  This file is part of TALER
  Copyright (C) 2020, 2021 Taler Systems SA

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
 * @file util/crypto_helper_esign.c
 * @brief utility functions for running out-of-process private key operations
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler-exchange-secmod-eddsa.h"
#include <poll.h>
#include "crypto_helper_common.h"


struct TALER_CRYPTO_ExchangeSignHelper
{
  /**
   * Function to call with updates to available key material.
   */
  TALER_CRYPTO_ExchangeKeyStatusCallback ekc;

  /**
   * Closure for @e ekc
   */
  void *ekc_cls;

  /**
   * Socket address of the denomination helper process.
   * Used to reconnect if the connection breaks.
   */
  struct sockaddr_un sa;

  /**
   * The UNIX domain socket, -1 if we are currently not connected.
   */
  int sock;

  /**
   * Have we reached the sync'ed state?
   */
  bool synced;

};


/**
 * Disconnect from the helper process.  Updates
 * @e sock field in @a esh.
 *
 * @param[in,out] esh handle to tear down connection of
 */
static void
do_disconnect (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  GNUNET_break (0 == close (esh->sock));
  esh->sock = -1;
  esh->synced = false;
}


/**
 * Try to connect to the helper process.  Updates
 * @e sock field in @a esh.
 *
 * @param[in,out] esh handle to establish connection for
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
try_connect (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  if (-1 != esh->sock)
    return GNUNET_OK;
  esh->sock = socket (AF_UNIX,
                      SOCK_STREAM,
                      0);
  if (-1 == esh->sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "socket");
    return GNUNET_SYSERR;
  }
  if (0 !=
      connect (esh->sock,
               (const struct sockaddr *) &esh->sa,
               sizeof (esh->sa)))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "connect",
                              esh->sa.sun_path);
    do_disconnect (esh);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct TALER_CRYPTO_ExchangeSignHelper *
TALER_CRYPTO_helper_esign_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *section,
  TALER_CRYPTO_ExchangeKeyStatusCallback ekc,
  void *ekc_cls)
{
  struct TALER_CRYPTO_ExchangeSignHelper *esh;
  char *unixpath;
  char *secname;

  GNUNET_asprintf (&secname,
                   "%s-secmod-eddsa",
                   section);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               secname,
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "UNIXPATH");
    GNUNET_free (secname);
    return NULL;
  }
  /* we use >= here because we want the sun_path to always
     be 0-terminated */
  if (strlen (unixpath) >= sizeof (esh->sa.sun_path))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "UNIXPATH",
                               "path too long");
    GNUNET_free (unixpath);
    GNUNET_free (secname);
    return NULL;
  }
  GNUNET_free (secname);
  esh = GNUNET_new (struct TALER_CRYPTO_ExchangeSignHelper);
  esh->ekc = ekc;
  esh->ekc_cls = ekc_cls;
  esh->sa.sun_family = AF_UNIX;
  strncpy (esh->sa.sun_path,
           unixpath,
           sizeof (esh->sa.sun_path) - 1);
  GNUNET_free (unixpath);
  esh->sock = -1;
  if (GNUNET_OK !=
      try_connect (esh))
  {
    TALER_CRYPTO_helper_esign_disconnect (esh);
    return NULL;
  }

  TALER_CRYPTO_helper_esign_poll (esh);
  return esh;
}


/**
 * Handle a #TALER_HELPER_EDDSA_MT_AVAIL message from the helper.
 *
 * @param esh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_mt_avail (struct TALER_CRYPTO_ExchangeSignHelper *esh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_EddsaKeyAvailableNotification *kan
    = (const struct TALER_CRYPTO_EddsaKeyAvailableNotification *) hdr;

  if (sizeof (*kan) != ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_secmod_eddsa_verify (
        &kan->exchange_pub,
        GNUNET_TIME_timestamp_ntoh (kan->anchor_time),
        GNUNET_TIME_relative_ntoh (kan->duration),
        &kan->secm_pub,
        &kan->secm_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  esh->ekc (esh->ekc_cls,
            GNUNET_TIME_timestamp_ntoh (kan->anchor_time),
            GNUNET_TIME_relative_ntoh (kan->duration),
            &kan->exchange_pub,
            &kan->secm_pub,
            &kan->secm_sig);
  return GNUNET_OK;
}


/**
 * Handle a #TALER_HELPER_EDDSA_MT_PURGE message from the helper.
 *
 * @param esh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_mt_purge (struct TALER_CRYPTO_ExchangeSignHelper *esh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_EddsaKeyPurgeNotification *pn
    = (const struct TALER_CRYPTO_EddsaKeyPurgeNotification *) hdr;

  if (sizeof (*pn) != ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  esh->ekc (esh->ekc_cls,
            GNUNET_TIME_UNIT_ZERO_TS,
            GNUNET_TIME_UNIT_ZERO,
            &pn->exchange_pub,
            NULL,
            NULL);
  return GNUNET_OK;
}


void
TALER_CRYPTO_helper_esign_poll (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  char buf[UINT16_MAX];
  size_t off = 0;
  unsigned int retry_limit = 3;
  const struct GNUNET_MessageHeader *hdr
    = (const struct GNUNET_MessageHeader *) buf;

  if (GNUNET_OK !=
      try_connect (esh))
    return; /* give up */
  while (1)
  {
    uint16_t msize;
    ssize_t ret;

    ret = recv (esh->sock,
                buf + off,
                sizeof (buf) - off,
                (esh->synced && (0 == off))
                ? MSG_DONTWAIT
                : 0);
    if (ret < 0)
    {
      if (EINTR == errno)
        continue;
      if (EAGAIN == errno)
      {
        GNUNET_assert (esh->synced);
        GNUNET_assert (0 == off);
        break;
      }
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (esh);
      if (0 == retry_limit)
        return; /* give up */
      if (GNUNET_OK !=
          try_connect (esh))
        return; /* give up */
      retry_limit--;
      continue;
    }
    if (0 == ret)
    {
      GNUNET_break (0 == off);
      return;
    }
    off += ret;
more:
    if (off < sizeof (struct GNUNET_MessageHeader))
      continue;
    msize = ntohs (hdr->size);
    if (off < msize)
      continue;
    switch (ntohs (hdr->type))
    {
    case TALER_HELPER_EDDSA_MT_AVAIL:
      if (GNUNET_OK !=
          handle_mt_avail (esh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (esh);
        return;
      }
      break;
    case TALER_HELPER_EDDSA_MT_PURGE:
      if (GNUNET_OK !=
          handle_mt_purge (esh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (esh);
        return;
      }
      break;
    case TALER_HELPER_EDDSA_SYNCED:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Now synchronized with EdDSA helper\n");
      esh->synced = true;
      break;
    default:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Received unexpected message of type %d (len: %u)\n",
                  (unsigned int) ntohs (hdr->type),
                  (unsigned int) msize);
      GNUNET_break_op (0);
      do_disconnect (esh);
      return;
    }
    memmove (buf,
             &buf[msize],
             off - msize);
    off -= msize;
    goto more;
  }
}


enum TALER_ErrorCode
TALER_CRYPTO_helper_esign_sign_ (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_ExchangeSignatureP *exchange_sig)
{
  uint32_t purpose_size = ntohl (purpose->size);

  if (GNUNET_OK !=
      try_connect (esh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to helper\n");
    return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
  }
  GNUNET_assert (purpose_size <
                 UINT16_MAX - sizeof (struct TALER_CRYPTO_EddsaSignRequest));
  {
    char buf[sizeof (struct TALER_CRYPTO_EddsaSignRequest) + purpose_size
             - sizeof (struct GNUNET_CRYPTO_EccSignaturePurpose)];
    struct TALER_CRYPTO_EddsaSignRequest *sr
      = (struct TALER_CRYPTO_EddsaSignRequest *) buf;

    sr->header.size = htons (sizeof (buf));
    sr->header.type = htons (TALER_HELPER_EDDSA_MT_REQ_SIGN);
    sr->reserved = htonl (0);
    GNUNET_memcpy (&sr->purpose,
                   purpose,
                   purpose_size);
    if (GNUNET_OK !=
        TALER_crypto_helper_send_all (esh->sock,
                                      buf,
                                      sizeof (buf)))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "send",
                                esh->sa.sun_path);
      do_disconnect (esh);
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
    }
  }

  {
    char buf[UINT16_MAX];
    size_t off = 0;
    const struct GNUNET_MessageHeader *hdr
      = (const struct GNUNET_MessageHeader *) buf;
    bool finished = false;
    enum TALER_ErrorCode ec = TALER_EC_INVALID;

    while (1)
    {
      ssize_t ret;
      uint16_t msize;

      ret = recv (esh->sock,
                  &buf[off],
                  sizeof (buf) - off,
                  (finished && (0 == off))
                  ? MSG_DONTWAIT
                  : 0);
      if (ret < 0)
      {
        if (EINTR == errno)
          continue;
        if (EAGAIN == errno)
        {
          GNUNET_assert (finished);
          GNUNET_assert (0 == off);
          break;
        }
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "recv");
        do_disconnect (esh);
        return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
      }
      if (0 == ret)
      {
        GNUNET_break (0 == off);
        if (finished)
          return TALER_EC_NONE;
        return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
      }
      off += ret;
more:
      if (off < sizeof (struct GNUNET_MessageHeader))
        continue;
      msize = ntohs (hdr->size);
      if (off < msize)
        continue;
      switch (ntohs (hdr->type))
      {
      case TALER_HELPER_EDDSA_MT_RES_SIGNATURE:
        if (msize != sizeof (struct TALER_CRYPTO_EddsaSignResponse))
        {
          GNUNET_break_op (0);
          do_disconnect (esh);
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        }
        if (finished)
        {
          GNUNET_break_op (0);
          do_disconnect (esh);
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        }
        {
          const struct TALER_CRYPTO_EddsaSignResponse *sr =
            (const struct TALER_CRYPTO_EddsaSignResponse *) buf;
          *exchange_sig = sr->exchange_sig;
          *exchange_pub = sr->exchange_pub;
          finished = true;
          ec = TALER_EC_NONE;
          break;
        }
      case TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE:
        if (msize != sizeof (struct TALER_CRYPTO_EddsaSignFailure))
        {
          GNUNET_break_op (0);
          do_disconnect (esh);
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        }
        {
          const struct TALER_CRYPTO_EddsaSignFailure *sf =
            (const struct TALER_CRYPTO_EddsaSignFailure *) buf;

          finished = true;
          ec = (enum TALER_ErrorCode) ntohl (sf->ec);
          break;
        }
      case TALER_HELPER_EDDSA_MT_AVAIL:
        if (GNUNET_OK !=
            handle_mt_avail (esh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (esh);
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        }
        break; /* while(1) loop ensures we recv() again */
      case TALER_HELPER_EDDSA_MT_PURGE:
        if (GNUNET_OK !=
            handle_mt_purge (esh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (esh);
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        }
        break; /* while(1) loop ensures we recv() again */
      case TALER_HELPER_EDDSA_SYNCED:
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Synchronized add odd time with EdDSA helper!\n");
        esh->synced = true;
        break;
      default:
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Received unexpected message of type %u\n",
                    ntohs (hdr->type));
        do_disconnect (esh);
        return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
      }
      memmove (buf,
               &buf[msize],
               off - msize);
      off -= msize;
      goto more;
    } /* while(1) */
    return ec;
  }
}


void
TALER_CRYPTO_helper_esign_revoke (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  if (GNUNET_OK !=
      try_connect (esh))
    return; /* give up */
  {
    struct TALER_CRYPTO_EddsaRevokeRequest rr = {
      .header.size = htons (sizeof (rr)),
      .header.type = htons (TALER_HELPER_EDDSA_MT_REQ_REVOKE),
      .exchange_pub = *exchange_pub
    };

    if (GNUNET_OK !=
        TALER_crypto_helper_send_all (esh->sock,
                                      &rr,
                                      sizeof (rr)))
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "send");
      do_disconnect (esh);
      return;
    }
  }
}


void
TALER_CRYPTO_helper_esign_disconnect (
  struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  if (-1 != esh->sock)
    do_disconnect (esh);
  GNUNET_free (esh);
}


/* end of crypto_helper_esign.c */
