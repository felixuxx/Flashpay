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
 * @file util/crypto_helper_denom.c
 * @brief utility functions for running out-of-process private key operations
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler-helper-crypto-rsa.h"
#include <poll.h>


struct TALER_CRYPTO_DenominationHelper
{
  /**
   * Function to call with updates to available key material.
   */
  TALER_CRYPTO_DenominationKeyStatusCallback dkc;

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
do_disconnect (struct TALER_CRYPTO_DenominationHelper *dh)
{
  GNUNET_break (0 == close (dh->sock));
  if (0 != unlink (dh->my_sa.sun_path))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "unlink",
                              dh->my_sa.sun_path);
  dh->sock = -1;
}


/**
 * Try to connect to the helper process.  Updates
 * @e sock field in @a dh.
 *
 * @param[in,out] dh handle to establish connection for
 */
static void
try_connect (struct TALER_CRYPTO_DenominationHelper *dh)
{
  char *tmpdir;

  if (-1 != dh->sock)
    return;
  dh->sock = socket (AF_UNIX,
                     SOCK_DGRAM,
                     0);
  if (-1 == dh->sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "socket");
    return;
  }
  tmpdir = GNUNET_DISK_mktemp (dh->template);
  if (NULL == tmpdir)
  {
    do_disconnect (dh);
    return;
  }
  /* we use >= here because we want the sun_path to always
     be 0-terminated */
  if (strlen (tmpdir) >= sizeof (dh->sa.sun_path))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "PATHS",
                               "TALER_RUNTIME_DIR",
                               "path too long");
    GNUNET_free (tmpdir);
    do_disconnect (dh);
    return;
  }
  dh->my_sa.sun_family = AF_UNIX;
  strncpy (dh->my_sa.sun_path,
           tmpdir,
           sizeof (dh->sa.sun_path));
  if (0 != unlink (tmpdir))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "unlink",
                              tmpdir);
  if (0 != bind (dh->sock,
                 (const struct sockaddr *) &dh->my_sa,
                 sizeof (dh->my_sa)))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "bind",
                              tmpdir);
    do_disconnect (dh);
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
      .type = htons (TALER_HELPER_RSA_MT_REQ_INIT)
    };
    ssize_t ret;

    ret = sendto (dh->sock,
                  &hdr,
                  sizeof (hdr),
                  0,
                  (const struct sockaddr *) &dh->sa,
                  sizeof (dh->sa));
    if (ret < 0)
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "sendto",
                                dh->sa.sun_path);
      do_disconnect (dh);
      return;
    }
    /* We are using SOCK_DGRAM, partial writes should not be possible */
    GNUNET_break (((size_t) ret) == sizeof (hdr));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Successfully sent REQ_INIT\n");
  }

}


struct TALER_CRYPTO_DenominationHelper *
TALER_CRYPTO_helper_denom_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  TALER_CRYPTO_DenominationKeyStatusCallback dkc,
  void *dkc_cls)
{
  struct TALER_CRYPTO_DenominationHelper *dh;
  char *unixpath;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "taler-helper-crypto-rsa",
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-helper-crypto-rsa",
                               "UNIXPATH");
    return NULL;
  }
  /* we use >= here because we want the sun_path to always
     be 0-terminated */
  if (strlen (unixpath) >= sizeof (dh->sa.sun_path))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "taler-helper-crypto-rsa",
                               "UNIXPATH",
                               "path too long");
    GNUNET_free (unixpath);
    return NULL;
  }
  dh = GNUNET_new (struct TALER_CRYPTO_DenominationHelper);
  dh->dkc = dkc;
  dh->dkc_cls = dkc_cls;
  dh->sa.sun_family = AF_UNIX;
  strncpy (dh->sa.sun_path,
           unixpath,
           sizeof (dh->sa.sun_path));
  dh->sock = -1;
  {
    char *tmpdir;
    char *template;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "PATHS",
                                                 "TALER_RUNTIME_DIR",
                                                 &tmpdir))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                                 "PATHS",
                                 "TALER_RUNTIME_DIR");
      tmpdir = GNUNET_strdup ("/tmp");
    }
    GNUNET_asprintf (&template,
                     "%s/crypto-rsa-client/cli",
                     tmpdir);
    GNUNET_free (tmpdir);
    if (GNUNET_OK !=
        GNUNET_DISK_directory_create_for_file (template))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "mkdir",
                                template);
      GNUNET_free (dh);
      GNUNET_free (template);
      return NULL;
    }
    dh->template = template;
    if (strlen (template) >= sizeof (dh->sa.sun_path))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "PATHS",
                                 "TALER_RUNTIME_DIR",
                                 "path too long");
      TALER_CRYPTO_helper_denom_disconnect (dh);
      return NULL;
    }
  }
  TALER_CRYPTO_helper_denom_poll (dh);
  return dh;
}


