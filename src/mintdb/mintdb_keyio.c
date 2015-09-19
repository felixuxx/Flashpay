/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mintdb/mintdb_keyio.c
 * @brief I/O operations for the Mint's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_mintdb_lib.h"


/**
 * Closure for the #signkeys_iterate_dir_iter().
 */
struct SignkeysIterateContext
{

  /**
   * Function to call on each signing key.
   */
  TALER_MINTDB_SigningKeyIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;
};


/**
 * Function called on each file in the directory with our signing
 * keys. Parses the file and calls the iterator from @a cls.
 *
 * @param cls the `struct SignkeysIterateContext *`
 * @param filename name of the file to parse
 * @return #GNUNET_OK to continue,
 *         #GNUNET_NO to stop iteration without error,
 *         #GNUNET_SYSERR to stop iteration with error
 */
static int
signkeys_iterate_dir_iter (void *cls,
                           const char *filename)
{
  struct SignkeysIterateContext *skc = cls;
  ssize_t nread;
  struct TALER_MINTDB_PrivateSigningKeyInformationP issue;

  nread = GNUNET_DISK_fn_read (filename,
                               &issue,
                               sizeof (struct TALER_MINTDB_PrivateSigningKeyInformationP));
  if (nread != sizeof (struct TALER_MINTDB_PrivateSigningKeyInformationP))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid signkey file `%s': wrong size (%d, expected %u)\n",
                filename,
                (int) nread,
                sizeof (struct TALER_MINTDB_PrivateSigningKeyInformationP));
    return GNUNET_OK;
  }
  return skc->it (skc->it_cls,
                  filename,
                  &issue);
}


/**
 * Call @a it for each signing key found in the @a mint_base_dir.
 *
 * @param mint_base_dir base directory for the mint,
 *                      the signing keys must be in the #TALER_MINTDB_DIR_SIGNING_KEYS
 *                      subdirectory
 * @param it function to call on each signing key
 * @param it_cls closure for @a it
 * @return number of files found (may not match
 *         number of keys given to @a it as malformed
 *         files are simply skipped), -1 on error
 */
int
TALER_MINTDB_signing_keys_iterate (const char *mint_base_dir,
                                   TALER_MINTDB_SigningKeyIterator it,
                                   void *it_cls)
{
  char *signkey_dir;
  struct SignkeysIterateContext skc;
  int ret;

  GNUNET_asprintf (&signkey_dir,
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_SIGNING_KEYS,
                   mint_base_dir);
  skc.it = it;
  skc.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (signkey_dir,
                                    &signkeys_iterate_dir_iter,
                                    &skc);
  GNUNET_free (signkey_dir);
  return ret;
}


/**
 * Import a denomination key from the given file.
 *
 * @param filename the file to import the key from
 * @param[out] dki set to the imported denomination key
 * @return #GNUNET_OK upon success;
 *         #GNUNET_SYSERR upon failure
 */
int
TALER_MINTDB_denomination_key_read (const char *filename,
                                    struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  uint64_t size;
  size_t offset;
  void *data;
  struct GNUNET_CRYPTO_rsa_PrivateKey *priv;

  if (GNUNET_OK != GNUNET_DISK_file_size (filename,
                                          &size,
                                          GNUNET_YES,
                                          GNUNET_YES))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping inaccessable denomination key file `%s'\n",
                filename);
    return GNUNET_SYSERR;
  }
  offset = sizeof (struct TALER_MINTDB_DenominationKeyInformationP);
  if (size <= offset)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  data = GNUNET_malloc (size);
  if (size !=
      GNUNET_DISK_fn_read (filename,
                           data,
                           size))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "read",
                              filename);
    GNUNET_free (data);
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (priv = GNUNET_CRYPTO_rsa_private_key_decode (data + offset,
                                                    size - offset)))
  {
    GNUNET_free (data);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (NULL == dki->denom_priv.rsa_private_key);
  dki->denom_priv.rsa_private_key = priv;
  dki->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (priv);
  memcpy (&dki->issue,
          data,
          offset);
  GNUNET_free (data);
  return GNUNET_OK;
}


