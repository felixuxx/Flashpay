/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-keyup.c
 * @brief Update the exchange's keys for coins and online signing keys,
 *        using the exchange's offline master key.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_exchangedb_lib.h"


/**
 * When generating filenames from a cryptographic hash, we do not use all 512
 * bits but cut off after this number of characters (in base32-encoding).
 * Base32 is 5 bit per character, and given that we have very few coin types,
 * at 100 bits the chance of collision (by accident over such a tiny set) is
 * negligible. (Also, some file-systems do not support very long file names.)
 */
#define HASH_CUTOFF 20


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Struct with all of the meta data about a denomination.  Hashed
 * to generate a unique directory name per coin type.
 */
struct DenominationNBOP
{
  /**
   * How long are the signatures legally valid?
   */
  struct GNUNET_TIME_RelativeNBO duration_legal;

  /**
   * How long can the coins be spend?
   */
  struct GNUNET_TIME_RelativeNBO duration_spend;

  /**
   * How long can coins be withdrawn (generated)?
   */
  struct GNUNET_TIME_RelativeNBO duration_withdraw;

  /**
   * What is the value of each coin?
   */
  struct TALER_AmountNBO value;

  /**
   * What is the fee charged for withdrawal?
   */
  struct TALER_AmountNBO fee_withdraw;

  /**
   * What is the fee charged for deposits?
   */
  struct TALER_AmountNBO fee_deposit;

  /**
   * What is the fee charged for melting?
   */
  struct TALER_AmountNBO fee_refresh;

  /**
   * What is the fee charged for refunds?
   */
  struct TALER_AmountNBO fee_refund;

  /**
   * Key size (in NBO).
   */
  uint32_t rsa_keysize;
};

GNUNET_NETWORK_STRUCT_END

/**
 * Set of all of the parameters that characterize a denomination.
 */
struct DenominationParameters
{

  /**
   * How long are the signatures legally valid?  Should be
   * significantly larger than @e duration_spend (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_legal;

  /**
   * How long can the coins be spend?  Should be significantly
   * larger than @e duration_withdraw (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_spend;

  /**
   * How long can coins be withdrawn (generated)?  Should be small
   * enough to limit how many coins will be signed into existence with
   * the same key, but large enough to still provide a reasonable
   * anonymity set.
   */
  struct GNUNET_TIME_Relative duration_withdraw;

  /**
   * What is the value of each coin?
   */
  struct TALER_Amount value;

  /**
   * What is the fee charged for withdrawal?
   */
  struct TALER_Amount fee_withdraw;

  /**
   * What is the fee charged for deposits?
   */
  struct TALER_Amount fee_deposit;

  /**
   * What is the fee charged for melting?
   */
  struct TALER_Amount fee_refresh;

  /**
   * What is the fee charged for refunds?
   */
  struct TALER_Amount fee_refund;

  /**
   * Time at which this coin is supposed to become valid.
   */
  struct GNUNET_TIME_Absolute anchor;

  /**
   * Length of the RSA key (in bits).
   */
  uint32_t rsa_keysize;
};


/**
 * How much should coin creation (@e duration_withdraw) duration overlap
 * with the next denomination?  Basically, the starting time of two
 * denominations is always @e duration_withdraw - #duration_overlap apart.
 */
static struct GNUNET_TIME_Relative duration_overlap;

/**
 * The configured currency.
 */
static char *currency;

/**
 * Filename of the master private key.
 */
static char *masterkeyfile;

/**
 * Filename where to write denomination key signing
 * requests for the auditor (optional, can be NULL).
 */
static char *auditorrequestfile;

/**
 * Handle for writing the output for the auditor.
 */
static FILE *auditor_output_file;

/**
 * Director of the exchange, containing the keys.
 */
static char *exchange_directory;

/**
 * Directory where we should write the wire transfer fee structure.
 */
static char *feedir;

/**
 * Handle to the exchange's configuration
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Time when the key update is executed.
 * Either the actual current time, or a pretended time.
 */
static struct GNUNET_TIME_Absolute now;

/**
 * The time for the key update, as passed by the user
 * on the command line.
 */
static struct GNUNET_TIME_Absolute now_tmp;

/**
 * Master private key of the exchange.
 */
static struct TALER_MasterPrivateKeyP master_priv;

/**
 * Master public key of the exchange.
 */
static struct TALER_MasterPublicKeyP master_public_key;

/**
 * Until what time do we provide keys?
 */
static struct GNUNET_TIME_Absolute lookahead_sign_stamp;

/**
 * Largest duration for spending of any key.
 */
static struct GNUNET_TIME_Relative max_duration_spend;

