/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @brief Update the exchange's keys for coins and signatures,
 *        using the exchange's offline master key.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_exchangedb_lib.h"
#include "taler_wire_lib.h"

/**
 * When generating filenames from a cryptographic hash, we do not use
 * all 512 bits but cut off after this number of characters (in
 * base32-encoding).  Base32 is 5 bit per character, and given that we
 * have very few coin types we hash, at 100 bits the chance of
 * collision (by accident over tiny set -- birthday paradox does not
 * apply here!) is negligible.
 */
#define HASH_CUTOFF 20


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Struct with all of the key information for a kind of coin.  Hashed
 * to generate a unique directory name per coin type.
 */
struct CoinTypeNBOP
{
  /**
   * How long are the signatures legally valid?
   */
  struct GNUNET_TIME_RelativeNBO duration_legal;

  /**
   * How long can the coin be spend?
   */
  struct GNUNET_TIME_RelativeNBO duration_spend;

  /**
   * How long can the coin be withdrawn (generated)?
   */
  struct GNUNET_TIME_RelativeNBO duration_withdraw;

  /**
   * What is the value of the coin?
   */
  struct TALER_AmountNBO value;

  /**
   * What is the fee charged for withdrawl?
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
   * Key size in NBO.
   */
  uint32_t rsa_keysize;
};

GNUNET_NETWORK_STRUCT_END

/**
 * Set of all of the parameters that chracterize a coin.
 */
struct CoinTypeParams
{

  /**
   * How long are the signatures legally valid?  Should be
   * significantly larger than @e duration_spend (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_legal;


  /**
   * How long can the coin be spend?  Should be significantly
   * larger than @e duration_withdraw (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_spend;

  /**
   * How long can the coin be withdrawn (generated)?  Should be small
   * enough to limit how many coins will be signed into existence with
   * the same key, but large enough to still provide a reasonable
   * anonymity set.
   */
  struct GNUNET_TIME_Relative duration_withdraw;

  /**
   * How much should coin creation (@e duration_withdraw) duration
   * overlap with the next coin?  Basically, the starting time of two
   * coins is always @e duration_withdraw - @e duration_overlap apart.
   */
  struct GNUNET_TIME_Relative duration_overlap;

  /**
   * What is the value of the coin?
   */
  struct TALER_Amount value;

  /**
   * What is the fee charged for withdrawl?
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
   * Length of the RSA key in bits.
   */
  uint32_t rsa_keysize;
};


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
 * Return value from main().
 */
static int global_ret;


/**
 * Hash the data defining the coin type.  Exclude information that may
 * not be the same for all instances of the coin type (i.e. the
 * anchor, overlap).
 *
 * @param p coin parameters to convert to a hash
 * @param[out] hash set to the hash matching @a p
 */
static void
hash_coin_type (const struct CoinTypeParams *p,
                struct GNUNET_HashCode *hash)
{
  struct CoinTypeNBOP p_nbo;

  memset (&p_nbo,
          0,
          sizeof (struct CoinTypeNBOP));
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
                      sizeof (struct CoinTypeNBOP),
                      hash);
}


/**
 * Obtain the name of the directory we should use to store coins of
 * the given type.  The directory name has the format
 * "$EXCHANGEDIR/$VALUE/$HASH/" where "$VALUE" represents the value of the
 * coin and "$HASH" encodes all of the coin's parameters, generating a
 * unique string for each type of coin.  Note that the "$HASH"
 * includes neither the absolute creation time nor the key of the
 * coin, thus the files in the subdirectory really just refer to the
 * same type of coins, not the same coin.
 *
 * @param p coin parameters to convert to a directory name
 * @return directory name (valid until next call to this function)
 */
static const char *
get_cointype_dir (const struct CoinTypeParams *p)
{
  static char dir[4096];
  struct GNUNET_HashCode hash;
  char *hash_str;
  char *val_str;

  hash_coin_type (p, &hash);
  hash_str = GNUNET_STRINGS_data_to_string_alloc (&hash,
                                                  sizeof (struct GNUNET_HashCode));
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
                   "%s" DIR_SEPARATOR_STR TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS DIR_SEPARATOR_STR "%s-%s",
                   exchange_directory,
                   val_str,
                   hash_str);
  GNUNET_free (hash_str);
  GNUNET_free (val_str);
  return dir;
}


