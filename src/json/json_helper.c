/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file json/json_helper.c
 * @brief helper functions to generate specifications to parse
 *        Taler-specific JSON objects with libgnunetjson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Convert string value to numeric cipher value.
 *
 * @param cipher_s input string
 * @return numeric cipher value
 */
static enum GNUNET_CRYPTO_BlindSignatureAlgorithm
string_to_cipher (const char *cipher_s)
{
  if ((0 == strcasecmp (cipher_s,
                        "RSA")) ||
      (0 == strcasecmp (cipher_s,
                        "RSA+age_restricted")))
    return GNUNET_CRYPTO_BSA_RSA;
  if ((0 == strcasecmp (cipher_s,
                        "CS")) ||
      (0 == strcasecmp (cipher_s,
                        "CS+age_restricted")))
    return GNUNET_CRYPTO_BSA_CS;
  return GNUNET_CRYPTO_BSA_INVALID;
}


json_t *
TALER_JSON_from_amount (const struct TALER_Amount *amount)
{
  char *amount_str = TALER_amount_to_string (amount);

  GNUNET_assert (NULL != amount_str);
  {
    json_t *j = json_string (amount_str);

    GNUNET_free (amount_str);
    return j;
  }
}


/**
 * Parse given JSON object to Amount
 *
 * @param cls closure, expected currency, or NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_amount (void *cls,
              json_t *root,
              struct GNUNET_JSON_Specification *spec)
{
  const char *currency = cls;
  struct TALER_Amount *r_amount = spec->ptr;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount (json_string_value (root),
                              r_amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (NULL != currency) &&
       (0 !=
        strcasecmp (currency,
                    r_amount->currency)) )
  {
    GNUNET_break_op (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Expected currency `%s', but amount used currency `%s' in field `%s'\n",
                currency,
                r_amount->currency,
                spec->field);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        const char *currency,
                        struct TALER_Amount *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount,
    .cleaner = NULL,
    .cls = (void *) currency,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };

  GNUNET_assert (NULL != currency);
  return ret;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_any (const char *name,
                            struct TALER_Amount *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };

  return ret;
}


/**
 * Parse given JSON object to currency spec.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_cspec (void *cls,
             json_t *root,
             struct GNUNET_JSON_Specification *spec)
{
  struct TALER_CurrencySpecification *r_cspec = spec->ptr;
  const char *currency = spec->cls;
  const char *name;
  uint32_t fid;
  uint32_t fnd;
  uint32_t ftzd;
  const json_t *map;
  struct GNUNET_JSON_Specification gspec[] = {
    GNUNET_JSON_spec_string ("name",
                             &name),
    GNUNET_JSON_spec_uint32 ("num_fractional_input_digits",
                             &fid),
    GNUNET_JSON_spec_uint32 ("num_fractional_normal_digits",
                             &fnd),
    GNUNET_JSON_spec_uint32 ("num_fractional_trailing_zero_digits",
                             &ftzd),
    GNUNET_JSON_spec_object_const ("alt_unit_names",
                                   &map),
    GNUNET_JSON_spec_end ()
  };
  const char *emsg;
  unsigned int eline;

  memset (r_cspec->currency,
          0,
          sizeof (r_cspec->currency));
  if (GNUNET_OK !=
      GNUNET_JSON_parse (root,
                         gspec,
                         &emsg,
                         &eline))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to parse %s at %u: %s\n",
                spec[eline].field,
                eline,
                emsg);
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (strlen (currency) >= TALER_CURRENCY_LEN)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (fid > TALER_AMOUNT_FRAC_LEN) ||
       (fnd > TALER_AMOUNT_FRAC_LEN) ||
       (ftzd > TALER_AMOUNT_FRAC_LEN) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_check_currency (currency))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  strcpy (r_cspec->currency,
          currency);
  if (GNUNET_OK !=
      TALER_check_currency_scale_map (map))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  r_cspec->name = GNUNET_strdup (name);
  r_cspec->map_alt_unit_names = json_incref ((json_t *) map);
  return GNUNET_OK;
}


/**
 * Cleanup data left from parsing encrypted contract.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_cspec (void *cls,
             struct GNUNET_JSON_Specification *spec)
{
  struct TALER_CurrencySpecification *cspec = spec->ptr;

  (void) cls;
  GNUNET_free (cspec->name);
  json_decref (cspec->map_alt_unit_names);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_currency_specification (
  const char *name,
  const char *currency,
  struct TALER_CurrencySpecification *r_cspec)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_cspec,
    .cleaner = &clean_cspec,
    .cls = (void *) currency,
    .field = name,
    .ptr = r_cspec,
    .ptr_size = sizeof (*r_cspec),
    .size_ptr = NULL
  };

  memset (r_cspec,
          0,
          sizeof (*r_cspec));
  return ret;
}


static enum GNUNET_GenericReturnValue
parse_denomination_group (void *cls,
                          json_t *root,
                          struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationGroup *group = spec->ptr;
  const char *cipher;
  const char *currency = cls;
  bool age_mask_missing = false;
  bool has_age_restricted_suffix = false;
  struct GNUNET_JSON_Specification gspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
    TALER_JSON_spec_amount ("value",
                            currency,
                            &group->value),
    TALER_JSON_SPEC_DENOM_FEES ("fee",
                                currency,
                                &group->fees),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_uint32 ("age_mask",
                               &group->age_mask.bits),
      &age_mask_missing),
    GNUNET_JSON_spec_end ()
  };
  const char *emsg;
  unsigned int eline;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (root,
                         gspec,
                         &emsg,
                         &eline))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to parse %s at %u: %s\n",
                spec[eline].field,
                eline,
                emsg);
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  group->cipher = string_to_cipher (cipher);
  if (GNUNET_CRYPTO_BSA_INVALID == group->cipher)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* age_mask and suffix must be consistent */
  has_age_restricted_suffix =
    (NULL != strstr (cipher, "+age_restricted"));
  if (has_age_restricted_suffix && age_mask_missing)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (age_mask_missing)
    group->age_mask.bits = 0;

  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_group (const char *name,
                                    const char *currency,
                                    struct TALER_DenominationGroup *group)
{
  struct GNUNET_JSON_Specification ret = {
    .cls = (void *) currency,
    .parser = &parse_denomination_group,
    .field = name,
    .ptr = group,
    .ptr_size = sizeof(*group)
  };