/**
 * Revoke denomination key identified by this hash (if non-zero).
 */
static struct GNUNET_HashCode revoke_dkh;

/**
 * Which RSA key size should we use for replacement keys after revocation?
 * (Useful because maybe that's the one option one might usefully want to
 * change when replacing a key.)
 */
static unsigned int replacement_key_size = 2048;

/**
 * Return value from main().
 */
static int global_ret;


#include "key-helper.c"

/**
 * Hash the data defining a denomination type.  Exclude information that may
 * not be the same for all instances of the denomination's type (i.e. the
 * anchor, overlap).
 *
 * @param p denomination parameters to convert to a hash
 * @param[out] hash set to the hash matching @a p
 */
static void
hash_denomination_parameters (const struct DenominationParameters *p,
                              struct GNUNET_HashCode *hash)
{
  struct DenominationNBOP p_nbo;

  memset (&p_nbo,
          0,
          sizeof (struct DenominationNBOP));
  p_nbo.duration_spend = GNUNET_TIME_relative_hton (p->duration_spend);
  p_nbo.duration_legal = GNUNET_TIME_relative_hton (p->duration_legal);
  p_nbo.duration_withdraw = GNUNET_TIME_relative_hton (p->duration_withdraw);
  TALER_amount_hton (&p_nbo.value,
                     &p->value);
  TALER_amount_hton (&p_nbo.fee_withdraw,
                     &p->fee_withdraw);
  TALER_amount_hton (&p_nbo.fee_deposit,
                     &p->fee_deposit);
  TALER_amount_hton (&p_nbo.fee_refresh,
                     &p->fee_refresh);
  TALER_amount_hton (&p_nbo.fee_refund,
                     &p->fee_refund);
  p_nbo.rsa_keysize = htonl (p->rsa_keysize);
  GNUNET_CRYPTO_hash (&p_nbo,
                      sizeof (struct DenominationNBOP),
                      hash);
}


/**
 * Obtain the name of the directory we should use to store denominations of
 * the given type.  The directory name has the format
 * "$EXCHANGEDIR/$VALUE/$HASH/" where "$VALUE" represents the value of the
 * coins and "$HASH" encodes all of the denomination's parameters, generating
 * a unique string for each type of denomination.  Note that the "$HASH"
 * includes neither the absolute creation time nor the key of the
 * denomination, thus the files in the subdirectory really just refer to the
 * same type of denominations, not the same denomination.
 *
 * @param p denomination parameters to convert to a directory name
 * @return directory name (valid until next call to this function)
 */
static const char *
get_denomination_dir (const struct DenominationParameters *p)
{
  static char dir[4096];
  struct GNUNET_HashCode hash;
  char *hash_str;
  char *val_str;

  hash_denomination_parameters (p,
                                &hash);
  hash_str = GNUNET_STRINGS_data_to_string_alloc (&hash,
                                                  sizeof (struct
                                                          GNUNET_HashCode));
  GNUNET_assert (NULL != hash_str);
  GNUNET_assert (HASH_CUTOFF <= strlen (hash_str) + 1);
  hash_str[HASH_CUTOFF] = 0;

  val_str = TALER_amount_to_string (&p->value);
  GNUNET_assert (NULL != val_str);
  for (size_t i = 0; i < strlen (val_str); i++)
    if ( (':' == val_str[i]) ||
         ('.' == val_str[i]) )
      val_str[i] = '_';

  GNUNET_snprintf (dir,
                   sizeof (dir),
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS
                   DIR_SEPARATOR_STR "%s-%s",
                   exchange_directory,
                   val_str,
                   hash_str);
  GNUNET_free (hash_str);
  GNUNET_free (val_str);
  return dir;
}


/**
 * Obtain the name of the file we would use to store the key
 * information for a denomination of the given type @a p and validity
 * start time @a start
 *
 * @param p parameters for the denomination
 * @param start when would the denomination begin to be issued
 * @return name of the file to use for this denomination
 *         (valid until next call to this function)
 */
static const char *
get_denomination_type_file (const struct DenominationParameters *p,
                            struct GNUNET_TIME_Absolute start)
{
  static char filename[4096];
  const char *dir;

  dir = get_denomination_dir (p);
  GNUNET_snprintf (filename,
                   sizeof (filename),
                   "%s" DIR_SEPARATOR_STR "%llu",
                   dir,
                   (unsigned long long) start.abs_value_us);
  return filename;
}


