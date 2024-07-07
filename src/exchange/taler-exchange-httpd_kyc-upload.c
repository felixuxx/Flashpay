/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-upload.c
 * @brief Handle /kyc-upload/$ID request
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-exchange-httpd_kyc-upload.h"

/**
 * Size of the MHD post processor upload buffer.  Rather large, as we expect
 * large documents. Note that we *additionally* do stream processing, so the
 * actual uploads can be larger and are bounded (globally) by
 * #TALER_MHD_REQUEST_BUFFER_MAX.
 */
#define UPLOAD_BUFFER_SIZE (1024 * 1024)


/**
 * Context used for processing the KYC upload req
 */
struct UploadContext
{

  /**
   * Access token for the KYC data of the account.
   */
  struct TALER_AccountAccessTokenP access_token;

  /**
   * Index of the measure this upload is for.
   */
  unsigned int measure_index;

  /**
   * Index in the legitimization measures table this ID
   * refers to.
   */
  unsigned long long legitimization_measure_serial_id;

  /**
   * Our post processor.
   */
  struct MHD_PostProcessor *pp;

  /**
   * Uploaded data, in JSON.
   */
  json_t *result;

  /**
   * Last key in upload.
   */
  char *last_key;

  /**
   * Name of the file, possibly NULL.
   */
  char *filename;

  /**
   * Content type, possibly NULL.
   */
  char *content_type;

  /**
   * Current upload data.
   */
  char *curr_buf;

  /**
   * Size of @e curr_buf allocation.
   */
  size_t buf_size;

  /**
   * Number of bytes of actual data in @a curr_buf.
   */
  size_t buf_pos;

};


/**
 * Check if the upload data is in binary and thus
 * must be base32-encoded.
 *
 * @param uc upload context with data to eval
 */
static bool
is_binary (const struct UploadContext *uc)
{
  if (NULL != memchr (uc->curr_buf,
                      '\0',
                      uc->buf_pos))
    return true;
  if (NULL != uc->filename)
    return true; /* we always encode all files */
  if (NULL == uc->content_type)
    return false; /* fingers crossed */
  if (0 == strncmp (uc->content_type,
                    "text/",
                    strlen ("text/")))
    return false; /* good */
  return true;
}


/**
 * Finish processing the data in @a uc under the current
 * key.
 *
 * @param[in,out] uc upload context with key to process
 */
static void
finish_key (struct UploadContext *uc)
{
  json_t *val;

  if (NULL == uc->last_key)
    return; /* nothing to do */
  if (is_binary (uc))
  {
    val = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("filename",
                                 uc->filename)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("content_type",
                                 uc->content_type)),
      GNUNET_JSON_pack_data_varsize ("data",
                                     uc->curr_buf,
                                     uc->buf_pos)
      );
  }
  else
  {
    val = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("content_type",
                                 uc->content_type)),
      GNUNET_JSON_pack_string ("text",
                               uc->curr_buf));
  }
  GNUNET_assert (0 ==
                 json_object_set_new (uc->result,
                                      uc->last_key,
                                      val));
  GNUNET_free (uc->last_key);
  GNUNET_free (uc->filename);
  GNUNET_free (uc->content_type);
  memset (uc->curr_buf,
          0,
          uc->buf_pos);
  uc->buf_pos = 0;
}


/**
 * Function called to clean up upload context.
 */
static void
upload_cleaner (struct TEH_RequestContext *rc)
{
  struct UploadContext *uc = rc->rh_ctx;

  MHD_destroy_post_processor (uc->pp);
  GNUNET_free (uc->filename);
  GNUNET_free (uc->content_type);
  GNUNET_free (uc->last_key);
  GNUNET_free (uc->curr_buf);
  json_decref (uc->result);
  GNUNET_free (uc);
}


/**
 * Iterator over key-value pairs where the value
 * may be made available in increments and/or may
 * not be zero-terminated.  Used for processing
 * POST data.
 *
 * @param cls user-specified closure
 * @param kind type of the value, always #MHD_POSTDATA_KIND when called from MHD
 * @param key 0-terminated key for the value, NULL if not known. This value
 *            is never NULL for url-encoded POST data.
 * @param filename name of the uploaded file, NULL if not known
 * @param content_type mime-type of the data, NULL if not known
 * @param transfer_encoding encoding of the data, NULL if not known
 * @param data pointer to @a size bytes of data at the
 *              specified offset
 * @param off offset of data in the overall value
 * @param size number of bytes in @a data available
 * @return #MHD_YES to continue iterating,
 *         #MHD_NO to abort the iteration
 */
