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
 * @file include/taler_exchangedb_lib.h
 * @brief IO operations for the exchange's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGEDB_LIB_H
#define TALER_EXCHANGEDB_LIB_H

#include "taler_signatures.h"

/**
 * Subdirectroy under the exchange's base directory which contains
 * the exchange's signing keys.
 */
#define TALER_EXCHANGEDB_DIR_SIGNING_KEYS "signkeys"

/**
 * Subdirectory under the exchange's base directory which contains
 * the exchange's denomination keys.
 */
#define TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS "denomkeys"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief On disk format used for a exchange signing key.  Signing keys are used
 * by the exchange to affirm its messages, but not to create coins.
 * Includes the private key followed by the public information about
 * the signing key.
 */
struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP
{
  /**
   * Private key part of the exchange's signing key.
   */
  struct TALER_ExchangePrivateKeyP signkey_priv;

  /**
   * Public information about a exchange signing key.
   */
  struct TALER_ExchangeSigningKeyValidityPS issue;
};


/**
 * Information about a denomination key.
 */
struct TALER_EXCHANGEDB_DenominationKeyInformationP
{

  /**
   * Signature over this struct to affirm the validity of the key.
   */
  struct TALER_MasterSignatureP signature;

  /**
   * Signed properties of the denomination key.
   */
  struct TALER_DenominationKeyValidityPS properties;
};


GNUNET_NETWORK_STRUCT_END


/**
 * @brief All information about a denomination key (which is used to
 * sign coins into existence).
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation
{
  /**
   * The private key of the denomination.  Will be NULL if the private
   * key is not available (this is the case after the key has expired
   * for signing coins, but is still valid for depositing coins).
   */
  struct TALER_DenominationPrivateKey denom_priv;

  /**
   * Decoded denomination public key (the hash of it is in
   * @e issue, but we sometimes need the full public key as well).
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Signed public information about a denomination key.
   */
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
};


/**
 * @brief Iterator over signing keys.
 *
 * @param cls closure
 * @param filename name of the file the key came from
 * @param ski the sign key
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_EXCHANGEDB_SigningKeyIterator)(void *cls,
                                       const char *filename,
                                       const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski);


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
                                       void *it_cls);


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
                                    const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski);


/**
 * @brief Iterator over denomination keys.
 *
 * @param cls closure
 * @param dki the denomination key
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_EXCHANGEDB_DenominationKeyIterator)(void *cls,
                                            const char *alias,
                                            const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki);


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
                                            void *it_cls);


/**
 * Exports a denomination key to the given file.
 *
 * @param filename the file where to write the denomination key
 * @param dki the denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_EXCHANGEDB_denomination_key_write (const char *filename,
                                         const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki);


/**
 * Import a denomination key from the given file.
 *
 * @param filename the file to import the key from
 * @param[out] dki set to the imported denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_EXCHANGEDB_denomination_key_read (const char *filename,
                                        struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki);


/**
 * @brief Iterator over auditor information.
 *
 * @param cls closure
 * @param apub the auditor's public key
 * @param auditor_url URL of the auditor
 * @param mpub the exchange's public key (as expected by the auditor)
 * @param dki_len length of @a asig and @a dki arrays
 * @param asigs array of the auditor's signatures over the @a dks, of length @a dki_len
 * @param dki array of denomination coin data signed by the auditor, of length @a dki_len
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_EXCHANGEDB_AuditorIterator)(void *cls,
                                    const struct TALER_AuditorPublicKeyP *apub,
                                    const char *auditor_url,
                                    const struct TALER_MasterPublicKeyP *mpub,
                                    unsigned int dki_len,
                                    const struct TALER_AuditorSignatureP *asigs,
                                    const struct TALER_DenominationKeyValidityPS *dki);


/**
 * Call @a it with information for each auditor found in the
 * directory with auditor information as specified in @a cfg.
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
                                  void *it_cls);


/**
 * Write auditor information to the given file.
 *
 * @param filename the file where to write the auditor information to
 * @param apub the auditor's public key
 * @param auditor_url the URL of the auditor
 * @param asigs the auditor's signatures, array of length @a dki_len
 * @param mpub the exchange's public key (as expected by the auditor)
 * @param dki_len length of @a dki and @a asigs arrays
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
                                const struct TALER_DenominationKeyValidityPS *dki);


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return NULL on failure
 */
struct TALER_EXCHANGEDB_Plugin *
TALER_EXCHANGEDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown the plugin.
 *
 * @param plugin plugin to unload
 */
void
TALER_EXCHANGEDB_plugin_unload (struct TALER_EXCHANGEDB_Plugin *plugin);


#endif