/**
 * Get the latest key file from a past run of the key generation
 * tool.  Used to calculate the starting time for the keys we
 * generate during this invocation.  This function is used to
 * handle both signing keys and denomination keys, as in both cases
 * the filenames correspond to the timestamps we need.
 *
 * @param cls closure, a `struct GNUNET_TIME_Absolute *`, updated
 *                     to contain the highest timestamp (below #now)
 *                     that was found
 * @param filename complete filename (absolute path)
 * @return #GNUNET_OK (to continue to iterate)
 */
static int
get_anchor_iter (void *cls,
                 const char *filename)
{
  struct GNUNET_TIME_Absolute *anchor = cls;
  struct GNUNET_TIME_Absolute stamp;
  const char *base;
  char *end = NULL;
  long long int bval;

  base = GNUNET_STRINGS_get_short_name (filename);
  bval = strtoll (base,
                  &end,
                  10);
  if ( (NULL == end) ||
       (0 != *end) ||
       (0 > bval) )
  {
    fprintf (stderr,
             "Ignoring unexpected file `%s'.\n",
             filename);
    return GNUNET_OK;
  }
  stamp.abs_value_us = (uint64_t) bval;
  *anchor = GNUNET_TIME_absolute_max (stamp,
                                      *anchor);
  return GNUNET_OK;
}


/**
 * Get the timestamp where the first new key should be generated.
 * Relies on correctly named key files (as we do not parse them,
 * but just look at the filenames to "guess" at their contents).
 *
 * @param dir directory that should contain the existing keys
 * @param duration how long is one key valid (for signing)?
 * @param overlap what's the overlap between the keys validity period?
 * @param[out] anchor the timestamp where the first new key should be generated
 */
static void
get_anchor (const char *dir,
            struct GNUNET_TIME_Relative duration,
            struct GNUNET_TIME_Relative overlap,
            struct GNUNET_TIME_Absolute *anchor)
{
  GNUNET_assert (0 == duration.rel_value_us % 1000000);
  GNUNET_assert (0 == overlap.rel_value_us % 1000000);
  if (GNUNET_YES !=
      GNUNET_DISK_directory_test (dir,
                                  GNUNET_YES))
  {
    *anchor = now;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No existing keys found, starting with fresh key set.\n");
    return;
  }
  *anchor = GNUNET_TIME_UNIT_ZERO_ABS;
  if (-1 ==
      GNUNET_DISK_directory_scan (dir,
                                  &get_anchor_iter,
                                  anchor))
  {
    *anchor = now;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No existing keys found, starting with fresh key set.\n");
    return;
  }

  if ((GNUNET_TIME_absolute_add (*anchor,
                                 duration)).abs_value_us < now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Existing keys are way too old, starting with fresh key set.\n");
    *anchor = now;
  }
  else if (anchor->abs_value_us != now.abs_value_us)
  {
    *anchor = GNUNET_TIME_absolute_add (*anchor,
                                        duration);
    *anchor = GNUNET_TIME_absolute_subtract (*anchor,
                                             overlap);
  }

  /* anchor is now the stamp where we need to create a new key */
}


/**
 * Create a exchange signing key (for signing exchange messages, not for
 * signing coins) and assert its correctness by signing it with the master
 * key.
 *
 * @param start start time of the validity period for the key
 * @param duration how long should the key be valid
 * @param end when do all signatures by this key expire
 * @param[out] pi set to the signing key information
 */
static void
create_signkey_issue_priv (
  struct GNUNET_TIME_Absolute start,
  struct GNUNET_TIME_Relative duration,
  struct GNUNET_TIME_Absolute end,
  struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *pi)
{
  struct TALER_ExchangeSigningKeyValidityPS *issue = &pi->issue;

  GNUNET_CRYPTO_eddsa_key_create (&pi->signkey_priv.eddsa_priv);
  issue->master_public_key = master_public_key;
  issue->start = GNUNET_TIME_absolute_hton (start);
  issue->expire = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (start,
                                                                       duration));
  issue->end = GNUNET_TIME_absolute_hton (end);
  GNUNET_CRYPTO_eddsa_key_get_public (&pi->signkey_priv.eddsa_priv,
                                      &issue->signkey_pub.eddsa_pub);
  issue->purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  issue->purpose.size = htonl (sizeof (struct
                                       TALER_ExchangeSigningKeyValidityPS));
  GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                            issue,
                            &pi->master_sig.eddsa_signature);
}


