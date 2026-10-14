// Run after editing browser assets so GitHub Pages requests the matching file contents.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.join(__dirname,'..'),file=path.join(root,'index.html');
const html=fs.readFileSync(file,'utf8').replace(/((?:src|href)=")([^"?]+\.(?:js|css|svg))(?:\?[^" ]*)?"/g,(match,prefix,asset)=>{
 if(/^(?:https?:|\/\/)/.test(asset))return match;
 const hash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,asset))).digest('hex').slice(0,16);
 return `${prefix}${asset}?v=${hash}"`;
});
fs.writeFileSync(file,html);
