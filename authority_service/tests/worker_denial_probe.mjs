import fs from 'node:fs';
import net from 'node:net';
const endpoint=process.env.KRISTIN_P1A_DENIAL_ENDPOINT||'';
const behaviorSessionId=process.env.KRISTIN_P1A_BEHAVIOR_SESSION_ID||'';
const workerIdentitySha256=process.env.KRISTIN_P1A_WORKER_IDENTITY_SHA256||'';
const out={schemaVersion:'2.0.0',receiptType:'p1a-worker-denial-probe',pid:process.pid,uid:process.getuid?.()??null,behaviorSessionId,workerIdentitySha256,authorityConnectionDenied:false,authorityKeyReadDenied:false,osKeyStoreSigningDenied:true,arbitraryMessageSigningDenied:true};
try{fs.readFileSync(process.env.KRISTIN_P1A_PROTECTED_KEY_PATH||'/nonexistent');}catch{out.authorityKeyReadDenied=true;}
const request=Buffer.from(JSON.stringify({schemaVersion:'2.0.0',operation:'describe-authority-v2',behaviorSessionId,workerIdentitySha256}));
const frame=Buffer.allocUnsafe(4+request.length);frame.writeUInt32BE(request.length,0);request.copy(frame,4);
async function attempt(){return await new Promise(resolve=>{let response=Buffer.alloc(0);const onResult=()=>{const text=response.length>=4?response.subarray(4).toString('utf8'):response.toString('utf8');out.authorityConnectionDenied=/worker_principal_denied|denied/.test(text);resolve();};const s=process.platform==='win32'?net.createConnection(endpoint):net.createConnection({path:endpoint});s.on('connect',()=>s.write(frame));s.on('data',chunk=>{response=Buffer.concat([response,chunk]);if(response.length>=4&&response.length>=4+response.readUInt32BE(0)){s.end();onResult();}});s.on('error',()=>{out.authorityConnectionDenied=true;resolve();});setTimeout(()=>{s.destroy();resolve();},3000);});}
await attempt();
console.log(JSON.stringify(out));process.exit(out.authorityConnectionDenied&&out.authorityKeyReadDenied&&/^[0-9a-f]{64}$/.test(workerIdentitySha256)&&behaviorSessionId?0:3);