  return ret;
}


/**
 * Parse given JSON object to an encrypted contract.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_econtract (void *cls,
                 json_t *root,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_EncryptedContract *econtract = spec->ptr;
  struct GNUNET_JSON_Specification ispec[] = {
    GNUNET_JSON_spec_varsize ("econtract",
                              &econtract->econtract,
                              &econtract->econtract_size),
    GNUNET_JSON_spec_fixed_auto ("econtract_sig",
                                 &econtract->econtract_sig),
    GNUNET_JSON_spec_fixed_auto ("contract_pub",
                                 &econtract->contract_pub),
    GNUNET_JSON_spec_end ()
  };
  const char *emsg;
  unsigned int eline;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (root,
                         ispec,
                         &emsg,
                         &eline))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Cleanup data left from parsing encrypted contract.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_econtract (void *cls,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_EncryptedContract *econtract = spec->ptr;

  (void) cls;
  GNUNET_free (econtract->econtract);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_econtract (const char *name,
                           struct TALER_EncryptedContract *econtract)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_econtract,
    .cleaner = &clean_econtract,
    .field = name,
    .ptr = econtract
  };

  return ret;
}


/**
 * Parse given JSON object to an age commitmnet
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_age_commitment (void *cls,
                      json_t *root,
                      struct GNUNET_JSON_Specification *spec)
{
  struct TALER_AgeCommitment *age_commitment = spec->ptr;
  json_t *pk;
  unsigned int idx;
  size_t num;

  (void) cls;
  if ( (NULL == root) ||
       (! json_is_array (root)))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  num = json_array_size (root);
  if (32 <= num || 0 == num)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  age_commitment->num = num;
  age_commitment->keys =
    GNUNET_new_array (num,
                      struct TALER_AgeCommitmentPublicKeyP);

  json_array_foreach (root, idx, pk) {
    const char *emsg;
    unsigned int eline;
    struct GNUNET_JSON_Specification pkspec[] = {
      GNUNET_JSON_spec_fixed_auto (
        NULL,
        &age_commitment->keys[idx].pub),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (pk,
                           pkspec,
                           &emsg,
                           &eline))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
  };

  return GNUNET_OK;
}


/**
 * Cleanup data left from parsing age commitment
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_age_commitment (void *cls,
                      struct GNUNET_JSON_Specification *spec)
{
  struct TALER_AgeCommitment *age_commitment = spec->ptr;

  (void) cls;

  if (NULL == age_commitment ||
      NULL == age_commitment->keys)
    return;

  age_commitment->num = 0;
  GNUNET_free (age_commitment->keys);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_age_commitment (const char *name,
                                struct TALER_AgeCommitment *age_commitment)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_age_commitment,
    .cleaner = &clean_age_commitment,
    .field = name,
    .ptr = age_commitment
  };

  return ret;
}

struct GNUNET_JSON_Specification
TALER_JSON_spec_token_issue_sig (const char *field,
                                 struct TALER_TokenIssueSignatureP *sig)
{
  sig->signature = NULL;
  return GNUNET_JSON_spec_unblinded_signature (field,
                                               &sig->signature);
}

struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_token_issue_sig (
  const char *field,
  struct TALER_TokenIssueBlindSignatureP *sig)
{
  sig->signature = NULL;
  return GNUNET_JSON_spec_blinded_signature (field,
                                             &sig->signature);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_token_envelope (const char *field,
                                struct TALER_TokenEnvelopeP *env)
{
  env->blinded_pub = NULL;
  return GNUNET_JSON_spec_blinded_message (field,
                                           &env->blinded_pub);
}


/**
 * Parse given JSON object to denomination public key.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_denom_pub (void *cls,
                 json_t *root,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationPublicKey *denom_pub = spec->ptr;
  struct GNUNET_CRYPTO_BlindSignPublicKey *bsign_pub;
  const char *cipher;
  bool age_mask_missing = false;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_uint32 ("age_mask",
                               &denom_pub->age_mask.bits),
      &age_mask_missing),
    GNUNET_JSON_spec_end ()
  };
  const char *emsg;
  unsigned int eline;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (root,
                         dspec,
                         &emsg,
                         &eline))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (age_mask_missing)
    denom_pub->age_mask.bits = 0;
  bsign_pub = GNUNET_new (struct GNUNET_CRYPTO_BlindSignPublicKey);
  bsign_pub->rc = 1;
  bsign_pub->cipher = string_to_cipher (cipher);
  switch (bsign_pub->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_public_key (
          "rsa_public_key",
          &bsign_pub->details.rsa_public_key),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (root,
                             ispec,
                             &emsg,
                             &eline))
      {
        GNUNET_break_op (0);
        GNUNET_free (bsign_pub);
        return GNUNET_SYSERR;
      }
      denom_pub->bsign_pub_key = bsign_pub;
      return GNUNET_OK;
    }
  case GNUNET_CRYPTO_BSA_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed ("cs_public_key",
                                &bsign_pub->details.cs_public_key,
                                sizeof (bsign_pub->details.cs_public_key)),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (root,
                             ispec,
                             &emsg,
                             &eline))
      {
        GNUNET_break_op (0);
        GNUNET_free (bsign_pub);
        return GNUNET_SYSERR;
      }
      denom_pub->bsign_pub_key = bsign_pub;
      return GNUNET_OK;
    }
  }
  GNUNET_break_op (0);
  GNUNET_free (bsign_pub);
  return GNUNET_SYSERR;
}


/**
 * Cleanup data left from parsing denomination public key.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_denom_pub (void *cls,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationPublicKey *denom_pub = spec->ptr;

  (void) cls;
  TALER_denom_pub_free (denom_pub);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_pub (const char *field,
                           struct TALER_DenominationPublicKey *pk)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_denom_pub,
    .cleaner = &clean_denom_pub,
    .field = field,
    .ptr = pk
  };

  pk->bsign_pub_key = NULL;
  return ret;
}


/**
 * Parse given JSON object partially into a denomination public key.
 *
 * Depending on the cipher in cls, it parses the corresponding public key type.
 *
 * @param cls closure, enum GNUNET_CRYPTO_BlindSignatureAlgorithm
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_denom_pub_cipher (void *cls,
                        json_t *root,
                        struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationPublicKey *denom_pub = spec->ptr;
  enum GNUNET_CRYPTO_BlindSignatureAlgorithm cipher =
    (enum GNUNET_CRYPTO_BlindSignatureAlgorithm) (long) cls;
  struct GNUNET_CRYPTO_BlindSignPublicKey *bsign_pub;
  const char *emsg;
  unsigned int eline;

  bsign_pub = GNUNET_new (struct GNUNET_CRYPTO_BlindSignPublicKey);
  bsign_pub->cipher = cipher;
  bsign_pub->rc = 1;
  switch (cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_public_key (
          "rsa_pub",
          &bsign_pub->details.rsa_public_key),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (root,
                             ispec,
                             &emsg,
                             &eline))
      {
        GNUNET_break_op (0);
        GNUNET_free (bsign_pub);
        return GNUNET_SYSERR;
      }
      denom_pub->bsign_pub_key = bsign_pub;
      return GNUNET_OK;
    }
  case GNUNET_CRYPTO_BSA_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed ("cs_pub",
                                &bsign_pub->details.cs_public_key,
                                sizeof (bsign_pub->details.cs_public_key)),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (root,
                             ispec,
                             &emsg,
                             &eline))
      {
        GNUNET_break_op (0);
        GNUNET_free (bsign_pub);
        return GNUNET_SYSERR;
      }
      denom_pub->bsign_pub_key = bsign_pub;
      return GNUNET_OK;
    }
  }
  GNUNET_break_op (0);
  GNUNET_free (bsign_pub);
  return GNUNET_SYSERR;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_pub_cipher (const char *field,
                                  enum GNUNET_CRYPTO_BlindSignatureAlgorithm
                                  cipher,
                                  struct TALER_DenominationPublicKey *pk)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_denom_pub_cipher,
    .cleaner = &clean_denom_pub,
    .field = field,
    .cls = (void *) cipher,
    .ptr = pk
  };

  return ret;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_sig (const char *field,
                           struct TALER_DenominationSignature *sig)
{
  sig->unblinded_sig = NULL;
  return GNUNET_JSON_spec_unblinded_signature (field,
                                               &sig->unblinded_sig);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_denom_sig (
  const char *field,
  struct TALER_BlindedDenominationSignature *sig)
{
  sig->blinded_sig = NULL;
  return GNUNET_JSON_spec_blinded_signature (field,
                                             &sig->blinded_sig);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_planchet (const char *field,
                                  struct TALER_BlindedPlanchet *blinded_planchet)
{
  blinded_planchet->blinded_message = NULL;
  return GNUNET_JSON_spec_blinded_message (field,
                                           &blinded_planchet->blinded_message);
}


/**
 * Parse given JSON object to exchange withdraw values (/csr).
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_exchange_withdraw_values (void *cls,
                                json_t *root,
                                struct GNUNET_JSON_Specification *spec)
{
  struct TALER_ExchangeWithdrawValues *ewv = spec->ptr;
  struct GNUNET_CRYPTO_BlindingInputValues *bi;
  const char *cipher;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
    GNUNET_JSON_spec_end ()
  };
  const char *emsg;
  unsigned int eline;
  enum GNUNET_CRYPTO_BlindSignatureAlgorithm ci;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (root,
                         dspec,
                         &emsg,
                         &eline))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  ci = string_to_cipher (cipher);
  switch (ci)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ewv->blinding_inputs = TALER_denom_ewv_rsa_singleton ()->blinding_inputs;
    return GNUNET_OK;
  case GNUNET_CRYPTO_BSA_CS:
    bi = GNUNET_new (struct GNUNET_CRYPTO_BlindingInputValues);
    bi->cipher = GNUNET_CRYPTO_BSA_CS;
    bi->rc = 1;
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed (
          "r_pub_0",
          &bi->details.cs_values.r_pub[0],
          sizeof (struct GNUNET_CRYPTO_CsRPublic)),
        GNUNET_JSON_spec_fixed (
          "r_pub_1",
          &bi->details.cs_values.r_pub[1],
          sizeof (struct GNUNET_CRYPTO_CsRPublic)),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (root,
                             ispec,
                             &emsg,
                             &eline))
      {
        GNUNET_break_op (0);
        GNUNET_free (bi);
        return GNUNET_SYSERR;
      }
      ewv->blinding_inputs = bi;
      return GNUNET_OK;
    }
  }
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


/**
 * Cleanup data left from parsing withdraw values
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_exchange_withdraw_values (
  void *cls,
  struct GNUNET_JSON_Specification *spec)
{
  struct TALER_ExchangeWithdrawValues *ewv = spec->ptr;

  (void) cls;
  TALER_denom_ewv_free (ewv);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_exchange_withdraw_values (
  const char *field,
  struct TALER_ExchangeWithdrawValues *ewv)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_exchange_withdraw_values,
    .cleaner = &clean_exchange_withdraw_values,
    .field = field,
    .ptr = ewv
  };

  ewv->blinding_inputs = NULL;
  return ret;
}


/**
 * Closure for #parse_i18n_string.
 */
