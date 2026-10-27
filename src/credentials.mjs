const encoder=new TextEncoder();
const b64=b=>{const a=new Uint8Array(b);let s='';for(let i=0;i<a.length;i+=16384)s+=String.fromCharCode(...a.subarray(i,i+16384));return btoa(s);};
function unb64(s,max){if(typeof s!=='string'||s.length>Math.ceil(max/3)*4+8||!/^[A-Za-z0-9+/]*={0,2}$/.test(s))throw Error('Invalid file');const b=Uint8Array.from(atob(s),c=>c.charCodeAt(0));if(b.length<1||b.length>max)throw Error('Invalid size');return b;}
export function validateCredential(value){
 if(!value||typeof value.password!=='string'||new TextEncoder().encode(value.password).length>512)throw Error('Invalid password');
 const p12=unb64(value.p12,131072),profile=unb64(value.profile,262144);
 // Complete validity and team checks happen on the subscriber's device, using the signing engine.
 if(p12[0]!==0x30)throw Error('P12 must be a DER PKCS12 file');
 if(profile[0]!==0x30&&!new TextDecoder().decode(profile.slice(0,100)).includes('<?xml'))throw Error('Invalid provisioning file');
 return {p12:value.p12,profile:value.profile,password:value.password};
}
async function keyFor(secret){
 if(typeof secret!=='string'||secret.length<24)throw Error('Missing encryption secret');
 const raw=await crypto.subtle.digest('SHA-256',encoder.encode('taif-plus.delivery.v1:'+secret));
 return crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt','decrypt']);
}
export async function sealCredential(value,secret,context){
 const safe=validateCredential(value),iv=crypto.getRandomValues(new Uint8Array(12));
 const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode(context)},await keyFor(secret),encoder.encode(JSON.stringify(safe)));
 return {iv:b64(iv),ciphertext:b64(ciphertext)};
}
export async function openCredential(row,secret,context){
 const clear=await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(row.iv,12),additionalData:encoder.encode(context)},await keyFor(secret),unb64(row.ciphertext,600000));
 return validateCredential(JSON.parse(new TextDecoder().decode(clear)));
}
