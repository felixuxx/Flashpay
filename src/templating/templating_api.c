/*
  This file is part of TALER
  Copyright (C) 2020, 2022 Taler Systems SA

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
 * @file templating_api.c
 * @brief logic to load and complete HTML templates
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include "taler_templating_lib.h"
#include "mustach.h"
#include "mustach-jansson.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * Entry in a key-value array we use to cache templates.
 */
struct TVE
{
  /**
   * A name, used as the key. NULL for the last entry.
   */
  char *name;

  /**
   * Language the template is in.
   */
  char *lang;

  /**
   * 0-terminated (!) file data to return for @e name and @e lang.
   */
  char *value;

};


/**
 * Array of templates loaded into RAM.
 */
static struct TVE *loaded;

/**
 * Length of the #loaded array.
 */
static unsigned int loaded_length;


/**
 * Load Mustach template into memory.  Note that we intentionally cache
 * failures, that is if we ever failed to load a template, we will never try
 * again.
 *
 * @param connection the connection we act upon
 * @param name name of the template file to load
 *        (MUST be a 'static' string in memory!)
 * @return NULL on error, otherwise the template
 */
static const char *
lookup_template (struct MHD_Connection *connection,
                 const char *name)
{
  struct TVE *best = NULL;
  const char *lang;

  lang = MHD_lookup_connection_value (connection,
                                      MHD_HEADER_KIND,
                                      MHD_HTTP_HEADER_ACCEPT_LANGUAGE);
  if (NULL == lang)
    lang = "en";
  /* find best match by language */
  for (unsigned int i = 0; i<loaded_length; i++)
  {
    if (0 != strcmp (loaded[i].name,
                     name))
      continue; /* does not match by name */
    if ( (NULL == best) ||
         (TALER_language_matches (lang,
                                  loaded[i].lang) >
          TALER_language_matches (lang,
                                  best->lang) ) )
      best = &loaded[i];
  }
  if (NULL == best)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No templates found in `%s'\n",
                name);
    return NULL;
  }
  return best->value;
}


/**
 * Get the base URL for static resources.
 *
 * @param con the MHD connection
 * @param instance_id the instance ID
 * @returns the static files base URL, guaranteed
 *          to have a trailing slash.
 */
static char *
make_static_url (struct MHD_Connection *con,
                 const char *instance_id)
{
  const char *host;
  const char *forwarded_host;
  const char *uri_path;
  struct GNUNET_Buffer buf = { 0 };

  host = MHD_lookup_connection_value (con,
                                      MHD_HEADER_KIND,
                                      "Host");
  forwarded_host = MHD_lookup_connection_value (con,
                                                MHD_HEADER_KIND,
                                                "X-Forwarded-Host");

  uri_path = MHD_lookup_connection_value (con,
                                          MHD_HEADER_KIND,
                                          "X-Forwarded-Prefix");
  if (NULL != forwarded_host)
    host = forwarded_host;

  if (NULL == host)
  {
    GNUNET_break (0);
    return NULL;
  }

  GNUNET_assert (NULL != instance_id);

  if (GNUNET_NO == TALER_mhd_is_https (con))
    GNUNET_buffer_write_str (&buf,
                             "http://");
  else
    GNUNET_buffer_write_str (&buf,
                             "https://");
  GNUNET_buffer_write_str (&buf,
                           host);
  if (NULL != uri_path)
    GNUNET_buffer_write_path (&buf,
                              uri_path);
  if (0 != strcmp ("default",
                   instance_id))
  {
    GNUNET_buffer_write_path (&buf,
                              "instances");
    GNUNET_buffer_write_path (&buf,
                              instance_id);
  }
  GNUNET_buffer_write_path (&buf,
                            "static/");
  return GNUNET_buffer_reap_str (&buf);
}


enum GNUNET_GenericReturnValue
TALER_TEMPLATING_build (struct MHD_Connection *connection,
                        unsigned int *http_status,
                        const char *template,
                        const char *instance_id,
                        const char *taler_uri,
                        json_t *root,
                        struct MHD_Response **reply)
{
  char *body;
  size_t body_size;

  {
    const char *tmpl;
    int eno;

    tmpl = lookup_template (connection,
                            template);
    if (NULL == tmpl)
    {
      /* FIXME: should this not be an
         internal failure? The language
         mismatch is not critical here! */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to load template `%s'\n",
                  template);
      *http_status = MHD_HTTP_NOT_ACCEPTABLE;
      *reply = TALER_MHD_make_error (TALER_EC_GENERIC_FAILED_TO_LOAD_TEMPLATE,
                                     template);
      return GNUNET_NO;
    }
    /* Add default values to the context */
    if (NULL != instance_id)
    {
      char *static_url = make_static_url (connection,
                                          instance_id);

      GNUNET_break (0 ==
                    json_object_set_new (root,
                                         "static_url",
                                         json_string (static_url)));
      GNUNET_free (static_url);
    }
    if (0 !=
        (eno = mustach_jansson (tmpl,
                                root,
                                &body,
                                &body_size)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "mustach failed on template `%s' with error %d\n",
                  template,
                  eno);
      *http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
      *reply = TALER_MHD_make_error (TALER_EC_GENERIC_FAILED_TO_EXPAND_TEMPLATE,
                                     template);
      return GNUNET_NO;
    }
  }

  /* try to compress reply if client allows it */
  {
    bool compressed = false;

    if (MHD_YES ==
        TALER_MHD_can_compress (connection))
    {
      compressed = TALER_MHD_body_compress ((void **) &body,
                                            &body_size);
    }
    *reply = MHD_create_response_from_buffer (body_size,
                                              body,
                                              MHD_RESPMEM_MUST_FREE);
    if (NULL == *reply)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    if (compressed)
    {
      if (MHD_NO ==
          MHD_add_response_header (*reply,
                                   MHD_HTTP_HEADER_CONTENT_ENCODING,
                                   "deflate"))
      {
        GNUNET_break (0);
        MHD_destroy_response (*reply);
        *reply = NULL;
        return GNUNET_SYSERR;
      }
    }
  }

  /* Add standard headers */
  if (NULL != taler_uri)
    GNUNET_break (MHD_NO !=
                  MHD_add_response_header (*reply,
                                           "Taler",
                                           taler_uri));
  GNUNET_break (MHD_NO !=
                MHD_add_response_header (*reply,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         "text/html"));
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TEMPLATING_reply (struct MHD_Connection *connection,
                        unsigned int http_status,
                        const char *template,
                        const char *instance_id,
                        const char *taler_uri,
                        json_t *root)
{
  enum GNUNET_GenericReturnValue res;
  struct MHD_Response *reply;
  MHD_RESULT ret;

  res = TALER_TEMPLATING_build (connection,
                                &http_status,
                                template,
                                instance_id,
                                taler_uri,
                                root,
                                &reply);
  if (GNUNET_SYSERR == res)
    return res;
  ret = MHD_queue_response (connection,
                            http_status,
                            reply);
  MHD_destroy_response (reply);
  if (MHD_NO == ret)
    return GNUNET_SYSERR;
  return (res == GNUNET_OK)
    ? GNUNET_OK
    : GNUNET_NO;
}


