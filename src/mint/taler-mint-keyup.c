/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

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
 */

#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_signatures.h"
#include "key_io.h"

/**
 * FIXME: allow user to specify (within reason).
 */
#define RSA_KEYSIZE 2048

#define HASH_CUTOFF 20

/**
 * Macro to round microseconds to seconds in GNUNET_TIME_* structs.
 */
#define ROUND_TO_SECS(name,us_field) name.us_field -= name.us_field % (1000 * 1000);


GNUNET_NETWORK_STRUCT_BEGIN

struct CoinTypeNBO
{
  struct GNUNET_TIME_RelativeNBO duration_spend;
  struct GNUNET_TIME_RelativeNBO duration_withdraw;
  struct TALER_AmountNBO value;
  struct TALER_AmountNBO fee_withdraw;
  struct TALER_AmountNBO fee_deposit;
  struct TALER_AmountNBO fee_refresh;
};

GNUNET_NETWORK_STRUCT_END

struct CoinTypeParams
{
  struct GNUNET_TIME_Relative duration_spend;
  struct GNUNET_TIME_Relative duration_withdraw;
  struct GNUNET_TIME_Relative duration_overlap;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct GNUNET_TIME_Absolute anchor;
};


/**
 * Filename of the master private key.
 */
static char *masterkeyfile;

/**
 * Director of the mint, containing the keys.
 */
static char *mintdir;

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
static struct GNUNET_CRYPTO_EddsaPrivateKey *master_priv;

/**
 * Master public key of the mint.
 */
static struct GNUNET_CRYPTO_EddsaPublicKey *master_pub;

/**
 * Until what time do we provide keys?
 */
static struct GNUNET_TIME_Absolute lookahead_sign_stamp;


static int
config_get_denom (const char *section, const char *option, struct TALER_Amount *denom)
{
  char *str;
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string (kcfg, section, option, &str))
    return GNUNET_NO;
  if (GNUNET_OK != TALER_string_to_amount (str, denom))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


static char *
get_signkey_dir ()
{
  char *dir;
  size_t len;
  len = GNUNET_asprintf (&dir, ("%s" DIR_SEPARATOR_STR DIR_SIGNKEYS), mintdir);
  GNUNET_assert (len > 0);
  return dir;
}


static char *
get_signkey_file (struct GNUNET_TIME_Absolute start)
{
  char *dir;
  size_t len;
  len = GNUNET_asprintf (&dir, ("%s" DIR_SEPARATOR_STR DIR_SIGNKEYS DIR_SEPARATOR_STR "%llu"),
                         mintdir, (long long) start.abs_value_us);
  GNUNET_assert (len > 0);
  return dir;
}


/**
 * Hash the data defining the coin type.
 * Exclude information that may not be the same for all
 * instances of the coin type (i.e. the anchor, overlap).
 */
static void
hash_coin_type (const struct CoinTypeParams *p, struct GNUNET_HashCode *hash)
{
  struct CoinTypeNBO p_nbo;

  memset (&p_nbo, 0, sizeof (struct CoinTypeNBO));

  p_nbo.duration_spend = GNUNET_TIME_relative_hton (p->duration_spend);
  p_nbo.duration_withdraw = GNUNET_TIME_relative_hton (p->duration_withdraw);
  p_nbo.value = TALER_amount_hton (p->value);
  p_nbo.fee_withdraw = TALER_amount_hton (p->fee_withdraw);
  p_nbo.fee_deposit = TALER_amount_hton (p->fee_deposit);
  p_nbo.fee_refresh = TALER_amount_hton (p->fee_refresh);

  GNUNET_CRYPTO_hash (&p_nbo, sizeof (struct CoinTypeNBO), hash);
}


