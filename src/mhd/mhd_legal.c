/*
  This file is part of TALER
  Copyright (C) 2019 Taler Systems SA

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
 * @file mhd_legal.h
 * @brief API for returning legal documents based on client language
 *        and content type preferences
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"


/**
 * Entry in the terms-of-service array.
 */
struct Terms
{
  /**
   * Mime type of the terms.
   */
  const char *mime_type;

  /**
   * The terms (NOT 0-terminated!).
   */
  void *terms;

  /**
   * The desired language.
   */
  char *language;

  /**
   * Number of bytes in @e terms.
   */
  size_t terms_size;
};


/**
 * Prepared responses for legal documents
 * (terms of service, privacy policy).
 */
struct TALER_MHD_Legal
{
  /**
   * Array of terms of service, terminated by NULL/0 value.
   */
  struct Terms *terms;

  /**
   * Length of the #terms array.
   */
  unsigned int terms_len;

  /**
   * Etag to use for the terms of service (= version).
   */
  char *terms_etag;
};


/**
 * Check if @a mime matches the @a accept_pattern.
 *
 * @param accept_pattern a mime pattern like text/plain or image/<STAR>
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


/**
 * Check if @a lang matches the @a language_pattern, and if so with
 * which preference.
 *
 * @param language_pattern a language preferences string
 *        like "fr-CH, fr;q=0.9, en;q=0.8, *;q=0.1"
 * @param lang the 2-digit language to match
 * @return q-weight given for @a lang in @a language_pattern, 1.0 if no weights are given;
 *         0 if @a lang is not in @a language_pattern
 */
static double
language_matches (const char *language_pattern,
                  const char *lang)
{
  char *p = GNUNET_strdup (language_pattern);
  char *sptr;
  double r = 0.0;

  for (char *tok = strtok_r (p, ", ", &sptr);
       NULL != tok;
       tok = strtok_r (NULL, ", ", &sptr))
  {
    char *sptr2;
    char *lp = strtok_r (tok, ";", &sptr2);
    char *qp = strtok_r (NULL, ";", &sptr2);
    double q = 1.0;

    GNUNET_break_op ( (NULL == qp) ||
                      (1 == sscanf (qp,
                                    "q=%lf",
                                    &q)) );
    if (0 == strcasecmp (lang,
                         lp))
      r = GNUNET_MAX (r, q);
  }
  GNUNET_free (p);
  return r;
}


/**
 * Generate a response with a legal document in
 * the format and language of the user's choosing.
 *
 * @param conn HTTP connection to handle
 * @param legal legal document to serve
 * @return MHD result code
 */
int
TALER_MHD_reply_legal (struct MHD_Connection *conn,
                       struct TALER_MHD_Legal *legal)
{
  struct MHD_Response *resp;
  struct Terms *t;

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
      int ret;

