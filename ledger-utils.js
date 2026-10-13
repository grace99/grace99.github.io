/* Shared financial helpers: exact cents and permanent text villa identifiers. */
window.FernsLedger = {
  cents(value) {
    const text=String(value??'').trim();
    if(!/^\d+(?:\.\d{1,2})?$/.test(text))throw Error('Enter a non-negative amount with at most two decimal places.');
    const [whole,fraction='']=text.split('.');const result=Number(whole)*100+Number(fraction.padEnd(2,'0'));
    if(!Number.isSafeInteger(result))throw Error('Amount exceeds the supported range.');return result;
  },
  validateSplit(total,allocations){
    if(!Array.isArray(allocations)||allocations.length<2||allocations.length>120)throw Error('Enter between 2 and 120 monthly allocations.');
    const months=new Set();let sum=0;const result=allocations.map(part=>{
      if(!/^(?!0000)\d{4}-(0[1-9]|1[0-2])$/.test(part.month))throw Error('Choose a valid month for each allocation.');
      if(months.has(part.month))throw Error('Use one allocation per month.');months.add(part.month);
      const cents=this.cents(part.amount);if(cents<=0)throw Error('Every allocation must be greater than zero.');sum+=cents;
      return {month:part.month,amount:(cents/100).toFixed(2)};
    });if(sum!==this.cents(total))throw Error('Allocated amounts must equal the original payment amount.');return result;
  },
  monthlyPreview(villas,existing,{period,villaField,periodField}) {
    if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(period))throw Error('Choose a valid billing month.');
    const duplicateVillas=new Set(existing.filter(due=>String(due[periodField]??'').slice(0,7)===period).map(due=>String(due[villaField])));
    const seen=new Set();return villas.map(villa=>{
      if(seen.has(villa.id))throw Error('Duplicate villa number in master data.');seen.add(villa.id);
      const amount=this.cents(villa.due??0);
      return {villa:villa.id,name:villa.name,amount:amount/100,skip:duplicateVillas.has(villa.id)||amount===0,reason:duplicateVillas.has(villa.id)?'Already billed':amount===0?'No maintenance amount':''};
    });
  },
  availablePayment(payment,dues,{paymentKey,duePayment,dueAmount,dueStatus,paymentAmount}) {
    const used=dues.filter(due=>due[duePayment]!=null&&String(due[duePayment])===String(payment[paymentKey])).reduce((sum,due)=>sum+this.cents(due[dueAmount]??0),0);
    return this.cents(payment[paymentAmount]??0)-used;
  }
};
