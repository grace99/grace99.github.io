const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const source=fs.readFileSync(require('node:path').join(__dirname,'../supabase.js'),'utf8');
const empty={villas:[],issues:[],team:[],resources:[],posts:[],payments:[]};
function setup(handler,stored={}){
 const storage=new Map(Object.entries(stored));const calls=[];
 const ctx={window:{FERNSVILLA_SUPABASE:{url:'https://example.supabase.co',signupRedirect:'https://grace99.github.io/?signup=confirmed',passwordResetRedirect:'https://grace99.github.io/?reset-password=1',publishableKey:'sb_publishable_test',villaMaster:{table:'villaMaster',columns:{key:'Villa',id:'Villa',name:'Name',type:'OwnORrent',phone:'PriPhoneNo',due:'MaintAmount'}}}},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},AbortController,setTimeout,clearTimeout,atob,URLSearchParams,fetch:async(url,options)=>{calls.push({url,...options});const result=await handler(url,options);return {ok:(result.status||200)<400,status:result.status||200,text:async()=>JSON.stringify(result.data)};}};
 vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../villa-directory.js'),'utf8'),ctx);vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../ledger-utils.js'),'utf8'),ctx);vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../dues-ledger.js'),'utf8'),ctx);vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../community-issues.js'),'utf8'),ctx);vm.runInNewContext(source,ctx);return {cloud:ctx.window.FernsCloud,calls,storage};
}
const login={access_token:'access-test',refresh_token:'refresh-test',expires_in:3600,user:{id:'user-uuid',email:'member@example.test'}};
function handler(role='admin',saveResult=8){return (url,options)=>{
 if(url.includes('/auth/v1/token'))return {data:login};
 if(url.includes('fernsvilla_members'))return {data:role?[{role}]:[]};
 if(url.includes('fernsvilla_state'))return {data:[{data:empty,revision:7}]};
 if(url.includes('/villaDues')||url.includes('/VillaPmt'))return {data:[]};
 if(url.includes('/community_issues'))return {data:[]};
 if(url.includes('/villaMaster'))return {data:[]};
 if(url.includes('fernsvilla_save'))return {data:saveResult};
 if(url.includes('/auth/v1/logout'))return {data:{}};
 if(url.includes('/rest/v1/villaPaymentAllocations'))return {data:[]};
 throw Error('Unexpected request '+url);
};}
test('member login loads shared state, sends user access token and saves with revision',async()=>{
 const {cloud,calls}=setup(handler());await cloud.signIn('member@example.test','password');await cloud.save(empty);
 assert.equal(cloud.canEdit(),true);const save=calls.at(-1);assert.equal(save.headers.Authorization,'Bearer access-test');assert.equal(save.headers.apikey,'sb_publishable_test');assert.equal(JSON.parse(save.body).expected_revision,7);
 await cloud.save(empty);assert.equal(JSON.parse(calls.at(-1).body).expected_revision,8);
});
test('nonmember login does not fetch association records',async()=>{
 const {cloud,calls}=setup(handler(null));await assert.rejects(cloud.signIn('member@example.test','password'),/awaiting association approval/);assert.equal(calls.some(c=>c.url.includes('fernsvilla_state')),false);
});
test('resident write is blocked without making a write request',async()=>{
 const {cloud,calls}=setup(handler('resident'));await cloud.signIn('member@example.test','password');assert.equal(cloud.canEdit(),false);await assert.rejects(cloud.save(empty),/editor access/);assert.equal(calls.some(c=>c.url.includes('fernsvilla_save')),false);
});
test('failed save preserves revision so a retry cannot silently acknowledge a conflict',async()=>{
 let fail=true;const normal=handler();const {cloud,calls}=setup((url,options)=>url.includes('fernsvilla_save')&&fail?{status:400,data:{message:'Revision conflict'}}:normal(url,options));
 await cloud.signIn('member@example.test','password');await assert.rejects(cloud.save(empty),/Revision conflict/);fail=false;await cloud.save(empty);assert.equal(JSON.parse(calls.at(-1).body).expected_revision,7);
});
test('expired sessions refresh before reading and sign-out clears local credentials even on error',async()=>{
 const session={...login,expires_at:1};const normal=handler();const {cloud,calls,storage}=setup((url,options)=>url.includes('/logout')?{status:500,data:{message:'Offline'}}:normal(url,options),{'fernsvilla-supabase-session':JSON.stringify(session)});
 await cloud.load();assert.match(calls[0].url,/grant_type=refresh_token/);assert.equal(JSON.parse(calls[0].body).refresh_token,'refresh-test');await assert.rejects(cloud.signOut(),/Offline/);assert.equal(storage.has('fernsvilla-supabase-session'),false);assert.equal(cloud.hasSession(),false);
});
test('secret and service-role keys are rejected',()=>{
 const {cloud}=setup(handler());assert.throws(()=>cloud.setPublicKey('sb_secret_do_not_use'),/public/);const payload=Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url');assert.throws(()=>cloud.setPublicKey('header.'+payload+'.signature'),/public/);
});
test('villaMaster is authoritative and saves only balances into association document',async()=>{
 const normal=handler();const {cloud,calls}=setup((url,options)=>{
 if(url.includes('fernsvilla_state'))return {data:[{revision:7,data:{...empty,villas:[{id:'FV-001',name:'Stale JSON name',due:100,paid:900}]}}]};
 if(url.includes('/villaDues')||url.includes('/VillaPmt'))return {data:[]};
 if(url.includes('/community_issues'))return {data:[]};
 if(url.includes('/villaMaster'))return {data:[{Villa:'FV-001',Name:'Actual master name',OwnORrent:'Owner',PriPhoneNo:'12345',MaintAmount:'4500.00'}]};
 return normal(url,options);
 });
 const data=await cloud.signIn('member@example.test','password');assert.equal(data.villas[0].name,'Actual master name');assert.equal(data.villas[0].due,4500);assert.equal(data.villas[0].paid,900);
 await cloud.save(data);const stored=JSON.parse(calls.at(-1).body).new_data.villas[0];assert.deepEqual(stored,{id:'FV-001',due:4500,paid:900});
});
test('directory creation bypasses association JSON save and sends exact table columns',async()=>{
 const normal=handler();const {cloud,calls}=setup((url,options)=>url.includes('/villaMaster')&&options.method==='POST'?{data:[{Villa:'FV-009',Name:'New owner',OwnORrent:'Owner',PriPhoneNo:null,MaintAmount:5000}]}:normal(url,options));
 await cloud.signIn('member@example.test','password');const before=calls.length;await cloud.saveVilla({id:'FV-009',name:'New owner',type:'Owner',phone:'',due:5000});assert.equal(calls.length,before+1);const save=calls.at(-1);assert.match(save.url,/\/villaMaster$/);assert.equal(save.headers.Prefer,'return=representation');assert.deepEqual(JSON.parse(save.body),{Villa:'FV-009',Name:'New owner',OwnORrent:'Owner',PriPhoneNo:null,MaintAmount:5000});
});
test('relational financial records never overwrite legacy JSON payment history',async()=>{
 const normal=handler(),legacy=[{villa:'FV-001',amount:800,reference:'Old reference'}];let saved;
 const {cloud}=setup((url,options)=>{
 if(url.includes('fernsvilla_state'))return {data:[{revision:7,data:{...empty,payments:legacy}}]};
 if(url.includes('fernsvilla_save')){saved=JSON.parse(options.body).new_data;return {data:8};}
 return normal(url,options);
 });const data=await cloud.signIn('member@example.test','password');data.payments=[{id:1,Villa:'FV-001',PmtAmt:2400}];data.dues=[{villa:'FV-001',dueAmt:800}];await cloud.save(data);assert.deepEqual(saved.payments,legacy);assert.equal('dues' in saved,false);
});
test('table permission errors do not discard a valid signed-in session',async()=>{
 const normal=handler();const {cloud}=setup((url,options)=>url.includes('/villaDues')?{status:401,data:{code:'42501',message:'permission denied'}}:normal(url,options));await assert.rejects(cloud.signIn('member@example.test','password'),/permission denied/);assert.equal(cloud.hasSession(),true);
});
test('admin feed reads newest events with bounded timestamp/ID pagination',async()=>{
 const base=handler();let params;
 const {cloud}=setup((url,options)=>{if(url.includes('fernsvilla_audit_events')){params=new URL(url).searchParams;return {data:Array.from({length:101},(_,i)=>({id:200-i,occurred_at:'2026-10-14T12:00:00+00:00'}))};}return base(url,options);});
 await cloud.signIn('admin@example.test','password');const result=await cloud.adminFeed({id:300,occurred_at:'2026-10-14T12:00:00+00:00'});assert.equal(result.events.length,100);assert.equal(result.hasMore,true);assert.equal(params.get('order'),'occurred_at.desc,id.desc');assert.equal(params.get('limit'),'101');assert.equal(params.get('or'),'(occurred_at.lt.2026-10-14T12:00:00+00:00,and(occurred_at.eq.2026-10-14T12:00:00+00:00,id.lt.300))');
 await assert.rejects(cloud.adminFeed({id:'1)malformed',occurred_at:'2026-10-14T12:00:00Z'}),/Invalid activity cursor/);
});
test('editors and residents cannot request the administrator feed',async()=>{
 for(const role of ['editor','resident']){const {cloud,calls}=setup(handler(role));await cloud.signIn('member@example.test','password');await assert.rejects(cloud.adminFeed(),/Administrator access/);assert.equal(calls.filter(c=>c.url.includes('fernsvilla_audit_events')).length,0);}
});