/**
 * Generate signing keys starting from the last key found to
 * the lookahead time.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
exchange_keys_update_signkeys (void)
{
  struct GNUNET_TIME_Relative signkey_duration;
  struct GNUNET_TIME_Relative legal_duration;
  struct GNUNET_TIME_Absolute anchor;
  char *signkey_dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "SIGNKEY_DURATION",
                                           &signkey_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SIGNKEY_DURATION");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "LEGAL_DURATION",
                                           &legal_duration))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LEGAL_DURATION",
                               "fails to specify valid timeframe");
    return GNUNET_SYSERR;
  }
  if (signkey_duration.rel_value_us > legal_duration.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LEGAL_DURATION",
                               "Value given for LEGAL_DURATION must be longer than value for SIGNKEY_DURATION");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&signkey_duration);
  GNUNET_asprintf (&signkey_dir,
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_SIGNING_KEYS,
                   exchange_directory);
  /* make sure the directory exists */
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (signkey_dir))
  {
    fprintf (stderr,
             "Failed to create signing key directory\n");
    GNUNET_free (signkey_dir);
    return GNUNET_SYSERR;
  }

  get_anchor (signkey_dir,
              signkey_duration,
              GNUNET_TIME_UNIT_ZERO /* no overlap for signing keys */,
              &anchor);
  GNUNET_free (signkey_dir);

  while (anchor.abs_value_us < lookahead_sign_stamp.abs_value_us)
  {
    struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP signkey_issue;
    struct GNUNET_TIME_Absolute end;

    end = GNUNET_TIME_absolute_add (anchor,
                                    legal_duration);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Generating signing key for %s.\n",
                GNUNET_STRINGS_absolute_time_to_string (anchor));
    create_signkey_issue_priv (anchor,
                               signkey_duration,
                               end,
                               &signkey_issue);
    if (GNUNET_OK !=
        TALER_EXCHANGEDB_signing_key_write (exchange_directory,
                                            anchor,
                                            &signkey_issue))
      return GNUNET_SYSERR;
    anchor = GNUNET_TIME_absolute_add (anchor,
                                       signkey_duration);
  }
  return GNUNET_OK;
}


/**
 * Parse configuration for denomination type parameters.  Also determines
 * our anchor by looking at the existing denominations of the same type.
 *
 * @param ct section in the configuration file giving the denomination type parameters
 * @param[out] params set to the denomination parameters from the configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the configuration is invalid
 */
static int
get_denomination_type_params (const char *ct,
                              struct DenominationParameters *params)
{
  const char *dir;
  unsigned long long rsa_keysize;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_WITHDRAW",
                                           &params->duration_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_WITHDRAW");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_withdraw);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_SPEND",
                                           &params->duration_spend))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_SPEND");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_spend);
  max_duration_spend = GNUNET_TIME_relative_max (max_duration_spend,
                                                 params->duration_spend);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_LEGAL",
                                           &params->duration_legal))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_LEGAL");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_legal);
  if (duration_overlap.rel_value_us >=
      params->duration_withdraw.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "DURATION_OVERLAP",
                               "Value given for DURATION_OVERLAP must be smaller than value for DURATION_WITHDRAW!");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (kcfg,
                                             ct,
                                             "rsa_keysize",
                                             &rsa_keysize))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "rsa_keysize");
    return GNUNET_SYSERR;
  }
  if ( (rsa_keysize > 4 * 2048) ||
       (rsa_keysize < 1024) )
  {
    fprintf (stderr,
             "Given RSA keysize %llu outside of permitted range\n",
             rsa_keysize);
    return GNUNET_SYSERR;
  }
  params->rsa_keysize = (unsigned int) rsa_keysize;
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "VALUE",
                               &params->value))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_WITHDRAW",
                               &params->fee_withdraw))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_DEPOSIT",
                               &params->fee_deposit))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_REFRESH",
                               &params->fee_refresh))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "fee_refund",
                               &params->fee_refund))
  {
    return GNUNET_SYSERR;
  }

  dir = get_denomination_dir (params);
  get_anchor (dir,
              params->duration_withdraw,
              duration_overlap,
              &params->anchor);

  /**
   * The "anchor" is merely the latest denom key filename
   * converted to a GNUnet absolute time.
   */

  return GNUNET_OK;
}


/**
 * Initialize the private and public key information structure for
 * signing coins into existence.  Generates the private signing key
 * and signes it together with the denomination's meta data using the master
 * signing key.
 *
 * @param params parameters used to initialize the @a dki
 * @param[out] dki initialized according to @a params
 */
