/*
  This file is part of TALER
  Copyright (C) 2020, 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of EXCHANGEABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_spa.c
 * @brief logic to load the single page app (/)
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "taler-exchange-httpd.h"


/**
 * Resource from the WebUi.
 */
struct WebuiFile
{
  /**
   * Kept in a DLL.
   */
  struct WebuiFile *next;

  /**
   * Kept in a DLL.
   */
  struct WebuiFile *prev;

  /**
   * Path this resource matches.
   */
  char *path;

  /**
   * SPA resource, compressed.
   */
  struct MHD_Response *zspa;

  /**
   * SPA resource, vanilla.
   */
  struct MHD_Response *spa;

};


/**
 * Resources of the WebuUI, kept in a DLL.
 */
static struct WebuiFile *webui_head;

/**
 * Resources of the WebuUI, kept in a DLL.
 */
static struct WebuiFile *webui_tail;


MHD_RESULT
TEH_handler_spa (struct TEH_RequestContext *rc,
                 const char *const args[])
{
  struct WebuiFile *w = NULL;
  const char *infix = args[0];

  if ( (NULL == infix) ||
       (0 == strcmp (infix,
                     "")) )
    infix = "index.html";
  for (struct WebuiFile *pos = webui_head;
       NULL != pos;
       pos = pos->next)
    if (0 == strcmp (infix,
                     pos->path))
    {
      w = pos;
      break;
    }
  if (NULL == w)
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       rc->url);
  if ( (MHD_YES ==
        TALER_MHD_can_compress (rc->connection)) &&
       (NULL != w->zspa) )
    return MHD_queue_response (rc->connection,
                               MHD_HTTP_OK,
                               w->zspa);
  return MHD_queue_response (rc->connection,
                             MHD_HTTP_OK,
                             w->spa);
}


/**
 * Function called on each file to load for the WebUI.
 *
 * @param cls NULL
 * @param dn name of the file to load
 */
static enum GNUNET_GenericReturnValue
build_webui (void *cls,
             const char *dn)
{
  static struct
  {
    const char *ext;
    const char *mime;
  } mime_map[] = {
    {
      .ext = "css",
      .mime = "text/css"
    },
    {
      .ext = "html",
      .mime = "text/html"
    },
    {
      .ext = "js",
      .mime = "text/javascript"
    },
    {
      .ext = "jpg",
      .mime = "image/jpeg"
    },
    {
      .ext = "jpeg",
      .mime = "image/jpeg"
    },
    {
      .ext = "png",
      .mime = "image/png"
    },
    {
      .ext = "svg",
      .mime = "image/svg+xml"
    },
    {
      .ext = NULL,
      .mime = NULL
    },
  };
  int fd;
  struct stat sb;
  struct MHD_Response *zspa = NULL;
  struct MHD_Response *spa;
  const char *ext;
  const char *mime;

  (void) cls;
  /* finally open template */
  fd = open (dn,
             O_RDONLY);
  if (-1 == fd)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              dn);
    return GNUNET_SYSERR;
  }
  if (0 !=
      fstat (fd,
             &sb))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              dn);
    GNUNET_break (0 == close (fd));
    return GNUNET_SYSERR;
  }

  mime = NULL;
  ext = strrchr (dn, '.');
  if (NULL == ext)
  {
    GNUNET_break (0 == close (fd));
    return GNUNET_OK;
  }
  ext++;
  for (unsigned int i = 0; NULL != mime_map[i].ext; i++)
    if (0 == strcasecmp (ext,
                         mime_map[i].ext))
    {
      mime = mime_map[i].mime;
      break;
    }

  {
    void *in;
    ssize_t r;
    size_t csize;

    in = GNUNET_malloc_large (sb.st_size);
    if (NULL == in)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "malloc");
      GNUNET_break (0 == close (fd));
      return GNUNET_SYSERR;
    }
    r = read (fd,
              in,
              sb.st_size);
    if ( (-1 == r) ||
         (sb.st_size != (size_t) r) )
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "read",
                                dn);
      GNUNET_free (in);
      GNUNET_break (0 == close (fd));
      return GNUNET_SYSERR;
    }
    csize = (size_t) r;
    if (MHD_YES ==
        TALER_MHD_body_compress (&in,
                                 &csize))
    {
      zspa = MHD_create_response_from_buffer (csize,
                                              in,
                                              MHD_RESPMEM_MUST_FREE);
      if (NULL != zspa)
      {
        if (MHD_NO ==
            MHD_add_response_header (zspa,
                                     MHD_HTTP_HEADER_CONTENT_ENCODING,
                                     "deflate"))
        {
          GNUNET_break (0);
          MHD_destroy_response (zspa);
          zspa = NULL;
        }
        if (NULL != mime)
          GNUNET_break (MHD_YES ==
                        MHD_add_response_header (zspa,
                                                 MHD_HTTP_HEADER_CONTENT_TYPE,
                                                 mime));
      }
    }
    else
    {
      GNUNET_free (in);
    }
  }

  spa = MHD_create_response_from_fd (sb.st_size,
                                     fd);
  if (NULL == spa)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              dn);
    GNUNET_break (0 == close (fd));
    if (NULL != zspa)
    {
      MHD_destroy_response (zspa);
      zspa = NULL;
    }
    return GNUNET_SYSERR;
  }
  if (NULL != mime)
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (spa,
                                           MHD_HTTP_HEADER_CONTENT_TYPE,
                                           mime));

  {
    struct WebuiFile *w;
    const char *fn;

    fn = strrchr (dn, '/');
    GNUNET_assert (NULL != fn);
    w = GNUNET_new (struct WebuiFile);
    w->path = GNUNET_strdup (fn + 1);
    w->spa = spa;
    w->zspa = zspa;
    GNUNET_CONTAINER_DLL_insert (webui_head,
                                 webui_tail,
                                 w);
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TEH_spa_init ()
{
  char *dn;

  {
    char *path;

    path = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_DATADIR);
    if (NULL == path)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_asprintf (&dn,
                     "%sexchange/spa/",
                     path);
    GNUNET_free (path);
  }

  if (-1 ==
      GNUNET_DISK_directory_scan (dn,
                                  &build_webui,
                                  NULL))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to load WebUI from `%s'\n",
                dn);
    GNUNET_free (dn);
    return GNUNET_SYSERR;
  }
  GNUNET_free (dn);
  return GNUNET_OK;
}


/**
 * Nicely shut down.
 */
void __attribute__ ((destructor))
get_spa_fini ()
{
  struct WebuiFile *w;

  while (NULL != (w = webui_head))
  {
    GNUNET_CONTAINER_DLL_remove (webui_head,
                                 webui_tail,
                                 w);
    if (NULL != w->spa)
    {
      MHD_destroy_response (w->spa);
      w->spa = NULL;
    }
    if (NULL != w->zspa)
    {
      MHD_destroy_response (w->zspa);
      w->zspa = NULL;
    }
    GNUNET_free (w->path);
    GNUNET_free (w);
  }
}
