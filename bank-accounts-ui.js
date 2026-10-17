/* Read-only, on-demand bank reference view. Does not enter shared association JSON. */
window.FernsBankAccounts=(()=>{
 const key='villa-bank-accounts',storageKey='ferns-bank-reference-columns-v1';
 const labels={id:'Reference ID',villa:'Villa account',account_num:'Account number',bank_name:'Bank',account_type:'Account type',observed_forms:'Observed account forms',observations:'Payment observations',months_observed:'Months observed',months:'Observed months',first_seen:'First seen',last_seen:'Last seen',payment_methods:'Payment methods',full_number_observations:'Full-number observations',suffix_linked_observations:'Suffix-linked observations',source_references:'Source references',notes:'Notes',bank_name_basis:'Bank identification basis',bank_source_reference:'Bank source reference',bank_source_files:'Bank source files',window_start:'Observation window start',window_end:'Observation window end',is_suggested:'Reference status',created_at:'Created on',updated_at:'Updated on'};
 const defaults=['villa','account_num','bank_name','account_type','observations','months_observed','last_seen','is_suggested'];
 const numbers=['id','observations','months_observed','full_number_observations','suffix_linked_observations'],dates=['first_seen','last_seen','window_start','window_end'];
 let records=[],expanded=null,loaded=false,busy=false,error='',owner=null,generation=0,selected=defaults.slice();
 try{const saved=JSON.parse(localStorage.getItem(storageKey));if(Array.isArray(saved))selected=saved.filter(c=>Object.hasOwn(labels,c));}catch{}
 const allowed=()=>cloudReady&&cloud.hasSession()&&cloud.canEdit();
 const columns=()=>Object.keys(labels).filter(c=>c==='villa'||selected.includes(c));
 const rows=()=>records.map(record=>Object.fromEntries(Object.entries(record).map(([column,value])=>[column,Array.isArray(value)?value.join(', '):value])));
 function config(){return {title:'Villa bank accounts',date:FernsGrid.states.get(key)?.dateField||'last_seen',dateOptions:[{key:'last_seen',label:'Last seen'},{key:'first_seen',label:'First seen'}],sort:'villa',types:{villa:'villa',...Object.fromEntries(numbers.map(c=>[c,'number'])),...Object.fromEntries(dates.map(c=>[c,'date']))},fields:[{key:'bank_name',label:'Bank'},{key:'account_type',label:'Account type'},{key:'is_suggested',label:'Reference status',labels:{true:'Suggested',false:'Observed'}}]};}
 function value(column,raw){
  if(raw===null||raw===undefined||raw==='')return '—';
  if(column==='is_suggested')return `<span class="badge ${raw===true?'amber':'green'}">${raw===true?'Suggested':'Observed'}</span>`;
  if(column==='account_type')return `<span class="badge ${raw==='Masked'?'amber':'gray'}">${esc(raw)}</span>`;
  if(dates.includes(column)&&/^\d{4}-\d{2}-\d{2}$/.test(raw))return esc(raw.split('-').reverse().join('/'));
  if(['created_at','updated_at'].includes(column)){const date=new Date(raw);return esc(Number.isNaN(date.getTime())?raw:date.toLocaleString());}
  return esc(Array.isArray(raw)?raw.join(', '):raw);
 }
 function clear(){generation++;records=[];expanded=null;loaded=false;busy=false;error='';owner=null;FernsGrid.states.delete(key);document.querySelector('[data-bank-reference-modal]')?.closest('.modal-backdrop')?.remove();}
 async function load(){
  if(!allowed()||busy)return;
  const identity=cloud.user()?.id,token=++generation;owner=identity;busy=true;error='';draw();
  try{const result=await cloud.bankAccounts();if(token!==generation||!allowed()||cloud.user()?.id!==identity)return;records=result;loaded=true;}
  catch(e){if(token===generation&&allowed()&&cloud.user()?.id===identity)error=e.message;}
  finally{if(token===generation){busy=false;if(document.querySelector('[data-bank-reference-modal]'))draw();}}
 }
 function picker(){const visible=columns(),isOpen=FernsGrid.state(key).columnsOpen;return `<details class="column-picker" data-bank-picker ${isOpen?'open':''}><summary class="grid-action" title="Choose bank reference columns">${icon('grid',14)} Columns</summary><div class="column-picker-panel" role="group" aria-label="Bank reference columns">${Object.entries(labels).map(([column,label])=>`<label><input type="checkbox" data-bank-column="${column}" ${visible.includes(column)?'checked':''} ${column==='villa'?'disabled':''}>${label}</label>`).join('')}<button type="button" class="grid-action" data-bank-reset-columns>Reset columns</button></div></details>`;}
 function content(){
  const source=rows(),visible=FernsGrid.rows(key,source,config()),cols=columns(),accounts=new Set(records.map(r=>r.villa)).size;
  const errorHtml=error?`<div class="bank-reference-error" role="alert">${esc(error)} <span>Check membership and SELECT access for villa_account_reference. The supplied SQL 019 sets up manager read access.</span></div>`:'';
  return `${errorHtml}${FernsGrid.panel(key,source,config())}<div class="card-head table-head"><span class="card-desc">${records.length} references · ${accounts} of ${new Set(db.villas.map(v=>v.id)).size} villa accounts represented${busy?' · Loading…':''}</span>${picker()}</div><div class="table-wrap"><table class="bank-reference-table"><thead><tr>${cols.map(c=>FernsGrid.header(key,c,labels[c])).join('')}<th>Details</th></tr></thead><tbody>${visible.map(row=>`<tr>${cols.map(c=>`<td>${value(c,row[c])}</td>`).join('')}<td><button type="button" class="icon-btn grid-action" data-bank-detail="${esc(row.id)}" aria-label="View bank reference ${esc(row.id)} details" aria-expanded="${expanded===String(row.id)}" title="View observation evidence and source details">${icon('search',18)}</button></td></tr>${expanded===String(row.id)?`<tr class="bank-evidence-row"><td colspan="${cols.length+1}"><dl class="bank-evidence">${Object.entries(labels).map(([column,label])=>`<div><dt>${label}</dt><dd>${value(column,row[column])}</dd></div>`).join('')}</dl></td></tr>`:''}`).join('')}</tbody></table>${visible.length?'':`<div class="empty">${busy?'Loading bank references…':error?'Bank references could not be loaded.':loaded?'No bank references match these filters.':'Loading bank references…'}</div>`}</div><div class="table-footer">Showing ${visible.length} of ${source.length} bank references</div>`;
 }
 function draw(){
  if(!allowed()||!document.querySelector('[data-bank-reference-modal]'))return;
  withGridScroll(()=>{document.querySelector('#bank-reference-content').innerHTML=content();document.querySelector('[data-bank-refresh]').disabled=busy;});
 }
 function show(){
  if(!allowed())return;
  if(owner&&owner!==cloud.user()?.id)clear();
  document.querySelector('#modal-root').innerHTML=`<div class="modal-backdrop"><section class="modal bank-reference-modal" role="dialog" aria-modal="true" aria-label="Villa bank accounts" data-bank-reference-modal><header><h2>Villa bank accounts</h2><div class="actions"><button type="button" class="btn" data-bank-refresh>Refresh</button><button type="button" class="icon-btn" data-action="close" aria-label="Close dialog">${icon('close')}</button></div></header><div id="bank-reference-content"></div></section></div>`;
  FernsGrid.callbacks.set(key,draw);draw();document.querySelector('[data-bank-reference-modal] [data-action=close]').focus({preventScroll:true});
  if(!loaded&&!busy)load();
 }
 function mount(){if(!allowed()){if(owner||loaded||busy||records.length)clear();return;}if(owner&&owner!==cloud.user()?.id)clear();}
 function persistColumns(){try{localStorage.setItem(storageKey,JSON.stringify(selected))}catch{}}
 document.addEventListener('click',event=>{
  const target=event.target.closest('[data-bank-open],[data-bank-refresh],[data-bank-detail],[data-bank-reset-columns]');if(!target||!allowed())return;
  if(target.hasAttribute('data-bank-open'))show();
  else if(target.hasAttribute('data-bank-refresh'))load();
  else if(target.hasAttribute('data-bank-detail')){expanded=expanded===target.dataset.bankDetail?null:target.dataset.bankDetail;draw();}
  else withGridScroll(()=>{selected=defaults.slice();persistColumns();FernsGrid.state(key).columnsOpen=true;draw();document.querySelector('[data-bank-reset-columns]')?.focus({preventScroll:true});});
 });
 document.addEventListener('change',event=>{const target=event.target;if(!target.matches('[data-bank-column]')||!allowed())return;withGridScroll(()=>{const choice=target.dataset.bankColumn;if(target.checked)selected=[...new Set([...selected,choice])];else selected=selected.filter(c=>c!==choice);persistColumns();FernsGrid.state(key).columnsOpen=true;draw();document.querySelector(`[data-bank-column="${choice}"]`)?.focus({preventScroll:true});});});
 document.addEventListener('toggle',event=>{if(event.target.matches('[data-bank-picker]'))FernsGrid.state(key).columnsOpen=event.target.open;},true);
 document.addEventListener('keydown',event=>{if(event.key!=='Escape')return;const picker=document.querySelector('[data-bank-picker][open]');if(picker){event.stopImmediatePropagation();picker.removeAttribute('open');FernsGrid.state(key).columnsOpen=false;picker.querySelector('summary').focus({preventScroll:true});}},true);
 return {mount,clear,button:()=>allowed()?'<button type="button" class="text-btn" data-bank-open>Villa bank accounts</button>':''};
})();
