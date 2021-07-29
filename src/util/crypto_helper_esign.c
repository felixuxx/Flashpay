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
 * @file util/crypto_helper_esign.c
 * @brief utility functions for running out-of-process private key operations
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler-exchange-secmod-eddsa.h"
#include <poll.h>


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
   * Socket address of this process.
   */
  struct sockaddr_un my_sa;

  /**
   * Template for @e my_sa.
   */
  char *template;

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
  if (0 != unlink (esh->my_sa.sun_path))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "unlink",
                              esh->my_sa.sun_path);
  esh->sock = -1;
}


/**
 * Try to connect to the helper process.  Updates
 * @e sock field in @a esh.
 *
 * @param[in,out] esh handle to establish connection for
 */
static void
try_connect (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  char *tmpdir;

  if (-1 != esh->sock)
    return;
  esh->sock = socket (AF_UNIX,
                      SOCK_DGRAM,
                      0);
  if (-1 == esh->sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "socket");
    return;
  }
  tmpdir = GNUNET_DISK_mktemp (esh->template);
  if (NULL == tmpdir)
  {
    do_disconnect (esh);
    return;
  }
  /* we use >= here because we want the sun_path to always
     be 0-terminated */
  if (strlen (tmpdir) >= sizeof (esh->sa.sun_path))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "PATHS",
                               "TALER_RUNTIME_DIR",
                               "path too long");
    GNUNET_free (tmpdir);
    do_disconnect (esh);
    return;
  }
  esh->my_sa.sun_family = AF_UNIX;
  strncpy (esh->my_sa.sun_path,
           tmpdir,
           sizeof (esh->sa.sun_path) - 1);
  if (0 != unlink (tmpdir))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "unlink",
                              tmpdir);
  if (0 != bind (esh->sock,
                 (const struct sockaddr *) &esh->my_sa,
                 sizeof (esh->my_sa)))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "bind",
                              tmpdir);
    do_disconnect (esh);
    GNUNET_free (tmpdir);
    return;
  }
  /* Fix permissions on UNIX domain socket, just
     in case umask() is not set to enable group write */
  if (0 != chmod (tmpdir,
                  S_IRUSR | S_IWUSR | S_IWGRP))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "chmod",
                              tmpdir);
  }
  GNUNET_free (tmpdir);
  {
    struct GNUNET_MessageHeader hdr = {
      .size = htons (sizeof (hdr)),
      .type = htons (TALER_HELPER_EDDSA_MT_REQ_INIT)
    };
    ssize_t ret;

    ret = sendto (esh->sock,
                  &hdr,
                  sizeof (hdr),
                  0,
                  (const struct sockaddr *) &esh->sa,
                  sizeof (esh->sa));
    if (ret < 0)
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "sendto",
                                esh->sa.sun_path);
      do_disconnect (esh);
      return;
    }
    /* We are using SOCK_DGRAM, partial writes should not be possible */
    GNUNET_break (((size_t) ret) == sizeof (hdr));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Successfully sent REQ_INIT\n");
  }

}