struct I18nContext
{
  /**
   * Language pattern to match.
   */
  char *lp;

  /**
   * Name of the field to match.
   */
  const char *field;
};


/**
 * Parse given JSON object to internationalized string.
 *
 * @param cls closure, our `struct I18nContext *`
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_i18n_string (void *cls,
                   json_t *root,
                   struct GNUNET_JSON_Specification *spec)
{
  struct I18nContext *ctx = cls;
  json_t *i18n;
  json_t *val;

  {
    char *i18nf;

    GNUNET_asprintf (&i18nf,
                     "%s_i18n",
                     ctx->field);
    i18n = json_object_get (root,
                            i18nf);
    GNUNET_free (i18nf);
  }

  val = json_object_get (root,
                         ctx->field);
  if ( (NULL != i18n) &&
       (NULL != ctx->lp) )
  {
    double best = 0.0;
    json_t *pos;
    const char *lang;

    json_object_foreach (i18n, lang, pos)
    {
      double score;

      score = TALER_language_matches (ctx->lp,
                                      lang);
      if (score > best)
      {
        best = score;
        val = pos;
      }
    }
  }

  {
    const char *str;

    str = json_string_value (val);
    *(const char **) spec->ptr = str;
  }
  return GNUNET_OK;
}


/**
 * Function called to clean up data from earlier parsing.
 *
 * @param cls closure
 * @param spec our specification entry with data to clean.
 */
