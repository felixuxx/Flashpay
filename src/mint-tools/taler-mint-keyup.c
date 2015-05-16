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
 * @file taler-mint-keyup.c
 * @brief Update the mint's keys for coins and signatures,
 *        using the mint's offline master key.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_mintdb_lib.h"

/**
 * When generating filenames from a cryptographic hash, we do not use
 * all 512 bits but cut off after this number of characters (in
 * base32-encoding).  Base32 is 5 bit per character, and given that we
 * have very few coin types we hash, at 100 bits the chance of
 * collision (by accident over tiny set -- birthday paradox does not
 * apply here!) is negligible.
 */
#define HASH_CUTOFF 20

/**
 * Macro to round microseconds to seconds in GNUNET_TIME_* structs.
 *
 * @param name value to round
 * @param us_field rel_value_us or abs_value_us
 */
#define ROUND_TO_SECS(name,us_field) name.us_field -= name.us_field % (1000 * 1000);


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
 * Director of the mint, containing the keys.
 */
static char *mint_directory;

/**
 * Time to pretend when the key update is executed.
 */
static char *pretend_time_str;

/**
 * Handle to the mint's configuration
 */
static struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Time when the key update is executed.  Either the actual current time, or a
 * pretended time.
 */
static struct GNUNET_TIME_Absolute now;

/**
 * Master private key of the mint.
 */
static struct TALER_MasterPrivateKeyP master_priv;

/**
 * Master public key of the mint.
 */
static struct TALER_MasterPublicKeyP master_public_key;

/**
 * Until what time do we provide keys?
 */
static struct GNUNET_TIME_Absolute lookahead_sign_stamp;


/**
 * Obtain the name of the directory we use to store signing
 * keys created at time @a start.
 *
 * @param start time at which we create the signing key
 * @return name of the directory we should use, basically "$MINTDIR/$TIME/";
 *         (valid until next call to this function)
 */
static const char *
get_signkey_file (struct GNUNET_TIME_Absolute start)
{
  static char dir[4096];

  GNUNET_snprintf (dir,
                   sizeof (dir),
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_SIGNING_KEYS DIR_SEPARATOR_STR "%llu",
                   mint_directory,
                   (unsigned long long) start.abs_value_us);
  return dir;
}


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
  p_nbo.rsa_keysize = htonl (p->rsa_keysize);
  GNUNET_CRYPTO_hash (&p_nbo,
                      sizeof (struct CoinTypeNBOP),
                      hash);
}


