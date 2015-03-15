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
 */
#include "platform.h"
#include "key_io.h"


struct SignkeysIterateContext
{
  TALER_MINT_SignkeyIterator it;
  void *it_cls;
};


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
 * Import a denomination key from the given file
 *
 * @param filename the file to import the key from
 * @param dki pointer to return the imported denomination key
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


struct DenomkeysIterateContext
{
  const char *alias;
  TALER_MINT_DenomkeyIterator it;
  void *it_cls;
};


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
  return dic->it (dic->it_cls, dic->alias, &issue);
}


static int
denomkeys_iterate_topdir_iter (void *cls,
                               const char *filename)
{
  struct DenomkeysIterateContext *dic = cls;

  dic->alias = GNUNET_STRINGS_get_short_name (filename);

  // FIXME: differentiate between error case and normal iteration abortion
  if (0 > GNUNET_DISK_directory_scan (filename,
                                      &denomkeys_iterate_keydir_iter,
                                      dic))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


int
TALER_MINT_denomkeys_iterate (const char *mint_base_dir,
                              TALER_MINT_DenomkeyIterator it, void *cls)
{
  char *dir;
  size_t len;
  struct DenomkeysIterateContext dic;

  len = GNUNET_asprintf (&dir,
                         "%s" DIR_SEPARATOR_STR DIR_DENOMKEYS,
                         mint_base_dir);
  GNUNET_assert (len > 0);

  dic.it = it;
  dic.it_cls = cls;

  // scan over alias dirs
  return GNUNET_DISK_directory_scan (dir,
                                     &denomkeys_iterate_topdir_iter,
                                     &dic);
}



/* end of mint_common.c */