test('recovery email uses the public Pages callback without an existing session',async()=>{const {cloud,calls}=setup(()=>({data:{}}));await cloud.sendPasswordReset(' member@example.test ');const call=calls[0];assert.equal(new URL(call.url).searchParams.get('redirect_to'),'https://grace99.github.io/?reset-password=1');assert.equal(call.headers.Authorization,undefined);assert.equal(JSON.parse(call.body).email,'member@example.test');});
test('recovery verifies the token and updates passwords independently of membership',async()=>{const {cloud,calls,storage}=setup((url,options)=>{if(url.endsWith('/user'))return {data:login.user};if(url.endsWith('/logout'))return {data:{}};throw Error(url);});await assert.rejects(cloud.setNewPassword('password123'),/recovery link/);await cloud.acceptRecovery(new URLSearchParams({type:'recovery',access_token:'recovery-access',refresh_token:'recovery-refresh',expires_in:'3600'}));assert.equal(cloud.hasRecovery(),true);assert.equal(cloud.canEdit(),false);await assert.rejects(cloud.load(),/Finish resetting/);await cloud.setNewPassword('new-password123');assert.equal(calls.find(c=>c.method==='PUT').headers.Authorization,'Bearer recovery-access');assert.equal(JSON.parse(calls.find(c=>c.method==='PUT').body).password,'new-password123');assert.equal(cloud.hasSession(),false);assert.equal(storage.has('fernsvilla-supabase-session'),false);assert.equal(calls.some(c=>c.url.includes('/rest/v1/')),false);});
test('invalid recovery tokens never establish a session',async()=>{const {cloud}=setup(()=>({status:401,data:{message:'Expired recovery link'}}));await assert.rejects(cloud.acceptRecovery(new URLSearchParams({type:'recovery',access_token:'expired',refresh_token:'expired'})),/Expired/);assert.equal(cloud.hasRecovery(),false);});

