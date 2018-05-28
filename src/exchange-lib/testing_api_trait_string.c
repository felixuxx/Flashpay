/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange-lib/testing_api_trait_string.c
 * @brief offers strings traits.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

#define TALER_TESTING_TRAIT_CONTRACT_TERMS "contract-terms"
#define TALER_TESTING_TRAIT_TRANSFER_SUBJECT "transfer-subject"
#define TALER_TESTING_TRAIT_AMOUNT "amount"
#define TALER_TESTING_TRAIT_URL "url"
#define TALER_TESTING_TRAIT_ORDER_ID "order-id"
#define TALER_TESTING_TRAIT_REJECTED "rejected"

/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract the contract terms from.
 * @param index contract terms index number.
 * @param contract_terms[out] where to write the contract
 *        terms.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_contract_terms
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **contract_terms)
{
  return cmd->traits (cmd->cls,
                      (void **) contract_terms,
                      TALER_TESTING_TRAIT_CONTRACT_TERMS,
                      index);
}

/**
 * Offer contract terms.
 *
 * @param index contract terms index number.
 * @param contract_terms contract terms to offer.
 * 
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_contract_terms
  (unsigned int index,
   const char *contract_terms)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_CONTRACT_TERMS,
    .ptr = (const void *) contract_terms
  };
  return ret;
}


/**
 * Obtain a transfer subject from @a cmd.
 *
 * @param cmd command to extract the subject from.
 * @param index index number associated with the transfer
 *        subject to offer.
 * @param transfer_subject[out] where to write the offered
 *        transfer subject.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_transfer_subject
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **transfer_subject)
{
  return cmd->traits (cmd->cls,
                      (void **) transfer_subject,
                      TALER_TESTING_TRAIT_TRANSFER_SUBJECT,
                      index);
}

/**
 * Offer transfer subject.
 *
 * @param index index number associated with the transfer
 *        subject being offered.
 * @param transfer_subject transfer subject to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_transfer_subject
  (unsigned int index,
   const char *transfer_subject)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_TRANSFER_SUBJECT,
    .ptr = (const void *) transfer_subject
  };
  return ret;
}


/**
 * Obtain an amount from @a cmd.
 *
 * @param cmd command to extract the amount from.
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_amount
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **amount)
{
  return cmd->traits (cmd->cls,
                      (void **) amount,
                      TALER_TESTING_TRAIT_AMOUNT,
                      index);
}

/**
 * Offer amount in a trait.
 *
 * @param index which amount is to be offered,
 *        in case multiple are offered.
 * @param amount the amount to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount
  (unsigned int index,
   const char *amount)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_AMOUNT,
    .ptr = (const void *) amount
  };
  return ret;
}


/**
 * Obtain a url from @a cmd.
 *
 * @param cmd command to extract the url from.
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param url[out] where to write the url.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_url
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **url)
{
  return cmd->traits (cmd->cls,
                      (void **) url,
                      TALER_TESTING_TRAIT_URL,
                      index);
}

/**
 * Offer url in a trait.
 *
 * @param index which url is to be picked,
 *        in case multiple are offered.
 * @param url the url to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_url
  (unsigned int index,
   const char *url)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_URL,
    .ptr = (const void *) url
  };
  return ret;
}


/**
 * Obtain a order id from @a cmd.
 *
 * @param cmd command to extract the order id from.
 * @param index which order id is to be picked, in case
 *        multiple are offered.
 * @param order_id[out] where to write the order id.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_order_id
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **order_id)
{
  return cmd->traits (cmd->cls,
                      (void **) order_id,
                      TALER_TESTING_TRAIT_ORDER_ID,
                      index);
}

/**
 * Offer order id in a trait.
 *
 * @param index which order id is to be offered,
 *        in case multiple are offered.
 * @param order_id the order id to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_order_id
  (unsigned int index,
   const char *order_id)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_ORDER_ID,
    .ptr = (const void *) order_id
  };
  return ret;
}

/**
 * Obtain the reference to a "reject" CMD.  Usually offered
 * by _rejected_ bank transfers.
 *
 * @param cmd command to extract the reference from.
 * @param index which reference is to be picked, in case
 *        multiple are offered.
 * @param rejected_reference[out] where to write the reference.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_rejected
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **rejected_reference)
{
  return cmd->traits (cmd->cls,
                      (void **) rejected_reference,
                      TALER_TESTING_TRAIT_REJECTED,
                      index);
}

/**
 * Offer a "reject" CMD reference.
 *
 * @param index which reference is to be offered,
 *        in case multiple are offered.
 * @param rejected_reference the reference to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_rejected
  (unsigned int index,
   const char *rejected)
{
  struct TALER_TESTING_Trait ret = {
    .index = index,
    .trait_name = TALER_TESTING_TRAIT_REJECTED,
    .ptr = (const void *) rejected
  };
  return ret;
}

/* end of testing_api_trait_string.c */
