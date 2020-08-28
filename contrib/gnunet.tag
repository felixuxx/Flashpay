<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<tagfile>
  <compound kind="file">
    <name>gnunet_util_lib.h</name>
    <path></path>
    <filename>gnunet_util_lib.h</filename>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_YES</name>
      <anchorfile>gnunet_util_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_OK</name>
      <anchorfile>gnunet_util_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_NO</name>
      <anchorfile>gnunet_util_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_SYSERR</name>
      <anchorfile>gnunet_util_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_TIME_UNIT_FOREVER_ABS</name>
      <anchorfile>gnunet_util_lib.h</anchorfile>
      <arglist></arglist>
    </member>
  </compound>

  <compound kind="file">
    <name>gnunet_common.h</name>
    <path></path>
    <filename>gnunet_db_lib.h</filename>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_free</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(ptr)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_free_non_null</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(ptr)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_malloc_large</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(size)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_realloc</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(ptr, size)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_new</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(type)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_malloc</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(size)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_new_array</name>
      <anchorfile>gnunet_common.h</anchorfile>
      <arglist>(n, type)</arglist>
    </member>
  </compound>
  <compound kind="file">
    <name>gnunet_db_lib.h</name>
    <path></path>
    <filename>gnunet_db_lib.h</filename>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_DB_STATUS_SUCCESS_ONE_RESULT</name>
      <anchorfile>gnunet_db_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_DB_STATUS_SUCCESS_NO_RESULTS</name>
      <anchorfile>gnunet_db_lib.h</anchorfile>
      <arglist></arglist>
    </member>
  </compound>
  <compound kind="file">
    <name>gnunet_pq_lib.h</name>
    <path></path>
    <filename>gnunet_pq_lib.h</filename>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_PQ_query_param_auto_from_type</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>(x)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <name>GNUNET_PQ_result_spec_end</name>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <name>GNUNET_PQ_result_spec_auto_from_type</name>
      <arglist>(name, dst)</arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_PQ_ResultSpec</type>
      <name>GNUNET_PQ_result_spec_absolute_time</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>(const char *name, struct GNUNET_TIME_Absolute *at)</arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_PQ_ResultSpec</type>
      <name>GNUNET_PQ_result_spec_absolute_time_nbo</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>(const char *name, struct GNUNET_TIME_AbsoluteNBO *at)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <name>GNUNET_PQ_PREPARED_STATEMENT_END</name>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <name>GNUNET_PQ_EXECUTE_STATEMENT_END</name>
      <arglist></arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_PQ_QueryParam</type>
      <name>GNUNET_PQ_query_param_absolute_time</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>(const struct GNUNET_TIME_Absolute *x)</arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_PQ_QueryParam</type>
      <name>GNUNET_PQ_query_param_absolute_time_nbo</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>(const struct GNUNET_TIME_AbsoluteNBO *x)</arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_SQ_QueryParam</type>
      <name>GNUNET_SQ_query_param_absolute_time</name>
      <anchorfile>gnunet_sq_lib.h</anchorfile>
      <arglist>(const struct GNUNET_TIME_Absolute *x)</arglist>
    </member>
    <member kind="function">
      <type>struct GNUNET_SQ_QueryParam</type>
      <name>GNUNET_PQ_query_param_absolute_time_nbo</name>
      <anchorfile>gnunet_sq_lib.h</anchorfile>
      <arglist>(const struct GNUNET_TIME_AbsoluteNBO *x)</arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_PQ_query_param_end</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="define">
      <type>#define</type>
      <name>GNUNET_SQ_query_param_end</name>
      <anchorfile>gnunet_sq_lib.h</anchorfile>
      <arglist></arglist>
    </member>
    <member kind="typedef">
      <type>int</type>
      <name>GNUNET_PQ_ResultConverter</name>
      <anchorfile>gnunet_pq_lib.h</anchorfile>
      <arglist>)(void *cls, PGresult *result, int row, const char *fname, size_t *dst_size, void *dst)</arglist>
    </member>
    <member kind="typedef">
      <type>int</type>
      <name>GNUNET_SQ_ResultConverter</name>
      <anchorfile>gnunet_sq_lib.h</anchorfile>
      <arglist>)(void *cls, sqlite3_stmt *result, unsigned int column, size_t *dst_size, void *dst)</arglist>
    </member>
  </compound>
</tagfile>
