"""Verify executable hashes and CMS mathematics without asserting Apple trust.
Disposable test certificates are deliberately not Apple-issued identities.
"""
import hashlib,pathlib,struct,subprocess

def verify(app,openssl,scratch):
 binary=(app/'Smoke').read_bytes()
 assert struct.unpack_from('<I',binary)[0]==0xfeedfacf
 commands=struct.unpack_from('<I',binary,16)[0];pos=32;signature=None
 for _ in range(commands):
  command,length=struct.unpack_from('<II',binary,pos)
  if command==0x1d:
   offset,size=struct.unpack_from('<II',binary,pos+8);signature=binary[offset:offset+size]
  pos+=length
 assert signature is not None
 magic,length,count=struct.unpack_from('>III',signature)
 assert magic==0xfade0cc0
 slots={}
 for i in range(count):
  kind,offset=struct.unpack_from('>II',signature,12+i*8)
  size=struct.unpack_from('>I',signature,offset+4)[0];slots[kind]=signature[offset:offset+size]
 cd=slots[0];assert struct.unpack_from('>I',cd)[0]==0xfade0c02
 hash_offset=struct.unpack_from('>I',cd,16)[0]
 special,pages,limit=struct.unpack_from('>III',cd,24)
 hash_size,hash_type,platform,page_exp=struct.unpack_from('BBBB',cd,36)
 digest={1:hashlib.sha1,2:hashlib.sha256,3:hashlib.sha256,4:hashlib.sha384}[hash_type]
 for i in range(pages):
  page=binary[i*(1<<page_exp):min((i+1)*(1<<page_exp),limit)]
  assert digest(page).digest()[:hash_size]==cd[hash_offset+i*hash_size:hash_offset+(i+1)*hash_size], 'Executable page hash mismatch'
 for slot,path in [(1,app/'Info.plist'),(3,app/'_CodeSignature/CodeResources')]:
  assert special>=slot
  assert digest(path.read_bytes()).digest()[:hash_size]==cd[hash_offset-slot*hash_size:hash_offset-(slot-1)*hash_size], 'Resource seal mismatch'
 (scratch/'cd.bin').write_bytes(cd);(scratch/'cms.der').write_bytes(slots[0x10000][8:])
 subprocess.run([str(openssl),'cms','-verify','-inform','DER','-in',str(scratch/'cms.der'),'-content',str(scratch/'cd.bin'),'-binary','-noverify','-out',str(scratch/'verified.bin')],check=True)
 assert (scratch/'verified.bin').read_bytes()==cd
 print('PASS: executable page hashes, Info.plist/resource seal, and cryptographic CMS signature (Apple trust not asserted)')
