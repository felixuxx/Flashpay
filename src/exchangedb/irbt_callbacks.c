/*
   This file is part of GNUnet
   Copyright (C) 2020 Taler Systems SA

   GNUnet is free software: you can redistribute it and/or modify it
   under the terms of the GNU Affero General Public License as published
   by the Free Software Foundation, either version 3 of the License,
   or (at your option) any later version.

   GNUnet is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

     SPDX-License-Identifier: AGPL3.0-or-later
 */
/**
 * @file exchangedb/irbt_callbacks.c
 * @brief callbacks used by postgres_insert_records_by_table, to be
 *        inlined into the plugin
 * @author Christian Grothoff
 */


/**
 * Function called with denominations records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_denominations (struct PostgresClosure *pg,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with denomination_revocations records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_denomination_revocations (struct PostgresClosure *pg,
                                        struct TALER_EXCHANGEDB_Session *session,
                                        const struct
                                        TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with reserves records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves (struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with reserves_in records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_in (struct PostgresClosure *pg,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with reserves_close records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_close (struct PostgresClosure *pg,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with reserves_out records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_out (struct PostgresClosure *pg,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with auditors records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_auditors (struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with auditor_denom_sigs records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_auditor_denom_sigs (struct PostgresClosure *pg,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with exchange_sign_keys records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_exchange_sign_keys (struct PostgresClosure *pg,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with signkey_revocations records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_signkey_revocations (struct PostgresClosure *pg,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with known_coins records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_known_coins (struct PostgresClosure *pg,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with refresh_commitments records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_commitments (struct PostgresClosure *pg,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with refresh_revealed_coins records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_revealed_coins (struct PostgresClosure *pg,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      const struct
                                      TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with refresh_transfer_keys records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_transfer_keys (struct PostgresClosure *pg,
                                     struct TALER_EXCHANGEDB_Session *session,
                                     const struct
                                     TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with deposits records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_deposits (struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with refunds records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refunds (struct PostgresClosure *pg,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with wire_out records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wire_out (struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with aggregation_tracking records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_aggregation_tracking (struct PostgresClosure *pg,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with wire_fee records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wire_fee (struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with recoup records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_recoup (struct PostgresClosure *pg,
                      struct TALER_EXCHANGEDB_Session *session,
                      const struct TALER_EXCHANGEDB_TableData *td)
{
}


/**
 * Function called with recoup_refresh records to insert into table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_recoup_refresh (struct PostgresClosure *pg,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
}


/* end of irbt_callbacks.c */
