import { html, css, javascript } from './panel.mjs';
import { siteHTML, siteCSS, siteJS } from './site.mjs';
import { brandPNG } from './brand.mjs';
import { apps } from './catalog-data.mjs';
import { catalogHTML, catalogCSS, catalogJS } from './catalog.mjs';
import { sealCredential, openCredential } from './credentials.mjs';
export const PUBLIC_KEY = 'HfxDxlZl9XEqrN86xR2A4kGyoop8k36ItekNw9WEhpA=';
const enc = new TextEncoder();
const catalogIndex = apps.map(a=>(a.name+' '+a.bundle).toLowerCase());
const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const accountSchema = `CREATE TABLE IF NOT EXISTS admin_accounts (id TEXT PRIMARY KEY CHECK(id='owner'), username TEXT NOT NULL, salt TEXT NOT NULL, hash TEXT NOT NULL, iterations INTEGER NOT NULL)`;
const sessionSchema = 'CREATE TABLE IF NOT EXISTS admin_sessions (token_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL)';
const nonceSchema = 'CREATE TABLE IF NOT EXISTS admin_nonces (nonce TEXT PRIMARY KEY, expires INTEGER NOT NULL)';
export const schema = [
 nonceSchema,
 sessionSchema,
 accountSchema,
 `CREATE TABLE IF NOT EXISTS licenses (id TEXT PRIMARY KEY, code_hash TEXT NOT NULL UNIQUE, suffix TEXT NOT NULL, subject TEXT NOT NULL, name TEXT NOT NULL, token TEXT NOT NULL, issued INTEGER NOT NULL, expires INTEGER NOT NULL, disabled INTEGER NOT NULL DEFAULT 0 CHECK(disabled IN (0,1)), first_used INTEGER, last_used INTEGER)`,
 `CREATE INDEX IF NOT EXISTS licenses_issued ON licenses(issued DESC, id)`,
 `CREATE TABLE IF NOT EXISTS credential_deliveries (license_id TEXT PRIMARY KEY REFERENCES licenses(id) ON DELETE CASCADE, iv TEXT NOT NULL, ciphertext TEXT NOT NULL, updated INTEGER NOT NULL)`,
 `CREATE TABLE IF NOT EXISTS attempts (key TEXT NOT NULL, window INTEGER NOT NULL, hits INTEGER NOT NULL, PRIMARY KEY(key,window))`
];
export const base64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const decode = text => Uint8Array.from(atob(text.replaceAll('-','+').replaceAll('_','/')), c=>c.charCodeAt(0));
export const digest = async text => base64url(await crypto.subtle.digest('SHA-256', enc.encode(text)));
export function newCode() {
 // Rejection sampling avoids modulo bias for the 31-character alphabet.
 let result='idk';
 while(result.length<12) for(const b of crypto.getRandomValues(new Uint8Array(16))) {
  if(b<256-256%alphabet.length) result+=alphabet[b%alphabet.length];
  if(result.length===12)break;
 }
 return result;
}
export function normalizeCode(input) {
 if(typeof input!=='string')return null;
 const code=input.trim().toUpperCase();
 return /^IDK[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{9}$/.test(code) ? 'idk'+code.slice(3) : null;
}
export async function verifyToken(token, now=Math.floor(Date.now()/1000), publicKey=PUBLIC_KEY) {
 try {
  if(typeof token!=='string'||token.length>4096)return null;
  const [prefix,body,sig,...extra]=token.split('.');
  if(prefix!=='IDK1'||extra.length||!body||!sig)return null;
  const key=await crypto.subtle.importKey('raw',decode(publicKey),'Ed25519',false,['verify']);
  if(!await crypto.subtle.verify('Ed25519',key,decode(sig),enc.encode(body)))return null;
  const p=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(decode(body)));
  if(p.app!=='app.idkplus.store'||!validSubject(p.subject)||typeof p.name!=='string'||!p.name.trim()||p.name.length>100||!Number.isSafeInteger(p.issued)||!Number.isSafeInteger(p.expires)||p.issued>now+300||p.expires<=now||p.expires<=p.issued||p.expires-p.issued>730*86400)return null;
  return p;
 }catch{return null;}
}
const validSubject = value => typeof value==='string'&&/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/.test(value);
const securityHeaders = {
 'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
 'Content-Security-Policy':"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' https:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
 'Strict-Transport-Security':'max-age=31536000'
};
const response = (data,status=200) => new Response(JSON.stringify(data), {status,headers:{...securityHeaders,'Content-Type':'application/json; charset=utf-8'}});
async function json(request,maxBytes=8192) {
 if(!request.headers.get('content-type')?.startsWith('application/json'))throw new HttpError(415,'JSON required');
 const reader=request.body?.getReader();if(!reader)throw new HttpError(400,'Missing body');
 let length=0,chunks=[];
 for(;;){const {value,done}=await reader.read();if(done)break;length+=value.byteLength;if(length>maxBytes){await reader.cancel();throw new HttpError(413,'Body too large');}chunks.push(value);}
 const data=new Uint8Array(length);let offset=0;for(const c of chunks){data.set(c,offset);offset+=c.length;}
 try {return JSON.parse(new TextDecoder().decode(data));}catch{throw new HttpError(400,'Invalid JSON');}
}
class HttpError extends Error { constructor(status,message){super(message);this.status=status;} }
export const adminMessage = (url,method,time,nonce,bodyHash) => ['IDK-ADMIN1',url.origin,method,url.pathname+url.search,time,nonce,bodyHash].join('\n');
async function ownerAuthorized(request,env,publicKey,now) {
 const time=request.headers.get('x-idk-time')??'',nonce=request.headers.get('x-idk-nonce')??'',signature=request.headers.get('x-idk-signature')??'';
 if(!/^\d{10}$/.test(time)||Math.abs(now-Number(time))>120||! /^[0-9a-f-]{36}$/.test(nonce)||! /^[A-Za-z0-9_-]{86}$/.test(signature))return false;
 // Bound body reads also protect certificate-upload authentication from unbounded input.
 const copy=request.clone(),reader=copy.body?.getReader();let length=0,chunks=[];
 if(reader)for(;;){const {value,done}=await reader.read();if(done)break;length+=value.byteLength;if(length>550000){reader.cancel().catch(()=>{});throw new HttpError(413,'Body too large');}chunks.push(value);}
 const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 const bodyHash=base64url(await crypto.subtle.digest('SHA-256',bytes));
 let valid=false;
 try {const key=await crypto.subtle.importKey('raw',decode(publicKey),'Ed25519',false,['verify']);valid=await crypto.subtle.verify('Ed25519',key,decode(signature),enc.encode(adminMessage(new URL(request.url),request.method,time,nonce,bodyHash)));}catch{return false;}
 if(!valid)return false;
 // Only a proven owner may initialize replay protection. Replays fail atomically.
 await env.DB.prepare(nonceSchema).run();
 try {await env.DB.prepare('INSERT INTO admin_nonces(nonce,expires) VALUES(?,?)').bind(nonce,now+300).run();}
 catch(e){if(String(e).includes('UNIQUE constraint failed'))return false;throw e;}
 return true;
}
function sessionCookie(request){const raw=request.headers.get('cookie')??'';const matches=raw.split(';').map(x=>x.trim()).filter(x=>x.startsWith('idk_admin='));if(matches.length!==1)return null;const value=matches[0].slice(10);return /^[A-Za-z0-9_-]{43}$/.test(value)?value:null;}
async function sessionAuthorized(request,env,now){const value=sessionCookie(request);if(!value)return false;try{return !!await env.DB.prepare('SELECT token_hash FROM admin_sessions WHERE token_hash=? AND expires>?').bind(await digest(value),now).first();}catch(e){if(String(e).includes('no such table'))return false;throw e;}}
async function authorized(request,env,publicKey,now){return await sessionAuthorized(request,env,now)&&await ownerAuthorized(request,env,publicKey,now);}
export async function verifyPassword(username,password,config){
 if(typeof username!=='string'||username.length>80||typeof password!=='string'||password.length>256)return false;
 const key=await crypto.subtle.importKey('raw',enc.encode(password),'PBKDF2',false,['deriveBits']);
 const derived=new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:decode(config.salt),iterations:config.iterations},key,256));
 const expected=decode(config.hash);let diff=derived.length^expected.length;for(let i=0;i<derived.length;i++)diff|=derived[i]^(expected[i]??0);
 return diff===0&&username===config.username;
}
async function readAccount(env){try{return await env.DB.prepare('SELECT username,salt,hash,iterations FROM admin_accounts WHERE id=?').bind('owner').first();}catch(e){if(String(e).includes('no such table'))return null;throw e;}}
async function startSession(env,now){
 await env.DB.prepare(sessionSchema).run();await env.DB.prepare('DELETE FROM admin_sessions WHERE expires<=?').bind(now).run();
 const session=base64url(crypto.getRandomValues(new Uint8Array(32)));
 await env.DB.prepare('INSERT INTO admin_sessions(token_hash,expires) VALUES(?,?)').bind(await digest(session),now+1800).run();
 const result=response({ok:true,expires:now+1800});result.headers.set('Set-Cookie',cookieHeader(session));return result;
}
const cookieHeader=(value,age=1800)=>'idk_admin='+value+'; Path=/api/admin/; HttpOnly; Secure; SameSite=Strict; Max-Age='+age;
async function limit(request,env,scope,max,now) {
 const key=await digest(scope+':'+(request.headers.get('cf-connecting-ip')??'local'));
 const row=await env.DB.prepare('INSERT INTO attempts(key,window,hits) VALUES(?,?,1) ON CONFLICT(key,window) DO UPDATE SET hits=hits+1 RETURNING hits').bind(key,Math.floor(now/60)).first();
 if(row.hits>max)throw new HttpError(429,'محاولات كثيرة. انتظر دقيقة وأعد المحاولة.');
}
async function handle(request,env,publicKey,passwordConfig) {
 const url=new URL(request.url),path=url.pathname;
 if(request.method==='GET'&&path==='/brand.png') {
  return new Response(decode(brandPNG),{headers:{...securityHeaders,'Content-Type':'image/png','Cache-Control':'public, max-age=86400'}});
 }
 const pages = {'/':[siteHTML,'text/html'],'/admin':[html,'text/html'],'/admin/':[html,'text/html'],
                '/apps':[catalogHTML,'text/html'],'/catalog.css':[catalogCSS,'text/css'],'/catalog.js':[catalogJS,'application/javascript'],
                '/site.css':[siteCSS,'text/css'],'/site.js':[siteJS,'application/javascript'],
                '/panel.css':[css,'text/css'],'/panel.js':[javascript,'application/javascript']};
 if(request.method==='GET'&&Object.hasOwn(pages,path)) {
  const [data,type]=pages[path];
  return new Response(data,{headers:{...securityHeaders,'Content-Type':type+'; charset=utf-8'}});
 }
 if(path==='/api/catalog'&&request.method==='GET') {
  const q=(url.searchParams.get('q')??'').trim().toLocaleLowerCase().slice(0,100);
  const offset=Number(url.searchParams.get('offset')??0);
  if(!Number.isSafeInteger(offset)||offset<0||offset>apps.length)throw new HttpError(400,'Invalid page');
  const matches=q?apps.filter((a,i)=>catalogIndex[i].includes(q)):apps;
  return response({items:matches.slice(offset,offset+30),total:matches.length,next:offset+30<matches.length?offset+30:null});
 }
 if(path==='/api/health'&&request.method==='GET')return response({service:'idk plus',version:1});
 if(!env.DB)return response({code:'DB_NOT_BOUND',error:'باقي خطوة إعداد واحدة: اربط قاعدة بيانات المشتركين بالموقع باسم DB. هذا مو خطأ بملف المالك.'},503);
 const now=Math.floor(Date.now()/1000);
 if(path==='/api/admin/login'&&request.method==='POST'){
  const origin=request.headers.get('origin');if(origin&&origin!==url.origin)throw new HttpError(403,'Origin not allowed');
  await env.DB.prepare(schema.find(sql=>sql.includes('CREATE TABLE IF NOT EXISTS attempts'))).run();
  await limit(request,env,'password-login',8,now);
  const {username,password}=await json(request,2048);
  const account=passwordConfig??await readAccount(env);
  if(!account)return response({code:'ACCOUNT_NOT_SETUP',error:'حساب المالك يحتاج تهيئة مرة واحدة. اختر ملف المالك لحفظ بيانات الدخول بقاعدة الموقع الخاصة.'},409);
  if(!await verifyPassword(username,password,account))throw new HttpError(401,'اسم المستخدم أو كلمة المرور غير صحيحة.');
  return startSession(env,now);
 }
 if(path==='/api/admin/account/setup'&&request.method==='POST'){
  const origin=request.headers.get('origin');if(origin&&origin!==url.origin)throw new HttpError(403,'Origin not allowed');
  if(!await ownerAuthorized(request,env,publicKey,now))throw new HttpError(401,'ملف المالك غير صحيح. لا يمكن إنشاء الحساب بدون إثبات الملكية.');
  if(passwordConfig||await readAccount(env))throw new HttpError(409,'حساب المالك موجود بالفعل؛ استخدم اسم المستخدم وكلمة المرور للدخول.');
  const {username,password}=await json(request,2048);
  if(typeof username!=='string'||!/^[A-Za-z0-9_.-]{3,80}$/.test(username)||typeof password!=='string'||password.length<8||password.length>256)throw new HttpError(400,'اسم المستخدم من 3 إلى 80 حرفًا إنجليزيًا أو رقمًا، وكلمة المرور 8 خانات على الأقل.');
  const salt=crypto.getRandomValues(new Uint8Array(16)),iterations=100000;
  const key=await crypto.subtle.importKey('raw',enc.encode(password),'PBKDF2',false,['deriveBits']);
  const hash=base64url(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt,iterations},key,256));
  await env.DB.prepare(accountSchema).run();
  const added=await env.DB.prepare('INSERT INTO admin_accounts(id,username,salt,hash,iterations) VALUES(?,?,?,?,?) ON CONFLICT(id) DO NOTHING RETURNING id').bind('owner',username,base64url(salt),hash,iterations).first();
  if(!added)throw new HttpError(409,'حساب المالك موجود بالفعل.');
  return startSession(env,now);
 }
 if(path==='/api/admin/logout'&&request.method==='POST'){
  const origin=request.headers.get('origin');if(origin&&origin!==url.origin)throw new HttpError(403,'Origin not allowed');
  const session=sessionCookie(request);if(session&&await sessionAuthorized(request,env,now))await env.DB.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(await digest(session)).run();
  const result=response({ok:true});result.headers.set('Set-Cookie',cookieHeader('',0));return result;
 }
 if(path.startsWith('/api/admin/')) {
  // Require both the password session and the owner PEM proof on every protected request.
  if(!await authorized(request,env,publicKey,now))throw new HttpError(401,'انتهت جلسة الدخول أو تعذر التحقق من ملف المالك. ادخل باسمك وكلمة المرور ثم اختر ملف PEM الصحيح.');
  const origin=request.headers.get('origin');
  if(origin&&origin!==url.origin)throw new HttpError(403,'Origin not allowed');
  if(path==='/api/admin/setup'&&request.method==='POST') {
   await env.DB.batch(schema.map(sql=>env.DB.prepare(sql)));return response({ok:true});
  }
  await limit(request,env,'admin',120,now);
  if(path==='/api/admin/licenses'&&request.method==='GET') {
   const offset=Number(url.searchParams.get('offset')??0);
   if(!Number.isSafeInteger(offset)||offset<0||offset>1000000)throw new HttpError(400,'Invalid offset');
   const page=await env.DB.prepare('SELECT id,suffix,subject,name,issued,expires,disabled,first_used,last_used,EXISTS(SELECT 1 FROM credential_deliveries d WHERE d.license_id=licenses.id) AS has_certificate FROM licenses ORDER BY issued DESC,id LIMIT 101 OFFSET ?').bind(offset).all();
   return response({items:page.results.slice(0,100),next:page.results.length>100?offset+100:null});
  }
  if(path==='/api/admin/licenses'&&request.method==='POST') {
   const {token}=await json(request);const p=await verifyToken(token,now,publicKey);
   if(!p)throw new HttpError(400,'التفعيل الموقّع غير صحيح أو منتهي الصلاحية.');
   for(let attempt=0;attempt<4;attempt++) {
    const code=newCode(),hash=await digest(code),id=crypto.randomUUID();
    try {
     await env.DB.prepare('INSERT INTO licenses(id,code_hash,suffix,subject,name,token,issued,expires) VALUES(?,?,?,?,?,?,?,?)').bind(id,hash,code.slice(-4),p.subject,p.name,token,now,p.expires).run();
     return response({code,id,subject:p.subject,name:p.name,expires:p.expires},201);
    }catch(e){if(!String(e).includes('UNIQUE constraint failed'))throw e;}
   }
   throw new HttpError(503,'أعد توليد الكود.');
  }
  const deliveryMatch=path.match(/^\/api\/admin\/licenses\/([0-9a-f-]{36})\/certificate$/);
  if(deliveryMatch&&request.method==='POST') {
   const license=await env.DB.prepare('SELECT id,subject,expires FROM licenses WHERE id=?').bind(deliveryMatch[1]).first();
   if(!license||license.expires<=now)throw new HttpError(404,'الاشتراك غير موجود أو منتهي.');
   const encryptionSecret=env.CERTIFICATE_KEY??env.ADMIN_KEY;
   if(typeof encryptionSecret!=='string'||encryptionSecret.length<24)throw new HttpError(503,'إضافة الشهادات تحتاج إعداد مفتاح تشفير مرة واحدة: أضف Secret باسم CERTIFICATE_KEY في Cloudflare، بقيمة عشوائية لا تقل عن 24 خانة. إصدار الأكواد يعمل بدونه.');
   let sealed;
   try {sealed=await sealCredential(await json(request,550000),encryptionSecret,license.id+':'+license.subject);}catch(e){if(e instanceof HttpError)throw e;throw new HttpError(400,'تحقق من ملفات P12 وprovisioning وكلمة المرور وأحجامها.');}
   await env.DB.prepare('INSERT INTO credential_deliveries(license_id,iv,ciphertext,updated) VALUES(?,?,?,?) ON CONFLICT(license_id) DO UPDATE SET iv=excluded.iv,ciphertext=excluded.ciphertext,updated=excluded.updated').bind(license.id,sealed.iv,sealed.ciphertext,now).run();
   return response({ok:true});
  }
  const match=path.match(/^\/api\/admin\/licenses\/([0-9a-f-]{36})$/);
  if(match&&request.method==='PATCH') {
   const {disabled}=await json(request);if(typeof disabled!=='boolean')throw new HttpError(400,'Invalid state');
   const result=await env.DB.prepare('UPDATE licenses SET disabled=? WHERE id=? RETURNING id').bind(disabled?1:0,match[1]).first();
   if(!result)throw new HttpError(404,'الكود غير موجود.');return response({ok:true});
  }
 }
 if(path==='/api/redeem'&&request.method==='POST') {
  await limit(request,env,'redeem',15,now);
  const body=await json(request),code=normalizeCode(body.code),subject=body.subject;
  if(!code||!validSubject(subject))throw new HttpError(403,'الكود غير صالح لهذا الجهاز أو منتهي.');
  const row=await env.DB.prepare('SELECT id,token FROM licenses WHERE code_hash=? AND subject=? AND disabled=0 AND expires>?').bind(await digest(code),subject,now).first();
  if(!row||!await verifyToken(row.token,now,publicKey))throw new HttpError(403,'الكود غير صالح لهذا الجهاز أو منتهي.');
  // Repeat requests from the bound installation remain idempotent.
  const changed=await env.DB.prepare('UPDATE licenses SET first_used=COALESCE(first_used,?),last_used=? WHERE id=? AND disabled=0 AND expires>? RETURNING id').bind(now,now,row.id,now).first();
  if(!changed)throw new HttpError(403,'الكود غير صالح لهذا الجهاز أو منتهي.');
  let delivery;
  try {delivery=await env.DB.prepare('SELECT iv,ciphertext FROM credential_deliveries WHERE license_id=?').bind(row.id).first();}
  catch(e){if(!String(e).includes('no such table'))throw e;}
  let credentials;
  if(delivery) {
   try {credentials=await openCredential(delivery,env.CERTIFICATE_KEY??env.ADMIN_KEY,row.id+':'+subject);}
   catch {throw new HttpError(503,'تعذر فتح حزمة الشهادة. اطلب من المالك إعادة ربطها.');}
  }
  return response({token:row.token,...(credentials?{credentials}:{})});
 }
 return response({error:'Not found'},404);
}
export function createWorker(publicKey=PUBLIC_KEY,passwordConfig) { return {
 async fetch(request,env){try{return await handle(request,env,publicKey,passwordConfig);}catch(e){return response({error:e instanceof HttpError?e.message:'الخدمة غير جاهزة. افتح اللوحة ونفّذ تهيئة قاعدة البيانات.'},e instanceof HttpError?e.status:503);}},
 async scheduled(_event,env){if(env.DB){await env.DB.prepare('DELETE FROM attempts WHERE window < ?').bind(Math.floor(Date.now()/60000)-60).run();await env.DB.prepare(nonceSchema).run();await env.DB.prepare('DELETE FROM admin_nonces WHERE expires < ?').bind(Math.floor(Date.now()/1000)).run();await env.DB.prepare(sessionSchema).run();await env.DB.prepare('DELETE FROM admin_sessions WHERE expires<=?').bind(Math.floor(Date.now()/1000)).run();}}
}; }
export default createWorker();