/**
 * Obtain the name of the directory we should use to store coins of
 * the given type.  The directory name has the format
 * "$MINTDIR/$VALUE/$HASH/" where "$VALUE" represents the value of the
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
  size_t i;

  hash_coin_type (p, &hash);
  hash_str = GNUNET_STRINGS_data_to_string_alloc (&hash,
                                                  sizeof (struct GNUNET_HashCode));
  GNUNET_assert (NULL != hash_str);
  GNUNET_assert (HASH_CUTOFF <= strlen (hash_str) + 1);
  hash_str[HASH_CUTOFF] = 0;

  val_str = TALER_amount_to_string (&p->value);
  for (i = 0; i < strlen (val_str); i++)
    if ( (':' == val_str[i]) ||
         ('.' == val_str[i]) )
      val_str[i] = '_';

  GNUNET_snprintf (dir,
                   sizeof (dir),
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_DENOMINATION_KEYS DIR_SEPARATOR_STR "%s-%s",
                   mint_directory,
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

  base = GNUNET_STRINGS_get_short_name (filename);
  stamp.abs_value_us = strtol (base,
                               &end,
                               10);
  if ((NULL == end) || (0 != *end))
  {
    fprintf(stderr,
            "Ignoring unexpected file `%s'.\n",
            filename);
    return GNUNET_OK;
  }
  if (stamp.abs_value_us <= now.abs_value_us)
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
  else if (anchor->abs_value_us != now.abs_value_us) // Also odd...
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
 * Create a mint signing key (for signing mint messages, not for coins)
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
                           struct TALER_MINTDB_PrivateSigningKeyInformationP *pi)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  struct TALER_MintSigningKeyValidityPS *issue = &pi->issue;

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
  issue->purpose.size = htonl (sizeof (struct TALER_MintSigningKeyValidityPS) -
                               offsetof (struct TALER_MintSigningKeyValidityPS,
                                         purpose));

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                                           &issue->purpose,
                                           &issue->signature.eddsa_signature));
}


/**
 * Generate signing keys starting from the last key found to
 * the lookahead time.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
mint_keys_update_signkeys ()
{
  struct GNUNET_TIME_Relative signkey_duration;
  struct GNUNET_TIME_Relative legal_duration;
  struct GNUNET_TIME_Absolute anchor;
  char *signkey_dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "mint_keys",
                                           "signkey_duration",
                                           &signkey_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint_keys",
                               "signkey_duration");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "mint_keys",
                                           "legal_duration",
                                           &legal_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint_keys",
                               "legal_duration");
    return GNUNET_SYSERR;
  }
  if (signkey_duration.rel_value_us < legal_duration.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "mint_keys",
                               "legal_duration",
                               "must be longer than signkey_duration");
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (signkey_duration,
                 rel_value_us);
  GNUNET_asprintf (&signkey_dir,
                   "%s" DIR_SEPARATOR_STR TALER_MINTDB_DIR_SIGNING_KEYS,
                   mint_directory);
  /* make sure the directory exists */
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (signkey_dir))
  {
    fprintf (stderr,
             "Failed to create signing key directory\n");
    return GNUNET_SYSERR;
  }

  get_anchor (signkey_dir,
              signkey_duration,
              GNUNET_TIME_UNIT_ZERO /* no overlap for signing keys */,
              &anchor);

  while (anchor.abs_value_us < lookahead_sign_stamp.abs_value_us)
  {
    const char *skf;
    struct TALER_MINTDB_PrivateSigningKeyInformationP signkey_issue;
    ssize_t nwrite;
    struct GNUNET_TIME_Absolute end;

    skf = get_signkey_file (anchor);
    end = GNUNET_TIME_absolute_add (anchor,
                                    legal_duration);
    GNUNET_break (GNUNET_YES !=
                  GNUNET_DISK_file_test (skf));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Generating signing key for %s.\n",
                GNUNET_STRINGS_absolute_time_to_string (anchor));
    create_signkey_issue_priv (anchor,
                               signkey_duration,
                               end,
                               &signkey_issue);
    nwrite = GNUNET_DISK_fn_write (skf,
                                   &signkey_issue,
                                   sizeof (struct TALER_MintSigningKeyValidityPS),
                                   GNUNET_DISK_PERM_USER_WRITE | GNUNET_DISK_PERM_USER_READ);
    if (nwrite != sizeof (struct TALER_MintSigningKeyValidityPS))
    {
      fprintf (stderr,
               "Failed to write to file `%s': %s\n",
               skf,
               STRERROR (errno));
      return GNUNET_SYSERR;
    }
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
  ROUND_TO_SECS (params->duration_withdraw,
                 rel_value_us);
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
  ROUND_TO_SECS (params->duration_spend,
                 rel_value_us);
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
  ROUND_TO_SECS (params->duration_legal,
                 rel_value_us);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "duration_overlap",
                                           &params->duration_overlap))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "mint_denom_duration_overlap");
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (params->duration_overlap,
                 rel_value_us);
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

  dir = get_cointype_dir (params);
  get_anchor (dir,
              params->duration_spend,
              params->duration_overlap,
              &params->anchor);
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
                       struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  dki->denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (params->rsa_keysize);
  GNUNET_assert (NULL != dki->denom_priv.rsa_private_key);
  dki->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &dki->issue.denom_hash);
  dki->issue.master = master_public_key;
  dki->issue.start = GNUNET_TIME_absolute_hton (params->anchor);
  dki->issue.expire_withdraw =
      GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                           params->duration_withdraw));
  dki->issue.expire_spend =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                         params->duration_spend));
  dki->issue.expire_legal =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                         params->duration_legal));
  TALER_amount_hton (&dki->issue.value,
                     &params->value);
  TALER_amount_hton (&dki->issue.fee_withdraw,
                     &params->fee_withdraw);
  TALER_amount_hton (&dki->issue.fee_deposit,
                     &params->fee_deposit);
  TALER_amount_hton (&dki->issue.fee_refresh,
                     &params->fee_refresh);
  dki->issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  dki->issue.purpose.size = htonl (sizeof (struct TALER_MINTDB_DenominationKeyIssueInformation) -
                                   offsetof (struct TALER_MINTDB_DenominationKeyIssueInformation,
                                             issue.purpose));
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                                           &dki->issue.purpose,
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
mint_keys_update_cointype (void *cls,
                           const char *coin_alias)
{
  int *ret = cls;
  struct CoinTypeParams p;
  const char *dkf;
  struct TALER_MINTDB_DenominationKeyIssueInformation denomkey_issue;

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
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create (get_cointype_dir (&p)))
  {
    *ret = GNUNET_SYSERR;
    return;
  }

  while (p.anchor.abs_value_us < lookahead_sign_stamp.abs_value_us)
  {
    dkf = get_cointype_file (&p,
                             p.anchor);
    GNUNET_break (GNUNET_YES != GNUNET_DISK_file_test (dkf));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Generating denomination key for type `%s', start %s at %s\n",
                coin_alias,
                GNUNET_STRINGS_absolute_time_to_string (p.anchor),
                dkf);
    create_denomkey_issue (&p,
                           &denomkey_issue);
    if (GNUNET_OK !=
        TALER_MINTDB_denomination_key_write (dkf,
                                    &denomkey_issue))
    {
      fprintf (stderr,
               "Failed to write denomination key information to file `%s'.\n",
               dkf);
      *ret = GNUNET_SYSERR;
      GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv.rsa_private_key);
      return;
    }
    GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv.rsa_private_key);
    p.anchor = GNUNET_TIME_absolute_add (p.anchor,
                                         p.duration_spend);
    p.anchor = GNUNET_TIME_absolute_subtract (p.anchor,
                                              p.duration_overlap);
  }
}