static void
i18n_cleaner (void *cls,
              struct GNUNET_JSON_Specification *spec)
{
  struct I18nContext *ctx = cls;

  (void) spec;
  if (NULL != ctx)
  {
    GNUNET_free (ctx->lp);
    GNUNET_free (ctx);
  }
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_string (const char *name,
                             const char *language_pattern,
                             const char **strptr)
{
  struct I18nContext *ctx = GNUNET_new (struct I18nContext);
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_i18n_string,
    .cleaner = &i18n_cleaner,
    .cls = ctx,
    .field = NULL, /* we want the main object */
    .ptr = strptr,
    .ptr_size = 0,
    .size_ptr = NULL
  };

  ctx->lp = (NULL != language_pattern)
    ? GNUNET_strdup (language_pattern)
    : NULL;
  ctx->field = name;
  *strptr = NULL;
  return ret;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_str (const char *name,
                          const char **strptr)
{
  const char *lang = getenv ("LANG");
  char *dot;
  char *l;
  struct GNUNET_JSON_Specification ret;

  if (NULL != lang)
  {
    dot = strchr (lang,
                  '.');
    if (NULL == dot)
      l = GNUNET_strdup (lang);
    else
      l = GNUNET_strndup (lang,
                          dot - lang);
  }
  else
  {
    l = NULL;
  }
  ret = TALER_JSON_spec_i18n_string (name,
                                     l,
                                     strptr);
  GNUNET_free (l);
  return ret;
}


/**
 * Parse given JSON object with Taler error code.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_ec (void *cls,
          json_t *root,
          struct GNUNET_JSON_Specification *spec)
{
  enum TALER_ErrorCode *ec = spec->ptr;
  json_int_t num;

  (void) cls;
  if (! json_is_integer (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  num = json_integer_value (root);
  if (num < 0)
  {
    GNUNET_break_op (0);
    *ec = TALER_EC_INVALID;
    return GNUNET_SYSERR;
  }
  *ec = (enum TALER_ErrorCode) num;
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_ec (const char *field,
                    enum TALER_ErrorCode *ec)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_ec,
    .field = field,
    .ptr = ec
  };

  *ec = TALER_EC_NONE;
  return ret;
}


/**
 * Parse given JSON object with AML decision.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_aml_decision (void *cls,
                    json_t *root,
                    struct GNUNET_JSON_Specification *spec)
{
  enum TALER_AmlDecisionState *aml = spec->ptr;
  json_int_t num;

  (void) cls;
  if (! json_is_integer (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  num = json_integer_value (root);
  if ( (num > TALER_AML_MAX) ||
       (num < 0) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  *aml = (enum TALER_AmlDecisionState) num;
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_aml_decision (const char *field,
                              enum TALER_AmlDecisionState *aml_state)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_aml_decision,
    .field = field,
    .ptr = aml_state
  };

  return ret;
}


/**
 * Parse given JSON object to web URL.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_web_url (void *cls,
               json_t *root,
               struct GNUNET_JSON_Specification *spec)
{
  const char *str;

  (void) cls;
  str = json_string_value (root);
  if (NULL == str)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (! TALER_is_web_url (str))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  *(const char **) spec->ptr = str;
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_web_url (const char *field,
                         const char **url)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_web_url,
    .field = field,
    .ptr = url
  };

  *url = NULL;
  return ret;
}


/**
 * Parse given JSON object to payto:// URI.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_payto_uri (void *cls,
                 json_t *root,
                 struct GNUNET_JSON_Specification *spec)
{
  const char *str;
  char *err;

  (void) cls;
  str = json_string_value (root);
  if (NULL == str)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  err = TALER_payto_validate (str);
  if (NULL != err)
  {
    GNUNET_break_op (0);
    GNUNET_free (err);
    return GNUNET_SYSERR;
  }
  *(const char **) spec->ptr = str;
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_payto_uri (const char *field,
                           const char **payto_uri)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_payto_uri,
    .field = field,
    .ptr = payto_uri
  };

  *payto_uri = NULL;
  return ret;
}


/**
 * Parse given JSON object with protocol version.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_protocol_version (void *cls,
                        json_t *root,
                        struct GNUNET_JSON_Specification *spec)
{
  struct TALER_JSON_ProtocolVersion *pv = spec->ptr;
  const char *ver;
  char dummy;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  ver = json_string_value (root);
  if (3 != sscanf (ver,
                   "%u:%u:%u%c",
                   &pv->current,
                   &pv->revision,
                   &pv->age,
                   &dummy))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_version (const char *field,
                         struct TALER_JSON_ProtocolVersion *ver)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_protocol_version,
    .field = field,
    .ptr = ver
  };

  return ret;
}


/**
 * Parse given JSON object to an OTP key.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_otp_key (void *cls,
               json_t *root,
               struct GNUNET_JSON_Specification *spec)
{
  const char *pos_key;

  (void) cls;
  pos_key = json_string_value (root);
  if (NULL == pos_key)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  {
    size_t pos_key_length = strlen (pos_key);
    void *key; /* pos_key in binary */
    size_t key_len; /* length of the key */
    int dret;

