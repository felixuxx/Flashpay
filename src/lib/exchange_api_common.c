/*
  This file is part of TALER
  Copyright (C) 2015-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_common.c
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


const struct TALER_EXCHANGE_SigningPublicKey *
TALER_EXCHANGE_get_signing_key_info (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  for (unsigned int i = 0; i<keys->num_sign_keys; i++)
  {
    const struct TALER_EXCHANGE_SigningPublicKey *spk
      = &keys->sign_keys[i];

    if (0 == GNUNET_memcmp (exchange_pub,
                            &spk->key))
      return spk;
  }
  return NULL;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_create_conflict_ (
  const struct TALER_PurseContractSignatureP *cpurse_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof)
{
  struct TALER_Amount amount;
  uint32_t min_age;
  struct GNUNET_TIME_Timestamp purse_expiration;
  struct TALER_PurseContractSignatureP purse_sig;
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_PurseMergePublicKeyP merge_pub;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("amount",
                                &amount),
    GNUNET_JSON_spec_uint32 ("min_age",
                             &min_age),
    GNUNET_JSON_spec_timestamp ("purse_expiration",
                                &purse_expiration),
    GNUNET_JSON_spec_fixed_auto ("purse_sig",
                                 &purse_sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                 &merge_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_purse_create_verify (purse_expiration,
                                        &h_contract_terms,
                                        &merge_pub,
                                        min_age,
                                        &amount,
                                        purse_pub,
                                        &purse_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (&purse_sig,
                     cpurse_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_merge_conflict_ (
  const struct TALER_PurseMergeSignatureP *cmerge_sig,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof)
{
  struct TALER_PurseMergeSignatureP merge_sig;
  struct GNUNET_TIME_Timestamp merge_timestamp;
  const char *partner_url = NULL;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_web_url ("partner_url",
                               &partner_url),
      NULL),
    GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                &merge_timestamp),
    GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                 &merge_sig),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &reserve_pub),
    GNUNET_JSON_spec_end ()
  };
  char *payto_uri;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (NULL == partner_url)
    partner_url = exchange_url;
  payto_uri = TALER_reserve_make_payto (partner_url,
                                        &reserve_pub);
  if (GNUNET_OK !=
      TALER_wallet_purse_merge_verify (
        payto_uri,
        merge_timestamp,
        purse_pub,
        merge_pub,
        &merge_sig))
  {
    GNUNET_break_op (0);
    GNUNET_free (payto_uri);
    return GNUNET_SYSERR;
  }
  GNUNET_free (payto_uri);
  if (0 ==
      GNUNET_memcmp (&merge_sig,
                     cmerge_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_coin_conflict_ (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  const char *partner_url = NULL;
  struct TALER_Amount amount;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 h_denom_pub),
    GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                 phac),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 coin_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 coin_pub),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_web_url ("partner_url",
                               &partner_url),
      NULL),
    TALER_JSON_spec_amount_any ("amount",
                                &amount),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (NULL == partner_url)
    partner_url = exchange_url;
  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (
        partner_url,
        purse_pub,
        &amount,
        h_denom_pub,
        phac,
        coin_pub,
        coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_econtract_conflict_ (
  const struct TALER_PurseContractSignatureP *ccontract_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof)
{
  struct TALER_ContractDiffiePublicP contract_pub;
  struct TALER_PurseContractSignatureP contract_sig;
  struct GNUNET_HashCode h_econtract;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_econtract",
                                 &h_econtract),
    GNUNET_JSON_spec_fixed_auto ("econtract_sig",
                                 &contract_sig),
    GNUNET_JSON_spec_fixed_auto ("contract_pub",
                                 &contract_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_econtract_upload_verify2 (
        &h_econtract,
        &contract_pub,
        purse_pub,
        &contract_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (&contract_sig,
                     ccontract_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


// FIXME: should be used...
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_denomination_conflict_ (
  const json_t *proof,
  const struct TALER_DenominationHashP *ch_denom_pub)
{
  struct TALER_DenominationHashP h_denom_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (ch_denom_pub,
                     &h_denom_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_OK;
  }
  /* indeed, proof with different denomination key provided */
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_get_min_denomination_ (
  const struct TALER_EXCHANGE_Keys *keys,
  struct TALER_Amount *min)
{
  bool have_min = false;
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *dk = &keys->denom_keys[i];

