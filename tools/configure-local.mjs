import {execFileSync} from 'node:child_process';
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
const status=JSON.parse(execFileSync('npx',['supabase','status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','inherit']}));
const file='apps/api/.env';let lines=readFileSync(existsSync(file)?file:file+'.example','utf8').split('\n');
for(const [name,key] of Object.entries({SUPABASE_URL:'API_URL',SUPABASE_ANON_KEY:'ANON_KEY',SUPABASE_SERVICE_ROLE_KEY:'SERVICE_ROLE_KEY'})){
 if(!status[key])throw new Error('Missing local Supabase '+key);
 const value=name+'='+status[key];if(lines.some(l=>l.startsWith(name+'=')))lines=lines.map(l=>l.startsWith(name+'=')?value:l);else lines.push(value);
}
writeFileSync(file,lines.join('\n'));console.log('Local API configuration saved. Existing model keys preserved; no secrets printed.');