static const char *
get_cointype_dir (const struct CoinTypeParams *p)
{
  static char dir[4096];
  size_t len;
  struct GNUNET_HashCode hash;
  char *hash_str;
  char *val_str;
  unsigned int i;

  hash_coin_type (p, &hash);
  hash_str = GNUNET_STRINGS_data_to_string_alloc (&hash,
                                                  sizeof (struct GNUNET_HashCode));
  GNUNET_assert (HASH_CUTOFF <= strlen (hash_str) + 1);
  GNUNET_assert (NULL != hash_str);
  hash_str[HASH_CUTOFF] = 0;

  val_str = TALER_amount_to_string (p->value);
  for (i = 0; i < strlen (val_str); i++)
    if (':' == val_str[i] || '.' == val_str[i])
      val_str[i] = '_';

  len = GNUNET_snprintf (dir, sizeof (dir),
                         ("%s" DIR_SEPARATOR_STR DIR_DENOMKEYS DIR_SEPARATOR_STR "%s-%s"),
                         mintdir, val_str, hash_str);
  GNUNET_assert (len > 0);
  GNUNET_free (hash_str);
  return dir;
}


static const char *
get_cointype_file (struct CoinTypeParams *p,
                   struct GNUNET_TIME_Absolute start)
{
  const char *dir;
  static char filename[4096];
  size_t len;
  dir = get_cointype_dir (p);
  len = GNUNET_snprintf (filename, sizeof (filename), ("%s" DIR_SEPARATOR_STR "%llu"),
                         dir, (unsigned long long) start.abs_value_us);
  GNUNET_assert (len > 0);
  return filename;
}


