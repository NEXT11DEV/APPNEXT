import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createWorker,newCode,normalizeCode,verifyToken,base64url,adminMessage,digest } from '../src/worker.mjs';
import {testPassword,testPasswordConfig} from './auth-fixture.mjs';
import { javascript } from '../src/panel.mjs';
const now=Math.floor(Date.now()/1000);
const subject='AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const publicKey=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
async function token(overrides={}) {
 const body=base64url(new TextEncoder().encode(JSON.stringify({app:'app.taifplus.store',subject,name:'Test subscriber',issued:now,expires:now+86400,...overrides})));
 return 'TAIF1.'+body+'.'+base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(body)));
}
function fixture(){
 const db=new DatabaseSync(':memory:');
 const DB={prepare(sql){return {bind(...args){return {async first(){return db.prepare(sql).get(...args)??null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){return db.prepare(sql).run(...args);}};},async run(){return db.prepare(sql).run();}};},async batch(statements){db.exec('BEGIN');try{for(const s of statements)await s.run();db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}}};
 const env={DB,ADMIN_KEY:'test-only-admin-'+ 'X'.repeat(32)};
 const worker=createWorker(publicKey,testPasswordConfig);let cookie;
 async function request(path,method='GET',data,auth=true,extra={}){
  if(auth&&!cookie){const login=await worker.fetch(new Request('https://idk.example/api/admin/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:testPasswordConfig.username,password:testPassword})}),env);assert.equal(login.status,200);cookie=login.headers.get('set-cookie').split(';')[0];}
  const url=new URL('https://idk.example'+path),body=data?JSON.stringify(data):undefined;
  const headers={...(auth?{Cookie:cookie}:{}),...(data?{'Content-Type':'application/json'}:{}),'CF-Connecting-IP':'192.0.2.1',...extra};
  if(auth){const time=String(Math.floor(Date.now()/1000)),nonce=crypto.randomUUID();headers['X-IDK-Time']=time;headers['X-IDK-Nonce']=nonce;headers['X-IDK-Signature']=base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(adminMessage(url,method,time,nonce,await digest(body??'')))));}
  return worker.fetch(new Request(url,{method,headers,body}),env);
 }
 return {db,request,env,worker};
}
test('12-character unbiased-format codes normalize without changing the taif prefix',()=>{
 const codes=new Set();for(let i=0;i<5000;i++){const c=newCode();assert.match(c,/^TAIF[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$/);assert.equal(c.length,12);assert.equal(normalizeCode(c.toLowerCase()),'taif'+c.slice(4));assert.equal(normalizeCode(c),'taif'+c.slice(4));codes.add(c);}assert.equal(codes.size,5000);assert.equal(normalizeCode('taif../etc'),null);
});
test('real Ed25519 verification rejects forged, expired, future and wrong-app payloads',async()=>{
 assert.ok(await verifyToken(await token(),now,publicKey));
 for(const p of [{expires:now-1},{issued:now+1000},{app:'other'},{subject:'not-a-uuid'},{expires:now+731*86400}])assert.equal(await verifyToken(await token(p),now,publicKey),null);
 const t=await token();assert.equal(await verifyToken(t.slice(0,-4)+'AAAA',now,publicKey),null);
});
test('end-to-end issue, bound redemption, retry, disable and re-enable using real SQLite',async()=>{
 const f=fixture();assert.equal((await f.request('/api/admin/setup','POST',{},false)).status,401);
 assert.equal((await f.request('/api/admin/setup','POST',{})).status,200);
 assert.equal((await f.request('/api/admin/setup','POST',{})).status,200);
 const signed=await token();const issued=await f.request('/api/admin/licenses','POST',{token:signed});assert.equal(issued.status,201);const code=await issued.json();
 const invalid=await f.request('/api/redeem','POST',{code:code.code,subject:subject.replace('AAAA','FFFF')},false);assert.equal(invalid.status,403);
 for(let i=0;i<2;i++){const ok=await f.request('/api/redeem','POST',{code:code.code.toLowerCase(),subject},false);assert.equal(ok.status,200);assert.equal((await ok.json()).token,signed);}
 const list=await (await f.request('/api/admin/licenses')).json();assert.equal(list.items.length,1);assert.ok(list.items[0].first_used);assert.equal(list.items[0].token,undefined);assert.equal(list.items[0].code_hash,undefined);assert.equal(list.items[0].code,undefined);
 assert.equal((await f.request('/api/admin/licenses/'+code.id,'PATCH',{disabled:true})).status,200);
 assert.equal((await f.request('/api/redeem','POST',{code:code.code,subject},false)).status,403);
 await f.request('/api/admin/licenses/'+code.id,'PATCH',{disabled:false});assert.equal((await f.request('/api/redeem','POST',{code:code.code,subject},false)).status,200);
 f.db.close();
});
test('authentication, cross-origin writes, payload bounds, forgery and guessing limits',async()=>{
 const f=fixture();await f.request('/api/admin/setup','POST',{});
 assert.equal((await f.request('/api/admin/licenses')).status,200);
 assert.equal((await f.request('/api/admin/licenses','GET',undefined,false)).status,401);
 assert.equal((await f.request('/api/admin/licenses','POST',{token:await token()},true,{Origin:'https://evil.example'})).status,403);
 assert.equal((await f.request('/api/admin/licenses','POST',{token:'x'.repeat(9000)})).status,413);
 assert.equal((await f.request('/api/admin/licenses','POST',{token:'TAIF1.forged.fake'})).status,400);
 for(let i=0;i<15;i++)assert.equal((await f.request('/api/redeem','POST',{code:'invalid',subject},false)).status,403);
 assert.equal((await f.request('/api/redeem','POST',{code:'invalid',subject},false)).status,429);
 f.db.close();
});
test('list pagination does not drop records sharing an issuance second',async()=>{
 const f=fixture();await f.request('/api/admin/setup','POST',{});
 for(let i=0;i<105;i++)f.db.prepare('INSERT INTO licenses(id,code_hash,suffix,subject,name,token,issued,expires) VALUES(?,?,?,?,?,?,?,?)').run(String(i).padStart(4,'0'),String(i),'ABCD',subject,'Test','not-public',now,now+86400);
 const a=await (await f.request('/api/admin/licenses?offset=0')).json(),b=await (await f.request('/api/admin/licenses?offset='+a.next)).json();assert.equal(a.items.length,100);assert.equal(b.items.length,5);assert.equal(new Set([...a.items,...b.items].map(x=>x.id)).size,105);assert.equal(b.next,null);
 f.db.close();
});
test('panel is dependency-free and uses safe text nodes for subscriber data',()=>{assert.doesNotThrow(()=>new Function(javascript));assert.ok(javascript.includes('textContent=value'));assert.ok(!javascript.includes('innerHTML'));assert.ok(!javascript.includes('localStorage'));});
test('subscriber website, owner panel, brand and script routes remain distinct',async()=>{
 const f=fixture();
 const home=await f.request('/');assert.equal(home.status,200);const body=await home.text();assert.ok(body.includes('كل جديد، <em>بطابعك.'));assert.ok(!body.includes('id="adminKey"'));assert.ok(body.includes('/admin'));assert.ok(body.includes('taif-plus-1.1.0-unsigned.ipa'));
 const admin=await f.request('/admin');assert.equal(admin.status,200);assert.ok((await admin.text()).includes('id="adminKey"'));
 const icon=await f.request('/brand.jpg');assert.equal(icon.headers.get('content-type'),'image/jpeg');assert.equal((await icon.arrayBuffer()).byteLength,485755);
 assert.equal((await f.request('/site.js')).headers.get('content-type'),'application/javascript; charset=utf-8');
 assert.equal((await f.request('/api/admin/licenses','GET',undefined,false)).status,401);
 assert.equal((await f.request('/constructor')).status,404);
 f.db.close();
});
test('certificate delivery stays encrypted at rest and only follows a valid bound code',async()=>{
 const f=fixture();await f.request('/api/admin/setup','POST',{});
 const issued=await (await f.request('/api/admin/licenses','POST',{token:await token()})).json();
 const p12=Buffer.concat([Buffer.from([0x30]),Buffer.alloc(100000,7)]).toString('base64');
 const profile=Buffer.from('<?xml version="1.0"?><plist><dict/></plist>').toString('base64');
 const payload={p12,profile,password:'sample-secret-never-public'};
 const path='/api/admin/licenses/'+issued.id+'/certificate';
 assert.equal((await f.request(path,'POST',payload,false)).status,401);
 assert.equal((await f.request(path,'POST',payload)).status,200);
 const stored=f.db.prepare('SELECT * FROM credential_deliveries').get();
 assert.ok(stored.ciphertext);assert.ok(!stored.ciphertext.includes(payload.password));assert.ok(!stored.ciphertext.includes(p12.slice(0,100)));
 const list=await (await f.request('/api/admin/licenses')).json();assert.equal(list.items[0].has_certificate,1);assert.equal(list.items[0].ciphertext,undefined);
 const other=await f.request('/api/redeem','POST',{code:issued.code,subject:subject.replace('AAAA','FFFF')},false);assert.equal(other.status,403);assert.equal((await other.json()).credentials,undefined);
 const redeemed=await (await f.request('/api/redeem','POST',{code:issued.code,subject},false)).json();assert.deepEqual(redeemed.credentials,payload);
 f.env.ADMIN_KEY='changed-key-'+ 'Y'.repeat(32);
 assert.equal((await f.request('/api/redeem','POST',{code:issued.code,subject},false)).status,503);
 f.db.close();
});
test('catalog pages stay bounded to thirty, full-library search and no public download links',async()=>{
 const f=fixture();const first=await (await f.request('/api/catalog')).json();assert.equal(first.items.length,30);assert.equal(first.total,20419);assert.equal(first.next,30);assert.equal(first.items[0].downloadURL,undefined);
 const next=await (await f.request('/api/catalog?offset=30')).json();assert.equal(next.items.length,30);assert.ok(!first.items.some(x=>x.id===next.items[0].id));
 const search=await (await f.request('/api/catalog?q=Alpenglow')).json();assert.ok(search.total>0);assert.ok(search.items.every(a=>a.name.toLowerCase().includes('alpenglow')));
 const home=await (await f.request('/')).text();for(const url of ['https://t.me/YG8_1','https://t.me/tife_store1','https://t.me/tife_store'])assert.ok(home.includes(url));
 const page=await f.request('/apps');assert.equal(page.status,200);assert.ok((await page.text()).includes('catalogSearch'));
 f.db.close();
});
