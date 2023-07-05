/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
static enum TALER_DenominationCipher
string_to_cipher (const char *cipher_s)
{
  if ((0 == strcasecmp (cipher_s,
                        "RSA")) ||
      (0 == strcasecmp (cipher_s,
                        "RSA+age_restricted")))
    return TALER_DENOMINATION_RSA;
  if ((0 == strcasecmp (cipher_s,
                        "CS")) ||
      (0 == strcasecmp (cipher_s,
                        "CS+age_restricted")))
    return TALER_DENOMINATION_CS;
  return TALER_DENOMINATION_INVALID;
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


json_t *
TALER_JSON_from_amount_nbo (const struct TALER_AmountNBO *amount)
{
  struct TALER_Amount a;

  TALER_amount_ntoh (&a,
                     amount);
  return TALER_JSON_from_amount (&a);
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
 * Parse given JSON object to Amount in NBO.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_amount_nbo (void *cls,
                  json_t *root,
                  struct GNUNET_JSON_Specification *spec)
{
  const char *currency = cls;
  struct TALER_AmountNBO *r_amount = spec->ptr;
  const char *sv;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  sv = json_string_value (root);
  if (GNUNET_OK !=
      TALER_string_to_amount_nbo (sv,
                                  r_amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "`%s' is not a valid amount\n",
                sv);
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (NULL != currency) &&
       (0 !=
        strcasecmp (currency,
                    r_amount->currency)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_nbo (const char *name,
                            const char *currency,
                            struct TALER_AmountNBO *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount_nbo,
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
TALER_JSON_spec_amount_any_nbo (const char *name,
                                struct TALER_AmountNBO *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount_nbo,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };

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
    GNUNET_JSON_spec_fixed_auto ("hash",
                                 &group->hash),
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
  if (TALER_DENOMINATION_INVALID == group->cipher)
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
    .cleaner = NULL,
    .field = name,
    .ptr = group,
    .ptr_size = sizeof(*group),
    .size_ptr = NULL,
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
    .cls = NULL,
    .field = name,
    .ptr = econtract,
    .ptr_size = 0,
    .size_ptr = NULL
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
 * Cleanup data left fom parsing age commitment
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
    .cls = NULL,
    .field = name,
    .ptr = age_commitment,
    .ptr_size = 0,
    .size_ptr = NULL
  };

  return ret;
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

  denom_pub->cipher = string_to_cipher (cipher);
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_public_key (
          "rsa_public_key",
          &denom_pub->details.rsa_public_key),
        GNUNET_JSON_spec_end ()
      };

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
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed ("cs_public_key",
                                &denom_pub->details.cs_public_key,
                                sizeof (denom_pub->details.cs_public_key)),
        GNUNET_JSON_spec_end ()
      };

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
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
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

  pk->cipher = TALER_DENOMINATION_INVALID;
  return ret;
}


/**
 * Parse given JSON object partially into a denomination public key.
 *
 * Depending on the cipher in cls, it parses the corresponding public key type.
 *
 * @param cls closure, enum TALER_DenominationCipher
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
  enum TALER_DenominationCipher cipher =
    (enum TALER_DenominationCipher) (long) cls;
  const char *emsg;
  unsigned int eline;

  switch (cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_public_key (
          "rsa_pub",
          &denom_pub->details.rsa_public_key),
        GNUNET_JSON_spec_end ()
      };

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
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed ("cs_pub",
                                &denom_pub->details.cs_public_key,
                                sizeof (denom_pub->details.cs_public_key)),
        GNUNET_JSON_spec_end ()
      };

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
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_pub_cipher (const char *field,
                                  enum TALER_DenominationCipher cipher,
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


/**
 * Parse given JSON object to denomination signature.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_denom_sig (void *cls,
                 json_t *root,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationSignature *denom_sig = spec->ptr;
  const char *cipher;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
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
  denom_sig->cipher = string_to_cipher (cipher);
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_signature (
          "rsa_signature",
          &denom_sig->details.rsa_signature),
        GNUNET_JSON_spec_end ()
      };

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
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed_auto ("cs_signature_r",
                                     &denom_sig->details.cs_signature.r_point),
        GNUNET_JSON_spec_fixed_auto ("cs_signature_s",
                                     &denom_sig->details.cs_signature.s_scalar),
        GNUNET_JSON_spec_end ()
      };

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
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Cleanup data left from parsing denomination public key.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_denom_sig (void *cls,
                 struct GNUNET_JSON_Specification *spec)
{
  struct TALER_DenominationSignature *denom_sig = spec->ptr;

  (void) cls;
  TALER_denom_sig_free (denom_sig);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denom_sig (const char *field,
                           struct TALER_DenominationSignature *sig)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_denom_sig,
    .cleaner = &clean_denom_sig,
    .field = field,
    .ptr = sig
  };

  sig->cipher = TALER_DENOMINATION_INVALID;
  return ret;
}


/**
 * Parse given JSON object to blinded denomination signature.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_blinded_denom_sig (void *cls,
                         json_t *root,
                         struct GNUNET_JSON_Specification *spec)
{
  struct TALER_BlindedDenominationSignature *denom_sig = spec->ptr;
  const char *cipher;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
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
  denom_sig->cipher = string_to_cipher (cipher);
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_rsa_signature (
          "blinded_rsa_signature",
          &denom_sig->details.blinded_rsa_signature),
        GNUNET_JSON_spec_end ()
      };

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
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_uint32 ("b",
                                 &denom_sig->details.blinded_cs_answer.b),
        GNUNET_JSON_spec_fixed_auto ("s",
                                     &denom_sig->details.blinded_cs_answer.
                                     s_scalar),
        GNUNET_JSON_spec_end ()
      };

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
    break;
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Cleanup data left from parsing denomination public key.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_blinded_denom_sig (void *cls,
                         struct GNUNET_JSON_Specification *spec)
{
  struct TALER_BlindedDenominationSignature *denom_sig = spec->ptr;

  (void) cls;
  TALER_blinded_denom_sig_free (denom_sig);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_denom_sig (
  const char *field,
  struct TALER_BlindedDenominationSignature *sig)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_blinded_denom_sig,
    .cleaner = &clean_blinded_denom_sig,
    .field = field,
    .ptr = sig
  };

  sig->cipher = TALER_DENOMINATION_INVALID;
  return ret;
}


/**
 * Parse given JSON object to blinded planchet.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static enum GNUNET_GenericReturnValue
parse_blinded_planchet (void *cls,
                        json_t *root,
                        struct GNUNET_JSON_Specification *spec)
{
  struct TALER_BlindedPlanchet *blinded_planchet = spec->ptr;
  const char *cipher;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
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
  blinded_planchet->cipher = string_to_cipher (cipher);
  switch (blinded_planchet->cipher)
  {
  case TALER_DENOMINATION_RSA:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_varsize (
          "rsa_blinded_planchet",
          &blinded_planchet->details.rsa_blinded_planchet.blinded_msg,
          &blinded_planchet->details.rsa_blinded_planchet.blinded_msg_size),
        GNUNET_JSON_spec_end ()
      };

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
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed_auto (
          "cs_nonce",
          &blinded_planchet->details.cs_blinded_planchet.nonce),
        GNUNET_JSON_spec_fixed_auto (
          "cs_blinded_c0",
          &blinded_planchet->details.cs_blinded_planchet.c[0]),
        GNUNET_JSON_spec_fixed_auto (
          "cs_blinded_c1",
          &blinded_planchet->details.cs_blinded_planchet.c[1]),
        GNUNET_JSON_spec_end ()
      };

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
    break;
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Cleanup data left from parsing blinded planchet.
 *
 * @param cls closure, NULL
 * @param[out] spec where to free the data
 */
static void
clean_blinded_planchet (void *cls,
                        struct GNUNET_JSON_Specification *spec)
{
  struct TALER_BlindedPlanchet *blinded_planchet = spec->ptr;

  (void) cls;
  TALER_blinded_planchet_free (blinded_planchet);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_blinded_planchet (const char *field,
                                  struct TALER_BlindedPlanchet *blinded_planchet)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_blinded_planchet,
    .cleaner = &clean_blinded_planchet,
    .field = field,
    .ptr = blinded_planchet
  };

  blinded_planchet->cipher = TALER_DENOMINATION_INVALID;
  return ret;
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
  const char *cipher;
  struct GNUNET_JSON_Specification dspec[] = {
    GNUNET_JSON_spec_string ("cipher",
                             &cipher),
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
  ewv->cipher = string_to_cipher (cipher);
  switch (ewv->cipher)
  {
  case TALER_DENOMINATION_RSA:
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    {
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed (
          "r_pub_0",
          &ewv->details.cs_values.r_pub[0],
          sizeof (struct GNUNET_CRYPTO_CsRPublic)),
        GNUNET_JSON_spec_fixed (
          "r_pub_1",
          &ewv->details.cs_values.r_pub[1],
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
        return GNUNET_SYSERR;
      }
      return GNUNET_OK;
    }
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_exchange_withdraw_values (
  const char *field,
  struct TALER_ExchangeWithdrawValues *ewv)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_exchange_withdraw_values,
    .field = field,
    .ptr = ewv
  };

  ewv->cipher = TALER_DENOMINATION_INVALID;
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
  GNUNET_free (ctx->lp);
  GNUNET_free (ctx);
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

  ctx->lp = (NULL != language_pattern) ? GNUNET_strdup (language_pattern) :
            NULL;
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


/* end of json/json_helper.c */