/**
 * Obtain the name of the file we would use to store the key
 * information for a coin of the given type @a p and validity
 * start time @a start
 *
 * @param p parameters for the coin
 * @param start when would the coin begin to be issued
 * @return name of the file to use for this coin
 *         (valid until next call to this function)
 */
static const char *
get_cointype_file (const struct CoinTypeParams *p,
                   struct GNUNET_TIME_Absolute start)
{
  static char filename[4096];
  const char *dir;

  dir = get_cointype_dir (p);
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
 * handle both signing keys and coin keys, as in both cases
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
    /* Real starting time is the last start time + duration - overlap */
    *anchor = GNUNET_TIME_absolute_add (*anchor,
                                        duration);
    *anchor = GNUNET_TIME_absolute_subtract (*anchor,
                                             overlap);
  }
  /* anchor is now the stamp where we need to create a new key */
}


/**
 * Create a exchange signing key (for signing exchange messages, not for coins)
 * and assert its correctness by signing it with the master key.
 *
 * @param start start time of the validity period for the key
 * @param duration how long should the key be valid
 * @param end when do all signatures by this key expire
 * @param[out] pi set to the signing key information
 */
static void
create_signkey_issue_priv (struct GNUNET_TIME_Absolute start,
                           struct GNUNET_TIME_Relative duration,
                           struct GNUNET_TIME_Absolute end,
                           struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *pi)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  struct TALER_ExchangeSigningKeyValidityPS *issue = &pi->issue;

  priv = GNUNET_CRYPTO_eddsa_key_create ();
  pi->signkey_priv.eddsa_priv = *priv;
  GNUNET_free (priv);
  issue->master_public_key = master_public_key;
  issue->start = GNUNET_TIME_absolute_hton (start);
  issue->expire = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (start,
                                                                       duration));
  issue->end = GNUNET_TIME_absolute_hton (end);
  GNUNET_CRYPTO_eddsa_key_get_public (&pi->signkey_priv.eddsa_priv,
                                      &issue->signkey_pub.eddsa_pub);
  issue->purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  issue->purpose.size = htonl (sizeof (struct TALER_ExchangeSigningKeyValidityPS));
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                                           &issue->purpose,
                                           &pi->master_sig.eddsa_signature));
}


/**
 * Generate signing keys starting from the last key found to
 * the lookahead time.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
exchange_keys_update_signkeys ()
{
  struct GNUNET_TIME_Relative signkey_duration;
  struct GNUNET_TIME_Relative legal_duration;
  struct GNUNET_TIME_Absolute anchor;
  char *signkey_dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "signkey_duration",
                                           &signkey_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "signkey_duration");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "legal_duration",
                                           &legal_duration))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "legal_duration",
                               "fails to specify valid timeframe");
    return GNUNET_SYSERR;
  }
  if (signkey_duration.rel_value_us > legal_duration.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "legal_duration",
                               "must be longer than signkey_duration");
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
 * Parse configuration for coin type parameters.  Also determines
 * our anchor by looking at the existing coins of the same type.
 *
 * @param ct section in the configuration file giving the coin type parameters
 * @param[out] params set to the coin parameters from the configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the configuration is invalid
 */
