/*
  This file is part of TALER
  Copyright (C) 2019, 2020, 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mhd_legal.c
 * @brief API for returning legal documents based on client language
 *        and content type preferences
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"

/**
 * How long should browsers/proxies cache the "legal" replies?
 */
#define MAX_TERMS_CACHING GNUNET_TIME_UNIT_DAYS


/**
 * Entry in the terms-of-service array.
 */
struct Terms
{
  /**
   * Kept in a DLL.
   */
  struct Terms *prev;

  /**
   * Kept in a DLL.
   */
  struct Terms *next;

  /**
   * Mime type of the terms.
   */
  const char *mime_type;

  /**
   * The terms (NOT 0-terminated!), mmap()'ed. Do not free,
   * use munmap() instead.
   */
  void *terms;

  /**
   * The desired language.
   */
  char *language;

  /**
   * deflated @e terms, to return if client supports deflate compression.
   * malloc()'ed.  NULL if @e terms does not compress.
   */
  void *compressed_terms;

  /**
   * Number of bytes in @e terms.
   */
  size_t terms_size;

  /**
   * Number of bytes in @e compressed_terms.
   */
  size_t compressed_terms_size;

  /**
   * Sorting key by format preference in case
   * everything else is equal. Higher is preferred.
   */
  unsigned int priority;

};


/**
 * Prepared responses for legal documents
 * (terms of service, privacy policy).
 */
struct TALER_MHD_Legal
{
  /**
   * DLL of terms of service.
   */
  struct Terms *terms_head;

  /**
   * DLL of terms of service.
   */
  struct Terms *terms_tail;

  /**
   * Etag to use for the terms of service (= version).
   */
  char *terms_etag;
};


/**
 * Check if @a mime matches the @a accept_pattern.
 *
 * @param accept_pattern a mime pattern like "text/plain"
 *        or "image/STAR"
 * @param mime the mime type to match
 * @return true if @a mime matches the @a accept_pattern
 */
static bool
mime_matches (const char *accept_pattern,
              const char *mime)
{
  const char *da = strchr (accept_pattern, '/');
  const char *dm = strchr (mime, '/');

  if ( (NULL == da) ||
       (NULL == dm) )
    return (0 == strcmp ("*", accept_pattern));
  return
    ( ( (1 == da - accept_pattern) &&
        ('*' == *accept_pattern) ) ||
      ( (da - accept_pattern == dm - mime) &&
        (0 == strncasecmp (accept_pattern,
                           mime,
                           da - accept_pattern)) ) ) &&
    ( (0 == strcmp (da, "/*")) ||
      (0 == strcasecmp (da,
                        dm)) );
}


bool
TALER_MHD_xmime_matches (const char *accept_pattern,
                         const char *mime)
{
  char *ap = GNUNET_strdup (accept_pattern);
  char *sptr;

  for (const char *tok = strtok_r (ap, ";", &sptr);
       NULL != tok;
       tok = strtok_r (NULL, ";", &sptr))
  {
    if (mime_matches (tok,
                      mime))
    {
      GNUNET_free (ap);
      return true;
    }
  }
  GNUNET_free (ap);
  return false;
}


MHD_RESULT
TALER_MHD_reply_legal (struct MHD_Connection *conn,
                       struct TALER_MHD_Legal *legal)
{
  struct MHD_Response *resp;
  struct Terms *t;
  struct GNUNET_TIME_Absolute a;
  struct GNUNET_TIME_Timestamp m;
  char dat[128];
  char *langs;

