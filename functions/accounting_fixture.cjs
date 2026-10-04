// Transactional in-memory fixture: staged writes, rollback, serialized concurrent callers.
const copy=v=>v===undefined?undefined:structuredClone(v);
function fixture(initial={}) {
  const docs=new Map(Object.entries(initial));let tail=Promise.resolve();
  const FieldValue={increment:n=>({increment:n}),serverTimestamp:()=>1000};
  function ref(path){return {path,id:path.split('/').pop(),collection:n=>col(path+'/'+n),
    get:async()=>({id:path.split('/').pop(),ref:ref(path),exists:docs.has(path),data:()=>copy(docs.get(path))}),
    update:async data=>write(path,data,true)};}
  function col(path,filters=[],max=Infinity){return {doc:id=>ref(path+'/'+id),
    where:(key,op,value)=>col(path,[...filters,[key,op,value]],max),limit:n=>col(path,filters,n),get:async()=>{
      const selected=[...docs].filter(([p,d])=>p.startsWith(path+'/')&&!p.slice(path.length+1).includes('/')&&filters.every(([k,op,v])=>op==='=='?d[k]===v:op==='in'?v.includes(d[k]):op==='>='?d[k]>=v:d[k]<=v)).slice(0,max);
      const rows=await Promise.all(selected.map(([p])=>ref(p).get()));return {docs:rows,size:rows.length,empty:!rows.length};
    }};}
  function write(path,data,merge){
    const next=merge?{...docs.get(path)}:{};
    for(const [k,v] of Object.entries(data))next[k]=v?.increment!==undefined?(next[k]||0)+v.increment:copy(v);
    docs.set(path,next);
  }
  const db={collection:col,runTransaction:action=>{
    const run=tail.then(async()=>{
      const writes=[];
      const result=await action({get:async r=>{if(writes.length)throw Error('Firestore read after write');return r.get();},
        create:(r,d)=>{if(docs.has(r.path))throw Error('already exists');writes.push([r.path,d,false]);},
        set:(r,d,o)=>writes.push([r.path,d,!!o?.merge]),
        update:(r,d)=>{if(!docs.has(r.path))throw Error('missing update '+r.path);writes.push([r.path,d,true]);},
      });
      for(const args of writes)write(...args);return result;
    });
    tail=run.catch(()=>{});return run;
  }};
  return {db,FieldValue,docs};
}
module.exports={fixture};
