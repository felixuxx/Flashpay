/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchangedb_history.c
 * @brief helper function to build AML inputs from account histories
 * @author Christian Grothoff
 */
#include "taler_exchangedb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_common.h>

/**
 * Function called to expand AML history for the account.
 *
 * @param cls a `json_t *` array to build
 * @param decision_time when was the decision taken
 * @param justification what was the given justification
 * @param decider_pub which key signed the decision
 * @param jproperties what are the new account properties
 * @param jnew_rules what are the new account rules
 * @param to_investigate should AML staff investigate
 *          after the decision
 * @param is_active is this the active decision
 */
static void
add_aml_history_entry (
  void *cls,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const json_t *jproperties,
  const json_t *jnew_rules,
  bool to_investigate,
  bool is_active)
{
  json_t *aml_history = cls;
  json_t *e;

  e = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_timestamp ("decision_time",
                                decision_time),
    GNUNET_JSON_pack_string ("justification",
                             justification),
    GNUNET_JSON_pack_data_auto ("decider_pub",
                                decider_pub),
    GNUNET_JSON_pack_object_incref ("properties",
                                    (json_t *) jproperties),
    GNUNET_JSON_pack_object_incref ("new_rules",
                                    (json_t *) jnew_rules),
    GNUNET_JSON_pack_bool ("to_investigate",
                           to_investigate),
    GNUNET_JSON_pack_bool ("is_active",
                           is_active)
    );
  GNUNET_assert (0 ==
                 json_array_append_new (aml_history,
                                        e));
}


json_t *
TALER_EXCHANGEDB_aml_history_builder (void *cls)
{
  struct TALER_EXCHANGEDB_HistoryBuilderContext *hbc = cls;
  const struct TALER_NormalizedPaytoHashP *acc = hbc->account;
  enum GNUNET_DB_QueryStatus qs;
  json_t *aml_history;

  aml_history = json_array ();
  GNUNET_assert (NULL != aml_history);
  qs = hbc->db_plugin->lookup_aml_history (
    hbc->db_plugin->cls,
    acc,
    &add_aml_history_entry,
    aml_history);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    json_decref (aml_history);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* empty history is fine! */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  return aml_history;
}


/**
 * Closure for #add_kyc_history_entry.
 */
struct KycContext
{
  /**
   * JSON array we are building.
   */
  json_t *kyc_history;

  /**
   * Key to use to decrypt KYC attributes.
   */
  const struct TALER_AttributeEncryptionKeyP *attribute_key;
};


/**
 * Function called to expand KYC history for the account.
 *
 * @param cls a `json_t *` array to build
 * @param provider_name name of the KYC provider
 *    or NULL for none
 * @param finished did the KYC process finish
 * @param error_code error code from the KYC process
 * @param error_message error message from the KYC process,
 *    or NULL for none
 * @param provider_user_id user ID at the provider
 *    or NULL for none
 * @param provider_legitimization_id legitimization process ID at the provider
 *    or NULL for none
 * @param collection_time when was the data collected
 * @param expiration_time when does the collected data expire
 * @param encrypted_attributes_len number of bytes in @a encrypted_attributes
 * @param encrypted_attributes encrypted KYC attributes
 */
static void
add_kyc_history_entry (
  void *cls,
  const char *provider_name,
  bool finished,
  enum TALER_ErrorCode error_code,
  const char *error_message,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Absolute expiration_time,
  size_t encrypted_attributes_len,
  const void *encrypted_attributes)
{
  struct KycContext *kc = cls;
  json_t *kyc_history = kc->kyc_history;
  json_t *attributes;
  json_t *e;

  attributes = TALER_CRYPTO_kyc_attributes_decrypt (
    kc->attribute_key,
    encrypted_attributes,
    encrypted_attributes_len);
  e = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string (
      "provider_name",
      provider_name),
    GNUNET_JSON_pack_bool (
      "finished",
      finished),
    TALER_JSON_pack_ec (error_code),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "error_message",
        error_message)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "provider_user_id",
        provider_user_id)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "provider_legitimization_id",
        provider_legitimization_id)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp (
        "collection_time",
        collection_time)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp (
        "expiration_time",
        GNUNET_TIME_absolute_to_timestamp (
          expiration_time))),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_steal (
        "attributes",
        attributes))
    );

  GNUNET_assert (0 ==
                 json_array_append_new (kyc_history,
                                        e));
}


json_t *
TALER_EXCHANGEDB_kyc_history_builder (void *cls)
{
  struct TALER_EXCHANGEDB_HistoryBuilderContext *hbc = cls;
  const struct TALER_NormalizedPaytoHashP *acc = hbc->account;
  enum GNUNET_DB_QueryStatus qs;
  struct KycContext kc = {
    .kyc_history = json_array (),
    .attribute_key = hbc->attribute_key
  };

  GNUNET_assert (NULL != kc.kyc_history);
  qs = hbc->db_plugin->lookup_kyc_history (
    hbc->db_plugin->cls,
    acc,
    &add_kyc_history_entry,
    &kc);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    json_decref (kc.kyc_history);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* empty history is fine! */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  return kc.kyc_history;
}


json_t *
TALER_EXCHANGEDB_current_rule_builder (void *cls)
{
  struct TALER_EXCHANGEDB_HistoryBuilderContext *hbc = cls;
  const struct TALER_NormalizedPaytoHashP *acc = hbc->account;
  enum GNUNET_DB_QueryStatus qs;
  json_t *jlrs;

  qs = hbc->db_plugin->get_kyc_rules2 (
    hbc->db_plugin->cls,
    acc,
    &jlrs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    jlrs = json_incref ((json_t *) TALER_KYCLOGIC_get_default_legi_rules ());
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  return jlrs;
}
