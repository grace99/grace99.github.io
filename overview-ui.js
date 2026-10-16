function renderOverviewStats(monthly){
 const period=FernsOverview.reportingMonth(),plots=FernsOverview.plots(db.villas),records=FernsOverview.records(db.dues,db.payments,monthly?period.key:null);
 const status=p=>String(p.resStatus||p.type||'').trim().toLowerCase();
 const construction=plots.filter(p=>status(p)==='under construction').length;
 const paid=records.payments.reduce((sum,p)=>sum+financialCents(p.PmtAmt),0)/100,outstanding=records.dues.reduce((sum,d)=>sum+financialCents(dueOutstanding(d)),0)/100;
 const issues=db.issues.filter(i=>!issueIsClosed(i));
 return `<div class="stats">${stat('Total villas',plots.length,`${construction} under construction`,'home',{kind:'plots',rows:plots,overview:monthly})}${stat('Payments received',money(paid),monthly?`${period.label} · receipt date`:'All receipt dates','wallet',{kind:'payments',rows:records.payments,overview:monthly,period:monthly?period.label:null})}${stat('Outstanding dues',money(outstanding),`${monthly?period.label+' · ':''}${new Set(records.dues.map(d=>d.villa)).size} villa accounts with unpaid dues`,'chart',{kind:'dues',rows:records.dues,overview:monthly,period:monthly?period.label:null})}${stat('Open issues',issues.length,`${issues.filter(i=>i.status==='In progress').length} in progress`,'tool',{kind:'issues',rows:issues})}</div>`;
}
function openStatDrill(key){
 const drill=statDrills.get(key);if(!drill)return;
 const gridKey='stat-drill';FernsGrid.states.delete(gridKey);
 const kinds={allocations:{columns:['payment_id','villa','dueTyp','dueDate','amount'],labels:{payment_id:'Payment ID',villa:'Villa',dueTyp:'Due type',dueDate:'Due date',amount:'Amount applied'},config:{title:'Payment allocations',date:'dueDate',sort:'dueDate',types:{payment_id:'number',villa:'villa',amount:'number',dueDate:'date'},fields:[{key:'villa',label:'Villa'},{key:'dueTyp',label:'Due type'}]}},plots:{columns:['plot','account','name','resStatus','area','street'],labels:{plot:'Villa plot',account:'Villa account',name:'Resident / owner',resStatus:'Residence status',area:'Area',street:'Street'},config:{title:'Villas',sort:'plot',types:{plot:'villa',account:'villa'},fields:[{key:'resStatus',label:'Residence status'},{key:'area',label:'Area'},{key:'street',label:'Street'}]}},issues:{columns:['id','title','category','severity','villa','location','status','reporter','reportedOn','detail'],labels:{id:'Issue ID',title:'Issue',category:'Category',severity:'Severity',villa:'Villa account',location:'Location',status:'Status',reporter:'Reported by',reportedOn:'Reported on',detail:'Description'},config:{title:'Open issues',sort:'title',date:'reportedOn',types:{id:'number',villa:'villa',reportedOn:'date'},fields:[{key:'category',label:'Category'},{key:'severity',label:'Severity'},{key:'status',label:'Status'},{key:'villa',label:'Villa account'}]}},dues:{columns:FINANCE_DUE_COLUMNS,labels:FINANCE_LABELS,config:financeGridConfig('dues')},payments:{columns:[...FINANCE_PAYMENT_COLUMNS,'available'],labels:{...FINANCE_LABELS,available:'Available balance'},config:{...financeGridConfig('payments'),date:'PmtDate',dateOptions:null,values:{}}}};
 const spec=kinds[drill.kind];let source=drill.kind==='payments'?drill.rows.map(p=>({...p,available:paymentAvailable(p)/100})):drill.rows;
 const monthly=drill.overview&&['payments','dues'].includes(drill.kind);
 if(drill.overview&&drill.kind==='plots'){
  spec.columns=['account','name','area','street','maintenance','outstanding'];spec.labels={account:'Villa account',name:'Resident / owner',area:'Total area sq ft',street:'Street',maintenance:'Monthly maintenance',outstanding:'Total outstanding balance'};
  spec.config={...spec.config,fields:spec.config.fields.filter(f=>f.key!=='resStatus'),sort:'account',types:{account:'villa',maintenance:'number',outstanding:'number'}};
  source=db.villas.map(v=>({...v,account:v.id,maintenance:v.due??0,outstanding:villaOutstanding(v.id)}));
 }
 if(drill.overview&&drill.kind==='payments'){
  spec.columns=FINANCE_PAYMENT_COLUMNS.filter(c=>!['id','PmtMthd','PmtRemarks','LatePmt','UTR','AllocationMonth','SplitFromPmtId','IsSplitParent'].includes(c));
  spec.config={...spec.config,hideDateRange:true,fields:spec.config.fields.filter(f=>['Villa','PaymentStatus'].includes(f.key))};source=activePayments();
 }
 if(drill.overview&&drill.kind==='dues'){
  spec.columns=['villa','dueDesc','dueAmt','dueDate','paidAmt','dueStatus','outstandingAmt'];spec.labels={...FINANCE_LABELS,outstandingAmt:'Outstanding due'};
  spec.config={...spec.config,hideDateRange:true};source=db.dues.filter(d=>dueOutstanding(d)>0).map(d=>({...d,paidAmt:duePaid(d),outstandingAmt:dueOutstanding(d)}));
 }
 if(monthly){const period=FernsOverview.reportingMonth(),state=FernsGrid.state(gridKey,spec.config);state.year=period.key.slice(0,4);state.months=[period.key.slice(5,7)];state.singleMonth=true;}
 document.querySelector('#modal-root').innerHTML=`<div class="modal-backdrop"><section class="modal stat-modal" role="dialog" aria-modal="true" aria-label="${esc(drill.title)} details"><header><h2>${esc(drill.title)}</h2>${drill.overview&&drill.kind==='plots'?'<span class="villa-assessment-note">Monthly dues assessed at <strong>₹1 per sq ft effective Jan 2026</strong>, as approved on 11 January 2026 GB meeting</span>':''}<button type="button" class="icon-btn" data-action="close" aria-label="Close dialog">${icon('close')}</button></header>${drill.period?`<p class="subtitle">${esc(drill.period)}</p>`:''}<div id="stat-drill-content"></div></section></div>`;
 const draw=()=>{if(monthly){const state=FernsGrid.state(gridKey);const label=state.months.length?state.months.map(m=>new Date(2026,Number(m)-1,1).toLocaleDateString(undefined,{month:'short'})+(state.year?' '+state.year:' · All years')).join(', '):(state.year?'Full year '+state.year:'All months · All years');document.querySelector('.stat-modal h2').textContent=drill.title+' · '+label;document.querySelector('.stat-modal .subtitle')?.remove();}const rows=FernsGrid.rows(gridKey,source,spec.config);document.querySelector('#stat-drill-content').innerHTML=FernsGrid.panel(gridKey,source,spec.config)+`<div class="table-wrap"><table><thead><tr>${spec.columns.map(c=>FernsGrid.header(gridKey,c,spec.labels[c])).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${spec.columns.map(c=>`<td>${['available','maintenance','outstanding'].includes(c)?money(row[c])+(c==='maintenance'&&Number(row[c])===0?` <span class="villa-hint" tabindex="0" role="img" data-villa-tooltip="Under construction" aria-label="Under construction">${icon('tool',19)}</span>`:''):['dues','payments','allocations'].includes(drill.kind)?financeCell(c,row[c]):esc(row[c]??'—')+(c==='account'&&String(row.resStatus||row.type||'').trim().toLowerCase()==='vacant'?` <span class="villa-hint" tabindex="0" role="img" data-villa-tooltip="Vacant" aria-label="Vacant">${icon('home',19)}</span>`:'')}</td>`).join('')}</tr>`).join('')}</tbody></table>${rows.length?'':'<div class="empty">No items match these filters.</div>'}</div><p class="table-footer">Showing ${rows.length} of ${source.length} items</p>`;};
 FernsGrid.callbacks.set(gridKey,draw);draw();document.querySelector('.stat-modal [data-action=close]').focus();
}
document.addEventListener('click',event=>{const button=event.target.closest('[data-stat-drill]');if(button)openStatDrill(button.dataset.statDrill);});

document.addEventListener('keydown',event=>{const bar=event.target.closest('svg [data-stat-drill]');if(bar&&['Enter',' '].includes(event.key)){event.preventDefault();openStatDrill(bar.dataset.statDrill);}});

window.FernsTrendTooltip=(()=>{
 let tooltip=null,anchor=null;const selector='[data-trend-tooltip],[data-villa-tooltip]';
 function hide(){anchor?.removeAttribute('aria-describedby');anchor=null;if(tooltip)tooltip.hidden=true;}
 function position(x,y){const box=tooltip.getBoundingClientRect();tooltip.style.left=Math.max(8,Math.min(x+12,innerWidth-box.width-8))+'px';tooltip.style.top=Math.max(8,Math.min(y+14,innerHeight-box.height-8))+'px';}
 function show(target,event){if(anchor!==target)hide();anchor=target;if(!tooltip){tooltip=document.createElement('div');tooltip.id='trend-amount-tooltip';tooltip.className='trend-amount-tooltip';tooltip.setAttribute('role','tooltip');document.body.append(tooltip);}tooltip.textContent=target.dataset.trendTooltip||target.dataset.villaTooltip;tooltip.hidden=false;target.setAttribute('aria-describedby',tooltip.id);const rect=target.getBoundingClientRect();position(event.clientX??rect.left+rect.width/2,event.clientY??rect.bottom);}
 document.addEventListener('pointerover',event=>{const target=event.target.closest(selector);if(target)show(target,event);});
 document.addEventListener('pointermove',event=>{if(anchor&&event.target.closest(selector)===anchor)position(event.clientX,event.clientY);});
 document.addEventListener('pointerout',event=>{if(event.target.closest(selector)&&!event.relatedTarget?.closest?.(selector))hide();});
 document.addEventListener('focusin',event=>{const target=event.target.closest(selector);if(target)show(target,event);else hide();});
 document.addEventListener('focusout',event=>{if(event.target.closest(selector))hide();});
 document.addEventListener('click',hide);document.addEventListener('keydown',event=>{if(event.key==='Escape')hide();});window.addEventListener('scroll',hide,true);
 return {hide};
})();
