import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {createWorker,adminMessage,digest,base64url} from '../src/worker.mjs';
import {createHash} from 'node:crypto';
import {testPassword,testPasswordConfig} from './auth-fixture.mjs';
import {javascript,html} from '../src/panel.mjs';
import {ed25519JS} from '../src/ed25519-asset.mjs';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const publicKey=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
const testSession=base64url(crypto.getRandomValues(new Uint8Array(32)));
function fixture(){const db=new DatabaseSync(':memory:');db.exec('CREATE TABLE admin_sessions (token_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL)');db.prepare('INSERT INTO admin_sessions VALUES(?,?)').run(createHash('sha256').update(testSession).digest('base64url'),Math.floor(Date.now()/1000)+1800);const DB={prepare(sql){return {bind(...args){return {async first(){return db.prepare(sql).get(...args)??null;},async all(){return {results:db.prepare(sql).all(...args)};},async run(){return db.prepare(sql).run(...args);}};},async run(){return db.prepare(sql).run();}};},async batch(statements){for(const s of statements)await s.run();}};return {db,env:{DB},worker:createWorker(publicKey,testPasswordConfig)};}
async function signed(path='/api/admin/setup',method='POST',data={},options={}){
 const url=new URL('https://idk.example'+path),body=data===undefined?undefined:JSON.stringify(data);
 const time=String(options.time??Math.floor(Date.now()/1000)),nonce=options.nonce??crypto.randomUUID();
 const signature=base64url(await crypto.subtle.sign('Ed25519',options.key??pair.privateKey,new TextEncoder().encode(adminMessage(url,method,time,nonce,await digest(body??'')))));
 return new Request(options.url??url,{method,headers:{'Content-Type':'application/json','Cookie':'taif_admin='+testSession,'X-IDK-Time':time,'X-IDK-Nonce':nonce,'X-IDK-Signature':signature,...options.headers},body:options.body??body});
}
async function token(){const now=Math.floor(Date.now()/1000);const body=base64url(new TextEncoder().encode(JSON.stringify({app:'app.taifplus.store',subject:'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',name:'Owner test',issued:now,expires:now+86400})));return 'TAIF1.'+body+'.'+base64url(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(body)));}
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
 const code=javascript.replace('yMFlyNPeTyazhCFLXQQa6CV/tf5Zgj8R5RjfQbpzJgQ=',publicKey);
 const browser=new Function('document','fetch','location','crypto',code+';return {api,importOwnerKey};')(doc,browserFetch,{origin:'https://idk.example'},crypto);
 const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';await browser.api('login','POST',{username:testPasswordConfig.username,password:testPassword});await browser.importOwnerKey({size:pem.length,text:async()=>pem});
 assert.equal((await browser.api('setup','POST',{})).account.role,'owner');const issued=await browser.api('licenses','POST',{token:await token()});assert.equal(issued.code.length,12);assert.equal((await browser.api('licenses?offset=0')).items.length,1);
 f.env.CERTIFICATE_KEY='test-only-encryption-key-'+ 'Z'.repeat(32);
 const credential={p12:Buffer.concat([Buffer.from([0x30]),Buffer.alloc(100000,7)]).toString('base64'),profile:Buffer.from('<?xml version="1.0"?><plist/>').toString('base64'),password:'private-test'};
 assert.deepEqual(await browser.api('licenses/'+issued.id+'/certificate','POST',credential),{ok:true});
 for(const req of sent.filter(x=>x.headers['X-IDK-Signature'])){assert.ok(req.headers['X-IDK-Signature']);assert.ok(!JSON.stringify(req).includes('PRIVATE KEY'));assert.equal(req.headers.Authorization,undefined);}
 const noDB=await f.worker.fetch(new Request('https://idk.example/api/admin/setup',{method:'POST'}),{});assert.equal((await noDB.json()).code,'DB_NOT_BOUND');f.db.close();
});


