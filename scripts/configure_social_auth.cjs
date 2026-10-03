// Uses the local Firebase CLI session. Never prints OAuth secrets or tokens.
// Check: node scripts/configure_social_auth.cjs
// Refresh native config after enabling providers: node scripts/configure_social_auth.cjs --refresh-google
const fs=require('node:fs'),path=require('node:path');
const project='shop-pos-89294';
const androidApp='1:1010156115465:android:4b7c1f68c877f094a68ad8';
const iosApp='1:1010156115465:ios:eb6db61eb6305fdca68ad8';
const releaseSha1='382691a76cf170602024a8155104e8fa7fd9199f';
const refresh=process.argv.includes('--refresh-google');
(async()=>{
 const cliAuth=require(path.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib/auth.js'));
 const account=cliAuth.getGlobalDefaultAccount();
 if(!account)throw Error('Run firebase login first.');
 const token=await cliAuth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform']);
 async function api(url,method='GET',body){
  const r=await fetch(url,{method,headers:{Authorization:`Bearer ${token.access_token}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
  const data=await r.json();if(!r.ok&&r.status!==404)throw Error(`Configuration API returned HTTP ${r.status}`);return {status:r.status,data};
 }
 const base=`https://identitytoolkit.googleapis.com/admin/v2/projects/${project}`;
 const google=await api(base+'/defaultSupportedIdpConfigs/google.com');
 const apple=await api(base+'/defaultSupportedIdpConfigs/apple.com');
 const googleReady=google.data.enabled===true&&!!google.data.clientId;
 const appleReady=apple.data.enabled===true&&!!apple.data.clientId&&!!apple.data.appleSignInConfig?.codeFlowConfig?.keyId;
 console.log('Google provider:',googleReady?'configured':'not configured');
 console.log('Apple web/Android provider:',appleReady?'configured':'not configured');
 const management=`https://firebase.googleapis.com/v1beta1/projects/${project}`;
 if(process.argv.includes('--register-sha')){
  const existing=await api(`${management}/androidApps/${androidApp}/sha`);
  if(!(existing.data.certificates||[]).some(c=>c.certType==='SHA_1'&&c.shaHash.toLowerCase()===releaseSha1)){
   await api(`${management}/androidApps/${androidApp}/sha`,'POST',{certType:'SHA_1',shaHash:releaseSha1});
  }
  console.log('Release signing SHA-1 registered.');
 }
 if(refresh){
  if(!googleReady)throw Error('Enable Google in Firebase Authentication first, then rerun --refresh-google.');
  const android=await api(`${management}/androidApps/${androidApp}/config`);
  const ios=await api(`${management}/iosApps/${iosApp}/config`);
  const androidText=Buffer.from(android.data.configFileContents,'base64').toString('utf8');
  const iosText=Buffer.from(ios.data.configFileContents,'base64').toString('utf8');
  const parsed=JSON.parse(androidText);
  if(!parsed.client.some(c=>(c.oauth_client||[]).some(o=>o.client_type===3)))throw Error('Downloaded Android config has no web OAuth client yet.');
  const field=name=>iosText.match(new RegExp('<key>'+name+'</key>\\s*<string>([^<]+)</string>'))?.[1];
  const client=field('CLIENT_ID'),reversed=field('REVERSED_CLIENT_ID');
  if(!client||!reversed)throw Error('Downloaded iOS config has no OAuth client. Check the iOS app registration.');
  let info=fs.readFileSync('ios/Runner/Info.plist','utf8');
  // Preserve unrelated URL schemes: this block belongs exclusively to this helper.
  info=info.replace(/\s*<!-- Pokpok Google Sign-In START -->[\s\S]*?<!-- Pokpok Google Sign-In END -->/,'');
  if(/<key>GIDClientID<\/key>|<key>CFBundleURLTypes<\/key>/.test(info))throw Error('Existing Google/URL config needs manual merge; no files changed.');
  const block=`\n\t<!-- Pokpok Google Sign-In START -->\n\t<key>GIDClientID</key><string>${client}</string>\n\t<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>${reversed}</string></array></dict></array>\n\t<!-- Pokpok Google Sign-In END -->\n`;
  info=info.replace(/<dict>/,()=>'<dict>'+block);
  fs.writeFileSync('android/app/google-services.json',androidText);
  fs.writeFileSync('ios/Runner/GoogleService-Info.plist',iosText);
  fs.writeFileSync('ios/Runner/Info.plist',info);
  console.log('Native Google configuration refreshed. Rebuild both apps.');
 }
 if(!googleReady||!appleReady)process.exitCode=2;
})().catch(e=>{console.error(e.message);process.exitCode=1;});
