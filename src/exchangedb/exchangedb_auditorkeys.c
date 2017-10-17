/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2017 Inria & GNUnet e.V.

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
 * @file exchangedb/exchangedb_auditorkeys.c
 * @brief I/O operations for the Exchange's auditor data
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


/**
 * Closure for #auditor_iter() and
 */
struct AuditorIterateContext
{

  /**
   * Function to call with the information for each auditor.
   */
  TALER_EXCHANGEDB_AuditorIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;

  /**
   * Status of the iteration.
   */
  int status;
};


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Header of a file with auditing information.
 */
struct AuditorFileHeaderP
{

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP apub;

  /**
   * Master public key of the exchange the auditor is signing
   * information for.
   */
  struct TALER_MasterPublicKeyP mpub;

  /**
   * Number of signatures and DKI entries in this file.
   */
  uint32_t dki_len;

};
GNUNET_NETWORK_STRUCT_END


/**
 * Load the auditor signature and the information signed by the
 * auditor and call the callback in @a cls with the information.
 *
 * @param cls the `struct AuditorIterateContext *`
 * @param filename name of a file that should contain
 *                 a denomination key
 * @return #GNUNET_OK to continue to iterate
 *         #GNUNET_NO to abort iteration with success
 *         #GNUNET_SYSERR to abort iteration with failure
 */
