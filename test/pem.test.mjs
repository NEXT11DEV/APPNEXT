import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createWorker,adminMessage,digest,base64url} from '../src/worker.mjs';
import {createHash} from 'node:crypto';
import {testPassword,testPasswordConfig} from './auth-fixture.mjs';
import {javascript} from '../src/panel.mjs';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const publicKey=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
const testSession=base64url(crypto.getRandomValues(new Uint8Array(32)));
function fixture(){const db=new DatabaseSync(':memory:');db.exec('CREATE TABLE admin_sessions (token_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL)');db.prepare('INSERT INTO admin_sessions VALUES(?,?)').run(createHash('sha256').update(testSession).digest('base64url'),Math.floor(Date.now()/1000)+1800);const DB={prepare(sql){return {bind(...args){return {async first(){return db.prepare(sql).get(...args)??null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){return db.prepare(sql).run(...args);}};},async run(){return db.prepare(sql).run();}};},async batch(statements){for(const s of statements)await s.run();}};return {db,env:{DB},worker:createWorker(publicKey,testPasswordConfig)};}
async function signed(path='/api/admin/setup',method='POST',data={},options={}){
 const url=new URL('https://idk.example'+path),body=data===undefined?undefined:JSON.stringify(data);
 const time=String(options.time??Math.floor(Date.now()/1000)),nonce=options.nonce??crypto.randomUUID();
 const signature=base64url(await crypto.subtle.sign('Ed25519',options.key??pair.privateKey,new TextEncoder().encode(adminMessage(url,method,time,nonce,await digest(body??'')))));
 return new Request(options.url??url,{method,headers:{'Content-Type':'application/json','Cookie':'idk_admin='+testSession,'X-IDK-Time':time,'X-IDK-Nonce':nonce,'X-IDK-Signature':signature,...options.headers},body:options.body??body});
}
async function token(){const now=Math.floor(Date.now()/1000);const body=base64url(new TextEncoder().encode(JSON.stringify({app:'app.idkplus.store',subject:'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',name:'Owner test',issued:now,expires:now+86400})));return 'IDK1.'+body+'.'+base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(body)));}
test('PEM proofs bind body, route, origin and time; replay and wrong keys fail',async()=>{
 const f=fixture(),first=await signed();assert.equal((await f.worker.fetch(first.clone(),f.env)).status,200);assert.equal((await f.worker.fetch(first.clone(),f.env)).status,401);
 const other=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
 for(const options of [{time:Math.floor(Date.now()/1000)-500},{key:other.privateKey},{body:'{"changed":true}'},{url:'https://idk.example/api/admin/licenses'},{url:'https://other.example/api/admin/setup'}])assert.equal((await f.worker.fetch(await signed('/api/admin/setup','POST',{},options),f.env)).status,401);
 assert.equal((await f.worker.fetch(await signed('/api/admin/setup','POST',{}, {headers:{Origin:'https://evil.example'}}),f.env)).status,403);
 const issue=await f.worker.fetch(await signed('/api/admin/licenses','POST',{token:await token()}),f.env);assert.equal(issue.status,201);const issued=await issue.json();
 const missingSecret=await f.worker.fetch(await signed('/api/admin/licenses/'+issued.id+'/certificate','POST',{}),f.env);assert.equal(missingSecret.status,503);assert.match((await missingSecret.json()).error,/CERTIFICATE_KEY/);f.db.close();
});
test('actual browser PEM flow requires password session and authenticates without transmitting private key',async()=>{
 const f=fixture(),elements=new Map();const doc={getElementById(id){if(!elements.has(id))elements.set(id,{value:'',hidden:false,files:[],textContent:'',className:'',replaceChildren(){},append(){},children:[]});return elements.get(id);}};
 let cookie='';const sent=[],browserFetch=async(url,init)=>{sent.push(init);const response=await f.worker.fetch(new Request(url,{...init,headers:{...init.headers,...(cookie?{Cookie:cookie}:{})}}),f.env);if(response.headers.get('set-cookie'))cookie=response.headers.get('set-cookie').split(';')[0];return response;};
 const code=javascript.replace('HfxDxlZl9XEqrN86xR2A4kGyoop8k36ItekNw9WEhpA=',publicKey);
 const browser=new Function('document','fetch','location','crypto',code+';return {api,importOwnerKey};')(doc,browserFetch,{origin:'https://idk.example'},crypto);
 const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';await browser.api('login','POST',{username:testPasswordConfig.username,password:testPassword});await browser.importOwnerKey({size:pem.length,text:async()=>pem});
 assert.equal((await browser.api('setup','POST',{})).account.role,'owner');const issued=await browser.api('licenses','POST',{token:await token()});assert.equal(issued.code.length,12);assert.equal((await browser.api('licenses?offset=0')).items.length,1);
 f.env.CERTIFICATE_KEY='test-only-encryption-key-'+ 'Z'.repeat(32);
 const credential={p12:Buffer.concat([Buffer.from([0x30]),Buffer.alloc(100000,7)]).toString('base64'),profile:Buffer.from('<?xml version="1.0"?><plist/>').toString('base64'),password:'private-test'};
 assert.deepEqual(await browser.api('licenses/'+issued.id+'/certificate','POST',credential),{ok:true});
 for(const req of sent.filter(x=>x.headers['X-IDK-Signature'])){assert.ok(req.headers['X-IDK-Signature']);assert.ok(!JSON.stringify(req).includes('PRIVATE KEY'));assert.equal(req.headers.Authorization,undefined);}
 const noDB=await f.worker.fetch(new Request('https://idk.example/api/admin/setup',{method:'POST'}),{});assert.equal((await noDB.json()).code,'DB_NOT_BOUND');f.db.close();
});