static int
get_cointype_params (const char *ct,
                     struct CoinTypeParams *params)
{
  const char *dir;
  unsigned long long rsa_keysize;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "duration_withdraw",
                                           &params->duration_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "duration_withdraw");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_withdraw);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "duration_spend",
                                           &params->duration_spend))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "duration_spend");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_spend);
  max_duration_spend = GNUNET_TIME_relative_max (max_duration_spend,
                                                 params->duration_spend);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "duration_legal",
                                           &params->duration_legal))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "duration_legal");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_legal);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "duration_overlap",
                                           &params->duration_overlap))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "exchange_denom_duration_overlap");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&params->duration_overlap);
  if (params->duration_overlap.rel_value_us >=
      params->duration_withdraw.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "duration_overlap",
                               "duration_overlap must be smaller than duration_withdraw!");
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
      TALER_config_get_denom (kcfg,
                              ct,
                              "value",
                              &params->value))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "value");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_denom (kcfg,
                              ct,
                              "fee_withdraw",
                              &params->fee_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "fee_withdraw");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_denom (kcfg,
                              ct,
                              "fee_deposit",
                              &params->fee_deposit))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "fee_deposit");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_denom (kcfg,
                              ct,
                              "fee_refresh",
                              &params->fee_refresh))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "fee_refresh");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_denom (kcfg,
                              ct,
                              "fee_refund",
                              &params->fee_refund))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "fee_refund");
    return GNUNET_SYSERR;
  }

  dir = get_cointype_dir (params);
  get_anchor (dir,
              params->duration_withdraw,
              params->duration_overlap,
              &params->anchor);

  /**
   * The "anchor" is merely the latest denom key filename
   * converted to a GNUnet absolute date.
   */

  return GNUNET_OK;
}


/**
 * Initialize the private and public key information structure for
 * signing coins into existence.  Generates the private signing key
 * and signes it together with the coin's meta data using the master
 * signing key.
 *
 * @param params parameters used to initialize the @a dki
 * @param[out] dki initialized according to @a params
 */
static void
create_denomkey_issue (const struct CoinTypeParams *params,
                       struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  dki->denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (params->rsa_keysize);
  GNUNET_assert (NULL != dki->denom_priv.rsa_private_key);
  dki->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &dki->issue.properties.denom_hash);
  dki->issue.properties.master = master_public_key;
  dki->issue.properties.start = GNUNET_TIME_absolute_hton (params->anchor);
  dki->issue.properties.expire_withdraw =
      GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                           params->duration_withdraw));
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
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                                           &dki->issue.properties.purpose,
                                           &dki->issue.signature.eddsa_signature));
}


/**
 * Generate new coin signing keys for the coin type of the given @a
 * coin_alias.
 *
 * @param cls a `int *`, to be set to #GNUNET_SYSERR on failure
 * @param coin_alias name of the coin's section in the configuration
 */
static void
exchange_keys_update_cointype (void *cls,
			       const char *coin_alias)
{
  int *ret = cls;
  struct CoinTypeParams p;
  const char *dkf;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation denomkey_issue;

  if (0 != strncasecmp (coin_alias,
                        "coin_",
                        strlen ("coin_")))
    return; /* not a coin definition */
  if (GNUNET_OK !=
      get_cointype_params (coin_alias,
                           &p))
  {
    *ret = GNUNET_SYSERR;
    return;
  }
  /* p has the right anchor now = latest denom filename converted to time.  */
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (get_cointype_dir (&p)))
  {
    *ret = GNUNET_SYSERR;
    return;
  }

  while (p.anchor.abs_value_us < lookahead_sign_stamp.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Future time not covered yet for type `%s': %s\n",
                coin_alias,
                GNUNET_STRINGS_relative_time_to_string
                  (GNUNET_TIME_absolute_get_difference (p.anchor,
                                                        lookahead_sign_stamp),
                                                        GNUNET_NO));

    dkf = get_cointype_file (&p,
                             p.anchor);
    GNUNET_break (GNUNET_YES !=
                  GNUNET_DISK_file_test (dkf));

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Generating denomination key for type `%s', start %s at %s\n",
                coin_alias,
                GNUNET_STRINGS_absolute_time_to_string (p.anchor),
                dkf);

    create_denomkey_issue (&p,
                           &denomkey_issue);
    if (GNUNET_OK !=
        TALER_EXCHANGEDB_denomination_key_write (dkf,
						 &denomkey_issue))
    {
      fprintf (stderr,
               "Failed to write denomination key information to file `%s'.\n",
               dkf);
      *ret = GNUNET_SYSERR;
      GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv.rsa_private_key);
      GNUNET_CRYPTO_rsa_public_key_free (denomkey_issue.denom_pub.rsa_public_key);
      return;
    }
    if ( (NULL != auditor_output_file) &&
         (1 !=
          fwrite (&denomkey_issue.issue.properties,
                  sizeof (struct TALER_DenominationKeyValidityPS),
                  1,
                  auditor_output_file)) )
    {
      fprintf (stderr,
               "Failed to write denomination key information to %s: %s\n",
               auditorrequestfile,
               STRERROR (errno));
      *ret = GNUNET_SYSERR;
      GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv.rsa_private_key);
      GNUNET_CRYPTO_rsa_public_key_free (denomkey_issue.denom_pub.rsa_public_key);
      return;
    }
    GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (denomkey_issue.denom_pub.rsa_public_key);
    p.anchor = GNUNET_TIME_absolute_add (p.anchor,
                                         p.duration_withdraw);
    p.anchor = GNUNET_TIME_absolute_subtract (p.anchor,
                                              p.duration_overlap);
  }
}