/**
 * Function called with a template's filename.
 *
 * @param cls closure
 * @param filename complete filename (absolute path)
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static enum GNUNET_GenericReturnValue
load_template (void *cls,
               const char *filename)
{
  char *lang;
  char *end;
  int fd;
  struct stat sb;
  char *map;
  const char *name;

  if ('.' == filename[0])
    return GNUNET_OK;

  name = strrchr (filename,
                  '/');
  if (NULL == name)
    name = filename;
  else
    name++;
  lang = strchr (name,
                 '.');
  if (NULL == lang)
    return GNUNET_OK; /* name must include .$LANG */
  lang++;
  end = strchr (lang,
                '.');
  if ( (NULL == end) ||
       (0 != strcmp (end,
                     ".must")) )
    return GNUNET_OK; /* name must end with '.must' */

  /* finally open template */
  fd = open (filename,
             O_RDONLY);
  if (-1 == fd)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              filename);

    return GNUNET_SYSERR;
  }
  if (0 !=
      fstat (fd,
             &sb))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "open",
                              filename);
    GNUNET_break (0 == close (fd));
    return GNUNET_OK;
  }
  map = GNUNET_malloc_large (sb.st_size + 1);
  if (NULL == map)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    GNUNET_break (0 == close (fd));
    return GNUNET_SYSERR;
  }
  if (sb.st_size !=
      read (fd,
            map,
            sb.st_size))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "read",
                              filename);
    GNUNET_break (0 == close (fd));
    return GNUNET_OK;
  }
  GNUNET_break (0 == close (fd));
  GNUNET_array_grow (loaded,
                     loaded_length,
                     loaded_length + 1);
  loaded[loaded_length - 1].name = GNUNET_strndup (name,
                                                   (lang - 1) - name);
  loaded[loaded_length - 1].lang = GNUNET_strndup (lang,
                                                   end - lang);
  loaded[loaded_length - 1].value = map;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TEMPLATING_init (const char *subsystem)
{
  char *dn;
  int ret;

  {
    char *path;

    path = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_DATADIR);
    if (NULL == path)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_asprintf (&dn,
                     "%s/%s/templates/",
                     path,
                     subsystem);
    GNUNET_free (path);
  }
  ret = GNUNET_DISK_directory_scan (dn,
                                    &load_template,
                                    NULL);
  GNUNET_free (dn);
  if (-1 == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


void
TALER_TEMPLATING_done (void)
{
  for (unsigned int i = 0; i<loaded_length; i++)
  {
    GNUNET_free (loaded[i].name);
    GNUNET_free (loaded[i].lang);
    GNUNET_free (loaded[i].value);
  }
  GNUNET_array_grow (loaded,
                     loaded_length,
                     0);
}


/* end of templating_api.c */
