import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createWorker,adminMessage,base64url,digest} from '../src/worker.mjs';
import {html,javascript} from '../src/panel.mjs';
import {testPassword,testPasswordConfig} from './auth-fixture.mjs';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const publicKey=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
const subject='AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE';
async function token(name='Example'){const now=Math.floor(Date.now()/1000),body=base64url(new TextEncoder().encode(JSON.stringify({app:'app.taifplus.store',subject,name,issued:now,expires:now+86400})));return 'TAIF1.'+body+'.'+base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(body)));}
function fixture(){const db=new DatabaseSync(':memory:');const DB={prepare(sql){return {bind(...args){return {async first(){return db.prepare(sql).get(...args)??null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){return db.prepare(sql).run(...args);}};},async run(){return db.prepare(sql).run();}};},async batch(statements){db.exec('BEGIN');try{for(const s of statements)await s.run();db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}}};const env={DB,ADMIN_KEY:'test-only-encryption-secret-'+ 'X'.repeat(32)},worker=createWorker(publicKey,testPasswordConfig);
 async function request(path,method='GET',data,cookie='',signed=true){const url=new URL('https://idk.example'+path),body=data===undefined?undefined:JSON.stringify(data),headers={Cookie:cookie,...(body?{'Content-Type':'application/json'}:{})};if(signed){const time=String(Math.floor(Date.now()/1000)),nonce=crypto.randomUUID();Object.assign(headers,{'X-IDK-Time':time,'X-IDK-Nonce':nonce,'X-IDK-Signature':base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(adminMessage(url,method,time,nonce,await digest(body??'')))))});}return worker.fetch(new Request(url,{method,headers,body}),env);}
 async function login(username=testPasswordConfig.username,password=testPassword){const r=await request('/api/admin/login','POST',{username,password},'',false);assert.equal(r.status,200);return r.headers.get('set-cookie').split(';')[0];}
 return {db,request,login};}