static void
create_denomkey_issue (
  const struct DenominationParameters *params,
  struct TALER_EXCHANGEDB_DenominationKey *dki)
{
  dki->denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (params->rsa_keysize);
  GNUNET_assert (NULL != dki->denom_priv.rsa_private_key);
  dki->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (
        dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &dki->issue.properties.denom_hash);
  dki->issue.properties.master = master_public_key;
  dki->issue.properties.start = GNUNET_TIME_absolute_hton (params->anchor);
  dki->issue.properties.expire_withdraw =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                         params->
                                                         duration_withdraw));
  dki->issue.properties.expire_deposit =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                         params->duration_spend));
  dki->issue.properties.expire_legal =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                         params->duration_legal));
  TALER_amount_hton (&dki->issue.properties.value,
                     &params->value);
  TALER_amount_hton (&dki->issue.properties.fee_withdraw,
                     &params->fee_withdraw);
  TALER_amount_hton (&dki->issue.properties.fee_deposit,
                     &params->fee_deposit);
  TALER_amount_hton (&dki->issue.properties.fee_refresh,
                     &params->fee_refresh);
  TALER_amount_hton (&dki->issue.properties.fee_refund,
                     &params->fee_refund);
  dki->issue.properties.purpose.purpose
    = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  dki->issue.properties.purpose.size
    = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                            &dki->issue.properties,
                            &dki->issue.signature.eddsa_signature);
}


/**
 * Write the @a denomkey_issue to file @a dkf and also (if applicable)
 * dump the properties to the #auditor_output_file.
 *
 * @param dkf where to write the @a denomkey_issue
 * @param denomkey_issue data to write
 * @return #GNUNET_OK on success
 */
static int
write_denomkey_issue (
  const char *dkf,
  const struct TALER_EXCHANGEDB_DenominationKey *denomkey_issue)
{
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_denomination_key_write (dkf,
                                               denomkey_issue))
  {
    fprintf (stderr,
             "Failed to write denomination key information to file `%s'.\n",
             dkf);
    return GNUNET_SYSERR;
  }
  if ( (NULL != auditor_output_file) &&
       (1 !=
        fwrite (&denomkey_issue->issue.properties,
                sizeof (struct TALER_DenominationKeyValidityPS),
                1,
                auditor_output_file)) )
  {
    fprintf (stderr,
             "Failed to write denomination key information to %s: %s\n",
             auditorrequestfile,
             strerror (errno));
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Generate new denomination signing keys for the denomination type of the given @a
 * denomination_alias.
 *
 * @param cls a `int *`, to be set to #GNUNET_SYSERR on failure
 * @param denomination_alias name of the denomination's section in the configuration
 */
static void
exchange_keys_update_denominationtype (void *cls,
                                       const char *denomination_alias)
{
  int *ret = cls;
  struct DenominationParameters p;
  const char *dkf;
  struct TALER_EXCHANGEDB_DenominationKey denomkey_issue;

  if (0 != strncasecmp (denomination_alias,
                        "coin_",
                        strlen ("coin_")))
    return; /* not a denomination type definition */
  if (GNUNET_OK !=
      get_denomination_type_params (denomination_alias,
                                    &p))
  {
    *ret = GNUNET_SYSERR;
    return;
  }
  /* p has the right anchor now = latest denom filename converted to time.  */
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (get_denomination_dir (&p)))
  {
    *ret = GNUNET_SYSERR;
    return;
  }

  while (p.anchor.abs_value_us < lookahead_sign_stamp.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Future time not covered yet for type `%s': %s\n",
                denomination_alias,
                GNUNET_STRINGS_relative_time_to_string
                  (GNUNET_TIME_absolute_get_difference (p.anchor,
                                                        lookahead_sign_stamp),
                  GNUNET_NO));
    dkf = get_denomination_type_file (&p,
                                      p.anchor);
    GNUNET_break (GNUNET_YES !=
                  GNUNET_DISK_file_test (dkf));

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Generating denomination key for type `%s', start %s at %s\n",
                denomination_alias,
                GNUNET_STRINGS_absolute_time_to_string (p.anchor),
                dkf);
    create_denomkey_issue (&p,
                           &denomkey_issue);
    *ret = write_denomkey_issue (dkf,
                                 &denomkey_issue);
    GNUNET_CRYPTO_rsa_private_key_free (
      denomkey_issue.denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (denomkey_issue.denom_pub.rsa_public_key);
    if (GNUNET_OK != *ret)
      return; /* stop loop, hard error */
    p.anchor = GNUNET_TIME_absolute_add (p.anchor,
                                         p.duration_withdraw);
    p.anchor = GNUNET_TIME_absolute_subtract (p.anchor,
                                              duration_overlap);
  }
}


/**
 * Update all of the denomination keys of the exchange.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
exchange_keys_update_denomkeys (void)
{
  int ok;

  ok = GNUNET_OK;
  GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                         &exchange_keys_update_denominationtype,
                                         &ok);
  return ok;
}


/**
 * Sign @a af with @a priv
 *
 * @param[in,out] af fee structure to sign
 * @param method name of the wire method for which we sign
 * @param priv private key to use for signing
 */