  a = GNUNET_TIME_relative_to_absolute (MAX_TERMS_CACHING);
  m = GNUNET_TIME_absolute_to_timestamp (a);
  TALER_MHD_get_date_string (m.abs_time,
                             dat);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Setting '%s' header to '%s'\n",
              MHD_HTTP_HEADER_EXPIRES,
              dat);
  if (NULL != legal)
  {
    const char *etag;

    etag = MHD_lookup_connection_value (conn,
                                        MHD_HEADER_KIND,
                                        MHD_HTTP_HEADER_IF_NONE_MATCH);
    if ( (NULL != etag) &&
         (NULL != legal->terms_etag) &&
         (0 == strcasecmp (etag,
                           legal->terms_etag)) )
    {
      MHD_RESULT ret;

      resp = MHD_create_response_from_buffer (0,
                                              NULL,
                                              MHD_RESPMEM_PERSISTENT);
      TALER_MHD_add_global_headers (resp);
      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (resp,
                                             MHD_HTTP_HEADER_EXPIRES,
                                             dat));

      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (resp,
                                             MHD_HTTP_HEADER_ETAG,
                                             legal->terms_etag));
      ret = MHD_queue_response (conn,
                                MHD_HTTP_NOT_MODIFIED,
                                resp);
      GNUNET_break (MHD_YES == ret);
      MHD_destroy_response (resp);
      return ret;
    }
  }

  t = NULL;
  langs = NULL;
  if (NULL != legal)
  {
    const char *mime;
    const char *lang;

    mime = MHD_lookup_connection_value (conn,
                                        MHD_HEADER_KIND,
                                        MHD_HTTP_HEADER_ACCEPT);
    if (NULL == mime)
      mime = "text/html";
    lang = MHD_lookup_connection_value (conn,
                                        MHD_HEADER_KIND,
                                        MHD_HTTP_HEADER_ACCEPT_LANGUAGE);
    if (NULL == lang)
      lang = "en";
    /* Find best match: must match mime type (if possible), and if
       mime type matches, ideally also language */
    for (struct Terms *p = legal->terms_head;
         NULL != p;
         p = p->next)
    {
      if ( (NULL == t) ||
           (TALER_MHD_xmime_matches (mime,
                                     p->mime_type)) )
      {
        if (NULL == langs)
        {
          langs = GNUNET_strdup (p->language);
        }
        else
        {
          char *tmp = langs;

          GNUNET_asprintf (&langs,
                           "%s %s",
                           tmp,
                           p->language);
          GNUNET_free (tmp);
        }
        if ( (NULL == t) ||
             (! TALER_MHD_xmime_matches (mime,
                                         t->mime_type)) ||
             (TALER_language_matches (lang,
                                      p->language) >
              TALER_language_matches (lang,
                                      t->language) ) )
          t = p;
      }
    }
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Best match for %s/%s: %s / %s\n",
                lang,
                mime,
                (NULL != t) ? t->mime_type : "<none>",
                (NULL != t) ? t->language : "<none>");
  }

  if (NULL == t)
  {
    /* Default terms of service if none are configured */
    static struct Terms none = {
      .mime_type = "text/plain",
      .terms = "not configured",
      .language = "en",
      .terms_size = strlen ("not configured")
    };

    t = &none;
  }

  /* try to compress the response */
  resp = NULL;
  if (MHD_YES ==
      TALER_MHD_can_compress (conn))
  {
    resp = MHD_create_response_from_buffer (t->compressed_terms_size,
                                            t->compressed_terms,
                                            MHD_RESPMEM_PERSISTENT);
    if (MHD_NO ==
        MHD_add_response_header (resp,
                                 MHD_HTTP_HEADER_CONTENT_ENCODING,
                                 "deflate"))
    {
      GNUNET_break (0);
      MHD_destroy_response (resp);
      resp = NULL;
    }
  }
  if (NULL == resp)
  {
    /* could not generate compressed response, return uncompressed */
    resp = MHD_create_response_from_buffer (t->terms_size,
                                            (void *) t->terms,
                                            MHD_RESPMEM_PERSISTENT);
  }
  TALER_MHD_add_global_headers (resp);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_EXPIRES,
                                         dat));
  if (NULL != langs)
  {
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           "Acceptable-Languages",
                                           langs));
    GNUNET_free (langs);
  }
  /* Set cache control headers: our response varies depending on these headers */
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_VARY,
                                         MHD_HTTP_HEADER_ACCEPT_LANGUAGE ","
                                         MHD_HTTP_HEADER_ACCEPT ","
                                         MHD_HTTP_HEADER_ACCEPT_ENCODING));
  /* Information is always public, revalidate after 10 days */
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "public max-age=864000"));
  if (NULL != legal)
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_ETAG,
                                           legal->terms_etag));
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         t->mime_type));
  {
    MHD_RESULT ret;

    ret = MHD_queue_response (conn,
                              MHD_HTTP_OK,
                              resp);
    MHD_destroy_response (resp);
    return ret;
  }
}


