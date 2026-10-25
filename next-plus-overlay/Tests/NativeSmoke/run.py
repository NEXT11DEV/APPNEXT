"""Exercises the actual C++ bridge using disposable non-Apple test identities.
This validates archive/signature generation, not acceptance by a physical iPhone.
"""
import datetime, os, pathlib, plistlib, shutil, struct, subprocess, tempfile, zipfile
from verify import verify as verify_signature
root=pathlib.Path.cwd()
def run(args, **kwargs): return subprocess.run([str(x) for x in args], check=True, **kwargs)
ssl=pathlib.Path(subprocess.check_output(['brew','--prefix','openssl@3'],text=True).strip())
openssl=ssl/'bin/openssl'
with tempfile.TemporaryDirectory(prefix='next-smoke-') as scratch:
 d=pathlib.Path(scratch);objs=[]
 for source in (root/'vendor/zsign/third-party/minizip').glob('*.c'):
  if source.name not in ['ioapi.c','unzip.c','zip.c']:continue
  obj=d/(source.stem+'.o');run(['clang','-c',source,'-o',obj]);objs.append(obj)
 sources=list((root/'vendor/zsign').glob('*.cpp'))+list((root/'vendor/zsign/common').glob('*.cpp'))
 sources=[s for s in sources if s.name!='zsign.cpp']
 driver=d/'bridge-smoke'
 run(['clang++','-O2','-std=c++11','-Wno-deprecated-declarations','-DZSIGN_VERSION="test"',
      '-I'+str(root/'Bridge'),'-I'+str(root/'vendor/zsign'),'-I'+str(root/'vendor/zsign/common'),
      '-I'+str(ssl/'include'), root/'Bridge/zsign_wrapper.cpp',root/'Tests/NativeSmoke/driver.cpp',*sources,*objs,
      '-L'+str(ssl/'lib'),'-lssl','-lcrypto','-lz','-framework','CoreFoundation','-o',driver])
 def cmd(*args):run([openssl,*args],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 cmd('req','-x509','-newkey','rsa:2048','-nodes','-keyout',d/'ca.key','-out',d/'ca.pem','-days','2','-subj','/CN=NEXT Disposable Test CA')
 cmd('req','-newkey','rsa:2048','-nodes','-keyout',d/'leaf.key','-out',d/'leaf.csr','-subj','/CN=NEXT Disposable Test/OU=NEXTTEST01/O=Test')
 cmd('x509','-req','-in',d/'leaf.csr','-CA',d/'ca.pem','-CAkey',d/'ca.key','-CAcreateserial','-out',d/'leaf.pem','-days','1')
 cmd('x509','-in',d/'leaf.pem','-outform','DER','-out',d/'leaf.der')
 for name,password in [('protected','test-only'),('empty','')]:
  cmd('pkcs12','-export','-inkey',d/'leaf.key','-in',d/'leaf.pem','-certfile',d/'ca.pem','-out',d/(name+'.p12'),'-passout','pass:'+password)
 now=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
 profile=dict(Name='NEXT Test Fixture',UUID='00000000-0000-0000-0000-000000000001',TeamIdentifier=['NEXTTEST01'],ApplicationIdentifierPrefix=['NEXTTEST01'],DeveloperCertificates=[(d/'leaf.der').read_bytes()],CreationDate=now,ExpirationDate=now+datetime.timedelta(days=1),ProvisionsAllDevices=True,Entitlements={'application-identifier':'NEXTTEST01.*','com.apple.developer.team-identifier':'NEXTTEST01','get-task-allow':False,'keychain-access-groups':['NEXTTEST01.*']})
 (d/'profile.plist').write_bytes(plistlib.dumps(profile))
 cmd('cms','-sign','-binary','-nodetach','-in',d/'profile.plist','-signer',d/'leaf.pem','-inkey',d/'leaf.key','-outform','DER','-out',d/'test.mobileprovision')
 app=d/'Payload/Smoke.app';app.mkdir(parents=True)
 (app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier='app.idkplus.smoke',CFBundleExecutable='Smoke',CFBundleName='Smoke',CFBundleVersion='1',CFBundleShortVersionString='1.0',CFBundlePackageType='APPL',MinimumOSVersion='15.0')))
 (d/'main.c').write_text('int main(void) { return 0; }\n')
 sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
 run(['xcrun','clang','-target','arm64-apple-ios15.0','-isysroot',sdk,d/'main.c','-o',app/'Smoke'])
 (app/'resource.txt').write_text('NEXT signing test resource')
 with zipfile.ZipFile(d/'input.ipa','w',zipfile.ZIP_DEFLATED) as z:
  for p in (d/'Payload').rglob('*'):
   if p.is_file():z.write(p,p.relative_to(d))
 def sign(p12,password,out,source='input.ipa'):
  work=d/('work-'+out);work.mkdir()
  return subprocess.run([str(driver),str(d/source),str(d/p12),password,str(d/'test.mobileprovision'),str(d/out),str(work)])
 for name,password in [('protected','test-only'),('empty','')]:
  output=name+'.ipa';assert sign(name+'.p12',password,output).returncode==0
  with zipfile.ZipFile(d/output) as z:
   assert z.read('Payload/Smoke.app/embedded.mobileprovision')==(d/'test.mobileprovision').read_bytes()
   resources=plistlib.loads(z.read('Payload/Smoke.app/_CodeSignature/CodeResources'))
   assert 'resource.txt' in resources.get('files2',resources.get('files',{}))
   assert plistlib.loads(z.read('Payload/Smoke.app/Info.plist'))['CFBundleIdentifier']=='app.idkplus.smoke'
   signed=z.read('Payload/Smoke.app/Smoke');assert b'\xfa\xde\x0c\xc0' in signed
   verify=d/('verify-'+name);z.extractall(verify)
  verify_signature(verify/'Payload/Smoke.app',openssl,d)
  print('PASS native bridge: '+name+' password IPA signing')
 # Regression: same explicit profile, two distinct app identifiers. The signer
 # must retain each app's identifier and the original profile/entitlements.
 # This mirrors the signed structure observed in the user-provided Zsign IPA;
 # it makes no assertion about Apple's acceptance on a physical device.
 exact_id='NEXTTEST01.app.horizon9614.emerald5763'
 profile['Entitlements']['application-identifier']=exact_id
 (d/'profile.plist').write_bytes(plistlib.dumps(profile))
 cmd('cms','-sign','-binary','-nodetach','-in',d/'profile.plist','-signer',d/'leaf.pem','-inkey',d/'leaf.key','-outform','DER','-out',d/'test.mobileprovision')
 original_profile=(d/'test.mobileprovision').read_bytes()
 identifiers=['com.gitswift.SwiftServer','com.suversal.wrappin']
 outputs=[]
 for index,bundle in enumerate(identifiers):
  info=plistlib.loads((app/'Info.plist').read_bytes());info['CFBundleIdentifier']=bundle
  (app/'Info.plist').write_bytes(plistlib.dumps(info))
  source='explicit-input-'+str(index)+'.ipa'
  with zipfile.ZipFile(d/source,'w',zipfile.ZIP_DEFLATED) as z:
   for file in (d/'Payload').rglob('*'):
    if file.is_file():z.write(file,file.relative_to(d))
  original_input=(d/source).read_bytes()
  output='explicit-output-'+str(index)+'.ipa'
  assert sign('protected.p12','test-only',output,source).returncode==0
  assert (d/source).read_bytes()==original_input
  with zipfile.ZipFile(d/output) as z:
   signed_id=plistlib.loads(z.read('Payload/Smoke.app/Info.plist'))['CFBundleIdentifier']
   assert signed_id==bundle
   assert z.read('Payload/Smoke.app/embedded.mobileprovision')==original_profile
   extracted=d/('explicit-verify-'+str(index));z.extractall(extracted)
  entitlements=verify_signature(extracted/'Payload/Smoke.app',openssl,d)
  assert entitlements['application-identifier']==exact_id
  assert entitlements['com.apple.developer.team-identifier']=='NEXTTEST01'
  outputs.append(signed_id)
 assert len(set(outputs))==2
 print('PASS native compatibility: two distinct bundle IDs, same explicit profile; profile bytes and signing application-identifier preserved')
 assert sign('protected.p12','wrong','wrong.ipa').returncode!=0
 (d/'invalid.ipa').write_text('not an IPA')
 assert sign('empty.p12','','invalid-output.ipa','invalid.ipa').returncode!=0
 print('PASS native bridge: rejects wrong password and invalid archive')


 # Prepared pipeline: verify the reused extraction and unchanged input, then
 # reject stale archives, escaped directories, replay, and encrypted fixtures.
 for name,password in [('protected','test-only'),('empty','')]:
  work=d/('prepared-work-'+name);work.mkdir()
  output=d/('prepared-'+name+'.ipa')
  original=(d/'input.ipa').read_bytes()
  run([driver,d/'input.ipa',d/(name+'.p12'),password,d/'test.mobileprovision',output,work,'prepared'])
  assert (d/'input.ipa').read_bytes()==original
  assert not (work/'idk_prepared').exists()
  assert not (work/'idk_prepared.ready').exists()
  with zipfile.ZipFile(output) as z:
   assert z.read('Payload/Smoke.app/prepared-proof.txt')==b'prepared tree was reused'
   assert not any('idk_prepared.ready' in n for n in z.namelist())
   extracted=d/('prepared-verify-'+name);z.extractall(extracted)
  verify_signature(extracted/'Payload/Smoke.app',openssl,d)
  print('PASS prepared native pipeline: one extraction reused, protected/empty passwords, CMS/resources valid, original input unchanged, replay rejected')
 for mode in ['stale','outside']:
  source=d/(mode+'-input.ipa');source.write_bytes((d/'input.ipa').read_bytes())
  work=d/('reject-'+mode);work.mkdir();output=d/(mode+'-output.ipa')
  result=subprocess.run([str(driver),str(source),str(d/'protected.p12'),'test-only',str(d/'test.mobileprovision'),str(output),str(work),mode])
  assert result.returncode!=0 and not output.exists()
  print('PASS prepared native pipeline: rejects '+mode+' extraction')
 binary=bytearray((app/'Smoke').read_bytes())
 ncmds,sizeofcmds=struct.unpack_from('<II',binary,16)
 offset=32+sizeofcmds
 assert binary[offset:offset+24]==bytes(24),'Expected Mach-O header padding'
 binary[offset:offset+24]=struct.pack('<IIIIII',0x2c,24,0,0,1,0)
 struct.pack_into('<II',binary,16,ncmds+1,sizeofcmds+24)
 (app/'Smoke').write_bytes(binary)
 source=d/'encrypted-input.ipa'
 with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED) as z:
  for file in (d/'Payload').rglob('*'):
   if file.is_file():z.write(file,file.relative_to(d))
 work=d/'encrypted-work';work.mkdir();output=d/'encrypted-output.ipa'
 result=subprocess.run([str(driver),str(source),str(d/'protected.p12'),'test-only',str(d/'test.mobileprovision'),str(output),str(work),'encrypted'])
 assert result.returncode!=0 and not output.exists() and not (work/'idk_prepared.ready').exists()
 print('PASS prepared native pipeline: encrypted Mach-O cannot receive a prepared marker or reach signing')