static int
auditor_iter (void *cls,
              const char *filename)
{
  struct AuditorIterateContext *aic = cls;
  uint64_t size;
  struct AuditorFileHeaderP *af;
  const struct TALER_AuditorSignatureP *sigs;
  const struct TALER_DenominationKeyValidityPS *dki;
  const char *auditor_url;
  unsigned int dki_len;
  size_t url_len;
  int iret;

  if (GNUNET_OK != GNUNET_DISK_file_size (filename,
                                          &size,
                                          GNUNET_YES,
                                          GNUNET_YES))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping inaccessable auditor information file `%s'\n",
                filename);
    return GNUNET_OK;
  }
  if (size < sizeof (struct AuditorFileHeaderP))
  {
    GNUNET_break (0);
    return GNUNET_OK;
  }
  af = GNUNET_malloc (size);
  if (size !=
      GNUNET_DISK_fn_read (filename,
                           af,
                           size))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "read",
                              filename);
    GNUNET_free (af);
    return GNUNET_OK;
  }
  dki_len = ntohl (af->dki_len);
  if (0 == dki_len)
  {
    GNUNET_break_op (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No signed keys in %s\n",
                filename);
    GNUNET_free (af);
    return GNUNET_OK;
  }
  if ( (size - sizeof (struct AuditorFileHeaderP)) / dki_len <
       (sizeof (struct TALER_DenominationKeyValidityPS) +
        sizeof (struct TALER_AuditorSignatureP)) )
  {
    GNUNET_break_op (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Malformed key file %s\n",
                filename);
    GNUNET_free (af);
    return GNUNET_OK;
  }
  url_len = size
    - sizeof (struct AuditorFileHeaderP)
    - dki_len * (sizeof (struct TALER_DenominationKeyValidityPS) +
                 sizeof (struct TALER_AuditorSignatureP));
  sigs = (const struct TALER_AuditorSignatureP *) &af[1];
  dki = (const struct TALER_DenominationKeyValidityPS *) &sigs[dki_len];
  auditor_url = (const char *) &dki[dki_len];
  if ( (0 == url_len) ||
       ('\0' != auditor_url[url_len - 1]) )
  {
    GNUNET_break_op (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Malformed key file %s\n",
                filename);
    GNUNET_free (af);
    return GNUNET_OK;
  }
  /* Ignoring return value to not interrupt the iteration */
  if (GNUNET_OK !=
      (iret = aic->it (aic->it_cls,
		       &af->apub,
		       auditor_url,
		       &af->mpub,
		       dki_len,
		       sigs,
		       dki)))
  {
    GNUNET_free (af);
    if (GNUNET_SYSERR == iret)
      aic->status = GNUNET_SYSERR;
    return GNUNET_SYSERR;
  }
  aic->status++;
  GNUNET_free (af);
  return GNUNET_OK;
}


/**
 * Call @a it with information for each auditor found in the @a exchange_base_dir.
 *
 * @param cfg configuration to use
 * @param it function to call with auditor information
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_EXCHANGEDB_auditor_iterate (const struct GNUNET_CONFIGURATION_Handle *cfg,
                                  TALER_EXCHANGEDB_AuditorIterator it,
                                  void *it_cls)
{
  struct AuditorIterateContext aic;
  int ret;
  char *auditor_base_dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchangedb",
                                               "AUDITOR_BASE_DIR",
                                               &auditor_base_dir))
    return -1;
  aic.it = it;
  aic.it_cls = it_cls;
  aic.status = 0;
  ret = GNUNET_DISK_directory_scan (auditor_base_dir,
                                    &auditor_iter,
                                    &aic);
  GNUNET_free (auditor_base_dir);
  if ( (0 != aic.status) ||
       (GNUNET_OK == ret) )
    return aic.status;
  return ret;
}


/**
 * Write auditor information to the given file.
 *
 * @param filename the file where to write the auditor information to
 * @param apub the auditor's public key
 * @param auditor_url the URL of the auditor
 * @param asigs the auditor's signatures, array of length @a dki_len
 * @param mpub the exchange's public key (as expected by the auditor)
 * @param dki_len length of @a dki
 * @param dki array of denomination coin data signed by the auditor
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_EXCHANGEDB_auditor_write (const char *filename,
                                const struct TALER_AuditorPublicKeyP *apub,
                                const char *auditor_url,
                                const struct TALER_AuditorSignatureP *asigs,
                                const struct TALER_MasterPublicKeyP *mpub,
                                unsigned int dki_len,
                                const struct TALER_DenominationKeyValidityPS *dki)
{
  struct AuditorFileHeaderP af;
  struct GNUNET_DISK_FileHandle *fh;
  ssize_t wrote;
  size_t wsize;
  int ret;
  int eno;

  af.apub = *apub;
  af.mpub = *mpub;
  af.dki_len = htonl ((uint32_t) dki_len);
  ret = GNUNET_SYSERR;
  if (NULL == (fh = GNUNET_DISK_file_open
               (filename,
                GNUNET_DISK_OPEN_WRITE | GNUNET_DISK_OPEN_CREATE | GNUNET_DISK_OPEN_TRUNCATE,
                GNUNET_DISK_PERM_USER_READ | GNUNET_DISK_PERM_USER_WRITE)))
    goto cleanup;
  wsize = sizeof (struct AuditorFileHeaderP);
  if (GNUNET_SYSERR == (wrote = GNUNET_DISK_file_write (fh,
                                                        &af,
                                                        wsize)))
    goto cleanup;
  if (wrote != wsize)
    goto cleanup;
  wsize = dki_len * sizeof (struct TALER_AuditorSignatureP);
  if (wsize ==
      GNUNET_DISK_file_write (fh,
                              asigs,
                              wsize))
    ret = GNUNET_OK;
  wsize = dki_len * sizeof (struct TALER_DenominationKeyValidityPS);
  if (wsize ==
      GNUNET_DISK_file_write (fh,
                              dki,
                              wsize))
    ret = GNUNET_OK;
  wsize = strlen (auditor_url) + 1;
  if (wsize ==
      GNUNET_DISK_file_write (fh,
                              auditor_url,
                              wsize))
    ret = GNUNET_OK;
 cleanup:
  eno = errno;
  if (NULL != fh)
    (void) GNUNET_DISK_file_close (fh);
  errno = eno;
  return ret;
}


/* end of exchangedb_auditorkeys.c */