/**
 * Update all of the denomination keys of the exchange.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
exchange_keys_update_denomkeys ()
{
  int ok;

  ok = GNUNET_OK;
  GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                         &exchange_keys_update_cointype,
                                         &ok);
  return ok;
}


/**
 * Sign @a af with @a priv
 *
 * @param[in,out] af fee structure to sign
 * @param wireplugin name of the plugin for which we sign
 * @param priv private key to use for signing
 */
static void
sign_af (struct TALER_EXCHANGEDB_AggregateFees *af,
         const char *wireplugin,
         const struct GNUNET_CRYPTO_EddsaPrivateKey *priv)
{
  struct TALER_MasterWireFeePS wf;

  TALER_EXCHANGEDB_fees_2_wf (wireplugin,
                              af,
                              &wf);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (priv,
                                           &wf.purpose,
                                           &af->master_sig.eddsa_signature));
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
    char *amounts;

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
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               section,
                                               opt,
                                               &amounts))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 opt);
      *ret = GNUNET_SYSERR;
      GNUNET_free (opt);
      break;
    }
    if (GNUNET_OK !=
        TALER_string_to_amount (amounts,
                                &af->wire_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid amount `%s' specified in `%s' under `%s'\n",
                  amounts,
                  wiremethod,
                  opt);
      *ret = GNUNET_SYSERR;
      GNUNET_free (amounts);
      GNUNET_free (opt);
      break;
    }
    GNUNET_free (amounts);
    GNUNET_free (opt);

    /* handle closing fee */
    GNUNET_asprintf (&opt,
                     "closing-fee-%u",
                     year);
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               section,
                                               opt,
                                               &amounts))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 opt);
      *ret = GNUNET_SYSERR;
      GNUNET_free (opt);
      break;
    }
    if (GNUNET_OK !=
        TALER_string_to_amount (amounts,
                                &af->closing_fee))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid amount `%s' specified in `%s' under `%s'\n",
                  amounts,
                  wiremethod,
                  opt);
      *ret = GNUNET_SYSERR;
      GNUNET_free (amounts);
      GNUNET_free (opt);
      break;
    }
    GNUNET_free (amounts);

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
  struct TALER_WIRE_Plugin *plugin;

  if (GNUNET_NO == ai->credit_enabled)
    return;
  plugin = TALER_WIRE_plugin_load (kcfg,
                                   ai->plugin_name);
  if (NULL == plugin)
  {
    fprintf (stderr,
             "Failed to load wire plugin `%s' configured for account `%s'\n",
             ai->plugin_name,
             ai->section_name);
    *ret = GNUNET_SYSERR;
    return;
  }
  /* We may call this function repeatedly for the same method
     if there are multiple accounts with plugins using the
     same method, but except for some minor performance loss,
     this is harmless. */
  create_wire_fee_for_method (ret,
                              plugin->method);
  TALER_WIRE_plugin_unload (plugin);
}