    if (! have_min)
    {
      *min = dk->value;
      have_min = true;
      continue;
    }
    if (1 != TALER_amount_cmp (min,
                               &dk->value))
      continue;
    *min = dk->value;
  }
  if (! have_min)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_deposit_signature_ (
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  const struct TALER_ExtensionPolicyHashP *ech,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_EXCHANGE_CoinDepositDetail *cdd,
  const struct TALER_EXCHANGE_DenomPublicKey *dki)
{
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (&cdd->amount,
                                   &dki->fees.deposit,
                                   h_wire,
                                   &dcd->h_contract_terms,
                                   &dcd->wallet_data_hash,
                                   &cdd->h_age_commitment,
                                   ech,
                                   &cdd->h_denom_pub,
                                   dcd->wallet_timestamp,
                                   &dcd->merchant_pub,
                                   dcd->refund_deadline,
                                   &cdd->coin_pub,
                                   &cdd->coin_sig))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid coin signature on /deposit request!\n");
    TALER_LOG_DEBUG ("... amount_with_fee was %s\n",
                     TALER_amount2s (&cdd->amount));
    TALER_LOG_DEBUG ("... deposit_fee was %s\n",
                     TALER_amount2s (&dki->fees.deposit));
    return GNUNET_SYSERR;
  }

  /* check coin signature */
  {
    struct TALER_CoinPublicInfo coin_info = {
      .coin_pub = cdd->coin_pub,
      .denom_pub_hash = cdd->h_denom_pub,
      .denom_sig = cdd->denom_sig,
      .h_age_commitment = cdd->h_age_commitment,
    };

    if (GNUNET_YES !=
        TALER_test_coin_valid (&coin_info,
                               &dki->key))
    {
      GNUNET_break_op (0);
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      return GNUNET_SYSERR;
    }
  }

  /* Check coin does make a contribution */
  if (0 < TALER_amount_cmp (&dki->fees.deposit,
                            &cdd->amount))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Deposit amount smaller than fee\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse account restriction in @a jrest into @a rest.
 *
 * @param jresta array of account restrictions in JSON
 * @param[out] resta_len set to length of @a resta
 * @param[out] resta account restriction array to set
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_restrictions (const json_t *jresta,
                    unsigned int *resta_len,
                    struct TALER_EXCHANGE_AccountRestriction **resta)
{
  if (! json_is_array (jresta))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  *resta_len = json_array_size (jresta);
  if (0 == *resta_len)
  {
    /* no restrictions, perfectly OK */
    *resta = NULL;
    return GNUNET_OK;
  }
  *resta = GNUNET_new_array (*resta_len,
                             struct TALER_EXCHANGE_AccountRestriction);
  for (unsigned int i = 0; i<*resta_len; i++)
  {
    const json_t *jr = json_array_get (jresta,
                                       i);
    struct TALER_EXCHANGE_AccountRestriction *ar = &(*resta)[i];
    const char *type = json_string_value (json_object_get (jr,
                                                           "type"));

    if (NULL == type)
    {
      GNUNET_break (0);
      goto fail;
    }
    if (0 == strcmp (type,
                     "deny"))
    {
      ar->type = TALER_EXCHANGE_AR_DENY;
      continue;
    }
    if (0 == strcmp (type,
                     "regex"))
    {
      const char *regex;
      const char *hint;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string (
          "payto_regex",
          &regex),
        GNUNET_JSON_spec_string (
          "human_hint",
          &hint),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_json (
            "human_hint_i18n",
            &ar->details.regex.human_hint_i18n),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jr,
                             spec,
                             NULL, NULL))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        goto fail;
      }
      ar->type = TALER_EXCHANGE_AR_REGEX;
      ar->details.regex.posix_egrep = GNUNET_strdup (regex);
      ar->details.regex.human_hint = GNUNET_strdup (hint);
      continue;
    }
    /* unsupported type */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
