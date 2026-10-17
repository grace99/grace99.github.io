/* Current account balances by due month; this is not a historical month-end snapshot. */
window.FernsAnalytics={
 accountTrend(villas,dues,now=new Date()){
  const accounts=[...new Map(villas.map(v=>[String(v.id),v])).values()],ids=new Set(accounts.map(v=>String(v.id)));
  const cents=value=>Number.isFinite(Number(value))?Math.round(Number(value)*100):0;
  const today=`${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
  const indexed=new Map();for(const d of dues){const key=String(d.villa)+'|'+String(d.dueDate||'').slice(0,7);if(!indexed.has(key))indexed.set(key,[]);indexed.get(key).push(d);}
  const buckets=Array.from({length:12},(_,month)=>{
   const period=`${now.getFullYear()}-${String(month+1).padStart(2,'0')}`,future=month>now.getMonth();
   const rows=accounts.map(v=>{const items=indexed.get(String(v.id)+'|'+period)||[];
    const assessment=items.reduce((sum,d)=>sum+cents(d.dueAmt),0),applied=items.reduce((sum,d)=>sum+cents(d.paidAmt),0),balance=items.reduce((sum,d)=>sum+Math.max(0,cents(d.outstandingAmt)),0),overdue=items.reduce((sum,d)=>sum+(d.dueDate<today?Math.max(0,cents(d.outstandingAmt)):0),0);
    const status=future?'Upcoming month':(!items.length||items.every(d=>d.dueAmt==null))?'No dues loaded':overdue>0?'Overdue':balance>0?'Not yet due':'Paid / NIL';
    return {villa:String(v.id),name:v.name||'',month:period,status,assessment:assessment/100,applied:applied/100,balance:balance/100,overdue:overdue/100,dueItems:items.length};
   });
   return {period,label:new Date(now.getFullYear(),month,1).toLocaleDateString(undefined,{month:'short',year:'numeric'}),future,rows};
  });
  return {accounts:accounts.length,buckets,orphanDues:dues.filter(d=>!ids.has(String(d.villa))).length};
 }
};
function defaultersChart(){
 const model=FernsAnalytics.accountTrend(db.villas,db.dues.map(d=>({...d,paidAmt:duePaid(d),outstandingAmt:dueOutstanding(d)}))),maximum=Math.max(1,model.accounts),height=126;
 const categories=[{status:'Overdue',label:'Overdue',color:'#d85b57'},{status:'Paid / NIL',label:'Paid / NIL',color:'#179d87'},{status:'Not yet due',label:'Not yet due',color:'#dca345'},{status:'No dues loaded',label:'No dues loaded',color:'#8298aa'}];
 const bars=model.buckets.map((bucket,index)=>{
  const x=64+index*90,allKey=`Analytics:defaulters:${index}:all`;
  statDrills.set(allKey,{title:'All villa accounts · '+bucket.label,kind:'account-status',rows:bucket.rows});
  const counts=categories.map(c=>bucket.rows.filter(row=>row.status===c.status).length),tooltip=bucket.future?`${bucket.label}\nUpcoming month\n${model.accounts} villa accounts`:`${bucket.label}\n${categories.map((c,i)=>c.label+': '+counts[i]).join('\n')}\nTotal: ${model.accounts} villa accounts`;
  let y=146;
  const segments=bucket.future?`<g role="button" tabindex="0" data-stat-drill="${allKey}" aria-label="Upcoming month · ${bucket.label}" data-trend-tooltip="${esc(tooltip)}"><rect x="${x}" y="20" width="36" height="126" rx="3" fill="transparent" stroke="#8298aa" stroke-dasharray="4 4"/></g>`:categories.map((c,ci)=>{
   const rows=bucket.rows.filter(row=>row.status===c.status),key=`Analytics:defaulters:${index}:${ci}`,barHeight=rows.length/maximum*height;y-=barHeight;
   statDrills.set(key,{title:c.label+' accounts · '+bucket.label,kind:'account-status',rows});
   return rows.length?`<g role="button" tabindex="0" class="defaulter-segment" data-status="${c.status}" data-count="${rows.length}" data-stat-drill="${key}" aria-label="${c.label} accounts · ${bucket.label}: ${rows.length}" data-trend-tooltip="${esc(tooltip)}"><rect x="${x}" y="${y}" width="36" height="${barHeight}" fill="${c.color}"/></g>`:'';
  }).join('');
  return `<g class="defaulter-month" data-month="${bucket.period}">${segments}<text x="${x+18}" y="175" text-anchor="middle" role="button" tabindex="0" data-stat-drill="${allKey}" aria-label="All villa accounts · ${bucket.label}: ${model.accounts}">${bucket.label.split(' ')[0]}</text></g>`;
 }).join('');
 return `<section class="card defaulters-chart"><div class="card-head"><div><h2>Defaulters trend</h2><p class="card-desc">${new Date().getFullYear()} · ${model.accounts} villa accounts · current balances by due month</p></div><div class="legend defaulters-legend">${categories.map(c=>`<span><i style="background:${c.color}"></i>${c.label}</span>`).join('')}</div></div><div class="chart"><svg viewBox="0 0 1140 190" role="group" aria-label="Full year villa account payment status chart">${[0,1,2,3].map(n=>`<text x="0" y="${24+n*42}">${Math.round(maximum*(1-n/3))}</text><line x1="36" x2="1130" y1="${20+n*42}" y2="${20+n*42}" stroke="#8298aa55" stroke-dasharray="3 4"/>`).join('')}${bars}</svg></div><p class="defaulters-note">Overdue means a positive balance after its due date, including partial payments. Only applied payments reduce these balances. Select a segment for details, or a month label for every villa account. Multi-plot villas count as one account.${model.orphanDues?` ${model.orphanDues} due items have no matching villa account.`:''}</p></section>`;
}
