/* Read-only administrator feed. Capture and access rules live in migration 014. */
window.FernsAdmin=(()=>{
 let events=[],loaded=false,busy=false,error='',hasMore=false,owner=null,tab='All';
 const entityLabels={community_issues:'Community issues',VillaPmt:'Payments',villaDues:'Dues',villaMaster:'Villa directory',villaPaymentAllocations:'Payment allocations',villaBalances:'Villa balances',fernsvilla_state:'Association content',fernsvilla_members:'Membership',fernsvilla_registrations:'Registrations'};
 const actionLabels={INSERT:'Created',UPDATE:'Modified',DELETE:'Deleted',TRUNCATE:'Table cleared',SIGN_IN:'Signed in',MONTHLY_LOAD:'Monthly dues load',SNAPSHOT:'Snapshot'};
 const allowed=()=>cloudReady&&cloud.hasSession()&&cloud.role()==='admin';
 function clear(){document.querySelector('[data-admin-event]')?.closest('.modal-backdrop')?.remove();events=[];loaded=false;busy=false;error='';hasMore=false;owner=null;tab='All';FernsGrid.states.delete('admin-feed');}
 function localDay(value){const d=new Date(value);return Number.isNaN(d.getTime())?'':`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;}
 function rows(){return events.map(e=>({...e,entityLabel:entityLabels[e.entity]||e.entity,action:actionLabels[e.event_type]||e.event_type,actor:e.actor_email||e.actor_id||e.database_user||'Database',operation:e.metadata?.operation||'',date:localDay(e.occurred_at),summary:e.event_type==='MONTHLY_LOAD'?`${e.metadata?.billing_date||''} · ${e.metadata?.inserted??0} created · ${e.metadata?.skipped??0} skipped`:e.metadata?.installation?e.metadata.description:e.record_key||'—'})).filter(e=>tab==='All'||(tab==='Sign-ins'?e.event_type==='SIGN_IN':tab==='Database changes'?e.source==='Database':e.event_type!=='SIGN_IN'));}
 const config={title:'Admin activity',date:'date',sort:'occurred_at',direction:'desc',fields:[{key:'entityLabel',label:'Area'},{key:'action',label:'Action'},{key:'source',label:'Source'},{key:'actor',label:'User / database role'},{key:'villa',label:'Villa'}],types:{id:'number',villa:'villa',occurred_at:'date'}};
 async function load(older=false){
  if(!allowed()||busy)return;
  const identity=cloud.user()?.id;owner=identity;busy=true;error='';render();
  try{const result=await cloud.adminFeed(older?{id:events.at(-1)?.id,occurred_at:events.at(-1)?.occurred_at}:null);if(!allowed()||cloud.user()?.id!==identity)return;
   events=older?[...events,...result.events]:result.events;hasMore=result.hasMore;loaded=true;
  }catch(e){if(allowed()&&cloud.user()?.id===identity)error=e.message;}
  finally{if(owner===identity){busy=false;if(page==='Admin center')render();}}
 }
 function pageContent(){
  if(!allowed())return heading('Admin center','')+'<div class="card empty">Sign in with administrator access to view the activity feed.</div>';
  const source=rows(),visible=FernsGrid.rows('admin-feed',source,config);
  const columns=[['occurred_at','Time'],['actor','User / database role'],['action','Action'],['entityLabel','Area'],['villa','Villa'],['summary','Record / summary'],['source','Source'],['transaction_id','Transaction ID']];
  return heading('Admin center','',`<button type="button" class="btn" data-admin-refresh ${busy?'disabled':''} title="Reload the newest audit events">${icon('chart',15)} Refresh feed</button>`)+(window.FernsSignup?.panel()||'')+
   `<div class="actions admin-tabs">${['All','Sign-ins','Activities','Database changes'].map(t=>`<button type="button" class="btn ${tab===t?'primary':''}" data-admin-tab="${t}" aria-pressed="${tab===t}">${t}</button>`).join('')}</div>`+
   '<p class="admin-note">Filters apply to loaded events. Load older events for more history. Times use your local timezone.</p>'+FernsGrid.panel('admin-feed',source,config)+
   (error?`<div class="card admin-error" role="alert"><p>${esc(error)}</p><p>If audit capture is not installed, run <a href="supabase/014_admin_center.sql" target="_blank" rel="noopener">migration 014</a> after 013, then refresh the feed.</p></div>`:'')+
   `<div class="card"><div class="card-head table-head"><h2>Activity feed</h2><span class="card-desc">${events.length} loaded events${busy?' · Loading…':''}</span></div><div class="table-wrap"><table class="admin-table"><thead><tr>${columns.map(([c,label])=>FernsGrid.header('admin-feed',c,label)).join('')}<th>Details</th></tr></thead><tbody>${visible.map(e=>`<tr>${columns.map(([c])=>`<td>${c==='occurred_at'?esc(new Date(e[c]).toLocaleString()):esc(e[c]??'—')}${c==='action'&&e.operation?`<small class="audit-operation">${esc(e.operation)}</small>`:''}</td>`).join('')}<td><button type="button" class="grid-action row-action" data-admin-detail="${esc(e.id)}" title="View event details and before/after values" aria-label="View event ${esc(e.id)} details">${icon('search',16)}</button></td></tr>`).join('')}</tbody></table>${visible.length?'':`<div class="empty">${busy?'Loading activity…':loaded?'No events match these filters.':'Refresh the feed to load activity.'}</div>`}</div><div class="table-footer"><span>Showing ${visible.length} of ${source.length} loaded events in this view</span>${hasMore?`<button type="button" class="grid-action" data-admin-older ${busy?'disabled':''}>Load older events</button>`:''}</div></div>`;
 }
 function detail(id){if(!allowed())return;const event=events.find(e=>String(e.id)===id);if(!event)return;
  const old=event.old_record||{},next=event.new_record||{},keys=[...new Set([...Object.keys(old),...Object.keys(next)])];
  const format=value=>value===undefined?'—':typeof value==='object'?JSON.stringify(value,null,2):String(value);
  const fields=keys.filter(k=>event.event_type!=='UPDATE'||JSON.stringify(old[k])!==JSON.stringify(next[k]));
  document.querySelector('#modal-root').innerHTML=`<div class="modal-backdrop"><section class="modal stat-modal" role="dialog" aria-modal="true" aria-label="Audit event details" data-admin-event><header><h2>${esc(actionLabels[event.event_type]||event.event_type)} · ${esc(entityLabels[event.entity]||event.entity)}</h2><button type="button" class="icon-btn" data-action="close" aria-label="Close dialog">${icon('close')}</button></header><p class="subtitle">${esc(new Date(event.occurred_at).toLocaleString())} · ${esc(event.actor_email||event.actor_id||event.database_user)} · ${esc(event.source)} · Transaction ${esc(event.transaction_id)}</p>${event.metadata?.historical?'<p class="admin-note">Imported from retained financial history.</p>':''}${fields.length?`<div class="table-wrap"><table class="audit-values"><thead><tr><th>Field</th><th>Before</th><th>After</th></tr></thead><tbody>${fields.map(k=>`<tr><th scope="row">${esc(FINANCE_LABELS[k]||k)}</th><td><pre>${esc(format(old[k]))}</pre></td><td><pre>${esc(format(next[k]))}</pre></td></tr>`).join('')}</tbody></table></div>`:''}<h3 class="audit-meta-title">Event information</h3><pre class="audit-metadata">${esc(JSON.stringify({event_id:event.id,user_id:event.actor_id,database_role:event.database_user,record:event.record_key,...event.metadata},null,2))}</pre></section></div>`;
  document.querySelector('.stat-modal [data-action=close]').focus();
 }
 document.addEventListener('click',event=>{const target=event.target.closest('[data-admin-refresh],[data-admin-older],[data-admin-tab],[data-admin-detail]');if(!target||!allowed())return;
  if(target.hasAttribute('data-admin-refresh'))load();else if(target.hasAttribute('data-admin-older'))load(true);else if(target.dataset.adminTab){tab=target.dataset.adminTab;render();}else detail(target.dataset.adminDetail);
 });
 return {page:pageContent,mount(){if(!allowed()){clear();return;}if(owner&&owner!==cloud.user()?.id)clear();if(page==='Admin center'&&!loaded&&!busy&&!error)load();}};
})();