    key_len = pos_key_length * 5 / 8;
    key = GNUNET_malloc (key_len);
    dret = TALER_rfc3548_base32decode (pos_key,
                                       pos_key_length,
                                       key,
                                       key_len);
    if (-1 == dret)
    {
      GNUNET_free (key);
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    GNUNET_free (key);
  }
  *(const char **) spec->ptr = pos_key;
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_otp_key (const char *name,
                         const char **otp_key)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_otp_key,
    .field = name,
    .ptr = otp_key
  };

  *otp_key = NULL;
  return ret;
}


/**
 * Parse given JSON object to `enum TALER_MerchantConfirmationAlgorithm`
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_otp_type (void *cls,
                json_t *root,
                struct GNUNET_JSON_Specification *spec)
{
  static const struct Entry
  {
    const char *name;
    enum TALER_MerchantConfirmationAlgorithm val;
  } lt [] = {
    { .name = "NONE",
      .val = TALER_MCA_NONE },
    { .name = "TOTP_WITHOUT_PRICE",
      .val = TALER_MCA_WITHOUT_PRICE },
    { .name = "TOTP_WITH_PRICE",
      .val = TALER_MCA_WITH_PRICE },
    { .name = NULL,
      .val = TALER_MCA_NONE },
  };
  enum TALER_MerchantConfirmationAlgorithm *res
    = (enum TALER_MerchantConfirmationAlgorithm *) spec->ptr;

  (void) cls;
  if (json_is_string (root))
  {
    const char *str;

    str = json_string_value (root);
    if (NULL == str)
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    for (unsigned int i = 0; NULL != lt[i].name; i++)
    {
      if (0 == strcasecmp (str,
                           lt[i].name))
      {
        *res = lt[i].val;
        return GNUNET_OK;
      }
    }
    GNUNET_break_op (0);
  }
  if (json_is_integer (root))
  {
    json_int_t val;

    val = json_integer_value (root);
    for (unsigned int i = 0; NULL != lt[i].name; i++)
    {
      if (val == lt[i].val)
      {
        *res = lt[i].val;
        return GNUNET_OK;
      }
    }
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_otp_type (const char *name,
                          enum TALER_MerchantConfirmationAlgorithm *mca)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_otp_type,
    .field = name,
    .ptr = mca
  };

  *mca = TALER_MCA_NONE;
  return ret;
}


/* end of json/json_helper.c */