test('older Safari without Ed25519 or randomUUID imports the same PEM, authenticates and issues native-compatible tokens',async()=>{
 const f=fixture();let cookie='';const sent=[];
 const browserFetch=async(url,init)=>{sent.push(init);const response=await f.worker.fetch(new Request(url,{...init,headers:{...init.headers,...(cookie?{Cookie:cookie}:{})}}),f.env);if(response.headers.get('set-cookie'))cookie=response.headers.get('set-cookie').split(';')[0];return response;};
 const elements=new Map(),doc={getElementById(id){if(!elements.has(id))elements.set(id,{value:'',hidden:false,files:[],textContent:'',replaceChildren(){},append(){},children:[]});return elements.get(id);}};
 const limitedCrypto={getRandomValues:crypto.getRandomValues.bind(crypto),subtle:{digest:crypto.subtle.digest.bind(crypto.subtle),importKey:async()=>{throw new DOMException('The operation is not supported.','NotSupportedError');}}};
 const ed=new Function('module','self',ed25519JS+';return module.exports;')({exports:{}},{crypto:limitedCrypto});
 const code=javascript.replace('yMFlyNPeTyazhCFLXQQa6CV/tf5Zgj8R5RjfQbpzJgQ=',publicKey);
 const browser=new Function('document','fetch','location','crypto','nacl',code+';return {api,importOwnerKey,signOwner,forgetOwnerKey,getSecret:()=>ownerKey?.naclSecret};')(doc,browserFetch,{origin:'https://idk.example'},limitedCrypto,ed);
 const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
 await browser.api('login','POST',{username:testPasswordConfig.username,password:testPassword});await browser.importOwnerKey({size:pem.length,text:async()=>pem});assert.ok(doc.getElementById('keyState').textContent.includes('التوافق'));
 assert.equal((await browser.api('setup','POST',{})).account.role,'owner');
 const now=Math.floor(Date.now()/1000),body=base64url(new TextEncoder().encode(JSON.stringify({app:'app.taifplus.store',subject:'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE',name:'Safari compatibility',issued:now,expires:now+86400})));
 const proof=await browser.signOwner(new TextEncoder().encode(body));assert.ok(await crypto.subtle.verify('Ed25519',pair.publicKey,proof,new TextEncoder().encode(body)));
 assert.deepEqual(proof,new Uint8Array(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(body))));
 assert.equal((await browser.api('licenses','POST',{token:'TAIF1.'+body+'.'+base64url(proof)})).code.length,12);
 for(const req of sent.filter(x=>x.headers['X-IDK-Signature']))assert.match(req.headers['X-IDK-Nonce'],/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
 const secret=browser.getSecret();assert.ok(secret.some(x=>x));browser.forgetOwnerKey();assert.ok(secret.every(x=>x===0));await assert.rejects(()=>browser.signOwner(new Uint8Array(1)));
 const other=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']),wrongPem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',other.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';await assert.rejects(()=>browser.importOwnerKey({size:wrongPem.length,text:async()=>wrongPem}),/لا يطابق/);
 assert.ok(html.indexOf('src="/ed25519.js"')<html.indexOf('src="/panel.js"'));const asset=await f.worker.fetch(new Request('https://idk.example/ed25519.js'),f.env);assert.equal(asset.status,200);assert.equal(await asset.text(),ed25519JS);f.db.close();
});

test('vendored compatibility signer matches the published RFC8032 empty-message vector',()=>{
 const ed=new Function('module','self',ed25519JS+';return module.exports;')({exports:{}},{crypto});
 const key=ed.sign.keyPair.fromSeed(new Uint8Array(Buffer.from('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60','hex')));
 assert.equal(Buffer.from(key.publicKey).toString('hex'),'d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
 assert.equal(Buffer.from(ed.sign.detached(new Uint8Array(),key.secretKey)).toString('hex'),'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b');key.secretKey.fill(0);
});
