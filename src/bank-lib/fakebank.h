/*
  This file is part of TALER
  (C) 2016, 2017, 2018 Inria and GNUnet e.V.

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file bank-lib/fakebank.h
 * @brief definitions for the "/history[-range]" layer.
 * @author Marcello Stanisci <stanisci.m@gmail.com>
 */

#ifndef FAKEBANK_H
#define FAKEBANK_H
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_bank_service.h"

/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction
{
  /**
   * We store transactions in a DLL.
   */
  struct Transaction *next;

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *prev;

  /**
   * Amount to be transferred.
   */
  struct TALER_Amount amount;

  /**
   * Account to debit.
   */
  uint64_t debit_account;

  /**
   * Account to credit.
   */
  uint64_t credit_account;

  /**
   * Subject of the transfer.
   */
  char *subject;

  /**
   * Base URL of the exchange.
   */
  char *exchange_base_url;

  /**
   * When did the transaction happen?
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Number of this transaction.
   */
  uint64_t row_id;

  /**
   * Flag set if the transfer was rejected.
   */
  int rejected;

  /**
   * Has this transaction been subjected to #TALER_FAKEBANK_check()
   * and should thus no longer be counted in
   * #TALER_FAKEBANK_check_empty()?
   */
  int checked;
};


/******************************************
 * Definitions for "/history" start here. *
 ******************************************/

/**
 * Needed to implement ascending/descending ordering
 * of /history results.
 */
struct HistoryElement
{

  /**
   * History JSON element.
   */
  json_t *element;

  /**
   * Previous element.
   */
  struct HistoryElement *prev;

  /**
   * Next element.
   */
  struct HistoryElement *next;
};


/**
 * Values to implement the "/history-range" range.
 */
struct HistoryRangeDates
{
  /**
   * Oldest row in the results.
   */
  struct GNUNET_TIME_Absolute start;

  /**
   * Youngest row in the results.
   */
  struct GNUNET_TIME_Absolute end;
};

/**
 * Values to implement the "/history" range.
 */
struct HistoryRangeIds
{

  /**
   * (Exclusive) row ID for the result set.
   */
  unsigned long long start;

  /**
   * How many transactions we want in the result set.  If
   * negative/positive, @a start will be strictly younger/older
   * of any element in the result set.
   */
  long long count;
};


/**
 * This is the "base" structure for both the /history and the
 * /history-range API calls.
 */
struct HistoryArgs
{

  /**
   * Direction asked by the client: CREDIT / DEBIT / BOTH / CANCEL.
   */
  enum TALER_BANK_Direction direction;

  /**
   * Bank account number of the requesting client.
   */
  unsigned long long account_number;

  /**
   * Ordering of the results.
   */
  unsigned int ascending;

  /**
   * Overloaded type that indicates the "range" to be returned
   * in the results; this can be either a date range, or a
   * starting row id + the count.
   */
  void *range;
};



/**
 * Type for a function that decides whether or not
 * the history-building loop should iterate once again.
 * Typically called from inside the 'while' condition.
 *
 * @param ha history argument.
 * @param pos current position.
 * @return GNUNET_YES if the iteration shuold go on.
 */
typedef int (*CheckAdvance)
  (const struct HistoryArgs *ha,
   const struct Transaction *pos);

/**
 * Type for a function that steps over the next element
 * in the list of all transactions, after the current @a pos
 * _got_ included in the result.
 */
typedef struct Transaction * (*Step)
  (const struct HistoryArgs *ha,
   const struct Transaction *pos);

/*
 * Type for a function that steps over the next element
 * in the list of all transactions, after the current @a pos
 * did _not_ get included in the result.
 */
typedef struct Transaction * (*Skip)
  (const struct HistoryArgs *ha,
   const struct Transaction *pos);

/**
 * Actual history response builder.
 *
 * @param pos first (included) element in the result set.
 * @param ha history arguments.
 * @param caller_name which function is building the history.
 * @return MHD_YES / MHD_NO, after having enqueued the response
 *         object into MHD.
 */
int
TFH_build_history_response (struct MHD_Connection *connection,
                            struct Transaction *pos,
                            struct HistoryArgs *ha,
                            Skip skip,
                            Step step,
                            CheckAdvance advance);


/**
 * Parse URL history arguments, of _both_ APIs:
 * /history and /history-range.
 *
 * @param connection MHD connection.
 * @param function_name name of the caller.
 * @param ha[out] will contain the parsed values.
 * @return GNUNET_OK only if the parsing succeedes.
 */
int
TFH_parse_history_common_args (struct MHD_Connection *connection,
                               struct HistoryArgs *ha);


/**
 * Decides whether the history builder will advance or not
 * to the next element.
 *
 * @param ha history args
 * @return GNUNET_YES/NO to advance/not-advance.
 */
int
TFH_handle_history_advance (const struct HistoryArgs *ha,
                            const struct Transaction *pos);

/**
 * Iterates on the "next" element to be processed.  To
 * be used when the current element does not get inserted in
 * the result.
 *
 * @param ha history arguments.
 * @param pos current element being processed.
 * @return the next element to be processed.
 */
struct Transaction *
TFH_handle_history_skip (const struct HistoryArgs *ha,
                         const struct Transaction *pos);

/**
 * Iterates on the "next" element to be processed.  To
 * be used when the current element _gets_ inserted in the result.
 *
 * @param ha history arguments.
 * @param pos current element being processed.
 * @return the next element to be processed.
 */
struct Transaction *
TFH_handle_history_step (const struct HistoryArgs *ha,
                         const struct Transaction *pos);

/**
 * Decides whether the history builder will advance or not
 * to the next element.
 *
 * @param ha history args
 * @return GNUNET_YES/NO to advance/not-advance.
 */
int
TFH_handle_history_range_advance (const struct HistoryArgs *ha,
                                  const struct Transaction *pos);

/**
 * Iterates towards the "next" element to be processed.  To
 * be used when the current element does not get inserted in
 * the result.
 *
 * @param ha history arguments.
 * @param pos current element being processed.
 * @return the next element to be processed.
 */
struct Transaction *
TFH_handle_history_range_skip (const struct HistoryArgs *ha,
                               const struct Transaction *pos);

/**
 * Iterates on the "next" element to be processed.  To
 * be used when the current element _gets_ inserted in the result.
 * Same implementation of the "skip" counterpart, as /history-range
 * does not have the notion of count/delta.
 */
Step TFH_handle_history_range_step;
#endif