/**
 * Handle a #TALER_HELPER_RSA_MT_AVAIL message from the helper.
 *
 * @param dh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static int
handle_mt_avail (struct TALER_CRYPTO_DenominationHelper *dh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_RsaKeyAvailableNotification *kan
    = (const struct TALER_CRYPTO_RsaKeyAvailableNotification *) hdr;
  const char *buf = (const char *) &kan[1];
  const char *section_name;

  if (sizeof (*kan) > ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (ntohs (hdr->size) !=
      sizeof (*kan)
      + ntohs (kan->pub_size)
      + ntohs (kan->section_name_len))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  section_name = &buf[ntohs (kan->pub_size)];
  if ('\0' != section_name[ntohs (kan->section_name_len) - 1])
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  {
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_HashCode h_denom_pub;

    denom_pub.rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_decode (buf,
                                             ntohs (kan->pub_size));
    if (NULL == denom_pub.rsa_public_key)
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &h_denom_pub);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Received RSA key %s (%s)\n",
                GNUNET_h2s (&h_denom_pub),
                section_name);
    if (GNUNET_OK !=
        TALER_exchange_secmod_rsa_verify (
          &h_denom_pub,
          section_name,
          GNUNET_TIME_absolute_ntoh (kan->anchor_time),
          GNUNET_TIME_relative_ntoh (kan->duration_withdraw),
          &kan->secm_pub,
          &kan->secm_sig))
    {
      GNUNET_break_op (0);
      GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);
      return GNUNET_SYSERR;
    }
    dh->dkc (dh->dkc_cls,
             section_name,
             GNUNET_TIME_absolute_ntoh (kan->anchor_time),
             GNUNET_TIME_relative_ntoh (kan->duration_withdraw),
             &h_denom_pub,
             &denom_pub,
             &kan->secm_pub,
             &kan->secm_sig);
    GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);
  }
  return GNUNET_OK;
}


/**
 * Handle a #TALER_HELPER_RSA_MT_PURGE message from the helper.
 *
 * @param dh helper context
 * @param hdr message that we received
 * @return #GNUNET_OK on success
 */