/**
 * Exports a denomination key to the given file.
 *
 * @param filename the file where to write the denomination key
 * @param dki the denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_MINTDB_denomination_key_write (const char *filename,
                                     const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  char *priv_enc;
  size_t priv_enc_size;
  struct GNUNET_DISK_FileHandle *fh;
  ssize_t wrote;
  size_t wsize;
  int ret;

  fh = NULL;
  priv_enc_size
    = GNUNET_CRYPTO_rsa_private_key_encode (dki->denom_priv.rsa_private_key,
                                            &priv_enc);
  ret = GNUNET_SYSERR;
  if (NULL == (fh = GNUNET_DISK_file_open
               (filename,
                GNUNET_DISK_OPEN_WRITE | GNUNET_DISK_OPEN_CREATE | GNUNET_DISK_OPEN_TRUNCATE,
                GNUNET_DISK_PERM_USER_READ | GNUNET_DISK_PERM_USER_WRITE)))
    goto cleanup;
  wsize = sizeof (struct TALER_MINTDB_DenominationKeyInformationP);
  if (GNUNET_SYSERR == (wrote = GNUNET_DISK_file_write (fh,
                                                        &dki->issue,
                                                        wsize)))
    goto cleanup;
  if (wrote != wsize)
    goto cleanup;
  if (GNUNET_SYSERR ==
      (wrote = GNUNET_DISK_file_write (fh,
                                       priv_enc,
                                       priv_enc_size)))
    goto cleanup;
  if (wrote != priv_enc_size)
    goto cleanup;
  ret = GNUNET_OK;
 cleanup:
  GNUNET_free_non_null (priv_enc);
  if (NULL != fh)
    (void) GNUNET_DISK_file_close (fh);
  return ret;
}


/**
 * Closure for #denomkeys_iterate_keydir_iter() and
 * #denomkeys_iterate_topdir_iter().
 */
struct DenomkeysIterateContext
{

  /**
   * Set to the name of the directory below the top-level directory
   * during the call to #denomkeys_iterate_keydir_iter().
   */
  const char *alias;

  /**
   * Function to call on each denomination key.
   */
  TALER_MINTDB_DenominationKeyIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;
};


/**
 * Decode the denomination key in the given file @a filename and call
 * the callback in @a cls with the information.
 *
 * @param cls the `struct DenomkeysIterateContext *`
 * @param filename name of a file that should contain
 *                 a denomination key
 * @return #GNUNET_OK to continue to iterate
 *         #GNUNET_NO to abort iteration with success
 *         #GNUNET_SYSERR to abort iteration with failure
 */
static int
denomkeys_iterate_keydir_iter (void *cls,
                               const char *filename)
{
  struct DenomkeysIterateContext *dic = cls;
  struct TALER_MINTDB_DenominationKeyIssueInformation issue;
  int ret;

  memset (&issue, 0, sizeof (issue));
  if (GNUNET_OK !=
      TALER_MINTDB_denomination_key_read (filename,
                                          &issue))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid denomkey file: '%s'\n",
                filename);
    return GNUNET_OK;
  }
  ret = dic->it (dic->it_cls,
                 dic->alias,
                 &issue);
  GNUNET_CRYPTO_rsa_private_key_free (issue.denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (issue.denom_pub.rsa_public_key);
  return ret;
}


/**
 * Function called on each subdirectory in the #TALER_MINTDB_DIR_DENOMINATION_KEYS.  Will
 * call the #denomkeys_iterate_keydir_iter() on each file in the
 * subdirectory.
 *
 * @param cls the `struct DenomkeysIterateContext *`
 * @param filename name of the subdirectory to scan
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR if we need to abort
 */
