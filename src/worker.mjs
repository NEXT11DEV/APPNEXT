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
export const schema = [
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
async function authorized(request,env) {
 if(typeof env.ADMIN_KEY!=='string'||env.ADMIN_KEY.length<24)return false;
 const header=request.headers.get('authorization')??'';
 const provided=header.startsWith('Bearer ')?header.slice(7):'';
 if(provided.length>512)return false;
 const a=await digest(provided),b=await digest(env.ADMIN_KEY);let diff=0;
 for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
 return diff===0;
}
async function limit(request,env,scope,max,now) {
 const key=await digest(scope+':'+(request.headers.get('cf-connecting-ip')??'local'));
 const row=await env.DB.prepare('INSERT INTO attempts(key,window,hits) VALUES(?,?,1) ON CONFLICT(key,window) DO UPDATE SET hits=hits+1 RETURNING hits').bind(key,Math.floor(now/60)).first();
 if(row.hits>max)throw new HttpError(429,'محاولات كثيرة. انتظر دقيقة وأعد المحاولة.');
}
async function handle(request,env,publicKey) {
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
 if(!env.DB)return response({error:'اربط قاعدة D1 باسم DB أولًا.'},503);
 const now=Math.floor(Date.now()/1000);
 if(path.startsWith('/api/admin/')) {
  // Do not initialize anything until the admin secret is configured and verified.
  if(!await authorized(request,env))throw new HttpError(401,'مفتاح الإدارة غير صحيح أو لم يُضبط بعد.');
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
   let sealed;
   try {sealed=await sealCredential(await json(request,550000),env.CERTIFICATE_KEY??env.ADMIN_KEY,license.id+':'+license.subject);}catch(e){if(e instanceof HttpError)throw e;throw new HttpError(400,'تحقق من ملفات P12 وprovisioning وكلمة المرور وأحجامها.');}
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
export function createWorker(publicKey=PUBLIC_KEY) { return {
 async fetch(request,env){try{return await handle(request,env,publicKey);}catch(e){return response({error:e instanceof HttpError?e.message:'الخدمة غير جاهزة. افتح اللوحة ونفّذ تهيئة قاعدة البيانات.'},e instanceof HttpError?e.status:503);}},
 async scheduled(_event,env){if(env.DB)await env.DB.prepare('DELETE FROM attempts WHERE window < ?').bind(Math.floor(Date.now()/60000)-60).run();}
}; }
export default createWorker();
