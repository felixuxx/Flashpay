/*
  This file is part of TALER
  Copyright (C) 2020, 2021, 2022 Taler Systems SA

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
 * @file util/crypto_helper_cs.c
 * @brief utility functions for running out-of-process private key operations
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "secmod_cs.h"
#include <poll.h>
#include "crypto_helper_common.h"


struct TALER_CRYPTO_CsDenominationHelper
{
  /**
   * Function to call with updates to available key material.
   */
  TALER_CRYPTO_CsDenominationKeyStatusCallback dkc;

  /**
   * Closure for @e dkc
   */
  void *dkc_cls;

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
   * Have we ever been sync'ed?
   */
  bool synced;
};


/**
 * Disconnect from the helper process.  Updates
 * @e sock field in @a dh.
 *
 * @param[in,out] dh handle to tear down connection of
 */
static void
do_disconnect (struct TALER_CRYPTO_CsDenominationHelper *dh)
{
  GNUNET_break (0 == close (dh->sock));
  dh->sock = -1;
  dh->synced = false;
}


/**
 * Try to connect to the helper process.  Updates
 * @e sock field in @a dh.
 *
 * @param[in,out] dh handle to establish connection for
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
try_connect (struct TALER_CRYPTO_CsDenominationHelper *dh)
{
  if (-1 != dh->sock)
    return GNUNET_OK;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Establishing connection!\n");
  dh->sock = socket (AF_UNIX,
                     SOCK_STREAM,
                     0);
  if (-1 == dh->sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "socket");
    return GNUNET_SYSERR;
  }
  if (0 !=
      connect (dh->sock,
               (const struct sockaddr *) &dh->sa,
               sizeof (dh->sa)))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "connect",
                              dh->sa.sun_path);
    do_disconnect (dh);
    return GNUNET_SYSERR;
  }
  TALER_CRYPTO_helper_cs_poll (dh);
  return GNUNET_OK;
}


struct TALER_CRYPTO_CsDenominationHelper *
TALER_CRYPTO_helper_cs_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *section,
  TALER_CRYPTO_CsDenominationKeyStatusCallback dkc,
  void *dkc_cls)
{
  struct TALER_CRYPTO_CsDenominationHelper *dh;
  char *unixpath;
  char *secname;

  GNUNET_asprintf (&secname,
                   "%s-secmod-cs",
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
  if (strlen (unixpath) >= sizeof (dh->sa.sun_path))
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
  dh = GNUNET_new (struct TALER_CRYPTO_CsDenominationHelper);
  dh->dkc = dkc;
  dh->dkc_cls = dkc_cls;
  dh->sa.sun_family = AF_UNIX;
  strncpy (dh->sa.sun_path,
           unixpath,
           sizeof (dh->sa.sun_path) - 1);
  GNUNET_free (unixpath);
  dh->sock = -1;
  if (GNUNET_OK !=
      try_connect (dh))
  {
    TALER_CRYPTO_helper_cs_disconnect (dh);
    return NULL;
  }
  return dh;
}


/**
 * Handle a #TALER_HELPER_CS_MT_AVAIL message from the helper.
 *
 * @param dh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_mt_avail (struct TALER_CRYPTO_CsDenominationHelper *dh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_CsKeyAvailableNotification *kan
    = (const struct TALER_CRYPTO_CsKeyAvailableNotification *) hdr;
  const char *buf = (const char *) &kan[1];
  const char *section_name;
  uint16_t snl;

  if (sizeof (*kan) > ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  snl = ntohs (kan->section_name_len);
  if (ntohs (hdr->size) != sizeof (*kan) + snl)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 == snl)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  section_name = buf;
  if ('\0' != section_name[snl - 1])
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  {
    struct GNUNET_CRYPTO_BlindSignPublicKey *bsign_pub;
    struct TALER_CsPubHashP h_cs;

    bsign_pub = GNUNET_new (struct GNUNET_CRYPTO_BlindSignPublicKey);
    bsign_pub->cipher = GNUNET_CRYPTO_BSA_CS;
    bsign_pub->rc = 1;
    bsign_pub->details.cs_public_key = kan->denom_pub;

    GNUNET_CRYPTO_hash (&bsign_pub->details.cs_public_key,
                        sizeof (bsign_pub->details.cs_public_key),
                        &bsign_pub->pub_key_hash);
    h_cs.hash = bsign_pub->pub_key_hash;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Received CS key %s (%s)\n",
                GNUNET_h2s (&h_cs.hash),
                section_name);
    if (GNUNET_OK !=
        TALER_exchange_secmod_cs_verify (
          &h_cs,
          section_name,
          GNUNET_TIME_timestamp_ntoh (kan->anchor_time),
          GNUNET_TIME_relative_ntoh (kan->duration_withdraw),
          &kan->secm_pub,
          &kan->secm_sig))
    {
      GNUNET_break_op (0);
      GNUNET_CRYPTO_blind_sign_pub_decref (bsign_pub);
      return GNUNET_SYSERR;
    }
    dh->dkc (dh->dkc_cls,
             section_name,
             GNUNET_TIME_timestamp_ntoh (kan->anchor_time),
             GNUNET_TIME_relative_ntoh (kan->duration_withdraw),
             &h_cs,
             bsign_pub,
             &kan->secm_pub,
             &kan->secm_sig);
    GNUNET_CRYPTO_blind_sign_pub_decref (bsign_pub);
  }
  return GNUNET_OK;
}


/**
 * Handle a #TALER_HELPER_CS_MT_PURGE message from the helper.
 *
 * @param dh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_mt_purge (struct TALER_CRYPTO_CsDenominationHelper *dh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_CsKeyPurgeNotification *pn
    = (const struct TALER_CRYPTO_CsKeyPurgeNotification *) hdr;

  if (sizeof (*pn) != ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received revocation of denomination key %s\n",
              GNUNET_h2s (&pn->h_cs.hash));
  dh->dkc (dh->dkc_cls,
           NULL,
           GNUNET_TIME_UNIT_ZERO_TS,
           GNUNET_TIME_UNIT_ZERO,
           &pn->h_cs,
           NULL,
           NULL,
           NULL);
  return GNUNET_OK;
}


void
TALER_CRYPTO_helper_cs_poll (struct TALER_CRYPTO_CsDenominationHelper *dh)
{
  char buf[UINT16_MAX];
  size_t off = 0;
  unsigned int retry_limit = 3;
  const struct GNUNET_MessageHeader *hdr
    = (const struct GNUNET_MessageHeader *) buf;

  if (GNUNET_OK !=
      try_connect (dh))
    return; /* give up */
  while (1)
  {
    uint16_t msize;
    ssize_t ret;

    ret = recv (dh->sock,
                buf + off,
                sizeof (buf) - off,
                (dh->synced && (0 == off))
                ? MSG_DONTWAIT
                : 0);
    if (ret < 0)
    {
      if (EINTR == errno)
        continue;
      if (EAGAIN == errno)
      {
        GNUNET_assert (dh->synced);
        GNUNET_assert (0 == off);
        break;
      }
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (dh);
      if (0 == retry_limit)
        return; /* give up */
      if (GNUNET_OK !=
          try_connect (dh))
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
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Received message of type %u and length %u\n",
                (unsigned int) ntohs (hdr->type),
                (unsigned int) msize);
    switch (ntohs (hdr->type))
    {
    case TALER_HELPER_CS_MT_AVAIL:
      if (GNUNET_OK !=
          handle_mt_avail (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        return;
      }
      break;
    case TALER_HELPER_CS_MT_PURGE:
      if (GNUNET_OK !=
          handle_mt_purge (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        return;
      }
      break;
    case TALER_HELPER_CS_SYNCED:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Now synchronized with CS helper\n");
      dh->synced = true;
      break;
    default:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Received unexpected message of type %d (len: %u)\n",
                  (unsigned int) ntohs (hdr->type),
                  (unsigned int) msize);
      GNUNET_break_op (0);
      do_disconnect (dh);
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
TALER_CRYPTO_helper_cs_sign (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CRYPTO_CsSignRequest *req,
  bool for_melt,
  struct TALER_BlindedDenominationSignature *bs)
{
  enum TALER_ErrorCode ec = TALER_EC_INVALID;
  const struct TALER_CsPubHashP *h_cs = req->h_cs;

  memset (bs,
          0,
          sizeof (*bs));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting signature process\n");
  if (GNUNET_OK !=
      try_connect (dh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to helper\n");
    return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting signature\n");
  {
    char buf[sizeof (struct TALER_CRYPTO_CsSignRequestMessage)];
    struct TALER_CRYPTO_CsSignRequestMessage *sr
      = (struct TALER_CRYPTO_CsSignRequestMessage *) buf;

    sr->header.size = htons (sizeof (buf));
    sr->header.type = htons (TALER_HELPER_CS_MT_REQ_SIGN);
    sr->for_melt = htonl (for_melt ? 1 : 0);
    sr->h_cs = *h_cs;
    sr->message = *req->blinded_planchet;
    if (GNUNET_OK !=
        TALER_crypto_helper_send_all (dh->sock,
                                      buf,
                                      sizeof (buf)))
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "send");
      do_disconnect (dh);
      return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Awaiting reply\n");
  {
    char buf[UINT16_MAX];
    size_t off = 0;
    const struct GNUNET_MessageHeader *hdr
      = (const struct GNUNET_MessageHeader *) buf;
    bool finished = false;

    while (1)
    {
      uint16_t msize;
      ssize_t ret;

      ret = recv (dh->sock,
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
          return ec;
        }
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "recv");
        do_disconnect (dh);
        ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
        break;
      }
      if (0 == ret)
      {
        GNUNET_break (0 == off);
        if (! finished)
          ec = TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        return ec;
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
      case TALER_HELPER_CS_MT_RES_SIGNATURE:
        if (msize != sizeof (struct TALER_CRYPTO_SignResponse))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          goto end;
        }
        if (finished)
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          goto end;
        }
        {
          const struct TALER_CRYPTO_SignResponse *sr =
            (const struct TALER_CRYPTO_SignResponse *) buf;
          struct GNUNET_CRYPTO_BlindedSignature *blinded_sig;

          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received signature\n");
          ec = TALER_EC_NONE;
          finished = true;
          blinded_sig = GNUNET_new (struct GNUNET_CRYPTO_BlindedSignature);
          blinded_sig->cipher = GNUNET_CRYPTO_BSA_CS;
          blinded_sig->rc = 1;
          blinded_sig->details.blinded_cs_answer.b = ntohl (sr->b);
          blinded_sig->details.blinded_cs_answer.s_scalar = sr->cs_answer;
          bs->blinded_sig = blinded_sig;
          break;
        }
      case TALER_HELPER_CS_MT_RES_SIGN_FAILURE:
        if (msize != sizeof (struct TALER_CRYPTO_SignFailure))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          goto end;
        }
        {
          const struct TALER_CRYPTO_SignFailure *sf =
            (const struct TALER_CRYPTO_SignFailure *) buf;

          ec = (enum TALER_ErrorCode) (int) ntohl (sf->ec);
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Signing failed with status %d!\n",
                      ec);
          finished = true;
          break;
        }
      case TALER_HELPER_CS_MT_AVAIL:
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Received new key!\n");
        if (GNUNET_OK !=
            handle_mt_avail (dh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          goto end;
        }
        break; /* while(1) loop ensures we recvfrom() again */
      case TALER_HELPER_CS_MT_PURGE:
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Received revocation!\n");
        if (GNUNET_OK !=
            handle_mt_purge (dh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          goto end;
        }
        break; /* while(1) loop ensures we recvfrom() again */
      case TALER_HELPER_CS_SYNCED:
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Synchronized add odd time with CS helper!\n");
        dh->synced = true;
        break;
      default:
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Received unexpected message of type %u\n",
                    ntohs (hdr->type));
        do_disconnect (dh);
        ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        goto end;
      }
      memmove (buf,
               &buf[msize],
               off - msize);
      off -= msize;
      goto more;
    } /* while(1) */
end:
    if (finished)
      TALER_blinded_denom_sig_free (bs);
    return ec;
  }
}