static int
denomkeys_iterate_topdir_iter (void *cls,
                               const char *filename)
{
  struct DenomkeysIterateContext *dic = cls;

  dic->alias = GNUNET_STRINGS_get_short_name (filename);
  if (0 > GNUNET_DISK_directory_scan (filename,
                                      &denomkeys_iterate_keydir_iter,
                                      dic))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Call @a it for each denomination key found in the @a mint_base_dir.
 *
 * @param mint_base_dir base directory for the mint,
 *                      the signing keys must be in the #TALER_MINTDB_DIR_DENOMINATION_KEYS
 *                      subdirectory
 * @param it function to call on each denomination key found
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_MINTDB_denomination_keys_iterate (const char *mint_base_dir,
                                        TALER_MINTDB_DenominationKeyIterator it,
                                        void *it_cls)
{
  char *dir;
  struct DenomkeysIterateContext dic;
  int ret;

  GNUNET_asprintf (&dir,
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_DENOMINATION_KEYS,
                   mint_base_dir);
  dic.it = it;
  dic.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (dir,
                                    &denomkeys_iterate_topdir_iter,
                                    &dic);
  GNUNET_free (dir);
  return ret;
}


/**
 * Closure for #auditor_iter() and
 */
struct AuditorIterateContext
{

  /**
   * Function to call with the information for each auditor.
   */
  TALER_MINTDB_AuditorIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;
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
   * Master public key of the mint the auditor is signing
   * information for.
   */
  struct TALER_MasterPublicKeyP mpub;

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
  unsigned int len;
  int ret;

  if (GNUNET_OK != GNUNET_DISK_file_size (filename,
                                          &size,
                                          GNUNET_YES,
                                          GNUNET_YES))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping inaccessable auditor information file `%s'\n",
                filename);
    return GNUNET_SYSERR;
  }
  if ( (size < sizeof (struct AuditorFileHeaderP)) ||
       (0 != (len = ((size - sizeof (struct AuditorFileHeaderP)) %
                     (sizeof (struct TALER_DenominationKeyValidityPS) +
                      sizeof (struct TALER_AuditorSignatureP))))) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
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
    return GNUNET_SYSERR;
  }
  sigs = (const struct TALER_AuditorSignatureP *) &af[1];
  dki = (const struct TALER_DenominationKeyValidityPS *) &sigs[len];
  ret = aic->it (aic->it_cls,
                 &af->apub,
                 &af->mpub,
                 len,
                 sigs,
                 dki);
  GNUNET_free (af);
  return ret;
}


/**
 * Call @a it with information for each auditor found in the @a mint_base_dir.
 *
 * @param mint_base_dir base directory for the mint,
 *                      the signing keys must be in the #TALER_MINTDB_DIR_DENOMINATION_KEYS
 *                      subdirectory
 * @param it function to call with auditor information
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_MINTDB_auditor_iterate (const char *mint_base_dir,
                              TALER_MINTDB_AuditorIterator it,
                              void *it_cls)
{
  char *dir;
  struct AuditorIterateContext aic;
  int ret;

  GNUNET_asprintf (&dir,
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_AUDITORS,
                   mint_base_dir);
  aic.it = it;
  aic.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (dir,
                                    &auditor_iter,
                                    &aic);
  GNUNET_free (dir);
  return ret;
}


/**
 * Write auditor information to the given file.
 *
 * @param filename the file where to write the auditor information to
 * @param apub the auditor's public key
 * @param asigs the auditor's signatures, array of length @a dki_len
 * @param mpub the mint's public key (as expected by the auditor)
 * @param dki_len length of @a dki
 * @param dki array of denomination coin data signed by the auditor
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_MINTDB_auditor_write (const char *filename,
                            const struct TALER_AuditorPublicKeyP *apub,
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
 cleanup:
  eno = errno;
  if (NULL != fh)
    (void) GNUNET_DISK_file_close (fh);
  errno = eno;
  return ret;
}


/* end of mintdb_keyio.c */