/**
 * Output the wire fee structure.  Must be run after #max_duration_spend
 * was initialized.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
create_wire_fees ()
{
  int ret;

  ret = GNUNET_OK;
  TALER_EXCHANGEDB_find_accounts (kcfg,
                                  &create_wire_fee_by_account,
                                  &ret);
  return ret;
}


/**
 * Revoke the denomination key matching @a hc and request /payback to be
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
  static struct GNUNET_HashCode zero;
  struct GNUNET_TIME_Relative lookahead_sign;
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;

  kcfg = cfg;

  if (now.abs_value_us != now_tmp.abs_value_us)
  {
    /* The user gave "--now", use it */ 
    now = now_tmp;
  }
  /* The user _might_ have given "--now" but it matched
   * exactly the normal now, so no change required.  */

  if (NULL == feedir)
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "exchangedb",
                                                 "WIREFEE_BASE_DIR",
                                                 &feedir))
    {
      fprintf (stderr,
               "Wire fee directory not given in neither configuration nor command-line\n");
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
  GNUNET_TIME_round_abs (&now);
  if ( (NULL == masterkeyfile) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "exchange",
                                                 "MASTER_PRIV_FILE",
                                                 &masterkeyfile)) )
  {
    fprintf (stderr,
             "Master key file not given in neither configuration nor command-line\n");
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
  if (GNUNET_YES != GNUNET_DISK_file_test (masterkeyfile))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Exchange master private key `%s' does not exist yet, creating it!\n",
                masterkeyfile);
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (masterkeyfile);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize master key from file `%s'\n",
             masterkeyfile);
    global_ret = 1;
    return;
  }
  master_priv.eddsa_priv = *eddsa_priv;
  GNUNET_free (eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_public_key.eddsa_pub);

  if (NULL != auditorrequestfile)
  {
    auditor_output_file = FOPEN (auditorrequestfile,
                                 "w");
    if (NULL == auditor_output_file)
    {
      fprintf (stderr,
               "Failed to open `%s' for writing: %s\n",
               auditorrequestfile,
               STRERROR (errno));
      global_ret = 1;
      return;
    }
  }

  /* check if key from file matches the one from the configuration */
  {
    struct TALER_MasterPublicKeyP master_public_key_from_cfg;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_data (kcfg,
                                       "exchange",
                                       "master_public_key",
                                       &master_public_key_from_cfg,
                                       sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "master_public_key");
      global_ret = 1;
      return;
    }
    if (0 !=
        memcmp (&master_public_key,
                &master_public_key_from_cfg,
                sizeof (struct TALER_MasterPublicKeyP)))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "master_public_key",
                                 _("does not match with private key"));
      global_ret = 1;
      return;
    }
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "lookahead_sign",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "lookahead_sign");
    global_ret = 1;
    return;
  }
  if (0 == lookahead_sign.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "lookahead_sign",
                               _("must not be zero"));
    global_ret = 1;
    return;
  }
  GNUNET_TIME_round_rel (&lookahead_sign);
  lookahead_sign_stamp = GNUNET_TIME_absolute_add (now,
                                                   lookahead_sign);


  /* finally, do actual work */
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
  if ( (0 != memcmp (&zero,
                     &revoke_dkh,
                     sizeof (zero))) &&
       (GNUNET_OK !=
        revoke_denomination (&revoke_dkh)) )
  {
    global_ret = 1;
    return;
  }
}


/**
 * The main function of the taler-exchange-keyup tool.  This tool is used
 * to create the signing and denomination keys for the exchange.  It uses
 * the long-term offline private key and writes the (additional) key
 * files to the respective exchange directory (from where they can then be
 * copied to the online server).  Note that we need (at least) the
 * most recent generated previous keys so as to align the validity
 * periods.
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
    GNUNET_GETOPT_option_filename ('o',
                                   "output",
                                   "FILENAME",
                                   "auditor denomination key signing request file to create",
                                   &auditorrequestfile),
    GNUNET_GETOPT_option_base32_auto ('r',
                                      "revoke",
                                      "DKH",
                                      "revoke denomination key hash (DKH) and request wallets to initiate /payback",
                                      &revoke_dkh),
    GNUNET_GETOPT_option_absolute_time ('t',
                                        "time",
                                        "TIMESTAMP",
                                        "pretend it is a different time for the update",
                                        &now_tmp),
    GNUNET_GETOPT_OPTION_END
  };

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
    FCLOSE (auditor_output_file);
    auditor_output_file = NULL;
  }
  return global_ret;
}

/* end of taler-exchange-keyup.c */
