create temporary view sizes as
  select table_name as n,
         pg_relation_size(quote_ident(table_name)) / 1024.0 / 1024.0 as s_tbl,
	 pg_indexes_size(quote_ident(table_name)) / 1024.0 / 1024.0 as s_idx
   from information_schema.tables
   where table_schema = 'public';


select n, s_tbl, s_idx, s_tbl + s_idx from sizes where (s_tbl) != 0
order by (s_tbl + s_idx);

select sum(s_tbl), sum(s_idx), sum(s_tbl + s_idx) from sizes where s_tbl != 0;
