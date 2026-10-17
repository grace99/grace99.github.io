/* Keep a tab's view across refresh, after membership and fresh data are loaded. */
window.FernsViewState=(()=>{
 if('scrollRestoration' in history)history.scrollRestoration='manual';
 const key='ferns-tab-view-v1',ephemeral=new Set(['stat-drill','payment-matching','monthly-preview']);
 let pending=null,restoring=false,applied=false;
 try{const saved=JSON.parse(sessionStorage.getItem(key));if(saved&&saved.version===1&&typeof saved.page==='string'&&Array.isArray(saved.grids)&&Array.isArray(saved.scroll?.positions))pending=saved;}catch{}
 function clear(){pending=null;applied=false;FernsGrid.states.clear();duesView='items';communityIssueView='Issue';defaultersView='stacked';defaultersLineMetric='count';try{sessionStorage.removeItem(key)}catch{}}
 function beforeRender(){
  if(!pending||applied||(cloud.configured&&!cloudReady))return;
  if(pending.owner!==(cloud.user()?.id||'local')){clear();return;}
  if(![...nav.map(item=>item[0]),'Admin center'].includes(pending.page)||!canOpenPage(pending.page)){clear();page='Overview';return;}
  page=pending.page;applied=true;
  for(const entry of pending.grids){if(!Array.isArray(entry)||entry.length!==2)continue;const [id,state]=entry;if(typeof id!=='string'||ephemeral.has(id)||!state||typeof state!=='object')continue;
   const restored={};for(const prop of ['search','year','from','to','sort','dateField'])if(typeof state[prop]==='string')restored[prop]=state[prop];
   restored.direction=state.direction==='desc'?'desc':'asc';restored.months=Array.isArray(state.months)?state.months.filter(m=>/^(0[1-9]|1[0-2])$/.test(m)):[];
   for(const prop of ['values','defaultValues'])restored[prop]=state[prop]&&typeof state[prop]==='object'?Object.fromEntries(Object.entries(state[prop]).filter(([,v])=>typeof v==='string')):{};
   restored.columnsOpen=false;FernsGrid.states.set(id,restored);
  }
  if(['items','balances'].includes(pending.duesView))duesView=pending.duesView;
  if(['stacked','line','heatmap','ageing'].includes(pending.defaultersView))defaultersView=pending.defaultersView;
  if(['count','rate'].includes(pending.defaultersLineMetric))defaultersLineMetric=pending.defaultersLineMetric;
  if(['Issue','Preventive maintenance'].includes(pending.issueView))communityIssueView=pending.issueView;
 }
 function afterRender(){
  if(!pending||!applied||restoring||page!==pending.page)return;
  restoring=true;
  // Admin rows arrive after the initial page render; keep the snapshot until loaded.
  const table=document.querySelector('.main .table-wrap');
  if(page==='Admin center'&&table&&!table.querySelector('tbody tr')&&document.querySelector('[data-admin-refresh]')?.disabled){restoring=false;return;}
  const saved=pending;pending=null;
  try{const positions=saved.scroll.positions.filter(entry=>Array.isArray(entry)&&typeof entry[0]==='string'&&Number.isFinite(entry[1]?.top)&&Number.isFinite(entry[1]?.left));const point=saved.scroll.pagePosition;captureGridScroll(document,{positions,pagePosition:point&&Number.isFinite(point.x)&&Number.isFinite(point.y)?point:{x:0,y:0}})();}finally{restoring=false;}
 }
 function save(){
  if(restoring||pending||(cloud.configured&&(!cloudReady||!cloud.hasSession()))||document.querySelector('.main')?.dataset.view!==page)return;
  try{const app=document.querySelector('#app'),snapshot=captureGridScroll(app).snapshot;
   // Dialogs and unsaved form contents are intentionally excluded.
   snapshot.pagePosition={x:window.scrollX,y:window.scrollY};
   sessionStorage.setItem(key,JSON.stringify({version:1,owner:cloud.user()?.id||'local',page,grids:[...FernsGrid.states].filter(([id])=>!ephemeral.has(id)),scroll:snapshot,duesView,issueView:communityIssueView,defaultersView,defaultersLineMetric}));
  }catch{}
 }
 window.addEventListener('pagehide',save);
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')save();});
 return {beforeRender,afterRender,save,clear};
})();