struct TALER_CRYPTO_ExchangeSignHelper *
TALER_CRYPTO_helper_esign_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  TALER_CRYPTO_ExchangeKeyStatusCallback ekc,
  void *ekc_cls)
{
  struct TALER_CRYPTO_ExchangeSignHelper *esh;
  char *unixpath;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "taler-exchange-secmod-eddsa",
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "UNIXPATH");
    return NULL;
  }
  /* we use >= here because we want the sun_path to always
     be 0-terminated */
  if (strlen (unixpath) >= sizeof (esh->sa.sun_path))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "UNIXPATH",
                               "path too long");
    GNUNET_free (unixpath);
    return NULL;
  }
  esh = GNUNET_new (struct TALER_CRYPTO_ExchangeSignHelper);
  esh->ekc = ekc;
  esh->ekc_cls = ekc_cls;
  esh->sa.sun_family = AF_UNIX;
  strncpy (esh->sa.sun_path,
           unixpath,
           sizeof (esh->sa.sun_path) - 1);
  GNUNET_free (unixpath);
  esh->sock = -1;
  {
    char *tmpdir;
    char *template;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "taler-exchange-secmod-eddsa",
                                                 "CLIENT_DIR",
                                                 &tmpdir))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler-exchange-secmod-eddsa",
                                 "CLIENT_DIR");
      GNUNET_free (esh);
      return NULL;
    }
    GNUNET_asprintf (&template,
                     "%s/cli",
                     tmpdir);
    /* We expect the service to create the client directory */
    if (GNUNET_OK !=
        GNUNET_DISK_directory_test (tmpdir,
                                    GNUNET_YES))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unable to read secmod client directory (%s)\n",
                  tmpdir);
      GNUNET_free (esh);
      GNUNET_free (template);
      GNUNET_free (tmpdir);
      return NULL;
    }
    GNUNET_free (tmpdir);
    esh->template = template;
    if (strlen (template) >= sizeof (esh->sa.sun_path))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "PATHS",
                                 "TALER_RUNTIME_DIR",
                                 "path too long");
      TALER_CRYPTO_helper_esign_disconnect (esh);
      return NULL;
    }
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
static int
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
        GNUNET_TIME_absolute_ntoh (kan->anchor_time),
        GNUNET_TIME_relative_ntoh (kan->duration),
        &kan->secm_pub,
        &kan->secm_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  esh->ekc (esh->ekc_cls,
            GNUNET_TIME_absolute_ntoh (kan->anchor_time),
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
static int
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
            GNUNET_TIME_UNIT_ZERO_ABS,
            GNUNET_TIME_UNIT_ZERO,
            &pn->exchange_pub,
            NULL,
            NULL);
  return GNUNET_OK;
}


/**
 * Wait until the socket is ready to read.
 *
 * @param esh helper to wait for
 * @return false on timeout (after 5s)
 */
static bool
await_read_ready (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  /* wait for reply with 5s timeout */
  struct pollfd pfd = {
    .fd = esh->sock,
    .events = POLLIN
  };
  sigset_t sigmask;
  struct timespec ts = {
    .tv_sec = 5
  };
  int ret;

  GNUNET_assert (0 == sigemptyset (&sigmask));
  GNUNET_assert (0 == sigaddset (&sigmask, SIGTERM));
  GNUNET_assert (0 == sigaddset (&sigmask, SIGHUP));
  ret = ppoll (&pfd,
               1,
               &ts,
               &sigmask);
  if ( (-1 == ret) &&
       (EINTR != errno) )
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "ppoll");
  return (0 < ret);
}


void
TALER_CRYPTO_helper_esign_poll (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  char buf[UINT16_MAX];
  ssize_t ret;
  const struct GNUNET_MessageHeader *hdr
    = (const struct GNUNET_MessageHeader *) buf;

  try_connect (esh);
  if (-1 == esh->sock)
    return; /* give up */
  while (1)
  {
    ret = recv (esh->sock,
                buf,
                sizeof (buf),
                MSG_DONTWAIT);
    if (ret < 0)
    {
      if (EAGAIN == errno)
      {
        if (esh->synced)
          break;
        if (! await_read_ready (esh))
        {
          /* timeout AND not synced => full reconnect */
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Restarting connection to EdDSA helper, did not come up properly\n");
          do_disconnect (esh);
          try_connect (esh);
          if (-1 == esh->sock)
            return; /* give up */
        }
        continue; /* try again */
      }
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (esh);
      return;
    }

    if ( (ret < sizeof (struct GNUNET_MessageHeader)) ||
         (ret != ntohs (hdr->size)) )
    {
      GNUNET_break_op (0);
      do_disconnect (esh);
      return;
    }
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
      GNUNET_break_op (0);
      do_disconnect (esh);
      return;
    }
  }
}