/**
 * Load all the terms of service from @a path under language @a lang
 * from file @a name
 *
 * @param[in,out] legal where to write the result
 * @param path where the terms are found
 * @param lang which language directory to crawl
 * @param name specific file to access
 */
static void
load_terms (struct TALER_MHD_Legal *legal,
            const char *path,
            const char *lang,
            const char *name)
{
  static struct MimeMap
  {
    const char *ext;
    const char *mime;
    unsigned int priority;
  } mm[] = {
    { .ext = ".html", .mime = "text/html", .priority = 100 },
    { .ext = ".htm", .mime = "text/html", .priority = 99 },
    { .ext = ".txt", .mime = "text/plain", .priority = 50 },
    { .ext = ".md", .mime = "text/markdown", .priority = 50 },
    { .ext = ".pdf", .mime = "application/pdf", .priority = 25 },
    { .ext = ".jpg", .mime = "image/jpeg" },
    { .ext = ".jpeg", .mime = "image/jpeg" },
    { .ext = ".png", .mime = "image/png" },
    { .ext = ".gif", .mime = "image/gif" },
    { .ext = ".epub", .mime = "application/epub+zip", .priority = 10 },
    { .ext = ".xml", .mime = "text/xml", .priority = 10 },
    { .ext = NULL, .mime = NULL }
  };
  const char *ext = strrchr (name, '.');
  const char *mime;
  unsigned int priority;

  if (NULL == ext)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unsupported file `%s' in directory `%s/%s': lacks extension\n",
                name,
                path,
                lang);
    return;
  }
  if ( (NULL == legal->terms_etag) ||
       (0 != strncmp (legal->terms_etag,
                      name,
                      ext - name - 1)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Filename `%s' does not match Etag `%s' in directory `%s/%s'. Ignoring it.\n",
                name,
                legal->terms_etag,
                path,
                lang);
    return;
  }
  mime = NULL;
  for (unsigned int i = 0; NULL != mm[i].ext; i++)
    if (0 == strcasecmp (mm[i].ext,
                         ext))
    {
      mime = mm[i].mime;
      priority = mm[i].priority;
      break;
    }
  if (NULL == mime)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unsupported file extension `%s' of file `%s' in directory `%s/%s'\n",
                ext,
                name,
                path,
                lang);
    return;
  }
  /* try to read the file with the terms of service */
  {
    struct stat st;
    char *fn;
    int fd;

    GNUNET_asprintf (&fn,
                     "%s/%s/%s",
                     path,
                     lang,
                     name);
    fd = open (fn, O_RDONLY);
    if (-1 == fd)
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "open",
                                fn);
      GNUNET_free (fn);
      return;
    }
    if (0 != fstat (fd, &st))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "fstat",
                                fn);
      GNUNET_break (0 == close (fd));
      GNUNET_free (fn);
      return;
    }
    if (SIZE_MAX < ((unsigned long long) st.st_size))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "fstat-size",
                                fn);
      GNUNET_break (0 == close (fd));
      GNUNET_free (fn);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Loading legal information from file `%s'\n",
                fn);
    {
      void *buf;
      size_t bsize;

      bsize = (size_t) st.st_size;
      buf = mmap (NULL,
                  bsize,
                  PROT_READ,
                  MAP_SHARED,
                  fd,
                  0);
      if (MAP_FAILED == buf)
      {
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                  "mmap",
                                  fn);
        GNUNET_break (0 == close (fd));
        GNUNET_free (fn);
        return;
      }
      GNUNET_break (0 == close (fd));
      GNUNET_free (fn);

      /* insert into global list of terms of service */
      {
        struct Terms *t;

        t = GNUNET_new (struct Terms);
        t->mime_type = mime;
        t->terms = buf;
        t->language = GNUNET_strdup (lang);
        t->terms_size = bsize;
        t->priority = priority;
        buf = GNUNET_memdup (t->terms,
                             t->terms_size);
        if (TALER_MHD_body_compress (&buf,
                                     &bsize))
        {
          t->compressed_terms = buf;
          t->compressed_terms_size = bsize;
        }
        else
        {
          GNUNET_free (buf);
        }
        {
          struct Terms *prev = NULL;

          for (struct Terms *pos = legal->terms_head;
               NULL != pos;
               pos = pos->next)
          {
            if (pos->priority < priority)
              break;
            prev = pos;
          }
          GNUNET_CONTAINER_DLL_insert_after (legal->terms_head,
                                             legal->terms_tail,
                                             prev,
                                             t);
        }
      }
    }
  }
}


/**
 * Load all the terms of service from @a path under language @a lang.
 *
 * @param[in,out] legal where to write the result
 * @param path where the terms are found
 * @param lang which language directory to crawl
 */
static void
load_language (struct TALER_MHD_Legal *legal,
               const char *path,
               const char *lang)
{
  char *dname;
  DIR *d;

  GNUNET_asprintf (&dname,
                   "%s/%s",
                   path,
                   lang);
  d = opendir (dname);
  if (NULL == d)
  {
    GNUNET_free (dname);
    return;
  }
  for (struct dirent *de = readdir (d);
       NULL != de;
       de = readdir (d))
  {
    const char *fn = de->d_name;

    if (fn[0] == '.')
      continue;
    load_terms (legal,
                path,
                lang,
                fn);
  }
  GNUNET_break (0 == closedir (d));
  GNUNET_free (dname);
}


struct TALER_MHD_Legal *
TALER_MHD_legal_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                      const char *section,
                      const char *diroption,
                      const char *tagoption)
{
  struct TALER_MHD_Legal *legal;
  char *path;
  DIR *d;

  legal = GNUNET_new (struct TALER_MHD_Legal);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             tagoption,
                                             &legal->terms_etag))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               section,
                               tagoption);
    GNUNET_free (legal);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               section,
                                               diroption,
                                               &path))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               section,
                               diroption);
    GNUNET_free (legal->terms_etag);
    GNUNET_free (legal);
    return NULL;
  }
  d = opendir (path);
  if (NULL == d)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_WARNING,
                               section,
                               diroption,
                               "Could not open directory");
    GNUNET_free (legal->terms_etag);
    GNUNET_free (legal);
    GNUNET_free (path);
    return NULL;
  }
  for (struct dirent *de = readdir (d);
       NULL != de;
       de = readdir (d))
  {
    const char *lang = de->d_name;

    if (lang[0] == '.')
      continue;
    load_language (legal,
                   path,
                   lang);
  }
  GNUNET_break (0 == closedir (d));
  GNUNET_free (path);
  return legal;
}


void
TALER_MHD_legal_free (struct TALER_MHD_Legal *legal)
{
  struct Terms *t;
  if (NULL == legal)
    return;
  while (NULL != (t = legal->terms_head))
  {
    GNUNET_free (t->language);
    GNUNET_free (t->compressed_terms);
    if (0 != munmap (t->terms, t->terms_size))
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "munmap");
    GNUNET_CONTAINER_DLL_remove (legal->terms_head,
                                 legal->terms_tail,
                                 t);
    GNUNET_free (t);
  }
  GNUNET_free (legal->terms_etag);
  GNUNET_free (legal);
}
