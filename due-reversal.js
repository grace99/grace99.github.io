function openDueReversal(index){
 const due=db.dues[Number(index)];
 if(!due||due.dueStatus!=='Cleared'){toast('This due is no longer cleared. Refresh and retry.');return}
 const payment=db.payments.find(p=>due.PmtId!=null&&String(p.id)===String(due.PmtId));
 financeDialog('Revert cleared due',`<div class="split-receipt"><strong>Villa ${esc(due.villa)} · ${esc(due.dueTyp)}</strong><p>${financeCell('dueDate',due.dueDate)} · ${money(due.dueAmt)}</p>${due.PmtId!=null?`<p>Payment ID: ${esc(due.PmtId)}</p>`:''}</div><p class="subtitle">This will return the due to Unpaid and remove its payment link.${due.PmtId!=null?' The amount will become available on the linked payment again. Other dues linked to that payment will remain cleared.':''}</p><p class="subtitle">The payment receipt and its original transaction information will be retained.${payment?.SplitFromPmtId!=null?' This releases credit to the split transaction; it does not undo the receipt split.':''}</p>`,'Revert allocation',async()=>{
  const result=await cloud.finance.revertDue(due);
  if(!result?.due||!['Unpaid','NIL'].includes(result.due.dueStatus)||result.due.PmtId!=null)throw Error('Unexpected reversal result. Refresh to verify the due.');
  const i=db.dues.indexOf(due);if(i>=0)db.dues[i]=result.due;
  if(result.payment){const p=db.payments.findIndex(p=>String(p.id)===String(result.payment.id));if(p>=0)db.payments[p]=result.payment;}
  // Reload all allocations so payment balances include concurrent changes to other dues.
  try{await refreshFinancial()}catch(error){return 'Allocation reverted. Refresh to reload all payment balances.';}
  return result.already_reverted?'Due is already Unpaid. Grids refreshed.':'Allocation reverted. Due is Unpaid and payment credit restored.';
 });
}