      resp = MHD_create_response_from_buffer (0,
                                              NULL,
                                              MHD_RESPMEM_PERSISTENT);
      ret = MHD_queue_response (conn,
                                MHD_HTTP_NOT_MODIFIED,
                                resp);
      GNUNET_break (MHD_YES == ret);
      MHD_destroy_response (resp);
      return ret;
    }
  }

  t = NULL;
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
    for (unsigned int i = 0; i < legal->terms_len; i++)
    {
      struct Terms *p = &legal->terms[i];

      if ( (NULL == t) ||
           (mime_matches (mime,
                          p->mime_type)) )
      {
        if ( (NULL == t) ||
             (! mime_matches (mime,
                              t->mime_type)) ||
             (language_matches (lang,
                                p->language) >
              language_matches (lang,
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
    void *buf = GNUNET_memdup (t->terms,
                               t->terms_size);
    size_t buf_size = t->terms_size;

    if (TALER_MHD_body_compress (&buf,
                                 &buf_size))
    {
      resp = MHD_create_response_from_buffer (buf_size,
                                              buf,
                                              MHD_RESPMEM_MUST_FREE);
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
    else
    {
      GNUNET_free (buf);
    }
  }
  if (NULL == resp)
  {
    /* could not generate compressed response, return uncompressed */
    resp = MHD_create_response_from_buffer (t->terms_size,
                                            (void *) t->terms,
                                            MHD_RESPMEM_PERSISTENT);
  }
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
    int ret;

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
 * @param legal[in,out] where to write the result
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
  } mm[] = {
    { .ext = ".html", .mime = "text/html" },
    { .ext = ".htm", .mime = "text/html" },
    { .ext = ".txt", .mime = "text/plain" },
    { .ext = ".pdf", .mime = "application/pdf" },
    { .ext = ".jpg", .mime = "image/jpeg" },
    { .ext = ".jpeg", .mime = "image/jpeg" },
    { .ext = ".png", .mime = "image/png" },
    { .ext = ".gif", .mime = "image/gif" },
    { .ext = NULL, .mime = NULL }
  };
  const char *ext = strrchr (name, '.');
  const char *mime;

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
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
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
    GNUNET_free (fn);
    if (0 != fstat (fd, &st))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "fstat",
                                fn);
      (void) close (fd);
      GNUNET_free (fn);
      return;
    }
    if (SIZE_MAX < ((unsigned long long) st.st_size))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "fstat-size",
                                fn);
      (void) close (fd);
      GNUNET_free (fn);
      return;
    }
    {
      char *buf;
      size_t bsize;
      ssize_t ret;

      bsize = (size_t) st.st_size;
      buf = GNUNET_malloc_large (bsize);
      if (NULL == buf)
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "malloc");
        (void) close (fd);
        GNUNET_free (fn);
        return;
      }
      ret = read (fd,
                  buf,
                  bsize);
      if ( (ret < 0) ||
           (bsize != ((size_t) ret)) )
      {
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                  "read",
                                  fn);
        (void) close (fd);
        GNUNET_free (buf);
        GNUNET_free (fn);
        return;
      }
      (void) close (fd);
      GNUNET_free (fn);

      /* append to global list of terms of service */
      {
        struct Terms t = {
          .mime_type = mime,
          .terms = buf,
          .language = GNUNET_strdup (lang),
          .terms_size = bsize
        };

        GNUNET_array_append (legal->terms,
                             legal->terms_len,
                             t);
      }
    }
  }
}


/**
 * Load all the terms of service from @a path under language @a lang.
 *
 * @param legal[in,out] where to write the result
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
  for (struct dirent *de = readdir (d);
       NULL != de;
       de = readdir (d))
  {
    const char *fn = de->d_name;

    if (fn[0] == '.')
      continue;
    load_terms (legal, path, lang, fn);
  }
  closedir (d);
  free (dname);
}


/**
 * Load set of legal documents as specified in
 * @a cfg in section @a section where the Etag
 * is given under the @param tagoption and the
 * directory under the @a diroption.
 *
 * @param cfg configuration to use
 * @param section section to load values from
 * @param diroption name of the option with the
 *        path to the legal documents
 * @param tagoption name of the files to use
 *        for the legal documents and the Etag
 * @return NULL on error
 */
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
  for (struct dirent *de = readdir (d);
       NULL != de;
       de = readdir (d))
  {
    const char *lang = de->d_name;

    if (lang[0] == '.')
      continue;
    load_language (legal, path, lang);
  }
  closedir (d);
  free (path);
  return legal;
}


/**
 * Free set of legal documents
 *
 * @param leg legal documents to free
 */
void
TALER_MHD_legal_free (struct TALER_MHD_Legal *legal)
{
  if (NULL == legal)
    return;
  for (unsigned int i = 0; i<legal->terms_len; i++)
  {
    struct Terms *t = &legal->terms[i];

    GNUNET_free (t->language);
    GNUNET_free (t->terms);
  }
  GNUNET_array_grow (legal->terms,
                     legal->terms_len,
                     0);
  GNUNET_free (legal->terms_etag);
  GNUNET_free (legal);
}
