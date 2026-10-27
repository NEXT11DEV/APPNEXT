export const testPassword='disposable-test-password-only';
const salt=crypto.getRandomValues(new Uint8Array(16));
const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(testPassword),'PBKDF2',false,['deriveBits']);
export const testPasswordConfig={username:'test-owner',iterations:1000,salt:Buffer.from(salt).toString('base64'),hash:Buffer.from(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt,iterations:1000},key,256)).toString('base64')};