static enum MHD_Result
post_helper (void *cls,
             enum MHD_ValueKind kind,
             const char *key,
             const char *filename,
             const char *content_type,
             const char *transfer_encoding,
             const char *data,
             uint64_t off,
             size_t size)
{
  struct UploadContext *uc = cls;

  if ( (NULL != uc->last_key) &&
       (0 != strcmp (key,
                     uc->last_key)) )
    finish_key (uc);
  if (NULL == uc->last_key)
  {
    uc->last_key = GNUNET_strdup (key);
    if (NULL != filename)
      uc->filename = GNUNET_strdup (filename);
    if (NULL != content_type)
      uc->content_type = GNUNET_strdup (content_type);
  }
  if (size > uc->buf_size - uc->buf_pos)
  {
    char *tmp;
    size_t tgt;

    tgt = uc->buf_size * 2;
    if (tgt >= GNUNET_MAX_MALLOC_CHECKED - 1)
      tgt = GNUNET_MAX_MALLOC_CHECKED - 1;
    if (tgt < size + uc->buf_pos)
      tgt = size + uc->buf_pos;
    if (tgt >= GNUNET_MAX_MALLOC_CHECKED - 1)
      return MHD_NO;
    tmp = GNUNET_malloc (tgt + 1); /* for 0-termination */
    memcpy (tmp,
            uc->curr_buf,
            uc->buf_pos);
    GNUNET_free (uc->curr_buf);
    uc->buf_size = tgt;
    uc->curr_buf = tmp;
  }
  memcpy (uc->curr_buf + uc->buf_pos,
          data,
          size);
  uc->buf_pos += size;
  return MHD_YES;
}


MHD_RESULT
TEH_handler_kyc_upload (struct TEH_RequestContext *rc,
                        const char *id,
                        size_t *upload_data_size,
                        const char *upload_data)
{
  struct UploadContext *uc = rc->rh_ctx;

  if (NULL == uc)
  {
    const char *slash;
    char dummy;

    uc = GNUNET_new (struct UploadContext);
    uc->pp = MHD_create_post_processor (rc->connection,
                                        UPLOAD_BUFFER_SIZE,
                                        &post_helper,
                                        uc);
    if (NULL == uc->pp)
    {
      GNUNET_break (0);
      GNUNET_free (uc);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_ALLOCATION_FAILURE,
        "MHD_create_post_processor");
    }
    uc->result = json_object ();
    GNUNET_assert (NULL != uc->result);
    rc->rh_ctx = uc;
    rc->rh_cleaner = &upload_cleaner;

    slash = strchr (id, '-');
    if (NULL == slash)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
        rc->url);
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (id,
                                       slash - id,
                                       &uc->access_token,
                                       sizeof (uc->access_token)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "Access token in ID is malformed");
    }
    if (2 != sscanf (slash + 1,
                     "%u-%llu%c",
                     &uc->measure_index,
                     &uc->legitimization_measure_serial_id,
                     &dummy))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "ID is malformed");
    }
    return MHD_YES;
  }
  if (0 != *upload_data_size)
  {
    MHD_RESULT mres;

    mres = MHD_post_process (uc->pp,
                             upload_data,
                             *upload_data_size);
    *upload_data_size = 0;
    return mres;
  }
  finish_key (uc);

  {
    uint64_t legi_process_row;
    struct TALER_PaytoHashP h_payto;
    enum GNUNET_DB_QueryStatus qs;
    json_t *jmeasures;

    qs = TEH_plugin->lookup_pending_legitimization (
      TEH_plugin->cls,
      uc->legitimization_measure_serial_id,
      &uc->access_token,
      &h_payto,
      &jmeasures);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_pending_legitimization");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      // FIXME: should check for idempotency!

      /* Note: we do not distinguish between row ID unknown and
         access token wrong here; this is on purpose to
         minimize information leakage (but we could distinguish
         the two in the future to help diagnose issues) */
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_KYC_CHECK_REQUEST_UNKNOWN,
        NULL);
    }
    // FIXME: Do sanity checks on jmeasures vs. POSTed data:
    //
    // assert ! jmeasures.verboten
    // MeasureInformation mi = jmeasures.measures[measure_index]
    // Have: mi.{check_name,prog_name,context}
    // assert kyc_checks[check_name].type == form
    // assert input data matches form requirements...

    json_decref (jmeasures);

    /* Setup KYC process (which we will then immediately 'finish') */
    qs = TEH_plugin->insert_kyc_requirement_process (
      TEH_plugin->cls,
      &h_payto,
      uc->measure_index,
      uc->legitimization_measure_serial_id,
      "FORM",   // FIXME: correct??? or allow NULL?
      NULL,     /* provider account ID */
      NULL,     /* provider legi ID */
      &legi_process_row);
    if (qs <= 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "insert_kyc_requirement_process");
    }

    /* Now finally encrypt and store attribute data */
    {
      struct GNUNET_TIME_Timestamp now;
      struct GNUNET_TIME_Absolute expiration_time;
      void *enc_attributes;
      size_t enc_attributes_size;

      now = GNUNET_TIME_timestamp_get ();

      TALER_CRYPTO_kyc_attributes_encrypt (
        &TEH_attribute_key,
        uc->result,
        &enc_attributes,
        &enc_attributes_size);
      qs = TEH_plugin->insert_kyc_attributes (
        TEH_plugin->cls,
        legi_process_row,
        &h_payto,
        0 /* birthday unknown */,
        now,
        NULL /* provider name */,
        NULL /* provider account */,
        NULL /* provider legi ID */,
        expiration_time,
        enc_attributes_size,
        enc_attributes,
        false /* require aml??? Pass do not know? */
        );
      GNUNET_free (enc_attributes);
      if (qs < 0)
      {
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_STORE_FAILED,
          "insert_kyc_attributes");
      }
      if (0 == qs)
      {
        // FIXME: should check for idempotency!
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_CONFLICT,
          TALER_EC_EXCHANGE_KYC_FORM_ALREADY_UPLOADED,
          "insert_kyc_attributes");
      }
    }
  }

  return TALER_MHD_reply_static (
    rc->connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}
