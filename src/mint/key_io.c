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
 * @file mint/key_io.c
 * @brief I/O operations for the Mint's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 *
 * TODO:
 * - revisit IO with respect to variable-size RSA keys!
 */
#include "platform.h"
#include "key_io.h"


/**
 * Closure for the #signkeys_iterate_dir_iter().
 */
struct SignkeysIterateContext
{

  /**
   * Function to call on each signing key.
   */
  TALER_MINT_SignkeyIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;
};


/**
 * Function called on each file in the directory with
 * our signing keys. Parses the file and calls the
 * iterator from @a cls.
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
  struct TALER_MINT_SignKeyIssuePriv issue;

  nread = GNUNET_DISK_fn_read (filename,
                               &issue,
                               sizeof (struct TALER_MINT_SignKeyIssuePriv));
  if (nread != sizeof (struct TALER_MINT_SignKeyIssuePriv))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid signkey file: `%s'\n",
                filename);
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
 *                      the signing keys must be in the #DIR_SIGNKEYS
 *                      subdirectory
 * @param it function to call on each signing key
 * @param it_cls closure for @a it
 * @return number of files found (may not match
 *         number of keys given to @a it as malformed
 *         files are simply skipped), -1 on error
 */
int
TALER_MINT_signkeys_iterate (const char *mint_base_dir,
                             TALER_MINT_SignkeyIterator it,
                             void *it_cls)
{
  char *signkey_dir;
  struct SignkeysIterateContext skc;
  int ret;

  GNUNET_asprintf (&signkey_dir,
                   "%s" DIR_SEPARATOR_STR DIR_SIGNKEYS,
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
 * @param[OUT] dki set to the imported denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_read_denom_key (const char *filename,
                           struct TALER_MINT_DenomKeyIssuePriv *dki)
{
  uint64_t size;
  size_t offset;
  void *data;
  struct GNUNET_CRYPTO_rsa_PrivateKey *priv;
  int ret;

  ret = GNUNET_SYSERR;
  data = NULL;
  offset = sizeof (struct TALER_MINT_DenomKeyIssuePriv)
      - offsetof (struct TALER_MINT_DenomKeyIssuePriv,
                  issue.signature);
  if (GNUNET_OK != GNUNET_DISK_file_size (filename,
                                          &size,
                                          GNUNET_YES,
                                          GNUNET_YES))
    goto cleanup;
  if (size <= offset)
  {
    GNUNET_break (0);
    goto cleanup;
  }
  data = GNUNET_malloc (size);
  if (size != GNUNET_DISK_fn_read (filename,
                                   data,
                                   size))
    goto cleanup;
  if (NULL == (priv = GNUNET_CRYPTO_rsa_private_key_decode (data + offset,
                                                            size - offset)))
    goto cleanup;
  dki->denom_priv = priv;
  memcpy (&dki->issue.signature, data, offset);
  ret = GNUNET_OK;

 cleanup:
  GNUNET_free_non_null (data);
  return ret;
}


/**
 * Exports a denomination key to the given file
 *
 * @param filename the file where to write the denomination key
 * @param dki the denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_MINT_write_denom_key (const char *filename,
                            const struct TALER_MINT_DenomKeyIssuePriv *dki)
{
  char *priv_enc;
  size_t priv_enc_size;
  struct GNUNET_DISK_FileHandle *fh;
  ssize_t wrote;
  size_t wsize;
  int ret;

  fh = NULL;
  priv_enc_size = GNUNET_CRYPTO_rsa_private_key_encode (dki->denom_priv,
                                                        &priv_enc);
  ret = GNUNET_SYSERR;
  if (NULL == (fh = GNUNET_DISK_file_open
               (filename,
                GNUNET_DISK_OPEN_WRITE | GNUNET_DISK_OPEN_CREATE | GNUNET_DISK_OPEN_TRUNCATE,
                GNUNET_DISK_PERM_USER_READ | GNUNET_DISK_PERM_USER_WRITE)))
    goto cleanup;
  wsize = sizeof (struct TALER_MINT_DenomKeyIssuePriv)
      - offsetof (struct TALER_MINT_DenomKeyIssuePriv,
                  issue.signature);
  if (GNUNET_SYSERR == (wrote = GNUNET_DISK_file_write (fh,
                                                        &dki->issue.signature,
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
  TALER_MINT_DenomkeyIterator it;

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
  struct TALER_MINT_DenomKeyIssuePriv issue;

  if (GNUNET_OK !=
      TALER_MINT_read_denom_key (filename,
                                 &issue))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid denomkey file: '%s'\n",
                filename);
    return GNUNET_OK;
  }
  return dic->it (dic->it_cls,
                  dic->alias,
                  &issue);
}


/**
 * Function called on each subdirectory in the #DIR_DENOMKEYS.  Will
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
 *                      the signing keys must be in the #DIR_DENOMKEYS
 *                      subdirectory
 * @param it function to call on each denomination key found
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_MINT_denomkeys_iterate (const char *mint_base_dir,
                              TALER_MINT_DenomkeyIterator it,
                              void *it_cls)
{
  char *dir;
  size_t len;
  struct DenomkeysIterateContext dic;
  int ret;

  GNUNET_asprintf (&dir,
                   "%s" DIR_SEPARATOR_STR DIR_DENOMKEYS,
                   mint_base_dir);
  dic.it = it;
  dic.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (dir,
                                    &denomkeys_iterate_topdir_iter,
                                    &dic);
  GNUNET_free (dir);
  return ret;
}


/* end of key_io.c */