static int
handle_mt_purge (struct TALER_CRYPTO_DenominationHelper *dh,
                 const struct GNUNET_MessageHeader *hdr)
{
  const struct TALER_CRYPTO_RsaKeyPurgeNotification *pn
    = (const struct TALER_CRYPTO_RsaKeyPurgeNotification *) hdr;

  if (sizeof (*pn) != ntohs (hdr->size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  dh->dkc (dh->dkc_cls,
           NULL,
           GNUNET_TIME_UNIT_ZERO_ABS,
           GNUNET_TIME_UNIT_ZERO,
           &pn->h_denom_pub,
           NULL,
           NULL,
           NULL);
  return GNUNET_OK;
}


/**
 * Wait until the socket is ready to read.
 *
 * @param dh helper to wait for
 * @return false on timeout (after 5s)
 */
static bool
await_read_ready (struct TALER_CRYPTO_DenominationHelper *dh)
{
  /* wait for reply with 5s timeout */
  struct pollfd pfd = {
    .fd = dh->sock,
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
TALER_CRYPTO_helper_denom_poll (struct TALER_CRYPTO_DenominationHelper *dh)
{
  char buf[UINT16_MAX];
  ssize_t ret;
  const struct GNUNET_MessageHeader *hdr
    = (const struct GNUNET_MessageHeader *) buf;

  try_connect (dh);
  if (-1 == dh->sock)
    return; /* give up */
  while (1)
  {
    ret = recv (dh->sock,
                buf,
                sizeof (buf),
                MSG_DONTWAIT);
    if (ret < 0)
    {
      if (EAGAIN == errno)
      {
        if (dh->synced)
          break;
        if (! await_read_ready (dh))
        {
          /* timeout AND not synced => full reconnect */
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Restarting connection to RSA helper, did not come up properly\n");
          do_disconnect (dh);
          try_connect (dh);
          if (-1 == dh->sock)
            return; /* give up */
        }
        continue; /* try again */
      }
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (dh);
      return;
    }

    if ( (ret < sizeof (struct GNUNET_MessageHeader)) ||
         (ret != ntohs (hdr->size)) )
    {
      GNUNET_break_op (0);
      do_disconnect (dh);
      return;
    }
    switch (ntohs (hdr->type))
    {
    case TALER_HELPER_RSA_MT_AVAIL:
      if (GNUNET_OK !=
          handle_mt_avail (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        return;
      }
      break;
    case TALER_HELPER_RSA_MT_PURGE:
      if (GNUNET_OK !=
          handle_mt_purge (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        return;
      }
      break;
    case TALER_HELPER_RSA_SYNCED:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Now synchronized with RSA helper\n");
      dh->synced = true;
      break;
    default:
      GNUNET_break_op (0);
      do_disconnect (dh);
      return;
    }
  }
}


struct TALER_DenominationSignature
TALER_CRYPTO_helper_denom_sign (
  struct TALER_CRYPTO_DenominationHelper *dh,
  const struct GNUNET_HashCode *h_denom_pub,
  const void *msg,
  size_t msg_size,
  enum TALER_ErrorCode *ec)
{
  struct TALER_DenominationSignature ds = { NULL };
  {
    char buf[sizeof (struct TALER_CRYPTO_SignRequest) + msg_size];
    struct TALER_CRYPTO_SignRequest *sr
      = (struct TALER_CRYPTO_SignRequest *) buf;
    ssize_t ret;

    try_connect (dh);
    if (-1 == dh->sock)
    {
      *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      return ds;
    }
    sr->header.size = htons (sizeof (buf));
    sr->header.type = htons (TALER_HELPER_RSA_MT_REQ_SIGN);
    sr->reserved = htonl (0);
    sr->h_denom_pub = *h_denom_pub;
    memcpy (&sr[1],
            msg,
            msg_size);
    ret = sendto (dh->sock,
                  buf,
                  sizeof (buf),
                  0,
                  &dh->sa,
                  sizeof (dh->sa));
    if (ret < 0)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "sendto");
      do_disconnect (dh);
      *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      return ds;
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

    if (! await_read_ready (dh))
    {
      do_disconnect (dh);
      *ec = TALER_EC_GENERIC_TIMEOUT;
      return ds;
    }
    ret = recv (dh->sock,
                buf,
                sizeof (buf),
                0);
    if (ret < 0)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      do_disconnect (dh);
      *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE;
      return ds;
    }
    if ( (ret < sizeof (struct GNUNET_MessageHeader)) ||
         (ret != ntohs (hdr->size)) )
    {
      GNUNET_break_op (0);
      do_disconnect (dh);
      *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
      return ds;
    }
    switch (ntohs (hdr->type))
    {
    case TALER_HELPER_RSA_MT_RES_SIGNATURE:
      if (ret < sizeof (struct TALER_CRYPTO_SignResponse))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        return ds;
      }
      {
        const struct TALER_CRYPTO_SignResponse *sr =
          (const struct TALER_CRYPTO_SignResponse *) buf;
        struct GNUNET_CRYPTO_RsaSignature *rsa_signature;

        rsa_signature = GNUNET_CRYPTO_rsa_signature_decode (&sr[1],
                                                            ret - sizeof (*sr));
        if (NULL == rsa_signature)
        {
          GNUNET_break_op (0);
          do_disconnect (dh);
          *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
          return ds;
        }
        *ec = TALER_EC_NONE;
        ds.rsa_signature = rsa_signature;
        return ds;
      }
    case TALER_HELPER_RSA_MT_RES_SIGN_FAILURE:
      if (ret != sizeof (struct TALER_CRYPTO_SignFailure))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        return ds;
      }
      {
        const struct TALER_CRYPTO_SignFailure *sf =
          (const struct TALER_CRYPTO_SignFailure *) buf;

        *ec = (enum TALER_ErrorCode) ntohl (sf->ec);
        return ds;
      }
    case TALER_HELPER_RSA_MT_AVAIL:
      if (GNUNET_OK !=
          handle_mt_avail (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        return ds;
      }
      break; /* while(1) loop ensures we recvfrom() again */
    case TALER_HELPER_RSA_MT_PURGE:
      if (GNUNET_OK !=
          handle_mt_purge (dh,
                           hdr))
      {
        GNUNET_break_op (0);
        do_disconnect (dh);
        *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
        return ds;
      }
      break; /* while(1) loop ensures we recvfrom() again */
    default:
      GNUNET_break_op (0);
      do_disconnect (dh);
      *ec = TALER_EC_EXCHANGE_DENOMINATION_HELPER_BUG;
      return ds;
    }
  }
}


void
TALER_CRYPTO_helper_denom_revoke (
  struct TALER_CRYPTO_DenominationHelper *dh,
  const struct GNUNET_HashCode *h_denom_pub)
{
  struct TALER_CRYPTO_RevokeRequest rr = {
    .header.size = htons (sizeof (rr)),
    .header.type = htons (TALER_HELPER_RSA_MT_REQ_REVOKE),
    .h_denom_pub = *h_denom_pub
  };
  ssize_t ret;

  try_connect (dh);
  if (-1 == dh->sock)
    return; /* give up */
  ret = sendto (dh->sock,
                &rr,
                sizeof (rr),
                0,
                (const struct sockaddr *) &dh->sa,
                sizeof (dh->sa));
  if (ret < 0)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "sendto");
    do_disconnect (dh);
    return;
  }
  /* We are using SOCK_DGRAM, partial writes should not be possible */
  GNUNET_break (((size_t) ret) == sizeof (rr));
}


void
TALER_CRYPTO_helper_denom_disconnect (
  struct TALER_CRYPTO_DenominationHelper *dh)
{
  if (-1 != dh->sock)
    do_disconnect (dh);
  GNUNET_free (dh->template);
  GNUNET_free (dh);
}


/* end of crypto_helper_denom.c */
