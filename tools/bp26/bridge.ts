// Loopback-only harness service. Signs fixture HTTP calls and uses the real API.
import {Engine,emptyState,type Identity} from '../../server/src/engine';
import {API} from '../../server/src/api';import {Verifier,signedText} from '../../server/src/auth';
let now=1800000060000,e:Engine,api:API,sequence=0;
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']) as CryptoKeyPair;
function reset(){e=new Engine(emptyState(),{now:()=>now,random:()=>0,welcomeAmount:25});const v=new Verifier(e.state,{now:()=>now});v.keys.set('fixture',pair.publicKey);api=new API(e,{load:()=>e.state,save:()=>{}},v);}
reset();
Bun.serve({hostname:'127.0.0.1',port:Number(process.env.HARNESS_PORT??8799),async fetch(req){
 const b=await req.json();
 if(b.control==='reset'){now=1800000060000;reset();return Response.json({ok:true});}
 if(b.control==='advance'){now+=b.ms;e.tick();return Response.json({ok:true});}
 if(b.control==='inspect')return Response.json(e.state);
 if(b.control==='config'){Object.assign(e.config,b.config);return Response.json({ok:true});}
 const id=b.badge,body=JSON.stringify(b.body??{}),headers:Record<string,string>={'x-badge-app':'range-lazarus','x-badge-id':id,'x-badge-user':'user_'+id,'x-badge-time':String(now),'x-badge-request':`fixture_${++sequence}`,'x-badge-key':'fixture'};
 const unsigned=new Request(b.url,{method:'POST',headers,body});
 headers['x-badge-signature']=Buffer.from(await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(await signedText(unsigned,body)))).toString('base64');
 const response=await api.handle(new Request(unsigned,{headers}));
 return Response.json({status:response.status,body:await response.json()});
}});
console.log('BP26 harness ready');