void
TALER_CRYPTO_helper_cs_revoke (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs)
{
  struct TALER_CRYPTO_CsRevokeRequest rr = {
    .header.size = htons (sizeof (rr)),
    .header.type = htons (TALER_HELPER_CS_MT_REQ_REVOKE),
    .h_cs = *h_cs
  };

  if (GNUNET_OK !=
      try_connect (dh))
    return; /* give up */
  if (GNUNET_OK !=
      TALER_crypto_helper_send_all (dh->sock,
                                    &rr,
                                    sizeof (rr)))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "send");
    do_disconnect (dh);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requested revocation of denomination key %s\n",
              GNUNET_h2s (&h_cs->hash));
}


enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_r_derive (struct TALER_CRYPTO_CsDenominationHelper *dh,
                                 const struct TALER_CRYPTO_CsDeriveRequest *cdr,
                                 bool for_melt,
                                 struct GNUNET_CRYPTO_CSPublicRPairP *crp)
{
  enum TALER_ErrorCode ec = TALER_EC_INVALID;
  const struct TALER_CsPubHashP *h_cs = cdr->h_cs;
  const struct GNUNET_CRYPTO_CsSessionNonce *nonce = cdr->nonce;

  memset (crp,
          0,
          sizeof (*crp));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting R derivation process\n");
  if (GNUNET_OK !=
      try_connect (dh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to helper\n");
    return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting R\n");
  {
    struct TALER_CRYPTO_CsRDeriveRequest rdr = {
      .header.size = htons (sizeof (rdr)),
      .header.type = htons (TALER_HELPER_CS_MT_REQ_RDERIVE),
      .for_melt = htonl (for_melt ? 1 : 0),
      .h_cs = *h_cs,
      .nonce = *nonce
    };

    if (GNUNET_OK !=
        TALER_crypto_helper_send_all (dh->sock,
                                      &rdr,
                                      sizeof (rdr)))
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "send");
      do_disconnect (dh);
      return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Awaiting reply\n");
  {
    char buf[UINT16_MAX];
    size_t off = 0;
    const struct GNUNET_MessageHeader *hdr
      = (const struct GNUNET_MessageHeader *) buf;
    bool finished = false;

    while (1)
    {
      uint16_t msize;
      ssize_t ret;

      ret = recv (dh->sock,
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
          return ec;
        }
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "recv");
        do_disconnect (dh);
        return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      }
      if (0 == ret)
      {
        GNUNET_break (0 == off);
        if (! finished)
          return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
        return ec;
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
      case TALER_HELPER_CS_MT_RES_RDERIVE:
        if (msize != sizeof (struct TALER_CRYPTO_RDeriveResponse))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        if (finished)
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        {
          const struct TALER_CRYPTO_RDeriveResponse *rdr =
            (const struct TALER_CRYPTO_RDeriveResponse *) buf;

          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received R\n");
          finished = true;
          ec = TALER_EC_NONE;
          *crp = rdr->r_pub;
          break;
        }
      case TALER_HELPER_CS_MT_RES_RDERIVE_FAILURE:
        if (msize != sizeof (struct TALER_CRYPTO_RDeriveFailure))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        {
          const struct TALER_CRYPTO_RDeriveFailure *rdf =
            (const struct TALER_CRYPTO_RDeriveFailure *) buf;

          ec = (enum TALER_ErrorCode) (int) ntohl (rdf->ec);
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "R derivation failed!\n");
          finished = true;
          break;
        }
      case TALER_HELPER_CS_MT_AVAIL:
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Received new key!\n");
        if (GNUNET_OK !=
            handle_mt_avail (dh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        break; /* while(1) loop ensures we recvfrom() again */
      case TALER_HELPER_CS_MT_PURGE:
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Received revocation!\n");
        if (GNUNET_OK !=
            handle_mt_purge (dh,
                             hdr))
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        break; /* while(1) loop ensures we recvfrom() again */
      case TALER_HELPER_CS_SYNCED:
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Synchronized add odd time with CS helper!\n");
        dh->synced = true;
        break;
      default:
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Received unexpected message of type %u\n",
                    ntohs (hdr->type));
        do_disconnect (dh);
        return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
      }
      memmove (buf,
               &buf[msize],
               off - msize);
      off -= msize;
      goto more;
    } /* while(1) */
  }
}


enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_batch_sign (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  unsigned int reqs_length,
  const struct TALER_CRYPTO_CsSignRequest reqs[static reqs_length],
  bool for_melt,
  struct TALER_BlindedDenominationSignature bss[static reqs_length])
{
  enum TALER_ErrorCode ec = TALER_EC_INVALID;
  unsigned int rpos;
  unsigned int rend;
  unsigned int wpos;

  memset (bss,
          0,
          sizeof (*bss) * reqs_length);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting signature process\n");
  if (GNUNET_OK !=
      try_connect (dh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to helper\n");
    return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting %u signatures\n",
              reqs_length);
  rpos = 0;
  rend = 0;
  wpos = 0;
  while (rpos < reqs_length)
  {
    unsigned int mlen = sizeof (struct TALER_CRYPTO_BatchSignRequest);

    while ( (rend < reqs_length) &&
            (mlen + sizeof (struct TALER_CRYPTO_CsSignRequestMessage)
             < UINT16_MAX) )
    {
      mlen += sizeof (struct TALER_CRYPTO_CsSignRequestMessage);
      rend++;
    }
    {
      char obuf[mlen] GNUNET_ALIGN;
      struct TALER_CRYPTO_BatchSignRequest *bsr
        = (struct TALER_CRYPTO_BatchSignRequest *) obuf;
      void *wbuf;

      bsr->header.type = htons (TALER_HELPER_CS_MT_REQ_BATCH_SIGN);
      bsr->header.size = htons (mlen);
      bsr->batch_size = htonl (rend - rpos);
      wbuf = &bsr[1];
      for (unsigned int i = rpos; i<rend; i++)
      {
        struct TALER_CRYPTO_CsSignRequestMessage *csm = wbuf;
        const struct TALER_CRYPTO_CsSignRequest *csr = &reqs[i];

        csm->header.size = htons (sizeof (*csm));
        csm->header.type = htons (TALER_HELPER_CS_MT_REQ_SIGN);
        csm->for_melt = htonl (for_melt ? 1 : 0);
        csm->h_cs = *csr->h_cs;
        csm->message = *csr->blinded_planchet;
        wbuf += sizeof (*csm);
      }
      GNUNET_assert (wbuf == &obuf[mlen]);
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Sending batch request [%u-%u)\n",
                  rpos,
                  rend);
      if (GNUNET_OK !=
          TALER_crypto_helper_send_all (dh->sock,
                                        obuf,
                                        sizeof (obuf)))
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "send");
        do_disconnect (dh);
        return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      }
    } /* end of obuf scope */
    rpos = rend;
    {
      char buf[UINT16_MAX];
      size_t off = 0;
      const struct GNUNET_MessageHeader *hdr
        = (const struct GNUNET_MessageHeader *) buf;
      bool finished = false;

      while (1)
      {
        uint16_t msize;
        ssize_t ret;

        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Awaiting reply at %u (up to %u)\n",
                    wpos,
                    rend);
        ret = recv (dh->sock,
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
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
        }
        if (0 == ret)
        {
          GNUNET_break (0 == off);
          if (! finished)
            return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
          if (TALER_EC_NONE == ec)
            break;
          return ec;
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
        case TALER_HELPER_CS_MT_RES_SIGNATURE:
          if (msize != sizeof (struct TALER_CRYPTO_SignResponse))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          if (finished)
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          {
            const struct TALER_CRYPTO_SignResponse *sr =
              (const struct TALER_CRYPTO_SignResponse *) buf;
            struct GNUNET_CRYPTO_BlindedSignature *blinded_sig;
            GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                        "Received %u signature\n",
                        wpos);
            blinded_sig = GNUNET_new (struct GNUNET_CRYPTO_BlindedSignature);
            blinded_sig->cipher = GNUNET_CRYPTO_BSA_CS;
            blinded_sig->rc = 1;
            blinded_sig->details.blinded_cs_answer.b = ntohl (sr->b);
            blinded_sig->details.blinded_cs_answer.s_scalar = sr->cs_answer;

            bss[wpos].blinded_sig = blinded_sig;
            wpos++;
            if (wpos == rend)
            {
              if (TALER_EC_INVALID == ec)
                ec = TALER_EC_NONE;
              finished = true;
            }
            break;
          }

        case TALER_HELPER_CS_MT_RES_SIGN_FAILURE:
          if (msize != sizeof (struct TALER_CRYPTO_SignFailure))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          {
            const struct TALER_CRYPTO_SignFailure *sf =
              (const struct TALER_CRYPTO_SignFailure *) buf;

            ec = (enum TALER_ErrorCode) (int) ntohl (sf->ec);
            GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                        "Signing %u failed with status %d!\n",
                        wpos,
                        ec);
            wpos++;
            if (wpos == rend)
            {
              finished = true;
            }
            break;
          }
        case TALER_HELPER_CS_MT_AVAIL:
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received new key!\n");
          if (GNUNET_OK !=
              handle_mt_avail (dh,
                               hdr))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          break; /* while(1) loop ensures we recvfrom() again */
        case TALER_HELPER_CS_MT_PURGE:
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received revocation!\n");
          if (GNUNET_OK !=
              handle_mt_purge (dh,
                               hdr))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          break; /* while(1) loop ensures we recvfrom() again */
        case TALER_HELPER_CS_SYNCED:
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Synchronized add odd time with CS helper!\n");
          dh->synced = true;
          break;
        default:
          GNUNET_break_op (0);
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Received unexpected message of type %u\n",
                      ntohs (hdr->type));
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        memmove (buf,
                 &buf[msize],
                 off - msize);
        off -= msize;
        goto more;
      } /* while(1) */
    } /* scope */
  } /* while (rpos < cdrs_length) */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Existing with %u signatures and status %d\n",
              wpos,
              ec);
  return ec;
}


enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_r_batch_derive (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  unsigned int cdrs_length,
  const struct TALER_CRYPTO_CsDeriveRequest cdrs[static cdrs_length],
  bool for_melt,
  struct GNUNET_CRYPTO_CSPublicRPairP crps[static cdrs_length])
{
  enum TALER_ErrorCode ec = TALER_EC_INVALID;
  unsigned int rpos;
  unsigned int rend;
  unsigned int wpos;

  memset (crps,
          0,
          sizeof (*crps) * cdrs_length);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting R derivation process\n");
  if (GNUNET_OK !=
      try_connect (dh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to helper\n");
    return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting %u R pairs\n",
              cdrs_length);
  rpos = 0;
  rend = 0;
  wpos = 0;
  while (rpos < cdrs_length)
  {
    unsigned int mlen = sizeof (struct TALER_CRYPTO_BatchDeriveRequest);

    while ( (rend < cdrs_length) &&
            (mlen + sizeof (struct TALER_CRYPTO_CsRDeriveRequest)
             < UINT16_MAX) )
    {
      mlen += sizeof (struct TALER_CRYPTO_CsRDeriveRequest);
      rend++;
    }
    {
      char obuf[mlen] GNUNET_ALIGN;
      struct TALER_CRYPTO_BatchDeriveRequest *bdr
        = (struct TALER_CRYPTO_BatchDeriveRequest *) obuf;
      void *wbuf;

      bdr->header.type = htons (TALER_HELPER_CS_MT_REQ_BATCH_RDERIVE);
      bdr->header.size = htons (mlen);
      bdr->batch_size = htonl (rend - rpos);
      wbuf = &bdr[1];
      for (unsigned int i = rpos; i<rend; i++)
      {
        struct TALER_CRYPTO_CsRDeriveRequest *rdr = wbuf;
        const struct TALER_CRYPTO_CsDeriveRequest *cdr = &cdrs[i];

        rdr->header.size = htons (sizeof (*rdr));
        rdr->header.type = htons (TALER_HELPER_CS_MT_REQ_RDERIVE);
        rdr->for_melt = htonl (for_melt ? 1 : 0);
        rdr->h_cs = *cdr->h_cs;
        rdr->nonce = *cdr->nonce;
        wbuf += sizeof (*rdr);
      }
      GNUNET_assert (wbuf == &obuf[mlen]);
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Sending batch request [%u-%u)\n",
                  rpos,
                  rend);
      if (GNUNET_OK !=
          TALER_crypto_helper_send_all (dh->sock,
                                        obuf,
                                        sizeof (obuf)))
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "send");
        do_disconnect (dh);
        return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      }
    } /* end of obuf scope */
    rpos = rend;
    {
      char buf[UINT16_MAX];
      size_t off = 0;
      const struct GNUNET_MessageHeader *hdr
        = (const struct GNUNET_MessageHeader *) buf;
      bool finished = false;

      while (1)
      {
        uint16_t msize;
        ssize_t ret;

        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Awaiting reply at %u (up to %u)\n",
                    wpos,
                    rend);
        ret = recv (dh->sock,
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
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
        }
        if (0 == ret)
        {
          GNUNET_break (0 == off);
          if (! finished)
            return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
          if (TALER_EC_NONE == ec)
            break;
          return ec;
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
        case TALER_HELPER_CS_MT_RES_RDERIVE:
          if (msize != sizeof (struct TALER_CRYPTO_RDeriveResponse))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          if (finished)
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          {
            const struct TALER_CRYPTO_RDeriveResponse *rdr =
              (const struct TALER_CRYPTO_RDeriveResponse *) buf;

            GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                        "Received %u R pair\n",
                        wpos);
            crps[wpos] = rdr->r_pub;
            wpos++;
            if (wpos == rend)
            {
              if (TALER_EC_INVALID == ec)
                ec = TALER_EC_NONE;
              finished = true;
            }
            break;
          }
        case TALER_HELPER_CS_MT_RES_RDERIVE_FAILURE:
          if (msize != sizeof (struct TALER_CRYPTO_RDeriveFailure))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          {
            const struct TALER_CRYPTO_RDeriveFailure *rdf =
              (const struct TALER_CRYPTO_RDeriveFailure *) buf;

            ec = (enum TALER_ErrorCode) (int) ntohl (rdf->ec);
            GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                        "R derivation %u failed with status %d!\n",
                        wpos,
                        ec);
            wpos++;
            if (wpos == rend)
            {
              finished = true;
            }
            break;
          }
        case TALER_HELPER_CS_MT_AVAIL:
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received new key!\n");
          if (GNUNET_OK !=
              handle_mt_avail (dh,
                               hdr))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          break; /* while(1) loop ensures we recvfrom() again */
        case TALER_HELPER_CS_MT_PURGE:
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Received revocation!\n");
          if (GNUNET_OK !=
              handle_mt_purge (dh,
                               hdr))
          {
            GNUNET_break_op (0);
            do_disconnect (dh);
            return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          }
          break; /* while(1) loop ensures we recvfrom() again */
        case TALER_HELPER_CS_SYNCED:
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Synchronized add odd time with CS helper!\n");
          dh->synced = true;
          break;
        default:
          GNUNET_break_op (0);
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Received unexpected message of type %u\n",
                      ntohs (hdr->type));
          do_disconnect (dh);
          return TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        }
        memmove (buf,
                 &buf[msize],
                 off - msize);
        off -= msize;
        goto more;
      } /* while(1) */
    } /* scope */
  } /* while (rpos < cdrs_length) */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Existing with %u signatures and status %d\n",
              wpos,
              ec);
  return ec;
}


void
TALER_CRYPTO_helper_cs_disconnect (
  struct TALER_CRYPTO_CsDenominationHelper *dh)
{
  if (-1 != dh->sock)
    do_disconnect (dh);
  GNUNET_free (dh);
}


/* end of crypto_helper_cs.c */
