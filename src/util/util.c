/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file util.c
 * @brief Common utility functions; we might choose to move those to GNUnet at some point
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>


/**
 * Convert a buffer to an 8-character string
 * representative of the contents. This is used
 * for logging binary data when debugging.
 *
 * @param buf buffer to log
 * @param buf_size number of bytes in @a buf
 * @return text representation of buf, valid until next
 *         call to this function
 */
const char *
TALER_b2s (const void *buf,
	   size_t buf_size)
{
  static char ret[9];
  struct GNUNET_HashCode hc;
  char *tmp;

  GNUNET_CRYPTO_hash (buf,
		      buf_size,
		      &hc);
  tmp = GNUNET_STRINGS_data_to_string_alloc (&hc,
					     sizeof (hc));
  memcpy (ret,
	  tmp,
	  8);
  GNUNET_free (tmp);
  ret[8] = '\0';
  return ret;
}	   


/**
 * Obtain denomination amount from configuration file.
 *
 * @param cfg configuration to use
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_config_get_denom (struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        const char *option,
                        struct TALER_Amount *denom)
{
  char *str;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             option,
                                             &str))
    return GNUNET_NO;
  if (GNUNET_OK != TALER_string_to_amount (str,
                                           denom))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Round a time value so that it is suitable for transmission
 * via JSON encodings.
 *
 * @param at time to round
 * @return #GNUNET_OK if time was already rounded, #GNUNET_NO if
 *         it was just now rounded
 */
int
TALER_round_abs_time (struct GNUNET_TIME_Absolute *at)
{
  if (at->abs_value_us == GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us)
    return GNUNET_OK;
  if (0 == at->abs_value_us % 1000000)
    return GNUNET_OK;
  at->abs_value_us -= at->abs_value_us % 1000000;
  return GNUNET_NO;
}


/**
 * Round a time value so that it is suitable for transmission
 * via JSON encodings.
 *
 * @param rt time to round
 * @return #GNUNET_OK if time was already rounded, #GNUNET_NO if
 *         it was just now rounded
 */
int
TALER_round_rel_time (struct GNUNET_TIME_Relative *rt)
{
  if (rt->rel_value_us == GNUNET_TIME_UNIT_FOREVER_REL.rel_value_us)
    return GNUNET_OK;
  if (0 == rt->rel_value_us % 1000000)
    return GNUNET_OK;
  rt->rel_value_us -= rt->rel_value_us % 1000000;
  return GNUNET_NO;
}


/**
 * Load configuration by parsing all configuration
 * files in the given directory.
 *
 * @param base_dir directory with the configuration files
 * @return NULL on error, otherwise configuration
 */
struct GNUNET_CONFIGURATION_Handle *
TALER_config_load (const char *base_dir)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *cfg_dir;
  int res;

  res = GNUNET_asprintf (&cfg_dir,
                         "%s" DIR_SEPARATOR_STR "config",
                         base_dir);
  GNUNET_assert (res > 0);
  cfg = GNUNET_CONFIGURATION_create ();
  res = GNUNET_CONFIGURATION_load_from (cfg, cfg_dir);
  GNUNET_free (cfg_dir);
  if (GNUNET_OK != res)
   return NULL;
  return cfg;
}



/**
 * At what offset does the help text start?
 */
#define BORDER 29

/**
 * Print out details on command line options (implements --help).
 *
 * @param ctx command line processing context
 * @param scls additional closure (points to about text)
 * @param option name of the option
 * @param value not used (NULL)
 * @return #GNUNET_NO (do not continue, not an error)
 */
int
TALER_GETOPT_format_help_ (struct GNUNET_GETOPT_CommandLineProcessorContext *ctx,
			   void *scls,
			   const char *option,
			   const char *value)
{
  const char *about = scls;
  size_t slen;
  unsigned int i;
  int j;
  size_t ml;
  size_t p;
  char *scp;
  const char *trans;
  const struct GNUNET_GETOPT_CommandLineOption *opt;

  if (NULL != about)
  {
    printf ("%s\n%s\n",
	    ctx->binaryOptions,
	    gettext (about));
    printf (_("Arguments mandatory for long options are also mandatory for short options.\n"));
  }
  opt = ctx->allOptions;
  for (i=0;NULL != opt[i].description;i++)
  {
    if (opt[i].shortName == '\0')
      printf ("      ");
    else
      printf ("  -%c, ", opt[i].shortName);
    printf ("--%s", opt[i].name);
    slen = 8 + strlen (opt[i].name);
    if (opt[i].argumentHelp != NULL)
    {
      printf ("=%s", opt[i].argumentHelp);
      slen += 1 + strlen (opt[i].argumentHelp);
    }
    if (slen > BORDER)
    {
      printf ("\n%*s", BORDER, "");
      slen = BORDER;
    }
    if (slen < BORDER)
    {
      printf ("%*s", (int) (BORDER - slen), "");
      slen = BORDER;
    }
    if (0 < strlen (opt[i].description))
      trans = gettext (opt[i].description);
    else
      trans = "";
    ml = strlen (trans);
    p = 0;
OUTER:
    while (ml - p > 78 - slen)
    {
      for (j = p + 78 - slen; j > p; j--)
      {
        if (isspace ((unsigned char) trans[j]))
        {
          scp = GNUNET_malloc (j - p + 1);
          memcpy (scp, &trans[p], j - p);
          scp[j - p] = '\0';
          printf ("%s\n%*s", scp, BORDER + 2, "");
          GNUNET_free (scp);
          p = j + 1;
          slen = BORDER + 2;
          goto OUTER;
        }
      }
      /* could not find space to break line */
      scp = GNUNET_malloc (78 - slen + 1);
      memcpy (scp, &trans[p], 78 - slen);
      scp[78 - slen] = '\0';
      printf ("%s\n%*s", scp, BORDER + 2, "");
      GNUNET_free (scp);
      slen = BORDER + 2;
      p = p + 78 - slen;
    }
    /* print rest */
    if (p < ml)
      printf ("%s\n", &trans[p]);
    if (strlen (trans) == 0)
      printf ("\n");
  }
  printf ("Report bugs to taler@gnu.org.\n"
          "Taler home page: http://www.gnu.org/software/taler/\n"
          "General help using GNU software: http://www.gnu.org/gethelp/\n");
  return GNUNET_NO;
}



/* end of util.c */
