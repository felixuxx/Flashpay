/*
  This file is part of TALER
  Copyright (C) 2020, 2023, 2024 Taler Systems SA

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
 * @file mhd_spa.c
 * @brief logic to load single page apps
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>


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
  struct MHD_Response *zresponse;

  /**
   * SPA resource, vanilla.
   */
  struct MHD_Response *response;

};


/**
 * Resource from the WebUi.
 */
struct TALER_MHD_Spa
{
  /**
   * Resources of the WebUI, kept in a DLL.
   */
  struct WebuiFile *webui_head;

  /**
   * Resources of the WebUI, kept in a DLL.
   */
  struct WebuiFile *webui_tail;
};


MHD_RESULT
TALER_MHD_spa_handler (const struct TALER_MHD_Spa *spa,
                       struct MHD_Connection *connection,
                       const char *path)
{
  struct WebuiFile *w = NULL;

  if ( (NULL == path) ||
       (0 == strcmp (path,
                     "")) )
    path = "index.html";
  for (struct WebuiFile *pos = spa->webui_head;
       NULL != pos;
       pos = pos->next)
    if (0 == strcmp (path,
                     pos->path))
    {
      w = pos;
      break;
    }
  if (NULL == w)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       path);
  if ( (MHD_YES ==
        TALER_MHD_can_compress (connection)) &&
       (NULL != w->zresponse) )
    return MHD_queue_response (connection,
                               MHD_HTTP_OK,
                               w->zresponse);
  return MHD_queue_response (connection,
                             MHD_HTTP_OK,
                             w->response);
}


/**
 * Function called on each file to load for the WebUI.
 *
 * @param cls the `struct TALER_MHD_Spa *` to build
 * @param dn name of the file to load
 */
static enum GNUNET_GenericReturnValue
build_webui (void *cls,
             const char *dn)
{
  static const struct
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
  struct TALER_MHD_Spa *spa = cls;
  int fd;
  struct stat sb;
  struct MHD_Response *zresponse = NULL;
  struct MHD_Response *response;
  const char *ext;
  const char *mime;

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
      zresponse = MHD_create_response_from_buffer (csize,
                                                   in,
                                                   MHD_RESPMEM_MUST_FREE);
      if (NULL != zresponse)
      {
        if (MHD_NO ==
            MHD_add_response_header (zresponse,
                                     MHD_HTTP_HEADER_CONTENT_ENCODING,
                                     "deflate"))
        {
          GNUNET_break (0);
          MHD_destroy_response (zresponse);
          zresponse = NULL;
        }
        if (NULL != mime)
          GNUNET_break (MHD_YES ==
                        MHD_add_response_header (zresponse,
                                                 MHD_HTTP_HEADER_CONTENT_TYPE,
                                                 mime));
      }
    }
    else
    {
      GNUNET_free (in);
    }
  }

  response = MHD_create_response_from_fd (sb.st_size,
                                          fd);
  if (NULL == response)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              dn);
    GNUNET_break (0 == close (fd));
    if (NULL != zresponse)
    {
      MHD_destroy_response (zresponse);
      zresponse = NULL;
    }
    return GNUNET_SYSERR;
  }
  if (NULL != mime)
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (response,
                                           MHD_HTTP_HEADER_CONTENT_TYPE,
                                           mime));

  {
    struct WebuiFile *w;
    const char *fn;

    fn = strrchr (dn, '/');
    GNUNET_assert (NULL != fn);
    w = GNUNET_new (struct WebuiFile);
    w->path = GNUNET_strdup (fn + 1);
    w->response = response;
    w->zresponse = zresponse;
    GNUNET_CONTAINER_DLL_insert (spa->webui_head,
                                 spa->webui_tail,
                                 w);
  }
  return GNUNET_OK;
}


struct TALER_MHD_Spa *
TALER_MHD_spa_load (const char *dir)
{
  struct TALER_MHD_Spa *spa;
  char *dn;

  {
    char *path;

    path = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_DATADIR);
    if (NULL == path)
    {
      GNUNET_break (0);
      return NULL;
    }
    GNUNET_asprintf (&dn,
                     "%s%s",
                     path,
                     dir);
    GNUNET_free (path);
  }
  spa = GNUNET_new (struct TALER_MHD_Spa);
  if (-1 ==
      GNUNET_DISK_directory_scan (dn,
                                  &build_webui,
                                  spa))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to load WebUI from `%s'\n",
                dn);
    GNUNET_free (dn);
    TALER_MHD_spa_free (spa);
    return NULL;
  }
  GNUNET_free (dn);
  return spa;
}


void
TALER_MHD_spa_free (struct TALER_MHD_Spa *spa)
{
  struct WebuiFile *w;

  while (NULL != (w = spa->webui_head))
  {
    GNUNET_CONTAINER_DLL_remove (spa->webui_head,
                                 spa->webui_tail,
                                 w);
    if (NULL != w->response)
    {
      MHD_destroy_response (w->response);
      w->response = NULL;
    }
    if (NULL != w->zresponse)
    {
      MHD_destroy_response (w->zresponse);
      w->zresponse = NULL;
    }
    GNUNET_free (w->path);
    GNUNET_free (w);
  }
  GNUNET_free (spa);
}
