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
    const status=future?'Upcoming month':(!items.length||items.every(d=>d.dueAmt==null))?'No dues loaded':overdue>0?'Overdue':balance>0?'Not yet due':'CLEARED';
    return {villa:String(v.id),name:v.name||'',month:period,status,assessment:assessment/100,applied:applied/100,balance:balance/100,overdue:overdue/100,defaultCount:items.filter(d=>d.dueDate<today&&cents(d.outstandingAmt)>0).length,dueItems:items.length};
   });
   return {period,label:new Date(now.getFullYear(),month,1).toLocaleDateString(undefined,{month:'short',year:'numeric'}),future,rows};
  });
  return {accounts:accounts.length,buckets,orphanDues:dues.filter(d=>!ids.has(String(d.villa))).length};
 }
};
window.FernsAnalytics.ageing=(villas,dues,now=new Date())=>{
 const cents=v=>Number.isFinite(Number(v))?Math.round(Number(v)*100):0;
 const today=Date.UTC(now.getFullYear(),now.getMonth(),now.getDate());
 const bands=[{key:'current',label:'Not yet due'},{key:'1-30',label:'1–30 days'},{key:'31-60',label:'31–60 days'},{key:'61-90',label:'61–90 days'},{key:'90+',label:'Over 90 days'},{key:'undated',label:'Undated dues'}];
 const accounts=[...new Map(villas.map(v=>[String(v.id),v])).values()],byVilla=new Map(accounts.map(v=>[String(v.id),[]]));
 for(const d of dues)byVilla.get(String(d.villa))?.push(d);
 const age=d=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(d.dueDate||''))return null;const [y,m,day]=d.dueDate.split('-').map(Number);return Math.floor((today-Date.UTC(y,m-1,day))/86400000)};
 const band=d=>{const days=age(d);return days===null?'undated':days<=0?'current':days<=30?'1-30':days<=60?'31-60':days<=90?'61-90':'90+'};
 const row=(v,items)=>{
  const balance=items.reduce((n,d)=>n+Math.max(0,cents(d.outstandingAmt)),0),overdue=items.reduce((n,d)=>n+(age(d)>0?Math.max(0,cents(d.outstandingAmt)):0),0);
  return {villa:String(v.id),name:v.name||'',month:'All dates',assessment:items.reduce((n,d)=>n+cents(d.dueAmt),0)/100,applied:items.reduce((n,d)=>n+cents(d.paidAmt),0)/100,balance:balance/100,overdue:overdue/100,dueItems:items.length,status:!items.length||items.every(d=>d.dueAmt==null)?'No dues loaded':overdue>0?'Overdue':balance>0?(items.some(d=>band(d)==='undated'&&cents(d.outstandingAmt)>0)?'Undated dues':'Not yet due'):'CLEARED'};
 };
 return {accounts:accounts.map(v=>row(v,byVilla.get(String(v.id)))),bands:bands.map(b=>{const rows=accounts.map(v=>row(v,byVilla.get(String(v.id)).filter(d=>cents(d.outstandingAmt)>0&&band(d)===b.key))).filter(r=>r.balance>0);return {...b,rows,amount:rows.reduce((n,r)=>n+cents(r.balance),0)/100};})};
};
let defaultersView='heatmap',defaultersLineMetric='count';
const DEFAULTERS_VIEWS={heatmap:'Villa heatmap',line:'Defaulters by month',ageing:'Ageing'};
function analyticsModels(){const dues=db.dues.map(d=>({...d,paidAmt:duePaid(d),outstandingAmt:dueOutstanding(d)}));return {trend:FernsAnalytics.accountTrend(db.villas,dues),ageing:FernsAnalytics.ageing(db.villas,dues)};}
function defaultersChart(){
 const {trend,ageing}=analyticsModels(),allKey='Analytics:defaulters:all-accounts';
 statDrills.set(allKey,{title:'All villa accounts · current balances',kind:'account-status',rows:ageing.accounts});
 const controls=`<div class="defaulters-controls"><div class="defaulters-switch" role="group" aria-label="Defaulters chart options">${Object.entries(DEFAULTERS_VIEWS).map(([key,label])=>`<button type="button" class="btn ${defaultersView===key?'primary':''}" data-defaulters-view="${key}" aria-pressed="${defaultersView===key}">${label}</button>`).join('')}</div><div class="defaulters-account-actions"><button type="button" class="text-btn" data-stat-drill="${allKey}">All accounts (${trend.accounts})</button>${window.FernsBankAccounts?.button()||''}</div></div>`;
 const body=defaultersView==='line'?defaultersLineChart(trend):defaultersView==='heatmap'?defaultersHeatmap(trend):defaultersAgeingChart(ageing);
 const detail=defaultersView==='ageing'?'All years · outstanding amounts by days past due':new Date().getFullYear()+' · current balances by due month';
 return `<section class="card defaulters-chart"><div class="card-head"><div><h2>${defaultersView==='line'?'Defaulters by month':'Defaulters trend'}</h2><p class="card-desc">${trend.accounts} villa accounts · ${detail}</p></div></div>${controls}${body}<p class="defaulters-note">${defaultersView==='ageing'?'Ageing uses all outstanding dues, including prior years. An account can appear in more than one band; each due balance appears in one band. Undated balances are shown separately.':'Counts and rates use today’s remaining balances by due month. Every master account is included; missing dues are flagged and multi-plot groups remain one account.'}${trend.orphanDues?` ${trend.orphanDues} due items have no matching villa account.`:''}</p></section>`;
}
function defaultersLineChart(model){
 const rate=defaultersLineMetric==='rate',maximum=rate?100:Math.max(1,model.accounts),points=[];
 const markers=model.buckets.map((bucket,index)=>{
  const rows=bucket.rows.filter(r=>r.status==='Overdue'),count=rows.length,percent=model.accounts?count/model.accounts*100:0,key=`Analytics:defaulters:line:${index}`;
  statDrills.set(key,{title:'Overdue accounts · '+bucket.label,kind:'account-status',rows});
  const x=82+index*90,y=146-(rate?percent:count)/maximum*126;if(!bucket.future)points.push(`${x},${y}`);
  return `<g class="defaulter-line-month" data-month="${bucket.period}">${bucket.future?'':`<g role="button" tabindex="0" data-stat-drill="${key}" data-count="${count}" data-rate="${percent.toFixed(1)}" aria-label="Overdue accounts · ${bucket.label}: ${count} (${percent.toFixed(1)}%)" data-trend-tooltip="${esc(bucket.label+'\nOverdue accounts: '+count+'\nRate: '+percent.toFixed(1)+'% of '+model.accounts+' accounts')}"><circle cx="${x}" cy="${y}" r="12" fill="transparent"/><circle cx="${x}" cy="${y}" r="5" fill="#d85b57"/></g>`}<text x="${x}" y="175" text-anchor="middle">${bucket.label.split(' ')[0]}${bucket.future?' · upcoming':''}</text></g>`;
 }).join('');
 return `<div class="defaulters-metric" role="group" aria-label="Line chart measure">${['count','rate'].map(metric=>`<button type="button" class="month-button ${defaultersLineMetric===metric?'selected':''}" data-defaulters-metric="${metric}" aria-pressed="${defaultersLineMetric===metric}">${metric==='count'?'Account count':'Defaulter rate (%)'}</button>`).join('')}</div><div class="chart"><svg viewBox="0 0 1140 190" role="group" aria-label="${rate?'Defaulter rate':'Defaulter count'} line chart">${[0,1,2,3].map(n=>`<text x="0" y="${24+n*42}">${rate?Math.round(100*(1-n/3))+'%':Math.round(maximum*(1-n/3))}</text><line x1="36" x2="1130" y1="${20+n*42}" y2="${20+n*42}" stroke="#8298aa55" stroke-dasharray="3 4"/>`).join('')}<polyline points="${points.join(' ')}" fill="none" stroke="#d85b57" stroke-width="3"/>${markers}</svg></div>`;
}
function defaultersHeatmap(model){
 const counts=new Map();for(const bucket of model.buckets)for(const row of bucket.rows)counts.set(row.villa,(counts.get(row.villa)||0)+row.defaultCount);
 const key='defaulters-heatmap',source=model.buckets[0].rows.map(({villa,name})=>({villa,name,defaultCount:counts.get(villa)||0})).sort((a,b)=>FernsGrid.compareVilla(a.villa,b.villa)),config={title:'Villa heatmap',sort:'defaultCount',direction:'desc',types:{villa:'villa',defaultCount:'number'}},rows=FernsGrid.rows(key,source,config);
 const label=status=>({'Overdue':'Overdue','CLEARED':'CLEARED','No dues loaded':'No dues','Not yet due':'Not due','Upcoming month':'Upcoming'}[status]);
 const byMonth=model.buckets.map(b=>new Map(b.rows.map(r=>[r.villa,r])));
 return `<div class="defaulters-heatmap-filters">${FernsGrid.panel(key,source,config)}</div><div class="table-wrap defaulters-heatmap"><table><thead><tr>${FernsGrid.header(key,'villa','Villa account')}${FernsGrid.header(key,'defaultCount','Defaulted dues')}${model.buckets.map(b=>`<th scope="col">${esc(b.label)}</th>`).join('')}</tr></thead><tbody>${rows.map(v=>`<tr><th scope="row">${esc(v.villa)}<small>${esc(v.name)}</small></th><td class="defaulter-count" title="Overdue due items with a remaining balance in the displayed year">${v.defaultCount}</td>${model.buckets.map((b,index)=>{const row=byMonth[index].get(v.villa),drillKey=`Analytics:defaulters:heatmap:${index}:${v.villa}`;statDrills.set(drillKey,{title:'Villa '+v.villa+' · '+b.label,kind:'account-status',rows:[row]});return `<td><button type="button" class="heatmap-cell" data-status="${row.status}" data-stat-drill="${esc(drillKey)}" aria-label="${esc('Villa '+v.villa+' · '+b.label+' · '+row.status)}" data-trend-tooltip="${esc('Villa '+v.villa+' · '+b.label+'\n'+row.status+'\nOutstanding: '+money(row.balance)+'\nOverdue: '+money(row.overdue))}">${row.status==='Overdue'?money(row.overdue):label(row.status)}</button></td>`;}).join('')}</tr>`).join('')}</tbody></table>${rows.length?'':'<div class="empty">No villa accounts match your search.</div>'}</div><p class="defaulters-note">Showing ${rows.length} of ${source.length} villa accounts · Defaulted dues counts overdue due items in the displayed year, including partially paid items. Select any month cell for details.</p>`;
}
function defaultersAgeingChart(model){
 const maximum=Math.max(1,...model.bands.map(b=>b.amount));
 return `<div class="chart defaulters-ageing"><svg viewBox="0 0 1140 280" role="group" aria-label="Outstanding dues ageing chart">${model.bands.map((band,index)=>{const key=`Analytics:defaulters:ageing:${band.key}`,y=18+index*42,width=band.amount/maximum*740;statDrills.set(key,{title:'Outstanding dues · '+band.label,kind:'account-status',rows:band.rows});return `<g role="button" tabindex="0" data-age-band="${band.key}" data-amount="${band.amount}" data-stat-drill="${key}" aria-label="${band.label}: ${money(band.amount)} across ${band.rows.length} accounts" data-trend-tooltip="${esc(band.label+'\nOutstanding: '+money(band.amount)+'\nVilla accounts: '+band.rows.length)}"><text x="0" y="${y+19}">${band.label}</text><rect x="138" y="${y}" width="740" height="29" fill="#8298aa15"/><rect x="138" y="${y}" width="${width}" height="29" rx="3" fill="${index===0?'#dca345':index===5?'#8298aa':'#d85b57'}"/><text x="895" y="${y+19}">${money(band.amount)} · ${band.rows.length} accounts</text></g>`;}).join('')}</svg></div>`;
}
if(typeof document!=='undefined')document.addEventListener('click',event=>{
 const target=event.target.closest('[data-defaulters-view],[data-defaulters-metric]');if(!target||!canOpenPage('Analytics'))return;
 if(target.dataset.defaultersView&&Object.hasOwn(DEFAULTERS_VIEWS,target.dataset.defaultersView))defaultersView=target.dataset.defaultersView;
 else if(['count','rate'].includes(target.dataset.defaultersMetric))defaultersLineMetric=target.dataset.defaultersMetric;else return;
 const attribute=target.hasAttribute('data-defaulters-view')?'data-defaulters-view':'data-defaulters-metric',value=target.getAttribute(attribute);
 withGridScroll(()=>{render();document.querySelector(`[${attribute}="${value}"]`)?.focus({preventScroll:true});});
});