static void
sign_af (struct TALER_EXCHANGEDB_AggregateFees *af,
         const char *method,
         const struct GNUNET_CRYPTO_EddsaPrivateKey *priv)
{
  struct TALER_MasterWireFeePS wf;

  TALER_EXCHANGEDB_fees_2_wf (method,
                              af,
                              &wf);
  GNUNET_CRYPTO_eddsa_sign (priv,
                            &wf,
                            &af->master_sig.eddsa_signature);
}


/**
 * Output the wire fee structure.  Must be run after #max_duration_spend
 * was initialized.
 *
 * @param cls pointer to `int`, set to #GNUNET_SYSERR on error
 * @param wiremethod method to write fees for
 */
static void
create_wire_fee_for_method (void *cls,
                            const char *wiremethod)
{
  int *ret = cls;
  struct TALER_EXCHANGEDB_AggregateFees *af_head;
  struct TALER_EXCHANGEDB_AggregateFees *af_tail;
  unsigned int year;
  struct GNUNET_TIME_Absolute last_date;
  struct GNUNET_TIME_Absolute start_date;
  struct GNUNET_TIME_Absolute end_date;
  char yearstr[12];
  char *fn;
  char *section;

  if (GNUNET_OK != *ret)
    return;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Setting up wire fees for `%s'\n",
              wiremethod);
  last_date = GNUNET_TIME_absolute_add (lookahead_sign_stamp,
                                        max_duration_spend);
  GNUNET_asprintf (&section,
                   "fees-%s",
                   wiremethod);
  GNUNET_asprintf (&fn,
                   "%s/%s.fee",
                   feedir,
                   wiremethod);
  af_head = NULL;
  af_tail = NULL;
  year = GNUNET_TIME_get_current_year ();
  start_date = GNUNET_TIME_year_to_time (year);
  while (start_date.abs_value_us < last_date.abs_value_us)
  {
    struct TALER_EXCHANGEDB_AggregateFees *af;
    char *opt;

    GNUNET_snprintf (yearstr,
                     sizeof (yearstr),
                     "%u",
                     year);
    end_date = GNUNET_TIME_year_to_time (year + 1);
    af = GNUNET_new (struct TALER_EXCHANGEDB_AggregateFees);
    af->start_date = start_date;
    af->end_date = end_date;

    /* handle wire fee */
    GNUNET_asprintf (&opt,
                     "wire-fee-%u",
                     year);
    if ( (GNUNET_OK !=
          TALER_config_get_amount (kcfg,
                                   section,
                                   opt,
                                   &af->wire_fee)) ||
         (0 != strcasecmp (currency,
                           af->wire_fee.currency)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Need amount with currency `%s' for option `%s' in section `%s'\n",
                  currency,
                  opt,
                  section);
      *ret = GNUNET_SYSERR;
      GNUNET_free (opt);
      break;
    }
    GNUNET_free (opt);

    /* handle closing fee */
    GNUNET_asprintf (&opt,
                     "closing-fee-%u",
                     year);
    if ( (GNUNET_OK !=
          TALER_config_get_amount (kcfg,
                                   section,
                                   opt,
                                   &af->closing_fee)) ||
         (0 != strcasecmp (currency,
                           af->closing_fee.currency)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Need amount with currency `%s' for option `%s' in section `%s'\n",
                  currency,
                  opt,
                  section);
      *ret = GNUNET_SYSERR;
      GNUNET_free (opt);
      break;
    }

    GNUNET_free (opt);
    sign_af (af,
             wiremethod,
             &master_priv.eddsa_priv);
    if (NULL == af_tail)
      af_head = af;
    else
      af_tail->next = af;
    af_tail = af;
    start_date = end_date;
    year++;
  }
  if ( (GNUNET_OK == *ret) &&
       (GNUNET_OK !=
        TALER_EXCHANGEDB_fees_write (fn,
                                     wiremethod,
                                     af_head)) )
    *ret = GNUNET_SYSERR;
  GNUNET_free (section);
  GNUNET_free (fn);
  TALER_EXCHANGEDB_fees_free (af_head);
}


/**
 * Output the wire fee structure.  Must be run after #max_duration_spend
 * was initialized.
 *
 * @param cls pointer to `int`, set to #GNUNET_SYSERR on error
 * @param ai information about enabled accounts
 */
static void
create_wire_fee_by_account (void *cls,
                            const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  int *ret = cls;

  if (GNUNET_NO == ai->credit_enabled)
    return;
  /* We may call this function repeatedly for the same method
     if there are multiple accounts with plugins using the
     same method, but except for some minor performance loss,
     this is harmless. */
  create_wire_fee_for_method (ret,
                              ai->method);
}


/**
 * Output the wire fee structure.  Must be run after #max_duration_spend
 * was initialized.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
create_wire_fees (void)
{
  int ret;

  ret = GNUNET_OK;
  TALER_EXCHANGEDB_find_accounts (kcfg,
                                  &create_wire_fee_by_account,
                                  &ret);
  return ret;
}


/**
 * Check if the denomination that we just revoked is currently active,
 * and if so, generate a replacement key.
 *
 * @param cls closure with the revoked denomination key hash, a `struct GNUNET_HashCode *`
 * @param alias coin alias
 * @param dki the denomination key
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
check_revocation_regeneration (
  void *cls,
  const char *alias,
  const struct TALER_EXCHANGEDB_DenominationKey *dki)
{
  const struct GNUNET_HashCode *denom_hash = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute withdraw_end;

  (void) alias;
  if (0 !=
      GNUNET_memcmp (denom_hash,
                     &dki->issue.properties.denom_hash))
    return GNUNET_OK; /* does not match */
  now = GNUNET_TIME_absolute_get ();
  withdraw_end = GNUNET_TIME_absolute_ntoh (
    dki->issue.properties.expire_withdraw);
  if (now.abs_value_us >= withdraw_end.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Revoked denomination key has expired, no need to create a replacement\n");
    return GNUNET_NO;
  }

  {
    struct GNUNET_TIME_Absolute anchor
      = GNUNET_TIME_absolute_ntoh (dki->issue.properties.start);
    struct TALER_EXCHANGEDB_DenominationKey dki_new;
    const char *dkf;
    int ret;
    struct DenominationParameters dp = {
      .duration_legal
        = GNUNET_TIME_absolute_get_difference
            (anchor,
            GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_legal)),
      .duration_spend
        = GNUNET_TIME_absolute_get_difference
            (anchor,
            GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_deposit)),
      .duration_withdraw
        = GNUNET_TIME_absolute_get_difference
            (anchor,
            GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_withdraw)),
      .anchor = anchor,
      .rsa_keysize = replacement_key_size
    };
    char *dkfi;

    TALER_amount_ntoh (&dp.value,
                       &dki->issue.properties.value);
    TALER_amount_ntoh (&dp.fee_withdraw,
                       &dki->issue.properties.fee_withdraw);
    TALER_amount_ntoh (&dp.fee_deposit,
                       &dki->issue.properties.fee_deposit);
    TALER_amount_ntoh (&dp.fee_refresh,
                       &dki->issue.properties.fee_refresh);
    TALER_amount_ntoh (&dp.fee_refund,
                       &dki->issue.properties.fee_refund);

    /* find unused file name for revocation file by appending -%u */
    dkf = get_denomination_type_file (&dp,
                                      dp.anchor);
    for (unsigned int i = 1;; i++)
    {
      GNUNET_asprintf (&dkfi,
                       "%s-%u",
                       dkf,
                       i);
      if (GNUNET_YES != GNUNET_DISK_file_test (dkfi))
        break;
      GNUNET_free (dkfi);
    }

    create_denomkey_issue (&dp,
                           &dki_new);
    ret = write_denomkey_issue (dkfi,
                                &dki_new);
    GNUNET_free (dkfi);
    GNUNET_CRYPTO_rsa_private_key_free (dki_new.denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (dki_new.denom_pub.rsa_public_key);
    if (GNUNET_OK != ret)
      return GNUNET_SYSERR;
  }

  return GNUNET_NO;
}


/**
 * Revoke the denomination key matching @a hc and request /recoup to be
 * initiated.
 *
 * @param hc denomination key hash to revoke
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if @a hc was not found
 *         #GNUNET_SYSERR on error
 */
static int
revoke_denomination (const struct GNUNET_HashCode *hc)
{
  {
    char *basedir;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "exchange",
                                                 "REVOCATION_DIR",
                                                 &basedir))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "REVOCATION_DIR");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        TALER_EXCHANGEDB_denomination_key_revoke (basedir,
                                                  hc,
                                                  &master_priv))
    {
      GNUNET_free (basedir);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_free (basedir);
  }

  if (GNUNET_SYSERR ==
      TALER_EXCHANGEDB_denomination_keys_iterate (exchange_directory,
                                                  &check_revocation_regeneration,
                                                  (void *) hc))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Might have failed to generate replacement for revoked denomination key!\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct GNUNET_TIME_Relative lookahead_sign;

  (void) cls;
  (void) args;
  (void) cfgfile;
  kcfg = cfg;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency))
  {
    global_ret = 1;
    return;
  }
  if (now.abs_value_us != now_tmp.abs_value_us)
  {
    /* The user gave "--now", use it! */
    now = now_tmp;
  }
  GNUNET_TIME_round_abs (&now);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchangedb",
                                           "DURATION_OVERLAP",
                                           &duration_overlap))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "DURATION_OVERLAP");
    global_ret = 1;
    return;
  }
  GNUNET_TIME_round_rel (&duration_overlap);

  if (NULL == feedir)
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "exchangedb",
                                                 "WIREFEE_BASE_DIR",
                                                 &feedir))
    {
      fprintf (stderr,
               "Wire fee directory given neither in configuration nor on command-line\n");
      global_ret = 1;
      return;
    }
  }
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (feedir))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "mkdir",
                              feedir);
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange",
                                               "KEYDIR",
                                               &exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    global_ret = 1;
    return;
  }

  if (GNUNET_OK !=
      get_and_check_master_key (kcfg,
                                masterkeyfile,
                                &master_priv))
  {
    global_ret = 1;
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_public_key.eddsa_pub);

  if (NULL != auditorrequestfile)
  {
    auditor_output_file = fopen (auditorrequestfile,
                                 "w");
    if (NULL == auditor_output_file)
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "open (w)",
                                auditorrequestfile);
      global_ret = 1;
      return;
    }
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LOOKAHEAD_SIGN");
    global_ret = 1;
    return;
  }
  if (0 == lookahead_sign.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LOOKAHEAD_SIGN",
                               "must not be zero");
    global_ret = 1;
    return;
  }
  GNUNET_TIME_round_rel (&lookahead_sign);
  lookahead_sign_stamp = GNUNET_TIME_absolute_add (now,
                                                   lookahead_sign);


  /* finally, do actual work */
  if (0 != GNUNET_is_zero (&revoke_dkh))
  {
    if (GNUNET_OK != revoke_denomination (&revoke_dkh))
    {
      global_ret = 1;
      return;
    }
    /* if we were invoked to revoke a key, let's not also generate
       new keys, as that might not be desired. */
    return;
  }

  if (NULL == auditor_output_file)
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Option `-o' missing. Hence, you will NOT be able to use an auditor with the generated keys!\n");

  if (GNUNET_OK != exchange_keys_update_signkeys ())
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK != exchange_keys_update_denomkeys ())
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK != create_wire_fees ())
  {
    global_ret = 1;
    return;
  }
}


