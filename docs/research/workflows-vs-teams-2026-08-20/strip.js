// crude but faithful JS stripper: removes comments, '', "", `` (incl nested ${} kept? no - we drop template contents but KEEP ${...} expressions)
function strip(src){
  let out=''; let i=0; const n=src.length;
  while(i<n){
    const c=src[i], d=src[i+1];
    if(c==='/'&&d==='/'){ while(i<n&&src[i]!=='\n')i++; continue; }
    if(c==='/'&&d==='*'){ i+=2; while(i<n&&!(src[i]==='*'&&src[i+1]==='/'))i++; i+=2; continue; }
    if(c==="'"||c==='"'){ const q=c; i++; while(i<n){ if(src[i]==='\\'){i+=2;continue;} if(src[i]===q){i++;break;} i++; } out+=' "STR" '; continue; }
    if(c==='`'){ i++; let depth=0;
      while(i<n){ if(src[i]==='\\'){i+=2;continue;}
        if(src[i]==='$'&&src[i+1]==='{'){ // keep the expression
          i+=2; let br=1; let expr='';
          while(i<n&&br>0){ if(src[i]==='{')br++; else if(src[i]==='}')br--; if(br>0)expr+=src[i]; i++; }
          out+=' ${'+expr+'} '; continue; }
        if(src[i]==='`'){ i++; break; }
        i++; }
      out+=' `TPL` '; continue; }
    out+=c; i++;
  }
  return out;
}
const fs=require('fs');
const paths=fs.readFileSync(process.argv[2],'utf8').trim().split('\n');
const rows=[];
for(const p of paths){
  const src=fs.readFileSync(p,'utf8');
  const s=strip(src);
  const cnt=(re)=> (s.match(re)||[]).length;
  rows.push({
    file:p.split('/').pop(),
    lines:src.split('\n').length,
    agentCalls:cnt(/\bagent\s*\(/g),
    pipelineCalls:cnt(/\bpipeline\s*\(/g),
    parallelCalls:cnt(/\bparallel\s*\(/g),
    forLoop:cnt(/\bfor\s*\(/g)+cnt(/\bfor\s+await\s*\(/g),
    whileLoop:cnt(/\bwhile\s*\(/g),
    ifStmt:cnt(/(^|[^\w.$])if\s*\(/g),
    ternary:cnt(/\?[^:]{0,40}:/g),
    mapCall:cnt(/\.map\s*\(/g),
    budget:cnt(/\bbudget\b/g),
    budgetRemaining:cnt(/budget\.remaining/g),
    resume:cnt(/resumeFromRunId/g),
    promiseAll:cnt(/Promise\.all/g),
    interpInTpl:(src.match(/\$\{/g)||[]).length,
  });
}
fs.writeFileSync('census2.json',JSON.stringify(rows,null,1));
const T=(f)=>rows.reduce((a,r)=>a+r[f],0);
const H=(f)=>rows.filter(r=>r[f]>0).length;
console.log('n='+rows.length);
for(const f of ['agentCalls','pipelineCalls','parallelCalls','forLoop','whileLoop','ifStmt','ternary','mapCall','budget','budgetRemaining','resume','promiseAll'])
  console.log(f.padEnd(18), 'total='+String(T(f)).padStart(5), ' files_with>0='+String(H(f)).padStart(4));
