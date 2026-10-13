const {test}=require('node:test');const assert=require('node:assert/strict');const vm=require('node:vm');const fs=require('node:fs');const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../villa-directory.js'),'utf8');
const columns={key:'row_id',id:'villa_no',name:'resident',type:'occupancy',phone:'contact',due:'assessment'};
const row={row_id:'uuid-1',villa_no:'FV-001',resident:'Meera',occupancy:'Owner occupied',contact:'99999',assessment:4500};
function setup(request,settings={table:'villaMaster',columns}){const window={};vm.runInNewContext(source,{window,URLSearchParams});return window.createVillaDirectory(request,settings);}
test('uses exact villaMaster table and maps actual columns',async()=>{let url;const directory=setup(async u=>{url=u;return [row]});const villas=await directory.list();assert.match(url,/\/rest\/v1\/villaMaster\?/);assert.equal(villas[0].id,'FV-001');assert.equal(villas[0].name,'Meera');assert.equal(villas[0]._masterKey,'uuid-1');assert.equal(villas[0].due,4500);});
test('insert writes only mapped directory fields and requests saved row',async()=>{let call;const directory=setup(async(url,options)=>{call={url,...options};return [row]});await directory.save({id:'FV-001',name:'Meera',type:'Owner occupied',phone:'99999',due:4500,paid:999});assert.equal(call.method,'POST');assert.equal(call.prefer,'return=representation');assert.deepEqual(JSON.parse(JSON.stringify(call.body)),{villa_no:'FV-001',resident:'Meera',occupancy:'Owner occupied',contact:'99999',assessment:4500});});
test('edit addresses stable primary key and compares original values',async()=>{let call;const directory=setup(async(url,options)=>{if(!options)return [row];call={url,...options};return [{...row,resident:'Updated'}]});const original=(await directory.list())[0];const changed=await directory.save({...original,name:'Updated'},original);const params=new URL('https://example.test'+call.url).searchParams;assert.equal(call.method,'PATCH');assert.equal(params.get('row_id'),'eq.uuid-1');assert.equal(params.get('resident'),'eq.Meera');assert.equal(changed.name,'Updated');});
test('empty PATCH result is reported as a failed save',async()=>{const directory=setup(async(url,options)=>options?[]:[row]);const original=(await directory.list())[0];await assert.rejects(directory.save({...original,name:'Changed'},original),/not saved/);});
test('villa number changes cannot break existing payment references',async()=>{const directory=setup(async()=>[row]);const original=(await directory.list())[0];await assert.rejects(directory.save({...original,id:'FV-002'},original),/cannot change/);});
test('missing schema prevents speculative writes',async()=>{let calls=0;const directory=setup(async()=>{calls++;return []},{table:'villaMaster',columns:null});await assert.rejects(directory.list(),/column mapping/);await assert.rejects(directory.save({}),/column mapping/);assert.equal(calls,0);});
test('reads subsequent pages beyond REST row limits',async()=>{let calls=0;const directory=setup(async url=>{calls++;const offset=Number(new URL('https://example.test'+url).searchParams.get('offset'));return offset===0?Array.from({length:500},(_,i)=>({...row,row_id:i,villa_no:'FV-'+i})):[{...row,row_id:500,villa_no:'FV-500'}]});assert.equal((await directory.list()).length,501);assert.equal(calls,2);});

test('maintenance, counts and booleans use unquoted scalar filters including numeric strings',async()=>{
 const fullColumns={...columns,numRes:'NumRes',numKids:'NumKids',ownCCTV:'OwnCCTV',ownPwrLine:'OwnPwrLine'};
 const originalRow={...row,assessment:'800',NumRes:3,NumKids:0,OwnCCTV:true,OwnPwrLine:false};let captured;
 const directory=setup(async(url,options)=>{if(!options)return [originalRow];captured={url,...options};return [originalRow]},{table:'villaMaster',columns:fullColumns});
 const original=(await directory.list())[0];await directory.save({...original,name:'Updated'},original);
 const params=new URL('https://example.test'+captured.url).searchParams;
 assert.equal(params.get('assessment'),'eq.800');assert.equal(params.get('NumRes'),'eq.3');assert.equal(params.get('NumKids'),'eq.0');assert.equal(params.get('OwnCCTV'),'eq.true');assert.equal(params.get('OwnPwrLine'),'eq.false');assert.equal(captured.body.assessment,800);
});
test('nullable values use is.null and punctuation in scalar text is preserved',async()=>{
 let captured;const originalRow={...row,resident:'Owner, "A"',contact:null};const directory=setup(async(url,options)=>{if(!options)return [originalRow];captured=url;return [originalRow]});
 const original=(await directory.list())[0];await directory.save(original,original);const params=new URL('https://example.test'+captured).searchParams;
 assert.equal(params.get('contact'),'is.null');assert.equal(params.get('resident'),'eq.'+originalRow.resident);
});
test('blocked update to an unchanged readable record identifies update policy access',async()=>{
 const directory=setup(async(url,options)=>options?[]:[row]);const original=(await directory.list())[0];
 await assert.rejects(directory.save({...original,name:'New name'},original),/UPDATE policies and grants/);
});
test('stale update reports a changed record rather than a policy issue',async()=>{
 let reads=0;const directory=setup(async(url,options)=>options?[]:(reads++===0?[row]:[]));const original=(await directory.list())[0];
 await assert.rejects(directory.save({...original,name:'New name'},original),/record changed or is no longer accessible/);
});