/**
 * The main function of the taler-exchange-keyup tool.  This tool is used to
 * create the signing and denomination keys for the exchange.  It uses the
 * long-term offline private key and writes the (additional) key files to the
 * respective exchange directory (from where they can then be copied to the
 * online server).  Note that we need (at least) the most recent generated
 * previous keys to align the validity periods.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_filename ('m',
                                   "master-key",
                                   "FILENAME",
                                   "master key file (private key)",
                                   &masterkeyfile),
    GNUNET_GETOPT_option_filename ('f',
                                   "feedir",
                                   "DIRNAME",
                                   "directory where to write wire transfer fee structure",
                                   &feedir),
    GNUNET_GETOPT_option_uint ('k',
                               "replacement-keysize",
                               "BITS",
                               "when creating a replacement key in a revocation operation, which key size should be used for the new denomination key",
                               &replacement_key_size),
    GNUNET_GETOPT_option_filename ('o',
                                   "output",
                                   "FILENAME",
                                   "auditor denomination key signing request file to create",
                                   &auditorrequestfile),
    GNUNET_GETOPT_option_base32_auto ('r',
                                      "revoke",
                                      "DKH",
                                      "revoke denomination key hash (DKH) and request wallets to initiate recoup",
                                      &revoke_dkh),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_absolute_time ('t',
                                        "time",
                                        "TIMESTAMP",
                                        "pretend it is a different time for the update",
                                        &now_tmp),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-keyup",
                                   "WARNING",
                                   NULL));
  now = now_tmp = GNUNET_TIME_absolute_get ();
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-keyup",
                          "Setup signing and denomination keys for a Taler exchange",
                          options,
                          &run, NULL))
    return 1;
  if (NULL != auditor_output_file)
  {
    GNUNET_assert (0 == fclose (auditor_output_file));
    auditor_output_file = NULL;
  }
  return global_ret;
}


/* end of taler-exchange-keyup.c */
