/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file util/taler-exchange-secmod-eddsa.c
 * @brief Standalone process to perform private key EDDSA operations
 * @author Christian Grothoff
 *
 * Key design points:
 * - EVERY thread of the exchange will have its own pair of connections to the
 *   crypto helpers.  This way, every threat will also have its own /keys state
 *   and avoid the need to synchronize on those.
 * - auditor signatures and master signatures are to be kept in the exchange DB,
 *   and merged with the public keys of the helper by the exchange HTTPD!
 * - the main loop of the helper is SINGLE-THREADED, but there are
 *   threads for crypto-workers which (only) do the signing in parallel,
 *   one per client.
 * - thread-safety: signing happens in parallel, thus when REMOVING private keys,
 *   we must ensure that all signers are done before we fully free() the
 *   private key. This is done by reference counting (as work is always
 *   assigned and collected by the main thread).
 */
#include "platform.h"
#include "taler_util.h"


/**
 * The entry point.
 *
 * @param argc number of arguments in @a argv
 * @param argv command-line arguments
 * @return 0 on normal termination
 */
int
main (int argc,
      char **argv)
{
  struct TALER_SECMOD_Options opts = {
    .max_workers = 16,
    .section = "taler-exchange"
  };
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    TALER_SECMOD_OPTIONS (&opts),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* Restrict permissions for the key files that we create. */
  (void) umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);
  opts.global_now_tmp
    = opts.global_now = GNUNET_TIME_timestamp_get ();
  ret = GNUNET_PROGRAM_run (TALER_EXCHANGE_project_data (),
                            argc,
                            argv,
                            "taler-exchange-secmod-eddsa",
                            "Handle private EDDSA key operations for a Taler exchange",
                            options,
                            &TALER_SECMOD_eddsa_run,
                            &opts);
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  return opts.global_ret;
}
