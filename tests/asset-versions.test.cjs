const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
test('published HTML requests the current versions of all local browser assets',()=>{
 const root=path.join(__dirname,'..'),html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 const references=[...html.matchAll(/(?:src|href)="([^"?]+\.(?:js|css|svg))(?:\?v=([^" ]+))?"/g)].filter(([,asset])=>!asset.startsWith('http')&&!asset.startsWith('//'));
 assert.ok(references.length>0);
 for(const [,asset,version] of references){const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,asset))).digest('hex').slice(0,16);assert.equal(version,hash,`${asset} changed: run node scripts/update-asset-versions.cjs before publishing`);}
});
