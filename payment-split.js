function openPaymentSplit(id){
 const payment=db.payments.find(p=>String(p.id)===String(id));
 if(!payment||payment.IsSplitParent||payment.SplitFromPmtId!=null){toast('Choose an original, unsplit payment.');return}
 if(db.dues.some(d=>d.PmtId!=null&&String(d.PmtId)===String(payment.id))){toast('Payments already applied to dues cannot be split.');return}
 const originalCents=financialCents(payment.PmtAmt);let rows=[{month:(payment.AllocationMonth||payment.PmtDate||new Date().toLocaleDateString('en-CA')).slice(0,7),amount:''},{month:'',amount:''}];
 financeDialog('Split payment',`<div class="split-receipt"><strong>Payment ${esc(payment.id)} · Villa ${esc(payment.Villa)}</strong><p>Original amount: ${money(payment.PmtAmt)}</p><p>${esc(financeCell('PmtDate',payment.PmtDate))} · ${esc(payment.PmtMthd||'')} · ${esc(payment.UTR||'No transaction reference')}</p></div><p class="subtitle">Assign the full amount to at least two different months. New payment IDs will keep the same receipt date, account, method, purpose, UTR, remarks and late-payment flag.</p><div id="split-rows"></div><button type="button" class="btn" id="add-split-row">+ Add month</button><div id="split-totals" role="status"></div><p class="subtitle">The original is retained as a split receipt and excluded from balances. New transactions can be applied to dues separately.</p>`,'Create split payments',async()=>{
  const allocations=FernsLedger.validateSplit(payment.PmtAmt,rows);const result=await cloud.finance.splitPayment(payment,allocations);
  if(!result?.original||!Array.isArray(result.payments)||result.payments.length<2)throw Error('Unexpected split result. Refresh and check this receipt before retrying.');
  const originalIndex=db.payments.findIndex(p=>String(p.id)===String(payment.id));db.payments[originalIndex]=result.original;
  for(const child of result.payments){const index=db.payments.findIndex(p=>String(p.id)===String(child.id));if(index>=0)db.payments[index]=child;else db.payments.unshift(child);}
  return `${result.already_split?'Existing split restored':'Split created'}: payment IDs ${result.payments.map(p=>p.id).join(', ')}.`;
 });
 const form=document.querySelector('#finance-form');
 const totals=()=>{let sum=0,invalid=false;for(const row of rows){try{sum+=financialCents(row.amount||0)}catch{invalid=true}}
  form.querySelector('#split-totals').innerHTML=`<span>Allocated <strong>${money(sum/100)}</strong></span><span>${sum>originalCents?'Over by':'Remaining'} <strong>${money(Math.abs(originalCents-sum)/100)}</strong></span>`;
  let valid=true,message='';try{FernsLedger.validateSplit(payment.PmtAmt,rows)}catch(error){valid=false;message=error.message}form.querySelector('.finance-error').textContent=rows.every(row=>row.amount)?message:'';form.querySelector('[type=submit]').disabled=!valid||invalid||cloudBusy;
 };
 const renderRows=()=>{form.querySelector('#split-rows').innerHTML=rows.map((row,index)=>`<div class="split-row"><label>Billing month<input type="month" data-split-month="${index}" value="${esc(row.month)}" required></label><label>Amount (₹)<input type="number" min="0.01" step="0.01" data-split-amount="${index}" value="${esc(row.amount)}" required></label><button type="button" class="icon-btn" data-remove-split="${index}" aria-label="Remove allocation ${index+1}" ${rows.length<=2?'disabled':''}>${icon('close')}</button></div>`).join('');totals();};
 form.querySelector('#add-split-row').onclick=()=>{if(rows.length>=120){toast('Maximum 120 allocations.');return}rows.push({month:'',amount:''});renderRows();};
 form.addEventListener('input',event=>{const input=event.target;if(input.hasAttribute('data-split-month'))rows[Number(input.dataset.splitMonth)].month=input.value;else if(input.hasAttribute('data-split-amount'))rows[Number(input.dataset.splitAmount)].amount=input.value;else return;form.querySelector('.finance-error').textContent='';totals();});
 form.addEventListener('click',event=>{const button=event.target.closest('[data-remove-split]');if(button&&rows.length>2){rows.splice(Number(button.dataset.removeSplit),1);renderRows();}});renderRows();
}