fail:
  GNUNET_free (*resta);
  *resta_len = 0;
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_accounts (
  const struct TALER_MasterPublicKeyP *master_pub,
  const json_t *accounts,
  unsigned int was_length,
  struct TALER_EXCHANGE_WireAccount was[static was_length])
{
  memset (was,
          0,
          sizeof (struct TALER_EXCHANGE_WireAccount) * was_length);
  GNUNET_assert (was_length ==
                 json_array_size (accounts));
  for (unsigned int i = 0;
       i<was_length;
       i++)
  {
    struct TALER_EXCHANGE_WireAccount *wa = &was[i];
    const char *payto_uri;
    const char *conversion_url;
    const json_t *credit_restrictions;
    const json_t *debit_restrictions;
    struct GNUNET_JSON_Specification spec_account[] = {
      TALER_JSON_spec_payto_uri ("payto_uri",
                                 &payto_uri),
      GNUNET_JSON_spec_mark_optional (
        TALER_JSON_spec_web_url ("conversion_url",
                                 &conversion_url),
        NULL),
      GNUNET_JSON_spec_array_const ("credit_restrictions",
                                    &credit_restrictions),
      GNUNET_JSON_spec_array_const ("debit_restrictions",
                                    &debit_restrictions),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &wa->master_sig),
      GNUNET_JSON_spec_end ()
    };
    json_t *account;

    account = json_array_get (accounts,
                              i);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (account,
                           spec_account,
                           NULL, NULL))
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if ( (NULL != master_pub) &&
         (GNUNET_OK !=
          TALER_exchange_wire_signature_check (
            payto_uri,
            conversion_url,
            debit_restrictions,
            credit_restrictions,
            master_pub,
            &wa->master_sig)) )
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if ( (GNUNET_OK !=
          parse_restrictions (credit_restrictions,
                              &wa->credit_restrictions_length,
                              &wa->credit_restrictions)) ||
         (GNUNET_OK !=
          parse_restrictions (debit_restrictions,
                              &wa->debit_restrictions_length,
                              &wa->debit_restrictions)) )
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    wa->payto_uri = GNUNET_strdup (payto_uri);
    if (NULL != conversion_url)
      wa->conversion_url = GNUNET_strdup (conversion_url);
  }       /* end 'for all accounts */
  return GNUNET_OK;
}


/**
 * Free array of account restrictions.
 *
 * @param ar_len length of @a ar
 * @param[in] ar array to free contents of (but not @a ar itself)
 */
static void
free_restrictions (unsigned int ar_len,
                   struct TALER_EXCHANGE_AccountRestriction ar[static ar_len])
{
  for (unsigned int i = 0; i<ar_len; i++)
  {
    struct TALER_EXCHANGE_AccountRestriction *a = &ar[i];
    switch (a->type)
    {
    case TALER_EXCHANGE_AR_INVALID:
      GNUNET_break (0);
      break;
    case TALER_EXCHANGE_AR_DENY:
      break;
    case TALER_EXCHANGE_AR_REGEX:
      GNUNET_free (ar->details.regex.posix_egrep);
      GNUNET_free (ar->details.regex.human_hint);
      json_decref (ar->details.regex.human_hint_i18n);
      break;
    }
  }
}


void
TALER_EXCHANGE_free_accounts (
  unsigned int was_len,
  struct TALER_EXCHANGE_WireAccount was[static was_len])
{
  for (unsigned int i = 0; i<was_len; i++)
  {
    struct TALER_EXCHANGE_WireAccount *wa = &was[i];

    GNUNET_free (wa->payto_uri);
    GNUNET_free (wa->conversion_url);
    free_restrictions (wa->credit_restrictions_length,
                       wa->credit_restrictions);
    GNUNET_array_grow (wa->credit_restrictions,
                       wa->credit_restrictions_length,
                       0);
    free_restrictions (wa->debit_restrictions_length,
                       wa->debit_restrictions);
    GNUNET_array_grow (wa->debit_restrictions,
                       wa->debit_restrictions_length,
                       0);
  }
}


/* end of exchange_api_common.c */