enum TALER_ErrorCode
TALER_CRYPTO_helper_esign_sign_ (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_ExchangeSignatureP *exchange_sig)
{
  {
    uint32_t purpose_size = ntohl (purpose->size);
    char buf[sizeof (struct TALER_CRYPTO_EddsaSignRequest) + purpose_size
             - sizeof (struct GNUNET_CRYPTO_EccSignaturePurpose)];
    struct TALER_CRYPTO_EddsaSignRequest *sr
      = (struct TALER_CRYPTO_EddsaSignRequest *) buf;
    ssize_t ret;

    try_connect (esh);
    if (-1 == esh->sock)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to connect to helper\n");
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
    }
    sr->header.size = htons (sizeof (buf));
    sr->header.type = htons (TALER_HELPER_EDDSA_MT_REQ_SIGN);
    sr->reserved = htonl (0);
    memcpy (&sr->purpose,
            purpose,
            purpose_size);
    ret = sendto (esh->sock,
                  buf,
                  sizeof (buf),
                  0,
                  (const struct sockaddr *) &esh->sa,
                  sizeof (esh->sa));
    if (ret < 0)
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "sendto",
                                esh->sa.sun_path);
      do_disconnect (esh);
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
    }
    /* We are using SOCK_DGRAM, partial writes should not be possible */
    GNUNET_break (((size_t) ret) == sizeof (buf));
  }

  while (1)
  {
    char buf[UINT16_MAX];
    ssize_t ret;
    const struct GNUNET_MessageHeader *hdr
      = (const struct GNUNET_MessageHeader *) buf;

    if (! await_read_ready (esh))
    {
      do_disconnect (esh);
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Timeout waiting for helper\n");
      return TALER_EC_GENERIC_TIMEOUT;
    }
    ret = recv (esh->sock,
                buf,
                sizeof (buf),
                0);
    if (ret < 0)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (esh);
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE;
    }
    if ( (ret < sizeof (struct GNUNET_MessageHeader)) ||
         (ret != ntohs (hdr->size)) )
    {
      GNUNET_break_op (0);
      do_disconnect (esh);
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
    }
    switch (ntohs (hdr->type))
    {
    case TALER_HELPER_EDDSA_MT_RES_SIGNATURE:
      if (ret != sizeof (struct TALER_CRYPTO_EddsaSignResponse))
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
        return TALER_EC_NONE;
      }
    case TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE:
      if (ret != sizeof (struct TALER_CRYPTO_EddsaSignFailure))
      {
        GNUNET_break_op (0);
        do_disconnect (esh);
        return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
      }
      {
        const struct TALER_CRYPTO_EddsaSignFailure *sf =
          (const struct TALER_CRYPTO_EddsaSignFailure *) buf;

        return (enum TALER_ErrorCode) ntohl (sf->ec);
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
      break; /* while(1) loop ensures we recvfrom() again */
    case TALER_HELPER_EDDSA_MT_PURGE:
      if (GNUNET_OK !=
          handle_mt_purge (esh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (esh);
        return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
      }
      break; /* while(1) loop ensures we recvfrom() again */
    default:
      GNUNET_break_op (0);
      do_disconnect (esh);
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
    }
  }
}


void
TALER_CRYPTO_helper_esign_revoke (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  struct TALER_CRYPTO_EddsaRevokeRequest rr = {
    .header.size = htons (sizeof (rr)),
    .header.type = htons (TALER_HELPER_EDDSA_MT_REQ_REVOKE),
    .exchange_pub = *exchange_pub
  };
  ssize_t ret;

  try_connect (esh);
  if (-1 == esh->sock)
    return; /* give up */
  ret = sendto (esh->sock,
                &rr,
                sizeof (rr),
                0,
                (const struct sockaddr *) &esh->sa,
                sizeof (esh->sa));
  if (ret < 0)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "sendto");
    do_disconnect (esh);
    return;
  }
  /* We are using SOCK_DGRAM, partial writes should not be possible */
  GNUNET_break (((size_t) ret) == sizeof (rr));
}


void
TALER_CRYPTO_helper_esign_disconnect (
  struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  if (-1 != esh->sock)
    do_disconnect (esh);
  GNUNET_free (esh->template);
  GNUNET_free (esh);
}


/* end of crypto_helper_esign.c */
