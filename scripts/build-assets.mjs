import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const parts=Array.from({length:4},(_,i)=>readFileSync(new URL('../brand/icon-'+String(i).padStart(2,'0')+'.part',import.meta.url)));
const png=Buffer.concat(parts);
if(createHash('sha256').update(png).digest('hex')!=='23992e52399b1b245419b8959844718513d407281e2bd9b115800ed64c6c6b9f')throw Error('Brand asset checksum mismatch');
writeFileSync(new URL('../src/brand.mjs',import.meta.url),'export const brandPNG = '+JSON.stringify(png.toString('base64'))+';\n');
