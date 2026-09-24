-- Cost of ToolSearch-only responses by what they loaded (list-price weights). MEASURED.
-- Join: a tool_use_input item's resp_before = the seq of the response that produced it.
with ts as (
  select r.file, r.seq, r.ctx_type, r.usd_total u, r.usd_total_at_opus55 u55, i.detail d
  from resp_priced r join item i on i.file=r.file and i.resp_before=r.seq
  where r.xdup=0 and r.tool_use_names='ToolSearch' and i.kind='tool_use_input' and i.subkind='ToolSearch' and i.xdup=0)
select case when d like 'select:%WebSearch%' or d like 'select:%WebFetch%' then 'WebSearch/WebFetch'
            when d like '%ms365%' then 'ms365'
            when d like 'select:%Monitor%' then 'Monitor'
            when d like 'select:%SendMessage%' then 'SendMessage'
            when d like 'select:%TaskStop%' or d like 'select:%TaskOutput%' then 'TaskStop/TaskOutput'
            when d like 'select:%' then 'other select'
            else 'keyword search' end as target,
       count(*) n, round(sum(u),2) usd_own, round(sum(u55),2) usd_o55,
       sum(ctx_type='main') main, sum(ctx_type!='main') agents
from ts group by 1 order by 3 desc;
