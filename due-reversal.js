function openDueReversal(index){
 const due=db.dues[Number(index)];
 if(!due||duePaid(due)<=0){toast('This due has no applied payments. Refresh and retry.');return}
 const payment=db.payments.find(p=>due.PmtId!=null&&String(p.id)===String(due.PmtId));
 financeDialog('Revert applied payments',`<div class="split-receipt"><strong>Villa ${esc(due.villa)} · ${esc(due.dueTyp)}</strong><p>${financeCell('dueDate',due.dueDate)} · Due ${money(due.dueAmt)} · Applied ${money(duePaid(due))} · Outstanding ${money(dueOutstanding(due))}</p><p>${dueAllocations(due).map(a=>`Payment ${esc(a.payment_id)}: ${money(a.amount)}`).join(' · ')}</p></div><p class="subtitle">This will reverse ALL payments applied to this due, restore the full outstanding amount, and return the released credit to each receipt.${due.PmtId!=null?' The amount will become available on the linked payment again. Other due allocations remain unchanged.':''}</p><p class="subtitle">The payment receipt and its original transaction information will be retained.${payment?.SplitFromPmtId!=null?' This releases credit to the split transaction; it does not undo the receipt split.':''}</p>`,'Revert all allocations',async()=>{
  const result=await cloud.finance.revertDue(due);
  if(!result?.due||!['Unpaid','NIL'].includes(result.due.dueStatus)||result.due.PmtId!=null)throw Error('Unexpected reversal result. Refresh to verify the due.');
  const i=db.dues.indexOf(due);if(i>=0)db.dues[i]=result.due;
  for(const pay of result.payments||[]){const j=db.payments.findIndex(p=>String(p.id)===String(pay.id));if(j>=0)db.payments[j]=pay;}
  if(result.payment){const p=db.payments.findIndex(p=>String(p.id)===String(result.payment.id));if(p>=0)db.payments[p]=result.payment;}
  // Reload all allocations so payment balances include concurrent changes to other dues.
  try{await refreshFinancial()}catch(error){return 'Allocation reverted. Refresh to reload all payment balances.';}
  return result.already_reverted?'Due is already Unpaid. Grids refreshed.':'Allocation reverted. Due is Unpaid and payment credit restored.';
 });
}