test('self signup sends a confirmation redirect and no chosen membership role',async()=>{const {cloud,calls}=setup(()=>({data:{user:{id:'pending'}}}));await cloud.signUp('New Resident',' new@example.test ','password123');const call=calls[0],body=JSON.parse(call.body);assert.equal(new URL(call.url).searchParams.get('redirect_to'),'https://grace99.github.io/?signup=confirmed');assert.equal(body.email,'new@example.test');assert.equal(body.data.fernsvilla_signup,'true');assert.equal(body.data.role,undefined);assert.equal(cloud.hasSession(),false);});
test('resident blog publication uses the dedicated append RPC without shared-state saving',async()=>{const base=handler('resident');const {cloud,calls}=setup((url,options)=>url.includes('fernsvilla_add_post')?{data:{}}:base(url,options));await cloud.signIn('resident@example.test','password');await cloud.addPost({title:'Hello',category:'Community',body:'A story',author:'Forged author'});const call=calls.find(c=>c.url.includes('fernsvilla_add_post'));assert.deepEqual(JSON.parse(call.body),{post_title:'Hello',post_category:'Community',post_body:'A story'});assert.equal(calls.some(c=>c.url.includes('fernsvilla_save')),false);await assert.rejects(cloud.approveRegistration('other'),/Administrator/);await assert.rejects(cloud.registrations(),/Administrator/);});
test('dedicated issues override JSON on load and unrelated saves preserve legacy JSON',async()=>{
 const legacy=[{id:1,title:'Legacy gate'}],base=handler();
 const {cloud,calls}=setup((url,options)=>{
  if(url.includes('fernsvilla_state'))return {data:[{data:{...empty,issues:legacy},revision:7}]};
  if(url.includes('/community_issues'))return {data:[{issue_id:99,issue_title:'Dedicated gate',issue_status:'Open'}]};
  return base(url,options);
 });
 const data=await cloud.signIn('member@example.test','password');assert.equal(data.issues[0].id,99);await cloud.save(data);assert.deepEqual(JSON.parse(calls.at(-1).body).new_data.issues,legacy);
});
