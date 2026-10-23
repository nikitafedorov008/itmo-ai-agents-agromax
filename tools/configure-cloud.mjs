import {mkdirSync,writeFileSync} from 'node:fs';
const url=new URL(process.argv[2] || '');
if(url.protocol!=='https:' || url.username || url.password || url.search || url.hash || url.pathname!=='/')
  throw new Error('Expected a public HTTPS origin without credentials, path, or query');
const origin=url.origin;
mkdirSync('apps/mobile/config',{recursive:true});
writeFileSync('apps/mobile/config/cloud.json',JSON.stringify({API_BASE_URL:origin},null,2)+'\n');
writeFileSync('apps/mobile/config/local.json',JSON.stringify({API_BASE_URL:'http://localhost:8787'},null,2)+'\n');
writeFileSync('apps/mobile/lib/generated/deployment.dart',`// Public endpoint, no credentials. Override API_BASE_URL for local development.\nconst defaultApiOrigin = '${origin}';\n`);
console.log('Mobile default and cloud build configuration updated:',origin);
