import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createWorker,adminMessage,base64url,digest,verifyPassword} from '../src/worker.mjs';
import {html,javascript} from '../src/panel.mjs';
import {testPassword,testPasswordConfig} from './auth-fixture.mjs';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const publicKey=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
function fixture(config=testPasswordConfig){const db=new DatabaseSync(':memory:');const DB={prepare(sql){return {bind(...args){return {async first(){return db.prepare(sql).get(...args)??null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){return db.prepare(sql).run(...args);}};},async run(){return db.prepare(sql).run();}};},async batch(statements){for(const s of statements)await s.run();}};const worker=createWorker(publicKey,config),env={DB,ADMIN_KEY:'old-admin-secret-'+ 'X'.repeat(32)};return {db,env,worker};}
async function request(f,path,data={},cookie='',sign=false,extra={}){const url=new URL('https://idk.example'+path),body=JSON.stringify(data);const headers={'Content-Type':'application/json',Cookie:cookie,...extra};if(sign){const time=String(Math.floor(Date.now()/1000)),nonce=crypto.randomUUID();Object.assign(headers,{'X-IDK-Time':time,'X-IDK-Nonce':nonce,'X-IDK-Signature':base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(adminMessage(url,'POST',time,nonce,await digest(body)))))});}return f.worker.fetch(new Request(url,{method:'POST',headers,body}),f.env);}
const login=(f,password=testPassword)=>request(f,'/api/admin/login',{username:testPasswordConfig.username,password});
test('password and PEM are both enforced server-side; logout invalidates the cookie',async()=>{
 const f=fixture();assert.equal((await login(f,'incorrect')).status,401);
 assert.equal((await request(f,'/api/admin/login',{username:'wrong',password:testPassword})).status,401);
 assert.equal((await request(f,'/api/admin/setup',{},'',true)).status,401);
 assert.equal((await request(f,'/api/admin/setup',{},'',false,{Authorization:'Bearer '+f.env.ADMIN_KEY})).status,401);
 const result=await login(f);assert.equal(result.status,200);const setCookie=result.headers.get('set-cookie'),cookie=setCookie.split(';')[0];
 for(const expected of ['HttpOnly','Secure','SameSite=Strict','Max-Age=1800'])assert.ok(setCookie.includes(expected));
 assert.equal((await request(f,'/api/admin/setup',{},cookie)).status,401);
 assert.equal((await request(f,'/api/admin/setup',{},cookie,true)).status,200);
 assert.equal((await request(f,'/api/admin/logout',{},cookie,false,{Origin:'https://evil.example'})).status,403);
 assert.equal((await request(f,'/api/admin/logout',{},cookie)).status,200);
 assert.equal((await request(f,'/api/admin/setup',{},cookie,true)).status,401);
 const second=await login(f),secondCookie=second.headers.get('set-cookie').split(';')[0];f.db.prepare('UPDATE admin_sessions SET expires=0').run();
 assert.equal((await request(f,'/api/admin/setup',{},secondCookie,true)).status,401);f.db.close();
});
test('password guesses are bounded and origin/payload checks apply before login',async()=>{
 const f=fixture();assert.equal((await request(f,'/api/admin/login',{},'',false,{Origin:'https://evil.example'})).status,403);
 for(let i=0;i<8;i++)assert.equal((await login(f,'wrong')).status,401);
 assert.equal((await login(f)).status,429);f.db.close();
 const second=fixture();assert.equal((await request(second,'/api/admin/login',{password:'x'.repeat(3000)})).status,413);second.db.close();
});
test('password verifier uses exact username/password and UI hides PEM until password verification',async()=>{
 assert.ok(await verifyPassword(testPasswordConfig.username,testPassword,testPasswordConfig));
 assert.equal(await verifyPassword(testPasswordConfig.username.toUpperCase(),testPassword,testPasswordConfig),false);
 assert.equal(await verifyPassword(testPasswordConfig.username,testPassword+' ',testPasswordConfig),false);
 assert.ok(html.includes('id="pemStep" hidden'));assert.ok(html.includes('id="loginUsername"'));assert.ok(!html.includes('id="generateAdmin"'));
 assert.doesNotThrow(()=>new Function(javascript));assert.ok(!javascript.includes('localStorage'));assert.ok(!javascript.includes('sessionStorage'));
});
test('first account setup is owner-only, stores a private salted hash, and cannot overwrite an existing owner',async()=>{
 const f=fixture(null),credentials={username:testPasswordConfig.username,password:testPassword};
 const before=await login(f);assert.equal(before.status,409);assert.equal((await before.json()).code,'ACCOUNT_NOT_SETUP');
 assert.equal((await request(f,'/api/admin/account/setup',credentials)).status,401);
 const setup=await request(f,'/api/admin/account/setup',credentials,'',true);assert.equal(setup.status,200);
 const row=f.db.prepare('SELECT * FROM admin_accounts').get();assert.equal(row.username,credentials.username);assert.notEqual(row.hash,credentials.password);assert.equal(row.iterations,100000);assert.ok(row.salt);assert.equal(row.password,undefined);
 assert.ok(await verifyPassword(credentials.username,credentials.password,row));
 assert.equal((await login(f)).status,200);assert.equal((await login(f,'bad-password')).status,401);
 assert.equal((await request(f,'/api/admin/account/setup',{username:'attacker',password:'changed-password'},'',true)).status,409);
 assert.equal(f.db.prepare('SELECT username FROM admin_accounts').get().username,credentials.username);
 const publicRead=await f.worker.fetch(new Request('https://idk.example/api/admin/licenses'),f.env);assert.equal(publicRead.status,401);f.db.close();
});
