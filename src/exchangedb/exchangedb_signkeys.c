/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Inria & GNUnet e.V.

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
 * @file exchangedb/exchangedb_signkeys.c
 * @brief I/O operations for the Exchange's private online signing keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


/**
 * Closure for the #signkeys_iterate_dir_iter().
 */
struct SignkeysIterateContext
{

  /**
   * Function to call on each signing key.
   */
  TALER_EXCHANGEDB_SigningKeyIterator it;

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
  struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP issue;

  nread = GNUNET_DISK_fn_read (filename,
                               &issue,
                               sizeof (struct
                                       TALER_EXCHANGEDB_PrivateSigningKeyInformationP));
  if (nread != sizeof (struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid signkey file `%s': wrong size (%d, expected %u)\n",
                filename,
                (int) nread,
                (unsigned int) sizeof (struct
                                       TALER_EXCHANGEDB_PrivateSigningKeyInformationP));
    return GNUNET_OK;
  }
  if (0 == GNUNET_TIME_absolute_get_remaining
        (GNUNET_TIME_absolute_ntoh (issue.issue.expire)).rel_value_us)
  {
    if (0 != unlink (filename))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "unlink",
                                filename);
      return GNUNET_OK; /* yes, we had an error, but continue to iterate anyway */
    }
    /* Expired file deleted, continue to iterate -without- calling iterator
       as this key is expired */
    return GNUNET_OK;
  }
  return skc->it (skc->it_cls,
                  filename,
                  &issue);
}


/**
 * Call @a it for each signing key found in the @a exchange_base_dir.
 *
 * @param exchange_base_dir base directory for the exchange,
 *                      the signing keys must be in the #TALER_EXCHANGEDB_DIR_SIGNING_KEYS
 *                      subdirectory
 * @param it function to call on each signing key
 * @param it_cls closure for @a it
 * @return number of files found (may not match
 *         number of keys given to @a it as malformed
 *         files are simply skipped), -1 on error
 */
int
TALER_EXCHANGEDB_signing_keys_iterate (const char *exchange_base_dir,
                                       TALER_EXCHANGEDB_SigningKeyIterator it,
                                       void *it_cls)
{
  char *signkey_dir;
  struct SignkeysIterateContext skc;
  int ret;

  GNUNET_asprintf (&signkey_dir,
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_SIGNING_KEYS,
                   exchange_base_dir);
  skc.it = it;
  skc.it_cls = it_cls;
  ret = GNUNET_DISK_directory_scan (signkey_dir,
                                    &signkeys_iterate_dir_iter,
                                    &skc);
  GNUNET_free (signkey_dir);
  return ret;
}


/**
 * Obtain the name of the directory we use to store signing
 * keys created at time @a start.
 *
 * @param exchange_directory base director where we store key material
 * @param start time at which we create the signing key
 * @return name of the directory we should use, basically "$EXCHANGEDIR/$TIME/";
 *         (valid until next call to this function)
 */
static char *
get_signkey_file (const char *exchange_directory,
                  struct GNUNET_TIME_Absolute start)
{
  char *fn;

  GNUNET_asprintf (&fn,
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_SIGNING_KEYS
                   DIR_SEPARATOR_STR "%llu",
                   exchange_directory,
                   (unsigned long long) start.abs_value_us);
  return fn;
}


/**
 * Exports a signing key to the given file.
 *
 * @param exchange_base_dir base directory for the keys
 * @param start start time of the validity for the key
 * @param ski the signing key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_EXCHANGEDB_signing_key_write (const char *exchange_base_dir,
                                    struct GNUNET_TIME_Absolute start,
                                    const struct
                                    TALER_EXCHANGEDB_PrivateSigningKeyInformationP
                                    *ski)
{
  char *skf;
  ssize_t nwrite;

  skf = get_signkey_file (exchange_base_dir,
                          start);
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create_for_file (skf))
    return GNUNET_SYSERR;
  nwrite = GNUNET_DISK_fn_write (skf,
                                 ski,
                                 sizeof (struct
                                         TALER_EXCHANGEDB_PrivateSigningKeyInformationP),
                                 GNUNET_DISK_PERM_USER_WRITE
                                 | GNUNET_DISK_PERM_USER_READ);
  if (sizeof (struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP) != nwrite)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "write",
                              skf);
    GNUNET_free (skf);
    return GNUNET_SYSERR;
  }
  GNUNET_free (skf);
  return GNUNET_OK;
}

/* end of exchangedb_signkeys.c */
