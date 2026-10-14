window.FernsOverview={
 reportingMonth(now=new Date()){
  const date=new Date(now.getFullYear(),now.getMonth()-(now.getDate()<=10?1:0),1);
  return {key:`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}`,label:date.toLocaleDateString(undefined,{month:'short',year:'numeric'})};
 },
 plots(villas){return villas.flatMap(v=>{const id=String(v.id);const parts=/^\d+(?:-\d+)+$/.test(id)?id.split('-'):[id];return parts.map(plot=>({...v,plot,account:id}));});},
 records(dues,payments,period){return {payments:payments.filter(p=>!p.IsSplitParent&&(!period||p.PmtDate?.slice(0,7)===period)),dues:dues.filter(d=>(!period||d.dueDate?.slice(0,7)===period)&&d.dueStatus!=='Cleared'&&Number(d.dueAmt)>0)};}
};