async function ready(){const f=fixture();f.owner=await f.login();assert.equal((await f.request('/api/admin/setup','POST',{},f.owner)).status,200);f.delegate=await (await f.request('/api/admin/delegates','POST',{username:'delegate-one',password:'test-delegate-password',name:'First delegate'},f.owner)).json();assert.ok(f.delegate.id);f.cookie=await f.login('delegate-one','test-delegate-password');return f;}
test('same PEM with separate sessions enforces per-delegate code visibility, writes and owner-only administration',async()=>{
 const f=await ready();const ownerCode=await (await f.request('/api/admin/licenses','POST',{token:await token('Owner')},f.owner)).json();
 const own=await (await f.request('/api/admin/licenses','POST',{token:await token('Delegate'),issuer_id:'owner',role:'owner'},f.cookie)).json();
 const setup=await (await f.request('/api/admin/setup','POST',{},f.cookie)).json();assert.equal(setup.account.role,'delegate');assert.equal(setup.account.id,f.delegate.id);
 const list=await (await f.request('/api/admin/licenses','GET',undefined,f.cookie)).json();assert.deepEqual(list.items.map(x=>x.id),[own.id]);assert.equal(list.items[0].issuer_id,f.delegate.id);
 const all=await (await f.request('/api/admin/licenses','GET',undefined,f.owner)).json();assert.equal(all.items.length,2);assert.ok(all.items.some(x=>x.issuer_id===f.delegate.id));
 assert.equal((await f.request('/api/admin/licenses?issuer=owner','GET',undefined,f.cookie)).status,403);
 for(const method of ['GET','POST'])assert.equal((await f.request('/api/admin/delegates',method,method==='POST'?{role:'owner'}:undefined,f.cookie)).status,403);
 assert.equal((await f.request('/api/admin/delegates/'+f.delegate.id,'PATCH',{disabled:false},f.cookie)).status,403);
 assert.equal((await f.request('/api/admin/licenses/'+ownerCode.id,'PATCH',{disabled:true},f.cookie)).status,404);
 assert.equal((await f.request('/api/admin/licenses/'+ownerCode.id+'/certificate','POST',{},f.cookie)).status,404);
 assert.equal((await f.request('/api/admin/licenses/'+own.id,'PATCH',{disabled:true},f.cookie)).status,200);
 assert.equal((await f.request('/api/admin/licenses/'+own.id,'PATCH',{disabled:false},f.cookie)).status,200);
 const filtered=await (await f.request('/api/admin/licenses?issuer='+f.delegate.id,'GET',undefined,f.owner)).json();assert.equal(filtered.items.length,1);assert.equal(filtered.items[0].id,own.id);
 const delegates=await (await f.request('/api/admin/delegates','GET',undefined,f.owner)).json();assert.equal(delegates.items[0].codes,1);for(const key of ['hash','salt','password'])assert.equal(delegates.items[0][key],undefined);
 f.db.close();
});
test('revoking a delegate invalidates every session while optionally keeping codes; bulk owner blocks cannot be undone by delegates',async()=>{
 const f=await ready(),secondCookie=await f.login('delegate-one','test-delegate-password');const own=await (await f.request('/api/admin/licenses','POST',{token:await token()},f.cookie)).json();
 assert.equal((await f.request('/api/admin/delegates/'+f.delegate.id,'PATCH',{disabled:true},f.owner)).status,200);
 for(const cookie of [f.cookie,secondCookie])assert.equal((await f.request('/api/admin/licenses','GET',undefined,cookie)).status,401);
 assert.equal((await f.request('/api/admin/login','POST',{username:'delegate-one',password:'test-delegate-password'},'',false)).status,401);
 assert.equal((await f.request('/api/redeem','POST',{code:own.code,subject},'',false)).status,200);
 assert.equal((await f.request('/api/admin/delegates/'+f.delegate.id,'PATCH',{disabled:false},f.owner)).status,200);f.cookie=await f.login('delegate-one','test-delegate-password');
 assert.equal((await f.request('/api/admin/delegates/'+f.delegate.id+'/codes','PATCH',{disabled:true},f.owner)).status,200);
 assert.equal((await f.request('/api/redeem','POST',{code:own.code,subject},'',false)).status,403);
 assert.equal((await f.request('/api/admin/licenses/'+own.id,'PATCH',{disabled:false},f.cookie)).status,403);
 assert.equal((await f.request('/api/admin/licenses/'+own.id,'PATCH',{disabled:false},f.owner)).status,200);
 assert.equal((await f.request('/api/redeem','POST',{code:own.code,subject},'',false)).status,200);
 assert.equal((await f.request('/api/admin/delegates/'+f.delegate.id,'PATCH',{disabled:true,disable_codes:true},f.owner)).status,200);
 assert.equal((await f.request('/api/redeem','POST',{code:own.code,subject},'',false)).status,403);f.db.close();
});
test('legacy owner codes remain owner-only; delegate usernames cannot shadow owner or each other',async()=>{
 const f=await ready();f.db.prepare('INSERT INTO licenses(id,code_hash,suffix,subject,name,token,issued,expires) VALUES(?,?,?,?,?,?,?,?)').run('legacy','legacy-hash','LAST',subject,'Old owner record',await token(),1,9999999999);
 const owner=await (await f.request('/api/admin/licenses?issuer=owner','GET',undefined,f.owner)).json();assert.equal(owner.items[0].id,'legacy');assert.equal(owner.items[0].issuer_id,'owner');
 const delegated=await (await f.request('/api/admin/licenses','GET',undefined,f.cookie)).json();assert.equal(delegated.items.length,0);
 for(const username of [testPasswordConfig.username,'delegate-one'])assert.equal((await f.request('/api/admin/delegates','POST',{username,password:'test-password',name:'Test'},f.owner)).status,409);
 assert.equal((await f.request('/api/admin/delegates/owner','PATCH',{disabled:true},f.cookie)).status,403);
 assert.ok(html.includes('id="delegateManager"'));assert.ok(html.includes('id="issuerFilter"'));assert.doesNotThrow(()=>new Function(javascript));f.db.close();
});
