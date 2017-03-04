/*
  This file is part of TALER
  Copyright (C) 2017 GNUnet e.V.

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
 * @file exchangedb/exchangedb_fees.c
 * @brief Logic to read/write/convert aggregation wire fees (not other fees!)
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Structure for wire fees on disk.
 */
struct TALER_WireFeeDiskP
{

  /**
   * Wire fee details.
   */
  struct TALER_MasterWireFeePS wf;


  /**
   * Signature affirming the above fee structure.
   */
  struct TALER_MasterSignatureP master_sig;

};

GNUNET_NETWORK_STRUCT_END


/**
 * Convert @a wd disk format to host format.
 *
 * @param wd aggregate fees, disk format
 * @return fees in host format
 */
static struct TALER_EXCHANGEDB_AggregateFees *
wd2af (const struct TALER_WireFeeDiskP *wd)
{
  struct TALER_EXCHANGEDB_AggregateFees *af;

  af = GNUNET_new (struct TALER_EXCHANGEDB_AggregateFees);
  af->start_date = GNUNET_TIME_absolute_ntoh (wd->wf.start_date);
  af->end_date = GNUNET_TIME_absolute_ntoh (wd->wf.end_date);
  TALER_amount_ntoh (&af->wire_fee,
                     &wd->wf.wire_fee);
  af->master_sig = wd->master_sig;
  return af;
}


/**
 * Read the current fee structure from disk.
 *
 * @param cfg configuration to use
 * @param wireplugin name of the wire plugin to read fees for
 * @return sorted list of aggregation fees, NULL on error
 */
struct TALER_EXCHANGEDB_AggregateFees *
TALER_EXCHANGEDB_fees_read (const struct GNUNET_CONFIGURATION_Handle *cfg,
                            const char *wireplugin)
{
  char *wirefee_base_dir;
  char *fn;
  struct GNUNET_DISK_FileHandle *fh;
  struct TALER_WireFeeDiskP wd;
  struct TALER_EXCHANGEDB_AggregateFees *af;
  struct TALER_EXCHANGEDB_AggregateFees *endp;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchangedb",
                                               "WIREFEE_BASE_DIR",
                                               &wirefee_base_dir))
    return NULL;
  GNUNET_asprintf (&fn,
                   "%s/%s.fee",
                   wirefee_base_dir,
                   wireplugin);
  GNUNET_free (wirefee_base_dir);
  fh = GNUNET_DISK_file_open (fn,
                              GNUNET_DISK_OPEN_READ,
                              GNUNET_DISK_PERM_NONE);
  GNUNET_free (fn);
  if (NULL == fh)
    return NULL;

  af = NULL;
  endp = NULL;
  while (sizeof (wd) ==
         GNUNET_DISK_file_read (fh,
                                &wd,
                                sizeof (wd)))
  {
    struct TALER_EXCHANGEDB_AggregateFees *n;

    n = wd2af (&wd);
    if ( ( (NULL == af) ||
           (endp->end_date.abs_value_us == n->start_date.abs_value_us) ) &&
         (n->start_date.abs_value_us < n->end_date.abs_value_us) )
    {
      /* append to list */
      if (NULL != endp)
        endp->next = n;
      else
        af = n;
      endp = n;
    }
    else
    {
      /* We expect file to be in chronological order! */
      GNUNET_break (0);
      GNUNET_DISK_file_close (fh);
      GNUNET_free (n);
      TALER_EXCHANGEDB_fees_free (af);
      return NULL;
    }
  }
  GNUNET_DISK_file_close (fh);
  return af;
}


/**
 * Convert @a af to @a wf.
 *
 * @param wireplugin name of the wire plugin the fees are for
 * @param[in,out] af aggregate fees, host format (updated to round time)
 * @param[out] wf aggregate fees, disk / signature format
 */
void
TALER_EXCHANGEDB_fees_2_wf (const char *wireplugin,
                            struct TALER_EXCHANGEDB_AggregateFees *af,
                            struct TALER_MasterWireFeePS *wf)
{
  (void) GNUNET_TIME_round_abs (&af->start_date);
  (void) GNUNET_TIME_round_abs (&af->end_date);
  wf->purpose.size = htonl (sizeof (*wf));
  wf->purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES);
  GNUNET_CRYPTO_hash (wireplugin,
                      strlen (wireplugin) + 1,
                      &wf->h_wire_method);
  wf->start_date = GNUNET_TIME_absolute_hton (af->start_date);
  wf->end_date = GNUNET_TIME_absolute_hton (af->end_date);
  TALER_amount_hton (&wf->wire_fee,
                     &af->wire_fee);
}


/**
 * Write given fee structure to disk.
 *
 * @param filename where to write the fees
 * @param wireplugin which plugin the fees are about
 * @param af fee structure to write
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_EXCHANGEDB_fees_write (const char *filename,
                             const char *wireplugin,
                             struct TALER_EXCHANGEDB_AggregateFees *af)
{
  struct GNUNET_DISK_FileHandle *fh;
  struct TALER_WireFeeDiskP wd;
  struct TALER_EXCHANGEDB_AggregateFees *last;

  if (GNUNET_OK !=
      GNUNET_DISK_directory_create_for_file (filename))
    return GNUNET_SYSERR;

  fh = GNUNET_DISK_file_open (filename,
                              GNUNET_DISK_OPEN_WRITE |
                              GNUNET_DISK_OPEN_TRUNCATE |
                              GNUNET_DISK_OPEN_CREATE,
                              GNUNET_DISK_PERM_USER_READ |
                              GNUNET_DISK_PERM_USER_WRITE);
  if (NULL == fh)
    return GNUNET_SYSERR;

  last = NULL;
  while (NULL != af)
  {
    if ( ( (NULL != last) &&
           (last->end_date.abs_value_us != af->start_date.abs_value_us) ) ||
         (af->start_date.abs_value_us >= af->end_date.abs_value_us) )
    {
      /* @a af malformed, refusing to write file that will be rejected */
      GNUNET_break (0);
      GNUNET_assert (GNUNET_OK ==
                     GNUNET_DISK_file_close (fh));
      return GNUNET_SYSERR;
    }
    TALER_EXCHANGEDB_fees_2_wf (wireplugin,
                                af,
                                &wd.wf);
    wd.master_sig = af->master_sig;
    af = af->next;
    if (sizeof (wd) !=
        GNUNET_DISK_file_write (fh,
                                &wd,
                                sizeof (wd)))
    {
      GNUNET_assert (GNUNET_OK ==
                     GNUNET_DISK_file_close (fh));
      return GNUNET_SYSERR;
    }
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_DISK_file_close (fh));
  return GNUNET_OK;
}


/**
 * Free @a af data structure
 *
 * @param af list to free
 */
void
TALER_EXCHANGEDB_fees_free (struct TALER_EXCHANGEDB_AggregateFees *af)
{
  struct TALER_EXCHANGEDB_AggregateFees *next;

  while (NULL != af)
  {
    next = af->next;
    GNUNET_free (af);
    af = next;
  }
}


/* end of exchangedb_fees.c */
