/*
  This file is part of TALER
  Copyright (C) 2014-2017 Inria & GNUnet e.V.

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
 * @file exchangedb/exchangedb_denomkeys.c
 * @brief I/O operations for the Exchange's denomination private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Contents of a file with a revocation certificate.
 */
struct RevocationFileP
{

  /**
   * Hash of the denomination public key being revoked.
   */
  struct GNUNET_HashCode denom_hash;

  /**
   * Master signature over the revocation, must match purpose
   * #TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED.
   */
  struct TALER_MasterSignatureP msig;
};

GNUNET_NETWORK_STRUCT_END


/**
 * Mark the given denomination key as revoked and request the wallets
 * to initiate /payback.
 *
 * @param revocation_dir where to write the revocation certificate
 * @param denom_hash hash of the denomination key to revoke
 * @param mpriv master private key to sign with
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_EXCHANGEDB_denomination_key_revoke (const char *revocation_dir,
                                          const struct GNUNET_HashCode *denom_hash,
                                          const struct TALER_MasterPrivateKeyP *mpriv)
{
  struct TALER_MasterDenominationKeyRevocationPS rm;
  char *fn;
  int ret;
  struct RevocationFileP rd;

  ret = GNUNET_SYSERR;
  GNUNET_asprintf (&fn,
                   "%s" DIR_SEPARATOR_STR                   
                   "%s.rev",
                   revocation_dir,
                   GNUNET_h2s_full (denom_hash));
  rm.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED);
  rm.purpose.size = htonl (sizeof (rm));
  rm.h_denom_pub = *denom_hash;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&mpriv->eddsa_priv,
                                           &rm.purpose,
                                           &rd.msig.eddsa_signature));
  rd.denom_hash = *denom_hash;
  if (sizeof (rd) !=
      GNUNET_DISK_fn_write (fn,
			    &rd,
			    sizeof (rd),
			    GNUNET_DISK_PERM_USER_READ | GNUNET_DISK_PERM_USER_WRITE))
    ret = GNUNET_SYSERR;
  else
    ret = GNUNET_OK;
  GNUNET_free (fn);
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
TALER_EXCHANGEDB_denomination_key_read (const char *filename,
                                        struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  uint64_t size;
  size_t offset;
  void *data;
  struct GNUNET_CRYPTO_RsaPrivateKey *priv;

  if (GNUNET_OK !=
      GNUNET_DISK_file_size (filename,
                             &size,
                             GNUNET_YES,
                             GNUNET_YES))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping inaccessable denomination key file `%s'\n",
                filename);
    return GNUNET_SYSERR;
  }
  offset = sizeof (struct TALER_EXCHANGEDB_DenominationKeyInformationP);
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
  if (0 == GNUNET_TIME_absolute_get_remaining
      (GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_withdraw)).rel_value_us)
  {
    /* FIXME: #5536: we should delete this file, the
       private key is no longer needed (and return SYSERR!) */
  }
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
TALER_EXCHANGEDB_denomination_key_write (const char *filename,
                                         const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
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
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create_for_file (filename))
    return GNUNET_SYSERR;
  if (NULL == (fh = GNUNET_DISK_file_open
               (filename,
                GNUNET_DISK_OPEN_WRITE | GNUNET_DISK_OPEN_CREATE | GNUNET_DISK_OPEN_TRUNCATE,
                GNUNET_DISK_PERM_USER_READ | GNUNET_DISK_PERM_USER_WRITE)))
    goto cleanup;
  wsize = sizeof (struct TALER_EXCHANGEDB_DenominationKeyInformationP);
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
  TALER_EXCHANGEDB_DenominationKeyIterator it;

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
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation issue;
  int ret;

  memset (&issue, 0, sizeof (issue));
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_denomination_key_read (filename,
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
 * Function called on each subdirectory in the #TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS.  Will
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
 * Call @a it for each denomination key found in the @a exchange_base_dir.
 *
 * @param exchange_base_dir base directory for the exchange,
 *                      the signing keys must be in the #TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS
 *                      subdirectory
 * @param it function to call on each denomination key found
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_EXCHANGEDB_denomination_keys_iterate (const char *exchange_base_dir,
                                            TALER_EXCHANGEDB_DenominationKeyIterator it,
                                            void *it_cls)
{
  char *dir;
  struct DenomkeysIterateContext dic;
  int ret;

  GNUNET_asprintf (&dir,
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS,
                   exchange_base_dir);
  dic.it = it;
  dic.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (dir,
                                    &denomkeys_iterate_topdir_iter,
                                    &dic);
  GNUNET_free (dir);
  return ret;
}


/**
 * Closure for #revocations_iterate_cb().
 */
struct RevocationsIterateContext
{

  /**
   * Function to call on each revoked denomination key.
   */
  TALER_EXCHANGEDB_RevocationIterator it;

  /**
   * Closure for @e it.
   */
  void *it_cls;
  
  /**
   * Master public key to use to validate revocations.
   */
  const struct TALER_MasterPublicKeyP *master_pub;

};


/**
 * Decode the revocation certificate in the given file @a filename and call
 * the callback in @a cls with the information.
 *
 * @param cls the `struct RevocationsIterateContext *`
 * @param filename name of a file that should contain
 *                 a denomination key
 * @return #GNUNET_OK to continue to iterate
 *         #GNUNET_NO to abort iteration with success
 *         #GNUNET_SYSERR to abort iteration with failure
 */
static int
revocations_iterate_cb (void *cls,
			const char *filename)
{
  struct RevocationsIterateContext *ric = cls;
  struct RevocationFileP rf;
  struct TALER_MasterDenominationKeyRevocationPS rm;

  /* Check if revocation is valid... */
  if (sizeof (rm) !=
      GNUNET_DISK_fn_read (filename,
			   &rf,
			   sizeof (rf)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		_("Invalid revocation file `%s' found and ignored (bad size)\n"),
		filename);
    return GNUNET_OK;
  }
  rm.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED);
  rm.purpose.size = htonl (sizeof (rm));
  rm.h_denom_pub = rf.denom_hash;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED,
				  &rm.purpose,
				  &rf.msig.eddsa_signature,
				  &ric->master_pub->eddsa_pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		_("Invalid revocation file `%s' found and ignored (bad signature)\n"),
		filename);
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
	      "Denomination key `%s' was revoked!\n",
	      GNUNET_h2s (&rm.h_denom_pub));
  return ric->it (ric->it_cls,
		  &rm.h_denom_pub,
		  &rf.msig);
}


/**
 * Call @a it for each revoked denomination key found in the @a revocation_dir.
 *
 * @param revocation_dir base directory where revocations are stored
 * @param master_pub master public key (used to check revocations)
 * @param it function to call on each revoked denomination key found
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_EXCHANGEDB_revocations_iterate (const char *revocation_dir,
				      const struct TALER_MasterPublicKeyP *master_pub,
				      TALER_EXCHANGEDB_RevocationIterator it,
				      void *it_cls)
{
  struct RevocationsIterateContext ric = {
    .it = it,
    .it_cls = it_cls,
    .master_pub = master_pub
  };

  return GNUNET_DISK_directory_scan (revocation_dir,
				     &revocations_iterate_cb,
				     &ric);
}


/* end of exchangedb_denomkeys.c */
