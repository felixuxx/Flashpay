/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file tokens.c
 * @brief token family utility functions
 * @author Christian Blättler
 */
#include "platform.h"
#include "taler_util.h"


void
TALER_token_issue_sig_free (struct TALER_TokenIssueSignatureP *issue_sig)
{
  if (NULL != issue_sig->signature)
  {
    GNUNET_CRYPTO_unblinded_sig_decref (issue_sig->signature);
    issue_sig->signature = NULL;
  }
}
