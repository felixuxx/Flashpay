/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file pg_helper.h
 * @brief shared internal definitions for postgres DB plugin
 * @author Christian Grothoff
 */
#ifndef PG_HELPER_H
#define PG_HELPER_H


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

  /**
   * Our configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Directory with SQL statements to run to create tables.
   */
  char *sql_dir;

  /**
   * After how long should idle reserves be closed?
   */
  struct GNUNET_TIME_Relative idle_reserve_expiration_time;

  /**
   * After how long should reserves that have seen withdraw operations
   * be garbage collected?
   */
  struct GNUNET_TIME_Relative legal_reserve_expiration_time;

  /**
   * What delay should we introduce before ready transactions
   * are actually aggregated?
   */
  struct GNUNET_TIME_Relative aggregator_shift;

  /**
   * Which currency should we assume all amounts to be in?
   */
  char *currency;

  /**
   * Our base URL.
   */
  char *exchange_url;

  /**
   * Postgres connection handle.
   */
  struct GNUNET_PQ_Context *conn;

  /**
   * Name of the current transaction, for debugging.
   */
  const char *transaction_name;

  /**
   * Counts how often we have established a fresh @e conn
   * to the database. Used to re-prepare statements.
   */
  unsigned long long prep_gen;

  /**
   * Number of purses we allow to be opened concurrently
   * for one year per annual fee payment.
   */
  uint32_t def_purse_limit;

};


/**
 * Prepares SQL statement @a sql under @a name for
 * connection @a pg once.
 * Returns with #GNUNET_DB_STATUS_HARD_ERROR on failure.
 *
 * @param pg a `struct PostgresClosure`
 * @param name name to prepare the statement under
 * @param sql actual SQL text
 */
#define PREPARE(pg,name,sql)                      \
  do {                                            \
    static struct {                               \
      unsigned long long cnt;                     \
      struct PostgresClosure *pg;                 \
    } preps[2]; /* 2 ctrs for taler-auditor-sync*/ \
    unsigned int off = 0;                         \
                                                  \
    while ( (NULL != preps[off].pg) &&            \
            (pg != preps[off].pg) &&              \
            (off < sizeof(preps) / sizeof(*preps)) ) \
    off++;                                      \
    GNUNET_assert (off <                          \
                   sizeof(preps) / sizeof(*preps)); \
    if (preps[off].cnt < pg->prep_gen)            \
    {                                             \
      struct GNUNET_PQ_PreparedStatement ps[] = { \
        GNUNET_PQ_make_prepare (name, sql),       \
        GNUNET_PQ_PREPARED_STATEMENT_END          \
      };                                          \
                                                  \
      if (GNUNET_OK !=                            \
          GNUNET_PQ_prepare_statements (pg->conn, \
                                        ps))      \
      {                                           \
        GNUNET_break (0);                         \
        return GNUNET_DB_STATUS_HARD_ERROR;       \
      }                                           \
      preps[off].pg = pg;                         \
      preps[off].cnt = pg->prep_gen;              \
    }                                             \
  } while (0)


/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT(field,amountp) TALER_PQ_result_spec_amount ( \
    field,pg->currency,amountp)


/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.  NBO variant.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT_NBO(field,                          \
                                        amountp) TALER_PQ_result_spec_amount_nbo ( \
    field,pg->currency,amountp)


#endif