/**
 * Get the latest key file from the past.
 *
 * @param cls closure
 * @param filename complete filename (absolute path)
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
get_anchor_iter (void *cls,
                 const char *filename)
{
  struct GNUNET_TIME_Absolute stamp;
  struct GNUNET_TIME_Absolute *anchor = cls;
  const char *base;
  char *end = NULL;

  base = GNUNET_STRINGS_get_short_name (filename);
  stamp.abs_value_us = strtol (base, &end, 10);

  if ((NULL == end) || (0 != *end))
  {
    fprintf(stderr, "Ignoring unexpected file '%s'.\n", filename);
    return GNUNET_OK;
  }

  // TODO: check if it's actually a valid key file

  if ((stamp.abs_value_us <= now.abs_value_us) && (stamp.abs_value_us > anchor->abs_value_us))
    *anchor = stamp;

  return GNUNET_OK;
}


/**
 * Get the timestamp where the first new key should be generated.
 * Relies on correctly named key files.
 *
 * @param dir directory with the signed stuff
 * @param duration how long is one key valid?
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
  if (GNUNET_YES != GNUNET_DISK_directory_test (dir, GNUNET_YES))
  {
    *anchor = now;
    printf ("Can't look for anchor (%s)\n", dir);
    return;
  }

  *anchor = GNUNET_TIME_UNIT_ZERO_ABS;
  if (-1 == GNUNET_DISK_directory_scan (dir, &get_anchor_iter, anchor))
  {
    *anchor = now;
    return;
  }

  if ((GNUNET_TIME_absolute_add (*anchor, duration)).abs_value_us < now.abs_value_us)
  {
    // there's no good anchor, start from now
    // (existing keys are too old)
    *anchor = now;
  }
  else if (anchor->abs_value_us != now.abs_value_us)
  {
    // we have a good anchor
    *anchor = GNUNET_TIME_absolute_add (*anchor, duration);
    *anchor = GNUNET_TIME_absolute_subtract (*anchor, overlap);
  }
  // anchor is now the stamp where we need to create a new key
}


static void
create_signkey_issue_priv (struct GNUNET_TIME_Absolute start,
                           struct GNUNET_TIME_Relative duration,
                           struct TALER_MINT_SignKeyIssuePriv *pi)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  struct TALER_MINT_SignKeyIssue *issue = &pi->issue;

  priv = GNUNET_CRYPTO_eddsa_key_create ();
  GNUNET_assert (NULL != priv);
  pi->signkey_priv = *priv;
  GNUNET_free (priv);
  issue->master_pub = *master_pub;
  issue->start = GNUNET_TIME_absolute_hton (start);
  issue->expire = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (start, duration));

  GNUNET_CRYPTO_eddsa_key_get_public (&pi->signkey_priv, &issue->signkey_pub);

  issue->purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNKEY);
  issue->purpose.size = htonl (sizeof (struct TALER_MINT_SignKeyIssue) - offsetof (struct TALER_MINT_SignKeyIssue, purpose));

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (master_priv,
                                           &issue->purpose,
                                           &issue->signature));
}


static int
check_signkey_valid (const char *signkey_filename)
{
  // FIXME: do real checks
  return GNUNET_OK;
}


static int
mint_keys_update_signkeys ()
{
  struct GNUNET_TIME_Relative signkey_duration;
  struct GNUNET_TIME_Absolute anchor;
  char *signkey_dir;

  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_time (kcfg, "mint_keys", "signkey_duration", &signkey_duration))
  {
    fprintf (stderr, "Can't read config value mint_keys.signkey_duration\n");
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (signkey_duration, rel_value_us);
  signkey_dir = get_signkey_dir ();
  // make sure the directory exists
  if (GNUNET_OK != GNUNET_DISK_directory_create (signkey_dir))
  {
    fprintf (stderr, "Cant create signkey dir\n");
    return GNUNET_SYSERR;
  }

  get_anchor (signkey_dir, signkey_duration, GNUNET_TIME_UNIT_ZERO, &anchor);

  while (anchor.abs_value_us < lookahead_sign_stamp.abs_value_us) {
    char *skf;
    skf = get_signkey_file (anchor);
    if (GNUNET_YES != GNUNET_DISK_file_test (skf))
    {
      struct TALER_MINT_SignKeyIssuePriv signkey_issue;
      ssize_t nwrite;
      printf ("Generating signing key for %s.\n",
              GNUNET_STRINGS_absolute_time_to_string (anchor));
      create_signkey_issue_priv (anchor, signkey_duration, &signkey_issue);
      nwrite = GNUNET_DISK_fn_write (skf, &signkey_issue, sizeof (struct TALER_MINT_SignKeyIssue),
                                     (GNUNET_DISK_PERM_USER_WRITE | GNUNET_DISK_PERM_USER_READ));
      if (nwrite != sizeof (struct TALER_MINT_SignKeyIssue))
      {
        fprintf (stderr, "Can't write to file '%s'\n", skf);
        return GNUNET_SYSERR;
      }
    }
    else if (GNUNET_OK != check_signkey_valid (skf))
    {
      return GNUNET_SYSERR;
    }
    anchor = GNUNET_TIME_absolute_add (anchor, signkey_duration);
  }
  return GNUNET_OK;
}


static int
get_cointype_params (const char *ct, struct CoinTypeParams *params)
{
  const char *dir;
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_time (kcfg, "mint_denom_duration_withdraw", ct, &params->duration_withdraw))
  {
    fprintf (stderr, "Withdraw duration not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (params->duration_withdraw, rel_value_us);
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_time (kcfg, "mint_denom_duration_spend", ct, &params->duration_spend))
  {
    fprintf (stderr, "Spend duration not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (params->duration_spend, rel_value_us);
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_time (kcfg, "mint_denom_duration_overlap", ct, &params->duration_overlap))
  {
    fprintf (stderr, "Overlap duration not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (params->duration_overlap, rel_value_us);

  if (GNUNET_OK != config_get_denom ("mint_denom_value", ct, &params->value))
  {
    fprintf (stderr, "Value not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK != config_get_denom ("mint_denom_fee_withdraw", ct, &params->fee_withdraw))
  {
    fprintf (stderr, "Withdraw fee not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK != config_get_denom ("mint_denom_fee_deposit", ct, &params->fee_deposit))
  {
    fprintf (stderr, "Deposit fee not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK != config_get_denom ("mint_denom_fee_refresh", ct, &params->fee_refresh))
  {
    fprintf (stderr, "Deposit fee not given for coin type '%s'\n", ct);
    return GNUNET_SYSERR;
  }

  dir = get_cointype_dir (params);
  get_anchor (dir, params->duration_spend, params->duration_overlap, &params->anchor);
  return GNUNET_OK;
}


static void
create_denomkey_issue (struct CoinTypeParams *params,
                       struct TALER_MINT_DenomKeyIssuePriv *dki)
{
  GNUNET_assert (NULL != (dki->denom_priv = GNUNET_CRYPTO_rsa_private_key_create (RSA_KEYSIZE)));
  dki->denom_pub = GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv);
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub,
                                     &dki->issue.denom_hash);
  dki->issue.master = *master_pub;
  dki->issue.start = GNUNET_TIME_absolute_hton (params->anchor);
  dki->issue.expire_withdraw =
      GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                           params->duration_withdraw));
  dki->issue.expire_spend =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (params->anchor,
                                                           params->duration_spend));
  dki->issue.value = TALER_amount_hton (params->value);
  dki->issue.fee_withdraw = TALER_amount_hton (params->fee_withdraw);
  dki->issue.fee_deposit = TALER_amount_hton (params->fee_deposit);
  dki->issue.fee_refresh = TALER_amount_hton (params->fee_refresh);

  dki->issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOM);
  dki->issue.purpose.size = htonl (sizeof (struct TALER_MINT_DenomKeyIssuePriv) - offsetof (struct TALER_MINT_DenomKeyIssuePriv, issue.purpose));

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (master_priv,
                                           &dki->issue.purpose,
                                           &dki->issue.signature));
}


static int
check_cointype_valid (const char *filename, struct CoinTypeParams *params)
{
  // FIXME: add real checks
  return GNUNET_OK;
}


static int
mint_keys_update_cointype (const char *coin_alias)
{
  struct CoinTypeParams p;
  const char *cointype_dir;

  if (GNUNET_OK != get_cointype_params (coin_alias, &p))
    return GNUNET_SYSERR;

  cointype_dir = get_cointype_dir (&p);
  if (GNUNET_OK != GNUNET_DISK_directory_create (cointype_dir))
    return GNUNET_SYSERR;

  while (p.anchor.abs_value_us < lookahead_sign_stamp.abs_value_us) {
    const char *dkf;
    dkf = get_cointype_file (&p, p.anchor);

    if (GNUNET_YES != GNUNET_DISK_file_test (dkf))
    {
      struct TALER_MINT_DenomKeyIssuePriv denomkey_issue;
      int ret;
      printf ("Generating denomination key for type '%s', start %s.\n",
              coin_alias,
              GNUNET_STRINGS_absolute_time_to_string (p.anchor));
      printf ("Target path: %s\n", dkf);
      create_denomkey_issue (&p, &denomkey_issue);
      ret = TALER_MINT_write_denom_key (dkf, &denomkey_issue);
      GNUNET_CRYPTO_rsa_private_key_free (denomkey_issue.denom_priv);
      if (GNUNET_OK != ret)
      {
        fprintf (stderr, "Can't write to file '%s'\n", dkf);
        return GNUNET_SYSERR;
      }
    }
    else if (GNUNET_OK != check_cointype_valid (dkf, &p))
    {
      return GNUNET_SYSERR;
    }
    p.anchor = GNUNET_TIME_absolute_add (p.anchor, p.duration_spend);
    p.anchor = GNUNET_TIME_absolute_subtract (p.anchor, p.duration_overlap);
  }
  return GNUNET_OK;
}


static int
mint_keys_update_denomkeys ()
{
  char *coin_types;
  char *ct;
  char *tok_ctx;

  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string (kcfg, "mint_keys", "coin_types", &coin_types))
  {
    fprintf (stderr, "mint_keys.coin_types not in configuration\n");
    return GNUNET_SYSERR;
  }

  for (ct = strtok_r (coin_types, " ", &tok_ctx);
       ct != NULL;
       ct = strtok_r (NULL, " ", &tok_ctx))
  {
    if (GNUNET_OK != mint_keys_update_cointype (ct))
    {
      GNUNET_free (coin_types);
      return GNUNET_SYSERR;
    }
  }
  GNUNET_free (coin_types);
  return GNUNET_OK;
}


static int
mint_keys_update ()
{
  int ret;
  struct GNUNET_TIME_Relative lookahead_sign;
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_time (kcfg, "mint_keys", "lookahead_sign", &lookahead_sign))
  {
    fprintf (stderr, "mint_keys.lookahead_sign not found\n");
    return GNUNET_SYSERR;
  }
  if (lookahead_sign.rel_value_us == 0)
  {
    fprintf (stderr, "mint_keys.lookahead_sign must not be zero\n");
    return GNUNET_SYSERR;
  }
  ROUND_TO_SECS (lookahead_sign, rel_value_us);
  lookahead_sign_stamp = GNUNET_TIME_absolute_add (now, lookahead_sign);

  ret = mint_keys_update_signkeys ();
  if (GNUNET_OK != ret)
    return GNUNET_SYSERR;

  return mint_keys_update_denomkeys ();
}


/**
 * The main function of the keyup tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc, char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keyup OPTIONS"),
    {'m', "master-key", "FILE",
     "master key file (private key)", 1,
     &GNUNET_GETOPT_set_filename, &masterkeyfile},
    {'d', "mint-dir", "DIR",
     "mint directory with keys to update", 1,
     &GNUNET_GETOPT_set_filename, &mintdir},
    {'t', "time", "TIMESTAMP",
     "pretend it is a different time for the update", 0,
     &GNUNET_GETOPT_set_string, &pretend_time_str},
    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert (GNUNET_OK == GNUNET_log_setup ("taler-mint-keyup", "WARNING", NULL));

  if (GNUNET_GETOPT_run ("taler-mint-keyup", options, argc, argv) < 0)
    return 1;
  if (NULL == mintdir)
  {
    fprintf (stderr, "mint directory not given\n");
    return 1;
  }

  if (NULL != pretend_time_str)
  {
    if (GNUNET_OK != GNUNET_STRINGS_fancy_time_to_absolute (pretend_time_str, &now))
    {
      fprintf (stderr, "timestamp invalid\n");
      return 1;
    }
  }
  else
  {
    now = GNUNET_TIME_absolute_get ();
  }
  ROUND_TO_SECS (now, abs_value_us);

  kcfg = TALER_config_load (mintdir);
  if (NULL == kcfg)
  {
    fprintf (stderr, "can't load mint configuration\n");
    return 1;
  }

  if (NULL == masterkeyfile)
  {
    fprintf (stderr, "master key file not given\n");
    return 1;
  }
  master_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (masterkeyfile);
  if (NULL == master_priv)
  {
    fprintf (stderr, "master key invalid\n");
    return 1;
  }

  master_pub = GNUNET_new (struct GNUNET_CRYPTO_EddsaPublicKey);
  GNUNET_CRYPTO_eddsa_key_get_public (master_priv, master_pub);

  // check if key from file matches the one from the configuration
  {
    struct GNUNET_CRYPTO_EddsaPublicKey master_pub_from_cfg;
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_data (kcfg, "mint", "master_pub",
                                       &master_pub_from_cfg,
                                       sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
    {
      fprintf (stderr, "master key missing in configuration (mint.master_pub)\n");
      return 1;
    }
    if (0 != memcmp (master_pub, &master_pub_from_cfg, sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
    {
      fprintf (stderr, "Mismatch between key from mint configuration and master private key file from command line.\n");
      return 1;
    }
  }

  if (GNUNET_OK != mint_keys_update ())
    return 1;
  return 0;
}
