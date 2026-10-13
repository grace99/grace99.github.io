const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const source=fs.readFileSync(require('node:path').join(__dirname,'../supabase.js'),'utf8');
const empty={villas:[],issues:[],team:[],resources:[],posts:[],payments:[]};
function setup(handler,stored={}){
 const storage=new Map(Object.entries(stored));const calls=[];
 const ctx={window:{FERNSVILLA_SUPABASE:{url:'https://example.supabase.co',publishableKey:'sb_publishable_test'}},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},AbortController,setTimeout,clearTimeout,atob,fetch:async(url,options)=>{calls.push({url,...options});const result=await handler(url,options);return {ok:(result.status||200)<400,status:result.status||200,text:async()=>JSON.stringify(result.data)};}};
 vm.runInNewContext(source,ctx);return {cloud:ctx.window.FernsCloud,calls,storage};
}
const login={access_token:'access-test',refresh_token:'refresh-test',expires_in:3600,user:{id:'user-uuid',email:'member@example.test'}};
function handler(role='admin',saveResult=8){return (url,options)=>{
 if(url.includes('/auth/v1/token'))return {data:login};
 if(url.includes('fernsvilla_members'))return {data:role?[{role}]:[]};
 if(url.includes('fernsvilla_state'))return {data:[{data:empty,revision:7}]};
 if(url.includes('fernsvilla_save'))return {data:saveResult};
 if(url.includes('/auth/v1/logout'))return {data:{}};
 throw Error('Unexpected request '+url);
};}
test('member login loads shared state, sends user access token and saves with revision',async()=>{
 const {cloud,calls}=setup(handler());await cloud.signIn('member@example.test','password');await cloud.save(empty);
 assert.equal(cloud.canEdit(),true);const save=calls.at(-1);assert.equal(save.headers.Authorization,'Bearer access-test');assert.equal(save.headers.apikey,'sb_publishable_test');assert.equal(JSON.parse(save.body).expected_revision,7);
 await cloud.save(empty);assert.equal(JSON.parse(calls.at(-1).body).expected_revision,8);
});
test('nonmember login does not fetch association records',async()=>{
 const {cloud,calls}=setup(handler(null));await assert.rejects(cloud.signIn('member@example.test','password'),/not been added/);assert.equal(calls.some(c=>c.url.includes('fernsvilla_state')),false);
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
