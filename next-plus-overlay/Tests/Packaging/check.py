"""Audit actual packaged deployment versions, including embedded native libraries."""
import io,pathlib,plistlib,struct,sys,zipfile

def versions(b):
 if b[:4] in [b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca']:
  endian='>' if b[:4]==b'\xca\xfe\xba\xbe' else '<'
  count=struct.unpack_from(endian+'I',b,4)[0]
  for i in range(count):
   _,_,offset,size,_=struct.unpack_from(endian+'IIIII',b,8+i*20)
   yield from versions(b[offset:offset+size])
 elif b[:4] in [b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe']:
  n=struct.unpack_from('<I',b,16)[0];o=32 if b[:4]==b'\xcf\xfa\xed\xfe' else 28
  for _ in range(n):
   c,s=struct.unpack_from('<II',b,o)
   if c==0x32:
    platform,minimum=struct.unpack_from('<II',b,o+8)
    if platform==2:yield minimum
   elif c==0x25:yield struct.unpack_from('<I',b,o+8)[0]
   o+=s

with zipfile.ZipFile(sys.argv[1]) as z:
 info=plistlib.loads(z.read('Payload/IDKPlus.app/Info.plist'))
 assert info['MinimumOSVersion']=='15.0',info['MinimumOSVersion']
 assert info['CFBundleIdentifier']=='app.idkplus.store'
 assert info['CFBundleDisplayName']=='idk plus'
 import json
 catalog=json.loads(z.read('Payload/IDKPlus.app/IDKPlusCatalog.json'))
 assert len(catalog['apps'])==20419
 assert 'Payload/IDKPlus.app/NextPlusIcon.png' not in z.namelist()
 main=versions(z.read('Payload/IDKPlus.app/IDKPlus'))
 assert list(main)==[15<<16],'Main executable must target iOS 15.0'
 native=0
 for name in z.namelist():
  if name.endswith('/'):continue
  b=z.read(name)
  for minimum in versions(b):
   assert minimum <= 15<<16, (name,hex(minimum))
   native+=1
 print('PASS: IPA minimum iOS 15.0, stable bundle ID, all '+str(native)+' native slices target iOS 15 or earlier')