/**
 * Update all of the denomination keys of the mint.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
mint_keys_update_denomkeys ()
{
  int ok;

  ok = GNUNET_OK;
  GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                         &mint_keys_update_cointype,
                                         &ok);
  return ok;
}


/**
 * The main function of the taler-mint-keyup tool.  This tool is used
 * to create the signing and denomination keys for the mint.  It uses
 * the long-term offline private key and writes the (additional) key
 * files to the respective mint directory (from where they can then be
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
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'d', "mint-dir", "DIR",
     "mint directory with keys to update", 1,
     &GNUNET_GETOPT_set_filename, &mint_directory},
    TALER_GETOPT_OPTION_HELP ("Setup signing and denomination keys for a Taler mint"),
    {'m', "master-key", "FILE",
     "master key file (private key)", 1,
     &GNUNET_GETOPT_set_filename, &masterkeyfile},
    {'t', "time", "TIMESTAMP",
     "pretend it is a different time for the update", 0,
     &GNUNET_GETOPT_set_string, &pretend_time_str},
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_TIME_Relative lookahead_sign;
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-keyup",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-mint-keyup",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == mint_directory)
  {
    fprintf (stderr,
             "Mint directory not given\n");
    return 1;
  }
  if (NULL != pretend_time_str)
  {
    if (GNUNET_OK !=
        GNUNET_STRINGS_fancy_time_to_absolute (pretend_time_str,
                                               &now))
    {
      fprintf (stderr,
               "timestamp `%s' invalid\n",
               pretend_time_str);
      return 1;
    }
  }
  else
  {
    now = GNUNET_TIME_absolute_get ();
  }
  ROUND_TO_SECS (now, abs_value_us);

  kcfg = TALER_config_load (mint_directory);
  if (NULL == kcfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration\n");
    return 1;
  }
  if (NULL == masterkeyfile)
  {
    fprintf (stderr,
             "Master key file not given\n");
    return 1;
  }
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (masterkeyfile);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize master key from file `%s'\n",
             masterkeyfile);
    return 1;
  }
  master_priv.eddsa_priv = *eddsa_priv;
  GNUNET_free (eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_public_key.eddsa_pub);

  /* check if key from file matches the one from the configuration */
  {
    struct GNUNET_CRYPTO_EddsaPublicKey master_public_key_from_cfg;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_data (kcfg,
                                       "mint",
                                       "master_public_key",
                                       &master_public_key_from_cfg,
                                       sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "mint",
                                 "master_public_key");
      return 1;
    }
    if (0 !=
        memcmp (&master_public_key,
                &master_public_key_from_cfg,
                sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "mint",
                                 "master_public_key",
                                 _("does not match with private key"));
      return 1;
    }
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "mint_keys",
                                           "lookahead_sign",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint_keys",
                               "lookahead_sign");
    return GNUNET_SYSERR;
  }
  if (0 == lookahead_sign.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "mint_keys",
                               "lookahead_sign",
                               _("must not be zero"));
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (lookahead_sign,
                 rel_value_us);
  lookahead_sign_stamp = GNUNET_TIME_absolute_add (now,
                                                   lookahead_sign);


  /* finally, do actual work */
  if (GNUNET_OK != mint_keys_update_signkeys ())
    return 1;

  if (GNUNET_OK != mint_keys_update_denomkeys ())
    return 1;
  return 0;
}

/* end of taler-mint-keyup.c */
